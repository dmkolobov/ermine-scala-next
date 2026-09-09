module FfiClassMissing where

-- LSP-FFI kind (1): the class is not on this JVM's classpath at all
-- (ClassNotFoundException).  The warning lands on the class name.
foreign
  function "com.clarifi.reporting.writers.NoSuchWriter" "render" render : String -> String
