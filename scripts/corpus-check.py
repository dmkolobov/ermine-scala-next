#!/usr/bin/env python3
"""Compare a corpus-run.sh output directory with the checked-in expected verdicts.

    scripts/corpus-check.py <outdir> tracker/corpus-verdicts.expected            # compare
    scripts/corpus-check.py <outdir> tracker/corpus-verdicts.expected --write    # re-record

The expected file holds one line per corpus module: `<out file>\t<LOADED|REJECTED>\t<message>`,
where message is the refusal line corpus-verdicts.py extracts, with the checkout path normalised
(so every worktree records the same text).  The comparison fails on ANY difference: a verdict that
flips, a refusal that now says something else, a module that appears, disappears or is UNKNOWN.
Re-recording is for an INTENDED change and belongs in the same commit, with the diff in its message.
"""
import os
import re
import sys

sys.dont_write_bytecode = True  # never leave __pycache__ in tracker/tools

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tracker", "tools"))
import importlib.util

spec = importlib.util.spec_from_file_location(
    "corpus_verdicts", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tracker", "tools", "corpus-verdicts.py"))
cv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cv)

CHECKOUT = re.compile(r"/[^\s:]*/ermine-scala[^/\s:]*/")


def norm(msg):
    return CHECKOUT.sub("<checkout>/", msg).strip()


def main():
    if len(sys.argv) < 3 or sys.argv[1] in ("-h", "--help"):
        print(__doc__); return 2
    got = {k: (v, norm(m)) for k, (v, m) in cv.read(sys.argv[1]).items()}
    if not got:
        print("SUMMARY no .out files in %s" % sys.argv[1]); return 1
    if "--write" in sys.argv[3:]:
        with open(sys.argv[2], "w") as f:
            for k in sorted(got):
                f.write("%s\t%s\t%s\n" % (k, got[k][0], got[k][1]))
        print("SUMMARY recorded %d modules" % len(got)); return 0
    want = {}
    for line in open(sys.argv[2]):
        k, v, m = (line.rstrip("\n").split("\t") + ["", ""])[:3]
        want[k] = (v, m)
    diffs = 0
    for k in sorted(set(got) | set(want)):
        a, b = want.get(k, ("MISSING", "")), got.get(k, ("MISSING", ""))
        if a != b:
            diffs += 1
            if a[0] != b[0]:
                print("VERDICT %s: expected %s, got %s" % (k, a[0], b[0]))
            else:
                print("MESSAGE %s:\n  expected: %s\n  got:      %s" % (k, a[1], b[1]))
    n = lambda s: sum(1 for v, _ in got.values() if v == s)
    print("SUMMARY %d loaded / %d rejected / %d unknown of %d; %d differ from expected"
          % (n("LOADED"), n("REJECTED"), n("UNKNOWN"), len(got), diffs))
    return 1 if diffs or n("UNKNOWN") else 0


if __name__ == "__main__":
    sys.exit(main())
