# Signature entailment: closing the row-constraint hole in declared signatures

Opened 2026-09-10. Owner: the orchestrating session (Fable); each stage is implemented by a
fresh Opus agent and reviewed by another, against the acceptance criteria written here BEFORE
the stage starts. Nothing advances on an implementer's word alone. Funded by the user
2026-09-10 ("Pin the bug, then design an orchestration loop").

Branch `sig-entail`, worktree `~/research/ermine/ermine-scala-wt-sig` (from `a15a97e`). The
LSP roadmap loop owns the main checkout and its Stage-4 invariant forbids `Subst` changes
there; this loop lives in its own worktree with its own `target/` so the two never share a
JVM or a tree. Merge into `scala3-migration` only at S5, when the LSP loop is at a gate.

## The defect

`healthOpt : forall r. {..r} -> Int; healthOpt r = r ! health` is accepted; `healthOpt
{position = 2.0}` evaluates to `<error: key not found: health>`. A declared signature's ROW
constraints are never checked against the body's obligations. `Subst.subsumeType`
(Subst.scala:527-553 at a15a97e) partitions the inferred residual by `Type.fskvs` into
skolem-free `ds` and skolem-mentioning `rs` -- the obligations -- runs `entails(qs, r)` on
each and discards the Boolean (:535-536), then returns only `ds` (:553). `entails` (:313) is
class-only, `entail` (:394) is gated on `isClassConstraint`, and `restrictTypes(tts)` (:540)
removes what the skolem-escape check (:543) would need. Callers instantiate the DECLARED
type (the .ei publishes it). Upstream TODO at :639. Present since the initial export.

Why nothing caught it: the solver only REFUTES (its one rigid-variable rule is `makeEmpty`'s
skolem refusal, Constraints.scala:945/2142), and `sk <- ((|health|), s)` with `s` fresh is
satisfiable; the missing check is entailment of wanteds by givens. The Lean development
(`tracker/lean`, `tracker/loopmodel`) models constraint systems and the solver loop only:
no terms, no typing judgement, no progress/preservation, `Entails` (Basic.lean:64-68)
one-sorted over all variables, no given/wanted split, skolem only as a string tag
(Loop/State.lean:275, Loop/Step.lean:136). The mechanism is listed in
`TICKET-row-constraint-decision.md:816,843` as a "rejection channel", never as a hole.
Distinct from `incomplete/README-unsound.md` (unsatisfiable sets accepted at call sites).

Pins (S0, this commit): `core/examples/shouldfail/sig01..sig04`, `shouldfail-controls/
control08_sig_declared.e`, `RESULTS.md` §"Pinned, class 6", `TestSigEntail.scala`
(KNOWN HOLE properties assert today's behaviour; flip at S3). Observed 2026-09-10: sig01,
sig02, sig04 ACCEPTED under all/cut/nongen; **sig03 (let-bound) is REFUSED at the call
site** -- explained by S1: the renamer drops let-bound signatures (a second bug, see below);
**sig05 (expression annotation) ACCEPTED** -- the `ann` site is live (S1 review).

## The missing judgement

At every `subsumeType(declared, inferred)` where `declared` is a user signature: let `Q` be
the signature's constraints with its quantified variables rigid (skolems), `W` the body's
residual wanteds that mention a skolem, `F` the solver-minted (flexible) variables of `W`.
Require

    for every model rho of Q, there is rho' agreeing with rho off F such that rho' models W.

Skolems universal, minted variables existential. Under the one-sorted reading
`Entails [] (sk <- ((|health|), s))` is already false, so a naive check rejects sig01; the
existential over `s` is what keeps `healthWith` (control08) accepted. The practical decision
procedure for the common shape (a concrete-label extension of one skolem, i.e. every wanted
`!`, `cons`, `\`, `modify` generates): `Q` entails `L ⊆ sk` iff `Q ∪ {sk' <- (sk, L)}` is
unsatisfiable for fresh `sk'` -- a refutation the solver already performs. Precondition: `Q`
satisfiable (Basic.lean:525 `entails_iff_forall_label` needs it; a signature with
unsatisfiable givens is vacuous -- policy decided at S2). Wanteds of other shapes (a skolem
inside the parts, several skolems) are S2's design question; the fallback is "must appear
literally among the givens", with a warning, never silence.

## Stages

Gates per `tracker/GATE-POLICY.md`: Tier 0 before every commit; Tier 1 when `Subst`/`Type`/
solver/executable Lean changes (S3, S4); Tier 2 (full core/test alone + interleaved A/B) on
the adoption commit (S5). ONE JVM at a time inside this worktree; never while the LSP loop's
agent is measuring in the main checkout (check `pgrep -af sbt-launch` and the mtimes under
`tracker/loopmodel/` before a Tier run).

### S0 -- pin (DONE 2026-09-10, this commit)
As above. Acceptance: the four shouldfail modules and the control carry headers with today's
verdict and the mechanism; `TestSigEntail` green in this worktree; RESULTS.md section.

### S1 -- measure before enforcing (warn-mode survey)
Implement the probe, NOT the check: a flag `ermine.sigEntail` = `off` (default) | `warn`.
Under `warn`, at the two `subsumeType` call sites that check a user signature
(`typeCheck` :638, `typeCheckExplicitBinding` :655), print one line per skolem-mentioning
wanted: module, binding, position, the wanted (pretty), the givens (pretty), and a
SHAPE tag (`concrete-ext` = one skolem lhs, concrete labels + one fresh remainder;
`skolem-in-parts`; `multi-skolem`; `other`). Also record whether the wanted appears
LITERALLY among the givens (alpha-equivalent up to the fresh remainder). Then sweep the whole
corpus (stdlib 161 + core/examples, `corpus-run.sh` per-file default is fine; `--batch` is
acceptable for a count) under `warn` and classify every hit:
  (a) literally given; (b) not literal but a human can see it is entailed (sample 20, argue
  each); (c) NOT entailed -- a real hole in shipped code (list them all, with the call that
  would crash if one exists).
Deliverables: `tracker/loopmodel/SIG-1-SURVEY.md` with counts per shape and per class, the
full (c) list, and THE SIG03 EXPLANATION: trace why the let-bound twin is refused at the
call site (which residual survives, where it lands, why the top-level path loses it) and
whether that mechanism is reusable for the fix. No entailment logic. Acceptance: Tier 0
green with the flag off (shipped behaviour byte-identical: repl goldens, TestSigEntail
unchanged); the survey's totals reproduce from a command line in the report; every (c) item
has a file:line.
Stop point for the user: if (c) is non-empty in stdlib.

### S2 -- design the check, on paper, with the Lean statement
Input: S1's shape table. Output: `tracker/loopmodel/SIG-2-DESIGN.md` fixing (i) the exact
judgement (above) and the policy for unsatisfiable givens; (ii) the decision procedure per
shape: refutation trick for `concrete-ext` (with the fresh `sk'` encoding of lacks), literal
match with warning for the rest, and what the error message says; (iii) where in `Subst`
it runs (inside `subsumeType`, guarded by "e1 is a user signature" -- how that is known
at :638 vs :655 vs the App case :918-924, which must NOT run it); (iv) interaction with
`restrictTypes(tts)` at :540 and `mkSimplified` at :553; (v) the blame: which `Located`
carries the wanted, and the "declared at" secondary location. Lean: add a `flavour :
Var -> Rigid|Flex` (or an existential closure on the wanted set) to `Rowpartition/Basic`,
state `SigEntails Q W F`, and prove `sigEntails_concreteExt_iff_refute` -- the refutation
trick is sound and complete for the `concrete-ext` shape given `Q` satisfiable -- from
`entails_iff_forall_label` (Basic.lean:525) and the conservative-extension lemmas
(Rules.lean:412 `ConservativeExt`, RoseTheory.lean:971/1001). Acceptance: `lake build` +
audit green; the design names every code site by line; the reviewer tries to break the
judgement with a program the procedure accepts but that crashes, or rejects but is fine
(controls: control08's four spellings, `consRow`/`pRecord`/`withRunning` in Lang/Helpers.e,
the `Has` helpers in Ai/Common.e).
Stop point for the user: read the design before S3 starts.

### S3 -- implement, flagged
`ermine.sigEntail` gains `error`. Default stays `off` in this stage. Under `error`, the
check rejects with the S2 message and blame; under `warn`, it prints; `off` is byte-identical
to today. Flip the pins: sig01/sig02/sig04/sig05 headers to "rejected", RESULTS.md, and
`TestSigEntail`'s KNOWN HOLE properties to `no(...)` -- the suite must run those under
`error` without `System.setProperty` on a per-call flag (the fixture rule at the top of
TestErmine.scala; use the fixture's session-option mechanism). Tier 1. Acceptance: under
`error`, shouldfail sig01/02/04/05 rejected with the designed message (05 through the
`ann` site, `Subst.typeCheck`); sig03 still rejected
and its blame now on the signature/`!`; all controls load; corpus sweep under `error` equals
S1's (c) list exactly (nothing more rejected, nothing less); `.ei` diff under `off` empty.

### S4 -- editor parity
`session/TolerantCheck.scala` reaches `subsumeType` on its own path (:277, :321). Under
`error` the LSP must report the same diagnostic at the same position; pin it in
`TestTolerantCheck` and a fixture under `tracker/lsp-tests/`. Coordinate with the LSP loop:
this is the one stage that touches an editor-path file -- land it between LSP items, and
re-run lsp-smoke. Acceptance: lsp-smoke baseline unchanged under `off`, +N checks under
`error`.

### S5 -- adoption (the user's call)
Present S1's (c) list with fixes for each affected module (honest signatures), the perf
figure (one small solve per explicit signature: interleaved A/B on the stdlib boot and
Report.e), and the recommendation. If the user flips the default to `error`: Tier 2, merge
`sig-entail` into `scala3-migration` at an LSP gate, corrected modules committed with it.
`warn` as default is the fallback if (c) is large.

### S6 -- back-port
`backport-2.11` (worktree `ermine-scala-wt-backport`) has the same `subsumeType`; cherry-pick
S3 and its pins after S5.

## Orchestration

Per stage: brief `tracker/loopmodel/briefs/brief-SIG-<n>.md` -> fresh Opus general-purpose
implementer (background, in the worktree) -> fresh Opus reviewer with
`brief-SIG-<n>-review.md` re-running the stage's tier ONCE -> orchestrator applies review
edits, runs Tier 0, commits code + report + this file's tick + a log line -> next brief.
Agents never commit, never touch `tracker/lean/` except in S2 (Lean-only stage, no JVM),
delete every `.ei` they cause, and stop at the stop points above. Verdicts on reviews are the
orchestrator's (FIX-THEN-ADVANCE edits applied; BLOCK -> a fix round to the implementer).

## Checklist

- [x] S0 pin (2026-09-10)
- [x] S1 survey (2026-09-11; STOP POINT FIRED: 7 stdlib signatures not entailed)
- [x] S2 design + Lean statement (2026-09-11; STOPPED: the user reads SIG-2-DESIGN.md before S3)
- [x] S3 implement (2026-09-11; DEFAULT error by the user's decision; S3b: 19 signatures corrected + 7 forced callers; S3c: class status note)
- [ ] S4 editor parity -- PARTLY in S3 (TolerantCheck reaches the check; two properties; lsp-tests/SigEntail.e); remaining: the ambient-meta flavour measurement under warn, D5 (interfaceKey reads the process mode, the check the session mode)
- [x] S5 adoption (the user: error; LANDED on scala3-migration 2026-09-12)
- [ ] S6 back-port

## Iteration log

- 2026-09-10 S0: pins written and verified in the REPL (sig01/02/04 accepted + crash,
  sig03 refused at 32:12, control08 loads). TestSigEntail 6/6 in this worktree.
- 2026-09-11 S1 DONE (implementer report SIG-1-SURVEY.md, review SIG-1-REVIEW.md,
  FIX-THEN-ADVANCE applied). Probe `ermine.sigEntail=off|warn` (SigEntail.scala; NOT in
  GenRules, which is half of the interface key). Sweep 158 files: 1,502 hits, 914 row
  obligations. NOT entailed: 12 signatures / 32 wanteds -- 7 in the stdlib (unify1,
  partialLookup, cons_Bracket, Keyed.softRelation, Keyed.keyValueTabular, cutoffs, others),
  5 in examples (melt2/3/4, melt3Simple, runningTotalFullViaWritten); 8 have runtime
  witnesses (rename of a missing column, a header lacking a column, a record outside its
  type, union column mismatch). STOP POINT FIRED. Taxonomy (reviewer's independent re-tag
  agrees): the refutation trick covers 20/914 as stated, 43/914 = 4.7% with the dual for
  `X <- (L, sk)`; 871/914 have no concrete label at all and are out of reach of any
  refutation-shaped procedure ("X meets sk" is not "X is inside sk") -- S2 must handle
  variable-only wanteds by a different route. SECOND BUG: rename/Lower.scala drops
  let-bound signatures (regression: stub 284afe1, sole path since faa5769); no LSP test
  pins it; ticket for the LSP loop. Annotation site live: pin sig05 added. Tier 0 off:
  corpus 88/70/0 of 158, off-vs-warn 0 differ and .out byte-identical, .ei 129/129
  identical vs g1-baseline and off-vs-warn, repl-smoke 8/8 (with the WORKTREE classpath --
  tracker/repl-classpath.txt is checked in with absolute paths into the main checkout),
  TestLoopTrace 3/3, TestSigEntail 8/8 after this commit.

- 2026-09-11 S2 DONE (design SIG-2-DESIGN.md 655 lines, Lean Rowpartition/SigEntail.lean 796 lines /
  46 theorems / 0 sorry, build + audit 4670/0; review SIG-2-REVIEW.md FIX-THEN-ADVANCE, all ten
  edits applied, Lean unchanged). Judgement: F = vars(W) ∩ pxs \ vars(Q); R = (vars(Q) ∪ vars(W)) \ F;
  W = closure of rs under shared F variables (= rs on this corpus; S3 adds a ds column to the probe
  and re-states the criterion). Procedure: per label class (literal labels + one generic), one-hot
  propositional encoding, 2QBF by search with the solver's propagation rules; solver only for Q's
  satisfiability on the rejecting path; unsat Q vacuous + own diagnostic; NO VERDICT = warn + accept,
  REJECT outranks. Crux sigEntails_of_lsig. Executable oracle sigcheck.py: 309 signatures = 288
  accept / 21 reject / 0 undecided (4 pins + 12 S1 (c) + 5 NEW in Time/Helpers.e: dayCount,
  monthsBetween, monthsSince, daysSince, daysUntil -- S1's triage script never enforced shared
  choices) => 17 dishonest signatures, 7 stdlib. Reviewer: brute force on 36,000 random systems and
  an independent DPLL agree on all 309. Decided: ambient metas RIGID (conservative; S4 measures).
  S3 checklist has 13 items incl. a core/test differential vs the oracle and the Part-shape contract.

- 2026-09-12 LANDED: sig-entail fast-forwarded onto scala3-migration. Merged tree gates: full
  core/test alone 1061/1061; corpus batch error vs off differs in exactly the five pins; .ei error vs
  off: 5 of 274 differ, bindings identical 3494 / order-only 26 / alpha 3 / other 0 (the same-config
  floor is worse: other 27); repl-smoke 8/8; lsp-smoke 551; g1-validate EQUIVALENT, baseline re-cut.
  Open: S4 remainder, S6 back-port (2.11 has the same subsumeType), the class-constraint hole
  (SIG-3-CLASS-STATUS.md: same hole, pin it, fix constraint heads in the renamer, then the class
  check), keyValueTabular's degenerate wrapper (ticket), cutoffs NO VERDICT (decidable in principle).

## Blocked / Awaiting the user (after S2)

0. Read tracker/loopmodel/SIG-2-DESIGN.md before S3 starts (§(a) the judgement, §(b) the procedure,
   §(e) the S3 checklist, "Open questions"). OQ1 (the five Time/Helpers holes) and OQ4 (warn vs error
   default, now 17 signatures) are yours; OQ2 decided conservative; OQ6 (class constraints stay with
   generalisation) needs a yes.

## Blocked / Awaiting the user (after S1)

1. The seven stdlib signatures: fix them in this loop (S5 folds the corrections in) or
   look at them first. `unify1` has no caller; the Keyed wrappers have none in the corpus;
   `cutoffs`/`others` are private behind `cutoffDrilldownRel`.
2. S2's scope: the plan's refutation trick decides 4.7% of the obligations. The general
   case (variable-only wanteds) needs a different decision procedure -- S2's brief must
   ask for one, with the Lean statement covering it.
3. The let-signature drop in rename/Lower.scala: a ticket for the LSP loop (it owns the
   file; its Stage-4 rules forbid Subst changes but not Lower), or a stage here.
