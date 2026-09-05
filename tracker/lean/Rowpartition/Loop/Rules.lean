/-
# The inference rules, branch for branch

`Constraints.scala`: `selfSubstitution` (1156), `splitConcrete` (1301), `cancellation` (1667),
`resolution` (1758), `subBody`/`substitution` (1807/1821), `commonSubexpression` (1834),
`disjunction` (1867).

Two things every rule here has to get right and a relation does not:

* the SET each rule returns is a `scala.collection.immutable.Set`, and the caller iterates
  it -- into the queue, and into the `learn` trace records.  So the rules build `SSet`s in
  the Scala's own insertion order;
* `fresh` is drawn where the Scala draws it, not where the mint is used.  `resolution` draws
  ONE id per call that reaches the lone-variable case, even when it returns nothing;
  `splitConcrete` draws only in its final branch.  Getting this wrong shifts every later
  mint's id and every trace line that names one.

A rule that can `die` returns `Except String`; the message is the Scala's, including its
`V.toString` (`name^id` for a named variable, the bare id for a mint).
-/
import Rowpartition.Loop.Queue

namespace Rowpartition.Loop

/-- `V.toString` (`Vars.scala:111`), which the error messages interpolate. -/
def varStr (ns : Names) (v : Nat) : String :=
  match ns.nameOf v with
  | some n => n ++ "^" ++ toString v
  | none => toString v

/-- `Set.toString`, which the "fields appear twice" message interpolates. -/
def labelSetStr (s : SSet Lbl) : String :=
  "Set(" ++ String.intercalate ", " (s.toList.map Lbl.toStr) ++ ")"

/-! ## `RHS.merge` and `RHS.substitute` -/

/-- `RHS.merge`: union, minus the variables common to both, and die on a common label. -/
def rhsMerge (r s : RHS) : Except String (RHS × SSet Nat) :=
  let aint := r.abstr.inter s.abstr
  let cint := r.conc.inter s.conc
  if cint.isEmpty then
    .ok (⟨(r.abstr.concat s.abstr).removedAll aint, r.conc.concat s.conc⟩, aint)
  else .error ("Fields appear twice in row: " ++ labelSetStr cint)

/-- `RHS.substitute`. -/
def rhsSubstitute (r : RHS) (v : Nat) (s : RHS) : Except String (RHS × SSet Nat) :=
  if r.abstr.contains v then rhsMerge (r.erase v) s else .ok (r, SSet.empty)

/-! ## Self substitution -/

/-- `Constraints.selfSubstitution`. -/
def selfSubstitution (ns : Names) (v : Nat) (abstr : SSet Nat) (concr : SSet Lbl) :
    Except String (SSet LPart) :=
  if concr.isEmpty then
    .ok ((abstr.excl v).map (fun u => ⟨u, RHS.empty, some .selfSubstitution⟩))
  else .error ("Infinite row partition for '" ++ varStr ns v ++ "'")

/-! ## Split concrete -/

/-- `Constraints.splitConcrete`, all five branches in order: syntactic reuse, keyed reuse
(`splitKey`), concrete-row reuse (`splitRow`), empty-row reuse (`emptyRow`), mint.  Returns
the derived set and the supply after the call. -/
def splitConcrete (fl : Flags) (v : Nat) (abstr : SSet Nat) (concr : SSet Lbl)
    (rhss : RHS → Option Nat) (resolvent concRow emptyRow : SSet Lbl → Option Nat)
    (su : Sup) : SSet LPart × Sup :=
  if concr.isEmpty || abstr.size < 2 then (SSet.empty, su)
  else
    match rhss (RHS.ofAbstr abstr) with
    | some u => (SSet.ofList [⟨v, ⟨SSet.ofList [u], concr⟩, some .splitConcrete⟩], su)
    | none =>
      if !fl.splitMints then (SSet.empty, su)
      else
        match (if fl.splitKey then resolvent concr else none) with
        | some w => (SSet.ofList [⟨w, RHS.ofAbstr abstr, some .splitKeyed⟩], su)
        | none =>
          match (if fl.splitRow then concRow concr else none) with
          | some w => (SSet.ofList [⟨w, RHS.ofAbstr abstr, some .splitRow⟩], su)
          | none =>
            match (if fl.emptyRow then emptyRow concr else none) with
            | some _ =>
              (abstr.map (fun x => (⟨x, RHS.empty, some .splitEmpty⟩ : LPart)), su)
            | none =>
              let (u, su) := su.fresh
              (SSet.ofList
                [⟨u, RHS.ofAbstr abstr, some .splitConcrete⟩,
                 ⟨v, ⟨SSet.ofList [u], concr⟩, some .splitConcrete⟩], su)

/-! ## Cancellation -/

/-- `Constraints.cancellation`. -/
def cancellation (_v : Nat) (rhs1 rhs2 : RHS) : SSet LPart :=
  let absInt := rhs1.abstr.inter rhs2.abstr
  let conInt := rhs1.conc.inter rhs2.conc
  let xs := rhs1.abstr.removedAll absInt
  let ys := rhs2.abstr.removedAll absInt
  let fs := rhs1.conc.removedAll conInt
  let gs := rhs2.conc.removedAll conInt
  if fs.isEmpty && xs.size == 1 then
    match xs.elems with
    | x :: _ => SSet.ofList [⟨x, ⟨ys, gs⟩, some .cancellation⟩]
    | [] => SSet.empty
  else if gs.isEmpty && ys.size == 1 then
    match ys.elems with
    | y :: _ => SSet.ofList [⟨y, ⟨xs, fs⟩, some .cancellation⟩]
    | [] => SSet.empty
  else SSet.empty

/-! ## Resolution -/

/-- `Constraints.resolution`, four branches: resolvent reuse (`resGuard`), concrete-row reuse
(`resRow`), empty-row reuse (`emptyRow`), mint.  `fresh` is drawn ONCE per call that gets
past the lone-variable pattern, before any branch, so a reuse costs an id too. -/
def resolution (fl : Flags) (v : Nat) (rhs1 rhs2 : RHS)
    (resolvent concRow emptyRow : SSet Lbl → Option Nat) (su : Sup) : SSet LPart × Sup :=
  if !fl.resolves then (SSet.empty, su)
  else
    match rhs1.abstrSingle?, rhs2.abstrSingle? with
    | some x, some y =>
      let concr1 := rhs1.conc
      let concr2 := rhs2.conc
      let (z, su) := su.fresh
      let int := concr1.inter concr2
      let tops := concr1.removedAll int
      let bots := concr2.removedAll int
      if tops.isEmpty || bots.isEmpty then (SSet.empty, su)
      else
        let all := concr1.concat concr2
        match (if fl.resGuard then resolvent all else none) with
        | some w =>
          (SSet.ofList
            [⟨x, ⟨SSet.ofList [w], bots⟩, some .resolution⟩,
             ⟨y, ⟨SSet.ofList [w], tops⟩, some .resolution⟩], su)
        | none =>
          match (if fl.resRow then concRow all else none) with
          | some w =>
            (SSet.ofList
              [⟨x, ⟨SSet.ofList [w], bots⟩, some .resolutionRow⟩,
               ⟨y, ⟨SSet.ofList [w], tops⟩, some .resolutionRow⟩], su)
          | none =>
            match (if fl.emptyRow then emptyRow all else none) with
            | some _ =>
              (SSet.ofList
                [⟨x, RHS.ofConcr bots, some .resolutionEmpty⟩,
                 ⟨y, RHS.ofConcr tops, some .resolutionEmpty⟩], su)
            | none =>
              (SSet.ofList
                [⟨v, ⟨SSet.ofList [z], all⟩, some .resolution⟩,
                 ⟨x, ⟨SSet.ofList [z], bots⟩, some .resolution⟩,
                 ⟨y, ⟨SSet.ofList [z], tops⟩, some .resolution⟩], su)
    | _, _ => (SSet.empty, su)

/-! ## Substitution -/

/-- `Constraints.subBody`. -/
def subBody (v : Nat) (rhs1 : RHS) (u : Nat) (rhs2 : RHS) : Except String (SSet LPart) :=
  if rhs2.contains v then do
    let (nrhs, es) ← rhsSubstitute rhs2 v rhs1
    let s := es.map (fun w => (⟨w, RHS.empty, some .deDuplication⟩ : LPart))
    return s.incl ⟨u, nrhs, some .substitution⟩
  else return SSet.empty

/-- `Constraints.substitution`. -/
def substitution (v : Nat) (rhs1 : RHS) (u : Nat) (rhs2 : RHS) : Except String (SSet LPart) :=
  do return (← subBody v rhs1 u rhs2).concat (← subBody u rhs2 v rhs1)

/-! ## Common subexpression -/

/-- `Constraints.commonSubexpression`.  Under the shipped `genRules=cut` the final MINTING
branch returns nothing; the reuse and the two folding branches are untouched. -/
def commonSubexpression (fl : Flags) (v : Nat) (rhs1 : RHS) (u : Nat) (rhs2 : RHS)
    (rhss : RHS → Option Nat) (su : Sup) : SSet LPart × Sup :=
  let abstr1 := rhs1.abstr
  let abstr2 := rhs2.abstr
  let int := abstr1.inter abstr2
  let rhsCommon := RHS.ofAbstr int
  if int.size < 2 then (SSet.empty, su)
  else
    match rhss rhsCommon with
    | some z =>
      (SSet.ofList
        [⟨v, ⟨(abstr1.removedAll int).incl z, rhs1.conc⟩, some .commonSubexpression⟩,
         ⟨u, ⟨(abstr2.removedAll int).incl z, rhs2.conc⟩, some .commonSubexpression⟩], su)
    | none =>
      if rhs1.eqv rhsCommon then
        (SSet.ofList
          [⟨u, ⟨(abstr2.removedAll int).incl v, rhs2.conc⟩, some .commonSubexpression⟩], su)
      else if rhs2.eqv rhsCommon then
        (SSet.ofList
          [⟨v, ⟨(abstr1.removedAll int).incl u, rhs1.conc⟩, some .commonSubexpression⟩], su)
      else if !fl.cseMints then (SSet.empty, su)
      else
        let (z, su) := su.fresh
        (SSet.ofList
          [⟨z, rhsCommon, some .commonSubexpressionMint⟩,
           ⟨v, ⟨(abstr1.removedAll int).incl z, rhs1.conc⟩, some .commonSubexpressionMint⟩,
           ⟨u, ⟨(abstr2.removedAll int).incl z, rhs2.conc⟩, some .commonSubexpressionMint⟩],
         su)

/-! ## Disjunction -/

/-- `Constraints.disjunction`.  Its three call sites are behind `-Dermine.disjunction`, which
ships OFF; it is here so the flag is meaningful and so `fresh` is accounted for if it is ever
turned on.  Note the Scala draws `v` BEFORE the guards, and a second id in the last arm. -/
def disjunction (rhs1 rhs2 rhs3 : RHS) (su : Sup) : SSet LPart × Sup :=
  let conAll := (rhs1.conc.inter rhs2.conc).inter rhs3.conc
  let absAll := (rhs1.abstr.inter rhs2.abstr).inter rhs3.abstr
  let conC := (rhs1.conc.inter rhs2.conc).removedAll conAll
  let absc := (rhs1.abstr.inter rhs2.abstr).removedAll absAll
  let absr := (rhs2.abstr.inter rhs3.abstr).removedAll absAll
  let absz := (rhs1.abstr.inter rhs3.abstr).removedAll absAll
  let absu := ((rhs3.abstr.removedAll absz).removedAll absr).removedAll absAll
  let (v, su) := su.fresh
  if absz.isEmpty || (conC.isEmpty && absc.isEmpty) then (SSet.empty, su)
  else
    match absu.elems with
    | [] => (SSet.empty, su)
    | [u] => (SSet.ofList [⟨u, ⟨absc.incl v, conC⟩, some .disjunction⟩], su)
    | _ =>
      let (us, su) := su.fresh
      (SSet.ofList
        [⟨us, RHS.ofAbstr absu, some .disjunction⟩,
         ⟨us, ⟨absc.incl v, conC⟩, some .disjunction⟩], su)

end Rowpartition.Loop
