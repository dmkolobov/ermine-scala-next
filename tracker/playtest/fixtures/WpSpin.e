-- WpSpin: a report that NEVER FINISHES -- a bare self-call.
--
-- WHAT IT IS FOR: making the preview watchdog fire, and keeping it fired.
-- `report` forces `spin n`, which re-enters itself with the very argument
-- thunk it was given and builds no datum at all.  The evaluation never
-- returns, so the render is answered by the watchdog after
-- `ermine.preview.timeoutSeconds`, and the JVM then dies by itself when the
-- `swhnf` thunk chain reaches -Xmx (about two minutes at the 2g default).
--
-- The params type is `Int`, so the S3 skeleton is the bare JSON value `0`
-- (a non-object root) and a hand-written params file is just `5`.
--
-- USED BY tracker/WP-7-MANUAL-CHECKLIST.md steps 2.7-2.12 (stuck and
-- recovery), 2.15-2.25 (the WP-22 wedge guard), 2.28-2.32c (the automatic
-- restart), 2.40-2.41c (params files and the wedge question) and 2.52.
-- The checklist calls this file /tmp/wp7/WpSpin.e; see
-- tracker/PLAYTEST-SETUP.md for where it lives now and for the one step
-- (2.40) that still needs a copy OUTSIDE every workspace folder.
--
-- Measured: tracker/JSON-WIDGET-PLAYGROUND.md section 2.5 (watchdog at
-- 12.5 s with a 10 s clock at -Xmx2g; RSS 2.31 GiB; gone about 5 s later).

module WpSpin where

import Builtin
import Int
import Layout.Doc

spin : Int -> Node
spin n = spin n

report : Int -> Node
report n = spin n
