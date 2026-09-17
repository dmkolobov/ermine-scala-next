/-
# S1b: how big is the `SubstEnv` the loop can leave, and can it be CYCLIC?

`tracker/satterm/briefs/brief-S1b.md`, deliverables 2 and 3.  The hang the programme is about
(`tracker/PROMPT-subsume-termination.md` Part B) samples every thread in
`Subst.subsumeType`'s escaping-skolem check at `:648`, which walks the KINDS of every type in
`SubstEnv.types` through an unmemoised `foldRight`.  Two of the three hypotheses are about that
map:

* **H1, finite but explosive** -- the rejection path leaves `hm.types` ENORMOUS and the walk is
  super-linear on it;
* **H2, cyclic substitution** -- a variable is bound to a type that mentions it, through some
  chain, and the walk never returns.

This module answers both FOR THE ROW LOOP, which is the part of the compiler the loop model is
faithful to (L2: 2,355,430 corpus solve segments, 0 mismatches).  §1-§2 bound the environment,
§3 the walk over it, §4 exhibits the blow-up that H1 needs and shows WHERE it has to come from,
and §5 proves the no-cyclic-binding invariant.

THE ANSWER IN ONE LINE.  `incorporateAll` writes exactly two shapes into `SubstEnv.types` --
`instantiateType(v, VarT(u))` at `Constraints.scala:2139` and
`instantiateType(v, ConcreteRho(Loc.builtin, Set()))` at `:2191`, which is what `EnvVal` is
(`Loop/State.lean` §6) -- so every entry the loop writes is ONE NODE and the map grows by at
most one entry per dequeue, which leaves neither of `:648`'s two walks anything to recurse into
over those entries.  (§3 models the `fskvs` half of that line only, and bounds its ANSWER; the
`kindVars` half is not modelled -- read §3's header before citing it.)  The row loop cannot be
the source of an enormous `hm.types` MEASURED IN TERM SIZE; §4 shows a three-line substitution
chain that is, and it is built by `unifyType`'s VARIABLE arms (`Subst.scala:313-318`), which are
not in this model.
-/
import Rowpartition.Loop.RejectTerm

namespace Rowpartition.Loop

variable {pol : Policy} {aux : Aux}

/-! ## 1. The environment grows by at most one entry per dequeue -/

/-- **One dequeue binds at most one variable.**  `instantiate` and `makeEmpty` append exactly
one entry (`StrictBound.instantiate_env_len`, `makeEmpty_env_len`); the `concrete` and `learn`
branches write nothing at all, which is why `makeConcrete`'s row never reaches `SubstEnv.types`
(it stays in the processed queue -- `Loop/Step.lean`'s `insertNP`). -/
theorem stepP_env_len_le {s s' : State} (h : stepP pol aux s = .continue s') :
    s'.env.binds.length ≤ s.env.binds.length + 1 := by
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    split at h
    · rename_i u _
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        rcases unifyVars_env hres with rfl | ⟨hl, -, -⟩
        · exact Nat.le_succ _
        · exact Nat.le_of_eq hl
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          exact Nat.le_of_eq (makeEmpty_env_len hres).1
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact Nat.le_succ _
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              rcases unifyVars_env hres with rfl | ⟨hl, -, -⟩
              · exact Nat.le_succ _
              · exact Nat.le_of_eq hl
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              simp [foldl_log_env]

/-- **Along a run of `n` dequeues the environment gains at most `n` entries.**  The bound S2
compares with S0's measured `hm.types.size`: it is LINEAR in the number of dequeues, with no
dependence on the size of the constraints. -/
theorem runsP_env_len_le : ∀ (n : Nat) {a c : Aux} {s t : State},
    RunsP pol n a s c t → t.env.binds.length ≤ s.env.binds.length + n
  | 0, a, c, s, t, hr => by
    simp only [RunsP] at hr
    obtain ⟨rfl, rfl⟩ := hr
    exact Nat.le_refl _
  | n + 1, a, c, s, t, hr => by
    obtain ⟨u, hstep, hrest⟩ := hr
    have h1 := runsP_env_len_le n hrest
    have h2 := stepP_env_len_le hstep
    omega

/-! ## 2. Every entry the loop writes is ONE NODE -/

/-- The SIZE, in type-constructor nodes, of the `Type` `instantiateType` is handed.  Both of the
loop's two writes are leaves: `VarT(u)` is one node (`Type.scala`'s `VarT`) and
`ConcreteRho(Loc.builtin, Set())` is one node with an EMPTY label set.  This is a definition
about the model's `EnvVal`, and `EnvVal` is faithful by construction -- `Loop/State.lean` §6
records the two `instantiateType` call sites it abstracts, and they are the only two the loop
has (`Constraints.scala:2139`, `:2191`). -/
def EnvVal.termSize : EnvVal → Nat
  | .emptyRow => 1
  | .alias _ => 1

/-- The total term size of the environment's RANGE: what `Type.fskvs(hm.types)` and
`Kind.kindVars(hm.types)` walk. -/
def envTermSize (e : Env) : Nat := (e.binds.map (fun b => EnvVal.termSize b.2)).sum

/-- **The range's total size IS its cardinality.**  No chain of bindings whose substituted form
is exponential can exist inside what the loop writes: there is no compound term to substitute
INTO.  (`Env.instantiate` does run a substitution over the range -- `alias v ↦ val` -- but on
one-node terms it can only replace a leaf by a leaf.) -/
theorem envTermSize_eq_len (e : Env) : envTermSize e = e.binds.length := by
  unfold envTermSize
  induction e.binds with
  | nil => simp
  | cons b bs ih =>
    simp only [List.map_cons, List.sum_cons, List.length_cons, ih]
    cases b.2 <;> simp [EnvVal.termSize] <;> omega

/-- **The environment bound, as one statement.**  After a run of `n` dequeues from `s`, the
substitution environment has at most `|s.env| + n` entries and its total term size is the same
number.  With `s` a solve's initial state (`env = {}`, `RejectTerm.seedInit`) that is: at most
`n` entries of one node each. -/
theorem runsP_envTermSize_le : ∀ (n : Nat) {a c : Aux} {s t : State},
    RunsP pol n a s c t → envTermSize t.env ≤ envTermSize s.env + n := by
  intro n a c s t hr
  rw [envTermSize_eq_len, envTermSize_eq_len]
  exact runsP_env_len_le n hr

/-- The vocabulary form of the same bound, for the fragments where a vocabulary is fixed:
`NoConc.env_len_le_card` says a `Nodup` environment inside a vocabulary `V` has at most `|V|`
entries, so its total term size is at most `|V|` as well. -/
theorem envTermSize_le_card {V : Finset Var} {s : State} (h : InVoc V s) (hnd : EnvNodup s) :
    envTermSize s.env ≤ V.card := by
  rw [envTermSize_eq_len]
  exact env_len_le_card h hnd

/-! ## 3. The `fskvs` HALF of the escaping-skolem walk, over what the loop wrote

**READ THE SCOPE BEFORE THE THEOREM.**  `Subst.subsumeType:648` is
`hm.fskvs.filter(v => stss.contains(v)) ++ hm.kindVars.filter(skss(_))`, which is TWO walks:

* `Type.fskvs(hm.types)` -- `mapHasTypeVars.vars` folds over the map's VALUES
  (`Type.scala:771`), which is what `escWalk` below is;
* `hm.kindVars` = `Kind.kindVars(kinds) ++ Kind.kindVars(types)` (`Subst.scala:169`), which
  walks the KIND ANNOTATION of every variable in every value (`Kind.scala:132-134`).  **That
  half is NOT modelled here**, because `EnvVal` carries no kind component at all -- and it is
  the half Part B's jstack sits in (`Kind$.kindVars:96 <- SubstEnv.kindVars:169 <-
  subsumeType:648`) and the half S0's largest number (35,921 tree nodes) measures.

So nothing below is an equivalence with `:648`: `escWalk` is a DEFINITION this stage
introduces, faithful to the `fskvs` half over the two shapes the loop writes, and
`escWalk_length_le` bounds the LENGTH OF ITS ANSWER, not the work either walk performs.  The
honest statement about cost is `envTermSize_eq_len` (§2) plus the `EnvVal` faithfulness note
(`Loop/State.lean` §6): what the loop writes is one node per entry, so there is nothing for
either walk to recurse into. -/

/-- The skolem-filtered `fskvs` walk over the loop's own entries:
`Type.fskvs(types).filter(stss)` restricted to the two shapes `EnvVal` records.  `sks` is
`stss` -- the skolem set `subsumeType` filters by.  The `kindVars` half of `:648` has no
counterpart here (see the section header). -/
def escWalk (sks : Nat → Bool) (e : Env) : List Nat :=
  e.binds.filterMap (fun b => match b.2 with
    | .alias u => if sks u then some u else none
    | .emptyRow => none)

/-- **The ANSWER is at most one variable per entry.**  This bounds the RESULT (it is
`List.length_filterMap_le`), not the work of `:648`; the definition has no recursion by
construction, which is a fact about the definition and not a theorem about the compiler.  What
makes the compiler's walk cheap over these entries is that each is a single node
(`envTermSize_eq_len`).  Two code facts belong with it, neither of them proved here: the walk
never follows a BINDING -- `typeHasKindVars.vars` at `VarT(v)` reads `v.extract`, the
variable's KIND ANNOTATION (`Type.scala:651`, `Kind.scala:135`) -- and `Type`/`Kind`/`V` are
strict case classes, so no term's object graph can be cyclic.  §5 proves separately that the
environment has no cyclic binding. -/
theorem escWalk_length_le (sks : Nat → Bool) (e : Env) :
    (escWalk sks e).length ≤ e.binds.length := by
  unfold escWalk
  exact List.length_filterMap_le _ _

/-- The same bound along a run: at most `|s.env| + n` escaping variables can be reported out of
what the loop wrote in `n` dequeues.  Again a bound on the ANSWER, and only over the `fskvs`
half and only over the loop's own entries. -/
theorem runsP_escWalk_le {sks : Nat → Bool} : ∀ (n : Nat) {a c : Aux} {s t : State},
    RunsP pol n a s c t → (escWalk sks t.env).length ≤ s.env.binds.length + n := by
  intro n a c s t hr
  exact le_trans (escWalk_length_le sks t.env) (runsP_env_len_le n hr)

/-! ## 4. Where H1's enormous `hm.types` HAS to come from

The loop cannot build a big substitution (§2).  `Subst.instantiateType` in general can, and
this section exhibits it: `hm.types = subType(Map(v -> e), hm.types) + (v -> e)`
(`Subst.scala:255`) rewrites the whole RANGE at every binding, so `n` bindings can square-and-
square again one entry's term.  The witness below is not pathological input: every step binds a
variable that is UNBOUND, to a term that does not mention it (so `occursCheckType` passes at
`Subst.scala:314`), and the environment stays fully substituted -- no bound variable occurs in
any range term.  The invariant of §5 is therefore NOT a defence against H1; only a bound on the
number or the shape of the bindings would be.

The compiler path that does this is `unifyType`'s VARIABLE arms, `Subst.scala:313-318` -- the
`case (VarT(v), e) if v.ty != Skolem` / `case (e, VarT(v))` pair, where `occursCheckType` is
tested and `instantiateType` (`:254`) is called.  (`:319`'s `AppT` arm is what puts the
compound term on the other side; it is not the binder.)  It is outside the loop model.  S1a's substitution model is the lane that studies it; this section exists so that S2
reads the two results together: a large `hm.types` is evidence about the TYPE CHECKER's
unifications, never about the row solver. -/

namespace SubstBlowup

/-- A type syntax with just enough structure for `AppT`: a variable and an application. -/
inductive Ty where
  | var (v : Nat)
  | app (a b : Ty)
deriving DecidableEq, Repr

namespace Ty

/-- Nodes, the unit `Type.fskvs`'s walk pays in. -/
def size : Ty → Nat
  | .var _ => 1
  | .app a b => 1 + a.size + b.size

/-- `Type.subType` for a single-variable map, which is what `instantiateType` applies. -/
def subst1 (v : Nat) (e : Ty) : Ty → Ty
  | .var w => if w = v then e else .var w
  | .app a b => .app (subst1 v e a) (subst1 v e b)

/-- `w` occurs in the term -- `occursCheckType`'s question. -/
def mentions : Ty → Nat → Prop
  | .var v, w => v = w
  | .app a b, w => mentions a w ∨ mentions b w

end Ty

/-- The balanced tree of depth `d` all of whose leaves are `var lv`. -/
def bal (lv : Nat) : Nat → Ty
  | 0 => .var lv
  | d + 1 => .app (bal lv d) (bal lv d)

/-- A balanced tree of depth `d` has `2^(d+1) - 1` nodes. -/
theorem size_bal (lv d : Nat) : (bal lv d).size + 1 = 2 ^ (d + 1) := by
  induction d with
  | zero => simp [bal, Ty.size]
  | succ d ih =>
    have hp : (2 : Nat) ^ (d + 1 + 1) = 2 ^ (d + 1) * 2 := Nat.pow_succ 2 (d + 1)
    have h1 : 1 ≤ (2 : Nat) ^ (d + 1) := Nat.one_le_pow (d + 1) 2 (by omega)
    simp only [bal, Ty.size]
    omega

/-- ...and it mentions exactly its leaf variable. -/
theorem mentions_bal (lv : Nat) : ∀ (d w : Nat), Ty.mentions (bal lv d) w → w = lv := by
  intro d
  induction d with
  | zero =>
    intro w h
    simp only [bal, Ty.mentions] at h
    exact h.symm
  | succ d ih =>
    intro w h
    simp only [bal, Ty.mentions] at h
    exact h.elim (ih w) (ih w)

/-- **The doubling step.**  Binding `k` to `app (var (k+1)) (var (k+1))` turns a balanced tree
over `k` into a balanced tree over `k+1` one level deeper.  The bound variable `k` does not
occur in the value, so this is a legal `instantiateType`: `occursCheckType k (app ..)` is
false. -/
theorem subst1_bal (k d : Nat) :
    Ty.subst1 k (.app (.var (k + 1)) (.var (k + 1))) (bal k d) = bal (k + 1) (d + 1) := by
  induction d with
  | zero => simp [bal, Ty.subst1]
  | succ d ih => simp only [bal, Ty.subst1, ih]

/-- `Subst.instantiateType`'s environment update, for the type half: rewrite the whole range
through `v ↦ e`, then add the entry. -/
def instEnv (env : List (Nat × Ty)) (v : Nat) (e : Ty) : List (Nat × Ty) :=
  env.map (fun p => (p.1, Ty.subst1 v e p.2)) ++ [(v, e)]

/-- `n` unifications, each binding a fresh variable to a two-leaf application of the next. -/
def chain : Nat → List (Nat × Ty)
  | 0 => [(0, bal 1 0)]
  | n + 1 => instEnv (chain n) (n + 1) (.app (.var (n + 1 + 1)) (.var (n + 1 + 1)))

theorem chain_keys (n : Nat) : (chain n).map Prod.fst = List.range (n + 1) := by
  induction n with
  | zero => simp [chain]
  | succ n ih =>
    simp only [chain, instEnv, List.map_append, List.map_map, Function.comp_def, List.map_cons,
      List.map_nil, ih]
    simp [List.range_succ]

/-- Every value in the chain is a balanced tree over the one variable the chain has not bound
yet.  So the environment is FULLY SUBSTITUTED: no bound variable occurs in any range term. -/
theorem chain_values (n : Nat) : ∀ p ∈ chain n, ∃ d, p.2 = bal (n + 1) d := by
  induction n with
  | zero => intro p hp; simp only [chain, List.mem_singleton] at hp; exact ⟨0, by rw [hp]⟩
  | succ n ih =>
    intro p hp
    simp only [chain, instEnv, List.mem_append, List.mem_map, List.mem_singleton] at hp
    rcases hp with ⟨q, hq, rfl⟩ | rfl
    · obtain ⟨d, hd⟩ := ih q hq
      refine ⟨d + 1, ?_⟩
      simp only [hd]
      exact subst1_bal (n + 1) d
    · exact ⟨1, by simp [bal]⟩

/-- The chain's FIRST entry, explicitly: the variable `0`, bound to a balanced tree of depth
`n` -- one level per unification. -/
theorem chain_head (n : Nat) : ∃ tl, chain n = (0, bal (n + 1) n) :: tl := by
  induction n with
  | zero => exact ⟨[], by simp [chain]⟩
  | succ n ih =>
    obtain ⟨tl, htl⟩ := ih
    refine ⟨tl.map (fun p => (p.1, Ty.subst1 (n + 1) (.app (.var (n + 1 + 1)) (.var (n + 1 + 1))) p.2)) ++
      [(n + 1, (.app (.var (n + 1 + 1)) (.var (n + 1 + 1)) : Ty))], ?_⟩
    simp only [chain, instEnv, htl, List.map_cons, List.cons_append]
    rw [subst1_bal (n + 1) n]

theorem chain_head_mem (n : Nat) : (0, bal (n + 1) n) ∈ chain n := by
  obtain ⟨tl, htl⟩ := chain_head n
  rw [htl]
  simp

/-- **The witness.**  After `n` unifications the environment has `n + 1` entries, its keys are
distinct, no bound variable occurs in its range -- and one entry's term has `2^(n+1) - 1` nodes.
Cardinality is LINEAR and range size is EXPONENTIAL, which is exactly H1's "enormous
`hm.types`", reached without a cycle, without a failed occurs check and without the row
solver. -/
theorem chain_blowup (n : Nat) :
    ((chain n).map Prod.fst).Nodup ∧
      (chain n).length = n + 1 ∧
      (∀ p ∈ chain n, ∀ w, Ty.mentions p.2 w → w ∉ (chain n).map Prod.fst) ∧
      (∃ p ∈ chain n, p.2.size + 1 = 2 ^ (n + 1)) := by
  refine ⟨by rw [chain_keys]; exact List.nodup_range, ?_, ?_, ?_⟩
  · have hl : ((chain n).map Prod.fst).length = (List.range (n + 1)).length := by
      rw [chain_keys n]
    simpa using hl
  · intro p hp w hw hmem
    obtain ⟨d, hd⟩ := chain_values n p hp
    rw [hd] at hw
    have hwv : w = n + 1 := mentions_bal (n + 1) _ w hw
    rw [chain_keys, List.mem_range] at hmem
    omega
  · exact ⟨(0, bal (n + 1) n), chain_head_mem n, size_bal (n + 1) n⟩

end SubstBlowup

/-! ## 5. No cyclic binding: H2 has no path through the loop -/

/-- A binding `v ↦ VarT(u)` in the environment. -/
def AliasEdge (e : Env) (v u : Nat) : Prop := (v, EnvVal.alias u) ∈ e.binds

/-- **The invariant.**  No alias points at a BOUND variable.  Equivalently: every alias chain
has length one, so the substitution needs no chasing -- which is exactly the property
`Subst.instantiateType`'s comment claims for `SubstEnv.types` ("keeps the types in the map
fully substituted in light of the new instantiation") and which `Loop/State.lean`'s `Env.lookup`
relies on. -/
def NoAliasChain (e : Env) : Prop :=
  ∀ v u : Nat, (v, EnvVal.alias u) ∈ e.binds → e.contains u = false

/-- The source of an alias edge is bound, by definition of `contains`. -/
theorem aliasEdge_source {e : Env} {v u : Nat} (h : AliasEdge e v u) : e.contains v = true :=
  Env.contains_iff.mpr ⟨(v, EnvVal.alias u), h, rfl⟩

/-- **No two alias edges compose**, which is the invariant read as a statement about paths. -/
theorem noAliasChain_no_two {e : Env} (h : NoAliasChain e) {v u w : Nat}
    (h1 : AliasEdge e v u) (h2 : AliasEdge e u w) : False := by
  have := h v u h1
  rw [aliasEdge_source h2] at this
  exact absurd this (by simp)

/-- **No cyclic binding.**  Under the invariant no variable reaches itself through any chain of
bindings -- the H2 shape, refuted for the environment the loop builds.  (`Relation.TransGen` is
"one or more edges", so this covers the self-loop `v ↦ VarT(v)` as well.) -/
theorem noAliasChain_no_cycle {e : Env} (h : NoAliasChain e) (v : Nat) :
    ¬ Relation.TransGen (AliasEdge e) v v := by
  intro hc
  obtain ⟨u, hvu, huv⟩ := Relation.TransGen.head'_iff.mp hc
  rcases Relation.ReflTransGen.cases_head huv with rfl | ⟨w, hw, -⟩
  · have hb := aliasEdge_source hvu
    have h1 := h _ _ hvu
    rw [h1] at hb
    exact absurd hb (by simp)
  · exact noAliasChain_no_two h hvu hw

/-- The initial state's environment is empty, so the invariant holds vacuously. -/
theorem noAliasChain_of_binds_nil {e : Env} (h : e.binds = []) : NoAliasChain e := by
  intro v u hv
  rw [h] at hv
  exact absurd hv (by simp)

/-- **`Env.instantiate` preserves the invariant** when the variable being bound is unbound and,
for an alias, its target is unbound and different.  The interesting case is the RANGE rewrite:
an existing `w ↦ VarT(v)` becomes `w ↦ val`, so an alias to the variable just bound is replaced
rather than left dangling -- which is the one thing `instantiateType`'s
`subType(Map(v -> e), hm.types)` is there for.  `e.contains v = false` is NOT needed: a first
version assumed it, Lean reported it unused, and the statement is stronger without it (the
callers have it anyway -- `queueHygiene_binds_unboundP`). -/
theorem noAliasChain_instantiate {e : Env} {v : Nat} {val : EnvVal}
    (h : NoAliasChain e)
    (hval : ∀ u, val = EnvVal.alias u → e.contains u = false ∧ u ≠ v) :
    NoAliasChain (e.instantiate v val) := by
  intro w z hw
  have key : e.contains z = false ∧ z ≠ v := by
    simp only [Env.instantiate, List.mem_append, List.mem_map, List.mem_singleton,
      Prod.mk.injEq] at hw
    rcases hw with ⟨b, hb, hb1, hb2⟩ | ⟨-, hval2⟩
    · cases hbv : b.2 with
      | emptyRow => rw [hbv] at hb2; exact absurd hb2 (by simp)
      | «alias» u =>
        by_cases huv : u = v
        · rw [hbv] at hb2
          simp only [huv, beq_self_eq_true, if_pos] at hb2
          exact hval z hb2
        · rw [hbv] at hb2
          simp only [beq_iff_eq, huv] at hb2
          have hzu : z = u := by simpa [EnvVal.alias.injEq] using hb2.symm
          subst hzu
          refine ⟨h b.1 z (by rw [← hbv]; simpa using hb), ?_⟩
          intro hzv
          rw [hzv] at huv
          exact huv rfl
    · first
      | exact hval z hval2
      | exact hval z hval2.symm
  cases hc : (e.instantiate v val).contains z with
  | false => rfl
  | true =>
    rcases Env.contains_instantiate.mp hc with h1 | h1
    · rw [key.1] at h1; exact absurd h1 (by simp)
    · exact absurd h1 key.2

/-- `unifyVars` either leaves the environment alone or binds an UNBOUND variable to a DIFFERENT
one.  `StrictBound.unifyVars_env` gives everything but the disequality, which is the guard
`unify` makes before it calls `instantiate` (`Constraints.scala:2122`). -/
theorem unifyVars_env_ne {ns : Names} {v u : Nat} {incm proc : PQueue} {env : Env}
    {ni np : PQueue} {e : Env} (h : unifyVars ns v u incm proc env = .ok (ni, np, e)) :
    e = env ∨ (env.contains v = false ∧ v ≠ u ∧ e = env.instantiate v (.alias u)) := by
  simp only [unifyVars] at h
  split at h
  · rw [Except.ok.injEq, Prod.mk.injEq, Prod.mk.injEq] at h
    exact Or.inl h.2.2.symm
  · rename_i hne
    obtain ⟨-, hc, he⟩ := instantiate_env_len h
    exact Or.inr ⟨hc, by simpa using hne, he⟩

/-- **The invariant is preserved by every `continue` step**, under queue hygiene.  This is a
ONE-STEP statement; the run-level reading is `runsP_noAliasChain` below, which has to carry
`stepP_queueHygiene`'s own side conditions (`disjRule = false` and the per-state supply
invariants `RunSupOkP`) -- do not read this lemma as "no cycle is reachable, full stop".  So
the loop's freedom from cyclic
bindings does NOT rest on an occurs check: `Constraints.instantiate` calls `instantiateType`
directly (`:2139`) and never reaches `unifyType`'s `occursCheckType` at all.  What it rests on
is that the three variables a step binds are unbound (`queueHygiene_binds_unboundP`), because a
bound variable has been erased from both queues. -/
theorem stepP_noAliasChain {s s' : State} (hq : QueueHygiene s) (h0 : NoAliasChain s.env)
    (h : stepP pol aux s = .continue s') : NoAliasChain s'.env := by
  simp only [stepP, State.log] at h
  split at h
  · exact absurd h (by simp)
  · rename_i r rest hdq
    obtain ⟨hlhs, habs, hcom⟩ := queueHygiene_binds_unboundP hq hdq
    split at h
    · rename_i u hu
      cases hres : unifyVars s.names r.lhs u rest s.proc s.env with
      | error m => rw [hres] at h; exact absurd h (by simp)
      | ok w =>
        obtain ⟨ni, np, e⟩ := w
        rw [hres] at h
        simp only [StepResult.continue.injEq] at h
        subst h
        rcases unifyVars_env_ne hres with rfl | ⟨-, hne, rfl⟩
        · exact h0
        · refine noAliasChain_instantiate h0 ?_
          intro z hz
          have hzu : z = u := by
            first
            | simpa [EnvVal.alias.injEq] using hz
            | simpa [EnvVal.alias.injEq] using hz.symm
          subst hzu
          exact ⟨hcom z hu, fun hzl => hne hzl.symm⟩
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          obtain ⟨-, -, rfl⟩ := makeEmpty_env_len hres
          exact noAliasChain_instantiate h0 (by intro z hz; exact absurd hz (by simp))
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            exact h0
        · split at h
          · rename_i u hu
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              rcases unifyVars_env_ne hres with rfl | ⟨-, hne, rfl⟩
              · exact h0
              · refine noAliasChain_instantiate h0 ?_
                intro z hz
                have hzu : z = r.lhs := by
                  first
                  | simpa [EnvVal.alias.injEq] using hz
                  | simpa [EnvVal.alias.injEq] using hz.symm
                subst hzu
                exact ⟨hlhs, fun hzl => hne hzl.symm⟩
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              simpa [foldl_log_env] using h0

/-- **...and along a RUN, with the side conditions named.**  The composition is not free: it
needs `QueueHygiene` at every state, and `PolicyStep.stepP_queueHygiene` itself asks for
`disjRule = false` and the supply invariants `SupOk`/`SupFresh` AT EACH STATE -- which is
exactly `PolicyStep.RunSupOkP`, the policy form of `RefineLearn.RunSupOk`.  `RunSupOkP` is
DISCHARGEABLE (`Supply.step_supFresh` / `runSupOk_of` make it a theorem for the shipped ORDER
from an input's own `SupOk`/`SupFresh`) -- but the adopted DEFAULT policy is `smallcanon`, not
the shipped order, and there is no `runSupOkP_of` for the policy form in the tree, so at the
shipped defaults this hypothesis is undischarged; it is a hypothesis here, and
`Hygiene.run_queueHygiene` carries it for the same reason.  So "no cyclic binding is reachable"
is a statement WITH these three side conditions, not without them.

At a solve's own initial state `NoAliasChain` is free (`noAliasChain_of_binds_nil`: `env = {}`
in `seedInit`, `Seed.solveSeed` and `Loop/Replay.lean`) and so is `QueueHygiene`
(`Hygiene.queueHygiene_initial`). -/
theorem runsP_noAliasChain : ∀ (n : Nat) {a c : Aux} {s t : State},
    s.flags.disjRule = false → RunSupOkP pol a n s → QueueHygiene s → NoAliasChain s.env →
    RunsP pol n a s c t → NoAliasChain t.env
  | 0, a, c, s, t, _, _, _, h0, hr => by
    simp only [RunsP] at hr
    obtain ⟨rfl, rfl⟩ := hr
    exact h0
  | n + 1, a, c, s, t, hdj, hsup, hq, h0, hr => by
    obtain ⟨u, hstep, hrest⟩ := hr
    exact runsP_noAliasChain n (by rw [stepP_flags hstep]; exact hdj) (hsup.2.2 u hstep)
      (stepP_queueHygiene hdj hsup.1 hsup.2.1 hq hstep) (stepP_noAliasChain hq h0 hstep) hrest

end Rowpartition.Loop
