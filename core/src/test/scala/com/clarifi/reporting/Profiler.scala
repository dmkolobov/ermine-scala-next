/*

TODO: Rewrite this with the new relations, if necessary

package com.clarifi.reporting

import scalaz._
import Scalaz._
import com.clarifi.reporting._
import Reporting._
import RelationGens._
import com.clarifi.reporting.sql._
import com.clarifi.reporting.backends._
import java.sql.Connection
import com.clarifi.reporting.PrimT._

import scala.math.{sqrt, pow}
import scala.collection.immutable.ListMap

import relational._
import SMEnv.dummySmenv

import com.clarifi.machines._

import SqlEmitter._

/**
 * @author MSP
 * @todo create tests where the exact relation can be specified
 * @todo track outliers
 * @todo display query plans
 * @todo track I/O costs
 * @todo flush the cache after each test
 * @todo time the no-op scan
 * @todo track the size of the result relation
 */
object Profiler {
  /**
   * Accepts data points as they stream in, and calculates summary statistics
   * on the data.
   */
  class Stats {
    var times = List[Double]()
    def addTime(time: Double): Unit =
      times = time :: times

    def min = times.min
    def max = times.max
    def mean = times.sum / times.length
    def median = {
      val sortedTimes = times.sortWith(_ < _)
      val len = sortedTimes.length
      val mid = len / 2
      if (len % 2 == 0)
        (sortedTimes(mid) + sortedTimes(mid+1)) / 2.0
      else
        sortedTimes(mid)
    }

    def stddev = sqrt(variance)
    def variance = moment(2)
    def skewness = moment(3) / pow(moment(2), 1.5)
    def kurtosis = moment(4) / pow(moment(2), 2)

    private def moment(k: Int) = {
      if (k == 0) 1.0
      else if (k == 1) 0.0
      else {
        val mu = mean
        times.map(x => pow(x - mu, k)).sum / times.length
      }
    }

    override def toString = "[min/mean/max/stddev] = " +
        List(min, mean, max, stddev).map(_.truncate(2)).mkString("[", " / ", "]")
  }

  case class Truncatable(d: Double) {
    def truncate(places: Int): String = {
      val format = new java.text.DecimalFormat("0." + List.fill(places)("0").mkString)
      format.format(d)
    }
  }
  implicit def double2Truncatable(d: Double): Truncatable = Truncatable(d)

  /**
   * Profiles a block of code
   * @param burn - true to run the block once before profiling, for example to
   *               cache values
   * @param numTrials - the number of trials to run
   * @param block - the code to profile
   */
  def profile(burn: Boolean, numTrials: Int, block: => Unit): Stats = {
    profile(burn, numTrials, (), block, ())
  }

  /**
   * Profiles a block of code
   * @param burn - true to run the block once before profiling, for example to
   *               cache values
   * @param numTrials - the number of trials to run
   * @param setup - a block of code to run before each test
   * @param block - the code to profile
   * @param teardown - a blcok of code to run after each test
   */
  def profile(burn: Boolean, numTrials: Int, setup: => Unit, block: => Unit, teardown: => Unit): Stats = {
    if (burn)
      block

    val stats = new Stats
    var startTime: Long = 0
    var stopTime: Long = 0

    for (i <- 0 until numTrials) {
      setup
      startTime = System.currentTimeMillis()
      block
      stopTime = System.currentTimeMillis()
      teardown

      stats.addTime(stopTime - startTime)
    }

    stats
  }

  /**
   * Profiles a block of code
   * @param burn - true to run the block once before profiling, for example to
   *               cache values
   * @param numTrials - the number of trials to run
   * @param samples - the number of times to run each trial, in case the time is
   *                below the timer resolution (should be set as low as possible)
   * @param block - the code to profile
   */
  def profile(burn: Boolean, numTrials: Int, samples: Int, block: => Unit): Stats = {
    profile(burn, numTrials, samples, (), block, ())
  }

  /**
   * Profiles a block of code
   * @param burn - true to run the block once before profiling, for example to
   *               cache values
   * @param numTrials - the number of trials to run
   * @param samples - the number of times to run each trial, in case the time is
                    below the timer resolution (should be set as low as possible)
   * @param setup - a block of code to run before each test
   * @param block - the code to profile
   * @param teardown - a blcok of code to run after each test
   */
  def profile(burn: Boolean, numTrials: Int, samples: Int, setup: => Unit, block: => Unit, teardown: => Unit): Stats = {
    if (burn)
      block

    val stats = new Stats
    var startTime: Long = 0
    var stopTime: Long = 0

    for (i <- 0 until numTrials) {
      setup
      startTime = System.currentTimeMillis()
      for (j <- 0 until samples) {
        block
      }
      stopTime = System.currentTimeMillis()
      teardown

      stats.addTime((stopTime - startTime).asInstanceOf[Double] / samples)
    }

    stats
  }
}

object ReportingProfiling {
  import Profiler._

  /**
   * Class representing the statistics of a DB profiling test.
   * @param stats - the statistics of the run
   * @param resultSize - the number of rows in the resulting relation
   * @param queryPlan - the query plan of the tested relation
   */
  case class DBStats(stats: Stats, resultSize: Int, queryPlan: String) {
    override def toString: String = stats.toString + " (" + resultSize + ")"
  }

  /**
   * Profiles all of the relations for a given Run/Scanner, given a number of
   * trials and tuples for each run.
   */
  def profileAllRelations(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                               (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                               : Map[String, DBStats] = {
    ListMap("Noop" -> profileNoop(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Join-common" -> profileJoin_Common(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Join-cartesian" -> profileJoin_Cartesian(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Union" -> profileUnion(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Minus-distint" -> profileMinus_Distinct(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Minus-common" -> profileMinus_Common(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Filter-all" -> profileFilter_All(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Filter-none" -> profileFilter_None(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Combine" -> profileCombine(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Aggregate" -> profileAggregate(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql),
            "Rename" -> profileRename(burn, numTrials, samples, tuples)(r, backend, scanner, debugSql))
  }

  def printStats(map: Map[String, DBStats]) = map.foreach(e => println(e._1 + " ==> " + e._2))

  /**
   * Runs an entire set of profiling tests, outputting the results to a file (CSV)
   * @param testNames - the names of the individual tests (e.g., SQL vendors)
   * @param samples - the 'sample' param to use for each test (not given -> 1)
   * @param backends - the Run/Scanner to use for each test
   * @param tupleSizes - the numbers of tuples to test
   * @param filename - the name of the file to output (no extension)
   */
  def profileSuite(testNames: List[String],
                         samples: Map[String, Int],
                         backends: Map[String, (Run[DB], Scanner[DB], SqlExecution, DebugBackend[DB])],
                         tupleSizes: List[Int],
                         filename: String)
                        : Unit = {
    import java.io.{BufferedWriter, FileWriter}
    val writer = new BufferedWriter(new FileWriter(filename + ".csv"))

    val profilers: Map[String, (Int, Int, Run[DB], SqlExecution, Scanner[DB], DebugBackend[DB]) => DBStats] = ListMap(
      "Noop" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileNoop(false, 4, s, t)(r, b, x, d)),
      "Join-common" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileJoin_Common(false, 4, s, t)(r, b, x, d)),
      "Join-cartesian" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileJoin_Cartesian(false, 4, s, t)(r, b, x, d)),
      "Union" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileUnion(false, 4, s, t)(r, b, x, d)),
      "Minus-distint" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileMinus_Distinct(false, 4, s, t)(r, b, x, d)),
      "Minus-common" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileMinus_Common(false, 4, s, t)(r, b, x, d)),
      "Filter-all" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileFilter_All(false, 4, s, t)(r, b, x, d)),
      "Filter-none" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileFilter_None(false, 4, s, t)(r, b, x, d)),
      "Combine" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileCombine(false, 4, s, t)(r, b, x, d)),
      "Aggregate" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileAggregate(false, 4, s, t)(r, b, x, d)),
      "Rename" -> ((s: Int, t: Int, r: Run[DB], b: SqlExecution, x: Scanner[DB], d: DebugBackend[DB]) => profileRename(false, 4, s, t)(r, b, x, d))
    )

    try {
      testNames.foreach(testname => {
        writer.write(testname + ":")
        // println(testname + ":")
        writer.newLine()

        // header for each DB:
        writer.write(",")
        writer.write(tupleSizes.map(size => size + ",result size").mkString(","))
        writer.newLine()

        profilers.foreach(e => {
          // name of profile test
          writer.write(e._1 + ",")
          // println(e._1)

          val (r, x, b, d) = backends.getOrElse(testname, sys.error("Run/Scanner not found for: " + testname))
          val s = samples.getOrElse(testname, 1)

          // data for each number of tuples
          writer.write(tupleSizes.map(t => {
            val dbStats = e._2(s, t, r, b, x, d)
            dbStats.stats.mean.truncate(2) + "," + dbStats.resultSize
          }).mkString(","))
          writer.newLine()
        })

        writer.newLine()
        writer.newLine()
      })
    }
    finally {
      writer.close()
    }
  }

  def profileAllDBs(sizes: List[Int], filename: String) = {
    import DB._
    import SqlEmitter._
    import DebugBackend._
    profileSuite(
        testNames = List("MySQL", "SQL Server", "Vertica"),
        samples = Map("MySQL" -> 10), // MySQL is local, scale up
        backends = Map("MySQL" -> ((mySqlTestDB,
                                    Backends.MySQL(dummySmenv),
                                    new SqlExecution()(mySqlEmitter),
                                    mySqlDebug)),
                       "SQL Server" -> ((msSqlTestDB,
                                         Backends.MicrosoftSQLServer(dummySmenv),
                                         new SqlExecution()(msSqlEmitter),
                                         msSqlDebug)),
                       "Vertica" -> ((verticaTestDB,
                                      Backends.Vertica(dummySmenv),
                                      new SqlExecution()(verticaSqlEmitter),
                                      verticaDebug))),
        tupleSizes = sizes,
        filename = filename)
  }

  /**
   * Profiles the time needed to scan a relation of the given size
   */
  def profileNoop(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                        (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB]): DBStats = {
    val relation = genRelation(r, backend, tuples, tuples).sample.get.out
    val x = scanner.scanRel(relation, Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, relation)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Join relation, where there is at least one column in common
   */
  def profileJoin_Common(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                       (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB]): DBStats = {
    // val (r1, r2, _) = genJoin(true, r, backend, tuples, tuples).sample.get
    val (r1, r2, _) = getJoin(true, r, backend, tuples)
    val c = Join(r1.out, r2.out)
    val x = scanner.scanRel(c, Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, c, r1.out, r2.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Join relation, where there are no columns in common
   */
  def profileJoin_Cartesian(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                       (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB]): DBStats = {
    // val (r1, r2, _) = genJoin(false, r, backend, tuples, tuples).sample.get
    val (r1, r2, _) = getJoin(false, r, backend, tuples)
    val c = Join(r1.out, r2.out)
    val x = scanner.scanRel(c, Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, c, r1.out, r2.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  // HACK!!! REMOVE THIS ONCE genJoin IS FIXED!!!
  // genJoin occasionally returns None for some reason, so just keep trying until it works
  private def getJoin(common: Boolean, r: Run[DB], backend: SqlExecution, tuples: Int)
                           : (Relation[Nothing, Nothing], Relation[Nothing, Nothing], Option[Header]) = {
    var result: Option[(ClosedRel, ClosedRel, Option[Header])] = None
    while (result == None)
      result = genJoin(common, r, backend, tuples, tuples).sample
    val (a, b, c) = result.get
    (a.out, b.out, c)
  }

  /**
   * Profiles the Union relation
   */
  def profileUnion(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                        (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                        : DBStats = {
    val (r1, r2) = genRelationSameHeader2(r, backend, tuples, tuples).sample.get
    val c = Union(r1.out, r2.out)
    val x = scanner.scanRel(c, Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, c, r1.out, r2.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Minus relation with arbitrary headers and tuples.  Most likely,
   * there will be nothing to subtract.
   */
  def profileMinus_Arbitrary(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                                  (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                                  : DBStats = {
    val (r1, r2) = genRelationSameHeader2(r, backend, tuples, tuples).sample.get
    val c = Minus(r1.out, r2.out)
    val x = scanner.scanRel(c, Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, c, r1.out, r2.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Minus relation with a header complex enough that it is extremely
   * unlikely that there are any rows to subtract.
   */
  def profileMinus_Distinct(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                           (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
      : DBStats = {
    val header: Header = Map("Column1" -> DoubleT(), "Column2" -> DoubleT(), "Column3" -> DoubleT())
    val r1 = genRelationWithHeader(header, r, backend, tuples, tuples).sample.get
    val r2 = genRelationWithHeader(header, r, backend, tuples, tuples).sample.get
    val c = Minus(r1.out, r2.out)
    val x = scanner.scanRel(c, Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, c, r1.out, r2.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Minus relation with a header consisting of two boolean columns,
   * such that there will be a large number of rows to be subtracted
   */
  def profileMinus_Common(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                               (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                               : DBStats = {
    val header: Header = Map("Column1" -> BooleanT(), "Column2" -> BooleanT())
    val r1 = genRelationWithHeader(header, r, backend, tuples, tuples).sample.get
    val r2 = genRelationWithHeader(header, r, backend, tuples, tuples).sample.get
    val c = Minus(r1.out, r2.out)
    val x = scanner.scanRel(c, Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, c, r1.out, r2.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Filter relation with a random relation and predicate
   */
  def profileFilter(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                         (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                         : DBStats = {
    val (relation, predicate) = genRelationPredicateTuple(r,
                                                             backend,
                                                             false,
                                                             RelationGens.NoRelationLevel,
                                                             tuples,
                                                             tuples).sample.get
    val x = scanner.scanRel(Filter(relation.out, predicate), Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, relation.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Filter relation with a predicate that will be false for all rows.
   * The relation contains two Double columns, and the predicate is that they are equal.
   * Since data is randomly generated, it is exceedingly unlikely that this will ever pass.
   */
  def profileFilter_All(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                             (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                             : DBStats = {
    val header: Header = Map("Column1" -> DoubleT(), "Column2" -> DoubleT())
    val relation = genRelationWithHeader(header, r, backend, tuples, tuples).sample.get
    val predicate = Predicate.Eq(Op.ColumnValue("Column1", DoubleT()),
                                 Op.ColumnValue("Column2", DoubleT()))
    val x = scanner.scanRel(Filter(relation.out, predicate), Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, relation.out)(r, backend, scanner, debugSql) { r. run(x) }
  }

  /**
   * Profiles the Filter relation with a predicate that will be true for all rows
   * The relation contains two Double columns, and the predicate is that they are not equal.
   * Since data is randomly generated, it is exceedingly unlikely that this will ever fail.
   */
  def profileFilter_None(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                              (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                              : DBStats = {
    val header: Header = Map("Column1" -> DoubleT(), "Column2" -> DoubleT())
    val relation = genRelationWithHeader(header, r, backend, tuples, tuples).sample.get
    val predicate = Predicate.Not(Predicate.Eq(Op.ColumnValue("Column1", DoubleT()),
                                               Op.ColumnValue("Column2", DoubleT())))
    val x = scanner.scanRel(Filter(relation.out, predicate), Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, relation.out)(r, backend, scanner, debugSql) { r. run(x) }
  }

  /**
   * Profiles the Combine relation, using a random header and an appropriate combine
   * function
   */
  def profileCombine(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                          (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                          : DBStats = {
    // something's not right with this...
    // val (relation, op, t) = genCombineTuple(r, backend).sample.get
    // val x = scanner.scanRel(Combine(relation, Attribute("Combined", t), op), Process(_ => 1))
    // profileAndDrop(burn, numTrials, samples, relation)(r, backend) { r.run(x) }

    val header: Header = Map("Column1" -> IntT(), "Column2" -> IntT())
    val relation = genRelationWithHeader(header, r, backend, tuples, tuples).sample.get
    val x = scanner.scanRel(Combine(relation.out, Attribute("Combined", IntT()),
                                 Op.Add(Op.ColumnValue("Column1", DoubleT()),
                                        Op.ColumnValue("Column2", DoubleT()))),
                         Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, relation.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Aggregate relation, using a random header and an appropriate
   * aggregation function
   */
  def profileAggregate(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                            (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                            : DBStats = {
    val (relation, func, t) = genAggregateTuple(r, backend).sample.get
    val x = scanner.scanRel(Aggregate(relation.out, Attribute("Aggregated", t), func), Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, relation.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  /**
   * Profiles the Rename relation
   */
  def profileRename(burn: Boolean, numTrials: Int, samples: Int, tuples: Int)
                         (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                         : DBStats = {
    val (relation, column, newname) = genRelationRename(genRelation(r, backend, tuples, tuples)).sample.get
    val x = scanner.scanRel(Rename(relation.out, column, newname), Process(_ => 1))
    profileAndDrop(burn, numTrials, samples, relation.out)(r, backend, scanner, debugSql) { r.run(x) }
  }

  // Profiles the given code block and cleans up the created tables.
  private def profileAndDrop(burn: Boolean, numTrials: Int, samples: Int, relations: Relation[Nothing, Nothing]*)
                                  (r: Run[DB], backend: SqlExecution, scanner: Scanner[DB], debugSql: DebugBackend[DB])
                                  (block: => Int): DBStats = {
    // call simpler function if possible
    val stats = if (samples == 1) profile(burn, numTrials, (), block, r.run(debugSql.flush))
                             else profile(burn, numTrials, samples, (), block, r.run(debugSql.flush))
    val result = DBStats(stats, block, r.run(debugSql.explain(relations(0))))
    relations.foreach(dropTables(_, r, backend))
    result
  }

  // digs the RefIDs out of the given relation and drops the tables
  private def dropTables(relation: Relation[Nothing, Nothing], r: Run[DB], backend: SqlExecution, scanner: Scanner[DB]) : Unit = {
    relation match {
      // a relation may contain multiple refs to the same table, so ignore exceptions
      // about how a table doesn't exist (may have already been dropped)
      case Table(_, refID) => try { r.run(backend.destroy(refID)) } catch { case _ => () }
      case JoinOn(r1, r2, _, _) => { dropTables(r1, r, backend); dropTables(r2, r, backend) }
      case Union(r1, r2) => { dropTables(r1, r, backend); dropTables(r2, r, backend) }
      case Minus(r1, r2) => { dropTables(r1, r, backend); dropTables(r2, r, backend) }
      case Filter(rel, _) => dropTables(rel, r, backend)
      case Project(rel, _) => dropTables(rel, r, backend)
      case Aggregate(rel, _, _) => dropTables(rel, r, backend)
      case Rename(rel, _, _) => dropTables(rel, r, backend)
    }
  }

  import IterV._
  def noopIterV[A]: IterV[A, Option[A]] = {
    def step(s: Input[A]): IterV[A, Option[A]] = {
      s(el = e => Cont(step),
        empty = Cont(step),
        eof = Done(None, EOF[A])
      )
    }
    Cont(step)
  }
} */
