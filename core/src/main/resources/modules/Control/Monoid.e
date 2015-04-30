module Control.Monoid where

data Monoid m = Monoid m (m -> m -> m)

mempty : Monoid m -> m
mempty (Monoid m _) = m

mappend : Monoid m -> m -> m -> m
mappend (Monoid _ p) = p

mproduct : Monoid m -> Monoid n -> Monoid (m, n)
mproduct m n = Monoid (mempty m, mempty n)
                      (~(m1, n1) ~(m2, n2) -> (mappend m m1 m2, mappend n n1 n2))

mproduct3 m n o = Monoid (mempty m, mempty n, mempty o)
                         (~(m1, n1, o1) ~(m2, n2, o2) -> (mappend m m1 m2, mappend n n1 n2, mappend o o1 o2))

-- sum = Monoid 0 (+)
-- product = Monoid 1 (*)
