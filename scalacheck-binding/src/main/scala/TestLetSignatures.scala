package com.clarifi.reporting

import org.scalacheck._
import Prop.{ Result => _, _ }
import scalaparsers.Death

/** LET-1 (tracker/loopmodel/LET-1-FIX.md): a signature on a `let`-bound
  * binding reaches the type checker.
  *
  * It did not between 2026-08-31 and 2026-09-11.  `Lower.term`'s `SLet`
  * case built `Let(pos, implicits, Nil, body)` because `Lower.bindings`
  * was typed `(List[ImplicitBinding], List[Nothing])` and its signature
  * case was `case _: SSigStatement => ()  // 4.1` -- a staged stub from
  * 91c0d52 that became the only module path when 80df1eb retired the
  * fused pipeline (whose `let` production filled BOTH halves of `Let`).
  * So a let-bound signature could neither restrict nor widen and the
  * compiler did not say so: `let g : Int -> Int; g q = q in g "hello"`
  * LOADED and evaluated to `"hello"`.  A `where` was unaffected, because
  * a top-level `where` goes through the module path's `pairSigs` -- but a
  * `where` nested INSIDE a `let` block went through `Lower.bindings` and
  * was dropped as well.  Nothing pinned any of it; these are the pins.
  *
  * The fix shares ONE implementation of "group the equations, lower the
  * signatures, pair them" (`Lower.collectBlock`/`pairSigs`/`bindings`)
  * between the module top level, `where` clauses and `let` blocks, so a
  * signature in any block is an `ExplicitBinding` that
  * `Subst.inferBindingGroupTypes` type checks against its body.
  */
object TestLetSignatures extends Properties("Ermine let signatures") {
  private val ermineFixture = ErmineFixture()
  import ermineFixture._

  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
        "Function" -> all, "Bool" -> all)

  /** The refusal report for these statements, or None if they loaded. */
  private def refusal(stmts: String, m: Map[String, ImportSpec] = imps): Option[String] =
    try { session { implicit s => loadStatements(stmts, m) }; None }
    catch { case d: Death => Some(d.getMessage) }

  private def rejected(stmts: String, re: String,
                       m: Map[String, ImportSpec] = imps): Prop =
    secure {
      refusal(stmts, m) match {
        case None => falsified :| "loaded cleanly; expected a refusal"
        case Some(msg) =>
          if (re.r.findFirstIn(msg).isDefined) proved
          else falsified :| ("report did not match /" + re + "/: " +
                             msg.linesIterator.take(2).mkString(" | "))
      }
    }

  // -- 1. the signature RESTRICTS, in every block shape ---------------------
  // The four spellings of one program.  All four were LOADING before LET-1
  // except the plain `where`, which is why the `where` was the control.

  private val letRestrict =
    "v = let g : Int -> Int\n" +
    "        g q = q\n" +
    "    in g \"hello\""

  private val whereRestrict =
    "v = g \"hello\"\n" +
    "  where g : Int -> Int\n" +
    "        g q = q"

  private val whereInLet =
    "v = let outer y = g y\n" +
    "          where g : Int -> Int\n" +
    "                g q = q\n" +
    "    in outer \"hello\""

  private val letInWhere =
    "v = outer \"hello\"\n" +
    "  where outer y = let g : Int -> Int\n" +
    "                      g q = q\n" +
    "                  in g y"

  property("a let signature restricts its binding: Int -> Int refuses a String") =
    rejected(letRestrict, "failed to unify")

  property("the where twin is refused as it always was") =
    rejected(whereRestrict, "failed to unify")

  property("a where inside a let block is checked too (the second drop site)") =
    rejected(whereInLet, "failed to unify")

  property("a let inside a where body is checked too") =
    rejected(letInWhere, "failed to unify")

  // -- 2. an HONEST signature is not in the way -----------------------------

  property("a correct polymorphic let signature is honoured at two types") =
    typeChecks("v = let g : a -> a\n" +
               "        g q = q\n" +
               "    in (g 1, g True)", "v", imps)

  property("a correct polymorphic where signature, the same way") =
    typeChecks("v = (g 1, g True)\n" +
               "  where g : a -> a\n" +
               "        g q = q", "v", imps)

  // -- 3. ...and a signature the body cannot deliver is refused -------------

  property("a let signature more general than its body is refused") =
    rejected("v = let g : a -> Int\n" +
             "        g q = q + 1\n" +
             "    in g 2", "failed to unify|rigid|skolem|escape")

  // -- 4. a signature with no equation: the top level's refusal, verbatim ---

  property("a let signature with no definition is refused like a where's") = {
    val inLet   = refusal("v = let g : Int -> Int\n    in 1")
    val inWhere = refusal("v = 1\n  where g : Int -> Int")
    def anchored(o: Option[String]) =
      o.flatMap(m => ":(\\d+):(\\d+): missing definition".r.findFirstMatchIn(m)
                       .map(mm => (mm.group(1).toInt - statementWrapperLines(imps),
                                   mm.group(2).toInt)))
    ((anchored(inLet) ?= Some((1, 9))) :| s"let: $inLet") &&
    ((anchored(inWhere) ?= Some((2, 9))) :| s"where: $inWhere")
  }

  // -- 5. the row-constraint twin: a KNOWN HOLE, and now it shows ----------
  // `local`'s declared context is EMPTY while its body needs
  // `r <- ((|health|), _)`, and the call hands it a row without `health`.
  // Before LET-1 the signature was dropped, `local` was INFERRED with the
  // honest constraint, and the call was refused -- for the right reason by
  // accident.  Now the declaration is honoured, and the checker's separate
  // entailment hole (an unentailed residual row constraint is DROPPED
  // rather than refused, Subst.scala's `rs`) lets the too-weak context
  // through, exactly as it does for the identical program at the TOP LEVEL
  // (`core/examples/shouldfail/sig01_*` on branch sig-entail; the whole
  // analysis is ../ermine-scala-wt-sig/tracker/loopmodel/SIG-1-SURVEY.md).
  // So this property says ACCEPTED, and it is the entailment loop's to
  // flip: when S3 lands, `shouldfail/sig03_let_bound_signature.e` and
  // `TestSigEntail`'s let property move with it.
  private val rowImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Prelude" -> all)

  private val rowTwin =
    "field position : Double\n" +
    "field health   : Int\n" +
    "crash = let local : forall r. {..r} -> Int\n" +
    "            local r = r ! health\n" +
    "        in local { position = 2.0 }"

  property("KNOWN HOLE: a let signature with a too-weak context is ACCEPTED") =
    typeChecks(rowTwin, "crash", rowImps)

  // Sharing the block machinery with the module path makes interleaved equations of one
  // name a refusal inside a `let` block too (LET-1 review edit 1): in the let channel the
  // refusal is recorded and lowering continues, so the message is what surfaces.
  property("interleaved equations of one name are refused in a let block") =
    no(typeChecks("v = let f 0 = 1\n        g y = y\n        f 1 = 2\n    in f 1", "v", imps))
}
