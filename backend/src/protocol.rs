use serde::Deserialize;
use std::io::{self, BufRead};
const MAX_COMMAND: usize = 4096;
#[derive(Debug, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Command {
    pub version: u8,
    pub request_id: String,
    pub command: Action,
}
#[derive(Debug, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum Action {
    Snapshot,
    Shutdown,
}
#[derive(Debug, PartialEq)]
pub enum Input {
    Eof,
    Command(Command),
    Invalid(&'static str),
}

/// Bounded framing even without a terminating newline. A framing violation is
/// fatal; do not drain an arbitrarily long input looking for the next command.
pub fn read_command(reader: &mut impl BufRead) -> io::Result<Input> {
    let mut line = Vec::new();
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(if line.is_empty() {
                Input::Eof
            } else {
                Input::Invalid("unterminatedCommand")
            });
        }
        let end = available.iter().position(|b| *b == b'\n');
        let take = end.map_or(available.len(), |i| i + 1);
        if line.len() + take > MAX_COMMAND {
            return Ok(Input::Invalid("commandTooLarge"));
        }
        line.extend_from_slice(&available[..take]);
        reader.consume(take);
        if end.is_some() {
            break;
        }
    }
    // Check nesting before serde allocates a tree, respecting escaped strings.
    let (mut depth, mut quoted, mut escaped) = (0usize, false, false);
    for byte in &line {
        if quoted {
            if escaped {
                escaped = false;
            } else if *byte == b'\\' {
                escaped = true;
            } else if *byte == b'"' {
                quoted = false;
            }
        } else {
            match byte {
                b'"' => quoted = true,
                b'{' | b'[' => {
                    depth += 1;
                    if depth > 8 {
                        return Ok(Input::Invalid("commandTooDeep"));
                    }
                }
                b'}' | b']' => {
                    if depth == 0 {
                        return Ok(Input::Invalid("invalidCommand"));
                    }
                    depth -= 1;
                }
                _ => {}
            }
        }
    }
    let command: Command = match serde_json::from_slice(&line) {
        Ok(v) => v,
        Err(_) => return Ok(Input::Invalid("invalidCommand")),
    };
    if command.version != 1 {
        return Ok(Input::Invalid("unsupportedVersion"));
    }
    if command.request_id.is_empty()
        || command.request_id.len() > 64
        || !command
            .request_id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
    {
        return Ok(Input::Invalid("invalidRequestId"));
    }
    Ok(Input::Command(command))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_and_bounds_framing() {
        let valid = b"{\"version\":1,\"requestId\":\"sample-1\",\"command\":\"snapshot\"}\n";
        assert!(matches!(
            read_command(&mut &valid[..]).unwrap(),
            Input::Command(_)
        ));
        for (bytes, expected) in [
            (vec![b' '; 4097], "commandTooLarge"),
            (
                b"{\"version\":2,\"requestId\":\"x\",\"command\":\"snapshot\"}\n".to_vec(),
                "unsupportedVersion",
            ),
            (b"{}".to_vec(), "unterminatedCommand"),
            (b"{}\n".to_vec(), "invalidCommand"),
            (b"[[[[[[[[[0]]]]]]]]]\n".to_vec(), "commandTooDeep"),
            (vec![255, 10], "invalidCommand"),
        ] {
            assert_eq!(
                read_command(&mut &bytes[..]).unwrap(),
                Input::Invalid(expected)
            );
        }
        assert_eq!(read_command(&mut &b""[..]).unwrap(), Input::Eof);
        let mut two = &b"{\"version\":1,\"requestId\":\"x\",\"command\":\"shutdown\"}\n{\"version\":1,\"requestId\":\"y\",\"command\":\"snapshot\"}\n"[..];
        assert!(matches!(
            read_command(&mut two).unwrap(),
            Input::Command(Command {
                command: Action::Shutdown,
                ..
            })
        ));
        assert!(matches!(
            read_command(&mut two).unwrap(),
            Input::Command(Command {
                command: Action::Snapshot,
                ..
            })
        ));
    }
}
