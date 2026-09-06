package com.clarifi.reporting
package ermine
package loopmodel

import java.io.File
import org.scalacheck.{Gen, Prop, Properties}
import org.scalacheck.Prop.propBoolean
import org.scalacheck.rng.Seed

/** Stage L4 of `tracker/LOOP-MODEL-PLAN.md`: the Lean loop model and the real row solver,
  * compared record for record, IN `core/test`, so the two cannot drift apart silently.
  *
  * WHAT IS COMPARED.  For every tracked seed file under `tracker/repro/satterm/seeds` at
  * several id bases, and for a sample of randomly generated, SATISFIABLE-BY-CONSTRUCTION
  * systems (`genSystem` below, the shape of `tracker/tools/rowclosure.py`'s `gen_random`),
  * the compiler runs `Subst.solve` with `-Dermine.rowTrace` on and the Lean model replays the
  * resulting trace at the compiler's OWN ids.  The two record streams must be byte identical,
  * segment for segment -- the same comparison `tracker/tools/looptrace-diff.py --segments`
  * makes over the corpus in L2, reimplemented here so the property needs no python.
  *
  * DESIGN CONSTRAINTS, and how each is met.
  *
  *  1. The compiler side is the REAL `Subst.solve` / `Constraints.incorporateAll` path.  It is
  *     driven the way `tracker/repro/satterm/SatTermRepro.scala` drives it: a raw `Exists` over
  *     a constraint list at an exact id base, a fresh `SubstEnv`, no stdlib boot and no module
  *     loading.  Nothing about the solver is stubbed or re-implemented.
  *
  *  2. The trace is taken in a CHILD JVM (`LoopTraceChild`, whose header explains the choice).
  *     `RowTrace.enabled` is a `val` read from a system property once, and `core`'s tests are
  *     NOT forked (`Test / fork := false`), so the property cannot turn tracing on for itself
  *     without either racing `RowTrace`'s initialisation or turning it on for every other
  *     suite's solves as well.  Making `enabled` mutable would put a live read on the solver's
  *     default path, which the instrumentation may not do.  The child is launched with
  *     `java -Dermine.rowTrace=<file> -cp <the classpath this test is running under>`.
  *
  *  3. The Lean side is the `looptrace` executable, `tracker/lean/.lake/build/bin/looptrace`
  *     (override with `-Dermine.looptrace=<path>`), run as `--replay <trace>`.  When it is
  *     absent -- no Lean toolchain, or `lake build looptrace` never run -- both properties
  *     SKIP with a message naming the build command, so `core/test` does not depend on Lean.
  *     When it is present they run in the ordinary `sbt core/test`.
  *
  *  4. A POSITIVE CONTROL.  The second property replays a DOCTORED trace in which every
  *     segment's `Supply` base has been moved by one id, and requires the comparison against
  *     the compiler's real trace to FAIL.  Without it a comparison that silently compared
  *     nothing would still be green.  The control is a wrong id base rather than a flag
  *     difference because it bites on every segment that mints, whatever rules fire.
  *
  *  5. Run time.  Everything expensive happens ONCE for the whole sample: one child JVM for
  *     all the solves, one `looptrace --replay` for the honest comparison and one for the
  *     control.  The per-segment assertions are then pure string comparisons.  Sizes are
  *     `Bases` x the seed files, plus `NGenerated`; see `tracker/loopmodel/L4-TEST.md` for the
  *     measured wall clock.
  *
  * If this property fails after a change to the solver, the change altered the loop's
  * behaviour: either it is wrong, or the Lean model in `tracker/lean/Rowpartition/Loop/` has to
  * be changed with it, and the L2 corpus replay re-run.  See `tracker/lean/README.md`.
  *
  * WHAT IT DOES NOT REACH, measured on the trace the 702 solves actually write, so that nobody
  * reads it as covering more than it does (L4 review, F2).  All five dispatch branches fire
  * (`empty` 818, `concrete` 674, `learn` 619, `unify` 450, `common` 157) and NINE of the
  * sixteen `Constraints.Inference` kinds -- `Substitution` 194, `Cancellation` 189,
  * `SplitConcrete` 121, `CommonSubexpression` 118, `SelfSubstitution` 61, `Resolution` 21,
  * `SplitKeyed` 18, `DeDuplication` 18, `SplitRow` 3.  Under a forwarded flag three more do:
  * `CommonSubexpressionMint` 6 at `-Dermine.genRules=all`, and `SplitEmpty` 12 /
  * `ResolutionEmpty` 4 at `-Dermine.emptyRow=true`.  **`ResolutionRow`, `PartitionEmpty`,
  * `CommonPartition` and `Disjunction` never fire in any configuration of this population** --
  * the corpus does reach `ResolutionRow` (nine times in one `gu05` solve alone), so a change
  * confined to those branches is caught by `tracker/tools/looptrace-corpus.sh`, which is NOT
  * part of `core/test`, and not by this property.  `RR.json` and `RE.json` are in the
  * population and do NOT fire the rules they are named for: at the shipped flags the loop takes
  * the `concrete` branch on their input before any resolution branch is reachable.
  *
  * Two more shapes it does not reach, both covered by L2's corpus instead: no solve here has
  * an EXISTENTIAL (`ex` records: 0), and every input variable is `Free` and named -- no
  * `Skolem`, no `Ambiguous`, and nothing that has been through `.nf`.  And, inherited from L2
  * review F3: both sides are driven by the compiler's own `sin`/`slbl`/`svar`/`scon` records,
  * so this tests the LOOP, not the construction of the loop's input -- a change before
  * `RowTrace.solveInput` moves both sides together and is invisible here.
  *
  * FLAGS.  `-Dermine.*` rule switches ARE forwarded to the child and translated into the
  * model's `--flags` (see `flagMap`), so `sbt -Dermine.emptyRow=true core/test` really does
  * compare that configuration on both sides; a value with no model token is a hard failure
  * rather than a silent fallback to the defaults.  Measured: `emptyRow`, `splitKey=false`,
  * `genRules=all`, `genRules=nongen`, `labelCheck=false`, `labelCheckEarly=false`,
  * `resGuard=false`, `splitRow=false` and `resRow=false` all give 702/702.
  * `-Dermine.disjunction=true` does NOT finish -- the CHILD (the compiler) exceeds the 180 s
  * budget for 702 solves, which is `L2-CORPUS.md` §4c/§10's "a sweep with `Disjunction` on
  * finishes on neither side", and the property now says so instead of passing.
  */
object TestLoopTrace extends Properties("loop model trace") {

  /* ---------------------------------------------------------------- configuration ---- */

  /** Id bases for the tracked seeds.  More than one because the queue is ordered by
    * `rhs.hashCode` and `V.hashCode` IS the id, so the base decides the dequeue order; L1
    * found real disagreements only by sweeping bases. */
  val Bases: List[Int] = List(0, 7, 41, 300, 1234, 65537)

  /** Generated systems.  Sampled once, from a fixed `Seed`, so the property is reproducible
    * and its run time does not depend on how many times ScalaCheck decides to try it. */
  val NGenerated: Int = 600
  val SampleSeed: Long = 20260904L

  val root: File = new File(System.getProperty("user.dir", "."))
  def rel(p: String): File = new File(root, p)

  val seedDir: File = new File(System.getProperty("satterm.seeds", rel("tracker/repro/satterm/seeds").getPath))
  val leanBin: File = new File(System.getProperty("ermine.looptrace",
                                                  rel("tracker/lean/.lake/build/bin/looptrace").getPath))

  /* ------------------------------------------------------------------- the systems ---- */

  /** A system in the `rowclosure.py` / `SatTermRepro` seed shape: the variable indices that
    * receive consecutive ids, and the constraints `lhs <- (group..., (|labels|))`. */
  final case class Sys(name: String, varIds: List[Int], cons: List[(Int, List[Int], List[Int])]) {
    def wire(site: String, base: Int): String =
      site + "\t" + base + "\t" + varIds.mkString(",") + "\t" +
        cons.map { case (l, g, k) => s"$l|${g.mkString(",")}|${k.mkString(",")}" }.mkString(";")
    def nAbstract: Int = cons.map(_._2.length).foldLeft(0)(_ max _)
    def nConcrete: Int = cons.count(_._3.nonEmpty)
  }

  /* --- the tracked seeds ------------------------------------------------------------- */

  /** Just enough JSON for the seed files: `{"rho": {"0": [..]}, "cons": [[l,[v..],[k..]]]}`.
    * The seeds are written by `rowclosure.py`, so the shapes are exactly these. */
  private object MiniJson {
    sealed trait J
    final case class JObj(m: List[(String, J)]) extends J
    final case class JArr(a: List[J]) extends J
    final case class JStr(s: String) extends J
    final case class JNum(n: Double) extends J
    final case class JLit(s: String) extends J

    def parse(s: String): J = { val p = new P(s); val v = p.value(); p.ws(); v }

    final class P(s: String) {
      var i = 0
      def ws(): Unit = while (i < s.length && s.charAt(i).isWhitespace) i += 1
      def value(): J = { ws(); s.charAt(i) match {
        case '{' => i += 1; ws()
          if (s.charAt(i) == '}') { i += 1; JObj(Nil) } else {
            var m = List[(String, J)]()
            var go = true
            while (go) { ws(); val k = str(); ws(); i += 1 /* ':' */; m ::= (k -> value()); ws()
                         if (s.charAt(i) == ',') i += 1 else { i += 1; go = false } }
            JObj(m.reverse) }
        case '[' => i += 1; ws()
          if (s.charAt(i) == ']') { i += 1; JArr(Nil) } else {
            var a = List[J]()
            var go = true
            while (go) { a ::= value(); ws(); if (s.charAt(i) == ',') i += 1 else { i += 1; go = false } }
            JArr(a.reverse) }
        case '"' => JStr(str())
        case 't' => i += 4; JLit("true")
        case 'f' => i += 5; JLit("false")
        case 'n' => i += 4; JLit("null")
        case _   => val st = i
                    while (i < s.length && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i += 1
                    JNum(s.substring(st, i).toDouble)
      } }
      def str(): String = { ws(); i += 1
        val sb = new StringBuilder
        while (s.charAt(i) != '"') { if (s.charAt(i) == '\\') i += 1; sb += s.charAt(i); i += 1 }
        i += 1; sb.toString }
    }
  }

  /** One seed file.  The variable list is every index the constraints or `rho` mention, in
    * ascending order -- `SatTermRepro.seedFromJson`'s rule, so a seed gets the same ids here
    * as it did in the L1 and L2 sweeps. */
  def readSeed(f: File): Sys = {
    import MiniJson._
    val src = scala.io.Source.fromFile(f)
    val obj = try parse(src.mkString) finally src.close()
    def field(k: String): Option[J] = obj match {
      case JObj(m) => m.find(_._1 == k).map(_._2)
      case _       => None
    }
    def ints(j: J): List[Int] = j match {
      case JArr(a) => a.map { case JNum(n) => n.toInt; case x => sys.error("not a number: " + x) }
      case x       => sys.error("not an array: " + x)
    }
    val cons = field("cons") match {
      case Some(JArr(cs)) => cs.map {
        case JArr(List(JNum(l), vs, ks)) => (l.toInt, ints(vs), ints(ks))
        case x => sys.error("bad constraint " + x)
      }
      case _ => sys.error("no cons in " + f)
    }
    val rhoKeys = field("rho") match {
      case Some(JObj(m)) => m.map(_._1.toInt)
      case _             => Nil
    }
    val vars = (cons.flatMap { case (l, vs, _) => l :: vs } ++ rhoKeys).distinct.sorted
    Sys(f.getName.stripSuffix(".json"), vars, cons)
  }

  lazy val seeds: List[Sys] = {
    val fs = Option(seedDir.listFiles).getOrElse(Array[File]())
      .filter(_.getName.endsWith(".json")).sortBy(_.getName).toList
    fs.map(readSeed)
  }

  /* --- generated systems ------------------------------------------------------------- */

  /** `tracker/tools/rowclosure.py`'s `gen_random`, ported: `k` variables with rows drawn from
    * `m` labels (empty and duplicated rows with positive probability), then `n` DISTINCT
    * constraints true under that model -- a concrete part `K` contained in `rho a`, and a
    * group of variables whose rows are pairwise disjoint and partition `rho a - K`, plus
    * empty-row variables added freely.  Satisfiability is by construction and is CHECKED
    * (`satSets`) before a constraint is kept, which is `rowclosure.py`'s own assertion.
    *
    * The coverage this is here for: at least two abstract parts on a right-hand side, real
    * concrete parts, empty rows, duplicate rows and the occasional self-partition
    * `a <- (a, empties)` -- the shapes that make the loop mint, cancel and split. */
  def gen_random(rnd: scala.util.Random, k: Int, m: Int, n: Int): (Map[Int, Set[Int]], List[(Int, List[Int], List[Int])]) = {
    val pEmpty = 0.25; val pDup = 0.25; val pSelf = 0.04; val pFullConc = 0.08
    val labels = (0 until m).toList
    var rho = Map[Int, Set[Int]]()
    var rows = List[Set[Int]]()
    (0 until k).foreach { v =>
      val r = rnd.nextDouble()
      val row =
        if (r < pEmpty) Set[Int]()
        else if (r < pEmpty + pDup && rows.nonEmpty) rows(rnd.nextInt(rows.length))
        else labels.filter(_ => rnd.nextDouble() < 0.55).toSet
      rho += v -> row
      rows = rows :+ row
    }
    var cons = List[(Int, List[Int], List[Int])]()
    var seen = Set[(Int, Set[Int], Set[Int])]()
    var tries = 0
    while (cons.length < n && tries < 60 * n) {
      tries += 1
      val a = rnd.nextInt(k)
      val R = rho(a)
      val empties = (0 until k).filter(v => v != a && rho(v).isEmpty).toList
      val cand: Option[(List[Int], Set[Int])] =
        if (rnd.nextDouble() < pSelf)
          Some((a :: empties.filter(_ => rnd.nextDouble() < 0.5), Set[Int]()))
        else {
          val K = if (rnd.nextDouble() < pFullConc) R else R.filter(_ => rnd.nextDouble() < 0.4)
          val rest = R -- K
          val cands = rnd.shuffle((0 until k).filter(v => v != a && rho(v).nonEmpty && rho(v).subsetOf(rest)).toList)
          var group = List[Int]()
          var remaining = rest
          cands.foreach { v => if (rho(v).subsetOf(remaining)) { group = group :+ v; remaining --= rho(v) } }
          if (remaining.nonEmpty) None
          else Some((group ++ empties.filter(_ => rnd.nextDouble() < 0.35), K))
        }
      cand.foreach { case (group, kk) =>
        val key = (a, group.toSet, kk)
        if (!seen(key) && satSets(rho, a, group, kk)) {
          seen += key
          cons = cons :+ ((a, group.sorted, kk.toList.sorted))
        }
      }
    }
    (rho, cons)
  }

  /** `rowclosure.py`'s `sat_sets`: the parts are pairwise disjoint and their union is the
    * left-hand side's row.  This is what makes a generated system satisfiable BY A MODEL. */
  def satSets(rho: Map[Int, Set[Int]], lhs: Int, vs: List[Int], ks: Set[Int]): Boolean = {
    val parts = ks :: vs.map(rho)
    val union = parts.foldLeft(Set[Int]())(_ ++ _)
    parts.map(_.size).sum == union.size && union == rho(lhs)
  }

  /** A real ScalaCheck generator: the seed decides `k`, `m`, `n` and every draw.  The ranges
    * are the ones L2's 2,000-system sweep used (`rowclosure.py --seeds 2000` defaults). */
  val genSystem: Gen[Sys] = Gen.choose(Int.MinValue, Int.MaxValue).map { s =>
    val rnd = new scala.util.Random(s.toLong)
    val k = 3 + rnd.nextInt(5)          // 3..7
    val m = 2 + rnd.nextInt(3)          // 2..4
    val n = 2 + rnd.nextInt(5)          // 2..6
    val (rho, cons) = gen_random(rnd, k, m, n)
    val vars = (cons.flatMap { case (l, vs, _) => l :: vs } ++ rho.keys).distinct.sorted
    Sys("gen%d-k%dm%dn%d".format(s, k, m, n), vars, cons)
  }

  /** The sample, drawn once with a fixed seed.  Systems with no constraints are dropped:
    * `gen_random` can fail to place any, and a solve of nothing tests nothing. */
  lazy val generated: List[Sys] = {
    val p = Gen.Parameters.default
    val out = List.newBuilder[Sys]
    var s = Seed(SampleSeed)
    var i = 0
    var guard = 0
    while (i < NGenerated && guard < NGenerated * 20) {
      guard += 1
      genSystem.pureApply(p, s, retries = 1) match {
        case sy if sy.cons.nonEmpty => out += sy; i += 1
        case _ => ()
      }
      s = s.next
    }
    out.result()
  }

  /* --------------------------------------------------------------- running the sides ---- */

  /** The classpath this test is running under.  `Test / fork := false`, so
    * `java.class.path` is sbt's own launcher and useless; the real classpath is in the test
    * classloader chain (sbt's layered loaders are `URLClassLoader`s).  Three code sources are
    * added explicitly as well -- `LoopTraceChild`'s (the test classes), `RowTrace`'s (the
    * compiler) and `Supply`'s (the `parsers` module) -- so the child still finds everything it
    * needs if sbt's loader ever stops being a `URLClassLoader`. */
  def childClasspath(): List[String] = {
    val seen = scala.collection.mutable.LinkedHashSet[String]()
    def add(u: java.net.URL): Unit =
      try { seen += new File(u.toURI).getAbsolutePath } catch { case _: Throwable => () }
    def addOf(c: Class[_]): Unit =
      try add(c.getProtectionDomain.getCodeSource.getLocation) catch { case _: Throwable => () }
    addOf(LoopTraceChild.getClass)
    addOf(RowTrace.getClass)
    addOf(classOf[scalaparsers.Supply])
    var cl: ClassLoader = getClass.getClassLoader
    while (cl != null) {
      cl match { case u: java.net.URLClassLoader => u.getURLs.foreach(add); case _ => () }
      cl = cl.getParent
    }
    System.getProperty("java.class.path", "").split(File.pathSeparator)
      .filter(_.nonEmpty).foreach(p => seen += new File(p).getAbsolutePath)
    seen.toList.filter(p => new File(p).exists)
  }

  /* ------------------------------------------------------------------ the rule flags ---- */

  /** The solver's rule switches, and the `looptrace --flags=` token that means the same thing.
    *
    * Both sides must be told, or the comparison is between two different rule sets and every
    * segment disagrees.  Without this the property always ran the SHIPPED defaults on both
    * sides -- correct, but it meant `sbt -Dermine.emptyRow=true core/test` silently tested the
    * default configuration instead of the one asked for (L4 review, F2/§3b).  Now the property
    * FORWARDS whatever `-Dermine.*` the run was given to the child JVM and passes the matching
    * `--flags` to the model.
    *
    * `ermine.genRules` is a mode rather than a boolean (`Constraints.scala:768`), so it maps
    * value by value.  A value neither side knows is a hard error, not a silent default: it
    * would make the two sides disagree everywhere for a reason that has nothing to do with the
    * solver. */
  val flagMap: List[(String, String, String)] = List(
    // property,                 value that is NOT the default,  model token
    ("ermine.genRules",          "all",     "all"),
    ("ermine.genRules",          "cut",     "cut"),
    ("ermine.genRules",          "nongen",  "nongen"),
    ("ermine.disjunction",       "true",    "disj"),
    ("ermine.labelCheck",        "false",   "nolabel"),
    ("ermine.labelCheckEarly",   "false",   "lateLabel"),
    ("ermine.resGuard",          "false",   "noresguard"),
    ("ermine.splitKey",          "false",   "nosplitkey"),
    ("ermine.splitRow",          "false",   "nosplitrow"),
    ("ermine.resRow",            "false",   "noresrow"),
    ("ermine.emptyRow",          "true",    "emptyrow"),
    // S2 (`tracker/loopmodel/S2-DESIGN.md`), all DEFAULT OFF on both sides.  The master
    // `-Dermine.rowSound` turns the three layers on together, and each is separately
    // switchable, so each maps to its own model token (`Loop/Main.lean`'s `applyFlag`).
    ("ermine.rowSound",            "true",  "rowsound"),
    ("ermine.rowSound.bare",       "true",  "rsbare"),
    ("ermine.rowSound.bare",       "false", "norsbare"),
    ("ermine.rowSound.saturated",  "true",  "rssat"),
    ("ermine.rowSound.saturated",  "false", "norssat"),
    ("ermine.rowSound.decide",     "true",  "rsdecide"),
    ("ermine.rowSound.decide",     "false", "norsdecide"))

  /** The NUMERIC S2 switches, which `flagMap`'s value-by-value shape cannot express: any
    * value maps to `<token>=<value>` (S2 review V-3 -- `-Dermine.rowSound.budget` used to be
    * in neither `setFlags` nor the `bad` check, so
    * `sbt -Dermine.rowSound.budget=1 "core/testOnly *TestLoopTrace"` ran the compiler at
    * budget 1 and the model at 200 000, silently). */
  val numericFlags: List[(String, String)] = List(
    ("ermine.rowSound.budget",      "rsbudget"),
    ("ermine.rowSound.solveBudget", "rssolvebudget"))

  /** The numeric `-Dermine.*` this JVM was given. */
  val setNumeric: List[(String, String)] =
    numericFlags.map(_._1).flatMap { k =>
      Option(System.getProperty(k)).filter(_.nonEmpty).map(k -> _)
    }

  /** The `-Dermine.*` this JVM was given, in the order `flagMap` lists them. */
  val setFlags: List[(String, String)] =
    flagMap.map(_._1).distinct.flatMap { k =>
      Option(System.getProperty(k)).filter(_.nonEmpty).map(k -> _)
    }

  /** `Left` when a value has no model token; otherwise the model's `--flags` tokens. */
  val modelFlags: Either[String, List[String]] = {
    val bad = setFlags.filterNot { case (k, v) =>
      flagMap.exists { case (k2, v2, _) => k2 == k && v2 == v } ||
        // the value that IS the default needs no token
        (k, v) == ("ermine.disjunction", "false") || (k, v) == ("ermine.labelCheck", "true") ||
        (k, v) == ("ermine.labelCheckEarly", "true") || (k, v) == ("ermine.resGuard", "true") ||
        (k, v) == ("ermine.splitKey", "true") || (k, v) == ("ermine.splitRow", "true") ||
        (k, v) == ("ermine.resRow", "true") || (k, v) == ("ermine.emptyRow", "false") ||
        (k, v) == ("ermine.rowSound", "false")
    }
    if (bad.nonEmpty)
      Left("no `looptrace --flags` token is known for " +
           bad.map { case (k, v) => "-D" + k + "=" + v }.mkString(", ") +
           "; add it to TestLoopTrace.flagMap (and to Loop/Main.lean's applyFlag) before " +
           "running the property under that setting")
    else Right(setFlags.flatMap { case (k, v) =>
      flagMap.collectFirst { case (k2, v2, tok) if k2 == k && v2 == v => tok } } ++
      setNumeric.flatMap { case (k, v) =>
        numericFlags.collectFirst { case (k2, tok) if k2 == k => tok + "=" + v } })
  }

  /** D1's two switches.  They are NOT `--flags` tokens: `-Dermine.dequeuePolicy` and
    * `-Dermine.solveBudget` are read by the LOOP DRIVER, not by any rule, and the model
    * mirrors that with its own `--policy=` / `--budget=` options rather than with a field on
    * `GenRules`/`Flags`.  `--trace` forces the model's RECORD path, because `--policy=` alone
    * selects its `pol` census.  Forwarded here for the same reason S2 review V-3 made the
    * numeric flags forwarded: otherwise `sbt -Dermine.dequeuePolicy=smallcanon
    * "core/testOnly *TestLoopTrace"` would run the compiler under the policy and the model
    * under the shipped order, and the property would fail for a reason that is not a bug. */
  val setD1: List[(String, String)] =
    List("ermine.dequeuePolicy" -> "shipped", "ermine.solveBudget" -> "0").flatMap {
      case (k, off) => Option(System.getProperty(k)).filter(_.nonEmpty).filter(_ != off).map(k -> _)
    }

  val d1Opts: List[String] = {
    val opts = setD1.map {
      case ("ermine.dequeuePolicy", v) => "--policy=" + v
      case (_, v)                      => "--budget=" + v
    }
    if (opts.isEmpty) Nil else opts :+ "--trace"
  }

  /** `--flags=a,b` for the model, or nothing when the run is at the shipped defaults; plus
    * D1's `--policy=` / `--budget=` / `--trace` when they are set. */
  def flagArgs(extra: List[String]): List[String] = (modelFlags match {
    case Right(ts) if (ts ++ extra).nonEmpty => List("--flags=" + (ts ++ extra).mkString(","))
    case _                                   => Nil
  }) ++ d1Opts

  /** The rule-set injection for the positive control.  `nongen` normally, but if the run is
    * ALREADY at `nongen` that would be no injection at all, so use `all` instead. */
  def controlToken: String =
    if (modelFlags.fold(_ => Nil, identity).contains("nongen")) "all" else "nongen"

  /** Run a command, capturing stdout and stderr; `None` on timeout. */
  def run(cmd: List[String], out: File, timeoutMs: Long): Option[(Int, String)] = {
    val pb = new ProcessBuilder(cmd: _*)
    pb.directory(root)
    pb.redirectOutput(out)
    pb.redirectErrorStream(true)
    val p = pb.start()
    p.getOutputStream.close()
    if (!p.waitFor(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)) {
      p.destroyForcibly(); p.waitFor(); None
    } else {
      val txt = try scala.io.Source.fromFile(out).mkString.take(4000) catch { case _: Throwable => "" }
      Some((p.exitValue, txt))
    }
  }

  /* ------------------------------------------------------------------ the comparison ---- */

  /** Record types the model produces; the rest of the trace (`concr`, `splice`, `ex`, and the
    * `sin`/`slbl`/`svar`/`scon` replay input) is not part of the comparison.  Same list as
    * `tracker/tools/looptrace-diff.py`'s `KEEP`. */
  val Keep = Set("step", "learn", "in", "inpart", "sat", "solve")

  /** `sin site loc suLo suHi nCs blk bsz nRows` is nine fields; a tenth is L4's thread id. */
  val SinFields = 9

  final case class Seg(site: String, loc: String, recs: Vector[String])

  /** The compiler side, split at `sin`, with the thread-id column dropped (the model emits
    * none).  Records are attached to the open segment OF THEIR OWN THREAD, exactly as
    * `looptrace-diff.py --segments` now does; `LoopTraceChild` is single-threaded, so here
    * that is the same as splitting the file. */
  def scalaSegments(f: File): Vector[Seg] = {
    val src = scala.io.Source.fromFile(f)
    try {
      val segs = Vector.newBuilder[Seg]
      var recs = Vector.newBuilder[String]
      var open: Option[(String, String)] = None
      var tidCol: Option[Boolean] = None
      def close(): Unit = open.foreach { case (s, l) => segs += Seg(s, l, recs.result()) }
      src.getLines().foreach { ln0 =>
        val cols = ln0.split("\t", -1)
        val k = cols(0)
        if (k == "sin" || Keep(k)) {
          if (tidCol.isEmpty && k == "sin") tidCol = Some(cols.length > SinFields)
          val tc = tidCol.getOrElse(false)
          val ln = if (tc) ln0.substring(0, ln0.lastIndexOf('\t')) else ln0
          if (k == "sin") {
            close()
            recs = Vector.newBuilder[String]
            open = Some((cols.lift(1).getOrElse("?"), cols.lift(2).getOrElse("-")))
          } else if (open.isDefined) recs += ln
        }
      }
      close()
      segs.result()
    } finally src.close()
  }

  final case class LeanSeg(site: String, loc: String, recs: Vector[String], note: Option[String],
                           hashdiff: Int, eqdiff: Int)

  /** `looptrace --replay`'s output, split at its `#seg` markers. */
  def leanSegments(f: File): (Vector[LeanSeg], String) = {
    val src = scala.io.Source.fromFile(f)
    try {
      val segs = Vector.newBuilder[LeanSeg]
      var cur: Option[LeanSeg] = None
      var recs = Vector.newBuilder[String]
      var summary = ""
      def close(): Unit = cur.foreach(c => segs += c.copy(recs = recs.result()))
      src.getLines().foreach { ln =>
        val cols = ln.split("\t", -1)
        cols(0) match {
          case "#seg" =>
            close(); recs = Vector.newBuilder[String]
            cur = Some(LeanSeg(cols.lift(2).getOrElse("?"), cols.lift(3).getOrElse("-"),
                               Vector(), None, 0, 0))
          case "#skip"     => cur = cur.map(_.copy(note = Some("skip: " + cols.lift(2).getOrElse("?"))))
          case "#REJECTED" => cur = cur.map(_.copy(note = Some("REJECTED: " + cols.lift(2).getOrElse(""))))
          case "#FUEL"     => cur = cur.map(_.copy(note = Some("FUEL: " + cols.lift(2).getOrElse(""))))
          case "#hashdiff" => cur = cur.map(_.copy(hashdiff = cols.lift(2).flatMap(_.toIntOption).getOrElse(1)))
          case "#eqdiff"   => cur = cur.map(_.copy(eqdiff = cols.lift(2).flatMap(_.toIntOption).getOrElse(1)))
          case "#summary"  => summary = ln
          case k if Keep(k) && cur.isDefined => recs += ln
          case _ => ()
        }
      }
      close()
      (segs.result(), summary)
    } finally src.close()
  }

  /** `None` when the pair agrees, otherwise the class and the first differing pair. */
  def classify(lean: Vector[String], scala0: Vector[String]): Option[(String, Int, String, String)] = {
    val n = lean.length min scala0.length
    var i = 0
    var r: Option[(String, Int, String, String)] = None
    while (i < n && r.isEmpty) {
      if (lean(i) != scala0(i)) r = Some((lean(i).split("\t", -1)(0), i, lean(i), scala0(i)))
      i += 1
    }
    r.orElse {
      if (lean.length == scala0.length) None
      else if (lean.length > scala0.length) Some(("length+", n, lean(n), "<none>"))
      else Some(("length-", n, "<none>", scala0(n)))
    }
  }

  final case class Cmp(nScala: Int, nLean: Int, agree: Int,
                       bad: Vector[(Int, String, String, String, String)], summary: String) {
    def ok: Boolean = bad.isEmpty && nScala == nLean && nScala > 0
    def show: String =
      "segments scala=%d lean=%d agree=%d bad=%d\n%s".format(
        nScala, nLean, agree, bad.length,
        bad.take(4).map { case (i, site, cls, a, b) =>
          "  [%s] seg %d %s\n    lean : %s\n    scala: %s".format(cls, i, site, a, b) }.mkString("\n"))
  }

  def compare(leanOut: File, scalaTrace: File): Cmp = {
    val sc = scalaSegments(scalaTrace)
    val (ln, summary) = leanSegments(leanOut)
    val n = sc.length min ln.length
    var agree = 0
    val bad = Vector.newBuilder[(Int, String, String, String, String)]
    (0 until n).foreach { i =>
      val l = ln(i)
      if (l.note.exists(n => n.startsWith("skip") || n.startsWith("FUEL")))
        // `skip`: the model could not reconstruct the system from the replay records.
        // `FUEL`: it ran out of fuel mid-solve.  Neither is a comparison; both are failures.
        bad += ((i, sc(i).site, if (l.note.exists(_.startsWith("skip"))) "SKIP" else "FUEL",
                 l.note.getOrElse(""), ""))
      else if (l.hashdiff > 0 || l.eqdiff > 0)
        bad += ((i, sc(i).site, "hash/eqdiff", "hashdiff=" + l.hashdiff + " eqdiff=" + l.eqdiff, ""))
      else classify(l.recs, sc(i).recs) match {
        case None => agree += 1
        case Some((cls, _, a, b)) => bad += ((i, sc(i).site, cls, a, b))
      }
    }
    Cmp(sc.length, ln.length, agree, bad.result(), summary)
  }

  /* ------------------------------------------------------------------- the one setup ---- */

  final case class Setup(jobs: Vector[(String, Sys, Int)], trace: File, honest: Cmp,
                         control: Cmp, controlFlags: Cmp, childOut: String, ms: Long,
                         nMints: Int)

  /** A reason the comparison did not happen.  `skip` is TRUE for exactly one of them -- the
    * Lean model executable is not built -- and FALSE for every other, because every other is a
    * failure of this side of the test and must FALSIFY, not pass.
    *
    * This distinction is the whole difference between a regression test and a decoration.  The
    * case that decides it is the child JVM's TIMEOUT: a solver change that makes
    * `incorporateAll` diverge -- the exact failure this programme exists to study -- makes the
    * child run forever, and a property that answered "proved" to that would be green precisely
    * when the solver is broken.  The same goes for a child that crashes, a child that writes
    * no trace, an empty population, and anything the `catch` below sees. (L4 review, F1.) */
  final case class NoRun(skip: Boolean, why: String)

  def fail(why: String): Left[NoRun, Setup] = Left(NoRun(skip = false, why))

  /** Everything expensive, done once: write the jobs, run one child JVM, replay the trace
    * three times (honest, wrong-id-base control, wrong-flags control) and compare each. */
  lazy val setup: Either[NoRun, Setup] = {
    if (!leanBin.canExecute)
      Left(NoRun(skip = true,
           "the Lean model executable is absent (" + leanBin.getPath +
           "); build it with `cd tracker/lean && lake build looptrace`, or point " +
           "-Dermine.looptrace at it. `lake` itself is only needed for that build."))
    else if (seeds.isEmpty && generated.isEmpty)
      fail("the population is EMPTY: no seed files under " + seedDir.getPath +
           " and no generated systems")
    else if (modelFlags.isLeft)
      fail(modelFlags.swap.getOrElse(""))
    else try {
      val t0 = System.nanoTime
      val dir = java.nio.file.Files.createTempDirectory("looptrace-test").toFile
      // Kept only for a post-mortem: `-Dermine.looptrace.keep=true` leaves the trace, the
      // doctored trace and the three model outputs behind for `looptrace-diff.py`.
      if (System.getProperty("ermine.looptrace.keep", "").isEmpty)
        _root_.java.lang.Runtime.getRuntime.addShutdownHook(new Thread(new Runnable { def run(): Unit = {
          def rm(f: File): Unit = {
            if (f.isDirectory) Option(f.listFiles).foreach(_.foreach(rm))
            f.delete(); ()
          }
          rm(dir)
        }}))
      else println("[loop model trace] scratch kept in " + dir.getPath)
      val jobs = (for { s <- seeds; b <- Bases } yield (s.name + "@" + b, s, b)).toVector ++
                 generated.zipWithIndex.map { case (s, i) => (s.name + "@" + (i % 40), s, i % 40) }
      val jobFile = new File(dir, "jobs.tsv")
      val w = new java.io.PrintWriter(jobFile)
      try jobs.foreach { case (site, s, b) => w.println(s.wire(site, b)) } finally w.close()

      val trace = new File(dir, "trace.tsv")
      val childLog = new File(dir, "child.out")
      val javaExe = new File(new File(System.getProperty("java.home"), "bin"), "java").getPath
      val cp = childClasspath().mkString(File.pathSeparator)
      // `setD1` must be forwarded to the CHILD as well, not only translated into the model's
      // `--policy=` / `--budget=`: without it the compiler side runs at the shipped order while
      // the model side runs under the policy, and the property fails on 419 of 714 segments for
      // a reason that is not a bug in either.
      val cmd = List(javaExe, "-Xmx1g", "-Dermine.rowTrace=" + trace.getPath) ++
                (setFlags ++ setNumeric ++ setD1).map { case (k, v) => "-D" + k + "=" + v } ++
                List("-cp", cp,
                     "com.clarifi.reporting.ermine.loopmodel.LoopTraceChild", jobFile.getPath)
      if ((setFlags ++ setNumeric ++ setD1).nonEmpty)
        println("[loop model trace] flags forwarded to both sides: " +
                (setFlags ++ setNumeric ++ setD1).map { case (k, v) => "-D" + k + "=" + v }.mkString(" ") +
                "  ->  " + flagArgs(Nil).mkString(" "))
      val childRc = run(cmd, childLog, 180000)
      val childOut = childRc.map(_._2).getOrElse("<timed out>")
      if (childRc.isEmpty)
        fail("the tracing child JVM did NOT FINISH " + jobs.length + " solves in 180 s. The " +
             "likely cause is a solve that does not terminate, which is exactly what this " +
             "property exists to catch. Rule flags in force: " +
             (if ((setFlags ++ setNumeric).isEmpty) "the shipped defaults"
              else (setFlags ++ setNumeric).map { case (k, v) => "-D" + k + "=" + v }.mkString(" ")) +
             ". (`-Dermine.disjunction=true` is KNOWN not to finish here, on this side and on " +
             "the model's: `L2-CORPUS.md` §4c/§10 covers `Disjunction` by seeds only.)\n" +
             childOut)
      else if (childRc.get._1 != 0)
        fail("the tracing child JVM exited " + childRc.get._1 + ":\n" + childOut)
      else if (!trace.isFile || trace.length == 0)
        fail("the child JVM wrote no trace (is `-Dermine.rowTrace` still honoured?):\n" + childOut)
      else {
        def replay(t: File, flags: List[String], tag: String): Cmp = {
          val o = new File(dir, "model-" + tag + ".out")
          run(leanBin.getPath :: "--replay" :: t.getPath :: flags, o, 180000) match {
            case None    => Cmp(0, 0, 0, Vector((0, tag, "TIMEOUT", "", "")), "")
            case Some(_) => compare(o, trace)
          }
        }
        // The positive control: the same trace with every segment's `Supply` base moved by
        // one.  The compiler's records are unchanged, so any segment that MINTS must now
        // disagree; a comparison that could not detect that would be worthless.
        val doctored = new File(dir, "trace-shifted.tsv")
        val dw = new java.io.PrintWriter(doctored)
        try {
          val src = scala.io.Source.fromFile(trace)
          try src.getLines().foreach { ln =>
            val c = ln.split("\t", -1)
            if (c(0) == "sin" && c.length > 4) {
              c(3) = (c(3).toInt + 1).toString
              c(4) = (c(4).toInt + 1).toString
              dw.println(c.mkString("\t"))
            } else dw.println(ln)
          } finally src.close()
        } finally dw.close()

        val honest = replay(trace, flagArgs(Nil), "honest")
        val control = replay(doctored, flagArgs(Nil), "shifted")
        val controlFlags = replay(trace, flagArgs(List(controlToken)), "flags")
        /* How many records mention a MINTED variable.  A mint prints as
         * `^ambiguous(free)<id>` (`Partition.toString`), and it is the only thing the id-base
         * injection can move: a solve that derives nothing draws no id from the `Supply`, so
         * shifting the `Supply` leaves its records identical.  The control property uses this
         * to know whether that injection has any power in the configuration being run --
         * under `-Dermine.genRules=nongen` no rule mints at all, and it has none. */
        val nMints = {
          val src = scala.io.Source.fromFile(trace)
          try src.getLines().count(_.contains("^ambiguous(free)")) finally src.close()
        }
        Right(Setup(jobs, trace, honest, control, controlFlags, childOut,
                    (System.nanoTime - t0) / 1000000L, nMints))
      }
    } catch {
      case e: Throwable =>
        fail("the comparison could not be set up: " + e + "\n" +
             e.getStackTrace.take(6).map("    at " + _).mkString("\n"))
    }
  }

  /** What to do when `setup` produced no comparison.
    *
    * ScalaCheck has no "skipped", so a genuine skip -- the Lean model executable is not built,
    * the ONE case in which this property has nothing to say -- is a PROVED property (one
    * evaluation, not a hundred) that announces itself on stdout, where sbt's test log shows it.
    * Everything else is FALSIFIED with the reason: a comparison that did not happen because
    * this side broke is not evidence that the two sides agree. */
  def notRun(n: NoRun): Prop =
    if (n.skip) {
      println("[loop model trace] SKIPPED: " + n.why)
      Prop.proved
    } else {
      println("[loop model trace] FAILED, no comparison was made: " + n.why)
      Prop.falsified :| ("the trace property could not run, so nothing was compared: " + n.why)
    }

  /* ---------------------------------------------------------------------- properties ---- */

  /** `-Dermine.looptrace.inject=idbase|nongen` makes the FIRST property compare the INJECTED
    * replay instead of the honest one, so it fails.  That is how the positive control is
    * demonstrated end to end: the second property asserts that the injected comparison is not
    * clean, and this switch shows what the first property's failure looks like when it is not.
    * Unset -- which is always, in an ordinary `core/test` -- it changes nothing. */
  val inject: String = System.getProperty("ermine.looptrace.inject", "")

  property("the Lean loop model reproduces the compiler's trace, segment for segment") =
    setup match {
      case Left(n) => notRun(n)
      case Right(s) =>
        val c = inject match {
          case "idbase" => println("[loop model trace] INJECTION: idbase"); s.control
          case "nongen" => println("[loop model trace] INJECTION: " + controlToken); s.controlFlags
          case _        => s.honest
        }
        println("[loop model trace] %d solves (%d seed x %d bases + %d generated); %d segments; %d agree; %d ms; %s"
                  .format(s.jobs.length, seeds.length, Bases.length, generated.length,
                          c.nScala, c.agree, s.ms, c.summary))
        (propBoolean(c.nScala == s.jobs.length) :| ("one segment per job, got " + c.nScala +
             " for " + s.jobs.length + " jobs\n" + s.childOut)) &&
        (propBoolean(c.nScala == c.nLean) :| ("segment COUNT differs: " + c.show)) &&
        (propBoolean(c.bad.isEmpty) :| ("model and compiler disagree:\n" + c.show)) &&
        (propBoolean(c.agree == c.nScala) :| ("not every segment agreed:\n" + c.show)) &&
        // Belt and braces: the model's own tally, read off its `#summary` line, must say the
        // same thing the per-segment comparison does (L4 review, F5).
        (propBoolean(c.summary.contains("skipped=0") && c.summary.contains("fuel=0")) :|
           ("the model's own summary reports skipped/fuel segments: " + c.summary))
    }

  property("positive control: an injected divergence IS detected") =
    setup match {
      case Left(n) => notRun(n)
      case Right(s) =>
        println("[loop model trace] control (id base +1): %d of %d segments disagree (%d records mint); control (--flags=%s): %d of %d"
                  .format(s.control.bad.length, s.control.nScala, s.nMints, controlToken,
                          s.controlFlags.bad.length, s.controlFlags.nScala))
        // The id-base injection can only move a MINTED id, so it has power exactly when the
        // configuration mints.  `-Dermine.genRules=nongen` turns every minting rule off, and
        // then this injection is not a control at all -- asserting it would be asserting
        // something false.  The rule-set injection below is asserted unconditionally.
        (propBoolean(s.nMints == 0 || s.control.bad.nonEmpty) :|
           ("the id-base injection was NOT detected although " + s.nMints +
            " records mint: the comparison still reports " + s.control.agree + "/" +
            s.control.nScala + " agreeing, so it proves nothing")) &&
        (propBoolean(s.nMints == 0 || !s.control.ok) :| "the doctored replay compared clean") &&
        (propBoolean(s.controlFlags.bad.nonEmpty) :|
           ("the rule-set injection (--flags=" + controlToken + ") was NOT detected: " +
            s.controlFlags.agree + "/" + s.controlFlags.nScala + " agreeing"))
    }

  property("the generated systems really are satisfiable, and cover the shapes L4 needs") = {
    val gs = generated
    (propBoolean(gs.length == NGenerated) :| ("sampled " + gs.length + " of " + NGenerated)) &&
    (propBoolean(gs.forall(_.cons.nonEmpty)) :| "a generated system has no constraints") &&
    (propBoolean(gs.count(_.nAbstract >= 2) >= gs.length / 10) :|
       ("only " + gs.count(_.nAbstract >= 2) + " of " + gs.length +
        " systems have a right-hand side with two or more abstract parts")) &&
    (propBoolean(gs.count(_.nConcrete > 0) >= gs.length / 10) :|
       ("only " + gs.count(_.nConcrete > 0) + " of " + gs.length + " systems have a concrete part"))
  }
}
