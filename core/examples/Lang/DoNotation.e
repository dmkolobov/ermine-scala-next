module Lang.DoNotation where

{- `do` NOTATION IN A LANGUAGE WITH NO CLASSES: the same computation written five ways,
   in five monads, with `Syntax.Do`, `Syntax.Monad`, `Syntax.Maybe`, `Syntax.Either`,
   `Syntax.List` and raw `Control.Monad` dictionaries side by side.

   Fact: shipments (10 fields: shipRef, shipOrigin, shipDest, carrierName,
         despatchDate, arrivalDate, weightKg, volumeM3, freightUsd, shipStatus)

   WHY THIS FILE EXISTS. Ermine has `do`, and `do` is the one piece of syntax whose
   meaning is a library function. `Lower.scala` desugars every `do` to
   `Syntax.Do.bind`, ALWAYS -- not to the `bind` of whatever monad is in scope -- and
   `Syntax.Do.bind` is

       private type MonadK f a = Monad f -> f a
       unit  = flip unit_M
       bind fa f m = bind_M m (fa m) (flip f m)
       liftDo = const

   So a `do` block does not have type `m a`. It has type `Monad m -> m a`: it is a
   READER of the dictionary, and you apply the dictionary to get the value. Two
   consequences that cost every newcomer a compile:

     1. An ordinary monadic value cannot appear in a `do` block. `Just 3` has type
        `Maybe Int`, not `Monad Maybe -> Maybe Int`. `liftDo` (which is `const`) is
        what puts it in.
     2. The block must be APPLIED. `(do …) ' maybeMonad` -- and `'` is `infixl 0`, so
        it binds looser than everything inside, which is why that spelling works.

   The `Syntax.X` modules are the alternative: each fixes ONE monad and can therefore
   afford operators. `Syntax.Maybe`, `Syntax.Either`, `Syntax.List`, `Syntax.IO` and
   `Syntax.Reader` all export `>>=`, `>>`, `<<`, `<*>`, `<$`, `<$>`; `Syntax.Maybe` and
   `Syntax.Either` add `(|)`, a left-biased choice. Because they are separate modules
   the operators must be qualified -- `>>=_Mb` versus `>>=_Eth` -- which is Ermine's
   substitute for `instance`.

   AND `Syntax.Monad` IS A THIRD THING: the operators lifted over `MonadK`, so
   `>>=_SM`, `<$>_SM`, `lift2_SM` … work in ANY monad and produce a value that still
   wants the dictionary. It also has `sequenceList`, `traverseList` and `for_`.

   SHAPES EXERCISED
     * one `do` block instantiated at `Maybe`, `Either String`, `List`, `State Int` and
       `Parser` -- five monads, one piece of syntax.
     * `Control.Ap`'s `liftA2`…`liftA6` and `tupleA2`; `Control.Monad`'s `join`, `ifM`;
       `Control.Functor`'s `strength` and `mapply`.
     * `Control.Alt` at `Maybe`: `empty`, `alt`, `firstOf`, `orElseA`, `withDefaultA`.
     * `Control.Monad.Id` as a sixth monad for the same `do` block, and
       `Control.Monad.Error`'s `ErrorT` over both `Id` and `Maybe`.
     * `Helpers.allOrNothing`, `cellOr`, `minMonoid` and `inMonad` -- the four helpers
       with no other call site in the group.
     * `traverseRows` and `checkedRel` from `Helpers.e` over a 10-column relation, in
       `Maybe` and in the accumulating `Either` -- a row variable under three different
       applicatives in one file.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/DoNotation.e
   >> maybeSum, eitherSum, listSum, statefulSum, parsedSum, identitySum
   >> dividedOk, dividedBad, dividedOverMaybe
   >> allCarrierCodes, everyBadCode, weightOrZero, weightRange
   >> pairsOfLegs
   >> heaviestOf shipmentRows
   >> checkedShipments
   >> spoiltShipments
   >> doNotationReport
-}

import Prelude
import Syntax.List
import Syntax.Maybe as Mb
import Syntax.Either as Eth
import Syntax.Monad as SM
import Control.Monad as M
import Control.Alt as Alt
import Control.Monoid as Mo
import Control.Monad.State as St
import Control.Monad.Id as Id
import Control.Monad.Error as Err
import Control.Functor as Fn
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import List as L
import String as S
import Date as D
import Maybe as MbD
import Either as ED
import Lang.Helpers

field shipRef      : String
field shipOrigin   : String
field shipDest     : String
field carrierName  : String
field despatchDate : Date
field arrivalDate  : Date
field weightKg     : Double
field volumeM3     : Double
field freightUsd   : Double
field shipStatus   : String

-- ---------------------------------------------------------------------------
-- 1. ONE `do` block, five monads.
--
-- `addTwo` is generic: it takes a dictionary and two actions and adds their results.
-- Every use below is the same three lines at a different type.

addTwo : forall m. Monad_M m -> m Int -> m Int -> m Int
addTwo m ma mb = (do a <- liftDo ma
                     b <- liftDo mb
                     unit (a + b)) ' m

maybeSum : Maybe Int
maybeSum = addTwo maybeMonad (Just 40) (Just 2)

maybeMiss : Maybe Int
maybeMiss = addTwo maybeMonad (Just 40) Nothing

eitherSum : Either String Int
eitherSum = addTwo eitherMonad (Right 40) (Right 2)

eitherFail : Either String Int
eitherFail = addTwo eitherMonad (Right 40) (Left "no second operand")

-- | In the LIST monad `addTwo` is a cartesian product: every a with every b.
listSum : List Int
listSum = addTwo listMonad ([10, 20]_L) ([1, 2, 3]_L)

-- | In `State Int` the two actions both consume the state, so the answer depends on
--   the ORDER -- which is the whole difference between a monad and an applicative.
tick : State_St Int Int
tick = State_St (s -> (s, s + 1))

statefulSum : (Int, Int)
statefulSum = runState_St (addTwo stateMonad_St tick tick) 100

-- | And in the parser from `Helpers.e`, `addTwo` reads two integers.
parsedSum : Maybe Int
parsedSum = parseAll (addTwo parserMonad (pToken pInt) pInt) "17 25"

-- | A SIXTH: `Control.Monad.Id`, the monad that does nothing. `Id` is what a transformer
--   stack sits on when the base has no effect, and it is the cheapest way to see that
--   `addTwo`'s genericity is in the dictionary and nowhere else.
identitySum : Int
identitySum = runIdentity_Id (addTwo idMonad_Id (Id_Id 40) (Id_Id 2))

-- | `Helpers.inMonad` is the same application written as a name rather than as `'`:
--   `inMonad m block` is `block m`. Worth having when the block is long enough that the
--   trailing `' dict` gets lost.
identitySumNamed : Int
identitySumNamed = runIdentity_Id (inMonad idMonad_Id (do a <- liftDo (Id_Id 40)
                                                          b <- liftDo (Id_Id 2)
                                                          unit (a + b)))

-- ---------------------------------------------------------------------------
-- 1b. `Control.Monad.Error`: the transformer `RunningState.e` did not need.
--
-- `ErrorT e m a` wraps `m (Either e a)`, and `errorTMonad : Monad m -> Monad (ErrorT e m)`
-- builds its dictionary from the base's. Over `Id` it is `Either` with a name; over
-- `Maybe` it is two failure modes at once, and telling them apart is the point: `Nothing`
-- is "the base gave up", `Just (Left e)` is "the computation reported why".

checkedDivide : Monad_M m -> Double -> Double -> ErrorT_Err String m Double
checkedDivide m a b = if (b == 0.0) (fail_Err m "divide by zero") (success_Err m (a / b))

dividedOk : Id_Id (Either String Double)
dividedOk = runErrorT_Err (checkedDivide idMonad_Id 84.0 2.0)

dividedBad : Id_Id (Either String Double)
dividedBad = runErrorT_Err (checkedDivide idMonad_Id 84.0 0.0)

-- | The same over `Maybe`, where BOTH failure modes exist. `Nothing` never appears here
--   because nothing in the chain fails in the base; that is what makes the two
--   distinguishable rather than redundant.
dividedOverMaybe : (Maybe (Either String Double), Maybe (Either String Double))
dividedOverMaybe = (runErrorT_Err (checkedDivide maybeMonad 84.0 2.0),
                    runErrorT_Err (checkedDivide maybeMonad 84.0 0.0))

-- ---------------------------------------------------------------------------
-- 2. The same thing with `Syntax.Monad`'s operators, which are `MonadK`-lifted and so
--    still generic, and with each `Syntax.X` module's own fixed-monad operators.

addTwoOps : forall m. Monad_M m -> m Int -> m Int -> m Int
addTwoOps m ma mb = lift2_SM (+) (liftDo ma) (liftDo mb) m

addTwoMaybe : Maybe Int -> Maybe Int -> Maybe Int
addTwoMaybe ma mb = ma >>=_Mb (a -> mb >>=_Mb (b -> return_Mb (a + b)))

addTwoEither : Either String Int -> Either String Int -> Either String Int
addTwoEither ma mb = (+) <$>_Eth ma <*>_Eth mb

-- | All four agree.
fourWaysAgree : Bool
fourWaysAgree =
  let a = orElse 0 (addTwo maybeMonad (Just 40) (Just 2))
      b = orElse 0 (addTwoOps maybeMonad (Just 40) (Just 2))
      c = orElse 0 (addTwoMaybe (Just 40) (Just 2))
      d = either (_ -> 0) id (addTwoEither (Right 40) (Right 2))
  in a == b && b == c && c == d

-- ---------------------------------------------------------------------------
-- 3. `Syntax.Monad`'s list functions, and the list monad as a comprehension.

legs : List String
legs = ["Rotterdam", "Singapore", "Santos"]_L

-- | Every ordered pair of distinct legs: the list monad's `do` is a comprehension.
pairsOfLegs : List (String, String)
pairsOfLegs = (do a <- liftDo legs
                  b <- liftDo legs
                  liftDo (if (a == b) Nil ((a, b) :: Nil))) ' listMonad

-- | `sequenceList` in `Maybe`: all present, or nothing.
allPresent : Maybe (List Int)
allPresent = sequenceList_SM ([liftDo (Just 1), liftDo (Just 2), liftDo (Just 3)]_L) maybeMonad

onePresent : Maybe (List Int)
onePresent = sequenceList_SM ([liftDo (Just 1), liftDo Nothing, liftDo (Just 3)]_L) maybeMonad

-- | `traverseList` is `sequenceList . map`, and here it parses a whole column.
parsedColumn : Maybe (List Int)
parsedColumn = traverseList_SM (s -> liftDo (parseIntTotal s))
                               (["11", "22", "33"]_L) maybeMonad

spoiltColumn : Maybe (List Int)
spoiltColumn = traverseList_SM (s -> liftDo (parseIntTotal s))
                               (["11", "2x", "33"]_L) maybeMonad

-- ---------------------------------------------------------------------------
-- 4. Applicative and functor odds and ends that have no example anywhere.

-- | `liftA2` … `liftA6`: `Control.Ap` provides six, and the sixth needs six actions.
sixWide : Maybe (List String)
sixWide = liftA6_M maybeAp (a b c d e f -> [a,b,c,d,e,f]_L)
                   (Just "a") (Just "b") (Just "c") (Just "d") (Just "e") (Just "f")

pairedUp : Maybe (Int, String)
pairedUp = tupleA2_M maybeAp (Just 7) (Just "seven")

-- | `strength` moves a pure value inside a functor; `mapply` applies a wrapped
--   function to a bare argument. Both are one-liners in `Control.Functor` and both
--   are used constantly once you notice them.
strengthened : Maybe (String, Int)
strengthened = strength_Fn maybeFunctor ("units", Just 12)

applied : Maybe Int
applied = mapply_Fn maybeFunctor (Just (n -> n * 3)) 14

-- | `join` and `ifM`. `ifM` is NOT `liftA3 if`: it runs only the branch it needs, which
--   for `State` or `IO` is the difference between right and wrong.
flattened : Maybe Int
flattened = join_M maybeMonad (Just (Just 5))

chosen : (Int, Int)
chosen = runState_St (ifM_M stateMonad_St (State_St (s -> (s < 5, s)))
                             tick (unit_M stateMonad_St 0)) 9

-- | `Control.Alt` at `Maybe`: a zero, a choice, and `firstOf` over a table.
firstCarrier : Maybe String
firstCarrier = firstOf maybeAlt ([Nothing, Nothing, Just "Maersk", Just "MSC"]_L)

noCarrier : Maybe String
noCarrier = firstOf maybeAlt ([Nothing, Nothing]_L)

-- | The other two `Alt` helpers. `orElseA` is `alt` under a name that reads at a call
--   site; `withDefaultA` turns a failure into a value, which is the one thing `Alt`
--   alone cannot do -- it needs the `Ap` inside the dictionary to make the default.
preferredCarrier : Maybe String
preferredCarrier = orElseA maybeAlt Nothing (Just "Hapag")

carrierOrHouse : Maybe String
carrierOrHouse = withDefaultA maybeAlt "house account" noCarrier

-- | `allOrNothing` is `traverse` at the ACCUMULATING applicative: every failure, or every
--   success. Compare `parsedColumn` above, which stops at the first.
allCarrierCodes : Either String (List Int)
allCarrierCodes = allOrNothing (a b -> a ++_S "; " ++_S b)
                               ([Right 1, Right 2, Right 3]_L)

everyBadCode : Either String (List Int)
everyBadCode = allOrNothing (a b -> a ++_S "; " ++_S b)
                            ([Left "bad ref", Right 2, Left "bad weight"]_L)

-- | `cellOr` makes a cell reader that cannot fail, by supplying a default. Used here on
--   the shipment column that is allowed to be blank.
weightOrZero : List (Maybe Double)
weightOrZero = map (cellOr 0.0 cellDouble) (["18400.0", "", "not a number"]_L)

-- | `minMonoid` beside `maxMonoid`: a measure bracketed from both sides in ONE pass over
--   the rows, which is what `Control.Monoid.mproduct` is for.
weightRange : (Double, Double)
weightRange = foldRows (mproduct_Mo minMonoid maxMonoid) (t -> (t ! weightKg, t ! weightKg))
                       (filter_L (t -> (t ! weightKg) > 0.0) shipmentRows)

-- ---------------------------------------------------------------------------
-- 5. The facts, and the row traversals over them.

shipmentRows : List {shipRef, shipOrigin, shipDest, carrierName, despatchDate,
                     arrivalDate, weightKg, volumeM3, freightUsd, shipStatus}
shipmentRows = [
  { shipRef = "SHP-9001", shipOrigin = "Rotterdam", shipDest = "Santos",
    carrierName = "Maersk", despatchDate = yyyymmdd_D 2011 5 2,
    arrivalDate = yyyymmdd_D 2011 5 24, weightKg = 18400.0, volumeM3 = 62.5,
    freightUsd = 21400.0, shipStatus = "DELIVERED" },
  { shipRef = "SHP-9002", shipOrigin = "Singapore", shipDest = "Rotterdam",
    carrierName = "MSC", despatchDate = yyyymmdd_D 2011 5 6,
    arrivalDate = yyyymmdd_D 2011 6 1, weightKg = 27250.0, volumeM3 = 88.0,
    freightUsd = 31875.0, shipStatus = "DELIVERED" },
  { shipRef = "SHP-9003", shipOrigin = "Santos", shipDest = "Singapore",
    carrierName = "Hapag", despatchDate = yyyymmdd_D 2011 5 11,
    arrivalDate = yyyymmdd_D 2011 6 9, weightKg = 9100.0, volumeM3 = 41.2,
    freightUsd = 14200.0, shipStatus = "IN TRANSIT" },
  { shipRef = "SHP-9004", shipOrigin = "Rotterdam", shipDest = "Singapore",
    carrierName = "Maersk", despatchDate = yyyymmdd_D 2011 5 17,
    arrivalDate = yyyymmdd_D 2011 6 14, weightKg = 33800.0, volumeM3 = 104.7,
    freightUsd = 39600.0, shipStatus = "IN TRANSIT" },
  { shipRef = "SHP-9005", shipOrigin = "Singapore", shipDest = "Santos",
    carrierName = "Hapag", despatchDate = yyyymmdd_D 2011 5 23,
    arrivalDate = yyyymmdd_D 2011 6 22, weightKg = 0.0, volumeM3 = 55.9,
    freightUsd = 26100.0, shipStatus = "IN TRANSIT" }
  ]_L

shipments : Relation (|shipRef, shipOrigin, shipDest, carrierName, despatchDate,
                       arrivalDate, weightKg, volumeM3, freightUsd, shipStatus|)
shipments = relation shipmentRows

-- | `traverseRows` in `Maybe`: the whole traversal fails if ANY row has no weight.
--   The row variable travels under `Maybe`; nothing here mentions a column but
--   `weightKg`.
densities : Maybe (List Double)
densities = traverseRows maybeAp (t -> if ((t ! weightKg) <= 0.0) Nothing
                                          (Just ((t ! weightKg) / (t ! volumeM3))))
                         shipmentRows

-- | The same over the four rows that do have a weight.
goodDensities : Maybe (List Double)
goodDensities = traverseRows maybeAp (t -> if ((t ! weightKg) <= 0.0) Nothing
                                              (Just ((t ! weightKg) / (t ! volumeM3))))
                             (filter_L (t -> (t ! weightKg) > 0.0) shipmentRows)

-- | `checkedRel` in the ACCUMULATING `Either`: every bad row, then the relation.
shipmentChecks : {shipRef, shipOrigin, shipDest, carrierName, despatchDate,
                  arrivalDate, weightKg, volumeM3, freightUsd, shipStatus} -> List Err
shipmentChecks t =
  (if ((t ! weightKg) <= 0.0) (("weightKg", (t ! shipRef) ++_S ": zero weight") :: Nil) Nil)
  ++_L
  (if ((t ! freightUsd) <= 0.0) (("freightUsd", (t ! shipRef) ++_S ": zero freight") :: Nil) Nil)

checkedShipments : Either (List Err) (Relation (|shipRef, shipOrigin, shipDest,
                                                 carrierName, despatchDate, arrivalDate,
                                                 weightKg, volumeM3, freightUsd,
                                                 shipStatus|))
checkedShipments = checkedRel shipmentChecks (filter_L (t -> (t ! weightKg) > 0.0)
                                                       shipmentRows)

spoiltShipments : Either (List Err) (Relation (|shipRef, shipOrigin, shipDest,
                                                carrierName, despatchDate, arrivalDate,
                                                weightKg, volumeM3, freightUsd,
                                                shipStatus|))
spoiltShipments = checkedRel shipmentChecks shipmentRows

-- | `foldRows` with `Ord`-free monoids from `Helpers.e`.
heaviestOf : List {shipRef, shipOrigin, shipDest, carrierName, despatchDate,
                   arrivalDate, weightKg, volumeM3, freightUsd, shipStatus} -> Double
heaviestOf = foldRows maxMonoid (t -> t ! weightKg)

-- ---------------------------------------------------------------------------
-- 6. The report.

inTransit : Relation (|shipRef, shipOrigin, shipDest, carrierName, despatchDate,
                       arrivalDate, weightKg, volumeM3, freightUsd, shipStatus|)
inTransit = shipments |> filter_Pred (col_Op shipStatus ==_Pred prim_Op "IN TRANSIT")

byCarrier : Mem (|carrierName, freightUsd|)
byCarrier = shipments |> groupBy {carrierName} (sumBy freightUsd)

doNotationReport : Report f z
doNotationReport = vflow [
    text "## Shipments, May 2011",
    tabular Nothing (shipments # {shipRef, shipOrigin, shipDest, carrierName,
                                  weightKg, freightUsd, shipStatus}),
    text "### In transit",
    tabular Nothing (inTransit # {shipRef, carrierName, arrivalDate}),
    text "### Freight by carrier",
    tabular Nothing byCarrier,
    text ("### Legs, as a list-monad comprehension: "
          ++_S toString (length_L pairsOfLegs) ++_S " ordered pairs")
  ]_L
