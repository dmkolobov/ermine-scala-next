/-
# A mechanical counterexample hunt (placeholder docstring -- rewritten at the end)
-/
import Rowpartition.Cut

namespace Rowpartition

namespace CutSearch

/-! ## 1. Bit sets

Variable sets and concrete label sets are carried as `Nat` BITMASKS.  This is not a
modelling choice, it is a speed choice: `&&&`, `|||`, `^^^`, `<<<` and `Nat.testBit` are
GMP-accelerated inside the Lean kernel, whereas `Finset` operations reduce through
`Quotient` and `List.dedup` and are far too slow to `decide` a sweep of this size.
`varsOf` decodes a mask back to the `Finset ℕ` the rest of the development uses, and the
lemmas of this section are what let every later statement be read in terms of the real
`Constraint`s. -/

/-- The singleton mask `{z}`. -/
def bit (z : ℕ) : ℕ := 1 <<< z

/-- Bitwise set difference. -/
def sdiffM (a b : ℕ) : ℕ := a ^^^ (a &&& b)

/-- Does `m` have at least two bits set?  Clearing the lowest set bit leaves something. -/
def twoBits (m : ℕ) : Bool := (m &&& (m - 1)) != 0

/-- The finite set a mask denotes.  `Finset.range m` is a safe upper bound: a set bit `i`
forces `2 ^ i ≤ m`, and `i < 2 ^ i`. -/
def varsOf (m : ℕ) : Finset ℕ := (Finset.range m).filter (fun i => m.testBit i = true)

theorem mem_varsOf {m i : ℕ} : i ∈ varsOf m ↔ m.testBit i = true := by
  rw [varsOf, Finset.mem_filter, Finset.mem_range]
  refine ⟨And.right, fun h => ⟨?_, h⟩⟩
  have h2 : 2 ^ i ≤ m := by
    by_contra hlt
    rw [Nat.testBit_lt_two_pow (Nat.lt_of_not_le hlt)] at h
    exact Bool.noConfusion h
  exact lt_of_lt_of_le Nat.lt_two_pow_self h2

@[simp] theorem varsOf_zero : varsOf 0 = ∅ := by
  ext i; simp [mem_varsOf]

theorem varsOf_and (a b : ℕ) : varsOf (a &&& b) = varsOf a ∩ varsOf b := by
  ext i; simp [mem_varsOf, Nat.testBit_and]

theorem varsOf_or (a b : ℕ) : varsOf (a ||| b) = varsOf a ∪ varsOf b := by
  ext i; simp [mem_varsOf, Nat.testBit_or]

theorem varsOf_sdiffM (a b : ℕ) : varsOf (sdiffM a b) = varsOf a \ varsOf b := by
  ext i
  simp only [sdiffM, mem_varsOf, Nat.testBit_xor, Nat.testBit_and, Finset.mem_sdiff]
  cases a.testBit i <;> cases b.testBit i <;> simp

@[simp] theorem varsOf_bit (z : ℕ) : varsOf (bit z) = {z} := by
  ext i
  simp only [bit, mem_varsOf, Nat.one_shiftLeft, Nat.testBit_two_pow, Finset.mem_singleton,
    decide_eq_true_eq]
  exact eq_comm

theorem varsOf_eq_empty {m : ℕ} : varsOf m = ∅ ↔ m = 0 := by
  refine ⟨fun h => Nat.eq_of_testBit_eq fun i => ?_, fun h => by rw [h]; simp⟩
  rw [Nat.zero_testBit]
  by_contra hb
  have hi : i ∈ varsOf m := mem_varsOf.mpr (by simpa using hb)
  rw [h] at hi
  simp at hi

/-- `twoBits` really does witness two distinct set bits.  (Only this direction is used:
it is what turns the computable guard into the rule's real side condition
`2 ≤ (shared c₁ c₂).card`.) -/
theorem exists_two_bits {m : ℕ} (h : twoBits m = true) :
    ∃ i j, i ≠ j ∧ m.testBit i = true ∧ m.testBit j = true := by
  rw [twoBits, bne_iff_ne, ne_eq] at h
  by_contra hcon
  push Not at hcon
  have hm : m ≠ 0 := by rintro rfl; exact h (by simp)
  obtain ⟨i, hi⟩ : ∃ i, m.testBit i = true := by
    by_contra hno
    push Not at hno
    exact hm (Nat.eq_of_testBit_eq fun i => by rw [Nat.zero_testBit]; simpa using hno i)
  have hpow : m = 2 ^ i := by
    refine Nat.eq_of_testBit_eq fun j => ?_
    rw [Nat.testBit_two_pow]
    by_cases hij : i = j
    · subst hij; simpa using hi
    · have : m.testBit j ≠ true := hcon i j hij hi
      simp [hij, Bool.eq_false_iff.mpr this]
  refine h (Nat.eq_of_testBit_eq fun k => ?_)
  rw [Nat.zero_testBit, hpow, Nat.testBit_and, Nat.testBit_two_pow, Nat.testBit_two_pow_sub_one]
  by_cases hik : i = k <;> simp [hik]

/-- Conversely, at most one bit is set once clearing the lowest one empties the mask.
Strong induction on the mask: an odd mask with `m &&& (m-1) = 0` is `1`, and an even one
is twice a smaller mask with the same property. -/
theorem at_most_one_bit : ∀ m : ℕ, m &&& (m - 1) = 0 →
    ∀ i j, m.testBit i = true → m.testBit j = true → i = j := by
  intro m
  induction m using Nat.strong_induction_on with
  | _ m ih =>
    intro h i j hi hj
    rcases Nat.eq_zero_or_pos m with rfl | hm
    · simp at hi
    have hbit : ∀ k, (m.testBit k && (m - 1).testBit k) = false := by
      intro k
      have := congrArg (fun x => Nat.testBit x k) h
      simpa [Nat.testBit_and] using this
    by_cases hpar : m % 2 = 1
    · have hd : (m - 1) / 2 = m / 2 := by omega
      have hhalf : m / 2 = 0 := by
        refine Nat.eq_of_testBit_eq fun k => ?_
        rw [Nat.zero_testBit]
        have := hbit (k + 1)
        rw [Nat.testBit_succ, Nat.testBit_succ, hd] at this
        simpa using this
      have hm1 : m = 1 := by omega
      subst hm1
      have h1 : ∀ k, (1 : ℕ).testBit k = true → k = 0 := by
        intro k hk
        cases k with
        | zero => rfl
        | succ n => rw [Nat.testBit_succ] at hk; simp at hk
      rw [h1 i hi, h1 j hj]
    · have hpar0 : m % 2 = 0 := by omega
      have hd : (m - 1) / 2 = m / 2 - 1 := by omega
      have hhalf : m / 2 &&& (m / 2 - 1) = 0 := by
        refine Nat.eq_of_testBit_eq fun k => ?_
        rw [Nat.zero_testBit, Nat.testBit_and]
        have := hbit (k + 1)
        rwa [Nat.testBit_succ, Nat.testBit_succ, hd] at this
      have hlt : m / 2 < m := by omega
      have hi0 : i ≠ 0 := by
        rintro rfl
        rw [Nat.testBit_zero] at hi
        simp [hpar0] at hi
      have hj0 : j ≠ 0 := by
        rintro rfl
        rw [Nat.testBit_zero] at hj
        simp [hpar0] at hj
      obtain ⟨i', rfl⟩ : ∃ i', i = i' + 1 := ⟨i - 1, by omega⟩
      obtain ⟨j', rfl⟩ : ∃ j', j = j' + 1 := ⟨j - 1, by omega⟩
      rw [Nat.testBit_succ] at hi hj
      rw [ih (m / 2) hlt hhalf i' j' hi hj]

/-- `twoBits` is EXACTLY "at least two bits set".  Both directions are needed: the sound
direction turns the search's guard into the rule's side condition, the complete direction
turns the real refutation conditions back into the search's Boolean test. -/
theorem twoBits_iff {m : ℕ} :
    twoBits m = true ↔ ∃ i j, i ≠ j ∧ m.testBit i = true ∧ m.testBit j = true := by
  refine ⟨exists_two_bits, ?_⟩
  rintro ⟨i, j, hij, hi, hj⟩
  rw [twoBits, bne_iff_ne, ne_eq]
  exact fun h => hij (at_most_one_bit m h i j hi hj)

theorem exists_testBit {m : ℕ} (h : m ≠ 0) : ∃ i, m.testBit i = true := by
  by_contra hno
  push Not at hno
  exact h (Nat.eq_of_testBit_eq fun i => by rw [Nat.zero_testBit]; simpa using hno i)

theorem ne_zero_of_testBit {m i : ℕ} (h : m.testBit i = true) : m ≠ 0 := by
  rintro rfl
  simp at h

@[simp] theorem testBit_bit (z v : ℕ) : (bit z).testBit v = decide (z = v) := by
  rw [bit, Nat.one_shiftLeft, Nat.testBit_two_pow]

/-- Two set bits give a set of at least two elements: the rule's guard `int.size >= 2`. -/
theorem two_le_card_varsOf {m : ℕ} (h : twoBits m = true) : 2 ≤ (varsOf m).card := by
  obtain ⟨i, j, hij, hi, hj⟩ := exists_two_bits h
  exact Finset.one_lt_card.mpr ⟨i, mem_varsOf.mpr hi, j, mem_varsOf.mpr hj, hij⟩

/-! ## 2. The universe

A mini constraint is a left-hand variable, a mask of right-hand variables and a mask of
concrete labels; `toC` decodes it to a `Constraint` in `mk`-normal form and `toS` decodes
a LIST of them (repeats allowed -- they collapse) to a `System`. -/

/-- How many labels the search universe has: a concrete part is a subset of
`{0, ..., nlabs - 1}`. -/
def nlabs : ℕ := 2

/-- A constraint of the search universe. -/
structure MC where
  /-- the left-hand variable -/
  lhs : ℕ
  /-- the right-hand variable set, as a bitmask -/
  vs : ℕ
  /-- the concrete part, as a bitmask of labels -/
  cs : ℕ
deriving DecidableEq, Repr, Inhabited

/-- Decoding one mini constraint. -/
def toC (c : MC) : Constraint := mk c.lhs (varsOf c.vs) (varsOf c.cs)

@[simp] theorem lhs_toC (c : MC) : (toC c).lhs = c.lhs := rfl
@[simp] theorem vset_toC (c : MC) : vset (toC c) = varsOf c.vs := vset_mk _ _ _
@[simp] theorem conc_toC (c : MC) : (toC c).conc = varsOf c.cs := rfl

/-- Decoding a mini system. -/
def toS (L : List MC) : System := (L.map toC).toFinset

@[simp] theorem toS_nil : toS [] = ∅ := rfl

@[simp] theorem toS_cons (c : MC) (L : List MC) : toS (c :: L) = insert (toC c) (toS L) := by
  simp [toS]

theorem mem_toS {c : MC} {L : List MC} (h : c ∈ L) : toC c ∈ toS L :=
  List.mem_toFinset.mpr (List.mem_map_of_mem h)

theorem toS_mono {L L' : List MC} (h : L ⊆ L') : toS L ⊆ toS L' := by
  intro c hc
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hc)
  exact mem_toS (h hd)

theorem toS_append (L L' : List MC) : toS (L ++ L') = toS L ∪ toS L' := by
  simp [toS, List.toFinset_append]

/-- The bookkeeping invariant: every VARIABLE a mini system mentions is `< n` and every
LABEL is `< nlabs`.  The variable half is what makes the counter's current value a
genuinely fresh name; the label half is what makes the refuters' fixed label list
exhaustive.  No branch of the rule ever invents a label, so both halves survive
saturation. -/
def Below (n : ℕ) (L : List MC) : Prop :=
  ∀ c ∈ L, c.lhs < n ∧ varsOf c.vs ⊆ Finset.range n ∧ varsOf c.cs ⊆ Finset.range nlabs

theorem Below.mono {m n : ℕ} {L : List MC} (h : Below m L) (hmn : m ≤ n) : Below n L :=
  fun c hc => ⟨lt_of_lt_of_le (h c hc).1 hmn, (h c hc).2.1.trans (Finset.range_mono hmn),
    (h c hc).2.2⟩

theorem Below.sublist {n : ℕ} {L L' : List MC} (h : Below n L') (hsub : L ⊆ L') : Below n L :=
  fun c hc => h c (hsub hc)

theorem Below.cons {n : ℕ} {c : MC} {L : List MC} (hc : c.lhs < n)
    (hv : varsOf c.vs ⊆ Finset.range n) (hl : varsOf c.cs ⊆ Finset.range nlabs)
    (h : Below n L) : Below n (c :: L) := by
  intro d hd
  rcases List.mem_cons.mp hd with rfl | hd'
  · exact ⟨hc, hv, hl⟩
  · exact h d hd'

theorem Below.append {n : ℕ} {L L' : List MC} (h : Below n L) (h' : Below n L') :
    Below n (L ++ L') := by
  intro c hc
  rcases List.mem_append.mp hc with h1 | h1
  · exact h c h1
  · exact h' c h1

/-- `Below` bounds the decoded system's vocabulary. -/
theorem Below.vocab {n : ℕ} {L : List MC} (h : Below n L) :
    allVars (toS L) ⊆ Finset.range n := by
  intro v hv
  obtain ⟨c, hc, hv'⟩ := Finset.mem_biUnion.mp hv
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp (List.mem_toFinset.mp hc)
  rcases Finset.mem_insert.mp hv' with rfl | hv''
  · exact Finset.mem_range.mpr (h d hd).1
  · exact (h d hd).2.1 (by simpa using hv'')

/-- The counter's value is fresh for the system built so far. -/
theorem Below.fresh {n : ℕ} {L : List MC} (h : Below n L) {z : ℕ} (hz : n ≤ z) :
    z ∉ allVars (toS L) := fun hmem => by
  have := Finset.mem_range.mp (h.vocab hmem)
  omega

/-! ## 3. The rule of `commonSubexpression`, computably

`cutClose` and `fullClose` below are THE SAME CODE with one Boolean flipped: `fullClose`
takes the minting branch when the shared block has no name yet, `cutClose` takes nothing.
Everything else -- the guard, the reuse conclusions, the order the pairs are visited, the
number of rounds -- is shared, so any difference between the two is exactly the cut. -/

/-- The shared block of two constraints: `int = abstr1 ∩ abstr2`. -/
def sharedM (a b : MC) : ℕ := a.vs &&& b.vs

/-- The rule's guard: different left-hand sides and `int.size >= 2`. -/
def firesPair (a b : MC) : Bool := (a.lhs != b.lhs) && twoBits (sharedM a b)

/-- `c` with its shared block replaced by the single variable `z`. -/
def reduceM (c : MC) (S z : ℕ) : MC := ⟨c.lhs, sdiffM c.vs S ||| bit z, c.cs⟩

@[simp] theorem reduceM_lhs (c : MC) (S z : ℕ) : (reduceM c S z).lhs = c.lhs := rfl

@[simp] theorem reduceM_cs (c : MC) (S z : ℕ) : (reduceM c S z).cs = c.cs := rfl

/-- Every name `L` gives to `S`: the Scala reverse lookup `rhss(RHSAbstr(int))`, which
here searches the whole accumulated system. -/
def namesOf (L : List MC) (S : ℕ) : List ℕ :=
  (L.filter (fun d => d.vs == S && d.cs == 0)).map (·.lhs)

/-- All unordered pairs of a list. -/
def pairsOf : List MC → List (MC × MC)
  | [] => []
  | c :: t => t.map (fun d => (c, d)) ++ pairsOf t

theorem mem_pairsOf : ∀ {L : List MC} {p : MC × MC}, p ∈ pairsOf L → p.1 ∈ L ∧ p.2 ∈ L := by
  intro L
  induction L with
  | nil => intro p hp; cases hp
  | cons c t ih =>
    intro p hp
    rcases List.mem_append.mp hp with h | h
    · obtain ⟨d, hd, rfl⟩ := List.mem_map.mp h
      exact ⟨List.mem_cons_self, List.mem_cons_of_mem _ hd⟩
    · exact ⟨List.mem_cons_of_mem _ (ih h).1, List.mem_cons_of_mem _ (ih h).2⟩

/-- One rule application, on one pair, against the accumulated system.  `mint = true` is
the shipped solver, `mint = false` the cut.  The pair `(system, next fresh name)` is
threaded so that every minted name is fresh for everything derived so far. -/
def stepPair (mint : Bool) (acc : List MC × ℕ) (p : MC × MC) : List MC × ℕ :=
  if firesPair p.1 p.2 then
    let S := sharedM p.1 p.2
    let ns := namesOf acc.1 S
    if mint && ns.isEmpty then
      (⟨acc.2, S, 0⟩ :: reduceM p.1 S acc.2 :: reduceM p.2 S acc.2 :: acc.1, acc.2 + 1)
    else (ns.flatMap (fun z => [reduceM p.1 S z, reduceM p.2 S z]) ++ acc.1, acc.2)
  else acc

/-- One round: every pair of the round's input, against the growing accumulator. -/
def round (mint : Bool) (st : List MC × ℕ) : List MC × ℕ :=
  (pairsOf st.1).foldl (stepPair mint) st

/-- Fuel-bounded saturation. -/
def close (mint : Bool) : ℕ → List MC × ℕ → List MC × ℕ
  | 0, st => st
  | n + 1, st => close mint n (round mint st)

/-- Minted names start here.  Every system the search enumerates uses variables `< 8`,
so the counter is fresh from its first value on. -/
def nbase : ℕ := 8

/-- The cut solver's fuel-bounded saturation: branches (a) and (b) only. -/
def cutClose (f : ℕ) (G : List MC) : List MC := (close false f (G, nbase)).1

/-- The shipped solver's fuel-bounded saturation: (a), (b) and (c). -/
def fullClose (f : ℕ) (G : List MC) : List MC := (close true f (G, nbase)).1

/-! ## 4. Every step the search takes is a step of the real rule

This section is what makes the sweep a statement about `Cut.CutStep` and `Cut.CseBranch`
rather than about a private transcription of them: `cutClose_run` and `fullClose_run` say
that the two saturations are *runs of the real relations* on the decoded system. -/

theorem shared_toC (a b : MC) : shared (toC a) (toC b) = varsOf (sharedM a b) := by
  rw [shared, vset_toC, vset_toC, sharedM, varsOf_and]

theorem toC_reduceM (c : MC) (S z : ℕ) : toC (reduceM c S z) = reduce (toC c) (varsOf S) z := by
  rw [reduce, toC, reduceM, vset_toC, conc_toC, lhs_toC, varsOf_or, varsOf_sdiffM, varsOf_bit,
    Finset.union_comm, ← Finset.insert_eq]

theorem mem_namesOf {L : List MC} {S z : ℕ} (h : z ∈ namesOf L S) :
    ∃ d ∈ L, d.lhs = z ∧ d.vs = S ∧ d.cs = 0 := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp h
  obtain ⟨hd', hfilt⟩ := List.mem_filter.mp hd
  simp only [Bool.and_eq_true, beq_iff_eq] at hfilt
  exact ⟨d, hd', rfl, hfilt.1, hfilt.2⟩

theorem names_toS {L : List MC} {S z : ℕ} (h : z ∈ namesOf L S) :
    Names (toS L) z (varsOf S) := by
  obtain ⟨d, hd, rfl, hvs, hcs⟩ := mem_namesOf h
  exact ⟨toC d, mem_toS hd, rfl, by rw [vset_toC, hvs], by rw [conc_toC, hcs, varsOf_zero]⟩

theorem names_mono {G G' : System} (hsub : G ⊆ G') {z : ℕ} {S : Finset ℕ} (h : Names G z S) :
    Names G' z S := by
  obtain ⟨d, hd, h1, h2, h3⟩ := h
  exact ⟨d, hsub hd, h1, h2, h3⟩

theorem csePair_toS {L : List MC} {a b : MC} (ha : a ∈ L) (hb : b ∈ L)
    (hf : firesPair a b = true) : CsePair (toS L) (toC a) (toC b) := by
  rw [firesPair, Bool.and_eq_true, bne_iff_ne] at hf
  exact ⟨mem_toS ha, mem_toS hb, hf.1, by rw [shared_toC]; exact two_le_card_varsOf hf.2⟩

theorem cutSteps_trans : ∀ {k' : ℕ} {G' G'' : System}, CutSteps k' G' G'' →
    ∀ {k : ℕ} {G : System}, CutSteps k G G' → CutSteps (k + k') G G'' := by
  intro k' G' G'' h'
  induction h' with
  | refl _ => intro k G hk; exact hk
  | tail _ hstep ih => intro k G hk; exact CutSteps.tail (ih hk) hstep

theorem branchSteps_trans : ∀ {k' : ℕ} {G' G'' : System}, BranchSteps k' G' G'' →
    ∀ {k : ℕ} {G : System}, BranchSteps k G G' → BranchSteps (k + k') G G'' := by
  intro k' G' G'' h'
  induction h' with
  | refl _ => intro k G hk; exact hk
  | tail _ hstep ih => intro k G hk; exact BranchSteps.tail (ih hk) hstep

/-- The reuse conclusions for one pair, over every name the accumulator offers, are a
chain of `CutStep`s -- one `CutStep.reuse` per name. -/
theorem cutSteps_reuse {L : List MC} {a b : MC} (ha : a ∈ L) (hb : b ∈ L)
    (hf : firesPair a b = true) :
    ∀ ns : List ℕ, (∀ z ∈ ns, z ∈ namesOf L (sharedM a b)) →
      ∃ k, CutSteps k (toS L)
        (toS (ns.flatMap (fun z => [reduceM a (sharedM a b) z, reduceM b (sharedM a b) z]) ++ L)) := by
  intro ns
  induction ns with
  | nil => intro _; exact ⟨0, CutSteps.refl _⟩
  | cons z t ih =>
    intro hns
    obtain ⟨k, hk⟩ := ih fun w hw => hns w (List.mem_cons_of_mem _ hw)
    set M := t.flatMap (fun z => [reduceM a (sharedM a b) z, reduceM b (sharedM a b) z]) ++ L
      with hM
    have hLM : L ⊆ M := fun c hc => List.mem_append_right _ hc
    have hstep : CutStep (toS M)
        (toS (reduceM a (sharedM a b) z :: reduceM b (sharedM a b) z :: M)) := by
      have hp : CsePair (toS M) (toC a) (toC b) := csePair_toS (hLM ha) (hLM hb) hf
      have hn : Names (toS M) z (shared (toC a) (toC b)) := by
        rw [shared_toC]
        exact names_mono (toS_mono hLM) (names_toS (hns z List.mem_cons_self))
      have := CutStep.reuse hp hn
      rwa [reuseResult, shared_toC, ← toC_reduceM, ← toC_reduceM, ← toS_cons, ← toS_cons] at this
    exact ⟨k + 1, CutSteps.tail hk hstep⟩

/-- The minting branch on one pair is one `CseBranch.mint` step; the counter's value is
fresh because of `Below`. -/
theorem branchStep_mint {L : List MC} {a b : MC} (ha : a ∈ L) (hb : b ∈ L)
    (hf : firesPair a b = true) {n : ℕ} (hB : Below n L) :
    CseBranch (toS L)
      (toS (⟨n, sharedM a b, 0⟩ :: reduceM a (sharedM a b) n :: reduceM b (sharedM a b) n :: L)) := by
  have happ : CseApp (toS L) (toC a) (toC b) n :=
    (csePair_toS ha hb hf).toApp (hB.fresh le_rfl)
  have := CseBranch.mint happ
  rwa [cseResult, shared_toC, ← toC_reduceM, ← toC_reduceM, show mk n (varsOf (sharedM a b)) ∅
    = toC ⟨n, sharedM a b, 0⟩ from by rw [toC, varsOf_zero], ← toS_cons, ← toS_cons,
    ← toS_cons] at this

/-! ### From one pair to a whole run -/

theorem stepPair_eq_false (acc : List MC × ℕ) (p : MC × MC) :
    stepPair false acc p =
      if firesPair p.1 p.2 then
        ((namesOf acc.1 (sharedM p.1 p.2)).flatMap
          (fun z => [reduceM p.1 (sharedM p.1 p.2) z, reduceM p.2 (sharedM p.1 p.2) z]) ++ acc.1,
          acc.2)
      else acc := by
  simp [stepPair]

theorem stepPair_eq_true (acc : List MC × ℕ) (p : MC × MC) :
    stepPair true acc p =
      if firesPair p.1 p.2 then
        (if (namesOf acc.1 (sharedM p.1 p.2)).isEmpty then
          (⟨acc.2, sharedM p.1 p.2, 0⟩ :: reduceM p.1 (sharedM p.1 p.2) acc.2 ::
            reduceM p.2 (sharedM p.1 p.2) acc.2 :: acc.1, acc.2 + 1)
         else
          ((namesOf acc.1 (sharedM p.1 p.2)).flatMap
            (fun z => [reduceM p.1 (sharedM p.1 p.2) z, reduceM p.2 (sharedM p.1 p.2) z]) ++ acc.1,
            acc.2))
      else acc := by
  simp [stepPair]

theorem stepPair_sub (mint : Bool) (acc : List MC × ℕ) (p : MC × MC) :
    acc.1 ⊆ (stepPair mint acc p).1 := by
  intro c hc
  cases mint
  · rw [stepPair_eq_false]
    split
    · exact List.mem_append_right _ hc
    · exact hc
  · rw [stepPair_eq_true]
    split
    · split
      · exact List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_cons_of_mem _ hc))
      · exact List.mem_append_right _ hc
    · exact hc

theorem stepPair_cnt (mint : Bool) (acc : List MC × ℕ) (p : MC × MC) :
    acc.2 ≤ (stepPair mint acc p).2 := by
  cases mint
  · rw [stepPair_eq_false]; split <;> simp
  · rw [stepPair_eq_true]
    split
    · split <;> simp
    · simp

theorem varsOf_reduceM_subset {c : MC} {S z n : ℕ} (hc : varsOf c.vs ⊆ Finset.range n)
    (hz : z < n) : varsOf (reduceM c S z).vs ⊆ Finset.range n := by
  intro v hv
  simp only [reduceM, varsOf_or, varsOf_sdiffM, varsOf_bit, Finset.mem_union, Finset.mem_sdiff,
    Finset.mem_singleton] at hv
  rcases hv with ⟨h1, -⟩ | rfl
  · exact hc h1
  · exact Finset.mem_range.mpr hz

/-- The reuse conclusions stay inside the current vocabulary: the kept branches are
non-generative (`Cut.CutStep.allVars_eq`), and here that is a computation. -/
theorem below_flatMap {acc : List MC × ℕ} {p : MC × MC} (hb : Below acc.2 acc.1)
    (h1 : p.1 ∈ acc.1) (h2 : p.2 ∈ acc.1) :
    Below acc.2 ((namesOf acc.1 (sharedM p.1 p.2)).flatMap
      (fun z => [reduceM p.1 (sharedM p.1 p.2) z, reduceM p.2 (sharedM p.1 p.2) z])) := by
  intro c hc
  obtain ⟨z, hz, hc'⟩ := List.mem_flatMap.mp hc
  obtain ⟨d, hd, rfl, -, -⟩ := mem_namesOf hz
  have hdlt : d.lhs < acc.2 := (hb d hd).1
  rcases List.mem_cons.mp hc' with rfl | hc''
  · exact ⟨(hb p.1 h1).1, varsOf_reduceM_subset (hb p.1 h1).2.1 hdlt, (hb p.1 h1).2.2⟩
  · rcases List.mem_cons.mp hc'' with rfl | hc'''
    · exact ⟨(hb p.2 h2).1, varsOf_reduceM_subset (hb p.2 h2).2.1 hdlt, (hb p.2 h2).2.2⟩
    · cases hc'''

theorem stepPair_below (mint : Bool) {acc : List MC × ℕ} {p : MC × MC} (hb : Below acc.2 acc.1)
    (h1 : p.1 ∈ acc.1) (h2 : p.2 ∈ acc.1) :
    Below (stepPair mint acc p).2 (stepPair mint acc p).1 := by
  have hshared : varsOf (sharedM p.1 p.2) ⊆ Finset.range acc.2 := by
    rw [sharedM, varsOf_and]
    exact Finset.inter_subset_left.trans (hb p.1 h1).2.1
  cases mint
  · rw [stepPair_eq_false]
    split
    · exact (below_flatMap hb h1 h2).append hb
    · exact hb
  · rw [stepPair_eq_true]
    split
    · split
      · refine Below.cons (Nat.lt_succ_self acc.2)
          (hshared.trans (Finset.range_mono (Nat.le_succ _))) (by simp) ?_
        refine Below.cons (Nat.lt_succ_of_lt (hb p.1 h1).1)
          (varsOf_reduceM_subset ((hb p.1 h1).2.1.trans (Finset.range_mono (Nat.le_succ _)))
            (Nat.lt_succ_self _)) (hb p.1 h1).2.2 ?_
        refine Below.cons (Nat.lt_succ_of_lt (hb p.2 h2).1)
          (varsOf_reduceM_subset ((hb p.2 h2).2.1.trans (Finset.range_mono (Nat.le_succ _)))
            (Nat.lt_succ_self _)) (hb p.2 h2).2.2 ?_
        exact hb.mono (Nat.le_succ _)
      · exact (below_flatMap hb h1 h2).append hb
    · exact hb

theorem cutSteps_stepPair {acc : List MC × ℕ} {p : MC × MC} (h1 : p.1 ∈ acc.1)
    (h2 : p.2 ∈ acc.1) : ∃ k, CutSteps k (toS acc.1) (toS (stepPair false acc p).1) := by
  rw [stepPair_eq_false]
  split
  · rename_i hf
    exact cutSteps_reuse h1 h2 hf _ (fun z hz => hz)
  · exact ⟨0, CutSteps.refl _⟩

theorem branchSteps_stepPair (mint : Bool) {acc : List MC × ℕ} {p : MC × MC} (h1 : p.1 ∈ acc.1)
    (h2 : p.2 ∈ acc.1) (hb : Below acc.2 acc.1) :
    ∃ k, BranchSteps k (toS acc.1) (toS (stepPair mint acc p).1) := by
  cases mint
  · obtain ⟨k, hk⟩ := cutSteps_stepPair h1 h2
    exact ⟨k, hk.toBranchSteps⟩
  · rw [stepPair_eq_true]
    split
    · rename_i hf
      split
      · exact ⟨1, BranchSteps.tail (BranchSteps.refl _) (branchStep_mint h1 h2 hf hb)⟩
      · obtain ⟨k, hk⟩ := cutSteps_reuse h1 h2 hf _ (fun z hz => hz)
        exact ⟨k, hk.toBranchSteps⟩
    · exact ⟨0, BranchSteps.refl _⟩

theorem cut_fold {L : List MC} : ∀ ps : List (MC × MC), (∀ p ∈ ps, p.1 ∈ L ∧ p.2 ∈ L) →
    ∀ acc : List MC × ℕ, L ⊆ acc.1 → Below acc.2 acc.1 →
      (∃ k, CutSteps k (toS L) (toS acc.1)) →
      L ⊆ (ps.foldl (stepPair false) acc).1 ∧
        Below (ps.foldl (stepPair false) acc).2 (ps.foldl (stepPair false) acc).1 ∧
        ∃ k, CutSteps k (toS L) (toS (ps.foldl (stepPair false) acc).1) := by
  intro ps
  induction ps with
  | nil => intro _ acc h1 h2 h3; exact ⟨h1, h2, h3⟩
  | cons p t ih =>
    intro hps acc hsub hbel hst
    have hp := hps p List.mem_cons_self
    have h1 : p.1 ∈ acc.1 := hsub hp.1
    have h2 : p.2 ∈ acc.1 := hsub hp.2
    obtain ⟨k, hk⟩ := hst
    obtain ⟨k', hk'⟩ := cutSteps_stepPair h1 h2
    exact ih (fun q hq => hps q (List.mem_cons_of_mem _ hq)) _
      (fun c hc => stepPair_sub false acc p (hsub hc)) (stepPair_below false hbel h1 h2)
      ⟨k + k', cutSteps_trans hk' hk⟩

theorem full_fold {L : List MC} : ∀ ps : List (MC × MC), (∀ p ∈ ps, p.1 ∈ L ∧ p.2 ∈ L) →
    ∀ acc : List MC × ℕ, L ⊆ acc.1 → Below acc.2 acc.1 →
      (∃ k, BranchSteps k (toS L) (toS acc.1)) →
      L ⊆ (ps.foldl (stepPair true) acc).1 ∧
        Below (ps.foldl (stepPair true) acc).2 (ps.foldl (stepPair true) acc).1 ∧
        ∃ k, BranchSteps k (toS L) (toS (ps.foldl (stepPair true) acc).1) := by
  intro ps
  induction ps with
  | nil => intro _ acc h1 h2 h3; exact ⟨h1, h2, h3⟩
  | cons p t ih =>
    intro hps acc hsub hbel hst
    have hp := hps p List.mem_cons_self
    have h1 : p.1 ∈ acc.1 := hsub hp.1
    have h2 : p.2 ∈ acc.1 := hsub hp.2
    obtain ⟨k, hk⟩ := hst
    obtain ⟨k', hk'⟩ := branchSteps_stepPair true h1 h2 hbel
    exact ih (fun q hq => hps q (List.mem_cons_of_mem _ hq)) _
      (fun c hc => stepPair_sub true acc p (hsub hc)) (stepPair_below true hbel h1 h2)
      ⟨k + k', branchSteps_trans hk' hk⟩

theorem cut_close : ∀ (f : ℕ) (st : List MC × ℕ), Below st.2 st.1 →
    Below (close false f st).2 (close false f st).1 ∧
      ∃ k, CutSteps k (toS st.1) (toS (close false f st).1) := by
  intro f
  induction f with
  | zero => intro st h; exact ⟨h, 0, CutSteps.refl _⟩
  | succ n ih =>
    intro st h
    obtain ⟨-, hb, k, hk⟩ := cut_fold (L := st.1) (pairsOf st.1) (fun p hp => mem_pairsOf hp)
      st (fun c hc => hc) h ⟨0, CutSteps.refl _⟩
    obtain ⟨hb2, k2, hk2⟩ := ih (round false st) hb
    exact ⟨hb2, k + k2, cutSteps_trans hk2 hk⟩

theorem full_close : ∀ (f : ℕ) (st : List MC × ℕ), Below st.2 st.1 →
    Below (close true f st).2 (close true f st).1 ∧
      ∃ k, BranchSteps k (toS st.1) (toS (close true f st).1) := by
  intro f
  induction f with
  | zero => intro st h; exact ⟨h, 0, BranchSteps.refl _⟩
  | succ n ih =>
    intro st h
    obtain ⟨-, hb, k, hk⟩ := full_fold (L := st.1) (pairsOf st.1) (fun p hp => mem_pairsOf hp)
      st (fun c hc => hc) h ⟨0, BranchSteps.refl _⟩
    obtain ⟨hb2, k2, hk2⟩ := ih (round true st) hb
    exact ⟨hb2, k + k2, branchSteps_trans hk2 hk⟩

/-- **The cut saturation is a real cut run.**  Whatever `cutClose` computes is reachable
from the input by `CutStep`s -- branches (a) and (b) of `commonSubexpression` only. -/
theorem cutClose_run (f : ℕ) (L : List MC) (h : Below nbase L) :
    ∃ k, CutSteps k (toS L) (toS (cutClose f L)) := (cut_close f (L, nbase) h).2

/-- **The full saturation is a real solver run.**  Whatever `fullClose` computes is
reachable from the input by `CseBranch` steps -- all three branches. -/
theorem fullClose_run (f : ℕ) (L : List MC) (h : Below nbase L) :
    ∃ k, BranchSteps k (toS L) (toS (fullClose f L)) := (full_close f (L, nbase) h).2

/-! ## 5. Ermine-shaped refuters

Three of Ermine's five error conditions are about CONCRETE labels, and all three are
`Cut.Refuter`s: sound (they fire only on genuinely unsatisfiable systems) and monotone
(deriving more constraints can only make them fire more).  Each comes with a computable
transcription and an `iff` linking the two, so the sweep below is a statement about these
conditions and not about a private Boolean function. -/

/-- **Error condition 10 after propagation: a duplicated field.**  Two DISTINCT parts of
one partition are both forced to contain the same label -- either two variable parts
whose own partitions pin the label, or the concrete part and a variable part.  (In the
flattened one-block `Constraint` a literally repeated concrete block is invisible;
`Rules.rule10` needs `RawConstraint` for that.  This is the form the condition takes once
the field has been propagated to two disjoint places, which is how the solver meets it.) -/
def RDup (G : System) : Prop :=
  ∃ c ∈ G, ∃ l : Label,
    (∃ d ∈ G, ∃ e ∈ G, d.lhs ∈ vset c ∧ e.lhs ∈ vset c ∧ d.lhs ≠ e.lhs ∧
        l ∈ d.conc ∧ l ∈ e.conc) ∨
      (l ∈ c.conc ∧ ∃ d ∈ G, d.lhs ∈ vset c ∧ l ∈ d.conc)

theorem rDup_sound (G : System) (h : RDup G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, l, hcase⟩ := h
  rcases hcase with ⟨d, hd, e, he, hdv, hev, hne, hdl, hel⟩ | ⟨hcl, d, hd, hdv, hdl⟩
  · have h1 : l ∈ rho d.lhs := (hm d hd).conc_subset_lhs hdl
    have h2 : l ∈ rho e.lhs := (hm e he).conc_subset_lhs hel
    exact Finset.disjoint_left.mp ((hm c hc).disjoint_of_ne' hdv hev hne) h1 h2
  · have h1 : l ∈ rho d.lhs := (hm d hd).conc_subset_lhs hdl
    exact Finset.disjoint_left.mp ((hm c hc).disjoint_conc' hdv) hcl h1

theorem rDup_mono (G G' : System) (hsub : G ⊆ G') (h : RDup G) : RDup G' := by
  obtain ⟨c, hc, l, hcase⟩ := h
  refine ⟨c, hsub hc, l, ?_⟩
  rcases hcase with ⟨d, hd, e, he, h1, h2, h3, h4, h5⟩ | ⟨h1, d, hd, h2, h3⟩
  · exact Or.inl ⟨d, hsub hd, e, hsub he, h1, h2, h3, h4, h5⟩
  · exact Or.inr ⟨h1, d, hsub hd, h2, h3⟩

/-- Ermine's duplicated-field condition, packaged. -/
def refuterDup : Refuter := ⟨RDup, rDup_sound, rDup_mono⟩

/-- **Error condition 1: an infinite row.**  `a <- C+ a b*` with a nonempty concrete
part has no model at all (`Rules.rule1_unsat`). -/
def RInf (G : System) : Prop := ∃ c ∈ G, c.lhs ∈ vset c ∧ c.conc ≠ ∅

theorem rInf_sound (G : System) (h : RInf G) : ¬ ∃ rho, SModels rho G := by
  rintro ⟨rho, hm⟩
  obtain ⟨c, hc, hmem, hne⟩ := h
  exact hne (rule1_general (hm c hc) (List.mem_toFinset.mp hmem)).1

theorem rInf_mono (G G' : System) (hsub : G ⊆ G') (h : RInf G) : RInf G' := by
  obtain ⟨c, hc, h1, h2⟩ := h
  exact ⟨c, hsub hc, h1, h2⟩

/-- Ermine's infinite-row condition, packaged. -/
def refuterInf : Refuter := ⟨RInf, rInf_sound, rInf_mono⟩

/-! ### The computable transcriptions -/

/-- The labels of the universe. -/
def labList : List ℕ := List.range nlabs

/-- The variables whose own partitions pin the label `l`: `carriers L l` has the bit `v`
set exactly when some `v <- (..., K)` of `L` has `l ∈ K`. -/
def carriers (L : List MC) (l : ℕ) : ℕ :=
  L.foldr (fun d m => if d.cs.testBit l then m ||| bit d.lhs else m) 0

theorem testBit_carriers {L : List MC} {l v : ℕ} :
    (carriers L l).testBit v = true ↔ ∃ d ∈ L, d.lhs = v ∧ d.cs.testBit l = true := by
  induction L with
  | nil => simp [carriers]
  | cons c t ih =>
    simp only [carriers, List.foldr_cons] at ih ⊢
    by_cases hc : c.cs.testBit l = true
    · rw [if_pos hc, Nat.testBit_or, Bool.or_eq_true, ih, testBit_bit]
      constructor
      · rintro (⟨d, hd, h1, h2⟩ | h)
        · exact ⟨d, List.mem_cons_of_mem _ hd, h1, h2⟩
        · exact ⟨c, List.mem_cons_self, by simpa using h, hc⟩
      · rintro ⟨d, hd, h1, h2⟩
        rcases List.mem_cons.mp hd with rfl | hd'
        · exact Or.inr (by simp [h1])
        · exact Or.inl ⟨d, hd', h1, h2⟩
    · rw [if_neg hc, ih]
      constructor
      · rintro ⟨d, hd, h1, h2⟩; exact ⟨d, List.mem_cons_of_mem _ hd, h1, h2⟩
      · rintro ⟨d, hd, h1, h2⟩
        rcases List.mem_cons.mp hd with rfl | hd'
        · exact absurd h2 hc
        · exact ⟨d, hd', h1, h2⟩

/-- The duplicated-field test. -/
def firesDup (L : List MC) : Bool :=
  labList.any fun l =>
    let S := carriers L l
    L.any fun c => twoBits (c.vs &&& S) || (c.cs.testBit l && (c.vs &&& S != 0))

/-- The incompatible-instantiation test (Ermine error condition 11, `Cut.Fires11`). -/
def fires11 (L : List MC) : Bool :=
  L.any fun c => c.vs == 0 && L.any fun d => d.lhs == c.lhs && (sdiffM d.cs c.cs != 0)

/-- The infinite-row test. -/
def firesInf (L : List MC) : Bool := L.any fun c => c.vs.testBit c.lhs && (c.cs != 0)

theorem mem_toS_iff {c : Constraint} {L : List MC} : c ∈ toS L ↔ ∃ d ∈ L, toC d = c := by
  simp [toS]

theorem firesInf_iff (L : List MC) : firesInf L = true ↔ RInf (toS L) := by
  constructor
  · intro h
    obtain ⟨c, hc, h1⟩ := List.any_eq_true.mp h
    rw [Bool.and_eq_true, bne_iff_ne] at h1
    exact ⟨toC c, mem_toS hc, by rw [vset_toC]; exact mem_varsOf.mpr h1.1,
      by rw [conc_toC]; exact fun hz => h1.2 (varsOf_eq_empty.mp hz)⟩
  · rintro ⟨c, hc, h1, h2⟩
    obtain ⟨d, hd, rfl⟩ := mem_toS_iff.mp hc
    refine List.any_eq_true.mpr ⟨d, hd, ?_⟩
    rw [Bool.and_eq_true, bne_iff_ne]
    refine ⟨mem_varsOf.mp (by simpa using h1), fun hz => h2 ?_⟩
    rw [conc_toC, hz, varsOf_zero]

theorem fires11_iff (L : List MC) : fires11 L = true ↔ Fires11 (toS L) := by
  constructor
  · intro h
    obtain ⟨c, hc, h1⟩ := List.any_eq_true.mp h
    rw [Bool.and_eq_true, beq_iff_eq] at h1
    obtain ⟨d, hd, h2⟩ := List.any_eq_true.mp h1.2
    rw [Bool.and_eq_true, beq_iff_eq, bne_iff_ne] at h2
    refine ⟨toC c, mem_toS hc, toC d, mem_toS hd, by simpa using h2.1.symm,
      by rw [vset_toC, h1.1, varsOf_zero], ?_⟩
    rw [conc_toC, conc_toC]
    intro hsub
    have he : varsOf (sdiffM d.cs c.cs) = ∅ := by
      rw [varsOf_sdiffM]
      exact Finset.sdiff_eq_empty_iff_subset.mpr hsub
    exact h2.2 (varsOf_eq_empty.mp he)
  · rintro ⟨c, hc, d, hd, h1, h2, h3⟩
    obtain ⟨c', hc', rfl⟩ := mem_toS_iff.mp hc
    obtain ⟨d', hd', rfl⟩ := mem_toS_iff.mp hd
    refine List.any_eq_true.mpr ⟨c', hc', ?_⟩
    rw [Bool.and_eq_true, beq_iff_eq]
    refine ⟨varsOf_eq_empty.mp (by simpa using h2), List.any_eq_true.mpr ⟨d', hd', ?_⟩⟩
    rw [Bool.and_eq_true, beq_iff_eq, bne_iff_ne]
    refine ⟨by simpa using h1.symm, fun hz => h3 ?_⟩
    have := varsOf_sdiffM d'.cs c'.cs
    rw [hz, varsOf_zero] at this
    rw [conc_toC, conc_toC, ← Finset.sdiff_eq_empty_iff_subset]
    exact this.symm

theorem firesDup_sound {L : List MC} (h : firesDup L = true) : RDup (toS L) := by
  simp only [firesDup, List.any_eq_true] at h
  obtain ⟨l, -, c, hc, h2⟩ := h
  rw [Bool.or_eq_true] at h2
  rcases h2 with h2 | h2
  · obtain ⟨i, j, hij, hi, hj⟩ := exists_two_bits h2
    rw [Nat.testBit_and, Bool.and_eq_true] at hi hj
    obtain ⟨d, hd, rfl, hd2⟩ := testBit_carriers.mp hi.2
    obtain ⟨e, he, rfl, he2⟩ := testBit_carriers.mp hj.2
    exact ⟨toC c, mem_toS hc, l, Or.inl ⟨toC d, mem_toS hd, toC e, mem_toS he,
      by simpa using mem_varsOf.mpr hi.1, by simpa using mem_varsOf.mpr hj.1,
      by simpa using hij, by simpa using mem_varsOf.mpr hd2,
      by simpa using mem_varsOf.mpr he2⟩⟩
  · rw [Bool.and_eq_true, bne_iff_ne] at h2
    obtain ⟨i, hi⟩ := exists_testBit h2.2
    rw [Nat.testBit_and, Bool.and_eq_true] at hi
    obtain ⟨d, hd, rfl, hd2⟩ := testBit_carriers.mp hi.2
    exact ⟨toC c, mem_toS hc, l, Or.inr ⟨by simpa using mem_varsOf.mpr h2.1,
      toC d, mem_toS hd, by simpa using mem_varsOf.mpr hi.1,
      by simpa using mem_varsOf.mpr hd2⟩⟩

theorem firesDup_complete {n : ℕ} {L : List MC} (hb : Below n L) (h : RDup (toS L)) :
    firesDup L = true := by
  obtain ⟨c, hc, l, hcase⟩ := h
  obtain ⟨c', hc', rfl⟩ := mem_toS_iff.mp hc
  simp only [firesDup, List.any_eq_true]
  rcases hcase with ⟨d, hd, e, he, hdv, hev, hne, hdl, hel⟩ | ⟨hcl, d, hd, hdv, hdl⟩
  · obtain ⟨d', hd', rfl⟩ := mem_toS_iff.mp hd
    obtain ⟨e', he', rfl⟩ := mem_toS_iff.mp he
    have hlab : l ∈ labList :=
      List.mem_range.mpr (Finset.mem_range.mp ((hb d' hd').2.2 (by simpa using hdl)))
    refine ⟨l, hlab, c', hc', ?_⟩
    rw [Bool.or_eq_true]
    refine Or.inl (twoBits_iff.mpr ⟨d'.lhs, e'.lhs, by simpa using hne, ?_, ?_⟩) <;>
      rw [Nat.testBit_and, Bool.and_eq_true]
    · exact ⟨mem_varsOf.mp (by simpa using hdv),
        testBit_carriers.mpr ⟨d', hd', rfl, mem_varsOf.mp (by simpa using hdl)⟩⟩
    · exact ⟨mem_varsOf.mp (by simpa using hev),
        testBit_carriers.mpr ⟨e', he', rfl, mem_varsOf.mp (by simpa using hel)⟩⟩
  · obtain ⟨d', hd', rfl⟩ := mem_toS_iff.mp hd
    have hlab : l ∈ labList :=
      List.mem_range.mpr (Finset.mem_range.mp ((hb c' hc').2.2 (by simpa using hcl)))
    refine ⟨l, hlab, c', hc', ?_⟩
    rw [Bool.or_eq_true, Bool.and_eq_true, bne_iff_ne]
    refine Or.inr ⟨mem_varsOf.mp (by simpa using hcl), ne_zero_of_testBit (i := d'.lhs) ?_⟩
    rw [Nat.testBit_and, Bool.and_eq_true]
    exact ⟨mem_varsOf.mp (by simpa using hdv),
      testBit_carriers.mpr ⟨d', hd', rfl, mem_varsOf.mp (by simpa using hdl)⟩⟩

/-- The three transcriptions are the three conditions. -/
theorem firesDup_iff {n : ℕ} {L : List MC} (hb : Below n L) :
    firesDup L = true ↔ RDup (toS L) := ⟨firesDup_sound, firesDup_complete hb⟩

/-! ## 6. The search

`ok f G` is the per-system question: for each of the three refuters, does the FULL
saturation fire it only where the CUT saturation does?  The `active` guard in front is a
speed device only -- `close_of_not_active` shows that when no pair of `G` fires the rule's
guard both saturations are the identity, so the question answers itself. -/

/-- Some pair of `G` fires the rule's guard. -/
def active (G : List MC) : Bool := (pairsOf G).any fun p => firesPair p.1 p.2

/-- The per-system check. -/
def ok (f : ℕ) (G : List MC) : Bool :=
  !active G ||
    (let Cf := fullClose f G
     let Cc := cutClose f G
     (!firesDup Cf || firesDup Cc) && (!fires11 Cf || fires11 Cc) && (!firesInf Cf || firesInf Cc))

theorem foldl_stepPair_of_none (mint : Bool) :
    ∀ (ps : List (MC × MC)), (∀ p ∈ ps, firesPair p.1 p.2 = false) →
      ∀ acc : List MC × ℕ, ps.foldl (stepPair mint) acc = acc := by
  intro ps
  induction ps with
  | nil => intro _ acc; rfl
  | cons p t ih =>
    intro h acc
    have : stepPair mint acc p = acc := by
      cases mint
      · rw [stepPair_eq_false, if_neg (by simp [h p List.mem_cons_self])]
      · rw [stepPair_eq_true, if_neg (by simp [h p List.mem_cons_self])]
    rw [List.foldl_cons, this]
    exact ih (fun q hq => h q (List.mem_cons_of_mem _ hq)) acc

theorem round_of_not_active {mint : Bool} {st : List MC × ℕ} (h : active st.1 = false) :
    round mint st = st :=
  foldl_stepPair_of_none mint (pairsOf st.1)
    (fun p hp => by simpa using (List.any_eq_false.mp h) p hp) st

theorem close_of_not_active {mint : Bool} {f : ℕ} {st : List MC × ℕ} (h : active st.1 = false) :
    close mint f st = st := by
  induction f with
  | zero => rfl
  | succ n ih => rw [close, round_of_not_active h]; exact ih

theorem cutClose_of_not_active {f : ℕ} {G : List MC} (h : active G = false) :
    cutClose f G = G := by rw [cutClose, close_of_not_active h]

theorem fullClose_of_not_active {f : ℕ} {G : List MC} (h : active G = false) :
    fullClose f G = G := by rw [fullClose, close_of_not_active h]

/-- Reading `ok` back: the three implications, whether or not the short-circuit fired. -/
theorem ok_read {f : ℕ} {G : List MC} (h : ok f G = true) :
    (firesDup (fullClose f G) = true → firesDup (cutClose f G) = true) ∧
      (fires11 (fullClose f G) = true → fires11 (cutClose f G) = true) ∧
      (firesInf (fullClose f G) = true → firesInf (cutClose f G) = true) := by
  by_cases ha : active G = true
  · rw [ok, ha] at h
    simp only [Bool.not_true, Bool.false_or, Bool.and_eq_true, Bool.or_eq_true,
      Bool.not_eq_true'] at h
    refine ⟨fun hf => ?_, fun hf => ?_, fun hf => ?_⟩
    · rcases h.1.1 with h' | h'
      · rw [hf] at h'; exact absurd h' (by simp)
      · exact h'
    · rcases h.1.2 with h' | h'
      · rw [hf] at h'; exact absurd h' (by simp)
      · exact h'
    · rcases h.2 with h' | h'
      · rw [hf] at h'; exact absurd h' (by simp)
      · exact h'
  · rw [Bool.not_eq_true] at ha
    rw [cutClose_of_not_active ha, fullClose_of_not_active ha]
    exact ⟨id, id, id⟩

/-- **What one line of the sweep says.**  Both saturations are real runs of the real
relations, and every one of the three error conditions that fires on the full solver's
derived system fires on the cut solver's too. -/
def Keeps (f : ℕ) (L : List MC) : Prop :=
  (∃ m, BranchSteps m (toS L) (toS (fullClose f L))) ∧
    (∃ k, CutSteps k (toS L) (toS (cutClose f L))) ∧
    (RDup (toS (fullClose f L)) → RDup (toS (cutClose f L))) ∧
    (Fires11 (toS (fullClose f L)) → Fires11 (toS (cutClose f L))) ∧
    (RInf (toS (fullClose f L)) → RInf (toS (cutClose f L)))

theorem keeps_of_ok {f : ℕ} {L : List MC} (hb : Below nbase L) (h : ok f L = true) :
    Keeps f L := by
  obtain ⟨h1, h2, h3⟩ := ok_read h
  refine ⟨fullClose_run f L hb, cutClose_run f L hb, ?_, ?_, ?_⟩
  · intro hd
    exact firesDup_sound (h1 (firesDup_complete (full_close f (L, nbase) hb).1 hd))
  · intro hd
    exact (fires11_iff _).mp (h2 ((fires11_iff _).mpr hd))
  · intro hd
    exact (firesInf_iff _).mp (h3 ((firesInf_iff _).mpr hd))

/-! ### The enumerated universe -/

/-- Population count over the lowest `k` bits. -/
def pop : ℕ → ℕ → ℕ
  | 0, _ => 0
  | k + 1, m => m % 2 + pop k (m / 2)

/-- The right-hand-side masks of a universe: subsets of `{0,...,nv-1}` of size `≤ rm`. -/
def vsPool (nv rm : ℕ) : List ℕ := (List.range (2 ^ nv)).filter fun m => pop nv m ≤ rm

/-- Every constraint of a universe: left-hand side one of `nv` variables, right-hand side
at most `rm` of them, concrete part any subset of `nl` labels. -/
def mcPool (nv rm nl : ℕ) : List MC :=
  (List.range nv).flatMap fun l => (vsPool nv rm).flatMap fun v =>
    (List.range (2 ^ nl)).map fun c => ⟨l, v, c⟩

theorem mem_mcPool {nv rm nl : ℕ} {c : MC} (h : c ∈ mcPool nv rm nl) :
    c.lhs < nv ∧ c.vs < 2 ^ nv ∧ c.cs < 2 ^ nl := by
  simp only [mcPool, List.mem_flatMap, List.mem_map, List.mem_range, vsPool,
    List.mem_filter] at h
  obtain ⟨l, hl, v, ⟨hv, -⟩, k, hk, rfl⟩ := h
  exact ⟨hl, hv, hk⟩

theorem varsOf_subset_range {m k : ℕ} (h : m < 2 ^ k) : varsOf m ⊆ Finset.range k := by
  intro i hi
  rw [mem_varsOf] at hi
  rw [Finset.mem_range]
  by_contra hlt
  push Not at hlt
  have h2 : (2 : ℕ) ^ k ≤ 2 ^ i := Nat.pow_le_pow_right (by omega) hlt
  rw [Nat.testBit_lt_two_pow (lt_of_lt_of_le h h2)] at hi
  exact Bool.noConfusion hi

theorem below_of_pool {nv rm nl : ℕ} (hv : nv ≤ nbase) (hl : nl ≤ nlabs) {L : List MC}
    (h : ∀ c ∈ L, c ∈ mcPool nv rm nl) : Below nbase L := by
  intro c hc
  obtain ⟨h1, h2, h3⟩ := mem_mcPool (h c hc)
  exact ⟨lt_of_lt_of_le h1 hv, (varsOf_subset_range h2).trans (Finset.range_mono hv),
    (varsOf_subset_range h3).trans (Finset.range_mono hl)⟩

theorem land_comm (a b : ℕ) : a &&& b = b &&& a :=
  Nat.eq_of_testBit_eq fun i => by simp only [Nat.testBit_and, Bool.and_comm]

theorem firesPair_comm (a b : MC) : firesPair a b = firesPair b a := by
  simp only [firesPair, sharedM, land_comm a.vs b.vs, bne_comm]

theorem toS_congr {L L' : List MC} (h1 : L ⊆ L') (h2 : L' ⊆ L) : toS L = toS L' :=
  Finset.Subset.antisymm (toS_mono h1) (toS_mono h2)

/-- **Universe A**: 4 variables, 2 labels, right-hand sides of at most 3 variables.
Every such constraint: 4 * 15 * 4 = 240 of them. -/
def poolA : List MC := mcPool 4 3 2

/-- **Universe B**: 4 variables, 1 label, right-hand sides of at most 2 variables.
Every such constraint: 4 * 11 * 2 = 88 of them. -/
def poolB : List MC := mcPool 4 2 1

/-- `f` on every unordered pair drawn from a list, repeats included. -/
def allPairs (f : MC → MC → Bool) : List MC → Bool
  | [] => true
  | a :: t => (a :: t).all (f a) && allPairs f t

theorem allPairs_read {f : MC → MC → Bool} : ∀ {L : List MC}, allPairs f L = true →
    ∀ a ∈ L, ∀ b ∈ L, f a b = true ∨ f b a = true := by
  intro L
  induction L with
  | nil => intro _ a ha; cases ha
  | cons c t ih =>
    intro h a ha b hb
    rw [allPairs, Bool.and_eq_true, List.all_eq_true] at h
    rcases List.mem_cons.mp ha with rfl | ha'
    · exact Or.inl (h.1 b hb)
    · rcases List.mem_cons.mp hb with rfl | hb'
      · exact Or.inr (h.1 a (List.mem_cons_of_mem _ ha'))
      · exact ih h.2 a ha' b hb'

/-- **Sweep A.**  Every system of at most two constraints over universe A, fuel 3. -/
def sweepA : Bool := allPairs (fun a b => ok 3 [a, b]) poolA

/-- **Sweep B.**  Every system of at most three constraints over universe B whose first
two constraints fire the rule's guard, fuel 2.  (A system no pair of which fires is
handled by `close_of_not_active`, and one whose firing pair is not the first two is a
reordering -- see `sweepB_keeps`.) -/
def sweepB : Bool :=
  allPairs (fun a b => !firesPair a b || poolB.all fun c => ok 2 [a, b, c]) poolB

/-! ## 7. What is true of ALL systems, not just the searched ones

The sweep is bounded; this section is not.  7.1 isolates the shape both the minting
branch and the reuse branch have -- "every conclusion copies a premise, with a block of
its right-hand side abbreviated by a name that carries no labels" -- and proves that a
step of that shape cannot create an instance of any of the three conditions.  7.2 proves
that the cut can abbreviate by an EXISTING name with no second premise to find.  7.3 says
exactly what is left open, and it is what the sweep tests. -/

/-! ### 7.1 Abbreviating by an inert name creates no refutation -/

theorem ne_empty_of_mem {s : Finset Label} {l : Label} (h : l ∈ s) : s ≠ ∅ := by
  rintro rfl
  simp at h

/-- The shape of a step that abbreviates a block of right-hand sides by the name `z`.
Both `cseResult` (minting, `z` fresh) and `reuseResult` (`z` an existing name) have it,
and the last field -- `z` heads nothing with a concrete part -- is what makes the
abbreviation invisible to a refuter that reasons about labels. -/
structure Abbrev (G H : System) (z : Var) : Prop where
  /-- every conclusion's parts come from an existing constraint's parts, plus `z`; and it
  either has no concrete part or repeats that constraint's left-hand side and concrete
  part exactly -/
  copy : ∀ d ∈ H, ∃ e ∈ G, vset d ⊆ insert z (vset e) ∧
    (d.conc = ∅ ∨ (d.lhs = e.lhs ∧ d.conc = e.conc))
  /-- a conclusion that carries a label repeats an existing constraint's left-hand side
  and concrete part -/
  carrier : ∀ d ∈ H, d.conc ≠ ∅ → ∃ e ∈ G, e.lhs = d.lhs ∧ e.conc = d.conc
  /-- `z` is inert: nothing it heads carries a label -/
  inert : ∀ d ∈ G, d.lhs = z → d.conc = ∅
  /-- no conclusion is a fully concrete partition -/
  solved : ∀ d ∈ H, vset d = ∅ → d ∈ G

theorem Abbrev.lhs_ne {G H : System} {z : Var} (h : Abbrev G H z) {d : Constraint}
    (hd : d ∈ H) (hne : d.conc ≠ ∅) : d.lhs ≠ z := by
  obtain ⟨e, he, hlhs, hconc⟩ := h.carrier d hd hne
  intro hz
  exact (hne (by rw [← hconc]; exact h.inert e he (by rw [hlhs, hz]))).elim

theorem Abbrev.rDup {G H : System} {z : Var} (h : Abbrev G H z) (hd : RDup H) : RDup G := by
  obtain ⟨c, hc, l, hcase⟩ := hd
  obtain ⟨p, hp, hsub, hconc⟩ := h.copy c hc
  rcases hcase with ⟨d, hd', e, he, hdv, hev, hne, hdl, hel⟩ | ⟨hcl, d, hd', hdv, hdl⟩
  · obtain ⟨d', hd2, hd3, hd4⟩ := h.carrier d hd' (ne_empty_of_mem hdl)
    obtain ⟨e', he2, he3, he4⟩ := h.carrier e he (ne_empty_of_mem hel)
    have hdp : d.lhs ∈ vset p := by
      rcases Finset.mem_insert.mp (hsub hdv) with h' | h'
      · exact absurd h' (h.lhs_ne hd' (ne_empty_of_mem hdl))
      · exact h'
    have hep : e.lhs ∈ vset p := by
      rcases Finset.mem_insert.mp (hsub hev) with h' | h'
      · exact absurd h' (h.lhs_ne he (ne_empty_of_mem hel))
      · exact h'
    exact ⟨p, hp, l, Or.inl ⟨d', hd2, e', he2, by rw [hd3]; exact hdp, by rw [he3]; exact hep,
      by rw [hd3, he3]; exact hne, by rw [hd4]; exact hdl, by rw [he4]; exact hel⟩⟩
  · obtain ⟨d', hd2, hd3, hd4⟩ := h.carrier d hd' (ne_empty_of_mem hdl)
    have hdp : d.lhs ∈ vset p := by
      rcases Finset.mem_insert.mp (hsub hdv) with h' | h'
      · exact absurd h' (h.lhs_ne hd' (ne_empty_of_mem hdl))
      · exact h'
    have hpc : l ∈ p.conc := by
      rcases hconc with h0 | ⟨-, h0⟩
      · exact absurd hcl (by rw [h0]; simp)
      · rwa [h0] at hcl
    exact ⟨p, hp, l, Or.inr ⟨hpc, d', hd2, by rw [hd3]; exact hdp, by rw [hd4]; exact hdl⟩⟩

theorem Abbrev.fires11 {G H : System} {z : Var} (h : Abbrev G H z) (hf : Fires11 H) :
    Fires11 G := by
  obtain ⟨c, hc, d, hd, hlhs, hvs, hsub⟩ := hf
  have hdne : d.conc ≠ ∅ := fun h0 => hsub (by rw [h0]; exact Finset.empty_subset _)
  obtain ⟨d', hd2, hd3, hd4⟩ := h.carrier d hd hdne
  exact ⟨c, h.solved c hc hvs, d', hd2, by rw [hd3]; exact hlhs, hvs, by rw [hd4]; exact hsub⟩

theorem Abbrev.rInf {G H : System} {z : Var} (h : Abbrev G H z) (hf : RInf H) : RInf G := by
  obtain ⟨c, hc, hmem, hne⟩ := hf
  obtain ⟨e, he, hsub, hconc⟩ := h.copy c hc
  rcases hconc with h0 | ⟨hl, hcn⟩
  · exact absurd h0 hne
  · have hmem' : c.lhs ∈ vset e := by
      rcases Finset.mem_insert.mp (hsub hmem) with h' | h'
      · exact absurd h' (h.lhs_ne hc hne)
      · exact h'
    exact ⟨e, he, by rw [← hl]; exact hmem', by rw [← hcn]; exact hne⟩

/-- **A step of abbreviating shape creates no refutation.** -/
theorem Abbrev.no_new_refutation {G H : System} {z : Var} (h : Abbrev G H z) :
    (RDup H → RDup G) ∧ (Fires11 H → Fires11 G) ∧ (RInf H → RInf G) :=
  ⟨h.rDup, h.fires11, h.rInf⟩

theorem mem_cseResult {G : System} {c₁ c₂ : Constraint} {z : Var} {d : Constraint}
    (hd : d ∈ cseResult G c₁ c₂ z) :
    d = mk z (shared c₁ c₂) ∅ ∨ d = reduce c₁ (shared c₁ c₂) z ∨
      d = reduce c₂ (shared c₁ c₂) z ∨ d ∈ G := by
  simpa [cseResult, Finset.mem_insert, or_assoc] using hd

theorem mem_reuseResult {G : System} {c₁ c₂ : Constraint} {z : Var} {d : Constraint}
    (hd : d ∈ reuseResult G c₁ c₂ z) :
    d = reduce c₁ (shared c₁ c₂) z ∨ d = reduce c₂ (shared c₁ c₂) z ∨ d ∈ G := by
  simpa [reuseResult, Finset.mem_insert, or_assoc] using hd

/-- The minting branch has abbreviating shape: its name is FRESH, hence inert. -/
theorem cseResult_abbrev {G : System} {c₁ c₂ : Constraint} {z : Var} (happ : CseApp G c₁ c₂ z) :
    Abbrev G (cseResult G c₁ c₂ z) z where
  copy d hd := by
    rcases mem_cseResult hd with rfl | rfl | rfl | hd'
    · exact ⟨c₁, happ.mem₁, by
        rw [vset_mk]; exact (shared_subset_left c₁ c₂).trans (Finset.subset_insert _ _),
        Or.inl rfl⟩
    · exact ⟨c₁, happ.mem₁, by
        rw [vset_reduce]; exact Finset.insert_subset_insert _ Finset.sdiff_subset,
        Or.inr ⟨rfl, rfl⟩⟩
    · exact ⟨c₂, happ.mem₂, by
        rw [vset_reduce]; exact Finset.insert_subset_insert _ Finset.sdiff_subset,
        Or.inr ⟨rfl, rfl⟩⟩
    · exact ⟨d, hd', Finset.subset_insert _ _, Or.inr ⟨rfl, rfl⟩⟩
  carrier d hd hne := by
    rcases mem_cseResult hd with rfl | rfl | rfl | hd'
    · exact absurd rfl hne
    · exact ⟨c₁, happ.mem₁, rfl, rfl⟩
    · exact ⟨c₂, happ.mem₂, rfl, rfl⟩
    · exact ⟨d, hd', rfl, rfl⟩
  inert d hd hz := absurd (hz ▸ lhs_mem_allVars hd) happ.fresh
  solved d hd hvs := by
    rcases mem_cseResult hd with rfl | rfl | rfl | hd'
    · rw [vset_mk] at hvs
      have := happ.two_le
      rw [hvs] at this
      simp at this
    · rw [vset_reduce] at hvs
      have hz : z ∈ (∅ : Finset Var) := hvs ▸ Finset.mem_insert_self z _
      simp at hz
    · rw [vset_reduce] at hvs
      have hz : z ∈ (∅ : Finset Var) := hvs ▸ Finset.mem_insert_self z _
      simp at hz
    · exact hd'

/-- The reuse branch has abbreviating shape whenever its name is inert. -/
theorem reuseResult_abbrev {G : System} {c₁ c₂ : Constraint} {z : Var} (h₁ : c₁ ∈ G)
    (h₂ : c₂ ∈ G) (hinert : ∀ d ∈ G, d.lhs = z → d.conc = ∅) :
    Abbrev G (reuseResult G c₁ c₂ z) z where
  copy d hd := by
    rcases mem_reuseResult hd with rfl | rfl | hd'
    · exact ⟨c₁, h₁, by
        rw [vset_reduce]; exact Finset.insert_subset_insert _ Finset.sdiff_subset,
        Or.inr ⟨rfl, rfl⟩⟩
    · exact ⟨c₂, h₂, by
        rw [vset_reduce]; exact Finset.insert_subset_insert _ Finset.sdiff_subset,
        Or.inr ⟨rfl, rfl⟩⟩
    · exact ⟨d, hd', Finset.subset_insert _ _, Or.inr ⟨rfl, rfl⟩⟩
  carrier d hd _ := by
    rcases mem_reuseResult hd with rfl | rfl | hd'
    · exact ⟨c₁, h₁, rfl, rfl⟩
    · exact ⟨c₂, h₂, rfl, rfl⟩
    · exact ⟨d, hd', rfl, rfl⟩
  inert := hinert
  solved d hd hvs := by
    rcases mem_reuseResult hd with rfl | rfl | hd'
    · rw [vset_reduce] at hvs
      have hz : z ∈ (∅ : Finset Var) := hvs ▸ Finset.mem_insert_self z _
      simp at hz
    · rw [vset_reduce] at hvs
      have hz : z ∈ (∅ : Finset Var) := hvs ▸ Finset.mem_insert_self z _
      simp at hz
    · exact hd'

/-- **The minting branch cannot create a refutation.**  For each of the three
concrete-label error conditions: if it fires on the output of a minting step, it already
fired on the input.  No bound on the system, the vocabulary or the number of labels --
this is the unbounded fact the sweep is evidence for.

The reason is structural.  The fresh name is INERT: every constraint the branch emits
either repeats an existing left-hand side with an existing concrete part, or is the new
name's own definition `z <- int`, whose concrete part is empty -- and nothing else in the
system can mention `z` at all, because `z` is fresh.  A refuter that reasons about
concrete labels sees nothing it did not already see. -/
theorem mint_creates_no_refutation {G : System} {c₁ c₂ : Constraint} {z : Var}
    (happ : CseApp G c₁ c₂ z) :
    (RDup (cseResult G c₁ c₂ z) → RDup G) ∧ (Fires11 (cseResult G c₁ c₂ z) → Fires11 G) ∧
      (RInf (cseResult G c₁ c₂ z) → RInf G) :=
  (cseResult_abbrev happ).no_new_refutation

/-- **Consuming an inert name cannot create a refutation either.**  In particular a REUSE
step whose name was minted -- the step that "uses what the cut cannot invent" -- is as
harmless as the minting step itself. -/
theorem reuse_inert_creates_no_refutation {G : System} {c₁ c₂ : Constraint} {z : Var}
    (h₁ : c₁ ∈ G) (h₂ : c₂ ∈ G) (hinert : ∀ d ∈ G, d.lhs = z → d.conc = ∅) :
    (RDup (reuseResult G c₁ c₂ z) → RDup G) ∧
      (Fires11 (reuseResult G c₁ c₂ z) → Fires11 G) ∧
      (RInf (reuseResult G c₁ c₂ z) → RInf G) :=
  (reuseResult_abbrev h₁ h₂ hinert).no_new_refutation

/-! ### 7.2 The cut can abbreviate by any existing name -/

/-- **A naming constraint is all the cut needs.**  If `z` names `S` and `S` sits inside
the right-hand side of `c`, then the PAIR `(c, z <- S)` fires the rule with shared block
exactly `S`, and the reuse branch emits `reduce c S z`.  So every abbreviation the reuse
branch can make from a pair of premises, the cut can already make from the naming
constraint alone: the only thing the cut cannot do is INVENT a name. -/
theorem cut_can_abbreviate {G : System} {c : Constraint} {z : Var} {S : Finset Var}
    (hc : c ∈ G) (hz : Names G z S) (hS : S ⊆ vset c) (h2 : 2 ≤ S.card) (hne : c.lhs ≠ z) :
    ∃ G', CutStep G G' ∧ reduce c S z ∈ G' := by
  obtain ⟨d, hd, hdlhs, hdvs, hdconc⟩ := hz
  have hshared : shared c d = S := by
    rw [shared, hdvs]
    exact Finset.inter_eq_right.mpr hS
  have hp : CsePair G c d :=
    ⟨hc, hd, by rw [hdlhs]; exact hne, by rw [hshared]; exact h2⟩
  refine ⟨reuseResult G c d z, CutStep.reuse hp ⟨d, hd, hdlhs, by rw [hdvs, hshared], hdconc⟩, ?_⟩
  rw [reuseResult, hshared]
  exact Finset.mem_insert_self _ _

/-! ### 7.3 What is left open

`mint_creates_no_refutation` and `reuse_inert_creates_no_refutation` between them settle
every step whose name carries no labels.  What they do NOT settle is the composite: a
minting step makes a name, a later step CONSUMES that name in a premise, and the
constraint that comes out then meets a step whose name is an ORIGINAL one.  The cut cannot
replay the first step, and `cut_can_abbreviate` replays the last one only when the naming
constraint it needs is one the cut has.  That composite is what the sweep tests. -/

/-! ## 8. The sweep, checked by the kernel

`decide +kernel` and not `native_decide`: the Boolean is evaluated by the Lean kernel, so
the proof term is checked the same way every other theorem in this development is.  These
two declarations are the whole cost of the file (about two and a half minutes). -/

set_option maxRecDepth 10000000 in
/-- **Sweep A.**  Every system of at most two constraints over universe A -- 4 variables,
2 labels, right-hand sides of at most 3 variables, all 240 constraints -- at fuel 3.
28920 systems. -/
theorem sweepA_check : sweepA = true := by decide +kernel

set_option maxRecDepth 10000000 in
/-- **Sweep B.**  Every system of at most three constraints over universe B -- 4
variables, 1 label, right-hand sides of at most 2 variables, all 88 constraints -- whose
first two constraints fire the rule's guard, at fuel 2.  12672 systems. -/
theorem sweepB_check : sweepB = true := by decide +kernel

theorem below_poolA {L : List MC} (h : ∀ c ∈ L, c ∈ poolA) : Below nbase L :=
  below_of_pool (by rw [nbase]; omega) (by rw [nlabs]) h

theorem below_poolB {L : List MC} (h : ∀ c ∈ L, c ∈ poolB) : Below nbase L :=
  below_of_pool (by rw [nbase]; omega) (by rw [nlabs]; omega) h

/-- **Sweep A, read out.**  For every system of at most two constraints over universe A
there is a presentation of it that the search ran, and on that run both saturations are
real runs of the real relations and the cut refutes wherever the full solver does. -/
theorem sweepA_keeps (a b : MC) (ha : a ∈ poolA) (hb : b ∈ poolA) :
    ∃ L : List MC, toS L = toS [a, b] ∧ Keeps 3 L := by
  have hsub : ∀ x y : MC, x ∈ poolA → y ∈ poolA → ∀ c ∈ [x, y], c ∈ poolA := by
    intro x y hx hy c hc
    rcases List.mem_cons.mp hc with rfl | hc'
    · exact hx
    · rcases List.mem_cons.mp hc' with rfl | hc''
      · exact hy
      · cases hc''
  rcases allPairs_read sweepA_check a ha b hb with h | h
  · exact ⟨[a, b], rfl, keeps_of_ok (below_poolA (hsub a b ha hb)) h⟩
  · refine ⟨[b, a], toS_congr ?_ ?_, keeps_of_ok (below_poolA (hsub b a hb ha)) h⟩ <;>
      (intro x hx; simp only [List.mem_cons, List.not_mem_nil, or_false] at hx ⊢; tauto)

/-- **Sweep B, read out.**  For every system of at most three constraints over universe B
-- whether or not any of its pairs fires the rule -- there is a presentation of it that
the search ran, and on that run the cut refutes wherever the full solver does. -/
theorem sweepB_keeps (a b c : MC) (ha : a ∈ poolB) (hb : b ∈ poolB) (hc : c ∈ poolB) :
    ∃ L : List MC, toS L = toS [a, b, c] ∧ Keeps 2 L := by
  have hmem : ∀ x y w : MC, x ∈ poolB → y ∈ poolB → w ∈ poolB → ∀ d ∈ [x, y, w], d ∈ poolB := by
    intro x y w hx hy hw d hd
    rcases List.mem_cons.mp hd with rfl | hd'
    · exact hx
    · rcases List.mem_cons.mp hd' with rfl | hd''
      · exact hy
      · rcases List.mem_cons.mp hd'' with rfl | hd'''
        · exact hw
        · cases hd'''
  have hperm : ∀ x y w : MC, (∀ d ∈ [x, y, w], d ∈ [a, b, c]) → (∀ d ∈ [a, b, c], d ∈ [x, y, w]) →
      toS [x, y, w] = toS [a, b, c] := fun x y w h1 h2 => toS_congr h1 h2
  -- the sweep's line for a firing pair `(x, y)` and any third constraint `w`
  have hline : ∀ x y w : MC, x ∈ poolB → y ∈ poolB → w ∈ poolB → firesPair x y = true →
      ok 2 [x, y, w] = true ∨ ok 2 [y, x, w] = true := by
    intro x y w hx hy hw hf
    have hf' : firesPair y x = true := by rwa [firesPair_comm] at hf
    rcases allPairs_read sweepB_check x hx y hy with h | h
    · exact Or.inl (by simpa [hf] using List.all_eq_true.mp (by simpa [hf] using h) w hw)
    · exact Or.inr (by simpa [hf'] using List.all_eq_true.mp (by simpa [hf'] using h) w hw)
  by_cases hab : firesPair a b = true
  · rcases hline a b c ha hb hc hab with h | h
    · exact ⟨[a, b, c], rfl, keeps_of_ok (below_poolB (hmem a b c ha hb hc)) h⟩
    · exact ⟨[b, a, c], hperm b a c (by intro d hd; simp at hd ⊢; tauto)
        (by intro d hd; simp at hd ⊢; tauto), keeps_of_ok (below_poolB (hmem b a c hb ha hc)) h⟩
  · by_cases hac : firesPair a c = true
    · rcases hline a c b ha hc hb hac with h | h
      · exact ⟨[a, c, b], hperm a c b (by intro d hd; simp at hd ⊢; tauto)
          (by intro d hd; simp at hd ⊢; tauto), keeps_of_ok (below_poolB (hmem a c b ha hc hb)) h⟩
      · exact ⟨[c, a, b], hperm c a b (by intro d hd; simp at hd ⊢; tauto)
          (by intro d hd; simp at hd ⊢; tauto), keeps_of_ok (below_poolB (hmem c a b hc ha hb)) h⟩
    · by_cases hbc : firesPair b c = true
      · rcases hline b c a hb hc ha hbc with h | h
        · exact ⟨[b, c, a], hperm b c a (by intro d hd; simp at hd ⊢; tauto)
            (by intro d hd; simp at hd ⊢; tauto), keeps_of_ok (below_poolB (hmem b c a hb hc ha)) h⟩
        · exact ⟨[c, b, a], hperm c b a (by intro d hd; simp at hd ⊢; tauto)
            (by intro d hd; simp at hd ⊢; tauto), keeps_of_ok (below_poolB (hmem c b a hc hb ha)) h⟩
      · refine ⟨[a, b, c], rfl, keeps_of_ok (below_poolB (hmem a b c ha hb hc)) ?_⟩
        simp only [Bool.not_eq_true] at hab hac hbc
        have hact : active [a, b, c] = false := by
          simp [active, pairsOf, hab, hac, hbc]
        rw [ok, hact]
        simp

/-! ## 9. A COUNTEREXAMPLE: the cut really can lose a refutation

Everything above is either an unbounded theorem about a single step or a bounded sweep.
This section is the answer to the question the sweeps were built to ask, and it is
negative.

```
0 <- (3, 4, 5, 6)
1 <- (2, 3, 4)
1 <- (5, 6)
1 <- (3, 5, 6, (|A|))
```

The system has NO model: the last two constraints make `rho 1 = rho 5 + rho 6` and
`rho 1 = rho 3 + rho 5 + rho 6 + {A}` at once, so `A` would have to be both inside and
outside `rho 1`.

The shipped solver finds that in two rounds.  `int = {3,4}` is shared by the first two
constraints and has no name, so branch (c) MINTS one: `z <- (3,4)`, and rewrites the
first constraint to `0 <- (5, 6, z)`.  THAT constraint shares exactly `{5,6}` with the
last one -- and `{5,6}` is named, by `1 <- (5,6)`.  So branch (a) fires and rewrites the
last constraint to `1 <- (1, 3, (|A|))`: a row that contains itself and a field, which is
Ermine's infinite-row error.

The cut cannot follow.  The pair that would abbreviate `1 <- (3,5,6,(|A|))` by the name
`1` directly is `(1 <- (5,6), 1 <- (3,5,6,(|A|)))`, and the rule refuses it: both
constraints have the SAME left-hand side.  Minting is what breaks that tie -- it produces
a constraint headed by `0` that shares the same block.  Six constraints are all the cut
ever derives here, at ANY fuel (`cutClose_cex_mem`), and none of the three error
conditions fires on them.

So `Cut.refuter_can_miss` is not an abstract possibility: the loss is realised by an
actual run of `commonSubexpression` against Ermine's own error conditions.  What the
example needs is exactly the configuration the sweeps of section 8 cannot express -- a
premise with four right-hand variables, so that what is left after the minted block is
abbreviated is still big enough to share two variables with something else.

SCOPE, honestly.  This is a statement about the rule `commonSubexpression` in isolation,
which is what `Cut` formalises.  Ermine's solver has other rules, and one of them may well
refute this system by another route -- two partitions of the SAME variable is exactly the
configuration `Rules.rule11` and the subtraction rules are about.  What is proved here is
that the cut loses a refutation THIS rule set finds, not that Ermine as a whole would
accept the program. -/

/-- The counterexample: `0 <- (3,4,5,6)`, `1 <- (2,3,4)`, `1 <- (5,6)`,
`1 <- (3,5,6,(|A|))`, with `A` the label `0`. -/
def cex : List MC := [⟨0, 120, 0⟩, ⟨1, 28, 0⟩, ⟨1, 96, 0⟩, ⟨1, 104, 1⟩]

/-- Everything the cut ever derives from `cex`: the input, plus `0 <- (1,3,4)` and the
vacuous `1 <- (1)`. -/
def cexCut : List MC :=
  [⟨0, 26, 0⟩, ⟨1, 2, 0⟩, ⟨0, 120, 0⟩, ⟨1, 28, 0⟩, ⟨1, 96, 0⟩, ⟨1, 104, 1⟩]

/-- `B` is closed under the cut rule: every conclusion the kept branches can draw from
two of its constraints is already one of its constraints. -/
def stableUnder (B : List MC) : Bool :=
  B.all fun a => B.all fun b => !firesPair a b ||
    (namesOf B (sharedM a b)).all fun z =>
      decide (reduceM a (sharedM a b) z ∈ B) && decide (reduceM b (sharedM a b) z ∈ B)

theorem namesOf_mono {L B : List MC} (h : ∀ c ∈ L, c ∈ B) {S z : ℕ} (hz : z ∈ namesOf L S) :
    z ∈ namesOf B S := by
  obtain ⟨d, hd, rfl, h1, h2⟩ := mem_namesOf hz
  exact List.mem_map.mpr ⟨d, List.mem_filter.mpr ⟨h d hd, by simp [h1, h2]⟩, rfl⟩

theorem stableUnder_read {B : List MC} (h : stableUnder B = true) {a b : MC} (ha : a ∈ B)
    (hb : b ∈ B) (hf : firesPair a b = true) {z : ℕ} (hz : z ∈ namesOf B (sharedM a b)) :
    reduceM a (sharedM a b) z ∈ B ∧ reduceM b (sharedM a b) z ∈ B := by
  have h2 := List.all_eq_true.mp (List.all_eq_true.mp h a ha) b hb
  rw [hf] at h2
  simp only [Bool.not_true, Bool.false_or] at h2
  have h3 := List.all_eq_true.mp h2 z hz
  rw [Bool.and_eq_true, decide_eq_true_eq, decide_eq_true_eq] at h3
  exact h3

theorem stepPair_mem {B : List MC} (hB : stableUnder B = true) {acc : List MC × ℕ}
    (hacc : ∀ c ∈ acc.1, c ∈ B) {p : MC × MC} (h1 : p.1 ∈ B) (h2 : p.2 ∈ B) :
    ∀ c ∈ (stepPair false acc p).1, c ∈ B := by
  rw [stepPair_eq_false]
  split
  · rename_i hf
    intro c hc
    rcases List.mem_append.mp hc with hc' | hc'
    · obtain ⟨z, hz, hc''⟩ := List.mem_flatMap.mp hc'
      obtain ⟨r1, r2⟩ := stableUnder_read hB h1 h2 hf (namesOf_mono hacc hz)
      rcases List.mem_cons.mp hc'' with rfl | hc'''
      · exact r1
      · rcases List.mem_cons.mp hc''' with rfl | hc''''
        · exact r2
        · cases hc''''
    · exact hacc c hc'
  · exact hacc

theorem fold_mem {B : List MC} (hB : stableUnder B = true) :
    ∀ ps : List (MC × MC), (∀ p ∈ ps, p.1 ∈ B ∧ p.2 ∈ B) →
      ∀ acc : List MC × ℕ, (∀ c ∈ acc.1, c ∈ B) →
        ∀ c ∈ (ps.foldl (stepPair false) acc).1, c ∈ B := by
  intro ps
  induction ps with
  | nil => intro _ acc h; exact h
  | cons p t ih =>
    intro hps acc hacc
    have hp := hps p List.mem_cons_self
    exact ih (fun q hq => hps q (List.mem_cons_of_mem _ hq)) _
      (stepPair_mem hB hacc hp.1 hp.2)

theorem close_mem {B : List MC} (hB : stableUnder B = true) : ∀ (f : ℕ) (st : List MC × ℕ),
    (∀ c ∈ st.1, c ∈ B) → ∀ c ∈ (close false f st).1, c ∈ B := by
  intro f
  induction f with
  | zero => intro st h; exact h
  | succ n ih =>
    intro st h
    exact ih (round false st)
      (fold_mem hB (pairsOf st.1) (fun p hp => ⟨h _ (mem_pairsOf hp).1, h _ (mem_pairsOf hp).2⟩)
        st h)

theorem cexCut_stable : stableUnder cexCut = true := by decide

/-- **The cut saturation of `cex` never leaves six constraints, whatever the fuel.** -/
theorem cutClose_cex_mem (f : ℕ) : ∀ c ∈ cutClose f cex, c ∈ cexCut :=
  close_mem cexCut_stable f (cex, nbase) (by decide)

theorem below_of_bounds {n : ℕ} {L : List MC}
    (h : ∀ c ∈ L, c.lhs < n ∧ c.vs < 2 ^ n ∧ c.cs < 2 ^ nlabs) : Below n L :=
  fun c hc => ⟨(h c hc).1, varsOf_subset_range (h c hc).2.1, varsOf_subset_range (h c hc).2.2⟩

theorem below_cex : Below nbase cex := below_of_bounds (by decide)

theorem below_cexCut : Below nbase cexCut := below_of_bounds (by decide)

theorem cexCut_no_fire :
    firesDup cexCut = false ∧ fires11 cexCut = false ∧ firesInf cexCut = false := by decide

/-! ### The negative result does not depend on the search's strategy

`stableUnder cexCut` says more than "the fuel-bounded saturation stops there": it says the
six constraints are closed under EVERY instance of the cut rule.  Decoding that back to
`Cut.CutStep` gives `cutSteps_cex_subset` -- no run of the cut rule from `cex`, in any
order and of any length, ever leaves them. -/

theorem varsOf_inj {m m' : ℕ} (h : varsOf m = varsOf m') : m = m' := by
  refine Nat.eq_of_testBit_eq fun i => ?_
  have hi := Finset.ext_iff.mp h i
  rw [mem_varsOf, mem_varsOf] at hi
  cases hm : m.testBit i <;> cases hm' : m'.testBit i <;> simp_all

theorem twoBits_of_two_le_card {m : ℕ} (h : 2 ≤ (varsOf m).card) : twoBits m = true := by
  obtain ⟨a, ha, b, hb, hab⟩ := Finset.one_lt_card.mp h
  exact twoBits_iff.mpr ⟨a, b, hab, mem_varsOf.mp ha, mem_varsOf.mp hb⟩

/-- A naming constraint of a decoded system comes from a name of the mini system. -/
theorem namesOf_of_Names {B : List MC} {z : ℕ} {S : ℕ} (h : Names (toS B) z (varsOf S)) :
    z ∈ namesOf B S := by
  obtain ⟨d, hd, hlhs, hvs, hconc⟩ := h
  obtain ⟨e, he, rfl⟩ := mem_toS_iff.mp hd
  refine List.mem_map.mpr ⟨e, List.mem_filter.mpr ⟨he, ?_⟩, hlhs⟩
  have h1 : e.vs = S := varsOf_inj (by simpa using hvs)
  have h2 : e.cs = 0 := varsOf_eq_empty.mp (by simpa using hconc)
  simp [h1, h2]

/-- One instance of the cut rule, decoded.  If both premises and the naming constraint
come from a stable set, so do both conclusions. -/
theorem reduce_mem_toS {B : List MC} (hB : stableUnder B = true) {a b : MC} (ha : a ∈ B)
    (hb : b ∈ B) (hlhs : a.lhs ≠ b.lhs) (h2 : 2 ≤ (shared (toC a) (toC b)).card) {z : ℕ}
    (hz : Names (toS B) z (shared (toC a) (toC b))) :
    reduce (toC a) (shared (toC a) (toC b)) z ∈ toS B ∧
      reduce (toC b) (shared (toC a) (toC b)) z ∈ toS B := by
  rw [shared_toC] at h2 hz ⊢
  have hf : firesPair a b = true := by
    rw [firesPair, Bool.and_eq_true, bne_iff_ne]
    exact ⟨hlhs, twoBits_of_two_le_card h2⟩
  obtain ⟨r1, r2⟩ := stableUnder_read hB ha hb hf (namesOf_of_Names hz)
  rw [← toC_reduceM, ← toC_reduceM]
  exact ⟨mem_toS r1, mem_toS r2⟩

theorem cutStep_stays {B : List MC} (hB : stableUnder B = true) {G G' : System}
    (hG : G ⊆ toS B) (h : CutStep G G') : G' ⊆ toS B := by
  have key : ∀ (c₁ c₂ : Constraint) (z : Var), c₁ ∈ G → c₂ ∈ G → c₁.lhs ≠ c₂.lhs →
      2 ≤ (shared c₁ c₂).card → Names G z (shared c₁ c₂) →
      reduce c₁ (shared c₁ c₂) z ∈ toS B ∧ reduce c₂ (shared c₁ c₂) z ∈ toS B := by
    intro c₁ c₂ z h1 h2 hne hcard hn
    obtain ⟨a, ha, rfl⟩ := mem_toS_iff.mp (hG h1)
    obtain ⟨b, hb, rfl⟩ := mem_toS_iff.mp (hG h2)
    exact reduce_mem_toS hB ha hb (by simpa using hne) hcard (names_mono hG hn)
  cases h with
  | @reuse c₁ c₂ z hp hn =>
    obtain ⟨r1, r2⟩ := key c₁ c₂ z hp.mem₁ hp.mem₂ hp.lhs_ne hp.two_le hn
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact r1
    · rcases Finset.mem_insert.mp hc' with rfl | hc''
      · exact r2
      · exact hG hc''
  | @fold c₁ c₂ hp hvs hconc =>
    have hn : Names G c₁.lhs (shared c₁ c₂) := ⟨c₁, hp.mem₁, rfl, hvs, hconc⟩
    obtain ⟨-, r2⟩ := key c₁ c₂ c₁.lhs hp.mem₁ hp.mem₂ hp.lhs_ne hp.two_le hn
    intro c hc
    rcases Finset.mem_insert.mp hc with rfl | hc'
    · exact r2
    · exact hG hc'

/-- **Every cut run from `cex` stays inside the same six constraints.**  Not just the
fuel-bounded saturation of section 3 -- every run of `Cut.CutStep`, in any order, of any
length. -/
theorem cutSteps_subset {B : List MC} (hB : stableUnder B = true) :
    ∀ {k : ℕ} {G₀ G : System}, CutSteps k G₀ G → G₀ ⊆ toS B → G ⊆ toS B := by
  intro k G₀ G h
  induction h with
  | refl => exact id
  | tail _ hstep ih => exact fun h0 => cutStep_stays hB (ih h0) hstep

theorem cutSteps_cex_subset {k : ℕ} {G : System} (h : CutSteps k (toS cex) G) :
    G ⊆ toS cexCut :=
  cutSteps_subset cexCut_stable h (toS_mono (by decide))

/-- **No cut run from `cex` ever fires any of the three error conditions.** -/
theorem cut_never_refutes_cex {k : ℕ} {G : System} (h : CutSteps k (toS cex) G) :
    ¬ RDup G ∧ ¬ Fires11 G ∧ ¬ RInf G := by
  have hsub := cutSteps_cex_subset h
  refine ⟨fun hf => ?_, fun hf => ?_, fun hf => ?_⟩
  · have := firesDup_complete below_cexCut (rDup_mono _ _ hsub hf)
    rw [cexCut_no_fire.1] at this
    exact Bool.noConfusion this
  · have := (fires11_iff cexCut).mpr (fires11_mono _ _ hsub hf)
    rw [cexCut_no_fire.2.1] at this
    exact Bool.noConfusion this
  · have := (firesInf_iff cexCut).mpr (rInf_mono _ _ hsub hf)
    rw [cexCut_no_fire.2.2] at this
    exact Bool.noConfusion this

/-- The full solver fires the infinite-row condition after two rounds. -/
theorem cex_full_fires : RInf (toS (fullClose 2 cex)) := (firesInf_iff _).mp (by decide)

/-- ... and the duplicated-field condition too. -/
theorem cex_full_fires_dup : RDup (toS (fullClose 2 cex)) := firesDup_sound (by decide)

/-- The system has no model.  Proved by the solver's own refutation: the derived system is
reachable from the input by real `CseBranch` steps, `RInf` is a sound refuter, and every
branch preserves satisfiability (`Cut.run_refutation_sound`). -/
theorem cex_unsat : ¬ ∃ rho, SModels rho (toS cex) := by
  obtain ⟨m, hm⟩ := fullClose_run 2 cex below_cex
  exact run_refutation_sound refuterInf hm cex_full_fires

/-- **THE RESULT OF THE HUNT.**  There is an unsatisfiable four-constraint system on
which the shipped solver's common-subexpression rule reaches two of Ermine's error
conditions -- by a run that goes through the minting branch -- and on which NO run of the
cut rule, in any order and of any length, ever reaches any of the three.

Dropping branch (c) loses a refutation.  `Cut.refuter_can_miss` said a sound monotone
refuter CAN be lost by deriving less; this says Ermine's own error conditions ARE lost, on
a system a program could produce. -/
theorem cut_loses_a_refutation :
    (¬ ∃ rho, SModels rho (toS cex)) ∧
      (∃ (m : ℕ) (Gfull : System), BranchSteps m (toS cex) Gfull ∧ RInf Gfull ∧ RDup Gfull) ∧
      (∀ (k : ℕ) (Gcut : System), CutSteps k (toS cex) Gcut →
        ¬ RDup Gcut ∧ ¬ Fires11 Gcut ∧ ¬ RInf Gcut) := by
  refine ⟨cex_unsat, ?_, fun k Gcut h => cut_never_refutes_cex h⟩
  obtain ⟨m, hm⟩ := fullClose_run 2 cex below_cex
  exact ⟨m, toS (fullClose 2 cex), hm, cex_full_fires, cex_full_fires_dup⟩

/-- The same, for the search's own saturation: whatever the fuel, the cut solver's
derived system refutes nothing. -/
theorem cex_cut_never (f : ℕ) :
    ¬ RDup (toS (cutClose f cex)) ∧ ¬ Fires11 (toS (cutClose f cex)) ∧
      ¬ RInf (toS (cutClose f cex)) :=
  cut_never_refutes_cex (cutClose_run f cex below_cex).choose_spec

end CutSearch

end Rowpartition
