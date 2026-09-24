//! Linux UAPI decoding uses explicit offsets, never Rust struct layout.
use serde::Serialize;
use std::{
    io, mem,
    net::{IpAddr, Ipv4Addr, Ipv6Addr},
    os::fd::{AsRawFd, FromRawFd, OwnedFd},
    time::Instant,
};

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Endpoint {
    pub address: IpAddr,
    pub port: u16,
}
#[derive(Clone, Debug)]
pub struct Socket {
    pub family: u8,
    pub local: Endpoint,
    pub remote: Endpoint,
    pub state: u8,
    pub inode: u32,
    pub uid: u32,
    pub cookie: [u32; 2],
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Failure {
    Denied,
    Timeout,
    Unavailable,
    Interrupted,
    Malformed,
    Io,
}
impl Failure {
    fn os(error: io::Error) -> Self {
        match error.raw_os_error() {
            Some(libc::EPERM | libc::EACCES) => Self::Denied,
            Some(libc::EAFNOSUPPORT | libc::EPROTONOSUPPORT | libc::ENOENT) => Self::Unavailable,
            Some(libc::ENOBUFS) => Self::Interrupted,
            _ => Self::Io,
        }
    }
}
fn u16n(b: &[u8]) -> u16 {
    u16::from_ne_bytes(b[..2].try_into().unwrap())
}
fn u32n(b: &[u8]) -> u32 {
    u32::from_ne_bytes(b[..4].try_into().unwrap())
}

#[derive(Default)]
pub struct Dump {
    pub sockets: Vec<Socket>,
    pub omitted: usize,
}

/// Parse one kernel datagram. No partially parsed family is published on error.
pub fn parse(
    data: &[u8],
    family: u8,
    sequence: u32,
    dump: &mut Dump,
    limit: usize,
) -> Result<bool, Failure> {
    let mut offset = 0;
    while offset < data.len() {
        if data.len() - offset < 16 {
            return Err(Failure::Malformed);
        }
        let header = &data[offset..offset + 16];
        let len = u32n(header) as usize;
        if len < 16 || len > data.len() - offset || u32n(&header[8..]) != sequence {
            return Err(Failure::Malformed);
        }
        if u16n(&header[6..]) & 0x10 != 0 {
            return Err(Failure::Interrupted);
        }
        let body = &data[offset + 16..offset + len];
        match u16n(&header[4..]) {
            1 => {} // NLMSG_NOOP
            2 => {
                if body.len() < 4 {
                    return Err(Failure::Malformed);
                }
                let error = i32::from_ne_bytes(body[..4].try_into().unwrap());
                if error != 0 {
                    return Err(Failure::os(io::Error::from_raw_os_error(
                        error.checked_neg().ok_or(Failure::Malformed)?,
                    )));
                }
            }
            3 => {
                if !body.is_empty() && (body.len() < 4 || u32n(body) != 0) {
                    return Err(Failure::Interrupted);
                }
                if offset + ((len + 3) & !3) < data.len() {
                    return Err(Failure::Malformed);
                }
                return Ok(true);
            }
            4 => return Err(Failure::Interrupted), // NLMSG_OVERRUN
            20 => {
                if body.len() < 72 || body[0] != family || !(1..=12).contains(&body[1]) {
                    return Err(Failure::Malformed);
                }
                // Exclude listeners and unconnected/closed TCP sockets.
                if body[1] != 10 && body[1] != 7 {
                    let address = |bytes: &[u8]| -> Result<IpAddr, Failure> {
                        match family {
                            2 => Ok(
                                Ipv4Addr::from(<[u8; 4]>::try_from(&bytes[..4]).unwrap()).into()
                            ),
                            10 => {
                                Ok(Ipv6Addr::from(<[u8; 16]>::try_from(&bytes[..16]).unwrap())
                                    .into())
                            }
                            _ => Err(Failure::Malformed),
                        }
                    };
                    let socket = Socket {
                        family,
                        local: Endpoint {
                            address: address(&body[8..24])?,
                            port: u16::from_be_bytes(body[4..6].try_into().unwrap()),
                        },
                        remote: Endpoint {
                            address: address(&body[24..40])?,
                            port: u16::from_be_bytes(body[6..8].try_into().unwrap()),
                        },
                        state: body[1],
                        cookie: [u32n(&body[44..]), u32n(&body[48..])],
                        uid: u32n(&body[64..]),
                        inode: u32n(&body[68..]),
                    };
                    if dump.sockets.len() < limit {
                        dump.sockets.push(socket);
                    } else {
                        dump.omitted += 1;
                    }
                }
            }
            _ => return Err(Failure::Malformed),
        }
        let aligned = (len + 3) & !3;
        if aligned > data.len() - offset && offset + len != data.len() {
            return Err(Failure::Malformed);
        }
        offset += aligned;
    }
    Ok(false)
}

pub fn collect(
    family: u8,
    sequence: u32,
    limit: usize,
    deadline: Instant,
) -> Result<Dump, Failure> {
    // SAFETY: all pointers refer to initialized storage with the specified lengths;
    // the newly created fd is transferred exactly once to OwnedFd for every exit path.
    unsafe {
        let raw = libc::socket(
            libc::AF_NETLINK,
            libc::SOCK_RAW | libc::SOCK_CLOEXEC | libc::SOCK_NONBLOCK,
            libc::NETLINK_SOCK_DIAG,
        );
        if raw < 0 {
            return Err(Failure::os(io::Error::last_os_error()));
        }
        let fd = OwnedFd::from_raw_fd(raw);
        let mut address: libc::sockaddr_nl = mem::zeroed();
        address.nl_family = libc::AF_NETLINK as u16;
        let size = mem::size_of_val(&address) as libc::socklen_t;
        if libc::bind(
            fd.as_raw_fd(),
            (&address as *const libc::sockaddr_nl).cast(),
            size,
        ) < 0
        {
            return Err(Failure::os(io::Error::last_os_error()));
        }
        let mut request = [0u8; 72];
        request[..4].copy_from_slice(&72u32.to_ne_bytes());
        request[4..6].copy_from_slice(&20u16.to_ne_bytes());
        request[6..8].copy_from_slice(&0x301u16.to_ne_bytes());
        request[8..12].copy_from_slice(&sequence.to_ne_bytes());
        request[16] = family;
        request[17] = libc::IPPROTO_TCP as u8;
        request[20..24].copy_from_slice(&0x1ffeu32.to_ne_bytes());
        request[64..72].fill(255);
        if libc::sendto(
            fd.as_raw_fd(),
            request.as_ptr().cast(),
            request.len(),
            0,
            (&address as *const libc::sockaddr_nl).cast(),
            size,
        ) != request.len() as isize
        {
            return Err(Failure::os(io::Error::last_os_error()));
        }
        let mut dump = Dump::default();
        let mut buffer = vec![0u8; 256 * 1024];
        // Both wall-clock and datagram bounds protect against endless multipart dumps.
        for _ in 0..4096 {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(Failure::Timeout);
            }
            let mut poll = libc::pollfd {
                fd: fd.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            };
            let ready = libc::poll(&mut poll, 1, remaining.as_millis().clamp(1, 2000) as i32);
            if ready == 0 {
                return Err(Failure::Timeout);
            }
            if ready < 0 {
                let err = io::Error::last_os_error();
                if err.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(Failure::os(err));
            }
            let mut sender: libc::sockaddr_nl = mem::zeroed();
            let mut iov = libc::iovec {
                iov_base: buffer.as_mut_ptr().cast(),
                iov_len: buffer.len(),
            };
            let mut message: libc::msghdr = mem::zeroed();
            message.msg_name = (&mut sender as *mut libc::sockaddr_nl).cast();
            message.msg_namelen = size;
            message.msg_iov = &mut iov;
            message.msg_iovlen = 1;
            let n = libc::recvmsg(fd.as_raw_fd(), &mut message, 0);
            if n < 0 {
                let err = io::Error::last_os_error();
                if matches!(
                    err.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) {
                    continue;
                }
                return Err(Failure::os(err));
            }
            if n == 0
                || message.msg_flags & (libc::MSG_TRUNC | libc::MSG_CTRUNC) != 0
                || message.msg_namelen != size
                || sender.nl_family != libc::AF_NETLINK as u16
                || sender.nl_pid != 0
                || sender.nl_groups != 0
            {
                return Err(Failure::Malformed);
            }
            if parse(&buffer[..n as usize], family, sequence, &mut dump, limit)? {
                return Ok(dump);
            }
        }
        Err(Failure::Timeout)
    }
}

pub fn state_name(state: u8) -> &'static str {
    match state {
        1 => "ESTABLISHED",
        2 => "SYN_SENT",
        3 => "SYN_RECV",
        4 => "FIN_WAIT1",
        5 => "FIN_WAIT2",
        6 => "TIME_WAIT",
        7 => "CLOSE",
        8 => "CLOSE_WAIT",
        9 => "LAST_ACK",
        10 => "LISTEN",
        11 => "CLOSING",
        12 => "NEW_SYN_RECV",
        _ => "UNKNOWN",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn message(kind: u16, flags: u16, body: &[u8]) -> Vec<u8> {
        let mut bytes = vec![0; 16];
        bytes[..4].copy_from_slice(&((16 + body.len()) as u32).to_ne_bytes());
        bytes[4..6].copy_from_slice(&kind.to_ne_bytes());
        bytes[6..8].copy_from_slice(&flags.to_ne_bytes());
        bytes[8..12].copy_from_slice(&1u32.to_ne_bytes());
        bytes.extend(body);
        bytes
    }
    fn row(family: u8) -> Vec<u8> {
        let mut body = vec![0; 72];
        body[0] = family;
        body[1] = 1;
        body[4..6].copy_from_slice(&1234u16.to_be_bytes());
        body[6..8].copy_from_slice(&443u16.to_be_bytes());
        if family == 2 {
            body[8..12].copy_from_slice(&[127, 0, 0, 1]);
            body[24..28].copy_from_slice(&[192, 0, 2, 1]);
        } else {
            body[8..24].copy_from_slice(&Ipv6Addr::LOCALHOST.octets());
            body[24..40].copy_from_slice(&"2001:db8::1234".parse::<Ipv6Addr>().unwrap().octets());
        }
        body[68..72].copy_from_slice(&123u32.to_ne_bytes());
        body
    }
    #[test]
    fn multipart_decode_and_truncation_count() {
        for family in [2, 10] {
            let mut data = message(20, 2, &row(family));
            data.extend(message(20, 2, &row(family)));
            data.extend(message(3, 2, &0u32.to_ne_bytes()));
            let mut dump = Dump::default();
            assert!(parse(&data, family, 1, &mut dump, 1).unwrap());
            assert_eq!(dump.omitted, 1);
            let s = &dump.sockets[0];
            assert_eq!((s.local.port, s.remote.port, s.inode), (1234, 443, 123));
            assert_eq!(
                s.remote.address.to_string(),
                if family == 2 {
                    "192.0.2.1"
                } else {
                    "2001:db8::1234"
                }
            );
        }
    }
    #[test]
    fn rejects_corruption_and_incomplete_dumps() {
        let good = message(20, 2, &row(2));
        for len in 1..good.len() {
            assert!(parse(&good[..len], 2, 1, &mut Dump::default(), 10).is_err());
        }
        assert_eq!(
            parse(&good, 2, 2, &mut Dump::default(), 10),
            Err(Failure::Malformed)
        );
        assert_eq!(
            parse(&good, 10, 1, &mut Dump::default(), 10),
            Err(Failure::Malformed)
        );
        assert_eq!(
            parse(&message(20, 0x10, &row(2)), 2, 1, &mut Dump::default(), 10),
            Err(Failure::Interrupted)
        );
        assert_eq!(
            parse(
                &message(2, 0, &(-libc::EACCES).to_ne_bytes()),
                2,
                1,
                &mut Dump::default(),
                10
            ),
            Err(Failure::Denied)
        );
        assert_eq!(
            parse(
                &message(3, 0, &(-libc::EINTR).to_ne_bytes()),
                2,
                1,
                &mut Dump::default(),
                10
            ),
            Err(Failure::Interrupted)
        );
        assert!(!parse(&good, 2, 1, &mut Dump::default(), 10).unwrap());
        let mut listener = row(2);
        listener[1] = 10;
        let mut dump = Dump::default();
        parse(&message(20, 2, &listener), 2, 1, &mut dump, 10).unwrap();
        assert!(dump.sockets.is_empty());
    }
    #[test]
    fn bounded_arbitrary_input_never_panics() {
        let mut seed = 1234u32;
        for size in 0..512 {
            let data: Vec<_> = (0..size)
                .map(|_| {
                    seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                    (seed >> 16) as u8
                })
                .collect();
            let _ = parse(&data, 2, 1, &mut Dump::default(), 4);
        }
    }
}
