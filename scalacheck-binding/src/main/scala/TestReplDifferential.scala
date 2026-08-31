package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.{ Session => S, SessionEnv }
import scalaparsers.Death

import org.scalacheck._
import Prop._

/** Post-G1 D1: the REPL expression differential.  Every corpus entry
  * evaluates through BOTH Session.eval paths — the fused phrase(term)
  * and NewPipeline.replTerm — and must agree on the rendered type and
  * the shown value, or REFUSE on both sides.  (The repl-smoke suites
  * cover the console end-to-end; this pins the library-level parity
  * with a wider grammar corpus.) */
object TestReplDifferential extends Properties("REPL eval differential") {
  private val fx = ErmineFixture()
  import fx._

  // Prelude WITHOUT Primitive: together they make `+` ambiguous (the
  // operator-imported-twice pin), which would refuse most of the corpus
  // on both sides and test nothing.  Syntax.Do so do-notation's
  // import-bypassing bind primitive is loaded.
  private val evalImps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Prelude" -> all, "Syntax.Do" -> all,
        "Function" -> ((Some("F"), List[syntax.Explicit[Global]](), false)))

  private val corpus: List[String] = List(
    "1 + 2 * 3",
    "id 42",
    "id_F 42",                                  // alias-affixed reference
    "(+) 1 2",                                  // paren-op reference
    "(+ 1) 5",                                  // left section
    "(1 +) 5",                                  // right section
    "- 5 + 8",                                  // prefix minus negates the chain
    "let q = 4 in q + 1",
    "let f x = x * 2\n    g y = f y + 1\nin g 5",  // letrec siblings
    "case Just 3 of\n  Just n -> n\n  Nothing -> 0",
    "(x -> x + 1) 9",                           // lambda
    "[1, 2, 3]",                                // bracket literal (hooks)
    "{}",                                       // empty record
    "(1, \"two\", True)",                       // tuple
    "fst (3, 4)",
    "``foldr`` (+) 0 [1,2,3]",                  // literal identifier
    "(id : forall a. a -> a) 7",                // annotated term
    "sum [1,2,3,4]",
    "head [9]",
    "if True 1 2",
    "flip const 1 2",
    "3 `const` 4"                               // backtick infix? (fused may refuse)
  )

  private def run(pipelineNew: Boolean, text: String): Either[String, (String, String)] =
    try {
      val r = session { implicit s0 =>
        implicit val s: SessionEnv = s0.withPipelineNew(pipelineNew)
        val (ty, v) = S.eval(text, evalImps)
        (Pretty.prettyType(ty, -1).toString, Pretty.prettyRuntime(v).toString)
      }
      Right(r)
    } catch {
      case d: Death => Left("refused")
      case scala.util.control.NonFatal(_) => Left("refused")
    }

  /** The fused phrase(term) cannot parse multi-equation let blocks in
    * one expression string ("end of layout not found") — the console
    * historically assembled them through |> continuations.  The surface
    * grammar handles them; that relaxation is intentional (D1 log). */
  private val relaxations: Set[String] = Set(
    "let f x = x * 2\n    g y = f y + 1\nin g 5")

  property("corpus agrees across pipelines") = secure {
    val rows = corpus.map { e =>
      val o = run(pipelineNew = false, e)
      val n = run(pipelineNew = true, e)
      (e, o, n)
    }
    val bad = rows.filter {
      case (e, Left(_), Right(_)) if relaxations(e) => false  // documented
      case (_, o, n) => o != n
    }
    (bad.isEmpty :| bad.map { case (e, o, n) => s"[$e] old=$o new=$n" }.mkString("; ")) &&
    (rows.count(_._3.isRight) >= 18) :| s"only ${rows.count(_._3.isRight)} accepted by new — corpus too refusal-heavy"
  }
}
