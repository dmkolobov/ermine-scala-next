package com.clarifi.reporting
package ermine

/**
 * Stage 0 instrumentation for tracker/TICKET-row-constraint-decision.md.
 *
 * INERT unless `-Dermine.rowTrace=<path>` is passed. When the property is
 * absent, `enabled` is false, every `log` call is a single boolean test on a
 * by-name argument that is never forced, and no file is opened. Nothing here
 * may change the compiler's behaviour in either mode: it observes and prints.
 *
 * WHY IT EXISTS. Every drift figure anyone has quoted about the row solver —
 * including the ones in this repo's own ticket — was computed from EMITTED
 * RESIDUALS (`tracker/g1-baseline/ei`, `browse.txt`). That is the wrong
 * population twice over: two thirds of the constrained signatures are
 * annotations that `solve` never sees, and `reduce`'s second case splices
 * partitions drawn from the SATURATED queue into the committed output, so the
 * residual is not a function of `solve`'s input alone. This log records what
 * `solve` actually receives and what `reduce` actually commits.
 *
 * FORMAT. One tab-separated record per line, first field a record type:
 *
 *   solve   site  loc  nIn  nParts  nSat  nDerived  concrete  arities  byRule
 *   concr   site  loc  var  fields  prov
 *   splice  site  loc  var  nAbs  con  prov  changed
 *
 * `prov` is the `Inference` that derived a partition, or `INPUT` when
 * `Partition.inf` is `None` — which is precisely how an input partition is
 * distinguished from a derived one, since `PQueue.build` uses the two-argument
 * `Partition(v, rhs)` constructor and every rule supplies an `Inference`.
 */
object RowTrace {
  private val path: String = System.getProperty("ermine.rowTrace", "")

  /** True iff `-Dermine.rowTrace=<path>` was given. */
  val enabled: Boolean = path.nonEmpty

  private lazy val out: java.io.PrintWriter =
    new java.io.PrintWriter(new java.io.BufferedWriter(new java.io.FileWriter(path, true)))

  /** The current `solve` call site, so records can be attributed. Set by
   *  `withSite`; the solver is single-threaded per session but the field is
   *  thread-local so a parallel load cannot interleave attributions. */
  private val site0 = new ThreadLocal[String] {
    override def initialValue(): String = "?"
  }

  def site: String = site0.get

  /** Run `body` with the call site tagged. Returns `body`'s value unchanged. */
  def withSite[A](s: String)(body: => A): A =
    if (!enabled) body
    else {
      val old = site0.get
      site0.set(s)
      try body finally site0.set(old)
    }

  /** The argument is by-name: nothing is built when tracing is off. */
  def log(record: => String): Unit =
    if (enabled) out.synchronized { out.println(record); out.flush() }

  /** Escape tabs and newlines so a record stays on one line. */
  def clean(s: String): String =
    s.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')
}
