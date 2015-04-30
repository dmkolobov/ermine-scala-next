package  com.clarifi.reporting.writers

case class BorderOptions[A](top: Option[A], right: Option[A], bottom: Option[A], left: Option[A])

sealed abstract class LineStyle()
case class Dotted() extends LineStyle
case class Dashed() extends LineStyle
case class Solid() extends LineStyle
sealed abstract class LineThickness()
case class Thin() extends LineThickness
case class Thick() extends LineThickness
case class Medium() extends LineThickness
