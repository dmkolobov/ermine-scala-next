module Layout.Report.StyleGrid where

import Native

private foreign 
	data "com.clarifi.reporting.writers.StyleList" StyleList# (a: *)
	data "com.clarifi.reporting.writers.StyleGrid" StyleGrid# (a: *) -- a is for the type paramter

    value "com.clarifi.reporting.writers.StyleList$" "MODULE$"
      styleListModule : Function1 (List# (Pair# (Maybe# String) (a))) (StyleList# a)

    value "com.clarifi.reporting.writers.StyleGrid$" "MODULE$"
      styleGridModule : Function1 (StyleList# (StyleList# a)) (StyleGrid# a)
