module FfiClassUnloadable where

-- LSP-FFI kind (2): the class IS on the classpath, but its SUPERCLASS is
-- not, so loading it throws NoClassDefFoundError -- an Error, and
-- `catch { case e: Exception }` used to let it escape uncaught.
-- `probejar` is built from tracker/lsp-tests/jsrc by
-- tracker/tools/build-probejar.sh, which compiles `Missing` and then
-- deletes it: no third-party library can silence this fixture.
foreign
  function "probejar.PresentSuper" "shout" shout : String -> String
