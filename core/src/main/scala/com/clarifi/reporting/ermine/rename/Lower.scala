package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{
  Alt, Annot, App, Bound, Case, EmptyRecord, ExplicitBinding, Free, Global,
  Hole, ImplicitBinding, Lam,
  Let, LitByte, LitChar, LitDate, LitDouble, LitFloat, LitInt, LitLong,
  LitShort, LitString, Local, Name, Pattern, Product, Remember, Sig, Star,
  Term, Type, V, Var, VarT,
  ConP, LazyP, LitIntP, LitLongP, LitByteP, LitShortP, LitStringP, LitCharP,
  LitFloatP, LitDoubleP, LitDateP, ProductP, StrictP, VarP, WildcardP, AsP }
import com.clarifi.reporting.ermine.surface._
import com.clarifi.reporting.ermine.{ Lit, Rigid, Fixity, Idfix }
import Renamer.{ Resolution, ToBinder, ToGlobal, Unresolved, Ambiguous }
import scalaparsers.Supply

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
  * Bracket/brace hook literals and do-notation (3.4b) and relational
  * envelopes (3.4c) are here too; a TYPE or ANNOTATION is lowered
  * through the `Ctx.lowerAnnot` hook the module reader wires to
  * `TyLower` (`Ctx` cannot depend on its context directly).  What is
  * left as a `Lower.Unsupported` is a tree the phases before this one
  * should have removed: an un-reassociated (pattern) chain, an error
  * node, a signature on a non-variable pattern.
  *
  * The binding-block machinery at the bottom of this object
  * (`collectBlock`/`pairSigs`/`bindings`) is shared with the module
  * reader: see the comment there (LET-1).
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
      scope: ModuleScope.Scope,
      supply: Supply,
      fixities: Map[String, Fixity],
      moduleTerms: Map[String, Int]) {

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
          // internalVar: a canonicalTerms miss falls through to termNames,
          // which holds the module's OWN bindings (List.e defines
          // empty_Bracket and uses [] itself)
          moduleTerms.get(name) match {
            case Some(id) => binderV(id, name) at pos(at)
            case None =>
              diags += Renamer.Diag(at, s"error: bracket/brace hook $name is not in scope")
              V(pos(at), freshHookId(), Some(Local(name)), Bound, (null: Type))
          }
        case Some(ns) =>
          diags += Renamer.Diag(at, s"error: bracket/brace hook $name is ambiguous: $ns")
          V(pos(at), freshHookId(), Some(Local(name)), Bound, (null: Type))
      }
    }
    private def freshHookId(): Int = supply.fresh

    private var vars = Map.empty[Int, V[Type]]      // renamer binder id -> core V
    // ids come from the session Supply: module loads accumulate their Vs in
    // s.env/s.termNames, so a per-module counter would collide across loads
    private def freshId(): Int = supply.fresh

    def pos(sp: Span) = scalaparsers.Pos(file, "", sp.startLine, sp.startCol, false)

    private def unspecified(sp: Span): Type =
      VarT(V(pos(sp).inferred, freshId(), None, Free, Star(pos(sp).inferred)))

    /** Module fixity declarations are part of a binder's NAME — the
      * fused termDef binds the canonical Local, whose fixity the decl
      * set, and globalization copies it onto the exported Global. */
    def localName(sp: String): Local = Local(sp, fixities.getOrElse(sp, Idfix))

    def binderV(id: Int, spelling: String): V[Type] =
      vars.getOrElse(id, {
        val site = binderSites.getOrElse(id, Span(0, 0, 0, 0))
        val v = V(pos(site), freshId(), Some(localName(spelling)), Bound, unspecified(site))
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

    private var placeholders = Map.empty[String, V[Type]]

    /** Reference placeholders keyed as Locals — merged into the
      * constructed parse state's termNames (insert-on-miss parity, read
      * by e.g. processFieldStatement). */
    def placeholderNames: Map[Name, V[Type]] =
      placeholders.map { case (sp, v) => (Local(sp): Name) -> v }

    def varFor(n: SName): V[Type] = resolve(n) match {
      case ToBinder(id)       => binderV(id, n.spelling) at pos(n.span)
      case ToGlobal(g, _, _)  => globals.get(g)
        .map(_ at pos(n.span))
        .getOrElse(V(pos(n.span), freshId(), Some(g), Bound, unspecified(n.span)))
      case _ =>
        // Unresolved/Ambiguous: placeholder tolerance — and insert-on-miss
        // parity: occurrences of one unknown spelling SHARE the placeholder
        // (the fused termVar inserts it into termNames module-wide)
        placeholders.getOrElse(n.spelling, {
          val v = V(pos(n.span), freshId(), Some(localName(n.spelling)), Bound, unspecified(n.span))
          placeholders += n.spelling -> v
          v
        }) at pos(n.span)
    }

    def global(g: Global, at: Span): V[Type] =
      globals.get(g).map(_ at pos(at))
        .getOrElse(V(pos(at), freshId(), Some(g), Bound, unspecified(at)))

    def freshRememberId(): Int = supply.fresh

    /** Annotation lowering, wired to the module's TCtx by NewPipeline
      * (Lower cannot depend on TyLower's context directly). */
    var lowerAnnot: STy => com.clarifi.reporting.ermine.Annot =
      t => sys.error("Lower.Ctx.lowerAnnot: annotation lowering not wired")

    /** A named kind variable is scoped to the SIGNATURE it appears in
      * (`TyLower.TCtx.resetKindScope`, which NewPipeline also calls
      * before every top-level statement).  Wired the same way and for
      * the same reason as `lowerAnnot` -- by both `read` and `replTerm`;
      * a `Ctx` built by hand keeps the no-op default, which costs
      * nothing until it lowers a signature. */
    var resetKindScope: () => Unit = () => ()
  }

  def apply(r: Renamer.Result, file: String, globals: Map[Global, V[Type]],
            scope: ModuleScope.Scope = ModuleScope.Scope.empty,
            fixities: Map[String, Fixity] = Map())(implicit su: Supply): Ctx =
    new Ctx(file,
      r.occurrences.map(o => o.span -> o.resolution).toMap,
      globals,
      r.binders.map { case (id, b) => id -> b.defSite },
      r.binders.map { case (id, b) => b.defSite -> id },
      scope,
      su,
      fixities,
      r.moduleTerms)

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
      val (implicits, explicits) = bindings(ss, c, ctxEnv(c))
      Let(c.pos(l.span), implicits, explicits, term(b, c))
    case SSig(l, tm, t)     => Sig(c.pos(l.span), term(tm, c), c.lowerAnnot(t))
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
        case Nil if suffix.isEmpty =>
          // the fused rec production: `{}` is the EMPTY RECORD
          EmptyRecord(c.pos(l.span))
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
                // Appable parity: internal() relocated each minted
                // application to its FIRST ARGUMENT's loc, so type
                // errors blame the statement, not the whole do
                App(App(Var(bind at mv.loc), mv), mf)
              }
          }
      }
    case SRelEnvelope(l, arrows) =>
      // desugarRelArrows ported: an empty envelope is Function.id; each
      // arrow catafies with an evolving column set (by SPELLING, starting
      // empty per the fused call site); later arrows compose LEFT via
      // Function.(.) at InfixR(9)
      if (arrows.isEmpty) Var(c.global(Global("Function", "id"), l.span))
      else {
        def rewrite(t0: Term, cols: Set[String]): Term = {
          def rec(t: Term): Term = t match {
            case Var(tv) if tv.name.exists(n => cols(n.string)) =>
              App(Var(c.global(Global("Relation.Op", "col"), l.span)), t)
            case lit: com.clarifi.reporting.ermine.Lit[_] =>
              App(Var(c.global(Global("Relation.Op", "prim"), l.span)), lit)
            case App(f, x) => App(rec(f), rec(x))
            case Sig(sl, st, a) => Sig(sl, rec(st), a)
            case com.clarifi.reporting.ermine.Rigid(rt) => com.clarifi.reporting.ermine.Rigid(rec(rt))
            case other => other  // descent stops: records, products, lams,
                                 // vars, case, let, holes, remembers
          }
          rec(t0)
        }
        def catafy(arr: SRelArrow, cols: Set[String]): (Term, Set[String]) = arr match {
          case SFilterArrow(p) =>
            (App(Var(c.global(Global("Relation.Predicate", "filter"), l.span)),
                 rewrite(term(p, c), cols)), cols)
          case SRenameArrow(_, to, from) =>
            (App(App(Var(c.global(Global("Relation", "rename"), l.span)),
                     Var(c.varFor(from))), Var(c.varFor(to))),
             cols - from.spelling + to.spelling)
          case SCombineArrow(_, as, opExpr) =>
            (App(App(Var(c.global(Global("Relation.Op", "combine"), l.span)),
                     rewrite(term(opExpr, c), cols)), Var(c.varFor(as))),
             cols + as.spelling)
        }
        val comp = c.global(Global("Function", ".", com.clarifi.reporting.ermine.InfixR(9)), l.span)
        arrows.tail.foldLeft(catafy(arrows.head, Set.empty[String])) { (st, arr) =>
          val (acc, cols) = st
          val (t2, cols2) = catafy(arr, cols)
          (App(App(Var(comp), t2), acc), cols2)
        }._1
      }
    case x: SErrorTerm      => throw Unsupported("error node", x.loc.span)
  }

  // ------------------------------------------------------- binding blocks
  // ONE implementation of "group the equations, lower the signatures,
  // pair them" for EVERY binding block: the module's top level and its
  // `where` clauses (NewPipeline.assemble, which supplies its own
  // refusal channel and per-statement tolerance) and `let` blocks and
  // the `where` clauses inside them (`term`'s SLet case, through
  // `ctxEnv`).  Until LET-1 the let path had a second, signature-blind
  // copy of the grouping and built `Let(..., Nil, body)`, so a
  // let-bound signature never reached the type checker at all.

  /** How a binding block refuses, and how it brackets one statement.
    * `guarded` is the tolerance bracket: the editor read keeps going
    * after a bad statement, a batch read does not catch anything. */
  trait BlockEnv {
    def refuse(sp: Span, message: String): Unit
    def guarded[A](sp: Span)(a: => A): Option[A]
  }

  /** The refusal channel for a block `term` lowers itself: the Ctx's
    * diagnostic sink, which the batch reader renders as the Death it
    * renders an assemble refusal as (NewPipeline.read's checkpoint) and
    * the editor collects as a Phase.Lower squiggle.  Nothing is caught
    * here -- an `Unsupported` from a nested statement rides out to the
    * enclosing statement's guard, as it did before. */
  def ctxEnv(c: Ctx): BlockEnv = new BlockEnv {
    def refuse(sp: Span, message: String): Unit = c.diags += Renamer.Diag(sp, message)
    def guarded[A](sp: Span)(a: => A): Option[A] = Some(a)
  }

  /** One block's bindings: adjacent equations of one name merge into one
    * binding's alts (gatherBindings parity, so equations of one name
    * must be consecutive AMONG EQUATIONS -- an interleaved equation
    * silently merging into an earlier group was a 4.2 regression, caught
    * by its pin), and each signature is lowered to a type paired with
    * the binder's V by span.  The groups carry the FIRST equation head's
    * Span, which is the position a later re-opening of the name collides
    * with (5.1; that refusal used to report Span(0,0,0,0), not a
    * position at all). */
  def collectBlock(ss: List[SStatement], c: Ctx, env: BlockEnv)
      : (List[(V[Type], ImplicitBinding, Span)], List[(V[Type], Type, Span)]) = {
    val grouped = scala.collection.mutable.LinkedHashMap[String, (V[Type], List[Alt], Span)]()
    val sigs = List.newBuilder[(V[Type], Type, Span)]
    var lastEq: Option[String] = None
    ss foreach { st => env.guarded(st.loc.span) { st match {
      case SEquation(l, n, args, body, wh) =>
        if (grouped.contains(n.spelling) && !lastEq.contains(n.spelling))
          env.refuse(n.span, s"error: interleaved equations for ${n.spelling}")
        lastEq = Some(n.spelling)
        val v = grouped.get(n.spelling).map(_._1).getOrElse {
          c.binderAtSite(n) getOrElse c.varFor(n)
        }
        val bodyT = wh match {
          case None => term(body, c)
          case Some(SWhere(wl, wss)) =>
            val (wis, wes) = bindings(wss, c, env)
            Let(c.pos(wl.span), wis, wes, term(body, c))
        }
        val alt = Alt(c.pos(l.span), args.map(pattern(_, c)), bodyT)
        grouped(n.spelling) = grouped.get(n.spelling) match {
          case Some((v0, alts, sp0)) => (v0, alts :+ alt, sp0)
          case None                  => (v, List(alt), n.span)
        }
      case SSigStatement(_, ns, t) =>
        c.resetKindScope()
        val ty = c.lowerAnnot(t).body
        ns.foreach { n =>
          val v = c.binderAtSite(n) getOrElse c.varFor(n)
          sigs += ((v, ty, n.span))
        }
      case other => throw Unsupported("statement in binding block", other.loc.span)
    } } }
    (grouped.values.toList.map { case (v, alts, sp) => (v, ImplicitBinding(v.loc, v, alts), sp) },
     sigs.result())
  }

  /** Pair each signature with the binding of the same V: that one is
    * EXPLICIT and carries the declared type into
    * `Subst.inferBindingGroupTypes`, the rest stay implicit and are
    * inferred.  A signature with no equation to pair with is refused
    * ("missing definition", at the signature's own span) -- in a `let`
    * block exactly as at the top level. */
  def pairSigs(im: collection.Map[V[Type], ImplicitBinding],
               sigs: List[(V[Type], Type, Span)], env: BlockEnv)
      : (List[ImplicitBinding], List[ExplicitBinding]) = {
    val es = sigs.flatMap { case (v, ty, sp) => env.guarded(sp) {
      im.get(v) match {
        case Some(i) => Some(ExplicitBinding(i.loc, i.v, Annot.plain(i.loc, ty), i.alts))
        case None    => env.refuse(sp, "missing definition"); None
      }
    }.flatten }
    ((im -- es.map(_.v)).values.toList, es)
  }

  /** A `let`/`where` block: collected and paired in one step, which is
    * what both halves of `Let(pos, implicits, explicits, body)` want. */
  def bindings(ss: List[SStatement], c: Ctx, env: BlockEnv)
      : (List[ImplicitBinding], List[ExplicitBinding]) = {
    val (groups, sigs) = collectBlock(ss, c, env)
    pairSigs(scala.collection.mutable.LinkedHashMap(groups.map { case (v, b, _) => v -> b }: _*),
             sigs, env)
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
    case SPSig(l, i, t)    => i match {
      // signedLocalPatternVar: the annot IS the pattern var's extract;
      // body references pick the typed var up via inferAltTypes' subTerm
      case SPVar(n) =>
        val v = c.binderAtSite(n) getOrElse c.varFor(n)
        VarP(v.map(_ => c.lowerAnnot(t)))
      case _ =>
        // signedLocalPatternVar: the fused grammar signs VARS only
        // (core SigP is commented out)
        throw Unsupported("non-variable pattern signature", l.span)
    }
    case x: SPError        => throw Unsupported("error pattern", x.loc.span)
  }

  private def annotOf(c: Ctx, sp: Span): com.clarifi.reporting.ermine.Annot =
    com.clarifi.reporting.ermine.Annot.annotAny  // unannotated binder (4.1 refines)
}
