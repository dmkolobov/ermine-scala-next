package com.clarifi.reporting

import com.clarifi.reporting.ermine._

import org.scalacheck._
import Prop.{ Result => _, _ }

/** The signature-entailment check, pinned from both sides (`tracker/SIG-ENTAIL-PLAN.md`).
  *
  * BACK-PORT (branch `backport-2.11`, `backport/SIG-ENTAIL-2.11.md`): scala3-migration
  * `5162945`'s suite, with `TestInterfaceKey`'s key assertion folded in as one property
  * (that suite is not on this branch -- its warm-load step deadlocks the 2.11 loader,
  * BACKPORT.md).
  *
  * S0 pinned the HOLE: a declared signature's ROW constraints were never checked against
  * the body's obligations (`Subst.subsumeType` discarded the skolem-mentioning wanteds), so
  * `healthOpt : forall r. {..r} -> Int` with body `r ! health` was accepted and
  * `healthOpt {position = 2.0}` failed at run time with "key not found: health".  S3 closed
  * it: the four KNOWN HOLE properties below are `rejects(...)` now, and the last group pins the
  * flag itself -- under `-Dermine.sigEntail=off` (here, the session option) the old
  * behaviour is back, byte for byte, which is what makes the flag a real escape hatch.
  *
  * Corpus twins: `core/examples/shouldfail/sig0{1,2,3,4,5}_*.e` and
  * `shouldfail-controls/control08_sig_declared.e`.  The decision procedure itself is
  * differentially tested in `TestSigEntailDiff`. */
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
  /* SCALA 2.11: `private`, because `ImportSpec` is a type member of the (private) fixture
   * and 2.11 refuses a public member whose type names a private value's type. */
  private val imps: Map[String, ImportSpec] =
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

  /* THE LET-BOUND TWIN.  On scala3-migration this reaches the check through the same `sig`
   * site since LET-1 (cff6c42) made the renamer honour let-bound signatures.  THIS BRANCH
   * HAS NO RENAMER: the fused Scala-2 grammar pairs a let signature with its equation in
   * `Statement.scala`, so the site it reaches is measured rather than assumed -- what the
   * property asserts either way is that the module is REFUSED, which is the statement the
   * other four make.  `backport/SIG-ENTAIL-2.11.md` records which of the two refusals this
   * branch actually produces (the check's, or ordinary inference at the CALL). */
  property("S3: a let-bound unconstrained signature is REJECTED") =
    rejects(typeChecks(fields,
      "let local : forall r. {..r} -> Int\n    local r = r ! health\nin local { position = 2.0 }", imps))

  property("control: an honest let-bound signature still loads") =
    typeChecks(fields,
      "let localWith : forall r t. r <- ((|health|), t) => {..r} -> Int\n" +
      "    localWith r = r ! health\nin localWith { position = 1.0, health = 10 }", imps)

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

  /** `TestInterfaceKey` is NOT on this branch (its warm-load step deadlocks the 2.11 module
    * loader, BACKPORT.md), so its one S3 assertion lives here: `error` -- and only `error` --
    * APPENDS `|sigEntail=error` to the interface key, and the staleness test is `contains`, so
    * an `.ei` written under `error` still matches under `off` while one written under `off`
    * is rebuilt under `error`.  It reads the PROCESS default, which is what `Session` reads
    * (S3 review D5), so the property states the implication rather than a literal. */
  property("interface key: `error` appends the suffix, and nothing else does") = secure {
    val key = com.clarifi.reporting.ermine.session.Session.interfaceKey
    val suffix = "|sigEntail=error"
    val header = com.clarifi.reporting.ermine.session.Session.interfaceHeader
    ((key.endsWith(suffix) ?= (SigEntail.defaultMode == SigEntail.Error)) :| key) &&
    ((key.indexOf(suffix) ?= key.lastIndexOf(suffix)) :| ("appended once: " + key)) &&
    ((header.endsWith(key) ?= true) :| header)
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
