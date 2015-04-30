module Layout.Font where

import Function

foreign
  data "com.clarifi.reporting.writers.Font" Font

  private data "com.clarifi.reporting.writers.FontName" FontName#
  private constructor fontName# : String -> FontName#
  private subtype FontName : FontName# -> Font

  private data "com.clarifi.reporting.writers.FontByGenre" FontByGenre#
  private constructor fontGenre# : FontGenre -> FontByGenre#
  private subtype FontByGenre : FontByGenre# -> Font

  data "com.clarifi.reporting.writers.FontGenre" FontGenre

  private data "com.clarifi.reporting.writers.SansSerif" SansSerif#
  private constructor sansSerifC : SansSerif#
  private subtype SansSerif : SansSerif# -> FontGenre

  private data "com.clarifi.reporting.writers.Serif" Serif#
  constructor serifC : Serif#
  subtype Serif : Serif# -> FontGenre

  private data "com.clarifi.reporting.writers.Monospaced" Monospaced#
  constructor monospacedC : Monospaced#
  subtype Monospaced : Monospaced# -> FontGenre

  private data "com.clarifi.reporting.writers.Unicode" Unicode#
  constructor unicodeC : Unicode#
  subtype Unicode : Unicode# -> FontGenre

  private data "com.clarifi.reporting.writers.Humanist" Humanist#
  constructor humanistC : Humanist#
  subtype Humanist : Humanist# -> FontGenre

  private data "com.clarifi.reporting.writers.Grotesque" Grotesque#
  constructor grotesqueC : Grotesque#
  subtype Grotesque : Grotesque# -> FontGenre

  private data "com.clarifi.reporting.writers.NeoGrotesque" NeoGrotesque#
  constructor neoGrotesqueC : NeoGrotesque#
  subtype NeoGrotesque : NeoGrotesque# -> FontGenre

  private data "com.clarifi.reporting.writers.Geometric" Geometric#
  constructor geometricC : Geometric#
  subtype Geometric : Geometric# -> FontGenre

  private data "com.clarifi.reporting.writers.OldStyle" OldStyle#
  constructor oldStyleC : OldStyle#
  subtype OldStyle : OldStyle# -> FontGenre

  private data "com.clarifi.reporting.writers.Transitional" Transitional#
  constructor transitionalC : Transitional#
  subtype Transitional : Transitional# -> FontGenre

  private data "com.clarifi.reporting.writers.Didone" Didone#
  constructor didoneC : Didone#
  subtype Didone : Didone# -> FontGenre

  private data "com.clarifi.reporting.writers.SlabSerif" SlabSerif#
  constructor slabSerifC : SlabSerif#
  subtype SlabSerif : SlabSerif# -> FontGenre

fontGenre = FontByGenre . fontGenre#
fontName = FontName . fontName#

serif = fontGenre . Serif $ serifC
sansSerif = fontGenre . SansSerif $ sansSerifC
monospaced = fontGenre . Monospaced $ monospacedC
unicode = fontGenre . Unicode $ unicodeC
humanist = fontGenre . Humanist $ humanistC
grotesque = fontGenre . Grotesque $ grotesqueC
neoGrotesque = fontGenre . NeoGrotesque $ neoGrotesqueC
geometric = fontGenre . Geometric $ geometricC
oldStyle = fontGenre . OldStyle $ oldStyleC
transitional = fontGenre . Transitional $ transitionalC
didone = fontGenre . Didone $ didoneC
slabSerif = fontGenre . SlabSerif $ slabSerifC

timesNewRoman = fontName "Times New Roman"
gillSans = fontName "Gill Sans"
dejaVuSans = fontName "DejaVu sans"
verdana  = fontName "Verdana"
arial = fontName "Arial"

