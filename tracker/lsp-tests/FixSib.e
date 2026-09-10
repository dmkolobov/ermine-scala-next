module FixSib where

-- An open sibling that DECLARES a name the stdlib also exports, so
-- `catMaybes` in Fix.e has two candidate modules: this buffer and Maybe.
catMaybes = 2

sibValue = 1
