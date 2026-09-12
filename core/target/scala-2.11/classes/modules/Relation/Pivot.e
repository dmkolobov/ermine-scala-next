
module Relation.Pivot where

import Control.Functor
import Field
import Function
import List
import Map
import Native.List using toList#; fromList#
import Native.Pair
import Native.Record
import Pair
import Relation.Op hiding empty_Bracket ; cons_Bracket ; (++)
import Prim
import Date
import GUID
import Record hiding (++)
import Relation.Op.Unsafe
import Relation.Row hiding empty_Bracket ; cons_Bracket ; single_Brace ; snoc_Brace
import Layout.Presentation using rowUsed

-- XXX should a Fulcrum have a Prim# for each field?  Should the Record# and/or Op# just be Record and/or Op?

data Fulcrum k v p = Fulcrum (List String) -- field names of key row
                             (List String) -- field names of value row
                             (List (Record#, -- filters the overall relation to just the rows that should have this new field
                                     (String, -- name of new field
                                      Op#)))  -- op to apply to each row to get the value of the field

data FulcrumWithDefault k v p = FulcrumWithDefault (List String) -- field names of key row
                                        (List String) -- field names of value row
                                        (List (Record#, -- filters the overall relation to just the rows that should have this new field
                                               (String, -- name of new field
                                                Op#,  -- op to apply to each row to get the value of the field
                                                PrimExpr#))) -- default Value if not present.

-- | defaultFulcrum {fld} valFld keyFld  is equivalent to {(fld1, asOp valFld, {keyField = fieldName fld)}
defaultFulcrum : Row p -> Field v a -> Field k String -> Fulcrum k v p
defaultFulcrum (Row p) val key = 
  Fulcrum ([fieldName key])
          ([fieldName val])
          (map_List ((fname,ftype) -> (record# {key = fname}, (fname, UnsafeOp $ asOp val))) p)
defaultFulcrumWithDefault : Row p -> Field v a -> Field k String -> FulcrumWithDefault k v p
defaultFulcrumWithDefault (Row p) val key =
  FulcrumWithDefault ([fieldName key])
                     ([fieldName val])
                     (map_List ((fname,ftype) -> (record# {key = fname}, (fname, UnsafeOp $ asOp val, defaultValue ftype))) p)


defaultValue t = primCata
  0 (Some 0)
  "" (Some "")
  True (Null Bool)
  0.0 (Some 0.0)
  0b (Some 0b)
  0s (Some 0s)
  0l (Some 0l)
  (yyyymmdd 1970 1 1) (Null Date)
  (stringGuid "00000000-0000-0000-0000-000000000000") (Null GUID)
  (timestampFromLong 0l) (Null Timestamp)
  t

single_Brace : (Field p a, Op v a, {..k}) -> Fulcrum k v p
single_Brace (f, op, k) = Fulcrum (map_List fst ks) (map_List fst vs) [(record# k, (fieldName f, UnsafeOp op))]
 where
 vs = case rowUsed op of Row x -> x
 ks = case header k of Row x -> x

single_Brace_ = single_Brace

snoc_Brace : (p' <- (p, f), RUnion2 v3 v2 v1)
          => Fulcrum k v1 p
          -> (Field f a, Op v2 a, {..k})
          -> Fulcrum k v3 p'
snoc_Brace (Fulcrum ks vs m) (f, o, k) = Fulcrum ks (vs ++ vs') ((record# k, (fieldName f, UnsafeOp o)) :: m)
 where
 vs' = case rowUsed o of Row x -> map_List fst x

snoc_Brace_ = snoc_Brace

nilFulcrum' : Row k -> Fulcrum k (||) (||)
nilFulcrum' (Row ks) = Fulcrum (map_List fst ks) [] []

nilFulcrum : Row k -> Row v -> Fulcrum k v (||)
nilFulcrum (Row ks) (Row vs) = Fulcrum (map_List fst ks) (map_List fst vs) []

consFulcrum : (p' <- (f, p), RUnion2 v3 v2 v1) => Field f a -> Op v1 a -> {..k} -> Fulcrum k v2 p -> Fulcrum k v3 p'
consFulcrum f o r (Fulcrum ks vs m) = Fulcrum ks (vs ++ vs') ((record# r, (fieldName f, UnsafeOp o)) :: m)
 where
 vs' = case rowUsed o of Row x -> map_List fst x

catFulcrum : (p <- (p1, p2), RUnion2 v3 v2 v1)
          => Fulcrum k v1 p1
          -> Fulcrum k v2 p2
          -> Fulcrum k v3 p
catFulcrum (Fulcrum ks vs l1) (Fulcrum _ vs' l2) = Fulcrum ks (vs ++ vs') (l1 ++ l2)

mapFulcrum : (forall f r a. Field f a -> Op r a -> {..k} -> (Op r a, {..k})) -> Fulcrum k v p -> Fulcrum k v p
mapFulcrum (g: some k v. forall f r a. Field f a -> Op r a -> {..k} -> (Op r a, {..k})) (Fulcrum ks vs l) = Fulcrum ks vs $
  map_List ((r,(n,o)) -> case o of
              UnsafeOp o1 -> case existentialF n (typeOfOp o1) of
                EField f -> case g f o1 $ unsafeRecordIn# r of
                  (PhantomOp o2, r2) -> (record# r2,(n,o2)))
           l

mapFulcrumKeys : ({..k} -> {..k}) -> Fulcrum k v p -> Fulcrum k v p
mapFulcrumKeys (g : some k. {..k} -> {..k}) (Fulcrum ks vs l) = Fulcrum ks vs $
  map_List ((r,(n,o)) -> (record# . g . unsafeRecordIn# $ r,(n,o))) l

pivot : (RelationalComb rel, r <- (k, v, i), s <- (i, p)) => Fulcrum k v p -> rel r -> rel s
pivot (Fulcrum ks vs m) = pivot# (toList# ks) (toList# vs) (toList# m')
 where m' = map_List $ ((r,(s,op)) -> pair# $ scalaRecord# r $ (pair# s $ pair# op (primExpr# $ Null Double)))  $ m

pivotWithDefault : (RelationalComb rel, r <- (k, v, i), s <- (i, p)) => FulcrumWithDefault k v p -> rel r -> rel s
pivotWithDefault (FulcrumWithDefault ks vs m) = pivot# (toList# ks) (toList# vs) (toList# m')
 where m' = map_List $ ((r,(s,op,pe)) -> pair# (scalaRecord# r) (pair# s (pair# op pe))) $ m


