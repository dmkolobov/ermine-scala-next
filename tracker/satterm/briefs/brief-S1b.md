# brief-S1b — the rejection path: the loop model on unsatisfiable inputs (Opus Lean prover, 4 h)

Worktree `~/research/ermine/ermine-scala-wt-subsume-s1b`, branch `subsume-s1b`. Read `brief-S-common.md` first,
then `tracker/lean/README.md` (L1–L5, S1, D1 sections), `tracker/loopmodel/L1-MODEL.md`, `L5-TERMINATION.md`,
and the headers of `Rowpartition/Loop/{Budget,PolicyTerm,Reject,Refuted,Residual,VocFix,Wf}.lean` and
`Rowpartition/{KeyedSplit,KeyedRow,KeyedLoop}.lean`. Report: `tracker/satterm/SUBSUME-STAGE1B.md`. Read
`~/research/ermine/ermine-scala-wt-subsume-s0/tracker/satterm/SUBSUME-STAGE0.md` whenever it has content (the
rejection path's trace, which rules fired, whether `labelDecide`/the budgets were reached), but do not wait for it.

## Goal

H3 says the rejection path grows the environment or diverges BEFORE `subsumeType`'s escape check, and `:648` is
merely where the thread was sampled. Extend the loop model (`Rowpartition/Loop/`) with what this input's
rejection path does, and answer with theorems or witnesses:

1. **Does refutation terminate?** Is the step relation well-founded on UNSATISFIABLE inputs? The tree already
   has: termination is NOT a property of the algorithm in general (eight L5 rounds; `L5-TERMINATION.md` §R8.6),
   it is engineered by the draw budget (`Loop/Budget.lean` `budget_terminates`, transported to the shipped policy
   in `PolicyTerm.lean`; `-Dermine.solveBudget=20000` is adopted default ON). So: state precisely what
   `budget_terminates` guarantees for THIS solve under the shipped defaults (cite, don't re-prove); then prove
   what it does NOT cover that the rejection path runs — `Subst.solve` around the loop (`Loop/Seed.lean`), the
   `labelClash`/`labelDecide` layers (`Loop/Decide.lean`, their own budgets), and `subsumeType`'s post-solve steps
   (`for (r <- rs) entails(qs,r)`, `SigEntail.enforce`, `restrictTypes`) — for the row fragment, or exhibit a
   witness in the `KeyedLoop.lean` W3 style where one of them does not terminate on an unsatisfiable input.
2. **How big can the environment be when the loop stops?** Bound `|types|` (and `|kinds|`) of the `SubstEnv` the
   loop leaves in terms of the input size and the draws (`VocFix.lean`'s vocabulary lemmas, `Draws.lean`,
   `Mints.lean`): a theorem of the form "after a budgeted solve, the environment has at most input + f(budget)
   entries and each binding has size at most g(...)" — or the witness that the range's SIZE is unbounded even
   when its cardinality is not (a chain of bindings whose substituted form is exponential). This is what tells
   S2 whether H1's "enormous `hm.types`" is reachable from the loop, and it is the number S0's measured
   `types.size` is compared against.
3. **Is a cyclic binding reachable?** The model's `unify`/`destructiveSub`/`makeConcrete` binding sites versus
   the Scala `occursFail` (`Subst.scala:228`) and `occursCheckKind` (`Kind.scala:112`): prove the invariant "no
   variable is bound to a term mentioning it, through any chain" is preserved by every `continue` step from every
   seed/replay state (the `NoSelfUnif`/`NoInfRow` invariants of `Loop/Residual.lean` are the starting point), or
   produce the witness that reaches a cyclic binding — that is H2's upstream cause and the fix belongs at the
   binding site (an occurs check) with its own theorem. Note what S0 says about whether the walk follows
   bindings at all; if it does not, a cycle cannot be what the walk spins on, and say so — but the invariant is
   still worth having for S2.

## Build/audit/README

New file(s) under `Rowpartition/Loop/` (e.g. `Loop/Reject2.lean` or `Loop/EnvBound.lean` — pick names that say
what they prove) imported from `Rowpartition/Loop.lean`; `lake build` (full default target; `looptrace` need not be
rebuilt unless you change an executable module — if you do, say so, that is a Tier 1 trigger for the landing),
`lake env lean Audit.lean` 0 non-standard, `#print axioms` on every new declaration (paste), README entry under
the Loop model sections naming every theorem with a one-line statement. No `sorry`/`partial`/`unsafe`/
`native_decide`/new axioms.

## Deliverables

`SUBSUME-STAGE1B.md`: theorem names and statements, witnesses (with the state that reaches them), the axioms
output, the build/audit lines, the environment bound as a formula S2 can compare with S0's numbers, which of
H1/H2/H3 the model supports, and the stage's answer to the title question for the loop and the post-solve path
(yes / no / bounded). List every changed file.
