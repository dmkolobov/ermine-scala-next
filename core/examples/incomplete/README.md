# `incomplete/` — where Ermine's row inference gives up

Realistic data-query modules, each exhibiting one way the row-constraint solver is
incomplete or wrong. Written 2026-09-01. `README-unsound.md` covers the four
`unsound0*` modules, which are a genuine soundness bug: they load, and their row
constraints have no solution.

## The `.slow` convention — read this before adding a file

Several tests sweep `core/examples` and **type-check every `.e` file they find**
(`TestTolerantRead`, `TestSurfaceParsers`, `TestStatementExtents` — all use a
`walk` that filters on the `.e` extension). This directory deliberately contains
modules that trigger the `commonSubexpression` blowup and **do not terminate**. If
such a module is named `.e`, `core/test` stops terminating too.

So: a module that does not type-check in reasonable time gets the extension
**`.slow`** instead of `.e`. The walkers skip it; `bin/ermine` will still run it
if you name it explicitly.

Measured per-file, default rules (`-Dermine.genRules=all`), 60s cap. Boot is
~11.8s of every figure:

| module | wall | verdict |
|---|---|---|
| `gu02_star_join_7dim_inferred` | >60s | `.slow` |
| `gu03_star_join_8dim_inferred` | >60s | `.slow` |
| `gu07_label_helper_callsite` | >60s | `.slow` |
| `gu09_star_join_halves_composed` | >60s | `.slow` |
| `np05a_inferring_the_helper` | — | `.slow` (marked by the original author) |
| `np05c_helper_at_a_call_site` | — | `.slow` (likewise) |
| `gu01_star_join_6dim_inferred` | 23.0s | kept as `.e` — slow but bounded |
| `gu05_star_join_4dim_concrete_signature` | 24.2s | kept as `.e` — likewise |
| everything else (32 modules) | ~12s | boot cost only |

`gu01` and `gu05` are kept as `.e` on purpose: they are the cheap end of the cliff
curve, they terminate, and a corpus that only contains the unrunnable cases would
not show the shape of the curve.

## These are not a regression

The divergence is a property of the shipped solver, not of any work in the
row-constraint ticket. Verified by stashing every solver change
(`Constraints.scala`, `Subst.scala`, `Type.scala`), rebuilding, and re-timing with
no flags set:

```
  PRISTINE  gu02  90.06 (timeout)      PRISTINE  gu03  90.06 (timeout)
  PRISTINE  gu07  90.06 (timeout)      PRISTINE  gu09  90.06 (timeout)
  PRISTINE  gu04  14.58 (control, finishes)
```

Identical to the modified tree. The control is the interesting one:
`gu04_star_join_8dim_annotated` finishes in 14.6s while
`gu03_star_join_8dim_inferred` never does — **same eight dimensions, and the type
annotation is the only difference.** That is the cliff's signature: it is an
inference problem, not a size problem.

Under `-Dermine.genRules=cut` all six run fast, which is one of the arguments for
the cut in `tracker/TICKET-row-constraint-decision.md` §7.
