-- This used to fail: fmt in the definition of foo was not allowed to shadow
-- the fmt exported by Layout ("error: pattern variable shadows global
-- binding Layout.fmt"). Fixed: binders (pattern variables, lambda, case,
-- let and where bindings) may now shadow imports and enclosing binders.
-- This file is kept as a regression check: it is loaded by
-- tracker/repl-tests/scoping.in, and the behaviour is covered by the
-- "Ermine scoping" properties in scalacheck-binding/src/main/scala/TestScopes.scala.
module Foo where
import Layout
foo fmt = 1
