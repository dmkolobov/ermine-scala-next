/-
# Conformance: the JVM's answers, checked at build time

Every value below was printed by a Scala programme run against the compiler's own
classpath (`scala-library 2.13.18`, Scala 3.3.8), reproduced in
`tracker/loopmodel/L1-MODEL.md` §"Probing the JVM".  They are `#guard`s rather than prose so
that a change to `Hash.lean` or `SSet.lean` that breaks the correspondence breaks the BUILD.

If one of these ever fails, the model's queue order is wrong and the differential traces will
disagree; fix the hash, not the guard.
-/
import Rowpartition.Loop.Json

namespace Rowpartition.Loop

/-! ## `java.lang.String.hashCode` -/

#guard I32.toSigned (javaStringHash "Repro") == (78848890 : Int)
#guard I32.toSigned (javaStringHash "l1") == (3397 : Int)
#guard I32.toSigned (javaStringHash "RHS") == (81117 : Int)
#guard I32.toSigned Murmur.seqSeed == (83007 : Int)
#guard I32.toSigned Murmur.setSeed == (83010 : Int)

/-! ## `MurmurHash3.setHash`, i.e. `immutable.Set.hashCode` -/

#guard I32.toSigned (Murmur.setHash []) == (835491922 : Int)
#guard I32.toSigned (Murmur.setHash [1]) == (-1075495872 : Int)
#guard I32.toSigned (Murmur.setHash [1, 2]) == (-2081538426 : Int)
#guard I32.toSigned (Murmur.setHash [1, 2, 3, 7, 9]) == (696780465 : Int)

/-! ## `MurmurHash3.listHash`, i.e. `List.hashCode` -- including the range special case -/

#guard I32.toSigned (Murmur.seqHash []) == (473519988 : Int)
#guard I32.toSigned (Murmur.seqHash [5]) == (1669515522 : Int)
#guard I32.toSigned (Murmur.seqHash [1, 2, 3]) == (1836368899 : Int)
#guard I32.toSigned (Murmur.seqHash [1, 2, 3, 4, 5, 6, 7, 8]) == (-159536971 : Int)

/-! ## The solver's own case classes -/

/- `Global("Repro", "l1").hashCode`. -/
#guard I32.toSigned (Lbl.hshOf (Lbl.repro 1)) == (2069000494 : Int)

/- `RHS().hashCode`. -/
#guard I32.toSigned RHS.empty.hshOf == (-1285229852 : Int)

/- `RHS(Set(v1), Set()).hashCode`. -/
#guard I32.toSigned (RHS.hshOf ⟨SSet.ofList [1], SSet.empty⟩) == (-1065199571 : Int)

/- `RHS(Set(v1, v2), Set(Repro.l1)).hashCode`. -/
#guard I32.toSigned (RHS.hshOf ⟨SSet.ofList [1, 2], SSet.ofList [Lbl.repro 1]⟩) ==
  (-1720534804 : Int)

/- `Partition(v1, RHS()).hashCode`, which is `(v1, RHS()).hashCode`. -/
#guard I32.toSigned (LPart.hshOf ⟨1, RHS.empty, none⟩) == (257672878 : Int)

/- `ConcreteRho(-, Set(Repro.l100)).hashCode = fields.hashCode * 111`. -/
#guard I32.toSigned (ITerm.hshOf (.concRho (SSet.ofList [Lbl.repro 100]))) ==
  (1040573865 : Int)

/- `VarT(v0).hashCode = v0.hashCode = 0` (the `Variable` trait). -/
#guard I32.toSigned (ITerm.hshOf (.varT 0)) == (0 : Int)

/- `Part(VarT(v0), List(VarT(v2), ConcreteRho(Set(Repro.l100)))).hashCode`. -/
#guard I32.toSigned
  (IPart.hshOf ⟨.varT 0, [.varT 2, .concRho (SSet.ofList [Lbl.repro 100])]⟩) ==
  (1723884977 : Int)

/-! ## `immutable.Set`'s ITERATION ORDER

`Set1`..`Set4` iterate in insertion order; a `HashSet` in canonical CHAMP order. -/

#guard (SSet.ofList [3, 1, 2]).elems == [3, 1, 2]
#guard (SSet.ofList [3, 1, 2, 4]).elems == [3, 1, 2, 4]
#guard (SSet.ofList [3, 1, 2, 4, 5]).elems == [5, 1, 2, 3, 4]
#guard (SSet.ofList [5, 4, 3, 2, 1]).elems == [5, 1, 2, 3, 4]
#guard (SSet.ofList (List.range 10)).elems == [0, 5, 1, 6, 9, 2, 7, 3, 8, 4]
#guard (SSet.ofList (List.range 6)).elems == [0, 5, 1, 2, 3, 4]
#guard (SSet.ofList [1000, 1001, 1002, 1003, 1004, 1005]).elems ==
  [1005, 1001, 1002, 1000, 1003, 1004]
#guard (SSet.ofList (List.range 41)).elems ==
  [0, 5, 10, 14, 1, 6, 9, 13, 2, 12, 18, 11, 8, 4, 15, 24, 37, 25, 20, 29, 21, 33, 28, 38,
   17, 32, 34, 22, 27, 7, 39, 3, 35, 16, 31, 40, 26, 23, 36, 30, 19]
#guard (SSet.ofList [1130, 763, 1248, 884, 1970, 1525, 1505, 918, 1519, 93, 1182, 1502, 1276,
    292, 476, 32, 456, 170, 743, 209]).elems ==
  [170, 93, 292, 456, 1970, 1525, 32, 743, 209, 1130, 1276, 763, 1248, 918, 1505, 1519, 1502,
   884, 1182, 476]

/-! ## `immutable.Set`'s REPRESENTATION, which decides the order after a shrink -/

/- `Set(3,1,2,4) + 5` is a `HashSet`, and stays one. -/
#guard ((SSet.ofList [3, 1, 2, 4]).incl 5).elems == [5, 1, 2, 3, 4]
/- `Set(3,1,2,4,5) - 5` keeps the CHAMP order of what is left, not the insertion order. -/
#guard (((SSet.ofList [3, 1, 2, 4, 5]).excl 5)).elems == [1, 2, 3, 4]
/- `Set(1,2,3,4) -- Set(1)` is still a `Set3`, in insertion order. -/
#guard ((SSet.ofList [1, 2, 3, 4]).removedAll (SSet.ofList [1])).elems == [2, 3, 4]
/- `Set(3,1,2) ++ Set(9,8)` grows past four and becomes a `HashSet`. -/
#guard ((SSet.ofList [3, 1, 2]).concat (SSet.ofList [9, 8])).elems == [1, 9, 2, 3, 8]
/- `Set(3,1,2) ++ Set(3,1)` does not grow, so it stays a `Set3`. -/
#guard ((SSet.ofList [3, 1, 2]).concat (SSet.ofList [3, 1])).elems == [3, 1, 2]
/- `Set(30,20,10) ++ Set(1,2)`. -/
#guard ((SSet.ofList [30, 20, 10]).concat (SSet.ofList [1, 2])).elems == [10, 20, 1, 2, 30]
/- `Set(1,2) ++ Set(3,4,5,6,7)`. -/
#guard ((SSet.ofList [1, 2]).concat (SSet.ofList [3, 4, 5, 6, 7])).elems ==
  [5, 1, 6, 2, 7, 3, 4]
/- `Set(3,1,2,4,5) & Set(1,2)` keeps the receiver's order and representation. -/
#guard ((SSet.ofList [3, 1, 2, 4, 5]).inter (SSet.ofList [1, 2])).elems == [1, 2]
/- `Set(1,2,3,4) & Set(1,3)` is a `Set2`. -/
#guard ((SSet.ofList [1, 2, 3, 4]).inter (SSet.ofList [1, 3])).elems == [1, 3]
/- `Set(3,1,2).map(_+10)` builds a `Set3` in the receiver's order. -/
#guard ((SSet.ofList [3, 1, 2]).map (· + 10)).elems == [13, 11, 12]
/- `Set(3,1,2,4,5).map(_+10)` maps a `HashSet` to a `HashSet`. -/
#guard ((SSet.ofList [3, 1, 2, 4, 5]).map (· + 10)).elems == [14, 13, 12, 11, 15]
/- `Set(1,2,3,4).map(_%2)` collapses to a `Set2`, in the receiver's order. -/
#guard ((SSet.ofList [1, 2, 3, 4]).map (· % 2)).elems == [1, 0]
/- `Set(3,1,2,4,5).map(_/100)` collapses a `HashSet` to a one-element `HashSet`. -/
#guard ((SSet.ofList [3, 1, 2, 4, 5]).map (· / 100)).elems == [0]
/- `Set(3,1,2,4,5).filter(_>2)`. -/
#guard ((SSet.ofList [3, 1, 2, 4, 5]).filter (· > 2)).elems == [5, 3, 4]

/-! ## `Set.hashCode` does not depend on the iteration order -/

#guard (SSet.ofList [3, 1, 2, 4, 5]).hsh == (SSet.ofList [5, 4, 3, 2, 1]).hsh

/-! ## L2: the label forms the CORPUS has, which a `json:` seed never produces

`Lbl` now carries the `Name` rather than a number.  These pin the three things that changed:
a qualified `Global` at a module other than `Repro`, a `Local`, and a non-`Idfix` fixity,
whose `toString` has parentheses and whose `con` is not 1.  The expected values are
`(2, module, string, con).hashCode` / `(1, string, con).hashCode` computed by the same
`Murmur.productHash` the JVM probes in `L1-MODEL.md` §5 validated, so what they really guard
is that `hshOf` dispatches on `glob` and reads `mod`, `str` and `con` and nothing else. -/

/- `Global("Prelude", "x").hashCode` = `(2, "Prelude", "x", 1).hashCode`. -/
#guard Lbl.hshOf { n := 0, glob := true, mod := "Prelude", str := "x", con := 1 } ==
  Murmur.productHash "Tuple4" [2, javaStringHash "Prelude", javaStringHash "x", 1]

/- `Local("x").hashCode` = `(1, "x", 1).hashCode`, and it is NOT the `Global`'s. -/
#guard Lbl.hshOf { n := 0, glob := false, mod := "", str := "x", con := 1 } ==
  Murmur.productHash "Tuple3" [1, javaStringHash "x", 1]
#guard Lbl.hshOf { n := 0, glob := false, mod := "", str := "x", con := 1 } !=
  Lbl.hshOf { n := 0, glob := true, mod := "", str := "x", con := 1 }

/- `Name.toString`: `Idfix` prints `module.string`, every other fixity `module.(string)`,
and a `Local` prints its string alone (`Name.scala:17,31`). -/
#guard Lbl.toStr { n := 0, glob := true, mod := "Prelude", str := "x", con := 1 } == "Prelude.x"
#guard Lbl.toStr { n := 0, glob := true, mod := "Prelude", str := "+", con := 3 } == "Prelude.(+)"
#guard Lbl.toStr { n := 0, glob := false, mod := "", str := "x", con := 1 } == "x"
#guard Lbl.toStr (Lbl.repro 100) == "Repro.l100"

/- `Fixity.con` is what `hashCode` reads, so `Infix` and `Postfix` (both 3) hash alike and
`Prefix` (2) does not -- which is why `slbl` records `con` and not the fixity. -/
#guard Lbl.hshOf { n := 0, glob := true, mod := "M", str := "f", con := 2 } !=
  Lbl.hshOf { n := 0, glob := true, mod := "M", str := "f", con := 3 }

/- `Con.hashCode = 92 + 13 * name.hashCode` (`Type.scala:536`). -/
#guard ITerm.hshOf (.conT (Lbl.repro 1)) == 92 + 13 * Lbl.hshOf (Lbl.repro 1)

/- `Partition.toString`'s `pvar` reads the `svar` table, and falls back to L1's id rule for a
variable the table does not list — i.e. for a mint. -/
#guard Names.pvar { named := [], tys := [(3, "Skolem"), (4, "Ambiguous(Skolem)")],
                    supplyLo := 10 } 3 == "^skolem3"
#guard Names.pvar { named := [], tys := [(3, "Skolem"), (4, "Ambiguous(Skolem)")],
                    supplyLo := 10 } 4 == "^ambiguous(skolem)4"
#guard Names.pvar { named := [], tys := [], supplyLo := 10 } 2 == "^free2"
#guard Names.pvar { named := [], tys := [], supplyLo := 10 } 11 == "^ambiguous(free)11"

end Rowpartition.Loop
