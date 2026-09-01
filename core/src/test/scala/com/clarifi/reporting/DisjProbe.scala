package com.clarifi.reporting

import scalaparsers._
import ermine._
import Constraints._
import Subst.solve

/** Drives the row-constraint solver directly, bypassing the module loader, and
 *  compares it against a candidate REFUTATION-ONLY rule: per-concrete-label
 *  unit propagation.
 *
 *  The rule.  A partition `x <- (p1..pn)` says the parts are pairwise disjoint
 *  and union to x.  Project that onto one label L: at most one part contains L,
 *  and x contains L iff some part does.  That is a Boolean constraint over the
 *  bits [L in v].  Concrete rows pin bits; unit propagation does the rest.  A
 *  contradiction at any single label refutes the whole set, because every real
 *  solution induces a consistent assignment of these bits.
 *
 *  Properties, which are why this is worth considering where Disjunction is not:
 *    - refutation only: never emits a partition, never mints a variable, so it
 *      cannot feed the saturation loop or change any inferred type;
 *    - ranges only over labels that literally occur in a ConcreteRho in the set;
 *    - propagation only, no case split, so it is linear per label.
 *  It is therefore INCOMPLETE by construction -- deciding these Boolean systems
 *  in general is NP-hard (Schaefer's one-in-three; see ticket section 1).
 *
 *  Run: sbt -batch 'core/Test/runMain com.clarifi.reporting.DisjProbe'
 */
object DisjProbe {
  implicit val su: Supply = Supply.create
  implicit val tml: Located = Loc.builtin
  val L = Loc.builtin

  // -- a description shared by the solver and the checker --------------------
  sealed trait P
  case class Row(v: TypeVar) extends P
  case class Con(ns: Set[Name]) extends P
  case class Pt(lhs: P, parts: List[P])

  def cfresh(): TypeVar = fresh(L, None, Free, Rho(L))
  def c(ns: String*): Con = Con(ns.map(n => Local(n): Name).toSet)
  def toT(p: P): Type = p match {
    case Row(v)  => VarT(v)
    case Con(ns) => ConcreteRho(L, ns)
  }
  def toType(pt: Pt): Type = Part(L, toT(pt.lhs), pt.parts.map(toT))

  // -- the candidate rule ----------------------------------------------------
  def labelCheck(pts: List[Pt]): Option[String] = {
    val labels: Set[Name] =
      pts.flatMap(p => (p.lhs :: p.parts).collect { case Con(ns) => ns }.flatten).toSet
    labels.toList.flatMap(l => checkLabel(pts, l).map(m => s"[$l] $m")).headOption
  }

  /** Unit-propagate the bits [l in v]. Some(msg) = contradiction = REFUTED. */
  def checkLabel(pts: List[Pt], l: Name): Option[String] = {
    var bits = Map[TypeVar, Boolean]()
    var changed = true
    var clash: Option[String] = None

    def get(p: P): Option[Boolean] = p match {
      case Con(ns) => Some(ns contains l)
      case Row(v)  => bits.get(v)
    }
    def set(p: P, b: Boolean, why: => String): Unit = p match {
      case Con(ns) => if ((ns contains l) != b) clash = clash orElse Some(why)
      case Row(v)  => bits.get(v) match {
        case Some(b0) => if (b0 != b) clash = clash orElse Some(why)
        case None     => bits = bits + (v -> b); changed = true
      }
    }

    while (changed && clash.isEmpty) {
      changed = false
      for (Pt(lhs, parts) <- pts if clash.isEmpty) {
        val pb    = parts.map(get)
        val ones  = pb.count(_ == Some(true))
        val zeros = pb.count(_ == Some(false))
        if (ones > 1)
          clash = clash orElse Some("two parts of one partition both carry it")
        else {
          if (ones == 1) {                                  // some part has it
            set(lhs, true, "a part carries it but the whole does not")
            for (p <- parts if get(p).isEmpty) set(p, false, "")
          }
          if (get(lhs) == Some(false))                      // whole lacks it
            for (p <- parts) set(p, false, "a part carries it but the whole does not")
          if (zeros == parts.length)                        // no part has it
            set(lhs, false, "the whole carries it but no part does")
          if (get(lhs) == Some(true) && ones == 0) {        // must be somewhere
            val unknown = parts.filter(get(_).isEmpty)
            if (unknown.isEmpty) clash = clash orElse Some("the whole carries it but no part can")
            else if (unknown.length == 1) set(unknown.head, true, "")
          }
        }
      }
    }
    clash
  }

  // -- harness ---------------------------------------------------------------
  var rows = List[(String, Boolean, String, String)]()

  def probe(name: String, satisfiable: Boolean)(pts: List[Pt]): Unit = {
    implicit val hm: SubstEnv = new SubstEnv()
    val solverV =
      try { solve(Exists(L, List(), pts.map(toType))); "ACCEPTED" }
      catch { case _: Death => "REFUTED " }
    val ruleV = if (labelCheck(pts).isDefined) "REFUTED " else "ACCEPTED"
    rows = rows :+ ((name, satisfiable, solverV, ruleV))
  }

  def main(args: Array[String]): Unit = {
    val t0 = System.nanoTime()

    probe("unsound01 keyed halves", false) {
      val l, s, t, lt, rt = cfresh()
      List(Pt(Row(t),  List(Row(l), Row(s))),
           Pt(Row(lt), List(c("accountId"), Row(l))),
           Pt(Row(rt), List(c("accountId"), Row(s))),
           Pt(Row(t),  List(c("accountId", "regionCode"))))
    }
    probe("unsound02 three-way shard", false) {
      val a, b, d, t, at, bt, ct = cfresh()
      List(Pt(Row(t),  List(Row(a), Row(b), Row(d))),
           Pt(Row(at), List(c("accountId"), Row(a))),
           Pt(Row(bt), List(c("accountId"), Row(b))),
           Pt(Row(ct), List(c("accountId"), Row(d))),
           Pt(Row(t),  List(c("accountId", "regionCode"))))
    }
    probe("CONTROL good: key not in ledger", true) {
      val l, s, t, lt, rt = cfresh()
      List(Pt(Row(t),  List(Row(l), Row(s))),
           Pt(Row(lt), List(c("accountId"), Row(l))),
           Pt(Row(rt), List(c("accountId"), Row(s))),
           Pt(Row(t),  List(c("regionCode", "amount"))))
    }
    probe("CONTROL dup: t <- (|x|),(|x|)", false) {
      val t = cfresh()
      List(Pt(Row(t), List(c("accountId"), c("accountId"))))
    }
    for ((nm, ls, ss) <- List(
           ("witness case1 l={} s={a,r}",   List[String](),                 List("accountId","regionCode")),
           ("witness case2 l={a} s={r}",    List("accountId"),              List("regionCode")),
           ("witness case3 l={r} s={a}",    List("regionCode"),             List("accountId")),
           ("witness case4 l={a,r} s={}",   List("accountId","regionCode"), List[String]())))
      probe(nm, false) {
        val t, lt, rt = cfresh()
        List(Pt(Row(t),  List(c(ls: _*), c(ss: _*))),
             Pt(Row(lt), List(c("accountId"), c(ls: _*))),
             Pt(Row(rt), List(c("accountId"), c(ss: _*))),
             Pt(Row(t),  List(c("accountId", "regionCode"))))
      }
    probe("CONTROL join example", true) {
      val a, b, d, e, f, g = cfresh()
      List(Pt(Row(e), List(Row(a), Row(b))),
           Pt(Row(f), List(Row(b), Row(d))),
           Pt(Row(g), List(Row(a), Row(b), Row(d))),
           Pt(Row(e), List(c("Fst", "Snd"))),
           Pt(Row(f), List(c("Snd", "Thd"))))
    }
    // a general helper mentioning concrete fields, with NO concrete instance:
    probe("CONTROL general helper, open", true) {
      val t, l, s, lt, rt = cfresh()
      List(Pt(Row(t),  List(Row(l), Row(s))),
           Pt(Row(lt), List(c("accountId"), Row(l))),
           Pt(Row(rt), List(c("accountId"), Row(s))))
    }

    println("genRules=" + GenRules + "  disjunction=" + GenRules.disjRule)
    println()
    println(f"  ${"case"}%-34s ${"sat?"}%-6s ${"solver"}%-10s ${"label rule"}%-10s")
    println("  " + "-" * 62)
    var solverMiss, ruleMiss = 0
    for ((nm, sat, sv, rv) <- rows) {
      val sOk = (sv.trim == "ACCEPTED") == sat
      val rOk = (rv.trim == "ACCEPTED") == sat
      if (!sOk) solverMiss += 1
      if (!rOk) ruleMiss += 1
      println(f"  $nm%-34s $sat%-6s $sv%-10s${if (sOk) "  " else "<-MISS"} $rv%-10s${if (rOk) "" else "<-MISS"}")
    }
    println()
    println(s"solver wrong on $solverMiss/${rows.length}; label rule wrong on $ruleMiss/${rows.length}")
    println(f"total wall ${(System.nanoTime() - t0) / 1e6}%.0f ms")
  }
}
