module Json where

-- The JSON document type and the reflective encoder.  The type, its
-- constructors and the `#` primitives are declared by the session library
-- (ermine/session/Lib.scala, `json`); this module adds the plain names.
--
--   data Json = JNull | JBool Bool | JNum Double | JInt Long | JStr String
--             | JArr (List Json) | JObj (List (String, Json))
--             | JRel [..r] | JInline [..r] | JDeferred [..r]
--
-- `toJson` encodes any value by walking it (tracker/JSON-API-DESIGN.md
-- section 3.1): numbers, strings, booleans, dates as ISO strings, Long as a
-- decimal string, Maybe and Nullable as the value or null, lists and tuples
-- as arrays, records as objects with sorted keys, an all-nullary data type
-- as its constructor name, a relation as JRel (or JInline / JDeferred when
-- it is wrapped in Inline / Deferred, below).  A data constructor with
-- NAMED fields (`data Pt = Pt { px : Int, py : Int }`) is an object keyed in
-- declaration order, with a "tag" key first when the type has more than one
-- constructor and none when it has exactly one; a named field of type
-- `Maybe a` holding Nothing is left OUT of the object.  A POSITIONAL
-- constructor is {"tag": C, "args": [..]}.  A function, an IO action, a
-- foreign value or an error inside the value is an error naming the path
-- to it.
--
-- `render` prints compactly and `pretty` with two-space indentation; both
-- refuse a relation node (its rows are resolved by the document writer, not
-- here).  `parse` reads text back into a Json value.

-- Delivery of a relation's rows in a document (tracker/JSON-API-DESIGN.md
-- section 3.4a).  A bare relation takes the request's default; a wrapped one
-- always gets what it asks for.  On the wire both arms carry the columns:
--
--   {"kind": "inline",   "columns": [..], "rows": [[..]], "rowCount": n}
--   {"kind": "deferred", "columns": [..], "token": "..", "expires": ".."}
--
-- and the schema exporter gives a bare relation the union of the two, an
-- Inline the first arm only and a Deferred the second only.

data Inline r = Inline [..r]       -- the rows are in this response
data Deferred r = Deferred [..r]   -- the columns now, the rows on re-request

-- A named constructor field of declared type `Spread Json` is MERGED into
-- the object its constructor writes (tracker/JSON-API-DESIGN.md section
-- 3.1b item 2): the long tail of options nobody wants to model.
--
--   data HcConfig = HcConfig { hcTitle : String, hcExtra : Spread Json }
--   HcConfig "t" (Spread (obj [("plotOptions", jnull)]))
--     ==>  {"hcTitle": "t", "plotOptions": null}
--
-- The spread's keys go out AFTER the declared fields, in the object's own
-- order.  A key that collides with a declared field name (or with the "tag"
-- of a type with several constructors) is an error naming both, since the
-- params decoder reads such a key back as the field -- the SPREAD field's
-- own name excepted, which is no key of any document of the type and so is
-- merged and gathered like any other.  A repeated key is an error too,
-- and so is a Spread holding anything but an object.  A constructor carries
-- at most one Spread field, and a positional constructor none (there is no
-- object to merge into).  Only `Spread Json` is meaningful: a record's keys
-- are known from its declaration, so spreading one would be no more than a
-- second way to spell fields the constructor can already name.
--
-- The schema exporter drops `additionalProperties: false` from the parent
-- object (zod `.passthrough()` instead of `.strict()`) and the spread field
-- is not a property of it; the decoder gathers every key the declaration
-- does not name back into the Spread, in document order.
data Spread a = Spread a

toJson : a -> Json
toJson = toJson#

render : Json -> String
render = renderJson#

pretty : Json -> String
pretty = prettyJson#

parse : String -> Maybe Json
parse = parseJson#

-- constructors under the names the document builders use

jnull : Json
jnull = JNull

bool : Bool -> Json
bool = JBool

num : Double -> Json
num = JNum

int : Long -> Json   -- renders as a JSON number, unlike toJson on a Long (a decimal string)
int = JInt

str : String -> Json
str = JStr

arr : List Json -> Json
arr = JArr

obj : List (String, Json) -> Json
obj = JObj

rel : [..r] -> Json
rel = JRel

relInline : [..r] -> Json
relInline = JInline

relDeferred : [..r] -> Json
relDeferred = JDeferred
