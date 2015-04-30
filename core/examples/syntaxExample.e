-- Example of using Syntax.X to get a monomorphic monad.
-- Useful until typeclasses are actually implemented.
module SyntaxExample where

import Prelude
import Syntax.Maybe

foo x = Just x
baz y = Just y

ex1 = Just 1 >>= foo >>= baz
ex2 = Nothing >>= foo >>= baz
