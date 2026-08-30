package com.clarifi.reporting.ermine.tools

import com.clarifi.reporting.ermine.ImplicitBinding
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import scalaparsers.Supply

/** Binding-group SCC dump for the G1 oracle (tracker/LSP-ROADMAP.md item
  * 1.1): the resolved reference graph is the renamer's most direct
  * observable, and one that types can mask.
  *
  * The REPL's :groups is unusable for this — its re-parse runs against a
  * session where the module's own globals are live, so most stdlib
  * modules die with "Multiple fixity definitions" / "type definition
  * would shadow".  This tool re-parses each module against an env copy
  * with the module's OWN globals filtered out (the seeding Session.dep's
  * body parse sees; same trick as Resident.checkFile's nav re-parse).
  * Output is fully normalized: modules sorted, group lines sorted, names
  * within a group sorted.
  */
object G1Groups {
  def main(args: Array[String]): Unit = {
    implicit val supply: Supply = Supply.create
    implicit val printer: Printer = Printer(_ => ())
    implicit val env: SessionEnv = new SessionEnv(_typeCheck = Some(true))
    System.err.println("g1-groups: booting...")
    Lib.preamble
    Session.loadModules(List("Prelude", "Layout"))
    val mods = env.loadedModules.keySet.filterNot(_ == "Builtin").toList.sorted
    var bad = 0
    for (m <- mods) {
      val file = env.loadFile(m) getOrElse (sys.error("no source for module " + m))
      val e2 = env.copy
      e2.termNames       = e2.termNames.filter { case (g, _) => g.module != m }
      e2.cons            = e2.cons.filter { case (g, _) => g.module != m }
      e2.termNameOrigins = e2.termNameOrigins.filter { case (g, _) => g.module != m }
      e2.consOrigins     = e2.consOrigins.filter { case (g, _) => g.module != m }
      // 5/129 modules (Field, Native.List, String, Type.Eq, Relation) do not
      // survive this re-parse under ANY filtering variant — they use their
      // own exports through sugar hooks, re-exported operators, or type ops
      // in ways only the original incremental parse can resolve (measured;
      // see tracker/g1-oracle-tests/README.md).  Their PARSE-ERROR lines are
      // deterministic and diff cleanly; the direct resolution oracle for
      // them is the occurrence->def-site differential (roadmap item 4.2).
      println(s"== $m")
      Session.parseModule(m, file.contents, m)(e2, supply) match {
        case Left(err) =>
          println("PARSE-ERROR: " + err.toString.linesIterator.next())
          bad += 1
        case Right(mod) =>
          ImplicitBinding.implicitBindingComponents(
              mod.implicits ++ mod.explicits.map(_.forgetSignature))
            .map(_.flatMap(_.v.name.map(_.string)).sorted.mkString(", "))
            .sorted
            .foreach(println)
      }
    }
    System.err.println(s"g1-groups: ${mods.size} modules, $bad with PARSE-ERROR markers (expected: 5)")
    System.exit(0)
  }
}
