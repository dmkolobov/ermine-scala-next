package scalaparsers

/** The HIGH-WATER MARK of one parse: the furthest input offset the parse has
  * EXAMINED -- consumed, or merely looked at to make a decision.  One cell per
  * parse unit, shared by every `ParseState` of that parse.
  *
  * WHY A MUTABLE CELL AND NOT A FIELD (LSP Stage 4 item 7.1a).  `ParseState`
  * is an immutable case class copied on every advance, and `Parser.attempt`
  * backtracks by DISCARDING the state its branch produced: on failure the
  * state that survives is the one from BEFORE the branch.  A plain `Int` field
  * on the state would therefore be thrown away with the branch -- losing
  * exactly the extent a failed lookahead examined, which is the only thing the
  * mark is for (Ohm defines `maxExaminedPos` to include input "used to make a
  * parsing decision"; four other systems converged on the same integer,
  * tracker/loopmodel/STAGE4-PRIOR-ART.md 1.10).  Because the cell is SHARED
  * rather than copied, `s.copy(...)` carries the same cell and a discarded
  * branch still leaves its examination recorded.
  *
  * THE CONVENTION is Ohm's, one position per examination: `reach(end)` says
  * every input position below `end` has been examined, so examining the single
  * position `p` -- by consuming the character there, by testing its value, or
  * by asking whether a character exists there at all -- is `reach(p + 1)`.
  * The absence of a character is as load-bearing as its value: a parse that
  * ended because nothing was at `p` depends on nothing being inserted at `p`.
  * So `furthest` may legitimately exceed `input.length` by one, and for the
  * last statement of a file it does.
  *
  * TWO KINDS, and which path gets which (the 7.1a fix round).  The mark exists
  * for the EDITOR's statement cache; the strict path must pay nothing for a
  * number it never reads.  `MarkOff` is therefore the DEFAULT on every
  * `ParseState`, and its `reach` is empty -- the batch loader, the REPL, the
  * interface parser and `statementFailure`'s slice re-parse all get it, and the
  * call sites stay bimorphic so the JIT inlines the empty body away.  Only
  * `SurfaceParsers.moduleMarked`, the editor-only whole-file entry, installs a
  * live `new Mark`.
  *
  * NOT STATE: two marks are interchangeable as far as a `ParseState` is
  * concerned, so `equals`/`hashCode` ignore the counter and the field changes
  * neither state equality nor any state's hash.
  *
  * NOT THREAD-SAFE, and it does not need to be: one cell belongs to one parse,
  * `Parser` is a single-threaded trampoline, and the parallel loader gives
  * every module's parse its own `ParseState.mk` and therefore its own cell.
  */
sealed class Mark(start: Int = 0) {
  private[this] var far: Int = start

  /** Record that every input position below `end` has been examined. */
  def reach(end: Int): Unit = if (end > far) far = end

  /** The exclusive end of the examined region. */
  def furthest: Int = far

  override def equals(other: Any): Boolean = other.isInstanceOf[Mark]
  override def hashCode: Int = 0
  override def toString: String = "mark(" + far + ")"
}

/** The strict path's mark: it records NOTHING, and therefore claims
  * EVERYTHING.  `reach` is empty, so a batch parse pays no counter; and
  * `furthest` answers `Int.MaxValue` rather than 0, so that a consumer which
  * reads a mark it should not have read is refused every reuse instead of being
  * told the parse examined nothing.  Unsoundness is not available by accident
  * here; only over-conservatism is.
  *
  * A sibling object rather than a `Mark.Off` inside a companion: both compile,
  * and this one keeps `Mark` without an explicit companion.  (A WARNING FOR
  * WHOEVER EDITS THIS FILE NEXT: an INCREMENTAL `core/compile` after touching
  * `Mark.scala` or `ParseState.scala` can fail with 27 `E046 Cyclic reference
  * involving val <import>` errors in the legacy `parsing/ParseState.scala` --
  * zinc recompiling a subset of the `ermine` package, not a real cycle.
  * `sbt core/clean core/compile` succeeds in 38 s.) */
object MarkOff extends Mark(0) {
  override def reach(end: Int): Unit = ()
  override def furthest: Int = Int.MaxValue
  override def toString: String = "mark(off)"
}
