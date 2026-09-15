module Json where

-- The JSON document type and the reflective encoder.  The type, its
-- constructors and the `#` primitives are declared by the session library
-- (ermine/session/Lib.scala, `json`); this module adds the plain names.
--
--   data Json = JNull | JBool Bool | JNum Double | JInt Long | JStr String
--             | JArr (List Json) | JObj (List (String, Json)) | JRel [..r]
--
-- `toJson` encodes any value by walking it (tracker/JSON-API-DESIGN.md
-- section 3.1): numbers, strings, booleans, dates as ISO strings, Long as a
-- decimal string, Maybe and Nullable as the value or null, lists and tuples
-- as arrays, records as objects with sorted keys, an all-nullary data type
-- as its constructor name, a relation as JRel.  A data constructor with
-- NAMED fields (`data Pt = Pt { px : Int, py : Int }`) is an object keyed in
-- declaration order, with a "tag" key first when the type has more than one
-- constructor and none when it has exactly one; a named field of type
-- `Maybe a` holding Nothing is left OUT of the object.  A POSITIONAL
-- constructor is {"tag": C, "args": [..]}.  A function, an IO action, a
-- foreign value or an error inside the value is an error naming the path
-- to it.
--
-- `render` prints compactly and `pretty` with two-space indentation; both
-- refuse a JRel node (its rows are resolved by the document writer, not
-- here).  `parse` reads text back into a Json value.

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
