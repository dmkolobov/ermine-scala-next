package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.json.Encode
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.session.Session.SourceFile

import java.nio.file.Files

import org.scalacheck._
import Prop.{ Result => _, _ }
import scalaparsers.Death

/** NAMED CONSTRUCTOR FIELDS and their generated selector functions
  * (tracker/JSON-API-DESIGN.md 3.1 item 2, 3.1b, Stage 1a).
  *
  * The generators produce random DECLARATIONS, not fixed examples: random
  * type names, one to four constructors each written positionally or as a
  * record, zero to three fields drawn from the encodable fragment plus a
  * type parameter and another type of the same module, and random values
  * of those types rendered as Ermine source.  Each property then compares
  * against an answer computed independently in Scala -- the field type,
  * the projected value, the wire JSON -- so a change to the mapping or to
  * the selector's scheme shows up here as a mismatch rather than as a
  * silently different document.
  */
object TestNamedFields extends Properties("Ermine named constructor fields") {
  private lazy val ermineFixture = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import ermineFixture._

  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Json" -> all, "List" -> all,
        "Maybe" -> all, "Function" -> all, "Int" -> all, "Long" -> all,
        "Double" -> all, "Bool" -> all, "String" -> all)

  // ------------------------------------------------------------ the model

  /** A field type: how it is written in a declaration, how a value of it is
    * written, and what that value encodes to. */
  sealed abstract class FTy {
    /** Written as a constructor field (an ATOM, so already parenthesised). */
    def atom: String
    /** Written where a full type is allowed (a selector's result). */
    def src: String = atom
    /** How the pretty printer spells it in the selector's scheme. */
    def pretty: String = src
  }
  case object FInt    extends FTy { def atom = "Int" }
  case object FString extends FTy { def atom = "String" }
  case object FBool   extends FTy { def atom = "Bool" }
  case object FDouble extends FTy { def atom = "Double" }
  case object FLong   extends FTy { def atom = "Long" }
  case object FListI  extends FTy { def atom = "(List Int)"; override def src = "List Int" }
  case object FMaybeI extends FTy { def atom = "(Maybe Int)"; override def src = "Maybe Int" }
  /** The declaration's own type parameter, always instantiated at Int. */
  case object FParam  extends FTy { def atom = "a" }
  /** Another `data` type declared earlier in the same module, applied at
    * `Int` when it takes a parameter (its kind would not be `*` bare). */
  final case class FOther(d: Decl) extends FTy {
    def atom = if (d.param) "(" + d.name + " Int)" else d.name
    override def src = if (d.param) d.name + " Int" else d.name
  }

  final case class Con(name: String, fields: List[(String, FTy)], record: Boolean)
  final case class Decl(name: String, param: Boolean, cons: List[Con]) {
    /** All-nullary: the wire form is the constructor name (Stage 0). */
    def isEnum: Boolean = cons.forall(_.fields.isEmpty)
    /** A record-style constructor with at least one field encodes as an
      * object; the tag distinguishes a union of more than one. */
    def tagged: Boolean = cons.length > 1
    def source: String = {
      val hd = "data " + name + (if (param) " a" else "") + " = "
      hd + cons.map { c =>
        if (c.record && c.fields.nonEmpty)
          c.name + " { " + c.fields.map { case (n, t) => n + " : " + t.src }.mkString(", ") + " }"
        else (c.name :: c.fields.map(_._2.atom)).mkString(" ")
      }.mkString(" | ")
    }
    /** Every field name of the declaration, once, in first-seen order. */
    def fieldNames: List[(String, FTy)] =
      cons.filter(_.record).flatMap(_.fields)
        .foldLeft(List.empty[(String, FTy)]) { (acc, f) =>
          if (acc.exists(_._1 == f._1)) acc else acc :+ f }
  }

  /** A value: its Ermine source and the JSON it must encode to. */
  final case class Val(src: String, json: argonaut.Json)

  // ------------------------------------------------------------ generators

  private val ident: Gen[String] =
    Gen.listOfN(3, Gen.oneOf("abcdefghijklmnopqrstuvwxyz".toList)).map(_.mkString)

  /** A generated FIELD name.  Prefixed, because an unprefixed three-letter
    * name collides with the stdlib often enough to matter (`abs`, `all`,
    * `div`, ...) and that is a refusal of its own (property (d)). */
  private val fieldIdent: Gen[String] = ident.map("nf" + _)

  /** Names are prefixed AND salted.  `DataConDecl`'s registry is
    * process-wide, keyed by `Global("Test", constructorName)`, and every
    * property here loads a module called `Test`: two samples that reused a
    * constructor name would clobber each other's declaration (Stage 0:
    * "last writer wins on a reload"), and the encoder reads the registry,
    * not the session.  One salt per generated module settles it. */
  private val salt = new java.util.concurrent.atomic.AtomicInteger(0)
  private def tyName(k: Int, i: Int): String = "NfT" + k + "x" + i
  private def conName(k: Int, i: Int, j: Int): String = "NfC" + k + "x" + i + "x" + j

  private def baseTys(param: Boolean, prior: List[Decl]): Gen[FTy] = {
    val simple: List[Gen[FTy]] =
      List(FInt, FString, FBool, FDouble, FLong, FListI, FMaybeI).map(Gen.const[FTy])
    val extra =
      (if (param) List(Gen.const[FTy](FParam)) else Nil) ++
      (if (prior.nonEmpty) List(Gen.oneOf(prior).map(FOther(_): FTy)) else Nil)
    Gen.oneOf(simple ++ extra).flatMap(identity)
  }

  /** One declaration.  `shared` lets a field name repeat across
    * constructors, which must give ONE selector working on both (rule 3);
    * when it does, the type repeats with it. */
  private def genDecl(k: Int, i: Int, prior: List[Decl]): Gen[Decl] = for {
    nc    <- Gen.choose(1, 4)
    names <- Gen.listOfN(nc * 3, fieldIdent).map(_.distinct)
    cons  <- Gen.sequence[List[Con], Con]((0 until nc).toList.map { j => for {
               record <- Gen.oneOf(true, false)
               nf     <- Gen.choose(0, 3)
               tys    <- Gen.listOfN(nf, baseTys(true, prior))
               shared <- Gen.oneOf(true, false)
             } yield {
               // field names are drawn from one per-declaration pool: with
               // `shared` a constructor reuses the pool's head names, which
               // is how two constructors come to carry the same field
               val ns = if (shared && names.length >= nf) names.take(nf)
                        else names.slice(j * 3, j * 3 + nf)
               Con(conName(k, i, j), ns.zip(tys), record)
             } })
  } yield {
    // a shared name must carry the SAME type at every site (rule 3 refuses
    // otherwise, which property (c) checks on purpose)
    val fixed = scala.collection.mutable.Map.empty[String, FTy]
    val cs = cons.map { c => c.copy(fields = c.fields.map { case (n, t) =>
      (n, fixed.getOrElseUpdate(n, t)) }) }
    // ... and, once unified, a name must not repeat WITHIN one constructor
    val cs2 = cs.map(c => c.copy(fields =
      c.fields.foldLeft(List.empty[(String, FTy)]) { (acc, f) =>
        if (acc.exists(_._1 == f._1)) acc else acc :+ f }))
    // the declaration takes a parameter exactly when a field uses it: a
    // PHANTOM parameter's kind stays a kind variable and the scheme reads
    // `forall {k} (a: k). T a -> ...` -- which the constructor's own scheme
    // does too (probed 2026-09-14), so it is not a selector question and
    // the generator keeps it out of property (a)'s expected string
    Decl(tyName(k, i), cs2.exists(_.fields.exists(_._2 == FParam)), cs2)
  }

  /** One to three declarations; later ones may use earlier ones as fields. */
  private val genModule: Gen[List[Decl]] = for {
    k  <- Gen.delay(Gen.const(salt.incrementAndGet()))
    n  <- Gen.choose(1, 3)
    ds <- (0 until n).foldLeft(Gen.const(List.empty[Decl])) { (acc, i) =>
            acc.flatMap(prior => genDecl(k, i, prior).map(prior :+ _)) }
  } yield {
    // one name pool for the whole module: a selector may not collide with
    // another type's selector (a located refusal, property (d)), so rename
    // across declarations -- consistently, since a name shared by two
    // constructors of ONE type must stay shared (rule 3)
    val taken = scala.collection.mutable.Set.empty[String]
    ds.map { d =>
      val ren = d.cons.flatMap(_.fields.map(_._1)).distinct.map { n =>
        val nn = if (taken.contains(n)) n + d.name.toLowerCase else n
        taken += nn
        n -> nn
      }.toMap
      d.copy(cons = d.cons.map(c => c.copy(fields = c.fields.map { case (n, t) => (ren(n), t) })))
    }
  }

  import argonaut.Json

  private def genVal(t: FTy): Gen[Val] = t match {
    case FInt | FParam => Gen.choose(0, 1000).map(n => Val(n.toString, Json.jNumber(n)))
    case FString       => ident.map(s => Val("\"" + s + "\"", Json.jString(s)))
    case FBool         => Gen.oneOf(true, false).map(b => Val(if (b) "True" else "False", Json.jBool(b)))
    case FDouble       => Gen.choose(0, 400).map(n => Val((n / 4.0).toString, Json.jNumber(n / 4.0)))
    // an auto-encoded Long is a DECIMAL STRING (JSON numbers lose precision)
    case FLong         => Gen.choose(0L, 1000L).map(n => Val(n.toString + "L", Json.jString(n.toString)))
    case FListI        => Gen.listOf(Gen.choose(0, 100)).map(xs =>
                            Val("[" + xs.mkString(",") + "]", Json.array(xs.map(Json.jNumber(_)): _*)))
    case FMaybeI       => Gen.option(Gen.choose(0, 100)).map {
                            case None    => Val("Nothing", Json.jNull)
                            case Some(n) => Val("(Just " + n + ")", Json.jNumber(n)) }
    case FOther(d)     => genDeclVal(d)
  }

  /** A value of a generated declaration, always in the POSITIONAL spelling
    * (record construction is not in this stage), with the JSON the mapping
    * says it must have. */
  private def genDeclVal(d: Decl): Gen[Val] = for {
    c  <- Gen.oneOf(d.cons)
    vs <- Gen.sequence[List[Val], Val](c.fields.map(f => genVal(f._2)))
  } yield {
    val src = if (c.fields.isEmpty) c.name
              else "(" + (c.name :: vs.map(_.src)).mkString(" ") + ")"
    Val(src, expected(d, c, vs))
  }

  /** The wire form, computed from the declaration alone. */
  private def expected(d: Decl, c: Con, vs: List[Val]): Json =
    if (d.isEnum) Json.jString(c.name)
    else if (c.record && c.fields.nonEmpty) {
      val kept = c.fields.zip(vs).collect {
        // a Maybe field is an OPTIONAL key: Nothing drops out
        case ((n, t), v) if !(t == FMaybeI && v.json.isNull) => (n, v.json)
      }
      Json.obj(((if (d.tagged) List(("tag", Json.jString(c.name))) else Nil) ++ kept): _*)
    } else Json.obj("tag" -> Json.jString(c.name), "args" -> Json.array(vs.map(_.json): _*))

  private def moduleSrc(ds: List[Decl]): String = ds.map(_.source).mkString("\n")

  /** A declaration and one value of it. */
  private val genDeclAndVal: Gen[(List[Decl], Decl, Val)] = for {
    ds <- genModule
    d  <- Gen.oneOf(ds)
    v  <- genDeclVal(d)
  } yield (ds, d, v)

  // ------------------------------------------------------------ helpers

  private def render(stmts: String, e: String): String =
    defAndEval(stmts, "render (toJson (" + e + "))", imps).extract[String]

  private def parsed(txt: String): Json =
    argonaut.Parse.parseOption(txt).getOrElse(sys.error("not JSON: " + txt))

  /** The refusal report for these statements, or None if they loaded. */
  private def refusal(stmts: String): Option[String] =
    try { session { implicit s => loadStatements(stmts, imps) }; None }
    catch { case d: Death => Some(d.getMessage) }

  private def rejected(stmts: String, re: String): Prop =
    refusal(stmts) match {
      case None      => falsified :| ("loaded cleanly; expected a refusal:\n" + stmts)
      case Some(msg) =>
        if (re.r.findFirstIn(msg).isDefined) proved
        else falsified :| ("report did not match /" + re + "/: " +
                           msg.linesIterator.take(2).mkString(" | "))
    }

  // ------------------------------------------------------------ properties

  // (a) every selector has the expected type, and projects the field of a
  //     positionally constructed value
  property("a selector's type is the declared field type") =
    forAllNoShrink(genModule) { ds =>
      val src = moduleSrc(ds)
      sessionProof { implicit s =>
        loadStatements(src, imps)
        ds.foreach { d => d.fieldNames.foreach { case (n, t) =>
          // an existential field gets no selector at all -- none is
          // generated here, so every field name must have one
          val got = Pretty.prettyType(typeOf(n, imps), -1).toString
          val want = (if (d.param) "forall a. " + d.name + " a -> " else d.name + " -> ") + t.pretty
          assert(got == want, d.name + "." + n + ": " + got + " (wanted " + want + ")")
        } }
      }
    }

  property("a selector projects the field of a positional value") =
    forAllNoShrink(genDeclAndVal) { case (ds, d, v) =>
      val src = moduleSrc(ds)
      // read every field the chosen value's constructor actually carries
      val c = d.cons.find(cc => v.src.startsWith("(" + cc.name + " ") || v.src == cc.name).get
      if (!c.record || c.fields.isEmpty) proved
      else sessionProof { implicit s =>
        loadStatements(src, imps)
        c.fields.zipWithIndex.foreach { case ((n, _), i) =>
          val got = parsed(Session.eval("render (toJson (" + n + " " + v.src + "))", imps)._2.extract[String])
          val want = v.json.field(n)
          // a Nothing-valued Maybe field is absent from the object but the
          // selector still returns Nothing, which renders as null
          assert(got == want.getOrElse(Json.jNull),
                 d.name + "." + n + ": " + got.nospaces + " vs " + want.map(_.nospaces))
        }
      }
    }

  // (b) a selector applied to a constructor that lacks the field
  /** A random declaration with one record constructor and one NULLARY
    * constructor, so there is always a well-typed value that the selector
    * cannot read. */
  private val genWithGap: Gen[(String, String, String, String)] = for {
    ns  <- Gen.listOfN(3, fieldIdent).map(_.distinct).suchThat(_.nonEmpty)
    tys <- Gen.listOfN(ns.length, Gen.oneOf[FTy](FInt, FString, FBool, FDouble, FListI))
    i   <- Gen.choose(0, 99)
  } yield {
    val fs = ns.zip(tys)
    val d = Decl("NfGap" + i, false,
                 List(Con("NfGapC" + i, fs, true), Con("NfGapNil" + i, Nil, false)))
    (d.source, fs.head._1, "NfGapNil" + i, "NfGapC" + i)
  }

  property("a selector on a constructor without the field is a named Bottom") =
    forAllNoShrink(genWithGap) { case (src, field, nil, con) =>
      sessionProof { implicit s =>
        loadStatements(src, imps)
        Session.eval(field + " " + nil, imps)._2 match {
          case b: Bottom =>
            val msg = b.exn.getMessage
            assert(msg == nil + " has no field " + field, msg)
          case other => sys.error("expected a Bottom, got " + other)
        }
      }
    }

  // (c) a field name shared by two constructors
  property("a shared field name of one type is one selector over both") =
    forAll(Gen.choose(0, 1000), Gen.choose(0, 1000)) { (x, y) =>
      val src = "data NfU = NfA { nfq : Int } | NfB { nfq : Int, nfr : Bool }"
      sessionProof { implicit s =>
        loadStatements(src, imps)
        assert(Session.eval("nfq (NfA " + x + ")", imps)._2.extract[Int] == x)
        assert(Session.eval("nfq (NfB " + y + " True)", imps)._2.extract[Int] == y)
        assert(Pretty.prettyType(typeOf("nfq", imps), -1).toString == "NfU -> Int")
      }
    }

  property("a shared field name with two types is refused at the declaration") =
    forAll(Gen.oneOf("Bool", "String", "Double", "List Int")) { other =>
      rejected("data NfV = NfP { nfz : Int } | NfQ { nfz : " + other + " }",
               "field nfz has different types in two constructors of NfV")
    }

  // (d) a selector name that collides with something else the module defines
  property("a colliding selector name is refused, and loads once renamed") =
    forAll(ident) { n =>
      val nm = "nf" + n
      val collisions: List[(String, String)] = List(
        // a term equation of the same name
        (nm + " : Int\n" + nm + " = 1\ndata NfW = NfW { " + nm + " : Int }",
         "field selector " + nm + " collides with the definition of " + nm),
        // a `field` witness
        ("field " + nm + " : Int\ndata NfW = NfW { " + nm + " : Int }",
         "field selector " + nm + " collides with the declaration of " + nm),
        // a constructor of this module
        ("data NfW = " + nm + " Int | NfX { " + nm + " : Int }",
         "field selector " + nm + " collides with the declaration of " + nm),
        // another data type's selector
        ("data NfW = NfW { " + nm + " : Int }\ndata NfX = NfX { " + nm + " : Int }",
         "field selector " + nm + " is already a field selector of another data type"))
      collisions.foldLeft(proved: Prop) { case (acc, (src, msg)) =>
        acc && rejected(src, java.util.regex.Pattern.quote(msg)) } &&
      // renaming the selector makes every one of them load
      typeChecks("field " + nm + " : Int\ndata NfW = NfW { " + nm + "2 : Int }", nm + "2", imps)
    }

  property("a selector name that shadows an import is refused") =
    forAll(Gen.oneOf("id", "const", "flip", "head", "tail")) { n =>
      rejected("data NfY = NfY { " + n + " : Int }",
               "field selector " + n + " would shadow global definition")
    }

  // (e) the record spelling changes nothing about construction or matching
  property("record and positional spellings evaluate alike") =
    forAllNoShrink(genDeclAndVal) { case (ds, d, v) =>
      val c = d.cons.find(cc => v.src == cc.name || v.src.startsWith("(" + cc.name + " ")).get
      // one positional pattern match that rebuilds the constructor's
      // arguments, rendered as JSON -- the one answer both spellings of the
      // SAME declaration must give (the wire form of the value itself
      // differs by design once the fields are named)
      val pat = (c.name :: (1 to c.fields.length).map("p" + _).toList).mkString(" ")
      // only fields that are NOT another generated type: a nested value's
      // own wire form depends on ITS spelling, which is the difference this
      // property must not see
      val flatIx = c.fields.zipWithIndex.collect {
        case ((_, t), i) if !t.isInstanceOf[FOther] => i + 1 }
      val body = flatIx match {
        case Nil      => "0"
        case i :: Nil => "p" + i
        case is       => "(" + is.map("p" + _).mkString(", ") + ")"
      }
      val probe = "nfprobe = case " + v.src + " of\n  " + pat + " -> " + body + "\n"
      val e = "render (toJson nfprobe)"
      val a = defAndEval(moduleSrc(ds) + "\n" + probe, e, imps).extract[String]
      val b = defAndEval(moduleSrc(ds.map(x => x.copy(cons = x.cons.map(_.copy(record = false))))) +
                         "\n" + probe, e, imps).extract[String]
      (a ?= b) :| (probe + " gave " + a + " / " + b)
    }

  // (f) existential fields get no selector; their siblings do
  property("an existential field gets no selector, a sibling still does") = {
    val src = "data NfH = forall e. NfHidden { nfsecret : e, nfshown : Int }"
    no(typeChecks(src, "nfsecret", imps)) &&
    typeChecks(src, "nfshown", imps) &&
    sessionProof { implicit s =>
      loadStatements(src, imps)
      assert(Pretty.prettyType(typeOf("nfshown", imps), -1).toString == "NfH -> Int")
      // the name survives on the WIRE even with no selector for it
      assert(Session.eval("render (toJson (NfHidden 1 5))", imps)._2.extract[String]
             == "{\"nfsecret\":1,\"nfshown\":5}")
    }
  }

  // (g) the wire form, against a JSON document built independently
  property("the wire form matches the mapping") =
    forAllNoShrink(genDeclAndVal) { case (ds, d, v) =>
      val got = parsed(render(moduleSrc(ds), v.src))
      (got ?= v.json) :| (moduleSrc(ds) + "\n" + v.src + "\n got " + got.nospaces +
                          "\nwant " + v.json.nospaces)
    }

  property("a single-constructor record has no tag, a union does") = sessionProof { implicit s =>
    assert(render("data NfS = NfS { nfa : String, nfb : List Double }",
                  "NfS \"q1\" [1.0]") == "{\"nfa\":\"q1\",\"nfb\":[1.0]}")
    assert(render("data NfR = NfC1 { nfrad : Double } | NfDot",
                  "NfC1 1.5") == "{\"tag\":\"NfC1\",\"nfrad\":1.5}")
    assert(render("data NfR = NfC1 { nfrad : Double } | NfDot",
                  "NfDot") == "{\"tag\":\"NfDot\",\"args\":[]}")
  }

  property("a Nothing-valued Maybe field is an absent key") = sessionProof { implicit s =>
    val src = "data NfO = NfO { nfreq : Int, nfopt : Maybe Int, nfvar : Maybe Int }"
    assert(render(src, "NfO 1 (Just 2) Nothing") == "{\"nfreq\":1,\"nfopt\":2}")
    assert(render(src, "NfO 1 Nothing Nothing") == "{\"nfreq\":1}")
    // a field whose DECLARED type is a variable keeps the walker's null
    assert(render("data NfG a = NfG { nfpv : a }", "NfG Nothing") == "{\"nfpv\":null}")
  }

  // (h) the registry
  property("the registry reports the field names in order") =
    forAllNoShrink(genModule) { ds =>
      val src = moduleSrc(ds)
      sessionProof { implicit s =>
        loadStatements(src, imps)
        ds.foreach { d =>
          val decl = DataConDecl.forType(Global("Test", d.name))
            .getOrElse(sys.error("unregistered: " + d.name))
          assert(decl.constructors.map(_.name.string) == d.cons.map(_.name))
          decl.constructors.zip(d.cons).foreach { case (rc, c) =>
            val want = if (c.record && c.fields.nonEmpty) c.fields.map(f => Some(f._1))
                       else c.fields.map(_ => None)
            assert(rc.fields.map(_._1) == want,
                   d.name + "." + c.name + ": " + rc.fields.map(_._1) + " vs " + want)
          }
        }
      }
    }

  // (i) interface parity: the .ei path runs processTypeDefComponent on the
  //     parsed source too, so the encoder must see the same names
  property("interfaces on and off encode identically") = secure {
    implicit val su: scalaparsers.Supply = scalaparsers.Supply.create
    implicit val printer: Printer = Printer.ignore
    val src =
      """module NfI where
        |import Json
        |import List
        |import Maybe
        |
        |data NfISeries = NfISeries { nfiname : String, nfipts : List Double, nfiopt : Maybe Int }
        |data NfIShape = NfICircle { nfirad : Double } | NfIDot
        |
        |nfidoc : List String
        |nfidoc = [render (toJson (NfISeries "q" [1.0] Nothing)),
        |          render (toJson (NfICircle 1.5)),
        |          render (toJson NfIDot),
        |          render (toJson (nfirad (NfICircle 2.5)))]
        |""".stripMargin
    val dir = Files.createTempDirectory("ermine-nf")
    Files.write(dir.resolve("NfI.e"), src.getBytes("UTF-8"))
    // one string per session, built by the ENCODER from the list of
    // rendered documents, so a difference anywhere shows up as a diff
    def answer(useInterface: Boolean): String = {
      implicit val e: SessionEnv = new SessionEnv(_typeCheck = Some(true),
                                                  _useInterface = Some(useInterface))
      Lib.preamble
      e.loadFile = SourceFile.inOrder(SourceFile.filesystem(dir.toString) _, e.loadFile)
      Session.loadModules(List("NfI"))
      val m = Map("NfI" -> ((None, List[com.clarifi.reporting.ermine.syntax.Explicit[Global]](), false)),
                  "Json" -> ((None, List[com.clarifi.reporting.ermine.syntax.Explicit[Global]](), false)))
      Encode.render(Session.eval("nfidoc", m)._2).fold(e => "error: " + e.report, identity)
    }
    try ErmineFixture.literalLock.synchronized {
      Session.depCache.clear()
      val off = answer(false)
      Session.depCache.clear()
      val coldOn = answer(true)                 // writes NfI.ei
      val wroteEi = Files.exists(dir.resolve("NfI.ei"))
      Session.depCache.clear()
      val warmOn = answer(true)                 // reads it back
      (off ?= coldOn) :| "interfaces off vs cold on" &&
      (off ?= warmOn) :| ("interfaces off vs warm on (ei written: " + wroteEi + ")") &&
      (off.contains("nfiname") ?= true) :| ("named on the wire: " + off)
    }
    finally { Session.depCache.clear(); ErmineFixture.deleteTree(dir) }
  }
}
