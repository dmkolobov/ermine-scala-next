package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.json.{ Encode, ArgonautJson, ErmineJson }
import com.clarifi.reporting.ermine.session.SessionEnv

import org.scalacheck._
import Prop.{ Result => _, _ }

/** The JSON encoder (core/json/Encode.scala, tracker/JSON-API-DESIGN.md
  * Stage 0): the value mapping, the stdlib `Json` module, the FFI
  * primitives, stack safety on large lists, and the standard-library sweep.
  *
  * Every property round-trips Ermine source through the pipeline and reads
  * the rendered text back, so a change to the wire mapping shows up here as
  * a changed string.
  */
object TestJson extends Properties("Ermine JSON") {
  private lazy val ermineFixture = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import ermineFixture._

  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Json" -> all, "List" -> all,
        "Maybe" -> all, "Nullable" -> all, "Function" -> all, "Int" -> all, "Num" -> all, "Error" -> all)

  /** `render (toJson <e>)` with the statements loaded first. */
  def json(stmts: String, e: String): String =
    defAndEval(stmts, "render (toJson (" + e + "))", imps).extract[String]
  def json(e: String): String = json("", e)

  /** The Scala-side encoder on the evaluated value: `:json`'s path. */
  def wire(stmts: String, e: String): Either[Encode.Error, String] =
    Encode.toArgonaut(defAndEval(stmts, e, imps)).right.map(_.nospaces)

  // -- primitives ---------------------------------------------------------

  property("Int is a number") = forAll(Gen.choose(-100000, 100000)) { (n: Int) =>
    json(n.toString) == n.toString
  }
  // Long.MinValue is excluded: the literal lexes as negate(9223372036854775808), which overflows
  property("Long is a decimal string") = forAll(Gen.choose(Long.MinValue + 1, Long.MaxValue)) { (l: Long) =>
    json(l.toString + "L") == "\"" + l.toString + "\""
  }
  property("Double is a number") = forAll(Gen.choose(-1e6, 1e6)) { (d: Double) =>
    val out = json(d.toString)
    out.toDouble == d
  }
  property("String is escaped") = forAll(Gen.alphaNumStr, Gen.oneOf("\"", "\\", "\n", " ")) { (s: String, sep: String) =>
    val lit = "\"" + s + sep.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + s + "\""
    argonaut.Parse.parse(json(lit)).right.map(_.string) == Right(Some(s + sep + s))
  }
  property("Bool is a boolean") = sessionProof { implicit s =>
    assert(json("True") == "true" && json("False") == "false")
  }
  property("unit is an empty array; tuples are fixed arrays") = sessionProof { implicit s =>
    assert(json("()") == "[]")
    assert(json("(1, \"a\", True)") == "[1,\"a\",true]")
  }
  property("Maybe is the value or null") = sessionProof { implicit s =>
    assert(json("noInt : Maybe Int\nnoInt = Nothing", "noInt") == "null")
    assert(json("Just 3") == "3")
    assert(json("[Just 1, Nothing]") == "[1,null]")
  }

  // -- collections ----------------------------------------------------------

  property("List is an array") = forAll(Gen.listOf(Gen.choose(0, 99))) { (xs: List[Int]) =>
    json(xs.mkString("[", ", ", "]")) == xs.mkString("[", ",", "]")
  }
  property("a record is an object with sorted unqualified keys") = sessionProof { implicit s =>
    assert(json("field zeta : Int\nfield alpha : String\nfield mid : Bool",
                "{ zeta = 1, alpha = \"a\", mid = True }")
           == "{\"alpha\":\"a\",\"mid\":true,\"zeta\":1}")
  }
  property("a list of records") = sessionProof { implicit s =>
    assert(json("field x : Int\nfield y : Int", "[{ x = 1, y = 2 }, { x = 3, y = 4 }]")
           == "[{\"x\":1,\"y\":2},{\"x\":3,\"y\":4}]")
  }

  // -- data -----------------------------------------------------------------

  property("an all-nullary data type is a string enum") = sessionProof { implicit s =>
    assert(json("data Colour = Red | Green | Blue", "[Red, Blue]") == "[\"Red\",\"Blue\"]")
  }
  property("a data value with fields is tag + positional args") = sessionProof { implicit s =>
    assert(json("data Shape = Circle Double | Rect Double Double | Dot",
                "[Circle 1.5, Rect 2.0 3.0, Dot]")
           == "[{\"tag\":\"Circle\",\"args\":[1.5]},{\"tag\":\"Rect\",\"args\":[2.0,3.0]},{\"tag\":\"Dot\",\"args\":[]}]")
  }
  property("named constructor fields are an object in declaration order") = sessionProof { implicit s =>
    // Stage 1a; the shape is property-tested in full by TestNamedFields
    assert(json("data Series = Series { name : String, points : List Double }",
                "Series \"q1\" [1.0, 2.5]")
           == "{\"name\":\"q1\",\"points\":[1.0,2.5]}")
    assert(json("data Shape = Circle { radius : Double } | Rect { w : Double, h : Double } | Dot",
                "[Circle 1.5, Rect 2.0 3.0, Dot]")
           == "[{\"tag\":\"Circle\",\"radius\":1.5}," +
              "{\"tag\":\"Rect\",\"w\":2.0,\"h\":3.0}," +
              "{\"tag\":\"Dot\",\"args\":[]}]")
  }
  property("nesting goes through data, not records") = sessionProof { implicit s =>
    assert(json("data Series = Series String (List Double)\ndata Config = Config String (List Series)",
                "Config \"Sales\" [Series \"q1\" [1.0, 2.5]]")
           == "{\"tag\":\"Config\",\"args\":[\"Sales\",[{\"tag\":\"Series\",\"args\":[\"q1\",[1.0,2.5]]}]]}")
  }
  property("a parameterised data type") = sessionProof { implicit s =>
    assert(json("data Duo a b = Duo a b", "Duo 1 \"x\"")
           == "{\"tag\":\"Duo\",\"args\":[1,\"x\"]}")
  }
  property("the registry knows a module's data declaration") = sessionProof { implicit s =>
    json("data Colour = Red | Green | Blue", "Red")
    val decl = DataConDecl.forConstructor(Global("Test", "Green"))
    assert(decl.isDefined, "Test.Green registered")
    assert(decl.get.isEnum && decl.get.constructors.map(_.name.string) == List("Red", "Green", "Blue"))
    json("data Shape = Circle Double | Dot", "Dot")
    val shape = DataConDecl.forConstructor(Global("Test", "Circle")).get
    assert(!shape.isEnum)
    assert(shape.constructors.head.fields.map(_._2) == List(Type.double))
  }

  // -- the Json type itself -------------------------------------------------

  property("a Json value encodes as itself") = sessionProof { implicit s =>
    assert(json("obj [(\"a\", arr [num 1.5, int 7L, str \"s\", bool True, jnull])]")
           == "{\"a\":[1.5,7,\"s\",true,null]}")
  }
  property("parse . render is the identity on the Json fragment") =
    forAll(Gen.listOf(Gen.choose(0, 9)), Gen.alphaNumStr) { (xs: List[Int], k: String) =>
      val doc = "{\"" + k + "\":" + xs.mkString("[", ",", "]") + ",\"t\":true,\"n\":null,\"d\":2.5}"
      val out = defAndEval("", "render (maybe jnull id (parse " + "\"" + doc.replace("\"", "\\\"") + "\"" + "))", imps).extract[String]
      argonaut.Parse.parse(out) == argonaut.Parse.parse(doc)
    }
  property("pretty is two-space indented") = sessionProof { implicit s =>
    assert(defAndEval("", "pretty (toJson [1])", imps).extract[String] == "[\n  1\n]")
  }

  // -- errors name the path -------------------------------------------------

  property("a function inside the value is an error at its path") = sessionProof { implicit s =>
    assert(wire("data Holder = Holder (Int -> Int) Int", "[Holder id 1]")
           == Left(Encode.Error("$[0].Holder[0]", "a function has no JSON representation")))
  }
  property("a bottom inside the value is an error at its path") = sessionProof { implicit s =>
    wire("field x : Int", "[{ x = 1 }, { x = error \"boom\" }]") match {
      case Left(Encode.Error(path, msg)) => assert(path == "$[1].x" && msg.contains("boom"), path + ": " + msg)
      case Right(txt) => sys.error("encoded a bottom: " + txt)
    }
  }
  property("toJson# fails as a Bottom, render surfaces it") = sessionProof { implicit s =>
    val r = defAndEval("", "render (toJson id)", imps)
    r match {
      case b: Bottom => assert(b.exn.getMessage.contains("$: a function"), b.exn.getMessage)
      case other     => sys.error("expected a Bottom, got " + other)
    }
  }
  property("a relation is JRel for toJson# and refused by render") = sessionProof { implicit s =>
    val r = defAndEval("field x : Int", "toJson (mkRelation# (toList# [{ x = 1 }]))",
                       imps + ("Native.List" -> all))
    r match {
      case Data(Global("Json", "JRel", _), _) => ()
      case other => sys.error("expected JRel, got " + other)
    }
    Encode.render(r) match {
      case Left(Encode.Error("$", msg)) => assert(msg.contains("relation"), msg)
      case other => sys.error("expected a refusal, got " + other)
    }
  }

  // -- stack safety ---------------------------------------------------------

  property("a 100,000-element list encodes without growing the stack") = sessionProof { implicit s =>
    val out = json("replicate 1 100000")
    assert(out.length == 2 + 100000 * 2 - 1, out.length)
  }
  property("a 100,000-element list of records") = sessionProof { implicit s =>
    val out = json("field x : Int", "replicate { x = 7 } 100000")
    assert(out.startsWith("[{\"x\":7},{\"x\":7}") && out.endsWith("{\"x\":7}]"), out.take(40))
  }
  property("nesting past the depth where nf overflows still encodes") = sessionProof { implicit s =>
    // 2,000 nested singleton lists: `nf` overflows the default stack here.
    // The walker itself is iterative in depth too; argonaut's printer is
    // not (Json.fold recurses per level), which bounds the *rendered*
    // depth at a few thousand levels on the default stack -- far past any
    // document, but a document 20,000 levels deep does not print.
    val out = defAndEval("nest : Int -> Json\nnest 0 = int 0L\nnest n = arr [nest (n - 1)]",
                         "render (nest 2000)", imps).extract[String]
    assert(out == "[" * 2000 + "0" + "]" * 2000)
  }

  // -- the standard library sweep -------------------------------------------

  /** Stage 0 gate: every `data` declared in `modules/` is either in the
    * encodable fragment or rejected with a location and a reason; nothing
    * throws.  The counts are printed so a change in the fragment is visible. */
  property("every stdlib data declaration is classified") = sessionProof { implicit s =>
    val lib = modules(mkEnv.loadFile("Prelude") match {
      case Some(com.clarifi.reporting.ermine.session.Session.Filesystem(p, _)) => new java.io.File(p).getParentFile
      case _ => sys.error("Not in the ermine-scala build tree")
    }).toList
    ermineFixture.loadModules(lib)
    // Builtin types (Bool, List, Maybe, Nullable) are special-cased by the
    // walker, so their `Prim a` witness field is not a rejection
    val decls = DataConDecl.all.filter(d => d.typeName.module != "Test" && d.typeName.module != "Builtin")
    assert(decls.size > 50, "registry populated: " + decls.size)
    val rejected = decls.flatMap { d => Encode.rejections(d).map(r => (d, r)) }
    rejected.foreach { case (d, r) => assert(r.report(d.loc).nonEmpty) }
    val byReason = rejected.groupBy(_._2.reason).map { case (k, v) => (k, v.size) }.toList.sortBy(-_._2)
    println("  JSON sweep: " + decls.size + " data types, " + rejected.size + " rejected constructor fields")
    byReason.foreach { case (k, n) => println("    " + n + " x " + k) }
  }
}
