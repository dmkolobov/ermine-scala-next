/-
# L5 round 8: the mint CHAIN DEPTH — the instrument, and the decomposition of the mint bound

Round 7 leaves the open problem as one quantity.  `VocFix.terminates_of_drawsAtMost` says that
ANY bound `k` on the loop's draws gives `Terminates`; `VocFix.drawn_unbounded_of_not_terminates`
says a divergence draws unboundedly many ids; and `VocFix.reaches_concSub` says the LABEL POOL
is fixed along every run, unconditionally.  The loop mints at keys `(v, C)` with `C` from a
fixed finite set, so a divergence must mint at unboundedly many distinct left-hand sides `v` —
and each `v` beyond the input's own is itself a minted name.  A divergence is therefore an
infinite CHAIN

    v₀ → v₁ → v₂ → …        `vᵢ₊₁` drawn while a partition of `vᵢ` is dequeued.

This module has two halves.

**§1–§4, the instrument.**  `depthRun` is `pumpRun` with a depth assignment threaded through it:
every id present at the FIRST dequeue (the input's own variables and whatever `PQueue.build`
minted) has depth `0`, and an id drawn at a step whose dequeued premise has left-hand side `v`
has depth `depth v + 1`.  Every draw is recorded with its rule (`splitConcrete`'s mint is the
first draw of a `learn` step, because `splitConcrete` is `learnPartitions`' fold INITIAL VALUE
and draws at most once — `Draws.splitConcrete_drawn`; every later draw of the step is
`resolution`'s), the site's depth, and the key's re-mint index.  `Loop/Main.lean`'s `--depth`
prints it, on the `--replay` path and on the `json:` path both.

**§5–§8, the decomposition.**  `terminates_of_chainRun` is the theorem the measurement is
for: if along every run from `s₀` every drawn id has depth at most `D` and every key `(v, C)` is
minted at most `R` times, then the loop draws at most

    n · D · (2 ^ m · R) ^ D          (`chainBound n m D R`)

ids, where `n` is the input's variable count and `m = |L|` its label pool — and hence
`Terminates s₀`.  The counting is the obvious one and it is done honestly: the ids of depth
`d + 1` inject into (ids of depth `d`) × (subsets of `L`) × (`Fin R`) by
`z ↦ (site z, key z, index z)`, which is exactly hypothesis (b); depth `0` is the input's own
variables, which is `n`; and the ids drawn along a run are DISTINCT because `Sup.fresh` never
returns an id it can still reach (`SupOk`).  Nothing here is about `step` except through the
two hypotheses, which is the point: the theorem is the socket, and §1's instrument is what
decides its two hypotheses per solve.
-/
import Rowpartition.Loop.VocFix

set_option maxRecDepth 100000
set_option maxHeartbeats 2000000

namespace Rowpartition.Loop

open Rowpartition

/-! ## 1. The depth assignment -/

/-- An id's depth, as an association list.  Absent means `0`: an id nobody drew is an input
variable. -/
abbrev DMap := List (Nat × Nat)

/-- Look up a depth; an unrecorded id is an input variable, at depth `0`. -/
def dget (m : DMap) (z : Nat) : Nat :=
  match m.find? (fun p => p.1 == z) with
  | none => 0
  | some p => p.2

/-- Record a depth.  The FIRST write wins, so a re-used id keeps the depth of the draw that
made it. -/
def dput (m : DMap) (z d : Nat) : DMap :=
  if m.any (fun p => p.1 == z) then m else (z, d) :: m

/-- The ids the supply will hand out next, in order.  `Sup.fresh` is a function of the supply
alone, so the ids a run draws are determined by the supply it starts from and how many it
draws — which is what makes the depth of a draw observable without re-implementing any rule. -/
def drawSeq (su : Sup) : Nat → List Nat
  | 0 => []
  | k + 1 => (su.fresh).1 :: drawSeq (su.fresh).2 k

/-- Every label the state's partitions mention: the input's label pool `L`. -/
def stateLabels (s : State) : SSet Lbl :=
  s.parts.foldl (fun acc p => acc.concat p.rhs.conc) SSet.empty

/-- A key's count in a tally, BEFORE it is bumped: the key's re-mint index. -/
def tallyGet (t : List (MKey × Nat)) (k : MKey) : Nat :=
  match t.find? (fun p => mkeyEq p.1 k) with
  | none => 0
  | some p => p.2

/-- Bump a depth histogram. -/
def bumpHist (h : List (Nat × Nat)) (d : Nat) : List (Nat × Nat) :=
  if h.any (fun p => p.1 == d) then h.map (fun p => if p.1 == d then (p.1, p.2 + 1) else p)
  else h ++ [(d, 1)]

/-! ## 2. What one instrumented solve reports -/

/-- The chain report of one solve. -/
structure DepthRep where
  /-- Dequeues taken. -/
  steps : Nat := 0
  /-- `SOLVED`, `REJECTED`, `FUEL` or `BUILD`. -/
  verdict : String := "SOLVED"
  /-- `Sup.drawn` at the end. -/
  drawn : Nat := 0
  /-- `Sup.drawn` at the FIRST dequeue: `PQueue.build` runs before the loop. -/
  drawn0 : Nat := 0
  /-- The depth of every id in play. -/
  dmap : DMap := []
  /-- One record per DRAW: `(step, rule, site, site's depth, id, id's depth, key index)`.
  The rule is `split` for `splitConcrete`'s mint and `res` for `resolution`'s draw; the key
  index is the draw's index at its DEQUEUE key `(dequeued lhs, dequeued concrete part)`, which
  is `Chain`'s `idx`. -/
  chain : List (Nat × String × Nat × Nat × Nat × Nat × Nat) := []
  /-- `depth ↦ how many ids were drawn at it`. -/
  hist : List (Nat × Nat) := []
  /-- The largest depth of a drawn id. -/
  maxDepth : Nat := 0
  /-- `splitConcrete` mints. -/
  nSplit : Nat := 0
  /-- `resolution` draws. -/
  nRes : Nat := 0
  /-- The `splitConcrete` GUARD-key tally (round 5's `tally`). -/
  gtally : List (MKey × Nat) := []
  /-- The CARRIER-key tally (round 5's `ctally`). -/
  ctally : List (MKey × Nat) := []
  /-- **The DEQUEUE-key tally**, which is the one `Chain` needs.  A draw's key is the DEQUEUED
  premise's `(left-hand side, concrete part)`; every draw of a step shares it, and the draw's
  index is this counter at the time.  The guard and carrier tallies count only the draws that
  install something, so neither of them bounds `resolution`'s REUSE draws (it takes its `fresh`
  BEFORE its guards) -- this one counts every draw, and is therefore the `R` of
  `terminates_of_chainRun`. -/
  dtally : List (MKey × Nat) := []
  /-- Variables at the first dequeue: the input's `n`. -/
  nVars : Nat := 0
  /-- Partitions at the first dequeue. -/
  nParts : Nat := 0
  /-- Labels at the first dequeue: the input's `m = |L|`. -/
  nLbl : Nat := 0

/-- The largest number of `splitConcrete` mints at one guard key. -/
def DepthRep.maxRemint (r : DepthRep) : Nat := r.gtally.foldl (fun a p => max a p.2) 0

/-- The largest number of fresh carriers installed at one key. -/
def DepthRep.maxCRemint (r : DepthRep) : Nat := r.ctally.foldl (fun a p => max a p.2) 0

/-- **The largest number of DRAWS at one dequeue key** -- `Chain`'s `R`. -/
def DepthRep.maxDKey (r : DepthRep) : Nat := r.dtally.foldl (fun a p => max a p.2) 0

/-! ## 3. The run -/

/-- Attach the step's rule attribution and depths to the ids it drew.  `splitConcrete` is
`learnPartitions`' fold INITIAL VALUE and draws at most once, so when the step mints at a
guard key that mint is the step's FIRST draw and every later draw is `resolution`'s. -/
def chainRecs (stp : Nat) (v d didx : Nat) (hasSplit : Bool) :
    List Nat → Nat → List (Nat × String × Nat × Nat × Nat × Nat × Nat)
  | [], _ => []
  | z :: zs, i =>
    (stp, (if hasSplit && i == 0 then "split" else "res"), v, d, z, d + 1, didx + i) ::
      chainRecs stp v d didx hasSplit zs (i + 1)

/-- Run the loop with the depth assignment, the two key tallies and the chain log.  The fuel is
the same bound `run` uses. -/
def depthRun : Nat → State → DepthRep → DepthRep
  | 0, s, rep => { rep with verdict := "FUEL", drawn := s.su.drawn }
  | n + 1, s, rep =>
    let rep :=
      if rep.steps == 0 then
        { rep with dmap := (stateVars s).toList.map (fun w => (w, 0)),
                   drawn0 := s.su.drawn,
                   nVars := (stateVars s).size,
                   nParts := s.parts.length,
                   nLbl := (stateLabels s).size }
      else rep
    let v := match s.incm.dequeue with
      | none => 0
      | some (r, _) => r.lhs
    let d := dget rep.dmap v
    let dk : MKey := match s.incm.dequeue with
      | none => (0, SSet.empty)
      | some (r, _) => (r.lhs, r.rhs.conc)
    let didx := tallyGet rep.dtally dk
    let gk := splitMintKey s
    match step s with
    | .done s' => { rep with verdict := "SOLVED", drawn := s'.su.drawn }
    | .died _ s' => { rep with verdict := "REJECTED", drawn := s'.su.drawn }
    | .continue s' =>
      let zs := drawSeq s.su (s'.su.drawn - s.su.drawn)
      let ck := carrierKeys s s'
      let recs := chainRecs rep.steps v d didx gk.isSome zs 0
      let rep :=
        { rep with
            dmap := zs.foldl (fun m z => dput m z (d + 1)) rep.dmap,
            chain := rep.chain ++ recs,
            hist := zs.foldl (fun h _ => bumpHist h (d + 1)) rep.hist,
            maxDepth := if zs.isEmpty then rep.maxDepth else max rep.maxDepth (d + 1),
            nSplit := rep.nSplit + (if gk.isSome then 1 else 0),
            nRes := rep.nRes + zs.length - (if gk.isSome then 1 else 0),
            gtally := match gk with
              | none => rep.gtally
              | some key => bumpKey rep.gtally key,
            ctally := ck.foldl bumpKey rep.ctally,
            dtally := zs.foldl (fun t _ => bumpKey t dk) rep.dtally }
      depthRun n s' { rep with steps := rep.steps + 1 }

/-! ## 4. The depth of a site, as the chain's own statement

The instrument's `dmap` is exactly the chain: an id's depth is one more than the depth of the
left-hand side that was dequeued when it was drawn.  These two `rfl`-facts pin the reading of
the report's columns; the mathematics is §5 onwards. -/

/-- An id nobody drew reads as depth `0`. -/
theorem dget_nil (z : Nat) : dget [] z = 0 := rfl

/-- A depth just written reads back. -/
theorem dget_dput_self {m : DMap} {z d : Nat} (h : m.any (fun p => p.1 == z) = false) :
    dget (dput m z d) z = d := by
  unfold dput dget
  rw [if_neg (by simp [h])]
  simp [List.find?]

/-! ## 5. The supply's draws are DISTINCT

`Sup.fresh` hands out an id it can still reach and then cannot reach it again
(`RefineLearn.fresh_reach`, `RefineLearn.fresh_reach_mono`), so under `SupOk` the sequence
`drawSeq` enumerates distinct ids.  That is what turns "the run drew `k` ids" into "the run
drew a `k`-element SET of ids", which is what the counting in §7 bounds. -/

/-- The supply after `k` draws. -/
def Sup.after (su : Sup) : Nat → Sup
  | 0 => su
  | k + 1 => (su.after k).fresh.2

/-- The `k`-th id a supply hands out. -/
def drawAt (su : Sup) (k : Nat) : Nat := (su.after k).fresh.1

theorem after_supOk {su : Sup} (h : SupOk su) : ∀ k, SupOk (su.after k)
  | 0 => h
  | k + 1 => fresh_supOk (after_supOk h k)

theorem after_reach_mono {su : Sup} (h : SupOk su) :
    ∀ k z, Sup.Reach (su.after k) z → Sup.Reach su z
  | 0, _, hz => hz
  | k + 1, z, hz =>
    after_reach_mono h k z (reach_fresh_mono (after_supOk h k) z hz)

theorem after_add (su : Sup) (j k : Nat) : su.after (j + k) = (su.after j).after k := by
  induction k with
  | zero => rfl
  | succ k ih => simp only [Sup.after, ← ih]; rfl

/-- **Distinct draws.**  The `j`-th and the `k`-th id a coherent supply hands out differ
whenever `j < k`. -/
theorem drawAt_ne {su : Sup} (hok : SupOk su) {j k : Nat} (hjk : j < k) :
    drawAt su j ≠ drawAt su k := by
  obtain ⟨c, rfl⟩ : ∃ c, k = j + 1 + c := ⟨k - (j + 1), by omega⟩
  have hj : SupOk (su.after j) := after_supOk hok j
  have hreach : Sup.Reach ((su.after j).fresh.2) (drawAt su (j + 1 + c)) := by
    have : su.after (j + 1 + c) = ((su.after j).fresh.2).after c := by
      rw [after_add su (j + 1) c, after_add su j 1]; rfl
    unfold drawAt
    rw [this]
    exact after_reach_mono (fresh_supOk hj) c _ (fresh_reach (after_supOk (fresh_supOk hj) c))
  intro he
  have hself : Sup.Reach ((su.after j).fresh.2) ((su.after j).fresh.1) := by
    change Sup.Reach ((su.after j).fresh.2) (drawAt su j)
    rw [he]; exact hreach
  exact (fresh_reach_mono hj _ hself).2 rfl

/-- The set of ids a run of `k` draws takes out of the supply. -/
def drawnSet (su : Sup) (k : Nat) : Finset Nat := (Finset.range k).image (drawAt su)

/-- ...and it has exactly `k` elements. -/
theorem drawnSet_card {su : Sup} (hok : SupOk su) (k : Nat) : (drawnSet su k).card = k := by
  unfold drawnSet
  rw [Finset.card_image_of_injOn, Finset.card_range]
  intro a _ b _ hab
  by_contra hne
  rcases Nat.lt_or_ge a b with h | h
  · exact drawAt_ne hok h hab
  · exact drawAt_ne hok (by omega) hab.symm

/-! ## 6. The two hypotheses, as statements about the run

Both are MEASURED per solve by §1's instrument: `D` is the report's `maxdepth` column and `R`
is its **`maxdkey`** column — the largest number of draws at one DEQUEUE key.  It is not
`maxremint` or `maxcremint`: those count only the draws that install something, and
`resolution` takes its `fresh` BEFORE its guards, so a reuse bumps neither of them and `inj`
below would fail for it (`DepthRep.dtally`).

Measured, not DECIDED.  Round 7 could turn `NoDraw` into a Boolean `NoDrawB` with
`noDraw_of_noDrawB`, because "the loop draws nothing" is a property of the run alone; `Chain`
additionally asserts that the instrument's `site` / `key` / `idx` really are the ones `step`
uses, and that implication is not proved here.  `ChainRun` is therefore a hypothesis, and there
is deliberately no `ChainRunB`; see `L5-TERMINATION.md` §R8.6b, obligation L-a.

The clauses are stated over an ARBITRARY chain structure — a depth `dep`, a site `site`, a key
`key` and an index `idx` on ids — because that is all the counting needs, and because it keeps
the theorem independent of how the instrument computes them. -/

/-- **A chain structure on the ids a run draws.**  `V₀` is the input's vocabulary, `L` its label
pool, `D` the depth bound and `R` the per-key mint bound.  The five clauses are, in order: the
input sits at depth `0`; a drawn id is one deeper than the site it was drawn at; a site is an
input variable or an id drawn earlier; the depth bound; and the key bound with the injectivity
that makes it a bound — two draws at the same key with the same index are the same draw. -/
structure Chain (V₀ : Finset Nat) (L : Finset Nat) (D R : Nat) (Drawn : Finset Nat)
    (dep site idx : Nat → Nat) (key : Nat → Finset Nat) : Prop where
  /-- the input's own variables are at depth `0` -/
  base : ∀ v ∈ V₀, dep v = 0
  /-- a drawn id is one deeper than its site -/
  succ : ∀ z ∈ Drawn, dep z = dep (site z) + 1
  /-- a site is an input variable or an id this run drew -/
  from_ : ∀ z ∈ Drawn, site z ∈ V₀ ∨ site z ∈ Drawn
  /-- (a) the depth bound -/
  depth : ∀ z ∈ Drawn, dep z ≤ D
  /-- the key is over the input's label pool -/
  keyL : ∀ z ∈ Drawn, key z ⊆ L
  /-- (b) the per-key mint bound -/
  idxR : ∀ z ∈ Drawn, idx z < R
  /-- ...and the index really indexes the key: same site, same key, same index, same draw -/
  inj : ∀ z ∈ Drawn, ∀ w ∈ Drawn, site z = site w → key z = key w → idx z = idx w → z = w

/-! ## 7. The counting -/

/-- The drawn ids at one depth. -/
def atDepth (Drawn : Finset Nat) (dep : Nat → Nat) (d : Nat) : Finset Nat :=
  Drawn.filter (fun z => dep z = d)

/-- **Nothing is drawn at depth `0`.**  Every draw is one deeper than its site. -/
theorem atDepth_zero {V₀ L : Finset Nat} {D R : Nat} {Drawn : Finset Nat}
    {dep site idx : Nat → Nat} {key : Nat → Finset Nat}
    (hc : Chain V₀ L D R Drawn dep site idx key) : atDepth Drawn dep 0 = ∅ := by
  apply Finset.eq_empty_of_forall_notMem
  intro z hz
  rw [atDepth, Finset.mem_filter] at hz
  have := hc.succ z hz.1
  omega

/-- **One layer bounds the next.**  A draw at depth `d + 1` is determined by its site (at depth
`d`), its key (a subset of `L`) and its index (below `R`), so the layer at `d + 1` injects into
the layer at `d` times `L`'s powerset times `Fin R`. -/
theorem atDepth_succ_card {V₀ L : Finset Nat} {D R : Nat} {Drawn : Finset Nat}
    {dep site idx : Nat → Nat} {key : Nat → Finset Nat}
    (hc : Chain V₀ L D R Drawn dep site idx key) (d : Nat) (hd : 1 ≤ d) :
    (atDepth Drawn dep (d + 1)).card ≤ (atDepth Drawn dep d).card * (2 ^ L.card * R) := by
  classical
  have hmap : ∀ z ∈ atDepth Drawn dep (d + 1),
      (site z, key z, idx z) ∈ (atDepth Drawn dep d) ×ˢ (L.powerset ×ˢ Finset.range R) := by
    intro z hz
    rw [atDepth, Finset.mem_filter] at hz
    obtain ⟨hzD, hzd⟩ := hz
    have hs : dep (site z) = d := by have := hc.succ z hzD; omega
    have hsite : site z ∈ atDepth Drawn dep d := by
      rcases hc.from_ z hzD with h | h
      · exact absurd (hc.base _ h) (by omega)
      · rw [atDepth, Finset.mem_filter]; exact ⟨h, hs⟩
    simp only [Finset.mem_product, Finset.mem_powerset, Finset.mem_range]
    exact ⟨hsite, hc.keyL z hzD, hc.idxR z hzD⟩
  have hinj : ∀ z ∈ atDepth Drawn dep (d + 1), ∀ w ∈ atDepth Drawn dep (d + 1),
      (site z, key z, idx z) = (site w, key w, idx w) → z = w := by
    intro z hz w hw he
    rw [atDepth, Finset.mem_filter] at hz hw
    simp only [Prod.mk.injEq] at he
    exact hc.inj z hz.1 w hw.1 he.1 he.2.1 he.2.2
  have := Finset.card_le_card_of_injOn _ hmap hinj
  calc (atDepth Drawn dep (d + 1)).card
      ≤ ((atDepth Drawn dep d) ×ˢ (L.powerset ×ˢ Finset.range R)).card := this
    _ = (atDepth Drawn dep d).card * (2 ^ L.card * R) := by
        rw [Finset.card_product, Finset.card_product, Finset.card_powerset, Finset.card_range]

/-- **The first layer.**  A draw at depth `1` has an INPUT variable for its site. -/
theorem atDepth_one_card {V₀ L : Finset Nat} {D R : Nat} {Drawn : Finset Nat}
    {dep site idx : Nat → Nat} {key : Nat → Finset Nat}
    (hc : Chain V₀ L D R Drawn dep site idx key) :
    (atDepth Drawn dep 1).card ≤ V₀.card * (2 ^ L.card * R) := by
  classical
  have hmap : ∀ z ∈ atDepth Drawn dep 1,
      (site z, key z, idx z) ∈ V₀ ×ˢ (L.powerset ×ˢ Finset.range R) := by
    intro z hz
    rw [atDepth, Finset.mem_filter] at hz
    obtain ⟨hzD, hzd⟩ := hz
    have hs : dep (site z) = 0 := by have := hc.succ z hzD; omega
    have hsite : site z ∈ V₀ := by
      rcases hc.from_ z hzD with h | h
      · exact h
      · exact absurd (Finset.eq_empty_iff_forall_notMem.mp (atDepth_zero hc) (site z)
          (by rw [atDepth, Finset.mem_filter]; exact ⟨h, hs⟩)) (by simp)
    simp only [Finset.mem_product, Finset.mem_powerset, Finset.mem_range]
    exact ⟨hsite, hc.keyL z hzD, hc.idxR z hzD⟩
  have hinj : ∀ z ∈ atDepth Drawn dep 1, ∀ w ∈ atDepth Drawn dep 1,
      (site z, key z, idx z) = (site w, key w, idx w) → z = w := by
    intro z hz w hw he
    rw [atDepth, Finset.mem_filter] at hz hw
    simp only [Prod.mk.injEq] at he
    exact hc.inj z hz.1 w hw.1 he.1 he.2.1 he.2.2
  have := Finset.card_le_card_of_injOn _ hmap hinj
  calc (atDepth Drawn dep 1).card
      ≤ (V₀ ×ˢ (L.powerset ×ˢ Finset.range R)).card := this
    _ = V₀.card * (2 ^ L.card * R) := by
        rw [Finset.card_product, Finset.card_product, Finset.card_powerset, Finset.card_range]

/-- **Layer `d` is at most `n · (2^m · R)^d`.** -/
theorem atDepth_card_le {V₀ L : Finset Nat} {D R : Nat} {Drawn : Finset Nat}
    {dep site idx : Nat → Nat} {key : Nat → Finset Nat}
    (hc : Chain V₀ L D R Drawn dep site idx key) :
    ∀ d, 1 ≤ d → (atDepth Drawn dep d).card ≤ V₀.card * (2 ^ L.card * R) ^ d
  | 0, h => absurd h (by omega)
  | 1, _ => by simpa using atDepth_one_card hc
  | d + 2, _ => by
      have ih := atDepth_card_le hc (d + 1) (by omega)
      calc (atDepth Drawn dep (d + 2)).card
          ≤ (atDepth Drawn dep (d + 1)).card * (2 ^ L.card * R) :=
            atDepth_succ_card hc (d + 1) (by omega)
        _ ≤ (V₀.card * (2 ^ L.card * R) ^ (d + 1)) * (2 ^ L.card * R) :=
            Nat.mul_le_mul_right _ ih
        _ = V₀.card * (2 ^ L.card * R) ^ (d + 2) := by
            rw [Nat.mul_assoc, ← Nat.pow_succ]

/-- **The bound**: `n · D · (2^m · R)^D`. -/
def chainBound (n m D R : Nat) : Nat := n * D * (2 ^ m * R) ^ D

/-- **The decomposition, as a cardinal bound.**  Under a chain structure of depth `D` and
per-key multiplicity `R`, the drawn ids number at most `chainBound n m D R`. -/
theorem chain_card_le {V₀ L : Finset Nat} {D R : Nat} {Drawn : Finset Nat}
    {dep site idx : Nat → Nat} {key : Nat → Finset Nat}
    (hc : Chain V₀ L D R Drawn dep site idx key) :
    Drawn.card ≤ chainBound V₀.card L.card D R := by
  classical
  rcases Nat.eq_zero_or_pos R with rfl | hR
  · -- nothing is minted at all, so nothing is drawn
    have : Drawn = ∅ := by
      apply Finset.eq_empty_of_forall_notMem
      intro z hz
      exact absurd (hc.idxR z hz) (by omega)
    rw [this]; simp
  have hone : 1 ≤ 2 ^ L.card * R := by
    have h2 : 1 ≤ 2 ^ L.card := Nat.one_le_two_pow
    calc 1 = 1 * 1 := by omega
      _ ≤ 2 ^ L.card * R := Nat.mul_le_mul h2 hR
  have hcover : Drawn ⊆ (Finset.range (D + 1)).biUnion (fun d => atDepth Drawn dep d) := by
    intro z hz
    rw [Finset.mem_biUnion]
    refine ⟨dep z, ?_, ?_⟩
    · rw [Finset.mem_range]
      have := hc.depth z hz
      omega
    · rw [atDepth, Finset.mem_filter]; exact ⟨hz, rfl⟩
  have hsplit : ∑ d ∈ Finset.range (D + 1), (atDepth Drawn dep d).card
      = ∑ d ∈ Finset.range D, (atDepth Drawn dep (d + 1)).card := by
    rw [Finset.sum_range_succ', atDepth_zero hc]
    simp
  calc Drawn.card
      ≤ ((Finset.range (D + 1)).biUnion (fun d => atDepth Drawn dep d)).card :=
        Finset.card_le_card hcover
    _ ≤ ∑ d ∈ Finset.range (D + 1), (atDepth Drawn dep d).card := Finset.card_biUnion_le
    _ = ∑ d ∈ Finset.range D, (atDepth Drawn dep (d + 1)).card := hsplit
    _ ≤ ∑ _d ∈ Finset.range D, V₀.card * (2 ^ L.card * R) ^ D := by
        refine Finset.sum_le_sum ?_
        intro d hd
        rw [Finset.mem_range] at hd
        calc (atDepth Drawn dep (d + 1)).card
            ≤ V₀.card * (2 ^ L.card * R) ^ (d + 1) := atDepth_card_le hc (d + 1) (by omega)
          _ ≤ V₀.card * (2 ^ L.card * R) ^ D :=
              Nat.mul_le_mul_left _ (Nat.pow_le_pow_right hone (by omega))
    _ = chainBound V₀.card L.card D R := by
        rw [Finset.sum_const_nat (m := V₀.card * (2 ^ L.card * R) ^ D) (fun _ _ => rfl),
          Finset.card_range, chainBound, ← Nat.mul_assoc, Nat.mul_comm D V₀.card]

/-! ## 8. …and hence `Terminates`

The bridge from §7's cardinal statement to the loop is `drawnSet_card`: the ids a run draws are
distinct, so "the run drew `k` ids" IS "the drawn set has `k` elements", and §7 bounds that
set. -/

/-- **The run-level hypothesis.**  `ChainRun s₀ V₀ L D R` says: at every state reachable from
`s₀`, the ids drawn so far carry a chain structure of depth at most `D` and per-key
multiplicity at most `R`.  Both numbers are what §1's instrument reports, per solve. -/
def ChainRun (s : State) (V₀ L : Finset Nat) (D R : Nat) : Prop :=
  ∀ t, Reaches s t → ∃ (dep site idx : Nat → Nat) (key : Nat → Finset Nat),
    Chain V₀ L D R (drawnSet s.su (t.su.drawn - s.su.drawn)) dep site idx key

/-- **The draw bound.**  `ChainRun` bounds `Sup.drawn` along the whole run. -/
theorem drawn_le_of_chainRun {s : State} {V₀ L : Finset Nat} {D R : Nat}
    (hok : SupOk s.su) (h : ChainRun s V₀ L D R) :
    ∀ t, Reaches s t → t.su.drawn ≤ s.su.drawn + chainBound V₀.card L.card D R := by
  intro t ht
  obtain ⟨dep, site, idx, key, hc⟩ := h t ht
  have hcard := chain_card_le hc
  rw [drawnSet_card hok] at hcard
  omega

/-- **THE DECOMPOSITION THEOREM.**  If every id the loop draws has depth at most `D` and every
key is minted at most `R` times, the loop terminates — at the explicit bound
`chainBound n m D R = n · D · (2^m · R)^D`, with `n` the input's variable count and `m` its
label pool.  The two hypotheses are exactly the two quantities round 8's instrument measures. -/
theorem terminates_of_chainRun {s : State} {V₀ L : Finset Nat} {D R : Nat}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ChainRun s V₀ L D R) : Terminates s :=
  terminates_of_drawsAtMost hem hdj hcse hw hnd hok hfr hqh hki hkp
    (drawn_le_of_chainRun hok h)

/-- ...and the same at an INITIAL state, so a seed or a corpus replay carries only `Wf`,
`SupOk`, `SupFresh` and the chain condition (round 7's `_of_buildQueue` corollaries, verbatim
in shape). -/
theorem terminates_of_chainRun_of_buildQueue {V₀ L : Finset Nat} {D R : Nat}
    {cs : List CsItem} {su : Sup} {q : PQueue} {su' : Sup}
    {fl : Flags} {ns : Names} {site : String} {tr : List String} {z : Nat}
    (hq : buildQueue cs su = .ok (q, su'))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z)))
    (h : ChainRun (initState q su' tr fl ns site z) V₀ L D R) :
    Terminates (initState q su' tr fl ns site z) := by
  obtain ⟨ps, rfl⟩ := buildQueue_ofList hq
  refine terminates_of_chainRun hem hdj hcse hw (envNodup_initial fl ns site su' tr z) hok hfr
    (queueHygiene_of_env_nil rfl) (kdist_ofList ps) ?_ h
  simp [initState, PQueue.empty, KDist]

/-! ## 9. The two REAL seeds, in Lean (R8.4)

`tracker/repro/satterm/seeds/NP01.json` and `GU05.json` are the round-7 review's two witnesses
transcoded out of their own `sin`/`scon` records: `np01_add_or_recompute.e(134:15)`, the ONLY
corpus solve that mints one `splitConcrete` guard key twice, and
`gu05_star_join_4dim_concrete_signature.e(62:1)`, the deepest solve on record.  The seed format
(`rowclosure.py`'s `[lhs, [vars], [labels]]`) has a variable left-hand side and one concrete
part, so a `Part` with a CONCRETE left-hand side -- which `PQueue.build` mints a name for --
becomes a fresh seed variable plus its two partitions; everything else is preserved. -/

section Seeds
set_option maxRecDepth 8000

/-- `np01_add_or_recompute.e(134:15)`, twelve constraints over eleven variables and seven
labels -- the same 11 partitions, 11 variables and 7 labels the trace records. -/
def npSeed : Seed :=
  { name := "np01",
    cons := [⟨0, [1, 2, 3, 4], [0, 1, 2]⟩, ⟨7, [1, 2], []⟩, ⟨7, [], [3]⟩,
             ⟨5, [4, 6, 3], [0, 1, 2, 3]⟩, ⟨8, [3, 4, 1], [0, 1, 2]⟩,
             ⟨8, [], [0, 1, 2, 4, 5]⟩, ⟨0, [4, 3], [0, 1, 2, 3]⟩, ⟨9, [4, 6], []⟩,
             ⟨9, [], [6]⟩, ⟨10, [1, 3, 4], [0, 1, 2]⟩, ⟨10, [], [0, 1, 2, 4, 5]⟩,
             ⟨0, [3, 4], [0, 1, 2, 3]⟩],
    rhoKeys := [] }

/-- A supply of the COMPILER's shape (a live block below a global counter that is ahead of
it); `Sup.ofSeed`'s `blk = 0` would make `SupFresh` false.  `lo = 311` is the seed's own
`supplyLo` at id base 300, which is the base at which the model reproduces the trace. -/
def npSu : Sup := { lo := 311, hi := 1311, blk := 1311, bsz := 1024 }

def npNs : Names := (seedSystem npSeed 300).2

def npQ : PQueue :=
  match buildQueue (seedSystem npSeed 300).1 npSu with
  | .ok (q, _) => q
  | .error _ => PQueue.empty

def npSu2 : Sup :=
  match buildQueue (seedSystem npSeed 300).1 npSu with
  | .ok (_, su) => su
  | .error _ => npSu

theorem npBuild : buildQueue (seedSystem npSeed 300).1 npSu = .ok (npQ, npSu2) := by rfl

def npS0 : State := initState npQ npSu2 [] {} npNs "np01" 311

/-- Eleven input partitions, as the trace's segment 54291 records. -/
theorem npS0_size : npS0.incm.elems.length = 11 := by rfl

/-- The seed draws nothing before the loop: every left-hand side is a variable. -/
theorem npS0_supply : npS0.su.lo = 311 ∧ npS0.su.drawn = 0 := ⟨by rfl, by rfl⟩

/-- **The seed reproduces the corpus solve, inside Lean.**  Trace segment 54291 records
`steps=98 drawn=22 drawn0=4 maxdepth=2 nsplit=6 nres=12 maxremint=2 maxcremint=3 nvars=11
nparts=11 nlbl=7 hist=1:11,2:7`, and `depthRun 200 npS0 {}` computes
`steps=98 drawn=18 maxdepth=2 maxremint=2 maxcremint=3 maxdkey=3 nvars=11 nparts=11 nlbl=7
hist=[(1,11),(2,7)]` — every column, with `drawn` the segment's `22 - 4 = 18` LOOP draws
(the seed's own supply draws nothing before the loop).

Only the DEPTH is stated as a theorem here.  Each `by rfl` on `depthRun` re-runs 98 dequeues
in the KERNEL and costs minutes of `lake build`; the rest of the columns are checked instead
by the corpus differential, which replays the same solve out of the compiler's own trace
2,301,195 times over with `0 hashdiff / 0 eqdiff` (§R8.0 of `L5-TERMINATION.md`) — stronger
evidence than a second kernel evaluation of the same function. -/
theorem npS0_depth : (depthRun 200 npS0 {}).maxDepth = 2 := by rfl

/-- The solve TERMINATES, proved outright by running it — `run` without the instrument, which
is what makes this one cheap. -/
theorem npS0_terminates : Terminates npS0 := ⟨200, by trivial⟩

/-- What `terminates_of_chainRun` gives at this solve's measured `n = 11`, `m = 7`, `D = 2`,
`R = 3`: a bound of 3,244,032 draws, against the 18 the solve takes.  The theorem is true and
the constant is useless; `2 ^ m` is the whole of it. -/
theorem npS0_bound : chainBound 11 7 2 3 = 3244032 := by rfl

end Seeds

end Rowpartition.Loop
