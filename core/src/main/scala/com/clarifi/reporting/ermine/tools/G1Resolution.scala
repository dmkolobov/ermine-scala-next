package com.clarifi.reporting.ermine.tools

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.syntax.DataStatement
import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.rename.{ ModuleScope, Renamer }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.surface.SurfaceParsers
import scalaparsers.{ Death, Pos, Supply }

/** The occurrence -> def-site differential (roadmap 4.2): the direct
  * resolution oracle, and 4.3's spec.
  *
  * OLD side: fused moduleBody parse; every Var/ConP occurrence with a
  * real Pos in the module's own file maps by V id to a binder location
  * (binding Vs post-relocation, pattern vars, foreign defs, data
  * constructors, else the session global's def loc).
  *
  * NEW side: SurfaceParsers + Renamer occurrence table; ToBinder joins
  * the binder def-site span, ToGlobal the session global's loc.
  *
  * Occurrences claimed by BOTH sides (same line:col) must resolve to
  * the SAME def-site.  One-way occurrences are counted, not errors:
  * the fused side sees desugar-minted vars (bracket hooks, do binds),
  * the renamer sees sig/fixity/type-level names.
  */
object G1Resolution {

  private def render(l: scalaparsers.Loc, self: String): String = l match {
    case p: Pos =>
      val f = p.fileName.replaceAll(".*[/!]", "")
      (if (f == self) "self" else f) + ":" + p.line + ":" + p.column
    case other => "<" + other.toString.take(20) + ">"
  }

  def main(args: Array[String]): Unit = {
    implicit val supply: Supply = Supply.create
    implicit val printer: Printer = Printer(_ => ())
    implicit val env: SessionEnv = new SessionEnv(_typeCheck = Some(true))
    System.err.println("g1-resolution: booting...")
    Lib.preamble
    Session.loadModules(List("Prelude", "Layout"))

    val moddir = "core/target/scala-3.3.8/classes/modules"
    val modlist = scala.io.Source.fromFile("tracker/tools/g1-modules.txt").getLines().toList
    val stdlib = modlist.map { m =>
      val path = moddir + "/" + m.replace('.', '/') + ".e"
      (m, path, new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(path)), "UTF-8"))
    }
    val examples = new java.io.File("core/examples").listFiles((_, n) => n.endsWith(".e")).toList.sortBy(_.getName)
      .++(new java.io.File("core/examples/bugs").listFiles((_, n) => n.endsWith(".e")).toList.sortBy(_.getName))
      .++(new java.io.File("core/examples/guide").listFiles((_, n) => n.endsWith(".e")).toList.sortBy(_.getName))
      .map { f =>
        val src = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
        val name = src.linesIterator.find(_.startsWith("module ")).map(_.stripPrefix("module ").takeWhile(!_.isWhitespace)).getOrElse(f.getName)
        (name, f.getPath, src)
      }

    var files = 0; var agreed = 0; var mismatched = 0
    var oldOnly = 0; var newOnly = 0; var skipped = 0
    val mismatches = List.newBuilder[String]

    for ((name, path, contents) <- stdlib ++ examples) {
      // ------------------------------------------------------- old side
      val oldRes: Option[Map[(Int, Int), String]] =
        try {
          val (ps0, mh) = Session.parse(ModuleParsers.moduleHeader(name), ErParseState.mk(path, contents, name))
          // a LOADED module's own globals would trip termDef's shadow
          // refusal on re-parse (the :groups problem; nav fix 0.5)
          val tn = env.termNames.filter(_._1.module != name)
          val cs = env.cons.keySet.filter(_.module != name)
          val ips = ps0.importing(tn, cs, mh.imports, env.termNameOrigins, env.consOrigins)
          val (ps, m) = Session.parse(ModuleParsers.moduleBody(mh), ips)

          val binders = scala.collection.mutable.Map[Int, scalaparsers.Loc]()
          val occs = List.newBuilder[(Pos, Int)]
          for ((g, v) <- env.termNames) binders(v.id) = v.loc  // imports (lowest precedence)

          def pat(p: Pattern): Unit = p match {
            case VarP(v)         => binders(v.id) = v.loc
            case AsP(_, p1, p2)  => pat(p1); pat(p2)
            case ConP(_, con, ps) =>
              con.loc match { case cp: Pos if cp.fileName == path => occs += ((cp, con.id)); case _ => () }
              ps.foreach(pat)
            case ProductP(_, ps) => ps.foreach(pat)
            case StrictP(_, i)   => pat(i)
            case LazyP(_, i)     => pat(i)
            case _               => ()
          }
          def term(t: Term): Unit = t match {
            case Var(v) => v.loc match {
              case p: Pos if p.fileName == path => occs += ((p, v.id))
              case _ => ()
            }
            case App(f, x)        => term(f); term(x)
            case Sig(_, b, _)     => term(b)
            case Lam(_, p, b)     => pat(p); term(b)
            case Rigid(e)         => term(e)
            case Case(_, e, alts) => term(e); alts.foreach(alt)
            case Let(_, is, es, b) =>
              is.foreach { i => binders(i.v.id) = i.v.loc; i.alts.foreach(alt) }
              es.foreach { e => binders(e.v.id) = e.v.loc; e.alts.foreach(alt) }
              term(b)
            case Remember(_, e)   => term(e)
            case _                => ()
          }
          def alt(a: Alt): Unit = { a.patterns.foreach(pat); term(a.body) }

          for (st <- m.types) st match {
            case DataStatement(_, _, _, _, cons) => cons.foreach { case (_, cv, _) => binders(cv.id) = cv.loc }
            case _ => ()
          }
          m.foreigns.foreach { f => binders(f.v.id) = f.v.loc }
          (m.implicits ++ m.explicits).foreach { b =>
            binders(b.v.id) = b.v.loc
            b.alts.foreach(alt)
          }
          // the POST-PARSE termNames state carries the canonical def-site
          // relocation (LAST equation; the binding's captured v is the
          // first equation's copy) — highest precedence
          for ((_, v) <- ps.s.termNames) binders(v.id) = v.loc
          Some(occs.result().map { case (p, id) =>
            (p.line, p.column) -> binders.get(id).map(render(_, path.replaceAll(".*[/!]", ""))).getOrElse("<unbound>")
          }.toMap)
        } catch { case _: Death => None }

      // ------------------------------------------------------- new side
      val newRes: Option[Map[(Int, Int), String]] =
        try {
          val (_, mh) = Session.parse(ModuleParsers.moduleHeader(name), ErParseState.mk(path, contents, name))
          SurfaceParsers.module(path, contents, name) match {
            case Left(_) => None
            case Right(sm) =>
              val scope = ModuleScope.importing(name, ModuleScope.Scope.empty,
                env.termNames.filter(_._1.module != name), env.cons.keySet.filter(_.module != name),
                mh.imports, env.termNameOrigins, env.consOrigins)
              val r = Renamer.rename(sm, scope)
              val self = path.replaceAll(".*[/!]", "")
              Some(r.occurrences.flatMap { o =>
                o.resolution match {
                  case Renamer.ToBinder(id) =>
                    r.binders.get(id).filter(b => b.kind != Renamer.TyParam && b.kind != Renamer.KindParam && b.kind != Renamer.TyDef)
                      .map(b => (o.span.startLine, o.span.startCol) -> ("self:" + b.defSite.startLine + ":" + b.defSite.startCol))
                  case Renamer.ToGlobal(g, _, _) =>
                    env.termNames.get(g).map(v => (o.span.startLine, o.span.startCol) -> render(v.loc, self))
                  case _ => None
                }
              }.toMap)
          }
        } catch { case _: Death => None }

      (oldRes, newRes) match {
        case (Some(o), Some(n)) =>
          files += 1
          val shared = o.keySet intersect n.keySet
          for (k <- shared.toList.sorted) {
            if (o(k) == n(k)) agreed += 1
            else { mismatched += 1; mismatches += s"$name:${k._1}:${k._2}: old=${o(k)} new=${n(k)}" }
          }
          oldOnly += (o.keySet -- n.keySet).size
          newOnly += (n.keySet -- o.keySet).size
        case (o, n) =>
          skipped += 1
          System.err.println(s"g1-resolution: SKIPPED $name (old=${o.isDefined} new=${n.isDefined})")
      }
      if (args.contains("--samples")) (oldRes, newRes) match {
        case (Some(o), Some(n)) =>
          (o.keySet -- n.keySet).toList.sorted.take(3).foreach(k =>
            println(s"OLDONLY $name:${k._1}:${k._2} -> ${o(k)}"))
          (n.keySet -- o.keySet).toList.sorted.take(3).foreach(k =>
            println(s"NEWONLY $name:${k._1}:${k._2} -> ${n(k)}"))
        case _ => ()
      }
    }

    println(s"g1-resolution: $files files, $agreed agreed, $mismatched MISMATCHED, " +
            s"$oldOnly old-only, $newOnly new-only, $skipped skipped")
    mismatches.result().take(40).foreach(println)
  }
}
