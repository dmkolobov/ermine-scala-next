package com.clarifi.reporting
package ermine

import scalaparsers.{Inferred, Loc, Located, Pos}
import scalaparsers.Document.text
import com.clarifi.reporting.ermine.Type.{ Con, fskvs }
import com.clarifi.reporting.ermine.Constraints.RHS

/** THE SIGNATURE-ENTAILMENT CHECK (`tracker/SIG-ENTAIL-PLAN.md`, design
  * `tracker/loopmodel/SIG-2-DESIGN.md`).
  *
  * `Subst.subsumeType` (Subst.scala:534) partitions the residual constraints of the
  * inferred type into the skolem-free `ds` and the skolem-mentioning `rs`, runs the
  * class-only `entails` over `rs` and throws the Boolean away, then returns only `ds`.  So
  * until S3 a declared signature's ROW obligations were never checked, and
  * `healthOpt : forall r. {..r} -> Int; healthOpt r = r ! health` was accepted.
  *
  * S1 (`SIG-1-SURVEY.md`) measured the population with the `warn` probe below; S2
  * (`SIG-2-DESIGN.md`, Lean `tracker/lean/Rowpartition/SigEntail.lean`) fixed the
  * judgement and proved the decision procedure; S3 -- this file -- runs it.  The
  * judgement, verbatim from (a): with `Q` the signature's row givens, `W` the body's row
  * obligations and `F` the solver-minted variables of `W`,
  *
  *     for every rho with rho |= Q there is rho' agreeing with rho off F with rho' |= W.
  *
  * Rigid variables (`R`) are universally quantified -- the CALLER instantiates them -- and
  * `F` is chosen per model, which is the weakest sound requirement because no compiled
  * code depends on which row a minted variable denotes.  `F = vars(W) ∩ pxs \ vars(Q)`:
  * rigidity is read off the variable's provenance in THIS residual, never off the call's
  * skolem list (an enclosing signature's skolem would otherwise be CHOSEN, which accepts a
  * dishonest signature).  The procedure decides the judgement LABEL CLASS by LABEL CLASS
  * (one 2QBF per literally mentioned column plus ONE generic class standing for every
  * column mentioned nowhere), by enumerating the models of the givens over `R` and asking
  * whether the wanteds are satisfiable with the minted bits free -- `Constraints.
  * LabelSearch`, the same one-hot engine `Subst.solve`'s per-label decision uses.
  *
  * Soundness and completeness of that decomposition are `sigEntails_of_lsig` /
  * `lsig_of_sigEntails` in the Lean module; the corpus differential against the Python
  * oracle and a ScalaCheck differential against exhaustive enumeration are
  * `TestSigEntailDiff`.
  */
object SigEntail {
  /** `error` (DEFAULT, the user's decision of 2026-09-11) | `warn` | `off`.
    *
    * `off` is byte-identical to the shipped pre-S3 behaviour: no `Site` is allocated, the
    * check never runs.  `warn` prints the S1 probe records AND every diagnostic the check
    * would raise, and accepts.  `error` refuses the module.
    *
    * This is the process-wide DEFAULT, read ONCE at class-init the way
    * `Constraints.GenRules` reads its own (Constraints.scala:928), so no property flip
    * mid-run can change behaviour under a test fixture.  The mode that is actually
    * consulted is per session -- `SessionEnv.sigEntail` -> `SubstEnv.sigEntail` -> the
    * three call sites in `Subst` -- so a suite can run one property under `error` and
    * another under `off` in one JVM without `System.setProperty` (the fixture rule at the
    * top of TestErmine.scala).
    *
    * It is deliberately NOT a `Constraints.GenRules` field: `GenRules.toString` is
    * `Session.interfaceKey`'s second half, and a new field there invalidates every cached
    * `.ei`.  `error` CAN change what is published (by refusing), so `Session.interfaceKey`
    * appends `|sigEntail=error` in that mode only -- see Session.scala.
    */
  sealed abstract class Mode { def on: Boolean = this != Off }
  case object Off   extends Mode
  case object Warn  extends Mode
  case object Error extends Mode

  /** A typo must not choose a mode.  Mapping an unrecognised value to `Error` (as the first
    * draft did) silently ships the strictest behaviour on `-Dermine.sigentail=warn`; mapping
    * it to `Off` would silently ship no check at all.  It DIES, naming what it accepts --
    * from a `val` initialiser, so the failure is immediate and unmissable rather than a
    * module refused ten minutes later for a reason nobody typed. */
  def modeOf(s: String): Mode = s match {
    case "off"   => Off
    case "warn"  => Warn
    case "error" => Error
    case other   => sys.error("-Dermine.sigEntail: unknown mode '" + other +
                              "'; accepted values are off, warn, error")
  }

  val defaultMode: Mode = modeOf(System.getProperty("ermine.sigEntail", "error"))

  /** Which signature is being checked: the two callers that pass one are
    * `Subst.typeCheck` (:651 -- a term annotation `e : T`) and
    * `Subst.typeCheckExplicitBinding` (:669 -- a declared binding signature).  Every other
    * `subsumeType` caller passes `None` and is silent; see SIG-1-SURVEY.md's caller table.
    * `loc` is the SECONDARY location of a diagnostic, the "declared at" line: the bound
    * variable's own position for a signature, the annotated expression's for `ann`. */
  final case class Site(kind: String, module: String, binding: String, loc: Loc)

  /** `at` is the SECONDARY location -- the "declared at" line -- and the caller passes the
    * DECLARED ANNOTATION's own `Loc`, not the bound variable's: `binding.v.loc` is the
    * EQUATION's head, so on a one-line body the two locations of the diagnostic collapse onto
    * the same line and the secondary tells the reader nothing (S3 review M1, measured on all
    * four `sig` pins).  The variable is still where the NAME and the module come from. */
  def siteOf(kind: String, v: TermVar, at: Loc): Site = v.name match {
    case Some(Global(m, s, _)) => Site(kind, m, s, at)
    case Some(n)               => Site(kind, moduleOf(v.loc), n.toString, at)
    case None                  => Site(kind, moduleOf(v.loc), "_" + v.id, at)
  }

  /** A site with no binding name of its own: a term annotation `e : T`. */
  def siteAt(kind: String, l: Loc): Site = Site(kind, moduleOf(l), "<annot>", l)
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
    *   sigEntail \t module \t binding \t file:line:col \t shape \t lit|nolit \t wanted
    *           \t givens \t the skolem-FREE residual (`ds`)
    *
    * It goes through `RowTrace.log` when `-Dermine.rowTrace` is set -- so a traced run keeps
    * every record in one file and one order -- and to stdout otherwise, which is where
    * `tracker/tools/corpus-run.sh` captures it into the per-file `.out`.  Both spellings end
    * with `RowTrace`'s thread-id column, so one reader handles both.
    *
    * The `ds` column is S3's addition (design (a3) / checklist 12): `W` is the closure of
    * `rs` under shared minted variables WITHIN `ps`, so the other half of the `:541`
    * partition is what decides whether the closure is wider than `rs`, and the oracle
    * cannot see it from the S1 records.  Printed under `warn` only; the column is appended
    * so every reader of the S1 format (which took eight columns and a tid) still works. */
  def probe(site: Site, qs: List[Type], rs: List[Type], ds: List[Type]): Unit = {
    val givens = one(qs.map(render).mkString("; "))
    val free   = one(ds.map(render).mkString("; "))
    for (r <- rs) {
      val rec = "sigEntail\t" + site.module + "\t" + site.kind + ":" + site.binding + "\t" +
                posOf(r.loc) + "\t" + shapeOf(r) + "\t" + (if (literal(r, qs)) "lit" else "nolit") +
                "\t" + one(render(r)) + "\t" + givens + "\t" + free
      if (RowTrace.enabled) RowTrace.log(rec)
      else System.out.println(rec + "\t" + RowTrace.tid)
    }
  }

  /* ------------------------------------------------------------------ *
   *  S3: THE CHECK                                                      *
   * ------------------------------------------------------------------ */

  /** A row constraint the engine can read: `v <- (abstr..., concr)`.  `src` is the `Type`
    * it came from, kept for blame (its `Loc`) and for the message (its rendering). */
  final case class Row(v: TypeVar, rhs: RHS, src: Type) {
    def vars: Set[TypeVar] = rhs.abstr + v
    def conc: Set[Name]    = rhs.concr
    def tup: (TypeVar, RHS) = (v, rhs)
  }

  /** What one constraint of `qs`/`ps` turned into.  `Type` is WIDER than the verified model
    * (`Part.apply` can leave two OVERLAPPING concrete parts unmerged, Type.scala:427-429,
    * and can build a CONCRETE left-hand side, :421-424, while `RHS` has one `concr` field
    * and Lean's `Constraint` one `conc`), so the encoding contract of design (e) 2b is
    * explicit here: a repeated variable part is NORMALISED (it forces that variable empty --
    * `Basic.Sat.eq_empty_of_dup`), and anything else the model cannot STATE is `Unreadable`,
    * which means NO VERDICT with a named reason.  Never a silent merge: merging two
    * overlapping concrete parts turns an unsatisfiable partition into a satisfiable one,
    * which flips verdicts in both directions. */
  private sealed abstract class Enc
  private final case class Encoded(rows: List[Row]) extends Enc
  private final case class Unreadable(why: String)  extends Enc
  private final case class NotRow(why: Option[String]) extends Enc

  private def strip(t: Type): Type = t match {
    case Memory(_, b) => strip(b)
    case other        => other
  }

  /** The head of a curried application, for the (a4) diagnostic. */
  private def headOf(t: Type): Type = strip(t) match {
    case AppT(f, _) => headOf(f)
    case other      => other
  }

  private def encode(t0: Type): Enc = strip(t0) match {
    case p@Part(_, lhs0, rhs0) =>
      val lhs = strip(lhs0)
      val parts = rhs0.map(strip)
      val bad = parts.collectFirst {
        case x if !(x.isInstanceOf[VarT] || x.isInstanceOf[ConcreteRho]) =>
          "the partition has a part that is neither a row variable nor a literal column " +
          "set (" + render(x) + ")"
      }
      val concs = parts.collect { case c: ConcreteRho => c }
      lazy val vs = parts.collect { case VarT(v) => v }
      if (bad.isDefined) Unreadable(bad.get)
      else if (concs.length > 1)
        Unreadable("the partition has " + concs.length + " literal column sets on its right " +
          "(" + concs.map(render).mkString(", ") + "); they may overlap, and merging them " +
          "could flip the verdict either way, so no verdict is claimed")
      else lhs match {
        case VarT(v) =>
          val dups = vs.groupBy(x => x).collect { case (x, l) if l.length > 1 => x }.toList
          // a repeated part forces that variable EMPTY (`Sat.eq_empty_of_dup`), and the
          // partition then reads with every occurrence of it deleted
          val kept = vs.filterNot(dups.contains)
          val main = Row(v, RHS(kept.toSet, concs.headOption.fold(Set[Name]())(_.fields)), p)
          Encoded(main :: dups.map(d => Row(d, RHS(Set(), Set()), p)))
        /* THE EMPTY ROW ON THE LEFT, normalised.  `(||) <- (p1..pk)` says the empty row is
         * partitioned by the parts, i.e. at every column the whole is absent, so EVERY part
         * is absent: the partition is EQUIVALENT to `p1 <- () & ... & pk <- ()`, which the
         * model states directly.  Verdict-preserving in both directions (one-hot: a whole
         * that is 0 forces every part to 0, and all-0 parts force the whole to 0), and it
         * is the one concrete-left-hand-side shape the corpus actually has -- 269 of them,
         * all in the skolem-free half `ds`, where `Time.Signatures.yearFrac365Simple`'s
         * `(||) <- (f, e)` is what makes its `out` row the union of its operands'.
         * `Part.apply` has already flopped the single-part case (`(|C|) <- (v)` becomes
         * `v <- ((|C|))`, Type.scala:423) and discharged the tautology, so what arrives here
         * has two or more parts. */
        case c: ConcreteRho if c.fields.isEmpty && concs.forall(_.fields.isEmpty) =>
          Encoded(vs.distinct.map(v => Row(v, RHS(Set(), Set()), p)))
        case c: ConcreteRho =>
          Unreadable("the partition has a NON-EMPTY literal column set on its LEFT (" +
                     render(c) + "), which the decision procedure's model cannot state")
        case other =>
          Unreadable("the partition's left-hand side is neither a row variable nor a " +
                     "literal column set (" + render(other) + ")")
      }
    case other =>
      /* Not a row constraint at all.  A CLASS constraint is out of scope by design (they
       * are checked at generalisation, Subst.scala:389) and is dropped silently.  An
       * application headed by a type VARIABLE is different and must be named: it is an
       * alias that is NOT IN SCOPE, closed over as an ordinary implicitly quantified
       * variable, so it constrains no row -- `DrilldownList.e`'s three `Has` givens are
       * exactly this, and without the note its rejection is unreadable (design (a4)). */
      headOf(other) match {
        case VarT(h) if h.ty != Skolem =>
          NotRow(Some("`" + render(other) + "`: an application of a type VARIABLE, which " +
            "constrains no row here" + h.name.fold("")(n => " -- is `" + n + "` in scope? " +
            "`Has` lives in `Constraint`") ))
        case _ => NotRow(None)
      }
  }

  /** The procedure's answer.  `NotEntailed` carries everything the message needs and the
    * givens the (a2) satisfiability branch re-decides. */
  sealed abstract class Verdict
  case object Ok extends Verdict
  final case class NotEntailed(label: Option[Name], witness: List[(TypeVar, Boolean)],
                               wanted: Type, minted: List[TypeVar],
                               givens: List[Type], ignored: List[String],
                               qRows: List[(TypeVar, RHS)]) extends Verdict
  final case class NoVerdict(why: String) extends Verdict

  /** Decision nodes, per label class and per signature: the same two-cap shape as
    * `GenRules.rowSoundBudget`/`rowSoundSolveBudget`, and a cap on the number of models of
    * the givens at one class.  Measured over the S2 corpus the maxima were 24,109
    * propagation steps and 256 models at one class, so these are ~8x and ~80x the
    * observed worst case; exhausting either is NO VERDICT, which warns and accepts. */
  private val classBudget: Long = 200000L
  private val sigBudget:   Long = 1000000L
  private val modelLimit:  Int  = 20000

  /** Cost of the last decision, for the S3 measurement (design (b4)): decision nodes,
    * models of `Q` at the widest class, label classes. */
  final case class Cost(nodes: Long, models: Int, classes: Int)
  /** PER THREAD: the checker runs on whatever thread the load is on, and a suite's properties
    * run on a pool, so a process-global `var` hands one property another's measurement (two
    * runs of the cost property differed by 28 nodes before this was a `ThreadLocal`). */
  private val costTL = ThreadLocal.withInitial[Cost](() => Cost(0, 0, 0))
  def lastCost: Cost = costTL.get
  private def lastCost_=(c: Cost): Unit = costTL.set(c)

  /** THE JUDGEMENT, decided.  `qs` are the signature's givens and `rs`/`ds` the two halves
    * of `subsumeType`'s `:541` partition of the body's residual, exactly as that call
    * captured them (design (e) 6: never a re-`substType`d copy, or `qxs`'s freshness
    * invariant -- no wanted can name a given's existential -- is not available).  `sks` is
    * used for ONE thing: telling this signature's own skolems from a FOREIGN one, whose
    * enclosing signature's facts are not in `Q` and which therefore degrades a rejection to
    * NO VERDICT rather than reporting a lie. */
  def check(qs: List[Type], rs: List[Type], ds: List[Type],
            sks: List[TypeVar], pxs: List[TypeVar]): Verdict = {
    /* A constraint the model cannot STATE ((a4), (e) 2b) is DROPPED, by name, and the drop
     * then forbids ONE of the two verdicts -- never both, and never silently:
     *
     *   - a dropped GIVEN weakens `Q`, so there are MORE models to satisfy: an ACCEPT
     *     still holds for the real (stronger) `Q`, a REJECT may be a lie -> NO VERDICT;
     *   - a dropped OBLIGATION (or a dropped `ds` member of the closure) weakens `W`, so a
     *     REJECT still holds for the real (larger) obligation set -- rejection is monotone
     *     in `W`: if some model of `Q` extends to no model of `W0 ⊆ W`, it extends to none
     *     of `W` either -- while an ACCEPT may be a lie -> NO VERDICT.
     *
     * This is design (e) 2b's guarantee ("never a silent merge") with the one-sided verdict
     * that monotonicity licenses, which is strictly more useful than refusing to decide:
     * it is what lets `Time.Signatures.yearFrac365Simple` be REJECTED although its `ds`
     * half contains `(||) <- (f, e)`, a partition with a LITERAL column set on the left
     * that neither `Constraints.RHS` (whose left-hand side is a `TypeVar`) nor Lean's
     * `Constraint` can express.  The encoding that would decide those cases -- a fresh
     * determined variable `z` with `z <- (parts)` and `z <- (C)` -- is an S4 item with a
     * Lean statement of its own. */
    var caveatQ: Option[String] = None   // a dropped given: forbids REJECT
    var caveatW: Option[String] = None   // a dropped obligation: forbids ACCEPT

    // ---- 1. the givens -------------------------------------------------
    val qEnc  = qs.map(q => (q, encode(q)))
    qEnc.foreach { case (_, Unreadable(why)) => if (caveatQ.isEmpty) caveatQ = Some(why)
                   case _ => () }
    val qRows = qEnc.flatMap { case (_, Encoded(rws)) => rws; case _ => Nil }
    val ignored = qEnc.collect { case (_, NotRow(Some(why))) => why } ++
                  qEnc.collect { case (q, Unreadable(why)) => "`" + one(render(q)) + "`: " + why }
    val qv: Set[TypeVar] = qRows.flatMap(_.vars).toSet

    // ---- 2. the obligations, and the closure of design (a3) ------------
    val rEnc = rs.map(r => (r, encode(r)))
    rEnc.foreach { case (_, Unreadable(why)) => if (caveatW.isEmpty) caveatW = Some(why)
                   case _ => () }
    var wRows = rEnc.flatMap { case (_, Encoded(rws)) => rws; case _ => Nil }
    if (wRows.isEmpty)
      return caveatW.fold[Verdict](Ok)(why =>
        NoVerdict("every obligation was dropped as unreadable -- " + why))
    val pxsSet = pxs.toSet
    /* `W` is the closure of `rs` under shared MINTED variables within `ps`: a residual that
     * mentions no skolem still lands in `ds` and can PIN a variable `W` chooses (reviewer
     * F2's witness `ps = {sk <- (f1,f2), f1 <- (f3), f2 <- (f3)}` -- `rs` alone accepts,
     * all of `ps` rejects).  Not all of `ds`: a component sharing no minted variable with
     * any obligation constrains nothing this signature is responsible for. */
    val dsCand = ds.map(d => (d, encode(d))).filter { case (_, e) => !e.isInstanceOf[NotRow] }
    var taken  = Set[Int]()
    var grew   = true
    while (grew) {
      grew = false
      val f = wRows.flatMap(_.vars).filter(v => pxsSet(v) && !qv(v)).toSet
      var i = 0
      while (i < dsCand.length) {
        if (!taken(i)) dsCand(i) match {
          case (d, e) =>
            val shares = e match {
              case Encoded(rws) => rws.exists(_.vars.exists(f))
              case _            => Type.typeVars(d).exists(f)
            }
            if (shares) e match {
              case Encoded(rws) => wRows = wRows ++ rws; taken = taken + i; grew = true
              case Unreadable(why) =>
                // pinned to the obligations and unreadable: drop it, and forbid ACCEPT
                if (caveatW.isEmpty) caveatW = Some(why)
                taken = taken + i
              case _ => ()
            }
        }
        i += 1
      }
    }
    val wv: Set[TypeVar] = wRows.flatMap(_.vars).toSet
    val F: Set[TypeVar]  = wv.filter(v => pxsSet(v) && !qv(v))
    val rigidW: Set[TypeVar] = wv -- F
    /* A skolem of an ENCLOSING signature: rigid (conservative, design (a)) but its own row
     * facts are not in `Q`, so a rejection that leans on it may be a lie.  Named here and
     * consulted only if a refuting model puts a column in one. */
    val foreign: Set[TypeVar] = rigidW.filter(v => v.ty == Skolem && !sks.contains(v) && !qv(v))

    // ---- 3. the label classes ------------------------------------------
    val labels  = (qRows ++ wRows).flatMap(_.conc).distinct.sortBy(_.toString)
    val classes: List[Option[Name]] = labels.map(Some(_)) ++ List(None)
    /* CANONICAL ORDER (S3 review M2).  `LabelSearch` indexes variables in order of FIRST
     * APPEARANCE and searches FALSE-before-TRUE, so WHICH refuting model it finds -- and
     * therefore the witness sentence the user reads -- is a function of the order the
     * constraints and their parts arrive in.  `RHS.abstr` is a `Set` and `rs`/`ds` arrive in
     * whatever order the residual was built, both of which depend on the ids this run happened
     * to mint: two runs of the same compiler printed two different explanations of the same
     * signature (measured on `Wide.Helpers.melt4` and `DrilldownList.cons_Bracket`).  Sorting
     * by RENDERED NAME first and id second makes the sentence a function of the SOURCE. */
    val qTups = canonRows(qRows)
    val wTups = canonRows(wRows)

    var spent      = 0L
    var models     = 0
    var noVerdict: Option[String] = None
    /* EVERY class is decided before anything is reported, and a REJECT at one class OUTRANKS
     * a NO VERDICT at another (design (b3): a refutation at any class refutes the judgement,
     * `lsig_iff_classes`).  So the loop does not stop at a no-verdict, and the per-class
     * no-verdict below is LOCAL -- a global one must not silence the next class's search. */
    for (lab <- classes) {
      val hasLabel: Set[Name] => Boolean = lab match {
        case Some(l) => (fs => fs contains l)
        case None    => (_ => false)
      }
      val left = sigBudget - spent
      val cap  = if (left < classBudget) left else classBudget
      if (cap <= 0) {
        if (noVerdict.isEmpty)
          noVerdict = Some("the signature's decision budget of " + sigBudget +
            " nodes was spent before " + className(lab) + " was decided")
      } else {
        // canonically ordered too: these variables are BRANCHED OVER, so their index order
        // decides which model the search reaches first
        val extra = (rigidW -- qv).toList.sortBy(canonVar)
        val qe = new Constraints.LabelSearch(qTups, hasLabel, extra, cap)
        val proj = qe.indicesOf(rigidW)
        val ms   = scala.collection.mutable.ListBuffer[List[(TypeVar, Boolean)]]()
        val seen = scala.collection.mutable.HashSet[List[(Int, Boolean)]]()
        qe.rootPropagate()
        val complete =
          if (qe.conflicted) true   // no model of the givens at this class: nothing to check
          else qe.enumerate(qe.everyVar, modelLimit) { e =>
            val key = proj.toList.map(i => (e.varAt(i).id, e.bitAt(i) == 1))
            if (seen.add(key))
              ms += proj.toList.map(i => (e.varAt(i), e.bitAt(i) == 1))
          }
        spent += qe.nodesUsed
        models = math.max(models, ms.length)
        if (!complete) {
          if (noVerdict.isEmpty)
            noVerdict = Some("the models of the signature's own constraints at " +
              className(lab) + " could not be enumerated within " + cap + " decisions")
        } else {
          /* THE PER-CLASS CAP, not the whole remaining signature budget (design (b3): two
           * caps, one per label class and one per signature, so a wide signature cannot spend
           * `#classes x` the first).  `blame`'s own little searches are charged to the class
           * too, through `spent`. */
          val we = new Constraints.LabelSearch(wTups, hasLabel, Nil,
                                               math.min(cap, sigBudget - spent))
          var bad: Option[List[(TypeVar, Boolean)]] = None
          var classNoVerdict: Option[String] = None
          val it = ms.iterator
          while (it.hasNext && bad.isEmpty && classNoVerdict.isEmpty) {
            val m = it.next()
            we.reset()
            val ok = we.freeze(m) && we.searchSat(we.everyVar)
            if (!ok) {
              if (we.exhausted)
                classNoVerdict = Some("the obligations at " + className(lab) +
                  " could not be decided within " + (sigBudget - spent) + " decisions")
              else if (we.checkFailed)
                classNoVerdict = Some("a complete assignment failed its own check at " +
                  className(lab) + "; no verdict is claimed")
              else bad = Some(m)
            }
          }
          spent += we.nodesUsed
          if (noVerdict.isEmpty) noVerdict = classNoVerdict
          bad match {
            case Some(m) =>
              val ones = m.filter(_._2).map(_._1).toSet
              /* THE WHOLE VOCABULARY OF THE MODEL, not only its 1-bits (S3 review D4): a
               * model that puts the column OUTSIDE a foreign skolem is just as unjustified as
               * one that puts it inside, because the enclosing signature's row facts are
               * absent from `Q` either way.  Design (a) says "if the refuting model ASSIGNS
               * such a variable", and every variable of `m` is assigned. */
              val used = m.map(_._1).filter(foreign)
              if (used.nonEmpty) {
                if (noVerdict.isEmpty)
                  noVerdict = Some("the counterexample the check found assigns " +
                    used.sortBy(canonVar).map(varShort).mkString(", ") + ", which belongs to " +
                    "an ENCLOSING signature whose own constraints are not visible here, so " +
                    "no verdict is claimed (another model might refute the judgement without " +
                    "it; the check does not look for one)")
              } else if (caveatQ.isDefined) {
                if (noVerdict.isEmpty)
                  noVerdict = Some("an obligation is not entailed by the givens the check " +
                    "could read, but one given was dropped as unreadable, so the real " +
                    "context may be stronger -- " + caveatQ.get)
              } else {
                lastCost = Cost(spent, models, classes.length)
                return NotEntailed(lab, m, blame(wRows, hasLabel, m, ones).src,
                                   F.toList.sortBy(_.id), qs, ignored, qTups)
              }
            case None => ()
          }
        }
      }
    }
    lastCost = Cost(spent, models, classes.length)
    noVerdict orElse caveatW.map(why =>
      "every class the check could build is satisfied, but an obligation was dropped as " +
      "unreadable, so the real obligation set may be larger -- " + why) match {
      case Some(why) => NoVerdict(why)
      case None      => Ok
    }
  }

  private def className(lab: Option[Name]): String =
    lab.fold("the generic column class")(l => "the column `" + l + "`")

  /** WHICH obligation to blame: the first one that is unsatisfiable on its own under the
    * refuting model, else the first one the model's true variables occur in, else the
    * first. */
  private def blame(ws0: List[Row], hasLabel: Set[Name] => Boolean,
                    m: List[(TypeVar, Boolean)], ones: Set[TypeVar]): Row = {
    // canonical order here too, or WHICH obligation the message names depends on the ids
    val ws = ws0.sortBy(r => canonKey(canonTup(r)))
    val alone = ws.find { r =>
      val e = new Constraints.LabelSearch(List(r.tup), hasLabel, Nil, 10000L)
      !(e.freeze(m) && e.searchSat(e.everyVar))
    }
    alone orElse ws.find(_.vars.exists(ones)) getOrElse ws.head
  }

  private def varShort(v: TypeVar): String = v.name.fold("_" + v.id)(_.toString)

  /* CANONICAL ORDER (S3 review M2).  `LabelSearch` indexes variables in order of FIRST
   * APPEARANCE and searches FALSE-before-TRUE, so WHICH refuting model it finds -- and
   * therefore the witness sentence the user reads, and which obligation `blame` picks -- is a
   * function of the order the constraints and their parts arrive in.  `RHS.abstr` is a `Set`
   * and `rs`/`ds` arrive in whatever order the residual was built, both of which depend on the
   * ids this run happened to mint: two runs of the same compiler printed two different
   * explanations of the same signature (measured on `Wide.Helpers.melt4` and
   * `DrilldownList.cons_Bracket`).  Sorting by RENDERED NAME first and id second makes the
   * whole diagnostic a function of the SOURCE. */
  private def canonVar(v: TypeVar): (String, Int) = (varShort(v), v.id)
  private def canonTup(r: Row): (TypeVar, RHS) =
    (r.v, RHS(scala.collection.immutable.SortedSet.empty[TypeVar](Ordering.by(canonVar)) ++
              r.rhs.abstr, r.rhs.concr))
  private def canonKey(t: (TypeVar, RHS)): String =
    varShort(t._1) + "^" + t._1.id + " <- (" +
    t._2.abstr.toList.map(v => varShort(v) + "^" + v.id).mkString(",") + ";" +
    t._2.concr.toList.map(_.toString).sorted.mkString(",") + ")"
  private def canonRows(rs0: List[Row]): List[(TypeVar, RHS)] = rs0.map(canonTup).sortBy(canonKey)

  /* ------------------------------------------------------------------ *
   *  S3: THE DIAGNOSTIC                                                 *
   * ------------------------------------------------------------------ */

  private def file(x: Loc): Option[String] = x match {
    case Pos(fn, _, _, _, _)           => Some(fn)
    case Inferred(Pos(fn, _, _, _, _)) => Some(fn)
    case _                             => None
  }

  /** DISPLAY NAMES for one sentence, containing NO ids.
    *
    * Two problems at once.  A minted variable carries the name it was refreshed FROM, so one
    * sentence can mention two different `r`s -- the signature's own and the solver's copy --
    * and an earlier draft disambiguated them with `^id`, which made the sentence depend on
    * the ids the run happened to mint (S3 review M2: two runs printed two explanations of one
    * signature).  A variable with no name at all printed as `_1011728`, the same problem in
    * its purest form.  So: a name the solver copied gets a PRIME, a nameless variable gets a
    * positional `_1`, `_2`, and nothing carries an id.  The order is canonical (name, then id)
    * with the nameless ones last, so the STRING is the same however the ids fall -- two
    * nameless variables swapping places produce the same text. */
  private def displayNames(m: List[(TypeVar, Boolean)], minted: List[TypeVar]): Map[Int, String] = {
    val vs    = (m.map(_._1) ++ minted).distinct
    val mintS = minted.map(_.id).toSet
    val named = vs.filter(_.name.isDefined).sortBy(v => (v.name.get.toString, v.id))
    val anon  = vs.filterNot(_.name.isDefined).sortBy(_.id)
    var used  = Set[String]()
    val out   = scala.collection.mutable.HashMap[Int, String]()
    named.foreach { v =>
      var n = v.name.get.toString + (if (mintS(v.id)) "'" else "")
      while (used(n)) n = n + "'"
      used = used + n
      out(v.id) = n
    }
    anon.zipWithIndex.foreach { case (v, i) => out(v.id) = "_" + (i + 1) }
    out.toMap
  }

  /** How many of the solver's own variables to name before saying "and N more": the minted set
    * reaches 35 on `Layout.Report.Relation.cutoffs` and 32 on `Wide.Helpers.melt4`, and a list
    * that long buries the sentence it is part of (S3 review M4). */
  private val mintedShown = 6

  /** The witness, in prose and in the source's own names (design (d3), checklist 10). */
  private def prose(lab: Option[Name], m: List[(TypeVar, Boolean)], minted: List[TypeVar]): String = {
    val nms  = displayNames(m, minted)
    def nm(v: TypeVar): String = nms.getOrElse(v.id, varShort(v))
    val ones = m.filter(_._2).map(p => nm(p._1)).sorted
    val zero = m.filterNot(_._2).map(p => nm(p._1)).sorted
    val cls  = lab.fold("a column named nowhere in the signature")(l => "the column `" + l + "`")
    val take =
      if (ones.isEmpty) "take " + cls + " to be in none of the signature's rows (" +
                        (if (zero.isEmpty) "it has none" else zero.mkString(", ")) + ")"
      else "take " + cls + " to be in " + ones.mkString(" and in ") +
           (if (zero.isEmpty) "" else ", and in none of " + zero.mkString(", "))
    val ms = minted.map(nm).sorted
    take + " -- the givens allow that, and no choice of " +
      (if (ms.isEmpty) "anything"
       else (if (ms.length <= mintedShown) ms.mkString(", ")
             else ms.take(mintedShown).mkString(", ") + " and " + (ms.length - mintedShown) +
                  " more") +
            " (the solver's own, which may be any rows)") + " then satisfies the wanted"
  }

  /** The rejection, as the two-location message of design (d3).  PRIMARY is the
    * obligation's own position when it is in the file being compiled -- a large share of
    * wanteds carry a builtin or another module's position, and an error whose only position
    * is in the stdlib is the failure mode `labelCheckEarly` was declined for on 2026-09-01
    * -- else the signature itself, with the foreign position quoted in the body.  SECONDARY
    * is always "declared at", the site's own `Loc`. */
  private def lines(site: Site, v: NotEntailed, here: Option[String]): (Loc, String, List[String]) = {
    val wl    = v.wanted.loc
    val there = file(wl)
    val primary = if (there.isDefined && there == here) wl else site.loc
    val head  = "the signature does not entail this row constraint"
    val body  = List(
      "    wanted   " + one(render(v.wanted)) +
        (if (primary eq site.loc) "   (required at " + posOf(wl) + ")" else ""),
      "    given    " + (if (v.givens.isEmpty) "(none)" else one(v.givens.map(render).mkString(";  "))),
      "  no rows satisfying the givens satisfy it: " + prose(v.label, v.witness, v.minted)) ++
      v.ignored.map(i => "  ignored given  " + i) ++
      List("  declared at " + posOf(site.loc) + " (" + site.kind + " " + site.binding + ")")
    (primary, head, body)
  }

  /** THE ENTRY POINT, called from `Subst.subsumeType` for a user signature only.  `off`
    * never reaches it (no `Site` is allocated). */
  def enforce(site: Site, qs: List[Type], rs: List[Type], ds: List[Type],
              sks: List[TypeVar], pxs: List[TypeVar])
             (implicit hm: SubstEnv, tml: Located): Unit = {
    val mode = hm.sigEntail
    if (!mode.on || rs.isEmpty) return
    if (mode == Warn) probe(site, qs, rs, ds)
    val here = file(tml.loc)
    check(qs, rs, ds, sks, pxs) match {
      case Ok => ()
      case NoVerdict(why) =>
        /* Never a silent pass: the `rowSound` no-verdict line (Subst.scala:1477) is the
         * precedent and the wording.  A no-verdict ACCEPTS -- under `error` too, which is
         * why `error` is not a guarantee. */
        System.err.println("warning: the signature-entailment check gave NO VERDICT at " +
          posOf(site.loc) + " (" + site.kind + " " + site.binding + ": " + why +
          "); this signature is accepted on the shipped rules alone")
      case v: NotEntailed =>
        /* (a2): the judgement is VACUOUSLY true when the givens have no model, and the
         * per-label reading is then strictly stronger, so the rejection may not be
         * reported as the body's fault.  Decide the givens ONCE, on this path only, and
         * branch on all THREE verdicts. */
        Constraints.labelDecide(v.qRows, 200000, sigBudget).verdict match {
          case Constraints.LabelSat =>
            val (primary, head, body) = lines(site, v, here)
            if (mode == Error) Subst.sourcePosition(primary).die(text(head), body.map(text): _*)
            else System.err.println(Subst.sourcePosition(primary)
              .report(text("warning: " + head), body.map(text): _*).toString)
          case Constraints.LabelRefuted(lbl, _, why) =>
            val head = "the signature's constraints have no solution: no call can satisfy them"
            val body = List(
              "    given    " + (if (qs.isEmpty) "(none)" else one(qs.map(render).mkString(";  "))),
              "  at the column `" + lbl + "`: " + why,
              "  the body is not blamed: this signature cannot be instantiated at all",
              "  declared at " + posOf(site.loc) + " (" + site.kind + " " + site.binding + ")")
            if (mode == Error) Subst.sourcePosition(site.loc).die(text(head), body.map(text): _*)
            else System.err.println(Subst.sourcePosition(site.loc)
              .report(text("warning: " + head), body.map(text): _*).toString)
          case Constraints.LabelNoVerdict(lbl, why, _) =>
            /* NEITHER claim may be made: "not entailed" needs the givens to be
             * satisfiable, and "no solution" needs them refuted. */
            System.err.println("warning: the signature-entailment check gave NO VERDICT at " +
              posOf(site.loc) + " (" + site.kind + " " + site.binding +
              ": an obligation is not entailed, but whether the signature's own constraints " +
              "have a solution could not be decided at the column `" + lbl + "`: " + why +
              "); this signature is accepted on the shipped rules alone")
        }
    }
  }
}
