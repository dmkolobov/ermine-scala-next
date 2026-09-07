# A1 — REVIEW of the ADOPTION (the three defaults flipped)

2026-09-06.  Reviewer, second agent.  Repository `/home/dmitry/research/ermine/ermine-scala`,
branch `scala3-migration`, base `c0221fc`.  Brief `tracker/loopmodel/briefs/brief-A1.md`;
implementer's report `tracker/loopmodel/A1-ADOPTION.md`.  Findings are prefixed `R-`.
Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-A1/`.  Nothing was edited except this
file and that directory; no commit, no Lean edit, no Scala edit.

## Verdict

**ADVANCE — commit the flip**, with two documentation corrections that need no re-gate: add the
"clear every `.ei` once" instruction to the ADOPTED section (**R-4**), and correct
`A1-ADOPTION.md` §A1.7, where two of the three bindings it calls "a different saturated set"
are in fact renamings (**R-1**) and the one that really differs publishes a strictly MORE
GENERAL type, which the corpus itself certifies (**R-6**).  Nine findings, none of them a defect
in the Scala or the Lean, none red.  Full ranking in §6.

## 1. Rebuild, re-audit, re-test — re-run, not read

| step | command | my result | implementer's | agree? |
|---|---|---|---|---|
| Lean library | `LEAN_NUM_THREADS=2 lake build Rowpartition` | `Build completed successfully (867 jobs)`, rc=0 | 867 | YES |
| axiom audit | `lake env lean Audit.lean` | `Rowpartition theorems audited: 4116; declarations using a non-standard axiom: 0` | 4,116 / 0 | YES |
| executable | `lake build looptrace` | `Build completed successfully (1670 jobs)` | 1,670 | YES |
| Scala | `sbt -batch -J-Xmx3g core/compile core/test:compile` | rc=0, one `[warn]` line (pre-existing) | `[success]` | YES |

Log: `review-A1/lean-build.log`, `review-A1/sbt-compile.log`.

**Which Lean files can hold a theorem.**  `git diff --stat tracker/lean` touches four files.
`grep -cE '^(theorem|lemma|example)'`: `Loop/Main.lean` **0**, `Loop/State.lean` **0**,
`Loop/NoFalseAccept.lean` **53**.  So the ONLY theorem file changed is `NoFalseAccept.lean`,
as claimed.  `Rowpartition/CutSearch.lean` is still out of the root import list and
`lakefile.toml` has the one `mathlib` require and no other.

**`shippedFlags` proves the same sentence — checked mechanically, not by eye.**  I extracted the
`Flags` structure from `HEAD` and from the working tree and diffed the DEFAULTS field by field
(`review-A1/state_head.lean`, a 20-line script): **16 fields on each side, no field added or
removed, and exactly three defaults move** — `rowSoundBare`, `rowSoundSat`, `rowSoundDecide`,
`false -> true`.  `shippedFlags` sets those three to `false` and takes the other thirteen from
their (unmoved) defaults, so `seedS0 shippedFlags …` denotes exactly what `seedS0 {} …` denoted
at `c0221fc`.  `min1_loop_accepts`, `min2_loop_accepts` and `surv1_loop_accepts` therefore prove
the sentences they proved before; `min2_loop_rejects_at_defaults` is an addition (4,115 -> 4,116).
**No weakening.**

| test | my result | implementer's | agree? |
|---|---|---|---|
| `sbt core/test` (new defaults) | **Total 914, Passed 912, Failed 2** | 913/914 | **NO — see R-3** |
| `core/testOnly *TestLoopTrace`, new defaults | 714 solves; 714 segments; **714 agree**; `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls **46** and **58** of 714; 3 of 3 properties | identical | YES |
| the same with `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` | prints `flags forwarded to both sides: -Dermine.rowSound=false -Dermine.dequeuePolicy=shipped  ->  --flags=norowsound --policy=shipped --trace`; **714/714/714**, same summary line; controls **53** and **65**; 3 of 3 | identical | YES |

**R-3 (LOW, not a defect in this stage).**  `core/test` is **912/914 on my run**.  The second
failure is `TestInterfaceRoundTrip` — *"new-pipeline cold write, fresh warm read, same answers:
Falsified … Expected Some(Interface) but got Some(Full)"*.  I re-ran it **isolated at the new
defaults (PASSES)** and **isolated with the OLD configuration forced (PASSES)**, so it is not
the flip: it is the documented cross-suite dep-cache flake
(`tracker/LSP-ROADMAP.md`, 2026-08-31 D3 part 1, "the Interface round-trip flake"), the same
class the S2 reviewer recorded as `V-4` with a different property.  What is worth saying once
more, since it has now bitten two consecutive reviewers: **"913/914" is not a constant**, and a
report that quotes it as one is quoting a sample.  Logs `review-A1/coretest.log`,
`rt-new.log`, `rt-old.log`, `tlt-new.log`, `tlt-old.log`.

## 2. The defaults, read

`git diff core/src/main` moves **exactly three** property defaults and nothing else in the
solver:

| `Constraints.GenRules` | old | new |
|---|---|---|
| `System.getProperty("ermine.rowSound", …)` | `"false"` | `"true"` |
| `System.getProperty("ermine.dequeuePolicy", …)` | `"shipped"` | `"smallcanon"` |
| `System.getProperty("ermine.solveBudget", …).toInt` | `"0"` | `"20000"` |

`rowSoundFlag(n) = getProperty(n, if (rowSoundAll) "true" else "false")` is UNCHANGED, so the
three sub-flags follow the master exactly as S2 defined them.  The budget-requires-policy rule
(`solveBudget = if (dequeuePolicy == "shipped") 0 else solveBudgetRequested`) is unchanged.
Everything else in the 113 added lines is comment, plus the six-line re-worded warning.
`Subst.scala`'s three lines are comment.  **R-9 (INFO)**: one behavioural line is not a default —
the `NumberFormatException` fallback moves `0 -> 20000`, so `-Dermine.solveBudget=nonsense` now
means 20,000 rather than off.  Consistent with "fall back to the default"; worth knowing.

**The fingerprint, re-measured at five settings** (`review-A1/fingerprint.log`) — every string
is the implementer's, byte for byte:

```
(no flags)                                    cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000
-Dermine.dequeuePolicy=shipped                cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide
-Dermine.rowSound=false -Dermine.…=shipped    cut+label-early+resguard+splitkey+splitrow+resrow          <-- THE ROLLBACK
-Dermine.solveBudget=0                        cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon
-Dermine.rowSound=false                       cut+label-early+resguard+splitkey+splitrow+resrow+pol:smallcanon+budget:20000
model (no flags)                              …+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000   (identical to the compiler's)
model --flags=norowsound                      …+resrow+pol:smallcanon+budget:20000                  (identical to the compiler's)
```

The rollback string is `cut+label-early+resguard+splitkey+splitrow+resrow`.  `GenRules.toString`
itself is untouched by this stage and emits `+rs*` / `+pol:` / `+budget:` only when they are
non-default-off, so the rollback string is byte-identical to the pre-adoption default **by
construction as well as by measurement**.  CONFIRMED.

**The one behavioural difference between the rollback and the pre-adoption compiler**, also
confirmed: `-Dermine.dequeuePolicy=shipped` now prints exactly one line on `stderr`,
`ermine: NOTE the draw budget -Dermine.solveBudget=20000 (the default) is IGNORED because
-Dermine.dequeuePolicy is 'shipped'. …`.  It appeared on both `shipped` rows above and in every
OLD-side gate of mine.  The `(the default)` clause appears only when the property was not set,
as documented.

The `ADOPTED 2026-09-06` comments name their evidence (`A1-ADOPTION.md`, `D1B-REVIEW.md` §8(ii),
`S2-FIX.md` §P1, `Loop/NoFalseAccept.lean`, `Budget.budget_never_accepts`,
`Loop/PolicyStep.lean`) and, in the house style of the `splitKey`/`splitRow`/`resRow` flips,
each also states what the flip does NOT buy.  ACCEPTED.

## 3. The gates, re-run

Every gate below is MY run on this tree, at the NEW defaults, with
`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` (model `--flags=norowsound
--policy=shipped`) as the control.  A number in the "implementer" column that differs from mine
is called out.

### 3a The model side, read (A1.2 / A1.3)

`Loop/Main.lean` is the driver and holds **no theorem** (`grep -c '^theorem\|^lemma\|^example'`
= 0), so none of its 92 changed lines can weaken anything.  What it does:

* `applyFlag` gains **`norowsound`** — required, because with the three layers defaulting ON the
  pre-adoption configuration would otherwise be unreachable from the model's command line and
  `-Dermine.rowSound=false` could not be forwarded.  `rsbare`/`rssat`/`rsdecide` and their `no…`
  forms are unchanged.
* `policyOf` defaults to `.smallCanon`; `defaultBudget = 20000`.
* The `json:` seed path runs `solveSeedP dfPol dfBud …` unless `dfPol = .shipped` and
  `effBudget dfPol dfBud = 0`, in which case it runs the ORIGINAL `solveSeed` — so
  `--policy=shipped` is the pre-adoption path definitionally, not approximately.  The solve is a
  THUNK, so the `--policy=` census, `--depth`, `--cycle` and `--mints` paths do not pay for it.
* `--verdict` appends `+pol:` / `+budget:` for the EFFECTIVE configuration, which is what makes
  the model's fingerprint the compiler's string.  Verified above: identical at the defaults and
  at `--flags=norowsound`.
* `replayMain` moves the `segPol`/`usePol`/`useBud` computation ABOVE the `polMode` branch, so
  the census path now reads the segment's own `sin` policy/budget the way the record path always
  did.  This is a fix, and it is in the right direction.

`TestLoopTrace` forwards `-Dermine.rowSound=false -> --flags=norowsound` and forwards
`dequeuePolicy`/`solveBudget` whenever they DIFFER from the shared default in EITHER direction.
Both directions were exercised above and the forwarding line was printed.  ACCEPTED.
### 3b The L2 corpus differential (A1.5) — three groups, one of them `incomplete/`

`tracker/tools/looptrace-corpus.sh`, `-Dermine.loadInSeries=true`, `-Dermine.useInterface=false`,
model `--replay` taking the policy and budget from each segment's own `sin`:

| group | files | segments | AGREE | skip | hashdiff | eqdiff | rc / timeouts / dropped |
|---|---|---|---|---|---|---|---|
| `boot` | 0 | **54,199** | **54,199** | 0 | 0 | 0 | 0 / 0 / 0 |
| `shouldfail` | 40 | **56,030** | **56,030** | 0 | 0 | 0 | 0 / 0 / 0 |
| **`incomplete`** | 35 | **1,905,366** | **1,905,366** | 0 | 0 | 0 | 0 / 0 / 0 |
| total | 75 | **2,015,595** | **2,015,595** | **0** | **0** | **0** | |

Every figure is the implementer's, digit for digit (`review-A1/l2-new/results.txt`).
`#summary` lines: `nonpart=1009/1048/35573`, `rejected=0/32/9`, `fuel=0` throughout.

**THE TWO MISSING SOLVES — localised, not just explained.**  I re-ran `shouldfail` at the OLD
configuration (compiler `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`, model
`--flags=norowsound`): **56,032 segments, 56,032 agree**.  So the difference really is two, and
the OLD population replays perfectly too.  Counting `sin` records per SITE on both traces
(`review-A1/sf-old2.cnt` vs `sf-new2.cnt`) the whole difference is:

```
site                       OLD      NEW
mkSimplified-extinct     38095    38094      (-1)
trySolveOn               17313    17312      (-1)
everything else          identical
```

**one solve at each of two sites, and nothing else moves anywhere in the 40 files.**  That is
exactly the shape of "the module dies earlier, so two solves that used to follow it never
happen", and it is `shouldfail/inf04_except_recursive.e`, the module S2 identified (§3d confirms
the position move).  CONFIRMED.
### 3c Corpus verdicts (A1.6) — my own runs, with my own floor

`tracker/tools/corpus-run.sh --batch` and `--incomplete --batch`, `-Dermine.loadInSeries=true`
on both sides, `CORPUS_BATCH_TIMEOUT=1800`, compared with `tracker/tools/corpus-verdicts.py`
(NOT `diff -rq`, which reports every file because the `.out` files carry timings):

| comparison | 66-file corpus | `incomplete/` |
|---|---|---|
| verdicts, NEW run A | **23 LOADED / 43 REJECTED** | **18 LOADED / 16 REJECTED** |
| verdicts, NEW run B | 23 / 43 | 18 / 16 |
| verdicts, OLD | 23 / 43 | 18 / 16 |
| **my floor** (NEW twice) | **0 of 66 differ** | **0 of 34 differ** |
| **OLD vs NEW** | **9 of 66 differ — messages only** | **0 of 34 differ** |

**ZERO verdict changes**, my numbers identical to the implementer's.  The nine, in full
(A = OLD, B = NEW):

| file | what moves |
|---|---|
| `der02_copy_column_onto_existing.e` `39:7` | same field `Der02.b`, CLAUSE `two parts…both contain it` -> `the whole contains it but no part does` |
| `der07_shared_three_var_remainder.e` `44:7` | same field `Der07.b`, CLAUSE |
| `dup03_join1_shared_column.e` `30:7` | same field `Dup03.x`, CLAUSE |
| `dup04_joinby_shared_column.e` `30:7` | same field `Dup04.x`, CLAUSE |
| `inc03_project_absent_field.e` `34:7` | same field `Inc03.shipDate`, CLAUSE |
| `inc07_has_helper_missing_column.e` `37:7` | same field `Inc07.customerId`, CLAUSE |
| `inf02_substitution_chain.e` `25:7` | same position, **FIELD** `Inf02.a` -> `Inf02.b` |
| `inf04_except_recursive.e` | **POSITION** `22:7` -> `20:10` and the clause — S2's known earlier refutation |
| `inf05_union_two_fields.e` | **POSITION** `23:18` -> `23:30` AND **FIELD** `Inf05.a` -> `Inf05.b` |

All nine are in `shouldfail/`, i.e. on modules whose rejection is the point, and all nine are
still REJECTED.  Two small corrections to the report (**R-5, LOW**): it gives `inf02`'s field
move in the wrong direction (`b -> a`; it is `a -> b` from OLD to NEW), and it says `inf02`/`inf05`
"keep their position" — `inf05`'s COLUMN moves, `23:18 -> 23:30`.  Neither changes any
conclusion.
### 3d The seeds (A1.8) — my runs

`BulkRunA1` through the shipped `Subst.solve`, one JVM per side, 60 s cap, `-XX:ActiveProcessorCount=2`.

| gate | NEW | OLD | implementer | agree? |
|---|---|---|---|---|
| the 7 `seeds/unsat/*` x 10 bases | **REJECTED 10/10 on all seven — 0 SOLVED of 70** | `ENV-LINK`/`FALSE-ACCEPT-1`/`MIN1`/`SURV1` SOLVED 10/10, `MIN2`/`FALSE-ACCEPT-2` SOLVED 2/10, `PANIC-1` REJECTED 10/10 = **44 SOLVED of 70** | 0 of 70 / 44 of 70 | **YES, seed for seed** |
| 19 tracked seeds x 10 bases | 190 runs | 190 runs | | |
| … VERDICT lines differing | **0** | | 0 | YES |
| … FULL lines differing, `Set` order normalised | **2 of 190** | | 2 | YES |
| … and they are | `H2` base 9 `v2 := unbound -> 14`; `NE6` base 8 `v2 := 17 -> unbound` | | the same two | **YES, same seed, same base, same variable** |
| `run.sh env` | **`cases=9 differ=0 decide=true`** | **`cases=9 differ=4 decide=false`** | same | YES |
| `PANIC3` x 100 bases | **SOLVED=100 REJECTED=0 HANG=0**, `DRAWN min=median=max=0` | | 100/0/0 | YES |
| `slow/GU05.json` x 25 bases | **SOLVED 25/25, `DRAWN min=median=max=306`** | | 306 at all 25 | YES |
| `slow/GU05MIN.json` x 10 bases | **SOLVED 10/10, 256 at every base** | | 256 | YES |
| 500-seed slice of the round-8 hunt x 3 bases | **1,500 runs, SOLVED 1,500 of 1,500** | **1,500 of 1,500** | 11,520/11,520 on the full 3,840 | YES |
| … VERDICT differences | **0** | | 0 | YES |
| … substitution lines differing | **35 of 1,500 (2.3 %)** | | 379 of 11,520 (3.3 %) | same phenomenon |
| … and every per-variable difference is | **alias -> unbound 22, unbound -> alias 16, alias -> alias 10 — NOT ONE concrete row assignment moves** | | the same three classes | **YES** |
| the draw budget | **`DRAWBUDGETHITS=0`** on all 1,500 + 190 + 70 runs; `rowSoundBudgetHits=0`, `rowSoundCheckFails=0` everywhere | | 0 | YES |

The two alias-vs-unbound substitution differences on the tracked seeds are the SAME two rows the
implementer reports, at the same seed, base and variable.  My first pass counted 10 rather than
2 because normalising `HashSet(` to `Set(` is not enough — the ELEMENTS inside a printed `Set`
also come out in a hash order, and eight of the ten differed only in that.  `review-A1/subcmp.py`
sorts them and then classifies each variable, which is how the 2 and the alias/unbound breakdown
above are obtained.  Anyone reproducing this should use it rather than a raw `diff`.
### 3e The two diagnostics as a user sees them (A1.10)

Reproduced verbatim on my tree.  CLI, `bin/ermine`, `-Dermine.useInterface=false
-Dermine.loadInSeries=true`:

```
NEW: core/examples/shouldfail/inf04_except_recursive.e:20:10: Row partitions are unsatisfiable
     at field 'Shouldfail.Inf04.a': a part contains it but the whole does not
OLD: core/examples/shouldfail/inf04_except_recursive.e:22:7:  Row partitions are unsatisfiable
     at field 'Shouldfail.Inf04.a': two parts of one partition both contain it

core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e:62:1: Row solver resource
limit reached (this is NOT a type error): the row constraint solver drew 21 fresh row variables
at this signature, past the -Dermine.solveBudget=20 limit, so it was stopped rather than left
to run.  Raise the limit with -Dermine.solveBudget=<n>, simplify the row constraints at this
signature, or report it.
```

Language server (`initialize` / `didOpen` / `publishDiagnostics`):

```
DIAGNOSTICS 2 for inf04_except_recursive.e
  line 20 col 10 severity 1  … a part contains it but the whole does not
  line 22 col  1 severity 3  … unchecked: depends on a broken definition
DIAGNOSTICS 1 for gu05… (-Dermine.solveBudget=20)
  line 62 col  1 severity 1  … Row solver resource limit reached (this is NOT a type error) …
```

`repl-smoke.sh` **PASS** — aliasing (2), relations (6), scoping (4), smoke (23), `rc=0`.
`lsp-smoke.sh` **PASS** — lsp (98 checks), `rc=0`.  Both figures are the implementer's.

**The budget diagnostic's SEVERITY — my answer to the question the brief asks.**  It is
`severity 1` (Error), beside real type errors, and `Diagnostics.scala:167-174` emits only
`range` / `severity` / `source:"ermine"` / `message` — there is no `code` field, so an IDE has
nothing but the prose to tell a resource limit from a type error.  **Is that acceptable for
adoption?  Yes — it is not a blocker, and it should not hold the flip.**  Three reasons:
(1) Error is the *correct* LSP severity — the file did not type-check, and a warning would be a
lie; (2) it is unreachable in practice at the adopted value — the budget fired ZERO times across
my 1,690 seed runs, the 2,015,595-segment corpus differential and both corpora, and 20,000 is
61x the largest corpus solve; (3) the wording already carries the distinction, in the first
clause, in the CLI, the REPL and the LSP alike.  **The follow-up I would file** (not a
precondition): give the diagnostic a machine-readable `code` (e.g. `ermine/row-solver-budget`)
so tooling can filter it, since `Diagnostics.range` would have to grow the field anyway.
### 3f Performance (A1.9) — the one number of mine that does not reproduce

`tracker/tools/perf-bench.sh batch -n 3`, cold, interface-free, `PERF_JVM_PROPS=
-XX:ActiveProcessorCount=2 [+OLD]`, `PERF_MAX_LOAD=6.0`, **FOUR alternated rounds** (NEW first
in rounds 1-2, OLD first in rounds 3-4), `ei_after=0` on every run:

| round | NEW cold median | OLD cold median | NEW − OLD | loads (NEW / OLD) |
|---|---|---|---|---|
| 1 | 13.58 s | 13.43 s | **+0.15** | 4.90 / 4.50 |
| 2 | 13.90 s | 13.44 s | **+0.46** | 3.95 / 3.92 |
| 3 | 13.82 s | 13.76 s | **+0.06** | 3.77 / 2.74 |
| 4 | 13.83 s | 13.61 s | **+0.22** | 4.48 / 3.45 |
| median | **13.83** | **13.53** | **+0.30 (+2.2 %)** | |

**R-7 (LOW — a number of mine that differs).**  The report says the sign FLIPS between its two
rounds and reads that as "no measurable difference".  **In my four alternated rounds the sign
does not flip: the new defaults are slower in all four**, by 0.06–0.46 s on a ~13.6 s cold
stdlib batch, median +0.30 s (+2.2 %).  Round 2 is the cleanest pair (loads 3.95 against 3.92)
and is +0.46 s (+3.4 %).  Each individual difference is inside a single run's own spread
(0.39–0.77 s over 3 reps) and this host is the user's loaded desktop, so I would not call it
resolved either — but "the sign flips" is a two-sample claim and it did not survive four.  The
honest statement for the record is **"a small cost, of order 1–3 % on the cold stdlib batch,
not separable from the noise on this host, and two orders of magnitude smaller than what the
policy buys"** (`incomplete/gu05`'s ten-file chunk: 629 s -> 11 s).  It is not a blocker and it
does not change the verdict; the report's wording should.

### 3g My own `.ei` sweep, against the implementer's snapshot

Because the whole `.ei` analysis of §4 rests on snapshots I did not take, I re-ran the
deterministic sweep myself at the NEW defaults — same chunking (10 files, `Ai/Common.e`
prepended where needed), `-Dermine.loadInSeries=true`, interfaces ENABLED, all eleven chunks
`rc=0` — and compared it to `tmp/A1/ei-new-1`:

```
interfaces: 187
vs the implementer's ei-new-1: 0 files differ
```

**Byte for byte, all 187.**  So the snapshots are this tree's output, the floor really is
byte-stable at a configuration, and everything in §4 is grounded.  Every `.ei` I caused under
`core/examples` and `core/target/scala-3.3.8/classes/modules` was deleted afterwards (`find … -name
'*.ei' | wc -l` = 0 in both; the only `.ei` left in the tree are the 143 committed under
`tracker/g1-baseline/ei/`).

## 4. THE `.ei` QUESTION — settled

### 4a The sweep's own numbers, re-derived from the implementer's snapshots

The four deterministic sweeps (`tmp/A1/ei-{old,new}-{1,2}`) plus the two attribution sweeps
(`ei-rs` = `rowSound` alone, `ei-pol` = policy alone) are all 187 interfaces.  Hashing every
file in every sweep myself:

| sweep | aggregate md5 over all 187 | equals |
|---|---|---|
| `ei-old-1`, `ei-old-2`, **`ei-rs`** | `9deffcc4b2bd…` | **all three byte-identical** |
| `ei-new-1`, `ei-new-2`, **`ei-pol`** | `254eeee39cd8…` | **all three byte-identical** |

So, re-derived rather than taken on trust: the floor is **byte-identical at each configuration**;
**`-Dermine.rowSound` changes NOT ONE BYTE of any of the 187 interfaces** (the `rowSound`-only
sweep IS the old sweep, file for file); and **every interface the adoption moves is the dequeue
policy's** (the policy-only sweep IS the new sweep, file for file).  17 of 187 files differ
between OLD and NEW at the raw byte level — the same 17 the report lists.  A1.7b: CONFIRMED.

### 4b I classified all 1,921 bindings myself, and I get a different answer

The report analyses **eight** moved bindings.  Comparing the two deterministic sweeps binding by
binding I find **30 that differ textually** (which is also what the report's own
`ei-classify.py` row says: 13 order-only + 10 alpha + 7 other = 30).  I wrote my own isomorphism
checker (`review-A1/iso2.py`) that maps `forall` binders POSITIONALLY, de-duplicates verbatim
constraints, compares a concrete row as a SET of field names and a partition's parts as a
MULTISET, renames class-variable heads, and searches the existential bijection by backtracking:

| class | count | which |
|---|---|---|
| **ISO** — the same type under a renaming | **27** | incl. `np01.inferredRestate`, `RunCalibration.scaledRuns`, `Relation.lookbackJoin`, `SoftRelation.groupingDateDrilldown`, `TargetList.restrictTo`, `Signatures.*` |
| **ISO_PLUS** — a renaming plus one EXTRA constraint on the new side | **1** | `incomplete/RunCalibration.valueAsOf` |
| **NOISO** | **1** | `incomplete/RevenueShare.shareOfGroup` |
| **kind-prefix** — one extra bound KIND variable | **2** | `GridExample.stackedAreaChart`, `stackedBarChart` |

**R-1 (MEDIUM, a correction in the adoption's FAVOUR).**  Two of the report's three
"genuinely different, not a renaming" bindings ARE renamings, and the report's §A1.7 verdict
column is wrong on them:

* **`incomplete/np01.inferredRestate` is ALPHA-EQUIVALENT.**  The report says "not isomorphic"
  because the old side prints 9 constraints and the new 7.  But the old side's extra two are
  VERBATIM DUPLICATES with their parts permuted (`r <- (C, rs, a, rs1)` again as
  `r <- (C, a, rs1, rs)`; `t1 <- (C', rs1, a)` again as `t1 <- (C', a, rs1)`) — note the report
  itself says "the old side prints ONE partition TWICE"; it is **two**.  De-duplicated, both
  sides have 7, and the single transposition **`rs <-> rs1`** maps one set onto the other
  exactly.  I verified it by applying that map and taking the set difference in both directions:
  **empty both ways, |S|=7 = 7.**
* **`incomplete/RunCalibration.scaledRuns` is ALPHA-EQUIVALENT** under
  `{a->c, b->a, c->d, d->b, o->o, rs->rs, so->so}`; all six constraints map 1:1.  (My first
  checker also called this one NOISO — because a constraint whose LEFT-HAND SIDE is a
  multi-field concrete row, `(|refValue, asOfDate, rigId|) <- (d, b)`, has spaces in it and
  broke a `(\S+) <- ` regex.  Anyone re-doing this analysis should watch for that; it is
  plausibly why the report's own tooling misclassified `np01`.)
* Likewise `SoftRelation.groupingDateDrilldown`, which the report does not list at all, is
  alpha-equivalent once the two CLASS variables `Has`/`Has1` are allowed to swap.

**`incomplete/RunCalibration.valueAsOf`: EQUIVALENT, and here is the proof.**  Under
`{c->i, d->f, e->g, f->h, g->d, h->e, i->c, c1->c1}` the old side's nine constraints map exactly
onto nine of the new side's ten.  The tenth, on the new side only, is **`t <- (e, c1, r)`**, and
it is ENTAILED by three constraints both sides carry:

```
t  <- (e, d, c)     and   r1 <- (d, c)   and   r1 <- (r, c1)
  ==>  d (+) c = r1 = r (+) c1  ==>  t = e (+) d (+) c = e (+) r (+) c1  ==>  t <- (e, c1, r)
```

so NEW |= OLD (drop a conjunct) and OLD |= NEW (derive it).  The two residuals **entail each
other**, the free variables are the same up to the renaming, and the body (`Field r Date ->
Relation r1 -> Relation a -> Relation b`) is identical.  The new side simply publishes one more
already-derived fact.  **NOT a weakening.**

### 4c `RevenueShare.shareOfGroup` — the one that really differs, and what it is

The difference is **exactly one thing**, and I pinned it constraint by constraint.  Under the
positional `forall` map (`k,a,b,c` -> `a,b,c,d`) every one of the fifteen old constraints maps
onto one of the fifteen new ones (one pair, `d1 <- (o,d,c)` vs `e1 <- (o,b,f)`, only after the
one-step rewrite `d1 (+) d = b (+) f` that two other constraints give) **except that wherever
the old side names the UNIVERSAL `k` — the row of the `Row k` argument — the new side names a
FRESH EXISTENTIAL `i`**.  That is the whole of it, and it is why the new side has 17
existentials to the old side's 16:

```
OLD :  kv2 <- (k, a)      kv <- (k, a, t1)      g <- (k, c)          -- `k` is the universal
NEW :  kv2 <- (i, b)      kv <- (i, b, t1)      j <- (i, d)          -- `i` is existential,
                                                                     -- and `a` (= old `k`)
                                                                     -- occurs in NO constraint
```

So **OLD |= NEW** (instantiate `i := k`) but **NEW |=/= OLD**: the new residual is strictly
WEAKER, i.e. the published type is strictly MORE GENERAL.  The report's "no published TYPE is
weaker by `ei-classify.py`" is true of that classifier (it looks for `concrete -> polymorphic`);
it is not true of ordinary logical entailment, and the report should not be read as claiming it.

**Is that RED?  No — and the corpus itself settles it.**  Three facts, each re-run:

1. **It is not an artefact of the batch or of interfaces.**  Loaded ALONE with
   `-Dermine.useInterface=false`, `:type shareOfGroup` gives the `k`-constrained, 16-existential
   form at the OLD configuration and the `a`-unconstrained, 17-existential form at the new
   defaults (`review-A1/shareOfGroup-alone.log`).  It is the dequeue order.
2. **The NEW residual is a type the compiler independently CHECKS for this exact body.**
   `core/examples/incomplete/Signatures.e` carries `shareOfGroupFull`, a HAND-WRITTEN signature
   over the identical body (`let totals = rename amtF totF (groupBy keyRow (sumBy amtF) r) in
   combine_Op …`, verbatim the same three lines), and that signature **leaves the `Row` argument's
   row unconstrained** — it is alpha-identical to the new defaults' residual, term by term
   (I checked the sixteen constraints under
   `{i->e1, e1->j, f1->i, h->f1, g->g, j->h, r->r1, …}`), and I proved that MECHANICALLY, not by
   eye: turning `shareOfGroupFull`'s free row variables into an explicit `exists` block and
   applying the ONE entailed rewrite `e1 <- (o, b, f)  ==  e1 <- (o, e, d1, f)` (justified by
   `b <- (e, d1)`, which both carry), my checker reports **ISO**.  `Signatures.e` type-checks and
   publishes that signature **at BOTH configurations** (my checker: `shareOfGroupFull` OLD vs NEW
   = ISO).  So the more general type the flip publishes is one the compiler verifies for the
   term, twice, by a route that does not depend on the dequeue order.
3. **Nothing regresses.**  `OLD |= NEW` means every call site that discharged the old residual
   discharges the new one: no program that type-checked stops type-checking.  The extra call
   sites the new residual admits are justified by (2).  And the module's own use site,
   `repShare = shareOfGroup {region} amount regionTotal pctOfRegion bookings`, checks under both.

The honest summary is therefore the opposite of a red flag: **of the three bindings the report
calls "a different saturated set", two are renamings and the third publishes a MORE GENERAL type
that the corpus independently certifies.**  What must change is the REPORT's wording (R-1, R-2),
not the code.

**R-2 (LOW).**  `GridExample.stackedAreaChart` / `stackedBarChart`: the new side's `forall`
prefix is `{a a1 b b1 c} … (sa: c) …` where the old side's is `{a a1 b b1} … sa …` — the new
side BINDS the kind of `sa` instead of defaulting it.  This is D1B review U-2's "one vacuous
implicit kind binder", already reviewed and accepted; it makes the new type kind-POLYMORPHIC
where the old one fixed a kind, i.e. more general again, never less.  Worth stating as "a kind
binder" rather than "a vacuous forall binder", which is what the report calls it.

### 4d The cache-key gap, re-confirmed, and what a user must be told

`Session.scala`'s `preChecked` keys a warm read on `typeCheck`, `useInterface` and whether every
import was itself interface-checked; `GenRules.toString`'s only consumer in the tree is
`DisjProbe`.  So **no `.ei` is invalidated by this flip** — the implementer measured it (a stdlib
closure written at the OLD configuration is READ at the new defaults, 8.44 s against 15.12 s cold)
and the code says the same.  CONFIRMED, and it is correctly listed as an open gap.

**R-4 (MEDIUM — the one documentation change I would require before the commit).**  The ADOPTED
section of `ROW-CONSTRAINT-STATE.md` explains the gap but never tells a user what to DO about it.
It must say, in one line, near the top: **delete every `.ei` once, after taking the flip** —

```
find . -name '*.ei' -delete        # or at least:
find core/examples core/target/scala-*/classes/modules -name '*.ei' -delete
```

Interfaces live next to their source (`core/examples/**/*.ei`) and, for the stdlib, in
`core/target/scala-3.3.8/classes/modules/**/*.ei` (150 of them in this tree right now).  Without
that line a user upgrades into a tree where some interfaces were written by the old solver and
some by the new one, silently.  It is safe here — the difference is a renaming or a strictly more
general type, and a mixed tree loads — but "safe" is a measurement on THIS corpus, and the
instruction costs one line.

## 5. Docs and acceptance

### 5a The documents

* **`tracker/ROW-CONSTRAINT-STATE.md`** — a dated ADOPTED section at the top: the three defaults
  in a table, the one-line rollback, why each and why as a SET (the `U-0` argument, correctly
  stated), a gate table, and the three open gaps.  Accurate against my runs except that the gate
  table repeats the perf claim (R-7) and the "0 signatures weaker" line (R-6).  **Missing: the
  `.ei` clear-once instruction (R-4).**
* **`tracker/PERF-ROADMAP.md`** — P10 ticked and marked CLOSED with the reason ("the default
  MOVED"), the old text preserved, a pointer to A1.9.  Correct: `U-4` said the box stays unticked
  *until a default moves*, and one has.  ACCEPTED.
* **`tracker/LOOP-MODEL-PLAN.md`** — an A1 section and a status row marked *(pending)* awaiting
  this review.  ACCEPTED.
* **`tracker/lean/README.md`** — the model's defaults, the `norowsound` token, the `shippedFlags`
  explanation, 867 / 4,116 / 1,670.  All three figures re-run and correct.  ACCEPTED.

### 5b The brief's items

| item | verdict | evidence |
|---|---|---|
| A1.1 Scala defaults + `ADOPTED` comments | **PASS** | §2; exactly three defaults move, sub-flags follow the master, budget-requires-policy rule intact |
| A1.2 model defaults, rebuild, audit | **PASS** | 867 jobs, 4,116 theorems / 0 non-standard axioms, looptrace 1,670; `Flags` diffed field by field |
| A1.3 `TestLoopTrace` forwarding | **PASS** | both directions, forwarding line printed |
| A1.4 `core/test`, `TestLoopTrace` x2 | **PASS** (with R-3) | 912/914 on my run — the second failure is the documented round-trip flake and passes isolated at BOTH configurations; 714/714/714 twice |
| A1.5 eight-group L2 differential | **PASS** for the three groups I ran | 2,015,595 / 2,015,595 agree, 0 skip/hashdiff/eqdiff; the two-segment difference localised to one solve at each of two sites |
| A1.6 corpus verdicts | **PASS** | 23/43 and 18/16 on all three runs, 0 verdict changes, my own floor 0/66 and 0/34, 9 message moves |
| A1.7 `.ei` sweep, "0 signatures weaker" | **PASS with a correction (R-1, R-6)** | 187 interfaces reproduced byte for byte; `rowSound` moves not one byte; 27 of 30 moved bindings are renamings, 1 is a renaming plus an entailed constraint, 2 are a kind binder, 1 is strictly MORE GENERAL |
| A1.8 seeds | **PASS** | 0 SOLVED of 70; 0 verdict changes on 190 and on 1,500; 2 and 35 substitution lines, all alias-vs-unbound; `differ=0`; 306 / 256; PANIC3 100/100; budget never fired |
| A1.9 performance | **PARTIAL (R-7)** | four alternated rounds, NEW slower in all four by a median 0.30 s (+2.2 %), inside a single run's spread |
| A1.10 smoke + the two diagnostics | **PASS** | repl-smoke 2/6/4/23, lsp-smoke 98, both deaths located in CLI and LSP; budget at severity 1 (accepted, see §3e) |
| A1.11 docs | **PASS with R-4** | the ADOPTED section must gain the clear-`.ei` line |

## 6. Findings, ranked

| # | sev | where | what | fix |
|---|---|---|---|---|
| **R-1** | MED | `A1-ADOPTION.md` §A1.7 table and §3 | Two of the three bindings called "a different saturated set, not a renaming" ARE renamings: `np01.inferredRestate` is alpha-equivalent under `rs <-> rs1` once the old side's TWO verbatim duplicate constraints are collapsed (the report says "ONE partition twice"), and `RunCalibration.scaledRuns` is alpha-equivalent under `{a->c,b->a,c->d,d->b}`. `SoftRelation.groupingDateDrilldown`, which the report does not list, is also a renaming (the two CLASS variables swap). CONFIRMED, mechanically | rewrite §A1.7: **one** binding genuinely differs, not three |
| **R-6** | MED | same | The one that does — `RevenueShare.shareOfGroup` — is not merely "different": it is strictly WEAKER, i.e. the published type is strictly MORE GENERAL. Every constraint maps 1:1 except that the old side names the universal `k` where the new names a fresh existential `i`, so `OLD \|= NEW` but `NEW \|/= OLD`. "No published TYPE is weaker" is true of `ei-classify.py`'s test, not of entailment. **Not a defect**: `Signatures.shareOfGroupFull` is that same weaker signature written by hand over the identical body and it checks at BOTH configurations, and `OLD \|= NEW` means no call site regresses. CONFIRMED | say it plainly in §A1.7 and §3, with the `shareOfGroupFull` certificate |
| **R-4** | MED | `ROW-CONSTRAINT-STATE.md` ADOPTED section | The `.ei` cache gap is explained but the user is never told what to DO. Add: **delete every `.ei` once after taking the flip**, and where they live (`core/examples/**`, `core/target/scala-*/classes/modules/**`). CONFIRMED (the loader has no configuration in its key; measured by the implementer, re-confirmed by me structurally) | one line, near the top of the section |
| **R-7** | LOW | `A1-ADOPTION.md` A1.9, `ROW-CONSTRAINT-STATE.md` gate table | "the sign FLIPS … no measurable difference" is a two-sample claim. Four alternated rounds of mine put the new defaults slower every time, median +0.30 s (+2.2 %) on a 13.6 s cold stdlib batch. CONFIRMED (as a measurement; the effect is inside a run's own spread) | reword to "a small cost of order 1–3 %, not separable from this host's noise" |
| **R-3** | LOW | `A1-ADOPTION.md` A1.4, and the programme generally | `core/test` was **912/914** on my run; the extra failure is `TestInterfaceRoundTrip`, the flake `LSP-ROADMAP.md` names, and it PASSES isolated at both configurations. Second consecutive reviewer to hit a second failure (S2 review `V-4` hit a different one). CONFIRMED | quote 913/914 as "913 or 912 of 914, the second failure being one of two known flakes" |
| **R-5** | LOW | `A1-ADOPTION.md` §A1.6b | `inf02`'s field move is given backwards (it is `Inf02.a -> Inf02.b` from OLD to NEW), and `inf05` does NOT keep its position (`23:18 -> 23:30`). CONFIRMED | correct the two lines |
| **R-2** | LOW | `A1-ADOPTION.md` §A1.7 | `GridExample.stackedAreaChart`/`stackedBarChart` differ by a bound KIND variable (`{a a1 b b1 c}` … `(sa: c)` against `{a a1 b b1}` … `sa`), not by "a vacuous `forall` binder"; that makes the new type kind-polymorphic where the old fixed `*` — more general, never less. This is D1B `U-2`, already accepted. CONFIRMED | one word |
| **R-8** | INFO | `Constraints.scala` | `-Dermine.solveBudget=<not a number>` now means 20,000, not 0 (the `NumberFormatException` fallback moved with the default). Defensible; undocumented | a clause in the comment |
| **R-9** | INFO | `lsp/Diagnostics.scala:167` | The budget death is `severity 1` and the diagnostic JSON carries no `code`, so tooling cannot tell a resource limit from a type error except by prose. **Acceptable for adoption** (§3e); file a follow-up for a `code` | follow-up ticket |

Nothing above is a defect in the Scala or the Lean.  I found **no** case where the compiler and
the model disagree, **no** verdict change, **no** program newly rejected, **no** theorem
weakened, and **no** signature that is weaker in a way that could accept a call the term does not
support.

## 7. Verdict

**ADVANCE — commit the flip**, after the two-line documentation fix (R-4 must be in the ADOPTED
section; R-1/R-6 must be corrected in `A1-ADOPTION.md` §A1.7 so the record is right).  Neither
touches code, neither needs a re-gate.

The bar the earlier adoptions met is met here.  Nothing is red: the Lean builds and audits at
867 / 4,116 / 0 non-standard axioms with the only theorem-file change being an explicit
`shippedFlags` that I verified proves the same sentence (16 `Flags` fields, exactly three
defaults moved) plus one ADDED theorem; the three moved defaults are exactly the three; the
rollback string is byte-identical to the pre-adoption default and the one extra `NOTE` line is
its only observable difference; 2,015,595 corpus solve segments agree record for record with 0
skips over three groups including `incomplete/`; not one corpus verdict moves on either corpus,
with my own zero floor; 44 false acceptances of 70 become 0; `differ=4` becomes `differ=0`;
`GU05` is 306 draws at all 25 bases; 1,690 seed runs move no concrete row and never touch the
budget; the smoke suites pass; and the published interfaces reproduce byte for byte, with
`-Dermine.rowSound` moving not one byte of any of the 187.

**On the three "saturated set" bindings the brief singles out: two of them are renamings, and
the third is not a weakening of any guarantee.**  `np01.inferredRestate` and (though the report
does not name it) `SoftRelation.groupingDateDrilldown` are alpha-equivalent; `RunCalibration.scaledRuns`
is too; `RunCalibration.valueAsOf` is a renaming plus one constraint that its own siblings entail,
so the two residuals entail each other; and `RevenueShare.shareOfGroup` publishes a strictly more
general type that `core/examples/incomplete/Signatures.e` independently certifies for the
identical body at BOTH configurations, with `OLD |= NEW` guaranteeing that no call site regresses.

**What a user must do at adoption:** nothing to their code — but **clear the interface cache
once.**  `.ei` files are not keyed by the solver configuration, so a tree built before the flip
keeps feeding pre-flip interfaces to the post-flip compiler; it loads today (measured), but the
one-line habit is `find . -name '*.ei' -delete` (they live beside the sources under
`core/examples/**` and, for the stdlib, under `core/target/scala-*/classes/modules/**`).  To go
back to the old compiler exactly: `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped`,
which also turns the draw budget off and prints one `NOTE` line saying so.

## 8. How to re-run this review

```
S=/home/dmitry/.claude/jobs/880c725d/tmp/review-A1
$S/seeds.sh     # the 7 unsat x10, 19 tracked x10 NEW/OLD, env, PANIC3, GU05/GU05MIN, 500 hunt seeds x3
$S/corpus.sh    # corpus verdicts, batch + incomplete, NEW twice (the floor) and OLD
$S/misc.sh      # the two diagnostics (CLI + LSP), repl-smoke, lsp-smoke, perf rounds 1-2
$S/misc2.sh     # perf rounds 3-4 and my own 187-interface .ei sweep against the snapshot
python3 $S/iso2.py <old-ei-dir> <new-ei-dir>          # the binding isomorphism classification
python3 $S/subcmp.py <old.tsv> <new.tsv>              # Set-order-normalised substitution diff
# the L2 differential:
LOOPTRACE_GROUPS="boot shouldfail incomplete" tracker/tools/looptrace-corpus.sh $S/l2-new
LOOPTRACE_GROUPS="shouldfail" LOOPTRACE_FLAGS="--flags=norowsound" \
  LOOPTRACE_JAVA="-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped" \
  tracker/tools/looptrace-corpus.sh $S/l2-old2
```
