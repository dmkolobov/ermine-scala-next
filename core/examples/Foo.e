module Foo where

import Syntax.Relation

field ``Col2`` : String
field ``Col1`` : Int
--able mytable1: [Col1, Col2]

--example2 = guiReportFX fxg (Table (relation mytable1))


-- legal
table ``table1`` : [``Col1``, Col2]

``foo`` = ``table1`` & {``Col1`` = 0}

data ``Bar`` = ``Baz`` | ``Quux``

