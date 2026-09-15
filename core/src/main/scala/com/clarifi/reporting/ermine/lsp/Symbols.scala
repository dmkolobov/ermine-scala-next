package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Fixity, Global, Idfix, Infix, Postfix, Prefix,
  Pretty, Type }
import com.clarifi.reporting.ermine.session.SessionEnv
import com.clarifi.reporting.ermine.surface.{ SClassStatement, SConDef, SDatabaseBlock,
  SDataStatement, SEquation, SErrorStatement, SFieldStatement, SFixity, SForeign,
  SForeignBlock, SForeignConstructor, SForeignData, SForeignFunction, SForeignMethod,
  SForeignPrivate, SForeignSubtype, SForeignValue, SModule, SName, SPrivateBlock,
  SSigStatement, SStatement, STableStatement, STypeAlias, Span }
import scalaparsers.{ AssocL, AssocN, AssocR, Pos }

/** textDocument/documentSymbol and workspace/symbol
  * (tracker/LSP-ROADMAP.md, Stage 3 item 6.4).
  *
  * NOTHING HERE ANALYSES ANYTHING, the Stage-3 invariant: the document
  * symbol tree is built ON THE CHECK PATH from the surface tree the
  * tolerant read already produced, stored in `Definitions.DocIndex`
  * beside the occurrence list, and a request renders it to JSON.  The
  * workspace list is built ONCE, the first time a query arrives after
  * boot, from the resident session's own `termNames`/`cons` -- the very
  * tables `textDocument/definition` answers from -- because the resident
  * session is interface-free and never reloads (Decision 5), so that
  * list cannot go stale.  No parse, no rename, no check, no inference is
  * reachable from either handler.
  *
  * THE SHAPE (6.4.1).  One symbol per TOP-LEVEL GROUP, not per
  * statement: a spelling's signature and its equations are ONE thing to
  * a reader and they merge into one symbol, whose `range` runs from the
  * first of them to the end of the last and whose `selectionRange` is
  * the head name of the first EQUATION (the signature's own head when
  * the group has no equation).  Everything else maps by statement kind;
  * the rules are at their use sites below and the report tabulates them.
  *
  * POSITIONS.  `Span` is 1-based half-open and LSP is 0-based, and the
  * conversion here is the one every other range in this server uses --
  * `line - 1`, `Definitions.toCharacter` for the column, and a name's
  * length from `Definitions.nameExtent` over the same
  * `Definitions.Lines`.  Since 7.5 (ticket E8) that conversion is real
  * rather than `± 1`: a parser column is tab-expanded to 8-column stops
  * and an LSP character is not, and the index's own `Lines` is what
  * knows the difference.  This item still does not invent a second
  * position model to sit beside it.
  */
object Symbols {

  // ------------------------------------------------------------ SymbolKind
  // The LSP enumeration, spelled out where it is used rather than as bare
  // numbers in the tree builder.
  val KModule        = 2
  val KNamespace     = 3
  val KClass         = 5
  val KMethod        = 6
  val KProperty      = 7
  val KField         = 8
  val KConstructor   = 9
  val KEnum          = 10
  val KInterface     = 11
  val KFunction      = 12
  val KVariable      = 13
  val KObject        = 19
  val KStruct        = 23

  /** A half-open range in PARSER coordinates (1-based line and column):
    * exactly what the surface tree carries, converted at render time. */
  final case class Rng(sl: Int, sc: Int, el: Int, ec: Int) {
    def union(o: Rng): Rng = {
      val (asl, asc) = if (before(sl, sc, o.sl, o.sc)) (sl, sc) else (o.sl, o.sc)
      val (ael, aec) = if (before(el, ec, o.el, o.ec)) (o.el, o.ec) else (el, ec)
      Rng(asl, asc, ael, aec)
    }
  }

  /** (line, column) order; there is no `Ordering` on a tuple in scope and
    * this is clearer than importing one for four comparisons. */
  private def before(l1: Int, c1: Int, l2: Int, c2: Int): Boolean =
    l1 < l2 || (l1 == l2 && c1 <= c2)

  /** Does `outer` contain `inner`?  The LSP spec REQUIRES a symbol's
    * `range` to contain its `selectionRange`, and a child to sit inside
    * its parent; the corpus property (TestRenamer, 6.4) asserts both by
    * calling THIS, the same rule the builder makes true by
    * construction, rather than restating it. */
  def containsRng(outer: Rng, inner: Rng): Boolean =
    before(outer.sl, outer.sc, inner.sl, inner.sc) &&
    before(inner.el, inner.ec, outer.el, outer.ec)

  /** Do two ranges share any text?  Half-open, so a range that ENDS where
    * another begins does not overlap it -- which is the ordinary shape of
    * two adjacent statements, because a token swallows the whitespace
    * after its lexeme and a statement's span therefore runs to the start
    * of the next one.  The corpus property (TestRenamer, 6.4) uses this
    * to say that no two SIBLINGS straddle each other. */
  def overlaps(a: Rng, b: Rng): Boolean =
    strictlyBefore(a.sl, a.sc, b.el, b.ec) && strictlyBefore(b.sl, b.sc, a.el, a.ec)

  /** STRICT (line, column) order.  `before` admits equality, which is what
    * containment wants; overlap wants the opposite, because half-open
    * ranges that touch at one point share no text. */
  private def strictlyBefore(l1: Int, c1: Int, l2: Int, c2: Int): Boolean =
    l1 < l2 || (l1 == l2 && c1 < c2)

  /** Sibling order: by start position, ties broken by end position.  The
    * builder sorts every level by start; this is the predicate the corpus
    * property checks it with. */
  def beforeSym(a: Sym, b: Sym): Boolean =
    before(a.range.sl, a.range.sc, b.range.sl, b.range.sc)

  /** The NAME's own extent: where the editor puts the cursor when the
    * symbol is picked, and the `location` a workspace hit answers. */
  final case class Sel(line: Int, col: Int, len: Int) {
    def asRange: Rng = Rng(line, col, line, col + len)
  }

  /** One document symbol.  The TYPE is kept, not its rendering: hover
    * renders on demand for exactly the same reason (an index rebuilt on
    * every keystroke must not pay for a printer nobody asked for), and
    * `detail` carries only what is already a string (a foreign class
    * name, a fixity, `export`). */
  final case class Sym(name: String, kind: Int, ty: Option[Type],
                       detail: Option[String], range: Rng, selection: Sel,
                       children: List[Sym]) {
    def pos: (Int, Int) = (range.sl, range.sc)
  }

  // ----------------------------------------------------------- the builder

  private object TopOwner

  /** One statement that contributes to a term group: which CONTAINER's
    * statement list it stands in, its INDEX in that list, its span, its
    * head name, and whether it is an equation (and takes arguments).
    *
    * The index is what makes 6.4's fix round possible: a group's `range`
    * is the maximal CONTIGUOUS run of its own statements, so the two
    * indices either side of the selection are what decides where the
    * range stops. */
  private final class Hit(val owner: AnyRef, val idx: Int, val rng: Rng,
                          val sel: Sel, val isEq: Boolean, val hasArgs: Boolean)

  /** A term group under construction: every statement of one spelling in
    * this binding scope, in source order. */
  private final class Grp(val spelling: String) {
    val hits = scala.collection.mutable.ListBuffer.empty[Hit]
  }

  /** Build the symbol tree for one module.
    *
    * `termTy` is "the type this check knows for that spelling" --
    * `TolerantCheck`'s own `types` for this module's top levels, falling
    * back to the session's `termNames` for the names a check installs
    * rather than binds (constructors, `field`, `table`, `foreign`).  It
    * is a function so that this builder needs NO session at all, which
    * is what lets the corpus property (TestRenamer, 6.4) run it over 253
    * files in seconds. */
  def build(m: SModule, lines: Definitions.Lines,
            termTy: String => Option[Type]): List[Sym] = {

    def sel(n: SName): Sel = {
      val (len, _) = Definitions.nameExtent(lines, n.span, n.spelling)
      Sel(n.span.startLine, n.span.startCol, len)
    }
    def rng(sp: Span): Rng = Rng(sp.startLine, sp.startCol, sp.endLine, sp.endCol)
    /** The spec requires `range` to CONTAIN `selectionRange`, and the
      * corpus property asserts it -- so make it true by construction
      * rather than hope the parser's spans line up. */
    def sym(name: String, kind: Int, ty: Option[Type], detail: Option[String],
            r: Rng, s: Sel, children: List[Sym]): Sym = {
      val covered = children.foldLeft(r union s.asRange)((a, c) => a union c.range)
      Sym(name, kind, ty, detail, covered, s, children)
    }

    /** A container keyword's own extent: `foreign`, `private`,
      * `database`.  Their spans start exactly at the keyword
      * (`SurfaceParsers` takes `p1 <- loc` before consuming it), so the
      * selection is that keyword, clipped to the line. */
    def keywordSel(r: Rng, word: String): Sel = {
      val off = lines.offset(r.sl, r.sc)
      val eol = lines.endOfLine(r.sl)
      val len = if (off < 0) word.length else math.max(1, math.min(word.length, eol - off))
      Sel(r.sl, r.sc, len)
    }

    // Fixity declarations are PROPERTIES of the operator they name, not
    // symbols of their own (6.4.1): they go in that symbol's `detail`.
    def fixityMap(typeLevel: Boolean): Map[String, String] =
      m.statements.collect {
        case SFixity(_, f, tl, ops) if tl == typeLevel =>
          ops.map(_.spelling -> renderFixity(f))
      }.flatten.toMap
    val termFixity = fixityMap(false)
    val typeFixity = fixityMap(true)

    def detailOf(spelling: String, fix: Map[String, String]): Option[String] =
      fix.get(spelling).filter(_.nonEmpty)

    /** One BINDING SCOPE: the module's own statements (private and
      * database blocks included -- the renamer's `collectHeads` flattens
      * them into one namespace, so the symbol tree must group them the
      * same way or the moduleTerms cross-check would be measuring
      * something else), or one class body.
      *
      * THE RANGE RULE (6.4 fix round, review F1/F2).  A group's symbol is
      * emitted in the container of its SELECTION -- its first equation,
      * or its signature when it has no equation -- and its `range` is the
      * maximal CONTIGUOUS RUN of its own statements, in that container's
      * statement list, containing that selection.
      *
      * The first version of 6.4 took the union of ALL of a group's spans,
      * which is why the review found 171 pairs of sibling ranges that
      * straddle each other.  Two ordinary idioms do it: a block of
      * signatures followed by a block of equations
      * (`Layout/Column.e` 25-32 is a four-deep staircase), and a
      * multi-name signature whose equations are on separate lines
      * (`Function.e`'s `($), ($!)`).  Nothing spec-illegal followed and
      * the outline LIST was right, but every client feature that maps a
      * CURSOR to a symbol -- breadcrumbs, sticky scroll, outline
      * follow-cursor -- walks siblings and takes the first range that
      * contains the position, so a cursor on `unsafeFCol`'s own signature
      * line reported `unsafeCol`.
      *
      * What the run rule gives up, deliberately and statedly: a signature
      * SEPARATED from its equations by another group is not in the
      * symbol's range, so that source line belongs to no symbol at all.
      * A breadcrumb there says nothing, which is honest; before, it said
      * the wrong name.  The symbol is still found by name, still selects
      * its equation head, and every adjacent sig+equation group -- the
      * overwhelming majority, and every pin -- is unchanged.
      *
      * It also settles the cross-container case (F2): a signature at top
      * level whose equations are inside a `private` block used to leave
      * an EMPTY namespace beside a top-level symbol whose selectionRange
      * pointed inside it.  Now the group lives where its equations do,
      * the stray signature is outside the run, and a container's range is
      * its own block. */
    def scopeSymbols(top: List[SStatement], inClass: Boolean): List[Sym] = {
      val groups = scala.collection.mutable.LinkedHashMap.empty[String, Grp]
      def grp(spelling: String): Grp =
        groups.getOrElseUpdate(spelling, new Grp(spelling))

      def collect(ss: List[SStatement], owner: AnyRef): Unit =
        ss.zipWithIndex foreach {
          case (SSigStatement(loc, ns, _), i) => ns foreach { n =>
            grp(n.spelling).hits += new Hit(owner, i, rng(loc.span), sel(n), false, false)
          }
          case (SEquation(loc, n, args, _, _), i) =>
            grp(n.spelling).hits += new Hit(owner, i, rng(loc.span), sel(n),
                                            true, args.nonEmpty)
          case (b: SPrivateBlock, _)  => collect(b.statements, b)
          case (b: SDatabaseBlock, _) => collect(b.statements, b)
          case _ => ()
        }
      collect(top, TopOwner)

      /** (the container the symbol belongs to, the symbol itself). */
      def groupSym(g: Grp): Option[(AnyRef, Sym)] = {
        val hits = g.hits.toList
        // THE SELECTION: the head of the first EQUATION, or of the
        // signature when the group has none.
        (hits.find(_.isEq) orElse hits.headOption) map { anchor =>
          // The contiguous run of this group's statements around the
          // anchor, inside the anchor's own container.
          val here = hits.filter(_.owner eq anchor.owner)
          val idxs = here.map(_.idx).toSet
          var lo = anchor.idx
          while (idxs.contains(lo - 1)) lo -= 1
          var hi = anchor.idx
          while (idxs.contains(hi + 1)) hi += 1
          val run = here.filter(h => h.idx >= lo && h.idx <= hi)
          val r = run.map(_.rng).reduce((a: Rng, b: Rng) => a union b)
          // A group is a VARIABLE when it has an equation and no
          // equation of it takes an argument -- `answer = 42` is a value
          // and `f x = x` is a function; a group that is only a
          // SIGNATURE (a class member, or a sig whose definition is
          // missing) is a Function, because nothing says otherwise.  A
          // member of a `class` body is a METHOD whatever its arity:
          // it is a class member, and it also keeps the moduleTerms
          // cross-check exact (class bodies are their own binding scope
          // and are NOT in `Renamer.Result.moduleTerms`).  The arity is
          // read off EVERY equation of the group, run or no run: the kind
          // is about the name, not about one block of it.
          val kind =
            if (inClass) KMethod
            else if (hits.exists(_.isEq) && !hits.exists(h => h.isEq && h.hasArgs)) KVariable
            else KFunction
          (anchor.owner,
           sym(g.spelling, kind, termTy(g.spelling),
               detailOf(g.spelling, termFixity), r, anchor.sel, Nil))
        }
      }

      lazy val resolved: List[(AnyRef, Sym)] = groups.values.toList.flatMap(groupSym)

      def foreignSym(f: SForeign): Option[Sym] = f match {
        // `foreign data` names a TYPE with no constructors of its own --
        // the same shape as a `type` alias, and the same kind.
        case x: SForeignData =>
          Some(sym(x.name.spelling, KClass, None, Some(x.className),
                   rng(x.loc.span), sel(x.name), Nil))
        case x: SForeignFunction =>
          Some(sym(x.name.spelling, KFunction, termTy(x.name.spelling),
                   Some(x.className + "." + x.member), rng(x.loc.span), sel(x.name), Nil))
        case x: SForeignMethod =>
          Some(sym(x.name.spelling, KFunction, termTy(x.name.spelling),
                   Some(x.member), rng(x.loc.span), sel(x.name), Nil))
        case x: SForeignValue =>
          Some(sym(x.name.spelling, KProperty, termTy(x.name.spelling),
                   Some(x.className + "." + x.member), rng(x.loc.span), sel(x.name), Nil))
        case x: SForeignConstructor =>
          Some(sym(x.name.spelling, KConstructor, termTy(x.name.spelling),
                   None, rng(x.loc.span), sel(x.name), Nil))
        case x: SForeignSubtype =>
          Some(sym(x.name.spelling, KFunction, termTy(x.name.spelling),
                   None, rng(x.loc.span), sel(x.name), Nil))
        case x: SForeignPrivate =>
          val r = rng(x.loc.span)
          Some(sym("private", KNamespace, None, None, r, keywordSel(r, "private"),
                   x.statements.flatMap(foreignSym).sortBy(_.pos)))
      }

      def emit(ss: List[SStatement], owner: AnyRef): List[Sym] = {
        val mine = resolved.filter(_._1 eq owner).map(_._2)
        val rest = ss.flatMap {
          case _: SSigStatement | _: SEquation => Nil
          // A fixity declaration is not a symbol: it is a property of the
          // operator it names, and it is in that symbol's `detail`.
          case _: SFixity => Nil
          // A broken statement gets a DIAGNOSTIC, which is enough; the
          // healthy statements around it still list.
          case _: SErrorStatement => Nil
          case x: SFieldStatement => x.names.map { n =>
            sym(n.spelling, KField, termTy(n.spelling), None,
                rng(x.loc.span), sel(n), Nil) }
          case x: STableStatement => x.names.map { n =>
            sym(n.spelling, KObject, termTy(n.spelling), None,
                rng(x.loc.span), sel(n), Nil) }
          case x: STypeAlias =>
            List(sym(x.name.spelling, KClass, None,
                     detailOf(x.name.spelling, typeFixity),
                     rng(x.loc.span), sel(x.name), Nil))
          case x: SDataStatement =>
            val cons = x.constructors.map { (cd: SConDef) =>
              sym(cd.name.spelling, KConstructor, termTy(cd.name.spelling), None,
                  rng(cd.loc.span), sel(cd.name), Nil) }
            // Stage 1a: a record-style constructor's fields are generated
            // top-level FUNCTIONS, so they belong in the outline beside the
            // constructors; distinct by name, since one name shared by two
            // constructors is one selector
            val sels = x.constructors.flatMap(_.fieldNames.getOrElse(Nil))
              .foldLeft(List.empty[SName]) { (acc, n) =>
                if (acc.exists(_.spelling == n.spelling)) acc else acc :+ n }
              .map(n => sym(n.spelling, KField, termTy(n.spelling), None,
                            rng(n.span), sel(n), Nil))
            // ENUM when every constructor is nullary (`data Bool = True
            // | False`), STRUCT when any of them carries a field: the
            // distinction an editor's outline icon is actually for.
            val kind = if (x.constructors.nonEmpty && x.constructors.forall(_.fields.isEmpty))
                         KEnum else KStruct
            List(sym(x.name.spelling, kind, None,
                     detailOf(x.name.spelling, typeFixity),
                     rng(x.loc.span), sel(x.name), (cons ++ sels).sortBy(_.pos)))
          case x: SClassStatement =>
            List(sym(x.name.spelling, KInterface, None,
                     detailOf(x.name.spelling, typeFixity),
                     rng(x.loc.span), sel(x.name),
                     scopeSymbols(x.body, inClass = true)))
          case x: SForeignBlock =>
            val r = rng(x.loc.span)
            List(sym("foreign", KModule, None, None, r, keywordSel(r, "foreign"),
                     x.statements.flatMap(foreignSym).sortBy(_.pos)))
          case x: SPrivateBlock =>
            val r = rng(x.loc.span)
            List(sym("private", KNamespace, None, None, r, keywordSel(r, "private"),
                     emit(x.statements, x)))
          case x: SDatabaseBlock =>
            val r = rng(x.loc.span)
            List(sym(if (x.dbName.isEmpty) "database" else x.dbName, KNamespace, None,
                     Some("database"), r, keywordSel(r, "database"),
                     emit(x.statements, x)))
          // `SStatement` is sealed and every case is above: a NEW
          // statement kind must come here and be given a SymbolKind
          // rather than vanish silently from the outline.
        }
        (mine ++ rest).sortBy(_.pos)
      }

      emit(top, TopOwner)
    }

    // IMPORTS are Module symbols at the head of the list; the module name
    // is the selection, so picking one lands on the name the definition
    // request also answers.
    val imports = m.header.imports.map { imp =>
      val sp  = imp.moduleSpan
      val len = Definitions.nameExtent(lines, sp, imp.module)._1
      sym(imp.module, KModule, None, if (imp.isExport) Some("export") else None,
          rng(imp.loc.span), Sel(sp.startLine, sp.startCol, len), Nil)
    }

    (imports ++ scopeSymbols(m.statements, inClass = false)).sortBy(_.pos)
  }

  private def renderFixity(f: Fixity): String = f match {
    case Idfix              => ""
    case Prefix(p)          => "prefix " + p
    case Postfix(p)         => "postfix " + p
    case Infix(p, AssocL)   => "infixl " + p
    case Infix(p, AssocR)   => "infixr " + p
    case Infix(p, AssocN)   => "infix " + p
    case other              => other.toString
  }

  // ------------------------------------------------------------- rendering

  private def rangeJson(r: Rng, ls: Option[Definitions.Lines]): Json =
    Json.obj(
      "start" -> Json.obj("line" -> Json.num(r.sl - 1),
                          "character" -> Json.num(Definitions.toCharacter(ls, r.sl, r.sc))),
      "end"   -> Json.obj("line" -> Json.num(r.el - 1),
                          "character" -> Json.num(Definitions.toCharacter(ls, r.el, r.ec))))

  private def selJson(s: Sel, ls: Option[Definitions.Lines]): Json = {
    val chr = Definitions.toCharacter(ls, s.line, s.col)
    Json.obj(
      "start" -> Json.obj("line" -> Json.num(s.line - 1), "character" -> Json.num(chr)),
      "end"   -> Json.obj("line" -> Json.num(s.line - 1), "character" -> Json.num(chr + s.len)))
  }

  /** The rendered `detail`: the checked type printed the way HOVER prints
    * it (one printer, one spelling), then whatever string detail the
    * symbol carries.  Rendered HERE, in the request, not on the check
    * path -- the same rule the hover payload follows. */
  private def detailJson(s: Sym): List[(String, Json)] = {
    val ty = s.ty.map(t => Pretty.prettyType(t, -1).toString)
    List(ty, s.detail).flatten match {
      case Nil => Nil
      case xs  => List("detail" -> Json.Str(xs.mkString("  ")))
    }
  }

  private def documentSymbolJson(ls: Option[Definitions.Lines])(s: Sym): Json =
    Json.Obj(
      List("name" -> Json.Str(s.name), "kind" -> Json.num(s.kind)) ++
      detailJson(s) ++
      List("range" -> rangeJson(s.range, ls),
           "selectionRange" -> selJson(s.selection, ls)) ++
      (if (s.children.isEmpty) Nil
       else List("children" -> Json.Arr(s.children.map(documentSymbolJson(ls))))))

  /** A flat `SymbolInformation`, for workspace/symbol.  `location` is the
    * NAME's own range -- where the editor should land -- and
    * `containerName` is the module the symbol belongs to. */
  private def symbolInformation(name: String, kind: Int, container: String,
                                location: Json): Json =
    Json.obj("name" -> Json.Str(name), "kind" -> Json.num(kind),
             "containerName" -> Json.Str(container), "location" -> location)

  /** Every symbol in a document tree, depth first. */
  def flatten(ss: List[Sym]): List[Sym] =
    ss.flatMap(s => s :: flatten(s.children))

  /** The symbols that came from a TERM GROUP -- a signature and its
    * equations -- in the MODULE's own binding scope.  That is exactly
    * the set `Renamer.Result.moduleTerms` holds one entry per, and the
    * corpus property (TestRenamer, 6.4) checks the two against each
    * other file by file, which is what says the merge is right.
    *
    * Two subtrees are NOT groups and are skipped whole:
    *  - a `Module` symbol: an import, or a `foreign` block.  A foreign
    *    declaration prints as a Function to an editor because that is
    *    what it is to a caller, but the renamer never binds it --
    *    `collectHeads` walks signatures and equations only -- so it is
    *    not a group and must not be counted as one.
    *  - an `Interface`: a `class` body is its OWN binding scope
    *    (`Renamer.statement` calls `topLevelHeads` on it separately), so
    *    its members are not module terms.  They are Methods for exactly
    *    that reason.
    * A `private` or `database` namespace IS part of the module's scope
    * (`collectHeads` walks into both), so it is recursed into. */
  def termGroups(ss: List[Sym]): List[Sym] = ss.flatMap { s =>
    if (s.kind == KModule || s.kind == KInterface) Nil
    else if (s.kind == KFunction || s.kind == KVariable) List(s)
    else termGroups(s.children)
  }

  // ----------------------------------------------- the session's own names

  /** One workspace-searchable global from the RESIDENT session: the name,
    * its module, its kind, and the LSP `Location` already rendered.
    *
    * Rendered once, at build time, on purpose: `Definitions.location`
    * stats the file (that is how a Scala-installed builtin, whose `Loc`
    * is `Loc.builtin`, drops out), and a query must not do thousands of
    * stats.  A query over this list is a `contains` per entry and
    * nothing else. */
  final case class GlobalSym(name: String, lower: String, module: String,
                             kind: Int, location: Json)

  private var globals: Option[List[GlobalSym]] = None

  /** The session's globals, built ONCE.  It cannot go stale: the
    * resident session is interface-free and loads its 129 modules at
    * boot and never again (Decision 5), and every check runs against a
    * COPY of that env (`Resident.withEnv`), so nothing a check does
    * reaches this table. */
  def sessionGlobals(env: SessionEnv, src: Definitions.LineSource,
                     log: String => Unit): List[GlobalSym] =
    globals getOrElse {
      val t0 = System.nanoTime
      // A name that several modules re-export arrives under each of their
      // Globals, all pointing at ONE definition site.  Keep one entry per
      // (definition site, spelling) and prefer the module the file itself
      // defines -- otherwise `not` would list once per re-exporter and a
      // popular name would fill the 200-result cap with copies of itself.
      val moduleOfFile: Map[String, String] =
        env.loadedFiles.foldLeft(Map.empty[String, String]) {
          case (m, (src, mod)) => m + (src.toString -> mod)
        }
      def site(l: scalaparsers.Loc): Option[(String, Int, Int)] = l match {
        case p: Pos                       => Some((p.fileName, p.line, p.column))
        case scalaparsers.Inferred(p)     => Some((p.fileName, p.line, p.column))
        case _                            => None
      }
      def better(a: (Global, Int), b: (Global, Int), file: String): (Global, Int) = {
        val want = moduleOfFile.get(file)
        if (want.contains(a._1.module)) a
        else if (want.contains(b._1.module)) b
        else if (a._1.module <= b._1.module) a else b
      }
      /** The CONTAINER is the module the definition LIVES in, which is the
        * module the file defines -- not the `Global`'s own module, which
        * for a re-exported name is whichever re-exporter's Global
        * survived (`Prelude` for half of `Syntax/Relation.e`). */
      def containerOf(file: String, g: Global): String =
        moduleOfFile.getOrElse(file, g.module)
      val picked = scala.collection.mutable.HashMap
        .empty[(String, Int, Int, String, Boolean), (Global, Int)]
      def offer(g: Global, l: scalaparsers.Loc, kind: Int, typeLevel: Boolean): Unit =
        site(l) foreach { case (f, ln, col) =>
          val k = (f, ln, col, g.string, typeLevel)
          picked.get(k) match {
            case Some(old) => picked(k) = better(old, (g, kind), f)
            case None      => picked(k) = (g, kind)
          }
        }
      // TERMS.  A Scala-installed builtin carries `Loc.builtin`, which is
      // not a `Pos` at all, so it never even reaches `offer`.
      env.termNames foreach { case (g, v) =>
        // Constructors are the one term kind that can be told apart here,
        // and they are told apart the way the grammar tells them apart:
        // an upper-case initial.  Everything else is a Function.
        val kind = if (g.string.headOption.exists(_.isUpper)) KConstructor else KFunction
        offer(g, v.loc, kind, false)
      }
      // TYPES.  A `class` is an Interface, exactly as in the document
      // tree; every other Con -- data, alias, foreign data -- is a Struct.
      env.cons foreach { case (g, con) =>
        offer(g, con.loc, if (env.classes.contains(g)) KInterface else KStruct, true)
      }
      val out = picked.toList.flatMap { case ((f, ln, col, name, _), (g, kind)) =>
        Definitions.location(Definitions.Target(Pos(f, "", ln, col, false), name.length), src)
          .map(loc => GlobalSym(name, name.toLowerCase, containerOf(f, g), kind, loc))
      }.sortBy(s => (s.lower, s.module))
      log("workspace symbols: " + out.size + " session globals with source, built in " +
          ((System.nanoTime - t0) / 1000000) + " ms")
      globals = Some(out)
      out
    }

  // -------------------------------------------------------------- the wire

  def install(server: Server, ermine: Resident, docs: Documents, log: String => Unit): Unit = {

    // 7.5, tickets E8/E9: the session's thousands of Locations are built
    // ONCE (`sessionGlobals`) and share this one line source, so the
    // whole stdlib is read at most once and its target-tree paths are
    // rewritten to the source tree in `Definitions.location`.
    val src = new Definitions.LineSource(docs)

    // 6.4.3.  documentSymbol answers from the STORED tree if there is
    // one; before the first check of a file there is none, and the answer
    // is an empty list -- never null, never a wait.
    server.onRequest("textDocument/documentSymbol") { params =>
      val idx = for {
        uri <- params / "textDocument" flatMap (_ / "uri") flatMap (_.str)
        ix  <- docs index uri
      } yield ix
      Json.Arr(idx.toList.flatMap(ix => ix.symbols.map(documentSymbolJson(ix.lines))))
    }

    server.onRequest("workspace/symbol") { params =>
      val t0 = System.nanoTime
      val query = (params / "query" flatMap (_.str)) getOrElse ""
      val q = query.toLowerCase

      // (a) EVERY OPEN DOCUMENT'S OWN DECLARATIONS, flattened out of the
      // hierarchical tree the last check of it produced.
      val open = docs.all.flatMap { d =>
        d.index.toList.flatMap { idx =>
          flatten(idx.symbols).map { s =>
            (s.name, s.name.toLowerCase, idx.moduleName, s.kind,
             Json.obj("uri" -> Json.Str(d.uri),
                      "range" -> selJson(s.selection, idx.lines)))
          }
        }
      }
      // CONTAINERS are not declarations, and workspace/symbol is a search
      // for declarations: an import and the `foreign` block are Modules,
      // a `private` or `database` block is a Namespace, and none of the
      // four declares a name (review F4 -- the Namespaces used to leak).
      // A `class` (Interface) and a `data` type (Struct/Enum) DO declare
      // their names and stay.
      val ownDecls = open.filterNot(x => x._4 == KModule || x._4 == KNamespace)

      // (b) THE RESIDENT SESSION'S GLOBALS that have a real file Loc.
      // Built once (see `sessionGlobals`); a Scala-installed builtin has
      // no source and is not in it.  An EMPTY query lists the open
      // documents only -- 2000 stdlib names are not an answer to "show me
      // everything".
      val fromSession =
        if (q.isEmpty) Nil
        else ermine.loadedEnv.toList.flatMap(env => sessionGlobals(env, src, log))
          .filter(_.lower contains q)
          .map(s => (s.name, s.lower, s.module, s.kind, s.location))

      val matches = ownDecls.filter(x => q.isEmpty || (x._2 contains q))
      // Dedupe (a) over (b) by (module, name): a module that is BOTH open
      // and loaded would otherwise appear twice, once from its buffer and
      // once from the session.
      val mine = matches.map(x => (x._3, x._1)).toSet
      val all  = matches ++ fromSession.filterNot(x => mine((x._3, x._1)))

      // RANKED: exact match first, then prefix, then substring; inside a
      // tier by name then container, so the order is total and pinnable.
      def tier(lower: String): Int =
        if (lower == q) 0 else if (lower startsWith q) 1 else 2
      val ranked = all.sortBy(x => (tier(x._2), x._2, x._3)).take(200)

      log("workspace/symbol \"" + query + "\": " + ranked.size + " of " + all.size +
          " in " + ((System.nanoTime - t0) / 1000000.0) + " ms")
      Json.Arr(ranked.map { case (name, _, container, kind, loc) =>
        symbolInformation(name, kind, container, loc) })
    }
  }
}
