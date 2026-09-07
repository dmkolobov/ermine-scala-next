/-
# From a `json:` seed to the initial state

The repro harness (`tracker/repro/satterm/SatTermRepro.scala`, `seedFromJson` / `system`)
turns a `rowclosure.py` seed and an id BASE into a `List[Type]` of raw `Part`s, and
`Subst.solve` turns that into the initial `PQueue`.  Neither step is a formality: between
them sit `Exists.apply`'s `p.toSet.toList` (twice, once in the smart constructor and once in
`.nf`) and `PQueue.build`'s `RHS.build`, and both reorder.

* `Exists.apply(l, Nil, q)` with `q.length > 1` REVERSES `q` and then runs it through
  `Set` -- so for four constraints or fewer the reversal cancels and the order is the
  input's, and for five or more the order is the CHAMP order of `Part.hashCode`.
  `Type.nf` on the result applies the same constructor again.
* `Part.hashCode = 3 + 23 * lhs.hashCode + 5 * rhs.hashCode` with `VarT.hashCode = id`
  (the `Variable` trait, `Vars.scala:143`), `ConcreteRho.hashCode = fields.hashCode * 111`
  and `List.hashCode = MurmurHash3.listHash`.
* `RHS.build` folds the right-hand side LIST in order, so the variable set's insertion order
  is the order the labels were written in, and a variable that occurs twice is REMOVED from
  the set and reported as forced empty.

The `in` records of the compiler's trace show `cs`, the list `solve` received -- which is the
seed's order, because `unbindExists` does not reorder -- while the `inpart` records show the
QUEUE, which is where all of the above has been applied.
-/
import Rowpartition.Loop.Trace

namespace Rowpartition.Loop

/-! ## 1. Input row expressions -/

/-- A row expression in an input constraint.  A seed only ever writes the first two; the
corpus adds `Con`, which `RHS.build` treats as a one-label concrete row
(`Constraints.scala:394`), and `otherT` for anything else -- a shape `RHS.build`'s last case
dies on, carried here only so that `Part.hashCode`, and hence `Exists.apply`'s ordering, is
still exact. -/
inductive ITerm where
  | varT (v : Nat)
  | concRho (fs : SSet Lbl)
  | conT (n : Lbl)
  | otherT (h : I32)

namespace ITerm

/-- `VarT.hashCode = v.hashCode = id` (the `Variable` trait);
`ConcreteRho.hashCode = fields.hashCode * 111` (`Type.scala:152`);
`Con.hashCode = 92 + 13 * name.hashCode` (`Type.scala:536`). -/
def hshOf : ITerm → I32
  | .varT v => UInt32.ofNat v
  | .concRho fs => fs.hsh * 111
  | .conT n => 92 + 13 * n.hshOf
  | .otherT h => h

def eqv : ITerm → ITerm → Bool
  | .varT a, .varT b => a == b
  | .concRho a, .concRho b => a.eqv b
  | .conT a, .conT b => SVal.eq a b
  | .otherT a, .otherT b => a == b
  | _, _ => false

/-- `Subst.solve`'s trace helper `st`. -/
def toStr (ns : Names) : ITerm → String
  | .varT v => ns.sv v
  | .concRho fs =>
    "(|" ++ String.intercalate "," (sortStrings (fs.toList.map Lbl.toStr)) ++ "|)"
  | .conT n => "(|" ++ Lbl.toStr n ++ "|)"
  | .otherT h => "?" ++ toString h.toNat

end ITerm

/-- A raw `Part(loc, lhs, rhs)`. -/
structure IPart where
  lhs : ITerm
  rhs : List ITerm

namespace IPart

/-- `Part.hashCode` (`Type.scala:396`). -/
def hshOf (p : IPart) : I32 :=
  3 + 23 * p.lhs.hshOf + 5 * Murmur.seqHash (p.rhs.map ITerm.hshOf)

/-- `Part.equals`: the location is ignored. -/
def eqv (p q : IPart) : Bool :=
  p.lhs.eqv q.lhs && p.rhs.length == q.rhs.length &&
  (p.rhs.zip q.rhs).all (fun t => t.1.eqv t.2)

end IPart

instance svalIPart : SVal IPart where
  eq := IPart.eqv
  hsh := IPart.hshOf

/-! ## 1b. One element of the constraint list `PQueue.build` receives

`solve` hands `PQueue.build` an `Exists` over the WHOLE list `unbindExists` returned, and
`aux` turns only the `Part`s of it into partitions.  But every element is in the list
`Exists.apply` puts through `p.toSet.toList`, so an element the solver never looks at can
still MOVE the ones it does.  `other` is such an element, reduced to what that reordering
reads: its `hashCode`, and the index of the first element of the list it is `equals` to
(the trace's `scon` fields, `RowTrace.scala`). -/
inductive CsItem where
  | part (p : IPart)
  /-- `hashCode`, and the `eqid` that stands in for `equals`. -/
  | other (h : I32) (eqid : Nat)

namespace CsItem

def hshOf : CsItem → I32
  | .part p => p.hshOf
  | .other h _ => h

def eqv : CsItem → CsItem → Bool
  | .part p, .part q => p.eqv q
  | .other _ a, .other _ b => a == b
  | _, _ => false

def part? : CsItem → Option IPart
  | .part p => some p
  | .other _ _ => none

end CsItem

instance svalCsItem : SVal CsItem where
  eq := CsItem.eqv
  hsh := CsItem.hshOf

/-! ## 2. `Exists.apply` and `PQueue.build` -/

/-- `Exists.apply(l, Nil, q)`, as it acts on the constraint LIST: identity at one element,
otherwise reverse then `toSet.toList`. -/
def existsApply {α : Type} [SVal α] (q : List α) : List α :=
  if q.length == 1 then q
  else (SSet.ofList (q.foldl (fun r t => t :: r) [])).toList

/-- `Constraints.RHS.build`: fold the right-hand side list, collecting variables, labels and
the variables that occurred TWICE (which are forced empty). -/
def rhsBuild (ts : List ITerm) : Except String (RHS × List Nat) :=
  let step := fun (acc : Except String (SSet Nat × SSet Lbl × SSet Nat)) (t : ITerm) => do
    let (a, c, e) ← acc
    match t with
    | .concRho s =>
      let i := c.inter s
      if i.isEmpty then return (a, c.concat s, e)
      else .error ("Fields appear twice in row: " ++
                   String.intercalate "," (i.toList.map Lbl.toStr))
    | .varT v =>
      if a.contains v || e.contains v then return (a.excl v, c, e.incl v)
      else return (a.incl v, c, e)
    | .conT n => return (a, c.incl n, e)
    | .otherT _ => .error "panic: Malformed constraint, RHS"
  do
    let (a, c, e) ← ts.foldl step (.ok (SSet.empty, SSet.empty, SSet.empty))
    return (⟨a, c⟩, e.toList)

/-- `Q.PQueue.build`'s `aux`, for one `Part`. -/
def partToPartitions (p : IPart) (su : Sup) : Except String (List LPart × Sup) := do
  match p.lhs with
  | .varT v =>
    let (rhs, es) ← rhsBuild p.rhs
    return (⟨v, rhs, none⟩ :: es.map (fun u => (⟨u, RHS.empty, none⟩ : LPart)), su)
  | lhs =>
    -- `Part(loc, lhs, rhs)` with a non-variable left-hand side mints a name for it.
    let (v, su) := su.fresh
    let (rhs1, es1) ← rhsBuild p.rhs
    let (rhs2, es2) ← rhsBuild [lhs]
    return (⟨v, rhs1, none⟩ :: ⟨v, rhs2, none⟩ ::
            (es1 ++ es2).map (fun u => (⟨u, RHS.empty, none⟩ : LPart)), su)

/-! ## 2b. S4: the written-partition normalisation (`Flags.topNormalise`, DEFAULT OFF)

`tracker/loopmodel/S4-CHANGE.md`.  Mirrors `Constraints.topNormalise` / `Subst.solve`'s call to
it, which runs immediately after `PQueue.build` and BEFORE `labelCheckEarly`, `rowSoundDecide`
and `q.expand`, so all three input-reading checks and the loop see the SAME live input.

The trigger at one left-hand side `v`: `k ≥ 3` LONE-ABSTRACT partitions with non-empty concrete
parts whose DISTINCT concrete parts are pairwise INCOMPARABLE, and no concrete-row partition at
`v` (that case is `resRow`'s / `emptyRow`'s and they answer it without minting).  The rewrite
deletes the `k` reads and adds `v <- (c, F)` with `c` fresh and `F` their union, plus
`c_i <- (c, F \ F_i)` for each read.

**One pass over the ORIGINAL families** (S4A review G-11): every family is computed from the
queue as `buildQueue` left it, and the replacements are applied afterwards, so no rewrite can
see a family the input did not have and the result does not depend on the fold order.  The
candidate left-hand sides are taken in the QUEUE's own order, which is what the Scala's
`q.toList` gives, so the two mint the same ids in the same order. -/

/-- The families the rewrite fires on, in queue order: `(lhs, the reads, their union)`. -/
def topFamilies (q : PQueue) : List (Nat × List LPart × SSet Lbl) :=
  let ps := q.elems
  /- A READ is lone-abstract with a non-empty concrete part and NOT a SELF-READ `v <- (v, C)`;
     `Constraints.topFamilies`' `isRead` carries the reason (S4B review H-2: the rewrite deletes
     premises, and `noloss_of_top` is semantic while `selfSubstitution`'s occurs check is
     syntactic). -/
  let isRead := fun (p : LPart) =>
    (match p.rhs.abstrSingle? with | some x => x != p.lhs | none => false) &&
      !p.rhs.conc.isEmpty
  let cand := (ps.filterMap (fun p => if isRead p then some p.lhs else none)).eraseDups
  cand.filterMap (fun v =>
    if ps.any (fun p => p.lhs == v && p.rhs.abstr.isEmpty) then none
    else
      let fam := ps.filter (fun p => p.lhs == v && isRead p)
      let dis := (fam.map (fun p => p.rhs.conc)).foldl
        (fun acc c => if acc.any (fun d => d.eqv c) then acc else acc ++ [c]) []
      if dis.length < 3 then none
      else if !(dis.all (fun c => dis.all (fun d => c.eqv d || !(c.subsetOf d)))) then none
      else some (v, fam, dis.foldl (fun a c => a.concat c) SSet.empty))

/-- Apply the rewrite.  Returns the new queue, the supply, and one `(lhs, carrier, F)` per
family for the `tnorm` trace record. -/
def topNormalise (on : Bool) (q : PQueue) (su : Sup) :
    PQueue × Sup × List (Nat × Nat × SSet Lbl) :=
  if !on then (q, su, []) else
  let plans := topFamilies q
  if plans.isEmpty then (q, su, []) else
    let dead := plans.flatMap (fun t => t.2.1)
    let keep := q.elems.filter (fun p => !(dead.any (fun d => d.eqv p)))
    let step := fun (acc : List LPart × Sup × List (Nat × Nat × SSet Lbl))
                    (t : Nat × List LPart × SSet Lbl) =>
      let (added, su, rc) := acc
      let (c, su) := su.fresh
      let top : LPart := ⟨t.1, ⟨SSet.ofList [c], t.2.2⟩, some .topNormalise⟩
      let res := t.2.1.filterMap (fun p =>
        match p.rhs.abstrSingle? with
        | some x => some (⟨x, ⟨SSet.ofList [c], t.2.2.removedAll p.rhs.conc⟩,
                           some .topNormalise⟩ : LPart)
        | none => none)
      (added ++ (top :: res), su, rc ++ [(t.1, c, t.2.2)])
    let (added, su, rc) := plans.foldl step ([], su, [])
    (PQueue.ofList (keep ++ added), su, rc)

/-- `PQueue.build(Exists(l, Nil, cs))`, including the two `Exists.apply` passes.  `aux`'s
`case _ => (List(), List())` is why an `other` item contributes no partition. -/
def buildQueue (cs : List CsItem) (su : Sup) : Except String (PQueue × Sup) := do
  let cs2 := existsApply (existsApply cs)
  let (ps, su) ← cs2.foldl
    (fun (acc : Except String (List LPart × Sup)) (c : CsItem) => do
      let (l, su) ← acc
      match c with
      | .other _ _ => return (l, su)
      | .part p =>
        let (l', su) ← partToPartitions p su
        return (l ++ l', su))
    (.ok ([], su))
  return (PQueue.ofList ps, su)

/-! ## 3. The per-label refutation (`labelCheckEarly`, shipped ON) -/

/-- `Constraints.checkLabel`: unit-propagate the bits `[l ∈ x]` over the INPUT partitions.
`Some (v, msg)` is a contradiction found while processing the partition of `v`.  The Scala's
`while (changed && clash.isEmpty)` is bounded by the number of bits it can set, so the fuel
here is the number of partitions plus two and cannot run out early. -/
def checkLabel (ns : Names) (ps : List LPart) (l : Lbl) : Nat → List (Nat × Bool) → Bool →
    Option (Nat × String)
  | 0, _, _ => none
  | _ + 1, _, false => none
  | f + 1, bits0, true =>
    let stepOne := fun (st : List (Nat × Bool) × Bool × Option (Nat × String)) (p : LPart) =>
      if st.2.2.isSome then st else
      let bits := st.1
      let get := fun (v : Nat) => (bits.find? (fun q => q.1 == v)).map (·.2)
      let setVar := fun (acc : List (Nat × Bool) × Bool × Option (Nat × String))
          (v : Nat) (b : Bool) (why : String) =>
        match (acc.1.find? (fun q => q.1 == v)).map (·.2) with
        | some b0 => if b0 != b then
            (acc.1, acc.2.1, if acc.2.2.isSome then acc.2.2 else some (p.lhs, why)) else acc
        | none => (acc.1 ++ [(v, b)], true, acc.2.2)
      let conBit := p.rhs.conc.contains l
      let absList := p.rhs.abstr.toList
      let ones := (absList.filter (fun u => get u == some true)).length +
                  (if conBit then 1 else 0)
      let unknown := absList.filter (fun u => (get u).isNone)
      if ones > 1 then
        (bits, st.2.1, some (p.lhs, "two parts of one partition both contain it"))
      else
        let acc : List (Nat × Bool) × Bool × Option (Nat × String) := (bits, st.2.1, none)
        let acc := if ones == 1 then
            let acc := setVar acc p.lhs true "a part contains it but the whole does not"
            unknown.foldl (fun a u =>
              setVar a u false "two parts of one partition both contain it") acc
          else acc
        let get2 := fun (v : Nat) => (acc.1.find? (fun q => q.1 == v)).map (·.2)
        let acc := if get2 p.lhs == some false then
            let acc := if conBit then
              (acc.1, acc.2.1,
               if acc.2.2.isSome then acc.2.2
               else some (p.lhs, "a part contains it but the whole does not")) else acc
            unknown.foldl (fun a u =>
              setVar a u false "a part contains it but the whole does not") acc
          else acc
        let acc := if ones == 0 && unknown.isEmpty then
            setVar acc p.lhs false "the whole contains it but no part does" else acc
        let get3 := fun (v : Nat) => (acc.1.find? (fun q => q.1 == v)).map (·.2)
        let acc := if get3 p.lhs == some true && ones == 0 then
            match unknown with
            | [] => (acc.1, acc.2.1,
                     if acc.2.2.isSome then acc.2.2
                     else some (p.lhs, "the whole contains it but no part can"))
            | [u] => setVar acc u true "the whole contains it but no part can"
            | _ => acc
          else acc
        (acc.1, acc.2.1, acc.2.2)
    let (bits, changed, clash) := ps.foldl stepOne (bits0, false, none)
    match clash with
    | some c => some c
    | none => checkLabel ns ps l f bits changed
decreasing_by all_goals simp_wf

/-- `Constraints.labelClash`: the first label at which propagation refutes. -/
def labelClash (ns : Names) (ps : List LPart) : Option (Lbl × Nat × String) :=
  let labels := ps.foldl (fun (s : SSet Lbl) p => s.concat p.rhs.conc) SSet.empty
  labels.toList.findSome? (fun l =>
    (checkLabel ns ps l (ps.length + 2) [] true).map (fun (v, m) => (l, v, m)))

end Rowpartition.Loop
