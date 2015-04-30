module Syntax.DoTest where

import Bool
import Primitive
import List
import Function
import Native.Object            -- == for Ints
import String using stringMonoid
import Control.Functor
import Control.Monoid
import Syntax.Do
import Eq

-- No Eq, so wiring here.
eqList _ [] [] = True
eqList eqe (x :: xs) (y :: ys) = eqe x y && eqList eqe xs ys
eqList _ _ _ = False
eqPair eqa eqb (a, b) (a', b') = eqa a a' && eqb b b'
eqInt = (==)

-- No show, so wiring here.
showList showe elts = stringConcat $
    "[" :: (interpose ", " $ fmap listFunctor showe elts) ++ ["]"]
showPair showa showb (a, b) =
    stringConcat ["(", showa a, ", ", showb b, ")"]
showInt = toString

-- Insert J between the list's elements.
interpose _ Nil = Nil
interpose j (x :: xs) = x :: concatMap (e -> [j, e]) xs

stringConcat = foldl (mappend stringMonoid) ""

-- Test equality and answer an error-list.
isEqual : (a -> a -> Bool) -> (a -> String) -> String -> a -> a -> List String
isEqual eqtc show what ex ac =
  if (eqtc ex ac) []
    [stringConcat [what, " yielded ", show ac, ", not ", show ex]]

-- What I usually test.
isEqualIL = isEqual (eqList eqInt) (showList showInt)
isEqualITL = isEqual (eqList $ eqPair eqInt eqInt) (showList $ showPair showInt showInt)

infixr 1 #
(#) = flip ($)

-- The module functions.

basicUnit = isEqual (eqList $ eqList eqInt) (showList $ showList showInt)
            "unit" [[42]] (unit [42] listMonad)

basicBind = isEqualIL "bind" [4, 6, 5, 7]
                    (bind (liftDo [1, 2]) (x -> liftDo [x + 3, x + 5]) listMonad)

liftDoRT = isEqualIL "liftDo" [33, 66] (liftDo [33, 66] listMonad)

-- do-syntax.

doId = isEqual eqInt showInt "do id" 42 (do id 42)

doSimple = isEqualIL "do simple" [42] $ listMonad # do
  x <- liftDo [42]
  unit x

doGuardedTrue = isEqualIL "do guarded true" [42] $ listMonad # do
  x <- liftDo [42]
  unit ()
  unit x

doGuardedFalse = isEqualIL "do guarded true" [] $ listMonad # do
  x <- liftDo [42]
  liftDo []
  unit x

doNum = isEqual eqInt showInt "num parse" 33 $ do 33

-- multiple binding

doSequence = isEqualITL "sequence right" [(1, 3), (1, 4), (2, 3), (2, 4)]
             $ listMonad # do
  x <- liftDo [1, 2]
  y <- liftDo [3, 4]
  unit (x, y)

myLiftM2 f x y = do
  x <- x
  y <- y
  unit (f x y)

tryMyLiftM2 = isEqualITL "monad-generic" [(3, 1), (4, 1), (3, 2), (4, 2)]
              $ listMonad #
              myLiftM2 (x -> y -> (y, x)) (liftDo [1, 2]) (liftDo [3, 4])

-- edge cases

-- Don't define laterReverse until after actionFreeRefs.
actionFreeRefs = isEqualIL "free refs in action" [7, 6] $ listMonad # do
  x <- liftDo $ laterReverse [1, 2]
  unit (x + 5)
laterReverse = reverse

-- driver

testMain = concat [-- module functions
                   basicUnit, basicBind, liftDoRT,
                   -- do-syntax
                   doId, doSimple, doGuardedTrue, doGuardedFalse,
                   -- multiple binding
                   doNum, doSequence, tryMyLiftM2,
                   -- edge cases
                   actionFreeRefs]
