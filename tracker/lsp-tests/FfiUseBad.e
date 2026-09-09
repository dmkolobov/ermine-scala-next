module FfiUseBad where

-- The stub is bound at its DECLARED type, so misusing it is still a
-- type error at the use site -- one, here, not a dead module.
import FfiClassMissing

oops : String
oops = render 42
