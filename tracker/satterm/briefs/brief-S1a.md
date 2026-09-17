# brief-S1a — the substitution model: the kind-variable walk over a substitution (Opus Lean prover, 4 h)

Worktree `~/research/ermine/ermine-scala-wt-subsume-s1a`, branch `subsume-s1a`. Read `brief-S-common.md` first,
then `tracker/lean/README.md` (module map, "Proved in Lean" section, `DefaultSatDiverge.lean` for the witness
style, `Audit.lean`). Report: `tracker/satterm/SUBSUME-STAGE1A.md`. Read `tracker/satterm/SUBSUME-STAGE0.md` in
the S0 worktree (`~/research/ermine/ermine-scala-wt-subsume-s0/tracker/satterm/SUBSUME-STAGE0.md`) whenever it has
content, but do not wait for it.

## Goal

New `tracker/lean/Rowpartition/SubsumeEscape.lean`: a model of `Subst.scala:648`'s escaping-skolem check —
`hm.fskvs.filter(stss) ++ hm.kindVars.filter(skss)` over `SubstEnv.types`/`kinds` — precise enough that a theorem
about it licenses (or forbids) the S2 fix. Two theorems, whichever the model yields:

- **Termination + equivalence.** The collection terminates for every well-formed substitution (state the
  invariant precisely: what "acyclic bindings" means for the map `types : TypeVar ⇀ Type` and
  `kinds : KindVar ⇀ Kind` that the solver keeps — `Subst.scala:228-240` `occursFail` is the binding-site check);
  and the RESTRICTED collection — kind variables of the skolems `sks`/`sts` and of the types they occur in (the
  cheap `X`, since `escs` is filtered by `skss`/`stss` anyway) — gives the SAME verdict (`escs` empty or not) as
  the whole-environment walk. The equivalence theorem must name exactly what may change: nothing observable.
- **Or a witness**, in `DefaultSatDiverge.lean`'s style: a well-formed substitution on which the walk is
  unbounded (or, if the walk is structural and always terminates, a family of well-formed substitutions of size
  n whose walk cost is exponential in n — shared subterms unfolded as a tree — with the cost function stated and
  the bound proved). A witness must be small enough to be checked by `decide`/`native`-free evaluation
  (`#eval` on the model is fine for exhibiting; the theorem is what counts).

## Model the CODE, not the prompt

Before writing the model read `Type.scala:649-660`, `Kind.scala:58-65`, `Kind.scala:119-136`, `Vars.scala` and
`Subst.scala:169, :221-226, :642-648`. Decide and record: does `VarT(v) => v.extract.vars` follow the binding of
`v` in `types`, or only `v`'s kind annotation (`V[Kind].extract`)? Does `VarK(v).vars` follow `kinds(v)`? If no
binding is followed, the "acyclic" invariant is vacuous for termination and the theorem to prove is the COST
bound (tree size vs. DAG size of the substitution's range) plus the equivalence of the restricted walk; say so
and prove that instead — the brief's first bullet is then "terminates unconditionally, cost = tree size", the
interesting content is the exponential-unfolding witness or its impossibility. The syntax: `Con`, `App`, `Var`
(with a kind annotation), enough binder structure for `Forall`/`Exists` (`Forall`'s `vars` subtracts its bound
kind variables and deliberately excludes its constraint `q`; `Exists` collects its `xs`' kinds and `q`'s), `Part`,
and kinds `Star`/`ArrowK`/`VarK`. Sharing: represent a substitution range as a DAG (or terms with an explicit
`let`/sharing node) if the cost theorem needs it; explain the choice.

## Build/audit/README

`lake build` (full default target), `lake env lean Audit.lean` (0 non-standard), `#print axioms` on every new
declaration (paste the output in the report), add `import Rowpartition.SubsumeEscape` to `Rowpartition.lean`,
and a README entry under "Later additions" naming every theorem with its statement in one line and what is
proved in Lean vs stated on paper. No `sorry`, no `partial`, no `unsafe`, no `native_decide`, no new axioms.

## Deliverables

`SUBSUME-STAGE1A.md`: the invariant (or its vacuity), theorem names and statements, the axioms output, the build
and audit lines, what the S2 implementer may change and what it may not (from the equivalence theorem), and the
stage's answer to the title question restricted to the walk (yes / no / bounded). List every changed file.
