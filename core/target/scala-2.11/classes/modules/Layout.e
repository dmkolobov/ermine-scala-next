module Layout where

export Layout.Chart
export Layout.Report
export Layout.Color
export Layout.Report.Atomic
export Layout.Writer
import Syntax.IO
import Function
import Internal.SMEnv
import DB
import Scanners using { type Scanner }
import Runners using { type Runner; run }

harness : (SMEnv DB -> Scanner f) -> Runner f -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO ()
harness backend runner f report =
  smEnv >>= (smE -> (let writer = f (backend $ smE) runner
                       in run runner (runReport writer report) >>= runW writer))

harness' : (SMEnv DB -> Scanner f) -> Runner f -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO z
harness' backend runner f report =
  smEnv >>= (smE -> (let writer = f (backend $ smE) runner
                      in run runner (runReport writer report)))

harnessNoSM : (SMEnv DB -> Scanner f) -> Runner f -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO ()
harnessNoSM backend runner f report =
  let writer = f (backend $ cachedSMEnv) runner
                       in run runner (runReport writer report) >>= runW writer

harnessNoSM' : (SMEnv DB -> Scanner f) -> Runner f -> (Scanner f -> Runner f -> Writer f z) -> Report f z -> IO z
harnessNoSM' backend runner f report =
  let writer = f (backend $ cachedSMEnv) runner
    in run runner (runReport writer report)
