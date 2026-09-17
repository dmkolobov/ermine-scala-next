package com.clarifi.reporting

import com.clarifi.reporting.ermine.session.SessionEnv

import org.scalacheck.{ Gen, Prop, Properties }
import Prop.{ Result => _, _ }

/** Unsatisfiable row programs are REFUSED, never accepted, never hung.
  *
  * BACK-PORT of `scala3-migration` b69b13de's `TestRowRefusals.scala` to Scala 2.11 /
  * scalacheck 1.11.3; what changed and why is in `backport/SUBSUME-2.11.md` and in the two
  * BACK-PORT paragraphs below.
  *
  * The `subsume-termination` programme (`tracker/PROMPT-subsume-termination.md` on
  * `scala3-migration`; this branch has no `tracker/` tree) started from a report that the
  * checker HANGS on one refused row program -- B1, the `dateDiff` combine over a relation
  * without the dates.  It does not.  Stage 0 measured the refusal at 0.06-0.09 s at seventeen
  * `Supply` id bases, the escape check in `subsumeType` returning on all 492,200 traced calls
  * with no cycle in 984,400 identity-marked walks; Stage 1a proved that walk total
  * (`Rowpartition/SubsumeEscape.lean`, `runV_steps`); Stage 1b proved the row loop bounded at
  * the shipped defaults (`Loop/RejectTerm.lean`, `budgetSP_terminates`) and no cyclic binding
  * reachable (`runsP_noAliasChain`).  What did not return in bounded time was the ScalaCheck
  * PROPERTY: `ErmineFixture.no` rewrote a refutation to *passed* rather than *proved*, so a
  * hundred library-scale re-checks were asked for.  `ErmineFixture.rejects` is that fix; this
  * suite is the pin that outlives it.
  *
  * Two things are pinned here that no property pinned before.
  *
  *  - **The shape, not the instance.**  B1 is one program.  This generates a family: random
  *    field names, a relation carrying a random subset of them, and a `combine_Op` of an op
  *    over two date columns, of which a random NON-EMPTY subset is missing from the relation.
  *    Every such program must be refused, and its twin -- the same program over a relation
  *    that carries all of them -- must check.
  *  - **Bounded time.**  Every case runs on a daemon thread joined with a deadline, so a
  *    divergence is a RED property in a minute rather than a wedged landing run.  That is the
  *    guarantee the programme was after, and it is a pin rather than a proof: the theorems are
  *    S1a's and S1b's, and they do not cover `subsumeType` as a whole.
  *
  * BACK-PORT: WHY `coalesce'` AND NOT `dateDiff`, and it is a finding rather than a taste.
  * The Scala 3 suite builds each case as `combine_Op (dateDiff_Op days (col_Op s) (col_Op e))
  * g r`.  That program is NOT refused on this branch: `Relation.Op`'s `dateDiff` here has NO
  * signature (`Op.e:150` is the commented-out line that would have given it one and left `r2`
  * free anyway), so the result row is unconstrained and the combine type-checks over a
  * relation carrying neither date -- the F3/B1 defect itself, which this branch does not
  * carry the stdlib fix for.  MEASURED: the exact B1 program of `TestDateAndScan` loads clean
  * here in 0.25 s (`scratch-subsume/p211/probe/B1.e`).  Porting the F3 signature is a stdlib
  * change with its own gates and is not in this port's brief.  So the op is `coalesce'`
  * instead, whose signature -- `(RUnion2 r r1 r2, AsOp opc, AsOp opa) => opc r1 a -> opa r2 a
  * -> Op r a` -- is BYTE-IDENTICAL on the two branches and puts both columns in the op's row,
  * which is precisely the shape the `combine` constraint `r <- (s, o)` then refuses.  The
  * refusal is the same sentence at the same site: `Row partitions are unsatisfiable at field
  * 'X.eB1': a part contains it but the whole does not` (`probe/Bad1.e`, 0.50 s).
  *
  * WHY THE CASES SHARE ONE SESSION.  `ErmineFixture.loadStatements` names every case
  * `module Test`, and a case loaded into a fresh `mkEnv` re-reads and re-type-checks the whole
  * import closure -- a library boot, tens of seconds.  Twenty cases that way is minutes of
  * re-reading the standard library.  `ErmineFixture.loadNamed` gives each case its own module
  * name, so they can all go into ONE warm session: the closure is read once, and the second
  * and later cases cost only their own four declarations.
  *
  * BACK-PORT: THE SAMPLE IS DRAWN ONCE, FROM A `java.util.Random` SEED THAT IS REPORTED.  A
  * `forAll` here would ask ScalaCheck for `minSuccessfulTests` = 100 draws, which is the very
  * cost this stage removed.  The Scala 3 suite draws its own sample from an
  * `org.scalacheck.rng.Seed`; scalacheck 1.11.3 HAS NO `rng` PACKAGE (`Seed` arrives in 1.13),
  * and its `Gen.Parameters` carries a `scala.util.Random` instead.  So the seed here is a
  * `Long`, the sample is `gen.apply(Gen.Parameters.default.withRng(new Random(seed)))`, and a
  * failure is reproducible by `-Dermine.test.rowRefusals.seed=<long>` exactly as there. */
object TestRowRefusals extends Properties("unsatisfiable row programs (S2)") {
  private val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)

  /** A LAZY `secure`, shadowing `Prop.secure`, and on this branch it is the difference
    * between a suite and a deadlock (`backport/SUBSUME-2.11.md`; the same idiom and the
    * same diagnosis as `TestRunner.scala` / `TestDoc.scala` / `TestWidgets.scala` on
    * `json-encode-2.11`).
    *
    * scalacheck 1.11.3 stores a property BY VALUE --
    * `Properties.PropertySpecifier.update(String, Prop)`, against 1.15.4's
    * `update(String, Function0[Prop])`, both read with `javap` from the shipped jars -- and
    * `Prop.secure` is eager in BOTH versions.  So here the whole right-hand side of
    * `property(..) = secure { .. }` is evaluated where it is written, which is INSIDE THIS
    * OBJECT'S STATIC INITIALISER.  Harmless for a single-threaded
    * property; fatal for one that starts a thread which calls back into the object, which
    * is exactly what `ErmineFixture.bounded` does here (the thread body reads
    * `getstatic TestRowRefusals$.MODULE$`).  The JVM makes a thread that touches a class
    * whose initialisation is in progress on ANOTHER thread wait for that initialisation --
    * and the initialising thread is itself inside `Thread.join`.  MEASURED before the fix:
    * every case's daemon thread parked with no frames below the thunk and 0 % CPU, the
    * property thread in `join` inside `TestRowRefusals$.<clinit>`, one abandoned thread and
    * one 180 s timeout per case (`scratch-subsume/p211/rr-jstack{1,2}.txt`,
    * `rr-n2-jstack.txt`).  On `scala3-migration` the by-name `update` defers the whole
    * right-hand side out of `<clinit>`, so this shadow restores that branch's behaviour
    * rather than changing it.
    *
    * It also keeps the ONE-EVALUATION property this stage is about: the body answers
    * `Prop.all(..)` over `propBoolean` props, and `propBoolean(true)` is `proved` in 1.11.3
    * (verified in the shipped jar), so an all-green run is `Proof` and ScalaCheck stops
    * after one test exactly as `rejects` makes it do elsewhere. */
  private def secure[P](p: => P)(implicit pv: P => Prop): Prop =
    Prop((prms: Gen.Parameters) => Prop.secure(p)(pv).apply(prms))

  /** Cases per run.  Each is a bad module and its positive twin, so `n` cases are `2n` loads
    * into the shared session.
    *
    * SIXTEEN, and the reason is not wall clock: the fixture's one library boot dominates and a
    * case is a fraction of a second.  What bounds the sample is the SHAPE SPACE -- three
    * missing-column subsets by three payload widths is nine shapes -- and the id bases: each
    * case draws fresh `Supply` ids, so a larger sample also sweeps more of the order-dependence
    * that `rejects` now asserts once per program instead of a hundred times.  Sixteen covers the
    * nine shapes with room to spare.  `-Dermine.test.rowRefusals.n` moves the sample. */
  private val sample: Int = Integer.getInteger("ermine.test.rowRefusals.n", 16).intValue

  /** Per case.  The FIRST case also pays the shared session's library closure (tens of seconds,
    * and more when a full `core/test` is loading on several threads); every later case is a
    * fraction of a second.  180 s covers the cold one with a wide margin and is still "not
    * forever", which is the whole guarantee.  Sixty seconds was the Scala 3 stage's first choice
    * and it went red twice in three runs on a loaded machine for no reason but contention -- a
    * divergence pin that cries wolf is worse than none. */
  private val deadlineMs: Long = 180000L

  private val fixedSeed: Option[Long] =
    Option(java.lang.Long.getLong("ermine.test.rowRefusals.seed")).map(_.longValue)

  /** Module names must be unique in the PROCESS: the dep cache keys a `Literal` by module
    * name (`Session.scala:295-308`). */
  private val counter = new java.util.concurrent.atomic.AtomicInteger(0)

  private val header =
    "import Prelude\nimport Relation.Op as Op\nimport Syntax.Relation\n"

  /** The refusal these programs must die of: the bare row-label check -- the same sentence B1
    * dies of on `scala3-migration`, at whichever field and in whichever clause ("the whole
    * contains it but no part does" / "a part contains it but the whole does not") the run's id
    * order reaches first. */
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
      "field g" + sfx + " : Date\n" +
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
      "out" + sfx + " = combine_Op (coalesce'_Op (col_Op s" + sfx +
        ") (col_Op e" + sfx + ")) g" + sfx + " r" + sfx + "\n"
  }

  private val pairGen: Gen[Pair] = for {
    extras  <- Gen.choose(0, 2)
    missing <- Gen.oneOf(List(List("s"), List("e"), List("s", "e")))
  } yield {
    val k = counter.incrementAndGet()
    val kept = List("s", "e").filterNot(missing.contains)
    Pair(k, missing, extras,
         module("B" + k, extras, kept),           // the bad one: the missing columns are absent
         module("G" + k, extras, List("s", "e"))) // the twin:    every column is there
  }

  /** The session every case is loaded into.  `lazy` so that a `core/test` that never reaches
    * this suite never boots it, and FORCED BEFORE THE FIRST DEADLINE by `bootShared` below.
    *
    * BACK-PORT, and it is hygiene rather than the fix (`backport/SUBSUME-2.11.md`).  The
    * Scala 3 suite forces this lazy val inside the first `bounded` case, which charges the
    * fixture's `mkEnv` to that case's deadline and initialises a Scala 2.11 object's `lazy
    * val` under the object's own monitor from a thread that is about to be joined.  MEASURED:
    * `mkEnv` itself is only ~300 ms here, so moving it out buys almost no time -- what wedged
    * this suite before the lazy `secure` above was the CLASS-INITIALISATION deadlock, not the
    * boot.  It is still the right place: the deadline should bound the CHECK, and what remains
    * inside it is the first case's import closure (43.5 s measured on a loaded machine,
    * `scratch-subsume/p211/bp-rowrefusals-mutation.log`), which is what the 180 s is sized
    * for.  Same lesson the Scala 3 stage recorded when its B1 pin turned out to be bounding
    * `literalLock` contention instead of the check. */
  private lazy val shared: SessionEnv = fx.mkEnv

  /** Force the shared session, OUTSIDE any deadline, and say what it cost. */
  private def bootShared(): Long = {
    val t = System.currentTimeMillis
    shared.loadedModules.size
    System.currentTimeMillis - t
  }

  private def outcome(name: String, src: String): (String, Long) = {
    val answer = new java.util.concurrent.atomic.AtomicReference[String]("did not run")
    val (finished, ms) = fx.bounded(deadlineMs)(answer.set(fx.outcomeOf(name, src)(shared)))
    (if (finished == "accepted") answer.get else finished, ms)
  }

  property("(rr) every unsatisfiable row program is refused, and its twin checks, in bounded time") =
    secure {
      val seed: Long = fixedSeed.getOrElse(scala.util.Random.nextLong())
      val params = Gen.Parameters.default.withRng(new scala.util.Random(seed))
      /* P211 review F-1.  `Gen[T].apply(params)` is `Option[T]` in scalacheck 1.11.3, and
       * `getOrElse(Nil)` would turn "the sample could not be drawn" into "there is no
       * sample" -- whereupon `checks` is empty, and `Prop.all` with an empty `Seq` answers
       * `proved` (bytecode: `all(Seq)` = `if (ps.isEmpty) proved`).  That is a GREEN
       * property asserting nothing, which is exactly the vacuity the S2 review closed in
       * this file.  The Scala 3 original cannot reach it: `pureApply` retries and then
       * THROWS `Gen.RetrievalError`.  `sys.error` restores that: the throw happens inside
       * the lazy `secure` above, which turns it into `Prop.exception` -- a RED property
       * naming the seed.  (The alternative, a `cases.size ?= sample` conjunct, asserts the
       * same thing one evaluation later; the throw was chosen because it matches the Scala 3
       * behaviour it replaces and cannot itself be dropped by a later edit to `checks`.)
       * It cannot fire today -- `Gen.choose` and `Gen.oneOf` never fail -- but a `suchThat`,
       * a `retryUntil` or a filter on the generated names is one edit away. */
      val cases = Gen.listOfN(sample, pairGen).apply(params).getOrElse(
        sys.error("rowRefusals: the generator produced no sample of " + sample +
                  " cases at seed " + seed))
      val bootMs = bootShared()
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
          // nothing: the `Death` message is already in the outcome string.
          bad.contains(rowRefusal) :|
            (c.describe + ": refused, but not by the row-label check (" + badMs + " ms): " + bad),
          (good == "accepted") :|
            (c.describe + ": the twin did not check (" + goodMs + " ms): " + good))
      }
      Prop.all(checks: _*) :|
        ("seed " + seed + ", " + sample + " cases, session boot " + bootMs + " ms")
    }
}
