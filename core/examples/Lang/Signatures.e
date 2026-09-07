module Lang.Signatures where

{- THE SMALLER SIGNATURES, AND MACHINE-CHECKED PROOF THAT THEY SAY THE SAME.

   For each generic helper in `Lang/Helpers.e` whose inferred constraint set differs
   from the one it ships with, this file holds

     xFull     -- a body carrying VERBATIM the constraint set the compiler infers for
                  it (read out of a `-Dermine.useInterface=true` interface), and
     xDeduped  -- the same constraint set with the redundant members deleted, DEFINED
                  AS `= xFull`.

   That definition is the proof. Checking `xDeduped = xFull` means assuming the deduped
   constraints and discharging the full ones, so if the module compiles then the deduped
   set ENTAILS the full set; the full set trivially entails the deduped one, being a
   superset. The two are therefore equivalent.

   Where the shipped signature is a SPECIALISATION rather than an equivalent -- the
   signature a person would actually write at one type -- it is named `xSimple` and its
   body is written out, so that checking it proves the body really has that type.

   KEEP THIS FILE SEPARATE from the helper file: an annotated copy of a body in the same
   module as the unannotated one perturbs what the unannotated one infers.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/Signatures.e
   >> permutationHolds
   >> sugarHolds
   >> sameFieldTwice     -- `Has r h1, Has r h2` does NOT make the two fields disjoint
-}

import Prelude
import Syntax.List
import Control.Monad as M
import Control.Traversable as T
import Control.Monad.State as St
import List as L
import String as S
import Lang.Helpers

-- =========================================================== 0. two lemmas

-- `r <- (r)` is a tautology: it is discharged at a call site with NO constraint in
-- scope, so every occurrence of it in a residual is noise.
taut : r <- (r) => List {..r} -> List {..r}
taut x = x

tautIsFree : forall r. List {..r} -> List {..r}
tautIsFree x = taut x

-- The right-hand side of a partition is a SET, so the rotations entail one another.
permA : t <- (a, b) => RowReader t -> RowReader t
permA x = x
permB : t <- (b, a) => RowReader t -> RowReader t
permB x = permA x

permutationHolds : Bool
permutationHolds = True    -- proved by the fact that `permB` above compiles

-- =========================================================== 1. `consRow` and `pRecord`
--
-- The interface for the ETA-DELEGATED forms
--
--     iConsRow (fld, ix, rd) rest = consRow (fld, ix, rd) rest
--     iPRecord fld pa ps        = pRecord fld pa ps
--
-- reads, verbatim (`-Dermine.useInterface=true`, 2026-09-07):
--
--     iConsRow : forall (r: rho) a (s: rho) (t: rho). t <- (r, s)
--             => (Field r a, Int, String -> Maybe a) -> RowReader s -> RowReader t
--     iPRecord : forall (r: rho) a (s: rho) (t: rho). t <- (s, r)
--             => Field r a -> Parser a -> Parser (Record s) -> Parser (Record t)
--
-- Same body shape, same shipped signature -- and the partition comes back PERMUTED for
-- one of them and not for the other. That is not a bug: the right-hand side of a
-- partition is a SET, so the two entail one another, and which order the printer picks
-- depends on the order the solver happened to normalise. It does mean an `.ei` read as
-- documentation will not always match the source it came from.
--
-- (Before 2026-09-07 03:22 both also carried an inferred KIND variable,
-- `forall {a} … (a1: a)`, which the surface parser rejects. See
-- `tracker/loopmodel/E5-EXAMPLES.md` section 4.5 and
-- `Lang/shouldfail/lang07_kind_variable_written.e`, which is a language fact
-- independent of any solver change.)

consRowFull : forall (r: rho) a (s: rho) (t: rho). t <- (s, r)
           => (Field r a, Int, String -> Maybe a) -> RowReader s -> RowReader t
consRowFull p rest = consRow p rest

consRowDeduped : forall r a s t. t <- (r, s)
              => (Field r a, Int, String -> Maybe a) -> RowReader s -> RowReader t
consRowDeduped = consRowFull

-- =========================================================== 2. `pRecord` from scratch
--
-- Written out rather than delegated,
--
--     jPRecord fld pa ps = bind_M parserMonad pa (a -> fmap parserFunctor (cons fld a) ps)
--
-- infers
--
--     forall (a: rho) b (c: rho) (d: rho). d <- (c, a)
--       => Field a b -> Parser b -> Parser (Record c) -> Parser (Record d)
--
-- -- the permutation again, and no kind variable, because `cons`'s own signature fixes
-- the value type's kind at `*`.

pRecordFull : forall a b c d. d <- (c, a)
           => Field a b -> Parser b -> Parser {..c} -> Parser {..d}
pRecordFull fld pa ps = bind_M parserMonad pa (v -> fmap parserFunctor (cons fld v) ps)

pRecordDeduped : forall r a s t. t <- (r, s)
              => Field r a -> Parser a -> Parser {..s} -> Parser {..t}
pRecordDeduped = pRecordFull

-- The SPECIALISATION a person writes: a parser for one two-column row.
field ledgerRef : String
field ledgerAmt : Double

pRecordSimple : Parser {ledgerRef, ledgerAmt}
pRecordSimple = pRecord ledgerRef (pUpTo pipeChar)
                  (pRecord ledgerAmt pDouble pNil)

-- =========================================================== 3. `withRunning`
--
--     jWithRunning fld step z rows =
--       fst (withState (t -> s -> let s' = step s t in (cons fld s' t, s')) z rows)
--
-- infers
--
--     forall (a: rho) b (c: rho) (d: rho). d <- (c, a)
--       => Field a b -> (b -> Record c -> b) -> b -> List (Record c) -> List (Record d)
--
-- permuted relative to the shipped `t <- (r, c)` -- while the ETA-DELEGATED
-- `iWithRunning fld step z rows = withRunning fld step z rows` comes back in the
-- shipped order. Which of the two orders the printer picks is not stable across
-- spellings of the same function.

withRunningFull : forall a b c d. d <- (c, a)
               => Field a b -> (b -> {..c} -> b) -> b -> List {..c} -> List {..d}
withRunningFull fld step z rows =
  fst (withState (t -> s -> let s' = step s t in (cons fld s' t, s')) z rows)

withRunningDeduped : forall t r c n. t <- (r, c)
                  => Field c n -> (n -> {..r} -> n) -> n -> List {..r} -> List {..t}
withRunningDeduped = withRunningFull

-- The SPECIALISATION: a running total over a two-column row, written out.
field runTotal : Double

withRunningSimple : List {ledgerRef, ledgerAmt} -> List {ledgerRef, ledgerAmt, runTotal}
withRunningSimple = withRunning runTotal (s t -> s + (t ! ledgerAmt)) 0.0

-- =========================================================== 4. `askField`, and `Has`
--
-- `Constraint.Has a b` is `exists c. a <- (b, c)`, a type SYNONYM, and the interface
-- printer expands it. Both spellings are accepted in a signature, and each entails the
-- other -- which is what the two definitions below prove, in both directions.

askFieldSugar : forall e h a. Has e h => Field h a -> {..e} -> a
askFieldSugar f = (p -> p ! f)

askFieldExpanded : forall e h a. (exists c. e <- (h, c)) => Field h a -> {..e} -> a
askFieldExpanded = askFieldSugar

askFieldBack : forall e h a. Has e h => Field h a -> {..e} -> a
askFieldBack = askFieldExpanded

sugarHolds : Bool
sugarHolds = True          -- proved by the two definitions above compiling

-- The interface form for the eta-delegated `iAskField`, verbatim:
--
--     forall (h: rho) a (e: rho). (exists (c: rho). e <- (c, h))
--       => Field h a -> Record e -> a
--
-- -- note that the expansion of `Has e h` comes back with its two parts the other way
-- round from the way `Constraint.e` writes the synonym. Permuted, and equivalent.
askFieldFull : forall (h: rho) a (e: rho). (exists (c: rho). e <- (c, h))
            => Field h a -> {..e} -> a
askFieldFull f = askField f

askFieldDeduped : forall e h a. Has e h => Field h a -> {..e} -> a
askFieldDeduped = askFieldFull

-- =========================================================== 5. two projections
--
-- Projecting a record TWICE under one row variable is the shape that made E4's most
-- expensive solve. Unannotated,
--
--     jTwoFields f g t = (t ! f, t ! g)
--
-- infers TWO existential partitions over the same whole:
--
--     forall (a: rho) b (c: rho) d (e: rho).
--       (exists (f: rho) (g: rho). e <- (c, g), e <- (a, f))
--       => Field a b -> Field c d -> Record e -> (b, d)
--
-- which is exactly `Has e a, Has e c` after the sugar is folded back up. Note what it
-- is NOT: it does not say the two fields are DISJOINT, so `twoFields x x` is accepted
-- and returns the same value twice.

twoFieldsFull : forall a b c d e. (exists f g. e <- (c, g), e <- (a, f))
             => Field a b -> Field c d -> {..e} -> (b, d)
twoFieldsFull f g t = (t ! f, t ! g)

twoFieldsDeduped : forall r h1 a1 h2 a2. (Has r h1, Has r h2)
                => Field h1 a1 -> Field h2 a2 -> {..r} -> (a1, a2)
twoFieldsDeduped = twoFieldsFull

-- The DISJOINT version, which is a different -- and stronger -- statement.
twoFieldsDisjoint : forall r h1 a1 h2 a2 o. r <- (h1, h2, o)
                 => Field h1 a1 -> Field h2 a2 -> {..r} -> (a1, a2)
twoFieldsDisjoint f g t = (t ! f, t ! g)

sameFieldTwice : (String, String)
sameFieldTwice = twoFieldsDeduped ledgerRef ledgerRef {ledgerRef = "L-1", ledgerAmt = 2.0}

-- =========================================================== 6. specialisations
--
-- Three `xSimple`s: the shipped helper at one applicative, one monad and one monoid.
-- Each body is written out, so checking it proves the body has that type.

traverseRowsAtMaybe : forall r a. ({..r} -> Maybe a) -> List {..r} -> Maybe (List a)
traverseRowsAtMaybe f = traverse_T listTraversable_L maybeAp f

mapMRowsAtState : forall r s a. ({..r} -> State_St s a) -> List {..r}
               -> State_St s (List a)
mapMRowsAtState f = mapM_T listTraversable_L stateMonad_St f

foldRowsAtSum : forall r. ({..r} -> Double) -> List {..r} -> Double
foldRowsAtSum f = foldl_L (acc t -> acc + f t) 0.0

-- =========================================================== 7. what cannot be written
--
-- `Lang/Helpers.e`'s `readRowsAs` publishes
--
--     forall (r: rho). RowReader r -> Row r -> List (List String)
--                   -> Either (List (String, String)) (Relation r)
--
-- with NO residual constraint at all, even though its body traverses with an
-- accumulating applicative and calls `relationWithHeader`. Every partition inside is
-- discharged against `RowReader r`'s own row, which is the point of the type: the
-- reader carries the header, so the caller owes nothing.
--
-- The two things in this group that CANNOT be given a signature are recorded in
-- `tracker/loopmodel/E5-EXAMPLES.md` section 6, not here, because neither has an
-- Ermine spelling to write down.
