-- WpBlow: a report that EATS THE HEAP instead of spinning.
--
-- WHAT IT IS FOR: killing the server JVM mid-render so the extension takes
-- the `died-mid-render` path rather than the watchdog's.  `grow` is a
-- TOP-LEVEL binding, so the head of the infinite list is retained for the
-- render session's whole life and `length grow` allocates without bound
-- until -XX:+ExitOnOutOfMemoryError exits the process (code 3).
--
-- IT ONLY WORKS AT A SMALL HEAP AND A LONG CLOCK: set
-- "ermine.maxHeap": "256m" and "ermine.preview.timeoutSeconds": 600, so the
-- OOM arrives before the watchdog can answer.  At the 2g default it would
-- take far longer and the watchdog would win.
--
-- USED BY tracker/WP-7-MANUAL-CHECKLIST.md step 2.26 -- the only step that
-- can observe the WP-22 review's M1 (the mark is set from BOTH edges).
-- Put ermine.maxHeap back to "" afterwards.
--
-- Measured: tracker/JSON-WIDGET-PLAYGROUND.md section 2.5 (exit code 3
-- after 8.6 s at ERMINE_LSP_XMX=256m, no watchdog fire).

module WpBlow where

import Int
import Json
import List using {iterate; length}
import Layout.Doc

grow : List Int            -- a TOP-LEVEL binding, so the head of the infinite
grow = iterate (x -> x) 1  -- list is retained for the render session's life

report : Int -> Node
report n = rawWidget "blow" (length grow)
