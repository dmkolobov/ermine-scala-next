-- WpInt: a report that RENDERS, with a NON-OBJECT parameter root.
--
-- WHAT IT IS FOR: WP-8's G5 case.  `report : Int -> Node` means the
-- parameter schema's root is a number, not an object, so the first-pick
-- skeleton written to `<binding>.params.json` is the bare JSON value `0`
-- with NO `$schema` key (a JSON number cannot carry one), and the extension
-- says out loud that the editor will not validate that file.  It is
-- WpSpin's shape minus the spin, so it answers straight away.
--
-- USED BY tracker/WP-7-MANUAL-CHECKLIST.md as the non-object-root report of
-- section 2.43-2.49 (the first-pick writes), and as the control for every
-- wedge step: if WpInt does not render, the trouble is the server or the
-- roots, not the fixture.
--
-- Measured: tracker/JSON-WIDGET-PLAYGROUND.md section 6, S3's table -- a
-- 105-byte schema carrying $schema/$id/type, a skeleton of `0`, and a first
-- render of ok=true with an 86-byte document.

module WpInt where

import Int
import Json
import Layout.Doc

report : Int -> Node
report n = rawWidget "int" n
