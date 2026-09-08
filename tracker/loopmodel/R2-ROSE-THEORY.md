# R2 — Ermine's row constraints ARE a row theory in Rose's sense, at the model level

Stage R2 of the loop-model programme (`tracker/LOOP-MODEL-PLAN.md`), brief
`tracker/loopmodel/briefs/brief-R2.md`, origin `tracker/ROSE-COMPARISON.md` §3 rank 2.
2026-09-07, branch `scala3-migration`.  **LEAN ONLY**: no Scala, no examples, no executable Lean;
`looptrace` was not rebuilt and its mtime is unchanged; no `.ei` was created.  Nothing committed.

**This document is the report AFTER the review fix round.**  The review is
`tracker/loopmodel/R2-REVIEW.md` (594 lines, verdict FIX-THEN-ADVANCE, findings K-1…K-12, no
defect found in the Lean).  **The reviewer obtained the paper** — the Wayback Machine's 2025-07-21
snapshot of the ACM CC-BY PDF of `10.1145/3290325` — and checked Definitions 1, 2 and 6 clause by
clause, so every quotation below is now from the primary source rather than from the memo.  §9
lists what the fix round changed, finding by finding.

## 0. Outcome

**PARTIAL — every deliverable R2.1–R2.5 is present and kernel-checked, and exactly ONE condition
of the brief fails as stated.**

> **The failing condition, named.**  R2.2 asks for `⇒` = derivability in the NON-DELETING
> fragment of `LoopRel`, with condition (2), *soundness of `⇒` for the algebra*, to come "from
> `LoopRel.sat`, restricted to the fragment".  **It does not come from there, and it is false for
> that fragment** — and the reason is STRUCTURAL, not incidental.  Definition 2's second model
> condition reads, verbatim:
>
> > If `P ⇒ ψ`, then for each ground substitution `θ` on **`fv(P,ψ)`**, `f ⊨ θP` implies `f ⊨ θψ`.
>
> `θ` ranges over `fv(P, ψ)` — *including the variables that occur only in the conclusion*.  A
> MINT puts a fresh variable in `fv(ψ) \ fv(P)`, where `θ` is free to send it anywhere.  So **no
> minting rule can be an entailment rule in Rose's sense, in any row theory.**  Four of the nine
> constructors that survive dropping `weaken` — `split`, `res`, `splitFree`, `kres` — mint.
> `LoopRel.sat`, by contrast, is *satisfiability* preservation (`SSat G → SSat G'`), which is a
> different and much weaker statement.
>
> Exhibited, not asserted: `nd_derives_not_entails` and `split_not_conserv` carry a three-variable
> witness — `G₀ = { a <- (x, y, (|ℓ|)) }`, one `splitConcrete` step minting `u` and emitting
> `u <- (x, y)`, and a model of `G₀` that refutes it.  (The reviewer re-elaborated this
> independently, from scratch, rather than reusing it.)
>
> **The repair, and what is actually proved.**  The row theory is built on the MINT-FREE
> non-deleting fragment `MFStep` = `LoopRel` minus `weaken` minus the four minting constructors —
> both fragment identities proved in both directions (`loopRel_split`, `ndStep_split`,
> `MFStep.toND`, `NDStep.toLoopRel`).  On `MFStep`, soundness is not merely available, it is
> *stronger* than Definition 2 asks: `NonGenStep.models_iff` says the model set never moves, and
> the four remaining constructors carry `Refine.lean`'s `renameLhs_sat` / `linkSymm_sat` /
> `emptyProp_sat` / `dedup_sat`.
>
> **And the mints are recovered, on the input's own vocabulary.**  `nd_derives_sound_on_vocab`:
> derivability in the FULL non-deleting fragment — mints included — IS Definition 2's soundness
> provided the derived constraint is phrased in `allVars G`.  Nothing new is proved; five existing
> library lemmas are assembled (`K2SplitStep.extend`, `K2ResStep.extend`, `mint_extend`,
> `split_mint_conservativeExt`, `sat_congr_of_agree`), and the library already carried the same
> statement for the CSE mint as `Cut.CseStep.entails_iff` / `Cut.cut_preserves_meaning` ("over the
> input's own vocabulary, entail exactly the same constraints").  So the mints are outside `⇒`
> **only for conclusions that mention the minted name**, which is what a mint is for; what is
> genuinely outside a Definition-2-sound relation is **`weaken` alone**.

Everything else is green: Definitions 1, 2 and 6 stated from the paper (R2.1), Ermine exhibited as
a row theory with all the model conditions discharged — twice, once over derivability and once
over semantic consequence (R2.2), Definition 6 proved (R2.3), R2.4's accounting below, and
kernel-checked non-vacuity (R2.5).

**The PARTIAL does not weaken what R3 needs.**  Rose's Definition 13 mentions neither `⇒` nor
models; it is a closure on *predicates*.  What R3 inherits is `sat_iff_pfold` and
`labelAlgebra`-as-a-partial-monoid, both green.  §5's last subsection says this in full, because
a reader of this section could easily conclude the opposite.

## 1. What was built

One new module, `tracker/lean/Rowpartition/RoseTheory.lean` (1,554 lines, of which about half is
docstring), added to the root import list `tracker/lean/Rowpartition.lean`.  It imports
`Rowpartition.Loop.Strict` (for `LoopRel`, `NoLoss`, `Conserv`, `SSat`) and
`Rowpartition.NameLossClosed` (for `NonGenStep.mono`).  `Rowpartition.Loop.Main`'s import closure
is untouched.

| § | contents | main declarations |
|---|---|---|
| 1 | Definition 2's row algebras; the `Mergeable` presentation; Ermine's `⟨𝒫fin(L), ⊎, ∅⟩` | `RowAlgebra`, `RowAlgebra.pfold`, `Mergeable.toAlgebra`, `labelAlgebra` |
| 2 | Ermine's `Sat` IS the algebra's combination predicate | `disjoint_foldr_iff`, `pfold_label`, **`sat_iff_pfold`** |
| 3 | Definition 1's row theories, quoted | `RowTheory` |
| 4 | the two fragments, BOTH inclusions, and derivability | `MFStep`, `NDStep`, `loopRel_split`, `ndStep_split`, `Derives`, `Ent`, `ent_of_mem`, `ent_trans`, `ent_eq_inv`, `perm_already_equal`, `mfRun_mono`, `ent_iff_derives`, `MFStep.allVars`, `mfRun_allVars` |
| 5 | Ermine as a row theory, twice | `zeta0`, `EEnt`, `eEnt_sound`, `ermineTheory`, `IsModel`, **`ermine_isRowTheory`**, `PermSim`, `perm_ne`, `permSim_sat`, `permSim_sEntails`, `ermineSemTheory`, `ermineSem_isRowTheory`, `Goal_eEnt_permInvariant` |
| 6 | the caveats, and the vocabulary-restricted repair | `weaken_not_subset`, `ndRun_ssat`, `ndTheory`, `MintWitness.*`, **`nd_derives_not_entails`**, `split_not_conserv`, `split_preserves_ssat`, `ndStep_extend`, `ndRun_extend`, **`nd_derives_sound_on_vocab`**, `nd_ent_sound_on_vocab`, `Goal_nd_ent_sound_off_vocab` |
| 7 | Rose's simple rows: the two notions the paper distinguishes | `PMap`, `simpleAlgebra`, `AlgHom`, `dom_hom`, `lift`, `lift_algHom`, `lift_dom_unit`, `SatS`, `satS_dom`, `satS_lift_iff`, `SimpleRowTransport`, `Def6Hom`, `simpleTheory`, **`ermine_to_simple_hom`**, `bridge_side_condition` |
| 8 | non-vacuity, and one incompleteness witness | `Witness.*`, `LiveRules.*`, `taut_entailed`, `eEnt_empty_false` |

**271 non-internal declarations** land under `Rowpartition.Rose`, of which **151 theorems**; all
use only `propext`, `Classical.choice`, `Quot.sound`, and 55 use fewer.  There is no `sorry` and
no `partial` anywhere in the file.

## 2. R2.1 — Rose's definitions, stated

**Source discipline.**  The definitions below are quoted from the paper, through
`R2-REVIEW.md` §1, which extracted them from the CC-BY PDF.  The numbering is the paper's:
Definition 1 the row theory, Definition 2 the row algebra plus the model conditions, Definition 6
the row theory homomorphism.  (The brief's R2.1 swaps 1 and 2; the paper does not.)

### Definition 1 — row theory (`RowTheory`)

> **Definition 1.** A row theory is a 3-tuple ⟨R, ∼, ⇒⟩, as follows.
> • R is a set of syntactic rows (that is, of well-formed **ground** row type expressions). …
> • Relation ∼ is an equivalence relation on R …
> • Relation ⇒ is an entailment relation on row predicates (ζ₁ ≼ ζ₂ and ζ₁ ⊙ ζ₂ ∼ ζ₃), invariant
>   with respect to ∼, satisfying monotonicity (P ⇒ ψ if ψ ∈ P) and transitivity (P, Q ⇒ ϕ if
>   P ⇒ ψ and Q,ψ ⇒ ϕ).

Monotonicity and transitivity match `ent_mono` and `ent_trans` exactly, `insert` and `∪` included.
Two readings are this file's and are flagged at the declaration: the context is a **`Finset`** of
predicates (the paper writes sets, with no finiteness — this narrows), and `∼`-invariance is
stated with an explicit lifting `psim` plus a two-sided pointwise correspondence of contexts,
because the paper gives no more than the phrase.

**"Ground" is load-bearing, and the fix round acted on it.**  Rose's `R` is the *ground* rows, so
Ermine's `R` is `Row = Finset Label` and the model map `f` is the identity — a ground Ermine row
IS an element of the algebra.  `Type.scala`'s `VarT | ConcreteRho` is *not* `R`: its variable case
is not ground.  The variables live in the PREDICATES, where Definition 2's ground substitution `θ`
sends them into `R` — and `θ` is exactly an Ermine `Assign`.

### Definition 2 — row algebra and model (`RowAlgebra`, `IsModel`)

> **Definition 2.** A row algebra is any partial monoid ⟨M, ·, ϵ⟩; that is, · is a partial binary
> function M × M ⇀ M such that: m · ϵ = m = ϵ · m; and, if m₁ · (m₂ · m₃) is defined, then it is
> equal to (m₁ · m₂) · m₃. Let f : R → M; we write f ⊨ ζ₁ ⊙ ζ₂ ∼ ζ₃ if f(ζ₁) · f(ζ₂) = f(ζ₃),
> extended to f ⊨ ζ₁ ≼ ζ₂ and f ⊨ P in the obvious way. We say that such an f is a model of
> ⟨R, ∼, ⇒⟩ in ⟨M, ·, ϵ⟩ iff:
> • For ζ₁, ζ₂ ∈ R, if ζ₁ ∼ ζ₂, then f(ζ₁) = f(ζ₂);
> • If P ⇒ ψ, then for each ground substitution θ on fv(P,ψ), f ⊨ θP implies f ⊨ θψ; and,
> • There is some ζ₀ ∈ R such that f(ζ₀) = ϵ.

`IsModel` has four fields.  Three are the bullets; the fourth, `pred_algebraic`, is the paper's
**definition of `⊨`** ("we write `f ⊨ ζ₁ ⊙ ζ₂ ∼ ζ₃` if `f(ζ₁) · f(ζ₂) = f(ζ₃)`"), recast n-arily,
because Ermine's `Sat` is given independently in `Basic.lean` and has to be *shown* to agree.
Without it `hold` could be any relation and the model conditions would say nothing about the
algebra.  So the accurate phrasing is "the three conditions plus the definition of `⊨`".

One deliberate narrowing: `RowAlgebra.assoc` is the two-sided Kleene equation, whereas the paper's
condition is one-directional.  Ours implies the paper's — the safe direction — so every
`RowAlgebra` here is a Rose row algebra, but the class is smaller.  Flagged at the field.

### Definition 6 — row theory homomorphism (`Def6Hom`)

> **Definition 6.** A function h : R₁ → R₂, extended to predicates in the obvious fashion, is a
> **row theory homomorphism** … from ⟨R, ∼, ⇒⟩ to ⟨R′, ∼′, ⇒′⟩ if ζ₁ ∼ ζ₂ implies that
> h(ζ₁) ∼′ h(ζ₂) and P ⇒ ψ implies that h(P) ⇒′ h(ψ).
>
> **Row algebras are related by partial monoid homomorphisms.** …

**Two clauses, both syntactic, on a map between syntactic row sets.**  It says nothing about `⊎`,
nothing about `ε` and nothing about models; maps of *algebras* are the paper's separate notion,
named in the very next sentence.  The first round of this stage called its algebra-plus-transport
bundle "Definition 6"; that was wrong (K-1), and so is `ROSE-COMPARISON.md` §3 rank 2's own bullet
("the inclusion composed with `dom`" — which is an algebra map, and points from Rose's algebra
into Ermine's rather than into simple rows).  Both are corrected, there and here.

## 3. R2.2 — Ermine exhibited as a row theory

### The algebra, and the predicates read in it

`labelAlgebra : RowAlgebra Row` is `⟨𝒫fin(L), ⊎, ∅⟩`.  The step that makes the exercise more than
a naming convention is

```lean
theorem sat_iff_pfold (rho : Assign) (c : Constraint) :
    Sat rho c ↔ labelAlgebra.pfold (parts rho c) = some (rho c.lhs)
```

**one Ermine partition constraint is exactly one n-ary combination predicate of the algebra**: the
fold is *defined* precisely when the parts are pairwise disjoint, and it *equals the whole*
precisely when the partition is complete.  Nothing in `Basic.lean`'s semantics had to be adjusted.

*Arity, stated because it matters later.*  Rose's `⊙` is BINARY and has a companion containment
predicate `≼`; Ermine's `<-` is n-ary and has no `≼`.  One n-ary Ermine constraint is a
*conjunction* of Rose predicates with an existential intermediate (`ROSE-COMPARISON.md` §1.2:
`a <- (b,c,d)` is `b ⊙ u ∼ a, c ⊙ d ∼ u`) — and that intermediate is the same existential the
mints supply.  **The arity gap and the mint failure are one phenomenon.**  `sat_iff_pfold` is a
statement about the *algebra*, where the n-ary fold is unimpeachable.

### Condition (1) — `∼`-invariance, and where it is free

Definition 1's `∼` is an equivalence **on rows**.  Ermine's rows are `Finset Label`, so Rose's
`∼simp` ("identifies sequences up to permutation") really is `=` here — that is
`ROSE-COMPARISON.md` §1.1 row 5, and `perm_already_equal` is its instance.  This is the correct
instance, not a discretisation.

At the PREDICATE level the story is different, and the module now says both halves:

* `ermineTheory.psim = Eq`.  That is the smallest lifting Definition 1 permits, and it is FORCED
  for the derivability relation: `perm_ne` proves `⟨0,[1,2],∅⟩ ≠ ⟨0,[2,1],∅⟩` (`Constraint.vars`
  is a `List`), and no `MFStep` derivation produces the permuted variant, because every rule's
  premises are memberships of `mk`-BUILT constraints.
* `ermineSemTheory.psim = PermSim`, the permutation equivalence, with every Definition-1 clause
  discharged at it.  `permSim_sat` proves the model set does not move under a permutation of
  parts; `permSim_sEntails` is the full `∼`-invariance of the semantic entailment relation, on
  both sides.  The price is that `⇒` there is semantic consequence rather than derivability.
* `Goal_eEnt_permInvariant` records the remaining question — permutation-invariance of
  *derivability* — and what it would cost: permutation-invariance for `NonGenStep`'s six
  sub-relations, which live in other modules.

### Condition (2) — soundness of `⇒` for the algebra — **the condition that fails as stated**

See §0 for the failure and the repair.  What is proved:

* `MFStep.models` — every mint-free non-deleting step preserves **models** (`NonGenStep.models_iff`
  plus the four `*_sat` lemmas).
* `MFStep.noLoss` / `MFStep.conserv` — the same in the library's vocabulary.  `Conserv` **is**
  Definition 2's soundness condition read constraint by constraint.
* `mfRun_models`, `eEnt_sound : EEnt G c → SEntails G c` — the condition, discharged.
* `nd_derives_not_entails`, `split_not_conserv` — the counterexample for the wider fragment;
  `split_preserves_ssat`, `ndRun_ssat` — what `LoopRel.sat` does give there.
* `ndStep_extend`, `ndRun_extend`, **`nd_derives_sound_on_vocab`**, `nd_ent_sound_on_vocab` — the
  repair.

**What is NOT a mint, and the report's first round overstated it.**  `MFStep.nongen` is
`SplitNecessary.NonGenStep`, which bundles six sub-relations — one of them `SplitReuseStep`,
`splitConcrete`'s REUSE branch, and another `Cut.CutStep`, CSE's reuse and fold.  So
`splitConcrete` is not wholly outside `⇒`; **only its minting branch is**.

**The `Ent`-versus-`Derives` choice costs nothing.**  `⇒` is derivability *in every context*:

```lean
def Derives (Step) (G) (c) : Prop := ∃ H, Relation.ReflTransGen Step G H ∧ c ∈ H
def Ent     (Step) (G) (c) : Prop := ∀ H, G ⊆ H → Derives Step H c
```

`Ent` is the library's own `Refine.Adds` idiom, and it is what makes Definition 1's transitivity
provable without a frame lemma for the minting rules — whose freshness side condition has none.
On the fragment the row theory is actually built on the two coincide: **`ent_iff_derives :
Ent MFStep G c ↔ Derives MFStep G c`** (via `mfRun_mono`, from `NameLoss.NonGenStep.mono`).  So
`EEnt` is plain derivability and nothing was traded away.  The context closure costs something
only on `NDStep`, which is exactly where the remaining open question is stated.

### Condition (3) — `ζ₀`

`zeta0 : Row := ∅` with `f_zeta0 : id zeta0 = labelAlgebra.eps`, unconditionally — the paper's
"there is some ζ₀ ∈ R such that f(ζ₀) = ϵ", with no quantifier over assignments.  The brief's
suggestion `ζ₀ := a <- ()` is a *constraint*, not a row, and is recorded separately as
`zeta0_constraint : Sat rho (mk a ∅ ∅) ↔ rho a = labelAlgebra.eps` (`Refine.sat_empty_iff`):
at the SOLVER level, where a row expression is always a variable, the empty row is not a row but
is *said* by `a <- ()`.

### The main theorems

```lean
def ermineTheory     : RowTheory Row Constraint                  -- Definition 1, over derivability
theorem ermine_isRowTheory    : IsModel labelAlgebra ermineTheory    id id Sat zeta0
def ermineSemTheory  : RowTheory Row Constraint                  -- Definition 1, over ⊨, at ∼simp
theorem ermineSem_isRowTheory : IsModel labelAlgebra ermineSemTheory id id Sat zeta0
```

`ROSE-COMPARISON.md` §5.4 item 3 notes that **Rose's Example 3 is asserted, not proved** — the
paper's footnote 2 says a formal demonstration "would require building similar maps from the
syntax of rows present in each language".  `ermine_isRowTheory` is the Ermine-side analogue,
discharged.

## 4. R2.3 — the two notions, and Definition 6

Rose's simple-row algebra is `⟨L ⇀ T, ⊔, ∅⟩` (Example 3), partial maps label → field type with
`⊔` defined iff the domains are disjoint.  `PMap T` models it with an explicit `Finset` domain, so
`simpleAlgebra T` is the **finite-domain sub-algebra** of the paper's carrier — closed under `⊔`,
containing `∅`, a legitimate row algebra, but not literally Example 3's carrier.  Flagged.

**The paper's two notions, kept apart.**

| theorem / structure | what it is |
|---|---|
| `dom_hom T` | a **partial monoid homomorphism** `(simpleAlgebra T) → labelAlgebra`.  This is "Ermine's algebra is Rose's simple-row algebra composed with `dom`, `T` collapsed to a point" (`ROSE-COMPARISON.md` §1.1 row 2) as a theorem |
| `lift_algHom tau` | a **partial monoid homomorphism** the other way, `labelAlgebra → (simpleAlgebra T)`, preserving `⊎` *including definedness* and `ε` |
| `dom_lift`, `lift_dom_unit` | `dom ∘ lift tau = id`; at `T = Unit` the two are mutually **inverse** |
| `SimpleRowTransport` | one of those bundled with model-level transport of the predicates (`satS_lift_iff`) and of `SEntails`.  Useful, and **NOT Definition 6** — the paper has no `pred` clause anywhere near Definition 6 |
| `Def6Hom` | **Definition 6 itself**, its two syntactic clauses, with the extension to predicates as an explicit parameter |
| **`ermine_to_simple_hom tau`** | `Def6Hom ermineTheory (simpleTheory tau) (lift tau) id` — Definition 6, discharged |
| `bridge_side_condition` | the paper's bridge's hypothesis, discharged |

`AlgHom` is deliberately **strict** (`(A.op a b).map h = B.op (h a) (h b)` preserves *undefined*
too), which is what "preserves `⊎`" has to mean for a partial operation; the paper's partial
monoid homomorphisms are not required to be.  Flagged.

**What `simpleTheory tau` is, and is not.**  Its rows are Rose's ground simple rows, `∼′` is `=`,
and `⇒′` is **semantic consequence in the simple-row algebra along the `tau`-slice**.  Definition 6
quantifies over any two row theories, so this is a legitimate target — but it is **not Rose's
`⇒simp`**, and a Definition-6 map into `⇒simp` is out of reach for two reasons worth recording:

1. `⇒simp`'s two ground axiom schemes fire only on fully spelt-out rows (`ROSE-COMPARISON.md`
   §1.3), and §1.3's finding is that `⇒simp` derives **none** of Ermine's rules.  `Witness.ent_x`
   (`{a <- (x,y), a <- ()} ⇒ x <- ()`) has no `⇒simp` counterpart.
2. "h extended to predicates in the obvious fashion" is not well defined here: `Constraint` is
   `⟨lhs : Var, vars : List Var, conc⟩`, so **Ermine has no ground predicates at all** — every
   constraint is over variables, and a map on rows induces a map on predicates only once an
   assignment is supplied.  `Def6Hom` therefore takes the extension as data.

**The paper's bridge** — "if there is a partial monoid homomorphism `j` from `M` to `M′`, and for
every `ζ ∈ R` there is a `ζ′ ∈ R′` such that `j(f(ζ)) = g(ζ′)`, there is a row theory
homomorphism" — is the alternative route, and its side condition is **exactly this module's
`tau`-slice**: choosing `tau` is choosing the witness family.  `bridge_side_condition` discharges
it (cheaply, because a ground simple row IS an element of the simple-row algebra, so `g = id`).
The bridge's conclusion is prose in the paper and is proved neither there nor here;
`ermine_to_simple_hom` reaches Definition 6 directly instead.

## 5. R2.4 — what it buys, honestly

### What becomes citable

1. **"Principal types for Ermine" now has a STATEMENT.**  `ROSE-COMPARISON.md` §1.5: the
   correspondence "is the prerequisite for even *stating* it, because Rose's Theorem 11 is stated
   over a row theory."  With `ermineTheory` in hand, the claim to be proved or refuted is
   Theorem 11 at that row theory, under Figure 9's generality ordering `⊒`.
2. **Definition 13's determinacy closure is a legitimate Ermine notion.**  See §5's last
   subsection: this is the licence R3 needs, and it survives the PARTIAL intact.
3. **A correctness criterion for a simplifier**: Figure 9's `⊒` is an ordering on constrained type
   schemes *of a row theory*, so `IsCanonicaliser.faithful` (memo §4.2) is anchored in a published
   definition rather than an analogy.
4. **The Ermine-side analogue of Example 3 is discharged** where the paper leaves its own
   undischarged (§3).

### What does NOT become citable, and why

* **Theorem 11 for Ermine's compiler.**  Three independent reasons, all confirmed by the reviewer
  against the source.
  (i) *Scope*: Theorem 11 is a theorem about Rose's typing judgment, its syntax-directed variant
  and its Algorithm M.  Being a row theory is a hypothesis of Rose's *calculus*, not of Theorem
  11's proof; exhibiting `ermineTheory` makes the *statement* available and nothing more.
  (ii) *Rose buys principality by never solving*; Ermine solves and **commits**.  `A1-REVIEW.md`
  §R-6 is a measured instance: `RevenueShare.shareOfGroup`'s published type is strictly MORE
  GENERAL at the new dequeue order (`OLD ⊨ NEW`, `NEW ⊭ OLD`), over the same body — "It is the
  dequeue order."
  (iii) *The compiler does not run `⇒`.*  It runs `incorporateAll`, whose relation is `LoopRel`.
  With the vocabulary-restricted repair the *mints* are back inside a Definition-2-sound relation,
  so what remains outside is **`weaken` alone** — and S1's account of the deletions is conditional
  (`run_noLoss` concludes `NoLoss ∨ ¬ SSat`, and the S1 review found `BareAgree` failing at
  reachable shipped-flag states).
* **Theorem 15 for Ermine — and the obstruction is stronger than "unmet".**
  > **Definition 14.** A type scheme ∀T.Ψ ⇒ τ is coherent if T ⊆ fv(τ)⁺_Ψ. **A term M is coherent
  > if its principal type scheme is coherent.**

  Definition 14 defines coherence *of a term* through its **principal type scheme** — and §5's own
  argument is that Ermine has no principality theorem.  So for Ermine **Definition 14 is not yet
  well-defined**, not merely unmet.  That is the headline, and it is a stronger statement than the
  first round made.

  Beyond it: Ermine has **no ambiguity criterion for row residuals at all** —
  `Subst.mkSimplified` computes `ambiguitiesIn(exts, complex)` over the CLASS constraints only
  (`Subst.scala:1723-1724`), the row parts reach `pruned` without passing through it, and
  `ambiguitiesIn` (`:371-372`) is `typeVars(p).exists(_ == v)` with no closure; `split`,
  `ambiguities` and `defaultSubst` (`:374-386`) are callerless.  And the criterion is known to
  fail on a real residual: `PivotTest.pivotData`'s
  `(|Issue, Key, Value|) <- ((|Key|), v3, i)` with `v3` and `i` existential is genuinely
  underdetermined — four solutions over two labels — and `fv(τ) = {s}` closes to nothing under
  Definition 13, so `T ⊄ fv(τ)⁺_Ψ`.  **The reviewer reproduced this on the compiler** (one JVM,
  `-Dermine.useInterface=false`, `:type pivotData`; every `.ei` created was deleted afterwards).
  Two corrections to the first round's wording: it is **not** a "shipped `.ei`" — no `.ei` is
  checked in for `PivotTest`, the residual is in the **inferred signature**; and reading Ermine's
  **existential** binders as Definition 14's `∀T` is an **interpretation**, not an identity, which
  R3 will have to make explicitly.
* **Nothing about the solver, the budget, the simplifier or `reduce`.**  Rose gives no decision
  procedure for `⇒`, no completeness theorem and no complexity bound; the row theory is a
  statement about a *relation*.

### What R3 inherits — and the PARTIAL does not weaken it

> **Definition 13.** We define T⁺_Ψ as the smallest set U such that • T ⊆ U; and, • if
> ζ₁ ⊙ ζ₂ ∼ ζ₃ ∈ Ψ, and fv(ζ₁, ζ₂) ⊆ U, then fv(ζ₃) ⊆ U.

**Definition 13 mentions neither `⇒` nor models.**  It is a closure on the *predicates* of `Ψ`.
Therefore:

* **Inherited, and load-bearing:** `sat_iff_pfold`, which licenses reading an Ermine constraint as
  a combination predicate and so restating Definition 13's clause n-arily
  (`fv(all parts) ⊆ U ⟹ fv(lhs) ⊆ U`); and `labelAlgebra` being a genuine partial monoid, which is
  what makes "determined" mean anything at all — in a partial monoid the combination is a
  *function* of the parts wherever it is defined.  Both are green.
* **Not inherited, and R3 should not wait for it:** anything about entailment.  The `MFStep`
  restriction, `nd_derives_not_entails` and `Goal_nd_ent_sound_off_vocab` are all irrelevant to
  Definition 13.  **The PARTIAL does not weaken R3's licence.**
* **R3 must supply for itself:** the n-ary restatement; the *larger*-than-Rose closure the memo
  identifies (cancellation determines a part from the whole and the other parts once the concrete
  parts are known); the `∀`-versus-`∃` reading; and the fact that Theorem 15 is unavailable as a
  *guarantee* because Definition 14 is not well-defined for Ermine — so Definition 13 can be
  imported as a **criterion**, which is all `ROSE-COMPARISON.md` rank 4 ever claimed for it.

## 6. R2.5 — non-vacuity, and one incompleteness witness

* `Witness` — `G = { a <- (x, y), a <- () }` at `a = 0`, `x = 1`, `y = 2`.  `ent_x` and `ent_y`
  (`emptyProp`, derivable from **every** context containing `G`); `run_both`, a two-step
  `ReflTransGen MFStep` run; `entails_x` through `eEnt_sound`; `models`, `models_conclusion`;
  `simple_models`, the same instance in the simple-row reading at `T = Unit`.
* `LiveRules` — **added in the fix round**, so no branch of `MFStep` is dead: `dedup_live`,
  `renameLhs_live`, `linkSymm_live`, and `dedup_sound : SEntails {0 <- (1,2), 1 <- (2)} (2 <- ())`,
  a second non-trivial entailment derived from a non-empty system.
* `MintWitness` — the negative instance of §0, with all five `SplitApp` premises discharged.
* `taut_entailed (r) : SEntails ∅ (mk r {r} ∅)` — the memo's `Goal_taut_is_trivial`.  **This is
  NOT non-vacuity evidence for `⇒`**, and the first round presented it as if it were.  `MFStep` is
  non-generative (`MFStep.allVars`), so `eEnt_empty_false` proves `EEnt ∅ (mk r {r} ∅)` is FALSE:
  the tautology is semantically entailed and the exhibited `⇒` does not derive it.  That is an
  **incompleteness witness**, and an honest one — Definition 2 asks only for soundness, and
  `ROSE-COMPARISON.md` §1.3 records that Rose's `⇒` "is a *parameter*".

## 7. Gates

| gate | number |
|---|---|
| `lake build` (full default target) | **GREEN, 869 jobs** (unchanged by the fix round).  Baseline re-derived by removing the root import line and rebuilding: **868 jobs**.  Warnings are the project-wide Mathlib style set: no file in `Rowpartition/` carries a copyright header (0 of 39), and the module emits seven header-linter warnings of the kind **65 of the project's Lean files** emit; one pre-existing 103-character line at `Rowpartition.lean:94`, untouched.  The new module has no long lines, no `simp` warnings and no unused-variable warnings |
| `lake env lean Audit.lean` | **4,446 theorems audited, 0 declarations using a non-standard axiom** (4,427 before the fix round).  Baseline **re-derived, not quoted**, by the same import-removal procedure: **4,295 / 0** |
| `#print axioms`, **all non-internal declarations** | **271** non-internal declarations under `Rowpartition.Rose`, of which **151 theorems** — the reviewer's wider sweep, adopted.  Saved at `/home/dmitry/.claude/jobs/880c725d/tmp/R2/print-axioms-all.txt` (generator `PrintAxiomsAll.lean` beside it).  216 use `[propext, Classical.choice, Quot.sound]`, 18 `[propext, Quot.sound]`, 2 `[propext]`, 35 none.  **No `sorryAx`, no `nativeDecide`, no `ofReduceBool`**; no `sorry` and no `partial` in the source |
| `git diff --stat` | **3 files changed, 121 insertions(+), 1 deletion(-)** — `tracker/lean/Rowpartition.lean` **28 +** (docstring entry and `import`), `tracker/ROSE-COMPARISON.md` **93 +, 1 −** (the dated DONE note, the K-1 correction under the original Rank 2 bullet, and the K-12 note; the single deletion is the §0 vocabulary line, corrected in place for K-8 with the correction marked inline), `tracker/LOOP-MODEL-PLAN.md` **1 +** (the R2 row).  Untracked: `tracker/lean/Rowpartition/RoseTheory.lean`, `tracker/loopmodel/R2-ROSE-THEORY.md`, `tracker/loopmodel/R2-REVIEW.md`.  **No Scala, no examples, no executable Lean** |
| `.ei` | **143, unchanged**; none created (no compiler was run in either round of this stage) |
| `looptrace` mtime | **UNCHANGED**: `2026-09-07 15:12:54.333891088 -0600`, 292,801,216 bytes, before and after both rounds |
| commits | **none** |

Toolchain: `leanprover/lean4:v4.33.1`, Mathlib `v4.33.1`, `LEAN_NUM_THREADS=2`, one `lake build`
at a time.  No `lake exe cache get`, no new `require`, no new Lean project, `~/research/leanwork`
untouched, `Rowpartition/CutSearch.lean` still out of the root import list and out of the audit.

## 8. Scope limits and open questions

1. **`Goal_eEnt_permInvariant` is OPEN**: permutation-invariance of *derivability*, which
   `ermineTheory.psim = Eq` avoids.  It would need permutation-invariance for `NonGenStep`'s six
   sub-relations, in other modules.  `ermineSemTheory` discharges the same clause at `∼simp` for
   the semantic entailment relation, which is what R3 uses.
2. **`Goal_nd_ent_sound_off_vocab` is OPEN**, and it is now a curiosity rather than the question
   that matters: `nd_derives_sound_on_vocab` settles the minting fragment for every conclusion
   inside the input's vocabulary, and what is left is only conclusions outside it under the
   context-closed reading.  **Proving** it needs a closure argument over the five rule families of
   the kind `NameLossClosed.lean` carries; **refuting** it needs a construction whose conclusion
   survives freshness blocking in every context.  (The first round stated these two directions the
   wrong way round.)
3. **A Definition-6 map into Rose's own `⇒simp` is not available**, for the two reasons in §4;
   `ermine_to_simple_hom`'s target is named honestly.
4. **Entailment transport into simple rows is proved along the `tau`-slice only.**  `satS_dom`
   transports Rose models to Ermine models in general; `satS_lift_iff` gives the `iff` only when
   the field types are supplied by a single `tau`.  This is the exact place where "Ermine's rows
   carry no field types" has content — and it is also, by the paper's bridge, the hypothesis
   Definition 6 would need on that route.
5. **This stage says nothing about the loop's ORDER.**  Everything proved is about the relation
   `LoopRel` and the semantics `Sat`.
6. **R3 was not started**, per the brief.

## 9. Fix round (R2 review)

Review: `tracker/loopmodel/R2-REVIEW.md`, verdict **FIX-THEN-ADVANCE**, findings K-1…K-12, no
defect found in the Lean.  All twelve are addressed below.  The module grew from 1,061 to **1,554**
lines; `Audit.lean` from 4,427 to **4,446**; no gate moved otherwise.

| # | rank | what the review said | what was done |
|---|---|---|---|
| K-1 | HIGH | `RowTheoryHom` is not Rose's Definition 6; Definition 6 is a map on SYNTACTIC rows with two clauses, and maps of algebras are the paper's separate notion.  Mis-citation in module, report, root docstring, memo DONE note, plan row, and the memo's ORIGINAL Rank 2 bullet | structure **renamed** `SimpleRowTransport` and re-documented for what it is (a partial monoid homomorphism bundled with model-level transport); Definition 6 **quoted verbatim** in §7's docstring; **`Def6Hom`** added with the paper's two clauses (the extension to predicates as an explicit parameter, because Ermine has no ground predicates); **`simpleTheory tau`** added as an explicitly-named target row theory; **`ermine_to_simple_hom` now discharges Definition 6** and keeps the brief's main-theorem name; the transport theorem is `ermine_to_simple_transport`.  The `⇒simp` obstruction is stated in both its forms.  Mis-citation corrected in the module docstring, this report (§2, §4, §8), `Rowpartition.lean`'s docstring entry, the memo's DONE note, the memo's original Rank 2 bullet (dated CORRECTION block) and the plan row |
| K-2 | HIGH | the PARTIAL is right and the reason is structural — Definition 2 quantifies `θ` over `fv(P,ψ)`, so no minting rule is an entailment rule in ANY row theory; and prove both fragment identities | the structural reason is now the wording in §0, in the module docstring and in the memo's two correction blocks; **`loopRel_split`** and **`ndStep_split`** added (the hard direction of each identity), so both fragments are characterised in both directions.  Also added: the precision that `MFStep.nongen` contains `splitConcrete`'s REUSE branch and CSE's reuse-and-fold, so only the minting BRANCHES are outside `⇒` |
| K-3 | HIGH | `Goal_nd_ent_sound` is the wrong open question; the vocabulary-restricted statement is ~50 lines from existing lemmas, and `Cut.CseStep.entails_iff` already does it for the CSE mint; the cost sentence has its two directions swapped | **`ndStep_extend`**, **`ndRun_extend`**, **`nd_derives_sound_on_vocab`**, **`nd_ent_sound_on_vocab`** added, assembled from `K2SplitStep.extend`, `K2ResStep.extend`, `mint_extend`, `split_mint_conservativeExt`, `sat_congr_of_agree`; `Cut.CseStep.entails_iff` / `cut_preserves_meaning` now cited in the module docstring and here.  The open question is renamed `Goal_nd_ent_sound_off_vocab`, demoted to "a curiosity", and its cost sentence corrected (proving needs the closure argument; refuting needs the freshness-surviving construction) |
| K-4 | MED | prove `EEnt = Derives MFStep`; say the context closure costs nothing | **`mfRun_mono`** and **`ent_iff_derives`** added; §3 says it in as many words |
| K-5 | MED | `taut_entailed` is an INCOMPLETENESS witness, not non-vacuity; give a genuine one | **`MFStep.allVars`**, **`mfRun_allVars`**, **`eEnt_empty_false`** added; `taut_entailed` relabelled at its docstring and in §6; **`LiveRules`** added — `dedup_live`, `renameLhs_live`, `linkSymm_live` and `dedup_sound` (a non-empty `G` with a non-trivial derived entailment), so no `MFStep` branch is dead |
| K-6 | MED | three unflagged narrowings: one-directional associativity, the finite-domain `PMap` carrier, the strict `AlgHom`; and `pred_algebraic` is *more* faithful than claimed | all three flagged in the module docstring and at the declarations, and restated in §2/§4 here; `pred_algebraic` is now described as the paper's DEFINITION of `⊨`, so `IsModel` is "the three conditions plus the definition of `⊨`" |
| K-7 | MED | Rose's `⊙` is BINARY with a companion `≼`; and `∼`-invariance was discharged at the discrete equivalence, which `∼simp` is not | the arity gap is stated in the module docstring and §3, together with the observation that it and the mint failure are ONE phenomenon.  **`PermSim`**, **`perm_ne`**, **`permSim_sat`**, **`PermSimSys`**, **`permSimSys_models`**, **`permSim_sEntails`**, **`ermineSemTheory`**, **`ermineSem_isRowTheory`** added: Definition 1 discharged at Rose's `∼simp` for the semantic entailment relation, with `Goal_eEnt_permInvariant` recording what the derivability version would cost.  Also: `R` changed from `RowExpr` to the GROUND rows `Row` (Definition 1's own wording), `IsModel` restated in the paper's shape (`f : R → M`, `θ : Var → R`), and `unit` is now unconditional |
| K-8 | LOW | `LoopRel` has TEN constructors, not eleven | corrected in the module docstring (with the constructor list) and in `ROSE-COMPARISON.md` §0, where the correction notes that the ELEVEN of §1.3 is the count of Ermine's RULES, a different tally |
| K-9 | MED | three corrections to R2.4 plus one unnamed prior obstruction | §5 corrected: no `.ei` is shipped for `PivotTest` (the residual is in the **inferred signature**, which the reviewer measured on the compiler); **Definition 14 is not well-defined for Ermine**, since it quantifies over the PRINCIPAL scheme — now the headline rather than "a named unmet hypothesis"; the `∀T`-versus-existential reading is flagged as an interpretation R3 must make explicitly |
| K-10 | MED | state exactly what R3 inherits, and that the PARTIAL does not weaken its licence | §5 gains a dedicated subsection with Definition 13 quoted, the two inherited items (`sat_iff_pfold`, the partial-monoid algebra), the explicitly non-inherited entailment half, and the three things R3 must supply itself.  §0 now says the same, because a reader of §0 could have concluded the opposite |
| K-11 | LOW | the module does emit seven header-linter warnings of its own, of a kind 65 project files emit | §7's build row restated with the reviewer's census |
| K-12 | LOW | recommended wording for the memo's correction note | applied verbatim (with the module's new line count and theorem names substituted), as a dated **CORRECTION (2026-09-07, R2 review K-12)** block under Rank 2, additive |

**Nothing was removed and no proof was weakened.**  Every theorem the first round carried is still
present and still proved, except that `RowExpr` / `den` were replaced by the ground-row
presentation (K-7), which changes `ermine_isRowTheory`'s statement to the more faithful one, and
`RowTheoryHom` / `ermine_to_simple_hom` were split into `SimpleRowTransport` /
`ermine_to_simple_transport` and `Def6Hom` / `ermine_to_simple_hom` (K-1).
