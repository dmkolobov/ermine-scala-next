import Replay._
import com.clarifi.reporting.ermine._

/** Positive control for tracker/tools/keptdef-mints.py: the KeepInert.lean counterexample
  *   u <- (x, y, (|k|))    u <- (|k, c|)    R <- (u, z)
  * replayed through the real `Subst.solve` with the kept definition in play. */
object KeepMintRepro {
  def f(s: String): Name = Global("Repro", s)
  val k = Set(f("k")); val c = Set(f("c"))
  def inst(u: TypeVar, x: TypeVar, y: TypeVar, r: TypeVar, z: TypeVar, order: Int): List[Type] = {
    val d = part(vt(u), List(vt(x), vt(y), cr(k)))
    val e = part(vt(u), List(cr(k ++ c)))
    val m = part(vt(r), List(vt(u), vt(z)))
    order match { case 0 => List(d, e, m); case 1 => List(e, d, m); case 2 => List(m, e, d); case _ => List(e, m, d) }
  }
  def main(args: Array[String]): Unit = {
    for (b <- 0 until 8; o <- 0 until 4) {
      val (u, x, y, r, z) = (tv(b, "u"), tv(b + 1, "x"), tv(b + 2, "y"), tv(b + 3, "r"), tv(b + 4, "z"))
      val out = try {
        implicit val hm: SubstEnv = new SubstEnv()
        implicit val su: scalaparsers.Supply = supplyAt(b + 5)
        implicit val tml: scalaparsers.Located = scalaparsers.Loc.builtin
        val ex: Type = new Exists(scalaparsers.Loc.builtin, List(), inst(u, x, y, r, z, o))
        RowTrace.withSite("keepmint@" + b + "/" + o)(com.clarifi.reporting.ermine.Subst.solve(ex))
        "solved: u=" + hm.types.get(u) + " x=" + hm.types.get(x) + " r=" + hm.types.get(r)
      } catch { case t: Throwable => "REJECTED " + t.getClass.getSimpleName + ": " + t.getMessage }
      println(f"base $b order $o: $out")
    }
  }
}
