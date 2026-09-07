# Brief: E1 — a new example corpus: generic helpers over WIDE tables, pivots and window functions

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, CLEAN at the commit the
orchestrator names (the three row-solver defaults ADOPTED: `rowSound` ON, `dequeuePolicy=smallcanon`,
`solveBudget=20000`). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
`bin/ermine <files>` type-checks modules; the REPL (`bin/ermine` with no args? — see `tracker/tools/repl-smoke.sh`
for how it is driven non-interactively) `:load`s a file and `render <report>`s it; Lean `export PATH=$HOME/.elan/bin:$PATH`
in `tracker/lean/` for the model instruments. One JVM at a time (`-XX:ActiveProcessorCount=2`); long runs under
`setsid nohup` with a log (background shells are capped at ten minutes); `pkill -f` matches itself (kill by PID);
disk tight (gzip traces; delete `.ei` files you cause under `core/examples`); no commits; sbt allowed only for the
gates named below.

THE USER'S ASK (2026-09-06): "develop the examples directory further … uses of generic helpers with wide-ish
tables … reach into parts we haven't so much: existential-generating helpers like pivots, window functions, etc."
Ermine is a REPORTING language; the examples are both documentation for users and the certification corpus
for the row solver (every solve of every example is traced and replayed through the Lean model, and the
termination/soundness census is measured over them — `tracker/loopmodel/L5-TERMINATION.md`, `S2-FIX.md`,
`A1-ADOPTION.md`). Today the corpus exercises the interesting machinery thinly: `Relation.Pivot` appears in one
toy (`core/examples/PivotTest.e`), `Relation.Windowed` in NO example, and the round-7/8 census shows the
generative rules (`SplitConcrete`, `Resolution`) firing on only ~2.6 % of example solves, depth ≤ 4, and the
`concrete` branch on a quarter.

READ FIRST: `core/examples/Ai/README.md` (the conventions of the last example set: self-contained realistic
reports, a header block per file, `Common.e` as the row-polymorphic helper library, the measured pitfall that a
helper bundling `RUnion3` and `RUnion2` "does not finish" — measured BEFORE the new defaults); three Ai modules
in full (`SupplyChainInventory.e`, `FiscalCalendar.e`, `ClinicalTrial.e`) for style; `core/examples/incomplete/README.md`
(the `.slow` convention: a module that does not type-check in reasonable time MUST be named `.slow`, because
`core/test` type-checks every `.e` it finds); `core/examples/incomplete/Signatures.e` (how a residual signature is
hand-written and proved equivalent); the stdlib: `core/src/main/resources/modules/Relation.e` (`joinWithDefault`
with its `exists c s.` signature, `groupBy`, `joinBy`, `copyColumn`, `lookupLatest*`, `nearestDate*`, `leafRows`),
`Relation/Pivot.e` (`nilFulcrum`, `consFulcrum : (p' <- (f, p), RUnion2 v3 v2 v1) => …`, `pivot : (RelationalComb rel,
r <- (k, v, i), s <- (i, p)) => Fulcrum k v p -> rel r -> rel s`, `pivotWithDefault`), `Relation/Windowed.e`
(`window : (t <- (r, s)) => Row r -> Sort s -> Frame -> Window t`, `windowed : (t <- (r, s)) => Windowed r a ->
Window s -> Op t a`, `rank`/`dense`/`rowNumber`/`nTile`/`windowedAggregate`, `Frame`), `Relation/Aggregate.e`,
`Layout/Report/Keyed.e` and `Layout/Report/Fulcrum/*.e` (the wide-table report layouts), `Syntax/Relation.e`;
`tracker/tools/{corpus-run.sh,looptrace-corpus.sh,repl-smoke.sh}` (how examples are validated and traced; the
`Ai)` special case that puts `Common.e` first — mirror it for the new group).

## What to build: `core/examples/Wide/` — a new example group

E1.1 **A helper library `Wide/Helpers.e`** (module `Wide.Helpers`), row-polymorphic and EXISTENTIAL-GENERATING:
     generic helpers whose signatures mint rows — a `pivotBy` that builds a `Fulcrum` from a key column and a
     value column over an otherwise-unknown row; `rankWithin`/`topNWithin` (window functions partitioned by a
     generic key row with a generic sort); `runningTotal`/`movingAverage` (framed window aggregates); `share`
     (a measure divided by its window total); `unpivot`/`melt` if the stdlib can express it (a column set into
     key/value rows) — say so if not; `withDerived` in the style of `Ai.Common.withColumn` but over several
     columns; a `lookupLatestBy` over a generic key. Each with an EXPLICIT signature (the Ai README's lesson),
     each with a one-paragraph doc comment saying what row constraint it carries and why. Expect and measure the
     RUnion pitfall; at the NEW defaults, re-measure the Ai README's three-row table (inline / `withColumn` /
     bundled `RUnion3`+`RUnion2`) and report whether the bundled form now finishes.
E1.2 **Eight to ten report modules** (`Wide.<Subject>`), each a self-contained, realistic report over WIDE tables
     — 20 to 40 fields per fact row is the target, several dimensions — with the data inline (`relation [...]`)
     as the Ai examples do, a header block (subject; fact and dimension tables with their fields; the helpers
     used; WHICH SOLVER SHAPES it exercises; how to load and render), and at least one `render`able report each.
     Subjects are yours; cover between them: a wide sales ledger pivoted by period AND by product line (two
     Fulcrums, one nested in a Keyed report); a trial-balance / general-ledger report with running balances
     (framed window); a leaderboard with rank/dense/nTile within groups over a 30-field player table; a
     time-series with moving averages and lookupLatest joins across two calendars; a wide survey table melted
     to key/value then pivoted back (the round-trip); a share-of-total report with nested groupings (window
     totals at two levels); a report composing three generic helpers whose residual rows chain (the depth the
     census never sees); and one `shouldfail`-style module in `core/examples/Wide/shouldfail/` that misuses a
     helper (a pivot whose key column is also a value column, a window over a missing column) with the EXPECTED
     diagnostic recorded — the negative example the corpus needs for the soundness gates.
E1.3 **Wire the group into the tooling**: `tracker/tools/corpus-run.sh` (the `Ai)`-style `Helpers.e`-first rule),
     `tracker/tools/looptrace-corpus.sh` (`Wide` in the default group list, `Helpers.e` first), the examples
     `README.md` and a `Wide/README.md` in the Ai README's style (the table of files, what each exercises, the
     measured numbers). Do NOT touch `tracker/lean/`; the model needs no change to replay a new group.

## Gates and measurements (every number in the report with its command)

E1.4 Every `Wide/*.e` type-checks: `bin/ermine core/examples/Wide/Helpers.e <the rest>` LOADED, per file AND in
     one batch (`corpus-run.sh` both modes); the `shouldfail` module REJECTED with the expected message; per-file
     wall clock (anything over 30 s is named; anything that does not finish becomes `.slow` per the convention
     — and is a FINDING at the new defaults, since the budget is supposed to stop it: report whether the budget
     fires, with the diagnostic). `sbt core/test` must stay 913/914 (or 912 with the known flake) and must not
     slow by more than the new modules' own check time (`TestTolerantRead`/`TestSurfaceParsers`/
     `TestStatementExtents` walk every `.e`).
E1.5 The L2 differential on the new group: `looptrace-corpus.sh` with `LOOPTRACE_GROUPS="Wide"` — every solve
     replayed, 0 skipped / 0 hashdiff / 0 eqdiff (the model must reproduce the compiler on the new solves; a
     disagreement is a FINDING about the model, report it at once). Then the census instruments over the new
     group (`lake exe looptrace --replay <trace> --depth`, `--cycle`, the S2 `rsound` records): per solve —
     draws, chain depth, per-key mints, dequeues, generative rules fired, `concrete` steps, decision nodes;
     summarised against the existing groups' figures (round 7/8: depth ≤ 4, R ≤ 11, 97.4 % vocabulary-fixed,
     generative rules on ~2.6 %). The point of the stage is measured here: which shapes the new group reaches
     that the old corpus did not (depth, resolution chains, the `concrete` branch, the decision's case splits,
     budget headroom — the largest draw count of any new solve against 20,000).
E1.6 `render` every report through the REPL harness (the way `repl-smoke.sh` drives it): each must render
     without error; capture one rendered table per report in the report (trimmed) so a reader sees what the
     example produces. The `.ei` sweep on the group (`tracker/tools/ei-diff.sh` or the A1 recipe): every
     interface published; list the residual constraints each helper publishes.
E1.7 Report `tracker/loopmodel/E1-EXAMPLES.md`: the file table, the helper signatures verbatim with their
     residuals, the gates with numbers, the census comparison table, the RUnion re-measurement, renderings,
     what you could not write and why (a helper the type system cannot express is a finding worth recording
     precisely). A reviewer re-runs everything and judges the examples as REPORTS a user would learn from.

Outcomes: (GREEN) all modules load, differential clean, census reported; (RED) something does not load or the
model disagrees — report, do not paper over. Constraints as always: no silent weakening, one JVM at a time,
report early and keep it current, never `lake exe cache get`, never touch `tracker/lean/` or `~/research/leanwork`.
