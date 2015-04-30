module Validation where

import Map
import Either
import List as List
import Field using cons; fieldName
import Parse
import Control.Functor using fmap
import Native.Object using toString
import Nullable using toMaybe
import Function
import Maybe
import String as String

type FormValidator r = Map String String -> Either (List Err) {..r}
type Err = (String, String)
type Validator a b = a -> Either String b

validate : FormValidator r -> Map String String -> Either (List Err) {..r}
validate = id

nilV : FormValidator (| |)
nilV _ = Right {}

consV : (t <- (r,s)) => Field r a -> Validator (Maybe String) a -> FormValidator s -> FormValidator t
consV fld fn vs env = combineErrors (cons fld) (fieldName fld) (fn (lookup (fieldName fld) env)) (vs env)

-- I'm not wild about exposing any of Validator's variance, really.
-- So there are no combinators for it, and 'arr' is private to this
-- module. -SMRC

-- | Always produce 'b'. (Applicative unit)
always : b -> Validator a b
always = const . Right

-- | Pass through the value as success. (Category id)
pass : Validator a a
pass = arr id

-- | Wrap 'a' in 'Some'.
someify : Validator a (Nullable a)
someify = arr Some

-- | Separate null from non-null.
unnullify : Validator (Nullable a) (Either () a)
unnullify = arr (maybeEither () . toMaybe)

-- | Choose based on input.  (Category |||)
choice : Validator a c -> Validator b c -> Validator (Either a b) c
choice = either

-- | Fallback on right if left fails.  (lifted mplus, satisfies Left
-- Catch)
orTry : Validator a b -> Validator a b -> Validator a b
orTry f g a = orEither (f a) (g a)

-- | Forgive failure.
forgive : Validator a b -> Validator a (Either String b)
forgive = arr

combineErrors : (a -> b -> c) -> String -> Either String a -> Either (List Err) b -> Either (List Err) c
combineErrors f n (Right a) (Right b) = Right (f a b)
combineErrors _ n (Left  a) (Left  b) = Left ((n,a)::b)
combineErrors _ n (Left  a)  _        = Left [(n,a)]_List
combineErrors _ n _         (Left  b) = Left b

empty_Bracket = nilV
cons_Bracket (f, v) = consV f v

-- validator library

lookupForm : Validator (Maybe String) String
lookupForm = maybe (Left "Value not found") Right

validateInt    : Validator String Int
validateInt    = validateIntM "Bad Int"
validateDouble : Validator String Double
validateDouble = validateDoubleM "Bad Double"
validateBool   : Validator String Bool
validateBool   = validateBoolM "Bad Bool"

validateIntM             : String -> Validator String Int
validateIntM errorMsg    = maybe (Left errorMsg) Right . parseInt 10
validateDoubleM          : String -> Validator String Double
validateDoubleM errorMsg = maybe (Left errorMsg) Right . parseDouble
validateBoolM            : String -> Validator String Bool
validateBoolM errorMsg   = maybe (Left errorMsg) Right . parseBool

composeValidators : Validator a b -> Validator b c -> Validator a c
composeValidators vab vbc a = either Left vbc $ vab a

infixl 5 >=>
(>=>) x y = composeValidators x y

--type Validator a b = a -> Either String b
--lookupInt : Maybe String -> Either String Int
lookupInt : Validator (Maybe String) Int
lookupInt    = lookupForm >=> validateInt
lookupDouble = lookupForm >=> validateDouble
lookupBool   = lookupForm >=> validateBool
lookupString = lookupForm
lookupStringDef : String -> Validator (Maybe String) String
lookupStringDef def = maybe (Right def) Right

within : List b -> (b -> b -> Bool) -> Validator a b -> Validator a b
within bs pred vab a =
  let errmsg = "couldn't find " ++_String (toString a) ++_String " in " ++_String (toString bs)
      existsb b = find_List (pred b) bs
      checkWithin = maybe (Left errmsg) Right . existsb
  in either Left checkWithin $ vab a

private
  arr : (a -> b) -> Validator a b
  arr = (.) Right
