module Relation.Op where

-- Op provides expressions built on literals, fields, and combinators
-- like `+`.  It excludes boolean combinators, the domain of
-- `Relation.Predicate`.
--
-- The `combine` relational operator adds a new column based on an
-- `Op` evaluated against other columns in the underlying relation.

export Relation.Op.Type

import Constraint
import Function
import Field using fieldName; existentialF; EField
import List as L
import List.Util using sort
import Maybe
import Native
import Ord using contramap
import Pair
import Prim using String; primExpr#; type PrimExpr#; unsafePrim#
import Relation.Op.Unsafe
import Relation.Row using {type Row; Row}
import String as S
import Syntax.List
import Unsafe.Coerce
import Date

infixr 5 ++
infixl 6 + -
infixl 7 * / //

prim : forall a. Primitive a => a -> Op (| |) a
prim = funcall1# opLiteralModule . primExpr#

col : Field r a -> Op r a
col = asOp

if : forall a r s t v op1 op2. (RUnion3 v r s t,
       AsOp opc, AsOp opa)
   => Predicate r               -- ^ Truth/falsehood.
   -> opc s a                    -- ^ If truth.
   -> opa t a                    -- ^ If falsehood.
   -> Op v a
if p c a = funcall3# ifModule p (asOp c) (asOp a)

private foreign
  function "com.clarifi.reporting.Ops" "coalesce" coalesce# : RUnion r r1 r2 => Op r1 a -> Op r2 a -> Op r a

coalesce : forall opc s a opa t v. (RUnion2 v s t, AsOp opc, AsOp opa)
        => opc s (Nullable a)
        -> opa t a
        -> Op v a
coalesce l r = funcall2# coalesceModule (asOp l) (asOp r)

coalesce' : (RUnion2 r r1 r2, AsOp opc, AsOp opa)
        => opc r1 a
        -> opa r2 a
        -> Op r a
coalesce' l r = coalesce# (asOp l) (asOp r)

cast : (AsOp op) => op s a -> Prim b -> Op s b
cast o p = funcall3# castModule (asOp o) p false#

tryCast : (PrimitiveAtom b, AsOp op) => op s a -> Prim b -> Op s (Nullable b)
tryCast o p = funcall3# castModule (asOp o) (withNull p) true#

type OpBin v = forall a b c opl opr.
               (exists d e f. a <- (e, d), b <- (f, e), c <- (f, e, d),
                       AsOp opl, AsOp opr)
               => opl a v -> opr b v -> Op c v

type OpTri a1 a2 a3 r =
  forall op1 op2 op3 r1 r2 r3 rr.
  (exists r12 r13 r23 r123 r1e r2e r3e
         . r1 <- (r12, r13, r123, r1e)
         , r2 <- (r12, r23, r123, r2e)
         , r3 <- (r13, r23, r123, r3e)
         , rr <- (r12, r13, r23, r123, r1e, r2e, r3e)
         , AsOp op1
         , AsOp op2
         , AsOp op3)
  => op1 r1 a1 -> op2 r2 a2 -> op3 r3 a3 -> Op rr r

(+), (-), (*), (//), (/), pow, logBase : PrimitiveNum n => OpBin n
(+) = opBin $ funcall2# addModule
(-) = opBin $ funcall2# subModule
(*) = opBin $ funcall2# mulModule
(//) = opBin $ funcall2# floorDivModule
(/) = opBin $ funcall2# doubleDivModule
pow = opBin $ builtin2 powBuiltin
logBase = opBin $ builtin2 logBaseBuiltin

log, log10, exp : PrimitiveNum n  => OpUn n
log x = builtin1 logBuiltin (asOp x)
log10 x = builtin1 log10Builtin (asOp x)
exp x = builtin1 expBuiltin (asOp x)

type OpUn v = forall a b op. (exists c. b <- (a, c), AsOp op) => op a v -> Op b v

abs : PrimitivieNum => OpUn n
abs x = builtin1 absBuiltin (asOp x)

upper : AsOp op => op r String -> Op r String 
upper x = builtin1 upperBuiltin (asOp x)

lower : AsOp op => op r String -> Op r String 
lower x = builtin1 lowerBuiltin (asOp x)

replace : OpTri a b c String
replace target replacement x = builtin3 replaceBuiltin (asOp x) (asOp target) (asOp replacement)

negate x = (prim $ Some 0.0 ) - x

fromNumericOp : (PrimitiveNum n, PrimitiveNum n2, AsOp op) => op r n -> Op r n2
fromNumericOp = unsafeCoerce . asOp

annul : (AsOp op, PrimitiveAtom a) => op r a -> Op r (Nullable a)
annul = unsafeCoerce . asOp

(++) : PrimitiveString s => OpBin s
(++) x y = funcall1# concatModule $ UnsafeOp (asOp x) ::# UnsafeOp (asOp y) ::# Nil#

show : PrimitiveString s => AsOp op => op r a -> Op r s
show x = funcall1# concatModule $ UnsafeOp (asOp x) ::# Nil#

-- dateRange : (AsOp o1, AsOp o2) .  r <- (r1,r2) => o1 r1 Date -> o2 r2 Date -> Op r String
dateRange start stop = show start ++ prim " - " ++ show stop

-- sugary Concatting
empty_Bracket = prim ""
cons_Bracket = (++)

combine : forall a c r s t rel.
          (exists o. RUnion2 t r c, r <- (s, o), AsOp op, RelationalComb rel)
          => op s a -> Field c a -> rel r -> rel t
combine op f = combine# f (UnsafeOp $ asOp op)

-- | Op which converts the given field, assumed to be returns, to the growth of 10k
-- Computed as: 10k * (1 + r)
growthOf10k returns = prim (Some 10000.0) * (returns + (prim (Some 1.0))) -- todo: find better home for this

dateAdd : (AsOp op, PrimitiveTemporal d) => Int -> TimeUnit -> op r d -> Op r d
dateAdd n u o = dateAdd# (prim n) u (asOp o)

dateAdd' : (AsOp op1, AsOp op2, RUnion2 t r s, PrimitiveTemporal d) => op1 r Int -> TimeUnit -> op2 s d -> Op t d
dateAdd' n u o = dateAdd# (asOp n) u (asOp o)

--dateDiff : forall r r1 r2 .  AsOp op1 op2 => TimeUnit -> op1 r Date -> op2 r1 Date -> Op r2 Long
dateDiff u s e = dateDiff# u (asOp s) (asOp e)

typeOfOp : AsOp op => op r n -> Prim n
typeOfOp = typeOfOp# . asOp

-- | Default op for a row.  Because the underlying value type isn't
-- known, you can't decide things about it.
foldFromRow : (forall a. Op r a -> z) -> Row r -> z
foldFromRow (f: some r z. forall a. Op r a -> z) (Row cols) =
  case cols of
    [(s, pt)] -> case existentialF s (unsafePrim# pt) of
                   (EField e) -> f (unsafeROp $ asOp e)
    _ -> f (unsafeROp . orElse empty_Bracket
            $ foldr1_L comma (showE <$> (sort (contramap fst ord_S) cols)))
  where unsafeROp : forall s t a. Op s a -> Op t a
        unsafeROp = unsafeCoerce
        showE (s, pt) = case existentialF s (unsafePrim# pt) of
                          (EField e) -> unsafeROp . show $ asOp e
        -- XXX the choice of prim ", " here is totally arbitrary.
        comma l r = [l, prim ", ", r]

private
  opBin : (AsOp opl, AsOp opr) =>
          (Op r a -> Op s b -> z) -> (opl r a -> opr s b -> z)
  opBin f x y = f (asOp x) (asOp y)

foreign function "com.clarifi.reporting.Ops" "dateAdd" dateAdd# : (PrimitiveTemporal d) => Op r Int -> TimeUnit -> Op r1 d -> Op r2 d
foreign function "com.clarifi.reporting.Ops" "dateDiff" dateDiff# : (PrimitiveTemporal d) => TimeUnit -> Op r d -> Op r1 d -> Op r2 Int

weaken : r <- (x,y) => Op x b -> Op r b
weaken = PhantomOp . UnsafeOp

{-
builtin
  class AsOp (a: ρ -> * -> *) where
    asOp : a r b -> Op r b

  instance AsOp Op where
    asOp = id

  instance AsOp Field where
    asOp = col
-}
