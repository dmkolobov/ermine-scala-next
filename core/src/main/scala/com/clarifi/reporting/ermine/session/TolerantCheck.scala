package com.clarifi.reporting
package ermine.session

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.ImplicitBinding.implicitBindingComponents
import com.clarifi.reporting.ermine.Term.termVars
import com.clarifi.reporting.ermine.HasTermVars._
import com.clarifi.reporting.ermine.Subst.{
  assertTypeClosed, inferImplicitBindingTypes, toGamma, typeCheckExplicitBinding, unbindAnnot }
import com.clarifi.reporting.ermine.syntax._
import com.clarifi.reporting.ermine.syntax.TypeDef.typeDefComponents
import com.clarifi.reporting.ermine.parsing.ParseState
import scalaparsers.{ Death, Document, Supply }

/** EDITOR-PATH type checking (tracker/LSP-ROADMAP.md item 5.4).
  *
  * Session.loadModule type checks a module the way a batch load must:
  * the first Death ends it, and nothing is reported after.  An editor
  * wants the opposite — every independent problem at once, and the
  * healthy definitions of a broken file still checked — so this is a
  * SEPARATE entry point beside loadModule, never a flag inside it
  * (Stage-2 invariant: batch semantics are frozen).  It installs
  * nothing: the caller runs it against a session copy that is thrown
  * away, so partial results can never reach a real session.
  *
  * The one structural thing it does differently, and the reason it is
  * not just loadModule in a try: EACH BINDING SCC INFERS IN ITS OWN
  * SubstEnv.  A Death part-way through a component leaves that
  * component's half-solved meta bindings in a shared SubstEnv, and
  * those metas are shared with module-wide placeholder Vs — so every
  * LATER component would be inferred against them and report
  * consequences of the first error rather than its own.  Only the
  * generalized `subs` crosses a component boundary, which is the
  * structure inferBindingGroupTypes already has.
  *
  * A component that fails, and TRANSITIVELY any component depending on
  * one that failed or was skipped, is reported "unchecked: depends on a
  * broken definition".  Inferring it anyway against unconstrained metas
  * would typecheck to lies.
  */
object TolerantCheck {

  /** LSP severities. */
  val Error       = 1
  val Information = 3

  /** One note.  `report` is rendered the way every Death is — leading
    * "file:line:col:" — so the caller maps it to a position the same
    * way.  `spelling` is set on undefined-term notes, which the editor
    * suppresses when a broken statement defines that name (5.4). */
  final case class Note(report: String, severity: Int, spelling: Option[String] = None)

  /** `types` maps a top-level binding's spelling to the type checking
    * gave it — inferred for implicits, declared for explicits.  It is
    * what hover reads now that the editor path no longer runs a real
    * load to put the module in the session. */
  final case class Result(notes: List[Note], types: Map[String, Type])

  def check(ps: ParseState, m: Module)(implicit s: SessionEnv, su: Supply): Result = {
    val notes = scala.collection.mutable.ListBuffer.empty[Note]

    def guard[A](sev: Int)(body: => A): Option[A] =
      try Some(body)
      catch {
        case Death(e, _) => notes += Note(e.toString, sev); None
        case scala.util.control.NonFatal(e) =>
          notes += Note("error: " + Option(e.getMessage).getOrElse(e.toString), sev); None
      }

    val mod = m.name
    var maps: Session.Maps = (Type.conMap(m.name, ps.s.typeNames, s.cons), Map(): Map[TermVar, TermVar])

    // The statement phases, one unit at a time: a data declaration that
    // will not kind-check must not take the module's terms with it.
    def phase[A](xs: List[A])(f: (Session.Maps, A) => Session.Maps): Unit =
      xs.foreach { x => guard(Error) { maps = f(maps, x) } }

    phase(m.fields)(Session.processFieldStatement(mod, ps))
    phase(m.foreignData)(Session.processForeignDataStatement(mod))
    phase(typeDefComponents(m.types))(Session.processTypeDefComponent(mod))
    phase(m.foreigns) { (cm, cs) => cs match {
      case x: ForeignFunctionStatement    => Session.processForeignFunctionStatement(mod)(cm, x)
      case x: ForeignMethodStatement      => Session.processForeignMethodStatement(mod)(cm, x)
      case x: ForeignValueStatement       => Session.processForeignValueStatement(mod)(cm, x)
      case x: ForeignConstructorStatement => Session.processForeignConstructorStatement(mod)(cm, x)
      case x: ForeignSubtypeStatement     => Session.processForeignSubtypeStatement(mod)(cm, x)
    } }
    phase(m.tables)(Session.processTableStatement(mod))

    val is = Session.subTermMaps(maps, m.implicits).map(_.close).toList
    val es = Session.subTermMaps(maps, m.explicits).map(_.close).toList
    val bs: List[Binding] = is ++ es

    // Undefined terms, one note each rather than one Death listing them
    // all (assertTermClosed's shape).  A binding that mentions one cannot
    // be checked, so it counts as failed — but silently: the undefined
    // term IS the explanation, and "unchecked" on top of it is noise.
    val free = (termVars(bs) -- (s.env.keySet ++ bs.map(_.v))).toSet
    free.foreach { v =>
      notes += Note(v.report(Document.text("error: undefined term")).toString,
                    Error, v.name.map(_.string))
    }
    guard(Error) { assertTypeClosed(bs) }

    val preFailed = bs.collect { case b if termVars(b.alts).exists(free) => b.v }.toSet
    var failed: Set[TermVar] = preFailed

    def unchecked(b: Binding): Unit =
      notes += Note(b.loc.report(Document.text(
        "unchecked: depends on a broken definition")).toString, Information)

    // The explicit annotations, so implicit components referring to an
    // annotated binding see its DECLARED type rather than a meta.
    val etm: Map[TermVar, Type] = Session.subst { implicit hm =>
      es.flatMap { e =>
        guard(Error) { e.v -> unbindAnnot(Nil, e.ty)._3 }
      }.toMap
    }
    val em  = etm map { case (v, t) => (v, v as t) }
    val esp = es.map(e => e.subst(Map(), Map(), em))
    val isp = is.map(i => i.subst(Map(), Map(), em))

    var subs: Map[TermVar, TermVar] = Map()
    implicitBindingComponents(isp) foreach { comp =>
      val vs   = comp.map(_.v).toSet
      val refs = comp.flatMap(b => termVars(b.alts).toList).toSet
      if ((refs & failed).nonEmpty || (vs & preFailed).nonEmpty) {
        if ((vs & preFailed).isEmpty) comp.foreach(unchecked)
        failed = failed ++ vs
      } else
        // A FRESH SubstEnv per component (see the class comment).
        guard(Error) {
          Session.subst { implicit hm =>
            val (ds, sub) = inferImplicitBindingTypes(m.loc, toGamma(subs),
                                                      Term.subTerm(subs, comp), true)
            for (d <- ds) if (!d.isTrivialConstraint) d.die("non-trivial top level constraint")
            sub
          }
        } match {
          case Some(sub) => subs = subs ++ sub
          case None      => failed = failed ++ vs
        }
    }

    // The explicits check per binding, each in its own SubstEnv too.
    esp foreach { e =>
      val refs = termVars(e.alts).toSet
      if ((refs & failed).nonEmpty) { if (!preFailed(e.v)) unchecked(e) }
      else if (etm contains e.v)
        guard(Error) {
          Session.subst { implicit hm =>
            typeCheckExplicitBinding(Nil, Term.subTerm(subs, e))
          }
        }
    }

    val types =
      (subs.flatMap { case (v, v2) => v.name.map(_.string -> v2.extract) } ++
       etm.flatMap  { case (v, t)  => v.name.map(_.string -> t) }).toMap
    Result(notes.toList, types)
  }
}
