module Layout.Format where

{- Description of how to format a result datapoint for display.
   Typically composed in Presentation. -}

import Function using (.); flip
import Native
import Unsafe.Coerce

foreign
  -- Non-codata description of how to display fields, so that writers
  -- can reinterpret them for their media.  The sample formats below
  -- are just approximations; we choose the appropriate display for
  -- the media.
  data "com.clarifi.reporting.writers.Format" Format (a: *)
  -- The default format.
  value "com.clarifi.reporting.writers.Format$Default$" "MODULE$"
      unit : Primitive a => Format a
  -- Format as date range.
  value "com.clarifi.reporting.writers.Format$DateRange$" "MODULE$"
      dateRange : Format (Date, Date)

private foreign
  value "com.clarifi.reporting.writers.Format$Percentage$" "MODULE$"
      percentage## : PrimitiveNum n => Function2 Int Bool# (Format n)
  value "com.clarifi.reporting.writers.Format$Round$" "MODULE$"
      round# : PrimitiveNum n => Function1 Int (Format n)
  value "com.clarifi.reporting.writers.Format$IntegralRound$" "MODULE$"
      integralRound# : PrimitiveNum n => Function1 Int (Format n)
  value "com.clarifi.reporting.writers.Format$Truncate$" "MODULE$"
      truncate# : Primitive a => Function1 Int (Format a)
  -- Renders markdown in strings.  e.g. "[**The Best Link EVAR**](bestaddrever.com)" creates a bold link to bestaddr.com.
  -- Works as a Format transformer, so you can have markdown $ truncate 5 or markdown unit
  value "com.clarifi.reporting.writers.Format$Markdown$" "MODULE$"
      markdown# : Unscaled a => Function1 (Format a) (Format a)
  -- 1.5 -> "USD" -> "$1.50"
  -- As per CFI 21264, in scala-2.9.2 we do not want to actually render the currency symbol
  -- in order to maintain backwards compatibility with java
  -- Make sure this is reverted in default!
  value "com.clarifi.reporting.writers.Format$IntegralRound$" "MODULE$"
      currency# : PrimitiveNum n =>  Function1 Int (Format n)

-- 2 -> 34.7652 -> 34.77
round : PrimitiveNum n => Int -> Format n
round = funcall1# round#

currency s = funcall1# currency# 2

-- exactly the same as round with one exception:
--   if a double is the same as it's int value,
--   then it gets displayed as an int
--     eg:  6.00 -> 6
integralRound : PrimitiveNum n => Int -> Format n
integralRound = funcall1# integralRound#

-- 0.42 -> "42%"
percentage : PrimitiveNum n => Format n
percentage = percentageIntegralRound 2

percentageRound, percentageIntegralRound : PrimitiveNum n => Int -> Format n
percentageRound = percentage# True
percentageIntegralRound = percentage# False

{--
truncate examples, truncating at 10 characters
  10 -> "abcdefghijkl" -> "abcdefg..."  -- input length 12,  output length 10
  10 -> "abcdefghijk"  -> "abcdefg..."  -- input length 11,  output length 10
  10 -> "abcdefghij"   -> "abcdefghij"  -- input length 10,  output length 10
  10 -> "abcdefghi"    -> "abcdefghi"   -- input length  9,  output length  9
--}
truncate : Unscaled a => Int -> Format a
truncate = funcall1# truncate#

markdown : Unscaled a => Format a -> Format a
markdown = funcall1# markdown#

-- Add Nullable to a formatter, as all formatters can format anything.
nullable : Format a -> Format (Nullable a)
nullable = unsafeCoerce

private
  percentage# = flip (funcall2# percentage##) . toBool#
