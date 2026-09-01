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
import com.clarifi.reporting.ermine.surface.StatementExtents
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
  final case class Result(notes: List[Note], types: Map[String, Type],
                          reused: Int = 0, components: Int = 0)

  /** Per-uri inference reuse (roadmap 5.5).  `scopeKey` covers
    * everything an SCC's inference depends on beyond its own text: the
    * imports, the scope-bearing statements, the top-level head set, and
    * the versions of the OTHER open buffers (a sibling's unsaved edit
    * changes what an import means).  When it moves, the whole map goes:
    * conservative and correct beats clever.
    *
    * `entries` is keyed by an SCC fingerprint — its bindings' source
    * text INCLUDING their start lines, plus the fingerprints of the
    * module-local groups it references.  Fingerprints rather than
    * inferred types because they are alpha-invariant by construction:
    * every V in a fresh run has a fresh id, so a type rendering would
    * be a moving target.  Start lines are in the key so a REUSED entry
    * can never carry a note or a type whose Locs have drifted; note-
    * bearing components are not cached at all, for the same reason. */
  final case class Cache(scopeKey: String, entries: Map[String, Map[String, Type]]) {
    def isEmpty: Boolean = entries.isEmpty
    def size: Int = entries.size
  }
  object Cache { val empty = Cache("", Map()) }

  /** Statement heads whose EDIT changes what every other statement
    * means, so the whole per-uri cache goes.  `private` and `database`
    * are here because their bodies are not top-level items, so nothing
    * inside one can be fingerprinted on its own. */
  private val ScopeWords = Set(
    "import", "export", "type", "data", "class", "instance", "field", "table",
    "foreign", "private", "database", "abstract",
    "infixl", "infixr", "infix", "prefix", "postfix")

  /** The two fingerprint inputs, derived from the source: the per-group
    * texts and the scope key.  A group is one top-level spelling's own
    * statements, sig and equations together — the invalidation unit,
    * since they pair module-wide by shared V — with START LINES in the
    * text, so a reused result can never carry positions that have
    * drifted.  `workspaceKey` is the caller's business: the LSP puts
    * the OTHER open buffers' versions in it, because a sibling's
    * unsaved edit changes what an import means. */
  def keys(contents: String, moduleName: String, importsKey: String,
           workspaceKey: String): (Map[String, String], String) = {
    val scan = StatementExtents.scan(contents)
    // One index for the whole run.  This makes two position lookups per
    // top-level statement, and each of them used to re-walk the file from
    // offset 0 -- 4.7% of the editor round trip (roadmap P5(a)).
    val off = new StatementExtents.Offsets(contents)
    val (scopeItems, bindItems) = scan.items partition (x => ScopeWords(x.headWord))
    val groups = bindItems.filter(_.headWord.nonEmpty).groupBy(_.headWord).map {
      case (w, xs) => w -> xs.map(x =>
        x.startLine + ":" + off.text(x)).mkString("\u0000")
    }
    val scopeKey = fingerprint(
      moduleName, importsKey,
      scopeItems.map(off.text).mkString("\u0000"),
      bindItems.map(_.headWord).sorted.mkString(","),
      workspaceKey)
    (groups, scopeKey)
  }

  def check(ps: ParseState, m: Module)(implicit s: SessionEnv, su: Supply): Result =
    checkWith(ps, m, Map(), "", Cache.empty)._1

  /** As `check`, reusing (and rebuilding) per-SCC inference results.
    * `groups` maps a top-level spelling to the source text of its
    * statements — sig and equations together, since they are one
    * invalidation unit (module-wide pairing by shared V: a sig edit
    * changes its group's ExplicitBinding without touching the head
    * set).  A spelling missing from `groups` — an operator, anything
    * the extent scanner cannot name — is simply never cached. */
  def checkWith(ps: ParseState, m: Module,
                groups: Map[String, String], scopeKey: String, cache: Cache)
               (implicit s: SessionEnv, su: Supply): (Result, Cache) = {
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

    // --- per-SCC reuse (5.5) -------------------------------------------
    // A group's fingerprint is its own text plus the fingerprints of the
    // module-local groups it references, so a change anywhere upstream
    // reaches everything downstream.  Explicit bindings are groups too:
    // their annotation is what their dependents were inferred against.
    def spelling(v: TermVar): Option[String] = v.name.map(_.string)
    val localFp = scala.collection.mutable.Map.empty[String, String]
    es.foreach { e =>
      for (sp <- spelling(e.v); text <- groups.get(sp)) localFp += sp -> fingerprint("sig", sp, text)
    }
    def fpOf(comp: List[ImplicitBinding], refs: Set[TermVar]): Option[String] = {
      val sps = comp.flatMap(b => spelling(b.v))
      if (sps.size != comp.size) None
      else {
        val texts = sps.map(groups.get)
        if (texts.exists(_.isEmpty)) None
        else {
          val upstream = refs.toList.flatMap(spelling).flatMap(localFp.get).sorted
          Some(fingerprint(("scc" :: sps.sorted ::: texts.flatten ::: upstream): _*))
        }
      }
    }

    val reusable = cache.scopeKey == scopeKey && scopeKey.nonEmpty
    val fresh = scala.collection.mutable.Map.empty[String, Map[String, Type]]
    var reused = 0

    var subs: Map[TermVar, TermVar] = Map()
    var components = 0
    implicitBindingComponents(isp) foreach { comp =>
      val vs   = comp.map(_.v).toSet
      val refs = comp.flatMap(b => termVars(b.alts).toList).toSet
      val fp   = fpOf(comp, refs)
      components += 1
      fp foreach { f => comp.foreach(b => spelling(b.v) foreach (localFp += _ -> f)) }

      def hit: Option[Map[String, Type]] =
        if (!reusable) None else fp.flatMap(cache.entries.get)

      if ((refs & failed).nonEmpty || (vs & preFailed).nonEmpty) {
        if ((vs & preFailed).isEmpty) comp.foreach(unchecked)
        failed = failed ++ vs
      } else hit match {
        case Some(tys) if comp.forall(b => spelling(b.v).exists(tys.contains)) =>
          // Only NOTE-FREE components are ever cached, so a hit adds
          // nothing to report and nothing whose Locs could have drifted.
          comp foreach { b => spelling(b.v) foreach { sp => subs = subs + (b.v -> b.v.as(tys(sp))) } }
          fp foreach { f => fresh += f -> tys }
          reused += 1
        case _ =>
          val before = notes.length
          // A FRESH SubstEnv per component (see the class comment).
          guard(Error) {
            Session.subst { implicit hm =>
              val (ds, sub) = inferImplicitBindingTypes(m.loc, toGamma(subs),
                                                        Term.subTerm(subs, comp), true)
              for (d <- ds) if (!d.isTrivialConstraint) d.die("non-trivial top level constraint")
              sub
            }
          } match {
            case Some(sub) =>
              subs = subs ++ sub
              if (notes.length == before) fp foreach { f =>
                fresh += f -> comp.flatMap(b => spelling(b.v).flatMap(sp =>
                  sub.get(b.v).map(sp -> _.extract))).toMap
              }
            case None => failed = failed ++ vs
          }
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

    // A foreign declaration binds a top-level name with a type written out in
    // the statement, but it is neither an implicit nor an explicit binding, so
    // neither map above holds it and hover on `dateAdd#` came back empty.  No
    // inference is involved -- take the declared type as written.
    val foreignTypes: List[(String, Type)] = m.foreigns.flatMap {
      case ForeignFunctionStatement(_, v, t, _, _)  => v.name.map(_.string -> t)
      case ForeignMethodStatement(_, v, t, _)       => v.name.map(_.string -> t)
      case ForeignValueStatement(_, v, t, _, _)     => v.name.map(_.string -> t)
      case ForeignConstructorStatement(_, v, t)     => v.name.map(_.string -> t)
      case ForeignSubtypeStatement(_, v, t)         => v.name.map(_.string -> t)
      case _                                        => None
    }

    val types =
      (subs.flatMap { case (v, v2) => v.name.map(_.string -> v2.extract) } ++
       etm.flatMap  { case (v, t)  => v.name.map(_.string -> t) } ++
       foreignTypes).toMap
    (Result(notes.toList, types, reused, components), Cache(scopeKey, fresh.toMap))
  }

  def fingerprint(parts: String*): String = {
    val md = java.security.MessageDigest.getInstance("SHA-1")
    parts foreach { p => md.update(p.getBytes("UTF-8")); md.update(0: Byte) }
    md.digest().map("%02x".format(_)).mkString
  }
}
