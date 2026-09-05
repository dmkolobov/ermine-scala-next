package com.clarifi.reporting
package ermine
package loopmodel

import scalaparsers.{Loc, Located, Supply}

/** The COMPILER side of the L4 trace property, run in a CHILD JVM.
  *
  * WHY A CHILD JVM.  `RowTrace.enabled` is `System.getProperty("ermine.rowTrace").nonEmpty`
  * read once into a `val`, and `core`'s tests run with `Test / fork := false` (build.sbt), so
  * the property cannot turn tracing on inside sbt's JVM: by the time a test runs, `RowTrace`
  * may already be initialised by another suite, and if it is not, setting the property would
  * turn the trace on for EVERY solve in the whole `core/test` run -- `TestConstraints` alone
  * performs thousands -- appending them all to one file and slowing the suite down.  The
  * alternative, making `enabled` a `def` or adding a settable switch, would put a live
  * property read (or a volatile field) on the solver's default path, which the instrumentation
  * is explicitly not allowed to do.  So the trace is taken by a second JVM, launched with
  * `-Dermine.rowTrace=<file>` and the classpath the test itself is running under, and the
  * parent compares the file it writes with the Lean model's replay of it.
  *
  * WHAT IT DOES.  Reads a job file -- one solve per line, in the wire format below -- and runs
  * each through the REAL `Subst.solve` (`Constraints.incorporateAll` and everything under it)
  * on a fresh `SubstEnv` at an exact id base, exactly as `tracker/repro/satterm/SatTermRepro.scala`
  * does, with no stdlib boot and no module loading.  Every solve runs on the MAIN thread, in
  * order, so the trace is the serialized one the segmenter expects.  A solve that dies is
  * caught and reported on stdout: the compiler's trace of a died solve is still a segment the
  * model must reproduce (it writes no `solve` record, and `looptrace --replay` answers
  * `#REJECTED`), so a death is data, not an error.
  *
  * WIRE FORMAT, one job per line, tab separated:
  *
  *     <site>  <base>  <v0,v1,...>  <lhs|g1,g2|k1,k2 ; lhs|g|k ; ...>
  *
  * `site` is the `RowTrace` site tag, which becomes the second column of every record the job
  * writes.  The third field lists the seed's variable indices in ascending order; index `vi`
  * gets the id `base + i`, and the `Supply` starts at `base + n`, which is exactly
  * `SatTermRepro.system`'s convention (and hence the ids every tracked seed was traced at in
  * L1 and L2).  Each constraint is `lhs|group|labels`: `lhs` and the group are variable
  * indices, the labels are label numbers `n` standing for `Global("Repro", "l" + n)`, and an
  * empty label list means the right-hand side has NO concrete part rather than an empty one.
  * `Part` is built with `new Part(...)` and `Exists` with `new Exists(...)`, bypassing both
  * smart constructors, so the list order `solve` receives is exactly the one written here.
  */
object LoopTraceChild {

  /** A `Supply` starting at `lo`.  Its constructor is private (`Supply.scala`), so this
    * reflects, as `SatTermRepro`/`tracker/repro/nameloss/Replay.scala` already do. The block
    * is deliberately wide (100 000) so a job never crosses a block boundary by accident;
    * `RowTrace`'s `sin` record carries `lo`, `hi`, `block` and `blockSize` either way. */
  def supplyAt(lo: Int): Supply = {
    val c = classOf[Supply].getDeclaredConstructors.head
    c.setAccessible(true)
    c.newInstance(Integer.valueOf(lo), Integer.valueOf(lo + 100000)).asInstanceOf[Supply]
  }

  def label(n: Int): Name = Global("Repro", "l" + n)

  def tv(id: Int, name: String): TypeVar =
    V(Loc.builtin, id, Some(Local(name)), Free, Rho(Loc.builtin))

  /** One job: the constraint list at this base, and the id the `Supply` starts at. */
  def build(varIds: List[Int], cons: List[(Int, List[Int], List[Int])], base: Int)
      : (List[Type], Int) = {
    val ids = varIds.zipWithIndex.map { case (v, i) => v -> tv(base + i, "v" + v) }.toMap
    def vt(v: Int): Type = VarT(ids(v))
    val parts = cons.map { case (lhs, grp, ks) =>
      val rhs = grp.map(vt) ++ (if (ks.isEmpty) Nil
                                else List(ConcreteRho(Loc.builtin, ks.map(label).toSet)))
      new Part(Loc.builtin, vt(lhs), rhs): Type
    }
    (parts, base + varIds.length)
  }

  /** `<lhs>|<g,g>|<k,k> ; ...` back into constraints. */
  def parseCons(s: String): List[(Int, List[Int], List[Int])] = {
    def ints(x: String): List[Int] =
      x.split(",").iterator.map(_.trim).filter(_.nonEmpty).map(_.toInt).toList
    s.split(";").iterator.map(_.trim).filter(_.nonEmpty).map { c =>
      val f = c.split("\\|", -1)
      (f(0).trim.toInt, ints(f.lift(1).getOrElse("")), ints(f.lift(2).getOrElse("")))
    }.toList
  }

  def main(args: Array[String]): Unit = {
    if (!RowTrace.enabled) {
      System.err.println("LoopTraceChild: needs -Dermine.rowTrace=<file>")
      System.exit(2)
    }
    if (args.length != 1) {
      System.err.println("usage: LoopTraceChild <jobfile>")
      System.exit(2)
    }
    val src = scala.io.Source.fromFile(args(0))
    val jobs = try src.getLines().filter(_.nonEmpty).toList finally src.close()
    var solved = 0
    var died = 0
    jobs.foreach { ln =>
      val f = ln.split("\t", -1)
      val site = f(0)
      val base = f(1).toInt
      val varIds = f(2).split(",").iterator.filter(_.nonEmpty).map(_.toInt).toList
      val (parts, supplyLo) = build(varIds, parseCons(f(3)), base)
      implicit val hm: SubstEnv = new SubstEnv()
      implicit val su: Supply = supplyAt(supplyLo)
      implicit val tml: Located = Loc.builtin
      val ex: Type = new Exists(Loc.builtin, List(), parts)
      try {
        RowTrace.withSite(site)(Subst.solve(ex))
        solved += 1
      } catch {
        case e: Throwable =>
          died += 1
          println("DIED\t" + site + "\t" + e.getClass.getName + "\t" +
                  String.valueOf(e.getMessage).replace('\n', ' ').take(160))
      }
    }
    println("JOBS\t" + jobs.length + "\tsolved=" + solved + "\tdied=" + died)
  }
}
