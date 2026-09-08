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
Orchestrator commit fde996a (2026-09-05): S1 plan section/row + brief, harness SupplyWindow 2^30, PERF-ROADMAP P10. S1 implementer RUNNING.
D1 brief DRAFTED at briefs/brief-D1.md (Part A: budget spec + dequeue-policy experiments on the MODEL, design doc, STOP; Part B: flagged Scala change default OFF with gates + perf; adoption = user). Finalise after S1's outcome; launch after S1 is committed.
S1 REPORTED (2026-09-05 night, uncommitted): OUTCOME P-. (B) rejection soundness COMPLETE (`run_rejects_unsat`; every
death a refutation except the skolem message; two panics proved unreachable). (A) output soundness `run_noLoss`
holds UNDER `SSat (sys s₀)`: unconditional NoLoss at the `concrete` branch is FALSE — makeConcrete deletes a bare
row `v <- ((|C|))` with C ⊊ fs and emits nothing (`step_noLoss_or : NoLoss ∨ ¬SSat`). OPEN QUESTION = can the
shipped compiler ACCEPT an unsatisfiable input through that hole (false acceptance)? Two probes caught by
ensureSuperset / labelCheckEarly; LabelAlgo proves the label check SOUND not COMPLETE, so it does not close the
hole. New Loop/{Sound,Reject,Solve}.lean; build 859 / Audit 3804-0 / looptrace 1662 (orchestrator re-verified: see
s1-verify.log). S1 REVIEWER LAUNCHED (Opus; report S1-REVIEW.md; main job = a SOUNDNESS HUNT for a false
acceptance with the per-label sat oracle, compiler replay of any candidate, and an attempt at the closing theorem).
If a false acceptance is CONFIRMED: it is a compiler soundness BUG -> a fix stage (like B1) before D1.
S1 REVIEW (2026-09-06 ~00:30): FIX-THEN-ADVANCE, nothing wrong in the Lean, but the hunt answered the open question
YES: the SHIPPED COMPILER ACCEPTS UNSATISFIABLE ROW SYSTEMS — 10 seeds confirmed SOLVED with a substitution that
violates an input constraint (review-S1/MIN1.json: saturation incompleteness, 20/20 bases; MIN2.json: THROUGH the
bare-row deletion, 4/20 bases; U11/u00857 survives even labelClash-on-saturated-set). Hunt: 11,048 unsat
label-check-passing seeds, ~27k model runs, 1,166 model false acceptances / 665 seeds, 0 unsound rejections. The
S1 theorems hold on every witness (the output is unsat too) — they are right and are NOT the property the type
checker needs (accepted ⇒ satisfiable = refutation completeness). S1 implementer RESUMED with the framing
corrections (outcome → BUG; seeds to seeds/unsat/; Z-3..Z-11). S2 LAUNCHED (Opus, briefs/brief-S2.md): Part A in
worktree ermine-scala-wt-s2 (branch row-sound): (i) makeConcrete requires C = fs at a bare definition, (ii)
checkLabels on the saturated set, (iii) a COMPLETE per-label decision (unit propagation + case split) on the live
input — ALL behind flags default OFF; gates: flags off byte-identical; flags on: unsat seeds 0 SOLVED, satisfiable
seeds unchanged, corpus list of newly rejected programs (each = an ill-typed program accepted today), P1 perf.
STOP after Part A; Part B (Lean mirror + `solve_noFalseAccept` theorem) after S1 is committed. The S2 plan section
is added by the orchestrator after S1's corrections land (plan file in use by the S1 agent). Then: S1 commit →
S2 Part B → S2 reviewer → S2 commit (flag default OFF) → D1. ADOPTION of the fix's default = the USER's decision;
it is the first thing to put in front of them.
S1 COMMITTED `5c08363` (2026-09-06, autonomous mode; corrections applied; verified 859/1662/3804-0; outcome BUG).
Plan: S2 + D1 sections and status rows added (uncommitted, goes with the S2 commit). S2 Part A RUNNING in
worktree ermine-scala-wt-s2; on its report: check the gates + corpus list, then give the go for Part B (Lean in
the main tree, now clean), then an Opus reviewer, then commit with flags default OFF, then D1.
S2 PART A DONE (2026-09-06 ~03:00, worktree ermine-scala-wt-s2, report there: S2-FIX.md/S2-DESIGN.md): flags
`-Dermine.rowSound` (+ .bare/.saturated/.decide/.budget=200000), all default OFF; "the input" = queue partitions +
SubstEnv facts of mentioned variables (closed transitively). Gates OFF: core/test 913/914, TestLoopTrace 714/714,
corpus row trace byte-identical (2,355,430 segments, 8 groups), 20 seeds × 10 bases byte-identical, .ei 0/185
differ. Gates ON: seeds/unsat 120 runs 0 SOLVED (labels as predicted); reviewer's 665-seed population 404 → 0
SOLVED (667 distinct refutations, 0 satisfiable at the named label under an independent oracle); 38,400
satisfiable hunt runs all SOLVED, substitutions byte-identical; CORPUS LIST OF NEWLY REJECTED PROGRAMS = EMPTY (0
verdicts move; one message moves on already-failing shouldfail/inf04); cost +0.9% within noise, the decision
0.69 s over 2.36M solves, per-solve max 3.7 ms. PART B RELEASED (message sent): apply the 3-file diff to main,
Lean mirror + Decide theorems (sound + COMPLETE) + `solve_noFalseAccept`, L2 differential flags ON, TestLoopTrace
flag forwarded, report/README/state/plan row. Then an Opus reviewer, then commit (flags OFF). USER DECISION
QUEUED: flip `ermine.rowSound` default ON (the corpus shows zero behaviour change on valid programs and no cost).
S2 PART B DONE (2026-09-06 ~07:30, main tree, uncommitted): Scala 3-file diff applied on main (+ senv record +
TestLoopTrace flag forwarding, 8 new model --flags tokens); Loop/Decide.lean (327) + Loop/NoFalseAccept.lean
(1,025): `labelDecide_sat_ssat` (COMPLETENESS), `labelDecide_refuted_unsat` (soundness), `solve_noFalseAccept`
(flags on ∧ budget not cut ∧ verdict ≠ REJECTED ⇒ SSat of the live input = queue + env facts); L2 differential
flags ON 2,355,428/2,355,428 agree (0/0/0), OFF 2,355,430 unchanged; TestLoopTrace 714/714 both ways; build 861 /
Audit 3888-0 / looptrace 1664; core/test 913/914. Gaps stated: no end-to-end kernel rfl (Json.checkLabel WF
recursion), pass-based vs worklist propagation (same verdicts), layer (ii) cited-sound only, Subst.reduce
unmodelled, opaque env bindings skipped. Orchestrator verification running (s2-verify.log). S2 REVIEWER LAUNCHED
(Opus; report S2-REVIEW.md; incl. a false-REJECTION hunt under the flag and an adoption recommendation). Then
commit S2 (flags default OFF) → D1 launch. USER DECISION QUEUED: flip -Dermine.rowSound default ON.
S2 REVIEW (2026-09-06 ~08:00): ADVANCE — everything reproduced (861/3888-0/1664; TestLoopTrace 714/714 both ways;
120/120 unsat runs rejected; 404→0; corpus verdicts unchanged; 0 CONFIRMED FALSE REJECTIONS in 6,300+ runs incl. a
case-split-forcing generator). Findings: V-1 the chain to run_noLoss only in prose (~15 lines of Lean); V-2 the
env-fact path has no tracked gate (one corpus solve); V-3 .budget not forwarded by TestLoopTrace; V-12 per-label
budget without a per-solve cap and exhaustion invisible; V-4..V-10 prose/numbers (core/test 912/914 on the
reviewer's run: a writers date/TZ flake). BONUS: a THIRD shipped false-acceptance mechanism via a VarT link in the
long-lived SubstEnv (SOLVED today, REJECTED with the flag on). ADOPTION RECOMMENDATION: not yet — (1) tracked env
gate, (2) per-solve budget + visible exhaustion signal, (3) the chain in Lean; then yes; layers (i)+(iii) alone buy
the whole measured benefit (layer (ii) contributed 0 corpus records, cited-sound only). S2 implementer RESUMED to
close V-1..V-13 + the three prerequisites; then orchestrator re-verify → COMMIT S2 (flags OFF) → D1 launch.
S2 COMMITTED `3991a58` (2026-09-06 ~05:20, autonomous mode; orchestrator re-verified 861/1664/3898-0, TestLoopTrace
714/714 both ways, env gate 9 cases shipped 4 differ / flag ON 0 differ, ENV-LINK shipped SOLVED 5/5 / flag ON
REJECTED at l0). USER DECISION QUEUED: flip `-Dermine.rowSound` (or `.bare`+`.decide` only) default ON — the
reviewer's three prerequisites are now met. D1 LAUNCHING (Opus, briefs/brief-D1.md finalised at 3991a58): Part A on
the model only (draw budget spec + `budget_terminates`/`budget_never_accepts`; dequeue-order policies vs
GU05/GU05MIN/tracked seeds/eight-group corpus; design note D1-DESIGN.md; STOP). Part B (flagged Scala change) only
on the orchestrator's go after Part A's report.
D1-A REVIEW (2026-09-06 ~11:30): ADVANCE — all load-bearing numbers reproduced (smallcanon GU05 414 dequeues / 306
draws at every base; only 134 of 2.3M segments change draws, 0 change verdict); T-1 budget reset must be at the
loop's entry thread-locally (RowTrace.withSite is a no-op without -Dermine.rowTrace); T-2 smallcanon needs a
finger-tree measure component (or scan) and must not displace rhs.hashCode (findRHS/contains/insert range-split on
it); T-3 dequeuePol_none unproved; T-4..T-7 prose (canon/fifo SEVEN segments short; canon −4.0%/+1.49% on the common
population; concfirst changes one verdict); T-9 diagnostic wording; T-13 budget value by compiler measurement,
flags coupling; T-14 extra gates (.ei with policy ON, env gate, smokes, perf ON, per-solve draw equality
compiler vs model). Recommendation: implement smallcanon + budget together, default OFF. Implementer RESUMED:
Phase 1 (T-3 Lean + prose, main tree) → orchestrator commits D1-A → Phase 2 Part B Scala in worktree
ermine-scala-wt-d1 (branch dequeue-policy), Lean mirror in main only after "D1-A committed" → Part B reviewer →
commit (flags OFF). Adoption of smallcanon/solveBudget AND rowSound = user's decisions.
D1-A COMMITTED 93e9454 (2026-09-06); Part B RUNNING in worktree ermine-scala-wt-d1 (branch dequeue-policy); Lean mirror in main released by message; canonKey label order must be by Name triple, not slbl index (implementer's finding) — census re-run required.
D1 PART B IN PROGRESS (2026-09-06 afternoon): Scala in worktree ermine-scala-wt-d1 compiles; flags-OFF gates:
core/test 913/914, TestLoopTrace 714/714, L2 differential 7/8 groups agree (incomplete running), .ei queued; driver
runs unattended: .ei A/B/C, GU05 25 bases on the COMPILER under smallcanon, shipped control, GU05MIN, gu05 load
time, corpus at the budget, env gate, smokes, perf. Lean mirror written (Loop/PolicyReplay.lean new; Replay/Main
edits; TestLoopTrace.d1Opts forwards -Dermine.dequeuePolicy/-Dermine.solveBudget as --policy/--budget/--trace),
build deferred until the differential's binary is free. HARD REQUIREMENT SENT (user's soundness question):
re-PROVE step_refines_all / run_sat_all / run_noLoss / run_rejects_unsat (+ budget message in NonRefutation) and the
S2 chain against the flagged step before the D1-B commit; any policy for which a proof fails = a finding.
USER'S POSITION (2026-09-06): asked whether the improvements can reject valid programs — answer given: S2 cannot
(sound + no false rejections found), the policy cannot (same derived set), the BUDGET can in principle (resource
error vs hang; 60× headroom under the policy; coupled to the policy; both flags default OFF; the policy can ship
alone). Decision on flags is the user's.
D1-B FINDING (2026-09-06 ~15:00): the BUDGET transports completely (Loop/FlaggedSound.lean 303: runBud_noLoss /
runBud_sat_all / runBud_models / runBud_rejects_unsat with NonRefutationB = NonRefutation ∨ BudgetDeath;
runBud_not_rejected carries the S2 chain; stepP_done_dequeue: accept only on an empty queue; build 865 / Audit
3969-0 / looptrace 1670). The POLICY transport is NOT done: 22 theorems in 11 modules unfold the dispatch (1,221
proof lines) and must be re-run against DequeueShape — mechanical, all facts proved, not yet written. ORCHESTRATOR
DECISION: no D1-B commit until the transport is a theorem; D1-B implementer finishes the gates + writes a TRANSPORT
SPEC section in D1-CHANGE.md; then a FRESH Opus agent "D1-T" does the re-proof in a new module (Loop/PolicyStep.lean:
stepP_refines_all / runP_sat_all / runP_noLoss / runP_rejects_unsat + S2 chain for runSP), originals untouched;
then the Part B reviewer; then commit (flags OFF). Gate 3 CLOSED: L2 differential flags OFF 2,355,430/2,355,430.
D1-T brief written at briefs/brief-D1T.md (2026-09-06 ~16:00): the policy transport in a new Loop/PolicyStep.lean from D1-CHANGE.md §5's spec; LAUNCH (fresh Opus) only after D1-B reports done (shared Lean tree; never 'lake build looptrace' from D1-T). Then Part B reviewer over D1-B + D1-T together, then commit (flags OFF).
D1-B GATE RESULTS (2026-09-06 ~11:00): GU05 on the COMPILER under smallcanon: 1,093 draws at EVERY one of 25 bases,
≤ 2.4 s each (shipped: 743 / 1,091 / 47,317 draws at bases 2/1/0, 128 s at base 0); GU05MIN SOLVED 25/25 at 256
draws. gu05 load time unchanged; corpus at solveBudget=20000 limit-hits=0; env gate identical; repl/lsp smokes
PASS. TWO FINDINGS: (1) .ei is NOT byte-stable at a fixed configuration (published constraint lists print in Set/
hash/id order) → gate compared up to order (einorm.py): OFF 180/181, policy ON 173/181; six interfaces exist only
under the policy (incomplete/gu05, gu06, gu08, gu10, np01 — likely the batch sweep's 180 s cap; per-file check
requested). (2) BLOCKING: compiler 1,093 vs model 306 draws on GU05 — both base-invariant, so the two smallcanon
implementations differ (canonKey list-order bug found+fixed, gap remains); the differential under the policy must
localise the first diverging dequeue; until green, NEITHER number is "the" policy figure. Implementer nudged to
continue; D1-T waits for its report.
D1-B GAP CLOSED (2026-09-06 ~12:00): compiler = model on GU05 under smallcanon — 306 draws at EVERY one of 25 bases
(shipped: 743–47,317; 155× reduction of the maximum on the compiler). Cause of the phantom "fix had no effect": the
driver ran gates after a FAILED compile (stale classes) — lesson recorded; the real bug was canonKey's tuple
prefix-order vs the model's sentinel order at equal arity. Arity = |abstr| + [conc nonempty]. removeOne preserves
survivor order. Remaining D1-B gates running unattended (eight-group differential under the policy, firing-budget
differential, draw equality, TestLoopTrace both flags, per-file OFF/ON loads of the five incomplete/ modules, .ei
control, perf). D1-T LAUNCHED (fresh Opus, briefs/brief-D1T.md) in main's Lean in parallel: Loop/PolicyStep.lean,
`lake build -j2 Rowpartition` only, never looptrace. Then: one Part B reviewer over D1-B + D1-T → commit (flags
OFF). Both agents told to coordinate on Rowpartition.lean.
D1-T DONE (2026-09-06 ~13:00): Loop/PolicyStep.lean 2,373 lines / 84 declarations, Audit 4059-0, build 866: the
transitive closure was 41 declarations (not 22) + five policy forms of the step predicates; stepP_refines_all,
stepP_noLoss_all, stepP_died_refutes, runP_sat_all/noLoss/models/ssat_iff/rejects_unsat, runP_solved_saturated
(uses stepP_done_dequeue in the .solved case), runSP_* incl. runSP_rejects_unsat with NonRefutationB and
runSP_not_rejected, solveP_noFalseAccept / solveP_accepted_faithful; NO policy broke any theorem; originals
RECOVERED from the transported forms at pol := .shipped (anti-weakening); report D1-TRANSPORT.md (= D1-CHANGE §6).
GAP → D1-T ROUND 2 (running): termination under a budget was only for run/runBud (shipped order); transporting
round 7's measure argument to stepP → budgetP_terminates for runSP. D1-B: eight-group differential UNDER THE
POLICY 2,355,430/2,355,430; draw equality exact (54,199/54,199); the five incomplete/ interfaces are a REAL
completion (gu05 never finishes in the .ei chunk under the shipped order at the id base its predecessors leave;
2.08 s under smallcanon; alone, both settings ~16-17 s); TestLoopTrace with flags forwarded FAILS on a one-line
Main.lean seed-path `--trace` bug (fix authorised; looptrace rebuild only after "D1-T done"); firing-budget check
on gu05 queued; .ei control + perf running. Then D1-B applies the Scala diff to main, folds D1-TRANSPORT into
D1-CHANGE §6, fixes FlaggedSound §SS5 note → Part B reviewer over D1-B + D1-T → commit (flags OFF).
D1-T ROUND 2 DONE (2026-09-06 ~14:00): Loop/PolicyTerm.lean 1,127 lines / 54 declarations — round 7's measure
argument transported to stepP for EVERY policy (measure4 reused verbatim; ReachesP threads Aux): terminatesP_of_
drawsAtMost, vocFixedP_terminates, drawnP_unbounded_of_not_terminatesP, budgetP_terminates (needs b ≠ 0: runSP
treats budget 0 as OFF) + recoveries at pol := .shipped; build 867 / Audit 4112-0 (orchestrator re-verified).
Open for EVERY order incl. shipped: an a-priori fuel number (dequeues per draw unbounded). D1-B given the go: rebuild
looptrace, TestLoopTrace both flags, FlaggedSound §SS5 note, finish gates, apply Scala diff to main, fold
D1-TRANSPORT into D1-CHANGE §6, state file D1 section, plan/README, report → Part B reviewer (over D1-B + D1-T)
→ commit (flags OFF).
D1-B DONE (2026-09-06 ~12:20): the worktree's Scala diff is APPLIED TO MAIN (Constraints.scala +231/-8,
RowTrace.scala +16/-1, TestLoopTrace.scala +33/-7; git apply clean, files byte-identical to the worktree's;
Rowpartition.lean re-read and NOT touched — it carries both agents' import lines). Main tree re-gated:
core/compile + core/test:compile green; core/test 913/914 (the known TestConstraints failure, unmoved); TestLoopTrace 714/714 3-of-3 at ALL THREE settings (OFF, policy,
policy+budget) after the child-JVM forwarding fix (setD1 on the child's command line — the model had been
running the policy while the compiler ran shipped, 419/714 mismatches, a silent failure mode). Remaining gates
closed: firing budget on incomplete/gu05 (budget 0 → imports in 0.41 s, 54,235/54,235 agree, rejected=0;
budget 20 → REJECTED with the resource-limit diagnostic at gu05:62:1, 54,235/54,235 agree, rejected=1 — the
model agrees on the firing itself); corpus at solveBudget=20000 under the policy inert (bugs 54,235, guide
54,244, limit-hits=0); .ei with einorm2.py: control 181/181 (ZERO noise floor), OFF vs main 181/181, OFF vs
policy 176/181 + 6 policy-only → the policy is INTERFACE-AFFECTING; perf-bench batch alternated twice OFF
13.63/13.68 s vs ON 13.42/13.55 s = no measurable cost (PERF_MAX_LOAD raised to 6.0: the desktop's own load
never falls below 1.5 and a batch run leaves it at ~4.3; OFF/ON comparison sound, absolutes not comparable
with quiet-machine numbers). Docs updated in main: D1-CHANGE.md (1,347 lines; §6 = D1-TRANSPORT folded in,
D1-TRANSPORT.md replaced by a 9-line pointer; §7 = the application to main), ROW-CONSTRAINT-STATE.md dated D1
section, LOOP-MODEL-PLAN.md D1 Part B row + narrative, tracker/lean/README.md (compiler side + FlaggedSound
line count corrected to 267). NO COMMITS; both flags DEFAULT OFF. NEXT: the Part B reviewer over D1-B + D1-T.
D1 PART B DONE (2026-09-06 ~17:30; all in MAIN, uncommitted, flags default OFF): gates OFF: core/test 913/914,
TestLoopTrace 714/714, differential 2,355,430/2,355,430, .ei 181/181 identical; ON: GU05 on the compiler 306 draws
at all 25 bases (~1 s; shipped 743..47,317 / 128 s), GU05MIN 256×25, differential under the policy
2,355,430/2,355,430, TestLoopTrace 714/714 at OFF/policy/policy+budget (child-JVM forwarding fixed), firing budget
on gu05 rejected at budget 20 with the diagnostic and the model agreeing on the firing, draw census identical,
smokes PASS, perf no measurable cost (load guard overridden to 6.0; comparison alternated). FINDINGS: .ei not
byte-stable (compared up to Set order, control residue 0); the POLICY IS INTERFACE-AFFECTING: 5 signatures change
TEXT (ChartsExample.stackedPair, GridExample.stackedBarChart, incomplete/TargetList.restrictTo,
incomplete/RunCalibration.valueAsOf, Relation.lookbackJoin) and 6 interfaces exist only under the policy (gu05 etc.
now finish) — THE REVIEWER MUST DECIDE whether the five are equivalent types printed differently (residual
constraint form / variable naming) or genuine differences. Orchestrator verification running (d1b-verify.log),
then the Part B reviewer (over D1-B + D1-T), then commit (flags OFF). Adoption: user; weigh the interface finding.
ORCHESTRATOR VERIFIED D1-B ON MAIN (2026-09-06 12:29): build 867 / looptrace 1670 / Audit 4112-0 / no sorry;
TestLoopTrace 714/714 at OFF, policy, policy+budget (forwarding printed); GU05 under the policy 306 draws at bases
0–2, ≤ 1 s. D1-B REVIEWER LAUNCHED (Opus; report D1B-REVIEW.md; CENTRAL QUESTION = are the five changed signatures
equivalent types printed differently or genuine differences; plus the anti-weakening check of D1-T, the Scala line
by line, gates re-run, substitution comparison under the two orders on all seeds + a 500-seed hunt; two
recommendations: commit verdict, and adoption of smallcanon/budget and of rowSound). Then commit (flags OFF).
D1-B+D1-T REVIEW (2026-09-06 ~14:30): FIX-THEN-ADVANCE — no defect in Scala or Lean; all numbers reproduced (49
transported statements 0 weakenings; 158 new declarations 0 non-standard; differential under the policy
2,355,430/2,355,430; hunt 600 seeds × 3 bases: 1 verdict change = a shipped-side timeout). CENTRAL QUESTION
ANSWERED: the five signatures are alpha-equivalent residuals (three identical up to existential names; two differ
by a vacuous kind binder that also flips between runs at the SHIPPED configuration under the parallel loader) —
no different type; residue is Subst.reduce naming + printer, unmodelled. NEW U-0 (HIGH): smallcanon ACCEPTS
unsat MIN2/FALSE-ACCEPT-2 at 10/10 bases vs shipped 2/10 (refutation completeness is order-dependent; theorems
hold) — rowSound removes it entirely (all seven witnesses refuted 10/10 under both orders). U-1..U-12: .ei floor
via the parallel loader is NOT zero (1/152), deterministic loader OFF-vs-ON 2/152; einorm2.py artefacts; P10
un-tick; census 83/84; NO .ei CACHE KEY RECORDS THE FLAGS (U-6); bindcmp.sh broken; budget footgun reproduced
(20,000 at the shipped order rejects satisfiable GU05 at base 0). RECOMMENDATIONS: commit this stage flags OFF
= YES; adopt smallcanon = YES but ONLY TOGETHER WITH rowSound; budget NEVER alone (20,000 under the policy
defensible, ~56 s ceiling; 5,000 tighter); adopt rowSound before or with the policy. Corrections SENT to the D1
implementer (incl. structural: budget ignored unless the policy is on; flags in the .ei fingerprint).
Then orchestrator verify → COMMIT D1-B (flags OFF) → REPORT TO THE USER with the adoption decision.
D1-B POST-REVIEW (2026-09-06 ~15:30), verdict FIX-THEN-ADVANCE (loopmodel/D1B-REVIEW.md, 763 lines; no defect
in the Scala or the Lean, every re-run number reproduced): all findings CLOSED, D1-CHANGE.md section 8 carries
old -> new. THE FINDING THAT DECIDES ADOPTION is the review's own U-0: at the shipped rowSound default the
policy STOPS REFUTING seeds/unsat/MIN2 and FALSE-ACCEPT-2 (8 of 10 bases rejected under shipped, 0 of 10 under
smallcanon; the model agrees, so it is the ORDER; no theorem is contradicted -- rejection soundness never
promised refutation completeness). Reproduced over all 7 witnesses x 10 bases x 2 orders x 2 rowSound settings:
with -Dermine.rowSound=true ALL SEVEN are refuted 10/10 under BOTH orders => the policy must not ship without
rowSound, and "zero verdict changes in 2,301,195 solves" is qualified (the corpus has no unsat input of this
shape). TWO CODE CHANGES: (1) the budget is now IGNORED unless a non-shipped policy is set (warning says so;
EFFECTIVE budget in the trace; mirrored in the model by Loop/Policy.lean's effBudget in polCensus/solveSeedP --
a DRIVER rule, no theorem statement moved); gate: gu05 at budget 20 under shipped LOADS, limit-hits=0, replay
54,235/54,235 rejected=0, while under the policy it still fires rejected=1. (2) U-6: +pol:/+budget: tokens in
GenRules.toString, byte-identical at defaults (nothing keys an .ei by that string -- stated as the open gap for
incremental adoption). INTERFACE FINDING RE-MEASURED with -Dermine.loadInSeries=true and einorm3.py (anonymise
before sort): floor ZERO at the BYTE level twice at each setting; OFF vs ON = 1 of 152 interfaces (GridExample,
two bindings) differing by ONE VACUOUS kind binder; all other residuals ALPHA-EQUIVALENT -> "five signatures
change text" withdrawn. Also: P10 un-ticked (U-4); axiom census re-run over 161 decls incl QOk.shape, 0
non-standard (U-5); the flags-OFF sin record has two new columns (U-7); bindcmp.sh fixed and RUN -- it catches
U-0 (U-8); lblKey now code POINTS on both sides (U-9); RowTrace doc comment (U-10); combine has no callers
(U-11); draws are the figure of record, wall clocks are ranges (U-12). Re-gated: build 867 / audit 4,115-0 /
looptrace 1,670, TestLoopTrace 714/714 x3, boot+top differential 146,872/146,872 OFF and under the policy,
fingerprint unchanged at defaults. NO COMMITS; both flags DEFAULT OFF. Recommendation carried forward from the
review: adopt rowSound first or with the policy, the policy second, the budget only with the policy.
D1-B + D1-T COMMITTED 82c982a (2026-09-06 15:45, autonomous mode; verified 867/1670/4115-0, TestLoopTrace 714/714 x3, MIN2 policy rsOFF 5/5 SOLVED / rsON 0/5, budget ignored at shipped with warning). Tree clean. NEXT = report to the user; the loop is at a natural stop: the user's decisions (rowSound default; smallcanon default with rowSound; budget value) gate everything further.
USER'S DECISION (2026-09-06 17:00): "Let's do 20,000" → "Full recommended set": ADOPT rowSound ON + dequeuePolicy=
smallcanon + solveBudget=20000 as defaults. A1 ADOPTION LAUNCHED (fresh Opus, briefs/brief-A1.md): flip defaults on
BOTH sides (compiler GenRules + model Flags), full gate set at the new shipped configuration with the old
configuration as the control (core/test, TestLoopTrace both ways, eight-group differential, corpus verdicts with
every change explained, .ei sweep up to Set order with the deterministic loader + 0 weaker, seeds incl. unsat 0
SOLVED and GU05 306×25, hunt seeds 0 limit hits, perf, smokes, docs incl. an ADOPTED section in the state file).
Then an Opus reviewer, then COMMIT (this is the first default flip made in autonomous mode — with the user's
explicit word). Rollback = -Dermine.rowSound=false -Dermine.dequeuePolicy=shipped (budget then off).
A1 DELIVERED 2026-09-06, GREEN, UNCOMMITTED. Report `tracker/loopmodel/A1-ADOPTION.md`. Defaults flipped on BOTH
sides: `-Dermine.rowSound=true`, `-Dermine.dequeuePolicy=smallcanon`, `-Dermine.solveBudget=20000`; model `Flags`
rowSound* default true, `Loop/Main.lean` `policyOf`->smallCanon and `defaultBudget=20000`, new `--flags=norowsound`
token; `TestLoopTrace` forwards any DEPARTURE from the shared defaults in either direction. New fingerprint
`cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000`; rollback
`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` gives back the pre-adoption string byte for byte.
Gates: build 867 / Audit 4116-0 / looptrace 1670; core/test 913/914; TestLoopTrace 714/714 at BOTH configurations
(the OLD one forwarded as `--flags=norowsound --policy=shipped`); L2 differential 2,355,428/2,355,428 NEW and
2,355,430/2,355,430 OLD; corpus verdicts 0 changes (deterministic loader, floor 0, 9 blame-clause messages in
shouldfail/); .ei 187 both sides, byte-identical floor at each configuration, 0 signatures weaker, and ATTRIBUTION:
`rowSound` changes NOT ONE BYTE, all four moved interfaces are the policy's; unsat witnesses 44 SOLVED of 70 -> 0;
run.sh env differ=4 -> 0; GU05 306 x25, GU05MIN 256 x25; PANIC3 100/100; 11,520 hunt runs all SOLVED with no
concrete row moved and the draw budget never fired; perf unmoved (sign flips); repl/lsp smoke PASS; both new deaths
render as ordinary diagnostics in CLI, REPL and LSP. NO THEOREM STATEMENT CHANGED (`({} : Flags)` no longer means
the shipped configuration, so NoFalseAccept's three "the shipped loop accepts" theorems name it explicitly via
`shippedFlags`, and `min2_loop_rejects_at_defaults` is ADDED). Open, stated in the report §3: three
`incomplete/` residuals are NOT isomorphic (no type weaker, bodies identical); the .ei cache is still not keyed by
the configuration (measured: a stale stdlib closure IS read across the flip); the budget diagnostic still renders
at error severity; the model's json seed loader cannot read S2's `env` block. NEXT = reviewer, then commit.
A1 ADOPTION REPORTED GREEN (2026-09-06 ~20:20, uncommitted): defaults flipped both sides; fingerprint
`cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000`; rollback
`-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` (byte-identical to the pre-adoption string; one NOTE line
about the ignored budget). Gates: Lean 867 / 4116-0 / 1670; core/test 913/914; TestLoopTrace 714/714 both
configurations; differential 2,355,428/2,355,428; corpus verdicts 0 changes (9 shouldfail files blame a different
clause/field); unsat witnesses 0/70 SOLVED (old 44/70); env differ=0; GU05 306×25, GU05MIN 256×25; PANIC3 100/100;
hunt 11,520/11,520 both sides, budget never fired; .ei 187: 183 identical / 4 differ / 0 weaker — rowSound changes
NOT ONE BYTE, all four moved interfaces are the policy's; THREE bindings (incomplete/np01.inferredRestate,
RunCalibration.valueAsOf, RevenueShare.shareOfGroup) publish a DIFFERENT (theorem-equivalent) saturated set, not a
renaming — bodies identical, nothing weaker — REVIEWER TO CONFIRM EQUIVALENCE; perf unmoved; smokes PASS; the
batch chunk holding gu05 629 s → 11 s. Open: .ei cache not keyed by configuration (old-configuration interfaces
are READ at the new defaults — clear .ei once at adoption); budget diagnostic severity 1 in the LSP; the model's
json seed loader lacks S2's env block (ENV-LINK on the model). Lean: shippedFlags named explicitly in
NoFalseAccept.lean (+ min2_loop_rejects_at_defaults). Orchestrator verification running (a1-verify.log) → A1
reviewer → COMMIT (the default flip, with the user's explicit word "Full recommended set").
ORCHESTRATOR VERIFIED A1 (2026-09-06 21:33): 867/1670/4116-0; TestLoopTrace 714/714 at the new defaults and with the old configuration forced; MIN1/MIN2/SURV1/ENV-LINK 0/5 SOLVED each at the new defaults; GU05 306×3; NP01 SOLVED 5/5. A1 REVIEWER LAUNCHED (Opus; A1-REVIEW.md; settles the three saturated-set bindings' equivalence, re-runs the gates, judges the diagnostic severity for adoption). COMMIT on ADVANCE.
A1 REVIEW (2026-09-06 ~22:30): ADVANCE — commit the flip after doc corrections. Reviewer classified all 1,921 bindings: ONE genuine difference (RevenueShare.shareOfGroup, strictly MORE GENERAL = the hand-written shareOfGroupFull in Signatures.e; OLD entails NEW; no call site regresses); np01.inferredRestate alpha-equivalent, RunCalibration.valueAsOf equivalent (entailed extra constraint). Corrections R-1..R-9 (doc only: verdict column, weaker/more-general wording, CLEAR .ei ONCE instruction with paths, perf +2.2% median on the reviewer's 4 rounds, core/test 912/914 flake, inf02/inf05 wording, kind variable, budget parse note, diagnostic code follow-up) SENT to the A1 implementer. Then COMMIT.
A1 POST-REVIEW CORRECTIONS APPLIED (2026-09-06, docs only, no code, no re-gate, uncommitted). `A1-ADOPTION.md`
gains §6 "POST-REVIEW CORRECTIONS" (old -> new for R-1…R-9) and §A1.7 is rewritten: 30 of 1,921 bindings move --
27 renamings, 1 a renaming plus an ENTAILED constraint (`RunCalibration.valueAsOf`), 2 a bound KIND variable
(`GridExample`), and ONE genuine (`RevenueShare.shareOfGroup`), stated as ENTAILMENT: `OLD |= NEW`, `NEW |/= OLD`,
i.e. strictly MORE GENERAL, certified by the hand-written `Signatures.shareOfGroupFull` over the identical body at
BOTH configurations, and no call site regresses. `np01.inferredRestate` (two verbatim duplicate constraints; `rs
<-> rs1`), `RunCalibration.scaledRuns` and `SoftRelation.groupingDateDrilldown` are RENAMINGS, not differences. Also
corrected: core/test is 913-or-912 of 914 (TestInterfaceRoundTrip flake); perf is "a small 1-3 % cost, not
separable from this desktop's noise" (the reviewer's four alternated rounds put NEW slower every time, median
+0.30 s), not "the sign flips"; `inf02` moves a->b and `inf05` moves 23:18 -> 23:30; GridExample's is a bound kind
variable; `-Dermine.solveBudget=<not a number>` means 20,000; the budget diagnostic has no `code` field --
acceptable, follow-up filed in the report. `ROW-CONSTRAINT-STATE.md`'s ADOPTED section now OPENS with the R-4
instruction: `find . -name '*.ei' -delete` once after the flip (`core/examples/**`, `core/target/scala-*/classes/
modules/**`), because `.ei` is not keyed by the solver configuration. Plan row and `tracker/lean/README.md`
updated with the review verdict. NEXT = COMMIT.
A1 COMMITTED fe024a7 (2026-09-06 ~23:00): the three defaults are SHIPPED (rowSound ON, smallcanon, budget 20000). Tree clean. Agents stopped. PROGRAMME COMPLETE for the user's stated goals; open follow-ups: .ei cache key by configuration (clear .ei once at adoption), a-priori fuel number, budget diagnostic code, the model's json seed loader lacks S2's env block, worktrees ermine-scala-wt-{s2,d1,b1,loader,prof} still present (user's call to remove).
E-SERIES EXAMPLE CORPUS (user, 2026-09-06 23:00: "develop the examples directory even further … with background
agents … different under-exampled aspects of ermine … many examples of interesting generic helpers"). Import
census: examples import ~40 of ~160 stdlib modules. Machine: 12 cores / ~9 GB free → THREE concurrent
implementers max, one JVM each (-Xmx2g, 2 cores). RUNNING: E1 Wide/ (pivots, window functions, wide tables;
brief-E1.md — it ALSO wires corpus-run.sh/looptrace-corpus.sh/README for its group), E2 Algebra/ (Relation.e's
constrained helpers incl. joinWithDefault's `exists`, UnifyFields/RTree/Scan/Process, set ops, closures;
brief-E2.md), E3 Time/ (Date/DateRange/lookupLatest/nearestDate, Currency, Nullable, Math, aggregates, charts;
brief-E3.md). Common rules in brief-E-common.md (E2+ do NOT edit shared tooling; they record wiring lines; the
orchestrator wires all groups at the end). QUEUED when slots free: E4 Present/ (Layout.Chart/Writer/StyleGrid/
Fulcrum reports/Validation/Column/Magnitude/DrilldownList/Syntax.Selector), E5 Lang/ (Control.* monads/
functors/traversable, Data.Free/Cofree, Syntax.Do/Monad/Reader/Procedure, Either/Maybe/Validation, Parse,
String.Markdown/StringManip, Map/Tree/List.*, Type.*, IO/IO.CSV/File). Per group: an Opus reviewer, then wiring
+ commit. Reviews judge the examples as programs a user learns from AND as corpus (differential clean, census).
R1 LAUNCHED (2026-09-06 ~23:40; Opus researcher, briefs/brief-R1.md): Rose/Rω vs Ermine comparison memo → tracker/ROSE-COMPARISON.md; reading/writing only, no lake build (E1–E3 use the looptrace binary), scratch Lean via lake env lean only. Adoptable-idea candidates: canonical residual simplification via entailment-equivalence (fixes order-dependent .ei form, Signatures.e noise, cache-key gap), entailment-based call-site checking with labelDecide as oracle (the Ai README cost cliff), a formal correspondence theorem Ermine rules ⇔ Rose axioms.
S3 BRIEF WRITTEN (briefs/brief-S3.md: mkSimplified NormalPart.hashCode + tautology case; launch when a JVM slot frees after E1–E3). R1 memo COMMITTED 40f80aa.
E2 Algebra/ DONE GREEN (2026-09-07 ~00:40; uncommitted): 12 modules + 6 shouldfail + README; 28 helpers (89
partition constraints across 43 signatures vs the old corpus's 12/9); loads per file ≤ 1.25 s own time, batch 15.5
s; differential 151,993 segments 0/0/0; census: GENTLER than Ai (max draws 14, depth ≤ 2, key mints ≤ 1) but the
widest label set (26). STDLIB/LANGUAGE FINDINGS (to ticket after review): UnifyFields.unify1 cannot unify
differently-named schemas; join1's doc is wrong (it is joinBy {f}); a row variable in `[f1,f2]` relation-type
syntax is read as a LABEL; rowSound blame clause varies with the command line at a fixed field; NO REPL `render`
(Ai README wrong) — E1 built tracker/tools/sql-render.sh (SQLite route; cannot dump Mem); Ai README's
"does not finish" RUnion3+RUnion2 figure does NOT reproduce at either configuration. SHARED WIRING for the
orchestrator at the end: looptrace-corpus.sh groups + hoist arms; corpus-run.sh file lists + hoist arms;
examples README rows; scalacheck-binding/src/main/scala/TestSurfaceParsers.scala:81 `(files ?= 271)` → the new
total (every E-stage trips it; 315 at E2's run) + the "271 files" strings there and in TestStatementExtents.
E2 REVIEWER LAUNCHED (Opus, briefs/brief-E-review.md template, report E2-REVIEW.md). Slots: E1, E3, E2-review
running (3 JVM users) → E4 launches when one finishes, then E5, then S3.
E3 Time/ DONE GREEN (2026-09-07 ~01:30; uncommitted): 13 modules (34 helpers, 38 partition constraints/23 sigs;
Signatures.e 8 entailment proofs); all six stdlib as-of lookups exercised; differential 115,674 segments 0/0/0
(the model reproduces both row negatives down to the clause); census: max input row vars 42 (Ai 11), max input
partitions 24 (Ai 7), label table 31 (Ai 14) — yet cheaper per solve (max draws 13, depth ≤ 2, vocab-fixed
99.5%); budget never fired (1,538× headroom). RUnion cliff GONE at the adopted defaults (1.04→0.17 s; "does not
finish"→0.12 s). FINDINGS: `render` is NOT a defined term anywhere (Ai/*.e headers' recipe is not executable;
Layout.harness needs DB-backed Scanner+Runner); lookupLatest/nearestDate group by the DATE ALONE (multi-series
histories silently lose a series); nearestDate is dates→dates only; Relation.Op.dateDiff's result row is
UNCONSTRAINED (type-checks over a relation containing neither date); weightedMean forces one type; refutation
clause flips per-file vs batch (bucket01); bucketBy's inferred type quantifies over the class AsOp and an implicit
kind var — the compiler prints a type its parser cannot read back; Math/Vector cannot be lifted into an Op (no
rolling median/percentile as a column); no year/month/quarter op. Wiring lines in E3-EXAMPLES.md §6 (same shape
as E2's). E4 Present/ LAUNCHED into the freed slot (running: E1, E2-review, E4). Queue: E3-review, E5, S3.
E2 REVIEW (2026-09-07 ~02:00): FIX-THEN-ADVANCE — every measurement reproduced (151,993 segments 0/0/0; census
table line for line; 18/23 relations render via sql-render.sh with matching row counts; all 7 stdlib findings
CONFIRMED with probes: unify1 cross-schema impossible; join1 ≡ joinBy {f}; `[aid, c]` label trap; blame-clause
instability; no render; rename' misnamed not misdocumented; sumBy' vacuous constraint; Layout.Scan omits
removeK/removeBy/multiply). Fixes: prose (Customer360 19 cols; ManagerChains 4 doc errors; alg06 clause;
LedgerScan/Deduplication list unused helpers; duplicate `valued` across modules), §G3's heaviest-solve labels are
combine_Op (RUnion2) not joins — conclusion flipped; missed rightJoinWithDefault/unsafeRightJoin/partialLookup'/
`[| … |]` comprehensions/running total → follow-up Algebra/Comprehensions.e. SqlEmitter bug sharpened: flattens
a non-left-deep join tree without parentheses (`A JOIN B ON c1 JOIN C JOIN D ON c2 ON c3`). Best: Inventory
Snapshots, KeyDiscipline, Signatures; weakest: ManagerChains, LedgerScan, Deduplication. NOTE: someone (E1)
replaced TestSurfaceParsers' `files ?= 271` with `moduleFiles.size` — count property now passes. E2 implementer
RESUMED with the corrections + the new module. Running: E1, E4, E2-corrections. Queue: E3-review, E5, S3.
Ticket recommendations (E2-REVIEW §13): new TICKET-stdlib-findings.md + two additions to
TICKET-editor-and-solver-followups.md — orchestrator writes them at the end of the E-series.
E1 Wide/ DONE GREEN (2026-09-07 ~02:30; uncommitted; it ALSO edited corpus-run.sh, looptrace-corpus.sh,
core/examples/README.md (3-column table), TestSurfaceParsers.scala (`moduleFiles.size` replaces `files ?= 271`),
and added tracker/tools/{sql-render.sh,SqlRun.java,tsql2sqlite.py,wide-render-probe.*}): 10 modules (20–36
fact fields) + 3 shouldfail; 24 helpers, 85 partition constraints; reports publish 0 residuals (the pivot's
existential `i` minted and resolved); differential 114,844 + 55,775 segments 0/0/0; census bigger not deeper
(nvars 21, labels 46, draws 77 vs Ai 52; depth ceiling 3; vocab-fixed 99.64%); budget headroom 77/20,000;
RUnion cliff gone (bundled form 1.3–1.5 s on the very module Ai measured). FINDINGS: `render` undefined (no
concrete Writer ships); **Relation.Pivot.pivot and Relation.Predicate.all PANIC when forced** — `record#`
returns a MapView (Scala 2.13) that scalaRecord#'s `case Prim(t: Map[...])` cannot match; one-line fix at
Lib.scala:988 (NOT applied — a real runtime bug for a ticket/fix stage); window functions emit real SQL only on
the MS SQL emitter (others emit a TODO into the query); dumpQuery cannot dump Mem or lookupLatest's SqlLoad;
variadic melt / relation-level dynamic pivot inexpressible (no type-level fold over a row); `seq`/`currency`
collide with stdlib terms. E3 REVIEWER LAUNCHED. Running: E4, E2-corrections, E3-review. Queue: E1-review, E5,
S3, then a fix stage for the MapView panic.
E2 CORRECTIONS DONE GREEN (2026-09-07 ~03:30): 13 modules (+Comprehensions.e: all `[| … |]` clause forms, right
outer joins, running total twice), 33 helpers, .ei 146 partition constraints/51 sigs; differential 156,368
segments 0/0/0; census now MATCHES Ai on draws/depth (max draws 53, depth 3) — the "gentler" claim withdrawn;
runningTotal: 2 hand-written constraints proved equivalent to the compiler's 21 over 27 existentials (19 are
noise — the largest ratio in the repo). E1 REVIEWER LAUNCHED (covers E1's SHARED-FILE edits: corpus-run.sh,
looptrace-corpus.sh, examples README, TestSurfaceParsers moduleFiles.size, the sql-render tooling; and the
MapView pivot panic's scope + fix). Running: E4, E3-review, E1-review. Queue: E5, S3, pivot-panic fix stage.
COMMIT PLAN: after E1's review — one commit for E1 (incl. shared tooling) then E2 and E3 (their READMEs depend
on sql-render.sh), each after its review's fixes; then E4/E5 likewise; the orchestrator writes
TICKET-stdlib-findings.md from the confirmed findings at the end.
E3 REVIEW (2026-09-07 ~04:00): FIX-THEN-ADVANCE — all 8 stdlib findings CONFIRMED (dateDiff's wrapper has NO
signature → `Op r2 Int` with r2 free: a static guarantee silently deferred to run time, one-signature fix;
bucketBy unprintable: four AsOp existentials + forall {a}); three claims the DATA DENIES (MultiCurrencyPnl.unrated
always empty; ReadingHistory.asOfWithin 1 not empty; carriedCells wrong); five clashing top-level names
(banded/indexed ×3 modules); census corrections (draws max 16; per-key mints max 1, "4" was mint keys; band4's 42
vars are a definition-site lattice, call sites peak at 11/7); DateRange never used (the one coverage gap). E3
implementer RESUMED with the corrections. Running: E4, E1-review, E3-corrections. Queue: E5, S3, pivot-panic fix.
E4 Present/ DONE GREEN (2026-09-07 ~05:00; uncommitted): 9 reports (15–30 fields) + 6 shouldfail + Signatures.e;
34 helpers (11 with partitions, 6 with existentials); differential 126,260 + 59,493 segments 0/0/0; census: max
draws 225 — ALL Resolution, zero splits (new shape) at a Layout.Validation call site; PER-KEY MINTS 12 (first time
the round-7/8 max of 11 is exceeded; no theorem violated — R is a hypothesis; headroom 89×); depth ≤ 2; vocab-fixed
99.81%. FINDINGS: the WRITERS EXIST in sibling project ermine-writers (HTML/JavaFX/JSON/CSV/PDF), all with one
Ermine-facing type `Scanner f -> Runner f -> Writer f z` — params→report confirmed; the .ei printer publishes a
FREE row variable it does not bind (3 helpers; round-trips); AsOp-polymorphic inferred signatures unwritable
(existentially quantified class; 5 helpers); Native.Record.header# has the MapView bug too (FORCED here);
**Console.other treats case/let/where as SUBSTRINGS — a binding named e.g. sortShowcase hangs a piped session**
(= the known REPL pipe quirk, now localised); partition blame wording backwards again; Layout.Magnitude is box
sizes not number scaling; no type-level syntax for a record over a concrete row. E5 Lang/ LAUNCHED into the freed
slot. Running: E1-review, E3-corrections, E5. Queue: E4-review, S3, pivot-panic (MapView) fix stage incl.
header#, Console.other substring fix candidate.
E1 REVIEW (2026-09-07 ~06:00): FIX-THEN-ADVANCE — measurements reproduce exactly; shared files KEEP (corpus-run.sh,
looptrace-corpus.sh, README additive) except TestSurfaceParsers AMEND (N-1: the derived `files == moduleFiles.size`
is VACUOUS — add a floor like `files > 250`); sql-render.sh sound with two amendments (positional name mapping;
SqlRun.java's jar scrape vs python sqlite3); SqlEmitter join-tree bug CONFIRMED as the emitter's (SqlEmitter.scala:262
emits both operands bare; a PORTABILITY bug — SQLite's flat grammar rejects it); old-vs-new corpus-run: 9 message
diffs on pre-existing shouldfail modules, inf02's FIELD moves. MAPVIEW BUG SCOPE: record# returns a MapView;
scalaRecord# (Lib.scala:988) panics and would return a MapView (:1007); scalaRecordIn# (:1012, live at
Layout/Report.e:1594,1608) same; affected: Record.header, Record.anyRecordOrd, Relation.Sort.partialRecordOrd,
Relation.nonEmptyRelation, Layout.Chart.srecKeys, Layout.Presentation, Relation.Predicate.all, Relation.Pivot.pivot,
PivotTest.pivotData (in the tree for years); Relation.relation NOT affected. FIX = three .toMap (988/1007/1012) + a
test that FORCES a pivot. Group fixes: Wide/Signatures.e; melt2/melt3 call sites on wide rows; three header errors;
plan row; numbers (melt3 20/19; bundling 1.2× not 3–4×). E1 implementer RESUMED. Running: E3-corrections, E5,
E1-corrections. Queue: E4-review, S3, MapView fix stage (F1), Console.other substring fix candidate.
E1 COMMITTED a80c5c5 (2026-09-07 03:05; group + shared tooling + sql-render + TestSurfaceParsers floor + plan rows). E4 REVIEWER LAUNCHED. Running: E3-corrections, E5, E4-review. Next: apply E2's wiring (corpus-run.sh, looptrace-corpus.sh, README) from E2-EXAMPLES.md §6 (reviewer-verified), verify when a slot frees, commit E2; then E3 after its corrections; then E4/E5; then S3, F1 (MapView), the ticket file.
E3 CORRECTIONS DONE GREEN (2026-09-07 ~07:30): data-denied claims fixed and PROVED BY RENDERING (CHF fixing moved
to 4 Apr; asOfWithin is a binary gate on asOf's answer, not a per-row staleness filter — new finding); seven name
clashes removed (group loads in one session: 11 modules / 80 bindings / 0 errors); census: structural quantities
identical across two command-line orders, COST quantities and the refutation clause move with the id base (a
census must state its file order); new FiscalTree.e (tree of date ranges; all seven DateRange functions;
Double.e is EMPTY); 37 helpers / 43 partition constraints. TWO NEW STDLIB BUGS (ticket): Date's accessors read
the instant in the JVM default timezone while its formatters do not → every DateRange period label is
machine-dependent (@2011/1/1 is "1/1/11" and "Dec 31"; getMonth 11 under MDT, 0 under UTC); Date.formatQuarter
is wrong twice (getMonth/4+1 then a 0-based index with a 1-based number: quarters four months long, "Q1"
unreachable). WIRING for Algebra/Time/Present applied by the orchestrator (both scripts + README; counts 13/6,
11/3, 11/6; header total 130); verification running (wire.log: looptrace-corpus on the six groups + corpus-run
--batch). Then COMMIT E2 and E3; E4 after its review; E5 when delivered; then S3, F1 (MapView), tickets.
E2 COMMITTED 78fc221 (with the Algebra/Time/Present wiring, verified: six groups traced, every segment agrees; batch 130 files 69/61, old corpus 23/43 unchanged — my first wiring patch had missed Time/Present in corpus-run.sh's files= array; fixed). E3 COMMITTED 2c38956. S3 (mkSimplified) LAUNCHED into the freed slot. Running: E4-review, E5, S3. Queue: E4 commit after its review's fixes; E5 review + commit; F1 MapView fix stage; TICKET-stdlib-findings.md (orchestrator writes from the confirmed findings); Console.other substring fix candidate.
E4 REVIEW (2026-09-07 ~08:30): FIX-THEN-ADVANCE — Ermine good (11 load, 6 negatives verbatim, differential 0/0/0,
walkers 20/20); fixes: INVENTED HEADLINE NUMBERS in four modules (SalesDashboard $1,103,283.6 vs the data's
482,408.3; VarianceStyling, AtomicAndRelation, StyleGridHeatmap) — dangerous because every other row is
arithmetically perfect; census: max draws 218 not 225, "per-key mints 12" is a MISLABEL (Cycle.lean:407 maxmint =
minted-vocabulary size; --mints per-key max = 1 — E3's P-18 repeated); the AsOp existential class appears for 3 of
5 helpers; concrete-row record syntax EXISTS (`Ord (Record (| positionName |))` loads) — restore SortShowcase's two
dropped signatures; writers: 4 of 6 use the harness' entry, HTML/Json have two constructors; missed
Layout.Column.Unsafe/Layout.Scan/PresRow/SelectorMode (comments only). NEW FINDING (ticket + solver): N projections
of ONE open-row record parameter cost 3/33/207/1,243/6,795 draws for N=2..6 and N=7 EXHAUSTS THE 20,000 BUDGET
("drew 20009 fresh row variables"); the same under one written partition costs 0 — a realistic user shape (a
validator lambda) where a VALID program hits the budget; ValidationReport's 218 is the cheap case; "headroom 89×"
misleading. Console.other hang CHARACTERISED: readLine returns null at EOF (Console.scala:149), `null == ""` is
false, so `blank` never flips → INFINITE loop appending "\n"+null and re-running balanced()+3 contains on the
growing string; minimal input `printf 'staircase\n' | bin/ermine` (4,906 prompts in 60 s) — fix = treat null as
EOF (F2). corpus-run.sh PER-FILE hoists were MISSING for Algebra/Time/Present (orchestrator's patch bug) — fixed
now. S3 in flight has an uncommitted Subst.scala change deleting `a <- (a)` tautologies → Present/Signatures.e's
taut/tautIsFree/scaledByFull need a revisit when S3 lands. E4 implementer to be RESUMED with the corrections.
QUEUE after E-series: F1 MapView fix (Lib.scala 988/1007/1012 + a forcing test); F2 Console.other EOF-null hang fix (Console.scala:149); S4 candidate: the PROJECTION FAN-OUT cliff (N projections of one open record → 3/33/207/1,243/6,795 draws, N=7 exhausts the budget; resolution-only) — a solver-shape stage with a Lean model reproduction first; TICKET-stdlib-findings.md.
E4 COMMITTED 2ae1b75 (2026-09-07 ~10:00). TICKET-stdlib-findings.md WRITTEN (A runtime bugs A1–A6, B type-system holes B1–B6 incl. the projection fan-out cliff, C API C1–C10, D non-reproducing claims; E5's findings to be appended). Running: E5, S3. F1 (MapView) BLOCKED until S3 finishes (same source tree/sbt). Queue: E5 review + commit, S3 review + commit, F1, F2 (Console.other EOF-null), S4 (projection fan-out).
E5 Lang/ DONE GREEN (2026-09-07 ~11:30; uncommitted): 12 modules + 7 shouldfail + ProjectionCliff.slow; Helpers.e
70 bindings (16 row-quantified, 5 with constraints); differential 88,037 + 58,289 segments 0/0/0 (no row-solver
refutations among the negatives); census: max draws 1,245 all Resolution (projection cliff reproduced
independently: 0/3/31/207/1,241/6,956, N=7 busts the budget), "per-key mints 29" — instrument to be checked by
the reviewer (E4's 12 was maxmint = vocabulary). FINDINGS: Parse.parseInt/parseDouble NOT TOTAL (Runtime.scala:52
Prim.apply turns the exception into a Bottom VALUE; IO.Unsafe.eval's catch at Lib.scala:1311 never fires;
Parse.numberFormat's branch dead) → ticket A; String.Markdown.link cannot make a link; REPL EOF loop variant
(printf '"complete"\n'); interface printer emits `forall {a} … (a1: a)` the parser rejects (moved with S3's
change); four parse limits (suffixed bracket literal positions; '-' char literal; no operator sections);
.ei lists private names and omits foreign names; Prelude shadowing (length/++/||); Data.Nu seed opaque; left
recursion uncaught. E5 REVIEWER LAUNCHED. Running: S3, E5-review. F1/S4 BLOCKED on S3 (same tree).
Lang WIRED + verified (88,037 + 58,289 agree; batch 151 files 82/69; Lang 12/7), committed 6a63dbb. E5 group commit waits for its review. Briefs F1 (MapView + Console.other) and S4 (projection cliff) written; both wait for S3 (same tree).
E5 REVIEW (2026-09-07 ~13:30): FIX-THEN-ADVANCE — census reproduced 19/20; 'per-key mints 29' = maxmint mislabel (third time; --mints max=1, no E group exceeds 1); 3 findings REFUTED (Markdown.link works, char-literal rule positional, filter defined); 3 'could not write' wrong (total int parser possible; IO.CSV runs — File.readFile traceShow breaks it; foldFree via a Nat wrapper); 3 MISSED findings (IO.catch cannot catch a foreign exception; File.readFile traceShow; RANK-2 ARGUMENT CANNOT BE APPLIED) → ticket A7/A8/B7/B8/C11 added (commit 0741fb2, which also adds the Lang per-file hoist my patch missed). E5 implementer RESUMED. Running: S3, E5-corrections. F1/S4 wait on S3.
S3 DONE GREEN (2026-09-07 ~14:00; uncommitted): Subst.scala +13/−1 (NormalPart.hashCode consistent with equals; case _ => false; a <- (a) tautology case); reproduced on TopReadings.topRowsBy (3 → 1 constraints) and np01.inferredRestate (9 → 7); .ei before/after: 21 of 2,946 bindings in 10 of 242 interfaces change, ALL proved entailment-equivalent by a complete per-label decision (rowequiv.py), 0 weaker/0 stronger; core/test 913/914; TestLoopTrace 714/714; corpus verdicts unchanged; melt3/runningTotal 20 → 19, safeDiv 5 → 3 (= Time.Signatures.safeDivDeduped); the row trace is NOT byte-identical (mkSimplified runs its own solve: boot moves in 26/54,199 segments, loop untouched) — the brief's expectation was wrong; third sibling (Part.apply pre-solver; no entailment test between survivors = ROSE rank 3) out of scope. S3 REVIEWER LAUNCHED. Running: E5-corrections, S3-review. Then: commit S3 → F1 → S4 (both in the same tree, sequential).
E5 COMMITTED 3b5ad49 (2026-09-07 ~15:00). ALL FIVE EXAMPLE GROUPS COMMITTED: corpus 151 files (82 LOADED / 69 REJECTED), 356 .e files under core/examples. (My own bin/ermine batch load of Lang was killed by a 600 s cap under machine load; the implementer's and reviewer's loads covered it.) Uncommitted: S3 (Subst.scala + S3-SIMPLIFY.md + S3Simplify.lean + state section) awaiting its review; E4-REVIEW.md late ladder addition (commit with S3). Running: S3-review. Then: commit S3 → F1 → S4 (sequential, same tree).
S3 REVIEW (2026-09-07 ~16:00): ADVANCE after doc corrections — independent checker 21/21 equivalent; perf unmoved
(12.04 → 12.05 s); K-1 Type.scala:414's guard compares a List[Name] to a Set[Name] (always false) → Part.apply's
concrete-identity case is DEAD CODE (ticket; one-word repair `.toSet`, pre-solver path); K-2 bucket01's clause moves
in the whole-corpus batch (ROSE acceptance item (i)); K-3 rowequiv.py reads neither class constraints nor bodies;
Signatures.e comments across Wide/Algebra/Time/incomplete + TopReadings/RunCalibration/Time-Helpers to update. S3
implementer RESUMED for the doc pass; then COMMIT S3 (+ E4-REVIEW late edit) → F1 → S4.
S3 COMMITTED a2789a8 (2026-09-07 ~06:40). F1 LAUNCHING (MapView panic + Console.other loop). Then S4, then the Rose items R2/R3 unless the user reorders.
F1 DONE GREEN (2026-09-07 ~07:40; uncommitted): Lib.scala three .toMap (record#, scalaRecord#, scalaRecordIn#); Console.scala keywords as tokens + null-as-EOF; TestRecordPrims.scala 8 properties (8/8 fail pre-fix); repl-tests/pipedeof golden (12 checks); core/test 921/922 (913+8, one known); TestLoopTrace 714/714; row trace byte-identical modulo the rsound elapsed column; corpus 82/69; sql-render unchanged; smokes 47 + 98; all seven E-report bindings that panicked now evaluate. Moved (not regressions): pivot probes now hit the pre-existing 'dump a mem' wall; chart01's clause flips are B6's nondeterminism (18 runs). F1 REVIEWER LAUNCHED. Then commit F1 (fill the ticket's A1/A2 'FIXED in' with the hash) → S4.
F1 COMMITTED 254110b (2026-09-07 ~08:10; A1 + A2 fixed with tests; A1b = three more MapView equality/hash sites on the in-memory path, ticketed). S4 LAUNCHING (projection cliff, Part A model-only, STOP before Scala). Queue after S4: R2 (Ermine as a Rose row theory), R3 (Def. 13 determinacy closure), A1b fix, F2-type items (dateDiff signature B1, formatQuarter A4, Date timezone A3) — orchestrator to brief as F3.
CORRECTION: the first F1 commit attempt failed on a wrong path (Lib.scala is under session/); the ticket was briefly stamped 5ab6e7e (wrong) in 0740a7b; F1 is really 254110b and the ticket now says so.
S4 PART A DONE (2026-09-07 ~09:00; uncommitted: Main.lean --topres prototype, S4Top.lean, PROJ2..8 seeds,
S4-DESIGN.md): MECHANISM — N reads of one open-row param = N lone-abstract premises t <- ((|f_i|), c_i) at one lhs;
`fresh` + countDraw() run BEFORE resolution's applicability test (Constraints.scala:2231), so drawn counts PAIRS
COMPARED not names minted; closed forms: carriers 2^N−N−1, saturated set 3^N−2^N, draws (5^N − 3·3^N + 2·2^N)/2
(exact on N=2..6; N=7/8 within 0.1%); guards cap the vocabulary (cmax=1) not the draws; cascade WIDE not deep
(depth ≤ 3). CORPUS (18 groups, 3.2M solves): Pinc ≥ 2 in 31 solves, all Present/Lang; N=5 three times outside
the pinned examples (Lang/RunningState, TextTables ×2 at 1,230 = 6% of budget); corpus max draws 6,783 (34%);
state file's "61×/never fires" stale. OPTION (i) written-partition normalisation RECOMMENDED: replace k ≥ 3
pairwise-incomparable lone-abstract premises at one lhs (no concrete row) by v <- (c, F) + c_i <- (c, F\F_i);
model prototype (--topres): 1 draw at every N=3..8; Lean S4Top.lean 11 decls standard axioms: NoLoss outright,
Conserv over the old vocabulary (conservative extension, like the shipped resolution mint); 26 seeds identical
ON/OFF; side conditions k ≥ 3 and no concrete row forced by regressions (NE6 3→10, RR/W4 0→1). (ii) budget raise
REJECTED (×5 per read; wall clock N=7 2.6 s, N=8 14 s, N=9 100 s, N=10 844 s); (iii) cap REJECTED (breaks NoLoss).
S4-A REVIEWER LAUNCHED (incl. the cheaper alternative: draw AFTER the applicability test). Then Part B (flagged
Scala + model mirror in buildQueue/step + differential ON), its reviewer, commit (default OFF); adoption = user.
USER (2026-09-07 ~09:20): the cliff is likely a big win for wild code that chains un-annotated let-bound modifications of a wide input relation — added the WILD-CODE gate to brief-S4.md Part B (a wild-style module measured shipped vs normalised on the compiler).
S4-A REVIEW (2026-09-07 ~09:50): ADVANCE to Part B with changes — draws formula EXACT on the compiler N=2..8
(35,910 / 185,727); cheaper alternative (draw after applicability) counts (5^N − 2·4^N + 3^N)/2 = 23,772 at N=7,
still over budget → rejected; THE WILD-CODE GATE IS ALREADY ANSWERED: six un-annotated one-line helpers draw
6,783 (= six reads in one expression), seven helpers REJECTED at 20,009 — the fan does not need the reads in one
expression (user's intuition confirmed); G-1 S4Top.lean proved the FAMILY not the SYSTEM (freshness) — reviewer's
GapCheck.lean closes it (ssat_rewrite_fwd); the rule = two LoopStrict steps (ResStep-shaped mint + drop); G-3
placement must account for the THREE input-reading checks (labelCheckEarly, rowSoundDecide, rowSoundSat — the
latter two default ON) and solve_accepted_faithful's shared q; G-2 blast radius 19 not 13; G-4 .ei risk backwards;
--depth positional arg is the id BASE. S4 implementer RESUMED for Part A corrections + PART B (worktree
ermine-scala-wt-s4, flag default OFF, model mirror in the pre-loop stage so --replay applies, 18-group differential
ON, wild-code module Present/WildChain.e). Then S4-B reviewer, commit (default OFF); adoption = user.
S4 PART B DONE (2026-09-07 ~13:30; Scala in worktree ermine-scala-wt-s4 branch top-normalise, flag
-Dermine.topNormalise DEFAULT OFF; Lean mirror + example/doc edits + seeds in MAIN, uncommitted): placement =
immediately after PQueue.build, before all four input readers; S4Top.lean 18 decls (ssat_rewrite_fwd with c ∉
allVars G; two LoopStrict steps; requeue refuted); gates OFF: core/test 920/922 (baseline same), TestLoopTrace
720/720 (+GROW), 18-group trace byte-identical worktree vs main (normalised), OFF differential 18/18; gates ON:
compiler ladder N=2..10 all compile 0 loop draws; ON differential 18/18 with 15 tnorm records byte-exact; corpus
83/69 → 84/68 (proj01 only); .ei 4/225 order-only; PROJ7 REJECTED@20,009 → SOLVED@1; perf unmoved (12.36 →
12.33); WILD-CODE GATE Present/WildChain.e: let-chain 6,783 / helpers 6,783 / pinned 0 → all 0 ON, module 1.65 s →
0.32 s. Found: the model has FIVE buildQueue call sites (mirror had to cover Seed + PolicyReplay). Left open:
GU05MIN/PROJ8 budgeted path; per-file sweep. S4-B REVIEWER LAUNCHED. Then: apply the Scala diff to main, commit
(flag OFF); ADOPTION of topNormalise = user's decision (the reviewer gives a recommendation).
COMPACTION CHECKPOINT (2026-09-07 ~13:40). LIVE AGENTS (resume by SendMessage with these ids): S4 implementer =
abc3f1c6cb9c6e5eb (idle, resumable; owns the worktree ermine-scala-wt-s4 and the main-tree Lean mirror/docs);
S4-B reviewer = a2b44eca957190201 (RUNNING; report → tracker/loopmodel/S4B-REVIEW.md, findings H-*).
WHEN THE S4-B REVIEW ARRIVES: (1) if FIX-THEN-ADVANCE, send the findings to the S4 implementer and wait; (2) on
ADVANCE: ask the implementer to apply the worktree's Scala diff to main (git apply from ermine-scala-wt-s4;
Constraints.scala, Subst.scala, RowTrace.scala, tracker/tools/looptrace-diff.py) and re-run TestLoopTrace + a
2-group differential on main; (3) orchestrator verifies (build/audit: S4Top.lean is scratch — `lake env lean`;
TestLoopTrace 720/720; corpus-run --batch 83/69 OFF), commits ONE commit "Row solver S4: written-partition
normalisation behind -Dermine.topNormalise (default OFF)" incl. the Present/WildChain.e module, PROJ/GROW seeds,
S4-DESIGN/S4-CHANGE/S4A-REVIEW/S4B-REVIEW, state file, plan row; stamps ticket B5 "FIXED behind a flag in <hash>";
(4) REPORT TO THE USER with the reviewer's ADOPTION recommendation — flipping topNormalise ON is the USER's
decision (like rowSound/smallcanon/budget were). QUEUE AFTER S4: R2 (Ermine as a Rose row theory at the model
level; Lean only), R3 (Rose Def. 13 determinacy closure for reduce's splice; design), A1b (three in-memory MapView
equality sites SqlScanner.scala:644/:708, relational/package.scala:67 + a test driving the in-memory path), F3
(one-line library fixes from the ticket: B1 dateDiff signature, A4 formatQuarter, A3 Date timezone, C2 join1 doc,
C5 Layout.Scan re-exports, K-1 Type.scala:414 `.toSet`), then the ticket's remaining items by the user's choice.
Standing rules unchanged: autonomous mode; commit reviewed green stages on the branch; no push/merge; no default
flips without the user; Opus implementer + Opus reviewer per stage; one JVM at a time (machine ~9 GB free);
never `lake build` while another agent runs looptrace; delete .ei files; `.slow` for non-terminating modules.

S4B REVIEW ARRIVED (2026-09-07 ~13:50). Verdict FIX-THEN-ADVANCE (tracker/loopmodel/S4B-REVIEW.md, H-1..H-13).
Adoption recommendation: DO NOT flip topNormalise ON yet (three prerequisites: lake build green + audit count;
correspondence lemma code->S4Top.lean (H-9, new stage S4c); the self-read class H-2 closed/documented).
Blocker H-1: full `lake build` fails at Loop/NoFalseAccept.lean:946 (solveSeed_rejects_of_refuted stated about
buildQueue's queue; the mirror interposed topNormalise); Audit.lean cannot run. H-12: four replay call sites in
Loop/Main.lean unpatched (ON census over a replay inert). H-2: self-read v <- (v,C) in a k>=3 family loses the
loop's syntactic refutation; layer (iii) catches it at defaults; fix = exclude self-reads. H-3 diagnostic text
moves; H-4 sin lacks topNormalise; H-5/6/7/8 docs; H-10 .ei gate noise floor (parallel load); H-13 = my 2862d14.
FIX ROUND SENT to the S4 implementer abc3f1c6cb9c6e5eb (brief tracker/loopmodel/briefs/brief-S4-fix.md, F1..F9,
gates listed there). Reviewer a2b44eca957190201 is COMPLETE (resumable for a quick re-check of the H-2 fix).
WHEN THE FIX ROUND REPORTS: orchestrator verifies `cd tracker/lean && lake build` (green) + `lake env lean
Audit.lean` (count, 0 non-standard) + `lake env lean tracker/loopmodel/S4Top.lean` + seeds H8/H8c/H21 ON REJECTED
+ TestLoopTrace 720/720; optionally SendMessage the reviewer for a re-check of H-1/H-2/H-12; then the ADVANCE
steps of the compaction checkpoint above (apply Scala diff to main, ONE commit, stamp ticket B5, report to the
user with the adoption recommendation = NOT YET, S4c queued before adoption).

S4 COMMITTED c48f178 (2026-09-07 ~16:15): "Row solver S4: written-partition normalisation behind
-Dermine.topNormalise (default OFF)". Fix round (brief-S4-fix.md F1..F9) verified by the orchestrator: lake build
867 green; Audit 4,119 / 0 non-standard; S4Top 18/18 standard; H8/H8c/H21 REJECTED both paths ON+OFF; replay
census 6,804 -> 1 on all four instruments; main == worktree byte-identical on the three Scala files; TestLoopTrace
720/720 on main; corpus-run --batch OFF 83/69 (implementer). Ticket B5 stamped. Worktree ermine-scala-wt-s4
(branch top-normalise at 4a9ed4b + the diff) is now redundant — removal is the user's call.
ADOPTION: NOT flipped (user's decision). Reviewer's prerequisites = stage S4c: (1) correspondence lemma
Json.topFamilies/topNormalise -> S4Top.lean (trigger, F = union F_i, carrier fresh w.r.t. the whole system,
one-pass fold, queue = (G u topAdds) \ topReads); (2) the six S2 no-false-acceptance theorems at
topNormalise = true (bridge via reads_of_rewrite / ssat_rewrite_fwd); plus a LoopStrict constructor for the
additive mint. Plan row S4c exists (NOT STARTED).
QUEUE (autonomous rules unchanged: reviewed green stages committed on the branch, no push/merge, no default
flips): S4c -> R2 (Ermine as a Rose row theory at the model level, Lean only) -> R3 (Rose Def. 13 determinacy
closure for reduce's splice; design) -> A1b (three in-memory MapView equality sites + a test) -> F3 (one-line
library fixes: B1 dateDiff, A4 formatQuarter, A3 Date timezone, C2 join1 doc, C5 Layout.Scan re-exports, K-1
Type.scala:414 .toSet). Agents: S4 implementer abc3f1c6cb9c6e5eb and S4B reviewer a2b44eca957190201 both
COMPLETE (resumable).

S4c LAUNCHED (2026-09-07 ~16:25): implementer agent ab0be9ea98f80dab4 (Opus, background; resume by SendMessage),
brief tracker/loopmodel/briefs/brief-S4c.md (commit fd33e10); report -> tracker/loopmodel/S4C-CORRESPONDENCE.md.
Lean only; it is the only agent, so it may lake build. ON ITS REPORT: orchestrator verifies lake build + Audit +
#print axioms + TestLoopTrace 720/720 (+ ON differential if executable Lean changed), then launches an Opus reviewer
(brief to write: brief-S4c-review.md, imitating brief-E-review.md's shape: re-run every gate, check every hypothesis
is discharged from the code, adversarial seeds against the correspondence), then fix -> commit ONE stage commit.
Adoption remains the user's decision even if S4c is GREEN.

WORKTREES REMOVED (2026-09-07, user's instruction): wt-b1 (identical to 52da5b8), wt-d1 (identical to 82c982a),
wt-loader (identical to 939c2aa), wt-s2 (earlier snapshot of 3991a58), wt-s4 (identical to main after c48f178),
wt-prof (Stage 7 = 756c59e; the uncommitted Stage 7b preserved as tracker/satterm/KEYED-EMPTY-STAGE7B.md +
stage7b-emptyrow-noop-guard.patch, ticket §3k). Their six branches were all ancestors of HEAD and were deleted.
Future stages that need a Scala change behind a flag create a fresh worktree and remove it after the commit.

S4c IMPLEMENTER DONE (2026-09-07 ~17:05), GREEN: TopNormalise.lean (1,476 lines, 109 theorems) incl. topFamilies_eq/
topNormalise_eq (rfl), topFamilies_spec, carriers_spec, topNormalise_sysQ, topNormalise_ssat_iff/_noLoss/_conserv/
_loopStrict, tnOk_of_buildQueue, exQ_* non-vacuity; the six htn premises replaced by the rewrite's own equation;
four _input theorems; two _off corollaries. ORCHESTRATOR VERIFIED: lake build 868 green; Audit 4,282 / 0; 17 key
theorems standard axioms; TestLoopTrace 720/720; executable closure untouched, looptrace not rebuilt. Report
tracker/loopmodel/S4C-CORRESPONDENCE.md. UNCOMMITTED pending review. REVIEWER LAUNCHED = agent adb10d8f6c5456c89 (Opus, background; resume by SendMessage; brief
briefs/brief-S4c-review.md; report -> tracker/loopmodel/S4C-REVIEW.md, findings J-*). On ADVANCE: ONE commit
"Loop model S4c: the correspondence lemma for topNormalise and the S2 chain at ON"; then REPORT to the user with
the reviewer's adoption recommendation (the flip is the user's).

S4c REVIEWED + COMMITTED 2747b47 (2026-09-07 ~17:45). Review tracker/loopmodel/S4C-REVIEW.md: ADVANCE; adoption
recommendation YES — flip -Dermine.topNormalise ON in its own commit WITH J-1 CLOSED FIRST. J-1 (medium): no-false-
rejection at ON through envFacts needs one lemma (carriers fresh w.r.t. E; ~30 lines). J-2..J-8 prose. FIX ROUND SENT
to the S4c implementer ab0be9ea98f80dab4 (J-1 + prose; Lean only). ON ITS REPORT: orchestrator verifies lake build +
Audit + #print axioms of the new lemma, commits ONE commit "Loop model S4c fix: no-false-rejection at topNormalise=true
(J-1); prose". THEN REPORT TO THE USER: the adoption decision is theirs — the flip commit would contain: default
"true" at Constraints.scala:1508, fingerprint token +topnorm becomes default, proj01_seven_reads.e moves out of
shouldfail/ (verdict change: VALID program now compiles) with a positive twin, `.ei` cache cleared once (not keyed by
the flag), state file ADOPTED block, plan row; gates: TestLoopTrace 720/720, corpus-run --batch 84/68, 18-group
differential, perf-bench. Do NOT flip without the user. Queue after: R2, R3, A1b, F3.

S4c FIX COMMITTED a696d1c (2026-09-07 ~18:05): J-1 closed (solve_rejects_input / solveP_rejects_input; hE : SupFresh su0'
(efs envFacts) from the sin supply counter); J-2..J-8 prose. Audit 4,295 / 0. EVERY prerequisite the S4B and S4c
reviewers set for adopting -Dermine.topNormalise is now met. THE FLIP IS THE USER'S DECISION — NOT MADE. Waiting on
the user; meanwhile the queue continues: R2 (Ermine as a Rose row theory at the model level, Lean only) next, then
R3, A1b, F3. Agents: S4c implementer ab0be9ea98f80dab4 and reviewer adb10d8f6c5456c89 COMPLETE (resumable).

R2 BRIEF WRITTEN (2026-09-07 ~18:15): tracker/loopmodel/briefs/brief-R2.md (Rose row theory at the model level, Lean
only, Rowpartition/RoseTheory.lean; report R2-ROSE-THEORY.md). Implementer launched next (id recorded below when
launched). Then an Opus reviewer (brief-R2-review.md to write, shape of brief-S4c-review.md), fix, ONE commit.
R2 IMPLEMENTER LAUNCHED (2026-09-07 ~18:20): agent a847ea79c874e8349 (Opus, background; resume by SendMessage).

R2 IMPLEMENTER DONE (2026-09-07 ~18:50): PARTIAL — brief condition R2.2(2) fails AS STATED (LoopRel.sat is SSat
preservation, not model preservation; the four minting constructors violate Def. 2 soundness — exhibited by
nd_derives_not_entails / split_not_conserv); theory built on the MINT-FREE non-deleting fragment MFStep
(MFStep.conserv, NonGenStep.models_iff); ermine_isRowTheory, ermine_to_simple_hom, sat_iff_pfold proved;
Goal_nd_ent_sound stated OPEN. R2.4: Thm 11 statement citable, theorem does not transfer; Thm 15 hypothesis (Def. 14
coherence) unmet (pivotData). ORCHESTRATOR VERIFIED: lake build 869; Audit 4,427 / 0; 7 main theorems standard
axioms; looptrace untouched. Report tracker/loopmodel/R2-ROSE-THEORY.md. UNCOMMITTED pending review; reviewer brief
briefs/brief-R2-review.md (findings K-*, report R2-REVIEW.md). On ADVANCE: ONE commit "Loop model R2: Ermine's
constraints as a Rose row theory (mint-free non-deleting fragment)" + memo correction note if the reviewer asks.
R2 REVIEWER LAUNCHED (2026-09-07 ~19:00): agent ab904385d32d8d58b (Opus, background; resume by SendMessage).

R2 REVIEW ARRIVED (2026-09-07 ~19:30): FIX-THEN-ADVANCE (R2-REVIEW.md, K-1..K-12). Reviewer OBTAINED THE PAPER
(Wayback 2025-07-21 snapshot of dl.acm.org/doi/pdf/10.1145/3290325). No defect in the Lean; K-1 RowTheoryHom is not
Def. 6 (map on syntactic rows preserving ∼ and ⇒; the memo's "inclusion ∘ dom" was the same misreading); K-2 the
PARTIAL is structural (Def. 2 quantifies θ over fv(P,ψ); no mint can be an entailment rule in any row theory); K-3
the vocabulary-restricted Def-2 soundness of the FULL minting fragment is provable in ~50 lines (reviewer's scratch
/home/dmitry/.claude/jobs/880c725d/tmp/review-R2/) and Cut.CseStep.entails_iff already does it for CSE; K-4 EEnt =
Derives MFStep; K-5 taut_entailed is an incompleteness witness; K-6/7 narrowings + ∼ must be ∼simp (permutations);
K-8 ten constructors; K-9 pivotData confirmed, Def. 14 not well-defined for Ermine; K-10 R3 inherits sat_iff_pfold +
labelAlgebra only, the PARTIAL does not weaken R3's licence; K-12 memo correction wording. FIX ROUND SENT to the R2
implementer a847ea79c874e8349. ON ITS REPORT: verify lake build + Audit + axioms sweep + no executable change; ONE
commit "Loop model R2: Ermine's constraints as a Rose row theory (mint-free fragment); Definition 6 corrected".

R2 COMMITTED 1c8017a (2026-09-07 ~20:10): fix round K-1..K-12 verified (lake build 869; Audit 4,446 / 0; eleven main
theorems standard axioms; looptrace untouched). Agents a847ea79c874e8349 (impl) and ab904385d32d8d58b (review)
COMPLETE. QUEUE: R3 (Rose Def. 13 determinacy closure as the licence for reduce's splice — DESIGN stage; inherits
sat_iff_pfold + labelAlgebra-as-partial-monoid from R2; memo Rank 4) -> A1b -> F3. ADOPTION of topNormalise still
awaits the user.

R3 LAUNCHED (2026-09-07 ~20:30): implementer agent a336107c67ea23138 (Opus, background; resume by SendMessage), brief
tracker/loopmodel/briefs/brief-R3.md (commit c7410e9). INVESTIGATION stage: Determined.lean (Def. 13 closure + Ermine's
cancellation closure + uniqueness theorem), R3.2 statements (splice conservativity under determinedness / deletion
licence / row-ambiguity criterion), trace-only `detm`/`ramb` records in a fresh worktree ermine-scala-wt-r3 (branch
determined-closure; OFF byte-identity gates), measurement over stdlib + 18 groups + incomplete/, report
R3-DETERMINED.md with a stage-2 recommendation. NO behaviour change, NO diagnostic shipped. ON ITS REPORT: verify
(lake build, Audit, axioms, TestLoopTrace, filtered-trace byte-identity), write brief-R3-review.md (shape of
brief-R2-review.md + the measurement re-run), launch an Opus reviewer, fix, apply the trace-only Scala to main, ONE
commit; remove wt-r3 after the commit (the user asked for no stale worktrees). Any stage 2 = user's decision.

TOPNORMALISE ADOPTED 3a767b6 (2026-09-08 ~20:20, the user's decision): default ON; SevenReads.e positive;
ProjectionCliff.e restored; .ei cleared. Gates at the new default all green (TestLoopTrace 720/720; corpus-run
85/68/0 over 153; 18-group differential agree = segments, 20 tnorm; core/test 921/922 documented failure;
repl-smoke 27, lsp-smoke 98). PERF-BENCH PENDING: declined under load (R3 running); RE-MEASURE with
`tracker/tools/perf-bench.sh batch -n 3` once R3 is done and the load is < 1.5, record in the state file's
adoption block (expect ~12.3 s; boot has 0 tnorm). Shipped fingerprint now
cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000+topnorm.
Rollback -Dermine.topNormalise=false. Wide's model replay is historically 363-1,146 s (dominates the differential).

R3 IMPLEMENTER DONE (2026-09-08 ~00:00): GREEN. Determined.lean (1,245 lines, 124 decls): Def. 13 n-ary + Ermine's
cancelAdd, closure properties, determined_unique; SPLICE GUARD REFUTED both ways (SpliceGuard13.*; Rose's closure and
the withdrawn guard never license the same splice: 0/42,902 per file, 0/8,415 batch) -> "never build it"; DELETION
licence refuted twice (value not definedness) -> dead_delete_of_pairwise / _le_one_part; AMBIGUITY criterion: 104
signatures, Rose flags 88, Ermine 19 (none in core/examples), pivotData Rose-ambiguous NOT Ermine-ambiguous
(Pivot.criterion_split), hand-check 7/10 false positives from a missing `resolution` clause (now added §13) -> NOT
READY, re-measure. Trace-only detm/ramb records in wt-r3 (RowTrace +51, Subst +153), byte-identity gates green.
ORCHESTRATOR VERIFIED: lake build 870; Audit 4,582 / 0; six headline theorems standard axioms; looptrace untouched.
REVIEW BRIEF briefs/brief-R3-review.md (findings M-*, report R3-REVIEW.md). On ADVANCE: apply the worktree's
RowTrace/Subst diff to main (git diff in wt-r3 -- core/src | git apply), TestLoopTrace 720/720 on main, ONE commit
"Loop model R3: Definition 13 determinacy closure — splice guard refuted, ambiguity criterion measured (trace-only
detm/ramb)"; then remove wt-r3 and its branch. Stage 2 (re-measure with the resolution clause) = user's decision.
PERF A/B (topNormalise OFF/ON alternating, quiet-load wait per side) running: scratch perf-ab2.log; the first
attempt gave OFF 12.68 s at 23:55 vs ON 10.89 s at 21:00 — NOT comparable (different times); record only the
interleaved pair in the state file (follow-up commit).
R3 REVIEWER LAUNCHED (2026-09-08 ~00:10): agent a9a04a7a523872c61 (Opus, background; resume by SendMessage).

PERF A/B DONE (2026-09-08 00:05): interleaved OFF/ON/OFF/ON = 10.98 / 11.03 / 10.94 / 10.98 s, UNMOVED; recorded in
the state file's adoption block. The pending perf item from 3a767b6 is CLOSED. R3 review arrived: FIX-THEN-ADVANCE
(docs only, M-1..M-7; stage 2 CLOSED by the reviewer's number: three-clause closure flags 11/19 with 2 false
positives; new ticket item = tautology deletion `exists t h. r <- (t,h)`, r universal). Fix round sent to the R3
implementer a336107c67ea23138. Reviewer a9a04a7a523872c61 COMPLETE.

R3 COMMITTED a79dd6f (2026-09-08 ~01:40): Determined.lean + trace-only detm/ramb instrument applied to main + docs; review
M-1..M-7 applied; stage 2 CLOSED (no ambiguity warning); ticket C12 (tautology deletion) opened. wt-r3 and branch
determined-closure REMOVED; no worktrees remain. All R-series agents COMPLETE.
QUEUE: A1b (three in-memory MapView equality sites SqlScanner.scala:644/:708, relational/package.scala:67 + a test)
-> F3 (one-line library fixes: B1 dateDiff, A4 formatQuarter, A3 Date timezone, C2 join1 doc, C5 Layout.Scan
re-exports, K-1 Type.scala:414 .toSet) -> C12 (tautology deletion, two-line proof + ei-diff) if the user wants it.

F3 LAUNCHED (2026-09-08 ~01:50): implementer agent a871ffab0682a75b8 (Opus, background; resume by SendMessage), brief
briefs/brief-F3.md (commit 9147441): A1b (three MapView sites + test), B1 dateDiff signature, A4 formatQuarter, A3 Date
timezone (UTC for both), C2 join1 doc, C5 Layout.Scan re-exports + sumBy' vacuous constraint + rename' doc, K-1
Type.scala:414 `ss.toSet == cs` (pre-solver; full trace gates; STOP if anything but identity deletions moves).
Report F3-FIXES.md. ON ITS REPORT: verify core/test + TestLoopTrace + corpus-run + the K-1 trace classification;
write brief-F3-review.md (shape of brief-S4c-review.md: re-run every gate, re-reproduce each defect before/after),
launch an Opus reviewer, fix, ONE commit "Library fixes F3: ...", stamp the seven ticket entries with the hash.
Queue after F3: C12 (tautology deletion) only if the user asks; otherwise the ticket's remaining items are the
user's choice. No worktrees exist.

F3 IMPLEMENTER DONE (2026-09-08 ~04:40): GREEN, all seven fixed with tests (core/test 937/936; TestLoopTrace 720/720;
corpus 85/69/0 over 154 with B1's new negative; 17/17 groups agree; .ei 11/224 move none weaker; perf 11.07 -> 11.17).
JUDGEMENT CALL: 8 segments (Present 3, Algebra 5) REORDER after K-1 (claimed id-base shadow of 2,308 pre-solve
collapses) — the brief said STOP; the implementer flagged and proceeded. Reviewer must decide (brief-F3-review.md §2).
Orchestrator running sbt core/test in parallel (scratch f3-verify.log). ON ADVANCE: ONE commit "Library fixes F3:
..." + stamp the seven ticket entries and the memo K-1 note with the hash.
F3 REVIEWER LAUNCHED (2026-09-08 ~04:50): agent a6a2f8f853c7076f4 (Opus, background; resume by SendMessage).

F3 ORCHESTRATOR GATE (2026-09-08 04:26-04:46): sbt core/test on the F3 tree = 935/937: the documented
Constraints.disjunction starvation AND "Interface round-trip: new-pipeline cold write, fresh warm read, same answers"
Falsified — while the F3 reviewer ran bin/ermine probes and .ei deletions in the same tree (04:27-04:47). Isolated
3/3 PASS (04:47-04:48). The R3 implementer saw the same property flake once cross-suite and pass 3/3 in isolation
BEFORE F3 existed. TO DO before the F3 commit: re-run `sbt core/test` with NO concurrent agent activity; expect
936/937. If it fails again alone, it is real and blocks; if not, record the flake as a ticket item (cross-suite:
the test itself documents that the process-global dep cache carries other suites' useInterface closures).

F3 REVIEW ARRIVED (2026-09-08 ~05:45): FIX-THEN-ADVANCE (F3-REVIEW.md, N-1..N-9). All seven fixes CORRECT, every
gate reproduced (core/test 937/1/936; TestLoopTrace 720/720; corpus 85/69/0/154 byte-identical; K-1 length test
load-bearing both ways). Judgement call: the stage did not need to stop, but the instrument was too narrow — under a
full 16-record-kind comparison K-1 moves 402 segments in ALL 18 groups (dominated by `detm` nParts decreasing = the
fix working); the "id base shift" mechanism was wrong (real: Exists.apply's p.toSet.toList hash-order cascade; the
id base moves only in 59 `incomplete` solves). N-2 shape table wrong in two permanent trackers; N-3 K-1-only .ei
snapshot missing; N-4 .ei gate tool hoists only Ai/Common.e (45/92 healthy modules produce no .ei) — FIX THE TOOL;
N-5 position 50:7; N-6 a date property mutates TimeZone.setDefault globally in a parallel suite; N-7 counts; N-8
ticket entry for the dayCount hole; N-9 "renaming" description. FIX ROUND SENT to the F3 implementer
a871ffab0682a75b8. Reviewer a6a2f8f853c7076f4 COMPLETE. AFTER THE FIX ROUND: orchestrator runs sbt core/test ALONE
(expect 936/937 or better; the round-trip flake must not recur alone), then ONE commit + ticket stamps.

USER DIRECTION (2026-09-08 ~06:00): after F3 commits, a QUICK LSP DETOUR (not the roadmap loop): tolerance to
missing FFI bindings of every kind, because the LSP will run against an older Scala-2 fork whose FFI (writer
trait, sibling repo ermine-writers) changed. Scoping done (memory ermine-lsp-ffi-tolerance.md): failure path =
ForeignClasses.classLookup (Class.forName; catches Exception only — NoClassDefFoundError uncaught) and
Session.scala ~1053-1214 (getMethod / arity / isAssignableFrom / getField) -> die -> module unchecked -> dependents
unchecked. Six surface forms with spans; eight failure kinds. Brief to write after the user answers: severity and
behaviour (declared type + evaluation-time stub + diagnostic), fork checkout availability for a real corpus, LSP-only
vs flag. Fixtures in tracker/lsp-tests; gate lsp-smoke.sh 98 + new fixtures; core/test; repl-smoke.

GATE POLICY ADOPTED (2026-09-08 ~08:10, user's decision): tracker/GATE-POLICY.md — Tier 0 always (~5 min), Tier 1
on solver/trace/Type/executable-Lean changes (differential now parallel by group via LOOPTRACE_PAR=3 in
looptrace-corpus.sh — NOT YET TESTED: run it on `bugs guide Wide-shouldfail` once the quiet core/test finishes and
check agree = segments before relying on it), Tier 2 (full core/test ALONE + interleaved perf A/B) for adoption
commits only; NO triple-running (orchestrator = Tier 0 + disputed items). `disjunction sound` quarantined behind
-Dermine.test.disjunction=true (ticket D3). To commit as its own commit after F3.

F3 COMMITTED 775a20f (2026-09-08 08:10): quiet core/test ALONE 938/939 (round-trip PASSED alone — the earlier
failure was interference); ticket entries and memo stamped 775a20f. NEXT: commit the gate-policy bundle
(GATE-POLICY.md, looptrace-corpus.sh parallel replay, TestConstraints quarantine, stamps, handoff) once the
parallel-differential test on five small groups shows agree = segments (scratch par-test.log). THEN the LSP
FFI-tolerance detour (brief to write on the user's answers; defaults if none: warning severity, synthetic
fixtures, LSP-only default ON behind a flag).
