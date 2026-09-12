package com.clarifi.reporting

import com.clarifi.reporting.ermine._

import org.scalacheck._
import Prop.{ Result => _, _ }

/** Pins for the signature-entailment hole: a declared signature's ROW constraints are
  * never checked against the body's obligations (`Subst.subsumeType` discards the
  * skolem-mentioning wanteds), so `healthOpt : forall r. {..r} -> Int` with body
  * `r ! health` is accepted and `healthOpt {position = 2.0}` fails at runtime with
  * "key not found: health".  Corpus twins: `core/examples/shouldfail/sig0{1,2,3,4}_*.e`
  * and `shouldfail-controls/control08_sig_declared.e`; plan `tracker/SIG-ENTAIL-PLAN.md`.
  *
  * The two KNOWN HOLE properties assert TODAY'S wrong behaviour on purpose, so the suite
  * stays green while the hole is open and goes red the moment a fix lands -- at which
  * point S3 flips them to `no(...)`.  The two controls must hold before and after. */
object TestSigEntail extends Properties("Ermine signature entailment (pinned hole)") {
  private val ermineFixture = ErmineFixture()
  import ermineFixture._

  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all, "Prelude" -> all)

  val fields = "field position : Double\nfield health : Int\n"

  property("control: an honest row signature type-checks at a satisfying record") =
    typeChecks(fields +
      "healthWith : forall r t. r <- ((|health|), t) => {..r} -> Int\nhealthWith r = r ! health",
      "healthWith { position = 1.0, health = 10 }", imps)

  property("control: inference alone refuses a record lacking the field") =
    no(typeChecks(fields + "healthInf r = r ! health",
                  "healthInf { position = 2.0 }", imps))

  property("KNOWN HOLE S0 (flip to no(...) at S3): an unconstrained row signature is accepted") =
    typeChecks(fields + "healthOpt : forall r. {..r} -> Int\nhealthOpt r = r ! health",
               "healthOpt { position = 2.0 }", imps)

  property("KNOWN HOLE S0 (flip to no(...) at S3): a wrong-label row signature is accepted") =
    typeChecks(fields + "field mana : Nullable Int\n" +
      "wrongLabel : forall r t. r <- ((|mana|), t) => {..r} -> Int\nwrongLabel r = r ! health",
      "wrongLabel { position = 2.0, mana = Null Int }", imps)

  property("KNOWN HOLE S0: a record-to-record unconstrained signature (modify) is accepted") =
    typeChecks(fields + "bump : forall r. {..r} -> {..r}\nbump = modify health (h -> h)",
               "bump { position = 2.0 }", imps)

  // The annotation site evaluates eagerly in the fixture, so this pin records the whole
  // story in one property: the program is ACCEPTED and then fails at runtime with the
  // missing-key exception.  At S3 it becomes `no(typeChecks(...))`.
  property("KNOWN HOLE S0 (flip to no(...) at S3): an unconstrained row ANNOTATION is accepted, then crashes") =
    Prop.throws(classOf[java.util.NoSuchElementException]) {
      defAndEval(fields, "((r -> r ! health) : forall r. {..r} -> Int) { position = 2.0 }", imps)
    }

  property("control: an honest row annotation type-checks at a satisfying record") =
    typeChecks(fields,
      "((r -> r ! health) : forall r t. r <- ((|health|), t) => {..r} -> Int) { position = 1.0, health = 10 }", imps)

  // Since LET-1 (cff6c42) the renamer honours let-bound signatures, so the let-bound twin
  // is sig01 in a let: ACCEPTED through the same hole.  Before LET-1 it was refused at the
  // call site by ordinary inference, because the signature was dropped.
  property("KNOWN HOLE S0 (flip to no(...) at S3): a let-bound unconstrained signature is accepted") =
    typeChecks(fields,
      "let local : forall r. {..r} -> Int\n    local r = r ! health\nin local { position = 2.0 }", imps)
}
