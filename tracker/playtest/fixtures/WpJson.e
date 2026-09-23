-- WpJson: a report whose parameter type is `Json` -- one of WP-8 S4's five
-- non-object params roots, and the widest one.
--
-- WHAT IT IS FOR: the exporter writes a `Json` position as the EMPTY schema
-- `{}` (json/Schema.scala:300), which accepts anything at all, so the whole
-- answer is `$schema` and `$id` and nothing else (MEASURED, 88 bytes). The
-- skeleton walker's fallback for "no type and no keyword" is `null`, the
-- shortest value that decodes, and the notice must say the file may hold any
-- JSON value at all.
--
-- USED BY tracker/WP-7-MANUAL-CHECKLIST.md step B27.
--
-- Measured 2026-09-23 against a real bin/ermine-lsp (section 6's S4 table):
-- schema 88 bytes, skeleton null, first render ok=true, an 88-byte document
-- {"version":1,"settings":{},"root":{"tag":"Widget","name":"json","props":null}}.

module WpJson where

import Int
import Json
import Layout.Doc

report : Json -> Node
report j = rawWidget "json" j
