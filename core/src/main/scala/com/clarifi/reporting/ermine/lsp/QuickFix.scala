package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ AppT, ArrowK, Arrow, ConcreteRho, Exists, Forall,
                                      Global, Kind, Local, Memory, Name, Part, Pretty,
                                      ProductT, Type, VarK, VarT }
import com.clarifi.reporting.ermine.surface.{ ParenOp, ParenPostfixOp, ParenPrefixOp, Plain,
                                              SDatabaseBlock, SEquation, SModule, SName,
                                              SPrivateBlock, SSigStatement, SStatement }

/** textDocument/codeAction (tracker/LSP-ROADMAP.md, Stage 3 item 6.6):
  * two quick fixes, ADD IMPORT and ADD TYPE SIGNATURE.
  *
  * NOTHING HERE ANALYSES ANYTHING, the Stage-3 invariant, and here it
  * bites harder than anywhere else in the stage: a `codeAction` request
  * fires on every cursor move, so an answer that cost a check would cost
  * a check per keystroke.  Decision (e) settles it — the signature fix is
  * offered WITHOUT server-side re-checking, and its correctness is
  * measured ONCE, by the corpus sweep in `tools/SigSweep`, against a
  * ship bar.  An answer is built from exactly two things:
  *
  *  1. THE LAST CHECK'S STORED RESULTS: the diagnostics that check
  *     PUBLISHED, each still paired with the `TolerantCheck.Note` that
  *     produced it (`Documents.Doc.diags`, filled by `Diagnostics.check`
  *     beside the index), the surface tree and the inferred types on the
  *     index, and the `ModuleScope` the check built.
  *  2. THE CURRENT BUFFER TEXT, read LEXICALLY: the import statements
  *     (`imports`), the line a signature would go above, and the line
  *     terminator every inserted line has to match.
  *
  * STALENESS IS REFUSED HERE, not accepted.  Every other request in this
  * server answers from a possibly-stale index because a stale ANSWER is
  * harmless — a hover one keystroke behind is a hover one keystroke
  * behind.  A code action is not an answer, it is an EDIT: a signature
  * inserted at a line the buffer no longer has is corruption, not
  * staleness.  So when the index's version is not the buffer's version
  * (an edit has landed since the last check, and the ~300 ms debounce has
  * not fired yet) the answer is `[]`, with the reason in the log.  This
  * is 6.3's rule for rename, in the shape a speculative request takes:
  * rename REFUSES loudly because the user asked for it, a code action
  * offers nothing because the user did not.
  */
object QuickFix {

  /** An LSP TextEdit in the server's own model: 0-based lines, 0-based
    * CHARACTER indices into the line (not parser columns — every index
    * here is computed by scanning the buffer, so `Definitions.Lines`'s
    * tab expansion never enters). */
  final case class TEdit(sl: Int, sc: Int, el: Int, ec: Int, newText: String) {
    def json: Json = Json.obj(
      "range" -> Json.obj(
        "start" -> Json.obj("line" -> Json.num(sl), "character" -> Json.num(sc)),
        "end"   -> Json.obj("line" -> Json.num(el), "character" -> Json.num(ec))),
      "newText" -> Json.Str(newText))
  }

  /** ONE PUBLISHED DIAGNOSTIC, with its source (6.6.1).
    *
    * The range is the one that WENT OUT — read back off the JSON the
    * publish built, so it cannot drift from what the client shows — and
    * `spelling` is the flag `TolerantCheck.Note` carries for an
    * undefined term (5.4), which is what an add-import action keys on.
    * A read-phase `NewPipeline.Diag` is stored too, with no spelling:
    * nothing offers a fix for one today, but the stored list is what a
    * request matches against and it must be the whole published set. */
  final case class Published(sl: Int, sc: Int, el: Int, ec: Int,
                             message: String, severity: Int,
                             spelling: Option[String], json: Json)

  // ------------------------------------------------------- the buffer's lines

  /** The line terminator this buffer uses, from its FIRST one — 142 of
    * the 161 stdlib modules are CRLF and a lone `\n` inserted into one of
    * them would be its only mixed line.  A file with no terminator at all
    * takes `\n`. */
  def eolOf(text: String): String =
    text.indexOf('\n') match {
      case -1 => "\n"
      case i  => if (i > 0 && text.charAt(i - 1) == '\r') "\r\n" else "\n"
    }

  /** The buffer split on `\n`, each line WITHOUT its `\r`: every column
    * this file computes is an index into one of these, so a CRLF file's
    * indices are the same as an LF file's and the terminator is re-added
    * only when text is inserted. */
  private def linesOf(text: String): Array[String] =
    text.split("\n", -1).map(l => if (l.endsWith("\r")) l.dropRight(1) else l)

  /** THE BUFFER WITH ITS COMMENTS BLANKED OUT, character for character:
    * every `--` line comment, every nesting `{- -}` block comment and
    * nothing else becomes spaces, and the line structure is untouched, so
    * an index into the masked text is an index into the real one.
    *
    * This is not decoration.  `core/src/main/resources/modules/Layout/
    * Scan.e` carries `import Layout.Presentation as P` INSIDE a `{- -}`
    * block at line 84 — a scanner that reads it believes the module is
    * imported twice, skips the fix that would have worked and anchors a
    * new import line inside a comment.  The corpus differential in the
    * sweep is what found it.  String literals are tracked for the same
    * reason: a `--` inside one is not a comment.  This is the surface
    * `Lexer`'s job done coarsely; it does not know layout, and it does
    * not need to. */
  def masked(text: String): String = {
    val a = text.toCharArray
    var i = 0
    var depth = 0
    var inStr = false
    def blank(j: Int): Unit = if (a(j) != '\n') a(j) = ' '
    while (i < a.length) {
      val c = a(i)
      if (inStr) {
        if (c == '\\' && i + 1 < a.length) i += 1
        else if (c == '"' || c == '\n') inStr = false
      } else if (depth > 0) {
        if (c == '{' && i + 1 < a.length && a(i + 1) == '-') { depth += 1; blank(i); i += 1; blank(i) }
        else if (c == '-' && i + 1 < a.length && a(i + 1) == '}') { depth -= 1; blank(i); i += 1; blank(i) }
        else blank(i)
      } else if (c == '"') inStr = true
      else if (c == '-' && i + 1 < a.length && a(i + 1) == '-') {
        while (i < a.length && a(i) != '\n') { blank(i); i += 1 }
        i -= 1
      } else if (c == '{' && i + 1 < a.length && a(i + 1) == '-') {
        depth += 1; blank(i); i += 1; blank(i)
      }
      i += 1
    }
    new String(a)
  }

  // ------------------------------------------------------ the import scanner

  /** One item of a `using` / `hiding` list: `x`, `type X`, `(++)`,
    * `x as y`.  `provides` is the spelling the item puts IN SCOPE, which
    * is the rename when there is one. */
  final case class ImpItem(name: String, isType: Boolean, rename: Option[String],
                           line: Int, startCol: Int, endCol: Int) {
    def provides: String = rename getOrElse name
  }

  /** One import statement, LEXICALLY (6.6.2).
    *
    * `line`..`lastLine` is the statement's extent under the layout rule:
    * a laid-out `using` list continues onto every following line indented
    * deeper than the `import` keyword itself.  `isUsing` is `Some(true)`
    * for `using`, `Some(false)` for `hiding`, `None` for an open import.
    * `insert` is where a new list item goes — just after the last
    * non-blank character of the list, inside the braces when there are
    * any — and is `None` when the statement carries no list or the
    * scanner will not touch it (a `{- -}` anywhere in it). */
  /** The `using` / `hiding` clause of an import, when it has one.  Its
    * three positions are TOTAL: a statement either carries a list, in
    * which case the scanner found all three, or it does not.  (Round one
    * made them `Option`s on `Imp` and carried a `SkipOpaque` reason for
    * the case where they were absent while the clause was present, which
    * the scanner cannot produce -- review R-10.  The shape below makes
    * that unreachable state unrepresentable instead of unreachable.) */
  final case class ImpList(isUsing: Boolean, braced: Boolean, items: List[ImpItem],
                           insert: (Int, Int),
                           clauseStart: (Int, Int), clauseEnd: (Int, Int))

  final case class Imp(line: Int, lastLine: Int, isExport: Boolean, module: String,
                       alias: Option[String], list: Option[ImpList]) {
    def isUsing: Option[Boolean] = list.map(_.isUsing)
    def braced: Boolean          = list.exists(_.braced)
    def items: List[ImpItem]     = list.map(_.items) getOrElse Nil
  }

  private val ImportHead =
    """^(\s*)(import|export)\s+([A-Za-z0-9_.']+)\s*(.*)$""".r

  /** Every import statement of the buffer.
    *
    * THE ASSUMPTIONS, stated because they are the whole of this scanner's
    * soundness: an import statement STARTS ITS LINE (no corpus file, and
    * no fixture, writes `import A; import B` on one line, and no module
    * header in the corpus opens an explicit `{` block), and the list that
    * follows `using`/`hiding` runs to the matching `}` when it is braced
    * and to the end of the layout block when it is not.  Comments are
    * blanked out before any of this runs (`masked`), so the brace matcher
    * never counts a comment's brace and a `{- -}` statement needs no
    * special case. */
  def imports(text: String): List[Imp] = {
    val ls = linesOf(masked(text))
    val out = List.newBuilder[Imp]
    var i = 0
    while (i < ls.length) {
      ImportHead.findFirstMatchIn(ls(i)) match {
        case None => i += 1
        case Some(m) =>
          val indent  = m.group(1).length
          val isExp   = m.group(2) == "export"
          val mod     = m.group(3)
          // The statement's extent: every following line indented deeper
          // than the `import` keyword belongs to it (the layout rule the
          // `laidout` combinator applies to the explicit-import list).
          var last = i
          var j = i + 1
          while (j < ls.length && {
                   val l = ls(j)
                   val t = l.trim
                   t.isEmpty || l.takeWhile(_.isWhitespace).length > indent
                 }) {
            if (ls(j).trim.nonEmpty) last = j
            j += 1
          }
          out += scanOne(ls, i, last, m.start(4) + 0, isExp, mod)
          i = last + 1
      }
    }
    out.result()
  }

  /** The tail of one import statement: `as A`, then `using`/`hiding` and
    * its list. */
  private def scanOne(ls: Array[String], first: Int, last: Int,
                      tailCol: Int, isExport: Boolean, mod: String): Imp = {
    // (line, col) cursor over the statement's text, comments already
    // blanked out by `masked`.
    var ln = first
    var col = tailCol
    def cur: String = ls(ln)
    def atEnd: Boolean = ln > last
    def skipSpace(): Unit = {
      while (!atEnd && (col >= cur.length || cur.charAt(col).isWhitespace)) {
        if (col >= cur.length) { ln += 1; col = 0 } else col += 1
      }
    }
    def word(): Option[(String, Int, Int)] = {
      skipSpace()
      if (atEnd) None
      else {
        val l = cur
        val s = col
        while (col < l.length && !l.charAt(col).isWhitespace && l.charAt(col) != ';' &&
               l.charAt(col) != '{' && l.charAt(col) != '}') col += 1
        if (col == s) { col += 1; Some((l.substring(s, s + 1), s, s + 1)) }
        else Some((l.substring(s, col), s, col))
      }
    }
    // `as A`
    var alias: Option[String] = None
    var save = (ln, col)
    word() match {
      case Some(("as", _, _)) => word() foreach { w => alias = Some(w._1) }
      case _ => { ln = save._1; col = save._2 }
    }
    save = (ln, col)
    val kw = word()
    val isUsing = kw match {
      case Some(("using", _, _))  => Some(true)
      case Some(("hiding", _, _)) => Some(false)
      case _ => { ln = save._1; col = save._2; None }
    }
    if (isUsing.isEmpty)
      Imp(first, last, isExport, mod, alias, None)
    else {
      // The clause starts at the `using`/`hiding` keyword, with the space
      // before it: removing the clause must leave `import M`, not
      // `import M ` with a stranded trailing space.
      val clauseStart = {
        var cs = save._2
        while (cs > 0 && ls(save._1).charAt(cs - 1).isWhitespace) cs -= 1
        (save._1, cs)
      }
      skipSpace()
      val braced = !atEnd && col < cur.length && cur.charAt(col) == '{'
      if (braced) col += 1
      val items = List.newBuilder[ImpItem]
      var closed = false
      var guard = 0
      while (!atEnd && !closed && guard < 10000) {
        guard += 1
        skipSpace()
        if (atEnd) ()
        else if (col < cur.length && cur.charAt(col) == '}') { closed = true }
        else if (col < cur.length && cur.charAt(col) == ';') col += 1
        else word() foreach { w =>
          var name = w._1
          var isTy = false
          var s = w._2
          var e = w._3
          if (name == "type") {
            word() foreach { w2 => isTy = true; name = w2._1; e = w2._3 }
          }
          var rename: Option[String] = None
          val mark = (ln, col)
          word() match {
            case Some(("as", _, _)) => word() foreach { w3 => rename = Some(w3._1); e = w3._3 }
            case _ => { ln = mark._1; col = mark._2 }
          }
          items += ImpItem(strip(name), isTy, rename.map(strip), ln, s, e)
        }
      }
      // WHERE A NEW ITEM GOES: after the last non-blank character of the
      // list — before the closing brace when there is one, at the end of
      // the statement when there is not.  Backing up over whitespace is
      // what turns `{ a; b }` into `{ a; b; s }` rather than `{ a; b ; s}`.
      val endAt =
        if (braced && closed) (ln, col)
        else {
          var k = last
          while (k > first && ls(k).trim.isEmpty) k -= 1
          (k, ls(k).length)
        }
      var (el, ec) = endAt
      while (ec > 0 && ls(el).substring(0, ec).lastOption.exists(_.isWhitespace)) ec -= 1
      while (ec == 0 && el > first) { el -= 1; ec = ls(el).replaceAll("\\s+$", "").length }
      val clauseEnd =
        if (braced && closed) (ln, col + 1)
        else {
          var k = last
          while (k > first && ls(k).trim.isEmpty) k -= 1
          (k, ls(k).replaceAll("\\s+$", "").length)
        }
      Imp(first, last, isExport, mod, alias,
          Some(ImpList(isUsing.get, braced, items.result(), (el, ec), clauseStart, clauseEnd)))
    }
  }

  /** `(++)` in a list names the operator `++`; `` `x` `` names `x`. */
  private def strip(s: String): String = {
    val t = if (s.startsWith("(") && s.endsWith(")") && s.length > 2) s.substring(1, s.length - 1).trim
            else s
    val u = if (t.startsWith("prefix ")) t.substring(7).trim
            else if (t.startsWith("postfix ")) t.substring(8).trim else t
    if (u.startsWith("``") && u.endsWith("``") && u.length > 4) u.substring(2, u.length - 2) else u
  }

  /** HOW A SIGNATURE HEAD IS WRITTEN, from the FORM the source used —
    * not from the `SName`'s fixity, which is the syntactic bucket the
    * lexer read the occurrence under and not a resolved precedence.
    * `Function.e` is the case that settles it: `(`) a f = f a` defines
    * the backtick operator, its `SName` carries `Idfix`, and a
    * fixity-driven rendering wrote ` ````` ` — five backticks, which is
    * not a name in this grammar.  The form says `ParenOp`, and `(`)` is
    * exactly what the source wrote. */
  def headOf(n: SName): Option[String] = n.form match {
    case Plain if n.spelling.nonEmpty && n.spelling.charAt(0).isLetter => Some(n.spelling)
    case Plain           => Some("``" + n.spelling + "``")
    case ParenOp         => Some("(" + n.spelling + ")")
    case ParenPrefixOp   => Some("(prefix " + n.spelling + ")")
    case ParenPostfixOp  => Some("(postfix " + n.spelling + ")")
    case _               => None   // a fixity binder is not a top-level head
  }

  /** How a name is WRITTEN in an import list and in a signature head —
    * the printer's own rule (`Pretty.ppName`), which is the grammar's:
    * an operator is parenthesised, a name that does not start with a
    * letter is double-backticked. */
  def written(spelling: String, fixity: com.clarifi.reporting.ermine.Fixity): String = {
    import com.clarifi.reporting.ermine.{ Idfix, Infix, Postfix, Prefix }
    val q = if (spelling.nonEmpty && spelling.charAt(0).isLetter) spelling else "``" + spelling + "``"
    fixity match {
      case Idfix      => q
      case Prefix(_)  => "(prefix " + spelling + ")"
      case Postfix(_) => "(postfix " + spelling + ")"
      case _          => "(" + spelling + ")"
    }
  }

  // ---------------------------------------------------------- the ADD IMPORT edit

  /** Why an add-import action was NOT offered for a module (the report's
    * table is built out of these, and the log prints them). */
  sealed abstract class Skip { def why: String }
  final case class SkipOwn(m: String)     extends Skip { def why = "it is this module" }
  final case class SkipOpen(m: String)    extends Skip { def why = "already imported openly" }
  final case class SkipAlias(m: String, a: String) extends Skip {
    def why = "imported as `" + a + "`: its names are in scope only in the `_" + a +
              "` affix form, and a second import of one module is a hard error"
  }
  final case class SkipListed(m: String)  extends Skip { def why = "already in the import list" }

  /** THE EDIT, case by case (6.6.2).  Every case is decided from the
    * CURRENT buffer, never from the last check's header: an import the
    * user typed a second ago counts, exactly as it does for 6.5's
    * qualified completion.
    *
    *  - M is this module            -> no action (`SkipOwn`).
    *  - M is not imported           -> INSERT `import M using s` on its
    *      own line after the LAST import, after the `module … where` line
    *      when there are none, at the top when there is no header either.
    *  - M is imported openly        -> no action (`SkipOpen`): every name
    *      M exports is already in scope, so an undefined `s` did not come
    *      from M.
    *  - M is imported WITH AN ALIAS -> no action (`SkipAlias`), whatever
    *      its list says.  `ModuleScope.local` calls `Global.localized`,
    *      so an aliased import puts `s_A` in scope and never `s`; and
    *      `ModuleHeader.imports` DIES on a duplicate module import, so a
    *      second, unaliased `import M using s` is not available either.
    *  - M is imported `using` a list without s -> INSERT `; s` after the
    *      list's last item (THE 6.5 GAP, closed here).
    *  - M is imported `using` a list WITH s    -> no action.
    *  - M is imported `hiding` a list with s   -> REMOVE s from the list;
    *      when s is its only item, remove the whole `hiding` clause.
    *  - M is imported `hiding` a list without s -> no action.
    */
  def addImport(text: String, ownModule: String, mod: String,
                spelling: String, fixity: com.clarifi.reporting.ermine.Fixity)
      : Either[Skip, (String, List[TEdit])] = {
    val item = written(spelling, fixity)
    if (mod == ownModule) Left(SkipOwn(mod))
    else imports(text).find(_.module == mod) match {
      case None =>
        val eol   = eolOf(text)
        val ls    = linesOf(masked(text))
        val imps  = imports(text)
        val anchor =
          if (imps.nonEmpty) imps.map(_.lastLine).max
          else ls.indexWhere(l => l.trim.startsWith("module ") && l.contains(" where"))
        val at = anchor + 1
        Right(("import " + mod + " using " + item,
               List(TEdit(at, 0, at, 0, "import " + mod + " using " + item + eol))))
      case Some(i) if i.alias.isDefined => Left(SkipAlias(mod, i.alias.get))
      case Some(i) => i.list match {
        case None => Left(SkipOpen(mod))
        case Some(l0) if l0.isUsing =>
          if (l0.items.exists(x => !x.isType && x.provides == spelling)) Left(SkipListed(mod))
          else {
            val (l, c) = l0.insert
            Right(("add " + item + " to the " + mod + " import list",
                   List(TEdit(l, c, l, c, "; " + item))))
          }
        case Some(l0) =>
          l0.items.zipWithIndex.find { case (x, _) => !x.isType && x.provides == spelling } match {
            case None => Left(SkipListed(mod))
            case Some((x, n)) =>
              val terms = l0.items
              if (terms.size == 1) {
                // The only hidden name: drop the whole `hiding` clause and
                // leave an open import.
                val (sl, sc) = l0.clauseStart
                val (el, ec) = l0.clauseEnd
                Right(("stop hiding " + item + " from " + mod,
                       List(TEdit(sl, sc, el, ec, ""))))
              } else if (n > 0) {
                val p = terms(n - 1)
                Right(("stop hiding " + item + " from " + mod,
                       List(TEdit(p.line, p.endCol, x.line, x.endCol, ""))))
              } else {
                val nx = terms(1)
                Right(("stop hiding " + item + " from " + mod,
                       List(TEdit(x.line, x.startCol, nx.line, nx.startCol, ""))))
              }
          }
      }
    }
  }

  // -------------------------------------------------- the ADD SIGNATURE edit

  /** One top-level binding GROUP of the surface tree: its spelling, its
    * head as the source has to write it, whether the group already has a
    * signature, and the line its first equation starts on. */
  final case class Group(spelling: String, head: String, hasSig: Boolean,
                         eqLine: Int, eqCol: Int)

  /** The groups of a module's TOP LEVEL, `private` and `database` blocks
    * included (their statements are top-level bindings in their own
    * right).  A `class` body is NOT here: its members are methods, whose
    * signatures the class declares. */
  def groups(m: SModule): List[Group] = {
    val sigs = scala.collection.mutable.HashSet.empty[String]
    val eqs  = scala.collection.mutable.LinkedHashMap.empty[String, (SName, Int, Int)]
    def walk(ss: List[SStatement]): Unit = ss foreach {
      case SSigStatement(_, ns, _) => ns foreach (n => sigs += n.spelling)
      case SEquation(loc, n, _, _, _) =>
        val sp = n.spelling
        val here = (n, loc.span.startLine, loc.span.startCol)
        eqs.get(sp) match {
          case Some((_, l, c)) if l < here._2 || (l == here._2 && c <= here._3) => ()
          case _ => eqs += sp -> here
        }
      case b: SPrivateBlock  => walk(b.statements)
      case b: SDatabaseBlock => walk(b.statements)
      case _ => ()
    }
    walk(m.statements)
    eqs.toList.map { case (sp, (n, l, c)) =>
      Group(sp, headOf(n) getOrElse "", sigs(sp), l, c)
    }
  }

  /** Why a signature was not offered for a group. */
  sealed abstract class SigSkip { def why: String }
  case object NoType        extends SigSkip { def why = "the check gave the group no type" }
  case object HasSig        extends SigSkip { def why = "the group already has a signature" }
  case object NotLineStart  extends SigSkip { def why = "the equation does not start its line" }
  case object BehindTab     extends SigSkip { def why = "the equation is behind a tab (ticket E8)" }
  case object Wrapped       extends SigSkip { def why = "the printer emitted a line break in the type" }
  case object NoHead        extends SigSkip { def why = "the head is not a form a signature can write" }
  final case class Unlexable(names: List[String]) extends SigSkip {
    def why = "the printer writes " + names.mkString(", ") + ", which is not one name to the lexer"
  }
  case object FreeKind      extends SigSkip {
    def why = "the printer emits a kind variable that nothing quantifies"
  }
  case object StarArrow     extends SigSkip {
    def why = "the printer drops the parentheses a nested `* ->` kind needs"
  }
  final case class FieldIdentity(names: List[String]) extends SigSkip {
    def why = "the row field(s) " + names.mkString(", ") +
              " do not round-trip: the name this file writes resolves to a different Global"
  }
  final case class OutOfScope(names: List[String]) extends SigSkip {
    def why = "the type names " + names.mkString(", ") + ", which this file does not import"
  }

  /** Would the printer's spelling of this name LEX as one name?
    * `Native/Throwable.e` renders `Throwable <:_Type.Cast Object`: the
    * `Con`'s own `Global` carries the localized spelling `<:_Type.Cast`,
    * and `Type` then `.` then `Cast` is three tokens, so the signature
    * cannot be written however it is parenthesised.  A dot is the only
    * character that does this (module qualification is the one thing the
    * lexer splits a name on), and the check is exact rather than a
    * character class for that reason. */
  private def lexes(spelling: String): Boolean = !spelling.contains('.')

  /** Does a printed KIND need parentheses the printer will not write?
    *
    * MEASURED, not assumed (the probes are in the item's report): the
    * kind grammar reads `rho -> rho -> *` and `rho -> (* -> *)` and
    * REFUSES `rho -> * -> *` and `* -> * -> *`.  The shape that fails is
    * a NESTED arrow whose left operand is `*`: standing alone `* -> *` is
    * fine, and under another arrow it needs brackets.  `Pretty` writes
    * kind arrows right-associatively without them, so
    * `Relation/Op.e`'s `negate` renders `forall (opr: rho -> * -> *) …`
    * and the signature does not parse.  A PRINTER bug (the ticket); the
    * action refuses rather than emitting it. */
  def starArrow(t: Type): Boolean = {
    def nested(k: Kind): Boolean = k match {
      case ArrowK(_, i, o) => o match {
        case ArrowK(_, i2, _) => i2.isInstanceOf[com.clarifi.reporting.ermine.Star] ||
                                 nested(i) || nested(o)
        case _ => nested(i)
      }
      case _ => false
    }
    def go(x: Type): Boolean = x match {
      case f: Forall    => f.ts.exists(v => nested(v.extract)) || go(f.constraints) || go(f.body)
      case x: Exists    => x.xs.exists(v => nested(v.extract)) || x.constraints.exists(go)
      case AppT(a, b)   => go(a) || go(b)
      case p: Part      => go(p.lhs) || p.rhs.exists(go)
      case Memory(_, b) => go(b)
      case _            => false
    }
    go(t)
  }

  /** Does the rendered type carry a KIND VARIABLE nothing quantifies?
    *
    * `Aggregate.e`'s `avg` renders
    * `forall (op: rho -> * -> *) (r: rho) n. (exists (AsOp: (rho -> * ->
    * *) -> a). AsOp op, PrimitiveNum n) => …` — the `a` in the `exists`
    * binder's KIND is bound by no `forall {…}` group, so the text names a
    * variable that is not there and does not parse.  `Forall.ks` is what
    * the printer writes between braces; an `Exists` quantifies TYPE
    * variables and never kinds, so a kind variable under one has to have
    * been quantified further out.  This is a PRINTER bug (the ticket in
    * the item's report) and the action refuses rather than emitting it. */
  def freeKinds(t: Type): Boolean = {
    def kv(k: Kind): Set[Int] = k match {
      case VarK(v)         => Set(v.id)
      case ArrowK(_, i, o) => kv(i) ++ kv(o)
      case _               => Set()
    }
    def go(x: Type, bound: Set[Int]): Boolean = x match {
      case f: Forall =>
        val b2 = bound ++ f.ks.map(_.id)
        f.ts.exists(v => (kv(v.extract) -- b2).nonEmpty) ||
          go(f.constraints, b2) || go(f.body, b2)
      case x: Exists =>
        x.xs.exists(v => (kv(v.extract) -- bound).nonEmpty) ||
          x.constraints.exists(go(_, bound))
      case AppT(a, b)  => go(a, bound) || go(b, bound)
      case p: Part     => go(p.lhs, bound) || p.rhs.exists(go(_, bound))
      case Memory(_, b) => go(b, bound)
      case _           => false
    }
    go(t, Set())
  }

  /** THE RENDERING (6.6.3).  The SAME printer hover uses,
    * `Pretty.prettyType(t, -1)`, laid out FLAT: `Document.toString`
    * formats at 80 columns, and a wrapped signature is a signature whose
    * continuation lines the layout rule may or may not accept.  Same
    * document, no width limit; a hard break (there is none in type
    * printing today) is caught by `Wrapped` rather than inserted. */
  def render(t: Type): String = {
    val w = new java.io.StringWriter
    Pretty.prettyType(t, -1).format(1 << 20, w)
    w.toString
  }

  /** Every name the rendered type MENTIONS, split by namespace: the type
    * constructors (`Type.Con`) and the record-field names a
    * `ConcreteRho` carries.  Walked over the TYPE, not scraped out of the
    * rendered string — a name in a signature must be checked as the
    * printer will write it, and the printer writes `Global(m, n)` as `n`
    * (`Pretty.Unqualified`). */
  def mentioned(t: Type): (List[Global], List[Name]) = {
    val cons = List.newBuilder[Global]
    val flds = List.newBuilder[Name]
    def go(x: Type): Unit = x match {
      case Type.Con(_, g, _, _)  => cons += g
      case ConcreteRho(_, fs)    => flds ++= fs
      case AppT(a, b)            => go(a); go(b)
      case Memory(_, b)          => go(b)
      case Forall(_, _, _, c, b) => go(c); go(b)
      case Exists(_, _, cs)      => cs foreach go
      case Part(_, l, rs)        => go(l); rs foreach go
      case _: VarT | _: ProductT | _: Arrow => ()
      case _                     => ()
    }
    go(t)
    (cons.result().distinct, flds.result().distinct)
  }

  /** Is `g` reachable in this file's scope under the spelling the printer
    * gives it?  The scope map is the renamer's own
    * (`ModuleScope.Scope.canonicalTypes` / `canonicalTerms`), keyed by
    * the LOCAL name a reference would be written with, so the test is
    * exactly "would this word resolve here" — and it is an IDENTITY test,
    * not a spelling one: the entry has to denote `g` itself, chased
    * through the origins table because `collapseNames` keeps a singleton
    * entry un-collapsed (`Maybe.Maybe` where the `Con` says
    * `Native.Maybe.Maybe`). */
  private def chase(origins: Map[Global, List[Global]], g: Global): Set[Global] = {
    var seen = Set(g)
    var todo = List(g)
    var guard = 0
    while (todo.nonEmpty && guard < 1000) {
      guard += 1
      val h = todo.head; todo = todo.tail
      origins.getOrElse(h, Nil) foreach { o => if (!seen(o)) { seen += o; todo = o :: todo } }
    }
    seen
  }

  /** THE SPELLING THE PRINTER WILL WRITE for a name in a type.
    *
    * `Pretty.ppType`'s operator cases write a GLOBAL infix/prefix/postfix
    * constructor as `n_Module` (Pretty.scala:290-292) whatever the
    * `Qualification` asks for — the affixed reference form, with the
    * module's FULL name as the affix.  `Native/Throwable.e` is the case
    * that matters: `<:` comes from `Type.Cast`, the file imports that
    * module plainly, and the printer writes `Throwable <:_Type.Cast
    * Object`, which the lexer reads as `<:_Type` then `.`.  So the name
    * to test against the file's scope is the PRINTED one, not the
    * Global's own spelling. */
  def printedName(g: Global): String = {
    import com.clarifi.reporting.ermine.Idfix
    if (g.fixity == Idfix) g.string else g.string + "_" + g.module
  }

  def inScope(scope: Map[Local, List[Name]], origins: Map[Global, List[Global]],
              ownModule: String, g: Global): Boolean = {
    val printed = printedName(g)
    (g.module == ownModule && printed == g.string) || {
      val key = Local(printed, g.fixity)
      scope.get(key).exists { ns =>
        val want = chase(origins, g)
        ns.exists {
          case h: Global => (chase(origins, h) & want).nonEmpty
          case l: Local  => l.string == printed
        }
      }
    }
  }

  /** The STRICT version, for a concrete row's FIELD names.
    *
    * A type constructor may be reached through a re-export and still mean
    * the same type, which is what the origins chase above is for.  A
    * FIELD does not behave that way, and the sweep found it:
    * `core/examples/Algebra/Deduplication.e` infers
    * `Mem (|Count, customerId|)` whose fields are
    * `Field.Count.Count` and `Algebra.Deduplication.customerId.customerId`,
    * while the same two words WRITTEN in that file resolve to
    * `Prelude.Count` and `Algebra.Deduplication.customerId` — different
    * Globals, and the checker then refuses to unify the declared row with
    * the inferred one.  So an IMPORTED field has to resolve to ITSELF,
    * with no chase, or the signature is not offered.
    *
    * A field THIS MODULE declares is exempt, and it has to be: a `field`
    * statement mints its own pseudo-module (`Algebra.Deduplication`'s
    * `customerId` is `Global("Algebra.Deduplication.customerId",
    * "customerId")`), the module's own names are not in `canonicalTerms`
    * at all, and the strict test refused 450 insertions over the corpus
    * that check perfectly well — the checker normalises an own field's
    * name and the mismatch never reaches unification.  Measured: with the
    * exemption the corpus loses none of them and still refuses every
    * `Mem (|Count, …|)` the imported half breaks.
    *
    * The exemption is the EXACT own-field shape, `<ownModule>.<name>`,
    * and not a `startsWith` on the module prefix (review R-3): 46 corpus
    * modules import a SUBMODULE of themselves, and a field re-exported
    * that way would otherwise skip the strict test and reach exactly the
    * non-unification it exists to catch. */
  def fieldInScope(scope: Map[Local, List[Name]], ownModule: String, g: Global): Boolean =
    g.module == ownModule || g.module == ownModule + "." + g.string ||
      scope.get(Local(printedName(g), g.fixity)).exists(_.contains(g))

  /** THE SIGNATURE EDIT for one group: `f : <type>` on its own line above
    * the group's first equation, at that equation's own indentation, with
    * the buffer's own terminator (6.6.3).
    *
    * REFUSALS, all of them measured by the sweep: no type, an existing
    * signature, an equation that does not start its line (`f x = 1; g y =
    * 2`), an equation behind a TAB (ticket E8's units problem: a parser
    * column is tab-expanded and an insertion index is not), a rendered
    * type carrying a line break, and a rendered type naming a type or a
    * field this file does not have in scope — that last one is the case
    * the roadmap's item asks about by name, and a refusal is the only
    * honest answer to it: the insertion would not parse. */
  def sigEdit(text: String, g: Group, ty: Type,
              scopeTypes: Map[Local, List[Name]], scopeTerms: Map[Local, List[Name]],
              typeOrigins: Map[Global, List[Global]],
              termOrigins: Map[Global, List[Global]], ownModule: String)
      : Either[SigSkip, (String, TEdit)] =
    if (g.hasSig) Left(HasSig)
    else {
      val ls = linesOf(text)
      val li = g.eqLine - 1
      if (li < 0 || li >= ls.length) Left(NotLineStart)
      else {
        val line = ls(li)
        val ws = line.takeWhile(_.isWhitespace)
        // The equation must START its line: the parser column is
        // tab-expanded, so compare in the parser's units.
        val expanded = ws.foldLeft(1) { (c, ch) => if (ch == '\t') c + 8 - (c % 8) else c + 1 }
        if (ws.contains('\t')) Left(BehindTab)
        else if (expanded != g.eqCol) Left(NotLineStart)
        else {
          val r = render(ty)
          val (cons, flds) = mentioned(ty)
          val unlex = (cons.map(printedName) ++ flds.map(_.string)).filterNot(lexes).distinct
          if (g.head.isEmpty) Left(NoHead)
          else if (r.contains('\n') || r.contains('\r')) Left(Wrapped)
          else if (unlex.nonEmpty) Left(Unlexable(unlex))
          else if (freeKinds(ty)) Left(FreeKind)
          else if (starArrow(ty)) Left(StarArrow)
          else {
            val bad = cons.filterNot(inScope(scopeTypes, typeOrigins, ownModule, _))
              .map(printedName)
            val badF = flds.collect {
              case x: Global if !fieldInScope(scopeTerms, ownModule, x) => x.string
              case x: Local  if !scopeTerms.contains(x)      => x.string
            }
            if (bad.nonEmpty) Left(OutOfScope(bad.distinct))
            else if (badF.nonEmpty) Left(FieldIdentity(badF.distinct))
            else {
              val txt = ws + g.head + " : " + r
              Right((txt, TEdit(li, 0, li, 0, txt + eolOf(text))))
            }
          }
        }
      }
    }

  // ------------------------------------------------------------- the request

  /** Line overlap, which is the rule a code action selects diagnostics
    * by.  An undefined-term note publishes as a CARET (its `Note` has no
    * span, so `Diagnostics.fromReport` recovers the position from the
    * report's `file:line:col:` prefix and makes end = start), so a
    * character-overlap test would only ever fire with the cursor on that
    * exact column.  The rule is therefore: a diagnostic is in range when
    * its LINES intersect the request's — "the fixes for the squiggles on
    * these lines", which is what a user asking for a fix means. */
  private def onLines(p: Published, sl: Int, el: Int): Boolean =
    p.sl <= el && sl <= p.el

  private def sameRange(p: Published, d: Json): Boolean = {
    def at(which: String, f: String) =
      (d / "range" flatMap (_ / which) flatMap (_ / f) flatMap (_.int)) getOrElse -1
    at("start", "line") == p.sl && at("start", "character") == p.sc &&
    at("end", "line") == p.el && at("end", "character") == p.ec &&
    ((d / "message" flatMap (_.str)) getOrElse "") == p.message
  }

  private def action(title: String, kind: String, uri: String, edits: List[TEdit],
                     diags: List[Json], preferred: Boolean): Json =
    Json.Obj(
      List("title" -> Json.Str(title), "kind" -> Json.Str(kind)) ++
      (if (diags.isEmpty) Nil else List("diagnostics" -> Json.Arr(diags))) ++
      (if (preferred) List("isPreferred" -> Json.Bool(true)) else Nil) ++
      List("edit" -> Json.obj("changes" -> Json.Obj(
        List(uri -> Json.Arr(edits.map(_.json)))))))

  /** THE CANDIDATE MODULES for an undefined term `s` (6.6.2).
    *
    * (a) THE SESSION: every `Global` of the check's own `ModuleScope`
    *     `termNames` — the session superset this file was checked against
    *     — whose spelling is `s`, mapped through the session's
    *     `termNameOrigins` to its GREATEST ANCESTOR, so a module that
    *     re-exports a name and the module that defines it are one
    *     candidate and the one offered is the DEFINING module.  (A
    *     re-export would import too; the origin is the answer that does
    *     not depend on which of several re-exporters we happened to
    *     enumerate first.)
    * (b) THE OPEN SIBLINGS: every other open buffer whose last check's
    *     `moduleTerms` declares `s` — a module the resident session has
    *     never loaded is still a candidate while its buffer is open.
    */
  def candidates(idx: Definitions.DocIndex, docs: Documents, s: String): List[String] = {
    val fromSession = idx.importTypes.keysIterator.collect {
      case g: Global if g.string == s => g
    }.toList.flatMap { g =>
      val anc = chase(idx.termOrigins, g).filter(h => chase(idx.termOrigins, h) == Set(h))
      if (anc.isEmpty) List(g.module) else anc.toList.map(_.module)
    }
    val fromOpen = docs.all.flatMap(_.index.toList).filter(_.moduleName != idx.moduleName)
      .filter(_.renamed.moduleTerms.contains(s)).map(_.moduleName)
    (fromSession ++ fromOpen).distinct.filter(_.nonEmpty).sorted
  }

  /** At most this many add-import actions for one name.  A common
    * spelling (`map`, `empty`) is exported by a dozen stdlib modules and
    * a menu of twelve is not a fix; the list is alphabetical and the cap
    * is stated in `docs/lsp.md`. */
  val MaxImports = 8

  def install(server: Server, ermine: Resident, docs: Documents, log: String => Unit): Unit = {

    // ONE MEMO, of the last document a code action was asked about: its
    // unsigned groups and the signature edit each of them yields.  A
    // codeAction fires on every cursor move, and the `source` action has
    // to know how many groups it can serve, which means rendering every
    // unsigned group's type -- 28 ms on `Layout/Report.e` (36 groups, most
    // of them refused) and 0.1 ms once it is cached.  The key is
    // (uri, version), the same pair the staleness refusal already turns
    // on: an edit invalidates it by construction, and dispatch is
    // single-threaded so no lock is needed.
    var memo: Option[(String, Long, List[(Group, Option[(String, TEdit)])])] = None

    server.onRequest("textDocument/codeAction") { params =>
      val t0 = System.nanoTime
      if (!ermine.ready) { log("codeAction: [] , session still booting"); Json.Arr(Nil) }
      else {
        val site = for {
          uri  <- params / "textDocument" flatMap (_ / "uri") flatMap (_.str)
          d    <- docs get uri
          rng  <- params / "range"
          sl   <- rng / "start" flatMap (_ / "line") flatMap (_.int)
          el   <- rng / "end" flatMap (_ / "line") flatMap (_.int)
        } yield (uri, d, sl, el)

        site match {
          case None => Json.Arr(Nil)
          case Some((uri, d, sl, el)) =>
            val only = (params / "context" flatMap (_ / "only") flatMap (_.arr))
              .map(_.flatMap(_.str)).filter(_.nonEmpty)
            def wanted(kind: String): Boolean =
              only.forall(_.exists(k => kind == k || kind.startsWith(k + ".")))
            val clientDiags =
              (params / "context" flatMap (_ / "diagnostics") flatMap (_.arr)) getOrElse Nil

            d.index match {
              case Some(idx) if idx.version == d.version =>
                val out = List.newBuilder[Json]
                // --- (a) ADD IMPORT, one per candidate module.
                val hits = d.diags.filter(p => p.spelling.isDefined && onLines(p, sl, el))
                if (wanted("quickfix")) hits foreach { p =>
                  val s = p.spelling.get
                  val echo = clientDiags.find(sameRange(p, _)) getOrElse p.json
                  val cands = candidates(idx, docs, s)
                  val fixes = cands.flatMap { m =>
                    addImport(d.text, idx.moduleName, m, s,
                              com.clarifi.reporting.ermine.Idfix) match {
                      case Right((title, edits)) => List((title, edits))
                      case Left(sk) => log("codeAction: " + m + " skipped — " + sk.why); Nil
                    }
                  }.take(MaxImports)
                  // `isPreferred` only when there is exactly ONE candidate:
                  // a client's "fix all"/auto-fix takes the preferred action
                  // without asking, and picking one of two modules for the
                  // user is not a thing this server knows how to do.
                  fixes foreach { case (title, edits) =>
                    out += action(title, "quickfix", uri, edits, List(echo), fixes.size == 1)
                  }
                }
                // --- (b) ADD TYPE SIGNATURE, for the group(s) the
                // request's lines touch, and one `source` action for the
                // whole file.
                val sigs = memo match {
                  case Some((u, v, gs)) if u == uri && v == d.version => gs
                  case _ =>
                    val gs = idx.module.toList.flatMap(groups).filterNot(_.hasSig).map { g =>
                      (g, idx.types.get(g.spelling).flatMap { t =>
                        sigEdit(d.text, g, t, idx.scopeTypes, idx.scopeTerms,
                                idx.typeOrigins, idx.termOrigins, idx.moduleName) match {
                          case Right(r) => Some(r)
                          case Left(sk) => log("codeAction: no signature for " + g.spelling +
                                               " — " + sk.why); None
                        }
                      })
                    }
                    memo = Some((uri, d.version, gs))
                    gs
                }
                if (wanted("quickfix")) sigs
                  .filter(x => x._1.eqLine - 1 >= sl && x._1.eqLine - 1 <= el)
                  .foreach { case (_, e) => e foreach { case (txt, te) =>
                      out += action("add signature: " + title(txt), "quickfix", uri,
                                    List(te), Nil, preferred = false)
                    }
                  }
                if (wanted("source")) {
                  val all = sigs.flatMap(_._2.map(_._2))
                  // Sorted by line DESCENDING.  A conforming client
                  // applies a TextEdit[] against the ORIGINAL document, so
                  // order cannot matter to it; a client that applies them
                  // in sequence needs the later lines first or every
                  // insertion after the first lands one line low.
                  if (all.nonEmpty)
                    out += action("add all missing signatures (" + all.size + ")", "source",
                                  uri, all.sortBy(-_.sl), Nil, preferred = false)
                }
                val res = out.result()
                log(f"codeAction: ${d.path.getFileName} lines $sl-$el -> ${res.size} action(s) " +
                    f"in ${(System.nanoTime - t0) / 1e6}%.1f ms")
                Json.Arr(res)
              case Some(idx) =>
                log(s"codeAction: [] , index is v${idx.version} and the buffer is v${d.version}")
                Json.Arr(Nil)
              case None =>
                log("codeAction: [] , this document has not been checked yet")
                Json.Arr(Nil)
            }
        }
      }
    }
  }

  /** A menu entry is one line: the whole signature when it is short, its
    * head and an ellipsis when it is not. */
  private def title(sig: String): String = {
    val one = sig.trim
    if (one.length <= 72) one else one.take(71) + "…"
  }
}
