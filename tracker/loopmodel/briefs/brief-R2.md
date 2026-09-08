# Brief: R2 — Ermine's row constraints ARE a row theory in Rose's sense, at the model level (Lean only)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from commit `257cbde`. LEAN ONLY: no
Scala, no examples, no executable Lean (`Loop/Main.lean`'s import closure must not change; `looptrace` must not be
rebuilt). Toolchain `export PATH=$HOME/.elan/bin:$PATH`, `LEAN_NUM_THREADS=2`, in `tracker/lean/`; you are the only
agent on the machine, so `lake build` is allowed, one at a time. Disk is tight: never `lake exe cache get`, never add a
`require`, never create another Lean project, never touch `~/research/leanwork`; `Rowpartition/CutSearch.lean` stays
OUT of the root import list and the audit. Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/R2/`. No commits. Report
early and keep it current.

ORIGIN: `tracker/ROSE-COMPARISON.md` Rank 2 (§3) — "REJECT AS STATED, ADOPT THE USEFUL HALF" — with §0 (vocabulary),
§1.1 (which row theory Ermine implements: the SIMPLE row theory over label SETS, `⟨𝒫fin(L), ⊎, ∅⟩`), §1.3 (the rules
side by side), §1.4 and §5.1 (Morris & McKinna, *Instance chains* / *Rose*, POPL 2019: Definitions 1, 2, 6, Theorems
11 and 15). Read the memo in full first. The Lean you build on: `Rowpartition/Basic.lean` (`Constraint`, `mk`, rows
as `Finset`), `Rowpartition/Loop/Refine.lean` (`LoopRel`, and `LoopRel.sat` at ~:417 — "every constructor preserves
satisfiability", the one hard lemma, ALREADY PROVED), `Loop/Strict.lean` (`NoLoss`, `LoopStrict` with its `weaken`),
`Rowpartition/Canonical.lean` (`SatL`, `step_vacuous`). For idiom only (read, do not install anything): Toohey, Chen,
Jamalzadeh & Xie, *Extensible Data Types with Ad-Hoc Polymorphism* (POPL 2026) mechanises a row calculus in Lean 4.

## What to prove (one module, `Rowpartition/RoseTheory.lean`, order of 150–300 lines, added to the root import list)

R2.1 STATE Rose's definitions faithfully in Lean, with the paper's numbering in the docstrings: a row algebra
     (Def. 1 or the memo's reading of it: a partial monoid `⟨R, ⊎, ε⟩`), a row theory (Def. 2: predicates over rows,
     an entailment relation `⇒`, `∼`-invariance, soundness of `⇒` for the algebra, and a `ζ₀` with `f(ζ₀) = ε`), and a
     row-theory homomorphism (Def. 6). Where the memo's reading of the paper is an interpretation, say so in the
     docstring; do not invent structure the paper does not have.
R2.2 EXHIBIT Ermine as a row theory: rows = `Finset Lbl`, `⊎` = disjoint union (partial: defined iff disjoint), `ε` =
     `∅`; predicates = Ermine's partition constraints `a <- (parts, K)` (the `Constraint` of `Basic.lean`, with `Has`
     as the existential form the memo names); `⇒` = derivability in the NON-DELETING fragment of `LoopRel` (the memo's
     caveat: `weaken` deletes and is not monotone in the Definition-1 sense, so the theory is `LoopRel` minus `weaken`,
     with deletions handled by `NoLoss` — write that caveat into the docstring verbatim). Prove the three conditions:
     (1) `∼`-invariance is free (`mk` takes a `Finset` — state the theorem anyway); (2) soundness of `⇒` for the
     algebra — from `LoopRel.sat`, restricted to the fragment; (3) `ζ₀ := a <- ()` with `f(ζ₀) = ∅`.
     Main theorem: `ermine_isRowTheory` (or the name that reads best).
R2.3 EXHIBIT the homomorphism into Rose's SIMPLE rows (Def. 6): the inclusion composed with `dom : (L ⇀ T) → 𝒫(L)`;
     prove it preserves `⊎`, `ε` and entailment. Main theorem: `ermine_to_simple_hom`.
R2.4 SAY WHAT IT BUYS, honestly, in the report: Rose's Theorem 11 (principality) and Theorem 15 (coherence) are
     parametric over the row theory — state, as prose with the paper's hypotheses listed, what exhibiting Ermine as a
     row theory makes citable for Ermine's SURFACE language and what it does NOT (Ermine's solver, the budget, the
     simplifier, `reduce` are outside Rose's statements; §1.5 of the memo: Ermine is not in Rose's principal-types
     position). If any hypothesis of Theorem 11/15 is NOT met by Ermine, say which. This is the licence R3 (Rose's
     Def. 13 determinacy closure for `reduce`'s splice) needs; do not start R3.
R2.5 Non-vacuity: a kernel-checked instance (a concrete constraint set, its derivation in the fragment, its model).

## Gates (report every number)
`cd tracker/lean && lake build` GREEN (full default target; the job count goes up by one module); `lake env lean
Audit.lean` count with 0 non-standard axioms; `#print axioms` for every theorem in the module saved in scratch (the
standard three only; no `sorryAx`, no `nativeDecide`); `git diff --stat` shows only the new module, the root import
and the docs; `looptrace` mtime unchanged. Report `tracker/loopmodel/R2-ROSE-THEORY.md` (definitions with the paper's
numbering, theorem by theorem, the caveats, R2.4); a plan row R2 in `tracker/LOOP-MODEL-PLAN.md`; a dated additive
note under Rank 2 in `tracker/ROSE-COMPARISON.md` ("DONE <date>: …"). Outcomes: (GREEN) R2.1–R2.5; (PARTIAL) which
condition or hypothesis fails and why — a definition that does NOT fit is a finding, not a failure; (BLOCKED) why.
No silent weakening. A reviewer re-runs everything. STOP after the report.
