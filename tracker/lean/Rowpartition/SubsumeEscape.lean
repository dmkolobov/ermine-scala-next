/-
# SubsumeEscape -- `Subst.scala:648`'s escaping-skolem check, modelled as a function

Stage S1a of the `subsume-termination` programme
(`tracker/PROMPT-subsume-termination.md`, `tracker/satterm/briefs/brief-S1a.md`).

`Subst.subsumeType` (`Subst.scala:613-659`) finishes with

```scala
val skss = sks.toSet                              // the SKOLEM KIND vars unbind minted
val stss = sts.toSet                              // the SKOLEM TYPE vars unbind minted
val escs = hm.fskvs.filter(v => stss.contains(v)) ++ hm.kindVars.filter(skss(_))
if (escs nonEmpty) tml.die(...)                   // :649
```

with (`Subst.scala:168-169`)

```scala
def fskvs:    Traversable[TypeVar] = Type.fskvs(types)
def kindVars: Traversable[KindVar] = Kind.kindVars(kinds) ++ Kind.kindVars(types)
```

and this file models exactly those three walks -- `Type.typeHasKindVars.vars`
(`Type.scala:648-661`), `Type.typeHasTypeVars.vars` (`Type.scala:706-715`),
`Kind.kindHasKindVars` / `Kind.vars` (`Kind.scala:16, 59, 65`),
`KindSchema.kindSchemaHasKindVars` (`KindSchema.scala:25-27`), the `Map`/`List`/`V`
instances (`Kind.scala:119-136`) and the `Vars` combinators themselves
(`Vars.scala:13-46`) -- together with their COST.

## THE FIRST QUESTION THE BRIEF ASKS: does the walk follow any binding?

**No.**  `Type.scala:653` is `case VarT(v) => v.extract.vars`, and `v : V[Kind]`, so
`v.extract` is the type variable's KIND ANNOTATION (`Vars.scala:98`, the `extract` field of
`V`); `Kind.scala:65` is `case VarK(v) => Vars(v)`, which emits the kind variable and stops.
Neither `hm.types` nor `hm.kinds` is ever consulted.  The walk is a STRUCTURAL recursion over
the terms the environment already holds.

Three consequences, all of them proved below.

* **H2 of the prompt ("cyclic substitution: `VarT(v) => v.extract.vars` follows a variable's
  binding, and a variable bound to a type that mentions it makes `vars` non-terminating") is
  FALSE as a reading of the code.**  `escs_total_on_cyclic` computes the check on an
  environment whose single binding is `a |-> a a`, which no occurs check would admit, and it
  returns.  What H2 describes is a DIFFERENT function, `kvarsFollow` below, and that one does
  diverge on the same input (`follow_diverges`) -- so the hypothesis is coherent, it just is
  not this code.
* **The "acyclic bindings" invariant the brief asks to be stated precisely is VACUOUS for
  termination.**  Not one theorem in this file has an acyclicity hypothesis.  The invariants
  that DO carry weight are about IDENTITY, not about cycles, and they are named
  `SkolemCoherent` and `Untouched` in §7.
* **The interesting content is therefore the COST**, which is §5 and §6, and the EQUIVALENCE
  of a cheaper check, which is §7.

## What is proved

* §2 `Vars.scala` itself.  `runV` is `Vars.apply(s, f)` -- the seen-set/callback protocol,
  including `++`'s `w(that(s,f), f)` and `--`'s
  `(that(s ++ t, f) -- t) ++ (t.map(...) intersect s)`.  `runV_seen` and `runV_emitted_id`
  say what it computes: the seen set out is the seen set in plus the free variables, and the
  emitted ids are exactly the free ids not already seen.  `many_can_duplicate` is a
  refutation of the class docstring's "designed to avoid duplicates": the `Vars(vs: Iterable)`
  constructor does not update its seen set inside its own loop.
* §5 Cost.  `costV` counts `apply` invocations, `subPass` counts the nodes ONE substitution
  pass (`Type.subst`, the traversal `instantiateType` runs over the whole of `hm.types`,
  `Subst.scala:254`) visits.  `kvars_cost_le` / `tvars_cost_le` / `escs_cost_le_subPass`: the
  whole escape check costs at most a small constant times ONE substitution pass over the same
  environment.  That is the stage's central quantitative fact, and it is what tells S2 that
  making `:648` cheaper cannot by itself fix a hang.  **These are bounds on NODE VISITS, not on
  time** (S1a review, Finding 2): `costV` charges one step per `VarsE` node, while in the JVM a
  `minus` node runs immutable-`Set` operations over a seen set that grows with the number of
  distinct variables, and `Vars.filter`/`nonEmpty` materialise a `Vector` per half through
  `ForeachIterable.iterator`, against a singleton-map lookup per node in `Type.subst`.
* §6 Sharing.  The walk unfolds a DAG as a TREE, so its cost is exponential in the size of a
  shared representation (`walk_exp_in_dag`: DAG size `4n+1`, walk cost `2^(n+1) - 1`).  And
  the matching NEGATIVE result, `subst_pays_the_same`: the substitution pass unfolds the same
  DAG the same way, so an environment on which the walk is exponential cannot be REACHED
  cheaply through `instantiateType`.
* §7 The cheap check.  `verdictR` tests each skolem for occurrence instead of collecting every
  variable and filtering; `verdict_eq` proves the two agree, so nothing observable changes AT
  `:648`.  `escs_restrict_untouched` is the stronger licence: entries that cannot mention a
  skolem may be skipped entirely -- but see the §7 header, `Untouched` is about CONTENT and not
  about age.

**Where the verdict-only argument does NOT apply** (S1a review, Finding 4).  `escs`'s elements
are dead at `:648`, but `checkSkolemEscape` (`Subst.scala:361-367`) runs the SAME `Type.fskvs`
walk -- `val hescs = fskvs(hm.types -- mask).filter(ss(_))` at `:365`, over a freshly allocated
`hm.types -- mask` -- and at `:367` it PRINTS `hescs.mkString(", ")`.  There the elements are
LIVE, so `verdict_eq` and `skolem_filter_redundant` do not license a transformation of `:365`.
S0 measures `:365` at 3.9 s against `:648`'s 2.2 s in the 12-property suite, so it is the site
S2 will be most tempted to change and the one this file does not cover.

## Contents

* §1  Syntax: kinds, kind schemas, type variables, types, the substitution environment.
* §2  `Vars.scala`: `VarsE`, `runV`, `fvE`/`fvId`/`occE`, and what they compute.
* §3  The three walks and `escs`/`verdict`, transcribed.
* §4  H2: the binding-following reading, its divergence, and the code's totality.
* §5  Cost: `costV`, `subPass`, and the walk against one substitution pass.
* §6  Sharing: a DAG whose walk is exponential, and why it is not reachable.
* §7  The restricted check and its equivalence; the untouched-entry licence.
-/
import Rowpartition.Basic

namespace Rowpartition
namespace SubsumeEscape

/-! ## 1. Syntax

`Vars.scala:99-112`: a variable `V[A]` is an `id : Int`, a `VarType` and an `extract : A`,
and `equals`/`hashCode` use the ID ALONE.  Every set and every `contains` below is therefore
a set of ids, and that is modelled directly. -/

/-- `Vars.scala:76-86`, `VarType`.  `Ambiguous` wraps another and is folded into `free` here;
nothing on this path inspects it. -/
inductive VTy where
  | free | skolem | bound | unspecified
  deriving DecidableEq, Repr

/-- A kind variable, `V[Unit]`. -/
structure KVar where
  id : Nat
  ty : VTy
  deriving DecidableEq, Repr

/-- `Kind.scala:20-67`.  `Rho`/`Star`/`Field`/`Constraint` are nullary and are tagged by a
`Nat`; `ArrowK` and `VarK` are the two that `vars` recurses through. -/
inductive Knd where
  | base : Nat → Knd
  | arrowK : Knd → Knd → Knd
  | varK : KVar → Knd
  deriving DecidableEq, Repr

/-- `KindSchema.scala:7`. -/
structure KSchema where
  forallK : List KVar
  body : Knd
  deriving DecidableEq, Repr

/-- A type variable, `V[Kind]`: `kind` is the `extract` that `Type.scala:653` reads. -/
structure TVar where
  id : Nat
  ty : VTy
  kind : Knd
  deriving DecidableEq, Repr

mutual

/-- `Type.scala`.  Exactly the constructors the two `vars` functions dispatch on:
`Arrow`, `AppT`, `Con`, `VarT`, `Forall`, `Exists`, `Part`, `Memory`, and one `opaqueT`
standing for every constructor both walks send to `Vars()` (`ConcreteRho`, `ProductT`, ...). -/
inductive Ty where
  | arrowT : Ty
  | app : Ty → Ty → Ty
  | con : KSchema → Ty
  | var : TVar → Ty
  /-- `Forall(loc, vs, ts, q, b)`; `q` is the constraint `vars` DELIBERATELY excludes. -/
  | allT : List KVar → List TVar → Ty → Ty → Ty
  /-- `Exists(loc, xs, q)`, `q` a LIST of constraints. -/
  | exT : List TVar → TyList → Ty
  /-- `Part(loc, v, c)`, `c` a LIST. -/
  | part : Ty → TyList → Ty
  | mem : Ty → Ty
  | opaqueT : Ty

/-- Scala's `List[Type]`, as an inductive so that the walks are structurally recursive. -/
inductive TyList where
  | tnil : TyList
  | tcons : Ty → TyList → TyList

end

/-- `SubstEnv` (`Subst.scala:88-170`) restricted to the two fields `:648` reads. -/
structure Env where
  types : List (TVar × Ty)
  kinds : List (KVar × Knd)

/-! ## 2. `Vars.scala` as a function

`Vars[K]` is not a collection: it is the church-encoded traversal
`apply(s : Set[V], f : V => Unit) : Set[V]`, with three combinators.  `++` is
`w(that(s,f), f)` (`Vars.scala:22-24`) and both arguments are BY VALUE, so building a
`Vars` is already a full structural walk; `--` is `Vars.scala:28-32`. -/

/-- The five shapes a `Vars` value can have.  `minus`'s list is a list of IDS because
`Vars.--` does `w.toSet` and `V.equals` is id equality. -/
inductive VarsE (α : Type) where
  | nil : VarsE α
  | one : α → VarsE α
  | many : List α → VarsE α
  | app : VarsE α → VarsE α → VarsE α
  | minus : VarsE α → List Nat → VarsE α

variable {α : Type}

/-- Decidable membership of an id in a seen set, as a `Bool`. -/
def memN (n : Nat) (s : List Nat) : Bool := decide (n ∈ s)

@[simp] theorem memN_iff (n : Nat) (s : List Nat) : memN n s = true ↔ n ∈ s := by
  simp [memN]

@[simp] theorem memN_false (n : Nat) (s : List Nat) : memN n s = false ↔ n ∉ s := by
  simp [memN]

/-- `Vars.apply(s, f)`, with the callback replaced by the list of what it was called with.
Returns `(emitted, seen-out)`. -/
def runV (idOf : α → Nat) : VarsE α → List Nat → List α × List Nat
  | .nil, s => ([], s)
  | .one a, s => if memN (idOf a) s then ([], s) else ([a], idOf a :: s)
  | .many as, s => (as.filter (fun a => !memN (idOf a) s), s ++ as.map idOf)
  | .app x y, s =>
      let r1 := runV idOf x s
      let r2 := runV idOf y r1.2
      (r1.1 ++ r2.1, r2.2)
  | .minus x t, s =>
      let r := runV idOf x (s ++ t)
      (r.1, (r.2.filter (fun n => !memN n t)) ++ t.filter (fun n => memN n s))

/-- The free variables of a `Vars` expression, the naive way. -/
def fvE (idOf : α → Nat) : VarsE α → List α
  | .nil => []
  | .one a => [a]
  | .many as => as
  | .app x y => fvE idOf x ++ fvE idOf y
  | .minus x t => (fvE idOf x).filter (fun a => !memN (idOf a) t)

/-- Their ids -- what every filter at `Subst.scala:648` actually tests. -/
def fvId (idOf : α → Nat) (e : VarsE α) : List Nat := (fvE idOf e).map idOf

/-- Every variable OCCURRING in the expression, `--`-bound ones included. -/
def occE : VarsE α → List α
  | .nil => []
  | .one a => [a]
  | .many as => as
  | .app x y => occE x ++ occE y
  | .minus x _ => occE x

theorem mem_map_filter {β : Type} (f : α → β) (p : α → Bool) (l : List α) (b : β) :
    b ∈ (l.filter p).map f ↔ ∃ a, a ∈ l ∧ p a = true ∧ f a = b := by
  simp only [List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨a, ⟨ha, hp⟩, hb⟩; exact ⟨a, ha, hp, hb⟩
  · rintro ⟨a, ha, hp, hb⟩; exact ⟨a, ⟨ha, hp⟩, hb⟩

@[simp] theorem fvId_nil (idOf : α → Nat) : fvId idOf (.nil : VarsE α) = [] := rfl

@[simp] theorem fvId_one (idOf : α → Nat) (a : α) : fvId idOf (.one a) = [idOf a] := rfl

@[simp] theorem fvId_many (idOf : α → Nat) (as : List α) :
    fvId idOf (.many as) = as.map idOf := rfl

@[simp] theorem fvId_app (idOf : α → Nat) (x y : VarsE α) :
    fvId idOf (.app x y) = fvId idOf x ++ fvId idOf y := by
  simp [fvId, fvE]

theorem mem_fvId_minus (idOf : α → Nat) (x : VarsE α) (t : List Nat) (n : Nat) :
    n ∈ fvId idOf (.minus x t) ↔ n ∈ fvId idOf x ∧ n ∉ t := by
  simp only [fvId, fvE]
  rw [mem_map_filter]
  constructor
  · rintro ⟨a, ha, hp, rfl⟩
    refine ⟨List.mem_map_of_mem ha, ?_⟩
    simpa using hp
  · rintro ⟨hn, hnt⟩
    obtain ⟨a, ha, rfl⟩ := List.mem_map.1 hn
    exact ⟨a, ha, by simpa using hnt, rfl⟩

/-- `occE` covers `fvE`: `--` only ever REMOVES. -/
theorem fvE_subset_occE (idOf : α → Nat) :
    ∀ (e : VarsE α) (a : α), a ∈ fvE idOf e → a ∈ occE e := by
  intro e
  induction e with
  | nil => intro a h; exact h
  | one b => intro a h; exact h
  | many as => intro a h; exact h
  | app x y ihx ihy =>
      intro a h
      rcases List.mem_append.1 h with h | h
      · exact List.mem_append.2 (Or.inl (ihx a h))
      · exact List.mem_append.2 (Or.inr (ihy a h))
  | minus x t ih =>
      intro a h
      exact ih a (List.mem_filter.1 h).1

/-- **What the seen set out is.**  `Vars.apply` returns exactly the seen set it was given,
enlarged by the expression's free variables -- for `++` by construction, and for `--` because
`(s \ t) ∪ (t ∩ s) = s` is what its last line recovers. -/
theorem runV_seen (idOf : α → Nat) :
    ∀ (e : VarsE α) (s : List Nat) (n : Nat),
      n ∈ (runV idOf e s).2 ↔ n ∈ s ∨ n ∈ fvId idOf e := by
  intro e
  induction e with
  | nil => intro s n; simp [runV]
  | one a =>
      intro s n
      by_cases h : idOf a ∈ s
      · simp [runV, memN, h]
        rintro rfl; exact h
      · simp [runV, memN, h]
        exact Or.comm
  | many as =>
      intro s n
      simp [runV]
  | app x y ihx ihy =>
      intro s n
      simp only [runV, fvId_app, List.mem_append]
      rw [ihy, ihx]
      tauto
  | minus x t ih =>
      intro s n
      simp only [runV, List.mem_append, List.mem_filter, mem_fvId_minus]
      rw [ih]
      by_cases hnt : n ∈ t <;> by_cases hns : n ∈ s <;>
        simp [hnt, hns, memN]

/-- **What is emitted, at the level of ids.**  Exactly the free ids that were not already in
the seen set.  Unconditional: no hypothesis about the environment, about acyclicity, or about
id uniqueness. -/
theorem runV_emitted_id (idOf : α → Nat) :
    ∀ (e : VarsE α) (s : List Nat) (n : Nat),
      n ∈ (runV idOf e s).1.map idOf ↔ n ∈ fvId idOf e ∧ n ∉ s := by
  intro e
  induction e with
  | nil => intro s n; simp [runV]
  | one a =>
      intro s n
      by_cases h : idOf a ∈ s
      · simp [runV, memN, h]
        rintro rfl; exact h
      · simp [runV, memN, h]
        rintro rfl; exact h
  | many as =>
      intro s n
      simp only [runV, fvId_many]
      rw [mem_map_filter]
      constructor
      · rintro ⟨a, ha, hp, rfl⟩
        exact ⟨List.mem_map_of_mem ha, by simpa using hp⟩
      · rintro ⟨hn, hns⟩
        obtain ⟨a, ha, rfl⟩ := List.mem_map.1 hn
        exact ⟨a, ha, by simpa using hns, rfl⟩
  | app x y ihx ihy =>
      intro s n
      simp only [runV, List.map_append, List.mem_append, fvId_app]
      rw [ihx, ihy, runV_seen idOf x s n]
      tauto
  | minus x t ih =>
      intro s n
      simp only [runV, mem_fvId_minus]
      rw [ih]
      simp only [List.mem_append]
      tauto

/-- Emission is a subset of the free variables, as ELEMENTS -- the direction that needs no
uniqueness hypothesis. -/
theorem runV_emitted_subset (idOf : α → Nat) :
    ∀ (e : VarsE α) (s : List Nat) (a : α), a ∈ (runV idOf e s).1 → a ∈ fvE idOf e := by
  intro e
  induction e with
  | nil => intro s a h; simp [runV] at h
  | one b =>
      intro s a h
      by_cases hb : memN (idOf b) s <;> simp [runV, hb] at h
      simp [fvE, h]
  | many as =>
      intro s a h
      have h' : a ∈ as.filter (fun b => !memN (idOf b) s) := by simpa [runV] using h
      simpa [fvE] using (List.mem_filter.1 h').1
  | app x y ihx ihy =>
      intro s a h
      simp only [runV, List.mem_append] at h
      rcases h with h | h
      · exact List.mem_append.2 (Or.inl (ihx s a h))
      · exact List.mem_append.2 (Or.inr (ihy _ a h))
  | minus x t ih =>
      intro s a h
      have hx : a ∈ fvE idOf x := ih _ a (by simpa [runV] using h)
      have hid : idOf a ∉ t := by
        have := runV_emitted_id idOf x (s ++ t) (idOf a)
        have hmem : idOf a ∈ (runV idOf x (s ++ t)).1.map idOf :=
          List.mem_map_of_mem (by simpa [runV] using h)
        have := (this.1 hmem).2
        simp only [List.mem_append, not_or] at this
        exact this.2
      simp only [fvE, List.mem_filter]
      exact ⟨hx, by simpa using hid⟩

/-- **A refutation of `Vars`'s own docstring.**  "It is designed to avoid duplicates" --
`Vars.scala:13`.  The `Vars(vs: Iterable)` constructor (`Vars.scala:60-65`) tests each element
against the seen set it was ENTERED with and never updates it inside its own loop, so a
repeated element is emitted twice.  (Not a defect on this path: `Kind.vars` and
`Type.vars` only ever build `Vars(v)` singletons.) -/
theorem many_can_duplicate :
    (runV (fun n : Nat => n) (.many [7, 7]) []).1 = [7, 7] := by
  decide

/-! ## 3. The three walks, transcribed

`Kind.scala:16` (`def vars = Vars()`), `:59` (`ArrowK`: `i.vars ++ o.vars`), `:65`
(`VarK(v)`: `Vars(v)`). -/

def kvarsK : Knd → VarsE KVar
  | .base _ => .nil
  | .arrowK i o => .app (kvarsK i) (kvarsK o)
  | .varK v => .one v

/-- `KindSchema.scala:26`: `kindVars(ks.body) -- ks.forall`. -/
def kvarsKS (ks : KSchema) : VarsE KVar :=
  .minus (kvarsK ks.body) (ks.forallK.map KVar.id)

/-- `Kind.scala:128-131` (`listHasKindVars`) composed with `:133-136` (`vHasKindVars`,
`A.vars(v.extract)`): the kinds of a list of type variables, right-folded. -/
def kvarsTVars : List TVar → VarsE KVar
  | [] => .nil
  | v :: r => .app (kvarsK v.kind) (kvarsTVars r)

mutual

/-- `Type.scala:648-661`, `typeHasKindVars.vars`, case for case.  `Forall`'s `q` is absent
because the Scala excludes it ("deliberately excludes q", `:654`). -/
def kvarsT : Ty → VarsE KVar
  | .arrowT => .nil
  | .app a b => .app (kvarsT a) (kvarsT b)
  | .con ks => kvarsKS ks
  | .var v => kvarsK v.kind
  | .allT vs ts _q b => .minus (.app (kvarsTVars ts) (kvarsT b)) (vs.map KVar.id)
  | .exT xs q => .app (kvarsTVars xs) (kvarsTL q)
  | .part v c => .app (kvarsT v) (kvarsTL c)
  | .mem b => kvarsT b
  | .opaqueT => .nil

def kvarsTL : TyList → VarsE KVar
  | .tnil => .nil
  | .tcons t r => .app (kvarsT t) (kvarsTL r)

end

mutual

/-- `Type.scala:706-715`, `typeHasTypeVars.vars` -- the walk behind `Type.fskvs`. -/
def tvarsT : Ty → VarsE TVar
  | .arrowT => .nil
  | .app a b => .app (tvarsT a) (tvarsT b)
  | .con _ => .nil
  | .var v => .one v
  | .allT _ks ts _q b => .minus (tvarsT b) (ts.map TVar.id)
  | .exT xs q => .minus (tvarsTL q) (xs.map TVar.id)
  | .part t ts => .app (tvarsT t) (tvarsTL ts)
  | .mem b => tvarsT b
  | .opaqueT => .nil

def tvarsTL : TyList → VarsE TVar
  | .tnil => .nil
  | .tcons t r => .app (tvarsT t) (tvarsTL r)

end

/-- `Kind.scala:124-126`, `mapHasKindVars`: `xs.foldRight(Vars())((x,ys) => A.vars(x._2) ++ ys)`
-- over the map's VALUES, the keys are never walked. -/
def kvarsKinds : List (KVar × Knd) → VarsE KVar
  | [] => .nil
  | p :: r => .app (kvarsK p.2) (kvarsKinds r)

def kvarsTypes : List (TVar × Ty) → VarsE KVar
  | [] => .nil
  | p :: r => .app (kvarsT p.2) (kvarsTypes r)

def tvarsTypes : List (TVar × Ty) → VarsE TVar
  | [] => .nil
  | p :: r => .app (tvarsT p.2) (tvarsTypes r)

/-- `SubstEnv.kindVars` (`Subst.scala:169`). -/
def envKindVars (Γ : Env) : VarsE KVar := .app (kvarsKinds Γ.kinds) (kvarsTypes Γ.types)

/-- The walk behind `SubstEnv.fskvs` (`Subst.scala:168`), BEFORE the `Skolem` filter. -/
def envTypeVars (Γ : Env) : VarsE TVar := tvarsTypes Γ.types

/-- `SubstEnv.fskvs`: `Type.fskvs(types)` = `A.vars(types).filter(_.ty == Skolem)`
(`Type.scala:666`). -/
def fskvs (Γ : Env) : List TVar :=
  (runV TVar.id (envTypeVars Γ) []).1.filter (fun v => v.ty == VTy.skolem)

/-- `Subst.scala:648`.  The two halves are `Traversable`s of different element types joined by
`++`, and the joined value is observed ONLY through `nonEmpty` at `:649` -- the error message
at `:650-656` prints `e1`/`e2`, and the one line that did print `escs` is commented out at
`:657`.  The elements are therefore dead, and the model keeps only their ids. -/
def escs (Γ : Env) (sks : List KVar) (sts : List TVar) : List Nat :=
  ((fskvs Γ).filter (fun v => memN v.id (sts.map TVar.id))).map TVar.id ++
    ((runV KVar.id (envKindVars Γ) []).1.filter
      (fun u => memN u.id (sks.map KVar.id))).map KVar.id

/-- `if (escs nonEmpty)` -- the ONLY thing `subsumeType` observes about `escs`. -/
def verdict (Γ : Env) (sks : List KVar) (sts : List TVar) : Bool := !(escs Γ sks sts).isEmpty

/-! ## 4. H2: the binding-following reading, and why the code is not it -/

/-- `hm.types.get(v)` by id (`Subst.scala:199`). -/
def lookupTy (Γ : Env) (n : Nat) : Option Ty :=
  (Γ.types.find? (fun p => p.1.id == n)).map Prod.snd

/-- **H2's function.**  What `Type.scala:653` would be if `VarT(v) => v.extract.vars` followed
`v`'s BINDING rather than its kind annotation.  Given a fuel, so that it is a total function
in Lean at all; `none` means the fuel ran out, i.e. the real thing would not have returned. -/
def kvarsFollow (Γ : Env) : Nat → Ty → Option (VarsE KVar)
  | 0, _ => none
  | f + 1, .var v =>
      match lookupTy Γ v.id with
      | some t => kvarsFollow Γ f t
      | none => some (kvarsK v.kind)
  | f + 1, .app a b =>
      match kvarsFollow Γ f a, kvarsFollow Γ f b with
      | some x, some y => some (.app x y)
      | _, _ => none
  | _ + 1, t => some (kvarsT t)

/-- A skolem type variable `a`, and the environment that binds it to `a a` -- an environment
`occursFail` (`Subst.scala:228-229`) exists to prevent. -/
def aVar : TVar := ⟨1, VTy.skolem, Knd.base 0⟩

def cyclicEnv : Env := ⟨[(aVar, Ty.app (Ty.var aVar) (Ty.var aVar))], []⟩

/-- **H2's reading diverges on it**: no amount of fuel suffices. -/
theorem follow_diverges :
    ∀ f : Nat, kvarsFollow cyclicEnv f (Ty.var aVar) = none ∧
      kvarsFollow cyclicEnv f (Ty.app (Ty.var aVar) (Ty.var aVar)) = none := by
  intro f
  induction f with
  | zero => exact ⟨rfl, rfl⟩
  | succ f ih =>
      refine ⟨?_, ?_⟩
      · show (match lookupTy cyclicEnv aVar.id with
              | some t => kvarsFollow cyclicEnv f t
              | none => some (kvarsK aVar.kind)) = none
        have hl : lookupTy cyclicEnv aVar.id
            = some (Ty.app (Ty.var aVar) (Ty.var aVar)) := rfl
        rw [hl]
        exact ih.2
      · show (match kvarsFollow cyclicEnv f (Ty.var aVar),
                    kvarsFollow cyclicEnv f (Ty.var aVar) with
              | some x, some y => some (VarsE.app x y)
              | _, _ => none) = none
        rw [ih.1]

/-- **The code's reading returns on it.**  `escs` on the same cyclic environment is a value:
`a` itself escapes, and the check says so.  No occurs-check, acyclicity or well-formedness
hypothesis is used -- because none is available to use. -/
theorem escs_total_on_cyclic : escs cyclicEnv [] [aVar] = [1] := by
  decide

theorem verdict_total_on_cyclic : verdict cyclicEnv [] [aVar] = true := by
  decide

/-- And on the same environment with the skolem NOT among the signature's, the check is
empty -- so the cyclic binding is not what decides the verdict either. -/
theorem escs_cyclic_other : escs cyclicEnv [] [] = [] := by
  decide

/-! ## 5. Cost: the escape walk against one substitution pass

`Vars.++` and `Vars.--` take their arguments BY VALUE (`Vars.scala:22`, `:28`), so
`typeHasKindVars.vars(t)` is already a full structural walk at CONSTRUCTION time, and running
the result walks the same shape again.  `costV` counts the `apply` invocations of one run --
one per node of the `VarsE` tree, which is one per node of the term.

`subPass` counts the nodes ONE substitution pass visits: `AppT.subst` (`Type.scala:227-230`)
recurses into both children unconditionally, `VarT.subst` (`:241-250`) walks the variable's
kind through `subKind`, `Con.subst` (`:566`) walks the schema, and `Forall`/`Exists`/`Part`
walk their constraint lists.  That pass is what `instantiateType` runs over the WHOLE of
`hm.types` on every single unification binding (`Subst.scala:254`,
`hm.types = subType(Map(v -> e), hm.types) + (v -> e)`). -/

def costV : VarsE α → Nat
  | .nil => 1
  | .one _ => 1
  | .many _ => 1
  | .app x y => 1 + costV x + costV y
  | .minus x _ => 1 + costV x

/-- `Vars.apply` again, with a tick on every invocation -- the cost model, MEASURED rather
than asserted. -/
def runVC (idOf : α → Nat) : VarsE α → List Nat → (List α × List Nat) × Nat
  | .nil, s => (([], s), 1)
  | .one a, s => ((if memN (idOf a) s then ([], s) else ([a], idOf a :: s)), 1)
  | .many as, s => ((as.filter (fun a => !memN (idOf a) s), s ++ as.map idOf), 1)
  | .app x y, s =>
      let r1 := runVC idOf x s
      let r2 := runVC idOf y r1.1.2
      ((r1.1.1 ++ r2.1.1, r2.1.2), 1 + r1.2 + r2.2)
  | .minus x t, s =>
      let r := runVC idOf x (s ++ t)
      ((r.1.1, (r.1.2.filter (fun n => !memN n t)) ++ t.filter (fun n => memN n s)), 1 + r.2)

theorem runVC_val (idOf : α → Nat) :
    ∀ (e : VarsE α) (s : List Nat), (runVC idOf e s).1 = runV idOf e s := by
  intro e
  induction e with
  | nil => intro s; rfl
  | one a => intro s; rfl
  | many as => intro s; rfl
  | app x y ihx ihy => intro s; simp only [runVC, runV, ihx, ihy]
  | minus x t ih => intro s; simp only [runVC, runV, ih]

theorem runVC_steps (idOf : α → Nat) :
    ∀ (e : VarsE α) (s : List Nat), (runVC idOf e s).2 = costV e := by
  intro e
  induction e with
  | nil => intro s; rfl
  | one a => intro s; rfl
  | many as => intro s; rfl
  | app x y ihx ihy => intro s; simp only [runVC, costV, ihx, ihy]
  | minus x t ih => intro s; simp only [runVC, costV, ih]

/-- **Termination, as a count.**  One run of `Vars.apply` makes exactly `costV e`
invocations -- a number fixed by the EXPRESSION alone, hence by the terms the environment
stores and never by what those terms' variables are BOUND to.  That is the precise sense in
which the "acyclic substitution" invariant the brief asks for is vacuous for this walk: there
is no hypothesis under which the count could fail to be this finite number. -/
theorem runV_steps (idOf : α → Nat) (e : VarsE α) (s : List Nat) :
    (runVC idOf e s).2 = costV e ∧ (runVC idOf e s).1 = runV idOf e s :=
  ⟨runVC_steps idOf e s, runVC_val idOf e s⟩

def treeK : Knd → Nat
  | .base _ => 1
  | .arrowK i o => 1 + treeK i + treeK o
  | .varK _ => 1

/-- The cost of `List.map` over a list of type variables: the spine, each `V.map`, and each
annotation's kind. -/
def sTV : List TVar → Nat
  | [] => 1
  | v :: r => 1 + (1 + treeK v.kind) + sTV r

mutual

def subPass : Ty → Nat
  | .arrowT => 1
  | .app a b => 1 + subPass a + subPass b
  | .con ks => 1 + treeK ks.body + ks.forallK.length
  | .var v => 1 + treeK v.kind
  | .allT vs ts q b => 1 + vs.length + sTV ts + subPass q + subPass b
  | .exT xs q => 1 + sTV xs + subPassL q
  | .part v c => 1 + subPass v + subPassL c
  | .mem b => 1 + subPass b
  | .opaqueT => 1

def subPassL : TyList → Nat
  | .tnil => 1
  | .tcons t r => 1 + subPass t + subPassL r

end

/-- The kind walk costs exactly the kind's node count. -/
theorem costK_eq : ∀ k : Knd, costV (kvarsK k) = treeK k := by
  intro k
  induction k with
  | base n => rfl
  | arrowK i o ihi iho => simp [kvarsK, costV, treeK, ihi, iho]
  | varK v => rfl

theorem costTV_le : ∀ ts : List TVar, costV (kvarsTVars ts) ≤ 2 * sTV ts := by
  intro ts
  induction ts with
  | nil => simp [kvarsTVars, costV, sTV]
  | cons v r ih =>
      have h := costK_eq v.kind
      simp only [kvarsTVars, costV, sTV, h]
      omega

theorem subPass_pos : ∀ t : Ty, 1 ≤ subPass t := by
  intro t
  cases t <;> simp [subPass] <;> omega

mutual

/-- **The kind-variable walk costs at most twice one substitution pass.** -/
theorem kvars_cost_le : ∀ t : Ty, costV (kvarsT t) ≤ 2 * subPass t
  | .arrowT => by simp [kvarsT, costV, subPass]
  | .app a b => by
      have ha := kvars_cost_le a
      have hb := kvars_cost_le b
      simp only [kvarsT, costV, subPass]; omega
  | .con ks => by
      have h := costK_eq ks.body
      simp only [kvarsT, kvarsKS, costV, subPass, h]; omega
  | .var v => by
      have h := costK_eq v.kind
      simp only [kvarsT, subPass, h]; omega
  | .allT vs ts q b => by
      have hts := costTV_le ts
      have hb := kvars_cost_le b
      simp only [kvarsT, costV, subPass]; omega
  | .exT xs q => by
      have hxs := costTV_le xs
      have hq := kvarsL_cost_le q
      simp only [kvarsT, costV, subPass]; omega
  | .part v c => by
      have hv := kvars_cost_le v
      have hc := kvarsL_cost_le c
      simp only [kvarsT, costV, subPass]; omega
  | .mem b => by
      have hb := kvars_cost_le b
      simp only [kvarsT, subPass]; omega
  | .opaqueT => by simp [kvarsT, costV, subPass]

theorem kvarsL_cost_le : ∀ l : TyList, costV (kvarsTL l) ≤ 2 * subPassL l
  | .tnil => by simp [kvarsTL, costV, subPassL]
  | .tcons t r => by
      have ht := kvars_cost_le t
      have hr := kvarsL_cost_le r
      simp only [kvarsTL, costV, subPassL]; omega

end

mutual

/-- **And so does the type-variable walk** -- the one behind `SubstEnv.fskvs`. -/
theorem tvars_cost_le : ∀ t : Ty, costV (tvarsT t) ≤ 2 * subPass t
  | .arrowT => by simp [tvarsT, costV, subPass]
  | .app a b => by
      have ha := tvars_cost_le a
      have hb := tvars_cost_le b
      simp only [tvarsT, costV, subPass]; omega
  | .con ks => by simp only [tvarsT, costV, subPass]; omega
  | .var v => by simp only [tvarsT, costV, subPass]; omega
  | .allT vs ts q b => by
      have hb := tvars_cost_le b
      simp only [tvarsT, costV, subPass]; omega
  | .exT xs q => by
      have hq := tvarsL_cost_le q
      simp only [tvarsT, costV, subPass]; omega
  | .part v c => by
      have hv := tvars_cost_le v
      have hc := tvarsL_cost_le c
      simp only [tvarsT, costV, subPass]; omega
  | .mem b => by
      have hb := tvars_cost_le b
      simp only [tvarsT, subPass]; omega
  | .opaqueT => by simp [tvarsT, costV, subPass]

theorem tvarsL_cost_le : ∀ l : TyList, costV (tvarsTL l) ≤ 2 * subPassL l
  | .tnil => by simp [tvarsTL, costV, subPassL]
  | .tcons t r => by
      have ht := tvars_cost_le t
      have hr := tvarsL_cost_le r
      simp only [tvarsTL, costV, subPassL]; omega

end

/-- One substitution pass over the whole of `hm.types` (`Subst.scala:254`). -/
def subPassEnv (Γ : Env) : Nat := (Γ.types.map (fun p => subPass p.2)).sum

/-- One pass over `hm.kinds`. -/
def kindPassEnv (Γ : Env) : Nat := (Γ.kinds.map (fun p => treeK p.2)).sum

/-- What `Subst.scala:648` costs: building and running both walks. -/
def escsCost (Γ : Env) : Nat := costV (envTypeVars Γ) + costV (envKindVars Γ)

theorem cost_tvarsTypes_le : ∀ l : List (TVar × Ty),
    costV (tvarsTypes l) ≤ 2 * (l.map (fun p => subPass p.2)).sum + l.length + 1 := by
  intro l
  induction l with
  | nil => simp [tvarsTypes, costV]
  | cons p r ih =>
      have h := tvars_cost_le p.2
      simp only [tvarsTypes, costV, List.map_cons, List.sum_cons, List.length_cons]
      omega

theorem cost_kvarsTypes_le : ∀ l : List (TVar × Ty),
    costV (kvarsTypes l) ≤ 2 * (l.map (fun p => subPass p.2)).sum + l.length + 1 := by
  intro l
  induction l with
  | nil => simp [kvarsTypes, costV]
  | cons p r ih =>
      have h := kvars_cost_le p.2
      simp only [kvarsTypes, costV, List.map_cons, List.sum_cons, List.length_cons]
      omega

theorem cost_kvarsKinds_le : ∀ l : List (KVar × Knd),
    costV (kvarsKinds l) ≤ (l.map (fun p => treeK p.2)).sum + l.length + 1 := by
  intro l
  induction l with
  | nil => simp [kvarsKinds, costV]
  | cons p r ih =>
      have h := costK_eq p.2
      simp only [kvarsKinds, costV, List.map_cons, List.sum_cons, List.length_cons]
      omega

/-- **The headline cost fact.**  The whole escaping-skolem check at `Subst.scala:648` costs at
most FOUR substitution passes over `hm.types`, one pass over `hm.kinds`, and a per-entry
constant.  `instantiateType` runs one such pass on every binding it makes
(`Subst.scala:254`), so `:648` is a constant factor of ONE unification step: it cannot be
asymptotically worse than the work that built the environment it walks.  Whatever makes the
check take minutes has made every binding take comparably long. -/
theorem escs_cost_le_subPass (Γ : Env) :
    escsCost Γ ≤ 4 * subPassEnv Γ + kindPassEnv Γ + 2 * Γ.types.length + Γ.kinds.length + 4 := by
  have h1 := cost_tvarsTypes_le Γ.types
  have h2 := cost_kvarsTypes_le Γ.types
  have h3 := cost_kvarsKinds_le Γ.kinds
  simp only [escsCost, envTypeVars, envKindVars, costV, subPassEnv, kindPassEnv]
  omega

/-! ## 6. Sharing: the walk unfolds a DAG as a tree

The environment's types are DAGs in the heap: `VarT.subst` (`Type.scala:245-246`) returns THE
SAME `Type` object for every occurrence of the variable it replaces, and `AppT.subst`
(`:229`) returns `this` when nothing underneath changed.  `vars` has no such short-circuit
and no memo table, so it visits every PATH.  The cost is therefore exponential in the size of
a shared representation -- and the same is true of the substitution pass, which is the
negative half of the result. -/

def v0 : TVar := ⟨0, VTy.free, Knd.base 0⟩

/-- The `n`-fold doubling, as a TREE. -/
def dbl : Nat → Ty
  | 0 => .var v0
  | n + 1 => .app (dbl n) (dbl n)

/-- A term with explicit sharing: `dlet d b` binds `d` to `dbound 0` inside `b`. -/
inductive DTy where
  | dvar : TVar → DTy
  | dbound : Nat → DTy
  | dapp : DTy → DTy → DTy
  | dlet : DTy → DTy → DTy

/-- Allocated nodes -- what the heap actually holds. -/
def dsize : DTy → Nat
  | .dvar _ => 1
  | .dbound _ => 1
  | .dapp a b => 1 + dsize a + dsize b
  | .dlet d b => 1 + dsize d + dsize b

/-- The tree the walk sees. -/
def unfoldD : List Ty → DTy → Ty
  | _, .dvar v => .var v
  | env, .dbound i => env.getD i Ty.opaqueT
  | env, .dapp a b => .app (unfoldD env a) (unfoldD env b)
  | env, .dlet d b => unfoldD (unfoldD env d :: env) b

/-- The family: `n` shared doublings. -/
def powD : Nat → DTy
  | 0 => .dvar v0
  | n + 1 => .dlet (powD n) (.dapp (.dbound 0) (.dbound 0))

theorem powD_size : ∀ n : Nat, dsize (powD n) = 4 * n + 1 := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih => simp only [powD, dsize, ih]; omega

theorem powD_unfold : ∀ (n : Nat) (env : List Ty), unfoldD env (powD n) = dbl n := by
  intro n
  induction n with
  | zero => intro env; rfl
  | succ n ih =>
      intro env
      simp only [powD, unfoldD, dbl]
      rw [ih env]
      rfl

theorem cost_dbl : ∀ n : Nat, costV (kvarsT (dbl n)) + 1 = 2 ^ (n + 1) := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih =>
      simp only [dbl, kvarsT, costV]
      rw [pow_succ]
      omega

theorem subPass_dbl : ∀ n : Nat, subPass (dbl n) + 1 = 3 * 2 ^ n := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih =>
      simp only [dbl, subPass]
      rw [pow_succ]
      omega

/-- **The walk is exponential in the DAG's size.**  A shared representation of `4n+1` nodes
unfolds to a tree the walk visits `2^(n+1) - 1` times. -/
theorem walk_exp_in_dag (n : Nat) :
    dsize (powD n) = 4 * n + 1 ∧
      costV (kvarsT (unfoldD [] (powD n))) + 1 = 2 ^ (n + 1) := by
  refine ⟨powD_size n, ?_⟩
  rw [powD_unfold n []]
  exact cost_dbl n

/-- **...and the substitution pass pays the same.**  `Type.subst` unfolds the DAG exactly as
`vars` does, so an environment on which the escape walk is exponential cannot be REACHED
cheaply: `instantiateType` (`Subst.scala:254`) runs a pass of this cost on every binding, and
already paid it before `:648` was entered.  A memo table on `:648` alone therefore removes an
exponential that the unifier is paying anyway -- which is why S2's win has to come from the
walk's DOMAIN (§7), not from its bookkeeping. -/
theorem subst_pays_the_same (n : Nat) :
    subPass (unfoldD [] (powD n)) + 1 = 3 * 2 ^ n := by
  rw [powD_unfold n []]
  exact subPass_dbl n

/-! ## 7. The restricted check, and what may change

`escs` collects EVERY variable of the environment and then keeps the handful that are in
`stss`/`skss`.  The cheap check runs the membership the other way round: for each of the
call's own skolems, ask whether it occurs.  Nothing observable changes, because nothing but
`nonEmpty` is ever observed. -/

def occursTV (n : Nat) (Γ : Env) : Bool := memN n (fvId TVar.id (envTypeVars Γ))

def occursKV (n : Nat) (Γ : Env) : Bool := memN n (fvId KVar.id (envKindVars Γ))

/-- The restricted check `X`: one occurrence test per skolem of THIS call. -/
def verdictR (Γ : Env) (sks : List KVar) (sts : List TVar) : Bool :=
  sts.any (fun v => occursTV v.id Γ) || sks.any (fun u => occursKV u.id Γ)

/-- **The invariant the equivalence needs**, and the only one it needs.  Not acyclicity: the
statement is that a variable in the environment carrying one of this call's skolem IDS really
is a skolem -- the `V` ids are globally unique (`Vars.scala:92-95`) and `unbind(Skolem, e1)`
mints skolems (`Subst.scala:614, :686-689`).  It is what makes `Type.fskvs`'s
`_.ty == Skolem` filter (`Type.scala:666`) redundant in this use. -/
def SkolemCoherent (Γ : Env) (sts : List TVar) : Prop :=
  ∀ v ∈ occE (envTypeVars Γ), v.id ∈ sts.map TVar.id → v.ty = VTy.skolem

/-- Global id uniqueness plus "the signature's variables are skolems" gives it. -/
theorem skolemCoherent_of_unique (Γ : Env) (sts : List TVar)
    (huniq : ∀ v ∈ occE (envTypeVars Γ), ∀ w ∈ sts, v.id = w.id → v = w)
    (hsk : ∀ w ∈ sts, w.ty = VTy.skolem) : SkolemCoherent Γ sts := by
  intro v hv hid
  obtain ⟨w, hw, hwid⟩ := List.mem_map.1 hid
  have : v = w := huniq v hv w hw hwid.symm
  rw [this]; exact hsk w hw

theorem isEmpty_false_iff {β : Type} (l : List β) : (!l.isEmpty) = true ↔ ∃ x, x ∈ l := by
  cases l with
  | nil => simp
  | cons a t => exact ⟨fun _ => ⟨a, by simp⟩, fun _ => by simp⟩

/-- The type half of `escs` is nonempty exactly when one of the call's skolem type variables
occurs in the environment. -/
theorem escs1_iff (Γ : Env) (sts : List TVar) (h : SkolemCoherent Γ sts) :
    (∃ n, n ∈ ((fskvs Γ).filter (fun v => memN v.id (sts.map TVar.id))).map TVar.id) ↔
      ∃ w ∈ sts, w.id ∈ fvId TVar.id (envTypeVars Γ) := by
  constructor
  · rintro ⟨n, hn⟩
    rw [mem_map_filter] at hn
    obtain ⟨v, hv, hp, rfl⟩ := hn
    have hvem : v ∈ (runV TVar.id (envTypeVars Γ) []).1 := (List.mem_filter.1 hv).1
    have hvfv : v ∈ fvE TVar.id (envTypeVars Γ) :=
      runV_emitted_subset TVar.id (envTypeVars Γ) [] v hvem
    obtain ⟨w, hw, hwid⟩ := List.mem_map.1 (by simpa using hp : v.id ∈ sts.map TVar.id)
    exact ⟨w, hw, by rw [hwid]; exact List.mem_map_of_mem hvfv⟩
  · rintro ⟨w, hw, hwfv⟩
    have : w.id ∈ (runV TVar.id (envTypeVars Γ) []).1.map TVar.id :=
      (runV_emitted_id TVar.id (envTypeVars Γ) [] w.id).2 ⟨hwfv, by simp⟩
    obtain ⟨v, hv, hvid⟩ := List.mem_map.1 this
    have hin : v.id ∈ sts.map TVar.id := by rw [hvid]; exact List.mem_map_of_mem hw
    have hocc : v ∈ occE (envTypeVars Γ) :=
      fvE_subset_occE TVar.id (envTypeVars Γ) v
        (runV_emitted_subset TVar.id (envTypeVars Γ) [] v hv)
    refine ⟨v.id, ?_⟩
    rw [mem_map_filter]
    exact ⟨v, List.mem_filter.2 ⟨hv, by simp [h v hocc hin]⟩, by simpa using hin, rfl⟩

/-- The kind half, with no hypothesis at all: `hm.kindVars` carries no `Skolem` filter. -/
theorem escs2_iff (Γ : Env) (sks : List KVar) :
    (∃ n, n ∈ ((runV KVar.id (envKindVars Γ) []).1.filter
        (fun u => memN u.id (sks.map KVar.id))).map KVar.id) ↔
      ∃ w ∈ sks, w.id ∈ fvId KVar.id (envKindVars Γ) := by
  constructor
  · rintro ⟨n, hn⟩
    rw [mem_map_filter] at hn
    obtain ⟨u, hu, hp, rfl⟩ := hn
    have hufv : u ∈ fvE KVar.id (envKindVars Γ) :=
      runV_emitted_subset KVar.id (envKindVars Γ) [] u hu
    obtain ⟨w, hw, hwid⟩ := List.mem_map.1 (by simpa using hp : u.id ∈ sks.map KVar.id)
    exact ⟨w, hw, by rw [hwid]; exact List.mem_map_of_mem hufv⟩
  · rintro ⟨w, hw, hwfv⟩
    have : w.id ∈ (runV KVar.id (envKindVars Γ) []).1.map KVar.id :=
      (runV_emitted_id KVar.id (envKindVars Γ) [] w.id).2 ⟨hwfv, by simp⟩
    obtain ⟨u, hu, huid⟩ := List.mem_map.1 this
    have hin : u.id ∈ sks.map KVar.id := by rw [huid]; exact List.mem_map_of_mem hw
    refine ⟨u.id, ?_⟩
    rw [mem_map_filter]
    exact ⟨u, hu, by simpa using hin, rfl⟩

/-- **THE EQUIVALENCE.**  The restricted check and `Subst.scala:648` give the same verdict, so
what may change when S2 replaces the walk is: NOTHING observable.  `escs`'s elements are dead
(`:649-657`), the verdict is all that reaches the program, and the verdict is the same. -/
theorem verdict_iff (Γ : Env) (sks : List KVar) (sts : List TVar)
    (h : SkolemCoherent Γ sts) :
    verdict Γ sks sts = true ↔ verdictR Γ sks sts = true := by
  rw [verdict, escs, isEmpty_false_iff]
  constructor
  · rintro ⟨n, hn⟩
    rcases List.mem_append.1 hn with hn | hn
    · obtain ⟨w, hw, hwfv⟩ := (escs1_iff Γ sts h).1 ⟨n, hn⟩
      simp only [verdictR, Bool.or_eq_true, List.any_eq_true]
      exact Or.inl ⟨w, hw, by simpa [occursTV] using hwfv⟩
    · obtain ⟨w, hw, hwfv⟩ := (escs2_iff Γ sks).1 ⟨n, hn⟩
      simp only [verdictR, Bool.or_eq_true, List.any_eq_true]
      exact Or.inr ⟨w, hw, by simpa [occursKV] using hwfv⟩
  · intro hr
    simp only [verdictR, Bool.or_eq_true, List.any_eq_true] at hr
    rcases hr with ⟨w, hw, hwo⟩ | ⟨w, hw, hwo⟩
    · obtain ⟨n, hn⟩ := (escs1_iff Γ sts h).2 ⟨w, hw, by simpa [occursTV] using hwo⟩
      exact ⟨n, List.mem_append.2 (Or.inl hn)⟩
    · obtain ⟨n, hn⟩ := (escs2_iff Γ sks).2 ⟨w, hw, by simpa [occursKV] using hwo⟩
      exact ⟨n, List.mem_append.2 (Or.inr hn)⟩

theorem verdict_eq (Γ : Env) (sks : List KVar) (sts : List TVar)
    (h : SkolemCoherent Γ sts) : verdict Γ sks sts = verdictR Γ sks sts := by
  have := verdict_iff Γ sks sts h
  cases hv : verdict Γ sks sts <;> cases hr : verdictR Γ sks sts <;>
    simp only [hv, hr] at this ⊢ <;> simp at this

/-- **`Type.fskvs`'s `Skolem` filter is redundant here.**  Under the same invariant the first
half of `escs` is unchanged by deleting `_.ty == Skolem` (`Type.scala:666`): the id test
already implies it. -/
theorem skolem_filter_redundant (Γ : Env) (sts : List TVar) (h : SkolemCoherent Γ sts) :
    (fskvs Γ).filter (fun v => memN v.id (sts.map TVar.id)) =
      (runV TVar.id (envTypeVars Γ) []).1.filter (fun v => memN v.id (sts.map TVar.id)) := by
  rw [fskvs, List.filter_filter]
  refine List.filter_congr ?_
  intro v hv
  have hocc : v ∈ occE (envTypeVars Γ) :=
    fvE_subset_occE TVar.id (envTypeVars Γ) v
      (runV_emitted_subset TVar.id (envTypeVars Γ) [] v hv)
  by_cases hp : v.id ∈ sts.map TVar.id
  · simp [memN, hp, h v hocc hp]
  · simp [memN, hp]

/-! ### The untouched-entry licence

`Untouched` is a hypothesis about the CONTENT of the skipped entries at the moment of the
check, and the theorem says such entries may be skipped.  It is the only restriction in this
file that could make the check asymptotically cheaper rather than merely tidier.

**It is NOT discharged by insertion order, and reading it that way accepts an escaping
skolem** (S1a review, Finding 1).  `instantiateType` (`Subst.scala:254`) is
`hm.types = subType(Map(v -> e), hm.types) + (v -> e)`: it rewrites EVERY VALUE in `hm.types`
on every binding, so an entry whose key and value both predate the fresh draw at `:614` can
still come to mention a skolem drawn there.  Let `a |-> F(u)` predate the draw; `:616`'s
`unifyType` binds `u |-> G(t)` for a `t` minted at `:615` and then `t |-> H(sk)` for
`sk` in `sts`, rewriting `a` to `a |-> F(G(H(sk)))`; `:645`'s `restrictTypes(tts)` deletes
`t`, and the surviving witnesses of the escape are keyed by `a` and `u`, both inserted BEFORE
`:614`.  An implementation that stamps an entry when its KEY is inserted and skips "entries
older than the draw" computes `escs` empty, does not `die`, and ACCEPTS the program.

Age is a sound proxy only for a mechanism that RE-STAMPS an entry whenever `subType` changes
its value, or that tracks the skolem ids each entry currently contains.  Proving that update
law is S2's obligation; the statement below says exactly what it must deliver. -/

theorem any_congr_mem {β : Type} (l : List β) (p q : β → Bool)
    (h : ∀ x ∈ l, p x = q x) : l.any p = l.any q := by
  induction l with
  | nil => rfl
  | cons a t ih =>
      simp only [List.any_cons]
      rw [h a (by simp), ih (fun x hx => h x (by simp [hx]))]

def Untouched (old : List (TVar × Ty)) (sks : List KVar) (sts : List TVar) : Prop :=
  (∀ v ∈ occE (tvarsTypes old), v.id ∉ sts.map TVar.id) ∧
    (∀ u ∈ occE (kvarsTypes old), u.id ∉ sks.map KVar.id)

theorem tvarsTypes_append : ∀ (a b : List (TVar × Ty)) (n : Nat),
    n ∈ fvId TVar.id (tvarsTypes (a ++ b)) ↔
      n ∈ fvId TVar.id (tvarsTypes a) ∨ n ∈ fvId TVar.id (tvarsTypes b) := by
  intro a
  induction a with
  | nil => intro b n; simp [tvarsTypes, fvId, fvE]
  | cons p r ih => intro b n; simp only [List.cons_append, tvarsTypes, fvId_app,
      List.mem_append, ih b n]; tauto

theorem kvarsTypes_append : ∀ (a b : List (TVar × Ty)) (n : Nat),
    n ∈ fvId KVar.id (kvarsTypes (a ++ b)) ↔
      n ∈ fvId KVar.id (kvarsTypes a) ∨ n ∈ fvId KVar.id (kvarsTypes b) := by
  intro a
  induction a with
  | nil => intro b n; simp [kvarsTypes, fvId, fvE]
  | cons p r ih => intro b n; simp only [List.cons_append, kvarsTypes, fvId_app,
      List.mem_append, ih b n]; tauto

theorem occE_tvarsTypes_append : ∀ (a b : List (TVar × Ty)) (v : TVar),
    v ∈ occE (tvarsTypes a) → v ∈ occE (tvarsTypes (a ++ b)) := by
  intro a
  induction a with
  | nil => intro b v h; simp [tvarsTypes, occE] at h
  | cons p r ih =>
      intro b v h
      simp only [List.cons_append, tvarsTypes, occE, List.mem_append] at h ⊢
      rcases h with h | h
      · exact Or.inl h
      · exact Or.inr (ih b v h)

/-- **Entries that cannot mention this call's skolems contribute nothing to the verdict.**
`Untouched` is about the CONTENT of `old` at the moment of the check, never about its age: see
the section header.  `instantiateType` rewrites every value in `hm.types` on every binding, so
an entry older than the `:614` draw can still mention a skolem drawn there. -/
theorem escs_restrict_untouched (old new : List (TVar × Ty)) (kinds : List (KVar × Knd))
    (sks : List KVar) (sts : List TVar) (h : Untouched old sks sts) :
    verdictR ⟨old ++ new, kinds⟩ sks sts = verdictR ⟨new, kinds⟩ sks sts := by
  have hT : ∀ w : TVar, w ∈ sts →
      (occursTV w.id ⟨old ++ new, kinds⟩ = occursTV w.id ⟨new, kinds⟩) := by
    intro w hw
    have hold : w.id ∉ fvId TVar.id (tvarsTypes old) := by
      intro hc
      obtain ⟨v, hv, hvid⟩ := List.mem_map.1 hc
      exact h.1 v (fvE_subset_occE TVar.id (tvarsTypes old) v hv)
        (by rw [hvid]; exact List.mem_map_of_mem hw)
    have hiff : (w.id ∈ fvId TVar.id (envTypeVars ⟨old ++ new, kinds⟩)) ↔
        (w.id ∈ fvId TVar.id (envTypeVars ⟨new, kinds⟩)) := by
      show (w.id ∈ fvId TVar.id (tvarsTypes (old ++ new))) ↔
        (w.id ∈ fvId TVar.id (tvarsTypes new))
      rw [tvarsTypes_append old new w.id]
      tauto
    simp only [occursTV, memN]
    exact decide_eq_decide.mpr hiff
  have hK : ∀ w : KVar, w ∈ sks →
      (occursKV w.id ⟨old ++ new, kinds⟩ = occursKV w.id ⟨new, kinds⟩) := by
    intro w hw
    have hold : w.id ∉ fvId KVar.id (kvarsTypes old) := by
      intro hc
      obtain ⟨u, hu, huid⟩ := List.mem_map.1 hc
      exact h.2 u (fvE_subset_occE KVar.id (kvarsTypes old) u hu)
        (by rw [huid]; exact List.mem_map_of_mem hw)
    have hiff : (w.id ∈ fvId KVar.id (envKindVars ⟨old ++ new, kinds⟩)) ↔
        (w.id ∈ fvId KVar.id (envKindVars ⟨new, kinds⟩)) := by
      simp only [envKindVars, fvId_app, List.mem_append]
      rw [kvarsTypes_append old new w.id]
      tauto
    simp only [occursKV, memN]
    exact decide_eq_decide.mpr hiff
  simp only [verdictR]
  rw [any_congr_mem sts _ _ hT, any_congr_mem sks _ _ hK]

/-- **No early exit when the verdict is empty.**  The restricted check short-circuits on the
first escaping skolem, but a REJECTION path on which nothing escapes forces every skolem to be
tested against the whole environment.  S2 must not sell short-circuiting as the fix. -/
theorem no_early_exit_on_empty (Γ : Env) (sks : List KVar) (sts : List TVar)
    (h : verdictR Γ sks sts = false) :
    (∀ w ∈ sts, occursTV w.id Γ = false) ∧ (∀ w ∈ sks, occursKV w.id Γ = false) := by
  simp only [verdictR, Bool.or_eq_false_iff, List.any_eq_false] at h
  exact ⟨fun w hw => Bool.eq_false_iff.2 (h.1 w hw), fun w hw => Bool.eq_false_iff.2 (h.2 w hw)⟩

theorem occE_tvarsTypes_right : ∀ (a b : List (TVar × Ty)) (v : TVar),
    v ∈ occE (tvarsTypes b) → v ∈ occE (tvarsTypes (a ++ b)) := by
  intro a
  induction a with
  | nil => intro b v h; exact h
  | cons p r ih =>
      intro b v h
      simp only [List.cons_append, tvarsTypes, occE, List.mem_append]
      exact Or.inr (ih b v h)

theorem skolemCoherent_shrink (old new : List (TVar × Ty)) (kinds : List (KVar × Knd))
    (sts : List TVar) (h : SkolemCoherent ⟨old ++ new, kinds⟩ sts) :
    SkolemCoherent ⟨new, kinds⟩ sts := fun v hv hid =>
  h v (occE_tvarsTypes_right old new v hv) hid

/-- **The one asymptotic licence in this file, on the SHIPPED check.**  `escs`'s own verdict
is unchanged by dropping every environment entry that cannot mention this call's skolems.  What
`Untouched` does NOT say is that insertion order decides which entries those are: it does not
(see the section header), and S2 owes a proved re-stamping law before it may use age as the
proxy. -/
theorem verdict_restrict_untouched (old new : List (TVar × Ty)) (kinds : List (KVar × Knd))
    (sks : List KVar) (sts : List TVar) (hu : Untouched old sks sts)
    (h : SkolemCoherent ⟨old ++ new, kinds⟩ sts) :
    verdict ⟨old ++ new, kinds⟩ sks sts = verdict ⟨new, kinds⟩ sks sts := by
  rw [verdict_eq _ _ _ h, verdict_eq _ _ _ (skolemCoherent_shrink old new kinds sts h),
    escs_restrict_untouched old new kinds sks sts hu]

/-! ### One restriction that is NOT available

The narrow statement the witness below supports, and no wider one: **the kind half cannot be
restricted to the entries the skolem TYPE variables occur in.**  A skolem KIND variable can
reach the environment through `unifyKind`/`instantiateKind` (`Subst.scala:239-245`) inside the
kind annotation of an entry that contains no skolem TYPE variable at all, and then
`hm.kindVars.filter(skss(_))` fires while `hm.fskvs` is empty of skolems.

This does NOT refute the brief's candidate `X` ("`sks`/`sts` and the types they occur in") read
so that "occur in" includes KIND-LEVEL occurrence: in `kindOnlyEnv` the skolem `u` DOES occur
in the entry's type, inside the `Con`'s kind schema, so a restriction keyed on kind-level
occurrence remains open to S2 (S1a review, Finding 3). -/

def uKV : KVar := ⟨2, VTy.skolem⟩

def wTV : TVar := ⟨3, VTy.free, Knd.base 0⟩

/-- A one-entry environment binding a FREE type variable to a `Con` whose kind schema mentions
the skolem kind variable `u`. -/
def kindOnlyEnv : Env := ⟨[(wTV, Ty.con ⟨[], Knd.varK uKV⟩)], []⟩

/-- **The kind half cannot be restricted to the entries the skolem TYPE variables occur in.**
Here the type-variable walk emits nothing at all, and the check still (correctly) reports an
escape. -/
theorem kind_half_not_reducible_to_type_skolems :
    (runV TVar.id (envTypeVars kindOnlyEnv) []).1 = [] ∧
      escs kindOnlyEnv [uKV] [] = [2] ∧ verdict kindOnlyEnv [uKV] [] = true := by
  decide

/-- ...and the restricted check agrees with it, as `verdict_eq` requires. -/
theorem kindOnly_verdictR : verdictR kindOnlyEnv [uKV] [] = true := by decide

end SubsumeEscape
end Rowpartition
