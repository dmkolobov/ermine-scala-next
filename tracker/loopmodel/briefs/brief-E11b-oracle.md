# Brief: E11b Phase 1 — the entailment oracle at publication, EXPLORATION ONLY (3 h)

Repo `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD `8cc4d38c`. You change NO file
under `core/src/main`, `session/`, `tracker/lean/` and NO tracker file except your report
`tracker/loopmodel/E11b-ORACLE.md`. Scratch harnesses (Python, Lean scripts run with `lake env lean --run`, or a
throw-away Scala driver) live under
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11b-oracle/`
(call it `<scratch>`). A throw-away Scala driver may sit in the test tree while you run it but must be deleted
before you write up; `git status` at the end shows the report and nothing else. Delete every `.ei` you cause under
`core/target` (`find core/target -name '*.ei'`). Never `lake build`; never commit. JVMs and sbt may run in parallel
with anything else on the machine (`tracker/GATE-POLICY.md`, parallelism rules). Toolchain notes: memory file
`~/.claude/projects/-home-dmitry-research-ermine/memory/ermine-scala-toolchain.md` if you need PATH exports for sbt.
Budget 3 hours wall clock; at the budget, write up what you have and stop. You do NOT implement anything.

## The problem, in one paragraph

When the row solver finishes a top-level binding, `Subst.mkSimplified` (`Subst.scala:2086`) publishes a residual
constraint set that can contain a constraint the others already ENTAIL; whether it survives depends on solver
order, so two cold checks of one unchanged module publish two different sets for the same binding. Item E11a fixed
the FORM (order, letters); the SET class is what is left: `Relation.e:lookbackJoin`,
`Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'`, `Present/WriterOutputs.e:reportFor`, `Yahoo.e:investmentTableData`,
`Yahoo.e:joinCumRet`, `Yahoo.e:joinTotalValue` (the run of record), plus `Layout/Report.e:drilldownKeyValueTable2`,
`core/examples/incomplete/RevenueShare.e:shareOfGroup` and `incomplete/np01_add_or_recompute.e:inferredRestate`
seen intermittently. The variants are entailment-equivalent (not a soundness bug). The proved six-rule
canonicaliser (`tracker/lean/Rowpartition/Canonical.lean`) fires NO rule on any of the six: what is missing is
entailment (definitional substitution, existential projection) — see the probe. E11b's shape, already decided by
the user (roadmap "Interstage item E11", E11b paragraph): at publication, delete a constraint the rest of the set
entails UNDER THE EXISTENTIALS, using an entailment oracle, per-scheme budget, KEEP on no-verdict, to a fixpoint,
idempotent, after E11a's canonical order.

## Read, in this order (about 40 minutes)

1. `tracker/GATE-POLICY.md` (parallelism, no `.ei` left behind).
2. `tracker/loopmodel/E11b-PROBE.md` — §1, §5, §6, §7.2. The six leftover differences, `lookbackJoin` worked by
   hand, the concrete-left-hand-side problem (§3.1, §7.2 item 1). Its scratch data is still on disk:
   `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/e11b/` —
   `pairs/*.txt` are the 31 raw rendering pairs, `cases.json` the parsed systems, `conv.py`/`parse.py` the
   converters, `leftover.log` the minimal leftovers per pair. REUSE them; do not re-derive the pairs.
3. `tracker/loopmodel/E11a-CANON.md` §4 and §15 (R-3, R-8, R-9) and `E11a-REVIEW.md` "The 47" and its
   `lookbackJoin` REquiv proof.
4. Ticket E11 in `tracker/TICKET-stdlib-findings.md` (E-section, "E11.") and the roadmap section "Interstage item
   E11" in `tracker/LSP-ROADMAP.md` (the E11b paragraph is the spec you are exploring against).
5. `tracker/ROSE-COMPARISON.md` rank 3 (§3) and §4 — `Residual`, `Holds`, `REntails`, `REquiv`, `IsCanonicaliser`
   (`faithful`, `irredundant`, `idem`, `universals`), §4.3 (pass (ii) is coNP-hard in general: budget, and a lapse
   KEEPS), §4.6 (`labelDecide` as the oracle: the per-label decomposition `entails_iff_forall_label`, its
   satisfiability side condition, and `LabelNoVerdict` = keep).
6. `tracker/SIG-ENTAIL-PLAN.md` "The missing judgement" and `core/src/main/scala/com/clarifi/reporting/ermine/SigEntail.scala`
   header + `check` (`:418-616`): the judgement it decides, `F = vars(W) ∩ pxs \ vars(Q)`, the per-label-class
   loop over `Constraints.LabelSearch`, the two budgets and the model cap, and the NO-VERDICT DISCIPLINE (a dropped
   given forbids REJECT, a dropped obligation forbids ACCEPT; `NoVerdict` is never silently either). Note what
   `encode` (`:322`) can and cannot read — a partition with a CONCRETE left-hand side is `Unreadable`, and three of
   the six bindings carry one (probe §3.1, §5.3).
7. `Subst.mkSimplified` (`Subst.scala:2086-2184`) and `Subst.generalize` (`:1758-1800`): note that `mkSimplified`
   runs BEFORE `Canonical.scheme` (`:1776` builds the `Forall`, `:1792` canonicalises it), that `deleteTautologies`
   (`:2060`, `publishing` only) is the existing publication-only deletion and the model for where a new pass sits,
   and that `normalPart` already yields `NormalPart(left, concrete, abstrakt)`.
8. `tracker/ROW-CONSTRAINT-STATE.md` line ~61 and ~426 (the complete per-label decision, A1) — what "classified
   equivalent by the per-label decision tooling" will mean for Phase 2's `.ei` moves.

## THE QUESTION

Which oracle should decide, for a published residual `R = ⟨ex, sys⟩` (universals = the scheme's `forall` binders
and the body's free variables; `ex` = `pubExts`) and a constraint `c ∈ sys`,

    DELETABLE(c)  :=  REntails ⟨ex, sys \ {c}⟩ ⟨ex, sys⟩        (ROSE §4.1; the other direction is trivial)

i.e. for every assignment ρ of the universals that some choice of the existentials extends to a model of
`sys \ {c}`, some (possibly different) choice extends it to a model of all of `sys`. Compare THREE candidates:

**(A) `SigEntail.check` as it stands**, called as `check(qs = sys \ {c}, rs = List(c), ds = Nil, sks = ?, pxs = ex)`.
Its judgement is ∀ρ ⊨ Q. ∃ρ' agreeing with ρ off `F`. ρ' ⊨ W, with `F = vars(c) ∩ ex \ vars(Q)`. The orchestrator's
sketch — CHECK IT, do not take it: since `F ∩ vars(Q) = ∅`, a witness ρ' also models Q, so `Ok` implies
DELETABLE(c); `NotEntailed` and `NoVerdict` both mean KEEP; the sketch covers `lookbackJoin` (pointwise: `F = ∅`)
and `reportFor` (the fresh existential `c` IS `F`). Things to settle: how `check` reads rigid vs flexible
(`rigid(v) = v.ty == Skolem`, `:137`) when at publication the universals are NOT skolems — does any branch depend on
it (`rigidW`, `extra`, `foreign`)? What `sks` must be. Whether the `Unreadable` drop of a concrete-left-hand-side
GIVEN (safe: forbids only REJECT) leaves the three `Yahoo` bindings undecidable — and whether the probe's proxy-variable
encoding (`z <- (parts)`, `z <- ((|K|))`, the S4 item SigEntail's comment names) is the one-line extension that
decides them. Whether the satisfiability precondition (ROSE §4.6) is discharged for a residual reaching `mkSimplified`
(the `extinct` solve at `:2137` and `rowSound.decide`). Determinism: `canonRows` sorts by RENDERED NAME then id — is
the verdict, INCLUDING a `NoVerdict` on budget, a function of E11a's canonical order alone?

**(B) The row solver on the negation**: `solve(Exists(l, Nil, Q ∪ enc(¬c)))` unsatisfiable ⇒ entailed. `¬c` is not a
partition constraint; SIG-ENTAIL-PLAN's refutation trick (`Q ∪ {sk' <- (sk, L)}` unsat iff `L ⊆ sk`) covers only the
concrete-extension shape. Say precisely which shapes of `c` admit an encoding, whether the solver's refutation
incompleteness (ROSE §1.4) makes a non-failure meaningless, and whether the complete per-label decision inside
`solve` changes that. Expect to reject this with reasons, but reject it from evidence.

**(C) A small saturating decision procedure over partition constraints**: treat `a <- (b, c) + K` as the equation
`a = b ⊎ c ⊎ K` (disjoint), close `Q` under definitional substitution (fold/unfold, probe §5.3, §6) plus the two
degenerate rules a FRESH existential in `c` allows (it matches any sub-partition: `reportFor`) and a concrete
left-hand side is just a definition (`{initValue} = c ⊎ d`: the `Yahoo` three), and ask whether `c` is in the closure
up to right-hand-side permutation. Sound because every derived equation is a consequence; incomplete; cheap;
deterministic. Bound the closure (depth or size) and say what a bound lapse means (KEEP).

A layered answer (C first, A as the general fallback under budget, or A alone with the proxy encoding) is a
legitimate recommendation if the evidence supports it.

## For EACH candidate, the report must give

* **Soundness**: an argument that `ACCEPT ⇒ DELETABLE(c)` in the `REntails`-with-existentials sense (ROSE §4.1),
  covering: shared existentials between `c` and `Q`; a fresh existential in `c`; a universal in `c` not in `Q`;
  a concrete left-hand side; class constraints (they are partitioned off at `:2130` — does the oracle ever need
  them?); an UNSATISFIABLE `Q`. Where the argument fails, say so and say what the oracle must return there (KEEP).
* **What it decides on the six** (and on the three intermittent ones if their pairs are recoverable from the
  previous scratch; if not, say so): per pair, which leftover constraint(s) it would delete, from the actual
  renderings in `<prev-scratch>/e11b/pairs/`. For (A) this is a MEASUREMENT: build the residuals as `Type` values
  (or read them through whatever the shortest path is — a throw-away driver against the compiled classes, `sbt
  core/console`, or a scratch test) and call `SigEntail.check`, logging the verdict and `SigEntail.lastCost` per
  constraint. For (C) a Python prototype over `cases.json` is enough. For (B) a hand argument per shape suffices.
* **THE CONVERGENCE QUESTION** (this is the one that decides whether E11b closes the ticket, and no earlier document
  answers it): deletion to a fixpoint is NOT order-independent in general — when two constraints entail each other
  given the rest (in `lookbackJoin`'s B, both B6 and B7 are deletable given the other), which one goes depends on the
  visiting order. State the visiting/choice rule you assume (E11a's canonical key order over the set, first
  deletable goes, restart; or last; or a preference on the key), simulate it on BOTH variants of every pair, and
  report whether they land on the SAME set (up to E11a's form). If the answer depends on the rule, find a rule that
  works on all decidable pairs and say why it should generalise, or say that it does not. Include the case where a
  variant's deletion lands on a set that is neither A nor B.
* **Cost per constraint**: measured for (A) (`Cost(nodes, models, classes)` and wall ms) on the actual residual
  sizes — `cutoffGroupedFldsPosNegRel'` has 28 constraints and is the stress case; estimate the per-scheme total
  (`|sys|` calls per fixpoint round, rounds ≤ deletions + 1) against the corpus's ~4,000 published bindings and the
  batch wall time (~10-14 s; E11a's floor is ~1 %). Propose the two budgets (per constraint, per scheme).
* **Determinism given E11a's canonical input order**: is every verdict, including budget lapses, a function of the
  canonical order and nothing else (no `Set` iteration order, no id, no hash)? Cite the lines.

## Report `tracker/loopmodel/E11b-ORACLE.md`

Recommendation FIRST (one paragraph: which oracle, the choice rule, the budgets, what closes and what is beyond the
oracle by name), then a comparison table (candidate × {sound / decides on the six / convergence / cost / determinism}),
then the sections above, then a **Phase 2 sketch**: where the loop goes given that `mkSimplified` precedes
`Canonical.scheme` (run the oracle after canonicalising the constraint list, i.e. on `Canonical.key` order, or move
the pass into `generalize` after `:1792` — say which and why), what "idempotent" and "keep on lapse" mean in code,
what the `.ei` classification will have to show, what a Lean target would be if any (ROSE §4.2 `faithful` for the
deletion rule given oracle soundness — optional, say how big), and the survivors to exempt by name. Every number
from a command whose log is in `<scratch>` and named in the report. Plain language; a reader who has not opened
`SigEntail.scala` should follow the soundness argument.

## Acceptance (five points)

1. `tracker/loopmodel/E11b-ORACLE.md` exists, states DELETABLE(c) as above, and gives all three candidates the
   five-part treatment (soundness, the six, convergence, cost, determinism), with the recommendation first.
2. Candidate (A) is MEASURED, not argued: a log in `<scratch>` shows `SigEntail.check`'s verdict and `lastCost` for
   every leftover constraint of every recoverable pair, and the report says how the residuals were built.
3. The convergence question is answered per pair under a STATED choice rule, with the simulation's log.
4. `git status` shows only the report; no `.ei` under `core/target`; no `lake build`; nothing committed.
5. Written up inside 3 hours, with the time spent stated; anything not reached is listed under "NOT DONE", never
   inferred.
