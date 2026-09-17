package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import Subst.{ inferType, inferKind, assertTypeClosed }
import Type.{ int, subType, conMap, typeVars }
import scalaparsers._
import parsing.{ phrase, ErParseState, Parser, ParseState, ModuleHeader }
import parsing.ModuleParsers.moduleBody
import parsing.TermParsers.term
import parsing.TypeParsers.typ
import session.{ Lib, SessionEnv, Printer, Session, CheckMethod }
import session.Session.{loadModules => _, _}
import syntax.{ ImportExportStatement, Explicit }
import ErParseState.Implicits._

import org.scalacheck._
import Prop.{ Result => _, _ }

import java.io.File
import scalaz.{ Failure => _, Success => _, _ }
import Scalaz.{ gets => _, _ }

object ErmineFixture {
  /* RULE FOR EVERY SUITE: never `System.setProperty` a flag that a `SessionEnv`,
   * `SubstEnv` or `GenRules` reads ONCE.  The suite runs in ONE JVM with classes in
   * parallel, so a flip lands on whichever property happens to be running.  A mode a
   * suite needs is a SESSION OPTION, passed to the fixture below. */

  /** THE ONE REASON a suite asks for a mode other than the shipped default: booting the
    * standard library under `error` fails while any shipped signature is dishonest, and a
    * suite must fail for its own reason.  When the library corrections are in this is
    * `None` and every use of it can go -- which is why it is one named value rather than
    * twenty literals. */
  val untilSigFixes: Option[com.clarifi.reporting.ermine.SigEntail.Mode] =
    None  // the 2.11 library corrections are in (see backport/CORRECTIONS.md)
}

/** I am not thread-safe, so use a separate one of me per `Properties`
  * instance.  Importing my symbols unqualified works quite well.
  */
/** `sigEntail` is the SESSION OPTION of SIG-3, not a system property:
  * `SessionEnv.sigEntail` is a `val` read at construction, so a suite that wants a mode
  * other than this fixture's constructs its own, and two fixtures with different modes
  * coexist in one JVM.  `System.setProperty` could not do this -- see the rule above.
  *
  * THE DEFAULT IS THE SHIPPED DEFAULT (`None` inherits `-Dermine.sigEntail`, i.e. `error`),
  * so a suite tests what ships unless it says otherwise. */
final case class ErmineFixture(prepBaseEnv: SessionEnv => Unit
                               = Function const (()),
                               sigEntail: Option[com.clarifi.reporting.ermine.SigEntail.Mode]
                               = None) {
  implicit val supply = Supply.create
  implicit val con = Printer.ignore

  lazy val baseEnv: SessionEnv = {
    implicit val e : SessionEnv = new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false),
                                                _sigEntail = sigEntail)
    Lib.preamble
    e.loadedModules = e.loadedModules + ("Test" -> CheckMethod.Interface)
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

  type ImportSpec = (Option[String], List[Explicit[Global]], Boolean)

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
    loadModule(sps, m, _ => None)
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

  def unexceptional(p: => Prop): Prop = try {
    p
  } catch { case _ : Throwable => false: Prop }

  /** Invert a property: the body must FAIL.
    *
    * `no` leaves a refuted result *passed* (status `True`), not *proved*, so ScalaCheck keeps
    * drawing until `minSuccessfulTests` (100).  That is the RIGHT semantics for a body that
    * consumes generated input -- `no(forAll(g) { ... })`, where every draw must fail -- and it
    * is the WRONG semantics for a body that takes no input.
    *
    * For a DETERMINISTIC refutation use `rejects`, which is proved by one evaluation.
    *
    * BACK-PORT NOTE, and it matters for what the change below is WORTH on this branch
    * (`backport/SUBSUME-2.11.md`).  On `scala3-migration` those hundred draws are a hundred
    * complete re-checks of the program, each re-reading the module's whole import closure
    * (~9 s), which is what made the B1 rejection property look like a hang -- 1,099 s to the
    * second.  HERE THEY ARE NOT, and the reason is NOT `Prop.secure`: that is eager in BOTH
    * scalacheck versions (`try pv(p) catch ..`, as `TestRunner.scala:50-57` on
    * `json-encode-2.11` already records).  What differs is how `Properties` STORES a property,
    * verified in both shipped jars with `javap`:
    *
    *   1.11.3  PropertySpecifier.update(String, Prop)                <- BY VALUE
    *   1.15.4  PropertySpecifier.update(String, Function0[Prop])     <- BY NAME
    *
    * So here the whole right-hand side of `property(..) = ..` is evaluated ONCE, where it is
    * written -- in the suite object's static initialiser -- and the stored `Prop` is a constant
    * `Result` that the other ninety-nine draws only re-wrap; on `scala3-migration` the by-name
    * `update` re-evaluates that right-hand side per draw, which is where the 1,099 s went.
    * `sessionProof`/`sessionProp`/`typeChecks` are ordinary expressions, so on this branch the
    * check runs ONCE however many tests ScalaCheck asks for.  So `rejects` buys no wall clock
    * here; what it buys is the same STATUS and the same harness as the Scala 3 branch -- a
    * refutation reads `OK, proved property` -- and it is already right for the day a suite
    * defers its property with a lazy `secure` shadow (the `def secure` idiom of the JSON suites
    * on `json-encode-2.11`, and of `TestRowRefusals` here). */
  def no(p: Prop): Prop = p map { r =>
    r.copy(status = r.status match {case False => True; case _ => False},
           labels = r.labels + "must fail")
  }

  /** A DETERMINISTIC refutation: the body must fail, and ONE evaluation settles it.
    *
    * Same verdict as `no` -- refused is green, accepted/thrown/undecided is red -- but a
    * refusal maps to `Proof` rather than `True`, and ScalaCheck stops at the first test on a
    * proved property exactly as it does for `sessionProof`.  Use it wherever the body takes no
    * generated input; `no` stays for `no(forAll(...))`, where proving the first draw would
    * silently drop the other ninety-nine.
    *
    * WHAT IS LOST, said plainly: a deterministic property run 100 times was run at 100
    * different `Supply` id bases, and under `no` EVERY one of those hundred had to fail -- so a
    * refutation that some id order made ACCEPT at one base in a hundred turned the property
    * red.  `rejects` makes that assertion ONCE PER PROGRAM instead of a hundred times, and
    * `TestRowRefusals` trades the lost breadth the other way: sixteen fresh id bases over
    * sixteen DIFFERENT generated programs instead of a hundred bases over one.
    *
    * BACK-PORT NOTE: on this branch the lost breadth was never there to lose.  scalacheck
    * 1.11.3 stores a property BY VALUE (`PropertySpecifier.update(String, Prop)`; see `no`
    * above), so the hundred draws of a `sessionProof` body were a hundred re-wraps of ONE
    * evaluation at ONE id base, not a hundred checks.  `TestRowRefusals`' sixteen bases are
    * therefore a net gain here, not a trade. */
  def rejects(p: Prop): Prop = p map { r =>
    r.copy(status = r.status match {case False => Proof; case _ => False},
           labels = r.labels + "must fail")
  }

  /** Run `body` on a daemon thread and join it with a deadline; answer what happened.
    *
    * The point is to FAIL LOUDLY instead of wedging the run: a check that really did diverge
    * becomes a red property in bounded time instead of holding a `core/test` thread until
    * somebody kills the JVM (the `(iso)` idiom, `TestRunner.scala` on `json-encode-2.11`).
    * The thread is a daemon, so a diverged check cannot keep the JVM alive either.
    *
    * The outcome is one of `"refused: <message>"`, `"accepted"`, `"threw <t>"` or
    * `"did not finish in <ms> ms"`, with the elapsed milliseconds.
    *
    * The one leak is the intended one: a genuinely diverged check leaves one spinning daemon
    * thread for the life of the JVM (no `interrupt()` is attempted, and the checker would not
    * honour one), which can slow the rest of that run -- but that run is already red. */
  def bounded(ms: Long)(body: => Unit): (String, Long) = {
    val answer = new java.util.concurrent.atomic.AtomicReference[String](null)
    val t0 = System.currentTimeMillis
    val th = new Thread(new Runnable {
      def run(): Unit = answer.set(
        try { body; "accepted" }
        catch { case e: Death => "refused: " + e.getMessage
                case e: Throwable => "threw " + e })
    })
    th.setDaemon(true)
    th.setName("ermine-bounded-check")
    th.start()
    th.join(ms)
    (Option(answer.get).getOrElse("did not finish in " + ms + " ms"),
     System.currentTimeMillis - t0)
  }

  /** Load a generated module into `s` and say what happened: `"accepted"`, or
    * `"refused: <message>"`.  Compose with `bounded` for a deadline. */
  def outcomeOf(moduleName: String, src: String)(implicit s: SessionEnv): String =
    try { loadNamed(moduleName, src); "accepted" }
    catch { case e: Death => "refused: " + e.getMessage }

  /** Load a generated module under its OWN name into the session it is handed.  A refusal is
    * a `Death`, as everywhere else in the fixture -- `bounded` turns it into an outcome
    * string, and a plain `try` will do where no deadline is wanted.
    *
    * WHY A SEPARATE PATH.  `loadStatements` above exists for one program at a time: it names
    * every case `module Test`, parses it against the session's import environment and calls
    * `loadModule` directly, and a case loaded into a fresh `mkEnv` re-reads and re-type-checks
    * the whole import closure (a library boot, tens of seconds).  A generator that wants twenty
    * cases cannot pay that.  Under its OWN module name a case collides with nothing, so the
    * cases can all go into ONE warm session and the closure is read once.  `moduleName` must be
    * unique in the PROCESS, because the dep cache keys a `Literal` by module name
    * (`Session.scala:295-308`: `hashCode`/`equals` are the default module name's).  The entry
    * is evicted before and after so the cache does not grow with the sample.
    *
    * A FAILED load leaves the imports loaded -- `Session.load` loads the deps before `d.make`
    * runs -- which is what makes the second and later cases of a generated sample cheap.
    *
    * BACK-PORT NOTE (`backport/SUBSUME-2.11.md`).  On `scala3-migration` this method's
    * docstring argues at length that dropping `ErmineFixture.literalLock` is sound, because
    * there `loadStatements` takes that lock around a dep-cache eviction and `TestDateAndScan`
    * holds the same lock for a whole property body with the JVM DEFAULT TIMEZONE changed.
    * NEITHER IS TRUE ON THE 2.11 LINE: `loadStatements` above never touches `Session.depCache`
    * and takes no lock, and no suite here changes the default timezone (`TestDateAndScan` is
    * not back-ported).  `ErmineFixture.literalLock` does not exist on `backport-2.11` at all;
    * on `json-encode-2.11` it exists and is taken by exactly one property -- `TestNamedFields`'
    * interface-cache case, which CLEARS the whole dep cache -- and a `loadNamed` in flight
    * during that clear can be made to re-read a dependency, never to reach a different verdict.
    * What survives of the argument is the part about this branch's data structure:
    * `Session.depCache` is a `HashMap with SynchronizedMap` (`Session.scala:101`), so this
    * unlocked `-=` can neither corrupt it nor race another property's, and a `Literal`'s
    * identity IS its module name, which every caller here mints uniquely. */
  def loadNamed(moduleName: String, src: String)(implicit s: SessionEnv): Unit = {
    val file = Session.Literal("module " + moduleName + " where\n" + src + "\n", moduleName)
    try { Session.depCache -= file; Session.load(file, Some(moduleName)); () }
    finally Session.depCache -= file
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
  private val ermineFixture = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import ermineFixture._

  property("Occurs.fun") = rejects(sessionProof(implicit s => typeOf("a -> a a")))
  property("Occurs.Maybe") =
    rejects(sessionProof(implicit s => typeOf("x -> maybe (Just x) Just x",Map("Builtin" -> all, "Maybe" -> all))))
  property("Occurs.kind") = rejects(sessionProof(implicit s => kindOf("forall f. f f")))
  property("Maybe.Maybe") = rejects(sessionProof(implicit s => kindOf("Maybe Maybe")))
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
    rejects(sessionProof(implicit s => typeOf("prim 42 < prim 43L", imps)))
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
    rejects(sessionProof(implicit s => loadStatements("data O (f : * -> *) = N | S f")))

  property("Type.HigherKinded") = sessionProof(implicit s => kindAfter("type L = List", "L Int"))

  property("Type.HigherKinded.Argument") = rejects(sessionProof(implicit s => loadStatements("type L (f : * -> *) = List f")))

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

  def sampleModules: List[String]

  def sampleRoot: SourceFile.Loader = {
    import SourceFile._
    val examples = file("core", "examples")
    inOrder(filesystem(examples.getPath),
            classloader("com/clarifi/reporting/examples"))
  }

  property("all modules load") =
    sessionProof(implicit s =>
      loadModules(libraryModules.filterNot(excludedModules).toList))

  property("interesting test modules load") =
    sessionProof(implicit s =>
      loadModules(testModules.toList))

  property("all interesting examples load") =
    sessionProof{implicit s =>
      sampleModules
        .traverseU(mod => sampleRoot.apply(mod) \/> mod)
        .fold(mod => throw Death("example " + mod + " not found"),
              _.foreach(load(_)))}
}

object TestErmineModules extends Properties("Ermine library") with ErmineModulesProperties {
  protected lazy val ermineFixture = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import ermineFixture.{mkEnv, modules}

  lazy val excludedModules = Set.empty[String]

  lazy val libraryModules =
    modules(mkEnv.loadFile("Prelude") match {
              case Some(Filesystem(p, _)) => new File(p).getParentFile
              case _ => sys error "Not in Reporting build tree"
            })

  lazy val testModules =
    Stream("Layout.Report.KeyedTest")

  lazy val sampleModules =
    List("SoftRelation"
       , "HelloWorld"
       , "ChartsExample"
       , "GridExample")
}
