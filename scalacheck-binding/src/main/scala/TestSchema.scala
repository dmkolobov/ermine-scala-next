package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.json.{ ArgonautJson, Delivery, Encode, JsonBuilder, Schema, Validate, Wire, Zod }
import com.clarifi.reporting.relational.{ ExtRel, SmallLit }
import com.clarifi.reporting.ermine.rename.NewPipeline
import com.clarifi.reporting.ermine.session.{ Session, SessionEnv }

import org.scalacheck._
import Prop.{ Result => _, _ }
import argonaut.Json

/** The JSON SCHEMA EXPORTER (core/json/Schema.scala, tracker/JSON-API-DESIGN.md
  * §3.5, Stage 1b): the type walker, the validator, the zod generator, the
  * committed gate fixtures.
  *
  * THE property of this stage is the first one: for a random Ermine TYPE and a
  * random VALUE of it, the document `Encode` writes validates against the
  * schema `Schema` exports with zero errors.  That is what makes the value
  * walker and the type walker one mapping rather than two, and it is the §5
  * Stage 1 gate.  Everything else here supports it: the validator is only as
  * general as the schemas the exporter emits (`json/Validate.scala`), the
  * negative properties are what stop the validator from passing everything,
  * and the fixtures turn a change in the mapping into a reviewable diff.
  *
  * The generator builds Ermine SOURCE: a list of declarations (the `field`s a
  * record needs, the `data`s a constructor needs) plus an expression, loaded
  * as one `module Test` and evaluated.  `Shape` is the whole vocabulary --
  * adding a kind of type is one entry in `shape`.
  *
  * WHEN NAMED CONSTRUCTOR FIELDS LAND (the parallel branch): add ONE case to
  * `shape`'s `Gen.oneOf` list, a `recordStyleData` beside `positionalData`
  * below, emitting `data Dn = Cn { f1 : t1, ... }` and a value
  * `(Cn { f1 = v1, ... })`; the exporter already treats a `Some(name)` field
  * as a named property and a `Maybe`-headed one as an optional key, so the
  * consistency property covers the new shape the moment the generator can
  * produce it.  Nothing else in this file changes.
  */
object TestSchema extends Properties("Ermine JSON Schema") {
  private lazy val ermineFixture = ErmineFixture()
  import ermineFixture._

  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Json" -> all, "List" -> all,
        "Maybe" -> all, "Function" -> all, "Int" -> all, "Num" -> all)

  // ---------------------------------------------------------------------
  // running one generated case

  /** Load `decls` as `module Test`, evaluate `expr`, and return its
    * published type beside its value -- the two inputs of the consistency
    * property.  `ErmineFixture.defAndEval` throws the type away. */
  def defAndType(decls: String, expr: String): (Type, Runtime) =
    session { implicit env =>
      loadStatements(decls, imps)
      Session.eval(expr, imps)
    }

  /** The schema of a type expression parsed against `mods`, for a type that
    * needs no `Test` module (the standard-library gate types). */
  def schemaOf(mods: List[String], module: String, tyExpr: String): Either[Schema.Error, Json] =
    session { implicit env =>
      Session.loadModules(mods)
      val importSpecs = (("Builtin" -> all) :: mods.map(m => (m, all))).toMap
      val ty = NewPipeline.replType("<gate>", tyExpr, importSpecs)
      Schema.exportType(ty, module)
    }

  /** The schema of a type expression parsed against a freshly loaded `Test`
    * module -- what a user record, relation or recursive `data` needs. */
  def schemaAfter(decls: String, tyExpr: String, im: Map[String, ImportSpec] = imps): Either[Schema.Error, Json] =
    session { implicit env =>
      loadStatements(decls, im)
      Schema.exportType(NewPipeline.replType("<gate>", tyExpr, im), "Test")
    }

  /** The relation properties' imports (J3a): `mkRelation#`/`toList#`, the
    * `Prim` witnesses a `Null` names, and the Date/Timestamp/GUID
    * constructors. */
  val relImps: Map[String, ImportSpec] =
    imps ++ Map("Native.List" -> all, "Date" -> all, "GUID" -> all, "Prim" -> all)

  // ---------------------------------------------------------------------
  // the generator: random Ermine types with random values of them

  /** One generated type: its source, the declarations it needs (deduplicated
    * before they are emitted) and a generator of value source.  `rels`
    * counts the relation positions in the TYPE (J3a): a shape with any is
    * not encodable by `Encode.toArgonaut` and only the relation properties
    * below generate one. */
  final case class Shape(ty: String, decls: List[String], value: Gen[String], rels: Int = 0)

  private val counter = new java.util.concurrent.atomic.AtomicInteger(0)
  /** A name no other declaration in the process has used.  The counter, not
    * a random suffix, so two shapes in ONE case can never collide. */
  private def fresh(prefix: String): Gen[String] =
    Gen.const(()).map(_ => prefix + counter.incrementAndGet())

  private val litString: Gen[String] =
    Gen.choose(0, 8).flatMap(n => Gen.listOfN(n, Gen.alphaNumChar)).map(cs => "\"" + cs.mkString + "\"")

  /** Non-negative literals only: `C -3` parses the minus as an operator, and
    * the sign is not what this generator is about.  Negative numbers have
    * their own properties below. */
  private val prims: List[Shape] = List(
    Shape("Int",    Nil, Gen.choose(0, 100000).map(_.toString)),
    Shape("Long",   Nil, Gen.choose(0L, Long.MaxValue).map(_.toString + "L")),
    Shape("Double", Nil, Gen.choose(0, 100000000).map(n => (n / 100.0).toString)),
    Shape("Bool",   Nil, Gen.oneOf("True", "False")),
    Shape("String", Nil, litString))

  /** The record field pool.  A field's TYPE is fixed by its NAME, so two
    * records generated into one module always agree about a shared key --
    * which is what `field` declarations require. */
  private val fieldPool: List[(String, String)] =
    List(("sfInt", "Int"), ("sfLong", "Long"), ("sfDouble", "Double"),
         ("sfBool", "Bool"), ("sfString", "String"))

  private def primFor(ty: String): Shape = prims.find(_.ty == ty).get

  /** `n` distinct elements of `xs`, uniformly.  NOT `Gen.pick`: ScalaCheck
    * 1.15.4's reservoir step computes `x & Long.MaxValue % count`, which
    * parses as `x & (Long.MaxValue % count)`, so the replacement index is
    * badly biased and the FIRST element is almost never kept -- found by
    * (r-a)'s coverage check, which never met the pool's first column. */
  def pickN[A](n: Int, xs: List[A]): Gen[List[A]] =
    Gen.listOfN(xs.length, Gen.choose(0L, Long.MaxValue)).map(keys => xs.zip(keys).sortBy(_._2).take(n).map(_._1))

  /** A relation column (J3a): the field's name and declared type, the header
    * `PrimT` a table over it carries -- the document writer reads a column
    * descriptor off that, through `Wire.columnType` -- and a generator of
    * value source.  All ten column types, each plain and `Nullable`; as in
    * `fieldPool`, a name fixes the type.  Negative numbers are written
    * `(0s - 5s)`, the only spelling a constructor argument accepts. */
  final case class Col(name: String, ty: String, prim: PrimT, value: Gen[String])

  private def signed(n: Long, suffix: String): String =
    if (n < 0) "(0" + suffix + " - " + (-n) + suffix + ")" else n.toString + suffix

  private val hexGuid: Gen[String] =
    Gen.listOfN(32, Gen.oneOf("0123456789abcdef".toList)).map { cs =>
      val s = cs.mkString
      s.substring(0, 8) + "-" + s.substring(8, 12) + "-" + s.substring(12, 16) + "-" +
        s.substring(16, 20) + "-" + s.substring(20)
    }

  private val baseColumns: List[(String, PrimT, Gen[String])] = List(
    ("Int",       PrimT.IntT(false),       Gen.choose(-100000L, 100000L).map(signed(_, ""))),
    ("Long",      PrimT.LongT(false),      Gen.choose(-Long.MaxValue, Long.MaxValue).map(signed(_, "L"))),
    ("Double",    PrimT.DoubleT(false),    Gen.choose(-100000000L, 100000000L).map(n =>
                                             if (n < 0) "(0.0 - " + ((-n) / 100.0) + ")" else (n / 100.0).toString)),
    ("Bool",      PrimT.BooleanT(false),   Gen.oneOf("True", "False")),
    ("String",    PrimT.StringT(0, false), litString),
    ("Short",     PrimT.ShortT(false),     Gen.choose(-32767L, 32767L).map(signed(_, "s"))),
    ("Byte",      PrimT.ByteT(false),      Gen.choose(-127L, 127L).map(signed(_, "b"))),
    ("Date",      PrimT.DateT(false),      for { y <- Gen.choose(1900, 2100); m <- Gen.choose(1, 12); d <- Gen.choose(1, 28) }
                                           yield "(yyyymmdd " + y + " " + m + " " + d + ")"),
    ("Timestamp", PrimT.TimestampT(false), Gen.choose(-2208988800000L, 4102444800000L)
                                             .map(n => "(timestampFromLong " + signed(n, "L") + ")")),
    ("GUID",      PrimT.UuidT(false),      hexGuid.map(g => "(stringGuid \"" + g + "\")")))

  val columnPool: List[Col] = baseColumns.flatMap { case (t, p, v) =>
    List(Col("sc" + t, t, p, v),
         Col("scN" + t, "Nullable " + t, p.withNull,
             Gen.frequency((1, Gen.const("(Null " + t + ")")), (3, v.map(x => "(Some " + x + ")")))))
  }

  /** One to six distinct columns, in sorted name order (the wire's). */
  val columnsGen: Gen[List[Col]] =
    Gen.choose(1, 6).flatMap(n => pickN(n, columnPool)).map(_.sortBy(_.name))

  def recordGen(cols: List[Col]): Gen[String] =
    Gen.sequence[List[String], String](cols.map(_.value))
      .map(vs => cols.zip(vs).map { case (c, v) => c.name + " = " + v }.mkString("{ ", ", ", " }"))

  def fieldDecls(cols: List[Col]): List[String] = cols.map(c => "field " + c.name + " : " + c.ty)
  def rowType(cols: List[Col]): String = cols.map(_.name).mkString("[", ", ", "]")
  /** The row itself, `(|a, b|)`: what `Inline` and `Deferred` take (`data
    * Inline r = Inline [..r]`), so `Inline (|a, b|)` is `Inline` of `[a, b]`. */
  def rowOf(cols: List[Col]): String = cols.map(_.name).mkString("(|", ", ", "|)")

  private def listOfGen(g: Gen[String]): Gen[String] =
    Gen.choose(0, 3).flatMap(n => Gen.listOfN(n, g)).map(_.mkString("[", ", ", "]"))

  /** `depth` bounds nesting; `underMaybe` keeps `Maybe (Maybe a)` out, which
    * the mapping rejects on purpose (both layers encode to `null`).  `rels`
    * adds relations -- bare, `Inline` and `Deferred`, over random closed rows
    * of the column pool -- as a fourth leaf, anywhere in the tree (J3a). */
  def shape(depth: Int, underMaybe: Boolean = false, rels: Boolean = false): Gen[Shape] = {
    val leaves: List[Gen[Shape]] =
      Gen.oneOf(prims) :: Gen.const(Shape("()", Nil, Gen.const("()"))) :: enumData ::
      (if (rels) List(relationShape) else Nil)
    if (depth <= 0) Gen.oneOf(leaves).flatMap(identity)
    else {
      val composites: List[Gen[Shape]] =
        listShape(depth, rels) :: tupleShape(depth, rels) :: recordShape ::
        positionalData(depth, rels) :: recordStyleData(depth, rels) :: parameterisedData(depth, rels) :: recursiveData ::
        (if (underMaybe) Nil else List(maybeShape(depth, rels)))
      Gen.oneOf(leaves ++ composites).flatMap(identity)
    }
  }

  private def maybeShape(depth: Int, rels: Boolean): Gen[Shape] =
    shape(depth - 1, underMaybe = true, rels = rels).map { a =>
      Shape("(Maybe " + a.ty + ")", a.decls,
            Gen.frequency((1, Gen.const("Nothing")), (3, a.value.map(v => "(Just " + v + ")"))), a.rels)
    }

  private def listShape(depth: Int, rels: Boolean): Gen[Shape] =
    shape(depth - 1, rels = rels).map(a => Shape("(List " + a.ty + ")", a.decls, listOfGen(a.value), a.rels))

  private def tupleShape(depth: Int, rels: Boolean): Gen[Shape] =
    Gen.choose(2, 3).flatMap(n => Gen.listOfN(n, shape(depth - 1, rels = rels))).map { as =>
      Shape(as.map(_.ty).mkString("(", ", ", ")"), as.flatMap(_.decls),
            Gen.sequence[List[String], String](as.map(_.value)).map(_.mkString("(", ", ", ")")),
            as.map(_.rels).sum)
    }

  private def recordShape: Gen[Shape] =
    Gen.choose(1, fieldPool.length).flatMap(n => pickN(n, fieldPool)).map { chosen =>
      val fs = chosen.toList.sortBy(_._1)
      Shape(fs.map(_._1).mkString("{", ", ", "}"),
            fs.map { case (n, t) => "field " + n + " : " + t },
            Gen.sequence[List[String], String](fs.map(f => primFor(f._2).value))
              .map(vs => fs.map(_._1).zip(vs).map(kv => kv._1 + " = " + kv._2).mkString("{ ", ", ", " }")))
    }

  /** A relation over random columns, bare or wrapped, holding one to three
    * literal records: the J3a leaf. */
  private def relationShape: Gen[Shape] =
    for {
      cols <- columnsGen
      w    <- Gen.oneOf("Inline", "Deferred", "")
    } yield {
      def wrap(s: String) = if (w.isEmpty) s else "(" + w + " " + s + ")"
      Shape(if (w.isEmpty) rowType(cols) else wrap(rowOf(cols)), fieldDecls(cols),
            Gen.choose(1, 3).flatMap(k => Gen.listOfN(k, recordGen(cols)))
              .map(rs => wrap("(mkRelation# (toList# " + rs.mkString("[", ", ", "]") + "))")),
            1)
    }

  private def enumData: Gen[Shape] =
    for {
      d  <- fresh("E")
      n  <- Gen.choose(1, 4)
    } yield {
      val cons = (1 to n).toList.map(i => d + "c" + i)
      Shape(d, List("data " + d + " = " + cons.mkString(" | ")), Gen.oneOf(cons))
    }

  private def positionalData(depth: Int, rels: Boolean): Gen[Shape] =
    for {
      d     <- fresh("D")
      arity <- Gen.choose(1, 3)
      ctors <- Gen.listOfN(arity, Gen.choose(0, 2).flatMap(k => Gen.listOfN(k, shape(depth - 1, rels = rels))))
    } yield positionalDecl(d, ctors)

  private def positionalDecl(d: String, ctors: List[List[Shape]]): Shape = {
    val named = ctors.zipWithIndex.map { case (fs, i) => (d + "c" + (i + 1), fs) }
    val decl = "data " + d + " = " +
      named.map { case (c, fs) => (c :: fs.map(_.ty)).mkString(" ") }.mkString(" | ")
    Shape(d, decl :: named.flatMap(_._2.flatMap(_.decls)),
          Gen.oneOf(named).flatMap { case (c, fs) =>
            Gen.sequence[List[String], String](fs.map(_.value))
              .map(vs => (c :: vs).mkString("(", " ", ")")) },
          ctors.flatten.map(_.rels).sum)
  }

  /** `data Rn = Rnc1 { rnc1f0 : t, ... } | Rnc2 { ... }` (Stage 1a, named
    * constructor fields): named properties in declaration order, a `tag`
    * only from two constructors up, and a `Maybe`-headed field is an
    * OPTIONAL key (Nothing -> absent).  Field names are unique per
    * constructor so no two selectors collide.  Values are built
    * POSITIONALLY: record construction syntax is not part of Stage 1. */
  private def recordStyleData(depth: Int, rels: Boolean): Gen[Shape] =
    for {
      d     <- fresh("R")
      arity <- Gen.choose(1, 3)
      ctors <- Gen.listOfN(arity, Gen.choose(1, 3).flatMap(k => Gen.listOfN(k, shape(depth - 1, rels = rels))))
    } yield recordStyleDecl(d, ctors)

  private def recordStyleDecl(d: String, ctors: List[List[Shape]]): Shape = {
    val named = ctors.zipWithIndex.map { case (fs, i) =>
      (d + "c" + (i + 1), fs.zipWithIndex.map { case (f, j) => (d.toLowerCase + "c" + (i + 1) + "f" + j, f) })
    }
    val decl = "data " + d + " = " + named.map { case (c, fs) =>
      c + " { " + fs.map { case (n, f) => n + " : " + f.ty }.mkString(", ") + " }"
    }.mkString(" | ")
    Shape(d, decl :: named.flatMap(_._2.flatMap(_._2.decls)),
          Gen.oneOf(named).flatMap { case (c, fs) =>
            Gen.sequence[List[String], String](fs.map(_._2.value))
              .map(vs => (c :: vs).mkString("(", " ", ")")) },
          ctors.flatten.map(_.rels).sum)
  }

  /** `data Dn a = Dna a | Dnb a a`, exported at an instantiation: the
    * exporter substitutes the argument into the constructor field types, so
    * a type PARAMETER is never the "polymorphic" error. */
  private def parameterisedData(depth: Int, rels: Boolean): Gen[Shape] =
    for {
      d <- fresh("P")
      a <- shape(depth - 1, rels = rels)
    } yield {
      val decl = "data " + d + " a = " + d + "a a | " + d + "b a a"
      Shape("(" + d + " " + a.ty + ")", decl :: a.decls,
            Gen.oneOf(
              a.value.map(v => "(" + d + "a " + v + ")"),
              Gen.zip(a.value, a.value).map(p => "(" + d + "b " + p._1 + " " + p._2 + ")")).flatMap(identity),
            a.rels)
    }

  /** `data Tn = Tna Int | Tnb Tn Tn ...` with a random branching arity: the
    * `$defs`/`$ref` case.  Values are random trees of random depth. */
  private def recursiveData: Gen[Shape] =
    for {
      d     <- fresh("T")
      arity <- Gen.choose(1, 3)
    } yield {
      val leaf = d + "leaf"
      val node = d + "node"
      val decl = "data " + d + " = " + leaf + " Int | " + node + " " + List.fill(arity)(d).mkString(" ")
      def tree(k: Int): Gen[String] =
        if (k <= 0) Gen.choose(0, 99).map(n => "(" + leaf + " " + n + ")")
        else Gen.frequency(
          (1, Gen.choose(0, 99).map(n => "(" + leaf + " " + n + ")")),
          (2, Gen.sequence[List[String], String](List.fill(arity)(tree(k - 1)))
                .map(kids => "(" + node + " " + kids.mkString(" ") + ")")))
      Shape(d, List(decl), Gen.choose(0, 3).flatMap(tree))
    }

  /** A shape with a value of it, as one sample. */
  val typeAndValue: Gen[(Shape, String)] =
    shape(3).flatMap(sh => sh.value.map(v => (sh, v)))

  /** `n` samples of `g`, drawn from fixed seeds: a property that wants an
    * exact case count (the Stage 1 gate says 200) rather than ScalaCheck's
    * default hundred, without moving every other property's budget. */
  def samples[A](g: Gen[A], n: Int, seed0: Long = 20260914L): List[A] = {
    val p = Gen.Parameters.default.withSize(12)
    (0 until n).toList.flatMap(i => g.apply(p, rng.Seed(seed0 + i)))
  }

  /** One generated case: load it, encode the value, export the schema of its
    * type, validate.  Returns the complaint, or None when they agree. */
  def consistent(sh: Shape, v: String): Option[String] = {
    val decls = (sh.decls.distinct ++ List("gv : " + sh.ty, "gv = " + v)).mkString("\n")
    try {
      val (ty, rt) = defAndType(decls, "gv")
      session { implicit env =>
        loadStatements(decls, imps)
        (Schema.exportType(ty, "Test"), Encode.toArgonaut(rt)) match {
          case (Left(e), _)  => Some("export refused " + sh.ty + ": " + e.report + "\n" + decls)
          case (_, Left(e))  => Some("encode refused " + sh.ty + ": " + e.report + "\n" + decls)
          case (Right(schema), Right(doc)) =>
            val errs = Validate.check(schema, doc)
            if (errs.isEmpty) None
            else Some(errs.mkString("; ") + "\n  type " + sh.ty + "\n  doc " + doc.nospacesWithOrder +
                      "\n  schema " + Schema.compact(schema) + "\n" + decls)
        }
      }
    } catch { case e: Throwable => Some("threw " + e + "\n" + decls) }
  }

  // ---------------------------------------------------------------------
  // (a) THE property: encode and export agree

  property("(a) every generated value validates against its type's schema (200 cases)") = {
    val cases = samples(typeAndValue, 200)
    val bad = cases.flatMap { case (sh, v) => consistent(sh, v) }
    (bad.isEmpty :| ("cases: " + cases.length + "\n" + bad.take(3).mkString("\n---\n"))) &&
      ((cases.length == 200) :| ("generated " + cases.length + " of 200 cases"))
  }

  property("(a2) the same, with ScalaCheck's own shrinking generator") =
    forAllNoShrink(typeAndValue) { (tv: (Shape, String)) =>
      consistent(tv._1, tv._2) match {
        case None    => proved
        case Some(m) => falsified :| m
      }
    }

  // -- the primitive corners the generator deliberately leaves out ---------

  property("(a3) negative numbers, Char, and the empty record") = sessionProof { implicit s =>
    def agree(decls: String, ty: String, v: String): Unit = {
      val full = (decls.split("\n").filter(_.nonEmpty).toList ++ List("gv : " + ty, "gv = " + v)).mkString("\n")
      val (t, rt) = defAndType(full, "gv")
      session { implicit e2 =>
        loadStatements(full, imps)
        val schema = Schema.exportType(t, "Test").fold(er => sys.error(er.report), identity)
        val doc = Encode.toArgonaut(rt).fold(er => sys.error(er.report), identity)
        val errs = Validate.check(schema, doc)
        assert(errs.isEmpty, ty + " = " + v + ": " + errs.mkString("; ") +
                             " doc " + doc.nospacesWithOrder + " schema " + Schema.compact(schema))
      }
    }
    agree("", "Int", "(0 - 7)")
    agree("", "Long", "(0L - 7L)")
    agree("", "Double", "(0.0 - 2.5)")
    agree("", "(List Int)", "[]")
    agree("", "(Maybe Int)", "Nothing")
    agree("", "(List (Maybe String))", "[Just \"a\", Nothing]")
  }

  // ---------------------------------------------------------------------
  // (b) the validator actually rejects: mutate the document

  property("(b) a mutated document is reported at the mutated path") = sessionProof { implicit s =>
    val decls = List("field sfInt : Int", "field sfString : String",
                     "data Shp = Circ Double | Rect Double Double | Dot").mkString("\n")
    val rec = schemaAfter(decls, "{sfInt, sfString}").fold(e => sys.error(e.report), identity)
    val shp = schemaAfter(decls, "Shp").fold(e => sys.error(e.report), identity)
    val recDoc = Json.obj("sfInt" -> Json.jNumber(1), "sfString" -> Json.jString("a"))
    val shpDoc = Json.obj("tag" -> Json.jString("Rect"),
                          "args" -> Json.array(Json.jNumber(1.5).get, Json.jNumber(2.5).get))
    assert(Validate.check(rec, recDoc).isEmpty, Validate.check(rec, recDoc).mkString)
    assert(Validate.check(shp, shpDoc).isEmpty, Validate.check(shp, shpDoc).mkString)

    def reports(name: String, schema: Json, doc: Json, path: String): Unit = {
      val errs = Validate.check(schema, doc)
      assert(errs.nonEmpty, name + ": the validator accepted a mutated document " + doc.nospacesWithOrder)
      assert(errs.exists(_.startsWith(path)),
             name + ": expected a complaint at " + path + ", got " + errs.mkString("; "))
    }
    // a required key dropped
    reports("dropped key", rec, Json.obj("sfInt" -> Json.jNumber(1)), "$")
    // a number where a string goes
    reports("wrong type", rec,
            Json.obj("sfInt" -> Json.jNumber(1), "sfString" -> Json.jNumber(2)), "$.sfString")
    // an extra key in a closed record
    reports("extra key", rec,
            Json.obj("sfInt" -> Json.jNumber(1), "sfString" -> Json.jString("a"),
                     "sfBogus" -> Json.jBool(true)), "$.sfBogus")
    // a tag that names no constructor
    reports("bad tag", shp,
            Json.obj("tag" -> Json.jString("Square"),
                     "args" -> Json.array(Json.jNumber(1.5).get, Json.jNumber(2.5).get)), "$")
    // the right tag, the wrong arity
    reports("bad arity", shp,
            Json.obj("tag" -> Json.jString("Rect"), "args" -> Json.array(Json.jNumber(1.5).get)), "$")
    // a string where a number goes, inside the arm
    reports("wrong element", shp,
            Json.obj("tag" -> Json.jString("Rect"),
                     "args" -> Json.array(Json.jString("x"), Json.jNumber(2.5).get)), "$")
  }

  property("(b2) the validator checks the three formats it promises") = sessionProof { implicit s =>
    val date = Json.obj("type" -> Json.jString("string"), "format" -> Json.jString("date"))
    val ts   = Json.obj("type" -> Json.jString("string"), "format" -> Json.jString("date-time"))
    val uuid = Json.obj("type" -> Json.jString("string"), "format" -> Json.jString("uuid"))
    assert(Validate.check(date, Json.jString("2026-09-14")).isEmpty)
    assert(Validate.check(date, Json.jString("14/09/2026")).nonEmpty)
    // the encoder's own spelling: ISO-8601 with milliseconds and Z
    assert(Validate.check(ts, Json.jString("2026-09-14T12:34:56.789Z")).isEmpty)
    assert(Validate.check(ts, Json.jString("2026-09-14 12:34:56")).nonEmpty)
    assert(Validate.check(uuid, Json.jString("3f2504e0-4f89-11d3-9a0c-0305e82c3301")).isEmpty)
    assert(Validate.check(uuid, Json.jString("not-a-uuid")).nonEmpty)
  }

  // ---------------------------------------------------------------------
  // (c) determinism

  /** (c), extended by J3a: the shapes now include relations (bare, `Inline`,
    * `Deferred`) anywhere in the tree, and the second export sees the
    * declarations in REVERSE order in a session that loaded another module
    * and exported another type first -- so neither declaration order nor
    * load order may reach the text. */
  property("(c) exporting twice is byte-identical across declaration and load order") =
    forAllNoShrink(shape(3, rels = true)) { (sh: Shape) =>
      val decls = sh.decls.distinct
      val a = schemaAfter(decls.mkString("\n"), sh.ty, relImps)
      val b = session { implicit env =>
        ermineFixture.loadModules(List("Relation.Sort"))
        Schema.exportType(NewPipeline.replType("<gate>", "SortOrder", Map("Builtin" -> all, "Relation.Sort" -> all)),
                          "Relation.Sort")
        loadStatements(decls.reverse.mkString("\n"), relImps)
        Schema.exportType(NewPipeline.replType("<gate>", sh.ty, relImps), "Test")
      }
      (a, b) match {
        case (Right(x), Right(y)) =>
          (Schema.text(x) == Schema.text(y)) :| ("not identical for " + sh.ty)
        case (Left(x), Left(y)) => (x == y) :| "errors differ"
        case _                  => falsified :| ("one export refused for " + sh.ty + ": " + a + " / " + b)
      }
    }

  property("(c2) $defs order and property order do not follow declaration order") =
    sessionProof { implicit s =>
      val a = List("data Za = Za1 Int | Za2 Zb", "data Zb = Zb1 String").mkString("\n")
      val b = List("data Zb = Zb1 String", "data Za = Za1 Int | Za2 Zb").mkString("\n")
      val sa = schemaAfter(a, "Za").fold(e => sys.error(e.report), identity)
      val sb = schemaAfter(b, "Za").fold(e => sys.error(e.report), identity)
      assert(Schema.text(sa) == Schema.text(sb), "declaration order leaked:\n" +
             Schema.compact(sa) + "\n" + Schema.compact(sb))
      assert(sa.field("$defs").get.objectFieldsOrEmpty == List("Test.Za", "Test.Zb"),
             sa.field("$defs").get.objectFieldsOrEmpty.mkString(","))
      // a record's properties are sorted, whatever order the fields were declared in
      val r1 = schemaAfter(List("field sfZeta : Int", "field sfAlpha : Int").mkString("\n"),
                           "{sfZeta, sfAlpha}").fold(e => sys.error(e.report), identity)
      val r2 = schemaAfter(List("field sfAlpha : Int", "field sfZeta : Int").mkString("\n"),
                           "{sfAlpha, sfZeta}").fold(e => sys.error(e.report), identity)
      assert(Schema.text(r1) == Schema.text(r2), "field order leaked")
      assert(r1.field("properties").get.objectFieldsOrEmpty == List("sfAlpha", "sfZeta"))
    }

  // ---------------------------------------------------------------------
  // (d) every refusal names the constructor, the field index and the reason

  property("(d) a refusal names the constructor, the field index and the reason") =
    sessionProof { implicit s =>
      def refusal(decls: String, ty: String): Schema.Error =
        schemaAfter(decls, ty) match {
          case Left(e)  => e
          case Right(j) => sys.error("exported the unexportable " + ty + ": " + Schema.compact(j))
        }
      val cases = List(
        ("data Fn = Fn Int (Int -> Int)", "Fn", "Fn.Fn[1]", "function"),
        ("data Io = Io (IO Int)", "Io", "Io.Io[0]", "IO"),
        // a CONCRETE Field row: `Field h Int` with `h` free makes the
        // constructor's field a rank-n scheme, and the walker says so first
        ("field sfInt : Int\ndata Fw = Fw (Field (|sfInt|) Int)", "Fw", "Fw.Fw[0]", "Field"),
        ("data Op r = Op {..r}", "Op r", "Op.Op[0]", "open row"),
        ("field sfInt : Int", "{..r}", "$", "open row"),
        ("field sfInt : Int", "a", "$", "polymorphic"))
      val es = cases.map { case (d, t, p, why) => (refusal(d, t), p, why, t) }
      val wrong = es.filterNot { case (e, p, why, _) => e.path == p && e.message.contains(why) }
      assert(wrong.isEmpty, wrong.map { case (e, p, why, t) =>
        t + ": want " + p + " / " + why + ", got " + e.path + " / " + e.message }.mkString("\n"))
      // every message reads as a sentence about a place
      es.map(_._1).foreach { e =>
        assert(e.report.startsWith("cannot export " + e.path + ": "), e.report)
      }
    }

  property("(d2) a foreign type and a PrimT witness are refused, not exported") =
    sessionProof { implicit s =>
      List("data Pw = Pw (Prim Int)", "data Fo = Fo (FFI Int)").zip(List("Pw", "Fo")).foreach {
        case (decls, ty) =>
          schemaAfter(decls, ty) match {
            case Left(e)  => assert(e.path.startsWith(ty + "." + ty), e.toString)
            case Right(j) => sys.error("exported " + ty + ": " + Schema.compact(j))
          }
      }
    }

  // ---------------------------------------------------------------------
  // (e) zod

  property("(e) Zod.render succeeds and names every $defs entry (relations included)") =
    forAllNoShrink(shape(3, rels = true)) { (sh: Shape) =>
      schemaAfter(sh.decls.distinct.mkString("\n"), sh.ty, relImps) match {
        case Left(e) => falsified :| ("export refused " + sh.ty + ": " + e.report)
        case Right(schema) => Zod.render(schema) match {
          case Left(e) => falsified :| ("zod refused " + sh.ty + ": " + e + "\n" + Schema.compact(schema))
          case Right(src) =>
            val names = schema.field("$defs").map(_.objectFieldsOrEmpty).getOrElse(Nil)
            val missing = names.map(Zod.identifier).filterNot(id => src.contains("export const " + id))
            (missing.isEmpty :| ("no const for " + missing.mkString(", ") + "\n" + src)) &&
              (src.contains("export const Schema =") :| "no root const") &&
              (src.contains("import { z } from \"zod\"") :| "no import")
        }
      }
    }

  property("(e2) a recursive type's zod is lazy and annotated") = sessionProof { implicit s =>
    val schema = schemaAfter("data Tr = Trl Int | Trn Tr Tr", "Tr").fold(e => sys.error(e.report), identity)
    val src = Zod.render(schema).fold(e => sys.error(e), identity)
    assert(src.contains("z.lazy(() => Test_Tr)"), src)
    assert(src.contains("export const Test_Tr: z.ZodTypeAny"), src)
    assert(src.contains("z.discriminatedUnion(\"tag\""), src)
  }

  // ---------------------------------------------------------------------
  // (f) $ref: a recursive type exports once and validates at any depth

  property("(f) a recursive type has one $defs entry and validates at depth") =
    forAllNoShrink(recursiveData.flatMap(sh => sh.value.map(v => (sh, v)))) {
      (tv: (Shape, String)) =>
        val (sh, v) = tv
        val decls = sh.decls.mkString("\n")
        schemaAfter(decls, sh.ty) match {
          case Left(e) => falsified :| e.report
          case Right(schema) =>
            val defs = schema.field("$defs").map(_.objectFieldsOrEmpty).getOrElse(Nil)
            val refd = Schema.compact(schema).contains("\"$ref\":\"#/$defs/Test." + sh.ty + "\"")
            (defs == List("Test." + sh.ty)) :| ("$defs = " + defs.mkString(",")) &&
              (refd :| "no self $ref") &&
              (consistent(sh, v) match { case None => proved; case Some(m) => falsified :| m })
        }
    }

  // ---------------------------------------------------------------------
  // J3a: relations -- the delivery union, the wrappers, the generic arm
  //
  // The wire objects (tracker/JSON-STAGE3-PLAN.md, keys from `Wire`) are
  // built HERE, by hand, the way the document writer builds them: columns
  // from the header `PrimT`s through `Wire.columnType`, cells by `Encode` on
  // evaluated Ermine values.  The schema side is `Schema.export` and nothing
  // else, so an agreement is between two independent spellings of the plan.

  def columnsDoc(cols: List[Col]): Json =
    Json.array(cols.map(c => Json.obj(
      Wire.Name     -> Json.jString(c.name),
      Wire.Type     -> Json.jString(Wire.columnType(c.prim)),
      Wire.Nullable -> Json.jBool(c.prim.nullable))): _*)

  def inlineDoc(cols: List[Col], rows: List[Json]): Json =
    Json.obj(Wire.Kind     -> Json.jString(Wire.Inline),
             Wire.Columns  -> columnsDoc(cols),
             Wire.Rows     -> Json.array(rows: _*),
             Wire.RowCount -> Json.jNumber(rows.length))

  def deferredDoc(cols: List[Col], token: String, expires: String): Json =
    Json.obj(Wire.Kind    -> Json.jString(Wire.Deferred),
             Wire.Columns -> columnsDoc(cols),
             Wire.Token   -> Json.jString(token),
             Wire.Expires -> Json.jString(expires))

  /** 128 to 256 random bits, base64url without padding: the plan's token. */
  val tokenGen: Gen[String] =
    Gen.choose(16, 32).flatMap(n => Gen.listOfN(n, Gen.choose(-128, 127))).map { bs =>
      java.util.Base64.getUrlEncoder.withoutPadding.encodeToString(bs.map(_.toByte).toArray)
    }

  /** One relation instance: columns, record literals (none a fifth of the
    * time), a token and an expiry instant. */
  final case class RelCase(cols: List[Col], records: List[String], token: String, expiresMillis: Long)

  val relCase: Gen[RelCase] =
    for {
      cols <- columnsGen
      k    <- Gen.frequency((1, Gen.const(0)), (4, Gen.choose(1, 4)))
      recs <- Gen.listOfN(k, recordGen(cols))
      tok  <- tokenGen
      ms   <- Gen.choose(0L, 4102444800000L)
    } yield RelCase(cols, recs, tok, ms)

  /** The case as module source: its fields, the records as `gv`, the expiry
    * as the Timestamp `gx`. */
  def relDecls(c: RelCase): List[String] =
    fieldDecls(c.cols) ++ List(
      "gv : List " + c.cols.map(_.name).mkString("{", ", ", "}"),
      "gv = " + c.records.mkString("[", ", ", "]"),
      "gx : Timestamp",
      "gx = timestampFromLong " + c.expiresMillis + "L")

  def encodeIn(expr: String)(implicit env: SessionEnv): Json =
    Encode.toArgonaut(Session.eval(expr, relImps)._2).fold(e => sys.error(e.report), identity)

  def exportIn(ty: String)(implicit env: SessionEnv): Json =
    Schema.exportType(NewPipeline.replType("<gate>", ty, relImps), "Test")
      .fold(e => sys.error("export refused " + ty + ": " + e.report), identity)

  /** The rows of a loaded case: each record of `gv` encoded by `Encode`,
    * its values read in column order. */
  def rowsIn(c: RelCase)(implicit env: SessionEnv): List[Json] =
    encodeIn("gv").array.get.map { o =>
      Json.array(c.cols.map(col => o.field(col.name).getOrElse(sys.error("no " + col.name + " in " + o.nospaces))): _*)
    }

  /** The case's inline and deferred documents; `expires` is `Encode`'s
    * spelling of `gx`. */
  def relDocs(c: RelCase)(implicit env: SessionEnv): (Json, Json) =
    (inlineDoc(c.cols, rowsIn(c)), deferredDoc(c.cols, c.token, encodeIn("gx").string.get))

  // -- zod samples for the node runtime check ----------------------------

  /** `ERMINE_ZOD_SAMPLES=<dir>` makes the relation properties write, per
    * sampled case, the zod of the schema and the documents with the verdict
    * the Scala validator gave (`<name>.zod.ts`, `<name>.docs.json`), for a
    * node script to replay against the compiled zod. */
  private val zodSamples: Option[java.io.File] =
    Option(System.getenv("ERMINE_ZOD_SAMPLES")).filter(_.nonEmpty).map(new java.io.File(_))

  private def writeText(f: java.io.File, s: String): Unit = {
    val w = new java.io.PrintWriter(f, "UTF-8")
    try w.write(s) finally w.close()
  }

  def dumpZod(name: String, schema: Json, docs: List[(String, Json, Boolean)]): Unit =
    zodSamples foreach { dir =>
      dir.mkdirs()
      Zod.render(schema) foreach { src => writeText(new java.io.File(dir, name + ".zod.ts"), src) }
      writeText(new java.io.File(dir, name + ".docs.json"),
        Json.array(docs.map { case (why, d, ok) =>
          Json.obj("why" -> Json.jString(why), "accept" -> Json.jBool(ok), "doc" -> d) }: _*).nospacesWithOrder)
    }

  // -- (r-a) the arms ------------------------------------------------------

  property("(r-a) an inline / deferred document validates against [..r] and its own wrapper, not the other (150 cases)") = {
    val cases = samples(relCase, 150, 20260916L)
    val kinds = scala.collection.mutable.Set[String]()
    var rows = 0; var nulls = 0; var empty = 0
    val bad = cases.zipWithIndex.flatMap { case (c, idx) =>
      try session { implicit env =>
        loadStatements(relDecls(c).mkString("\n"), relImps)
        val rt = rowType(c.cols)
        val (both, inl, dfr) = (exportIn(rt), exportIn("Inline " + rowOf(c.cols)), exportIn("Deferred " + rowOf(c.cols)))
        val (i, d) = relDocs(c)
        val rs = i.field(Wire.Rows).get.array.get
        rows += rs.length
        nulls += rs.map(_.array.get.count(_.isNull)).sum
        if (rs.isEmpty) empty += 1
        else c.cols.foreach(col => kinds += Wire.columnType(col.prim) + (if (col.prim.nullable) "?" else ""))
        val verdicts = List(
          ("inline vs " + rt,               i, both, true),
          ("inline vs Inline " + rowOf(c.cols),     i, inl,  true),
          ("inline vs Deferred " + rowOf(c.cols),   i, dfr,  false),
          ("deferred vs " + rt,                     d, both, true),
          ("deferred vs Deferred " + rowOf(c.cols), d, dfr,  true),
          ("deferred vs Inline " + rowOf(c.cols),   d, inl,  false))
        if (idx < 20) {
          dumpZod("ra" + idx + "_rel", both, verdicts.filter(_._3 eq both).map(v => (v._1, v._2, v._4)))
          dumpZod("ra" + idx + "_inline", inl, verdicts.filter(_._3 eq inl).map(v => (v._1, v._2, v._4)))
          dumpZod("ra" + idx + "_deferred", dfr, verdicts.filter(_._3 eq dfr).map(v => (v._1, v._2, v._4)))
        }
        verdicts.flatMap { case (what, doc, schema, want) =>
          val errs = Validate.check(schema, doc)
          if (errs.isEmpty == want) Nil
          else List(what + (if (want) " rejected: " + errs.mkString("; ") else " accepted") +
                    "\n  doc " + doc.nospacesWithOrder + "\n  schema " + Schema.compact(schema))
        }
      } catch { case e: Throwable => List("threw " + e + "\n" + relDecls(c).mkString("\n")) }
    }
    println("  (r-a) " + cases.length + " cases, " + rows + " rows, " + nulls + " null cells, " +
            empty + " empty relations, column kinds with rows: " + kinds.size + "/20")
    (bad.isEmpty :| bad.take(3).mkString("\n---\n")) &&
      ((kinds.size == 20) :| ("column kinds never met with a row: " +
        columnPool.map(c => Wire.columnType(c.prim) + (if (c.prim.nullable) "?" else "")).filterNot(kinds).mkString(", "))) &&
      ((nulls > 0 && empty > 0 && rows > cases.length) :| "the sample has no nulls, no empty relation or few rows")
  }

  // -- (r-b) one mutation is always rejected --------------------------------

  private def setKey(o: Json, k: String, v: Json): Json = {
    val fs = o.obj.get.toList
    if (fs.exists(_._1 == k)) Json.obj(fs.map(kv => if (kv._1 == k) (k, v) else kv): _*)
    else Json.obj((fs :+ ((k, v))): _*)
  }
  private def dropKey(o: Json, k: String): Json = Json.obj(o.obj.get.toList.filterNot(_._1 == k): _*)
  private def mapAt(a: Json, i: Int)(f: Json => Json): Json =
    Json.array(a.array.get.zipWithIndex.map { case (x, j) => if (j == i) f(x) else x }: _*)

  /** A cell no column of `c`'s type admits. */
  private def wrongCell(c: Col, rnd: scala.util.Random): Json = rnd.nextInt(3) match {
    case 0 => Json.jEmptyObject
    case 1 => Json.array(Json.jNumber(1))
    case _ => Wire.columnType(c.prim) match {
      case "Int" | "Short" | "Byte" | "Double" => Json.jString("1")
      case "Bool"                              => Json.jString("true")
      case _                                   => Json.jNumber(1) // Long, String, dates, GUID: string cells
    }
  }

  /** One random mutation of a valid relation document over the PINNED arm:
    * its name and the mutated document.  Every one of them breaks the
    * contract; which are available depends on the arm and on whether there
    * are rows to break. */
  def mutatePinned(doc: Json, cols: List[Col], rnd: scala.util.Random): (String, Json) = {
    val inline = doc.field(Wire.Kind).flatMap(_.string).contains(Wire.Inline)
    val rows = doc.field(Wire.Rows).flatMap(_.array).getOrElse(Nil)
    val n = cols.length
    val colsJ = doc.field(Wire.Columns).get
    val options =
      List("wrong kind", "dropped key", "extra key", "wrong nullable", "wrong column type") ++
      (if (!inline) List("empty token", "bad expires")
       else List("row length", "bad rowCount") ++ (if (rows.nonEmpty) List("cell type") else Nil))
    val m = options(rnd.nextInt(options.length))
    val i = rnd.nextInt(n)
    val out = m match {
      case "wrong kind" =>
        setKey(doc, Wire.Kind, Json.jString(List(if (inline) Wire.Deferred else Wire.Inline, "streamed", "Inline")(rnd.nextInt(3))))
      case "dropped key" =>
        val ks = doc.objectFieldsOrEmpty
        dropKey(doc, ks(rnd.nextInt(ks.length)))
      case "extra key" =>
        if (rnd.nextBoolean) setKey(doc, "extra", Json.jBool(true))
        else setKey(doc, Wire.Columns, mapAt(colsJ, i)(c => setKey(c, "extra", Json.jNumber(1))))
      case "wrong nullable" =>
        setKey(doc, Wire.Columns, mapAt(colsJ, i)(c => setKey(c, Wire.Nullable, Json.jBool(!cols(i).prim.nullable))))
      case "wrong column type" =>
        val others = Wire.columnTypes.filterNot(_ == Wire.columnType(cols(i).prim))
        setKey(doc, Wire.Columns, mapAt(colsJ, i)(c => setKey(c, Wire.Type, Json.jString(others(rnd.nextInt(others.length))))))
      case "empty token" => setKey(doc, Wire.Token, Json.jString(""))
      case "bad expires" =>
        setKey(doc, Wire.Expires, Json.jString(List("2026-09-16", "tomorrow", "2026-09-16T12:00:00", "2026-09-16 12:00:00.000Z")(rnd.nextInt(4))))
      case "row length" =>
        if (rows.isEmpty) setKey(doc, Wire.Rows, Json.array(Json.array(List.fill(n + 1)(Json.jNull): _*)))
        else setKey(doc, Wire.Rows, mapAt(doc.field(Wire.Rows).get, rnd.nextInt(rows.length)) { r =>
          val cells = r.array.get
          Json.array((if (rnd.nextBoolean) cells :+ Json.jNull else cells.init): _*)
        })
      case "bad rowCount" =>
        setKey(doc, Wire.RowCount, if (rnd.nextBoolean) Json.jNumber(-1) else Json.jString(rows.length.toString))
      case "cell type" =>
        setKey(doc, Wire.Rows, mapAt(doc.field(Wire.Rows).get, rnd.nextInt(rows.length))(r => mapAt(r, i)(_ => wrongCell(cols(i), rnd))))
    }
    (m, out)
  }

  property("(r-b) a single random mutation of a valid relation document is rejected (150 cases, 300 mutants)") = {
    val cases = samples(relCase, 150, 20260917L)
    val mix = scala.collection.mutable.Map[String, Int]().withDefaultValue(0)
    val bad = cases.zipWithIndex.flatMap { case (c, idx) =>
      val rnd = new scala.util.Random(7919L * idx)
      try session { implicit env =>
        loadStatements(relDecls(c).mkString("\n"), relImps)
        val rt = rowType(c.cols)
        val (both, inl, dfr) = (exportIn(rt), exportIn("Inline " + rowOf(c.cols)), exportIn("Deferred " + rowOf(c.cols)))
        val (i, d) = relDocs(c)
        val (mi, iMut) = mutatePinned(i, c.cols, rnd)
        val (md, dMut) = mutatePinned(d, c.cols, rnd)
        mix(mi) += 1; mix(md) += 1
        if (idx < 20) {
          dumpZod("rb" + idx + "_rel", both, List(("valid inline", i, true), ("valid deferred", d, true),
                                                   ("inline: " + mi, iMut, false), ("deferred: " + md, dMut, false)))
          dumpZod("rb" + idx + "_inline", inl, List(("valid inline", i, true), ("inline: " + mi, iMut, false)))
          dumpZod("rb" + idx + "_deferred", dfr, List(("valid deferred", d, true), ("deferred: " + md, dMut, false)))
        }
        List((i, iMut, mi, inl), (d, dMut, md, dfr)).flatMap { case (orig, mut, m, arm) =>
          val sane = Validate.check(arm, orig).isEmpty && Validate.check(both, orig).isEmpty
          val armErrs = Validate.check(arm, mut)
          val bothErrs = Validate.check(both, mut)
          if (!sane) List("the unmutated document is rejected: " + orig.nospacesWithOrder)
          else if (armErrs.isEmpty || bothErrs.isEmpty)
            List("mutation '" + m + "' accepted by " + (if (armErrs.isEmpty) "the arm" else "the union") +
                 "\n  " + mut.nospacesWithOrder + "\n  from " + orig.nospacesWithOrder)
          else Nil
        }
      } catch { case e: Throwable => List("threw " + e + "\n" + relDecls(c).mkString("\n")) }
    }
    val mixText = mix.toList.sortBy(_._1).map { case (k, v) => k + " " + v }.mkString(", ")
    println("  (r-b) mutation mix over " + mix.values.sum + " mutants: " + mixText)
    (bad.isEmpty :| bad.take(3).mkString("\n---\n")) &&
      ((mix.size == 10) :| ("some mutation never drawn: " + mixText))
  }

  // -- the document writer, played by the test --------------------------------

  /** `ArgonautJson` everywhere but a relation, where it plays the document
    * writer over a LITERAL relation: the object for the delivery the walker
    * passed (`ByRequest` alternates inline and deferred), column descriptors
    * from the column pool by name (from `emptyCols` when there are no rows)
    * and each cell the `Encode`d `PrimExpr` of the relation's record.  So a
    * document it writes agrees with a schema only if the walker's delivery
    * (Json.Inline / Json.Deferred recognition) agrees with the exporter's. */
  final class DocBuilder(emptyCols: List[Col], token: String, expires: String) extends JsonBuilder[Json] {
    val seen = new scala.collection.mutable.ListBuffer[(String, Delivery, Int)]
    private var inlineNext = true
    def nul                = ArgonautJson.nul
    def bool(b: Boolean)   = ArgonautJson.bool(b)
    def int(i: Int)        = ArgonautJson.int(i)
    def long(l: Long)      = ArgonautJson.long(l)
    def num(d: Double)     = ArgonautJson.num(d)
    def str(s: String)     = ArgonautJson.str(s)
    def arr(xs: List[Json]) = ArgonautJson.arr(xs)
    def obj(fields: List[(String, Json)]) = ArgonautJson.obj(fields)
    def rel(path: String, r: Runtime, delivery: Delivery): Either[Encode.Error, Json] = {
      val records: List[Record] = Runtime.swhnf(r) match {
        case EmptyRel => Nil
        case rl: Rel => rl.extract[relational.Ext[Nothing, Nothing]] match {
          case ExtRel(SmallLit(tups), _) => tups.head :: tups.tail.toList
          case other => return Left(Encode.Error(path, "not a literal relation: " + other))
        }
        case other => return Left(Encode.Error(path, "not a relation: " + other))
      }
      val cols =
        if (records.isEmpty) emptyCols
        else records.head.keys.toList.sorted.map(n => columnPool.find(_.name == n).getOrElse(sys.error("no pool column " + n)))
      val rows = records.map(rec => Json.array(cols.map(c =>
        Encode.toArgonaut(Prim(rec(c.name))).fold(e => sys.error(e.report), identity)): _*))
      val asInline = delivery match {
        case Delivery.Inline    => true
        case Delivery.Deferred  => false
        case Delivery.ByRequest => inlineNext = !inlineNext; !inlineNext
      }
      seen += ((path, delivery, rows.length))
      Right(if (asInline) inlineDoc(cols, rows) else deferredDoc(cols, token, expires))
    }
  }

  def encodeWith(expr: String, b: DocBuilder)(implicit env: SessionEnv): Json =
    Encode.encode(Session.eval(expr, relImps)._2, b).fold(e => sys.error(e.report), identity)

  // -- (r-c) one schema for every row ----------------------------------------

  /** A random props type with ONE row parameter: 1-3 relation fields over
    * `r` (bare, Inline, Deferred), 0-2 other fields, in random order, and
    * three random instantiations of `r`. */
  final case class PropsCase(d: String, fields: List[(String, Either[(Shape, String), String])],
                             insts: List[RelCase])

  val propsCase: Gen[PropsCase] =
    for {
      d      <- fresh("W")
      k      <- Gen.choose(0, 2)
      plain  <- Gen.listOfN(k, shape(1))
      nrel   <- Gen.choose(1, 3)
      wraps  <- Gen.listOfN(nrel, Gen.oneOf("Inline", "Deferred", ""))
      keys   <- Gen.listOfN(k + nrel, Gen.choose(0, 1000000))
      pvs    <- Gen.sequence[List[String], String](plain.map(_.value))
      insts  <- Gen.listOfN(3, relCase)
    } yield {
      val tagged: List[Either[(Shape, String), String]] = plain.zip(pvs).map(Left(_)) ++ wraps.map(Right(_))
      val ordered = tagged.zip(keys).sortBy(_._2).map(_._1)
      PropsCase(d, ordered.zipWithIndex.map { case (f, i) => (d.toLowerCase + "f" + i, f) }, insts)
    }

  def propsDecls(p: PropsCase): List[String] = {
    val decl = "data " + p.d + " r = " + p.d + " { " + p.fields.map {
      case (n, Left((sh, _))) => n + " : " + sh.ty
      case (n, Right(w))      => n + " : " + (if (w.isEmpty) "[..r]" else w + " r")
    }.mkString(", ") + " }"
    decl :: p.fields.flatMap(_._2.left.toOption.toList.flatMap(_._1.decls))
  }

  def propsValue(p: PropsCase): String =
    (p.d :: p.fields.map {
      case (_, Left((_, v))) => v
      case (_, Right(w))     => if (w.isEmpty) "(mkRelation# (toList# gv))" else "(" + w + " (mkRelation# (toList# gv)))"
    }).mkString("(", " ", ")")

  /** A generic-arm mutation: the ones the generic arm can see (it pins no
    * column, so a wrong `nullable` or row length is not one). */
  def mutateGeneric(doc: Json, rnd: scala.util.Random): (String, Json) = {
    val inline = doc.field(Wire.Kind).flatMap(_.string).contains(Wire.Inline)
    val colsJ = doc.field(Wire.Columns).get
    val n = colsJ.array.get.length
    val rows = doc.field(Wire.Rows).flatMap(_.array).getOrElse(Nil)
    val options = List("wrong kind", "dropped key", "extra key", "type outside the vocabulary", "nullable not a boolean") ++
      (if (inline) List("bad rowCount") ++ (if (rows.nonEmpty) List("cell not a scalar") else Nil) else List("empty token"))
    val m = options(rnd.nextInt(options.length))
    val i = rnd.nextInt(n)
    val out = m match {
      case "wrong kind"  => setKey(doc, Wire.Kind, Json.jString(if (inline) Wire.Deferred else Wire.Inline))
      case "dropped key" => val ks = doc.objectFieldsOrEmpty; dropKey(doc, ks(rnd.nextInt(ks.length)))
      case "extra key"   =>
        if (rnd.nextBoolean) setKey(doc, "extra", Json.jBool(true))
        else setKey(doc, Wire.Columns, mapAt(colsJ, i)(c => setKey(c, "extra", Json.jNumber(1))))
      case "type outside the vocabulary" =>
        setKey(doc, Wire.Columns, mapAt(colsJ, i)(c => setKey(c, Wire.Type, Json.jString(List("Char", "UUID", "int")(rnd.nextInt(3))))))
      case "nullable not a boolean" =>
        setKey(doc, Wire.Columns, mapAt(colsJ, i)(c => setKey(c, Wire.Nullable, Json.jString("true"))))
      case "bad rowCount" => setKey(doc, Wire.RowCount, Json.jNumber(-1))
      case "empty token"  => setKey(doc, Wire.Token, Json.jString(""))
      case "cell not a scalar" =>
        setKey(doc, Wire.Rows, mapAt(doc.field(Wire.Rows).get, rnd.nextInt(rows.length))(r =>
          mapAt(r, rnd.nextInt(n))(_ => if (rnd.nextBoolean) Json.jEmptyObject else Json.array())))
    }
    (m, out)
  }

  property("(r-c) a props type with a row parameter: one schema, valid for every instantiation (40 types x 3 rows)") = {
    val cases = samples(propsCase, 40, 20260918L)
    val mix = scala.collection.mutable.Map[String, Int]().withDefaultValue(0)
    var docs = 0; var rels = 0; var withRows = 0
    val bad = cases.zipWithIndex.flatMap { case (p, idx) =>
      val rnd = new scala.util.Random(104729L * idx)
      try {
        val perInst = p.insts.zipWithIndex.map { case (inst, j) =>
          session { implicit env =>
            val decls = (propsDecls(p) ++ relDecls(inst) ++ List("gp = " + propsValue(p))).distinct.mkString("\n")
            loadStatements(decls, relImps)
            val schema = Schema.exportNamed("Test", p.d).fold(e => sys.error("exportNamed refused " + p.d + ": " + e.report), identity)
            val b = new DocBuilder(inst.cols, inst.token, encodeIn("gx").string.get)
            val doc = encodeWith("gp", b)
            docs += 1; rels += b.seen.length; withRows += b.seen.count(_._3 > 0)
            // the literal relation's PrimExpr cells are the Ermine values' cells
            val direct = rowsIn(inst)
            val viaRel = doc.field(p.fields.find(_._2.isRight).get._1).get
            val relRows = viaRel.field(Wire.Rows).flatMap(_.array)
            val errs = Validate.check(schema, doc)
            // a generic mutation of one relation field
            val (rf, _) = p.fields.filter(_._2.isRight)(rnd.nextInt(p.fields.count(_._2.isRight)))
            val (m, mutRel) = mutateGeneric(doc.field(rf).get, rnd)
            mix(m) += 1
            val mutDoc = setKey(doc, rf, mutRel)
            val mutErrs = Validate.check(schema, mutDoc)
            if (idx < 10) dumpZod("rc" + idx + "_" + j, schema, List(("valid", doc, true), (rf + ": " + m, mutDoc, false)))
            val problems =
              (if (errs.nonEmpty) List("rejected: " + errs.mkString("; ") + "\n  doc " + doc.nospacesWithOrder) else Nil) ++
              (if (mutErrs.isEmpty) List("mutation '" + m + "' of " + rf + " accepted: " + mutDoc.nospacesWithOrder) else Nil) ++
              (if (b.seen.length != p.fields.count(_._2.isRight)) List("the writer met " + b.seen.length + " relations") else Nil) ++
              (if (relRows.exists(_ != direct)) List("PrimExpr cells differ from the Ermine values' cells:\n  " +
                                                     relRows.get.map(_.nospaces) + "\n  " + direct.map(_.nospaces)) else Nil)
            (Schema.text(schema), problems.map(_ + "\n" + decls))
          }
        }
        val texts = perInst.map(_._1).distinct
        (if (texts.length == 1) Nil else List("the schema of " + p.d + " depends on the row:\n" + texts.mkString("\n---\n"))) ++
          perInst.flatMap(_._2)
      } catch { case e: Throwable => List("threw " + e + "\n" + propsDecls(p).mkString("\n")) }
    }
    println("  (r-c) " + cases.length + " props types, " + docs + " documents, " + rels + " relations (" +
            withRows + " with rows); generic mutation mix: " +
            mix.toList.sortBy(_._1).map { case (k, v) => k + " " + v }.mkString(", "))
    (bad.isEmpty :| bad.take(3).mkString("\n---\n")) && ((withRows > 0) :| "no relation with rows")
  }

  // -- (r-d) relations at concrete rows inside random data -------------------

  /** A random `data` (record-style or positional, one or two constructors)
    * whose first constructor has a relation field -- bare or wrapped, at a
    * concrete row -- among fields that may hold more relations anywhere in
    * their own trees. */
  val relData: Gen[Shape] =
    for {
      d     <- fresh("Q")
      named <- Gen.oneOf(true, false)
      k     <- Gen.choose(0, 2)
      first <- Gen.listOfN(k, shape(2, rels = true))
      rel   <- relationShape
      pos   <- Gen.choose(0, k)
      more  <- Gen.choose(0, 1)
      rest  <- Gen.listOfN(more, Gen.choose(1, 2).flatMap(j => Gen.listOfN(j, shape(2, rels = true))))
    } yield {
      val ctors = (first.take(pos) ++ (rel :: first.drop(pos))) :: rest
      if (named) recordStyleDecl(d, ctors) else positionalDecl(d, ctors)
    }

  property("(r-d) data with relations inside: exports, its zod renders, the written document validates (100 cases)") = {
    val cases = samples(relData.flatMap(sh => sh.value.map(v => (sh, v))), 100, 20260919L)
    val met = scala.collection.mutable.Map[String, Int]().withDefaultValue(0)
    val bad = cases.zipWithIndex.flatMap { case ((sh, v), idx) =>
      val decls = (sh.decls.distinct ++ List("gv : " + sh.ty, "gv = " + v, "gx : Timestamp",
                                             "gx = timestampFromLong " + (1700000000000L + idx) + "L")).mkString("\n")
      try session { implicit env =>
        loadStatements(decls, relImps)
        val schema = exportIn(sh.ty)
        val b = new DocBuilder(Nil, "tok" + idx + "AAAAAAAAAAAAAAAAAA", encodeIn("gx").string.get)
        val doc = encodeWith("gv", b)
        b.seen.foreach(s => met(s._2.name) += 1)
        val errs = Validate.check(schema, doc)
        val zod = Zod.render(schema)
        if (idx < 30) dumpZod("rd" + idx, schema, List(("written", doc, true)))
        (if (errs.isEmpty) Nil else List("rejected: " + errs.mkString("; ") + "\n  doc " + doc.nospacesWithOrder +
                                         "\n  schema " + Schema.compact(schema) + "\n" + decls)) ++
          zod.left.toOption.toList.map(e => "zod refused: " + e + "\n" + decls)
      } catch { case e: Throwable => List("threw " + e + "\n" + decls) }
    }
    println("  (r-d) " + cases.length + " data types; relations written by delivery: " +
            met.toList.sortBy(_._1).map { case (k, n) => k + " " + n }.mkString(", "))
    (bad.isEmpty :| bad.take(3).mkString("\n---\n")) &&
      ((List("inline", "deferred", "request").forall(met(_) > 0)) :| ("a delivery was never written: " + met))
  }

  // -- pins beside the properties ---------------------------------------------

  property("(r-pins) the wrapper shapes, the generic key, the refusals") = sessionProof { implicit s =>
    val decls = List(
      "field sfInt : Int", "field sfNote : Nullable String",
      "data TableProps r = TableProps { title : String, rows : Inline r }",
      "data Page r = Page { body : TableProps r, more : Deferred r, plain : [..r] }",
      "data Mixed a r = Mixed a (Inline r)",
      "data OpenRec r = OpenRec {..r}").mkString("\n")
    session { implicit env =>
      loadStatements(decls, relImps)
      def refused(e: Either[Schema.Error, Json]): Schema.Error =
        e.fold(identity, j => sys.error("exported " + Schema.compact(j)))
      // a wrapper is neither a $defs entry nor a {tag,args} object
      val inl = exportIn("Inline (|sfInt, sfNote|)")
      assert(inl.field("$defs").isEmpty, Schema.compact(inl))
      assert(inl.field("properties").get.objectFieldsOrEmpty ==
             List(Wire.Kind, Wire.Columns, Wire.Rows, Wire.RowCount), Schema.compact(inl))
      assert(Schema.compact(inl).contains(
        "{\"type\":\"object\",\"properties\":{\"name\":{\"const\":\"sfNote\"},\"type\":{\"const\":\"String\"}," +
        "\"nullable\":{\"const\":true}},\"required\":[\"name\",\"type\",\"nullable\"],\"additionalProperties\":false}"),
        Schema.compact(inl))
      val dfr = exportIn("Deferred (|sfInt|)")
      assert(dfr.field("properties").get.objectFieldsOrEmpty ==
             List(Wire.Kind, Wire.Columns, Wire.Token, Wire.Expires), Schema.compact(dfr))
      assert(exportIn("[sfInt]").field("oneOf").flatMap(_.array).map(_.length) == Some(2))
      // one generic schema, keyed `_`, whatever the variable is called
      val tp = Schema.exportNamed("Test", "TableProps").fold(e => sys.error(e.report), identity)
      assert(tp.field("$id").flatMap(_.string) == Some("ermine:Test/TableProps r"), Schema.compact(tp))
      assert(tp.field("$defs").get.objectFieldsOrEmpty == List("Test.TableProps__"), Schema.compact(tp))
      val tq = exportIn("TableProps q")
      assert(Schema.text(tq.field("$defs").get) == Schema.text(tp.field("$defs").get))
      val page = Schema.exportNamed("Test", "Page").fold(e => sys.error(e.report), identity)
      assert(page.field("$defs").get.objectFieldsOrEmpty == List("Test.Page__", "Test.TableProps__"), Schema.compact(page))
      assert(Schema.text(page.field("$defs").get.field("Test.TableProps__").get) ==
             Schema.text(tp.field("$defs").get.field("Test.TableProps__").get))
      // the bare relation field is the delivery union, discriminated by `kind`
      assert(Zod.render(page).right.get.contains("z.discriminatedUnion(\"kind\""), Zod.render(page))
      // a *-kinded parameter cannot be left abstract; an open RECORD stays an error
      val mixed = refused(Schema.exportNamed("Test", "Mixed"))
      assert(mixed.path == "$" && mixed.message.contains("type arguments") &&
             mixed.message.contains("the parameter a has kind *"), mixed)
      val open = refused(Schema.exportNamed("Test", "OpenRec"))
      assert(open.path == "OpenRec.OpenRec[0]" && open.message.contains("open row"), open)
      // no column type outside the vocabulary can reach the exporter: `field`
      // itself accepts only Type.primTypes (and Nullable of one)
      assert(scala.util.Try(session { implicit e2 => loadStatements("field sfChar : Char", relImps) }).isFailure)
      // a partially applied builtin is still not a value type
      val mb = refused(Schema.exportType(NewPipeline.replType("<gate>", "Maybe", relImps), "Test"))
      assert(mb.message.contains("partially applied"), mb)
    }
  }

  property("(r-pins) the validator's minLength") = sessionProof { implicit s =>
    val tok = Json.obj("type" -> Json.jString("string"), "minLength" -> Json.jNumber(1))
    assert(Validate.check(tok, Json.jString("a")).isEmpty)
    assert(Validate.check(tok, Json.jString("")).nonEmpty)
  }

  // ---------------------------------------------------------------------
  // the gate fixtures (§5 Stage 1) and the CI equality check

  private val fixtureDir = new java.io.File("core/src/test/resources/schema")
  /** `ERMINE_SCHEMA_FIXTURES=write sbt 'core/testOnly ...TestSchema'`
    * regenerates the committed fixtures; any other run compares against them
    * byte for byte, so a change to the mapping shows up as a failing test
    * AND a reviewable diff. */
  private val writing = Option(System.getenv("ERMINE_SCHEMA_FIXTURES")).contains("write")

  private def fixture(name: String, ext: String, actual: String): Option[String] = {
    val f = new java.io.File(fixtureDir, name + ext)
    if (writing) {
      fixtureDir.mkdirs()
      val w = new java.io.PrintWriter(f, "UTF-8")
      try w.write(actual) finally w.close()
      None
    } else if (!f.exists) Some(f.getPath + " is missing; regenerate with ERMINE_SCHEMA_FIXTURES=write")
    else {
      val want = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
      if (want == actual) None
      else Some(f.getPath + " differs from the exporter's output (first difference at character " +
                want.zip(actual).indexWhere(p => p._1 != p._2) + "); regenerate with " +
                "ERMINE_SCHEMA_FIXTURES=write and review the diff")
    }
  }

  /** The Stage 1 gate list: the schemas and zod of these types are committed
    * under core/src/test/resources/schema/ and regenerated here. */
  private def gates: List[(String, Either[Schema.Error, Json])] = {
    val userDecls = List("field sfInt : Int", "field sfString : String", "field sfBool : Bool",
                         "field sfDate : Date", "field sfNote : Nullable String",
                         "data Tree = Leaf Int | Node Tree Tree",
                         // J3a: a widget props type, one schema for every row
                         "data TableProps r = TableProps { title : String, rows : Inline r, detail : [..r] }"
                        ).mkString("\n")
    List(
      ("Ordering",       schemaOf(List("Ord"), "Ord", "Ordering")),
      ("Either",         schemaOf(List("Either"), "Either", "Either String Int")),
      ("SortOrder",      schemaOf(List("Relation.Sort"), "Relation.Sort", "SortOrder")),
      ("Direction",      schemaOf(List("Layout.Report.Direction"), "Layout.Report.Direction", "Direction")),
      ("BorderOptions",  schemaOf(List("Layout.BorderOptions"), "Layout.BorderOptions", "BorderOptions Int")),
      ("UserRecord",     schemaAfter(userDecls, "{sfInt, sfString, sfBool, sfDate}")),
      ("UserRelation",   schemaAfter(userDecls, "[sfInt, sfString, sfDate]")),
      ("UserInline",     schemaAfter(userDecls, "Inline (|sfDate, sfInt, sfNote|)")),
      ("UserDeferred",   schemaAfter(userDecls, "Deferred (|sfDate, sfInt, sfNote|)")),
      ("UserTableProps", session { implicit env =>
                           loadStatements(userDecls, imps)
                           Schema.exportNamed("Test", "TableProps") }),
      ("UserTree",       schemaAfter(userDecls, "Tree")))
  }

  property("(gate) the committed schema and zod fixtures are what the exporter produces") =
    sessionProof { implicit s =>
      val problems = gates.flatMap { case (name, res) =>
        res match {
          case Left(e) => List(name + ": " + e.report)
          case Right(schema) =>
            val sj = fixture(name, ".schema.json", Schema.text(schema) + "\n")
            val sz = Zod.render(schema) match {
              case Left(e)    => Some(name + ": zod refused: " + e)
              case Right(src) => fixture(name, ".zod.ts", src)
            }
            sj.toList ++ sz.toList
        }
      }
      assert(problems.isEmpty, problems.mkString("\n"))
      println("  schema gate: " + gates.length + " fixtures " + (if (writing) "written" else "match"))
    }

  // ---------------------------------------------------------------------
  // the LSP request answers in the server's own Json

  property("(lsp) the ermine/schema answer converts into the server's Json") =
    sessionProof { implicit s =>
      import com.clarifi.reporting.ermine.json.LspSchema
      val schema = schemaOf(List("Ord"), "Ord", "Ordering").fold(e => sys.error(e.report), identity)
      val lsp = LspSchema.toLsp(schema)
      val text = com.clarifi.reporting.ermine.lsp.Json.print(lsp)
      assert(text.contains("\"$id\":\"ermine:Ord/Ordering\""), text)
      assert(text.contains("\"LT\""), text)
      // the round trip through the server's parser is the shape the client sees
      com.clarifi.reporting.ermine.lsp.Json.parse(text) match {
        case Right(back) => assert(com.clarifi.reporting.ermine.lsp.Json.print(back) == text, text)
        case Left(e)     => sys.error("the server cannot parse its own answer: " + e)
      }
      val bad = LspSchema.toLsp(argonaut.Json.jNumber(1))
      assert(com.clarifi.reporting.ermine.lsp.Json.print(bad) == "1")
    }

  // ---------------------------------------------------------------------
  // the mapping, case by case: one assertion per row of the §3.1 table

  property("(map) the primitive rows of the §3.1 table") = sessionProof { implicit s =>
    def sch(ty: String): String =
      Schema.compact(schemaAfter("field sfInt : Int", ty).fold(e => sys.error(e.report), identity))
        .replace("{\"$schema\":\"" + Schema.dialect + "\",\"$id\":\"ermine:Test/" + ty + "\",", "{")
    assert(sch("Int")       == "{\"type\":\"integer\"}", sch("Int"))
    assert(sch("Short")     == "{\"type\":\"integer\",\"minimum\":-32768,\"maximum\":32767}", sch("Short"))
    assert(sch("Byte")      == "{\"type\":\"integer\",\"minimum\":-128,\"maximum\":127}", sch("Byte"))
    assert(sch("Long")      == "{\"type\":\"string\",\"pattern\":\"^-?[0-9]+$\"}", sch("Long"))
    assert(sch("Double")    == "{\"type\":\"number\"}", sch("Double"))
    assert(sch("Bool")      == "{\"type\":\"boolean\"}", sch("Bool"))
    assert(sch("String")    == "{\"type\":\"string\"}", sch("String"))
    assert(sch("Char")      == "{\"type\":\"string\",\"maxLength\":1}", sch("Char"))
    assert(sch("Date")      == "{\"type\":\"string\",\"format\":\"date\"}", sch("Date"))
    assert(sch("Timestamp") == "{\"type\":\"string\",\"format\":\"date-time\"}", sch("Timestamp"))
    assert(sch("GUID")      == "{\"type\":\"string\",\"format\":\"uuid\"}", sch("GUID"))
    assert(sch("()")        == "{\"type\":\"array\",\"maxItems\":0}", sch("()"))
  }

  property("(map) Maybe, List, tuples and the stdlib Json type") = sessionProof { implicit s =>
    def sch(ty: String, decls: String = "field sfInt : Int"): String =
      Schema.compact(schemaAfter(decls, ty).fold(e => sys.error(e.report), identity))
    assert(sch("(Maybe Int)").contains("\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"null\"}]"), sch("(Maybe Int)"))
    assert(sch("(Nullable Int)").contains("\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"null\"}]"))
    assert(sch("(List Int)").contains("\"type\":\"array\",\"items\":{\"type\":\"integer\"}"))
    assert(sch("(Int, String)").contains("\"prefixItems\":[{\"type\":\"integer\"},{\"type\":\"string\"}],\"minItems\":2,\"maxItems\":2"))
    // the escape hatch: Ermine owns no contract for a Json value
    assert(sch("Json").endsWith("\"$id\":\"ermine:Test/Json\"}"), sch("Json"))
  }

  property("(map) a single-constructor data type is not a oneOf") = sessionProof { implicit s =>
    val one = Schema.compact(schemaAfter("data One = One Int Bool", "One").fold(e => sys.error(e.report), identity))
    assert(!one.contains("oneOf"), one)
    assert(one.contains("\"const\":\"One\""), one)
    val two = Schema.compact(schemaAfter("data Two = Two Int | Tre Bool", "Two").fold(e => sys.error(e.report), identity))
    assert(two.contains("\"oneOf\":["), two)
  }

  property("(map) an operator constructor has no stable tag") = sessionProof { implicit s =>
    schemaAfter("data Ops = (:+:) Int Int", "Ops") match {
      case Left(e)  => assert(e.message.contains("operator"), e.toString)
      case Right(j) => sys.error("exported an operator constructor: " + Schema.compact(j))
    }
  }

  property("(map) a type alias is expanded before anything else") = sessionProof { implicit s =>
    val direct = schemaAfter("field sfInt : Int", "(List Int)").fold(e => sys.error(e.report), identity)
    val alias  = schemaAfter("type Ints = List Int", "Ints").fold(e => sys.error(e.report), identity)
    assert(Schema.compact(direct).replace("ermine:Test/List Int", "X") ==
           Schema.compact(alias).replace("ermine:Test/Ints", "X"),
           Schema.compact(direct) + " vs " + Schema.compact(alias))
  }
}
