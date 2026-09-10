package com.clarifi.reporting.ermine.session

/** LSP Stage 4, item 7.0: DIRECT MEASUREMENT of the editor read's phases.
  *
  * Not a profiler and not a sample share -- `System.nanoTime` around each
  * phase of one check, accumulated by name and reported once per check.
  * PERF-ROADMAP P5(a) is the reason this exists: JFR over-attributed one
  * pass by 3.5x, and every share in that roadmap is an upper bound.
  *
  * OFF unless `-Dermine.lsp.phases=true`, and "off" is one boolean field
  * read per call site: no clock call, no allocation (nothing here takes a
  * by-name argument, so a disabled site does not even build a closure),
  * no map touched, no behaviour of any kind.  That matters because two of
  * the timed sites -- `NewPipeline.read` and `TolerantCheck.keys` -- are
  * shared with the STRICT batch reader, which never sets the property.
  *
  * The report goes to the LSP log, never to stdout (roadmap Decision 4:
  * stdout is the protocol channel).  `Diagnostics.run` emits it and then
  * resets, so each line is one check's own numbers -- including the `Rpc`
  * frame/JSON timings of the `didChange` that triggered it, which are
  * recorded before the check starts and after the previous reset.
  */
object Phases {

  val enabled: Boolean = "true" == System.getProperty("ermine.lsp.phases")

  // Insertion-ordered, so the emitted line reads in pipeline order.
  // `synchronized` only ever runs with the property on; the editor path is
  // single-threaded (Decision 3) but the loader is not, and a batch JVM
  // that opted in must not corrupt the map.
  private val acc = scala.collection.mutable.LinkedHashMap.empty[String, Long]
  // Plain integers (byte counts, item counts) rendered as-is beside the times.
  private val counts = scala.collection.mutable.LinkedHashMap.empty[String, Long]

  /** `System.nanoTime`, or 0 when off. */
  def now: Long = if (enabled) System.nanoTime else 0L

  /** Attribute the elapsed time since `startNs` (from `now`) to `name`. */
  def add(name: String, startNs: Long): Unit =
    if (enabled) record(name, System.nanoTime - startNs)

  def record(name: String, ns: Long): Unit =
    if (enabled) synchronized { acc(name) = acc.getOrElse(name, 0L) + ns }

  /** A non-time quantity, reported beside the times. */
  def count(name: String, n: Long): Unit =
    if (enabled) synchronized { counts(name) = counts.getOrElse(name, 0L) + n }

  def reset(): Unit = if (enabled) synchronized { acc.clear(); counts.clear() }

  /** `name=ms` pairs in first-touch order (milliseconds to 3 places),
    * then the plain counts. */
  def render: String = synchronized {
    (acc.iterator.map { case (k, ns) => f"$k=${ns / 1e6}%.3f" } ++
     counts.iterator.map { case (k, n) => k + "=" + n }).mkString(" ")
  }
}
