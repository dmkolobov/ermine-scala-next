/-
# `scala.collection.immutable.Set`, modelled with its ITERATION ORDER

The solver reads sets in order in five places that reach the output:

* `TypeVarGraph.+` builds `newNodes = nodes ++ vs + u` and hands `newNodes.toStream` to
  `reverseTopSort` as the DFS root order -- so the topological index, i.e. the queue's
  PRIORITY, is a function of this order;
* `edgeFun` hands `newEdges.get(v)` to the same routine as the child order;
* `learnPartitions` returns a `Set[Partition]` which `++!` folds into the queue and
  `incorporateAll` prints one `learn` record per element;
* `instantiate`/`makeEmpty` fold a `Set[Partition]` into the incoming queue;
* `Partition.toString` prints `abs.map(pvar).mkString(" ")` and `con.mkString(" ")`.

Scala 2.13 has TWO representations and they iterate differently:

* `EmptySet`, `Set1`..`Set4` (size ≤ 4) iterate in INSERTION order;
* `immutable.HashSet` (a CHAMP trie) iterates in a CANONICAL order determined by
  `Hashing.improve(x.##)`: at each node the data entries first, in increasing 5-bit index
  order, then the sub-nodes, in increasing index order.

A set becomes a `HashSet` when it grows past four, or when it is derived from one, and it
never becomes a `SetN` again.  That is the whole of the model below: a flag plus a list.

Verified against the JVM for `+`, `-`, `++`, `--`, `&`, `map`, `filter` and `toSet` at sizes
0..41; the probe programme and its output are in `tracker/loopmodel/L1-MODEL.md`.
-/
import Rowpartition.Loop.Hash

namespace Rowpartition.Loop

/-- What Scala needs of a set element: `equals` and `hashCode`. -/
class SVal (α : Type) where
  eq : α → α → Bool
  hsh : α → I32

/-- A `scala.collection.immutable.Set`: the elements IN ITERATION ORDER, plus whether the
representation is a `HashSet` (canonical CHAMP order) or a `SetN` (insertion order). -/
structure SSet (α : Type) where
  hashed : Bool
  elems : List α

namespace SSet

variable {α β : Type} [SVal α]

/-- The CHAMP iteration order of a list of distinct elements: at each level, the elements
whose 5-bit index is unique (the node's data array) in increasing index order, then the
groups of two or more (its sub-nodes) in increasing index order, recursively.  `depth`
counts the seven 5-bit levels of a 32-bit hash; beyond them a real trie makes a collision
node, which keeps insertion order, and so does this. -/
def champSort : Nat → Nat → List α → List α
  | 0, _, xs => xs
  | d + 1, shift, xs =>
    if xs.length ≤ 1 then xs else
      let bucket : Nat → List α :=
        fun i => xs.filter (fun x => champMask (improve (SVal.hsh x)) shift == i)
      let data := List.flatten ((List.range 32).map
        (fun i => if (bucket i).length == 1 then bucket i else []))
      let subs := List.flatten ((List.range 32).map
        (fun i => if (bucket i).length == 1 then [] else champSort d (shift + 5) (bucket i)))
      data ++ subs

/-- Impose the CHAMP order on a list. -/
def champ (xs : List α) : List α := champSort 7 0 xs

/-- The empty set (`EmptySet`, a `SetN`). -/
def empty : SSet α := ⟨false, []⟩

/-- A set that is already a `HashSet` even though it is small -- the shape `filter`, `-` and
`map` leave behind. -/
def emptyHashed : SSet α := ⟨true, []⟩

def contains (s : SSet α) (x : α) : Bool := s.elems.any (fun y => SVal.eq x y)

def size (s : SSet α) : Nat := s.elems.length

def toList (s : SSet α) : List α := s.elems

def isEmpty (s : SSet α) : Bool := s.elems.isEmpty

/-- `s + x`.  Growing past four turns a `SetN` into a `HashSet`. -/
def incl (s : SSet α) (x : α) : SSet α :=
  if s.contains x then s
  else if s.hashed || s.elems.length + 1 > 4 then ⟨true, champ (s.elems ++ [x])⟩
  else ⟨false, s.elems ++ [x]⟩

/-- `s - x`.  The representation does not change -- a `HashSet` that shrinks below five stays
a `HashSet` -- but the SURVIVORS' ORDER can, and does.  `BitmapIndexedSetNode.removed`
(`HashSet.scala:603`) INLINES a sub-node that drops to one element into the parent as data:

```scala
case 1 =>
  if (this.size == subNode.size) subNodeNew.asInstanceOf[BitmapIndexedSetNode[A]]
  else copyAndMigrateFromNodeToInline(bitpos, elementHash, subNode, subNodeNew)  // move to front
```

and `foreach` emits all data before all sub-nodes, so that element MOVES FORWARD.  The result
is always the canonical CHAMP order of what is left, which is what re-`champ`ing computes.
(Found by the L1 review, F1: the model used to keep the pre-removal order with holes, which is
right only when no sub-node collapses.  `LBL.json` is the regression seed.) -/
def excl (s : SSet α) (x : α) : SSet α :=
  if s.hashed then ⟨true, champ (s.elems.filter (fun y => !SVal.eq x y))⟩
  else ⟨false, s.elems.filter (fun y => !SVal.eq x y)⟩

/-- `anyChangesMadeSoFar` for `BitmapIndexedSetNode.concat(that, shift)`: does the right node
change this one at all?

`HashSet.scala:1686` is the SECOND early return of the merge --

```scala
if (anyChangesMadeSoFar)
  new BitmapIndexedSetNode(dataMap = newDataMap, ...)   // right payloads at the overwrite slots
else this                                               // the whole LEFT node
```

-- and `leftDataRightDataLeftOverwrites` writes the right's payload into `newContent` WITHOUT
setting the flag.  So when nothing at a node actually changes, `concat` returns `this`, the
left node, and every one of its representatives survives -- at every depth, and even at slots
where both sides hold the element as data.  That is exactly the "right operand contained in
the left" case, which is the shape `destructiveSub`'s `srs` fold, `makeConcrete`'s `rhss` and
`makeEmpty`'s `qps ++ pps` produce.

This predicate subsumes the FIRST early return (`HashSet.scala:1532`,
`newDataMap == leftDataOnly | leftDataRightDataLeftOverwrites && newNodeMap == leftNodeOnly`):
whenever that condition holds no flag is set either.  The arms below are the flag's
assignments in `BitmapIndexedSetNode.concat`'s classification loop, slot by slot.
(Found by the L1 re-review, F2.) -/
def changed : Nat → List α → List α → Bool
  | 0, _, T => !T.isEmpty
  | d + 1, S, T =>
    let shift := 5 * (7 - (d + 1))
    let slot := fun (y : α) => champMask (improve (SVal.hsh y)) shift
    (List.range 32).any (fun j =>
      let Sj := S.filter (fun y => slot y == j)
      let Tj := T.filter (fun y => slot y == j)
      match Sj, Tj with
      | _, [] => false                                -- leftDataOnly / leftNodeOnly
      | [], _ => true                                 -- rightDataOnly / rightNodeOnly
      | [a], [b] => !SVal.eq a b                      -- overwrite (no change) / migrate (change)
      | [_], _ => true                                -- leftDataRightNode: unconditional
      | _, [b] => !(Sj.any (fun y => SVal.eq y b))    -- leftNodeRightData: `updated ne leftNode`
      | _, _ => changed d Sj Tj)                      -- leftNodeRightNode: recurse

/-- Which side's REPRESENTATIVE survives `HashSet ++ HashSet` at an element both hold.

This matters because `Partition.equals` and `RHS.equals` ignore, respectively, the `Inference`
tag and the sets' iteration order, so two `equals`-equal partitions are distinguishable in the
trace.  `HashSet.concat` is a CHAMP bulk union, not a fold.  If the right node changes this one
at all (`changed`, above), then at a trie slot where both sides carry the element as DATA the
RIGHT one overwrites the left (`leftDataRightDataLeftOverwrites`, `HashSet.scala:1667`); where
one side carries a SUBNODE the surviving representative is whichever side owns the node that
`updated` is called on -- `leftNodeRightData` keeps the LEFT, `leftDataRightNode` keeps the
RIGHT.  If it changes nothing, the LEFT node is returned whole and the left wins everywhere.
And a right operand of size one takes the `bm.size == 1` shortcut, `this.updated(...)`, which
keeps the LEFT. -/
def rightWins : Nat → List α → List α → α → Bool
  | 0, _, _, _ => true
  | d + 1, S, T, x =>
    if !changed (d + 1) S T then false
    else
      let shift := 5 * (7 - (d + 1))
      let slot := fun (y : α) => champMask (improve (SVal.hsh y)) shift
      let Si := S.filter (fun y => slot y == slot x)
      let Ti := T.filter (fun y => slot y == slot x)
      if Si.length == 1 && Ti.length == 1 then true
      else if Ti.length == 1 then false
      else if Si.length == 1 then true
      else rightWins d Si Ti x

/-- Which representative of `x` the CHAMP union keeps: `x` itself (the right operand's) or
the left operand's copy. -/
def pickRep (S T : List α) (x : α) : α :=
  match S.find? (fun y => SVal.eq y x) with
  | none => x
  | some sx => if rightWins 7 S T x then x else sx

/-- `s ++ t`.  `StrictOptimizedSetOps.concat` -- which every `SetN` uses, and which
`HashSet.concat` falls back to whenever `that` is not itself a `HashSet` -- is a fold of `+`,
and `+` keeps the element already present.  `HashSet ++ HashSet` with a right operand of two
or more is the one exception: see `rightWins`. -/
def concat (s : SSet α) (t : SSet α) : SSet α :=
  if s.hashed && t.hashed && !s.elems.isEmpty && t.elems.length > 1 then
    ⟨true, (champ ((s.elems.filter (fun x => !t.contains x)) ++ t.elems)).map
      (pickRep s.elems t.elems)⟩
  else t.elems.foldl incl s

/-- `s -- t`. -/
def removedAll (s : SSet α) (t : SSet α) : SSet α := t.elems.foldl excl s

/-- `s.filter p`.  Same story as `excl`: `HashSet.filterImpl` canonicalises, inlining every
sub-node that drops to a single element, so the survivors come back in CHAMP order. -/
def filter (s : SSet α) (p : α → Bool) : SSet α :=
  if s.hashed then ⟨true, champ (s.elems.filter p)⟩ else ⟨false, s.elems.filter p⟩

/-- `s & t`, which is `s.filter(t)`. -/
def inter (s t : SSet α) : SSet α := s.filter (fun x => t.contains x)

/-- `s.map f`.  The builder starts in the receiver's representation, so a `HashSet` maps to a
`HashSet` however small the image. -/
def map [SVal β] (s : SSet α) (f : α → β) : SSet β :=
  s.elems.foldl (fun acc x => acc.incl (f x)) ⟨s.hashed, []⟩

/-- `xs.toSet` / `Set(xs*)`: the generic builder, so a `SetN` up to four. -/
def ofList (xs : List α) : SSet α := xs.foldl incl empty

def subsetOf (s t : SSet α) : Bool := s.elems.all (fun x => t.contains x)

/-- Scala's `Set` equality: same elements, whatever the order or representation. -/
def eqv (s t : SSet α) : Bool := s.size == t.size && s.subsetOf t

/-- `Set.hashCode`: `MurmurHash3.setHash`, which is order-independent. -/
def hsh (s : SSet α) : I32 := Murmur.setHash (s.elems.map SVal.hsh)

/-- The `Single.unapply` pattern of `Constraints`. -/
def single? (s : SSet α) : Option α :=
  match s.elems with
  | [x] => some x
  | _ => none

def foldl {γ : Type} (s : SSet α) (f : γ → α → γ) (z : γ) : γ := s.elems.foldl f z

end SSet

/-! ## Element instances -/

/-- A row variable, identified by its `V.id` -- which is also its `hashCode`
(`V.hashCode = id.hashCode`, `Vars.scala:109`). -/
instance svalNat : SVal Nat where
  eq a b := a == b
  hsh a := UInt32.ofNat a

instance svalString : SVal String where
  eq a b := a == b
  hsh := javaStringHash

end Rowpartition.Loop
