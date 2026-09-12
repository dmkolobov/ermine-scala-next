module Layout.Validation where

import Either
import Prelude
import Layout.Report
import Validation as V
import List
import Control.Functor

-- some error handling combinators (based on work in Validation.e)
showErrors =  let getError (n, s) = text (n ++_String ": " ++_String s) in (vflow . fmap listFunctor getError)
withValidation v f = either showErrors f . (validate_V v)
