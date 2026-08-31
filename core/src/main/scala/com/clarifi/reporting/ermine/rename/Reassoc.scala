package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{
  Fixity, Idfix, Infix, InfixN, InfixR, Local, Postfix, Prefix }
import scalaparsers.{ Assoc, AssocL, AssocN, AssocR }
import com.clarifi.reporting.ermine.surface._
import Renamer.Diag

/** Fixity re-association (tracker/LSP-ROADMAP.md, Stage 1 item 3.3):
  * ParsingUtil's shuntingYard ported as a PURE pass over the flat chains
  * (Op.scala is a commented-out duplicate; ParsingUtil.scala:385-440 is
  * the live source).  Exact clear/finish semantics: lower precedence
  * pops, equal precedence reduces for left/left, shifts for right/right,
  * and anything else is "error: ambiguous operator of precedence N";
  * unary ops keep AssocL so parenthesized stacking still works; an
  * exhausted chain with more than one operand is "error: ill-formed
  * expression".
  *
  * The fixity environment is POSITIONAL (Decisions a and e): a
  * declaration governs uses textually after it; a redeclaration against
  * an import or an earlier declaration in the same bucket is "Multiple
  * fixity definitions for operator: X" — which also covers the shared
  * infix/postfix bucket.  Unknown operators are diagnosed here (the
  * fused pipeline's layout error was its way of saying the same thing;
  * Decision f permits the drift).
  */
object Reassoc {

  // ------------------------------------------------------------- the yard

  final case class YOp[A](span: Span, prec: Int, assoc: Assoc, unary: Boolean,
                          build: List[A] => Option[List[A]])

  /** Left = the resolved operator; Right = an operand. */
  def yard[A](items: List[Either[YOp[A], A]]): Either[Diag, A] = {

    def clear(p: YOp[A], rators: List[YOp[A]], rands: List[A],
              rest: List[Either[YOp[A], A]]): Either[Diag, A] = rators match {
      case f :: fs =>
        if (p.prec < f.prec) f.build(rands) match {
          case Some(r) => clear(p, fs, r, rest)
          case None    => Left(Diag(f.span, "error: ill-formed expression"))
        }
        else if (p.prec == f.prec) (p.assoc, f.assoc) match {
          case (AssocL, AssocL) => f.build(rands) match {
            case Some(r) => clear(p, fs, r, rest)
            case None    => Left(Diag(f.span, "error: ill-formed expression"))
          }
          case (AssocR, AssocR) => postRator(p :: rators, rands, rest)
          case _ => Left(Diag(f.span, s"error: ambiguous operator of precedence ${p.prec}"))
        }
        else postRator(p :: rators, rands, rest)
      case Nil => postRator(List(p), rands, rest)
    }

    def finish(rators: List[YOp[A]], rands: List[A]): Either[Diag, A] = rators match {
      case f :: fs => f.build(rands) match {
        case Some(r) => finish(fs, r)
        case None    => Left(Diag(f.span, "error: ill-formed expression"))
      }
      case Nil => rands match {
        case List(x) => Right(x)
        case _ =>
          val sp = Span(0, 0, 0, 0)
          Left(Diag(sp, "error: ill-formed expression"))
      }
    }

    def postRator(rators: List[YOp[A]], rands: List[A],
                  rest: List[Either[YOp[A], A]]): Either[Diag, A] = rest match {
      case Right(rand) :: more            => postRand(rators, rand :: rands, more)
      case Left(op) :: more if op.unary   => clear(op, rators, rands, more)  // prefix
      case _                              => finish(rators, rands)
    }

    def postRand(rators: List[YOp[A]], rands: List[A],
                 rest: List[Either[YOp[A], A]]): Either[Diag, A] = rest match {
      case Left(op) :: more => clear(op, rators, rands, more)  // infix or postfix
      case Nil              => finish(rators, rands)
      case Right(r) :: _    => Left(Diag(Span(0, 0, 0, 0), "error: ill-formed expression"))
    }

    postRator(Nil, Nil, items)
  }

  // --------------------------------------------------- fixity environment

  /** One declaration site: a fixity governs uses textually AFTER it
    * (Decision a for block binders, Decision e for module statements). */
  final case class Decl(line: Int, col: Int, fixity: Fixity)

  final case class FixityEnv(
      imports: Map[(String, Int), Fixity],       // (spelling, bucket) -> declared fixity
      decls: Map[(String, Int), List[Decl]]) {   // textual declarations, any scope

    def lookup(spelling: String, bucket: Int, line: Int, col: Int): Option[Fixity] = {
      val declared = decls.getOrElse((spelling, bucket), Nil)
        .filter(d => d.line < line || (d.line == line && d.col < col))
        .sortBy(d => (d.line, d.col)).lastOption.map(_.fixity)
      declared orElse imports.get((spelling, bucket))
    }

    def declare(spelling: String, bucket: Int, d: Decl): (FixityEnv, Option[String]) = {
      val clash = imports.contains((spelling, bucket)) || decls.contains((spelling, bucket))
      val env2 = copy(decls = decls.updated((spelling, bucket),
        d :: decls.getOrElse((spelling, bucket), Nil)))
      (env2, if (clash) Some(s"Multiple fixity definitions for operator: $spelling") else None)
    }
  }

  private def bucket(f: Fixity): Int = f match {
    case Idfix        => 1
    case _: Prefix    => 2
    case _            => 3  // infix and postfix share
  }

  /** Imports' fixities live inside the canonical keys. */
  def importFixities(scope: ModuleScope.Scope): Map[(String, Int), Fixity] =
    (scope.canonicalTerms.keysIterator ++ scope.canonicalTypes.keysIterator)
      .filter(l => l.fixity != Idfix)
      .map(l => (l.string, bucket(l.fixity)) -> l.fixity).toMap

  /** Module-level environment: import layer + fixity statements in
    * textual order, with the duplicate diagnostics. */
  def moduleEnv(m: SModule, scope: ModuleScope.Scope): (FixityEnv, List[Diag]) = {
    val diags = List.newBuilder[Diag]
    var env = FixityEnv(importFixities(scope), Map())
    m.statements foreach {
      case SFixity(loc, fix, _, ops) =>
        ops foreach { op =>
          val (e2, clash) = env.declare(op.spelling, bucket(fix),
            Decl(op.span.startLine, op.span.startCol, fix))
          env = e2
          clash.foreach(msg => diags += Diag(op.span, msg))
        }
      case _ => ()
    }
    (env, diags.result())
  }

  // -------------------------------------------------------- term rewrite

  private val kindAtoms = Set("*", "rho", "ρ", "phi", "φ", "constraint", "Γ")
  private val tyArrows: Map[String, Fixity] =
    Map("->" -> InfixR(0), "=>" -> InfixR(0), "<-" -> InfixN(1))

  /** Block binders declaring fixity inline — `(infixl 5 op) a b = ...` —
    * extend the environment at their textual position (Decision a: they
    * govern later siblings only, which the positional lookup enforces). */
  private def blockDecls(sts: List[SStatement], env0: FixityEnv, diags: scala.collection.mutable.Builder[Diag, List[Diag]]): FixityEnv =
    sts.foldLeft(env0) {
      case (env, SEquation(_, n, _, _, _)) => n.form match {
        case ParenFixityBinder(f) =>
          val (e2, clash) = env.declare(n.spelling, bucket(f), Decl(n.span.startLine, n.span.startCol, f))
          clash.foreach(msg => diags += Diag(n.span, msg))
          e2
        case _ => env
      }
      case (env, _) => env
    }

  /** Re-associate every chain in a term.  Returns the rewritten term and
    * any diagnostics (the term keeps its shape past an error). */
  def term(t: STerm, env0: FixityEnv): (STerm, List[Diag]) = {
    val diags = List.newBuilder[Diag]
    var env = env0

    def opFor(o: OpOcc): Either[Diag, YOp[STerm]] = {
      val b = o.posClass match { case OperandPos => 2; case PostOperandPos => 3 }
      env.lookup(o.name.spelling, b, o.name.span.startLine, o.name.span.startCol) match {
        case None => Left(Diag(o.name.span, s"error: unknown operator ${o.name.spelling}"))
        case Some(f) =>
          val v: STerm = SVar(o.name)
          f match {
            case Prefix(p)  => Right(YOp(o.name.span, p, AssocL, unary = true,
              { case x :: xs => Some(SApp(v, x) :: xs); case _ => None }))
            case Postfix(p) => Right(YOp(o.name.span, p, AssocL, unary = false,
              { case x :: xs => Some(SApp(v, x) :: xs); case _ => None }))
            case Infix(p, a) => Right(YOp(o.name.span, p, a, unary = false,
              { case x :: y :: xs => Some(SApp(SApp(v, y), x) :: xs); case _ => None }))
            case _ => Left(Diag(o.name.span, s"error: unknown operator ${o.name.spelling}"))
          }
      }
    }

    def go(t: STerm): STerm = t match {
      case SChain(c) =>
        val items = c.items.map {
          case Left(operand) => Right(go(operand)): Either[YOp[STerm], STerm]
          case Right(op) => opFor(op) match {
            case Right(y) => Left(y)
            case Left(d)  => diags += d; Right(SErrorTerm(Real(op.name.span), d.message))
          }
        }
        yard(items) match {
          case Right(res) => res
          case Left(d)    => diags += d; SErrorTerm(c.loc, d.message)
        }
      case SApp(f, a) => SApp(go(f), go(a))
      case SLam(l, ps, b) => SLam(l, ps, go(b))
      case SSig(l, tm, ann) => SSig(l, go(tm), ann)
      case SNeg(l, m, o) => SNeg(l, m, go(o))
      case SParen(l, i) => SParen(l, go(i))
      case STuple(l, es) => STuple(l, es.map(go))
      case SCase(l, e, alts) => SCase(l, go(e), alts.map(a => a.copy(body = go(a.body))))
      case SLet(l, ss, b) =>
        val saved = env
        env = blockDecls(ss, env, diags)
        val r = SLet(l, ss.map(stmt), go(b))
        env = saved
        r
      case SDo(l, ds) => SDo(l, ds.map {
        case SDoBind(bl, p, ar, r) => SDoBind(bl, p, ar, go(r))
        case SDoExpr(e) => SDoExpr(go(e))
      })
      case SListLit(l, es, sfx) => SListLit(l, es.map(go), sfx)
      case SBraceLit(l, es, sfx) => SBraceLit(l, es.map(go), sfx)
      case SRecordLit(l, fs) => SRecordLit(l, fs.map { case (k, v) => (go(k), go(v)) })
      case SRelEnvelope(l, as) => SRelEnvelope(l, as.map {
        case SCombineArrow(al, n, e) => SCombineArrow(al, n, go(e))
        case SFilterArrow(e) => SFilterArrow(go(e))
        case r => r
      })
      case SRemember(l, i) => SRemember(l, go(i))
      case other => other
    }

    def stmt(s: SStatement): SStatement = s match {
      case eq: SEquation =>
        val whRewritten = eq.where.map { w =>
          val saved = env
          env = blockDecls(w.statements, env, diags)
          val r = w.copy(statements = w.statements.map(stmt))
          env = saved
          r
        }
        eq.copy(body = go(eq.body), where = whRewritten)
      case other => other
    }

    (go(t), diags.result())
  }

  /** Re-associate a type chain: arrows carry builtin pseudo-fixities
    * (0R, 0R, 1N); kind atoms at operand position ARE operands. */
  def ty(t0: STy, env: FixityEnv): (STy, List[Diag]) = {
    val diags = List.newBuilder[Diag]

    def opFor(o: OpOcc): Either[Diag, YOp[STy]] = {
      val v: STy = STyName(o.name)
      def mk(f: Fixity): Either[Diag, YOp[STy]] = f match {
        case Prefix(p)  => Right(YOp(o.name.span, p, AssocL, unary = true,
          { case x :: xs => Some(STyApp(v, x) :: xs); case _ => None }))
        case Postfix(p) => Right(YOp(o.name.span, p, AssocL, unary = false,
          { case x :: xs => Some(STyApp(v, x) :: xs); case _ => None }))
        case Infix(p, a) => Right(YOp(o.name.span, p, a, unary = false,
          { case x :: y :: xs => Some(STyApp(STyApp(v, y), x) :: xs); case _ => None }))
        case _ => Left(Diag(o.name.span, s"error: unknown type operator ${o.name.spelling}"))
      }
      tyArrows.get(o.name.spelling) match {
        case Some(f) => mk(f)
        case None =>
          val b = o.posClass match { case OperandPos => 2; case PostOperandPos => 3 }
          env.lookup(o.name.spelling, b, o.name.span.startLine, o.name.span.startCol) match {
            case Some(f) => mk(f)
            case None => Left(Diag(o.name.span, s"error: unknown type operator ${o.name.spelling}"))
          }
      }
    }

    def go(t: STy): STy = t match {
      case STyChain(c) =>
        val items = c.items.map {
          case Left(operand) => Right(go(operand)): Either[YOp[STy], STy]
          case Right(op) if op.posClass == OperandPos && kindAtoms(op.name.spelling) =>
            Right(STyName(op.name))  // '*' at operand position IS the star atom
          case Right(op) => opFor(op) match {
            case Right(y) => Left(y)
            case Left(d)  => diags += d; Right(STyError(Real(op.name.span), d.message))
          }
        }
        yard(items) match {
          case Right(res) => res
          case Left(d)    => diags += d; STyError(c.loc, d.message)
        }
      case STyApp(f, a) => STyApp(go(f), go(a))
      case STyParen(l, i) => STyParen(l, go(i))
      case STyTuple(l, es) => STyTuple(l, es.map(go))
      case STyList(l, e) => STyList(l, e.map(go))
      case STyRowBrace(l, d, i)   => STyRowBrace(l, d, i.map(go))
      case STyRowBracket(l, d, i) => STyRowBracket(l, d, i.map(go))
      case STyBanana(l, d, i)     => STyBanana(l, d, i.map(go))
      case STyForall(l, ks, bs, b) => STyForall(l, ks, bs, go(b))
      case STyExists(l, bs, b)     => STyExists(l, bs, b.map(go))
      case STySome(l, ks, bs, b)   => STySome(l, ks, bs, go(b))
      case other => other
    }

    (go(t0), diags.result())
  }
}
