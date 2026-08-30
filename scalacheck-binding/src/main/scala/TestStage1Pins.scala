package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.syntax.Explicit

import org.scalacheck._
import Prop.{ Result => _, _ }
import scalaparsers.Death

/** Stage-1 spec pins (tracker/LSP-ROADMAP.md, item 1.3a): properties that
  * record what the FUSED parse/resolve pipeline does today in the corners
  * the 129-module differential cannot see — class bodies (the stdlib has
  * no live `class` declaration at all), do-binder scoping, the
  * where-body-parsed-first repair, implicit type quantification, equation
  * adjacency, and error anchors inside desugared forms.  The renamer must
  * reproduce these; they run against the new pipeline too once the
  * fixture is parameterized (item 4.1).
  */
object TestStage1Pins extends Properties("Ermine stage1 pins") {
  private val ermineFixture = ErmineFixture()
  import ermineFixture._

  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
        "Function" -> all, "List" -> all, "Bool" -> all,
        "Maybe" -> all, "Syntax.Do" -> all)

  val aliasImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all,
        "Prelude" -> all, "Function" -> ((Some("F"), List[Explicit[Global]](), false)))

  val small: Gen[Int] = Gen.choose(0, 1000)

  /** Statements refuse to load, and the Death report matches `re`. */
  def failsMatching(stmts: String, re: String,
                    m: Map[String, ImportSpec] = imps): Prop =
    secure {
      try {
        session { implicit s => loadStatements(stmts, m) }
        falsified :| "loaded cleanly; expected a refusal"
      } catch {
        case d: Death =>
          if (re.r.findFirstIn(d.getMessage).isDefined) proved
          else falsified :| ("report did not match /" + re + "/: " +
                             d.getMessage.linesIterator.take(2).mkString(" | "))
      }
    }

  /** Statements refuse to load, anchored at 1-based `line` of the input. */
  def failsAtLine(stmts: String, line: Int,
                  m: Map[String, ImportSpec] = imps): Prop =
    secure {
      try {
        session { implicit s => loadStatements(stmts, m) }
        falsified :| "loaded cleanly; expected a refusal"
      } catch {
        case d: Death =>
          ":(\\d+):(\\d+):".r.findFirstMatchIn(d.getMessage) match {
            case Some(mm) => (mm.group(1).toInt ?= line) :| "anchor line"
            case None => falsified :| ("no line:col anchor in: " +
                                       d.getMessage.linesIterator.take(2).mkString(" | "))
          }
      }
    }

  // -- where clauses: the body parses before its block opens ---------------

  property("a where body reference binds to the where binding, not the argument") =
    forAll(small) { x =>
      defAndEval(s"f w = w + 1 where w = $x", "f 999", imps).extract[Int] ?= x + 1 }

  // -- pattern binders shadow the canonical map too ------------------------

  property("a pattern binder shadows the plain name while its alias survives") =
    forAll(small) { x =>
      // id is an Int binder; id_F is still Function.id — if the binder
      // captured the alias, (id_F id) would apply an Int to an Int.
      defAndEval("f id = id_F id", s"f $x", aliasImps).extract[Int] ?= x }

  // Witnessed while writing these pins: with Prelude AND Primitive both
  // open, `+` is visible under two canonical names and termOpVar's
  // Some(List(n)) match fails SILENTLY — the chain dies as a layout error
  // at the operator.  (Type-level ambiguity errors loudly; ticket lists
  // the asymmetry as an unfixed remnant.)
  property("an operator imported twice is silently unusable at term level") =
    failsMatching("v = 1 + 2", "end of layout", aliasImps)

  // -- do-notation binder scoping (no direct test existed; ticket edge) ----

  property("a do binder's rhs sees the outer name (unbind before rhs)") =
    forAll(small) { x =>
      defAndEval(
        s"f w = orElse 0 ((do w <- liftDo (Just (w + 1)); unit w) maybeMonad)",
        s"f $x", imps).extract[Int] ?= x + 1 }

  property("a do binder rebinds for the statements after it") =
    typeChecks(
      "g w = (w + 1, orElse True ((do w <- liftDo (Just True); unit (w && False)) maybeMonad))",
      "g 5", imps)

  property("after a do rebinding the outer type no longer applies") =
    no(typeChecks(
      "h w = (w + 1, orElse 0 ((do w <- liftDo (Just True); unit (w + 1)) maybeMonad))",
      "h 5", imps))

  // -- class bodies: no stdlib witness exists, and members are DEAD --------
  // Probed 2026-08-30: every class body member (sig, default, either
  // order) and every class context dies in loadModule's type processing
  // with "undefined type"; only bare declarations load.  The renamer must
  // preserve exactly this — resurrecting classes is not Stage-1 business.

  property("a bare class declaration loads") =
    typeChecks("class Frob a", "1", imps)

  property("a kind-braced class declaration loads") =
    typeChecks("class Frob {a}", "1", imps)

  property("any class body member dies: undefined type (current pipeline)") =
    failsMatching("class Frob a where\n  frob : a -> Int", "undefined type", imps)

  property("a class default alone also dies: undefined type") =
    failsMatching("class Frob a where\n  frob q = q", "undefined type", imps)

  property("a class context also dies: undefined type") =
    failsMatching("class Sub a | Frob a where\n  frub : a -> Int", "undefined type", imps)

  property("a class default may not shadow an import (globalTermDef path)") =
    failsMatching(
      "class Frob a where\n  id : a -> a\n  id q = q",
      "shadow", imps)

  // -- implicit type quantification (qtyp/closed; no direct test existed) --

  property("bare sig type variables quantify per signature, independently") =
    typeChecks("f : a -> a\nf q = q\ng : a -> Int\ng _ = 0",
               "(f True, g (f 5))", imps)

  property("a data declaration with an unbound type variable loads") =
    // no improperly-quantified refusal here — the var becomes rigid
    typeChecks("data D = MkD a\nunD (MkD q) = q", "1", imps)

  property("but such a constructor is unusable: the var is a rigid skolem") =
    failsMatching("data D = MkD a\nv = MkD 5", "failed to unify", imps)

  property("a type alias with an unbound variable also loads") =
    // the closed() improperly-quantified guard does not fire here either;
    // finding a live trigger for that diagnostic is a 1.3b corpus TODO
    typeChecks("type T = a", "1", imps)

  // -- statement adjacency (gatherBindings groups adjacent equations only) --

  property("interleaved equations of one name are refused") =
    failsMatching("f 0 = 1\ng 0 = 2\nf 1 = 3", ".")

  // -- error anchors inside desugared forms --------------------------------

  property("a type error inside a list literal anchors on its line") =
    failsAtLine("v = [1,\n  1 && True]", 2)

  property("a type error inside a do block anchors on its line") =
    failsAtLine("v = orElse 0 ((do w <- liftDo (Just 1)\n                   unit (w && True)) maybeMonad)", 2)
}
