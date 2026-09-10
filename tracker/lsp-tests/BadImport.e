module BadImport where

import NoSuchModule
import BadSib

own : Int
own = 6

useOwn = own

use = sibAnswer

bad : Int
bad = "no"
