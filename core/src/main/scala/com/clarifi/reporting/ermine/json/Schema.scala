package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.SessionEnv
import scala.collection.immutable.List
import scala.collection.mutable
import argonaut.Json
import scalaparsers.Supply

/** `Type => JSON Schema 2020-12`: the type walker of
  * tracker/JSON-API-DESIGN.md §3.5, Stage 1b.
  *
  * The exporter is the STATIC mirror of `json/Encode.scala`.  Encode's walk
  * over a `Runtime` is the definition of the wire mapping; every case here
  * exists because a case there produces that shape, and the encode/schema
  * consistency property (`TestSchema`, §5 Stage 1 gate) is what keeps the
  * two honest.  Where this file departs from Encode it is because a schema
  * has to be decided from the DECLARATION where the encoder can look at the
  * value: an open row, a type variable and a rank-n field are all encodable
  * once a value exists and are all export errors here.
  *
  * The mapping, type by type:
  *
  *  - `Int` -> `{"type":"integer"}`; `Short`/`Byte` the same with
  *    `minimum`/`maximum`; `Long` -> `{"type":"string","pattern":"^-?[0-9]+$"}`
  *    (Encode writes a Long as a decimal string: JSON numbers lose precision
  *    past 2^53); `Double`/`Float` -> `{"type":"number"}`; `Bool` ->
  *    `{"type":"boolean"}`; `String` -> `{"type":"string"}`; `Char` -> the
  *    same with `maxLength: 1`; `Date` -> string/`format: date`;
  *    `Timestamp` -> string/`format: date-time`; `GUID` -> string/`format:
  *    uuid`.  (`Session.toHeader` reads a column's `PrimT` through
  *    `PrimT.withName`, which spells the UUID type "UUID" while the `Con` is
  *    `Builtin.GUID`; this walker never goes through `PrimT`, so the
  *    mismatch cannot arise.)
  *  - `Maybe a` / `Nullable a` -> `{"anyOf":[a,{"type":"null"}]}`; a nested
  *    `Maybe (Maybe a)` is an error, as it is for the encoder (both layers
  *    encode to the same `null`, so the shape is not invertible).
  *  - `List a`, `Native.List.List# a`, `Vector.Vector a` -> an array of `a`.
  *  - a tuple `(a, b, ...)` -> an array with `prefixItems` and
  *    `minItems == maxItems == n`; `()` -> `{"type":"array","maxItems":0}`;
  *    `Native.Pair.Pair# a b` -> the 2-tuple (Encode emits a Scala pair as a
  *    two-element array).
  *  - a closed record `{..(|f1..fn|)}` -> an object whose properties are the
  *    field witnesses' types in SORTED key order (`Rec` is an unordered map,
  *    so the encoder sorts too), `required` = every key,
  *    `additionalProperties: false`.
  *  - an open row (a row variable or a `Part`) -> an error: there is no
  *    schema for "some fields".  Export at an instantiation.
  *  - a `data` type: one `$defs` entry per INSTANTIATION reached, referenced
  *    by `$ref`, so a recursive type terminates.  All-nullary ->
  *    `{"enum":[...]}` in declaration order.  Positional constructors ->
  *    `{"tag": {"const": C}, "args": [...]}` objects, `oneOf` over them when
  *    the type has more than one.  Record-style constructors (fields named,
  *    which is what the named-constructor-fields branch puts in
  *    `DataConDecl.Constructor.fields`) -> an object with the `tag` const
  *    plus the named properties in declaration order; a field whose declared
  *    type is headed by `Builtin.Maybe` is OPTIONAL and its schema is the
  *    Maybe's PAYLOAD, not the `anyOf`-null (the encoder omits the key
  *    instead of writing null); a single-constructor record-style type drops
  *    the `tag` entirely.
  *  - the stdlib `Json` type -> `{}`: any JSON document.  Ermine owns no
  *    contract for it (§3.1b item 1).
  *  - a relation `[..r]` over a closed row -> the columns + rows-as-arrays
  *    object of §3.4a.  NOTE: the ENCODER does not produce this yet.  Stage 0
  *    refuses a relation on the wire (`ArgonautJson.rel`) and `toJson#` makes
  *    a `JRel` node the document writer resolves; the inline shape lands with
  *    Stage 3's `Write.doc`.  The schema is exported now so the TS side can
  *    be written against it, and the `Inline`/`Deferred` wrapper arms of
  *    §3.4a are Stage 3 too.
  *  - `Arrow`, `IO`, `FFI`, `Field`, a `Prim`/`PrimT` witness, any other
  *    foreign type, a rank-n (`Forall`) field and an existentially bound
  *    field are errors carrying the path to the offending node -- for a
  *    constructor field, `<Type>.<Constructor>[<index>]`, the same spelling
  *    `Encode.Error` uses.  The vocabulary is `Encode.reject`'s.
  *  - a type variable anywhere -> "polymorphic; export at an instantiation".
  *    A data type's own parameters are NOT variables by the time they are
  *    walked: the instantiation's arguments are substituted into the
  *    constructor field types first.
  *
  * Type aliases are expanded before anything else.  Output is deterministic:
  * `$defs` is keyed and emitted in sorted order, record properties are
  * sorted, constructors keep declaration order, and no `Loc` or type-variable
  * id reaches the document -- the same input gives byte-identical output, and
  * the order in which modules were loaded cannot be observed.
  */
object Schema {

  final case class Error(path: String, message: String) {
    def report: String = "cannot export " + path + ": " + message
  }

  val dialect = "https://json-schema.org/draft/2020-12/schema"

  /** The CANONICAL TEXT of an exported schema: two-space indented with the
    * keys in the order the exporter wrote them.  argonaut's default printer
    * iterates the field MAP, which is neither insertion order nor sorted and
    * is not even stable across field counts, so `spaces2` alone would make
    * the committed fixtures and the determinism property meaningless.
    * `preserveOrder` prints `JsonObject.toList`, which IS insertion order. */
  val prettyParams: argonaut.PrettyParams = argonaut.PrettyParams.spaces2.copy(preserveOrder = true)
  def text(j: Json): String    = j.pretty(prettyParams)
  def compact(j: Json): String = j.nospacesWithOrder

  /** The name the design note uses.  `export` is a Scala 3 KEYWORD, so the
    * definition needs backticks and every Scala caller inside this build
    * uses `exportType`; the alias is here so the design note's spelling is
    * not a lie and so a 2.11 caller (where `export` is an ordinary
    * identifier) can write it. */
  def `export`(ty: Type, module: String)(implicit s: SessionEnv): Either[Error, Json] =
    exportType(ty, module)

  private final class Reject(val error: Error) extends RuntimeException(error.report, null, false, false)

  /** The JSON Schema 2020-12 document for `ty`, as declared in `module`
    * (which resolves a record's unqualified field names and names the
    * `$id`). */
  def exportType(ty: Type, module: String)(implicit s: SessionEnv): Either[Error, Json] = {
    val ctx = new Ctx(module, s)
    try {
      val root = ctx.walk(ty, "$")
      val head = List(
        "$schema" -> Json.jString(dialect),
        "$id"     -> Json.jString("ermine:" + module + "/" + renderType(ty)))
      val defs =
        if (ctx.defs.isEmpty) Nil
        else List("$defs" -> Json.obj(ctx.defs.toList.sortBy(_._1): _*))
      Right(Json.obj((head ++ root.objectFieldsOrEmpty.map(f => (f, root.field(f).get)) ++ defs): _*))
    } catch { case r: Reject => Left(r.error) }
  }

  /** The schema of a data type named by the module it is declared in, for
    * the `{module, name}` form of the LSP request and `bin/ermine-schema`'s
    * bare-name argument.  Only a type with no parameters can be named this
    * way; a parameterised one needs an instantiation. */
  def exportNamed(module: String, name: String)(implicit s: SessionEnv): Either[Error, Json] =
    s.cons.get(Global(module, name)) match {
      case Some(c) => exportType(c, module)
      case None    => Left(Error("$", "the module " + module + " declares no type " + name))
    }

  // ---------------------------------------------------------------------
  // one walk

  private final class Ctx(module: String, s: SessionEnv) {
    implicit val supply: Supply = Supply.create
    /** def name -> body; emitted sorted, so load order is unobservable. */
    val defs = mutable.HashMap[String, Json]()
    /** def names whose body is still being built (a recursive occurrence). */
    val open = mutable.HashSet[String]()

    def reject(path: String, why: String): Nothing = throw new Reject(Error(path, why))

    def walk(t0: Type, path: String): Json = {
      val t = resolve(t0)
      val (head, args) = unfurl(t)
      head match {
        case Type.Con(_, g, decl, _) => con(g, decl, args, path)
        case ProductT(_, n)          => tuple(n, args, path)
        case Arrow(_)                => reject(path, "a function has no JSON representation")
        case VarT(_)                 => reject(path, "polymorphic; export at an instantiation")
        case _: Forall               => reject(path, "a polymorphic (rank-n) type; export at an instantiation")
        case _: Exists               => reject(path, "an existential has no JSON representation")
        case _: Part                 => reject(path, "open row; export at an instantiation")
        case ConcreteRho(_, _)       => reject(path, "a bare row is not a value type")
        case other                   => reject(path, "no JSON representation for " + other.getClass.getName)
      }
    }

    private def con(g: Global, decl: ConDecl, args: List[Type], path: String): Json =
      if (g.module == "Builtin") builtin(g, args, path)
      else if (g.module == Encode.jsonModule && g.string == "Json") Json.jEmptyObject
      else if (g.module == "Native.List" && g.string == "List#") array(arg1(g, args, path), path + "[]")
      else if (g.module == "Vector" && g.string == "Vector") array(arg1(g, args, path), path + "[]")
      else if (g.module == "Native.Maybe" && g.string == "Maybe#") nullable(arg1(g, args, path), path)
      else if (g.module == "Native.Pair" && g.string == "Pair#") tuple(2, args, path)
      else decl match {
        case d: DataConDecl   => dataType(g, d, args, path)
        case _: FieldConDecl  => reject(path, "a Field witness has no JSON representation")
        case _ => DataConDecl.forType(g) match {
          // a `data` seen through another Con instance (an .ei-loaded
          // interface rebuilds the Con without the decl)
          case Some(d) => dataType(g, d, args, path)
          case None    => reject(path, "the foreign type " + g + " has no JSON representation")
        }
      }

    private def builtin(g: Global, args: List[Type], path: String): Json = g.string match {
      case "Int"       => integer(None, None)
      case "Short"     => integer(Some(java.lang.Short.MIN_VALUE.toLong), Some(java.lang.Short.MAX_VALUE.toLong))
      case "Byte"      => integer(Some(java.lang.Byte.MIN_VALUE.toLong), Some(java.lang.Byte.MAX_VALUE.toLong))
      case "Long"      => Json.obj("type" -> Json.jString("string"), "pattern" -> Json.jString("^-?[0-9]+$"))
      case "Double" | "Float" => Json.obj("type" -> Json.jString("number"))
      case "Bool"      => Json.obj("type" -> Json.jString("boolean"))
      case "String"    => Json.obj("type" -> Json.jString("string"))
      case "Char"      => Json.obj("type" -> Json.jString("string"), "maxLength" -> Json.jNumber(1))
      case "Date"      => Json.obj("type" -> Json.jString("string"), "format" -> Json.jString("date"))
      case "Timestamp" => Json.obj("type" -> Json.jString("string"), "format" -> Json.jString("date-time"))
      case "GUID"      => Json.obj("type" -> Json.jString("string"), "format" -> Json.jString("uuid"))
      case "Maybe" | "Nullable" => nullable(arg1(g, args, path), path)
      case "List"      => array(arg1(g, args, path), path + "[]")
      case "Vector"    => array(arg1(g, args, path), path + "[]")
      case "Record"    => record(arg1(g, args, path), path)
      case "Relation"  => relation(arg1(g, args, path), path)
      case "IO"        => reject(path, "an IO action has no JSON representation")
      case "FFI"       => reject(path, "an FFI value has no JSON representation")
      case "Field"     => reject(path, "a Field witness has no JSON representation")
      case "Prim" | "PrimT" => reject(path, "a PrimT witness has no JSON representation")
      case _           => reject(path, "the foreign type " + g + " has no JSON representation")
    }

    private def arg1(g: Global, args: List[Type], path: String): Type = args match {
      case a :: Nil => a
      case _        => reject(path, g.string + " expects one type argument, not " + args.length +
                                    " (a partially applied type constructor is not a value type)")
    }

    private def integer(lo: Option[Long], hi: Option[Long]): Json =
      Json.obj((("type" -> Json.jString("integer")) ::
                lo.toList.map(l => "minimum" -> Json.jNumber(l)) ++
                hi.toList.map(h => "maximum" -> Json.jNumber(h))): _*)

    private def array(elem: Type, path: String): Json =
      Json.obj("type" -> Json.jString("array"), "items" -> walk(elem, path))

    /** `Maybe a` -> `a | null`.  The encoder writes `Just x` as `x` and
      * `Nothing` as `null`, so a second layer is indistinguishable. */
    private def nullable(inner: Type, path: String): Json = {
      maybePayload(inner) foreach { _ =>
        reject(path, "a nested Maybe (Maybe a) has no JSON representation: both layers encode to null")
      }
      Json.obj("anyOf" -> Json.array(walk(inner, path + "?"), Json.obj("type" -> Json.jString("null"))))
    }

    private def tuple(n: Int, args: List[Type], path: String): Json =
      if (args.length != n)
        reject(path, "a " + n + "-tuple applied to " + args.length + " arguments is not a value type")
      else if (n == 0) Json.obj("type" -> Json.jString("array"), "maxItems" -> Json.jNumber(0))
      else Json.obj(
        "type"        -> Json.jString("array"),
        "prefixItems" -> Json.array(args.zipWithIndex.map { case (a, i) => walk(a, path + "[" + i + "]") }: _*),
        "minItems"    -> Json.jNumber(n),
        "maxItems"    -> Json.jNumber(n))

    // -- rows -------------------------------------------------------------

    /** The declared type of every field of a closed row, in sorted key
      * order.  `Session.toHeader` reads the same witnesses out of
      * `s.cons`; unlike it we keep the `Type` rather than narrowing to a
      * `PrimT`, so `GUID`, `Char` and a nullable field all keep their own
      * schema. */
    private def rowFields(row0: Type, path: String): List[(String, Type)] = {
      val row = resolve(row0)
      row match {
        case ConcreteRho(_, names) =>
          names.toList.map { n =>
            val g = n match {
              case l: Local  => l global module
              case g: Global => g
            }
            s.cons.get(g) match {
              case Some(Type.Con(_, fg, FieldConDecl(ft), _)) => (fg.string, ft)
              case Some(other) => reject(path + "." + g.string, "the field " + g + " is not a field witness: " + other)
              case None        => reject(path + "." + g.string, "no field witness for " + g +
                                                                " is in scope in module " + module)
            }
          }.sortBy(_._1)
        case _: Part | VarT(_) => reject(path, "open row; export at an instantiation")
        case other             => reject(path, "expected a concrete row, found " + other)
      }
    }

    private def record(row: Type, path: String): Json = {
      val fs = rowFields(row, path)
      Json.obj(
        "type"       -> Json.jString("object"),
        "properties" -> Json.obj(fs.map { case (k, t) => (k, walk(t, path + "." + k)) }: _*),
        "required"   -> Json.array(fs.map(f => Json.jString(f._1)): _*),
        "additionalProperties" -> Json.jBool(false))
    }

    /** §3.4a: `{"columns":[{name,type}...],"rows":[[...]...]}`.  Column
      * order is the row's sorted key order, the same order the record
      * encoder uses, and `rows` are arrays in that order. */
    private def relation(row: Type, path: String): Json = {
      val fs = rowFields(row, path)
      val n = fs.length
      val cols = fs.map { case (k, t) =>
        Json.obj(
          "type"       -> Json.jString("object"),
          "properties" -> Json.obj(
            "name" -> Json.obj("const" -> Json.jString(k)),
            "type" -> Json.obj("const" -> Json.jString(columnType(t)))),
          "required"   -> Json.array(Json.jString("name"), Json.jString("type")),
          "additionalProperties" -> Json.jBool(false))
      }
      val rowSchema =
        if (n == 0) Json.obj("type" -> Json.jString("array"), "maxItems" -> Json.jNumber(0))
        else Json.obj(
          "type"        -> Json.jString("array"),
          "prefixItems" -> Json.array(fs.map { case (k, t) => walk(t, path + ".rows[]." + k) }: _*),
          "minItems"    -> Json.jNumber(n),
          "maxItems"    -> Json.jNumber(n))
      Json.obj(
        "type"       -> Json.jString("object"),
        "properties" -> Json.obj(
          "columns" -> Json.obj(
            "type"        -> Json.jString("array"),
            "prefixItems" -> Json.array(cols: _*),
            "minItems"    -> Json.jNumber(n),
            "maxItems"    -> Json.jNumber(n)),
          "rows"    -> Json.obj("type" -> Json.jString("array"), "items" -> rowSchema)),
        "required"   -> Json.array(Json.jString("columns"), Json.jString("rows")),
        "additionalProperties" -> Json.jBool(false))
    }

    /** The column descriptor's `type`: the unqualified Ermine name of the
      * column type with `Nullable` unwrapped.  Nullability stays visible in
      * the row schema (an `anyOf` with null), so this is a label for the
      * client's formatter, not a second source of truth. */
    private def columnType(t: Type): String = resolve(t) match {
      case Type.Nullable(u)        => columnType(u)
      case Type.Con(_, g, _, _)    => g.string
      case u                       => renderType(u)
    }

    // -- data -------------------------------------------------------------

    private def dataType(g: Global, decl: DataConDecl, args: List[Type], path: String): Json = {
      val name = defName(g, args)
      val ref = Json.obj("$ref" -> Json.jString("#/$defs/" + name))
      if (defs.contains(name) || open.contains(name)) ref
      else {
        open += name
        try {
          if (decl.typeArgs.length != args.length)
            reject(path, g.string + " takes " + decl.typeArgs.length + " type " +
                         (if (decl.typeArgs.length == 1) "argument" else "arguments") +
                         ", applied to " + args.length + "; export at an instantiation")
          val sub: Map[TypeVar, Type] = decl.typeArgs.zip(args).toMap
          val cs = decl.constructors
          if (cs.isEmpty) reject(path, g.string + " has no constructors, so it has no values")
          val body =
            if (decl.isEnum) Json.obj("enum" -> Json.array(cs.map(c => Json.jString(c.name.string)): _*))
            else {
              val arms = cs.map(c => constructor(g, c, sub, cs.length == 1))
              if (arms.length == 1) arms.head else Json.obj("oneOf" -> Json.array(arms: _*))
            }
          defs += ((name, body))
        } finally open -= name
        ref
      }
    }

    private def constructor(ty: Global, c: DataConDecl.Constructor,
                            sub: Map[TypeVar, Type], only: Boolean): Json = {
      val base = ty.string + "." + c.name.string
      def path(i: Int) = base + "[" + i + "]"
      if (c.name.string.exists(ch => !(ch.isLetterOrDigit || ch == '_' || ch == '\'')))
        reject(base, "an operator constructor has no stable discriminator tag " +
                     "(a tag must be an alphanumeric constructor name)")
      val ex = c.existentials.toSet
      val fields = c.fields.zipWithIndex.map { case ((nm, t0), i) =>
        if (Type.typeVars(t0).exists(ex)) reject(path(i), "an existential has no JSON representation")
        (nm, Type.subType(sub, t0), i)
      }
      val named = fields.count(_._1.isDefined)
      if (named != 0 && named != fields.length)
        reject(base, "constructor fields are partly named; name all of them or none")
      val tagProp = "tag" -> Json.obj("const" -> Json.jString(c.name.string))
      if (named == fields.length && fields.nonEmpty) {
        // record-style: named properties in declaration order; a Maybe
        // field is an OPTIONAL key carrying the Maybe's payload schema
        val props = fields.map { case (nm, t, i) =>
          val k = nm.get
          maybePayload(t) match {
            case Some(inner) => (k, walk(inner, path(i)), false)
            case None        => (k, walk(t, path(i)), true)
          }
        }
        val required = (if (only) Nil else List("tag")) ++ props.filter(_._3).map(_._1)
        Json.obj(
          "type"       -> Json.jString("object"),
          "properties" -> Json.obj(((if (only) Nil else List(tagProp)) ++
                                    props.map(p => (p._1, p._2))): _*),
          "required"   -> Json.array(required.map(Json.jString): _*),
          "additionalProperties" -> Json.jBool(false))
      } else {
        val n = fields.length
        val args =
          if (n == 0) Json.obj("type" -> Json.jString("array"), "maxItems" -> Json.jNumber(0))
          else Json.obj(
            "type"        -> Json.jString("array"),
            "prefixItems" -> Json.array(fields.map { case (_, t, i) => walk(t, path(i)) }: _*),
            "minItems"    -> Json.jNumber(n),
            "maxItems"    -> Json.jNumber(n))
        Json.obj(
          "type"       -> Json.jString("object"),
          "properties" -> Json.obj(tagProp, "args" -> args),
          "required"   -> Json.array(Json.jString("tag"), Json.jString("args")),
          "additionalProperties" -> Json.jBool(false))
      }
    }

    /** `Some(a)` when `t` is headed by `Builtin.Maybe` (or `Nullable`, or
      * the native `Maybe#`) -- the test the record-style rule and the
      * nested-Maybe refusal share. */
    private def maybePayload(t: Type): Option[Type] = unfurl(resolve(t)) match {
      case (Type.Con(_, g, _, _), a :: Nil)
        if (g.module == "Builtin" && (g.string == "Maybe" || g.string == "Nullable")) ||
           (g.module == "Native.Maybe" && g.string == "Maybe#") => Some(a)
      case _ => None
    }

    /** Expand type aliases to a fixed point.  `Type.expandAlias` reports
      * `Unexpanded` whenever the OUTERMOST head is not itself an alias, so
      * `type Ints = List Int` comes back as `Unexpanded(List Int)` -- an
      * expansion nonetheless.  The fixed point is therefore "the type stopped
      * changing", not "the result said Expanded"; the fuel bound is there
      * because an alias cycle is a load-time error this walker should not
      * hang on. */
    private def resolve(t: Type): Type = {
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

  // ---------------------------------------------------------------------
  // pure helpers (no session, no supply): naming and rendering

  private def strip(t: Type): Type = t match {
    case Memory(_, b)                  => strip(b)
    case Forall(_, Nil, Nil, _, b)     => strip(b)
    case other                         => other
  }

  private def unfurl(t: Type, args: List[Type] = Nil): (Type, List[Type]) = t match {
    case AppT(f, a)   => unfurl(f, strip(a) :: args)
    case Memory(_, u) => unfurl(u, args)
    case other        => (other, args)
  }

  /** The `$defs` key of one instantiation: the module-qualified type name
    * with its arguments appended, sanitised to `[A-Za-z0-9_.]`.  `data Tree
    * a` at `Int` in module `Test` is `Test.Tree_Int`.  Structural types
    * (`Maybe`, `List`, records, tuples) never get a key -- they are inlined,
    * so only a `data` instantiation can be recursive. */
  def defName(g: Global, args: List[Type]): String =
    sanitise(g.module + "." + g.string + args.map(a => "_" + keyOf(a)).mkString)

  private def keyOf(t: Type): String = unfurl(strip(t)) match {
    case (Type.Con(_, g, _, _), as)  => (g.string :: as.map(keyOf)).mkString("_")
    case (ProductT(_, n), as)        => ("Tuple" + n :: as.map(keyOf)).mkString("_")
    case (ConcreteRho(_, fs), _)     => ("Row" :: fs.toList.map(_.string).sorted).mkString("_")
    case (VarT(v), _)                => v.name.map(_.string).getOrElse("_")
    case (Arrow(_), as)              => ("Fun" :: as.map(keyOf)).mkString("_")
    case (other, _)                  => "T"
  }

  private def sanitise(s: String): String =
    s.map(c => if (c.isLetterOrDigit || c == '_' || c == '.') c else '_')

  /** A stable, id-free rendering of a monomorphic type, for `$id` and for
    * error messages: `Either String Int`, `Maybe (List Int)`,
    * `{..(|x, y|)}`, `[..(|x|)]`, `(Int, String)`. */
  def renderType(t: Type): String = unfurl(strip(t)) match {
    case (Type.Con(_, g, _, _), as) if g == Global("Builtin", "Record") && as.length == 1 =>
      "{.." + renderType(as.head) + "}"
    case (Type.Con(_, g, _, _), as) if g == Global("Builtin", "Relation") && as.length == 1 =>
      "[.." + renderType(as.head) + "]"
    case (Type.Con(_, g, _, _), as) => (g.string :: as.map(paren)).mkString(" ")
    case (ProductT(_, 0), Nil)      => "()"
    case (ProductT(_, n), as) if as.length == n => as.map(renderType).mkString("(", ", ", ")")
    case (ProductT(_, n), as)       => (("Tuple" + n) :: as.map(paren)).mkString(" ")
    case (ConcreteRho(_, fs), _)    => fs.toList.map(_.string).sorted.mkString("(|", ", ", "|)")
    case (VarT(v), as)              => (v.name.map(_.string).getOrElse("_") :: as.map(paren)).mkString(" ")
    case (Arrow(_), a :: b :: Nil)  => paren(a) + " -> " + renderType(b)
    case (Arrow(_), as)             => ("(->)" :: as.map(paren)).mkString(" ")
    case (_: Forall, _)             => "forall"
    case (_: Exists, _)             => "exists"
    case (_: Part, _)               => "<partition>"
    case (other, _)                 => other.toString
  }

  private def paren(t: Type): String = {
    val s = renderType(t)
    if (s.contains(' ') && !s.startsWith("(") && !s.startsWith("{") && !s.startsWith("[")) "(" + s + ")" else s
  }
}

/** The `ermine/schema` LSP request (tracker/JSON-API-DESIGN.md §3.5's second
  * entry point): the same export, answered out of the editor's already booted
  * session instead of paying `bin/ermine-schema`'s boot.
  *
  * {{{
  *   --> {"method":"ermine/schema","params":{"module":"Ord","type":"Ordering"}}
  *   --> {"method":"ermine/schema","params":{"module":"Ord","name":"Ordering"}}
  *   <-- { "$schema": ..., "$id": "ermine:Ord/Ordering", ... }
  *   <-- {"error":"cannot export $: ..."}
  * }}}
  *
  * The answer is built in the server's OWN `lsp.Json` (`lsp/Rpc.scala`), which
  * is what the protocol writer prints; argonaut stops at this boundary.  The
  * handler lives here rather than in `lsp/` so the exporter owns its own wire
  * shape -- `lsp/Definitions.scala` holds one line that calls it.
  */
object LspSchema {
  import com.clarifi.reporting.ermine.lsp.{ Json => LJson, Resident }
  import com.clarifi.reporting.ermine.session.Session
  import com.clarifi.reporting.ermine.rename.NewPipeline
  import com.clarifi.reporting.ermine.syntax.Explicit
  import com.clarifi.reporting.ermine.Global
  import scala.util.control.NonFatal

  private def err(msg: String): LJson = LJson.obj("error" -> LJson.Str(msg))

  /** argonaut's tree in the server's ADT.  A number is printed by
    * `lsp.Json.Num`'s whole-number rule, which is what every count and bound
    * the exporter emits wants. */
  def toLsp(j: argonaut.Json): LJson =
    j.fold(
      LJson.Null,
      b => LJson.Bool(b),
      n => LJson.Num(n.toBigDecimal.toDouble),
      s => LJson.Str(s),
      xs => LJson.Arr(xs.map(toLsp)),
      o  => LJson.Obj(o.toList.map(kv => (kv._1, toLsp(kv._2)))))

  def answer(ermine: Resident, params: LJson): LJson = {
    val module = params / "module" flatMap (_.str)
    val tyExpr = params / "type" flatMap (_.str)
    val named  = params / "name" flatMap (_.str)
    module match {
      case None => err("ermine/schema needs a \"module\"")
      case Some(m) =>
        try ermine.withEnv { implicit env =>
          implicit val su: scalaparsers.Supply = ermine.supply
          implicit val pr: com.clarifi.reporting.ermine.session.Printer = ermine.printer
          Session.loadModules(List(m))
          val all: (Option[String], List[Explicit[Global]], Boolean) = (None, List(), false)
          val result = (tyExpr, named) match {
            case (Some(t), _) =>
              val ty = NewPipeline.replType("<ermine/schema>", t, Map("Builtin" -> all, m -> all))
              Schema.exportType(ty, m)
            case (None, Some(n)) => Schema.exportNamed(m, n)
            case (None, None)    =>
              Left(Schema.Error("$", "ermine/schema needs a \"type\" expression or a \"name\""))
          }
          result match {
            case Right(j) => toLsp(j)
            case Left(e)  => err(e.report)
          }
        } catch {
          case scalaparsers.Death(d, _) => err(d.toString)
          case NonFatal(e)              => err(Option(e.getMessage).getOrElse(e.toString))
        }
    }
  }
}
