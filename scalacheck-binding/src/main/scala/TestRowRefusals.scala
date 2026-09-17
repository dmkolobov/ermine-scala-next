package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.SessionEnv

import org.scalacheck.{ Gen, Prop, Properties }
import org.scalacheck.rng.Seed
import Prop.{ Result => _, _ }

/** Unsatisfiable row programs are REFUSED, never accepted, never hung.
  *
  * The `subsume-termination` programme (`tracker/PROMPT-subsume-termination.md`) started from
  * a report that the checker HANGS on one refused row program -- B1, the `dateDiff` combine
  * over a relation without the dates.  It does not.  Stage 0 measured the refusal at
  * 0.06-0.09 s at seventeen `Supply` id bases, the escape check at `Subst.scala:648` returning
  * on all 492,200 traced calls with no cycle in 984,400 identity-marked walks; Stage 1a proved
  * that walk total (`Rowpartition/SubsumeEscape.lean`, `runV_steps`); Stage 1b proved the row
  * loop bounded at the shipped defaults (`Loop/RejectTerm.lean`, `budgetSP_terminates`) and no
  * cyclic binding reachable (`runsP_noAliasChain`).  What did not return in bounded time was
  * the ScalaCheck PROPERTY: `ErmineFixture.no` rewrote a refutation to *passed* rather than
  * *proved*, so a hundred library-scale re-checks were asked for.  `ErmineFixture.rejects` is
  * that fix; this suite is the pin that outlives it.
  *
  * Two things are pinned here that no property pinned before.
  *
  *  - **The shape, not the instance.**  B1 is one program.  This generates a family: random
  *    field names, a relation carrying a random subset of them, and a `combine_Op` of a
  *    `dateDiff_Op` over the two date columns, of which a random NON-EMPTY subset is missing
  *    from the relation.  Every such program must be refused, and its twin -- the same program
  *    over a relation that carries all of them -- must check.
  *  - **Bounded time.**  Every case runs on a daemon thread joined with a deadline, so a
  *    divergence is a RED property in a minute rather than a wedged landing run.  That is the
  *    guarantee the programme was after, and it is a pin rather than a proof: the theorems are
  *    S1a's and S1b's, and they do not cover `subsumeType` as a whole (`SUBSUME-STAGE1B.md`
  *    §8).
  *
  * WHY THE CASES SHARE ONE SESSION.  `ErmineFixture.loadStatements` names every case
  * `module Test`, so it must evict the process-global dep cache around each one, and a case
  * loaded into a fresh `mkEnv` re-reads and re-type-checks the whole import closure -- 9.1 s a
  * case, measured (`SUBSUME-STAGE0.md` §6.2).  Twenty cases that way is three minutes of
  * re-reading the standard library.  `ErmineFixture.loadNamed` gives each case its own module
  * name, so they can all go into ONE warm session: the closure is read once, and the second
  * and later cases cost only their own four declarations.  The measured figures are in
  * `tracker/satterm/SUBSUME-STAGE2.md`.
  *
  * THE SAMPLE IS DRAWN ONCE, WITH A SEED THAT IS REPORTED.  A `forAll` here would ask
  * ScalaCheck for `minSuccessfulTests` = 100 draws, which is the very cost this stage removed.
  * The property draws `n` cases itself from one `Seed` and names that seed in its label, so a
  * failure is reproducible by `-Dermine.test.rowRefusals.seed=<base64>`. */
object TestRowRefusals extends Properties("unsatisfiable row programs (S2)") {
  private val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)

  /** Cases per run.  Each is a bad module and its positive twin, so `n` cases are `2n` loads
    * into the shared session.
    *
    * SIXTEEN, and the reason is not wall clock.  Measured alone, this suite costs 22 s at
    * n = 1, 29 s at n = 8 and 24 s at n = 24 (`scratch-subsume/s2/rowrefusals-{1,scale}.log`):
    * flat inside the noise, because the fixture's one library boot is ~20 s of it and a case
    * is ~0.1 s.  What bounds the sample is the SHAPE SPACE -- three missing-date subsets by
    * three payload widths is nine shapes -- and the id bases: each case draws fresh `Supply`
    * ids, so a larger sample also sweeps more of the order-dependence that `rejects` now asserts
    * once per program instead of a hundred times.  Sixteen covers the nine shapes with room to
    * spare.  ITS COST, one number (S2 review F-7): about **20 s of work** -- one library-closure
    * read (19.5 s measured, `scratch-subsume/s2/rowrefusals-vacuity.log`) plus ~0.1 s a case, so
    * ~3 s of it is the sample itself and the rest is a boot any fixture in this suite would pay.
    * Standalone wall clock is 16-29 s including sbt start-up.  `-Dermine.test.rowRefusals.n`
    * moves the sample. */
  private val sample: Int = Integer.getInteger("ermine.test.rowRefusals.n", 16).intValue

  /** Per case.  The FIRST case also pays the shared session's library closure (19.5 s measured
    * alone, `scratch-subsume/s2/rowrefusals-vacuity.log`) and more when a full `core/test` is
    * loading on eight threads; every later case is ~0.1 s.  180 s covers the cold one with a
    * wide margin and is still "not forever", which is the whole guarantee.  Sixty seconds was
    * the first choice and it went red twice in three runs on a loaded machine for no reason
    * but contention (`b1-after-{1,3}.log`) -- a divergence pin that cries wolf is worse than
    * none. */
  private val deadlineMs: Long = 180000L

  private val fixedSeed: Option[String] = Option(System.getProperty("ermine.test.rowRefusals.seed"))

  /** Module names must be unique in the PROCESS: the dep cache keys a `Literal` by module
    * name (`Session.scala:328-341`). */
  private val counter = new java.util.concurrent.atomic.AtomicInteger(0)

  private val header =
    "import Prelude\nimport Relation.Op as Op\nimport Syntax.Relation\n"

  /** The refusal these programs must die of: the bare row-label check, the twelve `slbl` records
    * of `SUBSUME-STAGE0.md` §1.4 -- the same sentence B1 dies of, at whichever field and in
    * whichever clause ("the whole contains it but no part does" / "a part contains it but the
    * whole does not") the run's id order reaches first. */
  private val rowRefusal = "Row partitions are unsatisfiable"

  /** One generated pair.  `missing` is the non-empty subset of the two date columns the bad
    * relation does NOT carry; `extras` is how many Int payload columns it carries besides the
    * name.  `bad` must be refused, `good` must check. */
  private final case class Pair(k: Int, missing: List[String], extras: Int,
                                badSrc: String, goodSrc: String) {
    def badName  = "RowUnsatBad"  + k
    def goodName = "RowUnsatGood" + k
    def describe = "case " + k + " missing " + missing.mkString("{", ",", "}") +
                   " with " + extras + " payload column(s)"
  }

  private def module(sfx: String, extras: Int, present: List[String]): String = {
    // NO underscore in a generated name: `_` is the module-alias suffix in Ermine source
    // (`col_Op` is `col` from the module imported as `Op`), so `pB1_0` would be read as a
    // qualified name and the module would die for the wrong reason.
    val pay = (0 until extras).map(i => "p" + sfx + ('a' + i).toChar).toList
    val decls =
      "field s" + sfx + ", e" + sfx + " : Date\n" +
      "field g" + sfx + " : Int\n" +
      "field n" + sfx + " : String\n" +
      (if (pay.isEmpty) "" else "field " + pay.mkString(", ") + " : Int\n")
    val cols = ("n" + sfx) :: pay ++ present.map(_ + sfx)
    val vals = ("n" + sfx + " = \"Ada\"") ::
               pay.map(_ + " = 1") ++
               present.map { case "s" => "s" + sfx + " = @2011/1/1"
                             case _   => "e" + sfx + " = @2011/1/31" }
    header + "\n" + decls + "\n" +
      "r" + sfx + " : " + cols.mkString("[ ", ", ", " ]") + "\n" +
      "r" + sfx + " = relation [ { " + vals.mkString(", ") + " } ]\n\n" +
      "out" + sfx + " = combine_Op (dateDiff_Op days (col_Op s" + sfx +
        ") (col_Op e" + sfx + ")) g" + sfx + " r" + sfx + "\n"
  }

  private val pairGen: Gen[Pair] = for {
    extras  <- Gen.choose(0, 2)
    missing <- Gen.oneOf(List("s"), List("e"), List("s", "e"))
  } yield {
    val k = counter.incrementAndGet()
    val kept = List("s", "e").filterNot(missing.contains)
    Pair(k, missing, extras,
         module("B" + k, extras, kept),           // the bad one: the missing dates are absent
         module("G" + k, extras, List("s", "e"))) // the twin:    every column is there
  }

  /** The session every case is loaded into.  The FIRST load pays the import closure; the rest
    * are its own four declarations.  `lazy` so that a `core/test` that never reaches this
    * suite never boots it. */
  private lazy val shared: SessionEnv = fx.mkEnv

  private def outcome(name: String, src: String): (String, Long) = {
    val answer = new java.util.concurrent.atomic.AtomicReference[String]("did not run")
    val (finished, ms) = fx.bounded(deadlineMs)(answer.set(fx.outcomeOf(name, src)(shared)))
    (if (finished == "accepted") answer.get else finished, ms)
  }

  property("(rr) every unsatisfiable row program is refused, and its twin checks, in bounded time") =
    secure {
      val seed = fixedSeed.flatMap(s => Seed.fromBase64(s).toOption).getOrElse(Seed.random())
      val cases = Gen.listOfN(sample, pairGen).pureApply(Gen.Parameters.default, seed)
      val checks: List[Prop] = cases.flatMap { c =>
        val (bad, badMs)   = outcome(c.badName,  c.badSrc)
        val (good, goodMs) = outcome(c.goodName, c.goodSrc)
        List(
          bad.startsWith("refused: ") :|
            (c.describe + ": the bad program was not refused (" + badMs + " ms): " + bad),
          // REFUSED BY THIS CHECK, not merely refused (S2 review F-1).  These programs are
          // MACHINE-GENERATED, so they are the ones most likely to die for the wrong reason: a
          // generated name that collides, a `field` redeclaration, a parse error of the kind
          // `module`'s no-underscore rule above already had to dodge.  Every such death is a
          // `Death` and would read as "refused" here, leaving sixteen green cases that assert
          // nothing about row unsatisfiability.  The twin is only a partial guard -- it catches
          // breakage that ALSO breaks the twin, and bad and twin differ exactly in the relation's
          // declared columns, which is the part this generator varies.  The cause check costs
          // nothing: the `Death` message is already in the outcome string.  `failsMatching`
          // (`TestStage1Pins.scala:35`) is the same idea for fixed programs.
          bad.contains(rowRefusal) :|
            (c.describe + ": refused, but not by the row-label check (" + badMs + " ms): " + bad),
          (good == "accepted") :|
            (c.describe + ": the twin did not check (" + goodMs + " ms): " + good))
      }
      Prop.all(checks: _*) :| ("seed " + seed.toBase64 + ", " + sample + " cases")
    }
}
