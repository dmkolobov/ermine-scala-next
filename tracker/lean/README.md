# `rowpartition` — a Lean 4 formalisation of Ermine's row-partition constraint

Ermine (an ML-family language with row-typed records and relations) has exactly one row
constraint, **partition**, written `a <- (b, c, (|Foo|))`: the row `a` is the *disjoint
union* of the rows `b`, `c` and the concrete singleton `{Foo}`. One relation carries
concatenation, disjointness and completeness at once. Rows are finite sets of labels
drawn from an open (unbounded) universe; a row expression is a variable or a fully
concrete finite label set — no complement, no intersection, no nesting. A constraint
system is a finite conjunction of such constraints.

This development formalises that language and then audits the real solver
(`ermine-scala/core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`)
against it: its inference rules, its canonicalisation, its divergence, and the fragment
of the language that actually occurs in Ermine's own standard library.

**Headline numbers**, recounted mechanically on 2026-09-01. 22 modules, **1224 named
theorems in source**, **0 `sorry`**, **0 custom axioms**. Every theorem's axiom set is a
subset of Lean's three standard axioms (`propext`, `Classical.choice`, `Quot.sound`);
`sorryAx` appears nowhere. This is checked by walking the whole environment — `Audit.lean`
in this directory enumerates every theorem under the `Rowpartition` namespace and collects
its axioms:

```
$ lake env lean Audit.lean
Rowpartition theorems audited: 1465; declarations using a non-standard axiom: 0
```

(1465 > 1224 because the environment also carries generated equation and match-arm lemmas,
which the audit checks too; and 1224 counts `CutSearch`'s 125, which the audit does NOT
see — see the correction below.)

The source count is reproducible:

```
$ for f in Rowpartition/*.lean; do \
    grep -cE '^(theorem|lemma|@\[simp\] theorem|protected theorem|private theorem)' $f; \
  done | paste -sd+ | bc
1224
```

The figures this paragraph used to give — "15 modules, 960 named theorems", and per-module
counts of 86 for `Divergence`, 117 for `Cut`, 27 for `Compare`, 114 for `CutSearch`, 87 for
`SplitNecessary` — did not match any reproducible count and are corrected in the module map
below.

**Modules added after the original inventory was written.** First `CutConcrete`,
`CutSearch`, `SplitNecessary` and `LabelProp`; then, on 2026-09-01, `ResGuard`,
`ResGuardTerm`, `ResGuardDiverge` and `Saturate` (ticket items 8c and 8a). The detailed
per-theorem [inventory](#complete-inventory) below still covers the original eleven; the
later modules are described under [Later additions](#later-additions).

**Correction, 2026-09-01: `CutSearch` is NOT in the axiom audit, and never was.** The
library root did not import it, so `lake build` never compiled it and `Audit.lean`, which
walks the environment reachable from the root, never saw its theorems. Worse, it does not
build in the current environment at all: `lake build Rowpartition.CutSearch` is killed by
the OOM killer (`Lean exited with code 137`) on a 15 GB machine, twice, once with nothing
else running. Its 125 theorems are therefore claimed on the strength of a `lake env lean`
run recorded in a previous session and are NOT covered by any audit reproducible here.
Every other module IS imported by the root and IS covered.

**A standing caveat about citations.** Module headers written before 2026-09-01 cite
`Constraints.scala` and `Subst.scala` by LINE NUMBER, and those numbers are stale — the
solver files have grown by roughly 120 lines since (the `GenRules` flag object, the
`resGuard` guard, the corrected resolution diagram). The theorem statements are unaffected;
only the cross-references are. The modules added on 2026-09-01 cite by DEFINITION NAME
(`Constraints.scala`, `def resolution`) for exactly this reason, and new work should do the
same.

**Four of the results are negative** — three informal claims turn out to be *false*, and
they are the most useful things here. They are collected under
[Refutations](#refutations-what-turned-out-to-be-false).

**Three further modules place the language in its literature**, and add seven more
negative results. `Pottier.lean` builds an exact bridge to the constraint language of
Pottier's *A Constraint-Based Presentation and Generalization of Rows* (LICS 2003), then
measures the four places where the two systems come apart; `Berthomieu.lean` proves that
the `=_L` device cannot express Ermine's partition at all, and classifies exactly what it
can; `LabelClass.lean` proves that per-label reasoning costs one Boolean solve per
*signature class*, not per label, so schema width is free. See
[The comparison modules](#the-comparison-modules-pottier-berthomieu-label-classes).

**Two further modules evaluate a concrete engineering proposal**: deleting the
minting branch of `commonSubexpression` — a five-line change, guarded in the shipped
source by `GenRules.cseMints`. `Cut.lean` proves the cut is exactly meaning-preserving
and that its risk is one-sided, then proves it **does not terminate**; `Compare.lean`
puts the cut and the fully non-generative calculus of `Canonical.lean` side by side.
The headline is negative and was expected to be, and the modules add three more negative
results (12–14). See [The cut modules](#the-cut-modules-cutlean-and-comparelean) and, for
the property grid, [Cut versus clean, side by side](#cut-versus-clean-side-by-side).

---

## Building

The toolchain is pinned by `lean-toolchain` to `leanprover/lean4:v4.33.1`, and Mathlib
is pinned to `v4.33.1` by `lakefile.toml` / `lake-manifest.json`. `elan` is not on the
default `PATH`, so the export is required:

```bash
export PATH="$HOME/.elan/bin:$PATH"
cd ermine-scala/tracker/lean

lake build                              # build the whole library (804 jobs, 2026-09-01)
lake env lean Rowpartition/Rules.lean   # type-check ONE file (fast iteration)
```

`lake build` with a warm Mathlib cache completes in well under a minute; a single
`lake env lean` on one module takes 2–3 s once `Basic.olean` exists. Do **not** run
`lake exe cache get` here — Mathlib is already built and cached, and disk is tight.

`Rowpartition.lean` is the library root and imports every module under `Rowpartition/`.
Importing the root is the only check that the modules are mutually *consistent as a
namespace* — see [Integration log](#integration-log).

### Verified build status

Every file was type-checked individually and as part of the root. The table lists the
eleven-module state; on 2026-09-01 `ResGuard`, `ResGuardTerm`, `ResGuardDiverge`,
`Saturate`, `Splice`, `LabelAlgo` and `DerivedColumn` were each verified the same way (`lake env lean`,
exit 0, no output), the root builds, and `Audit.lean` reports 1465 theorems and 0
non-standard axioms. `CutSearch` is the one module that does NOT build here at all.

| file | `lake env lean` | notes |
|---|---|---|
| `Rowpartition.lean` (root) | **exit 0**, no output | imports all eleven modules |
| `Rowpartition/Basic.lean` | **exit 0**, no output | |
| `Rowpartition/Rules.lean` | **exit 0**, no output | some `linter.flexible` / `linter.style.show` warnings under `lake build` |
| `Rowpartition/Canonical.lean` | **exit 0**, no output | |
| `Rowpartition/Divergence.lean` | **exit 0**, no output | |
| `Rowpartition/Cut.lean` | **exit 0**, no output | 18 `linter.style.header` warnings under `lake build` |
| `Rowpartition/Compare.lean` | **exit 0**, no output | 1 `linter.style.header` warning under `lake build` |
| `Rowpartition/Fragment.lean` | **exit 0**, no output | |
| `Rowpartition/Berthomieu.lean` | **exit 0**, no output | |
| `Rowpartition/Pottier.lean` | **exit 0**, no output | the slowest module, 3.7 s |
| `Rowpartition/LabelClass.lean` | **exit 0**, no output | |
| `Rowpartition/Sanity.lean` | **exit 0** | one-line toolchain smoke test; `linter.style.header` warning |

`lake build` → `Build completed successfully (804 jobs).` (2026-09-01, with the five
modules added that day; `CutSearch` is NOT among them — see the correction at the top.)

**Build these one at a time on a small machine.** `lake` 5.0.0 has no `-j`/`--jobs` option,
so a bare `lake build` runs as many elaborations in parallel as it likes and can exhaust
memory. `lake build Rowpartition.<Module>` one module at a time is the reliable route, and
`LEAN_NUM_THREADS` bounds the per-file parallelism.

`lake build` emits **0 errors**. The warning counts in the table below were measured at
the eleven-module state and are NOT current — the five modules added on 2026-09-01 add more
`linter.style.header` warnings, since they follow the surrounding convention of a `/- … -/`
block before the imports. All warnings are Mathlib *style* linters and none touches a
proof:

| linter | count | what it wants |
|---|---|---|
| `linter.style.header` | 159 | the opening `/- … -/` block written as a `/-! … -/` module docstring placed immediately after the imports |
| `linter.flexible` | 26 | `simp at h` replaced by the `simp only [...]` it expands to, where `h` is used afterwards |
| `linter.style.show` | 6 | `change` instead of `show` where the goal is actually altered |
| `linter.style.longLine` | 1 | `Fragment.lean:445` exceeds 100 columns |
| `linter.unusedDecidableInType` | 1 | an unused `Decidable` argument |

The two new modules add **19** warnings and nothing else: all 19 are
`linter.style.header`, 18 from `Cut.lean` (which opens with a `/- … -/` block rather
than a `/-! … -/` docstring) and 1 from `Compare.lean`. The `flexible`, `show`,
`longLine` and `unusedDecidableInType` counts are unchanged from the nine-module state,
so neither new module introduced a tactic-level lint.

(The string `error` does occur twice in the build log — inside the phrase "error
condition 10" in a `Rules.lean` docstring. There are no compilation errors.)

---

## The shared vocabulary

All ten substantive modules are stated against the definitions in `Basic.lean`:

```lean
abbrev Label := Nat
abbrev Var   := Nat
abbrev Row   := Finset Label

structure Constraint where
  lhs  : Var            -- the row being partitioned
  vars : List Var       -- variable parts (order irrelevant, REPEATS MEANINGFUL)
  conc : Finset Label   -- the concrete part

abbrev Assign := Var → Row

def parts (rho : Assign) (c : Constraint) : List Row := c.conc :: c.vars.map rho

def Sat (rho : Assign) (c : Constraint) : Prop :=
  rho c.lhs = (parts rho c).foldr (· ∪ ·) ∅ ∧ (parts rho c).Pairwise Disjoint

def Models  (rho : Assign) (G : List Constraint) : Prop := ∀ c ∈ G, Sat rho c
def Entails (G : List Constraint) (c : Constraint) : Prop :=
  ∀ rho, Models rho G → Sat rho c
```

Two consequences of these choices recur throughout and are worth stating up front,
because several informal rules get them wrong:

* **`Pairwise` is positional, not by name.** `Sat` demands disjointness between
  *positions* of `parts`, so a variable that occurs twice on a right-hand side is
  required to be disjoint from itself, i.e. **forced empty** (`Sat.eq_empty_of_dup`).
  This is a real feature of the language, and the syntactic procedures in
  `Fragment.lean` cannot see it — which is where their completeness breaks.
* **One concrete part, not several.** A right-hand side with several concrete blocks is
  represented by their union. `Rules.rsat_iff_flatten` proves this faithful, *and* that
  the information lost by flattening is exactly the pairwise disjointness of the blocks —
  which is exactly Ermine's error condition 10.

---

## Module map

| module | thms | what it settles |
|---|---|---|
| `Basic.lean` | 56 | Syntax, semantics, and the **label-decomposition theorem**: satisfaction is pointwise in the label, so one row problem is a family of independent Boolean problems. Plus finite-support reconstruction, and the fact that *entailment* decomposes per label exactly when the hypothesis system is satisfiable — with a counterexample showing the side condition cannot be dropped. |
| `Rules.lean` | 97 | Every inference rule in `Constraints.scala`'s header comment, proved or refuted. Rules 1–5 and 7–11 sound; **rule 6 as written in the comment is unsound**. Fresh-variable rules are stated as `ConservativeExt`, which is the correct soundness notion for a rule that mints a variable. |
| `Canonical.lean` | 88 | The six non-generative rules as a terminating, meaning-preserving calculus: well-founded lexicographic measure, exact model preservation, an executable deterministic driver that is both sound and exhaustive. **Confluence is refuted.** |
| `Divergence.lean` | 81 | Why the solver blows up: the `commonSubexpression` rule is conservative (so the search is *pointless*, not merely slow), admits **no `ℕ`-valued decreasing measure at all**, and any saturated system over the `m`-constraint co-star has `≥ 2^m − m − 2` constraints. |
| `Cut.lean` | 102 | The proposed **five-line cut**: delete `commonSubexpression`'s minting branch, keep REUSE and FOLD. The kept branches are non-generative, derive only *entailed contractions*, and **preserve the model set exactly**; the cut's risk is one-sided (it can accept an ill-typed program, never reject a well-typed one). But the cut rule set **does not terminate**, and the obstruction is identified precisely: `resolution`, which mints unconditionally. |
| `Compare.lean` | 28 | The cut against `Canonical.lean`'s clean calculus, property by property. `Canonical`'s lexicographic measure runs strictly **backwards** on a rule the cut retains, on input that *has a model*; the cut inherits both of the clean calculus's negative results (non-confluence, non-decidability), and inheriting them is a theorem, not an observation. |
| `Fragment.lean` | 61 | The **definitional fragment** — what Ermine's own stdlib residuals actually look like — is trivially satisfiable, has a structural leaf-expansion normal form, and has *decidable* entailment by a syntactic multiset test. Completeness needs an extra `Linear` hypothesis that the informal statement omitted. |
| `Berthomieu.lean` | 48 | Berthomieu's `=_L` ("the rows agree outside the finite set `L`"), the device that keeps Wand-style concatenation disjunction-free. **Ermine cannot adopt it**: no `=_L` system defines `a <- (b, c)`, with any number of auxiliaries — and a complete classification of what does survive. |
| `Pottier.lean` | 81 | The bridge to Pottier's LICS 2003 constraint language. His symmetric concatenation **is** Ermine's binary partition, exactly (`bridge`) — but the exactness is a consequence of dropping subtyping, the **ternary** partition is not definable at all over its own variables, and his Theorem 4's join-of-lower-bounds witness degenerates to the empty assignment. |
| `LabelClass.lean` | 53 | Per-label reasoning costs one Boolean solve per **signature class**, not per label. Under a laminar hypothesis — one concrete block per database table — that is one solve per table plus one, **independent of schema width**. The two general bounds are shown simultaneously tight. |
| `CutConcrete.lean` | 80 | The minting branch of `commonSubexpression` introduces no concrete label, so cutting it cannot lose a refutation that turns on a concrete label. |
| `CutSearch.lean` | 125 | Bounded exhaustive counterexample hunt over small systems, by `decide` rather than `native_decide`, for the claim that the cut changes no verdict. |
| `SplitNecessary.lean` | 91 | Why the fully non-generative variant is unsound: `splitConcrete` is load-bearing for error detection, and the five programs `nongen` wrongly accepts are exhibited. |
| `LabelProp.lean` | 22 | **Per-label unit propagation**, the refutation-only rule now implemented behind `-Dermine.labelCheck`. Soundness (`forced_sound`, `refuted_unsat`): the rule never rejects a satisfiable system. The soundness bug in `unsound01_keyed_halves.e` is refuted mechanically, its satisfiable sibling is kept, and the rule's **incompleteness is proved, not asserted** — an unsatisfiable system is exhibited that propagation provably cannot refute. |
| `ResGuard.lean` | 20 | **Guarding `resolution`** with the resolvent reverse lookup — the analogue, for that rule, of the lookup `splitConcrete` already consults. The guard is not a semantic change: the reuse branch does not move the model set at all, the mint branch is a conservative extension, and `resolvent_unique` shows the variable the guard declines to mint is FORCED EQUAL to the one it reuses. |
| `ResGuardTerm.lean` | 30 | …and the guarded rule **terminates on every satisfiable system**, with an explicit bound (`guarded_terminates_of_satisfiable`). The measure weights each variable's remaining resolvent-key budget by a power of the cardinality of the row it denotes: the guard bounds the keys, the MODEL bounds the depth, and neither ingredient works alone. |
| `ResGuardDiverge.lean` | 33 | …and **not in general**. Four constraints on four variables and four labels admit guarded chains of every length (`gSeed_diverges`, `gres_no_decreasing_measure`). The seed is proved unsatisfiable, so the two halves are complementary — and `gSeed_refuted` proves per-label propagation kills it at one label in five steps, so the guard and the label check are complementary defences. |
| `Saturate.lean` | 25 | **The licence to run the label check on the SATURATED set** (`refute_saturated_sound`): a satisfiable input stays satisfiable through any run of the solver. Adds the four behaviours no other step relation modelled — `makeEmpty`'s two halves, `makeConcrete`, rename-with-de-duplication, and DELETION — and proves the implication is STRICT (`satStep_not_reflecting`), so a refutation-only check may move there and an acceptance check may not. |
| `Splice.lean` | 29 | **`Subst.reduce`'s second case** (ticket 8b). The splice is sound with NO side condition — the concrete parts are automatically disjoint and a duplicated variable is automatically empty — and exactly conservative for one splice. But `DroppedPartition.dropped_can_lose` exhibits a satisfiable system with no concrete labels on which the emitted residual FAILS to entail a consequence of the input, because `reduce` never rewrites a left-hand side. |
| `LabelAlgo.lean` | 57 | **The Scala `checkLabel` fixpoint itself**, not just the rule it implements: every bit the algorithm writes is `Forced` (`algoWrite_forced`), so every clash it reports is a genuine refutation (`checkLabel_clash_unsat`). Closes what `Saturate` calls the weakest link. And `DupNeeded.nodup_needed` shows the `ones > 1` branch is sound ONLY because the Scala's right-hand side is a `Set`: with a duplicated variable part it fires where `Forced` derives nothing. |
| `SpliceGuard.lean` | 17 | **The licence for the 8b repair.** `SpliceOK` packages the three side conditions of `splice_entails_iff` as ONE DECIDABLE predicate — so the compiler can test them — and `reduce2G` is the guarded fold. `reduce2G_backward`: a model of the guarded residual extends, changing only ambiguous variables, to a model of the input. `reduce2G_preserves_entailment` is unconditional. `dropped_fixed_entails` shows the guard repairs `DroppedPartition`, and `spliceOK_fires` that it is not merely "never splice". |
| `DerivedColumn.lean` | 4 | **Settles quality-vs-soundness for the 2026-09-02 signature regressions.** Four definitions began publishing `forall t. (exists ..) => Relation t` where they had published a concrete row. `t_determined_of_sat`: the three published constraints force `rho t = insert d K`, so the two forms accept exactly the same consumers and the regressions are QUALITY defects, not soundness ones. Proved for the SHAPE ("add one derived column to a relation with a concrete header"), which recurs in `BatteryCycling`, `RevenueByPeriod`, `HeadcountPlan` and `ClinicalTrial`. Needs NEITHER `L ⊆ K` nor `d ∉ K` — a first version assumed both, Lean reported one unused, and chasing that produced an argument needing neither, nor the `Pairwise Disjoint` halves of the hypotheses. |
| `Sanity.lean` | 0 | A single `example`: a toolchain smoke test, no content. |

---

---

## Later additions

Four modules postdate the original inventory. All four are in `Rowpartition.lean`, all
four build, and all four are covered by the environment-wide axiom audit above.

### `LabelProp.lean` — the per-label refutation rule

`Basic.sat_iff_forall_label` says satisfaction is pointwise in the label. This module
turns that into a *rule*, and proves the properties that make it adoptable where
`Constraints.disjunction` is not.

| theorem | what it says |
|---|---|
| `forced_sound` | every bit unit propagation derives is the bit of **every** Boolean model at that label |
| `refuted_unsat` | a variable forced both ways ⇒ the system has no model |
| `not_refuted_of_sat` | contrapositive — **a satisfiable system is never refuted**, i.e. no false rejections |
| `forced_mono` | derived facts survive weakening, so running on the saturated set is at least as strong as on the input |
| `Unsound01.refuted` / `.unsat` | the shipped compiler's soundness bug, refuted at the single label `accountId`, and independently proved unsatisfiable |
| `Good.models` / `.not_refuted` | its satisfiable sibling, with an explicit model — the rule provably keeps it |
| `Incomplete.unsat_and_not_refuted` | **the incompleteness is mechanized**: a system that has no model and that propagation provably does not refute |

The last row is the honest boundary. Propagation never case-splits, so it decides only
what is forced; `Incomplete.forced_char` characterises the derivable facts exactly and
shows the clash is not among them. Deciding these Boolean systems in general is
Schaefer's one-in-three problem, so no polynomial propagation can be complete unless
P = NP. Refusing to search is what makes the failure mode deterministic.

Two structural facts separate this rule from `disjunction`, and they are why one is
adoptable and the other is not:

* it **emits no constraint and mints no variable**, so it cannot feed the saturation
  loop. NOTE, corrected 2026-09-01: this is visible from the SHAPE of `Forced`, whose
  conclusion is a `Prop` about the system and never a system — it is *not* established by
  `models_unchanged`, which is literally `Models rho G ↔ Models rho G := Iff.rfl`, a
  tautology with no content. That declaration records the intent and proves nothing;
* it **ranges only over labels occurring in a `ConcreteRho`**, so a general helper
  signature with no concrete instance has no labels to check and is untouched.

Measured against the corpus: with `-Dermine.labelCheck=true` the 129 stdlib modules load
in 11.11s against 11.17s with the flag off, and the output over `core/examples`,
`core/examples/Ai` and `core/examples/shouldfail` — 66 files, 297 lines — is
**byte-identical** to the run with the check disabled.

### `CutConcrete.lean`, `CutSearch.lean`, `SplitNecessary.lean`

Three further results on the CSE minting cut, produced alongside the ticket's §7.10.
`CutConcrete` shows the minting branch introduces no concrete label, so cutting it
cannot lose a concrete-label refutation. `CutSearch` runs a bounded exhaustive
counterexample search by `decide` (not `native_decide`, so no compiler trust is
involved). `SplitNecessary` proves the complementary negative: `splitConcrete` is
load-bearing, which is why the fully non-generative `nongen` variant is unsound.

### 2026-09-01: `ResGuard`, `ResGuardTerm`, `ResGuardDiverge`, `Saturate`, `Splice`

Ticket items 8c, 8a and 8b — full write-up in `tracker/TICKET-row-solver-8abc.md`.

`Cut.lean` §5 left `resolution` as the sole obstruction to termination of the cut rule set,
and observed that the guard it needs already exists elsewhere in the same file. These
modules take that step and settle what it buys.

* **`ResGuard`** — the guard. `resolution`'s minted `z` has no defining partition, so
  `Cut.Named` is the wrong lookup; what names `z` is the rule's own first conclusion,
  `v <- (z, C ∪ D)`. Guarding on that is provably not a semantic change: the reuse branch
  does not move the model set (`GResStep.reuse_models_iff`), the mint branch is a
  conservative extension, and `resolvent_unique` shows the variable the guard declines to
  mint is FORCED EQUAL to the one it reuses (`guard_loses_nothing`).
* **`ResGuardTerm`** — `guarded_terminates_of_satisfiable`, with an explicit bound. The
  measure weights each variable's remaining resolvent-key budget by a power of the
  cardinality of the row it denotes. The guard alone bounds nothing, because minting
  creates variables with fresh budgets; the MODEL supplies the descent (`mint_rank_lt`).
  Contrast `Cut.resSeed_diverges`, which runs on a system that *has* a model.
* **`ResGuardDiverge`** — and it does NOT terminate in general: four constraints admit
  guarded chains of every length (`gSeed_diverges`, `gres_no_decreasing_measure`). The
  seed is proved unsatisfiable, so the halves are complementary rather than contradictory
  — and `gSeed_refuted` proves `LabelProp`'s propagation kills it at one label in five
  steps, which is why the guard and the label check are complementary defences.
* **`Saturate`** — the licence for item 8a: a satisfiable input stays satisfiable through
  any run of the solver (`SatSteps.sat_mono`), so a refutation on the saturated set refutes
  the input (`refute_saturated_sound`). Adds the four behaviours no other step relation
  modelled: `makeEmpty`'s two halves, `makeConcrete`, rename-with-de-duplication, and
  DELETION — every previous step relation is monotone by construction. And it proves the
  implication STRICT (`satStep_not_reflecting`): a refutation-only check may move to the
  saturated set, an acceptance check may not.
* **`Splice`** — item 8b, and the answer is a counterexample. `Subst.reduce`'s second case
  is sound (`splice_sat`, with no side condition — the concrete-part disjointness and the
  duplicate case both discharge themselves) and exactly conservative for one splice
  (`spliceG_backward`). But `DroppedPartition.dropped_can_lose` exhibits a satisfiable
  four-variable system with no concrete labels on which the emitted residual FAILS to
  entail a consequence of the input. The cause is precise, and it is not the drop:
  `reduce` never rewrites a LEFT-hand side, so an ambiguous variable that still heads a
  constraint in the published list is left with nothing tying it to the rest.
  `dropped_loses_nothing` is the positive half, under exactly the hypothesis the
  counterexample violates.
* **`SpliceGuard`** — the repair, licensed. Those three hypotheses are all syntactically
  decidable, so the compiler can check them and skip the splice when they fail; that is
  `-Dermine.spliceGuard`. `reduce2G_backward` proves the guarded fold conservative,
  `reduce2G_preserves_entailment` — with no hypothesis about the saturated set at all —
  that every consequence of the input over non-ambiguous variables survives, and
  `dropped_fixed_entails` that the guard repairs the counterexample above.


## What is proved in Lean / what is proved on paper / what is cited

This is the section a reviewer should read first. Nothing below is hedged for effect;
the categories are meant literally.

### Proved in Lean

Everything in the [inventory](#complete-inventory) — all 714 theorems — is a complete
Lean proof, machine-checked, with no `sorry` anywhere in the development and no axiom
beyond Lean's standard three. In particular the following are *theorems*, not summaries
of arguments made elsewhere:

* **Label decomposition** (`sat_iff_forall_label`, `satisfiable_iff_forall_label`,
  `entails_iff_forall_label`), including the counterexample
  (`Counterexample.entails_not_pointwise`) showing that the entailment version genuinely
  needs its satisfiability hypothesis.
* **Soundness of rules 1, 2, 3, 4, 5, 7, 8, 9, 10, 11** in general list-indexed form, and
  the two-way equivalence (`rule4_back`, `rule6_back`, `rule9_back`) showing the
  fresh-variable rules lose no information.
* **Unsoundness of rule 6 as written in the header comment**
  (`Rule6Header.header_not_conservative`, `Rule6Header.header_makes_unsat`), together with
  the sound sharp form the Scala code actually implements (`rule6`).
* **Necessity of three omitted side conditions**: `rule5_needs_shared_conc`,
  `rule6_swapped_needs_disjoint`, `absorb_guard_needed`, `unsat_of_occurs`.
* **Termination of the canonicaliser** (`Step.decreasing`, `lexLt_wf`,
  `no_infinite_descent`, `exists_fuel`) and **exact model preservation**
  (`Step.preserves`, `canonN_preserves`).
* **Soundness *and* exhaustiveness of the executable driver** (`stepFn_sound`,
  `stepFn_complete`), hence `canonicalise_normalForm`: the state the driver halts in is a
  normal form of the *rule relation*, not merely a state the implementation ran out of
  moves on.
* **Non-confluence** (`CriticalPair.not_locally_confluent`, `not_joinable`) and
  **incompleteness as a decision procedure** (`normal_form_can_be_unsat`).
* **Conservativity of the common-subexpression rule** (`CseStep.extend`,
  `CseSteps.entails_iff`, `coStar_residual`) and its **non-termination**
  (`no_decreasing_measure`, `seed_diverges`, `joinTriple_diverges`).
* **The exponential lower bound** `coStar_card_lower` (and its numeric instance
  `coStar_seven`: at least 119 constraints at m = 7).
* **The definitional fragment's decision procedure** and its two counterexamples
  (`entails_iff_test`, `decidableEntails`, `NotDefinitional.entails_not_test`,
  `NonLinear.entails_not_test`).
* **The bridge to Pottier's constraint language** (`bridge`,
  `sat_iff_pmodels_concatSystem`, `models_iff_pmodels`), its sharpness
  (`bridge_result_position_sharp`, `pottierConcat_comm`), the n-ary chain
  (`pchainRow_iff_flat`, `sat_iff_pchainRow`), and the four negative results that
  surround it (`ternary_not_definable`, `concat4_not_functional`, `lbAt_encode`,
  `Filter'.apparent_union_ne`).
* **The Berthomieu separation and its classification** (`not_defines_partition`,
  `defines_partition_iff`, `berthomieu_separation`, `not_definesX_subset`), together with
  the positive boundary (`defines_unary`, `definesX_extension`, `bcDefines_eqOut`) that
  keeps it from being vacuous.
* **Signature classes** (`bmodels_congr`, `entails_iff_abstract`, `card_sigs_le`,
  `card_sigs_le_blocks`), the width-independence witness
  (`wideSchema_width_independent`) and the simultaneous tightness of both general bounds
  (`genSys_bounds_tight`).
* **Exact meaning preservation of the proposed CSE cut** (`sat_reduce_of_denotes`,
  `reuse_entails`, `fold_entails`, `CutStep.models_iff`, `cut_preserves_meaning`), the
  one-sidedness of its risk (`cut_never_wrongly_refutes`, `refuter_can_miss`,
  `cut_risk_is_one_sided`, `complete_refuter_unaffected`), termination of the branches it
  keeps (`CutChain.length_le`, `cut_branches_terminate`), and its non-vacuity
  (`CutExample.reuse_fires`, `CutExample.fold_fires`, `cut_removes_something`).
* **Non-termination of the cut rule set** (`cut_does_not_terminate`,
  `cut_no_decreasing_measure`, `resSeed_diverges`, `ResStep.escapes`) *together with the
  localisation of the obstruction*: `splitConcrete` terminates by itself
  (`SplitStep.cands_lt`, `split_terminates`), so `resolution` is the sole
  unconditionally-minting rule left.
* **The cut-versus-clean separation** (`Compare.termination_separation`,
  `Compare.preservation_strength`, `Compare.bottom_line`), including that
  `Canonical`'s own measure *increases* on a retained rule
  (`Compare.resStep_canonical_measure_increases`) on input that has a model
  (`Compare.resSeed_satisfiable`), and that the cut inherits both of the clean calculus's
  negative results (`Compare.full_cut_not_locally_confluent`,
  `Compare.full_cut_normal_form_can_be_unsat`).

Concrete instances in the counterexample namespaces (`Counterexample`, `Rule6Header`,
`CriticalPair`, `Orientation`, `NotDefinitional`, `NonLinear`, `Worked`, `demo`,
`RefuteEx`, `CutExample`) are
discharged by `decide`/`rfl` on closed terms — kernel computation, not `native_decide`.
There is no `native_decide` in the development, so no `Lean.ofReduceBool` dependency.

### Proved on paper only (stated in the files, not formalised)

These are honest gaps in *coverage*, not gaps in any proof. Each is a claim that appears
in a module's prose and is **not** backed by a Lean theorem:

1. **Genuinely fresh naming in the exponential lower bound.** `coStar_card_lower` assumes
   `CseClosed`, which uses a *canonical* namer `nm : Finset Var → Var` (perfect
   hash-consing). The prose argues that genuinely fresh naming can only make the
   saturated set larger — the idealisation is the solver's best case — but formalising
   that needs an invariant about which variables may name which rows that
   `Divergence.lean` does not develop. Explicitly flagged in the file, section 5.
2. **That making `occurs` total would join the critical pair.** `Canonical.lean` suggests
   repairing non-confluence by letting `occurs` detect the contradiction when
   `c.conc ≠ ∅` instead of blocking, and says outright: "I expect the latter joins this
   particular pair, but I did not prove that."
3. ~~**That the Scala `def resolution` implements the sound pairing.**~~ **DISCHARGED
   2026-09-01.** `Rules.lean` reported from a *reading of the Scala source* that
   `resolution` derives `x <- bots z` with `bots = concr2 -- (concr1 & concr2)`, i.e. the
   correct `E \ C` / `C \ E` form proved as `rule6`, and said a reviewer wanting the link
   should re-read `Constraints.scala` directly. Two independent readings did that on
   2026-09-01 and confirmed it, with the substitution written out: `D := concr1 ∩ concr2`,
   `C := tops`, `E := bots`, under which `rule6`'s two disjointness hypotheses are
   set-difference identities and hold unconditionally. It remains a reading, not a
   verification of the Scala — Lean cannot check Scala — but it is no longer an unchecked
   one. The FILE-HEADER diagram, which stated the unsound own-premise pairing, has been
   corrected.
4. **That the Scala solver is saved from `Divergence`'s non-termination by its `rhss`
   reverse lookup and queue de-duplication.** Stated as a design observation about the
   engine, not proved. What *is* proved is that the rule as documented has no termination
   argument.

   Sharpened 2026-09-01, still not proved. The engine has a third discipline the rule sets
   here do not model: `learnPartitions` compares the INCOMING partition against `proc`
   only, so a fixed PAIR of premises is examined exactly once — when the later of the two
   is incorporated — whereas every step relation in this development lets a matching pair
   fire forever. That is why `Cut.resSeed_diverges` and `ResGuardDiverge.gSeed_diverges`
   are statements about RULE SETS and not reproducible compiler hangs, and it is visible
   in the corpus: the Ermine transcription of `gSeed` is REJECTED by the shipped compiler
   in 0.03s, by rules the model does not include. A faithful model of the engine would
   have to carry the incoming/processed split, and none here does.

### Cited (empirical, from outside Lean)

These numbers motivate the formalisation and are quoted in the module headers. **None of
them is verified by Lean**; they come from running the real compiler and from measuring
Ermine's standard library.

* **Solver timings.** Family A (`N` left-nested `join`s): `N=4: 0.03 s`, `5: 0.13 s`,
  `6: 0.79 s`, `7: 10.94 s`, `8: killed at >138 s`. Family B (the *co-star*,
  `x_i <- (b_0 … b_{m−1} minus b_i)`): `m=4: 0.03 s`, `5: 0.09 s`, `6: 0.68 s`,
  `7: 6.38 s`. (`Divergence.lean` header.)
* **That the retained residual is verbatim the input** in both families, observed on the
  real compiler. `coStar_residual` proves the *semantic* counterpart (the reachable
  system entails nothing new over the input's vocabulary) but not the syntactic identity
  the compiler exhibits.
* **That profiling names `commonSubexpression` as the hot rule.** This is why
  `Divergence.lean` models only that rule.
* **Corpus statistics** over the 129-module stdlib closure's inferred interfaces: 199
  constrained signatures, 345 partition constraints; 135/199 carry exactly one constraint
  (maximum 15); **no residual constraint anywhere contains a concrete label**; 11/199
  constrain the same variable twice; right-hand-side arities 10 unary, 220 binary, 77
  ternary, 28 4-ary, 4 5-ary, 4 6-ary, 2 7-ary. (`Fragment.lean` header.) The
  "all abstract" observation is what makes `satisfiable_of_abstract` bite on real inputs;
  the "11/199 constrain the same variable twice" observation is what makes the
  `IsDefList` hypothesis a *restriction* rather than a free lunch.
* **The two known defects of the Scala solver** (it emits a vacuous `r <- (r)` and emits
  the same constraint twice under a permuted right-hand side). The *defects* are cited;
  that this calculus removes both, meaning-preservingly, is proved (`step_vacuous`,
  `step_perm_dup`).

### Deliberately out of scope

Not gaps in the sense of unfinished proofs — simply not attempted, and named so that
nobody mistakes silence for coverage:

* `Divergence.lean` models **only** `commonSubexpression`. `resolution`, `cancellation`,
  `substitution` and `disjunction` are not modelled there. Adding rules can only enlarge
  a saturated set, so the lower bound survives; **the conservativity theorem does not
  automatically survive and would have to be redone per rule.**
* No **upper** bound: nothing says the saturation is *only* exponential.
* Family A is not modelled constraint-by-constraint; `joinTriple_diverges` shows only
  that one `join` call already contains a divergent seed.
* `Canonical.lean` implements six of the eight non-generative rules named in the design
  proposal. **Cancellation and definitional substitution are not implemented** — the
  first needs positional list surgery across two constraints with care that the measure
  not rise, the second an acyclicity invariant on the definition graph that none of the
  other five rules maintain.
* `Fragment.lean` proves the fragment's entailment decidable but says nothing about the
  complexity of the decision procedure.
* Nothing here connects to Ermine's *type inference* — only to the constraint solver.

---

## Refutations: what turned out to be false

Four informal claims are refuted with explicit counterexamples. These are the
load-bearing results.

### 1. Rule 6 (resolution), as written in the header comment, is unsound

The comment concludes `x <- C* z, y <- E* z`, pairing each lone variable with the
concrete part of **its own** premise. The correct pairing is the other way round.
`Rule6Header.premise_conclusion_unsat` gives the general reason: premise 1
`a <- C* D* x` forces `Disjoint (C ∪ D) (rho x)`, while the conclusion `x <- C* z`
forces `C ⊆ rho x`, so `C = ∅`. Concretely with `a = {1,2}, C = {1}, D = ∅, E = {2}`:
the premises have a model (`Rule6Header.premises_sat`), no extension of it satisfies the
comment's conclusion (`header_no_extension`), the rule is not a conservative extension
(`header_not_conservative`), and premises-plus-conclusion is outright unsatisfiable
(`header_makes_unsat`). A solver following the comment would report a spurious type
error.

Two refinements, both proved: the swapped rule with `C` and `E` raw is sound **only**
given `Disjoint C E` (`rule6_swapped`, and `rule6_swapped_needs_disjoint` shows the
hypothesis is necessary — the premises alone do not force it); the sharp
`x <- (E \ C) z, y <- (C \ E) z` form (`rule6`) is sound with no hypothesis beyond the
`C ⊥ D`, `D ⊥ E` that the premises themselves force. The prose above the ASCII rule in
`Constraints.scala` describes the correct version, so the defect is confined to the
diagram.

### 2. The canonicalisation calculus is not confluent

`CriticalPair.not_locally_confluent` / `not_joinable`. On
`G = [a <- (a, b), b <- ((|{7}|))]`, `occurs` fires on the first constraint (its concrete
part is empty) and yields `[b = ∅, b = {7}]`; `absorb` instead instantiates `b`, giving
`a <- (a, (|{7}|))` — whose concrete part is now **non-empty**, so `occurs` is
permanently blocked. Both results are normal forms (checked exhaustively against all six
constructors, not merely against the implementation's search order) and they differ. The
mechanism is general: `absorb` enlarges a concrete part and `occurs` requires it empty.
**The canonicaliser's output is therefore strategy-dependent.** The shipped `stepFn` is a
function, so `canonN` is deterministic and its result unique — determinism is a property
of the *implementation*, not of the rule set.

A second, independent and *repairable* ambiguity, on a satisfiable system:
`Orientation.results_differ` — `common` may eliminate `x` in favour of `y` or the
reverse, and the results differ. Fix: always eliminate the larger variable.

And `CriticalPair.normal_form_can_be_unsat`: a normal form can be unsatisfiable, so the
non-generative calculus is a sound and complete *simplifier* but **not** a decision
procedure.

### 3. The multiset test for the definitional fragment is incomplete without linearity

`NonLinear.entails_not_test`. `G = [p <- (d, d)]` is abstract and a perfectly good
definition list (`p` defined once, `d` a leaf, acyclic), and `Entails G (p <- (d))`
genuinely holds — a repeated variable is forced empty, so `rho d = ∅` and `rho p = ∅`.
The syntactic test compares `leaves p = [d,d]` against `leaves d = [d]` and fails on
length. **The syntactic test cannot see forced-emptiness.** Completeness therefore needs
`Linear G := ∀ a, (leaves G a).Nodup`, a hypothesis the informal statement omitted;
`linear_iff` turns it into a finite decidable check. For a solver this means: reject, or
specially handle, any residual whose expansion repeats a leaf.

### 4. The common-subexpression rule has no termination argument at all

`no_decreasing_measure`: there is **no** `μ : System → ℕ` decreasing on every step — not
merely that the usual candidates fail. All three standard measures (constraint count,
variable occurrences, multiset of right-hand-side sizes) strictly *increase*
(`cseStep_measures_increase`). The reason is that the conclusion is added to the working
set and the fresh name is genuinely fresh, so the same pair of premises stays applicable
forever (`seed_diverges`). A single `join` call already contains such a pair
(`joinTriple_diverges`) — Family A's blow-up does not require nesting to *start*.

### Bonus surprises (true statements that were expected to be different)

* **The lower bound is `2^m − m − 2`, not `2^m − m − 1`.** The co-sets of size `m−1` (the
  inputs' own right-hand sides) are the intersection of no two distinct constraints, so
  they are never canonically named; the named family is `{S : 2 ≤ |S| ≤ m−2}`, of size
  `2^m − 2m − 2`, plus the `m` inputs. Stated subtraction-free as
  `2^m ≤ |G| + m + 2` (`coStar_card_lower`) and again with truncated subtraction
  (`coStar_card_lower'`).
* **Error condition 10 cannot even be stated in `Constraint`.** With a single concrete
  `Finset`, `a <- C* x* D D` flattens to `a <- (C ∪ D) x*` and the duplication vanishes.
  `Rules.lean` therefore adds `RawConstraint` (a *list* of concrete blocks) and proves
  `rsat_iff_flatten`. Practical consequence: **the duplicated-field check must happen
  where a source right-hand side is turned into a solver constraint** — once flattened,
  the information is gone.
* **Meaning is preserved on the nose**, with no "modulo the eliminated variables" hedge,
  because `a <- (b)` with empty concrete part *is* the equation `a = b` (`sat_eqc`). A
  `State` keeps eliminated variables in a `solved` list read back as ordinary
  constraints. Recommendation for the implementation: never discard an eliminated
  variable's definition, and the correctness statement becomes an equality of model sets.
* **Removing all copies of a duplicated variable is unsound; removing one is exact.**
  `sat_absorb` uses `List.erase` and needs no multiplicity side condition. A
  `filter`-based rule would be unsound: `a <- (b, b, (|k|))` with `b = k ≠ ∅` is
  unsatisfiable while `a <- ((|c ∪ k|))` is satisfiable.
* **Soundness of the leaf expansion needs no hypotheses at all.** Defining
  `leaves (c :: G) a` to expand `c`'s right-hand side using only the *tail* makes the
  recursion structural, so it terminates by construction and is semantically valid for
  every system — cyclic, duplicated-lhs, concrete-carrying. Acyclicity and uniqueness are
  needed only for *completeness* and for the leaf-ness of the output. A solver may fire
  the expansion rule unconditionally.
* **A definitional system need not be satisfiable once concrete labels are allowed**
  (e.g. `a <- (b, (|{1}|))` with `b <- ((|{1}|))`). What rules this out on the corpus is
  abstractness, not definitionality. Stated as an observation in `Fragment.lean`; the
  unsatisfiable example is *not* formalised.

### 12. The proposed cut does not terminate, and `splitConcrete` is not why

The five-line cut was expected to fail the standard finiteness argument, because two
minting rules survive it. That is right, but it is not the whole story, and the
difference decides what to do next. **`splitConcrete` terminates on its own**
(`Cut.split_terminates`): it consults the same reverse lookup that drives branch (a)
before minting, and `Cut.SplitStep.cands_lt` turns that guard into a strictly decreasing
measure. **`resolution` consults nothing** and mints on every match, and it is the sole
obstruction (`Cut.resSeed_diverges`, `Cut.cut_no_decreasing_measure`). If the ticket ever
wants termination, `resolution` is the rule to guard — and the guard already exists
elsewhere in the same file.

### 13. `Canonical`'s measure does not merely fail on the cut; it runs backwards

The expected result was "the clean calculus's termination argument is unavailable for the
cut". What is true is stronger: `Compare.resStep_canonical_measure_increases` shows
`LexLt (Meas G) (Meas G')` on **every** retained `resolution` step — the exact relation
`Canonical.Step.decreasing` asserts, in the opposite direction, in the dominant
coordinate. With `lexLt_asymm` that kills not just the measure but the whole proof
strategy. And the input on which it happens **has a model**
(`Compare.resSeed_satisfiable`), so this is not the degenerate case.

### 14. A task statement that was self-contradictory, resolved by proving both halves

The brief for `Cut.lean` §3 asked to show that `G ⊆ G' → unsat G → unsat G'` is *false in
general*, and in the same sentence called that "the useful direction". They are the same
statement, and it is **true** — `Cut.unsat_mono`, one line. The statement that is actually
false is the **converse**, refuted by `{x <- (|1|)} ⊆ {x <- (|1|), x <- (|2|)}`
(`Cut.unsat_not_antitone`). Both are proved, with a note at the head of §3 recording the
discrepancy so no reader is misled.

---

## The comparison modules: Pottier, Berthomieu, label classes

Three modules place Ermine's partition constraint in its literature and measure the fit.
They share `Basic.lean`'s vocabulary and add no axioms; between them they contribute 182
of the 714 theorems.

| module | thms | the question it answers |
|---|---|---|
| `Pottier.lean` | 81 | *Is Pottier's symmetric-concatenation constraint the same relation as Ermine's binary partition?* **Yes, exactly** (`bridge`) — and the module then locates the four places where the two systems come apart. |
| `Berthomieu.lean` | 48 | *Could Ermine adopt the `=_L` device that keeps Wand-style concatenation disjunction-free?* **No** (`not_defines_partition`), with a complete classification of what does survive. |
| `LabelClass.lean` | 53 | *Does per-label reasoning cost one Boolean solve per label?* **No — one per signature class**, and under a laminar hypothesis that is one per table, independent of schema width. |

### Separations and refutations found

Seven results here are negative, numbered on from
[Refutations](#refutations-what-turned-out-to-be-false). Each is a Lean theorem with an
explicit witness, not an observation.

#### 5. Pottier's Definition-8 remark is literally an over-statement

The paper says "the row labels apparent in `L₁ ∪ L₂` are those apparent in `L₁` or
`L₂`", which reads as an equality. Only `⊆` is true: `{1} ∪ (𝓛 \ {1,2}) = 𝓛 \ {2}`, in
which the label `1` is no longer apparent (`Filter'.apparent_union_ne`). The direction
his Theorem 2 and his parameter `m` actually need — that nothing becomes apparent that
was not — does hold (`Filter'.apparent_union_subset`, and `apparent_inter_subset` for
intersection, which is what (TRANS-ROW) propagates through). **Nothing in his development
breaks**; the remark is simply stated one direction too strongly.

#### 6. The bridge is exact only because subtyping is gone

`bridge` is an equality of relations, so it is tempting to read it as "Pottier's
concatenation *is* Ermine's partition". That reading is false of the paper's own system.
Interpret the three conditional constraints in Example 1's flat field lattice
`{⊥_field, Abs, Pre, ⊤_field}` with a genuine `≤` (`Sym4`, verified a partial order by
`Sym4.le_refl` / `le_trans` / `le_antisymm`), and the arguments `(Abs, Abs)` admit **both**
`Abs` and `⊤_field` as the result (`concat4_not_functional`,
`concat4_result_underdetermined`). The constraints bound the result only *from below* —
which is all a subtyping system needs. The specialisation is nonetheless provably
faithful on the two values an Ermine row can exhibit (`concat4_iff_bit`), where the
relation *is* functional (`pottierConcatBit_functional`).

The element that destroys exactness is `⊤_field` — precisely the join that Theorem 1
supplies, and precisely the one `no_upper_bound` says the Ermine model lacks. **So the
bridge's exactness is a consequence of dropping subtyping, not something inherited from
the paper.**

#### 7. Pottier's scheme is irreducibly binary

The ternary Ermine partition `a <- (x, y, z)` is **not definable by any conjunction of
Pottier constraints over its own four row variables** (`ternary_not_definable`), proved by
an exhaustive kernel check of all 468 atoms over `{x, y, z, a, ∂Abs, ∂Pre}`: every atom
valid throughout the relation is also valid at `(Abs, Abs, Abs, Pre)`, which is outside it
(`ternary_atom_sound`, `ternary_bad`). Exactly one intermediate variable repairs it
(`ternary_via_one_intermediate`), and the n-ary case is a chain of binary concatenations
(`pchainBit_iff_flat`, `pchainRow_iff_flat`, `sat_iff_pchainRow`).

This **sharpens** the paper's "none of the rules requires fresh variables to be allocated":
that is a property of the *solver* — closure never mints a variable — not of constraint
*generation*, which introduces one row variable per sub-expression, hence one intermediate
per `+` in a nest. Ermine's n-ary partition compresses that nest into a single constraint,
and the price is a relation Pottier's grammar cannot state in one atom.

#### 8. The join-of-lower-bounds witness degenerates twice over

Pottier's Theorem 4 builds its witness as `φ(α) = ⊔ φ(lb_ℓ(α))`, invoking Theorem 1 by
name to supply the least upper bounds. In the Ermine specialisation:

* because `≤` has collapsed to `=`, every constant lower bound of a variable at a label
  equals that variable's value in any model (`lbAt_eq_of_pmodels`), so `lb_ℓ(α)` is empty
  or constant and `⊔` never joins two incomparable things — **the construction reads off a
  forced value, i.e. it is unification**;
* on the encoding of an Ermine system the lower-bound sets are *literally empty*
  (`lbAt_encode`), because `concatSystem` is three **conditional** constraints and contains
  no unconditional subtyping constraint at all (`mem_encodeC`).

So the witness is constant-`Abs` = the everywhere-empty row assignment
(`joinWitness_eq_toPAssign_empty`) — which is exactly `Fragment`'s `models_empty` witness,
reached by a completely different route. `theorem4_analogue` therefore states the Ermine
proposition whose *shape* matches Theorem 4, and proves it by `satisfiable_of_abstract`:
**the statements coincide; the proofs have nothing in common.**

#### 9. Berthomieu's `=_L` cannot express partition — for two independent reasons

No system `Φ` of `Eq` / `EqOut` constraints, over **any** interface and with **any** number
of existentially quantified auxiliary variables, defines `a <- (b, c)`
(`not_defines_partition`); `Φ` is not even required to be finite. The proof is an
invariance argument: inserting one label into *every* variable at once preserves every
`BC` model (`bcModels_insert`) but destroys disjointness. Notably this needs **no freshness
hypothesis at all** — at the inserted label both sides of the biconditional become true
simultaneously. Freshness becomes necessary only once absence literals enter the language
(`bcxModels_insert`).

A second, independent obstruction: the everywhere-empty assignment models **every** `BC`
system (`bcModels_empty`), so `BC` cannot express "this row is nonempty" — which rules out
every partition constraint with a nonempty concrete part on its own.

Together these give a complete **classification** (`defines_partition_iff`): `⟨a, vs, k⟩`
is `BC`-definable **iff** `vs.length = 1` and `k = ∅` — that is, iff it is the degenerate
`a <- (b)`, which is just `a = b` (`defines_unary`). Nothing of Ermine's partition survives
into `BC`. Non-vacuity is certified in the other direction too: `BC` does define `=_L`
itself (`bcDefines_eqOut`).

Adding presence/absence literals — enough to make the language talk about concrete label
sets — **does** buy single-label record extension `a <- (b, (|ℓ|))` (`definesX_extension`),
which is exactly Pottier's cosingleton-filter idiom, but still not `a <- (b, c)`
(`berthomieu_separation`). **The expressiveness boundary lands precisely between
"extension by a KNOWN label" and "disjoint union of two UNKNOWN rows".**

#### 10. …nor row subsumption, and the obstruction is broader than disjointness

Label *insertion* does not refute `Has` (row subsumption `rho b ⊆ rho a`), because
insertion is monotone. A different invariance is needed: **toggling** one label in every
row (symmetric difference with `{ℓ}`), which preserves `=_L` for the same reason insertion
does but reverses inclusions (`bcModels_toggle`, `bcxModels_toggle`). With it, subsumption
is separated too (`not_defines_subset`, `not_definesX_subset`), and `has_iff_subset` /
`exists_partition_iff_subset` confirm that subsumption really is the existential form of
partition. So the obstruction is **not** merely "`=_L` cannot see disjointness".

`sat_two_iff_eqOutside` turns the whole separation into a one-line slogan that is now a
theorem: **Ermine's partition IS `=_L` — with the exception set a *variable* instead of a
constant.** That reframes the negative result as a precise measurement of one missing
degree of freedom rather than a blanket incompatibility.

#### 11. Label count is the wrong cost model, and the general bounds cannot be improved

`wideSchema w` is a three-constraint system over two tables, one of width `w` and one of
width 1. It mentions `w + 1` labels but realises at most **3** signatures, for every `w`
(`wideSchema_width_independent`). Under `Laminar` — blocks pairwise disjoint or equal,
exactly the shape one block per database table produces — the number of Boolean solves is
at most (distinct blocks) + 1, **with no dependence on block width** (`card_sigs_le_blocks`,
`transversal_of_blocks`). The width-independence is not an estimate: under laminarity
`l ∈ c.conc` becomes equivalent to the label-free proposition `c.conc = s`
(`sig_eq_bsig`), so the label variable literally disappears from the signature computation.

Without a shape hypothesis, neither general bound can be improved, and — a result that was
expected to be a prose aside — **both are attained simultaneously by the same witness**.
`genSys k` puts `k` blocks in general position; it realises exactly `2^k` signatures and
mentions exactly `2^k − 1` labels, so the constraint-count bound `2^k` and the label-count
bound `L + 1 = 2^k` coincide (`genSys_bounds_tight`, `card_concLabels_genSys`). Taking the
min of the two buys nothing in the worst case; only the laminar hypothesis helps.
`genSys_not_laminar` confirms the witness is outside the laminar fragment, so §6 is not
vacuously escaping it.

### Two results that came out stronger than expected

* **`entails_iff_abstract` has no side condition.** `Basic`'s `entails_iff_forall_label`
  genuinely needs a satisfiability hypothesis (there is a counterexample). On an abstract
  system, `Fragment`'s F1 (`satisfiable_of_abstract`) discharges it automatically. So on
  exactly the shape all 345 measured stdlib residual constraints have, deciding
  `Entails G c` is **one Boolean implication check at one arbitrary label**, whatever the
  schema. Correspondingly a `satisfiable_iff_abstract` corollary would be vacuous — both
  sides outright true — so it is deliberately not stated.
* **The bridge cannot see an argument/argument swap** — `pottierConcat_comm` is a theorem,
  which is exactly why Pottier's scheme needs only *one* disjointness constraint,
  `𝓛 : Pre ≤ φ₁ ? φ₂ ≤ Abs`, rather than two. It *does* see an argument/result swap
  (`bridge_result_position_sharp`), so the direction that could actually be got wrong is
  certified.

### Headline signatures

```lean
-- Pottier: the bridge, and its whole-system form
bridge (b : Var → Bool) (l : Label) (a x y : Var) :
    BSat b l ⟨a, [x, y], ∅⟩ ↔ PottierConcat b x y a
sat_iff_pmodels_concatSystem (rho : Assign) (a x y : Var) :
    Sat rho ⟨a, [x, y], ∅⟩ ↔ PModels (toPAssign rho) (concatSystem x y a)
models_iff_pmodels (rho) (G) (h : BinAbstract G) :
    Models rho G ↔ PModels (toPAssign rho) (encode G)

-- Pottier: the ternary partition is NOT definable over its own four variables
ternary_not_definable (C : List PAtom) :
    ¬ (∀ p q s r, (∀ A ∈ C, A.eval p q s r = true) ↔ ternary p q s r = true)
ternary_via_one_intermediate (b) (l) (a x y z : Var) :
    BSat b l ⟨a, [x, y, z], ∅⟩ ↔
      ∃ t : Bool, PottierConcatBit (b y) (b z) t ∧ PottierConcatBit (b x) t (b a)

-- Pottier: Theorem 1 fails, and the Theorem 4 witness degenerates
no_upper_bound : ¬ ∃ z : Bool, SymLe Abs z ∧ SymLe Pre z
lbAt_encode (G) (α) (l) : lbAt (encode G) α l = []
joinWitness_eq_toPAssign_empty (G) : joinWitness (encode G) = toPAssign (fun _ => ∅)

-- Pottier: exactness is a consequence of dropping subtyping
concat4_iff_bit (p q r : Bool) :
    Concat4 (Sym4.ofBool p) (Sym4.ofBool q) (Sym4.ofBool r) = true ↔ PottierConcatBit p q r
concat4_not_functional : ¬ ∀ p q r r', Concat4 p q r = true → Concat4 p q r' = true → r = r'

-- Berthomieu: the separation, and the classification
not_defines_partition (S : Set Var) (Φ : BC → Prop) (a b c : Var) :
    ¬ BCDefines S Φ (fun rho => Sat rho ⟨a, [b, c], ∅⟩)
defines_partition_iff (a) (vs) (k) :
    (∃ S Φ, BCDefines S Φ (fun rho => Sat rho ⟨a, vs, k⟩)) ↔ (vs.length = 1 ∧ k = ∅)
berthomieu_separation (S : Set Var) (Φ : List BCX) (a b c : Var) :
    ¬ BCXDefines S Φ (fun rho => Sat rho ⟨a, [b, c], ∅⟩)
definesX_extension (a b : Var) (ℓ : Label) :
    BCXDefines {a, b} [BCX.eqOut {ℓ} a b, BCX.pres ℓ a, BCX.abs ℓ b]
      (fun rho => Sat rho ⟨a, [b], {ℓ}⟩)
sat_two_iff_eqOutside (rho) (a b c : Var) :
    Sat rho ⟨a, [b, c], ∅⟩ ↔
      EqOutside (rho c) (rho a) (rho b) ∧ Disjoint (rho b) (rho c) ∧ rho c ⊆ rho a

-- LabelClass: labels of equal signature are interchangeable, and how many classes there are
bmodels_congr {G l l'} (h : sig G l = sig G l') (b) : BModels b l G ↔ BModels b l' G
entails_iff_abstract {G c} (h : Abstract (c :: G)) (l₀ : Label) :
    Entails G c ↔ ∀ b, BModels b l₀ G → BSat b l₀ c
card_sigs_le (G) : (sigs G).card ≤ min (2 ^ G.length) ((concLabels G).card + 1)
card_sigs_le_blocks {G} (h : Laminar G) : (sigs G).card ≤ (blocks G).toFinset.card + 1
wideSchema_width_independent (w : Nat) :
    (concLabels (wideSchema w)).card = w + 1 ∧ (sigs (wideSchema w)).card ≤ 3
genSys_bounds_tight (k : Nat) :
    min (2 ^ (genSys k).length) ((concLabels (genSys k)).card + 1) = 2 ^ k ∧
      (sigs (genSys k)).card = 2 ^ k
```

### What is proved in Lean, and what is only cited from Pottier's paper

This distinction matters more here than anywhere else in the development, because these
modules name a published paper and could be misread as having verified it. **They have
not.**

**Proved in Lean.** Every row of the three inventory tables below — all 182 theorems —
is a complete machine-checked proof about *Ermine's specialisation*: the bridge and its
sharpness, the n-ary chain, the filter algebra and the "apparent" operator, the
468-atom impossibility, the `Sym4` lattice facts, the degeneration of the lower-bound
construction, the whole Berthomieu separation and classification, and every signature-class
bound. All of it rests only on `propext`, `Classical.choice`, `Quot.sound`.

**Cited, not verified.** Pottier's Definitions 1–8, his Figure 1 constraint grammar, his
Figure 3 satisfaction judgement, his Figure 4 closure rules, and his Theorems 1–7 with
their proofs are **quoted** — in docstrings, from a transcription of the paper read off
300 dpi page images (`pottier-extract.md`, whose own caveats apply). **None of the paper's
theorems is re-proved here, and no claim is made about their correctness in their own
setting.** In particular:

* `no_upper_bound` proves that Theorem 1's *conclusion* fails in the Ermine
  specialisation. It does **not** check Theorem 1's proof, and does **not** contradict it:
  the paper's field lattice contains `⊤_field`, which the Ermine model deliberately lacks.
* `theorem4_analogue` is **not** Pottier's Theorem 4. It is the Ermine proposition whose
  shape matches, and it is proved by `Fragment.satisfiable_of_abstract`. The section's
  point is precisely that the paper's *proof strategy* does not transport.
* Nothing here touches Theorem 2 (closure), Theorem 3, Theorems 5–6, or Theorem 7
  (complexity). Termination and completeness of Pottier's closure are neither used nor
  checked.

**Hand translations, which are modelling assumptions rather than theorems.** Three
definitions render printed notation into Lean by a human reading, and every result stated
over them is exactly as strong as that reading:

1. `Filter'`, `RowTerm`, `PConstr` and `PSat` render §2.3's filters, the term grammar
   `ρ ::= α | ∂φ` and Figure 3's two constraint forms. Faithfulness to the printed paper
   is argued in the module header; it is not a Lean theorem.
2. `PAtom` models "what one Pottier constraint says at one label", and
   `ternary_not_definable` is exactly as strong as that model. The enumeration is
   deliberately *generous* — it lets condition terms and both sides of an equality range
   over constants as well as variables, which Figure 1's sorting partly forbids — so the
   impossibility is if anything understated. **That generosity argument is prose, not
   Lean.**
3. `Sym4` / `Concat4` render Example 1's flat field lattice. `Sym4.le_refl`,
   `le_trans`, `le_antisymm` verify the *rendering* is a genuine partial order; they
   verify nothing about the paper.

**Berthomieu is at one further remove.** The `=_L` device is taken from Pottier & Rémy's
ATTAPL §10.8, which *reports* it and attributes it to Berthomieu; Berthomieu's own
formulation was not consulted. `BC` is a model of the device as reported. The
correspondence to Pottier's filters is, however, proved rather than asserted:
`EqOutside L` is an equality constraint under the cofinite filter `𝓛 \ L`, his fusion law
becomes `EqOutside.inter` and his (TRANS-ROW) rule becomes `EqOutside.trans_union`.

**One motivating claim in `LabelClass.lean` is a design observation, not a measurement.**
That real Ermine projects bind wide database tables, so a table's column set arrives as one
concrete block, is why the width question is asked. `wideSchema` is a *synthetic* witness
built to answer it, not a system extracted from an Ermine program. The corpus figure it
leans on — that all 345 measured stdlib residual constraints are abstract — is the
`Fragment.lean` measurement already listed under [Cited](#cited-empirical-from-outside-lean).

---

## The cut modules: `Cut.lean` and `Compare.lean`

These two modules do not describe the language; they evaluate **one proposed change to
the shipped solver**, and they are the only part of the development aimed at a decision
someone is actually about to take.

### The object of study

`commonSubexpression` (`Constraints.scala:1089`) fires on two partitions `v <- rhs1`,
`u <- rhs2` whose abstract right-hand sides share `int = abstr1 ∩ abstr2` with
`|int| ≥ 2`. It has three branches:

| branch | guard | emits |
|---|---|---|
| **(a) REUSE** | the reverse lookup `rhss(RHSAbstr(int))` returns some `z` | `v <- (abstr1 \ int) ∪ {z} ∪ concr1` and `u <- (abstr2 \ int) ∪ {z} ∪ concr2` |
| **(b) FOLD** | `rhs1` *is* `int` (or symmetrically `rhs2`) | `u <- (abstr2 \ int) ∪ {v} ∪ concr2` |
| **(c) MINT** | otherwise | a **fresh** `z`, plus `z <- int` and both rewritten premises |

**The proposed cut replaces branch (c) with the empty set**, keeping (a) and (b). It is
five lines, and it is already in the source behind a flag: `object GenRules`
(`Constraints.scala:698–702`) reads

```scala
val cseMints: Boolean   = mode == "all"
val splitMints: Boolean = mode == "all" || mode == "cut"
val resolves: Boolean   = mode == "all" || mode == "cut"
```

so the mode literally named `"cut"` is this proposal — and it demonstrably leaves the
other two minting sites switched **on**. That is the whole difficulty, and the modules
were written knowing it.

### What `Cut.lean` settles (117 theorems)

`CutStep` is branches (a) and (b); `CseBranch` is all three, so every cut run is a run of
the full solver (`CutStep.toBranch`).

* **The kept branches are outright entailment.** The core lemma `sat_reduce_of_denotes`
  says: if `rho` satisfies `c` and `z` already denotes the union of a sub-group `S` of
  `c`'s right-hand side, then `rho` *already* satisfies the contracted constraint — no
  freshness side condition, no update of `rho`. Hence `reuse_entails` and `fold_entails`,
  and hence `CutStep.models_iff`: **the model set is literally unchanged**, not merely
  satisfiability, and not merely over the old vocabulary.
* **Branch (c) is sound too**, but the statement has to be different, because it mints:
  `mint_conservativeExt` proves `SConservativeExt`, which `sConservativeExt_iff` shows is
  `Rules.ConservativeExt` transported to finsets.
* **`cut_preserves_meaning`** is the conclusion: any cut run and any full run from the
  same input are equisatisfiable, and over the input's own vocabulary entail exactly the
  same constraints. **Dropping branch (c) cannot change the set of models.**
* **The risk is one-sided.** A `Refuter` is a sound, monotone syntactic error condition —
  the shape of Ermine's rules 10 and 11. `cut_never_wrongly_refutes`: nothing a cut run
  refutes was satisfiable, so **the cut never rejects a well-typed program**.
  `refuter_can_miss`: a sound monotone refuter *can* fire on the larger derived set and
  not the smaller, so the cut can fail to reject an ill-typed one. `cut_risk_is_one_sided`
  conjoins the two.
* **And the sharpest statement of where a lost refutation can come from**, which was not
  asked for: `complete_refuter_unaffected`. A refuter that fires *exactly* on the
  unsatisfiable systems is untouched by any branch, minting included, because every
  branch preserves satisfiability. **Any refutation the cut can lose is attributable
  purely to the incompleteness of Ermine's syntactic error conditions, never to a loss of
  semantic information.** That is the precise sense in which the 23 measured contact
  points of branch (c) with emitted output are or are not dangerous.
* **The kept branches terminate.** They are non-generative (`CutStep.allVars_eq`), they
  derive only entailed contractions of existing constraints (`CutStep.new_constraints`),
  and every productive chain from `G₀` is bounded by `(bound G₀).card`
  (`CutChain.length_le`, `cut_branches_terminate`), where `bound` is an explicit finite
  universe of `mk`-normal constraints over the input's vocabulary and concrete parts.
* **The cut rule set does not terminate** — the honest negative outcome, and §5 locates it
  exactly. See below.
* **None of it is vacuous.** `CutExample.reuse_fires` and `CutExample.fold_fires` exhibit
  systems where each kept branch actually fires, and `cut_removes_something` exhibits one
  where *only* branch (c) can fire — so the cut is not a no-op and the meaning-preservation
  theorem is not about an empty situation.

### The termination obstruction is `resolution`, not `splitConcrete`

This is the most decision-relevant thing in either module, and it refines the caveat the
work started from. Both surviving rules mint, so the finiteness argument dies — but they
do not die the same way.

* **`splitConcrete` (`:816`) takes an `rhss` argument** and mints only when the reverse
  lookup misses — the same lookup that drives branch (a). `SplitStep.cands_lt` turns that
  guard into a strictly decreasing measure: each mint names a group that had no name, and
  neither constraint it emits is itself a candidate (one has an empty concrete part, the
  other arity one), so no new candidate is ever created. **`split_terminates`:
  split-minting alone terminates.**
* **`resolution` (`:1047`) takes no `rhss` argument at all.** It calls `fresh`
  unconditionally on every match. `resSeed_diverges` exploits this: from the
  two-constraint seed `a <- (|1|) x`, `a <- (|2|) y` there are chains of *every* length,
  growing the system by a constraint per step. Hence `res_no_decreasing_measure`, and
  hence `cut_no_decreasing_measure`: **no `ℕ`-valued measure decreases on every step of
  the cut rule set.** `ResStep.escapes` says why §4's argument cannot be repaired — a
  resolution step leaves the finite vocabulary bound on its *first* application.

So `resolution` is the sole unconditionally-minting rule left after the cut. **If the
ticket ever wants termination, `resolution` is the rule to guard, and the guard already
exists elsewhere in the same file.**

### `Compare.lean` (27 theorems): the measure runs backwards

`Compare.lean` imports `Cut.lean` and cites it rather than reproving it, adding what the
comparison needs and neither file had:

* `resStep_canonical_measure_increases`: `Canonical.Meas` — the lexicographic measure
  whose descent *is* the clean calculus's termination proof — strictly **increases** on
  every retained `resolution` step, in its dominant coordinate, with `varsOf_toList`
  bridging to the actual measure rather than a look-alike. With `lexLt_asymm` this gives
  `resStep_canonical_measure_fails`. The clean calculus's argument does not merely fail to
  transfer to the cut; **it is refuted for it.**
* `resSeed_satisfiable`: the divergent seed **has a model**. So the obstruction is not the
  degenerate "unsatisfiable input, anything goes" case — the correct answer on that input
  is *satisfiable*, and no measure argument can certify that the rule ever gets there.
  This materially strengthens `Cut.resSeed_diverges`, which said nothing about models.
* `res_not_model_preserving`: a retained minting step does **not** preserve the model set,
  so the cut's meaning preservation is a weaker claim about a weaker object than
  `Canonical.Step.preserves`. `res_conservative` and `split_conservative` supply the
  weaker claim that does hold, instantiated from `Rules.rule6` and `rule4`.
* `vocabulary_restriction_necessary`: the vocabulary restriction in
  `cut_preserves_meaning`'s entailment clause **cannot be dropped** — a minting step
  entails `z <- x⁺` for its own `z` and the premises do not.
* `full_cut_not_locally_confluent`, `full_cut_not_joinable`,
  `full_cut_normal_form_can_be_unsat`: the cut **inherits** both of `Canonical`'s negative
  results. Inheritance is not free: `FullCutStep` is the clean calculus's six rules *plus*
  all five generative rules the cut retains, so a "normal form" for the cut is a stronger
  claim, and `fullCutNormalForm_of` isolates exactly what must be checked.

### Cut versus clean, side by side

The grid the exercise is for. "Clean calculus" is `Canonical.lean`; "the cut" is
`Cut.lean` together with `Compare.lean`. **A row marked NO means the negative is
*proved*, not that the positive is merely missing** — the one exception is row 1, where
what is proved is rows 1a–1c.

| # | property | clean calculus | THE CUT | theorems (clean \| cut) |
|---|---|---|---|---|
| 1 | terminates | **YES** | **NO** (see 1a–1c) | `Step.decreasing`, `no_infinite_descent` \| `Cut.cut_does_not_terminate` |
| 1a | …under `Canonical.Meas` | descends | ***increases*** | `Step.decreasing` \| `resStep_canonical_measure_increases`, `…_fails` |
| 1b | …under *any* `ℕ` measure | has one | **none exists** | (`Meas` is one) \| `Cut.cut_no_decreasing_measure` |
| 1c | …is the bad input at least unsat? | — | **no, it has a model** | — \| `resSeed_satisfiable` + `Cut.resSeed_diverges` |
| 1d | …kept CSE branches alone | (n/a) | **YES** | — \| `Cut.cut_branches_terminate`, `Cut.CutChain.length_le` |
| 1e | …`splitConcrete` alone | (n/a) | **YES** | — \| `Cut.split_terminates` |
| 1f | …`resolution` alone | (n/a) | **NO** | — \| `Cut.res_no_decreasing_measure` |
| 2 | model sets preserved, *every* rule | **YES** | **NO** | `Step.preserves` \| `res_not_model_preserving` |
| 2a | …on the kept CSE branches | (n/a) | **YES** | — \| `Cut.CutStep.models_iff` |
| 2b | …on the retained minting rules | (n/a) | **NO** — conservative ext only | — \| `res_conservative`, `split_conservative` |
| 2c | loses no consequence vs. uncut | (n/a) | **YES**, over input vocabulary | — \| `Cut.cut_preserves_meaning` |
| 2d | …may that restriction be dropped? | (n/a) | **NO** | — \| `vocabulary_restriction_necessary` |
| 3 | confluent | **NO** | **NO**, inherited | `not_locally_confluent`, `not_joinable` \| `full_cut_not_locally_confluent`, `full_cut_not_joinable` |
| 4 | decides satisfiability | **NO** | **NO**, inherited | `normal_form_can_be_unsat` \| `full_cut_normal_form_can_be_unsat` |
| 5 | never wrongly refutes | (n/a) | **YES** | — \| `Cut.cut_never_wrongly_refutes` |
| 6 | can miss a refutation | (n/a) | **YES**, but only via incomplete checks | — \| `Cut.refuter_can_miss`, `Cut.complete_refuter_unaffected` |

Unqualified names in the "clean" column live in `Canonical.lean`; unqualified names in the
"cut" column live in `Compare.lean`. `Compare.bottom_line` conjoins rows 1, 1b, 1c, 1d,
1a, 2, 2a, 3 and 4 into a single theorem, so the grid is machine-checked as a unit and not
only row by row.

### The verdict the two modules support

**The cut is a real improvement and a principled one *locally*.** The branch it deletes is
exactly the one with no decreasing measure (`Divergence.no_decreasing_measure`); the
branches it keeps are non-generative, exactly meaning-preserving, and terminating. Its
risk is one-sided, and any refutation it could lose is a consequence of Ermine's error
conditions being incomplete, not of information being thrown away.

**It is not a principled *calculus*.** It does not deliver termination and cannot, because
the very flag that turns `cseMints` off leaves `splitMints` and `resolves` on, and
`resolution` mints unconditionally. A termination theorem for Ermine's row solver requires
cutting all three minting sites — which is `Canonical`'s rule set. What the clean calculus
proves and the cut does not is exactly one thing, and it is the thing the exercise was
about.

### What the cut modules do NOT settle

Recorded because both modules state it and a reader should not have to infer it:

* **Whether the cut changes what Ermine *infers*.** Row 2c is about entailment over the
  input vocabulary. Ermine's residual partitions become part of an inferred type, and the
  23 measured splices of branch-(c) output into committed output are syntactic changes no
  theorem here models.
* **Whether any real refutation depends on a minted variable.** §3's sound monotone
  refuter that fires only on the larger system is hand-built, *not* derived by a MINT
  step. That the 23 contact points ever change a refutation is empirical and unsettled.
* **Whether the cut terminates on the systems Ermine's front end actually emits.**
  `resSeed` is a legal *and satisfiable* system; whether the front end can emit two
  partitions of one variable with single abstract parts and incomparable concrete parts is
  empirical. What is proved is that no measure argument can rule it out. (Measured,
  `resolution` and `splitConcrete` fire **zero** times in a 129-module boot — an empirical
  answer, and not a termination theorem.)
* **Interleaving.** `CutChain`s are (a)/(b)-only, `SplitSteps` split-only, `ResSteps`
  resolution-only. `FullCutStep` puts every rule in one relation but is used only for
  normal forms, where interleaving cannot arise. The split measure of §5.2 is **not**
  invariant under REUSE steps, which can create new split candidates.
* **Whether §3's non-confluence survives a purely *additive* reading** of the
  non-generative rules. It is stated for `Canonical`'s replacing reading; read additively
  this particular critical pair would join. No additive form of the six rules is defined
  anywhere in the development, so the question is open, not answered.

### One faithfulness note, added during integration

Both modules gloss branch (b) as "branch (a) in disguise", on the strength of
`Cut.fold_names`: under FOLD's guard the premise `c₁` *is* a naming constraint for the
shared block, and the one conclusion REUSE would additionally emit is the vacuous
self-partition `a <- a` (`fold_first_conclusion_vacuous`). **That is a theorem about the
model and about the rule, and it is correct as such** — but it should not be read as a
claim that Ermine's REUSE branch would have fired first. In the Lean model `CsePair.mem₁`
puts `c₁` inside `G`, which is what makes `Named G (shared c₁ c₂)` hold. In the Scala the
lookup is `findRHS(incm, proc, s)` (`:748`) over the incoming queue, the processed queue
and the accumulator, while `learnPartitions` (`:833`) is called with `v <- rhs1` as "the
rule we're about to add" — so the premise is in **none** of the three. That is precisely
why FOLD is reachable in the real solver rather than shadowed by REUSE: **it is live
code.** A note to this effect was added to `Cut.lean` §1; no theorem changed.

---

## Headline theorems, with their signatures

```lean
-- Basic: satisfaction is pointwise in the label
sat_iff_forall_label (rho : Assign) (c : Constraint) :
    Sat rho c ↔ ∀ l : Label, BSat (proj rho l) l c

satisfiable_iff_forall_label (G : List Constraint) :
    (∃ rho, Models rho G) ↔ ∀ l : Label, ∃ b, BModels b l G

entails_iff_forall_label {G c} (hsat : ∃ rho, Models rho G) :
    Entails G c ↔ ∀ (l : Label) (b : Var → Bool), BModels b l G → BSat b l c

-- Rules: the sharp, sound form of resolution (what Constraints.scala computes)
rule6 {a x y z C D E} (h₁ : Disjoint C D) (h₂ : Disjoint D E)
    (ha : a ≠ z) (hx : x ≠ z) (hy : y ≠ z) :
  ConservativeExt [⟨a,[x],C ∪ D⟩, ⟨a,[y],D ∪ E⟩] z
                  [⟨a,[z],C ∪ D ∪ E⟩, ⟨x,[z],E \ C⟩, ⟨y,[z],C \ E⟩]

-- Rules: the header comment's version turns a satisfiable system unsatisfiable
Rule6Header.header_not_conservative : ¬ ConservativeExt G0 3 Gheader
Rule6Header.header_makes_unsat :
    (∃ rho, Models rho G0) ∧ ¬ ∃ rho, Models rho (G0 ++ Gheader)

-- Canonical: termination + exact meaning preservation + a real normal form
Step.decreasing        {s s'} : Step s s' → LexLt (Meas s'.cs) (Meas s.cs)
no_infinite_descent    (f : ℕ → State) : (∀ i, Step (f i) (f (i+1))) → False
Step.preserves         {s s'} : Step s s' → ∀ rho, Models rho s.toSystem ↔ Models rho s'.toSystem
canonicalise_normalForm (s : State) :
    ∃ t, NormalForm t ∧ ∀ rho, Models rho t.toSystem ↔ Models rho s.toSystem

-- Canonical: confluence is FALSE
CriticalPair.not_locally_confluent :
    Step S S1 ∧ Step S S2 ∧ S1 ≠ S2 ∧ NormalForm S1 ∧ NormalForm S2
CriticalPair.not_joinable : ¬ ∃ t, Steps S1 t ∧ Steps S2 t

-- Divergence: the search is conservative, unbounded, and exponentially wide
CseSteps.entails_iff {n G₀ G} (h : CseSteps n G₀ G) {c} :
    c.lhs ∈ allVars G₀ → vset c ⊆ allVars G₀ → (SEntails G c ↔ SEntails G₀ c)
no_decreasing_measure : ¬ ∃ μ : System → ℕ, ∀ G G', CseStep G G' → μ G' < μ G
coStar_card_lower {m G} : CseClosed G → coStar m ⊆ G → 2 ^ m ≤ G.card + m + 2
coStar_seven      {G}   : CseClosed G → coStar 7 ⊆ G → 119 ≤ G.card

-- Fragment: the definitional fragment is decidable
satisfiable_of_abstract {G} : Abstract G → ∃ rho, Models rho G
sat_leaves (rho) (G) : Models rho G → ∀ a, Sat rho ⟨a, leaves G a, kern G a⟩
entails_iff_test {G c} : IsDefList G → Abstract G → Linear G → c.conc = ∅ →
    (Entails G c ↔ Test G c)
decidableEntails {G c} (hG : IsDefList G) (habs : Abstract G) (hlin : Linear G)
    (hc : c.conc = ∅) : Decidable (Entails G c)
```

The two cut modules, verbatim:

```lean
-- Cut: the core lemma. No freshness, no disjointness side condition.
sat_reduce_of_denotes {rho : Assign} {c : Constraint} {S : Finset Var} {z : Var}
    (hc : Sat rho c) (hS : S ⊆ vset c) (hz : rho z = S.biUnion rho) :
    Sat rho (reduce c S z)

-- Cut: the kept branches leave the MODEL SET unchanged, not merely satisfiability
CutStep.models_iff {G G' : System} (h : CutStep G G') (rho : Assign) :
    SModels rho G ↔ SModels rho G'

-- Cut: dropping branch (c) cannot change the set of models
cut_preserves_meaning {n m : ℕ} {G₀ Gcut Gfull : System}
    (hcut : CutSteps n G₀ Gcut) (hfull : BranchSteps m G₀ Gfull) :
    ((∃ rho, SModels rho Gcut) ↔ (∃ rho, SModels rho Gfull)) ∧
      ∀ c : Constraint, c.lhs ∈ allVars G₀ → vset c ⊆ allVars G₀ →
        (SEntails Gcut c ↔ SEntails Gfull c)

-- Cut: a COMPLETE refuter is untouched by any branch, minting included
complete_refuter_unaffected {G G' : System} (h : CseBranch G G') (R : System → Prop)
    (hcomp : ∀ H : System, R H ↔ ¬ ∃ rho, SModels rho H) : R G ↔ R G'

-- Cut: the kept branches terminate on a fixed vocabulary
CutChain.length_le {n : ℕ} {G₀ G : System} (h : CutChain n G₀ G) :
    G₀.card + n ≤ (bound G₀).card

-- Cut: splitConcrete's reverse lookup IS a decreasing measure
SplitStep.cands_lt {G G' : System} (h : SplitStep G G') :
    (splitCands G').card < (splitCands G).card

-- Cut: THE NEGATIVE RESULT. No N-valued measure decreases on every cut-rule step.
cut_no_decreasing_measure :
    ¬ ∃ μ : System → ℕ, ∀ G G', CutRule G G' → μ G' < μ G

-- Compare: Canonical's own measure runs BACKWARDS on a retained rule
Compare.resStep_canonical_measure_increases {G G' : System} (h : ResStep G G') :
    LexLt (Meas G.toList) (Meas G'.toList)

-- Compare: ... and the input on which it happens has a model
Compare.resSeed_satisfiable : ∃ rho, SModels rho resSeed
```

Read the signatures carefully; three of them are weaker than the prose around them might
suggest, and deliberately so:

* `coStar_card_lower` is a statement about **`CseClosed` systems** — a fixpoint
  condition. It does not assert that the solver reaches the fixpoint. The dichotomy is
  nevertheless complete: either the solver saturates, and the bound applies, or it does
  not, and `no_decreasing_measure` says no `ℕ`-valued measure can certify that it ever
  will.
* `entails_iff_test` requires the *conclusion* to be abstract too (`c.conc = ∅`), not
  just the system.
* `canonicalise` (the older, weaker form kept in the file) concludes `stepFn t = none`.
  `canonicalise_normalForm` is the one that concludes `NormalForm t`. See
  [Integration log](#integration-log) for why both exist.

---

## Axiom audit

The check that matters: a theorem can compile and still depend on `sorryAx`. It was run
over **every** declaration in every module, by walking the environment and calling
`Lean.collectAxioms`, not by spot-checking:

```
constants in the `Rowpartition` namespace scanned: 1951   (auto-generated ones included)
of which named theorems:                            714
declarations depending on sorryAx:                    0
custom axioms declared:                               0   (grep '^axiom' Rowpartition/ -> none)
literal `sorry` / `admit` in sources:                 0
`native_decide` occurrences:                          0   (so no Lean.ofReduceBool)
```

`collectAxioms` is transitive, so the 0 above also covers every auxiliary definition,
match-arm and equation lemma that the 714 theorems rest on.

Axiom sets observed, over the 714 theorems:

| axiom set | count |
|---|---|
| `propext, Classical.choice, Quot.sound` | 612 |
| `propext, Quot.sound` | 68 |
| `propext` | 24 |
| none | 10 |

Restricted to the 182 theorems of the three comparison modules: 147 / 11 / 16 / 8.
Restricted to the **144 theorems of the two cut modules: 142 / 2 / 0 / 0** — `Cut.lean`
is 116 / 1 / 0 / 0 and `Compare.lean` 26 / 1 / 0 / 0, the two `propext, Quot.sound`
entries being `Cut.SplitApp.conc_ne` (a structure projection) and `Compare.lexLt_asymm`.
**No theorem anywhere in the development depends on `sorryAx`**, and the check was re-run
over all eleven modules after integration, not inherited from the nine-module state.

Every headline theorem of the two new modules was additionally checked one at a time with
`#print axioms`, and **all 55 report exactly `[propext, Classical.choice, Quot.sound]`** —
a subset of the three standard axioms, with nothing else present:

```
'Rowpartition.sat_reduce_of_denotes'                 [propext, Classical.choice, Quot.sound]
'Rowpartition.reuse_entails'                         [propext, Classical.choice, Quot.sound]
'Rowpartition.fold_entails'                          [propext, Classical.choice, Quot.sound]
'Rowpartition.fold_first_conclusion_vacuous'         [propext, Classical.choice, Quot.sound]
'Rowpartition.mint_conservativeExt'                  [propext, Classical.choice, Quot.sound]
'Rowpartition.sConservativeExt_iff'                  [propext, Classical.choice, Quot.sound]
'Rowpartition.CutStep.models_iff'                    [propext, Classical.choice, Quot.sound]
'Rowpartition.cut_preserves_meaning'                 [propext, Classical.choice, Quot.sound]
'Rowpartition.unsat_mono'                            [propext, Classical.choice, Quot.sound]
'Rowpartition.unsat_not_antitone'                    [propext, Classical.choice, Quot.sound]
'Rowpartition.cut_never_wrongly_refutes'             [propext, Classical.choice, Quot.sound]
'Rowpartition.refuter_can_miss'                      [propext, Classical.choice, Quot.sound]
'Rowpartition.complete_refuter_unaffected'           [propext, Classical.choice, Quot.sound]
'Rowpartition.cut_risk_is_one_sided'                 [propext, Classical.choice, Quot.sound]
'Rowpartition.CutStep.allVars_eq'                    [propext, Classical.choice, Quot.sound]
'Rowpartition.CutStep.new_constraints'               [propext, Classical.choice, Quot.sound]
'Rowpartition.CutChain.length_le'                    [propext, Classical.choice, Quot.sound]
'Rowpartition.cut_branches_terminate'                [propext, Classical.choice, Quot.sound]
'Rowpartition.resSeed_diverges'                      [propext, Classical.choice, Quot.sound]
'Rowpartition.res_no_decreasing_measure'             [propext, Classical.choice, Quot.sound]
'Rowpartition.ResStep.escapes'                       [propext, Classical.choice, Quot.sound]
'Rowpartition.SplitStep.cands_lt'                    [propext, Classical.choice, Quot.sound]
'Rowpartition.split_terminates'                      [propext, Classical.choice, Quot.sound]
'Rowpartition.cut_no_decreasing_measure'             [propext, Classical.choice, Quot.sound]
'Rowpartition.cut_does_not_terminate'                [propext, Classical.choice, Quot.sound]
'Rowpartition.cut_removes_something'                 [propext, Classical.choice, Quot.sound]
'Rowpartition.CutExample.reuse_fires'                [propext, Classical.choice, Quot.sound]
'Rowpartition.CutExample.fold_fires'                 [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.varsOf_toList'                 [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.resStep_canonical_measure_increases'  [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.resStep_canonical_measure_fails'      [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.resSeed_satisfiable'           [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.termination_separation'        [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.res_not_model_preserving'      [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.res_conservative'              [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.split_conservative'            [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.vocabulary_restriction_necessary'     [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.preservation_strength'         [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.fullCutNormalForm_of'          [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.full_cut_not_locally_confluent'       [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.full_cut_not_joinable'         [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.full_cut_normal_form_can_be_unsat'    [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.full_cut_normal_S1'            [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.full_cut_normal_S2'            [propext, Classical.choice, Quot.sound]
'Rowpartition.Compare.bottom_line'                   [propext, Classical.choice, Quot.sound]
```

(Also checked and identical: `fold_names`, `foldResult_eq`, `fold_symm`,
`CutSteps.models_iff`, `CutStep.satisfiable_iff`, `CutStep.conservativeExt`,
`CseBranch.satisfiable_iff`, `CseBranch.entails_iff`, `CutSteps.allVars_eq`,
`card_vset_reduce_lt`.)

`#print axioms` on the headline theorems, verbatim:

```
'Rowpartition.sat_iff_forall_label' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.satisfiable_iff_forall_label' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.entails_iff_forall_label' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Counterexample.entails_not_pointwise' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Sat.eq_empty_of_dup' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rsat_iff_flatten' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule1_unsat' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule4' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule5' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule5_needs_shared_conc' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule6' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule6_back' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule6_swapped' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule6_swapped_needs_disjoint' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Rule6Header.header_not_conservative' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Rule6Header.header_makes_unsat' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule7' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule8' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule9' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule10' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.rule11' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Step.preserves' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Step.decreasing' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.no_infinite_descent' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.canonicalise' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.canonicalise_normalForm' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.stepFn_complete' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.exists_fuel' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.sat_absorb' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.absorb_guard_needed' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.unsat_of_occurs' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.CriticalPair.not_locally_confluent' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.CriticalPair.not_joinable' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.CriticalPair.normal_form_can_be_unsat' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Orientation.results_differ' depends on axioms: [propext, Quot.sound]
'Rowpartition.coStar_card_lower' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.coStar_card_lower'' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.coStar_seven' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.no_decreasing_measure' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.cseStep_measures_increase' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.seed_diverges' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.joinTriple_diverges' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.CseStep.extend' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.CseSteps.entails_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.coStar_residual' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.coStar_satisfiable' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.satisfiable_of_abstract' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.entails_iff_forall_label_of_abstract' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.sat_leaves' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.leaves_idem' depends on axioms: [propext, Quot.sound]
'Rowpartition.leaves_def' depends on axioms: [propext, Quot.sound]
'Rowpartition.leaf_of_mem_leaves' depends on axioms: [propext, Quot.sound]
'Rowpartition.entails_of_test' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.test_of_entails' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.entails_iff_test' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.decidableEntails' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.NonLinear.entails_not_test' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.NotDefinitional.entails_not_test' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Worked.entails' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Worked.not_entails'' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.bridge' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.sat_iff_pmodels_concatSystem' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.bridge_result_position_sharp' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.pottierConcat_comm' depends on axioms: [propext]
'Rowpartition.Pottier.pchainBit_iff_flat' depends on axioms: [propext, Quot.sound]
'Rowpartition.Pottier.pchainRow_iff_flat' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.sat_iff_pchainRow' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.ternary_via_one_intermediate' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.ternary_atom_sound' does not depend on any axioms
'Rowpartition.Pottier.ternary_not_definable' does not depend on any axioms
'Rowpartition.Pottier.sat_iff_filter_split' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.models_iff_pmodels' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.satisfiable_iff_psatisfiable' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.models_iff_filter_and_chain' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.no_upper_bound' depends on axioms: [propext]
'Rowpartition.Pottier.lbAt_eq_of_pmodels' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.lbAt_encode' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.joinWitness_eq_toPAssign_empty' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.theorem4_analogue' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.pmodels_joinWitness' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.concat4_iff_bit' depends on axioms: [propext]
'Rowpartition.Pottier.concat4_not_functional' depends on axioms: [propext]
'Rowpartition.Pottier.pottierConcatBit_functional' depends on axioms: [propext]
'Rowpartition.Pottier.Filter'.apparent_union_subset' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.Filter'.apparent_union_ne' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.Pottier.psat_sub_full' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bsat_iff_bsatBit' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bmodels_iff_bmodelsSig' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bmodels_congr' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bmodels_ext' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.satisfiable_iff_transversal' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.entails_iff_transversal' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.satisfiable_iff_sigs' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.entails_iff_abstract' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.mem_sigs_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.card_sigs_le_two_pow' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.card_sigs_le_labels' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.card_sigs_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.satisfiable_decided_by_reps' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.sig_eq_bsig' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.card_sigs_le_blocks' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.transversal_of_blocks' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.wideSchema_width_independent' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.card_sigs_genSys' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.genSys_bounds_tight' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.genSys_not_laminar' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.EqOutside.reconstruct' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.eq_iff_inter_of_eqOutside' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bcModels_insert' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.not_bcDefines_of_pointwise' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.not_defines_partition' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.not_defines_partition_list' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.not_defines_partition_noaux' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bcModels_empty' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bcDefines_empty' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.defines_partition_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.defines_unary' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bcDefines_eqOut' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.berthomieu_separation' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.definesX_extension' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bcxModels_insert' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.not_defines_eqOutside_of_isEq' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.eqOutside_conc_of_sat' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.eqOutside_leaves' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.eq_leaves_of_abstract' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.sat_two_iff_eqOutside' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.sat_ext_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bcModels_toggle' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.bcxModels_toggle' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.has_iff_subset' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.not_defines_subset' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.not_definesX_subset' depends on axioms: [propext, Classical.choice, Quot.sound]
```

To reproduce the sweep:

```bash
export PATH="$HOME/.elan/bin:$PATH"
cd ermine-scala/tracker/lean
cat > /tmp/audit.lean <<'EOF'
import Rowpartition
open Lean Elab Meta in
#eval show CoreM Unit from do
  let env ← getEnv
  for (n, _) in env.constants.toList do
    if (`Rowpartition).isPrefixOf n then
      if (← collectAxioms n).contains ``sorryAx then IO.println s!"SORRY: {n}"
  IO.println "audit done"
EOF
lake env lean /tmp/audit.lean
```

---

## Remaining gaps

**There are none of the `sorry` kind.** For completeness, the honest list of things a
reviewer might expect to find and will not:

| # | gap | kind |
|---|---|---|
| 1 | `sorry`, `admit`, or a custom `axiom` anywhere | **none exist** |
| 2 | Genuinely-fresh-name version of `coStar_card_lower` | paper-level remark, `Divergence.lean` §5 |
| 3 | That a totalised `occurs` rule restores confluence | conjecture, `Canonical.lean` §11 |
| 4 | That `Constraints.scala` computes the `rule6` form | read from Scala source, not formalised |
| 5 | Cancellation and definitional substitution as `Step` constructors | not implemented |
| 6 | Conservativity of the *other* generative rules | not attempted |
| 7 | Any upper bound on saturation size | not attempted |
| 8 | An unsatisfiable *definitional* system with concrete labels | described in prose, not formalised |
| 9 | Any of Pottier's own Theorems 1–7, re-proved in his setting | **not attempted** — quoted only; see [what is cited](#what-is-proved-in-lean-and-what-is-only-cited-from-pottiers-paper) |
| 10 | That `PAtom` faithfully enumerates Figure 1's per-label atoms | hand translation, argued in prose in `Pottier.lean` §11 |
| 11 | That `Filter'` / `PConstr` / `PSat` faithfully render §2.3 and Figure 3 | hand translation, argued in `Pottier.lean`'s header |
| 12 | Berthomieu's original formulation of `=_L` | not consulted; `BC` models the device as *reported* in ATTAPL §10.8 |
| 13 | That a `Laminar` system is what Ermine actually generates from table bindings | design observation; `wideSchema` is a synthetic witness |
| 14 | Whether `bmodels_congr` can be upgraded to an iff | **it cannot** — equal signatures are sufficient but not necessary for interchangeability (two labels can pose different but equally unsatisfiable problems); recorded in `LabelClass.lean`, converse not formalised |
| 15 | Termination of the cut rule set | **refuted, not missing** — `Cut.cut_no_decreasing_measure`; see rows 1–1f of [the grid](#cut-versus-clean-side-by-side) |
| 16 | That the 23 measured branch-(c) contact points ever change a refutation | empirical; §3's witness is hand-built, not MINT-derived (`Cut.lean` §7) |
| 17 | Whether Ermine's front end can emit `Cut.resSeed` | empirical; the seed is legal *and satisfiable* (`Compare.resSeed_satisfiable`) |
| 18 | Interleaved cut chains | not analysed — chains are per-rule; the §5.2 split measure is **not** REUSE-invariant (`Cut.lean` §7) |
| 19 | Whether non-confluence survives an *additive* reading of the six rules | **open in both directions** — no additive form is defined anywhere (`Compare.lean` §5) |
| 20 | Whether the cut changes what Ermine *infers* (as opposed to entails) | not modelled — row 2c is about entailment over the input vocabulary |

---

## Integration log

The five substantive modules were written in parallel against a shared `Basic.lean`.
Integrating them required exactly two changes, both recorded here so that a reviewer can
diff them against the parallel authors' own reports:

1. **Name collision: `Steps`.** `Canonical.lean` and `Divergence.lean` each declared an
   inductive `Rowpartition.Steps` (reflexive-transitive closure of their respective step
   relations). Two modules cannot declare the same constant and both be imported;
   `import Rowpartition.Divergence` failed with
   `environment already contains 'Rowpartition.Steps.below' from Rowpartition.Canonical`.
   `Divergence.lean`'s copy was renamed **`CseSteps`** (matching its `CseStep`), affecting
   `CseSteps.subset`, `CseSteps.entails_iff`, `CseSteps.satisfiable_iff` and their uses.
   `Canonical.lean` keeps `Steps`. An exhaustive constant-level collision check
   (comparing per-module declaration sets, auto-generated names included) found no other
   clash: the earlier collisions the parallel authors reported (`upd`, `sat_mk`,
   `sat_congr`) had already been resolved by them into `setVar`, `sat_mk_iff`,
   `sat_congr_of_agree`.
2. **A prose/theorem mismatch, now closed.** `Canonical.lean`'s header claimed
   "`exists_fuel` [says] that the fuelled driver always reaches a normal form", but
   `exists_fuel` and `canonicalise` concluded only `stepFn t = none` — *the
   implementation found no move* — and there was no theorem that `stepFn` is exhaustive.
   `stepFn_sound` (implementation ⟹ rule) had no converse. Added:
   `firstSome_eq_none`, `stepFn_eq_none`, **`stepFn_complete : stepFn s = none →
   NormalForm s`** (by replaying each of the six `Step` constructors against the
   corresponding `try…` search), and **`canonicalise_normalForm`**. The original
   `canonicalise` is retained unchanged so nothing downstream shifts. This is the only
   mathematical content added during integration.

No proof was weakened, no statement was altered, and nothing was replaced by `sorry`.

`Rowpartition.lean` was written to import all six modules.

### Second round: the three comparison modules

`Berthomieu.lean`, `Pottier.lean` and `LabelClass.lean` were likewise written in parallel
against `Basic.lean` (`Berthomieu` and `LabelClass` also import `Fragment`, `Pottier`
imports `Fragment`). Importing all nine from the root exposed **two constant collisions**,
both of them cases where two modules had independently proved the *same lemma*:

3. **`Rowpartition.exists_fresh`** — declared in `Divergence.lean` for a fresh `Var` and
   in `Berthomieu.lean` for a fresh `Label`. Since `Var` and `Label` are both `abbrev`s
   for `ℕ`, these were literally the same statement with the same proof.
   `import Rowpartition.Berthomieu` failed with `environment already contains
   'Rowpartition.exists_fresh' from Rowpartition.Divergence`.
4. **`Rowpartition.models_append`** — declared in `Rules.lean` (resolution toolkit) and
   in `Canonical.lean` (`State.toSystem` is a concatenation), again the same statement.
   This one was latent: it had never surfaced, because nothing had yet imported both
   modules together. **The root had never been built successfully with every module
   present.**

Both were resolved by **promoting the shared lemma into `Basic.lean`** and deleting the
three duplicate copies, rather than by renaming. That is why `Basic.lean` gains two
theorems (54 → 56) while `Rules.lean` (98 → 97) and `Divergence.lean` (87 → 86) each lose
one; `Canonical.lean`'s copy was never listed in the inventory, so its count is unchanged
at 88. The net change to the pre-existing total is **zero**: it is still 388. No use site
needed editing — both lemmas resolve from `Basic` with the same implicit arguments.

`Basic.lean` needed one extra import for the promoted `exists_fresh`,
`Mathlib.Data.Finset.Lattice.Fold` (for `Finset.sup` / `Finset.le_sup`); it was already in
the library's dependency cone via `Divergence`, `Berthomieu` and `Pottier`.

An exhaustive constant-level collision check over all nine modules found no other clash.
No proof was weakened, no statement was altered, and nothing was replaced by `sorry`.

`Rowpartition.lean` now imports all nine modules.

### Third round: the two cut modules

`Cut.lean` and `Compare.lean` were written in parallel against `Basic.lean`, `Rules.lean`,
`Canonical.lean` and `Divergence.lean`. This round was the cleanest of the three:
**`lake build` succeeded on the first attempt, 795 jobs, 0 errors, and every file
type-checks standalone.** No proof was weakened, no statement altered, nothing replaced by
`sorry`. Four things are worth recording.

5. **A name collision was avoided by the author, and the single-file check would not have
   caught it.** `Cut.lean` needed a finite universe of `mk`-normal constraints; the
   natural names `Rowpartition.canon` / `mem_canon` were already taken by `Fragment.lean`
   for a *different* notion (the canonical assignment of the definitional fragment). They
   are called **`normalForms` / `mem_normalForms`** instead. Note that
   `lake env lean Rowpartition/Cut.lean` does **not** detect this, because `Cut.lean` does
   not import `Fragment.lean` — only `lake build` (or importing the root) does, which is
   the point made under [Building](#building) and is why both checks are run.
6. **The cut is modelled twice, independently, and that is deliberate.** `Compare.lean`
   was begun before `Cut.lean` existed and initially reproved §1–2 from the Scala source
   directly — reaching the same architecture (a finite `closure`/`bound` universe with a
   cardinality measure) and the same core lemma. On discovering the overlap its author
   **deleted the duplicates and rewrote `Compare.lean` to import and cite `Cut.lean`**,
   which is why it is 641 lines rather than ~960. The two files agree on every shared
   conclusion; `Compare.lean` keeps everything inside `namespace Rowpartition.Compare`, so
   the handful of deliberately parallel names (`resSeed`-related lemmas) do not clash.
7. **Two lemmas were added during integration**, the only mathematical content added this
   round. `Constraints.scala`'s `commonSubexpression` has **two** fold cases,
   `rhs1 == rhsCommon` and `rhs2 == rhsCommon`, and `Cut.CutStep.fold` models only the
   first. `shared_comm` (`shared` is symmetric, since it is an intersection),
   `CsePair.symm` and **`fold_symm`** together show the second case is a derivable
   *instance* of the first, so modelling one loses nothing. Previously this was true but
   nowhere stated, and a reader had no way to check that the model covered the rule.
8. **A prose gloss was qualified.** Both modules describe branch (b) as branch (a) "in
   disguise". The theorem behind it (`fold_names`) is correct, but the gloss invited the
   reading that Ermine's REUSE branch would always fire first, which is **false** — the
   Scala's reverse lookup does not see the partition being added, which is exactly why
   FOLD is live code. A note was added to `Cut.lean` §1 and is reproduced under
   [One faithfulness note](#one-faithfulness-note-added-during-integration). No theorem
   changed.

`Rowpartition.lean` now imports all eleven modules. The eleven-module total is **714**
theorems: the previous 570, plus 117 from `Cut.lean` and 27 from `Compare.lean`. The
pre-existing per-module counts are unchanged.

**A note on the theorem counts.** The per-module numbers are produced by walking the
environment and counting non-internal `thmInfo` constants, excluding compiler-generated
equation lemmas (`.eq_N`, `.eq_def`), `.injEq` / `.inj` / `.sizeOf_spec` / `.ofNat_ctorIdx`
and friends. That method reproduces the first round's published numbers for `Basic`,
`Rules`, `Divergence` and `Fragment` exactly. It reports **89** for `Canonical` where the
first round published 88 — the extra one is precisely the duplicated `models_append`, which
the first round's inventory table omitted. With that lemma now gone, the two agree at 88.

---

## Complete inventory

Every named theorem in the development, in source order, with its axiom set. **All 714
are fully proved; none depends on `sorryAx`.** Axiom codes: `p` = `propext`,
`c` = `Classical.choice`, `q` = `Quot.sound`, `—` = no axioms at all.

`example`s are not listed (they are anonymous): `Basic.lean` has 2 non-vacuity checks,
`Canonical.lean` 4 computational checks of the §13 worked example, `Sanity.lean` 1.
`Cut.lean` and `Compare.lean` have none — their non-vacuity checks are named theorems
(`Cut.CutExample.reuse_fires`, `Cut.CutExample.fold_fires`, `Cut.cut_removes_something`,
`Compare.resSeed_satisfiable`), which is why they appear in the tables below.

The two cut modules are listed last, in the order they were integrated, matching how the
three comparison modules were appended in the second round.

### `Basic.lean` — 56 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `mem_foldr_union` | Membership in a `foldr`-union of a list of finsets. | yes | p c q |
| 2 | `foldr_or_eq_true` | A `foldr`-or of a list of booleans is `true` iff some entry is. | yes | p |
| 3 | `bool_eq_iff` | Boolean equality is equality of the two `= true` propositions. | yes | p |
| 4 | `pairwise_congr` | `Pairwise` respects pointwise equivalence of relations. | yes | p |
| 5 | `pairwise_forall_comm` | A universally quantified relation is pairwise iff it is pairwise at every index. | yes | p q |
| 6 | `pairwise_of_forall_mem` | A relation holding between all pairs of members holds pairwise. | yes | p |
| 7 | `pairwise_ne_imp` | From a symmetric pairwise relation, any two DISTINCT members are related. | yes | p |
| 8 | `pairwise_self_of_two_le_count` | A value occurring at least twice in a pairwise list is related to ITSELF. | yes | p q |
| 9 | `Sat.eq_union` | First projection of `Sat`: the union equation. | yes | p c q |
| 10 | `Sat.pairwise` | Second projection of `Sat`: pairwise disjointness of the parts. | yes | p c q |
| 11 | `mem_parts_conc` | The concrete part is one of the parts. | yes | p q |
| 12 | `mem_parts_of_mem_vars` | The row of a right-hand variable is one of the parts. | yes | p q |
| 13 | `Sat.mem_lhs_iff` | Membership characterisation of the left-hand row. | yes | p c q |
| 14 | `Sat.subset_lhs` | Every variable part is contained in the left-hand row. | yes | p c q |
| 15 | `Sat.conc_subset_lhs` | The concrete part is contained in the left-hand row. | yes | p c q |
| 16 | `Sat.pairwise_vars` | The variable parts are pairwise disjoint (as a `Pairwise` on the variable list). | yes | p c q |
| 17 | `Sat.disjoint_conc` | The concrete part is disjoint from every variable part. | yes | p c q |
| 18 | `Sat.disjoint_of_ne` | DISTINCT variables of a constraint get disjoint rows. | yes | p c q |
| 19 | `Sat.disjoint_getElem` | Distinct POSITIONS of the variable list get disjoint rows (this is the sharp form: it applies even when the two positions carry the same variable). | yes | p c q |
| 20 | `Sat.eq_empty_of_dup` | A REPEATED variable is forced to be empty. | yes | p c q |
| 21 | `Sat.exclusive` | Exclusivity: at most one part of a satisfied constraint contains any given label. | yes | p c q |
| 22 | `Sat.not_mem_of_mem_conc` | A label of the concrete part lies in no variable part. | yes | p c q |
| 23 | `Sat.not_mem_of_mem_var` | A label of one variable part lies in no other variable part. | yes | p c q |
| 24 | `models_append` | `Models` distributes over list concatenation. Shared plumbing, promoted here at integration: `Rules` needs it for the resolution toolkit and `Canonical` for `State.toSystem`, which is a concatenation. | yes | p c q |
| 25 | `exists_fresh` | There is always a name outside a finite set: `Var = Label = ℕ` is infinite. Shared plumbing, promoted here at integration: `Divergence` needs a fresh VARIABLE, `Berthomieu` a fresh LABEL, and both are `Finset ℕ`. | yes | p c q |
| 26 | `sat_zero` | `a <- ((\|k\|))`. | yes | p c q |
| 27 | `sat_one` | `a <- (b, (\|k\|))`. | yes | p c q |
| 28 | `sat_two` | `a <- (b₁, b₂, (\|k\|))`. | yes | p c q |
| 29 | `sat_three` | `a <- (b₁, b₂, b₃, (\|k\|))`. | yes | p c q |
| 30 | `Models.sat` | A model of `G` satisfies every member of `G`. | yes | p c q |
| 31 | `Models.mono` | A model of a system models any sub-list of it. | yes | p c q |
| 32 | `Models.nil` | Every assignment models the empty system. | yes | p c q |
| 33 | `models_cons` | Modelling `c :: G` is satisfying `c` and modelling `G`. | yes | p c q |
| 34 | `entails_of_mem` | Anything in the system is entailed by it. | yes | p c q |
| 35 | `entails_self` | Reflexivity. | yes | p c q |
| 36 | `Entails.mono` | Monotonicity under list extension. | yes | p c q |
| 37 | `Entails.cons` | Weakening by one extra hypothesis. | yes | p c q |
| 38 | `Entails.trans` | Cut / transitivity through a list of entailed constraints. | yes | p c q |
| 39 | `bparts_proj` | The Boolean shadow of the parts is the pointwise membership image of the parts. | yes | p c q |
| 40 | `eq_foldr_union_iff` | Half of the decomposition: the union equation is pointwise. | yes | p c q |
| 41 | `pairwise_disjoint_iff` | The other half: pairwise disjointness is pointwise. | yes | p c q |
| 42 | `sat_iff_forall_label` | Label decomposition. A constraint is satisfied by `rho` iff, at EVERY label, the Boolean projection of `rho` satisfies the Boolean shadow of the constraint. | yes | p c q |
| 43 | `models_iff_forall_label` | System-level corollary. | yes | p c q |
| 44 | `proj_filter` | If a family of Boolean assignments is supported inside a finite label set `S`, then it IS the projection family of an actual row assignment. | yes | p c q |
| 45 | `exists_assign_of_bmodels` | Reconstruction of an assignment from a finitely-supported Boolean family. | yes | p c q |
| 46 | `mem_concLabels` | Characterises the finite set of labels a system mentions concretely. | yes | p c q |
| 47 | `bmodels_false_of_not_mem` | Outside the (finite) set of concrete labels, the all-false Boolean assignment is a model of every system. | yes | p c q |
| 48 | `satisfiable_iff_forall_label` | Satisfiability decomposes per label. A system has a row model iff it has a Boolean model at every individual label. | yes | p c q |
| 49 | `exists_splice` | Splicing: any Boolean assignment can be installed at a single label of an existing row assignment, leaving all other labels untouched. | yes | p c q |
| 50 | `entails_of_forall_label` | The easy direction: per-label validity always implies entailment. | yes | p c q |
| 51 | `entails_iff_forall_label` | Entailment decomposes per label, given satisfiability. If `G` has at least one row model then `Entails G c` is equivalent to the per-label Boolean statement. | yes | p c q |
| 52 | `Counterexample.not_models` | `x = {5}` together with `x = {6}` has no model. | yes | p c q |
| 53 | `Counterexample.entails_G_c` | The unsatisfiable G entails `y = {7}` (ex falso). | yes | p c q |
| 54 | `Counterexample.bmodels_false` | At label 7 the all-false Boolean assignment is a Boolean model of the (unsatisfiable) system G. | yes | p c q |
| 55 | `Counterexample.not_bsat` | The all-false Boolean assignment at label 7 refutes the Boolean shadow of `y = {7}`. | yes | p c q |
| 56 | `Counterexample.entails_not_pointwise` | The per-label reading of entailment is strictly stronger than entailment. | yes | p c q |

### `Rules.lean` — 97 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `disjoint_of_subset_right` | Disjointness is antitone in its right argument. | yes | p c q |
| 2 | `disjoint_of_subset_left` | Disjointness is antitone in its left argument. | yes | p c q |
| 3 | `eq_empty_of_disjoint_self` | A row disjoint from itself is empty. | yes | p c q |
| 4 | `foldr_union_append` | `foldr`-union distributes over list append. | yes | p c q |
| 5 | `exists_mem_append` | Bounded existential over an append. | yes | p q |
| 6 | `exists_mem_cons` | Bounded existential over a cons. | yes | p q |
| 7 | `exists_mem_singleton` | Bounded existential over a singleton. | yes | p q |
| 8 | `mem_parts_foldr` | Membership in the union of the parts. | yes | p c q |
| 9 | `pairwise_parts_of` | Introduction rule for the disjointness half of `Sat`. | yes | p c q |
| 10 | `sat_of` | Introduction rule for `Sat`, stated pointwise in the label. | yes | p c q |
| 11 | `sat_mk` | `sat_of` at an explicit constraint literal. | yes | p c q |
| 12 | `Sat.mem_iff` | Membership characterisation, at a constraint literal. | yes | p c q |
| 13 | `Sat.eq_of` | The union equation, at a constraint literal. | yes | p c q |
| 14 | `Sat.conc_disj` | The concrete part is disjoint from every variable part, at a constraint literal. | yes | p c q |
| 15 | `Sat.sub` | Every variable part is inside the left-hand row, at a constraint literal. | yes | p c q |
| 16 | `Sat.conc_sub` | The concrete part is inside the left-hand row, at a constraint literal. | yes | p c q |
| 17 | `Sat.pw` | Pairwise disjointness of the variable parts, at a constraint literal. | yes | p c q |
| 18 | `Sat.disjoint_cons_head` | The FIRST variable of a right-hand side is disjoint from all the later ones -- note this is positional, so it needs no distinctness hypothesis. | yes | p c q |
| 19 | `Sat.disjoint_append` | Variables in the left block of an appended right-hand side are disjoint from those in the right block -- again positional. | yes | p c q |
| 20 | `Sat.pw_append_left` | Pairwise disjointness of the left block of an appended right-hand side. | yes | p c q |
| 21 | `Sat.pw_append_right` | Pairwise disjointness of the right block of an appended right-hand side. | yes | p c q |
| 22 | `Sat.mem_one` | Membership characterisation for a one-variable right-hand side. | yes | p c q |
| 23 | `Sat.disj_one` | Disjointness for a one-variable right-hand side. | yes | p c q |
| 24 | `sat_one_mk` | Introduction rule for a one-variable right-hand side. | yes | p c q |
| 25 | `Sat.mem_cons` | Membership characterisation for a cons right-hand side. | yes | p c q |
| 26 | `sat_cons_mk` | Introduction rule for a cons right-hand side. | yes | p c q |
| 27 | `Sat.mem_append` | Membership characterisation for an appended right-hand side. | yes | p c q |
| 28 | `sat_append_mk` | Introduction rule for an appended right-hand side. | yes | p c q |
| 29 | `mem_rowSum` | Membership in the union of a group of variables. | yes | p c q |
| 30 | `rowSum_congr` | The group union depends only on the rows of the variables in the group. | yes | p c q |
| 31 | `subset_rowSum` | Each member of a group is inside the group's union. | yes | p c q |
| 32 | `disjoint_rowSum_right` | `s` is disjoint from a group union if it is disjoint from each member. | yes | p c q |
| 33 | `disjoint_rowSum_left` | A group union is disjoint from `s` if each member is. | yes | p c q |
| 34 | `sat_empty_conc` | A constraint with an empty concrete part says exactly that its left-hand row is the union of a pairwise-disjoint group of variables. | yes | p c q |
| 35 | `upd_same` | A point update takes the new value at the updated variable. | yes | p q |
| 36 | `upd_ne` | A point update leaves every other variable alone (implicit-argument form). | yes | p q |
| 37 | `upd_agrees` | A point update leaves every other variable alone. | yes | p q |
| 38 | `upd_of_not_mem` | A point update at a variable outside a list leaves the whole list alone. | yes | p q |
| 39 | `sat_congr` | `Sat` only depends on the rows of the variables the constraint mentions. | yes | p c q |
| 40 | `pairwise_disj_congr` | Transport a `Pairwise` disjointness statement along an agreeing assignment. | yes | p c q |
| 41 | `models_of_one` | Build a one-constraint system from one `Sat`. | yes | p c q |
| 42 | `models_of_two` | Build a two-constraint system from two `Sat`s. | yes | p c q |
| 43 | `models_of_three` | Build a three-constraint system from three `Sat`s. | yes | p c q |
| 44 | `disjoint_foldr_union_left` | A `foldr`-union is disjoint from `t` iff each summand is. | yes | p c q |
| 45 | `rsat_iff_flatten` | Flattening is faithful. A multi-block right-hand side is satisfied exactly when its union-flattened form is satisfied and the concrete blocks are pairwise disjoint. | yes | p c q |
| 46 | `ConservativeExt.satisfiable_iff` | A conservative extension preserves satisfiability in both directions. | yes | p c q |
| 47 | `ConservativeExt.entails_iff` | A conservative extension does not change which `u`-free constraints are entailed. | yes | p c q |
| 48 | `models_of_agree` | If a model of `G` is untouched off `u`, and `u` occurs nowhere in `G`, the modified assignment still models `G`. | yes | p c q |
| 49 | `ConservativeExt.models_append` | The practically relevant corollary: the solver KEEPS the premises and ADDS the conclusion, and the enlarged system still has a model. | yes | p c q |
| 50 | `rule1_empty` | Rule 1, first half, general form. In `a <- a b*` every other variable on the right is forced empty. | yes | p c q |
| 51 | `rule1_conc` | Rule 1, second half. In `a <- a b*` the concrete part is forced empty. | yes | p c q |
| 52 | `rule1_unsat` | Rule 1 as an "infinite row" error. `a <- C+ a b*` with `C` nonempty has NO model whatsoever. | yes | p c q |
| 53 | `rule1_entails` | Entailment form of rule 1: `b <-` really is derivable. | yes | p c q |
| 54 | `rule1_general` | Rule 1 for an arbitrary position of the left-hand variable on the right. | yes | p c q |
| 55 | `rule2` | Rule 2, general form. If `a` is empty and `a <- x*`, every `x` is empty. | yes | p c q |
| 56 | `rule2_conc` | The concrete part of the second premise is forced empty too. | yes | p c q |
| 57 | `rule2_entails` | Entailment form of rule 2. | yes | p c q |
| 58 | `rule3` | Rule 3, general form. A variable occurring at least twice on a right-hand side is empty. (This is `Sat.eq_empty_of_dup` from the foundations, restated as a rule.) | yes | p c q |
| 59 | `rule3_entails` | Entailment form of rule 3. | yes | p c q |
| 60 | `rule3_concrete` | Rule 3 at the concrete arity `a <- C* x b b`, proved directly from positional disjointness rather than from the `count` version. | yes | p c q |
| 61 | `rule4_fresh` | `u` really is fresh for the premise of rule 4. | yes | p q |
| 62 | `rule4_back` | The backward half of rule 4: the conclusion already implies the premise. Note that NO freshness hypothesis occurs here; freshness is needed only for the forward half. | yes | p c q |
| 63 | `rule4` | Rule 4 (split concrete), general form, both halves. The freshness hypotheses `hau` and `hxu` are used in the forward half only (see `rule4_back`). | yes | p c q |
| 64 | `rule4_concrete` | Rule 4 at the concrete arity `a <- C (x1, x2)`. | yes | p c q |
| 65 | `union_sdiff_of_disjoint` | If `C` and `D` are disjoint, removing `C` from `C ∪ D` leaves `D`. | yes | p c q |
| 66 | `rule5` | Rule 5 (cancellation), general form. | yes | p c q |
| 67 | `rule5_header` | Rule 5 in the header's notation: the second premise's concrete part is `C* D*`, with `C*` shared with the first premise and `D*` disjoint from it (header convention 8). | yes | p c q |
| 68 | `rule5_concrete` | Rule 5 at concrete arity: `a <- (x, z)` against `a <- (x, d1, d2)`. | yes | p c q |
| 69 | `rule5_entails` | Entailment form of rule 5. | yes | p c q |
| 70 | `sdiff_eq_self_of_disjoint` | Removing a disjoint set changes nothing. | yes | p c q |
| 71 | `rule6_fresh` | `z` really is fresh for the premises of rule 6. | yes | p c q |
| 72 | `rule6_back` | The backward half of rule 6: the conclusion implies both premises. | yes | p c q |
| 73 | `rule6` | Rule 6 (resolution), general form, both halves -- exactly the inference the Scala `resolution` function performs. The fresh variable is given the row `rho x ∩ rho y`. | yes | p c q |
| 74 | `rule6_swapped` | Header convention 8 ("named sequences are disjoint over an entire rule") gives `Disjoint C E`, and then the sharp form collapses to the header's shape -- with `C` and `E` ... | yes | p c q |
| 75 | `Rule6Header.premise_conclusion_unsat` | The header's first conclusion `x <- C* z` contradicts the first premise `a <- C* D* x` as soon as `C` is nonempty: the premise makes `C` disjoint from `rho x`, the ... | yes | p c q |
| 76 | `Rule6Header.premises_sat` | The concrete premises used against the header's rule 6 do have a model. | yes | p c q |
| 77 | `Rule6Header.header_no_extension` | No extension of the model along the fresh variable satisfies the header's conclusion. | yes | p c q |
| 78 | `Rule6Header.header_not_conservative` | The header comment's resolution rule is not a conservative extension: its premises have a model, but no extension of that model satisfies its conclusion. | yes | p c q |
| 79 | `Rule6Header.header_makes_unsat` | The sharper statement: keeping the premises (as the solver does -- the rules are non-destructive) and adding the header's conclusion yields an UNSATISFIABLE system, ... | yes | p c q |
| 80 | `rule7` | Rule 7 (substitution), general form. | yes | p c q |
| 81 | `rule7_entails` | Entailment form of rule 7. | yes | p c q |
| 82 | `rule7_concrete` | Rule 7 at concrete arity: `a <- (D, b, x)` and `b <- (F, y)` give `a <- (D F, x, y)`. | yes | p c q |
| 83 | `rule8` | Rule 8 (common partition), general form. Two identical right-hand sides force their left-hand variables to be equal. | yes | p c q |
| 84 | `rule8_entails` | Entailment form of rule 8: `a <- b` is the constraint `⟨a, [b], ∅⟩`. | yes | p c q |
| 85 | `rule9_fresh` | `w` really is fresh for the premises of rule 9. | yes | p q |
| 86 | `exists_mem_congr` | Rewriting a bounded existential along an assignment that agrees on the list. | yes | p c q |
| 87 | `rule9_back` | The backward half of rule 9: the three conclusions imply both premises. NO freshness hypothesis occurs here. | yes | p c q |
| 88 | `rule9` | Rule 9 (common subexpression), general form, both halves. The freshness hypotheses are used in the forward half only (see `rule9_back`). | yes | p c q |
| 89 | `rule10` | Error condition 10, general form. A concrete block occurring at least twice in a raw right-hand side is empty; so a nonempty repeated block makes the constraint unsatisfiable. | yes | p c q |
| 90 | `rule10_unsat` | Error condition 10 as unsatisfiability. | yes | p c q |
| 91 | `rule10_concrete` | Error condition 10 at the concrete shape `a <- C x D D`. | yes | p c q |
| 92 | `rule11` | Error condition 11, general form. If `a` has a fully concrete partition `C`, every other partition of `a` has its concrete part inside `C`. | yes | p c q |
| 93 | `rule11_vars` | ... and each variable part too. | yes | p c q |
| 94 | `rule11_unsat` | Error condition 11 as unsatisfiability. | yes | p c q |
| 95 | `rule11_header` | Error condition 11 in the header's notation: the second premise's concrete part is `D* E+`, and it is the failure of `E+ ⊆ C*` that is detected. | yes | p c q |
| 96 | `rule5_needs_shared_conc` | Cancellation needs its shared concrete part to really be shared. | yes | p c q |
| 97 | `rule6_swapped_needs_disjoint` | The swapped-but-unsharpened resolution rule needs `Disjoint C E`. | yes | p c q |

### `Canonical.lean` — 88 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `sat_iff_satL` | `Sat rho c` is `SatL` applied to the left-hand row and the parts. | yes | p c q |
| 2 | `foldr_union_perm` | The union of a list of rows is permutation-invariant. | yes | p c q |
| 3 | `pairwise_disjoint_perm` | Pairwise disjointness is permutation-invariant. | yes | p c q |
| 4 | `satL_perm` | `SatL` is invariant under permuting its list of parts. | yes | p c q |
| 5 | `foldr_union_filter` | Dropping empty parts does not change the union. | yes | p c q |
| 6 | `pairwise_disjoint_filter` | Dropping empty parts does not affect pairwise disjointness. | yes | p c q |
| 7 | `satL_filter` | `SatL` only sees the non-empty parts. | yes | p c q |
| 8 | `satL_congr` | The congruence principle for `SatL`. Satisfaction depends only on the MULTISET OF NON-EMPTY PARTS: empty parts are invisible and order is irrelevant. | yes | p c q |
| 9 | `satL_merge` | Merging two adjacent parts: exactly the disjointness of the two is lost. | yes | p c q |
| 10 | `satL_cons_self` | A part equal to the whole forces every other part to be empty. | yes | p c q |
| 11 | `sat_absorb` | Master elimination lemma. If a variable `b` of the right-hand side is known to denote the concrete row `k`, it may be absorbed into the concrete part -- and the ONLY thing ... | yes | p c q |
| 12 | `sat_erase_empty` | Empty propagation. A variable known to be empty may simply be deleted. | yes | p c q |
| 13 | `sat_dedup_var` | Self-de-duplication. A variable occurring at least twice on the right is forced empty; deleting one occurrence and recording `b = ∅` is an exact rewrite. | yes | p c q |
| 14 | `sat_occurs` | Occurs. A constraint whose left-hand variable also occurs on the right is completely determined: it says exactly that the concrete part and all the OTHER parts are empty. | yes | p c q |
| 15 | `sat_congr_perm` | Satisfaction is invariant under permuting the right-hand side. | yes | p c q |
| 16 | `eq_lhs_of_common` | Common-partition unification. Two constraints with the same right-hand side (up to permutation) force their left-hand variables to be equal. | yes | p c q |
| 17 | `sat_eqc` | Singleton right-hand side. `a <- (b)` is precisely the equation `a = b`. This is also how an eliminated variable is recorded in the solved part. | yes | p c q |
| 18 | `substV_apply` | Substitution does not change the row denoted, when `rho a = rho b`. | yes | p q |
| 19 | `parts_substC` | The parts of a substituted constraint, under an assignment identifying the two variables. | yes | p q |
| 20 | `sat_substC` | Substituting equals for equals does not change satisfaction. | yes | p c q |
| 21 | `models_perm` | Modelling is invariant under permuting the system. | yes | p c q |
| 22 | `models_erase` | Peel one (occurrence of a) constraint off a system. | yes | p c q |
| 23 | `models_eqs` | Modelling a list of `v <- ()` constraints is exactly `every v is empty`. | yes | p c q |
| 24 | `models_substG` | If `rho a = rho b`, `rho` models the substituted system iff it models the original. | yes | p c q |
| 25 | `mem_varSet` | The `Finset` of a variable list has the same members as the list. | yes | p c q |
| 26 | `mem_cvars` | Membership in a constraint's variable set (lhs plus right-hand variables). | yes | p c q |
| 27 | `mem_varsOf` | Membership in a system's variable set. | yes | p c q |
| 28 | `varsOf_subset` | Variable-set monotonicity from a constraint-wise inclusion. | yes | p c q |
| 29 | `cvars_subset_varsOf` | A constraint's variables lie in its system's variable set. | yes | p c q |
| 30 | `rhsSize_append` | Total right-hand-side size is additive over append. | yes | p q |
| 31 | `rhsSize_perm` | Total right-hand-side size is permutation-invariant. | yes | p q |
| 32 | `rhsSize_erase` | Erasing a member drops the total right-hand-side size by that member's arity. | yes | p c q |
| 33 | `rhsSize_substG` | Substitution does not change total right-hand-side size. | yes | p q |
| 34 | `length_erase_le` | Erasing a constraint does not increase the system's length. | yes | p c q |
| 35 | `varsOf_erase` | Erasing a constraint cannot add variables. | yes | p c q |
| 36 | `mem_cvars_substC` | Every variable of a substituted constraint is the substitute of a variable of the original. | yes | p c q |
| 37 | `varsOf_substG_subset` | Substitution keeps the variable set inside the original one. | yes | p c q |
| 38 | `card_varsOf_substG_lt` | Substituting one variable for another strictly drops the distinct-variable count. | yes | p c q |
| 39 | `lexLt_of` | The three-component comparison we actually use: each component may only go down, and at least one must strictly go down. | yes | p c q |
| 40 | `acc_lex` | Every measure triple is accessible for the lexicographic order. | yes | — |
| 41 | `lexLt_wf` | The lexicographic order on measure triples is well-founded (proved from scratch). | yes | — |
| 42 | `lexLt_fst` | First component down: the triple decreases. | yes | p q |
| 43 | `lexLt_snd` | First component level, second down: the triple decreases. | yes | p c q |
| 44 | `lexLt_thd` | First two level, third down: the triple decreases. | yes | p c q |
| 45 | `card_varsOf_le` | Monotonicity of the distinct-variable count. | yes | p c q |
| 46 | `rhsSize_eqs` | Emitted equations `v <- ()` contribute zero right-hand-side size. | yes | p q |
| 47 | `length_erase_lt` | Erasing a member strictly decreases the system's length. | yes | p c q |
| 48 | `Step.decreasing` | Every rule strictly decreases the measure. This is the heart of the design. | yes | p c q |
| 49 | `no_infinite_descent` | No infinite reduction sequence. The canonicaliser terminates on every input. | yes | p c q |
| 50 | `preserves_of_cs` | Model preservation lifts from the working list to the whole state. | yes | p c q |
| 51 | `models_toSystem_cons` | Reading one solved pair back as the partition constraint `a <- (b)`. | yes | p c q |
| 52 | `Step.preserves` | Soundness AND completeness of the simplifier. Every rule preserves the set of models of the system EXACTLY. | yes | p c q |
| 53 | `Step.satisfiable_iff` | Each step preserves satisfiability. | yes | p c q |
| 54 | `Step.entails_iff` | Each step preserves entailment in both directions: the input and the output are LOGICALLY EQUIVALENT constraint systems. | yes | p c q |
| 55 | `firstSome_eq_some` | If the first-success search succeeds, some entry succeeded. | yes | p |
| 56 | `firstSome_eq_none` | Dual of `firstSome_eq_some`: if the search fails, it failed at every entry. | yes | p |
| 57 | `tryOccurs_sound` | The `occurs` search only ever returns a genuine `Step`. | yes | p c q |
| 58 | `trySelfDedup_sound` | The `selfDedup` search only ever returns a genuine `Step`. | yes | p c q |
| 59 | `tryAbsorb_sound` | The `absorb` search only ever returns a genuine `Step`. | yes | p c q |
| 60 | `tryUnify_sound` | The `unify` search only ever returns a genuine `Step`. | yes | p c q |
| 61 | `tryDedup_sound` | The `dedup` search only ever returns a genuine `Step`. | yes | p c q |
| 62 | `tryCommon_sound` | The `common` search only ever returns a genuine `Step`. | yes | p c q |
| 63 | `stepFn_sound` | The implementation only ever performs genuine rule steps. | yes | p c q |
| 64 | `canonN_preserves` | The fuelled driver preserves the model set exactly. | yes | p c q |
| 65 | `exists_fuel` | Enough fuel always exists: the driver reaches a normal form. | yes | p c q |
| 66 | `canonicalise` | The canonicaliser. Every constraint system reduces, in finitely many steps, to a normal form with EXACTLY the same models. | yes | p c q |
| 67 | `Steps.eq_of_normalForm` | Nothing reduces out of a normal form. | yes | p c q |
| 68 | `canonN_entails` | Sound and complete as a SIMPLIFIER: entailment is unchanged by canonicalisation. | yes | p c q |
| 69 | `stepFn_eq_none` | Every `try...` combinator that `stepFn` consults reports `none` at every constraint of a state on which `stepFn` reports `none`. | yes | p c q |
| 70 | `stepFn_complete` | The implementation is EXHAUSTIVE. If `stepFn` reports no step, then NO rule of the calculus applies: the state is a `NormalForm`. | yes | p c q |
| 71 | `canonicalise_normalForm` | The canonicaliser, sharpened. Every constraint system reduces, in finitely many steps, to a state on which NO rule applies and which has exactly the same models as the input. | yes | p c q |
| 72 | `unsat_of_occurs` | A constraint whose left-hand variable occurs on its right with a NON-EMPTY concrete part is unsatisfiable. | yes | p c q |
| 73 | `absorb_guard_needed` | The `absorb` guard is necessary. `a <- (b, (\|{5}\|))` together with `b = {5}` is UNSATISFIABLE, but absorbing `b` without checking `Disjoint c.conc k` yields `a = {5}`, ... | yes | p c q |
| 74 | `CriticalPair.step_S1` | `S` reduces to `S1` by `occurs`. | yes | p c q |
| 75 | `CriticalPair.step_S2` | `S` reduces to `S2` by `absorb`. | yes | p c q |
| 76 | `CriticalPair.normal_S1` | The `occurs` reduct is a normal form (checked against all six constructors). | yes | p c q |
| 77 | `CriticalPair.normal_S2` | The `absorb` reduct is a normal form (checked against all six constructors). | yes | p c q |
| 78 | `CriticalPair.S1_ne_S2` | The two reducts of the critical pair are literally different states. | yes | p c q |
| 79 | `CriticalPair.not_locally_confluent` | Local confluence FAILS. `S` steps to two DISTINCT normal forms. | yes | p c q |
| 80 | `CriticalPair.not_joinable` | ... hence the two results have no common reduct: normal forms are NOT unique. | yes | p c q |
| 81 | `CriticalPair.both_branches_unsat` | Meaning IS preserved along both branches, as the general theorem guarantees: both results are unsatisfiable, like the input. | yes | p c q |
| 82 | `CriticalPair.normal_form_can_be_unsat` | The canonicaliser is not a decision procedure. `S1` is a normal form and is unsatisfiable: no non-generative rule detects the contradiction `b = ∅ ∧ b = {7}`. | yes | p c q |
| 83 | `Orientation.T_sat` | The system on which `common` is ambiguous is satisfiable. | yes | p c q |
| 84 | `Orientation.step_left` | `T` steps to the state that eliminates `x` in favour of `y`. | yes | p c q |
| 85 | `Orientation.step_right` | `T` steps to the state that eliminates `y` in favour of `x`. | yes | p c q |
| 86 | `Orientation.results_differ` | The two orientations of `common` yield different states. | yes | p q |
| 87 | `step_vacuous` | A vacuous `r <- (r)` is deleted outright. | yes | p c q |
| 88 | `step_perm_dup` | A duplicate under a PERMUTED right-hand side is recognised and deleted. | yes | p c q |

### `Divergence.lean` — 86 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `mem_slist` | The computable sorted list of a finset has the finset's members. | yes | p c q |
| 2 | `slist_toFinset` | The computable sorted list round-trips back to its finset. | yes | p c q |
| 3 | `slist_nodup` | The computable sorted list of a finset is duplicate-free. | yes | p q |
| 4 | `vset_mk` | Variable set of a set-shaped constraint. | yes | p c q |
| 5 | `lhs_mk` | Left-hand side of a set-shaped constraint. | yes | p q |
| 6 | `conc_mk` | Concrete part of a set-shaped constraint. | yes | p q |
| 7 | `mk_inj` | The set-shaped constraint constructor is injective. | yes | p c q |
| 8 | `foldr_union_map` | The `foldr`-union of a mapped variable list is the `biUnion` over its finset. | yes | p c q |
| 9 | `Sat.eq_biUnion` | The union equation as a `Finset.biUnion` (set-shaped right-hand side). | yes | p c q |
| 10 | `Sat.disjoint_conc'` | Concrete part disjoint from every variable part (set-shaped right-hand side). | yes | p c q |
| 11 | `Sat.disjoint_of_ne'` | Distinct variables get disjoint rows (set-shaped right-hand side). | yes | p c q |
| 12 | `sat_mk_iff` | Unfolding `Sat` at a set-shaped constraint. | yes | p c q |
| 13 | `sat_congr_of_agree` | `Sat` only depends on the assignment at the variables the constraint mentions. | yes | p c q |
| 14 | `sModels_iff_models` | Modelling a finite-set system agrees with modelling its list form. | yes | p c q |
| 15 | `sEntails_iff_entails` | Entailment over finite-set systems agrees with entailment over list systems. | yes | p c q |
| 16 | `SModels.mono` | A model of a finite system models any subset of it. | yes | p c q |
| 17 | `mem_allVars` | Vocabulary membership for a constraint of the system. | yes | p c q |
| 18 | `lhs_mem_allVars` | A constraint's left-hand side is in its system's vocabulary. | yes | p c q |
| 19 | `vset_subset_allVars` | A constraint's variables lie in its system's vocabulary. | yes | p c q |
| 20 | `allVars_mono` | The vocabulary of a system is monotone in the system. | yes | p c q |
| 21 | `setVar_self` | Point update takes the new value at the updated variable. | yes | p q |
| 22 | `setVar_of_ne` | Point update leaves every other variable alone. | yes | p q |
| 23 | `sModels_setVar` | Updating at a variable the system does not mention leaves all its models intact. | yes | p c q |
| 24 | `CseApp.mem₁` | the first premise is in the system | yes | p c q |
| 25 | `CseApp.mem₂` | the second premise is in the system | yes | p c q |
| 26 | `CseApp.lhs_ne` | the rule fires only across DIFFERENT left-hand sides | yes | p q |
| 27 | `CseApp.two_le` | the guard `int.size >= 2` | yes | p c q |
| 28 | `CseApp.fresh` | `z` is a genuinely fresh variable | yes | p c q |
| 29 | `subset_cseResult` | A step's result contains the system it came from. | yes | p c q |
| 30 | `CseStep.subset` | A CSE step never deletes a constraint. | yes | p c q |
| 31 | `shared_subset_left` | The shared set is inside the first constraint's variables. | yes | p c q |
| 32 | `shared_subset_right` | The shared set is inside the second constraint's variables. | yes | p c q |
| 33 | `disjoint_biUnion_left'` | A `biUnion` is disjoint from `t` if each member is. | yes | p c q |
| 34 | `disjoint_biUnion_right'` | `t` is disjoint from a `biUnion` if it is disjoint from each member. | yes | p c q |
| 35 | `biUnion_split` | Splitting a `biUnion` along a subset. | yes | p c q |
| 36 | `sat_name` | The fresh name really does denote the shared sub-row: `w <- x++` is satisfied by the extended assignment. | yes | p c q |
| 37 | `sat_reduce` | The rewritten premise `a <- C* E* w y*` is satisfied by the extended assignment. | yes | p c q |
| 38 | `CseStep.extend` | Every model of the premises extends to a model of the conclusion, changing only the fresh variable. | yes | p c q |
| 39 | `CseStep.satisfiable_iff` | One CSE step preserves satisfiability in both directions. | yes | p c q |
| 40 | `CseStep.entails_iff` | One step is a conservative extension. On any constraint phrased in the OLD vocabulary, the enlarged system entails exactly what the old one did. | yes | p c q |
| 41 | `CseSteps.subset` | A chain of CSE steps never deletes a constraint. | yes | p c q |
| 42 | `CseSteps.entails_iff` | The residual is the input. For every system reachable from `G₀` by any number of common-subexpression steps, and every constraint over the ORIGINAL vocabulary, the ... | yes | p c q |
| 43 | `CseSteps.satisfiable_iff` | A chain of CSE steps preserves satisfiability in both directions. | yes | p c q |
| 44 | `bv_injective` | The base-variable naming `bv` is injective. | yes | p q |
| 45 | `xv_injective` | The co-star left-hand-side naming `xv` is injective. | yes | p q |
| 46 | `nm_injective` | Canonical (hash-consed) naming `nm` is injective. | yes | p c q |
| 47 | `xv_ne_nm` | Co-star left-hand sides are never canonical names. | yes | p c q |
| 48 | `bv_ne_nm` | Base variables are never canonical names. | yes | p c q |
| 49 | `mem_base` | Membership in the base variable set. | yes | p c q |
| 50 | `card_base` | The base has exactly `m` variables. | yes | p c q |
| 51 | `mem_coStar` | The `i`-th co-star constraint really is in the co-star system. | yes | p c q |
| 52 | `card_coStar` | The co-star system has exactly `m` constraints. | yes | p c q |
| 53 | `lhs_of_mem_coStar` | Every co-star constraint has an `x`-variable as left-hand side. | yes | p c q |
| 54 | `sdiff_inter_sdiff` | `(X \ A) ∩ (X \ B) = X \ (A ∪ B)`. | yes | p c q |
| 55 | `named_sdiff` | Induction on the number of deleted base variables: every such intersection is canonically named. | yes | p c q |
| 56 | `named_of_mem_Fam` | In a CSE-closed system containing the co-star, every family member carries its canonical name. | yes | p c q |
| 57 | `card_Fam` | The canonically-nameable family has at least `2^m - 2m - 2` members. | yes | p c q |
| 58 | `names_subset` | All canonical names of the family belong to a CSE-closed system containing the co-star. | yes | p c q |
| 59 | `card_names` | The canonical names are in bijection with the family. | yes | p c q |
| 60 | `disjoint_names_coStar` | Canonical names never collide with the co-star's own constraints. | yes | p c q |
| 61 | `coStar_card_lower` | THE MAIN LOWER BOUND. Any system that contains the `m`-constraint co-star system and is closed under common-subexpression naming has at least `2 ^ m - m - 2` constraints. | yes | p c q |
| 62 | `coStar_card_lower'` | The same bound written with truncated subtraction. | yes | p c q |
| 63 | `coStar_seven` | Concretely, at the measured size `m = 7` (6.38 s in the real solver) any saturated system carries at least 119 constraints. | yes | p c q |
| 64 | `CseStep.ssubset` | A CSE step strictly enlarges the working set. | yes | p c q |
| 65 | `CseStep.card_lt` | Measure 1: the number of constraints. It STRICTLY INCREASES. | yes | p c q |
| 66 | `CseStep.occ_lt` | Measure 2 STRICTLY INCREASES. | yes | p c q |
| 67 | `CseStep.rhsSizes_lt` | Measure 3 STRICTLY INCREASES: the old multiset is a PROPER sub-multiset of the new one, so it is smaller in the sub-multiset order and in every order extending it. | yes | p c q |
| 68 | `cseStep_measures_increase` | All three standard syntactic measures go the WRONG way on every step. | yes | p c q |
| 69 | `exists_step` | A step is always available on a pair of premises satisfying the guard: freshness can never block the rule, because the label/variable universe is unbounded. | yes | p c q |
| 70 | `steps_exists` | Chains of EVERY length exist: one applicable pair of premises can be re-used forever, because each application needs only a new fresh name. | yes | p c q |
| 71 | `steps_measure` | A measure decreasing on every step would bound the length of every chain. | yes | p c q |
| 72 | `seed_shared` | The seed's two constraints share exactly `{2,3}`. | yes | p c q |
| 73 | `seed_guard` | The seed satisfies the rule's `2 ≤ \|shared\|` guard. | yes | p c q |
| 74 | `seed_lhs_ne` | The seed's two constraints have different left-hand sides. | yes | p q |
| 75 | `seed_diverges` | The common-subexpression rule does not terminate. From `seed` there are chains of every length, and the working set grows by at least one constraint per step. | yes | p c q |
| 76 | `no_decreasing_measure` | There is NO measure into `ℕ` that decreases on every rule application. | yes | p c q |
| 77 | `bv_ne_xv` | Base variables are never co-star left-hand sides. | yes | p q |
| 78 | `xv_notMem_base` | Co-star left-hand sides are not base variables. | yes | p c q |
| 79 | `rhoStar_base` | The separating model sends each base variable to its own singleton label. | yes | p c q |
| 80 | `rhoStar_xv` | The separating model sends `x_i` to the base minus `b_i`. | yes | p c q |
| 81 | `biUnion_singleton_self` | The union of the singletons of a finset is the finset. | yes | p c q |
| 82 | `sat_coStar` | The separating model satisfies every co-star constraint. | yes | p c q |
| 83 | `coStar_satisfiable` | The co-star system is satisfiable -- so the solver's answer really is "yes, and the residual is what you gave me". | yes | p c q |
| 84 | `coStar_residual` | Family B: the entire search is discarded work. Whatever the solver derives from the co-star system, over the co-star system's own vocabulary it entails exactly what the ... | yes | p c q |
| 85 | `joinTriple_shared` | The two constraints of one `join` share exactly two right-hand variables. | yes | p c q |
| 86 | `joinTriple_diverges` | One `join` call already admits CSE chains of every length. | yes | p c q |

### `Fragment.lean` — 61 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `mem_foldr_cons_map` | Membership in the union of a concrete part and a family of variable parts. | yes | p c q |
| 2 | `mem_flatten_map` | Membership in a flattened list of blocks. | yes | p q |
| 3 | `flatten_map_singleton` | Flattening a list of singletons is the identity. | yes | p |
| 4 | `sat_iff'` | Componentwise characterisation of `Sat`. | yes | p c q |
| 5 | `sat_self` | Every variable is trivially its own expansion. | yes | p c q |
| 6 | `sat_subst` | Substitution. If `a` partitions into `vs` (plus concrete `k`) and each `v ∈ vs` partitions into `ws v` (plus concrete `kv v`), then `a` partitions into the concatenated ... | yes | p c q |
| 7 | `sat_empty` | The everywhere-empty assignment satisfies any abstract constraint. | yes | p c q |
| 8 | `models_empty` | (F1) An abstract system is modelled by the everywhere-empty assignment. | yes | p c q |
| 9 | `satisfiable_of_abstract` | (F1) An abstract system is satisfiable. | yes | p c q |
| 10 | `entails_iff_forall_label_of_abstract` | Consequently, for an abstract system entailment DOES decompose per label: the satisfiability side condition of `Rowpartition.entails_iff_forall_label` is free. | yes | p c q |
| 11 | `leaves_nil` | In the empty system a variable expands to itself. | yes | p q |
| 12 | `kern_nil` | The concrete part of an expansion in the empty system is empty. | yes | p c q |
| 13 | `leaves_cons` | Recursion equation for the leaf expansion. | yes | p q |
| 14 | `kern_cons` | Recursion equation for the concrete part of the expansion. | yes | p c q |
| 15 | `leaves_cons_pos` | ... at the defining constraint. | yes | p q |
| 16 | `leaves_cons_neg` | ... past a non-defining constraint. | yes | p q |
| 17 | `kern_cons_pos` | ... at the defining constraint. | yes | p c q |
| 18 | `kern_cons_neg` | ... past a non-defining constraint. | yes | p c q |
| 19 | `sat_leaves` | (F2) Normal form. For EVERY system `G` and EVERY variable `a`, the leaf expansion of `a` is an entailed constraint: any model of `G` partitions `rho a` into the rows of ... | yes | p c q |
| 20 | `entails_leaves` | The normal form, as an entailment. | yes | p c q |
| 21 | `isDefList_cons` | Cons-characterisation of a definition list (unique lhs, no forward reference). | yes | p q |
| 22 | `IsDefList.uniq` | A definition list has unique left-hand sides. | yes | p q |
| 23 | `wellFounded_dep` | The dependency relation of a definition list is well-founded: no cycles. | yes | p q |
| 24 | `leaves_of_leaf` | A leaf expands to itself. | yes | p q |
| 25 | `mem_leaves_cases` | Every variable in an expansion either is the expanded variable itself or occurs on some right-hand side. | yes | p q |
| 26 | `leaf_of_mem_leaves` | (F2) In a definition list, the expansion of any variable consists of LEAVES. | yes | p q |
| 27 | `leaves_idem` | (F2) The expansion is a normal form: expanding it again changes nothing. | yes | p q |
| 28 | `leaves_def` | The fixed-point equation. In a definition list, the expansion of a defined variable is exactly the concatenation of the expansions of its right-hand variables. | yes | p q |
| 29 | `kern_eq_empty` | In an abstract system every expansion has empty concrete part. | yes | p c q |
| 30 | `entails_of_test` | (F3, soundness). Passing the test implies entailment -- for ANY system `G`, definitional or not, abstract or not. | yes | p c q |
| 31 | `linear_iff` | `Linear` is a finite, decidable condition. | yes | p c q |
| 32 | `mem_canon` | Membership in the canonical model's row for `a` is membership in `a`'s expansion. | yes | p c q |
| 33 | `canon_disjoint` | List disjointness of expansions transfers to the canonical model. | yes | p c q |
| 34 | `canon_disjoint'` | ... and back again. | yes | p c q |
| 35 | `models_canon` | The canonical model really is a model. | yes | p c q |
| 36 | `perm_of_nodup` | Two `Nodup` lists with the same members are permutations of one another. | yes | p c q |
| 37 | `test_of_entails` | (F3, completeness). On the definitional fragment -- abstract, a definition list, and linear -- entailment of an abstract constraint implies the syntactic test. | yes | p c q |
| 38 | `entails_iff_test` | (F3). Entailment on the definitional fragment IS the syntactic test. | yes | p c q |
| 39 | `test_of_mem` | Every constraint of an in-fragment system passes its own test: the procedure is reflexive, hence not vacuously refuting. | yes | p c q |
| 40 | `NotDefinitional.not_uniq` | ... but two of its constraints share a left-hand side. | yes | p q |
| 41 | `NotDefinitional.abstract` | The non-definitional counterexample system is abstract. | yes | p q |
| 42 | `NotDefinitional.entails` | Both constraints force `x` to be the whole of `y` and the whole of `z`, so `y` and `z` are equal in every model and `y <- (z)` is entailed. | yes | p c q |
| 43 | `NotDefinitional.leaves_lhs` | Its expansion of `y` is `[y]`. | yes | p q |
| 44 | `NotDefinitional.leaves_rhs` | ... while the expansion of `z` is `[z]`. | yes | p q |
| 45 | `NotDefinitional.not_test` | ... but the test fails: `y` and `z` are distinct leaves. | yes | p c q |
| 46 | `NotDefinitional.entails_not_test` | The test is incomplete outside the definitional fragment. | yes | p c q |
| 47 | `NonLinear.isDefList` | The non-linear counterexample system IS a definition list. | yes | p q |
| 48 | `NonLinear.abstract` | The non-linear counterexample system is abstract. | yes | p q |
| 49 | `NonLinear.entails` | The repeated variable is forced empty, hence so is `p`, hence `p <- (d)` holds. | yes | p c q |
| 50 | `NonLinear.leaves_lhs` | Its expansion of `p` is `[d, d]`. | yes | p q |
| 51 | `NonLinear.leaves_rhs` | ... while the expansion of the right-hand side is `[d]`. | yes | p q |
| 52 | `NonLinear.not_linear` | ... but it is not linear: an expansion repeats a leaf. | yes | p q |
| 53 | `NonLinear.not_test` | The test fails, although `G` IS a definition list: the expansions have different lengths. So `Linear` is genuinely needed for completeness. | yes | p c q |
| 54 | `NonLinear.entails_not_test` | Completeness fails inside the definitional fragment without linearity. | yes | p c q |
| 55 | `Worked.isDefList` | The worked example is a definition list. | yes | p q |
| 56 | `Worked.abstract` | The worked example is abstract. | yes | p q |
| 57 | `Worked.linear` | The worked example is linear, so the procedure DECIDES on it. | yes | p c q |
| 58 | `Worked.test` | The procedure accepts the entailed constraint. | yes | p c q |
| 59 | `Worked.entails` | Entailment, by the decision procedure alone. | yes | p c q |
| 60 | `Worked.not_test'` | The procedure rejects the non-entailed constraint. | yes | p c q |
| 61 | `Worked.not_entails'` | ... and the procedure REFUTES it, using completeness. So the test is not a one-sided heuristic on this system: it decides. | yes | p c q |

Three more tables follow, for the comparison modules added in the second integration
round. Same conventions. `Pottier.lean`'s names are shown without the `Rowpartition.Pottier`
prefix; `Filter'.…` are inside its `Filter'` namespace.

### `Pottier.lean` — 81 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `symLe_iff` | The specialised order unfolds to equality of presence bits. | yes | — |
| 2 | `symLe_refl` | It is reflexive. | yes | — |
| 3 | `symLe_symm` | The specialised order is SYMMETRIC. In Pottier's system `τ₁ ≤ τ₂` and `τ₂ ≤ τ₁` are different constraints; here they are the same one. Consequently "lower bound" and "upper bound" are not distinguishable notions -- see section 12. | yes | — |
| 4 | `no_upper_bound` | Pottier's Theorem 1 ("every `(𝕋^ς_κ, ≤^ς_κ)` forms a lattice") fails in the Ermine specialisation: `Abs` and `Pre` have no common upper bound at all, so the specialised model is not even a join-semilattice. Theorem 1 is invoked by name inside the proof of Theorem 4 to supply the least upper bounds out of which the canonical witness is built; this lemma is why that proof strategy cannot be transported. | yes | p |
| 5 | `toPAssign_apply` | An Ermine row assignment, read as a Pottier ground assignment, is `proj` with its arguments swapped. | yes | p c q |
| 6 | `Filter'.mem_full` | The full filter contains every label. | yes | p c q |
| 7 | `Filter'.mem_empty` | The empty filter contains none. | yes | p c q |
| 8 | `Filter'.mem_fin` | Membership in a finite filter is membership in its payload. | yes | p c q |
| 9 | `Filter'.mem_cofin` | Membership in a cofinite filter is NON-membership in its payload. | yes | p c q |
| 10 | `Filter'.mem_compl` | Complement of a filter negates membership -- filters are closed under `¬`. | yes | p c q |
| 11 | `Filter'.mem_union` | Union of filters is disjunction of membership. | yes | p c q |
| 12 | `Filter'.mem_inter` | Intersection of filters is conjunction of membership. | yes | p c q |
| 13 | `Filter'.exists_mem_cofin` | Filters are Boolean-closed and have a decidable emptiness test -- which §5 of the paper identifies as the ONLY properties the development (bar the complexity analysis) uses. Emptiness: a finite filter is empty iff its payload is; a cofinite one never is, because `𝓛` is infinite. | yes | p c q |
| 14 | `Filter'.apparent_fin` | The apparent labels of a finite filter are its payload. | yes | p q |
| 15 | `Filter'.apparent_cofin` | ... and of a cofinite filter, also its payload -- the labels it explicitly mentions. | yes | p q |
| 16 | `Filter'.mem_apparent_fin` | Definition 8, first disjunct: a FINITE filter's apparent labels are its members. | yes | p c q |
| 17 | `Filter'.mem_apparent_cofin` | Definition 8, second disjunct: a COFINITE filter's apparent labels are its NON-members. So "apparent" is not "belongs to"; it is "explicitly mentioned". | yes | p c q |
| 18 | `Filter'.apparent_union_subset` | No rule makes new row labels apparent (the finiteness invariant behind Theorem 2 and behind the parameter `m` of Theorem 7): the labels apparent in a union are among those apparent in the operands. | yes | p c q |
| 19 | `Filter'.apparent_inter_subset` | The same for intersection, which is what (TRANS-ROW) propagates through. | yes | p c q |
| 20 | `Filter'.apparent_union_ne` | A transcription-level caveat, made precise. The paper says "the row labels apparent in `L₁ ∪ L₂` are those apparent in `L₁` or `L₂`", which reads as an equality; only the inclusion `apparent_union_subset` is true, and only the inclusion is needed (nothing must become apparent that was not). | yes | p c q |
| 21 | `RowTerm.eval_var` | Evaluation of a variable row term. | yes | — |
| 22 | `RowTerm.eval_const` | Evaluation of a constant row term is that constant at every label. | yes | — |
| 23 | `psat_sub_full` | The unfiltered comparison is the full-filter one: `𝓛 : τ₁ ≤ τ₂` is exactly Definition 4's pointwise `≤^Row`. (§2.4: "`τ₁ ≤ τ₂` and `L : ∂τ₁ ≤ ∂τ₂` are logically equivalent when `L` is nonempty".) | yes | p c q |
| 24 | `pmodels_cons` | `PModels` unfolds over `cons`. | yes | p c q |
| 25 | `pmodels_append` | `PModels` distributes over list concatenation. | yes | p c q |
| 26 | `pmodels_concatSystem` | `concatSystem` is satisfied exactly when its per-label reading holds at every label. This is the content of Figure 3 for a full filter; it is where the "∀ℓ ∈ 𝓛" of the scheme is discharged. | yes | p c q |
| 27 | `bsat_binary` | `BSat` at a binary, concrete-free constraint, unfolded. The head of `bparts` is `decide (l ∈ ∅) = false`, which contributes nothing to either conjunct. | yes | p c q |
| 28 | `ermineConcatBit_iff_pottier` | The two per-label relations are the same relation on bits. | yes | p |
| 29 | `bridge` | THE BRIDGE. Pottier's symmetric-concatenation constraint and Ermine's binary partition are the same relation, label by label. `⟨a, [x, y], ∅⟩` is Ermine's `a <- (x, y)`: `a` is the LEFT-HAND SIDE, i.e. the row being partitioned, and `x`, `y` are the two parts. | yes | p c q |
| 30 | `sat_iff_pmodels_concatSystem` | The row-level form of the bridge: an Ermine assignment satisfies the binary partition iff, read as a Pottier ground assignment, it satisfies the concatenation scheme. This is `sat_iff_forall_label` composed with `bridge`. | yes | p c q |
| 31 | `pottierConcatBit_comm` | Swapping the two ARGUMENTS is invisible: `Pre ≤ φ₁ ? φ₂ ≤ Abs` already says `¬(φ₁ = Pre ∧ φ₂ = Pre)`, which is symmetric. | yes | p |
| 32 | `pottierConcat_comm` | Pottier's concatenation is symmetric in its two ARGUMENTS -- which is why the scheme needs only one disjointness constraint, not two. | yes | p |
| 33 | `bridge_result_position_sharp` | Swapping an ARGUMENT with the RESULT is visible. Take `x` present, `y` absent, `a` present: Ermine's `a <- (x, y)` holds at that label, but reading `a` as an argument and `y` as the result makes `a` and `x` both `Pre`, which the third constraint forbids. | yes | p c q |
| 34 | `bsat_iff_flatBit` | `BSat` is the flat n-ary Boolean partition relation on `bparts`. | yes | p c q |
| 35 | `flatBit_false_cons` | A part known ABSENT at this label contributes nothing. | yes | p |
| 36 | `flatBit_true_cons` | A part known PRESENT at this label forces the left-hand side present and every other part absent. | yes | p q |
| 37 | `not_and_foldr_or` | Disjointness from a whole union is disjointness from each part. | yes | p |
| 38 | `pchainBit_iff_flat` | The n-ary bridge, at bit level. The chain of binary Pottier concatenations, with its intermediates existentially quantified, is exactly Ermine's flat n-ary partition. | yes | p q |
| 39 | `pchainBit_singleton` | A one-element chain: the single part must equal the whole. | yes | p q |
| 40 | `pchainBit_pair` | A two-element chain is one Pottier concatenation, no intermediate needed. | yes | p q |
| 41 | `bsat_iff_pchainBit` | The n-ary bridge, phrased on an Ermine constraint with an empty concrete part. | yes | p c q |
| 42 | `ternary_via_one_intermediate` | Exactly one intermediate suffices for the ternary case: `a <- (x, y, z)` is `t <- (y, z)` followed by `a <- (x, t)`, two instances of Pottier's scheme. Read together with `ternary_not_definable` (section 11), this pins the cost of the encoding down: ZERO intermediates is impossible, ONE is enough. | yes | p c q |
| 43 | `sat_iff_flatRow` | `Sat` is the flat n-ary row partition relation on `parts`. | yes | p c q |
| 44 | `disjoint_foldr_union` | Disjointness from a `foldr`-union is disjointness from every member. | yes | p c q |
| 45 | `flatRow_empty_cons` | An empty part contributes nothing to a flat row partition. | yes | p c q |
| 46 | `pchainRow_iff_flat` | The n-ary bridge, at row level. | yes | p c q |
| 47 | `sat_iff_pchainRow` | `a <- (b₁, …, bₙ)` is a chain of `n` symmetric concatenations. No per-label detour: the equivalence is between honest row assignments. | yes | p c q |
| 48 | `pmodels_map_sub` | A list of filtered `≤ Abs` constraints says every listed variable is absent throughout the filter. | yes | p c q |
| 49 | `pmodels_concEncoding` | The concrete part's encoding says: present in the result, absent in every part, at every concrete label. | yes | p c q |
| 50 | `bsat_split` | The per-label shadow splits along the concrete part: ON the filter it is total information, OFF it the constraint is the concrete-free partition. | yes | p c q |
| 51 | `sat_iff_filter_split` | The concrete part is a filter. `Sat` splits into a filtered pair of Pottier constraints on `k` and the concrete-free partition off `k`. | yes | p c q |
| 52 | `BinAbstract.abstract` | Binary-and-abstract implies abstract. | yes | p q |
| 53 | `encodeC_binary` | The encoding of a binary abstract constraint is exactly `concatSystem`. | yes | p q |
| 54 | `mem_encode` | Membership in the encoded system. | yes | p q |
| 55 | `pmodels_encode` | `PModels` of an encoded system is `PModels` of each constraint's encoding. | yes | p c q |
| 56 | `models_iff_pmodels` | Whole-system bridge. A row assignment models an Ermine system iff, read as a Pottier ground assignment, it satisfies the encoding of that system. | yes | p c q |
| 57 | `satisfiable_iff_psatisfiable` | Whole-system bridge, satisfiability form. The `←` direction is the interesting one: a Pottier ground assignment is a TOTAL family over all labels and need not have finite support, so it is not directly an Ermine assignment. | yes | p c q |
| 58 | `sat_iff_filter_and_chain` | The complete Pottier reading of one Ermine constraint. | yes | p c q |
| 59 | `models_iff_filter_and_chain` | The complete Pottier reading of an Ermine SYSTEM. This is the general form of the whole-system corollary; `models_iff_pmodels` is the special case in which every constraint is binary and concrete-free, and there the chain collapses to a single `concatSystem` with no intermediate at all. | yes | p c q |
| 60 | `ternary_iff_flat` | The ternary Boolean relation is the flat partition relation at arity 3. | yes | p c q |
| 61 | `bsat_iff_ternary` | `BSat` at a ternary abstract constraint is the `ternary` Boolean relation. | yes | p c q |
| 62 | `ternary_atom_sound` | The key finite check. Every atom valid throughout the ternary partition is also valid at `(Abs, Abs, Abs, Pre)`. 468 atoms x 16 points, decided by the kernel. | yes | — |
| 63 | `ternary_bad` | `(Abs, Abs, Abs, Pre)` is not in the relation: it puts a label in the result and in none of the parts. | yes | — |
| 64 | `ternary_not_definable` | The ternary Ermine partition is not definable by Pottier constraints over its own four variables. Intermediate row variables -- the chain of section 8 -- are therefore not a presentational convenience but a necessity. Note the contrast this draws. | yes | — |
| 65 | `lbAt_eq_of_pmodels` | First degeneration: a lower-bound set is never more than one value. Because `≤` has collapsed to `=` (`SymLe`), a constant "lower" bound is an EQUATION; two distinct ones make the system unsatisfiable. | yes | p c q |
| 66 | `mem_encodeC` | Every constraint the encoder emits is CONDITIONAL -- the fact `lbAt_encode` turns on. | yes | p q |
| 67 | `lbAt_encode` | Second degeneration: on an Ermine encoding the lower-bound sets are all EMPTY. `concatSystem` consists of three CONDITIONAL constraints and nothing else; there is not a single unconditional subtyping constraint for `lb_ℓ` to collect. | yes | p c q |
| 68 | `joinWitness_encode` | Consequently the witness is the everywhere-`Abs` assignment, whatever reading of `⊔` one picks: all readings agree on the empty set's join, namely the bottom element. | yes | p c q |
| 69 | `toPAssign_empty` | The everywhere-empty row assignment reads as the everywhere-`Abs` ground assignment. | yes | p c q |
| 70 | `theorem4_analogue` | The Ermine analogue of Theorem 4, and the point of this section. Pottier's canonical witness, transported to the encoding of an Ermine system, IS the everywhere- empty row assignment. | yes | p c q |
| 71 | `joinWitness_eq_toPAssign_empty` | The witness of `theorem4_analogue`, read as a Pottier ground assignment, is exactly `joinWitness` of the encoding. | yes | p c q |
| 72 | `pmodels_joinWitness` | Closing the loop: on the binary abstract fragment, Pottier's canonical witness really does satisfy the encoded system. The construction reaches the right answer; it just carries no information while doing so. | yes | p c q |
| 73 | `Sym4.le_refl` | The four-element field lattice's order is reflexive. | yes | p |
| 74 | `Sym4.le_trans` | ... transitive. | yes | p |
| 75 | `Sym4.le_antisymm` | ... and antisymmetric: it is a genuine partial order, not a stand-in. | yes | p |
| 76 | `Sym4.abs_pre_incomparable` | `Abs` and `Pre` are incomparable, exactly as the paper requires. | yes | p |
| 77 | `Sym4.le_top` | …but they have a common upper bound, `⊤_field`: "they do have a common supertype `⊤_field`, so width subtyping is present". Compare `no_upper_bound`, which says this element is exactly what the Ermine model does not have. | yes | p |
| 78 | `concat4_iff_bit` | The specialisation of section 5 is faithful. On the two-element subset `{Abs, Pre}` -- the only field symbols an Ermine row can exhibit -- Pottier's three constraints, read with the real subtyping order, define exactly `PottierConcatBit`. So nothing was lost or invented when `≤` was replaced by `=`. | yes | p |
| 79 | `concat4_result_underdetermined` | But on the full lattice the result is not determined. Both arguments `Abs` admits the result `Abs` and the result `⊤_field`. Ermine's partition is functional in the parts (`Sat` forces `rho a` to be the union), so the two relations differ as soon as `⊤_field` is in the model. | yes | p |
| 80 | `concat4_not_functional` | The sharp form: in the full lattice the concatenation relation is not a function of its arguments, so it cannot be the graph of any partition operator. | yes | p |
| 81 | `pottierConcatBit_functional` | Whereas after the collapse to equality it IS a function of its arguments: the result bit is forced to be the OR of the argument bits. That is the exactness the bridge records. | yes | p |

### `LabelClass.lean` — 53 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `map_eq_map_forall` | Two maps that agree as lists agree pointwise on the members. | yes | p |
| 2 | `exists_unmentioned_label` | `Label = ℕ` is infinite, so a system's finitely many mentioned labels never exhaust it. This is what makes the all-false signature always realised. | yes | p c q |
| 3 | `bsat_iff_bsatBit` | The variable part is label-independent. `BSat` at a label is `BSatBit` at that label's concrete-membership bit -- definitionally. | yes | p c q |
| 4 | `bsat_congr` | Two labels with the same bit give literally the same Boolean problem. | yes | p c q |
| 5 | `sig_nil` | The signature of the empty system is empty. | yes | p c q |
| 6 | `sig_cons` | Signature unfolds over `cons`: one bit per constraint. | yes | p c q |
| 7 | `sig_length` | A signature has one bit per constraint. | yes | p c q |
| 8 | `bmodels_iff_bmodelsSig` | The per-label instance is the label-free instance at the label's signature. | yes | p c q |
| 9 | `bmodels_congr` | Labels with equal signatures are interchangeable. This is the formal content of Pottier's filters: a solver may handle a whole label set as one unit, because every label in the set poses the identical Boolean problem. | yes | p c q |
| 10 | `bmodels_ext` | The sharper form: equal signatures transfer the whole SOLUTION SET at the label, not merely satisfiability. (The converse fails -- two labels can pose different but equally unsatisfiable Boolean problems -- so signature equality is a sufficient, not a necessary, condition for interchangeability.) | yes | p c q |
| 11 | `satisfiable_iff_transversal` | Satisfiability needs only one label per signature class. | yes | p c q |
| 12 | `entails_iff_transversal` | Entailment needs only one label per signature class of `c :: G`. The goal's own concrete block must be part of the signature: `c` can distinguish labels that `G` cannot. | yes | p c q |
| 13 | `sig_const_of_abstract` | An abstract system -- `Rowpartition.Abstract` of `Fragment`, i.e. no constraint mentions a concrete label, the shape of all 345 residual constraints in the measured stdlib corpus -- has a single signature class. | yes | p c q |
| 14 | `transversal_of_abstract` | Hence any single label is a transversal. | yes | p c q |
| 15 | `entails_iff_abstract` | Entailment between abstract constraints is decided at ONE label, with no side condition at all. | yes | p c q |
| 16 | `sig_eq_replicate` | The signature of an unmentioned label is all-false. | yes | p c q |
| 17 | `mem_sigs` | Every label's signature is in the signature set. | yes | p c q |
| 18 | `mem_sigs_iff` | `sigs G` is EXACTLY the set of realised signatures: nothing is counted twice and nothing spurious is counted. (The all-false vector is always realised, by any label the system does not mention -- there always is one, since labels are drawn from `ℕ`.) | yes | p c q |
| 19 | `sigs_length` | Every signature in the set has the system's length. | yes | p c q |
| 20 | `satisfiable_iff_sigs` | Once per distinct signature, literally. Satisfiability of the whole system is decided by solving the LABEL-FREE Boolean instance `BModelsSig` once for each realised signature -- and `sigs G` is a `Finset`, whose cardinality is bounded below without any reference to the number of labels. | yes | p c q |
| 21 | `mem_bitVectors` | Every bit vector of length `n` is enumerated by `bitVectors n`. | yes | p c q |
| 22 | `card_bitVectors` | There are at most `2^n` bit vectors of length `n`. | yes | p c q |
| 23 | `card_sigs_le_two_pow` | Bound 1. A system of `k` constraints realises at most `2 ^ k` signatures. | yes | p c q |
| 24 | `card_sigs_le_two_pow_of_blocks` | The same bound in the form the input data suggests: `k` is the number of concrete blocks, i.e. the length of the block list `G.map Constraint.conc`. | yes | p c q |
| 25 | `card_sigs_le_labels` | Bound 2. A system mentioning `L` labels realises at most `L + 1` signatures -- the `+1` being the all-false class shared by every unmentioned label, no matter how many of those there are. | yes | p c q |
| 26 | `card_sigs_le` | Both bounds at once. Neither dominates the other: on `wideSchema w` (§7) the first bound gives `8` and the second `w + 2`, while on `genSys k` (§8) the two coincide at `2 ^ k` and are both attained (`genSys_bounds_tight`). | yes | p c q |
| 27 | `sig_rep` | A chosen representative of a signature really does have that signature. | yes | p c q |
| 28 | `transversal_reps` | The chosen representatives form a transversal. | yes | p c q |
| 29 | `card_reps_le` | There are no more representatives than signatures. | yes | p c q |
| 30 | `satisfiable_decided_by_reps` | The scaling theorem for satisfiability. There is a set of at most `min (2 ^ k) (L + 1)` labels -- `k` constraints, `L` labels mentioned -- whose Boolean instances decide satisfiability of the whole system. | yes | p c q |
| 31 | `entails_decided_by_reps` | The scaling theorem for entailment. Same, for `Entails G c`, with the representatives taken for `c :: G`. | yes | p c q |
| 32 | `mem_blocks` | Membership in the multiset of concrete blocks. | yes | p q |
| 33 | `sig_eq_bsig` | Under laminarity a label's signature is determined by its block. Membership in a block is the same as equality to that block, so the label itself drops out. | yes | p c q |
| 34 | `transversal_of_blocks` | What the solver should actually do. On a laminar system it is enough to take one label out of each nonempty block -- one column per table -- together with one label outside every block. No block is ever enumerated. | yes | p c q |
| 35 | `satisfiable_by_one_label_per_block` | The decision procedure that statement licenses. | yes | p c q |
| 36 | `card_sigs_le_blocks` | The practically important corollary. If the concrete blocks are pairwise disjoint or equal, the number of signature classes is at most (number of DISTINCT blocks) plus one -- with no dependence whatsoever on how many labels those blocks contain. | yes | p c q |
| 37 | `card_sigs_le_nonempty_blocks` | Sharpened: empty blocks contain no label, so they cost nothing. | yes | p c q |
| 38 | `satisfiable_decided_by_blocks` | The scaling theorem for schemas. On a laminar system, satisfiability is decided by one Boolean solve per distinct table, plus one -- whatever the tables' widths. | yes | p c q |
| 39 | `wideSchema_blocks` | The wide-schema witness's blocks, computed. | yes | p c q |
| 40 | `wideSchema_laminar` | The wide-schema witness is laminar. | yes | p c q |
| 41 | `wideSchema_card_blocks` | It has at most 2 distinct blocks, whatever the width. | yes | p c q |
| 42 | `wideSchema_card_sigs` | At most three signature classes, for every width. | yes | p c q |
| 43 | `wideSchema_concLabels` | Its concrete labels are `range (w+1)` -- it really is `w`-wide. | yes | p c q |
| 44 | `wideSchema_width_independent` | The headline. The system mentions `w + 1` labels but has at most `3` signature classes -- so a naive per-label procedure does `w + 1` Boolean solves where the signature procedure does `3`, for every width `w`. A 500-column table costs the same as a 1-column table. | yes | p c q |
| 45 | `genSys_length` | `genSys k` has exactly `k` constraints. | yes | p c q |
| 46 | `sig_genSys` | The signature of `l` under `genSys k` is the binary expansion of `l`. | yes | p c q |
| 47 | `sig_genSys_inj` | Distinct labels below `2^k` get distinct signatures. | yes | p c q |
| 48 | `card_sigs_genSys` | Tightness. `k` blocks in general position realise ALL `2 ^ k` signatures, so the bound of §4 cannot be improved without a hypothesis on the blocks. | yes | p c q |
| 49 | `mem_concLabels_genSys` | The blocks of `genSys k` together mention every nonzero label below `2 ^ k`. | yes | p c q |
| 50 | `concLabels_genSys` | `genSys k` mentions exactly the nonzero labels below `2^k`. | yes | p c q |
| 51 | `card_concLabels_genSys` | ... that is, `2^k - 1` of them. | yes | p c q |
| 52 | `genSys_bounds_tight` | Neither general bound is slack. On `genSys k` the constraint-count bound and the label-count bound COINCIDE at `2 ^ k`, and the true number of classes is `2 ^ k`. So no combination of the two bounds of §4 improves on either: only a hypothesis on the SHAPE of the blocks, such as `Laminar`, can. | yes | p c q |
| 53 | `genSys_not_laminar` | The tight witness is genuinely outside the laminar fragment: blocks `0` and `1` of `genSys 2` are neither equal nor disjoint (they share the label `3`). | yes | p c q |

### `Berthomieu.lean` — 48 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `EqOutside.refl` | `=_L` is reflexive. | yes | p c q |
| 2 | `EqOutside.symm` | `=_L` is symmetric. | yes | p c q |
| 3 | `EqOutside.trans` | `=_L` is transitive. | yes | p c q |
| 4 | `EqOutside.mono` | Agreeing outside a smaller set is more informative. | yes | p c q |
| 5 | `EqOutside.inter` | Fusion. Two `=_L` facts about the same pair combine by INTERSECTING the exception sets. Through the complement this is Pottier's fusion law `(L₁ : e) ∧ (L₂ : e) ≡ (L₁ ∪ L₂) : e`. | yes | p c q |
| 6 | `EqOutside.trans_union` | Composition. Chaining two `=_L` facts UNIONS the exception sets. Through the complement this is Pottier's (TRANS-ROW), whose filters intersect. | yes | p c q |
| 7 | `eqOutside_equivalence` | `=_L` for fixed `L` is an equivalence relation. | yes | p c q |
| 8 | `eqOutside_empty` | With no exceptions allowed, `=_L` IS equality. | yes | p c q |
| 9 | `eqOutside_iff_sdiff` | The closed form: `r =_L s` iff `r` and `s` have the same part outside `L`. | yes | p c q |
| 10 | `eqOutside_of_subset` | Two rows that both live inside `L` agree outside it, vacuously. | yes | p c q |
| 11 | `EqOutside.reconstruct` | Determination. `r =_L s` together with the two rows' traces on `L` pins them down: knowing `s` and `r ∩ L` reconstructs `r` exactly. | yes | p c q |
| 12 | `EqOutside.eq_of_inter` | Determination, sharp form. `=_L` plus equality of the traces on `L` is equality. | yes | p c q |
| 13 | `sat_ext_iff` | Single-label extension, exactly. `a <- (b, (/ℓ/))` is `=_{ℓ}` plus two presence bits. This is Pottier's cosingleton-filter idiom in Ermine's equality-only setting, and it is the constraint shape for which `=_L` really is the right notation. | yes | p c q |
| 14 | `bcDefines_eqOut` | Non-vacuity: `BC` does define something, namely `=_L` itself. | yes | p c q |
| 15 | `not_bcDefines_of_pointwise` | The master lemma. If a pointwise operation on rows preserves every model of `Φ`, then no predicate that the operation destroys can be defined by `Φ` -- for ANY interface `S`, hence with any number of auxiliary variables. | yes | p c q |
| 16 | `bcModels_insert` | The invariance. Inserting one and the same label into EVERY variable preserves every Berthomieu system. No freshness hypothesis is needed: equality is a congruence, and at the inserted label both sides of any `=_L` become true simultaneously. | yes | p c q |
| 17 | `bcModels_empty` | The everywhere-empty assignment models EVERY Berthomieu system. So `BC` cannot even express "this row is nonempty", and every `BC`-definable predicate must hold of the empty assignment. | yes | p c q |
| 18 | `bcDefines_empty` | Consequently every `BC`-definable predicate holds of the empty assignment. | yes | p c q |
| 19 | `not_sat_const` | A CONSTANT nonempty assignment breaks any partition with at least two variable parts: two distinct positions of the right-hand side then carry the same nonempty row, and `Sat` demands they be disjoint. | yes | p c q |
| 20 | `not_defines_partition` | THE SEPARATION. No system of Berthomieu constraints -- over any interface, with any number of auxiliary variables, finite or not -- defines Ermine's binary partition `a <- (b, c)`. The variables `a`, `b`, `c` need not be distinct. | yes | p c q |
| 21 | `not_defines_partition_list` | The finite reading asked for: `Φ` a finite LIST of constraints over `{a, b, c}` plus auxiliaries. | yes | p c q |
| 22 | `not_defines_partition_noaux` | The auxiliary-free reading, spelled out: no `BC` system is satisfied by EXACTLY the assignments satisfying `a <- (b, c)`. | yes | p c q |
| 23 | `not_defines_of_conc_ne` | A concrete part is already fatal: the empty assignment models every `BC` system, but does not satisfy a partition with a nonempty concrete part. | yes | p c q |
| 24 | `not_defines_of_length_ne_one` | Zero or two-or-more variable parts is fatal too, by the invariance. | yes | p c q |
| 25 | `defines_unary` | The one positive case: `a <- (b)` is `a = b`, and `BC` says that. | yes | p c q |
| 26 | `defines_partition_iff` | Classification. A partition constraint is Berthomieu-definable exactly when it is the trivial one-variable, no-concrete-part constraint. | yes | p c q |
| 27 | `mem_litLabels` | Every label named by a literal of a system is in the system's label set. | yes | p c q |
| 28 | `not_bcxDefines_of_pointwise` | The master lemma, for the extended language. | yes | p c q |
| 29 | `bcxModels_insert` | The invariance, extended. Inserting a label that no absence literal mentions into every variable still preserves every model. | yes | p c q |
| 30 | `berthomieu_separation` | THE SEPARATION, in its strongest form proved here. Even with equalities, `=_L`, and arbitrary presence/absence literals, no finite system defines `a <- (b, c)`. | yes | p c q |
| 31 | `definesX_extension` | ... yet the extended language DOES define single-label record extension. This is Pottier's cosingleton-filter idiom: "`a` and `b` agree away from `ℓ`, `ℓ` is present in `a` and absent from `b`". | yes | p c q |
| 32 | `bcModels_map` | Equality-only systems are preserved by every pointwise map of rows. | yes | p c q |
| 33 | `not_defines_eqOutside_of_isEq` | Strictness. No equality-only system defines `=_{0}` between two distinct variables. Hence `BC` is strictly more expressive than its `eq`-only fragment. | yes | p c q |
| 34 | `eqOutside_conc_of_sat` | Partition entails `=_L`. Outside its concrete part, the left-hand row of a satisfied constraint agrees with the union of its variable parts. This is the `=_L` shadow of every Ermine constraint. | yes | p c q |
| 35 | `eqOutside_leaves` | `=_L` reading of the leaf expansion. For every system and every variable, the row of `a` agrees, outside `kern G a`, with the union of the rows of its leaves. | yes | p c q |
| 36 | `eq_leaves_of_abstract` | On Ermine's actual residuals, `=_L` collapses to `=`. All 345 residual partition constraints measured over the stdlib closure are purely abstract, so `kern G a = ∅` and `EqOutside ∅` is equality: the leaf expansion is a plain equation and the exception set has nothing to hold. | yes | p c q |
| 37 | `sat_two_iff_eqOutside` | The exact diagnosis. Ermine's `a <- (b, c)` IS a `=_L` constraint -- with the exception set taken to be the row of a VARIABLE, plus disjointness and containment. Berthomieu's `L` is a constant; that difference is exactly what `not_defines_partition` measures. | yes | p c q |
| 38 | `eq_iff_inter_of_eqOutside` | Determination in Ermine terms: if two rows are known to agree away from a concrete label set `L`, then their traces on `L` decide equality -- a `/L/`-bit test rather than a whole-row comparison. | yes | p c q |
| 39 | `mem_toggle_of_ne` | Toggling `ℓ` leaves every other label's membership alone. | yes | p c q |
| 40 | `mem_toggle_self` | ... and flips `ℓ`'s. | yes | p c q |
| 41 | `toggle_singleton` | Toggling `ℓ` in `{ℓ}` gives `∅`. | yes | p c q |
| 42 | `toggle_empty` | ... and in `∅` gives `{ℓ}`. | yes | p c q |
| 43 | `bcModels_toggle` | The second invariance. Toggling one label in every variable preserves every Berthomieu system: equality is a congruence, and `=_L` only ever compares the two sides at the same label, where toggling negates both. | yes | p c q |
| 44 | `bcxModels_toggle` | The same, for the extended language, at a label no literal mentions. | yes | p c q |
| 45 | `exists_partition_iff_subset` | The residual row of a partition exists exactly when the part is contained in the whole. This is the semantics of Ermine's `Has`. | yes | p c q |
| 46 | `has_iff_subset` | `Has` is subsumption. `∃ c. a <- (b, c)`, with `c` a variable distinct from `a` and `b` and free to take any value, holds exactly when `rho b ⊆ rho a`. | yes | p c q |
| 47 | `not_defines_subset` | Subsumption is not Berthomieu-definable. Hence neither is Ermine's `Has`. | yes | p c q |
| 48 | `not_definesX_subset` | ... and the extended language does not reach it either. | yes | p c q |

### `Cut.lean` — 117 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `Names.named` | If `z` is `G`'s name for the block `S`, then `S` is named in `G` at all. The predicate form of the Scala's `rhss(RHSAbstr(int))` reverse lookup. | yes | p c q |
| 2 | `Named.mono` | Being named survives adding constraints. Every rule in the file is monotone, so this is what makes the lookup stable along a run. | yes | p c q |
| 3 | `Names.mem_allVars` | A name is a variable the system already mentions — the fact that makes branch (a) non-generative. | yes | p c q |
| 4 | `CsePair.mem₁` | Projection: the first premise is in the system. | yes | p c q |
| 5 | `CsePair.mem₂` | Projection: the second premise is in the system. | yes | p c q |
| 6 | `CsePair.lhs_ne` | Projection: the rule fires only across *different* left-hand sides. | yes | p c q |
| 7 | `CsePair.two_le` | Projection: the guard `int.size >= 2`. | yes | p c q |
| 8 | `CsePair.toApp` | A CSE pair plus a genuinely fresh `z` is exactly `Divergence.CseApp`, the premise of branch (c). The three branches share one premise pattern. | yes | p c q |
| 9 | `subset_reuseResult` | REUSE is monotone: it adds constraints and erases none. | yes | p c q |
| 10 | `subset_foldResult` | FOLD is monotone. | yes | p c q |
| 11 | `CutStep.toBranch` | Every cut step is a step of the full three-branch rule. This is what lets every cut run be compared with a full run. | yes | p c q |
| 12 | `CseStep.toBranch` | So is every `Divergence.CseStep`, i.e. every branch-(c) step. | yes | p c q |
| 13 | `CutStep.subset` | Cut steps are monotone. | yes | p c q |
| 14 | `CseBranch.subset` | So is the full rule, all three branches. | yes | p c q |
| 15 | `fold_names` | **Under FOLD's guard the premise `c₁` IS a naming constraint for the shared block.** In this model branch (b) is therefore an instance of branch (a). (See the faithfulness note: this is a fact about the rule, not a claim that Ermine's REUSE branch fires first.) | yes | p c q |
| 16 | `fold_first_conclusion_vacuous` | **Why FOLD emits one constraint where REUSE emits two.** Under the guard, the missing conclusion is `reduce c₁ int c₁.lhs = mk c₁.lhs {c₁.lhs} ∅` — the vacuous self-partition `a <- a`, satisfied by every assignment. | yes | p c q |
| 17 | `foldResult_eq` | Consequently `reuseResult` at `z := c₁.lhs` is `foldResult` plus that vacuous constraint. The two kept branches are one rule. | yes | p c q |
| 18 | `shared_comm` | `shared` is symmetric, being an intersection. *(Added during integration.)* | yes | p c q |
| 19 | `CsePair.symm` | The CSE premise pattern is symmetric in its two constraints. *(Added during integration.)* | yes | p c q |
| 20 | `fold_symm` | **The Scala's second fold case (`rhs2 == rhsCommon`) is a derivable instance of the first**, so modelling one case loses nothing. *(Added during integration.)* | yes | p c q |
| 21 | `sat_reduce_of_denotes` | **The core lemma of the file.** If `rho` satisfies `c` and `z` already denotes the union of a sub-group `S ⊆ vset c`, then `rho` *already* satisfies the contracted constraint. No freshness, no `z ∉ vset c`, no update of `rho` — plain entailment. `Divergence.sat_reduce` carries all those side conditions because it is stated for a *minted* name. | yes | p c q |
| 22 | `Names.denotes` | A named block really denotes its union under every model — the hypothesis `sat_reduce_of_denotes` needs, discharged from the naming constraint. | yes | p c q |
| 23 | `reuse_entails` | **Branch (a) is outright ENTAILMENT.** Both conclusions of REUSE are semantic consequences of the premises. | yes | p c q |
| 24 | `fold_entails` | **Branch (b) is outright ENTAILMENT.** | yes | p c q |
| 25 | `CutStep.models_iff` | **The kept branches do not change the models at all.** Not merely satisfiability-preserving, not merely conservative over the old vocabulary: the model *set* is literally unchanged. | yes | p c q |
| 26 | `CutStep.satisfiable_iff` | Corollary: a cut step preserves satisfiability in both directions. | yes | p c q |
| 27 | `CutStep.entails_iff` | Corollary: a cut step preserves entailment of *every* constraint, with no vocabulary restriction. | yes | p c q |
| 28 | `sConservativeExt_iff` | The finset-transported notion of conservative extension *is* `Rules.ConservativeExt`, so §2 connects to the audited rule set rather than to a look-alike. | yes | p c q |
| 29 | `mint_conservativeExt` | **Branch (c) is sound too, as a conservative extension at the minted variable.** Every model of the premises extends — changing only `z` — to a model of the conclusion, and every model of the conclusion already models the premises. Outright entailment is not even well-formed here, since `z` is new. | yes | p c q |
| 30 | `CutStep.conservativeExt` | The kept branches are conservative extensions degenerately: at *any* variable, with the identity extension, since they add nothing that needed a name. | yes | p c q |
| 31 | `CseBranch.satisfiable_iff` | All three branches preserve satisfiability — the fact `complete_refuter_unaffected` turns on. | yes | p c q |
| 32 | `CseBranch.entails_iff` | All three preserve entailment over the input's vocabulary. For branch (c) the restriction is essential (`Compare.vocabulary_restriction_necessary`). | yes | p c q |
| 33 | `CutSteps.toBranchSteps` | Every *run* of the cut solver is a run of the full solver. | yes | p c q |
| 34 | `BranchSteps.subset` | Full runs are monotone. | yes | p c q |
| 35 | `CutSteps.subset` | Cut runs are monotone. | yes | p c q |
| 36 | `BranchSteps.satisfiable_iff` | A full run preserves satisfiability, by induction on its length. | yes | p c q |
| 37 | `BranchSteps.entails_iff` | A full run entails exactly what its input entailed, for constraints over the input's vocabulary. | yes | p c q |
| 38 | `CutSteps.models_iff` | A whole cut *run* leaves the model set unchanged, not just one step. | yes | p c q |
| 39 | `cut_preserves_meaning` | **Dropping branch (c) cannot change the set of models.** Any cut run and any full run from the same input are equisatisfiable, and over the input's own vocabulary entail exactly the same constraints — namely exactly what the input entailed. | yes | p c q |
| 40 | `unsat_mono` | **The useful direction of refutation monotonicity.** Adding constraints only destroys models, so unsatisfiability of a subsystem is inherited by every supersystem. (The task statement posed this as the thing to refute; it is in fact true, and one line. See the head of §3.) | yes | p c q |
| 41 | `RefuteEx.sub` | `{x <- (\|1\|)} ⊆ {x <- (\|1\|), x <- (\|2\|)}`. | yes | p c q |
| 42 | `RefuteEx.GA_sat` | The smaller system has a model. | yes | p c q |
| 43 | `RefuteEx.GB_unsat` | The larger one does not: `x` cannot be both `{1}` and `{2}`. | yes | p c q |
| 44 | `unsat_not_antitone` | **The CONVERSE of `unsat_mono` is false.** Unsatisfiability of the larger system does not imply unsatisfiability of the smaller. This is the statement the task meant to name. | yes | p c q |
| 45 | `Refuter.sound` | Projection: a refuter only fires on genuinely unsatisfiable systems. | yes | p c q |
| 46 | `Refuter.mono` | Projection: deriving more constraints can only make it fire more. Ermine's error conditions 10 and 11 have this shape. | yes | p c q |
| 47 | `run_refutation_sound` | If a sound refuter fires anywhere reachable from `G₀`, then `G₀` had no model — for cut and full runs alike. | yes | p c q |
| 48 | `cut_never_wrongly_refutes` | **The cut never rejects a well-typed program.** Soundness of the refuter plus meaning preservation of the cut run is already enough; the argument does not even need that the cut derives less. | yes | p c q |
| 49 | `fires11_sound` | Ermine's error condition 11 is a sound refutation test: a fully concrete partition `a <- C` plus another partition of `a` with a concrete part outside `C` is unsatisfiable. | yes | p c q |
| 50 | `fires11_mono` | … and it is monotone. | yes | p c q |
| 51 | `fires11_GB` | Condition 11 fires on the larger system. | yes | p c q |
| 52 | `not_fires11_GA` | … and not on the smaller one. | yes | p c q |
| 53 | `refuter_can_miss` | **A sound monotone refuter can fire on the larger derived set and not on the smaller.** So a saturation that derives fewer constraints can fail to refute — the direction in which the cut is risky. | yes | p c q |
| 54 | `complete_refuter_unaffected` | **The most decision-relevant theorem in the file, and it was not asked for.** A *complete* refuter — one firing exactly on the unsatisfiable systems — is untouched by any branch, minting included, because every branch preserves satisfiability. **Any refutation the cut can lose is attributable purely to the incompleteness of Ermine's syntactic error conditions, never to a loss of semantic information.** | yes | p c q |
| 55 | `cut_risk_is_one_sided` | **The risk direction in one statement.** The cut can accept an ill-typed program; it can never reject a well-typed one. | yes | p c q |
| 56 | `allVars_insert` | Vocabulary of an extended system. | yes | p c q |
| 57 | `allVars_insert_eq_of_subset` | Adding a constraint whose variables are already present leaves the vocabulary fixed. | yes | p c q |
| 58 | `reduce_lhs` | Contraction preserves the left-hand side. | yes | p c q |
| 59 | `reduce_conc` | Contraction preserves the concrete part. | yes | p c q |
| 60 | `vset_reduce` | Variable set of a contraction. | yes | p c q |
| 61 | `vset_reduce_subset` | A contraction's variables come from the existing vocabulary, given that the name does. | yes | p c q |
| 62 | `reduce_vars_subset` | … including its left-hand side. | yes | p c q |
| 63 | `CutStep.allVars_eq` | **The kept branches are non-generative**: a REUSE or FOLD step introduces no variable the system did not already mention. Contrast `CseApp.fresh`, where MINT introduces one by construction. | yes | p c q |
| 64 | `CutSteps.allVars_eq` | … and so does a whole cut run. | yes | p c q |
| 65 | `card_vset_reduce_lt` | **The kept branches strictly contract**: replacing a block of ≥ 2 variables by its single name lowers the constraint's arity. | yes | p c q |
| 66 | `CutStep.new_constraints` | **Exactly what a kept branch adds.** Every constraint of the successor system is either already present, or is a contraction of one that is — same left-hand side, same concrete part, variables from the existing vocabulary, strictly smaller arity, *and entailed*. | yes | p c q |
| 67 | `mem_normalForms` | Membership in the finite universe of `mk`-normal constraints over a vocabulary and a set of concrete parts. | yes | p c q |
| 68 | `allVars_normalForms` | That universe does not enlarge the vocabulary. | yes | p c q |
| 69 | `concs_normalForms` | … nor the set of concrete parts. | yes | p c q |
| 70 | `allVars_union` | Vocabulary of a union. | yes | p c q |
| 71 | `subset_bound` | A system is inside its own bound. | yes | p c q |
| 72 | `allVars_bound` | The bound has the same vocabulary as the system. | yes | p c q |
| 73 | `concs_bound` | … and no new concrete parts. | yes | p c q |
| 74 | `reduce_mem_bound` | A contraction of a bounded constraint stays inside the bound — the step case of the invariant. | yes | p c q |
| 75 | `CutStep.bound_invariant` | **`bound G₀` is invariant under cut steps.** Every cut run from `G₀` stays inside one explicit finite set. | yes | p c q |
| 76 | `CutChain.toSteps` | A productive chain is a run. (`CutChain` requires each step to actually enlarge the system: re-deriving what is already present is idling, not divergence, and every implementation deduplicates.) | yes | p c q |
| 77 | `CutChain.bounded` | Every productive cut chain stays inside `bound G₀`. | yes | p c q |
| 78 | `CutChain.card_ge` | A productive chain of length `n` has grown the system by at least `n`. | yes | p c q |
| 79 | `CutChain.length_le` | **The kept branches terminate.** Any chain of productive REUSE/FOLD steps from `G₀` has length at most `(bound G₀).card`. | yes | p c q |
| 80 | `cut_branches_terminate` | The same as an explicit bound depending only on the input. | yes | p c q |
| 81 | `ResApp.mem₁` | Projection: `resolution`'s first premise. | yes | p c q |
| 82 | `ResApp.mem₂` | Projection: its second premise. | yes | p c q |
| 83 | `ResApp.tops` | Projection: `tops = C \ D` is nonempty. | yes | p c q |
| 84 | `ResApp.bots` | Projection: `bots = D \ C` is nonempty. | yes | p c q |
| 85 | `ResApp.fresh` | Projection: `z` is genuinely fresh. **There is no `already named` side condition, because the Scala rule has none** — `resolution` takes no `rhss` argument. | yes | p c q |
| 86 | `subset_resResult` | Resolution is monotone. | yes | p c q |
| 87 | `ResStep.subset` | … as a step relation. | yes | p c q |
| 88 | `ResStep.fresh_var` | Every resolution step introduces a variable the system did not have. | yes | p c q |
| 89 | `ResStep.escapes` | **`resolution` escapes §4's vocabulary bound on its very first step.** This is precisely why the argument that terminates the kept branches does not extend to the cut rule set. | yes | p c q |
| 90 | `ResStep.ssubset` | A resolution step strictly enlarges the system. | yes | p c q |
| 91 | `ResStep.card_lt` | … so its cardinality strictly grows. | yes | p c q |
| 92 | `res_exists_step` | **A resolution step is always available on a matching pair.** Freshness never blocks it and — unlike `splitConcrete` — nothing else does either. | yes | p c q |
| 93 | `ResSteps.subset` | Resolution runs are monotone. | yes | p c q |
| 94 | `res_steps_exists` | From one fixed matching pair there are resolution chains of every length. | yes | p c q |
| 95 | `res_steps_measure` | Any measure decreasing on every resolution step bounds chain length. | yes | p c q |
| 96 | `resSeed_tops` | The seed's `tops` is nonempty. | yes | p c q |
| 97 | `resSeed_bots` | … and so is its `bots`, so `resolution` fires. | yes | p c q |
| 98 | `resSeed_diverges` | **The rule set that survives the cut does not terminate.** From the two-constraint seed `a <- (\|1\|) x`, `a <- (\|2\|) y` there are resolution chains of every length, the system growing by at least one constraint per step. Compare `Divergence.seed_diverges`, which says the same of the branch the cut *removes*: cutting branch (c) does not remove the phenomenon, only one of its sources. | yes | p c q |
| 99 | `res_no_decreasing_measure` | **No measure into `ℕ` decreases on every resolution step.** | yes | p c q |
| 100 | `SplitApp.mem` | Projection: `splitConcrete`'s premise. | yes | p c q |
| 101 | `SplitApp.conc_ne` | Projection: `C+` is nonempty. | yes | p q |
| 102 | `SplitApp.two_le` | Projection: the guard `abstr.size >= 2`. | yes | p c q |
| 103 | `SplitApp.unnamed` | **Projection: the reverse lookup missed.** This is the Scala's `rhss(RHSAbstr(abstr)) == None` — the guard `resolution` does not have, and the whole reason the two retained rules behave differently. | yes | p c q |
| 104 | `SplitApp.fresh` | Projection: `u` is genuinely fresh. | yes | p c q |
| 105 | `subset_splitResult` | `splitConcrete` is monotone. | yes | p c q |
| 106 | `SplitStep.subset` | … as a step relation. | yes | p c q |
| 107 | `mem_splitCands` | Characterisation of the variable groups `splitConcrete` could still name. | yes | p c q |
| 108 | `SplitStep.cands_lt` | **The reverse lookup IS a termination measure for `splitConcrete`.** Each mint names a group that had no name, and neither constraint it emits is itself a candidate (one has an empty concrete part, the other arity one), so no new candidate is ever created. | yes | p c q |
| 109 | `SplitSteps.length_le` | Every split chain from `G₀` is at most `(splitCands G₀).card` long. | yes | p c q |
| 110 | `split_terminates` | **`splitConcrete` terminates**, fresh name notwithstanding. So it is *not* the obstruction. | yes | p c q |
| 111 | `cut_no_decreasing_measure` | **NEGATIVE RESULT. No measure into `ℕ` decreases on every step of the cut rule set** — the standard finiteness argument does not merely fail to apply; no well-founded `ℕ`-ranking of systems exists at all. The obstruction is `resolution`; the kept CSE branches and `splitConcrete` each terminate on their own. | yes | p c q |
| 112 | `cut_does_not_terminate` | **The §5 verdict, in one statement.** (i) `resolution` alone admits chains of every length from a two-constraint seed; (ii) hence no `ℕ`-valued measure decreases on every cut-rule step; (iii) the §4 finiteness argument fails for a specific identifiable reason — a resolution step leaves the vocabulary bound at once. | yes | p c q |
| 113 | `CutExample.shared₁₂` | The example pair shares exactly `{2,3}`. | yes | p c q |
| 114 | `CutExample.sharedE` | … and so does the fold example. | yes | p c q |
| 115 | `CutExample.reuse_fires` | **Branch (a) can actually fire.** Non-vacuity. | yes | p c q |
| 116 | `CutExample.fold_fires` | **Branch (b) can actually fire.** Non-vacuity. | yes | p c q |
| 117 | `cut_removes_something` | **The cut really removes derivations.** On `Divergence.seed` the shared block has no name and neither premise *is* the block, so branches (a) and (b) are both inapplicable while branch (c) fires. The cut is not a no-op, and §2's meaning-preservation theorem is not vacuous. | yes | p c q |

### `Compare.lean` — 27 theorems, 0 gaps

| # | theorem | statement | proved | axioms |
|---|---|---|---|---|
| 1 | `varsOf_toList` | Bridge: the `varsOf` of a system's `toList` is its `allVars`. This is what makes §1 a statement about `Canonical`'s ACTUAL measure rather than a look-alike. | yes | p c q |
| 2 | `lexLt_asymm` | The lexicographic order used by `Canonical.Meas` is asymmetric. | yes | p q |
| 3 | `resStep_allVars_card_lt` | A retained `resolution` step strictly enlarges the vocabulary. | yes | p c q |
| 4 | `resStep_canonical_measure_increases` | **`Canonical`'s measure goes the WRONG way on a rule the cut retains, in its dominant coordinate.** `Canonical.Step.decreasing` asserts `LexLt (Meas s'.cs) (Meas s.cs)` for every clean rule; here the same `LexLt` holds in the opposite direction. | yes | p c q |
| 5 | `resStep_canonical_measure_fails` | … hence the clean calculus's measure certainly does not decrease on the cut. **Its termination argument is not merely unavailable for the cut, it is refuted for it.** | yes | p c q |
| 6 | `rhoRes_models` | `a = {1,2}`, `x = {2}`, `y = {1}` models the divergent seed. | yes | p c q |
| 7 | `resSeed_satisfiable` | **The seed carrying `Cut.resSeed_diverges` is SATISFIABLE.** So the obstruction is not the degenerate `unsatisfiable input, anything goes` case: the correct answer on that input is *satisfiable*, and no measure argument can certify that the retained rule ever reaches it. This materially strengthens `Cut.resSeed_diverges`, which said nothing about models. | yes | p c q |
| 8 | `termination_separation` | **The termination separation as one statement.** The clean calculus terminates; so do the cut's kept CSE branches; the cut rule set admits no `ℕ`-valued decreasing measure at all, the obstruction living on an input that has a model; and the clean calculus's own measure runs strictly backwards on the rule responsible. | yes | p c q |
| 9 | `canonical_preserves_models` | Cited: every rule of the clean calculus preserves the model set exactly. | yes | p c q |
| 10 | `cut_branch_preserves_models` | Cited from `Cut.lean`: so does every kept branch of the cut. | yes | p c q |
| 11 | `resStep_models_downward` | The half a monotone rule gets for free: models of the conclusion model the premises. | yes | p c q |
| 12 | `res_not_model_preserving` | **A retained minting step does NOT preserve the model set.** Send the fresh `z` to `{9}`: it models the premises and refutes the conclusion, because `a <- (z, …)` forces `rho z ⊆ rho a`. This is the precise sense in which the cut's meaning preservation is weaker than `Canonical.Step.preserves`. | yes | p c q |
| 13 | `res_conservative` | Cited and instantiated: the retained `resolution` **is** a conservative extension. `Rules.rule6` with `C := C₁ \ C₂`, `D := C₁ ∩ C₂`, `E := C₂ \ C₁` — exactly the `tops`/`bots` split the Scala computes. (`Cut.mint_conservativeExt` does this for the branch being *cut*; this does it for one being *kept*.) | yes | p c q |
| 14 | `split_conservative` | Cited and instantiated: the retained `splitConcrete` is a conservative extension (`Rules.rule4`). | yes | p c q |
| 15 | `vocabulary_restriction_necessary` | **The vocabulary restriction in `Cut.cut_preserves_meaning` cannot be dropped.** A single branch-(c) step entails `z <- x⁺` for its own minted `z`, and the premises do not. So `the cut loses nothing` is a statement about the *user's* variables; about minted ones the cut and the uncut solver genuinely disagree. | yes | p c q |
| 16 | `preservation_strength` | **The precise difference in strength**, as one statement: model-set equality for the clean calculus and for the cut's kept branches, one direction only for a retained minting step, and a counterexample to the other. | yes | p c q |
| 17 | `FullCutSteps.eq_of_normalForm` | Nothing reduces out of a cut normal form. | yes | p c q |
| 18 | `card_vset_res_premise` | A `resolution` premise carries exactly one right-hand variable. | yes | p c q |
| 19 | `fullCutNormalForm_of` | **A sufficient criterion for a cut normal form.** Clean-normal, plus no constraint of arity ≥ 2, plus no two `resolution` premises with crossing concrete parts. The first hypothesis kills `Canonical`'s six rules, the second kills all four CSE and split branches at once, the third kills `resolution`. This is what makes confluence inheritance a theorem rather than an observation. | yes | p c q |
| 20 | `full_cut_step_S1` | The `occurs` branch of the critical pair is a cut step. | yes | p c q |
| 21 | `full_cut_step_S2` | So is the `absorb` branch. | yes | p c q |
| 22 | `full_cut_normal_S1` | The `occurs` result is a normal form for the WHOLE cut rule set: every constraint has an empty right-hand side, so all five retained generative rules are blocked. | yes | p c q |
| 23 | `full_cut_normal_S2` | The `absorb` result is too — **and this is the tight case.** `a <- (a, (\|{7}\|))` *does* have the shape of a `resolution` premise; the rule is blocked not by a shape mismatch but because the only other constraint has a different left-hand side, so it can pair only with itself, and then `tops = ∅`. Had the concrete parts differed, the cut would have had a step where the clean calculus does not and the inheritance claim would have failed. | yes | p c q |
| 24 | `full_cut_not_locally_confluent` | **The cut inherits the failure of local confluence.** One state steps to two distinct states, each a normal form for the entire cut rule set. Deleting branch (c) does not touch the ambiguity, because the ambiguity is between two rules the cut leaves alone. | yes | p c q |
| 25 | `full_cut_not_joinable` | … hence the two results have no common reduct under the cut either: normal forms are not unique for it, as they are not for the clean calculus. | yes | p c q |
| 26 | `full_cut_normal_form_can_be_unsat` | **The cut inherits `Canonical.CriticalPair.normal_form_can_be_unsat`.** `S1` says `b = ∅` and `b = {7}` at once; it is unsatisfiable, and no rule of the cut — generative or not — detects it. Neither proposal is a decision procedure, and neither is closer to being one. | yes | p c q |
| 27 | `bottom_line` | **The comparison as one theorem.** Termination for the clean calculus, for the cut's kept branches, and its failure for the cut rule set (on satisfiable input, with the clean calculus's own measure running backwards); model-set preservation for the clean calculus, for the kept branches, and its refutation for a retained minting rule; the inherited failure of confluence; the inherited failure to decide satisfiability. The grid is machine-checked as a unit, not only row by row. | yes | p c q |
