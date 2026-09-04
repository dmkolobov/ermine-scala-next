/-
# The JVM hash functions the solver's queue order depends on

`Constraints.Q` is a finger tree keyed on `PSQK = (Option[(Int, (Int, Int))], Int)`, i.e. on
`(graph.sort(lhs), (rhs.hashCode, lhs.hashCode))`.  The two hash codes are Scala's, so the
DEQUEUE ORDER of the real solver is a function of `scala.util.hashing.MurmurHash3` and of the
iteration order of `scala.collection.immutable.Set`, which is a function of
`scala.collection.Hashing.improve`.  A model that wants to agree with the compiler step for
step has to compute them, not abstract them.

This module is those functions, transcribed from `scala-library-2.13.18-sources.jar`:

* `scala/util/hashing/MurmurHash3.scala` -- `mix`, `mixLast`, `finalizeHash`, `avalanche`,
  `productHash`, `unorderedHash`/`setHash`, `listHash` (including its arithmetic-range
  special case) and the seeds `productSeed = 0xcafebabe`, `seqSeed = "Seq".hashCode`,
  `setSeed = "Set".hashCode`;
* `scala/collection/Hashing.scala` -- `improve`, the bit mixer the CHAMP trie indexes on;
* `java.lang.String.hashCode`.

Everything is `UInt32` arithmetic, which is bit-for-bit Java `int` arithmetic for `+`, `*`,
`^`, `|`, `&`, `~`, `<<` and `>>>` (Java's LOGICAL right shift).  Signed comparison -- which
the queue's `Order[Int]` uses -- is `I32.toSigned` below.

All of this was checked against the JVM: see `tracker/loopmodel/L1-MODEL.md` for the probe
programme and the values it printed.
-/

namespace Rowpartition.Loop

/-- A Java `int`, as its two's-complement bit pattern. -/
abbrev I32 := UInt32

namespace I32

/-- The signed value of a Java `int`, for the comparisons the queue's `Order[Int]` makes. -/
def toSigned (x : I32) : Int :=
  if x.toNat < 2147483648 then (x.toNat : Int) else (x.toNat : Int) - 4294967296

/-- Java `<<` by a literal amount below 32. -/
def shl (x : I32) (n : Nat) : I32 := x <<< (UInt32.ofNat n)

/-- Java `>>>` (logical right shift) by a literal amount below 32. -/
def shr (x : I32) (n : Nat) : I32 := x >>> (UInt32.ofNat n)

/-- `java.lang.Integer.rotateLeft`. -/
def rotl (x : I32) (n : Nat) : I32 := shl x n ||| shr x (32 - n)

end I32

/-- `java.lang.String.hashCode`: `s[0]*31^(n-1) + ... + s[n-1]`. -/
def javaStringHash (s : String) : I32 :=
  s.toList.foldl (fun h c => 31 * h + UInt32.ofNat c.toNat) 0

/-! ## MurmurHash3 -/

namespace Murmur

/-- `MurmurHash3.mixLast`. -/
def mixLast (hash data : I32) : I32 :=
  let k := data * 0xcc9e2d51
  let k := I32.rotl k 15
  let k := k * 0x1b873593
  hash ^^^ k

/-- `MurmurHash3.mix`. -/
def mix (hash data : I32) : I32 :=
  let h := mixLast hash data
  let h := I32.rotl h 13
  h * 5 + 0xe6546b64

/-- `MurmurHash3.avalanche`. -/
def avalanche (hash : I32) : I32 :=
  let h := hash ^^^ I32.shr hash 16
  let h := h * 0x85ebca6b
  let h := h ^^^ I32.shr h 13
  let h := h * 0xc2b2ae35
  h ^^^ I32.shr h 16

/-- `MurmurHash3.finalizeHash`. -/
def finalizeHash (hash : I32) (length : Nat) : I32 :=
  avalanche (hash ^^^ UInt32.ofNat length)

/-- `MurmurHash3.productSeed`. -/
def productSeed : I32 := 0xcafebabe

/-- `MurmurHash3.seqSeed = "Seq".hashCode` (= 83007). -/
def seqSeed : I32 := javaStringHash "Seq"

/-- `MurmurHash3.setSeed = "Set".hashCode` (= 83010). -/
def setSeed : I32 := javaStringHash "Set"

/-- `MurmurHash3.rangeHash`. -/
def rangeHash (start step last seed : I32) : I32 :=
  avalanche (mix (mix (mix seed start) step) last)

/-- `MurmurHash3.unorderedHash`, on the element hashes in iteration order.  The result does
not depend on that order -- `a`, `b`, `c` are sum, xor and product -- which is why a `Set`'s
hash is stable even though its iteration order is not the insertion order. -/
def unorderedHash (hs : List I32) (seed : I32) : I32 :=
  let f := fun (acc : I32 × I32 × I32 × Nat) (h : I32) =>
    (acc.1 + h, acc.2.1 ^^^ h, acc.2.2.1 * (h ||| 1), acc.2.2.2 + 1)
  let (a, b, c, n) := hs.foldl f (0, 0, 1, 0)
  let x := mix seed a
  let x := mix x b
  let x := mixLast x c
  finalizeHash x n

/-- `MurmurHash3.setHash`: what `scala.collection.immutable.Set.hashCode` returns. -/
def setHash (hs : List I32) : I32 := unorderedHash hs setSeed

/-- The synthetic `hashCode` of a case class with a nonempty product: `productHash` with the
class name mixed in under `productSeed`.  (2.13.17 renamed this `caseClassHash`; the value is
the same, which the JVM probe confirms.) -/
def productHash (namePrefix : String) (elems : List I32) : I32 :=
  match elems with
  | [] => javaStringHash namePrefix
  | _ =>
    let h := mix productSeed (javaStringHash namePrefix)
    let h := elems.foldl mix h
    finalizeHash h elems.length

/-- The `rangeState` machine of `MurmurHash3.listHash`: `0` no data, `1` first element read,
`2` a valid common difference, `3` invalid. -/
structure ListAcc where
  h : I32
  state : Nat
  diff : I32
  prev : I32
  initial : I32
  n : Nat

/-- `MurmurHash3.listHash`, which `List.hashCode` calls with `seqSeed`.  The arithmetic-range
special case is REAL and reachable -- `List(1,2,3).hashCode` takes it -- so it is transcribed
rather than dropped. -/
def listHash (hs : List I32) (seed : I32) : I32 :=
  let step := fun (a : ListAcc) (hash : I32) =>
    let h := mix a.h hash
    let st :=
      match a.state with
      | 0 => { a with state := 1, initial := hash }
      | 1 => { a with state := 2, diff := hash - a.prev }
      | 2 => if a.diff ≠ hash - a.prev || a.diff = 0 then { a with state := 3 } else a
      | _ => a
    { st with h := h, prev := hash, n := a.n + 1 }
  let a := hs.foldl step { h := seed, state := 0, diff := 0, prev := 0, initial := 0, n := 0 }
  if a.state = 2 then rangeHash a.initial a.diff a.prev seed else finalizeHash a.h a.n

/-- `List.hashCode`. -/
def seqHash (hs : List I32) : I32 := listHash hs seqSeed

end Murmur

/-- `scala.collection.Hashing.improve`: the bit mixer a CHAMP trie indexes on, and therefore
the function that decides `immutable.HashSet`'s iteration order. -/
def improve (hcode : I32) : I32 :=
  let h := hcode + (~~~ (I32.shl hcode 9))
  let h := h ^^^ I32.shr h 14
  let h := h + I32.shl h 4
  h ^^^ I32.shr h 10

/-- The 5-bit trie index of a hash at a given depth.  The `% 32` is a no-op on the value --
`x &&& 31` is already below 32 -- and is there so `champMask_lt` is one `Nat.mod_lt`. -/
def champMask (h : I32) (shift : Nat) : Nat := (I32.shr h shift &&& 31).toNat % 32

theorem champMask_lt (h : I32) (shift : Nat) : champMask h shift < 32 :=
  Nat.mod_lt _ (by omega)

end Rowpartition.Loop
