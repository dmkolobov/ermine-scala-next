module PrimitiveTest where

import Eq
import Function
import List
import Native.Bool
import Native.List
import Primitive
import Prim using Int
import Syntax.List

t2x2 two = ([two + two, two - two, two * two, two / two, neg two,
             abs two, pow two two],
            two < two, two <= two, two > two, two >= two)

-- | With the last results, all monomorphic.
allResults numeric = (numeric, False, True, False, True)
intResults = [4, 0, 4, 1, neg 2,
              2, 4]
byteResults = [4B, 0B, 4B, 1B, neg 2B,
               2B, 4B]
shortResults = [4S, 0S, 4S, 1S, neg 2S,
                2S, 4S]
longResults = [4L, 0L, 4L, 1L, neg 2L,
               2L, 4L]
{- XXX float not in Num
floatResults = [4.0F, 0.0F, 4.0F, 1.0F, neg 2.0F,
                2.0F, 4.0F]
-}
doubleResults = [4.0, 0.0, 4.0, 1.0, neg 2.0,
                 2.0, 4.0]
someResults = Some <$> intResults
nullResults = take 7 . repeat $ Null Int

testMain = [allResults intResults == t2x2 2,
            allResults byteResults == t2x2 2B,
            allResults shortResults == t2x2 2S,
            allResults longResults == t2x2 2L,
            -- XXX float not in Num
            -- allResults floatResults == t2x2 2.0F,
            allResults doubleResults == t2x2 2.0,
            allResults someResults == t2x2 (Some 2),
            allResults nullResults == t2x2 (Null Int),
            Null Int == Null Int + Some 42]

testMainNative# : List# Bool#
testMainNative# = toList# (toBool# <$> testMain)
