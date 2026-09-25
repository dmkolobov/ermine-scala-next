module Layout.Trace.Connection where

import Json using type Json; type Spread

-- A render trace's `connection`: `kind` is "in-memory" or "profile".  It
-- never carries a url, user, host or password.  The server's `database` key
-- cannot be a field (`database` is an Ermine keyword), so `connectionMore`
-- is a `Spread Json` that gathers it; Layout.Trace reads it from there.

data TraceConnection = TraceConnection { kind           : String
                                       , dialect        : String
                                       , profile        : Maybe String
                                       , connectionMore : Spread Json }
