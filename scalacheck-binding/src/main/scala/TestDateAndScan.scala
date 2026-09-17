package com.clarifi.reporting

import java.util.{Calendar, Date, GregorianCalendar, TimeZone}

import com.clarifi.reporting.ermine._

import org.scalacheck.{ Prop, Properties }
import Prop.{ Result => _, _ }

/** Stage F3: the stdlib fixes that have an Ermine-visible answer --
  * `Date`'s timezone (A3), `Date.formatQuarter` (A4), `Relation.Op.dateDiff`'s
  * signature (B1) and `Layout.Scan`'s missing re-exports (C5).
  *
  * HOST INDEPENDENCE, and the one global write in this file (F3 review, N-6).  A3 is a
  * DIFFERENCE between two timezones, so on a build machine whose default zone is already UTC
  * the pre-fix and post-fix compilers compute the same answers and NO test can tell them
  * apart without changing the default zone.  The first version of these properties simply
  * read the host's zone, so the A3 half of the guard evaporated on a UTC host; and one of
  * them wrote `TimeZone.setDefault` with no lock, in a suite `build.sbt` runs in parallel.
  *
  * Both are fixed by `underZone`, the only place in this file that touches global state:
  * it takes `ErmineFixture.literalLock` -- the same monitor `loadStatements` takes, so no
  * module load can be in flight on another thread -- and restores the previous default in a
  * `finally`.  Every date property now runs its probe under an explicitly non-UTC zone, so
  * it discriminates on any host, and the window in which the default is not the host's is
  * one property's body.
  *
  * WHAT COULD SEE THE WRITE, measured by grep over `core/src/main/scala`: exactly two
  * places read the JVM default zone and do not immediately pin it -- `Op.scala`'s
  * `TimeUnit.increment`/`incrementTimestamp` (which is `Date.incrementDate`, a sibling of
  * A3 that F3 did not fix) and `PrimT.parse`'s `SimpleDateFormat`.  Everything else
  * (`SqlEmitter`, `SqlExecution`, every `PrimExprs` formatter) calls `setTimeZone` on the
  * calendar it just made.  `TestInterfaceRoundTrip` does neither -- it round-trips
  * signatures and never evaluates a date -- so it cannot be affected; nor can
  * `TestLoopTrace`, `TestSurface*`, `TestScopes` or `TestRecordPrims`.  `TestErmine`'s
  * "date literals/SQL emitting round-trip" uses `Calendar.getInstance` only to GENERATE
  * y/m/d, and parses and emits through zone-pinned paths, so a different default changes
  * which dates it generates and not whether it passes.
  *
  * Every property below FAILS on the pre-fix compiler on any host; the pre-fix answer is named.
  */
object TestDateAndScan extends Properties("Date, dateDiff and Layout.Scan (F3)") {
  private val fx = ErmineFixture(sigEntail = ErmineFixture.untilSigFixes)
  import fx.{defAndEval, typeChecks, rejects}

  private val onlyTest = Map("Test" -> fx.all)

  private def str(r: Runtime): String = r.whnf.extract[String]

  /** The one global write in this file; see the class comment. */
  private def underZone[A](zone: String)(body: => A): A =
    ErmineFixture.literalLock.synchronized {
      val saved = TimeZone.getDefault
      try { TimeZone.setDefault(TimeZone.getTimeZone(zone)); body }
      finally TimeZone.setDefault(saved)
    }

  /** `(getYear, getMonth, getDate)` of `d` read in `zone`, in `java.util.Date`'s
    * conventions -- the reading the accessors used to give when `zone` was the default. */
  private def readIn(d: Date, zone: String): (Int, Int, Int) = {
    val c = new GregorianCalendar(TimeZone.getTimeZone(zone))
    c.setTime(d)
    (c.get(Calendar.YEAR) - 1900, c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH))
  }

  // ------------------------------------------------------- the Ermine-level probes

  private val dateProbes =
    """import Prelude
      |import Date as D
      |import String as S
      |import DateRange as DR
      |
      |mths : List Date
      |mths = [ @2011/1/1, @2011/2/1, @2011/3/1, @2011/4/1, @2011/5/1, @2011/6/1,
      |         @2011/7/1, @2011/8/1, @2011/9/1, @2011/10/1, @2011/11/1, @2011/12/1 ]
      |
      |quarterLabels = unwords_S (map_List formatQuarter_D mths)
      |quarterNums   = unwords_S (map_List (toString . quarter_D) mths)
      |monthNums     = unwords_S (map_List (toString . getMonth_D) mths)
      |dayNums       = unwords_S (map_List (toString . getDate_D) mths)
      |yearNums      = unwords_S (map_List (toString . getYear_D) mths)
      |excelJan      = formatExcelDate_D @2011/1/1
      |periodQ2      = formatPeriodOr_DR "custom" (@2011/1/1, @2011/4/1)
      |excelPerJan   = formatExcelPeriod_DR (@2011/1/1, @2011/1/31)
      |""".stripMargin

  /** America/Denver is UTC-7 in January, so midnight UTC on the 1st is the previous month's
    * last day there: the pre-fix accessors answered 11 / 31 / 110 for `@2011/1/1` and the
    * fixed ones answer 0 / 1 / 111 wherever the test runs. */
  private val LOCAL = "America/Denver"

  property("formatQuarter labels all twelve months, Q1 included (A4)") = secure {
    underZone(LOCAL) {
      // Pre-fix under this zone: "Q4 Q2 Q2 Q2 Q2 Q3 Q3 Q3 Q3 Q4 Q4 Q4" -- `/ 4` made the
      // quarters four months long, the 1-based number indexed a 0-based list so "Q1" was
      // unreachable, and A3 moved January into the previous December on top of that.
      str(defAndEval(dateProbes, "quarterLabels", onlyTest)) ?=
        "Q1 Q1 Q1 Q2 Q2 Q2 Q3 Q3 Q3 Q4 Q4 Q4"
    }
  }

  property("quarter is 1-based and three months long (A4)") = secure {
    underZone(LOCAL) {
      str(defAndEval(dateProbes, "quarterNums", onlyTest)) ?= "1 1 1 2 2 2 3 3 3 4 4 4"
    }
  }

  property("the Date accessors read the UTC calendar, as the formatters do (A3)") = secure {
    underZone(LOCAL) {
      // Pre-fix under this zone: "11 0 1 2 …", "31 31 28 …", "110 111 111 …".
      (str(defAndEval(dateProbes, "monthNums", onlyTest)) ?= "0 1 2 3 4 5 6 7 8 9 10 11") &&
      (str(defAndEval(dateProbes, "dayNums",   onlyTest)) ?= "1 1 1 1 1 1 1 1 1 1 1 1") &&
      (str(defAndEval(dateProbes, "yearNums",  onlyTest)) ?=
         "111 111 111 111 111 111 111 111 111 111 111 111")
    }
  }

  property("an accessor-built label agrees with a formatter-built one (A3)") = secure {
    underZone(LOCAL) {
      // `formatExcelDate` is built on the accessors and `unsafeFormatDate` on the formatters;
      // under this zone they used to disagree ("Dec 31" against "1/1/11").  `formatPeriodOr`
      // and `formatExcelPeriod` reach both, through `DateRange`.
      (str(defAndEval(dateProbes, "excelJan",    onlyTest)) ?= "Jan 1") &&
      (str(defAndEval(dateProbes, "periodQ2",    onlyTest)) ?= "Q2 2011") &&
      (str(defAndEval(dateProbes, "excelPerJan", onlyTest)) ?= "Jan 1 to Jan 31")
    }
  }

  property("the same answers under five default zones (A3)") = secure {
    val zones = List("UTC", LOCAL, "Pacific/Kiritimati", "Asia/Tokyo", "Pacific/Niue")
    val answers = zones map { z =>
      (z, underZone(z)(str(defAndEval(dateProbes, "monthNums", onlyTest))))
    }
    Prop.all(answers.map { case (z, got) =>
      (got ?= "0 1 2 3 4 5 6 7 8 9 10 11") :| ("default zone " + z + " answered " + got)
    }: _*)
  }

  // ------------------------------------------------------- A3 at the Scala level

  property("PrimExprs' accessors read UTC and not the default zone (A3)") = secure {
    val d = com.clarifi.reporting.util.YMDTriple(2011, 1, 1)
    val utc = readIn(d, "UTC")
    val local = readIn(d, LOCAL)
    val got = (PrimExprs.getYear(d), PrimExprs.getMonth(d), PrimExprs.getDate(d))
    // Host-independent: no default zone is set, and the two readings differ by construction.
    ((local != utc) :| "the probe zones must disagree, or this proves nothing") &&
    ((got ?= utc) :| ("read as " + got + ", UTC is " + utc)) &&
    ((got != local) :| ("read as the " + LOCAL + " calendar would: " + local))
  }

  property("the accessors ignore the JVM default timezone (A3)") = secure {
    val d = com.clarifi.reporting.util.YMDTriple(2011, 1, 1)
    val answers = List("UTC", LOCAL, "Pacific/Kiritimati", "Asia/Tokyo") map { z =>
      (z, underZone(z)((PrimExprs.getYear(d), PrimExprs.getMonth(d), PrimExprs.getDate(d))))
    }
    // Pre-fix (`java.util.Date`'s own accessors): America/Denver answered (110, 11, 31).
    Prop.all(answers.map { case (z, got) =>
      (got ?= ((111, 0, 1))) :| ("default zone " + z + " answered " + got)
    }: _*)
  }

  // ------------------------------------------------------- B1: dateDiff's signature

  private val dateDiffPrelude =
    """import Prelude
      |import Relation.Op as Op
      |import Syntax.Relation
      |
      |field startDate, endDate : Date
      |field gap : Int
      |field name : String
      |""".stripMargin

  property("a dateDiff combine over a relation WITH the dates checks (B1)") =
    typeChecks(dateDiffPrelude +
      """
        |spans : [ name, startDate, endDate ]
        |spans = relation [ { name = "Ada", startDate = @2011/1/1, endDate = @2011/1/31 } ]
        |
        |good = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap spans
        |""".stripMargin, "good", onlyTest)

  /* QUARANTINED 2026-09-16 (tracker/GATE-POLICY.md; TICKET-editor-and-solver-followups.md item 12).
   * This refutation does not terminate when the suite runs ALONE: the checker spins in
   * `Subst.subsumeType -> hm.kindVars` (an unmemoised walk of every kind in the substitution
   * environment, `Kind.scala:125`) for as long as anyone has waited (28 CPU-minutes observed),
   * RUNNABLE, GC idle.  Reproduced alone on scala3-migration 478a369c itself, before any JSON
   * work, and on json-encode 3eba80f8; it PASSES inside a full core/test whenever the Supply
   * ids it meets happen to be favourable (the 1070/1070, 1137, 1148 and 1170 landing runs), and
   * wedged three full runs on 2026-09-16 once two new suites shifted that order.  A pre-existing
   * type-checker cliff on one rejection case; the JSON stages touch nothing it reaches.  Its
   * positive twin above still checks.  Registered only under -Dermine.test.dateDiffReject=true
   * so that a green suite means green and a run cannot wedge on it. */
  if (sys.props.contains("ermine.test.dateDiffReject"))
  property("a dateDiff combine over a relation WITHOUT the dates is now REJECTED (B1)") =
    rejects(typeChecks(dateDiffPrelude +
      """
        |people : [ name ]
        |people = relation [ { name = "Ada" } ]
        |
        |bad = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap people
        |""".stripMargin, "bad", onlyTest))

  // -------------------------------------------------- B1: the same pair, under a DEADLINE
  /* The programme that produced these properties started from a report that the B1 refusal
   * HANGS (`tracker/PROMPT-subsume-termination.md` Part B).  It does not: the module is
   * refused in 0.06-0.09 s by the compiler and at every one of 17 `Supply` id bases
   * (`SUBSUME-STAGE0.md` §1.3, §1.6), the escape check at `Subst.scala:648` returns on every
   * one of 492,200 traced calls, and `Rowpartition/SubsumeEscape.lean`'s `runV_steps` proves
   * that walk total.  What did not return in bounded time was the PROPERTY, and `rejects`
   * above is that fix.
   *
   * This pins the thing the report was actually worried about, which nothing pinned before:
   * that a refusal ARRIVES, in bounded time, and is the ROW-LABEL one.  The work runs on a
   * daemon thread joined with a deadline (the `(iso)` idiom of `TestRunner.scala` on
   * `json-encode`), so a future divergence is a red property in three minutes instead of a
   * wedged landing run.
   *
   * TWO BOUNDS, because one of them cannot be tight.  The outer 180 s covers a COLD session:
   * the first load into a fresh `mkEnv` reads the whole import closure, ~20 s measured alone
   * and more when eight properties of this suite are loading at once.  The inner 30 s covers
   * the twin's WARM check, which is the number that means something -- 0.1-0.2 s in every
   * measurement -- and it is the bound a divergence would blow.
   *
   * WHY `loadNamed` AND NOT `typeChecks`.  The first version of this pin used `typeChecks`,
   * whose `loadStatements` takes `ErmineFixture.literalLock` (every case is `module Test`, so
   * the shared dep-cache key must be serialised).  `underZone` above holds that same lock for
   * a whole property body, several library-scale loads long, and ScalaCheck runs this suite's
   * properties on a pool: the deadline then bounded the QUEUE rather than the check, and two
   * of three runs went red at exactly 60,000 ms with nothing wrong
   * (`scratch-subsume/s2/b1-after-{1,3}.log`).  `loadNamed` gives the pin its own module names
   * and takes no lock, so the deadline bounds the check.  It also means a load can be in
   * flight while `underZone` has the default zone changed -- which can only change the date
   * VALUES a generated module computes, never whether it type-checks, and a verdict is all
   * this property asserts. */

  private val b1Bad = dateDiffPrelude +
    """
      |people : [ name ]
      |people = relation [ { name = "Ada" } ]
      |
      |bad = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap people
      |""".stripMargin

  private val b1Good = dateDiffPrelude +
    """
      |spans : [ name, startDate, endDate ]
      |spans = relation [ { name = "Ada", startDate = @2011/1/1, endDate = @2011/1/31 } ]
      |
      |good = combine_Op (dateDiff_Op days (col_Op startDate) (col_Op endDate)) gap spans
      |""".stripMargin

  /** Module names must be unique in the PROCESS (the dep cache keys a `Literal` by module
    * name), and this property is evaluated once -- but count anyway, so that a re-evaluation
    * could never collide. */
  private val b1Counter = new java.util.concurrent.atomic.AtomicInteger(0)

  property("(B1-bound) the refusal arrives under a deadline, names the row, and the twin checks") =
    secure {
      val k       = b1Counter.incrementAndGet()
      val badOut  = new java.util.concurrent.atomic.AtomicReference[String]("did not run")
      val goodOut = new java.util.concurrent.atomic.AtomicReference[String]("did not run")
      val warmMs  = new java.util.concurrent.atomic.AtomicLong(-1L)
      val (finished, totalMs) = fx.bounded(180000L) {
        val env = fx.mkEnv
        badOut.set(fx.outcomeOf("SubsumeB1Bad" + k, b1Bad)(env))
        val t = System.currentTimeMillis
        goodOut.set(fx.outcomeOf("SubsumeB1Good" + k, b1Good)(env))
        warmMs.set(System.currentTimeMillis - t)
      }
      ((finished == "accepted") :|
         ("the bounded pair did not finish: " + finished + " after " + totalMs + " ms")) &&
      (badOut.get.startsWith("refused: ") :|
         ("the B1 program was not refused: " + badOut.get)) &&
      (badOut.get.contains("Row partitions are unsatisfiable") :|
         ("refused, but not by the row-label check: " + badOut.get)) &&
      ((goodOut.get == "accepted") :|
         ("the positive twin did not check: " + goodOut.get)) &&
      ((warmMs.get >= 0L && warmMs.get < 30000L) :|
         ("the WARM twin check took " + warmMs.get + " ms (the cold pair took " + totalMs + " ms)"))
    }

  // ------------------------------------------------------- C5: the re-exports

  private val scanReexports =
    """import Layout.Scan as LS
      |
      |useRemoveK  = removeK_LS
      |useRemoveBy = removeBy_LS
      |useMultiply = multiply_LS
      |""".stripMargin

  // Pre-fix all three were `error: undefined term` and the module did not load.
  property("Layout.Scan re-exports removeK (C5)") =
    typeChecks(scanReexports, "useRemoveK", onlyTest)

  property("Layout.Scan re-exports removeBy (C5)") =
    typeChecks(scanReexports, "useRemoveBy", onlyTest)

  property("Layout.Scan re-exports multiply (C5)") =
    typeChecks(scanReexports, "useMultiply", onlyTest)
}
