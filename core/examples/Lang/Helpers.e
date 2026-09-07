module Lang.Helpers where

{- GENERIC HELPERS ABOUT THE LANGUAGE, not about relations: applicative
   accumulation, traversals over a relation's rows, a row-polymorphic CSV reader, a
   parser-combinator library, State, Reader, Alt, Monoid folds, and text rendering.

   `core/examples/Lang` is the functional-programming half of Ermine. Everything else in
   `core/examples` is about RELATIONS; this directory is about the value-level language a
   report is written IN -- the half that has `Control.Functor`, `Control.Monad`,
   `Syntax.Do`, `Data.Free`, `Validation`, `Map`, `Tree` and `foreign`, and that had
   almost no example at all.

   ---------------------------------------------------------------------------
   THE ONE IDEA THAT MAKES THIS DIRECTORY WORTH READING

   Ermine has NO instance system. Every class in `Control.*` is a plain `data` value --
   a DICTIONARY -- that you pass by hand:

       data Monad f = Monad (forall a. a -> f a) (forall a b. f a -> (a -> f b) -> f b)

   So `bind` is `bind : Monad f -> f a -> (a -> f b) -> f b`, and a "polymorphic"
   function over monads is a function that takes the dictionary. `Syntax.Do` makes `do`
   notation work anyway by desugaring into a READER of the dictionary:

       private type MonadK f a = Monad f -> f a

   -- a `do` block has type `Monad f -> f a`, and you apply the dictionary at the end.
   That is why `twiceOver` below finishes with `... ) m`. Every `Syntax.X` module
   (`Syntax.Maybe`, `Syntax.Either`, `Syntax.List`, `Syntax.IO`, `Syntax.Reader`) is the
   same trick done once for a FIXED monad, which is why they can afford operator names
   (`>>=`, `<$>`, `<*>`) and `Syntax.Do` cannot.

   ---------------------------------------------------------------------------
   WHERE THE ROWS ARE

   `Lang/Helpers.ei` publishes 74 names: 70 public, plus the four `private` workers
   (`punit`, `pbind`, `por`, `mconcat`) that an `.ei` lists even though an importer
   cannot see them. SIXTEEN of the public ones quantify over a ROW, and FIVE of those
   carry an explicit row CONSTRAINT. Those five are the reason this directory is in the
   certification corpus: they put a row VARIABLE underneath a monadic or applicative
   type constructor, which no other example group does.

       consRow     : t <- (r, s) => ... -> RowReader s -> RowReader t
       pRecord     : t <- (r, s) => ... -> Parser {..s} -> Parser {..t}
       withRunning : t <- (r, c) => Field c n -> ... -> List {..r} -> List {..t}
       askField    : Has e h     => Field h a -> Reader {..e} a
       localField  : Has e h     => Field h a -> (a -> a) -> Reader {..e} b -> ...

   `RowReader t`, `Parser {..t}`: in each the solver has to keep a row partition alive
   across a type constructor it cannot see into. Read `t <- (r, s)` as "the row t is
   exactly the disjoint union of r and s"; `Has e h` is `exists c. e <- (h, c)`.

   The five ROW-QUANTIFIED helpers that carry NO constraint are just as much the point --
   `traverseRows`, `mapMRows`, `traverseRel`, `checkedRel`, `foldRows`, `showRows`,
   `withState`, `scanRows`, `runWith`, `readRowsAs`, `runRowReader` all move a row
   variable under `f`, `m`, `Either` or `List` with nothing left over for the caller.

   ---------------------------------------------------------------------------
   SEVEN THINGS THAT COST A COMPILE HERE, so you do not pay for them again

   1. `length` is `List.length`. `Prelude` exports `List` unqualified, so the STRING
      length -- a builtin registered as `String.length` -- must be written `length_S`
      after `import String as S`. `import Prelude hiding length` does not reveal it; it
      makes `length` undefined. (Same shape as `map`, which needs `Syntax.List`.)
   2. `++` is `List.(++)`. String concatenation is `++_S`.
   3. There are NO operator sections. `(2 +)` is `ill-formed expression` and `(+ 2)` is
      `unknown operator +`; only the bare `(+)` is a term. Write a lambda.
   4. A bracket or brace literal with a MODULE SUFFIX cannot be a non-final argument:
      `const []_L "x"` fails to parse. Parenthesise it -- `const ([]_L) "x"`.
   5. `||` is `Layout.Report`'s selector-event disjunction, not `Bool`'s. `Prelude`
      exports both and `Layout.Report` wins, so a boolean `or` must be `||_B` after
      `import Bool as B`. (`&&` is unaffected: `Layout.Report` does not define it.)
   6. `Parse.parseInt` and `Parse.parseDouble` are NOT total, and return
      `Just <bomb>` rather than `Nothing` on a bad string. Section 0b explains the
      mechanism and ships total replacements.
   7. `Parse` is NOT a parser-combinator library. It is six `java.lang.*` number
      parsers behind `Maybe`. The combinators below are what a reader expects to find
      there and does not; see `Lang/StatementParser.e`.
-}

import Prelude
import Syntax.List
import Control.Monad as M
import Control.Alt as Alt
import Control.Monoid as Mo
import Control.Traversable as T
import Control.Monad.State as St
import Control.Monad.Reader as Rd
import Type.Remember as Rem
import Validation as V
import Maybe as Mb
import Either as E
import List as L
import Bool as B
import String as S
import Relation.Row as R
import Data.Free as Fr

-- ---------------------------------------------------------------------------
-- 0. Foreign primitives the rest of the file needs.
--
-- `foreign` is how Ermine reaches the JVM, and it is the only construct in the
-- language whose meaning is a Java signature. Five forms exist: `data`, `constructor`,
-- `method`, `function` and `value`; `subtype` declares a coercion. A `method`
-- declaration's first argument is the receiver. See `Lang/ForeignJdk.e` for all of them.

foreign
  method "length"  strLength  : String -> Int
  method "isEmpty" strIsEmpty : String -> Bool
  method "charAt"  strCharAt  : String -> Int -> Char
  function "java.lang.Character" "isDigit" charIsDigit : Char -> Bool
  function "java.lang.Character" "isLetter" charIsLetter : Char -> Bool

type Err = Err_V                        -- (String, String): field name, message

-- ---------------------------------------------------------------------------
-- 0b. `Parse`, made total
--
-- `Parse.parseInt` and `Parse.parseDouble` are NOT total, and the way they fail is
-- worse than throwing:
--
--     >> parseInt 10 "1O2"
--     res0 : Maybe Int = (Just <error: For input string: "1O2">)
--     >> isJust (parseInt 10 "1O2")
--     res1 : Bool = True
--
-- `Just` wrapping a bomb. Any validator built on `Parse` therefore reports SUCCESS and
-- throws later, at the point of use, with no field name attached. The mechanism is
-- `Runtime.scala:51`'s `Prim.apply`, which catches an exception raised while forcing
-- and returns a `Bottom` VALUE; `IO.Unsafe.eval`'s own `try/catch` (`Lib.scala:1311`)
-- can therefore never see it, `unsafeFFI` always returns `Right`, and
-- `Parse.numberFormat`'s `Left e@(NumberFormatException _) -> Nothing` branch is dead
-- code. (`parseBool`, which is written in Ermine, is fine.)
--
-- The fix that works from Ermine is to check the STRING first. These two are what every
-- cell reader below actually calls.

-- | The characters of a string, as a list.
stringChars : String -> List Char
stringChars s = go 0
  where go i = if (i >= strLength s) Nil (strCharAt s i :: go (i + 1))

-- | Every character satisfies the predicate, and the string is not empty.
charsAll : (Char -> Bool) -> String -> Bool
charsAll ok s = not (strIsEmpty s) && every_L ok (stringChars s)

-- | An optional leading minus and then digits.
looksLikeInt : String -> Bool
looksLikeInt s = charsAll charIsDigit (if (take_S 1 s == "-") (drop_S 1 s) s)

-- | An optional leading minus, digits and at most one decimal point.
looksLikeNumber : String -> Bool
looksLikeNumber s =
  let body = if (take_S 1 s == "-") (drop_S 1 s) s
      dots = length_L (filter_L (c -> c == dotChar) (stringChars body))
  in charsAll (c -> charIsDigit c ||_B c == dotChar) body && dots <= 1

-- | `Parse.parseInt 10`, TOTAL -- shape and RANGE. The shape check alone is not enough:
--   `parseInt 10 "99999999999999"` is all digits and still throws, so this compares the
--   digit string against `Int`'s bound lexicographically first. A digit string of equal
--   length orders exactly as the number does, so the bound needs nothing the language
--   has not got. (Found by E5's reviewer, L-6/L-7: the earlier shape-only version
--   answered `Just <bomb>` on an overflowing literal -- the very defect this section is
--   about, in the helper written to avoid it.)
parseIntTotal : String -> Maybe Int
parseIntTotal s =
  let neg  = take_S 1 s == "-"
      body = if neg (drop_S 1 s) s
      cap  = if neg "2147483648" "2147483647"
      inRange = length_S body < length_S cap
                ||_B (length_S body == length_S cap && body <= cap)
  in if (looksLikeInt s && inRange) (parseInt 10 s) Nothing

-- | `Parse.parseDouble`, total. No range clause is needed here and the asymmetry is the
--   point: `Double` saturates rather than throwing, so `parseDoubleTotal` of a
--   thirty-three-digit literal is `Just 1.0E33`, while the same string through
--   `parseIntTotal` must be refused.
parseDoubleTotal : String -> Maybe Double
parseDoubleTotal s = if (looksLikeNumber s) (parseDouble s) Nothing

-- | A character literal is rejected by POSITION, not by which character it is. `'-'`,
--   `'.'`, `'|'` and `'/'` all lex perfectly well in a definition's head position and as
--   a function argument -- `Lang/TextTables.e` writes `split_S '/' p`. Immediately after
--   a BINARY OPERATOR the lexer's maximal munch takes `'` and the character as one
--   operator token, and every operator character fails there: `c == '-'` is
--   `error: unknown operator '-'`, and so are `c == '.'`, `c == '|'` and `c == '/'`.
--   Parenthesising does not help (`c == ('-')` is `undefined term`). Naming the literal
--   does, which is what these three are for: every comparison in this file is against a
--   NAME, never against a literal.
dashChar, dotChar, pipeChar : Char
dashChar = strCharAt "-" 0
dotChar  = strCharAt "." 0
pipeChar = strCharAt "|" 0

-- ---------------------------------------------------------------------------
-- 1. Applicative accumulation
--
-- `Either`'s shipped applicative SHORT-CIRCUITS: `eitherAp` returns the first `Left`
-- and throws the second away. A validation report must do the opposite. There is no
-- `Validation` functor in the stdlib -- `Validation.e` is a `FormValidator` library
-- whose accumulation is hidden inside `combineErrors` and cannot be reused -- so this
-- is the missing piece, and it is three lines.

-- | The accumulating applicative for `Either e`, given a semigroup on `e`.
--   Differs from `eitherAp` in ONE clause: `Left <*> Left` combines instead of
--   discarding. Not a monad: `bind` cannot accumulate, because the second
--   computation does not exist until the first succeeds.
accumAp : forall e. (e -> e -> e) -> Ap_M (Either e)
accumAp app = Ap_M Right ap'
  where ap' (Right f) (Right a) = Right (f a)
        ap' (Left e1) (Left e2) = Left (app e1 e2)
        ap' (Left e1) _         = Left e1
        ap' _         (Left e2) = Left e2

-- | `accumAp` at the error type every validator in this directory uses.
errsAp : Ap_M (Either (List Err))
errsAp = accumAp (++_L)

-- | Every failure, or every success. The applicative above, run over a list.
allOrNothing : forall e a. (e -> e -> e) -> List (Either e a) -> Either e (List a)
allOrNothing app = sequenceA_T listTraversable_L (accumAp app)

-- ---------------------------------------------------------------------------
-- 2. Traversals over a relation's rows
--
-- These are the corpus shapes: a row VARIABLE under an applicative. `{..r}` is a
-- record over the row `r`; `f (List {..r})` hides that row under a type constructor the
-- solver cannot see into, and it still has to discharge the partitions the caller's
-- projections make.

-- | Traverse a list of records in any applicative. The row `r` is untouched: this is
--   `Control.Traversable.traverse` at `List` with the element type pinned to a record.
traverseRows : forall f r a. Ap_M f -> ({..r} -> f a) -> List {..r} -> f (List a)
traverseRows ap f = traverse_T listTraversable_L ap f

-- | The same in a monad, for effects that must be sequenced (`IO`, `State`).
mapMRows : forall m r a. Monad_M m -> ({..r} -> m a) -> List {..r} -> m (List a)
mapMRows m f = mapM_T listTraversable_L m f

-- | Traverse rows to NEW rows and rebuild a relation. Two rows, `r` in and `s` out,
--   with the applicative in between: the shape a per-row check or repair has.
traverseRel : forall f r s. Ap_M f -> ({..r} -> f {..s}) -> List {..r} -> f (Relation (|..s|))
traverseRel ap f rs = fmap (apFunctor_M ap) relation (traverseRows ap f rs)

-- | Check every row, keep EVERY failure, and only then build the relation.
--   The row survives the `Either` unchanged, which is what makes the result a
--   relation of the input's own header.
checkedRel : forall r. ({..r} -> List Err) -> List {..r} -> Either (List Err) (Relation (|..r|))
checkedRel chk = traverseRel errsAp (t -> case chk t of
  Nil  -> Right t
  errs -> Left errs)

-- | Fold a measure out of every row into any monoid.
foldRows : forall r m. Monoid_Mo m -> ({..r} -> m) -> List {..r} -> m
foldRows m f = foldl_L (acc t -> mappend_Mo m acc (f t)) (mempty_Mo m)

-- ---------------------------------------------------------------------------
-- 3. A row-polymorphic reader for CSV cells
--
-- `IO.CSV.readCSVFile : FilePath -> IO (List (List String))` is where real data
-- arrives: a list of rows of untyped cells. Getting from there to `[..r]` is the
-- interesting typed step, and nothing in the stdlib does it. A `RowReader r` is a
-- function from one row of cells to a record over `r`, accumulating a message per bad
-- cell; `consRow` carries the partition that adds one field to the row.

data RowReader (r : rho) = RowReader (List String -> Either (List Err) {..r})

-- | Apply a reader to ONE row of cells. The row `r` travels under `Either`.
runRowReader : forall r. RowReader r -> List String -> Either (List Err) {..r}
runRowReader (RowReader f) = f

-- | The empty reader: no columns, no errors, the empty record.
nilRow : RowReader (| |)
nilRow = RowReader (_ -> Right {})

-- | Add one column. `t <- (r, s)` says the output row `t` is the new field's row `r`
--   plus everything the rest of the reader produces, `s` -- disjointly, so a repeated
--   field is rejected at compile time (`Lang/shouldfail/lang02_reader_field_twice.e`).
--   Errors from the head and the tail are BOTH kept.
consRow : forall t r s a. t <- (r, s)
       => (Field r a, Int, String -> Maybe a) -> RowReader s -> RowReader t
consRow (fld, ix, rd) (RowReader rest) = RowReader (cs ->
  let cell = orElse "" (at_L ix cs)
      here = case rd cell of
               Nothing -> Left ((fieldName fld, "unreadable cell " ++_S toString ix
                                                ++_S ": " ++_S cell) :: Nil)
               Just a  -> Right a
  in case (here, rest cs) of
       (Right a, Right t)  -> Right (cons fld a t)
       (Left e1, Left e2)  -> Left (e1 ++_L e2)
       (Left e1, _)        -> Left e1
       (_,       Left e2)  -> Left e2)

-- | Read every line, accumulate every line's every error, and build the relation.
--   The header is passed explicitly so that an EMPTY input still has a type-correct
--   relation, which `Relation.relation` alone cannot give you.
readRowsAs : forall r. RowReader r -> Row_R r -> List (List String) -> Either (List Err) [..r]
readRowsAs rdr hdr ls =
  fmap (apFunctor_M errsAp) (relationWithHeader hdr)
       (traverse_T listTraversable_L errsAp (runRowReader rdr) ls)

-- cell readers, to hand to `consRow`
-- | The identity cell reader: every string is a valid string.
cellString : String -> Maybe String
cellString = Just

-- | A whole-number cell, trimmed, through the TOTAL parser (never the raw `Parse` one).
cellInt : String -> Maybe Int
cellInt = parseIntTotal . trim_S

-- | A decimal cell, trimmed, through the total parser.
cellDouble : String -> Maybe Double
cellDouble = parseDoubleTotal . trim_S

-- | A cell that may be blank, with a default. Never fails.
cellOr : forall a. a -> (String -> Maybe a) -> String -> Maybe a
cellOr d rd s = Just (orElse d (rd s))

-- ---------------------------------------------------------------------------
-- 4. Parser combinators
--
-- `Parse` in the stdlib is `java.lang.Integer.parseInt` and five siblings. This is the
-- library a reader expects under that name: a state-passing parser with a `Monad`, an
-- `Ap`, an `Alt` and a row-polymorphic record builder.

data Parser a = Parser (String -> Maybe (a, String))

-- | Run a parser, returning the value and WHAT IS LEFT. `parseAll` is the strict form.
runParser : forall a. Parser a -> String -> Maybe (a, String)
runParser (Parser f) = f

-- | Run a parser and insist it consumed the whole input.
parseAll : forall a. Parser a -> String -> Maybe a
parseAll p s = case runParser p s of
  Just (a, rest) -> if (strIsEmpty rest) (Just a) Nothing
  Nothing        -> Nothing

-- | The dictionary that makes `do` work at `Parser`: state-passing bind, no backtracking
--   once the first parser has consumed input.
parserMonad : Monad_M Parser
parserMonad = Monad_M punit pbind
private
  punit a = Parser (s -> Just (a, s))
  pbind (Parser m) f = Parser (s -> case m s of
    Nothing      -> Nothing
    Just (a, s') -> runParser (f a) s')

-- | Derived from the monad, so `liftA2`/`traverse` work at `Parser` for free.
parserAp : Ap_M Parser
parserAp = monadAp_M parserMonad

-- | Likewise derived; `fmap parserFunctor` is how every combinator below reshapes a result.
parserFunctor : Functor Parser
parserFunctor = monadFunctor_M parserMonad

-- | Ordered choice, first match wins. `empty` is the parser that always fails, so
--   `firstOf parserAlt` is a keyword table.
parserAlt : Alt_Alt Parser
parserAlt = Alt_Alt (Parser (_ -> Nothing)) por parserAp
private
  por (Parser m) (Parser n) = Parser (s -> case m s of
    Nothing -> n s
    hit     -> hit)

-- | One character, as a `Char`, if the predicate holds.
pSat : (Char -> Bool) -> Parser Char
pSat ok = Parser (s ->
  if (strIsEmpty s) Nothing
     (let c = strCharAt s 0
      in if (ok c) (Just (c, drop_S 1 s)) Nothing))

-- | A literal prefix.
pLit : String -> Parser String
pLit lit = Parser (s ->
  if (take_S (strLength lit) s == lit) (Just (lit, drop_S (strLength lit) s)) Nothing)

-- | Zero or more. `pMany` on a parser that can succeed without consuming input does
--   NOT terminate -- Ermine will not catch that for you; see `Lang/StatementParser.e`.
pMany : forall a. Parser a -> Parser (List a)
pMany p = alt_Alt parserAlt (pSome p) (unit_M parserMonad Nil)

-- | One or more.
pSome : forall a. Parser a -> Parser (List a)
pSome p = bind_M parserMonad p (a -> fmap parserFunctor ((::) a) (pMany p))

-- | One or more, separated. The separator's result is dropped.
pSepBy : forall a b. Parser b -> Parser a -> Parser (List a)
pSepBy sep p = bind_M parserMonad p (a ->
  fmap parserFunctor ((::) a) (pMany (bind_M parserMonad sep (_ -> p))))

-- | Any run of characters that are neither letters, digits nor `-`: this parser's notion
--   of separator. Always succeeds, possibly on nothing.
pSpaces : Parser (List Char)
pSpaces = pMany (pSat (c -> not (charIsLetter c) && not (charIsDigit c) && c != dashChar))

-- | A parser, then any run of separators after it.
pToken : forall a. Parser a -> Parser a
pToken p = bind_M parserMonad p (a -> fmap parserFunctor (_ -> a) pSpaces)

-- | One or more digits, as a `String`.
pDigits : Parser String
pDigits = fmap parserFunctor charsToString (pSome (pSat charIsDigit))

-- | An optionally-signed integer, through `parseIntTotal`, so an overflowing literal
--   FAILS the parse rather than succeeding with a bomb.
pInt : Parser Int
pInt = bind_M parserMonad (pMany (pLit "-")) (sgn ->
       bind_M parserMonad pDigits (ds ->
         case parseInt 10 (concat_S sgn ++_S ds) of
           Just n  -> unit_M parserMonad n
           Nothing -> empty_Alt parserAlt))

-- | A decimal, through `parseDoubleTotal`.
pDouble : Parser Double
pDouble = bind_M parserMonad (pMany (pSat (c -> charIsDigit c ||_B c == dotChar ||_B c == dashChar))) (cs ->
  case parseDoubleTotal (charsToString cs) of
    Just d  -> unit_M parserMonad d
    Nothing -> empty_Alt parserAlt)

-- | Everything up to (not including) a delimiter.
pUpTo : Char -> Parser String
pUpTo d = fmap parserFunctor charsToString (pMany (pSat (c -> c != d)))

-- | Build a RECORD in the parser monad, one field at a time. This is `consRow`'s
--   shape under a different type constructor, and it is the helper that puts a row
--   partition under `Parser` -- the shape the census had never seen.
pRecord : forall t r s a. t <- (r, s) => Field r a -> Parser a -> Parser {..s} -> Parser {..t}
pRecord fld pa ps =
  bind_M parserMonad pa (a -> fmap parserFunctor (cons fld a) ps)

-- | The empty record parser, to end a `pRecord` chain.
pNil : Parser {}
pNil = unit_M parserMonad {}

-- ---------------------------------------------------------------------------
-- 4b. Natural transformations, and the rank-2 argument that does not work
--
-- `Data.Free` gives `Free f a` and a `Monad (Free f)` and then stops: there is no
-- `foldFree`, no `iterM`, no `runFree`, no `FreeT`. `lowerFree : Monad m -> Free m a ->
-- m a` needs the COMMAND functor to be a monad, so it cannot run a DSL. The missing
-- eliminator is eight lines and it is below.
--
-- What makes it eight lines rather than two is a language fact worth more than the
-- library: **a rank-2 function ARGUMENT cannot be applied.** The obvious spelling
--
--     oneWay : forall f m. (forall x. f x -> m x) -> f Int -> m Int
--     oneWay nat a = nat a
--     -- error: failed to unify type (forall x. f x -> m x) with type (a -> b)
--
-- type-checks as a signature and its argument cannot be USED. Wrap the same `forall` in
-- a DATA FIELD and it works. That is why every dictionary in `Control.*` is a `data`
-- with `forall`s in its fields rather than a tuple of polymorphic functions, why
-- `Data.Free.Church`'s `runF` is the one stdlib fold that needs no functor (its rank-2
-- is inside `F`), and why `foldFree` is missing. `Lang/TypesAndRows.e` section 9 is the
-- worked demonstration.

-- | A natural transformation `f ~> m`, in the only form the language can apply.
data Nat f m = Nat (forall x. f x -> m x)

-- | Interpret a `Free f` program in any monad, given an interpretation of one command.
--   The eliminator `Data.Free` does not ship. Note what it does NOT need: no
--   `Functor f`, because `k fs` already lands in `m` and `bind` does the recursion.
foldFree : forall f m a. Monad_M m -> Nat f m -> Free_Fr f a -> m a
foldFree mm n (Pure_Fr a)  = unit_M mm a
foldFree mm n (Free_Fr fs) = case n of
  Nat k -> bind_M mm (k fs) (rest -> foldFree mm n rest)

-- ---------------------------------------------------------------------------
-- 5. State: threading an accumulator through rows

-- | Fold a state through the rows, keeping one output per row AND the final state.
--   Written with `Control.Monad.State` and `Control.Traversable` rather than by hand,
--   so that the row variable travels under `State s`.
withState : forall r s a. ({..r} -> s -> (a, s)) -> s -> List {..r} -> (List a, s)
withState step s0 rows =
  runState_St (mapMRows stateMonad_St (t -> State_St (s -> step t s)) rows) s0

-- | The running values of a fold, one per row (a value-level `scan`).
scanRows : forall r s. (s -> {..r} -> s) -> s -> List {..r} -> List s
scanRows step s0 rows = fst (withState (t -> s -> let s' = step s t in (s', s')) s0 rows)

-- | Add a running-total COLUMN to every row. `t <- (r, c)` is the partition that says
--   the output row is the input row plus exactly the new column, so the compiler
--   rejects a column name the input already has.
withRunning : forall t r c n. t <- (r, c)
           => Field c n -> (n -> {..r} -> n) -> n -> List {..r} -> List {..t}
withRunning fld step z rows =
  fst (withState (t -> s -> let s' = step s t in (cons fld s' t, s')) z rows)

-- ---------------------------------------------------------------------------
-- 6. Reader: a report is a function from its parameters
--
-- `Control.Monad.Reader` defines `type Reader e a = e -> a`, so a parameterised report
-- IS a reader and needs no wrapper. What is worth naming is reading one FIELD of a
-- parameter record, because that is where the row constraint lives.

-- | Read one field out of the parameter record. `Has e h` is sugar for
--   `exists c. e <- (h, c)`, and the published interface writes that sugar out.
askField : forall e h a. Has e h => Field h a -> Reader_Rd {..e} a
askField f = (p -> p ! f)

-- | Run a report against one parameter set.
runWith : forall e a. {..e} -> Reader_Rd {..e} a -> a
runWith p r = runReader_Rd r p

-- | Override one parameter for part of a report. `local` under a field.
localField : forall e h a b. Has e h => Field h a -> (a -> a) -> Reader_Rd {..e} b -> Reader_Rd {..e} b
localField f g = local_Rd (modify f g)

-- ---------------------------------------------------------------------------
-- 7. Alt: the first thing that works

-- | The first success in a list, or `empty`. `Alt` is `Control.Alt`'s dictionary:
--   a zero, a choice and an `Ap`.
firstOf : forall f a. Alt_Alt f -> List (f a) -> f a
firstOf f = foldr_L (alt_Alt f) (empty_Alt f)

-- | Left-biased choice as a named function, for readability at call sites.
orElseA : forall f a. Alt_Alt f -> f a -> f a -> f a
orElseA = alt_Alt

-- | Succeed with a default instead of failing.
withDefaultA : forall f a. Alt_Alt f -> a -> f a -> f a
withDefaultA f d p = alt_Alt f p (pure_M (altAp_Alt f) d)

-- ---------------------------------------------------------------------------
-- 8. Monoids: the measures a report sums

-- | `foldMap` over a list at an explicit monoid. `foldRows` is this with the element
--   type pinned to a record.
foldMapL : forall a m. Monoid_Mo m -> (a -> m) -> List a -> m
foldMapL m f = foldl_L (acc a -> mappend_Mo m acc (f a)) (mempty_Mo m)

-- | Addition on `Double`, identity 0.
sumMonoid : Monoid_Mo Double
sumMonoid = Monoid_Mo 0.0 (+)

-- | Addition on `Int`, identity 0 -- so `foldRows countMonoid (_ -> 1)` counts and
--   `foldRows countMonoid (t -> t ! qty)` sums. The name describes the first use; both
--   are in the group.
countMonoid : Monoid_Mo Int
countMonoid = Monoid_Mo 0 (+)

-- | Maximum, with a very negative identity -- not a lattice bottom, just small enough
--   for report data. `Ord` is a value in Ermine, so a general version would take one.
maxMonoid : Monoid_Mo Double
maxMonoid = Monoid_Mo (0.0 - 1.0e18) (a b -> if (a > b) a b)

-- | Minimum, with a very large identity. The dual of `maxMonoid`; used in
--   `Lang/DoNotation.e` to bracket a measure from both sides in one pass.
minMonoid : Monoid_Mo Double
minMonoid = Monoid_Mo 1.0e18 (a b -> if (a < b) a b)

-- | Concatenation of strings, with a separator. Not `stringMonoid`: that one has no
--   separator and so cannot render a row.
joinedMonoid : String -> Monoid_Mo String
joinedMonoid sep = Monoid_Mo "" (a b ->
  if (strIsEmpty a) b (if (strIsEmpty b) a (a ++_S sep ++_S b)))

-- ---------------------------------------------------------------------------
-- 9. Text: the only rendering this build can do
--
-- There is no `render`: a `Report` needs a `Layout.Writer` and every concrete writer
-- lives in the separate `ermine-writers` project. A markdown table, however, is a
-- `String`, and a `String` prints in the REPL. `Lang/TextTables.e` uses these to draw
-- a relation you can actually look at.

-- | The inverse of `stringChars`; every character parser ends in one of these.
charsToString : List Char -> String
charsToString = foldl_L (acc c -> acc ++_S toString c) ""

-- | Pad on the right to a fixed width. `Layout.Report` owns `padRight`/`padLeft`, which
--   are about page boxes, so the string versions need their own names.
rpad : Int -> String -> String
rpad n s = if (strLength s >= n) s (rpad n (s ++_S " "))

-- | Pad on the left, for right-aligned numeric columns.
lpad : Int -> String -> String
lpad n s = if (strLength s >= n) s (lpad n (" " ++_S s))

-- | `String.Markdown.link` reads `"[" ++ title "](" ++ loc ++ ")"`; juxtaposition binds
--   tighter than `++`, so `title` is APPLIED and the shipped type is
--   `(String -> String) -> String -> String`. It is not unusable -- pass the title
--   pre-composed and it works: `link ((++) "SUP-77/A") loc` really does return
--   `"[SUP-77/A](...)"`. What is broken is that no ORDINARY call site type-checks, and
--   the working spelling is undocumented and unguessable. This is what it meant to say.
mdLink : String -> String -> String
mdLink title loc = "[" ++_S title ++_S "](" ++_S loc ++_S ")"

-- | One markdown table row: cells joined by ` | ` between leading and trailing pipes.
mdRow : List String -> String
mdRow cs = "| " ++_S mconcat (joinedMonoid " | ") cs ++_S " |"

-- | The `| --- | --- |` rule under a markdown header, for a table of n columns.
mdRule : Int -> String
mdRule n = mdRow (replicate_L "---" n)

-- | A markdown table from a header and a list of already-stringified rows.
mdTable : List String -> List (List String) -> String
mdTable hdr body =
  mconcat (joinedMonoid "\n") (mdRow hdr :: mdRule (length_L hdr) :: map mdRow body)

-- | Render a relation's rows as a markdown table. The row variable `r` is what the
--   caller's `cells` function projects; `hdr` names the columns in the order drawn.
showRows : forall r. List String -> ({..r} -> List String) -> List {..r} -> String
showRows hdr cells rows = mdTable hdr (map cells rows)

private
  mconcat : Monoid_Mo String -> List String -> String
  mconcat m = foldMapL m id

-- ---------------------------------------------------------------------------
-- 10. Types remembered
--
-- `Type.Remember` is two functions and no example anywhere. `unify a b` returns `b`
-- after forcing the two to have the same type; `asTypeOf a b` returns `a`. They are the
-- way to pin an inferred type without writing a signature -- which matters here,
-- because two of this directory's inferred types CANNOT be written down (see
-- `Lang/Signatures.e`).

-- | Force `x` to have the type of the witness, and return `x`.
sameShapeAs : forall a. a -> a -> a
sameShapeAs = asTypeOf_Rem

-- | The `do`-notation idiom, named: run a `Syntax.Do` block in a given monad.
--   `Syntax.Do` desugars a block to `Monad f -> f a`; this is the application.
inMonad : forall f a. Monad_M f -> (Monad_M f -> f a) -> f a
inMonad m k = k m

-- | Twice over: the smallest `do` block that is generic in its monad, and the model
--   every `do` in this directory follows.
twiceOver : forall m. Monad_M m -> m Int -> m Int
twiceOver m ma = inMonad m (do { a <- liftDo ma; b <- liftDo ma; unit (a + b) })
