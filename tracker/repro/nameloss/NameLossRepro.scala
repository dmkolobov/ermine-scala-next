import Replay._
import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.Constraints.GenRules

/** Partition-level reproducer for tracker/PROMPT-substitution-gap.md.
  *
  * Replays `Subst.solve` on exact constraint lists with exact variable ids (the ids decide
  * the priority-queue order, and the order decides the outcome), for
  *   (1) the two real module-level inputs of `Ai/HeadcountPlan.withUnitCost` (regime A ids
  *       615048.., regime B ids 506328..), with the duplicate removed / added, and with the
  *       ids of the other regime;
  *   (2) id sweeps of the A-shaped, B-shaped and B-minus-duplicate inputs;
  *   (3) the smallest input that shows the race,
  *         (|k,c|) <- ((|k|), x, y)    (|d|) <- (x, z)    t <- (x, y, z)
  *       and the same with the name given as an input, (|c|) <- (x, y), which never fails.
  * Under the solver as of 2026-09-02 (definitions kept in `destructiveSub`) every configuration
  * pins; the failing rows in tracker/repro/README.md were measured on the deleting solver.
  * Run with `-Dermine.rowTrace=<file>` to get step-level traces (records `step`/`learn`). */
object NameLossRepro {
  def pinnedTo(o: Outcome, fs: Set[Name]): Boolean =
    o.t match { case Some(ConcreteRho(_, s)) => s == fs; case _ => false }
  def bar(bs: Seq[Boolean]): String = bs.map(if (_) '#' else '.').mkString

  // ---- (1) exact replays -------------------------------------------------------------
  def exact(): Unit = {
    println("== exact replays of Ai/HeadcountPlan.withUnitCost (module-level solve)")
    val (tA, aA, rsA, soA) = (tv(615048, "t"), tv(615049), tv(615050, "rs"), tv(615051, "so"))
    val a0 = part(cr(D),  List(vt(rsA), vt(soA)))
    val a1 = part(cr(R8), List(cr(K), vt(rsA), vt(aA)))
    val a2 = part(vt(tA), List(cr(K), vt(rsA), vt(soA), vt(aA)))
    val (tB, aB, rsB, soB) = (tv(506328, "t"), tv(506329), tv(506330, "rs"), tv(506331, "so"))
    val b0 = part(cr(R8), List(cr(K), vt(aB), vt(rsB)))
    val b1 = part(cr(D),  List(vt(soB), vt(rsB)))
    val b2 = part(cr(R8), List(cr(K), vt(rsB), vt(aB)))
    val b3 = part(vt(tB), List(cr(K), vt(aB), vt(soB), vt(rsB)))
    def go(label: String, parts: List[Type], t: TypeVar, lo: Int): Unit =
      println(f"  $label%-30s ${show(run(parts, t, lo, Some(label)))}")
    go("A exact (3 parts)", List(a0, a1, a2), tA, 615052)
    go("B exact (4 parts, dup)", List(b0, b1, b2, b3), tB, 506332)
    go("B minus the duplicate", List(b0, b1, b3), tB, 506332)
    go("B minus the other copy", List(b1, b2, b3), tB, 506332)
    go("A plus a duplicate", List(a0, a1, part(cr(R8), List(cr(K), vt(aA), vt(rsA))), a2), tA, 615052)
    go("A shape, B ids", List(part(cr(D), List(vt(rsB), vt(soB))), part(cr(R8), List(cr(K), vt(rsB), vt(aB))),
                              part(vt(tB), List(cr(K), vt(rsB), vt(soB), vt(aB)))), tB, 506332)
    go("B shape, A ids", List(part(cr(R8), List(cr(K), vt(aA), vt(rsA))), part(cr(D), List(vt(soA), vt(rsA))),
                              part(cr(R8), List(cr(K), vt(rsA), vt(aA))), part(vt(tA), List(cr(K), vt(aA), vt(soA), vt(rsA)))), tA, 615052)
  }

  // ---- (2) id sweeps of the HeadcountPlan shapes --------------------------------------
  def shapeA(t: TypeVar, a: TypeVar, rs: TypeVar, so: TypeVar) = List(
    part(cr(D),  List(vt(rs), vt(so))),
    part(cr(R8), List(cr(K), vt(rs), vt(a))),
    part(vt(t),  List(cr(K), vt(rs), vt(so), vt(a))))
  def shapeB(t: TypeVar, a: TypeVar, rs: TypeVar, so: TypeVar) = List(
    part(cr(R8), List(cr(K), vt(a), vt(rs))),
    part(cr(D),  List(vt(so), vt(rs))),
    part(cr(R8), List(cr(K), vt(rs), vt(a))),
    part(vt(t),  List(cr(K), vt(a), vt(so), vt(rs))))
  def shapeBnodup(t: TypeVar, a: TypeVar, rs: TypeVar, so: TypeVar) = List(
    part(cr(R8), List(cr(K), vt(a), vt(rs))),
    part(cr(D),  List(vt(so), vt(rs))),
    part(vt(t),  List(cr(K), vt(a), vt(so), vt(rs))))

  def sweep(name: String, sh: (TypeVar, TypeVar, TypeVar, TypeVar) => List[Type], goal: Set[Name]): Unit = {
    val contiguous = (0 until 200).map { b =>
      val (t, a, rs, so) = (tv(b, "t"), tv(b + 1), tv(b + 2), tv(b + 3))
      pinnedTo(run(sh(t, a, rs, so), t, b + 4), goal) }
    val perms = List(0, 1, 2, 3).permutations.toList.map { p =>
      val vs = p.map(i => tv(1000 + i)); pinnedTo(run(sh(vs(0), vs(1), vs(2), vs(3)), vs(0), 1004), goal) }
    val supply = (0 until 50).map { b =>
      val (t, a, rs, so) = (tv(10, "t"), tv(11), tv(12), tv(13))
      pinnedTo(run(sh(t, a, rs, so), t, 100 + 7 * b), goal) }
    println(f"  $name%-28s ids base..base+3, supply base+4, base=0..199: pinned ${contiguous.count(identity)}%3d/200  ${bar(contiguous.take(40))}")
    println(f"  $name%-28s 24 permutations of the four input ids:          pinned ${perms.count(identity)}%3d/24")
    println(f"  $name%-28s fixed ids 10..13, mint ids from 100+7k, k<50:   pinned ${supply.count(identity)}%3d/50   ${bar(supply)}")
  }

  // ---- (3) the minimal instance ---------------------------------------------------------
  def f(s: String): Name = Global("Repro", s)
  val k = Set(f("k")); val c = Set(f("c")); val d = Set(f("d"))
  def minimal(t: TypeVar, x: TypeVar, y: TypeVar, z: TypeVar): List[Type] = List(
    part(cr(k ++ c), List(cr(k), vt(x), vt(y))),   // R <- (|k,c|), R <- ((|k|), x, y): split MINTS the name u <- (x, y)
    part(cr(d),      List(vt(x), vt(z))),          // D <- (|d|),   D <- (x, z)
    part(vt(t),      List(vt(x), vt(y), vt(z))))
  def minimalNamed(t: TypeVar, x: TypeVar, y: TypeVar, z: TypeVar): List[Type] = List(
    part(cr(c), List(vt(x), vt(y))),               // the name is an INPUT: nothing ever mentions it, so it is never deleted
    part(cr(d), List(vt(x), vt(z))),
    part(vt(t), List(vt(x), vt(y), vt(z))))

  def main(args: Array[String]): Unit = {
    println("genRules=" + GenRules)
    exact()
    println("== id sweeps of the HeadcountPlan shapes (goal: t := the 9-field row)")
    sweep("A (3 parts)", shapeA, R9)
    sweep("B (4 parts, dup)", shapeB, R9)
    sweep("B minus dup", shapeBnodup, R9)
    println("== the minimal instance (goal: t := (|c, d|))")
    sweep("split mints the name", minimal, c ++ d)
    sweep("name is an input", minimalNamed, c ++ d)
    for (b <- args.map(_.toInt)) {
      val (t, x, y, z) = (tv(b, "t"), tv(b + 1, "x"), tv(b + 2, "y"), tv(b + 3, "z"))
      val o = run(minimal(t, x, y, z), t, b + 4, Some("min@" + b))
      println(f"  minimal instance at id base $b%3d: ${if (pinnedTo(o, c ++ d)) "t := (|c, d|)" else "t UNPINNED"}")
    }
  }
}
