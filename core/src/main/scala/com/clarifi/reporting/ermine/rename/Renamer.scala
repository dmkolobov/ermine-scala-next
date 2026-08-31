package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{ Fixity, Global, Idfix, InfixN, Local, Name, Prefix }
import com.clarifi.reporting.ermine.surface._

/** The term-side renamer (tracker/LSP-ROADMAP.md, Stage 1 items 3.2a/b).
  *
  * Resolution over the surface AST with the parse dependency severed:
  * every block collects its binder HEADS before any right-hand side
  * resolves, so the fused pipeline's letrec shadow-rewrite (LocalBlocks/
  * checkShadows/subTerm) has no reason to exist.  References resolve
  * through the frame stack, then the module's own top-levels, then the
  * canonical import scope (ModuleScope) — never through the termNames
  * superset (the loaded-but-unimported leak pin).
  *
  * Scoping semantics per the pinned spec (TestStage1Pins/TestScopes):
  * sig + all equations of one name share ONE binder whose def-site is the
  * LAST equation (globalTermDef relocation parity); let/where blocks
  * scope over every rhs and the body; a do binder's rhs sees the outer
  * name, later statements see the binder; case/lambda patterns scope
  * over their bodies; unresolved names are TOLERATED (they die at
  * typecheck, not here).  Refusals owed by the disposition ledger:
  * top-level import shadowing and ':'-constructor binders are recorded
  * as diagnostics.
  *
  * Outputs are the LSP's food: occurrences (span, spelling-as-written,
  * resolution incl. import path + origin for hover labels), binder
  * table (def-site spans, kinds), scope frames for scope-at-position.
  */
object Renamer {

  sealed abstract class Resolution
  final case class ToBinder(id: Int) extends Resolution
  final case class ToGlobal(g: Global, importedAs: Name, origin: Global) extends Resolution
  final case class Unresolved(spelling: String) extends Resolution
  final case class Ambiguous(spelling: String, candidates: List[Name]) extends Resolution

  sealed abstract class BinderKind
  case object TopLevel extends BinderKind
  case object Arg      extends BinderKind
  case object LetBound extends BinderKind
  case object WhereBound extends BinderKind
  case object DoBound  extends BinderKind
  case object CaseBound extends BinderKind
  case object TyParam    extends BinderKind  // forall/exists/some, data/type/class args
  case object TyImplicit extends BinderKind  // per-annotation auto-quantified var
  case object KindParam  extends BinderKind  // {k} kind-brace binders
  case object TyDef      extends BinderKind  // module-level type definitions

  final case class BinderInfo(id: Int, spelling: String, defSite: Span, kind: BinderKind)
  final case class Occurrence(span: Span, spelling: String, resolution: Resolution)
  final case class Frame(span: Span, bindings: Map[String, Int])
  final case class Diag(span: Span, message: String)

  final case class Result(
    occurrences: List[Occurrence],
    binders: Map[Int, BinderInfo],
    frames: List[Frame],
    diagnostics: List[Diag],
    moduleTerms: Map[String, Int] = Map()) {

    def binderAt(line: Int, col: Int): Option[BinderInfo] =
      occurrences.find(o => o.span.contains(line, col)).flatMap(_.resolution match {
        case ToBinder(id) => binders.get(id)
        case _            => None
      })

    /** Innermost-first name set visible at a position. */
    def scopeAt(line: Int, col: Int): Map[String, Int] =
      frames.filter(_.span.contains(line, col))
        .sortBy(f => (f.span.startLine - f.span.endLine, f.span.startCol - f.span.endCol))
        .foldRight(Map.empty[String, Int])((f, acc) => acc ++ f.bindings)
  }

  // ------------------------------------------------------------------ state

  private final class S(scope: ModuleScope.Scope) {
    var nextId = 0
    val occs = List.newBuilder[Occurrence]
    val binders = Map.newBuilder[Int, BinderInfo]
    val frames = List.newBuilder[Frame]
    val diags = List.newBuilder[Diag]

    def fresh(): Int = { val i = nextId; nextId += 1; i }

    def addBinder(spelling: String, site: Span, kind: BinderKind): Int = {
      val id = fresh()
      binders += id -> BinderInfo(id, spelling, site, kind)
      id
    }

    /** Local key matching the canonical map's fixity-bucket equality. */
    private def probe(spelling: String, opPos: Option[PosClass]): Local = opPos match {
      case Some(OperandPos) => Local(spelling, Prefix(9))
      case Some(PostOperandPos) => Local(spelling, InfixN(9))
      case None => Local(spelling, Idfix)
    }

    def globalFor(n: Name): Global = n match {
      case g: Global => g
      case l: Local  => sys.error("canonical answer is Local: " + l)
    }

    def originOf(g: Global): Global = {
      def chase(x: Global, depth: Int): Global =
        if (depth > 32) x
        else scope.termOrigins.get(x) match {
          case Some(List(y)) if y != x => chase(y, depth + 1)
          case _ => x
        }
      chase(g, 0)
    }

    def resolveType(spelling: String, opPos: Option[PosClass]): Option[Resolution] =
      scope.canonicalTypes.get(probe(spelling, opPos)) map {
        case List(n) =>
          val g = n match { case g: Global => g; case l: Local => l global "" }
          ToGlobal(g, n, originOfTy(g))
        case ns => Ambiguous(spelling, ns)
      }

    def originOfTy(g: Global): Global = {
      def chase(x: Global, depth: Int): Global =
        if (depth > 32) x
        else scope.typeOrigins.get(x) match {
          case Some(List(y)) if y != x => chase(y, depth + 1)
          case _ => x
        }
      chase(g, 0)
    }

    def resolveGlobal(spelling: String, opPos: Option[PosClass]): Option[Resolution] =
      scope.canonicalTerms.get(probe(spelling, opPos)) map {
        case List(n) =>
          val g = n match { case g: Global => g; case l: Local => l global "" }
          ToGlobal(g, n, originOf(g))
        case ns => Ambiguous(spelling, ns)
      }

    def occur(name: SName, res: Resolution): Unit =
      occs += Occurrence(name.span, name.spelling, res)
  }

  private type Env = List[Map[String, Int]]  // innermost first

  private def lookup(env: Env, spelling: String): Option[Int] =
    env.collectFirst { case m if m.contains(spelling) => m(spelling) }

  /** NameParsers.opName: a bare `(op)` reference probes the infix/postfix
    * bucket; `(prefix op)`/`(postfix op)` select their declared bucket. */
  private def refPos(n: SName): Option[PosClass] = n.form match {
    case ParenOp                  => Some(PostOperandPos)
    case ParenFixityBinder(f)     => f match {
      case Prefix(_) => Some(OperandPos)
      case Idfix     => None
      case _         => Some(PostOperandPos)
    }
    case _                        => None
  }

  // ------------------------------------------------------------ binder heads

  /** One binder per unique name over sigs+equations; def-site = LAST
    * equation's name span (globalTermDef relocation parity), else the
    * (last) sig mention. */
  private def collectHeads(sts: List[SStatement], kind: BinderKind, s: S): Map[String, Int] = {
    val sites = scala.collection.mutable.LinkedHashMap[String, Span]()
    sts foreach {
      case SSigStatement(_, ns, _) =>
        ns.foreach(n => if (!sites.contains(n.spelling)) sites(n.spelling) = n.span)
      case SEquation(_, n, _, _, _) =>
        sites(n.spelling) = n.span  // last equation wins
      case _ => ()
    }
    sites.flatMap { case (sp, site) =>
      // ledger: a ':'-operator binder naming an imported constructor is
      // refused wherever it binds (localTermDef parity)
      if (kind != TopLevel && (sp startsWith ":") &&
          s.resolveGlobal(sp, Some(PostOperandPos)).isDefined) {
        s.diags += Diag(site, s"cannot bind $sp: it would shadow a data constructor")
        None
      } else Some(sp -> s.addBinder(sp, site, kind))
    }.toMap
  }

  // ---------------------------------------------------------------- walking

  def rename(m: SModule, scope: ModuleScope.Scope): Result = {
    val s = new S(scope)

    val top = topLevelHeads(m.statements, s)
    val env: Env = List(top)
    val moduleSpan = m.statements.headOption
      .map(st => st.loc.span to m.statements.last.loc.span)
      .getOrElse(Span(1, 1, 1, 1))
    s.frames += Frame(moduleSpan, top)

    m.statements.foreach(statement(_, env, s))
    val tyDefs = collectTypeDefs(m.statements, s)
    m.statements.foreach(statementTypes(_, s, tyDefs))   // 3.2c: the type/kind side
    m.statements.foreach(foreignClasses(_, m.file, "", s))

    Result(s.occs.result(), s.binders.result(), s.frames.result(), s.diags.result(), top)
  }

  /** Rename; on the first diagnostic, throw Death rendered the way
    * Pos.report renders - "file:line:col:" + source line + caret - so the
    * LSP Diagnostics regex and no(...)/sessionProof keep working when
    * refusals move here from parse time (roadmap 3.2b, Decision f). */
  def renameOrDie(m: SModule, scope: ModuleScope.Scope, source: String): Result = {
    val r = rename(m, scope)
    r.diagnostics.headOption foreach { d =>
      val lineText = source.linesIterator.drop(d.span.startLine - 1)
        .nextOption().getOrElse("").replaceAll("\r$", "")
      val pos = scalaparsers.Pos(m.file, lineText, d.span.startLine, d.span.startCol, false)
      throw scalaparsers.Death(pos.report(scalaparsers.Document.text("error: " + d.message)))
    }
    r
  }

  /** Module-level and class-body binder heads share the globalTermDef
    * discipline: one binder per name, and the shadow-an-import refusal
    * (ledger). */
  private def topLevelHeads(sts: List[SStatement], s: S): Map[String, Int] = {
    val heads = collectHeads(sts, TopLevel, s)
    for ((sp, id) <- heads; if s.resolveGlobal(sp, None).exists(_.isInstanceOf[ToGlobal]))
      s.diags += Diag(s.binders.result()(id).defSite,
                      s"term definition would shadow global definition ($sp)")
    heads
  }

  private def foreignClasses(st: SStatement, file: String, source: String, s: S): Unit = {
    def check(items: List[SForeign]): Unit = items foreach {
      case f: SForeignData     => lookup(f.className, f.classSpan)
      case f: SForeignFunction => lookup(f.className, f.classSpan)
      case f: SForeignValue    => lookup(f.className, f.classSpan)
      case f: SForeignPrivate  => check(f.statements)
      case _ => ()
    }
    // Class.forName leaves parsing (roadmap 3.2b); the classMap cache is
    // shared with the fused pipeline deliberately - one process-wide
    // global, same as before.
    def lookup(name: String, span: Span): Unit = {
      val pos = scalaparsers.Pos(file, "", span.startLine, span.startCol, false)
      com.clarifi.reporting.ermine.parsing.StatementParsers.classLookup(pos, name) match {
        case Left(e)  => s.diags += Diag(span, s"error loading '$name'")
        case Right(_) => ()
      }
    }
    st match {
      case SForeignBlock(_, items) => check(items)
      case SPrivateBlock(_, ss)    => ss.foreach(foreignClasses(_, file, source, s))
      case _ => ()
    }
  }

  // ------------------------------------------------------------ type side
  // (3.2c) Type references resolve through binder frames, then the
  // canonical type scope; UNBOUND lowercase names are per-annotation
  // implicit variables — the first occurrence binds, later ones share
  // (per-signature quantification, as pinned: "bare sig type variables
  // quantify per signature, independently").  The fused pipeline reaches
  // the same effective semantics through module-wide typeNames insertion
  // plus binding-group generalization; equivalence is 4.1's differential
  // obligation.  Kind atoms (*, rho/phi/constraint and unicode forms)
  // are builtin; {k} binders bind kind variables per declaration head.

  private val kindAtoms = Set("*", "rho", "ρ", "phi", "φ", "constraint", "Γ")

  /** Module-level TYPE definition names (data/type/class/field/foreign
    * data) — the outermost type frame, so sigs can reference the
    * module's own types (Control/Monoid.e's `Monoid (m, n)`). */
  private def collectTypeDefs(sts: List[SStatement], s: S): Map[String, Int] = {
    val out = scala.collection.mutable.LinkedHashMap[String, Int]()
    def add(n: SName): Unit =
      if (!out.contains(n.spelling)) out(n.spelling) = s.addBinder(n.spelling, n.span, TyDef)
    def fgo(f: SForeign): Unit = f match {
      case x: SForeignData    => add(x.name)
      case x: SForeignPrivate => x.statements.foreach(fgo)
      case _ => ()
    }
    def go(st: SStatement): Unit = st match {
      case x: SDataStatement    => add(x.name)
      case x: STypeAlias        => add(x.name)
      case x: SClassStatement   => add(x.name); x.body.foreach(go)
      case x: SFieldStatement   => x.names.foreach(add)
      case SForeignBlock(_, is) => is.foreach(fgo)
      case SPrivateBlock(_, ss)     => ss.foreach(go)
      case SDatabaseBlock(_, _, ss) => ss.foreach(go)
      case _ => ()
    }
    sts.foreach(go)
    out.toMap
  }

  private final class TyCtx(val s: S, base: Map[String, Int] = Map()) {
    var frames: List[Map[String, Int]] = if (base.isEmpty) Nil else List(base)
    var implicits = Map.empty[String, Int]         // per-annotation set

    def push(m: Map[String, Int]): Unit = frames = m :: frames
    def pop(): Unit = frames = frames.tail

    def resolve(n: SName, opPos: Option[PosClass]): Resolution =
      frames.collectFirst { case f if f.contains(n.spelling) => f(n.spelling) }
        .map(ToBinder.apply)
        .orElse(s.resolveType(n.spelling, opPos))
        .getOrElse {
          if (n.spelling.headOption.exists(_.isLower) && !kindAtoms(n.spelling)) {
            val id = implicits.getOrElse(n.spelling, {
              val i = s.addBinder(n.spelling, n.span, TyImplicit)
              implicits += n.spelling -> i
              i
            })
            ToBinder(id)
          } else Unresolved(n.spelling)  // unknown constructors die at typecheck
        }
  }

  private def tyBinderFrame(bs: List[SBinder], kind: BinderKind, ctx: TyCtx): Map[String, Int] = {
    val m = bs.map(b => b.name.spelling -> ctx.s.addBinder(b.name.spelling, b.name.span, kind)).toMap
    // binder kinds resolve in the enclosing context (before this frame)
    bs.foreach(_.kind.foreach(ty(_, ctx)))
    m
  }

  private def kindFrame(ks: List[SName], ctx: TyCtx): Map[String, Int] =
    ks.map(k => k.spelling -> ctx.s.addBinder(k.spelling, k.span, KindParam)).toMap

  private def ty(t: STy, ctx: TyCtx): Unit = t match {
    case STyName(n) =>
      val res = if (kindAtoms(n.spelling)) ToGlobal(Global("Builtin", n.spelling), Local(n.spelling), Global("Builtin", n.spelling))
                else ctx.resolve(n, refPos(n))
      ctx.s.occur(n, res)
    case STyApp(f, a) => ty(f, ctx); ty(a, ctx)
    case STyChain(c) => c.items.foreach {
      case Left(operand) => ty(operand, ctx)
      case Right(op) =>
        // '*' lexes as an operator at operand position but IS the star
        // kind atom (3.3's re-associator needs the same awareness)
        val res = if (Set("->", "=>", "<-")(op.name.spelling) || kindAtoms(op.name.spelling))
          ToGlobal(Global("Builtin", op.name.spelling), Local(op.name.spelling), Global("Builtin", op.name.spelling))
        else ctx.resolve(op.name, Some(op.posClass))
        ctx.s.occur(op.name, res)
    }
    case STyParen(_, i) => ty(i, ctx)
    case STyTuple(_, es) => es.foreach(ty(_, ctx))
    case STyList(_, e) => e.foreach(ty(_, ctx))
    case STyRowBrace(_, _, inner)   => inner.foreach(ty(_, ctx))
    case STyRowBracket(_, _, inner) => inner.foreach(ty(_, ctx))
    case STyBanana(_, _, inner)     => inner.foreach(ty(_, ctx))
    case STyForall(_, ks, bs, body) =>
      ctx.push(kindFrame(ks, ctx))              // binder kinds see {k}
      val bf = tyBinderFrame(bs, TyParam, ctx)
      ctx.push(bf); ty(body, ctx); ctx.pop(); ctx.pop()
    case STyExists(_, bs, body) =>
      val bf = tyBinderFrame(bs, TyParam, ctx)
      ctx.push(bf); body.foreach(ty(_, ctx)); ctx.pop()
    case STySome(_, ks, bs, body) =>
      ctx.push(kindFrame(ks, ctx))
      val bf = tyBinderFrame(bs, TyParam, ctx)
      ctx.push(bf); ty(body, ctx); ctx.pop(); ctx.pop()
    case _: STyError => ()
  }

  /** One annotation = one implicit-quantification scope. */
  private def annot(t: STy, s: S, base: Map[String, Int]): Unit = { ty(t, new TyCtx(s, base)) }

  /** Declaration heads (data/type/class): kindArgs + typeArgs scope over
    * the declaration's types. */
  private def declTypes(ks: List[SName], bs: List[SBinder], tys: List[STy], s: S,
                        base: Map[String, Int]): Unit = {
    val ctx = new TyCtx(s, base)
    ctx.push(kindFrame(ks, ctx))
    ctx.push(tyBinderFrame(bs, TyParam, ctx))
    tys.foreach(ty(_, ctx))
    ctx.pop(); ctx.pop()
  }

  private def statementTypes(st: SStatement, s: S, base: Map[String, Int]): Unit = st match {
    case SSigStatement(_, _, t)         => annot(t, s, base)
    case SFieldStatement(_, _, t)       => annot(t, s, base)
    case STableStatement(_, _, _, t)    => annot(t, s, base)
    case STypeAlias(_, _, ks, bs, body) => declTypes(ks, bs, List(body), s, base)
    case SDataStatement(_, _, ks, bs, cons) =>
      // per-constructor foralls nest inside the declaration frame
      val ctx = new TyCtx(s, base)
      ctx.push(kindFrame(ks, ctx))
      ctx.push(tyBinderFrame(bs, TyParam, ctx))
      cons.foreach { c =>
        val ef = tyBinderFrame(c.exists, TyParam, ctx)
        ctx.push(ef); c.fields.foreach(ty(_, ctx)); ctx.pop()
      }
      ctx.pop(); ctx.pop()
    case SClassStatement(_, _, ks, bs, context, body) =>
      val ctx = new TyCtx(s, base)
      ctx.push(kindFrame(ks, ctx))
      ctx.push(tyBinderFrame(bs, TyParam, ctx))
      context.foreach(ty(_, ctx))
      ctx.pop(); ctx.pop()
      body.foreach(statementTypes(_, s, base))
    case SForeignBlock(_, items) =>
      def go(f: SForeign): Unit = f match {
        case x: SForeignData        => declTypes(Nil, x.args, Nil, s, base)
        case x: SForeignFunction    => annot(x.ty, s, base)
        case x: SForeignMethod      => annot(x.ty, s, base)
        case x: SForeignValue       => annot(x.ty, s, base)
        case x: SForeignConstructor => annot(x.ty, s, base)
        case x: SForeignSubtype     => annot(x.ty, s, base)
        case x: SForeignPrivate     => x.statements.foreach(go)
      }
      items.foreach(go)
    case SPrivateBlock(_, ss)     => ss.foreach(statementTypes(_, s, base))
    case SDatabaseBlock(_, _, ss) => ss.foreach(statementTypes(_, s, base))
    case SEquation(_, _, args, body, wh) =>
      args.foreach(patternTypes(_, s, base))
      termTypes(body, s, base)
      wh.foreach(_.statements.foreach(statementTypes(_, s, base)))
    case _ => ()
  }

  private def patternTypes(p: SPat, s: S, base: Map[String, Int]): Unit = p match {
    case SPSig(_, i, t)  => annot(t, s, base); patternTypes(i, s, base)
    case SPParen(_, i)   => patternTypes(i, s, base)
    case SPTuple(_, es)  => es.foreach(patternTypes(_, s, base))
    case SPList(_, es)   => es.foreach(patternTypes(_, s, base))
    case SPStrict(_, i)  => patternTypes(i, s, base)
    case SPLazy(_, i)    => patternTypes(i, s, base)
    case SPAs(_, _, i)   => patternTypes(i, s, base)
    case SPApp(_, args)  => args.foreach(patternTypes(_, s, base))
    case SPChain(c)      => c.items.foreach { case Left(q) => patternTypes(q, s, base); case _ => () }
    case _ => ()
  }

  private def termTypes(t: STerm, s: S, base: Map[String, Int]): Unit = t match {
    case SSig(_, tm, ann) => annot(ann, s, base); termTypes(tm, s, base)
    case SApp(f, a) => termTypes(f, s, base); termTypes(a, s, base)
    case SLam(_, ps, b) => ps.foreach(patternTypes(_, s, base)); termTypes(b, s, base)
    case SChain(c) => c.items.foreach { case Left(o) => termTypes(o, s, base); case _ => () }
    case SNeg(_, _, o) => termTypes(o, s, base)
    case SParen(_, i) => termTypes(i, s, base)
    case STuple(_, es) => es.foreach(termTypes(_, s, base))
    case SCase(_, e, alts) => termTypes(e, s, base); alts.foreach(a => { patternTypes(a.pattern, s, base); termTypes(a.body, s, base) })
    case SLet(_, ss, b) => ss.foreach(statementTypes(_, s, base)); termTypes(b, s, base)
    case SDo(_, ds) => ds.foreach { case SDoBind(_, p, _, r) => patternTypes(p, s, base); termTypes(r, s, base); case SDoExpr(e) => termTypes(e, s, base) }
    case SListLit(_, es, _) => es.foreach(termTypes(_, s, base))
    case SBraceLit(_, es, _) => es.foreach(termTypes(_, s, base))
    case SRecordLit(_, fs) => fs.foreach { case (k, v) => termTypes(k, s, base); termTypes(v, s, base) }
    case SRelEnvelope(_, as) => as.foreach { case SCombineArrow(_, _, e) => termTypes(e, s, base); case SFilterArrow(e) => termTypes(e, s, base); case _ => () }
    case SRemember(_, i) => termTypes(i, s, base)
    case _ => ()
  }

  private def statement(st: SStatement, env: Env, s: S): Unit = st match {
    case SEquation(_, n, args, body, wh) =>
      // the equation name is an occurrence of its top-level binder
      lookup(env, n.spelling).foreach(id => s.occur(n, ToBinder(id)))
      val argB = args.flatMap(patternBinders(_, Arg, s)).toMap
      if (argB.nonEmpty) {
        val sp = st.loc.span
        s.frames += Frame(sp, argB)
      }
      val env2 = argB :: env
      wh match {
        case None => term(body, env2, s)
        case Some(SWhere(wloc, ws)) =>
          // where scopes over the BODY and its own rhss (body parses first
          // in the fused pipeline; here it simply resolves in the block env)
          val whB = collectHeads(ws, WhereBound, s)
          s.frames += Frame(st.loc.span, whB)
          val env3 = whB :: env2
          term(body, env3, s)
          ws.foreach(statement(_, env3, s))
      }
    case SSigStatement(_, ns, _) =>
      // sig names are occurrences of the shared binder (goto-def from a
      // signature; and Lower's sig pairing joins through it)
      ns.foreach(n => lookup(env, n.spelling).foreach(id => s.occur(n, ToBinder(id))))
    case SPrivateBlock(_, ss)      => ss.foreach(statement(_, env, s))
    case SDatabaseBlock(_, _, ss)  => ss.foreach(statement(_, env, s))
    case SClassStatement(loc, _, _, _, _, body) =>
      // class bodies bind through the globalTermDef path (no LocalBlock);
      // members resolve like top-levels and refuse import shadowing.
      // (Their TYPE processing is dead in the fused pipeline - pinned -
      // and stays a typecheck-time matter, not a rename refusal.)
      val heads = topLevelHeads(body, s)
      if (heads.nonEmpty) s.frames += Frame(loc.span, heads)
      body.foreach(statement(_, heads :: env, s))
    case _ => ()  // fixity/data/type/field/table/foreign carry no term rhss
  }

  private def patternBinders(p: SPat, kind: BinderKind, s: S): Map[String, Int] = p match {
    case SPVar(n) =>
      // ledger: a ':'-operator binder that names an imported constructor
      if ((n.spelling startsWith ":") && s.resolveGlobal(n.spelling, Some(PostOperandPos)).isDefined) {
        s.diags += Diag(n.span, s"cannot bind ${n.spelling}: it would shadow a data constructor")
        Map()
      } else Map(n.spelling -> s.addBinder(n.spelling, n.span, kind))
    case SPAs(_, n, inner) =>
      Map(n.spelling -> s.addBinder(n.spelling, n.span, kind)) ++ patternBinders(inner, kind, s)
    case SPApp(con, args) =>
      conOccurrence(con, s); args.flatMap(patternBinders(_, kind, s)).toMap
    case SPChain(c) =>
      c.items.flatMap {
        case Left(pat) => patternBinders(pat, kind, s)
        case Right(op) => conOccurrence(op.name, s); Nil
      }.toMap
    case SPParen(_, i)  => patternBinders(i, kind, s)
    case SPTuple(_, es) => es.flatMap(patternBinders(_, kind, s)).toMap
    case SPList(_, es)  => es.flatMap(patternBinders(_, kind, s)).toMap
    case SPStrict(_, i) => patternBinders(i, kind, s)
    case SPLazy(_, i)   => patternBinders(i, kind, s)
    case SPSig(_, i, _) => patternBinders(i, kind, s)
    case _ => Map()
  }

  private def conOccurrence(n: SName, s: S): Unit = {
    val opPos = if (n.spelling.headOption.exists(c => !c.isLetter && c != '`')) Some(PostOperandPos: PosClass) else None
    s.occur(n, s.resolveGlobal(n.spelling, opPos) getOrElse Unresolved(n.spelling))
  }

  /** Channel R (tracker/desugar-hooks.md): inside [| |] combine/filter
    * arms these spellings are REBOUND — referent and fixity — to the
    * relational combinators, beating every scope layer (the fused
    * parser's bindName rebinding did the same).  Never rename arms. */
  val relOverrides: Map[String, Global] = Map(
    "<=" -> Global("Relation.Predicate", "<=", InfixN(4)),
    ">=" -> Global("Relation.Predicate", ">=", InfixN(4)),
    "<"  -> Global("Relation.Predicate", "<", InfixN(4)),
    "==" -> Global("Relation.Predicate", "==", InfixN(4)),
    "!=" -> Global("Relation.Predicate", "!=", InfixN(4)),
    ">"  -> Global("Relation.Predicate", ">", InfixN(4)),
    "not" -> Global("Relation.Predicate", "not", Idfix),
    "&&" -> Global("Relation.Predicate", "&&", com.clarifi.reporting.ermine.InfixR(3)),
    "||" -> Global("Relation.Predicate", "||", com.clarifi.reporting.ermine.InfixR(2)),
    "+"  -> Global("Relation.Op", "+", com.clarifi.reporting.ermine.InfixL(6)),
    "-"  -> Global("Relation.Op", "-", com.clarifi.reporting.ermine.InfixL(6)),
    "*"  -> Global("Relation.Op", "*", com.clarifi.reporting.ermine.InfixL(7)),
    "/"  -> Global("Relation.Op", "/", com.clarifi.reporting.ermine.InfixL(7)),
    "//" -> Global("Relation.Op", "//", com.clarifi.reporting.ermine.InfixL(7)),
    "++" -> Global("Relation.Op", "++", com.clarifi.reporting.ermine.InfixL(5)))

  private def reference(n: SName, opPos: Option[PosClass], env: Env, s: S,
                        rel: Boolean = false): Unit = {
    val res =
      (if (rel) relOverrides.get(n.spelling).map(g => ToGlobal(g, g, g)) else None)
        .orElse(lookup(env, n.spelling).map(ToBinder.apply))
        .orElse(s.resolveGlobal(n.spelling, opPos))
        .getOrElse(Unresolved(n.spelling))
    s.occur(n, res)
  }

  private def term(t: STerm, env: Env, s: S, rel: Boolean = false): Unit = t match {
    case SVar(n) => reference(n, refPos(n), env, s, rel)
    case SApp(f, a) => term(f, env, s, rel); term(a, env, s, rel)
    case SLam(loc, ps, body) =>
      val b = ps.flatMap(patternBinders(_, Arg, s)).toMap
      if (b.nonEmpty) s.frames += Frame(loc.span, b)
      term(body, b :: env, s)
    case SSig(_, tm, _) => term(tm, env, s, rel)
    case SChain(c) =>
      c.items.foreach {
        case Left(operand) => term(operand, env, s, rel)
        case Right(op)     => reference(op.name, Some(op.posClass), env, s, rel)
      }
    case SNeg(_, _, operand) => term(operand, env, s, rel)
    case SParen(_, i) => term(i, env, s, rel)
    case STuple(_, es) => es.foreach(term(_, env, s, rel))
    case SCase(_, scrut, alts) =>
      term(scrut, env, s)
      alts.foreach { a =>
        val b = patternBinders(a.pattern, CaseBound, s)
        if (b.nonEmpty) s.frames += Frame(a.loc.span, b)
        term(a.body, b :: env, s)
      }
    case SLet(loc, sts, body) =>
      val b = collectHeads(sts, LetBound, s)
      if (b.nonEmpty) s.frames += Frame(loc.span, b)
      val env2 = b :: env
      sts.foreach(statement(_, env2, s))
      term(body, env2, s)
    case SDo(_, stmts) =>
      // sequential: a binder's rhs sees the OUTER env; later stmts see it
      var cur = env
      stmts.foreach {
        case SDoBind(loc, pat, _, rhs) =>
          term(rhs, cur, s)                      // unbind-before-rhs (pinned)
          val b = patternBinders(pat, DoBound, s)
          if (b.nonEmpty) s.frames += Frame(loc.span, b)
          cur = b :: cur
        case SDoExpr(e) => term(e, cur, s)
      }
    case SListLit(_, es, _)  => es.foreach(term(_, env, s))
    case SBraceLit(_, es, _) => es.foreach(term(_, env, s))
    case SRecordLit(_, fs)   => fs.foreach { case (k, v) => term(k, env, s); term(v, env, s) }
    case SRelEnvelope(_, arrows) => arrows.foreach {
      // combine/filter arms carry the channel-R override; rename never
      case SRenameArrow(_, to, from) => reference(to, None, env, s); reference(from, None, env, s)
      case SCombineArrow(_, as, e)   => reference(as, None, env, s); term(e, env, s, rel = true)
      case SFilterArrow(e)           => term(e, env, s, rel = true)
    }
    case SRemember(_, i) => term(i, env, s)
    case _ => ()  // literals, holes, sections, errors
  }
}
