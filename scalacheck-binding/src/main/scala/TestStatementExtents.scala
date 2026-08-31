package com.clarifi.reporting

import com.clarifi.reporting.ermine.surface.{ StatementExtents, SurfaceParsers }

import org.scalacheck._
import Prop._

import java.io.File

/** Post-G1 D7: the statement-extent scanner vs the surface parser's own
  * statement spans, across the 180-file corpus (stdlib + examples —
  * the standing sweep rule).  The scanner is pure and lexical; the
  * parser is the oracle.  Starts must agree exactly; the scanner's end
  * must not be before the parser's span end (token parsers eat trailing
  * whitespace, so parser ends can drift right past the last character).
  */
object TestStatementExtents extends Properties("Statement extents") {

  private def moduleFiles: List[File] = {
    def walk(f: File): List[File] =
      if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
      else if (f.getName endsWith ".e") List(f) else Nil
    walk(new File("core/src/main/resources/modules")) ++ walk(new File("core/examples"))
  }

  private val headerWords = Set("import", "export")

  property("scanner starts agree with parsed statement spans (180 files)") = secure {
    val bad = List.newBuilder[String]
    var files = 0; var stmts = 0
    for (f <- moduleFiles) {
      val src = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
      SurfaceParsers.module(f.getPath, src, "X") match {
        case Left(_) => ()  // unparseable corpus entries have no oracle
        case Right(m) =>
          files += 1
          val parsed = m.statements.map(s => (s.loc.span.startLine, s.loc.span.startCol))
          val scanned = StatementExtents.scan(src).items
            .filterNot(e => headerWords(e.headWord))
            .map(e => (e.startLine, e.startCol))
          stmts += parsed.size
          if (scanned != parsed) {
            val missing = parsed.filterNot(scanned.toSet)
            val extra   = scanned.filterNot(parsed.toSet)
            bad += s"${f.getName}: missing=${missing.take(3)} extra=${extra.take(3)} (${scanned.size} vs ${parsed.size})"
          }
      }
    }
    val failures = bad.result()
    (failures.isEmpty :| failures.take(8).mkString(" ;; ")) &&
    ((files >= 170) :| s"only $files files parsed") &&
    ((stmts >= 1000) :| s"only $stmts statements compared")
  }

  property("scanner ends cover the parsed spans") = secure {
    val bad = List.newBuilder[String]
    for (f <- moduleFiles) {
      val src = new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")
      SurfaceParsers.module(f.getPath, src, "X") match {
        case Left(_) => ()
        case Right(m) =>
          val scanned = StatementExtents.scan(src).items.filterNot(e => headerWords(e.headWord))
          val parsed = m.statements
          if (scanned.size == parsed.size) {
            // the parser's span END eats trailing whitespace up to the
            // next statement; the scanner's end is the last significant
            // character.  Contract: scanner end within the parsed span,
            // and strictly before the NEXT statement's start.
            val nexts = parsed.drop(1).map(s => (s.loc.span.startLine, s.loc.span.startCol)) :+ ((Int.MaxValue, 1))
            for (((e, s), nx) <- (scanned zip parsed) zip nexts) {
              val sp = s.loc.span
              val within = e.endLine < sp.endLine || (e.endLine == sp.endLine && e.endCol <= sp.endCol)
              val beforeNext = e.endLine < nx._1 || (e.endLine == nx._1 && e.endCol <= nx._2)
              if (!within || !beforeNext)
                bad += s"${f.getName}:${sp.startLine}: scanner end ${e.endLine}:${e.endCol} vs parsed ${sp.endLine}:${sp.endCol} next $nx"
            }
          }
      }
    }
    val failures = bad.result()
    failures.isEmpty :| failures.take(8).mkString(" ;; ")
  }
}
