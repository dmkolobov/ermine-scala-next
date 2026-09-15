package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.json.{ Encode, Schema, Validate, Zod }
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
  def schemaAfter(decls: String, tyExpr: String): Either[Schema.Error, Json] =
    session { implicit env =>
      loadStatements(decls, imps)
      Schema.exportType(NewPipeline.replType("<gate>", tyExpr, imps), "Test")
    }

  // ---------------------------------------------------------------------
  // the generator: random Ermine types with random values of them

  /** One generated type: its source, the declarations it needs (deduplicated
    * before they are emitted) and a generator of value source. */
  final case class Shape(ty: String, decls: List[String], value: Gen[String])

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

  private def listOfGen(g: Gen[String]): Gen[String] =
    Gen.choose(0, 3).flatMap(n => Gen.listOfN(n, g)).map(_.mkString("[", ", ", "]"))

  /** `depth` bounds nesting; `underMaybe` keeps `Maybe (Maybe a)` out, which
    * the mapping rejects on purpose (both layers encode to `null`). */
  def shape(depth: Int, underMaybe: Boolean = false): Gen[Shape] = {
    val leaves: List[Gen[Shape]] =
      Gen.oneOf(prims) :: Gen.const(Shape("()", Nil, Gen.const("()"))) :: enumData :: Nil
    if (depth <= 0) Gen.oneOf(leaves).flatMap(identity)
    else {
      val composites: List[Gen[Shape]] =
        listShape(depth) :: tupleShape(depth) :: recordShape ::
        positionalData(depth) :: parameterisedData(depth) :: recursiveData ::
        (if (underMaybe) Nil else List(maybeShape(depth)))
      Gen.oneOf(leaves ++ composites).flatMap(identity)
    }
  }

  private def maybeShape(depth: Int): Gen[Shape] =
    shape(depth - 1, underMaybe = true).map { a =>
      Shape("(Maybe " + a.ty + ")", a.decls,
            Gen.frequency((1, Gen.const("Nothing")), (3, a.value.map(v => "(Just " + v + ")"))))
    }

  private def listShape(depth: Int): Gen[Shape] =
    shape(depth - 1).map(a => Shape("(List " + a.ty + ")", a.decls, listOfGen(a.value)))

  private def tupleShape(depth: Int): Gen[Shape] =
    Gen.choose(2, 3).flatMap(n => Gen.listOfN(n, shape(depth - 1))).map { as =>
      Shape(as.map(_.ty).mkString("(", ", ", ")"), as.flatMap(_.decls),
            Gen.sequence[List[String], String](as.map(_.value)).map(_.mkString("(", ", ", ")")))
    }

  private def recordShape: Gen[Shape] =
    Gen.choose(1, fieldPool.length).flatMap(n => Gen.pick(n, fieldPool)).map { chosen =>
      val fs = chosen.toList.sortBy(_._1)
      Shape(fs.map(_._1).mkString("{", ", ", "}"),
            fs.map { case (n, t) => "field " + n + " : " + t },
            Gen.sequence[List[String], String](fs.map(f => primFor(f._2).value))
              .map(vs => fs.map(_._1).zip(vs).map(kv => kv._1 + " = " + kv._2).mkString("{ ", ", ", " }")))
    }

  private def enumData: Gen[Shape] =
    for {
      d  <- fresh("E")
      n  <- Gen.choose(1, 4)
    } yield {
      val cons = (1 to n).toList.map(i => d + "c" + i)
      Shape(d, List("data " + d + " = " + cons.mkString(" | ")), Gen.oneOf(cons))
    }

  private def positionalData(depth: Int): Gen[Shape] =
    for {
      d     <- fresh("D")
      arity <- Gen.choose(1, 3)
      ctors <- Gen.listOfN(arity, Gen.choose(0, 2).flatMap(k => Gen.listOfN(k, shape(depth - 1))))
    } yield {
      val named = ctors.zipWithIndex.map { case (fs, i) => (d + "c" + (i + 1), fs) }
      val decl = "data " + d + " = " +
        named.map { case (c, fs) => (c :: fs.map(_.ty)).mkString(" ") }.mkString(" | ")
      Shape(d, decl :: named.flatMap(_._2.flatMap(_.decls)),
            Gen.oneOf(named).flatMap { case (c, fs) =>
              Gen.sequence[List[String], String](fs.map(_.value))
                .map(vs => (c :: vs).mkString("(", " ", ")")) })
    }

  /** `data Dn a = Dna a | Dnb a a`, exported at an instantiation: the
    * exporter substitutes the argument into the constructor field types, so
    * a type PARAMETER is never the "polymorphic" error. */
  private def parameterisedData(depth: Int): Gen[Shape] =
    for {
      d <- fresh("P")
      a <- shape(depth - 1)
    } yield {
      val decl = "data " + d + " a = " + d + "a a | " + d + "b a a"
      Shape("(" + d + " " + a.ty + ")", decl :: a.decls,
            Gen.oneOf(
              a.value.map(v => "(" + d + "a " + v + ")"),
              Gen.zip(a.value, a.value).map(p => "(" + d + "b " + p._1 + " " + p._2 + ")")).flatMap(identity))
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

  property("(c) exporting twice is byte-identical") = forAllNoShrink(shape(3)) { (sh: Shape) =>
    val decls = sh.decls.distinct.mkString("\n")
    val a = schemaAfter(decls, sh.ty)
    val b = schemaAfter(decls, sh.ty)
    (a, b) match {
      case (Right(x), Right(y)) =>
        (Schema.text(x) == Schema.text(y)) :| ("not identical for " + sh.ty)
      case (Left(x), Left(y)) => (x == y) :| "errors differ"
      case _                  => falsified :| ("one export refused for " + sh.ty)
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

  property("(e) Zod.render succeeds and names every $defs entry") =
    forAllNoShrink(shape(3)) { (sh: Shape) =>
      schemaAfter(sh.decls.distinct.mkString("\n"), sh.ty) match {
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
                         "field sfDate : Date", "data Tree = Leaf Int | Node Tree Tree").mkString("\n")
    List(
      ("Ordering",       schemaOf(List("Ord"), "Ord", "Ordering")),
      ("Either",         schemaOf(List("Either"), "Either", "Either String Int")),
      ("SortOrder",      schemaOf(List("Relation.Sort"), "Relation.Sort", "SortOrder")),
      ("Direction",      schemaOf(List("Layout.Report.Direction"), "Layout.Report.Direction", "Direction")),
      ("BorderOptions",  schemaOf(List("Layout.BorderOptions"), "Layout.BorderOptions", "BorderOptions Int")),
      ("UserRecord",     schemaAfter(userDecls, "{sfInt, sfString, sfBool, sfDate}")),
      ("UserRelation",   schemaAfter(userDecls, "[sfInt, sfString, sfDate]")),
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
