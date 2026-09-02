#!/usr/bin/env python3
"""Classify a `corpus-run.sh` output directory as LOADED / REJECTED per file, and diff two.

    tracker/tools/corpus-verdicts.py /tmp/corpus-A
    tracker/tools/corpus-verdicts.py /tmp/corpus-A /tmp/corpus-B

WHY IT EXISTS.  `bin/ermine` exits 0 whether or not the module loaded -- it prints
"Unable to load module" and then reads EOF from stdin and quits cleanly -- so the exit
code recorded in `verdicts.txt` distinguishes only timeouts.  The verdict a gate cares
about ("did this shouldfail/ module stay rejected?") has to be read out of the output.
"""
import pathlib
import re
import sys

LOADED = re.compile(r"Importing module '([^']+)'")
FAILED = re.compile(r"Unable to load module")


def verdict(path):
    text = path.read_text(errors="replace")
    # the 129-module boot prints nothing per module; only the files named on the command
    # line produce "Importing module" / "Unable to load module".
    if FAILED.search(text):
        # first non-boot error line, for the message comparison
        msgs = [l for l in text.splitlines()
                if l.strip() and not l.startswith("[") and ": " in l and ".e:" in l]
        return "REJECTED", (msgs[-1] if msgs else "")
    if LOADED.search(text):
        return "LOADED", ""
    return "UNKNOWN", ""


def read(d):
    out = {}
    for f in sorted(pathlib.Path(d).glob("*.out")):
        out[f.name] = verdict(f)
    return out


def main():
    a = read(sys.argv[1])
    if len(sys.argv) == 2:
        for k, (v, m) in a.items():
            print("%-9s %s%s" % (v, k, ("   " + m) if m else ""))
        n = sum(1 for v, _ in a.values() if v == "LOADED")
        print("\n%d LOADED, %d REJECTED, %d UNKNOWN, %d total"
              % (n, sum(1 for v, _ in a.values() if v == "REJECTED"),
                 sum(1 for v, _ in a.values() if v == "UNKNOWN"), len(a)))
        return 0
    b = read(sys.argv[2])
    # an all-UNKNOWN side means the runs produced nothing (a missing PATH, a bad
    # classpath); comparing them yields a meaningless "0 differ" (2026-09-02)
    for name, d in ((sys.argv[1], a), (sys.argv[2], b)):
        if d and all(v == "UNKNOWN" for v, _ in d.values()):
            print("REFUSING TO COMPARE: every run in %s is UNKNOWN -- those invocations\n"
                  "produced neither 'Importing module' nor 'Unable to load module'.\n"
                  "Check the .out files before reading anything into a diff." % name)
            return 2
    changed = 0
    for k in sorted(set(a) | set(b)):
        va, ma = a.get(k, ("MISSING", ""))
        vb, mb = b.get(k, ("MISSING", ""))
        if va != vb:
            changed += 1
            print("VERDICT %-9s -> %-9s  %s" % (va, vb, k))
        elif ma != mb:
            changed += 1
            print("MESSAGE %s\n    A: %s\n    B: %s" % (k, ma, mb))
    print("\n%d of %d files differ" % (changed, len(set(a) | set(b))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
