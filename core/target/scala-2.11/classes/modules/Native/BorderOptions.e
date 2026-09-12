module Native.BorderOptions where

import Layout.BorderOptions
import Native.Maybe

foreign
  data "com.clarifi.reporting.writers.BorderOptions" BorderOptions# a
  private constructor borderOptions : Maybe# a -> Maybe# a -> Maybe# a -> Maybe# a -> BorderOptions# a
  data "com.clarifi.reporting.writers.LineStyle" LineStyle
  data "com.clarifi.reporting.writers.LineThickness" LineThickness

  private data "com.clarifi.reporting.writers.Dotted" Dotted#
  private subtype Dotted : Dotted# -> LineStyle
  private constructor dotted# : Dotted#

  private data "com.clarifi.reporting.writers.Dashed" Dashed#
  private subtype Dashed : Dashed# -> LineStyle
  private constructor dashed# : Dashed#

  private data "com.clarifi.reporting.writers.Solid" Solid#
  private subtype Solid : Solid# -> LineStyle
  private constructor solid# : Solid#

  private data "com.clarifi.reporting.writers.Thick" Thick#
  private subtype Thick : Thick# -> LineThickness
  private constructor thick# : Thick#

  private data "com.clarifi.reporting.writers.Medium" Medium#
  private subtype Medium : Medium# -> LineThickness
  private constructor medium# : Medium#

  private data "com.clarifi.reporting.writers.Thin" Thin#
  private subtype Thin : Thin# -> LineThickness
  private constructor thin# : Thin#

dotted = Dotted dotted#
dashed = Dashed dashed#
solid = Solid solid#
thick = Thick thick#
medium = Medium medium#
thin = Thin thin#

toBorderOptions# (BorderOptions t r b l) = borderOptions (toMaybe# t) (toMaybe# r) (toMaybe# b) (toMaybe# l)
