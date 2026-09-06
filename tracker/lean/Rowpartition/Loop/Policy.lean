/-
# D1 (A2): DEQUEUE-ORDER POLICIES on the model

`tracker/loopmodel/briefs/brief-D1.md` A2, and the finding it is a response to: `GU05.json`
(`tracker/repro/satterm/seeds/slow/`; `L5-TERMINATION.md` §R8.0a, `PERF-ROADMAP.md` P10) is a
SATISFIABLE 21-variable input whose cost is decided by nothing but the id base -- 743 draws at
one base and 47,000-81,481 at others, a like-for-like 1,210x in wall clock -- because
`Q.PQueue`'s priority is keyed on `hashCode`, and a `TypeVar`'s `hashCode` IS its id.  A draw
BUDGET without an order fix would make that seed type-check or fail BY ID BASE, which is worse
than slow; so the budget (`Loop/Budget.lean`) and the order come together.

The model is the fast oracle: `Loop/Queue.lean` reproduces `Q.pop` exactly -- the deepest
variable in the reverse-topological order, then the smallest `rhs.hashCode` as a signed Java
`int`, then the most recently inserted -- which is what lets it try OTHER orders without
touching a line of Scala.

WHAT IS AND IS NOT TOUCHED.  `step`, `run` and `PQueue.dequeue` are NOT changed: `stepP` is a
new function whose body is `step`'s, character for character, with the single dequeue call
replaced, and `stepP_shipped` is `rfl`.  So every theorem of the development is still about
the same loop, and the L2 corpus differential at the default is the same differential.  This
is the shape `Loop/Decide.lean`'s `stepS` has for S2, and for the same reason.

THE SIX POLICIES (`Policy`):

* `shipped`   -- `Q.pop`, unchanged, and the DEFAULT everywhere;
* `concFirst` -- partitions whose right-hand side carries a CONCRETE part first, ties by the
                 shipped order;
* `smallRhs`  -- fewest right-hand-side parts first (`|abstr| + (conc ? 1 : 0)`, the partition's
                 arity, which is what the `solve` record's `arities` column counts), ties by
                 the shipped order;
* `fifo`      -- earliest ARRIVAL BATCH first: every input partition is batch 0, and a
                 partition derived at dequeue `k` is in batch `k`; within a batch the shipped
                 order breaks the tie.  A true per-insertion FIFO would need an arrival counter
                 on `Partition`, which neither the model's `LPart` nor the Scala's carries;
                 the batch is what a `Queue`-shaped `PQueue` would give, and it is what Part B
                 would implement;
* `canon`     -- the shipped order with EVERY ID REPLACED BY ITS FIRST-OCCURRENCE RANK: the
                 reverse-topological sort is recomputed over rank-ordered nodes and rank-ordered
                 edge sets, and `rhs.hashCode` is replaced by the sorted list of the right-hand
                 side's ranks and its label indices.  The rank IS the id order (`sortByRank`'s
                 comment proves it: every input variable precedes every mint, and `Supply.fresh`
                 is monotone), so `canon` compares ids by ORDER and needs no rank table -- in
                 the model or in the compiler.  It is order-canonical because a change of id
                 base shifts every id of the solve by the same amount, which is exactly what the
                 25-base sweep varies, while the SHIPPED key `rhs.hashCode` is the case-class
                 hash of a `Set[TypeVar]`, a Murmur mix that is a pseudo-random function of
                 those same ids;
* `smallCanon` -- `smallRhs`'s ARITY as the primary key and `canon`'s ID ORDER as the whole of
                 the tie-break, so it is both the cheap order and an order-canonical one.  It is
                 the combination A2's measurements point at: `smallRhs` collapses `GU05`'s COST
                 and `canon` collapses its SPREAD, and neither alone does both.
-/
import Rowpartition.Loop.Budget

namespace Rowpartition.Loop

/-! ## 1. The policy, and the auxiliary state two of the five need -/

/-- The dequeue policy.  `shipped` is `Q.pop`; the other five are A2's candidates. -/
inductive Policy where
  | shipped | concFirst | smallRhs | fifo | canon | smallCanon
deriving DecidableEq, Repr, Inhabited

namespace Policy

def toStr : Policy → String
  | .shipped => "shipped"
  | .concFirst => "concfirst"
  | .smallRhs => "smallrhs"
  | .fifo => "fifo"
  | .canon => "canon"
  | .smallCanon => "smallcanon"

def ofString : String → Option Policy
  | "shipped" => some .shipped
  | "concfirst" => some .concFirst
  | "smallrhs" => some .smallRhs
  | "fifo" => some .fifo
  | "canon" => some .canon
  | "smallcanon" => some .smallCanon
  | _ => none

end Policy

/-- **The rank IS the id order.**  A variable's first-occurrence rank and its id sort the same
way, so `canon` can compare ids and needs no rank table -- in the model or in the compiler:

* every input variable of a solve precedes every mint, and `Sup.Reach`/`SupOk` say every id the
  supply can hand out is above every id in play;
* `Supply.fresh` is monotone: inside a block it returns `lo` and increments, and at a block
  boundary it returns the GLOBAL counter `blk`, which is past every id ever issued.

So `rank v < rank w ↔ v < w`, and an id ORDER is what `canon` compares.  It is
base-independent because a change of id base shifts every id of the solve by the same amount,
which is exactly what the 25-base sweep varies. -/
def sortByRank (xs : List Nat) : List Nat := sortNats xs

/-- The graph's fingerprint: how many nodes, and the total size of the edge sets. -/
def gfp (g : Graph) : Nat × Nat :=
  (g.nodes.elems.length, g.edges.foldl (fun n p => n + p.2.elems.length) 0)

/-- `canon`'s priority: `TypeVarGraph.sort`, recomputed over ID-ORDERED nodes and ID-ordered
children.  `Graph.add` recomputes the real one only when the new edge breaks it, and its input
orders are `Set` CHAMP orders -- that is, hash orders, and a `TypeVar`'s hash IS its id, so the
real `sort` moves with the base.  This one depends on the graph alone. -/
def canonPrio (g : Graph) : List (Nat × Nat) :=
  withIndex (Graph.reverseTopSort (sortByRank g.nodes.elems)
    (fun v => match alGet g.edges v with
      | some s => sortByRank s.elems
      | none => []))

/-- What `fifo` and `canon` need and the state does not carry: the queue in ARRIVAL-BATCH
order, and the variables in FIRST-OCCURRENCE order.  Both are derived from the states the
loop passes through, so nothing outside this file sees them. -/
structure Aux where
  /-- The current queue's partitions, oldest batch first (`fifo`). -/
  arr : List LPart := []
  /-- `canon`'s rank-ordered reverse-topological index, cached (see `Aux.next`). -/
  pr : List (Nat × Nat) := []
  /-- The fingerprint of the graph `pr` was computed from: the number of nodes and the total
  size of the edge sets.  `Graph.add` only ever ADDS a node or ADDS to an edge set and
  recomputes `sort` exactly when it does, so an unchanged fingerprint is an unchanged
  graph. -/
  fp : Nat × Nat := (0, 0)

namespace Aux

/-- At the loop's first dequeue: the input partitions are batch 0, and the input variables are
ranked in ascending id order -- which is the order the compiler created them in, and which is
the same at every id base because a base shifts every id by the same amount.

Only the field the policy READS is built: `shipped`, `concFirst` and `smallRhs` consult
neither, and computing them for those three would cost a `stateVars` traversal per dequeue for
nothing. -/
def init (pol : Policy) (s : State) : Aux :=
  match pol with
  | .shipped | .concFirst | .smallRhs => {}
  | .fifo => { arr := s.incm.elems }
  | .canon | .smallCanon => { pr := canonPrio s.incm.graph, fp := gfp s.incm.graph }

/-- After a step: the partitions that survived keep their batch order, the ones the step
derived form the new (latest) batch in the queue's own order, and any id the step drew is
ranked after every id already seen, in ascending order -- i.e. in the order `Supply.fresh`
handed them out. -/
def next (pol : Policy) (a : Aux) (s' : State) : Aux :=
  match pol with
  | .shipped | .concFirst | .smallRhs => a
  | .fifo =>
    let es := s'.incm.elems
    let kept := a.arr.filter (fun p => es.any (fun x => x.eqv p))
    let fresh := es.filter (fun x => !kept.any (fun p => p.eqv x))
    { a with arr := kept ++ fresh }
  | .canon | .smallCanon =>
    let f := gfp s'.incm.graph
    if f == a.fp then a else { a with pr := canonPrio s'.incm.graph, fp := f }

end Aux

/-! ## 2. The four alternative orders -/

/-- The separator inside `canon`'s key: larger than any rank or label index a solve can reach
(the largest corpus solve has 21 variables and 10 labels). -/
def canonSep : Nat := 1000000000

/-- `canon`'s replacement for `(rhs.hashCode, lhs.hashCode)`: the SORTED ids of the right-hand
side's variables, the SORTED label indices of its concrete part, and the id of the left-hand
side, compared LEXICOGRAPHICALLY.  Two distinct partitions of one solve get distinct keys, so
the order is total; and because only the ORDER of the ids is ever consulted, a change of base
-- which shifts every id by the same amount -- leaves it alone.  That is the whole difference
from `Q.pop`, whose key is `rhs.hashCode`: the case-class hash of a `Set[TypeVar]`, a Murmur
mix that is a pseudo-random function of exactly those ids. -/
def canonKey (p : LPart) : List Nat :=
  sortNats p.rhs.abstr.elems ++ [canonSep] ++
    sortNats (p.rhs.conc.elems.map (fun l => l.n)) ++ [canonSep, p.lhs]

/-- Lexicographic order on the keys, shorter-is-smaller at a common prefix. -/
def natListLt : List Nat → List Nat → Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | x :: xs, y :: ys => if x == y then natListLt xs ys else decide (x < y)

/-- `(priority, key)`, lexicographically. -/
def canonLt (x y : Nat × List Nat) : Bool :=
  decide (x.1 < y.1) || (x.1 == y.1 && natListLt x.2 y.2)

/-- `(arity, priority, key)`, lexicographically: `smallCanon`'s order. -/
def scLt (x y : Nat × Nat × List Nat) : Bool :=
  decide (x.1 < y.1) || (x.1 == y.1 && canonLt x.2 y.2)

/-- The PRE-KEY the three cheap policies minimise before the shipped order breaks the tie. -/
def preKey (pol : Policy) (a : Aux) (p : LPart) : Nat :=
  match pol with
  | .shipped => 0
  | .canon => 0
  | .concFirst => if p.rhs.conc.isEmpty then 1 else 0
  | .smallRhs | .smallCanon => p.rhs.abstr.size + (if p.rhs.conc.isEmpty then 0 else 1)
  | .fifo => a.arr.findIdx (fun x => x.eqv p)

/-- The four alternative orders, as a dequeue.  The queue's own list and its graph are the ones
`Q.pop` reads; only the CHOICE of index changes, so the state the loop then works on is the one
the shipped loop would have had if the queue had handed it that partition. -/
def dequeueAlt (pol : Policy) (a : Aux) (q : PQueue) : Option (LPart × PQueue) :=
  match q.elems with
  | [] => none
  | e0 :: rest =>
    let es := e0 :: rest
    -- ONE pass, carrying the position: indexing the list per candidate would make every
    -- dequeue quadratic in the queue, which on `GU05` is the difference between seconds and
    -- an hour.  `withIndex` is `Loop/Queue.lean`'s own `zip(Stream.from(0))`.
    let ix := withIndex es
    let pick : Option Nat :=
      match pol with
      | .canon =>
        (ix.foldl (fun (best : Option (Nat × Nat × List Nat)) z =>
            let k : Nat × List Nat := ((alGet a.pr z.1.lhs).getD 0, canonKey z.1)
            match best with
            | none => some (z.2, k)
            | some w => if canonLt k w.2 then some (z.2, k) else some w)
          none).map (·.1)
      | .smallCanon =>
        (ix.foldl (fun (best : Option (Nat × Nat × Nat × List Nat)) z =>
            let k : Nat × Nat × List Nat :=
              (preKey .smallRhs a z.1, (alGet a.pr z.1.lhs).getD 0, canonKey z.1)
            match best with
            | none => some (z.2, k)
            | some w => if scLt k w.2 then some (z.2, k) else some w)
          none).map (·.1)
      | _ =>
        let ks := ix.map (fun z => (z.2, preKey pol a z.1, q.graph.prio z.1.lhs))
        match ks with
        | [] => none
        | k0 :: kt =>
          let m0 := kt.foldl (fun acc t => Nat.min acc t.2.1) k0.2.1
          match ks.filter (fun t => t.2.1 == m0) with
          | [] => none
          | c0 :: ct =>
            let m := ct.foldl (fun acc t => Nat.min acc t.2.2) c0.2.2
            ((c0 :: ct).find? (fun t => t.2.2 == m)).map (·.1)
    match pick with
    | none => none
    | some i =>
      match es[i]? with
      | none => none
      | some p => some (p, ⟨es.eraseIdx i, q.graph⟩)

/-- **`pop` under a policy.**  At `shipped` -- the default -- this IS `PQueue.dequeue`, by
definition and not by a lemma. -/
def dequeuePol (pol : Policy) (a : Aux) (q : PQueue) : Option (LPart × PQueue) :=
  match pol with
  | .shipped => q.dequeue
  | _ => dequeueAlt pol a q

/-! ## 3. `stepP`: `step` with the policy in `pop`, and nothing else changed -/

/-- `incorporateAll`'s body for one dequeue, with `pop` taking a policy.  The body below is
`Loop/Step.lean`'s `step`, copied unchanged except for the first line; `stepP_shipped` is the
`rfl` that says so. -/
def stepP (pol : Policy) (a : Aux) (s : State) : StepResult :=
  match dequeuePol pol a s.incm with
  | none => .done s
  | some (r, rest) =>
    let stepLog := fun (st : State) (branch : String) =>
      st.log ("step\t" ++ st.site ++ "\t" ++ branch ++ "\t" ++ r.toStr st.names ++
              "\tincm=" ++ toString rest.size ++ "\tproc=" ++ toString s.proc.size)
    let fin := fun (st : State) (res : Except String (PQueue × PQueue × Env)) =>
      match res with
      | .error m => .died m st
      | .ok (ni, np, e) => .continue { st with incm := ni, proc := np, env := e }
    match s.proc.findRHS r.rhs with
    | some u =>
      let st := stepLog s ("common:" ++ toString u)
      fin st (unifyVars st.names r.lhs u rest s.proc st.env)
    | none =>
      if r.rhs.isEmpty then
        let st := stepLog s "empty"
        fin st (makeEmpty st.names r.lhs rest s.proc st.env)
      else if r.rhs.abstr.isEmpty then
        let st := stepLog s "concrete"
        match makeConcrete r.lhs r.rhs.conc rest s.proc with
        | .error m => .died m st
        | .ok (ni, np) => .continue { st with incm := ni, proc := np }
      else
        match r.rhs.single? with
        | some u =>
          let st := stepLog s ("unify:" ++ toString u)
          fin st (unifyVars st.names u r.lhs rest s.proc st.env)
        | none =>
          let st := stepLog s "learn"
          match learnPartitions st.flags st.names st.env r.lhs r.rhs rest s.proc st.su with
          | .error m => .died m st
          | .ok (learned, su) =>
            let st := learned.elems.foldl
              (fun (a : State) (p : LPart) =>
                a.log ("learn\t" ++ a.site ++ "\t" ++
                       (if s.proc.contains p then "seen" else "new") ++ "\t" ++
                       p.toStr a.names)) st
            .continue { st with
              incm := rest.concatP (trim learned s.proc).elems,
              proc := s.proc.insertNP r,
              su := su }

/-- **The default is the shipped loop, definitionally.**  Everything the development proves
about `step` is therefore about `stepP .shipped`, and the L2 corpus differential is untouched
by this file. -/
theorem stepP_shipped (a : Aux) (s : State) : stepP .shipped a s = step s := rfl

/-! ## 4. The census: one solve, under a policy and a budget -/

/-- What one policy run of one solve reports: the verdict, the dequeues, the ids drawn and the
count the loop started with, so that LOOP draws are `drawn - drawn0` -- the unit
`Loop/Budget.lean` budgets. -/
structure PolRep where
  verdict : String := "FUEL"
  steps : Nat := 0
  drawn : Nat := 0
  drawn0 : Nat := 0
  msg : String := ""
deriving Inhabited

/-- One dequeue under a policy AND a budget; `b = 0` is the budget off, which is the default
everywhere.  With `pol = .shipped` and `b = 0` this is `step`. -/
def stepPB (pol : Policy) (d0 b : Nat) (a : Aux) (s : State) : StepResult :=
  if b != 0 && d0 + b < s.su.drawn then .died (budgetMsg s.site d0 b s.su.drawn) s
  else stepP pol a s

/-- With the budget off and the shipped order, `stepPB` is `step`. -/
theorem stepPB_default (d0 : Nat) (a : Aux) (s : State) : stepPB .shipped d0 0 a s = step s := by
  rfl

/-- Run one solve under a policy and a budget, counting dequeues and draws. -/
def polRun (pol : Policy) (d0 b : Nat) : Nat → Aux → State → Nat → PolRep
  | 0, _, s, k => { verdict := "FUEL", steps := k, drawn := s.su.drawn, drawn0 := d0 }
  | n + 1, a, s, k =>
    match stepPB pol d0 b a s with
    | .done s' => { verdict := "SOLVED", steps := k, drawn := s'.su.drawn, drawn0 := d0 }
    | .died m s' =>
      { verdict := "REJECTED", steps := k, drawn := s'.su.drawn, drawn0 := d0, msg := m }
    | .continue s' => polRun pol d0 b n (a.next pol s') s' (k + 1)

/-- The census of one solve from its initial state. -/
def polCensus (pol : Policy) (b : Nat) (fuel : Nat) (s0 : State) : PolRep :=
  polRun pol s0.su.drawn b fuel (Aux.init pol s0) s0 0

/-! ## 5. What every policy has in common: the SHAPE of a dequeue

A3.  The soundness chain of S1 (`Loop/Sound.lean`, `Loop/Reject.lean`, `Loop/Solve.lean`) and
the certified termination fragments (`Loop/NoConc.lean`, `Loop/VocFix.lean`,
`Loop/Fragment.lean`) consume `pop` through exactly six facts, all of them about WHICH
partition is returned and none about the ORDER it was chosen in (the counts are uses net of
each lemma's own statement and doc line; review T-7 corrected them):

* `PQueue.dequeue_mem` (`Loop/Wf.lean`), 36 uses -- the dequeued partition is in the queue, and
  everything left was;
* `dequeue_mem_or` (`Loop/RefineLearn.lean`), 9 uses -- nothing else is lost;
* `dequeue_length_lt` (`Loop/Dequeue.lean`), 3 uses -- the queue got shorter;
* `dequeue_sub` (`Loop/Dequeue.lean`), 2 uses;
* `kdist_dequeue` (`Loop/NoConc.lean`), 2 uses, and `dequeue_unique`
  (`Loop/RefineConcrete.lean`), 13 uses.

The ONE order-dependent lemma the development has, `dequeue_prio_min` -- `Q.pop` returns a
partition of minimal graph priority -- is used in exactly one place, to prove
`dequeue_not_of_lt`, and `dequeue_not_of_lt` is used NOWHERE.  (Both greps are recorded in
`tracker/loopmodel/D1-DESIGN.md` §5.)  So the transport of S1 to another order is not a
question of weakening a hypothesis: it is a question of re-running the same proofs against a
`pop` that satisfies the shape below, which every policy does.

`DequeueShape` is that shape, and it is proved for `PQueue.dequeue` itself and for all FIVE
alternatives (`concFirst`, `smallRhs`, `fifo`, `canon`, `smallCanon`), from which the six facts
follow uniformly -- §6 adds the last two of them and the `none` case (review T-3). -/

/-- A dequeue returns an ELEMENT of the queue at some position, leaves the queue with that
position erased, and keeps the graph.  This is everything the development's proofs use ON THE
SUCCESS PATH; the `none` path is `dequeuePol_none` in §6 (review T-3). -/
def DequeueShape (q : PQueue) (r : LPart) (rest : PQueue) : Prop :=
  ∃ i, q.elems[i]? = some r ∧ rest = ⟨q.elems.eraseIdx i, q.graph⟩

/-- `Q.pop` has the shape. -/
theorem dequeue_shape {q : PQueue} {r : LPart} {rest : PQueue}
    (h : q.dequeue = some (r, rest)) : DequeueShape q r rest := by
  simp only [PQueue.dequeue] at h
  split at h
  · exact absurd h (by simp)
  · rename_i e0 tl he
    split at h
    · exact absurd h (by simp)
    · rename_i i hi
      split at h
      · exact absurd h (by simp)
      · rename_i z hz
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨i, by rw [he]; exact hz, by rw [he]⟩

/-- ...and so does every alternative order. -/
theorem dequeueAlt_shape {pol : Policy} {a : Aux} {q : PQueue} {r : LPart} {rest : PQueue}
    (h : dequeueAlt pol a q = some (r, rest)) : DequeueShape q r rest := by
  simp only [dequeueAlt] at h
  split at h
  · exact absurd h (by simp)
  · rename_i e0 tl he
    split at h
    · exact absurd h (by simp)
    · rename_i i hi
      split at h
      · exact absurd h (by simp)
      · rename_i z hz
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨i, by rw [he]; exact hz, by rw [he]⟩

/-- **Every policy's `pop` has the shape `Q.pop` has.** -/
theorem dequeuePol_shape {pol : Policy} {a : Aux} {q : PQueue} {r : LPart} {rest : PQueue}
    (h : dequeuePol pol a q = some (r, rest)) : DequeueShape q r rest := by
  cases pol with
  | shipped => simp only [dequeuePol] at h; exact dequeue_shape h
  | concFirst => simp only [dequeuePol] at h; exact dequeueAlt_shape h
  | smallRhs => simp only [dequeuePol] at h; exact dequeueAlt_shape h
  | fifo => simp only [dequeuePol] at h; exact dequeueAlt_shape h
  | canon => simp only [dequeuePol] at h; exact dequeueAlt_shape h
  | smallCanon => simp only [dequeuePol] at h; exact dequeueAlt_shape h

/-- The dequeued partition is in the queue, and everything left over was. -/
theorem shape_mem {q : PQueue} {r : LPart} {rest : PQueue} (h : DequeueShape q r rest) :
    r ∈ q.elems ∧ ∀ x ∈ rest.elems, x ∈ q.elems := by
  obtain ⟨i, hi, rfl⟩ := h
  exact ⟨List.mem_of_getElem? hi, fun x hx => (List.eraseIdx_sublist _ i).subset hx⟩

/-- Nothing but the dequeued partition is lost. -/
theorem shape_mem_or {q : PQueue} {r : LPart} {rest : PQueue} (h : DequeueShape q r rest) :
    ∀ x ∈ q.elems, x ∈ rest.elems ∨ x = r := by
  obtain ⟨i, hi, rfl⟩ := h
  intro x hx
  rcases mem_eraseIdx_or q.elems i x hx with hh | hh
  · exact Or.inl hh
  · exact Or.inr (by rw [hi] at hh; exact (Option.some.injEq _ _ ▸ hh).symm)

/-- The queue gets strictly shorter. -/
theorem shape_length_lt {q : PQueue} {r : LPart} {rest : PQueue} (h : DequeueShape q r rest) :
    rest.elems.length < q.elems.length := by
  obtain ⟨i, hi, rfl⟩ := h
  have hlt : i < q.elems.length := (List.getElem?_eq_some_iff.mp hi).1
  simp only [List.length_eraseIdx, hlt, if_pos]
  omega

/-! ## 6. The `none` case, and the two derivations a Part B mirror needs (review T-3)

`DequeueShape` covers a SUCCESSFUL dequeue.  The review's T-3 is that the other case is the one
the Scala mirror must not get wrong: `stepP`'s `.done` -- the model's ACCEPTANCE -- is exactly
`dequeuePol pol a s.incm = none`, so a `pop` that returned `none` on a NON-EMPTY queue would make
`incorporateAll` return `proc` and the solve accept WITHOUT SATURATING.  `dequeuePol_none` below
is that missing fact, for `Q.pop` and for all five alternatives; with it, what the development
uses of `pop` is covered on BOTH branches.

`shape_kdist` and `shape_unique` are the other two lemmas of the §5 inventory, re-derived from
the shape so that a mirror has the whole list from one place. -/

/-- `withIndex` numbers a list by position, so every index it hands out is one. -/
theorem withIndex_go_lt {α : Type} : ∀ (ys : List α) (i : Nat) (z : α × Nat),
    z ∈ withIndex.go ys i → z.2 < i + ys.length
  | [], _, _, hz => by simp [withIndex.go] at hz
  | y :: t, i, z, hz => by
    rw [withIndex.go] at hz
    rcases List.mem_cons.mp hz with rfl | ht
    · simp
    · have := withIndex_go_lt t (i + 1) z ht
      simp only [List.length_cons]
      omega

theorem withIndex_lt {α : Type} {xs : List α} {z : α × Nat} (h : z ∈ withIndex xs) :
    z.2 < xs.length := by
  have := withIndex_go_lt xs 0 z h
  omega

theorem withIndex_ne_nil {α : Type} {y : α} {t : List α} : withIndex (y :: t) ≠ [] := by
  simp [withIndex, withIndex.go]

/-- A `Nat`-valued minimum taken by a left fold is either the seed or attained on the list. -/
theorem foldl_minBy_mem {α : Type} (f : α → Nat) : ∀ (l : List α) (a : Nat),
    l.foldl (fun acc x => Nat.min acc (f x)) a = a ∨
      ∃ x ∈ l, l.foldl (fun acc x => Nat.min acc (f x)) a = f x
  | [], _ => Or.inl rfl
  | y :: t, a => by
    rw [List.foldl_cons]
    rcases foldl_minBy_mem f t (Nat.min a (f y)) with h | ⟨x, hx, hfx⟩
    · rcases Nat.le_total a (f y) with hle | hle
      · exact Or.inl (by rw [h]; exact Nat.min_eq_left hle)
      · exact Or.inr ⟨y, List.mem_cons_self .., by rw [h]; exact Nat.min_eq_right hle⟩
    · exact Or.inr ⟨x, List.mem_cons_of_mem _ hx, hfx⟩

/-- Once the accumulator of `dequeueAlt`'s argmin fold is `some`, it stays `some`. -/
theorem foldl_pick_isSome {α β : Type} {g : Option β → α → Option β}
    (hg : ∀ o x, (g o x).isSome = true) : ∀ (l : List α) (o : Option β),
    o.isSome = true → (l.foldl g o).isSome = true
  | [], _, ho => ho
  | x :: t, o, _ => by
    rw [List.foldl_cons]
    exact foldl_pick_isSome hg t (g o x) (hg o x)

/-- ...and a fold over a NON-EMPTY list is `some` whatever it started from. -/
theorem foldl_pick_isSome' {α β : Type} {g : Option β → α → Option β}
    (hg : ∀ o x, (g o x).isSome = true) {y : α} {t : List α} (o : Option β) :
    ((y :: t).foldl g o).isSome = true := by
  rw [List.foldl_cons]
  exact foldl_pick_isSome hg t (g o y) (hg o y)

/-- Every index `dequeueAlt`'s argmin fold can return is an index of the queue.  Stated over the
fold's BODY rather than its key, so that the two argmin folds -- `canon`'s and `smallCanon`'s,
whose keys have different types -- are both instances. -/
theorem foldl_pick_lt {α β : Type} {es : List α}
    {g : Option (Nat × β) → (α × Nat) → Option (Nat × β)}
    (hg : ∀ o z w, g o z = some w → w.1 = z.2 ∨ o = some w) :
    ∀ (l : List (α × Nat)) (o : Option (Nat × β)),
      (∀ z ∈ l, z.2 < es.length) → (∀ w, o = some w → w.1 < es.length) →
      ∀ w, l.foldl g o = some w → w.1 < es.length
  | [], o, _, ho, w, hw => ho w hw
  | z :: t, o, hl, ho, w, hw => by
    rw [List.foldl_cons] at hw
    refine foldl_pick_lt hg t _ (fun y hy => hl y (List.mem_cons_of_mem _ hy)) ?_ w hw
    intro v hv
    rcases hg o z v hv with h1 | h2
    · rw [h1]; exact hl z (List.mem_cons_self ..)
    · exact ho v h2

/-- **`Q.pop` returns `none` only on an EMPTY queue.** -/
theorem dequeue_none {q : PQueue} (h : q.dequeue = none) : q.elems = [] := by
  by_contra hne
  obtain ⟨e0, tl, he⟩ : ∃ e0 tl, q.elems = e0 :: tl := by
    cases hq : q.elems with
    | nil => exact absurd hq hne
    | cons a t => exact ⟨a, t, rfl⟩
  simp only [PQueue.dequeue, he] at h
  have hattain : ∃ p ∈ e0 :: tl,
      ((e0 :: tl).map (fun x => q.graph.prio x.lhs)).foldl Nat.min (q.graph.prio e0.lhs)
        = q.graph.prio p.lhs := by
    have hm := foldl_minBy_mem (α := Nat) id ((e0 :: tl).map (fun x => q.graph.prio x.lhs))
      (q.graph.prio e0.lhs)
    simp only [id] at hm
    rcases hm with hh | ⟨x, hx, hfx⟩
    · exact ⟨e0, List.mem_cons_self .., by simpa using hh⟩
    · obtain ⟨p, hp, rfl⟩ := List.mem_map.mp hx
      exact ⟨p, hp, by simpa using hfx⟩
  obtain ⟨p, hp, hpm⟩ := hattain
  split at h
  · rename_i hnone
    rw [List.findIdx?_eq_none_iff] at hnone
    have hcon := hnone p hp
    rw [hpm] at hcon
    simp at hcon
  · rename_i i hi
    split at h
    · rename_i hg
      obtain ⟨hlt, -, -⟩ := List.findIdx?_eq_some_iff_getElem.mp hi
      rw [List.getElem?_eq_getElem hlt] at hg
      exact absurd hg (by simp)
    · exact absurd h (by simp)

/-- **...and so does every alternative order.** -/
theorem dequeueAlt_none {pol : Policy} {a : Aux} {q : PQueue} (h : dequeueAlt pol a q = none) :
    q.elems = [] := by
  by_contra hne
  obtain ⟨e0, tl, he⟩ : ∃ e0 tl, q.elems = e0 :: tl := by
    cases hq : q.elems with
    | nil => exact absurd hq hne
    | cons b t => exact ⟨b, t, rfl⟩
  simp only [dequeueAlt, he] at h
  have hix : ∀ z ∈ withIndex (e0 :: tl), z.2 < (e0 :: tl).length := fun z hz => withIndex_lt hz
  -- Whatever the branch, the index it picks exists and is an index of the queue; that is all
  -- the outer `match` needs in order to return `some`.
  have key : ∀ (pk : Option Nat), pk ≠ none →
      (∀ i, pk = some i → i < (e0 :: tl).length) →
      (match pk with
       | none => none
       | some i => match (e0 :: tl)[i]? with
         | none => none
         | some p => some (p, ({ elems := (e0 :: tl).eraseIdx i, graph := q.graph } : PQueue)))
        ≠ (none : Option (LPart × PQueue)) := by
    intro pk hne' hlt
    cases hpk : pk with
    | none => exact absurd hpk hne'
    | some i =>
      simp only []
      rw [List.getElem?_eq_getElem (hlt i hpk)]
      simp
  refine key _ ?_ ?_ h
  · -- the pick is never `none`
    cases pol with
    | canon =>
      simp only [ne_eq, Option.map_eq_none_iff]
      intro hc
      have hs := foldl_pick_isSome' (g := fun (best : Option (Nat × Nat × List Nat)) z =>
          match best with
          | none => some (z.2, ((alGet a.pr z.1.lhs).getD 0, canonKey z.1))
          | some w => if canonLt ((alGet a.pr z.1.lhs).getD 0, canonKey z.1) w.2
                      then some (z.2, ((alGet a.pr z.1.lhs).getD 0, canonKey z.1)) else some w)
          (fun o x => by cases o with | none => simp | some u => simp only []; split <;> simp) (y := (e0, 0))
          (t := (withIndex.go tl 1)) none
      rw [withIndex, withIndex.go] at hc
      rw [hc] at hs
      simp at hs
    | smallCanon =>
      simp only [ne_eq, Option.map_eq_none_iff]
      intro hc
      have hs := foldl_pick_isSome' (g := fun (best : Option (Nat × Nat × Nat × List Nat)) z =>
          match best with
          | none => some (z.2, (preKey .smallRhs a z.1,
              (alGet a.pr z.1.lhs).getD 0, canonKey z.1))
          | some w => if scLt (preKey .smallRhs a z.1,
                        (alGet a.pr z.1.lhs).getD 0, canonKey z.1) w.2
                      then some (z.2, (preKey .smallRhs a z.1,
                        (alGet a.pr z.1.lhs).getD 0, canonKey z.1)) else some w)
          (fun o x => by cases o with | none => simp | some u => simp only []; split <;> simp) (y := (e0, 0))
          (t := (withIndex.go tl 1)) none
      rw [withIndex, withIndex.go] at hc
      rw [hc] at hs
      simp at hs
    | shipped | concFirst | smallRhs | fifo =>
      intro hc
      simp only [] at hc
      split at hc
      · rename_i hks
        exact withIndex_ne_nil (List.map_eq_nil_iff.mp hks)
      · rename_i k0 kt hks
        split at hc
        · rename_i hfil
          rw [List.filter_eq_nil_iff] at hfil
          rcases foldl_minBy_mem (fun t : Nat × Nat × Nat => t.2.1) kt k0.2.1 with hm | ⟨x, hx, hm⟩
          · have hcon := hfil k0 (by rw [hks]; exact List.mem_cons_self ..)
            rw [hm] at hcon; simp at hcon
          · have hcon := hfil x (by rw [hks]; exact List.mem_cons_of_mem _ hx)
            rw [hm] at hcon; simp at hcon
        · rename_i c0 ct hfil
          rw [Option.map_eq_none_iff, List.find?_eq_none] at hc
          rcases foldl_minBy_mem (fun t : Nat × Nat × Nat => t.2.2) ct c0.2.2 with hm | ⟨x, hx, hm⟩
          · have hcon := hc c0 (List.mem_cons_self ..)
            rw [hm] at hcon; simp at hcon
          · have hcon := hc x (List.mem_cons_of_mem _ hx)
            rw [hm] at hcon; simp at hcon
  · -- and it is an index of the queue
    cases pol with
    | canon =>
      intro i hi
      simp only [Option.map_eq_some_iff] at hi
      obtain ⟨w, hw, rfl⟩ := hi
      refine foldl_pick_lt (es := e0 :: tl) ?_ _ none hix (by simp) w hw
      · intro o z w h
        cases o with
        | none => exact Or.inl (by rw [← Option.some.inj h])
        | some u =>
          simp only [] at h
          split at h
          · exact Or.inl (by rw [← Option.some.inj h])
          · exact Or.inr h
    | smallCanon =>
      intro i hi
      simp only [Option.map_eq_some_iff] at hi
      obtain ⟨w, hw, rfl⟩ := hi
      refine foldl_pick_lt (es := e0 :: tl) ?_ _ none hix (by simp) w hw
      · intro o z w h
        cases o with
        | none => exact Or.inl (by rw [← Option.some.inj h])
        | some u =>
          simp only [] at h
          split at h
          · exact Or.inl (by rw [← Option.some.inj h])
          · exact Or.inr h
    | shipped | concFirst | smallRhs | fifo =>
      intro i hi
      simp only [] at hi
      split at hi
      · exact absurd hi (by simp)
      · rename_i k0 kt hks
        split at hi
        · exact absurd hi (by simp)
        · rename_i c0 ct hfil
          rw [Option.map_eq_some_iff] at hi
          obtain ⟨y, hy, rfl⟩ := hi
          have hym : y ∈ c0 :: ct := List.mem_of_find?_eq_some hy
          rw [← hfil] at hym
          obtain ⟨z, hz, hzy⟩ := List.mem_map.mp (List.mem_of_mem_filter hym)
          rw [← hzy]
          exact hix z hz

/-- **Every policy's `pop` returns `none` only on an EMPTY queue** -- so `stepP`'s acceptance
branch is reached exactly when the queue is exhausted, for every order.  This is the fact the
Scala mirror must not get wrong: a `pop` that answered `none` on a non-empty queue would make
`incorporateAll` return `proc` and the solve ACCEPT without saturating. -/
theorem dequeuePol_none {pol : Policy} {a : Aux} {q : PQueue}
    (h : dequeuePol pol a q = none) : q.elems = [] := by
  cases pol with
  | shipped => simp only [dequeuePol] at h; exact dequeue_none h
  | concFirst => simp only [dequeuePol] at h; exact dequeueAlt_none h
  | smallRhs => simp only [dequeuePol] at h; exact dequeueAlt_none h
  | fifo => simp only [dequeuePol] at h; exact dequeueAlt_none h
  | canon => simp only [dequeuePol] at h; exact dequeueAlt_none h
  | smallCanon => simp only [dequeuePol] at h; exact dequeueAlt_none h

/-- ...and the converse, which is immediate. -/
theorem dequeuePol_nil {pol : Policy} {a : Aux} {q : PQueue} (h : q.elems = []) :
    dequeuePol pol a q = none := by
  cases pol with
  | shipped => simp only [dequeuePol, PQueue.dequeue, h]
  | concFirst => simp only [dequeuePol, dequeueAlt, h]
  | smallRhs => simp only [dequeuePol, dequeueAlt, h]
  | fifo => simp only [dequeuePol, dequeueAlt, h]
  | canon => simp only [dequeuePol, dequeueAlt, h]
  | smallCanon => simp only [dequeuePol, dequeueAlt, h]

/-! ### The other two lemmas of the §5 inventory, from the shape -/

/-- `NoConc.kdist_dequeue` for any policy: key-distinctness survives a dequeue, because the
queue that is left is a sublist of the queue that was given. -/
theorem shape_kdist {q : PQueue} {r : LPart} {rest : PQueue} (h : DequeueShape q r rest)
    (hk : KDist q.elems) : KDist rest.elems := by
  obtain ⟨i, -, rfl⟩ := h
  exact kdist_sublist (List.eraseIdx_sublist _ i) hk

/-- `RefineConcrete.dequeue_unique` for any policy: `pop` is a function. -/
theorem dequeuePol_unique {pol : Policy} {a : Aux} {q : PQueue} {r r0 : LPart}
    {rest rest0 : PQueue} (h1 : dequeuePol pol a q = some (r, rest))
    (h2 : dequeuePol pol a q = some (r0, rest0)) : r0 = r ∧ rest0 = rest := by
  rw [h1] at h2
  simp only [Option.some.injEq, Prod.mk.injEq] at h2
  exact ⟨h2.1.symm, h2.2.symm⟩

end Rowpartition.Loop
