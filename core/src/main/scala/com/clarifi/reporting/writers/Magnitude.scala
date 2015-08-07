package com.clarifi.reporting.writers

// Use phantom type to constrain (Mag, Mag) to use the same units
sealed abstract class Magnitude
object Magnitude {
  type Area = (Magnitude, Magnitude)
  type Volume = (Magnitude, Magnitude, Magnitude)
}

// other possibly interesting units...
// https://developer.mozilla.org/en-US/docs/Web/CSS/length
case class Inches(mag: Double) extends Magnitude
case class Centimeters(mag: Double) extends Magnitude
case class Points(mag: Double) extends Magnitude

case class Cells(mag: Int) extends Magnitude
case class Pixels(mag: Int) extends Magnitude
case class Dimensionless(mag: Double) extends Magnitude

