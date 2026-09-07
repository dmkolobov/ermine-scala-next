module Lang.ForeignJdk where

{- `foreign`: every declaration form Ermine has for reaching the JVM, against real JDK
   classes, plus the two stdlib modules that are nothing but `foreign` (`GUID`,
   `Random`) and the bug that `foreign` results hide.

   Fact: deviceRel (10 fields: deviceRef, deviceName, vendorName, driftRate,
         deployedYear, ratedKw, driftValue, elapsedDays, gradeCode, siteCode)

   WHY THIS FILE EXISTS. `foreign` is the only construct in Ermine whose meaning is a
   Java signature, and the only examples of it are inside the stdlib -- where it is
   almost always `private`, so a reader never sees the whole shape. `Relation/Windowed.e`
   and `Relation/Pivot.e` were the brief's suggested models and both are one `function`
   declaration each. This file uses all six forms.

   THE SIX FORMS

     foreign
       data "java.math.BigDecimal" BigDec              -- a Java class as an Ermine type
       constructor bigDec : String -> BigDec           -- a `new`
       method "scale" scaleOf : BigDec -> Int          -- receiver is the FIRST argument
       function "java.lang.Math" "sqrt" sqrt : Double -> Double   -- a static method
       value "java.lang.Integer" "MAX_VALUE" maxInt : Int         -- a static field
       subtype BigDecIsObject : BigDec -> Object       -- a widening coercion

   plus `private foreign`, which is how the stdlib hides the raw handle and exports only
   the Ermine-shaped wrapper.

   THREE RULES THAT ARE NOT WRITTEN DOWN ANYWHERE ELSE

     1. A `method`'s receiver is its first argument. `method "charAt" strCharAt :
        String -> Int -> Char` is `s.charAt(i)`.
     2. The result type chooses the effect discipline. A plain type is pure; `IO a`
        makes it an action; `FFI a` makes it a value whose exception can be caught with
        `IO.Unsafe.unsafeFFI`. `File.e` uses `IO`, `Parse.e` uses `FFI`.
     3. OVERLOADS are chosen by the declared Ermine type, and an overload set the
        compiler cannot narrow is a load error. `java.lang.Math.abs` has four; declaring
        it at `Double -> Double` is what picks `abs(double)`.

   AND THE BUG. Rule 2 does not work. `Runtime.scala:51`'s `Prim.apply` catches any
   exception thrown while forcing a foreign result and returns a `Bottom` VALUE, so
   `IO.Unsafe.eval`'s `try/catch` never fires, `unsafeFFI` always returns `Right`, and
   `Parse.numberFormat`'s `NumberFormatException` branch is unreachable:

       >> parseInt 10 "1O2"
       res0 : Maybe Int = (Just <error: For input string: "1O2">)
       >> isJust (parseInt 10 "1O2")
       res1 : Bool = True

   `notCaught` below is the same thing declared from scratch in this module, so the
   reader can see it is the FFI mechanism and not `Parse`. `Helpers.parseIntTotal` is
   the workaround: check the string, then parse.

   SHAPES EXERCISED
     * all six `foreign` declaration forms, `private foreign`, and an overload narrowed
       by its declared type;
     * `IO`-returning and `FFI`-returning foreigns side by side;
     * `Random.randomInts : Long -> Stream Int` -- a seeded, referentially transparent
       stream built from `unsafePerformIO`, which the module's own header explains;
     * `GUID`'s three declarations, exercised on a FIXED uuid so the answer is stable;
     * a foreign function used as a relational `combine` over a 10-column row.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/ForeignJdk.e
   >> driftOf 4.25 98.5
   >> maxInt
   >> roundedValues
   >> scaledDecimals, decimalStrings
   >> notCaught          -- Just <error: …> : rule 2 does not hold
   >> caughtMissing      -- <error: …> : and `IO.catch` does not catch it either
   >> bothAbsOverloads   -- (42, 42.5) : one Java method, two Ermine names
   >> shouted, readLongUnsafe
   >> guardedRead        -- Nothing : what it should have been
   >> firstRandoms
   >> guidRoundTrip
   >> foreignReport
-}

import Prelude
import Syntax.List
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import List as L
import List.Stream as Inf
import String as S
import GUID as G
import Random as Rnd
import IO.Unsafe as IOU
import Native.Object as NO
import File as Fl
import Syntax.IO as SIO
import Lang.Helpers

field deviceRef    : String
field deviceName   : String
field vendorName   : String
field driftRate    : Double
field deployedYear : Int
field ratedKw      : Double
field driftValue   : Double
field elapsedDays  : Int
field gradeCode    : String
field siteCode     : String

field cleanValue   : Double
field driftPercent : Double

-- ---------------------------------------------------------------------------
-- 1. `function` and `value`: static methods and static fields.

foreign
  function "java.lang.Math" "sqrt"  sqrtOf  : Double -> Double
  function "java.lang.Math" "pow"   powOf   : Double -> Double -> Double
  function "java.lang.Math" "floor" floorOf : Double -> Double
  function "java.lang.Math" "abs"   absOf   : Double -> Double
  value "java.lang.Integer" "MAX_VALUE" maxInt : Int
  value "java.lang.Double"  "MAX_VALUE" maxDouble : Double
  value "java.lang.Math"    "PI"        piValue : Double

-- (`Math.e` already declares `sqrt`, `floor`, `ceil`, `pi` and `Double.MAX_VALUE` the
--  same way; they are redeclared here under different names so that this file shows the
--  declarations rather than importing them. Two Ermine names for one Java member is
--  fine -- `Math.e` itself binds `PI` twice, as `pi` and as `π`.)

-- | `abs` has four overloads in `java.lang.Math` (int, long, float, double). The declared
--   Ermine type is what picks one, and declaring it TWICE at two types in one module is
--   how you get both -- shown, not asserted: `absOf` above is `abs(double)` and `absI`
--   here is `abs(int)`, from the same two words of Java.
foreign
  function "java.lang.Math" "abs" absI : Int -> Int

bothAbsOverloads : (Int, Double)
bothAbsOverloads = (absI (0 - 42), absOf (0.0 - 42.5))

-- | The same thing written in Ermine, for the comparison.
absInt : Int -> Int
absInt n = if (n < 0) (0 - n) n

-- ---------------------------------------------------------------------------
-- 2. `data`, `constructor`, `method` and `subtype`: an object with state.

foreign
  data "java.math.BigDecimal" BigDec
  constructor bigDec : String -> BigDec
  method "scale"          scaleOf     : BigDec -> Int
  method "precision"      precisionOf : BigDec -> Int
  method "toPlainString"  plainOf     : BigDec -> String
  method "negate"         negateOf    : BigDec -> BigDec
  subtype BigDecIsObject : BigDec -> Object

-- | `subtype` is a coercion, not a cast: it says the Java type is a subtype of the
--   other, and lets a value be USED at the wider type. Here it lets `Native.Object`'s
--   `toString` see a `BigDec`.
decimalShown : String -> String
decimalShown s = toString_NO (BigDecIsObject (bigDec s))

scaledDecimals : List (Int, Int, String)
scaledDecimals = map (s -> let d = bigDec s in (scaleOf d, precisionOf d, plainOf (negateOf d)))
                     (["120.5", "0.00047", "98500", "1.750000"]_L)

-- | And the `subtype` coercion in use: `toString` from `Native.Object` applied to a
--   `BigDec`, which is only well-typed because `BigDecIsObject` says the Java class is
--   an `Object`. `"1.750000"` keeps its trailing zeros, which is the whole reason a
--   report reaches for `BigDecimal` at all.
decimalStrings : List String
decimalStrings = map decimalShown (["120.5", "0.00047", "98500", "1.750000"]_L)

-- ---------------------------------------------------------------------------
-- 3. `private foreign` and the FFI/IO distinction.
--
-- These two declare the SAME Java method at two result types. `readIntFFI` is what
-- `Parse.e` does; `readIntIO` is what `File.e` does. Neither is total (section 4).

private foreign
  function "java.lang.Integer" "parseInt" readIntFFI : String -> Int -> FFI Int
  function "java.lang.Long"    "parseLong" readLongIO : String -> Int -> IO Long
  method "toUpperCase" shout : String -> String

-- | `unsafeFFI : FFI a -> Either Throwable a`, then the `Right` branch. This is
--   `Parse.numberFormat` with the pattern match left out.
notCaught : Maybe Int
notCaught = case unsafeFFI_IOU (readIntFFI "1O2" 10) of
  Left _  -> Nothing
  Right n -> Just n

caughtProperly : Maybe Int
caughtProperly = case unsafeFFI_IOU (readIntFFI "102" 10) of
  Left _  -> Nothing
  Right n -> Just n

-- | The `IO`-returning sibling, used. `unsafePerformIO` is how a pure report reaches it;
--   note that it is exactly as unsafe as the `FFI` one -- section 4b.
readLongUnsafe : Long
readLongUnsafe = unsafePerformIO_IOU (readLongIO "9007199254740993" 10)

-- | And the plain `method` form: a receiver-first Java instance method.
shouted : String
shouted = shout "due for recalibration"

-- | A `value` declaration used for what it is for: a guard against a datum that cannot
--   be represented. `maxDouble` is `java.lang.Double.MAX_VALUE`.
representable : Double -> Bool
representable d = d < maxDouble && d > (0.0 - maxDouble)

-- | The workaround, from `Helpers.e`: check the string with `Character.isDigit` before
--   handing it to Java at all.
guardedRead : Maybe Int
guardedRead = parseIntTotal "1O2"

guardedReadOk : Maybe Int
guardedReadOk = parseIntTotal "102"

-- ---------------------------------------------------------------------------
-- 4b. AND `IO.catch` CANNOT CATCH IT EITHER.
--
-- Section 3 scopes the bug to `FFI` and `unsafeFFI`. It is not scoped to them.
-- `Session.scala:993`'s `perhapsForeign` routes the `IO` branch through the same `FF`
-- case, so an `IO` action built from a `foreign` declaration has its exception converted
-- to a `Bottom` VALUE before any handler exists -- and `IO.catch` is `IO`'s only handler:
--
--     >> caughtMissing
--     res : String = <error: /definitely/not/here.txt (No such file or directory)>
--
-- The handler does not run. **Every `IO` error path in the stdlib is unreachable for an
-- exception raised by the foreign call itself.** The distinction worth drawing is that a
-- PLAIN (non-`FFI`, non-`IO`) foreign only DEFERS: `strCharAt "" 0` reaches the REPL as
-- `runtime error: Index 0 out of bounds for length 0`, because the `Bottom` rethrows when
-- forced. So the conversion does not lose the exception; it converts a catchable one into
-- an uncatchable deferred one, and the damage is confined to code that tries to catch.
-- (Found by E5's reviewer, L-9.)

caughtMissing : String
caughtMissing = unsafePerformIO_IOU (catch (readFile_Fl "/definitely/not/here.txt")
                                           (e -> return_SIO "caught"))

deferredNotSwallowed : Char
deferredNotSwallowed = strCharAt "" 0

-- ---------------------------------------------------------------------------
-- 5. `Random`: referential transparency with a seed.
--
-- `Random.e`'s header is the best piece of prose in the stdlib: because Ermine demands
-- referential transparency, `getRandom` cannot mean anything, so the seed is in the
-- TYPE -- `randomInts : Long -> Stream Int` -- and the same seed gives the same stream
-- every time. Underneath it is `java.util.Random` and `unsafePerformIO`.

firstRandoms : List Int
firstRandoms = take_Inf 6 (randomInts_Rnd 20110404L)

sameSeedSameStream : Bool
sameSeedSameStream = firstRandoms == take_Inf 6 (randomInts_Rnd 20110404L)

-- | Integer remainder. `Num` has `+ - * /` and `abs`, and NO `mod`; `/` on `Int` is
--   integer division, so this is how a remainder is spelled.
modOf : Int -> Int -> Int
modOf a b = a - (a / b) * b

-- | A deterministic sample of the assets, drawn with a fixed seed.
sampledRefs : List String
sampledRefs = map (n -> orElse "?" (fmap maybeFunctor (t -> t ! deviceRef)
                                         (at_L (modOf (absInt n) 6) deviceRows)))
                  (take_Inf 4 (randomInts_Rnd 7L))

-- ---------------------------------------------------------------------------
-- 6. `GUID`: three declarations, and the only one that is deterministic.
--
--     function "java.util.UUID" "randomUUID" guid : IO GUID
--     method "toString" guidString : GUID -> String
--     function "java.util.UUID" "fromString" stringGuid : String -> GUID
--
-- `guid` is an `IO GUID` for the obvious reason. `stringGuid`/`guidString` are pure and
-- round-trip, which is what the example can check.

guidRoundTrip : Bool
guidRoundTrip = guidString_G (stringGuid_G fixedGuid) == fixedGuid

fixedGuid : String
fixedGuid = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"

-- | The round trip's actual output, so the recipe can show it rather than assert it.
guidShown : String
guidShown = guidString_G (stringGuid_G fixedGuid)

-- ---------------------------------------------------------------------------
-- 7. The facts, and a foreign function used relationally.

deviceRows : List {deviceRef, deviceName, vendorName, driftRate, deployedYear,
                   ratedKw, driftValue, elapsedDays, gradeCode, siteCode}
deviceRows = [
  { deviceRef = "SN0901", deviceName = "Aachen flow meter", vendorName = "Rheinmess AG",
    driftRate = 4.25, deployedYear = 2019, ratedKw = 250.0, driftValue = 101.85,
    elapsedDays = 47, gradeCode = "A", siteCode = "ZURI" },
  { deviceRef = "SN0902", deviceName = "Sarthe turbine probe", vendorName = "Sarthe Mesure",
    driftRate = 3.10, deployedYear = 2016, ratedKw = 180.0, driftValue = 98.42,
    elapsedDays = 112, gradeCode = "B", siteCode = "PARI" },
  { deviceRef = "SN0903", deviceName = "Kanto strain gauge", vendorName = "Kanto Instruments",
    driftRate = 1.85, deployedYear = 2014, ratedKw = 400.0, driftValue = 100.31,
    elapsedDays = 8, gradeCode = "A", siteCode = "TOKY" },
  { deviceRef = "SN0904", deviceName = "Pilbara ore scanner", vendorName = "Pilbara Metrics",
    driftRate = 6.75, deployedYear = 2021, ratedKw = 95.0, driftValue = 104.90,
    elapsedDays = 201, gradeCode = "C", siteCode = "PERT" },
  { deviceRef = "SN0905", deviceName = "Halcyon rack sensor", vendorName = "Halcyon Systems",
    driftRate = 5.00, deployedYear = 2018, ratedKw = 310.0, driftValue = 99.06,
    elapsedDays = 64, gradeCode = "A", siteCode = "ITHA" },
  { deviceRef = "SN0906", deviceName = "Thameside tide gauge", vendorName = "Thameside Marine",
    driftRate = 7.20, deployedYear = 2015, ratedKw = 60.0, driftValue = 96.15,
    elapsedDays = 155, gradeCode = "C", siteCode = "LOND" }
  ]_L

deviceRel : Relation (|deviceRef, deviceName, vendorName, driftRate, deployedYear,
                       ratedKw, driftValue, elapsedDays, gradeCode, siteCode|)
deviceRel = relation deviceRows

-- | Relative drift, computed with the foreign `Math` functions. Relational `combine`
--   works on `Op`s and cannot call an Ermine function, so a derived column that needs
--   the JVM is computed at the VALUE level and the relation rebuilt -- which is the
--   real reason `Lang/RunningState.e`'s `withRunning` exists.
driftOf : Double -> Double -> Double
driftOf rate value = floorOf ((rate / value) * 10000.0) / 100.0

cookedRows : List {deviceRef, deviceName, vendorName, driftRate, deployedYear, ratedKw,
                   driftValue, elapsedDays, gradeCode, siteCode, cleanValue,
                   driftPercent}
cookedRows = map (t -> cons cleanValue (cleanOf t)
                            (cons driftPercent (driftOf (t ! driftRate) (t ! driftValue)) t))
                 deviceRows
  where cleanOf t = (t ! driftValue)
                  - ((t ! driftRate) * toDouble (t ! elapsedDays) / 365.0)

cookedRel : Relation (|deviceRef, deviceName, vendorName, driftRate, deployedYear,
                       ratedKw, driftValue, elapsedDays, gradeCode, siteCode,
                       cleanValue, driftPercent|)
cookedRel = relation cookedRows

roundedValues : List (String, Double)
roundedValues = map (t -> (t ! deviceRef, floorOf ((t ! driftValue) * 100.0) / 100.0))
                    deviceRows

-- | `sqrt` and `pow` on a fleet-wide measure, so the foreigns are not decorative.
-- | `abs`, narrowed to `Double` by its declared type, measuring distance from the 100.0 reference.
offsetFromNom : List (String, Double)
offsetFromNom = map (t -> (t ! deviceRef, absOf ((t ! driftValue) - 100.0))) deviceRows

ratedRms : Double
ratedRms = sqrtOf (foldRows sumMonoid (t -> powOf (t ! ratedKw) 2.0) deviceRows
                   / toDouble (length_L deviceRows))

needsRecal : Relation (|deviceRef, deviceName, vendorName, driftRate, deployedYear,
                        ratedKw, driftValue, elapsedDays, gradeCode,
                        siteCode|)
needsRecal = deviceRel |> filter_Pred (col_Op gradeCode ==_Pred prim_Op "C")

bySite : Mem (|siteCode, ratedKw|)
bySite = deviceRel |> groupBy {siteCode} (sumBy ratedKw)

foreignReport : Report f z
foreignReport = vflow [
    text "## Asset telemetry",
    tabular Nothing (cookedRel # {deviceRef, deviceName, driftRate, driftValue,
                                  cleanValue, driftPercent}),
    text "### Due for recalibration",
    tabular Nothing (needsRecal # {deviceRef, vendorName, gradeCode}),
    text "### Rated kW by site",
    tabular Nothing bySite,
    text ("### RMS rated kW: " ++_S toString ratedRms)
  ]_L
