#!/usr/bin/env python3
"""Generate adversarial row-constraint modules, to find the solver's cliff.

   tracker/tools/gen-row-stress.py --out /tmp/rowstress --from 2 --to 10
   # then, one JVM per N (a hang at one size must not hide the sizes before it):
   ERMINE_JAVA_OPTS=-Dermine.useInterface=false \\
     timeout 150 bin/ermine /tmp/rowstress/RowStress7.e < /dev/null

WHY THIS EXISTS.  Nothing in the corpus stresses the row-constraint solver --
105 of 129 boot modules produce zero partition constraints and the global
maximum residual is 15 (`lookbackJoin`).  Upstream commit 1213681 (2018,
branch features/limit-row-solving, never merged) added a 50000-step budget and
an exception named `Eternity`, so the blow-up was real once.  To see it you
have to AUTHOR the input, not find it.

THE SHAPE.  `join : (a <- (d,e), b <- (e,f), c <- (d,e,f)) => [..a] -> [..b]
-> [..c]` (Relation.e:259) contributes three partition constraints and three
fresh existentials per call.  Left-nesting N of them feeds each output into the
next input, so the RHS sets overlap WITHOUT being identical -- which is what
fires `resolution` and `commonSubexpression` (Constraints.scala:1021, :1076),
and each of those mints ANOTHER fresh variable that re-enters the worklist and
is compared against everything already processed (`learnPartitions`, :805).
There is no step budget on that loop (`incorporateAll`, :743).

THE DEFINITION MUST NOT BE ANNOTATED.  With a signature the solver checks; the
corpus is annotated almost everywhere, which is why it is quiet.  Inference is
what makes it saturate.
"""
import argparse
import pathlib


def module(n):
    args = " ".join("a%d" % i for i in range(1, n + 1))
    expr = "a1"
    for i in range(2, n + 1):
        expr = "join (%s) a%d" % (expr, i)
    return ("module RowStress%d where\n\nimport Relation\n\nstress %s = %s\n"
            % (n, args, expr))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/rowstress")
    ap.add_argument("--from", dest="lo", type=int, default=2)
    ap.add_argument("--to", dest="hi", type=int, default=10)
    a = ap.parse_args()
    d = pathlib.Path(a.out)
    d.mkdir(parents=True, exist_ok=True)
    for n in range(a.lo, a.hi + 1):
        (d / ("RowStress%d.e" % n)).write_text(module(n))
    print("wrote RowStress%d.e .. RowStress%d.e in %s" % (a.lo, a.hi, d))


if __name__ == "__main__":
    main()
