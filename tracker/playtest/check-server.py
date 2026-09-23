#!/usr/bin/env python3
"""Start THIS worktree's bin/ermine-lsp exactly the way the extension does,
wait for its boot line, shut it down, and say whether it worked.

    python3 tracker/playtest/check-server.py

Run it from the worktree root before you open VS Code.  It proves three
things the editor cannot tell you apart when they go wrong: the launcher
runs, the classpath cache is usable, and the resident session boots.

Exit 0 = the server booted and exited cleanly.  Exit 1 = it did not; the
reason is printed.  It starts one JVM and always stops it.
"""
import json, os, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "bin" / "ermine-lsp"
DEADLINE = 180.0                      # a cold sbt classpath build can be minutes; this is not that

def frame(proc, msg):
    body = json.dumps(msg).encode()
    proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    proc.stdin.flush()

def read(proc):
    length = None
    while True:
        line = proc.stdout.readline()
        if not line: raise EOFError("the server closed stdout")
        if line in (b"\r\n", b"\n"): break
        if line.lower().startswith(b"content-length:"):
            length = int(line.split(b":", 1)[1].strip())
    if length is None: raise IOError("headers with no Content-Length")
    body = b""
    while len(body) < length:
        chunk = proc.stdout.read(length - len(body))
        if not chunk: raise EOFError("the server closed mid-body")
        body += chunk
    return json.loads(body)

def main():
    if not LAUNCHER.exists():
        print("NOT OK: %s does not exist" % LAUNCHER); return 1
    cache = ROOT / "target" / "ermine-classpath"
    print("worktree:  %s" % ROOT)
    print("launcher:  %s" % LAUNCHER)
    print("classpath: %s" % ("%s, %d bytes" % (cache, cache.stat().st_size) if cache.exists()
                             else "%s MISSING -- the first start will run sbt" % cache))
    t0 = time.time()
    proc = subprocess.Popen([str(LAUNCHER)], cwd=str(ROOT), stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        frame(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                     "params": {"capabilities": {}, "rootUri": ROOT.as_uri(),
                                "workspaceFolders": [{"uri": ROOT.as_uri(), "name": ROOT.name}]}})
        boot = None
        while time.time() - t0 < DEADLINE:
            msg = read(proc)
            if msg.get("id") == 1 and "result" in msg:
                print("initialize answered in %.2fs" % (time.time() - t0))
                frame(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})
            if "method" in msg and "id" in msg:            # a server -> client request
                frame(proc, {"jsonrpc": "2.0", "id": msg["id"], "result": None})
            if msg.get("method") == "window/logMessage":
                text = msg["params"]["message"]
                print("  [%6.2fs] %s" % (time.time() - t0, text))
                if "session ready" in text:
                    boot = text
                    break
        if boot is None:
            print("NOT OK: no boot line within %.0fs" % DEADLINE); return 1
        frame(proc, {"jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": None})
        while True:
            msg = read(proc)
            if msg.get("id") == 2: break
            if "method" in msg and "id" in msg:
                frame(proc, {"jsonrpc": "2.0", "id": msg["id"], "result": None})
        frame(proc, {"jsonrpc": "2.0", "method": "exit", "params": {}})
        rc = proc.wait(timeout=60)
        print("shutdown clean, exit code %d" % rc)
        print("OK: %s" % boot)
        return 0
    finally:
        if proc.poll() is None:
            proc.kill(); proc.wait(timeout=20)

sys.exit(main())
