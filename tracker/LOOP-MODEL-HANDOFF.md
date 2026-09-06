# Orchestrator handoff — state of the world, 2026-09-04

For whoever orchestrates `tracker/LOOP-MODEL-PLAN.md` next (a new session, a different model, or
this session after compaction). Read this, then the plan, then the memory index. Everything
durable is on disk; nothing lives only in a conversation.

## Where things stand

* **Committed on `scala3-migration`** (newest first): `2411296` Stage 6 (`KeyedEmpty.lean`),
  `39d2e5b` Stage 5 + adoption of `splitRow`/`resRow`, `939c2aa` loader batch-load fix,
  `98e7bf2` Stage 4, `e47a3ae` Stage 3, `d736bf9` correspondence lemma, `1e6f52b` adoption of
  `splitKey`, `94a2074`/`d30c4de` the Lean modules and harnesses. Shipped defaults:
  `cut+label-early+resguard+splitkey+splitrow+resrow`.
* **COMMITTED 2026-09-04 (user's decision): `756c59e` Stage 7 (flag off) and `c8484d0` L1.** The
  paragraph below is kept for the record of what Stage 7 is.
* **(was uncommitted)** Stage 7 — the `emptyRow` flag, DEFAULT OFF,
  with `KeyedEmptyScala.lean`, `seeds/G7.json`, `KEYED-EMPTY-STAGE7.md`, ticket §3j, state-file
  paragraph, README, `keptdef-mints.py`. All gates green except gu05 1.9× slower. The USER has
  not decided whether to commit it; ask before committing. Plus the loop-model files L1 adds.
* **Worktree `~/research/ermine/ermine-scala-wt-prof`** (branch `emptyrow-profiling`, no
  commits): Stage 7 + the Stage 7b variant (guard resolution's empty branch: reuse only if it
  adds a fact, else the shipped mint) + `KEYED-EMPTY-STAGE7B.md`. Variant diff also at
  `~/.claude/jobs/880c725d/tmp/stage7b-variant.diff`. Verdict so far: the regression is the
  branch's intended effect (the suppressed mint was the queue's GC); the variant restores 1.0 s
  but re-opens the empty-row loophole in every order except the loop's; NOT adopted. The
  orchestrator's recommendation to the user was: commit Stage 7 as research with the flag off,
  do an explicit queue-GC performance stage, then re-time Stage 7's proved rule. The user
  answered by starting the loop-model programme instead. Both decisions are still open.
* **Worktree `~/research/ermine/ermine-scala-wt-loader`** (branch `loader-batch-fix`): stale,
  its diff is committed as `939c2aa`; safe to `git worktree remove --force`, ask first.
* **Lean**: build 820 jobs, `Audit.lean` 2378 theorems / 0 non-standard axioms, before L1.

## The programme and its protocol

`tracker/LOOP-MODEL-PLAN.md`: L1 executable loop model → L2 corpus trace equivalence → L3
theorems about the model → L4 trace test in `core/test`. One Opus implementer per stage, then
one Opus reviewer (brief template `~/.claude/jobs/880c725d/tmp/brief-review.md`; the stage
briefs are `brief-L1.md` etc. beside it — copy them into `tracker/loopmodel/briefs/` if the job
directory may be cleaned). A stage advances only on the reviewer's ADVANCE verdict; confirmed
findings go back to the implementer (resumable by SendMessage within the SAME session only —
agents of a finished session cannot be resumed; re-launch with the brief + the report instead).

L1 IMPLEMENTED 2026-09-04 (Opus, ~65 min): `tracker/lean/Rowpartition/Loop/*` (13 files, ~2,500
lines), `lake exe looptrace`, `tracker/tools/looptrace-diff.py`, report `tracker/loopmodel/L1-MODEL.md`.
Orchestrator re-verified: build 832 jobs, Audit 2508/0, looptrace builds, W3/G7/NE6 at bases 3 and 11
agree with the compiler's traces. Implementer's own sweep: 240/240 agree, 60 byte-identical.
L1 REVIEW done (`tracker/loopmodel/L1-REVIEW.md`, 696/701 comparisons agree; verdict FIX-THEN-ADVANCE:
F1 CHAMP inlining in SSet.excl/filter, F2 rightWins early return, F3-F7 docs). Fixes APPLIED by the implementer (SSet.excl/filter re-champ survivors; rightWins takes concat's early
return; 851/851 comparisons agree; 11 regression seeds added under tracker/repro/satterm/seeds/; orchestrator
re-verified build 832 / Audit 2508/0 / LBL, COLL, RR agree). Second half of F2 (concat's 2nd early return,
`SSet.changed`) applied; reviewer's FINAL verdict ADVANCE (1,301 trace + 2,572 hash-set comparisons, 0
differing). L1 ADVANCED 2026-09-04. Its reviewed state is COMMITTED as `c8484d0` (the shared
README/root files split by hand so `756c59e` builds without the Loop import). The shared files README.md / Rowpartition.lean carry both Stage 7
and L1 lines and are unstaged; split by hand at commit time. L2 IMPLEMENTED 2026-09-04 (Opus, ~2h40): 2,355,430 corpus segments (stdlib boot + 110 examples,
`loadInSeries=true`) and 2,000 random systems AGREE byte for byte at the compiler's own ids; replay
records `sin`/`slbl`/`svar`/`scon` added to RowTrace.scala (+ one call line in Subst.solve, two
recompiles); model gaps fixed: makeEmpty's skolem refusal (M2), Supply's 1024-id block boundary (M3);
accepted abstraction M4 (envEmptyRow reads the whole inference's SubstEnv; 37 mismatches, `emptyRow` only,
ships off). SCOPE LIMIT: the PARALLEL loader's solves are not replayable (records interleave; gu05's
1,372-partition solve is not in the population) — needs a thread id per record. Build 833, Audit 2530/0.
L2 REVIEW done: FIX-THEN-ADVANCE with no correctness defect (core/test 910/911 after the RowTrace/Subst
change; 920,611 segments re-run; five negative controls confirm M2/M3 load-bearing); eight documentation
findings applied (headline = 12,310 distinct solves / 26,864 row-carrying segments; boot replayed 42x).
L2 ADVANCED 2026-09-04; its reviewed state is STAGED in the index (21 files, +2,601; tree id in
~/.claude/jobs/880c725d/tmp/l2tree.txt) — commit the index as the L2 commit when the user says so, without
re-adding paths. L3 IMPLEMENTED 2026-09-04 (Opus, ~100 min; modules Loop/{Wf,Order,Refine,RefineConcrete}.lean, 4,267 lines;
build 837, Audit 2834/0, 31 headline theorems standard-axiom): (iv) Wf PROVED (closes L1 F6, L2 F5 — LblCoh is a
theorem about the parser); (i) refinement PARTIAL — `sys`, `LoopRel` (+5 sound constructors), four of five
dispatch branches refined, the minting `learn` branch NOT; 4 of 7 died paths proved refutations, 3 classified
as not (skolem kinding, two panics); (ii) termination T2 — the four order properties are lemmas, every learn
step paid by a new processed constraint, MISSING = the loop-level mint bound (blocked by Sup.ofSeed's blk
placeholder and the whole-system-vs-queue-lookup guard mismatch, closable under a model); no witness in
2,033 runs; (iii) DECIDED — trim refuses what proc holds; two benign escapes. L3 REVIEW done (`L3-REVIEW.md`): FIX-THEN-ADVANCE — nothing unsound; (i) covers only non-learn branches
and uses none of the plan's relations; (ii) blocked structurally by `LoopRel.weaken` (arbitrary deletion, no
monotone measure) → needs a tighter relation, not one round's work; (iii) escape 1 provable unreachable,
escape 2 confirmed benign on the compiler. L3 ROUND 2 sent to the same implementer (§6c learn refinement,
SupOk/SupFresh, dead constructors, F2/F3/F4/F6 fixes, and a catalogue of residual `weaken` uses as the spec
for the tighter relation). L4 LAUNCHED IN PARALLEL (`briefs/brief-L4.md`: Part A the core/test trace
property with positive control; Part B thread ids in the trace so the parallel loader — gu05's big solve —
enters the population). L3 ROUND 2 DONE (Loop/RefineLearn.lean 1,558 lines): (i) PROVED for every branch — `step_refines_all`
under flags emptyRow/disjRule/cseMints = false and the supply hypotheses SupOk/SupFresh (replay states
satisfy them via `sin`; seed states only for 100,000 draws), all ten LoopRel constructors live (`emptyE`
removed), F2 fixed, NoSelfUnif proved (escape 1), six residual `weaken` uses catalogued = the `LoopStrict`
spec for (ii). Build 838, Audit 2921/0. RE-REVIEW of round 2: ADVANCE (no weakening; both minting rules inside
`step_refines_all`; all constructors live; six residual weaken sites confirmed non-library). L3 ADVANCED
2026-09-04 with (ii) split out as stage L5 (`LoopStrict` + mint bound; section written in the plan with
acceptance criteria). Three non-blocking closing items sent to the implementer (R-A table completeness,
R-C wording, R-B optional proof). L3 closing items DONE (NoInfRow proved; six-row residual table; Audit 2935/0). L3's files are UNSTAGED
(index still = L2 snapshot). L5 LAUNCHED 2026-09-04 (Opus, `briefs/brief-L5.md`, report `L5-TERMINATION.md`):
C1 LoopStrict, C2 supply invariant preserved by step, C3 the mint bound / witness hunt, C4 emptyRow note.
L4 IMPLEMENTED 2026-09-04 (core/test property via child JVM, 702 solves agree in ~3 s, positive controls
detected, skip path; thread ids in the trace, parallel-loader replay of Ai and gu05 AGREE incl. the
458-partition solve; core/test 913/914; orchestrator re-ran the three properties: pass). L4 REVIEW: F1 CONFIRMED (compiler-side failures reported as PASS) → fixed, flags forwarded to both sides,
positive-control vacuity fixed; FINAL ADVANCE. L4 ADVANCED 2026-09-04. COMMITTED (user's word, 2026-09-04): L2 `9b8aa33`, L3 `9568754` (root import list without the L5 imports),
L4 `9be2214` (with README/plan/handoff/briefs). Working tree now = L5 only: Loop/{Strict,StrictStep,StrictBound}.lean,
the three Strict imports in Rowpartition.lean, L5-TERMINATION.md, L5-REVIEW.md (round 2 in progress). Commit plan when the user says: L2 (the index), then L3 (Loop/{Wf,Order,Refine,RefineConcrete,
RefineLearn}.lean + L3 reports + root import lines), then L4 (RowTrace.scala thread id, the two test
sources, the two tools, L4 reports) with the shared README/plan/handoff in the last one. L5 IMPLEMENTED 2026-09-04 (Loop/{Strict,StrictStep,StrictBound}.lean, 1,723 lines; build 841, Audit 3003/0):
C1 PARTIAL — `LoopStrict` with four NoLoss-licensed deletions, rows 2-5 discharged, row 7 deletes nothing, row 6
(the `concrete` branch) OPEN with `cancellation_bare` showing NoLoss cannot license it; C2 PARTIAL; C3 T2 — the
obstacle localised to `qsys` (queues + empty facts) and to ONE guard case (the emptyRow case), charging argument
shown to fail; hunt 7,468 runs 0 fuel; C4 done. **COMPILER BUG FOUND by the hunt**: satisfiable
`v7 <- (v4,v6), v6 <- (v6,v7), v9 <- (v5,(|l100|))` (tmp/L5/min/panic3.json) makes shipped Subst.solve die with
`panic: reinstantiated type … ConcreteRho(-,Set()) … already bound to ConcreteRho(-,Set())` at ~11% of id bases
(orchestrator reproduced: 5 of 40 bases, e.g. 6, 13, 30); acceptance of a valid program depends on id allocation;
Subst.scala:182 has the fix commented out (`case Some(t) if e == t => warn(...)`). NOT fixed; user to decide.
L5 REVIEW done (`L5-REVIEW.md`): FIX-THEN-ADVANCE — F1 the deletion constructors admit arbitrary GROWTH
(reviewer proved `no_mint_bound_along_strict`), F2 the strict refinement still reaches `LoopRel.weaken`; C3
localisation partly wrong; round-2 spec in §10 (constructors as library operators → queue-hygiene invariant →
guard). BUG ROOT CAUSE (reviewer, traced at base 6): `makeEmpty`'s `aux` maps over ALL of `abstr` including
the emptied `v` (Constraints.scala ≈1564: `abstr.map(v => Partition(v, RHSEmpty(), PartitionEmpty))`), so a
self-referential `v <- (v, w)` manufactures `v <- ()` again → second makeEmpty(v) → panic; `selfSubstitution`
twelve lines away already uses `(abstr - v)`. 3 of 14 panicking hunt seeds have no self-referential INPUT (the
shape is derived via SplitKeyed). Recommended fix: `abstr.map` → `(abstr - v).map` at that line — NOT the
commented-out warn in Subst.scala (wrong layer; would also invalidate model lemmas). USER DECIDED 2026-09-04: fix it. B1 LAUNCHED (Opus; `briefs/brief-B1.md`): Part A = Scala fix + gates in worktree
`~/research/ermine/ermine-scala-wt-b1` (branch `makeempty-self-fix`) against the main checkout's classes, then STOP;
Part B (Lean mirror in `Loop/Step.lean`, TestLoopTrace with PANIC3 in the population, corpus replay, full core/test,
tickets) only after L5 round 2 is idle — the orchestrator messages the B1 agent to proceed; then a B1 reviewer.
L5 ROUND 2 DONE 2026-09-04 (build 841, Audit 3058/0): eliminations are the library operators (`substOut` new,
`makeEmptyE`, `concretizeSrs`; `drop`; one tight existential `requeue`); vocabulary bound PROVED
(`LoopStrictSteps.allVars_card_le`: +m over m minting steps; reviewer's Growth.lean no longer elaborates);
refinement weaken-free (reviewer's Deps.lean: 22 roots clean); `step_empty_makeEmptyE`; `QueueHygiene` stated,
`queueHygiene_no_rebind` proved, invariant FALSE for the current model (`makeEmpty_aux_emits_self` vs
`selfSubstitution_excludes_self`) — provable after B1's mirror; localisation corrected and proved. Still open:
`instRemove`/`concRemove` not live (substOut lacks replace's dedup fact; cancellation_bare), C2, termination.
L5 RE-REVIEW: ADVANCE with the remaining work carried forward (new obstacle R-4: `requeue` licence semantic → `hmeas`
may increase; priority list for a round 3 in L5-REVIEW.md). L5 ADVANCED 2026-09-04, TERMINATION STILL OPEN; whether
to fund a round 3 is the user's decision. L5's files UNCOMMITTED. B1 PART A DONE (worktree ermine-scala-wt-b1): fix `(abstr - v)` + PANIC3.json; gates all green (core/test 913/914,
PANIC3 100/100 solved, 17 other seeds byte-identical, the 14 hunt seeds 1400/1400 solved vs 866/1400 before —
the bug hits 38% of those runs, corpus verdicts identical, .ei 0 weaker, smokes pass). B1 PART B DONE in the MAIN
checkout: Step.lean:126 `.excl v`; six proof sites moved (Wf.makeEmpty_ok, Refine.makeEmpty_died/_run,
StrictStep.makeEmpty_forward/MECover/makeEmpty_noLoss — one genuinely new case discharged by the retained
`v <- ()`), `makeEmpty_aux_emits_self` REPLACED by `makeEmpty_aux_excludes_self` (so `QueueHygiene` is now
provable in principle — preservation is L5 round-3 work); Scala fix applied in main; PANIC3 100/100; TestLoopTrace
708/708 with PANIC3 in the population (18 seeds), controls detected; L1 sweep 180/180; L2 replay top 92,673 +
shouldfail 56,032 agree; core/test 913/914; build 841, Audit 3058/0; ticket item 11, state-file section. Orchestrator
re-verified build/audit/PANIC3/testOnly. B1 REVIEW: ADVANCE (full corpus row trace byte-identical pre/post; alias form has no path; RS5 = 100%-of-bases
rejection fixed; stdlib carries the premise shape, dissolved by selfSubstitution). Five doc fixes sent to the
implementer. COMMITTED 2026-09-04 as `52da5b8` (B1 + L5 round 2 in ONE commit: the fix touched three proof sites inside L5's
then-uncommitted modules, so no buildable split existed). Tree clean. L5 ROUND 3 LAUNCHED (FRESH Opus agent,
`briefs/brief-L5r3.md`: R3.1 Carried-preserving requeue/carried_step, R3.2 load-bearing empty branch + substOut,
R3.3 QueueHygiene preservation certifying B1, R3.4 concrete/learn branches + supply lemma, R3.5 the bound or the
lemma + witness hunt); reviewer after.
L5 ROUND 3 DONE 2026-09-05 (fresh agent; Loop/{Carried,Factor,Hygiene,Residual}.lean, 2,875 lines; build 846,
Audit 3186/0): R3.3 PROVED — `QueueHygiene` preserved by step and along runs from every Wf initial state,
`step_link_no_death`: the reinstantiation panic is unreachable, CERTIFYING B1 (the fix load-bearing at exactly
`abstr.excl v`); R3.1 `carried_step` for all ten constructors, mint bound proved along a Carried-preserving
`LoopStrictKRun`, but the conjunct cannot go on `requeue` (`substOut_breaks_carried`); R3.2 instRemove live,
13/14 constructors; R3.4 PARTIAL (learn/concrete branches; `learnPartitions_drawn` ≤ 1+|proc|); R3.5 T2 with
ONE residual Prop `QStepDichotomy` proved sufficient for the explicit bound (`run_qsys_bound`), new obstacle
`redirect_breaks_carried`; hunt 20,720 runs 0 fuel, 410 model-vs-compiler comparisons identical. ROUND-3 REVIEW: ADVANCE with corrections, APPLIED (the 'mint bound' restated as a queue-visible VOCABULARY
SNAPSHOT bound — no theorem yet bounds the loop's mint COUNT; B1's run-level certification is CONDITIONAL on the
unproved RunSupOk; carried_step 7 proved/4 vacuous/3 by hypothesis; learnPartitions_vocab weaker than C2's
clause). Round-4 spec in L5-REVIEW.md S-11/S-12: refute-or-relativise QStepDichotomy, discharge RunSupOk, choose
the carrier. Round 3 COMMITTED `9060fbf` (2026-09-05, user's word). L5 ROUND 4 LAUNCHED (fresh Opus agent, `briefs/brief-L5r4.md`:
R4.1 refute-or-relativise QStepDichotomy, R4.2 discharge RunSupOk (makes B1's certification unconditional), R4.3 a
real mint count with a productivity condition and a monotone carrier, R4.4 Terminates); reviewer after.
ROUND 4 DONE 2026-09-05 (Loop/{Refuted,Supply,Mints}.lean, 2,180 lines; build 849, Audit 3376/0): R4.1
QStepDichotomy REFUTED on an INITIAL witness (`v2 <- (v0,(|l0|)), v0 <- (), v1 <- ((|l0|))`; the CommonPartition
redirect swallows the carrier; no relativisation helps; the potential itself rises); R4.2 RunSupOk DISCHARGED
(`New Old su` freshness predicate; `step_supFresh`; `run_queueHygiene_of` unconditional except INPUT properties
SupOk/SupFresh + disjRule/cseMints=false) → B1's certification hypothesis-free; R4.3 `KMintRun.mints_le : n ≤ hmeas`
(productive mints, unconditional for satisfiable input) but the loop-level bound needs `HistDichotomy`, ALSO
REFUTED (four-constraint witness; 15 such mints in 6 hunt seeds; replays agree with the compiler); both carrier
horns refuted in Lean; direction left = charge each re-mint to a deletion (counting over queue history). T2.
ROUND-4 REVIEW: ADVANCE (everything reproduced by #eval and compiler replays; all 20 records of the mint witness
byte-identical; hunt extended to seeds 140-198: 5 more re-mints). Findings: U-2 the hypothesis-free certification
covers Replay of REAL traces, not the json seed driver (Sup.ofSeed blk=0 fails SupOk); U-4/T-9 the 'charge re-mints
to deletions' direction does NOT close (charge vacuous for c≥1; seeds 74/139 re-mint at the same (v,K) twice), and
the loop may PUMP (mint installs v <- (w,K); eliminating fresh w withdraws it; mint again) = what a divergence
witness would look like. ROUND-5 SPEC in the review: R5.1 drive the pump toward a witness W, R5.2 charging lemma in
refutable form, R5.3 use the DEQUEUE ORDER (untouched by any measure so far), R5.4 relativise Terminates to a stated
fragment. Doc corrections sent to the r4 implementer. Round 4 COMMITTED `e3cb56a` (2026-09-05, user's word). L5 ROUND 5 LAUNCHED (fresh Opus agent,
`briefs/brief-L5r5.md`: R5.1 drive the pump toward a divergence witness W with compiler replays and hang
detection, R5.2 charging lemma in refutable form, R5.3 dequeue-order lemma, R5.4 stated fragment); reviewer after.
ROUND 5 DONE 2026-09-05 (Loop/{Pump,Dequeue,Fragment}.lean; build 852, Audit 3494/0): (T2) NO divergence — pump
driven to 9 re-mints at one key (~100,000 model solves, 0 fuel; 384 seeds x 10 bases = 3,840 compiler solves, 0
HANG); charging lemma REFUTED in both clauses (`chargeI_false`: destructiveSub withdraws a carrier with no
SubstEnv entry, nothing to charge); dequeue order does NOT repair the redirect (`repairBeforeExam_false`);
`LinkOnly` fragment terminates (`linkOnly_terminates`, bound qsize+1) but no generated seed is in it. Two
untried directions named: a measure over the key's concrete-label structure; a bound on premise pairs per key.
ROUND-5 REVIEW: ADVANCE (everything reproduced; W-6: a 3-label input pumps 10 times at one key, killing the
naive label-structure measure; stdlib-boot inputs carry NO concrete labels — 0 Resolution/SplitConcrete records).
JUDGEMENT: genuinely open, ~65/35 toward termination (directed search plateaus; deep pumps are one key re-derived
from a growing proc, not cycles; vs: diverges one flag away, seven invariants refuted, makeConcrete forgets names
off-ledger). ROUND-6 SPEC: R6.1 search for a state CYCLE up to renaming of minted ids (a repeat = not_Terminates;
no repeat in 100k solves = strong negative), R6.2 recast termination as 'incm empties' (trim + guard completeness),
R6.3 widen the fragment to inputs with NO concrete labels — covers all 373 row-carrying stdlib-boot solves →
'proved for the standard library, open for the examples'. Round 5 COMMITTED `1394df4` (2026-09-05). L5 ROUND 6 DONE (fresh Opus, `briefs/brief-L5r6.md`), UNCOMMITTED:
**R6.3 LANDS — `Terminates` is PROVED, with an explicit bound, for the no-concrete-labels fragment
(`Loop/NoConc.lean`: `noConc_terminates` / `noConc_run` / `noConc_terminates_of_buildQueue`), and a fresh corpus
census puts ALL 373 row-carrying stdlib-boot solves inside it (0 with any concrete label; step census 0 Resolution,
0 SplitConcrete), plus 2,388 of 9,362 of the example programs' own solves; the reviewer widened that to 15,377 of
15,377 stdlib-located row-carrying solves across all 41 traces (W-6e/W-7).** On the fragment the loop is
non-generative — both minting rules are refused BEFORE their `fresh`, so the LOOP draws no id (stronger than the
round-5 review predicted; `PQueue.build`, which runs first, still mints for a non-variable lhs — 8 of the 373 boot
inputs — and the theorem covers them, W-6b) — the vocabulary is fixed, and the three quantities that move (env,
procSys, incm) are each bounded by it; the queue bound needed `unorderedHash_perm` (MurmurHash3's set hash is
order-independent, so `Partition.equals` implies equality of the queue's search key). R6.1 `Loop/Cycle.lean`:
`not_terminates_of_cycle` proved, `looptrace --cycle` built, 134,674 solves / 3,082,009 canonical states searched
(incl. a fresh 50,000-solve hunt), NO canonical repeat, 0 FUEL; NEITHER detector's hit would have been a proof —
the renaming quotient is not a congruence and `rawState` omits the queue graphs / `Sup.blk`,`bsz` / flags / names
that `SEq` demands (W-6a) — the negative direction is sound.
R6.2 (T1) recast (`terminates_iff_incm_empties`), (T2) residual: `GuardComplete` REFUTED by round 5's witnesses,
`ProcSaturates` proved sufficient and proved on the fragment, but the residual is FRAGMENT-RELATIVE (W-6d).
Build 854, Audit 3611/0; 128 new declarations (101 theorems), 375 + 1,722 lines. Round-6 review corrections
W-6a/b/c/d/e/g and W-9 APPLIED (2026-09-05) to the report, the plan row, the README and `ROW-CONSTRAINT-STATE.md`;
build and audit re-checked green after. Commit on the user's word.
(The earlier handoff sentences saying the invariant is false and that B1 must replace the emits_self lemma are
superseded by this paragraph.); the 1,456-partition splitKey=false replay under tmp/L4/gu05nk/ is a model-speed
question, not a disagreement. Reports: `L3-THEOREMS.md` (Round 2 section), `L4-TEST.md`.
Original launch note:
(iv) Wf invariant incl. LblCoh, (i) refinement + soundness, (ii) termination T1/T2/W with compiler replay
of any witness, (iii) single-pass lemma for the Stage 7b question. The plan carries a "Known scope limits"
section (serialized loader only; disjunction seeds only; emptyRow M4; raw-list hash classes untested). F6 was added to L3's acceptance (iv). If the launching session is gone: read both reports, and if the review verdict
is FIX-THEN-ADVANCE, re-launch an implementer with `briefs/brief-L1.md` + the review's fix list.
L2's brief is not yet written; the plan's L2 section is its specification.

## Standing rules the user set (do not relearn them the hard way)
* Do not commit or merge without asking. Never commit red. Re-measure, never inherit a figure.
* Disk is tight: never `lake exe cache get`, never add a Lean `require`, never create another
  Lean project, never touch `~/research/leanwork`; `Rowpartition/CutSearch.lean` OOMs at 15 GB
  and stays out of the root import list.
* One sbt at a time; never sbt during a `bin/ermine` sweep (the classes change under the JVMs);
  every A/B from ONE compiled class set; `corpus-run.sh` and `ei-diff.sh` never concurrently
  (both delete `.ei` files); batch mode is valid only batch-vs-batch; timing gates on an idle
  machine, one JVM at a time. Background shells in the harness are capped at ten minutes: long
  sweeps under `setsid nohup` with a log and a monitor.
* Label results THEOREM (about a relation, name it) vs MEASUREMENT (about `incorporateAll`,
  name the instrument). State coverage honestly at every flag.
* A guard may replace a mint by a NAME for the same row, never by silence (state file, 2026-09-03).
* `pkill -f` matches its own command line — split the literal.

## Instruments that exist
`tracker/repro/satterm/{run,sweep}.sh` (`json:` seeds, id bases, SOLVED/REJECTED/HANG, draws;
`trace` mode needs `ERMINE_JAVA_OPTS=-Dermine.rowTrace=<file>`), `tracker/repro/crule/`,
`tracker/repro/keepmint/`, `tracker/tools/corpus-run.sh [--batch]`, `ei-diff.sh [--batch]` +
`ei-classify.py`, `corpus-verdicts.py`, `keptdef-sweep.sh` + `keptdef-mints.py`,
`splitkey-counts.py`, `rowclosure.py` (additive explorer + seed generator), `batch-split.py`,
`repl-smoke.sh`, `lsp-smoke.sh`, gate-chain scripts under `~/.claude/jobs/880c725d/tmp/postflip2/`.

## Orchestrator note, 2026-09-05 (after L5 round 6)
ROUND 6 DONE (Loop/{NoConc,Cycle}.lean; build 854, Audit 3611/0): R6.3 CERTIFICATION CLAIM — `noConc_terminates`
with an explicit bound; NO id is drawn on the fragment; `unorderedHash_perm` turns queue dedup into a length bound;
corpus: 373 of 373 row-carrying stdlib-boot solves are NoConc → "Subst.solve terminates on every row-constraint
solve of the standard-library boot" (examples 2,388 of 9,362 = 25.5%); R6.1 cycle search 134,674 solves /
3,082,009 canonical states / 0 repeats (`not_terminates_of_cycle`; the renaming quotient is not a congruence, so a
hit would be a candidate, not a proof); R6.2 `terminates_iff_incm_empties` proved, `GuardComplete` refuted by
round-5 witnesses, `ProcSaturates` sufficient. Round-7 pointer: 9,256/9,362 example solves never fire a
generative rule on the input — a preservation question. ROUND-6 REVIEW running (certification checked at the
highest bar). UNCOMMITTED: round 6; commit on the user's word.
ROUND-6 REVIEW (2026-09-05): ADVANCE. Certification instantiated in Lean on the largest boot solve; corpus
re-derived; scope STRENGTHENED to 15,377/15,377 stdlib-located row-carrying solves across all seven groups; W-6b:
"no id drawn" holds of the loop, not the solve (PQueue.build mints for a non-variable lhs; 8 boot inputs);
naive round-7 widening refuted — 111 solves fire a generative rule via Substitution/CSE despite both being blocked
at the input; ceiling 97.6% (vocabulary-fixed), not 98.9%. Corrections sent to the r6 implementer. USER'S POINT
(2026-09-05): Ermine is a reporting language, users always end with concrete fields — the stdlib certification is
a FLOOR; round 7 should certify the examples' no-generative-rule fragment and list the label-carrying residue solve
by solve. UNCOMMITTED: round 6 (commit on the user's word).
Round 6 COMMITTED `157a3f3` (2026-09-05, user's word; certification scope = 15,377/15,377 stdlib-located row solves).
L5 ROUND 7 LAUNCHED (fresh Opus, `briefs/brief-L5r7.md`): the USER-FACING fragment — R7.1 vocabulary-fixed /
no-mint fragment with Terminates, R7.2 census of all 9,362 example solves with a row per residue solve (+ cycle
detector over corpus replays), R7.3 residue classified by shape with per-class lemmas, R7.4 the open problem
stated as certified fractions + a named list of shapes. Reviewer after.
ROUND 7 REPORTED (2026-09-05; uncommitted): `Loop/VocFix.lean` (1,938 lines, 86 theorems), `--cycle`/`--mints` over
corpus replays in `Loop/Main.lean`; orchestrator re-verified build 855 jobs / Audit 3706 theorems, 0 non-standard
axioms / no sorry. Headline: `vocFixed_terminates` + `noDraw_terminates` (RUN-level; input-checkable widening NOT
found), `terminates_of_drawsAtMost` / `drawn_unbounded_of_not_terminates` (a divergent solve draws unboundedly many
ids); the `concrete` branch paid for by `rowSet` (ensureSuperset + findRHS miss + destructiveSub keeps other rows).
Census: examples 9,118/9,362 (97.39%) vocabulary-fixed, stdlib 2,695/2,695; cycle detector over 450,064 corpus
solves 0 repeats; no splitConcrete key minted twice anywhere in the corpus (cmax reaches 4); residue 244 rows
classified A1 97 / A2 29 / A3 47 / B 36 / C 3 / D 32 (D = NameLoss shape in the corpus). REVIEWER LAUNCHED (fresh
Opus; report = "Round-7 review" section of L5-REVIEW.md; scratch tmp/review-L5r7/). Commit only on the user's word.
ROUND-7 REVIEW (2026-09-05): FIX-THEN-ADVANCE — mathematics reproduces exactly (all 50 verbatim, 244 residue rows ×
9 fields identical, theorem instantiated at a 5-`concrete`-step witness of the reviewer's own, SupFresh 450,064/
450,064); three sentences to fix: X-8a "no splitConcrete key minted twice anywhere / pump does not occur" is FALSE
(`incomplete/np01_add_or_recompute.e(134:15)` re-mints a guard key; round 5's pump is the CARRIER key, re-minted on
46/9,362 up to cmax 4, cmax 6 in incomplete/); X-8b census predicate (≥1 inpart, written only after q.expand) hides
19 REJECTED solves, 3 residue → honest 9,381/9,134/247; X-8c hashdiff/eqdiff are literal 0s in --cycle/--mints mode
(differential re-run separately, holds); docs X-8d..g. incomplete/ measured by the reviewer: stdlib 12,682/12,682,
group's own 1,188/1,283 = 92.6%, deepest 281 dequeues. Round-8 pointer: measure/bound the mint CHAIN DEPTH; do NOT
spend a round on "guard key minted at most once". Corrections SENT to the round-7 implementer (resumed).
ROUND 7 CORRECTIONS APPLIED (2026-09-05): §R7.7 old/new table in L5-TERMINATION.md; state file / plan row / README /
§R7.3b / §R7.4 restated (guard key vs CARRIER key; incomplete/ np01 re-mint; both populations 9,362/9,118/244 and
9,381/9,134/247; hashdiff/eqdiff via plain --replay 450,064 replayed 0/0/0; SupFresh 450,064/450,064; Wf kept as a
hypothesis by _of_buildQueue; incomplete/ figures folded in); Main.lean prints grew=? on BUILD and the CycleRep
fields on the json: path. Orchestrator re-verified: build 855 / looptrace 1656 / Audit 3706 theorems, 0 non-standard
axioms / no sorry. READY TO COMMIT on the user's word (round 7 + review + corrections, one commit; include the
handoff note and briefs/brief-L5r7.md). Round 8, if the user wants it: mint CHAIN DEPTH (reviewer X-12).
Round 7 COMMITTED `2f572a5` (2026-09-05, user's word; one commit: VocFix.lean + instruments + report + review +
corrections + brief + this handoff). L5 ROUND 8 LAUNCHED (fresh Opus, `briefs/brief-L5r8.md`, from the reviewer's
X-12): R8.1 instrument the mint CHAIN DEPTH (depth per drawn id; per-key re-mint index for guard AND carrier keys)
over EIGHT groups incl. incomplete/; R8.2 decomposition lemma in Lean (depth ≤ D ∧ re-mints per key ≤ R ⇒ drawn ≤
f(n,m,D,R) ⇒ Terminates via terminates_of_drawsAtMost); R8.3 hunt each factor with compiler replays; R8.4 transcode
np01(134:15) and gu05(62:1) into tracked json seeds (no sbt; orchestrator runs core/test if TestLoopTrace needs a
change); R8.5 incomplete/ first-class. Reviewer after; commit only on the user's word.
ROUND 8 IN PROGRESS, INTERRUPTED TWICE (power cut ~19:27, reboot ~20:24 on 2026-09-05; agent resumed each time by
SendMessage — transcripts survive). FINDING REPORTED AT ONCE (R8.0 in L5-TERMINATION.md): the SHIPPED COMPILER HANGS
on `tracker/repro/satterm/seeds/GU05.json` — 18 constraints / 21 vars / 10 labels, SATISFIABLE (model checked),
transcoded from `incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)` (the corpus solve itself SOLVES; the
only difference is the ids of the four build-minted names = dequeue order) — HANG at 14 of 25 id bases, up to
21,609 ids drawn in 60 s; the model runs out of fuel at every fuel tried (~0.25 draws/dequeue). NP01.json (from
np01_add_or_recompute.e(134:15)) solves. Done so far: Loop/Depth.lean (chain-depth instrument `--depth` +
decomposition lemma §5–§8), R8.1 census over eight groups, R8.2, R8.5; hunt 11,520 runs / 6 timeouts (rerun8.log).
Pending: confirm the hang under a 600 s cap + model `--cycle` at large fuel, reduce the witness, classify the six
timeouts, write R8.3/R8.4, restate outcome as W if confirmed. Then reviewer; commit only on the user's word.
L5 ROUND 8 DONE (2026-09-05), outcome (T2), UNCOMMITTED, awaiting review. New module
`Loop/Depth.lean` (the mint-CHAIN instrument `--depth` + the DECOMPOSITION theorem
`terminates_of_chainRun`: depth <= D and every dequeue key drawing <= R times => Terminates at
`chainBound n m D R = n*D*(2^m*R)^D`); `Loop/Main.lean` prints `depth`/`dm` lines on both paths;
two tracked seeds `tracker/repro/satterm/seeds/{NP01,GU05}.json` transcoded from real corpus
segments (TestLoopTrace picks them up with NO code change -- but GU05@base0 takes 267 s in the
compiler, so cap it before it enters a routine test run). Figures: build 856 / looptrace 1662 /
Audit 3735 theorems 0 non-standard axioms, 35 new decls all standard-axiom, no sorry.
Differential over EIGHT groups (seven + all 34 incomplete/ files) 2,301,195 segments, 0 skipped
/ 0 hashdiff / 0 eqdiff by plain --replay. Census: chain depth <= 2 in the seven groups, <= 4
over everything, per-dequeue-key draws (the theorem's R) <= 11; hunt 3,840 seeds / 11,514 runs
reached depth 5 and NEVER exceeded a guard-key count of 1 -- zero candidates. TWO THINGS A
REVIEWER MUST SEE: (i) R8.0 was written as a compiler DIVERGENCE on satisfiable GU05.json and
then RETRACTED -- longer caps SOLVE base 0 (267 s / 47,317 draws), base 6 (371 s / 81,481) and
base 5 (486 s / 75,059), each after more draws than the one base still unfinished had reached,
so it is a 2,200x order-dependent BLOW-UP, not non-termination, and the outcome is NOT (W); (ii) the remaining
lemma is named three ways in R8.6b, and the recommendation is L-c (bound the DEPTH -- the only
factor no refutation of rounds 4-7 touches) plus a generator built to drive depth, which the
rounds 4-5 generator provably is not. Report: L5-TERMINATION.md "Round 8", brief
`briefs/brief-L5r8.md`, scratch `tmp/L5r8/`.
ROUND 8 DONE (2026-09-05, uncommitted): OUTCOME T2. The GU05 "hang" was RETRACTED — bases 0/5/6 SOLVE at 267/486/371 s
after 47k–81k draws; it is a 2,200× order-dependent BLOW-UP (width over 2^m keys, depth pinned at 3), not a
divergence (§R8.0 kept both versions on purpose). Loop/Depth.lean: chain-depth instrument (`--depth`; third counter
`maxdkey` = the theorem's R; round 5's guard/carrier counters are NOT it) + `terminates_of_chainRun` (depth ≤ D ∧
dequeue-key draws ≤ R ⇒ Terminates at n·D·(2^m·R)^D); `ChainRun` is a HYPOTHESIS (L-a bridge from step not proved).
Census 2,301,195 segments / eight groups: D ≤ 4, R ≤ 11, user programs 96.8%, stdlib 15,377/15,377. Hunt 11,514
runs, zero candidates. Seeds NP01.json/GU05.json tracked — GU05@base0 = 267 s in the compiler and TestLoopTrace
enumerates every seed at bases 0,7,41,300,1234,65537 with a timeout = FAILURE → must move GU05 out of seeds/ (e.g.
seeds/slow/) or cap before commit; plan L5 row + README NOT updated by the round (reviewer to confirm). Orchestrator
re-verified build 856 / looptrace 1662 / Audit 3742/0 / no sorry. REVIEWER LAUNCHED (fresh Opus, "Round-8 review"
section of L5-REVIEW.md, scratch tmp/review-L5r8/). Implementer's background jobs may still run: GU05 base 4 at
2,400 s, reduce8.py → GU05MIN.json. Commit only on the user's word.
TestLoopTrace with NP01 included and GU05 EXCLUDED (`-Dsatterm.seeds=<copy without GU05>`): 714 solves (19 seeds × 6
bases + 600 generated), 714 agree, 10.4 s, 3/3 properties pass (2026-09-05 20:56). So NP01 can stay in seeds/; GU05
must not be enumerated by the test.
ROUND-8 REVIEW (2026-09-05): FIX-THEN-ADVANCE — maths/instrument/census reproduce exactly; Y-A the hunt never measured
the theorem's R (`maxdkey` absent from agg8.py; where present 18, reviewer re-runs 26/31; GU05@base2 maxcremint=12) →
"zero candidates" is a coverage artefact; Y-B "width not depth" refuted at fuel 1000 (depth 4, maxdkey 14) → BOTH
factors still look unbounded; Y-C GU05 breaks core/test (bases 7/300 HANG at 600 s; one -Xmx1g child JVM, 180 s
cap) → move to seeds/slow/; Y-D base 4 = REJECTED by the HARNESS's 100,000-id supply window recycling
(panic: reinstantiated type), so base 4 unresolved and 11/25 bases have no verdict — widening Replay.supplyAt is a
Scala follow-up; Y-E --depth/--cycle don't model labelCheck refutation (6 incomplete/ segments scored SOLVED); Y-F
plan row/README not updated; Y-G..J arithmetic/prose. Reviewer's round-9 order: L-a first, then hunt R, then depth
generator; GU05/GU05MIN → PERF-ROADMAP. Corrections SENT to the round-8 implementer (resumed).
ORCHESTRATOR'S POSITION (told the user 2026-09-05): rounds 7–8 drifted from proving to profiling (run-level
hypotheses); recommend stopping measurement rounds: prove SOUNDNESS (derived partitions entailed; rejection ⇒
unsat) as the theorem, ENGINEER termination (budget + structural mint-bound design change aimed at the 2^m width
factor, proved on the model, trace-tested, perf-measured on gu05). User's decision pending.
USER'S DECISION (2026-09-05): "prove soundness, then iterate on engineered termination guarantees/performance."
NEXT STAGE = S1 SOUNDNESS, brief written at `tracker/loopmodel/briefs/brief-S1.md` (pure proving: (A) output
soundness = NoLoss (sys s₀) (sys s_final) for all five branches — only the `concrete` branch's NoLoss is missing
(`StrictStep.step_noLoss` covers NonConcreteStep); (B) rejection soundness = every death site's loop-level extraction
+ explicit NonRefutation list; `solve_sound` from buildQueue; scope limits Subst.reduce / labelClash / Loc; report
S1-SOUNDNESS.md). LAUNCH ONLY after round 8's corrections land and are COMMITTED (user's word) — the plan file is
being edited by the round-8 implementer, so the S1 plan section is added by the orchestrator at launch time.
After S1: a DESIGN stage for engineered termination (budget + structural change at the 2^m width factor, proved on
the model, trace-tested, perf-measured on gu05/GU05MIN); Replay.supplyAt window widening is a Scala follow-up.
AUTONOMOUS MODE (user, 2026-09-05 evening: "I want this to be autonomous: I am stepping away"). Orchestrator's
reading, stated to the user: run the whole loop without waiting — verify, review, apply findings, COMMIT each
reviewed+green stage on the branch (no push, no merge), launch the next stage. Hard boundaries kept: never commit
red; never commit an unreviewed stage; no flag default flips / compiler behaviour changes adopted without the user
(a design stage ships its change behind a flag default OFF, proved + trace-tested + perf-measured, adoption waits);
no Scala edits by L5/S1 agents; disk/Lean constraints unchanged. Sequence: round-8 corrections → verify → move
GU05 to seeds/slow/ → TestLoopTrace → commit round 8 → add S1 plan section → launch S1 (brief-S1.md) → verify →
reviewer → fixes → commit S1 → design stage brief (engineered termination: budget + structural change at the 2^m
width factor) → implementer/reviewer → commit behind a flag → REPORT to the user. If this session dies (power),
a new orchestrator resumes from here; agents of a dead session cannot be resumed — re-launch with brief + report.
ROUND-8 REVIEW DONE (2026-09-05, fresh reviewer, `L5-REVIEW.md` "Round-8 review"): verdict
FIX-THEN-ADVANCE. Everything reproduced (856/3742-0/1662, 49 declarations, 22 verbatim, 342
residue rows x 18 fields with 0 differences, the 2,301,195-segment differential); the retraction
and the ChainRun-is-a-hypothesis honesty called exemplary. Ten findings, ALL APPLIED, old-for-new
in `L5-TERMINATION.md` "Round 8 -- post-review corrections" + `R8.7`. The three that change what
the round concludes: (Y-C) `TestLoopTrace` runs every seed in `seeds/` x 6 bases + 600 generated
in ONE -Xmx1g child under a SINGLE 180 s cap and a timeout is a FAILURE -- two of those six bases
exceed 600 s on GU05, so `GU05.json` and `GU05MIN.json` MOVED to `tracker/repro/satterm/seeds/slow/`
(`listFiles` is non-recursive, no code change; orchestrator already ran core/test without it:
714 solves, 714 agree, 3/3 pass); (Y-A) the hunt never measured the theorem's own R -- `maxdkey`
was in neither the growth table nor the candidate test and present in only 2,040 of 11,514 rows --
so "zero candidates" was a coverage artefact: R reaches 31 in the hunt against a corpus 11, and
20 on the round's own tracked seed, every such run SOLVED on the compiler; (Y-B) "the depth
reaches 3 and does not move again" was refuted by the round's OWN log (fuel 1000 -> depth 4), and
GU05 at base 2 gives depth 5 / maxcremint 12 / maxdkey 19. Also (Y-D) base 4 is UNRESOLVED, not
"cut off short": it ends `REJECTED ... panic: reinstantiated type 121` at ~692 s because
`Replay.supplyAt` gives a 100,000-id `Supply` window -- widening it is a Scala follow-up for the
orchestrator; and (Y-E) `--depth`/`--cycle` do not model `checkLabel`, so 6 of `incomplete/`'s 7
P2-only solves score SOLVED though the compiler refutes them (headline moves 0.01 points).
CORRECTED ROUND-9 ORDER: L-a first (make `ChainRun` a statement about `step`, not the
instrument), then hunt R, then a generator built to drive D -- NOT the round's original
"L-c first", which rested on the two false claims above. Deliverables Y-F done:
`LOOP-MODEL-PLAN.md` L5 row, a `### L5 round 8` section in `tracker/lean/README.md`, and the
eight-group 96.81 % beside the seven-group 97.39 % in `ROW-CONSTRAINT-STATE.md`.
Round 8 COMMITTED `bd348ab` (2026-09-05, autonomous mode; verified 856/1662/3742-0, TestLoopTrace 714/714 with NP01
in seeds/ and GU05/GU05MIN in seeds/slow/). S1 plan section + status row added; S1 implementer launching (Opus,
briefs/brief-S1.md, report S1-SOUNDNESS.md). Start figures for S1: 3742 theorems / 856 jobs / looptrace 1662.
