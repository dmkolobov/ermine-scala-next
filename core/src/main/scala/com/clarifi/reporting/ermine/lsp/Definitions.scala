package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{
  Alt, App, Case, ExplicitBinding, Global, ImplicitBinding, Lam, Let, Local,
  Pattern, Pretty, Remember, Rigid, Sig, Term, Type, V, Var, VarP, StrictP,
  LazyP, ConP }
import com.clarifi.reporting.ermine.session.SessionEnv
import com.clarifi.reporting.ermine.syntax.Module
import scalaparsers.{ Loc, Pos }

/** textDocument/definition (roadmap 0.5).
  *
  * The parser already did the name resolution: a reference parses as
  * `v at occurrencePos` — a copy of the definition's V, same id, its loc
  * moved to the occurrence (TermNameParsers.termVar) — while the V kept in
  * termNames is relocated to the actual definition site (globalTermDef),
  * and a pattern binder shares its id with the V it shadows termNames with
  * (PatternParsers.mkLocalPatternVar).  So: index every V in the tree by
  * position, map ids to definition sites (local binders over the env's
  * termNames), and definition is a hit-test plus two lookups.  Misses
  * answer null, never error.
  */
object Definitions {

  final case class Target(loc: Loc, len: Int)
  final case class Occ(line: Int, startCol: Int, len: Int, id: Int)
  final case class DocIndex(occs: List[Occ], defs: Map[Int, Target],
                            types: Map[Int, (String, Type)])

  /** Per-document indexes, kept across failed checks (stale navigation
    * beats none) and dropped on didClose.  Single-threaded, like all
    * request handling. */
  final class Docs {
    private var m = Map.empty[String, DocIndex]
    def put(uri: String, idx: DocIndex): Unit = m += uri -> idx
    def drop(uri: String): Unit = m -= uri
    def get(uri: String): Option[DocIndex] = m get uri
  }

  def install(server: Server, docs: Docs, log: String => Unit): Unit = {
    server.onRequest("textDocument/definition") { params =>
      val answer = for {
        occ <- occurrenceAt(docs, params)
        tgt <- occ._1.defs get occ._2.id
        loc <- location(tgt)
      } yield loc
      answer getOrElse Json.Null
    }

    // Hover: the inferred type from the session env, top-level and imported
    // names only — local binder types are Stage-1+ territory (roadmap 0.6).
    server.onRequest("textDocument/hover") { params =>
      val answer = for {
        occ <- occurrenceAt(docs, params)
        lt  <- occ._1.types get occ._2.id
      } yield Json.obj("contents" -> Json.obj(
        "kind"  -> Json.Str("plaintext"),
        "value" -> Json.Str(lt._1 + " : " + Pretty.prettyType(lt._2, -1).toString)))
      answer getOrElse Json.Null
    }
  }

  private def occurrenceAt(docs: Docs, params: Json): Option[(DocIndex, Occ)] =
    for {
      uri  <- params / "textDocument" flatMap (_ / "uri") flatMap (_.str)
      pos  <- params / "position"
      line <- pos / "line" flatMap (_.int)
      chr  <- pos / "character" flatMap (_.int)
      idx  <- docs get uri
      occ  <- hit(idx, line + 1, chr + 1)  // LSP is 0-based, Pos 1-based
    } yield (idx, occ)

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

  /** Build the index for one checked document. */
  def index(fileName: String, env: SessionEnv, m: Module): DocIndex = {
    val w = new Walk(fileName)
    m.implicits foreach w.implicitBinding
    m.explicits foreach w.explicitBinding
    // Globals — imports and everything the load pulled in — resolve through
    // the env; the file's own re-parsed binders overlay them afterwards.
    val globals = env.termNames.valuesIterator.map(v => v.id -> target(v)).toMap
    val globalTypes = env.termNames.iterator.map { case (g, v) =>
      v.id -> (label(g), v.extract)
    }.toMap
    // The file's own top-levels re-parsed under fresh ids; their inferred
    // types live in termNames under Local.global(moduleName) — bridge by name.
    val ownTypes = (m.implicits.map(_.v) ++ m.explicits.map(_.v)).flatMap { v =>
      for {
        l  <- v.name collect { case l: Local => l }
        tv <- env.termNames get (l global m.name)
      } yield v.id -> (label(l global m.name), tv.extract)
    }.toMap
    DocIndex(w.occs.result(), globals ++ w.defs.result(), globalTypes ++ ownTypes)
  }

  private def label(g: Global): String = g.module + "." + g.string

  private def nameLen[A](v: V[A]): Int =
    v.name map (_.string.length) getOrElse 1

  private def target[A](v: V[A]): Target = Target(v.loc, nameLen(v))

  private final class Walk(fileName: String) {
    val occs = List.newBuilder[Occ]
    val defs = Map.newBuilder[Int, Target]

    def v[A](x: V[A], isDef: Boolean): Unit = {
      x.loc match {
        case p: Pos if p.fileName == fileName =>
          occs += Occ(p.line, p.column, nameLen(x), x.id)
        case _ => ()
      }
      if (isDef) defs += x.id -> target(x)
    }

    def term(t: Term): Unit = t match {
      case Var(x)             => v(x, isDef = false)
      case App(a, b)          => term(a); term(b)
      case Sig(_, tm, _)      => term(tm)
      case Lam(_, p, b)       => pat(p); term(b)
      case Rigid(e)           => term(e)
      case Remember(_, e)     => term(e)
      case Case(_, e, alts)   => term(e); alts foreach alt
      case Let(_, is, es, b)  => is foreach implicitBinding; es foreach explicitBinding; term(b)
      case _                  => ()  // literals, Product, EmptyRecord, Hole
    }

    def alt(a: Alt): Unit = { a.patterns foreach pat; term(a.body) }

    def pat(p: Pattern): Unit = p match {
      case VarP(x)          => v(x, isDef = true)
      case StrictP(_, q)    => pat(q)
      case LazyP(_, q)      => pat(q)
      case ConP(_, con, ps) => v(con, isDef = false); ps foreach pat
      case _                => ()  // wildcards, literal patterns
    }

    def implicitBinding(b: ImplicitBinding): Unit = { v(b.v, isDef = true); b.alts foreach alt }
    def explicitBinding(b: ExplicitBinding): Unit = { v(b.v, isDef = true); b.alts foreach alt }
  }
}
