module Layout.Trace.Totals where

-- A render trace's `totals` (tracker/db/OBSERVABILITY.md section 4).  They
-- count every relation, including any past the 200-entry cap.

data TraceTotals = TraceTotals { dbMs          : Double
                               , otherMs       : Double
                               , wallMs        : Double
                               , queueMs       : Double
                               , relations     : Int
                               , queries       : Int
                               , rowsRead      : Int
                               , rows          : Int
                               , bytes         : Int
                               , documentBytes : Maybe Int }
