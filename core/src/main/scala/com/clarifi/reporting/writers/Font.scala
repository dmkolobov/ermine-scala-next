package com.clarifi.reporting.writers

import scala.collection.Set
import java.awt.GraphicsEnvironment

sealed abstract class Font() {
  def getFont : Option[String]
}

class FontName(name: String) extends Font() {
  def getFont = Option(name)
}
class FontByGenre(genre: FontGenre) extends Font() {
  def getFont = genre.getAvailableFont()
}

sealed abstract class FontGenre{
  def fonts:Set[String]

  lazy val availableFonts: Set[String] =
    GraphicsEnvironment.getLocalGraphicsEnvironment.getAllFonts.toSet.map( (f:java.awt.Font) => f.getFamily )

  def getAvailableFont(): Option[String] =
    fonts.intersect(availableFonts).headOption
}
case class Serif() extends FontGenre(){
  def fonts = OldStyle().fonts ++ Transitional().fonts ++ Didone().fonts ++ SlabSerif().fonts
}

case class SansSerif() extends FontGenre(){
  def fonts = Humanist().fonts ++ Grotesque().fonts ++ NeoGrotesque().fonts ++ Geometric().fonts
}

case class Monospaced() extends FontGenre(){
  def fonts = Set("DejaVu Sans Mono", "Consolas", "Monaco", "Lucida Console", "Bitstream Vera Sans Mono", "Andale Mono")
}

// Fonts with fairly complete (> 10,000 glyphs) unicode support
case class Unicode() extends FontGenre(){
  def fonts = Set( "Unifont", "Arial Unicode MS", "Bitstream Cyberbit", "DejaVu MS")
}

// TODO: perhaps UnicodeMath, for fonts with fairly complete renderings of latex math symbols?

// the major groups of sans serif fonts
case class Humanist() extends FontGenre(){
  def fonts = Set("Gill Sans", "Trebuchet MS", "Verdana", "Calabri", "Tahoma", "DejaVu Sans", "Bitstream Vera Sans")
}
case class Grotesque() extends FontGenre(){
  def fonts = Set("Monotype Grotesque", "Geneva", "Franklin Gothic", "Eurostile")
}
case class NeoGrotesque() extends FontGenre(){
  def fonts = Set("MS Sans Serif", "Arial", "Impact", "Helvetica")
}
case class Geometric() extends FontGenre(){
  def fonts = Set("Futura", "Gotham", "Century Gothic", "Bank Gothic", "Avenir")
}


// the major groups of serif fonts
case class OldStyle() extends FontGenre() {
  def fonts = Set("Garamond","Goudy Old Style", "Perpetua", "Palatino")
}
case class Transitional() extends FontGenre() {
  def fonts = Set("Times New Roman", "Baskerville", "Cambria", "Georgia")
}
case class Didone() extends FontGenre() {
  def fonts = Set("Didot", "Bodoni", "Walbaum")
}
case class SlabSerif() extends FontGenre(){
  def fonts = Set("Courier", "Egyptienne", "Alexandria", "Concrete Roman")
}
