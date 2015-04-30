package com.clarifi.reporting.writers

// Use phantom type to constrain (Mag, Mag) to use the same units
sealed abstract class Magnitude
object Magnitude {
  type Area = (Magnitude, Magnitude)
  type Volume = (Magnitude, Magnitude, Magnitude)
}

case class Cells(mag: Int) extends Magnitude
case class Pixels(mag: Int) extends Magnitude
case class Dimensionless(mag: Double) extends Magnitude

