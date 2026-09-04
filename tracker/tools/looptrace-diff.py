#!/usr/bin/env python3
"""Differential test: the Lean loop model against the compiler, record for record.

Both sides emit `RowTrace`'s TSV (`-Dermine.rowTrace=<file>` on the compiler,
`lake exe looptrace` on the model).  The two are not textually comparable as they
stand: the id base shifts every variable's id, and the compiler's file also carries
records from `Subst.reduce`, which the L1 model does not cover.  This script
normalises both and diffs them.

Normalisation
  * keep only the record types the model produces: step, learn, in, inpart, sat, solve;
    drop `concr` and `splice` (they come from `reduce`, after the loop) and `ex`;
  * drop the site column, which names the seed file and the base;
  * rewrite every variable id to the position of its FIRST OCCURRENCE in the file, so
    two runs at different bases normalise to the same text.  The three id syntaxes are
    `^free<id>` (an input variable), `^ambiguous(free)<id>` (a mint) and `<name>^<id>`
    (the population records' `sv`), plus the `common:<id>` / `unify:<id>` branch tags;
  * labels are already names (`Repro.l7`), so nothing to do.

Usage
  looptrace-diff.py LEAN.tsv SCALA.tsv
  looptrace-diff.py --sweep --lean DIR --scala DIR [--seeds W2,H2,..] [--bases 0-9]

Exit status is 0 when every comparison agrees.
"""

import argparse
import os
import re
import sys

KEEP = ("step", "learn", "in", "inpart", "sat", "solve")

_PATTERNS = [
    (re.compile(r"\^ambiguous\(free\)(\d+)"), "A"),
    (re.compile(r"\^free(\d+)"), "F"),
    (re.compile(r"\b(common|unify):(\d+)"), "B"),
    (re.compile(r"([A-Za-z][A-Za-z0-9]*)?\^(\d+)"), "S"),
]


def normalise(path):
    """Return the normalised record list of a trace file."""
    with open(path, "r", encoding="utf-8") as fh:
        raw = [ln.rstrip("\n") for ln in fh]
    rows = []
    for ln in raw:
        if not ln:
            continue
        cols = ln.split("\t")
        if cols[0] not in KEEP:
            continue
        # drop the site column
        rows.append("\t".join([cols[0]] + cols[2:]))

    ids = {}

    def rank(raw_id):
        if raw_id not in ids:
            ids[raw_id] = len(ids)
        return ids[raw_id]

    out = []
    for row in rows:
        # `^ambiguous(free)N` and `^freeN`
        def sub_a(m):
            return "^A" + str(rank(m.group(1)))

        def sub_f(m):
            return "^F" + str(rank(m.group(1)))

        def sub_b(m):
            return m.group(1) + ":#" + str(rank(m.group(2)))

        def sub_s(m):
            return (m.group(1) or "") + "^#" + str(rank(m.group(2)))

        row = _PATTERNS[0][0].sub(sub_a, row)
        row = _PATTERNS[1][0].sub(sub_f, row)
        row = _PATTERNS[2][0].sub(sub_b, row)
        row = _PATTERNS[3][0].sub(sub_s, row)
        out.append(row)
    return out


def compare(lean_path, scala_path):
    """Return (ok, message)."""
    a = normalise(lean_path)
    b = normalise(scala_path)
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return False, (
                "first mismatch at normalised record %d\n"
                "  lean : %s\n"
                "  scala: %s" % (i, a[i], b[i])
            )
    if len(a) != len(b):
        longer, extra = ("lean", a[n:]) if len(a) > len(b) else ("scala", b[n:])
        return False, (
            "prefixes agree for %d records; %s has %d more, first is\n  %s"
            % (n, longer, len(extra), extra[0])
        )
    return True, "%d records agree" % len(a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--sweep", action="store_true")
    ap.add_argument("--lean", default=None)
    ap.add_argument("--scala", default=None)
    ap.add_argument("--seeds", default="W2,H2,NE6,W3,W4,G7")
    ap.add_argument("--bases", default="0-9")
    args = ap.parse_args()

    if not args.sweep:
        if len(args.files) != 2:
            ap.error("give LEAN.tsv SCALA.tsv, or --sweep")
        ok, msg = compare(args.files[0], args.files[1])
        print(("AGREE  " if ok else "DIFFER ") + msg)
        return 0 if ok else 1

    if args.bases.count("-") == 1:
        lo, hi = args.bases.split("-")
        bases = list(range(int(lo), int(hi) + 1))
    else:
        bases = [int(x) for x in args.bases.split(",")]
    seeds = args.seeds.split(",")

    bad = 0
    width = max(len(s) for s in seeds)
    print("seed".ljust(width) + " | " + " ".join("%4d" % b for b in bases))
    print("-" * (width + 3 + 5 * len(bases)))
    details = []
    for s in seeds:
        cells = []
        for b in bases:
            lp = os.path.join(args.lean, "%s-%d.tsv" % (s, b))
            sp = os.path.join(args.scala, "%s-%d.tsv" % (s, b))
            if not (os.path.exists(lp) and os.path.exists(sp)):
                cells.append("   ?")
                bad += 1
                details.append("%s@%d: missing trace file" % (s, b))
                continue
            ok, msg = compare(lp, sp)
            cells.append("  ok" if ok else " DIF")
            if not ok:
                bad += 1
                details.append("%s@%d: %s" % (s, b, msg))
        print(s.ljust(width) + " | " + " ".join("%4s" % c for c in cells))
    print()
    if details:
        for d in details:
            print(d)
        print("\n%d disagreements" % bad)
    else:
        print("all %d comparisons agree" % (len(seeds) * len(bases)))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
