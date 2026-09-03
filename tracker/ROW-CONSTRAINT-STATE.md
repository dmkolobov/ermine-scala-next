# Row-constraint work — state as of 2026-09-03

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
- Loading MANY heavy modules in ONE `bin/ermine` invocation StackOverflows in
  `StreamTUtils.chop` (the loader's StateT stream chain), after ~2 modules of
  `core/examples/incomplete/`. PRE-EXISTING: identical with `-Dermine.genRules=all
  -Dermine.labelCheck=false`. Consequence: **never compare corpora by batch-loading
  them** -- both runs die partway and the counts are partial. Compare per-file.
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
