
-- This file gets overridden in bridge with a custom
-- loader to import the real security master implementation.
module Internal.SMEnv where

import DB
import IO.Unsafe

foreign
  data "com.clarifi.reporting.relational.SMEnv" SMEnv (f : * -> *)
  function "com.clarifi.reporting.relational.SMEnv" "dummySmenv" smEnv : IO (SMEnv DB)

cachedSMEnv = unsafePerformIO smEnv
