#!/usr/bin/env python3
r"""Generate row-constraint probes that make `resolution` fire.

   tracker/tools/gen-res-star.py --out /tmp/resprobe
   # one JVM per module, always:
   ERMINE_JAVA_OPTS="-Dermine.useInterface=false" timeout 300 \
     bin/ermine /tmp/resprobe/ResStar5.e < /dev/null

WHY THIS EXISTS.  `gen-row-overlap.py` isolates the cost of `commonSubexpression`
(the co-star family, cut by `-Dermine.genRules=cut`).  It says nothing about
`resolution`, because none of its probes carries a concrete label, and
`resolution` matches only `RHS(Single(x), concr)` -- two partitions of the SAME
variable, each with exactly one variable part, whose concrete parts are
incomparable (`tops` and `bots` both nonempty, Constraints.scala `def
resolution`).  Ticket §7.9 measured that `resolution` never fires once in a
129-module stdlib boot, so the stdlib cannot be used to measure a change to it.
These probes are the population that can.

THE FAMILY.

  ResStar<m>   a <- (x_i, (|f_i|))  for i = 0 .. m-1, all on the SAME `a`,
               with m distinct field labels.

  SATISFIABLE, and obviously so: take `a = {f_0..f_{m-1}}` and `x_i = a \ {f_i}`.
  It is the ordinary shape "m different single-column projections of one
  relation".  Every pair (i, j) has incomparable concrete parts, so `resolution`
  fires on all m(m-1)/2 of them, and each firing adds `a <- (z, {f_i, f_j})`,
  whose pairs with the others are incomparable again.  The concrete parts
  therefore generate the whole subset lattice of the m labels on the left-hand
  side `a` -- the same 2^m phenomenon `commonSubexpression` produces on the
  co-star, reached through the other minting rule.

  UNGUARDED, one fresh variable is minted per FIRING; guarded
  (`-Dermine.resGuard=true`), at most one per distinct label SET, because the
  reverse lookup finds the resolvent `a <- (z, K)` the previous firing left
  behind.  The difference is the point of the measurement.

  Gadget      a <- (p, (|f0|)), a <- (q, (|f1|)),
              b <- (p, (|f2|)), b <- (q, (|f3|))

  UNSATISFIABLE (`Rowpartition.ResGuardDiverge.gSeed_unsat`), and the guarded
  rule diverges on it -- that is the negative half of ticket item 8c, as an
  Ermine module.  Four constraints.  Note that `Subst.solve` runs `q.expand`
  (the saturation) BEFORE the `labelClash` refutation check, so the check cannot
  save this module even though it refutes it at label f0; see the ticket.

THE DEFINITION MUST NOT BE ANNOTATED -- the blow-up needs inference, exactly as
in `gen-row-overlap.py`.
"""
import argparse
import pathlib

PRELUDE = "module %s where\n\nimport Prelude\n\n"


def fields(n):
    return "field " + ", ".join("f%d" % i for i in range(n)) + " : Int\n\n"


def res_star(m):
    """a <- (x_i, (|f_i|)) for i < m, all sharing the left-hand side `a`."""
    helpers = "".join(
        "r%d : (a <- (x, (|f%d|))) => Relation a -> Relation x -> Int\n"
        "r%d _ _ = 0\n\n" % (i, i, i)
        for i in range(m))
    calls = ", ".join("r%d a x%d" % (i, i) for i in range(m))
    args = "a " + " ".join("x%d" % i for i in range(m))
    return (PRELUDE % ("ResStar%d" % m) + fields(m) + helpers
            + "probe %s = (%s)\n" % (args, calls))


def gadget():
    """The four-constraint unsatisfiable seed of `ResGuardDiverge.gSeed`."""
    h = ("g : ( a <- (p, (|f0|))\n"
         "     , a <- (q, (|f1|))\n"
         "     , b <- (p, (|f2|))\n"
         "     , b <- (q, (|f3|)) )\n"
         "  => Relation a -> Relation b -> Relation p -> Relation q -> Int\n"
         "g _ _ _ _ = 0\n\n")
    return (PRELUDE % "Gadget" + fields(4) + h
            + "probe a b p q = g a b p q\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/resprobe")
    ap.add_argument("--star-to", type=int, default=7,
                    help="largest ResStar; start small and walk up, the cost is 2^m")
    a = ap.parse_args()
    d = pathlib.Path(a.out)
    d.mkdir(parents=True, exist_ok=True)

    written = []
    for m in range(2, a.star_to + 1):
        (d / ("ResStar%d.e" % m)).write_text(res_star(m))
        written.append("ResStar%d" % m)
    (d / "Gadget.e").write_text(gadget())
    written.append("Gadget")

    print("wrote %d modules to %s:\n  %s" % (len(written), d, " ".join(written)))
    print("\ntime them one JVM each, both ways:\n"
          "  for f in %s/ResStar*.e; do\n"
          "    for g in false true; do\n"
          "      /usr/bin/time -f \"$g $f %%e\" env \\\n"
          "        ERMINE_JAVA_OPTS=\"-Dermine.useInterface=false -Dermine.resGuard=$g\" \\\n"
          "        timeout 300 bin/ermine \"$f\" < /dev/null > /dev/null\n"
          "    done\n"
          "  done" % d)


if __name__ == "__main__":
    main()
