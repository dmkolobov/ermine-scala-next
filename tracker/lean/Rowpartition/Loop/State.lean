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

/-- A field label: a `Name`, with the four things the compiler reads off one.

L1 modelled a label as a bare number `n`, standing for the repro harness's
`Global("Repro", "l" ++ toString n)`, and computed `hashCode` and `toString` from it.  The
corpus's labels are real qualified names, so L2 carries the name itself; `n` survives as the
label's INDEX in its solve's `slbl` table, which is what the bridge maps a label to (the
relational development's `Label` is `Nat`).  Distinct `Name`s get distinct indices --
`RowTrace.solveInput` numbers them out of a `LinkedHashMap[Name, Int]` keyed by Scala's own
`Name.equals` -- so within one solve `n` and the name determine each other; `Bridge.lean`
states that as `LblCoh` where it needs it, rather than assuming it. -/
structure Lbl where
  /-- The label's index in its solve's `slbl` table. -/
  n : Nat
  /-- `Global` (true) or `Local` (false).  `Name.equals` never identifies the two. -/
  glob : Bool := true
  /-- `Global.module`; `""` for a `Local`. -/
  mod : String := ""
  /-- `Name.string`. -/
  str : String := ""
  /-- `Fixity.con`: `Idfix` 1, `Prefix` 2, `Infix` and `Postfix` 3.  `Name.equals` and
  `Name.hashCode` read the `con`, not the fixity. -/
  con : Nat := 1
deriving DecidableEq, Repr, Inhabited, BEq

namespace Lbl

/-- The repro harness's label `n`: `Global("Repro", "l" ++ toString n, Idfix)`. -/
def repro (n : Nat) : Lbl := { n := n, glob := true, mod := "Repro", str := "l" ++ toString n }

/-- `Name.toString`.  `Global` prints `module ++ "." ++ string` at `Idfix` and
`module ++ ".(" ++ string ++ ")"` otherwise (`Name.scala:31`); `Local` prints its string. -/
def toStr (l : Lbl) : String :=
  if l.glob then
    (if l.con == 1 then l.mod ++ "." ++ l.str else l.mod ++ ".(" ++ l.str ++ ")")
  else l.str

/-- `Name.hashCode`: `(2, module, string, fixity.con).hashCode` for a `Global`
(`Name.scala:39`) and `(1, string, fixity.con).hashCode` for a `Local` (`Name.scala:24`). -/
def hshOf (l : Lbl) : I32 :=
  if l.glob then
    Murmur.productHash "Tuple4"
      [2, javaStringHash l.mod, javaStringHash l.str, UInt32.ofNat l.con]
  else
    Murmur.productHash "Tuple3" [1, javaStringHash l.str, UInt32.ofNat l.con]

end Lbl

/-- `Name.equals` is structural on `(kind, module, string, fixity.con)` (`Name.scala:20,35`),
and a `Global` never equals a `Local`.  `decide` on the derived `DecidableEq` is exactly
that, and it compares the table index first, so two labels of one solve are separated by a
`Nat` test. -/
instance svalLbl : SVal Lbl where
  eq a b := decide (a = b)
  hsh := Lbl.hshOf

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

/-! ## 3b. The id supply -/

/-- `scalaparsers.Supply`, exactly.

L1 modelled the supply as a single counter, which is right for a `json:` seed: the repro
harness builds `Supply(base, base + 100000)` and no seed draws 100 000 ids.  It is NOT right
for the corpus.  A real `Supply` owns a BLOCK of 1024 ids, and

```scala
def fresh: Int = if (lo != hi) { val r = lo; lo = r + 1; r }
                 else { val r = getBlock; hi = r + blockSize - 1; lo = r + 1; r }
```

so when the block runs out the next id is whatever the GLOBAL counter `Supply.block` hands
out -- a jump of a thousand or more, which changes `V.hashCode`, which changes the queue
order.  677 of the 83 942 solves in the `Ai` corpus start with fewer than ten ids left in
their block, and two of them actually cross the boundary while minting; before this was
modelled those two were the only disagreements left in that corpus.  The trace's `sin`
record carries `lo`, `hi`, the global counter and the block size, so the model can follow
`fresh` exactly, block changes and all. -/
structure Sup where
  /-- The next id, `Supply.lo`. -/
  lo : Nat
  /-- The last id of the current block, `Supply.hi`. -/
  hi : Nat
  /-- `Supply.block`, the global counter `getBlock` returns and then advances. -/
  blk : Nat
  /-- `Supply.blockSize`, 1024. -/
  bsz : Nat
  /-- How many ids have been drawn, for the harness's `drawn=` report. -/
  drawn : Nat := 0
deriving Inhabited, Repr

namespace Sup

/-- `Supply.fresh`. -/
def fresh (s : Sup) : Nat × Sup :=
  if s.lo != s.hi then (s.lo, { s with lo := s.lo + 1, drawn := s.drawn + 1 })
  else
    (s.blk, { s with lo := s.blk + 1, hi := s.blk + s.bsz - 1, blk := s.blk + s.bsz,
                     drawn := s.drawn + 1 })

/-- The repro harness's `supplyAt(lo)`: `Supply(lo, lo + 100000)`, which no seed exhausts. -/
def ofSeed (lo : Nat) : Sup := { lo := lo, hi := lo + 100000, blk := 0, bsz := 1024 }

end Sup

/-! ## 4. Partitions -/

/-- `Constraints.Partition`.  `equals` and `hashCode` IGNORE the `Inference` tag
(`Constraints.scala:1062-1067`), so two partitions that differ only in provenance are the
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

/-- What the trace records need about a variable beyond its id: the `V.name` the population
records print and the `VarType` `Partition.toString` prints. -/
structure Names where
  /-- `id ↦ V.name.toString`; a variable with `V.name = None` is absent. -/
  named : List (Nat × String)
  /-- `id ↦ V.ty.toString`, from the trace's `svar` records — `Free`, `Skolem`, `Bound`,
  `Unspecified`, `Ambiguous(Free)`, ...  EVERY input variable of the solve is listed.  A
  variable that is not is a MINT, and every mint the loop makes is `Ambiguous(Free)`
  (`Constraints.scala`'s five `fresh(Loc.builtin, none, Ambiguous(Free), Rho(...))` sites),
  which is what the fallback in `pvar` says.  L1 had no such table and inferred the flavour
  from the id; that is exact for a `json:` seed and wrong for real code, which is L1 review
  F7 and the reason this field exists. -/
  tys : List (Nat × String) := []
  /-- The first id the `Supply` will hand out. -/
  supplyLo : Nat
deriving Inhabited

namespace Names

def nameOf (ns : Names) (v : Nat) : Option String :=
  (ns.named.find? (fun p => p.1 == v)).map (·.2)

/-- `VarType.toString.toLowerCase`. -/
def lower (s : String) : String := s.map Char.toLower

/-- `V.ty.toString` for a variable the `svar` table lists; `Ambiguous(Free)` for one it does
not, which is a mint. -/
def tyOf (ns : Names) (v : Nat) : String :=
  match ns.tys.find? (fun p => p.1 == v) with
  | some p => p.2
  | none => "Ambiguous(Free)"

/-- `v.ty == Skolem`, the one flavour test the LOOP makes (`Constraints.scala:1587`, in
`makeEmpty`).  `Ambiguous(Skolem)` is NOT `Skolem`: the Scala compares the case object. -/
def isSkolem (ns : Names) (v : Nat) : Bool := ns.tyOf v == "Skolem"

/-- `Partition.toString`'s `pvar`: `'^' + ty.toString.toLowerCase + id`.  The `svar` table
decides the flavour; with no entry the variable is a mint, whose `ty` is `Ambiguous(Free)`.
(The `v < supplyLo` arm is L1's rule, kept so that a `json:` seed, which carries no table,
prints exactly what it printed before.) -/
def pvar (ns : Names) (v : Nat) : String :=
  match ns.tys.find? (fun p => p.1 == v) with
  | some p => "^" ++ lower p.2 ++ toString v
  | none => if v < ns.supplyLo then "^free" ++ toString v else "^ambiguous(free)" ++ toString v

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
  /-- S2 (`tracker/loopmodel/S2-DESIGN.md`) layer (i): `-Dermine.rowSound.bare`.  At a BARE
  definition `v <- ((|C|))` and a concrete instantiation `v := ((|fs|))`, require `C = fs`
  instead of `ensureSuperset`'s `C ⊆ fs`.

  ADOPTED 2026-09-06 (`tracker/loopmodel/A1-ADOPTION.md`): DEFAULT ON, like the compiler's
  (`Constraints.GenRules.rowSoundBare`).  `--flags=norowsound` turns all three layers off
  and `--flags=norsbare` this one, which is the configuration every pre-adoption trace and
  every pre-adoption theorem measurement was taken at. -/
  rowSoundBare : Bool := true
  /-- S2 layer (ii): `-Dermine.rowSound.saturated`.  Run `labelClash` on the SATURATED set as
  well as on the input.  ADOPTED 2026-09-06: DEFAULT ON, like the compiler's. -/
  rowSoundSat : Bool := true
  /-- S2 layer (iii): `-Dermine.rowSound.decide`.  The COMPLETE per-label decision on the
  live input -- the layer `Loop/NoFalseAccept.lean`'s `solve_noFalseAccept` and
  `solve_accepted_faithful` are about.  ADOPTED 2026-09-06: DEFAULT ON, like the compiler's. -/
  rowSoundDecide : Bool := true
  /-- S2: `-Dermine.rowSound.budget`, decision nodes per label for layer (iii).  On
  exhaustion the decision returns NO VERDICT and refutes nothing. -/
  rowSoundBudget : Nat := 200000
  /-- S2 review V-12: `-Dermine.rowSound.solveBudget`, a cap on the decision nodes ONE SOLVE
  may spend summed over its labels.  The per-label budget alone bounds the worst case at
  `#labels` times the per-label cost; this bounds it once.  Exhaustion is NO VERDICT. -/
  rowSoundSolveBudget : Nat := 1000000
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
  (if f.emptyRow then "+emptyrow" else "") ++
  (if f.rowSoundBare then "+rsbare" else "") ++
  (if f.rowSoundSat then "+rssat" else "") ++
  (if f.rowSoundDecide then "+rsdecide" else "")

end Flags

end Rowpartition.Loop
