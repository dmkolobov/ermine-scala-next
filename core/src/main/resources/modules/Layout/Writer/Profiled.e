module Layout.Writer.Profiled where

import Layout.Writer using type Writer
import Scanners using type Scanner
import Runners using type Runner

private foreign
  data "com.clarifi.reporting.writers.ProfiledWriter$" ProfiledWriterModule
  value "com.clarifi.reporting.writers.ProfiledWriter$" "MODULE$"
    profiledWriterModule : ProfiledWriterModule
  method "logging" logging# : forall f c. ProfiledWriterModule
                                       -> Writer f c -> Runner f
                                       -> Writer f c

private type WriterCtor f c = Scanner f -> Runner f -> Writer f c

withProfiling : WriterCtor f c -> WriterCtor f c
withProfiling ct s r = logging# profiledWriterModule (ct s r) r
