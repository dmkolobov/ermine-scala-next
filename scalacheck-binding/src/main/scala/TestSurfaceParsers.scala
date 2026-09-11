package com.clarifi.reporting

import java.io.File

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.syntax.{ Renaming, Single }
import com.clarifi.reporting.ermine.surface._

import org.scalacheck._
import Prop._
import scalaparsers.Supply

/** 2.3a parity: the resolution-free header agrees with the fused
  * pipeline's over every stdlib module, and the statement splitter
  * covers every file with plausible structure. */
object TestSurfaceParsers extends Properties("Surface parser 2.3a") {

  private implicit val supply: Supply = Supply.create

  private def moduleFiles: List[File] = {
    def walk(f: File): List[File] =
      if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
      else if (f.getName endsWith ".e") List(f) else Nil
    // stdlib AND the user-style example programs (Holes, the relational
    // examples, bugs/ regression cases, examples/Ai/) — different surface variety
    walk(new File("core/src/main/resources/modules")) ++ walk(new File("core/examples"))
  }

  private def read(f: File): String = {
    val s = scala.io.Source.fromFile(f, "UTF-8")
    try s.mkString finally s.close()
  }

  private def oldHeader(name: String, input: String) =
    ModuleParsers.moduleHeader(name).run(ErParseState.mk(name, input, name), supply.split)

  property("headers agree with the fused pipeline across the stdlib") = secure {
    val bad = List.newBuilder[String]
    var files = 0
    for (f <- moduleFiles) {
      val input = read(f)
      (oldHeader(f.getName, input), SurfaceParsers.module(f.getName, input, f.getName)) match {
        case (Right((_, oldH)), Right(m)) =>
          files += 1
          val h = m.header
          if (h.name != oldH.name) bad += s"${f.getName}: name ${h.name} vs ${oldH.name}"
          val oldImps = oldH.importExports
          if (h.imports.size != oldImps.size)
            bad += s"${f.getName}: ${h.imports.size} imports vs ${oldImps.size}"
          else for ((n, o) <- h.imports zip oldImps) {
            if (n.module != o.module) bad += s"${f.getName}: import ${n.module} vs ${o.module}"
            if (n.isExport != o.isExport) bad += s"${f.getName}/${o.module}: export flag"
            if (n.as != o.as || n.as.map(_.spelling) != o.as)
              if (n.as.map(_.spelling) != o.as) bad += s"${f.getName}/${o.module}: as ${n.as.map(_.spelling)} vs ${o.as}"
            val oldItems: Option[(Boolean, Int)] =
              if (o.using || o.explicits.nonEmpty) Some((o.using, o.explicits.size)) else None
            (n.items, oldItems) match {
              case (Some((u, xs)), Some((ou, on))) =>
                if (u != ou) bad += s"${f.getName}/${o.module}: using flag"
                if (xs.size != on) bad += s"${f.getName}/${o.module}: ${xs.size} items vs $on"
                val newNames = xs.map(_.name.spelling.stripPrefix("(").stripSuffix(")")).toSet
                val oldNames = o.explicits.map {
                  case Single(g, _)      => g.string
                  case Renaming(g, _, _) => g.string
                }.toSet
                if (newNames != oldNames) bad += s"${f.getName}/${o.module}: items $newNames vs $oldNames"
              case (None, None) => ()
              case (a, b) => bad += s"${f.getName}/${o.module}: item presence $a vs $b"
            }
          }
        case (Left(_), Left(_)) => files += 1  // agreement on rejection
        case (Left(err), Right(_)) => bad += s"${f.getName}: old rejects, new accepts: ${err.toString.linesIterator.next()}"
        case (_, Left(err))
            if f.getPath.endsWith("examples/Sample.e") || f.getPath.endsWith("guide/HelloWorld.e") =>
          files += 1  // legacy bodies the old pipeline rejects too; 2.3c
                      // statement grammar now fails them at the body
        case (_, Left(err)) => bad += s"${f.getName}: NEW header failed: ${err.toString.linesIterator.next()}"
      }
    }
    val failures = bad.result()
    // TWO assertions, because they catch different things.
    //
    // The count was the literal 271 until 2026-09-07, when four example groups landed at
    // once (`core/examples/{Wide,Algebra,Time,Present}`) and the corpus went 271 -> 333:
    // the property then failed with `Expected 271 but got 315` and an EMPTY failure list,
    // i.e. on the count alone, and every future example would have had to edit it.
    //
    // Deriving the count removes that trap but, on its own, asserts NOTHING: every branch
    // of the match above either does `files += 1` or appends to `bad`, so `failures.isEmpty`
    // already implies `files == moduleFiles.size`.  What the literal bought and the derived
    // equality does not is the FLOOR: if `moduleFiles` ever comes back empty or truncated --
    // wrong working directory, moved resources, partial checkout -- then `bad` is empty,
    // `files` and `expected` are both 0, and the property would pass on a corpus of zero
    // files.  The literal failed loudly at `Expected 271 but got 0`.
    //
    // So: keep the derived equality (it documents the invariant) and add the floor this file
    // already uses twice below (`fixities > 30`, `statements > 1000`) and `TestTolerantRead`
    // uses as `>= 180`.  E1 review finding N-1; tracker/loopmodel/E1-EXAMPLES.md section 3d.
    val expected = moduleFiles.size
    (failures.isEmpty :| failures.take(6).mkString(" ;; ")) &&
      ((expected >= 250) :| s"only $expected corpus files found -- sweep broken?") &&
      ((files ?= expected) :| s"$files of $expected files compared")
  }

  property("the splitter covers every file with ordered, plausible statements") = secure {
    val bad = List.newBuilder[String]
    var fixities = 0
    var statements = 0
    for (f <- moduleFiles) {
      val input = read(f)
      val legacy = f.getPath.endsWith("examples/Sample.e") || f.getPath.endsWith("guide/HelloWorld.e")
      SurfaceParsers.module(f.getName, input, f.getName) match {
        case Left(err) if oldHeader(f.getName, input).isLeft || legacy => ()  // old rejects these too
        case Left(err) => bad += s"${f.getName}: ${err.toString.linesIterator.next()}"
        case Right(m) =>
          statements += m.statements.size
          // spans strictly ordered and statements non-empty for non-trivial files
          val spans = m.statements.map(_.loc.span)
          for ((a, b) <- spans zip spans.drop(1))
            if (b.startLine < a.startLine) bad += s"${f.getName}: unordered spans $a $b"
          // fixity statements really parse (not placeholders), and match an
          // independent regex count of fixity declarations
          val parsed = m.statements.count { case _: SFixity => true; case _ => false }
          val uncommented = input.replaceAll("(?s)\\{-.*?-\\}", "")
          val expected = uncommented.linesIterator.count(_.matches("^(infixl|infixr|infix|prefix|postfix)\\b.*"))
          fixities += parsed
          if (parsed != expected) bad += s"${f.getName}: $parsed fixity stmts vs $expected by regex"
          // nothing may remain unconsumed: every non-fixity statement is a
          // classified placeholder, never an unclassifiable mystery
          m.statements foreach {
            case SErrorStatement(_, msg) if !(msg startsWith "unparsed:") =>
              bad += s"${f.getName}: unexpected error statement $msg"
            case SErrorStatement(loc, msg) if (msg startsWith "unparsed:") && !legacy =>
              // 2.3c: EVERY statement on an old-parseable file parses for
              // real; the two exempted files are legacy syntax the fused
              // pipeline rejects too (verified via Session.parseModule)
              bad += s"${f.getName}:${loc.span.startLine}: $msg fell back to placeholder"
            case _ => ()
          }
      }
    }
    val failures = bad.result()
    (failures.isEmpty :| failures.take(6).mkString(" ;; ")) &&
    ((fixities > 30) :| s"only $fixities fixity statements found — sweep broken?") &&
    ((statements > 1000) :| s"only $statements statements")
  }

  property("2.3b term and pattern shapes parse as written") = secure {
    def stmts(body: String) =
      SurfaceParsers.module("t", "module T where\n" + body, "T")
        .toOption.map(_.statements).getOrElse(Nil)

    val chain = stmts("v = 1 + !! x") match {
      case List(SEquation(_, _, _, SChain(c), _)) =>
        (c.items.collect { case Right(o) => (o.name.spelling, o.posClass) }
          ?= List(("+", PostOperandPos), ("!!", OperandPos))) :| "chain ops"
      case other => falsified :| ("chain: " + other)
    }
    val neg = stmts("f q = -q + 1") match {
      case List(SEquation(_, _, _, SNeg(_, _, SChain(_)), _)) => proved
      case other => falsified :| ("neg: " + other)
    }
    val doTree = stmts("g = do w <- liftDo (Just 1); unit w") match {
      case List(SEquation(_, _, _, SDo(_, List(_: SDoBind, _: SDoExpr)), _)) => proved
      case other => falsified :| ("do: " + other)
    }
    val recVsBrace = (stmts("r = {f = 1, g = 2}"), stmts("b = {1, 2}_M")) match {
      case (List(SEquation(_, _, _, _: SRecordLit, _)),
            List(SEquation(_, _, _, SBraceLit(_, _, Some("M")), _))) => proved
      case other => falsified :| ("rec/brace: " + other)
    }
    val envl = stmts("s f op r = [| f = op, r > 1, p <- i |] r") match {
      case List(SEquation(_, _, _, SApp(SRelEnvelope(_, arrows), _), _)) =>
        (arrows.map(_.getClass.getSimpleName) ?= List("SCombineArrow", "SFilterArrow", "SRenameArrow")) :| "arrow kinds"
      case other => falsified :| ("envelope: " + other)
    }
    val pat = stmts("h (a@(x :: y) : Int) = a") match {
      case List(SEquation(_, _, List(SPParen(_, SPSig(_, SPAs(_, _, SPParen(_, SPChain(_))), _))), _, _)) => proved
      case other => falsified :| ("pattern: " + other)
    }
    chain && neg && doTree && recVsBrace && envl && pat
  }

  property("2.3c type shapes parse as written") = secure {
    def sigTy(body: String) =
      SurfaceParsers.module("t", "module T where\n" + body, "T")
        .toOption.map(_.statements).getOrElse(Nil) match {
        case List(SSigStatement(_, _, t)) => Some(t)
        case _ => None
      }
    val fa = sigTy("f : forall {k} (a: k) b. a -> b") match {
      case Some(STyForall(_, List(k), List(a, b), STyChain(c))) =>
        ((k.spelling, a.name.spelling, a.kind.isDefined, b.kind.isDefined) ?= ("k", "a", true, false)) &&
        ((c.items.collect { case Right(o) => o.name.spelling } ?= List("->")) :| "arrow op")
      case other => falsified :| ("forall: " + other)
    }
    val ex = sigTy("g : exists c. a <- (b, c)") match {
      case Some(STyExists(_, List(_), List(STyChain(c)))) =>
        (c.items.collect { case Right(o) => o.name.spelling } ?= List("<-")) :| "partition op"
      case other => falsified :| ("exists: " + other)
    }
    val sm = sigTy("h : some a. F a -> Int") match {
      case Some(STySome(_, _, List(_), _)) => proved
      case other => falsified :| ("some: " + other)
    }
    val row = sigTy("r : Record {..q} -> [A, B]") match {
      case Some(STyChain(c)) =>
        (c.items.collectFirst { case Left(STyApp(_, STyRowBrace(_, true, _))) => true }.isDefined :| "dots row") &&
        (c.items.collectFirst { case Left(STyRowBracket(_, false, inner)) => inner.size }.getOrElse(-1) ?= 2)
      case other => falsified :| ("rows: " + other)
    }
    fa && ex && sm && row
  }

  /** 2.3d: the 1.3b rejected corpus, re-checked under the new parser.
    * Decision (f): rejection-vs-acceptance parity is gate-hard, but a
    * refusal may legitimately MOVE to a later pass — each moved case is
    * recorded here with its owing pass, and that pass's item must flip
    * the disposition to a refusal when it lands. */
  property("2.3d rejected-corpus dispositions") = secure {
    sealed trait Disp
    case class ParsesNow(owedBy: String) extends Disp   // refusal moves to the named pass
    case object StillRejects extends Disp
    val corpus: List[(String, String, Disp)] = List(
      ("unknown op in chain",      "v = 1 %%% 2",                          ParsesNow("3.3 re-associate: no fixity for %%%")),
      ("op before its fixity",     "v = 1 :%: 2\ninfixl 5 :%:\n(:%:) x y = x", ParsesNow("3.3 re-associate: positional fixity env")),
      ("mixed assoc equal prec",   "infixl 5 <%>\ninfixr 5 <^>\n(<%>) x y = x\n(<^>) x y = y\nv = 1 <%> 2 <^> 3", ParsesNow("3.3 re-associate: ambiguous operator")),
      ("refix imported operator",  "infixr 3 &&",                          ParsesNow("3.3 fixity env: Multiple fixity definitions")),
      ("postfix+infix collision",  "infixl 5 :%:\npostfix 5 :%:\n(:%:) x y = x", ParsesNow("3.3 fixity env: shared bucket")),
      ("top-level import shadow",  "id = 1",                               ParsesNow("3.2 rename: would shadow global definition")),
      ("data-con operator binder", "v = let (::) a b = 7 in 1",            ParsesNow("3.2 rename: constructor binder refusal")),
      ("missing bracket hooks",    "v = [1, 2]",                           ParsesNow("3.4 desugar: empty_Bracket/cons_Bracket unresolved")),
      ("empty brace literal",      "v = {}",                               ParsesNow("3.2/3.4: renamer rejects {} (old crashes masked by race)")),
      // [FLIPPED 2026-08-31, D3: chains open with prefix ops; the yard
      // refuses the stack ("ill-formed expression")]
      ("bare prefix stacking",     "prefix 9 !!\n(prefix !!) q = 0 - q\nv = !! !! 5", ParsesNow("re-associate: yard refuses the prefix stack (ill-formed expression)")),
      ("dead underscore affix",    "v = 1 +_ 2",                           StillRejects))
    val bad = List.newBuilder[String]
    for ((label, body, want) <- corpus) {
      val r = SurfaceParsers.module(label, "module T where\n" + body, "T")
      val placeholderFree = r match {
        case Right(m) =>
          def ok(s: SStatement): Boolean = s match {
            case _: SErrorStatement => false
            case SPrivateBlock(_, ss) => ss.forall(ok)
            case _ => true
          }
          m.statements.forall(ok)
        case Left(_) => false
      }
      (want, placeholderFree) match {
        case (ParsesNow(_), true)  => ()
        case (StillRejects, false) => ()
        case (ParsesNow(owed), false) =>
          bad += s"$label: expected to parse (refusal owed by $owed) but was rejected/placeholdered"
        case (StillRejects, true) =>
          bad += s"$label: expected a parse rejection but it parsed"
      }
    }
    val failures = bad.result()
    failures.isEmpty :| failures.mkString(" ;; ")
  }

  // ---------------------------------------------------------------- 7.1a
  // THE HIGH-WATER MARK (LSP Stage 4 item 7.1a).  `ParseState` carries one
  // shared `Mark` cell per parse; `SurfaceParsers.moduleMarked` records, per
  // top-level statement, the furthest input offset the parse had EXAMINED when
  // that statement finished.  These four properties are the item's acceptance
  // tests, and each is written so it can FAIL: (1) the mark really does reach
  // past a statement's own extent on real corpus files -- including, by name,
  // the 15 Report.e statements item 7.0 4.3 measured as looking past their
  // extent; (2) it never falls SHORT of what was consumed; (3) Lean's
  // `private def` counterexample, built in Ermine, has its first statement's
  // mark reaching into the second; (4) a failed `attempt` leaves the mark up.

  /** The 15 Report.e statements whose slice parse differs from the whole-file
    * parse ONLY in the statement's end span (tracker/loopmodel/LSP4-7.0-READ.md
    * 4.3), by start line.  These are exactly where `atLayoutBoundary` looked
    * past the extent, so each one's mark MUST exceed its extent's end. */
  private val report43StartLines =
    List(152, 391, 395, 473, 642, 731, 770, 781, 908, 916, 924, 1044, 1110, 1148, 1586)

  private case class MarkRow(file: String, startLine: Int,
                             startOffset: Int, extentEnd: Int, consumedEnd: Int,
                             examinedEnd: Int, nextStart: Int)

  /** Every recorded mark of every corpus file, joined to the extent scanner's
    * view of the same statement. */
  private def markRows(): (List[MarkRow], List[String]) = {
    val rows = List.newBuilder[MarkRow]
    val bad = List.newBuilder[String]
    for (f <- moduleFiles) {
      val input = read(f)
      SurfaceParsers.moduleMarked(f.getName, input, f.getName) match {
        case Left(_) => ()   // files the surface parser rejects; covered above
        case Right((m, marks)) =>
          if (marks.size != m.statements.size)
            bad += s"${f.getName}: ${marks.size} marks for ${m.statements.size} statements"
          val off = new StatementExtents.Offsets(input)
          val items = StatementExtents.scan(input).items
          val extEnd = items.map(e =>
            (e.startLine, e.startCol) -> off.offsetOf(e.endLine, e.endCol)).toMap
          val nextStart = {
            val starts = items.map(e => off.offsetOf(e.startLine, e.startCol))
            items.map(e => (e.startLine, e.startCol)).zip(starts.drop(1) :+ input.length).toMap
          }
          for (mk <- marks) {
            val key = (mk.startLine, mk.startCol)
            rows += MarkRow(f.getPath, mk.startLine, mk.startOffset,
                            extEnd.getOrElse(key, mk.endOffset), mk.endOffset,
                            mk.examinedEnd, nextStart.getOrElse(key, input.length))
          }
      }
    }
    (rows.result(), bad.result())
  }

  property("7.1a: the mark reaches PAST the statement's extent (anti-vacuity)") = secure {
    val (rows, bad) = markRows()
    val beyondExtent   = rows.count(r => r.examinedEnd > r.extentEnd)
    val beyondConsumed = rows.count(r => r.examinedEnd > r.consumedEnd)
    val intoNext       = rows.count(r => r.examinedEnd > r.nextStart)
    // the 15 named Report.e statements, each checked individually
    val rep = rows.filter(_.file.endsWith("Layout/Report.e"))
    val missing = report43StartLines.filter { l =>
      !rep.exists(r => r.startLine == l && r.examinedEnd > r.extentEnd)
    }
    val note = s"statements ${rows.size}; mark past extent $beyondExtent, " +
               s"past consumed end $beyondConsumed, into the next extent $intoNext; " +
               s"Report.e rows ${rep.size}"
    (bad.isEmpty :| bad.take(4).mkString(" ;; ")) &&
    ((rows.size > 1000) :| s"only ${rows.size} marked statements -- sweep broken? ($note)") &&
    ((beyondExtent >= 15) :| s"the mark never exceeds an extent: $note") &&
    // stated against the NEXT EXTENT'S START, which is strictly stronger than
    // the extent end and is what makes the atLayoutBoundary site load-bearing
    // for the 61 statements followed by a blank line or a comment run: with
    // that site's `reach` removed this count drops to 6,893 (review F2), so
    // THIS assertion is what catches the planting over the corpus.
    ((intoNext ?= rows.size) :|
      s"only $intoNext of ${rows.size} marks reach into the next extent ($note)") &&
    ((missing.isEmpty) :| s"7.0 4.3 statements whose mark does NOT pass their extent: $missing ($note)")
  }

  property("7.1a: the mark never falls short of what the parse consumed") = secure {
    val (rows, bad) = markRows()
    val short = rows.filter(r => r.examinedEnd < r.consumedEnd)
    val shortExtent = rows.filter(r => r.examinedEnd < r.extentEnd)
    (bad.isEmpty :| bad.take(4).mkString(" ;; ")) &&
    ((short.isEmpty) :| s"${short.size} statements examined less than they consumed, e.g. ${short.take(3)}") &&
    ((shortExtent.isEmpty) :| s"${shortExtent.size} statements examined less than their extent, e.g. ${shortExtent.take(3)}")
  }

  property("7.1a: Lean's counterexample -- the first statement's mark reaches into the second") = secure {
    // Editing the SECOND statement's first token changes how the FIRST
    // statement's trailing boundary is decided: indent `b` by one space and
    // the offside rule makes it a continuation of `a`, so `a`'s tree changes
    // although the edit is strictly after `a`'s text.  (Lean's note: "take the
    // (partial) input `def a := b private def c` ... the edit was strictly
    // after the end of the first command.")
    val src  = "module T where\na = 1\nb = 2\n"
    val edit = "module T where\na = 1\n b = 2\n"
    val bOffset = src.indexOf("b = 2")
    val split = SurfaceParsers.moduleMarked("lean", src, "T")
    val fused = SurfaceParsers.module("lean", edit, "T")
    val edited = fused match {
      case Right(m) => m.statements.size != 2 ||
                       m.statements.head != split.toOption.get._1.statements.head
      case Left(_)  => true   // the continuation does not parse: also a change
    }
    split match {
      case Right((m, marks)) if m.statements.size == 2 && marks.size == 2 =>
        val first = marks.head
        ((first.examinedEnd > bOffset) :|
          s"the first statement's mark ${first.examinedEnd} does not reach the second " +
          s"statement's first character at $bOffset (extent ends ${first.endOffset})") &&
        ((edited) :| "the one-space edit did not change the first statement after all") &&
        ((first.startOffset <= bOffset) :| "offsets are not what this test thinks")
      case other => falsified :| s"the two-statement buffer did not parse as two: $other"
    }
  }

  property("7.1a: atLayoutBoundary's OWN trivia scan reaches past the trivia") = secure {
    // The corpus property below cannot isolate this site: the token layer
    // CONSUMES the trailing trivia through `rawSatisfy` anyway, so the mark
    // reaches the next statement's first character with or without the bump in
    // `atLayoutBoundary` (measured -- removing that bump leaves every corpus
    // count unchanged).  This runs `atLayoutBoundary` ALONE, on a state whose
    // trivia has NOT been consumed, where the explicit bump is the only thing
    // that can move the mark: the parser is a `get` and a direct
    // `StatementExtents.skipTrivia` over the input, no primitive involved.
    val src = "x\n\n  -- a comment\n\ny = 1\n"
    val yAt = src.indexOf("y = 1")
    val ps = scalaparsers.ParseState[Unit](
      loc         = scalaparsers.Pos("t", "x", 1, 2, false),
      input       = src,
      offset      = 1,
      s           = (),
      layoutStack = List(scalaparsers.IndentedLayout[Unit](1, "top level")),
      bol         = false,
      // a LIVE mark: ParseState's default is `MarkOff`, the strict path's
      // no-op, so a test of the mark has to ask for the real one
      mark        = new scalaparsers.Mark)
    val r = SurfaceParsers.atLayoutBoundary.run(ps, supply.split)
    ((r.isRight) :| s"atLayoutBoundary should accept a column-1 successor: $r") &&
    ((ps.offset ?= 1) :| "atLayoutBoundary must not consume") &&
    ((ps.mark.furthest > yAt) :|
      s"the trivia scan left the mark at ${ps.mark.furthest}; the first significant " +
      s"character after the trivia is at $yAt, so the mark must exceed it")
  }

  property("7.1a: atLayoutBoundary covers the byte its comment PEEK decides on") = secure {
    // Review finding F1.  `StatementExtents.skipTrivia` decides whether to keep
    // skipping by PEEKING at `i + 1`: `-x` stops the scan where `--` opens a
    // line comment and keeps it going, and likewise `{x` against `{-`.  So the
    // byte at `i + 1` flips the site's decision and has to be inside the guard
    // `[start, examinedEnd)`.  The site used to record `reach(i + 1)`, whose
    // exclusive end is exactly `i + 1` -- one byte short, which is this table:
    //
    //   input             atLayoutBoundary   mark with reach(i+1)   needed
    //   "a = 1\n  -x\n"   FAILS              9                      >= 10
    //   "a = 1\n  --\n"   SUCCEEDS           12                     >= 10
    //   "a = 1\n  {x\n"   FAILS              9                      >= 10
    //   "a = 1\n  {-\n"   SUCCEEDS           12                     >= 10
    def boundary(src: String): (Boolean, Int) = {
      val ps = scalaparsers.ParseState[Unit](
        loc         = scalaparsers.Pos("t", "a = 1", 1, 6, false),
        input       = src,
        offset      = 5,
        s           = (),
        layoutStack = List(scalaparsers.IndentedLayout[Unit](1, "top level")),
        bol         = false,
        mark        = new scalaparsers.Mark)
      val r = SurfaceParsers.atLayoutBoundary.run(ps, supply.split)
      (r.isRight, ps.mark.furthest)
    }
    val flip = 9   // the byte the peek decides on, in every one of the four
    val cases = List("a = 1\n  -x\n" -> false, "a = 1\n  --\n" -> true,
                     "a = 1\n  {x\n" -> false, "a = 1\n  {-\n" -> true)
    val rows = cases.map { case (src, want) => (src, want, boundary(src)) }
    val decisions = rows.map { case (src, want, (got, _)) =>
      ((got ?= want) :| s"${src.replace("\n", "\\n")}: decision $got, expected $want") }
    val marks = rows.map { case (src, _, (_, m)) =>
      ((m > flip) :| s"${src.replace("\n", "\\n")}: mark $m does not cover the deciding byte $flip") }
    (decisions ++ marks).reduce(_ && _)
  }

  property("7.1a: rawTypeText's own scan covers the line it stops on") = secure {
    // Review finding F3: deleting this site's `reach` left all ten properties
    // green and every corpus count byte-identical, because inside
    // `rawTypeText` the trailing `optionalSpace` examines the same byte through
    // the primitives.  So run the SCANNER alone -- no primitive anywhere in it.
    //
    // On "Int\nB\n" at depth 1 the scan stops AT the newline (offset 3) because
    // the next line's first significant character sits at column 1: it reads
    // the byte at offset 4 to learn that, and consumes none of it.  Indent that
    // byte and the same scan runs on, which is what makes it load-bearing.
    def scan(src: String): (String, Int, Int) = {
      val ps = scalaparsers.ParseState[Unit](
        loc         = scalaparsers.Pos("t", src.linesIterator.next(), 1, 1, false),
        input       = src,
        offset      = 0,
        s           = (),
        layoutStack = List(scalaparsers.IndentedLayout[Unit](1, "top level")),
        bol         = false,
        mark        = new scalaparsers.Mark)
      SurfaceParsers.rawTypeTextScan(false).run(ps, supply.split) match {
        case Right((st, text)) => (text, st.offset, ps.mark.furthest)
        case Left(err)         => ("<failed>", -1, ps.mark.furthest)
      }
    }
    val stopped   = scan("Int\nB\n")    // column 1: the scan stops at the newline
    val continued = scan("Int\n B\n")   // indented: the same scan runs on
    val bAt = 4
    ((stopped._1 ?= "Int") :| s"the scan should stop at the newline, got '${stopped._1}'") &&
    ((stopped._2 ?= 3) :| s"the scan consumed to ${stopped._2}, expected 3 (the newline)") &&
    ((stopped._3 > bAt) :|
      s"the scan's mark is ${stopped._3}; it read the byte at $bAt to decide the stop, " +
      "so the mark must exceed it") &&
    ((continued._1.trim.endsWith("B")) :|
      s"the indented variant should run on, got '${continued._1}'")
  }

  property("7.1a: a failed attempt leaves the mark at what it examined") = secure {
    // `rawWord("abcdef")` consumes a, b, c and then EXAMINES 'x' to fail; the
    // `attempt` rolls the state back to offset 0, and the surviving state is
    // the one from before the branch -- yet the mark, being a shared cell,
    // still reads 4.  A plain field on the immutable state would read 0 here,
    // which is the whole reason for the design.
    // a LIVE mark on both states (the default is the strict path's `MarkOff`)
    val ps = scalaparsers.ParseState.mk("mark", "abcxyz", ())
      .copy(mark = new scalaparsers.Mark)
    val failed = SurfaceParsers.rawWord("abcdef").attempt.run(ps, supply.split)
    val afterFail = ps.mark.furthest
    // the same lookahead inside a real alternation: the winner consumes 3
    // characters, the mark keeps the 4th the loser looked at
    val ps2 = scalaparsers.ParseState.mk("mark", "abcxyz", ())
      .copy(mark = new scalaparsers.Mark)
    val won = (SurfaceParsers.rawWord("abcdef").attempt |
               SurfaceParsers.rawWord("abc")).run(ps2, supply.split)
    val consumed = won.toOption.map(_._1.offset).getOrElse(-1)
    ((failed.isLeft) :| "the lookahead was supposed to fail") &&
    ((ps.offset ?= 0) :| "attempt did not roll the offset back") &&
    ((afterFail >= 4) :| s"the failed attempt left the mark at $afterFail, expected >= 4") &&
    ((won.isRight) :| "the alternation was supposed to succeed") &&
    ((consumed ?= 3) :| s"the winning branch consumed $consumed, expected 3") &&
    ((ps2.mark.furthest >= 4) :|
      s"the mark after the alternation is ${ps2.mark.furthest}, expected >= 4 " +
      "(the discarded branch's examination was lost)")
  }

}



