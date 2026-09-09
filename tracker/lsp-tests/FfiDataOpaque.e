module FfiDataOpaque where

-- LSP-FFI kind (9), the silent case: a `foreign data` of a missing class
-- is a perfectly good OPAQUE type.  Declaring it, naming it in a
-- signature and passing it around need no class, so nothing warns.
foreign
  data "com.clarifi.reporting.writers.NoSuchOpaque" Opaque

keep : Opaque -> Opaque
keep o = o

first : Opaque -> Opaque -> Opaque
first a b = a
