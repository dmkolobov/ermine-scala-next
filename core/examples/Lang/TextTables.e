module Lang.TextTables where

{- STRINGS, REGULAR EXPRESSIONS AND MARKDOWN: the one kind of report this build can
   actually DRAW, because its output is a `String`.

   Fact: catalogue (9 fields: skuCode, skuTitle, brandName, categoryPath, listPriceUsd,
         costUsd, stockUnits, reorderPoint, supplierRef)

   WHY THIS FILE EXISTS. `core/examples` has no example of `String` beyond `++`, none
   of `StringManip`, and none of `String.Markdown`; and `Present/` had to explain at
   length that there is no `render`, because a `Report` needs a `Layout.Writer` and
   every writer lives in the separate `ermine-writers` project. A markdown table,
   though, is just a `String`, and a `String` prints in the REPL. So this module renders
   the SAME relation four ways -- markdown, fixed-width ASCII, a CSV line-per-row and a
   one-line summary -- and you can read all four.

   THREE THINGS ABOUT STRINGS IN ERMINE A READER WILL TRIP OVER

     1. `length` is `List.length`. `Prelude` exports `List` unqualified and the STRING
        length is a builtin registered as `String.length`, so it must be `length_S`.
        `import Prelude hiding length` does not help: it makes `length` undefined.
     2. `++` is `List.(++)`; string concatenation is `++_S`.
     3. A character literal whose character is an OPERATOR symbol does not lex. `'-'`
        is `error: unknown operator '-'`, because `'` is `Function.(')`, an `infixl 0`
        application operator. `' '`, `'\n'` and `'a'` are fine; `'-'`, `'.'` and `'|'`
        must be written `strCharAt "-" 0` (`Helpers.dashChar` and friends).

   AND ONE BUG. `String.Markdown` is eight lines and one of the three is wrong:

       link title loc = "[" ++ title "](" ++ loc ++ ")"

   `title "]("` is an APPLICATION -- juxtaposition binds tighter than `++` -- so the
   module type-checks with `link : (String -> String) -> String -> String`. It is not
   unusable: pass the title PRE-COMPOSED and the shipped `link` produces a correct link,

       link ((++) "SUP-77/A") loc   ==>   "[SUP-77/A](...)"

   which `workingLink` below evaluates. What is broken is that no ORDINARY call site
   type-checks and the working spelling is undocumented and unguessable. `mdLink` in
   `Helpers.e` is what it meant to say, and `brokenLinkType` pins the shipped one's real
   type so a reader can see it. (E5's reviewer refuted the stronger "can never produce a
   link" that this header used to carry.)

   SHAPES EXERCISED
     * `String`: `split`, `unsplit`, `words`, `unwords`, `lines`, `take`, `drop`,
       `substring`, `substringFrom`, `replace`, `replaceAll`, `splitCamelCase`,
       `uppercaseFirstLetter`, `trim`, `indexOf`, `uppercase`, `concat`, `stringMonoid`.
     * `StringManip.allMatches` -- `scala.util.matching.Regex` through six `foreign`
       declarations, which is the most involved FFI in the stdlib.
     * `String.Markdown.bold`/`italic`, and `link`'s type.
     * `Helpers.showRows`: a row variable, a projection to cells, and a markdown table.
     * THE PROJECTION CLIFF, twice, and its remedy. Two of the three most expensive
       solves in the whole E-series corpus are in this file: `catalogueMarkdown`'s cell
       lambda at 1,241 draws and `catalogueAscii`'s at 1,230, every one of them a
       `Resolution` step. (The third is `RunningState.postingMarkdown` at 1,233; the
       three sit within 1 % of one another, so treat them as a set rather than a
       ranking.) Five `t ! f`s on an unannotated record is all it takes.
       `catalogueMarkdownPinned` below is the SAME table with the lambda's argument
       annotated at the concrete row: **one draw**. E5's reviewer also measured that
       reordering `showRows`'s arguments changes nothing (1,230 vs 1,233) -- the
       annotation is the only fix.
     * `Control.Monoid` used for text: `joinedMonoid` is the separator-aware monoid
       `stringMonoid` is not.

   >> :load core/examples/Lang/Helpers.e
   >> :load core/examples/Lang/TextTables.e
   >> catalogueMarkdown          -- a markdown table, printed (1,230 draws to check)
   >> catalogueMarkdownPinned    -- the same table, annotated lambda: 1 draw
   >> workingLink
   >> catalogueAscii             -- fixed-width, printed
   >> catalogueCsv
   >> priceCodes
   >> tidyTitles
   >> catalogueSummary
-}

import Prelude
import Syntax.List
import Control.Monoid as Mo
import Layout
import Relation.Op as Op
import Relation.Predicate as Pred
import List as L
import String as S
import StringManip as SMan
import String.Markdown as MD
import Lang.Helpers

field skuCode      : String
field skuTitle     : String
field brandName    : String
field categoryPath : String
field listPriceUsd : Double
field costUsd      : Double
field stockUnits   : Int
field reorderPoint : Int
field supplierRef  : String

-- ---------------------------------------------------------------------------
-- 1. The catalogue.

catalogueRows : List {skuCode, skuTitle, brandName, categoryPath, listPriceUsd, costUsd,
                      stockUnits, reorderPoint, supplierRef}
catalogueRows = [
  { skuCode = "SKU-1001", skuTitle = "carbonRoadFrame", brandName = "Velodyne",
    categoryPath = "Bikes/Road/Frames", listPriceUsd = 2450.00, costUsd = 1180.00,
    stockUnits = 34, reorderPoint = 12, supplierRef = "SUP-77/A" },
  { skuCode = "SKU-1002", skuTitle = "alloyTouringWheelset", brandName = "Velodyne",
    categoryPath = "Bikes/Touring/Wheels", listPriceUsd = 890.00, costUsd = 402.50,
    stockUnits = 8, reorderPoint = 15, supplierRef = "SUP-77/B" },
  { skuCode = "SKU-1003", skuTitle = "merinoBaseLayerXL", brandName = "Fjordkit",
    categoryPath = "Apparel/Base/Tops", listPriceUsd = 129.00, costUsd = 44.75,
    stockUnits = 210, reorderPoint = 60, supplierRef = "SUP-31/C" },
  { skuCode = "SKU-1004", skuTitle = "hydraulicDiscBrakeSet", brandName = "Torqline",
    categoryPath = "Components/Brakes/Hydraulic", listPriceUsd = 415.00, costUsd = 198.00,
    stockUnits = 47, reorderPoint = 20, supplierRef = "SUP-52/A" },
  { skuCode = "SKU-1005", skuTitle = "GPSBikeComputer", brandName = "Torqline",
    categoryPath = "Electronics/Navigation", listPriceUsd = 349.00, costUsd = 151.25,
    stockUnits = 5, reorderPoint = 25, supplierRef = "SUP-52/D" },
  { skuCode = "SKU-1006", skuTitle = "thermalBibTightPro", brandName = "Fjordkit",
    categoryPath = "Apparel/Bottoms/Winter", listPriceUsd = 189.00, costUsd = 71.40,
    stockUnits = 96, reorderPoint = 40, supplierRef = "SUP-31/A" }
  ]_L

catalogue : Relation (|skuCode, skuTitle, brandName, categoryPath, listPriceUsd, costUsd,
                       stockUnits, reorderPoint, supplierRef|)
catalogue = relation catalogueRows

-- ---------------------------------------------------------------------------
-- 2. Rendering one: markdown, through `showRows`.
--
-- `showRows : List String -> ({..r} -> List String) -> List {..r} -> String` carries
-- the row variable; the projection to cells is the caller's business.

catalogueMarkdown : String
catalogueMarkdown =
  showRows (["SKU", "Title", "Brand", "List", "Stock"]_L)
           (t -> [ t ! skuCode
                 , bold_MD (tidyOf (t ! skuTitle))
                 , italic_MD (t ! brandName)
                 , toString (t ! listPriceUsd)
                 , toString (t ! stockUnits) ]_L)
           catalogueRows

-- | THE SAME TABLE, one token cheaper. Annotating the lambda's argument at the concrete
--   row removes the row VARIABLE, and with it all five existential partitions: this
--   binding costs the solver **one** draw where the one above costs 1,230. Nothing else
--   differs. Keep both: the generic one is what a helper's caller writes, and this is
--   what to do when the census says it hurts.
catalogueMarkdownPinned : String
catalogueMarkdownPinned =
  showRows (["SKU", "Title", "Brand", "List", "Stock"]_L)
           ((t : {skuCode, skuTitle, brandName, categoryPath, listPriceUsd, costUsd,
                  stockUnits, reorderPoint, supplierRef})
              -> [ t ! skuCode
                 , bold_MD (tidyOf (t ! skuTitle))
                 , italic_MD (t ! brandName)
                 , toString (t ! listPriceUsd)
                 , toString (t ! stockUnits) ]_L)
           catalogueRows

-- ---------------------------------------------------------------------------
-- 3. Rendering two: fixed-width ASCII, through `rpad`/`lpad`.

asciiRow : List Int -> List String -> String
asciiRow widths cs =
  foldMapL (joinedMonoid "  ") id (zipWith_L (w c -> rpad w c) widths cs)

catalogueAscii : String
catalogueAscii = foldMapL (joinedMonoid "\n") id (hdr :: rule :: body)
  where widths = [10, 24, 10, 10, 7]_L
        hdr    = asciiRow widths (["SKU", "TITLE", "BRAND", "LIST", "STOCK"]_L)
        rule   = foldMapL (joinedMonoid "  ") id (map (w -> dashes w) widths)
        body   = map (t -> asciiRow widths
                             [ t ! skuCode
                             , tidyOf (t ! skuTitle)
                             , t ! brandName
                             , lpad 10 (toString (t ! listPriceUsd))
                             , lpad 7 (toString (t ! stockUnits)) ]_L)
                     catalogueRows
        dashes n = if (n <= 0) "" ("-" ++_S dashes (n - 1))

-- ---------------------------------------------------------------------------
-- 4. Rendering three: CSV, which is `unsplit` and nothing else.

catalogueCsv : String
catalogueCsv = foldMapL (joinedMonoid "\n") id
  (map (t -> unsplit_S ',' [ t ! skuCode, t ! skuTitle, t ! brandName
                           , toString (t ! listPriceUsd) ]_L)
       catalogueRows)

-- ---------------------------------------------------------------------------
-- 5. String manipulation the report actually needs.

-- | `splitCamelCase` is the most useful thing in `String.e` and has no example. It is
--   three lookahead/lookbehind regexes joined by `|`, applied with `replaceAll`.
tidyOf : String -> String
tidyOf = uppercaseFirstLetter_S . splitCamelCase_S

tidyTitles : List String
tidyTitles = map (t -> tidyOf (t ! skuTitle)) catalogueRows

-- | The leaf of a `/`-separated category path, and its depth.
leafOf : String -> String
leafOf p = orElse p (lastOf (split_S '/' p))
  where lastOf Nil        = Nothing
        lastOf (x :: Nil) = Just x
        lastOf (_ :: xs)  = lastOf xs

depthOf : String -> Int
depthOf p = length_L (split_S '/' p)

categoryLeaves : List (String, Int)
categoryLeaves = map (t -> (leafOf (t ! categoryPath), depthOf (t ! categoryPath)))
                     catalogueRows

-- | `StringManip.allMatches` is `scala.util.matching.Regex` reached through six
--   `foreign` declarations -- a `data`, a `subtype`, a `constructor`, three `method`s.
--   Here it pulls every number out of a supplier reference.
priceCodes : List (List String)
priceCodes = map (t -> allMatches_SMan "\\d+" (t ! supplierRef)) catalogueRows

-- | `String.e` has `uppercase` and no `lowercase`, so here is one. Three lines of
--   `foreign` is how you extend the stdlib without touching it.
foreign
  method "toLowerCase" lowercase : String -> String

-- | `replace`, and the `foreign` above. A slug: "carbonRoadFrame" -> "carbon_road_frame".
slugOf : String -> String
slugOf = replace_S ' ' '_' . lowercase . splitCamelCase_S

skuSlugs : List String
skuSlugs = map (t -> slugOf (t ! skuTitle)) catalogueRows

-- | `replaceAll` takes REGEXES on both sides, so the replacement can refer to a group.
--   Here every run of digits in a supplier reference is bracketed.
markedRefs : List String
markedRefs = map (t -> replaceAll_S "(\\d+)" "<$1>" (t ! supplierRef)) catalogueRows

-- | Where the first `/` is in the category path, and what is in front of it.
--   `indexOf`'s receiver is the FIRST argument: `indexOf haystack needle`.
pathSplits : List (Int, String)
pathSplits = map (t -> let i = indexOf_S (t ! categoryPath) "/"
                       in (i, substringTo_S i (t ! categoryPath)))
                 catalogueRows

-- ---------------------------------------------------------------------------
-- 6. `String.Markdown`, and its one broken function.
--
-- `bold` and `italic` are right. `link` is not: `"[" ++ title "](" ++ loc ++ ")"`
-- applies `title` to the string `"]("`. The binding below has the type the shipped
-- `link` really has, and it type-checks -- which is the whole problem.

brokenLinkType : (String -> String) -> String -> String
brokenLinkType = link_MD

-- | The shipped `link`, called the one way that works: the title pre-composed with
--   `++`, so that `title "]("` is `"SUP-77/A" ++ "]("`.
workingLink : String
workingLink = link_MD ((++_S) "SUP-77/A") "https://example.invalid/supplier"

-- | What it meant to say. `Helpers.mdLink`, used here on a supplier reference.
supplierLinks : List String
supplierLinks = map (t -> mdLink (t ! supplierRef)
                                 ("https://example.invalid/supplier/" ++_S (t ! supplierRef)))
                    catalogueRows

-- ---------------------------------------------------------------------------
-- 7. A one-line summary, built with the two string monoids.
--
-- `String.stringMonoid` is `Monoid "" (++)` -- no separator, so it cannot join a list
-- of words into a sentence. `Helpers.joinedMonoid` is the one that can, and it is
-- careful about the empty string on either side.

catalogueSummary : String
catalogueSummary =
  foldMapL (joinedMonoid "; ") id
    (map (t -> tidyOf (t ! skuTitle) ++_S " (" ++_S toString (t ! stockUnits) ++_S ")")
         catalogueRows)

concatenated : String
concatenated = foldMapL stringMonoid_S (t -> t ! skuCode) catalogueRows

-- ---------------------------------------------------------------------------
-- 8. And the relational report beside the textual ones.

belowReorder : Relation (|skuCode, skuTitle, brandName, categoryPath, listPriceUsd,
                          costUsd, stockUnits, reorderPoint, supplierRef|)
belowReorder = catalogue |> filter_Pred (col_Op stockUnits <_Pred col_Op reorderPoint)

byBrand : Mem (|brandName, stockUnits|)
byBrand = catalogue |> groupBy {brandName} (sumBy stockUnits)

textReport : Report f z
textReport = vflow [
    text "## Catalogue",
    text catalogueMarkdown,
    text "### Below reorder point",
    tabular Nothing (belowReorder # {skuCode, skuTitle, stockUnits, reorderPoint}),
    text "### Units by brand",
    tabular Nothing byBrand,
    text ("### " ++_S catalogueSummary)
  ]_L
