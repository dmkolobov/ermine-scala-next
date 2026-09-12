# Brief: S3c -- the class-constraint status quo at signatures (investigation; parallel with S3)

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-fix`, branch `sig-fixes` (read the code; the ONLY
file you write is `tracker/loopmodel/SIG-3-CLASS-STATUS.md`; probes go in your scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S3c/`).
No commits; never `git stash`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
`bin/ermine` for probes (`-Dermine.useInterface=false`); parallel by default. Budget 2 hours.

Context: the user decided the entailment check (tracker/SIG-ENTAIL-PLAN.md, SIG-2-DESIGN.md) is ROW-ONLY:
class constraints keep their current path. The user asked for "a recommendation/explanation of the class
status quo" after the stage. Write it, one page, for a reader who knows Ermine but not this code.

Answer, with `Subst.scala` line numbers and probe programs that actually ran:
1. What happens to a CLASS constraint at a declared signature today: `subsumeType` splits the residual into
   `ds` (skolem-free) and `rs`; `entails(qs, r)` (:313, `bySuper`/`byInst`) is called and its result
   discarded; `entail` (:394) is gated on `isClassConstraint`; the `ds` half goes to `mkSimplified` (:553)
   and the `:548-549` loop dies on unknown classes. Trace a class-constrained signature whose body needs a
   class the signature does not provide: is it rejected, accepted, or accepted-then-fails? Probe it
   (Ermine has class DECLARATIONS but the memory note says class bodies are dead and there is no instance
   system -- find what a class constraint can even mean at runtime: `Ord`, `Eq`, `Num`-style dictionaries
   are explicit values in this stdlib, e.g. `Ord {..r}`, `Monoid_Mo m`; is there any constraint the checker
   can fail to discharge that would crash?).
2. Is the same hole present for classes: a signature promising `forall a. a -> Int` over a body using a
   class-constrained function -- the non-row control `bad : forall a. a -> Int; bad x = x + 1` IS rejected
   (S0). Explain WHY the class case is caught when the row case was not (the answer is probably that `+`
   is monomorphic-or-dictionary, not class-constrained; say precisely).
3. Where class constraints DO flow: generalisation (`inferAltTypesPrime` :1030), `.ei` publication,
   ambiguity checks (`ambiguities`, :390). Are declared class contexts ever compared with inferred ones?
4. Recommendation: leave as is / add the analogous check / remove dead machinery -- with the cost of each,
   and whether the row check's `Site` plumbing would carry a class check for free.
Keep it under 120 lines. Verdict line first.
