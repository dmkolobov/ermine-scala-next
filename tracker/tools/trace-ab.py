#!/usr/bin/env python3
"""Diff two COMPILER row traces of the same corpus group, segment by segment.

    tracker/tools/trace-ab.py <A.tsv[.gz]> <B.tsv[.gz]> [--name N] [--show K]

`looptrace-diff.py` compares the LEAN MODEL against the compiler; this compares two
compiler runs of two BUILDS (or of one build, as a noise-floor control).  Both traces are
split at their `sin` records and the segments are paired by index.

WHAT IT COMPARES, AND WHY THAT MATTERS.  Every record and every field, with exactly one
mask: `rsound ok`'s second-to-last field is the wall-clock microseconds the S2 per-label
check spent (`Subst.scala`), which differs between any two runs of one binary.  This is
the correction the F3 review made (finding N-1): the first version of this script inherited
`looptrace-diff.py`'s `KEEP` tuple and compared **six of the sixteen** record kinds a corpus
trace carries -- it never looked at `slbl`, `svar`, `scon`, `ex`, `concr`, `splice`, `detm`,
`ramb` or `rsound`, and of `sin` it read only the constraint count -- so it reported 8
differing segments where a full comparison finds 402, and it could not see either R3's
determinacy record or the `Supply` bounds.  Do not narrow it again: the records a change is
NOT expected to touch are the ones that make the result evidence.

CLASSIFICATION of a differing pair:
  PERMUTATION-ONLY   the same multiset of records once every numeric id (3+ digits) is
                     erased, and the same count of each record kind -- an ordering and a
                     renaming, no new or lost fact;
  CONTENT-DIFFERS    the record multiset itself moved (a field's value changed);
  KINDCOUNT-DIFFERS  one side has more records of some kind than the other.

`sin` bounds are compared separately and reported as `sinmoved`: a segment whose `Supply`
low/high bound differs is one where the id base really did move, which is the claim
`ROW-CONSTRAINT-STATE.md` warns must be measured rather than assumed.

`ident` counts, for information, the concrete-identity INPUT constraints in the A trace: an
`in` record whose lhs is a concrete row and whose single rhs part is the same concrete row.
That is the shape `Type.Part.apply`'s guard collapses -- but note that most collapses never
reach a `solve` at all, so a zero here does NOT mean the guard is dead (F3 review, N-1).

Exit status is 0 when every pair is IDENTICAL and no `sin` bound moved.
"""
import sys, re, gzip, argparse, itertools
from collections import Counter

NUM = re.compile(r"\d{3,}")
CONCRETE = re.compile(r"^\(\|[^|]*\|\)$")


def op(p):
    return gzip.open(p, "rt", encoding="utf-8", errors="replace") if p.endswith(".gz") \
        else open(p, "r", encoding="utf-8", errors="replace")


def segments(path):
    """Yield (loc, sin_fields, [records]) one segment at a time.

    A GENERATOR on purpose: `incomplete` is 1.9 M segments and holding them all costs
    gigabytes.  Two segments are ever live."""
    cur = None
    with op(path) as fh:
        for ln in fh:
            c = ln.rstrip("\n").split("\t")
            # `rsound ok <a> <b> <c> <micros> [tid]`: drop the micros, keep the rest
            if c[0] == "rsound" and len(c) > 3 and c[3] == "ok":
                c = c[:-2] + [c[-1]]
            if c[0] == "sin":
                if cur is not None:
                    yield cur
                cur = (c[2], c[3:], [c])
            elif cur is not None:
                cur[2].append(c)
    if cur is not None:
        yield cur


def is_identity(lhs, rhs):
    return lhs == rhs and CONCRETE.match(lhs) is not None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a"); ap.add_argument("b")
    ap.add_argument("--name", default="")
    ap.add_argument("--show", type=int, default=0)
    ap.add_argument("--locs", action="store_true",
                    help="print the loc of every differing segment")
    o = ap.parse_args()

    cls, shown, ident_a, sinmoved, n = Counter(), 0, 0, 0, 0
    unpaired, locs = "", []
    for i, (sa, sb) in enumerate(itertools.zip_longest(segments(o.a), segments(o.b))):
        if sa is None or sb is None:
            unpaired = "SEGMENT COUNT DIFFERS (one side ran out at index %d)" % i
            break
        n += 1
        la, lb = sa[2], sb[2]
        ident_a += sum(1 for c in la
                       if c[0] == "in" and len(c) > 5 and is_identity(c[4], c[5]))
        if sa[1] != sb[1]:
            sinmoved += 1
        ta = ["\t".join(c) for c in la]
        tb = ["\t".join(c) for c in lb]
        if ta == tb:
            cls["IDENTICAL"] += 1
            continue
        ka = Counter(c[0] for c in la); kb = Counter(c[0] for c in lb)
        ma = Counter(NUM.sub("#", x) for x in ta); mb = Counter(NUM.sub("#", x) for x in tb)
        if ka != kb:
            k = "KINDCOUNT-DIFFERS"
        elif ma == mb:
            k = "PERMUTATION-ONLY"
        else:
            k = "CONTENT-DIFFERS"
        cls[k] += 1
        locs.append((i, k, sa[0]))
        if shown < o.show:
            shown += 1
            print("  --- %s segment %d  %s" % (k, i, sa[0]))
            for x in (ma - mb).elements():
                print("      only-A: " + x)
            for x in (mb - ma).elements():
                print("      only-B: " + x)
    if unpaired:
        print("%-20s %s" % (o.name, unpaired))
    if o.locs:
        for i, k, l in locs:
            print("  %-18s %8d  %s" % (k, i, l))
    print("%-20s segments=%-8d %s  sinmoved=%d  (concrete identities in A: %d)"
          % (o.name, n, "  ".join("%s=%d" % kv for kv in sorted(cls.items())),
             sinmoved, ident_a))
    bad = n - cls["IDENTICAL"]
    return 0 if bad == 0 and sinmoved == 0 and not unpaired else 1


sys.exit(main())
