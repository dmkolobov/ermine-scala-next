module StringManip where

{- Here are some extra string manipulation functions, and examples of
working with strings in Ermine. -}

import Bool
import Control.Functor
import List
import Ord
import Function
import Native.List
import Native.Pair

private foreign
  data "java.lang.CharSequence" CharSequence#
  data "scala.collection.immutable.StringOps" ScalaStringOps#
  data "scala.util.matching.Regex" Regex#
  data "scala.util.matching.Regex$MatchIterator" MatchIterator#
  subtype StringIsCS : String -> CharSequence#
  constructor toStringOps : String -> ScalaStringOps#
  method "r" regex# : ScalaStringOps# -> Regex#
  method "findAllIn" srFindAllIn : Regex# -> CharSequence# -> MatchIterator#
  method "toList" miToList# : MatchIterator# -> List# String
  function "com.clarifi.reporting.writers.Markdown" "replaceTemplates" replaceTemplates : String -> List# (Pair# String String) -> String

foreign
  function "java.lang.Integer" "parseInt" parseInt : String -> Int

-- | Find all full matches of a regex in a string.
allMatches : String             -- ^ Regex.
          -> String             -- ^ String to search.
          -> List String
allMatches r = fromList# . miToList#
             . (srFindAllIn . regex# . toStringOps $ r) . StringIsCS

-- | Takes a string "like {{this}}" and a list like [("this,"replacement")] and returns
-- a string "like replacement".
templateSubstitute : String -> List (String, String) -> String
templateSubstitute tmpl subs = replaceTemplates tmpl . toList# . map_List toPair# $ subs

{-
>> allMatches  "\\d+" "1 2 3 4"
res0 : List String = ["1","2","3","4"]
-}

