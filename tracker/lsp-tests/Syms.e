module Syms where

import Prelude

infixl 6 <^>

type SymName = SymBox String

data SymColor = SymRed | SymGreen | SymBlue

data SymBox a = SymBox a

field symLabel : String

symNullary = 3

(<^>) x y = x + y

symBoth, symAlsoBoth : Int
symBoth = 1
symAlsoBoth = 2

private
  symHelper : Int -> Int
  symHelper n = n + 1

foreign
  data "java.io.File" SymFile
  constructor symFile# : String -> SymFile
  method "getName" symName# : SymFile -> String

private foreign
  method "getPath" symPath# : SymFile -> String
