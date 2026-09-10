package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Fixity, Global, Idfix, KindSchema, Local, Pretty, Type }
import com.clarifi.reporting.ermine.rename.Renamer
import com.clarifi.reporting.ermine.surface.{ SClassStatement, SDatabaseBlock,
  SDataStatement, SFieldStatement, SFixity, SForeign, SForeignBlock, SForeignConstructor,
  SForeignData, SForeignFunction, SForeignMethod, SForeignPrivate, SForeignSubtype,
  SForeignValue, SName, SPrivateBlock, SStatement, STableStatement, Span }
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
                       kind: Option[(String, KindSchema)] = None)
  final case class DocIndex(occs: List[Occ])

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

  private def hit(idx: DocIndex, line: Int, col: Int): Option[Occ] =
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

  private def location(t: Target): Option[Json] = positionOf(t.loc) match {
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

  /** Build the index for one checked document from the renamer tables. */
  def index(fileName: String, c: Resident#Checked): DocIndex = {
    val env = c.env
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

    val occs = c.renamed.occurrences.flatMap { o =>
      val sp = o.span
      def at(tgt: Option[Target], hov: Option[TermHover]): Occ =
        Occ(sp.startLine, sp.startCol, spanLen(sp), tgt, hov)
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
            Occ(sp.startLine, sp.startCol, spanLen(sp),
                Some(selfTarget(b.defSite)), hover, kindHov)
          }
        case Renamer.ToGlobal(g, _, _) if o.typeLevel =>
          // `Builtin` type/kind atoms (->, *, rho ...) have no Con and no
          // source file; they answer null, as they always did.
          conTarget(g).map(t => Occ(sp.startLine, sp.startCol, spanLen(sp),
                                    Some(t), None, conHover(g)))
        case Renamer.ToGlobal(g, _, _) =>
          termOf(g).map { case (t, h) => at(Some(t), Some(h)) }
        case Renamer.Unresolved(spelling) =>
          // Every name declared but not BOUND lands here — see ownDecls.
          // A genuinely undefined name is in none of these tables and
          // stays silent, which is what makes the miss case honest.
          if (o.typeLevel) {
            val g = ownTyCon(spelling)
            conTarget(g).map(t => Occ(sp.startLine, sp.startCol, spanLen(sp),
                                      Some(t), None, conHover(g)))
          } else {
            val g = ownGlobal(spelling)
            val session = termOf(g)
            val tgt = session.map(_._1) orElse ownDecls.get(spelling).map(selfTarget)
            val hov = session.map(_._2) orElse
                      c.types.get(spelling).map(t => TermHover(label(g), t))
            if (tgt.isEmpty && hov.isEmpty) None else Some(at(tgt, hov))
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
      Occ(sp.startLine, sp.startCol, spanLen(sp), Some(selfTarget(sp)),
          session.map(_._2) orElse c.types.get(spelling).map(t => TermHover(label(g), t)))
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
        if (tgt.isEmpty && hov.isEmpty) None
        else Some(Occ(n.span.startLine, n.span.startCol, spanLen(n.span), tgt, hov))
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
        Occ(d.startLine, d.startCol, spanLen(d), Some(selfTarget(d)), None,
            conHover(ownTyCon(b.spelling)))
    }

    // 6.2: a LOCAL binder's own def-site.  An equation head (a `let` or
    // `where` binding, top level or nested) IS an occurrence of its own
    // binder and is covered above; a PATTERN binder is not an occurrence
    // at all (`Renamer.patternBinders` records a binder and no
    // occurrence), so without this the one place a reader most expects a
    // type — where the name is introduced — answered nothing.  `dedup`
    // leaves any position a real occurrence already covers alone.
    val localDefOccs = c.renamed.binders.values.collect {
      case b if b.kind == Renamer.Arg || b.kind == Renamer.LetBound ||
                b.kind == Renamer.WhereBound || b.kind == Renamer.DoBound ||
                b.kind == Renamer.CaseBound =>
        val d = b.defSite
        Occ(d.startLine, d.startCol, spanLen(d), Some(selfTarget(d)),
            c.locals.get((d.startLine, d.startCol))
              .map(l => TermHover(b.spelling, l.ty, l.scope)))
    }.filter(o => o.hover.isDefined)

    DocIndex(dedup(occs ++ headOccs ++ fixityOccs ++ tyHeadOccs ++
                   localDefOccs ++ importOccs))
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
