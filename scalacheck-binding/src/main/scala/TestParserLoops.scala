package com.clarifi.reporting

import scalaparsers._
import org.scalacheck._
import Prop._

/** EQUIVALENCE PIN for the looped repetition combinators (PERF-ROADMAP, editor
  * path).  `Parser` overrides many/some/skipMany/skipSome with explicit loops
  * instead of the mutually-recursive definitions in Monadic's `Alternating`
  * trait, where depth is proportional to the NUMBER OF REPETITIONS -- i.e. to
  * input length, not grammar nesting.
  *
  * The reference implementations below are those generic definitions, spelled
  * out verbatim against the real flatMap/orElse/map2 (which are NOT changed),
  * so this property keeps testing the thing it claims to even after the
  * override exists.
  *
  * THE PART THAT IS EASY TO GET WRONG, and the reason this file exists: the
  * right-nested recursion DROPS every intermediate `expected` set and keeps
  * only the LAST one, unioned with the terminating failure's.  Tracing
  * Parser.flatMap: a Commit whose continuation also Commits falls through
  * `case r => r`, discarding the outer `xs`.  A loop that accumulated every
  * `expected` would silently enlarge every error message in the language.
  *
  * NOT TESTED, deliberately: an element parser that succeeds WITHOUT consuming
  * (`Pure`).  `many` of such a parser recurses at the same state forever today
  * -- a heap-growing infinite loop through the trampoline -- and the loop
  * reproduces that faithfully rather than "fixing" it.  Generating one here
  * would hang the suite, and changing the behaviour would not be transparent.
  */
object TestParserLoops extends Properties("Parser loops") {

  // --- the generic definitions, as the oracle -------------------------------
  def refMany[A](p: Parser[Unit,A]): Parser[Unit,List[A]] = refSome(p) orElse List.empty[A]
  def refSome[A](p: Parser[Unit,A]): Parser[Unit,List[A]] = p.map2(refMany(p))(_ :: _)
  def refSkipMany[A](p: Parser[Unit,A]): Parser[Unit,Unit] = refSkipSome(p) orElse (())
  def refSkipSome[A](p: Parser[Unit,A]): Parser[Unit,Unit] = p.map2(refSkipMany(p))((_, b) => b)

  // --- element parsers with fully controlled Commit/Fail/Err behaviour ------
  /** consumes one char when it satisfies `pred`; otherwise an UNCOMMITTED Fail.
    *
    * NOTE the offset in the `expected` string, and do not remove it.  With a
    * FIXED expectation per parser, unioning the sets is idempotent, so a loop
    * that wrongly accumulates every iteration's expected set is indistinguishable
    * from one that correctly keeps only the last -- and this whole file passes
    * while proving nothing.  Verified by planting exactly that bug: with a fixed
    * string all six properties still passed; with the offset in it, `many`,
    * `some` and `sepBy1` fail. */
  def item(pred: Char => Boolean, exp: String): Parser[Unit,Char] = Parser { (s, _) =>
    if (s.offset < s.input.length && pred(s.input.charAt(s.offset)))
      Commit(s.copy(offset = s.offset + 1), s.input.charAt(s.offset), Set(s"$exp@${s.offset}"))
    else Fail(None, List(), Set(s"$exp@${s.offset}"))
  }
  /** consumes one char, then fails HARD -- the committed-failure path */
  def itemThenErr(pred: Char => Boolean, exp: String): Parser[Unit,Char] = Parser { (s, _) =>
    if (s.offset < s.input.length && pred(s.input.charAt(s.offset)))
      Err.report(s.loc, Some(Document.text("boom")), List(), Set(exp))
    else Fail(None, List(), Set(exp))
  }
  /** never consumes, always an uncommitted Fail carrying msg+aux+expected */
  def alwaysFail(exp: String): Parser[Unit,Char] = Parser { (s, _) =>
    Fail(Some(Document.text("nope")), List(Document.text("aux")), Set(exp))
  }

  def st(input: String) = ParseState[Unit](Pos.start("test", input), input, 0, ())

  /** Structural comparison that does not depend on Err having case-class
    * equality (it does not -- ParseResult.scala:67 is a plain class). */
  def shape(r: ParseResult[Unit, Any]): String = r match {
    case Commit(s, a, xs) => s"Commit(off=${s.offset},$a,${xs.toList.sorted})"
    case Pure(a, last)    => s"Pure($a,$last)"
    case f: Fail          => s"Fail(${f.msg},${f.aux},${f.expected.toList.sorted})"
    case e: Err           => s"Err(${e.loc.line}:${e.loc.column},${e.toString})"
  }

  def agree[A](ref: Parser[Unit,A], looped: Parser[Unit,A], input: String): Prop = {
    val a = shape(ref(st(input), Supply.create).run)
    val b = shape(looped(st(input), Supply.create).run)
    (a == b) :| s"input=${input.take(40)}\n  ref    = $a\n  looped = $b"
  }

  val inputs: Gen[String] = Gen.listOfN(24, Gen.oneOf('a', 'b', 'c')).map(_.mkString)

  val elems: Gen[(String, Parser[Unit,Char])] = Gen.oneOf(
    ("a",         item(_ == 'a', "an 'a'")),
    ("ab",        item(c => c == 'a' || c == 'b', "an 'a' or 'b'")),
    ("none",      item(_ => false, "the impossible")),
    ("errAfterA", itemThenErr(_ == 'a', "an 'a'")),
    ("fail",      alwaysFail("nothing at all")))

  property("many agrees with the recursive definition") =
    forAll(inputs, elems) { case (in, (_, p)) => agree(refMany(p), p.many, in) }

  property("some agrees with the recursive definition") =
    forAll(inputs, elems) { case (in, (_, p)) => agree(refSome(p), p.some, in) }

  property("skipMany agrees with the recursive definition") =
    forAll(inputs, elems) { case (in, (_, p)) => agree(refSkipMany(p), p.skipMany, in) }

  property("skipSome agrees with the recursive definition") =
    forAll(inputs, elems) { case (in, (_, p)) => agree(refSkipSome(p), p.skipSome, in) }

  /** sepBy/sepBy1/endBy1 are defined in terms of many/some, so they should
    * follow by dispatch -- pinned so a future override cannot break them. */
  property("sepBy1 agrees (derived combinator, via dispatch)") =
    forAll(inputs) { in =>
      val p = item(_ == 'a', "an 'a'"); val sep = item(_ == 'b', "a 'b'")
      agree(p.map2(refMany(sep >> p))(_ :: _), p.sepBy1(sep), in)
    }

  /** THE DEPTH CLAIM.  The recursive definition is depth-proportional to the
    * repetition count; the loop is not.  4000 repetitions on a small stack
    * would overflow the old one -- this asserts the new one simply works. */
  property("many of 4000 items does not overflow the stack") = secure {
    val p = item(_ == 'a', "an 'a'")
    val in = "a" * 4000
    p.many(st(in), Supply.create).run match {
      case Commit(s, as, _) => (as.length == 4000 && s.offset == 4000) :|
        s"got ${as.length} items, offset ${s.offset}"
      case other => falsified :| s"unexpected: ${shape(other)}"
    }
  }
}
