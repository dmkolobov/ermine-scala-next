package com.clarifi.reporting.ermine.surface

/** ANCHORED POSITIONS — the span arithmetic, in one place
  * (tracker/LSP-ROADMAP.md, Stage 4 item 7.2).
  *
  * A cached artifact — an inference result today (5.5/6.2), a parsed
  * statement after 7.1b — is keyed on TEXT and reused when the text
  * comes back byte-identical.  Its positions are then wrong by exactly
  * one number: the line the text now starts at, minus the line it
  * started at when the entry was recorded.  Nothing else can differ,
  * because a top-level statement starts at column 1 and its own text
  * fixes every column and every INTERNAL line offset inside it.
  *
  * So an entry stores its positions RELATIVE to its anchor (a 1-based
  * source line) and gets them back by adding the anchor it is looked up
  * at.  That is rust-analyzer's anchored span with its stated reason —
  * "storing absolute ranges will require recomputation on every change
  * in a file at all times" — and Roslyn's green-node rule.
  *
  * The three rules this object exists to keep in ONE place:
  *
  *   1. a relative line is `line - anchor`, and it may be NEGATIVE (an
  *      entry may hold a position above its own anchor; nothing here
  *      clamps, because clamping would silently move a position);
  *   2. COLUMNS ARE NEVER SHIFTED.  A line insertion or deletion moves
  *      whole lines; it cannot move a column without changing the text,
  *      and a changed text is a different key;
  *   3. `rel` and `abs` are inverses at the same anchor, and that is the
  *      only property a caller may rely on.  Re-anchoring at a
  *      DIFFERENT anchor than the one an entry was recorded at is a
  *      cache-key bug, not something this object can detect.
  */
object Anchors {

  /** A 1-based source line, relative to `anchor`. */
  def rel(line: Int, anchor: Int): Int = line - anchor

  /** A relative line, back to 1-based absolute at `anchor`. */
  def abs(line: Int, anchor: Int): Int = line + anchor

  /** A (line, column) pair.  The column is carried through untouched
    * (rule 2). */
  def relPos(p: (Int, Int), anchor: Int): (Int, Int) = (p._1 - anchor, p._2)
  def absPos(p: (Int, Int), anchor: Int): (Int, Int) = (p._1 + anchor, p._2)

  /** A whole span: both ends move by the same delta, both columns stay. */
  def relSpan(s: Span, anchor: Int): Span =
    Span(s.startLine - anchor, s.startCol, s.endLine - anchor, s.endCol)
  def absSpan(s: Span, anchor: Int): Span =
    Span(s.startLine + anchor, s.startCol, s.endLine + anchor, s.endCol)

  /** A map KEYED by (line, column) — 6.2's `locals` shape.  The empty map
    * is the common case (a component with no reachable local binder) and
    * costs nothing; there is deliberately no `anchor == 0` short circuit,
    * because an anchor is a 1-based source line and can never be 0, and a
    * dead arm reads as a supported case (review R-6). */
  def relKeys[A](m: Map[(Int, Int), A], anchor: Int): Map[(Int, Int), A] =
    if (m.isEmpty) m else m.map { case (k, v) => relPos(k, anchor) -> v }

  def absKeys[A](m: Map[(Int, Int), A], anchor: Int): Map[(Int, Int), A] =
    if (m.isEmpty) m else m.map { case (k, v) => absPos(k, anchor) -> v }

  /** The tag one item of a keyed group contributes to its key: where it
    * sits relative to the group's own anchor.  This is what stops an
    * edit BETWEEN two byte-identical items from being invisible to the
    * key while it moves one of them — the case that makes text-only keys
    * unsound on their own (7.2's drift invariant). */
  def tag(line: Int, anchor: Int): String = rel(line, anchor).toString
}
