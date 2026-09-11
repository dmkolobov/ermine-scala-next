package com.clarifi.reporting
package ermine

import scalaparsers.{Inferred, Loc, Pos}
import com.clarifi.reporting.ermine.Type.{ Con, fskvs }

/** S1 of the signature-entailment programme (`tracker/SIG-ENTAIL-PLAN.md`): the WARN-MODE
  * PROBE, and nothing else.
  *
  * `Subst.subsumeType` (Subst.scala:527-553) partitions the residual constraints of the
  * inferred type into the skolem-free `ds` and the skolem-mentioning `rs`, runs the
  * class-only `entails` over `rs` and throws the Boolean away, then returns only `ds`.  So a
  * declared signature's ROW obligations are never checked.  Before deciding what to check
  * (S2) and enforcing it (S3), this object MEASURES what is out there: under
  * `-Dermine.sigEntail=warn` it prints one line per element of `rs` at each of the two
  * call sites that check a USER SIGNATURE.
  *
  * It changes no verdict, mints no variable, reads no `Supply`, and allocates nothing at
  * all under the default (`off`): every call site guards on `SigEntail.warn`, which is a
  * read-once `val`.  It is deliberately NOT a `Constraints.GenRules` field: `GenRules.
  * toString` is `Session.interfaceKey`'s second half (Session.scala:167), so a flag added
  * there invalidates every cached `.ei`, and this flag cannot change what is published.
  */
object SigEntail {
  /** `off` (DEFAULT -- shipped behaviour, byte-identical) | `warn` (print the probe).
    * `error` arrives at S3.  Read ONCE at class-init from a system property, the way
    * `Constraints.GenRules` reads its own (Constraints.scala:928), so a run is a constant
    * and no property flip mid-run can change behaviour under a test fixture. */
  private val mode: String = System.getProperty("ermine.sigEntail", "off")

  val warn: Boolean = mode == "warn"

  /** Which signature is being checked: the two callers that pass one are
    * `Subst.typeCheck` (:638 -- a term annotation `e : T`) and
    * `Subst.typeCheckExplicitBinding` (:655 -- a declared binding signature).  Every other
    * `subsumeType` caller passes `None` and is silent; see SIG-1-SURVEY.md's caller table. */
  final case class Site(kind: String, module: String, binding: String)

  def siteOf(kind: String, v: TermVar): Site = v.name match {
    case Some(Global(m, s, _)) => Site(kind, m, s)
    case Some(n)               => Site(kind, moduleOf(v.loc), n.toString)
    case None                  => Site(kind, moduleOf(v.loc), "_" + v.id)
  }

  /** A site with no binding name of its own: a term annotation `e : T`. */
  def siteAt(kind: String, l: Loc): Site = Site(kind, moduleOf(l), "<annot>")

  /** The best module name a location offers: the source file's base name without `.e`.
    * Used only when the binding's own `Name` is `Local` (a `let`/`where` head keeps its
    * local name); a top-level binding carries a `Global` and that module wins. */
  def moduleOf(l: Loc): String = l match {
    case p: Pos      => base(p.fileName)
    case Inferred(p) => base(p.fileName)
    case _           => "-"
  }

  /** `<dir>.<file>` without the `.e`, e.g. `Layout.Report` and `Lang.Helpers`.  The parent
    * directory is kept because the corpus has five different `Helpers.e` and the module
    * column would otherwise merge them; `modules/` and `examples/`, which are roots rather
    * than groups, are dropped. */
  private def base(f: String): String = {
    val s = f.replace('\\', '/')
    val i = s.lastIndexOf('/')
    val n0 = if (i < 0) s else s.substring(i + 1)
    val n = if (n0.endsWith(".e")) n0.substring(0, n0.length - 2) else n0
    val d = if (i < 0) "" else {
      val j = s.lastIndexOf('/', i - 1)
      if (j < 0) s.substring(0, i) else s.substring(j + 1, i)
    }
    if (d.isEmpty || d == "modules" || d == "examples") n else d + "." + n
  }

  /** `file:line:col`; a location the checker INFERRED from a source position is marked
    * with a leading `~`, and a builtin carries no position at all. */
  def posOf(l: Loc): String = l match {
    case p: Pos      => p.fileName + ":" + p.line + ":" + p.column
    case Inferred(p) => "~" + p.fileName + ":" + p.line + ":" + p.column
    case _           => "-"
  }

  private def flexible(v: TypeVar): Boolean = v.ty != Skolem
  private def rigid(v: TypeVar): Boolean    = v.ty == Skolem

  private def skolemIds(t: Type): Set[Int] = fskvs(t).map(_.id).toSet

  /** The SHAPE tags of the brief, tested in this order:
    *
    *  - `multi-skolem`   more than one DISTINCT skolem anywhere in the wanted;
    *  - `concrete-ext`   the lhs is that one skolem and every part is either a concrete
    *                     label set or a flexible variable, with EXACTLY ONE of the latter
    *                     -- the shape every `!`, `cons`, `\` and `modify` generates, and
    *                     the one the plan's refutation trick decides;
    *  - `skolem-in-parts` the one skolem occurs among the parts (rhs) instead;
    *  - `other`          anything else, including a class constraint over a skolem.
    */
  def shapeOf(t: Type): String = {
    val sks = skolemIds(t)
    if (sks.size > 1) "multi-skolem"
    else t match {
      case Part(_, lhs, rhs) =>
        val lhsSk = lhs match { case VarT(v) => rigid(v); case _ => false }
        val flexParts = rhs.count { case VarT(v) => flexible(v); case _ => false }
        val wellFormed = rhs.forall {
          case ConcreteRho(_, _) => true
          case VarT(v)           => flexible(v)
          case _                 => false
        }
        if (lhsSk && wellFormed && flexParts == 1) "concrete-ext"
        else if (rhs.exists(p => skolemIds(p).nonEmpty)) "skolem-in-parts"
        else "other"
      case _ => "other"
    }
  }

  /** A compact, UNAMBIGUOUS rendering.  `Pretty.prettyType` starts a fresh letter supply on
    * every call, so the wanted column and the givens column would name two different
    * variables `a` and hide exactly the distinction this survey is about; this spelling
    * carries the variable's id and its flavour (`S` skolem/rigid, `A` ambiguous-existential,
    * bare = free/flexible) so the two columns share one vocabulary. */
  def render(t: Type): String = t match {
    case Part(_, l, r)      => render(l) + " <- (" + r.map(render).mkString(", ") + ")"
    case ConcreteRho(_, fs) => "(|" + fs.toList.map(_.toString).sorted.mkString(",") + "|)"
    case VarT(v)            => varName(v)
    case AppT(AppT(Arrow(_), a), b) => "(" + render(a) + " -> " + render(b) + ")"
    case AppT(a, b)         => "(" + render(a) + " " + render(b) + ")"
    case Arrow(_)           => "->"
    case Con(_, n, _, _)    => n.string
    case ProductT(_, n)     => "(," + n + ")"
    case Memory(_, b)       => render(b)
    case Exists(_, xs, cs)  =>
      "exists " + xs.map(varName).mkString(" ") + ". " + cs.map(render).mkString(" & ")
    case Forall(_, _, ts, q, b) =>
      "forall " + ts.map(varName).mkString(" ") + ". " + render(q) + " => " + render(b)
    case other              => other.toString
  }

  private def varName(v: TypeVar): String = {
    val n = v.name match { case Some(nm) => nm.toString; case None => "_" }
    val tag = v.ty match {
      case Skolem       => "S"
      case Free         => ""
      case Ambiguous(_) => "A"
      case o            => o.toString.take(1)
    }
    n + "^" + v.id + tag
  }

  /** LITERAL: the wanted is alpha-equivalent, UP TO THE FRESH REMAINDER, to some given.
    * Skolems must match on the nose (they are the signature's own universals); flexible
    * variables match under a bijection, which is exactly "up to the fresh remainder".  A
    * `Part`'s parts are matched up to PERMUTATION, because `Part.apply` fixes no order.
    * Conservative by construction: anything it cannot take apart it compares with `==`, so
    * a `false` here is "not obviously literal", never "provably not entailed". */
  def literal(w: Type, qs: List[Type]): Boolean =
    qs.exists(g => alpha(w, g, Map()).isDefined)

  private def alpha(w: Type, g: Type, m: Map[Int, Int]): Option[Map[Int, Int]] =
    (w, g) match {
      case (VarT(a), VarT(b)) =>
        if (rigid(a) && rigid(b)) (if (a.id == b.id) Some(m) else None)
        else if (rigid(a) || rigid(b)) None
        else m.get(a.id) match {
          case Some(j) => if (j == b.id) Some(m) else None
          case None    => if (m.valuesIterator.contains(b.id)) None else Some(m + (a.id -> b.id))
        }
      case (ConcreteRho(_, x), ConcreteRho(_, y)) => if (x == y) Some(m) else None
      case (Con(_, n1, _, _), Con(_, n2, _, _))   => if (n1 == n2) Some(m) else None
      /* A CLASS HEAD is a `Con` in the body's wanted but can still be the `Bound` type
       * variable the renamer left in the SIGNATURE's constraint (`AsPresentation^537025B`
       * in `Report.e`'s givens against `AsPresentation` in its wanteds).  Same class, two
       * spellings; matching them by name is what keeps the `lit` column honest for class
       * constraints.  Only `Bound` qualifies -- a `Free` or `Skolem` variable in head
       * position is a real variable, not a name awaiting resolution. */
      case (Con(_, n1, _, _), VarT(v)) if v.ty == Bound =>
        if (v.name.exists(_.toString == n1.string)) Some(m) else None
      case (VarT(v), Con(_, n2, _, _)) if v.ty == Bound =>
        if (v.name.exists(_.toString == n2.string)) Some(m) else None
      case (Arrow(_), Arrow(_))                   => Some(m)
      case (ProductT(_, n1), ProductT(_, n2))     => if (n1 == n2) Some(m) else None
      case (AppT(a1, b1), AppT(a2, b2))           => alpha(a1, a2, m).flatMap(alpha(b1, b2, _))
      case (Memory(_, b1), Memory(_, b2))         => alpha(b1, b2, m)
      case (Part(_, l1, r1), Part(_, l2, r2)) =>
        if (r1.length != r2.length) None
        else alpha(l1, l2, m).flatMap(mm => perm(r1, r2, mm))
      case (a, b) => if (a == b) Some(m) else None
    }

  /** Match two part lists up to permutation, with backtracking.  The lists are two or
    * three long in every constraint the row theory builds, so this is not a cost. */
  private def perm(xs: List[Type], ys: List[Type], m: Map[Int, Int]): Option[Map[Int, Int]] =
    xs match {
      case Nil => if (ys.isEmpty) Some(m) else None
      case x :: rest =>
        ys.indices.iterator.flatMap { i =>
          alpha(x, ys(i), m).flatMap(mm => perm(rest, ys.patch(i, Nil, 1), mm)).iterator
        }.nextOption()
    }

  /** Escape tabs and newlines, and collapse the pretty printer's fill so a record stays on
    * one line.  Same job as `RowTrace.clean`, which it delegates to. */
  private def one(s: String): String = RowTrace.clean(s).replaceAll("  +", " ").trim

  /** One line per skolem-mentioning wanted:
    *
    *   sigEntail \t module \t binding \t file:line:col \t shape \t lit|nolit \t wanted \t givens
    *
    * It goes through `RowTrace.log` when `-Dermine.rowTrace` is set -- so a traced run keeps
    * every record in one file and one order -- and to stdout otherwise, which is where
    * `tracker/tools/corpus-run.sh` captures it into the per-file `.out`.  Both spellings end
    * with `RowTrace`'s thread-id column, so one reader handles both. */
  def probe(site: Site, qs: List[Type], rs: List[Type]): Unit = if (warn) {
    val givens = one(qs.map(render).mkString("; "))
    for (r <- rs) {
      val rec = "sigEntail\t" + site.module + "\t" + site.kind + ":" + site.binding + "\t" +
                posOf(r.loc) + "\t" + shapeOf(r) + "\t" + (if (literal(r, qs)) "lit" else "nolit") +
                "\t" + one(render(r)) + "\t" + givens
      if (RowTrace.enabled) RowTrace.log(rec)
      else System.out.println(rec + "\t" + RowTrace.tid)
    }
  }
}
