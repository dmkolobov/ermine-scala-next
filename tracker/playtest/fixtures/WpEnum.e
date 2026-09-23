-- WpEnum: a report whose parameter type is an ALL-NULLARY `data` -- one of
-- WP-8 S4's five non-object params roots.
--
-- WHAT IT IS FOR: the exporter writes an all-nullary `data` as a bare `enum`
-- of tag strings behind a `$ref` (MEASURED, 193 bytes:
-- `{"$ref": "#/$defs/WpEnum.Season", "$defs": {"WpEnum.Season":
-- {"enum": ["Spring","Summer","Autumn"]}}}`), so the first-pick skeleton is
-- the bare JSON string `"Spring"` -- the first member -- with NO `$schema`
-- key, and the write notice must say "one of "Spring", "Summer", "Autumn"".
-- It is also the only fixture whose root is reached through a `$ref` hop.
--
-- USED BY tracker/WP-7-MANUAL-CHECKLIST.md step B27.
--
-- Measured 2026-09-23 against a real bin/ermine-lsp, one boot, no editor
-- (tracker/JSON-WIDGET-PLAYGROUND.md section 6, the S4 table): schema 193
-- bytes, skeleton "Spring", first render ok=true, a 94-byte document
-- {"version":1,"settings":{},"root":{"tag":"Widget","name":"season","props":"Spring"}}.

module WpEnum where

import Int
import Json
import Layout.Doc

data Season = Spring | Summer | Autumn

report : Season -> Node
report s = rawWidget "season" s
