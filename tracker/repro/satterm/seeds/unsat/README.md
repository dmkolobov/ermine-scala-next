# `seeds/unsat/` — UNSATISFIABLE seeds the shipped row solver ACCEPTS

Found by the S1 review's hunt (2026-09-05, `tracker/loopmodel/S1-REVIEW.md` §2, §7): ~9 M
generated systems, 11,048 that are UNSAT **and** pass `labelCheckEarly`, ~27,000 model runs at
the shipped flags, **1,166 model false acceptances over 665 seeds**, ten of them replayed on
the shipped compiler and **all ten accepted**.

These seeds live in a SUBDIRECTORY on purpose: `TestLoopTrace` enumerates `seeds/*.json`
non-recursively, and these are gate material for the fix stage (S2), not conformance seeds.

| seed | witnesses | compiler at the shipped flags |
|---|---|---|
| `MIN1.json` | Z-1: saturation incompleteness — the loop reaches `.done` on an unrefuted residual | `SOLVED` 20/20 bases; violates the input at `l35` |
| `FALSE-ACCEPT-1.json` | the same, un-minimised (`u00019`) | `SOLVED` at 300–302 |
| `MIN2.json` | Z-2: the `concrete` branch's unlicensed BARE-ROW deletion | `SOLVED` 4/20 bases; violates the input at `l17` |
| `FALSE-ACCEPT-2.json` | the same constraints (`x00002`) | `SOLVED` |
| `PANIC-1.json` | Z-2/Z-5: the hole's SHAPE with `srs` empty, so nothing is deleted; `Subst.reduce` then PANICS | `REJECTED` by an internal panic, 3/3 bases |
| `SURV1.json` | the seed that survives the §7.1 fix (`checkLabels` on the saturated set) | `SOLVED` at 300, 301 |
| `ENV-LINK.json` | **a THIRD mechanism** (S2 review §4.5, found by the reviewer): unsatisfiable ONLY THROUGH THE ENVIRONMENT.  The seed's `env` block is a FIRST solve, run in the same `SubstEnv`, that binds `v4 := v0` — a `VarT` link, no concrete row anywhere; the solve under test is then `v3 <- (v0,v4)`, `v3 <- ((\|l0\|))`, which forces `rho v0 = rho v4 = ∅` hence `rho v3 = ∅` against `rho v3 = {l0}`.  `Subst.solve` does not `substType` its input, so the shipped check never sees the binding (S1 review Z-6).  **The only tracked seed that exercises layer (iii)'s environment-fact path**, the `senv` replay record and the theorem's `envFacts` | `SOLVED` **20/20**; with `-Dermine.rowSound.decide=true` REJECTED 20/20 at `l0` |

A seed may carry an `"env"` array in the same shape as `"cons"`: it is a FIRST solve run in
the SAME `SubstEnv`, so the solve under test is handed constraints mentioning variables the
environment already binds.  `SatTermRepro.runCapped` otherwise makes a fresh `SubstEnv` per
run, which is why no other seed here reaches that path.  `tracker/repro/satterm/run.sh env`
runs the nine-case table that covers it (concrete bindings, `Con`, `VarT` links, alias chains
and the two bare-row cases), at both flag settings.

Re-run:

```bash
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:tracker/repro/satterm/seeds/unsat/MIN2.json 300 319
```
