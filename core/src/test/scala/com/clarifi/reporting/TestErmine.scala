package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import Subst.{ inferType, inferKind, assertTypeClosed }
import Type.{ int, subType, conMap, typeVars }
import scalaparsers._
import parsing.{ phrase, ErParseState, Parser, ParseState, ModuleHeader }
import parsing.ModuleParsers.moduleBody
import parsing.TermParsers.term
import parsing.TypeParsers.typ
import session.{ Lib, SessionEnv, Printer, Session }
import session.Session.{loadModules => _, _}
import syntax.{ ImportExportStatement, Explicit }
import ErParseState.Implicits._

import org.scalacheck._
import Prop.{ Result => _, _ }

import java.io.File
import scalaz.{ Failure => _, Success => _, _ }
import Scalaz.{ gets => _, _ }

/** I am not thread-safe, so use a separate one of me per `Properties`
  * instance.  Importing my symbols unqualified works quite well.
  */
final case class ErmineFixture(prepBaseEnv: SessionEnv => Unit
                               = Function const (())) {
  implicit val supply = Supply.create
  implicit val con = Printer.ignore

  lazy val baseEnv: SessionEnv = {
    implicit val e : SessionEnv = new SessionEnv(_typeCheck = Some(true))
    Lib.preamble
    e.loadedModules = e.loadedModules + "Test"
    prepBaseEnv(e)
    e
  }

  def mkEnv = baseEnv.copy

  def session[A](f: SessionEnv => A): A = f(mkEnv)

  /** If load succeeds, feed the result back into baseEnv.  Kind of
    * evil, but makes things faster. */
  def loadModules(moduleNames: List[String])(implicit s: SessionEnv) = {
    val res = Session.loadModules(moduleNames)
    baseEnv := s
    res
  }

  type ImportSpec = (Option[String], List[Explicit], Boolean)

  val all: ImportSpec = (None, List(), false)
  val imps = Map("Int" -> all, "Builtin" -> all, "Test" -> all)

  def run[A](p: SessionEnv => A): Result[SessionEnv,A] = {
    val env = mkEnv
    try { val a = p(env); Success(a,env.copy) }
    catch { case Death(d,_) => Failure(Some(d),Nil) }
  }

  def loadStatements(
    stmts: String,
    imports: Map[String,ImportSpec] = imps
  )(implicit s: SessionEnv) {
    loadModules(imports.keySet.toList)
    val spsz = ErParseState.mk("<test statements>", stmts, "Test").importing( s.termNames
                                                                            , s.cons.keySet
                                                                            , imports
                                                                            , s.termNameOrigins
                                                                            , s.consOrigins
                                                                            )
    val (sps,m) = parse(moduleBody(ModuleHeader(spsz.loc,"Test",false,imports.toList.map {
      case (k,(as,explicits,using)) => ImportExportStatement(spsz.loc, false, k, as, explicits, using)
    })),spsz)
    loadModule(sps, m)
  }

  def testParse[A](p: Parser[A], e: String, m: Map[String,ImportSpec] = imps)(implicit s: SessionEnv): (ParseState, A) = {
    import ErParseState.Implicits._
    loadModules(m.keySet.toList)
    val epsz = ErParseState.mk("<test>", e, "Test").importing(s.termNames, s.cons.keySet, m, s.termNameOrigins, s.consOrigins)
    parse(p, epsz)
  }

  def typeOf(e: String, m : Map[String,ImportSpec] = imps)(implicit s: SessionEnv): Type =
    Session.eval(e,m)._1

  def typeAfter(p: String, e: String, m: Map[String, ImportSpec] = imps)(implicit s: SessionEnv): Type = {
    loadStatements(p, m)
    typeOf(e,m)
  }

  def typeCase(p: String, e: String, m: Map[String, ImportSpec] = imps)(f: PartialFunction[Type,Unit]): Prop = {
    sessionProof(implicit s => {
      loadStatements(p, m)
      val t = typeOf(e,m)
      if (f isDefinedAt t) f(t) else die("typeCase mismatch")
    })
  }

  def typeChecks(p: String, e: String, m: Map[String, ImportSpec] = imps): Prop = {
    sessionProof(implicit s => {
      loadStatements(p, m)
      typeOf(e,m)
    })
  }

  def kindOf(e: String, m: Map[String, ImportSpec] = imps)(implicit s: SessionEnv): KindSchema = {
    val (ps, tz) = testParse(phrase(typ), e, m)
    val t = subType(conMap("Test", ps.s.typeNames, s.cons), tz)
    assertTypeClosed(t)
    subst { implicit hm => inferKind(Nil,t.close) }
  }

  def kindAfter(p: String, e: String, m: Map[String, ImportSpec] = imps)(implicit s: SessionEnv): KindSchema =
    { loadStatements(p,m); kindOf(e,m) }

  def eval(s: String, m: Map[String, ImportSpec] = imps): Runtime =
    session(implicit env => Session.eval(s, m)._2)

  def defAndEval(stmts: String, e: String, m: Map[String, ImportSpec] = imps): Runtime =
    session(implicit env => {
      loadStatements(stmts, m)
      Session.eval(e, m)._2
    })

  def file(hd: String, elts: String*): File =
    (new File(hd) /: elts)(new File(_, _))

  def modules(dir: java.io.File): Stream[String] =
    dir.list.toStream.flatMap {dirent => new java.io.File(dir, dirent) match {
      case resolved if resolved.isDirectory =>
        modules(resolved).map(dirent |+| "." |+| _)
      case _ if dirent.endsWith(".e") =>
        Stream(dirent.replaceAll("\\.[e]$", ""))
      case _ => Stream.empty
    }
  }

  lazy val srcRoot =
    unfold(new File(Thread.currentThread
                          .getContextClassLoader
                          .getResource("com/clarifi/reporting/TestErmine$.class")
                          .toURI)) (
          (file:File) => Option(file).map(_.getParentFile).map(x => (x,x)))
     // On the next line, the file it was looking for was build.sbt
     // However, when building on a Mac, it makes sense to delete your
     // build.sbt since you need to make some mac specific changes to paths
     // to network files and change the line endings to unix style and don't want
     // to accidentally check it into source control.
     // So, test for the presence of /src instead.  -- EDS
     .find(new File(_, "/src").exists)
     .getOrElse(sys.error("not in an SBT tree"))

  def unexceptional(p: => Prop): Prop = try {
    p
  } catch { case _ => false: Prop }

  def no(p: Prop): Prop = p map { r =>
    r.copy(status = r.status match {case False => True; case _ => False},
           labels = r.labels + "must fail")
  }

  def sessionProp(v: SessionEnv => Any): Prop =
    secure {
      try { v(mkEnv); passed }
      catch { case e: Death => falsified :| e.getMessage }
    }

  def sessionProof(v: SessionEnv => Any): Prop =
    secure {
      try { v(mkEnv); proved }
      catch { case e: Death => falsified :| e.getMessage }
    }

  def circular(d: String, v: String) = typeChecks(d,v)
}

object TestErmine extends Properties("Ermine") {
  private val ermineFixture = ErmineFixture()
  import ermineFixture._

  property("Occurs.fun") = no(sessionProof(implicit s => typeOf("a -> a a")))
  property("Occurs.Maybe") =
    no(sessionProof(implicit s => typeOf("x -> maybe (Just x) Just x",Map("Builtin" -> all, "Maybe" -> all))))
  property("Occurs.kind") = no(sessionProof(implicit s => kindOf("forall f. f f")))
  property("Maybe.Maybe") = no(sessionProof(implicit s => kindOf("Maybe Maybe")))
  // Tests parsing of integers and calling of simple prelude functions also checks prefix -
  property("Int.arithmetic") = forAll((x: Short, y: Short) => {
    def str(x: Short) = if (x < 0) "neg " + x.toInt.abs else x.toString
    val plus = str(x) + " + " + str(y)
    val mult = str(x) + " * " + str(y)
    val minus = str(x) + " - " + str(y)
    val m = Map("Primitive" -> all)
    ((eval(plus, m) == Prim(x + y)) :| "plus") &&
    ((eval(mult, m) == Prim(x * y)) :| "mult") &&
    ((eval(minus, m) == Prim(x - y)) :| "minus") &&
    sessionProp(implicit s =>
      if ((typeOf(plus, m) != int) || (typeOf(mult, m) != int) || (typeOf(minus, m) != int)) die("bad types")
    )
  })

  property("generic arithmetic, primitive comparison") = secure(
    (eval("testMainNative#", Map("PrimitiveTest" -> all)).whnf: Runtime)
     ?= (Prim(List(true, true, true, true, true, true, true, true)): Runtime)
  )

  property("List") = secure(
    (eval("testMainNative#", Map("ListTest" -> all)).whnf: Runtime)
     ?= (Prim(List(true)): Runtime)
  )

  property("locals can be recycled") =
    typeCase("foo = let x = 5 in x\nbar = let x = 42 in x", "(foo, bar)") {
      case AppT(AppT(ProductT(_, 2), `int`), `int`) => ()
    }

  property("Native pairs are 2-tuples") =
    secure(eval("toPair# (1,2)", Map("Native.Pair" -> all)).extract[(Int,Int)]
           ?= (1, 2))

  property("Native pairs round-trip") =
    secure(eval("case fromPair# (toPair# (1,2)) of (1,2) -> 42",
                Map("Native.Pair" -> all)).extract[Int] ?= 42)

  property("Ops run") = secure {
    val s: Short = 42
    (defAndEval("field aaa : Int\nfield two : Int",
                "(col aaa * col two + prim 10) * prim 10 / col two - prim 100",
                Map("Field" -> all, "Relation.Op" -> all,
                    "Builtin" -> all, "String" -> all, "Test" -> all))
     .extract[Op].eval(Map("aaa" -> IntExpr(false, s),
                           "two" -> IntExpr(false, 2)))
     ?= IntExpr(false, ((s - 5) * 10)))
  }

  property("Different op types comparison") = secure {
    val imps = Map("Builtin" -> all,
                   "Relation.Op" -> all, "Relation.Predicate" -> all)
    sessionProof(implicit s => typeOf("prim 42 < prim 43", imps)) &&
    sessionProof(implicit s => typeOf("prim 42L < prim 43L", imps)) &&
    no(sessionProof(implicit s => typeOf("prim 42 < prim 43L", imps)))
  }

  /*property("primexprs/runtime round trip") = {
    implicit val arbExpr = Arbitrary(RelationGens.genPrimExpr)
    forAll { (pe: PrimExpr) =>
      (Runtime.toPrimExpr(Runtime.fromPrimExpr(pe)), pe) match {
        case (NullExpr(ta), NullExpr(te)) => (ta ?= te) :| "null case"
        case (a, e) => (a ?= e) :| "non-null case"
      }
    }
  }*/

  property("DataCon.Argument.Kind") =
    no(sessionProof(implicit s => loadStatements("data O (f : * -> *) = N | S f")))

  property("Type.HigherKinded") = sessionProof(implicit s => kindAfter("type L = List", "L Int"))

  property("Type.HigherKinded.Argument") = no(sessionProof(implicit s => loadStatements("type L (f : * -> *) = List f")))

  property("forall a. a : *") = sessionProof(implicit s =>
    kindOf("forall a. a") match {
      case KindSchema(_,Nil,Star(_)) => ()
      case t => die("Unexpected kind signature")
    }
  )

  property("Field : rho -> * -> *") = sessionProof(implicit s =>
    kindOf("Field") match {
      case KindSchema(_,Nil,ArrowK(_,Rho(_),ArrowK(_,Star(_),Star(_)))) => ()
      case k => die("wrong kind schema:" + k.toString)
    }
  )

  property("let-bound vars shouldn't unify across functions") = secure {
    val code = "foo = let x = 1 in 1\n bar= let x = \"Not an Int; a String\" in 2"
    typeChecks("",code,Map())
    .map( res => if (res.failure) res.copy(status = True) else res.copy(status = False) )
  }

  property("partitioning") = secure {
    val dfs = """field x: Int
                |field y: Int
                |asDisjoint: forall a b. (exists c. c <- (a, b)) => [..a] -> [..b] -> [..a]
                |asDisjoint = const
                |xrel = relation [{x = 1}]
                |yrel = relation [{y = 1}]""".stripMargin
    val mods = Map("Function" -> all, "Field" -> all, "Builtin" -> all,
                   "List" -> all, "Relation" -> all, "Test" -> all)
    typeChecks(dfs, "asDisjoint xrel yrel", mods)
    /* @TODO XFAIL && (typeAfter(dfs, "asDisjoint xrel xrel", mods) fails) */
  }

  property("explicitly typed expression") = sessionProof(implicit s => typeOf("42 : Int"))

  property("do syntax") = secure {
    eval("toList# testMain", Map("Native.List" -> all,
                                 "Syntax.DoTest" -> all)).extract[Any] match {
      case Nil => (true: Prop)
      case errs: List[_] => false :| errs.mkString("; ")
      case x => false :| ("bad testMain structure " + x)
    }
  }

  property("date literals/SQL emitting round-trip") = {
    import java.util.{Calendar => Cal}
    import sql.SqlEmitter
    implicit val arbEmit: Arbitrary[SqlEmitter] =
      Arbitrary(Gen.oneOf(SqlEmitter.mySqlInnoDBEmitter,
                          SqlEmitter.msSqlEmitter))
    implicit val arbCal = Arbitrary(Arbitrary.arbitrary[java.util.Date] map {d =>
      val c = Cal.getInstance
      c setTimeInMillis d.getTime
      c
    })
    forAll {(dat: Cal, emit: SqlEmitter) =>
      val y = dat get Cal.YEAR
      val m = (dat get Cal.MONTH) + 1
      val d = dat get Cal.DAY_OF_MONTH
      assert(1 to 12 contains m,
             "because I can't keep track of all the off-by-oneness")
      sessionProp(implicit s => testParse(phrase(term), "@%d/%d/%d" format (y, m, d), Map.empty)._2 match {
        case LitDate(_, ermineDate) => (emit emitDate ermineDate run) ?= ("'%d-%02d-%02d'" format (y, m, d))
        case fs => die("another day")
      })
    }
  }

  property(":= as a name") = secure{
    sessionProof(implicit s =>
      defAndEval("infix 0 :=\n(:=) x f = f x", "42 := (:=)").extract[Any] match {
        case 42 => true: Prop
        case _ => false: Prop
      })
  }

  // property("solver.sane") = secure(typeAfter("field Fst : Int\nfield Snd : Int", "({Fst = 5} : {Snd})") fails)

  property("circular.annotated") = circular("v = (v : Int)", "v")

  property("circular.application[1]") = circular("v = (x -> x) v", "v")

  property("circular.application[2]") = circular("v x = v x", "v")

//  property("circular definitions: tuples") = circular("v = {Fst = v.Fst}", "v")

  property("circular.lambda") = circular("v = x -> v x", "v")
}

trait ErmineModulesProperties {self: Properties =>
  protected val ermineFixture: ErmineFixture
  import ermineFixture._

  /** Modules to leave out of the load test, because they don't
    * work. */
  def excludedModules: Set[String]

  def libraryModules: Stream[String]

  def testModules: Stream[String]

  def sampleModules: List[File]

  def sampleRoot: File = srcRoot

  property("all modules load") =
    sessionProof(implicit s =>
      loadModules(libraryModules.filterNot(excludedModules).toList))

  property("interesting test modules load") =
    sessionProof(implicit s =>
      loadModules(testModules.toList))

  property("all interesting examples load") =
    sessionProof(implicit s => sampleModules.toStream.map(mod =>
      Filesystem(new File(sampleRoot.getPath, mod.getPath).getPath)).foreach(load(_)))
}

object TestErmineModules extends Properties("Ermine library") with ErmineModulesProperties {
  protected lazy val ermineFixture = ErmineFixture()
  import ermineFixture.{file, mkEnv, modules}

  lazy val excludedModules = Set.empty[String]

  lazy val libraryModules =
    modules(mkEnv.loadFile("Prelude") match {
              case Some(Filesystem(p, _)) => new File(p).getParentFile
              case _ => sys error "Not in Reporting build tree"
            })

  lazy val testModules =
    Stream("Layout.Report.KeyedTest")

  lazy val sampleModules =
    List(  file("examples", "SoftRelation")
         , file("examples", "HelloWorld")
         , file("examples", "ChartsExample")
         , file("examples", "GridExample")
        ) map {fil =>
      new File(fil.getPath |+| ".e")    // std extension
    }
}
