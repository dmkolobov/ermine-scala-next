package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.SessionEnv
import com.clarifi.reporting.PrimT
import scala.collection.immutable.List
import scala.collection.mutable
import scala.collection.mutable.ListBuffer
import scala.util.control.NonFatal
import argonaut.Json
import scalaparsers.Supply

/** `JSON => Runtime`, directed by a `Type`: the params decoder of
  * tracker/JSON-API-DESIGN.md §3.3 (Stage 2a).
  *
  * The decoder is the INVERSE of `json/Encode.scala` on the serializable
  * fragment, and it accepts exactly the documents `json/Validate.scala`
  * accepts against the schema `json/Schema.scala` exports for the same type
  * (TestDecode's round-trip and agreement properties are what hold the three
  * together).  It is a static walk like the exporter's -- the same alias
  * expansion to a fixed point, the same `unfurl`, the same `$defs`-style
  * handling of a `data` instantiation -- compiled once into a `Decoder`
  * (`compile`), then run over the document with an explicit stack.
  *
  * The mapping, type by type (the §3.1 table read right to left):
  *
  *  - `Int`/`Short`/`Byte` <- a JSON number with no fractional part, in the
  *    type's range (`1.0` and `1e2` are integers, as JSON Schema says);
  *    `Long` <- a string of decimal digits with an optional `-`, in range;
  *    `Double`/`Float` <- any number that is finite at that width; `Bool` <-
  *    true/false; `String` <- a string; `Char` <- a string of exactly one
  *    UTF-16 unit; `Date` <- `yyyy-MM-dd` (ISO_LOCAL_DATE, strict) as a
  *    `java.util.Date` at UTC midnight; `Timestamp` <- an ISO-8601 date-time
  *    WITH an offset (ISO_OFFSET_DATE_TIME: the encoder's `...SSS'Z'` and
  *    any other offset, any fraction down to nanoseconds) as a
  *    `java.sql.Timestamp` of that instant; `GUID` <- the canonical 8-4-4-4-12
  *    hex form.
  *  - `Maybe a` <- null (`Nothing`) or an `a` (`Just`); `Nullable a` <- null
  *    (`Null` carrying the column's nullable `PrimT`, the witness `Null Int`
  *    and a database read both carry) or an `a` (`Some`); the native `Maybe#`
  *    <- null or a value (`Prim(None)` / `Prim(Some(x))`).
  *  - `List a` <- an array (a `::` spine); `List# a` and `Vector a` <- an
  *    array (`Prim(List(..))` / `Prim(Vector(..))` of the elements' unboxed
  *    values, as `::#` and `Vector.snoc` store them); a tuple <- an array of
  *    exactly its arity (`Arr`); `()` <- `[]`; `Pair# a b` <- a two-element
  *    array.
  *  - a closed record `{..(|f..|)}` <- an object with EXACTLY the row's keys
  *    (`Rec`, keyed by the unqualified field name).
  *  - a `data` instantiation: all-nullary <- the constructor name as a
  *    string; record-style (`C { f : t, .. }`) <- an object of the fields,
  *    with a `"tag"` key naming the constructor when the type has more than
  *    one; a field whose DECLARED type is `Maybe a` is an optional key
  *    (absent -> `Nothing`, present -> `Just` of an `a`); positional <-
  *    `{"tag": C, "args": [..]}`.  Every object is closed: an unknown key is
  *    an error -- EXCEPT a constructor with a field declared `Spread Json`
  *    (Stage 2b), which is open: every key the constructor does not declare
  *    is gathered, in document order, into the `JObj` that field holds, the
  *    inverse of the encoder's merge.  The type's arguments are substituted
  *    into the field types.
  *    The value is `Data(<the registry's constructor Global>, args)`, which
  *    is what `Runtime.accumData` builds.
  *  - the stdlib `Json` type <- any document, exactly as `Encode.fromArgonaut`
  *    (`parse`) builds it.
  *
  * Refused at compile time (by `entry`), each with the path to the offending
  * part of the TYPE: a type variable, a `forall`, an open row, a function,
  * `IO`, `FFI`, `Field`/`Prim`/`PrimT` witnesses, a foreign type, a relation
  * (and the `Json.Inline` / `Json.Deferred` wrappers: rows never come from
  * the request), an existential constructor field, a nested `Maybe (Maybe
  * a)` (both layers are the same null), a `Nullable` of a type with no
  * `PrimT` (no witness for its `Null`), an operator constructor and a
  * record-style field named `tag` in a tagged union (no stable
  * discriminator).
  *
  * Refused at run time (by `decode`), each with the JSON path into the INPUT
  * document -- `$`, `.key`, `[i]`, a positional constructor's arguments as
  * `.args[i]` -- which is the spelling `Encode.Error` and `Validate` use.  A
  * missing key is reported at the object that lacks it, an unknown key at
  * the key.
  *
  * The walk keeps an explicit stack (a `Frame` per open array or object), so
  * neither a 100,000-element list nor a document nested to the parser's
  * depth grows the JVM stack.  Compiling recurses over the TYPE, which is
  * small.
  */
object Decode {

  final case class Error(path: String, message: String) {
    def report: String = "cannot decode " + path + ": " + message
  }

  /** A compiled decoder for one type: reusable across documents, needs no
    * `SessionEnv` to run. */
  final class Decoder private[Decode] (val ty: Type, root: Plan) {
    def apply(j: Json): Either[Error, Runtime] = run(root, j)
  }

  /** Check `ty` and build its decoder.  `ty` is expanded (aliases) and must
    * be monomorphic, closed-row and in the decodable fragment; the refusal
    * names the offending part of the type. */
  def compile(ty: Type)(implicit s: SessionEnv): Either[Error, Decoder] = {
    val c = new Compiler(s)
    try {
      val t = c.resolve(ty)
      Right(new Decoder(t, c.plan(t, "$")))
    } catch { case r: Refuse => Left(r.error) }
  }

  /** The entry-type check alone: the expanded type, or why it has no
    * decoding. */
  def entry(ty: Type)(implicit s: SessionEnv): Either[Error, Type] =
    compile(ty).right.map(_.ty)

  /** Decode `j` as a value of `ty`.  Runs `entry` first. */
  def decode(ty: Type, j: Json)(implicit s: SessionEnv): Either[Error, Runtime] =
    compile(ty).right.flatMap(_.apply(j))

  /** Split a report's type scheme `P -> R` (aliases expanded), for the
    * runner: refuses a scheme that quantifies or mentions a type variable.
    * Neither half is checked further; `P` goes to `entry`/`decode`, `R` is
    * the runner's business.
    *
    * WP-34 (Q27 option (i), decided 2026-09-24): a type that is NOT a
    * function is a report with NO parameters, and answers `(None, t)`: the
    * binding's value is the result itself and nothing is applied to it.
    * Whether `t` is a `Node` or a `Fetch Node` is still the runner's
    * business (`Runner.resultKind`), exactly as the codomain of a function
    * is. */
  def reportSignature(ty: Type)(implicit s: SessionEnv): Either[Error, (Option[Type], Type)] = {
    val c = new Compiler(s)
    val t = c.resolve(ty)
    t match {
      case f: Forall =>
        Left(Error("$", "a polymorphic report signature (" + Schema.renderType(f.body) +
                        ") cannot be applied to decoded parameters; give it a monomorphic type"))
      case _ =>
        val vs = Type.typeVars(t).toList
        if (vs.nonEmpty)
          Left(Error("$", "the report signature " + Schema.renderType(t) + " mentions the type variable" +
                          (if (vs.length == 1) " " else "s ") +
                          vs.map(v => v.name.map(_.string).getOrElse("_")).mkString(", ")))
        else unfurl(t) match {
          case (Arrow(_), p :: r :: Nil) => Right((Some(c.resolve(p)), c.resolve(r)))
          case _                         => Right((None, t))
        }
    }
  }

  // ---------------------------------------------------------------------
  // plans: the compiled form of a type

  private sealed abstract class Plan
  /** A leaf: reads one JSON scalar. */
  private final case class Scalar(name: String, read: (Path, Json) => Either[Error, Runtime]) extends Plan
  private final case class MaybeP(inner: Plan) extends Plan
  private final case class NullableP(inner: Plan, witness: PrimT) extends Plan
  private final case class NativeMaybeP(inner: Plan) extends Plan
  private final case class ListP(elem: Plan) extends Plan
  private final case class NativeListP(elem: Plan) extends Plan
  private final case class VectorP(elem: Plan) extends Plan
  private final case class TupleP(elems: List[Plan]) extends Plan
  private final case class NativePairP(a: Plan, b: Plan) extends Plan
  /** Fields in sorted key order. */
  private final case class RecordP(fields: List[(String, Plan)]) extends Plan
  /** A `data` instantiation, by `$defs`-style key into the compile's table
    * (a recursive type refers to itself this way). */
  private final class DataRef(val key: String, val table: mutable.HashMap[String, DataP]) extends Plan
  private case object JsonP extends Plan
  /** A `Spread Json` constructor field (Stage 2b): it decodes no key of its
    * own -- every key the constructor does not declare is gathered into the
    * `JObj` it holds, in document order.  `con` is the registry's `Spread`
    * constructor. */
  private final case class SpreadP(con: Global) extends Plan

  private final class DataP(val typeName: String) {
    /** Constructor name -> Global, for an all-nullary type. */
    var nullary: Option[Map[String, Global]] = None
    var cons: List[ConP] = Nil
    var tagged: Boolean = false
  }
  /** `fields` is `None` for a positional constructor. */
  private final case class ConP(name: Global, positional: List[Plan], fields: Option[List[FieldP]])
  /** `optional`: the declared type is `Maybe a` and `plan` decodes the `a`. */
  private final case class FieldP(name: String, plan: Plan, optional: Boolean)

  private final class Refuse(val error: Error) extends RuntimeException(error.report, null, false, false)

  // ---------------------------------------------------------------------
  // compiling: the static walk, the mirror of Schema.Ctx.walk

  private final class Compiler(s: SessionEnv) {
    implicit val supply: Supply = Supply.create
    val defs = mutable.HashMap[String, DataP]()

    def refuse(path: String, why: String): Nothing = throw new Refuse(Error(path, why))

    def plan(t0: Type, path: String): Plan = {
      val t = resolve(t0)
      val (head, args) = unfurl(t)
      head match {
        case Type.Con(_, g, decl, _) => con(g, decl, args, path)
        case ProductT(_, n)          => tuple(n, args, path)
        case Arrow(_)                => refuse(path, "a function cannot be decoded from JSON")
        case VarT(v)                 => refuse(path, "polymorphic: the type variable " + v.name.map(_.string).getOrElse("_") +
                                                     "; decode at an instantiation")
        case _: Forall               => refuse(path, "a polymorphic (forall) type; decode at an instantiation")
        case _: Exists               => refuse(path, "an existential cannot be decoded from JSON")
        case _: Part                 => refuse(path, "open row; decode at an instantiation")
        case ConcreteRho(_, _)       => refuse(path, "a bare row is not a value type")
        case other                   => refuse(path, "no JSON decoding for " + Schema.renderType(other))
      }
    }

    private def con(g: Global, decl: ConDecl, args: List[Type], path: String): Plan =
      if (g.module == "Builtin") builtin(g, args, path)
      else if (g.module == Encode.jsonModule && g.string == "Json") { arity(g, args, 0, path); JsonP }
      else if (g.module == Encode.jsonModule && (g.string == "Inline" || g.string == "Deferred"))
        refuse(path, "a relation (" + g.string + ") cannot be decoded: its rows never come from the request")
      // Stage 2b: a Spread is not a value of its own -- `constructor` takes
      // the named field that declares it out of the plan before the walk
      // reaches here, and there is no object to gather anywhere else
      else if (g.module == Encode.jsonModule && g.string == "Spread")
        refuse(path, "a Spread belongs in a named constructor field declared Spread Json, which gathers the " +
                     "keys the constructor does not declare; there is nothing to gather into here")
      else if (g.module == "Native.List" && g.string == "List#") NativeListP(plan(arg1(g, args, path), path + "[]"))
      else if (g.module == "Vector" && g.string == "Vector") VectorP(plan(arg1(g, args, path), path + "[]"))
      else if (g.module == "Native.Maybe" && g.string == "Maybe#") {
        val inner = arg1(g, args, path)
        notNested(inner, path)
        NativeMaybeP(plan(inner, path + "?"))
      }
      else if (g.module == "Native.Pair" && g.string == "Pair#") {
        arity(g, args, 2, path)
        NativePairP(plan(args(0), path + "[0]"), plan(args(1), path + "[1]"))
      }
      else decl match {
        case d: DataConDecl  => dataType(g, d, args, path)
        case _: FieldConDecl => refuse(path, "a Field witness cannot be decoded from JSON")
        case _ => DataConDecl.forType(g) match {
          case Some(d) => dataType(g, d, args, path)
          case None    => refuse(path, "the foreign type " + g + " cannot be decoded from JSON")
        }
      }

    private def builtin(g: Global, args: List[Type], path: String): Plan = g.string match {
      case "Int" | "Short" | "Byte" | "Long" | "Double" | "Float" | "Bool" | "String" | "Char" |
           "Date" | "Timestamp" | "GUID" =>
        arity(g, args, 0, path)
        scalars(g.string)
      case "Maybe" =>
        val inner = arg1(g, args, path)
        notNested(inner, path)
        MaybeP(plan(inner, path + "?"))
      case "Nullable" =>
        val inner = arg1(g, args, path)
        notNested(inner, path)
        val r = resolve(inner)
        val witness = Type.primTypes.get(r) match {
          case Some(pt) => pt.withNull
          case None => refuse(path, "Nullable " + Schema.renderType(r) + " has no PrimT witness for its Null " +
                                    "(a Nullable is a column type: Bool, Byte, Date, Double, GUID, Int, Long, " +
                                    "Short, String or Timestamp)")
        }
        NullableP(plan(r, path + "?"), witness)
      case "List"      => ListP(plan(arg1(g, args, path), path + "[]"))
      case "Vector"    => VectorP(plan(arg1(g, args, path), path + "[]"))
      case "Record"    => RecordP(rowFields(arg1(g, args, path), path).map { case (k, t) => (k, plan(t, path + "." + k)) })
      case "Relation"  => refuse(path, "a relation cannot be decoded: its rows never come from the request")
      case "IO"        => refuse(path, "an IO action cannot be decoded from JSON")
      case "FFI"       => refuse(path, "an FFI value cannot be decoded from JSON")
      case "Field"     => refuse(path, "a Field witness cannot be decoded from JSON")
      case "Prim" | "PrimT" => refuse(path, "a PrimT witness cannot be decoded from JSON")
      case _           => refuse(path, "the foreign type " + g + " cannot be decoded from JSON")
    }

    private def arity(g: Global, args: List[Type], n: Int, path: String): Unit =
      if (args.length != n)
        refuse(path, g.string + " applied to " + args.length + " type arguments, expects " + n)

    private def arg1(g: Global, args: List[Type], path: String): Type = args match {
      case a :: Nil => a
      case _        => refuse(path, g.string + " expects one type argument, not " + args.length +
                                    " (a partially applied type constructor is not a value type)")
    }

    private def notNested(inner: Type, path: String): Unit =
      if (maybePayload(inner).isDefined)
        refuse(path, "a nested Maybe (Maybe a) cannot be decoded: both layers are the same null")

    private def tuple(n: Int, args: List[Type], path: String): Plan =
      if (args.length != n) refuse(path, "a " + n + "-tuple applied to " + args.length + " arguments is not a value type")
      else TupleP(args.zipWithIndex.map { case (a, i) => plan(a, path + "[" + i + "]") })

    /** The row's fields and their declared types, in sorted key order. */
    private def rowFields(row0: Type, path: String): List[(String, Type)] =
      resolve(row0) match {
        case ConcreteRho(_, names) =>
          names.toList.map { n =>
            val g = n match {
              case g: Global => g
              case l: Local  => localField(l, path)
            }
            s.cons.get(g) match {
              case Some(Type.Con(_, fg, FieldConDecl(ft), _)) => (fg.string, ft)
              case Some(other) => refuse(path + "." + g.string, "the field " + g + " is not a field witness")
              case None        => refuse(path + "." + g.string, "no field witness for " + g + " is in scope")
            }
          }.sortBy(_._1)
        case _: Part | VarT(_) => refuse(path, "open row; decode at an instantiation")
        case other             => refuse(path, "expected a concrete row, found " + Schema.renderType(other))
      }

    /** A row name that was never globalised (a type parsed outside a module):
      * the one field witness with that spelling, if there is exactly one. */
    private def localField(l: Local, path: String): Global =
      s.cons.collect { case (g, Type.Con(_, _, FieldConDecl(_), _)) if g.string == l.string => g }.toList match {
        case g :: Nil => g
        case Nil      => refuse(path + "." + l.string, "no field witness named " + l.string + " is in scope")
        case gs       => refuse(path + "." + l.string, "the field name " + l.string + " is ambiguous: " +
                                                       gs.map(_.toString).sorted.mkString(", "))
      }

    private def dataType(g: Global, decl: DataConDecl, args: List[Type], path: String): Plan = {
      val key = Schema.defName(g, args)
      if (!defs.contains(key)) {
        if (decl.typeArgs.length != args.length)
          refuse(path, g.string + " takes " + decl.typeArgs.length + " type " +
                       (if (decl.typeArgs.length == 1) "argument" else "arguments") +
                       ", applied to " + args.length + "; decode at an instantiation")
        val cs = decl.constructors
        if (cs.isEmpty) refuse(path, g.string + " has no constructors, so it has no values")
        val d = new DataP(g.string)
        defs += ((key, d)) // before the fields: a recursive occurrence finds it
        val sub: Map[TypeVar, Type] = decl.typeArgs.zip(args).toMap
        if (decl.isEnum) d.nullary = Some(cs.map(c => (c.name.string, c.name)).toMap)
        else {
          d.tagged = cs.length > 1
          d.cons = cs.map(c => constructor(g, c, sub, d.tagged))
        }
        // A variable a field reaches was refused at that field just now; a
        // PHANTOM parameter's is never walked, so it is looked for here.  (The
        // exporter accepts a phantom variable: nothing in the schema mentions
        // it.  A decoded value has no type to carry it.)
        args.foreach { a =>
          if (Type.typeVars(a).toList.nonEmpty)
            refuse(path, "polymorphic: " + g.string + " is applied to " + Schema.renderType(a) +
                         ", which mentions a type variable; decode at an instantiation")
        }
      }
      new DataRef(key, defs)
    }

    private def constructor(ty: Global, c: DataConDecl.Constructor, sub: Map[TypeVar, Type], tagged: Boolean): ConP = {
      val base = ty.string + "." + c.name.string
      def at(i: Int) = base + "[" + i + "]"
      if (c.name.string.exists(ch => !(ch.isLetterOrDigit || ch == '_' || ch == '\'')))
        refuse(base, "an operator constructor has no stable discriminator tag " +
                     "(a tag must be an alphanumeric constructor name)")
      val ex = c.existentials.toSet
      // the SPREAD flag comes off the type as DECLARED (`Encode.isSpread`,
      // the encoder's own test), before the instantiation is substituted in
      val fields = c.fields.zipWithIndex.map { case ((nm, t0), i) =>
        if (Type.typeVars(t0).exists(ex)) refuse(at(i), "an existential cannot be decoded from JSON")
        (nm, Type.subType(sub, t0), i, Encode.isSpread(t0))
      }
      val named = fields.count(_._1.isDefined)
      if (named != 0 && named != fields.length)
        refuse(base, "constructor fields are partly named; name all of them or none")
      // Stage 2b: at most one Spread field, named; the encoder and the
      // exporter refuse the same two at the same field
      val spreads = fields.filter(_._4)
      spreads.drop(1).headOption foreach { f =>
        refuse(at(f._3), "a constructor merges at most one Spread field (field " + spreads.head._3 + " is the first)")
      }
      if (spreads.nonEmpty && named != fields.length)
        refuse(at(spreads.head._3), "a Spread field has nothing to gather into in a positional constructor; " +
                                    "name the constructor's fields")
      if (named == fields.length && fields.nonEmpty) {
        val fs = fields.map { case (nm, t, i, isSpread) =>
          val k = nm.get
          if (tagged && k == "tag")
            refuse(at(i), "a field named tag collides with the discriminator of a type with several constructors")
          if (isSpread) FieldP(k, SpreadP(spreadCon(t, at(i))), optional = true)
          else declaredMaybe(t) match {
            case Some(inner) => FieldP(k, plan(inner, at(i)), optional = true)
            case None        => FieldP(k, plan(t, at(i)), optional = false)
          }
        }
        ConP(c.name, Nil, Some(fs))
      } else ConP(c.name, fields.map { case (_, t, i, _) => plan(t, at(i)) }, None)
    }

    /** A `Spread` field's constructor, at the instantiation: only `Spread
      * Json` gathers keys (a record's or a data type's keys are known from
      * its declaration, so the constructor can name them as fields).  The
      * `Global` is the registry's, which is what `Runtime.accumData` builds
      * and what a round trip compares against. */
    private def spreadCon(t: Type, path: String): Global =
      unfurl(resolve(t)) match {
        case (Type.Con(_, g, decl, _), a :: Nil) =>
          unfurl(resolve(a)) match {
            case (Type.Con(_, j, _, _), Nil) if j.module == Encode.jsonModule && j.string == "Json" => ()
            case _ => refuse(path, "only Spread Json gathers an object's spare keys, not Spread " +
                                   Schema.renderType(a) + " (the keys of a record or a data type are known " +
                                   "from its declaration: name them as fields)")
          }
          val d = decl match {
            case dd: DataConDecl => Some(dd)
            case _               => DataConDecl.forType(g)
          }
          d.flatMap(_.constructors.headOption).map(_.name).getOrElse(Global(Encode.jsonModule, "Spread"))
        case _ => refuse(path, "Spread takes one type argument")
      }

    /** `Some(a)` when the declared type is headed by `Builtin.Maybe` -- the
      * encoder's test for an optional key (Encode.isMaybe), and the
      * exporter's for its record-style constructors. */
    private def declaredMaybe(t: Type): Option[Type] = unfurl(resolve(t)) match {
      case (Type.Con(_, Global("Builtin", "Maybe", _), _, _), a :: Nil) => Some(a)
      case _ => None
    }

    /** Any of the three null-carrying wrappers (Schema.maybePayload). */
    private def maybePayload(t: Type): Option[Type] = unfurl(resolve(t)) match {
      case (Type.Con(_, g, _, _), a :: Nil)
        if (g.module == "Builtin" && (g.string == "Maybe" || g.string == "Nullable")) ||
           (g.module == "Native.Maybe" && g.string == "Maybe#") => Some(a)
      case _ => None
    }

    /** Aliases expanded to a fixed point, exactly as `Schema.Ctx.resolve`. */
    def resolve(t: Type): Type = {
      var cur = strip(t)
      var fuel = 100
      var done = false
      while (!done && fuel > 0) {
        fuel -= 1
        val next = Type.expandAlias(cur.loc, cur)(supply) match {
          case Type.Expanded(u)   => Some(strip(u))
          case Type.Unexpanded(u) => Some(strip(u))
          case Type.Bad(_)        => None
        }
        next match {
          case Some(u) if u != cur => cur = u
          case _                   => done = true
        }
      }
      cur
    }
  }

  private def strip(t: Type): Type = t match {
    case Memory(_, b)              => strip(b)
    case Forall(_, Nil, Nil, _, b) => strip(b)
    case other                     => other
  }

  private def unfurl(t: Type, args: List[Type] = Nil): (Type, List[Type]) = t match {
    case AppT(f, a)   => unfurl(f, strip(a) :: args)
    case Memory(_, u) => unfurl(u, args)
    case other        => (other, args)
  }

  // ---------------------------------------------------------------------
  // scalars

  private val dateFmt     = java.time.format.DateTimeFormatter.ISO_LOCAL_DATE
  private val dateTimeFmt = java.time.format.DateTimeFormatter.ISO_OFFSET_DATE_TIME
  private val longPattern = java.util.regex.Pattern.compile("-?[0-9]+")
  private val uuidPattern =
    java.util.regex.Pattern.compile("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

  private def quote(s: String): String = {
    val shown = if (s.length > 40) s.substring(0, 40) + "..." else s
    "\"" + shown + "\""
  }

  private def describe(j: Json): String =
    if (j.isNull) "null"
    else j.bool.map(b => "the boolean " + b)
      .orElse(j.number.map(n => "the number " + n.toBigDecimal.toString))
      .orElse(j.string.map(s => "the string " + quote(s)))
      .orElse(j.array.map(xs => "an array of " + xs.length))
      .orElse(j.obj.map(_ => "an object"))
      .getOrElse("an unknown JSON value")

  private def expected(path: Path, what: String, j: Json): Either[Error, Nothing] =
    Left(Error(path.render, "expected " + what + ", found " + describe(j)))

  /** A JSON number with no fractional part, within `[lo, hi]`.  The
    * magnitude test comes first, so `1e1000000000` is refused without
    * materialising it. */
  private def integral(path: Path, j: Json, name: String, lo: Long, hi: Long): Either[Error, Long] =
    j.number match {
      case None => expected(path, "an integer (" + name + ")", j)
      case Some(n) =>
        val bd = n.toBigDecimal.bigDecimal
        val intDigits = bd.precision - bd.scale
        def outOfRange = Left(Error(path.render, "the number " + n.toBigDecimal.toString + " is out of the range of " +
                                          name + " [" + lo + ", " + hi + "]"))
        if (bd.signum == 0) Right(0L)
        else if (intDigits > 20) outOfRange
        else if (bd.scale > 0 && bd.stripTrailingZeros.scale > 0)
          Left(Error(path.render, "expected an integer (" + name + "), found the fraction " + n.toBigDecimal.toString))
        else {
          val bi = bd.toBigIntegerExact
          if (bi.compareTo(java.math.BigInteger.valueOf(lo)) < 0 || bi.compareTo(java.math.BigInteger.valueOf(hi)) > 0) outOfRange
          else Right(bi.longValue)
        }
    }

  private def number(path: Path, j: Json, name: String): Either[Error, Double] =
    j.number match {
      case None => expected(path, "a number (" + name + ")", j)
      case Some(n) =>
        val d = n.toBigDecimal.toDouble
        if (java.lang.Double.isInfinite(d) || java.lang.Double.isNaN(d))
          Left(Error(path.render, "the number " + n.toBigDecimal.toString + " is out of the range of " + name))
        else Right(d)
    }

  private def string(path: Path, j: Json, what: String): Either[Error, String] =
    j.string match {
      case Some(s) => Right(s)
      case None    => expected(path, what, j)
    }

  private val scalars: Map[String, Plan] = {
    def sc(name: String)(f: (Path, Json) => Either[Error, Runtime]): (String, Plan) = (name, Scalar(name, f))
    Map(
      sc("Int")   ((p, j) => integral(p, j, "Int", Int.MinValue, Int.MaxValue).right.map(l => Prim(l.toInt))),
      sc("Short") ((p, j) => integral(p, j, "Short", Short.MinValue, Short.MaxValue).right.map(l => Prim(l.toShort))),
      sc("Byte")  ((p, j) => integral(p, j, "Byte", Byte.MinValue, Byte.MaxValue).right.map(l => Prim(l.toByte))),
      sc("Long")  ((p, j) => string(p, j, "a decimal string (Long)").right.flatMap { s =>
        // `Prim`'s argument is BY NAME and it turns a throw into a Bottom, so
        // every conversion below is forced into a val first: a decode either
        // fails with an Error or yields a value with no bottom in it.
        if (!longPattern.matcher(s).matches) Left(Error(p.render, "the string " + quote(s) + " is not a decimal integer (Long)"))
        else try { val l = java.lang.Long.parseLong(s); Right(Prim(l)) }
             catch { case _: NumberFormatException =>
               Left(Error(p.render, "the string " + quote(s) + " is out of the range of Long")) }
      }),
      sc("Double")((p, j) => number(p, j, "Double").right.map(d => Prim(d))),
      sc("Float") ((p, j) => number(p, j, "Float").right.flatMap { d =>
        val f = d.toFloat
        if (java.lang.Float.isInfinite(f)) Left(Error(p.render, "the number " + d + " is out of the range of Float"))
        else Right(Prim(f))
      }),
      sc("Bool")  ((p, j) => j.bool match {
        case Some(b) => Right(if (b) Type.True else Type.False)
        case None    => expected(p, "a boolean", j)
      }),
      sc("String")((p, j) => string(p, j, "a string").right.map(s => Prim(s))),
      sc("Char")  ((p, j) => string(p, j, "a one-character string (Char)").right.flatMap { s =>
        if (s.length == 1) Right(Prim(s.charAt(0)))
        else Left(Error(p.render, "expected a one-character string (Char), found " + s.length + " characters"))
      }),
      sc("Date")  ((p, j) => string(p, j, "a date string yyyy-MM-dd").right.flatMap { s =>
        try {
          val d = java.time.LocalDate.from(dateFmt.parse(s))
          val at = new java.util.Date(d.atStartOfDay(java.time.ZoneOffset.UTC).toInstant.toEpochMilli)
          Right(Prim(at))
        } catch { case NonFatal(_) => Left(Error(p.render, "the string " + quote(s) + " is not a date yyyy-MM-dd")) }
      }),
      sc("Timestamp")((p, j) => string(p, j, "an ISO-8601 date-time string").right.flatMap { s =>
        try {
          val i = java.time.OffsetDateTime.from(dateTimeFmt.parse(s)).toInstant
          i.toEpochMilli // throws when the instant is out of a Timestamp's range;
                         // `Timestamp.from` alone MULTIPLIES AND WRAPS (JDK 21:
                         // year 999999999 comes back as year 169104628)
          val at = java.sql.Timestamp.from(i)
          Right(Prim(at))
        } catch { case NonFatal(_) =>
          Left(Error(p.render, "the string " + quote(s) + " is not an ISO-8601 date-time with an offset " +
                        "(yyyy-MM-ddTHH:mm:ss.SSSZ)")) }
      }),
      sc("GUID")  ((p, j) => string(p, j, "a GUID string").right.flatMap { s =>
        if (!uuidPattern.matcher(s).matches) Left(Error(p.render, "the string " + quote(s) + " is not a canonical GUID"))
        else try { val u = java.util.UUID.fromString(s); Right(Prim(u)) }
             catch { case NonFatal(_) => Left(Error(p.render, "the string " + quote(s) + " is not a canonical GUID")) }
      })
    )
  }

  // ---------------------------------------------------------------------
  // running: an explicit stack over the document

  private val consG    = Global("Builtin", "::", InfixR(5))
  private val nilV     = Data(Global("Builtin", "Nil"))
  private val nothingV = Data(Global("Builtin", "Nothing"))
  private val justG    = Global("Builtin", "Just")
  private val someG    = Global("Builtin", "Some")
  private val nullG    = Global("Builtin", "Null")

  private def listOf(xs: List[Runtime]): Runtime =
    xs.reverse.foldLeft(nilV: Runtime)((acc, x) => Data(consG, Array(x, acc)))

  /** What `::#`, `Just#` and `toPair#` store for an element: `x.extract`,
    * the payload of a `Prim` and the value itself otherwise (`Lib.scala`). */
  private def unboxed(r: Runtime): Any = r match {
    case p: Prim => p.extract[Any]
    case other   => other
  }

  /** What a `Vector` stores: its builders are FOREIGN functions, so an
    * element goes through `Session.whnfForeign`, which differs from
    * `extract` in one place -- an empty `Arr` (the unit value) arrives as
    * Scala's `()`. */
  private def foreign(r: Runtime): Any = r match {
    case p: Prim              => p.extract[Any]
    case Arr(xs) if xs.isEmpty => ()
    case other                => other
  }

  /** A JSON path as a parent-linked chain, rendered only when an error
    * needs it: eager strings would cost the square of the nesting depth. */
  private final class Path(val parent: Path, val seg: String) {
    def /(s: String): Path = new Path(this, s)
    def render: String = {
      val segs = new ListBuffer[String]
      var cur = this
      while (cur != null) { segs += cur.seg; cur = cur.parent }
      segs.reverse.mkString
    }
  }
  private object Path { val root = new Path(null, "$") }

  private final case class Task(path: Path, plan: Plan, j: Json)
  private sealed abstract class Step
  private final case class Done(r: Runtime) extends Step
  private final case class Kids(kids: List[Task], build: List[Runtime] => Runtime) extends Step
  private final class Frame(var pending: List[Task], val build: List[Runtime] => Runtime) {
    val acc = new ListBuffer[Runtime]
  }

  private def run(root: Plan, j: Json): Either[Error, Runtime] = {
    var stack: List[Frame] = Nil
    var cur = Task(Path.root, root, j)
    while (true) {
      step(cur) match {
        case Left(e) => return Left(e)
        case Right(Kids(k :: ks, build)) =>
          stack = new Frame(ks, build) :: stack
          cur = k
        case Right(done) =>
          var v: Runtime = done match {
            case Done(r)        => r
            case Kids(_, build) => build(Nil)
          }
          var descending = false
          while (!descending) {
            stack match {
              case Nil => return Right(v)
              case f :: rest =>
                f.acc += v
                f.pending match {
                  case Nil =>
                    v = f.build(f.acc.toList)
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

  private def indexed(path: Path, xs: List[Json], plan: Plan): List[Task] = {
    var i = -1
    xs.map { x => i += 1; Task(path / ("[" + i + "]"), plan, x) }
  }

  private def one(t: Task, build: Runtime => Runtime): Step = Kids(List(t), vs => build(vs.head))

  private def step(t: Task): Either[Error, Step] = {
    val path = t.path
    val j = t.j
    t.plan match {
      case Scalar(_, read) => read(path, j).right.map(Done(_))

      case MaybeP(inner) =>
        if (j.isNull) Right(Done(nothingV))
        else Right(one(Task(path, inner, j), v => Data(justG, Array(v))))

      case NullableP(inner, witness) =>
        if (j.isNull) Right(Done(Data(nullG, Array[Runtime](Prim(witness)))))
        else Right(one(Task(path, inner, j), v => Data(someG, Array(v))))

      case NativeMaybeP(inner) =>
        if (j.isNull) Right(Done(Prim(None)))
        else Right(one(Task(path, inner, j), v => Prim(Some(unboxed(v)))))

      case ListP(elem) => j.array match {
        case Some(xs) => Right(Kids(indexed(path, xs, elem), listOf))
        case None     => expected(path, "an array", j)
      }
      case NativeListP(elem) => j.array match {
        case Some(xs) => Right(Kids(indexed(path, xs, elem), vs => Prim(vs.map(unboxed))))
        case None     => expected(path, "an array", j)
      }
      case VectorP(elem) => j.array match {
        case Some(xs) => Right(Kids(indexed(path, xs, elem), vs => Prim(vs.map(foreign).toVector)))
        case None     => expected(path, "an array", j)
      }
      case TupleP(elems) => j.array match {
        case Some(xs) if xs.length == elems.length =>
          val kids = xs.zip(elems).zipWithIndex.map { case ((x, p), i) => Task(path / ("[" + i + "]"), p, x) }
          Right(Kids(kids, vs => Arr(vs.toArray)))
        case Some(xs) =>
          Left(Error(path.render, "expected an array of exactly " + elems.length + " (a " +
                           (if (elems.isEmpty) "unit ()" else elems.length + "-tuple") + "), found " + xs.length))
        case None => expected(path, "an array", j)
      }
      case NativePairP(a, b) => j.array match {
        case Some(x :: y :: Nil) =>
          Right(Kids(List(Task(path / "[0]", a, x), Task(path / "[1]", b, y)),
                     vs => Prim((unboxed(vs(0)), unboxed(vs(1))))))
        case Some(xs) => Left(Error(path.render, "expected an array of exactly 2 (a pair), found " + xs.length))
        case None     => expected(path, "an array", j)
      }

      case RecordP(fields) => j.obj match {
        case None => expected(path, "an object", j)
        case Some(o) =>
          val m = o.toMap
          closed(path, o.fields, fields.map(_._1).toSet).right.flatMap { _ =>
            fields.find(f => !m.contains(f._1)) match {
              case Some((k, _)) => Left(Error(path.render, "the required key " + quote(k) + " is missing"))
              case None =>
                val keys = fields.map(_._1)
                val kids = fields.map { case (k, p) => Task(path / ("." + k), p, m(k)) }
                Right(Kids(kids, vs => new Rec(keys.zip(vs).toMap)))
            }
          }
      }

      case r: DataRef => data(path, r.table(r.key), j)

      // never reached: `recordStyle` gathers a spread field's keys itself
      case SpreadP(_) =>
        Left(Error(path.render, "a Spread field is gathered by its constructor, not decoded on its own"))

      case JsonP =>
        j.array match {
          case Some(xs) => Right(Kids(indexed(path, xs, JsonP), vs => ErmineJson.arr(vs)))
          case None => j.obj match {
            case Some(o) =>
              val fs = o.toList
              val keys = fs.map(_._1)
              Right(Kids(fs.map { case (k, v) => Task(path / ("." + k), JsonP, v) }, vs => ErmineJson.obj(keys.zip(vs))))
            case None => Right(Done(Encode.fromArgonaut(j))) // a scalar: no recursion
          }
        }
    }
  }

  /** The first key of `keys` (document order) that `allowed` does not name. */
  private def closed(path: Path, keys: List[String], allowed: Set[String]): Either[Error, Unit] =
    keys.find(k => !allowed.contains(k)) match {
      case Some(k) => Left(Error((path / ("." + k)).render, "the key " + quote(k) + " is not allowed here"))
      case None    => Right(())
    }

  private def data(path: Path, d: DataP, j: Json): Either[Error, Step] =
    d.nullary match {
      case Some(names) => j.string match {
        case Some(s) => names.get(s) match {
          case Some(g) => Right(Done(Data(g, Array[Runtime]())))
          case None    => Left(Error(path.render, "the string " + quote(s) + " names no constructor of " + d.typeName +
                                           " (one of " + names.keys.toList.sorted.mkString(", ") + ")"))
        }
        case None => expected(path, "a constructor name of " + d.typeName, j)
      }
      case None => j.obj match {
        case None => expected(path, "an object (" + d.typeName + ")", j)
        case Some(o) =>
          val m = o.toMap
          val chosen: Either[Error, ConP] =
            if (!d.tagged) Right(d.cons.head)
            else m.get("tag") match {
              case None => Left(Error(path.render, "the required key \"tag\" is missing"))
              case Some(tj) => tj.string match {
                case None => expected(path / ".tag", "a constructor name of " + d.typeName, tj)
                case Some(tag) => d.cons.find(_.name.string == tag) match {
                  case Some(c) => Right(c)
                  case None    => Left(Error((path / ".tag").render, "the string " + quote(tag) + " names no constructor of " +
                                                            d.typeName + " (one of " +
                                                            d.cons.map(_.name.string).mkString(", ") + ")"))
                }
              }
            }
          chosen.right.flatMap { c =>
            c.fields match {
              case Some(fs) => recordStyle(path, c, fs, d.tagged, o.fields, m)
              case None     => positional(path, c, o.fields, m)
            }
          }
      }
    }

  /** One constructor field's contribution to the value: a constant (an
    * absent optional key), the next decoded kid (wrapped in `Just` when the
    * field is a `Maybe`), or the `Spread` gathering the keys the declaration
    * does not name, which takes one kid per such key. */
  private sealed abstract class Slot
  private final case class Const(r: Runtime) extends Slot
  private final case class Take(just: Boolean) extends Slot
  private final case class Gather(con: Global, keys: List[String]) extends Slot

  private def isSpreadField(f: FieldP): Boolean = f.plan match {
    case SpreadP(_) => true
    case _          => false
  }

  private def recordStyle(path: Path, c: ConP, fs: List[FieldP], tagged: Boolean,
                          keys: List[String], m: Map[String, Json]): Either[Error, Step] = {
    val spread = fs.exists(isSpreadField)
    val allowed = fs.filterNot(isSpreadField).map(_.name).toSet ++ (if (tagged) Set("tag") else Set[String]())
    // A constructor with a Spread field is OPEN: every key it does not
    // declare is gathered into the spread instead of being refused (which
    // is why the exporter drops `additionalProperties: false` for it).
    val spare = if (spread) keys.filterNot(allowed.contains) else Nil
    val check: Either[Error, Unit] = if (spread) Right(()) else closed(path, keys, allowed)
    check.right.flatMap { _ =>
      fs.find(f => !isSpreadField(f) && !f.optional && !m.contains(f.name)) match {
        case Some(f) => Left(Error(path.render, "the required key " + quote(f.name) + " is missing"))
        case None =>
          val kids = fs.flatMap { f =>
            if (isSpreadField(f)) spare.map(k => Task(path / ("." + k), JsonP, m(k)))
            else m.get(f.name).map(v => Task(path / ("." + f.name), f.plan, v)).toList
          }
          val slots: List[Slot] = fs.map { f =>
            f.plan match {
              case SpreadP(g) => Gather(g, spare)
              case _          => if (m.contains(f.name)) Take(f.optional) else Const(nothingV)
            }
          }
          val g = c.name
          Right(Kids(kids, vs => {
            val it = vs.iterator
            Data(g, slots.map {
              case Const(k)          => k
              case Take(just)        => val v = it.next(); if (just) Data(justG, Array(v)) else v
              case Gather(sg, ks)    => Data(sg, Array(ErmineJson.obj(ks.map(k => (k, it.next())))))
            }.toArray)
          }))
      }
    }
  }

  private def positional(path: Path, c: ConP, keys: List[String], m: Map[String, Json]): Either[Error, Step] =
    closed(path, keys, Set("tag", "args")).right.flatMap { _ =>
      if (!m.contains("tag")) Left(Error(path.render, "the required key \"tag\" is missing"))
      else if (m("tag").string != Some(c.name.string))
        Left(Error((path / ".tag").render, "expected the constructor name " + quote(c.name.string) + ", found " + describe(m("tag"))))
      else m.get("args") match {
        case None => Left(Error(path.render, "the required key \"args\" is missing"))
        case Some(aj) => aj.array match {
          case None => expected(path / ".args", "an array of " + c.name.string + "'s arguments", aj)
          case Some(xs) if xs.length != c.positional.length =>
            Left(Error((path / ".args").render, c.name.string + " takes " + c.positional.length + " arguments, found " + xs.length))
          case Some(xs) =>
            val kids = xs.zip(c.positional).zipWithIndex.map { case ((x, p), i) => Task(path / (".args[" + i + "]"), p, x) }
            val g = c.name
            Right(Kids(kids, vs => Data(g, vs.toArray)))
        }
      }
    }
}
