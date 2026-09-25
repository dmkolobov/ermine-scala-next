module Layout.Trace.Setup where

import Json using type Json; type Spread

-- One `queries[].setup[]` entry of a render trace (tracker/db/OBSERVABILITY.md
-- section 4).  The server's `table` key cannot be a field: `table` is an
-- Ermine keyword.  `setupMore` is a `Spread Json`, so the decoder gathers
-- `table` (and nothing else the server sends today) into it, and
-- Layout.Trace reads it from there.

data TraceSetup = TraceSetup { kind      : String
                             , created   : Maybe Bool
                             , ms        : Double
                             , error     : Maybe Bool
                             , setupMore : Spread Json }
