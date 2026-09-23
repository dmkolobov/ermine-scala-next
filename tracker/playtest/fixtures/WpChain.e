-- WpChain: a report that NEVER FINISHES -- a fold over a CYCLIC list.
--
-- WHAT IT IS FOR: the same wedge as WpSpin by a different mechanism, and
-- the one the watchdog figures in section 2.5 were measured on.  `repeat`
-- builds a one-cell cyclic list (`repeat a = t where t = a :: t`,
-- List.e:29-30) and `length` folds over it for ever.  On paper the live set
-- is one cons cell and one Int; it is not, because `Runtime.swhnf` carries a
-- thunk chain only `writeback` unwinds.
--
-- USE IT instead of WpSpin anywhere the checklist wants a second wedge with
-- a different shape -- nothing in tracker/WP-7-MANUAL-CHECKLIST.md names it
-- by name, and the steps that say WpSpin work with either.
--
-- Measured: tracker/JSON-WIDGET-PLAYGROUND.md section 2.5, three runs
-- (watchdog at 12.0-12.2 s with a 10 s clock at -Xmx2g; RSS 1.91-2.02 GiB;
-- exit code 3 before +120 s in the two runs that got there).

module WpChain where

import Int
import Json
import List using {length; repeat}
import Layout.Doc

report : Int -> Node
report n = rawWidget "chain" (length (repeat n))
