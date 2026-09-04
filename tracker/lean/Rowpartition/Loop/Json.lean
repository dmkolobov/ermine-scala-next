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

/-- The two shapes a seed's row expression can take: `VarT(v)` and `ConcreteRho(fs)`. -/
inductive ITerm where
  | varT (v : Nat)
  | concRho (fs : SSet Lbl)

namespace ITerm

/-- `VarT.hashCode = v.hashCode = id`; `ConcreteRho.hashCode = fields.hashCode * 111`. -/
def hshOf : ITerm → I32
  | .varT v => UInt32.ofNat v
  | .concRho fs => fs.hsh * 111

def eqv : ITerm → ITerm → Bool
  | .varT a, .varT b => a == b
  | .concRho a, .concRho b => a.eqv b
  | _, _ => false

/-- `Subst.solve`'s trace helper `st`. -/
def toStr (ns : Names) : ITerm → String
  | .varT v => ns.sv v
  | .concRho fs =>
    "(|" ++ String.intercalate "," (sortStrings (fs.toList.map Lbl.toStr)) ++ "|)"

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

instance : SVal IPart where
  eq := IPart.eqv
  hsh := IPart.hshOf

/-! ## 2. `Exists.apply` and `PQueue.build` -/

/-- `Exists.apply(l, Nil, q)`, as it acts on the constraint LIST: identity at one element,
otherwise reverse then `toSet.toList`. -/
def existsApply (q : List IPart) : List IPart :=
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
  do
    let (a, c, e) ← ts.foldl step (.ok (SSet.empty, SSet.empty, SSet.empty))
    return (⟨a, c⟩, e.toList)

/-- `Q.PQueue.build`'s `aux`, for one `Part`. -/
def partToPartitions (p : IPart) (su : Nat) : Except String (List LPart × Nat) := do
  match p.lhs with
  | .varT v =>
    let (rhs, es) ← rhsBuild p.rhs
    return (⟨v, rhs, none⟩ :: es.map (fun u => (⟨u, RHS.empty, none⟩ : LPart)), su)
  | .concRho _ =>
    -- `Part(loc, lhs, rhs)` with a non-variable left-hand side mints a name for it.
    let v := su
    let (rhs1, es1) ← rhsBuild p.rhs
    let (rhs2, es2) ← rhsBuild [p.lhs]
    return (⟨v, rhs1, none⟩ :: ⟨v, rhs2, none⟩ ::
            (es1 ++ es2).map (fun u => (⟨u, RHS.empty, none⟩ : LPart)), su + 1)

/-- `PQueue.build(Exists(l, Nil, cs))`, including the two `Exists.apply` passes. -/
def buildQueue (cs : List IPart) (su : Nat) : Except String (PQueue × Nat) := do
  let cs2 := existsApply (existsApply cs)
  let (ps, su) ← cs2.foldl
    (fun (acc : Except String (List LPart × Nat)) (p : IPart) => do
      let (l, su) ← acc
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
