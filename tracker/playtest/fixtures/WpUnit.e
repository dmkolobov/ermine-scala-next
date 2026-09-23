-- WpUnit: a report whose parameter type is `()` -- one of WP-8 S4's five
-- non-object params roots, and the only one whose file has nothing in it to
-- edit.
--
-- WHAT IT IS FOR: the exporter writes `()` as `{"type": "array", "maxItems":
-- 0}` (MEASURED, 118 bytes) -- the empty tuple -- so the first-pick skeleton
-- is the bare JSON value `[]`, with no `$schema` key, and the notice must
-- say so rather than calling it "a JSON array".
--
-- USED BY tracker/WP-7-MANUAL-CHECKLIST.md step B27.
--
-- Measured 2026-09-23 against a real bin/ermine-lsp (section 6's S4 table):
-- schema 118 bytes, skeleton [], first render ok=true, an 86-byte document
-- {"version":1,"settings":{},"root":{"tag":"Widget","name":"unit","props":[]}}.

module WpUnit where

import Int
import Json
import Layout.Doc

report : () -> Node
report u = rawWidget "unit" u
