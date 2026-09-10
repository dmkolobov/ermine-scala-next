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
import com.clarifi.reporting.ermine.surface.{ Span, StatementExtents }
import com.clarifi.reporting.ermine.parsing.ParseState
import scalaparsers.{ Death, Document, Pos, Supply }

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
  val Warning     = 2
  val Information = 3

  /** One note.  `report` is rendered the way every Death is — leading
    * "file:line:col:" — so the caller maps it to a position the same
    * way.  `spelling` is set on undefined-term notes, which the editor
    * suppresses when a broken statement defines that name (5.4).
    * `dependsOnBroken` marks the "unchecked" notes, which the editor
    * suppresses for the same reason and in the same places — a name
    * that never arrived (a broken statement, a failed import) explains
    * itself, and its consequences are noise (6.1(b)).  Both are FLAGS
    * rather than message matching: the caller must not have to parse
    * rendered report text to know what kind of note it holds. */
  final case class Note(report: String, severity: Int, spelling: Option[String] = None,
                        span: Option[Span] = None, dependsOnBroken: Boolean = false)

  /** `types` maps a top-level binding's spelling to the type checking
    * gave it — inferred for implicits, declared for explicits.  It is
    * what hover reads now that the editor path no longer runs a real
    * load to put the module in the session.
    *
    * `locals` (6.2) maps a LOCAL binder's def-site — (line, column) of
    * the renamer's `BinderInfo.defSite`, which is the `Pos` Lower gave
    * the binder's `V` — to the type inference gave it, zonked inside the
    * component's own `SubstEnv`.  Only `checkWith(wantLocals = true)`
    * fills it, and only for the binders `collectLocals` can reach. */
  /** What hover needs for ONE local binder: the type to print, and — for
    * an ARGUMENT recovered from its binding's own type (6.2 option 4) —
    * the binding type whose letters it must agree with.  See
    * `Pretty.prettyTypeIn`: without the second field, hovering `g` and
    * hovering `g`'s second argument would both start their letters at
    * `a` and tell the reader that two different variables are one. */
  final case class LocalTy(ty: Type, scope: Option[Type] = None)

  final case class Result(notes: List[Note], types: Map[String, Type],
                          reused: Int = 0, components: Int = 0,
                          locals: Map[(Int, Int), LocalTy] = Map())

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
  final case class Cache(scopeKey: String, entries: Map[String, Entry]) {
    def isEmpty: Boolean = entries.isEmpty
    def size: Int = entries.size
  }
  object Cache { val empty = Cache("", Map()) }

  /** What one cached component carries: the types its top-level
    * bindings were given, and (6.2, Decision b) the LOCAL binder types
    * collected inside the same `Session.subst` block.
    *
    * A reused entry's local positions cannot have drifted, for the same
    * reason its notes and types cannot: the entry's key is a fingerprint
    * of the group's whole SOURCE TEXT INCLUDING ITS START LINES (`keys`
    * above), and every top-level statement starts at column 1.  So an
    * edit that moves any def-site inside the group — a line inserted
    * above it, a character inserted before it on its own line — changes
    * the group's text or its start line, hence its fingerprint, hence
    * the key; and an edit ABOVE the group moves the group's own start
    * line, which is in the key too.  A hit therefore means every byte
    * and every line number inside the group is what it was. */
  final case class Entry(types: Map[String, Type], locals: Map[(Int, Int), LocalTy])

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

  /** 6.2: the LOCAL binder types of one already-inferred component,
    * zonked in that component's `SubstEnv`, keyed by def-site.
    *
    * WHICH BINDERS ARE REACHABLE, and why it is not all of them.  Lower
    * gives every renamer binder id ONE `V[Type]` whose `loc` is the
    * def-site `Pos` and whose type is a fresh meta (`Lower.Ctx.binderV`,
    * `unspecified`).  That meta is what a zonk reads.  Inference
    * constrains it for a binder that reaches the checker AS A BINDING
    * HEAD: `Subst.inferImplicitBindingTypes` does `subsumeType(
    * substType(b.v.extract), rp)`, so the head's own meta IS the solved
    * type.  That covers `let` and `where` heads (Renamer LetBound /
    * WhereBound) at every depth, and the module's top levels.
    *
    * It does NOT cover PATTERN binders — Arg, CaseBound, DoBound, and
    * the vars inside a constructor or product pattern.  Lower drops the
    * binder's meta when it builds the pattern (`VarP(v.map(_ =>
    * annotOf(...)))`, Lower.scala): the pattern var carries an `Annot`,
    * and for an unsigned binder that annot is the shared
    * `Annot.annotAny` (`exists a. a`, `Loc.builtin`, id -1).
    * `Subst.inferPatternType` then mints a FRESH meta per occurrence of
    * the pattern (`unbindAnnot` refreshes the existential) and
    * substitutes it into a LOCAL COPY of the alt body
    * (`inferAltTypesPrime`; `inferType`'s `Lam` case even refreshes the
    * bound vars' ids).  Nothing writes that meta back to a `V` this side
    * can see, so `substType` on the binder's own meta returns an
    * unconstrained variable — not the binder's type, and worse than
    * silence.  Making them reachable needs a recording hook where the
    * type exists, which is `Subst.inferPatternType`: out of scope for
    * this item by its brief (no `Subst.scala` change), written up in
    * tracker/loopmodel/LSP3-6.2-LOCALS.md.
    *
    * A SIGNED pattern binder is the exception and is collected: `\(x :
    * Int) -> ...` lowers to a `VarP` whose annot IS the declared type
    * (Lower's `SPSig` case), so it needs no inference at all — Decision
    * (a)'s "explicit local signatures show as declared", straight from
    * the tree.  `annotAny` is told apart by its id (-1), which nothing
    * else mints.
    *
    * `file` gates the record to THIS module: a `V` relocated to another
    * file, and anything at `Loc.builtin` or `Inferred`, is not a
    * def-site here. */
  private def collectLocals(bs: List[Binding], file: String,
                            published: TermVar => Option[Type])
                           (implicit hm: SubstEnv, su: Supply): Map[(Int, Int), LocalTy] = {
    val out = scala.collection.mutable.Map.empty[(Int, Int), LocalTy]

    def record(l: scalaparsers.Loc, t: => LocalTy): Unit = l match {
      case p: Pos if p.fileName == file => out += (p.line, p.column) -> t
      case _ => ()
    }

    /** A binding head: an IMPLICIT one reads its own meta, which
      * inference subsumed against the inferred type; an EXPLICIT one
      * reads its DECLARATION, which is what Decision (a) asks for and
      * needs no inference at all — `Subst.inferBindingGroupTypes` type
      * checks a COPY carrying the declared type and leaves this tree's
      * `V` holding Lower's untouched meta, so the meta is not an option
      * here.  A local explicit binding is what `assemble`'s `lowerLet`
      * makes of a SIGNED `let`/`where` binding (NewPipeline.scala:
      * `pairSigs`). */
    def headType(b: Binding): Type = b match {
      case e: ExplicitBinding => Subst.substType(e.ty.body)
      case i                  => Subst.substType(i.v.extract)
    }

    def binding(b: Binding): Unit = record(b.v.loc, LocalTy(headType(b)))

    /** 6.2 option 4 (review R-2): an EQUATION's argument types, by
      * arithmetic on the type this binding already has.  `b.arity` is how
      * many patterns each alt carries, and the head's type is an arrow
      * chain whose first `arity` domains ARE those arguments, in order.
      * No `Subst` change, no second inference — a reconstruction from the
      * checker's own answer.
      *
      * CONSERVATIVE BY CONSTRUCTION, because a wrong type is worse than
      * none: the quantifier is peeled STRUCTURALLY (never `unbind`, which
      * would mint fresh metas and break the letter agreement below), type
      * aliases are expanded on the way down, and if the chain does not
      * yield `arity` arrows — an alias that hides one — NOTHING is
      * recorded for that binding.  A CONSTRAINT does not stop the split
      * (it lives in the Forall's `q`, not in the arrow chain, so the
      * domains are still right).  A RANK-N argument would come out as a
      * `forall` type on a local, which Decision (a) forbids: a domain
      * that is not `mono` is skipped for that binder only (6.2 review
      * S-2), the same test `Subst` uses for this question.
      *
      * Only a `VarP` DIRECTLY under the alt is recorded, plus the outer
      * var of an `AsP` (whose type is the whole pattern's, hence the
      * domain).  A var inside a `ConP`/`ProductP` has a different type
      * that this arithmetic does not know, and `StrictP`/`LazyP` are not
      * unwrapped even though their type is the same, to keep the rule one
      * sentence long.
      *
      * `scope` is the head type, carried so hover can render the argument
      * with the letters the head's own hover gives (`Pretty.prettyTypeIn`). */
    def domains(t: Type, n: Int): Option[List[Type]] = {
      val rho = t match { case Forall(_, _, _, _, b) => b; case x => x }
      @annotation.tailrec
      def go(x: Type, k: Int, acc: List[Type]): Option[List[Type]] =
        if (k == 0) Some(acc.reverse)
        else Subst.substAlias(Subst.substType(x)) match {
          case AppT(AppT(Arrow(_), dom), cod) => go(cod, k - 1, dom :: acc)
          case _                              => None
        }
      go(rho, n, Nil)
    }

    def argVar(p: Pattern): Option[V[Annot]] = p match {
      case VarP(v)            => Some(v)
      case AsP(_, VarP(v), _) => Some(v)
      case _                  => None
    }

    def args(b: Binding, hover: Type): Unit =
      if (b.arity > 0) domains(hover, b.arity) foreach { ds =>
        b.alts foreach { a =>
          if (a.patterns.length == ds.length)
            a.patterns.zip(ds) foreach { case (p, d) =>
              if (d.mono) argVar(p) foreach (v => record(v.loc, LocalTy(d, Some(hover))))
            }
        }
      }

    def pat(p: Pattern): Unit = p match {
      case VarP(v) =>
        // `Annot.annotAny`'s hole has id -1; a real signature does not.
        val declared = v.extract.body match {
          case VarT(a) if a.id == -1 => false
          case _                     => true
        }
        if (declared) record(v.loc, LocalTy(Subst.substType(v.extract.body)))
      case AsP(_, p1, p2)   => pat(p1); pat(p2)
      case ConP(_, _, ps)   => ps.foreach(pat)
      case ProductP(_, ps)  => ps.foreach(pat)
      case StrictP(_, p1)   => pat(p1)
      case LazyP(_, p1)     => pat(p1)
      case _                => ()
    }

    def alt(a: Alt): Unit = { a.patterns.foreach(pat); term(a.body) }

    def term(t: Term): Unit = t match {
      case App(f, x)          => term(f); term(x)
      case Sig(_, e, _)       => term(e)
      case Rigid(e)           => term(e)
      case Remember(_, e)     => term(e)
      case Lam(_, p, b)       => pat(p); term(b)
      case Case(_, e, alts)   => term(e); alts.foreach(alt)
      case Let(_, is, es, b)  => (is ++ es).foreach { b2 =>
                                   binding(b2); args(b2, headType(b2)); b2.alts.foreach(alt) }
                                 term(b)
      case _                  => ()   // Var, literals, Product, EmptyRecord, Hole
    }

    // The component's OWN heads are top-level bindings, not locals —
    // `types` already carries them, so only their ARGUMENTS and their
    // bodies are collected here.  `published` is the type hover shows for
    // the head (the generalised scheme for an implicit, the declaration
    // for an explicit), which is the one the argument letters must agree
    // with; it falls back to the head's own type for a shape that has no
    // published entry.
    bs.foreach { b =>
      args(b, published(b.v) getOrElse headType(b))
      b.alts.foreach(alt)
    }
    out.toMap
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
                groups: Map[String, String], scopeKey: String, cache: Cache,
                wantLocals: Boolean = false)
               (implicit s: SessionEnv, su: Supply): (Result, Cache) = {
    val notes = scala.collection.mutable.ListBuffer.empty[Note]

    // `Recoverable`, not `NonFatal` (review finding P-1): NonFatal treats
    // the whole LinkageError family as fatal, and a reflective lookup
    // over a stale classpath throws exactly that.  One escaping from here
    // reaches Diagnostics.run, then Rpc's notification guard, and the
    // file is published NOTHING — a blank editor is worse than any
    // diagnostic, so nothing short of the three genuinely fatal
    // throwables gets to leave a check.
    def guard[A](sev: Int)(body: => A): Option[A] =
      try Some(body)
      catch {
        case Death(e, _) => notes += Note(e.toString, sev); None
        case com.clarifi.reporting.ermine.parsing.Recoverable(e) =>
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

    // LSP-FFI: the foreign phases above install stubs for whatever this
    // JVM could not resolve and leave positioned notes behind — warnings
    // for the bindings, information for an opaque `foreign data`.  Take
    // this module's; the env copy also carries the ones its imports left
    // when they were loaded, and those belong on their own files.
    s.foreignNotes.filter(_.module == mod).foreach { n =>
      notes += Note(n.report, n.severity, None, Some(n.span))
    }

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
        "unchecked: depends on a broken definition")).toString, Information,
        dependsOnBroken = true)

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
    val fresh = scala.collection.mutable.Map.empty[String, Entry]
    var reused = 0
    // 6.2: def-site -> type for the LOCAL binders of every component
    // that checked, reused ones included.  The file name is the one
    // Lower stamped on every binder `Pos` (ParseState's file).
    val file = ps.loc.fileName
    var locals: Map[(Int, Int), LocalTy] = Map()

    var subs: Map[TermVar, TermVar] = Map()
    var components = 0
    implicitBindingComponents(isp) foreach { comp =>
      val vs   = comp.map(_.v).toSet
      val refs = comp.flatMap(b => termVars(b.alts).toList).toSet
      val fp   = fpOf(comp, refs)
      components += 1
      fp foreach { f => comp.foreach(b => spelling(b.v) foreach (localFp += _ -> f)) }

      def hit: Option[Entry] =
        if (!reusable) None else fp.flatMap(cache.entries.get)

      if ((refs & failed).nonEmpty || (vs & preFailed).nonEmpty) {
        if ((vs & preFailed).isEmpty) comp.foreach(unchecked)
        failed = failed ++ vs
      } else hit match {
        case Some(e) if comp.forall(b => spelling(b.v).exists(e.types.contains)) =>
          // Only NOTE-FREE components are ever cached, so a hit adds
          // nothing to report and nothing whose Locs could have drifted
          // — the locals included (see `Entry`).
          comp foreach { b => spelling(b.v) foreach { sp => subs = subs + (b.v -> b.v.as(e.types(sp))) } }
          fp foreach { f => fresh += f -> e }
          locals = locals ++ e.locals
          reused += 1
        case _ =>
          val before = notes.length
          // A FRESH SubstEnv per component (see the class comment).
          guard(Error) {
            Session.subst { implicit hm =>
              /* S5 review Q-1: `publishing = true`.  `comp` is a component of
               * `m.implicits` split by the same `implicitBindingComponents` that
               * `Subst.inferBindingGroupTypes` uses, so this IS the module's
               * top-level implicit binding group -- the editor's copy of the very
               * generalisation the compiler publishes.  Without it the C12
               * tautology deletion did not run here and LSP hover answered a type
               * the compiler does not publish (measured through the LSP: hover
               * `(exists h t. r <- (t,h)) => Relation r -> Relation r` against the
               * `.ei`'s `Relation r -> Relation r`).  This path never writes an
               * `.ei` -- the only `writeInterface` caller is `Session.dep`'s
               * closure -- so it changes what the EDITOR shows and nothing on
               * disk. */
              val cs = Term.subTerm(subs, comp)
              val (ds, sub) = inferImplicitBindingTypes(m.loc, toGamma(subs), cs, true, true)
              for (d <- ds) if (!d.isTrivialConstraint) d.die("non-trivial top level constraint")
              // 6.2: one zonk per local binder, INSIDE the block that
              // already exists, over the terms as inference saw them.
              (sub, if (wantLocals) collectLocals(cs, file, sub.get(_).map(_.extract))
                    else Map.empty[(Int, Int), LocalTy])
            }
          } match {
            case Some((sub, ls)) =>
              subs = subs ++ sub
              locals = locals ++ ls
              if (notes.length == before) fp foreach { f =>
                fresh += f -> Entry(comp.flatMap(b => spelling(b.v).flatMap(sp =>
                  sub.get(b.v).map(sp -> _.extract))).toMap, ls)
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
            val ep = Term.subTerm(subs, e)
            typeCheckExplicitBinding(Nil, ep)
            if (wantLocals) locals = locals ++ collectLocals(List(ep), file, etm.get)
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
    (Result(notes.toList, types, reused, components, locals), Cache(scopeKey, fresh.toMap))
  }

  def fingerprint(parts: String*): String = {
    val md = java.security.MessageDigest.getInstance("SHA-1")
    parts foreach { p => md.update(p.getBytes("UTF-8")); md.update(0: Byte) }
    md.digest().map("%02x".format(_)).mkString
  }
}
