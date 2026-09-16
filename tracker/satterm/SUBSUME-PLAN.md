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
