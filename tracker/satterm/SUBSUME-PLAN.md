# SUBSUME-PLAN — does the checker terminate on a refused row program? (`subsumeType`'s escape check)

Programme prompt: `tracker/PROMPT-subsume-termination.md` (read it first; Part B is the shared evidence).
Orchestrator: Fable (plans, briefs, merges, gates, commits, logs — never proves, implements or reviews).
Every sub-agent is Opus. Started 2026-09-16.

Base: `scala3-migration` 478a369c. Programme branch `subsume-termination`, worktree
`~/research/ermine/ermine-scala-wt-subsume`. Stage branches `subsume-<stage>` off the programme branch, one
worktree each: `~/research/ermine/ermine-scala-wt-subsume-<stage>`.

## Stages

| Stage | Branch / worktree | Agents (Opus) | Depends on | Brief | Report | Status |
|---|---|---|---|---|---|---|
| S0 diagnosis | `subsume-s0` / `wt-subsume-s0` | implementer + reviewer | — | `briefs/brief-S0.md` | `SUBSUME-STAGE0.md`, `-REVIEW` | launched 2026-09-16 |
| S1a substitution model | `subsume-s1a` / `wt-subsume-s1a` | Lean prover + reviewer | reads S0 only | `briefs/brief-S1a.md` | `SUBSUME-STAGE1A.md`, `-REVIEW` | launched 2026-09-16 |
| S1b rejection-path model | `subsume-s1b` / `wt-subsume-s1b` | Lean prover + reviewer | reads S0 only | `briefs/brief-S1b.md` | `SUBSUME-STAGE1B.md`, `-REVIEW` | launched 2026-09-16 |
| S2 the fix | `subsume-s2` / `wt-subsume-s2` | implementer + reviewer | S0 + a reviewed S1 theorem | `briefs/brief-S2.md` | `SUBSUME-STAGE2.md`, `-REVIEW` | not started |
| S3 the budget | `subsume-s3` / `wt-subsume-s3` | implementer + reviewer (≠ S2's) | S2's PROVED negative only | `briefs/brief-S3.md` | `SUBSUME-STAGE3.md`, `-REVIEW` | not started |

Common rules for every agent: `briefs/brief-S-common.md`. Review brief: `briefs/brief-review.md`.

## Landing procedure (orchestrator)

1. Reviewer verdict LAND (or FIX-THEN-LAND with the fixes re-checked by the same reviewer).
2. Merge `subsume-termination` into the stage branch (doc conflicts: orchestrator; code conflicts: implementer).
3. Tier 0 on the merged stage tree, harness-tracked background, never `nohup`; Tier 1 items only if the review
   disputed one. Corpus verdicts must not move (89 LOADED / 79 REJECTED / 0 UNKNOWN over 168 per the prompt;
   S0 records the actual baseline on this tree).
4. One commit per stage on the stage branch citing the reviewer's verdict; fast-forward `subsume-termination`.
5. Never push, never merge into `scala3-migration`, never flip a default.

## The title question — running answer

Unanswered. Filled in per stage below (yes / no / bounded), then in the final report.

## Handoff log (append after every event; a new orchestrator resumes from here)

- 2026-09-16 (start): read PROMPT-subsume-termination.md, GATE-POLICY.md, memory notes (gate policy, autonomous
  mode, JSON Stage 3 lesson: no `nohup`). Branch `subsume-termination` created at 478a369c, worktree
  `ermine-scala-wt-subsume`. `tracker/lean` is byte-identical between 478a369c and `json-wrappers`, so the built
  `.lake` (2.0 G, mathlib v4.33.1 + Rowpartition + looptrace) from `ermine-scala-wt-json-wrappers/tracker/lean/.lake`
  is copied into the S1a/S1b worktrees to seed their builds. Machine: 12 cores, 15 G RAM (~10 G available),
  13 G disk free — three lanes concurrently are affordable, a fourth `.lake` copy is not without cleanup.
- One code-reading note recorded for the agents, NOT a finding: `Type.scala:653` `VarT(v) => v.extract.vars`
  extracts the type variable's KIND annotation (`Kind.scala:135` is the same pattern for `V[A]`), and
  `Kind.scala:65` gives `VarK(v).vars = Vars(v)` — so, as read, the kind-variable walk follows no binding at all.
  Part B's H2 wording ("follows a variable's binding") is therefore questioned in brief-S0/S1a; the agents settle it.
- 2026-09-16 ~afternoon: docs commit 1813172a on `subsume-termination`; stage branches `subsume-s0`/`s1a`/`s1b`
  and worktrees created at it; `.lake` copied into s1a and s1b (no-op `lake build` 871 jobs confirms the cache;
  disk now 8.2 G free). Three Opus agents launched concurrently: S0 implementer (3 h), S1a prover (4 h),
  S1b prover (4 h). Scratch dirs `~/research/ermine/scratch-subsume/{s0,s1a,s1b}`. Reviewers launch per stage on
  completion with `briefs/brief-review.md`. S2/S3 briefs to be written from Part C after S0/S1 report.
- 2026-09-16 ~16:35: S1a DONE (uncommitted on `subsume-s1a`, ~2h15): `Rowpartition/SubsumeEscape.lean` (55 theorems;
  audit 4936 / 0; lake build 872 jobs). Answer for the walk: YES, terminates unconditionally — `VarT(v) => v.extract.vars`
  reads the kind annotation, no binding followed (`follow_diverges` vs `escs_total_on_cyclic`: H2 REFUTED as a
  reading of the code); cost fixed by the expression (`runV_steps`); `escs_cost_le_subPass` (the walk costs a
  constant factor of one `instantiateType` pass, so a 28-minute :648 means the hang is upstream — H3 live, H1
  sharpened); `walk_exp_in_dag` witness + `subst_pays_the_same`; `verdict_eq` (per-skolem test ≡ whole walk under
  id uniqueness, nothing observable changes); `kind_half_not_reducible_to_type_skolems` (the brief's cheap X is
  unsound for the kind half). S1a reviewer launched (Opus, brief-review).
- 2026-09-16 ~17:05: S1b DONE at budget (uncommitted on `subsume-s1b`): `Loop/RejectTerm.lean` (225 l) +
  `Loop/EnvBound.lean` (528 l), 44 declarations, audit 4733 / 0, lake build 873; no executable module changed
  (looptrace unaffected, not a Tier 1 trigger). Findings: (1) HOLE at shipped defaults closed —
  `PolicyTerm.budgetP_terminates` assumed `rowSoundBare = false` but that layer has been default ON since
  2026-09-06, so no termination theorem covered `runSP`; `stepSP_cases` lets `budgetSP_terminates` drop the
  hypothesis; `solveSeedP_terminates` covers the whole of `Subst.solve`. (2) Environment bound: in n dequeues
  `|types_loop| ≤ n` with exactly one node per entry — the loop cannot produce H1's enormous `hm.types`.
  (3) H1 located in ordinary unification: `SubstBlowup.chain_blowup` (n unifications, one entry of 2^(n+1)−1
  nodes, all occurs checks passing). (4) H2 refuted twice (`stepP_noAliasChain`, `noAliasChain_no_cycle`; and
  the walk follows no binding). Answer: loop BOUNDED, rest of `Subst.solve` YES, post-solve row fragment yes
  (escape walk a theorem; `SigEntail.enforce` not covered). Reports S0 "landed mid-write": check runs 0.06 s,
  property runs it 100×; :648+:365 ~2 % of the pathological CPU. S1b reviewer launched (Opus).
- 2026-09-16 ~17:30: S1a REVIEW = FIX-THEN-LAND (`SUBSUME-STAGE1A-REVIEW.md`; reviewer re-ran: build 872,
  audit 4936/0, 55 axiom prints standard, 4 vacuity mutations all fail). Lean sound and unweakened; four PROSE
  fixes: (1) `Untouched` age-stamp discharge is false (instantiateType :254 rewrites every value in place) — an
  age-stamped skip could ACCEPT an escaping skolem; (2) cost theorem bounds node visits, not time; (3) narrow the
  "X unsound for the kind half" claim; (4) escs is live at Subst.scala:365-367, not covered by verdict_eq.
  Reviewer's conclusion for S2: S1a licenses NO asymptotic improvement to :648; its deliverable is the proof
  that making :648 cheaper cannot be the fix. Findings sent back to the S1a implementer (same agent).
- 2026-09-16 ~17:50: S1b REVIEW = FIX-THEN-LAND (`SUBSUME-STAGE1B-REVIEW.md`; reviewer re-ran: build 873 no-op,
  audit 4733/0, 44 axiom prints byte-identical, Main.lean closure 60 modules none new, 5 vacuity mutations all
  fail). Theorems correct; eight prose findings, chiefly: report:318 false — `rowSoundBare = false` also gates
  `budgetP_terminates_of_buildQueue` and the ten `runSP_*` soundness declarations (OPEN item: the shipped-default
  soundness family still carries a hypothesis the defaults violate); `escWalk` models only the fskvs half of :648
  and bounds the answer's length, not the cost; "NO enormous env" holds in term size only. Reviewer's signed
  answer: loop BOUNDED at shipped defaults (no theorem at all under -Dermine.dequeuePolicy=shipped), rest of
  Subst.solve YES, post-solve PARTIAL. Findings sent back to the S1b implementer (same agent).
- 2026-09-16 ~18:00: S1a fixes applied (prose only; statements untouched; build 872 / audit 4936/0 unchanged;
  report §7 "Review fixes"). Key correction for S2: the `Untouched` age-stamp idea would ACCEPT an escaping
  skolem; only a content-based (re-stamp-on-substitute) restriction is licensed, and S1a licenses no asymptotic
  improvement to :648. S1a reviewer re-checking the four findings. S1b fixes in flight. S0 still running.
- 2026-09-16 ~18:15: S1b fixes applied: +`budgetSP_terminates_of_buildQueue`, +`runsP_noAliasChain` (46 decls,
  build 873, audit 4735/0); `runSP_*` soundness family recorded as an OPEN item (still carries `rowSoundBare =
  false`, which the shipped defaults violate — S2 must not cite it at the defaults); escWalk scope, env-bound
  wording, blow-up site (:313-318), README looptrace row corrected; report §8 = reviewer's signed answer. S1b
  reviewer re-checking. S0 still running.
- 2026-09-16 ~18:45: S1a LANDED. Review re-check LAND (§7 of the review; two report-only nits fixed by the
  orchestrator at landing). Stage commit 228fb504 on `subsume-s1a`, merge c806dbea, `subsume-termination`
  fast-forwarded to c806dbea. Landing gate on the merged tree (scratch-subsume/orch/s1a-landing-tier0.log):
  lake build 872 jobs, Audit 4936 / 0. No Scala and no executable Lean changed, so the Scala Tier 0 items are
  unaffected by construction (the programme worktree compile at 478a369c+docs: exit 0). Title question, walk
  only: YES.
- 2026-09-16 ~19:10: S1b LANDED. Review re-check LAND (two cosmetic residuals fixed by the orchestrator at
  landing: §7 cross-references; EnvBound.lean docstring now says RunSupOkP is undischarged at the shipped
  DEFAULTS since the default policy is smallcanon). Stage commit 4a04ad00 on `subsume-s1b`, merge with
  `subsume-termination` clean, fast-forwarded. Landing gate on the merged tree
  (scratch-subsume/orch/s1b-landing-tier0.log): lake build 874 jobs, Audit 4995 / 0 (= S1a's 4936 + S1b's 59),
  Loop/Main.lean import closure contains none of the new modules. Programme tree now = 478a369c + docs + S1a + S1b.
  Title question so far: walk YES (S1a); loop BOUNDED at shipped defaults, rest of Subst.solve YES, post-solve
  PARTIAL (S1b). OPEN items carried: `runSP_*` soundness family still assumes rowSoundBare = false; no
  termination theorem under -Dermine.dequeuePolicy=shipped. Waiting on S0 to brief S2.
- 2026-09-16 ~19:30: S0 DONE (stopped at budget+; uncommitted on `subsume-s0`: Subst.scala +239/−2 behind
  `-Dermine.subsumeTrace`, report 714 lines). HEADLINE CONTRADICTS THE PREMISE: the B1 check REFUSES in
  0.06–0.10 s at all 16 Supply id bases (`bin/ermine repro/Bad.e`: "Row partitions are unsatisfiable at field
  'Bad.startDate'"); H1 refuted (types.size max 1,566 in every run; tree/DAG ≤ 4.39; slowest walk 29 ms;
  :648 2.2 s + :365 3.9 s of a 184 s suite), H2 refuted (0 cycles in 984,024 walks; strict case classes),
  H3 survives only as "nothing grows or diverges; :648 is one of five sampler landing places". The "hang":
  `ErmineFixture.no` maps Proof→False/False→True so a rejection is `passed` not `proved`; ScalaCheck runs 100
  full checks, each re-type-checking the import closure (~9.1 s, linear in N, one library boot per test);
  `-minSuccessfulTests 1` → 12/12 green. LSP hazard not reproduced. Baselines: corpus 89/79/0 over 168;
  TestLoopTrace 3/3 but model-agreement property self-skipped (no looptrace binary) — reviewer to run it with
  the wt-json-wrappers binary. Not done: filtered repro pair, "another suite ahead" control, solveDet at N=16.
  S0 reviewer launched (Opus) with the harness explanation as the point to dispute hardest. S2/S3 premises
  (memoised :648 / budget) fail on this evidence if the review confirms; S2 to be re-briefed accordingly.
- 2026-09-16 ~20:15: S0 REVIEW = FIX-THEN-LAND, headline CONFIRMED and strengthened: the reviewer's default-N
  run of the suite FINISHED green in 1,099 s ("never returns" refuted by a completed run); bin/ermine refuses
  Bad.e in 0.07 s; TestLoopTrace with the model binary 720/720/720 (the real baseline); a preceding suite makes
  the repetitions no cheaper (11.4 s vs 9.3 s per test). Must-fix: (1) every :648 cost figure was floor-summed
  integer ms — corrected estimate puts :648 at tens of seconds, 10–25 % of a suite, INVERTING the ":365 costlier"
  comparison quoted in the landed S1A report and both Lean reviews (to be corrected at S0's landing from S0's
  §0.2 replacement sentences); (2) the TestLoopTrace baseline cited a non-existent log. Findings sent to the S0
  implementer. Reviewer's signed answer: YES as a measurement; not signed: any :648 share, "terminates" as a
  theorem (that is S1a/S1b's), "no input can diverge" (fixture env never swept over id bases; base-16 boot 2×
  outlier). Recommended next stage: a harness stage, not Part C's S2, and no S3.
- 2026-09-16 ~20:25: brief-S2 REWRITTEN (3fe4e8c3) as the harness stage: `proved` refutation combinator at
  TestErmine.scala:220-223 (24 `no(` sites in 5 files), B1 deadline pin, small unsat generator + twins, LSP smoke
  case, Tier 0 + one full core/test; NO compiler change. Licence: S1a + S1b landed, S0 headline confirmed by
  review. Branch `subsume-s2`, worktree `wt-subsume-s2`; S2 implementer launched (Opus, 4 h) in parallel with
  S0's fixes (S2 does not build on S0's code). S3 NOT needed on this evidence.
- 2026-09-16 ~21:50: S0 fixes applied: nanosecond accumulators — :648 CORRECTED to 2.79 s (23 %) of the
  bin/ermine run and 45.42 s (24.7 %) of the 184 s suite (fskvs 21.07 s + kindVars 24.35 s; 265 µs per
  subsumeType; max 5.8 ms), 12.1× :365 (the old floor-sum was 15.7–21× low); unchanged: 1,566 / 0 cycles /
  0 budget hits / 0.07 s refusal / 100 repetitions. Subst.scala now +157/−2 (inline defs, measure removed,
  Walk model in scratch patch). §0.2 gives six replacement sentences for SUBSUME-STAGE1A.md (:289, :396, :488),
  SUBSUME-STAGE1A-REVIEW.md (:226, :262), SUBSUME-STAGE1B-REVIEW.md (:215) — to be applied by the orchestrator
  at S0's landing. Ticket line added to TICKET-perf-type-inference.md (start at :648). S0 reviewer re-checking.
- 2026-09-16 ~22:20: S0 REVIEW re-check = LAND (§7 of the review; both corrected totals re-derived by the
  reviewer from the nanosecond traces: 2.785 s CLI, 45.418 s suite; flag-OFF zero records on the rebuilt tree).
  Three cosmetic residuals: two doc nits fixed by the orchestrator at landing; `SubsumeTrace.cse` counting inside
  the timed region (~0.03 %) NOTED, not applied (a code change). Landing in progress: stage commit on
  `subsume-s0`, merge, the six §0.2 replacement sentences applied to the landed S1A report and both Lean reviews
  as a doc commit, then Tier 0 + Tier 1 gates on the merged tree (Subst.scala changed) run by a gate agent.
- 2026-09-16 ~23:20: S0 LANDED. Stage commit bef7e7a7, §0.2 corrections 00abe6e6, merge d30cf94b, gate
  section commit on top; `subsume-termination` fast-forwarded. Landing gates (gate agent, logs
  scratch-subsume/gates-s0/): compile rc=0; TestLoopTrace with the model binary 720/720/720 (controls 46, 58);
  corpus 89/79/0 over 168, per-file verdict+message listing byte-identical to S0's baseline; repl-smoke 66/66;
  lsp-smoke 573 (the prompt's 577 is the post-S2 target, pre-change tree also 573); looptrace-corpus 18 groups
  3,210,869 segments all agree, 0 skip/hashdiff/eqdiff/fuel; trace-ab boot 54,209 and Wide 116,420 IDENTICAL
  after worktree-path normalisation (same-build control noise floor 0); ei-diff --snapshot 274/274 identical,
  3523 bindings identical; g1-validate 9/9. Programme tree = 478a369c + docs + S1a + S1b + S0. Disk 7.0 G.
  S2 (harness stage) implementer still running; S3 not needed.

## Closing sequence (the user, 2026-09-16 late evening) — starts after S2's review and fixes land

1. Land S2 on `subsume-termination` (review LAND, fixes applied, gates green, one commit).
2. Merge `subsume-termination` into `scala3-migration` (main checkout `ermine-scala`); one full `core/test`
   on the receiving branch before it counts as done.
3. Merge `scala3-migration` into `json-encode` (worktree `ermine-scala-wt-json`); full `core/test` there; then
   lift the `-Dermine.test.dateDiffReject` gate (commit dd9e0316) since the property is fast once S2's
   combinator is in.
4. 2.11 line: port the Scala pieces (S0 instrumentation, S2 harness fix, pins, smoke case) by hand onto
   `backport-2.11` (worktree `ermine-scala-wt-backport`) in the 2.11-and-3 dialect, the way the JSON stages
   were ported (Opus porter + reviewer); Lean/docs copy unchanged; full 2.11 test; then merge `backport-2.11`
   into `json-encode-2.11` (worktree `ermine-scala-wt-json211`); full test there.
5. Nothing pushed to any remote at any step.
- 2026-09-16 ~23:45: S2 implementer still running (launched ~20:30, 4 h budget). Reviewer launches on its report.
- 2026-09-17 ~00:20: S2 DONE (uncommitted on `subsume-s2`): `ErmineFixture.rejects` (False→Proof, one
  evaluation; `no` kept for the one forAll-bodied site TestScopes.scala:122), `bounded(ms)` deadline idiom,
  `loadNamed`/`outcomeOf` (shared warm session, no literalLock); 21 live `no(` sites in 6 files, 20 converted
  (TestRelations.scala's 7 are inside a block comment — dead code). Timings: B1 suite alone at default N
  1,282 s → 181–195 s (13/13); full core/test 1,698 s (1070/1070) → 524 s (1071 + TestLegend quarantine on its
  allowed re-run) = 1,174 s saved (69 %). Pins: (B1-bound) 4/4; new TestRowRefusals (16 unsat programs + twins,
  32 loads in one session, ~20 s, mutation-falsified); LSP smoke RowUnsat.e + 5 checks, server answers 58 ms
  after didOpen (lsp-smoke 573 → 578). Finding kept: a deadline pin wrapping loadStatements measures
  literalLock contention, not the check. Gates Tier 0 green (TestLoopTrace 720/720/720; corpus 89/79/0, 0
  verdicts differ; repl-smoke PASS); Tier 1 not triggered (nothing under core/src/main). Answer YES with S1b
  §8's limits carried. S2 reviewer launched (Opus).
- 2026-09-17 ~00:50: S2 REVIEW = FIX-THEN-LAND (`SUBSUME-STAGE2-REVIEW.md`; reviewer re-ran B1 suite alone at
  default N 189 s 13/13 all `proved`, TestRowRefusals 16 s, lsp-smoke 578 with the RowUnsat diagnostic at 78 ms,
  two mutations red; census 21 sites / 6 files confirmed; TestRelations.scala dead by nested block comment).
  Findings: F-1 (code, one conjunct) TestRowRefusals asserts only "refused:", not the row-label cause; F-2..F-7
  prose (sweep claim, `failsMatching` idiom uncited, model-vs-Scala wording in §5.1 + buildQueue hypothesis,
  literalLock docstring, run order, added-cost figure). Reviewer's signed answer: YES for this path, with S1b §8's
  limits. Findings sent to the S2 implementer.
- 2026-09-17 ~01:05: S2 fixes applied (F-1 cause conjunct in TestRowRefusals, 48 assertions, both mutations red
  for the right reason; F-2..F-7 prose/docstrings; report §8). S2 reviewer re-checking. On LAND: merge
  `subsume-termination` into `subsume-s2`, Tier 0 on the merged tree (S0's Subst.scala + S2's tests together:
  compile, B1 suite alone at default N, TestRowRefusals, TestLoopTrace with the binary, corpus --batch, smokes),
  commit, fast-forward; then the closing sequence (M1 ff into scala3-migration + full core/test; M2 brief; P211 brief).
- 2026-09-17 ~01:25: S2 REVIEW re-check = LAND (§6 of the review; residual R-1 cross-reference fixed by the
  orchestrator at landing). Stage commit b69b13de on `subsume-s2` (+ a follow-up restoring
  tracker/repl-classpath.txt, staged by mistake), merge 2ab2b3c4 with `subsume-termination` clean. Tier 0 gate
  agent running on the merged tree (S0 instrumentation + S2 harness together). On GREEN: fast-forward, then the
  closing sequence: M1 = fast-forward `scala3-migration` (still at the base 478a369c) + one full core/test in the
  main checkout; M2 (brief-M2-json-encode.md) and P211 (brief-P211-port.md) launched in parallel.
- 2026-09-17 ~01:50: S2 LANDED (gates GREEN on the merged tree: compile 15 pre-existing warnings; TestLoopTrace
  720/720/720; B1 suite at default N 13/13 all `proved` in 329 s under contention; TestRowRefusals 1/1; corpus
  89/79/0 over 168, normalised listing byte-identical to S0's baseline; repl-smoke 66/66; lsp-smoke 578; Tier 1
  not triggered, core/src/main unchanged since ccaf3b45). `subsume-termination` = d278c900.
  CLOSING SEQUENCE STARTED: M1 = `scala3-migration` fast-forwarded to d278c900 (it was at the base 478a369c);
  full core/test running in the main checkout (scratch-subsume/orch/m1-scala3-full-coretest.log). M2 (json-encode
  merge + B1 gate lift) and P211 (2.11 port + json-encode-2.11 merge) launched in parallel (Opus); report stubs
  pre-created at wt-json/tracker/satterm/SUBSUME-M2.md and wt-backport|wt-json211/backport/SUBSUME-2.11.md.
- 2026-09-17 ~02:25: M1 DONE: full core/test on `scala3-migration` at d278c900 = 1072 / 1072, 0 failed, 0 errors,
  wall 1,141 s under contention (M2 and P211 compiling at the same time; S2 measured 524 s alone), 378 properties
  `proved` (scratch-subsume/orch/m1-scala3-full-coretest.log). M2 and P211 running.
- (clock note: the machine is on MDT; entries above stamped "2026-09-17 ~00:20–02:25" were guessed and correspond
  to 2026-09-16 ~18:30–20:30 MDT; the order is right.)
- 2026-09-16 21:10 MDT: P211 DONE (uncommitted on both 2.11 worktrees; report backport/SUBSUME-2.11.md on both):
  Subst.scala +168/−2 (`@inline def` + by-name instead of Scala 3 `inline def`), TestErmine +127/−7 (two
  docstrings REWRITTEN: no literalLock on 2.11; eager `secure`), TestScopes, TestSigEntail, TestRowRefusals new;
  json-encode-2.11 additionally TestNamedFields:416. Census 19 live sites / 3 files on backport-2.11, 18
  converted (TestScopes:116 forAll kept); +1 on json211. Findings: (1) scalacheck 1.11.3 `Prop.secure` is EAGER
  so `rejects` buys status parity, not time (129 s before/after); (2) `bounded` + eager secure = class-init
  deadlock (16 × 180 s), fixed with the documented lazy `secure` shadow; (3) THE 2.11 LINE STILL ACCEPTS THE B1
  PROGRAM — Relation/Op.e's dateDiff signature is commented out there (F3 never back-ported) — so the generator
  uses `coalesce'` and no (B1-bound) pin / dateDiffReject gate exists on 2.11. Gates: backport-2.11 full
  735/735 (193 s) → 736/736 (125 s); json-encode-2.11 859/859 (354 s); converted suites 69/69 and 83/83 all
  `proved`; TestRowRefusals proved on both; flag OFF zero records; mutation red. Six shared files byte-identical
  across the two worktrees. Open: `ermine211` in backport/env-2.11.sh broken (`unset _ERM_BP`). P211 reviewer
  launched (Opus). M2 still running.
- 2026-09-16 21:40 MDT: M2 DONE (report wt-json/tracker/satterm/SUBSUME-M2.md): merge of scala3-migration
  d278c900 into json-encode = 9ec3406d, NO textual conflict (Subst.scala keeps json's five `sels` lines + S0's
  +157/−2; lsp-client.py both blocks); the one semantic conflict — json's dateDiffReject guard above S2's
  `rejects` — resolved by the gate lift (uncommitted: TestDateAndScan.scala, GATE-POLICY.md LIFTED paragraph,
  ticket item 12 CLOSED). Gates: compile; B1 suite alone 13/13 (519 s under contention); TestRowRefusals 48
  assertions; TestLoopTrace 720/720/720; corpus 89/79/0, 0 verdicts differ; repl-smoke 86; lsp-smoke 582
  (577 + 5; RowUnsat diagnostic 129 ms); check-corpus.sh 60/60; full core/test 1,199/1,199 in 1,218 s (run 2;
  run 1 had ONE red: TestRunner `(iso)` timed out queueing on literalLock behind TestDateAndScan's loads —
  S2 §2.3's rule; controls green). Follow-ups requested from the M2 implementer before review: convert
  TestNamedFields.scala:393 to `rejects` (parity with P211's :416), give `(iso)` `loadNamed`. Then M2 reviewer.
- 2026-09-16 22:20 MDT: M2 follow-ups applied (TestNamedFields:393 → `rejects`, proved; TestRunner `(iso)` via
  `loadNamed` under a unique name, 17/17; trio TestDateAndScan+TestRunner+TestNamedFields in one JVM 46/46;
  report §7). M2 reviewer launched (Opus). P211 reviewer still running. Then: commit the gate lift + follow-ups on
  json-encode; commit the port on backport-2.11 (explicit path list), merge into json-encode-2.11, commit the
  TestNamedFields:416 addition there; fast-forward scala3-migration to the final plan log; final report.
- 2026-09-16 22:35 MDT: P211 REVIEW = FIX-THEN-LAND (backport/SUBSUME-2.11-REVIEW.md; reviewer re-ran: converted
  suites 69/69, TestRowRefusals proved on both branches, flag-OFF writes no file, both mutations red, revert
  byte-identical; B1 acceptance on 2.11 REPRODUCED — Relation/Op.e:150-151 dateDiff signature commented out —
  a pre-existing back-port gap, not this port's). Findings: F-1 (code) TestRowRefusals:209 `getOrElse(Nil)` +
  scalacheck 1.11's `Prop.all(Nil) = proved` = vacuous pass on generator failure; F-2 the one-evaluation
  mechanism is `PropertySpecifier.update` by value (1.11) vs Function0 (1.15), not `secure`; F-3..F-6 doc.
  Extra gap: `sbt211` in backport/env-2.11.sh also has the unbound `_ERM_ROOT` bug. Sent to the porter.
- 2026-09-16 22:55 MDT: M2 REVIEW = FIX-THEN-LAND with doc-only findings (ticket:411 984,024→984,400; GATE-POLICY
  suite timing qualified per branch; report §4 timestamps; commit named paths only — docs/JSON-GUIDE.md is
  pre-existing untracked). Reviewer re-ran: B1 suite alone 13/13 all `proved` in 4:08, TestRunner 17/17,
  TestNamedFields 16/16, lsp-smoke 582 (81 ms diagnostic); merge resolutions verified byte-for-byte. Applied by
  the orchestrator and COMMITTED on `json-encode` (gate lift + TestNamedFields:393 + (iso) loadNamed + report +
  review) on top of merge 9ec3406d. json-encode = 2afeb426 + d278c900 + this commit; full run 1,199/1,199.
