package com.clarifi.reporting

import java.util.{Date, UUID}
import scala.runtime.{AbstractFunction1 => abs_=>}

import scalaz.{@@, Equal, Ordering, Order, Semigroup, Show, Scalaz, Validation}
import scalaz.Tags.Disjunction
import scalaz.std.option._
import scalaz.syntax.bind._
import scalaz.syntax.show._
import Show._
import Equal._
import Order._

abstract sealed class PrimT {
  type Value
  def isa(that: PrimT): Boolean
  def sup(that: PrimT): Option[PrimT]
  def nullable: Boolean
  def withNull: PrimT
  def withoutNull: PrimT
  def name: String
  def primType: PrimType[_]
}

object PrimT {
  type Type = com.clarifi.reporting.PrimT
  type Union = Option[PrimT] @@ Disjunction

  private def nullify(nullable: Boolean, ty: PrimType[_]): PrimType[_] =
    if (nullable) PrimType primOption ty else ty

  /** Variant for PrimT classes that only have a `nullable` member.
    */
  sealed abstract class WithNullable[PT <: PrimT] extends PrimT {
    // NB: always use lazy val for implementers; otherwise, would be
    // circular
    private[PrimT] val PTCtor: WithNullableCompanion[PT]
    import PTCtor.ptClassTag
    final override def isa(that: PrimT) =
      that match {
        case PTCtor(n) => nullable <= n
        case _ => false
      }

    final override def sup(that: PrimT): Option[PrimT] =
      that match {
        case PTCtor(n) => Some(PTCtor(nullable || n))
        case _ => None
      }

    final override def withNull: PrimT = PTCtor.nullableInstance
    final override def withoutNull: PrimT = PTCtor.strictInstance
    final override def toString = name + "T(" + nullable + ")"
    final override val hashCode = (name,nullable).hashCode
  }

  /** Variant for PrimT companion objects where the companion class only
    * has a `nullable` member.
    */
  sealed abstract class WithNullableCompanion[PT <: PrimT](implicit val ptClassTag: reflect.ClassTag[PT])
      extends (Boolean abs_=> PT) {
    private[PrimT] val strictInstance: PT
    private[PrimT] val nullableInstance: PT
    final def apply(b: Boolean = false): PT =
      if (b) nullableInstance else strictInstance
    final def unapply(pt: PT): Some[Boolean] = Some(pt.nullable)
  }

  final class ByteT private(val nullable: Boolean = false)
      extends WithNullable[ByteT] {
    type Value = Byte
    private[PrimT] lazy val PTCtor: WithNullableCompanion[ByteT] = ByteT
    def name = "Byte"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object ByteT extends WithNullableCompanion[ByteT] {
    private[PrimT] override val strictInstance : ByteT = new ByteT(false)
    private[PrimT] override val nullableInstance : ByteT = new ByteT(true)
  }

  final class ShortT private(val nullable: Boolean = false)
      extends WithNullable[ShortT] {
    type Value = Short
    private[PrimT] lazy val PTCtor: WithNullableCompanion[ShortT] = ShortT
    def name = "Short"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object ShortT extends WithNullableCompanion[ShortT] {
    private[PrimT] override val strictInstance : ShortT = new ShortT(false)
    private[PrimT] override val nullableInstance : ShortT = new ShortT(true)
  }

  final class IntT private(val nullable: Boolean = false)
      extends WithNullable[IntT] {
    type Value = Int
    private[PrimT] lazy val PTCtor: WithNullableCompanion[IntT] = IntT
    def name = "Int"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object IntT extends WithNullableCompanion[IntT] {
    private[PrimT] override val strictInstance : IntT = new IntT(false)
    private[PrimT] override val nullableInstance : IntT = new IntT(true)
  }

  final class LongT private(val nullable: Boolean = false)
      extends WithNullable[LongT] {
    type Value = Long
    private[PrimT] lazy val PTCtor: WithNullableCompanion[LongT] = LongT
    def name = "Long"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object LongT extends WithNullableCompanion[LongT] {
    private[PrimT] override val strictInstance : LongT = new LongT(false)
    private[PrimT] override val nullableInstance : LongT = new LongT(true)
  }

  final class StringT private(val len: Int, val nullable: Boolean = false) extends PrimT {
    type Value = String
    def isa(that: PrimT) = that match {
      case StringT(l, n) => (len <= l) && (nullable <= n)
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case StringT(l, n) => Some(StringT(if (len == 0 || l == 0) 0
                                        else len max l, nullable || n))
      case _ => None
    }
    def withNull = if (nullable) this else StringT(len, true)
    def withoutNull = if (!nullable) this else StringT(len, false)
    def name = "String"
    def primType = nullify(nullable, PrimType primString len)
    override def toString = name + "T(" + len + "," + nullable + ")"
    override def equals(o: Any) = o match {
      case o: StringT => len == o.len && nullable == o.nullable
      case _ => false
    }
    final override val hashCode = (name, len, nullable).hashCode
  }
  object StringT {
    private val strictStringT : StringT = new StringT(0, false)
    private val nullableStringT : StringT = new StringT(0, true)
    def apply(len: Int, b: Boolean = false) =
      if (len == 0)
        if (b) nullableStringT else strictStringT
      else new StringT(len, b)
    def unapply(st: StringT): Some[(Int, Boolean)] =
      Some((st.len, st.nullable))
  }

  final class DateT private(val nullable: Boolean = false)
      extends WithNullable[DateT] {
    type Value = Date
    private[PrimT] lazy val PTCtor: WithNullableCompanion[DateT] = DateT
    def name = "Date"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object DateT extends WithNullableCompanion[DateT] {
    private[PrimT] override val strictInstance : DateT = new DateT(false)
    private[PrimT] override val nullableInstance : DateT = new DateT(true)
  }

  final class DoubleT private(val nullable: Boolean = false)
      extends WithNullable[DoubleT] {
    type Value = Double
    private[PrimT] lazy val PTCtor: WithNullableCompanion[DoubleT] = DoubleT
    def name = "Double"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object DoubleT extends WithNullableCompanion[DoubleT] {
    private[PrimT] override val strictInstance : DoubleT = new DoubleT(false)
    private[PrimT] override val nullableInstance : DoubleT = new DoubleT(true)
  }

  final class BooleanT private(val nullable: Boolean = false)
      extends WithNullable[BooleanT] {
    type Value = Boolean
    private[PrimT] lazy val PTCtor: WithNullableCompanion[BooleanT] = BooleanT
    def name = "Bool"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object BooleanT extends WithNullableCompanion[BooleanT] {
    private[PrimT] override val strictInstance : BooleanT = new BooleanT(false)
    private[PrimT] override val nullableInstance : BooleanT = new BooleanT(true)
  }

  final class UuidT private(val nullable: Boolean = false)
      extends WithNullable[UuidT] {
    type Value = UUID
    private[PrimT] lazy val PTCtor: WithNullableCompanion[UuidT] = UuidT
    def name = "UUID"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object UuidT extends WithNullableCompanion[UuidT] {
    private[PrimT] override val strictInstance : UuidT = new UuidT(false)
    private[PrimT] override val nullableInstance : UuidT = new UuidT(true)
  }

  def withName(s: String): PrimT = s match {
    case "Int"    => IntT  (false)
    case "Byte"   => ByteT (false)
    case "Short"  => ShortT(false)
    case "Long"   => LongT(false)
    case "String" => StringT(0, false)
    case "Date"   => DateT(false)
    case "Double" => DoubleT(false)
    case "Bool"   => BooleanT(false)
    case "UUID"   => UuidT(false)
  }

  def coerce(p:PrimT, s: String): Validation[Throwable, Any] = Validation.fromTryCatch(p match {
    case IntT(_)       => s.toInt
    case ByteT(_)      => s.toByte
    case ShortT(_)     => s.toShort
    case LongT(_)      => s.toLong
    case StringT(_, _) => s
    /**
     * TODO
     * Stephen would also strongly suggest, building from "Calendar getInstance ymdPivotTimeZone"
     * otherwise equality turns really dumb
     */
    case DateT(_)      => new java.text.SimpleDateFormat("YYYY/mm/dd").parse(s)
    case DoubleT(_)    => s.toDouble
    case BooleanT(_)   => s.toBoolean
    case UuidT(_)      => java.util.UUID.fromString(s)
  })

  implicit val PrimTEqual: Equal[PrimT] = equalA[PrimT]
  implicit val PrimTShow: Show[PrimT] = showA
  implicit val PrimTOrder: Order[PrimT] = implicitly[Order[String]].contramap(_.shows)

  /** `sup` forms a semigroup. */
  implicit val PrimTUnion: Semigroup[Union] = new Semigroup[Union] {
    def append(l: Union, r: => Union): Union =
      Disjunction(^(l, r)(_ sup _)(optionInstance).join)
  }

  def isNumeric(p:PrimT): Boolean = p match {
    case x: ByteT   => true
    case x: ShortT  => true
    case x: IntT    => true
    case x: LongT   => true
    case x: DoubleT => true
    case _ => false
  }

  private object Parsing extends scalaparsers.Parsing[Unit]

  def read(s: String): PrimT = {
    import scalaparsers.{ParseState, Pos}
    import Parsing.{word, token, paren, ch, nat, parserMonad, Parser}

    val comma = token(ch(','))
    val bool = (word("true") as true) | (word("false") as false)
    val strt : Parser[PrimT] = word("StringT") >> paren(for { n <- nat ; _ <- comma ; b <- bool } yield StringT(n.toInt, b))
    val nstr : Parser[Boolean => PrimT] =
      ("ByteT"    as (ByteT))    |
      ("ShortT"   as (ShortT))   |
      ("IntT"     as (IntT))     |
      ("LongT"    as (LongT))    |
      ("DoubleT"  as (DoubleT))  |
      ("BooleanT" as (BooleanT)) |
      ("DateT"    as (DateT))    |
      ("UuidT"    as (UuidT))

    val main : Parser[PrimT] = strt | (for { c <- nstr ; b <- paren(bool) } yield c(b))

    // this is ugly; using a null as a supply is better than creating a supply here though
    main.run(ParseState(Pos("","",0,0,false), s, s = ()), null) match {
      case Right((_, x)) => x
      case _             => sys.error("Failed to read PrimT: \"" + s + "\"")
    }
  }
}
