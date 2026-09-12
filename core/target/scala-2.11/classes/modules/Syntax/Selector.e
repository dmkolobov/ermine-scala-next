module Syntax.Selector where

import Control.Ap
import Layout.Report

infixl 4 <*> <$ <$>

return = pure selectorAp

(<*>) : forall f z a b. Selector f z (a -> b) -> Selector f z a -> Selector f z b
(<*>) = ap selectorAp

(<$) : forall f z a b. b -> Selector f z a -> Selector f z b
(<$) b ma = (_ -> b) <$> ma

(<$>) : forall f z a b. (a -> b) -> Selector f z a -> Selector f z b
(<$>) = fmap selectorFunctor
