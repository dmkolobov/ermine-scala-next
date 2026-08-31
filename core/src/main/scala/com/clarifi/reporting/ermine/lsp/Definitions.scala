package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Fixity, Global, Idfix, Local, Pretty, Type }
import com.clarifi.reporting.ermine.rename.Renamer
import com.clarifi.reporting.ermine.surface.{ SFixity, Span }
import scalaparsers.{ Loc, Pos }

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
        "kind"  -> Json.Str("plaintext"),
        "value" -> Json.Str(lt._1 + " : " + Pretty.prettyType(lt._2, -1).toString)))
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

  private def location(t: Target): Option[Json] = t.loc match {
    case p: Pos if new java.io.File(p.fileName).isFile =>
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

    val occs = c.renamed.occurrences.flatMap { o =>
      val sp = o.span
      o.resolution match {
        case Renamer.ToBinder(id) =>
          c.renamed.binders.get(id).map { b =>
            val d = b.defSite
            val tgt = Target(Pos(fileName, "", d.startLine, d.startCol, false), spanLen(d))
            val hover =
              // 5.4: the module's own types come from the tolerant check,
              // not from the session — the editor path no longer runs a
              // real load to put them there.
              if (b.kind == Renamer.TopLevel)
                c.types.get(b.spelling).map(t => (label(ownGlobal(b.spelling)), t))
              else None  // local binder types: perf-ticket territory
            Occ(sp.startLine, sp.startCol, spanLen(sp), Some(tgt), hover)
          }
        case Renamer.ToGlobal(g, _, _) =>
          env.termNames.get(g).map { v =>
            Occ(sp.startLine, sp.startCol, spanLen(sp),
                Some(Target(v.loc, v.name.map(_.string.length).getOrElse(1))),
                Some((label(g), v.extract)))
          }
        case _ => None  // unresolved/ambiguous: no navigation
      }
    }
    DocIndex(occs)
  }

  private def label(g: Global): String = g.module + "." + g.string
}
