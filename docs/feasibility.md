# Phase 0 — contracts and feasibility

Completed 2026-09-24: shell contracts inspected, unprivileged Linux socket
access demonstrated, related projects compared, data sources chosen, and a
distribution strategy recorded. This permits starting the simulated UI; it
does not certify the future plugin or its release.

## Repository baseline

The repository initially contained a licence and a README describing another
project. `PLAN.md`, `.gitignore`, and `.graphifyignore` were existing untracked
files. There was no manifest, QML, backend, development guide, or graph output
to validate. The unrelated untracked files and the original plan are preserved.

## Linux experiment

Reproduce with `python3 -B tools/probe_sockets.py` as an ordinary Linux user.
The standard-library script is a development probe, not the future backend.
It rejects UID 0 and effective capabilities. It creates held loopback TCP
connections, requests raw inet_diag dumps, matches only its own controlled
inodes, and checks them against `ss`. It prints neither other applications'
connections nor their command lines. No test payload or Internet traffic is
sent. Sockets close on normal completion and exceptions.

Environment observed:

| Item | Value |
| --- | --- |
| Architecture | aarch64 |
| Kernel | 7.2.5-1-aarch64-ARCH |
| UID / effective capabilities | 1000 / 0 |
| Omarchy runtime package | try-omarchy-runtime 4.0.3-1 |
| Omarchy version file | 4.0.0.alpha |
| Quickshell | 0.3.1-1 |
| Qt base / declarative | 6.11.2-3 / 6.11.2-2 |
| iproute2 | 7.2.0-1 |
| glibc | 2.43+r22+g8362e8ce10b2-2 |

| Check | Result |
| --- | --- |
| IPv4 established endpoints | Both visible through NETLINK_SOCK_DIAG |
| IPv6 established endpoints | Both visible through NETLINK_SOCK_DIAG |
| UID and inode association | Exact match for both families |
| Own process `comm` and fd symlinks | Readable |
| Independent `ss -ntp` comparison | Both endpoints attributed to probe PID |
| Connection opened/closed between dumps | Original socket inodes absent in next dump |
| `/proc/1/fd` listing | Permission denied |

The execution sandbox initially denied even creating an IPv4 socket. The
successful run was outside that sandbox, still UID 1000 with zero capabilities;
no sudo or capability elevation was used. Sandbox restrictions must not be
reported as intrinsic Linux collector limitations.

The test demonstrates accessible own sockets and a concrete process-permission
boundary, not comprehensive visibility of other users' sockets. Short-lived
connections may leave TIME_WAIT records, but their original inode/process
association can already be lost. Snapshot sampling is not an event stream.
The [socket diagnostic interface](https://man7.org/linux/man-pages/man7/sock_diag.7.html)
provides the fields used here; access to process fd links is separately
subject to [ptrace access checks](https://man7.org/linux/man-pages/man5/proc_pid_fd.5.html).

No x86_64, separate-user controlled server, hidepid mount, container namespace,
VPN/proxy interpretation, suspended process, Rust implementation, or live plugin
lifecycle test has been performed. These remain explicit later-phase checks.

## Related projects

Sources were downloaded for inspection only; no project was installed or run.

| Project and pinned revision | Verified overlap | Decision |
| --- | --- | --- |
| [OmaGlobe](https://github.com/zamak/omaglobe/tree/88df99e48bb643e78d9f344954db02d610dec0d4) | QML Canvas globe, bar/overlay integration, Natural Earth country geometry; live Earth-event feeds | Useful projection and interaction reference; no socket collector to reuse |
| [NetRadar](https://github.com/ozdil/omarchy-netradar/tree/9ce2b50e011553e86db0e23d9596b7a281572dcd) | Rust/JSON with QML UI, LAN neighbor discovery, process helpers and bounded operations | Different collection model; do not adopt active LAN scans, DNS lookups, ping, or port probes |

OmaGlobe's `Globe.qml` uses `Canvas.Cooperative` and redraws on view/selection
changes; its manifest combines overlay and bar-widget entry points. Its MIT
licence credits Akshar Patel and tiho; NOTICE identifies derivation from Radio
Atlas. Any later source adaptation must retain that provenance and licence.
Its map attribution identifies Natural Earth 1:110m Admin 0 Countries. Outbound
will source geometry directly rather than silently copying generated assets.

NetRadar's inspected `src/scanner.rs` invokes `ip`, reads interface counters,
does reverse name resolution, and contains UDP/ping and TCP service probes.
Its Cargo manifest uses serde, serde_json and libc; its MIT licence credits
Ozan Özdil. Its extra manifest fields are not evidence of supported shell APIs.
No source code from either project is included in Outbound by this phase.

## Local shell fingerprints

The local shell differs from the pinned official Quattro source. These SHA-256
values identify the exact inspected files under `/usr/share/omarchy`:

```text
shell/shell.qml
9e39e81551ae99bd5e2e9e33721075f7c91caf95dbe8af0e5a36e8eb9150e087
shell/Ui/BarWidget.qml
8be00e2553a486b3dbfcb4f99de976035f323c4061b993dbc1842c75ff8b9022
shell/services/PluginShellApi.qml
ff0cb5ec5fcdda0b21af447b11f07a24e065a3557796639364109aaa2ce5c763
bin/omarchy-plugin-add
fc8eb1486275e308037ca8f284fbb0eb4e010dec593260519695c79414a4b9fb
bin/omarchy-plugin-validate
f7507e5042eb970e3dc918bdf6bf251c7557443892a77e71a17d7019ddde72c8
```

## Handoff

Phase 1 may implement the UI against [architecture.md](architecture.md) with
clearly labelled fixtures. Its completion still requires real shell loading,
light/dark theme checks, keyboard access, reduced motion and rendering profiles.
The approved visual mockup was not present in the repository inspected here.
Phase 2 owns Rust/parser correctness; Phase 3/4 owns lifecycle and bounded
framing; Phase 5 owns both architecture builds and installation verification.
