#!/usr/bin/env python3
r"""Generate row-constraint probes that isolate WHY the solver blows up.

   tracker/tools/gen-row-overlap.py --out /tmp/rowprobe
   # then, one JVM per module (a slow one must not hide the others):
   ERMINE_JAVA_OPTS=-Dermine.useInterface=false \\
     timeout 400 bin/ermine /tmp/rowprobe/CoStar7.e < /dev/null

WHY THIS EXISTS.  `gen-row-stress.py` shows THAT the solver falls off a cliff on
N chained joins.  It does not isolate WHAT drives the cost, and its shape
conflates three things: the number of constraints, the number of row variables,
and how much the constraint right-hand sides overlap.  These probes vary one at a
time.  Measurements and analysis: tracker/TICKET-row-constraint-decision.md §2.3.

THE ANSWER THEY GIVE (measured 2026-08-31, one JVM per module):

  Chain8       8 join calls sharing NO row variables    24 constraints   0.05s
  Overlap1     x_i <- (b_i, c)        pairwise cap = 1   8 constraints   0.03s
  Overlap2     x_i <- (b_i, c, d)     pairwise cap = 2   8 constraints   0.05s
  OverlapHalf  8 distinct 4-subsets of 8                 8 constraints   0.07s
  PartStar4    4 co-stars over a ground set of 8         4 constraints   0.11s
  PartStar5    5 co-stars over a ground set of 8         5 constraints   0.60s
  PartStar6    6 co-stars over a ground set of 8         6 constraints   9.16s
  CoStar7      7 co-stars over a ground set of 7         7 constraints   6.38s
  CoStar8      8 co-stars over a ground set of 8         8 constraints 175.68s

So cost is NOT the constraint count -- 24 non-overlapping constraints cost 0.05s
while 8 overlapping ones cost 175s -- and NOT the overlap size on its own, since
OverlapHalf overlaps by 3 and stays at 0.07s.  It is the size of the MEET-
SEMILATTICE THE RIGHT-HAND SIDES GENERATE UNDER INTERSECTION.  `commonSubexpression`
(Constraints.scala:1076) names each distinct intersection with a FRESH variable
that re-enters the worklist and is compared against everything already processed.
The m co-star sets B\{b_i} generate the whole subset lattice, so that is 2^m
names.  PartStar holds the ground set fixed at 8 and varies only how many
co-stars are present: the exponent tracks k, not the ground-set size.

AND THE POINT: on these inputs the solver's RETAINED RESIDUAL IS ITS OWN INPUT,
verbatim -- CoStar8 is handed 8 constraints and returns those same 8 after 175
seconds, because Subst.reduce keeps only ambiguous/existential left-hand sides
and discards the entire saturation.  Check with:

   printf ':browse\\n:quit\\n' | ERMINE_JAVA_OPTS=-Dermine.useInterface=false \\
     bin/ermine /tmp/rowprobe/CoStar6.e | tr '\\r' '\\n' | grep -A12 '^probe : '

THE DEFINITION MUST NOT BE ANNOTATED.  An annotated signature carrying the same
constraints checks in 0.02-0.03s; the blow-up needs INFERENCE.  That is why every
probe puts the constrained calls in an unannotated `probe`.
"""
import argparse
import itertools
import pathlib

PRELUDE = "module %s where\n\nimport Relation\n\n"


def helper(arity, name="g"):
    """A single partition constraint  x <- (a0, .., a{arity-1})  as a function."""
    args = ",".join("a%d" % i for i in range(arity))
    sig = " ".join("Relation a%d ->" % i for i in range(arity))
    holes = " ".join("_" for _ in range(arity + 1))
    return ("%s : (x <- (%s)) => Relation x -> %s Int\n%s %s = 0\n"
            % (name, args, sig, name, holes))


def probe(name, rhss, ground, arity):
    """One unannotated definition applying `g` once per element of rhss."""
    calls = ", ".join("g x%d %s" % (i, " ".join(r)) for i, r in enumerate(rhss))
    args = " ".join("x%d" % i for i in range(len(rhss))) + " " + " ".join(ground)
    return PRELUDE % name + helper(arity) + "\nprobe %s = (%s)\n" % (args, calls)


def costar(m):
    """x_i <- (every b except b_i).  Generates the full 2^m subset lattice."""
    bs = ["b%d" % i for i in range(m)]
    rhss = [[b for j, b in enumerate(bs) if j != i] for i in range(m)]
    return probe("CoStar%d" % m, rhss, bs, m - 1)


def partstar(k, m=8):
    """Only k of the m co-stars, over a FIXED ground set: isolates the exponent."""
    bs = ["b%d" % i for i in range(m)]
    rhss = [[b for j, b in enumerate(bs) if j != i] for i in range(k)]
    return probe("PartStar%d" % k, rhss, bs, m - 1)


def overlap(n, shared, m=8):
    """x_i <- (b_i, c0 .. c{shared-1}): every pair overlaps in the SAME `shared`
    variables, so the intersection lattice has one element."""
    bs = ["b%d" % i for i in range(m)]
    cs = ["c%d" % i for i in range(shared)]
    rhss = [[b] + cs for b in bs]
    return probe("Overlap%d" % shared, rhss, bs + cs, shared + 1)


def overlaphalf(m=8, size=4):
    """m distinct size-subsets of the ground set, in lexicographic order: large
    overlaps, but a SMALL intersection lattice (they share a common prefix)."""
    bs = ["b%d" % i for i in range(m)]
    rhss = [list(s) for s in itertools.islice(itertools.combinations(bs, size), m)]
    return probe("OverlapHalf", rhss, bs, size)


def chain(m):
    """m join calls sharing NO row variables: 3m constraints, zero overlap.
    The control that shows constraint COUNT is not what costs."""
    h = ("j : (a <- (d,e), b <- (e,f), c <- (d,e,f))"
         " => Relation a -> Relation b -> Relation c -> Int\nj _ _ _ = 0\n")
    calls = ", ".join("j p%d q%d r%d" % (i, i, i) for i in range(m))
    args = " ".join("%s%d" % (v, i) for i in range(m) for v in "pqr")
    return PRELUDE % ("Chain%d" % m) + h + "\nprobe %s = (%s)\n" % (args, calls)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/rowprobe")
    ap.add_argument("--costar-to", type=int, default=8,
                    help="largest co-star; 8 takes ~3 minutes, 9 is hours")
    a = ap.parse_args()
    d = pathlib.Path(a.out)
    d.mkdir(parents=True, exist_ok=True)

    written = []
    for m in range(3, a.costar_to + 1):
        (d / ("CoStar%d.e" % m)).write_text(costar(m))
        written.append("CoStar%d" % m)
    for k in range(4, 7):
        (d / ("PartStar%d.e" % k)).write_text(partstar(k))
        written.append("PartStar%d" % k)
    for shared in (1, 2):
        (d / ("Overlap%d.e" % shared)).write_text(overlap(8, shared))
        written.append("Overlap%d" % shared)
    (d / "OverlapHalf.e").write_text(overlaphalf())
    written.append("OverlapHalf")
    for m in (4, 8):
        (d / ("Chain%d.e" % m)).write_text(chain(m))
        written.append("Chain%d" % m)

    print("wrote %d modules to %s:\n  %s" % (len(written), d, " ".join(written)))
    print("\ntime them one JVM each, e.g.:\n"
          "  for f in %s/*.e; do ERMINE_JAVA_OPTS=-Dermine.useInterface=false \\\n"
          "    timeout 400 bin/ermine $f </dev/null 2>&1 | tr '\\r' '\\n' |\n"
          "    grep -o \"Importing module '[^']*' ([0-9.]* seconds)\"; done" % d)


if __name__ == "__main__":
    main()
