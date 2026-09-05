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
positive-control vacuity fixed; FINAL ADVANCE. L4 ADVANCED 2026-09-04. L2 COMMITTED as `9b8aa33` (2026-09-04, user's word). UNSTAGED: L3 + L4 files, L5 in progress. Commit plan when the user says: L2 (the index), then L3 (Loop/{Wf,Order,Refine,RefineConcrete,
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
commented-out warn in Subst.scala (wrong layer; would also invalidate model lemmas). Unapplied; the fix must be
mirrored in the Lean model's makeEmpty (Loop/Step.lean) and gated (core/test incl. TestLoopTrace, corpus,
.ei, seeds). L5 ROUND 2 running (same implementer); the 1,456-partition splitKey=false replay under tmp/L4/gu05nk/ is a model-speed
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
