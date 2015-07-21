package com.clarifi.reporting

import java.util.{Date, UUID}

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

  final class ByteT private(val nullable: Boolean = false) extends PrimT {
    type Value = Byte
    def isa(that: PrimT) = that match {
      case ByteT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case ByteT(n) => Some(ByteT(nullable || n))
      case _ => None
    }
    def withNull = ByteT.nullableByteT
    def withoutNull = ByteT.strictByteT
    def name = "Byte"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object ByteT {
    private val strictByteT : ByteT = new ByteT(false)
    private val nullableByteT : ByteT = new ByteT(true)
    def apply(b: Boolean = false) = if (b) nullableByteT else strictByteT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : ByteT => Some(pt.nullable)
      case _ => None
    }
  }

  final class ShortT private(val nullable: Boolean = false) extends PrimT {
    type Value = Short
    def isa(that: PrimT) = that match {
      case ShortT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case ShortT(n) => Some(ShortT(nullable || n))
      case _ => None
    }
    def withNull = ShortT.nullableShortT
    def withoutNull = ShortT.strictShortT
    def name = "Short"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object ShortT {
    private val strictShortT : ShortT = new ShortT(false)
    private val nullableShortT : ShortT = new ShortT(true)
    def apply(b: Boolean = false) = if (b) nullableShortT else strictShortT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : ShortT => Some(pt.nullable)
      case _ => None
    }
  }

  final class IntT private(val nullable: Boolean = false) extends PrimT {
    type Value = Int
    def isa(that: PrimT) = that match {
      case IntT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case IntT(n) => Some(IntT(nullable || n))
      case _ => None
    }
    def withNull = IntT.nullableIntT
    def withoutNull = IntT.strictIntT
    def name = "Int"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object IntT {
    private val strictIntT : IntT = new IntT(false)
    private val nullableIntT : IntT = new IntT(true)
    def apply(b: Boolean = false) = if (b) nullableIntT else strictIntT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : IntT => Some(pt.nullable)
      case _ => None
    }
  }

  final class LongT private(val nullable: Boolean = false) extends PrimT {
    type Value = Long
    def isa(that: PrimT) = that match {
      case LongT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case LongT(n) => Some(LongT(nullable || n))
      case _ => None
    }
    def withNull = LongT.nullableLongT
    def withoutNull = LongT.strictLongT
    def name = "Long"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object LongT {
    private val strictLongT : LongT = new LongT(false)
    private val nullableLongT : LongT = new LongT(true)
    def apply(b: Boolean = false) = if (b) nullableLongT else strictLongT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : LongT => Some(pt.nullable)
      case _ => None
    }
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
  }
  object StringT {
    private val strictStringT : StringT = new StringT(0, false)
    private val nullableStringT : StringT = new StringT(0, true)
    def apply(len: Int, b: Boolean = false) =
      if (len == 0)
        if (b) nullableStringT else strictStringT
      else new StringT(len, b)
    def unapply(pt: PrimT): Option[(Int, Boolean)] = pt match {
      case st : StringT => Some((st.len, st.nullable))
      case _ => None
    }
  }

  final class DateT private(val nullable: Boolean = false) extends PrimT {
    type Value = Date
    def isa(that: PrimT) = that match {
      case DateT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case DateT(n) => Some(DateT(nullable||n))
      case _ => None
    }
    def withNull = DateT.nullableDateT
    def withoutNull = DateT.strictDateT
    def name = "Date"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object DateT {
    private val strictDateT : DateT = new DateT(false)
    private val nullableDateT : DateT = new DateT(true)
    def apply(b: Boolean = false) = if (b) nullableDateT else strictDateT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : DateT => Some(pt.nullable)
      case _ => None
    }
  }

  final class DoubleT private(val nullable: Boolean = false) extends PrimT {
    type Value = Double
    def isa(that: PrimT) = that match {
      case DoubleT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case DoubleT(n) => Some(DoubleT(nullable||n))
      case _ => None
    }
    def withNull = DoubleT.nullableDoubleT
    def withoutNull = DoubleT.strictDoubleT
    def name = "Double"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object DoubleT {
    private val strictDoubleT : DoubleT = new DoubleT(false)
    private val nullableDoubleT : DoubleT = new DoubleT(true)
    def apply(b: Boolean = false) = if (b) nullableDoubleT else strictDoubleT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : DoubleT => Some(pt.nullable)
      case _ => None
    }
  }

  final class BooleanT private(val nullable: Boolean = false) extends PrimT {
    type Value = Boolean
    def isa(that: PrimT) = that match {
      case BooleanT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case BooleanT(n) => Some(BooleanT(nullable||n))
      case _ => None
    }
    def withNull = BooleanT.nullableBooleanT
    def withoutNull = BooleanT.strictBooleanT
    def name = "Bool"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object BooleanT {
    private val strictBooleanT : BooleanT = new BooleanT(false)
    private val nullableBooleanT : BooleanT = new BooleanT(true)
    def apply(b: Boolean = false) = if (b) nullableBooleanT else strictBooleanT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : BooleanT => Some(pt.nullable)
      case _ => None
    }
  }

  final class UuidT private(val nullable: Boolean = false) extends PrimT {
    type Value = UUID
    def isa(that: PrimT) = that match {
      case UuidT(n) => nullable <= n
      case _ => false
    }
    def sup(that: PrimT) = that match {
      case UuidT(n) => Some(UuidT(nullable||n))
      case _ => None
    }
    def withNull = UuidT.nullableUuidT
    def withoutNull = UuidT.strictUuidT
    def name = "UUID"
    def primType = nullify(nullable, implicitly[PrimType[Value]])
  }
  object UuidT {
    private val strictUuidT : UuidT = new UuidT(false)
    private val nullableUuidT : UuidT = new UuidT(true)
    def apply(b: Boolean = false) = if (b) nullableUuidT else strictUuidT
    def unapply(pt: PrimT): Option[Boolean] = pt match {
      case _ : UuidT => Some(pt.nullable)
      case _ => None
    }
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

  def read(s: String): PrimT = {
    import scalaparsers.{ParseState, Pos, Supply}
    import ermine.parsing._
    val bool = (word("true") as true) | (word("false") as false)
    val strt : Parser[PrimT] = word("StringT") >> paren(for { n <- nat ; _ <- comma ; b <- bool } yield StringT(n.toInt, b))
    val nstr : Parser[Boolean => PrimT] =
      ("ByteT"    as ByteT.apply _)    |
      ("ShortT"   as ShortT.apply _)   |
      ("IntT"     as IntT.apply _)     |
      ("LongT"    as LongT.apply _)    |
      ("DoubleT"  as DoubleT.apply _)  |
      ("BooleanT" as BooleanT.apply _) |
      ("DateT"    as DateT.apply _)    |
      ("UuidT"    as UuidT.apply _)

    val main : Parser[PrimT] = strt | (for { c <- nstr ; b <- paren(bool) } yield c(b))

    // this is ugly
    main.run(ParseState(Pos("","",0,0,false), s, s = ErParseState("")), Supply.create) match {
      case Right((_, x)) => x
      case _             => sys.error("Failed to read PrimT: \"" + s + "\"")
    }
  }
}
