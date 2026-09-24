use serde::Serialize;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Scope {
    Public,
    Loopback,
    Private,
    LinkLocal,
    Shared,
    Documentation,
    Multicast,
    Unspecified,
    Reserved,
}

pub fn normalized(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v) => v.to_ipv4_mapped().map(IpAddr::V4).unwrap_or(ip),
        _ => ip,
    }
}
fn v4(ip: Ipv4Addr, base: [u8; 4], bits: u32) -> bool {
    u32::from(ip) >> (32 - bits) == u32::from(Ipv4Addr::from(base)) >> (32 - bits)
}
fn v6(ip: Ipv6Addr, base: &str, bits: u32) -> bool {
    u128::from(ip) >> (128 - bits) == u128::from(base.parse::<Ipv6Addr>().unwrap()) >> (128 - bits)
}

/// Reviewed IANA special-purpose registries (2025-10-09); see docs/protocol.md.
/// "Public" is a classification, not evidence of reachability or socket direction.
pub fn classify(address: IpAddr) -> Scope {
    use Scope::*;
    match normalized(address) {
        IpAddr::V4(ip) => {
            if ip.is_unspecified() {
                return Unspecified;
            }
            if ip.is_loopback() {
                return Loopback;
            }
            if ip.is_private() {
                return Private;
            }
            if ip.is_link_local() {
                return LinkLocal;
            }
            if ip.is_multicast() {
                return Multicast;
            }
            if ip.is_documentation() {
                return Documentation;
            }
            if v4(ip, [100, 64, 0, 0], 10) {
                return Shared;
            }
            // Globally reachable exceptions within the protocol-assignment block.
            if ip == Ipv4Addr::new(192, 0, 0, 9) || ip == Ipv4Addr::new(192, 0, 0, 10) {
                return Public;
            }
            if v4(ip, [0, 0, 0, 0], 8)
                || v4(ip, [192, 0, 0, 0], 24)
                || v4(ip, [192, 88, 99, 0], 24)
                || v4(ip, [198, 18, 0, 0], 15)
                || v4(ip, [240, 0, 0, 0], 4)
            {
                return Reserved;
            }
            Public
        }
        IpAddr::V6(ip) => {
            if ip.is_unspecified() {
                return Unspecified;
            }
            if ip.is_loopback() {
                return Loopback;
            }
            if ip.is_multicast() {
                return Multicast;
            }
            if v6(ip, "fc00::", 7) {
                return Private;
            }
            if v6(ip, "fe80::", 10) {
                return LinkLocal;
            }
            if v6(ip, "2001:db8::", 32) || v6(ip, "3fff::", 20) {
                return Documentation;
            }
            // Translation and tunnel prefixes are special-use: do not geolocate
            // their embedded addresses as though they were observed IPv4 peers.
            if v6(ip, "2002::", 16) {
                return Reserved;
            }
            if v6(ip, "2001::", 23) {
                if ["2001:1::1", "2001:1::2", "2001:1::3"]
                    .iter()
                    .any(|s| ip == s.parse::<Ipv6Addr>().unwrap())
                    || v6(ip, "2001:3::", 32)
                    || v6(ip, "2001:4:112::", 48)
                    || v6(ip, "2001:20::", 28)
                    || v6(ip, "2001:30::", 28)
                {
                    return Public;
                }
                return Reserved;
            }
            if v6(ip, "2000::", 3) {
                Public
            } else {
                Reserved
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn special_ranges_and_exceptions() {
        for (ip, expected) in [
            ("0.0.0.0", Scope::Unspecified),
            ("127.1.2.3", Scope::Loopback),
            ("10.0.0.1", Scope::Private),
            ("100.127.255.255", Scope::Shared),
            ("100.128.0.1", Scope::Public),
            ("169.254.1.1", Scope::LinkLocal),
            ("192.0.0.8", Scope::Reserved),
            ("192.0.0.9", Scope::Public),
            ("192.0.0.10", Scope::Public),
            ("192.0.2.1", Scope::Documentation),
            ("198.18.0.1", Scope::Reserved),
            ("224.1.2.3", Scope::Multicast),
            ("255.255.255.255", Scope::Reserved),
            ("::ffff:192.168.1.1", Scope::Private),
            ("::ffff:8.8.8.8", Scope::Public),
            ("::1", Scope::Loopback),
            ("::", Scope::Unspecified),
            ("fc00::1", Scope::Private),
            ("fe80::1", Scope::LinkLocal),
            ("ff02::1", Scope::Multicast),
            ("2001:db8::1", Scope::Documentation),
            ("3fff:fff::", Scope::Documentation),
            ("3fff:1000::", Scope::Public),
            ("2001:2::1", Scope::Reserved),
            ("2001:1::1", Scope::Public),
            ("2001:3::1", Scope::Public),
            ("2001:4860::8888", Scope::Public),
            ("64:ff9b::808:808", Scope::Reserved),
            ("2002::1", Scope::Reserved),
        ] {
            assert_eq!(classify(ip.parse().unwrap()), expected, "{ip}");
        }
    }
}
