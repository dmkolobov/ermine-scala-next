-- WpMaybe: a report whose parameter type is `Maybe String` -- one of WP-8
-- S4's five non-object params roots, and the one S1's corrected `Nullable`
-- rule turns on.
--
-- WHAT IT IS FOR: the exporter writes `Maybe a` as `{"anyOf": [a, {"type":
-- "null"}]}` (MEASURED, 146 bytes), and the skeleton rule is "the smallest
-- value that decodes", which for an optional is `null` and NOT the payload's
-- own skeleton -- `""` for a `Maybe String` filter would mean "match the
-- empty string", not "no filter". So the first-pick file is the bare JSON
-- value `null`, with no `$schema` key, and the notice must say it is
-- optional and that `null` means there is none.
--
-- USED BY tracker/WP-7-MANUAL-CHECKLIST.md step B27.
--
-- Measured 2026-09-23 against a real bin/ermine-lsp (section 6's S4 table):
-- schema 146 bytes, skeleton null, first render ok=true, an 89-byte document
-- {"version":1,"settings":{},"root":{"tag":"Widget","name":"maybe","props":null}}.

module WpMaybe where

import Int
import Json
import Layout.Doc

report : Maybe String -> Node
report m = rawWidget "maybe" m
