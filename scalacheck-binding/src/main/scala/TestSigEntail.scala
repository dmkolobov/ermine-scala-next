package com.clarifi.reporting

import com.clarifi.reporting.ermine._

import org.scalacheck._
import Prop.{ Result => _, _ }

/** The signature-entailment check, pinned from both sides (`tracker/SIG-ENTAIL-PLAN.md`).
  *
  * S0 pinned the HOLE: a declared signature's ROW constraints were never checked against
  * the body's obligations (`Subst.subsumeType` discarded the skolem-mentioning wanteds), so
  * `healthOpt : forall r. {..r} -> Int` with body `r ! health` was accepted and
  * `healthOpt {position = 2.0}` failed at run time with "key not found: health".  S3 closed
  * it: the four KNOWN HOLE properties below are `rejects(...)` now, and the last group pins the
  * flag itself -- under `-Dermine.sigEntail=off` (here, the session option) the old
  * behaviour is back, byte for byte, which is what makes the flag a real escape hatch.
  *
  * Corpus twins: `core/examples/shouldfail/sig0{1,2,3,4,5}_*.e`,
  * `shouldfail-controls/control08_sig_declared.e` and `control09_let_signatures.e`.
  * The decision procedure itself is differentially tested in `TestSigEntailDiff`. */
object TestSigEntail extends Properties("Ermine signature entailment") {
  /** THE SHIPPED MODE.  Explicit rather than inherited so that this suite says what it tests
    * even if the process default is overridden on the command line. */
  private val ermineFixture = ErmineFixture(sigEntail = Some(SigEntail.Error))
  import ermineFixture._

  /** The same programs with the check OFF: the escape hatch, and the pin that `off` is the
    * shipped pre-S3 behaviour.  Two modes, one JVM, no `System.setProperty`. */
  private val offFixture = ErmineFixture(sigEntail = Some(SigEntail.Off))

  /** NOT `Prelude`: `!`, `cons` and `\` are builtins and `modify` is `Field`'s, so these
    * programs need no library that the seven uncorrected stdlib signatures live in.  A
    * fixture under `Error` that booted `Prelude` would fail on `DrilldownList.cons_Bracket`
    * rather than on the property, until the corrections land. */
  val imps: Map[String, ImportSpec] =
    Map("Builtin" -> all, "Test" -> all, "Primitive" -> all, "Field" -> all, "Nullable" -> all)

  val fields = "field position : Double\nfield health : Int\n"

  val sig01 = fields + "healthOpt : forall r. {..r} -> Int\nhealthOpt r = r ! health"

  property("control: an honest row signature type-checks at a satisfying record") =
    typeChecks(fields +
      "healthWith : forall r t. r <- ((|health|), t) => {..r} -> Int\nhealthWith r = r ! health",
      "healthWith { position = 1.0, health = 10 }", imps)

  property("control: inference alone refuses a record lacking the field") =
    rejects(typeChecks(fields + "healthInf r = r ! health",
                  "healthInf { position = 2.0 }", imps))

  property("S3: an unconstrained row signature is REJECTED") =
    rejects(typeChecks(sig01, "healthOpt { position = 2.0 }", imps))

  property("S3: a wrong-label row signature is REJECTED") =
    rejects(typeChecks(fields + "field mana : Nullable Int\n" +
      "wrongLabel : forall r t. r <- ((|mana|), t) => {..r} -> Int\nwrongLabel r = r ! health",
      "wrongLabel { position = 2.0, mana = Null Int }", imps))

  property("S3: a record-to-record unconstrained signature (modify) is REJECTED") =
    rejects(typeChecks(fields + "bump : forall r. {..r} -> {..r}\nbump = modify health (h -> h)",
                  "bump { position = 2.0 }", imps))

  /* The ANNOTATION site (`Subst.typeCheck`, the `ann` `Site`).  At S0 this was a
   * `Prop.throws[NoSuchElementException]`: the program was ACCEPTED and then crashed when
   * the fixture evaluated it.  Under the check it never gets that far -- the module is
   * refused -- so the shape changes to `rejects(typeChecks(...))`, which is the same statement
   * the other three make. */
  property("S3: an unconstrained row ANNOTATION is REJECTED") =
    rejects(typeChecks(fields,
      "((r -> r ! health) : forall r. {..r} -> Int) { position = 2.0 }", imps))

  property("control: an honest row annotation type-checks at a satisfying record") =
    typeChecks(fields,
      "((r -> r ! health) : forall r t. r <- ((|health|), t) => {..r} -> Int) { position = 1.0, health = 10 }", imps)

  // Since LET-1 (cff6c42) the renamer honours let-bound signatures, so the let-bound twin
  // is sig01 in a let and the check reaches it through the same `sig` site.  Before LET-1
  // the signature was dropped and ordinary inference refused the CALL instead; this
  // property pins the check, not that older accident.
  property("S3: a let-bound unconstrained signature is REJECTED") =
    rejects(typeChecks(fields,
      "let local : forall r. {..r} -> Int\n    local r = r ! health\nin local { position = 2.0 }", imps))

  property("control: an honest let-bound signature still loads") =
    typeChecks(fields,
      "let localWith : forall r t. r <- ((|health|), t) => {..r} -> Int\n" +
      "    localWith r = r ! health\nin localWith { position = 1.0, health = 10 }", imps)

  /* ---- a literal column set on the LEFT of a partition ----------------------------- *
   * A join against a literal row leaves `(|k|) <- (x, y)` in the residual.  Before
   * 2026-10 the check dropped it, warned, and accepted both of these. */
  val relImps: Map[String, ImportSpec] = Map("Builtin" -> all, "Test" -> all, "Prelude" -> all)

  property("literal left: an honest join against a projection loads") =
    typeChecks("field demoKey : Int\n" +
      "keepKey : Has inputRow (|demoKey|) => Relation inputRow -> Relation inputRow\n" +
      "keepKey rows = join (rows) (project {demoKey} rows)",
      "keepKey", relImps)

  property("literal left: a join declared to return a literal row is REJECTED") =
    rejects(typeChecks("field jlA : Int\nfield jlB : Int\n" +
      "joinLit : Relation r1 -> Relation r2 -> Relation (|jlA, jlB|)\n" +
      "joinLit x y = join x y",
      "joinLit", relImps))

  /* ---- the flag ------------------------------------------------------------------ *
   * `off` is the shipped pre-S3 behaviour: the same module the default rejects is
   * ACCEPTED, and the two fixtures run in ONE JVM with no `System.setProperty`. */
  property("flag: under `off` the unconstrained signature is accepted again") =
    offFixture.typeChecks(sig01, "healthOpt { position = 2.0 }", imps)

  property("flag: under `off` the honest signature still type-checks") =
    offFixture.typeChecks(fields +
      "healthWith : forall r t. r <- ((|health|), t) => {..r} -> Int\nhealthWith r = r ! health",
      "healthWith { position = 1.0, health = 10 }", imps)

  /* ---- the MESSAGE, and that two readers get the SAME one ------------------------------ *
   * S3 review M2: the refuting model -- and so the sentence a user reads -- was a function of
   * the ids the run happened to mint, because the constraint lists reached the engine in `Set`
   * order.  `SigEntail.check` now sorts them canonically (rendered name, then id).  This
   * property is the pin: the same program, checked in two SEPARATE SESSIONS of one JVM, must
   * produce the same refusal text once the ids are normalised away -- and, since it is the one
   * property that reads the message at all, it also pins that the refusal is THIS check's
   * (the four `rejects(typeChecks(...))` above only say "refused"). */
  private def refusalText(p: String, e: String): String =
    ermineFixture.run { implicit s =>
      ermineFixture.loadStatements(p, imps)
      ermineFixture.typeOf(e, imps)
    } match {
      case scalaparsers.Failure(Some(d), _) => d.toString.replaceAll("\\^[0-9]+", "^N")
      case other                            => "<accepted: " + other + ">"
    }

  property("the message: two sessions, one explanation (reproducible witness)") = secure {
    val a = refusalText(sig01, "healthOpt { position = 2.0 }")
    val b = refusalText(sig01, "healthOpt { position = 2.0 }")
    (a ?= b) :| ("first:\n" + a + "\nsecond:\n" + b) &&
    ((a contains "the signature does not entail this row constraint") :| a) &&
    ((a contains "no rows satisfying the givens satisfy it: take the column") :| a) &&
    ((a contains "declared at") :| a)
  }

  property("flag: the session option is what the checker reads") = secure {
    val e = new com.clarifi.reporting.ermine.session.SessionEnv(_sigEntail = Some(SigEntail.Off))
    val d = new com.clarifi.reporting.ermine.session.SessionEnv()
    (e.sigEntail ?= (SigEntail.Off: SigEntail.Mode)) &&
    (d.sigEntail ?= SigEntail.defaultMode) &&
    (e.copy.sigEntail ?= (SigEntail.Off: SigEntail.Mode)) &&
    (SigEntail.modeOf("warn") ?= (SigEntail.Warn: SigEntail.Mode)) &&
    (SigEntail.modeOf("error") ?= (SigEntail.Error: SigEntail.Mode)) &&
    (SigEntail.modeOf("off") ?= (SigEntail.Off: SigEntail.Mode))
  }
}
