use outbound_engine::{
    engine::Engine,
    geo::Geo,
    protocol::{self, Action, Input},
};
use std::{
    io::{self, BufReader, Write},
    path::PathBuf,
    process::ExitCode,
};

fn run() -> io::Result<()> {
    let mut database = None;
    let mut check_database = false;
    let mut args = std::env::args_os().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--help" {
            eprintln!(
                "outbound-engine [--database FILE.mmdb] [--check-database]\nReads version-1 JSON commands from stdin; emits snapshots on stdout.\nNo automatic sampling, downloads or privilege elevation. EOF exits."
            );
            return Ok(());
        }
        if arg == "--check-database" && !check_database {
            check_database = true;
            continue;
        }
        if arg != "--database" || database.is_some() {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        database = Some(PathBuf::from(
            args.next().ok_or(io::ErrorKind::InvalidInput)?,
        ));
    }
    if check_database {
        let path = database.as_deref().ok_or(io::ErrorKind::InvalidInput)?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| io::ErrorKind::InvalidData)?
            .as_secs();
        let geo = Geo::load(Some(path), now);
        if !geo.is_country_database() {
            return Err(io::ErrorKind::InvalidData.into());
        }
        serde_json::to_writer(io::stdout().lock(), &geo.status)?;
        println!();
        return Ok(());
    }
    let mut engine = Engine::new(database.as_deref())?;
    let mut input = BufReader::with_capacity(4096, io::stdin().lock());
    let mut output = io::stdout().lock();
    loop {
        match protocol::read_command(&mut input)? {
            Input::Eof => return Ok(()),
            Input::Invalid(code) => {
                serde_json::to_writer(
                    &mut output,
                    &serde_json::json!({"version":1,"kind":"error","requestId":null,"code":code,"fatal":true}),
                )?;
                output.write_all(b"\n")?;
                output.flush()?;
                return Err(io::ErrorKind::InvalidData.into());
            }
            Input::Command(command) => {
                match command.command {
                    Action::Snapshot => {
                        output.write_all(&engine.sample(command.request_id).encode_bounded()?)?
                    }
                    Action::Shutdown => {
                        serde_json::to_writer(
                            &mut output,
                            &serde_json::json!({"version":1,"kind":"stopped","requestId":command.request_id}),
                        )?;
                        output.write_all(b"\n")?;
                        output.flush()?;
                        return Ok(());
                    }
                }
                output.flush()?;
            }
        }
    }
}
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(_) => {
            eprintln!("outbound-engine: stopped after an input or I/O error");
            ExitCode::FAILURE
        }
    }
}
