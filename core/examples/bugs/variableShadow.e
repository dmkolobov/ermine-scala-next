-- this fails because fmt in the definition of foo isn't allowed
-- to shadow fmt in the global scope.
-- Load this file (i.e. into the repl using import) in order to see the bug.
module Foo where
import Layout
foo fmt = 1
