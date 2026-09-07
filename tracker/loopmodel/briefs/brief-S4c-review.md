# Review brief: S4c — the correspondence lemma and the S2 chain at `topNormalise = true`

You are reviewing stage S4c in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `414913b`
plus the UNCOMMITTED S4c deliverables). The implementer's brief is `tracker/loopmodel/briefs/brief-S4c.md`; its report
`tracker/loopmodel/S4C-CORRESPONDENCE.md`; its changes: NEW `tracker/lean/Rowpartition/Loop/TopNormalise.lean` (1,476
lines, 109 theorems), `Loop/NoFalseAccept.lean` and `Loop/PolicyStep.lean` (the six theorems that carried
`htn : fl.topNormalise = false`), `Rowpartition.lean` (root import), `tracker/loopmodel/S4Top.lean` (now a pointer), the
plan row S4c in `tracker/LOOP-MODEL-PLAN.md`, the "AT ADOPTION" block in `tracker/ROW-CONSTRAINT-STATE.md`. Context:
`tracker/loopmodel/S4B-REVIEW.md` §2.2 / §5.2 / H-9 (why these two items were the adoption prerequisites),
`S4-CHANGE.md` §1, §7 and "Fix round (S4B)" FR-1. You edit NOTHING except a scratch directory
`/home/dmitry/.claude/jobs/880c725d/tmp/review-S4c/` and your report `tracker/loopmodel/S4C-REVIEW.md`. Lean:
`export PATH=$HOME/.elan/bin:$PATH`, `LEAN_NUM_THREADS=2`, `lake env lean <scratch file>` for your own checks; the
library is already built (`lake build` is a no-op — you may run it once to confirm; nothing else is running on the
machine). One JVM at a time (`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, sbt allowed for TestLoopTrace);
delete every `.ei` you cause; no commits. Never `lake exe cache get`, never add a `require`, never touch
`Rowpartition/CutSearch.lean` or `~/research/leanwork`. The orchestrator has already re-run: `lake build` 868 green,
`Audit.lean` 4,282 / 0 non-standard, `#print axioms` on 17 key theorems (standard three), TestLoopTrace 720/720, and
confirmed the executable closure (`Main/Json/Seed/PolicyReplay/Replay.lean`) is untouched and `looptrace` not rebuilt.

1. **The statements are the right statements.** Read `TopNormalise.lean` in full. (a) `topFamilies_eq` /
   `topNormalise_eq` are `rfl`: confirm they relate `Json.lean`'s EXECUTABLE functions to the spec and not a copy of
   them, so `topNormalise_ssat_iff` really is about the code the differential runs. (b) `TnOk` (five fields): which
   are proved from the code (`tnOk_of_buildQueue`: `buildQueue_qok`, `buildQueue_no_self`), which are assumed
   (`Wf.coh`, `SupOk`, `SupFresh`) — are those the development's standing assumptions (cite where `run_noLoss` /
   `run_ssat_iff` take them), and are they TRUE of the seeds the compiler emits (the `sin`/`scon` supply counter)?
   (c) `sysQ`: is it the same reading of the queue the S2 chain's `liveInput`/`decideLabels` use? (d) The
   `nodup` side condition on concrete parts: does the Scala (`Set`) guarantee what the Lean (`List.Nodup`) assumes,
   and is there an input where they diverge (an L2 question — the 3.2M-segment differential says no; look at the
   code path anyway). (e) Non-vacuity: `exQ_fires`/`exQ_tnOk`/`exQ_sys`/`exQ_equiv` — is the witness a k ≥ 3 family
   that actually fires under `topNormalise true`? Try to state a hypothesis of any main theorem that no real queue
   satisfies.
2. **No weakening of the S2 chain.** `git show HEAD:tracker/lean/Rowpartition/Loop/NoFalseAccept.lean` (and
   `PolicyStep.lean`) against the working copies: for each of the six theorems, the old statement, the new, and
   whether the `_off` corollaries recover the old VERBATIM (elaborate a scratch file that states the old theorem and
   proves it from the new). Is `htn` as an equation about a total function ever vacuous? Do the four `_input`
   theorems say what §2 claims (accepted ⇒ `SSat` of `buildQueue`'s own queue plus `envFacts`; faithful to the input
   via `NoLoss.trans`)? Are the three no-verdict/budget escapes still stated where they were?
3. **Adversarial.** Since `topNormalise_ssat_iff` is a theorem, attack the HYPOTHESES and the READING: a queue with a
   self-read, duplicate parts, two families sharing a remainder, a family whose lhs is another's carrier, a concrete
   row one link away (the S4B seeds `H1..H22` in `/home/dmitry/.claude/jobs/880c725d/tmp/review-S4B/seeds/` are
   the shapes) — for each, does `TnOk` hold, does the rule fire, and does the model's verdict match what the
   theorem predicts? Anything where `tnOk_of_buildQueue` cannot be applied is a finding.
4. **Gates, re-run:** `lake build`; `lake env lean Audit.lean`; `#print axioms` over EVERY new or changed
   declaration (the implementer's list is `/home/dmitry/.claude/jobs/880c725d/tmp/S4c/axioms.out`, 123 entries —
   regenerate it yourself, no `sorryAx`/`nativeDecide`); TestLoopTrace 720/720; `git diff --stat` shows no
   executable Lean changed and `looptrace`'s mtime predates the edits.
5. **Prose and the adoption question.** Is the report accurate, statement by statement? Is the plan row right? Is
   the state file's "AT ADOPTION" block now correct in saying the two Lean prerequisites of `S4B-REVIEW.md` §5.2
   are met? Then answer plainly, as that review did: **should `-Dermine.topNormalise` be flipped ON by default now?**
   State what (if anything) must still precede it — the missing `LoopStrict` constructor for the mint half, the
   fact that the Scala↔model link is the differential and not a proof, the two adoption obligations (`proj01`
   leaves `shouldfail/`, clear `.ei` once) — and what the flip would change for a user (the diagnostic-text moves
   of S4B H-3).

Findings prefixed `J-`, ranked, each CONFIRMED (you ran it) or PLAUSIBLE. Verdict: ADVANCE / FIX-THEN-ADVANCE /
REDO, plus the adoption recommendation. Write the report early and keep it current.
