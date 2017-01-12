module Relation.Op.Unsafe where

-- These symbols shouldn't be imported by Ermine programs.

import Native
import Prim using type PrimExpr#
import Relation.Op.Type
import Relation.Predicate.Type

-- the constraints here are those from Relation.join
type OpBin# v = forall a b c.
                (exists d e f. a <- (e, d), b <- (f, e), c <- (f, e, d))
                => Function2 (Op a v) (Op b v) (Op c v)

type OpUn# v = forall a b. (exists c. b <- (a, c)) => Function1 (Op a v) (Op b v)

builtin1 : Builtin -> Op r a -> Op s b
builtin1 bi o = funcall2# builtinCallModule bi (UnsafeOp o ::# Nil#)

builtin2 : Builtin -> Op r a -> Op s b -> Op t c
builtin2 bi o1 o2 = funcall2# builtinCallModule bi (UnsafeOp o1 ::# UnsafeOp o2 ::# Nil#)

builtin3 : Builtin -> Op r a -> Op s b -> Op t c -> Op u d
builtin3 bi o1 o2 o3 = funcall2# builtinCallModule bi (UnsafeOp o1 ::# UnsafeOp o2 ::# UnsafeOp o3 ::# Nil#)

foreign
  -- Op erasure
  subtype UnsafeOp : Op r a -> Op#
  subtype PhantomOp : Op# -> Op r a
  -- Op data constructors
  value "com.clarifi.reporting.Op$OpLiteral$" "MODULE$"
      opLiteralModule : Function1 PrimExpr# (Op (| |) a)
  value "com.clarifi.reporting.Op$Add$" "MODULE$"
      addModule : OpBin# a
  value "com.clarifi.reporting.Op$Sub$" "MODULE$"
      subModule : OpBin# a
  value "com.clarifi.reporting.Op$Mul$" "MODULE$"
      mulModule : OpBin# a
  value "com.clarifi.reporting.Op$FloorDiv$" "MODULE$"
      floorDivModule : OpBin# a
  value "com.clarifi.reporting.Op$DoubleDiv$" "MODULE$"
      doubleDivModule : OpBin# a
  value "com.clarifi.reporting.Op$Concat$" "MODULE$"
      concatModule : Function1 (List# Op#) (Op r a)
  value "com.clarifi.reporting.Op$If$" "MODULE$"
      ifModule : Function3 (Predicate r) (Op s a) (Op t a) (Op u a)
  value "com.clarifi.reporting.Op$Coalesce$" "MODULE$"
      coalesceModule : Function2 (Op s (Nullable a)) (Op t a) (Op u a)
  value "com.clarifi.reporting.Op$Funcall$" "MODULE$"
      funcallModule : Function5 String String (List# String) (List# Op#) (Prim a) (Op r a)
  value "com.clarifi.reporting.Op$BuiltinCall$" "MODULE$"
      builtinCallModule : Function2 Builtin (List# Op#) (Op r a)
  value "com.clarifi.reporting.Op$Cast$" "MODULE$"
      castModule : Function3 (Op s a) (Prim b) Bool# (Op s b)

  method "guessTypeUnsafe" typeOfOp# : Op r a -> Prim a

  data "com.clarifi.reporting.Op$Builtin" Builtin

  value "com.clarifi.reporting.Op$Upper$" "MODULE$" upperBuiltin : Builtin
  value "com.clarifi.reporting.Op$Lower$" "MODULE$" lowerBuiltin : Builtin
  value "com.clarifi.reporting.Op$Log$" "MODULE$" logBuiltin : Builtin
  value "com.clarifi.reporting.Op$Log10$" "MODULE$" log10Builtin : Builtin
  value "com.clarifi.reporting.Op$LogBase$" "MODULE$" logBaseBuiltin : Builtin
  value "com.clarifi.reporting.Op$Exp$" "MODULE$" expBuiltin : Builtin
  value "com.clarifi.reporting.Op$Abs$" "MODULE$" absBuiltin : Builtin
  value "com.clarifi.reporting.Op$Pow$" "MODULE$" powBuiltin : Builtin
  value "com.clarifi.reporting.Op$Replace$" "MODULE$" replaceBuiltin: Builtin

-- builtin
--   data "com.clarifi.reporting.Op" Op#
--   combine# : Field r a -> Op# -> [..s] -> [..t]
