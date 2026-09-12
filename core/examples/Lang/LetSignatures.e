module Lang.LetSignatures where

{- SIGNATURES ON LOCAL BINDINGS: `let`, `where`, and each nested inside the other.

   Fact: runlogRows (3 cols: runlogStation, runlogQty, runlogNote)

   WHY THIS FILE EXISTS.  Between 2026-08-31 and 2026-09-11 the renamer's lowering of a
   `let` block DISCARDED every signature in it (`rename/Lower.scala`'s `SLet` case built
   `Let(pos, implicits, Nil, body)` and its block helper never constructed an explicit
   binding at all), so a `let`-bound signature reached neither the type checker nor the
   editor: `let g : Int -> Int; g x = x in g "hello"` LOADED and evaluated to `"hello"`.
   A `where` on a TOP-LEVEL equation was unaffected -- it goes through the module path --
   but a `where` nested INSIDE a `let` block was dropped as well.  Nothing in the corpus
   noticed, because until this file NO module under `core/examples` had a signature on a
   `let`-bound binding, and the stdlib has exactly three (`Layout/Column/Unsafe.e` twice,
   `List/Util.e` once).  This module is the corpus's pin: it loads only if a local
   signature is both HONOURED and CHECKED.  See `tracker/loopmodel/LET-1-FIX.md`; the
   negatives are `core/examples/shouldfail/let01`..`let05` (error class 7).

   HOW EACH BINDING EARNS ITS PLACE.  Seven of the eleven local signatures below are ones
   INFERENCE WOULD NOT PRODUCE -- more specific than the inferred type, or carrying a
   constraint the body does not need; the other four (shapes 3, 5, 7 and `tag` in 9, each
   says so in its comment) coincide with inference and pin only that a signed let LOADS.  So the module cannot load by accident: a compiler that
   ignores local signatures infers something else and still loads, but then the USE in
   the body of each binding is what pins the declared type (a signature the compiler
   merely parsed and threw away leaves the more general inferred type, and every use
   below is written to be legal under that one too -- see the table).  Read the comment
   over each binding for the inferred type it replaces.

   >> :load core/examples/Lang/Helpers.e     -- the group library (not used here)
   >> :load core/examples/Lang/LetSignatures.e
   >> signedLocalsReport

   NAMES: no binding here contains the substring `let`, `case` or `where`, because
   `Console.other` treats a typed line containing one of them as UNFINISHED and a piped
   session would spin (`core/examples/Lang/README.md`, "The REPL trap, exactly").  That
   is why the summary value is `signedLocalsReport` and not `letSigReport`.
-}

import Prelude
import List as L
import String as S

field runlogStation : String
field runlogQty     : Int
field runlogNote    : String

runlogRows : List {runlogStation, runlogQty, runlogNote}
runlogRows =
  [ { runlogStation = "North", runlogQty = 40, runlogNote = "opening" },
    { runlogStation = "South", runlogQty = 25, runlogNote = "roll" },
    { runlogStation = "North", runlogQty = 15, runlogNote = "add" }
  ]_L

-- 1. A MONOMORPHIC signature on a `let` binding.
--    Inferred without it: `forall a. a -> a`.  The declaration pins it to `Int`, which
--    is why `sameInt` cannot be reused at another type -- see `shouldfail/let01`.
rowCount : Int
rowCount =
  let sameInt : Int -> Int
      sameInt q = q
  in sameInt (length runlogRows)

-- 2. A POLYMORPHIC signature on a `let` binding, INSTANTIATED AT TWO TYPES in the body.
--    Inferred without it: `forall a b. (a, b) -> a`.  The declaration makes both
--    components ONE type, and the binding is still polymorphic -- `Int` on the left of
--    the pair below, `String` on the right.
firstOfBoth : (Int, String)
firstOfBoth =
  let firstOf : forall a. (a, a) -> a
      firstOf (x, _) = x
  in (firstOf (7, 9), firstOf ("North", "South"))

-- 3. A signed `where` binding -- the shape that always worked, kept here as the control
--    beside the ones that did not.
--    Inferred without it: `forall a. a -> Int` is NOT what inference gives; `length_S`
--    forces `String`, so the declaration is the inferred type.  It earns its place as
--    the control, not as a narrowing.
noteWidth : Int
noteWidth = widthOf "opening"
  where widthOf : String -> Int
        widthOf s = length_S s

-- 4. A signed `where` attached to an equation INSIDE a `let` block -- the second drop
--    site, which no `where` test reached because `where` tests are written at the top
--    level.
--    Inferred without the inner signature: `forall n. Num n => n -> n -> n` for `add`.
--    The declaration pins it to `Int`, and `plus` is applied by `foldl` at `Int`.
qtyTotal : Int
qtyTotal =
  let plus : Int -> Int -> Int
      plus a b = add a b
        where add : Int -> Int -> Int
              add x y = x + y
  in foldl plus 0 (map_List (t -> t ! runlogQty) runlogRows)

-- 5. A signed `let` inside a `where` body.
--    Inferred without it: `String -> String` is what `++_S` gives, so this one is
--    pinned by the ROW of shapes rather than by narrowing -- it is here because the
--    nesting is a different code path (`Lower.term` reached from the module path's
--    `where`, not from another `let`).
stationLabel : String
stationLabel = label "North"
  where label d =
          let decorate : String -> String
              decorate s = "[" ++_S s ++_S "]"
          in decorate d

-- 6. A `let` signature carrying a ROW CONSTRAINT, applied at a record that satisfies it.
--    Inferred without it: `forall r. {..r} -> Int` -- the body ignores the record
--    entirely.  The declaration DEMANDS a `runlogQty` field, so the application below
--    has to discharge `(|runlogStation, runlogQty, runlogNote|) <- ((|runlogQty|), t)`,
--    which it does with `t = (|runlogStation, runlogNote|)`.  A compiler that dropped the
--    signature would never ask.
rowConstrained : Int
rowConstrained =
  let oneRow : forall r t. r <- ((|runlogQty|), t) => {..r} -> Int
      oneRow _ = 1
  in foldl (n t -> n + oneRow t) 0 runlogRows

-- 7. A `let` signature with an EXPLICIT KIND on its quantifier.  `rho` is the kind of
--    rows, and a local signature goes through the same `annotTy` production as a
--    top-level one, so it may write the kind.
--    Inferred without it: the same type, with the kind inferred rather than written --
--    this one pins the GRAMMAR, not the checking.
qtyOfFirst : Int
qtyOfFirst =
  let atRow : forall (r: rho). {..r} -> Int
      atRow _ = 0
  in atRow { runlogQty = 40 } + 40

-- 8. A `let` signature that MONOMORPHISES a row.
--    Inferred without it: `forall r t. r <- ((|runlogQty|), t) => {..r} -> Int`, the
--    row-polymorphic reader.  The declaration pins the argument to this run log's own
--    three-field record, so the binding is no longer applicable to any other row.
firstQty : Int
firstQty =
  let qtyOf : {runlogStation, runlogQty, runlogNote} -> Int
      qtyOf rec = rec ! runlogQty
  in qtyOf (head runlogRows)

-- 9. TWO ADJACENT signed bindings in ONE `let` block: the pairing is per binding, by
--    the binder the renamer shares between a signature and its equations, so two
--    signatures in one block must not cross.
--    Inferred without them: `forall n. Num n => n -> n` for `bump` (narrowed to `Int`)
--    and `Int -> String` for `tag` (the inferred type, kept adjacent to `bump`).
adjacentPair : (Int, String)
adjacentPair =
  let bump : Int -> Int
      bump n = n + 1
      tag : Int -> String
      tag n = "#" ++_S toString n
  in (bump 41, tag 41)

-- Everything above, in one value, so the module is checked by evaluating one name.
signedLocalsReport : (Int, (Int, String), Int, Int, String, Int, Int, Int, (Int, String))
signedLocalsReport = (rowCount, firstOfBoth, noteWidth, qtyTotal, stationLabel,
                rowConstrained, qtyOfFirst, firstQty, adjacentPair)
