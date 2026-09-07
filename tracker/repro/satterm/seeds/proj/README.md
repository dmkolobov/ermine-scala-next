# The projection-cliff ladder (stage S4)

`PROJ<N>.json` is the constraint system `N` projections `p ! f_i` of ONE open-row record
parameter hand `Subst.solve`, transcribed from the compiler's own `scon` records
(`tracker/loopmodel/S4-DESIGN.md` §1):

    t <- ((|f_1|), c_1)  ...  t <- ((|f_N|), c_N)

N lone-abstract premises at one left-hand side with pairwise-disjoint singleton concrete
parts.  The draws are `D(N) = (5^N - 3*3^N + 2*2^N) / 2` — 3 / 30 / 207 / 1,230 / 6,783 /
35,910 / 185,727 for N = 2..8, exact against the compiler at every one.

**They live in this SUBDIRECTORY, not in the tracked-seed directory above, on purpose.**
`core/src/test/scala/.../TestLoopTrace.scala` runs every top-level `*.json` at six id bases
in ONE child JVM with a 180 s budget; `PROJ7` and `PROJ8` alone would spend most of it, and
the ladder is measured by `tracker/loopmodel/S4-DESIGN.md`'s own runs rather than by that
property.  Run them directly:

    tracker/lean/.lake/build/bin/looptrace tracker/repro/satterm/seeds/proj/PROJ6.json 1000 --depth
    tracker/lean/.lake/build/bin/looptrace tracker/repro/satterm/seeds/proj/PROJ6.json 1000 --depth --flags=topnorm

(the `1000` is the id BASE; fuel is the third positional.)
