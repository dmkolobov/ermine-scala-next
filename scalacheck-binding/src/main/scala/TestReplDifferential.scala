package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.{ Session => S, SessionEnv }
import scalaparsers.Death

import org.scalacheck._
import Prop._

/** Post-G1 D3: the REPL expression GOLDEN corpus.  Born as an old|new
  * differential at D1 (both paths had to agree); when D3 removed the
  * fused eval branch the comparison became vacuous, so the observed
  * behavior is pinned as goldens instead.  Refusal positions/messages
  * are part of the pin (first line, "<interactive>" as @).
  *
  * Corpus-authoring note: Prelude WITHOUT Primitive — together they
  * make `+` ambiguous (the operator-imported-twice pin). */
object TestReplDifferential extends Properties("REPL eval goldens") {
  private val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import fx._

  private val evalImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Prelude" -> all, "Syntax.Do" -> all,
        "Function" -> ((Some("F"), List[syntax.Explicit[Global]](), false)))

  private val corpus: List[(String, String)] = List(
    "1 + 2 * 3"                 -> "OK|Int|7",
    "id 42"                     -> "OK|Int|42",
    "id_F 42"                   -> "OK|Int|42",                  // alias affix
    "(+) 1 2"                   -> "OK|Int|3",                   // paren-op ref
    "(+ 1) 5"                   -> "REFUSED|@:1:2: error: unknown operator +",
    "(1 +) 5"                   -> "REFUSED|@:1:4: error: ill-formed expression",
    "- 5 + 8"                   -> "REFUSED|@:1:2: expected case, do, let, operator, pattern atom, or term atom",
    "let q = 4 in q + 1"        -> "OK|Int|5",
    "let f x = x * 2\n    g y = f y + 1\nin g 5" -> "OK|Int|11", // fused never parsed this (D1 relaxation)
    "case Just 3 of\n  Just n -> n\n  Nothing -> 0" -> "OK|Int|3",
    "(x -> x + 1) 9"            -> "OK|Int|10",
    "[1, 2, 3]"                 -> "OK|List Int|[1,2,3]",        // bracket hooks
    "{}"                        -> "OK|Record (||)|{}",          // empty record
    "(1, \"two\", True)"        -> "OK|(Int, String, Bool)|(1,\"two\",True)",
    "fst (3, 4)"                -> "OK|Int|3",
    "``foldr`` (+) 0 [1,2,3]"   -> "OK|Int|6",                   // literal ident
    "(id : forall a. a -> a) 7" -> "OK|Int|7",                   // annotation
    "sum [1,2,3,4]"             -> "OK|Int|10",
    "head [9]"                  -> "OK|Int|9",
    "if True 1 2"               -> "OK|Int|1",
    "flip const 1 2"            -> "OK|Int|2",
    // type-VAR names in unify errors follow supply draws (a vs b1 under
    // concurrent suites): matched as a pattern, ~ prefix
    "3 `const` 4"               -> "REFUSED~@:1:9: error: failed to unify type \\(\\([a-z]\\d* -> Int\\) -> [a-z]\\d*\\) with type Int")

  private def run(text: String): String =
    try session { implicit s =>
      val (ty, v) = S.eval(text, evalImps)
      "OK|" + Pretty.prettyType(ty, -1).toString + "|" + Pretty.prettyRuntime(v).toString
    } catch {
      case d: Death => "REFUSED|" + d.getMessage.linesIterator.next().replaceAll("<interactive>", "@")
    }

  property("corpus matches goldens") = secure {
    val bad = corpus.flatMap { case (e, want) =>
      val got = run(e)
      val ok =
        if (want startsWith "REFUSED~") got.matches("REFUSED\\|" + want.stripPrefix("REFUSED~"))
        else got == want
      if (ok) None else Some(s"[${e.replace("\n", "\\n")}] want=$want got=$got")
    }
    bad.isEmpty :| bad.mkString("; ")
  }
}
