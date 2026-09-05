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

Segment mode (stage L2)
  looptrace-diff.py --segments --lean MODEL.out --scala TRACE.tsv [--report FILE] [--show N]

  A corpus trace holds MANY solves.  `RowTrace`'s `sin` record opens each one, so the
  compiler side splits there; the model side, `looptrace --replay`, prints a `#seg <i>`
  line per solve in the same order.  Segments are paired by index and compared RAW -- no
  id normalisation, because a replay runs at the compiler's own ids and its records should
  be byte-identical.  Each pair is classified AGREE, or by the record TYPE at which it
  first differs (`step`, `learn`, `inpart`, `sat`, `solve`, `length`), and per-class
  examples are printed.

Usage
  looptrace-diff.py LEAN.tsv SCALA.tsv
  looptrace-diff.py --sweep --lean DIR --scala DIR [--seeds W2,H2,..] [--bases 0-9]
  looptrace-diff.py --segments --lean MODEL.out --scala TRACE.tsv

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


# ---------------------------------------------------------------------------
# Segment mode
# ---------------------------------------------------------------------------

def _open(path):
    if path.endswith(".gz"):
        import gzip
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, "r", encoding="utf-8", errors="replace")


def scala_segments(path):
    """Split a compiler trace at its `sin` records.

    Returns a list of (site, loc, records) with `records` restricted to the types the
    model produces, in file order.  Records before the first `sin` (there are none in a
    trace taken with this build) are dropped."""
    segs = []
    cur = None
    with _open(path) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln:
                continue
            cols = ln.split("\t")
            k = cols[0]
            if k == "sin":
                cur = (cols[1] if len(cols) > 1 else "?",
                       cols[2] if len(cols) > 2 else "-", [])
                segs.append(cur)
            elif k in KEEP and cur is not None:
                cur[2].append(ln)
    return segs


def lean_segments(path):
    """Split `looptrace --replay` output at its `#seg` markers.

    Returns (segments, summary) where a segment is (index, site, loc, records, note);
    `note` is the `#skip`/`#REJECTED`/`#FUEL` line's reason, or None."""
    segs = []
    summary = ""
    cur = None
    with _open(path) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln:
                continue
            cols = ln.split("\t")
            k = cols[0]
            if k == "#seg":
                cur = {"i": int(cols[1]), "site": cols[2] if len(cols) > 2 else "?",
                       "loc": cols[3] if len(cols) > 3 else "-", "recs": [], "note": None,
                       "hashdiff": 0, "eqdiff": 0}
                segs.append(cur)
            elif k == "#skip" and cur is not None:
                cur["note"] = "skip: " + (cols[2] if len(cols) > 2 else "?")
            elif k == "#hashdiff" and cur is not None:
                cur["hashdiff"] = int(cols[2]) if len(cols) > 2 else 1
            elif k == "#eqdiff" and cur is not None:
                cur["eqdiff"] = int(cols[2]) if len(cols) > 2 else 1
            elif k in ("#REJECTED", "#FUEL") and cur is not None:
                cur["note"] = k[1:] + ": " + (cols[2] if len(cols) > 2 else "")
            elif k == "#summary":
                summary = ln
            elif k in KEEP and cur is not None:
                cur["recs"].append(ln)
    return segs, summary


def classify(lean_recs, scala_recs):
    """AGREE, or (class, i, lean record, scala record)."""
    n = min(len(lean_recs), len(scala_recs))
    for i in range(n):
        if lean_recs[i] != scala_recs[i]:
            return (lean_recs[i].split("\t")[0], i, lean_recs[i], scala_recs[i])
    if len(lean_recs) != len(scala_recs):
        if len(lean_recs) > len(scala_recs):
            return ("length+", n, lean_recs[n], "<none>")
        return ("length-", n, "<none>", scala_recs[n])
    return None


def segments_main(lean_path, scala_path, report=None, show=3):
    sc = scala_segments(scala_path)
    ln, summary = lean_segments(lean_path)
    out = []
    classes = {}
    examples = {}
    agree = 0
    skipped = 0
    hashdiff = 0
    eqdiff = 0
    n = min(len(sc), len(ln))
    for i in range(n):
        site, loc, srecs = sc[i]
        lseg = ln[i]
        hashdiff += 1 if lseg["hashdiff"] else 0
        eqdiff += 1 if lseg["eqdiff"] else 0
        if lseg["note"] and lseg["note"].startswith("skip"):
            skipped += 1
            classes["SKIP"] = classes.get("SKIP", 0) + 1
            examples.setdefault("SKIP", []).append((i, site, loc, lseg["note"], ""))
            continue
        c = classify(lseg["recs"], srecs)
        if c is None:
            agree += 1
        else:
            cls, j, a, b = c
            classes[cls] = classes.get(cls, 0) + 1
            examples.setdefault(cls, []).append((i, site, loc, a, b))
    out.append("segments: scala=%d lean=%d compared=%d" % (len(sc), len(ln), n))
    out.append("AGREE   %d" % agree)
    out.append("SKIP    %d" % skipped)
    out.append("hashdiff segments: %d" % hashdiff)
    out.append("eqdiff segments: %d" % eqdiff)
    if len(sc) != len(ln):
        out.append("!! segment COUNT differs (scala %d, lean %d)" % (len(sc), len(ln)))
    for cls in sorted(classes):
        out.append("class %-8s %d" % (cls, classes[cls]))
    for cls in sorted(examples):
        for (i, site, loc, a, b) in examples[cls][:show]:
            out.append("  [%s] seg %d  %s  %s" % (cls, i, site, loc))
            out.append("      lean : %s" % a)
            out.append("      scala: %s" % b)
    out.append(summary)
    text = "\n".join(out)
    print(text)
    if report:
        with open(report, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    bad = sum(v for k, v in classes.items())
    return 0 if bad == 0 and len(sc) == len(ln) else 1


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
    ap.add_argument("--segments", action="store_true")
    ap.add_argument("--report", default=None)
    ap.add_argument("--show", type=int, default=3)
    ap.add_argument("--lean", default=None)
    ap.add_argument("--scala", default=None)
    ap.add_argument("--seeds", default="W2,H2,NE6,W3,W4,G7")
    ap.add_argument("--bases", default="0-9")
    args = ap.parse_args()

    if args.segments:
        if not (args.lean and args.scala):
            ap.error("--segments needs --lean MODEL.out --scala TRACE.tsv")
        return segments_main(args.lean, args.scala, args.report, args.show)

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
