import Replay._
import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.Constraints.GenRules
import com.clarifi.reporting.ermine.Subst.solve
import scalaparsers.{Supply, Loc, Located}

/** Partition-level replay of the Lean witness W (tracker/lean/Rowpartition/ResGuardDiverge.lean's
  * gSeed, hidden behind two folds) through the real `Subst.solve`, with exact variable ids and
  * an in-process wall-clock cap.
  *
  *   W:  a  <- (p, (|l1|))          b  <- (q, (|l4|))
  *       w2 <- (a, s2)              w2 <- (q1, q2, s2, (|l2|))      q <- (q1, q2)
  *       w3 <- (b, s3)              w3 <- (p1, p2, s3, (|l3|))      p <- (p1, p2)
  *
  * ids: a b p q p1 p2 q1 q2 w2 s2 w3 s3 = base .. base+11, Supply from base+12.
  * Every run is a fresh `SubstEnv` on a fresh daemon thread; a thread that does not
  * return within the cap is abandoned (it keeps spinning) and the run is a HANG.
  *
  *   CRuleRepro sweep <sys> <from> <to> [capSec=10] [maxHung=6]
  *   sys = W | gseed | G4 | Wsat
  * exit code 3 = the hung-thread limit was reached; the last line names the next base. */
object CRuleRepro {
  def f(s: String): Name = Global("Repro", s)
  val l1 = Set(f("l1")); val l2 = Set(f("l2")); val l3 = Set(f("l3")); val l4 = Set(f("l4"))
  val names = List("a", "b", "p", "q", "p1", "p2", "q1", "q2", "w2", "s2", "w3", "s3")

  case class Sys(name: String, base: Int, vars: Map[String, TypeVar], parts: List[Type], supplyLo: Int)

  def mkVars(base: Int): Map[String, TypeVar] =
    names.zipWithIndex.map { case (n, i) => n -> tv(base + i, n) }.toMap

  /** W, in the exact RHS order of the brief. */
  def wParts(x: String => Type): List[Type] = List(
    part(x("a"),  List(x("p"), cr(l1))),
    part(x("b"),  List(x("q"), cr(l4))),
    part(x("w2"), List(x("a"), x("s2"))),
    part(x("w2"), List(x("q1"), x("q2"), x("s2"), cr(l2))),
    part(x("q"),  List(x("q1"), x("q2"))),
    part(x("w3"), List(x("b"), x("s3"))),
    part(x("w3"), List(x("p1"), x("p2"), x("s3"), cr(l3))),
    part(x("p"),  List(x("p1"), x("p2"))))

  /** gSeed: the four-constraint gadget of ResGuardDiverge.lean, on a b p q. */
  def gseedParts(x: String => Type): List[Type] = List(
    part(x("a"), List(x("p"), cr(l1))),
    part(x("a"), List(x("q"), cr(l2))),
    part(x("b"), List(x("p"), cr(l3))),
    part(x("b"), List(x("q"), cr(l4))))

  /** G4: W plus the four additive consequences the Lean derives (fold + cancellation). */
  def g4Parts(x: String => Type): List[Type] = wParts(x) ++ List(
    part(x("a"),  List(x("q"), cr(l2))),
    part(x("b"),  List(x("p"), cr(l3))),
    part(x("w2"), List(x("q"), x("s2"), cr(l2))),
    part(x("w3"), List(x("p"), x("s3"), cr(l3))))

  /** Wsat: W without b <- (q, (|l4|)); satisfiable. */
  def wsatParts(x: String => Type): List[Type] = wParts(x).filterNot {
    case Part(_, VarT(v), _) => v.name == Some(Local("b")); case _ => false }

  def system(name: String, base: Int): Sys = {
    val v = mkVars(base); def x(n: String): Type = vt(v(n))
    val ps = name match {
      case "W"     => wParts(x)
      case "gseed" => gseedParts(x)
      case "G4"    => g4Parts(x)
      case "Wsat"  => wsatParts(x)
      case other   => sys.error("unknown system " + other)
    }
    Sys(name, base, v, ps, base + 12)
  }

  sealed trait Outcome
  case class Solved(ms: Long, types: List[(String, String)], nBound: Int, residual: String) extends Outcome
  case class Rejected(ms: Long, cls: String, msg: String) extends Outcome
  case class Hang(capMs: Long, steps: Option[Long], maxId: Option[Int]) extends Outcome

  @volatile var hung = 0
  val tracePath: String = System.getProperty("ermine.rowTrace", "")

  /** For a HANG under `-Dermine.rowTrace`: how many `step` records this site wrote so far, and
    * the largest variable id mentioned in a `learn` record (a growing id = the mint loop). */
  def traceStats(site: String): (Option[Long], Option[Int]) =
    if (tracePath.isEmpty) (None, None)
    else try {
      val src = scala.io.Source.fromFile(tracePath)
      var steps = 0L; var maxId = -1
      val idRe = "\\^[a-z()]+(\\d+)".r  // pvar prints ^free12 / ^ambiguous(free)12
      try src.getLines().foreach { ln =>
        if (ln.startsWith("step\t" + site + "\t")) steps += 1
        else if (ln.startsWith("learn\t" + site + "\t"))
          idRe.findAllMatchIn(ln).foreach(m => maxId = maxId max m.group(1).toInt)
      } finally src.close()
      (Some(steps), if (maxId < 0) None else Some(maxId))
    } catch { case _: Throwable => (None, None) }

  def runCapped(s: Sys, capMs: Long, site: String): Outcome = {
    @volatile var result: Option[Outcome] = None
    val t0 = System.nanoTime
    def ms: Long = (System.nanoTime - t0) / 1000000L
    val th = new Thread(new Runnable { def run(): Unit =
      try {
        implicit val hm: SubstEnv = new SubstEnv()
        implicit val su: Supply = supplyAt(s.supplyLo)
        implicit val tml: Located = Loc.builtin
        val ex: Type = new Exists(Loc.builtin, List(), s.parts) // raw: Exists.apply would reverse + Set-dedup
        val res = RowTrace.withSite(site)(solve(ex))
        val took = ms
        val tys = List("a", "b", "p", "q").map(n =>
          n -> hm.types.get(s.vars(n)).map(_.toString).getOrElse("unbound"))
        result = Some(Solved(took, tys, hm.types.size, res.toString))
      } catch { case e: Throwable =>
        result = Some(Rejected(ms, e.getClass.getName, String.valueOf(e.getMessage)))
      }
    }, site)
    th.setDaemon(true)
    th.start()
    th.join(capMs)
    result.getOrElse {
      hung += 1
      val (st, mx) = traceStats(site)
      Hang(capMs, st, mx)
    }
  }

  def clip(s: String, n: Int): String = { val t = s.replace('\n', ' '); if (t.length <= n) t else t.take(n) + "..." }

  def show(o: Outcome): String = o match {
    case Solved(ms, tys, n, res) =>
      f"SOLVED   in $ms%5d ms  " + tys.map { case (k, v) => k + " := " + v }.mkString("; ") +
        s"  [bound=$n residual=${clip(res, 160)}]"
    case Rejected(ms, cls, msg) => f"REJECTED in $ms%5d ms  $cls: ${clip(msg, 300)}"
    case Hang(cap, st, mx) => f"HANG     cap $cap%5d ms" +
      st.fold("")(x => s"  steps=$x") + mx.fold("")(x => s"  maxId=$x")
  }

  def main(args: Array[String]): Unit = {
    println("genRules=" + GenRules + "  rowTrace=" + (if (tracePath.isEmpty) "off" else tracePath) +
            "  maxHeap=" + (java.lang.Runtime.getRuntime.maxMemory >> 20) + "M")
    args.toList match {
      case "sweep" :: sysName :: from :: to :: rest =>
        val capMs   = rest.headOption.map(_.toDouble).getOrElse(10.0) * 1000
        val maxHung = rest.drop(1).headOption.map(_.toInt).getOrElse(6)
        val (lo, hi) = (from.toInt, to.toInt)
        var counts = Map[String, Int]().withDefaultValue(0)
        var msgs   = Map[String, Int]().withDefaultValue(0)
        var stopped: Option[Int] = None
        var b = lo
        while (b <= hi && stopped.isEmpty) {
          val s = system(sysName, b)
          if (b == lo) s.parts.foreach { case Part(_, l, rs) =>
            def st(t: Type): String = t match {
              case VarT(v) => v.name.fold("")(_.toString) + "^" + v.id
              case ConcreteRho(_, fs) => "(|" + fs.map(_.toString).mkString(",") + "|)"
              case x => x.toString }
            println("INPUT " + st(l) + " <- (" + rs.map(st).mkString(", ") + ")")
          case x => println("INPUT " + x) }
          val o = runCapped(s, capMs.toLong, sysName + "@" + b)
          val bucket = o match {
            case _: Solved => "SOLVED"
            case r: Rejected => if (r.cls.contains("OutOfMemoryError")) "OOM" else "REJECTED"
            case _: Hang => "HANG"
          }
          counts += bucket -> (counts(bucket) + 1)
          o match { case r: Rejected => msgs += (r.cls + ": " + r.msg) -> (msgs(r.cls + ": " + r.msg) + 1); case _ => () }
          println(f"$sysName%-5s base=$b%4d ids $b..${b + 11} supply ${s.supplyLo}%4d: ${show(o)}")
          if (hung >= maxHung && b < hi) stopped = Some(b + 1)
          b += 1
        }
        println(s"SUMMARY sys=$sysName bases=$lo..${stopped.fold(hi)(_ - 1)} n=${counts.values.sum} " +
                List("SOLVED", "REJECTED", "HANG", "OOM").map(k => k + "=" + counts(k)).mkString(" "))
        msgs.toList.sortBy(-_._2).foreach { case (m, n) => println(s"  x$n  $m") }
        stopped match {
          case Some(nb) => println(s"HUNGLIMIT hung=$hung next=$nb"); System.exit(3)
          case None => ()
        }
      case _ =>
        System.err.println("usage: CRuleRepro sweep <W|gseed|G4|Wsat> <from> <to> [capSec] [maxHung]")
        System.exit(2)
    }
  }
}
