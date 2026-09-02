#!/usr/bin/env python3
"""Live progress bar for a long corpus sweep -- `corpus-run.sh` or `ei-diff.sh`.

    tracker/tools/sweep-progress.py                  # auto-detect whatever is running
    tracker/tools/sweep-progress.py /tmp/x/cum-new   # a corpus-run.sh output dir
    tracker/tools/sweep-progress.py --once           # one line, no loop (for logs/cron)

WHY IT EXISTS.  Both sweeps are one JVM per file across 66-220 files and run 15-50
minutes, and both are SILENT while they work.  `corpus-run.sh` prints a single line at
the end; `ei-diff.sh` prints nothing until BOTH sides finish -- and when it is launched
through a pipe (`... | tail -120`), even that is buffered until exit, so the task file
sits at 0 bytes for the whole run.  Until now the only way to know where a sweep was
had been `pgrep` plus arithmetic against `find core/examples -name '*.e' | sort`.

WHAT IT DELIBERATELY DOES NOT DO.  It renders to the TTY on **stderr** and never writes
into a sweep's captured output.  Sweep stdout gets compared byte-for-byte between runs;
a progress bar in there is precisely the noise the trap list warns about -- the JVM's
own boot bar already forces every corpus diff to normalise it away, and without that
step all 66 pairs "differ" by two lines of pure wall-clock.

THE ETA IS TWO NUMBERS ON PURPOSE.  Per-file cost is bimodal.  `incomplete/` under
`-Dermine.resGuard=false` measured ~35% slower than the rest of the corpus, and a single
cliff module can be an order of magnitude off its neighbours (`gu05`: 1.1s guarded,
12.0s not).  A mean-based ETA smooths that away and quietly lies.  So both are shown:
`overall` is every file since this monitor started, `recent` is the last few.  **The two
disagreeing is the signal** -- it means the sweep has just entered or left a slow
stretch, which is usually the thing you actually wanted to know.

HOW IT TRACKS.  The sweeps walk a SORTED file list sequentially, so the file currently
in `bin/ermine`'s argv gives an exact ordinal.  That works for both scripts and needs no
modification to either -- including for a sweep that is ALREADY RUNNING, which is the
case that motivated it.  Completed-output counting is used only as a fallback, since
`ei-diff.sh` has no per-file artifact to count.
"""
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(ROOT) if os.path.basename(ROOT) == "tracker" else ROOT

BAR_W = 42
RECENT_N = 8


def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout
    except Exception:
        return ""


def corpus_list(kind):
    """Reproduce each sweep's own file selection, exactly."""
    if kind == "ei-diff":
        # ei-diff.sh:  find core/examples -name '*.e' | sort
        out = sh("cd %s && find core/examples -name '*.e' | sort" % ROOT)
    else:
        # corpus-run.sh:  core/examples/*.e core/examples/Ai/*.e core/examples/shouldfail/*.e
        out = sh("cd %s && ls -1 core/examples/*.e core/examples/Ai/*.e "
                 "core/examples/shouldfail/*.e 2>/dev/null" % ROOT)
    return [l.strip() for l in out.splitlines() if l.strip()]


def detect():
    """(kind, outdir, side, pid) for whatever sweep is running, or all None.

    `pgrep -af` matches ANY process whose argv contains the pattern, and the shells that
    launch these sweeps carry the whole command -- sometimes this script's own source --
    in their argv.  So a substring match finds three "ei-diff.sh" processes when one is
    running.  Two filters make it exact: the script must be argv[0]-ish (the line starts
    with an optional interpreter then the path), and the captured outdir must EXIST.
    """
    ps = sh("pgrep -af 'ei-diff.sh|corpus-run.sh'")
    pat = re.compile(r"^(\d+)\s+(?:\S*/)?(?:ba)?sh\s+(\S*(ei-diff|corpus-run)\.sh)"
                     r"\s+(?:--incomplete\s+)?(\S+)")
    kind = outdir = pid = None
    for line in ps.splitlines():
        if "sweep-progress" in line:
            continue
        m = pat.match(line)
        if not m or not os.path.isdir(m.group(4)):
            continue
        pid, kind, outdir = m.group(1), m.group(3), m.group(4)
        if kind == "ei-diff":
            break
    side = None
    if kind == "ei-diff" and outdir:
        a, b = os.path.join(outdir, "A"), os.path.join(outdir, "B")
        side = "B" if os.path.isdir(b) else ("A" if os.path.isdir(a) else None)
    return kind, outdir, side, pid


def current_file():
    """The corpus file in flight.

    Read off the JVM's argv rather than the `bin/ermine` wrapper -- the wrapper's own
    launching shell also matches, and so does any shell whose command line merely
    mentions the path (this file's source, for one).  Requiring the extracted path to
    EXIST rejects those regardless of how they arise.  Ai modules are invoked as
    `Common.e <file>`, so the last surviving path is the one being checked.
    """
    ps = sh("pgrep -af 'ermine.session.Console'")
    hits = [h for h in re.findall(r"(core/examples/\S+?\.e)\b", ps)
            if os.path.exists(os.path.join(ROOT, h))]
    return hits[-1] if hits else None


def sweep_elapsed(pid):
    """Seconds since the SWEEP started -- not since this monitor attached.

    Attaching to an already-running sweep is the normal case (that is the whole point),
    so a monitor-relative clock would under-report elapsed while the ETA stayed right,
    which reads as an inconsistency.  `ps -o etimes=` gives the real figure.
    """
    try:
        return int(sh("ps -o etimes= -p %s" % pid).strip())
    except (ValueError, TypeError):
        return None


def fmt(sec):
    if sec is None or sec != sec or sec in (float("inf"),):
        return " --:--"
    sec = int(max(0, sec))
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return "%d:%02d:%02d" % (h, m, s) if h else "%2d:%02d" % (m, s)


def bar(frac, w=BAR_W):
    frac = min(1.0, max(0.0, frac))
    full = int(frac * w)
    part = int((frac * w - full) * 8)
    blocks = " ▏▎▍▌▋▊▉"
    s = "█" * full + (blocks[part] if part and full < w else "")
    return "[" + s.ljust(w, "·") + "]"


def render(state, tty):
    kind, side, done, total, cur, t0, durs, slowest = state
    # ei-diff sweeps the corpus once per side, so run-total is 2x and side B starts
    # from a full side A.  The ETA must count the work left in the RUN, not the side.
    sides = 2 if kind == "ei-diff" else 1
    done_run = done + (total if side == "B" else 0)
    total_run = total * sides
    frac = done_run / total_run if total_run else 0.0
    now = time.time()
    elapsed = now - t0

    overall = sum(durs) / len(durs) if durs else None
    recent = sum(durs[-RECENT_N:]) / len(durs[-RECENT_N:]) if durs else None
    left = total_run - done_run
    eta_o = left * overall if overall else None
    eta_r = left * recent if recent else None

    label = kind + (" side %s" % side if side else "")
    head = "%s  %s %3d%%  %d/%d" % (bar(frac), label, int(frac * 100), done_run, total_run)
    if sides > 1:
        head += " (side %d/%d)" % (done, total)
    pace = "  elapsed %s" % fmt(elapsed)
    if overall:
        pace += "  eta %s (overall %.1fs/f)" % (fmt(eta_o), overall)
        if recent and abs(recent - overall) / overall > 0.20:
            arrow = "▲slower" if recent > overall else "▼faster"
            pace += "  %s recent %s (%.1fs/f)" % (arrow, fmt(eta_r), recent)
    tail = "  » %s" % (cur.replace("core/examples/", "") if cur else "…")
    if slowest:
        tail += "   slowest: " + ", ".join(
            "%s %.0fs" % (n.replace("core/examples/", "").rsplit("/", 1)[-1], d)
            for n, d in slowest[:2])

    line = head + pace + tail
    if tty:
        cols = int(os.environ.get("COLUMNS") or sh("tput cols") or 200)
        sys.stderr.write("\r\033[2K" + line[:cols])
        sys.stderr.flush()
        return line
    # Not a TTY (a log, a pipe, a task file): a repainted bar is one line every poll,
    # so emit only on real movement.  Keeps a 50-minute sweep to ~one line per file.
    key = line.split("elapsed")[0]
    if key != render.last:
        render.last = key
        sys.stderr.write(line + "\n")
        sys.stderr.flush()
    return line


def main():
    once = "--once" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    tty = sys.stderr.isatty()

    kind, outdir, side, pid = detect()
    if not kind:
        sys.stderr.write("no corpus-run.sh or ei-diff.sh is running.\n")
        return 1
    if args:
        outdir = args[0]

    files = corpus_list(kind)
    total = len(files)
    index = {f: i + 1 for i, f in enumerate(files)}

    t0 = time.time()
    durs, slowest = [], []
    last_file, last_t = None, time.time()
    done = 0

    while True:
        k, _, s, pid = detect()
        if not k:
            if tty:
                sys.stderr.write("\r\033[2K")
            sys.stderr.write("sweep finished after %s.\n" % fmt(time.time() - t0))
            return 0
        if k == "ei-diff" and s != side:      # side A -> B: the ordinal restarts
            side = s
            durs, last_file = [], None
        cur = current_file()
        if cur and cur != last_file:
            if last_file is not None:
                d = time.time() - last_t
                durs.append(d)
                slowest.append((last_file, d))
                slowest.sort(key=lambda x: -x[1])
                del slowest[3:]
            last_file, last_t = cur, time.time()
        if cur:
            done = index.get(cur, done)

        render((k, side, done, total, cur,
                time.time() - (sweep_elapsed(pid) or (time.time() - t0)),
                durs, slowest), tty)
        if once:
            sys.stderr.write("\n")
            return 0
        time.sleep(2)


render.last = None

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.stderr.write("\n")
        sys.exit(130)
