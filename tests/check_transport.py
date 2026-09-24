"""Native Quickshell transport smoke tests; no desktop installation or screenshots."""
import os
from pathlib import Path
import subprocess
import sys
import time
import signal

repository = Path(__file__).resolve().parents[1]
preview = Path(subprocess.check_output([sys.executable, "-B", str(repository / "tools/prepare_preview.py")], text=True).strip())
(preview / "shell.qml").write_text((repository / "tests/transport.qml").read_text())
helper = preview / "fixture.py"
helper.write_text('''#!/usr/bin/env python3
import json, os, signal, sys, time, uuid
mode = os.environ['OUTBOUND_TRANSPORT_TEST']
with open(os.environ['OUTBOUND_TEST_PID_FILE'],'a') as record: record.write(str(os.getpid())+'\\n')
if mode == 'late': signal.signal(signal.SIGTERM, signal.SIG_IGN)
session = uuid.uuid4().hex
sequence = 0
for line in sys.stdin:
    request = json.loads(line)
    if mode == 'retry': sys.exit(1)
    if mode == 'oversized':
        sys.stdout.write('x' * (2 * 1024 * 1024 + 1)); sys.stdout.flush(); continue
    if mode == 'malformed': print('{}', flush=True); continue
    if mode == 'late': time.sleep(0.35)
    sequence += 1
    result = dict(version=1, kind='snapshot', requestId=request['requestId'], session=session, sequence=sequence,
        observedAtMs=int(time.time()*1000), status='ok',
        connections=[dict(id=session+':1',family='IPv4',local=dict(address='127.0.0.1',port=123),remote=dict(address='127.0.0.1',port=456),state='ESTABLISHED',uid=1000,scope='loopback',direction='unknown',country=None,owners=[dict(pid=1,startTimeTicks='1',name='船🦀')])],
        coverage=dict(ipv4=None,ipv6=None,namespace='current',omittedRows=0,truncated=False,processes=dict(denied=0,races=0,errors=0,ownersOmitted=0,timedOut=False,scanLimited=False)),
        database=dict(state='missing',buildEpochSeconds=None,releaseMonth=None,stale=False,lookupErrors=0),
        aggregates=dict(sockets=1,countries=dict(nonInternet=1),applications={'船🦀':1},unknownOwners=0))
    if mode == 'incompatible': result['version']=2
    payload=json.dumps(result,ensure_ascii=True)+'\\n'
    # Force real pipe chunks across JSON Unicode escape sequences.
    for offset in range(0,len(payload),101):
        sys.stdout.write(payload[offset:offset+101]); sys.stdout.flush()
''')
helper.chmod(0o755)
for mode in (sys.argv[1:] or ["normal", "missing", "malformed", "incompatible", "oversized", "retry", "late", "native", "crash"]):
    executable = Path(os.environ.get("OUTBOUND_TEST_NATIVE_BACKEND", repository / "backend/ruby/build/outbound-engine")) if mode == "native" else preview / "missing" if mode == "missing" else helper
    pid_file = preview / (mode + "-pids")
    env = dict(os.environ, OUTBOUND_TEST_PID_FILE=str(pid_file), QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="basic", OUTBOUND_TRANSPORT_TEST=mode, OUTBOUND_TEST_BACKEND=str(executable))
    if mode == "crash":
        child = subprocess.Popen(["qs", "-p", str(preview), "--no-color"], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            deadline = time.monotonic() + 5
            while not pid_file.exists() and time.monotonic() < deadline:
                time.sleep(0.025)
            if not pid_file.exists():
                raise RuntimeError("Fixture never started")
            pid = int(pid_file.read_text().splitlines()[0])
            child.kill()
            child.communicate(timeout=5)
            deadline = time.monotonic() + 3
            while Path(f"/proc/{pid}").exists() and time.monotonic() < deadline:
                # A reparented zombie is already dead; reaping belongs to init.
                if Path(f"/proc/{pid}/stat").read_text().rsplit(')',1)[1].split()[0] == 'Z':
                    break
                time.sleep(0.025)
            else:
                if Path(f"/proc/{pid}").exists():
                    os.kill(pid, signal.SIGKILL)
                    raise RuntimeError("Backend survived abrupt host exit")
            print("PASS transport: crash")
        finally:
            if child.poll() is None:
                child.kill()
                child.communicate(timeout=5)
        continue
    result = subprocess.run(["qs", "-p", str(preview), "--no-color"], env=env, text=True, capture_output=True, timeout=20)
    output=result.stdout+result.stderr
    if result.returncode or f"OUTBOUND_TEST_PASS {mode}" not in output or "OUTBOUND_TEST_FAILED" in output:
        print(output)
        raise SystemExit(f"Transport test failed: {mode}")
    print(f"PASS transport: {mode}")
