module FfiWriter where

-- The fork's writer-trait shape: an opaque writer parameterised by its
-- effect, a factory function that hands one out, and instance methods
-- on it.  None of these classes exist on this JVM, so the two term
-- declarations warn and the `data` does not -- and the Ermine code
-- around them checks normally.
foreign
  data "com.clarifi.reporting.writers.MissingWriter" Writer# (f : * -> *) a

  function "com.clarifi.reporting.writers.MissingCsvWriter" "csvWriter"
    csvWriter : Writer# f a

  method "render" render# : Writer# f a -> String -> String

renderWith : Writer# f a -> String -> String
renderWith w s = render# w s

csv : String -> String
csv = renderWith csvWriter
