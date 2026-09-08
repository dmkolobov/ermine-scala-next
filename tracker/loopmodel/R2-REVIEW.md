# R2 review — Ermine as a Rose row theory at the model level

Independent review of stage R2 (`tracker/loopmodel/R2-ROSE-THEORY.md`; implementer's brief
`briefs/brief-R2.md`; review brief `briefs/brief-R2-review.md`).  2026-09-07, branch
`scala3-migration`, HEAD `e1f381f`, R2's deliverables UNCOMMITTED on top of it.  Nothing was
edited except this file and the reviewer's scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-R2/`.  No commits.  Every `.ei` the review caused
was deleted (`ei-before.txt` / `ei-final.txt` in scratch: identical).

> **I obtained the paper.**  The implementer could not, and stated so honestly throughout.  I
> could: the ACM open-access PDF is behind Cloudflare live, but the Wayback Machine's 2025-07-21
> snapshot of `dl.acm.org/doi/pdf/10.1145/3290325` serves it (437,974 bytes, `rose.pdf` in
> scratch, text as `rose.txt`).  So §1 below is a clause-by-clause check against the source, not
> against the memo.  This changes the verdict: the one place the implementer named as "the single
> citation in the module that could be wrong in substance" **is** wrong (K-1).

## Verdict

**FIX-THEN-ADVANCE.**

Nothing proved is false.  I re-ran every gate and re-elaborated the load-bearing claims myself,
including the counterexample, and found no defect in the Lean: 869 jobs green, 4,427 / 0 on the
audit, 0 non-standard axioms over **all 257** non-internal declarations under `Rowpartition.Rose`
(the report sweeps the 132 theorems; I swept the definitions too).  The PARTIAL is right, and it
is right for a sharper reason than the report gives — I confirmed it against Definition 2's actual
text, and the failure is *structural*, not incidental (K-2).

Two things must be fixed before this propagates into R3.

1. **`RowTheoryHom` is not Rose's Definition 6** (K-1).  Definition 6 is a map on *syntactic
   rows* preserving `∼` and `⇒`; the module's structure is a map on *algebra carriers* bundling a
   partial monoid homomorphism with model-level transport.  The paper names the second notion
   separately and in the same paragraph.  The mis-citation is in the module docstring, the report,
   the root-import docstring, the memo's Rank 2 DONE note **and** the plan row, and the memo's
   *original* Rank 2 bullet ("the inclusion composed with `dom`") is the same misreading.
2. **The report mis-costs its own open question and understates an available result** (K-3).  The
   statement that matters for the minting fragment — Definition-2 soundness *restricted to the
   input's own vocabulary* — is not open.  I proved it in the reviewer's scratch in about fifty
   lines from lemmas that were already in the library, and the library already carries the same
   lemma for the CSE mint (`Cut.CseStep.entails_iff`), which the module never mentions.

Both fixes are documentation plus, if wanted, two short theorems (K-3, K-4).  No proof is at risk,
no gate moves, and R2.1–R2.5 all stand.

## Findings

Ranked.  CONFIRMED = I ran it or read it in the primary source; PLAUSIBLE = argued, not machined.

| # | rank | status | one line |
|---|---|---|---|
| K-1 | HIGH | CONFIRMED | `RowTheoryHom` is not Definition 6; the paper's Definition 6 is quoted below and says something else |
| K-2 | HIGH | CONFIRMED | the PARTIAL is right, and confirmed against Definition 2's text; the mint failure is structural, and `MFStep` is exactly the right fragment |
| K-3 | HIGH | CONFIRMED | `Goal_nd_ent_sound` is the wrong open question; the vocabulary-restricted statement is ~50 lines from existing lemmas, and `Cut.CseStep.entails_iff` already does it for the CSE mint |
| K-4 | MED | CONFIRMED | `EEnt = Derives MFStep`; the context-closed definition costs nothing and the report should say so |
| K-5 | MED | CONFIRMED | `taut_entailed` is an INCOMPLETENESS witness, not a non-vacuity one; `EEnt ∅ c` is false for every `c` |
| K-6 | MED | CONFIRMED | Definition 2: `pred_algebraic` is *more* faithful than the report claims; the associativity, the `PMap` carrier and `AlgHom` are three narrowings, none flagged |
| K-7 | MED | CONFIRMED | two unflagged gaps: Rose's `⊙` is BINARY and has a companion `≼`; and `∼`-invariance is discharged at the DISCRETE equivalence, which Rose's `∼simp` is not |
| K-8 | LOW | CONFIRMED | `LoopRel` has TEN constructors, not eleven (the module docstring and the memo §0 both say eleven) |
| K-9 | MED | CONFIRMED | R2.4's `pivotData` claim reproduces on the compiler; three corrections and one unnamed prior obstruction |
| K-10 | MED | judgement | what R3 actually inherits, stated exactly — and it is not the entailment half |
| K-11 | LOW | CONFIRMED | every gate re-run and reproduced; one nuance about the module's own linter warnings |
| K-12 | LOW | — | recommended wording for the memo's correction note |

---

## 1. The definitions, against the paper (review brief §1)

**Source.**  Morris & McKinna, *Abstracting Extensible Data Types: Or, Rows by Any Other Name*,
PACMPL 3(POPL) art. 12, 2019.  Text extracted with `pdftotext -layout`; the extractor renders
`≼` as `4d` / `4L` / `4R`, and I have restored the symbol in the quotations below.  Line numbers
are into `rose.txt` in scratch.

**The memo's numbering is the paper's.**  Definition 1 is the row theory (`:541`), Definition 2 is
the row algebra together with the model conditions (`:565`).  The implementer followed the memo
over the brief here and was right to; the brief's R2.1 does swap them.

### Definition 1 (`:541`), clause by clause

> **Definition 1.** A row theory is a 3-tuple ⟨R, ∼, ⇒⟩, as follows.
> • R is a set of syntactic rows (that is, of well-formed **ground** row type expressions). We
>   impose no further restriction on R at this level of abstraction …
> • Relation ∼ is an equivalence relation on R …
> • Relation ⇒ is an entailment relation on row predicates (ζ₁ ≼ ζ₂ and ζ₁ ⊙ ζ₂ ∼ ζ₃), invariant
>   with respect to ∼, satisfying monotonicity (P ⇒ ψ if ψ ∈ P) and transitivity (P, Q ⇒ ϕ if
>   P ⇒ ψ and Q,ψ ⇒ ϕ).

| clause | Lean | verdict |
|---|---|---|
| `R` a set of syntactic rows | `RowTheory (R : Type*)` | MATCHES as a signature.  **Narrower at the instance**: Rose's R is *ground*; `RowExpr` has a `var` constructor, so Ermine's carrier contains non-ground rows.  Harmless — `sim = Eq`, and `ζ₀ = .conc ∅` is genuinely ground — but it is a reading, and it is not flagged |
| `∼` an equivalence on `R` | `sim`, `sim_equivalence` | MATCHES exactly |
| predicates | `P : Type*`, instantiated to `Constraint` | **Narrows** (no `≼`) and **widens** (n-ary, not binary): see K-7 |
| monotonicity | `ent_mono : ψ ∈ Γ → ent Γ ψ` | MATCHES exactly |
| transitivity | `ent_trans : ent Γ ψ → ent (insert ψ Δ) φ → ent (Γ ∪ Δ) φ` | MATCHES exactly, `insert` and `∪` included |
| "invariant with respect to ∼" | `psim` + `ent_sim` with a two-sided pointwise correspondence | INTERPRETATION, correctly flagged by the implementer.  The paper gives no more than the phrase.  The `psim_equivalence` field is this file's too |
| the context `P` | `Finset P` | NARROWS.  The paper writes sets with no finiteness.  Flagged |

### Definition 2 (`:565`), clause by clause

> **Definition 2.** A row algebra is any partial monoid ⟨M, ·, ϵ⟩; that is, · is a partial binary
> function M × M ⇀ M such that: m · ϵ = m = ϵ · m; and, **if m₁ · (m₂ · m₃) is defined, then it is
> equal to (m₁ · m₂) · m₃**. Let f : R → M; **we write f ⊨ ζ₁ ⊙ ζ₂ ∼ ζ₃ if f(ζ₁) · f(ζ₂) = f(ζ₃)**,
> extended to f ⊨ ζ₁ ≼ ζ₂ and f ⊨ P in the obvious way. We say that such an f is a model of
> ⟨R, ∼, ⇒⟩ in ⟨M, ·, ϵ⟩ iff:
> • For ζ₁, ζ₂ ∈ R, if ζ₁ ∼ ζ₂, then f(ζ₁) = f(ζ₂);
> • **If P ⇒ ψ, then for each ground substitution θ on fv(P,ψ), f ⊨ θP implies f ⊨ θψ**; and,
> • There is some ζ₀ ∈ R such that f(ζ₀) = ϵ.

| clause | Lean | verdict |
|---|---|---|
| `op : M × M ⇀ M` | `op : M → M → Option M` | MATCHES |
| `m · ϵ = m = ϵ · m` | `eps_left`, `eps_right`, both `= some m` | MATCHES, definedness included |
| associativity | `assoc`, the two-sided Kleene equation on `bind` | **NARROWS**: the paper's condition is one-directional.  Lean's implies the paper's, so every `RowAlgebra` *is* a Rose row algebra — the safe direction — but the class is smaller.  K-6(b) |
| `f ⊨ …` | `IsModel.pred_algebraic` | **MATCHES, and better than the report claims.** `⊨` is *defined* by the algebra in the paper; the field is that definition, recast because Ermine's `Sat` is given independently.  K-6(a) |
| model condition 1 | `sim_sound` | MATCHES |
| model condition 2 | `ent_sound` | MATCHES.  **This is model preservation, verbatim** — the implementer's diagnosis, confirmed at the source.  K-2 |
| model condition 3 | `unit` | MATCHES (stated for every `rho`, which is the right reading once `θ` is folded into the family) |
| "⟨M,·,ϵ⟩ is an algebra for ⟨R,∼,⇒⟩ if there is such an f" | `ermine_isRowTheory` | discharged |

Rose's `θ` is Ermine's assignment and Rose's `f` is `den`: the implementer's "a model is not one map
but the family `Sat` indexed by assignments" is the correct transposition of "ground substitution θ
composed with f", and the paper's `fv(P,ψ)` quantification is what makes K-2 structural.

### Example 3 (`:576`) vs `simpleAlgebra`

The paper's carrier is *partial functions* `f, g` from `L` to `T`, with `⊔` defined iff the domains
are disjoint, and `⟨L ⇀ T, ⊔, ∅⟩` asserted (not proved — footnote 2, which the report correctly
cites) to be an algebra for the simple row theory.  `PMap T` carries an explicit **`Finset`**
domain, so `simpleAlgebra T` is the finite-domain *sub-algebra*: closed under `⊔`, containing `∅`,
and a legitimate row algebra, but not literally Example 3's carrier.  Not flagged.  K-6(c).

### Definition 6 (`:614`) — **the mis-citation, K-1**

> **Definition 6.** A function h : R₁ → R₂, extended to predicates in the obvious fashion, is a
> **row theory homomorphism** (or simply: homomorphism) from ⟨R, ∼, ⇒⟩ to ⟨R′, ∼′, ⇒′⟩ if ζ₁ ∼ ζ₂
> implies that h(ζ₁) ∼′ h(ζ₂) and P ⇒ ψ implies that h(P) ⇒′ h(ψ).
>
> **Row algebras are related by partial monoid homomorphisms.** Homomorphisms of row theories and
> partial monoids are related in an intuitive way. Given that f is a model of ⟨R, ∼, ⇒⟩ in
> ⟨M, ·, ϵ⟩, and g is a model of ⟨R′, ∼′, ⇒′⟩ in ⟨M′, ·′, ϵ′⟩, if there is a row theory
> homomorphism from R to R′, then there is a corresponding partial monoid homomorphism from M to
> M′. **Under the same assumptions, if there is a partial monoid homomorphism j from M to M′, and
> for every ζ ∈ R, there is a ζ′ ∈ R′ such that j(f(ζ)) = g(ζ′), there is a row theory
> homomorphism from R to R′.**

Definition 6 has exactly **two clauses**, both **syntactic**, on a map between **syntactic row
sets**.  It says nothing about `⊎`, nothing about `ε`, and nothing about models.  The module's

```lean
structure RowTheoryHom (tau : Label → T) (h : Row → PMap T) : Prop where
  alg  : AlgHom labelAlgebra (simpleAlgebra T) h
  pred : ∀ rho c, Sat rho c ↔ SatS tau (fun v => h (rho v)) c
  ent  : ∀ G c, SEntails G c → ∀ rho, (∀ d ∈ G, SatS … d) → SatS … c
```

differs on all three axes:

* **the map's type.**  `h : Row → PMap T` is a map between *algebra carriers* (`M → M′`), not
  between syntactic row sets (`R₁ → R₂`).  The paper puts maps of that type under its *other*
  notion, named one sentence later: "Row algebras are related by partial monoid homomorphisms."
* **the clause list.**  `alg` is that other notion (and `AlgHom` is a stricter version of it, K-6(d)).
  `pred` has no counterpart in Definition 6 at all — it is a semantic coherence condition.
* **the entailment clause.**  Definition 6 asks that the source theory's `⇒` map into the target
  theory's `⇒′`.  The field `ent` transports **`SEntails`**, the *semantic* consequence relation,
  and is proved by one application of `pred`.  `eEnt_to_simple` starts from `EEnt`, but its
  conclusion is still `SatS`, i.e. still semantic; nothing in the module produces a derivation in
  Rose's `⇒simp`.

Everything the module proves under this name is TRUE and useful; the *name* is wrong.  So is the
memo's original Rank 2 bullet, "The homomorphism into simple rows (Definition 6) is the inclusion
composed with `dom : (L ⇀ T) → 𝒫(L)`" — `dom` maps *out of* Rose's algebra into Ermine's, which is
the opposite direction to "into simple rows", and it is an algebra map either way.

**Is real Definition 6 reachable?**  Two answers, and both are worth writing down rather than the
current "content not quoted".

* *By the paper's own bridge, yes and cheaply.*  Take `j := lift tau` (`lift_algHom` is exactly the
  partial monoid homomorphism the bridge asks for), `f := den`, and for `ζ = K` take
  `ζ′ :=` the simple row listing each `ℓ ∈ K` at type `tau ℓ`; the bridge's side condition
  `∀ζ ∃ζ′. j(f(ζ)) = g(ζ′)` is then met — and it is *the same restriction* as the module's
  `tau`-slice, which answers the review brief's question "is that a restriction Definition 6
  allows?".  Definition 6 itself allows anything (it never mentions models); the paper's bridge
  *requires* precisely this slice condition.  Caveat: the bridge is prose and unproved in the paper.
* *Directly, probably not.*  Definition 6's second clause would need `EEnt G c ⟹ ⇒simp h(G) h(c)`,
  and the memo's own §1.3 is the obstruction: `⇒simp`'s two ground axiom schemes fire only on
  fully spelt-out rows, so `Witness.ent_x` (`{a <- (x,y), a <- ()} ⇒ x <- ()`) has no `⇒simp`
  counterpart.  Worse, "h extended to predicates in the obvious fashion" is not well-defined here:
  `Basic.lean`'s `Constraint` is `⟨lhs : Var, vars : List Var, conc⟩`, so **Ermine has no ground
  predicates at all** — every constraint is over variables, and an assignment must be supplied
  before any map on rows induces a map on predicates.  That obstruction is itself a finding worth
  keeping.

**Recommended fix (K-1).**  Rename the structure to something like `SimpleRowTransport`; quote
Definition 6 verbatim in the docstring with an explicit "NOT proved here, and here is why"; label
`dom_hom` / `lift_algHom` as the paper's *partial monoid homomorphisms*, citing the sentence above;
and record the bridge as the named route to Definition 6.  Then correct the report §2/§4/§8, the
`Rowpartition.lean` docstring entry, the memo Rank 2 note and the plan row, all of which repeat the
claim.

---

## 2. The PARTIAL, and the replacement (review brief §2)

### (a) The counterexample is genuine — CONFIRMED, re-elaborated independently

I did not reuse `MintWitness`.  `Check1.lean` in scratch builds its own (`namespace RevMint`):
`G₀ = { 0 <- (1, 2, (|ℓ|)) }` with `ℓ = 0`; a real `NDStep.splitFree` step with all five
`SplitApp` premises discharged from scratch (`mem`, `conc_ne`, `two_le`, `unnamed`,
`fresh : 3 ∉ allVars G₀`); the assignment `rho = [0 ↦ {ℓ}, 1 ↦ ∅, 2 ↦ ∅, 3 ↦ {ℓ}]`; `is_model`,
`refutes`, `not_entailed`.  It elaborates clean.  So: the minted `3 <- (1, 2)` is derivable and is
not entailed.

**And the failure is structural, which the report only half says.**  Definition 2's second
condition quantifies `θ` over `fv(P, ψ)` — *including the variables that occur only in the
conclusion*.  A mint puts a fresh variable in `fv(ψ) \ fv(P)`, so `θ` is free to send it anywhere
and soundness cannot hold.  **No minting rule can ever be an entailment rule in Rose's sense**, for
any row theory, and that is a stronger and cleaner statement than "the fresh variable is
unconstrained by `G`".  It is also the exact dual of the memo's §1.1 last bullet (Rose's predicate
language has no existential; `Has a b = exists c. a <- (b, c)` is Ermine's workaround at the
surface and its mints are the same workaround at solve time).  Worth putting in the report in that
form.

### (b) `MFStep` is exactly `LoopRel` minus `weaken` minus the four mints — CONFIRMED both ways

The module proves only `MFStep.toLoopRel` / `NDStep.toLoopRel`, i.e. the *easy* inclusion.  I
proved the converses (`Check1.lean`):

```lean
theorem rev_loopRel_split (h : LoopRel G G') : NDStep G G' ∨ G' ⊆ G
theorem rev_ndStep_split  (h : NDStep G G') :
    MFStep G G' ∨ K2SplitStep G G' ∨ ResStep G G' ∨ SplitStep G G' ∨ K2ResStep G G'
```

Both elaborate.  The constructor lists, from `Loop/Refine.lean:345`:

| relation | constructors |
|---|---|
| `LoopRel` (**10**, K-8) | `nongen`, `split`, `res`, `splitFree`, `kres`, `weaken`, `renameLhs`, `linkSymm`, `emptyProp`, `dedup` |
| `NDStep` (9) | the above minus `weaken` |
| the four mints | `split` = `K2SplitStep`, `res` = `ResStep`, `splitFree` = `SplitStep`, `kres` = `K2ResStep` |
| `MFStep` (5) | `nongen` = `SplitNecessary.NonGenStep`, `renameLhs`, `linkSymm`, `emptyProp`, `dedup` |

One precision the report should add: `nongen` is not mint-free by *stipulation*.
`SplitNecessary.NonGenStep` is "every rule that does not call `fresh` … No rule here mints" and
bundles six sub-relations, one of which is `SplitReuseStep` — **`splitConcrete`'s reuse branch**.
So `splitConcrete` is not wholly outside `⇒`; only its minting branch is.  Likewise
`Cut.CutStep` (the `cse` case) is reuse-and-fold only, `CseBranch.mint` being absent from `LoopRel`
altogether.  The report's blanket "`splitConcrete` and `resolution` MINT, so they are conservative
extensions and not entailments" (§5, last bullet) reads as if the whole rules were excluded.

### (c) `MFStep.conserv` and `NonGenStep.models_iff` do give Definition 2's soundness — CONFIRMED

`NonGenStep.models_iff` (`SplitNecessary.lean:613`) is an `iff` on models, so it is *stronger* than
Definition 2 needs, exactly as the report says; the other four constructors go through
`renameLhs_sat` / `linkSymm_sat` / `emptyProp_sat` / `dedup_sat` (`Refine.lean:383`ff), and
`MFStep.models` assembles them.  `MFStep.conserv` is `Loop.Conserv`, which is Definition 2's
condition read constraint by constraint.  No objection.

I also checked the fragment is not partly dead: `Witness` exercises only `emptyProp`, so I
instantiated the other three (`Check2.lean`: `rev_dedup_live`, `rev_renameLhs_live`,
`rev_linkSymm_live`, plus `rev_dedup_sound : SEntails {0 <- (1,2), 1 <- (2)} (2 <- ())`).  All live.

### (d) The memo's Rank 2 was wrong — CONFIRMED — and the DONE note is incomplete

"(2) *soundness of `⇒` for the algebra* — this is **already proved**: `LoopRel.sat`" is false, now
against the paper's text and not only against the memo.  The DONE note R2 added corrects that
sentence.  It does **not** correct two others in the same item: the *Risk* bullet's "the only hard
lemma already exists" (and "one new Lean module of order 150 lines" — the module is 1,061), and the
Definition 6 bullet.  Recommended wording is K-12.

### (e) `Goal_nd_ent_sound` — well-posed, but it is the wrong question (K-3)

```lean
def Goal_nd_ent_sound : Prop := ∀ G c, Ent NDStep G c → SEntails G c
```

Well-posed: it is a closed `Prop`, and the module is right that `MintWitness` does not settle it
(that witness is a `Derives`, and `Ent` quantifies over every `H ⊇ G`, in which a mint of the
*named* variable 3 is blocked by `fresh`).

Three objections.

1. **The cost sentence has the two directions swapped.**  "[R]efuting it would need a closure
   argument over five rule families … (≈400 lines); proving it needs a renaming theory for minted
   variables."  A closure argument over the rule families is what shows *no* derivation from a
   blocking `H` reaches the minted conclusion — that is evidence *for* the goal, and it is what
   **proving** it needs.  **Refuting** it needs the opposite: a construction that produces a
   non-entailed conclusion from *every* context, i.e. one that survives freshness blocking (for
   instance by composing a mint with `emptyProp`/`dedup`/`renameLhs` so that the surviving
   conclusion names only old variables).
2. **The question that matters is not open.**  Restrict the conclusion to the input's own
   vocabulary and the *full* minting fragment becomes Definition-2 sound.  `Check3.lean`, ~50 lines,
   elaborates clean:

   ```lean
   theorem rev_ndStep_extend (h : NDStep G G') (hm : SModels rho G) :
       ∃ rho', SModels rho' G' ∧ ∀ v ∈ allVars G, rho' v = rho v
   theorem rev_nd_derives_sound_on_vocab
       (h : Derives NDStep G c) (hlhs : c.lhs ∈ allVars G) (hvs : vset c ⊆ allVars G) :
       SEntails G c
   theorem rev_nd_ent_sound_on_vocab   -- the same for the context-closed reading
   ```

   Every ingredient was already in the tree: `KeyedRow.K2SplitStep.extend` and
   `K2ResStep.extend` (both already in the agreement form `∀ v ∈ allVars G, rho' v = rho v`),
   `ResGuard.mint_extend`, `SplitNecessary.split_mint_conservativeExt` (through `Cut.SConservativeExt`),
   and `Divergence.sat_congr_of_agree`.  I wrote no new mathematics; I assembled five existing lemmas.
3. **The library already does this for the CSE mint, and the module does not mention it.**
   `Cut.CseStep.entails_iff` (`Divergence.lean:411`) and `Cut.CseBranch.entails_iff` /
   `BranchSteps.entails_iff` (`Cut.lean:378, 424`) carry *exactly* the hypotheses
   `c.lhs ∈ allVars G` and `vset c ⊆ allVars G`, and `Cut.cut_preserves_meaning` states the
   conclusion in words: "over the input's own vocabulary, entail exactly the same constraints".
   So §0's "What the minting fragment does satisfy is recorded separately and honestly, as
   `ndRun_ssat` … a **conservative extension**, not an entailment" understates the tree by a wide
   margin: satisfiability preservation is the *weakest* of the three things available, and the
   strongest — vocabulary-restricted model preservation — is the one that explains why the
   compiler's mints are harmless.

   `nd_derives_not_entails` is not touched by any of this: its `minted` has
   `lhs = 3 ∉ allVars G₀`, which is what a mint is for.

**Recommendation.**  Keep `Goal_nd_ent_sound` as a curiosity, but demote it, add the
vocabulary-restricted theorem (it is short and it is the real content), and rewrite §0's last
paragraph and §5's "the two most load-bearing solver rules are outside the entailment relation"
around it: the mints are outside `⇒` *only for conclusions that mention the minted name*.

---

## 3. Do the main theorems say what the report says? (review brief §3)

Read in full, statement by statement.  All four say what the report says, with the qualifications
below.

* **`sat_iff_pfold`** — `Sat rho c ↔ labelAlgebra.pfold (parts rho c) = some (rho c.lhs)`.  Correct
  and load-bearing.  `Basic.lean:56-61` gives `parts rho c = c.conc :: c.vars.map rho` and `Sat` as
  union-equality ∧ pairwise-disjointness, and `pfold_label` splits the fold into exactly those two,
  so "definedness = disjointness, equality = completeness" is precise.  This is the best thing in
  the module and it is the thing R3 actually needs (K-10).
* **`ermine_isRowTheory : IsModel labelAlgebra ermineTheory den Sat zeta0`** — correct.  Small
  imprecision: the report calls it "the three conditions", and `IsModel` has four fields; the
  fourth, `pred_algebraic`, is Rose's *definition* of `⊨` (K-6(a)), so "the three conditions plus
  the definition of `⊨`" is the accurate phrasing.  `ζ₀ = (||)` holds at `den`, unconditionally;
  the second, solver-level reading via `zeta0_constraint` is a good addition.
* **`ermine_to_simple_hom`** — every listed property is really proved: `map_op` is an `Option`
  equality so definedness is preserved in both directions; `map_eps`; `pred` via `satS_lift_iff`;
  `ent`; `dom_lift` is the retraction; `lift_dom_unit` the inverse at `T = Unit`.  The
  `tau`-slice restriction is real and correctly flagged (§8 item 4) — `satS_lift_iff`'s `sigma` is
  always `fun v => lift tau (rho v)`, never an arbitrary `Var → PMap T`.  On the review brief's
  question "is that a restriction Definition 6 allows?": Definition 6 says nothing about models, so
  the question is answered by the paper's *bridge* instead, and there the slice is not merely
  allowed, it is the stated hypothesis (§1 above).  The name of the structure is K-1.
* **Non-vacuity.**  `Witness.ent_x` / `ent_y` / `run_both` / `entails_x` / `models` /
  `models_conclusion` / `simple_models` all check out and do establish that `EEnt` is not empty and
  `IsModel` not vacuous.  `taut_entailed` does **not** — K-5.

### A hypothesis no real constraint set satisfies (the review brief's challenge)

I tried and failed to find one, which is the right outcome.  None of the four main theorems has a
hypothesis at all beyond `tau : Label → T`; `IsModel`'s fields are all discharged; `MintWitness`'s
five `SplitApp` premises are discharged concretely and I re-discharged them independently; the four
`MFStep` constructors other than `nongen` are each instantiated (§2(c)).  The one place a reader
should look twice is `RowTheoryHom.pred`, which is an `iff` at the slice — but it is proved, not
assumed, so there is no vacuity there either.  The closest thing to a vacuous statement in the
module is `taut_entailed` being *presented* as non-vacuity evidence for `EEnt` when it is a
statement about `SEntails` (K-5).

### K-5, in detail

`MFStep` is non-generative: I proved `rev_mfStep_allVars : MFStep G G' → allVars G' = allVars G`
and its run form (`Check4.lean`), whence

```lean
theorem rev_eEnt_empty_false (r : Var) : ¬ EEnt (∅ : System) (mk r {r} (∅ : Row))
```

So `a <- (a)` is semantically entailed by the empty system and **not** derivable in the exhibited
`⇒`.  That is an *incompleteness* witness for `ermineTheory` — a perfectly honest one, since
Definition 2 asks only for soundness, and worth keeping for exactly that reason — but §6's framing
("All kernel-checked, so neither `EEnt` nor `IsModel` is vacuous", followed by three bullets of
which `taut_entailed` is one) invites the opposite reading.

### K-4, in detail

The report says of the `Ent`-versus-`Derives` choice that the converse "is exactly what the frame
lemma would buy, and for `MFStep` it is available (`MFStep.mono` …) though not needed".  It is
worth two lines of Lean, because without it a reader must wonder whether `Ent` was chosen to make
transitivity cheap at the cost of a smaller `⇒`:

```lean
theorem rev_ent_iff_derives : Ent MFStep G c ↔ Derives MFStep G c
```

(`Check1.lean`, via `rev_mfRun_mono`).  So `EEnt` **is** plain derivability, and the context
closure costs nothing on the fragment the row theory is built on.  It costs something only on
`NDStep`, which is precisely why `Goal_nd_ent_sound` is stated there.

### K-7, in detail

* **Arity and `≼`.**  Rose's combination predicate is binary and comes with a companion containment
  predicate; Ermine's is n-ary and has no `≼`.  `sat_iff_pfold` is about the *algebra*, where the
  n-ary fold is unimpeachable, so the theorem is right — but §5's "Ermine's predicates are now
  exhibited as a row theory's predicates" glides over the fact that one n-ary Ermine constraint is a
  *conjunction* of Rose predicates with an existential intermediate (memo §1.2 spells this out:
  `a <- (b,c,d)` is `b ⊙ u ∼ a, c ⊙ d ∼ u`).  And that intermediate is the same existential the
  mints supply — so the arity gap and the mint failure are one phenomenon, which would strengthen
  §0 if said.
* **`∼` is discretised.**  `ermineTheory.psim = Eq` on `Constraint`, and `Constraint.vars` is a
  `List`.  I confirmed (`Check2.lean`) that `⟨0,[1,2],∅⟩ ≠ ⟨0,[2,1],∅⟩` (`rev_perm_ne`, by
  `decide`) while `rev_perm_same_models` proves they have identical model sets.  Rose's `∼simp`
  "identifies sequences up to permutation"; the exhibited `∼` does not.  `perm_already_equal` is a
  statement about `mk`'s **`Finset`** argument — `mk a S k = ⟨a, slist S, k⟩` (`Divergence.lean:116`)
  canonicalises — which is a different claim from "permutation is equality on predicates".
  Definition 1 permits any equivalence, so nothing is wrong; but "∼-invariance is free" is free
  because `∼` was taken as small as Definition 1 allows, and one sentence should say so.

---

## 4. R2.4, honestly (review brief §4)

### Theorem 11 (`:1010`) — statement CONFIRMED verbatim, transfer correctly refused

> **Theorem 11 (Principality).** If P | Γ ⊢ M ⇝ E : σ, then there is some (P₀ | σ₀) such that
> P₀ | Γ ⊢ M ⇝ E : σ₀ and for all (P | σ) such that P | Γ ⊢ M ⇝ E : σ, (P₀ | σ₀) ⊒ (P | σ).

The memo's §2 row 2 quotes it accurately, un-subscripted `E` included (§5.4 item 2's uncertainty is
therefore about the paper, not about the memo).  The report's three reasons for non-transfer all
hold:

* **(i) scope.**  CONFIRMED at the source: Theorem 11 is about Rose's *typing judgment*, and the
  paper's own proof sketch is "we construct a syntax-directed variant of the type system, adapt
  Algorithm M … and then show soundness and completeness relationships between each".  Being a row
  theory is a hypothesis of Rose's calculus, not of Theorem 11's proof; exhibiting `ermineTheory`
  makes the *statement* available and nothing more.  The report says exactly this.
* **(ii) Rose buys principality by never solving.**  CONFIRMED against `A1-REVIEW.md` §R-6 (line
  513): `RevenueShare.shareOfGroup`'s published type is strictly MORE GENERAL at the new dequeue
  order, `OLD ⊨ NEW` and `NEW ⊭ OLD`, over the same body, "It is the dequeue order"
  (`A1-REVIEW.md:420`).  The report's direction of generality matches the memo's §1.5 and the
  review's.
* **(iii) the compiler does not run `⇒`.**  True, and K-3 sharpens it: after the vocabulary
  restriction, the *mints* are back inside a Definition-2-sound relation, and what remains outside
  is `weaken` alone.

### Theorem 15 / Definitions 13 and 14 (`:1048`–`:1056`) — CONFIRMED, with corrections

> **Definition 13.** We define T⁺_Ψ as the smallest set U such that • T ⊆ U; and, • if
> ζ₁ ⊙ ζ₂ ∼ ζ₃ ∈ Ψ, and fv(ζ₁, ζ₂) ⊆ U, then fv(ζ₃) ⊆ U.
> **Definition 14.** A type scheme ∀T.Ψ ⇒ τ is coherent if T ⊆ fv(τ)⁺_Ψ. **A term M is coherent if
> its principal type scheme is coherent.**
> **Theorem 15 (Coherence).** If M is coherent, P₁ | Γ ⊢ M ⇝ E₁ : σ₁, P₂ | Γ ⊢ M ⇝ E₂ : σ₂ and
> C : (P₁ | σ₁) ⊒ (P₂ | σ₂), then C E₁ =βη E₂.

**The `pivotData` claim reproduces on the compiler (K-9).**  One JVM,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false"`,
`bin/ermine core/examples/PivotTest.e` with `:type pivotData` on stdin; every `.ei` created was
deleted afterwards and the tree's `.ei` set is byte-identical to before.  Output (scratch
`pivot2.log`):

```
forall (s: rho).
  (exists (i: rho) (v3: a) (RUnion2: b -> c) (v31: b) (v32: d) (RUnion21: d -> c)
          (RUnion22: rho -> c).
   RUnion22 v3 v31 (|Value|), RUnion2 v31 v32 (|Value|),
   (|Issue, Key, Value|) <- ((|Key|), v3, i),
   RUnion21 v32 (|Value|) (|Value|), s <- ((|Sector, Price, MarketCap|), i)) => Mem s
```

So the constraint is there, existentially bound, exactly as `TICKET-row-constraint-decision.md`
§1.3 records (variables renamed: the ticket writes `i, v3` in the other order).  "Four solutions" is
right: `v3 ⊎ i = {Issue, Value}` over two labels has `2² = 4` ordered complementary pairs.  And it
is incoherent by Definition 14: `fv(τ) = fv(Mem s) = {s}`, and Definition 13's closure of `{s}` over
this Ψ adds nothing (every combination predicate has a part whose free variables are outside `{s}`),
so `T ⊄ fv(τ)⁺_Ψ`.  §8.7's alias-expansion oddity (`RUnion2` et al. as existentially quantified
constructor variables of arrow kind) reproduces too.

Three corrections and one addition to the report's §5:

1. "left unsolved in the **shipped `.ei`**" — no `.ei` is checked in for `PivotTest` (the tree's 143
   `.ei` files are all under `tracker/g1-baseline/`).  The residual is in the *inferred signature*,
   which is what I measured; say that.
2. **An unnamed prior obstruction.**  Definition 14 defines coherence *of a term* through its
   **principal type scheme** — and the report's own §5 argues Ermine has no principality theorem.
   So for Ermine, Definition 14 is not merely *unmet*, it is not yet *well-defined*.  That is a
   stronger and more useful statement than "a named unmet hypothesis", and it should be the
   headline.
3. **`∀` versus `∃`.**  Definition 14 quantifies `∀T.Ψ ⇒ τ`; Ermine binds `i`, `v3` and the rest
   **existentially**.  Reading Ermine's `exists` binder as Rose's `∀T` is an interpretation, not an
   identity, and R3 will have to make it explicitly.
4. The supporting code claims are accurate: `Subst.scala:1723-1724` is
   `val am = ambiguitiesIn(exts, complex)` with `complex = reduce(classes)`, and the row parts
   (`dumb`) reach `pruned` without passing through it; `ambiguitiesIn` at `:371-372` is
   `typeVars(p).exists(_ == v)` with no closure; `split`/`ambiguities`/`defaultSubst` at `:374-386`
   are indeed callerless.

### What R3 inherits — K-10

**Definition 13 mentions neither `⇒` nor models.**  It is a closure on the *predicates* of `Ψ`.  So:

* **Inherited, and load-bearing:** `sat_iff_pfold`, which licenses reading an Ermine constraint as a
  combination predicate and therefore restating Definition 13's clause n-arily
  (`fv(all parts) ⊆ U ⟹ fv(lhs) ⊆ U`); and `labelAlgebra` being a genuine partial monoid, which is
  what makes "determined" mean anything at all — in a partial monoid the combination is a *function*
  of the parts where it is defined.  Those two are the licence, and they are green.
* **Not inherited, and R3 should not wait for it:** anything about entailment.  The `MFStep`
  restriction, `nd_derives_not_entails` and `Goal_nd_ent_sound` are all irrelevant to Definition 13.
  **The PARTIAL does not weaken the licence R3 needs**, and the report should say so in as many
  words, because a reader of §0 could easily conclude the opposite.
* **R3 must supply for itself:** the n-ary restatement; the *larger*-than-Rose closure the memo
  already identifies (cancellation determines a part from the whole and the other parts once the
  concrete parts are known); the `∀`/`∃` reading (K-9(3)); and the fact that Theorem 15 is
  unavailable as a *guarantee* because Definition 14 is not well-defined for Ermine (K-9(2)) — so
  Definition 13 can be imported as a **criterion**, which is all the memo ever claimed for rank 4.

---

## 5. Gates, re-run (review brief §5)

| gate | reviewer's number | report's number | verdict |
|---|---|---|---|
| `lake build` (default target) | **869 jobs, "Build completed successfully"** | 869 | MATCHES |
| `lake env lean Audit.lean` | **4,427 theorems audited; 0 declarations using a non-standard axiom** | 4,427 / 0 | MATCHES |
| `#print axioms`, regenerated | **257 non-internal declarations under `Rowpartition.Rose`, of which 132 theorems; 0 non-standard-axiom users over all 257.**  Theorem breakdown **102** `[propext, Classical.choice, Quot.sound]`, **14** `[propext, Quot.sound]`, **2** `[propext]`, **14** none | 132; 102 / 14 / 2 / 14 | MATCHES to the digit, and my sweep is strictly wider (definitions and projections too).  No `sorryAx`, no `nativeDecide`, no `ofReduceBool` |
| `sorry` / `partial` in the source | none (`grep` hits are the word "partial" in prose only) | none | MATCHES |
| `git diff --stat` | **3 files, 61 insertions(+), 0 deletions** — `Rowpartition.lean` 18+, `ROSE-COMPARISON.md` 42+, `LOOP-MODEL-PLAN.md` 1+; untracked: `RoseTheory.lean`, `R2-ROSE-THEORY.md` (and now `R2-REVIEW.md`) | same | MATCHES.  No Scala, no examples, no `.ei`, no executable Lean |
| `looptrace` mtime | **`2026-09-07 15:12:54.333891088 -0600`, 292,801,216 bytes**, unchanged across my `lake build` | same | MATCHES |
| commits | none | none | MATCHES |
| plan row (`LOOP-MODEL-PLAN.md`) | present, accurate against the report | — | ACCURATE, except that it repeats the Definition 6 claim (K-1) |
| Rank 2 note (`ROSE-COMPARISON.md`) | present, dated, additive (42 lines, 0 deletions) | — | ACCURATE, except K-1 and the two uncorrected claims of K-12 |

**Baselines.**  I did **not** re-derive the 868 / 4,295 baselines: doing so means editing the root
import list, which this review forbids.  The arithmetic is self-consistent — `4,427 − 4,295 = 132`,
which is exactly the theorem count I measured independently.

**K-11, the one nuance.**  The report says the module "has **no long lines and no `simp`/unused-variable
warnings**".  True as written — I checked, there is no line over 100 characters and no `simp`
warning.  But the module *does* emit seven header-linter warnings of its own
(`RoseTheory.lean:57:0` "The module doc-string for a file should be the first command after the
imports", plus six doc-string text warnings at `:2`, `:4`, `:5`, `:8`, `:53`).  Since **65 of the
project's Lean files** emit the same doc-string warning, the report's "project-wide Mathlib style
set" characterisation is right in substance; the sentence is just slightly narrower than the facts.
Total build warnings: 2,182, of which 170 are one `simp` argument list in `NameLossClosed.lean`.

---

## 6. K-12 — recommended wording for the memo's correction note

To be inserted by the implementer or the orchestrator (I have not written it).  Additive, under
Rank 2, after the existing `DONE 2026-09-07` block:

> **CORRECTION (2026-09-07, R2 review).**  Two further claims in this item are wrong, and the
> paper was obtained during the review, so both are now checkable.
>
> 1. The *Risk* bullet's "the only hard lemma already exists" and "one new Lean module of order
>    150 lines".  `LoopRel.sat` is *satisfiability* preservation; Definition 2's second model
>    condition is *model* preservation — "If `P ⇒ ψ`, then for each ground substitution `θ` on
>    `fv(P,ψ)`, `f ⊨ θP` implies `f ⊨ θψ`" (paper, verbatim).  For a MINT no such lemma can exist:
>    the fresh variable lies in `fv(ψ) \ fv(P)`, which `θ` ranges over, so **no minting rule is an
>    entailment rule in Rose's sense, in any row theory**.  The lemma that does the work is
>    `NonGenStep.models_iff`, on the mint-free fragment, and the module is 1,061 lines.  What the
>    minting fragment *does* satisfy is not only `LoopRel.sat` but the library's own
>    vocabulary-restricted form — `Cut.CseStep.entails_iff`'s shape, `SEntails G' c ↔ SEntails G c`
>    for `c` phrased inside `allVars G` — which the review proves for all four mints in ~50 lines
>    from `K2SplitStep.extend`, `K2ResStep.extend`, `ResGuard.mint_extend`,
>    `split_mint_conservativeExt` and `sat_congr_of_agree`.
> 2. "The homomorphism into simple rows (Definition 6) is the inclusion composed with
>    `dom : (L ⇀ T) → 𝒫(L)`."  Definition 6 is a map `h : R₁ → R₂` on **syntactic rows** with two
>    clauses, `ζ₁ ∼ ζ₂ ⟹ h(ζ₁) ∼′ h(ζ₂)` and `P ⇒ ψ ⟹ h(P) ⇒′ h(ψ)`; maps of *algebras* are the
>    paper's separate notion ("Row algebras are related by partial monoid homomorphisms"), and
>    `dom` runs from Rose's algebra into Ermine's, not into simple rows.  R2 proves the partial
>    monoid half (`dom_hom`, `lift_algHom`) and model-level transport; **Definition 6 itself is not
>    proved**.  The cheapest route to it is the paper's own bridge — a partial monoid homomorphism
>    `j` together with `∀ζ ∈ R. ∃ζ′ ∈ R′. j(f(ζ)) = g(ζ′)` yields a row theory homomorphism — whose
>    side condition is exactly R2's `tau`-slice.  A direct proof is probably blocked: `⇒simp`
>    derives none of Ermine's rules (§1.3), and Ermine has no *ground* predicates for `h` to be
>    "extended to … in the obvious fashion" (`Constraint` is always over variables).

---

## 7. What I ran

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-R2/`.

| file | what it is |
|---|---|
| `rose.pdf` / `rose.txt` | the paper (Wayback snapshot of the ACM CC-BY PDF) and its extracted text |
| `PrintAxioms.lean` / `PrintAxioms2.lean` / `print-axioms.txt` | the regenerated axiom sweep over all 257 `Rowpartition.Rose` declarations, and the theorem-only breakdown |
| `Check1.lean` | `rev_loopRel_split`, `rev_ndStep_split`, `rev_mfRun_mono`, `rev_ent_iff_derives`, `namespace RevMint` (the counterexample, re-elaborated from scratch) |
| `Check2.lean` | `rev_perm_ne`, `rev_perm_same_models`, `rev_psim_discrete`, `rev_dedup_live`, `rev_dedup_sound`, `rev_renameLhs_live`, `rev_linkSymm_live` |
| `Check3.lean` | `rev_ndStep_extend`, `rev_ndRun_extend`, `rev_nd_derives_sound_on_vocab`, `rev_nd_ent_sound_on_vocab` |
| `Check4.lean` | `rev_mfStep_allVars`, `rev_mfRun_allVars`, `rev_eEnt_empty_false` |
| `build.log` | the full `lake build` output (869 jobs, warning census) |
| `pivot.log` / `pivot2.log` | the single compiler run; `ei-before.txt` / `ei-after.txt` / `ei-final.txt` show the 129 `.ei` it created and their deletion |

All four `Check*.lean` files elaborate with `lake env lean` under
`PATH=$HOME/.elan/bin:$PATH`, `LEAN_NUM_THREADS=2`, exit 0, no errors and no warnings.  One
`lake build`, one JVM, nothing else.
