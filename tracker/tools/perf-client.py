#!/usr/bin/env python3
"""Editor-target bench client for tracker/tools/perf-bench.sh (PERF-ROADMAP P1(b)).

Boots the resident language server ONCE, then drives K didChange ->
publishDiagnostics round trips over one file and reports the distribution.
Everything it measures is the editor's steady state: a warm JVM, a warm
session, and a per-uri inference cache that survives every edit.

Usage (the server command line follows a bare --):

   perf-client.py --rounds 15 --log /tmp/perf-lsp.log --out /tmp/editor.json \\
     --file core/src/main/resources/modules/Layout/Report.e \\
     -- java -Dermine.lsp.log=/tmp/perf-lsp.log -cp "$cp" \\
        com.clarifi.reporting.ermine.lsp.Main

WHY THIS IS NOT tracker/tools/lsp-client.py.  That client is an assertion
harness: no clock call anywhere in it, a 50-message read budget instead of a
deadline, and diagnostics_for() that will happily hand back a publish stashed
during an earlier wait.  A bench needs monotonic timing, real deadlines and a
drained stream between rounds, so the ~40 lines of framing are duplicated here
rather than imported.

THE EDIT IS THE WHOLE EXPERIMENT, so it is pinned and asserted:

  * It must CHANGE A FINGERPRINT.  TolerantCheck.keys (core/src/main/scala/
    com/clarifi/reporting/ermine/session/TolerantCheck.scala:98-114) keys each
    group by `startLine + ":" + text`, where text runs from the statement's
    first significant character to just past its last one.  Trailing
    whitespace and trailing comments therefore change NOTHING -- the roadmap
    records a measurement invalidated by exactly that (PERF-ROADMAP.md, 5.5
    entry).  We edit INSIDE a body line, with significant characters still
    after the edit on the same line.
  * It must NOT MOVE THE SCOPE KEY, or the whole per-uri cache drops and every
    round is cold: no import/export/type/data/class/instance/field/table/
    foreign/private/database/abstract/infix*/prefix/postfix statement, and no
    change to the top-level head set (TolerantCheck.scala:110).
  * It must NOT CHANGE THE LINE COUNT.  Start lines are in every group's key,
    so inserting a line invalidates everything below it.
  * It must land in a NAMED top-level definition -- groups come from
    bindItems.filter(_.headWord.nonEmpty), so an operator is never cached.

The pinned site satisfies all four: one digit of an integer literal inside
`emptyReport`'s single-line body, a definition referenced 14 times elsewhere in
Report.e, so the edit invalidates a real transitive closure rather than one
leaf.  Changing a digit cannot change a type, which is the point -- the
re-inference work is identical to a semantic edit's, because the cache is keyed
on TEXT, while the diagnostics stay empty and the run stays comparable.
`reused A of B` is reported for every round and is the proof the edit was real:
A == B means nothing was invalidated, A == 0 means the cache never warmed.
"""
import argparse
import json
import os
import pathlib
import re
import select
import subprocess
import sys
import time

# --- the pinned edit site (asserted against the file before anything runs) ---
EDIT_LINE = 281  # 1-based
EDIT_EXPECT = ("emptyReport = prefA [pixelsA 0 0, cellsA 0 0] "
               "' Report (w -> unit (wm w) (emptyW w))")
EDIT_ANCHOR = "cellsA 0 "  # the digit right after this is what we cycle

BOOT_DEADLINE = 180.0   # interface-free boot is ~13s; this is a hang guard
ROUND_DEADLINE = 120.0
DEBOUNCE = 0.300        # Diagnostics.scala's quiet window, a named term


def die(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)


class Client:
    """Content-Length framing over the server's stdio, with real deadlines."""

    def __init__(self, cmd, stderr_path):
        self.errf = open(stderr_path, "wb")
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=self.errf)
        self.next_id = 0
        self.buf = b""

    def send(self, msg):
        body = json.dumps(msg).encode("utf-8")
        self.proc.stdin.write(b"Content-Length: " + str(len(body)).encode()
                              + b"\r\n\r\n" + body)
        self.proc.stdin.flush()

    def request(self, method, params):
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": self.next_id,
                   "method": method, "params": params})
        return self.next_id

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def _fill(self, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            die("timed out waiting for the server")
        r, _, _ = select.select([self.proc.stdout], [], [], remaining)
        if not r:
            die("timed out waiting for the server")
        chunk = self.proc.stdout.read1(65536)
        if not chunk:
            die("server closed stdout (exit %s)" % self.proc.poll())
        self.buf += chunk

    def read_message(self, deadline):
        while True:
            head, sep, rest = self.buf.partition(b"\r\n\r\n")
            if sep:
                m = re.search(rb"Content-Length:\s*(\d+)", head, re.I)
                if not m:
                    die("headers without Content-Length: %r" % head[:200])
                n = int(m.group(1))
                if len(rest) >= n:
                    self.buf = rest[n:]
                    return json.loads(rest[:n].decode("utf-8"))
            self._fill(deadline)

    def wait_for(self, pred, what, deadline):
        while True:
            msg = self.read_message(deadline)
            if pred(msg):
                return msg
            if (msg.get("method") == "window/logMessage"
                    and "failed to boot" in msg["params"].get("message", "")):
                die("server failed to boot: " + msg["params"]["message"])


def variant(lines, digit):
    """The pinned edit: one digit, same line, same line count, same length."""
    line = lines[EDIT_LINE - 1]
    i = line.index(EDIT_ANCHOR) + len(EDIT_ANCHOR)
    out = list(lines)
    out[EDIT_LINE - 1] = line[:i] + str(digit) + line[i + 1:]
    return "\n".join(out)


def median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return float("nan")
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=15)
    ap.add_argument("--file", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--stderr", default=None)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    if not cmd:
        die("no server command given (put it after --)")
    if a.rounds < 3:
        die("--rounds must be at least 3 (round 1 is discarded as JIT warm-up)")

    path = pathlib.Path(a.file).resolve()
    # Bytes, decoded by hand: 142 of the 161 stdlib modules are CRLF and
    # Python's universal newlines would silently rewrite them, changing every
    # fingerprint at once (PERF-ROADMAP Decision 12).
    src = path.read_bytes().decode("utf-8")
    lines = src.split("\n")
    if len(lines) < EDIT_LINE or lines[EDIT_LINE - 1] != EDIT_EXPECT:
        die("the pinned edit site moved: %s:%d is %r, expected %r"
            % (path, EDIT_LINE, lines[EDIT_LINE - 1:EDIT_LINE], EDIT_EXPECT))
    uri = path.as_uri()

    client = Client(cmd, a.stderr or (a.out + ".stderr"))
    boot_deadline = time.monotonic() + BOOT_DEADLINE
    rid = client.request("initialize", {
        "processId": os.getpid(),
        "rootUri": pathlib.Path.cwd().as_uri(),
        "capabilities": {},
    })
    init = client.wait_for(lambda m: m.get("id") == rid, "initialize", boot_deadline)
    sync = init["result"]["capabilities"]["textDocumentSync"]
    if sync.get("change") != 1:
        die("server does not advertise full-text didChange (change=%r)"
            % sync.get("change"))
    client.notify("initialized", {})
    t_boot = time.monotonic()
    ready = client.wait_for(
        lambda m: (m.get("method") == "window/logMessage"
                   and "session ready" in m["params"].get("message", "")),
        "session ready", boot_deadline)
    boot_s = time.monotonic() - t_boot
    print("  boot: %s (%.2fs measured here)" % (ready["params"]["message"], boot_s))

    rounds = []

    def one(text, version, label):
        t0 = time.monotonic()
        if version == 1:
            client.notify("textDocument/didOpen", {"textDocument": {
                "uri": uri, "languageId": "ermine", "version": version,
                "text": text}})
        else:
            client.notify("textDocument/didChange", {
                "textDocument": {"uri": uri, "version": version},
                "contentChanges": [{"text": text}]})
        msg = client.wait_for(
            lambda m: (m.get("method") == "textDocument/publishDiagnostics"
                       and m["params"].get("uri") == uri),
            "publishDiagnostics", time.monotonic() + ROUND_DEADLINE)
        dt = time.monotonic() - t0
        n = len(msg["params"].get("diagnostics", []))
        rounds.append({"label": label, "version": version, "total_s": dt,
                       "diagnostics": n})
        return dt, n

    # Round 0 is didOpen: cold per-uri cache AND no debounce (didOpen checks
    # immediately).  Reported separately, never folded into the median.
    dt, n = one(src, 1, "didOpen")
    print("  round 0 (didOpen, cold cache): %.3fs, %d diagnostic(s)" % (dt, n))

    for r in range(1, a.rounds + 1):
        dt, n = one(variant(lines, r % 10), r + 1, "didChange")
        print("  round %d: %.3fs, %d diagnostic(s)" % (r, dt, n))

    rid = client.request("shutdown", {})
    client.wait_for(lambda m: m.get("id") == rid, "shutdown",
                    time.monotonic() + 30)
    client.notify("exit", {})
    try:
        rc = client.proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        client.proc.kill()
        die("server did not exit after shutdown/exit")
    if rc != 0:
        die("server exited %d (expected 0 after shutdown then exit)" % rc)

    # The server's own split, from its log.  Without -Dermine.lsp.log the log
    # lambda is a no-op and there is no split to harvest -- fail rather than
    # report a wall-clock number with no breakdown.
    log = pathlib.Path(a.log).read_text(errors="replace")
    if "fast mode" in log:
        die("the server entered fast mode; type checking was skipped")
    checks = re.findall(
        r"check: \S+ read ([0-9]+[.,][0-9]+)s, typecheck ([0-9]+[.,][0-9]+)s "
        r"\(reused (\d+) of (\d+) components\)", log)
    if len(checks) != len(rounds):
        die("harvested %d 'check:' lines for %d rounds -- log format changed "
            "or -Dermine.lsp.log was not passed (%s)"
            % (len(checks), len(rounds), a.log))
    for row, (read, chk, reused, comps) in zip(rounds, checks):
        row["read_s"] = float(read.replace(",", "."))
        row["typecheck_s"] = float(chk.replace(",", "."))
        row["reused"] = int(reused)
        row["components"] = int(comps)
        # didOpen checks IMMEDIATELY; only didChange goes through the quiet
        # window, so only didChange pays the debounce.
        row["debounce_s"] = DEBOUNCE if row["label"] == "didChange" else 0.0
        # Everything the check: line does not cover but the round trip pays:
        # the env copy, the nine-pass self-scrub, the header parse,
        # TolerantCheck.keys/StatementExtents.scan, Definitions.index, and the
        # protocol write itself.
        row["residual_s"] = (row["total_s"] - row["debounce_s"]
                             - row["read_s"] - row["typecheck_s"])

    edits = rounds[1:]
    if any(r["reused"] == 0 for r in edits):
        die("a round reused NOTHING -- the scope key moved, so the edit was "
            "not the in-body edit this bench assumes")
    if any(r["reused"] >= r["components"] for r in edits):
        die("a round reused EVERYTHING -- the edit changed no fingerprint, "
            "which is the flattering measurement PERF-ROADMAP warns about")
    if rounds[0]["diagnostics"] != 0 or any(r["diagnostics"] != 0 for r in edits):
        print("  note: the target published diagnostics; the edit may not be "
              "type-neutral (recorded, not fatal)")

    # Round 1 is warm in the cache but cold in the JIT; the steady state is 2..K.
    steady = edits[1:]
    summary = {
        "file": str(path), "rounds": a.rounds, "boot_s": boot_s,
        "debounce_s": DEBOUNCE,
        "cold_open": rounds[0],
        "first_edit": edits[0],
        "steady_n": len(steady),
        "median_total_s": median([r["total_s"] for r in steady]),
        "median_read_s": median([r["read_s"] for r in steady]),
        "median_typecheck_s": median([r["typecheck_s"] for r in steady]),
        "median_residual_s": median([r["residual_s"] for r in steady]),
        "min_total_s": min(r["total_s"] for r in steady),
        "max_total_s": max(r["total_s"] for r in steady),
        "reused": steady[0]["reused"], "components": steady[0]["components"],
        "per_round": rounds,
    }
    pathlib.Path(a.out).write_text(json.dumps(summary, indent=2))

    print("  steady state (rounds 2..%d, round 1 discarded as JIT warm-up):"
          % a.rounds)
    print("    median %.3fs = read %.3fs + typecheck %.3fs + debounce %.3fs "
          "+ residual %.3fs"
          % (summary["median_total_s"], summary["median_read_s"],
             summary["median_typecheck_s"], DEBOUNCE,
             summary["median_residual_s"]))
    print("    spread %.3fs..%.3fs, reused %d of %d components"
          % (summary["min_total_s"], summary["max_total_s"],
             summary["reused"], summary["components"]))
    print("PERFBENCH-EDITOR boot_s=%.2f rounds=%d steady_n=%d "
          "editor_median_s=%.3f editor_read_s=%.3f editor_check_s=%.3f "
          "editor_debounce_s=%.3f editor_residual_s=%.3f "
          "editor_min_s=%.3f editor_max_s=%.3f reused=%d/%d cold_open_s=%.3f"
          % (boot_s, a.rounds, len(steady), summary["median_total_s"],
             summary["median_read_s"], summary["median_typecheck_s"],
             DEBOUNCE, summary["median_residual_s"], summary["min_total_s"],
             summary["max_total_s"], summary["reused"], summary["components"],
             rounds[0]["total_s"]))


if __name__ == "__main__":
    main()
