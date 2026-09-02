module Decls where

import Prelude
import Either
import Date

infixl 6 <+>
(<+>) x y = x + y

field fa, fb : Int

data Shape a = Circle a | Square a a

type Alias a = Shape a

useOp = 1 <+> 2
useFa = fa
useCircle = Circle 1
useImported = Left 1
useForeign = yyyymmdd 1970 1 1
useAlias : Alias Int
useAlias = Circle 1
useEither : Either Int String
useEither = Left 2
