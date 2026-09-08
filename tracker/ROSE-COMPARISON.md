# Rose and its successors versus Ermine's row solver

Stage R1 of the loop-model programme (`tracker/LOOP-MODEL-PLAN.md`), 2026-09-07.  A reading and
writing stage: nothing in `core/` or `tracker/lean/Rowpartition/` was touched, nothing was
committed, and the only machine work was elaborating one scratch Lean file (§4) against the
existing library.

**The question, from the user (2026-09-06):** *"are there further parallels between our work and
that of Rose and successors?  Could we adopt any ideas?  Is this something that could be explored
by an agent?"*

**The short answers.**

* **Ermine implements Rose's *simple row theory*** over a degenerate row algebra — finite label
  sets under disjoint union, with no field types in the row at all (§1.1).  The parallel is exact
  at the level of the *predicates* and empty at the level of the *rules*: Rose's entailment
  relation for simple rows is **monotonicity, transitivity and two ground axiom schemes, and
  derives none of Ermine's eleven inference rules** (§1.3).  So there is **no rule Rose has that
  Ermine's saturation lacks**, and Rose is not the explanation for the refutation-incompleteness
  S1 found.
* **The deepest parallel is not about rules at all — it is about principal types** (§1.5).  Wand
  proved a concatenation calculus has *no* principal type but a *finite complete set* of them;
  Rose gets principality back by **never solving**; Ermine keeps the predicates *and* solves, and
  `A1-REVIEW.md` §R-6 is a measured instance of it publishing a strictly less general residual
  under one dequeue order than under another.  Ermine is in neither published position, and
  "principal types for Ermine" is an open question rather than a background assumption.
* **Three of the adoptable ideas are Rose's *structure*, not its rules**: a primitive containment
  predicate, the generality ordering `⊒` on constrained type schemes as the correctness criterion
  for any simplifier, and **Definition 13's determinacy closure**, which is the principled version
  of the guard `Subst.reduce`'s splice had, was measured with, and lost.
* **And the highest-payoff item is not from the papers at all.**  Looking for Rose's simplification
  step led to Ermine's — `Subst.mkSimplified`, which already tries to delete permuted duplicates
  and already fails to, because `NormalPart` overrides `equals` and not `hashCode` under a
  hash-based `distinct` (§3 rank 1).  That, plus a missing `None` case that publishes the tautology
  `a <- (a)`, is a one-stage fix for the largest measured class of residual noise.
* **"Could this be explored by an agent?"  Yes, and this memo is the evidence** — but only because
  the tree already carries what an agent needs: a trace-equal Lean model, a corpus differential, an
  `.ei` sweep with a classifier, and hand-written entailment certificates in
  `core/examples/incomplete/Signatures.e`.  The nine ranked items in §3 are sized in agent-stages
  precisely so they can be run that way, and ranks 1, 2 and 6 are each a single stage with
  mechanical acceptance criteria.  What an agent should **not** be sent to do unaided is rank 4 or
  rank 7: both change what the compiler accepts, and both were tried before in some form and
  withdrawn on measurement.

---

## 0. Vocabulary

Defined once, because this memo is meant to be readable by a language designer who has not
followed the loop-model programme.

**Ermine side.**

| term | meaning |
|---|---|
| *label* / *field* | a record column name.  In Ermine a value of type `Name`; the universe is unbounded. |
| *row* | a finite set of labels.  `Constraints.scala:286`: `type Fields = Set[Name]`.  **Rows carry no field types**; a field's type is carried separately by a `Field r a` witness (`modules/Field.e`). |
| *partition constraint* `a <- (b, c, (\|k\|))` | "the row `a` is the **disjoint union** of the rows `b`, `c` and the concrete singleton `{k}`".  One relation carrying concatenation, disjointness and completeness at once.  Ermine's *only* row constraint. |
| *`Partition`* | the solver's representation: `Partition(lhs: TypeVar, rhs: RHS, inf: Option[Inference])` (`Constraints.scala:1480`), where `RHS(abstr: Set[TypeVar], concr: Set[Name])`. |
| *the loop* | `Constraints.incorporateAll` (`:1544`): a saturation over a priority queue of partitions.  Each **dequeue** dispatches to one of five branches (`common`, `empty`, `concrete`, `unify`, `learn`) and may **mint** (draw a fresh row variable from the `Supply`) and may **delete**. |
| *residual* | the constraints that survive and are published as the qualification of an inferred signature: `Subst.solve` returns `Exists(l, [], reduce(l, cs map substType, es, ps))` (`Subst.scala:1260`). |
| *the loop model* | `tracker/lean/Rowpartition/Loop/`: a Lean function trace-equal to `incorporateAll` over the whole corpus (stages L1/L2). |
| `Sat`, `SModels`, `SEntails`, `SSat` | semantics.  `Sat rho c` = the assignment `rho` satisfies one constraint; `SModels rho G` = it satisfies every constraint of a system; `SEntails G c` = every model of `G` satisfies `c`; `SSat G` = `G` has a model.  (`Rowpartition/Basic.lean`, `Divergence.lean:178-196`.) |
| `NoLoss G G'` | `∀ c ∈ G, SEntails G' c` — the output still says everything the input said (`Loop/Strict.lean:48`). |
| `Conserv G G'` | `∀ c ∈ G', SEntails G c` — the output invents nothing (`:52`).  A mint fails this by construction. |
| `LoopRel` | the eleven-constructor relation the loop refines into (`Loop/Refine.lean:345`). **[Corrected 2026-09-07, R2 review K-8: TEN constructors — `nongen`, `split`, `res`, `splitFree`, `kres`, `weaken`, `renameLhs`, `linkSymm`, `emptyProp`, `dedup`.  The ELEVEN of §1.3 is the count of Ermine's RULES, which is a different tally.  `RoseTheory.loopRel_split` and `ndStep_split` are the constructor-by-constructor case analyses.]** |
| `labelDecide` | S2 layer (iii): a **complete** per-label DPLL decision on a solve's live input (`Constraints.scala:2532`, `Loop/Decide.lean:335`), default ON since 2026-09-06. |

**Rose side.**

| term | meaning |
|---|---|
| *Rose* | the calculus of Morris & McKinna, POPL 2019.  Hindley–Milner with **qualified types** (Jones), where the qualifiers are row predicates. |
| *combination* `ρ₁ ⊙ ρ₂ ~ ρ₃` | "`ρ₃` is the combination of `ρ₁` and `ρ₂`".  A three-place **predicate**, deliberately not a binary type constructor, so that the same syntax serves disjoint, overwriting and shadowing notions of extension. |
| *containment* `ρ₁ ≼ ρ₂` | "the fields of `ρ₁` are among those of `ρ₂`".  A **separate primitive**, even though `ρ₁ ≼ ρ₃ ⟺ ∃ρ₂. ρ₁ ⊙ ρ₂ ~ ρ₃` characterises its satisfiability — the paper keeps it distinct because it "more closely parallels the term structure" (§2.1). |
| *row theory* | `⟨R, ∼, ⇒⟩`: syntactic rows, an equivalence on them, and an **entailment relation on predicates** (Definition 1). |
| *row algebra* | any **partial monoid** `⟨M, ·, ε⟩` (Definition 2).  A model is a map `f : R → M` sound for `∼` and for `⇒`. |
| *simple rows* | the instance where `⊙` is disjoint union and overlapping combination is unsatisfiable. |
| *Rω* | Hubers & Morris, ICFP 2023: Fω + Rose-style rows + row-indexed type functions.  Explicitly typed. |

---

## 1. The correspondence, rule by rule

### 1.1 Which row theory Ermine implements — precisely

**Ermine implements Rose's simple row theory, in the label-only algebra
`⟨𝒫fin(L), ⊎, ∅⟩`.**  Item by item, with the evidence.

| Rose's parameter | Ermine's answer | evidence |
|---|---|---|
| the algebra `⟨M, ·, ε⟩` | finite label sets under **partial** disjoint union; unit `∅` | `type Fields = Set[Name]` (`Constraints.scala:286`); `Sat` in `Basic.lean:60` is "the lhs row is the union of the parts **and** the parts are pairwise disjoint" |
| are field **types** in the row? | **no.**  Rose's simple-row algebra is `⟨L ⇀ T, ⊔, ∅⟩` — partial maps *label → type*.  Ermine's is that algebra composed with `dom : (L ⇀ T) → 𝒫(L)`, i.e. `T` collapsed to a point | `ConcreteRho(loc, fields: Set[Name])` (`Type.scala:141`) carries labels only — there is nowhere to put a type; the field's type travels in a separate `Field r a` witness, e.g. `getF : r <- (h,t) => Field h a -> {..r} -> a` (`modules/Field.e:11`).  Decisive: `data Row (r:rho) = Row (List (String, PrimT))` (`modules/Relation/Row.e:21`) carries the field types **at run time**, because the type `r` does not carry them |
| duplicate labels? | **no.**  Combination is *undefined* on overlap and that is a **refutation** | `RHS.merge` (`Constraints.scala:357-366`): `if (cint.isEmpty) … else tml.die("Fields appear twice in row: " + cint)`.  Proved a genuine refutation as `merge_refutes` (S1 death site 1) |
| repeated **variable** parts? | forced empty, not an error | `RHS.build` (`:404-424`) moves a repeated `VarT` into `e`; `LoopRel.dedup` (`Refine.lean:377`), sound by `dedup_sat` |
| are rows ordered? | **no** at the solver level — Rose's `∼simp` "identifies sequences up to permutation" is Ermine's `Set` | `RHS(abstr: Set[TypeVar], concr: Set[Name])`; `Partition.equals` compares `(_1, _2)` only and **ignores the `inf` provenance tag** (`:1496-1499`); `hashCode` likewise (`:1501`).  In Lean, `mk a S K` takes a `Finset`, so `mk a {x,y,z} K = mk a {z,x,y} K` is a theorem (§4) |
| … at the **type** level? | **no — and this is a defect.**  `Type.Part` stores its right-hand side as a `List[Type]` and `Part.equals` compares it positionally (`Type.scala:391`), so `t <- (a,b,c)` and `t <- (c,a,b)` are two different published constraints | `A1-REVIEW.md` §R-1: `np01.inferredRestate`'s old side prints two verbatim permuted duplicates; `Signatures.e`'s `permA/permB/permC`, `perm2A/perm2B` are the hand-written proof that the rotations entail one another |
| scoping / shadowing / overwriting? | **none.**  Ermine is the *first* of Rose's three bullets — "extension is only valid for new field labels" | the `merge` death above; there is no shadowing operator anywhere in `Type.scala` or `Constraints.scala` |
| is the whole *exactly* the union? | **yes** (completeness, not just containment) | `Basic.lean:60`: `rho c.lhs = (parts rho c).foldr (· ∪ ·) ∅` |
| may the left-hand side be concrete? | in a **type**, yes (`(\|Issue,Key,Value\|) <- ((\|Key\|), i, v3)`); in the **solver**, no — `PQueue.build` mints a variable for a non-variable lhs.  The source header states this as rule 1 | `Constraints.scala:9-10`; `Type.scala:414-421` |

Two consequences worth stating.

* **Ermine's row algebra is a product over labels of the two-element partial monoid.**
  `𝒫fin(L) ≅ ∏_{l∈L} ⟨{0,1}, ⊎, 0⟩` where `⊎` is partial (undefined on `1·1`).  That *is*
  `Basic.lean`'s `sat_iff_forall_label` (`:401`), and it is why a per-label Boolean decision
  procedure (`labelDecide`) is complete.  Rose never makes this decomposition because in its
  algebra the codomain `T` is not a two-element set.
* **Rose's containment is derived in Ermine, not primitive.**  `modules/Constraint.e` defines
  `type Has a b = exists c. a <- (b, c)` — literally Rose's own characterisation
  `ρ₁ ≼ ρ₃ ⟺ ∃ρ₂. ρ₁ ⊙ ρ₂ ~ ρ₃`, spelt out as a source-level alias with an **existential row
  variable minted for the complement**.  Rose keeps `≼` primitive on purpose.  This is the single
  largest structural difference and §3 turns it into an adoptable idea.

### 1.2 The constraint forms

| Ermine | Rose |
|---|---|
| `a <- (b, c, d)` (n-ary) | `b ⊙ u ~ a`, `c ⊙ d ~ u` (binary, with `u` **named by the programmer** when the type is written) |
| `a <- (b, c)` | `b ⊙ c ~ a` — **exact match** |
| `a <- ()` | `ε ⊙ ε ~ a`; Rose has no dedicated "empty" predicate |
| `a <- ((\|k\|))` | `{k ⊲ τ} ⊙ ε ~ a`; a ground combination axiom of `⇒simp` |
| `a <- (b)` | row equality `a ∼ b`; in Rose this is `∼`, handled by unification, not by `⇒` |
| `Has a b` = `exists c. a <- (b, c)` | `b ≼ a` — **primitive in Rose** |
| `a \| b` = `exists c. c <- (a, b)` (disjointness) | `∃z. a ⊙ b ~ z` — expressible, no primitive either side |
| `RUnion2 t r s`, `RUnion3 v r s t` (`modules/Constraint.e`) | **not expressible.**  Both systems' combination is *disjoint*; non-disjoint union needs the hand-written inclusion–exclusion lattice Ermine spells out (3 constraints and 3 existentials for `RUnion2`; 4 and 7 for `RUnion3`) |

`RUnion3` is where the measured cost cliff lives (`core/examples/Ai/README.md`: inline 1.04 s, via
`withColumn` 0.50 s, via a helper bundling `RUnion3` **and** `RUnion2` "does not finish").  Rose
offers no relief for it: its simple theory has the same gap.  Its *overwriting* and *shadowing*
theories make `⊙` total but they are not union either, so they do not express `RUnion2` and would
change what Ermine's `<-` means.

### 1.3 The rules, side by side

Ermine's rule set, as documented in `Constraints.scala:31-215` and mechanised as the eleven
constructors of `LoopRel` (`Loop/Refine.lean:345-379`).  The last column is the finding.

| # | Ermine rule | Scala | Lean | Rose's `⇒simp` |
|---|---|---|---|---|
| 1 | **self-substitution** `a <- a b*` ⟹ `b <- ()` | `selfSubstitution` `:1608` | `SelfSubstStep` (`SplitNecessary.lean:497`) | **not derivable** |
| 2 | **empty partition** `a <- ()`, `a <- x+` ⟹ `x <- ()` | `makeEmpty` `:2014` | `LoopRel.emptyProp` | **not derivable** |
| 3 | **de-duplication** `a <- (C*, x*, b, b)` ⟹ `b <- ()` | `RHS.merge`'s `es`, `RHS.build` | `LoopRel.dedup` | **not derivable** |
| 4 | **split concrete** `a <- (C+, x++)` ⟹ `u <- x++`, `a <- (C+, u)`, `u` fresh | `splitConcrete` `:1753` | `SplitStep`, `SplitReuseStep`, `K2SplitStep` | **no counterpart, and none needed** — see below |
| 5 | **cancellation** | `cancellation` `:2140` | `CancelStep` (`:287`) | **not derivable** |
| 6 | **resolution** | `resolution` `:2231` | `ResStep` (`Cut.lean:888`), `K2ResStep` | **not derivable** |
| 7 | **substitution** (associativity) | `substitution` `:2296` | `SubstStep` (`:388`) | **not derivable** |
| 8 | **common partition** `a <- R`, `b <- R` ⟹ `a <- (b)` | queue `findRHS` `:550` + `unify` `:1973` | `CommonPartStep` (`:553`) | **not derivable**; the *conclusion* `a ∼ b` is `∼simp`'s business, but nothing in `⇒simp` produces it |
| 9 | **common subexpression** | `commonSubexpression` `:2309` | `CutStep` (`Cut.lean:149`) | **no counterpart** — a naming heuristic, not a logical rule |
| 10 | **disjunction** (default OFF, `-Dermine.disjunction`) | `disjunction` `:2342` | not modelled | **no counterpart** |
| 11 | **destructive substitution / instantiation** — `makeConcrete` deletes | `makeConcrete` `:2063`, `destructiveSub` `:2095` | `LoopRel.weaken`, `renameLhs`, `linkSymm` | **impossible in Rose.**  Definition 1 makes `⇒` monotone (`P ⇒ ψ if ψ ∈ P`); a *deletion* has no counterpart in an entailment relation at all |
| E1 | refutation `Fields appear twice in row` | `RHS.merge` `:363` | `merge_refutes` | Rose has **no refutation judgment**.  Overlap makes `⊙` *undefined in the algebra* (Example 3), which makes the predicate unsatisfiable; `⇒simp` has no rule that says so |
| E2 | refutation `Infinite row partition` | `selfSubstitution` | `selfSubst_refutes` | ditto |
| E3 | refutation `Row types failed to unify` | `ensureSuperset` `:325` / `ensureExactly` `:341` | `ensureSuperset_refutes`, `bare_refutes` | ditto |

**What Rose's `⇒simp` actually is.**  Definition 1 requires only three things of `⇒`:
`∼`-invariance, **monotonicity** (`P ⇒ ψ` if `ψ ∈ P`) and **transitivity**
(`P, Q ⇒ φ` if `P ⇒ ψ` and `Q, ψ ⇒ φ`).  On top of that, Figure 1 gives simple rows exactly **two
axiom schemes**, both *ground in the label structure*:

```
    {ℓ₁◃τ₁,…,ℓ_m◃τ_m} ⊆ {ℓ′₁◃τ′₁,…,ℓ′_n◃τ′_n}
    ─────────────────────────────────────────────────────────   (containment)
    P ⇒ (ℓ₁◃τ₁,…,ℓ_m◃τ_m) ≼ (ℓ′₁◃τ′₁,…,ℓ′_n◃τ′_n)

    {ℓ₁◃τ₁,…,ℓ_k◃τ_k} ⊎ {ℓ_{k+1}◃τ_{k+1},…,ℓ_m◃τ_m} = {ℓ′₁◃τ′₁,…,ℓ′_m◃τ′_m}
    ────────────────────────────────────────────────────────────────────────   (combination)
    P ⇒ (ℓ₁◃τ₁,…,ℓ_k◃τ_k) ⊙ (ℓ_{k+1}◃τ_{k+1},…,ℓ_m◃τ_m) ∼ (ℓ′₁◃τ′₁,…,ℓ′_m◃τ′_m)
```

Both premises are set relations between **literal sequences of labelled types**.  Neither fires on
a predicate with a row *variable* in it.  So, from these rules, `⇒simp` proves a predicate only
when it is already assumed (monotonicity) or when every row in it is spelt out.

**One caveat, stated because I could not close it.**  Figure 1's caption says "**Excerpted** typing
and entailment rules", so the two schemes above may not be the whole of `⇒simp`.  Two other
entailment figures in the paper are not marked excerpted and both carry a rule the simple theory
would presumably also have: Figure 3 (scoped rows) derives containment **from** combination,
`ζ₁ ⊙ ζ₂ ∼ ζ₃ / ζ₁ ≼L ζ₃` and `ζ₁ ⊙ ζ₂ ∼ ζ₃ / ζ₂ ≼R ζ₃`; and §4.4 says of the trivial theory that
"the containment relations `≼L` and `≼R` are proved in terms of the corresponding combination
predicate".  For simple rows the analogue would be `ζ₁ ⊙ ζ₂ ∼ ζ₃ ⟹ ζ₁ ≼ ζ₃` (one rule, not two,
because simple combination is commutative and there is a single containment operator).  **Adding
it changes nothing in the table above**: it is a rule *about `≼`*, and Ermine has no `≼` — its
Ermine-side reading is "from `a <- (b, c)` infer `exists c'. a <- (b, c')`", which is the identity
substitution `c' := c` and is never needed, because Ermine already carries the stronger constraint.
What I can say without reservation is that **no entailment rule shown anywhere in the paper derives
any of rules 1–11**.

**Therefore: no entailment rule Rose exhibits derives any of Ermine's eleven rules, and this
asymmetry is by design, not an oversight.**  Every Ermine rule is a valid consequence *in the simple-row
algebra* — that is what the loop model's soundness lemmas (`selfSubst_sat`, `emptyProp_sat`,
`dedup_sat`, `cancel_sat`, `subst_sat`, `commonPart_sat`, `rule6`) prove — and `⇒simp` simply does
not attempt to derive them.  Definition 2 asks a model only that `⇒` be **sound** for the algebra;
it never asks that `⇒` be **complete** for it, and the paper never claims it is.  Rose's `⇒` is a
*parameter*: §4.3 says outright that the entailment rules "determine the interpretation of the
predicates, and so are left abstract."

**The one place where the arrow points the other way.**  Rule 4, `splitConcrete`, has no Rose
counterpart *because Rose does not need one*.  It exists only to re-binarise Ermine's n-ary
right-hand side — `a <- (C, x, y)` becomes `u <- (x, y)`, `a <- (C, u)` — and Rose's `⊙` is binary
already, so in Rose the intermediate `u` is written down by the programmer at the moment the type
is written and never has to be *searched for*.  `splitConcrete` is Ermine paying at solve time,
with fresh variables and a reverse lookup, for a convenience it grants at the surface.  Its mint is
one of the two generative rules that make termination hard (`Cut.lean`'s `res_no_decreasing_measure`
for the other), and it is the rule the keyed split guard (`KeyedSplit.lean`, adopted 2026-09-03)
had to be invented for.

### 1.4 What this says about the refutation-incompleteness

The brief asks whether a rule Rose has and Ermine's saturation lacks could explain the
refutation-incompleteness `S1-REVIEW.md` found.  **It cannot: Rose has no such rule.**  On the
simple row theory Rose's entailment is *strictly weaker* than Ermine's rule set.  The two known
mechanisms stay what they were:

* `MIN2` — `makeConcrete`'s unlicensed **bare-row deletion**, `ensureSuperset` being containment
  where exactness is needed (`S1-SOUNDNESS.md` §S1.1 row 4).  Closed by S2 layer (i)
  (`ensureExactly`), adopted 2026-09-06.
* `MIN1` — the loop reaches `.done` on a residual it never refuted: plain refutation
  incompleteness of the saturation, and `reduce` then publishes the violated constraint
  (`{l22} <- ({l35}, v4)`) unchecked because `case (_, cs) => cs` drops every residual partition it
  can neither instantiate nor splice (`Subst.scala:1122`).  Closed *for acceptance* by S2 layer
  (iii)'s complete per-label decision, which is not a rule of the saturation at all.

The literature that *does* bear on refutation completeness is **Pottier's constraint closure**
(LICS 2003), whose Theorem 4 is "closed and false-free implies satisfiable" — a completeness
statement neither Rose nor Ermine's saturation has.  `TICKET-row-constraint-decision.md` §9 already
records the caveat about borrowing it (its satisfiability witness is built as a *join of lower
bounds*, and Ermine's equality-only setting has no ⊔).  Nothing in Rose changes that assessment.

---

### 1.5 Principal types: three positions, and Ermine is not in Rose's

This is the deepest parallel the stage found, and it is not about rules at all.

A calculus with **record concatenation** has a well-known problem: `λmn. (m ‖ n).a` must be typed
without committing `a` to either argument.  The three published answers are:

* **Wand (LICS 1989 / Inf. & Comp. 93(1), 1991) — there is no principal type.**  Verbatim from the
  abstract: *"We show that the type inference problem for a lambda calculus with records, including
  a record concatenation operator, is decidable.  We show that this calculus **does not have
  principal types, but does have finite complete sets of types**: that is, for any term M in the
  calculus, there exists an effectively generable finite set of type schemes such that every typing
  for M is an instance of one the schemes in the set."*  The mechanism is that concatenation
  generates a *positive Boolean combination* of equations, expanded to DNF and unified disjunct by
  disjunct; Wand bounds the result at **`2^{kn}`** schemes (`n = card(L)`, `k` = the number of
  concatenations).  Harper & Pierce reach the same place from the explicitly typed side: type
  reconstruction for `λ‖` *"would almost certainly have exponential complexity because, like
  Wand's, it would be inferring not principal types but finite sets of principal types."*
* **Rose — principal types, bought by never solving.**  Theorem 11 holds because the predicates are
  *kept*: an unsolved `z₁ ⊙ z₂ ∼ z₃` in the qualification is precisely the disjunction Wand had to
  enumerate, carried as a constraint instead of being case-split.  Rose's answer to Wand's term is
  the single type `∀t z₁ z₂. (x ◃ t) ≼ (z₁ ⊙ z₂) ⇒ Πz₁ → Πz₂ → t`.
* **Ermine — keeps the predicates *and* solves, and is measured to publish a non-principal
  residual.**  `A1-REVIEW.md` §R-6: on `RevenueShare.shareOfGroup`, the shipped dequeue order
  published a residual **strictly less general** than the one the new order publishes
  (`OLD |= NEW`, `NEW |/= OLD`), over the same body, differing only in that the old side names the
  *universal* `k` where the new names a fresh existential.  Loaded alone with interfaces off, the
  two configurations still differ — *"It is the dequeue order."*

**So Ermine sits between the two and has neither guarantee.**  It keeps predicates like Rose, which
is what makes principality *possible*; but its saturation also *commits* — `makeConcrete` and
`makeEmpty` call `instantiateType` and feed row solutions back into the main unifier
(`ROW-CONSTRAINT-STATE.md` §8.6, open), and which commitments are available depends on which
constraints have been derived, which depends on the dequeue order.  That is Wand's disjunction
reappearing as a *silent choice among a finite complete set* rather than as an enumeration of it.

Two consequences worth carrying:

1. **"Principal types for Ermine" is an open question, not a background assumption**, and R-6 is a
   counterexample to the naive version of it.  §3 rank 2's row-theory correspondence is the
   prerequisite for even stating it, because Rose's Theorem 11 is stated over a row theory.
2. **Canonical simplification (§3 rank 3, §4) is not the fix for R-6.**  Canonicalisation makes
   *equivalent* residuals identical; R-6's two residuals are **not** equivalent.  The `universals`
   clause of §4.2 forbids the *symptom*, but the cause is the commitment, and the cure — if there
   is one — is in the solver, not the simplifier.  §4 says this; it is worth saying twice.


## 2. The recollections, checked

The orchestrator's summary to the user, claim by claim.  Sources are §5.

| # | claim (verbatim) | verdict |
|---|---|---|
| 1 | "Rose's row combination predicate `ρ1 ⊙ ρ2 ~ ρ3` is Ermine's `ρ3 <- (ρ1, ρ2)`, and its containment predicates play the role of `Has`" | **RIGHT, and sharper than stated.**  Under simple rows, `⊙` is interpreted in `⟨L ⇀ T, ⊔, ∅⟩` with `⊔` *defined iff the domains are disjoint* (Example 3) — that is exactly the binary case of Ermine's `<-`.  And `Has` is not merely *like* containment: `modules/Constraint.e` defines `type Has a b = exists c. a <- (b, c)`, which is Rose's own characterisation of `≼` written out.  One correction of emphasis: Rose keeps `≼` **primitive** and says why (§2.1: it "more closely parallels the term structure", and it is what makes the translation to a row-free target work); Ermine derives it, and pays an existential row variable each time. |
| 2 | "Rose keeps unsolved row predicates in the inferred type, which is what gives it principal types" | **RIGHT in substance, but the restriction is in the wrong place.**  Theorem 11 (Principality) is about *constrained type schemes* `(P \| σ)` under the generality ordering of Figure 9, and carries **no side condition**: "If `P \| Γ ⊢ M ⇝ E : σ`, then there is some `(P₀ \| σ₀)` such that `P₀ \| Γ ⊢ M ⇝ E : σ₀` and for all `(P \| σ)` such that `P \| Γ ⊢ M ⇝ E : σ`, `(P₀ \| σ₀) ⊒ (P \| σ)`."  (The evidence term `E` is written without a subscript in all three
positions in the published text.)  The paper attributes the result to the qualified-types framework wholesale: "We are able to draw almost entirely on existing work on principality for qualified types systems [Jones 1994]. We construct a syntax-directed variant of the type system, adapt Algorithm M [Lee and Yi 1998] to our type system, and then show soundness and completeness relationships between each."  The restriction the recollection half-remembers belongs to **coherence**, not principality: Theorem 15 holds only for *coherent* terms, Definition 14, `∀T.Ψ ⇒ τ` coherent iff `T ⊆ fv(τ)⁺_Ψ`. |
| 3 | "Rose simplifies to a canonical set via entailment; Ermine saturates, minting fresh row variables, and publishes whatever survives" | **The second half is right; the first half is WRONG.**  **Rose has no simplification step at all.**  There is no context reduction, no improvement in Jones's sense, no canonical form, and no algorithm for `⇒` anywhere in the paper; predicates are introduced by (⇒I) and discharged by (⇒E) against an abstract entailment judgment.  The word "simplif-" occurs in the paper only in the senses "simplifying type inference" (intro) and "simplifies reasoning" (§3).  This matters for §3–§4: canonical simplification is **not** an idea to import from Rose, it is an idea Rose *lacks*, and what Rose supplies instead is the **correctness criterion** for one (Figure 9's `⊒`) and the **licence to delete an existential** (Definition 13). |
| 4 | "Rose's core algorithmic question is 'does this context entail that predicate', proved sound against a semantic definition" | **HALF RIGHT.**  Right that `P ⇒ E : ψ` is the interface between the type system and the predicate system (§4.3).  Wrong on two counts.  (i) It is not an *algorithmic* question in the paper — Rose gives no procedure for `⇒`, no decidability result, and no complexity bound; §4.3 says the rules "are left abstract".  (ii) Soundness of `⇒` against the semantics is a **condition in Definition 2** for a map `f : R → M` to count as a *model* ("If `P ⇒ ψ`, then for each ground substitution `θ` on `fv(P,ψ)`, `f ⊨ θP` implies `f ⊨ θψ`"), not a theorem.  The theorems that *are* proved about entailment are Lemma 8 (it produces well-typed **evidence** in the target `F^{⊗⊕}`) and, through it, Theorem 12 (Soundness of the translation) and Theorem 15 (Coherence). |
| 5 | "Rose separates the calculus from the row theory and its axioms" | **RIGHT, and it is the paper's central move.**  Definition 1 (`⟨R, ∼, ⇒⟩`), Definition 2 (row algebra = any partial monoid), Definition 6 (row-theory homomorphism), Theorem 17 (a translation extends to a semantics).  "Rose itself is defined generically over a row theory." |
| 6 | "the successor calculus adds row-indexed type functions for generic programming over records and variants" | **RIGHT, with three corrections.**  (a) The **title is not** "Rows by Any Other Name Redux"; it is *"Generic Programming with Extensible Data Types; Or, Making Ad Hoc Extensible Data Types Less Ad Hoc"* (Hubers & Morris, ICFP 2023).  (b) Rω generalises Rose in **two** dimensions, not one: "Rose imposes Hindley-Milner constraints on typ[ing]… [Rω] more significantly [generalises] the record and variant operations", i.e. Rω is built on **Fω**, adds **first-class labels**, and adds the label-generic operators `ana`, `syn`, `fold`.  (c) Rω is **explicitly typed**; type reconstruction is not attempted and is flagged as an obstacle in future work: "While adapting Rω to a type system without type-level functions would certainly make type reconstruction more likely, it may also introduce limitations in Rω's expressiveness." |
| 6b | *(implicit in the brief)* "any mechanisation of Rω" | **EXISTS.**  An Agda mechanisation, cited in the paper's Data Availability Statement and by the ICFP'23 artifact.  What is mechanised is a **denotational semantics** of stratified Rω, giving *constructive* proofs of four **unnumbered** claims: "The kind system of Rω is sound", "The entailment relation of Rω is sound", "The type and predicate equivalence relations of Rω are sound", "The type system of Rω is sound".  No completeness, no decidability, no inference, no complexity.  Also note a deliberate weakening: rule (e-sing) is dropped from the mechanised equivalence so that interpretations of equivalence derivations are propositional equalities at all kinds. |
| 7 | "Palsberg and Zhao established NP-completeness for a calculus with concatenation and subtyping" | **RIGHT, and this tree's existing citation is accurate** — `TICKET-row-constraint-decision.md` §1.3 already has "Inf. & Comp. 189(1), 2004, **Thm 6.4**", and Thm 6.4 verbatim is *"The type inference problem is NP-complete"*, with membership from **Thm 5.16** (*"The type inference problem is in NP"*) and hardness from **Lemma 6.3** (*"Solving simple constraint systems is NP-hard"*, by reduction from 3-SAT) through **Lemma 6.2**.  Two corrections, both to the ticket's *gloss* rather than to its citation.  (a) The ticket calls it "**symmetric** (disjointness-guarded) record concatenation".  The concatenation is symmetric — `A ⊕ A′` is undefined when the field sets overlap — but there are **no disjointness constraints in the type language**; disjointness is enforced by **variance annotations** `{0, →}`, where `[lᵢ : Bᵢ]⁰` is *exact* and only exact types may be concatenated.  The calculus is the **Abadi–Cardelli ς-object calculus** plus concatenation, with **equi-recursive types** and **width-only, depth-free subtyping** on **invariant** fields; the authors say plainly *"Our type system is simpler and less expressive than some previous type systems for record concatenation.  Our goal is to analyze the computational complexity of type inference."*  So it is **not** a result about Rémy-style rows, nor about `lacks`/disjointness predicates, and it should not be read as one.  (b) **Do not cite the conference version.**  LICS 2002 is titled *"**Efficient** Type Inference for Record Concatenation and Subtyping"* and **claimed polynomial time**; the 2004 acknowledgments retract it: *"we mistakenly claimed that the type inference problem can be solved in polynomial time.  Two reviewers … spotted a problem in the proof of a crucial lemma.  The lemma was indeed false and, as a consequence, we realized that the type inference problem is NP-complete, and not polynomial."*  The hardness's own diagnosis is worth carrying because it is Ermine's situation too: *"there is a choice which possibly later has to be undone"*, i.e. no smallest consistent closed superset exists. |
| 8 | "GHC's constraint solver has an iteration limit and gives up with an error" | **RIGHT on the facts, WRONG on the precedent.**  The facts: `mAX_SOLVER_ITERATIONS = 4` in `compiler/GHC/Settings/Constants.hs`, unchanged from 8.0 to master; `0` means infinity; the hard error (`GHC-95822`) is `solveWanteds: too many iterations (limit = 4)` / `Unsolved: …` with the hint `Set limit with -fconstraint-solver-iterations=n; n=0 for no limit`.  The flag is **undocumented in every User's Guide since 8.4** (`docs/users_guide/expected-undocumented-flags.txt`, tracking issue GHC #18641); the only official wording is GHC 8.0.2's generated flag table: *"Typically one iteration suffices; so please yell if you find you need to set it higher than the default."*  **But it is the wrong precedent for `-Dermine.solveBudget`.**  GHC's iteration limit is a backstop on a *progress-based fixpoint that normally converges in one round*, and hitting it is treated as a **bug report**, not a tuning knob — `Note [Expanding Recursive Superclasses and ExpansionFuel]` even requires `default givenFuel < solverIterations` so that a program hits a nicer diagnostic first.  The **budget-instead-of-a-proof** precedent is the *other* flag: **`-freduction-depth`, default 200** (`GHC-40404`, `Reduction stack overflow; size = N`), whose `Note [SubGoalDepth]` says it exactly — without `UndecidableInstances` the counter is bounded by the structural depth of the type (the Paterson and Coverage conditions are the actual termination proof), *"but without it can resolve things ad infinitum.  Hence there is a maximum level"*, and *"Because this check is solely to prevent infinite compilation times, it seems safe to disable it when a user has ascertained that their program doesn't loop at the type level."*  See §5 for what that implies for two A1 open gaps. |

---

## 3. Adoptable ideas, ranked by payoff over cost

**Unit.** One *agent-stage* = one implementer agent plus one reviewer agent, against acceptance
criteria written before the stage starts (`LOOP-MODEL-PLAN.md`'s convention).  Estimates below
include the review.

**A finding that reorders the list.**  Ermine already has a residual simplifier and it is already
trying to do two of the three things §4 asks for.  `Subst.mkSimplified` (`Subst.scala:1624`), which
`generalize` calls on every inferred signature (`:1446`), documents its own job as:

> 1) Eliminate all but one permutation of a right hand side for partitions of a given variable. I.E.:
> `x <- Foo, y, Bar` / `x <- Bar, Foo, y`
> 2) Rules about existential variables are only useful inasmuch as they provide information about
> universal variables, so any rules that aren't transitively related to universal variables should
> be eliminated.

Job (2) is implemented (`isolated`, and `solve(Exists(l, List(), extinct))` runs the dropped
constraints through the solver first so an unsatisfiable set still fails).  **Job (1) is
implemented and does not work**, for a reason visible in six lines:

```scala
private case class NormalPart(loc: Loc, left: TypeVar, concrete: Set[Name], abstrakt: List[TypeVar]) {
  override def equals(a: Any) = a match {
    case NormalPart(_, l, c, a) => l == left && c == concrete &&
      a.sortWith(_.id < _.id) == abstrakt.sortWith(_.id < _.id)
  }
  …
}
…
val (dumb, extinct) = (normal.distinct.map(_.left.get.part) ++ …)
```

`equals` is overridden to ignore `loc` and to compare `abstrakt` **sorted**.  `hashCode` is **not**
overridden, so it is the synthesised case-class one: it hashes `loc`, and it hashes `abstrakt` as a
**List**, order-sensitively.  `List.distinct` is `distinctBy(identity)` over a `mutable.HashSet`
(Scala 3.3.8 on the 2.13 collections), so it buckets by `hashCode` and only then compares with
`==`.  Two permuted copies of one constraint hash differently, land in different buckets, and
**both survive** — which is exactly `A1-REVIEW.md` §R-1's finding that `np01.inferredRestate`'s
old side prints two verbatim duplicates with their parts permuted, and why `Signatures.e` has to
carry `permA`/`permB`/`permC` at all.  Two copies from *different source locations* survive for the
same reason even when the parts are in the same order.

That, and two sibling omissions found beside it, move a one-stage fix to the top of the list.

---

### Rank 1 — three sibling omissions in `mkSimplified`  ·  cost **1 stage**  ·  risk LOW

All three have the same shape: **the concrete case is handled and the variable case is not.**

1. **`NormalPart` has no `hashCode`** (`Subst.scala:1616-1621`).  `equals` is overridden to ignore
   `loc` and to compare `abstrakt` *sorted*; `hashCode` is the synthesised case-class one, which
   hashes `loc` and hashes `abstrakt` as an order-sensitive `List`.  `List.distinct` is
   `distinctBy(identity)` over a `mutable.HashSet` (Scala 3.3.8 on the 2.13 collections), so it
   buckets by `hashCode` first — permuted copies hash differently and **both survive**.  That is
   `A1-REVIEW.md` §R-1's finding, mechanically explained.  Fix:
   `override def hashCode = (left, concrete, abstrakt.map(_.id).sorted).hashCode`.
2. **`normalPart` drops the concrete identity and keeps the variable identity.**  At
   `Subst.scala:1653-1655` the `ConcreteRho` branch returns `None` (delete) when
   `vs.isEmpty && cs == s`; the `VarT` branch at `:1657-1658` has no matching case, so
   `a <- (a)` — a partition with **one part, itself** — is published.  `TopReadings.e:31` shows it
   in an inferred type and the module's own commentary calls it what it is: *"It is not a condition
   on anything; it is the solver failing to notice that a partition with one part is an identity,
   and printing it in the user's face."*  Fix: `case VarT(v) if cs.isEmpty && vs == List(v) => None`.
3. **`Part.apply` has the same gap** — there is no variable-identity case, and
   `Part.isTrivialConstraint` is `false` unconditionally (`:394`).  Fixing (2) is enough for the
   published residual; fixing (3) as well would keep the tautology out of intermediate types too.
   **Do not** route this through `isTrivialConstraint` — `Exists.isTrivialConstraint` is
   `constraints.forall(...)` (`:266`) and `Forall` drops the *whole* qualification when it is
   trivial (`:356`), so a per-constraint test there would be wrong.

   > **Correction, stage S3 review 2026-09-07 (`loopmodel/S3-REVIEW.md` K-1).**  This item as first
   > written said `Type.scala:414` "collapses `(|Foo,Bar|) <- (|Foo,Bar|)` to `Exists(l)`", i.e. that
   > the concrete case is handled here and only the variable case is missing.  **It is not.**  The
   > guard is `case ConcreteRho(lclhs, cs) if ts.isEmpty && ss == cs`, where `ss` is a `List[Name]`
   > accumulated by the fold and `cs` is a `Set[Name]`; `List == Set` is **always false** at this
   > project's Scala 3.3.8, so the case is **dead code** and the constraint is rebuilt unchanged and
   > reaches the solver.  The concrete identity is deleted from the PUBLISHED residual only, by
   > `Subst.normalPart`'s `ConcreteRho` branch, where the comparison really is `Set == Set`.  So at
   > `Part.apply` **neither** case is handled — a fourth omission of this family — and the repair is
   > one word, `ss.toSet == cs`, which belongs in the same follow-up as the variable-identity case
   > because both are on the PRE-solver path and both move the row trace.
   >
   > **FIXED, stage F3 2026-09-08** (`loopmodel/F3-FIXES.md`, commit `<commit>`).  The guard is
   > now `ts.isEmpty && ss.toSet == cs && ss.length == cs.size`.  The length test is not
   > decoration: `ss` is the concatenation of EVERY concrete part's labels, so `ss.toSet == cs`
   > alone would also fire on `(|Foo,Bar|) <- ((|Foo,Bar|), (|Foo|))`, where two parts share a
   > label and the constraint is UNSATISFIABLE rather than trivially true.  With it the case is
   > exactly "the concrete parts are pairwise disjoint and their union is the concrete whole",
   > which is a partition of a concrete row and therefore holds.
   >
   > **What it moved, measured.**  The guard fires **2,308 times in the `Algebra` corpus group
   > alone** (**1,896** pure identities `(|X|) <- ((|X|))`, **389** non-empty concrete rows split
   > into two disjoint concrete parts and **23** empty-row cases, the largest a 26-label row; and
   > of all 2,308, ZERO had overlapping parts and ZERO had a part-union different from the whole,
   > so the guard fired only on genuine partitions.  Corrected 2026-09-08 in the F3 fix round: the
   > first version of this note said 1,516 / 769 / 23, which the artefact does not support).  None
   > of them ever reached
   > `Subst.solve`: over all eighteen `looptrace-corpus.sh` groups and 3,205,346 solves the
   > compiler receives **zero** concrete-identity `in` records, before the fix or after.  They
   > come from `Constraint.e`'s `type (|) a b = exists c. c <- (a, b)` once both operands have
   > been substituted to concrete rows, and from `Subst.instantiatedAt`'s `relocateConstraints`,
   > which re-runs `Part.apply` at every instantiation of an already-solved scheme.  The
   > consequence in the trace is real and it is the fix working: over **all eighteen** groups and
   > 3,205,346 solves, **402 segments differ** — 305 CONTENT-DIFFERS, 96 PERMUTATION-ONLY, 1
   > KINDCOUNT-DIFFERS — and the dominant class is R3's `detm` record, whose residual partition
   > count **decreases 510 times and increases 0 times** (`Relation/Op.e(165:3)` 6 → 5 in every
   > group, `Present/Helpers.e(529:1)` 17 → 10, `Algebra/Comprehensions.e(123:3)` 9 → 0).  The 96
   > permutations are `Exists.apply`'s `p.toSet.toList`: swap a `Part` for an `Exists` and the
   > constraint set's hash order changes, so the survivors reach `PQueue.build` in a different
   > order and mint their existentials in it.  Fifty-nine `incomplete` solves draw one id fewer
   > (`suLo` one lower).  Two runs of one binary are byte-identical under the same comparison, so
   > it is the change and not run-to-run noise; all 153 corpus verdicts AND messages are
   > byte-identical, and ticket B6 — which does follow the id base — fires zero times here against
   > thirteen times on the shipped build.  In the PUBLISHED interfaces, measured on the repaired
   > sweep (268 per side), K-1 alone moves **4 bindings in 2 interfaces**: `Algebra/SoftSchema`'s
   > `fulcrum4`/`fulcrum5`/`pivoted` alpha-equivalent, and `cutoffGroupedFldsPosNegRel'` keeping
   > its 26 partitions with one 3-part becoming a 6-part.  3,474 bindings identical, nothing
   > weaker, none lost or added.
   > *(This paragraph first said "16 of 18 groups identical segment for segment, eight segments",
   > which was the output of an instrument comparing six of the trace's sixteen record kinds;
   > corrected 2026-09-08 in the F3 fix round, review finding N-1.)*
   >
   > **Still open, and named here so it is not lost:** the VARIABLE-identity case of item 3
   > (`a <- (a)` at `Part.apply`, as opposed to `Subst.normalPart`) and
   > `Part.isTrivialConstraint`, which is still `false` unconditionally.

* **In Rose's terms.**  (1) is `∼simp`, which "identifies sequences up to permutation" — Ermine
  honours it in the solver (`RHS` is a `Set`) and violates it in the published type.  (2) is the
  combination axiom of Figure 1 at `k = 0`: `∅ ⊎ ζ = ζ`, an instance Rose's `⇒simp` proves outright
  because `ε` is the unit of the partial monoid (Definition 2).
* **What changes in Lean.**  Nothing.  `Rowpartition.mk` already takes a `Finset`, so
  `mk a {x,y,z} K = mk a {z,x,y} K` is a *theorem* — proved in §4's scratch file as
  `perm_already_equal` — and `Rowpartition.Canonical.step_vacuous` already deletes `r <- (r)`.
  **The model is the specification here and the compiler is behind it.**
* **What it fixes.**  Measured, not hypothesised.  (1): the permuted-duplicate class of
  `A1-REVIEW.md` §R-1 — 27 of the 30 bindings the dequeue-order flip moved are alpha-equivalent,
  and `np01.inferredRestate` is classified "not isomorphic" by the report's own tooling *only*
  because two duplicates survive.  (2): `TopReadings.topRowsBy`'s residual becomes exactly
  `Has b h`, which is the signature `Signatures.topRowsByDeduped` proves the body has, and which
  `TopReadings.e:18` says is "what a competent user expects".
* **Risk.**  LOW but not zero.  `mkSimplified` is on the path of every inferred signature, so
  published `.ei` bytes move — the same one-line `find . -name '*.ei' -delete` A1 already
  documents, and rank 6 is the real answer.  Two things need acceptance criteria: (i)
  `normal.distinct` preserves first occurrence, and the surviving representative's `loc` is what a
  blame message points at, so collapsing more constraints changes *which* `loc` survives; (ii)
  `NormalPart.equals` has no default case and throws `MatchError` against a non-`NormalPart` (it
  currently never is) — fix it while touching the file.
* **Acceptance.**  `.ei` sweep over the 187 interfaces / 1,921 bindings with `ei-classify.py`:
  every moved binding ISO or strictly shorter, none weaker.  `core/test`, `TestLoopTrace` and the
  eight-group corpus differential **unmoved** — all three changes are downstream of the loop, so
  the row trace must not move by a single segment.  `Signatures.e` still checks; `perf-bench batch`
  within noise.
* **Verdict: ADOPT.**  Highest payoff per unit cost on this list, and all three are bug fixes, not
  design changes.

### Rank 2 — the row-theory correspondence, at the **model** level  ·  cost **1 stage**  ·  risk NONE

This is the brief's item **(c)**, and the verdict is **REJECT AS STATED, ADOPT THE USEFUL HALF.**

* **Why "as stated" fails.**  A correspondence theorem "between Ermine's rule set and Rose's
  axioms" is vacuous in one direction and false in the other.  Rose's two ground axiom schemes are
  instances of things Ermine's semantics makes true, so `⇒simp ⊆ LoopRel*` is a formality; and
  `LoopRel* ⊆ ⇒simp` is **false** — §1.3 shows `⇒simp` derives none of Ermine's eleven rules.
  Proving either would state nothing about the compiler.
* **What to prove instead.**  That `⟨Ermine's constraints, =, LoopRel-derivability⟩` **is a row
  theory in Rose's sense**, with the row algebra `⟨𝒫fin(L), ⊎, ∅⟩`, and that there is a **row
  theory homomorphism** into Rose's simple rows.  Definition 2's three model conditions are:
  (1) `∼`-invariance — free, `mk` takes a `Finset`; (2) *soundness of `⇒` for the algebra* — this
  is **already proved**: `LoopRel.sat` (`Loop/Refine.lean:417`), "every constructor of `LoopRel`
  preserves satisfiability"; (3) some `ζ₀` with `f(ζ₀) = ε` — `a <- ()`.  The homomorphism into
  simple rows (Definition 6) is the inclusion composed with `dom : (L ⇀ T) → 𝒫(L)`.

  > **CORRECTION (2026-09-07, R2 review K-1; the paper was obtained during the review).**  Two
  > sentences of this bullet are wrong.  (a) *"soundness of `⇒` … is **already proved**:
  > `LoopRel.sat`"* — `LoopRel.sat` is SATISFIABILITY preservation; Definition 2's second model
  > condition is MODEL preservation, "If `P ⇒ ψ`, then for each ground substitution `θ` on
  > `fv(P,ψ)`, `f ⊨ θP` implies `f ⊨ θψ`" (paper, verbatim).  `θ` ranges over the conclusion's
  > free variables too, so a MINT — whose fresh variable lies in `fv(ψ) \ fv(P)` — can never be an
  > entailment rule in Rose's sense, **in any row theory**.  (b) *"The homomorphism into simple
  > rows (Definition 6) is the inclusion composed with `dom`"* — Definition 6 is a map
  > `h : R₁ → R₂` on **syntactic rows** with two clauses, `ζ₁ ∼ ζ₂ ⟹ h(ζ₁) ∼′ h(ζ₂)` and
  > `P ⇒ ψ ⟹ h(P) ⇒′ h(ψ)`; maps of ALGEBRAS are the paper's separate notion, named one sentence
  > later ("Row algebras are related by partial monoid homomorphisms"), and `dom` runs *out of*
  > Rose's algebra into Ermine's, not into simple rows.  Both are repaired in R2's fix round:
  > `RoseTheory.ermine_isRowTheory` is built on the MINT-FREE fragment, and
  > `RoseTheory.ermine_to_simple_hom` is Definition 6 proper, with the algebra maps kept apart as
  > `dom_hom` / `lift_algHom` / `SimpleRowTransport`.
* **What it buys.**  Rose's Theorem 11 (Principality) and Theorem 15 (Coherence) become *citable*
  for Ermine's surface language rather than analogies, because Rose is parametric over the row
  theory and Ermine would be exhibited as one.  That is the licence rank 4 needs before importing
  Definition 13's closure as a *criterion* rather than as a hunch.
* **Where to look first.**  Toohey, Chen, Jamalzadeh and Xie, *Extensible Data Types with Ad-Hoc
  Polymorphism* (POPL 2026) mechanises a row calculus **in Lean 4** — the closest technical
  neighbour to this tree's own toolchain, and worth reading for library and idiom before writing
  the module (§5.3).
* **Risk.**  None: no code changes, one new Lean module of order 150 lines, and the only hard lemma
  already exists.  The honest caveat to write into the module docstring is that `LoopRel` includes
  `weaken` (deletion), so `⇒ermine` as defined is **not monotone in the Definition-1 sense** and
  the theory must be built from `LoopRel` minus `weaken` — the non-deleting fragment — with the
  deletions handled where they belong, in `NoLoss`.
* **Verdict: ADOPT.**  Cheapest framing result available, and a prerequisite for rank 4.

> **DONE 2026-09-07 (stage R2, `tracker/loopmodel/R2-ROSE-THEORY.md`, uncommitted).**  PARTIAL:
> every deliverable is in `tracker/lean/Rowpartition/RoseTheory.lean` (1,061 lines, in the root
> import list; `lake build` 869 jobs green, `Audit.lean` 4,427/0, `looptrace` untouched), and
> **one condition of this item fails as stated**.
>
> *What is proved.*  `sat_iff_pfold` — one Ermine partition constraint IS one n-ary combination
> predicate of `⟨𝒫fin(L), ⊎, ∅⟩`, the fold being DEFINED exactly at pairwise disjointness and
> EQUAL to the whole exactly at completeness.  `ermine_isRowTheory` — `⟨Constraint, =,
> derivability⟩` is a row theory (Definition 1: monotone, transitive, `∼`-invariant) and `Sat`
> is a model of it (Definition 2), with `ζ₀ = (||)`.  `dom_hom` and `lift_algHom` — the paper's
> PARTIAL MONOID homomorphisms between `⟨𝒫fin(L), ⊎, ∅⟩` and `⟨L ⇀ T, ⊔, ∅⟩`, preserving `⊎`
> (definedness included) and `ε`; `dom` is `lift tau`'s retraction and the two are mutually
> inverse at `T = Unit`, which is this section's "Ermine's is that algebra composed with `dom`"
> (§1.1 row 2) as a theorem.  `ermine_to_simple_hom` — **Definition 6 itself** (fix round; the
> first round mis-named the transport bundle after it), from `ermineTheory` to `simpleTheory tau`,
> the simple rows under SEMANTIC consequence along the `tau`-slice.  Non-vacuity is kernel-checked
> (`Witness`, `LiveRules`), and `taut_entailed` proves §4.5's `Goal_taut_is_trivial` — as a fact
> about `SEntails`, not about `⇒`: `eEnt_empty_false` shows the exhibited `⇒` does not derive it.
>
> *The condition that fails.*  This section says condition (2), soundness of `⇒` for the
> algebra, "is **already proved**: `LoopRel.sat`".  **It is not the same statement.**
> `LoopRel.sat` is SATISFIABILITY preservation (`SSat G → SSat G'`); Definition 2 asks for MODEL
> preservation.  Dropping `weaken` is necessary but NOT sufficient: the four MINTING
> constructors (`split`, `res`, `splitFree`, `kres`) add a constraint over a variable the
> premises do not constrain, which is exactly what `Loop/Strict.lean`'s `Conserv` records
> ("A MINT fails this").  `nd_derives_not_entails` and `split_not_conserv` exhibit it on
> `G₀ = { a <- (x, y, (|ℓ|)) }`.  The row theory is therefore built on the **mint-free**
> non-deleting fragment `MFStep`, where soundness is `NonGenStep.models_iff` plus `Refine.lean`'s
> four `*_sat` lemmas and is strictly stronger than Definition 2 asks; the minting fragment keeps
> only `ndRun_ssat`.  So `splitConcrete` and `resolution` — two of the eleven rules of §1.3 —
> are **conservative extensions, not entailments**, which is the same fact as §1.1's last bullet
> (`Has a b = exists c. a <- (b, c)`) seen from the solver side: Rose's predicate language has no
> existential, and Ermine's solver mints them.
>
> *What it buys, corrected.*  This section's "Rose's Theorem 11 and Theorem 15 become *citable*
> for Ermine's surface language" is **too strong as written**.  What becomes citable is the
> STATEMENT of principality (the memo's own §1.5 wording — the correspondence "is the
> prerequisite for even stating it") and the legitimacy of Definition 13/14 as Ermine notions,
> which is the licence rank 4 needs.  Theorem 11 itself does not transfer: Ermine's *type system*
> has not been exhibited as an instance of Rose's calculus, Rose buys principality by never
> solving while Ermine solves and commits (§1.5, `A1-REVIEW.md` §R-6), and the compiler runs
> `LoopRel` with `weaken` and the mints rather than `⇒`.  Theorem 15 has a **named unmet
> hypothesis**: Definition 14's coherence, which `PivotTest.pivotData`'s four-solution residual
> violates and which Ermine has no criterion for at all (rank 4).  R3 was not started.

> **CORRECTION (2026-09-07, R2 review K-12).**  Two further claims in this item are wrong, and the
> paper was obtained during the review, so both are now checkable.
>
> 1. The *Risk* bullet's "the only hard lemma already exists" and "one new Lean module of order
>    150 lines".  `LoopRel.sat` is *satisfiability* preservation; Definition 2's second model
>    condition is *model* preservation — "If `P ⇒ ψ`, then for each ground substitution `θ` on
>    `fv(P,ψ)`, `f ⊨ θP` implies `f ⊨ θψ`" (paper, verbatim).  For a MINT no such lemma can exist:
>    the fresh variable lies in `fv(ψ) \ fv(P)`, which `θ` ranges over, so **no minting rule is an
>    entailment rule in Rose's sense, in any row theory**.  The lemma that does the work is
>    `NonGenStep.models_iff`, on the mint-free fragment, and the module is 1,554 lines.  What the
>    minting fragment *does* satisfy is not only `LoopRel.sat` but the library's own
>    vocabulary-restricted form — `Cut.CseStep.entails_iff`'s shape, `SEntails G' c ↔ SEntails G c`
>    for `c` phrased inside `allVars G` — which R2's fix round proves for all four mints
>    (`RoseTheory.nd_derives_sound_on_vocab`) from `K2SplitStep.extend`, `K2ResStep.extend`,
>    `mint_extend`, `split_mint_conservativeExt` and `sat_congr_of_agree`.
> 2. "The homomorphism into simple rows (Definition 6) is the inclusion composed with
>    `dom : (L ⇀ T) → 𝒫(L)`."  Definition 6 is a map `h : R₁ → R₂` on **syntactic rows** with two
>    clauses, `ζ₁ ∼ ζ₂ ⟹ h(ζ₁) ∼′ h(ζ₂)` and `P ⇒ ψ ⟹ h(P) ⇒′ h(ψ)`; maps of *algebras* are the
>    paper's separate notion ("Row algebras are related by partial monoid homomorphisms"), and
>    `dom` runs from Rose's algebra into Ermine's, not into simple rows.  R2 proves the partial
>    monoid half (`dom_hom`, `lift_algHom`) and model-level transport (`SimpleRowTransport`); the
>    fix round adds **Definition 6 itself** (`Def6Hom`, `ermine_to_simple_hom`) into a target row
>    theory whose `⇒′` is semantic consequence in the simple-row algebra.  A Definition-6 map into
>    Rose's own `⇒simp` is probably blocked: `⇒simp` derives none of Ermine's rules (§1.3), and
>    Ermine has no *ground* predicates for `h` to be "extended to … in the obvious fashion"
>    (`Constraint` is always over variables).  The paper's own bridge — a partial monoid
>    homomorphism `j` together with `∀ζ ∈ R. ∃ζ′ ∈ R′. j(f(ζ)) = g(ζ′)` yields a row theory
>    homomorphism — is the alternative route, and its side condition is exactly R2's `tau`-slice
>    (`RoseTheory.bridge_side_condition`); the bridge is prose and unproved in the paper.

### Rank 3 — canonical residual simplification, the achievable form  ·  cost **3 stages**  ·  risk MEDIUM

This is the brief's item **(a)**.  Verdict: **ADOPT THE ACHIEVABLE FORM; REJECT THE STATED FORM.**
Full specification in §4.

* **In Rose's terms.**  Rose supplies *no* simplification (recollection 3 is wrong about this).
  What it supplies is the **correctness criterion**: Figure 9's generality ordering `⊒` on
  constrained type schemes, which is exactly the pair of entailments `A1-REVIEW.md` §R-6 had to
  compute by hand for `RevenueShare.shareOfGroup` (`OLD |= NEW`, `NEW |/= OLD`).  A canonicaliser
  must be an *identity* for `⊒` in both directions; nothing weaker keeps both the definition
  well-typed and the call sites checking.
* **What changes.**  `Subst.mkSimplified` grows three passes after rank 1's fix:
  (i) *(done by rank 1)* delete tautologies and permuted duplicates; (ii) delete a constraint the
  rest entails, against a decision oracle (rank 5's Boolean core) — this is the pass rank 1 does
  **not** give, and it is what `shareOfGroupFull`'s four redundant members and
  `overwriteWithFull`'s `r2 <- (e, a)` need; (iii) impose an alpha-canonical numbering on the
  surviving existentials, which is what makes the published form independent of the id base.  In Lean, a new `Rowpartition/Residual.lean` carrying the
  `Residual` / `Holds` / `REntails` / `REquiv` / `IsAlphaCanonicaliser` definitions of §4.
* **What it fixes.**  (1) `A1-REVIEW.md` §R-1/§R-6 order-dependent residual *form* — pass (iii)
  makes the published constraint set independent of which ids the `Supply` handed out, which is
  the residue of the 30 movers that rank 1 does not already collapse.  (2) `Signatures.e`'s noise:
  the four redundant members of `shareOfGroupFull`, `overwriteWithFull`'s `r2 <- (e, a)`, and
  `valueAsOfFormA`'s fifteen constraints against `valueAsOfFormB`'s nine — every one of those is a
  hand-written certificate of something pass (ii) would have found and rank 1 cannot.  (3)
  Indirectly the call-site cost of rank 5: a smaller residual is a smaller instantiated system.
* **Risk.**  MEDIUM, and specific.  (a) Every published `.ei` moves, so rank 6 must land first or
  together.  (b) Pass (ii) is **coNP-hard in general** (`TICKET-row-constraint-decision.md` §1.3,
  Böhler et al. CSL 2002 Thm 6 / Claim 13(2) for the constant-free 0-valid non-Schaefer case,
  which is where 345 of 345 stdlib residuals live) — so it must run under a budget with the same
  no-verdict discipline S2 layer (iii) already has, and a budget lapse must mean *keep the
  constraint*, never *drop it*.  (c) Pass (iii) is a canonical-labelling problem; at corpus sizes
  (17 existentials at the worst signature, `A1-REVIEW.md` §4c) a sort on a structural key suffices,
  but the key must be proved invariant, not assumed.
* **Verdict: ADOPT, in the form §4 specifies, and only after ranks 1, 2 and 6.**

### Rank 4 — Rose's Definition 13 as the licence for `reduce`'s splice  ·  cost **2 stages**  ·  risk MEDIUM

The single best *new* idea in the papers, and it lands on a known open problem.

* **In Rose's terms.**  Definition 13: `T⁺_Ψ` is the smallest `U ⊇ T` such that if
  `ζ₁ ⊙ ζ₂ ∼ ζ₃ ∈ Ψ` and `fv(ζ₁,ζ₂) ⊆ U` then `fv(ζ₃) ⊆ U` — *the whole is determined by the
  parts*.  Definition 14: a scheme `∀T.Ψ ⇒ τ` is **coherent** iff `T ⊆ fv(τ)⁺_Ψ`, and Theorem 15
  needs exactly that.  Rose's own incoherence example is `prjL ∘ prjR : ∀z₁z₂z₃.(z₃ ≼L z₂,
  z₂ ≼R z₁) ⇒ Πz₁ → Πz₃`, where `z₂` "appears in the qualifiers, but nowhere in the type of the
  term, so its instantiation can be chosen arbitrarily".
* **The Ermine analogue is already in the corpus, unnamed.**  `PivotTest.pivotData`'s residual
  `(|Issue, Key, Value|) <- ((|Key|), i, v3)` with `i` and `v3` existential is *genuinely
  underdetermined — four solutions* (`TICKET-row-constraint-decision.md` §1.3), and the ticket
  records that it is "left unsolved in the shipped `.ei`" and that "any replacement must reproduce
  it, not solve it".  That is Rose's incoherence, diagnosed by Rose's criterion, in Ermine's tree.
* **What changes.**  Two sites.  (i) `Subst.reduce`'s second case (`Subst.scala:1081`) splices
  **any** `v.ty.ambiguous || es.contains(v)`.  `Rowpartition.Splice.splice_entails_iff` proves that
  splice conservative under three side conditions, and
  `Splice.DroppedPartition.dropped_can_lose` exhibits a system where it loses a consequence; the
  guard was implemented, measured and **removed** on 2026-09-02 because "the first condition fails
  on 90 % of splices".  Definition 13 gives a *different* and cheaper guard: splice `v` when `v` is
  **determined** by the rest of the residual, and report ambiguity when it is not.  (ii) **Ermine has
  no ambiguity criterion for row residuals at all.**  `mkSimplified` computes
  `ambiguitiesIn(exts, complex)` where `complex = reduce(classes)` (`Subst.scala:1671-1672`) — the
  **class** constraints only; the row parts (`dumb`) bypass it entirely.  And `ambiguitiesIn`
  itself computes ambiguity as "the existentials this predicate mentions", `typeVars(p).exists(_ == v)`
  (`:371-372`), with **no closure**.  (`Subst.split` at `:386`, `Subst.ambiguities` at `:374` and
  `Subst.defaultSubst` at `:377` have no callers at all — the comment at `:662` says "we'll need
  thih-style split and defaulting as well, when we actually add classes".)  Definition 13 is the
  closure that is missing, and it has to be applied to the row parts, which is where nothing is
  applied today.  In Lean: a `Determined : System → Finset Var → Finset Var` closure with
  the theorem that a determined variable's value is unique given the rest (the `<-`-shaped
  strengthening: cancellation also determines a *part* from the whole and the other parts when the
  concrete parts are known, so Ermine's closure is strictly larger than Rose's).
* **What it fixes.**  The `Splice` weakening (an open scope limit of S1); gives Ermine its first
  principled ambiguity criterion for *row* residuals; and supplies the deletion licence §4's
  `Goal_dead_existential_deletable` needs.
* **Risk.**  MEDIUM–HIGH.  A new ambiguity *diagnostic* can reject programs that check today, so it
  must arrive as a warning behind a flag, defaulted off, measured on both corpora, and only then
  considered.  The splice guard is the reverse risk: tightening it "degrades published signatures
  from resolved concrete rows to constrained polymorphic ones" — that is exactly what was measured
  in 2026-09-02 and it is why the previous guard was withdrawn.  Definition 13's guard is a
  different predicate and must be measured on its own before anyone believes it does better.
* **Verdict: ADOPT AS AN INVESTIGATION** (one stage to build the closure and measure how many
  splices it licenses against the 90 % figure; a second only if the number is good).

**R3 (2026-09-07) — the investigation was run; the splice half is REFUTED and the ambiguity half
is a criterion with measured numbers.**  `tracker/loopmodel/R3-DETERMINED.md`,
`tracker/lean/Rowpartition/Determined.lean` (1,245 lines, 163 source declarations, 136 theorems in
the environment, standard axioms).  Additive
note; nothing above is retracted except where it is named here.

* **The closure exists and is a closure.**  `Determined G U` and `RoseDetermined G U` are least
  fixed points, proved extensive / monotone / closed / least / idempotent, and
  `determined_unique` is the theorem that makes "determined" mean something: two models of `G`
  agreeing on `U` agree on `Determined G U`.  Ermine's cancellation clause is proved strictly
  larger than Rose's (`RuleFires.rose_lt_det`), and the measured reason it has to be is `Has`:
  `type Has a b = exists c. a <- (b, c)` is Rose-ambiguous and not Ermine-ambiguous
  (`Derived.has_needs_cancellation`), because Rose keeps `≼` primitive where Ermine mints the
  complement.
* **"Definition 13 gives a different and cheaper guard [for the splice]" — WITHDRAW that
  sentence.**  Determinedness is independent of conservativity in BOTH directions, on
  satisfiable systems with no concrete labels: `SpliceGuard13.determined_splice_not_conservative`
  (the `Splice.DroppedPartition` system, where `v` is determined by **Rose's clause alone** and
  the splice still loses a consequence stated entirely in the universal vocabulary) and
  `SpliceGuard13.undetermined_splice_is_conservative`.  The condition that decides the splice is
  `splice_entails_iff`'s `hlhs`, which is SYNTACTIC — a property of what `reduce` rewrites and
  discards — and no closure on models can see it.
* **"supplies the deletion licence §4's `Goal_dead_existential_deletable` needs" — WITHDRAW that
  too.**  Definition 13 licenses the VALUE and not the DEFINEDNESS: the row algebra is a PARTIAL
  monoid, and a partition also asserts that its parts COMBINE.
  `DeadTwoParts.two_parts_not_deletable` refutes deletion for a dead existential whose value
  Rose's clause DOES determine; `DeadUndetermined.undetermined_not_deletable` refutes it under
  the memo's own hypothesis ("neither determined by nor determining the universals").  What is
  proved is `dead_delete_of_pairwise` — deletion is sound exactly when the remainder already
  forces the parts to be pairwise disjoint — and its unconditional corollary
  `dead_delete_of_le_one_part` for a constraint with at most one part.
* **`PivotTest.pivotData` — the memo's example is right about the constraint it quotes and wrong
  about the residual.**  On the bare `(|Issue,Key,Value|) <- ((|Key|), i, v3)` the four solutions
  are real and both closures leave `i`, `v3` undetermined
  (`Pivot.bare_genuinely_ambiguous`).  On the residual the compiler PUBLISHES, which also carries
  `s <- ((|Sector,Price,MarketCap|), i)`, Rose's closure still says undetermined and **Ermine's
  says determined** (`Pivot.criterion_split`), and the models side with Ermine's
  (`Pivot.full_unique`: the value of `s` pins both).  So Ermine's tree does not, after all,
  contain "Rose's incoherence diagnosed by Rose's criterion" — it contains a residual that is
  incoherent by Rose's criterion and coherent by the criterion Ermine's own algebra supports.
* **The MEASURED numbers, in one line each.**  Splices: Rose's closure licenses 13.6 % per file
  (3.4 % in batch), Ermine's 18.6 % (10.1 %), the withdrawn guard 14.7 % (64.0 %) -- and **Rose's
  closure and the withdrawn guard never once license the same splice**, 0 of 42,902.  Published
  top-level signatures: of 104, **Rose's criterion flags 88 and Ermine's flags 19, none of them in
  `core/examples`**.  A hand-check of ten of the nineteen finds **seven false positives**, all from
  one missing clause -- the solver's own `resolution` -- which `Determined.lean` §13 now has,
  with the uniqueness theorem re-proved (`resAdd`, `Determined3`, `determined3_unique`) and the
  smallest of the seven as a kernel-checked instance (`NotEq.res_cures`, the stdlib `(!=)`).
  **`resolution` is not enough, and that number is in hand too** (R3 review M-1, re-derived by the
  implementer): running all three clauses over the published `.ei` leaves **11 of the 19** flagged,
  and two of the eleven — `Predicate.(>=)` and `(<=)` — are false positives pinned by a
  DISJOINTNESS obligation (`f ⊥ d` forces `e = a1 ∩ b`), which is `CriterionIncomplete`'s
  mechanism and which no clause of this family can reach.
* **Verdict on rank 4: the investigation is CLOSED, on both halves.**  (i) the splice guard should
  never be built — refuted in both directions, and Rose's closure and the withdrawn guard never
  once license the same splice.  (ii) no ambiguity warning should ship, and the stage 2 an earlier
  draft of the R3 report proposed is closed with a "no" rather than scheduled: its number fails
  the report's own acceptance criteria.  The one thing worth doing is a TICKET rather than a
  stage — TAUTOLOGY DELETION, `TICKET-stdlib-findings.md` C12: `exists t h. r <- (t, h)` with `r`
  universal is true of every row, it accounts for five of the nine genuine flags, deleting it
  shortens five published stdlib signatures, and `ei-diff.sh` is the measurement.  The numbers are
  in `R3-DETERMINED.md` §4 and §4.7, the recommendation in its §5, the review in `R3-REVIEW.md`.

### Rank 5 — entailment-based call-site checking  ·  cost **3 stages**  ·  risk MEDIUM

This is the brief's item **(b)**.  Verdict: **ADOPT AS A FAST PATH, NOT AS A REPLACEMENT.**

* **In Rose's terms.**  This is `(⇒E)`: at an instantiation, *discharge* the predicate against the
  context by entailment.  Rose's own framing — "In Rose, we will both instantiate type variables
  and discharge the corresponding predicates automatically" (§2.1).
* **What it targets.**  The measured cliff of `core/examples/Ai/README.md`: inline 1.04 s, via
  `withColumn` (one `RUnion2`) 0.50 s, via a helper bundling `RUnion3` **and** `RUnion2` **"does
  not finish"** — and `Common.e` is shaped around avoiding it.  At such a call site the callee's
  residual is instantiated and thrown into a fresh saturation that re-derives what the callee's own
  solve already derived.  Checking `Γ ⊨ P[θ]` instead is polynomially bounded work per label
  against an exponential search.
* **Four things must be true, and three of them are not yet.**
  1. *The oracle must exist.*  `labelDecide` decides **satisfiability** of a system of partitions.
     Entailment `G ⊨ c` is **unsatisfiability of `G ∧ ¬c`**, and `¬c` is not a partition
     constraint — it is a Boolean clause over the per-label bits.  So what is reusable is
     `decideAll`'s Boolean core (`propagate` at `Constraints.scala:2632` and `search` at `:2696`, inside `decideLabel`), extended
     with a negated goal clause; `labelDecide` itself is not the oracle.  **Small but real.**
  2. *The side condition must be discharged.*  `Basic.lean:525`'s `entails_iff_forall_label` is an
     `iff` **only** under `∃rho, Models rho G`, and `Basic.Counterexample.entails_not_pointwise`
     proves the hypothesis cannot be dropped (an unsatisfiable `G` entails everything without being
     pointwise valid).  That certificate is exactly what S2 layer (iii) produces:
     `Loop.solve_noFalseAccept` concludes `SSat` of an accepted solve's live input.  **Already in
     the tree, already on by default.**  This is the sharpest parallel this memo found between the
     two halves of the work: *the check adopted for soundness is the precondition the optimisation
     needs.*
  3. *The check must not lose the substitution.*  Today's re-saturation does not only check, it
     **solves**: `makeConcrete`, `makeEmpty` and `instantiate` call `instantiateType` and feed row
     solutions back into the main unifier (`ROW-CONSTRAINT-STATE.md` §8.6, open).  A pure
     entailment check would type-check the call and leave the caller's rows undetermined.  So the
     fast path is admissible only when the instantiated residual determines no variable the caller
     still needs — which is Definition 13's closure again (rank 4).  **This is why (b) cannot be a
     replacement.**
  4. *It must be measured on the cliff.*  The acceptance criterion is the `Ai/README.md` table
     re-run: the bundled `RUnion3`+`RUnion2` helper must finish.
* **Risk.**  MEDIUM.  Behind a flag, default off; a fast-path *miss* must fall through to the
  existing solve, never reject.  Ur/Web's disjointness prover is the precedent for exactly this
  shape — its goal check has an explicit *"not provable yet"* outcome and a retry loop, and
  Chlipala is candid that it comes with no theorems (§5.2).  Ermine can do better than Ur here,
  because the oracle it would use is complete and has one.

* **Verdict: ADOPT, three stages** — (1) the Boolean core's goal clause plus its Lean soundness;
  (2) the determinacy precondition from rank 4; (3) the fast path, flagged and measured.

### Rank 6 — a solver-configuration key on the `.ei` cache  ·  cost **1 stage**  ·  risk LOW

Not a Rose idea; listed because ranks 1 and 3 both move published bytes and this is their
prerequisite.  Nothing keys a published interface by `GenRules.toString` (its only consumer is
`DisjProbe`), so a tree built partly at one configuration silently mixes interfaces —
**measured, not assumed** (`A1-ADOPTION.md` §2, A1.7; A1 review R-4).  Today the mitigation is a
one-line `find . -name '*.ei' -delete`.  A canonicaliser makes that unacceptable, because the
whole point is that the published form is now a *function of the configuration*.
**Verdict: ADOPT, before rank 3.**

### Rank 7 — a primitive containment constraint  ·  cost **4–6 stages**  ·  risk HIGH

* **In Rose's terms.**  Keep `≼` primitive, as Rose does, instead of deriving it.  Rose's stated
  reason is not economy but semantics: `≼` "more closely parallels the term structure, and so …
  captures the translation of Rose into languages without row types" (§2.1).
* **What it would fix.**  Every `Has a b` in Ermine mints an existential complement
  (`type Has a b = exists c. a <- (b, c)`), and those existentials are precisely what the dequeue
  order names differently — `A1-REVIEW.md` §R-6's `RevenueShare.shareOfGroup` differs from its old
  self in *exactly one thing*: "wherever the old side names the UNIVERSAL `k` … the new side names
  a FRESH EXISTENTIAL `i`".  A primitive `≼` has no complement to name.
  `Signatures.e`'s `topRowsByDeduped : (Has b h, RelationalComb rel) => …` is the same observation
  written by hand: "What is left, `exists c. b <- (h, c)`, is exactly the `Has b h` alias, which is
  how a person spells it."
* **The published design that does it properly.**  Rωμ (Hubers, Ingle, Marmaduke & Morris,
  arXiv:2410.11742, Agda at `IowaFP/Rome`) adds a **row complement** operator.  A complement is
  exactly what `Has a b = exists c. a <- (b, c)` is mumbling: `c` *is* `a ∖ b`, and the existential
  exists only because the language cannot name it.  If Ermine's constraint language ever grows,
  complement — not `≼` — is probably the primitive to grow, because it removes the existential
  rather than adding a second predicate to every rule.  **Preprint only; no venue confirmed.**
* **Why not now.**  It is an *addition* to the constraint language, not a replacement:
  `TICKET-row-constraint-decision.md`'s Part 0 measured that containment plus disjointness covers
  only **56 of 345** residuals and **39 of 199** signatures, so `<-` stays and every rule, every
  `LoopRel` constructor, the queue's reverse lookups and the per-label decision all grow a second
  case.  The rule count of a saturation is what its cost is quadratic in.
* **Verdict: DEFER.**  Record as the principled long-term shape of the constraint language; do not
  schedule.  Revisit only if ranks 1–5 leave the residual-noise problem open.

### Rank 8 — Rω's row-indexed type functions for `Relation/Pivot.e`  ·  **REJECT**

`pivot : (RelationalComb rel, r <- (k, v, i), s <- (i, p)) => Fulcrum k v p -> rel r -> rel s`
(`modules/Relation/Pivot.e:110`).  The output row `s` is `i ⊎ p`, and `p` — the pivoted-in
columns — is an abstract row *parameter* of the `Fulcrum`, whose actual field list is a runtime
`List String`.  Rω is exactly the machinery for computing one row from another at the type level
(`ana`, `syn`, `fold`, and rows of labels in the kind system).  But Rω "is based on System Fω
extended with qualified types, and so supports first-class polymorphism and general type
operators", is **explicitly typed**, and its authors flag that "adapting Rω to a type system
without type-level functions would certainly make type reconstruction more likely" — i.e. type
reconstruction for Rω itself is not attempted.  Adopting it means adopting Fω and giving up full
inference, against a production shape that is `params -> report` with everything inferred.
**Verdict: REJECT.**  Worth writing down only so that the question is closed with a reason.

### Rank 9 — binarising the surface `<-`  ·  **ALREADY CLOSED**

Rose's `⊙` is binary; Ermine's `<-` is n-ary and `splitConcrete` exists only to re-binarise it at
solve time (§1.3).  Moving the binarisation to the surface was considered and **closed with
numbers** in `TICKET-row-constraint-decision.md`: "Rose's binary combination is expressively
complete by re-association but exactly as NP-hard, because the monotone 1-in-3-SAT witness
`L <- (x,u), u <- (y,z)` lives entirely in the arity-2 fragment, and it costs 171 new existential
binders across 88 signatures."  Nothing in the papers changes that.  **Verdict: STAYS CLOSED.**

---

## 4. A first specification of canonical residual simplification

The scratch file is `/home/dmitry/.claude/jobs/880c725d/tmp/R1/CanonSpec.lean`.  It is **not** part
of the library.  It was elaborated against the built library with

```
export PATH=$HOME/.elan/bin:$PATH
cd tracker/lean && LEAN_NUM_THREADS=2 lake env lean <that file>
```

and the result is **exit 0, no errors, no warnings, no `sorry`, no `axiom`** — every definition
below type-checks against `Rowpartition.Basic`, `Rowpartition.Divergence` and
`Rowpartition.Loop.Refine` as they stand.  No `lake build` was run.

### 4.1 The object being canonicalised is not a `System`

The brief asks for `Canonical : System → System`.  That signature is not quite right, and the
scratch file says why: `Subst.solve` publishes `Exists(l, [], reduce(…))` and `generalize` binds a
set of **existential** row variables (`Subst.scala:1443-1446`: `xs = typeVars(cs) -- nts -- gs`,
refreshed as `Ambiguous(Bound)`).  The whole point of a canonicaliser is to delete constraints that
mention only existentials and to renumber the rest, and a bare `System` cannot express which
variables those are.  So:

```lean
structure Residual where
  ex  : Finset Var        -- what `generalize` binds existentially
  sys : System            -- the published partitions
deriving DecidableEq

def Holds (rho : Assign) (R : Residual) : Prop :=
  ∃ rho' : Assign, (∀ v, v ∉ R.ex → rho' v = rho v) ∧ SModels rho' R.sys

def REntails (R S : Residual) : Prop := ∀ rho, Holds rho R → Holds rho S
def REquiv   (R S : Residual) : Prop := REntails R S ∧ REntails S R
```

`Holds` is the reading a **call site** has of a published qualification: the universals are fixed
by the caller, the existentials are the callee's to choose.  `REquiv` is provably an equivalence
(three one-line proofs in the file), and `holds_of_no_ex` is the bridge back to `SModels`, so every
S1 theorem still applies to the `ex = ∅` case.

### 4.2 The properties

```lean
structure IsCanonicaliser (F : Residual → Residual) : Prop where
  faithful    : ∀ R, REquiv R (F R)
  irredundant : ∀ R, ∀ c ∈ (F R).sys,
                  ¬ REntails ⟨(F R).ex, (F R).sys.erase c⟩ (F R)
  idem        : ∀ R, F (F R) = F R
  universals  : ∀ R, allVars (F R).sys \ (F R).ex ⊆ allVars R.sys \ R.ex

def OrderIndependent (F : Residual → Residual) : Prop :=
  ∀ R S, REquiv R S → F R = F S
```

* **`faithful`** is the brief's "`SEntails`-equivalence both ways", corrected for existentials.  It
  is Rose's Figure 9 `⊒` in both directions.  `REntails R (F R)` keeps the **definition**
  well-typed (the body still has the published type); `REntails (F R) R` keeps every **call site**
  that used to check checking.  This is precisely the pair `A1-REVIEW.md` §R-6 computed by hand for
  `RevenueShare.shareOfGroup` and found holding in only one direction, and precisely what
  `Signatures.e` certifies for `valueAsOfFormA` / `valueAsOfFormB` by defining each as the other.
* **`irredundant`** is the brief's minimality, in the achievable form.  *Minimum-cardinality* is
  not the right ask: finding a smallest equivalent set is a minimisation over a coNP-complete
  equivalence, and `Signatures.e`'s own hand-written "deduped" sets are irredundant, not proven
  minimum.
* **`universals`** is a property the brief did not name and that turns out to be load-bearing: a
  canonicaliser may rename and delete **existentials** but must not touch a universal, because
  those are the caller's rows.  Without it, "renumber canonically" would be licensed to rename the
  `k` in `Row k` — which is exactly the difference `A1-REVIEW.md` §R-6 measured.

### 4.3 Order-independence: the strong form is not achievable, and here is the argument

`OrderIndependent F` together with `DecidableEq Residual` **is a decision procedure for `REquiv`**:
`REquiv R S ↔ F R = F S`, left to right by order-independence and right to left by `faithful`.
Equivalence of these systems is **coNP-complete** (`TICKET-row-constraint-decision.md` §1.3, citing
Böhler–Hemaspaandra–Reith–Vollmer CSL 2002 Theorem 6 and Claim 13(2) for the constant-free,
0-valid, non-Schaefer case — which is where **345 of 345** stdlib partition constraints live, none
of them carrying a concrete label).  So no polynomial `F` is strongly order-independent unless
P = NP.  The scratch file states this as `Goal_strong_orderIndep_decides_equiv`.

There is a second, independent obstruction, and it is already in the library.
**`Rowpartition/Canonical.lean` (1,253 lines) is a terminating, model-preserving, non-generative
rewriting simplifier that was built and then found not to be confluent:**

* `Canonical.CriticalPair.not_locally_confluent` and `not_joinable` — a critical pair between
  `occurs` and `absorb` whose two results are **distinct normal forms**;
* `Canonical.Orientation.results_differ` — a second, independent ambiguity on a **satisfiable**
  system (`unify` may orient `a = b` either way);
* `Canonical.CriticalPair.normal_form_can_be_unsat` — normal forms are not decided.

So a canonicaliser **cannot** be specified as "run these rewrite rules to a fixpoint" *and* be
order-independent.  It has to be specified extensionally, as above.

### 4.4 The weaker property that is achievable, and is enough

```lean
def rename (f : Var → Var) (R : Residual) : Residual :=
  ⟨R.ex.image f, R.sys.image (fun c => mk (f c.lhs) ((vset c).image f) c.conc)⟩

def AlphaCanonical (F : Residual → Residual) : Prop :=
  ∀ (R : Residual) (f : Var → Var), Function.Injective f →
    (∀ v ∈ allVars R.sys \ R.ex, f v = v) →
    F (rename f R) = rename f (F R)

structure IsAlphaCanonicaliser (F : Residual → Residual) : Prop extends IsCanonicaliser F where
  alpha : AlphaCanonical F
```

**Alpha-canonicity says the output does not depend on which ids the `Supply` handed out** — only
on the shape.  It is strictly weaker than `OrderIndependent` (it quantifies over *renamings*, not
over all equivalent systems), it is achievable by a canonical-labelling pass, and it is **enough
for the measured problem**: `A1-REVIEW.md` §4b classifies the 30 bindings the dequeue flip moved as
**27 ISO** (a renaming), **1 ISO_PLUS** (a renaming plus one entailed constraint — pass (ii)
catches it), **2 kind-prefix**, and **1 NOISO**.  The one NOISO is `shareOfGroup`, and it is not an
alpha problem at all: it is a *universal* that became an *existential*, which the `universals`
clause forbids independently.

`IsAlphaCanonicaliser` is what §3 rank 3 proposes adopting.  `OrderIndependent` should be recorded
as a **non-requirement**, with the P = NP argument beside it.

### 4.5 The three passes, as statements

The scratch file states each as the property the canonicaliser must have.

```lean
def Goal_taut_is_trivial (r : Var) : Prop := SEntails (∅ : System) (mk r {r} (∅ : Row))

theorem perm_already_equal (a : Var) (x y z : Var) (K : Row) :
    mk a {x, y, z} K = mk a {z, x, y} K := …            -- PROVED in the scratch file

def DeadExistential (R : Residual) (c : Constraint) : Prop :=
  c ∈ R.sys ∧ c.lhs ∈ R.ex ∧ (∀ d ∈ R.sys.erase c, c.lhs ≠ d.lhs ∧ c.lhs ∉ vset d)
```

* **Tautology deletion.**  `a <- (a)` is entailed by the *empty* system, so it is illegal under
  `irredundant` and must go.  `Signatures.e`'s `taut` / `tautIsFree` is the compiler-checked
  certificate ("`taut`'s constraint is discharged at a call site with NO constraint whatsoever in
  scope, so every occurrence of it in a residual is pure noise"), and `TopReadings.topRowsBy`'s
  inferred `h <- (h)` (`TopReadings.e:31`) is the live instance.  `Rowpartition.Canonical`'s
  `step_vacuous` already deletes it in the model; the compiler's gap is the missing `None` case in
  `mkSimplified`'s `normalPart` (§3 rank 1, item 2).
* **Permuted duplicates.**  `perm_already_equal` is *proved*, in one line, from `Finset`
  extensionality.  **The model is already right; the Scala is behind it.**  §3 rank 1 gives the
  mechanism (`NormalPart`'s missing `hashCode`) and the one-line fix.  This is the item where the
  Lean library is the specification and the compiler is the defect.
* **Dead-existential deletion.**  `shareOfGroupDeduped`'s comment names four instances and the
  reason: "`c2 <- (f, e, d1)` (`c2` occurs nowhere else; `i <- (o, f, e, d1)` says it)".
  `mkSimplified`'s `isolated` already deletes existentials **not transitively related to
  universals**; these are related, so they survive, and deleting them needs the entailment oracle
  rather than a reachability test.

### 4.6 Can `labelDecide` be the entailment oracle?

**The decomposition it rests on can; the function itself cannot without one extension.**

* `Basic.lean:525` `entails_iff_forall_label` — `Entails G c ↔ ∀ l b, BModels b l G → BSat b l c`
  — is exactly the reduction a canonicaliser needs, and the per-label Boolean encoding
  (`Basic.lean:351-365`: `proj`, `bparts`, `BSat`, `BModels`) is the one `labelDecide` already
  works in.
* **But `labelDecide` decides satisfiability, not entailment.**  `G ⊨ c` is unsatisfiability of
  `G ∧ ¬c`, and `¬c` is not a partition constraint — it is a Boolean clause over the per-label
  bits.  What is reusable is `decideAll`'s core (`propagate` + `search`,
  `Constraints.scala:2632` and `:2696` inside `decideLabel` at `:2571`, mirrored in `Loop/Decide.lean`), extended with a negated goal
  clause.  That is a small change to a component that already has its soundness and completeness
  theorems (`labelDecide_refuted_unsat`, `labelDecide_sat_ssat`), and both would have to be
  restated for the extended core.
* **The side condition is the interesting part, and it is already paid for.**
  `entails_iff_forall_label` is an `iff` only under `∃rho, Models rho G`, and
  `Basic.Counterexample.entails_not_pointwise` proves the hypothesis cannot be dropped — an
  unsatisfiable `G` entails everything without being pointwise valid.  That certificate is exactly
  what **S2 layer (iii)** produces: `Loop.solve_noFalseAccept` concludes `SSat` of an accepted
  solve's live input, and it is **on by default since 2026-09-06**.  The scratch file records this
  as `Goal_oracle_precondition_is_S2`.  *The check adopted for soundness is the precondition the
  simplifier needs* — this is the sharpest internal parallel this stage found, and it means the
  oracle's obligation is discharged rather than assumed.
* One honest caveat: S2's guarantee lapses on a budget exhaustion (`LabelNoVerdict`).  A
  canonicaliser must treat "no verdict" as **keep the constraint**, never as "delete it".

### 4.7 What would be provable

In rough order of effort, and none of it attempted here:

1. `REquiv` is an equivalence, and `IsCanonicaliser F → REquiv R (F R)` composes with S1's
   `run_noLoss` so that the *published* signature, not merely the loop's output, is covered.  (The
   `Subst.reduce` scope limit of `S1-SOUNDNESS.md` sits exactly here and this is the natural place
   to close it.)
2. Tautology deletion, permuted-duplicate collapse and `mkSimplified`'s existing `isolated` pass
   each preserve `REquiv` — three small lemmas, the shapes of which `Canonical.Step.preserves`
   already has.
3. `Goal_dead_existential_deletable`: deleting a dead existential's constraint is `REquiv` iff the
   remainder entails it — reduces to `entails_iff_forall_label` plus the splicing lemma
   `Basic.exists_splice`.
4. `AlphaCanonical` for a concrete labelling function.  This is the real work: it needs a
   structural key on `Residual` proved invariant under renamings that fix the universals.
5. `Goal_strong_orderIndep_decides_equiv` — stated so that nobody re-proposes strong
   order-independence without meeting the P = NP argument.  Worth writing down as a *negative*
   result in the library, next to `Canonical.not_locally_confluent`.

---

## 5. Citations, and what I could not verify

Tags follow `TICKET-row-constraint-decision.md` §9: **[V]** the cited statement was read in the
primary source; **[S]** taken from an abstract or a reliable secondary source.

### 5.1 The two papers the brief names

* **[V]** J. Garrett Morris and James McKinna, *Abstracting extensible data types: or, rows by any
  other name*, **PACMPL 3(POPL), Article 12, pp. 12:1–12:28, January 2019**,
  [doi:10.1145/3290325](https://doi.org/10.1145/3290325).  Open access (CC-BY); read in full from
  the KU ScholarWorks deposit
  <https://kuscholarworks.ku.edu/handle/1808/27514> (bitstream `Morris_2019.pdf`; the ACM and
  Edinburgh copies are behind Cloudflare).
  **Definition 1** row theory `⟨R, ∼, ⇒⟩` (`⇒` required only `∼`-invariant, monotone, transitive);
  **Definition 2** row algebra = partial monoid, and the three conditions for `f : R → M` to be a
  *model* — the second of which is soundness of `⇒`; **Example 3** simple rows = `⟨L ⇀ T, ⊔, ∅⟩`
  with `⊔` defined iff the domains are disjoint, identified with the algebra of "Rémy [1989],
  Harper and Pierce [1991], Gaster and Jones [1996], and Chlipala [2010]"; **Example 4** scoped
  rows; **Example 5** unlabelled rows `⟨𝒫(T), ⊎, ∅⟩`; **Definition 6** row-theory homomorphism;
  **Figure 1** the (excerpted) simple-row entailment; **Figure 3** scoped-row entailment, including
  containment-from-combination; **Lemma 8** entailment produces well-typed evidence;
  **Definition 9** constrained type schemes; **Figure 9** the generality ordering `⊒`;
  **Theorem 11 (Principality)**; **Theorem 12 (Soundness)** of the translation into `F^{⊗⊕}`;
  **Definition 13** the determinacy closure `T⁺_Ψ`; **Definition 14** coherent scheme / term;
  **Theorem 15 (Coherence)**; **Definition 16 / Theorem 17** row-theory translations.
  **No decision procedure, no completeness theorem for entailment, no complexity bound, and no
  simplification step.**  **No mechanisation** — a full-text search of the CC-BY PDF finds zero
  occurrences of "Agda", "Coq", "mechanis/zed", "proof assistant" or "artifact", and POPL 2019
  awarded it no artifact badge.
* **[V]** Alex Hubers and J. Garrett Morris, *Generic Programming with Extensible Data Types; Or,
  Making Ad Hoc Extensible Data Types Less Ad Hoc*, **PACMPL 7(ICFP), Article 201, pp. 356–384,
  August 2023**, [doi:10.1145/3607843](https://doi.org/10.1145/3607843); preprint
  [arXiv:2307.08759](https://arxiv.org/abs/2307.08759), read in full.  **Note the title** — it is
  *not* "Rows by Any Other Name Redux".  §3: *"System Rω generalizes Rose in two dimensions.  Rose
  imposes Hindley-Milner constraints on typing; Rω is based on System Fω extended with qualified
  types … More significantly, the record and variant operations in Rose are all specific to
  concrete labels or sets of labels; Rω introduces label-generic combinators."*  The simple row
  theory is restated there verbatim: *"labels are restricted to appear at most once in a given row,
  row combination is commutative (and so there is a single containment operator), and `ρ₁ ⊙ ρ₂ ∼ ρ₃`
  is unsatisfiable if `ρ₁` and `ρ₂` contain any of the same fields."*  Four **unnumbered**
  theorems, all constructive via the Agda denotation: the kind system, the entailment relation, the
  type and predicate equivalence relations, and the type system are each *sound*.  Explicit scope
  limits: *"our mechanization of the entailment relation is limited to the minimal row theory"*;
  rule (e-sing) is dropped to get the general result; type reconstruction is future work.
* **[V]** the Rω mechanisation: Zenodo
  [10.5281/zenodo.8116889](https://doi.org/10.5281/zenodo.8116889) (concept DOI 10.5281/zenodo.7986778),
  mirrored at <https://github.com/IowaFP/ROmega-ICFP23-artifact>, ICFP'23 **Available, Functional,
  Reusable**.  Agda 2.6.2.2 / stdlib 1.7.1, entry point `ROmega.All`.  **Intrinsic and denotational
  only: no operational semantics, no progress/preservation, no normalisation.**  Functional
  extensionality is postulated; labels denote to the unit type.
* **[S]** the successor of the successor: Alex Hubers, Apoorv Ingle, Andrew Marmaduke and
  J. Garrett Morris, *Abstracting Extensible Recursive Functions*,
  [arXiv:2410.11742](https://arxiv.org/abs/2410.11742) (v1 2024, v2 2025) — **Rωμ**, adding
  iso-recursive types and, relevantly for §3 rank 7, a **row complement** operator.  Agda
  mechanisation at <https://github.com/IowaFP/Rome> (this, not the ICFP'23 artifact, is what
  "Rome" names); theorems include normalisation, decidability of type equality, canonicity,
  preservation and progress.  **Preprint only — no venue confirmed.**

### 5.2 The background the memo places them in

* **[V]** Didier Rémy, *Type checking records and variants in a natural extension of ML*, POPL '89,
  pp. 77–88, [doi:10.1145/75277.75284](https://doi.org/10.1145/75277.75284); and *Type Inference
  for Records in a Natural Extension of ML*, in Gunter & Mitchell (eds.), *Theoretical Aspects of
  Object-Oriented Programming*, MIT Press 1993
  (<http://cambium.inria.fr/~remy/ftp/taoop1.pdf>).  Rows are **total** functions `L → pre(T)+abs`
  with presence *flags*; the equational theory has exactly two schemes (left-commutativity,
  distributivity), all axioms **regular**.  **Theorem 1**: *"Unification in the record algebra is
  decidable and unitary (every solvable unification problem has a principal unifier)."*
  **Theorem 2** gives principal typings and a decidable inference algorithm from regularity plus
  unitary unification.  **No concatenation**: *"All common operations on records but concatenation
  are supported."*
* **⚠ [V] "Rémy's row unification is polynomial" is NOT supported by any primary source** — a
  correction to this memo's own framing of the background, and one worth carrying into
  `TICKET-row-constraint-decision.md`.  The primary sources claim only *decidable and unitary* and
  "efficient **in practice**".  The authoritative statement is Pottier & Rémy, *The Essence of ML
  Type Inference*, ch. 10 of ATTAPL (MIT Press 2005), §10.8, verbatim: *"What is, then, the time
  complexity of row unification?  **Only a partial answer is known.** … In theory, the complexity
  of row unification remains unexplored and forms an interesting open issue."*  Exercise 10.8.23
  goes further: *"The unification algorithm presented above, although very efficient in practice,
  **does not have linear or quasi-linear time complexity.**"*
* **[V]** Didier Rémy, *Typing Record Concatenation for Free*, POPL '92, pp. 166–176,
  [doi:10.1145/143165.143202](https://doi.org/10.1145/143165.143202).  Not a new row primitive: an
  **encoding**.  A record becomes a function `r† = λu.(u ‖ r)`, so concatenation becomes
  **composition**, `(M ‖ N)† ≡ N† ∘ M†`, and typing is inherited from a language with extension
  only.  Strictly weaker than Wand's system, and Rémy diagnoses why adding `‖` as a type operator
  fails: *"This disjunction in the relation ‖ breaks the principal type property of type inference.
  Worse, disjunctions on different fields combine and make the resulting type … explode in size."*
* **[V]** Mitchell Wand, *Type inference for record concatenation and multiple inheritance*, LICS
  1989, pp. 92–97; journal version **Information and Computation 93(1):1–15, 1991**,
  [doi:10.1016/0890-5401(91)90050-C](https://doi.org/10.1016/0890-5401(91)90050-C).  The
  no-principal-types / finite-complete-sets theorem quoted in §1.5, the `2^{kn}` bound, and the
  infinite-label version with **extension constraints** `ρ₁ ‖ ρ₂ = ρ₃` — of which Wand notes
  *"every set of extension constraints is satisfiable: just set all the ρᵢ to empty"*, which is
  Ermine's own 0-valid observation (`TICKET-row-constraint-decision.md` §1.3: every `R_k` is
  0-valid, and no stdlib partition constraint carries a concrete label).
* **[V]** Mitchell Wand, *Complete Type Inference for Simple Objects*, LICS 1987, pp. 37–44 — where
  the word **row** is coined for this purpose: *"If ρ : D → X, where D is a finite subset of L …
  then we call ρ a row of X's.  (This terminology is stolen from Algol 68.)"*  **[S]** the 1988
  corrigendum (LICS 1988, p. 132) — **not obtained**; see §5.3.
* **[V]** Robert Harper and Benjamin Pierce, *A Record Calculus Based on Symmetric Concatenation*,
  POPL '91, pp. 131–142, [doi:10.1145/99583.99603](https://doi.org/10.1145/99583.99603); read from
  the full version CMU-CS-90-157R (<https://www.cis.upenn.edu/~bcpierce/papers/merge.ps>).  The
  compatibility predicate `T ⊢ r # s` holds *"iff r and s are mergeable, that is, iff r lacks every
  field possessed by s and s lacks every field possessed by r"*, with constrained quantification
  `∀a#R. t`.  **Decidability of type CHECKING** is proved (algorithmic compatibility sound Thm
  2.3.4.1 / complete Thm 2.3.4.5; type synthesis sound 2.3.5.1 / complete 2.3.5.2); type
  **reconstruction** is left open and conjectured exponential, *"inferring not principal types but
  finite sets of principal types"*.  Their taxonomy is useful: Wand's row variables and `λ‖` are
  *"pure negative-information systems"* — which is what Ermine's `<-` is too.
* **[V]** Jens Palsberg and Tian Zhao, *Type inference for record concatenation and subtyping*,
  **Information and Computation 189(1):54–86, 2004**,
  [doi:10.1016/j.ic.2003.10.001](https://doi.org/10.1016/j.ic.2003.10.001)
  (<http://web.cs.ucla.edu/~palsberg/paper/ic04.pdf>).  Theorems as quoted in §2 row 7.
  **Do not cite** the LICS 2002 version, *"Efficient Type Inference for Record Concatenation and
  Subtyping"*, [doi:10.1109/LICS.2002.1029822](https://doi.org/10.1109/LICS.2002.1029822), which
  claimed polynomial time and is retracted in the journal acknowledgments.
* **[V]** Daan Leijen, *Extensible records with scoped labels*, TFP 2005, pp. 179–194
  (<https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/scopedlabels.pdf>).
  Duplicate labels are allowed and retained; the whole system is one equality relation whose
  `(eq-swap)` rule lets the first two fields swap *"if (and only if) their labels are different"*.
  **Theorem 1** unification sound, **Theorem 2** unification complete (most general unifier);
  principal types are inherited from Hindley–Milner, not re-proved; **no complexity claim**.
  What it gives up versus Rémy, in his words: *"a system based on flags can not give a type to our
  notion of proper free extension since it essentially views records as total functions from labels
  to values, where duplicate labels are certainly not allowed."*  **Directly relevant to this
  tree**: his termination side condition `tail(r) ∉ dom(θ₁)` *"prevents us from unifying rows with
  a common tail but a distinct prefix"*, with the witness
  `\r → if True then {x = 2 | r} else {y = 2 | r}` — and the observation that *"the unification
  rules of TREX fail to terminate for this particular example"*.  That is a published instance of
  the same failure mode `TICKET-sat-termination.md`'s W2/W3/W4 witnesses exhibit, and Leijen's
  answer is a **syntactic guard**, like `KeyedSplit`'s.
* **[V]** Adam Chlipala, *Ur: Statically-Typed Metaprogramming with Type-Level Record Computation*,
  PLDI 2010, pp. 122–133, [doi:10.1145/1806596.1806612](https://doi.org/10.1145/1806596.1806612)
  (<https://adam.chlipala.net/papers/UrPLDI10/UrPLDI10.pdf>).  **The closest algorithmic relative
  to Ermine's solver**, and the closest in candour.  Disjointness `c₁ ~ c₂` is a guarded type
  `[c₁ ~ c₂] ⇒ τ`, a guarded expression, and a kinding premise of `++`.  It is discharged by a
  **syntactic saturation**: decompose both rows with `D`, take the *symmetric closure of the
  Cartesian product* as facts, and check a goal by decomposing and looking every pair up, with an
  explicit *"not provable yet"* case and a retry loop.  And: *"**Type inference for Ur is
  undecidable, and we have no theorems that support our choice of inference procedure.**  Instead,
  we point to empirical evidence of Ur/Web's effectiveness."*  The equality rewrite system is only
  *"conjectured"* terminating and confluent.  **Residual disjointness constraints never appear in
  inferred signatures**, because Ur *"require[s] that all polymorphism be annotated explicitly at
  the definitions of functions"* — so Ermine's residual-noise problem is one Ur does not have and
  cannot have.
* **[V]** João Alpuim, Bruno C. d. S. Oliveira and Zhiyuan Shi, *Disjoint Polymorphism*, ESOP 2017,
  LNCS 10201, pp. 1–28,
  [doi:10.1007/978-3-662-54434-1_1](https://doi.org/10.1007/978-3-662-54434-1_1).  Disjoint
  quantification `∀(α * A). B`; **Theorem 4 (Unique elaboration)** is the coherence result;
  type safety and coherence are mechanised in Coq
  (<https://github.com/jalpuim/disjoint-polymorphism>).  **No decidability theorem for
  disjointness** — that arrives in Bi, Xie, Oliveira and Schrijvers, *Distributive Disjoint
  Polymorphism for Compositional Programming*, ESOP 2019,
  [doi:10.1007/978-3-030-17184-1_14](https://doi.org/10.1007/978-3-030-17184-1_14), whose abstract
  claims *"decidability of the type system"* while noting *"except some manual proofs of
  decidability"* outside Coq.
* **[V]** GHC.  `mAX_SOLVER_ITERATIONS = 4` and `mAX_REDUCTION_DEPTH = 200`,
  `compiler/GHC/Settings/Constants.hs`; the error and hint quoted in §2 row 8;
  `Note [SubGoalDepth]` in `compiler/GHC/Tc/Types/CtLoc.hs`;
  `Note [Expanding Recursive Superclasses and ExpansionFuel]` in `compiler/GHC/Tc/Solver/Solve.hs`;
  tracking issue [GHC #18641](https://gitlab.haskell.org/ghc/ghc/-/issues/18641) for the flag being
  undocumented; the last official wording,
  <https://downloads.haskell.org/~ghc/8.0.2/docs/html/users_guide/flags.html>.

### 5.2b What the GHC precedent implies for two A1 open gaps

Two of the open gaps recorded at the A1 adoption have a directly usable precedent, so they are
worth restating with it.

* **"The budget diagnostic carries no diagnostic `code`"** (`lsp/Diagnostics.scala:167`), judged
  acceptable at adoption with a follow-up.  GHC gives *both* of its fuel diagnostics a code —
  `GHC-95822` for the iteration limit and `GHC-40404` for reduction depth — precisely so that
  tooling can tell a resource limit from a type error without reading prose.  That is the
  follow-up, already designed by someone else.
* **"No a-priori fuel number"** — 20,000 is an empirical ceiling with 61× headroom, not a derived
  one.  GHC is in the same position and says so in the diagnostic itself: *"Use
  `-freduction-depth=0` to disable this check (**any upper bound you could choose might fail
  unpredictably with minor updates to GHC**, so disabling the check is recommended if you're sure
  that type checking should terminate)."*  The useful lesson is not the number but the **shape**:
  GHC pairs the ration with a *real* termination proof for a decidable fragment (the Paterson and
  Coverage conditions) and rations only outside it.  Ermine's analogue exists — `KeyedSplit.lean`
  and `VocFix.lean` prove termination for identified fragments — and the honest presentation is
  the same one: *proved terminating here, rationed there*, with the diagnostic saying which.
* One thing **not** to copy: GHC's `-fconstraint-solver-iterations` is a "please yell" backstop on
  a loop that converges in one round.  Ermine's `solveBudget` is not that; the L5 rounds found real
  divergence.  The parallel is `-freduction-depth`, and the memo's §2 row 8 says so.

### 5.3 Related mechanisations worth knowing about

Relevant because this tree is a Lean 4 development and the neighbouring literature has just started
mechanising.

* **[S]** Ningning Xie, Bruno C. d. S. Oliveira, Xuan Bi and Tom Schrijvers, *Row and Bounded
  Polymorphism via Disjoint Polymorphism*, ECOOP 2020,
  [doi:10.4230/LIPIcs.ECOOP.2020.27](https://doi.org/10.4230/LIPIcs.ECOOP.2020.27) — Coq, at
  <https://github.com/xnning/Row-and-Bounded-via-Disjoint>: an elaboration of **row polymorphism**
  into disjoint polymorphism, with a logical-relation coherence proof.
* **[S]** Toohey, Chen, Jamalzadeh and Xie, *Extensible Data Types with Ad-Hoc Polymorphism*,
  **POPL 2026**, PACMPL 10(POPL) 568–596,
  [doi:10.1145/3776662](https://doi.org/10.1145/3776662); artifact Zenodo
  [10.5281/zenodo.17298034](https://doi.org/10.5281/zenodo.17298034).  Rows plus type classes,
  elaborated into `F_ω^{⊗⊕}`, **mechanised in Lean 4** — the closest technical neighbour to this
  project's own toolchain, and the place to look first for library and idiom before §3 rank 2 is
  written.
* **[V]** Adam Chlipala, Featherweight Ur — soundness **by elaboration into CIC**, mechanised in
  Coq in the Ur/Web distribution's `src/coq`: *"since we give our semantics elaboratively, there is
  no need to prove a separate type soundness theorem."*
* No mechanisation exists of Leijen's scoped labels, of Koka's row-polymorphic effect types, or of
  Links's row types.

### 5.4 What I could not verify

1. **Whether Figure 1 is the whole of `⇒simp`.**  Its caption says "**Excerpted** typing and
   entailment rules".  Figure 3 (scoped rows) and §4.4 (trivial rows) both show a
   containment-from-combination rule that the simple theory presumably also has.  §1.3 states the
   consequence: adding it changes nothing in the table, because it is a rule about `≼` and Ermine
   has no `≼`.  But I cannot claim to have seen the complete simple-row entailment relation.
2. **Theorem 11's evidence term.**  In the published text the translation `E` is written **without
   a subscript in all three positions** of the statement, where one would expect `E₀` for the
   principal derivation.  I have quoted it as printed and cannot tell whether that is intended.
3. **Rose's Example 3 is asserted, not proved.**  "We have that `⟨L ⇀ T, ⊔, ∅⟩` is an algebra for
   the simple row theory" comes with a footnote saying a formal demonstration *"would require
   building similar maps from the syntax of rows present in each language"* — i.e. the soundness of
   `⇒simp` for its intended algebra is not discharged in the paper.  §3 rank 2 would discharge the
   Ermine-side analogue, which is a small point in its favour.
4. **Wand's 1988 corrigendum (LICS 1988, p. 132) could not be obtained.**  What §1.5 rests on is
   the *concatenation* theorem of LICS 1989 / I&C 1991, which was read directly.  The status of the
   1987 *extension-only* system is reported from three secondary sources that agree: Wand himself
   (I&C 1991 §8, *"unfortunately the unification algorithm in that paper was incorrect"*), Rémy
   (taoop1, *"a previous solution given by Wand in 1988 did not admit principal types but complete
   sets of principal types"*), and Leijen (§3.3, diagnosing free extension as *"an ambiguous
   interpretation … as a mixture of update and extension"*).
5. **The `NormalPart.hashCode` defect is read from the code, not measured.**  The mechanism is
   solid — inconsistent `equals`/`hashCode` under a `HashSet`-based `distinct` — and it predicts
   exactly the duplicates `A1-REVIEW.md` §R-1 found, but I did not run the compiler (three agents
   are running gates on this machine).  **Reproducing it is acceptance criterion #1 of §3 rank 1**,
   and if it does not reproduce, rank 1's payoff estimate is wrong and the rest of the ranking
   should be re-read.  The same caveat applies to the missing `None` case for `a <- (a)`, though
   `TopReadings.e:31` records the published tautology directly.
6. **No Lean was built.**  §4's scratch file was elaborated with `lake env lean` against the
   already-built library; no `lake build` was run, per the stage's constraints.
7. **Nothing here was validated against a compiler run.**  Every performance and `.ei` claim in §3
   is a prediction; the measurements cited are all of the incumbent, from `A1-ADOPTION.md`,
   `A1-REVIEW.md`, `S2-FIX.md` and `core/examples/Ai/README.md`.
