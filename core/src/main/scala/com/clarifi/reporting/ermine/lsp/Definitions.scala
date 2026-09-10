package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Fixity, Global, Idfix, KindSchema, Local, Name, Pretty, Type, V }
import com.clarifi.reporting.ermine.rename.Renamer
import com.clarifi.reporting.ermine.session.{ Phases, TolerantCheck }
import com.clarifi.reporting.ermine.surface.{ SClassStatement, SDatabaseBlock,
  SDataStatement, SFieldStatement, SFixity, SForeign, SForeignBlock, SForeignConstructor,
  SForeignData, SForeignFunction, SForeignMethod, SForeignPrivate, SForeignSubtype,
  SForeignValue, SModule, SName, SPrivateBlock, SStatement, STableStatement, Span }
import scalaparsers.{ Inferred, Loc, Pos }

/** textDocument/definition and hover on the Stage-1 renamer tables
  * (roadmap 4.3; the pre-4.3 walk over a fused re-parse is gone).
  *
  * The renamer already resolved every occurrence: ToBinder joins the
  * binder's def-site SPAN in this file, ToGlobal the session's V for the
  * imported global (relocated to its true definition site by the load).
  * Indexing flattens each occurrence to its span, target, and hover
  * payload; definition is a span hit-test.  Misses answer null, never
  * error.  Hover covers top-level and imported names, the LOCAL binders
  * the check could type (6.2, `TolerantCheck.Result.locals`, joined by
  * def-site), and TYPE names, which hover with their kind.
  */
object Definitions {

  final case class Target(loc: Loc, len: Int)

  /** 6.3: what two occurrences must AGREE ON to be the same name.
    *
    * A `Local` key is a renamer binder id, so it means something only
    * inside the document whose check minted it.  A `GlobalKey` is a
    * canonical `Global` -- the `ToGlobal.origin`, not the `g` the
    * reference was written through, because an alias-imported name and
    * its canonical name ARE the same thing and must find each other
    * across buffers.  `typeLevel` keeps `data Color = Color Int` apart:
    * one `Global`, two different things (the same reason
    * `Occurrence.typeLevel` exists).
    *
    * The key is STORED, not re-derived: the Stage-3 invariant forbids
    * any analysis on a request path, so references/highlight/rename all
    * answer by comparing keys in the index the last check left behind. */
  sealed abstract class Key
  final case class LocalKey(binderId: Int) extends Key
  final case class GlobalKey(origin: Global, typeLevel: Boolean) extends Key

  /** A TERM-level hover payload: the name to print, its type, and — when
    * the type was recovered from an enclosing binding's own type (6.2's
    * argument split) — that binding's type, so the letters of the two
    * hovers agree (`Pretty.prettyTypeIn`, review R-4). */
  final case class TermHover(name: String, ty: Type, scope: Option[Type] = None)

  /** `hover` is a TERM-level payload (a name and its type); `kind` is
    * the TYPE-level one (a name and its kind schema — kinds are not
    * types, and a `Con` carries a `KindSchema`, not a `Type`).  At most
    * one is set; both are rendered on DEMAND, in the request, so an
    * index that is rebuilt on every keystroke never pays for a printer
    * nobody asked for. */
  final case class Occ(line: Int, startCol: Int, len: Int,
                       target: Option[Target], hover: Option[TermHover],
                       kind: Option[(String, KindSchema)] = None,
                       // 6.3: the name this occurrence IS (see Key), the
                       // spelling it is written with, and whether this
                       // position is where the name is INTRODUCED (a
                       // DocumentHighlight Write, the declaration a
                       // references request may include or drop, and the
                       // proof rename has a def-site it is allowed to
                       // touch).
                       key: Option[Key] = None,
                       spelling: String = "",
                       isDef: Boolean = false,
                       // 6.3 fix round (review R2): does the SOURCE at
                       // this position spell the name exactly as
                       // `spelling` says?  A backtick literal
                       // (``wide``), a parenthesised operator ((++)) and
                       // anything else whose written form differs from
                       // its spelling answer false -- and rename refuses
                       // them rather than replace a range it measured
                       // and a form it cannot rebuild.
                       exact: Boolean = true)

  /** One document's stored answer to every navigation request.
    *
    * `version` is the buffer version the index was built from
    * (`Documents.putIndex` stamps it): rename refuses outright when it
    * differs from the document's current version, rather than writing an
    * edit at positions the text no longer has (Decision d).  `renamed`
    * is the renamer's own tables -- frames for the capture test,
    * `moduleTerms` for "is that name already a top level here", the
    * occurrence list for the `Ambiguous` test.  `scopeTerms`/`scopeTypes`
    * are the canonical import maps, held by REFERENCE (no copy is made,
    * and no probe costs more than a hash lookup).  `symbols` is 6.4's
    * hierarchical document-symbol tree, built here on the CHECK path (a
    * walk over statements only, no expression traversal) and rendered to
    * JSON in the request -- so `textDocument/documentSymbol` and
    * `workspace/symbol` are lookups, like every other request. */
  final case class DocIndex(occs: List[Occ],
                            version: Long = 0L,
                            moduleName: String = "",
                            renamed: Renamer.Result =
                              Renamer.Result(Nil, Map(), Nil, Nil),
                            scopeTerms: Map[Local, List[Name]] = Map(),
                            scopeTypes: Map[Local, List[Name]] = Map(),
                            symbols: List[Symbols.Sym] = Nil,
                            // 6.5.  Four references, no copies: completion
                            // answers from the tables the check already
                            // built, and storing them here is what keeps the
                            // request a lookup.
                            //   `locals` is 6.2's def-site -> type map, for
                            //     the detail of a visible local binder;
                            //   `importTypes` is the ModuleScope's own
                            //     `termNames` (the session superset the check
                            //     ran against, siblings included), for the
                            //     detail of an imported name and for
                            //     `Module.`'s exports;
                            //   `cons` is the check env's Con table, for a
                            //     type name's KIND;
                            //   `root` is the module root `Resident.checkFile`
                            //     computed, which is where `import La...`
                            //     looks for the `.e` files of this project;
                            //   `modules` is what THIS check had loaded, which
                            //     is a superset of the resident session's set
                            //     (this file's own imports and their closure --
                            //     `Layout.Scan` is imported by a fixture and is
                            //     in no other list).
                            locals: Map[(Int, Int), TolerantCheck.LocalTy] = Map(),
                            importTypes: Map[Name, V[Type]] = Map(),
                            cons: Map[Global, Type.Con] = Map(),
                            root: String = "",
                            modules: Set[String] = Set(),
                            // 6.6.  Four more references, on the same
                            // terms as 6.5's: a code action answers from
                            // what the check left behind, so what it
                            // needs has to BE here.
                            //   `module` is the surface tree the read
                            //     produced, for the top-level binding
                            //     GROUPS an add-signature action walks
                            //     (which statement has a sig, which
                            //     equation comes first);
                            //   `types` is TolerantCheck's spelling ->
                            //     type map, the same one hover reads;
                            //   `termOrigins`/`typeOrigins` are the
                            //     SESSION's `termNameOrigins`/
                            //     `consOrigins`, which say that a name a
                            //     module re-exports and the name its
                            //     origin defines are one name -- add
                            //     import offers the ORIGIN, and the
                            //     signature scope test is an identity
                            //     test rather than a spelling one.
                            module: Option[SModule] = None,
                            types: Map[String, Type] = Map(),
                            termOrigins: Map[Global, List[Global]] = Map(),
                            typeOrigins: Map[Global, List[Global]] = Map())

  // The per-document indexes live in Documents alongside the buffer text
  // and version (roadmap 5.3): a definition request and the check that
  // built the index must agree on what the file currently says.

  def install(server: Server, ermine: Resident, docs: Documents, log: String => Unit): Unit = {
    // Dispatch is single-threaded by design (roadmap decision 3), so a
    // request that arrives during the ~13s boot would sit behind it and
    // read to the editor as a hang.  Navigation has nothing to say until
    // the session is up, so say it AT ONCE rather than in 13 seconds.
    def ifReady(answer: => Json): Json =
      if (ermine.ready) answer
      else { log("navigation: answering null, session still booting"); Json.Null }

    server.onRequest("textDocument/definition") { params => ifReady {
      val answer = for {
        occ <- occurrenceAt(docs, params)
        tgt <- occ.target
        loc <- location(tgt)
      } yield loc
      answer getOrElse Json.Null
    } }

    server.onRequest("textDocument/hover") { params => ifReady {
      val answer = for {
        occ  <- occurrenceAt(docs, params)
        // A type name hovers with its KIND (6.2), a term with its type;
        // `:kind` and `browse` print a kind schema through
        // `Pretty.ppKindSchema`, and so does this — one printer, one
        // spelling of `forall {k}. k -> k`.
        text <- occ.hover.map(h => h.name + " : " + (h.scope match {
                  case Some(sc) => Pretty.prettyTypeIn(sc, h.ty).toString
                  case None     => Pretty.prettyType(h.ty, -1).toString
                })) orElse
                occ.kind.map(nk => nk._1 + " : " +
                                   Pretty.ppKindSchema(nk._2)(Pretty.Unqualified).runPrec(-1).toString)
      } yield Json.obj("contents" -> Json.obj(
        // A fenced block tagged `ermine` gets the extension's own TextMate
        // grammar applied, so a hovered type is highlighted like source.
        "kind"  -> Json.Str("markdown"),
        "value" -> Json.Str("```ermine\n" + text + "\n```")))
      answer getOrElse Json.Null
    } }
  }

  private def occurrenceAt(docs: Documents, params: Json): Option[Occ] =
    for {
      uri  <- params / "textDocument" flatMap (_ / "uri") flatMap (_.str)
      pos  <- params / "position"
      line <- pos / "line" flatMap (_.int)
      chr  <- pos / "character" flatMap (_.int)
      idx  <- docs index uri
      occ  <- hit(idx, line + 1, chr + 1)  // LSP is 0-based, Pos/Span 1-based
    } yield occ

  /** The occurrence at a 1-based position; public since 6.3, because
    * references, highlight and rename hit-test the very same way
    * definition and hover do -- one answer per position, always. */
  def hit(idx: DocIndex, line: Int, col: Int): Option[Occ] =
    idx.occs
      .filter(o => o.line == line && o.startCol <= col && col < o.startCol + o.len)
      .sortBy(-_.startCol)
      .headOption

  /** `Inferred(p)` is a real source position wearing a report-time
    * wrapper ("inferred from ..."): fields and rows carry it, and a
    * navigation target reads through it. */
  private def positionOf(l: Loc): Option[Pos] = l match {
    case p: Pos       => Some(p)
    case Inferred(p)  => Some(p)
    case _            => None
  }

  /** A Target as an LSP Location.  Public since 6.3: the references set
    * for an imported name includes its def-site, which may be in a file
    * no buffer has open -- a real position all the same. */
  def location(t: Target): Option[Json] = positionOf(t.loc) match {
    case Some(p) if new java.io.File(p.fileName).isFile =>
      val start = Json.obj("line" -> Json.num(p.line - 1), "character" -> Json.num(p.column - 1))
      val end   = Json.obj("line" -> Json.num(p.line - 1), "character" -> Json.num(p.column - 1 + t.len))
      Some(Json.obj(
        "uri"   -> Json.Str(java.nio.file.Paths.get(p.fileName).toUri.toString),
        "range" -> Json.obj("start" -> start, "end" -> end)))
    case _ => None
  }

  private def spanLen(sp: Span): Int =
    if (sp.endLine == sp.startLine && sp.endCol > sp.startCol) sp.endCol - sp.startCol else 1

  /** 1-based (line, column) to character offset over one buffer, built
    * once per index.  Public so the corpus properties can measure a name
    * with the SAME function the index uses (review R2: they used to
    * re-implement the rule inline and were blind to the case it got
    * wrong). */
  final class Lines(val text: String) {
    private val starts: Array[Int] = {
      val b = Array.newBuilder[Int]
      b += 0
      var i = 0
      while (i < text.length) { if (text.charAt(i) == '\n') b += i + 1; i += 1 }
      b.result()
    }
    /** Which lines contain a TAB.  On the 99.99 % that do not, a parser
      * column IS a character index and `locate` is arithmetic; only a
      * tabbed line pays for the walk.  One pass, on the same text the
      * line starts were found in. */
    private val tabby: Array[Boolean] = {
      val a = new Array[Boolean](starts.length)
      var ln = 0
      var i = 0
      while (i < text.length) {
        val ch = text.charAt(i)
        if (ch == '\n') ln += 1 else if (ch == '\t' && ln < a.length) a(ln) = true
        i += 1
      }
      a
    }
    def lineCount: Int = starts.length

    /** The character offset of a PARSER position, and whether a TAB lies
      * between the start of the line and it.
      *
      * A parser column is not a character index: `scalaparsers.Pos.bump`
      * advances a tab to the next multiple of 8
      * (`column + (8 - column % 8)`), so on a tab-indented line the two
      * disagree — `core/examples/GridExample.e` indents four lines with a
      * tab and the naive arithmetic lands seven characters late, which is
      * how the corpus property found this.  The walk below is the
      * parser's own rule.  `sawTab` matters as well as the offset: an LSP
      * range built from a parser column on such a line is in the wrong
      * units for the editor that receives it (the server's position model
      * has been tab-blind since 0.5, and fixing THAT is not this item),
      * so a name behind a tab is never treated as exact and never
      * renamed. */
    def locate(line: Int, col: Int): (Int, Boolean) = {
      if (line < 1 || line > starts.length || col < 1) return (-1, false)
      if (!tabby(line - 1)) {
        val o = starts(line - 1) + col - 1
        return (if (o > text.length) -1 else o, false)
      }
      val start = starts(line - 1)
      val end   = if (line < starts.length) starts(line) else text.length
      var i = start
      var c = 1
      var sawTab = false
      while (c < col && i < end) {
        val ch = text.charAt(i)
        if (ch == '\n' || ch == '\r') return (-1, sawTab)
        if (ch == '\t') { sawTab = true; c += 8 - (c % 8) } else c += 1
        i += 1
      }
      if (c != col) (-1, sawTab) else (i, sawTab)
    }

    /** -1 when the position is not in this text. */
    def offset(line: Int, col: Int): Int = locate(line, col)._1
    /** Offset just past the last character of `line`, newline excluded. */
    def endOfLine(line: Int): Int = {
      if (line < 1 || line > starts.length) return text.length
      var e = if (line < starts.length) starts(line) else text.length
      while (e > starts(line - 1) &&
             (text.charAt(e - 1) == '\n' || text.charAt(e - 1) == '\r')) e -= 1
      e
    }
  }

  /** The extent of the NAME, which is neither the extent of its span nor
    * the length of its spelling.
    *
    * `SurfaceParsers.spanned` brackets a `token`, and a token eats the
    * whitespace after it — so an occurrence's span runs to the start of
    * the NEXT token: `mine` in `let mine = ...` spans five characters,
    * and a name at the end of a line spans onto the next one (where
    * `spanLen` gives up and answers 1).  6.3's first round measured a
    * letter-initial name by its SPELLING instead, which is right for a
    * plain identifier and wrong for a backtick literal — ``wide`` spells
    * `wide` and occupies eight characters, so rename wrote `narrowde``
    * over it (review R2).
    *
    * So measure against the SOURCE: take the span's own region, clipped
    * to its line, and drop the trailing whitespace the token swallowed.
    * That is exact for every form — plain, parenthesised, backticked,
    * qualified — and it also says whether the source spells the name the
    * way `spelling` does, which is what rename needs in order to know it
    * may replace the range with a bare new name. */
  def nameExtent(ls: Lines, sp: Span, spelling: String): (Int, Boolean) = {
    val text = ls.text
    val (off, sawTab) = ls.locate(sp.startLine, sp.startCol)
    if (off < 0) (spanLen(sp), false)
    else {
      val eol = ls.endOfLine(sp.startLine)
      // EXACT: the source at this position literally begins with the
      // spelling.  This is the ordinary case and it is measured by the
      // spelling, NOT by the span -- a token swallows the whitespace AND
      // the line comment after it (`sa  -- ^ select …` is one span), so
      // the span is no measure of a name at all.
      if (spelling.nonEmpty && off + spelling.length <= eol &&
          text.regionMatches(off, spelling, 0, spelling.length))
        (spelling.length, !sawTab)
      // NOT EXACT: the source writes the name in some other form.  Two
      // exist, and both are measured from the source itself.
      else if (off + 1 < eol && text.charAt(off) == '`' && text.charAt(off + 1) == '`') {
        // a ``literal identifier``: through the closing pair, so an
        // inner space or escape is inside the extent
        val close = text.indexOf("``", off + 2)
        if (close < 0 || close + 2 > eol) (math.max(eol - off, 1), false)
        else (close + 2 - off, false)
      } else {
        // a parenthesised operator, or anything else: the run of
        // non-space characters, clipped to the span and to the line
        val span = if (sp.endLine == sp.startLine && sp.endCol > sp.startCol)
                     off + (sp.endCol - sp.startCol) else eol
        val stop = math.min(math.max(span, off + 1), eol)
        var e = off
        while (e < stop && !text.charAt(e).isWhitespace) e += 1
        (math.max(e - off, 1), false)
      }
    }
  }

  /** Build the index for one checked document from the renamer tables. */
  def index(fileName: String, c: Resident#Checked): DocIndex = {
    val env = c.env
    val lines = new Lines(c.contents)

    /** 6.3 fix round (review R1).  `ToGlobal.origin` is "the module I
      * imported this name FROM", not the module that DEFINES it:
      * `ModuleScope.importing` computes `termOrigins0` with the session's
      * origins in it and then returns `localImportsToGlobals(...)`
      * instead, so a re-exported name (`Prelude` exports `Bool`) arrives
      * with `Prelude.not` while `Bool.e`'s own binder keys on
      * `Bool.not` — two keys, two disjoint sets, one name, and a rename
      * from either end that quietly breaks the other.
      *
      * The session's own `termNameOrigins`/`consOrigins` are the
      * re-export chain (`Session.scala:1076`), and the check copy has
      * them.  Chase to the fixpoint HERE, at index time, so the request
      * path stays a lookup (the Stage-3 invariant) — the same
      * greatest-ancestor walk `ModuleScope.collapseNames` does, with a
      * depth cap and a memo, and stopping at an entry that offers more
      * than one ancestor (that is an ambiguity, not a chain).
      *
      * The module's own definitions are unaffected: `Resident.checkFile`
      * scrubs this module out of the env copy, so its own globals have
      * no origin entry and canonicalise to themselves. */
    def canonWith(origins: Map[Global, List[Global]],
                  memo: scala.collection.mutable.HashMap[Global, Global])
                 (g: Global): Global =
      memo.getOrElseUpdate(g, {
        var x = g
        var d = 0
        var going = true
        while (going && d < 32) {
          origins.get(x) match {
            case Some(List(y)) if y != x => x = y; d += 1
            case _                       => going = false
          }
        }
        x
      })
    val termMemo = scala.collection.mutable.HashMap.empty[Global, Global]
    val typeMemo = scala.collection.mutable.HashMap.empty[Global, Global]
    def canonTerm(g: Global): Global = canonWith(env.termNameOrigins, termMemo)(g)
    def canonType(g: Global): Global = canonWith(env.consOrigins, typeMemo)(g)
    def gkey(g: Global, typeLevel: Boolean): GlobalKey =
      GlobalKey(if (typeLevel) canonType(g) else canonTerm(g), typeLevel)
    // fixity declarations are part of the module's global NAMES — the
    // hover bridge from a binder spelling to Local(...).global(name)
    // needs them (a plain Local would miss `(++)`)
    val termFix: Map[String, Fixity] = c.module.statements.collect {
      case SFixity(_, f, false, ops) => ops.map(_.spelling -> f)
    }.flatten.toMap
    def ownGlobal(spelling: String): Global =
      Local(spelling, termFix.getOrElse(spelling, Idfix)).global(c.name)
    // The TYPE namespace has its own fixity declarations (`infixr 5 :+:`
    // with the type flag set), and its own Global bucket.
    val typeFix: Map[String, Fixity] = c.module.statements.collect {
      case SFixity(_, f, true, ops) => ops.map(_.spelling -> f)
    }.flatten.toMap
    def ownTyGlobal(spelling: String): Global =
      Local(spelling, typeFix.getOrElse(spelling, Idfix)).global(c.name)
    def isTypeKind(k: Renamer.BinderKind): Boolean =
      k == Renamer.TyDef || k == Renamer.TyParam ||
      k == Renamer.TyImplicit || k == Renamer.KindParam

    /** The session's own record of a name, term side.  Since the
      * definition site survives installation (Session.primOp keeps its
      * `loc`), this answers navigation as well as hover: data
      * constructors, `field` and `table` declarations and every foreign
      * declaration are installed this way and have nowhere else to point.
      * A Scala-installed builtin still carries Loc.builtin and simply
      * yields no location. */
    def termOf(g: Global): Option[(Target, TermHover)] =
      env.termNames.get(g).map { v =>
        (Target(v.loc, v.name.map(_.string.length).getOrElse(g.string.length)),
         TermHover(label(g), v.extract))
      }

    /** The type side: `data`, `type`, `class`, `field` and `foreign data`
      * all install a Con whose loc is the statement that declared it, so
      * a type occurrence navigates through the con map rather than the
      * term one.  The two namespaces overlap — `data Color = Color Int`
      * gives one Global to both — which is why the occurrence's
      * `typeLevel` flag picks the table instead of a fallback order. */
    def conTarget(g: Global): Option[Target] =
      env.cons.get(g).map(con => Target(con.loc, g.string.length))

    /** 6.2: the KIND of a type name.  Every `Con` carries the kind
      * schema its declaration was inferred at (`Type.Con.schema`), and
      * TolerantCheck's type phase installs this module's OWN cons into
      * the check copy (`Session.addCon`), so imported and own types
      * answer through one table.  A Builtin type atom (`->`, `*`, rho)
      * has no `Con` and stays silent, as it always did. */
    def conHover(g: Global): Option[(String, KindSchema)] =
      env.cons.get(g).map(con => (label(g), con.schema))

    /** The Global one of this module's own type names was installed
      * under: the TYPE fixity bucket, with the term one as the fallback
      * the pre-6.2 code used (for an Idfix name they are the same). */
    def ownTyCon(spelling: String): Global =
      List(ownTyGlobal(spelling), ownGlobal(spelling))
        .find(env.cons.contains) getOrElse ownTyGlobal(spelling)

    def selfTarget(sp: Span): Target =
      Target(Pos(fileName, "", sp.startLine, sp.startCol, false), spanLen(sp))

    // TERM-LEVEL DECLARATION HEADS the renamer keeps no binder for:
    // `field` and `table` names, data constructors, foreign declarations.
    // `collectHeads` records binders for signatures and equations only, so
    // every reference to one of these arrives Unresolved; the surface tree
    // is where their positions are.  The session knows them too (and more
    // precisely, since it resolves what the module actually installed),
    // but only after a check — so this map is what keeps navigation
    // working in fast mode and in a file whose check died.
    val ownDecls = {
      val b = Map.newBuilder[String, Span]
      def head(n: SName): Unit = b += n.spelling -> n.span
      def foreignHeads(f: SForeign): Unit = f match {
        case x: SForeignFunction    => head(x.name)
        case x: SForeignMethod      => head(x.name)
        case x: SForeignValue       => head(x.name)
        case x: SForeignConstructor => head(x.name)
        case x: SForeignSubtype     => head(x.name)
        case x: SForeignPrivate     => x.statements.foreach(foreignHeads)
        case _: SForeignData        => ()   // a TYPE head: a TyDef binder has it
      }
      def go(st: SStatement): Unit = st match {
        case x: SFieldStatement       => x.names.foreach(head)
        case x: STableStatement       => x.names.foreach(head)
        case x: SDataStatement        => x.constructors.foreach(cd => head(cd.name))
        case SForeignBlock(_, items)  => items.foreach(foreignHeads)
        case SPrivateBlock(_, ss)     => ss.foreach(go)
        case SDatabaseBlock(_, _, ss) => ss.foreach(go)
        case x: SClassStatement       => x.body.foreach(go)
        case _ => ()
      }
      c.module.statements.foreach(go)
      b.result()
    }

    // 6.3: an occurrence is the DEF-SITE when it sits exactly where the
    // binder table says the name is introduced.  For a sig+equations
    // group that is the LAST equation (the renamer's own rule), so an
    // earlier equation head reads as a use; every one of them is still
    // in the references set and every one is still edited by a rename.
    def isDefSite(sp: Span, b: Renamer.BinderInfo): Boolean =
      sp.startLine == b.defSite.startLine && sp.startCol == b.defSite.startCol

    val occs = c.renamed.occurrences.flatMap { o =>
      val sp = o.span
      val (nlen, nexact) = nameExtent(lines, sp, o.spelling)
      o.resolution match {
        case Renamer.ToBinder(id) =>
          c.renamed.binders.get(id).map { b =>
            val hover =
              // 5.4: the module's own types come from the tolerant check,
              // not from the session — the editor path no longer runs a
              // real load to put them there.
              if (b.kind == Renamer.TopLevel)
                c.types.get(b.spelling).map(t => TermHover(label(ownGlobal(b.spelling)), t))
              // 6.2: a LOCAL binder joins the check's `locals` by its
              // def-site.  A local is spelled as the source spells it —
              // it has no module to qualify it with.  A binder the check
              // could not type (a component that died, fast mode, or a
              // binder kind the collection cannot reach — see
              // TolerantCheck.collectLocals) is simply absent, and hover
              // answers null rather than guessing.
              else if (isTypeKind(b.kind)) None
              else c.locals.get((b.defSite.startLine, b.defSite.startCol))
                     .map(l => TermHover(b.spelling, l.ty, l.scope))
            // 6.2: a mention of one of THIS module's own type names
            // resolves to its TyDef binder, so its kind must come from
            // here as well as from the declaration head below — the two
            // must not disagree about the same name.  A type VARIABLE
            // (TyParam/TyImplicit/KindParam) has no Con and stays null.
            val kindHov =
              if (b.kind == Renamer.TyDef) conHover(ownTyCon(b.spelling)) else None
            // 6.3 KEY.  A top level and a `data`/`type`/`class` head are
            // GLOBAL names -- a sibling buffer's mention of one resolves
            // to the very same canonical Global -- so they key on that,
            // not on the binder id no other document has ever heard of.
            val key =
              if (b.kind == Renamer.TopLevel) gkey(ownGlobal(b.spelling), false)
              else if (b.kind == Renamer.TyDef) gkey(ownTyCon(b.spelling), true)
              else LocalKey(id)
            Occ(sp.startLine, sp.startCol, nlen,
                Some(selfTarget(b.defSite)), hover, kindHov,
                Some(key), o.spelling, isDefSite(sp, b), nexact)
          }
        case Renamer.ToGlobal(g, _, origin) if o.typeLevel =>
          // `Builtin` type/kind atoms (->, *, rho ...) have no Con and no
          // source file; they answer null, as they always did.
          conTarget(g).map(t => Occ(sp.startLine, sp.startCol, nlen,
                                    Some(t), None, conHover(g),
                                    Some(gkey(origin, true)), o.spelling,
                                    false, nexact))
        case Renamer.ToGlobal(g, _, origin) =>
          termOf(g).map { case (t, h) =>
            Occ(sp.startLine, sp.startCol, nlen, Some(t), Some(h), None,
                Some(gkey(origin, false)), o.spelling, false, nexact) }
        case Renamer.Unresolved(spelling) =>
          // Every name declared but not BOUND lands here — see ownDecls.
          // A genuinely undefined name is in none of these tables and
          // stays silent, which is what makes the miss case honest.
          if (o.typeLevel) {
            val g = ownTyCon(spelling)
            conTarget(g).map(t => Occ(sp.startLine, sp.startCol, nlen,
                                      Some(t), None, conHover(g),
                                      Some(gkey(g, true)), o.spelling,
                                      false, nexact))
          } else {
            val g = ownGlobal(spelling)
            val session = termOf(g)
            val tgt = session.map(_._1) orElse ownDecls.get(spelling).map(selfTarget)
            val hov = session.map(_._2) orElse
                      c.types.get(spelling).map(t => TermHover(label(g), t))
            // A name DECLARED but not BOUND (a constructor, a field, a
            // table, a foreign) is one of this module's own globals, and
            // its mentions must find its declaration head below.
            if (tgt.isEmpty && hov.isEmpty) None
            else Some(Occ(sp.startLine, sp.startCol, nlen, tgt, hov, None,
                          Some(gkey(g, false)), o.spelling, false, nexact))
          }
        case _ => None  // ambiguous: no navigation
      }
    }

    // The declaration heads themselves.  An equation head is an
    // occurrence of its own binder, so `f` in `f x = ...` already hovers
    // and navigates; the heads above are not occurrences at all, and
    // answered nothing where the very same name a line below answered its
    // type.  They point at themselves and hover with their declared type.
    // Spans an occurrence already covers are left to it (`dedup` keeps the
    // first entry per position).
    val headOccs = ownDecls.toList.map { case (spelling, sp) =>
      val g = ownGlobal(spelling)
      val session = termOf(g)
      val (l, x) = nameExtent(lines, sp, spelling)
      Occ(sp.startLine, sp.startCol, l, Some(selfTarget(sp)),
          session.map(_._2) orElse c.types.get(spelling).map(t => TermHover(label(g), t)),
          None, Some(gkey(g, false)), spelling, true, x)
    }

    // The operator named in `infixl 6 <+>` is a mention of the definition
    // below it, not a declaration of its own.
    val fixityOccs = c.module.statements.collect {
      case SFixity(_, _, tyLevel, ops) => ops.flatMap { n =>
        val g = ownGlobal(n.spelling)
        val tgt =
          if (tyLevel) conTarget(g)
          else (c.renamed.moduleTerms.get(n.spelling).flatMap(c.renamed.binders.get)
                  .map(b => selfTarget(b.defSite))
                orElse termOf(g).map(_._1)
                orElse ownDecls.get(n.spelling).map(selfTarget))
        val hov = if (tyLevel) None
                  else termOf(g).map(_._2) orElse
                       c.types.get(n.spelling).map(t => TermHover(label(g), t))
        // 6.3: the fixity line is a MENTION, so a rename of the operator
        // it names would have to edit it.  Renaming operators is refused
        // outright (References, refusal ii), so this key earns its keep
        // for references and highlight rather than for rename.
        val key = gkey(if (tyLevel) ownTyGlobal(n.spelling) else g, tyLevel)
        val (l, x) = nameExtent(lines, n.span, n.spelling)
        if (tgt.isEmpty && hov.isEmpty) None
        else Some(Occ(n.span.startLine, n.span.startCol, l,
                      tgt, hov, None, Some(key), n.spelling, false, x))
      }
    }.flatten

    // IMPORTS.  `import Layout.Scan` names a file the session has already
    // read; without this the one navigable thing at the top of every
    // module answers null.  loadedFiles maps the source back to the module
    // name it defined, so invert it and land on line 1.
    val fileOfModule: Map[String, String] =
      env.loadedFiles.foldLeft(Map.empty[String, String]) {
        case (m, (src, mod)) => if (m.contains(mod)) m else m + (mod -> src.toString)
      }
    val importOccs = c.module.header.imports.flatMap { imp =>
      fileOfModule.get(imp.module).map { f =>
        val sp = imp.moduleSpan
        Occ(sp.startLine, sp.startCol, spanLen(sp),
            Some(Target(Pos(f, "", 1, 1, false), 0)), None)
      }
    }

    // The type-side heads (`data`, `type`, `class`, `field`, `foreign
    // data`) are all TyDef binders, and a binder's def-site IS the head's
    // span — so navigating to itself is what the binder table already
    // says.  Since 6.2 they hover with their KIND, the same way a
    // mention of the name a line below does.
    val tyHeadOccs = c.renamed.binders.values.collect {
      case b if b.kind == Renamer.TyDef =>
        val d = b.defSite
        val (l, x) = nameExtent(lines, d, b.spelling)
        Occ(d.startLine, d.startCol, l, Some(selfTarget(d)), None,
            conHover(ownTyCon(b.spelling)),
            Some(gkey(ownTyCon(b.spelling), true)), b.spelling, true, x)
    }

    // 6.2: a LOCAL binder's own def-site.  An equation head (a `let` or
    // `where` binding, top level or nested) IS an occurrence of its own
    // binder and is covered above; a PATTERN binder is not an occurrence
    // at all (`Renamer.patternBinders` records a binder and no
    // occurrence), so without this the one place a reader most expects a
    // type — where the name is introduced — answered nothing.  `dedup`
    // leaves any position a real occurrence already covers alone.
    // 6.3 CHANGED THE FILTER: every local binder gets its def-site Occ,
    // typed or not.  6.2 kept only the ones a hover could answer, which
    // left highlight and rename unable to hit the very position a reader
    // clicks -- where the name is introduced.  An untyped one still
    // hovers null (no `hover`, no `kind`), so no hover answer moves; what
    // it gains is a KEY.  TYPE variables (forall/data args, kind braces)
    // are in too: they are binders with uses, and a highlight of `a`
    // inside one signature is exactly as useful as one of a value.
    val localDefOccs = c.renamed.binders.values.collect {
      case b if b.kind != Renamer.TopLevel && b.kind != Renamer.TyDef &&
                b.defSite.startLine > 0 =>
        val d = b.defSite
        val (dl, dx) = nameExtent(lines, d, b.spelling)
        Occ(d.startLine, d.startCol, dl, Some(selfTarget(d)),
            c.locals.get((d.startLine, d.startCol))
              .map(t => TermHover(b.spelling, t.ty, t.scope)),
            None, Some(LocalKey(b.id)), b.spelling, true, dx)
    }

    // 6.3: the names in an `import M using (a, b)` list.  They are
    // MENTIONS of M's definitions -- a rename of one has to edit them or
    // the importing file stops compiling -- and until now they were in no
    // table at all.  The canonical Global is chased the way the renamer
    // chases it (`Renamer.originOf` over `termOrigins`), but a name that
    // is USED in this file already has its origin in an occurrence, and
    // that answer is exact (it went through the renamer itself), so it
    // wins.  GAP, stated rather than papered over: an OPERATOR item is
    // written `(<+>)` -- parens in the spelling, fixity not recoverable
    // here -- so operator import items are not indexed.  Rename refuses
    // operators outright, so nothing rename does depends on it; a
    // references request on an operator misses its import-list mentions.
    val originOfUse: Map[(String, String, Boolean), Global] =
      c.renamed.occurrences.foldLeft(Map.empty[(String, String, Boolean), Global]) {
        case (m, o) => o.resolution match {
          case Renamer.ToGlobal(g, _, origin) =>
            m.updated((g.module, g.string, o.typeLevel), origin)
          case _ => m
        }
      }
    def chase(origins: Map[Global, List[Global]], g: Global): Global = {
      var x = g
      var d = 0
      var going = true
      while (going && d < 32) {
        origins.get(x) match {
          case Some(List(y)) if y != x => x = y; d += 1
          case _                       => going = false
        }
      }
      x
    }
    val importItemOccs = c.module.header.imports.flatMap { imp =>
      imp.items.toList.flatMap(_._2).flatMap { it =>
        val sp = it.name.span
        val spelling = it.name.spelling
        if (spelling.startsWith("(")) None       // an operator item; see above
        else {
          val g = Local(spelling, Idfix).global(imp.module)
          val origin = originOfUse.getOrElse((imp.module, spelling, it.isType),
            chase(if (it.isType) c.scope.typeOrigins else c.scope.termOrigins, g))
          val (l, x) = nameExtent(lines, sp, spelling)
          Some(Occ(sp.startLine, sp.startCol, l, None, None, None,
                   Some(gkey(origin, it.isType)), spelling, false, x))
        }
      }
    }

    // 6.4: the document symbol tree.  It reads the SURFACE statements and
    // the types this check knows -- `TolerantCheck.types` for the module's
    // own top levels, the session's `termNames` for the names a check
    // INSTALLS rather than binds (constructors, `field`, `table`,
    // `foreign`) -- and nothing else.  A broken statement is an
    // `SErrorStatement` and yields no symbol; its healthy neighbours do.
    // 7.0(h): the symbol tree's own share of the index build, split out
    // because the item's table asks for it.  Inert unless
    // -Dermine.lsp.phases=true.
    val tSyms = Phases.now
    val syms = Symbols.build(c.module, lines,
      spelling => c.types.get(spelling) orElse
                  env.termNames.get(ownGlobal(spelling)).map(_.extract))
    Phases.add("index.symbols", tSyms)

    DocIndex(dedup(occs ++ headOccs ++ fixityOccs ++ tyHeadOccs ++
                   localDefOccs ++ importOccs ++ importItemOccs),
             0L, c.name, c.renamed, c.scope.canonicalTerms, c.scope.canonicalTypes,
             syms,
             // 6.5: four references to tables this check already holds.
             // Nothing is walked, copied or rendered here -- completion is
             // a request-time filter over them.
             c.locals, c.scope.termNames, env.cons, c.root, env.loadedModules.keySet,
             // 6.6: four more references to tables this check already
             // holds -- the surface tree, the inferred types, and the
             // session's two origin maps.
             Some(c.module), c.types, env.termNameOrigins, env.consOrigins)
  }

  /** First entry wins per start position: a real occurrence outranks the
    * declaration-head and fixity-mention entries appended after it, which
    * are fallbacks for positions no occurrence covers. */
  private def dedup(os: List[Occ]): List[Occ] = {
    val seen = scala.collection.mutable.HashSet.empty[(Int, Int)]
    os.filter(o => seen.add((o.line, o.startCol)))
  }

  private def label(g: Global): String = g.module + "." + g.string
}
