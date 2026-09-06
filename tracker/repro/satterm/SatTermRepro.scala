import Replay._
import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.Constraints.GenRules
import com.clarifi.reporting.ermine.Subst.{solve, substType}
import scalaparsers.{Supply, Loc, Located}

/** Partition-level replay of the SATISFIABLE seeds of tracker/PROMPT-satterm (W2, H2, NE6) through
  * the real `Subst.solve`, with exact variable ids and an in-process wall-clock cap.
  *
  * The Lean (`Rowpartition/DefaultTerm.lean`, `TerminatesOnSat`) is FALSE for the additive rule
  * set: from W2 = { p <- (e1, e2, (|k|)), p <- (e2, (|k|)) } a productive run can mint forever
  * (cancellation -> substitution -> split mint, one fresh name per round, "names do not travel
  * with their groups").  This harness asks what the SHIPPED worklist does on the same input:
  * does a `unify:<id>` step on the singleton link `e2 <- (u)`, or an `empty` step once
  * `e1 <- ()` is derived, kill the loop (SOLVED), does something throw (REJECTED), or does it
  * follow the chain (HANG)?
  *
  *   W2:  p <- (e1, e2, (|k|)),  p <- (e2, (|k|))                     ids p e1 e2 = base..base+2, Supply from base+3
  *   H2:  p <- (e1, e2, (|k|)),  q <- (p, s),  q <- (e2, s, (|k|))    ids p e1 e2 q s = base..base+4, Supply from base+5
  *   NE6: loaded from seeds/NE6.json (rowclosure.py seed format: [lhs, [vars], [labels]]);
  *        variable i -> base+i in ascending numeric order, label n -> Global("Repro","l"+n),
  *        RHS = the variables in listed order then the concrete part; Supply from base+#vars
  *   json:<path> any other seed in that format
  *
  * Every run is a fresh `SubstEnv` on a fresh daemon thread; a thread that does not return
  * within the cap is abandoned (it keeps spinning) and the run is a HANG.  `drawn` is the
  * number of fresh ids the run's `Supply` handed out (read back reflectively; for a HANG it is
  * the value at the cap), i.e. an upper bound on the mints, exact when nothing else draws.
  *
  *   SatTermRepro sweep <seed> <from> <to> [capSec=10] [maxHung=6]
  *   SatTermRepro trace <seed> <base> [capSec=10] [nLines=40]      (needs -Dermine.rowTrace=<fresh file>)
  * exit code 3 = the hung-thread limit was reached; the last line names the next base.
  *
  * ANSWER (measured 2026-09-03, README.md next to this file): no seed hangs or is rejected —
  * 1000/1000 bases SOLVED for each of W2, H2, NE6.  W2 mints exactly once and is killed by the
  * `empty` step on `e1 <- ()` followed by the `unify` step on the singleton that erasure leaves
  * (`u <- (e2)`), at 100/100 bases; H2 the same after cancellation derives the hidden
  * `p <- (e2, (|k|))` (2-3 mints); NE6 mints 2-6 ids and ends through `concrete`.  `drawn` is an
  * over-count: `resolution` draws an id for every same-lhs pair of single-variable partitions
  * and discards it when it emits nothing; the fresh ids that appear in `step`/`learn` records
  * are the mints. */
object SatTermRepro {
  def f(s: String): Name = Global("Repro", s)
  val K = Set(f("k"))

  case class Seed(name: String, names: List[String], model: String, build: (String => Type) => List[Type])

  val W2 = Seed("W2", List("p", "e1", "e2"), "p={k,m} e1={} e2={m}", x => List(
    part(x("p"), List(x("e1"), x("e2"), cr(K))),
    part(x("p"), List(x("e2"), cr(K)))))

  val H2 = Seed("H2", List("p", "e1", "e2", "q", "s"), "p={k,m} e1={} e2={m} q={k,m,n} s={n}", x => List(
    part(x("p"), List(x("e1"), x("e2"), cr(K))),
    part(x("q"), List(x("p"), x("s"))),
    part(x("q"), List(x("e2"), x("s"), cr(K)))))

  /* --- rowclosure.py seed files ------------------------------------------------------- */
  object MiniJson {
    sealed trait J
    case class JObj(m: List[(String, J)]) extends J
    case class JArr(a: List[J]) extends J
    case class JStr(s: String) extends J
    case class JNum(n: Double) extends J
    case class JBool(b: Boolean) extends J
    case object JNull extends J
    def parse(s: String): J = { val p = new P(s); val v = p.value(); p.ws(); require(p.i == s.length, "trailing input"); v }
    class P(s: String) {
      var i = 0
      def ws(): Unit = while (i < s.length && s.charAt(i).isWhitespace) i += 1
      def expect(c: Char): Unit = { ws(); require(s.charAt(i) == c, s"expected '$c' at $i"); i += 1 }
      def value(): J = { ws(); s.charAt(i) match {
        case '{' =>
          i += 1; ws()
          if (s.charAt(i) == '}') { i += 1; JObj(Nil) }
          else { var m = List[(String, J)](); var go = true
            while (go) { ws(); val k = str(); expect(':'); val v = value(); m ::= (k -> v); ws()
              if (s.charAt(i) == ',') i += 1 else { expect('}'); go = false } }
            JObj(m.reverse) }
        case '[' =>
          i += 1; ws()
          if (s.charAt(i) == ']') { i += 1; JArr(Nil) }
          else { var a = List[J](); var go = true
            while (go) { a ::= value(); ws(); if (s.charAt(i) == ',') i += 1 else { expect(']'); go = false } }
            JArr(a.reverse) }
        case '"' => JStr(str())
        case 'n' => i += 4; JNull
        case 't' => i += 4; JBool(true)
        case 'f' => i += 5; JBool(false)
        case _   => val st = i; while (i < s.length && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i += 1
                    JNum(s.substring(st, i).toDouble)
      } }
      def str(): String = { ws(); require(s.charAt(i) == '"', s"expected string at $i"); i += 1
        val sb = new StringBuilder
        while (s.charAt(i) != '"') { if (s.charAt(i) == '\\') i += 1; sb += s.charAt(i); i += 1 }
        i += 1; sb.toString }
    }
  }

  def seedFromJson(path: String): Seed = {
    import MiniJson._
    val src = scala.io.Source.fromFile(path)
    val obj = try parse(src.mkString) finally src.close()
    def field(o: J, k: String): Option[J] = o match { case JObj(m) => m.find(_._1 == k).map(_._2); case _ => None }
    def ints(j: J): List[Int] = j match { case JArr(a) => a.map { case JNum(n) => n.toInt; case x => sys.error("not a number: " + x) }; case x => sys.error("not an array: " + x) }
    val cons: List[(Int, List[Int], List[Int])] = field(obj, "cons") match {
      case Some(JArr(cs)) => cs.map { case JArr(List(l, vs, ks)) => (l.asInstanceOf[JNum].n.toInt, ints(vs), ints(ks)); case x => sys.error("bad constraint " + x) }
      case _ => sys.error("no cons")
    }
    val rho: List[(Int, List[Int])] = field(obj, "rho") match {
      case Some(JObj(m)) => m.map { case (k, v) => (k.toInt, ints(v)) }
      case _ => Nil
    }
    val vars = (cons.flatMap { case (l, vs, _) => l :: vs } ++ rho.map(_._1)).distinct.sorted
    val name = field(obj, "name").collect { case JStr(s) => s }.getOrElse(path)
    val model = rho.sortBy(_._1).map { case (v, ls) => "v" + v + "={" + ls.map("l" + _).mkString(",") + "}" }.mkString(" ")
    Seed(name, vars.map("v" + _), model, x => cons.map { case (l, vs, ks) =>
      part(x("v" + l), vs.map(v => x("v" + v)) ++ (if (ks.isEmpty) Nil else List(cr(ks.map(n => f("l" + n)).toSet)))) })
  }

  val seedDir: String = System.getProperty("satterm.seeds", "tracker/repro/satterm/seeds")
  def seed(name: String): Seed = name match {
    case "W2"  => W2
    case "H2"  => H2
    case "NE6" => seedFromJson(seedDir + "/NE6.json").copy(name = "NE6")
    case s if s.startsWith("json:") => seedFromJson(s.drop(5))
    case other => sys.error("unknown seed " + other)
  }

  case class Sys(seed: Seed, base: Int, vars: Map[String, TypeVar], parts: List[Type], supplyLo: Int)

  def system(sd: Seed, base: Int): Sys = {
    val v = sd.names.zipWithIndex.map { case (n, i) => n -> tv(base + i, n) }.toMap
    def x(n: String): Type = vt(v(n))
    Sys(sd, base, v, sd.build(x), base + sd.names.length)
  }

  def showInput(t: Type): String = t match {
    case Part(_, l, rs) =>
      def st(t: Type): String = t match {
        case VarT(v) => v.name.fold("")(_.toString) + "^" + v.id
        case ConcreteRho(_, fs) => "(|" + fs.toList.map(_.toString).sorted.mkString(",") + "|)"
        case x => x.toString }
      st(l) + " <- (" + rs.map(st).mkString(", ") + ")"
    case x => x.toString
  }

  sealed trait Outcome { def drawn: Int }
  case class Solved(ms: Long, types: List[(String, String)], nBound: Int, nResidual: Int, residual: String, drawn: Int) extends Outcome
  case class Rejected(ms: Long, cls: String, msg: String, drawn: Int) extends Outcome
  case class Hang(capMs: Long, drawn: Int, steps: Option[Long], maxId: Option[Int]) extends Outcome

  @volatile var hung = 0
  val tracePath: String = System.getProperty("ermine.rowTrace", "")

  /** How many ids this Supply has handed out since it was created at `lo0`. */
  def drawnOf(su: Supply, lo0: Int): Int = {
    val fld = classOf[Supply].getDeclaredField("lo"); fld.setAccessible(true)
    val lo = fld.getInt(su)
    if (lo < lo0 || lo > lo0 + SupplyWindow) -1 else lo - lo0   // -1: the window was exhausted, count unknown
  }

  /** For a HANG under `-Dermine.rowTrace`: `step` records so far and the largest id in a learn record. */
  def traceStats(site: String): (Option[Long], Option[Int]) =
    if (tracePath.isEmpty) (None, None)
    else try {
      val src = scala.io.Source.fromFile(tracePath)
      var steps = 0L; var maxId = -1
      val idRe = "\\^[a-z()]+(\\d+)".r
      try src.getLines().foreach { ln =>
        if (ln.startsWith("step\t" + site + "\t")) steps += 1
        else if (ln.startsWith("learn\t" + site + "\t"))
          idRe.findAllMatchIn(ln).foreach(m => maxId = maxId max m.group(1).toInt)
      } finally src.close()
      (Some(steps), if (maxId < 0) None else Some(maxId))
    } catch { case _: Throwable => (None, None) }

  def short(s: String): String = s.replace("Repro.", "")

  def runCapped(s: Sys, capMs: Long, site: String): Outcome = {
    @volatile var result: Option[Outcome] = None
    val su: Supply = supplyAt(s.supplyLo)
    val t0 = System.nanoTime
    def ms: Long = (System.nanoTime - t0) / 1000000L
    val th = new Thread(new Runnable { def run(): Unit =
      try {
        implicit val hm: SubstEnv = new SubstEnv()
        implicit val isu: Supply = su
        implicit val tml: Located = Loc.builtin
        val ex: Type = new Exists(Loc.builtin, List(), s.parts) // raw: Exists.apply would reverse + Set-dedup
        val res = RowTrace.withSite(site)(solve(ex))
        val took = ms
        val tys = s.seed.names.map { n =>
          val v = s.vars(n)
          n -> (if (hm.types.contains(v)) short(substType(VarT(v)).toString) else "unbound")
        }
        val (_, _, rcs) = Exists.unfurl(res)
        val nres = rcs.count { case _: Part => true; case _ => false }
        result = Some(Solved(took, tys, hm.types.size, nres, short(res.toString), drawnOf(su, s.supplyLo)))
      } catch { case e: Throwable =>
        result = Some(Rejected(ms, e.getClass.getName, short(String.valueOf(e.getMessage)), drawnOf(su, s.supplyLo)))
      }
    }, site)
    th.setDaemon(true)
    th.start()
    th.join(capMs)
    result.getOrElse {
      hung += 1
      val (st, mx) = traceStats(site)
      Hang(capMs, drawnOf(su, s.supplyLo), st, mx)
    }
  }

  def clip(s: String, n: Int): String = { val t = s.replace('\n', ' '); if (t.length <= n) t else t.take(n) + "..." }

  def show(o: Outcome): String = o match {
    case Solved(ms, tys, n, nr, res, d) =>
      f"SOLVED   in $ms%5d ms  " + tys.map { case (k, v) => k + " := " + v }.mkString("; ") +
        s"  [bound=$n residual=$nr drawn=$d residual=${clip(res, 200)}]"
    case Rejected(ms, cls, msg, d) => f"REJECTED in $ms%5d ms  drawn=$d  $cls: ${clip(msg, 300)}"
    case Hang(cap, d, st, mx) => f"HANG     cap $cap%5d ms  drawn=$d" +
      st.fold("")(x => s"  steps=$x") + mx.fold("")(x => s"  maxId=$x")
  }

  def bucket(o: Outcome): String = o match {
    case _: Solved => "SOLVED"
    case r: Rejected => if (r.cls.contains("OutOfMemoryError")) "OOM" else "REJECTED"
    case _: Hang => "HANG"
  }

  def header(): Unit =
    println("genRules=" + GenRules + "  rowTrace=" + (if (tracePath.isEmpty) "off" else tracePath) +
            "  maxHeap=" + (java.lang.Runtime.getRuntime.maxMemory >> 20) + "M")

  def printInputs(s: Sys): Unit = {
    println("SEED " + s.seed.name + "  model " + s.seed.model)
    s.parts.foreach(p => println("INPUT " + showInput(p)))
  }

  def idRange(s: Sys): String = s"ids ${s.base}..${s.base + s.seed.names.length - 1} supply ${s.supplyLo}%4d"

  def main(args: Array[String]): Unit = {
    header()
    args.toList match {
      case "sweep" :: sdName :: from :: to :: rest =>
        val sd = seed(sdName)
        val capMs   = rest.headOption.map(_.toDouble).getOrElse(10.0) * 1000
        val maxHung = rest.drop(1).headOption.map(_.toInt).getOrElse(6)
        val (lo, hi) = (from.toInt, to.toInt)
        var counts = Map[String, Int]().withDefaultValue(0)
        var msgs   = Map[String, Int]().withDefaultValue(0)
        var drawn  = List[Int]()
        var times  = List[Long]()
        var stopped: Option[Int] = None
        var b = lo
        while (b <= hi && stopped.isEmpty) {
          val s = system(sd, b)
          if (b == lo) printInputs(s)
          val o = runCapped(s, capMs.toLong, sdName + "@" + b)
          val bk = bucket(o)
          counts += bk -> (counts(bk) + 1)
          drawn ::= o.drawn
          o match {
            case r: Rejected => msgs += (r.cls + ": " + r.msg) -> (msgs(r.cls + ": " + r.msg) + 1); times ::= r.ms
            case r: Solved   => times ::= r.ms
            case _ => ()
          }
          println(f"$sdName%-4s base=$b%4d ids $b..${b + sd.names.length - 1} supply ${s.supplyLo}%4d: ${show(o)}")
          if (hung >= maxHung && b < hi) stopped = Some(b + 1)
          b += 1
        }
        println(s"SUMMARY seed=$sdName bases=$lo..${stopped.fold(hi)(_ - 1)} n=${counts.values.sum} " +
                List("SOLVED", "REJECTED", "HANG", "OOM").map(k => k + "=" + counts(k)).mkString(" "))
        msgs.toList.sortBy(-_._2).foreach { case (m, n) => println(s"  x$n  $m") }
        val ds = drawn.sorted
        if (ds.nonEmpty) println(s"DRAWN  min=${ds.head} median=${ds(ds.length / 2)} max=${ds.last}  histogram " +
          ds.groupBy(identity).toList.sortBy(_._1).map { case (k, v) => s"$k:x${v.length}" }.mkString(" "))
        val ts = times.sorted
        if (ts.nonEmpty) println(s"TIME   min=${ts.head} median=${ts(ts.length / 2)} p95=${ts((ts.length * 95) / 100 min (ts.length - 1))} max=${ts.last} ms")
        stopped match {
          case Some(nb) => println(s"HUNGLIMIT hung=$hung next=$nb"); System.exit(3)
          case None => ()
        }

      case "trace" :: sdName :: base :: rest =>
        if (tracePath.isEmpty) { System.err.println("trace: needs -Dermine.rowTrace=<fresh file>"); System.exit(2) }
        val sd = seed(sdName)
        val capMs  = rest.headOption.map(_.toDouble).getOrElse(10.0) * 1000
        val nLines = rest.drop(1).headOption.map(_.toInt).getOrElse(40)
        val b = base.toInt
        val s = system(sd, b)
        printInputs(s)
        val site = sdName + "@" + b
        val o = runCapped(s, capMs.toLong, site)
        println(f"$sdName%-4s base=$b%4d ids $b..${b + sd.names.length - 1} supply ${s.supplyLo}%4d: ${show(o)}")
        // ---- read the trace back ----
        val src = scala.io.Source.fromFile(tracePath)
        val lines = try src.getLines().toList finally src.close()
        val mine = lines.filter(_.split("\t", 3).lift(1).contains(site))
        val steps = mine.filter(_.startsWith("step\t"))
        val learns = mine.filter(_.startsWith("learn\t"))
        val branches = steps.map(_.split("\t")(2))
        def bkind(x: String): String = x.takeWhile(_ != ':')
        val bcounts = branches.groupBy(bkind).map { case (k, v) => k + "=" + v.length }.toList.sorted.mkString(" ")
        val nNew = learns.count(_.split("\t")(2) == "new")
        val byRule = learns.map(_.split("\t")(3).takeWhile(_ != ':')).groupBy(identity).map { case (k, v) => k + "=" + v.length }.toList.sorted.mkString(" ")
        val idRe = "\\^[a-z()]+(\\d+)".r
        val ids = (steps ++ learns).flatMap(l => idRe.findAllMatchIn(l).map(_.group(1).toInt)).distinct.sorted
        val fresh = ids.filter(_ >= s.supplyLo)
        println(s"TRACE  records=${mine.length} steps=${steps.length} ($bcounts) learn=${learns.length} (new=$nNew seen=${learns.length - nNew}) byRule: $byRule")
        println(s"IDS    distinct=${ids.length} input=${ids.count(_ < s.supplyLo)} fresh(minted, in a step/learn record)=${fresh.length} ${fresh.mkString(",")}  supply-drawn=${o.drawn}")
        println("BRANCHES " + branches.mkString(" "))
        val pop = mine.filter(l => l.startsWith("solve\t") || l.startsWith("sat\t") || l.startsWith("inpart\t") || l.startsWith("concr\t") || l.startsWith("splice\t"))
        def strip(l: String): String = { val a = l.split("\t"); (a.take(1) ++ a.drop(2)).mkString("  ") }
        val sl = mine.filter(l => l.startsWith("step\t") || l.startsWith("learn\t"))
        println(s"FIRST ${nLines min sl.length} of ${sl.length} step/learn lines (site column dropped):")
        sl.take(nLines).foreach(l => println("    " + short(strip(l))))
        if (sl.length > nLines) {
          val k = 20 min (sl.length - nLines)
          println(s"LAST $k step/learn lines:")
          sl.takeRight(k).foreach(l => println("    " + short(strip(l))))
        }
        if (pop.nonEmpty) { println("POPULATION records (solve / inpart / sat / concr / splice):"); pop.foreach(l => println("    " + short(strip(l)))) }

      case _ =>
        System.err.println("usage: SatTermRepro sweep <W2|H2|NE6|json:PATH> <from> <to> [capSec] [maxHung]\n" +
                           "       SatTermRepro trace <seed> <base> [capSec] [nLines]   (with -Dermine.rowTrace=<fresh file>)")
        System.exit(2)
    }
  }
}
