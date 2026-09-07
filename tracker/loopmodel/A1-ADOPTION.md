# A1 — ADOPTION: the three defaults flipped

2026-09-06.  Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, base
`c0221fc`.  Brief `tracker/loopmodel/briefs/brief-A1.md`.  User's decision, 2026-09-06 17:00: adopt the
FULL RECOMMENDED SET.  **No commit is made by this stage.**

| | old default | new default |
|---|---|---|
| `-Dermine.rowSound` (and `.bare`/`.saturated`/`.decide`) | `false` | **`true`** |
| `-Dermine.dequeuePolicy` | `shipped` | **`smallcanon`** |
| `-Dermine.solveBudget` | `0` | **`20000`** (effective only under a non-shipped order) |

**The OLD configuration is one command line on both sides**: compiler
`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`; model `--flags=norowsound --policy=shipped`.

## 0. Outcome

**GREEN.**  Every gate in the brief was run and every one is green.  Nothing was worked around
and no gate was weakened.  What this report does NOT claim, and what is still open, is in §3 —
read it: ONE published residual is genuinely different (and strictly MORE GENERAL), the `.ei`
cache is still not keyed by the configuration so a user must clear it once, and the budget
diagnostic renders at error severity with no diagnostic `code`.

**The new default fingerprint** (`GenRules.toString`, and the model prints the same string):

```
cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000
```

**The OLD configuration** — `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`, model
`--flags=norowsound --policy=shipped` — gives back
`cut+label-early+resguard+splitkey+splitrow+resrow`, byte-identical to the pre-adoption default,
and was run as the control for every gate where a before/after means anything.

The headline numbers, new against old:

| | OLD | NEW |
|---|---|---|
| the 7 curated UNSATISFIABLE witnesses, 10 id bases each | **44 SOLVED of 70** (a false acceptance each) | **0 SOLVED of 70** |
| the S2 environment gate (`run.sh env`) | `cases=9 differ=4` | **`cases=9 differ=0`** |
| `GU05.json`, 25 id bases | 743 / 1,091 / 47,317 draws over the first three bases | **306 draws at all 25** |
| the chunk holding `incomplete/gu05`, batch load, interfaces on | **629 s** | **11 s** |
| corpus verdicts, 100 files, deterministic loader | 23/43 and 18/16 | **identical — 0 verdict changes** |
| the eight-group L2 differential | 2,355,430 of 2,355,430 agree | **2,355,428 of 2,355,428 agree** |
| 3,840 hunt seeds x 3 bases | 11,520 SOLVED | **11,520 SOLVED, 0 concrete rows moved, budget never fired** |
| published interfaces, 187 (1,921 bindings) | — | **30 bindings move; 29 are the same type, 1 is strictly MORE GENERAL; `rowSound` moves not one byte** |
| `core/test` / `TestLoopTrace` | 913/914, 714/714 | **913/914, 714/714** |
| `perf-bench batch` cold median | 12.81 / 12.91 s (mine); 13.43-13.76 s (the reviewer's four rounds) | **12.89 / 12.70 s** (mine); 13.58-13.90 s (the reviewer's) — **a small cost, of order 1-3 %, not separable from this desktop's noise** (R-7) |

**No commit was made.**  The orchestrator commits after a reviewer's verdict.

## 1. What changed

The files (line counts in §5):

```
core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala
core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala
core/src/test/scala/com/clarifi/reporting/ermine/loopmodel/TestLoopTrace.scala
tracker/lean/Rowpartition/Loop/Main.lean
tracker/lean/Rowpartition/Loop/NoFalseAccept.lean
tracker/lean/Rowpartition/Loop/State.lean
```

### 1a The compiler (`Constraints.GenRules`)

| property | old | new |
|---|---|---|
| `ermine.rowSound` (the master; `rowSoundFlag` takes its default from it, so the three layers `.bare` / `.saturated` / `.decide` follow) | `"false"` | `"true"` |
| `ermine.dequeuePolicy` | `"shipped"` | `"smallcanon"` |
| `ermine.solveBudget` (`solveBudgetRequested`) | `0` | `20000` |

Each carries an `ADOPTED 2026-09-06` comment in the style of the `splitKey`/`splitRow`/`resRow`
flips, naming the evidence documents and — as those do — what the flip does NOT buy.  Nothing
else in the solver changed: no rule, no guard, no dequeue body, no diagnostic text except the
one warning below.

**The budget-requires-policy rule stays**, and it is what makes `-Dermine.dequeuePolicy=shipped`
a complete rollback on its own: `solveBudget = if (dequeuePolicy == "shipped") 0 else
solveBudgetRequested`.  Its warning had to be re-worded, because at the new defaults it fires
for a user who asked for the shipped order and never asked for a budget at all: it now says
`NOTE the draw budget -Dermine.solveBudget=20000 (the default) is IGNORED because
-Dermine.dequeuePolicy is 'shipped' …`, and `(the default)` appears only when the property was
not set on the command line.  **This is the one behavioural change in this stage that is not a
default**: at the OLD configuration the compiler now prints one line on `stderr`.

### 1b The model (`tracker/lean/Rowpartition/Loop/`)

* `State.lean`: `Flags.rowSoundBare`, `.rowSoundSat`, `.rowSoundDecide` default `true`.
* `Main.lean`: a `norowsound` `--flags` token (all three layers off — without it the
  pre-adoption configuration is unreachable from the model's command line and
  `-Dermine.rowSound=false` cannot be forwarded); `policyOf` defaults to `.smallCanon` and a
  new `defaultBudget = 20000`; the `json:` seed path solves under those defaults, so
  `looptrace <seed>.json <base>` and `bin/ermine` run the same solve with nothing on either
  command line; the `--verdict` header prints `+pol:` / `+budget:` for the EFFECTIVE
  configuration, so the model's fingerprint string is the compiler's string;
  and the `--replay` census path now reads the segment's own `sin` policy/budget the way the
  record path always has (`--budget=<n>` alone over a policy-on trace no longer censuses it at
  the shipped order).
* `NoFalseAccept.lean`: `({} : Flags)` no longer denotes the pre-adoption configuration, so the
  three "the SHIPPED loop accepts this seed" theorems name it explicitly through a new
  `shippedFlags`.  **No statement is weakened**: each proves the sentence it proved before, of
  the configuration it was always about.  One theorem is ADDED —
  `min2_loop_rejects_at_defaults` — because at the new defaults the loop itself refutes `MIN2`
  through layer (i), before layer (iii) is reached.

### 1c The forwarding (`TestLoopTrace`)

* `flagMap` gains `("ermine.rowSound", "false", "norowsound")`, and `"true"` moves to the list
  of values that ARE the default and need no token.
* `setD1` forwards `-Dermine.dequeuePolicy` / `-Dermine.solveBudget` whenever they DIFFER from
  the shared default (`smallcanon` / `20000`) — in either direction.  Before the flip the test
  forwarded anything that was not the OFF value; now `-Dermine.dequeuePolicy=shipped` is the
  value that must reach the model, as `--policy=shipped`, and it does.

### 1d The new default fingerprint

`GenRules.toString`, measured at five settings (`gates1.log`):

| setting | `genRules=` |
|---|---|
| **the new defaults** | `cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000` |
| `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` (**the OLD configuration**) | `cut+label-early+resguard+splitkey+splitrow+resrow` — byte-identical to the pre-adoption default |
| `-Dermine.dequeuePolicy=shipped` | `…+rsbare+rssat+rsdecide` (the budget goes with the order) |
| `-Dermine.solveBudget=0` | `…+rsdecide+pol:smallcanon` |
| `-Dermine.rowSound=false` | `cut+label-early+resguard+splitkey+splitrow+resrow+pol:smallcanon+budget:20000` |

The MODEL prints the same string at its own defaults and at `--flags=norowsound`
(`looptrace <seed>.json <base> --verdict`), which is the check that the two sides' defaults are
the same defaults.

## 2. Gates

All at the NEW shipped configuration (nothing on the command line), with
`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` (model: `--flags=norowsound
--policy=shipped`) as the control wherever a before/after is meaningful.

| # | gate | result |
|---|---|---|
| A1.2 | `lake build Rowpartition` / `Audit.lean` / `lake build looptrace` (`LEAN_NUM_THREADS=2`) | **867 jobs, success; 4,116 theorems audited / 0 non-standard axioms** (4,115 before: the one added theorem); **looptrace 1,670 jobs**.  `sbt core/compile core/test:compile` **`[success]`**, no new warnings.  **PASS** |
| A1.4 | `core/test` (`sbt -batch -J-Xmx3g core/test`, 260 s) | **913 or 912 of 914**, the difference being one of two known flakes.  My run: Total 914, Passed 913, Failed 1 — `com.clarifi.reporting.TestConstraints`, the known `Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded`.  The reviewer's run: **912/914**, the extra failure being `TestInterfaceRoundTrip` (the flake `LSP-ROADMAP.md` names), which PASSES isolated at both configurations — the third consecutive stage to hit a second, different flake (S2 review V-4 hit `TestLegend`).  Neither figure is a constant.  **PASS** |
| A1.4 | `TestLoopTrace`, new defaults (`sbt "core/testOnly *TestLoopTrace"`) | **714 solves (19 seeds x 6 bases + 600 generated); 714 segments; 714 agree**, `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`, 3 of 3 properties.  Both positive controls still detect: id base +1 **46 of 714**, `--flags=nongen` **58 of 714** (the under-the-policy figures D1 recorded).  **PASS** |
| A1.4 | `TestLoopTrace`, OLD configuration forced (`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`) | the test prints `flags forwarded to both sides: -Dermine.rowSound=false -Dermine.dequeuePolicy=shipped  ->  --flags=norowsound --policy=shipped --trace`; **714 / 714 / 714**, same summary line, 3 of 3; controls **53 of 714** and **65 of 714** (the shipped-order figures).  **PASS — and this is the gate that shows the OLD configuration is reachable on BOTH sides and that the forwarding maps it in both directions** |
| A1.5 | eight-group L2 corpus differential, new defaults (`tracker/tools/looptrace-corpus.sh`, `-Dermine.loadInSeries=true -Dermine.useInterface=false -Dermine.rowTrace=<file>` per group, `incomplete` per file; model `--replay`, taking the policy and the budget from each segment's own `sin` record) | **2,355,428 segments, 2,355,428 AGREE, 0 skip, 0 hashdiff, 0 eqdiff**, every group `rc=0 timeouts=0 dropped=0 threads=1`.  **PASS** — table below |
| A1.5 | the same, OLD configuration (control): `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` on the compiler, `--flags=norowsound` on the model | **2,355,430 segments, 2,355,430 AGREE, 0 skip, 0 hashdiff, 0 eqdiff** — the pre-adoption population, digit for digit (S2-FIX §A3-3, D1-CHANGE §2a gate 3).  **PASS** |
| A1.6 | corpus verdicts, `--batch` and `--incomplete --batch`, new vs old | **ZERO verdict changes.**  66-file corpus **23 LOADED / 43 REJECTED on BOTH sides** (`shouldfail/` 40 of 40 still rejected); `incomplete/` **18 LOADED / 16 REJECTED on both**.  11 files report a DIFFERENT CLAUSE of the same refutation — §A1.6 below, with the control.  **PASS** |
| A1.7 | `.ei` sweep, deterministic loader, new vs old + floor (whole corpus, chunk 10, interfaces ENABLED, `-Dermine.loadInSeries=true`; `tmp/D1/einorm3.py`) | **187 interfaces on BOTH sides, none published on one side only.**  FLOOR: two sweeps at each configuration are **BYTE-identical** (NEW `md5 4dda77739572` twice, OLD `md5 69a80fb186fa` twice, `diff -rq` empty).  OLD vs NEW: **183 of 187 identical, 4 differing**; raw bytes 17 of 187.  **PASS** — §A1.7 below |
| A1.7 | `tracker/tools/ei-classify.py` on the two DETERMINISTIC sweeps (the measurement of record) | **1,891 bindings identical, 13 order-only, 10 alpha-equivalent, 7 other; 0 WEAKER, 0 STRONGER.**  17 of 187 interfaces differ in some binding.  **PASS — "0 signatures weaker"** |
| A1.7 | `tracker/tools/ei-diff.sh --batch` (the standard tool, chunk 5) | ran, `rc=0`, **187 interfaces captured on each side, none on one side only**; classifier **1,832 identical / 65 order-only / 13 alpha-equivalent / 11 other, 0 WEAKER**.  **CAVEAT, stated rather than buried: `ei-diff.sh` gives side A no flags, so its side A ran the SHIPPED PARALLEL loader while side B ran with `-Dermine.loadInSeries=true` — a broken control of exactly the shape D1B review U-1 found, and the reason its "order-only" count is 65 against the deterministic sweep's 13.  The row above is the measurement of record; this row is the standard tool's output, reported for completeness** |
| A1.7 | does the fingerprint change force an `.ei` to be regenerated? | **NO — measured, not only read off the code**: a stdlib closure whose interfaces were published at the OLD configuration is READ at the new defaults (boot 8.44 s against 15.12 s with no interfaces).  D1B review U-6, confirmed on this tree.  §A1.7c below |
| A1.8 | 19 tracked seeds x 10 bases on the COMPILER, NEW vs OLD (`tmp/A1/BulkRunA1.scala`, one JVM per side, 60 s cap) | **190 runs each side; 0 VERDICT lines differ.**  Substitutions: **2 of 190 lines differ** once the `Set` print order is normalised, and both are one variable that is `unbound` on one side and ALIASED TO ANOTHER VARIABLE on the other (`H2` base 9 `v2 := unbound` -> `v2 := 14`; `NE6` base 8 `v2 := 17` -> `v2 := unbound`).  **No concrete row moves anywhere.**  Base-invariance control: distinct outcomes across the ten bases fall from **5 of 19 seeds (OLD) to 4 of 19 (NEW)**.  **PASS** |
| A1.8 | `seeds/unsat/*` (7 witnesses) x 10 bases | **NEW: REJECTED 10/10 on all seven — 0 SOLVED of 70.**  OLD: `MIN1`, `FALSE-ACCEPT-1`, `SURV1`, `ENV-LINK` SOLVED 10/10; `MIN2` and `FALSE-ACCEPT-2` SOLVED 2/10; `PANIC-1` REJECTED 10/10 — **44 false acceptances of 70 become 0**.  **PASS**, and this is the U-0 condition discharged: the policy loses nothing because `rowSound` refutes all seven at every base |
| A1.8 | `seeds/slow/GU05.json` x 25 bases and `GU05MIN` x 25, NEW defaults (`run.sh sweep`, 600 s cap) | `GU05` **SOLVED 25/25, `DRAWN min=median=max=306`**; `GU05MIN` **SOLVED 25/25, 256 at every base**.  Both are the MODEL's own figures.  **PASS** |
| A1.8 | the S2 environment-fact gate, `tracker/repro/satterm/run.sh env` | NEW **`cases=9 differ=0 decide=true`**; OLD **`cases=9 differ=4 decide=false`** — the four differing cases at the old defaults are the unsatisfiable systems the shipped solver ACCEPTS.  **PASS** |
| A1.8 | B1's `PANIC3` x 100 bases, NEW defaults | **SOLVED=100, REJECTED=0, HANG=0**, `DRAWN 0 x100`.  **PASS** (B1's gate 3a figure) |
| A1.8 | round-8 hunt seeds, 3,840 x 3 bases, NEW vs OLD | **11,520 runs each side, SOLVED 11,520 of 11,520 on BOTH — 0 verdict differences.**  Substitutions: **379 of 11,520 lines differ** (3.3 %) after normalising the `Set` print order, and **every single per-variable difference is an ALIAS against UNBOUND** (354 alias->unbound, 213 unbound->alias, 105 alias->alias): **not one concrete row assignment changes anywhere in 11,520 solves.**  **The draw budget NEVER FIRED**: `solveBudgetHits=0` on all 11,520 + the 190 tracked + the 70 unsat runs.  So are S2's: `rowSoundBudgetHits=0`, `rowSoundCheckFails=0` everywhere.  **PASS** |
| A1.8 | the model-side verdict comparison, the LOOP CENSUS (`tmp/A1/gates8.sh`, `tmp/D1/bindcmp.sh`'s fixed shape: 26 seeds x 10 id bases, `--policy=` census both sides) | **280 pairs; excluding the two `slow/` seeds, 242 SAME and 18 DIFF, and all 18 are `REJECTED -> SOLVED`: `MIN2` x8, `FALSE-ACCEPT-2` x8, `PANIC-1` x2** — D1's tally to the digit.  **This is U-0 reproduced on the model, and it is NOT a verdict change of the adopted configuration**: the `--policy=` census runs `polRun`, the LOOP alone, and S2's layer (iii) lives in `solveSeedP`, outside it — so the census measures the dequeue order with `rowSound` switched off whatever the flags say.  The comparison through the SOLVE path is the row below.  Also here: on `GU05` the shipped-order census exceeds the 120 s cap at 8 of 10 bases where the new configuration solves in **306 draws** |
| A1.8 | the model-side verdict comparison through the SOLVE path (`--verdict --flags=norowsound --policy=shipped --trace` against the bare defaults, so layer (iii) is included; 26 seeds x 10 bases = **280 pairs**) | **230 SAME, 50 DIFF, and NOT ONE `REJECTED -> SOLVED`.**  Over the 260 non-`slow/` pairs: 140 `SOLVED -> SOLVED`, 78 `REJECTED -> REJECTED`, **42 `SOLVED -> REJECTED`** — exactly the false acceptances the fix removes (`MIN1` 10, `FALSE-ACCEPT-1` 10, `SURV1` 10, `PANIC-1` 8, `MIN2` 2, `FALSE-ACCEPT-2` 2, the last two being the 2 of 10 bases at which the shipped LOOP did not already refute them).  On `GU05` the OLD side exceeds the 120 s cap at 8 of 10 bases where the new configuration solves (**`NOOUTPUT -> SOLVED`**), and `GU05MIN` times out on BOTH sides at all ten.  Substitution text differs on **33 pairs whose verdict did not move** (`NP01` 10, `MIN2` 8, `FALSE-ACCEPT-2` 8, `PANIC-1` 2, `NE6` 2, `GU05` 2, `H2` 1) — the same residual-order and alias churn the compiler shows.  **PASS** |
| A1.9 | `tracker/tools/perf-bench.sh batch -n 5`, NEW and OLD **alternated twice** (cold, interface-free, `ei_after=0` every run, `PERF_JVM_PROPS=-XX:ActiveProcessorCount=2 [+OLD]`) | round 1 **NEW 12.89 s / OLD 12.81 s**; round 2 **NEW 12.70 s / OLD 12.91 s** (cold medians of 5 reps; per-run spread 0.42-1.33 s).  The sign flips between MY two rounds; **it did not survive the reviewer's four** (`-n 3`, alternated, NEW first in rounds 1-2 and OLD first in 3-4), which put the new defaults slower every time by 0.06-0.46 s on a ~13.6 s cold batch, median **+0.30 s (+2.2 %)**.  Each individual difference is inside a single run's own spread (0.39-0.77 s).  **The honest reading is a small cost, of order 1-3 % on the cold stdlib batch, not separable from the noise on this host** (R-7) — and two orders of magnitude smaller than what the policy buys (`incomplete/gu05`'s ten-file chunk, 629 s -> 11 s).  It is not a speed-up claim in either direction.  `PERF_MAX_LOAD` raised to 6.0 and `load_before` recorded per run (1.94 / 3.04 / 4.06 / 3.19): this host is the user's desktop and never falls below the harness's 1.5, and a batch run leaves the average at ~4 by itself — the NEW/OLD comparison is sound, the absolute seconds are not comparable with quiet-machine numbers.  **PASS** |
| A1.9 | `incomplete/gu05...e` loaded ALONE, 3 reps each (`-Dermine.useInterface=false -Dermine.loadInSeries=true`) | module time **NEW 0.35 / 0.36 / 0.35 s**, **OLD 0.25 / 0.23 / 0.23 s** — about 0.1 s dearer loaded alone.  The other side of the same coin: in a ten-file BATCH with interfaces enabled (gate A1.7's sweep) the chunk holding `gu05` takes **629 s under the OLD configuration and 11 s at the new defaults**.  **PASS** |
| A1.9 | layer (iii)'s bill on the corpus at the new defaults (from the `rsound` records of the A1.5 trace, 2,355,428 segments) | `ok` records **2,355,392** (the decision RAN and PASSED on every solve), `env` **1**, `decide` **1** (the `inf04` refutation), **`budget` 0, `bare` 0, `sat` 0**.  Total time inside the decision **0.690 s for the whole corpus**, 1,136 decision nodes.  Only 26,404 solves (1.1 %) have an input partition at all, 7,834 (0.33 %) mention a label, **361 spend a decision node**; largest input partition count anywhere **18**.  **Per-solve maximum: 6,136 us** at `incomplete/witness01_case4_left_all.e(31:18)` — with **labels=1 parts=1 nodes=0**, i.e. no work at all, JVM noise around a `System.nanoTime` pair (S2-FIX §5.2's phenomenon); the maximum among solves that did work is **5,690 us at `incomplete/gu05...e(62:1)`, 10 labels / 18 partitions / 4 nodes**, the same solve S2 identified.  **PASS** |
| A1.10 | `tracker/tools/repl-smoke.sh` / `lsp-smoke.sh` at the NEW defaults | repl-smoke **PASS**: aliasing (2), relations (6), scoping (4), smoke (23).  lsp-smoke **PASS**: lsp (98 checks).  Both `rc=0`.  **PASS** |
| A1.10 | the two new deaths as ORDINARY diagnostics | **Both reach a user as located diagnostics, in the CLI and in the language server.**  §A1.10 below has the verbatim text.  **PASS** |

### A1.5 in full — the eight groups, new defaults against the OLD configuration

| group | files | NEW segments | NEW agree | OLD segments | OLD agree |
|---|---|---|---|---|---|
| `boot` | 0 | 54,199 | **54,199** | 54,199 | **54,199** |
| `top` | 15 | 92,673 | **92,673** | 92,673 | **92,673** |
| `Ai` | 11 | 83,942 | **83,942** | 83,942 | **83,942** |
| `shouldfail` | 40 | **56,030** | **56,030** | 56,032 | **56,032** |
| `bugs` | 2 | 54,235 | **54,235** | 54,235 | **54,235** |
| `guide` | 2 | 54,244 | **54,244** | 54,244 | **54,244** |
| `shouldfail-controls` | 5 | 54,739 | **54,739** | 54,739 | **54,739** |
| `incomplete` | 35 | 1,905,366 | **1,905,366** | 1,905,366 | **1,905,366** |
| **total** | **110 (+35)** | **2,355,428** | **2,355,428** | **2,355,430** | **2,355,430** |

**THE ONE COUNT THAT MOVES, and why.**  `shouldfail` has **two fewer solves** at the new
defaults, 56,030 against 56,032 — and that is the fix working, not a loss.
`core/examples/shouldfail/inf04_except_recursive.e` is REFUTED EARLIER under `rowSound` (S2-FIX
§4.1: at `20:10` by layer (iii) instead of at `22:7` by the shipped clause), so two solves that
used to follow it in that session never happen.  It is the same 56,030 S2's Part B measured, and
the model reproduces it: the compiler's trace and the model's replay have the same 56,030
segments and they agree on every one.  **No other group's count moves at all** — in particular
`incomplete` is 1,905,366 both ways, because this harness loads `incomplete/` PER FILE with
`-Dermine.useInterface=false`, where `gu05` completes under both dequeue orders; the policy's
user-visible win is in a BATCH load, which is gate A1.6's population, not this one.

### A1.6 in full — corpus verdicts, and the eleven messages

`tracker/tools/corpus-run.sh --batch` and `--incomplete --batch`, `-Dermine.useInterface=false`,
one JVM per corpus, `CORPUS_BATCH_TIMEOUT=1800`; classified by `tracker/tools/corpus-verdicts.py`.

| corpus | files | OLD | NEW | verdicts moved | messages moved |
|---|---|---|---|---|---|
| examples + `Ai` + `shouldfail` | 66 | 23 LOADED / 43 REJECTED | 23 LOADED / 43 REJECTED | **0** | 10 |
| `incomplete/` | 34 | 18 LOADED / 16 REJECTED | 18 LOADED / 16 REJECTED | **0** | 1 |

**Not one program's verdict changes.**  Every module that loaded still loads and every module
that was rejected is still rejected, `shouldfail/` 40 of 40 included.

**The eleven messages.**  Every one is the SAME refutation — same file, same field, and in nine
of eleven the same source position — reporting a different CLAUSE of it (`two parts of one
partition both contain it` / `the whole contains it but no part does` / `a part contains it but
the whole does not`).  Two are more than that:

* `shouldfail/inf04_except_recursive.e`: `22:7` -> **`20:10`**, and the clause with it.  This is
  S2's known single corpus effect (S2-FIX §4.1): layer (iii) refutes the module EARLIER, at the
  signature that actually carries the contradiction.  Still REJECTED, same field.
* `shouldfail/inf02_substitution_chain.e`: same position `25:7`, the blamed FIELD moves
  `Shouldfail.Inf02.b` -> `Shouldfail.Inf02.a`.

The other nine are the blame-clause churn `Constraints.labelClash`/`labelDecide` document:
`labels` is a `Set[Name]`, so WHICH of several refuting labels and which violated clause is
reported is chosen in a HASH order, which is an ID order — and a different dequeue order shifts
ids.  It decides only which of several true refutations is printed, never whether the system is
refuted (`Constraints.labelDecide`'s comment; S2 review V-13a).

**AND the control, because that harness is not deterministic.**  `corpus-run.sh` runs the
SHIPPED PARALLEL loader, whose thread timing reaches the solver's id order
(`Session.scala:558-560`), so a message that differs between two sides may be run-to-run churn
rather than the flip.

### A1.6b — the same comparison with the loader made deterministic, and its floor

`-Dermine.loadInSeries=true` on both sides, and **each configuration run TWICE**
(`tmp/A1/gates3b.sh`):

| | 66-file corpus | `incomplete/` |
|---|---|---|
| **FLOOR: NEW twice** | **0 of 66 files differ** | **0 of 34** |
| **FLOOR: OLD twice** | **0 of 66 files differ** | **0 of 34** |
| **OLD vs NEW** | **9 of 66 differ — messages only** | **0 of 34** |
| verdicts | 23 LOADED / 43 REJECTED on both | 18 LOADED / 16 REJECTED on both |

So the floor really is zero once the loader is deterministic, the 11 messages of the parallel run
are **9** here (two were loader churn), the `incomplete/` corpus does not move at all, and the
verdict tallies are identical.  Of the 9: six are the blame-CLAUSE at the same field and the
same position; `inf04_except_recursive.e` moves `22:7` -> `20:10` (S2's refutation); `inf02`
keeps its position `25:7` and moves the blamed field `Inf02.a` -> `Inf02.b`; and
`inf05_union_two_fields.e` moves BOTH, `23:18` (`Inf05.a`) -> `23:30` (`Inf05.b`) — it does NOT
keep its position, as this stage first wrote (A1-REVIEW R-5).  Every one of the nine is in
`shouldfail/`, i.e. on a module that is rejected either way and whose rejection is the point.

### A1.7 in full — the published interfaces

Sweep: the whole 110-file example corpus in chunks of ten, interfaces ENABLED (that is what
makes signature changes propagate), `-Dermine.loadInSeries=true` so the loader is deterministic
(D1B review U-1: the shipped PARALLEL loader's thread timing reaches the solver's id order and
made an earlier "zero noise floor" one repetition of a nondeterministic experiment), 900 s per
chunk; both `core/examples` and the stdlib module tree snapshotted and then deleted.

| comparison | result |
|---|---|
| **floor, NEW twice** | **187 of 187 identical — and BYTE-identical**, same md5 `4dda77739572`, `diff -rq` empty |
| **floor, OLD twice** | **187 of 187 identical — and BYTE-identical**, same md5 `69a80fb186fa` |
| **OLD vs NEW**, `einorm3.py` (up to `Set` order and binder names) | **183 identical, 4 DIFFERING**; **0 published on one side only** |
| OLD vs NEW, raw bytes | 17 of 187 files differ — the other 13 are renamings, which is what FINDING 1 of `D1-CHANGE.md` says a byte diff cannot tell you |
| OLD vs NEW, `tracker/tools/ei-classify.py` | **1,891 bindings identical, 13 order-only, 10 alpha-equivalent, 7 other; 0 WEAKER, 0 STRONGER** — no `concrete->polymorphic` anywhere.  **Read that as what it is: "0 signatures weaker" is a statement about THAT classifier's test, not about entailment.**  The entailment statement, which is the one that matters, is below and in §3: one published type is strictly MORE GENERAL (A1-REVIEW R-6) |

*(CORRECTED 2026-09-06 after `tracker/loopmodel/A1-REVIEW.md` R-1, R-2 and R-6.  The reviewer
classified ALL 1,921 bindings with `review-A1/iso2.py` rather than the eight this stage looked
at, and got a different — and better — answer on three of them.  §6 has the old wording.)*

**THE THIRTY BINDINGS THAT MOVE.**  Thirty of 1,921 published bindings differ textually (which is
also what the `ei-classify.py` row above says: 13 + 10 + 7).  The body — the type after `=>`,
which is what a caller applies — is **IDENTICAL in every one**; what moves is the published
residual.  The reviewer's classification, which supersedes this stage's:

| class | count | which |
|---|---|---|
| **the same type under a renaming** | **27** | incl. `np01.inferredRestate`, `RunCalibration.scaledRuns`, `RunCalibration.calibrated`, `Relation.lookbackJoin`, `SoftRelation.groupingDateDrilldown`, `TargetList.restrictTo`, `Signatures.*` |
| **a renaming plus one EXTRA constraint the others ENTAIL** | **1** | `incomplete/RunCalibration.valueAsOf` |
| **one extra bound KIND variable** | **2** | `GridExample.stackedBarChart`, `stackedAreaChart` |
| **genuinely different** | **1** | `incomplete/RevenueShare.shareOfGroup` |

| binding | ex | constraints | verdict |
|---|---|---|---|
| `GridExample.stackedBarChart` | 2 -> 2 | 10 -> 10 | **ALPHA-EQUIVALENT residual**, and the new side's `forall` prefix BINDS a KIND variable the old side defaulted (`{a a1 b b1 c} … (sa: c)` against `{a a1 b b1} … sa`), i.e. it is kind-POLYMORPHIC where the old fixed `*` — more general, never less.  D1B review U-2, already accepted |
| `GridExample.stackedAreaChart` | 2 -> 2 | 10 -> 10 | **ALPHA-EQUIVALENT residual**, same bound kind variable |
| `Relation.lookbackJoin` (stdlib) | 11 -> 11 | 10 -> 10 | **ALPHA-EQUIVALENT** |
| `SoftRelation.groupingDateDrilldown` (stdlib) | — | — | **ALPHA-EQUIVALENT** once the two CLASS variables `Has`/`Has1` are allowed to swap (found by the reviewer; this stage did not list it) |
| `incomplete/RunCalibration.calibrated` | 4 -> 4 | 3 -> 3 | **ALPHA-EQUIVALENT** |
| `incomplete/RunCalibration.scaledRuns` | 7 -> 7 | 6 -> 6 | **ALPHA-EQUIVALENT** under `{a->c, b->a, c->d, d->b, o->o, rs->rs, so->so}` |
| `incomplete/np01.inferredRestate` | 6 -> 6 | 9 -> 7 (**7 -> 7 distinct**: the old side prints **TWO** partitions twice, with their parts permuted) | **ALPHA-EQUIVALENT.**  De-duplicated, both sides carry 7 and the single transposition **`rs <-> rs1`** maps one set onto the other exactly (set difference empty in both directions) |
| `incomplete/RunCalibration.valueAsOf` | 11 -> 11 | 9 -> **10** | **EQUIVALENT — the two residuals entail each other.**  Under `{c->i, d->f, e->g, f->h, g->d, h->e, i->c, c1->c1}` the old nine map onto nine of the new ten; the tenth, `t <- (e, c1, r)`, is ENTAILED by three constraints both sides carry (`t <- (e,d,c)`, `r1 <- (d,c)`, `r1 <- (r,c1)`, so `d (+) c = r1 = r (+) c1`).  The new side publishes one more already-derived fact |
| `incomplete/RevenueShare.shareOfGroup` | 16 -> **17** | 15 -> 15 | **GENUINELY DIFFERENT — and strictly MORE GENERAL.**  See below |

**So: of the thirty bindings that move, twenty-nine are the same type — twenty-seven renamings,
one renaming plus an entailed constraint, and two that additionally BIND a kind the old side
fixed.  ONE genuinely differs.**  (This stage's own first reading — "five of eight are renamings,
three are not" — was wrong on `np01.inferredRestate` and `RunCalibration.scaledRuns` because its checker
mis-parsed a constraint whose left-hand side is a multi-field concrete row, and it never looked
at `groupingDateDrilldown` at all.  R-1.)

**THE ONE THAT DIFFERS, and what it is.**  In `incomplete/RevenueShare.shareOfGroup` every one of
the fifteen old constraints maps onto one of the fifteen new ones **except that wherever the old
side names the UNIVERSAL `k` — the row of the `Row k` argument — the new side names a FRESH
EXISTENTIAL `i`**, and the universal occurs in no constraint at all.  That is the whole
difference, and it is why the new side has 17 existentials to the old side's 16:

```
OLD :  kv2 <- (k, a)      kv <- (k, a, t1)      g <- (k, c)     -- `k` is the UNIVERSAL
NEW :  kv2 <- (i, b)      kv <- (i, b, t1)      j <- (i, d)     -- `i` is EXISTENTIAL
```

So **`OLD |= NEW`** (instantiate `i := k`) but **`NEW |/= OLD`**: the new published residual is
strictly WEAKER as a requirement, i.e. the published TYPE is strictly MORE GENERAL.  **Stated
precisely, because the earlier wording of this report was not**: "no published TYPE is weaker" is
true of `ei-classify.py`'s test, which looks for `concrete -> polymorphic`; it is NOT a statement
about logical entailment, and under entailment this one type IS more general.  Three facts make
that safe, each of them the reviewer's own re-run (R-6):

1. **It is the dequeue order, not the batch or the interfaces.**  Loaded ALONE with
   `-Dermine.useInterface=false`, `:type shareOfGroup` gives the `k`-constrained 16-existential
   form at the OLD configuration and the unconstrained 17-existential form at the new defaults.
2. **The compiler independently CHECKS that more general type for this exact body.**
   `core/examples/incomplete/Signatures.e` carries `shareOfGroupFull`, a HAND-WRITTEN signature
   over the identical body, which leaves the `Row` argument's row unconstrained — alpha-identical
   to the new defaults' residual (verified mechanically, not by eye), and `Signatures.e`
   type-checks and publishes it at **BOTH** configurations.
3. **Nothing regresses.**  `OLD |= NEW` means every call site that discharged the old residual
   discharges the new one: no program that type-checked stops type-checking.  The module's own
   use site, `repShare = shareOfGroup {region} amount regionTotal pctOfRegion bookings`, checks
   under both.

All of which is what the theorems permit and no more: `Loop/PolicyStep.lean`'s `runP_noLoss`,
`runP_models` and `runP_ssat_iff` say the derived SYSTEM is equivalent under any dequeue order,
and `Subst.reduce` publishes from whichever saturated set it is handed — nothing anywhere says
two orders publish the same TEXT.  §A1.7b attributes every one of these to one flag or the other.

**And the operational check that matters:** every chunk of both sweeps returned `rc=0` with
interfaces ENABLED, so every module in the corpus was type-checked against the interfaces the
modules ahead of it had just published, at both configurations.

### A1.7b — ATTRIBUTION: which of the two flags moves the interfaces?

Two more deterministic sweeps of the whole corpus, each with ONE of the two flags at its new
value (`tmp/A1/gates4c.sh`), md5 over all 187 interfaces:

| configuration | md5 | against OLD | against NEW |
|---|---|---|---|
| OLD (`rowSound=false`, `shipped`) | `69a80fb186fa` | — | 183 identical, 4 differing |
| **`rowSound` ON, order SHIPPED** | **`69a80fb186fa`** | **187 of 187 identical — BYTE-IDENTICAL to OLD** | 183 identical, 4 differing |
| **`rowSound` OFF, order `smallcanon` + budget** | **`4dda77739572`** | 183 identical, 4 differing | **187 of 187 identical — BYTE-IDENTICAL to NEW** |
| NEW (both) | `4dda77739572` | 183 identical, 4 differing | — |

**So the answer is unambiguous: `-Dermine.rowSound` does not change one BYTE of any published
interface, and all four moved interfaces are the DEQUEUE POLICY's.**  That reproduces S2's own
`.ei` gate (S2-FIX §A3-5: identical to the base compiler's) on a bigger population and with a
deterministic loader, and it localises the interface-affecting half of this adoption to D1's
flag alone.

### A1.7c — does the fingerprint change force an `.ei` to be regenerated?  NO

**Structurally, from the code**: `Session.scala:479-484`'s `preChecked` reads an existing
interface whenever `typeCheck` and `useInterface` are on and every import of the module was
itself interface-checked.  There is no configuration in that key — `GenRules.toString`'s only
consumer in the tree is `DisjProbe`.

**And measured, not only read** (`tmp/A1/gates4d.sh`, step 2 against step 3).  Delete every
`.ei`, load a module at the OLD configuration so that the 129-module stdlib closure publishes
its interfaces, then load at the NEW defaults WITHOUT deleting them:

```
stdlib boot, stale OLD-configuration interfaces present :  8.44 s
stdlib boot, no interfaces at all                       : 15.12 s
```

The boot is nearly twice as fast because it **READ the interfaces the OLD configuration wrote**.
So a configuration change does NOT invalidate an `.ei`: this is D1B review U-6, confirmed on
this tree.  It is safe today — the interfaces the flip moves are alpha-variants or equivalent
residuals, `rowSound` moves none of them at all (§A1.7b), and a mixed tree loads — and it is the
thing to fix before any INCREMENTAL adoption.

*(The sharper probe the brief suggests — write one module's `.ei` at one configuration and load
an IMPORTER of it at the other — could not be run as such: `bin/ermine` cannot resolve
`Ai.Common` unless it is named on the command line, so the importer failed to load on both
sides.  The stdlib-boot measurement above answers the same question on a 129-module
population.)*

### A1.10 in full — the soundness refutation and the budget death, as a user sees them

The brief asks for one of each.  `seeds/unsat/MIN2` is a JSON constraint system, not an `.e`
module, so it cannot be loaded by any of the three front ends; the module that DOES exercise
layer (iii)'s refutation is `core/examples/shouldfail/inf04_except_recursive.e` — the one corpus
module S2 found (S2-FIX §4.2), and it is refuted by the decision, at the signature that carries
the contradiction.  The budget is exercised on
`core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e` at `-Dermine.solveBudget=20`.

**1. The soundness refutation, `bin/ermine`, new defaults against old** — same file, same field,
an EARLIER position and the clause that the complete decision found:

```
NEW: ...inf04_except_recursive.e:20:10: Row partitions are unsatisfiable at field
     'Shouldfail.Inf04.a': a part contains it but the whole does not
OLD: ...inf04_except_recursive.e:22:7:  Row partitions are unsatisfiable at field
     'Shouldfail.Inf04.a': two parts of one partition both contain it
```

**2. The budget death, `bin/ermine`** — a located error whose wording says what it is:

```
core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e:62:1: Row solver resource
limit reached (this is NOT a type error): the row constraint solver drew 21 fresh row variables
at this signature, past the -Dermine.solveBudget=20 limit, so it was stopped rather than left to
run.  Raise the limit with -Dermine.solveBudget=<n>, simplify the row constraints at this
signature, or report it.
```

**3. Both in the LANGUAGE SERVER** (`tmp/A1/lsp-probe.py`: `initialize`, `didOpen`, read
`textDocument/publishDiagnostics`):

```
DIAGNOSTICS 2 for inf04_except_recursive.e
  line 20 col 10 severity 1: ... Row partitions are unsatisfiable at field 'Shouldfail.Inf04.a':
                             a part contains it but the whole does not
  line 22 col  1 severity 3: ... unchecked: depends on a broken definition

DIAGNOSTICS 1 for gu05_star_join_4dim_concrete_signature.e   (-Dermine.solveBudget=20)
  line 62 col  1 severity 1: ... Row solver resource limit reached (this is NOT a type error): ...
```

**4. Both in the REPL** (`:load <file>`, 129-module session, `tmp/A1/gates7b.sh`) — each is an
ordinary located error and the session stays alive:

```
>> core/examples/shouldfail/inf04_except_recursive.e:20:10: Row partitions are unsatisfiable at
   field 'Shouldfail.Inf04.a': a part contains it but the whole does not
   Unable to load module from 'core/examples/shouldfail/inf04_except_recursive.e' (0.04 seconds)

>> core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e:62:1: Row solver resource
   limit reached (this is NOT a type error): ...
   Unable to load module from '...gu05_star_join_4dim_concrete_signature.e' (0.11 seconds)
```

Both are ordinary published diagnostics at the right position, in all three front ends, and the
tolerant checker keeps going around them (the severity-3 line).  **The caveat the D1 review recorded stands**: the
budget death's WORDING distinguishes a resource limit from a type error, its SEVERITY does not —
it is `severity 1`, an error, beside real type errors.  That is D1 review T-9(b), still partial,
and it is listed among the open gaps.

## 3. What could NOT be done, and what is NOT green

Stated side by side, as this programme's reports do.

| | |
|---|---|
| **The `.ei` cache is still not keyed by the configuration.** | Nothing in the tree keys a published interface by `GenRules.toString`; the loader's `preChecked` (`Session.scala:479-484`) asks only whether type-checking is on, whether interfaces are on, and whether every import was itself interface-checked.  Flipping a default therefore does NOT invalidate an existing `.ei`.  This is D1B review U-6, unchanged by this stage and re-confirmed here (§A1.7c) — it is safe today because the interfaces the flip moves are alpha-variants or equivalent residuals and a mixed tree loads, and it is the thing to fix before any INCREMENTAL adoption |
| **No a-priori fuel number.** | 20,000 is an empirical ceiling with 61x headroom over the largest corpus solve, not a derived one; and a DRAW budget is not a bound on DEQUEUES, which needs a dequeues-per-draw bound (`L5-TERMINATION.md` R8.6b, open for every order including the shipped one).  The budget stops divergence-by-minting; it is not a wall-clock watchdog |
| **The budget diagnostic carries no diagnostic `code`.** | Measured here (§A1.10): it is LSP `severity 1` and the diagnostic JSON has no `code` field (`lsp/Diagnostics.scala:167`), so tooling cannot tell a resource limit from a type error except by reading the prose.  The review's judgement, which this report adopts: **acceptable for adoption** — the budget never fires at 20,000, the wording carries the distinction, and Error IS the right severity for a signature that did not get checked.  **Follow-up: give it a diagnostic `code`** (A1-REVIEW R-9).  D1 review T-9(b), narrowed |
| **ONE published residual is genuinely different, and it is strictly MORE GENERAL.** | §A1.7, as corrected by A1-REVIEW R-1/R-6: of the 30 bindings that move, 29 are the same type (27 renamings, `RunCalibration.valueAsOf` a renaming plus a constraint its siblings entail, `GridExample`'s two additionally BINDING a kind the old side fixed) and **one** — `incomplete/RevenueShare.shareOfGroup` — really differs: the old side names the universal `k` where the new names a fresh existential `i`, so `OLD \|= NEW` but `NEW \|/= OLD`.  **Say it as entailment, not as the classifier's narrow test**: `ei-classify.py` looks for `concrete -> polymorphic` and finds none, but under entailment this one published type IS more general.  Not a defect — `Signatures.shareOfGroupFull` is that same signature written by hand over the identical body and it checks at BOTH configurations, and `OLD \|= NEW` guarantees no call site regresses |
| **The OLD configuration now prints one line.** | `-Dermine.dequeuePolicy=shipped` makes the compiler emit one `NOTE ... the draw budget ... is IGNORED` line on stderr, because the budget's default is no longer 0.  This is the only behavioural difference between the rollback configuration and the pre-adoption compiler.  It appears in every OLD-side gate log in this report |
| **`-Dermine.solveBudget=<not a number>` now means 20,000.** | The `NumberFormatException` fallback moved with the default, so a malformed value silently gets the default budget rather than 0 (`Constraints.scala`, `solveBudgetRequested`).  Defensible — it fails towards the shipped configuration rather than towards no limit — and now recorded (A1-REVIEW R-8) |
| **A user must clear the interface cache once.** | Because `.ei` is not keyed by the solver configuration (the row above), taking this flip in an existing tree leaves interfaces written by the old solver being read by the new one.  `find . -name '*.ei' -delete` once, after the upgrade; see the ADOPTED section of `tracker/ROW-CONSTRAINT-STATE.md` (A1-REVIEW R-4) |
| **The L2 differential is blind to layer (iii)'s verdicts** except through segment truncation. | S2 review V-11, unchanged: `looptrace-diff.py`'s `KEEP` is `step learn in inpart sat solve`, and a refutation emits no record on either side.  "2,355,428 agreeing segments" means the two sides die in the same places, not that they refute the same label with the same reason.  What pins THAT is the seed cross-check (A1.8) and `TestLoopTrace` |
| **`GU05MIN` on the MODEL** | times out at the 120 s cap at every id base on both configurations, as it did for D1; the compiler does it in 256 draws in about a second.  A model-side verdict comparison there measures the cap, not the configuration |
| **The model's `json:` seed loader cannot read S2's `env` block.** | `Loop/Json.lean` has no reader for the `"env"` key `SatTermRepro` gained in S2 (`S2-FIX.md` §P2), so `seeds/unsat/ENV-LINK` is solved on the model WITHOUT the environment fact that makes it unsatisfiable, and it reads `SOLVED -> SOLVED` in the A1.8 model table where the COMPILER has it `SOLVED 10/10 -> REJECTED 10/10`.  This is a pre-existing scope limit of the harness, not something this stage changed, and it does not touch the `--replay` path, which does carry the `senv` records.  Found here; worth a line in whatever picks up next |

## 4. How to re-run everything in this report

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
S=/home/dmitry/.claude/jobs/880c725d/tmp/A1
$S/build.sh     # Lean (LEAN_NUM_THREADS=2) then sbt; FAILS on a non-zero build
$S/gates1.sh    # the fingerprint at five settings, core/test, TestLoopTrace new + OLD
$S/gates2.sh    # the eight-group L2 differential, new defaults then the OLD control
$S/gates3.sh    # corpus verdicts, batch + incomplete, new vs old
$S/gates3b.sh   #   ... the same with -Dermine.loadInSeries=true, each side TWICE (the floor)
$S/gates4.sh    # the .ei sweeps: NEW x2, OLD x2, deterministic loader, einorm3
$S/gates4b.sh   # ei-diff.sh --batch + ei-classify.py, and the stale-interface probe
$S/gates4c.sh   # .ei attribution: rowSound alone, policy alone
$S/gates4d.sh   # does a configuration change invalidate a cached .ei?
$S/gates5.sh    # the seeds: 19 tracked, 7 unsat, env, PANIC3, GU05/GU05MIN, 3840 hunt seeds
$S/gates6.sh    # perf-bench alternated, gu05 load time, layer (iii)'s bill, repl/lsp smoke
$S/gates7.sh    # the two new deaths in the CLI and the language server
$S/gates7b.sh   #   ... and in the REPL
$S/gates8.sh    # the model's LOOP census, old vs new (this is where U-0 shows)
$S/gates8b.sh   # the model's SOLVE path, old vs new -- the verdict comparison that counts
python3 $S/alphaA1.py / $S/prealpha.py   # the .ei isomorphism analysis of A1.7
```

## 5. The diff

`git diff --numstat` at the end of this stage (documentation excluded from the first block):

```
 113  23  core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala
   3   2  core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala
  21   7  core/src/test/scala/com/clarifi/reporting/ermine/loopmodel/TestLoopTrace.scala
  66  26  tracker/lean/Rowpartition/Loop/Main.lean
  25   3  tracker/lean/Rowpartition/Loop/NoFalseAccept.lean
  12   6  tracker/lean/Rowpartition/Loop/State.lean
```

and the documentation:

```
  27   0  tracker/LOOP-MODEL-HANDOFF.md
  18   0  tracker/LOOP-MODEL-PLAN.md
  10   5  tracker/PERF-ROADMAP.md
 100   0  tracker/ROW-CONSTRAINT-STATE.md
  17   0  tracker/lean/README.md
```
plus this file, which is new.

Of the 113 added lines in `Constraints.scala`, three are the defaults themselves and six are the
re-worded warning; the rest is the `ADOPTED 2026-09-06` commentary the earlier flips
(`splitKey`, `splitRow`, `resRow`) established as the form.  Documentation touched:
`tracker/ROW-CONSTRAINT-STATE.md` (a dated ADOPTED section at the top), `tracker/PERF-ROADMAP.md`
(P10 ticked and CLOSED), `tracker/LOOP-MODEL-PLAN.md` (an A1 section and a status row),
`tracker/lean/README.md`, and this file.

**No theorem statement changed.**  The one Lean change that touches a theorem is forced and is
the opposite of a weakening: `({} : Flags)` no longer denotes the pre-adoption configuration, so
`Loop/NoFalseAccept.lean`'s three "the SHIPPED loop ACCEPTS this seed" theorems name it
explicitly through a new `shippedFlags`, each proving exactly the sentence it proved before; and
one theorem is ADDED, `min2_loop_rejects_at_defaults`, which is the new default behaviour in the
kernel.  `Audit.lean` goes 4,115 -> **4,116 theorems, 0 non-standard axioms**.

## 6. POST-REVIEW CORRECTIONS (2026-09-06)

`tracker/loopmodel/A1-REVIEW.md` (576 lines) returned **ADVANCE — commit the flip**, after
documentation corrections only: **no defect in the Scala or the Lean, no gate re-run, no code
change.**  The reviewer re-ran the build, the audit, `core/test`, `TestLoopTrace`, three L2
groups (2,015,595 segments), both corpora with their own floor, the seeds, the smokes, four
alternated perf rounds and an independent `.ei` sweep that reproduced this stage's snapshot
**byte for byte, all 187**.  This section records what changed in the prose, old → new.  The
findings are the review's `R-` numbers.

### 6a The three that mattered

| # | old | new |
|---|---|---|
| **R-1** | §A1.7: *"five of the eight moved bindings are the same type under a renaming; three are not"*, with `np01.inferredRestate` and `RunCalibration.scaledRuns` in the "not isomorphic" column | the reviewer classified **all 1,921 bindings** (`review-A1/iso2.py`), not the eight this stage looked at: **30 differ textually — 27 renamings, 1 a renaming plus an entailed constraint, 2 a bound kind variable, and ONE genuinely different.**  `np01.inferredRestate` IS alpha-equivalent (the old side prints **two** verbatim duplicate constraints, not one; de-duplicated, the single transposition `rs <-> rs1` maps the sets, set difference empty both ways), `RunCalibration.scaledRuns` IS alpha-equivalent under `{a->c, b->a, c->d, d->b}`, and `SoftRelation.groupingDateDrilldown` — which this stage never listed — is one too, once the two CLASS variables `Has`/`Has1` may swap.  **Why this stage got it wrong:** its checker mis-parsed a constraint whose LEFT-HAND SIDE is a multi-field concrete row (`(\|refValue, asOfDate, rigId\|) <- (d, b)` has spaces in it), sending those to a raw-text comparison no renaming could satisfy |
| **R-6** | §A1.7 / §3: *"none of them is WEAKER by the project's own classifier"*, read as a claim that no published type is weaker | **stated as ENTAILMENT, which is the claim that matters.**  `RevenueShare.shareOfGroup` is the one binding that really differs, and it is strictly MORE GENERAL: the old side names the universal `k` in three constraints where the new names a fresh existential `i`, so `OLD \|= NEW` but `NEW \|/= OLD`.  `ei-classify.py`'s "0 weaker" is true of ITS test (`concrete -> polymorphic`) and is not a statement about entailment.  It is safe, and the corpus says why: `core/examples/incomplete/Signatures.e`'s hand-written `shareOfGroupFull` is that same more general signature over the identical body and it checks and publishes at BOTH configurations; `OLD \|= NEW` means no call site regresses; and loaded alone with `-Dermine.useInterface=false` the two forms are reproduced, so it is the dequeue order and not the batch |
| **R-4** | `ROW-CONSTRAINT-STATE.md`'s ADOPTED section explained the `.ei` cache-key gap but never told a user what to DO | the section now says, near the top and in one line: **clear the interface cache once after taking the flip** — `find . -name '*.ei' -delete`, and where they live (`core/examples/**`, `core/target/scala-*/classes/modules/**`) |

### 6b The smaller ones

| # | old | new |
|---|---|---|
| **R-7** | A1.9: *"the sign FLIPS between rounds, so the reading is NO MEASURABLE DIFFERENCE"* | a two-sample claim that did not survive four.  The reviewer's four alternated rounds (`-n 3`, NEW first in 1-2, OLD first in 3-4) put the new defaults slower **every time**, by 0.06-0.46 s on a ~13.6 s cold batch, median **+0.30 s (+2.2 %)**.  Both measurements are now stated, with the host named as the user's loaded desktop: **a small cost, of order 1-3 %, not separable from this host's noise** — and two orders of magnitude smaller than what the policy buys |
| **R-3** | A1.4: *"Total 914, Passed 913, Failed 1 … Unmoved"* | **913 or 912 of 914.**  The reviewer's run was 912/914, the extra failure being `TestInterfaceRoundTrip`, a documented flake that PASSES isolated at both configurations.  Neither figure is a constant; the suite has at least three properties that can give up |
| **R-5** | §A1.6b: `inf02`'s field move given as `b -> a`, and `inf05` described as keeping its position | `inf02` moves `Inf02.a -> Inf02.b` from OLD to NEW (the direction was backwards); `inf05_union_two_fields.e` moves BOTH position and field, `23:18` (`Inf05.a`) -> `23:30` (`Inf05.b`) |
| **R-2** | §A1.7: `GridExample`'s difference called *"one extra VACUOUS `forall` binder"* | it is a bound KIND variable: `{a a1 b b1 c} … (sa: c)` against `{a a1 b b1} … sa`.  The new type is kind-POLYMORPHIC where the old fixed `*` — more general, never less.  D1B review U-2 |
| **R-8** | not recorded | `-Dermine.solveBudget=<not a number>` now means **20,000**, not 0: the `NumberFormatException` fallback moved with the default.  Defensible (it fails towards the shipped configuration) and now in §3 and in the `Constraints.scala` comment's own terms |
| **R-9** | §3: *"the budget diagnostic's SEVERITY"*, listed as a gap | narrowed and judged: the death is LSP `severity 1` with **no `code` field** (`lsp/Diagnostics.scala:167`).  **Acceptable for adoption** — it never fires at 20,000, the wording carries the distinction, and Error is the right severity for a signature that was not checked.  **Follow-up: give it a diagnostic `code`** |

### 6c What did NOT change

No code, on either side; no gate was re-run and none needed to be.  The reviewer found no case
where the compiler and the model disagree, no verdict change, no program newly rejected, no
theorem weakened, and no signature weaker in a way that could accept a call the term does not
support.  Every number in §2 stands as measured except the two the review re-measured (`core/test`
912-or-913, and the perf reading), and both are recorded above with both figures.
