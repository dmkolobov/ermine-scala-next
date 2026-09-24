# Does the checker terminate on a refused row program? `subsumeType`'s escape check

A programme for a **Fable orchestrator** driving **Opus sub-agents**. The orchestrator
plans, writes the briefs, launches agents in their own worktrees, merges, runs the gates
it owns, commits reviewed green stages, and keeps the handoff log; every proof, every
measurement and every line of Scala is written by an Opus agent and reviewed by a
different Opus agent. The orchestrator never proves, never implements, never reviews.

Branch `scala3-migration` (tip 5557ba39). Programme branch `subsume-termination`, worktree
`~/research/ermine/ermine-scala-wt-subsume`; stage branches off it, one worktree each
(`ermine-scala-wt-subsume-<stage>`). Not a JSON item: the JSON Stage 2/3 programme
(branch `json-encode`, 2026-09-16) only exposed it.

Three deliverables, in order, each gated on the one before:

1. **Make the check terminate** on the input below, with a proof of why it now does.
2. **If (1) cannot be had**, bail out under a **budget**: a bounded computation whose
   exhaustion is a counted, traced, safe outcome — never a silent acceptance, never a
   hang — with a proof that the bounded check is sound and that exhaustion is reachable
   only where the unbounded check would not have answered.
3. **Motivate and prove** whatever ships in `tracker/lean/Rowpartition/`, audited
   (`Audit.lean` 0 non-standard; `#print axioms` on every new declaration), BEFORE the
   Scala changes; design changes ship behind a flag, default OFF; adoption is the user's.

---

## Part A — for the orchestrator (Fable)

### Method (unchanged from the row programmes, and it is the point)

Lean leads, code follows. Our own reasoning is not trustworthy here: on 2026-09-16 the
orchestrator's first explanation of this very hang (cross-suite cache pollution) was
wrong and was refuted only by an agent reproducing the hang with the suite alone. So no
hypothesis in this document is a finding; the agents measure and prove, and you record
what came back. **Prefer a proven negative (a witness, a non-existence) over an asserted
limitation.** `tracker/lean/README.md` is the per-theorem authority — verify, don't trust.

### Stages, agents, parallelism

| Stage | Branch | Opus agent(s) | Depends on |
|---|---|---|---|
| S0 diagnosis | `subsume-s0` | 1 implementer (instrumentation + measurements), 1 reviewer | — |
| S1a substitution model | `subsume-s1a` | 1 Lean prover (H1/H2: the kind-variable walk over a substitution) | S0's numbers only to READ; starts in parallel with S0 |
| S1b rejection-path model | `subsume-s1b` | 1 Lean prover (H3: the loop model on unsatisfiable inputs) | same; parallel with S0 and S1a |
| S2 the fix | `subsume-s2` | 1 implementer, 1 reviewer | S0 + whichever of S1a/S1b licenses it |
| S3 budget (only if S2 reports "not available") | `subsume-s3` | 1 implementer, 1 reviewer (a different one from S2's) | S2's negative result, proved |

Maximum parallelism: S0, S1a and S1b start together, three worktrees, three JVMs/Lean
builds concurrently. S2 starts the moment its licensing theorem is reviewed, even if the
other S1 lane is still running. One reviewer per stage, never the implementer, launched
with the review brief below. Every agent is launched with `model: opus`.

### What you do yourself, and only this

- Write `tracker/satterm/SUBSUME-PLAN.md` (stages, worktrees, handoff log — append after
  every event) and `tracker/satterm/briefs/brief-S<n>.md` from Part B before launching.
- Create worktrees; merge `subsume-termination` into a stage branch before its landing;
  resolve doc conflicts yourself, never code conflicts (hand those to the implementer).
- Run the landing gates (Part A "Gates") **as harness-tracked background commands, never
  `nohup`** — a `nohup` job never notifies the orchestrator; the JSON programme lost
  three hours to that on 2026-09-16. If a run must be detached, schedule a poll.
- Commit only a reviewed green stage, one commit per stage, with the reviewer's verdict
  cited. Never push, never merge into `scala3-migration`, never flip a default.
- Save every report an agent returns into `tracker/satterm/` when the agent's harness
  cannot create `.md` files (it usually cannot; editing an existing one works).
- When an agent's result contradicts a hypothesis in this document, the document loses.

### Gates (tracker/GATE-POLICY.md; this is solver work)

Tier 0 before every commit. Tier 1 for any change to `Subst.scala`, `Constraints.scala`
or executable Lean: the 18-group `looptrace-corpus.sh` differential with `LOOPTRACE_PAR`
(the `looptrace` binary comes from `cd tracker/lean && lake build looptrace`; the
`ermine-scala-wt-json-wrappers` worktree already has one you may point `-Dermine.looptrace=`
at), `trace-ab.py` over all record kinds against a pre-change run, `ei-diff.sh --batch`
with `loadInSeries` both sides, `g1-validate.sh` (an intended signature change refreshes
the baseline in the same commit). Corpus verdicts **89 LOADED / 79 REJECTED / 0 UNKNOWN
over 168 must not move**: a rejection that becomes an acceptance, or the reverse, is the
one thing this work must not do. Tier 2 on the adoption commit only: full `core/test`
alone (1130 on this branch; the B1 property un-gated), interleaved perf A/B
(`perf-bench.sh batch -n 3`, old/new/old/new, load < 1.3) since `:648` is on every
explicit-signature check. Plus: the B1 property green ALONE three times and inside the
full suite once; `lsp-smoke.sh` 577 checks; a new smoke case that opens the B1 program in
the resident session and receives a diagnostic within the debounce ceiling.

### Reports

Per stage, `tracker/satterm/SUBSUME-STAGE<n>.md`: what was measured, what was proved
(theorem names, axioms), what was built, gate numbers with log paths, and — separately
and plainly — whether the title question's answer is *yes*, *no*, or *bounded*. Your own
final report to the user: the same, per stage, with commits.

---

## Part B — what every agent reads first (shared evidence)

### The defect, with the evidence

`scalacheck-binding/src/main/scala/TestDateAndScan.scala:192`,
*"a dateDiff combine over a relation WITHOUT the dates is now REJECTED (B1)"*:

```
import Prelude
import Relation.Op as Op
import Syntax.Relation
field startDate, endDate : Date
field gap : Int
field name : String
people : [ name ]
people = relation [ { name = "Ada" } ]
bad = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap people
```

`no(typeChecks(...))`: `people`'s row lacks `startDate`/`endDate`, so the checker must
REFUSE `bad`. Its twin with `spans : [ name, startDate, endDate ]` checks and passes.

- Run alone — `sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'` — on
  scala3-migration 5557ba39 (this tree), json-encode 17cdcbd1 and json-runner 1ed1d60c,
  the property **never returns**: 11 of 12 properties finish; one thread stays RUNNABLE
  at 100%+ CPU, GC idle, for as long as anyone waited (28 CPU-minutes seen), always in
  these frames (jstack, three JVMs, identical):

  ```
  com.clarifi.reporting.ermine.Type$$anon$3.vars(Type.scala:651)     x ~11, then :649
  HasKindVars$$anon$3.vars(Kind.scala:125)          foldRight over the env's type map
  Kind$.kindVars(Kind.scala:96)
  SubstEnv.kindVars(Subst.scala:169)                Kind.kindVars(kinds) ++ Kind.kindVars(types)
  Subst$.subsumeType(Subst.scala:648)               escs = hm.fskvs.filter(..) ++ hm.kindVars.filter(skss(_))
  Subst$.typeCheckExplicitBinding(Subst.scala:775)
  Subst$.inferBindingGroupTypes(Subst.scala:885)
  Session$.loadModule(Session.scala:1054) ... ErmineFixture.typeChecks(TestErmine.scala:178)
  ```
- Inside a full `core/test` the same property PASSED every recorded run (1070/1070 on
  2026-09-13 through 1170/1170 on 2026-09-16) and then wedged three landing runs on
  2026-09-16 once two new suites ran before it in the JVM. The only difference is the
  `Supply` ids the solver draws, i.e. the order its search takes.
- On `json-encode` the property is gated behind `-Dermine.test.dateDiffReject=true`
  (commit 3374deaf; GATE-POLICY.md; TICKET-editor-and-solver-followups.md item 12). On
  THIS branch it is not gated, which is what the reproduction wants.
- The row-sound decision procedure already carries a budget (`Constraints.scala:1236-1242`,
  `-Dermine.rowSound.budget`, default 200,000 nodes, exhaustion counted in
  `GenRules.rowSoundBudgetHits` and traced by `RowTrace.rowSound`; the theorem in
  `tracker/loopmodel/S2-DESIGN.md` carries the budget as a hypothesis). It does not cover
  the frames above.
- Why it matters beyond one test: the LSP runs a check to completion on its dispatch
  thread (`lsp/Diagnostics.scala`, Decision 3), nothing cancels it, and the VS Code
  extension has no watchdog. A user who types that line gets a server that pins a core
  forever and answers nothing until `Ermine: Restart Language Server`.

### Known, and three hypotheses that Stage 0 must SEPARATE by measurement

Known: order-dependent; on the REJECTION path; the spinning frames are the
escaping-skolem check at `Subst.scala:648`, which exists only to build the "did not
subsume" message and walks the kinds of EVERY type in `SubstEnv.types` through an
unmemoised `foldRight` with `Vars ++` (`Vars.scala:22`, a lazy nested view);
`Kind.scala:96-98` carries *"NO empty-map fast path here, deliberately -- see roadmap P7
Step 1"*, so this walk has been on the perf roadmap before.

- **H1, finite but explosive.** The failed refutation leaves `hm.types` enormous
  (`restrictTypes` at :642-645 runs before :648 but may not delete what a rejection
  left) and the walk is super-linear on it. Termination holds; the checker is merely
  astronomically slow.
- **H2, cyclic substitution.** `VarT(v) => v.extract.vars` (`Type.scala:653`) follows a
  variable's binding; a variable bound to a type that mentions it (through any chain)
  makes `vars` non-terminating. The observed stack was SHALLOW (about a dozen `AppT`
  frames), which fits a short cycle as well as a wide walk.
- **H3, the walk is the victim.** The rejection path itself grows the environment or
  diverges BEFORE `subsumeType`; `:648` is only where the thread was sampled. Whether
  this input's path passes through `labelDecide` (and hence the rowSound budget) at all
  is an open question.

### Rules every agent keeps

`tracker/GATE-POLICY.md` and its parallelism rules; the 2.11-and-3 Scala dialect is
irrelevant here (this branch is Scala 3 only) but no new dependency and no `nohup`. Work
only in your own worktree; do not commit — the orchestrator commits; never push. Trace
and instrumentation flags default OFF. Every claim in your report carries a log path or a
theorem name. Budget: the hours in your brief; at the budget, write up and stop.

---

## Part C — briefs the orchestrator writes (one file each, from these)

### brief-S0 — diagnosis (Opus implementer, 3 h)

Reproduce the hang alone, then separate H1/H2/H3 with instrumentation behind
`-Dermine.subsumeTrace=true` (default OFF): on entry to `subsumeType` for `bad`, record
`hm.types.size`, `hm.kinds.size`, the number of `++` nodes in the `kindVars` view,
whether `Type.fskvs(types)` returns; sample `jcmd Thread.print` every 30 s for five
minutes and diff the `v.extract` targets — a repeating set is H2, a `types.size` growing
before :648 is H3, a fixed large size with the walk never returning is H1. Then the
control: the SAME program under a favourable order (inside the full suite, or by seeding
the `Supply`) — same path and merely finishes, or a different path? `RowTrace`
(`-Dermine.rowTrace`) says which rules fired; compare the two traces with `trace-ab.py`.
Also: does the path go through `labelDecide`? Does the rowSound budget ever count? Write
`tracker/satterm/SUBSUME-STAGE0.md`: numbers, the traces' paths, which hypothesis
survives, and a minimal reproduction smaller than B1 if one exists. No fix.

### brief-S1a — the substitution model (Opus Lean prover, 4 h)

New `tracker/lean/Rowpartition/SubsumeEscape.lean`: a substitution as a finite map from
variables to types over a small syntax (`Con`, `App`, `Var`, enough binder structure for
`Forall`/`Exists` kinds), the kind-variable collection as a function over it, and the
property *"the collection terminates for every well-formed substitution"*, where
well-formed is the invariant the solver is supposed to keep (acyclic bindings). State
the invariant precisely. Two theorems, whichever the model yields: termination under the
invariant, with the collection restricted to the SKOLEMS' kind variables (`sks`/`sts` and
the types they occur in — the obvious cheap `X`, since `escs` is filtered by
`skss`/`stss` anyway) proven to give the SAME verdict as the whole-environment walk; or
a WITNESS that a well-formed substitution can still make the walk unbounded, in the
style of `DefaultSatDiverge.lean`. `lake build`, `Audit.lean` 0 non-standard,
`#print axioms`, README entry. Read S0's write-up when it lands, but do not wait for it.

### brief-S1b — the rejection path (Opus Lean prover, 4 h)

Extend the loop model (`Loop.lean`, `tracker/loopmodel/`) with the rejection path this
input takes (from S0's trace when available; from the rules before that): is the step
relation well-founded on UNSATISFIABLE inputs, i.e. does refutation terminate?
`KeyedSplit.lean`/`KeyedRow.lean` are the precedent for a terminating guard and for a
witness that a guard does not survive a deletion. If a cyclic binding is reachable on
this path, produce it as a witness (that is H2's upstream cause and the fix is at the
binding site — an occurs check — with its own theorem). Same build/audit/README rules.

### brief-S2 — the fix (Opus implementer, 5 h; needs S0 + a reviewed S1 theorem)

If S1 gives termination under an invariant the solver keeps: implement the cheaper /
memoised escape check keeping `:648`'s verdict by construction (the equivalence theorem
names what may change: nothing); if S1 gives a reachable violation, fix the binding
site with the theorem's invariant and nothing else. Pin: the B1 program, and a
GENERATOR of unsatisfiable row programs (random `field`s, a relation missing a random
non-empty subset, a `combine_Op`/`col_Op` chain over the missing ones — build the
source the way `TestSchema.shape` does), each case run on a deadline thread that FAILS
rather than hangs (the `(iso)` pin in `TestRunner` on json-encode is the idiom) and
required to be REJECTED; and the positive twins required to check. Tier 0 + Tier 1
yourself; report. If the fix is not available — S1a AND S1b both came back negative or
the upstream fix is out of reach — say so with the theorem names and stop; S3 follows.

### brief-S3 — the budget (Opus implementer, 4 h; only on S2's proved negative)

A budget on the escape check modelled on the rowSound one: `-Dermine.subsume.budget=<n>`
steps, exhaustion COUNTED and TRACED, and the outcome on exhaustion is the SAFE one for a
rejection path — the program is refused with a message naming the budget, never
accepted. First the theorem (a Lean prover may be split off in parallel): the budgeted
check terminates for every input; it agrees with the unbounded check whenever that
answers within the budget; exhaustion implies the unbounded check would not have
answered within it. Default value from S0's favourable-run measurements with margin,
recorded. Flag default: the budget ON is a behaviour change only where the checker did
not terminate before — argue that in the report and let the user decide the default.

### brief-review (Opus reviewer, under 2 h, one per stage)

You did not write the stage. Read the plan, the stage brief, the report. Re-run: `lake
build` + `Audit.lean` + `#print axioms` for Lean stages; compile + the stage's own
suites + the B1 property alone for Scala stages; and anything you dispute. Cite the
implementer's logs for the rest — never a whole-corpus or full-suite re-run. Check that
no theorem was weakened to pass (compare statements against the brief), that every
hypothesis discharged by measurement has the log, that a "terminates" claim is a
theorem and not a timing, and that corpus verdicts are unmoved. Vacuity: mutate one
case and confirm a failure, revert. Verdict: LAND / FIX-THEN-LAND (numbered, file:line,
failure scenario, fix) / REWORK.

---

## Out of scope — ticket, do not build

Moving the LSP check off the dispatch thread with cancellation (the Diagnostics comment
names it as clangd's advantage); a client-side watchdog in `editor/vscode`; the E11b
residual nondeterminism (parked by the user) — this work must not reopen it, though the
same order-dependence is why this hang hid for so long, and a note connecting the two
belongs in the Stage 0 write-up.
