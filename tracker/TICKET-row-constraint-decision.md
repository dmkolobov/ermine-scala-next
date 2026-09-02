# TICKET — a principled decision procedure for row-partition constraints

Status: RESEARCH COMPLETE, DESIGN AWAITING SIGN-OFF. No Scala changed.
Date: 2026-08-31. Branch: scala3-migration.
Deliverable 2 (Lean) is `tracker/lean/`; deliverable 3 (ranked recommendation) is §7.

Everything in §§1–4 is either MEASURED in this repo this session or CITED to a
source that was fetched and read. Where a claim is neither, it says so.

---

## 0. The one-paragraph answer

Ermine's partition constraint is **ACUI set-union plus disjointness** over finite
label sets — the "simple rows" theory of Morris & McKinna's Rose framework, and
the same algebra Ur implements. Union *alone* is in P; **disjointness is exactly
what makes it NP-complete**, and that is a published result about essentially
this problem (Palsberg & Zhao, Thm 6.4). So no clever solver will make the
general case cheap. But the general case is not what Ermine runs into. The
measured pathology is not that the answer is hard to compute — it is that
**the current solver computes an answer it already had.** On both divergent
families the retained residual is *byte-for-byte its own input*: eight
constraints in, the same eight constraints out, after 175 seconds. The entire
super-exponential search is discarded by `Subst.reduce`. The recommendation
(§7) is therefore not a cleverer search but a smaller one: keep the
non-generative rules as a terminating canonicaliser, and answer the genuinely
hard question (entailment) with a real decision procedure on demand.

---

## 1. What this problem is, exactly

### 1.1 The constraint language, restated semantically

A constraint `a <- (b, c, (|Foo|))` asserts, for an assignment ρ of variables to
finite label sets:

    ρ(a) = ρ(b) ∪ ρ(c) ∪ {Foo}    and    ρ(b), ρ(c), {Foo} pairwise disjoint.

Rows are variables or fully concrete sets; there is no complement, no
intersection, no nesting. A system is a pure conjunction. Constraints live only
in strictly positive positions (`Subst.scala:862`, `Type.scala:201`), so they
cannot accumulate across a higher-order boundary.

**The decisive structural property** — satisfaction is *pointwise in the label*.
Each label independently chooses which single part of a partition contains it,
and no constraint in the language relates two labels (there are no cardinalities,
no label variables, no complement). So a system decomposes into one independent
Boolean CSP per label, over the relations

    R_k = { 0^(k+1) } ∪ { (1, e_i) : i < k }

i.e. "the left side is on iff exactly one right part is on". This decomposition
is the justification for everything algorithmic below; it is stated as a Lean
theorem in `tracker/lean/Rowpartition/Basic.lean` (see §6 for what is actually
proved).

### 1.2 Which framing is faithful — and which are not

| framing | verdict | why |
|---|---|---|
| **Rose "simple rows"** (Morris & McKinna, POPL 2019) | **FAITHFUL** | Their combination predicate `ζ₁ ⊙ ζ₂ ~ ζ₃` is interpreted in the partial monoid of label-indexed maps under union *defined iff domains are disjoint* (Example 3). That is precisely Ermine's binary partition. The authors identify this algebra with Chlipala's Ur. Ermine's n-ary partition is a ⊙-chain through fresh intermediates; Rose's containment `≤` is definable in Ermine by minting a complement variable. |
| **Per-label Boolean CSP** | **FAITHFUL** | Exact, polynomial, structure-preserving in both directions (§1.1). This is the framing the complexity results below are stated over. |
| **ACUI / ACI1 unification** | RELAXATION | Dropping disjointness maps Ermine to ACUI; every Ermine-solvable system maps to an ACUI-solvable one, not conversely. Disjointness is *not expressible as an equation* in a union-only signature, and ⊎ is a **partial** operation, so "unification modulo disjoint union" is not an equational theory in the standard sense. This is why no dedicated study of it exists. |
| **Boolean unification** | GENERALISATION | The embedding is lossless (`a = b + c + ΣS` with zero products), but Boolean unification's language has complement and intersection, and its hardness results (NP-, Π₂ᵖ-, PSPACE-complete; Baader 1998) are upper bounds that do not transfer down to Ermine's strictly positive fragment. Its *unifiers* are also inexpressible in Ermine's syntax. |
| **Set constraints** (Aiken et al.) | OVER-GENERAL | Ermine embeds, so decidability transfers downward — but it lands entirely in the **constants-only** row of the Aiken–Kozen–Vardi–Wimmers arity hierarchy, where satisfiability is NP-complete. The NEXPTIME-completeness of general set constraints (Bachmair–Ganzinger–Waldmann, LICS 1993) comes from constructors Ermine does not have and **does not apply**. |
| **Gaster–Jones "lacks"** | STRICT RESTRICTION | See §3.1. |

### 1.3 Decidability and complexity — the settled results

**Satisfiability with concrete labels is NP-complete.**
*Membership*: by §1.1, guess one Boolean assignment per mentioned label; there
are at most |labels|+1 label classes, and the generic class is satisfied by
all-zeros. *Hardness*: positive/monotone One-in-Three SAT is NP-complete
(Schaefer, STOC 1978, Thm 2.1, with `R₆ = {(0,0,1),(0,1,0),(1,0,0)}`), and
reduces directly — a clause `{x,y,z}` becomes `L <- (x, u), u <- (y, z)` for one
fixed concrete singleton `L`.

Three independent corroborations of the same boundary:
- **Palsberg & Zhao**, *Type Inference for Record Concatenation and Subtyping*,
  Inf. & Comp. 189(1), 2004, **Thm 6.4**: type inference with **symmetric**
  (disjointness-guarded) record concatenation is **NP-complete**, hardness by
  3-SAT. This is a published result about essentially Ermine's inference problem.
- **Aiken, Kozen, Vardi & Wimmers**, CSL 1993: constants-only set constraints are
  NP-complete ("essentially Boolean satisfiability").
- **Karp 1972**: EXACT COVER and 0-1 integer programming, both of which encode it.

**Union without disjointness would be in P.** ACI1/ACUI unification with
constants is polynomial — indeed P-complete — for systems of equations, by
reduction to propositional Horn satisfiability (Kapur & Narendran 1992; Baader &
Snyder, *Unification Theory*, Handbook of Automated Reasoning ch. 8; Dovier,
Pontelli & Rossi, *Set Unification*, TPLP 6(6), 2006, §4.6). **This is the sharp
statement of where the difficulty lives: not in the union, in the disjointness.**

**The homogeneous case is trivially satisfiable, and it is almost the whole
corpus.** Every `R_k` is 0-valid, so a constant-free system is satisfied by the
everywhere-empty assignment (Schaefer's dichotomy, 0-valid row). Measured: **not
one of the 345 partition constraints in the 129-module boot closure contains a
concrete label.** So for the stdlib the solver's search cannot be justified as
"checking satisfiability" — there is nothing to check.

*This does not extend to `core/examples`, and the difference matters.* Of the 12
partition constraints in the 15 example interfaces, **8 carry concrete labels**,
across three signatures. The sharpest is `PivotTest.pivotData`:

    (|Issue, Key, Value|) <- ((|Key|), i, v3)

which says `i ⊎ v3 = {Issue, Value}` with `i` and `v3` existential — genuinely
underdetermined (four solutions), and left unsolved in the shipped `.ei`. This is
the only place in the 180-file corpus where the NP-hard flavour of §1.3 is
actually present, and it is present as an *ambiguous residual* rather than as
expensive search. Any replacement must reproduce it, not "solve" it.

**But equivalence of homogeneous systems is coNP-complete**, and this is exactly
the residual-simplification problem. Böhler, Hemaspaandra, Reith & Vollmer,
*Equivalence and Isomorphism for Boolean Constraint Satisfaction*, CSL 2002,
**Thm 6**: EQUIV(C) is in P if C is Schaefer and coNP-complete otherwise; the
coNP-hardness in the **constant-free, 0-valid, non-1-valid** case — precisely
Ermine's homogeneous `R` — is their Claim 13(2). `R_k` is not Schaefer: not Horn
(110 ∧ 101 = 100 ∉ R), not dual-Horn (110 ∨ 101 = 111 ∉ R), not affine, not
bijunctive (majority(000,110,101) = 100 ∉ R).

**Unification type.** Because Ermine's syntax has no ∪, ∩ or complement, most
general unifiers are generally *not expressible in the language*, whatever the
theory's unification type. This is why the qualified-type (residual-constraint)
formulation is the right one for Ermine and the unifier formulation is not — and
it is also why the ACUI unification-type literature, which is preorder-sensitive
and delicate (Baader & Fernández Gil: ACUI is unitary w.r.t. the restricted
instantiation preorder but *infinitary* w.r.t. the unrestricted one), does not
settle anything for Ermine.

### 1.4 Prior art with a working solver

- **Ur** (Chlipala, PLDI 2010) is the closest algorithmic relative: the same
  algebra, and a constraint engine that mirrors Ermine's rule-for-rule (atomic
  decomposition, pairwise closure of disjointness facts, fresh-variable
  rewriting, a deferral loop). Chlipala states plainly: *"Type inference for Ur
  is undecidable, and we have no theorems that support our choice of inference
  procedure."* Ur is precedent, not a solution.
- **CLP(SET)** (Dovier, Piazza, Pontelli & Rossi, *Sets and Constraint Logic
  Programming*, ACM TOPLAS) is the most directly transferable algorithm found:
  its primitive constraints include a ternary union predicate `un(s,t,u)` and a
  binary disjointness predicate `disj(s,t)`, with a **sound, complete and
  terminating** solver. Ermine's `a <- (b,c)` is exactly `un(b,c,a) ∧ disj(b,c)`.
  Worth reading before implementing §7.

---

## 2. What the solver actually does — measured, not inferred

### 2.1 Two divergent families

Family A is `tracker/tools/gen-row-stress.py` (N left-nested `join`s in one
unannotated definition). Family B, **found this session and much smaller**, is
the *co-star*: m calls of one (m−1)-ary partition helper,
`x_i <- (b_0 … b_{m-1} minus b_i)`. One JVM per size, `-Dermine.useInterface=false`.

| N (join chain) | solve | ratio | | m (co-star) | solve | ratio |
|---|---|---|---|---|---|---|
| 4 | 0.03s | | | 4 | 0.03s | |
| 5 | 0.13s | 4.3× | | 5 | 0.09s | 3.0× |
| 6 | 0.79s | 6.1× | | 6 | 0.68s | 7.6× |
| 7 | 10.94s | 13.8× | | 7 | 6.38s | 9.4× |
| 8 | **312.46s** | 28.6× | | 8 | **175.68s** | 27.5× |

**Correction to PERF-ROADMAP.md**: N=8 was recorded as ">138s, killed". It is not
a hang — it **terminates in 312s**. Neither family exhibits actual
non-termination at any size tested. The pathology is super-exponential blow-up,
and this ticket does not claim more than that (see §8).

### 2.2 The decisive fact: the residual equals the input

Measured by `:type` on the equivalent lambda and by `:browse` on the compiled
module:

- Family A residual size is **3N − 3 — linear** (N=2..7: 3, 6, 9, 12, 15, 18).
- At N=5 the solver is handed 12 constraints (four `join` instances) and returns
  **those same 12 constraints**, structurally identical.
- Co-star at m=4,5,6 returns **exactly the m constraints it was given**.

So: **8 constraints in, 8 constraints out, 175 seconds.** The work grows
super-exponentially while the answer grows linearly, because `Subst.reduce`
(`Subst.scala:1037`) keeps only constraints whose LHS is ambiguous or
existential and throws the entire saturation away. On these families the search
is not merely expensive — it is *pure waste*.

### 2.3 The mechanism, isolated by controls

| probe | shape | constraints | solve |
|---|---|---|---|
| `Chain8` | 8 `join` calls sharing **no** row variables | 24 | 0.05s |
| `Overlap1` | `x_i <- (b_i, c)` — pairwise RHS ∩ = 1 | 8 | 0.03s |
| `Overlap2` | `x_i <- (b_i, c, d)` — pairwise ∩ = same 2 | 8 | 0.05s |
| `OverlapHalf` | 8 distinct 4-subsets of 8 (shared 3-prefix) | 8 | 0.07s |
| `PartStar4` | 4 co-stars over a ground set of 8 | 4 | 0.11s |
| `PartStar5` | 5 co-stars over a ground set of 8 | 5 | 0.60s |
| `PartStar6` | 6 co-stars over a ground set of 8 | 6 | 9.16s |
| `CoStar8` | 8 co-stars over a ground set of 8 | 8 | 175.68s |

The cost is **not** constraint count (24 non-overlapping constraints cost
0.05s), and **not** overlap size alone (`OverlapHalf` overlaps by 3 and costs
0.07s). It is the size of the **meet-semilattice generated by the RHS sets under
intersection**, which `commonSubexpression` (`Constraints.scala:1076`) names one
fresh variable at a time — the fresh variable re-enters the queue and is compared
against everything already processed. For k co-stars that closure is the full
subset lattice, 2^k. `PartStar` over a *fixed* ground set confirms the exponent
is k, not the ground-set size: 0.11 → 0.60 → 9.16 → 175.7 for k = 4, 5, 6, 8.

That is a **predictive** model, not a description: it says which programs are
expensive before you run them, and it identifies the responsible rule.

**The smallest pathological input measured is six constraints** (`PartStar6`,
9.16s). Not six hundred, not sixty — six. That is well inside what a user writes
by hand, and it is why this is a correctness-of-experience problem rather than a
scaling problem.

**A note on acceptance criterion 5.** It asks for verification "with
gen-row-stress.py at N=8..20". For the *replacement* that is the right test. For
the **incumbent** it is not runnable: extrapolating the measured ratio (28.6× from
N=7 to N=8, and rising) puts N=9 at roughly four hours and N=10 at over a week.
N=8 at 312s is the last size anyone will ever measure on the current solver. The
criterion should be read as a requirement on the new implementation, with the
incumbent's curve taken from the table above.

### 2.4 Annotation really is the escape hatch

An annotated signature carrying the same constraints checks in 0.02–0.03s. The
blow-up requires **inference**. This matters for §7's diagnostic: the advice
"add a signature" is measured to work, not merely plausible.

### 2.5 What CHR theory says about repairing the rules in place

The existing rule set is a CHR program, and its four fresh-variable rules
(`splitConcrete`, `resolution`, `commonSubexpression`, `disjunction`) are
**propagation rules with local variables**. Frühwirth's ranking method for
proving CHR termination applies **only to programs without propagation rules** —
Theorems 1 and 2 both carry that hypothesis, and the paper states *"We currently
cannot deal with propagation rules in their generality"*, noting the ranking
condition fails when the body contains local variables not occurring in the head.
That is exactly this rule shape. So the answer to research question 3's "or show
none exists" is: **the standard CHR termination technique does not apply to these
rules, by its own stated hypothesis.** Confluence is more tractable — Haemmerlé's
diagrammatic-confluence result (TPLP 12(4-5)) proves confluence *without* global
termination by partitioning rules into inductive and coinductive sets — which is
directly usable for the design in §7, where only the non-generative core needs to
be confluent.

Leijen also documents that this rule shape genuinely diverges in a shipped
system: *"the unification rules of TREX fail to terminate"* for records sharing
an abstract tail.

---

## 3. Is there a fragment that covers all real uses?

The corpus is the 180 files the acceptance criterion names: the 129-module stdlib
closure **plus `core/examples`**. Measuring only the stdlib is the trap this
project has fallen into before, and the two halves genuinely differ (§1.3).

*Stdlib closure* — 1447 signatures, of which **199 carry at least one partition
constraint**, 345 constraints in total. 135 of the 199 carry exactly one; the
maximum is 15 (`lookbackJoin`). 133 are annotated in source, 66 inferred. RHS
arity: 10 unary, 220 binary, 77 ternary, 28 4-ary, 4 5-ary, 4 6-ary, 2 7-ary.

*`core/examples`* — 15 interfaces, **9 constrained signatures, 12 constraints**
(arity 4×binary, 3×ternary, 5×4-ary), in `ChartsExample`, `GridExample`,
`PivotTest` and `SoftRelation`. Unlike the stdlib these carry concrete labels
(8 of the 12). They contain **no** vacuous constraint, **no** duplicate, and
**no** signature constraining the same variable twice.

*Combined*: **208 constrained signatures, 357 partition constraints.**

### 3.1 Gaster–Jones "lacks" — NO, and the refutation is structural

A `lacks` predicate `r \ l` is exactly the Ermine partition
`exists s. s <- (r, (|l|))` — arity 2, one abstract component, the other a
concrete singleton. Ermine strictly contains it. The converse fails for a reason
verified in the source: **Gaster & Jones's predicate grammar has exactly one form,
`π ::= C^row \ l`, relating a row to a single concrete label; no form relates two
abstract rows.** The authors say so themselves in their conclusion: *"Our type
system does not support record append or the database join that was one of the
original motivations for Ohori's work. One approach would be to adopt the ideas
of Harper and Pierce, choosing an appropriate form of evidence for the (r1 # r2)
predicates."* Disjointness-of-two-unknown-rows is the acknowledged missing
feature.

Quantified against the corpus: **220 of 345 constraints are binary with both
sides abstract** — the exact shape `lacks` cannot express. Coverage is not
1447/1447; it is not even close.

### 3.2 Leijen's scoped labels — NO, for a different reason

Scoped labels obtain sound, complete, terminating unification with most general
unifiers precisely by **abandoning disjointness** (duplicate labels are allowed
and shadow). That is not a restriction of Ermine's language, it is a different
language: Ermine's relations are sets of *distinct* columns, and a join whose
operands share a column must be rejected, not shadowed. Likewise PureScript's
`Union` is left-biased multiset append, not disjoint union; MLstruct recovers
principality by moving to a full Boolean algebra *with complement*, which Ermine
deliberately lacks.

### 3.3 The definitional fragment — 95%, and it is the useful answer

Call a system **definitional** when every variable is the LHS of at most one
constraint and the dependency graph is acyclic. Then repeated expansion assigns
every variable a canonical *leaf expansion* (a multiset of leaf variables plus a
concrete set), and entailment is decided by multiset comparison in polynomial
time.

Measured over all 208 constrained signatures:

- **181 / 199** stdlib signatures are definitional as printed; **189 / 199 (95%)**
  after dropping the solver's own vacuous `x <- (x)` junk.
- **9 / 9** example signatures are definitional, with nothing to drop.
- **Combined: 198 / 208 (95.2%).**
- **The only cycles anywhere in the corpus are those vacuous self-constraints.**
  Not one genuine cyclic dependency exists in 357 constraints.
- The 10 genuinely non-definitional signatures are, in full: `getF2`,
  `lookbackJoin`, `replaceColumn`, `setColumn`, `(<=)`, `(>=)`,
  `drilldownKeyValueTable2`, `drilldownPivotTabular`, `drilldownPivotTabular'`,
  `combine` — all in the stdlib, none in the examples.

**So the honest answer to research question 2 is 95%, not 100%.** A fragment that
covered 1447/1447 would indeed beat a cleverer solver, and there isn't one. Ten
real signatures need genuine equation solving, and criterion 1 forbids regressing
them.

**A third side condition, found in Lean: LINEARITY.** Leaf-expansion
completeness also needs no variable to repeat inside one right-hand side. The
counterexample is small and proved (`tracker/lean/Rowpartition/Fragment.lean`,
`NonLinear`): `p <- (d, d)` is definitional and acyclic, but disjointness forces
`d = ∅` and hence `p = ∅`, which the multiset test cannot see — it compares the
multiset `{d, d}` against `{}` and reports a difference. So the multiset test is
incomplete *inside* the definitional fragment, not only outside it. This costs
nothing in practice: **no right-hand side anywhere in the 357-constraint corpus
repeats a variable**, so all 198 definitional signatures are linear too. But a
decision procedure must apply de-duplication before comparing.

**The crucial caveat, and it cuts against a naive fragment story**: the co-star
family *is* definitional (distinct LHSs, acyclic, linear) and still costs 175s in
the current solver. "Definitional" is cheap for a leaf-expansion procedure and
expensive for the incumbent. The fragment is a property of the *problem*, not a
property the current implementation exploits.

### 3.4 What users actually write

Ermine's stdlib defines the user-facing vocabulary in `Constraint.e`:

    type Has a b       = exists c. a <- (b, c)               -- containment
    type (|) a b       = exists c. c <- (a, b)               -- disjointness
    type RUnion2 t r s = exists ro so rs. t <- (ro,so,rs), r <- (ro,rs), s <- (so,rs)
    type RUnion3 v r s t = ...                               -- 7 regions, 4 constraints

Usage across the entire stdlib: **`Has` 31, `RUnion2` 11, `RUnion3` 2, `Union` 2,
`Intersection` 1.** Raw `<-` appears essentially only inside `Constraint.e` and
the modules defining those idioms. `RUnion2` and `RUnion3` are **hand-written
inclusion–exclusion lattices** over 2 and 3 sets (3 and 7 regions); `RUnion3`'s
4-constraint, 7-variable shape is the most expensive thing in the corpus, and its
cost is intrinsic to the combinatorics its author wrote out by hand. A
hypothetical `RUnion4` would need 15 regions.

---

## 4. The existing defects, quantified

**Non-confluence / non-canonicity.** Measured across the corpus: **9 vacuous
`x <- (x)` constraints across 9 signatures**, and **4 signatures carrying the
same constraint two, three or four times under permuted RHSs** (10 excess atoms) (`lookbackJoin`,
`drilldownKeyValueTable2`, `drilldownPivotTabular`, `drilldownPivotTabular'`).
Saturation stops at a non-canonical form.

**Non-determinism.** The priority-queue key is `(rhs.hashCode, lhs.hashCode)`
(`Constraints.scala:453, :483`) and a `TypeVar`'s hash is its `Supply`-drawn id,
so parallel loading changes solve order and reaches the emitted `.ei` bytes —
which is why `-Dermine.loadInSeries` exists. Separately, `Part.apply`
(`Type.scala`) accumulates its abstract RHS with `(other :: ts)` inside a
`foldLeft`, **reversing the list on every substitution pass**, so a partition's
rendered order depends on how many passes ran.

### 4.1 Exactly which signatures move if the residual is made canonical

Acceptance criteria 1 ("1447 signatures EQUIVALENT, no drift") and 4 ("residuals
canonical") are **in tension**: the baseline itself contains the vacuous and
duplicated constraints, and `G1Compare` matches constraint lists by multiset, so
removing them changes the `.ei`. The tension is small and fully enumerable.

Running all 208 constrained corpus signatures through the non-generative
canonicaliser proposed in §7 (self-substitution, de-duplication, empty
propagation, singleton-RHS unification, common-partition unification, vacuous
drop — no fresh variables):

- **196 of 208 are already fixpoints.** They come out byte-identical.
- **12 signature instances change**, and every change is a cleanup the criteria
  ask for. In full:

| signature | module | constraints | vacuous | duplicate |
|---|---|---:|---:|---:|
| `count` | `Relation` | 1 | 1 | |
| `count` | `Relation/Aggregate` | 1 | 1 | |
| `negate` | `Relation/Op` | 1 | 1 | |
| `growthOf10k` | `Relation/Op` | 1 | 1 | |
| `dateRange` | `Relation/Op` | 4 | 1 | |
| `maxRowBy` | `Relation` | 2 | 1 | |
| `minRowBy` | `Relation` | 2 | 1 | |
| `keyedDrilldown` | `Layout/Report` | 3 | 1 | |
| `lookbackJoin` | `Relation` | 15 | 1 | 2 |
| `drilldownKeyValueTable2` | `Layout/Report` | 5 | | 1 |
| `drilldownPivotTabular` | `Layout/Report` | 6 | | 1 |
| `drilldownPivotTabular'` | `Layout/Report` | 6 | | 1 |

That is the complete, reviewable baseline movement: **19 atoms across 12
signature instances** — 9 vacuous `x <- (x)` constraints (one each, in nine
signatures) and 10 excess duplicate atoms in four (`drilldownPivotTabular` and
`drilldownPivotTabular'` each carry *four* copies of the same constraint, so
three go from each; `drilldownKeyValueTable2` carries three copies;
`lookbackJoin` carries two pairs). `lookbackJoin` appears in both lists, and
`count` occurs in two modules, so the twelve instances are eleven distinct
names. A
re-cut of `tracker/g1-baseline` limited to exactly these 12 is a deliberate
change with a stated reason, not drift — which is what Decision 9 asks for. If a
13th signature moves, that is a bug, and the diff is small enough to say so
confidently.

*Caveat*: this was computed with a Python model of the rules
(`tracker/tools/`-adjacent, not committed), and that model does not faithfully
handle concrete label sets. The three concrete-bearing example signatures
(`pivotData`, `pivotData2`, `showWordstats`) were excluded from the change count
for that reason and must be checked against the real implementation.

### 4.2 A third defect: the documented resolution rule is stated backwards

**FIXED 2026-09-01** (ticket item 8a). The header diagram now states the sound crossed
pairing, with the reason and the Lean theorem names recorded in place. Two independent
readings of `def resolution` that day confirmed the implementation always computed the
sound form — which is the discharge of `tracker/lean/README.md`'s "proved on paper only"
item 3, the one it says a reviewer should check against `Constraints.scala` directly.
The paragraphs below describe the state before that fix.


`Constraints.scala`'s header comment gives Resolution as

        a <- C* D* x
        a <- y  D* E*
       ---------------
       a <- C* D* E* z   (z fresh)
          x <- C* z
          y <- E* z

The implementation (`resolution`, :1021) computes `int = concr1 & concr2`,
`tops = concr1 -- int`, `bots = concr2 -- int` and emits

       Partition(x, RHS(Set(z), bots))     -- x <- E* z
       Partition(y, RHS(Set(z), tops))     -- y <- C* z

i.e. **the opposite pairing to the comment**. The implementation is the correct one: from
`a = C ⊎ D ⊎ x` and `a = y ⊎ D ⊎ E` it follows that `x ⊇ E` and `y ⊇ C`, not the
reverse. Formalising the rule as the diagram writes it produces a statement that
is **not sound**, which is how this was found
(`tracker/lean/Rowpartition/Rules.lean`, `Rule6Header.*`): the premises have a
model, no extension of it satisfies the diagram's conclusion, and premises plus
conclusion are outright unsatisfiable — a solver following the diagram would
report a spurious type error.

**The defect is confined to the ASCII diagram.** The prose immediately above it
says the lone right-hand variables "contain the fields missing from *their*
rule" — `x` sits in the rule carrying `C* D*`, the fields missing from that rule
are `E*`, so the prose says `x ⊇ E`. That is the code's behaviour. Only the
diagram disagrees, with its own prose as well as with the implementation.

Two further side conditions, both settled in Lean:
- With the pairing merely swapped and `C`, `E` written raw, the rule is sound
  **only** given `Disjoint C E`, and the premises do not force that
  (`rule6_swapped_needs_disjoint`). The sharp form `x <- (E \ C) z`,
  `y <- (C \ E) z` needs no hypothesis beyond what the premises already give —
  and subtracting the intersection is exactly what `resolution` computes, which
  is why the implementation is sound without stating the condition.
- Cancellation's shared concrete part must genuinely be shared: the first
  premise's concrete part must be a **subset** of the second's. `a <- C* x* z` /
  `a <- C* x* D* d*` reads as though `C*` is common by construction; it is a real
  side condition, and the rule is unsound without it.

None of this is a live bug — the code is right. But the 240-line header is what
this ticket sends a reader to, and it is the artefact a reimplementation would be
written from. Fix the diagram.

**A precedent that matters for §7**: one of the four generative rules —
`disjunction`, the cubic one — is **already commented out at both call sites**
(`Constraints.scala:814-818, :823-831`) and the corpus is unaffected. Removing a
generative rule is not a novel manoeuvre in this codebase; it has already
shipped once. Note also that the whole-loop property `incorporateAll sound` is
commented out in `TestConstraints.scala:484` — only individual rules are tested,
which is the missing net.

---

## 5. Rejected prior art

Commit **04c2308** (Dan Doel, 2018, branch `features/limit-row-solving`, never
merged) adds a 50,000-step countdown to `incorporateAll` and an exception named
`Eternity`. On cutoff it returns the constraint set **unsolved**, so residuals
leak into inferred types and **typing becomes a function of how long the solver
ran**. Any budget-based proposal must fix exactly that: the budget must be on a
canonical, order-independent measure of the *input*, and exceeding it must be a
hard error with a stable message, never a silently degraded type.

Every production precedent surveyed bounds a **syntactic** measure, never
wall-clock, for exactly this reason: GHC's `-freduction-depth` (default 200) and
`-fconstraint-solver-iterations`; OutsideIn(X)'s deliberate incompleteness with a
documented error contract; Rust's `recursion_limit` plus overflow error; Scala 3's
implicit divergence checker; Z3's deterministic `rlimit` as against its
non-deterministic `timeout`.

---

## 6. The Lean development

`tracker/lean/` is a Lean 4 + Mathlib development (toolchain pinned in
`lean-toolchain`; build with `export PATH="$HOME/.elan/bin:$PATH"` then
`lake env lean Rowpartition/<File>.lean`). **`tracker/lean/README.md` is the
authoritative per-theorem status**, including `#print axioms` checks that catch
any theorem which compiles but secretly depends on `sorryAx`. Read that, not
this summary.

What is there, and what it produced (all five files compile; the four reported
so far carry **zero `sorry`s**):

| file | thms | what it establishes |
|---|---:|---|
| `Basic.lean` | 54 | Syntax, semantics, and the **label-decomposition theorem** — satisfaction is pointwise in the label, in both directions. |
| `Rules.lean` | 54 | Soundness of the solver's rules, with the fresh-variable rules stated correctly as **conservative extensions** rather than plain entailments. |
| `Divergence.lean` | 82 | The co-star blow-up made structural: a proved lower bound of **2^m − m − 2** constraints. |
| `Fragment.lean` | 23 | The definitional fragment: abstract systems are always satisfiable, leaf expansion is well-defined and sound. |
| `Canonical.lean` | — | The proposed non-generative canonicaliser. |

**The five results worth carrying into the design**, each of which corrected or
sharpened something this ticket originally asserted:

1. **The documented resolution rule is unsound; the code is right.** §4.2. Found
   by trying to prove the header comment's version.
2. **Common-subexpression, as documented, does not terminate at all** — and a
   divergent seed appears at N = 1, inside a single `join`. The implementation
   survives only because of a memoisation (`findRHS`) absent from the
   specification. §8.2.
3. **Entailment does NOT decompose per label in general.** The natural per-label
   reading is *strictly stronger* than entailment, because an unsatisfiable
   hypothesis set entails everything while the per-label reading cannot see
   cross-label inconsistency (proved counterexample: `x = {5}` and `x = {6}`).
   It does decompose **given satisfiability**, and **unconditionally for abstract
   systems** — which is every stdlib residual. Any SAT-based entailment checker
   must establish satisfiability first or it will reject valid programs.
4. **Leaf-expansion completeness needs linearity**, not just definitionality —
   `p <- (d, d)` forces `d = ∅` and the multiset test cannot see it. §3.3.
5. **The lower bound is 2^m − m − 2, not 2^m − m − 1**, because the right-hand
   sides of the input constraints are themselves never re-named. At the measured
   m = 7 that is ≥ 119 constraints, which matches the observed cost.

**One place the formalisation sent us back to the code, and the code was right.**
Lean could not even *state* the duplicated-field error condition
(`a <- C* x* D D`) with a single concrete `Finset`, because the two `D`s flatten
into one set and the duplication vanishes; `Rules.lean` had to add a
`RawConstraint` carrying a *list* of concrete blocks. The practical consequence
is a real constraint on any implementation: **the duplicated-field check must
happen where a source right-hand side is turned into a solver constraint, because
after flattening the information is gone.** Checked against the code —
`RHS.build` (`Constraints.scala:370`) does exactly that, dying with "Fields appear
twice in row" on a concrete overlap *before* accumulating into `Set[Name]`, and
moving a repeated variable into the forced-empty list in the same pass. Likewise
`Part.apply` (`Type.scala`) refuses to merge concrete blocks when
`ss.toSet.size != ss.length`. A reimplementation that flattens earlier would
silently lose both checks.

### 6.1 The Pottier / Berthomieu bridge (three further modules)

Three modules were added to square the literature against the formalisation.
Independently verified: all eight modules **and the library root** type-check;
every headline theorem's axiom set is a subset of `{propext, Classical.choice,
Quot.sound}`, and `ternary_not_definable` depends on **no axioms at all**.

| module | lines | thms | what it settles |
|---|---:|---:|---|
| `Pottier.lean` | 1279 | 69 | the bridge to Pottier's LICS 2003 constraint language |
| `LabelClass.lean` | 701 | 48 | label signature classes — the wide-schema bound |
| `Berthomieu.lean` | 828 | 45 | `=_L` cannot express partition, with a classification |

The development is now **9 modules, 7745 lines, 0 `sorry`** — the only occurrence
of the word is a docstring saying there are none. I counted **530 theorem/lemma
declarations** plus 14 `example`s; `tracker/lean/README.md`'s headline says 570
named theorems. I could not reproduce that tally and did not chase it: the
discrepancy is in how declarations are counted, not in what is proved. Where the
two disagree, prefer the README's per-theorem tables and its `#print axioms`
audit, which are itemised.

**The relation is literally the same, checked three ways.** Enumerating
Pottier's three conditional constraints over his own Example-1 flat lattice
`{⊥,Abs,Pre,⊤}` and restricting to `{Abs,Pre}³` gives
`{(Abs,Abs,Abs),(Abs,Pre,Pre),(Pre,Abs,Pre)}`; enumerating `BSat`/`bparts` gives
`{(0,0,0),(1,0,1),(1,1,0)}`; and `Pottier.bridge` proves
`BSat b l ⟨a,[x,y],∅⟩ ↔ PottierConcat b x y a`. His `(φ₁,φ₂,φ₃)` puts the result
**last** where `Sat` puts the union **first**;
`bridge_result_position_sharp` proves the rotation is not optional.

**Pottier's grammar is irreducibly binary.** `ternary_not_definable` quantifies
over *all* finite conjunctions of his atoms and proves none defines
`a <- (x,y,z)` over its own four variables, while `pchainBit_iff_flat` proves the
binary chain **with existentially quantified intermediates** is exactly the flat
n-ary partition. So binarising Ermine's partitions is available, but the
intermediates are a necessity, not a convenience. The trade is explicit: Pottier
has many variables, bounded arity and polynomial closure; Ermine has few
variables, unbounded arity and exponential closure — and the exponent lives in
the **arity**, not in the fresh variables (which our own `coStar_card_lower`
already showed, since it assumes perfect hash-consing).

**The correction that matters most for the design.** Theorem 2 (termination) and
Theorem 7 (O(n³ m log m)) are proved *without ever mentioning the order*: Thm 2's
argument is purely syntactic, Thm 7 counts edges and triples. The lattice and
`⊥_field` buy **Theorem 4** — completeness of closure as a satisfiability test
*without search*. Therefore **a Pottier-style closure on Ermine's two-valued
domain would still terminate and still be polynomial; it would simply stop being
complete.** That is a far better starting position than "his machinery needs
subtyping, so it is unavailable to us", which is what a first reading suggests.
Note also that Thm 7 quantifies over arbitrary well-sorted constraints, not only
inference-generated ones, and that on this ticket's own NP-hardness gadget
`m = 1`, so his bound would read O(n³) there — the label-count escape is closed,
which forces the reconciliation onto expressiveness, where it belongs.

**Berthomieu's `=_L` is settled negatively, with a classification rather than a
counterexample.** `defines_partition_iff` proves `⟨a, vs, k⟩` is definable in the
`=_L`-plus-equality language **iff `vs.length = 1` and `k = ∅`** — i.e. nothing
of PARTITION survives except the degenerate `a <- (b)`, which is just `a = b`.
Two independent obstructions: adding one label to every variable preserves every
`=_L` (needing no freshness hypothesis at all), and the everywhere-empty
assignment models every such system, so it cannot even express "this row is
non-empty". See also §9 on why `=_L` is not Berthomieu's notation.

**Ermine's concrete part IS a Pottier filter — as a theorem, not an analogy.**
`sat_iff_filter_split` proves `a <- (b₁,…,bₙ,(|k|))` says exactly that on the
finite filter `k` the left-hand row is `Pre` and every variable part is `Abs`
(two filtered subtyping constraints), and off `k` it is the concrete-free
partition. This is Pottier's own diagnosis — "filters compensate the omission of
the row constructor `(ℓ : · ; ·)`" — proved about Ermine's `Constraint.conc`.
Note the correspondence runs concrete-block-to-filter; the RHS *variable* set is
the constraint's index, and that is where the unbounded arity lives.

**The wide-schema question, answered.** `LabelClass.lean` proves the per-label
instance depends on the label only through its *signature*
`sig G l = G.map (fun c => decide (l ∈ c.conc))`; hence `bmodels_congr` (equal
signatures are interchangeable), `satisfiable_iff_transversal` and
`entails_iff_transversal` — one label per signature **class**, not per label. So
a 500-column table whose columns always occur together is **one** class and costs
what a 1-column table costs. The bad case (blocks in general position realising
all 2^k signatures) is exhibited and the bounds proved simultaneously tight.

**Discipline for reading this**: §1's complexity results are **cited from the
literature, not mechanised** — no NP-hardness reduction is formalised here. The
Lean development covers the semantics, the rule soundness, the divergence bound,
and the properties of the proposed replacement. The README separates *proved in
Lean* from *proved on paper* from *cited*.

## 7. Recommendation

Five designs were developed independently, each adversarially audited against the
acceptance criteria, then scored by three judges on different lenses
(correctness/risk, cost/deliverability, principle). What follows is the
synthesis. The full proposal set, audits and scores are in this session's
workflow transcript; the load-bearing content is reproduced here.

### 7.1 The recommendation

**MAKE COMMON-SUBEXPRESSION NON-GENERATIVE — then canonicalize at the root cause, rank-order the whole solver, and bound work (not steps) as the last resort.** This is the "minimal" proposal cut at *branch* granularity rather than *rule* granularity — the variant its own adversarial auditor measured on a real build — plus the canonicity and determinism work every option needs, plus the per-label Boolean semantics from "decision" grafted in as the **acceptance oracle** rather than as the shipped solver.

**The core change (five lines).** In `commonSubexpression` (Constraints.scala:1060-1082 — I read it; it is exactly as described) replace only the final `else { val z = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin)); Set(3 partitions) }` with `Set()`. **Keep** the `rhss(rhsCommon) match { case Some(z) => ... }` reuse branch and **keep** both folding branches (`if(rhs1 == rhsCommon) ... else if(rhs2 == rhsCommon) ...`), which mint nothing and emit `Partition(u, RHS((abstr2 -- int) + v, concr2))` where `v` is the *other constraint's original LHS*. The invariant gained is exactly stateable: **CSE becomes non-generative.** The set of names available to denote an intersection is fixed at entry, so the RHS set is no longer closed under intersection and the meet-semilattice cannot fill in. This is not my diagnosis — it is the repo's own, written into `tracker/tools/gen-row-overlap.py`'s docstring: *"It is the size of the MEET-SEMILATTICE THE RIGHT-HAND SIDES GENERATE UNDER INTERSECTION. `commonSubexpression` (Constraints.scala:1076) names each distinct intersection with a FRESH variable that re-enters the worklist... so that is 2^m names."* Line 1076 is the `fresh` call, and nothing else.

Cutting the branch rather than the rule is the whole point, and it is why the original "minimal" proposal was killed while this variant survives. Its auditor measured full-rule deletion as FATAL three ways: the repo's own `property("join example")` at TestConstraints.scala:491 flips PASS → `Falsified after 0 passed tests`; a direct solver probe stops deducing `a={Fst}, b={Snd}, c={Thd}, f={Fst,Snd,Thd}`; and `join rl rr` over two concrete-schema relations degrades from `Relation (|vl,k,w|)` to an unresolved existential constraint set. The same auditor then measured the branch-only cut: **CoStar8 175.68s → 0.06s, RowStress8 >138s → 0.12s, RowStress20 0.13s, `join example` PASSES, the JoinProbe still deduces the concrete rows, and the browse.txt delta shrinks from 65 lines to 14.** The folding branches are load-bearing (they are what feed `resolution` on concrete input, via CSE-fold → substitution → resolution); the minting branch is the cliff. The proposal's stated justification — "CSE is a definitional extension, it states nothing new about any original variable" — is false of two of its three branches, and that is precisely why the cut must be at the branch.

**Canonicity, at the root cause, and it is not where the "minimal" or "restrict" proposals put it.** I re-derived the defect set from `tracker/g1-baseline/browse.txt` this session: **9 vacuous `x <- (x)` atoms across 9 signatures and 10 excess duplicate atoms across 4 signatures — 19 atoms, 12 distinct signatures** (lookbackJoin is in both lists). This corrects the ticket's "8 signatures / 4 signatures" and the minimal proposal's "17 atoms". Two fixes. (a) `Part.apply` (Type.scala:402): add `case VarT(v) if ts == List(VarT(v)) && ss.isEmpty => Exists(l)`, the variable analogue of the existing `ConcreteRho` tautology collapse that sits three lines above it, so vacuous atoms die at the smart constructor on every construction path. (b) `NormalPart` (Subst.scala:1300) is its **own** case class that overrides `equals` (id-sorting `abstrakt`, ignoring `loc`) and leaves the synthesized `hashCode` in force over `(loc, left, concrete, abstrakt-as-written)`; `normal.distinct` at :1345 is HashSet-backed, so the dedup its author plainly intended has never once fired. Fix it **on `NormalPart`**, giving it a `private val key = (left, concrete, abstrakt.map(_.id).sorted)` with both `equals` and `hashCode` on that key. Do **not** fix it at `Part.equals`/`Part.hashCode` as the "restrict" proposal recommends: `normal.distinct` never consults them, and making `Type` equality order-insensitive globally has a blast radius through `Type.===` (Type.scala:589), `instantiateType`'s guard, and every `Set[Type]` in the compiler.

**One ordering hazard I checked and cleared.** The "diagnose" audit warns that pruning vacuous atoms perturbs `mkSimplified`'s `isolated` fixpoint, changing which existentials survive as binders and which constraints land in `extinct`. It does not: `val iso = isolated(exts.toSet, ps)` is computed at the **top** of `mkSimplified`, from the raw `ps`, before `normalPart` ever runs. And I verified from the baseline that all 9 vacuous atoms have a **universal** LHS (`count`'s `b`, `dateRange_Op`'s `r1`, `lookbackJoin`'s `r` are all forall-bound) — an existential-LHS vacuous atom would already be classified `extinct` and never printed. So no binder list moves. That is a real cross-audit resolution, not a hope.

**Determinism, against a complete inventory rather than a partial one.** No single proposal enumerated all the leaks; the union of the five audits does. Ten sites: (1) the PSQ key `(rhs.hashCode, lhs.hashCode)` at :437/:452 with `V.hashCode = id`; (2) `reverseTopSort(newNodes.toStream)` tie-breaking over `Set[TypeVar]` at :413; (3) `findRHS`'s `rhs.hashCode` bucketing at :580; (4) `RHS.toTypes`'s `abstr.toList` at :341, which reaches binder lists through `typeVars(cs)`; (5) `Part.apply`'s RHS reversal per substitution pass; (6) `reduce`'s `abs.toList` at Subst.scala:1046; (7) **the `Set[Partition]` folds into `++!` at Constraints.scala:758, :878, :920, :954, :975** — `insert` consults `rhsLookup` *mid-fold* at :504-508, so whichever same-RHS partition lands first wins the common-partition unification and `instantiate` writes that survivor into the global substitution at :877; this class is immune to a comparator swap and appears in only one of the five proposals; (8) `Subst.scala:391`'s `(rs.toSet -- ...).toList` round-trip; (9) `generalize`'s `typeVars(...).toList` at :1113-1126; (10) upstream, `Binding.scala:105-112`'s Tarjan over hash-ordered maps and `toGamma(m) = m.values.toList` at Subst.scala:814, which fix binding-group order. The key must be a **rank assigned by first occurrence in a left-to-right walk of the constraint list `solve` receives**, with minted variables ranked after all input variables in mint order — and explicitly **not** source `Loc`, which the "restrict" audit proved non-injective across instantiations (`refresh` uses `v.loc.instantiatedBy(l)`, `Loc.instantiatedBy(l) = orElse(l)` at Locations.scala:17, and `unbind`/`unfurl` refresh at the Forall's own loc, so RowStress7's 21 row variables occupy 3 distinct Locs). The Labelwise auditor prescribed Loc-anchoring as the fix; the restrict auditor proved it unavailable. Neither could see the other. Occurrence-rank is what remains. Sites (1)-(6) and (8)-(9) take the rank comparator; site (7) needs a total `Order[Partition]` and sorted folds; site (10) needs an occurrence-ordered binding-group list. Also move `resolution`'s `fresh` draw at :1030 to *after* its `tops.isEmpty || bots.isEmpty` bail at :1034, so mint order and kept-variable order stop diverging.

**The backstop bounds work, not steps.** `splitConcrete` and `resolution` still mint and there is no measure for them; I claim none. So: a counter of **rule-application attempts** — one per `(u,rhs1) × (v,rhs2)` pair examined in `learnPartitions` (:805) plus one per `insert` — not a dequeue counter. The audit's objection to the "minimal" fuel is correct and decisive: the per-dequeue cost *is* the `proc.foldLeft` all-pairs scan, so counting dequeues bounds steps while leaving work unbounded. On exhaustion, `tml.die` — a hard type error. `reduce` is never reached, no partial queue is ever returned, and no unsolved residual can leak into an inferred type. That is precisely the property commit 04c2308's `Eternity` lacked.

**The acceptance oracle is the graft that matters most, and it goes in before the cut.** Satisfaction in this language is pointwise in the label, so a system decomposes into one small Boolean CSP per mentioned label plus one generic column, and small instances are exhaustively enumerable over `TestConstraints.scala`'s existing `Valuation`/`satisfies` machinery. Build that as a differential test oracle: every forced fact the solver applies must hold in every model; the retained residual must be equivalent to its input on the universals under exhaustive valuation over a small label universe; the output must be invariant under permutation of the constraint list, of any RHS, and under a random renumbering of TypeVar ids. Then re-enable the commented-out whole-loop `incorporateAll sound` property. **This exists because the corpus gate is structurally blind to the failure that killed the original proposal**: the auditor booted all 129 modules with CSE fully deleted and got a clean load, 1447 signatures, no new rejections — while the repo's own test was red and `join`'s concrete inference was gone. All 345 corpus residuals are label-free, permanently, so "the corpus is green" will never be evidence about the concrete-label path. And user code reaches that path in three lines: `sub : Has r s => Relation r -> Relation s` applied to `Relation (|A,B|)` infers `forall s. (exists c. (|A, B|) <- (s, c)) => Relation s`, a residual carrying a concrete label, measured live.

**What this deliberately is not.** It is not the row-solver replacement. Labelwise's per-label ROBDD, with LEAF's definitional Tier-1 fast path in front of it so the BDD variable-ordering heuristic cannot decide whether the ~95%-definitional case compiles, is the right eventual destination and two of three judges ranked it first on merit. It cannot be the first commit, for four reasons that the work above happens to retire: its canonical index — which selects the *answer*, since R2's greedy irredundance yields lookbackJoin at 4, 5, or 7 constraints depending on drop order — is currently derived from Supply-hash orders, and the prescribed re-anchor is unavailable and unbudgeted; its drift is uncomputable from anything on disk, and its published figure of 17 was derived from emitted residuals when 133/199 constrained signatures are annotated and never reach `solve` at all (Subst.scala:655 emits the declared type; only :805 calls `solve`), which is why one of its 17 (`rowgroups`) is structurally impossible; its subset-only residual provably cannot reproduce `reduce`'s case-2 splice, whose fingerprint is visible on 10 baseline signatures; and complete consistency checking is strictly *more* rejecting than a solver with no completeness theorem, while `mkSimplified` calls `solve` on `extinct` at :1349 specifically to force failure. Stage 0's instrumentation boot, the model oracle, the determinism inventory and the canonicity fixes are all prerequisites it needs anyway. Build them, then decide.

### 7.2 Why this one

**Because one measured five-line diff removes every cliff anyone has found, and every alternative rests on numbers computed from the wrong artefact.**

The decisive asymmetry in this packet is evidential. The branch-only CSE cut was measured on a real build *by an adversary trying to kill the proposal it came from* — CoStar8 175.68s → 0.06s, RowStress8 >138s → 0.12s, RowStress20 0.13s, the repo's own `join example` property green, concrete-row inference preserved, a 14-line browse diff. Meanwhile all three full-replacement designs were wounded or killed by the same error: LEAF's "9.3ms, 13 pullbacks, max 42 atoms, 95% definitional", Labelwise's "17 signatures move", and Definitional Rows' "96.5% FD, 20 constraints across 14 entries" were **all computed by replaying a pipeline over `tracker/g1-baseline/ei`**, which is the wrong population twice over — two-thirds of those signatures are annotations `solve` never sees, and `reduce` case 2 splices partitions drawn from the *saturated* queue, so even for the inferred third the emitted residual is not a function of `solve`'s input alone. Two of the three had their foundational contract falsified live with a dozen lines of stdlib `Has`. When three independent designs converge on the same measurement error, the correct response is to go get the measurement (Stage 0) before committing to a thousand-line rewrite, not to pick whichever wrong number is smallest.

**Because the diagnosis is confirmed three times over and points at one branch, not one rule.** The "minimal" proposal traced it by reading guards; LEAF arrived at it from the opposite direction (co-star is definitional, so leaf expansion makes it free — the single best analytical result in the field); Definitional Rows named the structural cause (`substitution` at :1047 and `commonSubexpression` at :1060 are exact inverses, both unconditional, both inside one saturation — the textbook non-terminating configuration, which is why the 240-line header carries no measure); and the repo's own `gen-row-overlap.py` docstring names Constraints.scala:1076 by line number. Four independent derivations, one culprit. What none of the proposals got right was the *granularity*: deleting the rule breaks `join`, deleting the minting branch does not.

**Because "restrict the language" is settled, and settled negatively, with data.** The ticket demands it be considered; Definitional Rows' Part 0 considered it properly and its auditor could not break the result. `lacks` covers 0 of 345 residuals; containment + disjointness covers 56/345 and 39/199 signatures, leaving 160 signatures needing weaker types and every caller rewritten; Rose's binary combination is expressively complete by re-association but exactly as NP-hard, because the monotone 1-in-3-SAT witness `L <- (x,u), u <- (y,z)` lives entirely in the arity-2 fragment, and it costs 171 new existential binders across 88 signatures; promoting `Has`/`RUnion2`/`RUnion3` to primitives restricts nothing (177 raw `<-` occurrences at the surface against 47 alias uses, and 289/345 residuals need the completeness half the aliases cannot express). The dichotomy is the durable finding of this whole exercise: *any vocabulary that keeps completeness is as NP-hard as `<-`; any vocabulary that drops it covers under 20% of the constrained corpus.* There is no 1447/1447 vocabulary fragment. That option should be closed permanently in the ticket, with the numbers, so nobody reopens it.

**Because "do nothing but make it diagnose" is not merely weak, it is provably unavailable — and Stage 3 is what makes a budget honest.** The "diagnose" proposal's own auditor reverse-engineered its measure (co-star W = 2^m − m − 2 reproduces all five published figures) and applied it to the PartStar family the repo already generates and already timed: PartStar6 scores W = 63 at a **measured 9.16s** against a claimed corpus maximum of 61. There is no separating K — above 63 the fence admits a nine-second compile and PartStar7 at ~126 admits a projected two-minute one; at or below 63 it rejects `(<=)`/`(>=)` and fails criterion 1. And the structural reason generalises past that one measure to *any* pre-flight predictor: the pathology is a property of the search, not of the input's shape. The honest version of the diagnose option — no shape certificate, just a hard work budget — is what I have absorbed as Stage 5, but it only becomes calibratable **after** the cut. Before the cut, the budget *is* the fix, and its limit would have to sit below RowStress N=7 (10.94s) and PartStar6 (9.16s), i.e. it would reject programs that compile today. After the cut, nothing anyone has measured comes within orders of magnitude of it. That inversion is the argument for this ordering and against the ticket's own fallback.

**Because the expensive half is unavoidable and is not a reason to prefer the rewrite.** Criterion 3 costs 600-900 lines of ordering work against a ten-site leak inventory *whichever* design ships — Labelwise pays it, LEAF pays it, the diagnose proposal pays it in its Stage 2, and it is the majority of every effort estimate here. No auditor marked any effort estimate realistic. So the choice is not "cheap patch versus principled rewrite"; it is "pay the shared determinism bill on top of a five-line fix whose blast radius is 2 signatures, or on top of a 1750-line rewrite whose blast radius is uncomputable". Given that the repo's own gate says *"A red here is a Decision 9 stop — explain it or revert it; never re-cut the baseline to make it green"*, and given that a large re-cut is exactly where a real regression hides inside an expected diff, the smaller blast radius is not a preference. It is the only one a reviewer can actually verify.

### 7.3 Ranked against effort — including the two options the ticket demands

| option | effort | verdict |
|---|---|---|
| RECOMMENDED — Non-generative CSE (branch cut) + cano | 5-7 weeks total, but front-loaded value: the cliff is gone in week 2. Stage 0 in | TAKE. The only option whose headline change is measured rath |
| Labelwise — per-label ROBDD decision procedure with  | ~950 new lines, ~800 deleted from Constraints.scala, TestConstraints largely rew | RIGHT DESTINATION, WRONG FIRST STEP. Its canonical index cur |
| LEAF — leaf-expansion atom form with pullback refine | ~700-line new solver, ~658 lines deleted, ~400 lines of tests deleted and ~250 a | MINE FOR PARTS, DO NOT SHIP. Foundational contract broken li |
| RESTRICT THE LANGUAGE (ticket-mandated option, two r | Reading A, restrict the vocabulary: LOW to evaluate (Part 0 already did it, well | REJECT, AND CLOSE IT WITH THE PROOF. Reading B hard-errors o |
| DO NOTHING BUT MAKE IT DIAGNOSE (ticket-mandated opt | Advertised as cheap — a ~300-line pre-flight certificate, 2 days — but that fram | REJECT AS PRIMARY, ABSORB THE BACKSTOP HALF. A hard-error bu |

### 7.4 Staged plan, each stage leaving the repo green

**Stage 0 — Instrumentation boot (no shipped change)**

- *Work*: Log at every solve call site (Subst.scala:805 inferImplicitBindingTypes, :1067 trySolveOn, :1349 mkSimplified-on-extinct): (1) the ACTUAL input constraint list, (2) every destructive improvement with its Inference provenance from unify/instantiate/makeEmpty/makeConcrete (Partition.inf already carries it), (3) every firing of reduce's case 2 with the partition it spliced and whether that partition was an input or a derived one. One full 180-file boot (stdlib + core/examples). Widened from the 'restrict' proposal's Step 0 per the LEAF audit, which showed a binding-only log would license nothing.
- *Gate*: Baseline untouched (instrumentation behind a system property, off by default); g1-validate 1447 EQUIVALENT; repl goldens byte-identical; core/test passing. The log must answer three questions before anything else is built: what population does solve actually receive (versus the 199 emitted residuals everyone measured); do the four generative rules contribute any improvement that survives; does reduce case 2 fire on committed output and on DERIVED

**Stage 1 — Canonicity at the root cause**

- *Work*: Type.scala:402 Part.apply — add `case VarT(v) if ts == List(VarT(v)) && ss.isEmpty => Exists(l)` beside the existing ConcreteRho tautology collapse. Subst.scala:1300 NormalPart — add `private val key = (left, concrete, abstrakt.map(_.id).sorted)` and define BOTH equals and hashCode on it (its synthesized hash currently covers loc, so even same-order duplicates with differing locs survive the HashSet-backed distinct at :1345). Do NOT touch Part.equals/Part.hashCode. New tracker/tools/check-canonicalization-diff.py (~60 lines) parsing the browse.txt diff and asserting every removed atom is `x <- (x)` or a permutation of an atom surviving on the same line. Land BEFORE the CSE cut, because the c
- *Gate*: EXACTLY 19 atoms across 12 signatures move, matching the enumeration in baseline_movement, verified mechanically by the new script rather than by eye. Four signatures lose their entire partition list and must be inspected individually. No binder list moves (verified in advance: iso is computed from raw ps before normalPart runs, and all 9 vacuous atoms have universal LHSs). repl goldens byte-identical — no .expected file contains '<-', verified. 

**Stage 2 — The model oracle and property harness (tests only)**

- *Work*: Build the per-label Boolean semantics from the 'decision' proposal as a differential test oracle on top of TestConstraints.scala's existing Valuation/satisfies machinery: one Boolean CSP per mentioned label plus one generic column, exhaustively enumerated for small systems. Four properties: (a) every forced fact the solver applies holds in every model; (b) the retained residual is equivalent to its input on the universals under exhaustive valuation over a small label universe; (c) output is invariant under permutation of the constraint list, of any RHS, and under random renumbering of TypeVar ids; (d) the JoinProbe and RUnion2-over-concrete-relations shapes are fixtures, not incidental. Also
- *Gate*: Zero drift — tests only. The oracle must reproduce the incumbent's answers on `property("join example")` (TestConstraints.scala:491) and on generated small systems including label-bearing ones. This stage exists because the corpus gate is structurally blind to the concrete-label path: a full 129-module boot loads clean with 1447 signatures and no new rejections while `join`'s output schema is gone. Do not proceed to Stage 3 until the oracle can s

**Stage 3 — The cut: make commonSubexpression non-generative**

- *Work*: Constraints.scala:1078-1082 — replace the terminal `else { val z = fresh(...); Set(3 partitions) }` with `Set()`. Keep the `Some(z)` reuse branch and both `rhs1 == rhsCommon` / `rhs2 == rhsCommon` folding branches. Update the rule header to state the new invariant (CSE folds onto existing names only; the RHS set is not closed under intersection) and to record the substitution/CSE inverse-pair diagnosis that explains why no measure was ever written. Nothing else in this commit.
- *Gate*: Performance: gen-row-stress N=8..20 and gen-row-overlap Chain8/Overlap1/Overlap2/OverlapHalf/PartStar4-6/CoStar4-8, one JVM each, all under a wall-clock ceiling (expected <=0.13s; CoStar8 and RowStress8/20 already measured at 0.06-0.13s, PartStar is the one that must be newly measured). Correctness: `join example` green, JoinProbe deduces a={Fst} b={Snd} c={Thd} f={Fst,Snd,Thd}, `join rl rr : Relation (|vl,k,w|)` unchanged, RUnion2-over-concrete-

**Stage 4 — Determinism, against the full ten-site inventory**

- *Work*: Introduce a solver-local rank assigned by first occurrence in a left-to-right walk of the constraint list solve receives (LHS then RHS in list order), with minted variables ranked after all input variables in mint order. NOT source Loc — proven non-injective across instantiations. Apply it at: the PSQ key (:437/:452), reverseTopSort's tie-break (:413), findRHS's bucketing (:580), RHS.toTypes (:341), reduce's abs.toList (Subst.scala:1046), Subst.scala:391's rs.toSet round-trip, and generalize's typeVars(...).toList (:1113-1126). Add a total Order[Partition] and sort every Set[Partition] fold into ++! (Constraints.scala:758, :878, :920, :954, :975) — this class decides unification survivors mi
- *Gate*: ZERO semantic drift: g1-validate 1447 EQUIVALENT. Determinism, two new permanent gates: (a) full corpus boot twice with -Dermine.loadInSeries=false, requiring EQUIVALENT and byte-identical browse.txt — this fails today, so it is a real tripwire; (b) a Supply-offset sweep pre-advancing the global Supply by k=1..8, requiring identical .ei and browse.txt across all k. Stage-2 property (c) green. browse.txt churn is expected and must be attributable 

**Stage 5 — The work budget, as a last resort that never fires**

- *Work*: Add a counter of RULE-APPLICATION ATTEMPTS — one per (u,rhs1) x (v,rhs2) pair examined in learnPartitions (:805), plus one per insert — threaded through solve on SubstEnv (Subst.scala:93, already mutable), compared against a constant read once at class-init. Not a dequeue counter: the per-dequeue cost is the proc.foldLeft all-pairs scan, so a step budget bounds steps and leaves work unbounded. On exhaustion, tml.die through the existing Loc.report path. Calibrate from an instrumented corpus boot: record the per-solve maximum over all 1447 signatures, set the limit at >=50x with a floor, and write both numbers into tracker/PERF-ROADMAP.md. CI assertion fails if the corpus maximum climbs past 
- *Gate*: Never fires on the 180-file corpus, on gen-row-stress N=8..20, or on any gen-row-overlap family. Zero drift. A golden test for the diagnostic text on a synthetic over-budget module, asserting byte-identical output across three runs, both loadInSeries settings, and three Supply offsets. MUST land after Stage 4: before determinism, 'did it exceed' is itself nondeterministic and the diagnostic is a flake rather than a contract.

**Stage 6 — GATED, NOT SCHEDULED: the decision procedure**

- *Work*: Only if Stage 0's log shows the residual is a function of solve's input and the drift is computable. Then: Labelwise's per-label ROBDD (pointwise decomposition, finite-support lemma, straight-line, no fresh variables) with LEAF's definitional Tier-1 leaf-expansion in front of it, so the BDD variable-ordering heuristic — which the proposal itself calls 'the whole ballgame', 264 nodes versus 1,694,084 on the same system under a shuffled order — cannot decide whether the ~95%-definitional case compiles. Reuse Stage 2's oracle as the specification, Stage 4's rank as the canonical index (Loc being unavailable), and Stage 1's canonicity as the residual post-condition.
- *Gate*: Do not open this stage until Stage 0's numbers are published and Stages 1-5 are green. Entry conditions, all currently unmet: a drift set computed from solve's real inputs rather than emitted residuals; a stated answer for reduce case 2 under a subset-only residual; a measured bound on how much more rejecting complete consistency checking is, including on mkSimplified's extinct set; and a re-anchor of the canonical index that does not depend on s


### 7.5 Which .ei signatures move, and why that is deliberate

**Enumerated from `tracker/g1-baseline/browse.txt` this session, independently of every proposal — and the counts correct both the ticket and the proposals.**

**Stage 1 (canonicity) moves exactly 19 atoms across 12 distinct signatures.**

*Nine vacuous `x <- (x)` atoms, one each, in nine signatures:* `count` (Relation.ei), `count_Aggregate` (Relation/Aggregate.ei), `dateRange_Op`, `growthOf10k_Op`, `negate_Op` (Relation/Op.ei), `keyedDrilldown` (Layout/Report.ei), `lookbackJoin`, `maxRowBy`, `minRowBy` (Relation.ei).

*Ten excess duplicate atoms across four signatures:* `drilldownKeyValueTable2` (3 copies of `a2 <- (i,k,r,v)` → 1, so 2 removed), `drilldownPivotTabular` (4 copies of `t <- (k,s,v)` → 1, so 3 removed), `drilldownPivotTabular'` (same, 3 removed), `lookbackJoin` (`j <- (f,k)` twice and `t <- (f,i,r)` twice, 2 removed).

`lookbackJoin` appears in both lists, so the union is **12 distinct signatures, 19 atoms**. This corrects the ticket's "8 signatures carry a vacuous self-constraint" (it is 9) and the "minimal" proposal's "17 atoms" (it is 19; `drilldownKeyValueTable2` carries 3 copies not 2, and `drilldownPivotTabular'` carries 4 not 2).

**Four of the twelve lose their ENTIRE partition list** and are therefore hard `DIFFERENT` under G1Compare's `Exists` branch, which rejects on `constraints.length` — not cosmetic: `count`, `count_Aggregate`, `growthOf10k_Op`, `negate_Op` go from `(b <- (b), Builtin.RelationalComb a) => a b -> a (|Count|)` to `Builtin.RelationalComb a => a b -> a (|Count|)`.

**No binder list moves, and I verified this rather than assuming it.** `val iso = isolated(exts.toSet, ps)` is computed at the top of `mkSimplified` from the raw `ps`, *before* `normalPart` runs, so dropping an atom inside `normalPart` cannot perturb the isolated set or the `exts filterNot (v => iso(v) || am(v))` binder filter. Independently, all nine vacuous atoms have a **universal** LHS — `count`'s `b`, `dateRange_Op`'s `r1`, `lookbackJoin`'s `r` are all `forall`-bound — because an existential-LHS vacuous atom would be classified `extinct` at the `(dumb, extinct)` partition and never printed. This closes the ordering hazard the "diagnose" audit raised, which every proposal either missed or hand-waved.

**Stage 3 (the cut) moves at most 2 further signatures:** `Relation.ei:lookbackJoin` and `Layout/Report.ei:drilldownKeyValueTable2` — measured at *full-rule* deletion granularity, where lookbackJoin went from 13 existentials / 15 atoms to 15 existentials / 11 atoms with a raw RUnion2 shape appearing that is absent from the baseline. At *branch* granularity the browse diff shrinks from 65 lines to 14, so the movement is strictly smaller, but its exact .ei content has **not** been enumerated and must be measured, not predicted. Both signatures already move in Stage 1, so the union across stages is still 12 signatures — unless Stage 3's change to lookbackJoin is a shape change rather than a deletion, in which case it is 12 signatures with one carrying two independent reasons to move. That distinction must be settled by measurement at the Stage 3 gate.

**Stage 4 (determinism) must move ZERO signatures semantically.** Rank ordering changes RHS render order and can change which variable survives unification, but G1Compare matches `Part` right-hand sides by backtracking multiset, so `.ei` stays `EQUIVALENT` through pure reordering. `browse.txt` is different: `g1-diff.sh compare` byte-diffs it and `g1-normalize.py` sorts only *inside* `exists` blocks, not within an atom's parentheses, so churn on a large fraction of the 183 partition-bearing lines is expected and is .ei-invisible. Land Stage 4 alone so that churn is attributable.

**Why this is a deliberate, reviewable change and not drift.** Criteria 1 and 4 are in direct contradiction on the recorded baseline: the baseline *contains* the defects criterion 4 forbids, and `G1Compare` matches by multiset, so removing them necessarily changes those `.ei` files. Something has to move, and the question is only whether the movement is enumerable in advance and checkable by machine. Here it is both. Every one of the 19 atoms is either logically vacuous (`v` is trivially the disjoint union of `{v}` — the solver's own queue already discards these via `isSelfUnification` at Constraints.scala:481, which is proof the author considered them junk) or a verbatim repeat of a constraint that survives on the same line. Neither kind constrains any model. Both exist only because two identified bugs — a missing `VarT` case in `Part.apply` and a `NormalPart` that overrides `equals` without `hashCode` against a HashSet-backed `distinct` — defeated intent the code already expresses.

**Procedural requirement, not optional.** `tracker/tools/g1-validate.sh:49-52` states the project's own rule verbatim: *"A red here is a Decision 9 stop -- explain it or revert it; never re-cut the baseline to make it green."* So the re-cut needs an explicit ticket-owner waiver, and it must be gated by `tracker/tools/check-canonicalization-diff.py`, which parses the browse.txt diff and asserts every removed atom is `x <- (x)` or a permutation of an atom surviving on the same line, and that every remaining hunk is alpha-equal under G1Compare. That script is what makes the re-cut reviewable rather than a rubber stamp, and it is the only defence against the hazard the LEAF audit named: *a real regression can hide inside an expected diff.* It stays in CI permanently.

### 7.6 The honest failure mode

**The diagnostic.** One new hard error, raised through the existing `tml.die` / `Loc.report` path so it carries the source span of the definition being inferred and travels the normal type-error route (the REPL prints it and survives; a batch compile fails):

```
M.e:14:1: error: row constraint solving gave up
  the constraints for this definition did not settle within <N> rule applications
  (<K> live constraints over <V> row variables when the limit was reached)
  add a type signature to this definition: an annotated definition is checked
  against a fixed constraint set instead of accumulating one
  a program that needs a higher limit is very likely an inference bug --
  please file this module against the row solver
```

Every number in it is syntactic — a count of rule-application attempts, a count of live constraints, a count of variables. No timing, no memory figure, no "try again".

**What it counts, and why not what the runner-up counted.** One increment per `(u,rhs1) × (v,rhs2)` pair examined in `learnPartitions` (Constraints.scala:805), plus one per `insert`. Not dequeues. The "minimal" proposal's fuel counted `incorporateAll` dequeues, and its auditor's objection is correct and fatal to that formulation: the cost of a single dequeue *is* the `proc.foldLeft` all-pairs scan, so a dequeue budget bounds steps while leaving work unbounded — one dequeue against a large `proc` can run arbitrarily long and never trip the counter. Pair examinations are the actual unit of work and are still a purely syntactic measure.

**When it fires.** Never on the 180-file corpus. Never on `gen-row-stress.py` at N=8..20. Never on any `gen-row-overlap.py` family — Chain8, Overlap1/2, OverlapHalf, PartStar4-6, CoStar4-8 — after Stage 3, where every one is measured or predicted at ≤0.13s, orders of magnitude below any limit worth setting. It exists solely as a backstop for `splitConcrete` + `resolution` + `substitution` on concrete-field-rich input, for which I have no decreasing measure and claim none. The calibration is a full instrumented boot: record the per-`solve` maximum over all 1447 signatures, set the limit at ≥50× that with a floor, write both numbers into `tracker/PERF-ROADMAP.md`, and add a CI assertion that fails if the corpus maximum ever climbs past 20% of the limit, so headroom erosion is caught before a user hits the error.

**Why the same program always gets the same answer.** Three reasons, in order of importance. First, the counter measures a syntactic quantity, not wall-clock and not memory, so it cannot vary with machine speed, load, or GC. Second — and this is why the budget is Stage 5 and not Stage 1 — after Stage 4 the step *sequence* for a given source is fixed: the queue key is a rank-based total order on distinct partitions, so equal keys imply identical partitions and the existing dedup collapses them, making the queue a canonical sorted sequence; every `Set[Partition]` fold into `++!` is sorted by that same order, closing the one remaining path by which fold order reached a decision (`insert`'s mid-fold `rhsLookup`, which picks the survivor of a common-partition unification); and the rank comes from occurrence position in the constraint list `solve` receives, not from a Supply-drawn id. So the same source trips the limit at the same attempt number on every thread schedule, at every Supply offset, and under both `loadInSeries` settings. Third, on exhaustion `solve` **raises**. It has no path that returns a partially-saturated queue; `reduce` is never reached; no unsolved constraint can leak into an inferred type. A definition's type is therefore never a function of how many steps the solver got through — typing stays total, and which of "has a type" or "is an error" holds depends only on the source text.

That last property is the precise thing commit 04c2308 (Dan Doel, 2018, `features/limit-row-solving`) lacked: its `Eternity` exception returned the constraint set UNSOLVED, so residuals leaked into inferred types and typing became a function of how long the solver ran. The distinction is not rhetorical — it is the difference between a diagnostic and a corruption. Note also the ordering constraint it implies is non-negotiable: **the budget must land after the determinism work, never before.** Before Stage 4, "did it exceed" is itself nondeterministic and the error is a flake, not a contract.

**The honest part.** After Stage 3 this error fires on nothing anyone has measured, which means it ships **untested in production** and its constant is an extrapolation from a corpus where 105 of 129 modules produce zero partition constraints. So the failure mode of the failure mode is this: a legitimate user program — most plausibly a concrete-label-rich one, since that is the path the corpus cannot see and the path where `resolution` and `splitConcrete` still mint — trips a limit calibrated against quiet code and gets a hard error where it previously got a slow answer. That is a real behaviour change for real programs, and it is the deliberate trade. There is no `-D` flag to raise it in the shipping build, because a raisable limit would make a module's typability a function of build configuration and would make an `.ei` produced under a raised budget indistinguishable from one produced under the default; a *lowerable* flag for testing is fine and should exist. And to be explicit about what is not claimed: this is a bound, not a theorem. Stage 3 removes the one engine that all three known divergent families use; it does not prove no fourth family exists. Somebody can very likely construct a concrete-field-rich program that drives `resolution` and `substitution` hard, and the answer to that program is this error rather than a fix.

### 7.7 Ideas absorbed from the designs that were not chosen

- **From 'decision' (Labelwise) — the per-label Boolean semantics, as the ACCEPTANCE ORACLE rather than as the shipped solver.** Satisfaction is pointwise in the label, so a system decomposes into one small Boolean CSP per mentioned label plus one generic column, and small instances are exhaustively enumerable over TestConstraints.scala's existing Valuation/satisfies machinery. This is the single most valuable graft, because it is the exact instrument that would have caught the regression that killed the proposal it is grafted into: a full 129-module boot with CSE deleted loads clean with 1447 signatures and no new rejections while `join rl rr` has lost its output schema and the repo's own test is red. All 345 corpus residuals are label-free — permanently, not accidentally — so the corpus gate is structurally blind to the concrete-label path, and no amount of green makes it evidence.
- **From 'decision' — the finite-support lemma as the reason the oracle is faithful and not merely a relaxation.** The all-zero row satisfies every constraint at a label outside the mentioned set, so any per-label choice function is realisable by finite rows and existential projection decomposes per label. Its auditor tried to break this and reports 'correct and I could not break them'. Without it, a per-label oracle would be testing a different problem.
- **From 'definitional' (LEAF) — the observation that the definitional fragment is FREE, and the flatness lemma that proves it.** Co-star is definitional (distinct LHSs, acyclic), so a leaf-expansion procedure costs nothing on it while the incumbent costs 175.68s. That is the sharpest single diagnostic result in the packet and it explains WHY the minting branch is the whole cliff rather than merely correlating with it. It is also the front end Stage 6 needs, so that Labelwise's BDD variable-ordering heuristic — 264 nodes versus 1,694,084 on the same system under a shuffled order, by its own measurement — cannot decide whether the ~95%-definitional case compiles.
- **From 'definitional' (LEAF) — pullback refinement as the correct formalisation of 'name the equated remainders'.** g[p][q] := rho(p) INTERSECT rho(q) with simultaneous substitution is model-BIJECTIVE, so it reduces a multi-definition system INTO the definitional fragment rather than escaping to a different algorithm. Keep it for Stage 6; it is the right way to handle the 7 genuinely non-definitional corpus signatures.
- **From 'definitional' (LEAF) — validation against a brute-force model oracle at scale as a methodology, not just a test.** 50,000 random systems with zero soundness or completeness deviations is the right standard of evidence for a solver change, and it is the standard every proposal here failed to meet on the corpus because the corpus cannot supply it.
- **From 'restrict' (Definitional Rows) — Part 0's vocabulary dichotomy, as a permanent negative result to record in the ticket.** Any vocabulary keeping completeness is as NP-hard as `<-` (the monotone 1-in-3-SAT witness `L <- (x,u), u <- (y,z)` lives entirely in the arity-2 fragment); any vocabulary dropping it covers under 20% of the constrained corpus. lacks 0/345, containment+disjointness 56/345 and 39/199 signatures, Rose's binary combination costing 171 new binders across 88 signatures, alias-promotion restricting nothing against 177 raw `<-` occurrences. Its auditor could not break it. This closes the ticket's own mandated option with data instead of opinion.
- **From 'restrict' — the Step 0 instrumentation gate, widened per the LEAF audit.** 'Do not start the implementation before running this' is the right instinct and the right sequencing; the original formulation (log bindings with Inference provenance) was too narrow, because learned partitions also reach the emitted type through reduce's case-2 splice without ever touching unify/instantiate/makeEmpty/makeConcrete. Widened to log solve's actual inputs, all destructive improvements with provenance, and every case-2 firing with its source.
- **From 'restrict' — the structural diagnosis that `substitution` (:1047) and `commonSubexpression` (:1060) are exact inverses, both unconditional, both inside one saturation.** A rewrite system containing a rule and its own inverse has no terminating order. That is why the 240-line header carries no measure, and it belongs in the comment that replaces the deleted block, because it says which direction to orient and why the surviving folding branches are safe.
- **From 'restrict' — the proof that source `Loc` is non-injective across instantiations**, which resolves a cross-audit contradiction neither auditor could see alone. `refresh` uses `v.loc.instantiatedBy(l)`, `Loc.instantiatedBy(l) = orElse(l)` (Locations.scala:17), and `unbind`/`unfurl` refresh at the Forall's own loc, so RowStress7's 21 row variables occupy 3 distinct Locs. The Labelwise auditor prescribed Loc-anchoring as the fix for that design's determinism hole; this proves it unavailable, leaving occurrence-rank as the only candidate.
- **From 'restrict' — the termination measure mu = (unbound variables, live constraints) under lexicographic order on N^2**, the only fully sound measure anyone offered and the one its auditor endorsed outright ('None material — this is the part of the proposal that holds up'). Not usable here, since splitConcrete and resolution still mint, but it is the shape any future rule set should be built to satisfy.
- **From 'diagnose' — the backstop half, and only the backstop half.** A hard-error budget on a syntactic measure with no partial return is right; a pre-flight certificate that predicts cost from input shape is not, and cannot be made to work (PartStar6 scores W=63 at a measured 9.16s against a corpus max of 61 — no separating threshold exists). Absorbed as Stage 5, re-based to count work rather than steps.
- **From 'diagnose' — the mkSimplified isolated/extinct interaction warning.** Raised as an objection to canonicity pruning; I checked it and it clears (iso is computed from raw ps before normalPart runs, and all 9 vacuous atoms have universal LHSs), but it was the right question and no other proposal asked it.
- **From 'diagnose' — the Set[Partition] fold-order leak class** (++! at Constraints.scala:758, :878, :920, :954, :975, where insert's mid-fold rhsLookup at :504-508 picks the survivor of a common-partition unification that instantiate then writes into the global substitution at :877). It appears in exactly one of the five proposals' inventories and is immune to a comparator swap, so any determinism plan that omits it is silently incomplete.
- **From 'minimal' — the root-cause diagnoses of both canonicity defects**, which are correct, minimal, and reusable by every design: the missing VarT tautology case in Part.apply beside the existing ConcreteRho one, and NormalPart overriding equals without hashCode against a HashSet-backed distinct. Corrected per the 'restrict' audit: the NormalPart fix must be on NormalPart itself, not on Part.equals/hashCode, which normal.distinct never consults and whose global equality has a large blast radius.
- **From 'minimal' — `tracker/tools/check-canonicalization-diff.py`**, a script that parses the browse.txt diff and asserts every removed atom is `x <- (x)` or a permutation of an atom surviving on the same line. This is what makes a mandatory baseline re-cut reviewable rather than a rubber stamp, and it is the only defence against the hazard the LEAF audit named: a real regression hiding inside an expected diff.
- **From 'minimal' — the enumeration of every row-constraint rejection channel in the checker** (the die sites; isTrivialConstraint on ds, which never reaches solve; ambiguity rejection being class-constraint-only; entail/entails guarded by isClassConstraint at Subst.scala:398 with subsumeType discarding the result at :536; skolem escape via instantiateType). It is the map any weakening change needs, and it is the reason 'a weaker solver cannot reject more' is even arguable.

### 7.8 Open questions this recommendation does not close

**Read §8.1 first**: the single most important caveat is methodological. Every
drift figure in this section — and in §4.1 of this ticket — was computed from
**emitted residuals** (`tracker/g1-baseline/ei` and `browse.txt`), which is the
wrong population for reasoning about a *solver* change: two thirds of those
signatures are annotations that `solve` never sees, and `reduce` (`Subst.scala:1037`)
splices partitions drawn from the **saturated** queue, so the emitted residual is
not a function of `solve`'s input alone. Those numbers are sound for the question
they were asked (what a canonicaliser does to *printed output*, which is what
criterion 4 governs) and unsound for predicting what a rule change does to the
`.ei`. That is precisely why Stage 0 exists and why it gates everything else.

1. **Does the branch-only cut kill PartStar?** This is the largest unmeasured risk in the recommendation. PartStar6 costs a MEASURED 9.16s (gen-row-overlap.py's own docstring) and is a third divergent family absent from the ticket's evidence block. Full-rule deletion was measured at PartStar6 0.05s; the branch-only variant was measured only on CoStar8 and RowStress8. Structurally it should be inert — PartStar's intersections are proper subsets of both sides with no pre-existing name, so neither folding branch nor the reuse branch fires — but that is a prediction. Measure it at the Stage 3 gate before anything is claimed about criterion 5.
2. **What does Stage 3 actually do to `lookbackJoin`'s .ei?** At full-rule granularity it went 13 existentials/15 atoms → 15 existentials/11 atoms with a raw RUnion2 shape appearing that is absent from the baseline — a shape change, not a deletion. At branch granularity the browse diff is 14 lines rather than 65, but the .ei content is unenumerated. If it is still a shape change rather than a deletion, `check-canonicalization-diff.py` will reject it and the waiver has to cover a second, different kind of movement.
3. **What does `solve` actually receive?** Every drift figure in this packet — including the ones in my own baseline_movement section for Stage 3 — was computed from emitted residuals. 133 of 199 constrained signatures are annotated and never reach `solve` (Subst.scala:655 emits `substType(etm(e.v))`, the declared type; only :805 calls `solve`). The real inputs are pre-generalization, per-binding-group constraint sets that nobody has measured. Until Stage 0's log exists, no drift estimate here or in any proposal is trustworthy.
4. **Does `reduce` case 2 splice DERIVED partitions into committed output?** It folds over `ps = q.expand.toList`, the saturated queue, and every variable minted by a generative rule is `Ambiguous(Free)`. The fingerprint that it has run is visible on 10 baseline signatures with an existential LHS occurring in no RHS (bottomKBy, lookbackJoin, rename', replaceColumn, topKBy, drilldownKeyValueTable2, drilldownPivotTabular, drilldownPivotTabular', keyedDrilldown, softRelation). If it splices derived partitions, then Stage 3 — which changes which partitions are derived — can move residuals in ways not predicted here, and any future subset-only residual is not expressible at all.
5. **Is the `Set[Partition]` fold-order leak observable in emitted bytes?** The mechanism is stated precisely (`insert` consults `rhsLookup` mid-fold at :504-508; the first same-RHS partition to land wins the common-partition unification; `instantiate` writes that survivor into the global substitution at :877) but never measured. If `insert`'s dedup washes it out in practice, Stage 4 shrinks considerably. If it does not, it is the single largest piece of that stage and it is immune to a comparator swap.
6. **Is `-Dermine.loadInSeries` removable at all?** The 'restrict' audit found a PRE-EXISTING parallel-load failure unrelated to the row solver — a bare `bin/ermine` run died with `modules/Field.e:22:1: error: failed to unify kind * with kind !a` / `Unable to load Prelude and Layout`, while the same run under loadInSeries=true succeeded. So the double-run determinism gate may fail for reasons no row-solver work addresses, and the flag may not be retirable regardless.
7. **Does the pretty-printer assign fresh names independently of Supply order?** browse.txt renders variable NAMES. g1-diff.sh attributes today's cross-run drift specifically to 'the solver's id-hash queue', but if the printer is independently id-ordered then Stage 4's byte-identity gate fails for a cause outside its scope and deterministic printer naming becomes a prerequisite.
8. **Is `RHS.toTypes` / `PQueue.toType` live or dead?** The 'minimal' proposal calls `PQueue.toType` unreferenced dead code and proposes deleting both; the 'diagnose' audit says `RHS.toTypes` at :341 is live and reaches binder order through `typeVars(cs)`. Both cannot be right about the same path. Resolve by reference search before deleting anything; the safe move is to fix the ordering rather than delete.
9. **Can the cut lose an ERROR?** Some unsatisfiable systems may be refutable only through an intersection that no longer gets a name. Nobody constructed such a case and nobody ruled one out. The direction of the loss is benign for acceptance (a missed refutation means a more general type, never a spurious rejection, provided the rejection channels really are monotone in the derived set) but it is a genuine loss of error detection, and `mkSimplified` calls `solve` on `extinct` at :1349 precisely to force failure on unsatisfiable sets it is about to discard.
10. **Is moving `resolution`'s `fresh` draw safe?** Moving it from :1030 to after the `tops.isEmpty || bots.isEmpty` bail at :1034 changes global Supply consumption, hence every subsequent id, hence the CURRENT baseline. It must land with or after Stage 4, never before, and its own drift must be measured separately.
11. **Does the work-budget constant survive real user code?** The corpus is quiet — 105 of 129 modules produce zero partition constraints — so the observed maximum may be a poor predictor of legitimate user programs. A 50x margin plus a 20%-headroom CI assertion is the guard, but a real program that legitimately needs more gets a hard error where it previously got a slow answer.
12. **Is `mkSimplified`'s second `solve` on `extinct` (Subst.scala:1349) affected?** It is DESTRUCTIVE, not merely a satisfiability check: `q.expand` runs unify/makeEmpty/makeConcrete and `reduce` itself calls `instantiateType`. Any change to solver strength changes what it does to variables that remain in the retained part, and that happens after the residual is printed, so no drift enumeration can see it.
13. **Are the row-constraint rejection channels really monotone in the derived set?** The 'minimal' proposal enumerated them by reading — the solver's own `die` sites, `isTrivialConstraint` on `ds` (which never reach solve), ambiguity rejection (class constraints only), `entail`/`entails` guarded by `isClassConstraint` at Subst.scala:398 with `subsumeType` discarding the result at :536, and skolem escape. The enumeration is careful and I could not fault it, but it was produced by reading rather than by exhaustive search, and the whole 'a weaker solver cannot reject more' argument rests on it.
14. **Can any eventual decision procedure reproduce `reduce` case 2?** Labelwise's subset-only residual provably cannot emit an RHS absent from the input. If case 2 is load-bearing on committed output, that design needs a synthesis capability it deliberately excludes, and Stage 6's entry conditions cannot be met as currently framed.
15. **What is the true FD (definitional) rate on solve's real inputs?** The 96.5% figure and LEAF's '95% definitional, 13 pullbacks, max 42 atoms' were both measured on residuals. Family A is provably NOT definitional (N-1 variables carry two definitions, because left-nesting unifies each join's result with the next call's input), so pre-solve violations demonstrably exist. If they are pervasive, the definitional-fast-path argument for Stage 6 is much weaker than it appears.

### 7.9 Stage 0 results — what `solve` actually receives

Instrumentation: `core/.../RowTrace.scala` plus logging in `solve` and `reduce`,
behind `-Dermine.rowTrace=<path>`, **inert when the property is absent** (the log
argument is by-name and never forced; no file is opened). The three `solve` call
sites are tagged `inferImplicitBindingTypes`, `trySolveOn`,
`mkSimplified-extinct`. Provenance comes from `Partition.inf`: `None` means an
input partition (`PQueue.build` uses the two-argument constructor), `Some(rule)`
means a rule derived it. `Partition.equals`/`hashCode` ignore `inf`, so the
provenance split added for this measurement is provably behaviour-neutral.

Figures below are **one clean 129-module inference boot** (`useInterface=false`,
`loadInSeries=true`). Each example file re-boots the closure, so whole-corpus raw
counts over-represent stdlib sites; where examples are quoted it says so.

**Q1 — what population does `solve` receive?**

| | |
|---|---:|
| `solve` calls in one boot | 54,199 |
| … carrying at least one row constraint | **383 (0.71%)** |
| … carrying none — pure overhead | 53,816 |
| by site | `trySolveOn` 292, `inferImplicitBindingTypes` 80, `mkSimplified-extinct` 11 |
| input constraints per call | 1:230, 2:35, 3:86, 4:14, 5:5, 6:3, 7:2, 9:5, 13:2, 15:1 |
| mean / max | 1.98 / 15 |
| inputs carrying a concrete label | **0 of 383** |

Two corrections to the received picture, in opposite directions. The population
is **larger** than the 199 emitted constrained signatures — `solve` runs 383
non-trivial times per boot — so residual-derived counts undercount the work. But
on the concrete-label axis the emitted residuals were **not** misleading for the
stdlib: zero of 383 inputs carry a concrete label, matching the zero in the 345
emitted constraints. Concrete labels enter only through `core/examples`, where
they reach 39% of inputs. And 98.6% of all `solve` calls carry nothing at all,
which is worth knowing before anyone optimises the solver rather than its
call sites.

**Q2 — do the four generative rules contribute?**

| | |
|---|---:|
| calls where saturation grew the partition set | 104 of 383 |
| partitions in → after saturation | 735 → 1,056 |
| derived | 390 |
| by rule | `CommonSubexpression` 263, `Substitution` 114, `Cancellation` 13 |

**`resolution`, `splitConcrete` and `disjunction` never fire once in the entire
stdlib boot.** Of the four generative rules only common-subexpression is live,
and it accounts for all 263 generative derivations. That is a stronger statement
than the ticket previously made from residuals alone, and it is the empirical
case for targeting exactly that rule.

**Q3 — does `reduce` case 2 splice derived partitions into committed output?**

**Yes.** This is the question that gates everything, and the answer is
unambiguous:

| | |
|---|---:|
| splice firings | 225 |
| … that changed the committed output | **225 (all of them)** |
| … that spliced a **derived** partition | **121** |
| of those, from `CommonSubexpression` | **65** |
| provenance of effective splices | INPUT 104, CommonSubexpression 65, Substitution 45, Cancellation 11 |

So the emitted residual is **not** a function of `solve`'s input: 121 partitions
per boot that no user wrote are spliced into committed output, in twelve named
modules (`Relation/Predicate.e`, `Relation.e`, `Layout/Report.e`,
`Relation/Op.e`). Every drift figure computed from `tracker/g1-baseline/ei` —
including §4.1 of this ticket — is therefore measuring an artefact that depends
on the saturation, not on the input. Stage 0's purpose was to establish whether
that was a real effect or a theoretical worry. It is real.

**The measurement the recommendation turns on.** `commonSubexpression` has three
branches: reuse an existing name, fold onto the other constraint's own left-hand
variable, or **mint a fresh variable**. §7.1 proposes cutting only the third. To
find out whether that branch's output ever survives, the minting branch was
given a distinct provenance tag (`CommonSubexpressionMint`); `Inference` is never
inspected and `Partition.equals`/`hashCode` ignore it, so this is
behaviour-neutral — and the re-run confirms it, reproducing all of 383 / 735 →
1,056 / 390 / 225 / 121 exactly.

| CSE derivations in one boot | 263 |
|---|---:|
| from the reuse and folding branches (**kept**) | 237 |
| from the fresh-minting branch (**cut**) | **26** |

| CSE splices that changed committed output | 65 |
|---|---:|
| from the kept branches | 42 |
| from the minting branch | **23** |

**So the cut is not free.** Twenty-three partitions per boot that reach committed
output come from precisely the branch §7.1 removes. The proposal's premise —
that common-subexpression's output is discarded — is false for those 23. That
does not sink the recommendation, but it converts "the corpus already throws its
output away" from an argument into a hypothesis with a number attached, and
Stage 3 must be gated on what those 23 do to the emitted `.ei` rather than on the
assumption that they do nothing.

**What Stage 0 licenses.**
1. Target `commonSubexpression` and only it — `resolution`, `splitConcrete` and
   `disjunction` are provably dead on this corpus.
2. Do **not** compute drift from `tracker/g1-baseline/ei`. 121 derived partitions
   per boot are spliced into committed output; the residual is not a function of
   the input. Any before/after comparison must be a real build.
3. Treat the minting-branch cut as a change with 23 measured contact points, not
   as a no-op.

---


### 7.10 The cut, BUILT and VERIFIED — and the recommendation reversed twice

Stage 0's gate was met, so the cut was implemented behind
`-Dermine.genRules=all|cut|nongen` (read once at class-init; **`all` is the default
and is bit-identical to the shipped compiler**). `cut` disables only
`commonSubexpression`'s fresh-minting branch. `nongen` additionally disables
`splitConcrete`'s minting and `resolution` entirely — the fully non-generative
calculus `Canonical.lean` proves terminating.

**The cliff, one JVM per module**

| module | `all` | `cut` | `nongen` |
|---|---:|---:|---:|
| CoStar7 | 5.79s | 0.05s | 0.05s |
| CoStar8 | **156.18s** | **0.04s** | 0.05s |
| PartStar6 | 8.86s | 0.04s | 0.06s |
| RowStress7 | 11.19s | 0.08s | 0.08s |
| RowStress8 | **277.27s** | **0.11s** | 0.15s |

**Types of programs that compile — every difference is semantically null**

| corpus | textual diffs vs `all` | semantically equivalent |
|---|---:|---:|
| stdlib boot, 1447 signatures | 2 (`lookbackJoin`, `drilldownKeyValueTable2`) | **2 / 2** |
| examples, 1581 entries (`cut`) | 26 | **26 / 26** |
| examples, 1581 entries (`nongen`) | 37 | **37 / 37** |

Equivalence is decided exactly, not sampled: satisfaction is pointwise in the
label (`Basic.sat_iff_forall_label`, both directions, no hypothesis), and
`LabelClass` shows a label matters only through its signature, so one
representative label per class suffices. Both directions are enumerated over the
shared free variables with existentials projected away. The checker was validated
by a planted perturbation — dropping a part from a constraint — which it
correctly reports as DIFFERS. `lookbackJoin` drops from 15 constraints to 10 and
the 10 **entail the 15**; the removed constraints were redundant.

**Programs that must be REJECTED — `core/examples/shouldfail/`, 40 cases**

| mode | rejected | soundness regressions | message changes |
|---|---:|---:|---:|
| `all` | 40/40 | — | baseline |
| **`cut`** | **40/40** | **0** | **0** |
| `nongen` | 35/40 | **5** | 0 |

`cut` matches the shipped compiler on every case, verdict *and* message.
`nongen` silently accepts five ill-typed programs: `der06`, `der07`, `der08`
(duplicated-field contradictions visible only through DERIVED constraints),
`inc08`, `mis02`. Independently re-verified: `der06` is rejected under `all` and
`cut` with `Fields appear twice in row: Set(Der06.b)` and **compiles clean under
`nongen`**.

**Test suites**

| | `all` | `cut` | `nongen` |
|---|---|---|---|
| `Constraints.join example` | passes | **passes** | **FALSIFIED** |
| `core/test` | 903/904 | 903/904 | 898/904 |
| `repl-smoke` | 4/4 | 4/4 | 4/4 |

(The extra `nongen` failures in a full `core/test` run were a confound: the
should-fail corpus was being written into `core/examples/` while that suite ran,
changing the file count. Isolated with `testOnly TestConstraints`.)

### 7.11 RECOMMENDATION: `cut`, not `nongen`

`nongen` is the theoretically prettier object — it is the one with a termination
proof — but it is **unsound**: 5 lost refutations and a falsified test. That trade
is not available. `cut` achieves the identical speedup with identical semantics
and identical error behaviour.

**Two corrections this section makes to earlier claims in this ticket.**

1. §7.9 reported that `splitConcrete` and `resolution` never fire. That was
   measured on the **boot closure only**. `splitConcrete` fires 42 times across
   `core/examples`, and it is **load-bearing for error detection** — disabling it
   is precisely why `nongen` loses refutations. It must not be removed.
2. `cut` and `nongen` are **not** interchangeable. They agree on the boot closure
   and differ on 23 example signatures (equivalent, but not identical output).

**What remains open.** `cut` has no termination proof and cannot have one while
`splitConcrete` and `resolution` still mint — and the should-fail corpus now
proves they must stay. The 40-case corpus is a floor, not a ceiling: it is the
ill-typed programs we thought to write.

---

### 7.12 Re-enabling `disjunction`: measured, and rejected

`Constraints.scala` documents a `Disjunction` rule at line 1114 and implements it at
1122, but **all three call sites are commented out** (lines 843, 854, 856). It is the
only rule that performs elimination — "the label is somewhere in `l (+) s`; it is not
in `l`; therefore it is in `s`" — and it is precisely what the solver needs for the
soundness hole of §7.13. So: what happens if we turn it back on?

Measured 2026-09-01, behind a new `-Dermine.disjunction` flag (default `false`, so
shipped behaviour is unchanged).

| | shipped (`all`) | `all+disj` | `cut+disj` |
|---|---|---|---|
| `unsound01` keyed halves | ACCEPTED (bug) | REFUTED | REFUTED |
| `unsound02` three-way shard | ACCEPTED (bug) | REFUTED | REFUTED |
| `good` (satisfiable control) | ACCEPTED | ACCEPTED | ACCEPTED |
| four ground witnesses, dup control | REFUTED | REFUTED | REFUTED |
| **`Constraints.join example`** (satisfiable) | ACCEPTED, instant | **no termination** | **no termination** |

The rule does buy the refutations. The price is that `join example` — five partitions
over six variables, from the project's own `TestConstraints.scala`, and *satisfiable* —
ran 3.5 minutes without finishing. The standard library is worse: `StackOverflowError`
after 68s, and with `-Xss1g` it burned 13 CPU-minutes without loading one of the 129
boot modules. This is not a cliff that modest programs stay off; it does not get
through the prelude.

**`cut` does not rescue it, and cannot.** The cut works by deleting the one branch that
mints a name for an intersection no existing variable denotes. `disjunction` mints
*unconditionally* at line 1134, before it has decided whether to fire, and mints a
second variable when `absu.size >= 2`; every emission path yields a partition containing
a fresh variable, which is then eligible to feed further disjunction triples. There is
no reuse lookup and no fuel. So `cut+disj` does not compose two mitigations — it removes
minting from one rule and hands it back through another, which the measurement confirms.

Two aggravating factors. The call sites nest a `proc.toList` scan *inside* the existing
fold over `proc`, taking the per-incorporation cost from O(|proc|) rule applications to
O(|proc|²), each of which can mint. And where `commonSubexpression` names *pairwise*
intersections, `disjunction` computes the full three-set Venn decomposition
(`abs1 ∩ abs2 ∩ abs3` and each pairwise difference), reaching the same 2^k meet-semilattice
by more routes at once.

Whoever commented out those three call sites almost certainly hit exactly this.

**Verdict: do not enable `disjunction`.** The flag stays, defaulted off, as the
reproduction.

### 7.13 A soundness hole, and a rule that closes it

**The hole.** Four modules in `core/examples/incomplete/` type-check, load, and export
types whose row constraints have no solution. Default mode, minting on. The minimal one
is vertical sharding — split a ledger's columns into two groups and stamp the key on
each half:

```
t  <- (l, s)                 lt <- ((|accountId|), l)              rt <- ((|accountId|), s)
```

Satisfiable *unless the ledger already carries `accountId`*, in which case the key lands
in `l` or `s` and that half repeats it. `unsound01_keyed_halves.e` makes that mistake
and compiles. Verified independently: `:browse bad` gives `bad : Relation
(|accountId, regionCode|)` with **no constraint context** — the annotation is monomorphic,
so nothing could be deferred; the solver discharged an unsatisfiable set. The four ground
splits (`witness01_*.e`) are each rejected, so the solver refutes every case and accepts
their disjunction. Behaviour is identical under `-Dermine.genRules=cut`: **the hole is
pre-existing, and the cut neither causes nor widens it.**

**Why it escapes.** `lt` and `rt` occur only as partition left-hand sides. With the LHS
otherwise unconstrained, `lt <- ((|accountId|), l)` reads as a *definition* — "let `lt`
be `accountId ⊎ l`" — and is discharged, dropping the disjointness precondition. But
when the LHS is undetermined that precondition is the partition's entire content:
the constraint means exactly `accountId ∉ l`. Nothing in `Constraints.scala` can
represent a negative fact; every rule derives new partitions.

Corpus check: across the shipped stdlib and the pre-existing examples, **0 of 135
partition-LHS occurrences** have an LHS used nowhere else. All 20 instances of the
pattern are in corpora written to probe it. Making the LHS used does close the bug —
but by forcing the rows to be *determined*, which reduces the program to a ground split
the solver already decides. That is a well-formedness restriction, not added reasoning
power.

**The rule.** Project each partition onto one label: at most one part carries it, and
the whole carries it iff some part does. A `ConcreteRho` pins its bit; unit propagation
does the rest. Implemented as `Constraints.labelClash`, called from `Subst.solve` behind
`-Dermine.labelCheck` (default `false`).

On `unsound01` at label `accountId`: `lt <- ((|accountId|), l)` forces `l = 0`, the mirror
constraint forces `s = 0`, and `t <- (l, s)` with `t = 1` needs one of them. Contradiction,
by propagation alone, no search.

*Measured.*

| gate | result |
|---|---|
| 129 stdlib modules, check on | load in **11.11s** vs 11.17s off |
| `core/examples` + `ai` + `shouldfail`, 66 files | output **byte-identical**, 297 lines; 23.05s vs 23.07s |
| `unsound01` | refuted: `Row partitions are unsatisfiable at field 'accountId': the whole contains it but no part does` |
| solver-level probe, 10 cases (`DisjProbe.scala`) | solver wrong on 2/10, label rule wrong on **0/10**, 395 ms |

*Cost on wide schemas* — the regime a real database project lives in. Generated
modules, `n` concrete labels in one row, `p` chained partitions over it. Measured under
`genRules=cut`, so the pre-existing cliff does not contaminate the reading:

| n labels, 1 partition | off | on |   | n=200, p partitions | off | on |
|---|---|---|---|---|---|---|
| 25 | 0.05s | 0.06s | | p=2 | 0.20s | 0.30s |
| 100 | 0.08s | 0.09s | | p=4 | 0.22s | 0.28s |
| 200 | 0.16s | 0.18s | | p=8 | 0.22s | 0.31s |
| 400 | 0.37s | 0.46s | | p=16 | 0.37s | 0.48s |

The overhead grows with the label count and is **flat in the partition count** (~0.1s
across p = 2..16), which is what a per-label loop with no case split should do. Single-shot
timings, so ±50ms of JIT noise; the direction and magnitude are consistent across all
eight points. Worst case measured: +90ms on a module that is nothing but a 400-column row.

Incidentally these runs are also a `cut` data point: at n=200, p=16 the `cut` build
finishes in 0.37s where `all` does not finish inside 120s.

*Why it does not cost generality* — the property `disjunction` lacks:

* **Refutation-only.** It emits no partition and mints no variable, so it cannot feed
  the saturation loop and cannot change any type inferred for an accepted program.
* **Concrete labels only.** It ranges over labels occurring in a `ConcreteRho`, so a
  general helper signature with no concrete instance has nothing to check. The
  `CONTROL general helper, open` probe — the same three constraints as `unsound01`, with
  no instance — is untouched.
* **No case split**, hence linear per label.

*Proved in Lean*, `Rowpartition/LabelProp.lean`, 0 `sorry`, standard axioms only:
`forced_sound` (every derived bit is the bit of every Boolean model), `refuted_unsat`
and `not_refuted_of_sat` (**a satisfiable system is never refuted** — no false
rejections), `forced_mono`, `Unsound01.refuted`/`.unsat`, `Good.models`/`.not_refuted`,
and `Incomplete.unsat_and_not_refuted` — the incompleteness is **mechanized, not
asserted**: a system with no model that propagation provably cannot refute.

*Incomplete by construction, and deliberately.* Propagation never case-splits. Deciding
these Boolean systems in general is Schaefer's one-in-three problem (§1), so no
polynomial propagation is complete unless P = NP. Refusing to search is what makes the
failure mode deterministic — the contract §5 argues for.

*The `incomplete/` corpus, both rule modes.* Run as B1 (default rules, the `gu03+`
star-join probes excluded because they are the corpus's own cliff demonstrations and
take minutes each) and B2 (every file, under `genRules=cut`, which removes the cliff).
Compared by successfully-imported module, not by a hand parse:

| | B1 (`all`) | B2 (`cut`) |
|---|---|---|
| modules loading, check off | 19 | 26 |
| modules loading, check on | 15 | 22 |
| **newly failing** | `Unsound01`–`Unsound04` | `Unsound01`–`Unsound04` |
| **newly loading** | none | none |
| total diff hunks | 2 | 2 |

So under both rule modes the check rejects exactly the four known-unsound modules and
nothing else. **All four soundness bugs are closed; no program that loaded before stops
loading.**

The second hunk in each is a *diagnostic* change, not a verdict change:
`unsound05_lhs_used.e` and `witness03_grounded_call.e` were already rejected, and are
still rejected, but now by the label check rather than by the later duplicate-field
test.

*Blame.* As first written the check died at `tml`, which for a module-level binding is
the module header — `witness03` reported at `1:1`. `Subst.solve` now searches the input
constraints for a `Part` that mentions the offending field and dies at *its* location,
restricted to the file being compiled so that a constraint reached through a stdlib
helper's signature does not point the user into the standard library. `Loc` has two
source-bearing shapes, `Pos` and `Inferred(Pos)`; matching only the first silently
disables the search, which is worth knowing because it fails closed and looks like it
works.

Result: `unsound01` blames `104:18` and `unsound05` blames `25:16` — in both cases
exactly `, lt <- ((|accountId|), l)`, the constraint that mentions the field.
`witness03` and `unsound03` still fall back to the module header, correctly: their
offending constraint is not in the file being compiled. That fallback is the honest
answer, not a bug, but a user reading it learns only the field name.

**Status: ADOPTED 2026-09-01**, together with `cut`; both are now the defaults in
`GenRules`, with `-Dermine.genRules=all -Dermine.labelCheck=false` restoring the
previous compiler. The check was moved off the saturated set onto the INPUT partitions
before adoption: propagation is monotone (`forced_mono`), so the saturated set is
strictly stronger, but its soundness would then rest on every saturation rule being
sound or conservative -- and `Rules.lean` found rule 6's documented form unsound.
Reading the input makes the check depend only on the semantics `LabelProp.lean` proves,
and all five unsound modules are still refuted, with identical messages and blame.

Verified per-file over 45 modules (one invocation each, because batch-loading this
corpus StackOverflows in the loader and truncates both sides of the comparison):
**exactly four verdicts change, `unsound01`-`unsound04`, LOAD to REJECT.**
`core/test` with no flags: 903/904, the pre-existing failure only.

Superseded status note: Every corpus gate is green and the safety
proof is mechanized. Still open: the check runs on the saturated set inside `solve` and
its interaction with `reduce`'s second case has not been examined; no measurement exists
for a schema with hundreds of concrete labels — now measured, see the table above.
What remains: the `reduce` interaction, and the fact that two of the six rejections can
only name the field, not the constraint.

## 8. What could not be settled

Listed in descending order of how much a reviewer should care. None of these is
rhetorical; each is a thing this research genuinely did not close.

**8.1 Whether removing the generative rules preserves the 1447 `.ei` signatures.
This is the single load-bearing untested claim, and the whole recommendation
rests on it.** The evidence is strong but circumstantial:
- No corpus residual carries `commonSubexpression`'s fingerprint. Its output
  shape is an existential `w`, defined by one constraint with ≥2 abstract parts,
  occurring in the RHS of ≥2 other constraints. **Zero of the 357 corpus
  constraints match**, in either half of the corpus.
- `resolution`'s three outputs *all* carry a non-empty concrete part
  (`Constraints.scala:1021`, which returns `Set()` unless both `tops` and `bots`
  are non-empty). Zero stdlib residuals carry a concrete part at all, and the 8
  example ones that do are the un-simplified `PivotTest`/`SoftRelation` shapes,
  not resolution outputs.
- `disjunction`, the fourth generative rule, is **already disabled in production**
  and the corpus is unaffected — so this manoeuvre has shipped once already.

But *absence of the output from the residual does not prove the rule never
fired.* A generative rule can fire, have its conclusion consumed by a later
**destructive** step (`unify`, `makeEmpty`, `makeConcrete`, all of which call
`instantiateType` and therefore talk to the main unifier), and leave no trace in
the residual while still having changed the answer. `commonSubexpression` in
particular rewrites *existing* constraints (`a <- C* w y*`), which can enable a
subsequent `cancellation` or common-partition unification that would not
otherwise occur. **This must be settled by building the variant and running
`g1-validate.sh`, not by argument.** It is cheap to test — deleting call sites is
a few lines — and it is the first gate of any staged plan.

**8.2 Whether the *implementation* can diverge — and the fact that the
*specification* does.** This one splits in two, and the split is the interesting
part.

*The rule set as documented does not terminate.* Formalising
common-subexpression exactly as the header comment states it
(`tracker/lean/Rowpartition/Divergence.lean`) gives a rule that is **outright
non-terminating**: the conclusion is added to the working set, the introduced
name is genuinely fresh, and so the same pair of premises stays applicable
forever. Worse, a divergent seed is present at **N = 1** in the join family — a
single `join` contributes `a <- (d,e)`, `b <- (e,f)`, `c <- (d,e,f)`, and the
first and third already share two variables, so the rule fires immediately.

*The implementation terminates because of a guard that is not in the
specification.* `commonSubexpression` (:1076) first calls
`rhss(rhsCommon) = findRHS(incm, proc, s)`, which searches the incoming queue,
the processed queue and the accumulating set for a variable **already naming
that exact intersection**, and reuses it instead of minting a new one. That
memoisation bounds the fresh variables by the number of *distinct* intersections
— i.e. by the size of the meet-semilattice — which is exactly the 2^k of §2.3 and
exactly the `2^m − m − 2` lower bound proved in Lean. So the implementation is
finite-but-exponential while the documented rule is infinite.

**This is the most important thing in this section for anyone reimplementing:
the header comment is not a specification of the shipped algorithm.** A faithful
implementation of the comment would hang on a single `join`. Combined with §4.2
(the comment's resolution rule is also stated backwards), the 240-line header
should be treated as commentary, not as the source of truth.

No input was found on which the *implementation* fails to terminate. Both
families terminate at every size measured, including the two previously recorded
as hangs (`RowStress8` at 312s, `CoStar8` at 176s). The 2018 `Eternity` exception
implies someone once saw worse, but no reproducer survives and this session did
not construct one. A proof that the implementation always terminates is not
offered here and would be a genuine result.

**8.3 Whether a canonical residual is well-defined outside the definitional
fragment.** Leaf expansion gives a unique normal form inside the fragment. For
general systems, two syntactically different minimal constraint sets can be
semantically equivalent, and nothing here establishes a canonical choice among
them. Since equivalence is coNP-complete (§1.3), "minimise the residual" is not
obviously a tractable specification even at corpus sizes. Acceptance criterion 4
("residuals must be canonical") is therefore precise for 95% of the corpus and
under-specified for the rest.

**8.4 The complexity of Ermine's inference problem specifically.** §1.3
establishes NP-completeness of *constraint satisfiability* and coNP-completeness
of *equivalence*, and cites Palsberg & Zhao for NP-completeness of inference in a
closely related calculus with symmetric concatenation. Ermine's own inference
problem — with its strict positivity restriction, which the related work does not
have — was not reduced to or from anything. It is plausibly easier.

**8.5 Whether the 10 non-definitional signatures can be reduced into the
fragment.** Naming the equated remainders of a doubly-defined variable is the
obvious move (from `t <- (i,h,l)` and `t <- (i,r,f)` derive `w <- (h,l)`,
`w <- (r,f)`), but that is `cancellation` — itself generative in the general case
— and no termination argument for the reduction was produced.

**8.6 How much the type system depends on the solver's destructive
substitutions.** `Constraints.scala` calls `instantiateType` from `makeEmpty`,
`makeConcrete` and `instantiate`, feeding row solutions back into the main
unifier. The full set of ways a partition constraint can determine an ordinary
type variable was not mapped. Any redesign that changes *when* those calls happen
can move inferred types without changing any constraint.

**8.7 The `PivotTest` residuals contain a probable alias-expansion bug, and it is
in the acceptance corpus.** `pivotData`'s inferred type contains

    exists (RUnion2: a -> b) (RUnion21: c -> b) (RUnion22: rho -> b).
      RUnion22 v32 v3 (|Value|), RUnion21 v31 (|Value|) (|Value|), RUnion2 v3 v31 (|Value|)

`RUnion2` is a **type alias** (`Constraint.e`: `type RUnion2 t r s = exists ro so
rs. ...`), yet here it appears as an existentially-quantified type *constructor
variable of arrow kind*, applied but never expanded — three separate copies, at
three different kinds (`a -> b`, `c -> b`, `rho -> b`) inside one signature.
`PivotTest.e` never mentions `RUnion2`; it arrives by instantiating
`Relation/Pivot.e`'s `snoc_Brace`, whose own interface *does* expand it. So the
alias survives expansion at a use site across a module boundary and is then
generalised as a variable.

Confirmed to reproduce on a fresh full-inference run, so it is not a stale
checked-in interface. Not investigated further: it is unrelated to the cliff, but
it is in the 180-file acceptance corpus, so it will appear in every `.ei`
comparison and anyone touching constraint handling will meet it. Worth its own
ticket.

**8.8 Nothing here was validated against a build.** No Scala was written, per the
ticket. Every performance claim about a *replacement* is a prediction. The
measurements are all of the incumbent.

---

## 9. References

Every entry below was fetched and read during this research; the tag says how
strongly. **[V]** = the cited statement was verified in the source text.
**[S]** = taken from the abstract or a reliable secondary source, not the full
text. A consolidated dump of all 320 extracted claims (246 of them [V]) is in
the session scratch, not committed; the ones this ticket relies on are here.

**The faithful framing**
- [V] J. G. Morris & J. McKinna, *Abstracting Extensible Data Types: Or, Rows by
  Any Other Name*, POPL 2019 (PACMPL 3, art. 12). Row theories; the "simple rows"
  instance is disjoint union (Def. 1 §3.2; Example 3). Principality Thm 11,
  coherence Thm 15. **No decision procedure, no completeness theorem for its
  entailment relation, no complexity bound.**
- [S] A. Hubers & J. G. Morris, *Generic Programming with Extensible Data Types*,
  ICFP 2023 (Rω). Explicitly typed; type reconstruction left as future work.

**Closest algorithmic relative**
- [V] A. Chlipala, *Ur: Statically-Typed Metaprogramming with Type-Level Record
  Computation*, PLDI 2010. Disjointness as a kinding premise of `++`; a solver
  that mirrors Ermine's rules; and the author's own statement that inference is
  undecidable and unsupported by theorems.
- [S] A. Dovier, C. Piazza, E. Pontelli & G. Rossi, *Sets and Constraint Logic
  Programming*, ACM TOPLAS. **CLP(SET)**: primitive `un(s,t,u)` and `disj(s,t)`
  with a sound, complete, terminating solver. The most directly transferable
  algorithm found; read this before implementing §7.
- [V] F. Pottier, *A Constraint-Based Presentation and Generalization of Rows*,
  LICS 2003. Read in full from the author's PDF (the Type 3 fonts defeat text
  extraction; the pages were read as 300 dpi images). Row **terms** are removed
  in favour of constraints annotated with **filters** — finite or cofinite label
  sets, Boolean-closed. Symmetric concatenation is three **conditional**
  constraints. Closure terminates (Thm 2), preserves meaning (Thm 3), and closed
  plus false-free implies satisfiable (Thm 4), in O(n³ m log m) (Thm 7).
  **Caution before borrowing Thm 4**: its witness is built as the *join of the
  lower bounds* of each variable, invoking the lattice Theorem 1 by name. In an
  equality-only setting like Ermine's there is no ⊔ and no lower-bound set, so
  that proof has no analogue — the machinery specialises, the satisfiability
  proof does not.
- [V] B. Berthomieu & C. le Moniès de Sagazan, *A Calculus of Tagged Types, with
  applications to process languages*, TPA'95, in Aarhus DAIMI Report Series
  PB-493 (DOI 10.7146/dpb.v24i493.7021). **A correction to the citation trail
  everyone repeats.** The commonly cited LAAS report number is wrong: it is
  **93083 (March 1993)**, not 93205/93-2005, per both ATTAPL's bibliography and
  this paper's own reference list. That 1993 report could not be obtained — it
  is absent from HAL, DBLP, OpenAlex, Crossref, CORE, BASE and archive.org, and
  the author's LAAS page is behind an anti-bot wall that explicitly opts out of
  automated access, which we honoured rather than circumvented.
  **And the substantive correction: `=_L` is not Berthomieu's notation and is not
  a constraint form.** It is Pottier & Rémy's *name*, coined in ATTAPL, for what
  Berthomieu implements as a unification function carrying a label set as a
  subscript — `τ₁ U_L τ₂`, where `L` is "the set of labels for which its
  arguments have been unified so far". It is an algorithmic invariant, an
  accumulator threaded through a procedure, not a declarative predicate with a
  semantics. ATTAPL's hedge that complexity "apparently remains polynomial"
  should therefore be read as a remark about an unanalysed algorithm, not as a
  cited theorem. Anything this ticket says about `=_L` is about ATTAPL's
  rendering of the idea, not about Berthomieu's own statement of it.

**Complexity**
- [V] T. J. Schaefer, *The Complexity of Satisfiability Problems*, STOC 1978.
  Dichotomy Thm 2.1; SAT-with-constants dichotomy Lemma 4.1; positive
  One-in-Three SAT NP-complete via `R₆`. Ermine's `R_k` is 0-valid, giving the
  homogeneous case for free.
- [V] J. Palsberg & T. Zhao, *Type Inference for Record Concatenation and
  Subtyping*, Information and Computation 189(1):54–86, 2004. **Thm 6.4**: type
  inference with symmetric (disjointness-guarded) concatenation is NP-complete.
  The closest published result to Ermine's own problem.
- [V] A. Aiken, D. Kozen, M. Vardi & E. Wimmers, *The Complexity of Set
  Constraints*, CSL 1993. The arity hierarchy; **constants-only is NP-complete**,
  which is the row Ermine occupies.
- [V] L. Bachmair, H. Ganzinger & U. Waldmann, *Set Constraints are the Monadic
  Class*, LICS 1993. General positive set constraints are NEXPTIME-complete —
  cited to record that this bound does **not** apply to Ermine.
- [V] E. Böhler, E. Hemaspaandra, S. Reith & H. Vollmer, *Equivalence and
  Isomorphism for Boolean Constraint Satisfaction*, CSL 2002. **Thm 6**:
  equivalence is coNP-complete for non-Schaefer languages; Claim 13(2) covers
  exactly the constant-free 0-valid non-1-valid case, i.e. Ermine's residuals.
- [V] R. M. Karp, *Reducibility Among Combinatorial Problems*, 1972. EXACT COVER
  and 0-1 integer programming.
- [V] V. Kuncak & M. Rinard, *Towards Efficient Satisfiability Checking for
  Boolean Algebra with Presburger Arithmetic*, CADE-21. QFBAPA is in NP — an
  upper-bound machine with practical solvers, if cardinalities are ever wanted.

**Where the difficulty actually lives (union vs. disjointness)**
- [V] F. Baader & W. Snyder, *Unification Theory*, Handbook of Automated
  Reasoning vol. I ch. 8, 2001. ACI/ACUI: decision problem **polynomial —
  P-complete — for unification with constants**, NP-complete only with free
  function symbols. Type: ACUI unitary for elementary, finitary with constants.
- [V] A. Dovier, E. Pontelli & G. Rossi, *Set Unification*, TPLP 6(6):645–701,
  2006, §4.6. `gflat` systems are ACI1-with-constants and reduce to propositional
  **Horn satisfiability, hence in P**; adding variable elements makes systems
  NP-complete. This is the sharpest statement that union is easy and the extra
  structure is what costs.
- [V] F. Baader & O. Fernández Gil, *The Unification Type of an Equational Theory
  May Depend on the Instantiation Preorder*. ACUI is unitary w.r.t. the
  restricted preorder and infinitary w.r.t. the unrestricted one — a caution
  against quoting "ACUI is unitary" without saying which preorder.
- [S] F. Baader, *On the Complexity of Boolean Unification*, IPL 67(4), 1998.
  Elementary NP-complete, with free constants Π₂ᵖ-complete, general PSPACE-complete.
- [V] U. Martin & T. Nipkow, *Boolean Unification — The Story So Far*, JSC 7(3-4),
  1989. Boolean unification is unitary and decidable (Löwenheim; successive
  variable elimination).

**Restricted fragments (all evaluated and rejected for Ermine — §3)**
- [V] B. R. Gaster & M. P. Jones, *A Polymorphic Type System for Extensible
  Records and Variants*, NOTTCS-TR-96-3, 1996. One predicate form, `C^row \ l`,
  relating a row to a **single concrete label**; §7 concedes the system cannot
  type record append or the database join and points at Harper & Pierce's `r1 # r2`.
- [V] D. Leijen, *Extensible Records with Scoped Labels*, TFP 2005. Sound,
  complete, terminating unification obtained by allowing duplicate labels — i.e.
  by abandoning disjointness. Also documents that TREX's unification rules fail
  to terminate for rows sharing an abstract tail.
- [S] R. Harper & B. Pierce, *A Record Calculus Based on Symmetric Concatenation*,
  POPL 1991. The `#`/`‖` predicates Gaster–Jones name as the missing machinery.
- [V] A. Paszke & N. Xie, *Infix-Extensible Record Types for Tabular Data*,
  TyDe 2023. With first-class labels and AC row concatenation, unification is
  incomplete — no unique most general unifier.

**Constraint Handling Rules (for repairing the rules in place — §2.5)**
- [V] T. Frühwirth, *Proving Termination of Constraint Solver Programs*. The
  ranking method's theorems require programs **without propagation rules**;
  the paper states it cannot handle them in general. Ermine's generative rules
  are exactly propagation rules with local variables.
- [V] R. Haemmerlé, *Diagrammatic Confluence for Constraint Handling Rules*,
  TPLP 12(4-5):737–753. Confluence **without** global termination, by splitting
  rules into inductive and coinductive parts — directly usable for §7, where only
  the non-generative core must be confluent.
- [V] S. Abdennadher & T. Frühwirth, *On Completion of Constraint Handling Rules*,
  CP'98. Completion of a non-confluent CHR program, with the caveat that unlike
  term rewriting one generally needs more than one rule to join a critical pair.
- [V] S. Abdennadher, T. Frühwirth & H. Meuss, *Confluence and Semantics of
  Constraint Simplification Rules*. Confluence is decidable for terminating CHR
  programs via critical pairs.

**Deterministic-diagnostic precedent (§5)**
- [V] GHC User's Guide: `-freduction-depth` (default 200, formerly
  `-fcontext-stack`), `-fconstraint-solver-iterations`, and the Paterson
  Conditions; background in Sulzmann, Duck, Peyton Jones & Stuckey's CHR framing
  of instance reduction (Def. 11, Lemma 1, Cor. 2 give terminating and confluent
  derivations).
- [S] Vytiniotis, Peyton Jones, Schrijvers & Sulzmann, *OutsideIn(X)*. Deliberate
  incompleteness with a documented error contract.
- [S] Rust `recursion_limit` and the trait-solver overflow error; Scala 3 implicit
  divergence checking; Z3's `rlimit` (deterministic) vs `timeout` (not).
