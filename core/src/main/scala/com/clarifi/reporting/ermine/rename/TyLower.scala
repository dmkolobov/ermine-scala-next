package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{
  Annot, AppT, Arrow, Bound, ConcreteRho, Constraint, Exists, Field, Forall,
  Free, Global, Kind, KindSchema, Local, Name, Part, ProductT, Rho, Star, Type,
  V, VarT, ArrowK, VarK, Fixity, Idfix }
import com.clarifi.reporting.ermine.surface._
import Renamer.{ Resolution, ToBinder, ToGlobal, Unresolved, Ambiguous }
import scalaparsers.Supply

/** Surface -> core TYPE lowering (Stage 1 item 4.1b): the counterpart of
  * Lower for types, kinds, and annotations, mirroring TypeParsers'
  * constructions exactly —
  *   ->  builds Arrow(l)(a, b);
  *   =>  flattens Product-packed constraints and builds
  *       Forall(l, Nil, Nil, Exists.mk(...)-or-lhs, rhs);
  *   <-  builds Part(l.inferred, lhs, flattened-rhs);
  *   {..r}/[..r]/(|..|) rows apply recordT/relationT to a rho;
  *   explicit forall/exists lower to Forall/Exists with the written
  *   binders; per-annotation implicit variables stay FREE metas (one
  *   shared V per TyImplicit binder — generalization is inference's job,
  *   as in the fused pipeline where sig types went through `typ`);
  *   `some` quantifiers become the Annot's existentials;
  *   every annotation-level result is normalized with .nf, as typ did.
  */
object TyLower {

  final class TCtx(
      val file: String,
      resolutions: Map[Span, Resolution],
      binderSites: Map[Span, Int],
      binderInfo: Map[Int, Renamer.BinderInfo],
      cons: Map[Global, Type.Con],
      val moduleName: String,
      supply: Supply,
      typeFixities: Map[String, Fixity]) {

    private var tyVars = Map.empty[Int, V[Kind]]
    private var kindVars = Map.empty[Int, V[Unit]]
    // session-Supply ids: per-module counters collide across loads (s.cons
    // and interface types keep these Vs alive between modules)
    private def fresh(): Int = supply.fresh

    def pos(sp: Span) = scalaparsers.Pos(file, "", sp.startLine, sp.startCol, false)

    def freshKind(sp: Span): Kind = VarK(V(pos(sp).inferred, fresh(), None, Free, ()))

    /** `infix type` declarations are part of a type binder's name,
      * as at the term level. */
    def localTypeName(sp: String): Local = Local(sp, typeFixities.getOrElse(sp, Idfix))

    def tyVar(id: Int, spelling: String, sp: Span, kind: Option[Kind]): V[Kind] =
      tyVars.getOrElse(id, {
        val v = V(pos(sp), fresh(), Some(localTypeName(spelling): Name), Bound,
                  kind getOrElse freshKind(sp))
        tyVars += id -> v
        v
      })

    def kindVar(id: Int, spelling: String, sp: Span): V[Unit] =
      kindVars.getOrElse(id, {
        val v = V(pos(sp), fresh(), Some(Local(spelling): Name), Bound, ())
        kindVars += id -> v
        v
      })

    def resolve(n: SName): Resolution = resolutions.getOrElse(n.span,
      binderSites.get(n.span).map(ToBinder.apply).getOrElse(Unresolved(n.spelling)))

    def binderIdAt(sp: Span): Option[Int] = binderSites.get(sp)
    def infoOf(id: Int): Option[Renamer.BinderInfo] = binderInfo.get(id)

    // The fused pipeline lowers type REFERENCES to named variables and
    // lets loadModule's Type.conMap substitute the Cons by name — the
    // typeNames contract 4.1c feeds.  One shared V per Global (typeNames
    // insert-on-miss parity); the cons map only seeds kinds when known.
    private var conVars = Map.empty[Global, V[Kind]]
    def conFor(g: Global, at: Span): Type = VarT(
      conVars.getOrElse(g, {
        val k = cons.get(g).map(_.schema).map(schemaKind(_, at)).getOrElse(freshKind(at))
        val v = V(pos(at), fresh(), Some(g: Name), Bound, k)
        conVars += g -> v
        v
      }) at pos(at))

    private def schemaKind(ks: KindSchema, at: Span): Kind =
      // instantiate the schema's quantified kind vars per REFERENCE —
      // using the body verbatim would share them across every use site
      // (∀row. row -> * must not let one rho use pin the rest)
      if (ks.forall.isEmpty) ks.body
      else {
        val m = ks.forall.map(v => v -> (VarK(V(pos(at).inferred, fresh(), None,
          com.clarifi.reporting.ermine.Free, ())): Kind)).toMap
        ks.body.subst(m)
      }

    /** The named type variables this lowering minted, keyed by Global —
      * the typeNames map 4.1c hands to loadModule. */
    def typeNames: Map[Name, V[Kind]] = conVars.map { case (g, v) => (g: Name) -> v }

    // Unresolved type spellings SHARE one V module-wide (the fused
    // typeNames insert-on-miss); generalization still binds the free
    // var per signature, which is where `exists (Has: ...)` comes from.
    private var tyPlaceholders = Map.empty[String, V[Kind]]
    def placeholderTyVar(sp: String, at: Span): V[Kind] =
      tyPlaceholders.getOrElse(sp, {
        val v = V(pos(at), fresh(), Some(localTypeName(sp): Name), Bound, freshKind(at))
        tyPlaceholders += sp -> v
        v
      }) at pos(at)
    def placeholderTypeNames: Map[Name, V[Kind]] =
      tyPlaceholders.map { case (sp, v) => (localTypeName(sp): Name) -> v }

    // KindParsers has no `row`-style atoms: an unknown kind name is a
    // NAMED kind variable (kindVar), scoped to its statement — `data
    // Sort (r: row)` schema-quantifies row, it does not pin rho
    private var kindPlaceholders = Map.empty[String, V[Unit]]
    /** The fused kindVar is Localized: statement boundaries drop it
      * (type placeholders stay module-wide, like typeNames). */
    def resetKindScope(): Unit = kindPlaceholders = Map.empty
    def placeholderKindVar(sp: String, at: Span): V[Unit] =
      kindPlaceholders.getOrElse(sp, {
        val v = V(pos(at), fresh(), Some(Local(sp): Name), Bound, ())
        kindPlaceholders += sp -> v
        v
      })

    def nf(t: Type): Type = t.nf(supply)
  }

  def apply(r: Renamer.Result, file: String, moduleName: String,
            cons: Map[Global, Type.Con], supply: Supply,
            typeFixities: Map[String, Fixity] = Map()): TCtx =
    new TCtx(file,
      r.occurrences.map(o => o.span -> o.resolution).toMap,
      r.binders.map { case (id, b) => b.defSite -> id },
      r.binders, cons, moduleName, supply, typeFixities)

  private val kindAtomNames = Set("*", "rho", "ρ", "phi", "φ", "constraint", "Γ")

  /** TypeParsers.flattenConstraints, ported over core Types. */
  def flattenConstraints(p: Type, ys: List[Type] = List()): Option[List[Type]] = p match {
    case ProductT(_, n) if ys.length == n => Some(for {
      y <- ys
      z <- flattenConstraints(y) getOrElse List(y)
    } yield z)
    case AppT(x, y) => flattenConstraints(x, y :: ys)
    case _ => None
  }

  // ----------------------------------------------------------------- kinds

  def kind(t: STy, c: TCtx): Kind = t match {
    case STyName(n) => n.spelling match {
      case "*"                => Star(c.pos(n.span))
      case "rho" | "ρ"        => Rho(c.pos(n.span))
      case "phi" | "φ"        => Field(c.pos(n.span))
      case "constraint" | "Γ" => Constraint(c.pos(n.span))
      case sp => c.resolve(n) match {
        case ToBinder(id) => VarK(c.kindVar(id, sp, n.span))
        case _            => VarK(c.placeholderKindVar(sp, n.span))
      }
    }
    case STyApp(STyApp(STyName(ar), a), b) if ar.spelling == "->" =>
      ArrowK(c.pos(ar.span), kind(a, c), kind(b, c))
    case STyParen(_, i) => kind(i, c)
    case ch: STyChain => sys.error("tylower: un-reassociated kind chain at " +
      c.file + ":" + ch.loc.span.startLine + ":" + ch.loc.span.startCol)
    case other => c.freshKind(other.loc.span)
  }

  // ----------------------------------------------------------------- types

  def ty(t: STy, c: TCtx): Type = t match {
    case STyApp(STyApp(STyName(op), x), y) if op.spelling == "->" =>
      Arrow(c.pos(op.span))(ty(x, c), ty(y, c))
    case STyApp(STyApp(STyName(op), x), y) if op.spelling == "=>" =>
      val l = c.pos(op.span)
      val tx = ty(x, c)
      flattenConstraints(tx) match {
        case Some(xs) => Forall(l, List(), List(), Exists.mk(l, List(), xs), ty(y, c))
        case None     => Forall(l, List(), List(), tx, ty(y, c))
      }
    case STyApp(STyApp(STyName(op), x), y) if op.spelling == "<-" =>
      val l = c.pos(op.span)
      val tyy = ty(y, c)
      flattenConstraints(tyy) match {
        case Some(ys) => Part(l.inferred, ty(x, c), ys)
        case None     => Part(l.inferred, ty(x, c), List(tyy))
      }
    case STyName(n) => n.spelling match {
      case "->" => Arrow(c.pos(n.span))
      case sp if kindAtomNames(sp) =>
        // a kind atom in type position only reaches here through binder
        // kinds routed to kind(); a stray one becomes a meta
        VarT(V(c.pos(n.span), -1, None, Free, c.freshKind(n.span)))
      case sp => c.resolve(n) match {
        case ToBinder(id) =>
          val info = c.infoOf(id)
          VarT(c.tyVar(id, sp, n.span, None))
        case ToGlobal(g, _, _) => c.conFor(g, n.span)
        case _ if sp.contains('.') && sp.headOption.exists(_.isUpper) =>
          // FullyQualified reference (interface-style): Module.Sub.Name
          val cut = sp.lastIndexOf('.')
          c.conFor(Global(sp.substring(0, cut), sp.substring(cut + 1)), n.span)
        case _ =>
          VarT(c.placeholderTyVar(sp, n.span))
      }
    }
    case STyApp(f, a)   => AppT(ty(f, c), ty(a, c))
    case STyParen(_, i) => ty(i, c)
    case STyTuple(l, es) =>
      es.map(ty(_, c)).foldLeft(ProductT(c.pos(l.span), es.length): Type)(AppT.apply)
    case STyRowBrace(l, dots, inner)   => AppT(Type.recordT at c.pos(l.span), rho(l, dots, inner, c))
    case STyRowBracket(l, dots, inner) => AppT(Type.relationT at c.pos(l.span), rho(l, dots, inner, c))
    case STyBanana(l, dots, inner)     => rho(l, dots, inner, c)
    case STyForall(l, ks, bs, body) =>
      val kvs = ks.map(k => c.kindVar(c.binderIdAt(k.span).getOrElse(-1), k.spelling, k.span))
      val tvs = bs.map(b => c.tyVar(c.binderIdAt(b.name.span).getOrElse(-1), b.name.spelling,
                                    b.name.span, b.kind.map(kind(_, c))))
      Forall(c.pos(l.span), kvs, tvs, Exists(c.pos(l.span)), ty(body, c))
    case STyExists(l, bs, body) =>
      val tvs = bs.map(b => c.tyVar(c.binderIdAt(b.name.span).getOrElse(-1), b.name.spelling,
                                    b.name.span, b.kind.map(kind(_, c))))
      Exists(c.pos(l.span), tvs, body.map(ty(_, c)))
    case STySome(_, _, _, body) => ty(body, c)  // `some` lives on the Annot
    case STyList(_, _) | _: STyError =>
      VarT(V(c.pos(t.loc.span), -1, None, Free, c.freshKind(t.loc.span)))
    case STyChain(ch) => sys.error("tylower: un-reassociated type chain at " +
      c.file + ":" + t.loc.span.startLine + ":" + t.loc.span.startCol)
  }

  private def rho(l: SLoc, dots: Boolean, inner: List[STy], c: TCtx): Type =
    if (dots) inner match {
      case List(one) => ty(one, c)  // {..r}: the row variable itself
      case _ => VarT(V(c.pos(l.span), -1, None, Free, Rho(c.pos(l.span))))
    } else {
      // field-name set; names localize to this module when unresolved
      val names: Set[Name] = inner.collect { case STyName(n) =>
        c.resolve(n) match {
          case ToGlobal(g, _, _) => g: Name
          case _ => Local(n.spelling).global(c.moduleName): Name
        }
      }.toSet
      ConcreteRho(c.pos(l.span), names)
    }

  /** Signature/annotation entry: `some` quantifiers become the Annot's
    * existentials; the result normalizes with .nf as typ/annot did. */
  def annot(t: STy, c: TCtx): Annot = t match {
    case STySome(l, ks, bs, body) =>
      val kvs = ks.map(k => c.kindVar(c.binderIdAt(k.span).getOrElse(-1), k.spelling, k.span))
      val tvs = bs.map(b => c.tyVar(c.binderIdAt(b.name.span).getOrElse(-1), b.name.spelling,
                                    b.name.span, b.kind.map(kind(_, c))))
      Annot(c.pos(l.span), kvs, tvs, c.nf(ty(body, c)))
    case other =>
      Annot(c.pos(other.loc.span), List(), List(), c.nf(ty(other, c)))
  }
}
