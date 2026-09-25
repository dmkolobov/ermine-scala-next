module Layout.Trace.Running where

-- A render trace's `running`, present only when `partial` is true (the
-- watchdog answered first): the relation and SQL still running, or the
-- phase the render was stuck in.

data TraceRunning = TraceRunning { path    : Maybe String
                                 , phase   : Maybe String
                                 , sql     : Maybe String
                                 , sinceMs : Double }
