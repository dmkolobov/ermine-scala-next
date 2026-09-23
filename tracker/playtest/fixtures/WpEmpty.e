-- WpEmpty: a report whose table is an EMPTY relation with NO header.
--
-- WHAT IT IS FOR: the one render that still answers the "cannot be encoded"
-- 500 on purpose.  `relation []` builds the header-less empty relation (the
-- header is read off the first row, and there is none), so the JSON encoder
-- refuses with "an empty relation built from no rows carries no columns"
-- at $.props.  It is the editor-side twin of TestRunner's (b7) RgEmpty
-- property (scalacheck-binding/src/main/scala/TestRunner.scala).
--
-- Sales used to be this case whenever its date range matched no sale; since
-- 2026-09-23 (the user's Q21 decision) Sales builds that table with
-- `relationWithHeader` and renders an empty table instead.  The engine gap
-- itself is ticket WP-29 in tracker/JSON-WIDGET-PLAYGROUND.md.
--
-- USED BY editor/vscode/test/fixtures/panel-answers.json, case
-- "error-500-wpempty" (captured from a real bin/ermine-lsp).

module WpEmpty where

import Int
import Json
import Layout.Doc
-- `[]` desugars to these
import List using {empty_Bracket; cons_Bracket}
import Relation using {relation}

report : Int -> Node
report n = rawWidget "table" (relation [])
