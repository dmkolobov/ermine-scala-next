package com.clarifi.reporting

import scalaz.NonEmptyList
import org.scalacheck._
import Arbitrary.arbitrary
import java.util.Date
import java.util.UUID

object Gens {

  // generate a fresh type 4 UUID
  implicit val arbitraryUuid : Arbitrary[UUID] = Arbitrary(
    for { 
      a <- Gen.choose(0L, 0xFFFFFFFFFFFFL)
      b <- Gen.choose(0L, 0xFFFL) 
      c <- Gen.choose(0x8000000000000000L, 0xBFFFFFFFFFFFFFFFL)
    } yield new UUID((a << 4) | 0x4000L | b, c)
  )

  val DefaultMaxStringSize: Int = 10

  /** Represents 1/1/1902 in milliseconds */
  private val MinDate: Long = -2145898800000L

  /** Represents 2/5/2038 in milliseconds */
  private val MaxDate: Long = 2148958800000L

  /** A generator for Strings of non-zero length */
  def string(len: Int = DefaultMaxStringSize): Gen[String] = for {
    upper <- Gen.alphaLowerChar
    size <- Gen.choose(1, len)
    xs <- Gen.listOfN(size, Gen.alphaNumChar)
  } yield (upper :: xs).mkString.toLowerCase

  /**
   * A generator for dates between 1/1/1902 and 2/5/2038. These dates
   * were selected because they are the min and max dates downstream.
   */
  def date: Gen[Date] = Gen.choose(MinDate, MaxDate).map(new Date(_))

  /** A generator that draws a random positive number of elements from a non-empty list. */
  def atLeastOneOf[T](l: NonEmptyList[T]) = Gen.choose(1,l.list.toList.size) flatMap (Gen.pick(_,l.list.toList))
  
  def choose(lower: Int, upper: Int): Gen[Int] = {
    if (lower > upper) sys.error("Empty choose bounds: [" + lower + ", "+ upper + "]")
    else Gen.choose(lower, upper)
  }
}
