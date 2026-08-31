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
  Statement, TableStatement, TermStatement, TypeStatement }
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
    val scope = ModuleScope.importing(mh.name, ModuleScope.Scope.empty,
      s.termNames, s.cons.keySet, mh.imports, s.termNameOrigins, s.consOrigins)
    val renamed = Renamer.renameOrDie(sm, scope, contents)
    val (restatements, reDiags) = Reassoc.module(sm, scope)
    reDiags.headOption.foreach { d =>
      throw Death(mkPos(fileName, contents, d.span).report(Document.text(d.message)))
    }

    val lctx = Lower(renamed, fileName, s.termNames, scope)
    val tctx = TyLower(renamed, fileName, mh.name, s.cons ++ s.privateCons, su)

    val (module, ps) = assemble(mh, restatements, lctx, tctx, fileName, contents, scope)
    lctx.diags.result().headOption.foreach { d =>
      throw Death(mkPos(fileName, contents, d.span).report(Document.text(d.message)))
    }
    (ps, module)
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

    // binding statements group per adjacency block; collect (spelling ->
    // (V, alts)) then pair sigs by the SAME V
    def bindingBlock(bs: List[SStatement], intoPrivate: Boolean): Unit = {
      val grouped = scala.collection.mutable.LinkedHashMap[String, (V[Type], List[Alt])]()
      val sigs = List.newBuilder[(V[Type], Type, Span)]
      bs foreach {
        case SEquation(l, n, args, body, wh) =>
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
          val ty = TyLower.annot(t, tctx).body
          ns.foreach { n =>
            val v = lctx.binderAtSite(n) getOrElse lctx.varFor(n)
            sigs += ((v, ty, n.span))
          }
        case _ => ()
      }
      val im = grouped.values.map { case (v, as) => v -> ImplicitBinding(v.loc, v, as) }.toMap
      val es = sigs.result().map { case (v, ty, sp) =>
        im.get(v) match {
          case Some(i) => ExplicitBinding(i.loc, i.v, Annot.plain(i.loc, ty), i.alts)
          case None => throw Death(mkPos(fileName, contents, sp)
            .report(Document.text("missing definition")))
        }
      }
      val is = (im -- es.map(_.v)).values.toList
      implicits = implicits ++ is
      explicits = explicits ++ es
      if (intoPrivate) privateTerms = privateTerms ++ is.map(_.v) ++ es.map(_.v)
    }

    def ownTypeVar(n: SName): V[Kind] = {
      val v = V(lctx.pos(n.span), -(n.span.startLine * 1000 + n.span.startCol) - 5000000,
                Some(Local(n.spelling): Name), Bound, tctx.freshKind(n.span))
      ownTypeNames += (Local(n.spelling): Name) -> v
      v
    }

    def walk(sts0: List[SStatement], intoPrivate: Boolean): Unit = {
      // adjacent binding statements form one group (gatherBindings parity)
      val (block, rest) = sts0.span(st => st.isInstanceOf[SEquation] || st.isInstanceOf[SSigStatement])
      if (block.nonEmpty) { bindingBlock(block, intoPrivate); walk(rest, intoPrivate); return }
      sts0 match {
        case Nil => ()
        case st :: more =>
          st match {
            case SFieldStatement(l, ns, t) =>
              val ty = TyLower.annot(t, tctx).body
              fields ::= FieldStatement(lctx.pos(l.span),
                ns.map(n => ownTypeVar(n)), ty)
            case STableStatement(l, db, ns, t) =>
              val ty = TyLower.annot(t, tctx).body
              tables ::= TableStatement(lctx.pos(l.span), db.getOrElse(""),
                ns.map(n => (List.empty[Name], lctx.varFor(n))), ty)
            case STypeAlias(l, n, ks, bs, body) =>
              val kvs = ks.map(k => tctx.kindVar(tctx.binderIdAt(k.span).getOrElse(-1 - k.span.startCol), k.spelling, k.span))
              val tvs = bs.map(b => tctx.tyVar(tctx.binderIdAt(b.name.span).getOrElse(-2 - b.name.span.startCol * 7),
                                               b.name.spelling, b.name.span, b.kind.map(TyLower.kind(_, tctx))))
              types ::= TypeStatement(lctx.pos(l.span), ownTypeVar(n), kvs, tvs,
                TyLower.ty(body, tctx))
              if (intoPrivate) privateTypes = privateTypes + ownTypeNames(Local(n.spelling))
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
              if (intoPrivate) privateTypes = privateTypes + ownTypeNames(Local(n.spelling))
            case SForeignBlock(_, items) =>
              def fgo(f: SForeign): Unit = f match {
                case x: SForeignData =>
                  foreignData ::= ForeignDataStatement(lctx.pos(x.loc.span), ownTypeVar(x.name),
                    x.args.map(b => tctx.tyVar(tctx.binderIdAt(b.name.span).getOrElse(-6 - b.name.span.startCol * 19),
                                               b.name.spelling, b.name.span, None)),
                    foreignClass(x.className, x.classSpan))
                case x: SForeignFunction =>
                  foreigns ::= ForeignFunctionStatement(lctx.pos(x.loc.span), sigV(x.name),
                    TyLower.annot(x.ty, tctx).body, foreignClass(x.className, x.classSpan),
                    ForeignMember(lctx.pos(x.memberSpan), x.member))
                case x: SForeignMethod =>
                  foreigns ::= ForeignMethodStatement(lctx.pos(x.loc.span), sigV(x.name),
                    TyLower.annot(x.ty, tctx).body, ForeignMember(lctx.pos(x.memberSpan), x.member))
                case x: SForeignValue =>
                  foreigns ::= ForeignValueStatement(lctx.pos(x.loc.span), sigV(x.name),
                    TyLower.annot(x.ty, tctx).body, foreignClass(x.className, x.classSpan),
                    ForeignMember(lctx.pos(x.memberSpan), x.member))
                case x: SForeignConstructor =>
                  foreigns ::= ForeignConstructorStatement(lctx.pos(x.loc.span), sigV(x.name),
                    TyLower.annot(x.ty, tctx).body)
                case x: SForeignSubtype =>
                  foreigns ::= ForeignSubtypeStatement(lctx.pos(x.loc.span), sigV(x.name),
                    TyLower.annot(x.ty, tctx).body)
                case x: SForeignPrivate =>
                  // members of a private group are marked private
                  x.statements.foreach(fgo)  // TODO privateTerms for these (4.2)
              }
              items.foreach(fgo)
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
      val savedI = implicits; val savedE = explicits
      implicits = Nil; explicits = Nil
      bindingBlock(ss, intoPrivate = false)
      val r = (implicits, explicits)
      implicits = savedI; explicits = savedE
      r
    }

    walk(sts, intoPrivate = false)

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
      typeNames = tctx.typeNames ++ ownTypeNames,
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
