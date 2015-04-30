package com.clarifi.reporting.ermine.parsing

import scalaz.{Name => _, _}
import Scalaz.{modify => _, _}

import scalaparsers._
import scalaparsers.Diagnostic._
import scalaparsers.Document.text
import com.clarifi.reporting.ermine._
import ErParseState.Lenses._

/** Parsers for dealing with DMTL identifiers and keywords
  *
  * @author EAK
  */

abstract class NameParser {
  import SI8862._

  def identStart : Parser[Char]
  def opStart: Parser[Char]

  def ident : Parser[Local] = token(
    (for {
      l <- loc
      i <- (setBol(false) >> identStart >> identTail).slice
      if (!keywords(i))
    } yield Local(i)
    ).attempt("identifier")
  )

  /** parse an operator (without trailing whitespace!) */
  def op: Parser[String] = token((for {
      i <- (opStart >> opChar.skipMany >> (ch('_') >> tailChar.skipSome).skipOptional).slice
      _ <- if(i == "|") notFollowedBy("]")
           else if(keyOps(i)) fail("key operator")
           else if(i.length > 2 && i.foldLeft(true)((b, a) => b && a == '-')) fail("comment")
           else unit(())
  } yield i).attempt("operator"))

  def opName[N](m: PartialFunction[Local,List[N]]) = for {
    x <- (
      (keyword("prefix") >> op).map(prefix(_)) |
      (keyword("postfix") >> op).map(postfix(_)) |
      op.map(infix(_))
    ).attempt
    /* r <- liftOpt(m.lift(x))
         | fail("forward reference to an operator with unknown precedence")
    */
    r <- m.lift(x) match {
        case None => fail("forward reference to an operator with unknown precedence")
        case Some(List( o )) => unit(o)
        case Some( os ) => fail("ambiguous reference to operator: " + os)
    }
  } yield r

  // m maps a local to all of the definitions that are in scope - foo could be Foo.foo or Baz.foo
  // Therefore, we can only unambiguously choose if there are zero or one entries in that list
  def name[N>:Local](m: PartialFunction[Local,List[N]]): Parser[N] = (
    ident.flatMap(n => m.lift(n) match {
               case None => unit(n)
               case Some(List( x )) => unit(x)
               // Todo: better error message
               case Some(xs) => fail[Parser]("Ambiguous reference to identifier " + n + " imported from: " + xs.toString )
             }) | paren(opName(m)).attempt) scope "name"

//  def localName(l: Lens[ParseState, Map[Local,Name]]): Parser[Localized[Local]] = for {
//    m <- gets(l.get)
//    val lookup = (n: Local) => m.getOrElse(n,n).local
//    n <- ident |
//         paren(
//           (keyword("prefix") >> prec.optional ++ op).map({
//             case Some(n) ++ r => prefix(r,n)
//             case None ++ r => lookup(prefix(r))
//           }) |
//           (keyword("postfix") >> prec.optional ++ op).map({
//             case Some(n) ++ r => postfix(r,n)
//             case None ++ r => lookup(postfix(r))
//           }) |
//           (keyword("infixl") >> prec map2 op)((n,r) => infix(r,n,AssocL)) |
//           (keyword("infixr") >> prec map2 op)((n,r) => infix(r,n,AssocR)) |
//           (keyword("infix")  >> prec map2 op)((n,r) => infix(r,n,AssocN)) |
//           op.map(r => lookup(infix(r)))
//         )
//    val lp = l.member(n)
//    _ <- modify(lp.set(_, Some(n)))
//  } yield Localized(n, List(n), modify(lp.set(_, m.lift(n))))

  // also returns the previous name for restoration purposes if found
  def localName[N>:Local](m: PartialFunction[Local,List[N]]): Parser[N] = {
    def lookup(n: Local) = m.lift(n) match {
      case None => unit(n)
      case Some(List(x)) => unit(x)
      case Some(xs) => fail("Ambiguous reference: " + xs.toString)
    }
    ident.flatMap( lookup(_)) |
    paren(
      (keyword("prefix") >> prec.optional ++ op).flatMap({
        case Some(n) ++ r => unit( prefix(r,n))
        case None ++ r => lookup(prefix(r))
      }) |
      (keyword("postfix") >> prec.optional ++ op).flatMap({
        case Some(n) ++ r => unit(postfix(r,n))
        case None ++ r => lookup(postfix(r))
      }) |
      (keyword("infixl") >> prec map2 op)((n,r) => infix(r,n,AssocL)) |
      (keyword("infixr") >> prec map2 op)((n,r) => infix(r,n,AssocR)) |
      (keyword("infix")  >> prec map2 op)((n,r) => infix(r,n,AssocN)) |
      op.flatMap(r => lookup(infix(r)))
    )
  }

  /** Bind `n` to `v` in outer parser, reverse in inner. */
  def bindName[A](n: Local, v: V[A], l: Lens[ParseState, Map[Name, V[A]]]): Parser[Parser[Unit]] = {
    val lp = l member n
    ((parsing.gets(lp.get) << modify(x => lp.set(x, Some(v)))) map (old => modify(x => lp.set(x, old))))
  }

  def addFixity(n: Local, ty: Boolean): Parser[Unit] = {
    def add(l: Lens[ParseState, Map[Local,List[Name]]]) = {
      gets(l.member(n).get) flatMap {
        case Some(_) => fail[Parser]("Multiple fixity definitions for operator: " + n.toString)
        case None    => bindFixity(n, ty).skip
      }
    }
    if (ty) add(canonicalTypes) else add(canonicalTerms)
  }

  /** Answer a Parser that binds `n` to type or term fixities, whose
    * inner Parser undoes the binding. */
  def bindFixity(n: Local, ty: Boolean): Parser[Parser[Unit]] = {
    def add(l: Lens[ParseState, Map[Local,List[Name]]]) = {
      val lp = l.member(n)
      for {old <- gets(lp.get) << modify(s => lp.set(s, Some(List(n))))} // TODO: make sure this is right.
      yield modify(lp.set(_, old))
    }
    if (ty) add(canonicalTypes) else add(canonicalTerms)
  }
  // support for literal identifiers, for example, ``$dollars-us``
  // a literal identifer is anything wrapped between two sets of backticks
  // primarily implemented for interop wth the Security Master
  def literalIdentStart = parsing.word("``")
  def escape = ch('\\') >> satisfy(c => true)
  def literalIdentMiddle = (satisfy(c => c != '`' && c != '\\') | escape).many
  def literalIdentEnd = parsing.word("``")

  def literalIdent = token( for {
    _ <- literalIdentStart
    i <- literalIdentMiddle
    _ <- literalIdentEnd
    } yield Local(i.mkString))
  // a few term related concerns, becuase we need them across datacons and pattern vars
}

object TypeNameParsers extends NameParser {
  def identStart = letter
  override def ident = super.ident | literalIdent
  def opStart = opChar
}
