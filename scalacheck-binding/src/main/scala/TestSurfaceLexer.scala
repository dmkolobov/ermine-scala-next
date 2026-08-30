package com.clarifi.reporting

import java.io.File

import com.clarifi.reporting.ermine.parsing.{
  DataConParsers, ErParseState, PatternVarParsers, TermNameParsers }
import com.clarifi.reporting.ermine.surface.Lexer
import com.clarifi.reporting.ermine.surface.Lexer.{ ConOp, OpFlavor, PatVarOp, TermOp }

import org.scalacheck._
import Prop._
import scalaparsers.Supply
import com.clarifi.reporting.ermine.parsing.Parser

/** Tokenizer parity (roadmap 2.2): at every candidate offset of every
  * stdlib source, where the fused pipeline's op parser succeeds, the
  * ported Lexer must produce the same lexeme — for all three op-start
  * disciplines.  A crafted corpus checks both directions on the corners
  * (affixes, the dead-underscore commit, guards, unicode op chars).
  */
object TestSurfaceLexer extends Properties("Surface lexer parity") {

  private implicit val supply: Supply = Supply.create

  /** Run the old op parser at an offset; the lexeme on success. */
  private def oldOp(p: Parser[String], input: String, offset: Int): Option[String] = {
    val ps = ErParseState.mk("<lex>", input, "T").copy(offset = offset)
    p.run(ps, supply.split) match {
      case Right((_, lex)) => Some(lex)
      case Left(_)         => None
    }
  }

  private val flavors: List[(String, Parser[String], OpFlavor)] = List(
    ("term",    TermNameParsers.op,   TermOp),
    ("datacon", DataConParsers.op,    ConOp),
    ("patvar",  PatternVarParsers.op, PatVarOp))

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

  property("stdlib sweep: old op success implies same new lexeme (x3 flavors)") = secure {
    var comparisons = 0L
    var successes = 0L
    val bad = List.newBuilder[String]
    for (f <- moduleFiles) {
      val input = read(f)
      var i = 0
      while (i < input.length) {
        val c = input.charAt(i)
        if (Lexer.isOpChar(c)) {
          for ((fname, oldP, flavor) <- flavors) {
            oldOp(oldP, input, i) foreach { oldLex =>
              comparisons += 1
              Lexer.op(input, i, flavor) match {
                case Some(l) if l.lexeme == oldLex => successes += 1
                case other =>
                  if (bad.result().size < 5)
                    bad += s"${f.getName}@$i [$fname]: old=$oldLex new=$other"
              }
            }
          }
        }
        i += 1
      }
    }
    val failures = bad.result()
    (failures.isEmpty :| failures.mkString("; ")) &&
    ((comparisons > 10000L) :| s"only $comparisons comparisons — sweep broken?") &&
    ((successes ?= comparisons) :| s"$successes/$comparisons")
  }

  property("crafted corners agree in BOTH directions (x3 flavors)") = secure {
    val corpus = List(
      "+ x", "++_L rest", "+_x", "+_ x", "+_", "|]", "| ]", "|x", ": x", ":: x",
      ":+: y", "-- x", "--- x", "---- ", "-> x", "<- x", "=> x", ".. x", "= x",
      "~ x", "` x", "'' x", "≠ x", "( x", ", x", "@#$ x", ":%:_M q",
      "*_Mod x", "!! !! x", "\\ x", ". x", "/ x")
    val bad = List.newBuilder[String]
    for (s <- corpus; (fname, oldP, flavor) <- flavors) {
      val o = oldOp(oldP, s, 0)
      val n = Lexer.op(s, 0, flavor).map(_.lexeme)
      if (o != n) bad += s"'$s' [$fname]: old=$o new=$n"
    }
    val failures = bad.result()
    failures.isEmpty :| failures.mkString("; ")
  }
}
