package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Fixity, Global, Idfix, Local, Pretty, Type }
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
  * error.  Hover covers top-level and imported names only — local binder
  * TYPES are gated on tracker/TICKET-perf-type-inference.md, not on the
  * renamer (roadmap 0.6/4.3).
  */
object Definitions {

  final case class Target(loc: Loc, len: Int)
  final case class Occ(line: Int, startCol: Int, len: Int,
                       target: Option[Target], hover: Option[(String, Type)])
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
        occ <- occurrenceAt(docs, params)
        lt  <- occ.hover
      } yield Json.obj("contents" -> Json.obj(
        // A fenced block tagged `ermine` gets the extension's own TextMate
        // grammar applied, so a hovered type is highlighted like source.
        "kind"  -> Json.Str("markdown"),
        "value" -> Json.Str("```ermine\n" + lt._1 + " : " +
                            Pretty.prettyType(lt._2, -1).toString + "\n```")))
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

    /** The session's own record of a name, term side.  Since the
      * definition site survives installation (Session.primOp keeps its
      * `loc`), this answers navigation as well as hover: data
      * constructors, `field` and `table` declarations and every foreign
      * declaration are installed this way and have nowhere else to point.
      * A Scala-installed builtin still carries Loc.builtin and simply
      * yields no location. */
    def termOf(g: Global): Option[(Target, (String, Type))] =
      env.termNames.get(g).map { v =>
        (Target(v.loc, v.name.map(_.string.length).getOrElse(g.string.length)),
         (label(g), v.extract))
      }

    /** The type side: `data`, `type`, `class`, `field` and `foreign data`
      * all install a Con whose loc is the statement that declared it, so
      * a type occurrence navigates through the con map rather than the
      * term one.  The two namespaces overlap — `data Color = Color Int`
      * gives one Global to both — which is why the occurrence's
      * `typeLevel` flag picks the table instead of a fallback order. */
    def conTarget(g: Global): Option[Target] =
      env.cons.get(g).map(con => Target(con.loc, g.string.length))

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
      def at(tgt: Option[Target], hov: Option[(String, Type)]): Occ =
        Occ(sp.startLine, sp.startCol, spanLen(sp), tgt, hov)
      o.resolution match {
        case Renamer.ToBinder(id) =>
          c.renamed.binders.get(id).map { b =>
            val hover =
              // 5.4: the module's own types come from the tolerant check,
              // not from the session — the editor path no longer runs a
              // real load to put them there.
              if (b.kind == Renamer.TopLevel)
                c.types.get(b.spelling).map(t => (label(ownGlobal(b.spelling)), t))
              else None  // local binder types: perf-ticket territory
            at(Some(selfTarget(b.defSite)), hover)
          }
        case Renamer.ToGlobal(g, _, _) if o.typeLevel =>
          // `Builtin` type/kind atoms (->, *, rho ...) have no Con and no
          // source file; they answer null, as they always did.
          conTarget(g).map(t => at(Some(t), None))
        case Renamer.ToGlobal(g, _, _) =>
          termOf(g).map { case (t, h) => at(Some(t), Some(h)) }
        case Renamer.Unresolved(spelling) =>
          // Every name declared but not BOUND lands here — see ownDecls.
          // A genuinely undefined name is in none of these tables and
          // stays silent, which is what makes the miss case honest.
          val g = ownGlobal(spelling)
          if (o.typeLevel) conTarget(g).map(t => at(Some(t), None))
          else {
            val session = termOf(g)
            val tgt = session.map(_._1) orElse ownDecls.get(spelling).map(selfTarget)
            val hov = session.map(_._2) orElse
                      c.types.get(spelling).map(t => (label(g), t))
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
          session.map(_._2) orElse c.types.get(spelling).map(t => (label(g), t)))
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
                       c.types.get(n.spelling).map(t => (label(g), t))
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
    // says.  Types have no hover (kinds are not types); this is
    // navigation only, for parity with clicking the name a line below.
    val tyHeadOccs = c.renamed.binders.values.collect {
      case b if b.kind == Renamer.TyDef =>
        val d = b.defSite
        Occ(d.startLine, d.startCol, spanLen(d), Some(selfTarget(d)), None)
    }

    DocIndex(dedup(occs ++ headOccs ++ fixityOccs ++ tyHeadOccs ++ importOccs))
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
