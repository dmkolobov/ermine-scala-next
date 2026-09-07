# Row-constraint work — state as of 2026-09-07

## 2026-09-07: **FIXED — the published residual no longer carries permuted duplicates or `a <- (a)`** (loop model, stage S3)

`Subst.mkSimplified` has documented since it was written that its job (1) is to "eliminate all but
one permutation of a right hand side for partitions of a given variable".  It never did.
`NormalPart` overrides `equals` (ignoring `loc`, comparing `abstrakt` SORTED) and **not**
`hashCode`, and `List.distinct` is `distinctBy(identity)` over a `mutable.HashSet`, so two permuted
copies of one constraint hashed into different buckets and were never compared.  Beside it,
`normalPart` had a `None` case for the concrete identity `(|Foo|) <- (|Foo|)` and none for the
variable identity `a <- (a)`.  Both are one-line omissions; both are now fixed
(`core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala`, +13 −1, nothing else touched).
Origin `tracker/ROSE-COMPARISON.md` §3 rank 1; report `tracker/loopmodel/S3-SIMPLIFY.md`
(§11 = the post-review corrections), review `tracker/loopmodel/S3-REVIEW.md`.
**REVIEWED 2026-09-07: ADVANCE (commit) after documentation corrections, findings K-1…K-9, no defect
in the change** — both compilers rebuilt in a throwaway worktree, every gate re-run, the whole corpus
re-swept, and entailment-equivalence re-decided with an independent CNF+DPLL checker that also
compares bodies, binders, class multisets and binding sets: **21 of 21 EQUIVALENT, 0 weaker, 0
stronger**, and every load-bearing number below reproduces to the digit.  The corrections are applied
here and in the report.

**Reproduction, one JVM, two modules.**  `incomplete/TopReadings.e`'s `topRowsBy` published
`b <- (c, h), h <- (h), b <- (h, c)` — a tautology and a permuted duplicate in the same three-element
residual — and now publishes `b <- (h, c)`, which is `Has b h`, the signature the module's own header
says a competent user expects.  `incomplete/np01_add_or_recompute.e`'s `inferredRestate` published
nine partitions with two permuted pairs and now publishes **seven**, the number `A1-REVIEW.md` §R-1
reached by hand.

**Gates.**  `core/test` 913/914 (the known `Constraints.disjunction sound` starvation);
`TestLoopTrace` **714/714** (`skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`) — note
that this property **passes VACUOUSLY in a tree without `tracker/lean/.lake/build/bin/looptrace`**
and still reports `Passed: Total 3`, so quote it only with the binary present or
`-Dermine.looptrace=<path>` (review K-7);
`looptrace-corpus.sh` groups `boot` and `Wide`, model-vs-compiler **54,199/54,199** and
**115,864/115,864** agree with 0 skips on BOTH sides; `corpus-run.sh --batch` **0 verdict changes**
over the 130 files common to the two runs (69 LOADED / 61 REJECTED) and `--incomplete --batch`
**0 of 34** (18 / 16); the five `Signatures.e` proof modules still check with 0 errors.
**One user-visible message DOES move** (review K-2, and it is exactly `ROSE-COMPARISON.md` §3
rank 1's acceptance item (i) about which surviving representative's `loc` a blame message points at):
the corpus gate compared exit codes only, and a content comparison of all 132 + 34 `.out` files finds
one change — `Time/shouldfail/bucket01_calendar_overlaps_facts.e:77:7` prints "a part contains it but
the whole does not" where it printed "the whole contains it but no part does", **same verdict, same
position, same field, a different clause of the same refutation**.  Run PER FILE the clause is
identical on both sides, so this is the whole-corpus-batch configuration only; and the clause the
fixed compiler prints is the one `bucket01`'s own header and `E3-EXAMPLES.md:176` record first.  The
clause was already documented as unstable across loading modes.  Not a regression.

**What moved, and the proof it is equivalent.**  A 174-file `.ei` sweep against a FROZEN copy of
`core/examples` with `-Dermine.loadInSeries=true`, 242 interfaces / 2,946 bindings, with a
**same-configuration control that differs in 0 of 242 interfaces**: **21 bindings in 10 interfaces
change**.  (The frozen copy predates two `Present/` files: the same sweep at the reviewed commit
`0741fb2` is **176 files / 243 interfaces / 2,966 bindings** and moves the same twenty-one bindings —
review K-5 — and the `Lang/` group, committed mid-review, adds no moving binding of its own.)
Nineteen are exactly "before minus permuted duplicates minus `a <- (a)`" (10 duplicate copies, 15
tautologies); of the other two — four bindings by name — **two are PROPAGATION** (a module reading a
now-smaller signature from a module above it saturates differently) and **two are only the print
order of a three-element concrete row** (K-4).  All **21 are ENTAILMENT-EQUIVALENT**, decided
semantically rather than syntactically: a residual `exists E. G` is, per label, the Boolean function
`SAT(G at that label)` of the universals' membership bits (`Basic.lean` `sat_iff_forall_label` plus
the independence of a row variable's bits across labels), so equivalence is 2–256 SAT instances per
binding.  Zero weaker, zero stronger.  **What decides what** (K-3): that per-label decision covers
the ROW-PARTITION part only — it reads neither the body nor the class constraints — so the claim
rests on it together with the syntactic checker (bodies and `forall` binders, for the 19 it explains)
and the class-multiset check; the reviewer's independent CNF+DPLL checker covers all four for all 21
and agrees.  After the fix the only bindings in the whole sweep that still
publish a duplicate or a tautology are the **21 hand-written signatures in the five `Signatures.e`
proof files**, which carry those sets deliberately.

**The row trace is NOT byte-identical, and the brief's reason for expecting it to be is wrong.**
`mkSimplified` is post-loop for one binding, but its output is an input twice: it runs a solve of its
own (`RowTrace.withSite("mkSimplified-extinct")`, `Subst.scala:1670`) on the set it drops, and the
published residual is instantiated at every later use of the binding.  On `boot`, **26 of 54,199
segments differ (0.048 %)** — 18 where the before side's solve input carries a tautology, 4 a
duplicate, 4 with the same constraint count and shape and only a shifted `Supply`; `learn`, `step`,
`sat`, `splice`, `inpart`, `ex` and `slbl` record counts are identical and only `scon` (1,999 →
1,975), `svar` and `in` move.  What IS invariant is the loop itself: no rule, dequeue order or
refutation changed, and the model reproduces the compiler solve for solve on both sides.

**Perf.**  `perf-bench.sh` refuses above load average 1.5 and the implementer's machine ran at 3–7
with two other agents on it; **the reviewer ran it on a quiet machine, both sides:
`perf-bench.sh batch -n 3` gives 12.04 s before and 12.05 s after (a second after-run 12.10 s), each
started at load ≈ 1.1 — UNMOVED.**  The import-time proxy the implementer quoted (23.7 s → 21.9 s,
92 %) is retired: it was a single pair of runs at load 3 and does not reproduce at that magnitude;
the reviewer's re-measurement over the 70 shared modules is 21.40 s → 20.99 s (98.1 %), worst single
regression +0.05 s, dominated by `WardRoster` −0.62 s (K-8).

**Two corrections to the E-series memos.**  `Wide/Signatures.e`'s `melt3Full` carries **three**
order-permuted duplicate pairs, not the two `E1-EXAMPLES.md` N-11 records — the third,
`r21 <- (ro,rs)` / `r21 <- (rs,ro)`, survives into `melt3Deduped`, so the hand-deduplicated twenty is
nineteen by the rule the compiler now applies.  `Time/Signatures.e`'s `nearestByFull` carries two
pairs AND two tautologies.

**Not fixed, deliberately: the third sibling, in both readings — and a FOURTH omission found by the
review.**  `Part.apply` has no variable-identity case and `Part.isTrivialConstraint` (`Type.scala:394`)
is `false` unconditionally; and its concrete-identity case (`:414`) is **DEAD CODE** — the guard
`ss == cs` compares a `List[Name]` to a `Set[Name]`, which is always false at this project's Scala
3.3.8, so `(|Foo,Bar|) <- ((|Foo,Bar|))` is rebuilt unchanged and reaches the solver, and what deletes
it is `Subst.normalPart`'s `ConcreteRho` branch, from the published residual only (review K-1;
**`ROSE-COMPARISON.md` §3 rank 1 item 3 and the first version of `S3-SIMPLIFY.md` §2 both assert the
opposite and are corrected in place**).  So at `Part.apply` NEITHER case is handled, and the repair is
two changes, the concrete one being the single word `ss.toSet == cs`.  Both stay deferred for the same
reason: `Part.apply` is on the PRE-solver path (`Constraints.scala:786` builds every queue partition
through it), so either change moves the row trace and forces a fresh L2 differential on every group,
and `incomplete/Signatures.e:40`'s `taut : r <- (r) => …` — with `tautIsFree` proving it discharges
from an empty context — is a source-written constraint of exactly that shape.  And
`mkSimplified` still has NO entailment test between surviving partitions of any kind — confirmed by
reading; that is `ROSE-COMPARISON.md` rank 3 (canonical simplification), a separate stage, and two
of the residuals S3 moves show what it would buy (`RunCalibration.valueAsOf`'s `t <- (e, c1, r)`, the
`runningTotal` probe's `e <- (f1, f, e1, d1, so)`, each entailed by three siblings).

**Lean.**  `tracker/loopmodel/S3Simplify.lean` — a scratch file OUTSIDE `tracker/lean/`'s source
tree, checked with `cd tracker/lean && lake env lean ../loopmodel/S3Simplify.lean` (no `lake build`:
other agents were running the `looptrace` binary).  **Eight declarations** (K-6), all on
`[propext, Classical.choice, Quot.sound]` only: `sat_congr_of_perm`, `sEntails_of_perm`, `sat_taut`,
`sEntails_taut`, `sEntails_of_mem_subset`, `erase_perm_dup_equiv`, `erase_taut_equiv`,
`SEquiv.sat_iff`.  None of it is new: `Canonical.lean`
already implements both rules (`Step.dedup` "RECOGNISED UP TO PERMUTATION", `Step.occurs` which
"also deletes the vacuous `r <- (r)`") and already proves `Step.preserves`.  **The model was the
specification and the compiler was behind it.**

**A1's movers, re-measured.**  Re-running A1's configuration flip (`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` against the shipped defaults) on BOTH compilers over the same frozen corpus: the flip moves **45 of 2,941 bindings before the fix and 44 after** — the count does not drop, and should not have been expected to, because what a dequeue-order flip moves is dominated by alpha-renaming and print order.  What changes is the classification: `A1-REVIEW.md` §R-1's `np01.inferredRestate` published 8 constraints at the old configuration and now publishes 7, so the manual de-duplication R-1 had to perform is done by the compiler.  And the same complete per-label decision **independently confirms §R-6**: of the 45 movers at the fixed compiler, 44 are equivalent and exactly one — `incomplete/RevenueShare.shareOfGroup` — is strictly WEAKER at the new defaults, i.e. strictly more general, which R-6 established by hand.

**The example corpus's own commentary is updated.**  Ten comments in `core/examples/**` quoted an
inferred residual S3 changes; each now says what the compiler inferred BEFORE S3 and what it infers
now, with **no signature, proof or body changed** — `Wide/Signatures.e` (melt3: three permuted pairs,
not two, so the minimal set is nineteen), `Algebra/Signatures.e` (`antiJoin` 3 → 2, `runningTotal`
21 → 20), `Time/Signatures.e` (`orZero`/`yearFrac365`/`band3`/`band4` 1 → 0, `pctChange` 5 → 4,
**`safeDiv` 5 → 3 = `safeDivDeduped`**, `shiftBy` 7 → 6, `nearestBy` 10 → 7), `incomplete/Signatures.e`,
`incomplete/TopReadings.e` (the module the fix was read out of — its "WHAT ACTUALLY HAPPENS" block is
now "WHAT USED TO HAPPEN, AND WHAT S3 FIXED"), `incomplete/RunCalibration.e` (`valueAsOf` and
`lookbackJoin` 10 → 9 each) and `Time/Helpers.e`.  `Present/Signatures.e` was already correct.  All
five `Signatures.e` re-checked after the edits, 0 errors.

**Not committed.**  Working tree only.

## 2026-09-06: **ADOPTED — three defaults move** (loop model, stage A1)

The user's decision of 2026-09-06 17:00, on the D1B review's recommendation (§8 (ii) and (iii))
and the S2 review's adoption prerequisites: **adopt the full recommended set.**  Report
`tracker/loopmodel/A1-ADOPTION.md`; the evidence is `S2-FIX.md`, `S2-REVIEW.md`,
`D1-CHANGE.md`, `D1B-REVIEW.md`.

| flag | old default | new default | what it is |
|---|---|---|---|
| `-Dermine.rowSound` (master for `.bare` / `.saturated` / `.decide`) | `false` | **`true`** | S2's three layers: bare-row EXACTNESS in `makeConcrete`, `labelClash` on the SATURATED set, and a COMPLETE per-label decision on the solve's LIVE INPUT |
| `-Dermine.dequeuePolicy` | `shipped` | **`smallcanon`** | D1's dequeue order: fewest right-hand-side parts first, ties by an id order instead of `rhs.hashCode` |
| `-Dermine.solveBudget` | `0` (off) | **`20000`** | D1's draw budget, per solve; still IGNORED under `-Dermine.dequeuePolicy=shipped` |

**NOT adopted, offered: `-Dermine.topNormalise` (stage S4, 2026-09-07, DEFAULT OFF).**

| flag | default | what it is |
|---|---|---|
| `-Dermine.topNormalise` | **`false`** | S4's WRITTEN-PARTITION NORMALISATION: when one left-hand side carries k >= 3 lone-abstract INPUT partitions whose DISTINCT concrete parts are pairwise INCOMPARABLE and non-empty, and that left-hand side has no concrete row, the k reads are replaced by `v <- (c, F)` (F their union, c fresh) plus `c_i <- (c, F \ F_i)` — the 0-draw form the user could have written |

**Why it exists.**  `Record.(!)` is a row PARTITION, so N reads of one record parameter whose row
is a VARIABLE cost exactly `D(N) = (5^N - 3*3^N + 2*2^N) / 2` draws — 3 / 30 / 207 / 1,230 /
6,783 / 35,910 / 185,727 for N = 2..8, verified against this compiler at every one — i.e. **x5
per extra read**.  At N = 7 the adopted budget rejects a VALID program.  This is the only known
shape on which it does.  Raising the budget buys one read per x5 (and 99.74 s at N = 9, 843.90 s
at N = 10); moving `countDraw()` past the applicability test still needs 23,772 at N = 7; a
per-record cap breaks `Loop/Strict.lean`'s `NoLoss`.  The normalisation takes the whole ladder to
**one pre-loop draw at every N**: with it on, ten reads compile in 0.04 s where seven did not
compile at all.

**AT ADOPTION, TWO THINGS THAT ARE NOT OPTIONAL** (S4B review H-8 and §5.2).

1. **Clear the interface cache once**, exactly as `smallcanon`/`solveBudget` needed:
   `find . -name '*.ei' -delete`.  Nothing keys a published `.ei` by `GenRules.toString`
   (`Constraints.scala:1371`, the open gap A1 review R-4 recorded), so the new `+topnorm` token
   changes no interface key — and this flag demonstrably changes published bytes
   (`Present/ProjectionCost.ei` order-only, plus a NEW `Present/shouldfail/proj01_seven_reads.ei`
   because that module starts compiling).
2. **`core/examples/Present/shouldfail/proj01_seven_reads.e` must leave `shouldfail/`** (or gain
   more reads) in the same commit: its failure IS the resource limit this removes, and it is the
   one corpus module whose verdict changes.

**Status: OFFERED, NOT ADOPTED.**  Report `tracker/loopmodel/S4-CHANGE.md`, design
`tracker/loopmodel/S4-DESIGN.md`, review `tracker/loopmodel/S4A-REVIEW.md`, Lean
`tracker/loopmodel/S4Top.lean` (22 declarations, 18 audited theorems, 0 non-standard axioms), Scala in the worktree
`~/research/ermine/ermine-scala-wt-s4` (branch `top-normalise`, uncommitted), model mirror in
`Rowpartition/Loop/{State,Json,Seed,PolicyReplay,Main}.lean` under `Flags.topNormalise`
(`--flags=topnorm`).  **Adopting it changes the verdict of exactly one corpus module**:
`core/examples/Present/shouldfail/proj01_seven_reads.e` stops failing, because its failure is the
resource limit this removes.

**WHAT A USER MUST DO AT ADOPTION: nothing to their code — but CLEAR THE INTERFACE CACHE ONCE.**

```
find . -name '*.ei' -delete
# they live beside the sources under  core/examples/**/*.ei
# and, for the stdlib, under          core/target/scala-*/classes/modules/**/*.ei
```

A published `.ei` is **not keyed by the solver configuration** (the loader's `preChecked` asks
only whether type-checking is on, whether interfaces are on, and whether every import was itself
interface-checked; `GenRules.toString`'s only consumer in the tree is `DisjProbe`).  So a tree
built before the flip keeps feeding pre-flip interfaces to the post-flip compiler, silently —
measured, not assumed: a stdlib closure whose interfaces were written at the OLD configuration is
READ at the new defaults (cold boot 8.44 s against 15.12 s with none present).  A mixed tree
loads today and the differences are a renaming or a strictly more general type, so this is a
hygiene instruction rather than a correctness one; it costs one line
(A1 review R-4).

**HOW TO GET THE OLD BEHAVIOUR BACK, in one line:**

```
-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped
```

`rowSound=false` turns all three S2 layers off (they take their default from the master), and
`dequeuePolicy=shipped` restores `Q.pop`'s original body AND turns the draw budget off with it
(the budget-requires-policy rule).  At that setting `GenRules.toString` is
`cut+label-early+resguard+splitkey+splitrow+resrow` — byte-identical to the pre-adoption
default string — and the corpus row trace is the pre-adoption trace, 2,355,430 segments, with
the model agreeing on every one.  The model's matching command line is
`--flags=norowsound --policy=shipped`.  One thing is NOT restored: asking for the shipped order
now prints one `NOTE` line on `stderr` saying the (defaulted) draw budget is being ignored with
it.

**WHY, in one paragraph each.**

* **`rowSound`.**  The shipped solver ACCEPTS unsatisfiable row systems — ten confirmed on the
  compiler, the shortest five constraints long (`tracker/repro/satterm/seeds/unsat/`).  Layer
  (iii) is a COMPLETE per-label decision, so acceptance now carries a theorem
  (`Loop/NoFalseAccept.lean`'s `solve_noFalseAccept`, chained to S1 by
  `solve_accepted_faithful`), and the price is nothing measurable: no corpus program is newly
  rejected, no published signature changes, no substitution moves on 38,400 satisfiable-seed
  runs, `core/test` and `TestLoopTrace` unmoved, and the check's whole bill on the eight-group
  corpus is under a second.
* **`dequeuePolicy=smallcanon`.**  The shipped order's cost depends on the ID BASE, by two
  orders of magnitude on real code: `GU05` draws 743 ids at one base and 47,317 at another, and
  in a normal ten-file batch load with interfaces enabled the chunk holding
  `core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e` takes **629 s under the
  shipped order and 11 s at the new defaults** (A1's own deterministic `.ei` sweep; D1 measured
  the same chunk dying at its 900 s cap under the shipped parallel loader, taking the four
  modules after it down with it).  `smallcanon` is base-INVARIANT by construction — 306 draws at
  all 25 bases — and every soundness and termination theorem was transported to it before it was
  adopted (`Loop/PolicyStep.lean`, `Loop/PolicyTerm.lean`: they hold for EVERY policy).
* **`solveBudget=20000`.**  A floor under divergence-by-minting, the divergence eight L5 rounds
  actually found.  When it fires it is a REJECTION with a diagnostic that says in words that it
  is a resource limit and not a type error (`Budget.budget_never_accepts`,
  `runBud_rejects_unsat`).

  **RE-MEASURED 2026-09-07** (stage S4, `tracker/loopmodel/S4-DESIGN.md`; the sentence that used
  to stand here — "20,000 is 61x the largest draw count of any solve in the corpus (328); it
  never fires anywhere in the corpus" — was written before the `Present/` and `Lang/` groups
  were added and is stale on both halves).  Over all eighteen groups of `looptrace-corpus.sh`,
  with the compiler's own per-solve counter (`-Dermine.rowTrace.draws=true`):

  | | draws |
  |---|---|
  | largest solve in the corpus | **6,783** — `Present/ProjectionCost.e(1:1)`, i.e. the budget is **2.95x** it, not 61x |
  | largest that is not a projection cascade | 385 — `Wide/ClaimsExperience.e(207:3)` |
  | largest in ordinary code (nobody wrote it to demonstrate the cliff) | 1,230, three times — `Lang/TextTables.e(138:13)`, `(174:23)`, `Lang/RunningState.e(210:13)` |
  | stdlib boot | 0 |

  and **it does fire**: `Present/shouldfail/proj01_seven_reads.e` is rejected at 20,009 draws.
  That module is a VALID program — seven `p ! f` reads of one open-row record parameter — and it
  is the one known shape on which the budget rejects a well-typed program.  N reads of one such
  parameter cost exactly `(5^N - 3*3^N + 2*2^N)/2` draws (3 / 30 / 207 / 1,230 / 6,783 / 35,910 /
  185,727 for N = 2..8, verified against the compiler at every one), so the cost is x5 per extra
  read and no budget value can keep pace.  Stage S4 proposes the fix as a flagged normalisation
  rather than a bigger number; see `tracker/loopmodel/S4-CHANGE.md`.

**AND WHY AS A SET.**  `smallcanon` alone would have been a net LOSS of refutation power: the
loop's own refutation is incomplete and order-dependent, and under `smallcanon` it stops firing
on `MIN2` and `FALSE-ACCEPT-2` (D1B review U-0).  With `rowSound` on, all seven curated
witnesses are refuted at all ten id bases under BOTH orders, so the pair loses nothing.  The
budget is meaningless without the policy and is coded to ignore itself without it.

**THE GATES, in one table** (all of them, with commands and numbers, are in
`tracker/loopmodel/A1-ADOPTION.md`):

| gate | OLD | NEW |
|---|---|---|
| `core/test` | 913/914 | **913 or 912 of 914** — the `Constraints.disjunction sound` starvation always, and on one reviewer run also `TestInterfaceRoundTrip`, a documented flake that passes isolated at both configurations |
| `TestLoopTrace`, both configurations forwarded to both sides | 714/714 | **714/714** |
| the eight-group L2 corpus differential | 2,355,430 / 2,355,430 agree | **2,355,428 / 2,355,428 agree** |
| corpus verdicts, 100 files, deterministic loader, each side twice | 23 LOADED / 43 REJECTED, 18 / 16 | **identical — 0 verdict changes**, 9 blame-clause messages in `shouldfail/` |
| the 7 curated unsatisfiable witnesses x 10 id bases | 44 SOLVED of 70 | **0 SOLVED of 70** |
| `run.sh env` | `cases=9 differ=4` | **`differ=0`** |
| `GU05` / `GU05MIN` x 25 id bases | 743-47,317 draws | **306 / 256 at every base** |
| 3,840 hunt seeds x 3 bases | 11,520 SOLVED | **11,520 SOLVED**, no concrete row moved, the draw budget never fired |
| published `.ei`, 187 interfaces / 1,921 bindings | byte-identical floor | **30 bindings move: 27 renamings, 1 a renaming plus a constraint its siblings ENTAIL, 2 that BIND a kind the old side fixed, and ONE genuinely different — `incomplete/RevenueShare.shareOfGroup`, which is strictly MORE GENERAL (`OLD \|= NEW`, so no call site regresses).**  `rowSound` moves NOT ONE BYTE; every moved interface is the policy's |
| `perf-bench batch` cold, a loaded desktop | 12.81 / 12.91 s (2 rounds); 13.43-13.76 s (the reviewer's 4) | **12.89 / 12.70 s**; 13.58-13.90 s — **a small cost, of order 1-3 %, not separable from this host's noise** (the sign flips over two rounds but not over the reviewer's four, median +0.30 s / +2.2 %) |
| `repl-smoke` / `lsp-smoke` | — | **PASS** (2+6+4+23, 98) |
| Lean | — | build **867**, `Audit.lean` **4,116 theorems / 0 non-standard axioms**, `looptrace` **1,670** |

**THE OPEN GAPS, at adoption.**

* **No `.ei` cache key for the flags.**  Nothing in the tree keys a published interface by
  `GenRules.toString` (its only consumer is `DisjProbe`), and the loader reads any `.ei` whose
  dependencies were interface-checked.  So a tree built partly at one configuration keeps
  mixing interfaces silently, and switching a default does NOT force a rebuild — measured, not
  assumed (`A1-ADOPTION.md` §2, A1.7).  It is safe today because 29 of the 30 moved bindings
  are the same type and the thirtieth is more general; **what a user must do about it is the
  one-line `find . -name '*.ei' -delete` above**, and what the tree should grow is a
  configuration in the interface key, before any INCREMENTAL adoption (A1 review R-4).
* **No a-priori fuel number.**  A draw budget bounds DRAWS.  Turning that into a bound on
  DEQUEUES needs a dequeues-per-draw bound, which is `L5-TERMINATION.md` R8.6b and is open, for
  every order including the shipped one.  20,000 is an empirical ceiling — with **2.95x**
  headroom over the corpus's largest solve as of 2026-09-07, not the 61x the pre-`Present`
  corpus showed — not a derived one.  The budget is not a wall-clock watchdog.
* **The budget diagnostic carries no diagnostic `code`.**  It is LSP `severity 1` and the
  diagnostic JSON has no `code` field (`lsp/Diagnostics.scala:167`), so tooling can tell a
  resource limit from a type error only by reading the prose.  Judged **acceptable at adoption**
  (A1 review R-9): it never fired at 20,000 on the corpus as it stood, the wording carries the
  distinction, and Error is the right severity for a signature that did not get checked.
  **Follow-up: give it a code** — and it is now more than cosmetic, because as of 2026-09-07 the
  budget DOES fire on a valid program (`Present/shouldfail/proj01_seven_reads.e`, the projection
  cliff), so a tool cannot tell "your program is wrong" from "the solver gave up" without
  reading English.
* **One published TYPE really is more general.**  `incomplete/RevenueShare.shareOfGroup`: the
  old side names the universal `k` of its `Row k` argument in three constraints where the new
  side names a fresh existential, so `OLD |= NEW` and `NEW |/= OLD`.  No call site regresses
  (`OLD |= NEW`), and `core/examples/incomplete/Signatures.e`'s hand-written `shareOfGroupFull`
  is that same more general signature over the identical body and checks at BOTH configurations
  — but "no published type is weaker" is a statement about `ei-classify.py`'s test, not about
  entailment, and this state file does not make it (A1 review R-6).
* **`-Dermine.solveBudget=<not a number>` means 20,000**, not 0: the `NumberFormatException`
  fallback moved with the default.  It fails towards the shipped configuration (A1 review R-8).
* **`rowSound`'s three provisos are unchanged** and are stated in the S2 section below: the
  guarantee is conditional on the decision budgets not being exhausted (exhaustion is NO
  VERDICT, is counted, and warns on stderr), "the input" is the live input (the partitions plus
  the `SubstEnv` bindings of the variables they mention), and "satisfiable" is read
  existentially over the row variables.


## 2026-09-06: **the FIX for that bug, behind flags that DEFAULT OFF** (loop model, stage S2)

`tracker/loopmodel/S2-DESIGN.md` (what it targets) and `S2-FIX.md` (what was measured and
proved).  **Nothing is adopted: every flag introduced defaults to OFF, and with them off the
compiler is byte-identical — 2 355 430 corpus solve segments, group for group.**  Adoption is
the user's decision and this work does not make it.

Three layers on `Subst.solve`, each separately switchable:

* `-Dermine.rowSound.bare` — at a BARE definition `v <- ((|C|))` and a concrete instantiation
  `v := ((|fs|))`, require `C = fs` instead of `ensureSuperset`'s `C ⊆ fs`.  Sound by
  `Rowpartition/Loop/Sound.lean`'s `bare_refutes`; closes the hole `MIN2` walks through.
* `-Dermine.rowSound.saturated` — `labelClash` on the SATURATED set as well as on the input.
  Sound by `Rowpartition.refute_saturated_sound`.  This is the flag removed on 2026-09-02 at
  "zero additional refutations on both corpora"; it catches 384 of the 404 compiler-level
  false acceptances in the S1 review's population.
* `-Dermine.rowSound.decide` — a COMPLETE per-label decision (unit propagation plus a CASE
  SPLIT) on the solve's LIVE INPUT: the queue's partitions together with the `SubstEnv`
  bindings of every variable they mention, because `solve` does not `substType` its input and
  the environment is long-lived (S1 review Z-6).  This is the layer that carries the theorem.
  `-Dermine.rowSound.budget` (200000 nodes per label) bounds it; exhaustion is NO VERDICT,
  refutes nothing, and is counted.

**What is now proved** (`Rowpartition/Loop/NoFalseAccept.lean`):

    solve_noFalseAccept : flag on ∧ budget not exhausted ∧ the solve does not reject
                          ⇒ SSat (the queue's partitions ∪ the environment facts)

    solve_accepted_faithful : ... and hence, with S1's `run_noLoss` / `run_models` /
                          `run_ssat_iff`, the loop lost nothing, every model of the OUTPUT is
                          a model of the INPUT, and the two are satisfiable together

the CONVERSE of S1, whose `run_noLoss` / `solve_sound` are conditional on `SSat (sys s₀)`
exactly where they have to be.  Its two halves are `labelDecide_sat_ssat` (COMPLETE: a pass
means a model was constructed label by label and CHECKED against every constraint) and
`labelDecide_refuted_unsat` (SOUND: a refutation means there is none).

**THREE provisos, all stated and none of them hidden.**  The theorem says nothing when (a) a
node BUDGET runs out — per label (`-Dermine.rowSound.budget`, 200 000) or per solve
(`-Dermine.rowSound.solveBudget`, 1 000 000): the answer is NO VERDICT, nothing is refuted, a
warning naming the site goes to stderr, and it never fired on the corpus; (b) the `SubstEnv`
binds a mentioned variable to something that is not row-shaped, which is COUNTED as `opaque`
and skipped, so the decision runs on a sub-system — refutations stay sound, completeness is
not claimed for that solve, and the count was 0 over the whole corpus; (c) "satisfiable" is
read with EVERY variable existentially quantified, skolems included — the same reading
`labelClash` has always had, weaker than "the program type-checks", and free in the refutation
direction.  Layer (i)'s new death
is a refutation (`bare_death_refutes`), and `stepS_continue` — layer (i) can only turn a
continuation into a death — is why **no S1 theorem needed a hypothesis or changed at all.**

**Reviewed 2026-09-06** (`tracker/loopmodel/S2-REVIEW.md`, verdict ADVANCE, thirteen findings,
zero confirmed false rejections in the reviewer's own 4,800 + 1,500 + 8 runs) and every finding
closed (`S2-FIX.md` §P1-§P6).  Three things changed that a reader of this file should know:
the chain to S1 is now the theorem `solve_accepted_faithful`, not prose; the environment-fact
path is a TRACKED gate (`run.sh env`, and `seeds/unsat/ENV-LINK.json` carrying the third
mechanism above); and layer (iii) now has a PER-SOLVE node cap
(`-Dermine.rowSound.solveBudget`, default 1000000) whose exhaustion prints a warning on stderr
naming the site, so the one condition under which the theorem says nothing is bounded and
visible rather than silent.

**What it costs, measured** (`S2-FIX.md` §5): `perf-bench.sh batch` cold median 12.78 s off
against 12.89 s on, inside the run-to-run spread; layer (iii) spends 0.69 s over the whole
corpus (2 355 392 solves), median 7 µs on a solve with any row constraint, worst 3.7 ms, and
the budget never fired.  **The corpus list of newly rejected programs is EMPTY**: over the two
tracked corpora and the eight `looptrace-corpus` groups not one program is newly rejected, and
exactly one already-rejected module (`shouldfail/inf04_except_recursive.e`) reports a different
clause of the same refutation at the same field.

## 2026-09-06: **BUG — the shipped compiler ACCEPTS unsatisfiable row systems** (loop model, stage S1 + review)

Two minimal, compiler-reproduced witnesses, both five constraints, both passing
`labelCheckEarly`, both returned `SOLVED` by the shipped `Subst.solve` with a substitution that
violates an input constraint.  Seeds in `tracker/repro/satterm/seeds/unsat/`.

A THIRD mechanism was found by the S2 reviewer (2026-09-06, `S2-REVIEW.md` §4.5) and is
tracked as `seeds/unsat/ENV-LINK.json`: a system unsatisfiable **only through the
`SubstEnv`**.  A first solve binds `v4 := v0` (a `VarT` link, no concrete row anywhere); a
second solve in the same environment is handed `v3 <- (v0,v4)` and `v3 <- ((|l0|))`, which
under the binding forces `rho v3 = ∅` against `rho v3 = {l0}`.  `Subst.solve` does not
`substType` its input, so the shipped check never sees the binding (S1 review Z-6).  SOLVED
20/20 shipped; REJECTED 20/20 with `-Dermine.rowSound.decide`.

```json
MIN2.json   [[2,[3,0],[]], [3,[0,1],[]], [2,[1],[17]], [2,[],[17,38]], [5,[2,8],[]]]
```
```
v2 <- (v3, v0)     v3 <- (v0, v1)     v2 <- (v1, (|l17|))
v2 <- ((|l17,l38|))                   v5 <- (v2, v8)
```
UNSATISFIABLE at **`l17`**; `SOLVED` at **4 of 20** id bases (300, 303, 307, 315), binding
`v1 = v2 = v3 = {l17,l38}`, which makes `v2 <- (v1,(|l17|))` read `{l17,l38} = {l17,l38} ⊎
{l17}` — `l17` in two parts of one whole.  **This one goes THROUGH the `concrete` branch's
unlicensed bare-row deletion** (below): at step 9 `v1` carries both `((|l17,l38|))` and the
`cancellation`-derived `((|l38|))`, `ensureSuperset` passes (it is `subsetOf`), `destructiveSub`'s
`srs` is non-empty so `keepDefs` drops the bare row, `cancellation` emits nothing, `{l38}` is
lost.

```json
MIN1.json   [[6,[7,2],[]], [6,[4],[35]], [7,[3,1],[]], [3,[2,0],[]], [1,[0],[22]]]
```
```
v6 <- (v7, v2)     v6 <- (v4, (|l35|))     v7 <- (v3, v1)
v3 <- (v2, v0)     v1 <- (v0, (|l22|))
```
UNSATISFIABLE at **`l35`**; `SOLVED` at **20 of 20** id bases, binding `v6 = {l22}` against an
input that puts `l35` in `v6`, and PUBLISHING the violated constraint `{l22} <- ({l35}, v4)`
unchecked.  This one is NOT the bare-row hole: the loop reaches `.done` on a residual it never
refuted — plain refutation INCOMPLETENESS of the saturation.

Scale (`tracker/loopmodel/S1-REVIEW.md` §2.6, §7): ~9 M generated systems, 11,048 that are
UNSAT **and** pass `labelCheckEarly`, ~27,000 model runs at the shipped flags, **1,166 model
false acceptances over 665 distinct seeds**, ten replayed on the shipped compiler, **ten
accepted**.  Zero unsound REJECTIONS in ~23,000 runs.  Both defences are incomplete in the same
way: `ensureSuperset` is CONTAINMENT (`Constraints.scala:312`), so it waves through exactly the
`C ⊊ fs` the deletion loses; `labelCheckEarly` is unit propagation over the INPUT
(`Subst.scala:1187`), so any unsatisfiability needing a case split walks past it.

**The fix** (stage S2): (1) make `makeConcrete` refuse `C ⊊ fs` at a BARE definition — sound by
`bare_refutes`, and it turns `MIN2` into a proper `Row types failed to unify` diagnostic;
(2) run `checkLabels` on the SATURATED set as well as the input — sound by
`Rowpartition.refute_saturated_sound`, catches all six compiler-confirmed witnesses and
1,146 of the 1,166; (3) a COMPLETE per-label decision (propagation plus a case split), because
ten seeds survive (2) — `seeds/unsat/SURV1.json` is one, verified `SOLVED` on the compiler.

## 2026-09-05: SOUNDNESS of the row solver's LOOP, proved ON SATISFIABLE INPUT (loop model, stage S1)

After eight L5 rounds the direction changed: termination is to be ENGINEERED (stage D1) and
SOUNDNESS is what gets PROVED.  Stage S1 does that, over the loop model
(`tracker/lean/Rowpartition/Loop/`), in three new modules — `Sound.lean` (1,060 lines),
`Reject.lean` (633) and `Solve.lean` (215).  Report `tracker/loopmodel/S1-SOUNDNESS.md`,
review `S1-REVIEW.md` (FIX-THEN-ADVANCE, nothing to change in the Lean; the prose corrections
are applied here and dated 2026-09-06).  Build 859 jobs; audit 3,804 theorems, 0 non-standard
axioms.

**Read the proviso, it is load-bearing.**  What is proved is "an accepted SATISFIABLE program
is well-typed".  `solve_sound` says NOTHING when the input is unsatisfiable, and "an accepted
program is well-typed" is a refutation-COMPLETENESS statement the loop does not have — see the
BUG section above.  On all 1,166 measured false acceptances the OUTPUT system was itself
unsatisfiable, so `NoLoss` never actually failed: the theorems below are right, and they are
not the property the type checker needs.

### (A) OUTPUT SOUNDNESS — every model of the output is a model of the input, ON SATISFIABLE INPUT

The output system is `sys s'`: the residual partitions of BOTH queues plus the substitution
environment read as constraints (`EnvVal.toConstraint`: `emptyRow` is `v <- ()`, `alias u` is
`v <- (u)`).  So the substitution the type checker goes on to apply is part of what the
theorem talks about.

```lean
theorem step_noLoss_all {s s' : State} (hw : Wf s) (hba : BareAgree s)
    (h : step s = .continue s') : NoLoss (sys s) (sys s')

theorem step_noLoss_or {s s' : State} (hw : Wf s) (h : step s = .continue s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)

theorem run_noLoss : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → SSat (sys s) →
    ∀ s', (run s n = .solved s' ∨ run s n = .outOfFuel s') → NoLoss (sys s) (sys s')
```

`StrictStep.step_noLoss` already had four of the five dispatch branches; S1 adds the fifth,
`concrete`, which is the one that DELETES — and only when `destructiveSub`'s `srs` is NON-empty,
i.e. when something other than `v`'s own definitions mentions `v`
(`Constraints.scala:1643-1644`, `Loop/Step.lean:175-177`); when `srs` is empty nothing is
deleted at all.  Three of its four deletions are licensed —
a rewritten mention `a <- (S, K)` with `v ∈ S` by its `srs` image plus `v <- ((|fs|))`
(`sat_of_subst_image`), a definition `v <- (a, (|K|))` with ONE abstract part by
`cancellation`'s output `a <- ((|fs \ K|))` plus `v <- ((|fs|))` (`sat_of_cancel_image`), and
a definition with two or more abstract parts because `keepDefs` puts it back.

**The fourth is not, and this is the finding.**  A BARE concrete definition `v <- ((|C|))`
with `C ⊆ fs` (which `ensureSuperset` permits) is deleted and NOTHING is emitted in its place
— `cancellation`'s two branches both want exactly one variable left over and a bare row has
none (`StrictStep.cancellation_bare`).  With `C ≠ fs` that is a real loss.  It costs nothing
about ACCEPTING a well-typed program, because a state holding two different bare concrete
rows for one variable has no model (`bare_refutes`); what it costs is COMPLETENESS — the loop
can turn an unsatisfiable system into a satisfiable one and then accept.  `L5-TERMINATION.md`
§C1.5 predicted exactly this ("`concRemove`'s third field will have to read
`SSat G → NoLoss G G'`"); S1 proves it and localises it to that one shape.

**And it is reached, at the shipped flags, and the compiler accepts: `MIN2.json`, above.**
(The original submission said "no input on which the shipped compiler ACCEPTS through this hole
was found … two defences and both held".  That was drawn from two hand probes and is
WITHDRAWN: `ensureSuperset` is containment, `labelCheckEarly` is unit propagation, and both
wave `MIN2` through.  The review's instrument found the hole's SHAPE in 26.7 % of 11,048 runs
and the DELETION firing in 1.6 %.)

### (B) REJECTION SOUNDNESS — a rejected program is ill-typed

Complete.  All seven messages `step` can die with:

| # | message | branch | verdict |
|---|---|---|---|
| 1 | `Fields appear twice in row: …` | `concrete`, `learn` | REFUTATION (`merge_refutes`, extracted through `subPartitions`/`destructiveSub` and through `substitution`) |
| 2 | `Infinite row partition for 'v'` | `learn` | REFUTATION (`selfSubst_refutes`) |
| 3 | `panic: reinstantiated type v to u …` | `common`, `unify` | UNREACHABLE (`Hygiene.step_link_no_death`) |
| 4 | `Incompatible instantiations of 'v'` | `empty` | REFUTATION (`incompatible_refutes`) |
| 5 | `Cannot unify skolem variable …` | `empty` | NON-REFUTATION — a KINDING error; the only exception |
| 6 | `panic: … to ConcreteRho(-,Set()) …` | `empty` | UNREACHABLE (`queueHygiene_binds_unbound`) |
| 7 | `Row types failed to unify: …` | `concrete` | REFUTATION (`ensureSuperset_refutes`) |

```lean
def NonRefutation (ns : Names) (m : String) : Prop :=
  ∃ v : Nat, ns.isSkolem v = true ∧
    m = "Cannot unify skolem variable with empty relation " ++ varStr ns v

theorem run_rejects_unsat : ∀ (n : Nat) {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOk n s → QueueHygiene s →
    ∀ (m : String) (s' : State), run s n = .rejected m s' →
      ¬ NonRefutation s.names m → ¬ SSat (sys s)
```

and `run_rejects_unsat_noSkolem`, which drops the exception list entirely on a solve whose
variables carry no `Skolem` flavour — every `json:` seed, and every corpus solve whose `svar`
table has no `Skolem` entry.

### (C) `solve_sound`, and two seeds

`solve_sound` packages both halves from `buildQueue` / `initState`, with `Wf`, `QueueHygiene`
and `RunSupOk` discharged from the input.  Instantiated in Lean on
`tracker/repro/satterm/seeds/NP01.json` (SOLVED, 98 dequeues, drawn 18) and `.../REF.json`
(REJECTED, `Fields appear twice in row: Set(l1)`), and the COMPILER agrees on both at base 300
(`tracker/repro/satterm/run.sh sweep json:… 300 300`; REF needs `-Dermine.labelCheck=false` to
let the LOOP be the one that rejects, since at the shipped flags `labelCheckEarly` rejects it
first, with a different message and the same verdict).

### Scope limits, stated not proved

`Subst.reduce` (post-loop, not modelled — `Rowpartition.Splice` studies its second case
relationally and finds a residual WEAKER than the input; and it is NOT inert: it is the last
defence for the bare-row hole, its defence is a PANIC (`Subst.scala:1079 → :184`,
`seeds/unsat/PANIC-1.json` at 3/3 bases), and `Subst.solve` publishes
`reduce(l, cs map substType, es, ps)`, not `sys s'`); `labelClash` / `labelCheckEarly`
(pre-loop, `Rowpartition.LabelAlgo`'s own theorem — SOUNDNESS, not completeness); `Loc` /
blame (outside the model).

**Side condition on the two UNREACHABLE verdicts.**  Messages 3 and 6 are unreachable because
`QueueHygiene` is free at an initial state — but only because the MODEL sets `env := {}`.  In
the compiler `SubstEnv.types` is long-lived (`Subst.scala:182-188`) and `solve` does not
`substType` its input before `PQueue.build` (`:1135`), so the verdict transfers only under the
unproved side condition "no input partition mentions an already-bound variable".


## 2026-09-05: USER PROGRAMS too — the VOCABULARY-FIXED fragment terminates (loop model, L5 round 7)

`tracker/lean/Rowpartition/Loop/VocFix.lean` proves `Terminates` for a fragment that ALLOWS
labels, allows both generative rules to fire, and allows the `concrete` dispatch branch — the
one round 6 discharged as unreachable.  The condition is that the run keeps a fixed finite
vocabulary:

* `VocFixed V s := ∀ t, Reaches s t → InVoc V t`, with `vocFixed_terminates` giving
  `Terminates` at the explicit fuel `measure4 (n·2ⁿ·2ᵐ) (n·2ⁿ·2ᵐ) n (n·2ᵐ) V L s + 1`
  (`n = |V|`, `m = |L|`);
* `NoDraw s` — the loop draws no id at any reachable state — is sufficient for it
  (`vocFixed_of_noDraw`), and `noDraw_terminates` is the corollary.

Three things had to replace what "no labels" gave round 6 for free.  (1) The loop invents no
LABEL: every one of `LoopRel`'s eleven constructors preserves `ConcSub`, so the bound transports
along L3's own refinement and the two counting bounds land in `DefaultTerm.forms V L`.  (2) The
`learn` branch's vocabulary clause is traded for "the call drew nothing" — `resolution` takes
its `fresh` *inside* the lone-variable arm and *before* its guards, so not drawing means not
emitting; `splitConcrete` draws only in its last branch, so not drawing means it took a reuse
branch and named a variable a lookup produced.  (3) **The `concrete` branch is paid for**: the
downward-closed set of `(variable, concrete row)` pairs the processed queue carries strictly
GROWS at every `makeConcrete` step, because `ensureSuperset` forces every concrete row already
recorded for `v` inside the new one, the dispatch's own `findRHS` miss makes the inclusion
proper, and `destructiveSub` deletes only partitions that mention `v`.  That set is bounded by
`|V|·2^|L|`, and it is what takes the certified fraction of the example corpus from 72 % to
97 %.

**What that certifies, exactly.**  Running the MODEL over every solve of a fresh
`-Dermine.rowTrace` census of all seven corpus groups (450,064 segments, 0 skipped; the L2
differential — `hashdiff` / `eqdiff`, which `--cycle` mode does NOT compute — was re-run
separately as a plain `--replay` over the same 450,064 segments and is 0 / 0):

* **the standard library: 2,695 of 2,695** row-carrying solves keep a fixed vocabulary, draw
  no id and never take the `concrete` branch — the round-6 certification re-derived from the
  run rather than from the input;
* **user programs: 9,118 of 9,362 (97.39 %)** over the SEVEN example groups and
  **10,306 of 10,645 (96.81 %)** over the EIGHT that L5 round 8 measures (the seven plus all 34
  `core/examples/incomplete/` files, 2,301,195 segments; `L5-TERMINATION.md` §R8.5) —
  example-corpus row-carrying solves that keep a fixed
  vocabulary (9,117 draw no id), against 2,388 (25.5 %) for round 6's input-checkable
  fragment.  That population is "the solve wrote an `inpart` record", which
  `Subst.scala:1215` writes only after `q.expand` SUCCEEDS, so it cannot see the 19 solves the
  row solver REJECTS; over every solve the model runs the figures are **9,134 of 9,381
  (97.37 %)**, with 247 rather than 244 in the residue;
* in `core/examples/incomplete/` — inside `core/examples`, not measured by this round,
  measured by its reviewer — the group's own solves are **1,188 of 1,283 (92.6 %)**
  vocabulary-fixed and its stdlib half is **12,682 of 12,682**, which with the seven groups'
  2,695 is the 15,377-of-15,377 stdlib figure again;
* the cycle detector, now runnable over corpus replays, finds **0 canonical and 0 exact state
  repeats in all 450,064 solves**, 0 `FUEL`, deepest run 140 dequeues;
* round 5's per-key mint instrument, likewise, **and this is where the round's first draft
  over-reached**: no `splitConcrete` GUARD key is minted more than once **in the seven
  groups** — but `core/examples/incomplete/np01_add_or_recompute.e(134:15)` mints one twice
  (98 dequeues, 18 loop draws, on a solve the shipped compiler performs and the model replays
  record-for-record), and round 5's pump is defined on the **CARRIER** key, which **46 of the
  seven groups' own 9,362 solves re-mint**, up to four times (six in `incomplete/`).  So the
  pump shape DOES occur in real code; what is bounded — at four turns, and six — is how often.

**The honest caveat, and it matters.**  The condition is RUN-LEVEL, not input-checkable.  The
round-6 review refuted the obvious input predicate with 111 corpus witnesses: `substitution`
and `commonSubexpression` manufacture partitions of exactly `splitConcrete`'s firing shape out
of inputs on which it cannot fire.  So unlike round 6's `NoConc` — which is decidable from the
input alone and is why "the standard library terminates" is a prediction — this round's
certification is checkable per solve by running the model, and does not predict termination for
an input nobody has run.  What it does is delimit where divergence can live:

> **`drawn_unbounded_of_not_terminates`: a divergent solve draws unboundedly many ids**, and
> `terminates_of_drawsAtMost`: a run that draws at most `k` ids terminates, for any `k`.

So the open problem is now a single quantitative question — *is `Sup.drawn` bounded along every
run?* — with the whole measure apparatus discharged behind it.  The 247 example solves outside
the fragment are tabulated row by row in `tracker/loopmodel/L5-TERMINATION.md` (Round 7,
§R7.2d) and classified in §R7.3; `incomplete/` adds 95 more.

Audit after: **3706 theorems / 0 non-standard axioms, 855 jobs**.  The round-7 review's verdict
was FIX-THEN-ADVANCE: the mathematics reproduced exactly (50/50 verbatim, all 244 residue rows
× 9 fields, every census cell) and three sentences were false or vacuous as written — the
`splitConcrete`-key sentence above, the census population, and an `hashdiff`/`eqdiff` claim
`--cycle` mode does not actually compute.  All three are corrected here and recorded old-for-new
in `L5-TERMINATION.md` §R7.7.

## 2026-09-05: the STANDARD LIBRARY BOOT is proved terminating (loop model, L5 round 6)

`tracker/lean/Rowpartition/Loop/NoConc.lean` proves `Terminates` for the **no-concrete-labels
fragment** of `Constraints.incorporateAll` — states in which no partition of either queue
carries a field label — with an explicit fuel, at the SHIPPED flags (`genRules=cut`,
`disjunction` off; `splitKey`, `splitRow`, `resGuard`, `resRow`, `labelCheck` unrestricted).
On such a state the loop is **non-generative**: `splitConcrete` is refused at its first guard
and `resolution`'s lone-variable pattern fails *before* its `fresh`, so no id is ever drawn,
`makeConcrete`'s dispatch branch is unreachable, and the vocabulary is fixed — which bounds the
`SubstEnv`, the processed queue (by `forms V ∅`) and the incoming queue (by the queue's own
de-duplication, once `MurmurHash3.unorderedHash` is proved permutation-invariant so that
`Partition.equals` implies equality of the search key).

**What that certifies, exactly.**  A fresh `-Dermine.rowTrace` census of the 129-module stdlib
boot (54,199 `Subst.solve` segments) finds **383 segments carrying a row constraint, 373 of
which build at least one partition, and every one of the 373 has an input with NO concrete
label** — 0 with a label anywhere, and a step census of `0 Resolution` and `0 SplitConcrete`
records to match.  The round-6 reviewer widened that measurement to the whole corpus and it
holds there too: across the six example groups **2,322 of 2,322** row-carrying solves with a
stdlib `loc` are label-free, and adding the boot's own 373 and all 34 `.e` modules of
`core/examples/incomplete/` makes it **15,377 of 15,377 across 41 traces**.  So:

> **Every row-constraint solve the Ermine standard library performs — booting alone, or while
> any corpus program is loaded — is inside the proved fragment, and `incorporateAll` is proved
> to terminate on all 15,377 of them.**

Two qualifiers, both from the round-6 review.  **(1) "Draws no id" is true of the LOOP, not of
the whole solve.**  `PQueue.build`'s `aux` mints a name for a `Part` whose left-hand side is not
a variable (`Constraints.scala:661–662`), and 8 of the 373 boot inputs have exactly that shape —
a `ConcreteRho` with an empty field set on the left, in `Relation/Op.e` and `Relation.e`.  Those
8 are still in the fragment and still covered: an empty concrete row carries no label, and the
theorem's state starts at the supply `buildQueue` returns.  What is proved is that
`incorporateAll` invents no variable and draws no id; the build may draw one before it starts.
**(2) The theorem is about the Lean loop model**, which stage L2 verified record-for-record
against the compiler's own trace on 2,355,430 corpus segments with 0 mismatches — so the claim
is "proved of the model, verified of the compiler on exactly these solves", not a claim read off
`Subst.solve`'s source.

On the example programs' OWN solves the fragment covers **2,388 of 9,362** row-carrying solves
(25.5 %); the rest carry concrete labels and are NOT covered.  Termination in general is still
OPEN, for one reason: off the fragment the vocabulary is not fixed, because the two generative
rules mint, and round 5's witnesses show the reuse guards permit a second mint at a key whose
carrier has been lost (`guardComplete_false`).  And the obvious widening — "neither generative
rule can fire" — is REFUTED by the corpus: on 111 example solves both rules are blocked at the
input and one fires anyway, unblocked by a partition `Substitution` or `CommonSubexpression`
derived.  The honest ceiling for a closed fragment is the vocabulary-fixed condition, worth
**97.6 %** of the example solves, not 98.9 %.

## 2026-09-04: a compiler PANIC on satisfiable input — `makeEmpty` self-propagation, FIXED

`Constraints.makeEmpty` propagated the "is empty" fact to every variable of a right-hand side
INCLUDING the one being emptied, so a self-referential definition `v <- (v, w)` — written, or
DERIVED by `SplitKeyed` — made the call manufacture `v <- ()` for `v` itself, re-enqueue it,
and reach `makeEmpty v` a second time, where `Subst.instantiateType`'s `die` refuses the
(no-op) re-binding: `panic: reinstantiated type v6 to ConcreteRho(-,Set()) but it was already
bound to ConcreteRho(-,Set())`, on a SATISFIABLE program. Whether the second step happens
depends on the queue order, hence on how many ids were allocated before the solve, so a valid
program was accepted or rejected by id accident — the NameLoss order-dependence class again.
Found by the L5 witness hunt (`tracker/loopmodel/L5-TERMINATION.md` §0, root-caused in
`L5-REVIEW.md` §6.3), minimised to the new tracked seed `tracker/repro/satterm/seeds/PANIC3.json`
(11 of 100 id bases); over the fourteen panicking hunt seeds at bases 0–99 the shipped compiler
died at **534 of 1400 runs**. The fix is one token — `abstr.map` → `(abstr - v).map`, matching
`selfSubstitution` twelve lines above — and it leaves `instantiateType`'s `die` in place as a
real invariant check rather than uncommenting the tolerant `warn` at `Subst.scala:182`, which
would have masked the symptom and removed the only enforcement of queue hygiene. Everything
else holds: `PANIC3` 89/11 → 100/100, the hunt seeds 866/534 → 1400/0, the other 17 tracked
seeds and both `crule` controls byte-identical, corpus verdicts identical (23/43, 18/16,
`shouldfail/` 40/40) with identical per-file messages, no published type weakened, both smokes
green, `core/test` 913/914 (`disjunction sound` only). The Lean model was mirrored in lock-step
(`Loop/Step.lean:126`, `(p.rhs.abstr.excl v)`) with six proof sites moved and
`makeEmpty_aux_emits_self` replaced by `makeEmpty_aux_excludes_self`: `lake build Rowpartition`
841 jobs, `Audit.lean` 3058 theorems / 0 non-standard axioms, `TestLoopTrace` 708/708 segments
agreeing with `PANIC3` in the population, L1 sweep 180/180, L2 replay 148,705 segments 0
differing. Full account and gate tables: `tracker/loopmodel/B1-FIX.md`;
`TICKET-editor-and-solver-followups.md` item 11. Nothing committed.


## 2026-09-03: termination on WELL-TYPED input — FALSE for the syntactic split guard; the KEYED guard is proved terminating and `ermine.splitKey` ADOPTED

Full write-up `tracker/TICKET-sat-termination.md`. THEOREM (`DefaultSatDiverge.lean`,
`not_TerminatesOnSat`): the satisfiable two-constraint `W2 = {p <- (e1, e2, (|k|)), p <- (e2,
(|k|))}` admits productive runs of every length under the shipped additive rule set — the
forced-empty `e1` recurs in every group, so one parent acquires infinitely many split
children, exactly the gap `DefaultTerm.lean` isolates (rank descent and the resolution guard
bound everything else). MEASUREMENT (`tracker/repro/satterm/`): the shipped loop mints once
on `W2` and solves it at 1000/1000 id bases, because cancellation exposes `e1 <- ()`,
`makeEmpty` erases it and the singleton link is UNIFIED, never substituted; `H2` and `NE6`
likewise. MEASUREMENT (`tracker/satterm/measure/`): no well-typed input diverges under the
defaults; `ResStar` (m single-label projections of one row) is exponential, `3^m` partitions
and `2^m − m − 1` mints, timing out at m = 10 — a work cliff, not a termination one.
THEOREM, the repair (`KeyedSplit.lean`, later the same day): key `splitConcrete`'s guard on
`(lhs, concrete part)` as `resolution`'s is (`¬ Resolved G lhs conc`) and the whole calculus
terminates on every satisfiable input in every run order, by `ResGuardTerm`'s measure unchanged
(`terminatesOnSatKeyed`, `keyed_vs_syntactic`; `tracker/satterm/KEYED-SPLIT.md`).
**ADOPTED 2026-09-03: `ermine.splitKey` now DEFAULTS TO TRUE** (`GenRules.splitKey`,
`SplitKeyed` provenance; `-Dermine.splitKey=false` restores the syntactic guard exactly; the
Scala guard is the Lean guard exactly). MEASUREMENT, Stage 2
(`tracker/satterm/KEYED-SPLIT-STAGE2.md`), every gate green off vs on from one class set
before the flip: seeds 300/300 solved and
200/200 rejected, `W2` mints nothing with the flag on; stdlib boot byte-identical; `core/test`
903/904 both sides; corpus 0 of 66 and 0 of 34 differ, `shouldfail/` 40/40; 188 published
interfaces, 0 weaker (two attributable bindings, both equivalent); `ResStar` unchanged and
`gu05` 6.1 s -> 1.2 s (five keyed reuses, 1,372 -> 458 saturated partitions); 77 keyed firings
in 18 of 110 example modules. Report recommends ADOPT WITH CAVEATS (behaviour change in ids,
one forced existential, `np01` mints more; nothing for ill-typed input; additive theorem only —
the loop-layer question is Stage 3). Post-flip re-run against the new default with no
flags: see `TICKET-sat-termination.md` §3d. Still open for the PREVIOUS guard only
(`-Dermine.splitKey=false`): Conjecture S, a loop-shaped relation, undetected empty resolvents
(`NE6`) — moot for the shipped compiler, since the theorem covers every run order. Open for
the shipped compiler: the loop layer (Stage 3). Scala change: the flag, default on.
`incomplete/README.md`'s `.slow` timings are stale under the shipped defaults (all load in
under 0.4 s except `gu05` at 7 s).

**Stage 3, the same day: the keyed guard does NOT survive the loop layer.** THEOREM
(`KeyedLoop.lean`, `not_TerminatesOnSatKeyedLoop`): add the loop's own concretisation
`NameLoss.concretizeKeep` — `makeConcrete`/`destructiveSub`, which deletes the definitions
with fewer than two abstract parts and destructively rewrites every mention — to the additive
`KDefaultStep`, and the satisfiable three-constraint `W3 = {u <- ((|k,c|)), u <- (z, (|k|)),
u <- (x, y, (|k|))}` mints for ever, three steps to the round (`W3_mints_unbounded`). A
concretisation kills a key witness in exactly two ways, one per clause of `keepDefs`: as a
DEFINITION of the concretised variable (`notMem_lone_lhs` — the mode the Stage 3 brief named)
and as a MENTION of it (`notMem_lone_mention` — the mode the brief's sketch assumed away, and
the one the engine runs on); everything else survives (`resolved_of_concretizeKeep`).
MEASUREMENT (`tracker/repro/satterm/`, `W3` as a `json:` seed, 100 id bases, default flags):
SOLVED 100/100, and the mechanism's FIRST re-mint really happens — at 55 of 100 bases
`makeConcrete u` precedes the dequeue of the kept `u <- (x, y, (|k|))` and `splitConcrete`
mints (0 mints at the other 45, where the keyed reuse fires instead; the syntactic guard mints
at 100/100). The loop stops there through a defence no relation here states: `common`
dedup-unifies the re-minted name with `z`, the variable of the deleted witness, at 55 of 55.
MEASUREMENT, the corpus (`keptdef-sweep.sh`, 110 example modules, both flag sides from one
class set; a `SplitKeyed` count added to `keptdef-mints.py`): kept-definition mints — which
ARE these loop-layer re-mints — are **157 under the keyed guard against 156 under the
syntactic one**, in the same 27 of 110 modules, with 748 vs 715 kept-definition dequeues and
identical verdicts; the restore side reproduces the 2026-09-02 baseline exactly. **The guard
that makes the additive calculus terminate removes none of the loop-layer re-mints.** Scope,
machine-checked: `KSplitApp` has no `¬ Named` premise while the shipped `splitConcrete` asks
that lookup FIRST, so the witness's first re-mint is faithful (`W3sat_remint_enabled`) and its
later ones are not (`named_after_round`) — whether the two-lookup rule plus deletion terminates
is now the ranked-first open question. Write-up `tracker/satterm/KEYED-LOOP-STAGE3.md`; the
only Scala change is the adoption comment recording this answer.

**Design rule, written down after Stage 3 (2026-09-03).** A guard may replace a mint by a NAME
that denotes the same row (the keyed reuse: `ksplit_reuse_sat`, model set unchanged), never by
silence. Plain refusal — "do not split-mint when the left-hand side is already concrete" — was
considered and withdrawn: the minted name is the only channel through which two kept
definitions of one group under different concrete left-hand sides ever meet, so refusing it can
turn a refutation into an acceptance (the two-concrete-lhs instance in the conversation record;
the input-level version is caught by the label check, a derived one would not be), and the
channel is live on real code: of the 157 kept-definition mints in the corpus, 133 are later used
as a name by another partition (`keptmint-consumers.py`, scratch, 2026-09-03). The candidate
that obeys the rule is Stage 4: when the premise's left-hand side is concrete `C`, key the split
on the complement row `C \ K` and REUSE any variable already carrying that row — which is what
`common` achieves after the fact, moved into the rule where it holds in every order.

**Stage 4, the same day: the concrete-row reuse WORKS for the split, and the split was not the
whole engine.** THEOREM (`Rowpartition/KeyedRow.lean`, 94 theorems, write-up
`tracker/satterm/KEYED-ROW-STAGE4.md`). Add the clause the Design rule points at — a premise
`v <- (S, K)` whose left-hand side has a concrete definition `v <- ((|C|))` REUSES any `z` with
`z <- ((|C \ K|))`, emitting `z <- (S)` (sound: `conc_lone_sat` says the two concrete
definitions ARE the lone witness `v <- (z, K)`, and `ksplit_reuse_sat` finishes;
`K2RowApp.models_iff`, the model set does not move) — and make the deletion faithful to the
Scala's `srs`, i.e. keep the cancellation fact `z <- ((|C \ K|))` that `makeConcrete` derives
from each one-abstract definition before `destructiveSub` drops it (`concretizeSrs`, sound,
strictly larger than Stage 3's `concretizeKeep`; the `K ⊆ C` guard is `key_subset_of_model`, not
hidden). Then the guard `Carried G v K := Resolved G v K ∨ (v <- ((|C|)) and some z <- ((|C \ K|)))`
is an INVARIANT of the deleting step (`carried_concretizeSrs`): Stage 3's two failure modes are
precisely the two ways a lone witness turns INTO a concrete-row carrier. `ResGuardTerm`'s budget
therefore survives, and the split mints boundedly on every satisfiable input in every order
(`mintsBoundedOnSat_splitFragment`, bound `|allVars G₀| + hmeas L rho G₀`); Stage 3's `W3` dies
under the rule (`W3_row_reuse` emits `z <- (x, y)` where the shipped loop needed `common`;
`W3_not_mintable`). Every non-syntactic branch carries `¬ Named`, so the Stage 3 faithfulness gap
is closed for this relation (`K2MintApp.toSplitApp`: every mint here passes both shipped
lookups). **What is NOT bounded is the calculus**
(`not_MintsBoundedOnSatKeyed2`): the satisfiable, split-free `W4 = {v <- ((|a,b,c|)),
v <- (x, (|a|)), v <- (y, (|b|))}` mints for ever through guarded RESOLUTION, whose guard is
still keyed on `Resolved` and whose resolvent `v <- (w, (|a,b|))` is absorbed by the
`makeConcrete w` that makes the mint's own name concrete — Stage 3's failure mode 2 with no
split anywhere, so `W4` refutes `TerminatesOnSatKeyedLoop` as well, and that is a theorem
(`W4_kloop_mints_unbounded`, `W4_not_TerminatesOnSatKeyedLoop`): on this witness `srsOf` is
empty, so the faithful step and Stage 3's `concretizeKeep` coincide. Rekeying `resolution` on
`Carried` too, with the matching reuse branch, closes it in Lean
(`mintsBoundedOnSatKeyed2Star`, `keyed2_star_vs_shipped_res`). NO SCALA CHANGE: the exact
`splitConcrete`/`learnPartitions` edit (a `concRows` map of the bare concrete partitions, a
third lookup before the mint, a `SplitRow` reuse tag) and the matching `resolution` edit are
written out in the report, UNIMPLEMENTED and unmeasured — that is Stage 5.

**Stage 5, the same day: both concrete-row branches IMPLEMENTED behind flags, measured, and
ADOPTED — `ermine.splitRow` and `ermine.resRow` now DEFAULT TO TRUE** (`-Dermine.splitRow=false
-Dermine.resRow=false` restores the previous guard pair; coverage is PARTIAL: the mint bound
`mintsBoundedOnSatKeyed2Star` is against concretisation deletions, while `makeEmpty`/`unify`
deletions are outside the relation and the Scala lookup cannot see an emptied carrier — 74 of the
corpus's 157 kept-definition mints have an empty complement and stay mints, protected only by
eager empty propagation; Stage 6 formalises that step). As measured before the flip:** `-Dermine.splitRow` (the split's third lookup) and `-Dermine.resRow`
(resolution's second) are in `Constraints.scala` with the `SplitRow` / `ResolutionRow`
provenance tags and one shared lazy lookup in `learnPartitions` — a single fold over
`proc ++ incm` producing the map of BARE CONCRETE partitions `con -> u` and, on the way, the
row of the `v` at hand; the branch fires when `k ⊆ C` and `concRows(C -- k)` hits.
FAITHFULNESS, traced before the lookup was written: a NONEMPTY concrete row lives as a bare
partition in the `proc` queue and NOWHERE else — `makeConcrete` never calls `instantiateType`
and returns the dequeued partition to `proc` — while the EMPTY row is the exception
(`makeEmpty` writes it into the `SubstEnv` and DELETES every partition mentioning the
variable), so the lookup is a LOWER bound on the Lean's `mk u ∅ R ∈ G`: it can only miss.
The Scala also asks `k ⊆ C`, which `K2RowApp` does not (it gets it from the model); that too
can only refuse a reuse, so no refutation is lost. Correspondence proved:
`Rowpartition/KeyedRowScala.lean` (33 theorems) states the spec the Scala actually meets
(`MyRowSpec`, `ConcRowSpec` — one `Option` row per variable, plus the explicit `k ⊆ C`) and
proves `scalaRowSplit_step : K2SplitStep` and `scalaRowRes_step : K2ResStep` for THAT, on a
MODELLED system, the model being needed only to close the two gaps at the MINT guard
(`conc_unique_of_model`, `conc_key_subset_of_model`, isolated in `concRow_none_uncarried`).
MEASUREMENT, every gate from one class set in four configurations
(`tracker/satterm/KEYED-ROW-STAGE5.md`): `core/test` 903/904 both sides; 129 stdlib modules
with byte-identical traces and ZERO firings of either rule; corpus 0 of 66 and 0 of 34
differ, `shouldfail/` 40/40 (two of which exercise the new resolution branch); 188 published
interfaces, **0 weaker**, one attributable binding hand-classified (`np01.inferredRestate`
loses a FORCED existential, 7 -> 6, equivalent); `repl-smoke` 4/4, `lsp-smoke` 98/98; seeds
300/300 solved and 200/200 rejected, `W3` mints at 55 of 100 bases under the default and **0
under `splitRow`**. POPULATION: `SplitRow` fires 4 times in 3 of 110 example modules (split
mints 637 -> 626, kept-definition mints 157 -> 154 with all 133 consumers still finding a
name); `ResolutionRow` 19 times in 5 modules (resolution conclusions 1,748 -> 1,696). Both
branches are RARE on this corpus and neither is dead code; the `W4` seed does NOT exercise
`resRow` in the real loop (its carrier only exists from round 2, which `makeConcrete`'s order
prevents), so the positive control is `W4c`, `W4` plus that carrier. TIMING, one JVM at a
time on an idle machine over three passes (ResStar 5-9, RowStress 10/14, CoStar8, `gu05`
three runs per configuration): **nothing moved in either direction** — every ratio is inside
the run-to-run spread of the default itself (5 % on ResStar9 between idle passes, 25 %
including a loaded one), and the `ResStar` family cannot reach either branch at all, since
the resolution premise's left-hand side never becomes concrete there (traced: zero firings
under both flags). WHY THE POPULATION IS SMALL, classified over the 110 default traces: of
the 157 kept-definition mints, **74 have `K = C`, so the complement is the EMPTY row** and
the only carrier the rule could use is the one `makeEmpty` deletes; 82 have a nonempty
complement that nothing names; 1 is carried. The carrier exists essentially only where
`makeConcrete`'s own cancellation has just built it — Stage 4's `srsOf` fact — which is the
lone witness's own situation, already covered by `splitKey`. NEITHER DEFAULT WAS FLIPPED and
nothing was committed; the report's Part C carries the two one-line diffs with the ADOPTED
comment each would need, the re-run list, the honest scope and a per-flag recommendation:
**ADOPT WITH CAVEATS for both, as ONE decision** — `mintsBoundedOnSatKeyed2Star` is a
property of the PAIR (`splitRow` alone bounds only the split fragment,
`mintsBoundedOnSat_splitFragment`; `resRow` alone bounds nothing), and the caveats are the
small population, the absence of any speed win, and the usual behaviour-change churn.

**Stage 6, the same evening: `makeEmpty` as the second deleting step — the hole is exactly the
empty row's carrier.** THEOREM (`KeyedEmpty.lean`, `tracker/satterm/KEYED-EMPTY-STAGE6.md`):
with the compiler's `makeEmpty` added faithfully (`makeEmptyD`, `v <- ()` to the environment,
not the system), Stage 4's invariant fails (`carried_not_invariant`) and its potential strictly
increases (`hmeas_increases`) — in exactly one way, the deleted carrier of the EMPTY row. (T2):
the Stage 4 bound holds verbatim in every order under the order hypothesis that each `makeEmpty`
leaves an empty-row carrier behind (`mintsBoundedOnSat_emptyPersisting`, `EmptyKnown` made
checkable) — eager empty propagation, the first of the four unformalised defences, now stated
but not measured. (T1) unconditionally with a one-line repair: retain `v <- ()` / let the lookup
see the environment (`mintsBoundedOnSatKeyed3E`), which turns the 74 empty-complement
kept-definition mints into reuses (`G7_mints`, `G7_blocked`). The unhypothesised statement is
neither proved nor refuted; `unify` is the last unmodelled deletion. No Scala change.

**Stage 7, 2026-09-04: the repair implemented behind `-Dermine.emptyRow`, DEFAULT OFF, and
measured.** The §3i one-line repair is in `Constraints.scala`: a FIFTH branch of
`splitConcrete` and a FOURTH of `resolution`, taken when the Stage 5 concrete-row lookup
misses because the complement (resp. resolvent) row is EMPTY and some variable is known to
denote `∅` — read from the `SubstEnv`, where `makeEmpty` leaves the fact, which is
`KeyedEmpty.makeEmptyE` implemented literally and LOOKUP-ONLY (re-enqueueing `v <- ()` would
call `makeEmpty` again and cycle). The design was chosen on data: at 74 of 74 of the corpus's
empty-complement mints a `makeEmpty` had already run in that module, against 14 of 74 in the
same solve segment and 0 of 74 with the fact still queued. What the branch EMITS is not the
Lean reuse's conclusion — a partition about the emptied carrier would reach `makeEmpty` twice
and panic — but the propagation that conclusion forces, `x <- ()` per group member (resolution:
the two reuse conclusions with `∅` substituted for the carrier); `KeyedEmptyScala.lean` proves
that IS the reuse composed with its `makeEmptyE` step (`emptyReuse_compose`), so one Scala step
is two steps of `K3ELoopStep` and the Stage 4 bound applies to the rule as written
(`scalaEmptySplit_run`, `scalaEmptySplit_bounded`). Soundness needs no carrier at all
(`group_forced_empty`). MEASURED, every gate from one class set: the new tracked seed
`G7` mints at 100 of 100 id bases with the flag off and at NONE with it on; `core/test`
910/911 both sides; corpus verdicts 23/43 and 18/16 with `shouldfail/` 40/40 and the four
message differences shown by per-file re-runs to be `--batch` drift; 188 published interfaces,
0 weaker, two attributable bindings both hand-checked equivalent and more economical;
`repl-smoke` 4/4, `lsp-smoke` 98/98; stdlib boot trace byte-identical. Population, the largest
of the series: `SplitEmpty` 65 firings in 16 of 110 modules, `ResolutionEmpty` 183 in 19,
kept-definition mints 154 -> 82 (73 of the 154 have an empty complement), resolution
conclusions 1,644 -> 792. **The one gate that fails is timing: `incomplete/gu05` is 1.9x
SLOWER (1.03 s -> 1.96 s) and the cause was not isolated** — JFR puts the extra time in the
row-constraint QUEUE, not in the environment scan, and the module derives LESS under the flag.
Report recommends **DO NOT ADOPT YET**: keep the flag, settle `gu05` first. Nothing flipped,
nothing committed. Write-up `tracker/satterm/KEYED-EMPTY-STAGE7.md`; the remaining unmodelled
deletion is `unify`.

## 2026-09-02, latest: the two shipped defaults nothing proved — `PROMPT-default-termination.md` ANSWERED

Both questions Lean-first; every result below is labelled THEOREM (about the additive rule
set, `tracker/lean/Rowpartition/`) or MEASUREMENT (about `Constraints.incorporateAll`, with
the instrument named). The development has no vocabulary for the single-pass loop, so a
statement about it is a measurement, never a theorem.

**Q1 — "complementary defences" is FALSE; the compiler still terminates on the witness.**

* THEOREM (`DefaultDiverge.lean`, `not_CRule`): the shipped rule set `DefaultStep`
  (= `CutRuleStep` with `resolution` GUARDED, i.e. `genRules=cut` + `resGuard`) admits chains
  of every length from an unsatisfiable eight-constraint system `CRule.W` that the per-label
  check on the INPUT does not refute (`W_witness : W_unsat ∧ Diverges W ∧ ¬ Refuted W.toList`).
  The gadget `gSeed` cannot be an input — unit propagation is complete for single-variable
  constraints — so it is hidden behind two `w <- (v, s); w <- (x1, x2, s, (|l|)); x <- (x1, x2)`
  triples that propagation cannot see through in either polarity and that four
  `NonGenStep`s (fold, cancellation, twice) unfold. The saturated set `G₄` IS refuted
  (`G₄_refuted`). So the four documents' sentence was retired: what is proved is that the
  guard covers satisfiable systems (`guarded_terminates_of_satisfiable`) and the check
  covers `gSeed` and, in general, only what propagation can force (`LabelProp.Incomplete`).
* MEASUREMENT (`tracker/repro/crule/run.sh`, real `Subst.solve`, exact ids): `W` is REJECTED
  at 1000 of 1000 contiguous id bases under the default flags, in 2–75 ms each, by
  `RHS.merge` — "Fields appear twice in row: Set(l_i)" — never a hang, never an acceptance;
  also 100/100 under `genRules=all` and 10/10 with `resGuard=false`. The trace of base 0
  shows the loop DOES enter the mint round (4 Resolution-minted ids), but eager
  `substitution` spreads the resolvents' multi-label concrete parts into rows already
  carrying one of them and the duplicated-field check fires at the 50th dequeue. The label
  check never fires on `W` (predicted); it does on `gSeed` and on `G₄` (controls c1, c3);
  the satisfiable sibling `Wsat` SOLVES (c4); under `genRules=nongen` the unsatisfiable `W`
  is ACCEPTED (c6) — one more instance of `nongen`'s unsoundness, and one the label check
  cannot cover. Source level: `tracker/repro/crule/CRuleHang.e` is rejected the same way
  ("Fields appear twice in row: Set(Repro.CRuleHang.l1)"), blamed at `1:1` — the merge
  error still blames the module header, unlike the label check since follow-up item 1
  (small diagnostics follow-up, not fixed here).
* VERDICT on `TICKET-row-constraint-decision.md` §7 Stage 5 (the work budget): the case is
  "insurance whose premium is now known", NOT "urgent". The rule-set counterexample exists
  and is proved, but `incorporateAll` does not walk into it on this witness at any of 1000
  queue orders: a refuter the label check is not — `RHS.merge` (`SplitNecessary.FiresMerge`)
  — reaches the contradiction first. Stage 5 is therefore not scheduled by this result. What
  is NOT established, and remains the only gap between "measured" and "guaranteed": no
  theorem says the loop always finds a merge before it loops on an ill-typed input, and no
  theorem says the combined rule set terminates on WELL-typed input (`ResGuardTerm` covers
  guarded resolution alone; `guarded_terminates_of_satisfiable` says nothing about the
  combination with substitution and `splitConcrete`). If a witness is ever found that the
  loop follows into the mint round without a merge, Stage 5 becomes urgent; until then its
  premium is one counter and one `tml.die`, and its benefit is unmeasured.

**Q2 — `keepDefs` can mint (half of the prose was wrong), and does, on real code.**

* THEOREM (`KeepInert.lean`): guarded resolution is INERT on the kept definitions
  (`keep_gres_inert`, `keep_gres_runs_inert`; the loop's steps are a subset, so this
  transfers). `splitConcrete` is NOT: a kept definition with a nonempty concrete part is a
  `SplitApp` premise (`KeepMint.keep_mints` vs `concretize_no_split`; `prose_false`). What
  is true: bare kept definitions (the `NameLoss` `u <- (x, y)`) are inert for both minting
  rules (`keep_mint_inert_of_bare`), and any mint on a kept definition was already enabled
  on the INPUT before the deletion (`keep_split_of_kept`, hypothesis `u ∉ vset c`) — keepDefs
  restores a mint the deletion suppressed; it creates none. The prose in
  `TICKET-substitution-gap.md` §7 is annotated accordingly.
* MEASUREMENT (`tracker/repro/keepmint/run.sh`; `tracker/tools/keptdef-sweep.sh`, i.e. `keptdef-mints.py`
  over a serialized `-Dermine.rowTrace` of every `core/examples/**/*.e`, 110 modules, plus one
  stdlib boot; per-module results in `tracker/repro/keepmint/corpus-*-2026-09-02.txt`): the instance mints in 16 of 32 id/order configurations; on the example
  corpus kept definitions are re-dequeued 715 (329 the kept definition itself, 386 partitions derived from one after the concretisation) times, 284 (42 strict) of them with a concrete
  part, and `splitConcrete` MINTS on 156 (24 on the kept definition itself) of those (128 reuse an existing name)
  across 27 (14 with a mint on the kept definition itself, all ten `Ai/` modules among the 27) modules; the stdlib boot has 0 `makeConcrete` steps and hence 0 (it has
  no concrete rows to concretise — the §7.9 population fact again). A split mint is bounded
  on its own (`Cut.split_terminates`); the corpus sweep of `TICKET-substitution-gap.md` §7
  (every `.e` incl. `incomplete/`, no timeouts) is the only evidence about the combination.
* No Scala change. The only edit under `core/src` is the `resGuard` comment in
  `Constraints.scala`, which asserted the retired sentence.

Audit after integration: `lake build` -> `Build completed successfully (811 jobs)`;
`lake env lean Audit.lean` -> **1790 theorems audited, 0 using a non-standard axiom**
(was 1625). Baselines re-run 2026-09-02 (after the comment edit and recompile): `core/test`
903/904 (277 s; the one failure is the known `Constraints.disjunction sound` generator
starvation, re-confirmed with `testOnly`), `repl-smoke` 4/4 suites (35 checks), `lsp-smoke`
98/98, and 129 stdlib modules loaded on every one of the sweep's 110 runs.

Documents corrected: `tracker/lean/README.md` (module map row, `ResGuardDiverge` bullet),
`TICKET-row-solver-8abc.md`, `TICKET-editor-and-solver-followups.md` §8,
`ResGuardDiverge.lean` (header and summary docstrings), `Constraints.scala` (comment),
`TICKET-substitution-gap.md` §7. Still stale and NOT fixed here (flagged in the prompt):
`TICKET-signature-resolution-fragility.md` (headline fixed by `a4b62c0`),
`TICKET-row-solver-8abc.md` §"The signature surface", `TICKET-editor-and-solver-followups.md`
§9, `TICKET-row-constraint-decision.md`'s "No Scala changed" status line.

## 2026-09-02, later: `ermine.labelCheckEarly` ADOPTED, label-check blame goes to the call site

`GenRules.labelCheckEarly` now DEFAULTS TO TRUE: the per-concrete-label refutation runs on
the input partitions BEFORE `q.expand`, so an unsatisfiable input is refuted before the
saturation can diverge on it. `-Dermine.labelCheckEarly=false` restores the late position.
What had blocked it was follow-up item 1 (11 of its 26 changed messages blamed a stdlib
signature); that is fixed in three places -- `Subst.instantiatedAt` locates a scheme's
constraints at the occurrence that instantiates them, `Term.sub` keeps occurrence positions
instead of the binder's, and `Subst.solve` blames the refuted partition's constraint in the
file `tml` is in -- see `TICKET-editor-and-solver-followups.md` §1 for the mechanism and
`core/examples/shouldfail/RESULTS.md` for every message before and after.

Gates, all from snapshotted class directories, one JVM per file: 66-file corpus verdicts
identical (23/43, `shouldfail` 40/40), 26 label-check messages all in the user's file at the
call site, 16 further pre-existing messages move definition -> call site or stdlib -> user
file; `incomplete/` 34 files verdicts identical (18/16), 16 messages move to call sites,
`witness03` and `unsound03` no longer fall back to `1:1`; `core/test` 903/904 (known failure
only); `lsp-smoke` PASS 82.

## 2026-09-01, later the same day: items 8a / 8b / 8c ANSWERED

See `tracker/TICKET-row-solver-8abc.md`.

**ADOPTED 2026-09-02: `ermine.resGuard` now DEFAULTS TO TRUE** — `resolution`'s mint is guarded
by the resolvent reverse lookup. `-Dermine.resGuard=false` restores the previous behaviour
exactly. Gates under the new default: `core/test` 903/904 (known failure only), 66-file and
34-file corpora 0 files differ, `shouldfail/` 40/40 rejected, `lsp-smoke` PASS 82.
The win: `core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e` goes from ~12.0s
of solve to ~1.1s. `resolution` fires on 18 example modules and ZERO stdlib ones.

The other three flags stay DEFAULT OFF, each for a measured reason:

    -Dermine.labelCheckSaturated=true  0 additional refutations on BOTH corpora -> leave the
                                       check reading the input (ticket 8a's own criterion)
    -Dermine.labelCheckEarly=true      verdicts identical but 26 of 66 messages change: better
                                       text, 11 worse locations -> revisit after follow-up item 1
                                       [ADOPTED 2026-09-02 once item 1 was fixed; see the top]
    -Dermine.spliceGuard=true          its precondition fails on 90% of splices, and the .ei
                                       diff shows it DEGRADES signatures (resolved concrete rows
                                       become constrained polymorphic) -> do not adopt

Seven new Lean modules (`ResGuard`, `ResGuardTerm`, `ResGuardDiverge`, `Saturate`, `Splice`,
`LabelAlgo`, `SpliceGuard`); `lake env lean Audit.lean` reports 1465 theorems, 0 non-standard
axioms.

Headline: guarding `resolution` terminates on every SATISFIABLE system
(`guarded_terminates_of_satisfiable`) and not in general (`gSeed_diverges`), and there is
a SECOND cliff — driven by `resolution`, not `commonSubexpression`, on a well-typed
program — that the guard removes (`ResStar5`: >240s off, 0.2s on). `resolution` fires zero
times in a stdlib boot, which is why no existing corpus could see it;
`tracker/tools/gen-res-star.py` builds the population that can.


## ADOPTED 2026-09-01

Both changes are now the DEFAULT in `Constraints.GenRules`:
`ermine.genRules` defaults to `cut`, `ermine.labelCheck` defaults to `true`.
`-Dermine.genRules=all -Dermine.labelCheck=false` restores the previous compiler
exactly. Nothing is committed.

Adoption gates, all against the NEW defaults with no flags:
- 66-file corpus vs restored-old-behaviour: 15 differing line-pairs, ALL explained —
  14 are fresh-variable ids (the cut mints fewer, so the `Supply` counter shifts) and
  1 is field print order on a provably identical row set.
- `shouldfail/`: 40/40 still rejected, 0 modules loading.
- Per-file over `incomplete/` + `ai/` (45 modules, one invocation each):
  **exactly 4 verdicts change, `unsound01`-`unsound04`, LOAD -> REJECT.** Nothing else.
- `core/test` with no flags: **903/904**, the one failure being the pre-existing
  `Constraints.disjunction sound` generator. 4:42.

The VS Code extension is installed (`clarifi.ermine-lang@0.1.0`, packaged with vsce);
`bin/ermine-lsp` shares `bin/ermine`'s classpath so the editor runs these defaults.

DEFERRED to a later session: diagnostics. Two of six label-check rejections
(`witness03`, `unsound03`) can only name the field, not the constraint, because their
offending constraint is not in the file being compiled. [DONE 2026-09-02: both now
blame the call site, `32:16` and `81:16`; see the top of this file.]

Handoff note. Everything below is DONE and verified unless marked otherwise.
Authoritative documents: `tracker/TICKET-row-constraint-decision.md` (1303 lines,
§0–§9) and `tracker/lean/README.md` (per-theorem status + axiom audit).

## The recommendation

**Take `cut`. Do not take `nongen`.** See ticket §7.10 / §7.11.

`cut` = disable ONLY the fresh-minting `else` branch of `commonSubexpression`
(`Constraints.scala`, guarded by `GenRules.cseMints`). Keeps the reuse and
folding branches, `splitConcrete`, and `resolution`.

Verified: cliff gone (CoStar8 156s→0.04s, RowStress8 277s→0.11s); 1447 stdlib
signatures with 2 textual diffs both PROVED equivalent; 1581 example entries with
26 diffs all PROVED equivalent; should-fail corpus 40/40 rejected with identical
messages; `core/test` 903/904 (known failure only); `repl-smoke` 4/4.

`nongen` is UNSOUND: accepts 5 ill-typed programs (`der06`, `der07`, `der08`,
`inc08`, `mis02`) and falsifies `Constraints.join example`.

## Working tree (nothing committed)

Modified:
- `core/.../Type.scala` — cached `ConcreteRho.hashCode` (value unchanged; verified
  zero baseline drift). Independent of the cut work.
- `core/.../Constraints.scala` — `GenRules` mode switch + `CommonSubexpressionMint`
  provenance tag. **Default `all` is bit-identical to shipped behaviour.**
- `core/.../Subst.scala` — Stage 0 tracing calls in `solve` and `reduce`.
- `scalacheck-binding/.../TestSurfaceParsers.scala`, `TestStatementExtents.scala`
  — corpus count 180 -> 271 (`TestSurfaceParsers.scala` only). CAUTION: that file has
  OTHER `?= <digits>` assertions (`inner.size ?= 2`). Anchor the replacement on the old
  number; an unanchored `\?= \d+` clobbers them and the failure reads
  "Expected 271 but got 2".
- `core/test` result 2026-09-01 with everything in place: **903/904**, the one failure
  being the pre-existing `Constraints.disjunction sound` generator. 4:39.

Untracked:
- `core/src/.../RowTrace.scala` — Stage 0 instrumentation, inert unless
  `-Dermine.rowTrace=<path>`.
- `core/examples/Ai/` — 10 reports + `Common.e` + README (all compile).
- `core/examples/shouldfail/` — 40 must-be-rejected cases + `RESULTS.md` matrix.
- `core/examples/incomplete/` — incompleteness corpus + the 4 unsound modules.
- `core/src/test/.../DisjProbe.scala` — loader-free solver probe: reproduces the
  soundness bug in ~400ms with controls, instead of a 30s module load. Keep.
- `tracker/lean/Audit.lean` — whole-environment axiom audit.
- `tracker/TICKET-row-constraint-decision.md`, `tracker/lean/`,
  `tracker/tools/gen-row-overlap.py`.

## How to reproduce anything

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.genRules=cut" bin/ermine <file.e> </dev/null
_JAVA_OPTIONS="-Dermine.genRules=cut" tracker/tools/g1-diff.sh run new /tmp/g1-cut   # g1-diff resets G1_PROPS
tracker/tools/g1-diff.sh compare /tmp/g1-cut tracker/g1-baseline
python3 tracker/tools/gen-row-overlap.py --out /tmp/probe                            # cliff probes
tracker/tools/sweep-progress.py                                                      # live bar for a sweep
```
Lean: `export PATH="$HOME/.elan/bin:$PATH"; cd tracker/lean; lake env lean Rowpartition/X.lean`

`corpus-run.sh` and `ei-diff.sh` are silent for 15-50 minutes (one JVM per file, 66 and
220 files respectively), and through a pipe even their final line is buffered until exit.
`sweep-progress.py` attaches to an ALREADY-RUNNING sweep -- no flag, no restart -- and
reads position off the JVM's argv against the same sorted file list the sweep walks. It
renders to a TTY on stderr and never into captured output, because sweep stdout is
compared byte-for-byte and a progress bar there is the same noise the JVM's own boot bar
already forces every corpus diff to normalise away. Its ETA is deliberately two numbers:
per-file cost is bimodal (`incomplete/` runs ~35% slower without `resGuard`; `gu05` is
1.1s guarded and 12.0s not), so a single mean smooths the cliff away and lies -- the
overall and recent figures diverging is the signal that a slow stretch has started.

## The label-check rule (added 2026-09-01, after the cut work)

A SECOND finding, independent of the cut: the shipped solver **accepts unsatisfiable
row constraints** (`core/examples/incomplete/unsound0*.e`, 4 modules). Pre-existing;
identical under `cut`. See ticket §7.13 for the full write-up and §7.12 for why
re-enabling `Constraints.disjunction` is NOT the fix (it does not terminate on the
prelude, or on `Constraints.join example`).

The candidate fix is `Constraints.labelClash` + the call in `Subst.solve`, behind
`-Dermine.labelCheck=true` (default false). Refutation-only: emits no partition, mints
no variable, ranges only over labels in a `ConcreteRho`.

Gates green so far:
- 129 stdlib modules load, 11.11s vs 11.17s with the flag off
- `core/examples` + `ai` + `shouldfail` (66 files): output **byte-identical**, 297 lines
- `DisjProbe` solver-level probe: label rule 0/10 wrong, solver 2/10 wrong
- Lean `Rowpartition/LabelProp.lean`: soundness + mechanized incompleteness, 0 sorry

- `core/examples/incomplete/`, BOTH rule modes: exactly 4 modules newly fail
  (`Unsound01`-`Unsound04`, the known bugs), **0 newly load**. 2 diff hunks each.

BLAME (fixed): `Subst.solve` now finds the input `Part` mentioning the offending field
and dies at its loc, restricted to the current file. `unsound01` -> `104:18`, the
constraint itself. Two cases (`witness03`, `unsound03`) still fall back to the module
header because their constraint is not in the compiled file. [Fixed 2026-09-02:
constraints are now located at the occurrence that instantiated them, so the search
finds them in the compiled file; see the top of this file.] NOTE: `Loc` has TWO
source-bearing shapes, `Pos` and `Inferred(Pos)` -- matching only `Pos` silently
disables the search and looks like it works.

- wide schema (generator in scratchpad, regenerate with the snippet in ticket §7.13):
  400 labels/1 partition costs +90ms; 200 labels x 16 partitions costs +110ms, FLAT in
  the partition count. Cheap.

STILL OPEN: interaction with `reduce`'s second case unexamined. (The "candidate, not
recommendation" status this file used to carry is SUPERSEDED — both changes were
adopted as defaults; see the ADOPTED section at the top.) Remaining work across this
and the editor is collected in `tracker/TICKET-editor-and-solver-followups.md`.

Lean audit is now mechanical, not spot-checked: `cd tracker/lean && lake env lean
Audit.lean` walks the whole environment (1197 theorems, 0 non-standard axioms).

## In flight when this was written

(Both workflows were stopped 2026-09-01 ~10:35 after delivering their headline
artifacts; the Lean modules they wrote are on disk and `lake build` succeeds on all
798 jobs, so `CutSearch.lean` was not left broken by the kill.)

Two workflows. Neither is required for the recommendation above; both are
supporting evidence.
Run IDs and transcripts (check `journal.jsonl` for `{"type":"result"}` lines):
- `wf_4f1a5042-f05` — lean-cut-safety-proofs
- `wf_6e143d84-dea` — ermine-incompleteness-corpus
- both under `~/.claude/projects/-home-dmitry-research-ermine/539eca98-*/subagents/workflows/`
- if a workflow died mid-run, its results are still in its `journal.jsonl`; the new
  Lean files, if written, are simply on disk under `tracker/lean/Rowpartition/`
  and can be verified directly with `lake env lean` regardless.

1. `lean-cut-safety-proofs` → `CutConcrete.lean` (minting introduces no concrete
   label, so it cannot lose a concrete-label refutation), `CutSearch.lean`
   (bounded exhaustive counterexample hunt, `decide` not `native_decide`),
   `SplitNecessary.lean` (why `nongen` loses exactly those 5).
2. `ermine-incompleteness-corpus` → `core/examples/incomplete/` — realistic data
   queries showing the four ways row inference is incomplete.

**When they land: verify independently, do not trust the self-reports.** Three
agent self-reports have been wrong this session (a module reported compiling
while the library root was broken; theorem counts unreproducible; a "compiles:
true" that raced a concurrent edit). Run `lake env lean` on every module plus the
root, and `#print axioms` on the headline theorems.

## Traps that cost time — do not rediscover

- A NUMBER BELONGS TO AN INSTRUMENT, NOT TO THE COMPILER. A 66-file corpus sweep
  compares VERDICTS and ERROR MESSAGES and nothing else: a module that loads prints
  only `Importing module 'X'`, and `-Dermine.useInterface=false` suppresses the `.ei`
  where signatures live. Measured: `grep -lE 'forall|rho|<-' *.out` matches 0 of 66.
  So a corpus `0 differ` says NOTHING about published types — that surface needs
  `tracker/tools/ei-diff.sh`. On 2026-09-02 a predicted "15 differing line-pairs" for
  the cumulative check came back 0 purely because the 15 had been carried over from an
  `.ei` diff; the prediction was wrong, the measurement was fine. Same class of error
  as comparing against a moving baseline.
- A ZERO IS SUSPECT UNTIL THE INSTRUMENT IS SHOWN CAPABLE OF A NON-ZERO. Three times
  on 2026-09-02 a "0 differ" meant "measured nothing" (`.ei` contamination, a missing
  `PATH`, a metric on the wrong predicate). Positive control for the corpus harness:
  `core/examples/incomplete/unsound0[1-4]*.e` flip LOADED -> REJECTED under
  `-Dermine.labelCheck`, so run them through the same normalisation and classifier and
  confirm a non-zero before believing a zero.
- `corpus-verdicts.py` reads a LIVE directory. The file currently being written has no
  terminator yet and classifies as UNKNOWN, so a sweep in flight always shows exactly
  one UNKNOWN tracking the write head. Not a timeout. Wait for the run to end.
- A full-text corpus diff needs the boot PROGRESS BAR normalised as well as the
  `(N.NN seconds)` timings — it carries per-run wall-clocks, so without it all 66 pairs
  differ by exactly 2 lines and the diff looks meaningful when it is pure noise.

- The `:browse` pretty-printer WRAPS long types. Join continuation lines before
  parsing (see `tracker/tools/g1-normalize.py`); otherwise signature comparisons
  silently compare first lines and every equivalence check passes vacuously.
- `g1-diff.sh run` hard-resets `G1_PROPS`. Inject properties via `_JAVA_OPTIONS`.
- Any drift figure computed from `tracker/g1-baseline/ei` is measuring an
  artefact: `reduce` case 2 splices 121 DERIVED partitions per boot into
  committed output. Compare real builds, not residuals.
- Adding files under `core/examples/` breaks the hard-coded corpus count in
  `TestSurfaceParsers.scala`.
- One waiter per condition. Killing a long job orphans every watcher on it.
- Batch loading -- MANY modules in ONE `bin/ermine` invocation -- used to StackOverflow in
  `StreamTUtils.chop` (the loader's StateT stream chain, reached from the solver's
  `TypeVarGraph`). **FIXED 2026-09-03**: the dependency-order computation is iterative;
  `TICKET-editor-and-solver-followups.md` item 4 carries the mechanism, the property test
  and the gate numbers. `corpus-run.sh --batch`, `ei-diff.sh --batch` and
  `keptdef-sweep.sh --batch` now batch a corpus -- `corpus-run.sh` one JVM for the whole of
  it, `keptdef-sweep.sh` one per directory, `ei-diff.sh` only five files at a time (it needs
  interfaces WRITTEN, which makes the accumulation below far worse). The 66-file corpus goes
  from 19m22s per file to 19 s, `incomplete/`'s 34 from 7m31s to 15 s. What to know
  before switching a comparison over -- PER FILE IS STILL THE DEFAULT in all three, and
  every adopted measurement in this file was taken that way:
  * A batch compiles each module in a session that already holds every module ahead of it
    on the command line. Verdicts came out IDENTICAL on both corpora (0 of 66 and 0 of 34
    differ, 23/43 and 18/16, `shouldfail/` 40/40) but seven modules report a DIFFERENT
    CLAUSE of the same refutation at the same field and position, and published interfaces
    differ on 18 of 185 against a same-configuration per-file CONTROL's 6 of 188
    (0 weaker either way; the batch side is also missing 3 interfaces, two of them because
    a chunk ran out of time).
  * Do NOT merge the corpora into one JVM. `incomplete/gu05` solves in 0.4 s in a fresh
    session and had not finished after 200 s in a session already holding the 66-file
    corpus -- the time is in `learnPartitions`/`substitution`, not the loader. With
    INTERFACES ENABLED (which `ei-diff.sh` needs, since `useInterface=false` suppresses
    writing too) the same cliff appears inside `incomplete/` alone, one module short of the
    end of the group, which is why `ei-diff.sh --batch` chunks instead of taking a whole
    directory at once.
  * A batch dies WHOLE on anything that is not a `Death`. `ConsoleEnv.session`
    (`Console.scala` ~214) restores the session env on `Death`, so a REJECTED module leaves
    nothing behind; a `StackOverflowError` or an OOM reaches `main`'s catch-all and takes
    the rest of the command line with it (the pre-fix 110-file run: 41 of 110 files never
    attempted). `batch-split.py` refuses to split a run that did not produce one terminator
    line per file, so a truncated batch is an error here rather than a partial count.
  * `bin/ermine`'s failure line now names the file: `Unable to load module from '<path>'`
    (`Console.loadProject`). The verdict scripts grep the unchanged prefix.
- Running `bin/ermine` on one `core/examples/Ai/*.e` file alone reports
  `Module not found: 'Ai.Common'`. Put `Common.e` first on the command line. (The
  EDITOR resolves it correctly since the Resident fix below; the CLI still does not.)
- LSP FIX 2026-09-01 (2), `lsp/Resident.scala` `checkFile`: it scrubbed the module
  under check by NAME, which deleted that module's BUILTINS -- `Lib` installs `asOp`
  and class `AsOp` as `Global("Relation.Op", ...)`, and they are only COMMENTED in
  `Relation/Op.e`. Re-reading the source cannot restore them. Now guarded with
  `|| builtinEnv.contains(...)`, the way `Session.reloadChangedModules` always did.
  Only `Relation.Op` and `Layout.Presentation` carry builtins (`grep '[a-z]Mod =' Lib.scala`).
- LSP FIX 2026-09-01 (1), `lsp/Resident.scala` `checkFile`: a module `A.B.C` resolves its
  siblings against the HIERARCHY ROOT, not its own directory -- `SourceFile.filesystem`
  appends the whole dotted path, so the old code looked for `<dir>/A/B/D.e` inside
  `<root>/A/B/`. The header is now parsed BEFORE the loader is built so the name is
  known. This affected any project with a module hierarchy, not just our corpus.
  `core/examples/ai` was renamed `Ai` to match its `Ai.*` namespace (the stdlib
  convention: `Native/`, `Relation/`, `Layout/` all match). Verified: 4 Ai modules
  give 0 diagnostics in the LSP; `tracker/tools/lsp-smoke.sh` PASS (82 checks).
- `core/examples/**` is TYPE-CHECKED by `TestTolerantRead`, not just parsed, and its
  property is "GOOD CODE READS SILENTLY" with a hard-coded tolerance of exactly 4 known
  broken files. Adding a corpus of deliberately-bad code breaks it. Fixed by excluding
  `shouldfail/`, `shouldfail-controls/` and `incomplete/` from that sweep's
  `corpusFiles` (`ai/` stays in: those are valid examples). `TestSurfaceParsers`'s
  2.3d property is what checks the rejected corpus.
- A module that DIVERGES makes `core/test` diverge. Name it `.slow` instead of `.e`;
  every walker filters on `.e`. `core/examples/incomplete/README.md` has the per-file
  timings. Four renamed 2026-09-01: `gu02`, `gu03`, `gu07`, `gu09`.
- `com.clarifi.reporting.writers.TestLegend` "extra args are ignored" is FLAKY: it
  falsified after 70 passed tests on one run and passed on the next, untouched.
- Those four diverge on PRISTINE code too (verified by stashing all three solver files
  and rebuilding): 90s timeout each, with `gu04` finishing in 14.6s as the control.
  NOT caused by the cut or the label check.
- `pkill -f <pattern>` MATCHES ITS OWN COMMAND LINE. This killed three separate runs
  this session, including one reported as a completed test. Split the literal:
  `P="Xms10""24m"; pkill -f "$P"`.
- Never run `sbt` concurrently with another `sbt` on this project; they share the target
  directory and the second invalidates the first.
- **`bin/ermine` WRITES `.ei` interface files, and `ermine.useInterface` defaults to TRUE.**
  So the SECOND side of any A/B corpus comparison reads the interfaces the FIRST side just
  wrote and never re-runs the solver on those modules. This invalidated a 66-file
  comparison on 2026-09-01 before it was caught: the tell was the type-hole report vanishing
  from `Holes.e` and `LayoutTesting.e` on side B, and the stdlib boot dropping from 12.4s to
  5.6s. `tracker/tools/corpus-run.sh` now deletes `core/examples/**/*.ei` before each run
  AND passes `-Dermine.useInterface=false`. Any hand-rolled comparison must do both.
- **Never TIME anything while another build runs.** A full `res-guard-bench.sh` table was
  invalidated on 2026-09-01 by contention with a `lake build`: `ResStar3` was recorded as
  TIMEOUT at 90s and, re-run alone, solves in 0.05s. The table was discarded and re-run.
  Probes measure wall time; anything else on the machine is measurement error.
- **`bin/ermine` exits 0 even when the module fails to load.** It prints "Unable to load
  module" and then reads EOF from stdin and quits cleanly, so an exit-code comparison sees
  nothing. Read the verdict out of the output text --
  `tracker/tools/corpus-verdicts.py <dir> [<dir2>]` classifies LOADED/REJECTED per file and
  diffs two runs, including the error message.
- **`lake` 5.0.0 has no `-j` / `--jobs` option** (both are rejected). To bound memory,
  build modules one at a time (`lake build Rowpartition.X`) and/or set `LEAN_NUM_THREADS`.
- **`tracker/lean/Rowpartition/CutSearch.lean` does not build on this machine.**
  `lake build Rowpartition.CutSearch` is OOM-killed (`Lean exited with code 137`) at 15 GB,
  both with default parallelism and with `LEAN_NUM_THREADS=1`, once with nothing else
  running. It is therefore NOT imported by `Rowpartition.lean` and its 125 theorems are
  NOT covered by `Audit.lean` -- contrary to what README.md used to claim. Everything else
  is: `lake env lean Audit.lean` reports **1465 theorems, 0 non-standard axioms**.


## 2026-09-06: D1 — the row solver's dequeue ORDER and a draw BUDGET, both behind flags, DEFAULT OFF

Stage D1 of the LOOP MODEL programme (`tracker/LOOP-MODEL-PLAN.md`; design
`loopmodel/D1-DESIGN.md`, review `D1-REVIEW.md`, change `D1-CHANGE.md`).  Nothing is committed
and no default moves; adoption is the user's decision.

**What the two flags do.**

* `-Dermine.dequeuePolicy=smallcanon` (default `shipped`) changes `Q.pop` ONLY: fewest
  right-hand-side parts first (`|abstr| + (conc ? 1 : 0)`), ties by the id-ordered
  reverse-topological index, ties by a canonical key built from the right-hand side's variable
  IDS and its labels' NAMES — never from `rhs.hashCode`.  The finger tree keeps its
  `(rhs.hashCode, lhs.hashCode)` order, because `findRHS`, `contains` and `insert`'s `sandwich`
  are range splits on it; only the CHOICE of element changes.  Base-invariant because a change
  of id base shifts every id of a solve by the same amount, while `rhs.hashCode` is a Murmur mix
  of exactly those ids.
* `-Dermine.solveBudget=<n>` (default `0` = off) caps the fresh row variables ONE SOLVE's loop
  may draw.  Counted at the loop's two `fresh` sites, checked once per dequeue at the top of
  `incorporateAll` — the same place the model checks it, so both stop on the same dequeue.
  Exhaustion is a `Death` that says, in the message, that it is a resource limit and not a type
  error.  The counter is a `ThreadLocal` saved/restored at the LOOP's entry, NOT at
  `RowTrace.withSite`, which is a no-op unless tracing is on.
  **The two flags are COUPLED (D1B review):** the budget is IGNORED unless a non-shipped
  dequeue order is also set, and says so on `System.err`.  Under the shipped order a solve's
  draw count depends on the id base, so a budget alone rejects a well-typed program at some
  bases and accepts it at others — the reviewer reproduced `-Dermine.solveBudget=20000`
  rejecting a satisfiable `GU05` at base 0 after 56 s while bases 1 and 2 accept it.  The model's
  drivers apply the same rule (`Loop/Policy.lean`'s `effBudget`), and the trace carries the
  EFFECTIVE budget, so the differential is exact under every combination.  The published
  configuration string `GenRules.toString` gains `+pol:<name>` and `+budget:<n>` when they are
  active and is byte-identical to S2's at the defaults.

**The numbers, on the COMPILER.**  `GU05.json` — the satisfiable input of `PERF-ROADMAP` P10 —
goes from 743 draws / 1.3 s at its best id base and **47,317 draws / 128 s at base 0** to
**306 draws at every one of 25 bases**, ~1.0 s each: spread 1.00x against >= 63.7x, a 155x cut in
the worst base.  `GU05MIN`: SOLVED at all 25, 256 draws at every one.  Corpus cost does not rise
— 68,940 dequeues against the shipped 69,207 (**-0.39 %**) over 2,301,195 solve segments, no solve
worse by more than 2x, **zero verdict changes**.

**The user-visible half.**  In a normal ten-file batch load, `Incomplete.Gu05` does not finish
under the shipped order — the chunk dies at its 900 s cap and the four modules after it are never
reached — and takes **2.08 s** under the policy, after which `Gu06`, `Gu08`, `Gu10` and `Np01`
follow in under half a second each.  Loaded ALONE the same module completes under BOTH settings
in ~16 s, which is the id-base sensitivity itself and not a property of the module.

**What the gates say.**  Flags OFF the shipped path is byte-identical (`stepP_shipped` is `rfl`
on the model side, `popShipped` is the original body on the compiler side): `core/test`
913/914 — the one known `TestConstraints` failure, unmoved; `TestLoopTrace` 714/714; the L2
corpus differential 2,355,430 of 2,355,430 segments agreeing over eight groups; the published
interfaces identical to the base compiler's, 181 of 181.  Flags ON: the same corpus differential
**under the policy** is 2,355,430 of 2,355,430 agreeing, `TestLoopTrace` is 714/714 with the
policy and with the policy plus a budget, `repl-smoke` and `lsp-smoke` pass, and a budget that
FIRES (20 on `incomplete/gu05`, which draws 328) rejects the module with the resource-limit
diagnostic while the model's replay agrees on all 54,235 segments and on the rejection itself.
A per-solve draw census ties the two definitions of the budget's unit together: 54,199 solves of
`boot`, compiler-counted draws identical to the model's, every one.

**What it costs.**  `perf-bench.sh batch`, cold, 5 reps, OFF and ON alternated twice: OFF 13.63 /
13.68 s, ON 13.42 / 13.55 s — inside every run's own spread, i.e. **no measurable difference**
(the O(n) scan in `popSmallCanon` is invisible when the queues are small, and the corpus's whole
population is 68,940 dequeues over 2.3 M solves).  `PERF_MAX_LOAD` had to be raised for this: the
machine's background load is the user's desktop and a batch run leaves the 1-minute average at
~4.3 by itself, so the absolute seconds are not comparable with numbers taken on a quiet machine
while the OFF/ON comparison is.

**Where the change lives.**  `Constraints.scala` (+231/-8), `RowTrace.scala` (+16/-1),
`TestLoopTrace.scala` (+33/-7) in this tree, uncommitted; the model side is `Loop/Budget.lean`,
`Loop/Policy.lean`, `Loop/PolicyReplay.lean`, `Loop/FlaggedSound.lean` and D1-T's
`Loop/PolicyStep.lean` + `Loop/PolicyTerm.lean`.  The tree compiles and `TestLoopTrace` is
714/714 at all three settings (OFF, policy, policy+budget) in the main tree itself.

**THE ADOPTION CONDITION (D1B review U-0, the finding that decides this).**  At the shipped
`-Dermine.rowSound` default the policy STOPS REFUTING two of the seven curated unsatisfiable
witnesses: `seeds/unsat/MIN2` and `FALSE-ACCEPT-2` are rejected at 8 of 10 id bases under the
shipped order and at NONE under `smallcanon` (compiler and model agree, so it is the ORDER).  It
contradicts no theorem — `runP_rejects_unsat` says a rejection is SOUND and nothing says an
unsatisfiable input WILL be rejected; the loop's refutation is incomplete and, as this shows,
order-dependent — but it is behaviour users have today.  **With `-Dermine.rowSound=true` the loss
is exactly zero: all seven witnesses are refuted at all ten bases under BOTH orders**, because
S2's layer (iii) is a complete per-label decision run BEFORE the loop.  So: **adopt `rowSound`
first or with the policy; never the policy alone.**  The PAIR is gated: the 15 top-level examples
and the `Ai` group load at four settings (OFF, policy, `rowSound`, both) with the SAME three
pre-existing `top` failures — `Interp.e`, `Sample.e`, `Yahoo.e`, module for module — and none in
`Ai`.  This also qualifies "zero verdict changes in
2,301,195 solves" — that population is the corpus, which holds no known unsatisfiable input of
this shape, and the gate that would have caught it (`tmp/D1/bindcmp.sh`) was broken until the
review; fixed, it catches it immediately.

**The interface caveat, corrected.**  Turning the policy on moves published `.ei` TEXT, but far
less than this section first said, and no published TYPE changes.  Measured with the module
loader made deterministic (`-Dermine.loadInSeries=true`; the shipped loader is PARALLEL and
thread timing reaches interface bytes, so the original single-repetition control was not a
control) and with the normaliser fixed to anonymise binders BEFORE sorting: the floor is zero at
the BYTE level twice at each setting, and OFF versus ON differs in **one interface, `GridExample`,
in two bindings** (`stackedBarChart`, `stackedAreaChart`) — by ONE implicit KIND binder that is
VACUOUS (a bare binder is kind `*`, and the body pins that kind either way).  Every other
difference, including all three the first pass called "different residual row shapes", is
alpha-equivalence: the same constraint set under a renaming of the existentially bound row
variables.  What remains true: the 6 `incomplete/` interfaces published only under the policy are
real, and are the point of the stage.

**The theorems** (all `#print axioms` clean, no `sorry`; `lake build Rowpartition` 867 jobs,
`Audit.lean` 4,112 theorems / 0 non-standard axioms):

* `Loop/Budget.lean` — `budget_terminates`, `budget_never_accepts`, `stepBud_died_sys`,
  `budget_exhausted_rejects`, `runBud_eq_run`;
* `Loop/Policy.lean` — `stepP_shipped` (`rfl`: the default IS the shipped loop),
  `dequeuePol_shape` and the `shape_*` facts, `dequeuePol_none` (no policy can accept a
  non-empty queue);
* `Loop/FlaggedSound.lean` — the budget's transport: `runBud_noLoss`, `runBud_sat_all`,
  `runBud_models`, `runBud_rejects_unsat` with `BudgetDeath` on the `NonRefutation` exception
  list, `runBud_not_rejected`;
* `Loop/PolicyStep.lean` — soundness for EVERY policy: `stepP_refines_all`, `runP_sat_all`,
  `runP_noLoss`, `runP_rejects_unsat`, and S2's chain;
* `Loop/PolicyTerm.lean` — `budgetP_terminates` for every policy (with `b ≠ 0`, since a budget
  of 0 is off);
* `Loop/Policy.lean` — `effBudget` and its two lemmas, the model's copy of the compiler's rule
  that a budget without a policy is ignored (a DRIVER rule: no theorem statement changed).

`lake build Rowpartition` 867 jobs, `Audit.lean` **4,115 theorems / 0 non-standard axioms**,
`lake build looptrace` 1,670; a `#print axioms` census over **161 declarations** — every one in
the four new modules, `QOk.shape` included (D1B review U-5), plus the three new `effBudget`
declarations — is **0 non-standard**.

**The gap that remains, and it is not new.**  None of this supplies an a-priori FUEL number: a
draw budget bounds DRAWS, and converting that into a bound on DEQUEUES needs a dequeues-per-draw
bound, which is `L5-TERMINATION.md` §R8.6b's open problem.  The budget therefore stops
divergence-by-minting — the divergence eight L5 rounds actually found — and is not a wall-clock
watchdog.

**Traps this stage paid for.**  (i) `.ei` is NOT byte-stable at a fixed configuration: published
constraint lists and concrete rows print in `Set` iteration order, so an interface diff must be
taken up to that order (`tmp/D1/einorm3.py`) — and the normaliser must anonymise binder names
BEFORE sorting, or it reports alpha-variants as differences (D1B review U-3).  (iv) An `.ei`
comparison must be run with `-Dermine.loadInSeries=true`: the shipped loader is PARALLEL and
`Session.scala:558-560` says thread timing reaches interface bytes through the solver's id-hash
queue, so a control run once at the defaults is not a control (U-1).  (v) A verdict-comparison
script must not compare a line that BEGINS with the thing being varied: `bindcmp.sh` compared
`looptrace --verdict`'s whole last line, which starts with the policy name, so it reported SAME
only on a double timeout — and it was the one gate that would have caught U-0 (U-8).  (ii) A driver that runs gates after a build step
must FAIL on a non-zero build — a failed `core/compile` let a 25-base sweep and a differential
run against stale classes and nearly shipped a wrong number.  (iii) Do not `lake build` while a
corpus differential is running; it relinks `looptrace` under the sweep.
