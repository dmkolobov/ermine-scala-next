# Keying `splitConcrete`'s guard on `(lhs, concrete part)` — Stage 1 (Lean)

Module: `tracker/lean/Rowpartition/KeyedSplit.lean` (872 lines; 5 structures/inductives,
3 definitions, 57 theorems).  Nothing else was edited; the module is **not** added to the
root `Rowpartition.lean` (the orchestrator integrates).  Explorer change:
`tracker/tools/rowclosure.py` gains a `--split-key` flag (default OFF, backward compatible).
Date 2026-09-03.

---

## 1. Headline

Replacing `splitConcrete`'s SYNTACTIC reverse lookup (`¬ Named G (vset c)` — "nothing names
this GROUP", `Cut.SplitApp`) by the KEYED one (`¬ Resolved G c.lhs c.conc` — "nothing names
`c.lhs \ c.conc`", the guard `ResGuard.lean` already gives `resolution`) turns
`DefaultTerm.TerminatesOnSat` from FALSE into TRUE.  Formally: with `KDefaultStep` =
`NonGenStep` + `KSplitStep` + `GResStep` and `KRun` its productive runs,
**`terminatesOnSatKeyed : TerminatesOnSatKeyed`** — from every satisfiable `G₀` there is a
bound, computed from the input, on the length of every productive run in EVERY order —
with the explicit bound `KRun.length_le : n ≤ M · 2^M · 2^|L|`, `M := |allVars G₀| + gmeas L rho G₀`
(`keyed_terminates_of_satisfiable`).  The contrast is stated as
**`keyed_vs_syntactic : TerminatesOnSatKeyed ∧ ¬ TerminatesOnSat`**.  The guard change is
not semantic: the mint branch is a conservative extension at the fresh name
(`ksplit_mint_conservativeExt`) and the reuse branch does not move the model set at all
(`KSplitStep.reuse_models_iff`, from `ksplit_reuse_sat`).  On the very counterexample the
keyed guard fires: `SatDiverge.W2_not_keyed_mint0` (round 0 of the divergent engine is
refused, because `W2` itself carries `p <- (e2, (|k|))`) and
`SatDiverge.W2_keyed_no_second_mint` (the round's mint is refused, because `p <- (u1, (|k|))`
is present), with `SatDiverge.W2_keyed_bound` the bound on that same input.  The two
calculi are incomparable, not nested: `split_mint_not_keyed` exhibits a premise on which the
shipped rule mints and the keyed rule does not.  Every headline theorem uses only
`propext`, `Classical.choice`, `Quot.sound`; no `sorry`, no `native_decide`, no new axiom.

The mechanism in one line: **under a model the minted variable's row is forced by the pair
`(p, K)` alone (`rho u = rho p \ K`), so keying the guard on that pair is the keying that
the semantics already imposes — and that is exactly why `ResGuardTerm` terminates.**  The
keyed split's own witness `mk c.lhs {u} c.conc` has the SAME SHAPE as resolution's, so
`ResGuardTerm.unfired` — the count of keys `K ⊆ L` still open at a variable — is the budget
for BOTH mints, and one measure (`gmeas`) covers the whole calculus.

---

## 2. The relation and the measure

### 2.1 The rule

`splitConcrete` fires on a premise `p <- (S, K)` with `K ≠ ∅`, `2 ≤ |S|`.  What differs is
the reverse lookup consulted before minting:

|  | shipped (`Cut.SplitApp`) | keyed (`KSplitApp`) |
|---|---|---|
| guard | `¬ Named G (vset c)` | `¬ Resolved G c.lhs c.conc` |
| reads | "no bare `d <- S` in `G`" | "no `p <- (z, K)` in `G`" |
| mint emits | `u <- (S)`, `p <- (u, K)` | *the same* (`Cut.splitResult`) |
| reuse premise | `Names G u (vset c)` | `mk c.lhs {u} c.conc ∈ G` |
| reuse emits | `p <- (u, K)` | `u <- (S)` (`kSplitReuseResult`) |

The two reuse branches are duals: the syntactic one has a name for the GROUP and derives
the reduced constraint; the keyed one has a name for the KEY and derives that name's new
definition.  Both are entailed (`split_reuse_entails`, `ksplit_reuse_entails`).

```lean
structure KSplitApp (G : System) (c : Constraint) (u : Var) : Prop where
  mem : c ∈ G
  conc_ne : c.conc ≠ ∅
  two_le : 2 ≤ (vset c).card
  unresolved : ¬ Resolved G c.lhs c.conc
  fresh : u ∉ allVars G

structure KSplitReuseApp (G : System) (c : Constraint) (u : Var) : Prop where
  mem : c ∈ G
  conc_ne : c.conc ≠ ∅
  two_le : 2 ≤ (vset c).card
  witness : mk c.lhs {u} c.conc ∈ G

def kSplitReuseResult (G : System) (c : Constraint) (u : Var) : System :=
  insert (mk u (vset c) ∅) G

inductive KSplitStep : System → System → Prop
  | mint  {G c u} : KSplitApp G c u → KSplitStep G (splitResult G c u)
  | reuse {G c u} : KSplitReuseApp G c u → KSplitStep G (kSplitReuseResult G c u)

inductive KDefaultStep : System → System → Prop
  | nongen {G G'} : NonGenStep G G' → KDefaultStep G G'
  | split  {G G'} : KSplitStep G G' → KDefaultStep G G'
  | gres   {G G'} : GResStep G G' → KDefaultStep G G'

inductive KRun : ℕ → System → System → Prop
  | refl (G) : KRun 0 G G
  | tail {n G₀ G G'} : KRun n G₀ G → KDefaultStep G G' → G ⊂ G' → KRun (n + 1) G₀ G'

def TerminatesOnSatKeyed : Prop :=
  ∀ (G₀ : System) (rho : Assign), SModels rho G₀ →
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), KRun n G₀ G → n ≤ N
```

### 2.2 The measure

`ResGuardTerm`'s, unchanged and re-used verbatim: for a label set `L` bounding every
concrete part (`ConcSub`) and a model `rho`,

```lean
unfired L G v := (L.powerset.filter (fun K => ¬ Resolved G v K)).card
gmeas L rho G := ∑ v ∈ allVars G, unfired L G v * (2 ^ L.card + 1) ^ (rho v).card
```

`unfired L G v` is the number of resolvent keys still OPEN at `v`; it never increases as
`G` grows (`unfired_le`, the guards are monotone) and a mint at the key `K` closes that key
(`unfired_lt`).  The weight base `2^|L| + 1` is one more than the largest possible budget,
so one step down in the exponent outweighs a whole budget (`budget_mul_pow_lt`) — which is
precisely what a mint costs (one unit at the parent) and what it buys (a fresh budget at a
strictly smaller row, `ksplit_rank_lt`).

**What is new here.**  In `ResGuardTerm` only resolution spends the budget; the split was
outside the argument entirely (and `DefaultTerm` §9 says nothing bounds it).  The keyed
split spends the SAME budget, because its emitted witness `c.lhs <- (u, c.conc)` is exactly
the shape `Resolved` looks for.  So `unfired_lt` applies to it with no change, and the
single measure `gmeas` decreases at both mints.

Prose statement of the run invariant: along a keyed run from a model of the input, carrying
the model forward (extended, forced, at each minted variable), `|vocabulary| + gmeas` never
grows — a mint adds one variable and drops `gmeas` by at least one; every other rule adds
no variable and cannot raise `gmeas`.  Hence the vocabulary is bounded by the input alone,
hence (finitely many `mk`-shapes over a bounded vocabulary, one added per productive step)
so is the run.

---

## 3. Every theorem, with status

All **PROVED** unless marked otherwise.  Statements are as in the module.

### §1–2 The rule and its soundness

| name | statement | status |
|---|---|---|
| `KSplitApp`, `KSplitReuseApp`, `kSplitReuseResult`, `KSplitStep` | as §2.1 | proved (definitions) |
| `subset_kSplitReuseResult` | `G ⊆ kSplitReuseResult G c u` | proved |
| `KSplitReuseApp.name_mem_allVars` | `u ∈ allVars G` | proved |
| `KSplitStep.subset` | `KSplitStep G G' → G ⊆ G'` | proved |
| `sat_mk_of_sat` | `Sat rho c → Sat rho (mk c.lhs (vset c) c.conc)` | proved |
| `ksplit_reuse_sat` | `Sat rho (mk p S K) → Sat rho (mk p {u} K) → Sat rho (mk u S ∅)` | proved |
| `ksplit_reuse_entails` | `SEntails G (mk u (vset c) ∅)` from `KSplitReuseApp G c u` | proved |
| `KSplitStep.reuse_models_iff` | `SModels rho (kSplitReuseResult G c u) ↔ SModels rho G` | proved |
| `ksplit_extend` | `c ∈ G → u ∉ allVars G → SModels rho G → SModels (setVar rho u ((vset c).biUnion rho)) (splitResult G c u)` | proved |
| `ksplit_mint_conservativeExt` | `KSplitApp G c u → SConservativeExt G u (splitResult G c u)` | proved |
| `KSplitStep.satisfiable_iff` | `(∃ rho, SModels rho G) ↔ (∃ rho, SModels rho G')` | proved |
| `KSplitStep.mint_of_splitApp` | `SplitApp G c u → ¬ Resolved G c.lhs c.conc → KSplitStep G (splitResult G c u)` | proved |
| `KSplitApp.reuse_of_splitApp` | `SplitApp G c u → Resolved G c.lhs c.conc → ∃ z, KSplitReuseApp G c z` | proved |

`ksplit_extend` and `ksplit_mint_conservativeExt` are `DefaultTerm.split_extend` and
`SplitNecessary.split_mint_conservativeExt` restated with the syntactic guard dropped from
the hypotheses (those proofs use only `mem` and `fresh`).  DefaultTerm/SplitNecessary were
NOT edited; the ~10-line proofs are repeated in the new module, as the brief instructs.

### §3 The keyed calculus

| name | statement | status |
|---|---|---|
| `KDefaultStep`, `KRun`, `TerminatesOnSatKeyed` | as §2.1 | proved (definitions) |
| `KDefaultStep.subset` | `G ⊆ G'` | proved |
| `KDefaultStep.satisfiable_iff` | equisatisfiability of one step | proved |
| `KSplitStep.concSub`, `KDefaultStep.concSub` | `ConcSub L G → ConcSub L G'` | proved |
| `allVars_kSplitReuseResult` | reuse adds no variable | proved |
| `KSplitStep.allVars_cases`, `KDefaultStep.allVars_cases` | keeps the vocabulary, or adds exactly one fresh variable | proved |
| `KDefaultStep.allVars_card_le` | `(allVars G').card ≤ (allVars G).card + 1` | proved |
| `KDefaultStep.new_canonical` | everything added is `mk`-shaped | proved |
| `KDefaultStep.new_forms` | `G' ⊆ G ∪ forms (allVars G') L` | proved |
| `KRun.subset`, `.card_ge`, `.satisfiable_iff`, `.concSub` | as `DefaultRun`'s | proved |
| `KRun.subset_forms` | `G ⊆ G₀ ∪ forms (allVars G) L` | proved |
| `KRun.length_le_forms` | `n ≤ (forms (allVars G) L).card` | proved |

The `nongen` and `gres` cases of `concSub` / `new_canonical` are discharged by lifting to
`DefaultStep` (`DefaultStep.nongen h`, `DefaultStep.gres h`) and applying DefaultTerm's
lemma; only the split case is new.  `forms`, `card_forms_le`, `forms_mono`, `mem_forms`,
`formsBound_mono` are DefaultTerm's, used unchanged.

### §4 The measure

| name | statement | status |
|---|---|---|
| `gmeas_le_of_allVars_eq` | `G ⊆ G' → allVars G' = allVars G → gmeas L rho G' ≤ gmeas L rho G` | proved |
| `NonGenStep.gmeas_le` | corollary for the non-generative rules | proved |
| `KSplitStep.reuse_gmeas_le` | corollary for the keyed reuse | proved |
| `ksplit_rank_lt` | `c.conc ≠ ∅ → SModels rho (splitResult G c u) → (rho u).card < (rho c.lhs).card` | proved |
| `KSplitStep.mint_gmeas_lt` | `KSplitApp G c u → ConcSub L G → SModels rho (splitResult G c u) → gmeas L rho (splitResult G c u) < gmeas L rho G` | proved |
| `KDefaultStep.extend` | the model extends, agreeing on the old vocabulary | proved |
| `KDefaultStep.measure_step` | the packaged single step: `∃ rho'`, models `G'`, agrees on `allVars G`, and `\|allVars G'\| + gmeas L rho' G' ≤ \|allVars G\| + gmeas L rho G` | proved |
| `KRun.invariant` | the same along a whole run, against `(allVars G₀, gmeas L rho₀ G₀)` | proved |
| `KRun.allVars_card_le` | `(allVars G).card ≤ (allVars G₀).card + gmeas L rho G₀` | proved |

`gmeas_le_of_allVars_eq` is the single lemma the brief suggested: it covers `NonGenStep`,
the keyed reuse and (via `GResStep.reuse_allVars_eq`) the guarded resolution reuse at once.
The `gmeas_congr` subtlety `ResGuardTerm` handles (the measure of the OLD system under the
NEW model equals the measure under the old one) is handled the same way, inside
`KDefaultStep.measure_step`'s two mint cases.

**No hole was found.**  Every rule of `KDefaultStep` was checked against the two things the
measure needs: (i) it adds no variable except at a mint (`KDefaultStep.allVars_cases`, which
routes `nongen` through `NonGenStep.allVars_eq` and both reuses through their own
`allVars` lemmas), and (ii) it cannot RAISE `unfired` at any variable, which holds for every
rule because `unfired` is antitone in the system (`unfired_le`) and every rule is additive.
Both mints strictly decrease the measure.  There is no rule in this calculus that deletes,
and deletion is the only thing that could reopen a key — see §6.

### §5 Termination

| name | statement | status |
|---|---|---|
| `KRun.length_le` | `KRun n G₀ G → SModels rho G₀ → ConcSub L G₀ → n ≤ M · 2^M · 2^\|L\|`, `M := \|allVars G₀\| + gmeas L rho G₀` | proved |
| `keyed_terminates_of_satisfiable` | `SModels rho G₀ → ∃ N, ∀ n G, KRun n G₀ G → n ≤ N` | proved |
| `terminatesOnSatKeyed` | `TerminatesOnSatKeyed` | proved |
| `keyed_vs_syntactic` | `TerminatesOnSatKeyed ∧ ¬ TerminatesOnSat` | proved |
| `KRun.of_gRun`, `kRun_one_resSeed` | the resolution mint fires in the keyed calculus (`resSeed`) | proved |
| `keyed_mint_fires` | `∃ G c u, KSplitApp G c u` — the keyed SPLIT mint branch is reachable | proved |

`keyed_mint_fires` matters: without it the theorem could hold for the uninteresting reason
that the branch is never enabled.  Witness: `G = {0 <- (1, 2, (|5|))}`, `u = 3`.

### §6 Non-vacuity on `SatDiverge.W2`

| name | statement | status |
|---|---|---|
| `SatDiverge.W2_resolved` | `Resolved W2 p K` (`W2` itself carries `p <- (e2, (\|k\|))`) | proved |
| `SatDiverge.W2_not_keyed_mint0` | `∀ u, ¬ KSplitApp W2 (mk p {e1,e2} K) u` — round 0 refused | proved |
| `SatDiverge.W2_keyed_reuse0` | `KSplitReuseApp W2 (mk p {e1,e2} K) e2` — the reuse taken instead | proved |
| `SatDiverge.W2_bare_notMem`, `SatDiverge.kRun_one_W2` | `∃ G, KRun 1 W2 G` — the bound is not vacuous on `W2` | proved |
| `SatDiverge.W2_keyed_reuse0_selfSubst` | the emitted `e2 <- (e1, e2)` is a self-partition; `SelfSubstStep` derives `e1 <- ()` | proved |
| `SatDiverge.G₂`, `SatDiverge.cur1_mem_G₂`, `SatDiverge.G₂_resolved` | the system `W2Inv.round` reaches after cancel + subst, and `Resolved G₂ p K` | proved |
| **`SatDiverge.W2_keyed_no_second_mint`** | `∀ u', ¬ KSplitApp G₂ (mk p {e1,u1} K) u'` | proved (the brief's required theorem) |
| `SatDiverge.W2_keyed_reuse` | `KSplitReuseApp G₂ (mk p {e1,u1} K) u1` — reuse, emitting `u1 <- (e1, u1)` | proved |
| `SatDiverge.W2_keyed_reuse_selfSubst` | that conclusion is a self-partition; `SelfSubstStep` derives `e1 <- ()` | proved |
| **`SatDiverge.W2_keyed_bound`** | `∃ N, ∀ n G, KRun n W2 G → n ≤ N` | proved (the brief's required theorem) |
| `split_mint_not_keyed` | `∃ G c u, SplitApp G c u ∧ ¬ KSplitApp G c u` | proved |

A finding the brief did not anticipate: the keyed guard stops the `W2` engine one round
EARLIER than expected.  `W2 = { p <- (e1, e2, (|k|)), p <- (e2, (|k|)) }` — and the second
input constraint IS a name for `p \ (|k|)`.  So the keyed guard is closed on `W2` from the
start and round 0 (`SatDiverge.split0_app`, which the syntactic guard allows) never fires;
the calculus reuses, emitting the self-partition `e2 <- (e1, e2)` from which
self-substitution derives `e1 <- ()` — the forced-empty variable the whole engine runs on,
exposed in two steps instead of being carried around inside ever-new groups.  This is the
additive analogue of what the real loop does with `makeEmpty`.  `W2_keyed_no_second_mint` is
still proved as required, on the system the engine would reach.

### Weakened / not attempted

* **`DefaultStep ⊄ KDefaultStep` is stated at the level of PREMISES, not of the step
  relations.**  `split_mint_not_keyed` exhibits `G, c, u` with `SplitApp G c u` and
  `¬ KSplitApp G c u`; it does NOT prove `¬ ∀ G G', DefaultStep G G' → KDefaultStep G G'`.
  Refuting the set-level statement needs, for one concrete pair `(G, splitResult G c u)`,
  the exclusion of every other keyed rule that could emit exactly that system — the nongen
  rules and both reuses are excluded cheaply (they do not change `allVars`, and
  `splitResult` adds a fresh variable), but excluding a coincidental guarded-resolution
  mint or a different keyed split mint with the same result is a large concrete case
  analysis on `SatDiverge.G₂`.  Judged not worth the cost; the premise-level statement is
  what the docstring claims and what the report claims.  The claim is not in doubt — it is
  the formal cost that was declined.
* Nothing else was weakened or dropped.  The full list of §1–7 items in the brief is
  discharged.

---

## 4. Verification

Toolchain: Lean 4.33.1, Mathlib v4.33.1, `LEAN_NUM_THREADS=2`, `export PATH="$HOME/.elan/bin:$PATH"`.

```
$ cd tracker/lean && LEAN_NUM_THREADS=2 lake build Rowpartition.KeyedSplit
...
✔ [799/799] Built Rowpartition.KeyedSplit (1.9s)
Build completed successfully (799 jobs).
```

No module other than `Rowpartition.KeyedSplit` was compiled (1.9 s).  The rest of the
output is the pre-existing `linter.style.header` chatter replayed from already-built
modules — including 69 lines of the form `Rowpartition/NameLoss.lean:71:0:
linter.style.header:...: error: unknown tactic`, which are emitted by the STYLE LINTER
about files this task did not touch: `lake build Rowpartition.DefaultSatDiverge` (798 jobs,
no recompilation) prints the same 69 lines and also completes successfully.  Both builds
exit 0.

Iteration was `LEAN_NUM_THREADS=2 lake env lean Rowpartition/KeyedSplit.lean`, which is
SILENT (exit 0, no warnings).

**Collision check.**  Scratch file containing exactly

```lean
import Rowpartition
import Rowpartition.KeyedSplit
```

`lake env lean` on it: silent, exit 0.  No name in the new module clashes with anything in
the existing development.

**Axioms** (`#print axioms` from a scratch file importing only `Rowpartition.KeyedSplit`,
verbatim):

```
'Rowpartition.ksplit_reuse_sat' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KSplitStep.reuse_models_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.ksplit_mint_conservativeExt' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KSplitStep.satisfiable_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KSplitStep.mint_of_splitApp' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KSplitApp.reuse_of_splitApp' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KDefaultStep.satisfiable_iff' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KDefaultStep.concSub' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KDefaultStep.allVars_cases' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KDefaultStep.new_canonical' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KRun.length_le_forms' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.gmeas_le_of_allVars_eq' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KSplitStep.mint_gmeas_lt' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KSplitStep.reuse_gmeas_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.NonGenStep.gmeas_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KDefaultStep.extend' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KDefaultStep.measure_step' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KRun.invariant' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KRun.allVars_card_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.KRun.length_le' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.keyed_terminates_of_satisfiable' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.terminatesOnSatKeyed' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.keyed_vs_syntactic' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.kRun_one_resSeed' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.keyed_mint_fires' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.W2_not_keyed_mint0' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.W2_keyed_reuse0' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.kRun_one_W2' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.W2_keyed_reuse0_selfSubst' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.W2_keyed_no_second_mint' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.W2_keyed_reuse' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.W2_keyed_reuse_selfSubst' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.SatDiverge.W2_keyed_bound' depends on axioms: [propext, Classical.choice, Quot.sound]
'Rowpartition.split_mint_not_keyed' depends on axioms: [propext, Classical.choice, Quot.sound]
```

No `sorryAx`, no new axiom.  The module contains no `sorry`, `admit`, `native_decide` or
`#print` (checked by grep).

---

## 5. Explorer check (`tracker/tools/rowclosure.py --split-key`)

**The change.**  A new `System.split_open(c)` method carries the guard; with `--split-key`
it reads `(lhs, conc) not in G.resolved` (the index the tool already maintained for
`GResStep`) instead of `vset not in G.names`.  Three call sites use it (`split_requests`,
`apply_split_mint`'s re-check, the mint-cap detector), as do `is_split_premise` and the
`chase` strategy's `hot` predicate.  `rule_split_reuse` dispatches to a new
`rule_split_reuse_keyed`, which emits `z <- (vset c)` for the existing `z` with
`c.lhs <- (z, c.conc)` present.  `--split-key` defaults OFF and `build()` takes it as a
keyword; the docstring documents it.

**Backward compatibility.**  Six default-flag runs (`builtin gseed`, `builtin crulew`,
`builtin resseed`, `builtin twodecomp --strategy chase`, `run W2.json --strategy chase`,
`run NE6.json --strategy bfs`) were diffed against the unpatched script: byte-identical
except for the `time Ns` field.

**Unsatisfiable input is untouched** (as the theorem says it must be):

```
$ tracker/tools/rowclosure.py builtin gseed --split-key --rules gres --time-limit 60
== CAP HIT: mint-cap        constraints 1204  variables 404  mints 400 (split 0, resolution 400)
$ tracker/tools/rowclosure.py builtin gseed --split-key --time-limit 60
== CAP HIT: time            constraints 4960  variables 34   mints 30 (split 0, resolution 30)
$ tracker/tools/rowclosure.py builtin crulew --split-key --time-limit 45
== CAP HIT: time            constraints 18300 variables 88   mints 76 (split 40, resolution 36)
```

**W2 / H2 / NE6, all eight strategies, `--split-key`** — every run a VERIFIED FIXPOINT:

| seed | strategy | stopped | constraints | mints (split/res) |
|---|---|---|---|---|
| W2 | bfs, mintfirst, lazy, worklist, eager, dfs, random, chase | fixpoint (verified) | 5 | **0** |
| H2 | bfs, lazy, dfs, random | fixpoint (verified) | 14 | 1 (1/0) |
| H2 | mintfirst, worklist, eager, chase | fixpoint (verified) | 26 | 2 (2/0) |
| NE6 | bfs, lazy, worklist | fixpoint (verified) | 57 | 3 (2/1) |
| NE6 | dfs | fixpoint (verified) | 75 | 4 (3/1) |
| NE6 | mintfirst, random | fixpoint (verified) | 101–168 | 5 |
| NE6 | eager, chase | fixpoint (verified) | 149 | 6 (5/1) |

The same seeds with the SHIPPED guard, for contrast:

| seed | strategy | stopped | constraints | mints |
|---|---|---|---|---|
| W2 | chase | **con-cap** | 20154 | **100** (100 split) |
| H2 | chase | **con-cap** | 20145 | **110** |
| NE6 | chase | **con-cap** | 20094 | **152** |
| NE6 | dfs | **con-cap** | 20083 | **99** |
| NE6 | eager | fixpoint | 8997 | 64 |

`builtin twodecomp` (the explorer's own satisfiable diverger — `a <- (e, y, (|1|))`,
`a <- (e, (|1|))`, which hits the constraint cap at 100 split mints under `--strategy chase`
with the shipped guard) reaches a **verified fixpoint with 0 mints and 5 constraints under
every one of bfs / chase / dfs / eager** with `--split-key`.  `builtin resseed`: fixpoint, 1
resolution mint.

**Random search, 2000 satisfiable seeds (`--rng 1`, k = 3..7 vars, m = 2..4 labels,
n = 2..6 constraints), strategies bfs and chase:**

```
$ tracker/tools/rowclosure.py search --seeds 2000 --rng 1 --jobs 3 --split-key \
      --strategies bfs,chase --time-per-seed 20
== search/bfs:   2000 seeds; fixpoint 2000 (unverified 0), mint-cap 0, con-cap 0, time-limit 0
   mints: max 3   p99 2   p90 0   median 0
== search/chase: 2000 seeds; fixpoint 1999 (unverified 0), mint-cap 0, con-cap 1, time-limit 0
   mints: max 11  p99 3   p90 1   median 0
```

versus the same 2000 seeds with the shipped guard:

```
$ tracker/tools/rowclosure.py search --seeds 2000 --rng 1 --jobs 3 --strategies bfs,chase
== search/bfs:   2000 seeds; fixpoint 1960, mint-cap 0,   con-cap 0,   time-limit 40
   mints: max 9    p99 7    p90 1    median 0
== search/chase: 2000 seeds; fixpoint 1636, mint-cap 183, con-cap 181, time-limit 0
   mints: max 400 (= the cap)  p99 400  p90 308  median 0
```

**Max mints with `--split-key`: 3 (bfs) and 11 (chase).  Mint-cap hits: ZERO of 2000 under
both strategies** — the number the theorem predicts must be zero, against 183 of 2000 under
`chase` with the shipped guard.

**The one cap hit, investigated.**  Seed `r1030-k7m2n6` (6 constraints, 7 variables,
2 labels) hit the CONSTRAINT cap under `chase`, not the mint cap.  Re-run at mint caps
100 / 400 / 2000 the mint count is **11 at every cap** and the vocabulary is 18 variables at
every cap; re-run at `--con-cap 200000 --mint-cap 4000 --time-limit 200` it reaches 24 068
constraints with **still 11 mints and still 18 variables**, and stops on the clock.  So the
vocabulary has closed and what is growing is the (finite) closure over it — a big-closure
signal, not a termination one, exactly as the tool's docstring says the constraint cap
means.  The theorem bounds the run at `M·2^M·2^|L|` and with `|allVars| = 18`, `|L| = 2`
that bound is ~10^7, so nothing here is in tension with it.  No mint-cap hit occurred
anywhere under `--split-key`.

**A free extra check of `ksplit_reuse_sat`.**  The explorer model-checks every emitted
constraint against the (extended) assignment and aborts on a violation.  4000 keyed closures
plus all the seed runs emitted the new keyed-reuse conclusion `z <- (vset c)` many thousands
of times with **zero** `ModelViolation`s and zero unverified fixpoints — an independent
numerical check of the soundness lemma.

---

## 6. What this buys, and what it does not

**Buys.**  A termination theorem for the ADDITIVE relation, hence for EVERY loop order,
from every satisfiable input — the same quantifier under which `not_TerminatesOnSat` is a
real refutation.  That is stronger than the three defences the shipped loop actually relies
on (name travel, eager unification of singleton links, eager `makeEmpty`), each of which is
a property of an ORDER and none of which is stated by any relation in the development.  It
also collapses `DefaultTerm` §9's asymmetry: with the keyed guard, split branching per
parent is bounded by `2^|L|` for the same reason resolution branching already was
(`CountRun.res_branching_le`), because the two mints share one budget.

**Does not buy.**

* **Ill-typed (unsatisfiable) input.**  `KDefaultStep` still contains guarded resolution,
  and guarded resolution diverges on the unsatisfiable `ResGuardDiverge.gSeed`
  (`gSeed_diverges`).  The measure is defined against a model; with none there is no rank to
  descend.  The dichotomy of `ResGuardTerm`'s Summary is unchanged, and the explorer
  confirms it (`builtin gseed --split-key`, `builtin crulew --split-key` still hit caps).
  Ermine's protection there is the per-label check (`LabelProp`, `gSeed_refuted`), untouched.
* **The shipped guard.**  `DefaultStep` and `KDefaultStep` are INCOMPARABLE, not nested.
  Every syntactically-guarded mint that also passes the keyed guard is a keyed mint
  (`KSplitStep.mint_of_splitApp`); where it does not, the keyed calculus reuses instead
  (`KSplitApp.reuse_of_splitApp`), and `split_mint_not_keyed` exhibits that concretely at
  `SatDiverge.G₂`.  So `not_TerminatesOnSat` stands unchanged for the calculus as
  implemented; this file says what changing the guard would buy.  (The set-level
  non-inclusion of the step RELATIONS is not formalised — see §3, "Weakened".)
* **The real `incorporateAll` loop.**  It deletes and renames (`Saturate.SatStep`:
  `makeEmpty`, `makeConcrete`, `rename`/`unify`, `dedup`, `weaken`) and is not a
  sub-relation of any additive relation here.  Deleting a guard's witness can re-enable a
  mint (`NameLoss.orderB_remint_enabled`) — and for the KEYED guard the witness that
  deletion would remove is `p <- (z, K)`, which is exactly what `makeConcrete` /
  `destructiveSub` absorb.  Whether the keyed guard survives the loop layer is a separate
  question and is NOT answered here.
* **Implementation — DONE (Stage 2, 2026-09-03, `KEYED-SPLIT-STAGE2.md`).**
  `-Dermine.splitKey`, default OFF.  `splitConcrete` still calls `findRHS(RHSAbstr(abstr))`
  first (the syntactic reuse is a `NonGenStep`, kept verbatim); with the flag on it then asks
  `learnPartitions`' resolvent lookup for a partition of `a` with concrete part exactly `C+`
  and a single abstract variable `u`, and on a hit emits `u <- x++` (tagged `SplitKeyed`)
  rather than minting.  Measured: corpus verdicts and `shouldfail/` unchanged, 0 weaker
  published types, `gu05` 5x faster, 77 firings on 18 of 110 example modules, `np01` mints
  MORE — the delta `split_mint_not_keyed` predicts, on real code.  ADOPTED as the default
  2026-09-03; `-Dermine.splitKey=false` restores the syntactic guard.
* **Conjecture S** (every substitution-closed run from a satisfiable input is bounded, for
  the SHIPPED guard) is untouched: this file changes the guard rather than restricting the
  runs, and says nothing about saturating runs of `DefaultStep`.

## 7. Files

| file | what |
|---|---|
| `tracker/lean/Rowpartition/KeyedSplit.lean` | the module (new; not in the root `Rowpartition.lean`) |
| `tracker/tools/rowclosure.py` | `--split-key` (new flag, default off; `split_open`, `rule_split_reuse_keyed`) |
| `tracker/satterm/KEYED-SPLIT.md` | this report |
