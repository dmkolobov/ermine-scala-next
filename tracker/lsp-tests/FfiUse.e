module FfiUse where

-- A module that IMPORTS a stubbed binding and uses it well-typed: the
-- warning stays on the declaration's own file, and this one is clean.
import FfiClassMissing

greet : String
greet = render "hello"
