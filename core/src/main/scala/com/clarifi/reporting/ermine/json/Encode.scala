package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.Runtime.Thunk
import com.clarifi.reporting.{ PrimT, PrimExpr, NullExpr }
import scala.collection.immutable.List
import scala.collection.mutable.ListBuffer
import scala.util.control.NonFatal
import java.time.{ Instant, ZoneOffset }
import java.time.format.DateTimeFormatter

/** The JSON target of the encoder: what a walk over a `Runtime` value can
  * emit.  Two instances: `ArgonautJson` (the wire AST, what the REPL's
  * `:json` and the future document runner use) and `ErmineJson` (the
  * stdlib `Json` data type, what the FFI primitive `toJson#` returns so
  * Ermine code can inspect and rebuild the document).
  *
  * The walker decides the mapping; a builder only supplies nodes.  A
  * relation is the one node the walker cannot build itself (rows need the
  * runner's effect, design note §2.1, §3.4), so `rel` may refuse.
  */
/** How a relation's rows reach the client (design note §3.4a, "switch 1").
  * `ByRequest` is a bare relation (`JRel`, or a `Rel` met anywhere): the
  * request's `data.default` decides.  `Inline` and `Deferred` come from the
  * `Json.e` wrappers `Inline r` / `Deferred r` (or `JInline` / `JDeferred`)
  * and always win over the request. */
sealed abstract class Delivery(val name: String)
object Delivery {
  case object ByRequest extends Delivery("request")
  case object Inline    extends Delivery("inline")
  case object Deferred  extends Delivery("deferred")
}

trait JsonBuilder[J] {
  def nul: J
  def bool(b: Boolean): J
  def int(i: Int): J
  def long(l: Long): J
  /** Only ever called with a finite value. */
  def num(d: Double): J
  def str(s: String): J
  def arr(xs: List[J]): J
  def obj(fields: List[(String, J)]): J
  /** `r` evaluates to a `Rel` or `EmptyRel` but may not be evaluated yet
    * (force it with `Runtime.swhnf`; a bottom is the builder's to report
    * at `path`).  `delivery` is what the value asked for. */
  def rel(path: String, r: Runtime, delivery: Delivery): Either[Encode.Error, J]
}

/** `Runtime => J`: the type-directed reflective encoder of
  * tracker/JSON-API-DESIGN.md §3.1, Stage 0.
  *
  * The mapping (the single place it is defined; the schema exporter and the
  * params decoder mirror it):
  *
  *  - Int/Short/Byte -> number; Long -> decimal string (JSON numbers lose
  *    precision past 2^53); Double/Float -> number, NaN and infinities are
  *    an error; Bool -> boolean (`Data(True)` and a foreign `Boolean`
  *    alike); String/Char -> string; Date -> "YYYY-MM-DD" in GMT;
  *    Timestamp -> ISO-8601 with milliseconds and `Z`; GUID -> canonical
  *    string.
  *  - `Maybe a`, `Nullable a` -> the value or null.  `List a`, native
  *    `List# a`, `Vector a` -> array; the `::` spine is walked
  *    iteratively.  Tuples -> fixed-length array; `()` -> `[]`.
  *  - Records -> object, unqualified keys in sorted order (`Rec` is an
  *    unordered map).  A native `Map` with string keys -> object, sorted.
  *  - A `data` value: every constructor of the type nullary -> the
  *    constructor name as a string.  Otherwise, a constructor whose fields
  *    are NAMED (`C { f : t, .. }`) -> an object keyed in declaration
  *    order, with a `"tag"` key first when the type has more than one
  *    constructor and no tag when it has exactly one (the props shape,
  *    design note 3.1b) -- a field NAMED `tag` in a type with more than one
  *    constructor is an encode error, since it would overwrite the
  *    discriminator; a named field whose DECLARED type is `Maybe a`
  *    and whose value is `Nothing` is OMITTED, and `Just x` gives `x`;
  *    a named field whose DECLARED type is `Spread Json` is MERGED -- the
  *    keys of the `JObj` it holds are written into the constructor's own
  *    object, after the declared fields, in the object's order (Stage 2b),
  *    and a merged key that collides with a declared field name -- the
  *    spread field's OWN name excepted, since that is no key of any
  *    document of the type -- or with `tag`, a repeated key, a payload that
  *    is not an object, a second `Spread` field and a `Spread` anywhere
  *    else are all errors.
  *    A positional constructor -> `{"tag": C, "args": [...]}`.  Which of
  *    these is decided by the `DataConDecl` registry; a constructor the
  *    registry does not know falls back on its own arity.
  *  - A value of the stdlib `Json` type encodes as itself.
  *  - A relation goes to the builder's `rel`: a bare relation or `JRel`
  *    with `Delivery.ByRequest`, the wrappers `Json.Inline r` /
  *    `Json.Deferred r` and the nodes `JInline` / `JDeferred` with their
  *    own delivery.
  *  - Functions, IO actions, FFI values, foreign objects, `PrimT`
  *    witnesses and bottoms are errors that name the path to the offending
  *    node; a document with a hole in it does not go on the wire.
  *
  * The walk keeps an explicit stack (a `Frame` per open array or object),
  * so lists, records, tuples and `data` of any size and depth encode in
  * constant JVM stack: `nf` and `equals` on `Runtime` recurse and overflow
  * near 2,000 list elements, and this code never calls them.  The one
  * recursion left is one `step` per single-argument wrapper (`Just`, `Some`,
  * the `Json` constructors, a `PrimExpr`), i.e. per wrapper, not per element.
  * Each node is forced to weak head normal form only.
  *
  * Two things the mapping decides that are easy to miss: an Ermine `Long`
  * that the walker meets is a decimal string, but a `JInt` node built by
  * hand (`Json.int`) is a JSON number, the author's explicit choice; and a
  * `JObj` with a repeated key keeps the last one, as argonaut does.
  */
object Encode {
  final case class Error(path: String, message: String) {
    def report: String = "cannot encode " + path + ": " + message
  }

  /** The stdlib `Json` type (declared in `session/Lib.scala`, `json`). */
  val jsonModule = "Json"

  private sealed abstract class Node[J]
  private final case class Leaf[J](j: J) extends Node[J]
  /** `kids` carry the path label of each child; `wrap` receives the
    * children's encodings in order. */
  private final case class Compound[J](kids: List[(String, Runtime)], wrap: List[J] => J) extends Node[J]

  private final class Frame[J](var pending: List[(String, Runtime)], val wrap: List[J] => J) {
    val acc = new ListBuffer[J]
  }

  def encode[J](root: Runtime, b: JsonBuilder[J]): Either[Error, J] = {
    var stack: List[Frame[J]] = Nil
    var cur: (String, Runtime) = ("$", root)
    while (true) {
      step(cur._1, cur._2, b) match {
        case Left(e) => return Left(e)
        case Right(Compound(k :: ks, wrap)) =>
          stack = new Frame[J](ks, wrap) :: stack
          cur = k
        case Right(node) =>
          var v: J = node match {
            case Leaf(j) => j
            case Compound(_, wrap) => wrap(Nil)
          }
          // unwind: hand the value to the open frame, close frames that are complete
          var descending = false
          while (!descending) {
            stack match {
              case Nil => return Right(v)
              case f :: rest =>
                f.acc += v
                f.pending match {
                  case Nil =>
                    v = f.wrap(f.acc.toList)
                    stack = rest
                  case k :: ks =>
                    f.pending = ks
                    cur = k
                    descending = true
                }
            }
          }
      }
    }
    sys.error("unreachable")
  }

  def toArgonaut(r: Runtime): Either[Error, argonaut.Json] = encode(r, ArgonautJson)

  /** `toJson#`: the stdlib `Json` value, or a `Bottom` carrying the error. */
  def toErmine(r: Runtime): Runtime = encode(r, ErmineJson) match {
    case Right(j) => j
    case Left(e)  => Bottom(sys.error(e.report))
  }

  /** `renderJson#` / `prettyJson#`: a stdlib `Json` value (or any
    * encodable value) as text. */
  def render(r: Runtime, pretty: Boolean = false): Either[Error, String] =
    toArgonaut(r).right.map(j => if (pretty) j.spaces2 else j.nospaces)

  /** `parseJson#`: argonaut's tree as a stdlib `Json` value.  Recursive in
    * the document's nesting depth, which the parser already bounded. */
  def fromArgonaut(j: argonaut.Json): Runtime =
    j.fold(
      ErmineJson.nul,
      ErmineJson.bool,
      n => n.toLong match {
        case Some(l) => ErmineJson.long(l)
        case None    => ErmineJson.num(n.toBigDecimal.toDouble)
      },
      ErmineJson.str,
      xs => ErmineJson.arr(xs.map(fromArgonaut)),
      o  => ErmineJson.obj(o.toList.map { case (k, v) => (k, fromArgonaut(v)) })
    )

  // ---------------------------------------------------------------------
  // one node

  private val dateFmt      = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneOffset.UTC)
  private val timestampFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

  private def isBuiltin(g: Global, n: String) = g.module == "Builtin" && g.string == n
  private def isJson(g: Global, n: String)    = g.module == jsonModule && g.string == n

  private def finite[J](path: String, d: Double, b: JsonBuilder[J]): Either[Error, Node[J]] =
    if (java.lang.Double.isNaN(d) || java.lang.Double.isInfinite(d))
      Left(Error(path, "the number " + d + " has no JSON representation"))
    else Right(Leaf(b.num(d)))

  /** An element of a native collection: a `Runtime` for records, data and
    * tuples, a raw JVM value for primitives (`Lib.scala`, `Native.List`). */
  private def lift(x: Any): Runtime = x match {
    case r: Runtime => r
    case other      => Prim(other)
  }

  private def indexed(path: String, xs: List[Runtime]): List[(String, Runtime)] = {
    var i = -1
    xs.map { x => i += 1; (path + "[" + i + "]", x) }
  }

  private def keyed(path: String, fs: List[(String, Runtime)]): List[(String, Runtime)] =
    fs.map { case (k, v) => (path + "." + k, v) }

  private def objectOf[J](b: JsonBuilder[J], keys: List[String]): List[J] => J =
    vs => b.obj(keys.zip(vs))

  /** The `::` spine, iteratively.  A bottom or a foreign tail is an error at
    * its own index. */
  private def spine(path: String, l: Runtime): Either[Error, List[Runtime]] = {
    val buf = new ListBuffer[Runtime]
    var cur = l
    var i = 0
    while (true) {
      Runtime.swhnf(cur) match {
        case Data(g, _) if isBuiltin(g, "Nil") => return Right(buf.toList)
        case Data(g, args) if isBuiltin(g, "::") =>
          buf += args(0); cur = args(1); i += 1
        case bot: Bottom => return Left(bottom(path + "[" + i + "..]", bot))
        case other => return Left(Error(path + "[" + i + "..]", "a list spine ended in " + describe(other)))
      }
    }
    sys.error("unreachable")
  }

  /** The `(String, Json)` pairs of a `JObj`'s list argument, in the list's
    * order: the object's own fields.  Used by the `JObj` node and by a
    * `Spread` field, which merges exactly these into its parent. */
  private def objFields(path: String, pairs: Runtime): Either[Error, List[(String, Runtime)]] =
    spine(path, pairs).right.flatMap { ps =>
      val fields = new ListBuffer[(String, Runtime)]
      var i = 0
      var bad: Option[Error] = None
      ps.foreach { p =>
        if (bad.isEmpty) Runtime.swhnf(p) match {
          case Arr(kv) if kv.length == 2 => Runtime.swhnf(kv(0)) match {
            case Prim(k: String) => fields += ((k, kv(1)))
            case bot: Bottom     => bad = Some(bottom(path + "[" + i + "]", bot))
            case other           => bad = Some(Error(path + "[" + i + "]", "an object key must be a string, not " + describe(other)))
          }
          case bot: Bottom => bad = Some(bottom(path + "[" + i + "]", bot))
          case other       => bad = Some(Error(path + "[" + i + "]", "an object field must be a (String, Json) pair, not " + describe(other)))
        }
        i += 1
      }
      bad match {
        case Some(e) => Left(e)
        case None    => Right(fields.toList)
      }
    }

  private def bottom(path: String, b: Bottom): Error = {
    val t = b.thrown
    val msg = Option(t.getMessage).getOrElse(t.toString)
    Error(path, "the value is an error: " + msg)
  }

  private def describe(r: Runtime): String = r match {
    case _: Fun            => "a function"
    case Data(g, _)        => "the constructor " + g
    case Prim(x)           => if (x == null) "null" else "a foreign value of class " + x.getClass.getName
    case Box(x)            => if (x == null) "null" else "a foreign value of class " + x.getClass.getName
    case _: Rec            => "a record"
    case _: Arr            => "a tuple"
    case _: Rel | EmptyRel => "a relation"
    case _: Bottom         => "an error"
    case _: Thunk          => "a thunk"
  }

  private def step[J](path: String, r: Runtime, b: JsonBuilder[J]): Either[Error, Node[J]] = {
    val v = try Runtime.swhnf(r) catch { case NonFatal(e) => Bottom(throw e) }
    v match {
      case bot: Bottom => Left(bottom(path, bot))

      case Prim(x) => prim(path, x, b)
      case Box(x)  => prim(path, x, b)

      case Arr(elems) =>
        Right(Compound(indexed(path, elems.toList), b.arr _))

      case Rec(m) =>
        val fs = m.toList.sortBy(_._1)
        Right(Compound(keyed(path, fs), objectOf(b, fs.map(_._1))))

      case _: Rel | EmptyRel => b.rel(path, v, Delivery.ByRequest).right.map(Leaf(_))

      case _: Fun => Left(Error(path, "a function has no JSON representation"))

      case Data(g, args) => data(path, g, args, b)

      case _: Thunk => Left(Error(path, "unevaluated thunk after whnf")) // swhnf never returns one
    }
  }

  private def prim[J](path: String, x: Any, b: JsonBuilder[J]): Either[Error, Node[J]] = x match {
    case null                    => Right(Leaf(b.nul))
    case s: String               => Right(Leaf(b.str(s)))
    case c: java.lang.Character  => Right(Leaf(b.str(c.toString)))
    case bo: java.lang.Boolean   => Right(Leaf(b.bool(bo.booleanValue)))
    case i: java.lang.Integer    => Right(Leaf(b.int(i.intValue)))
    case s: java.lang.Short      => Right(Leaf(b.int(s.intValue)))
    case by: java.lang.Byte      => Right(Leaf(b.int(by.intValue)))
    case l: java.lang.Long       => Right(Leaf(b.str(l.toString)))
    case d: java.lang.Double     => finite(path, d.doubleValue, b)
    case f: java.lang.Float      => finite(path, f.doubleValue, b)
    // java.sql.Timestamp <: java.util.Date: Timestamp first
    case t: java.sql.Timestamp   => Right(Leaf(b.str(timestampFmt.format(Instant.ofEpochMilli(t.getTime)))))
    case d: java.util.Date       => Right(Leaf(b.str(dateFmt.format(Instant.ofEpochMilli(d.getTime)))))
    case u: java.util.UUID       => Right(Leaf(b.str(u.toString)))
    case e: PrimExpr             => e match {
      case NullExpr(_) => Right(Leaf(b.nul))
      case _           => prim(path, e.value, b)
    }
    case r: Runtime              => step(path, r, b)
    case _: Unit                 => Right(Leaf(b.arr(Nil)))
    case None                    => Right(Leaf(b.nul))
    case Some(y)                 => step(path, lift(y), b)
    case (k, y)                  => Right(Compound(indexed(path, List(lift(k), lift(y))), b.arr _))
    case xs: List[_]             => Right(Compound(indexed(path, xs.map(lift)), b.arr _))
    case xs: Vector[_]           => Right(Compound(indexed(path, xs.toList.map(lift)), b.arr _))
    case m: scala.collection.Map[_, _] =>
      if (m.keys.forall(_.isInstanceOf[String])) {
        val fs = m.toList.map { case (k, y) => (k.asInstanceOf[String], lift(y)) }.sortBy(_._1)
        Right(Compound(keyed(path, fs), objectOf(b, fs.map(_._1))))
      } else Left(Error(path, "a map with non-string keys has no JSON object encoding"))
    case _: PrimT                => Left(Error(path, "a PrimT witness has no JSON representation"))
    case _: FFI[_]               => Left(Error(path, "an FFI value has no JSON representation"))
    case other                   => Left(Error(path, "a foreign value of class " + other.getClass.getName + " has no JSON representation"))
  }

  private def data[J](path: String, g: Global, args: Array[Runtime], b: JsonBuilder[J]): Either[Error, Node[J]] = {
    if (g.module == "Builtin") g.string match {
      case "True"    => Right(Leaf(b.bool(true)))
      case "False"   => Right(Leaf(b.bool(false)))
      case "Nil"     => Right(Leaf(b.arr(Nil)))
      case "::"      => spine(path, Data(g, args)).right.map(xs => Compound(indexed(path, xs), b.arr _))
      case "Nothing" => Right(Leaf(b.nul))
      case "Just"    => step(path, args(0), b)
      case "Null"    => Right(Leaf(b.nul))
      case "Some"    => step(path, args(0), b)
      case _         => userData(path, g, args, b)
    } else if (g.module == jsonModule) g.string match {
      case "JNull" => Right(Leaf(b.nul))
      case "JBool" => step(path, args(0), b)
      case "JNum"  => step(path, args(0), b)
      case "JInt"  => Runtime.swhnf(args(0)) match {
        case Prim(l: java.lang.Long) => Right(Leaf(b.long(l.longValue)))
        case bot: Bottom             => Left(bottom(path, bot))
        case other                   => Left(Error(path, "JInt holds " + describe(other)))
      }
      case "JStr"  => step(path, args(0), b)
      case "JArr"  => step(path, args(0), b)
      case "JObj"  =>
        objFields(path, args(0)).right.map { fs =>
          Compound(keyed(path, fs), objectOf(b, fs.map(_._1)))
        }
      // `Spread` is only meaningful as a NAMED constructor field whose
      // declared type is `Spread Json` (userData merges it into the object);
      // anywhere else there is nothing to merge into, and writing the
      // wrapper as `{"tag":"Spread","args":[..]}` would be a document no
      // reader of the type expects.  The exporter and the decoder refuse
      // the same positions at the declaration.
      case "Spread" if args.length == 1 =>
        Left(Error(path, "a Spread value belongs in a named constructor field declared Spread Json, " +
                         "where its object is merged into the constructor's; it has no encoding on its own"))
      case "JRel"      => b.rel(path, args(0), Delivery.ByRequest).right.map(Leaf(_))
      case "JInline"   => b.rel(path, args(0), Delivery.Inline).right.map(Leaf(_))
      case "JDeferred" => b.rel(path, args(0), Delivery.Deferred).right.map(Leaf(_))
      // the delivery wrappers of Json.e: `data Inline r = Inline [..r]`
      case "Inline"   if args.length == 1 => b.rel(path, args(0), Delivery.Inline).right.map(Leaf(_))
      case "Deferred" if args.length == 1 => b.rel(path, args(0), Delivery.Deferred).right.map(Leaf(_))
      case _       => userData(path, g, args, b)
    } else userData(path, g, args, b)
  }

  private def userData[J](path: String, g: Global, args: Array[Runtime], b: JsonBuilder[J]): Either[Error, Node[J]] = {
    val decl = DataConDecl.forConstructor(g)
    val asEnum = decl match {
      case Some(d) => d.isEnum
      case None    => args.isEmpty
    }
    if (asEnum) Right(Leaf(b.str(g.string)))
    else {
      // Stage 1a: a constructor whose fields are NAMED encodes as an
      // object keyed in declaration order.  The tag is what tells a
      // discriminated union apart, so a single-constructor type (the
      // props shape of design note 3.1b) drops it.
      val named = for {
        d <- decl
        c <- d.constructor(g)
        if c.fields.length == args.length && c.fields.nonEmpty && c.fields.forall(_._1.isDefined)
      } yield (d.constructors.length > 1, c.fields.map { case (n, t) => (n.get, t) })
      named match {
        // A field named `tag` in a type with SEVERAL constructors would
        // overwrite the discriminator (the object would carry two "tag" keys,
        // of which argonaut keeps the last), so the document is refused rather
        // than written wrong.  The schema exporter and the params decoder
        // refuse the same declaration, at the field (J2a review finding 2).
        case Some((tagged, fields)) if tagged && fields.exists(_._1 == "tag") =>
          Left(Error(path + ".tag", "the constructor " + g.string + " has a field named tag, which " +
                                    "collides with the discriminator of a type with several constructors"))
        case Some((tagged, fields)) =>
          // A Maybe field is an OPTIONAL key: `Nothing` drops out of the
          // object rather than encoding as null.  Only the DECLARED type
          // decides, so a field of a type variable that happens to hold
          // Nothing still encodes as null, as the walker always did.
          //
          // A field whose declared type is headed by `Json.Spread` is MERGED
          // (Stage 2b): its object's keys are written into THIS object,
          // after the declared fields, in the object's own order.  At most
          // one such field per constructor; the exporter, the decoder and
          // `rejections` refuse a second one at the declaration.
          val spreads = fields.zipWithIndex.filter { case ((_, t), _) => isSpread(t) }
          val kept = new ListBuffer[(String, Runtime)]
          var extra: List[(String, Runtime)] = Nil
          var bad: Option[Error] =
            if (spreads.length <= 1) None
            else Some(Error(path + "." + spreads(1)._1._1,
                            "the constructor " + g.string + " has " + spreads.length + " Spread fields (" +
                            spreads.map(_._1._1).mkString(", ") + "); at most one can be merged into the object"))
          // The names the merged keys may not take: every declared field that
          // IS a key of the document (an omitted Maybe field included -- the
          // decoder reads such a key back as the field, not as part of the
          // spread) and the discriminator.  The SPREAD field's own name is
          // NOT reserved: it is no key of any document of this type, so the
          // decoder gathers it like any other spare key (J2b review finding 1
          // -- reserving it made the encoder refuse a document the exporter
          // declares legal and the decoder accepts).
          val taken: Set[String] =
            fields.filterNot { case (_, t) => isSpread(t) }.map(_._1).toSet ++
            (if (tagged) Set("tag") else Set[String]())
          fields.zipWithIndex.foreach { case ((n, t), i) =>
            if (bad.isEmpty) {
              val here = path + "." + n
              if (isSpread(t)) spread(path, here, g, n, args(i), taken) match {
                case Left(e)   => bad = Some(e)
                case Right(ps) => extra = ps
              }
              else if (isMaybe(t)) Runtime.swhnf(args(i)) match {
                case Data(Global("Builtin", "Nothing", _), _) => ()
                case bot: Bottom                              => bad = Some(bottom(here, bot))
                case forced                                   => kept += ((n, forced))
              } else kept += ((n, args(i)))
            }
          }
          bad match {
            case Some(e) => Left(e)
            case None =>
              val fs = kept.toList ++ extra
              val keys = if (tagged) "tag" :: fs.map(_._1) else fs.map(_._1)
              val kids = fs.map { case (n, a) => (path + "." + n, a) }
              val tag = b.str(g.string)
              Right(Compound(kids, vs => b.obj(keys.zip(if (tagged) tag :: vs else vs))))
          }
        case None =>
          val kids = args.toList.zipWithIndex.map { case (a, i) => (path + "." + g.string + "[" + i + "]", a) }
          val tag = b.str(g.string)
          Right(Compound(kids, vs => b.obj(List("tag" -> tag, "args" -> b.arr(vs)))))
      }
    }
  }

  /** Is the DECLARED type of a field `Maybe a`?  (Stage 1a: `Nothing`
    * drops the key.)  `Nullable a` is deliberately not included -- it is a
    * database column type whose `Null` carries a `PrimT` and whose JSON is
    * `null`, not an absent key. */
  private def isMaybe(t: Type): Boolean = unfurl(t) match {
    case (Type.Con(_, Global("Builtin", "Maybe", _), _, _), _ :: _) => true
    case _                                                          => false
  }

  /** Is the DECLARED type of a field headed by `Json.Spread`?  (Stage 2b:
    * its object is merged into the constructor's.)  Like `isMaybe`, this
    * reads the type as WRITTEN -- no alias expansion, which the encoder has
    * no session for.  The exporter and the decoder use the same test on the
    * same declared type, so an alias for `Spread Json` is not a spread field
    * anywhere: all three then refuse it, here at the value and there at the
    * `Spread` type itself. */
  def isSpread(t: Type): Boolean = unfurl(t) match {
    case (Type.Con(_, g, _, _), _ :: Nil) => g.module == jsonModule && g.string == "Spread"
    case _                                => false
  }

  /** The keys a `Spread` field merges into its parent object: the pairs of
    * the `JObj` it holds, in the object's order, checked against the keys
    * the constructor has already taken and against each other.  `path` is
    * the PARENT object (a merged key is a key of it), `here` the field. */
  private def spread(path: String, here: String, g: Global, field: String,
                     v: Runtime, taken: Set[String]): Either[Error, List[(String, Runtime)]] =
    Runtime.swhnf(v) match {
      case bot: Bottom => Left(bottom(here, bot))
      case Data(sg, sargs) if isJson(sg, "Spread") && sargs.length == 1 =>
        Runtime.swhnf(sargs(0)) match {
          case bot: Bottom => Left(bottom(here, bot))
          case Data(og, oargs) if isJson(og, "JObj") && oargs.length == 1 =>
            objFields(here, oargs(0)).right.flatMap { fs =>
              var seen = Set[String]()
              var bad: Option[Error] = None
              fs.foreach { case (k, _) =>
                if (bad.isEmpty) {
                  if (taken.contains(k))
                    bad = Some(Error(path + "." + k,
                      "the key " + quote(k) + " merged from the Spread field " + field + " collides with " +
                      (if (k == "tag") "the tag of " + g.string
                       else "the declared field " + quote(k) + " of " + g.string)))
                  else if (seen.contains(k))
                    bad = Some(Error(path + "." + k,
                      "the Spread field " + field + " of " + g.string + " repeats the key " + quote(k) +
                      "; a merged object cannot say the same key twice"))
                  else seen += k
                }
              }
              bad match {
                case Some(e) => Left(e)
                case None    => Right(fs)
              }
            }
          case other => Left(Error(here, "a Spread field carries a JSON object to merge into " + g.string +
                                         ", not " + describe(other)))
        }
      case other => Left(Error(here, "the field " + field + " of " + g.string + " is declared Spread but holds " +
                                     describe(other)))
    }

  private def quote(s: String): String = "\"" + s + "\""

  // ---------------------------------------------------------------------
  // the static side: which declared field types the encoder can carry

  /** Why a constructor field will not reach the wire, if it will not.
    * Used by the `modules/` sweep (Stage 0 gate: every `data` in the
    * standard library either encodes or is rejected with a location) and,
    * later, by the schema exporter. */
  final case class Rejected(constructor: Global, index: Int, ty: Type, reason: String) {
    def report(loc: scalaparsers.Loc): String =
      loc.report(scalaparsers.Document.text("constructor " + constructor.string + ", field " + index + ": " + reason)).toString
  }

  def rejections(decl: DataConDecl): List[Rejected] =
    decl.constructors.flatMap { c =>
      val spreads = c.fields.zipWithIndex.filter { case ((_, t), _) => isSpread(t) }
      c.fields.zipWithIndex.flatMap { case ((n, t), i) =>
        val tagClash =
          if (decl.constructors.length > 1 && n == Some("tag"))
            Some("a field named tag collides with the discriminator of a type with several constructors")
          else None
        // The three declaration-level Spread refusals (Stage 2b); the
        // exporter and the decoder refuse the same three, at the same field.
        // Tested in THEIR order (a second Spread before a positional one) so
        // that a declaration with both faults gets the same reason here as
        // there, at the field they name -- the sweep additionally reports the
        // first spread, since it lists every field rather than stopping.
        val spreadClash =
          if (!isSpread(t)) None
          else if (spreads.head._2 != i)
            Some("a constructor merges at most one Spread field (field " + spreads.head._2 + " is the first)")
          else if (n.isEmpty)
            Some("a Spread field has nothing to merge into in a positional constructor; name the constructor's fields")
          else spreadArgument(t)
        tagClash.orElse(spreadClash).orElse(if (isSpread(t)) None else reject(t)).map(Rejected(c.name, i, t, _))
      }
    }

  /** `None` when a `Spread` field's argument may be merged: `Json` itself,
    * or a type variable, which is decided at the instantiation (the exporter
    * and the decoder see the substituted type and insist on `Json` there). */
  def spreadArgument(t: Type): Option[String] = unfurl(t) match {
    case (_, a :: Nil) => unfurl(a) match {
      case (Type.Con(_, g, _, _), Nil) if g.module == jsonModule && g.string == "Json" => None
      case (VarT(_), Nil) => None
      case _ => Some("only Spread Json is merged into an object, not Spread " + Schema.renderType(a) +
                     " (a record's or a data type's keys are known from its declaration: name them as fields)")
    }
    case _ => Some("Spread takes one type argument")
  }

  private def unfurl(t: Type, args: List[Type] = Nil): (Type, List[Type]) = t match {
    case AppT(f, a)   => unfurl(f, a :: args)
    case Memory(_, u) => unfurl(u, args)
    case other        => (other, args)
  }

  /** `None` when the type is in the serializable fragment. */
  def reject(t: Type): Option[String] = unfurl(t) match {
    case (Type.Con(_, g, decl, _), args) =>
      if (g.module == "Builtin") g.string match {
        case "Int" | "Long" | "Double" | "Float" | "Short" | "Byte" | "Char" | "String" | "Bool" |
             "Date" | "Timestamp" | "GUID" => None
        case "List" | "Maybe" | "Nullable" | "Vector" => args.headOption.flatMap(reject)
        case "Record" | "Relation" => None
        case "IO"    => Some("an IO action")
        case "FFI"   => Some("an FFI value")
        case "Field" => Some("a Field witness")
        case "Prim" | "PrimT" => Some("a PrimT witness")
        case _       => Some("the foreign type " + g)
      }
      else if (g.module == jsonModule && g.string == "Json") None
      else if (g.module == jsonModule && g.string == "Spread")
        Some("a Spread belongs in a NAMED constructor field declared Spread Json, whose object is merged " +
             "into the constructor's; there is nothing to merge into here")
      else if (g.module == "Native.List" || g.module == "Vector") args.headOption.flatMap(reject)
      else if (g.module == "Native.Maybe") args.headOption.flatMap(reject)
      else if (g.module == "Native.Pair") args.flatMap(reject).headOption
      else decl match {
        case d: DataConDecl => None // its own constructors are checked as their own declaration
        case _: FieldConDecl => Some("a Field witness")
        case _: TypeAliasDecl => None // expanded by the checker before values exist
        case _ => if (DataConDecl.forType(g).isDefined) None // declared `data`, seen through another Con instance
                  else Some("the foreign type " + g)
      }
    case (ProductT(_, _), args) => args.flatMap(reject).headOption
    case (Arrow(_), _)          => Some("a function")
    case (VarT(_), _)           => None // decided at the instantiation
    case (_: Forall, _)         => Some("a polymorphic (rank-n) field")
    case (_: Exists, _)         => Some("an existential")
    case (ConcreteRho(_, _), _) => None
    case (_: Part, _)           => None
    case _                      => None
  }
}

/** The wire AST. */
object ArgonautJson extends JsonBuilder[argonaut.Json] {
  import argonaut.Json
  def nul                = Json.jNull
  def bool(b: Boolean)   = Json.jBool(b)
  def int(i: Int)        = Json.jNumber(i)
  def long(l: Long)      = Json.jNumber(l)
  def num(d: Double)     = Json.jNumber(d).getOrElse(Json.jNull)
  def str(s: String)     = Json.jString(s)
  def arr(xs: List[Json]) = Json.array(xs: _*)
  def obj(fields: List[(String, Json)]) = Json.obj(fields: _*)
  def rel(path: String, r: Runtime, delivery: Delivery) =
    Left(Encode.Error(path, "a relation has no inline encoding here; its rows are resolved by the document writer (design note §3.4a)"))
}

/** The stdlib `Json` data type, as `Data` nodes (`Lib.scala`, `json`). */
object ErmineJson extends JsonBuilder[Runtime] {
  private def con(n: String) = Global(Encode.jsonModule, n)
  private val cons = Global("Builtin", "::", InfixR(5))
  private val nil  = Data(Global("Builtin", "Nil"))
  private def list(xs: List[Runtime]): Runtime =
    xs.reverse.foldLeft(nil: Runtime)((acc, x) => Data(cons, Array(x, acc))) // foldRight recurses on 2.11

  val nul                = Data(con("JNull"))
  def bool(b: Boolean)   = Data(con("JBool"), Array[Runtime](if (b) Type.True else Type.False))
  def int(i: Int)        = Data(con("JInt"), Array(Prim(i.toLong)))
  def long(l: Long)      = Data(con("JInt"), Array(Prim(l)))
  def num(d: Double)     = Data(con("JNum"), Array(Prim(d)))
  def str(s: String)     = Data(con("JStr"), Array(Prim(s)))
  def arr(xs: List[Runtime]) = Data(con("JArr"), Array(list(xs)))
  def obj(fields: List[(String, Runtime)]) =
    Data(con("JObj"), Array(list(fields.map { case (k, v) => Arr(Array(Prim(k), v)) })))
  def rel(path: String, r: Runtime, delivery: Delivery) = delivery match {
    case Delivery.ByRequest => Right(Data(con("JRel"), Array(r)))
    case Delivery.Inline    => Right(Data(con("JInline"), Array(r)))
    case Delivery.Deferred  => Right(Data(con("JDeferred"), Array(r)))
  }
}
