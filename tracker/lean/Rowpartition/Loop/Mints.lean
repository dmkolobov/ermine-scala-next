/-
# L5 round 4 (R4.3): a REAL mint count

The round-3 review's F-2 showed that round 3's `LoopStrictKRun.allVars_card_le` is a bound on
the vocabulary held AT ONE STATE, not on the number of minting steps, and gave a
counterexample: the counted relation admitted steps that change nothing and steps that shrink
the vocabulary, so `n` could be anything.  §S-11 then posed the carrier dilemma: over a
MONOTONE carrier ingredient (B) is free but the loop's guard is a lookup over the QUEUES, so
(A) breaks; over the queue-visible `qsys` (A) is within reach but (B) is blocked.

R4.1 settles the second horn: over `qsys`, (B) is not merely blocked but FALSE, and so is the
potential (`Refuted.qstep_pot_increases`).  So this module takes the first horn.

* §1 fixes the count itself.  `KMintRun` counts exactly the steps that ADD A VARIABLE, and
  every `K2StarStep` is one of the two cases (`K2StarStep.allVars_cases`), so the counted
  relation is the star of `K2StarStep` with the count determined, not a restriction of it.
  `KMintRun.mints_le` is the real mint count: **`n ≤ hmeas L rho G₀` for every satisfiable
  `G₀`** -- an explicit bound in the input alone, with the productivity condition
  (`allVars G ⊊ allVars G'`) built into the minting constructor exactly as the brief asks and
  as `K2StarLoopRun.tail`'s `G ≠ G'` does for the library.  The round-3 review's
  `mints_not_bounded` is unprovable for it (§1.4).
* §2 is the monotone carrier for the LOOP -- `Trail`, the union of everything the run has
  ever held -- for which ingredient (B) is free, in one line, from `CarrPres.of_subset`.
* §3 states what is left, `HistDichotomy`, and proves it SUFFICIENT for a loop-level mint
  bound.  §4 says exactly why it is the hard half and what a witness against it looks like.
-/
import Rowpartition.Loop.Supply

set_option maxRecDepth 8000

namespace Rowpartition.Loop

open Rowpartition
open Rowpartition.KeyedRow Rowpartition.KeyedEmpty

/-! ## 1. The count: minting steps of the keyed calculus, counted -/

/-- **A run of the additive keyed calculus with the GENERATIVE steps counted.**  `keep` is a
step that names no new variable; `mint` is one that names exactly one, which is the
productivity condition -- `K2StarStep.allVars_cases` says there is no third case, so this
counts the mints of an arbitrary `K2StarStep` run rather than restricting it. -/
inductive KMintRun (L : Finset Label) : ℕ → System → System → Prop
  | refl (G : System) : KMintRun L 0 G G
  | keep {n : ℕ} {G₀ G G' : System} :
      KMintRun L n G₀ G → K2StarStep G G' → allVars G' = allVars G → KMintRun L n G₀ G'
  | mint {n : ℕ} {G₀ G G' : System} :
      KMintRun L n G₀ G → K2StarStep G G' →
      (∃ w, w ∉ allVars G ∧ allVars G' = insert w (allVars G)) → KMintRun L (n + 1) G₀ G'

/-- Every `K2StarStep` extends a counted run, and the count moves by 0 or 1. -/
theorem KMintRun.step {L : Finset Label} {n : ℕ} {G₀ G G' : System}
    (h : KMintRun L n G₀ G) (hs : K2StarStep G G') :
    KMintRun L n G₀ G' ∨ KMintRun L (n + 1) G₀ G' := by
  rcases hs.allVars_cases with hV | hV
  · exact Or.inl (h.keep hs hV)
  · exact Or.inr (h.mint hs hV)

/-- The counted relation is additive. -/
theorem KMintRun.subset {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : KMintRun L n G₀ G) : G₀ ⊆ G := by
  induction h with
  | refl G => exact Finset.Subset.refl G
  | keep _ hs _ ih => exact fun c hc => hs.subset (ih hc)
  | mint _ hs _ ih => exact fun c hc => hs.subset (ih hc)

/-- **The count IS the vocabulary growth.** -/
theorem KMintRun.card_eq {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : KMintRun L n G₀ G) : (allVars G).card = (allVars G₀).card + n := by
  induction h with
  | refl G => simp
  | keep _ _ hV ih => rw [hV]; exact ih
  | mint _ _ hV ih =>
    obtain ⟨w, hw, hV⟩ := hV
    rw [hV, Finset.card_insert_of_notMem hw, ih]
    omega

/-- The concrete-label pool travels. -/
theorem KMintRun.concSub {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : KMintRun L n G₀ G) : ConcSub L G₀ → ConcSub L G := by
  induction h with
  | refl G => exact fun hcs => hcs
  | keep _ hs _ ih => exact fun hcs => hs.concSub (ih hcs)
  | mint _ hs _ ih => exact fun hcs => hs.concSub (ih hcs)

/-- The potential never grows along a counted run. -/
theorem KMintRun.pot_le {L : Finset Label} {n : ℕ} {G₀ G : System}
    (h : KMintRun L n G₀ G) : ConcSub L G₀ → ∀ rho : Assign, SModels rho G₀ →
      ∃ rho', SModels rho' G ∧ Pot L rho' G ≤ Pot L rho G₀ := by
  induction h with
  | refl G => exact fun _ rho hm => ⟨rho, hm, Nat.le_refl _⟩
  | @keep n G₀ G G' hr hs _ ih =>
    intro hcs rho hm
    obtain ⟨rho1, hm1, hb1⟩ := ih hcs rho hm
    obtain ⟨rho2, hm2, -, hb2⟩ := hs.measure_step (hr.concSub hcs) hm1
    exact ⟨rho2, hm2, le_trans (by simpa [Pot] using hb2) hb1⟩
  | @mint n G₀ G G' hr hs _ ih =>
    intro hcs rho hm
    obtain ⟨rho1, hm1, hb1⟩ := ih hcs rho hm
    obtain ⟨rho2, hm2, -, hb2⟩ := hs.measure_step (hr.concSub hcs) hm1
    exact ⟨rho2, hm2, le_trans (by simpa [Pot] using hb2) hb1⟩

/-- **THE MINT COUNT.**  From a satisfiable `G₀`, the additive keyed calculus takes at most
`hmeas L rho G₀` GENERATIVE steps -- an explicit bound in the input alone.  This is what
round 3's `LoopStrictKRun.allVars_card_le` was mistaken for (round-3 review F-2). -/
theorem KMintRun.mints_le {L : Finset Label} {n : ℕ} {G₀ G : System} {rho : Assign}
    (h : KMintRun L n G₀ G) (hcs : ConcSub L G₀) (hm : SModels rho G₀) :
    n ≤ hmeas L rho G₀ := by
  obtain ⟨rho', -, hb⟩ := h.pot_le hcs rho hm
  have hcard := h.card_eq
  simp only [Pot] at hb
  omega

/-- The same, at the labels the input carries. -/
theorem KMintRun.mints_le_labelsOf {n : ℕ} {G₀ G : System} {rho : Assign}
    (h : KMintRun (labelsOf G₀) n G₀ G) (hm : SModels rho G₀) :
    n ≤ hmeas (labelsOf G₀) rho G₀ :=
  h.mints_le (labelsOf_concSub _) hm

/-- Counted runs compose, adding their counts. -/
theorem KMintRun.trans {L : Finset Label} {m n : ℕ} {G₀ G G' : System}
    (h' : KMintRun L n G G') : KMintRun L m G₀ G → KMintRun L (m + n) G₀ G' := by
  induction h' with
  | refl G => exact fun h => h
  | keep _ hs hV ih => exact fun h => (ih h).keep hs hV
  | @mint n G G1 G2 _ hs hV ih =>
    intro h
    have he : m + (n + 1) = (m + n) + 1 := by omega
    rw [he]
    exact (ih h).mint hs hV

/-- The round-3 review's `mints_not_bounded` -- "from a FIXED satisfiable `G₀` the relation
reaches every `n`" -- is UNPROVABLE for this relation: the count is bounded by the input's own
measure.  The two defects it exploited are gone: `keep` cannot shrink the vocabulary (it fixes
it) and `mint` must add a variable. -/
theorem kmint_bounded (G₀ : System) (rho : Assign) (hm : SModels rho G₀) :
    ∃ N : ℕ, ∀ (n : ℕ) (G : System), KMintRun (labelsOf G₀) n G₀ G → n ≤ N :=
  ⟨hmeas (labelsOf G₀) rho G₀, fun _ _ h => h.mints_le_labelsOf hm⟩

/-! ## 2. The monotone carrier for the LOOP, and ingredient (B) for free

`Trail s H t` is "the run from `s` has reached `t`, and `H` is everything it has ever held".
It is monotone by construction, which is the whole point: `Carried` is monotone under
addition, so ingredient (B) -- the clause `redirect_breaks_carried` blocks over `sys` and
R4.1 REFUTES over `qsys` -- costs one line here. -/

/-- The union of every system the run has held. -/
inductive Trail : State → System → State → Prop
  | refl (s : State) : Trail s (sys s) s
  | tail {s t u : State} {H : System} :
      Trail s H t → step t = .continue u → Trail s (H ∪ sys u) u

theorem Trail.start_subset {s t : State} {H : System} (h : Trail s H t) : sys s ⊆ H := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ _ ih => exact fun c hc => Finset.mem_union_left _ (ih hc)

theorem Trail.cur_subset {s t : State} {H : System} (h : Trail s H t) : sys t ⊆ H := by
  induction h with
  | refl => exact Finset.Subset.refl _
  | tail _ _ _ => exact fun c hc => Finset.mem_union_right _ hc

theorem Trail.reaches {s t : State} {H : System} (h : Trail s H t) : Reaches s t := by
  induction h with
  | refl => exact Reaches.refl _
  | tail _ hst ih => exact Reaches.tail ih hst

theorem Trail.wf {s t : State} {H : System} (hw : Wf s) (h : Trail s H t) : Wf t := by
  induction h with
  | refl => exact hw
  | tail _ hst ih => exact step_wf ih hst

/-- **Ingredient (B), free.**  The carrier only grows, and `Carried` is monotone under
addition -- this is the whole content of the monotone horn of `L5-REVIEW.md` §S-11. -/
theorem Trail.carrPres {H : System} (u : State) : CarrPres H (H ∪ sys u) :=
  CarrPres.of_subset Finset.subset_union_left

/-! ## 3. What is left, and the loop-level bound it gives -/

/-- **THE REMAINING LEMMA, over the monotone carrier.**  Every `continue` step extends the
history by a run of KEYED steps.  Ingredient (B) is already discharged (`Trail.carrPres`), so
this is ingredient (A) and nothing else: the loop's own guard -- `findRHS` / `findResolvent` /
`findConcRow` missing over the QUEUES -- must imply the relation's `¬ Carried H`, over the
whole HISTORY.  §4 says what a witness against it looks like. -/
def HistDichotomy (L : Finset Label) : Prop :=
  ∀ (s s' : State) (H : System) (rho : Assign), Wf s → sys s ⊆ H → SModels rho H →
    ConcSub L H → step s = .continue s' → ∃ n, KMintRun L n H (H ∪ sys s')

/-- Under the remaining lemma, the whole history of a run is a counted run of the keyed
calculus from the input system. -/
theorem trail_kmintRun {L : Finset Label} (h : HistDichotomy L) {s0 t : State} {H : System}
    (hw : Wf s0) (hcs : ConcSub L (sys s0)) (rho : Assign) (hm : SModels rho (sys s0))
    (ht : Trail s0 H t) : ∃ n, KMintRun L n (sys s0) H := by
  induction ht with
  | refl => exact ⟨0, KMintRun.refl _⟩
  | @tail t u H htr hst ih =>
    obtain ⟨n, hn⟩ := ih
    obtain ⟨rho1, hm1, -⟩ := hn.pot_le hcs rho hm
    obtain ⟨k, hk⟩ := h t u H rho1 (htr.wf hw) htr.cur_subset hm1 (hn.concSub hcs) hst
    exact ⟨n + k, hk.trans hn⟩

/-- **THE LOOP-LEVEL MINT COUNT, conditional on the remaining lemma.**  The number of fresh
names a run ever puts into play is at most `hmeas L rho (sys s₀)`, and the whole history --
not merely the state's own system -- stays inside that bound.  Unlike round 3's
`run_qsys_allVars_card_le` this IS a count of minting steps: `KMintRun.card_eq` makes the
count and the vocabulary growth the same number. -/
theorem run_hist_mints_le {L : Finset Label} (h : HistDichotomy L) {s0 t : State} {H : System}
    (hw : Wf s0) (hcs : ConcSub L (sys s0)) (rho : Assign) (hm : SModels rho (sys s0))
    (ht : Trail s0 H t) :
    (allVars H).card ≤ (allVars (sys s0)).card + hmeas L rho (sys s0) := by
  obtain ⟨n, hn⟩ := trail_kmintRun h hw hcs rho hm ht
  have h1 := hn.card_eq
  have h2 := hn.mints_le hcs hm
  omega

/-- ... and in particular the state's own vocabulary is bounded, at every state of the run. -/
theorem run_sys_allVars_le {L : Finset Label} (h : HistDichotomy L) {s0 t : State} {H : System}
    (hw : Wf s0) (hcs : ConcSub L (sys s0)) (rho : Assign) (hm : SModels rho (sys s0))
    (ht : Trail s0 H t) :
    (allVars (sys t)).card ≤ (allVars (sys s0)).card + hmeas L rho (sys s0) :=
  le_trans (Finset.card_le_card (allVars_mono ht.cur_subset))
    (run_hist_mints_le h hw hcs rho hm ht)

/-! ## 4. What refutes the remaining lemma, and what the hunt looked for

`HistDichotomy` forces the potential over the HISTORY not to grow, at every step: -/

/-- **The necessary condition.**  If the remaining lemma holds then at every step the
potential over the history does not grow -- so a step at which it DOES grow refutes it.  Over
`qsys` such a step is `Refuted.qstep_pot_increases`; over the history the corresponding
configuration is a MINT at a key the history already carries, since the added variable costs
`+1` and the key's budget cannot pay for it twice. -/
theorem histDichotomy_pot_le {L : Finset Label} (h : HistDichotomy L) {s s' : State}
    {H : System} {rho : Assign} (hw : Wf s) (hsub : sys s ⊆ H) (hm : SModels rho H)
    (hcs : ConcSub L H) (hst : step s = .continue s') :
    ∃ rho', SModels rho' (H ∪ sys s') ∧ Pot L rho' (H ∪ sys s') ≤ Pot L rho H := by
  obtain ⟨n, hn⟩ := h s s' H rho hw hsub hm hcs hst
  exact hn.pot_le hcs rho hm

/-- **The guard clause, isolated.**  A `K2SplitStep.mint` and a `K2ResStep.mint` both require
`¬ Carried G v K` at the key they mint for.  The loop's own guard is a lookup over the QUEUES
(`findResolvent` / `findConcRow` / `findRHS3`), and R4.1 shows the queues can lose a carrier
the history keeps -- `Refuted.wS_carried2` with `Refuted.wS'_notCarried2` is exactly that
disagreement, at step one of a three-constraint solve.  So the content of `HistDichotomy` is
that the loop never mints INTO that disagreement.  R4.3's hunt looks for a step that does. -/
theorem mint_needs_uncarried {G : System} {c : Constraint} {u : Var} (h : K2MintApp G c u) :
    ¬ Carried G c.lhs c.conc := h.uncarried

/-- **The two guards ARE different predicates**, at step one of a three-constraint solve: the
key `(v2, {l0})` of R4.1's witness is carried by the HISTORY and not by the queue-visible
system the loop's own lookups read.  So `HistDichotomy` is the statement that the loop never
mints into this gap -- which is what the R4.3 hunt tests. -/
theorem hist_qsys_disagree :
    Carried (sys wS ∪ sys wS') 2 ({0} : Row) ∧ ¬ Carried (qsys wS') 2 ({0} : Row) :=
  ⟨Carried.of_resolved (resolved_of_mem
      (Finset.mem_union_left _ (qsys_subset_sys _ wS_memW))), wS'_notCarried2⟩

/-! ## 5. Why the loop's `drawn` counter is NOT a mint count

`Sup.drawn` is the number of ids the loop has taken, and it is the number the harness reports
and L2/L4 match against the compiler.  It is NOT the mint count of §1, and no carrier-based
bound can make it one: `resolution` takes its id BEFORE its guards, so a REUSE costs an id
too.  That is the mechanism behind the `e00346` seed's 1,033 draws from twelve constraints,
and it is why R4.3's bound is stated over the vocabulary of the history rather than over
`drawn`. -/

/-- **`resolution` always draws when its two premises have a lone variable part** -- before
the intersection test and before all three reuse lookups. -/
theorem resolution_draws {fl : Flags} {v : Nat} {rhs1 rhs2 : RHS} {x y : Nat}
    {resolvent concRow emptyRow : SSet Lbl → Option Nat} {su : Sup}
    (hres : fl.resolves = true) (hx : rhs1.abstrSingle? = some x)
    (hy : rhs2.abstrSingle? = some y) :
    (resolution fl v rhs1 rhs2 resolvent concRow emptyRow su).2 = (su.fresh).2 := by
  simp only [resolution, hres, hx, hy, Bool.not_true, Bool.false_eq_true, if_false]
  split
  · rfl
  · split
    · rfl
    · split
      · rfl
      · split
        · rfl
        · rfl

/-- **How many ids one `step` can draw**: at most one for `splitConcrete` and at most one per
processed partition, under the shipped flags.  (`Draws.learnPartitions_drawn` lifted to the
dispatch; every other branch leaves the supply alone.) -/
theorem step_drawn_le {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : step s = .continue s') :
    s'.su.drawn ≤ s.su.drawn + 1 + s.proc.elems.length := by
  simp only [step, State.log] at h
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
        dsimp only
        omega
    · split at h
      · cases hres : makeEmpty s.names r.lhs rest s.proc s.env with
        | error m => rw [hres] at h; exact absurd h (by simp)
        | ok w =>
          obtain ⟨ni, np, e⟩ := w
          rw [hres] at h
          simp only [StepResult.continue.injEq] at h
          subst h
          dsimp only
          omega
      · split at h
        · cases hres : makeConcrete r.lhs r.rhs.conc rest s.proc with
          | error m => rw [hres] at h; exact absurd h (by simp)
          | ok w =>
            obtain ⟨ni, np⟩ := w
            rw [hres] at h
            simp only [StepResult.continue.injEq] at h
            subst h
            dsimp only
            omega
        · split at h
          · rename_i u _
            cases hres : unifyVars s.names u r.lhs rest s.proc s.env with
            | error m => rw [hres] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨ni, np, e⟩ := w
              rw [hres] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              dsimp only
              omega
          · cases hlp : learnPartitions s.flags s.names s.env r.lhs r.rhs rest s.proc s.su with
            | error m => rw [hlp] at h; exact absurd h (by simp)
            | ok w =>
              obtain ⟨learned, su2⟩ := w
              rw [hlp] at h
              simp only [StepResult.continue.injEq] at h
              subst h
              have hb := learnPartitions_drawn hdj hcse hlp
              dsimp only
              omega

/-! ## 6. The remaining lemma is FALSE too: the loop mints into the gap

R4.1 refutes the queue-visible horn; this section refutes the monotone one, so both horns of
`L5-REVIEW.md` §S-11's dilemma are settled negatively, in Lean.

The witness is a four-constraint SATISFIABLE input.  Its first step is R4.1's redirect --
`v0 <- ()` empties `v0`, the erased `v1 <- (v0, (|l0|))` becomes the bare `v1 <- ((|l0|))`, and
`Q.++!` redirects it onto the twin `v2 <- ((|l0|))`.  The queues have now lost every carrier of
the key `(v1, {l0})`.  Its second step dequeues `v1 <- (v3, v4, (|l0|))`, all three of
`splitConcrete`'s lookups miss over the QUEUES, and the rule MINTS -- at a key the HISTORY has
carried since the input.  The potential over the history rises from 12 to 15. -/

/-- `v1 <- (v0, (|l0|))` -- the lone witness that carries `(v1, {l0})` in the history. -/
def mA : LPart := ⟨1, ⟨⟨false, [0]⟩, ⟨false, [wLbl]⟩⟩, none⟩
/-- `v0 <- ()`. -/
def mB : LPart := ⟨0, ⟨⟨false, []⟩, ⟨false, []⟩⟩, none⟩
/-- `v2 <- ((|l0|))` -- the twin the redirect fires on. -/
def mC : LPart := ⟨2, ⟨⟨false, []⟩, ⟨false, [wLbl]⟩⟩, none⟩
/-- `v1 <- (v3, v4, (|l0|))` -- the premise `splitConcrete` will mint on. -/
def mD : LPart := ⟨1, ⟨⟨false, [3, 4]⟩, ⟨false, [wLbl]⟩⟩, none⟩

/-- The redirect partition the first step inserts. -/
def mR : LPart := ⟨2, ⟨⟨false, [1]⟩, ⟨false, []⟩⟩, some .commonPartition⟩
/-- The minted definition of the fresh id. -/
def mZ : LPart := ⟨100, ⟨⟨false, [3, 4]⟩, ⟨false, []⟩⟩, some .splitConcrete⟩
/-- The minted re-expression of the premise. -/
def mP : LPart := ⟨1, ⟨⟨false, [100]⟩, ⟨false, [wLbl]⟩⟩, some .splitConcrete⟩

/-- The witness's initial state. -/
def mS0 : State :=
  { incm := PQueue.ofList [mA, mB, mC, mD], proc := PQueue.empty, env := {},
    su := wSup, trace := [], flags := {}, names := wNames, site := "t0", su0 := 100 }

def mNext (s : State) : State :=
  match step s with
  | .continue t => t
  | .done t => t
  | .died _ t => t

/-- After the redirect. -/
def mS1 : State := mNext mS0
/-- After the mint. -/
def mS2 : State := mNext mS1

theorem mS0_step : step mS0 = .continue mS1 := rfl
theorem mS1_step : step mS1 = .continue mS2 := rfl

/-- The id the second step mints. -/
theorem mS2_drawn : mS2.su.drawn = 1 := rfl

theorem mS0_parts : mS0.parts = [mB, mA, mD, mC] := rfl
theorem mS1_parts : mS1.parts = [mR, mD, mC] := rfl
theorem mS0_env : mS0.env.binds = [] := rfl
theorem mS1_env : mS1.env.binds = [(0, EnvVal.emptyRow)] := rfl

theorem mS2_parts : mS2.parts = [mZ, mR, mP, mC, mD] := rfl

theorem mA_tc : mA.toConstraint = mk 1 {0} ({0} : Row) := by
  simp [LPart.toConstraint, mA, wLbl]
theorem mB_tc : mB.toConstraint = mk 0 ∅ (∅ : Row) := by simp [LPart.toConstraint, mB]
theorem mC_tc : mC.toConstraint = mk 2 ∅ ({0} : Row) := by
  simp [LPart.toConstraint, mC, wLbl]
theorem mD_tc : mD.toConstraint = mk 1 {3, 4} ({0} : Row) := by
  simp [LPart.toConstraint, mD, wLbl]
theorem mR_tc : mR.toConstraint = mk 2 {1} (∅ : Row) := by simp [LPart.toConstraint, mR]
theorem mZ_tc : mZ.toConstraint = mk 100 {3, 4} (∅ : Row) := by simp [LPart.toConstraint, mZ]
theorem mP_tc : mP.toConstraint = mk 1 {100} ({0} : Row) := by
  simp [LPart.toConstraint, mP, wLbl]

/-- The history after the redirect: the input system plus the redirect's link. -/
def mH1 : System :=
  {mk 0 ∅ (∅ : Row), mk 1 {0} ({0} : Row), mk 1 {3, 4} ({0} : Row), mk 2 ∅ ({0} : Row),
   mk 2 {1} (∅ : Row)}

/-- ... and after the mint: two more constraints and one more variable. -/
def mH2 : System :=
  {mk 0 ∅ (∅ : Row), mk 1 {0} ({0} : Row), mk 1 {3, 4} ({0} : Row), mk 2 ∅ ({0} : Row),
   mk 2 {1} (∅ : Row), mk 100 {3, 4} (∅ : Row), mk 1 {100} ({0} : Row)}

theorem sys_mS0 :
    sys mS0 = ({mk 0 ∅ (∅ : Row), mk 1 {0} ({0} : Row), mk 1 {3, 4} ({0} : Row),
                mk 2 ∅ ({0} : Row)} : System) := by
  have h : sys mS0 = ({mk 0 ∅ (∅ : Row), mk 1 {0} ({0} : Row), mk 1 {3, 4} ({0} : Row),
      mk 2 ∅ ({0} : Row)} : System) := by
    simp only [sys, mS0_parts, mS0_env, Env.sys, List.map_cons, List.map_nil,
      List.toFinset_cons, List.toFinset_nil, mA_tc, mB_tc, mC_tc, mD_tc,
      Finset.union_empty]
    ext c
    simp only [Finset.mem_insert, Finset.mem_singleton]
    tauto
  exact h

theorem sys_mS1 :
    sys mS1 = ({mk 2 {1} (∅ : Row), mk 1 {3, 4} ({0} : Row), mk 2 ∅ ({0} : Row),
                mk 0 ∅ (∅ : Row)} : System) := by
  simp only [sys, mS1_parts, mS1_env, Env.sys, List.map_cons, List.map_nil,
    List.toFinset_cons, List.toFinset_nil, mR_tc, mC_tc, mD_tc, EnvVal.toConstraint]
  ext c
  simp only [Finset.mem_union, Finset.mem_insert, Finset.mem_singleton]
  tauto

theorem sys_mS2 :
    sys mS2 = ({mk 100 {3, 4} (∅ : Row), mk 2 {1} (∅ : Row), mk 1 {100} ({0} : Row),
                mk 2 ∅ ({0} : Row), mk 1 {3, 4} ({0} : Row), mk 0 ∅ (∅ : Row)} : System) := by
  have henv : mS2.env.binds = [(0, EnvVal.emptyRow)] := rfl
  simp only [sys, mS2_parts, henv, Env.sys, List.map_cons, List.map_nil,
    List.toFinset_cons, List.toFinset_nil, mZ_tc, mR_tc, mP_tc, mC_tc, mD_tc,
    EnvVal.toConstraint]
  ext c
  simp only [Finset.mem_union, Finset.mem_insert, Finset.mem_singleton]
  tauto

theorem mH1_eq : sys mS0 ∪ sys mS1 = mH1 := by
  rw [sys_mS0, sys_mS1, mH1]
  ext c
  simp only [Finset.mem_union, Finset.mem_insert, Finset.mem_singleton]
  tauto

theorem mH2_eq : mH1 ∪ sys mS2 = mH2 := by
  rw [sys_mS2, mH1, mH2]
  ext c
  simp only [Finset.mem_union, Finset.mem_insert, Finset.mem_singleton]
  tauto

theorem mS1_sub : sys mS1 ⊆ mH1 := by rw [← mH1_eq]; exact Finset.subset_union_right

/-! ### 6.1 The budgets on either side of the mint -/

theorem uncarried_wL (G : System) (v : Var) :
    uncarried wL G v = (if Carried G v (∅ : Row) then 0 else 1)
      + (if Carried G v ({0} : Row) then 0 else 1) := by
  rw [uncarried, wL_powerset]
  by_cases h1 : Carried G v (∅ : Row) <;> by_cases h2 : Carried G v ({0} : Row) <;>
    simp [Finset.filter_insert, Finset.filter_singleton, h1, h2]

/-- No constraint of `G` is about `v` at all. -/
theorem not_carried_of_shape {G : System} {v : Var} {K : Row}
    (h1 : ∀ z, mk v {z} K ∉ G) (h2 : ∀ C, mk v ∅ C ∉ G) : ¬ Carried G v K := by
  rintro (hr | hc)
  · obtain ⟨z, hz⟩ := (resolved_iff _ _ _).mp hr; exact h1 z hz
  · obtain ⟨C, z, hC, -⟩ := (concCarried_iff _ _ _).mp hc; exact h2 C hC

theorem mH1_sub_mH2 : mH1 ⊆ mH2 := by
  intro c hc
  simp only [mH1, mH2, Finset.mem_insert, Finset.mem_singleton] at hc ⊢
  tauto

theorem carried_mH1_0 (K : Row) : Carried mH1 0 K := by
  refine Carried.of_conc (z := 0) (C := (∅ : Row)) ?_ ?_ <;> simp [mH1]

theorem carried_mH1_2_empty : Carried mH1 2 (∅ : Row) := by
  refine Carried.of_conc (z := 2) (C := ({0} : Row)) (by simp [mH1]) ?_
  have h : ({0} : Row) \ (∅ : Row) = ({0} : Row) := by simp
  rw [h]; simp [mH1]

theorem carried_mH1_2_zero : Carried mH1 2 ({0} : Row) := by
  refine Carried.of_conc (z := 0) (C := ({0} : Row)) (by simp [mH1]) ?_
  have h : ({0} : Row) \ ({0} : Row) = (∅ : Row) := by simp
  rw [h]; simp [mH1]

theorem carried_mH1_1_zero : Carried mH1 1 ({0} : Row) :=
  Carried.of_resolved (resolved_of_mem (z := 0) (by simp [mH1]))

theorem not_carried_mH2_1_empty : ¬ Carried mH2 1 (∅ : Row) := by
  refine not_carried_of_shape (fun z hz => ?_) (fun C hC => ?_)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hz
    rcases hz with ⟨h, -, -⟩ | ⟨-, -, h⟩ | ⟨-, h, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ |
      ⟨-, -, h⟩
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd (congrArg Finset.card h) (by simp)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hC
    rcases hC with ⟨h, -, -⟩ | ⟨-, h, -⟩ | ⟨-, h, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ |
      ⟨-, h, -⟩
    · exact absurd h (by decide)
    · exact absurd h.symm (by decide)
    · exact absurd h.symm (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h.symm (by decide)

theorem not_carried_mH2_3 (K : Row) : ¬ Carried mH2 3 K := by
  refine not_carried_of_shape (fun z hz => ?_) (fun C hC => ?_)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hz
    rcases hz with ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ |
      ⟨h, -, -⟩ <;> exact absurd h (by decide)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hC
    rcases hC with ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ |
      ⟨h, -, -⟩ <;> exact absurd h (by decide)

theorem not_carried_mH2_4 (K : Row) : ¬ Carried mH2 4 K := by
  refine not_carried_of_shape (fun z hz => ?_) (fun C hC => ?_)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hz
    rcases hz with ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ |
      ⟨h, -, -⟩ <;> exact absurd h (by decide)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hC
    rcases hC with ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ |
      ⟨h, -, -⟩ <;> exact absurd h (by decide)

theorem not_carried_mH2_100 (K : Row) : ¬ Carried mH2 100 K := by
  refine not_carried_of_shape (fun z hz => ?_) (fun C hC => ?_)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hz
    rcases hz with ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨-, h, -⟩ |
      ⟨h, -, -⟩
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd (congrArg Finset.card h) (by simp)
    · exact absurd h (by decide)
  · simp only [mH2, Finset.mem_insert, Finset.mem_singleton,
      Rowpartition.NameLoss.mk_eq_iff] at hC
    rcases hC with ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨h, -, -⟩ | ⟨-, h, -⟩ |
      ⟨h, -, -⟩
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h (by decide)
    · exact absurd h.symm (by decide)
    · exact absurd h (by decide)

theorem not_carried_mH1_1_empty : ¬ Carried mH1 1 (∅ : Row) :=
  fun h => not_carried_mH2_1_empty (CarrPres.of_subset mH1_sub_mH2 1 _ h)
theorem not_carried_mH1_3 (K : Row) : ¬ Carried mH1 3 K :=
  fun h => not_carried_mH2_3 K (CarrPres.of_subset mH1_sub_mH2 3 K h)
theorem not_carried_mH1_4 (K : Row) : ¬ Carried mH1 4 K :=
  fun h => not_carried_mH2_4 K (CarrPres.of_subset mH1_sub_mH2 4 K h)
theorem carried_mH2_0 (K : Row) : Carried mH2 0 K :=
  CarrPres.of_subset mH1_sub_mH2 0 K (carried_mH1_0 K)
theorem carried_mH2_2_empty : Carried mH2 2 (∅ : Row) :=
  CarrPres.of_subset mH1_sub_mH2 2 _ carried_mH1_2_empty
theorem carried_mH2_2_zero : Carried mH2 2 ({0} : Row) :=
  CarrPres.of_subset mH1_sub_mH2 2 _ carried_mH1_2_zero
theorem carried_mH2_1_zero : Carried mH2 1 ({0} : Row) :=
  CarrPres.of_subset mH1_sub_mH2 1 _ carried_mH1_1_zero

theorem allVars_mH1 : allVars mH1 = ({0, 1, 2, 3, 4} : Finset Var) := by
  simp only [mH1, allVars, Finset.biUnion_insert, Finset.singleton_biUnion, lhs_mk, vset_mk]
  decide

theorem allVars_mH2 : allVars mH2 = ({0, 1, 2, 3, 4, 100} : Finset Var) := by
  simp only [mH2, allVars, Finset.biUnion_insert, Finset.singleton_biUnion, lhs_mk, vset_mk]
  decide

/-- The model of the witness: `v1` and `v2` are `{l0}`, everything else is empty. -/
def mRho : Assign := fun v => if v = 1 ∨ v = 2 then {0} else ∅

theorem hmeas_mH1 : hmeas wL mRho mH1 = 7 := by
  rw [hmeas, allVars_mH1,
    show ({0, 1, 2, 3, 4} : Finset Var) = insert 0 (insert 1 (insert 2 (insert 3 {4}))) from rfl,
    Finset.sum_insert (by decide), Finset.sum_insert (by decide), Finset.sum_insert (by decide),
    Finset.sum_insert (by decide), Finset.sum_singleton]
  rw [uncarried_wL, uncarried_wL, uncarried_wL, uncarried_wL, uncarried_wL]
  rw [if_pos (carried_mH1_0 _), if_pos (carried_mH1_0 _),
    if_neg not_carried_mH1_1_empty, if_pos carried_mH1_1_zero,
    if_pos carried_mH1_2_empty, if_pos carried_mH1_2_zero,
    if_neg (not_carried_mH1_3 _), if_neg (not_carried_mH1_3 _),
    if_neg (not_carried_mH1_4 _), if_neg (not_carried_mH1_4 _)]
  simp [mRho]

theorem hmeas_mH2_mRho : hmeas wL mRho mH2 = 9 := by
  rw [hmeas, allVars_mH2,
    show ({0, 1, 2, 3, 4, 100} : Finset Var)
      = insert 0 (insert 1 (insert 2 (insert 3 (insert 4 {100})))) from rfl,
    Finset.sum_insert (by decide), Finset.sum_insert (by decide), Finset.sum_insert (by decide),
    Finset.sum_insert (by decide), Finset.sum_insert (by decide), Finset.sum_singleton]
  rw [uncarried_wL, uncarried_wL, uncarried_wL, uncarried_wL, uncarried_wL, uncarried_wL]
  rw [if_pos (carried_mH2_0 _), if_pos (carried_mH2_0 _),
    if_neg not_carried_mH2_1_empty, if_pos carried_mH2_1_zero,
    if_pos carried_mH2_2_empty, if_pos carried_mH2_2_zero,
    if_neg (not_carried_mH2_3 _), if_neg (not_carried_mH2_3 _),
    if_neg (not_carried_mH2_4 _), if_neg (not_carried_mH2_4 _),
    if_neg (not_carried_mH2_100 _), if_neg (not_carried_mH2_100 _)]
  simp [mRho]

/-! ### 6.2 The witness is well formed and satisfiable -/

theorem mS0_wf : Wf mS0 := by
  refine wf_of_nodup ?_ ?_ ?_
  · intro p hp
    have he : mS0.incm.elems = [mB, mA, mD, mC] := rfl
    rw [he] at hp
    rcases List.mem_cons.mp hp with rfl | hp1
    · exact ⟨by simp [mB, SSet.Nodup], by simp [mB, SSet.Nodup]⟩
    rcases List.mem_cons.mp hp1 with rfl | hp2
    · exact ⟨by simp [mA, SSet.Nodup], by simp [mA, SSet.Nodup]⟩
    rcases List.mem_cons.mp hp2 with rfl | hp3
    · exact ⟨by simp [mD, SSet.Nodup], by simp [mD, SSet.Nodup]⟩
    rcases List.mem_cons.mp hp3 with rfl | hp4
    · exact ⟨by simp [mC, SSet.Nodup], by simp [mC, SSet.Nodup]⟩
    · simp at hp4
  · intro p hp
    have he : mS0.proc.elems = [] := rfl
    rw [he] at hp
    simp at hp
  · intro x hx y hy _
    have hl : mS0.labels = [wLbl, wLbl, wLbl] := rfl
    rw [hl] at hx hy
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hx hy
    rcases hx with rfl | rfl | rfl <;> rcases hy with rfl | rfl | rfl <;> rfl

theorem mS1_wf : Wf mS1 := step_wf mS0_wf mS0_step

theorem mH1_models : SModels mRho mH1 := by
  intro c hc
  simp only [mH1, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl | rfl | rfl <;> rw [sat_mk_iff]
  · exact ⟨by simp [mRho], by simp, by simp⟩
  · refine ⟨by simp [mRho], ?_, ?_⟩
    · intro v hv; simp only [Finset.mem_singleton] at hv; subst hv; simp [mRho]
    · intro v hv w hw hvw
      simp only [Finset.mem_singleton] at hv hw
      exact absurd (hv.trans hw.symm) hvw
  · refine ⟨by simp [mRho], ?_, ?_⟩
    · intro v hv
      simp only [Finset.mem_insert, Finset.mem_singleton] at hv
      rcases hv with rfl | rfl <;> simp [mRho]
    · intro v hv w hw hvw
      simp only [Finset.mem_insert, Finset.mem_singleton] at hv hw
      rcases hv with rfl | rfl <;> rcases hw with rfl | rfl <;> simp [mRho] at hvw ⊢
  · exact ⟨by simp [mRho], by simp, by simp⟩
  · refine ⟨by simp [mRho], ?_, ?_⟩
    · intro v hv; simp only [Finset.mem_singleton] at hv; subst hv; simp
    · intro v hv w hw hvw
      simp only [Finset.mem_singleton] at hv hw
      exact absurd (hv.trans hw.symm) hvw

theorem mH1_concSub : ConcSub wL mH1 := by
  intro c hc
  simp only [mH1, Finset.mem_insert, Finset.mem_singleton] at hc
  rcases hc with rfl | rfl | rfl | rfl | rfl <;> simp [wL]

/-- Every model of the history after the mint agrees with `mRho` on its whole vocabulary:
the system pins all six variables. -/
theorem mH2_pinned {rho : Assign} (h : SModels rho mH2) : ∀ v ∈ allVars mH2, rho v = mRho v := by
  have h0 := h (mk 0 ∅ (∅ : Row)) (by simp [mH2])
  have h2 := h (mk 2 ∅ ({0} : Row)) (by simp [mH2])
  have h21 := h (mk 2 {1} (∅ : Row)) (by simp [mH2])
  have h134 := h (mk 1 {3, 4} ({0} : Row)) (by simp [mH2])
  have h100 := h (mk 100 {3, 4} (∅ : Row)) (by simp [mH2])
  rw [sat_mk_iff] at h0 h2 h21 h134 h100
  have e0 : rho 0 = ∅ := by simpa using h0.1
  have e2 : rho 2 = {0} := by simpa using h2.1
  have e1 : rho 1 = {0} := by
    have : rho 2 = rho 1 := by simpa using h21.1
    rw [← this]; exact e2
  have hb : ({3, 4} : Finset Var).biUnion rho = rho 3 ∪ rho 4 := by
    rw [show ({3, 4} : Finset Var) = insert 3 {4} from rfl, Finset.biUnion_insert,
      Finset.singleton_biUnion]
  have eun : rho 1 = ({0} : Row) ∪ (rho 3 ∪ rho 4) := by rw [← hb]; exact h134.1
  have e3 : rho 3 = ∅ := by
    rw [Finset.eq_empty_iff_forall_notMem]
    intro x hx
    have hx0 : x ∈ ({0} : Row) := by
      rw [e1] at eun
      have : x ∈ ({0} : Row) ∪ (rho 3 ∪ rho 4) := Finset.mem_union_right _ (by simp [hx])
      rwa [← eun] at this
    exact (Finset.disjoint_left.mp (h134.2.1 3 (by simp)) hx0) hx
  have e4 : rho 4 = ∅ := by
    rw [Finset.eq_empty_iff_forall_notMem]
    intro x hx
    have hx0 : x ∈ ({0} : Row) := by
      rw [e1] at eun
      have : x ∈ ({0} : Row) ∪ (rho 3 ∪ rho 4) := Finset.mem_union_right _ (by simp [hx])
      rwa [← eun] at this
    exact (Finset.disjoint_left.mp (h134.2.1 4 (by simp)) hx0) hx
  have e100 : rho 100 = ∅ := by
    have : rho 100 = (∅ : Row) ∪ (rho 3 ∪ rho 4) := by rw [← hb]; exact h100.1
    rw [this, e3, e4]; simp
  intro v hv
  rw [allVars_mH2] at hv
  simp only [Finset.mem_insert, Finset.mem_singleton] at hv
  rcases hv with rfl | rfl | rfl | rfl | rfl | rfl <;> simp [mRho, e0, e1, e2, e3, e4, e100]

/-! ### 6.3 The refutation -/

/-- **The history the refutation uses is a real run history**, not an arbitrary superset:
`mH1` is exactly what `Trail` accumulates over the witness's first step. -/
theorem mS1_trail : Trail mS0 mH1 mS1 := by
  have h := (Trail.refl mS0).tail mS0_step
  rwa [mH1_eq] at h

/-- The arithmetic both refutations share: `5 + 7 = 12` before the mint, `6 + 9 = 15` after. -/
theorem pot_mH2_gt {rho : Assign} (h : SModels rho mH2) :
    Pot wL mRho mH1 < Pot wL rho mH2 := by
  have hcong : hmeas wL rho mH2 = hmeas wL mRho mH2 := hmeas_congr (mH2_pinned h)
  rw [Pot, Pot, allVars_mH2, allVars_mH1, hcong, hmeas_mH2_mRho, hmeas_mH1]
  decide

/-- **THE REMAINING LEMMA IS FALSE.**  At the witness's second step the loop mints at the key
`(v1, {l0})`, which the history has carried since the input (`mk 1 {0} {0} ∈ mH1`), so the
potential over the monotone carrier rises from `5 + 7 = 12` to `6 + 9 = 15` -- and
`histDichotomy_pot_le` forbids exactly that.  With R4.1's `qStepDichotomy_false`, BOTH horns of
`L5-REVIEW.md` §S-11's carrier dilemma are now refuted in Lean. -/
theorem histDichotomy_false : ¬ HistDichotomy wL := by
  intro h
  obtain ⟨rho', hm', hle⟩ :=
    histDichotomy_pot_le h mS1_wf mS1_sub mH1_models mH1_concSub mS1_step
  rw [mH2_eq] at hm' hle
  exact absurd hle (Nat.not_le.mpr (pot_mH2_gt hm'))

/-- The remaining lemma RELATIVISED to the histories the loop actually builds -- the analogue
of R4.1's `QStepDichotomy'`, and the weakest form that still gives the bound. -/
def HistDichotomyR (L : Finset Label) : Prop :=
  ∀ (s0 s s' : State) (H : System) (rho : Assign), Trail s0 H s → Wf s0 → SModels rho H →
    ConcSub L H → step s = .continue s' → ∃ n, KMintRun L n H (H ∪ sys s')

/-- **... and it is false too**, by the same witness, because `mH1` is a `Trail` history. -/
theorem histDichotomyR_false : ¬ HistDichotomyR wL := by
  intro h
  obtain ⟨n, hn⟩ :=
    h mS0 mS1 mS2 mH1 mRho mS1_trail mS0_wf mH1_models mH1_concSub mS1_step
  obtain ⟨rho', hm', hle⟩ := hn.pot_le mH1_concSub mRho mH1_models
  rw [mH2_eq] at hm' hle
  exact absurd hle (Nat.not_le.mpr (pot_mH2_gt hm'))

/-- The key the mint fires at is carried by the history from the input onwards. -/
theorem mH1_carries_the_key : Carried mH1 1 ({0} : Row) := carried_mH1_1_zero

/-- The label pool of the witness is `{l0}`, so the refutation is at the pool the bound would
be stated with. -/
theorem labelsOf_mH1 : labelsOf mH1 = wL := by
  simp only [mH1, labelsOf, Finset.biUnion_insert, Finset.singleton_biUnion, conc_mk]
  decide

end Rowpartition.Loop
