module Layout.Trace.Query where

import Layout.Trace.Setup using type TraceSetup

-- One `queries[]` entry of a render trace: one relation, in execution order
-- (tracker/db/OBSERVABILITY.md section 4, the keys lsp/TraceJson.scala
-- emits, in its order).  `Maybe` fields are keys the server leaves out:
-- `dialect`, `sql`, `sqlBytes`, `statements` when no SQL ran, `setup` when
-- empty, `fetchMs` when the A/B drops it, and the three flags.  Counts are
-- Int: the server prints them as JSON numbers with no fraction.

data TraceQuery = TraceQuery { path          : String
                             , delivery      : String
                             , dialect       : Maybe String
                             , sql           : Maybe String
                             , sqlBytes      : Maybe Int
                             , statements    : Maybe Int
                             , setup         : Maybe (List TraceSetup)
                             , sqlEmitMs     : Double
                             , execMs        : Double
                             , fetchMs       : Maybe Double
                             , dbMs          : Double
                             , ms            : Double
                             , rowsRead      : Int
                             , rows          : Int
                             , scanned       : Int
                             , columns       : Int
                             , bytes         : Int
                             , deferred      : Bool
                             , overThreshold : Maybe Bool
                             , error         : Maybe Bool
                             , message       : Maybe String }
