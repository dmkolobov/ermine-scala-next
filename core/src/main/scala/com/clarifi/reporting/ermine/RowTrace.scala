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
 * EVERY record ends with a THREAD ID column (`t0`, `t1`, ... in order of first trace write
 * by that thread), appended by `log` — see `tid` below.  It is LAST so that every reader
 * indexing from the start of a record is unaffected.
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
 *
 * S2 RECORDS (added 2026-09-06 for stage S2 of `tracker/LOOP-MODEL-PLAN.md`, see
 * `tracker/loopmodel/S2-DESIGN.md`).  ONE record per firing of a NO-FALSE-ACCEPTANCE
 * layer, so the L2 replay can see the new refutation sites and Part B's model can
 * mirror them:
 *
 *   rsound  site  loc  kind  detail
 *
 * `kind` is one of
 *   `bare`     -- (i)   `makeConcrete` refused `C != fs` at a BARE definition;
 *                       `detail` is `<var>\t<C>\t<fs>`.
 *   `sat`      -- (ii)  `labelClash` refuted the SATURATED set; `detail` is
 *                       `<label>\t<lhs var>\t<reason>`.
 *   `decide`   -- (iii) the complete per-label decision refuted the live input;
 *                       `detail` is `<label>\t<lhs var>\t<nodes>\t<reason>`.
 *   `env`      -- (iii) the live input needed `SubstEnv` facts; `detail` is
 *                       `<#facts>\t<#opaque bindings skipped>`.
 *   `budget`   -- (iii) the decision returned NO VERDICT; `detail` is
 *                       `<label>\t<cause>\t<reason>`, `cause` being `budget` (a per-label
 *                       or per-solve node cap ran out) or `checkfail` (the fail-safe: a
 *                       total assignment failed its own check).  The two are counted
 *                       apart -- `GenRules.rowSoundBudgetHits` and `rowSoundCheckFails` --
 *                       so a counter named for the budget cannot absorb a propagator bug.
 *                       A no-verdict ALSO prints a one-line warning on stderr naming the
 *                       site, because it is the one condition under which the S2 theorem
 *                       says nothing (S2 review V-8, V-12).
 *   `ok`       -- (iii) the decision RAN and passed; `detail` is
 *                       `<#labels>\t<#partitions>\t<nodes>\t<micros>`.
 * Every one of these is emitted only when the corresponding `GenRules.rowSound*`
 * flag is on AND `-Dermine.rowTrace` is set, so a trace taken at the shipped
 * defaults is unchanged.
 *
 * S4 RECORD (added 2026-09-07 for stage S4, `tracker/loopmodel/S4-CHANGE.md`).  ONE
 * record per FAMILY the written-partition normalisation rewrites, so the model mirror
 * can be diffed against it byte for byte:
 *
 *   tnorm   site  loc  <lhs var>  <fresh carrier>  <(|F|)>
 *
 * `<lhs var>` and `<carrier>` are printed by `solve`'s own `sv` helper
 * (`name + '^' + id`) and `F` by its `st` helper for a `ConcreteRho` (sorted, so the
 * `Set` iteration order does not leak).  It is written immediately after `PQueue.build`
 * and before every check and the loop, so it is the FIRST record of a rewritten
 * segment.  Emitted only when `-Dermine.topNormalise=true` fires on a solve, so a trace
 * taken at the shipped defaults is byte-identical to one taken before S4.
 *
 * and ONE REPLAY record, written by `solveInput` alongside `slbl`/`svar`/`scon`
 * and only under `-Dermine.rowSound.decide`:
 *
 *   senv    site  loc  v<id>  payload
 *
 * the `SubstEnv` binding of one variable the input mentions, in `scon`'s own term
 * language (`v<id>`, `c<i>,<i>` / `C<i>,<i>`, `k<i>`, `o<hash>` for a binding that is
 * not row-shaped).  It exists because `Subst.solve` does NOT `substType` its input
 * and `SubstEnv.types` is long-lived (S1 review Z-6), so the constraints the layer-(iii)
 * decision is really about are the input PLUS these facts -- and a replay that cannot
 * see them cannot reproduce a flags-ON trace.  Emitted HERE rather than from the check
 * itself so that the label and variable tables above already carry anything the facts
 * mention: `term` extends both, and the `slbl`/`svar` blocks are written afterwards.
 * The set of variables walked is the one the input constraints mention, which is
 * exactly `PQueue.build`'s variable set on any segment the model replays (an item that
 * is not a `Part` makes the model skip the segment, and the only variable `build` mints
 * itself is fresh, hence unbound).
 *
 * R3 RECORDS (added 2026-09-07 for stage R3, `tracker/loopmodel/R3-DETERMINED.md`).  TWO
 * new records, and NO existing record is touched -- a trace taken before R3 and one taken
 * after are byte-identical once these two are filtered out.  They carry the verdict of
 * Rose's DETERMINACY CLOSURE (Definition 13, `tracker/lean/Rowpartition/Determined.lean`)
 * and of Ermine's strictly larger closure, so that "how many splices would a determinacy
 * guard license" and "how many published signatures carry an undetermined row existential"
 * are MEASURED rather than guessed.  Nothing in the solver reads them.
 *
 *   detm    site  loc  var  rose  erm  hlhs  hdis  hdup  nU0  nVars  nParts
 *   ramb    site  loc  binding  nEx  nRowEx  nRoseUndet  nErmUndet  nParts  roseUndet  ermUndet
 *
 * `detm` is written by `Subst.reduce` at every splice, immediately after the `splice`
 * record and computed on the SAME state: `cs`, the residual the fold has accumulated, which
 * is the system a determinacy guard would consult, with `U0` the variables of `cs` that the
 * splice's own guard does NOT count as existential (`!(v.ty.ambiguous || es.contains(v))`).
 * `rose`/`erm` say whether the spliced variable is in the respective closure.
 * `hlhs`/`hdis`/`hdup` are the three side conditions of `Rowpartition.splice_entails_iff`,
 * recomputed here so that the two guards can be compared row by row; they are a
 * transcription of the `splice` record's own inline block, and the corpus measurement
 * CHECKS that the two agree on every splice rather than assuming it.
 *
 * `ramb` is written by `Subst.mkSimplified` for every signature it publishes that carries at
 * least one row constraint.  `nEx` is the number of existentials the signature binds,
 * `nRowEx` how many of those the ROW constraints mention (an existential that occurs only in
 * a class constraint is not a row-ambiguity candidate and `ambiguitiesIn` already covers it),
 * and the two counts are how many of those `nRowEx` escape each closure.  `binding` is the
 * name of the binding whose final type this is, empty when the call is not one (the
 * `mkSimplified` inside `subsumeType`, and the intermediate `generalize`s of `App`/`Lam`);
 * it comes from `withBinding` below, which, like `withSite`, is a no-op when tracing is off.
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

  /** D1: emit the LOOP's draw count for each solve as its own `sdraw` record.
    * `-Dermine.rowTrace.draws=true`, DEFAULT OFF, because a new record kind on a trace the
    * model does not produce would break the byte-for-byte L2 differential.  With it on, the
    * gate is a per-solve equality of this count against the model's `drawn - drawn0`, which is
    * the only thing that ties the compiler's budget unit to the model's. */
  val drawRecords: Boolean =
    enabled && System.getProperty("ermine.rowTrace.draws", "false") == "true"

  /** Run `body` with the call site tagged. Returns `body`'s value unchanged. */
  def withSite[A](s: String)(body: => A): A =
    if (!enabled) body
    else {
      val old = site0.get
      site0.set(s)
      try body finally site0.set(old)
    }

  /** The THREAD id column (added 2026-09-04 for stage L4).  Every record ends with it, so a
    * trace written by the PARALLEL loader can be demultiplexed per thread and only then
    * segmented at `sin` boundaries, the way a serialized trace already is.  `log`
    * synchronises per LINE, not per solve, so without a thread id two threads solving at
    * once interleave their records and neither solve can be replayed
    * (`tracker/loopmodel/L2-CORPUS.md` §8: 1,654 of `gu05`'s 54,235 parallel segments hold
    * more than one `solve` record).
    *
    * It is a SMALL DENSE integer handed out on first use rather than `Thread.getId`, so the
    * ids are readable and stable across runs (`t0` is whichever thread traces first) and the
    * column stays narrow on a 500 MB trace.  It is APPENDED, so every reader that indexes
    * from the START of a record is unaffected: `tracker/tools/keptdef-mints.py`,
    * `splitkey-counts.py`, `rowtrace-summary.py` and the Lean `Loop/Replay.lean` parsers all
    * match a fixed prefix and ignore the tail.  `tracker/tools/looptrace-diff.py` strips it
    * before comparing, because the model does not emit one.
    *
    * Cost on the default path: none — `tid` is read inside `log`'s `if (enabled)`. */
  private val nextTid = new java.util.concurrent.atomic.AtomicInteger(0)

  private val tid0 = new ThreadLocal[String] {
    override def initialValue(): String = "t" + nextTid.getAndIncrement()
  }

  def tid: String = tid0.get

  /** R3: the BINDING whose final type is being generalised, for the `ramb` record.  Set by
    * `withBinding` around `inferImplicitBindingTypes`'s per-binding `generalize`, which is
    * the one call that publishes a binding's signature; every other `mkSimplified` call
    * leaves it empty.  Thread-local for the same reason `site0` is, and -- like `withSite`
    * -- it does nothing at all unless tracing is on, so the default path is unchanged. */
  private val binding0 = new ThreadLocal[String] {
    override def initialValue(): String = ""
  }

  def binding: String = binding0.get

  /** Run `body` with the binding name tagged.  Returns `body`'s value unchanged; the
    * argument is by-name, so no name is rendered when tracing is off. */
  def withBinding[A](s: => String)(body: => A): A =
    if (!enabled) body
    else {
      val old = binding0.get
      binding0.set(s)
      try body finally binding0.set(old)
    }

  /** The argument is by-name: nothing is built when tracing is off. */
  def log(record: => String): Unit =
    if (enabled) {
      val line = record + "\t" + tid
      out.synchronized { out.println(line); out.flush() }
    }

  /** One S2 no-false-acceptance record.  Both arguments are by-name, like `log`'s, so
    * nothing is rendered when tracing is off. */
  def rowSound(kind: String, loc: => String, detail: => String): Unit =
    if (enabled) log("rsound\t" + site + "\t" + clean(loc) + "\t" + kind + "\t" + detail)

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
  def solveInput(loc: => String, cs: List[Type], su: Supply,
                 env: Map[TypeVar, Type] = Map()): Unit = if (enabled) {
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

    /* The environment facts, in the input's own vocabulary.  Rendered BEFORE the tables
     * are written so that `term`'s side effect -- numbering a label or a variable the
     * facts mention and nothing else does -- lands in them.  The walk closes over the
     * variables the facts themselves introduce; `instantiateType` keeps `hm.types`
     * idempotent, so one round is normally enough, but the closure does not rely on it. */
    val envRecs =
      if (!Constraints.GenRules.rowSoundDecide) Nil
      else {
        val buf = new scala.collection.mutable.ListBuffer[String]
        var seen = Set[TypeVar]()
        var todo = vars.keysIterator.toList
        while (todo.nonEmpty) {
          val v = todo.head; todo = todo.tail
          if (!seen(v)) {
            seen = seen + v
            env.get(v) match {
              case None    => ()
              case Some(t) =>
                val rhs = term(t)
                buf += ("senv" + tag + "v" + v.id + "\t" + rhs)
                t match { case VarT(u) => todo = u :: todo ; case _ => () }
            }
          }
        }
        buf.toList
      }

    val (suLo, suHi) = supplyBounds(su)
    val (blk, bsz) = supplyBlock()
    /* D1: the dequeue POLICY and the draw BUDGET ride on `sin`, so a policy-on or
     * budget-on trace can be replayed by `looptrace --replay`.  They go BEFORE the
     * thread-id column `log` appends and AFTER every field an older reader knows,
     * and `Loop/Replay.lean` parses `sin` positionally with a trailing wildcard,
     * so old traces keep parsing and new ones stay readable by old tools. */
    log("sin" + tag + suLo + "\t" + suHi + "\t" + cs.length + "\t" + blk + "\t" + bsz +
        "\t" + cs.flatMap(_.rowConstraints).length +
        "\t" + Constraints.GenRules.dequeuePolicy +
        /* the EFFECTIVE budget (0 under the shipped order, where the flag is
         * ignored), so a replay applies exactly the cap this run applied. */
        "\t" + Constraints.GenRules.solveBudget +
        /* S4 (2026-09-07, S4B review H-4): the written-partition normalisation, for the
         * same reason the two columns above are here -- a replay must apply the
         * CONFIGURATION the trace was taken under, not the one its own command line
         * happens to carry.  Without it an ON trace replayed without `--flags=topnorm`
         * diverges instead of reproducing, which is loud but is exactly the failure mode
         * that hid two missing mirror call sites.  `Loop/Replay.lean` parses `sin`
         * positionally with a trailing wildcard, so old traces keep parsing. */
        "\t" + Constraints.GenRules.topNormalise)
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
    envRecs.foreach(log(_))
  }
}
