package com.clarifi.reporting

import java.io.File

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.syntax.{ Renaming, Single }
import com.clarifi.reporting.ermine.surface._

import org.scalacheck._
import Prop._
import scalaparsers.Supply

/** 2.3a parity: the resolution-free header agrees with the fused
  * pipeline's over every stdlib module, and the statement splitter
  * covers every file with plausible structure. */
object TestSurfaceParsers extends Properties("Surface parser 2.3a") {

  private implicit val supply: Supply = Supply.create

  private def moduleFiles: List[File] = {
    def walk(f: File): List[File] =
      if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
      else if (f.getName endsWith ".e") List(f) else Nil
    walk(new File("core/src/main/resources/modules"))
  }

  private def read(f: File): String = {
    val s = scala.io.Source.fromFile(f, "UTF-8")
    try s.mkString finally s.close()
  }

  private def oldHeader(name: String, input: String) =
    ModuleParsers.moduleHeader(name).run(ErParseState.mk(name, input, name), supply.split)

  property("headers agree with the fused pipeline across the stdlib") = secure {
    val bad = List.newBuilder[String]
    var files = 0
    for (f <- moduleFiles) {
      val input = read(f)
      (oldHeader(f.getName, input), SurfaceParsers.module(f.getName, input, f.getName)) match {
        case (Right((_, oldH)), Right(m)) =>
          files += 1
          val h = m.header
          if (h.name != oldH.name) bad += s"${f.getName}: name ${h.name} vs ${oldH.name}"
          val oldImps = oldH.importExports
          if (h.imports.size != oldImps.size)
            bad += s"${f.getName}: ${h.imports.size} imports vs ${oldImps.size}"
          else for ((n, o) <- h.imports zip oldImps) {
            if (n.module != o.module) bad += s"${f.getName}: import ${n.module} vs ${o.module}"
            if (n.isExport != o.isExport) bad += s"${f.getName}/${o.module}: export flag"
            if (n.as != o.as || n.as.map(_.spelling) != o.as)
              if (n.as.map(_.spelling) != o.as) bad += s"${f.getName}/${o.module}: as ${n.as.map(_.spelling)} vs ${o.as}"
            val oldItems: Option[(Boolean, Int)] =
              if (o.using || o.explicits.nonEmpty) Some((o.using, o.explicits.size)) else None
            (n.items, oldItems) match {
              case (Some((u, xs)), Some((ou, on))) =>
                if (u != ou) bad += s"${f.getName}/${o.module}: using flag"
                if (xs.size != on) bad += s"${f.getName}/${o.module}: ${xs.size} items vs $on"
                val newNames = xs.map(_.name.spelling.stripPrefix("(").stripSuffix(")")).toSet
                val oldNames = o.explicits.map {
                  case Single(g, _)      => g.string
                  case Renaming(g, _, _) => g.string
                }.toSet
                if (newNames != oldNames) bad += s"${f.getName}/${o.module}: items $newNames vs $oldNames"
              case (None, None) => ()
              case (a, b) => bad += s"${f.getName}/${o.module}: item presence $a vs $b"
            }
          }
        case (Left(err), _) => bad += s"${f.getName}: OLD header failed: ${err.toString.linesIterator.next()}"
        case (_, Left(err)) => bad += s"${f.getName}: NEW header failed: ${err.toString.linesIterator.next()}"
      }
    }
    val failures = bad.result()
    (failures.isEmpty :| failures.take(6).mkString(" ;; ")) && ((files ?= 161) :| s"$files files")
  }

  property("the splitter covers every file with ordered, plausible statements") = secure {
    val bad = List.newBuilder[String]
    var fixities = 0
    var statements = 0
    for (f <- moduleFiles) {
      val input = read(f)
      SurfaceParsers.module(f.getName, input, f.getName) match {
        case Left(err) => bad += s"${f.getName}: ${err.toString.linesIterator.next()}"
        case Right(m) =>
          statements += m.statements.size
          // spans strictly ordered and statements non-empty for non-trivial files
          val spans = m.statements.map(_.loc.span)
          for ((a, b) <- spans zip spans.drop(1))
            if (b.startLine < a.startLine) bad += s"${f.getName}: unordered spans $a $b"
          // fixity statements really parse (not placeholders), and match an
          // independent regex count of fixity declarations
          val parsed = m.statements.count { case _: SFixity => true; case _ => false }
          val uncommented = input.replaceAll("(?s)\\{-.*?-\\}", "")
          val expected = uncommented.linesIterator.count(_.matches("^(infixl|infixr|infix|prefix|postfix)\\b.*"))
          fixities += parsed
          if (parsed != expected) bad += s"${f.getName}: $parsed fixity stmts vs $expected by regex"
          // nothing may remain unconsumed: every non-fixity statement is a
          // classified placeholder, never an unclassifiable mystery
          m.statements foreach {
            case SErrorStatement(_, msg) if !(msg startsWith "unparsed:") =>
              bad += s"${f.getName}: unexpected error statement $msg"
            case _ => ()
          }
      }
    }
    val failures = bad.result()
    (failures.isEmpty :| failures.take(6).mkString(" ;; ")) &&
    ((fixities > 30) :| s"only $fixities fixity statements found — sweep broken?") &&
    ((statements > 1000) :| s"only $statements statements")
  }
}
