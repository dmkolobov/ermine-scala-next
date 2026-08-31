package com.clarifi.reporting.ermine.surface

/** The statement-extent SCANNER (post-G1 D7; Stage 2's recovery
  * primitive).  A pure lexical pass over module source that computes
  * every top-level layout item's extent -- no parser state, so an
  * editor-side recovery can ask "where does the broken statement end,
  * where does the next begin" without a live parse.
  *
  * Statement extents are lexically determined (the same fact the
  * block-re-parse correctness argument rested on): a top-level item
  * starts at the layout column fixed by the FIRST item after the
  * module header, and runs until the next line whose first significant
  * character sits at (or left of) that column.  The scanner knows just
  * enough lexical structure to not be fooled:
  *
  *  - line comments (-- to end of line) and nested block comments are
  *    whitespace, wherever they start;
  *  - string literals consume to their closing quote (escapes
  *    respected), so braces and dashes inside them are inert;
  *  - explicit bracket depth ((), [], curly) keeps an item open across
  *    dedented lines;
  *  - let/case/do/where open INNER layout blocks whose contents are
  *    deeper than the top column, so plain offside covers them here
  *    (their in/dedent closers matter for the NESTED extents Stage 2
  *    adds on this same chassis).
  *
  * KNOWN CORNER (flagged by the D7 spec): scalaparsers' virtualLeftBrace
  * merges equal-column layout contexts (the col-max-depth merge), so an
  * inner block opened at exactly the top-level column reads as a new
  * top-level item to a pure scanner -- the surface parser's own
  * splitter has the same per-character-offside view, which is what the
  * differential test pins.
  */
object StatementExtents {

  /** 1-based; end = the position just past the last significant char. */
  final case class Extent(startLine: Int, startCol: Int,
                          endLine: Int, endCol: Int, headWord: String)

  final case class Scan(layoutCol: Int, items: List[Extent])

  /** Skip whitespace and comments from `from`, whose 1-based position is
    * (`fromLine`, `fromCol`), and answer where the next significant
    * character sits: (offset, line, column).  Columns advance the way
    * scalaparsers' Pos.bump advances them (tab to the next multiple of
    * 8), so the result can be compared against a layout depth.
    *
    * The splitter's statement-boundary check runs on this (5.2b); it is
    * the same lexical view `scan` takes, `--` treated as a comment
    * wherever it starts included.
    */
  def skipTrivia(s: String, from: Int, fromLine: Int, fromCol: Int): (Int, Int, Int) = {
    val n = s.length
    var i = from; var line = fromLine; var col = fromCol
    def peek(k: Int): Char = if (i + k < n) s.charAt(i + k) else ' '
    def advance(): Unit = {
      s.charAt(i) match {
        case '\n' => line += 1; col = 1
        case '\t' => col += 8 - col % 8
        case _     => col += 1
      }
      i += 1
    }
    var more = true
    while (more && i < n) {
      val c = s.charAt(i)
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') advance()
      else if (c == '-' && peek(1) == '-') { while (i < n && s.charAt(i) != '\n') advance() }
      else if (c == '{' && peek(1) == '-') {
        advance(); advance()
        var depth = 1
        while (i < n && depth > 0) {
          if (peek(0) == '{' && peek(1) == '-') { advance(); advance(); depth += 1 }
          else if (peek(0) == '-' && peek(1) == '}') { advance(); advance(); depth -= 1 }
          else advance()
        }
      }
      else more = false
    }
    (i, line, col)
  }

  /** A line-start index over ONE source string, so a run of position
    * lookups costs a single pass plus a walk of each target line --
    * rather than a walk from offset 0 per lookup.
    *
    * `TolerantCheck.keys` makes two lookups per top-level statement on
    * every keystroke (~630 of them on Layout/Report.e, each previously
    * scanning all 77KB), which the P2 profile measured at 4.7% of the
    * editor round trip: 93 of 1970 samples, every one of them under
    * `text` under `keys`.  See tracker/PERF-ROADMAP.md P5(a).
    *
    * The per-line walk STAYS, because a column is not an offset:
    * columns are counted the way scalaparsers' Pos.bump counts them,
    * tab to the next multiple of 8.  That walk is character-for-
    * character the tail of the original loop, so it keeps the original's
    * behaviour in the corner that matters -- when `col` overshoots the
    * line, the '\n' IS consumed, the line counter passes `line`, and the
    * answer is the offset just past the newline.  TestStatementExtents
    * pins the agreement against a naive reference over all 180 files.
    */
  final class Offsets(contents: String) {
    private val n = contents.length
    private val starts: Array[Int] = {
      val b = Array.newBuilder[Int]
      b += 0
      var i = 0
      while (i < n) { if (contents.charAt(i) == '\n') b += i + 1; i += 1 }
      b.result()
    }

    def offsetOf(line: Int, col: Int): Int = {
      var i = 0
      var l = 1
      if (line > 1) {
        if (line - 1 >= starts.length) return n
        i = starts(line - 1); l = line
      }
      var c = 1
      while (i < n && (l < line || (l == line && c < col))) {
        contents.charAt(i) match {
          case '\n' => l += 1; c = 1
          case '\t' => c += 8 - c % 8
          case _     => c += 1
        }
        i += 1
      }
      i
    }

    /** The source an extent covers. */
    def text(e: Extent): String =
      contents.substring(offsetOf(e.startLine, e.startCol),
                         offsetOf(e.endLine, e.endCol))
  }

  /** The char offset of a 1-based (line, column), counted the way
    * scalaparsers' Pos.bump counts (tab to the next multiple of 8).
    * One-shot; build an `Offsets` for a run of lookups over one string. */
  def offsetOf(contents: String, line: Int, col: Int): Int =
    new Offsets(contents).offsetOf(line, col)

  /** The source an extent covers.  One-shot; see `Offsets.text`. */
  def text(contents: String, e: Extent): String =
    new Offsets(contents).text(e)

  def scan(contents: String): Scan = {
    val n = contents.length
    var i = 0
    var line = 1; var col = 1

    def peek(k: Int = 0): Char = if (i + k < n) contents.charAt(i + k) else ' '
    def advance(): Unit = {
      if (contents.charAt(i) == '\n') { line += 1; col = 1 } else col += 1
      i += 1
    }

    def skipWsUnit(): Boolean = {
      val c = peek()
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { advance(); true }
      else if (c == '-' && peek(1) == '-') {
        while (i < n && peek() != '\n') advance()
        true
      }
      else if (c == '{' && peek(1) == '-') {
        advance(); advance()
        var depth = 1
        while (i < n && depth > 0) {
          if (peek() == '{' && peek(1) == '-') { advance(); advance(); depth += 1 }
          else if (peek() == '-' && peek(1) == '}') { advance(); advance(); depth -= 1 }
          else advance()
        }
        true
      }
      else false
    }
    def skipWs(): Unit = { while (i < n && skipWsUnit()) () }

    def step(): Int = peek() match {
      case '"' =>
        advance()
        while (i < n && peek() != '"') { if (peek() == '\\') advance(); if (i < n) advance() }
        if (i < n) advance()
        0
      case q if q == '\'' && ((peek(1) == '\\' && peek(3) == '\'') || (peek(1) != '\'' && peek(1) != ' ' && peek(2) == '\'')) =>
        // char literal; a lone quote is the (') operator
        val len = if (peek(1) == '\\') 4 else 3
        var k = 0; while (k < len && i < n) { advance(); k += 1 }
        0
      case '(' | '[' | '{' => advance(); 1
      case ')' | ']' | '}' => advance(); -1
      case _ => advance(); 0
    }

    skipWs()
    def wordAt(): String = {
      var k = i
      while (k < n && (contents.charAt(k).isLetter || contents.charAt(k) == '#' ||
                       contents.charAt(k) == '.' || contents.charAt(k).isDigit)) k += 1
      contents.substring(i, k)
    }
    if (wordAt() == "module") {
      var done = false
      while (i < n && !done) {
        if (!skipWsUnit()) {
          if (wordAt() == "where") { var k = 0; while (k < 5) { advance(); k += 1 }; done = true }
          else advance()
        }
      }
    }
    skipWs()
    if (i >= n) return Scan(1, Nil)

    val layoutCol = col
    val items = List.newBuilder[Extent]

    // one identifier-ish word consumed wholesale (so let/in are visible)
    def stepWord(): String = {
      val w = wordAt()
      if (w.nonEmpty) { var k = 0; while (k < w.length) { advance(); k += 1 }; w }
      else { step(); "" }
    }

    while (i < n) {
      val sl = line; val sc = col
      val head = wordAt()
      var depth = 0
      var lets = 0                       // open `let`s awaiting their `in`
      var endLine = line; var endCol = col
      var open = true
      while (i < n && open) {
        val before = peek()
        if (before == '(' || before == '[' || before == '{' ) depth += step()
        else if (before == ')' || before == ']' || before == '}') depth += step()
        else stepWord() match {
          case "let" => lets += 1
          case "in"  => if (lets > 0) lets -= 1
          case _     => ()
        }
        endLine = line; endCol = col
        skipWs()
        if (i >= n) open = false
        else if (depth <= 0 && col <= layoutCol && line != sl) {
          // the let-in closer: an `in` for an OPEN let continues the
          // item even at (or left of) the layout column (Report.e:1004)
          if (!(lets > 0 && wordAt() == "in")) open = false
        }
      }
      items += Extent(sl, sc, endLine, endCol, head)
    }
    Scan(layoutCol, items.result())
  }
}
