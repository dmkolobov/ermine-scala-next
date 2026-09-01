package scalaparsers


import scalaparsers.Document.{ text, fillSep }

import scala.collection.immutable.List
import scalaz.{ Monad }
import scalaz.Scalaz._
import scalaz.Free.Trampoline
import scala.annotation.unchecked.uncheckedVariance

import scalaz.Ordering._

import Supply._

/** A parser with a nice error handling
  *
  * @author EAK
  */
abstract class Parser[S, +A] extends MonadicPlus[[a] =>> Parser[S,a], A] { that =>
  def self = that
  // scalaz 7.0's Free was covariant in its result type; it became invariant in
  // 7.1. The trampoline is only ever produced here, never consumed, so keeping
  // Parser covariant in A (as the original was) stays sound.
  def apply(s: ParseState[S], vs: Supply): Trampoline[ParseResult[S, A @uncheckedVariance]]
  def run(s: ParseState[S], vs: Supply): Either[Err, (ParseState[S], A)] = apply(s,vs).run match {
    case Pure(a,_)      => Right((s,a))
    case c: Commit[S @unchecked, A @unchecked] => Right((c.s, c.extract))
    case Fail(b,aux,xs) => Left(Err.report(s.loc,b,aux,xs))
    case e: Err         => Left(e)
  }

  // functorial
  def map[B](f: A => B) = new Parser[S,B] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map(_ map f)
  }

  // filtered
  def lift[B](p: Parser[S,B]) = p
  def withFilter(p : A => Boolean): Parser[S,A] = new Parser[S,A] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case Pure(a,e) if !p(a) => e
      case Commit(t,a,xs) if !p(a) => Err.report(t.loc,None,List(),xs)
      case r => r
    }
  }
  override def filterMap[B](f: A => Option[B]) = new Parser[S,B] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case Pure(a,e) => f(a) match {
        case Some(b) => Pure(b, e)
        case None => e
      }
      case Commit(s,a,xs) => f(a) match {
        case Some(b) => Commit(s,b,xs)
        case None    => Err.report(s.loc, None, List())
      }
      case r : ParseFailure => r
    }
  }

  // monadic
  def flatMap[B](f: A => Parser[S,B]) = new Parser[S,B] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).flatMap {
      case r@Pure(a, e)  => f(a)(s, vs).map {
        case Pure(b, ep) => Pure(b, e ++ ep)
        case r : Fail => e ++ r
        case r        => r
      }
      // Scala 3 narrows Commit's invariant S to a fresh S' <: S when matching a
      // ParseResult[S, _]; the scrutinee is genuinely a Commit[S, _], so recover it.
      case c: Commit[S @unchecked, A @unchecked] =>
        val (t, a, xs) = (c.s, c.extract, c.expected)
        f(a)(t, vs).map {
          case Pure(b, Fail(_, _, ys)) => Commit(t, b, xs ++ ys)
          case Fail(e, aux, ys) => Err.report(t.loc, e, aux, xs ++ ys)
          case r => r
        }
      case r : ParseFailure => scalaz.Trampoline.delay(r)
    }
  }

  def wouldSucceed: Parser[S, Boolean] = new Parser[S,Boolean] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case e : ParseFailure => Pure(false)
      case _                => Pure(true)
    }
  }

  def race[B >: A](p: Parser[S, B]) = new Parser[S,B] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).flatMap {
      case e : Fail => p(s, vs) map {
        case ep : Fail => e ++ ep
        case Pure(b, ep) => Pure[B](b, e ++ ep)
        case r => r
      }
      case e@Err(l,msg,aux,stk) => p(s, vs) map {
        case _ : Fail => e
        case ep@Err(lp,msgp,auxp,stkp) => (l ?|? ep.loc) match {
          case LT => ep
          case EQ => e // Err(l, msg, aux ++ List(ep.pretty), stk)
          case GT => e
        }
        case r => r
      }
      case r => scalaz.Trampoline.delay(r)
    }
  }

  // monadicplus
  def |[B >: A](other: => Parser[S,B]) = new Parser[S,B] {

    def apply(s: ParseState[S], vs: Supply) = that(s, vs).flatMap {
      case e : Fail => other(s, vs).map {
        case ep : Fail => e ++ ep
        case Pure(a, ep) => Pure(a, e ++ ep)
        case r => r
      }
      case r => scalaz.Trampoline.delay(r)
    }
  }
  /** LOOPED REPETITION.  The generic definitions in Monadic's `Alternating`
    * trait are mutually recursive -- `many = some orElse Nil`,
    * `some = map2(many)(_::_)` -- so their depth is the REPETITION COUNT, i.e.
    * proportional to input length rather than to grammar nesting, and each
    * iteration allocates a fresh Parser plus a Free bind.  These run the element
    * parser's own trampoline once per iteration and drive it from a while loop:
    * constant depth, and no per-iteration parser.
    *
    * THE ACCUMULATION RULE IS INHERITED EXACTLY, and it is the subtle part.
    * Tracing flatMap: a Commit whose continuation also Commits falls through
    * `case r => r`, DISCARDING the outer `expected` set.  So only the LAST
    * iteration's expected set survives, unioned with the terminating failure's.
    * A loop that accumulated all of them would silently enlarge every error
    * message in the language.  TestParserLoops pins this against the recursive
    * definitions, including the committed-failure (Err) path.
    *
    * An element parser that succeeds WITHOUT consuming (Pure) makes the
    * recursive form spin at the same state forever.  The loop reproduces that
    * faithfully rather than "fixing" it, because fixing it would not be
    * transparent; see the note in TestParserLoops. */
  private def repeat(s: ParseState[S], vs: Supply, keep: Boolean, need: Boolean)
      : ParseResult[S, List[A @uncheckedVariance]] = {
    var st = s
    val acc = List.newBuilder[A @uncheckedVariance]
    var lastXs: Set[String] = Set()
    var any = false
    var out: ParseResult[S, List[A @uncheckedVariance]] = null
    while (out eq null) {
      that(st, vs).run match {
        case c: Commit[S @unchecked, A @unchecked] =>
          if (keep) acc += c.extract
          st = c.s; lastXs = c.expected; any = true
        case Pure(a, _) =>
          if (keep) acc += a          // no progress; faithful spin, see above
        case f: Fail =>
          out = if (any) Commit(st, acc.result(), lastXs ++ f.expected)
                else if (need) f
                else Pure(List.empty[A @uncheckedVariance], f)
        case e: ParseFailure => out = e
      }
    }
    out
  }

  override def many: Parser[S,List[A]] = new Parser[S,List[A]] {
    def apply(s: ParseState[S], vs: Supply) = scalaz.Trampoline.delay(repeat(s, vs, true, false))
  }
  override def some: Parser[S,List[A]] = new Parser[S,List[A]] {
    def apply(s: ParseState[S], vs: Supply) = scalaz.Trampoline.delay(repeat(s, vs, true, true))
  }
  override def skipMany: Parser[S,Unit] = new Parser[S,Unit] {
    def apply(s: ParseState[S], vs: Supply) = scalaz.Trampoline.delay(repeat(s, vs, false, false).map(_ => ()))
  }
  override def skipSome: Parser[S,Unit] = new Parser[S,Unit] {
    def apply(s: ParseState[S], vs: Supply) = scalaz.Trampoline.delay(repeat(s, vs, false, true).map(_ => ()))
  }

  def orElse[B >: A](b: => B) = new Parser[S,B] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case e : Fail => Pure(b, e)
      case r => r
    }
  }

  // context
  def scope(desc: String) = new Parser[S,A] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case Fail(m, aux, _)                     => Fail(m, aux, Set(desc))
      case Err(p,d,aux,stk) if s.tracing       => Err(p,d,aux,(s.loc,desc)::stk)
      case Pure(a, Fail(m : Some[Document], aux, _)) => Pure(a, Fail(m, aux, Set(desc))) // TODO: can we drop the Some?
      case r => r
    }
  }

  // allow backtracking to retry after a parser state change
  def attempt = new Parser[S,A] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case e@Err(p,d,aux,stk) => Fail(None, List(e.pretty), Set()) // we can attach the current message, now!
      case r       => r
    }
  }
  def attempt(s: String): Parser[S,A] = attempt scope s

  def not = new Parser[S,Unit] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case Pure(a, _) => Fail(Some("unexpected" :+: text(a.toString)))
      case Commit(t, a, _)  => Err.report(s.loc, Some("unexpected" :+: text(a.toString)), List(), Set())
      case _                => Pure[Unit](())
    }
  }
  def handle[B >: A](f: ParseFailure => Parser[S,B]) = new Parser[S,B] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).flatMap {
      case r : Err        => f(r)(s, vs)
      case r@Fail(e, aux, xs)   => f(r)(s, vs).map {
        case Fail(ep, auxp, ys)  => Fail(ep orElse e, if (ep.isDefined) auxp else aux, xs ++ ys)
        case r => r
      }
      case r => scalaz.Trampoline.delay(r)
    }
  }
  def slice = new Parser[S,String] {
    def apply(s: ParseState[S], vs: Supply) = that(s, vs).map {
      case Pure(_, e)       => Pure("", e)
      case Commit(t, _, xs) => Commit(t, s.input.substring(s.offset, t.offset), xs)
         // s.rest.take(s.rest.length - t.rest.length), xs)
      case r : ParseFailure => r
    }
  }
  def when(b: Boolean): Parser[S,Unit] = if (b) skip else Parser( (x:ParseState[S], y:Supply) => Pure[Unit](()))
}

object Parser {
  def apply[A,S](f: (ParseState[S], Supply) => ParseResult[S,A]) = new Parser[S,A] {
    def apply(s: ParseState[S], vs: Supply) = scalaz.Trampoline.delay(f(s, vs))
  }
}
