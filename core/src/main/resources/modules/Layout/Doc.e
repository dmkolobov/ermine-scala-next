module Layout.Doc where

-- The layout vocabulary of a JSON report document (tracker/JSON-API-DESIGN.md
-- sections 3.2 and 3.4a; tracker/JSON-STAGE3-PLAN.md, "Wire contract").
-- A report is a function `report : Params -> Node` (or `Params -> Fetch Node`
-- when it needs rows while it is built: module Layout.Fetch); the document
-- runner evaluates it and encodes the Node with the generic walker, so these
-- record-style constructors ARE the wire:
--
--   {"tag": "Widget", "name": "table", "props": {..}}
--   {"tag": "VFlow",  "children": [node..]}
--   {"tag": "HFlow",  "children": [node..]}
--   {"tag": "Grid",   "cells": [[node..]..]}
--   {"tag": "Tabbed", "tabs": [{"label": "..", "content": node}..]}
--
-- and the whole response is {"version": 1, "settings": {..}, "root": node}.
--
-- A relation anywhere inside a widget's props -- a bare [..r], the wrappers
-- Inline r / Deferred r of module Json, or the Json nodes rel / relInline /
-- relDeferred -- is written by the document writer (json/Write.scala) as
--
--   {"kind": "inline",   "columns": [col..], "rows": [[cell..]..], "rowCount": n}
--   {"kind": "deferred", "columns": [col..], "token": "..", "expires": ".."}
--
-- with col = {"name": .., "type": .., "nullable": ..}, columns sorted by name.
-- A bare relation takes the request's default delivery; a wrapped one always
-- gets what it asks for.

import Json
import List using map_List

data Node = Widget { name : String, props : Json }
          | VFlow { children : List Node }
          | HFlow { children : List Node }
          | Grid { cells : List (List Node) }
          | Tabbed { tabs : List Tab }

data Tab = Tab { label : String, content : Node }

-- a widget of the client's registry, its props encoded by toJson
widget : String -> a -> Node
widget n p = Widget n (toJson p)

vflow : List Node -> Node
vflow = VFlow

hflow : List Node -> Node
hflow = HFlow

grid : List (List Node) -> Node
grid = Grid

tabbed : List (String, Node) -> Node
tabbed ts = Tabbed (map_List ((l, c) -> Tab l c) ts)
