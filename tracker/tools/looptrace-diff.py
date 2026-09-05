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

The THREAD ID column (stage L4)
  Every compiler record now ends with a thread id (`RowTrace.log`, `t0`/`t1`/...).  The
  MODEL emits no such column, so this script STRIPS it before comparing, and it detects
  its presence from the field count of the `sin` records rather than being told
  (`--thread-column=yes|no|auto`, default `auto`).

  The column also makes the PARALLEL loader segmentable.  `RowTrace.log` synchronises per
  line, not per solve, so under the shipped (parallel) loader two threads solving at once
  interleave their records and a segment split at `sin` alone is a mixture of two solves.
  `--segments` therefore DEMULTIPLEXES first: it partitions the records by their thread id
  and splits each thread's stream at its own `sin` records.  Segments from different
  threads are then interleaved back into the order of their OPENING `sin` record, because
  that is the order `looptrace --replay` -- which reads the same file top to bottom and
  starts a segment at every `sin` -- emits them in.  On a serialized trace (one tracing
  thread) this is exactly the L2 behaviour, byte for byte.  `--per-thread` prints the
  per-thread segment counts.

Usage
  looptrace-diff.py LEAN.tsv SCALA.tsv
  looptrace-diff.py --sweep --lean DIR --scala DIR [--seeds W2,H2,..] [--bases 0-9]
  looptrace-diff.py --segments --lean MODEL.out --scala TRACE.tsv

Exit status is 0 when every comparison agrees.  "Agrees" includes the model's own
cross-checks: a nonzero `#hashdiff` or `#eqdiff` count -- a segment whose records match but
whose `Part.hashCode` / `equals` class the model computed differently -- is a FAILURE here
too, as it already is in `looptrace --replay`'s own exit status (L2 review, F8).
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


# `RowTrace.log` appends a thread id to EVERY record (stage L4).  The model emits none, so
# both the comparison and the id normalisation have to drop it.  Which records carry one is
# decided by the `sin` record's field count -- `sin site loc suLo suHi nCs blk bsz nRows` is
# nine fields, ten with a thread id -- so a trace from either build is read correctly with
# no flag.  Falls back to the `solve` record (ten fields, eleven with a thread id) for a
# fragment that has no `sin`.
SIN_FIELDS = 9
SOLVE_FIELDS = 10


def has_thread_column(lines, forced="auto"):
    """True when these records end with a `RowTrace` thread id."""
    if forced == "yes":
        return True
    if forced == "no":
        return False
    for ln in lines:
        if ln.startswith("sin\t"):
            return len(ln.split("\t")) > SIN_FIELDS
        if ln.startswith("solve\t"):
            return len(ln.split("\t")) > SOLVE_FIELDS
    return False


def drop_tid(ln):
    """A record without its trailing thread-id column."""
    i = ln.rfind("\t")
    return ln[:i] if i >= 0 else ln


def normalise(path):
    """Return the normalised record list of a trace file."""
    with open(path, "r", encoding="utf-8") as fh:
        raw = [ln.rstrip("\n") for ln in fh]
    tid = has_thread_column(raw)
    rows = []
    for ln in raw:
        if not ln:
            continue
        cols = ln.split("\t")
        if cols[0] not in KEEP:
            continue
        if tid:
            cols = cols[:-1]
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


def scala_segments(path, forced="auto"):
    """Split a compiler trace at its `sin` records, PER THREAD.

    Returns (segments, stats) where a segment is (site, loc, records) with `records`
    restricted to the types the model produces and stripped of their thread-id column, and
    `stats` is {thread id: number of segments opened on it}.  Segments appear in the order
    of their opening `sin`, which is the order `looptrace --replay` emits them in.

    Records are attached to the open segment OF THEIR OWN THREAD.  On a serialized trace
    (one tracing thread) that is identical to the L2 behaviour of splitting the file at
    every `sin`.  On a parallel trace it is the difference between a segment and a mixture
    of two solves: `RowTrace.log` synchronises per line, so concurrent solves interleave.
    Records before their thread's first `sin` are dropped."""
    segs = []
    cur = {}
    stats = {}
    tid_col = None if forced == "auto" else (forced == "yes")
    with _open(path) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln:
                continue
            cols = ln.split("\t")
            k = cols[0]
            if k != "sin" and k not in KEEP:
                continue
            if tid_col is None:
                if k == "sin":
                    tid_col = len(cols) > SIN_FIELDS
                elif k == "solve":
                    tid_col = len(cols) > SOLVE_FIELDS
                else:
                    continue          # cannot tell yet, and nothing is open anyway
            t = cols[-1] if tid_col else "-"
            if tid_col:
                ln = drop_tid(ln)
            if k == "sin":
                seg = (cols[1] if len(cols) > 1 else "?",
                       cols[2] if len(cols) > 2 else "-", [])
                cur[t] = seg
                segs.append(seg)
                stats[t] = stats.get(t, 0) + 1
            else:
                seg = cur.get(t)
                if seg is not None:
                    seg[2].append(ln)
    return segs, stats


def demux(path, out_path):
    """Rewrite a trace so that each solve's records are CONTIGUOUS.

    `looptrace --replay` reads a trace top to bottom, opens a segment at every `sin` and
    folds the `slbl`/`svar`/`scon` records that follow into the most recent one -- it has
    no notion of a thread.  A trace written by the PARALLEL loader therefore cannot be fed
    to it directly: two threads solving at once interleave, and the replay reconstructs a
    system the compiler never had (`tracker/loopmodel/L2-CORPUS.md` §8).

    This regroups the file by thread id, emitting each thread's segments WHOLE (in the order
    they complete -- see STREAMING below), and writes the result.  EVERY record type is
    carried through,
    not just the ones the diff compares, because the model's input records (`slbl`, `svar`,
    `scon`) are exactly the ones that were interleaved.  The output is a valid trace with
    the same records in a different order, so the same `--segments` comparison applies to
    it -- and on a serialized trace it is a byte-for-byte copy.

    STREAMING: only the segment currently open on each thread is held, so a 500 MB trace
    costs a few threads' worth of records.  The price is that segments come out in the order
    they COMPLETE rather than the order they opened; that is harmless because both sides of
    the comparison read this same file -- `looptrace --replay` numbers the segments of the
    file it is given, and `--segments` pairs by that index.  On a serialized trace (one
    tracing thread) the two orders coincide and the output is a copy.

    Returns (segments, threads, interleaved, dropped): `interleaved` counts segments whose
    records were NOT already contiguous in the input, i.e. exactly what the parallel loader
    breaks and this repairs; `dropped` counts records that preceded their thread's first
    `sin`."""
    cur = {}            # thread id -> the segment currently open on it
    dropped = 0
    nseg = 0
    interleaved = 0
    threads = set()
    tid_col = None
    prev = None         # the segment the PREVIOUS record of the file belonged to
    oh = open(out_path, "w", encoding="utf-8")

    def flush(seg):
        nonlocal interleaved
        if not seg["contig"]:
            interleaved += 1
        for r in seg["recs"]:
            oh.write(r + "\n")

    try:
        with _open(path) as fh:
            for ln in fh:
                ln = ln.rstrip("\n")
                if not ln:
                    continue
                cols = ln.split("\t")
                k = cols[0]
                if tid_col is None:
                    if k == "sin":
                        tid_col = len(cols) > SIN_FIELDS
                    elif k == "solve":
                        tid_col = len(cols) > SOLVE_FIELDS
                if tid_col is None:
                    dropped += 1
                    continue
                t = cols[-1] if tid_col else "-"
                if k == "sin":
                    # This thread's previous solve is complete: write it out and forget it.
                    old = cur.get(t)
                    if old is not None:
                        flush(old)
                    seg = {"recs": [ln], "contig": True}
                    cur[t] = seg
                    threads.add(t)
                    nseg += 1
                else:
                    seg = cur.get(t)
                    if seg is None:
                        dropped += 1
                        prev = None
                        continue
                    seg["recs"].append(ln)
                    # Another thread wrote between two of this segment's records: the input
                    # was interleaved here, and this is a segment the regrouping repairs.
                    if prev is not None and prev is not seg:
                        seg["contig"] = False
                prev = seg
        for t in sorted(cur):
            flush(cur[t])
    finally:
        oh.close()
    return nseg, len(threads), interleaved, dropped


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


def segments_main(lean_path, scala_path, report=None, show=3, forced="auto",
                  per_thread=False):
    sc, tstats = scala_segments(scala_path, forced)
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
    out.append("threads: %d  %s" % (len(tstats), " ".join(
        "%s=%d" % (t, tstats[t]) for t in sorted(tstats)) if per_thread else ""))
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
    # L2 review F8: `hashdiff` / `eqdiff` are model-vs-compiler disagreements too -- a
    # segment whose records match but whose `Part.hashCode` or `equals` class the model got
    # wrong.  `looptrace --replay` already exits non-zero on them; this now agrees.
    bad = sum(v for k, v in classes.items()) + hashdiff + eqdiff
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
    ap.add_argument("--demux", default=None,
                    help="regroup a trace so each solve's records are contiguous "
                         "(--demux RAW.tsv --out DEMUX.tsv); needed before `looptrace "
                         "--replay` on a trace written by the PARALLEL loader")
    ap.add_argument("--out", default=None)
    ap.add_argument("--thread-column", default="auto", choices=("auto", "yes", "no"),
                    dest="thread_column")
    ap.add_argument("--per-thread", action="store_true", dest="per_thread")
    ap.add_argument("--seeds", default="W2,H2,NE6,W3,W4,G7")
    ap.add_argument("--bases", default="0-9")
    args = ap.parse_args()

    if args.demux:
        if not args.out:
            ap.error("--demux needs --out DEMUX.tsv")
        nseg, nthr, inter, drop = demux(args.demux, args.out)
        print("demux: segments=%d threads=%d interleaved=%d dropped-records=%d -> %s"
              % (nseg, nthr, inter, drop, args.out))
        return 0

    if args.segments:
        if not (args.lean and args.scala):
            ap.error("--segments needs --lean MODEL.out --scala TRACE.tsv")
        return segments_main(args.lean, args.scala, args.report, args.show,
                             args.thread_column, args.per_thread)

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
