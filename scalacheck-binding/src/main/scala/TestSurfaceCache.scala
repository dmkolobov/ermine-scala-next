package com.clarifi.reporting

import com.clarifi.reporting.ermine.surface.{ SModule, StatementExtents, SurfaceCache, SurfaceParsers }

import org.scalacheck._
import Prop._

import java.io.File

/** LSP Stage 4 item 7.1b -- THE STATEMENT-EXTENT SURFACE CACHE, against
  * its oracle.
  *
  * THE INVARIANT (Stage-4, hard): A REUSED SURFACE TREE MUST BE
  * BYTE-FOR-BYTE WHAT A FRESH PARSE WOULD GIVE.  So the property is a
  * DIFFERENTIAL: over the corpus, for a generated SEQUENCE of edits per
  * file -- a character, a line, a whole statement; at the top, the middle
  * and the end; one that MERGES two statements and one that SPLITS one; one
  * in the trivia a statement's lookahead reaches into; one inside a
  * `private`/`database` block; one to an item 7.2 calls UNREACHABLE -- the
  * module `SurfaceParsers.moduleCached` splices must equal, structurally and
  * SPAN FOR SPAN, the module `moduleMarked` parses from scratch, at EVERY
  * step.  Multi-edit, not single-edit: swift-syntax #3397 is invisible to a
  * single-edit test, which is why each edit is applied to the text the
  * previous one produced and the cache is carried across the whole sequence.
  *
  * THE SAMPLE.  The full 253-file corpus takes about three minutes (every
  * step parses the file twice, once as the oracle), so the shipped property
  * runs a deterministic sample -- every fourth file plus `Layout/Report.e`,
  * the 77 KB file the perf target is -- and the whole corpus runs under
  * `-Dermine.test.surfacecache.full=true`.  The sample is not random per
  * run: a differential that tests a different thing every time cannot be
  * bisected.
  *
  * ANTI-VACUITY is asserted, not assumed: a cache that reuses NOTHING would
  * pass a differential trivially, so the property floors the hit count and
  * the per-step reuse of an in-body edit, and three further properties pin
  * the parts a corpus sweep cannot see -- that the guard REFUSES the reuse
  * Lean's counterexample must refuse, that a reused entry carries ITS OWN
  * mark forward rather than acquiring the reusing parse's, and that a line
  * shift moves every span by exactly the shift.
  */
object TestSurfaceCache extends Properties("Surface cache") {

  // ------------------------------------------------------------- corpus

  private val notGoodCode = Set("shouldfail", "shouldfail-controls", "incomplete")

  private def walk(f: File): List[File] =
    if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
    else if (f.getName endsWith ".e") List(f) else Nil

  private def corpus: List[File] =
    (walk(new File("core/src/main/resources/modules")) ++ walk(new File("core/examples")))
      .filterNot(f => Option(f.getParentFile).exists(d => notGoodCode(d.getName)))

  private def slurp(f: File): String =
    new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")

  private def sample: List[File] = {
    val all = corpus
    if (java.lang.Boolean.getBoolean("ermine.test.surfacecache.full")) all
    else {
      val every = all.zipWithIndex.collect { case (f, i) if i % 4 == 0 => f }
      val report = all.filter(_.getPath.endsWith("Report.e"))
      (every ++ report).distinct
    }
  }

  // --------------------------------------------------------- edit shapes

  private final case class Edit(label: String, text: String)

  private def stmts(text: String): List[StatementExtents.Extent] =
    StatementExtents.scan(text).items
      .filterNot(x => x.headWord == "import" || x.headWord == "export")

  private def offs(text: String) = new StatementExtents.Offsets(text)

  private def splice(text: String, at: Int, drop: Int, ins: String): String =
    text.substring(0, at) + ins + text.substring(math.min(text.length, at + drop))

  /** `TolerantCheck`'s reachability rule, restated here so the sequence can
    * aim an edit at an item that has no key of its own (7.2's R-1 class). */
  private def reachable(x: StatementExtents.Extent, t: String): Boolean = {
    var k = 0
    while (k < t.length && { val c = t.charAt(k)
             c.isLetter || c.isDigit || c == '_' || c == '#' || c == '\'' }) k += 1
    x.headWord.nonEmpty && x.headWord == t.substring(0, k)
  }

  private def sequence(src: String, rnd: scala.util.Random): List[Edit] = {
    val out = List.newBuilder[Edit]
    var text = src
    def emit(label: String, t: String): Unit =
      if (t != text) { text = t; out += Edit(label, t) }
    def xs = stmts(text)

    xs.headOption.foreach { x =>                       // a character, at the top
      val o = offs(text)
      val a = o.offsetOf(x.startLine, x.startCol)
      val b = o.offsetOf(x.endLine, x.endCol)
      if (b > a + 1) emit("char-insert-top", splice(text, b - 1, 0, " "))
    }
    { val ys = xs                                      // a character, in the middle
      if (ys.size > 2) {
        val b = offs(text).offsetOf(ys(ys.size / 2).endLine, ys(ys.size / 2).endCol)
        emit("char-delete-mid", splice(text, b - 1, 1, ""))
      } }
    xs.headOption.foreach { x =>                       // a LINE at the top: the shift
      emit("line-insert-top", splice(text, offs(text).offsetOf(x.startLine, 1), 0, "\n"))
    }
    { val ys = xs                                      // a whole STATEMENT
      if (ys.size > 2) {
        val a = offs(text).offsetOf(ys(ys.size / 2).startLine, 1)
        emit("stmt-insert", splice(text, a, 0, "zzq71b = 1\n\n"))
      } }
    { val i = text.indexOf("zzq71b = 1\n\n")            // and away again
      if (i >= 0) emit("stmt-delete", splice(text, i, "zzq71b = 1\n\n".length, "")) }
    { val ys = xs                                      // the LOOKAHEAD region
      val o = offs(text)
      val gaps = ys.sliding(2).collect { case List(a, b) =>
        (o.offsetOf(a.endLine, a.endCol), o.offsetOf(b.startLine, b.startCol)) }
        .filter { case (e, s) => s - e > 1 }.toList
      if (gaps.nonEmpty) emit("trivia-comment", splice(text, gaps(rnd.nextInt(gaps.size))._1, 0,
                                                       "  -- 7.1b\n")) }
    { val ys = xs                                      // MERGE two statements
      if (ys.size > 3) {
        val x = ys(1 + rnd.nextInt(ys.size - 2))
        emit("merge", splice(text, offs(text).offsetOf(x.startLine, 1), 0, "  "))
      } }
    { val cand = xs.filter(x => x.endLine > x.startLine)   // SPLIT one
      if (cand.nonEmpty) {
        val x = cand(rnd.nextInt(cand.size))
        val a = offs(text).offsetOf(x.startLine + 1, 1)
        var k = a
        while (k < text.length && (text.charAt(k) == ' ' || text.charAt(k) == '\t')) k += 1
        if (k > a) emit("split", splice(text, a, k - a, ""))
      } }
    { val cand = xs.filter(x => x.headWord == "private" || x.headWord == "database")
      if (cand.nonEmpty) {                              // inside a private block
        val x = cand(rnd.nextInt(cand.size))
        val b = offs(text).offsetOf(x.endLine, x.endCol)
        emit("block-edit", splice(text, b - 1, 0, " "))
      } }
    { val o = offs(text)                                // an UNREACHABLE item
      val cand = xs.filterNot(x => reachable(x, o.text(x)))
      if (cand.nonEmpty) {
        val x = cand(rnd.nextInt(cand.size))
        emit("unreachable-edit", splice(text, o.offsetOf(x.endLine, x.endCol) - 1, 0, " "))
      } }
    xs.lastOption.foreach { x =>                        // the END of the file
      emit("end-edit", splice(text, offs(text).offsetOf(x.endLine, x.endCol), 0, " "))
    }
    emit("revert", src)                                 // and all the way back
    out.result()
  }

  private def firstDiff(a: SModule, b: SModule): String =
    if (a.header != b.header) "header: " + a.header.toString.take(200) + " vs " +
                              b.header.toString.take(200)
    else if (a.statements.size != b.statements.size)
      "statement count " + a.statements.size + " vs " + b.statements.size
    else a.statements.zip(b.statements).zipWithIndex.collectFirst {
      case ((x, y), i) if x != y => "statement #" + i + " at line " + y.loc.span.startLine +
        "\n  spliced " + x.toString.take(400) + "\n  fresh   " + y.toString.take(400)
    }.getOrElse("<equal>")

  // ------------------------------------------------- (i) the differential

  property("a spliced module equals a fresh parse, at every step of an edit sequence") = secure {
    val files = sample
    val bad = List.newBuilder[String]
    var steps = 0
    var hits = 0L
    var misses = 0L
    var inBodyReuse = 0.0
    var inBodySteps = 0
    files.foreach { f =>
      val src = slurp(f)
      val name = f.getName.stripSuffix(".e")
      val rnd = new scala.util.Random(71L * 31 + f.getPath.hashCode)
      var cache: Option[SurfaceCache.Cache] = None
      (Edit("cold", src) :: sequence(src, rnd)).foreach { ed =>
        steps += 1
        val fresh = SurfaceParsers.moduleMarked(f.getPath, ed.text, name)
        val spl   = SurfaceParsers.moduleCached(f.getPath, ed.text, name, cache)
        (fresh, spl) match {
          case (Right((fm, _)), Right((sm, _, c))) =>
            cache = Some(c)
            hits += c.hits; misses += c.misses
            if (ed.label == "char-insert-top" && c.statements > 4) {
              inBodyReuse += c.hits.toDouble / c.statements; inBodySteps += 1
            }
            if (fm != sm) bad += (f.getPath + " [" + ed.label + "] " + firstDiff(sm, fm))
            // the reported reuse pair must BE the file's statements: the
            // driver's last `sepEndBy` iteration can parse a statement it
            // then rolls back, and a count that included it would overstate
            // the cache on exactly the files where it happens
            if (c.statements != fm.statements.size)
              bad += (f.getPath + " [" + ed.label + "] counted " + c.statements +
                      " statements, the parse produced " + fm.statements.size)
          case (Left(a), Left(b)) =>
            cache = None
            if (a.pretty.toString != b.pretty.toString)
              bad += (f.getPath + " [" + ed.label + "] refusals differ: " +
                      b.pretty.toString.take(200) + " vs " + a.pretty.toString.take(200))
          case (x, y) =>
            cache = None
            bad += (f.getPath + " [" + ed.label + "] one side refused: fresh=" +
                    x.isRight + " spliced=" + y.isRight)
        }
      }
    }
    val errs = bad.result()
    ((files.size >= 60) :| ("only " + files.size + " files sampled")) &&
    ((steps >= 600) :| ("only " + steps + " steps")) &&
    ((errs.isEmpty) :| ("mismatches: " + errs.take(3).mkString("\n"))) &&
    // ANTI-VACUITY: a cache that never hits would pass everything above
    // the floor is deliberately BELOW the measured ratio (2.6 : 1 on the
    // sample, 2.2 : 1 over the whole corpus): two of the twelve steps --
    // the cold open and the revert-through-every-edit -- are all-miss by
    // construction, and the sharper floor is the in-body one below
    ((hits > 2 * misses) :| ("reuse too low: " + hits + " hits, " + misses + " misses")) &&
    ((inBodySteps > 20 && inBodyReuse / inBodySteps > 0.8) :|
      ("a one-character body edit reused only " +
       (if (inBodySteps == 0) 0.0 else inBodyReuse / inBodySteps) + " of the file"))
  }

  // ------------------------------------------ (ii) the guard is load-bearing

  /** LEAN'S COUNTEREXAMPLE, which is 7.1a property (iii) seen from the
    * cache's side: the edit is strictly AFTER the first statement's text,
    * and it changes the first statement anyway (the offside rule makes the
    * indented line a continuation).  Byte-equality of the extent would reuse
    * it; the high-water mark is what refuses.  The property requires BOTH
    * the refusal and the agreement, so removing the guard fails it. */
  property("the guard refuses a reuse that text equality alone would allow") = secure {
    val a = "module T where\n\na = 1\nb = 2\n"
    val b = "module T where\n\na = 1\n  b = 2\n"
    val c0 = SurfaceParsers.moduleCached("T.e", a, "T", None).toOption.get._3
    val (sm, _, c1) = SurfaceParsers.moduleCached("T.e", b, "T", Some(c0)).toOption.get
    val fresh = SurfaceParsers.moduleMarked("T.e", b, "T").toOption.get._1
    ((c0.hits == 0 && c0.misses == 2) :| ("cold: " + c0.hits + "/" + c0.misses)) &&
    ((c1.hits == 0) :| ("the indented continuation was reused: " + c1.hits)) &&
    ((sm == fresh) :| ("spliced != fresh: " + firstDiff(sm, fresh))) &&
    ((fresh.statements.size == 1) :| "the edit did not merge the two statements"
    )
  }

  // --------------------------------- (iii) reuse metadata survives reuse

  /** The Stage-4 invariant "REUSE METADATA SURVIVES REUSE" (swift-syntax
    * #3397): a statement that is REUSED is not parsed, so it computes no
    * mark of its own -- its entry must carry the mark it had.  Two edits at
    * the bottom of the file leave the top statement reused twice; its guard
    * must still be the one the cold parse measured, not zero and not the
    * extent's length. */
  property("a twice-reused entry still carries its own examined length") = secure {
    val s0 = "module T where\n\na = 1\n\nb = 2\n\nc = 3\n"
    val s1 = "module T where\n\na = 1\n\nb = 2\n\nc = 33\n"
    val s2 = "module T where\n\na = 1\n\nb = 2\n\nc = 333\n"
    val c0 = SurfaceParsers.moduleCached("T.e", s0, "T", None).toOption.get._3
    val c1 = SurfaceParsers.moduleCached("T.e", s1, "T", Some(c0)).toOption.get._3
    val c2 = SurfaceParsers.moduleCached("T.e", s2, "T", Some(c1)).toOption.get._3
    val k = SurfaceCache.Key("a", 0)
    val cold = c0.entries(k)
    val warm = c2.entries(k)
    ((c2.hits >= 2) :| ("only " + c2.hits + " reused")) &&
    ((warm.examinedLength == cold.examinedLength) :|
      ("mark not carried: " + warm.examinedLength + " vs " + cold.examinedLength)) &&
    ((cold.examinedLength > cold.extentLength) :|
      ("vacuous: the mark does not exceed the extent (" + cold.examinedLength + " vs " +
       cold.extentLength + ")"))
  }

  // ------------------------------- (iv) a zero-consumption entry is refused

  /** REVIEW R-3.  A hit advances the parse by the entry's `consumedLength`, so an
    * entry that consumed NOTHING would make the hit arm a committed no-op and
    * `sepEndBy(semi)` would spin on it — non-termination, not a wrong tree.  No
    * such entry can be recorded (the miss path refuses to cache one) and none
    * exists in the corpus, so the only way to exercise the reuse side is to
    * build one by hand: take a real entry, set its consumed length to 0, and
    * require that the cache treats it as a MISS — which also means this property
    * HANGS if the guard is removed, rather than failing, so it is written with
    * the whole parse behind a deadline. */
  property("an entry that consumed nothing is refused, not reused") = secure {
    val src = "module T where\n\na = 1\n\nb = 2\n"
    val c0 = SurfaceParsers.moduleCached("T.e", src, "T", None).toOption.get._3
    val k = SurfaceCache.Key("a", 0)
    val real = c0.entries(k)
    val poisoned = c0.copy(entries = c0.entries + (k -> real.copy(consumedLength = 0)))
    val fresh = SurfaceParsers.moduleMarked("T.e", src, "T").toOption.get._1
    // THE CONTROL that makes this non-vacuous without planting a bug: the very
    // same cache, unpoisoned, reuses BOTH statements.  One field changed on one
    // entry is therefore the whole difference between 2 hits and 1.
    val control = SurfaceParsers.moduleCached("T.e", src, "T", Some(c0)).toOption.get._3
    // a deadline, because the failure mode this guards is a spin, not a wrong
    // answer: 10 s is three orders of magnitude over the real cost
    val done = new java.util.concurrent.atomic.AtomicReference[Option[(Int, Boolean)]](None)
    val t = new Thread(() => {
      val (sm, _, c1) = SurfaceParsers.moduleCached("T.e", src, "T", Some(poisoned)).toOption.get
      done.set(Some((c1.hits, sm == fresh)))
    })
    t.setDaemon(true)
    t.start()
    t.join(10000)
    ((real.consumedLength > 0) :| "the real entry consumed nothing, so the pin is vacuous") &&
    ((control.hits == 2) :| ("the control reused " + control.hits + " of 2, so the poisoning " +
                             "is not what this property measures")) &&
    ((c0.misses == 2 && c0.hits == 0) :| ("cold: " + c0.hits + "/" + c0.misses)) &&
    (done.get match {
      case None => false :| "the spliced parse did not finish in 10 s — the zero-consumption guard is gone"
      case Some((hits, agreed)) =>
        // the OTHER statement is still reused: the guard refuses one entry, not the cache
        ((hits == 1) :| ("expected exactly the poisoned entry to miss, reused " + hits)) &&
        (agreed :| "spliced != fresh")
    })
  }

  // ------------------------------------------- (iv) re-anchoring by a line

  property("a line inserted at the top moves every reused span by exactly one line") = secure {
    val f = corpus.find(_.getPath.endsWith("Report.e")).get
    val src = slurp(f)
    val head = src.indexOf("\n\n")     // after the header block
    val at = StatementExtents.scan(src).items
      .find(x => x.headWord != "import" && x.headWord != "export").get.startLine
    val o = new StatementExtents.Offsets(src)
    val shifted = splice(src, o.offsetOf(at, 1), 0, "\n")
    val c0 = SurfaceParsers.moduleCached(f.getPath, src, "Report", None).toOption.get._3
    val (sm, _, c1) = SurfaceParsers.moduleCached(f.getPath, shifted, "Report", Some(c0)).toOption.get
    val fresh = SurfaceParsers.moduleMarked(f.getPath, shifted, "Report").toOption.get._1
    val cold  = SurfaceParsers.moduleMarked(f.getPath, src, "Report").toOption.get._1
    val moved = cold.statements.map(_.loc.span.startLine + 1) ==
                fresh.statements.map(_.loc.span.startLine)
    ((head > 0) :| "no header") &&
    ((c1.hits > c1.misses) :| ("a line shift reused " + c1.hits + " of " + c1.statements)) &&
    ((sm == fresh) :| ("spliced != fresh: " + firstDiff(sm, fresh))) &&
    (moved :| "the shift did not move every statement by one line")
  }
}
