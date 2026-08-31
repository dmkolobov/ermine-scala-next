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
  private val ermineFixture = ErmineFixture(statementsViaNew = true)
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
            case Some(mm) =>
              (mm.group(1).toInt - statementWrapperLines(m) ?= line) :| "anchor line"
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

  // With Prelude AND Primitive both open `+` is visible under two
  // canonical names.  The fused chain died as a silent layout error;
  // the split pipeline shares one placeholder for the ambiguous name
  // and refuses at type checking — same verdict, honest message.
  property("an operator imported twice is unusable at term level") =
    failsMatching("v = 1 + 2", "undefined term", aliasImps)

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
    failsMatching("class Frob a where\n  frob : a -> Int", "members die: undefined type", imps)

  property("a class default alone also dies: undefined type") =
    failsMatching("class Frob a where\n  frob q = q", "members die: undefined type", imps)

  property("a class context also dies: undefined type") =
    failsMatching("class Sub a | Frob a where\n  frub : a -> Int", "members die: undefined type", imps)

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

  // -- operator family (1.3b): the stdlib has ZERO prefix/postfix
  // witnesses, so these pins are the only spec for the re-associator ------

  val minimalImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all)

  property("a prefix operator applies to its operand inside a chain") =
    forAll(small) { x =>
      defAndEval(s"prefix 9 !!\n(prefix !!) q = 0 - q\nv = 1 + !! $x",
                 "v", imps).extract[Int] ?= 1 - x }

  property("prefix operators stack only with parentheses") =
    forAll(small) { x =>
      defAndEval(s"prefix 9 !!\n(prefix !!) q = 0 - q\nv = !! (!! $x)",
                 "v", imps).extract[Int] ?= x }

  property("bare prefix stacking is refused by the re-associator") =
    // the fused LEXER happened to refuse this ("expected whitespace");
    // the surface chain parses leading ops and the yard rejects the
    // stack — same verdict, structural message
    failsMatching("prefix 9 !!\n(prefix !!) q = 0 - q\nv = !! !! 5",
                  "ill-formed expression")

  property("a postfix operator binds by its precedence inside a chain") =
    forAll(small) { x =>
      defAndEval(s"postfix 9 %%\n(%%) q = q + 1\nv = 1 + $x %%",
                 "v", imps).extract[Int] ?= x + 2 }

  property("unary minus negates the ENTIRE chain, not the nearest operand") =
    // Haskell would read -q + 1 as (-q) + 1; Ermine applies primNeg to the
    // whole re-associated chain (TermParsers.termL2_) — preserve for G1
    forAll(small) { x =>
      defAndEval("f q = -q + 1", s"f $x", imps).extract[Int] ?= -(x + 1) }

  property("a block binder's inline fixity does not govern earlier siblings") =
    failsMatching("v = let a = 1 :%: 2\n        (infixl 5 :%:) x y = x - y\n    in a",
                  "unknown operator")

  property("a block binder's inline fixity governs later siblings") =
    defAndEval("v = let (infixl 5 :%:) x y = x - y\n        a = 8 :%: 3\n    in a",
               "v", imps).extract[Int] ?= 5

  property("equal precedence with mixed associativity is ambiguous") =
    failsMatching(
      "infixl 5 <%>\ninfixr 5 <^>\n(<%>) x y = x\n(<^>) x y = y\nv = 1 <%> 2 <^> 3",
      "ambiguous operator of precedence")

  property("redeclaring an imported operator's fixity is refused") =
    failsMatching("infixr 3 &&", "Multiple fixity definitions")

  property("an operator used before its fixity declaration is refused") =
    // positional FixityEnv: the use site precedes the declaration
    failsMatching("v = 1 :%: 2\ninfixl 5 :%:\n(:%:) x y = x + y", "unknown operator")

  property("an unknown operator is refused by name") =
    failsMatching("v = 1 %%% 2", "unknown operator")

  property("one lexeme cannot be both infix and postfix (shared bucket)") =
    failsMatching("infixl 5 :%:\npostfix 5 :%:\n(:%:) x y = x",
                  "Multiple fixity definitions")

  // -- rejected corpus: resolution failures steer today's grammar ----------

  property("a bracket literal without hooks in scope is refused") =
    failsMatching("v = [1, 2]", "hook empty_Bracket is not in scope", minimalImps)

  property("a loaded-but-unimported global is undefined at typecheck") =
    secure {
      try {
        session { implicit s =>
          loadModules(List("List"))          // in the session...
          loadStatements("v = head", minimalImps)  // ...but not imported
        }
        falsified :| "loaded; expected refusal"
      } catch {
        case d: Death =>
          if ("undefined term".r.findFirstIn(d.getMessage).isDefined) proved
          else falsified :| d.getMessage.linesIterator.next().take(120)
      }
    }

  property("an unknown identifier parses; it dies later as undefined term") =
    failsMatching("v = frobnicate", "undefined term")

  // -- error anchors inside desugared forms --------------------------------

  property("a type error inside a list literal anchors on its line") =
    failsAtLine("v = [1,\n  1 && True]", 2)

  property("a type error inside a do block anchors on the bind's rhs") =
    // The split pipeline blames the bind APPLICATION (line 1, at the
    // rhs) rather than the offending subterm on line 2: the checker
    // infers the continuation lambda independently and the Int-vs-Bool
    // clash surfaces at the subsume.  Anchor QUALITY debt — tracked in
    // the roadmap (Stage 2 diagnostics); the line asserted here is the
    // current behavior, not the ideal.
    failsAtLine("v = orElse 0 ((do w <- liftDo (Just 1)\n                  unit (w && True)) maybeMonad)", 1)
}
