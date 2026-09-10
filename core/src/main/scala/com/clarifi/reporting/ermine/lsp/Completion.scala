package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Global, Name, Pretty, Type }
import com.clarifi.reporting.ermine.rename.Renamer
import com.clarifi.reporting.ermine.surface.{ Lexer, SurfaceParsers }

/** textDocument/completion (tracker/LSP-ROADMAP.md, Stage 3 item 6.5).
  *
  * NOTHING HERE ANALYSES ANYTHING, the Stage-3 invariant.  An answer is
  * built from exactly two things:
  *
  *  1. THE LAST CHECK'S TABLES, stored in `Definitions.DocIndex`: the
  *     renamer's `frames` (through `Renamer.Result.scopeAt`, the
  *     scope-at-position layer 4.2 built and deferred "to where a
  *     consumer exists" — this is that consumer), its `binders` for the
  *     kind of each visible name, 6.2's `locals` for a local's type,
  *     6.4's symbol tree for the module's own declarations and their
  *     types, and the `ModuleScope` the check built for the names this
  *     file's imports put in scope.
  *  2. THE CURRENT BUFFER TEXT, read LEXICALLY and only on the request's
  *     own line: the word prefix at the cursor, and whether the cursor
  *     stands after `import `, after `Module.`, or in a comment or a
  *     string literal.
  *
  * No parse, no rename, no check and no inference is reachable from the
  * handler.  STALENESS IS THE PRICE AND IS ACCEPTED: a binder typed since
  * the last debounced check is in no table yet, so it is not offered
  * until that check lands (docs/lsp.md says so).  The alternative —
  * checking on a completion request — is a second's wait per keystroke,
  * which is the thing this whole stage exists not to do.
  *
  * OPERATORS ARE NOT COMPLETED.  The prefix is scanned as an IDENTIFIER
  * (letter, then `Lexer.isTailChar`s), so a cursor after `<+` has an
  * empty prefix and completes names, not operators: an operator's
  * spelling is not what the source writes it as in every position
  * (`(<+>)` in a reference, `<+>` in a fixity line), and offering one
  * would mean guessing which form to insert.
  */
object Completion {

  // ------------------------------------------------------ CompletionItemKind
  // The LSP enumeration, named rather than left as bare numbers.
  val KMethod        = 2
  val KFunction      = 3
  val KConstructor   = 4
  val KField         = 5
  val KVariable      = 6
  val KClass         = 7
  val KInterface     = 8
  val KModule        = 9
  val KProperty      = 10
  val KEnum          = 13
  val KKeyword       = 14
  val KTypeParameter = 25

  /** How many items one answer may carry.  A prefix-filtered answer is
    * normally far under it; when it bites, `isIncomplete` is true and the
    * client re-asks as the user types (§6.5.5 in the report). */
  val Cap = 300

  // ------------------------------------------------------------- the context

  /** What the buffer text says the cursor is in.  Decided by a LEXICAL
    * scan of the CURRENT LINE and nothing else (6.5.1). */
  sealed abstract class Ctx { def prefix: String }
  /** An ordinary name position: locals, own declarations, imports, keywords. */
  final case class Names(prefix: String) extends Ctx
  /** `import ` / `export ` — a module name is being typed, dots included. */
  final case class Modules(prefix: String) extends Ctx
  /** `Module.` — that module's exports.  `start` is the 0-based column
    * the dotted MODULE PATH begins at: an item completed here replaces
    * `Module.prefix` with the bare name (review F-2), so the range it
    * edits has to reach back that far. */
  final case class Qualified(module: String, prefix: String, start: Int) extends Ctx
  /** Inside a comment or a string literal: the answer is `[]`. */
  case object Dead extends Ctx { def prefix = "" }

  /** An identifier character, the surface lexer's own notion
    * (`ParsingUtil.tailChar`, via `Lexer.isTailChar`). */
  private def isWordChar(c: Char): Boolean = Lexer.isTailChar(c)

  /** The text of one 0-based LSP line, its line terminator excluded.  A
    * scan, not an index: one completion reads one line, and building a
    * whole-buffer line table per keystroke would cost more than the
    * answer does. */
  def lineText(text: String, line: Int): String = {
    var i = 0
    var n = 0
    while (n < line && i < text.length) {
      val j = text.indexOf('\n', i)
      if (j < 0) { i = text.length; n = line } else { i = j + 1; n += 1 }
    }
    if (n < line) ""
    else {
      val e = text.indexOf('\n', i)
      val end = if (e < 0) text.length else e
      val stop = if (end > i && text.charAt(end - 1) == '\r') end - 1 else end
      text.substring(i, stop)
    }
  }

  /** Is the cursor inside a line comment, a block comment opened on this
    * line, or a string literal?
    *
    * LINE-LOCAL, deliberately and with a stated gap: a `{- ... -}` block
    * comment opened on an EARLIER line, and a string literal that spans
    * lines, are not seen — the rule is "the current line only", and a
    * whole-buffer scan on every keystroke is a cost this item's latency
    * bar does not have room for.  Everything a completion actually meets
    * (a trailing `-- comment`, a `"string"` argument, a `{- … -}` on one
    * line) is covered. */
  def dead(line: String, col: Int): Boolean = {
    val c = math.max(0, math.min(col, line.length))
    var i = 0
    var inStr = false
    var depth = 0
    while (i < c) {
      val ch = line.charAt(i)
      if (inStr) {
        if (ch == '\\') i += 1
        else if (ch == '"') inStr = false
      } else if (depth > 0) {
        if (ch == '-' && i + 1 < line.length && line.charAt(i + 1) == '}') { depth -= 1; i += 1 }
        else if (ch == '{' && i + 1 < line.length && line.charAt(i + 1) == '-') { depth += 1; i += 1 }
      } else if (ch == '"') inStr = true
      else if (ch == '-' && i + 1 < line.length && line.charAt(i + 1) == '-') return true
      else if (ch == '{' && i + 1 < line.length && line.charAt(i + 1) == '-') { depth += 1; i += 1 }
      i += 1
    }
    inStr || depth > 0
  }

  /** THE CONTEXT RULES (6.5.1), on one line of text and a 0-based column.
    *
    * Public and free of every server type so the properties can call the
    * shipped function rather than restate its rule. */
  def contextAt(line: String, col: Int): Ctx = {
    val c = math.max(0, math.min(col, line.length))
    if (dead(line, c)) Dead
    else {
      // (A) a module name is being typed after `import` / `export`: the
      // whole dotted text is the prefix, because a module name is one
      // token to a reader even though it has dots in it.
      val lead = line.substring(0, c)
      val imp = "^\\s*(import|export)\\s+([A-Za-z0-9_.']*)$".r
      imp.findFirstMatchIn(lead) match {
        case Some(m) => Modules(m.group(2))
        case None =>
          var s = c
          while (s > 0 && isWordChar(line.charAt(s - 1))) s -= 1
          val prefix = line.substring(s, c)
          // (B) `Module.`, `Module.Sub.`: every segment upper-initial,
          // and the whole path preceded by something that is not an
          // identifier character (so `x.y` and `foo.Bar.` are not module
          // paths).
          if (s > 0 && line.charAt(s - 1) == '.') moduleBefore(line, s - 1) match {
            case Some((mod, at)) => Qualified(mod, prefix, at)
            case None            => Names(prefix)
          }
          else Names(prefix)
      }
    }
  }

  /** The dotted upper-initial module path ending at the '.' at `dot`,
    * with the column it BEGINS at. */
  private def moduleBefore(line: String, dot: Int): Option[(String, Int)] = {
    var segs: List[String] = Nil
    var i = dot
    var at = dot
    var going = true
    while (going) {
      var s = i
      while (s > 0 && isWordChar(line.charAt(s - 1))) s -= 1
      if (s >= i || !line.charAt(s).isUpper) { going = false; segs = Nil }
      else {
        segs = line.substring(s, i) :: segs
        at = s
        if (s > 0 && line.charAt(s - 1) == '.') i = s - 1
        else { going = false; if (s > 0 && isWordChar(line.charAt(s - 1))) segs = Nil }
      }
    }
    if (segs.isEmpty) None else Some((segs.mkString("."), at))
  }

  // --------------------------------------------------------------- the items

  /** One offered name.  `tier` is the ranking class (0 locals, 1 own,
    * 2 imported, 3 keywords) and `ci` says the prefix matched only
    * case-insensitively, which ranks it below every exact-case match of
    * its own tier.
    *
    * `detail` IS A THUNK, and that is a latency decision, not a style:
    * the candidate set is every name in scope (a Prelude-importing file
    * has thousands), and rendering a type costs a `Pretty` run.  Building
    * the list must therefore not print anything -- only the items that
    * survive the prefix filter and the cap are ever rendered, at most
    * `Cap` of them, in `itemJson`. */
  final case class Item(label: String, kind: Int, detail: () => Option[String],
                        tier: Int, ci: Boolean) {
    def sortText: String = tier.toString + (if (ci) "1" else "0") + label.toLowerCase
  }

  private val noDetail: () => Option[String] = () => None
  private def some(s: => String): () => Option[String] = () => Some(s)

  private def isPlainName(s: String): Boolean =
    s.nonEmpty && s.charAt(0).isLetter && s.substring(1).forall(isWordChar)

  private def ty(t: Type): String = Pretty.prettyType(t, -1).toString

  /** 6.4's SymbolKind for one of this module's own declarations, as the
    * CompletionItemKind an editor draws.  The two enumerations are
    * different numbers for the same idea; this is the whole mapping. */
  private def kindOfSym(k: Int): Int = k match {
    case Symbols.KFunction    => KFunction
    case Symbols.KVariable    => KVariable
    case Symbols.KMethod      => KMethod
    case Symbols.KConstructor => KConstructor
    case Symbols.KField       => KField
    case Symbols.KProperty    => KProperty
    case Symbols.KInterface   => KInterface
    case Symbols.KEnum        => KEnum
    case Symbols.KObject      => KVariable   // a `table` is a value
    case _                    => KClass      // Struct, Class: a type name
  }

  /** A visible binder's kind (6.5.2).  A type-level binder — a `forall`
    * variable, a data argument, a kind brace — is a TypeParameter; every
    * value binder is a Variable, because a renamer binder records no
    * arity and Function would be a guess. */
  private def kindOfBinder(k: Renamer.BinderKind): Int = k match {
    case Renamer.TyParam | Renamer.TyImplicit | Renamer.KindParam => KTypeParameter
    case Renamer.TyDef                                            => KClass
    case _                                                        => KVariable
  }

  private def isTypeLevel(k: Renamer.BinderKind): Boolean =
    k == Renamer.TyParam || k == Renamer.TyImplicit || k == Renamer.KindParam

  /** Every name the last check says is visible at this position, in
    * ranking order, BEFORE the prefix filter is applied.  Public so the
    * unfiltered payload can be measured (6.5.5) with the shipped
    * function. */
  def items(idx: Definitions.DocIndex, line: Int, col: Int): List[Item] = {
    val b = List.newBuilder[Item]

    // (1) LOCALS visible at the position, from the renamer's frames.
    // `scopeAt` answers with the module's own top levels in it too (they
    // are the outermost frame), so the binder's KIND is what separates a
    // local from an own top level -- and a top level is ranked with the
    // rest of the module's declarations, not with the locals.
    val scope = idx.renamed.scopeAt(line, col)
    val localNames = scope.toList.flatMap { case (spelling, id) =>
      idx.renamed.binders.get(id).toList.collect {
        case bi if bi.kind != Renamer.TopLevel && bi.kind != Renamer.TyDef =>
          val detail: () => Option[String] =
            if (isTypeLevel(bi.kind)) noDetail
            else () => idx.locals.get((bi.defSite.startLine, bi.defSite.startCol)).map { l =>
              // 6.2's letter agreement: an argument's type is rendered in
              // the letter supply of the binding it was split out of, so
              // the completion and the hover of the same name agree.
              l.scope match {
                case Some(sc) => Pretty.prettyTypeIn(sc, l.ty).toString
                case None     => ty(l.ty)
              }
            }
          Item(spelling, kindOfBinder(bi.kind), detail, 0, ci = false)
      }
    }
    b ++= localNames.filter(i => isPlainName(i.label)).sortBy(_.label)

    // (2) THE MODULE'S OWN DECLARATIONS -- 6.4's symbol tree, which is
    // already every top-level group, constructor, type, field, table and
    // foreign declaration with the type the check gave it.  Containers
    // (an import, a `foreign`/`private`/`database` block) declare no name
    // and are dropped, exactly as workspace/symbol drops them.
    val own = Symbols.flatten(idx.symbols)
      .filterNot(s => s.kind == Symbols.KModule || s.kind == Symbols.KNamespace)
      .map(s => Item(s.name, kindOfSym(s.kind), () => s.ty.map(ty) orElse s.detail, 1, ci = false))
    b ++= own.filter(i => isPlainName(i.label)).sortBy(_.label)
    // ... plus any top level the renamer bound that the symbol tree does
    // not carry (a group whose statement did not parse still binds its
    // head).  Deduped by label below, so a name in both keeps the symbol
    // entry, which is the one with a type.
    b ++= idx.renamed.moduleTerms.keysIterator.filter(isPlainName).toList.sorted
      .map(n => Item(n, KFunction, noDetail, 1, ci = false))

    // (3) THE NAMES THIS FILE'S IMPORTS PUT IN SCOPE -- the very map the
    // renamer resolved references through (`ModuleScope.Scope`'s
    // canonical terms and types), so what is offered is exactly what
    // would resolve.  A term's type comes from the V the scope carries;
    // a type's kind from the Con the check env installed.
    def canonical(ns: List[Name]): Option[Global] = ns match {
      case List(g: Global) => Some(g)
      case _               => None      // ambiguous: no single detail to show
    }
    val impTerms = idx.scopeTerms.toList.collect {
      case (l, ns) if isPlainName(l.string) =>
        val g = canonical(ns)
        val detail = () => g.flatMap(x => idx.importTypes.get(x)).map(v => ty(v.extract))
        val kind = if (l.string.charAt(0).isUpper) KConstructor else KFunction
        Item(l.string, kind, detail, 2, ci = false)
    }
    b ++= impTerms.sortBy(_.label)
    val impTypes = idx.scopeTypes.toList.collect {
      case (l, ns) if isPlainName(l.string) =>
        val detail = () => canonical(ns).flatMap(idx.cons.get).map(c =>
          Pretty.ppKindSchema(c.schema)(Pretty.Unqualified).runPrec(-1).toString)
        Item(l.string, KClass, detail, 2, ci = false)
    }
    b ++= impTypes.sortBy(_.label)

    // (4) KEYWORDS, last.  The surface grammar's own set, not a list of
    // our own.
    b ++= SurfaceParsers.keywords.toList.sorted
      .map(k => Item(k, KKeyword, noDetail, 3, ci = false))

    dedup(b.result())
  }

  /** First entry per LABEL wins, and the list arrives in ranking order --
    * so a local shadowing an import is offered once, as the local, which
    * is what the name at that position MEANS.  In a NAME context a type
    * and a constructor of the same spelling collapse the same way,
    * because the text to insert is identical either way.
    *
    * That last sentence is FALSE in a qualified context (review S-2), and
    * `dedupQualified` is what that branch uses instead: there the item
    * carries an `import M using …` whose form depends on the namespace
    * (`using type Ring` for the type, `using Ring` for the constructor),
    * so collapsing the two hands a TYPE position a term-only import. */
  private def dedup(is: List[Item]): List[Item] = {
    val seen = scala.collection.mutable.HashSet.empty[String]
    is.filter(i => seen.add(i.label))
  }

  /** One item per (label, NAMESPACE) -- `Ring` the constructor and `Ring`
    * the type are two offers with two import forms (review S-2).  We
    * cannot tell a type position from a term one lexically, so both are
    * offered and the kind (Constructor 4 / Class 7) plus the detail (a
    * type / a kind) is what tells them apart in the list. */
  private def dedupQualified(is: List[Item]): List[Item] = {
    val seen = scala.collection.mutable.HashSet.empty[(String, Boolean)]
    is.filter(i => seen.add((i.label, i.kind == KClass)))
  }

  /** The prefix filter, server-side (6.5.2): case-sensitive first, and a
    * case-insensitive prefix match kept BELOW every exact-case match of
    * its own tier rather than dropped -- typing `sort` and being shown
    * `SortOrder` after `sortBy` is what an editor user expects. */
  def matching(is: List[Item], prefix: String): List[Item] = {
    if (prefix.isEmpty) is
    else {
      val lower = prefix.toLowerCase
      is.flatMap { i =>
        if (i.label startsWith prefix) List(i)
        else if (i.label.toLowerCase startsWith lower) List(i.copy(ci = true))
        else Nil
      }
    }
  }

  // ------------------------------------------------------------ module names

  /** The `.e` files under one module root, as module names.  A directory
    * walk, cached per root for a few seconds: it is filesystem IO on a
    * request path (not a parse, not a check), and the alternative --
    * building it once forever -- would never show a module the user
    * creates while the editor is open. */
  private val fsTtlMs = 5000L
  private var fsCache = Map.empty[String, (Long, List[String])]

  def modulesUnder(root: String): List[String] = {
    val now = System.currentTimeMillis
    fsCache.get(root) match {
      case Some((t, ms)) if now - t < fsTtlMs => ms
      case _ =>
        val out = List.newBuilder[String]
        def walk(d: java.io.File, prefix: String, depth: Int): Unit =
          if (depth <= 8) Option(d.listFiles) foreach { fs =>
            fs.sortBy(_.getName) foreach { f =>
              val n = f.getName
              if (f.isDirectory) {
                if (!n.startsWith(".") && n.headOption.exists(_.isUpper))
                  walk(f, prefix + n + ".", depth + 1)
              } else if (n.endsWith(".e") && n.headOption.exists(_.isUpper))
                out += prefix + n.stripSuffix(".e")
            }
          }
        if (root.nonEmpty) walk(new java.io.File(root), "", 0)
        val ms = out.result().distinct
        fsCache = fsCache.updated(root, (now, ms))
        ms
    }
  }

  // ------------------------------------------------- the qualified edits (F-2)

  /** The buffer's import statements, LEXICALLY: (0-based line, module).
    *
    * A scan for a line whose first word is `import` or `export` followed
    * by a dotted name -- the same shape `contextAt` recognises, and no
    * parse.  It reads the CURRENT buffer, so an import the user has just
    * typed counts even though no check has seen it. */
  def importLines(text: String): List[(Int, String, Option[String])] =
    // 6.6 made this scanner richer -- it reads the `using`/`hiding` list
    // and its layout extent too, because an add-import quick fix has to
    // EDIT one -- so there is one scanner and this is its old face.
    QuickFix.imports(text).map(i => (i.line, i.module, i.alias))

  /** How this buffer imports `mod`: `None` = not at all, `Some(None)` =
    * plainly, `Some(Some(a))` = `import M as a`.
    *
    * The alias matters to what a qualified item may INSERT (review S-1).
    * An aliased import puts the module's names in scope ONLY in the affix
    * form -- `ModuleScope`'s `local` calls `Global.localized(as, …)`,
    * which is `name + "_" + alias` -- so under `import Bool as B` the
    * name `not` does not resolve and `not_B` does. */
  def importOf(text: String, mod: String): Option[Option[String]] =
    importLines(text).collectFirst { case (_, m, a) if m == mod => a }

  /** THE EDIT A QUALIFIED ITEM CARRIES, and why it is not just a label
    * (review F-2).
    *
    * A dotted reference does not parse in this fork AT ALL -- `varTerm`
    * and `tyName` try `identTok` before their dotted alternatives, so the
    * `.` in `Bool.not` is read as function composition and the file fails
    * with `unknown operator .` in every position, term, constructor and
    * type alike.  So an item completed in a qualified position must not
    * insert `Bool.not`: its `textEdit` replaces the WHOLE `Module.prefix`
    * span -- from the first character of the dotted path to the cursor --
    * with the BARE name, which is what this grammar reads.
    *
    * When the module is not already imported here, an
    * `additionalTextEdits` entry adds `import M using <name>` after the
    * last import line (after the module header when there are none), so
    * the bare name RESOLVES and the file still checks.  `using` is the
    * form this grammar has (`SurfaceParsers.importStatement`: `using` /
    * `hiding` over a laid-out list); a type takes `using type <name>`.
    * If the module IS already imported, nothing is added -- and if that
    * import carries a `using` list without this name, the insertion will
    * not resolve until the user extends it.  That is 6.6's business (the
    * add-import quick fix edits existing lists); this item does not touch
    * a list it did not write. */
  def importEdit(text: String, ownModule: String, mod: String,
                 label: String, isType: Boolean): Option[Json] = {
    val lines = text.split("\n", -1)
    val imports = importLines(text)
    if (mod == ownModule || imports.exists(_._2 == mod)) None
    else {
      // (the anchor and the terminator below)
      val anchor =
        if (imports.nonEmpty) imports.map(_._1).max
        else lines.indexWhere(l => l.trim.startsWith("module "))
      val at = anchor + 1
      // Match the buffer's own line terminator: 142 of the 161 stdlib
      // modules are CRLF, and a lone \n inserted into one of them would
      // be the only mixed line in the file.
      val eol = if (anchor >= 0 && anchor < lines.length && lines(anchor).endsWith("\r")) "\r\n"
                else "\n"
      val stmt = "import " + mod + " using " + (if (isType) "type " else "") + label + eol
      Some(Json.obj(
        "range" -> Json.obj(
          "start" -> Json.obj("line" -> Json.num(at), "character" -> Json.num(0)),
          "end"   -> Json.obj("line" -> Json.num(at), "character" -> Json.num(0))),
        "newText" -> Json.Str(stmt)))
    }
  }

  /** What one qualified item adds to its JSON: the replacement edit, the
    * import (or nothing), and a `filterText` -- the text the CLIENT is
    * matching, which is the dotted form the user typed, not the bare
    * label the edit inserts.  Without it an editor filters `not` against
    * `Bool.n` and shows nothing. */
  private def qualifiedExtras(text: String, ownModule: String, mod: String,
                              line: Int, start: Int, cursor: Int)(i: Item)
      : List[(String, Json)] = {
    // S-1: under `import M as A` the module's names are in scope ONLY as
    // `name_A`, so that is what an item inserts there -- a bare `not`
    // under `import Bool as B` would not resolve and no import edit
    // would save it (the module IS imported).  The affix rule is
    // `Global.localized`'s, character for character.
    val insert = importOf(text, mod) match {
      case Some(Some(alias)) => i.label + "_" + alias
      case _                 => i.label
    }
    val te = Json.obj(
      "range" -> Json.obj(
        "start" -> Json.obj("line" -> Json.num(line), "character" -> Json.num(start)),
        "end"   -> Json.obj("line" -> Json.num(line), "character" -> Json.num(cursor))),
      "newText" -> Json.Str(insert))
    val add = importEdit(text, ownModule, mod, i.label, i.kind == KClass)
    List("textEdit" -> te, "filterText" -> Json.Str(mod + "." + i.label)) ++
      add.toList.map(e => "additionalTextEdits" -> Json.Arr(List(e)))
  }

  // -------------------------------------------------------------- the wire

  private def itemJson(extras: Item => List[(String, Json)])(i: Item): Json =
    Json.Obj(List("label" -> Json.Str(i.label), "kind" -> Json.num(i.kind),
                  "sortText" -> Json.Str(i.sortText)) ++
             i.detail().toList.map(d => "detail" -> Json.Str(d)) ++
             extras(i))

  private val noExtras: Item => List[(String, Json)] = _ => Nil

  private def listJson(is: List[Item], incomplete: Boolean,
                       extras: Item => List[(String, Json)] = noExtras): Json =
    Json.obj("isIncomplete" -> Json.Bool(incomplete),
             "items" -> Json.Arr(is.map(itemJson(extras))))

  def install(server: Server, ermine: Resident, docs: Documents, log: String => Unit): Unit = {

    server.onRequest("textDocument/completion") { params =>
      val t0 = System.nanoTime
      // 6.5.4: during the ~13s boot there is no index to answer from, and
      // a request must not read as a hang.  The answer is an EMPTY LIST,
      // never null -- a client treats null as "no provider".
      if (!ermine.ready) { log("completion: [] , session still booting"); Json.Arr(Nil) }
      else {
        val site = for {
          uri  <- params / "textDocument" flatMap (_ / "uri") flatMap (_.str)
          d    <- docs get uri
          pos  <- params / "position"
          line <- pos / "line" flatMap (_.int)
          chr  <- pos / "character" flatMap (_.int)
        } yield (d, line, chr)

        site match {
          case None => Json.Arr(Nil)
          case Some((d, line, chr)) =>
            val ctx = contextAt(lineText(d.text, line), chr)
            // The position model is the server's own, everywhere:
            // LSP is 0-based, a Span is 1-based, and a parser column is
            // tab-expanded (ticket E8, inherited by every request since
            // 0.5).  `scopeAt` is asked about the position the WORD
            // starts at -- the position the name being typed occupies,
            // and the one the corpus property pins.
            val wordStart = chr - ctx.prefix.length
            // How many names were in scope BEFORE the prefix filter, for
            // the log: it costs nothing (the candidate list is built
            // either way, and nothing in it is rendered until an item
            // survives the cap) and it is what 6.5.5's payload figure is
            // a measurement of.
            var candidates = -1
            // A qualified answer carries edits (F-2); every other answer
            // is a plain label.
            var extras: Item => List[(String, Json)] = noExtras
            val (out, incomplete) = ctx match {
              case Dead => (Nil, false)
              case Modules(p) =>
                // 6.5.3's three sources, in that order: what the last
                // check of THIS file had loaded (its own imports and
                // their closure -- a superset of the resident set, and
                // the only list `Layout.Scan` is in when a file imports
                // it), the resident session's own modules, the `.e`
                // files under this file's module root, and the open
                // buffers' own module names (a module that exists only
                // as an unsaved buffer).
                val known =
                  d.index.toList.flatMap(_.modules) ++
                  ermine.loadedEnv.toList.flatMap(_.loadedModules.keySet) ++
                  d.index.toList.flatMap(i => modulesUnder(i.root)) ++
                  docs.all.flatMap(_.index.map(_.moduleName))
                val ms = known.distinct.filter(m => m.nonEmpty && m != "Builtin")
                  .filter(_ startsWith p).sorted
                  .map(m => Item(m, KModule, noDetail, 0, ci = false))
                (ms.take(Cap), ms.size > Cap)
              case Qualified(mod, p, start) =>
                val ex = d.index.toList.flatMap(exportsOf(_, docs, mod))
                val ms = matching(dedupQualified(ex.sortBy(_.label)), p)
                extras = qualifiedExtras(
                  d.text, d.index.map(_.moduleName) getOrElse "", mod, line, start, chr)
                (ms.take(Cap), ms.size > Cap)
              case Names(p) =>
                d.index match {
                  // No check of this document has finished yet, so there
                  // is no table to answer from.  `isIncomplete` says so:
                  // a client that took an empty COMPLETE list would cache
                  // it and never ask again, and the first check is a
                  // second away.
                  case None      => (Nil, true)
                  case Some(idx) =>
                    val all = items(idx, line + 1, wordStart + 1)
                    candidates = all.size
                    if (p.isEmpty) {
                      // 6.5.5: an empty prefix answers with what is
                      // LOCAL to this file -- the visible binders and the
                      // module's own declarations -- and says
                      // isIncomplete, so the client asks again as soon as
                      // a character is typed and gets the imports too.
                      // The unfiltered payload is thousands of names and
                      // a megabyte of JSON; the report measures it.
                      val near = all.filter(_.tier <= 1)
                      (near.sortBy(_.sortText).take(Cap), true)
                    } else {
                      val hits = matching(all, p).sortBy(_.sortText)
                      (hits.take(Cap), hits.size > Cap)
                    }
                }
            }
            val ms = (System.nanoTime - t0) / 1000000.0
            log(f"completion: ${d.path.getFileName} ${ctxName(ctx)} " +
                f"prefix='${ctx.prefix}' ${out.size} items" +
                (if (candidates >= 0) " of " + candidates + " in scope" else "") +
                (if (incomplete) " (incomplete)" else "") + f" in $ms%.1f ms")
            listJson(out, incomplete, extras)
        }
      }
    }
  }

  private def ctxName(c: Ctx): String = c match {
    case Dead            => "in a comment or string"
    case Modules(_)      => "module"
    case Qualified(m, _, _) => "qualified " + m
    case Names(_)        => "name"
  }

  /** One module's exports, for `Module.` (6.5.3).  The tables are the
    * ones the CHECK left behind: `ModuleScope`'s `termNames` is the
    * session superset the check ran against, so a module that is loaded
    * but not imported here answers too, and an open SIBLING's own
    * declarations are in it because the check loaded that sibling from
    * its buffer.  An unknown module answers nothing. */
  private def exportsOf(idx: Definitions.DocIndex, docs: Documents,
                        mod: String): List[Item] = {
    val terms = idx.importTypes.toList.collect {
      case (g: Global, v) if g.module == mod && isPlainName(g.string) =>
        Item(g.string, if (g.string.charAt(0).isUpper) KConstructor else KFunction,
             some(ty(v.extract)), 0, ci = false)
    }
    val types = idx.cons.toList.collect {
      case (g, c) if g.module == mod && isPlainName(g.string) =>
        Item(g.string, KClass,
             some(Pretty.ppKindSchema(c.schema)(Pretty.Unqualified).runPrec(-1).toString),
             0, ci = false)
    }
    // An OPEN BUFFER of that module, whose own declarations the resident
    // session has never seen (a new file, or one edited since boot).
    val open = docs.all.flatMap { d =>
      d.index.toList.filter(_.moduleName == mod).flatMap { i =>
        Symbols.flatten(i.symbols)
          .filterNot(s => s.kind == Symbols.KModule || s.kind == Symbols.KNamespace)
          .map(s => Item(s.name, kindOfSym(s.kind), () => s.ty.map(ty) orElse s.detail, 0, ci = false))
      }
    }
    (open ++ terms ++ types).filter(i => isPlainName(i.label))
  }
}
