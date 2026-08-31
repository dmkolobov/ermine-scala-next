package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{
  Alt, App, Bound, Case, EmptyRecord, Free, Global, Hole, ImplicitBinding, Lam,
  Let, LitByte, LitChar, LitDate, LitDouble, LitFloat, LitInt, LitLong,
  LitShort, LitString, Local, Name, Pattern, Product, Remember, Sig, Star,
  Term, Type, V, Var, VarT,
  ConP, LazyP, LitIntP, LitLongP, LitByteP, LitShortP, LitStringP, LitCharP,
  LitFloatP, LitDoubleP, LitDateP, ProductP, StrictP, VarP, WildcardP, AsP }
import com.clarifi.reporting.ermine.surface._
import Renamer.{ Resolution, ToBinder, ToGlobal, Unresolved, Ambiguous }

/** Surface -> core lowering, slice one (tracker/LSP-ROADMAP.md 3.4a):
  * the structural cases plus the G-channel sugars of this slice —
  * whole-chain negation (Builtin.primNeg), record literals (Field.cons
  * folded right onto EmptyRecord at the open brace), list patterns
  * (Builtin.Nil / Builtin.:: folded right), tuples and sections
  * (Product applied as a spine), holes (Remember(Hole)).  Expansion
  * SHAPES are bit-for-bit with the fused parser's (Decision h: shapes
  * exact, locations per the Synthesized policy — the tnodes differential
  * compares modulo ids and locs).
  *
  * Bracket/brace hook literals and do-notation are 3.4b; relational
  * envelopes are 3.4c; type/annotation lowering rides 4.1's typecheck
  * integration.  Encountering one of those here is a Lower.Unsupported.
  */
object Lower {

  final case class Unsupported(what: String, span: Span)
    extends Exception(s"lower: $what not lowered in this slice")

  /** Occurrence resolutions keyed by span (Renamer.Result.occurrences). */
  final class Ctx(
      val file: String,
      resolutions: Map[Span, Resolution],
      globals: Map[Global, V[Type]],
      binderSites: Map[Int, Span],
      siteToBinder: Map[Span, Int],
      scope: ModuleScope.Scope) {

    val diags = List.newBuilder[Renamer.Diag]

    /** Channel A (tracker/desugar-hooks.md): an alias-sensitive Local
      * hook — the _Module suffix is part of the name — resolved through
      * the canonical scope at the literal's position.  A missing or
      * ambiguous hook is diagnosed (the ledger's moved refusal) and a
      * dead placeholder V keeps the tree shaped. */
    def hookVar(base: String, suffix: Option[String], at: Span): V[Type] = {
      val name = base + suffix.map("_" + _).getOrElse("")
      scope.canonicalTerms.get(Local(name)) match {
        case Some(List(g: Global)) => global(g, at)
        case Some(Nil) | None =>
          diags += Renamer.Diag(at, s"error: bracket/brace hook $name is not in scope")
          V(pos(at), freshHookId(), Some(Local(name)), Bound, (null: Type))
        case Some(ns) =>
          diags += Renamer.Diag(at, s"error: bracket/brace hook $name is ambiguous: $ns")
          V(pos(at), freshHookId(), Some(Local(name)), Bound, (null: Type))
      }
    }
    private var hookN = -100000
    private def freshHookId(): Int = { hookN -= 1; hookN }

    private var vars = Map.empty[Int, V[Type]]      // renamer binder id -> core V
    private var nextMeta = -1                        // fresh negative ids: never
    private def freshId(): Int = { nextMeta -= 1; nextMeta }  // collide with session ids

    def pos(sp: Span) = scalaparsers.Pos(file, "", sp.startLine, sp.startCol, false)

    private def unspecified(sp: Span): Type =
      VarT(V(pos(sp).inferred, freshId(), None, Free, Star(pos(sp).inferred)))

    def binderV(id: Int, spelling: String): V[Type] =
      vars.getOrElse(id, {
        val site = binderSites.getOrElse(id, Span(0, 0, 0, 0))
        val v = V(pos(site), freshId(), Some(Local(spelling)), Bound, unspecified(site))
        vars += id -> v
        v
      })

    def resolve(n: SName): Resolution =
      resolutions.getOrElse(n.span, Unresolved(n.spelling))

    /** A binder SITE is not an occurrence; join through the binder
      * table's def-site spans so the pattern V and its body references
      * share one core variable. */
    def binderAtSite(n: SName): Option[V[Type]] =
      siteToBinder.get(n.span).map(binderV(_, n.spelling))

    def varFor(n: SName): V[Type] = resolve(n) match {
      case ToBinder(id)       => binderV(id, n.spelling) at pos(n.span)
      case ToGlobal(g, _, _)  => globals.get(g)
        .map(_ at pos(n.span))
        .getOrElse(V(pos(n.span), freshId(), Some(g), Bound, unspecified(n.span)))
      case _ =>  // Unresolved/Ambiguous: placeholder tolerance (termVar parity)
        V(pos(n.span), freshId(), Some(Local(n.spelling)), Bound, unspecified(n.span))
    }

    def global(g: Global, at: Span): V[Type] =
      globals.get(g).map(_ at pos(at))
        .getOrElse(V(pos(at), freshId(), Some(g), Bound, unspecified(at)))

    def freshRememberId(): Int = { nextMeta -= 1; nextMeta }
  }

  def apply(r: Renamer.Result, file: String, globals: Map[Global, V[Type]],
            scope: ModuleScope.Scope = ModuleScope.Scope.empty): Ctx =
    new Ctx(file,
      r.occurrences.map(o => o.span -> o.resolution).toMap,
      globals,
      r.binders.map { case (id, b) => id -> b.defSite },
      r.binders.map { case (id, b) => b.defSite -> id },
      scope)

  // ---------------------------------------------------------------- terms

  def term(t: STerm, c: Ctx): Term = t match {
    case SVar(n)            => Var(c.varFor(n))
    case SLitInt(l, v)      => LitInt(c.pos(l.span), v)
    case SLitLong(l, v)     => LitLong(c.pos(l.span), v)
    case SLitByte(l, v)     => LitByte(c.pos(l.span), v)
    case SLitShort(l, v)    => LitShort(c.pos(l.span), v)
    case SLitString(l, v)   => LitString(c.pos(l.span), v)
    case SLitChar(l, v)     => LitChar(c.pos(l.span), v)
    case SLitFloat(l, v)    => LitFloat(c.pos(l.span), v)
    case SLitDouble(l, v)   => LitDouble(c.pos(l.span), v)
    case SLitDate(l, v)     => LitDate(c.pos(l.span), v)
    case SApp(f, a)         => App(term(f, c), term(a, c))
    case SParen(_, i)       => term(i, c)
    case SLam(l, ps, b)     => ps.foldRight(term(b, c))((p, acc) => Lam(c.pos(l.span), pattern(p, c), acc))
    case SCase(l, e, alts)  => Case(c.pos(l.span), term(e, c),
      alts.map(a => Alt(c.pos(a.loc.span), List(pattern(a.pattern, c)), term(a.body, c))))
    case STuple(l, es)      =>
      es.map(term(_, c)).foldLeft(Product(c.pos(l.span), es.length): Term)(App.apply)
    case STupleSection(l, n) => Product(c.pos(l.span), n)
    case SHole(l)           => Remember(c.freshRememberId(), Hole(c.pos(l.span)))
    case SRemember(_, i)    => Remember(c.freshRememberId(), term(i, c))
    case SNeg(l, _, o)      =>  // primNeg over the ENTIRE chain (pinned)
      App(Var(c.global(Global("Builtin", "primNeg"), l.span)), term(o, c))
    case SRecordLit(l, fs)  =>  // foldRight onto EmptyRecord at the open brace
      val cons = c.global(Global("Field", "cons"), l.span)
      fs.foldRight(EmptyRecord(c.pos(l.span)): Term) { case ((k, v), acc) =>
        App(App(App(Var(cons), term(k, c)), term(v, c)), acc)
      }
    case SLet(l, ss, b)     =>
      val (implicits, _) = bindings(ss, c)
      Let(c.pos(l.span), implicits, Nil, term(b, c))
    case SSig(l, tm, _)     => term(tm, c)  // annotations lower at 4.1
    case SChain(_)          => throw Unsupported("un-reassociated chain", t.loc.span)
    case SListLit(l, es, suffix) =>
      // foldRight onto empty_Bracket[_M] with cons_Bracket[_M] (channel A)
      val nil  = c.hookVar("empty_Bracket", suffix, l.span)
      val cons = c.hookVar("cons_Bracket", suffix, l.span)
      es.foldRight(Var(nil): Term)((e, acc) => App(App(Var(cons), term(e, c)), acc))
    case SBraceLit(l, es, suffix) =>
      // xs.tail.foldLeft(single(xs.head))(snoc) — the fused shape; {} is
      // the crash the old race masked, diagnosed here (ledger)
      es match {
        case Nil =>
          c.diags += Renamer.Diag(l.span, "error: empty brace literal has no meaning")
          Remember(c.freshRememberId(), Hole(c.pos(l.span)))
        case hd :: tl =>
          val single = c.hookVar("single_Brace", suffix, l.span)
          val snoc   = c.hookVar("snoc_Brace", suffix, l.span)
          tl.foldLeft(App(Var(single), term(hd, c)): Term)((acc, e) =>
            App(App(Var(snoc), acc), term(e, c)))
      }
    case SDo(l, stmts) =>
      // reverse foldLeft over Syntax.Do.bind (channel G); the last
      // statement must be an expression, a do must be non-empty — the
      // fused parser's refusals, diagnosed here
      val bind = c.global(Global("Syntax.Do", "bind"), l.span)
      stmts.reverse match {
        case Nil =>
          c.diags += Renamer.Diag(l.span, "error: empty do expression")
          Remember(c.freshRememberId(), Hole(c.pos(l.span)))
        case last :: earlier =>
          last match {
            case SDoBind(bl, _, _, _) =>
              c.diags += Renamer.Diag(bl.span, "error: last statement in `do' must be expression")
              Remember(c.freshRememberId(), Hole(c.pos(l.span)))
            case SDoExpr(e0) =>
              earlier.foldLeft(term(e0, c)) { (tailAct, bform) =>
                val (mv, mf) = bform match {
                  case SDoExpr(e) =>
                    val et = term(e, c)
                    (et, Lam(tailAct.loc, com.clarifi.reporting.ermine.WildcardP(et.loc), tailAct))
                  case SDoBind(bl2, p, _, rhs) =>
                    (term(rhs, c), Lam(c.pos(bl2.span), pattern(p, c), tailAct))
                }
                App(App(Var(bind), mv), mf)
              }
          }
      }
    case x: SRelEnvelope    => throw Unsupported("relational envelope (3.4c)", x.loc.span)
    case x: SErrorTerm      => throw Unsupported("error node", x.loc.span)
  }

  /** Adjacent equations of one name merge (gatherBindings parity); sigs
    * ride to 4.1 (fixtures here avoid them). */
  private def bindings(ss: List[SStatement], c: Ctx): (List[ImplicitBinding], List[Nothing]) = {
    val grouped = scala.collection.mutable.LinkedHashMap[String, (V[Type], List[Alt])]()
    ss foreach {
      case SEquation(l, n, args, body, wh) =>
        val v = c.resolve(n) match {
          case ToBinder(id) => c.binderV(id, n.spelling)
          case _            => c.varFor(n)
        }
        val bodyT = wh match {
          case None => term(body, c)
          case Some(SWhere(wl, wss)) =>
            val (wis, _) = bindings(wss, c)
            Let(c.pos(wl.span), wis, Nil, term(body, c))
        }
        val alt = Alt(c.pos(l.span), args.map(pattern(_, c)), bodyT)
        grouped(n.spelling) = grouped.get(n.spelling) match {
          case Some((v0, alts)) => (v0, alts :+ alt)
          case None             => (v, List(alt))
        }
      case _: SSigStatement => ()  // 4.1
      case other => throw Unsupported("statement in binding block", other.loc.span)
    }
    (grouped.values.map { case (v, alts) => ImplicitBinding(v.loc, v, alts) }.toList, Nil)
  }

  // -------------------------------------------------------------- patterns

  def pattern(p: SPat, c: Ctx): Pattern = p match {
    case SPVar(n) =>
      val v = c.binderAtSite(n) getOrElse (c.resolve(n) match {
        case ToBinder(id) => c.binderV(id, n.spelling)
        case _ => V(c.pos(n.span), -1, Some(Local(n.spelling)), Bound, (null: Type))
      })
      VarP(v.map(_ => annotOf(c, n.span)))
    case SPWildcard(l)     => WildcardP(c.pos(l.span))
    case SPLitInt(l, v)    => LitIntP(c.pos(l.span), v)
    case SPLitLong(l, v)   => LitLongP(c.pos(l.span), v)
    case SPLitByte(l, v)   => LitByteP(c.pos(l.span), v)
    case SPLitShort(l, v)  => LitShortP(c.pos(l.span), v)
    case SPLitString(l, v) => LitStringP(c.pos(l.span), v)
    case SPLitChar(l, v)   => LitCharP(c.pos(l.span), v)
    case SPLitFloat(l, v)  => LitFloatP(c.pos(l.span), v)
    case SPLitDouble(l, v) => LitDoubleP(c.pos(l.span), v)
    case SPLitDate(l, v)   => LitDateP(c.pos(l.span), v)
    case SPParen(_, i)     => pattern(i, c)
    case SPTuple(l, es)    => ProductP(c.pos(l.span), es.map(pattern(_, c)))
    case SPStrict(l, i)    => StrictP(c.pos(l.span), pattern(i, c))
    case SPLazy(l, i)      => LazyP(c.pos(l.span), pattern(i, c))
    case SPAs(l, n, i)     =>
      val v = c.binderAtSite(n) getOrElse c.varFor(n)
      AsP(c.pos(l.span), VarP(v.map(_ => annotOf(c, n.span))), pattern(i, c))
    case SPList(l, es)     =>  // foldRight onto Builtin.Nil with Builtin.::
      val nil  = c.global(Global("Builtin", "Nil"), l.span)
      val cons = c.global(Global("Builtin", "::", com.clarifi.reporting.ermine.InfixR(5)), l.span)
      es.foldRight(ConP(c.pos(l.span), nil, Nil): Pattern)((e, acc) =>
        ConP(c.pos(l.span), cons, List(pattern(e, c), acc)))
    case SPApp(con, args)  =>
      ConP(c.pos(con.span), c.varFor(con), args.map(pattern(_, c)))
    case SPChain(ch)       =>
      // after re-association pattern chains are trees; a raw chain here
      // means :: style cons — fold pairwise left-to-right is not defined
      // for arbitrary shapes, so require pre-reassociated input
      throw Unsupported("un-reassociated pattern chain", p.loc.span)
    case SPSig(_, i, _)    => pattern(i, c)  // annotations at 4.1
    case x: SPError        => throw Unsupported("error pattern", x.loc.span)
  }

  private def annotOf(c: Ctx, sp: Span): com.clarifi.reporting.ermine.Annot =
    com.clarifi.reporting.ermine.Annot.annotAny  // unannotated binder (4.1 refines)
}
