package com.clarifi.reporting.ermine.tools

import java.security.MessageDigest

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.rename.ModuleScope
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import scalaparsers.{ Death, Supply }

/** Golden capture of ErParseState.importing (tracker/LSP-ROADMAP.md item
  * 1.3b): the parse-time scope construction the Stage-1 renamer must
  * reproduce as a pure function (item 3.1 diffs against this).
  *
  * For every module in tracker/tools/g1-modules.txt: parse the header,
  * run importing() against the booted session, and emit the size and
  * SHA-256 of the sorted canonicalTerms/canonicalTypes dump (the real
  * scope; the seeded termNames superset is the same session-wide dump for
  * everyone).  Synthetic headers that the stdlib barely exercises
  * (multi-alias, alias+plain, hiding, using, empty using, duplicate
  * import) are emitted in full.  `--dump <module>` prints a full dump for
  * debugging a hash mismatch.
  */
object G1Importing {

  private val synthetics = List(
    "SynMultiAlias" -> "module SynMultiAlias where\nimport Function as F\nimport Function as G",
    "SynAliasPlain" -> "module SynAliasPlain where\nimport Function\nimport Function as F",
    "SynUsing"      -> "module SynUsing where\nimport List using head; tail",
    "SynHiding"     -> "module SynHiding where\nimport Function hiding id",
    "SynUsingEmpty" -> "module SynUsingEmpty where\nimport List using {}",
    "SynDupImport"  -> "module SynDupImport where\nimport List\nimport List")

  def main(args: Array[String]): Unit = {
    implicit val supply: Supply = Supply.create
    implicit val printer: Printer = Printer(_ => ())
    implicit val env: SessionEnv = new SessionEnv(_typeCheck = Some(true))
    System.err.println("g1-importing: booting...")
    Lib.preamble
    Session.loadModules(List("Prelude", "Layout"))

    def dump(name: String, contents: String): Either[String, String] =
      try {
        val (ps, mh) = Session.parse(
          ModuleParsers.moduleHeader(name),
          ErParseState.mk(name, contents, name))
        val ips = ps.importing(env.termNames, env.cons.keySet, mh.imports,
                               env.termNameOrigins, env.consOrigins)
        val terms = ips.s.canonicalTerms.toList
          .map { case (l, ns) => "T " + l.toString + " -> " + ns.map(_.toString).sorted.mkString(", ") }
        val types = ips.s.canonicalTypes.toList
          .map { case (l, ns) => "Y " + l.toString + " -> " + ns.map(_.toString).sorted.mkString(", ") }
        Right((terms.sorted ++ types.sorted).mkString("\n"))
      } catch {
        case d: Death => Left(d.getMessage.linesIterator.next())
      }

    def sha(s: String): String =
      MessageDigest.getInstance("SHA-256").digest(s.getBytes("UTF-8"))
        .map("%02x".format(_)).mkString

    def verifyOne(name: String, contents: String): List[String] = {
      val diffs = List.newBuilder[String]
      try {
        val (ps, mh) = Session.parse(
          ModuleParsers.moduleHeader(name),
          ErParseState.mk(name, contents, name))
        val ips = ps.importing(env.termNames, env.cons.keySet, mh.imports,
                               env.termNameOrigins, env.consOrigins)
        val prior = ModuleScope.Scope(
          ps.s.canonicalTerms, ps.s.canonicalTypes, ps.s.termNames,
          ps.s.termOrigins, ps.s.typeOrigins)
        val nw = ModuleScope.importing(name, prior, env.termNames, env.cons.keySet,
                                       mh.imports, env.termNameOrigins, env.consOrigins)
        // value-list ORDER only feeds ambiguity-message text; compare sorted
        def canon(cm: Map[com.clarifi.reporting.ermine.Local, List[com.clarifi.reporting.ermine.Name]]) =
          cm.map { case (k, vs) => k.toString -> vs.map(_.toString).sorted }
        def origins(om: Map[com.clarifi.reporting.ermine.Global, List[com.clarifi.reporting.ermine.Global]]) =
          om.map { case (k, vs) => k.toString -> vs.map(_.toString).sorted }
        if (canon(nw.canonicalTerms) != canon(ips.s.canonicalTerms)) diffs += "canonicalTerms"
        if (canon(nw.canonicalTypes) != canon(ips.s.canonicalTypes)) diffs += "canonicalTypes"
        if (nw.termNames.map { case (k, v) => k.toString -> v.id } !=
            ips.s.termNames.map { case (k, v) => k.toString -> v.id }) diffs += "termNames"
        if (origins(nw.termOrigins) != origins(ips.s.termOrigins)) diffs += "termOrigins"
        if (origins(nw.typeOrigins) != origins(ips.s.typeOrigins)) diffs += "typeOrigins"
      } catch { case d: Death => () }  // header dies identically either way (dup imports)
      diffs.result()
    }

    args.toList match {
      case "verify" :: Nil =>
        val mods = scala.io.Source.fromFile("tracker/tools/g1-modules.txt").getLines().toList
        var bad = 0
        for (m <- mods) {
          val contents = env.loadFile(m).map(_.contents) getOrElse sys.error("no source for " + m)
          val ds = verifyOne(m, contents)
          if (ds.nonEmpty) { bad += 1; println(s"DIFF $m: ${ds.mkString(", ")}") }
        }
        for ((n, src) <- synthetics) {
          val ds = verifyOne(n, src)
          if (ds.nonEmpty) { bad += 1; println(s"DIFF synthetic $n: ${ds.mkString(", ")}") }
        }
        println(s"g1-importing verify: ${mods.size} modules + ${synthetics.size} synthetics, " +
                (if (bad == 0) "ALL MATCH" else s"$bad differ"))
        System.exit(if (bad == 0) 0 else 1)
      case "--dump" :: m :: Nil =>
        val contents = env.loadFile(m).map(_.contents) getOrElse sys.error("no source for " + m)
        dump(m, contents) match {
          case Right(text) => println(text)
          case Left(err)   => println("DIES: " + err)
        }
      case Nil =>
        val mods = scala.io.Source.fromFile("tracker/tools/g1-modules.txt").getLines().toList
        for (m <- mods) {
          val contents = env.loadFile(m).map(_.contents) getOrElse sys.error("no source for " + m)
          dump(m, contents) match {
            case Right(text) =>
              val (t, y) = (text.linesIterator.count(_ startsWith "T "),
                            text.linesIterator.count(_ startsWith "Y "))
              println(s"module $m terms=$t types=$y sha256=${sha(text)}")
            case Left(err) => println(s"module $m DIES: $err")
          }
        }
        for ((n, src) <- synthetics) {
          println(s"== synthetic $n")
          dump(n, src) match {
            case Right(text) => println(text)
            case Left(err)   => println("DIES: " + err)
          }
        }
      case _ =>
        System.err.println("usage: G1Importing [--dump <module>]"); System.exit(2)
    }
  }
}
