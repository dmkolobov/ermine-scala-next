package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import Subst.{ inferType, inferKind, assertTypeClosed }
import Type.{ int, subType, conMap, typeVars }
import scalaparsers._
import parsing.{ ErParseState, Parser, ParseState }
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
  /** Serializes dynamic `Literal` loads: their dep-cache key is the
    * module name, shared across every fixture in the process. */
  val literalLock = new Object

  /* RULE FOR EVERY SUITE (LSP Stage 3 item 6.0, tracker/loopmodel/LSP3-6.0-HYGIENE.md):
   * never `System.setProperty` a flag that Session reads PER CALL — `ermine.loadInSeries`
   * above all (`Session.loadModules` re-reads it every time; its series branch asks the
   * loader for every name, including the sourceless `Test` and `Builtin`, so a 16 ms flip
   * killed whichever concurrent property was loading: F4 review R-1).  The suite runs in
   * ONE JVM with classes in parallel.  To exercise a schedule, call it (`Session.
   * loadModulesInSeries`); to flip a read-once flag, go through TestInterfaceKey.withProps,
   * whose whitelist names the only properties that are safe to set at runtime. */

  /** THE ONE REASON a suite asks for a mode other than the shipped default: booting the
    * standard library under `error` fails until the seven dishonest shipped signatures are
    * corrected (branch `sig-fixes`), and a suite must fail for its own reason.  When the
    * corrections land this becomes `None` and every use of it can go -- which is why it is one
    * named value rather than twenty literals. */
  val untilSigFixes: Option[com.clarifi.reporting.ermine.SigEntail.Mode] =
    None  // LANDED 2026-09-11: sig-fixes merged; every fixture inherits the shipped default (error)

  /** Delete a staged temp workspace, deepest entry first.  Every suite that
    * calls `Files.createTempDirectory` must run this from a `finally`: without
    * it `core/test` leaves a tree in the system temp directory on every run
    * (F4 review R-5). */
  def deleteTree(p: java.nio.file.Path): Unit =
    try {
      if (java.nio.file.Files.exists(p))
        java.nio.file.Files.walk(p).sorted(java.util.Comparator.reverseOrder[java.nio.file.Path]())
          .forEach(q => try java.nio.file.Files.delete(q) catch { case _: Throwable => () })
    } catch { case _: Throwable => () }
}

/** I am not thread-safe, so use a separate one of me per `Properties`
  * instance.  Importing my symbols unqualified works quite well.
  */
/** `sigEntail` is the SESSION OPTION of SIG-3 (`tracker/SIG-ENTAIL-PLAN.md`), not a system
  * property: `SessionEnv.sigEntail` is a `val` read at construction, so a suite that wants a
  * mode other than this fixture's constructs its own, and two fixtures with different modes
  * coexist in one JVM.  `System.setProperty` could not do this -- see the rule above, and the
  * read-once `val`s it names.
  *
  * THE DEFAULT IS THE SHIPPED DEFAULT (`None` inherits `-Dermine.sigEntail`, i.e. `error`), so
  * a suite tests what ships unless it says otherwise.  A suite that BOOTS THE STANDARD LIBRARY
  * while the library still has dishonest signatures cannot: it would fail on
  * `DrilldownList.cons_Bracket` rather than on its own subject, so those fixtures pass
  * `sigEntail = ErmineFixture.untilSigFixes` -- ONE value to delete when the corrections land
  * (S3 review, landing checklist). */
final case class ErmineFixture(prepBaseEnv: SessionEnv => Unit
                               = Function const (()),
                               sigEntail: Option[com.clarifi.reporting.ermine.SigEntail.Mode]
                               = None) {
  // Supply is documented single-threaded; ScalaCheck runs properties on
  // a pool, so a shared instance races `lo` and hands two threads the
  // same id (the recurring eval:unbound-variable flake).  Per-thread
  // supplies draw from the synchronized global block allocator, so ids
  // stay globally unique.
  private val tlSupply = ThreadLocal.withInitial[Supply](() => Supply.create)
  implicit def supply: Supply = tlSupply.get
  implicit val con: Printer = Printer.ignore

  lazy val baseEnv: SessionEnv = {
    implicit val e : SessionEnv = new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false),
                                                _sigEntail = sigEntail)
    Lib.preamble
    e.loadedModules = e.loadedModules + ("Test" -> CheckMethod.Interface)
    prepBaseEnv(e)
    e
  }

  /** baseEnv writeback and copy are field-by-field; without the lock a
    * concurrent property's copy can see termNames from one load and env
    * from another (torn copy -> "eval: unbound variable"). */
  private val envLock = new Object

  def mkEnv = envLock.synchronized { baseEnv.copy }

  def session[A](f: SessionEnv => A): A = f(mkEnv)

  /** If load succeeds, feed the result back into baseEnv.  Kind of
    * evil, but makes things faster. */
  def loadModules(moduleNames: List[String])(implicit s: SessionEnv) = {
    val res = Session.loadModules(moduleNames)
    envLock.synchronized {
      // NEVER capture a session holding the dynamic Test module: its
      // Literal is NAME-keyed, so a written-back loadedFiles entry
      // short-circuits every later property's Test load (kindAfter
      // poisoned the whole suite this way)
      if (s.loadedFiles.keys.exists(_.defaultModuleName == "Test"))
        sys.error("fixture writeback would capture the dynamic Test module — " +
                  "use Session.loadModules directly after loadStatements")
      baseEnv := s
    }
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

  /** Lines the `module Test` wrapper prepends before the statements
    * (positions in refusals from loadStatements are offset by this). */
  def statementWrapperLines(imports: Map[String,ImportSpec] = imps): Int =
    2 + imports.count(_._1 != "Test")

  def loadStatements(
    stmts: String,
    imports: Map[String,ImportSpec] = imps
  )(implicit s: SessionEnv): Unit = {
    // statements load as one `module Test` Literal through the pipeline
    // (imports rendered to source; the corpus uses plain and `as` forms)
    loadModules(imports.keySet.toList)
    val importLines = imports.toList.collect {
      case (m, spec) if m != "Test" => spec match {
        case (Some(a), _, _) => s"import $m as $a"
        case _               => s"import $m"
      }
    }.mkString("\n")
    val src = "module Test where\n" + importLines + "\n\n" + stmts + "\n"
    val file = Session.Literal(src, "Test")
    // Literal equality keys off the module NAME (see its equals); the
    // process-global depCache would replay the first "Test" forever,
    // and a concurrent property's freshly-cached dep must not be
    // observed between our evict and load
    ErmineFixture.literalLock.synchronized {
      Session.depCache -= file
      Session.load(file)
      Session.depCache -= file
    }
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
    Session.loadModules(m.keySet.toList)
    val t = com.clarifi.reporting.ermine.rename.NewPipeline.replType("<test type>", e, m)
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
    * is the WRONG semantics for a body that takes no input: a hundred identical checks of one
    * fixed program, each of which re-reads and re-type-checks the module's whole import
    * closure (~9 s: `tracker/satterm/SUBSUME-STAGE0.md` §6.2).  That is what made the B1
    * rejection property look like a hang -- it is not a hang, it is 100 x 9.1 s, 1,099 s to
    * the second (`SUBSUME-STAGE0-REVIEW.md` §2.2).
    *
    * For a DETERMINISTIC refutation use `rejects`, which is proved by one evaluation. */
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
    * WHAT IS LOST, said plainly (S2 review F-2): a deterministic property run 100 times was run
    * at 100 different `Supply` id bases, and under `no` EVERY one of those hundred had to fail
    * -- so a refutation that some id order made ACCEPT at one base in a hundred turned the
    * property red.  That is a real assertion, not accidental coverage, and it is exactly the
    * failure mode this programme cares about; the S0 review's §4.4 records a measured 2x id-base
    * outlier, so id-order sensitivity here is measured rather than imagined.  `rejects` makes
    * that assertion ONCE PER PROGRAM instead of a hundred times, and `TestRowRefusals` trades
    * the lost breadth the other way: sixteen fresh id bases over sixteen DIFFERENT generated
    * programs, in 69 % less wall clock, instead of a hundred bases over one. */
  def rejects(p: Prop): Prop = p map { r =>
    r.copy(status = r.status match {case False => Proof; case _ => False},
           labels = r.labels + "must fail")
  }

  /** Run `body` on a daemon thread and join it with a deadline; answer what happened.
    *
    * The point is to FAIL LOUDLY instead of wedging the run: a check that really did diverge
    * becomes a red property in bounded time instead of holding a `core/test` thread until
    * somebody kills the JVM (the `(iso)` idiom, `TestRunner.scala` on `json-encode`).  The
    * thread is a daemon, so a diverged check cannot keep the JVM alive either.
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
    * `loadStatements` exists for one program at a time: every case is `module Test`, so the
    * fixture evicts the process-global dep cache around it and takes `literalLock` -- and a
    * case loaded into a fresh `mkEnv` re-reads and re-type-checks the whole import closure,
    * about 9 s a case.  A generator that wants twenty cases cannot pay that.  Under its own
    * module name a case collides with nothing, so the cases can go into ONE warm session and
    * the closure is read once; `moduleName` must be unique in the PROCESS, because the dep
    * cache keys a `Literal` by module name (`Session.scala:328-341`).  The entry is evicted
    * afterwards so the cache does not grow with the sample.  No `literalLock`: the lock is
    * there for the shared `"Test"` key, which this path does not use.
    *
    * A FAILED load leaves the imports loaded -- `Session.scala:872-875` loads the deps before
    * `d.make` runs, and `:608` records the module only on success -- which is what makes the
    * second and later cases of a generated sample cheap.
    *
    * WHY DROPPING THE LOCK IS SOUND, and the ONE THING IT COSTS YOU (S2 review F-5).  Sound
    * because `Session.depCache` is a `ConcurrentHashMap` (`Session.scala:110`), so this unlocked
    * `-=` can neither corrupt it nor race `loadStatements`' locked eviction, and because a
    * `Literal`'s identity IS its module name (`Session.scala:328-341`), which every caller here
    * mints uniquely -- so this path never touches the shared `"Test"` key the lock exists for.
    * What it costs: `literalLock` is also the fence `TestDateAndScan.underZone` takes so that no
    * module load is in flight while it has the JVM DEFAULT TIMEZONE changed.  A `loadNamed` load
    * can be in flight during that window.  It can only change the date VALUES a module computes,
    * never whether it type-checks -- so **assert on VERDICTS here, never on date values**. */
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
    implicit val arbCal: Arbitrary[Cal] = Arbitrary(Arbitrary.arbitrary[java.util.Date] map {(d: java.util.Date) =>
      val c = Cal.getInstance
      c setTimeInMillis d.getTime
      c
    })
    forAll {(dat: Cal, emit: SqlEmitter) =>
      val y = dat get Cal.YEAR
      val m = (dat get Cal.MONTH) + 1
      val d = dat get Cal.DAY_OF_MONTH
      assert((1 to 12) contains m,
             "because I can't keep track of all the off-by-oneness")
      sessionProp(implicit s =>
        com.clarifi.reporting.ermine.surface.SurfaceParsers.expression("<date>", "@%d/%d/%d" format (y, m, d)) match {
          case Right(com.clarifi.reporting.ermine.surface.SLitDate(_, ermineDate)) =>
            // SQL Server wraps the ISO text in CAST(.. AS DATE) since SQL audit E11.
            val iso = "'%d-%02d-%02d'" format (y, m, d)
            (emit emitDate ermineDate run) ?= (if (emit eq SqlEmitter.msSqlEmitter) "CAST(" + iso + " AS DATE)" else iso)
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

  // Concrete and lazy, rather than abstract and overridden in the one
  // implementor: it must be lazy (the properties below run while that object is
  // still being constructed), Scala 3 will not let a lazy val implement a
  // strict val, and an abstract member is not a stable enough path to import
  // from.
  // `final` so it is a legal import path: Scala 3 rejects importing from a
  // non-final lazy value.
  protected final lazy val ermineFixture: ErmineFixture = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
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

  private def proofIn(v: SessionEnv => Any): Prop = sessionProof(v)

  property("all modules load") =
    proofIn(implicit s =>
      loadModules(libraryModules.filterNot(excludedModules).toList))

  property("interesting test modules load") =
    proofIn(implicit s =>
      loadModules(testModules.toList))

  property("all interesting examples load") =
    proofIn{implicit s =>
      sampleModules
        .traverse[[a] =>> String \/ a, SourceFile](mod => sampleRoot.apply(mod) \/> mod)
        .fold(mod => throw Death("example " + mod + " not found"),
              _.foreach(load(_)))}
}

trait StdErmineModules { self: ErmineModulesProperties with Properties =>
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

object TestErmineModules extends Properties("Ermine library")
  with ErmineModulesProperties with StdErmineModules

