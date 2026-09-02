import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.Constraints._
import com.clarifi.reporting.ermine.Subst.{solve, substType}
import scalaparsers.{Supply, Loc, Located}

/** Replay a `solve` on an exact constraint list with exact variable ids. */
object Replay {
  val M = "Ai.HeadcountPlan"
  def g(s: String): Name = Global(M, s)
  val R8: Set[Name] = Set("annualCost","fte","orgId","orgName","personName","reqStatus","seatId","seatKind").map(g)
  val K:  Set[Name] = Set("annualCost","fte").map(g)
  val D:  Set[Name] = Set(g("costPerFte"))
  val R6: Set[Name] = R8 -- K
  val R9: Set[Name] = R8 ++ D

  def supplyAt(lo: Int): Supply = {
    val c = classOf[Supply].getDeclaredConstructors.head
    c.setAccessible(true)
    c.newInstance(Integer.valueOf(lo), Integer.valueOf(lo + 100000)).asInstanceOf[Supply]
  }
  def rho: Kind = Rho(Loc.builtin)
  def tv(id: Int, name: String = ""): TypeVar =
    V(Loc.builtin, id, if (name.isEmpty) None else Some(Local(name)), Free, rho)
  def cr(fs: Set[Name]): Type = ConcreteRho(Loc.builtin, fs)
  def vt(v: TypeVar): Type = VarT(v)
  /** raw Part, bypassing the smart constructor so the list order is exactly as given */
  def part(lhs: Type, rhs: List[Type]): Type = new Part(Loc.builtin, lhs, rhs)

  case class Outcome(t: Option[Type], sat: List[String], byRule: Map[String, Int])

  /** Run one solve.  `parts` is the input list; `t` the variable whose instantiation we read back. */
  def run(parts: List[Type], t: TypeVar, supplyLo: Int, trace: Option[String] = None): Outcome = {
    implicit val hm: SubstEnv = new SubstEnv()
    implicit val su: Supply = supplyAt(supplyLo)
    implicit val tml: Located = Loc.builtin
    val ex: Type = new Exists(Loc.builtin, List(), parts) // raw: Exists.apply would reverse + Set-dedup
    RowTrace.withSite(trace.getOrElse("replay"))(solve(ex))
    val tt = hm.types.get(t)
    Outcome(tt, Nil, Map())
  }

  def show(o: Outcome): String = o.t match {
    case Some(ConcreteRho(_, fs)) => "t := concrete(" + fs.size + ")" + (if (fs == R9) " = R9" else " " + fs.map(_.toString.split('.').last).toList.sorted.mkString(","))
    case Some(x) => "t := " + x
    case None => "t UNPINNED"
  }
}
