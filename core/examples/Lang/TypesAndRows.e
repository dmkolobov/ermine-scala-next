module Lang.TypesAndRows where

{- THE LANGUAGE ITSELF: `data` with kinds, `forall` and `exists` in signatures,
   `private`, fixity declarations, every pattern form, the row syntax, `field`
   declarations, the `Constraint` vocabulary, and the three `Type.*` modules.

   Fact: assetRel (12 fields: assetTag, assetName, assetClass, operatingSite,
         baseCurrency, fairValueUsd, bookValueUsd, acquiredYear, disposalYear,
         accountingCode, siteRegion, valuationBasis)

   WHY THIS FILE EXISTS. The language guide in `core/examples/guide/` is two files and
   fifty-eight lines: `HelloWorld.e` and `LetAndPatternMatching.e`. Between them they
   show comments, `import … hiding`, a signature, `let`, two pattern clauses, `field`,
   `relation` and `tabular`. Everything else about the language -- kinds, existentials,
   fixity, the row syntax, the `Type.*` modules -- has no example at all. This is the
   missing chapter, and every claim in it is checked by the fact that the file loads.

   THE KIND SYSTEM. Ermine has four kinds a user meets:

       *          ordinary types            Int, String, Report f z
       rho        ROWS                      the `r` in `{..r}` and `[..r]`
       * -> *     type constructors         List, Maybe, Relation is rho -> *
       constraint what appears before `=>`  r <- (a, b), Primitive a

   A `data` declaration may annotate its parameters: `data Tagged (s : rho) = …` is how
   you write a type that is indexed by a ROW rather than by a type. `Relation.Row.Row`
   is declared exactly that way (`data Row (r:rho) = Row (List (String, PrimT))`), and
   so is `Lang.Helpers.RowReader`.

   THE ROW VOCABULARY, in one place:

       {..r}          a record over the row r          (a value)
       [..r]          a relation over the row r        = Relation (|..r|)
       (| a, b |)     a literal row                    (a type)
       {a, b}         a `Row` value, or a record       (which, depends on position)
       r <- (a, b)    r is the disjoint union of a and b
       Has r a        exists c. r <- (a, c)            -- `Constraint.e`
       r | s          exists c. c <- (r, s)            -- r and s are disjoint
       RUnion2 t r s  t is the union of r and s, which may OVERLAP

   `Has` and `|` and `RUnion2` are type SYNONYMS in `Constraint.e`, and the interface
   printer expands them, which is why `Lang/Signatures.e` can prove the sugar and the
   expansion equivalent.

   SHAPES EXERCISED
     * `data` with `(s : rho)` and with `(f : * -> *)`; an existential `data`; a
       phantom row parameter.
     * `forall`, `exists`, `Has`, `|`, `RUnion2` written out in signatures.
     * every pattern form Ermine has: literal, constructor, nested, tuple, wildcard,
       as-pattern `x@p`, lazy `~(a, b)`, strict `!x`, and the empty `case x of {}`.
     * `Type.Eq` (`Refl`, `subst`, `symm`, `trans`), `Type.Cast` (`<:`, `upcast`,
       `downcast`, `trans`), `Type.Remember` (`unify`, `asTypeOf`).
     * `Void` and `absurd`.
     * RANK-2: a `forall` in an argument position cannot be applied, and the `data`-field
       form that can -- the fact that explains the shape of every `Control.*` dictionary
       (section 9).
     * `Control.Category` at `(->)`, and `catEndoMonoid` folding a pipeline (section 10).
     * the row operators `#`, `-#`, `!*`, `projectT`, `exceptT`, `spanT`, `except`,
       `project`, `Row.append`, `Row.minus`, `Row.intersection`.
     * `field` declarations, `cons`, `(!)`, `(\)`, `modify`, `update`, `getF`,
       `withFieldCopy`, `existentialF`.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/TypesAndRows.e
   >> shownValues
   >> keySplit
   >> narrowed
   >> widened
   >> roundTripped
   >> patternTour
   >> rowsAndRows
   >> rank2Works        -- ([7], []) : the rank-2 field applied
   >> revaluedTwice     -- three same-type transformations folded through a Category
-}

import Prelude
import Syntax.List
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import Relation.Row as R
import Type.Eq as TE
import Type.Cast as TC
import Type.Remember as TR
import Control.Category as Cat
import Control.Monoid as Mo
import List as L
import String as S
import Lang.Helpers

field assetTag       : String
field assetName      : String
field assetClass     : String
field operatingSite  : String
field baseCurrency   : String
field fairValueUsd   : Double
field bookValueUsd   : Double
field acquiredYear   : Int
field disposalYear   : Int
field accountingCode : String
field siteRegion     : String
field valuationBasis : String

-- ---------------------------------------------------------------------------
-- 1. Fixity declarations.
--
-- `infixl`, `infixr` and `infix` take a precedence 0-9 and one or more operator names.
-- There is a separate namespace for TYPE operators, declared `infix type`. Both are
-- used below. There are NO operator sections: `(2 +)` is `ill-formed expression` and
-- `(+ 2)` is `unknown operator +`; the bare `(+)` is the only sectioned form, and a
-- lambda is how you write the rest.

infixl 7 <+>
infixr 3 ==>>
infix  4 =~=

-- | A left-associative combiner: `a <+> b <+> c` is `(a <+> b) <+> c`.
(<+>) : Double -> Double -> Double
(<+>) a b = a + b

-- | Right-associative: `a ==>> b ==>> c` is `a ==>> (b ==>> c)`.
(==>>) : Bool -> Bool -> Bool
(==>>) a b = if a b True

-- | Non-associative, so `a =~= b =~= c` is a parse error.
(=~=) : Double -> Double -> Bool
(=~=) a b = (if (a > b) (a - b) (b - a)) < 0.005

fixityWorks : (Double, Bool, Bool)
fixityWorks = (1.0 <+> 2.0 <+> 3.0, True ==>> False ==>> True, 1.0 =~= 1.001)

-- ---------------------------------------------------------------------------
-- 2. `data` with kinds.
--
-- A parameter may be annotated with its kind. `rho` is the kind of ROWS, and a data
-- type indexed by one is how the stdlib carries a header around at the type level.

-- | A row-indexed tag: the row `s` appears in the TYPE and, through `Row s`, in the
--   value. This is `Relation.Row.Row`'s own shape with a label bolted on.
data Tagged (s : rho) = Tagged String (Row_R s)

tagOf : forall s. Tagged s -> String
tagOf (Tagged t _) = t

rowOf : forall s. Tagged s -> Row_R s
rowOf (Tagged _ r) = r

identityTag : Tagged (|assetTag, assetName|)
identityTag = Tagged "identity" {assetTag, assetName}

valuationTag : Tagged (|fairValueUsd, bookValueUsd, valuationBasis|)
valuationTag = Tagged "valuation" {fairValueUsd, bookValueUsd, valuationBasis}

-- | A PHANTOM row: `p` appears in the type and nowhere in the value. Useful for
--   marking a `String` as "the name of a column in p".
data Named (p : rho) = Named String
nameText : forall p. Named p -> String
nameText (Named s) = s

-- | A type constructor parameter, kind `* -> *`.
data Boxed (f : * -> *) a = Boxed (f a)
unbox : forall f a. Boxed f a -> f a
unbox (Boxed fa) = fa

boxedList : Boxed List Int
boxedList = Boxed ([3, 1, 4]_L)

-- ---------------------------------------------------------------------------
-- 3. Existentials.
--
-- `data D = forall a. C …` hides `a`. The stdlib uses this for `Field.EField`,
-- `Data.Nu` and every `PivotColumn`; the hidden variable can NEVER be projected out --
-- `seedOf (Unfold f x) = x` is `error: skolem variables escape` -- so the constructor
-- must package everything the consumer needs.

data Shown = forall a. Shown (a -> String) a

shownOf : Shown -> String
shownOf (Shown f a) = f a

shownValues : List String
shownValues = map shownOf [ Shown toString (42 : Int)
                          , Shown id "a string"
                          , Shown toString 3.25
                          , Shown (b -> if b "yes" "no") True ]_L

-- | `exists` also appears in SIGNATURES, and there it is how `Has` is really spelled.
--   These two signatures are the same constraint; `Lang/Signatures.e` proves it.
firstFieldSugar : forall r h a. Has r h => Field h a -> {..r} -> a
firstFieldSugar f t = t ! f

firstFieldExpanded : forall r h a. (exists c. r <- (h, c)) => Field h a -> {..r} -> a
firstFieldExpanded f t = t ! f

-- ---------------------------------------------------------------------------
-- 4. `private`.
--
-- A `private` block hides its bindings from IMPORTERS. Everything from `private` to
-- the end of the indented block is hidden; `Maybe.e` uses it after every dictionary to
-- hide the worker. A module that imports this one and mentions `scaleBy` gets
-- `undefined term`.
--
-- They DO still appear in `Lang/TypesAndRows.ei`, and so do `Helpers.e`'s `punit`,
-- `pbind`, `por` and `mconcat` in `Lang/Helpers.ei`. An `.ei` is a compilation CACHE,
-- not a published API: an interface-cached load still refuses a private name at the
-- import. Do not read an `.ei` as the module's surface.

private
  scaleBy : Double -> Double -> Double
  scaleBy k x = k * x

  data Hidden = Hidden Double

publicScale : Double -> Double
publicScale = scaleBy 1.05

-- ---------------------------------------------------------------------------
-- 5. Every pattern form.

-- (The pattern functions are top level rather than in a `where` block because a
--  suffixed bracket literal cannot be followed by `where` -- the same parse limit that
--  stops `const []_L "x"`.)

litOf : Int -> String
litOf 0 = "literal zero"                      -- literal pattern
litOf _ = "literal other"                     -- catch-all

conOf : Maybe Int -> String
conOf Nothing  = "con Nothing"                -- constructor patterns
conOf (Just n) = "con Just " ++_S toString n

nestedOf : Maybe (Either String Int) -> String
nestedOf (Just (Left s))  = "nested Left " ++_S s      -- nested constructors
nestedOf (Just (Right n)) = "nested Right " ++_S toString n
nestedOf Nothing          = "nested Nothing"

-- | An AS-pattern: name the whole and match the parts at once.
asOf : List Int -> String
asOf whole@(x :: _) = "as " ++_S toString (length_L whole) ++_S " head " ++_S toString x
asOf _              = "as empty"

tupleOf : (Int, String) -> String
tupleOf (n, s) = "tuple " ++_S s ++_S "/" ++_S toString n

-- | A LAZY pattern: the components are matched only when demanded, so the match itself
--   never fails and never forces. `Pair.mapFst` and `Control.Monoid.mproduct` are
--   written this way, and they must be: `mproduct` builds a pair from two thunks.
lazyOf : (Int, String) -> String
lazyOf ~(n, s) = "lazy " ++_S s

-- | A STRICT pattern: forces the argument before the body runs. `Function.($!)` and
--   `Function.seq` are the two places the stdlib uses one.
strictOf : Int -> String
strictOf !n = "strict " ++_S toString n

wildOf : Int -> String
wildOf _ = "wildcard"

patternTour : List String
patternTour = [
    litOf 0, litOf 7,
    conOf Nothing, conOf (Just 3),
    nestedOf (Just (Left "x")), nestedOf (Just (Right 9)), nestedOf Nothing,
    asOf ([1, 2, 3]_L), asOf Nil,
    tupleOf (1, "one"),
    lazyOf (2, "two"),
    strictOf 5,
    wildOf 99
  ]_L

-- | The EMPTY case, which is how `Void.absurd` is written: a type with no constructors
--   has no patterns, so the expression can have any type at all.
neverHappens : Void -> String
neverHappens v = case v of {}

-- ---------------------------------------------------------------------------
-- 6. The facts, and the row vocabulary applied to them.

assetRows : List {assetTag, assetName, assetClass, operatingSite, baseCurrency,
                  fairValueUsd, bookValueUsd, acquiredYear, disposalYear,
                  accountingCode, siteRegion, valuationBasis}
assetRows = [
  { assetTag = "AST-001", assetName = "Harbour Point warehouse", assetClass = "Property",
    operatingSite = "Baltimore Yard", baseCurrency = "USD", fairValueUsd = 18400000.0,
    bookValueUsd = 15900000.0, acquiredYear = 2004, disposalYear = 0,
    accountingCode = "PP-100", siteRegion = "AMER", valuationBasis = "FAIR" },
  { assetTag = "AST-002", assetName = "Fleet, long haul", assetClass = "Equipment",
    operatingSite = "Baltimore Yard", baseCurrency = "USD", fairValueUsd = 3250000.0,
    bookValueUsd = 4100000.0, acquiredYear = 2008, disposalYear = 0,
    accountingCode = "EQ-220", siteRegion = "AMER", valuationBasis = "COST" },
  { assetTag = "AST-003", assetName = "Rotterdam terminal lease", assetClass = "Property",
    operatingSite = "Rotterdam Yard", baseCurrency = "EUR", fairValueUsd = 9750000.0,
    bookValueUsd = 9750000.0, acquiredYear = 2011, disposalYear = 0,
    accountingCode = "PP-140", siteRegion = "EMEA", valuationBasis = "FAIR" },
  { assetTag = "AST-004", assetName = "Legacy plant, Osaka", assetClass = "Equipment",
    operatingSite = "Kobe Works", baseCurrency = "JPY", fairValueUsd = 1180000.0,
    bookValueUsd = 2450000.0, acquiredYear = 1998, disposalYear = 2011,
    accountingCode = "EQ-090", siteRegion = "APAC", valuationBasis = "IMPAIRED" },
  { assetTag = "AST-005", assetName = "Software licences", assetClass = "Intangible",
    operatingSite = "Baltimore Yard", baseCurrency = "USD", fairValueUsd = 640000.0,
    bookValueUsd = 640000.0, acquiredYear = 2010, disposalYear = 0,
    accountingCode = "IN-310", siteRegion = "AMER", valuationBasis = "COST" }
  ]_L

assetRel : Relation (|assetTag, assetName, assetClass, operatingSite, baseCurrency,
                      fairValueUsd, bookValueUsd, acquiredYear, disposalYear,
                      accountingCode, siteRegion, valuationBasis|)
assetRel = relation assetRows

-- | `#` is `project` flipped, `-#` is `except` flipped, and `!*` is `projectT` flipped
--   -- the record-level projection. All three are in `Relation.Row`.
identityPart : Relation (|assetTag, assetName|)
identityPart = assetRel # {assetTag, assetName}

withoutValuation : Relation (|assetTag, assetName, assetClass, operatingSite,
                              baseCurrency, acquiredYear, disposalYear, accountingCode,
                              siteRegion|)
withoutValuation = assetRel -# {fairValueUsd, bookValueUsd, valuationBasis}

-- | `spanT` splits ONE record in two along a row -- the value-level `<-`.
keySplit : ({assetTag, assetName},
            {assetClass, operatingSite, baseCurrency, fairValueUsd, bookValueUsd,
             acquiredYear, disposalYear, accountingCode, siteRegion, valuationBasis})
keySplit = spanT_R {assetTag, assetName} (orElse emptyAsset (at_L 0 assetRows))
  where emptyAsset = { assetTag = "", assetName = "", assetClass = "", operatingSite = "",
                       baseCurrency = "", fairValueUsd = 0.0, bookValueUsd = 0.0,
                       acquiredYear = 0, disposalYear = 0, accountingCode = "",
                       siteRegion = "", valuationBasis = "" }

-- | `Row` values compose: `append` is the type-level `<-` at the value level, `minus`
--   is its inverse, `intersection` is the overlap `RUnion2` talks about.
identityRow : Row (|assetTag, assetName|)
identityRow = {assetTag, assetName}

valuationRow : Row (|fairValueUsd, bookValueUsd, valuationBasis|)
valuationRow = {fairValueUsd, bookValueUsd, valuationBasis}

bothRows : Row (|assetTag, assetName, fairValueUsd, bookValueUsd, valuationBasis|)
bothRows = append_R identityRow valuationRow

rowsAndRows : List String
rowsAndRows = [ toString (rowOf identityTag), toString (rowOf valuationTag),
                toString bothRows, toString (minus_R bothRows identityRow) ]_L

-- | `cons`, `(!)`, `(\)`, `modify` and `update` on a record, and `Field.getF`, which
--   is `(!)` with the arguments the other way round so it composes.
field assetAgeYears  : Int

agedRows : List {assetTag, assetName, assetClass, operatingSite, baseCurrency,
                 fairValueUsd, bookValueUsd, acquiredYear, disposalYear,
                 accountingCode, siteRegion, valuationBasis, assetAgeYears}
agedRows = map (t -> cons assetAgeYears (2011 - (t ! acquiredYear)) t) assetRows

revaluedRows : List {assetTag, assetName, assetClass, operatingSite, baseCurrency,
                     fairValueUsd, bookValueUsd, acquiredYear, disposalYear,
                     accountingCode, siteRegion, valuationBasis}
revaluedRows = map (modify fairValueUsd (v -> v * 1.03)) assetRows

droppedBasis : List {assetTag, assetName, assetClass, operatingSite, baseCurrency,
                     fairValueUsd, bookValueUsd, acquiredYear, disposalYear,
                     accountingCode, siteRegion}
droppedBasis = map (t -> t \ valuationBasis) assetRows

tagsByGetF : List String
tagsByGetF = map (getF assetTag) assetRows

-- | `withFieldCopy` makes a FRESH field of the same type under a rank-2 continuation:
--   the copy's row is existentially bound, which is how the stdlib renames a column
--   without a name collision. `existentialF` is the raw form.
--   NOTE the copy's NAME is a fresh GUID (`Field.uniqExistentialF` calls
--   `GUID.guid`), so `copiedName` differs on every run; `copiedIsFresh` is the
--   deterministic thing to check.
copiedName : String
copiedName = withFieldCopy fairValueUsd (f -> fieldName f)

copiedIsFresh : Bool
copiedIsFresh = copiedName != "fairValueUsd" && length_S copiedName == 36

copiedType : String
copiedType = withFieldCopy fairValueUsd (f -> toString (fieldType f))

-- ---------------------------------------------------------------------------
-- 7. `Type.Eq`, `Type.Cast`, `Type.Remember`.

-- | `a == b` is a builtin GADT with one constructor `Refl`. `subst : a == b -> p a ->
--   p b` is the only elimination -- `Type/Eq.e`'s own comment says pattern matching on
--   `Refl` "fails because we don't do GADT type refinement", so `trans` is `subst`.
sameType : Int ==_TE Int
sameType = refl_TE

flipped : Int ==_TE Int
flipped = symm_TE sameType

-- | `subst` used for what it is for: moving a value across a proved equality.
private data Wrap a = Wrap a
private unwrap : forall a. Wrap a -> a
unwrap (Wrap a) = a

coerceEq : forall a b. a ==_TE b -> a -> b
coerceEq e x = unwrap (subst_TE e (Wrap x))

roundTripped : Int
roundTripped = coerceEq sameType 1729

-- | `Type.Cast`'s `a <: b` is a RUNTIME coercion pair, not a proof: an injection and a
--   partial inverse. Ermine has no subtyping, so this is how you build one.
intInDouble : Int <:_TC Double
intInDouble = Cast_TC toDouble (d -> if (d =~= toDouble (toInt d)) (Just (toInt d)) Nothing)

widened : Double
widened = upcast_TC intInDouble 42

narrowed : (Maybe Int, Maybe Int)
narrowed = (downcast_TC intInDouble 42.0, downcast_TC intInDouble 42.5)

-- | `trans` composes two casts.
intInString : Int <:_TC String
intInString = trans_TC (Cast_TC toString (_ -> Nothing)) refl_TC

-- | `Type.Remember`: `unify a b` returns `b` after forcing both to one type, and
--   `asTypeOf a b` returns `a`. They are how you pin an inferred type at a use site
--   without writing a signature -- which matters because two of this group's inferred
--   types cannot be written down at all (`Lang/Signatures.e`).
pinnedEmpty : List Double
pinnedEmpty = unify_TR ([1.0]_L) Nil

pinnedByWitness : Double
pinnedByWitness = sameShapeAs (foldRows sumMonoid (t -> t ! fairValueUsd) assetRows) 0.0

-- ---------------------------------------------------------------------------
-- 9. RANK-2: a `forall` in an argument position, and why every dictionary is a `data`.
--
-- A rank-2 SIGNATURE is accepted. A rank-2 ARGUMENT cannot be applied. This does not
-- compile, and the error is not about the caller:
--
--     oneWay : forall f m. (forall x. f x -> m x) -> f Int -> m Int
--     oneWay nat a = nat a
--     -- error: failed to unify type (forall x. f x -> m x) with type (a -> b)
--
-- The signature parses and elaborates; the TERM language cannot use the argument,
-- because applying it wants a `a -> b` and the polymorphic type never instantiates to
-- one in that position. Put the same `forall` in a DATA FIELD and everything works --
-- which is what `Helpers.Nat` is, and it is the only working form:
--
--     data Nat f m = Nat (forall x. f x -> m x)
--     apply (Nat k) a = k a          -- fine
--
-- THAT ONE FACT EXPLAINS THE SHAPE OF THE WHOLE `Control.*` HIERARCHY. Every dictionary
-- in the stdlib keeps its polymorphism in a field rather than taking it as an argument:
--
--     data Monad f       = Monad (forall a. a -> f a) (forall a b. f a -> (a -> f b) -> f b)
--     data Traversable t = Traversable (forall f a b. Ap f -> (a -> f b) -> t a -> f (t b))
--     data Comonad f     = Comonad (Extract f) (Extend f)
--     data F f a         = F (forall r. (a -> r) -> (f r -> r) -> r)
--     data Nu f          = forall s. Unfold (s -> f s) s
--
-- and it is why `Data/Free.e` has no `foldFree` (its natural type takes a natural
-- transformation as an argument) while `Data/Free/Church.e`'s `runF` needs no functor
-- at all -- `F`'s rank-2 is already inside a `data`. `Helpers.foldFree` is the missing
-- eliminator written the way the language permits.
--
-- (Found by E5's reviewer, L-11. The failing form is not shipped as a `shouldfail`
-- module because `lang06`/`lang07` already cover the two type-level refutation classes;
-- what earns its place here is the CONSEQUENCE, which a reader meets in every `Control`
-- signature.)

-- | The rank-2 field, applied. The whole of `Control.*` is this shape.
data Applier f m = Applier (forall x. f x -> m x)

applyNat : forall f m x. Applier f m -> f x -> m x
applyNat (Applier k) fx = k fx

-- (`maybeToList` is taken -- `Maybe.e` exports one, and a `field`/term may not shadow
--  a stdlib global.)
maybeAsList : forall x. Maybe x -> List x
maybeAsList Nothing  = Nil
maybeAsList (Just x) = x :: Nil

rank2Works : (List Int, List Int)
rank2Works = (applyNat (Applier maybeAsList) (Just 7),
              applyNat (Applier maybeAsList) Nothing)

-- ---------------------------------------------------------------------------
-- 10. `Control.Category`: the third shape a dictionary takes.
--
-- `Category k` is `data Category k = Category (forall a. k a a) (forall a b c. k b c ->
-- k a b -> k a c)` -- rank-2 fields again -- and `Function.fCategory` is its only
-- instance in the stdlib, at `(->)`. What it buys is that `id` and `(.)` become VALUES
-- you can abstract over, and `catEndoMonoid` turns any category's endomorphisms into a
-- monoid, which is how a pipeline of same-type transformations gets folded.

pipeline : Monoid_Mo (Double -> Double)
pipeline = catEndoMonoid_Cat fCategory

applyAll : Double -> Double
applyAll = foldMapL pipeline id ([ (v -> v * 1.03), (v -> v - 1000.0), publicScale ]_L)

revaluedTwice : Double
revaluedTwice = applyAll 1000000.0

categoryIdIsId : Bool
categoryIdIsId = idC_Cat fCategory 42 == 42

-- ---------------------------------------------------------------------------
-- 11. The report.

impaired : Relation (|assetTag, assetName, assetClass, operatingSite, baseCurrency,
                      fairValueUsd, bookValueUsd, acquiredYear, disposalYear,
                      accountingCode, siteRegion, valuationBasis|)
impaired = assetRel |> filter_Pred (col_Op fairValueUsd <_Pred col_Op bookValueUsd)

byClass : Mem (|assetClass, fairValueUsd|)
byClass = assetRel |> groupBy {assetClass} (sumBy fairValueUsd)

typesReport : Report f z
typesReport = vflow [
    text "## Fixed assets, 2011",
    tabular Nothing (assetRel # {assetTag, assetName, assetClass, fairValueUsd,
                                 bookValueUsd, valuationBasis}),
    text "### Carried above fair value",
    tabular Nothing (impaired # {assetTag, assetName, fairValueUsd, bookValueUsd}),
    text "### Fair value by class",
    tabular Nothing byClass,
    text "### With a derived age column (added at the value level)",
    tabular Nothing (relation agedRows # {assetTag, acquiredYear, assetAgeYears})
  ]_L
