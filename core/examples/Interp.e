module Interp where

import Control.Monad
import Either
import Syntax.Either as EitherS
import Maybe
import Syntax.Maybe as MaybeS
import String
import List
import Pair
import Error
import Control.Monad.Id
import Control.Monad.Error
import Control.Monad.Reader

-- types used in the interpreters

type Op = Int -> Int -> Int
type Env = List (String, Int)
data Exp = ValE Int | OpE Op Exp Exp | IdE String | LetE String Exp Exp

-- Some helper functions used in the interpreters

lookup k env = find (z -> k == (fst z)) env
lookupOrBust k env = snd (orElse (error ("not found: " ++ k)) (lookup k env))
lookupWithM : Monad m -> String -> List (String, v) -> ErrorT String m v
lookupWithM m k env = case (lookup k env) of
  Nothing -> (fail m ("not found: " ++ k))
  Just (k,v) -> success m v

-- INITIAL INTERPRETER

eval : Exp -> Env -> Int
eval (ValE i) e = i
eval (OpE o e1 e2) e = o (eval e1 e) (eval e2 e)
eval (IdE s) e = lookupOrBust s e
eval (LetE s e1 e2) e = eval e2 ((s, eval e1 e) :: e)

-- INTERPRETER RUNNING IN THE Id Monad

eval1 : Exp -> Env -> Id Int
eval1 (ValE i) e = unit idMonad i
eval1 (OpE o e1 e2) e = liftA2 idAp o (eval1 e1 e) (eval1 e2 e)
eval1 (IdE s) e = unit idMonad (lookupOrBust s e)
eval1 (LetE s e1 e2) e = bind idMonad (eval1 e1 e) (v -> eval1 e2 ((s, v) :: e))

-- eval1 : Exp -> Env -> Either String Int
-- eval1 (ValE i) e = Right i
-- eval1 (OpE o e1 e2) e = liftA2 eitherAp o (eval1 e1 e) (eval1 e2 e)
-- eval1 (IdE s) e = maybeEither ("not found " ++ s) (map_MaybeS snd (lookup s e))
-- eval1 (LetE s e1 e2) e = (eval1 e1 e) >>=_EitherS (v -> eval1 e2 ((s, v) :: e))

-- INTERPRETER RUNNING IN ANY Monad

eval1G : Monad m -> Exp -> Env -> m Int
eval1G m exp env = let
    eval1G' (ValE i) e = unit m i
    eval1G' (OpE o e1 e2) e = liftA2 (monadAp m) o (eval1G' e1 e) (eval1G' e2 e)
    eval1G' (IdE s) e = unit m (lookupOrBust s e)
    eval1G' (LetE s e1 e2) e = bind m (eval1G' e1 e) (v -> eval1G' e2 ((s, v) :: e))
  in eval1G' exp env

-- ADDING ERROR HANDLING (Still running in any Monad)

type Eval2 a = ErrorT String a Int
runEval2 : Eval2 m -> m (Either String Int)
runEval2 ev = runErrorT ev

eval2 : Monad m -> Exp -> Env -> Eval2 m
eval2 innerM exp env = let
    m = errorTMonad innerM
    eval2' (ValE i) e = unit m i
    eval2' (OpE o e1 e2) e =
      bind m (eval2' e1 e) (e1' -> bind m (eval2' e2 e) (e2' -> unit m (o e1' e2')))
    eval2' (IdE s) e = lookupWithM innerM s e
    eval2' (LetE s e1 e2) e = bind m (eval2' e1 e) (v -> eval2' e2 ((s, v) :: e))
  in (eval2' exp env)

type Eval3 m = ReaderT Env (ErrorT String m) Int
runEval3 : Env -> Eval3 m -> m (Either String Int)
runEval3 env ev = runErrorT (runReaderT ev env)

eval3 : Monad m -> Exp -> Eval3 m
eval3 innerM exp = let
    et = errorTMonad innerM
    mt = readerTMonad et
    eval3' (ValE i) = unit mt i
    eval3' (IdE s) = ReaderT (e -> lookupWithM innerM s e)
    -- TODO ... use ask or askT here? cant get it to work.
    -- eval3' (IdE s) = bind mt (askT mt) (e -> lookupWithM innerM s e)
    eval3' (OpE o e1 e2) =
      bind mt (eval3' e1) (e1' -> bind mt (eval3' e2) (e2' -> unit mt (o e1' e2')))
    eval3' (LetE s e1 e2) = bind mt (eval3' e1) (v -> localT ((::) (s, v)) (eval3' e2))
  in (eval3' exp)

-- type Eval4 m = ReaderT Env (ErrorT String (StateT Int m)) a
