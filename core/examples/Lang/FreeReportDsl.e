module Lang.FreeReportDsl where

{- A SMALL REPORT DSL AS A FREE MONAD, run two ways: DESCRIBED and RENDERED. Plus the
   Church encoding of the same program, a `Cofree` stream and a `Nu` unfold.

   Fact: quarterFacts (8 fields: lineCode, lineLabel, channelName, quarterName,
         unitsSold, grossSales, discountAmt, netSales)

   WHY THIS FILE EXISTS. `Data/Free.e` is twenty-four lines, `Data/Free/Church.e`
   twenty-seven, `Data/Cofree.e` thirteen and `Data/Nu.e` thirteen, and between them
   they have no example anywhere in the repository. They are also the clearest
   demonstration of what Ermine's dictionary-passing buys you: `freeMonad` takes a
   `Functor f` and hands back a `Monad (Free f)`, so a DSL is

       1. a functor for the commands              (`cmdFunctor`, six lines)
       2. one lifting function per command        (`say`, `total`, `tabulate`)
       3. a program, written with `do`            (`salesProgram`)
       4. as many interpreters as you like        (`describeOf`, `renderOf`, `countOf`)

   and step 4 is the payoff: the SAME program is a table of contents, a rendered
   document, and a static cost estimate, with no rewriting.

   FREE VS CHURCH. `Data.Free`'s representation is a tree and each `bind` walks it, so
   a left-nested chain of binds is quadratic. `Data.Free.Church` is the CPS
   representation --

       data F f a = F (forall r. (a -> r) -> (f r -> r) -> r)

   -- which fuses the binds and, as its own comment says, "has the benefit of not
   requiring a functor instance for f". Both encodings of the same three-command
   program are below, and both interpreters agree.

   WHAT THE STDLIB DOES NOT HAVE, AND WHAT THIS GROUP DOES ABOUT IT.
   `Data.Free.lowerFree : Monad m -> Free m a -> m a` needs the command functor to BE a
   monad, so it cannot run this DSL, and there is no `foldFree`, `iterM`, `runFree`,
   `FreeT` or `hoistFree` anywhere in `Data/Free.e`'s twenty-four lines. That is the
   stdlib's absence. `Helpers.foldFree` is this group's answer to it -- eight lines,
   generic in the command functor and the monad -- and `countedByFold` below is one of
   this file's interpreters rewritten as an algebra over it, so the two spellings can be
   compared. The three hand-written interpreters are kept because recursion over
   `Pure`/`Free` is what a reader should see first.

   The reason `foldFree` needs `Helpers.Nat` rather than a plain function argument is a
   language fact and it is the more interesting half: **a rank-2 function argument cannot
   be applied.** `Lang/TypesAndRows.e` section 9 has the two-line demonstration; it is
   also why `Data.Free.Church`'s `runF` below is the one stdlib fold that needs no
   functor -- its rank-2 lives in a `data` field.

   SHAPES EXERCISED
     * `Data.Free`: `freeFunctor`, `freeMonad`, `liftFree`, `Pure`/`Free` patterns.
     * `Data.Free.Church`: `F`, `fMonad`, `runF`, and the rank-2 field it hides.
     * `Data.Cofree`: `(:<)`, `cofreeFunctor`, `cofreeComonad`, `extract`, `extend` on
       an INFINITE stream -- a comonad the stdlib has and nothing uses.
     * `Data.Nu`: `unfold`/`observe`, and the existential `data Nu f = forall s. Unfold`.
     * `Syntax.Do` over a monad built at run time from a dictionary.
     * `Helpers.foldFree` and `Helpers.Nat`: the eliminator `Data.Free` does not ship,
       and the rank-2 wrapper that is the only form the language can apply.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/FreeReportDsl.e
   >> describeOf salesProgram
   >> countOf salesProgram
   >> renderOf salesProgram          -- a markdown document, as a String
   >> countedByFold                  -- 6: the same program through `Helpers.foldFree`
   >> churchDescription
   >> firstFive
   >> firstFiveSmoothed
   >> nuTake 6 countUp
   >> nuTake 8 fibs
   >> dslReport
-}

import Prelude
import Syntax.List
import Control.Monad as M
import Control.Comonad as Cm
import Data.Free as Fr
import Data.Free.Church as Ch
import Data.Cofree as Cf
import Data.Nu as Nu
import Control.Monad.State as St
import Layout
import List as L
import String as S
import Lang.Helpers

field lineCode    : String
field lineLabel   : String
field channelName : String
field quarterName : String
field unitsSold   : Int
field grossSales  : Double
field discountAmt : Double
field netSales    : Double

-- ---------------------------------------------------------------------------
-- 1. The command functor. Three commands; the last argument of each is the
--    continuation, which is what makes it a functor at all.

data ReportCmd a
  = SayC String a
  | TotalC String Double a
  | TableC String (List String) (List (List String)) a

cmdFunctor : Functor ReportCmd
cmdFunctor = Functor mapCmd
private
  mapCmd : (a -> b) -> ReportCmd a -> ReportCmd b
  mapCmd f (SayC s k)        = SayC s (f k)
  mapCmd f (TotalC n v k)    = TotalC n v (f k)
  mapCmd f (TableC t h rs k) = TableC t h rs (f k)

dslMonad : Monad_M (Free_Fr ReportCmd)
dslMonad = freeMonad_Fr cmdFunctor

-- ---------------------------------------------------------------------------
-- 2. The three lifting functions. `liftFree` is the generic one; writing them out
--    shows what it does.

say : String -> Free_Fr ReportCmd ()
say s = liftFree_Fr cmdFunctor (SayC s ())

total : String -> Double -> Free_Fr ReportCmd ()
total n v = liftFree_Fr cmdFunctor (TotalC n v ())

tabulate : String -> List String -> List (List String) -> Free_Fr ReportCmd ()
tabulate t h rs = liftFree_Fr cmdFunctor (TableC t h rs ())

-- ---------------------------------------------------------------------------
-- 3. The facts, and the program written over them.

quarterFacts : List {lineCode, lineLabel, channelName, quarterName, unitsSold,
                     grossSales, discountAmt, netSales}
quarterFacts = [
  { lineCode = "LN-10", lineLabel = "Road bikes", channelName = "Retail",
    quarterName = "Q1", unitsSold = 412, grossSales = 618000.0,
    discountAmt = 24720.0, netSales = 593280.0 },
  { lineCode = "LN-10", lineLabel = "Road bikes", channelName = "Wholesale",
    quarterName = "Q1", unitsSold = 980, grossSales = 1225000.0,
    discountAmt = 110250.0, netSales = 1114750.0 },
  { lineCode = "LN-20", lineLabel = "Apparel", channelName = "Retail",
    quarterName = "Q1", unitsSold = 3150, grossSales = 236250.0,
    discountAmt = 11812.5, netSales = 224437.5 },
  { lineCode = "LN-30", lineLabel = "Components", channelName = "Wholesale",
    quarterName = "Q1", unitsSold = 1740, grossSales = 435000.0,
    discountAmt = 34800.0, netSales = 400200.0 },
  { lineCode = "LN-20", lineLabel = "Apparel", channelName = "Online",
    quarterName = "Q1", unitsSold = 2210, grossSales = 176800.0,
    discountAmt = 5304.0, netSales = 171496.0 }
  ]_L

factRows : List (List String)
factRows = map (t -> [t ! lineLabel, t ! channelName, toString (t ! unitsSold),
                      toString (t ! netSales)]_L) quarterFacts

netTotal : Double
netTotal = foldRows sumMonoid (t -> t ! netSales) quarterFacts

unitTotal : Int
unitTotal = foldRows countMonoid (t -> t ! unitsSold) quarterFacts

-- | The program. Six commands, written with `do` in the monad `freeMonad` built from
--   `cmdFunctor` -- a monad that did not exist until this file made one.
salesProgram : Free_Fr ReportCmd ()
salesProgram = (do liftDo (say "# Bicycle sales, Q1 2011")
                   liftDo (say "## By line and channel")
                   liftDo (tabulate "Q1 detail"
                                    (["Line", "Channel", "Units", "Net"]_L)
                                    factRows)
                   liftDo (total "Net sales" netTotal)
                   liftDo (total "Units" (toDouble unitTotal))
                   liftDo (say "Prepared from `quarterFacts`.")) ' dslMonad

-- ---------------------------------------------------------------------------
-- 4. Three interpreters over the SAME program.

-- | (a) DESCRIBE: what the document will contain, without building it.
describeOf : forall a. Free_Fr ReportCmd a -> List String
describeOf (Pure_Fr _)                = Nil
describeOf (Free_Fr (SayC s k))       = ("text: " ++_S s) :: describeOf k
describeOf (Free_Fr (TotalC n v k))   = ("total: " ++_S n) :: describeOf k
describeOf (Free_Fr (TableC t h rs k)) =
  ("table: " ++_S t ++_S " (" ++_S toString (length_L rs) ++_S " rows, "
             ++_S toString (length_L h) ++_S " columns)") :: describeOf k

-- | (b) COUNT: a static cost, in lines the document will occupy.
countOf : forall a. Free_Fr ReportCmd a -> Int
countOf (Pure_Fr _)                 = 0
countOf (Free_Fr (SayC _ k))        = 1 + countOf k
countOf (Free_Fr (TotalC _ _ k))    = 1 + countOf k
countOf (Free_Fr (TableC _ _ rs k)) = 2 + length_L rs + countOf k

-- | (c) RENDER: the actual markdown document, as a String you can print.
renderOf : forall a. Free_Fr ReportCmd a -> String
renderOf p = foldMapL (joinedMonoid "\n") id (go p)
  where go : forall b. Free_Fr ReportCmd b -> List String
        go (Pure_Fr _)                 = Nil
        go (Free_Fr (SayC s k))        = s :: go k
        go (Free_Fr (TotalC n v k))    = ("**" ++_S n ++_S "**: " ++_S toString v) :: go k
        go (Free_Fr (TableC t h rs k)) = ("### " ++_S t) :: mdTable h rs :: go k

-- | (d) THE SAME COUNT, as an algebra over `Helpers.foldFree`. `Nat` carries the
--   interpretation of ONE command into the target monad; `foldFree` does the recursion.
--   Here the target is the list monad, so a command that yields `[k]` keeps going and
--   one that yields `[]` would stop.
cmdToList : forall x. ReportCmd x -> List x
cmdToList (SayC _ k)       = k :: Nil
cmdToList (TotalC _ _ k)   = k :: Nil
cmdToList (TableC _ _ _ k) = k :: Nil

foldedProgram : List ()
foldedProgram = foldFree listMonad (Nat cmdToList) salesProgram

-- | And an algebra that actually computes: the number of commands, through the same
--   eliminator, by counting in `State Int` instead of the list monad.
countedByFold : Int
countedByFold = snd (runState_St (foldFree stateMonad_St (Nat cmdToState) salesProgram) 0)

cmdToState : forall x. ReportCmd x -> State_St Int x
cmdToState (SayC _ k)       = State_St (n -> (k, n + 1))
cmdToState (TotalC _ _ k)   = State_St (n -> (k, n + 1))
cmdToState (TableC _ _ _ k) = State_St (n -> (k, n + 1))

-- ---------------------------------------------------------------------------
-- 5. The same program in the CHURCH encoding.
--
-- `F f a`'s single field is rank-2: `forall r. (a -> r) -> (f r -> r) -> r`. There is no
-- `liftF` in `Data/Free/Church.e`, so lifting is written by hand -- and note that it
-- needs NO functor dictionary, which is the encoding's advertised advantage.

churchSay : String -> F_Ch ReportCmd ()
churchSay s = F_Ch (kp kf -> kf (SayC s (kp ())))

churchTotal : String -> Double -> F_Ch ReportCmd ()
churchTotal n v = F_Ch (kp kf -> kf (TotalC n v (kp ())))

churchProgram : F_Ch ReportCmd ()
churchProgram = (do liftDo (churchSay "# Bicycle sales, Q1 2011")
                    liftDo (churchTotal "Net sales" netTotal)
                    liftDo (churchSay "Prepared from `quarterFacts`.")) ' fMonad_Ch

-- | Interpreting the Church encoding is `runF` with two continuations and no pattern
--   matching at all: the program IS its own fold.
churchDescription : List String
churchDescription = runF_Ch churchProgram (_ -> Nil) alg
  where alg (SayC s k)      = ("text: " ++_S s) :: k
        alg (TotalC n v k)  = ("total: " ++_S n) :: k
        alg (TableC t h rs k) = ("table: " ++_S t) :: k

-- ---------------------------------------------------------------------------
-- 6. `Cofree`: the dual, and the comonad nothing in this repository uses.
--
-- `data Cofree f a = (:<) a (f (Cofree f a))` with `f = Id` is an infinite stream: a
-- head and exactly one tail. `extend` is the comonadic scan -- it replaces every
-- position by a function of the whole stream FROM that position, which is what a
-- moving average is.

data Nxt a = Nxt a
nxtFunctor : Functor Nxt
nxtFunctor = Functor (f -> (Nxt a) -> Nxt (f a))

type Stream a = Cofree_Cf Nxt a

streamOf : List Double -> Stream Double
streamOf Nil       = 0.0 :<_Cf Nxt (streamOf Nil)
streamOf (x :: xs) = x   :<_Cf Nxt (streamOf xs)

takeS : Int -> Stream a -> List a
takeS n (a :<_Cf Nxt t) = if (n <= 0) Nil (a :: takeS (n - 1) t)

netSeries : Stream Double
netSeries = streamOf (map (t -> t ! netSales) quarterFacts)

firstFive : List Double
firstFive = takeS 5 netSeries

-- | A two-point moving average, written as `extend` over the comonad.
smoothed : Stream Double -> Stream Double
smoothed = extend_Cm (cofreeComonad_Cf nxtFunctor) mean2
  where mean2 (a :<_Cf Nxt (b :<_Cf _)) = (a + b) / 2.0

firstFiveSmoothed : List Double
firstFiveSmoothed = takeS 5 (smoothed netSeries)

-- ---------------------------------------------------------------------------
-- 7. `Nu`: a corecursive value with its seed hidden by an EXISTENTIAL.
--
--     data Nu f = forall s. Unfold (s -> f s) s
--
-- The seed type `s` is not in `Nu f`'s type, so two `Nu Nxt` values can have entirely
-- different states. `observe` is the only way to look, and it needs the functor.

-- The seed is genuinely OPAQUE. This does not compile:
--
--     seedOf (Unfold f x) = x
--     -- error: skolem variables escape:  Type would have been: Nu f -> !s
--
-- so a `Nu f` is only useful when `f` itself carries the value, which is why the
-- functor below has TWO fields where `Nxt` has one. `observe` is the only elimination.

data Step a = Step Int a
stepFunctor : Functor Step
stepFunctor = Functor (f -> (Step n a) -> Step n (f a))

countUp : Nu_Nu Step
countUp = unfold_Nu (n -> Step n (n + 1)) 0

-- | The same corecursive value with a different STATE type -- a pair -- and the same
--   type `Nu Step`, which is exactly what the existential is for.
fibs : Nu_Nu Step
fibs = unfold_Nu ((a, b) -> Step a (b, a + b)) (0, 1)

nuTake : Int -> Nu_Nu Step -> List Int
nuTake n s =
  if (n <= 0) Nil
     (case observe_Nu stepFunctor s of Step v s' -> v :: nuTake (n - 1) s')

-- ---------------------------------------------------------------------------
-- 8. And the ordinary report, so the DSL can be compared with the real thing.

quarterRel : Relation (|lineCode, lineLabel, channelName, quarterName, unitsSold,
                        grossSales, discountAmt, netSales|)
quarterRel = relation quarterFacts

dslReport : Report f z
dslReport = vflow [
    text "## The DSL program, described",
    text (foldMapL (joinedMonoid "\n\n") id (describeOf salesProgram)),
    text "## The DSL program, rendered",
    text (renderOf salesProgram),
    text "## The same facts through the ordinary report combinators",
    tabular Nothing (quarterRel # {lineLabel, channelName, unitsSold, netSales})
  ]_L
