/-
# `RowTrace`'s TSV, emitted where the compiler emits it

`core/src/main/scala/com/clarifi/reporting/ermine/RowTrace.scala` and the two call sites:
`Constraints.incorporateAll` (the `step` and `learn` records) and `Subst.solve` (the `in`,
`ex`, `inpart`, `sat` and `solve` records, all written AFTER `q.expand` returns and BEFORE
`reduce` runs).

The record order in the file is therefore: every `step`/`learn` of the run, then `in*`,
`ex*`, `inpart*`, `sat*`, then the single `solve` line.  `concr` and `splice` records come
later, from `reduce`, which this model does not cover.
-/
import Rowpartition.Loop.Step

namespace Rowpartition.Loop

/-! ## String ordering, for the `sorted` calls in the population records -/

/-- `java.lang.String.compareTo < 0`: lexicographic by code unit, a prefix first. -/
def strLt (a b : String) : Bool :=
  let rec go : List Char → List Char → Bool
    | [], [] => false
    | [], _ :: _ => true
    | _ :: _, [] => false
    | x :: xs, y :: ys => if x == y then go xs ys else x.toNat < y.toNat
  go a.toList b.toList

/-- `List[String].sorted`. -/
def sortStrings (xs : List String) : List String :=
  xs.foldl (fun acc x =>
    let rec ins : List String → List String
      | [] => [x]
      | y :: ys => if strLt x y then x :: y :: ys else y :: ins ys
    ins acc) []

/-- `List[Int].sorted`. -/
def sortNats (xs : List Nat) : List Nat :=
  xs.foldl (fun acc x =>
    let rec ins : List Nat → List Nat
      | [] => [x]
      | y :: ys => if x ≤ y then x :: y :: ys else y :: ins ys
    ins acc) []

/-! ## The population records -/

/-- `Subst.solve`'s `sp`: provenance, left-hand variable, the SORTED variable names, the
SORTED labels. -/
def satBody (ns : Names) (p : LPart) : String :=
  (match p.inf with | some i => i.toStr | none => "INPUT") ++ "\t" ++
  ns.sv p.lhs ++ "\t" ++
  String.intercalate " " (sortStrings (p.rhs.abstr.toList.map (ns.sv ·))) ++ "\t" ++
  String.intercalate "," (sortStrings (p.rhs.conc.toList.map Lbl.toStr))

/-- One `inpart` or `sat` record.  `loc` is `RowTrace.clean(l.toString)`, the third column:
`-` for a seed (`Loc.builtin`), the solve's own location when replaying a compiler trace. -/
def popRecord (kind : String) (site : String) (loc : String) (ns : Names) (i : Nat)
    (p : LPart) : String :=
  kind ++ "\t" ++ site ++ "\t" ++ loc ++ "\t" ++ toString i ++ "\t" ++ satBody ns p

end Rowpartition.Loop
