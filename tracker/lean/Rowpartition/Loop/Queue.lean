/-
# `Constraints.Q`: the priority-search queue and the type-variable graph

`Constraints.scala` lines 403-640.  The queue is a `scalaz.FingerTree` measured by
`PSQK = (Option[(Int, (Int, Int))], Int)`, whose monoid takes the MINIMUM of the first
component's priority and the RIGHTMOST element's `(rhs.hashCode, lhs.hashCode)`.  Two facts
turn that into a list:

* every `insert` splits on the last-element key, so the tree is a SEARCH TREE ordered by
  `(rhs.hashCode, lhs.hashCode)` ascending, and `heapify`, `filter`, `partition` and `pop`
  all preserve that order;
* `pop` splits on "the prefix's minimum priority equals the whole tree's minimum", which
  selects the FIRST element, in that order, whose `graph.sort(lhs)` is minimal.

Since `sort` is a bijection `nodes → 0..n-1`, the minimum picks a UNIQUE variable, and the
`(rhs.hashCode, lhs.hashCode)` order only breaks ties among that variable's own partitions.
Stated as the model's dequeue rule:

> **Dequeue order.**  Let `v` be the variable of minimal reverse-topological index among the
> left-hand sides present in the queue (children before parents, so `v` is the deepest).
> Dequeue the partition with `lhs = v` whose `rhs.hashCode` is smallest as a SIGNED Java
> `int`; among equal `rhs.hashCode` the most recently inserted wins, because `insert` places
> a new element at the FRONT of its `(rhs.hashCode, lhs.hashCode)` block.

`rhs.hashCode` is real: see `Rowpartition.Loop.Hash`.  `graph.sort` is real: it is the
position in `StreamTUtils.reverseTopSort`, whose result depends on the ITERATION ORDER of
the node set and of each edge set, which is why `SSet` exists.
-/
import Rowpartition.Loop.State

namespace Rowpartition.Loop

/-! ## 1. Association lists standing for Scala `Map`s

Only `get` and `+` are used on `TypeVarGraph.edges` and `.sort`, so the iteration order of
these maps never reaches the output and a list of pairs is faithful. -/

/-- `m.get(k)`. -/
def alGet {α : Type} (m : List (Nat × α)) (k : Nat) : Option α :=
  (m.find? (fun p => p.1 == k)).map (·.2)

/-- `m + (k -> v)`. -/
def alPut {α : Type} (m : List (Nat × α)) (k : Nat) (v : α) : List (Nat × α) :=
  if m.any (fun p => p.1 == k) then m.map (fun p => if p.1 == k then (k, v) else p)
  else m ++ [(k, v)]

/-- `s.zip(Stream.from(0)).toMap`. -/
def withIndex {α : Type} (xs : List α) : List (α × Nat) :=
  let rec go (ys : List α) (i : Nat) : List (α × Nat) :=
    match ys with
    | [] => []
    | y :: t => (y, i) :: go t (i + 1)
  go xs 0

/-! ## 2. `Q.TypeVarGraph` -/

/-- `Q.TypeVarGraph(nodes, edges, sort)` with its invariant: `sort` is a valid reverse
topological order of `nodes` under `edges`. -/
structure Graph where
  nodes : SSet Nat
  edges : List (Nat × SSet Nat)
  sort : List (Nat × Nat)

namespace Graph

def empty : Graph := ⟨SSet.empty, [], []⟩

def prioOf? (g : Graph) (v : Nat) : Option Nat := alGet g.sort v

/-- The priority `pr(graph)` gives a partition.  A variable outside `sort` makes the Scala
throw `NoSuchElementException`; it cannot happen, because every partition in a queue was put
there by `insert`, which extends the graph first. -/
def prio (g : Graph) (v : Nat) : Nat := (g.prioOf? v).getD 0

/-- `StreamTUtils.reverseTopSort`'s inner loop, as the recursion its explicit stack encodes:
mark on entry, recurse into unvisited children in order, emit on exit.  `fuel` bounds the
DEPTH, which is at most the number of nodes. -/
def dfs (children : Nat → List Nat) : Nat → Nat → List Nat × List Nat → List Nat × List Nat
  | 0, _, st => st
  | f + 1, v, (visited, out) =>
    if visited.contains v then (visited, out)
    else
      let st := ((v :: visited), out)
      let st := (children v).foldl (fun st c => dfs children f c st) st
      (st.1, st.2 ++ [v])

/-- `StreamTUtils.reverseTopSort(vertices)(children)`: children before parents. -/
def reverseTopSort (vertices : List Nat) (children : Nat → List Nat) : List Nat :=
  (vertices.foldl (fun st v => dfs children (vertices.length + 1) v st) ([], [])).2

/-- `TypeVarGraph.+ : (TypeVar, Set[TypeVar]) => (TypeVarGraph, Boolean)`.  The boolean says
whether the sort had to be recomputed; `heapify` then re-measures the tree, which does not
change its ORDER, so the model ignores it. -/
def add (g : Graph) (u : Nat) (vs : SSet Nat) : Graph × Bool :=
  let newNodes := (g.nodes.concat vs).incl u
  let newEdges :=
    match alGet g.edges u with
    | none => alPut g.edges u vs
    | some s => alPut g.edges u (s.concat vs)
  let ok :=
    match g.prioOf? u with
    | none => false
    | some su => vs.elems.all (fun v => match g.prioOf? v with
        | none => false
        | some sv => decide (sv < su))
  if ok then (⟨newNodes, newEdges, g.sort⟩, false)
  else
    let edgeFun := fun v => match alGet newEdges v with | some s => s.elems | none => []
    (⟨newNodes, newEdges, withIndex (reverseTopSort newNodes.elems edgeFun)⟩, true)

/-- `TypeVarGraph.+ : Partition => ...`. -/
def addPart (g : Graph) (p : LPart) : Graph × Bool := g.add p.lhs p.rhs.abstr

end Graph

/-! ## 3. The queue -/

/-- `Q.PQueue`: the elements in the finger tree's own order, and the graph the reducer reads.
`dequeue`, `filter` and `partition` all keep the graph they were given. -/
structure PQueue where
  elems : List LPart
  graph : Graph

namespace PQueue

/-- The search key: `(rhs.hashCode, lhs.hashCode)`, compared as SIGNED Java `int`s, which is
what `scalaz.Order[Int]` does. -/
def keyOf (p : LPart) : Int × Int :=
  (I32.toSigned p.rhs.hshOf, (p.lhs : Int))

def keyLt (a b : Int × Int) : Bool := a.1 < b.1 || (a.1 == b.1 && a.2 < b.2)

def keyEq (a b : Int × Int) : Bool := a.1 == b.1 && a.2 == b.2

def empty : PQueue := ⟨[], Graph.empty⟩

def size (q : PQueue) : Nat := q.elems.length

def isEmpty (q : PQueue) : Bool := q.elems.isEmpty

def toList (q : PQueue) : List LPart := q.elems

/-- `PQueue.contains`: the `(rhs.hashCode, lhs.hashCode)` block, then `==`.  Equal partitions
have equal keys, so scanning the whole list gives the same answer. -/
def contains (q : PQueue) (p : LPart) : Bool := q.elems.any (fun x => x.eqv p)

/-- Place `p` at the FRONT of its key block: `left <++> (p +: right)`. -/
def insertSorted (p : LPart) : List LPart → List LPart
  | [] => [p]
  | x :: xs => if keyLt (keyOf x) (keyOf p) then x :: insertSorted p xs else p :: x :: xs

/-- `Q.rhsLookup(rhs, req, exe = true)`: the first partition of the same-`rhs.hashCode` block
whose right-hand side is EQUAL, skipping empty right-hand sides and lone-variable ones.
Because the queue is ordered by `rhs.hashCode`, "first in the block" is "first in the
queue". -/
def rhsLookup (q : PQueue) (r : RHS) : Option Nat :=
  if r.isEmpty then none
  else if (r.single?).isSome then none
  else (q.elems.find? (fun x => x.rhs.eqv r)).map (·.lhs)

/-- `PQueue.findRHS`: the same scan without the two exclusions. -/
def findRHS (q : PQueue) (r : RHS) : Option Nat :=
  (q.elems.find? (fun x => x.rhs.eqv r)).map (·.lhs)

/-- `Q.insert(p, q, graph, process = false)`, i.e. `PQueue.+`. -/
def insertNP (q : PQueue) (p : LPart) : PQueue :=
  if p.isSelfUnification then q
  else if q.elems.any (fun x => keyEq (keyOf x) (keyOf p) && x.eqv p) then q
  else ⟨insertSorted p q.elems, (q.graph.addPart p).1⟩

/-- `Q.insert(p, q, graph, process = true)`, i.e. `PQueue.+!`: a right-hand side already
present in the queue makes this a COMMON PARTITION unification instead of an insertion, and
the graph is NOT extended with `p`. -/
def insertP (q : PQueue) (p : LPart) : PQueue :=
  if p.isSelfUnification then q
  else if q.elems.any (fun x => keyEq (keyOf x) (keyOf p) && x.eqv p) then q
  else
    match q.rhsLookup p.rhs with
    | some v => q.insertNP ⟨v, RHS.ofAbstr (SSet.ofList [p.lhs]), some .commonPartition⟩
    | none => ⟨insertSorted p q.elems, (q.graph.addPart p).1⟩

/-- `PQueue.++`. -/
def concatNP (q : PQueue) (ps : List LPart) : PQueue := ps.foldl insertNP q

/-- `PQueue.++!`. -/
def concatP (q : PQueue) (ps : List LPart) : PQueue := ps.foldl insertP q

/-- `Q.pop`: the first element, in queue order, of minimal priority. -/
def dequeue (q : PQueue) : Option (LPart × PQueue) :=
  match q.elems with
  | [] => none
  | e0 :: rest =>
    let prios := (e0 :: rest).map (fun p => q.graph.prio p.lhs)
    let m := prios.foldl Nat.min (q.graph.prio e0.lhs)
    match (e0 :: rest).findIdx? (fun p => q.graph.prio p.lhs == m) with
    | none => none
    | some i =>
      match (e0 :: rest)[i]? with
      | none => none
      | some p => some (p, ⟨(e0 :: rest).eraseIdx i, q.graph⟩)

/-- `PQueue.filter`, which keeps the graph and the order. -/
def filter (q : PQueue) (pred : LPart → Bool) : PQueue :=
  ⟨q.elems.filter pred, q.graph⟩

/-- `PQueue.partition`.  Scala folds from the RIGHT, so the returned `Set` receives the
matching partitions in REVERSE queue order -- which is their insertion order, and therefore
(at four elements or fewer) their iteration order. -/
def partition (q : PQueue) (pred : LPart → Bool) : SSet LPart × PQueue :=
  (SSet.ofList ((q.elems.filter pred).reverse), ⟨q.elems.filter (fun p => !pred p), q.graph⟩)

/-- `PQueue(ps)` = `empty ++ ps`. -/
def ofList (ps : List LPart) : PQueue := empty.concatNP ps

end PQueue

/-- `Constraints.trim`. -/
def trim (ps : SSet LPart) (cs : PQueue) : SSet LPart :=
  ps.filter (fun p => !cs.contains p)

/-- `Constraints.findRHS(ps, cs, s)`: `cs` first, then `ps`, then the current batch. -/
def findRHS3 (ps cs : PQueue) (s : SSet LPart) (r : RHS) : Option Nat :=
  match cs.findRHS r with
  | some v => some v
  | none =>
    match ps.findRHS r with
    | some v => some v
    | none => (s.elems.find? (fun p => p.rhs.eqv r)).map (·.lhs)

end Rowpartition.Loop
