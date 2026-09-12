module Shouldfail.Control09 where

-- MUST LOAD. Control for let01..let05 (error class 7, LET SIGNATURE): the same five
-- shapes, each with a signature its body satisfies. If this stops loading, the five
-- negatives next door are no longer evidence that the SIGNATURE is what refuses them.
--
-- Shape by shape: a monomorphic `let` signature applied at its own type (let01); a
-- signed `where` inside a `let` block, applied at its own type (let02); a signed `let`
-- inside a `where` body (let03); a `let` signature as general as its body really is,
-- which is the polymorphic identity rather than `a -> Int` (let04); and a signature
-- that HAS its equation in the same block (let05).

import Prelude

okLet : Int
okLet =
  let sameInt : Int -> Int
      sameInt q = q
  in sameInt 41

okWhereInLet : Int
okWhereInLet =
  let outer y = inner y
        where inner : Int -> Int
              inner q = q
  in outer 41

okLetInWhere : Int
okLetInWhere = outer 41
  where outer y =
          let inner : Int -> Int
              inner q = q
          in inner y

okGeneral : Int
okGeneral =
  let general : forall a. a -> a
      general x = x
  in general 41

okDefined : Int
okDefined =
  let defined : Int -> Int
      defined q = q + 1
  in defined 41
