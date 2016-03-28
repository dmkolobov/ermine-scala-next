module Layout.Report where

import Native
import Native.Map as NM
import Native.Ord using ord#
import Function
import Field
import Layout.Color
import Layout.Column using type Column; formatK; keys; drilldown; drilldown2
import Layout.Column.Unsafe using type Table#; column#
import Layout.Format as Fmt
import Layout.Legend using type Legend#; type Legend; legend
                           legend#; initialSort#; empty as emptyLegend
                           (++) as (++_Legend); fromRow; legendRow
import Layout.Presentation using type Presentation; asPresentation; rowUsed; basic
import Layout.Report.DynamicFulcrum
import Layout.Report.Atomic
import Layout.Report.SoftRelation
import Layout.Magnitude
import Layout.BorderOptions
import Layout.Font
import Date
import DateRange
import IO
import Bool as Bool
import List
import List.Util using sort
import DrilldownList using {type DrilldownList; fromDrilldown; toRow}
import Tree as T
import Either
import Maybe
import Int
import Ord using {type Ord; fromLess}
import Pair
import Prim using {unsafePrimExprIn#; primExpr#; type PrimExpr#}
import Error
import String as String
import Control.Functor
import Control.Monad
import Control.Monad.Cont
import Control.Traversable
import Relation using rheader; asMem; relation
import Relation.Op using prim; typeOfOp; type Op
import Relation.Pivot using type Fulcrum; snoc_Brace as snoc_Fulcrum ; single_Brace as single_Fulcrum; pivot
import Relation.Row using project; except; minus; single_Brace; snoc_Brace; type Row; append as appendR
                          empty as emptyRow
import Relation.Sort
import Record using type Record
import Syntax.Do hiding unit
import Syntax.List
import Syntax.IO hiding map
import Layout.Chart
import Layout.Chart.Unsafe
import Layout.Writer
import Layout.SortPriority as Pri
import Layout.SortStrategy as SS
import Layout.SortStrategy.Unsafe
import Void
import Unsafe.Coerce
import IO.Unsafe
import Eq
import Parse
import Validation hiding empty_Bracket; cons_Bracket

export Layout.Report.Direction
export Layout.Report.SelectorMode

-- defaultLegend = Nothing

-- z=the thing being built, like a JavaFX Node for the JavaFXWriter
data Report f z = Report (Writer f z -> f z)
runReport w (Report f) = f w

---------------------------------------------------
-- Terrible, Terrible Hacks
---------------------------------------------------

-- One requirement in scala-2.9.2 is to use a user supplied format string to format
-- dates.  To implement that requirement, the JavaFXWriter and ExcelWriter are parameterized
-- on a date format string.  If we want to be able to correctly turn a date into a string
-- in Ermine, we must go through the writer or do something even worse, like have global mutable state somewhere.

formatDate : Date -> (String -> Report f z) -> Report f z
formatDate d f = formatDateFn (ds -> f (ds d))

-- | A date-to-string function configured by the report.
formatDateFn : ((Date -> String) -> Report f z) -> Report f z
formatDateFn k = Report (w -> case k (formatDate_ w) of (Report r) -> r w)

formatDateAtom d = formatDate d text

formatDateRange : (Date, Date) -> (String -> Report f z) -> Report f z
formatDateRange (start, stop) k = formatDateRangeFn $ drs ->
  k (drs (start, stop))

-- | A daterange-to-string function configured by the report.
formatDateRangeFn : (((Date, Date) -> String) -> Report f z) -> Report f z
formatDateRangeFn k = formatDateFn $ df ->
  k ((start, stop) -> unwords_String [df start, "-", df stop])

---------------------------------------------------
-- Simple layout combinators
---------------------------------------------------

atom : Atomic a -> Report f z
atom (Atomic f s) = Report (w -> unit (wm w) (atomW w f s))

-- List of fonts, with all of them after the first being fallbacks, an optional size, in pts,
atom' : List Font -> Maybe Int -> Atomic a -> Report f z
atom' fonts size (Atomic f s) = Report (w -> unit (wm w) (atomW' w fonts size f s))

wrapped : MagnitudeList ->  Atomic a -> Report f z
wrapped m (Atomic f s) = Report (w -> unit (wm w) (wrappedW w m f s))

-- List of fonts, with all of them after the first being fallbacks, an optional size, in pts,
wrapped' : MagnitudeList -> List Font -> Maybe Int -> Atomic a -> Report f z
wrapped' m fonts size (Atomic f s) = Report (w -> unit (wm w) (wrappedW' w m fonts size f s))

--wrappedText s = wrapped s . Atomic unit_Fmt

atomShown : Primitive a => a -> Report f z
atomShown = atom . Atomic unit_Fmt

atomShown' fonts size = atom' fonts size . Atomic unit_Fmt

markdownShown = atom . Atomic (markdown_Fmt unit_Fmt)

val : Primitive a => a -> Atomic a
val = Atomic unit_Fmt

fmt : Format_Fmt a -> a -> Report f z
fmt f a = atom (Atomic f a)

-- Displays text label, supports markdown for hyperlinks, italics and bold text
text : String -> Report f z
text = fmt $ markdown_Fmt unit_Fmt

textNoMarkdown : String -> Report f z
textNoMarkdown = fmt unit_Fmt

-- Escape string so that "text" and "atomShown" do not try to interpret the markdown markers
foreign
  function "com.clarifi.reporting.writers.Markdown" "escapeForMarkdown" escapeMarkdown : String -> String



wrappedText' width fonts fontsize = wrapped' width fonts fontsize . Atomic unit_Fmt

link path txt = text $ linkText path txt
linkText path txt = "[" ++_String txt ++_String "](" ++_String path ++_String ")"

img path altText = Report (w -> unit (wm w) (imageW w path (toMaybe# altText)))

currency : String -> Double -> Report f z
currency cur = atom . Atomic (currency_Fmt cur)

number : PrimitiveNum a => a -> Report f z
number = atomShown

wholeNumber : PrimitiveNum a => a -> Report f z
wholeNumber = rounded 0

percent : PrimitiveNum a => a -> Report f z
percent n = atom (Atomic percentage_Fmt n)

rounded : PrimitiveNum a => Int -> a -> Report f z
rounded places n = atom (Atomic (round_Fmt places) n)

dateRange : Date -> Date -> Report f z
dateRange start stop = atom (Atomic dateRange_Fmt (start, stop))

style : String -> Report f z -> Report f z
style h a = Report (w -> liftM (wm w) (styleW w h) (runReport w a))

-- basic size combos, in terms of pixels
``1pixel`` = [pixelsM 1, cellsM 0]
``2pixels`` = [pixelsM 2, cellsM 1]
``4pixels`` = [pixelsM 4, cellsM 1]
``6pixels`` = [pixelsM 6, cellsM 1]
``8pixels`` =  [pixelsM 8, cellsM 1]
``12pixels`` = [pixelsM 12, cellsM 2]
``16pixels`` = [pixelsM 16, cellsM 2]
``20pixels`` = [pixelsM 20, cellsM 2]


-- some sizes just for excel, since padding is preferable for long text
-- instead of autosizing
``1cell`` = [cellsM 1]
``2cell`` = [cellsM 2]
``3cell`` = [cellsM 3]
``4cell`` = [cellsM 4]
``5cell`` = [cellsM 5]
``6cell`` = [cellsM 6]

-- spacers and struts

hspace1 = padLeft [cellsM 1] . style "hspace1" $ emptyReport
hspace2 = padLeft [cellsM 1] . style "hspace2" $ emptyReport
hspace3 = padLeft [cellsM 1] . style "hspace3" $ emptyReport
hspace4 = hflow [hspace3, hspace3]

-- spacing hack for Excel, for when autosized columns introduce the empty space for us.
hspace3' = style "hspace3" $ emptyReport

vspace1 = padBottom [cellsM 1] . style "vspace1" $ emptyReport
vspace2 = padBottom [cellsM 1] . style "vspace2" $ emptyReport
vspace3 = padBottom [cellsM 1] . style "vspace3" $ emptyReport
vspace4 = vflow [vspace3, vspace3]

space : Report f z
space = text " "

space2 : Report f z
space2 = text "  "

space3 : Report f z
space3 = text "   "

vline = stackLeft (backgroundColor underlineColor (prefW ``1pixel`` emptyReport)) emptyReport
hline = stack (backgroundColor underlineColor (prefH ``1pixel`` emptyReport)) emptyReport

surround delim r = hflow [delim, r, delim]

padSides padding = pad' (left padding . right padding)

hstrut = surround hpad1 vline
hstrutWide = surround hpad2 vline

vstrut = surround vpad1 hline
vstrutWide = surround vpad2

hpad1 = padLeft ``8pixels`` emptyReport
hpad2 = padLeft ``16pixels`` emptyReport

vpad1 = padTop ``8pixels`` emptyReport
vpad2 = padTop ``16pixels`` emptyReport

-- A heading
h : Int -> String -> Report f z
h n s = wrap ("h" ++_String (toString n)) (text s)

h1 : String -> Report f z
h1 = h 1

h2 : String -> Report f z
h2 = h 2

h3 : String -> Report f z
h3 = h 3

h4 : String -> Report f z
h4 = h 4

h5 : String -> Report f z
h5 = h 5

pad1 : Report f z -> Report f z
pad1 r = style "padded1" r

pad2 : Report f z -> Report f z
pad2 r = style "padded2" r

pad3 : Report f z -> Report f z
pad3 r = style "padded3" r

pad4 : Report f z -> Report f z
pad4 r = style "padded4" r

normalFont = style "normal-font"

emptyReport : Report f z
emptyReport = prefA [pixelsA 0 0, cellsA 0 0] ' Report (w -> unit (wm w) (emptyW w))

-- | Lay reports out left-to-right, each taking up their "natural"
-- horizontal amount of the containing space and 100% of vertical
-- space.
hflow : List (Report f z) -> Report f z
hflow = flow Horizontal

hflowStyle : String -> List (Report f z) -> Report f z
hflowStyle s = style ("hflow@" ++_String s) . hflow

-- | Lay reports out top-to-bottom, each taking up their "natural"
-- vertical amount of the containing space and 100% of horizontal
-- space.
vflow : List (Report f z) -> Report f z
vflow = flow Vertical

vflowStyle : String -> List (Report f z) -> Report f z
vflowStyle s = style ("vflow@" ++_String s) . vflow

stackAll : List (Report f z) -> Report f z -> Report f z
stackAll l r = foldr stack r l

stackAllPadded : MagnitudeList -> List (Report f z) -> Report f z -> Report f z
stackAllPadded p l r = foldr (t c -> stack ' padBottom p t ' c) r l

-- | Like `hflow`, but places `sep` (typically a spacer or strut)
-- between each element.
hsep : Report f z -> List (Report f z) -> Report f z
hsep sep = hflow . intersperse sep

-- | Like `vflow`, but places `sep` (typically a spacer or strut)
-- between each element.
vsep : Report f z -> List (Report f z) -> Report f z
vsep sep = vflow . intersperse sep

-- | Horizontal layout which takes up 100% of horizontal space, with
-- each element in the list receiving equal horizontal space
hspan : List (Report f z) -> Report f z
hspan = spanning Horizontal . map (r -> ([dimensionlessM 1.0], r))

-- | Vertical layout which takes up 100% of vertical space, with
-- each element in the list receiving equal vertical space
vspan : List (Report f z) -> Report f z
vspan = spanning Vertical . map (r -> ([dimensionlessM 1.0], r))

-- | As with hspan, but with relative-weighted widths.
hspanWeighted : List (MagnitudeList, Report f z) -> Report f z
hspanWeighted rs = spanning Horizontal (map ((w,r) -> (w, r)) rs)

-- | As with vspan, but with relative-weighted heights.
vspanWeighted : List (MagnitudeList, Report f z) -> Report f z
vspanWeighted rs = spanning Vertical (map ((w,r) -> (w, r)) rs)

-- | As with hspan, but with relative-weighted widths.
hspanWeighted' : List (Double, Report f z) -> Report f z
hspanWeighted' rs = spanning Horizontal (map ((w,r) -> ([dimensionlessM w], r)) rs)

-- | As with vspan, but with relative-weighted heights.
vspanWeighted' : List (Double, Report f z) -> Report f z
vspanWeighted' rs = spanning Vertical (map ((w,r) -> ([dimensionlessM w], r)) rs)

-- | As with hspan, but adds some padding between each element
-- hspanPad : MagnitudeList -> (Report f z) -> Report f z
hspanPad padding [] = hspan []
hspanPad padding [r] = hspan [r]
hspanPad padding (h :: t) = hspan (h :: map (padLeft padding) t)

hspanPad1 = hspanPad ``2pixels``
hspanPad2 = hspanPad ``6pixels``
hspanPad3 = hspanPad ``12pixels``

hflowPad padding [] = hflow []
hflowPad padding [r] = hflow [r]
hflowPad padding (h :: t) = hflow (h :: map (padLeft padding) t)

hflowPad1 = hflowPad ``2pixels``
hflowPad2 = hflowPad ``6pixels``
hflowPad3 = hflowPad ``12pixels``

vflowPad padding [] = vflow []
vflowPad padding [r] = vflow [r]
vflowPad padding (h :: t) = vflow (h :: map (padTop padding) t)

vflowPad1 = vflowPad ``2pixels``
vflowPad2 = vflowPad ``6pixels``
vflowPad3 = vflowPad ``12pixels``
vflowPad4 = vflowPad ``20pixels``

border : Maybe (Report f z) ->
         Maybe (Report f z) ->
         Maybe (Report f z) ->
         Maybe (Report f z) ->
         Maybe (Report f z) -> Report f z
border center top' right' bottom' left' = Report (wr ->
  liftA5 (wa wr) (borderW wr)
    (fMA wr center) (fMA wr top') (fMA wr bottom') (fMA wr right') (fMA wr left'))

stack : Report f z -> Report f z -> Report f z
stack top' center' = border (Just center') (Just top') Nothing Nothing Nothing

stackLeft : Report f z -> Report f z -> Report f z
stackLeft left' center' = border (Just center') Nothing Nothing Nothing (Just left')

stackRight : Report f z -> Report f z -> Report f z
stackRight right' center' = border (Just center') Nothing (Just right') Nothing Nothing

tree : Report f z -> Tree_T (Report f z) -> Report f z
tree lg t = Report (w -> liftA2 (wa w) (treeW_ w) (runReport w lg) (travTW w (runReport w) t))

private
  travTW : Writer f a -> (b -> f c) -> Tree_T b -> f (Tree_T c)
  travTW w = traverse traversable_T (wa w)

private
  flow : Direction -> List (Report f z) -> Report f z
  flow d xs = Report (w -> liftM (wm w) (flowW d w) $ travLW w (runReport w) xs)

unweighted : List a -> List (Maybe b, a)
unweighted = fmap listFunctor ((,) Nothing)

spanning : Direction -> (List (MagnitudeList, Report f z)) -> Report f z
spanning d xs = Report (w -> liftM (wm w) (spanW d w) $ travLW w (strength (wf w) . mapSnd (runReport w)) xs)

tabbed : List (String, Report f z) -> Report f z
tabbed xs = Report (w -> liftM (wm w) (tabbedW w) $ travLW w (strength (wf w) . mapSnd (runReport w)) xs)

sideTabbed : List (String, Report f z) -> Report f z
sideTabbed xs = Report (w -> liftM (wm w) (sideTabbedW w) $ travLW w (strength (wf w) . mapSnd (runReport w)) xs)

collapsible : Bool -> String -> Report f z -> Report f z
collapsible expanded title r =
  Report (w -> liftM (wm w) (collapsibleW w (toBool# expanded) title) (runReport w r))

box : Report f z -> Report f z
box r = wrap "boxed" r

grid : List (List (Report f z)) -> Report f z
grid d = Report (w -> liftM (wm w) (gridW w) $ travLW w (travLW w (runReport w)) d)

gridRow : String -> Report f z -> List (Report f z)
gridRow l r = [ style "fix-width-label" $ atomShown l, r ]

wrap : String -> Report f z -> Report f z
wrap h r = style h ' border (Just r) Nothing Nothing Nothing Nothing

wrapId = wrap "wrapped"

fixW : MagnitudeList -> Report f z -> Report f z
fixW w r = prefW w $ border Nothing Nothing Nothing Nothing (Just r)

hugL : Report f z -> Report f z
hugL r = border Nothing Nothing Nothing Nothing (Just r)
hugLeft = hugL

hugR : Report f z -> Report f z
hugR r = border Nothing Nothing (Just r) Nothing Nothing
hugRight = hugR

hugE = hugR
hugW = hugL

hugTop : Report f z -> Report f z
hugTop r = border Nothing (Just r) Nothing Nothing Nothing

hugBottom : Report f z -> Report f z
hugBottom r = border Nothing Nothing Nothing (Just r) Nothing

hugN = hugTop
hugS = hugBottom

centered : Report f z -> Report f z
centered r = Report (w -> liftM (wm w) (centeredW w) (runReport w r))

floatSides : Report f z -> Report f z -> Report f z
floatSides leftSide rightSide = border Nothing Nothing (Just rightSide) Nothing (Just leftSide)

labeled : String -> String -> Report f z
labeled l c = border (Just $ hugL (text c)) Nothing Nothing Nothing (Just $ fixW [pixelsM 120] (style "fix-width-label" $ text l))

header : String -> Report f z -> Report f z
header title content = section (text title) content

header' : Format_Fmt a -> a -> Report f z -> Report f z
header' f a content = section (fmt f a) content

headerDR = header' dateRange_Fmt


headerScroll : String -> Report f z -> Report f z
headerScroll title content = section (text title) (scroll content)

private
  sectionHeaderAny : Report f z -> (Report f z -> Report f z) -> Report f z
  sectionHeaderAny r ui = padBottom ``12pixels`` . wrap "section-header" . ui . style "h5" ' r
  majorPadding : Report f z -> Report f z
  majorPadding r = (pad' (bottom [pixelsM 12] . left [pixelsM 12] )) $ r

sectionHeader : Report f z -> Report f z
sectionHeader r = sectionHeaderNew . padBottom [pixelsM 2] $ r

sectionHeaderMajor : Report f z -> Report f z
sectionHeaderMajor r = sectionHeaderNew $ majorPadding r

lightGrayUnderline r = borderColorBottom underlineColor r
  
sectionUnderlined : Report f z -> Report f z
sectionUnderlined r =
  stackLeft r emptyReport
  |> pad' (bottom [pixelsM 2] . right [cellsM 9])
  |> borderSizeBottom solid thin
  |> borderColorBottom underlineColor
  |> padBottom ``12pixels``
  
sectionUnderlinedMajor : Report f z -> Report f z
sectionUnderlinedMajor r = sectionUnderlined $ majorPadding r
  
sectionHeaderNew : Report f z -> Report f z
sectionHeaderNew r = sectionUnderlined (style "h5" r)  

sectionContent : Report f z -> Report f z
sectionContent r = padLeft [cellsM 1] r

sectionRibbon : Report f z -> Report f z -> Report f z
sectionRibbon l c = stackLeft l $ centered c

section : Report f z -> Report f z -> Report f z
section hdr r = stack (sectionHeader hdr) (sectionContent r)

topSection : Report f z -> Report f z -> Report f z
topSection hdr r = stack (sectionHeaderMajor hdr) (sectionContent r)

summaryDetail : Report f z -> Report f z -> Report f z
summaryDetail = stackPadded ``12pixels``

stackPadded padding summary detail = stack (padBottom padding (wrapId summary)) detail
stackPad1 = stackPadded [pixelsM 2]
stackPad2 = stackPadded ``4pixels``
stackPad3 = stackPadded ``12pixels``

scrollSection : Report f z -> Report f z -> Report f z
scrollSection hdr body = section hdr (scroll body)

vsepScroll sep lr = scroll $ hugTop (vsep sep lr)

hflowLabeled : List (String, Report f z) -> Report f z
hflowLabeled kvs = hsep hstrut '
  map ((k,v) -> hflowPad2 [style "fix-width-label" (text k), v]) kvs

valueGridN : List (List (String, Report f z)) -> Report f z
valueGridN rows = valueGridNPad rows ``12pixels`` ``6pixels``

-- for excel, it's sometimes useful to manually control the padding
valueGridNPad rows paddingMajor paddingMinor =
  let makeRow [] = []
      makeRow ((k,v) :: t) = style "fix-width-label" (padRight [pixelsM 6, cellsM 1] (text k))
                          :: (hugLeft v |> padRight [pixelsM 12, cellsM 2])
                          :: makeRow t
  in style "value-grid-table" . grid ' map makeRow rows

-- | Displays aligned rows of label, value pairs
-- Labels are left-aligned, values are right-aligned
valueGrid : List (String, Report f z) -> Report f z
valueGrid =
  style "value-grid-table" . grid . map (
    (l, r) -> [style "fix-width-label" $ hflow [text l, hspace3], hugR r])

-- Sometimes you want to have the label be a report, such as when specifying font size.
valueGridR : List (Report f z, Report f z) -> Report f z
valueGridR =
  style "value-grid-table" . grid . map (
    (l, r) -> [style "fix-width-label" $ hflow [l, hspace3], hugR r])

-- spacing hack for excel, when autosizing columns means that we don't want buffered space
-- | Displays aligned rows of label, value pairs
-- Labels are left-aligned, values are right-aligned
valueGrid' =
  grid . map ((l, r) -> [style "fix-width-label" $ hflow [text l, hspace3'], hugR r])


-- an automorphism
reportEndo : forall f z . (Writer f z -> a -> z -> z) -> a -> Report f z -> Report f z
reportEndo f a r = Report (w -> liftM (wm w) (f w a) (runReport w r))

prefA : List Area -> Report f z -> Report f z
prefA as r = Report (w -> liftM (wm w) (prefAreaW w as) (runReport w r))

prefW : MagnitudeList -> Report f z -> Report f z
prefW ws r = Report (w -> liftM (wm w) (prefWidthW w ws) (runReport w r))

prefH : MagnitudeList -> Report f z -> Report f z
prefH = reportEndo prefHeightW  -- Report (w -> liftM (wm w) (prefHeightW w hs) (runReport w r))

maxA : List Area -> Report f z -> Report f z
maxA as r = Report (w -> liftM (wm w) (maxAreaW w as) (runReport w r))

maxW : MagnitudeList -> Report f z -> Report f z
maxW ws r = Report (w -> liftM (wm w) (maxWidthW w ws) (runReport w r))

maxH : MagnitudeList -> Report f z -> Report f z
maxH = reportEndo maxHeightW  -- Report (w -> liftM (wm w) (maxHeightW w hs) (runReport w r))


pad' = reportEndo padW
pad opt = pad' (setAllBorders opt)
padTop opt = pad' (top opt)
padBottom opt = pad' (bottom opt)
padLeft opt = pad' (left opt)
padRight opt = pad' (right opt)

borderSize : LineStyle -> LineThickness -> Report f z -> Report f z
borderSize ls lt = borderSize' (setAllBorders (ls, lt))
borderSizeTop ls lt = borderSize' (top (ls, lt))
borderSizeBottom ls lt = borderSize' (bottom (ls, lt))
borderSizeLeft ls lt = borderSize' (left (ls, lt))
borderSizeRight ls lt = borderSize' (right (ls, lt))

borderSize' : (BorderOptions (LineStyle, LineThickness) -> BorderOptions (LineStyle, LineThickness)) -> Report f z -> Report f z
borderSize' = reportEndo borderSizeW

borderColor' = reportEndo borderColorW
borderColor opt = borderColor' (setAllBorders opt)
borderColorTop opt = borderColor' (top opt)
borderColorBottom opt = borderColor' (bottom opt)
borderColorLeft opt = borderColor' (left opt)
borderColorRight opt = borderColor' (right opt)

foregroundColor = reportEndo foregroundColorW
backgroundColor = reportEndo backgroundColorW

scroll : Report f z -> Report f z
scroll r = scrollUnpadded ' padRight [pixelsM 6] r

scrollUnpadded : Report f z -> Report f z
scrollUnpadded r = Report (w -> liftM (wm w) (scrollingW w) (runReport w r))

scanRelation : Relational rel => rel r -> (List {..r} -> Report f z) -> Report f z
scanRelation r f = scanRelationInOrder empty r f

scanRelationInOrder : (Has r s, Relational rel) => Sort s -> rel r -> (List {..r} -> Report f z) -> Report f z
scanRelationInOrder srt r f =
  Report (w -> scanRelationW w (toSort# srt) (relation# r) (runReport w . (f . lmap unsafeRecordIn#)))

scan : Relational rel => rel r -> monad -> Cont (Report f z) (List {..r})
scan r _ = Cont (scanRelation r)

scanInOrder : (Has r s, Relational rel) => Sort s -> rel r -> monad -> Cont (Report f z) (List {..r})
scanInOrder srt r _ = Cont (scanRelationInOrder srt r)

runScan : forall f z r . (Monad (Cont r) -> Cont (Report f z) (Report f z)) -> Report f z
runScan report = runCont (report contMonad) id


-- | See SoftRelation.
softRelation : forall a b k v .
               (exists o . o <- (k, v), AsPresentation pr1, AsPresentation pr2)
    => pr1 k a                  -- ^ How to choose and display headings (keys).
    -> Either (Sort k) (Ord {..k}) -- ^ Order keys.
    -- | How to choose and display values.
    -> ({..k} -> SortPriorityAnnotated_Pri (pr2 v b, Maybe (SortStrategy_SS v)))
    -> SoftRelation a b k v
softRelation pr o prv = SoftRelation (asPresentation pr) o (capture . prv)
  where capture ((prv', ss), sp) = ((asPresentation prv', ss), sp)

-- | Simplifying combinator for softRelation; provide defaults for the
-- other pieces of data.
showingValues : AsPresentation pr
             => pr v b -> SortPriorityAnnotated_Pri
                           (pr v b, Maybe (SortStrategy_SS v))
showingValues pr = unsorted_Pri (pr, Nothing)

noTableScrolling  = style "no-table-scrolling"
noTablePagination = style "no-table-pagination"

columnTable : Column (a, Bound (Legend k), p, d) k v
           -> Report f z
columnTable col = Report $ w -> columnTableW w (column# col)

columnTableTransposed : Column (a, Bound (Legend k), p, d) k v
           -> Report f z
columnTableTransposed col = Report $ w -> columnTableTransposedW w (column# col)

columnTable2 : Column (a, Bound (Legend k), p, d) k v
           -> a
           -> Report f z
columnTable2 col rel = Report $ w -> columnTableW w (column# col)

tabular : Relational rel => Maybe (Legend r) -> rel (|..r|) -> Report f z
tabular leg r = Report $ w ->
    tableW w (fmap maybeFunctor legend# leg)
             (maybe (toList# []) initialSort# leg) false# (relation# r)

tabularTransposed : Relational rel => Maybe (Legend r) -> rel (|..r|) -> Report f z
tabularTransposed leg r = Report $ w ->
    tableW w (fmap maybeFunctor legend# leg)
             (maybe (toList# []) initialSort# leg) true# (relation# r)

titled : Report f z -> Report f z -> Report f z
titled hdr r = stack (padBottom ``6pixels`` . style "h5" ' hdr ) r

-- | A tabular with some columns represented as (key(s), value(s))
-- pairs in the database.
keyValueTabular : forall a b i k v r z rel .
                  (r <- (k, v, i), Relational rel)
                  => SoftRelation a b k v  -- ^ Introducing extra columns.
                  -> Maybe (Legend i) -- ^ How to display the "identifier" columns.
                  -> rel (|..r|)            -- ^ Original relation.
                  -> Report f z
keyValueTabular softr@(SoftRelation ks _ _) lg r =
  let defaultLg (hk :: _) = Just $ keys (joinKey softr hk (rheader r))
      defaultLg _ = Nothing
      byKeys ks = maybe (tabular Nothing r)
                        (fklg -> columnTable . fklg
                               . dynamicSchema softr r <| ks)
                        (orMaybe (fmap maybeFunctor formatK lg)
                                 (defaultLg ks))
  in scanRelation (project (rowUsed ks) r) byKeys



private
  data PivotSpec k v = forall s. PivotSpec (Legend s) (Row s) (Fulcrum k v s)

  pivotRow : PivotColumn v -> Row v
  pivotRow (PivotColumn op _ _) = rowUsed op

  dynamicPivot : List {..k} -> ({..k} -> PivotColumn v) -> Maybe (PivotSpec k v)
  dynamicPivot [] _ = Nothing
  dynamicPivot ks f = Just (dynamicPivot' ks f)

  dynamicPivot' : List {..k} -> ({..k} -> PivotColumn v) -> PivotSpec k v
  dynamicPivot' []        _ = error "dynamicPivot': IMPOSSIBLE"
  dynamicPivot' [k]       f = case f k of
    PivotColumn op pr fl -> PivotSpec (legend pr (fieldName fl)) (single_Brace fl) (single_Fulcrum (fl, op, k))
  dynamicPivot' (k :: ks) f = case dynamicPivot' ks f of
    PivotSpec lg rw fu -> case f k of
      PivotColumn op pr fl ->
        PivotSpec (legend pr (fieldName fl) ++_Legend lg) (snoc_Brace rw fl) (snoc_Fulcrum fu (fl, op, k))

  orderedScanner : Either (Sort k) (Ord {..k}) -> rel k -> (List {..k} -> Report f z) -> Report f z
  orderedScanner (Left so) r k = scanRelationInOrder so r k
  orderedScanner (Right o) r k = scanRelation r (k . sort o)

pivotTabular' : forall r k v i f z rel
              . (Relational rel, r <- (k, v, i))
              => DynamicFulcrum k v
              -> Maybe (Legend i)
              -> rel (| ..r |)
              -> Report f z
pivotTabular' (DynamicFulcrum row srt pivotCol) lgnd rel = pivotTabular row srt lgnd pivotCol rel

pivotTabular :  forall r k v i f z rel
             . (Relational rel, r <- (k, v, i))
             => Row k
             -> Either (Sort k) (Ord {..k})
             -> Maybe (Legend i)
             -> ({..k} -> PivotColumn v)
             -> rel (|.. r|)
             -> Report f z
pivotTabular kr srt ml cols rel = orderedScanner srt (project kr rel) go
 where
 go ks = case dynamicPivot ks cols of
   Just (PivotSpec lg rw fu) -> let
       ir = rheader rel ` minus ' kr ` minus ' pivotRow (cols $ head ks)
       idLg = maybe (fromRow ir) id ml
     in tabular (Just (idLg ++_Legend lg)) (pivot fu $ asMem rel)
   Nothing -> case ml of
     Just lg -> tabular (Just lg) (project (legendRow lg) rel)
     Nothing -> tabular Nothing rel
   
drilldownPivotTabular kr srt ml cols labelCol ddl rootf rel = orderedScanner srt (project kr rel) go
 where
 go ks = case dynamicPivot ks cols of
   Just (PivotSpec lg rw fu) -> let
       ir = rheader rel ` minus ' kr ` minus ' pivotRow (cols $ head ks)
       idLg = maybe (fromRow ir) id ml
       pivoted = (pivot fu $ asMem rel)
     in drilldownTable2 (Just (idLg ++_Legend lg)) labelCol ddl pivoted (rootf pivoted)
   Nothing -> case ml of
     Just lg -> tabular (Just lg) (project (legendRow lg) rel)
     Nothing -> tabular Nothing rel


drilldownPivotTabular' (DynamicFulcrum row srt pivotCol) lgnd ddl rootf rel = drilldownPivotTabular row srt lgnd pivotCol ddl rootf rel
   
---------------------------------------------------
-- Selector functions
---------------------------------------------------
dropdown    = selector DropDown
dropdown'    = selector' DropDown
radioButton = selector RadioButton
slider      = selector Slider
button      = button_
input       = input_ inputW


checkBox : Bool -> (Report f z -> Selector f z Bool -> Report f z) -> Report f z
checkBox = checkBox' ""

checkBox' : String -> Bool -> (Report f z -> Selector f z Bool -> Report f z) -> Report f z
checkBox' label initVal kont = selector CheckBox (const label) initVal [True, False] kont

barHeader ui = pad [pixelsM 4] . style "bar-header" ' ui

-- f is monad of the report. z is the underlying object of the report. a is the value we produce.

data Selector f z a = Selector (SelectorEvent z) (SelectorEvent z -> (a -> Report f z) -> Report f z)

on : SelectorEvent z -> Selector f z a -> (a -> Report f z) -> Report f z
on e (Selector _ v) go = v e go

using : Selector f z a -> (a -> Report f z) -> Report f z
using (Selector e v) go = v e go

infixr 5 ||
(||) e1 e2 = orEvent e1 e2

infixl 5 ***
(***) s1 s2 = zipSelector s1 s2

zipSelector : Selector f z a -> Selector f z b -> Selector f z (a, b)
zipSelector (Selector e1 v1) (Selector e2 v2) =
  Selector (orEvent e1 e2) $ e go -> v1 e $ a -> v2 e $ b -> go (a,b)

selectorFunctor = Functor mapSelector

selectorAp : Ap (Selector f z)
selectorAp = Ap unitSelector
                (ff -> mapSelector (uncurry ($)) . zipSelector ff)

{- TODO and then, you can use
sequenceSelector = sequenceA listTraversable selectorAp
-}

mapSelector : (a -> b) -> Selector f z a -> Selector f z b
mapSelector f (Selector e av) = Selector e $ mapSource f av
  where mapSource: (a -> b) -> (SelectorEvent z -> (a -> Report f z) -> Report f z) -> SelectorEvent z -> (b -> Report f z) -> Report f z
        mapSource aToB sel evt bToReport = sel evt $ a -> bToReport (aToB a)

-- | A selector that always yields the given 'a'.
unitSelector : a -> Selector f z a
unitSelector x = Selector live (const (k -> k x))

-- | Combine a list of selectors into a single selector producing the
-- list of all of its values.
--
-- TODO SMRC (identity: sequenceSelector . map unitSelector = unitSelector)?
sequenceSelector : List (Selector f z a) -> Selector f z (List a)
sequenceSelector Nil = unitSelector Nil
sequenceSelector (s :: ss) = seqSel ss $ mapSelector singleton s
    where seqSel (t :: ts) acc = seqSel ts $ mapSelector ((x,y) -> x :: y) (zipSelector t acc)
          seqSel Nil acc = acc

makeSelectors' : (List b -> Report f z) -> (a -> (b -> Selector f z a -> Report f z) -> Report f z) -> List a -> (Report f z -> Selector f z (List a) -> Report f z) -> Report f z
makeSelectors' flow f sss k = msGo sss Nil Nil
    where
      msGo (s :: ss) iacc selacc = f s $ i sel -> msGo ss (i :: iacc) (sel :: selacc)
      msGo Nil iacc selacc = k (flow $ reverse iacc) (sequenceSelector $ selacc)

makeSelectors = makeSelectors' vflow
gridSelectors = makeSelectors' grid
gridSelectorsH hdr = makeSelectors' (rs -> grid (hdr::rs))

parseInput : (String -> Maybe a) -> String -> (Report f z -> Selector f z (Maybe a) -> Report f z) -> Report f z
parseInput parse default f = input_ inputW default $ t s -> f t $ mapSelector parse s

parseInputV : (String -> Either String a) -> String -> (Report f z -> Selector f z (Either String a) -> Report f z) -> Report f z
parseInputV parse default f = input_ inputW default $ t s -> f t $ mapSelector parse s

stringInput : String -> (Report f z -> Selector f z String -> Report f z) -> Report f z
stringInput s f = input_ inputW s $ t s -> f t s

--| create a multi line text input selector
stringAreaInput : String -> (Report f z -> Selector f z String -> Report f z) -> Report f z
stringAreaInput s f = input_ inputAreaW s $ t s -> f t s

intInput default k =
  parseInput (parseInt 10) (toString default) (r s -> k (prefW [pixelsM 30] r) s)
doubleInput = parseInput parseDouble
dateInput   = parseInput parseDate

stackSelector : (Report f z -> Report f z)
             -> ((Report f z -> Selector f z a -> Report f z) -> Report f z)
             -> (Report f z -> Report f z)
             -> (a -> Report f z)
             -> Report f z
stackSelector fmt s hdr body = s ' ui src -> stack
  (fmt (hdr $ normalFont ui))
  (padLeft [cellsM 1] (using src body))

stackIntInput : (Report f z -> Report f z)
             -> Int
             -> (Report f z -> Report f z)
             -> (Int -> Report f z)
             -> Report f z
stackIntInput fmt default hdr body =
  stackSelector fmt (intInput default) hdr (m -> maybe (text "Enter a valid integer") body m)

selectorSection = stackSelector sectionHeader
selectorSectionMajor = stackSelector sectionHeaderMajor
intInputSection = stackIntInput sectionHeader
stackIntInputH5 = stackIntInput (padBottom ``6pixels`` . style "h5")

-- Integer value input selector with custom validation support
intInputV default intValidator k =
  parseInputV intValidator (toString default) (r s -> k (prefW [pixelsM 30] r) s)

stackIntInputV : (Report f z -> Report f z)
             -> (String -> Report f z)
             -> Int
             -> (String -> Either String Int) -- parser / validation function, returns (Left "Error Message") or (Right validatedValue)
             -> (Report f z -> Report f z)
             -> (Int -> Report f z)
             -> Report f z
stackIntInputV fmt' errorFormattingFn default intValidator hdr body = let
  normalReportFn = body
in stackSelector fmt' (intInputV default intValidator) hdr (validatedInput -> either errorFormattingFn normalReportFn validatedInput)

intInputSectionV = stackIntInputV
                     sectionHeader
                     (hugTop . padTop [pixelsM 6, cellsM 0] . padLeft [pixelsM 6, cellsM 0] . text)

-- Integer value input selector with custom validation support
stackIntInputH5V = stackIntInputV
                    (padBottom [pixelsM 6, cellsM 1] . style "h5")
                    (hugTop . padTop [pixelsM 6, cellsM 0] . padLeft [pixelsM 6, cellsM 0] . text)


{--
-- this monstrosity is still being worked out.
parseInput : (String -> Maybe a) -> String -> (Report f z -> Report f z) -> (Report f z -> Report f z) -> (Report f z -> a -> Report f z) -> Report f z
parseInput parse default defaultf failf succf =
      -- if there was a parse error, but the input was the same as the default
      -- then that is not a real error. it's just the default text, which might not be parseable into an 'a'
  let x t (Left True)  = failf    ' style "input-box"   t
      -- however, if there was a parse error and it wasn't the default text
      -- the input box has a legit bad entry.
      x t (Left False) = defaultf ' style "parse-error" t
      -- in the final case, the input did successfully parse into an 'a'
      x t (Right a)    = succf ' style "input-box"   t ' a
  in input default $ t s -> using (fmap selectorFunctor (x -> maybe (Left (x == default)) Right (parse x)) s) (x t)
--}


remoteSelection r sortField default reportFn = scanRelation r $ ts -> let
    recLessFn r1 r2 = primLt# (r1 ! sortField) (r2 ! sortField)
    sortedRecs = sort (fromLess recLessFn) ts
  in maybeHead default (reportFn sortedRecs) sortedRecs

remoteSelectionDescending r sortField default reportFn = scanRelation r $ ts -> let
    recLessFn r1 r2 = primGt# (r1 ! sortField) (r2 ! sortField)
    sortedRecs = sort (fromLess recLessFn) ts
  in maybeHead default (reportFn sortedRecs) sortedRecs


-- private functions for selectors
private
  lit z = Report $ w -> unit (wm w) z

  --selector : SelectorMode -> (a -> String) -> a -> List a -> (Report f z -> Selector f z a -> Report f z) -> Report f z
  selector mode showf default as f = Report $ w ->
    selectorW w (selectorMode# mode) (toPair# ((toPrimExprNel . showf $ default), default)) unit_Fmt (toList# (lmap (a -> toPair# ((toPrimExprNel . showf $ a),a)) as)) (function3 $ sel evt src ->
      runReport w $ (f (lit sel) (Selector evt $ e f2 -> Report $ w -> funcall2# src e (function1 $ runReport w . f2))))

  selector' mode showf default fmt as f = Report $ w ->
    selectorW w (selectorMode# mode) (toPair# ((toPrimExprNel . showf $ default), default)) fmt (toList# (lmap (a -> toPair# ((toPrimExprNel . showf $ a),a)) as)) (function3 $ sel evt src ->
      runReport w $ (f (lit sel) (Selector evt $ e f2 -> Report $ w -> funcall2# src e (function1 $ runReport w . f2))))

  type TextBoxPrim f z = Writer f z -> String ->
                         Function3 z (SelectorEvent z) (Function2 (SelectorEvent z) (Function1 String (f z)) (f z)) (f z) ->
                         f z

  input_ : (TextBoxPrim f z) -> String -> (Report f z -> Selector f z String -> Report f z) -> Report f z
  input_ primf default f = Report $ w ->
    primf w default (function3 $ sel evt src ->
      runReport w $ (f (lit sel) (Selector evt $ e f2 -> Report $ w -> funcall2# src e (function1 $ runReport w . f2))))



  --button_ : Primitive a => a -> Format a -> (Report f z -> SelectorEvent z -> Report f z) -> Report f z
  button_ name f = Report $ w -> buttonW w (toPrimExprNel name) unit_Fmt (function2 $ button evt -> runReport w $ f (lit button) evt)
  button'_ name fmt f = Report $ w -> buttonW w (toPrimExprNel  name) fmt (function2 $ button evt -> runReport w $ f (lit button) evt)

widget: a -> (a -> Report f z) -> (a -> (a -> Report f z) -> Report f z) -> Report f z
widget a view controls = Report $ w -> widgetW w a
  (function2 $ a sink -> runReport w $ controls a (a' -> Report $ w -> funcall1# sink a'))
  (function1 (runReport w . view))

---------------------------------------------------
-- Chart functions
---------------------------------------------------
-- | Deprecated; Use chart from Layout.Report.Keyed instead.
timeSeriesChart : forall x y a r1 r2 r3 r v z rel .
        (exists t . r <- (r1, r2, r3, t), Scaled v, Scaled d,
                   AsPresentation pr1, AsOp op2, AsOp op3, Relational rel)
        => Maybe String
        -> Maybe (Atomic x)
        -> Maybe (Atomic y)
        -> (pr1 r1 a -> op2 r2 d -> op3 r3 v -> rel (|..r|) -> ChartSeries d v)
        -> pr1 r1 a
        -> op2 r2 d
        -> op3 r3 v
        -> rel (|..r|)
        -> Report f z
timeSeriesChart t xl yl series s x y r =
    chart t Vertical defaultChartLegendOptions
      (upgradeAxisLabel xl) unit_Fmt True (scaled Ascending Nothing Nothing Linear)
      (upgradeAxisLabel yl) unit_Fmt True (scaled Ascending Nothing Nothing Linear)
      [series s x y r]

-- | Axis information for a Scaled axis.
scaled : Scaled a
      => SortOrder              -- ^ Direction from origin.
      -> Maybe a                -- ^ Lower bound; computed if Nothing.
      -> Maybe a                -- ^ Upper bound; computed if Nothing.
      -> DisplayScale
      -> Axis a
scaled s l u ds = scaledConstraints# (toSortOrder# s) (ope l) (ope u) (toDisplayScale ds)
    where ope = toMaybe# . fmap maybeFunctor primExpr#

data DisplayScale = Linear | Logarithmic
toDisplayScale : DisplayScale -> DisplayScale#
toDisplayScale Linear = linear#
toDisplayScale Logarithmic = logarithmic#

-- | The default axis for number-y data, sorting ascending with
-- computed axis display bounds.
defaultScaled : forall a . Scaled a => Axis a
defaultScaled = scaled Ascending Nothing Nothing Linear

-- | Axis information for an Unscaled axis.
unscaled : Unscaled a
        => Either SortOrder (a -> a -> Bool) -- ^ Natural or computed (less-than) sort.
        -> Axis a
unscaled = flip unscaledConstraints# empty#_NM . toEitherZ#
         . either (Left . toSortOrder#) (Right . ord# . peify . fromLess)
    where peify f l r = f (unsafePrimExprIn# l) (unsafePrimExprIn# r)

-- | The default axis for discrete data, sorting natural ascending.
defaultUnscaled : forall a . Unscaled a => Axis a
defaultUnscaled = unscaled $ Left Ascending

unscaledDateRange = unscaled $ Right ltStringDateRange

-- | Build a bar chart series.
bar : ChartMode
bar = seriesW bar#

-- | Build a line chart series.
line : ChartMode
line = seriesW line#

-- | Build a step chart series.
step : ChartMode
step = seriesW step#

-- | Build a scatter chart series.
scatter : ChartMode
scatter = seriesW scatter#

-- | Build a stacked bar chart series.
stackedBar : ScaledChartMode
stackedBar = seriesW stackedBar#

-- | Build a stacked area chart series.
stackedArea : ScaledChartMode
stackedArea = seriesW stackedArea#

-- | Build a box-and-whiskers chart series.
boxAndWhiskers : ScaledChartMode
boxAndWhiskers = seriesW boxAndWhiskers#

-- | Deprecated; Use chart from Layout.Report.Keyed instead, with the
-- 'bar' series function.
barChart : forall x y d e r1 r2 r3 r v z rel .
        (exists t . r <- (r1, r2, r3, t), Unscaled e, Scaled v,
                   AsPresentation pr1, AsOp op2, AsOp op3, Relational rel)
        => Maybe String
        -> Maybe (Atomic x)
        -> Maybe (Atomic y)
        -> pr1 r1 d
        -> op2 r2 e
        -> op3 r3 v
        -> rel (|..r|)
        -> Report f z
barChart t xl yl s x y r =
    chart t Vertical defaultChartLegendOptions
      (upgradeAxisLabel xl) unit_Fmt True (unscaled $ Left Ascending)
      (upgradeAxisLabel yl) unit_Fmt True (scaled Ascending Nothing Nothing Linear)
      [bar s x y r]

-- | Build a ChartSeries.
series : forall s x y r sr xr yr sa xa rel .
                (exists o . AsPresentation s, AsOp x, AsOp y, r <- (sr, xr, yr, o), Relational rel)
             => (s sr sa -> x xr xa -> y yr ya -> rel (|..r|) -> ChartSeries xa ya)
             -> s sr sa       -- ^ select the series identifier
             -> x xr xa       -- ^ select category
             -> y yr ya       -- ^ select value
             -> rel (|..r|)   -- ^ underlying relation for above
             -> ChartSeries xa ya
series = id

-- | Apply color to a chart series.  So instead of saying "line x
-- y...", you say "coloredSeries line [colors...] x y...".
coloredSeries : (s sr sa -> xa' -> ya' -> relr -> ChartSeries xa ya)
             -> List ({..sr}, Color)
             -> s sr sa
             -> xa'
             -> ya'
             -> relr
             -> ChartSeries xa ya
coloredSeries comb colors s x y r = comb s x y r |> (ChartSeries _ ct vt ncs) ->
  ChartSeries colors ct vt ncs

-- | Label some category ticks specially.  Stacks with 'coloredSeries'
-- et al.
categoryTickLabels : Unscaled xa
                  => List ({..xr}, {..xr})
                  -> (sa' -> x xr xa -> ya' -> relr -> ChartSeries xa ya)
                  -> (sa' -> x xr xa -> ya' -> relr -> ChartSeries xa ya)
categoryTickLabels ct comb s x y r = comb s x y r |> (ChartSeries colors _ vt ncs) ->
  ChartSeries colors ct vt ncs

-- | Label some value ticks specially.  Stacks with 'coloredSeries',
-- 'categoryTickLabels', et al.
valueTickLabels : Unscaled ya
               => List ({..yr}, {..yr})
               -> (sa' -> xa' -> y yr ya -> relr -> ChartSeries xa ya)
               -> (sa' -> xa' -> y yr ya -> relr -> ChartSeries xa ya)
valueTickLabels vt comb s x y r = comb s x y r |> (ChartSeries colors ct _ ncs) ->
  ChartSeries colors ct vt ncs

-- | Collect multiple ChartSeries into a chart.
chart : forall xa ya .
        ChartOptions xa ya
                     (List (ChartSeries xa ya) -- ^ Series data.
                      -> Report f z)
chart title ori legOpt catL catF catAx catCons valL valF valAx valCons series =
    Report $ flip axisChartW (chartW title ori legOpt catL catF catAx catCons
                                     valL valF valAx valCons series)

drilldownTable : forall r r1 r2 id z v label rel .
                 (exists o . r <- (r1, r2, v), v <- (label, o), Relational rel)
              => Maybe (Legend v)
              -> Field label String
              -> Field r1 id
              -> Field r2 id
              -> rel (|..r|)
              -> Report f z
drilldownTable leg labelColumn parentId childId fact = Report $ w ->
  drilldownTableW w (fmap maybeFunctor legend# leg)
                    (fieldName labelColumn) (fieldName parentId) (fieldName childId)
                    (maybe (toList# []) initialSort# leg)
                    (relation# fact)

drilldownTable2 : forall r r1 r2 id z v label rel .
                 (exists o . Has r r1, Has r v, v <- (label, o), Relational rel)
              => Maybe (Legend v)
              -> Field label String
              -> DrilldownList r1
              -> rel (|..r|)
              -> rel (|..r|)
              -> Report f z
drilldownTable2 leg labelColumn parentChildCols fact roots = Report $ w ->
  drilldownTable2W w (fmap maybeFunctor legend# leg)
                    (fieldName labelColumn)
                    (fromDrilldown parentChildCols)
                    (maybe (toList# []) initialSort# leg)
                    (relation# fact)
                    (relation# roots)

-- | A drilldown tabular with some columns represented as (key(s),
-- value(s)) pairs in the database.
drilldownKeyValueTable : forall k a v b i lbl p c id r z rel .
              (exists o . r <- (k, v, p, c, i), i <- (lbl, o), Relational rel)
              => SoftRelation a b k v  -- ^ Introducing extra columns.
              -> Maybe (Legend i) -- ^ How to display the "identifier" columns.
              -> Field lbl String -- ^ Label column, moved to left.
              -> Field p id       -- ^ Parent ID column.
              -> Field c id       -- ^ Child column.
              -> rel (|..r|)      -- ^ Original relation.
              -> Report f z
drilldownKeyValueTable softr@(SoftRelation ks _ _) lg lbl p c r =
  let defaultLg (hk :: _) = Just $ keys (joinKey softr hk (rheader r) ` minus ' {p, c})
      defaultLg _ = Nothing
      byKeys ks = maybe (tabular Nothing r)
                        (fklg -> columnTable . fklg
                               . drilldown p c . dynamicSchema softr r <| ks)
                        (orMaybe (fmap maybeFunctor formatK lg)
                                 (defaultLg ks))
  in scanRelation (project (rowUsed ks) r) -- TODO use lbl
                  byKeys

-- | A drilldown tabular with some columns represented as (key(s),
-- value(s)) pairs in the database.
{-
drilldownKeyValueTable2 : forall k a v b i i2 lbl r2 r z rel rel2 r3 o2 r4.
              (exists o . r <- (k, v, r2, i),
                          i <- (lbl, o),
                          r2 <- (r3, o2),
                          i2 <- (r2, i),
                          Relational rel,
                          Relation rel2)
              => SoftRelation a b k v  -- ^ Introducing extra columns.
              -> Maybe (Legend i2) -- ^ How to display the "identifier" columns.
              -> Field lbl String -- ^ Label column, moved to left.
              -> DrilldownList r2 -- ^ Parent ID column.
              -> rel (|..r|)      -- ^ Original relation.
              -> rel2 (|..r4|)     -- ^ roots of the forest
              -> Report f z
              -}
drilldownKeyValueTable2 softr@(SoftRelation ks _ _) lg lbl cols r roots =
  let defaultLg (hk :: _) = Just . keys $ joinKey softr hk (minus (rheader r)
                                                                  (toRow cols))
      defaultLg _ = Nothing
      byKeys ks = maybe (tabular Nothing r)
                        (fklg -> columnTable . fklg
                               . drilldown2 cols roots . dynamicSchema softr r <| ks)
                        (orMaybe (fmap maybeFunctor formatK lg)
                                 (defaultLg ks))
  in scanRelation (project (rowUsed ks) r) -- TODO use lbl
                  byKeys

-- | A drilldown tabular with some columns represented as (key(s),
-- value(s), x) pairs in the database.
-- useful for e.g. (key, value, date) pairs
-- TODO: implement.  Current implementation is just drilldownKeyValueTable
drilldownKeyValueDateTable : forall k a v b i lbl p c id r z rel .
              (exists o . r <- (k, v, p, c, i), i <- (lbl, o), Relational rel)
              => SoftRelation a b k v  -- ^ Introducing extra columns.
              -> Maybe (Legend i) -- ^ How to display the "identifier" columns.
              -> Field lbl String -- ^ Label column, moved to left.
              -> Field p id       -- ^ Parent ID column.
              -> Field c id       -- ^ Child column.
              -> Field d x       -- ^ x column.
              -> rel (|..r|)      -- ^ Original relation.
              -> Report f z
drilldownKeyValueDateTable softr@(SoftRelation ks _ _) lg lbl p c d r =
  let defaultLg (hk :: _) = Just $ keys (joinKey softr hk (rheader r) ` minus ' {p, c})
      defaultLg _ = Nothing
      byKeys ks = maybe (tabular Nothing r)
                        (fklg -> columnTable . fklg
                               . drilldown p c . dynamicSchema softr r <| ks)
                        (orMaybe (fmap maybeFunctor formatK lg)
                                 (defaultLg ks))
  in scanRelation (project (rowUsed ks) r) -- TODO use lbl
                  byKeys
--keyedDrilldown : (Relational rel, r <- (key,pid,nid,label,v))
--              => Field pid a
--              -> Field nid a
--              -> Field key k
--              -> (String, Field label String)
--              -> rel r
--              -> Report f z
keyedDrilldown pid nid k v (lbl, lblF) rel =
  drilldownKeyValueTable
    (softRelation k (Left $ ordering {k}) (r -> ((v, Nothing), Unsorted_Pri)))
    (Just (legend lblF lbl)) lblF pid nid rel

treemapChart : forall d id l labels prl pri prs r r1 r2 ivalue svalue z rel.
             (exists o. r <- (labels, ivalue, svalue, r1, r2, o), PrimitiveNum d, AsPresentation prl, AsPresentation pri, AsPresentation prv, Relational rel) =>
             Field r1 id ->
             Field r2 id ->
             prl labels l ->
             pri ivalue d ->
             prs svalue d ->
             rel (|..r|) -> Report f z
treemapChart parentId childId labelPres intensityPres sizePres rel = Report $ w -> treeMap# w (fieldName parentId) (fieldName childId) (asPresentation labelPres) (asPresentation intensityPres) (asPresentation sizePres) (relation# rel)

pieChart : forall d l labels prl prv r value z rel .
           (exists o . r <- (labels, value, o), PrimitiveNum d,
                      AsPresentation prl, AsPresentation prv, Relational rel)
        => String               -- ^ Title.
        -> ChartLegendOptions#      -- ^ Options for the charts legend.
        -> List ({..labels}, Color) -- ^ Color selections.
        -> prl labels l
        -> prv value d          -- ^ Chart values.
        -> rel (|..r|)
        -> Report f z
pieChart title legOpt color labelPres valuePres rel = Report $ w ->
    pieChartW w title legOpt color (asPresentation labelPres) (asPresentation valuePres)
              (relation# rel)
{-
drilldownPieChart2 : forall d prl prd r r0 r1 label lv z rel .
                    (exists t . r <- (r0, label, t), PrimitiveNum d,
                               Has r r1
                               AsPresentation prl, AsPresentation prd, Relational rel)
                 => String
                 -> ChartLegendOptions#     -- ^ Options for the charts legend.
                 -> List ({..label}, Color) -- ^ Color selections.
                 -> prl label lv
                 -> prd r0 d
                 -> DrilldownList r1
                 -> rel (|..r|)
                 -> Report f z -}
drilldownPieChart2 title legOpt color labelPres dataPres parentChildCols fact roots = Report $ w ->
  drilldownPieChart2W w title legOpt color (asPresentation labelPres) (asPresentation dataPres)
                    (fromDrilldown parentChildCols) (relation# fact) (relation# roots)

drilldownPieChart : forall d id prl prd r r0 r1 r2 label lv z rel .
                    (exists t . r <- (r0, r1, r2, label, t), PrimitiveNum d,
                               AsPresentation prl, AsPresentation prd, Relational rel)
                 => String
                 -> ChartLegendOptions#     -- ^ Options for the charts legend.
                 -> List ({..label}, Color) -- ^ Color selections.
                 -> prl label lv
                 -> prd r0 d
                 -> Field r1 id
                 -> Field r2 id
                 -> rel (|..r|)
                 -> Report f z
drilldownPieChart title legOpt color labelPres dataPres parentId childId fact = Report $ w ->
  drilldownPieChartW w title legOpt color (asPresentation labelPres) (asPresentation dataPres)
                     (fieldName parentId) (fieldName childId) (relation# fact)

-- | A drilldown bar chart.
drilldownBarChart : forall f spr sr sa cpr cr ca vpr vr va pi ci id r z rel .
                    (exists o . r <- (sr, cr, vr, pi, ci, o),
                               AsPresentation spr, AsPresentation cpr,
                               AsPresentation vpr, Relational rel)
                 => Maybe String       -- ^ Chart title.
                 -> Direction          -- ^ Orientation.
                 -> ChartLegendOptions# -- ^ Options for the charts legend.
                 -> AxisLabel           -- ^ Category axis label.
                 -> List ({..cr}, {..cr}) -- ^ Tick label overrides on category.
                 -> Axis ca            -- ^ Rules for category axis.
                 -> AxisLabel          -- ^ Value axis label.
                 -> List ({..vr}, {..vr}) -- ^ Tick label overrides on value.
                 -> Axis va            -- ^ Rules for value axis.
                 -> spr sr sa          -- ^ Choose/show series.
                 -> cpr cr ca          -- ^ Choose/show category.
                 -> vpr vr va          -- ^ Choose/show value.
                 -> Field pi id        -- ^ Parent field reference.
                 -> Field ci id        -- ^ Child field reference.
                 -> rel (|..r|)        -- ^ Underlying relation.
                 -> Report f z
drilldownBarChart title ori legOpt catLbl catTo catC datLbl datTo datC ser cat dat parentId childId fact =
  Report $ w -> drilldownBarChartW w
      -- XXX pass something other than Nil here for choosing colors
      (axisChartDataW catLbl unit_Fmt True datLbl unit_Fmt True
                      catC datC title ori legOpt Nil)
      catTo datTo
      (asPresentation ser) (asPresentation cat) (asPresentation dat)
      (fieldName parentId) (fieldName childId) (relation# fact)

-- | A drilldown bar chart with multiple parent child columns.
drilldownBarChart2 : forall f spr sr sa cpr cr ca vpr vr va r2 r z rel .
                    (exists o . r <- (sr, cr, vr, o),
                                Has r r2, AsPresentation spr, AsPresentation cpr,
                                AsPresentation vpr, Relational rel)
                 => Maybe String       -- ^ Chart title.
                 -> Direction          -- ^ Orientation.
                 -> AxisLabel          -- ^ Category axis label.
                 -> List ({..cr}, {..cr}) -- ^ Tick label overrides on category.
                 -> Axis ca            -- ^ Rules for category axis.
                 -> AxisLabel          -- ^ Value axis label.
                 -> List ({..vr}, {..vr}) -- ^ Tick label overrides on value.
                 -> Axis va            -- ^ Rules for value axis.
                 -> spr sr sa          -- ^ Choose/show series.
                 -> cpr cr ca          -- ^ Choose/show category.
                 -> vpr vr va          -- ^ Choose/show value.
                 -> DrilldownList r2   -- ^ Parent/Child column tuples
                 -> rel (|..r|)        -- ^ Underlying relation.
                 -> rel (|..r|)        -- ^ Root nodes of the drilldown tree
                 -> Report f z
drilldownBarChart2 title ori catLbl catTo catC datLbl datTo datC ser cat dat parentChildCols fact root =
  Report $ w -> drilldownBarChart2W w
      -- XXX pass something other than Nil here for choosing colors
      (axisChartDataW catLbl unit_Fmt True datLbl unit_Fmt True
                      catC datC title ori defaultChartLegendOptions Nil)
      catTo datTo
      (asPresentation ser) (asPresentation cat) (asPresentation dat)
      (fromDrilldown parentChildCols) (relation# fact) (relation# root)

defaultChartLegendOptions = defaultChartLegendOptions#
chartLegendOptions = chartLegendOptions#
chartLegendDefaultLocation = chartLegendOptions chartLegendDefaultLocation#
chartLegendBelow = chartLegendDefaultLocation
chartLegendAbove = chartLegendOptions chartLegendAbove#
chartLegendOverlay = chartLegendOptions chartLegendOverlay#
chartLegendRightOverlay = chartLegendOptions chartLegendRightOverlay#
chartLegendRight = chartLegendOptions chartLegendRightNotOverlay#
chartLegendHidden = chartLegendOptions chartLegendHidden#

-- may want to look into how am adding elements to a record - should at runtime
-- check to see if its null and return a NullExpr if that's the case
-- might also want a map_Field : (a -> b) -> Field r a -> Field r b
-- could use this to apply a default value to a Field r (Maybe a)

private
  type SoftRelationSort = Either# (List# (Pair# String SortOrder#))
                                  (Function2 ScalaRecord# ScalaRecord# Bool#)

  -- | SoftRelation helper.
  softKeySort# : Either (Sort k) ({..k} -> {..k} -> Bool) -> SoftRelationSort
  softKeySort# = toEither# . either (Left . toSort#) (Right . function2 . lower2tup)
      where lower2tup f l r = toBool# $ f (stup l) (stup r)
            stup = unsafeRecordIn# . scalaRecordIn#

  type ValuePresentations# v b =
      Function1 ScalaRecord# (Pair# (Pair# (Presentation v b) (SortStrategy# v))
                                   SortPriority#_Pri)

  softValueCtor# : ({..k} -> SortPriorityAnnotated_Pri
                              (Presentation v b, Maybe (SortStrategy_SS v)))
                -> ValuePresentations# v b
  softValueCtor# vs =
    let npair ((pr, ss), sp) =
            toPair# (toPair# (pr, sortStrategy# $
                               maybe (sortBy_SS forward_SS pr) id ss),
                     toSortPriority#_Pri sp)
     in function1 $ npair . vs . unsafeRecordIn# . scalaRecordIn#

  upgradeAxisLabel = maybe NoAxisLabel AxisLabel

  lmap = fmap listFunctor
  wf w = writerFunctor w
  wa w = writerAp w
  wm w = writerMonad w
  travLW : Writer f a -> (b -> f c) -> List b -> f (List c)
  travLW w = traverse listTraversable (wa w)
  seqLW : Writer f a -> List (f b) -> f (List b)
  seqLW w = sequence listTraversable (wm w)
  seqMW : Writer f a -> Maybe (f b) -> f (Maybe b)
  seqMW w = sequence maybeTraversable (wm w)
  fMA : Writer f z -> Maybe (Report f z) -> f (Maybe z)
  fMA w mr = seqMW w (fmap maybeFunctor (runReport w) mr)

  atomW' : Writer f z -> List Font -> Maybe Int -> Format_Fmt a -> a -> z
  atomW' w fonts size fmt a = atomW_' w (toList# fonts) (toMaybe# size) fmt a

  wrappedW : Writer f z -> MagnitudeList ->  Format_Fmt a -> a -> z
  wrappedW w s fmt a = wrappedW_ w (toMagnitudeList# s) fmt a

  wrappedW' : Writer f z -> MagnitudeList -> List Font -> Maybe Int -> Format_Fmt a -> a -> z
  wrappedW' w s fonts size fmt a = wrappedW_' w (toMagnitudeList# s) (toList# fonts) (toMaybe# size) fmt a

  prefAreaW : Writer f z -> List Area -> z -> z
  prefAreaW wr as t = prefA_ wr (toListArea# as) t

  prefHeightW : Writer f z -> MagnitudeList -> z -> z
  prefHeightW wr hs t = prefH_ wr (toMagnitudeList# hs) t

  prefWidthW :  Writer f z -> MagnitudeList -> z -> z
  prefWidthW wr ws t = prefW_ wr (toMagnitudeList# ws) t

  maxAreaW : Writer f z -> List Area -> z -> z
  maxAreaW wr as t = maxA_ wr (toListArea# as) t

  maxHeightW : Writer f z -> MagnitudeList -> z -> z
  maxHeightW wr hs t = maxH_ wr (toMagnitudeList# hs) t

  maxWidthW :  Writer f z -> MagnitudeList -> z -> z
  maxWidthW wr ws t = maxW_ wr (toMagnitudeList# ws) t


  padW wr optsF t = pad_ wr (toBorderOptions# . overAllBorders toMagnitudeList# $ optsF defaultBorderOptions) t

  borderSizeW : Writer f z -> (BorderOptions (LineStyle, LineThickness) -> BorderOptions (LineStyle, LineThickness)) -> z -> z
  borderSizeW wr optsF t = borderSize_ wr (toBorderOptions# . overAllBorders toPair#  $ optsF defaultBorderOptions) t


  borderColorW wr optsF t = borderColor_ wr (toBorderOptions# $ optsF defaultBorderOptions) t
  foregroundColorW = foregroundColor_
  backgroundColorW = backgroundColor_


  spanW : Direction -> Writer f z -> List (MagnitudeList, z) -> z
  spanW Horizontal w xs = horizontalSpanW_ w (toList# (lmap (x -> toPair# (mapFst toMagnitudeList# x)) xs))
  spanW Vertical w xs   = verticalSpanW_ w (toList# (lmap (x -> toPair# (mapFst toMagnitudeList# x)) xs))

  flowW : Direction -> Writer f z -> List z -> z
  flowW Horizontal w l = horizontalFlowW_ w (toList# l)
  flowW Vertical w l   = verticalFlowW_ w (toList# l)

  tabbedW : Writer f z -> List (String, z) -> z
  tabbedW w xs = tabbedW_ w (toList# (lmap toPair# xs))

  sideTabbedW : Writer f z -> List (String, z) -> z
  sideTabbedW w xs = sideTabbedW_ w (toList# (lmap toPair# xs))

  borderW : Writer f z -> Maybe z -> Maybe z -> Maybe z -> Maybe z -> Maybe z -> z
  borderW wr c n s e w = borderW_ wr (toMaybe# c) (toMaybe# n) (toMaybe# s) (toMaybe# e) (toMaybe# w)

  scanRelationW : Writer f z -> Sort# -> Relation# -> (List Record# -> f z) -> f z
  scanRelationW w srt rel f = scanRelationW' w srt rel (function1 (f . fromList#))

  tableW : Writer f z -> Maybe (Legend# String) -> Sort# -> Bool# -> Relation# -> f z
  tableW w leg = tableW_ w (toMaybe# leg)

  drilldownTableW : Writer f z -> Maybe (Legend# String) -> String -> String -> String
                 -> Sort# -> Relation# -> f z
  drilldownTableW w leg =
      drilldownTableW_ w (toMaybe# leg)

  drilldownTable2W : Writer f z -> Maybe (Legend# String) -> String -> List (String, String)
                 -> Sort# -> Relation# -> Relation# -> f z
  drilldownTable2W w leg label cols =
      drilldownTable2W_ w (toMaybe# leg) label (toList# $ lmap toPair# cols)

  gridW : Writer f z -> List (List z) -> z
  gridW w d = gridW_ w (toList# (lmap toList# d))

  foreign
    method "atomDMTL" atomW : forall f z a . Writer f z -> Format_Fmt a -> a -> z
    method "atomFontDMTL" atomW_' : forall f z a . Writer f z -> List# Font -> Maybe# Int -> Format_Fmt a -> a -> z
    method "atomWrappedDMTL" wrappedW_ : forall f z a b . Writer f z -> List# (Magnitude b) -> Format_Fmt a -> a -> z
    method "atomWrappedFontDMTL" wrappedW_' : forall f z a b . Writer f z -> List# (Magnitude b) -> List# Font -> Maybe# Int -> Format_Fmt a -> a -> z
    method "dateToString" formatDate_ : forall f z a b . Writer f z -> Date -> String
    method "scrolling" scrollingW : forall f z . Writer f z -> z -> z
    method "empty" emptyW : forall f z . Writer f z -> z
    method "tableDMTL" tableW_ : forall f z . Writer f z -> Maybe# (Legend# String) -> Sort# -> Bool# -> Relation# -> f z
    method "drilldownTableDMTL" drilldownTableW_ : forall f z . Writer f z -> Maybe# (Legend# String) -> String -> String -> String -> Sort# -> Relation# -> f z
    method "drilldownTableDMTL2" drilldownTable2W_ : forall f z . Writer f z -> Maybe# (Legend# String) -> String -> List# (Pair# String String) -> Sort# -> Relation# -> Relation# -> f z
    method "columnTableDMTL" columnTableW : forall f z . Writer f z -> Table# EAtomic# Relation# -> f z
    method "columnTableTransposedDMTL" columnTableTransposedW : forall f z . Writer f z -> Table# EAtomic# Relation# -> f z
    method "style" styleW : forall f z . Writer f z -> String -> z -> z
    method "prefArea" prefA_ : forall f z a . Writer f z -> List# (Pair# (Magnitude a) (Magnitude a)) -> z -> z
    method "prefHeight" prefH_ : forall f z a. Writer f z -> List# (Magnitude a) -> z -> z
    method "prefWidth" prefW_ : forall f z a. Writer f z -> List# (Magnitude a) -> z -> z
    method "maxArea" maxA_ : forall f z a . Writer f z -> List# (Pair# (Magnitude a) (Magnitude a)) -> z -> z
    method "maxHeight" maxH_ : forall f z a. Writer f z -> List# (Magnitude a) -> z -> z
    method "maxWidth" maxW_ : forall f z a. Writer f z -> List# (Magnitude a) -> z -> z
    method "pad" pad_: forall f z a . Writer f z -> BorderOptions# (List# (Magnitude a)) -> z -> z
    method "borderSize" borderSize_ : forall f z a . Writer f z -> BorderOptions# (Pair# LineStyle LineThickness) -> z -> z
    method "borderColor" borderColor_: forall f z a . Writer f z ->  BorderOptions# Color -> z -> z
    method "foregroundColor" foregroundColor_: forall f z a . Writer f z -> Color -> z -> z
    method "backgroundColor" backgroundColor_: forall f z a . Writer f z -> Color -> z -> z
    method "horizontalSpan" horizontalSpanW_ : forall f z a . Writer f z -> List# (Pair# (List# (Magnitude a)) z) -> z
    method "verticalSpan" verticalSpanW_ : forall f z a . Writer f z     -> List# (Pair# (List# (Magnitude a)) z) -> z
    method "horizontalFlow" horizontalFlowW_ : forall f z . Writer f z -> List# z -> z
    method "verticalFlow" verticalFlowW_ : forall f z . Writer f z -> List# z -> z
    method "collapsible" collapsibleW : forall f z . Writer f z -> Bool# -> String -> z -> z
    method "tree" treeW_ : forall f z . Writer f z -> z -> Tree_T z -> z
    method "tabbed" tabbedW_ : forall f z . Writer f z -> List# (Pair# String z) -> z
    method "sideTabbed" sideTabbedW_ : forall f z . Writer f z -> List# (Pair# String z) -> z
    method "border" borderW_ : forall f z . Writer f z -> Maybe# z -> Maybe# z -> Maybe# z -> Maybe# z -> Maybe# z -> z
    method "centered" centeredW : forall f z . Writer f z -> z -> z
    method "scanRelationDMTL" scanRelationW' : forall f z . Writer f z -> Sort# -> Relation# -> Function1 (List# Record#) (f z) -> f z
    method "grid" gridW_ : forall f z . Writer f z -> List# (List# z) -> z
    method "selector" selectorW: forall f z a b . Writer f z -> SelectorMode# -> Pair# (NonEmpty# PrimExpr# ) a -> Format_Fmt b -> List# (Pair# (NonEmpty# PrimExpr# ) a) ->
                                    Function3 z (SelectorEvent z) (Function2 (SelectorEvent z) (Function1 a (f z)) (f z)) (f z) ->
                                    f z
    method "textBox" inputW: TextBoxPrim f z
    method "textArea" inputAreaW: TextBoxPrim f z
    method "foreignSelector" foreignSelectorW: forall f z a . Writer f z -> String -> a -> Function1 a (f z) -> f z

    method "foreignSink" foreignSinkW: forall f z a . Writer f z -> String -> Function1 (Function1 a (f z)) (f z) -> f z

    method "widget" widgetW: forall f z a . Writer f z -> a ->         -- state: S
                                    Function2 a (Function1 a (f z)) (f z) -> -- controls: S => (S => F[HJS]) => F[HJS]
                                    Function1 a (f z) -> f z           -- view: S => F[HJS]
    method "button" buttonW : forall f z a . Writer f z -> NonEmpty# PrimExpr# -> Format_Fmt a -> Function2 z (SelectorEvent z) (f z) -> f z
    method "image" imageW : forall f z a . Writer f z -> String -> Maybe# String -> z -- TODO : is this right?
