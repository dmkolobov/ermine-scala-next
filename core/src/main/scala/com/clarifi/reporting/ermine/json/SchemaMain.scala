package com.clarifi.reporting.ermine.json

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.rename.NewPipeline
import com.clarifi.reporting.ermine.syntax.Explicit
import scala.collection.immutable.List
import scalaparsers.Supply

/** `bin/ermine-schema`: the JSON Schema (or zod) of one Ermine type, from a
  * shell.  tracker/JSON-API-DESIGN.md §3.5's first entry point; the second is
  * the `ermine/schema` LSP request, which answers out of the editor's already
  * booted session.
  *
  * {{{
  *   bin/ermine-schema -i Ord 'Ordering'
  *   bin/ermine-schema --zod -i Either 'Either String Int'
  *   bin/ermine-schema -i Relation.Sort SortOrder      # a bare type NAME
  * }}}
  *
  * It boots the way `session/Console` does -- `Lib.preamble`, then
  * `Session.loadModules` -- but loads ONLY the modules named with `-i` plus
  * their dependencies rather than the whole standard library, because boot
  * time is the whole cost of this program (the Prelude+Layout boot the
  * language server pays is ~13s; one small module is under two).
  *
  * The type argument is parsed by `NewPipeline.replType`, the REPL's `:kind`
  * path, against those imports.  A bare capitalised name with no arguments
  * that is a type in scope is taken as that type (so `SortOrder` works, and
  * `Maybe Int` works too, since `replType` parses it).  The schema goes to
  * stdout; an export error goes to stderr and exits 1.
  */
object SchemaMain {

  private val usage =
    "usage: ermine-schema [--zod] [-i Module ...] '<type expression>'"

  def main(args: Array[String]): Unit = {
    var zod = false
    var mods = List[String]()
    var rest = List[String]()
    var i = 0
    val as = args.toList
    var bad: Option[String] = None
    while (i < as.length && bad.isEmpty) as(i) match {
      case "--zod"           => zod = true; i += 1
      case "-h" | "--help"   => println(usage); return
      case "-i" | "--import" =>
        if (i + 1 >= as.length) bad = Some("-i needs a module name")
        else { mods = mods :+ as(i + 1); i += 2 }
      case other if other.startsWith("-") => bad = Some("unknown option " + other)
      case other             => rest = rest :+ other; i += 1
    }
    bad foreach { m => fail(m + "\n" + usage) }
    if (rest.length != 1) fail(usage)
    val source = rest.head

    com.clarifi.reporting.util.Logging.initializeLogging
    implicit val supply: Supply = Supply.create
    // Session chatter (load progress, timings) must not corrupt stdout: the
    // schema is the only thing this program prints there.
    implicit val printer: Printer = Printer(s => System.err.print(s))
    implicit val env: SessionEnv =
      new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false))

    val all: (Option[String], List[Explicit[Global]], Boolean) = (None, List(), false)
    val imports = ("Builtin" :: mods).map(m => (m, all)).toMap
    // the module the $id is attributed to, and the scope a record's
    // unqualified field names resolve in: the last -i wins, as the
    // right-most import is the one a user names the type from
    val module = mods.lastOption.getOrElse("Builtin")

    try {
      Lib.preamble
      if (mods.nonEmpty) Session.loadModules(mods)
      val ty = NewPipeline.replType("<type>", source, imports)
      Schema.exportType(ty, module) match {
        case Left(e) => fail(e.report)
        case Right(schema) =>
          if (!zod) println(Schema.text(schema))
          else Zod.render(schema) match {
            case Left(e)  => fail("zod: " + e)
            case Right(t) => print(t)
          }
      }
    } catch {
      case scalaparsers.Death(d, _) => fail(d.toString)
      case e: Exception => fail(Option(e.getMessage).getOrElse(e.toString))
    }
  }

  private def fail(msg: String): Nothing = {
    System.err.println(msg)
    System.out.flush()
    System.err.flush()
    sys.exit(1)
  }
}
