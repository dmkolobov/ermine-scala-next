module FfiDataNeeded where

-- LSP-FFI kind (9), the site that NEEDS the class: the receiver type of
-- a `foreign method` is where the reflective lookup starts, so the
-- warning is on the member and names the class that is missing.
foreign
  data "com.clarifi.reporting.writers.NoSuchOpaque" Opaque
  method "render" renderOpaque : Opaque -> String
