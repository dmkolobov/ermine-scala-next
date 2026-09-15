package com.clarifi.reporting.ermine.surface

/** THE STATEMENT-EXTENT SURFACE CACHE (tracker/LSP-ROADMAP.md, Stage 4
  * item 7.1b) -- the editor's read, with the statements it already
  * parsed carried over instead of re-parsed.
  *
  * WHY IT IS SOUND TO CARRY A PARSED STATEMENT ACROSS AN EDIT
  * (Stage-4 Decision (a)): a surface node carries only an `SLoc`/`Span`
  * and literal payloads -- no binder id, no `V`, no supply draw, and
  * `SName`'s fixity is the LEXICAL bucket, not a resolved precedence.
  * A parsed statement is therefore a CLOSED value of its own text and
  * its layout context, and the only thing an edit elsewhere in the file
  * can do to it is move its LINES.
  *
  * THE THREE PARTS, and the invariant each one keeps:
  *
  *  1. THE KEY: `(headWord, ordinal among the extents with that head
  *     word)` -- the grouping `TolerantCheck.keys` already computes,
  *     scoped PER head word so that a new statement shifts only the
  *     ordinals of its own head word (rust-analyzer's `ErasedFileAstId`
  *     with its warning attached).  NO IDENTITY IS IN IT (the Stage-4
  *     invariant): a head word and a count, both recomputed lexically
  *     from the NEW text on every check.  An UNREACHABLE item in 7.2's
  *     sense -- an operator definition (empty head word), a backtick
  *     name, a spelling the scanner truncates at `_`/`'` -- is keyed
  *     exactly like any other, by the head word the scanner produced
  *     (the empty head words form the "" sequence).  That is safe
  *     because a key only SELECTS a candidate: reuse additionally
  *     demands byte-identical extent text, the same start column, the
  *     same layout depth and a clean guard, and under those four an
  *     identical text parses identically.  A colliding key can only
  *     cost a hit, never produce a wrong tree.  (7.2's reachable rule
  *     still governs what the INFERENCE cache may key; it says nothing
  *     about what the parse cache may reuse.)
  *
  *  2. THE GUARD: an entry is reused iff (a) its extent text is
  *     byte-identical to the new extent's, AND (b) no edit intersects
  *     `[start, start + examinedLength)`, where `examinedLength` is
  *     7.1a's high-water mark for that statement -- RELATIVE, never an
  *     absolute offset, and CARRIED FORWARD into the new entry on a hit
  *     (the "reuse metadata survives reuse" invariant), because a reused
  *     statement is not parsed and so computes no mark of its own.  The
  *     guard is FORWARD-only, so the two backward dependencies the mark
  *     cannot carry are in the reuse condition beside it (7.1a review
  *     F4): the statement's own start COLUMN and the enclosing layout
  *     DEPTH.
  *
  *  3. THE EDITS: not enumerated at all, but ANSWERED where the
  *     question is asked -- "does the new buffer still hold what this
  *     statement's parse examined?" is decided by comparing those bytes
  *     against the previous buffer's (`examinedUnchanged`).  That is the
  *     roadmap's predicate evaluated exactly, for any number of
  *     scattered edits at once; the extent list is still recomputed
  *     lexically from the NEW text every check, so a merge or a split
  *     shows up as a changed extent rather than as a silently reused
  *     tree.
  *
  * AND THE FOURTH PART, which is not a cache but arithmetic: a reused
  * statement's spans are re-anchored by adding the line delta to every
  * line field, through `Anchors.absSpan` (7.2's helper, rule 2: COLUMNS
  * ARE NEVER SHIFTED -- the statement's own text fixes every column and
  * every internal line offset, and a changed text is a different key).
  */
object SurfaceCache {

  /** `(headWord, ordinal)`; see the class comment.  No identity, no
    * offset, no line number -- two strings' worth of nothing. */
  final case class Key(headWord: String, ordinal: Int)

  /** One cached top-level statement.
    *
    * `startOffset`/`startLine` are where this entry's statement sat in
    * the buffer the entry was BUILT from; every position derived from
    * them is re-derived at lookup (`examinedLength` and
    * `consumedLength` are relative, 7.1a review F4's condition).
    * `endLine`/`endCol` are the parse's exit position -- which is the
    * statement's top-level `Span` end for every grammar path that ends
    * at its last token, and the NEXT statement's start for the ones that
    * end in a laid-out block, because `virtualRightBrace` skips the
    * trivia between them and does not roll it back.  Both are inside
    * the guard, so both survive it (7.0 §4.3's 15 statements). */
  final case class Entry(key: Key,
                         startOffset: Int, extentLength: Int,
                         startLine: Int, startCol: Int, depth: Int,
                         bolAtEntry: Boolean, bolAtExit: Boolean,
                         endLine: Int, endCol: Int,
                         consumedLength: Int, examinedLength: Int,
                         stmt: SStatement)

  /** What one editor read leaves behind for the next one: the text it
    * read, and one entry per top-level statement.  ONE PER OPEN
    * DOCUMENT, replaced wholesale by the next check -- the retention
    * bound is therefore one surface tree plus one buffer per open
    * document, and nothing accumulates across keystrokes. */
  final case class Cache(contents: String, entries: Map[Key, Entry],
                         hits: Int, misses: Int) {
    def statements: Int = hits + misses
  }

  object Cache {
    val empty: Cache = Cache("", Map.empty, 0, 0)
  }

  /** THE GUARD, evaluated directly: does the new buffer still hold, byte
    * for byte, everything the cached parse of this statement EXAMINED?
    *
    * `[oldStart, oldStart + examined)` is the region 7.1a's high-water
    * mark says that parse looked at -- what it consumed, what it peeked
    * at, and what a rolled-back branch examined and lost.  If the new
    * buffer holds the same bytes at `[start, start + examined)`, then no
    * edit intersects the guard and the parse would make the same
    * decisions again; if it does not, something the parse read has
    * changed and the statement is re-parsed.  That is the reuse rule
    * exactly as the roadmap states it -- and evaluating it on the BYTES
    * rather than on an edit list makes it exact for any number of
    * scattered edits, where a single changed-window model would refuse
    * reuse across the whole span between the first edit and the last.
    * The extent list is still recomputed lexically from the NEW text on
    * every check, which is what keeps a merge or a split visible as a
    * changed extent rather than as a silently reused tree.
    *
    * THE END OF INPUT IS PART OF THE GUARD.  7.1a's convention counts a
    * probe at `p` as examining `p`, so `examined` may run one past the
    * buffer: the parse depended on there being NOTHING there.  When it
    * does, the two buffers must also END at the same distance from the
    * statement -- otherwise a character now follows where none did. */
  def examinedUnchanged(oldText: String, oldStart: Int,
                        newText: String, start: Int, examined: Int): Boolean = {
    val availOld = oldText.length - oldStart
    val availNew = newText.length - start
    val n = math.min(examined, math.min(availOld, availNew))
    n >= 0 && (examined <= availOld && examined <= availNew || availOld == availNew) &&
      oldText.regionMatches(oldStart, newText, start, n)
  }

  /** The keys of a scan, in source order: one per extent, the ordinal
    * counted per head word.  Header extents (`import`/`export` lines,
    * which the statement grammar never sees -- the header parser
    * consumes them) get a key like anything else and are simply never
    * looked up. */
  def keysOf(items: List[StatementExtents.Extent]): List[Key] = {
    val seen = scala.collection.mutable.HashMap.empty[String, Int]
    items.map { x =>
      val n = seen.getOrElse(x.headWord, 0)
      seen(x.headWord) = n + 1
      Key(x.headWord, n)
    }
  }

  // ------------------------------------------------------------ shifting

  /** Every `Span` in a reused statement, moved by `d` lines.
    *
    * This is `Anchors.absSpan` applied to a whole tree: a top-level
    * statement whose text is byte-identical and whose start column is
    * unchanged differs from its earlier self by exactly one number, the
    * line it now starts at.  Columns are untouched (Anchors rule 2).
    * The traversal matches on the sealed surface hierarchy without a
    * default arm on purpose: a node type added without a case here is a
    * non-exhaustive-match warning at compile time and a differential
    * failure at test time, rather than a silently stale span. */
  object Shift {

    def statement(st: SStatement, d: Int): SStatement =
      if (d == 0) st else stmt(st, d)

    private def sp(s: Span, d: Int): Span = Anchors.absSpan(s, d)

    private def loc(l: SLoc, d: Int): SLoc = l match {
      case Real(s)  => Real(sp(s, d))
      case Synth(o) => Synth(sp(o, d))
    }

    private def name(n: SName, d: Int): SName = n.copy(span = sp(n.span, d))

    private def binder(b: SBinder, d: Int): SBinder =
      SBinder(name(b.name, d), b.kind.map(ty(_, d)))

    private def chain[A](c: Chain[A], d: Int, f: A => A): Chain[A] =
      Chain(loc(c.loc, d), c.items.map {
        case Left(a)  => Left(f(a))
        case Right(o) => Right(OpOcc(name(o.name, d), o.posClass))
      })

    private def stmt(x: SStatement, d: Int): SStatement = x match {
      case SFixity(l, f, tl, ops) => SFixity(loc(l, d), f, tl, ops.map(name(_, d)))
      case SFieldStatement(l, ns, t) => SFieldStatement(loc(l, d), ns.map(name(_, d)), ty(t, d))
      case STableStatement(l, db, ns, t) =>
        STableStatement(loc(l, d), db, ns.map(name(_, d)), ty(t, d))
      case STypeAlias(l, n, ks, ts, b) =>
        STypeAlias(loc(l, d), name(n, d), ks.map(name(_, d)), ts.map(binder(_, d)), ty(b, d))
      case SDataStatement(l, n, ks, ts, cs) =>
        SDataStatement(loc(l, d), name(n, d), ks.map(name(_, d)), ts.map(binder(_, d)),
                       cs.map(c => SConDef(loc(c.loc, d), c.exists.map(binder(_, d)),
                                           name(c.name, d), c.fields.map(ty(_, d)),
                                           c.fieldNames.map(_.map(name(_, d))))))
      case SClassStatement(l, n, ks, ts, ctx, body) =>
        SClassStatement(loc(l, d), name(n, d), ks.map(name(_, d)), ts.map(binder(_, d)),
                        ctx.map(ty(_, d)), body.map(stmt(_, d)))
      case SPrivateBlock(l, ss)       => SPrivateBlock(loc(l, d), ss.map(stmt(_, d)))
      case SDatabaseBlock(l, db, ss)  => SDatabaseBlock(loc(l, d), db, ss.map(stmt(_, d)))
      case SForeignBlock(l, ss)       => SForeignBlock(loc(l, d), ss.map(foreign(_, d)))
      case SSigStatement(l, ns, a)    => SSigStatement(loc(l, d), ns.map(name(_, d)), ty(a, d))
      case SEquation(l, n, as, b, w)  =>
        SEquation(loc(l, d), name(n, d), as.map(pat(_, d)), term(b, d), w.map(where(_, d)))
      case SErrorStatement(l, m)      => SErrorStatement(loc(l, d), m)
    }

    private def where(w: SWhere, d: Int): SWhere =
      SWhere(loc(w.loc, d), w.statements.map(stmt(_, d)))

    private def foreign(x: SForeign, d: Int): SForeign = x match {
      case SForeignData(l, n, bs, c, cs) =>
        SForeignData(loc(l, d), name(n, d), bs.map(binder(_, d)), c, sp(cs, d))
      case SForeignFunction(l, n, t, c, cs, m, ms) =>
        SForeignFunction(loc(l, d), name(n, d), ty(t, d), c, sp(cs, d), m, sp(ms, d))
      case SForeignMethod(l, n, t, m, ms) =>
        SForeignMethod(loc(l, d), name(n, d), ty(t, d), m, sp(ms, d))
      case SForeignValue(l, n, t, c, cs, m, ms) =>
        SForeignValue(loc(l, d), name(n, d), ty(t, d), c, sp(cs, d), m, sp(ms, d))
      case SForeignConstructor(l, n, t) => SForeignConstructor(loc(l, d), name(n, d), ty(t, d))
      case SForeignSubtype(l, n, t)     => SForeignSubtype(loc(l, d), name(n, d), ty(t, d))
      case SForeignPrivate(l, ss)       => SForeignPrivate(loc(l, d), ss.map(foreign(_, d)))
    }

    private def term(x: STerm, d: Int): STerm = x match {
      case SVar(n)             => SVar(name(n, d))
      case SLitInt(l, v)       => SLitInt(loc(l, d), v)
      case SLitLong(l, v)      => SLitLong(loc(l, d), v)
      case SLitByte(l, v)      => SLitByte(loc(l, d), v)
      case SLitShort(l, v)     => SLitShort(loc(l, d), v)
      case SLitString(l, v)    => SLitString(loc(l, d), v)
      case SLitChar(l, v)      => SLitChar(loc(l, d), v)
      case SLitFloat(l, v)     => SLitFloat(loc(l, d), v)
      case SLitDouble(l, v)    => SLitDouble(loc(l, d), v)
      case SLitDate(l, v)      => SLitDate(loc(l, d), v)
      case SApp(f, a)          => SApp(term(f, d), term(a, d))
      case SLam(l, ps, b)      => SLam(loc(l, d), ps.map(pat(_, d)), term(b, d))
      case SSig(l, t, a)       => SSig(loc(l, d), term(t, d), ty(a, d))
      case SChain(c)           => SChain(chain(c, d, (t: STerm) => term(t, d)))
      case SNeg(l, m, o)       => SNeg(loc(l, d), sp(m, d), term(o, d))
      case SParen(l, i)        => SParen(loc(l, d), term(i, d))
      case STuple(l, es)       => STuple(loc(l, d), es.map(term(_, d)))
      case STupleSection(l, n) => STupleSection(loc(l, d), n)
      case SCase(l, s, as)     => SCase(loc(l, d), term(s, d), as.map(alt(_, d)))
      case SLet(l, ss, b)      => SLet(loc(l, d), ss.map(stmt(_, d)), term(b, d))
      case SDo(l, ss)          => SDo(loc(l, d), ss.map(doStmt(_, d)))
      case SListLit(l, es, s)  => SListLit(loc(l, d), es.map(term(_, d)), s)
      case SBraceLit(l, es, s) => SBraceLit(loc(l, d), es.map(term(_, d)), s)
      case SRecordLit(l, fs)   => SRecordLit(loc(l, d), fs.map { case (k, v) => (term(k, d), term(v, d)) })
      case SRelEnvelope(l, as) => SRelEnvelope(loc(l, d), as.map(relArrow(_, d)))
      case SHole(l)            => SHole(loc(l, d))
      case SRemember(l, i)     => SRemember(loc(l, d), term(i, d))
      case SErrorTerm(l, m)    => SErrorTerm(loc(l, d), m)
    }

    private def alt(a: SAlt, d: Int): SAlt =
      SAlt(loc(a.loc, d), pat(a.pattern, d), term(a.body, d), a.where.map(where(_, d)))

    private def doStmt(x: SDoStmt, d: Int): SDoStmt = x match {
      case SDoBind(l, b, ar, r) => SDoBind(loc(l, d), pat(b, d), sp(ar, d), term(r, d))
      case SDoExpr(t)           => SDoExpr(term(t, d))
    }

    private def relArrow(x: SRelArrow, d: Int): SRelArrow = x match {
      case SRenameArrow(l, t, f)  => SRenameArrow(loc(l, d), name(t, d), name(f, d))
      case SCombineArrow(l, a, e) => SCombineArrow(loc(l, d), name(a, d), term(e, d))
      case SFilterArrow(e)        => SFilterArrow(term(e, d))
    }

    private def pat(x: SPat, d: Int): SPat = x match {
      case SPVar(n)          => SPVar(name(n, d))
      case SPWildcard(l)     => SPWildcard(loc(l, d))
      case SPLitInt(l, v)    => SPLitInt(loc(l, d), v)
      case SPLitLong(l, v)   => SPLitLong(loc(l, d), v)
      case SPLitByte(l, v)   => SPLitByte(loc(l, d), v)
      case SPLitShort(l, v)  => SPLitShort(loc(l, d), v)
      case SPLitString(l, v) => SPLitString(loc(l, d), v)
      case SPLitChar(l, v)   => SPLitChar(loc(l, d), v)
      case SPLitFloat(l, v)  => SPLitFloat(loc(l, d), v)
      case SPLitDouble(l, v) => SPLitDouble(loc(l, d), v)
      case SPLitDate(l, v)   => SPLitDate(loc(l, d), v)
      case SPApp(c, as)      => SPApp(name(c, d), as.map(pat(_, d)))
      case SPChain(c)        => SPChain(chain(c, d, (p: SPat) => pat(p, d)))
      case SPParen(l, i)     => SPParen(loc(l, d), pat(i, d))
      case SPTuple(l, es)    => SPTuple(loc(l, d), es.map(pat(_, d)))
      case SPList(l, es)     => SPList(loc(l, d), es.map(pat(_, d)))
      case SPAs(l, b, i)     => SPAs(loc(l, d), name(b, d), pat(i, d))
      case SPStrict(l, i)    => SPStrict(loc(l, d), pat(i, d))
      case SPLazy(l, i)      => SPLazy(loc(l, d), pat(i, d))
      case SPSig(l, i, a)    => SPSig(loc(l, d), pat(i, d), ty(a, d))
      case SPError(l, m)     => SPError(loc(l, d), m)
    }

    private def ty(x: STy, d: Int): STy = x match {
      case STyName(n)                => STyName(name(n, d))
      case STyApp(f, a)              => STyApp(ty(f, d), ty(a, d))
      case STyChain(c)               => STyChain(chain(c, d, (t: STy) => ty(t, d)))
      case STyParen(l, i)            => STyParen(loc(l, d), ty(i, d))
      case STyTuple(l, es)           => STyTuple(loc(l, d), es.map(ty(_, d)))
      case STyList(l, e)             => STyList(loc(l, d), e.map(ty(_, d)))
      case STyRowBrace(l, dots, is)  => STyRowBrace(loc(l, d), dots, is.map(ty(_, d)))
      case STyRowBracket(l, dots, is) => STyRowBracket(loc(l, d), dots, is.map(ty(_, d)))
      case STyBanana(l, dots, is)    => STyBanana(loc(l, d), dots, is.map(ty(_, d)))
      case STyForall(l, ks, bs, b)   =>
        STyForall(loc(l, d), ks.map(name(_, d)), bs.map(binder(_, d)), ty(b, d))
      case STyExists(l, bs, b)       =>
        STyExists(loc(l, d), bs.map(binder(_, d)), b.map(ty(_, d)))
      case STySome(l, ks, bs, b)     =>
        STySome(loc(l, d), ks.map(name(_, d)), bs.map(binder(_, d)), ty(b, d))
      case STyError(l, m)            => STyError(loc(l, d), m)
    }
  }
}
