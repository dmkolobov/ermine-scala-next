module RootOnly where

-- STALENESS step 1 fixture: a module that exists ONLY under a source root
-- (tracker/lsp-tests/roots/), given to the server as initializationOptions.moduleRoots.
-- The fixture directory's sibling loader does not look here and the classpath has
-- no such module, so `import RootOnly` resolves through the root or not at all.

fromRoot : Int
fromRoot = 7
