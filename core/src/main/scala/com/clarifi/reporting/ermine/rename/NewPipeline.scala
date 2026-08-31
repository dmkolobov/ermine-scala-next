package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{
  Annot, Bound, Global, ImplicitBinding, ExplicitBinding, Kind, Local, Name,
  Pattern, Term, Type, V, Alt, Let }
import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleHeader }
import com.clarifi.reporting.ermine.session.SessionEnv
import com.clarifi.reporting.ermine.surface._
import com.clarifi.reporting.ermine.syntax.{
  DataStatement, FieldStatement, ForeignBlock, ForeignClass,
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

  def readModule(fileName: String, contents: String, mh: ModuleHeader)
                (implicit s: SessionEnv, su: Supply): (scalaparsers.ParseState[ErParseState], Module) = {

    val sm = SurfaceParsers.module(fileName, contents, mh.name) match {
      case Right(m)  => m
      case Left(err) => throw Death(err.pretty)
    }
    // batch loads REFUSE unparseable statements (the tolerant splitter
    // keeps their extent as SErrorStatement for editor flows; a module
    // load must not silently drop them — D3, Ugly.e)
    def firstError(ss: List[SStatement]): Option[SErrorStatement] = ss.collectFirst(Function.unlift {
      case e: SErrorStatement          => Some(e)
      case SPrivateBlock(_, ss2)       => firstError(ss2)
      case SDatabaseBlock(_, _, ss2)   => firstError(ss2)
      case _                           => None
    })
    firstError(sm.statements).foreach { e =>
      throw Death(mkPos(fileName, contents, e.loc.span)
        .report(Document.text("error: unparseable statement (" + e.message + ")")))
    }

    val scope = ModuleScope.importing(mh.name, ModuleScope.Scope.empty,
      s.termNames, s.cons.keySet, mh.imports, s.termNameOrigins, s.consOrigins)
    val renamed = Renamer.renameOrDie(sm, scope, contents)
    val (restatements, reDiags) = Reassoc.module(sm, scope)
    reDiags.headOption.foreach { d =>
      throw Death(mkPos(fileName, contents, d.span).report(Document.text(d.message)))
    }

    // fixity declarations are part of the declared NAMES (binders and
    // exported Globals carry them); no block-level decls exist in the corpus
    val termFix = sm.statements.collect {
      case SFixity(_, f, false, ops) => ops.map(_.spelling -> f) }.flatten.toMap
    val typeFix = sm.statements.collect {
      case SFixity(_, f, true, ops) => ops.map(_.spelling -> f) }.flatten.toMap

    val lctx = Lower(renamed, fileName, s.termNames, scope, termFix)
    val tctx = TyLower(renamed, fileName, mh.name, s.cons ++ s.privateCons, su, typeFix)
    lctx.lowerAnnot = (t: STy) => TyLower.annot(t, tctx)

    val (module, ps) = assemble(mh, restatements, lctx, tctx, fileName, contents, scope)
    lctx.diags.result().headOption.foreach { d =>
      throw Death(mkPos(fileName, contents, d.span).report(Document.text(d.message)))
    }
    (ps, module)
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

  private def mkPos(file: String, contents: String, sp: Span): Pos = {
    val line = contents.linesIterator.drop(sp.startLine - 1).nextOption().getOrElse("").replaceAll("\\r$", "")
    Pos(file, line, sp.startLine, sp.startCol, false)
  }

  // ------------------------------------------------------------- assembly
  // moduleBody's `go` bucketing, ported; sig pairing per checkBindings
  // (by shared V, Annot.plain, "missing definition" preserved).

  private def assemble(mh: ModuleHeader, sts: List[SStatement],
                       lctx: Lower.Ctx, tctx: TyLower.TCtx,
                       fileName: String, contents: String, scope: ModuleScope.Scope)
                      (implicit s: SessionEnv, su: Supply): (Module, scalaparsers.ParseState[ErParseState]) = {

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

    def collectBlock(bs: List[SStatement]): (List[(V[Type], ImplicitBinding)], List[(V[Type], Type, Span)]) = {
      val grouped = scala.collection.mutable.LinkedHashMap[String, (V[Type], List[Alt])]()
      val sigs = List.newBuilder[(V[Type], Type, Span)]
      // equations of one name must be consecutive among equations —
      // gatherBindings parity (an interleaved equation silently merging
      // into an earlier group was a 4.2 regression, caught by the pin)
      var lastEq: Option[String] = None
      bs foreach {
        case SEquation(l, n, args, body, wh) =>
          if (grouped.contains(n.spelling) && !lastEq.contains(n.spelling))
            throw Death(mkPos(fileName, contents, n.span)
              .report(Document.text(s"error: interleaved equations for ${n.spelling}")))
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
            case Some((v0, as)) => (v0, as :+ alt)
            case None           => (v, List(alt))
          }
        case SSigStatement(l, ns, t) =>
          tctx.resetKindScope()
          val ty = TyLower.annot(t, tctx).body
          ns.foreach { n =>
            val v = lctx.binderAtSite(n) getOrElse lctx.varFor(n)
            sigs += ((v, ty, n.span))
          }
        case _ => ()
      }
      (grouped.values.toList.map { case (v, as) => v -> ImplicitBinding(v.loc, v, as) },
       sigs.result())
    }

    def pairSigs(im: collection.Map[V[Type], ImplicitBinding],
                 sigs: List[(V[Type], Type, Span)]): (List[ImplicitBinding], List[ExplicitBinding]) = {
      val es = sigs.map { case (v, ty, sp) =>
        im.get(v) match {
          case Some(i) => ExplicitBinding(i.loc, i.v, Annot.plain(i.loc, ty), i.alts)
          case None => throw Death(mkPos(fileName, contents, sp)
            .report(Document.text("missing definition")))
        }
      }
      ((im -- es.map(_.v)).values.toList, es)
    }

    def bindingBlock(bs: List[SStatement], intoPrivate: Boolean): Unit = {
      val (groups, sigs) = collectBlock(bs)
      groups.foreach { case (v, b) =>
        topGroups.get(v) match {
          case Some(_) =>
            // a later adjacency block re-opening a name: refused, as above
            throw Death(mkPos(fileName, contents, Span(0, 0, 0, 0))
              .report(Document.text("error: interleaved equations for " +
                b.v.name.map(_.string).getOrElse("?"))))
          case None => topGroups(v) = b
        }
      }
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
                    foreignClass(x.className, x.classSpan))
                  if (priv) privateTypes = privateTypes + ownTypeNames(tctx.localTypeName(x.name.spelling))
                case x: SForeignFunction =>
                  foreigns ::= ForeignFunctionStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body, foreignClass(x.className, x.classSpan),
                    ForeignMember(lctx.pos(x.memberSpan), x.member))
                case x: SForeignMethod =>
                  foreigns ::= ForeignMethodStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body, ForeignMember(lctx.pos(x.memberSpan), x.member))
                case x: SForeignValue =>
                  foreigns ::= ForeignValueStatement(lctx.pos(x.loc.span), privTerm(priv, sigV(x.name)),
                    TyLower.annot(x.ty, tctx).body, foreignClass(x.className, x.classSpan),
                    ForeignMember(lctx.pos(x.memberSpan), x.member))
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
            case SPrivateBlock(_, ss)    => walk(ss, intoPrivate = true)
            case SDatabaseBlock(_, _, ss) => walk(ss, intoPrivate)
            case _: SFixity | _: SClassStatement | _: SErrorStatement => ()
            case _ => ()
          }
          walk(more, intoPrivate)
      }
    }

    def sigV(n: SName): V[Type] = lctx.binderAtSite(n) getOrElse lctx.varFor(n)

    def lowerLet(ss: List[SStatement]): (List[ImplicitBinding], List[ExplicitBinding]) = {
      val (groups, sigs) = collectBlock(ss)
      pairSigs(scala.collection.mutable.LinkedHashMap(groups: _*), sigs)
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

  private def foreignClass(name: String, sp: Span)(implicit s: SessionEnv): ForeignClass = {
    val pos = Pos("<foreign>", "", sp.startLine, sp.startCol, false)
    com.clarifi.reporting.ermine.parsing.StatementParsers.classLookup(pos, name) match {
      case Right(c) => c
      case Left(e)  => throw Death(pos.report(Document.text(s"error loading '$name'")))
    }
  }
}
