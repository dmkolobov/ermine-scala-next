module FfiSubtype where

-- LSP-FFI kind (8): a subtype claim over a foreign type with no backing
-- class.  The `data` itself is silent (it is a fine opaque type); the
-- claim cannot be checked against anything, so IT is what warns.
foreign
  data "com.clarifi.reporting.writers.NoSuchBase" Base#
  subtype up : String -> Base#
