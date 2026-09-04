/-
# The solver's vocabulary: labels, `RHS`, `Partition`, the environment, the flags

Transcribed from `core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`
(`RHS`, `Partition`, `Inference`, `GenRules`) and `Subst.scala` (`SubstEnv`,
`instantiateType`).

Two deliberate concretisations, both forced by the seeds this model is tested on and both
recorded in `tracker/loopmodel/L1-MODEL.md`:

* a row variable IS its `V.id` (`Nat`), because `V.equals` and `V.hashCode` look at nothing
  else (`Vars.scala:105-109`);
* a field label is the seed's label number `n`, standing for the `Global("Repro", "l" ++ n)`
  the repro harness builds -- so `Name.hashCode` and `Name.toString` are computable from it.
-/
import Rowpartition.Loop.SSet

namespace Rowpartition.Loop

/-! ## 1. Labels -/

/-- A field label: the repro harness's `Global("Repro", "l" ++ toString n)`. -/
structure Lbl where
  n : Nat
deriving DecidableEq, Repr, Inhabited

namespace Lbl

/-- `Name.toString` for a `Global` with `Idfix` fixity: `module ++ "." ++ string`. -/
def toStr (l : Lbl) : String := "Repro.l" ++ toString l.n

/-- `Global.hashCode = (2, module, string, fixity.con).hashCode` (`Name.scala:39`), with
`Idfix.con = 1`. -/
def hshOf (l : Lbl) : I32 :=
  Murmur.productHash "Tuple4"
    [2, javaStringHash "Repro", javaStringHash ("l" ++ toString l.n), 1]

end Lbl

instance svalLbl : SVal Lbl where
  eq a b := a.n == b.n
  hsh := Lbl.hshOf

instance : BEq Lbl := ⟨fun a b => a.n == b.n⟩

/-! ## 2. The right-hand side of a partition -/

/-- `Constraints.RHS`: a set of variables and a set of concrete labels. -/
structure RHS where
  abstr : SSet Nat
  conc : SSet Lbl

namespace RHS

def empty : RHS := ⟨SSet.empty, SSet.empty⟩

def isEmpty (r : RHS) : Bool := r.abstr.isEmpty && r.conc.isEmpty

/-- `RHS.isConcrete`: no variable parts. -/
def isConcrete (r : RHS) : Bool := r.abstr.isEmpty

def contains (r : RHS) (v : Nat) : Bool := r.abstr.contains v

def erase (r : RHS) (v : Nat) : RHS := ⟨r.abstr.excl v, r.conc⟩

/-- Case-class equality. -/
def eqv (r s : RHS) : Bool := r.abstr.eqv s.abstr && r.conc.eqv s.conc

/-- The synthetic case-class `hashCode`. -/
def hshOf (r : RHS) : I32 := Murmur.productHash "RHS" [r.abstr.hsh, r.conc.hsh]

/-- `RHSAbstr.apply`. -/
def ofAbstr (s : SSet Nat) : RHS := ⟨s, SSet.empty⟩

/-- `RHSConcr.apply`. -/
def ofConcr (s : SSet Lbl) : RHS := ⟨SSet.empty, s⟩

/-- `RHSAbstr(Single(u))`: a lone variable and NO labels.  This is the dispatch pattern of
`incorporateAll`, `Q.rhsLookup` and `Partition.isSelfUnification`. -/
def single? (r : RHS) : Option Nat :=
  if r.conc.isEmpty then r.abstr.single? else none

/-- `RHS(Single(w), con)`: a lone variable and ANY labels.  This is the pattern of
`learnPartitions`' `resolvents` fold and of `resolution`'s premise -- a different pattern
from `single?` above, and confusing the two silently turns every keyed reuse into a mint. -/
def abstrSingle? (r : RHS) : Option Nat := r.abstr.single?

end RHS

instance svalRHS : SVal RHS where
  eq := RHS.eqv
  hsh := RHS.hshOf

/-! ## 3. Provenance tags -/

/-- `Constraints.Inference`.  Never inspected by the solver; carried for the trace. -/
inductive Inference where
  | resolution | cancellation | selfSubstitution | substitution | partitionEmpty
  | splitConcrete | commonPartition | deDuplication | commonSubexpression
  | commonSubexpressionMint | splitKeyed | splitRow | resolutionRow | splitEmpty
  | resolutionEmpty | disjunction
deriving DecidableEq, Repr, Inhabited

namespace Inference

/-- The `toString` of the Scala case object, which is its name. -/
def toStr : Inference → String
  | .resolution => "Resolution"
  | .cancellation => "Cancellation"
  | .selfSubstitution => "SelfSubstitution"
  | .substitution => "Substitution"
  | .partitionEmpty => "PartitionEmpty"
  | .splitConcrete => "SplitConcrete"
  | .commonPartition => "CommonPartition"
  | .deDuplication => "DeDuplication"
  | .commonSubexpression => "CommonSubexpression"
  | .commonSubexpressionMint => "CommonSubexpressionMint"
  | .splitKeyed => "SplitKeyed"
  | .splitRow => "SplitRow"
  | .resolutionRow => "ResolutionRow"
  | .splitEmpty => "SplitEmpty"
  | .resolutionEmpty => "ResolutionEmpty"
  | .disjunction => "Disjunction"

end Inference

/-! ## 4. Partitions -/

/-- `Constraints.Partition`.  `equals` and `hashCode` IGNORE the `Inference` tag
(`Constraints.scala:1064-1071`), so two partitions that differ only in provenance are the
same element of every `Set` and of the queue. -/
structure LPart where
  lhs : Nat
  rhs : RHS
  inf : Option Inference := none

namespace LPart

def eqv (p q : LPart) : Bool := p.lhs == q.lhs && p.rhs.eqv q.rhs

/-- `(_1, _2).hashCode`, a `Tuple2` hash of the variable's id and the `RHS`'s hash. -/
def hshOf (p : LPart) : I32 :=
  Murmur.productHash "Tuple2" [UInt32.ofNat p.lhs, p.rhs.hshOf]

/-- `Partition.isSelfUnification`: `a <- (a)`. -/
def isSelfUnification (p : LPart) : Bool :=
  match p.rhs.single? with
  | some u => u == p.lhs
  | none => false

/-- `ruleInvolves u`. -/
def involves (p : LPart) (u : Nat) : Bool := p.lhs == u || p.rhs.contains u

end LPart

instance svalLPart : SVal LPart where
  eq := LPart.eqv
  hsh := LPart.hshOf

/-! ## 5. Printing, exactly as `Partition.toString` does -/

/-- The display names the repro harness gives the seed's variables, and the id below which a
variable is an input rather than a mint. -/
structure Names where
  /-- `id ↦ the `V.name` the harness gave it`; a mint has none. -/
  named : List (Nat × String)
  /-- The first id the `Supply` will hand out: at or above it, `V.ty = Ambiguous(Free)`. -/
  supplyLo : Nat
deriving Inhabited

namespace Names

def nameOf (ns : Names) (v : Nat) : Option String :=
  (ns.named.find? (fun p => p.1 == v)).map (·.2)

/-- `Partition.toString`'s `pvar`: `'^' + ty.toString.toLowerCase + id`.  An input variable
has `ty = Free`, a minted one `ty = Ambiguous(Free)` (`Constraints.scala:1338`,
`fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))`). -/
def pvar (ns : Names) (v : Nat) : String :=
  if v < ns.supplyLo then "^free" ++ toString v else "^ambiguous(free)" ++ toString v

/-- `Subst.solve`'s trace helper `sv`: `v.name.fold("")(_.toString) + "^" + v.id`. -/
def sv (ns : Names) (v : Nat) : String :=
  (ns.nameOf v).getD "" ++ "^" ++ toString v

end Names

namespace RHS

/-- `Partition.toString`'s `prhs`: the `Tuple2.toString` of the two `mkString(" ")`s, i.e.
`"(" ++ vars ++ "," ++ labels ++ ")"`.  Both sides iterate a `Set`, so both depend on the
`SSet` order model. -/
def toStr (ns : Names) (r : RHS) : String :=
  let vs := String.intercalate " " (r.abstr.map (ns.pvar ·) |>.toList)
  let cs := String.intercalate " " (r.conc.toList.map Lbl.toStr)
  "(" ++ vs ++ "," ++ cs ++ ")"

end RHS

namespace LPart

/-- `Partition.toString`. -/
def toStr (ns : Names) (p : LPart) : String :=
  (match p.inf with | some i => i.toStr ++ ": " | none => "") ++
  ns.pvar p.lhs ++ " <- " ++ p.rhs.toStr ns

end LPart

/-! ## 6. The substitution environment -/

/-- The only two shapes `incorporateAll` ever writes into `SubstEnv.types`:
`instantiateType(v, ConcreteRho(∅))` from `makeEmpty` and `instantiateType(v, VarT(u))` from
`instantiate`. -/
inductive EnvVal where
  | emptyRow
  | alias (u : Nat)
deriving DecidableEq, Repr, Inhabited

/-- `SubstEnv.types`, in insertion order.  `instantiateType` keeps it FULLY SUBSTITUTED --
`hm.types = subType(Map(v -> e), hm.types) + (v -> e)` -- so a lookup needs no chasing. -/
structure Env where
  binds : List (Nat × EnvVal) := []
deriving Inhabited

namespace Env

def lookup (e : Env) (v : Nat) : Option EnvVal :=
  (e.binds.find? (fun p => p.1 == v)).map (·.2)

def contains (e : Env) (v : Nat) : Bool := (e.lookup v).isSome

def size (e : Env) : Nat := e.binds.length

/-- `Subst.instantiateType`: rewrite every existing binding through `v ↦ val`, then add
`v ↦ val`.  The caller has already checked that `v` is unbound (the Scala panics otherwise);
`instantiate` is the panic. -/
def instantiate (e : Env) (v : Nat) (val : EnvVal) : Env :=
  let sub : EnvVal → EnvVal := fun w =>
    match w with
    | .alias u => if u == v then val else .alias u
    | .emptyRow => .emptyRow
  ⟨e.binds.map (fun p => (p.1, sub p.2)) ++ [(v, val)]⟩

end Env

/-! ## 7. The flags -/

/-- `Constraints.GenRules`, read once from system properties.  The defaults here are the
SHIPPED ones as of 2026-09-03: `genRules=cut`, `labelCheck`, `labelCheckEarly`, `resGuard`,
`splitKey`, `splitRow`, `resRow` on; `disjunction` and `emptyRow` off. -/
structure Flags where
  /-- `genRules=all`: `commonSubexpression` may mint. -/
  cseMints : Bool := false
  /-- `genRules ∈ {all, cut}`: `splitConcrete` may mint. -/
  splitMints : Bool := true
  /-- `genRules ∈ {all, cut}`: `resolution` fires at all. -/
  resolves : Bool := true
  disjRule : Bool := false
  labelCheck : Bool := true
  labelCheckEarly : Bool := true
  resGuard : Bool := true
  splitKey : Bool := true
  splitRow : Bool := true
  resRow : Bool := true
  emptyRow : Bool := false
deriving Inhabited

namespace Flags

/-- `GenRules.toString`, which the harness prints in its header line. -/
def toStr (f : Flags) : String :=
  (if f.cseMints then "all" else if f.splitMints then "cut" else "nongen") ++
  (if f.disjRule then "+disj" else "") ++
  (if f.labelCheck then "+label" else "") ++
  (if f.labelCheckEarly then "-early" else "") ++
  (if f.resGuard then "+resguard" else "") ++
  (if f.splitKey then "+splitkey" else "") ++
  (if f.splitRow then "+splitrow" else "") ++
  (if f.resRow then "+resrow" else "") ++
  (if f.emptyRow then "+emptyrow" else "")

end Flags

end Rowpartition.Loop
