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
import com.clarifi.reporting.ermine.surface.{ Anchors, Span, StatementExtents }
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
                        span: Option[Span] = None, dependsOnBroken: Boolean = false,
                        /** 7.5, ticket E7: this note is `assertTypeClosed`'s
                          * -- a TYPE name that did not resolve.  `spelling`
                          * is the flag the import-failure rule keys on for
                          * undefined TERMS, and it cannot carry this one:
                          * `assertTypeClosed` dies ONCE with every free type
                          * variable joined into one report, so there is no
                          * single spelling to put there.  A flag is what
                          * there is, and it is set by construction (never by
                          * matching the rendered text -- 6.1's rule). */
                        undefinedType: Boolean = false)

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
                          locals: Map[(Int, Int), LocalTy] = Map(),
                          /** 7.5, ticket E10(5): the file's own nullary
                            * type synonyms, resolved to the `Con` they
                            * name.  See `checkWith`. */
                          ownTypes: Map[String, Global] = Map())

  /** Per-uri inference reuse (roadmap 5.5).  `scopeKey` covers
    * everything an SCC's inference depends on beyond its own text: the
    * imports, the scope-bearing statements, the top-level head set, the
    * TEXT of every top-level bind item that no group can be looked up by
    * (7.2 fix round, `reachable` below), and the versions of the OTHER
    * open buffers (a sibling's unsaved edit changes what an import
    * means).  When it moves, the whole map goes: conservative and correct
    * beats clever.
    *
    * `entries` is keyed by an SCC fingerprint — its bindings' source
    * text, each group's items tagged with their offset from the group's
    * own first line, each group tagged with its offset from the SCC's
    * own first line, plus the fingerprints of the module-local groups it
    * references.  Fingerprints rather than inferred types because they
    * are alpha-invariant by construction: every V in a fresh run has a
    * fresh id, so a type rendering would be a moving target.
    *
    * 7.2: NO ABSOLUTE LINE IS IN THE KEY.  Until 7.2 each statement's
    * absolute start line was, which made a key move whenever a line was
    * inserted or deleted ANYWHERE above it — one blank line at the top
    * of Layout/Report.e dropped reuse from 97 of 154 to 0 and cost
    * +0.52 s (MEASURED, tracker/loopmodel/LSP4-7.0-READ.md §7).  What
    * replaces it is `Entry`'s anchoring: see there for the invariant. */
  final case class Cache(scopeKey: String, entries: Map[String, Entry]) {
    def isEmpty: Boolean = entries.isEmpty
    def size: Int = entries.size
  }
  object Cache { val empty = Cache("", Map()) }

  /** What one cached component carries: the types its top-level
    * bindings were given, and (6.2, Decision b) the LOCAL binder types
    * collected inside the same `Session.subst` block — the latter with
    * their def-site lines RELATIVE to the component's anchor, which is
    * the first line of the first of its groups (7.2).
    *
    * THE DRIFT INVARIANT, in the anchored form.  Stage 3 Decision (b)
    * argued that a reused entry's positions cannot have drifted because
    * the absolute start lines were in the key.  They no longer are, and
    * the argument is now this, in three parts:
    *
    *  (1) A HIT MEANS THE COMPONENT'S TEXT AND ITS INTERNAL GEOMETRY ARE
    *      WHAT THEY WERE.  The key holds every group's whole text, and
    *      every line offset INSIDE the component — each statement's
    *      offset from its group's first line, each group's offset from
    *      the component's anchor.  So an edit that changes any byte of
    *      it, or that moves any part of it relative to any other part
    *      (a comment or blank line inserted between two of its
    *      statements), changes the key and MISSES.
    *  (2) COLUMNS CANNOT HAVE MOVED.  A top-level statement starts at
    *      column 1 — a PARSER guarantee, not an assumption: an indented
    *      top-level statement is rejected by the header parse (6.2
    *      review R-7) — and the statement's own text then fixes every
    *      column inside it.
    *  (3) WHAT REMAINS IS ONE NUMBER: the anchor.  The whole component
    *      may have moved up or down as a block, and by exactly the
    *      difference between the anchor it was recorded at and the
    *      anchor it is looked up at.  `Anchors` adds it back at lookup,
    *      so a reused entry's def-sites are the CURRENT buffer's.
    *
    * `types` carry `Loc`s from the run that recorded them, and those are
    * NOT re-anchored.  They do not reach the client: hover, completion
    * detail, the document-symbol detail and the add-signature code
    * action all render a type through `Pretty`, which never reads a
    * `loc`; every position an LSP reply carries comes from the CURRENT
    * run's renamer, surface tree or session env (7.2's escape-route
    * enumeration).  Note-bearing components are still never cached, so
    * a reused entry contributes no diagnostic of its own. */
  final case class Entry(types: Map[String, Type], locals: Map[(Int, Int), LocalTy])

  /** One top-level spelling's statements, as `keys` fingerprints them:
    * the text (with each statement tagged by its offset from `anchor`)
    * and the 1-based source line the group starts at.  The anchor is
    * NOT part of the text — that is the whole of item 7.2. */
  final case class Group(text: String, anchor: Int)

  /** Statement heads whose EDIT changes what every other statement
    * means, so the whole per-uri cache goes.  `private` and `database`
    * are here because their bodies are not top-level items, so nothing
    * inside one can be fingerprinted on its own. */
  private val ScopeWords = Set(
    "import", "export", "type", "data", "class", "instance", "field", "table",
    "foreign", "private", "database", "abstract",
    "infixl", "infixr", "infix", "prefix", "postfix")

  /** Can this top-level bind item's group be looked up by the item's own
    * SPELLING?  (7.2 fix round, review R-1.)
    *
    * `groups` is keyed by `StatementExtents`' head word, which is the run
    * of letters, digits, `#` and `.` at the statement's first significant
    * character; the spelling is the run of `Lexer.tailChar`s there, which
    * is letters, digits, `_`, `#` and `'`.  The two agree on the ordinary
    * case and disagree in exactly three ways:
    *
    *   - the head word is EMPTY -- an operator definition `(<+>) x y = ...`
    *     or a backtick-quoted name ``1pixel`` = ... (16 of Layout/Report.e's
    *     top-level bindings);
    *   - the head word is TRUNCATED because the spelling contains `_` or
    *     `'` -- `foo_a` scans as `foo`, `unscaled'` as `unscaled` (11 more);
    *   - the head word is LONGER than the spelling, because `wordAt` eats a
    *     `.` that is not an identifier character.
    *
    * So the test is not "does it contain an odd character" but the direct
    * one: IS THE HEAD WORD THE WHOLE LEXEME.  That covers all three, and it
    * stays right if either character set ever changes.
    *
    * `head` deliberately does NOT mirror `Lexer`'s `_Module` affix quirk:
    * a longer lexeme than the head word only ever makes an item
    * unreachable, which is the safe direction. */
  private def reachable(x: StatementExtents.Extent, text: String): Boolean =
    x.headWord.nonEmpty && x.headWord == lexemeAt(text)

  /** The identifier lexeme at the start of an extent's text, by
    * `Lexer.tailChar`'s character set. */
  private def lexemeAt(t: String): String = {
    var k = 0
    while (k < t.length && {
             val c = t.charAt(k)
             c.isLetter || c.isDigit || c == '_' || c == '#' || c == '\''
           }) k += 1
    t.substring(0, k)
  }

  /** The two fingerprint inputs, derived from the source: the per-group
    * texts and the scope key.  A group is one top-level spelling's own
    * statements, sig and equations together — the invalidation unit,
    * since they pair module-wide by shared V.  `workspaceKey` is the
    * caller's business: the LSP puts the OTHER open buffers' versions in
    * it, because a sibling's unsaved edit changes what an import means.
    *
    * 7.2: the text carries each statement's offset from the GROUP'S OWN
    * first line, and the absolute line comes back separately as the
    * group's anchor.  Before 7.2 the absolute line was in the text, and
    * every key in the file moved when a line was inserted above it. */
  def keys(contents: String, moduleName: String, importsKey: String,
           workspaceKey: String): (Map[String, Group], String) = {
    // 7.0(b): the extent scan and its line index, timed apart, because
    // P5(a)'s 11.5x cut was on the index and the survey still carries the
    // pre-cut arithmetic (~54ms) for the pair.  Inert unless
    // -Dermine.lsp.phases=true.
    val tScan = Phases.now
    val scan = StatementExtents.scan(contents)
    Phases.add("extents.scan", tScan)
    // One index for the whole run.  This makes two position lookups per
    // top-level statement, and each of them used to re-walk the file from
    // offset 0 -- 4.7% of the editor round trip (roadmap P5(a)).
    val tOff = Phases.now
    val off = new StatementExtents.Offsets(contents)
    Phases.add("extents.offsets", tOff)
    val (scopeItems, bindItems) = scan.items partition (x => ScopeWords(x.headWord))
    // 7.2 fix round (review R-1).  A bind item is only REACHABLE if its own
    // spelling finds its group: both readers look up by the binding's full
    // spelling (`groups.get(sp)`), and `groups` is keyed by the extent
    // scanner's head word.  An UNREACHABLE item therefore reaches no key at
    // all -- not its own, and not its dependents' (`fpOf` returns None for
    // it, so nothing records an upstream edge), which until this round left
    // every cacheable dependent holding a stale type with its diagnostic
    // silently dropped.  Its TEXT goes into the scope key instead, so any
    // edit to one drops the whole per-uri cache: conservative and correct,
    // the answer 5.5 already gives for a `private` block.  The text is
    // position-free, so a pure line shift still moves nothing.
    // Each bind item's text is taken ONCE here and used by both halves --
    // strictly fewer `Offsets.text` calls than before this round, which took
    // one per GROUPED item and none for the rest.
    val bindTexts = bindItems.map(x => (x, off.text(x)))
    val (keyedItems, unkeyedItems) = bindTexts partition { case (x, t) => reachable(x, t) }
    val groups = keyedItems.groupBy(_._1.headWord).map {
      case (w, xs) =>
        // 7.2.  The group's ANCHOR is its first statement's line; every
        // statement goes into the text tagged with its offset from that
        // anchor, so a comment or blank line inserted BETWEEN a sig and
        // its equations still changes the text (and misses), while the
        // group as a whole may move up or down freely.
        val anchor = xs.map(_._1.startLine).min
        w -> Group(xs.map { case (x, t) =>
          Anchors.tag(x.startLine, anchor) + ":" + t }.mkString("\u0000"), anchor)
    }
    val scopeKey = fingerprint(
      moduleName, importsKey,
      scopeItems.map(off.text).mkString("\u0000"),
      bindItems.map(_.headWord).sorted.mkString(","),
      unkeyedItems.map(_._2).mkString("\u0000"),
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
    * set) — and to the line that group starts at, which is its
    * ANCHOR (7.2) and is not part of its text.  A spelling missing from
    * `groups` — an operator, anything the extent scanner cannot name —
    * is simply never cached. */
  def checkWith(ps: ParseState, m: Module,
                groups: Map[String, Group], scopeKey: String, cache: Cache,
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

    // 7.5, ticket E10(5): THE FILE'S OWN TYPE NAMES, each mapped to the
    // `Con` that writing that spelling in this file actually denotes.
    //
    // `ModuleScope.canonicalTypes` holds what the IMPORTS put in scope
    // and nothing else, so the add-signature quick fix refused every type
    // a module reaches only through a synonym of its own --
    // `Layout/Scan.e` declares `type Scan = Scan_S` over
    // `import Relation.Scan as S`, the printer writes `Scan`, and 29 of
    // that file's groups were refused for a name the file can write.
    //
    // ONLY A NULLARY SYNONYM OF A BARE CONSTRUCTOR is published, and the
    // narrowness is the soundness argument: `type X = C` means that `X`
    // and `C` are the same type constructor, so a signature spelling `C`
    // as `X` checks.  `type X = C Int` does NOT license writing `C` as
    // `X`, and a synonym with parameters is not a type by itself at all;
    // both fall out here rather than being accepted and then failing to
    // check.  The substitution is `maps`, the map the type-def phase has
    // just built (an imported constructor is a `Con` in it, which is how
    // `Scan_S` becomes `Relation.Scan.Scan`); `data` and `class` names
    // need no entry, since their `Global` already carries this module.
    val ownTypes: Map[String, Global] =
      m.types.collect {
        case TypeStatement(_, v, kindArgs, typeArgs, body)
          if kindArgs.isEmpty && typeArgs.isEmpty =>
          (v.name.map(_.string), Session.subTypeMaps(maps, body))
      }.collect {
        case (Some(n), Type.Con(_, g, _, _)) => n -> g
      }.toMap

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
    // 7.5, ticket E7: tagged, so `Resident.checkFile` can withhold it while
    // an import failed -- the same rule, and the same accepted cost, that
    // 6.1(b) already applies to undefined TERMS.  A module that did not load
    // contributes no TYPES either, so a file that uses one gets this note
    // for a name that could not have arrived, on top of the import failure
    // that explains it.
    try assertTypeClosed(bs)
    catch {
      case Death(e, _) => notes += Note(e.toString, Error, undefinedType = true)
      case com.clarifi.reporting.ermine.parsing.Recoverable(e) =>
        notes += Note("error: " + Option(e.getMessage).getOrElse(e.toString), Error,
                      undefinedType = true)
    }

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
      // A sig's own POSITION is not in its fingerprint (7.2): where an
      // upstream annotation sits cannot move a dependent's binders.
      for (sp <- spelling(e.v); g <- groups.get(sp)) localFp += sp -> fingerprint("sig", sp, g.text)
    }
    /** The component's fingerprint AND its anchor (7.2): the first line
      * of the first of its groups.  Every group goes into the key with
      * its own offset from that anchor, so the component's INTERNAL
      * geometry is pinned by the key and only the anchor itself is free
      * to move — which is exactly the one number a hit re-adds. */
    def fpOf(comp: List[ImplicitBinding], refs: Set[TermVar]): Option[(String, Int)] = {
      val sps = comp.flatMap(b => spelling(b.v))
      if (sps.size != comp.size) None
      else {
        val gs = sps.map(groups.get)
        if (gs.exists(_.isEmpty)) None
        else {
          val anchor   = gs.flatten.map(_.anchor).min
          // SORTED BY SPELLING, and the TEXTS with it.  Before the 7.2 fix
          // round the tags were sorted and the texts were taken in `comp`
          // order, which is an SCC traversal order over id-keyed maps and is
          // NOT stable between runs: a component with two or more groups
          // could fingerprint differently each time and then never be reused
          // at all.  Found while pinning review R-2 -- the property that is
          // supposed to prove a mutually recursive pair MISSES after a line
          // is inserted between them could not fail, because the pair never
          // hit in the first place (measured: reused 4 of 5 components on an
          // UNCHANGED re-run, the one that never hit being the pair).
          // Sorting makes the key a function of the text, which is what it
          // has always claimed to be.
          val parts    = sps.sorted.map(sp =>
                           sp + "@" + Anchors.tag(groups(sp).anchor, anchor) +
                           ":" + groups(sp).text)
          val upstream = refs.toList.flatMap(spelling).flatMap(localFp.get).sorted
          Some((fingerprint(("scc" :: parts ::: upstream): _*), anchor))
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
      // 7.2: the fingerprint and the component's ANCHOR travel together.
      // The anchor is 0 when the component has no fingerprint at all, in
      // which case nothing is stored or looked up and it is never used.
      val fpk    = fp.map(_._1)
      val anchor = fp.map(_._2) getOrElse 0
      components += 1
      fpk foreach { f => comp.foreach(b => spelling(b.v) foreach (localFp += _ -> f)) }

      def hit: Option[Entry] =
        if (!reusable) None else fpk.flatMap(cache.entries.get)

      if ((refs & failed).nonEmpty || (vs & preFailed).nonEmpty) {
        if ((vs & preFailed).isEmpty) comp.foreach(unchecked)
        failed = failed ++ vs
      } else hit match {
        case Some(e) if comp.forall(b => spelling(b.v).exists(e.types.contains)) =>
          // Only NOTE-FREE components are ever cached, so a hit adds
          // nothing to report; its locals come back RE-ANCHORED to the
          // buffer as it is now (7.2, see `Entry`'s drift invariant).
          comp foreach { b => spelling(b.v) foreach { sp => subs = subs + (b.v -> b.v.as(e.types(sp))) } }
          // The entry stays RELATIVE as it is carried forward, so a
          // component that is reused a hundred times over is anchored
          // once per lookup and never re-based (Stage-4 invariant:
          // reuse metadata survives reuse).
          fpk foreach { f => fresh += f -> e }
          locals = locals ++ Anchors.absKeys(e.locals, anchor)
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
              if (notes.length == before) fpk foreach { f =>
                fresh += f -> Entry(comp.flatMap(b => spelling(b.v).flatMap(sp =>
                  sub.get(b.v).map(sp -> _.extract))).toMap,
                  Anchors.relKeys(ls, anchor))
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
    (Result(notes.toList, types, reused, components, locals, ownTypes),
     Cache(scopeKey, fresh.toMap))
  }

  def fingerprint(parts: String*): String = {
    val md = java.security.MessageDigest.getInstance("SHA-1")
    parts foreach { p => md.update(p.getBytes("UTF-8")); md.update(0: Byte) }
    md.digest().map("%02x".format(_)).mkString
  }
}
