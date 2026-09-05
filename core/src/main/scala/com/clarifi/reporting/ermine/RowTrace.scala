package com.clarifi.reporting
package ermine

import scalaparsers.Supply
import com.clarifi.reporting.ermine.Type.Con

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
 *
 * REPLAY RECORDS (added 2026-09-04 for stage L2 of `tracker/LOOP-MODEL-PLAN.md`).
 * The records above describe what `solve` DID; these four describe what it was
 * GIVEN, which is exactly what `lake exe looptrace --replay` needs to re-run the
 * same solve in the Lean loop model and produce the same `step` / `learn` /
 * `inpart` / `sat` / `solve` records.  They are written by `RowTrace.solveInput`,
 * called once at the top of `Subst.solve` (after `unbindExists`, before
 * `PQueue.build`), and, like everything else here, they are inert unless
 * `-Dermine.rowTrace` is set.
 *
 *   sin     site  loc  suLo  suHi  nCs  blk  bsz  nRows
 *   slbl    site  loc  idx   kind  con  module  string
 *   svar    site  loc  id    ty    name
 *   scon    site  loc  i     eqid  hash  kind  payload
 *
 * `sin` OPENS a solve segment: it is the one record written before the solve does
 * anything, so a trace taken with `-Dermine.loadInSeries=true` splits into solves at
 * `sin` boundaries even when a solve DIES and writes no `solve` line.  `suLo`/`suHi`
 * are the `Supply`'s bounds at that moment, read reflectively and never written, so
 * the compiler draws exactly the ids it would have drawn without the property.
 * `suLo` is the first id `PQueue.build` and the loop will mint, and the model needs
 * it because `V.hashCode` IS the id and the queue is ordered by hash.  `blk` and `bsz`
 * are `Supply.block` — the GLOBAL block counter — and `Supply.blockSize`, because a
 * `Supply` whose own block runs out mid-solve does NOT continue at `hi + 1`: it calls
 * `getBlock` and jumps to wherever that counter stands.  With those two the model can
 * follow `Supply.fresh` across a block boundary instead of guessing (677 of the `Ai`
 * corpus's 83 942 solves start with fewer than ten ids left in their block, and two of
 * them cross it while minting).  `nRows` is `cs.flatMap(_.rowConstraints).length`, the
 * number of `in` records the solve is about to write: it lets the model CHECK that the
 * `part` elements below really are the row constraints rather than assume it.
 *
 * `slbl` is this solve's label table: every `Name` a `ConcreteRho` or a `Con` in the
 * input mentions, numbered in order of first appearance.  `kind` is `G` for a
 * `Global` and `L` for a `Local`; `con` is `fixity.con`.  All four fields are needed
 * because `Name.hashCode` is `(2, module, string, fixity.con).hashCode`
 * (`Name.scala:39`) and the `Set` iteration order that decides both the queue order
 * and the printed rows is a function of it — `toString` alone does not determine it,
 * since `Prefix`, `Infix` and `Postfix` all print `module.(string)` and two of them
 * share a `con`.
 *
 * `svar` is the variable table: every `TypeVar` the input mentions, with the
 * `VarType` that `Partition.toString` prints (`'^' + ty.toString.toLowerCase + id`)
 * and the `V.name` that the `in`/`inpart`/`sat` records print (empty field =
 * `V.name` is `None`).  `ty` cannot be inferred from the id in real code; that
 * assumption is the L1 model's `Names.pvar`, which the L1 review (F7) named L2's
 * blocker.
 *
 * `scon` is one element of the constraint list `PQueue.build` receives, in the
 * list's order.  `eqid` is the index of the FIRST element of the list this one is
 * `equals` to, and `hash` is its `hashCode`: `Exists.apply` puts the list through
 * `p.toSet.toList`, so the order the solver actually sees is decided by exactly those
 * two, and recording them lets the model reproduce it without modelling constraint
 * forms the solver never looks at.  `kind` is `part` for a `Part` — the only shape
 * `PQueue.build`'s `aux` turns into partitions — `exists` for a nested `Exists`, and
 * otherwise the class's simple name.  A `part`'s `payload` is `lhs|rhs1|rhs2|...`,
 * one term per field:
 *
 *     v<id>              a `VarT`
 *     c<i>,<i>,...       a `ConcreteRho`, its fields as label-table indices IN
 *                        ITERATION ORDER (which `in` and `inpart` sort away, and
 *                        which `Partition.toString` prints raw).  `C` instead of `c`
 *                        when the field set is an `immutable.HashSet` rather than a
 *                        `SetN` — the size does not determine that.
 *     k<i>               a `Con`, its name as a label-table index
 *     o<hashCode>        anything else (`RHS.build` dies on it)
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

  /** A `Supply`'s `(lo, hi)`: `lo` is the next id it hands out, `hi` the last id of its
    * current block (`Supply.fresh` takes a NEW block when `lo == hi`, so a replay is
    * contiguous from `lo` exactly while it stays below `hi`).  Both fields are `private`
    * (`parsers/src/main/scala/scalaparsers/Supply.scala:20`), so this reads them
    * reflectively rather than widening their visibility.  It is a READ: it takes no id and
    * changes nothing, which is why the compiler still draws exactly the same ids with
    * `-Dermine.rowTrace` set.  `(-1, -1)` if reflection is refused.
    * `tracker/repro/satterm/SatTermRepro.scala`'s `drawnOf` reads `lo` the same way. */
  /** `Supply.block` and `Supply.blockSize`: the GLOBAL block counter `Supply.fresh` calls
    * `getBlock` for when its own block runs out, and the size of a block.  Both are
    * `private` on the `Supply` companion.  READ, never called: invoking `getBlock` would
    * CONSUME a block and change the ids the compiler hands out.  `(-1, -1)` if reflection
    * is refused. */
  def supplyBlock(): (Int, Int) =
    try {
      val cls = Class.forName("scalaparsers.Supply$")
      val fb = cls.getDeclaredField("block"); fb.setAccessible(true)
      val fs = cls.getDeclaredField("blockSize"); fs.setAccessible(true)
      (fb.getInt(null), fs.getInt(null))
    } catch { case _: Throwable => (-1, -1) }

  def supplyBounds(su: Supply): (Int, Int) =
    try {
      val fl = classOf[Supply].getDeclaredField("lo"); fl.setAccessible(true)
      val fh = classOf[Supply].getDeclaredField("hi"); fh.setAccessible(true)
      (fl.getInt(su), fh.getInt(su))
    } catch { case _: Throwable => (-1, -1) }

  /** The replay records — `sin`, `slbl`, `svar`, `scon` — for ONE `Subst.solve`, written
    * before the solve does anything.  See the FORMAT block above.  This reads its
    * arguments and writes lines; it does not touch the `Supply` and builds no `Type`.
    * `loc` is by-name, like `log`'s argument, so a traced-off build renders no location. */
  def solveInput(loc: => String, cs: List[Type], su: Supply): Unit = if (enabled) {
    val tag = "\t" + site + "\t" + clean(loc) + "\t"

    /* Label table and variable table, both in order of FIRST APPEARANCE, filled while the
     * constraint payloads are rendered — left to right, lhs before rhs, which is the order
     * `RHS.build` folds. */
    val lbls = new scala.collection.mutable.LinkedHashMap[Name, Int]
    val vars = new scala.collection.mutable.LinkedHashMap[TypeVar, Unit]
    def lbl(n: Name): Int = lbls.getOrElseUpdate(n, lbls.size)
    def term(t: Type): String = t match {
      case VarT(v)            => vars.getOrElseUpdate(v, ()); "v" + v.id
      case ConcreteRho(_, fs) =>
        // `C` when the field set is an `immutable.HashSet` and `c` when it is a `SetN`.
        // The two iterate differently, and a `HashSet` that has shrunk below five is
        // still a `HashSet`, so the representation cannot be read off the size and the
        // model would otherwise have to guess it.
        (if (fs.isInstanceOf[scala.collection.immutable.HashSet[_]]) "C" else "c") +
          fs.toList.map(n => lbl(n).toString).mkString(",")
      case Con(_, n, _, _)    => "k" + lbl(n)
      case x                  => "o" + x.hashCode
    }
    val payload = cs.map {
      case p: Part   => "part\t" + term(p.lhs) + "|" + p.rhs.map(term).mkString("|")
      case e: Exists => "exists\t" + e.xs.length + ";" + e.constraints.length
      case x         => "other\t" + x.getClass.getSimpleName
    }

    /* `Exists.apply`'s `p.toSet.toList` reorders the list by `hashCode` and dedups by
     * `equals`.  Recording, per element, the index of the first element it is equal to and
     * its hash is exactly what a replay needs, and nothing more. */
    val firstEq = new scala.collection.mutable.HashMap[Type, Int]
    val eqid = cs.zipWithIndex.map { case (t, i) => firstEq.getOrElseUpdate(t, i) }

    val (suLo, suHi) = supplyBounds(su)
    val (blk, bsz) = supplyBlock()
    log("sin" + tag + suLo + "\t" + suHi + "\t" + cs.length + "\t" + blk + "\t" + bsz +
        "\t" + cs.flatMap(_.rowConstraints).length)
    lbls.foreach { case (n, i) =>
      val (kind, module) = n match {
        case g: Global => ("G", g.module)
        case _         => ("L", "")
      }
      log("slbl" + tag + i + "\t" + kind + "\t" + n.fixity.con + "\t" +
          clean(module) + "\t" + clean(n.string))
    }
    vars.keysIterator.foreach { v =>
      log("svar" + tag + v.id + "\t" + v.ty.toString + "\t" +
          clean(v.name.fold("")(_.toString)))
    }
    payload.zip(eqid).zip(cs).zipWithIndex.foreach { case (((p, e), t), i) =>
      log("scon" + tag + i + "\t" + e + "\t" + t.hashCode + "\t" + p)
    }
  }
}
