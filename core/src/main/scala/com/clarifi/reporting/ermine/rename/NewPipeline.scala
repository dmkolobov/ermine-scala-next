package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{
  Annot, Bound, Global, ImplicitBinding, ExplicitBinding, Kind, Local, Name,
  Pattern, Term, Type, V, Alt, Let }
import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleHeader }
import com.clarifi.reporting.ermine.session.{ Phases, SessionEnv }
import com.clarifi.reporting.ermine.surface._
import com.clarifi.reporting.ermine.syntax.{
  DataStatement, FieldStatement, ForeignBlock, ForeignClass, ForeignFailure,
  ForeignConstructorStatement, ForeignDataStatement, ForeignFunctionStatement,
  ForeignMember, ForeignMethodStatement, ForeignSubtypeStatement,
  ForeignTermDef, ForeignValueStatement, Module, PrivateBlock, SigStatement,
  Statement, TableStatement, TermStatement, TypeStatement, Explicit }
import scalaparsers.{ Death, Document, Pos, Supply }

/** The new pipeline's module reader (Stage 1 item 4.1c): surface parse ->
  * rename -> re-associate -> lower, producing the (ParseState, Module)
  * pair Session.dep's read closure hands to loadModule — the frozen
  * contract.  The constructed parse state carries the canonical maps from
  * ModuleScope, the termNames superset plus reference placeholders, and
  * the typeNames map minted by TyLower plus the module's own type
  * definitions — exactly what Type.conMap and the field processor read.
  */
object NewPipeline {

  /** The phase a diagnostic came from.  Strict reading dies on the first
    * diagnostic of the EARLIEST phase, each phase keeping its own
    * emission order — that is today's throw order, and it is NOT a
    * position-sorted merge (Stage 2 item 5.1). */
  sealed abstract class Phase(val name: String)
  object Phase {
    case object Syntax   extends Phase("syntax")
    case object Rename   extends Phase("rename")
    case object Reassoc  extends Phase("reassoc")
    case object Assemble extends Phase("assemble")
    case object Lower    extends Phase("lower")
  }

  /** One diagnostic, kept STRUCTURALLY: the span in the file plus the
    * message the strict reader renders at it.  The editor path wants a
    * real range; the batch path renders it through mkPos exactly as it
    * used to. */
  final case class Diag(phase: Phase, span: Span, message: String)

  /** Everything one read produces: the (ParseState, Module) pair the
    * loader contract wants, plus — for the editor — the surface module
    * (Definitions' fixity bridge reads it), the renamer tables
    * (navigation) and every phase's diagnostics. */
  /** `scope` is the module scope the RENAMER resolved through -- the
    * canonical import maps, not the session superset.  Carried out (6.3)
    * so the editor can ask "would this new name already resolve here?"
    * without re-running `ModuleScope.importing`; nothing on the batch
    * path reads it, and computing it is where it always was. */
  /** `marks` is the EDITOR read's per-statement high-water marks (LSP Stage 4
    * item 7.1a), one per top-level statement of `surface`, in order; empty on
    * the strict path, which calls `SurfaceParsers.module` and records nothing.
    * Nothing in this pipeline reads it -- it is 7.1b's reuse guard, written
    * here so the cache can be built beside this reader without touching it. */
  final case class Read(module: Module, ps: scalaparsers.ParseState[ErParseState],
                        surface: SModule, renamed: Renamer.Result,
                        diagnostics: List[Diag],
                        scope: ModuleScope.Scope = ModuleScope.Scope.empty,
                        marks: List[SurfaceParsers.StatementMark] = Nil)

  /** An assemble refusal with its position kept structurally, so the
    * strict path renders it exactly as before and the tolerant path can
    * make a diagnostic of it without regexing a report back apart. */
  private final case class Refusal(span: Span, message: String)
    extends RuntimeException(message) with scala.util.control.NoStackTrace

  def readModule(fileName: String, contents: String, mh: ModuleHeader)
                (implicit s: SessionEnv, su: Supply): (scalaparsers.ParseState[ErParseState], Module) = {
    val r = read(fileName, contents, mh, tolerant = false)
    (r.ps, r.module)
  }

  /** The EDITOR read (Stage 2 item 5.1): every phase runs and every
    * phase's diagnostics come back, so a file with two broken statements
    * gets two squiggles and its healthy statements still get an index.
    * BATCH SEMANTICS ARE UNTOUCHED: readModule is the same traversal
    * with tolerance off, dying byte-for-byte where it died before —
    * with tolerance off no statement is ever guarded and no phase runs
    * after one that produced a diagnostic. */
  def readModuleTolerant(fileName: String, contents: String, mh: ModuleHeader)
                        (implicit s: SessionEnv, su: Supply): Read =
    read(fileName, contents, mh, tolerant = true)

  private def read(fileName: String, contents: String, mh: ModuleHeader, tolerant: Boolean)
                  (implicit s: SessionEnv, su: Supply): Read = {

    // A module whose header does not parse leaves nothing to be tolerant
    // WITH; both modes die here, identically.
    // 7.0(c): the whole-file surface parse.  `Phases` is inert unless
    // -Dermine.lsp.phases=true, which no batch JVM sets.
    val tParse = Phases.now
    // THE BATCH PATH IS THE SAME CALL IT ALWAYS WAS (7.1a): `moduleMarked` is
    // `module`'s grammar with an observation wrapper around the statement
    // parser, and only the tolerant read takes it, so no strict output can
    // depend on the high-water mark.
    val noMarks: List[SurfaceParsers.StatementMark] = Nil
    val parsed = if (tolerant) SurfaceParsers.moduleMarked(fileName, contents, mh.name)
                 else SurfaceParsers.module(fileName, contents, mh.name).map((_, noMarks))
    val (sm, marks) = parsed match {
      case Right(p)  => p
      case Left(err) => throw Death(err.pretty)
    }
    Phases.add("parse", tParse)

    val ds = scala.collection.mutable.ListBuffer.empty[Diag]
    def checkpoint(): Unit =
      if (!tolerant) ds.headOption.foreach { d => throw Death(render(fileName, contents, d)) }

    // --- syntax.  batch loads REFUSE unparseable statements (the
    // tolerant splitter keeps their extent as SErrorStatement for editor
    // flows; a module load must not silently drop them — D3, Ugly.e)
    def errors(ss: List[SStatement]): List[SErrorStatement] = ss.flatMap {
      case e: SErrorStatement          => List(e)
      case SPrivateBlock(_, ss2)       => errors(ss2)
      case SDatabaseBlock(_, _, ss2)   => errors(ss2)
      case _                           => Nil
    }
    val tSyntax = Phases.now
    val errs = errors(sm.statements)
    if (errs.nonEmpty) {
      // The splitter's span runs to wherever the offside rule stopped —
      // trailing blank lines included.  D7's scanner ends just past the
      // last significant character, and its starts agree with the
      // splitter's exactly (the 180-file differential), so match by start
      // and prefer its end: a broken statement squiggles over itself and
      // not over the whitespace after it.  Only the position the strict
      // reader renders (start) is shared, so this changes no batch
      // output.  Statements nested in a private/database block are not in
      // a top-level scan and keep the parsed span (5.6's business).
      val ends = StatementExtents.scan(contents).items.iterator
        .map(x => (x.startLine, x.startCol) -> Span(x.startLine, x.startCol, x.endLine, x.endCol))
        .toMap
      errs.foreach { e =>
        val sp = e.loc.span
        val extent = ends.getOrElse((sp.startLine, sp.startCol), sp)
        // 5.2: the splitter's `.attempt` threw the real failure away and
        // left only the statement's start.  Re-run the real grammar over
        // the extent to get it back, so the squiggle lands where the
        // parser actually gave up.  A re-parse that SUCCEEDS (the slice
        // can lack context the whole file had) keeps the coarse form.
        SurfaceParsers.statementFailure(fileName, contents,
            extent.startLine, extent.startCol, extent.endLine, extent.endCol) match {
          case Some(err) =>
            val l = err.loc.line
            val c = err.loc.column
            ds += Diag(Phase.Syntax, Span(l, c, l, c + 1), "error: " + err.message.toString)
          case None =>
            ds += Diag(Phase.Syntax, extent,
                       "error: unparseable statement (" + e.message + ")")
        }
      }
    }
    Phases.add("syntax", tSyntax)
    checkpoint()

    // --- rename
    val tRename = Phases.now
    val scope = ModuleScope.importing(mh.name, ModuleScope.Scope.empty,
      s.termNames, s.cons.keySet, mh.imports, s.termNameOrigins, s.consOrigins)
    val renamed = Renamer.rename(sm, scope, s.foreignTolerant)
    renamed.diagnostics.foreach(d => ds += Diag(Phase.Rename, d.span, "error: " + d.message))
    Phases.add("rename", tRename)
    checkpoint()

    // --- re-associate
    val tReassoc = Phases.now
    val (restatements, reDiags) = Reassoc.module(sm, scope)
    reDiags.foreach(d => ds += Diag(Phase.Reassoc, d.span, d.message))
    Phases.add("reassoc", tReassoc)
    checkpoint()

    // fixity declarations are part of the declared NAMES (binders and
    // exported Globals carry them); no block-level decls exist in the corpus
    val termFix = sm.statements.collect {
      case SFixity(_, f, false, ops) => ops.map(_.spelling -> f) }.flatten.toMap
    val typeFix = sm.statements.collect {
      case SFixity(_, f, true, ops) => ops.map(_.spelling -> f) }.flatten.toMap

    val tCtx = Phases.now
    val lctx = Lower(renamed, fileName, s.termNames, scope, termFix)
    val tctx = TyLower(renamed, fileName, mh.name, s.cons ++ s.privateCons, su, typeFix)
    lctx.lowerAnnot = (t: STy) => TyLower.annot(t, tctx)
    Phases.add("lowerctx", tCtx)

    // --- assemble (Lower/TyLower run inside it, statement by statement)
    val tAssemble = Phases.now
    val (module, ps) =
      try assemble(mh, restatements, lctx, tctx, fileName, contents, scope, tolerant, ds)
      catch { case r: Refusal =>
        throw Death(render(fileName, contents, Diag(Phase.Assemble, r.span, r.message))) }
    Phases.add("lower", tAssemble)

    // --- lower.  assemble's own refusals precede these, as they do today
    lctx.diags.result().foreach(d => ds += Diag(Phase.Lower, d.span, d.message))
    checkpoint()

    Read(module, ps, sm, renamed, ds.toList, scope, marks)
  }

  /** A bare TYPE against the session (kindOf, post-G1 D3): parse,
    * rename, re-associate, lower, substitute cons. */
  def replType(source: String, contents: String,
               imports: Map[String, (Option[String], List[Explicit[Global]], Boolean)])
              (implicit s: SessionEnv, su: Supply): Type = {
    def die(sp: Span, msg: String): Nothing =
      throw Death(mkPos(source, contents, sp).report(Document.text(msg)))
    val t0 = SurfaceParsers.typeExpr(source, contents) match {
      case Right(t)  => t
      case Left(err) => throw Death(err.pretty)
    }
    val scope = ModuleScope.importing("REPL", ModuleScope.Scope.empty,
      s.termNames, s.cons.keySet, imports, s.termNameOrigins, s.consOrigins)
    val renamed = Renamer.renameType(t0, scope)
    renamed.diagnostics.headOption.foreach(d => die(d.span, "error: " + d.message))
    val fenv = Reassoc.FixityEnv(Reassoc.importFixities(scope), Map())
    val (re, reDs) = Reassoc.ty(t0, fenv)
    reDs.headOption.foreach(d => die(d.span, d.message))
    val tctx = TyLower(renamed, source, "REPL", s.cons ++ s.privateCons, su)
    val ty = TyLower.ty(re, tctx)
    val cm = Type.conMap("REPL", tctx.typeNames, s.cons)
    com.clarifi.reporting.ermine.Subst.subTypeMaps((cm, Map.empty[V[Type], V[Type]]), ty)
  }

  /** The REPL expression path (post-G1 D1): surface-parse one term,
    * rename it against the session imports, re-associate, lower, and
    * substitute cons — the core Term Session.eval infers and evaluates.
    * Death positions render over `source` like the fused phrase(term). */
  def replTerm(source: String, contents: String,
               imports: Map[String, (Option[String], List[Explicit[Global]], Boolean)])
              (implicit s: SessionEnv, su: Supply): com.clarifi.reporting.ermine.Term = {
    def die(sp: Span, msg: String): Nothing =
      throw Death(mkPos(source, contents, sp).report(Document.text(msg)))

    val e0 = SurfaceParsers.expression(source, contents) match {
      case Right(t)  => t
      case Left(err) => throw Death(err.pretty)
    }
    val scope = ModuleScope.importing("REPL", ModuleScope.Scope.empty,
      s.termNames, s.cons.keySet, imports, s.termNameOrigins, s.consOrigins)
    val renamed = Renamer.renameTerm(e0, scope)
    renamed.diagnostics.headOption.foreach(d => die(d.span, "error: " + d.message))

    val fenv = Reassoc.FixityEnv(Reassoc.importFixities(scope), Map())
    val (re, reDs) = Reassoc.term(e0, fenv)
    reDs.headOption.foreach(d => die(d.span, d.message))

    val lctx = Lower(renamed, source, s.termNames, scope)
    val tctx = TyLower(renamed, source, "REPL", s.cons ++ s.privateCons, su)
    lctx.lowerAnnot = (t: com.clarifi.reporting.ermine.surface.STy) => TyLower.annot(t, tctx)
    val tm = Lower.term(re, lctx)
    lctx.diags.result().headOption.foreach(d => die(d.span, d.message))

    val cm = Type.conMap("REPL", tctx.typeNames, s.cons)
    val out = com.clarifi.reporting.ermine.Subst.subTermMaps((cm, Map.empty[V[Type], V[Type]]), tm)

    // Unlike a module load, nothing links a REPL term later: every free
    // variable must already be bound in the session env, or this is the
    // fused parse-time refusal moved here (undefined names, ambiguous
    // imports, missing desugar primitives — Decision f rendering)
    val unbound = scala.collection.mutable.ListBuffer.empty[V[Type]]
    com.clarifi.reporting.ermine.Term.termVars(out).foreach { v =>
      if (!s.env.contains(v)) unbound += v
    }
    unbound.headOption.foreach { v =>
      throw Death(v.report(Document.text("error: undefined term")))
    }
    out
  }

  /** How the strict reader renders a diagnostic: the refusal batch loads
    * have always produced, "file:line:col:" + source line + caret.  The
    * tolerant/strict differential (TestTolerantRead) compares against
    * this, so the two paths cannot drift apart silently. */
  def render(fileName: String, contents: String, d: Diag): Document =
    mkPos(fileName, contents, d.span).report(Document.text(d.message))

  private def mkPos(file: String, contents: String, sp: Span): Pos = {
    val line = contents.linesIterator.drop(sp.startLine - 1).nextOption().getOrElse("").replaceAll("\\r$", "")
    Pos(file, line, sp.startLine, sp.startCol, false)
  }

  // ------------------------------------------------------------- assembly
  // moduleBody's `go` bucketing, ported; sig pairing per checkBindings
  // (by shared V, Annot.plain, "missing definition" preserved).

  private def assemble(mh: ModuleHeader, sts: List[SStatement],
                       lctx: Lower.Ctx, tctx: TyLower.TCtx,
                       fileName: String, contents: String, scope: ModuleScope.Scope,
                       tolerant: Boolean,
                       sink: scala.collection.mutable.ListBuffer[Diag])
                      (implicit s: SessionEnv, su: Supply): (Module, scalaparsers.ParseState[ErParseState]) = {

    // With tolerance OFF this is `Some(a)` and nothing is caught: the
    // strict reader keeps dying where it died.  With it ON, one statement
    // failing costs that statement only — and Death is not enough to
    // catch, because Reassoc leaves SErrorTerm/SPError/STyError nodes for
    // Lower.Unsupported to throw on and TyLower panics with sys.error
    // (Stage 2 item 5.1).
    def guard[A](sp: Span)(a: => A): Option[A] =
      if (!tolerant) Some(a)
      else try Some(a) catch {
        case Refusal(rsp, msg) =>
          sink += Diag(Phase.Assemble, rsp, msg); None
        case Lower.Unsupported(what, usp) =>
          sink += Diag(Phase.Assemble, usp, "error: " + what); None
        case Death(err, _) =>
          sink += Diag(Phase.Assemble, sp, err.toString); None
        case scala.util.control.NonFatal(e) =>
          sink += Diag(Phase.Assemble, sp,
                       "error: " + Option(e.getMessage).getOrElse(e.toString)); None
      }

    var fields      = List.empty[FieldStatement]
    var tables      = List.empty[TableStatement]
    var foreignData = List.empty[ForeignDataStatement]
    var types       = List.empty[TypeStatement]
    var dataStmts   = List.empty[DataStatement]
    var foreigns    = List.empty[ForeignTermDef]
    var implicits   = List.empty[ImplicitBinding]
    var explicits   = List.empty[ExplicitBinding]
    var privateTerms = Set.empty[V[Type]]
    var privateTypes = Set.empty[V[Kind]]
    var ownTypeNames = Map.empty[Name, V[Kind]]

    // binding statements group per adjacency block (adjacent equations of
    // one spelling are one binding's alts); sigs pair MODULE-WIDE by the
    // shared V, as the fused termNames memo does — a `private` group is a
    // privacy marker, not a pairing scope (List.e: `private map : t` with
    // the equations outside the group)
    val topGroups = scala.collection.mutable.LinkedHashMap[V[Type], ImplicitBinding]()
    val topSigs   = List.newBuilder[(V[Type], Type, Span)]

    def collectBlock(bs: List[SStatement]): (List[(V[Type], ImplicitBinding, Span)], List[(V[Type], Type, Span)]) = {
      // the group's Span is its FIRST equation's head — the position a
      // later re-opening of the name collides with (5.1; the cross-block
      // refusal used to report Span(0,0,0,0), not a position at all)
      val grouped = scala.collection.mutable.LinkedHashMap[String, (V[Type], List[Alt], Span)]()
      val sigs = List.newBuilder[(V[Type], Type, Span)]
      // equations of one name must be consecutive among equations —
      // gatherBindings parity (an interleaved equation silently merging
      // into an earlier group was a 4.2 regression, caught by the pin)
      var lastEq: Option[String] = None
      bs foreach { st => guard(st.loc.span) { st match {
        case SEquation(l, n, args, body, wh) =>
          if (grouped.contains(n.spelling) && !lastEq.contains(n.spelling))
            throw Refusal(n.span, s"error: interleaved equations for ${n.spelling}")
          lastEq = Some(n.spelling)
          val v = grouped.get(n.spelling).map(_._1).getOrElse {
            lctx.binderAtSite(n) getOrElse lctx.varFor(n)
          }
          val bodyT = wh match {
            case None => Lower.term(body, lctx)
            case Some(SWhere(wl, wss)) =>
              val (wis, wes) = lowerLet(wss)
              Let(lctx.pos(wl.span), wis, wes, Lower.term(body, lctx))
          }
          val alt = Alt(lctx.pos(l.span), args.map(Lower.pattern(_, lctx)), bodyT)
          grouped(n.spelling) = grouped.get(n.spelling) match {
            case Some((v0, as, sp0)) => (v0, as :+ alt, sp0)
            case None                => (v, List(alt), n.span)
          }
        case SSigStatement(l, ns, t) =>
          tctx.resetKindScope()
          val ty = TyLower.annot(t, tctx).body
          ns.foreach { n =>
            val v = lctx.binderAtSite(n) getOrElse lctx.varFor(n)
            sigs += ((v, ty, n.span))
          }
        case _ => ()
      } } }
      (grouped.values.toList.map { case (v, as, sp) => (v, ImplicitBinding(v.loc, v, as), sp) },
       sigs.result())
    }

    def pairSigs(im: collection.Map[V[Type], ImplicitBinding],
                 sigs: List[(V[Type], Type, Span)]): (List[ImplicitBinding], List[ExplicitBinding]) = {
      val es = sigs.flatMap { case (v, ty, sp) => guard(sp) {
        im.get(v) match {
          case Some(i) => ExplicitBinding(i.loc, i.v, Annot.plain(i.loc, ty), i.alts)
          case None    => throw Refusal(sp, "missing definition")
        }
      } }
      ((im -- es.map(_.v)).values.toList, es)
    }

    def bindingBlock(bs: List[SStatement], intoPrivate: Boolean): Unit = {
      val (groups, sigs) = collectBlock(bs)
      groups.foreach { case (v, b, sp) => guard(sp) {
        topGroups.get(v) match {
          case Some(_) =>
            // a later adjacency block re-opening a name: refused, as above
            throw Refusal(sp, "error: interleaved equations for " +
              b.v.name.map(_.string).getOrElse("?"))
          case None => topGroups(v) = b
        }
      } }
      topSigs ++= sigs
      if (intoPrivate)
        privateTerms = privateTerms ++ groups.map(_._1) ++ sigs.map(_._1)
    }

    def ownTypeVar(n: SName): V[Kind] = {
      // join the renamer's TyDef binder so sig references to the module's
      // own types share this V (Control/Monoid.e's `Monoid (m, n)`)
      val v = tctx.tyVar(
        tctx.binderIdAt(n.span).getOrElse(-(n.span.startLine * 1000 + n.span.startCol) - 5000000),
        n.spelling, n.span, None)
      ownTypeNames += (tctx.localTypeName(n.spelling): Name) -> v
      v
    }

    def walk(sts0: List[SStatement], intoPrivate: Boolean): Unit = {
      // adjacent binding statements form one group (gatherBindings parity)
      val (block, rest) = sts0.span(st => st.isInstanceOf[SEquation] || st.isInstanceOf[SSigStatement])
      if (block.nonEmpty) { bindingBlock(block, intoPrivate); walk(rest, intoPrivate); return }
      sts0 match {
        case Nil => ()
        case st :: more =>
          tctx.resetKindScope()  // named kind vars scope per statement
          st match {
            // blocks recurse OUTSIDE the guard: one bad statement inside
            // a private/database block must not cost the whole block
            case SPrivateBlock(_, ss)     => walk(ss, intoPrivate = true)
            case SDatabaseBlock(_, _, ss) => walk(ss, intoPrivate)
            case _ => guard(st.loc.span) { st match {
            case SFieldStatement(l, ns, t) =>
              val ty = TyLower.annot(t, tctx).body
              val fvs = ns.map(n => ownTypeVar(n))
              fields ::= FieldStatement(lctx.pos(l.span), fvs, ty)
              if (intoPrivate)
                privateTypes = privateTypes ++ ns.map(n => ownTypeNames(tctx.localTypeName(n.spelling)))
            case STableStatement(l, db, ns, t) =>
              val ty = TyLower.annot(t, tctx).body
              val tvs2 = ns.map(n => (List.empty[Name], lctx.varFor(n)))
              tables ::= TableStatement(lctx.pos(l.span), db.getOrElse(""), tvs2, ty)
              if (intoPrivate) privateTerms = privateTerms ++ tvs2.map(_._2)
            case STypeAlias(l, n, ks, bs, body) =>
              val kvs = ks.map(k => tctx.kindVar(tctx.binderIdAt(k.span).getOrElse(-1 - k.span.startCol), k.spelling, k.span))
              val tvs = bs.map(b => tctx.tyVar(tctx.binderIdAt(b.name.span).getOrElse(-2 - b.name.span.startCol * 7),
                                               b.name.spelling, b.name.span, b.kind.map(TyLower.kind(_, tctx))))
              types ::= TypeStatement(lctx.pos(l.span), ownTypeVar(n), kvs, tvs,
                TyLower.ty(body, tctx))
              if (intoPrivate) privateTypes = privateTypes + ownTypeNames(tctx.localTypeName(n.spelling))
            case SDataStatement(l, n, ks, bs, cons) =>
              val kvs = ks.map(k => tctx.kindVar(tctx.binderIdAt(k.span).getOrElse(-3 - k.span.startCol * 11), k.spelling, k.span))
              val tvs = bs.map(b => tctx.tyVar(tctx.binderIdAt(b.name.span).getOrElse(-4 - b.name.span.startCol * 13),
                                               b.name.spelling, b.name.span, b.kind.map(TyLower.kind(_, tctx))))
              val dcons = cons.map { cdef =>
                val evs = cdef.exists.map(b => tctx.tyVar(tctx.binderIdAt(b.name.span).getOrElse(-5 - b.name.span.startCol * 17),
                                                          b.name.spelling, b.name.span, b.kind.map(TyLower.kind(_, tctx))))
                (evs, lctx.binderAtSite(cdef.name) getOrElse lctx.varFor(cdef.name),
                 cdef.fields.map(TyLower.ty(_, tctx)))
              }
              dataStmts ::= DataStatement(lctx.pos(l.span), ownTypeVar(n), kvs, tvs, dcons)
              if (intoPrivate) {
                privateTypes = privateTypes + ownTypeNames(tctx.localTypeName(n.spelling))
                privateTerms = privateTerms ++ dcons.map(_._2)  // constructors go private too
              }
            case SForeignBlock(_, items) =>
              def privTerm(priv: Boolean, v: V[Type]): V[Type] = {
                if (priv) privateTerms = privateTerms + v
                v
              }
              def fgo(f: SForeign, priv: Boolean): Unit = { tctx.resetKindScope(); f match {
                case x: SForeignData =>
                  // foreignData's localTypes defaults unannotated arg
                  // kinds to Star — no body ever pins them
                  foreignData ::= ForeignDataStatement(lctx.pos(x.loc.span), ownTypeVar(x.name),
                    x.args.map(b => tctx.tyVar(tctx.binderIdAt(b.name.span).getOrElse(-6 - b.name.span.startCol * 19),
                                               b.name.spelling, b.name.span,
                                               b.kind.map(TyLower.kind(_, tctx))
                                                 .orElse(Some(com.clarifi.reporting.ermine.Star(lctx.pos(b.name.span)))))),
                    foreignClass(x.className, x.classSpan, fileName))
                  if (priv) privateTypes = privateTypes + ownTypeNames(tctx.localTypeName(x.name.spelling))
                case x: SForeignFunction =>
                  foreigns ::= ForeignFunctionStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body, foreignClass(x.className, x.classSpan, fileName),
                    ForeignMember(lctx.pos(x.memberSpan), x.member, literalSpan(x.memberSpan, x.member)))
                case x: SForeignMethod =>
                  foreigns ::= ForeignMethodStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body, ForeignMember(lctx.pos(x.memberSpan), x.member, literalSpan(x.memberSpan, x.member)))
                case x: SForeignValue =>
                  foreigns ::= ForeignValueStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body, foreignClass(x.className, x.classSpan, fileName),
                    ForeignMember(lctx.pos(x.memberSpan), x.member, literalSpan(x.memberSpan, x.member)))
                case x: SForeignConstructor =>
                  foreigns ::= ForeignConstructorStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body)
                case x: SForeignSubtype =>
                  foreigns ::= ForeignSubtypeStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body)
                case x: SForeignPrivate =>
                  x.statements.foreach(fgo(_, priv = true))
              } }
              items.foreach(fgo(_, intoPrivate))
            case c: SClassStatement if c.body.nonEmpty || c.context.nonEmpty =>
              // class bodies are dead code: every member or context died
              // in the fused type processing with "undefined type" —
              // refusing the statement keeps that contract explicit
              throw Refusal(c.loc.span,
                "error: class bodies are not supported (members die: undefined type)")
            case _: SFixity | _: SClassStatement | _: SErrorStatement => ()
            case _ => ()
            } }
          }
          walk(more, intoPrivate)
      }
    }

    def sigV(n: SName): V[Type] = lctx.binderAtSite(n) getOrElse lctx.varFor(n)

    def lowerLet(ss: List[SStatement]): (List[ImplicitBinding], List[ExplicitBinding]) = {
      val (groups, sigs) = collectBlock(ss)
      pairSigs(scala.collection.mutable.LinkedHashMap(groups.map { case (v, b, _) => v -> b }: _*), sigs)
    }

    walk(sts, intoPrivate = false)

    locally {
      val (is, es) = pairSigs(topGroups, topSigs.result())
      implicits = is
      explicits = es
    }

    val module = Module(mkPos(fileName, contents, Span(1, 1, 1, 1)), mh.name,
      mh.importExports,
      fields.reverse, tables.reverse, foreignData.reverse,
      (types.reverse: List[com.clarifi.reporting.ermine.syntax.TypeDef]) ++ dataStmts.reverse,
      foreigns.reverse, implicits, explicits, privateTerms, privateTypes)

    val er = ErParseState(
      moduleName = mh.name,
      canonicalTerms = scope.canonicalTerms,
      canonicalTypes = scope.canonicalTypes,
      termNames = scope.termNames ++ lctx.placeholderNames,
      typeNames = tctx.typeNames ++ tctx.placeholderTypeNames ++ ownTypeNames,
      termOrigins = scope.termOrigins,
      typeOrigins = scope.typeOrigins)
    (module, scalaparsers.ParseState.mk(fileName, contents, er))
  }

  /** LSP-FFI: with `foreignTolerant` OFF this is unreachable in a batch
    * load — the renamer's own foreign-class check refuses the module one
    * phase earlier — and its Death is kept for the editor's non-tolerant
    * path, which collects the rename diagnostic instead of throwing.
    * With the option ON nothing dies: the failure rides on the
    * `ForeignClass` to the loader, which decides where to warn. */
  private def foreignClass(name: String, sp: Span, fileName: String)(implicit s: SessionEnv): ForeignClass = {
    val pos = Pos(fileName, "", sp.startLine, sp.startCol, false)
    com.clarifi.reporting.ermine.parsing.ForeignClasses.classLookup(pos, name) match {
      case Right(c)                     => c
      case Left(e) if s.foreignTolerant =>
        ForeignClass(pos, classOf[com.clarifi.reporting.ermine.UnresolvedForeign],
                     Some(ForeignFailure(name, literalSpan(sp, name), e)))
      case Left(e)                      => throw Death(pos.report(Document.text(s"error loading '$name'")))
    }
  }

  /** The extent of a STRING LITERAL, given the span the parser recorded
    * for it and the value it parsed to (LSP-FFI review finding P-3).
    *
    * `spanned` ends a token's span where the NEXT token begins, so a
    * literal's recorded span runs over the trailing whitespace and a
    * diagnostic built from it squiggles one character too far.  The
    * literal itself is the value plus its two quotes; escapes can only
    * make the source longer than the value, never shorter, so clamp to
    * the recorded end rather than trusting the arithmetic.  A literal
    * that spans lines (there are none in practice) keeps its span. */
  private def literalSpan(sp: Span, value: String): Span =
    if (sp.endLine != sp.startLine) sp
    else Span(sp.startLine, sp.startCol, sp.startLine,
              math.min(sp.endCol, sp.startCol + value.length + 2))
}
