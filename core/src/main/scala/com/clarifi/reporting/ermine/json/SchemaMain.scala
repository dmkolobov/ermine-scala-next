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
  *
  * WP-32 adds two bundle modes, both zod and both one module on stdout:
  *
  * {{{
  *   bin/ermine-schema --zod Layout.Doc:Node=DocNode Layout.Widgets.Format:CellFormat
  *   bin/ermine-schema --widgets Layout.Widgets Layout.Doc:Node=DocNode
  * }}}
  *
  * `--zod M:T[=Alias] ...` exports every named type in ONE walk
  * (`Schema.exportMany`), so a def several of them reach is emitted once.
  * `--widgets U` loads `U` and every module under its directory, finds each
  * term DECLARED there whose type is `Layout.Doc.WidgetName T`, evaluates it
  * for the name string and exports `T`; `Zod.renderBundle` then writes the
  * `WidgetRegistry` interface, `WidgetName`, `WIDGET_PROP_SCHEMAS` and
  * `UNSUPPORTED_WIDGETS` (the names whose `T` has no constructors, e.g.
  * `Layout.Widgets.Unsupported`).  One name at two props types is an error
  * naming both terms.  The header records the command line, what the scan
  * found per module, and the sha256 of every `.e` file the run read, for a
  * JVM-free staleness check on the client side.
  */
object SchemaMain {

  private val usage =
    """usage: ermine-schema [--zod] [-i Module ...] '<type expression>'
      |       ermine-schema --zod Module:Type[=Alias] ...
      |       ermine-schema --widgets Layout.Widgets [Module:Type[=Alias] ...]
      |
      |  -i M '<type>'      the JSON Schema (with --zod: the zod module) of one type
      |  --zod M:T ...      ONE zod module for several types: every definition they
      |                     reach once, each type also under its short name
      |                     (T, TSchema) or the =Alias given
      |  --widgets M        scan module M and every module under its directory for
      |                     terms of type `WidgetName T`: the zod of every props
      |                     type T, plus WidgetRegistry, WidgetName,
      |                     WIDGET_PROP_SCHEMAS and UNSUPPORTED_WIDGETS
      |
      |The output goes to stdout.""".stripMargin

  /** `Module:Type` or `Module:Type=Alias`: a data type named by its module. */
  private val RootArg = """([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*):([A-Z][A-Za-z0-9_']*)(?:=([A-Za-z_$][A-Za-z0-9_$]*))?""".r

  def main(args: Array[String]): Unit = {
    var zod = false
    var widgets: Option[String] = None
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
      case "--widgets"       =>
        if (i + 1 >= as.length) bad = Some("--widgets needs a module name")
        else { widgets = Some(as(i + 1)); zod = true; i += 2 }
      case other if other.startsWith("-") => bad = Some("unknown option " + other)
      case other             => rest = rest :+ other; i += 1
    }
    bad foreach { m => fail(m + "\n" + usage) }
    val bundle = widgets.isDefined || (rest.nonEmpty && rest.forall(r => RootArg.unapplySeq(r).isDefined))
    if (bundle) {
      val notRoot = rest.filterNot(r => RootArg.unapplySeq(r).isDefined)
      if (notRoot.nonEmpty) fail("not a Module:Type[=Alias]: " + notRoot.mkString(" ") + "\n" + usage)
      if (!zod) fail("several Module:Type roots are a zod bundle: add --zod\n" + usage)
      if (mods.nonEmpty) fail("-i is for one type expression; a bundle names each type's module (Module:Type)")
      runBundle(args.toList, widgets, rest)
      return
    }
    if (rest.length != 1) fail(usage)
    val source = rest.head

    val booted = boot()
    implicit val supply: Supply = booted._1
    implicit val printer: Printer = booted._2
    implicit val env: SessionEnv = booted._3

    val all: (Option[String], List[Explicit[Global]], Boolean) = (None, List(), false)
    val imports = ("Builtin" :: mods).map(m => (m, all)).toMap
    // the module the $id is attributed to, and the scope a record's
    // unqualified field names resolve in: the last -i wins, as the
    // right-most import is the one a user names the type from
    val module = mods.lastOption.getOrElse("Builtin")

    guarded {
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
    }
  }

  private def boot(): (Supply, Printer, SessionEnv) = {
    com.clarifi.reporting.util.Logging.initializeLogging
    // Session chatter (load progress, timings) must not corrupt stdout: the
    // schema is the only thing this program prints there.
    (Supply.create, Printer(s => System.err.print(s)),
     new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false)))
  }

  private def guarded(body: => Unit): Unit =
    try body catch {
      case scalaparsers.Death(d, _) => fail(d.toString)
      case e: Exception => fail(Option(e.getMessage).getOrElse(e.toString))
    }

  // ---------------------------------------------------------------------
  // WP-32: one module for several types, and the widget scan

  private val WidgetNameG = Global("Layout.Doc", "WidgetName")

  /** A `WidgetName T` term found by the scan. */
  final case class Found(module: String, term: String, name: String, props: Type)

  private def strip(t: Type): Type = t match {
    case Memory(_, b)             => strip(b)
    case Forall(_, _, _, _, b)    => strip(b)
    case other                    => other
  }

  private def unfurl(t: Type, args: List[Type] = Nil): (Type, List[Type]) = t match {
    case AppT(f, a)   => unfurl(f, strip(a) :: args)
    case Memory(_, u) => unfurl(u, args)
    case other        => (other, args)
  }

  /** `T` has no values: a data type with no constructors (`data Unsupported`). */
  private def uninhabited(t: Type): Boolean = unfurl(strip(t))._1 match {
    case Type.Con(_, g, decl, _) =>
      (decl match {
        case d: DataConDecl => Some(d)
        case _              => DataConDecl.forType(g)
      }).exists(_.constructors.isEmpty)
    case _ => false
  }

  /** The umbrella module and every module under its directory (sorted),
    * from the file the loader would read the umbrella from. */
  def modulesUnder(umbrella: String): Either[String, List[String]] =
    Session.SourceFile.classloader()(umbrella) match {
      case None        => Left("--widgets " + umbrella + ": no such module")
      case Some(Session.Filesystem(f, _)) =>
        val dir = new java.io.File(f.stripSuffix(".e"))
        def walk(d: java.io.File, prefix: String): List[String] =
          Option(d.listFiles).map(_.toList).getOrElse(Nil).sortBy(_.getName).flatMap { f =>
            if (f.isDirectory) walk(f, prefix + f.getName + ".")
            else if (f.getName.endsWith(".e")) List(prefix + f.getName.stripSuffix(".e"))
            else Nil
          }
        Right(umbrella :: walk(dir, umbrella + "."))
      case Some(other) =>
        Left("--widgets " + umbrella + ": its source is not a file (" + other + "); cannot list its directory")
    }

  private def sha256(bytes: Array[Byte]): String =
    java.security.MessageDigest.getInstance("SHA-256").digest(bytes).map(b => "%02x".format(b & 0xff)).mkString

  private def shellQuote(a: String): String =
    if (a.nonEmpty && a.forall(c => c.isLetterOrDigit || "_./:=-@%+,".contains(c))) a
    else "'" + a.replace("'", "'\\''") + "'"

  private val sourceRoot = "core/src/main/resources/modules"

  private def runBundle(argv: List[String], widgets: Option[String], rootArgs: List[String]): Unit = {
    val booted = boot()
    implicit val supply: Supply = booted._1
    implicit val printer: Printer = booted._2
    implicit val env: SessionEnv = booted._3
    guarded {
      val requested: List[(String, String, Option[String])] = rootArgs.map {
        case RootArg(m, t, a) => (m, t, Option(a))
        case other            => fail("not a Module:Type[=Alias]: " + other)
      }
      val scan = widgets.map(w => (w, modulesUnder(w).fold(fail, identity)))
      Lib.preamble
      Session.loadModules((scan.map(_._2).getOrElse(Nil) ++ requested.map(_._1)).distinct)
      generate(argv, scan, requested) match {
        case Left(e)  => fail(e)
        case Right(t) => print(t)
      }
    }
  }

  private final class Refuse(msg: String) extends RuntimeException(msg, null, false, false)
  private def refuse(msg: String): Nothing = throw new Refuse(msg)

  /** The widget terms declared in `modules` (already loaded): every term of
    * type `WidgetName T` DECLARED there -- a re-export (`export
    * Layout.Widgets.Table` in the umbrella) is a Global of the umbrella too,
    * with an origin elsewhere, and is skipped -- with its name string, read
    * by evaluating the term. */
  def widgetsIn(modules: List[String])(implicit env: SessionEnv): Either[String, List[Found]] =
    try Right(modules.flatMap { m =>
      env.termNames.toList.filter { case (g, _) =>
        g.module == m && env.termNameOrigins.get(g).forall(_.forall(_.module == m))
      }.sortBy(_._1.string).flatMap { case (g, v) =>
        unfurl(strip(v.extract)) match {
          case (Type.Con(_, WidgetNameG, _, _), t :: Nil) =>
            val value = env.env.get(v).getOrElse(refuse(g.toString + ": no value in the session"))
            value.whnf match {
              case d: com.clarifi.reporting.ermine.Data if d.arr.length == 1 => d.arr(0).whnf.extract[Any] match {
                case str: String => List(Found(m, g.string, str, t))
                case other       => refuse(g.toString + ": the WidgetName does not hold a string: " + other)
              }
              case other => refuse(g.toString + ": cannot read the name out of " + other)
            }
          case _ => Nil
        }
      }
    }) catch { case r: Refuse => Left(r.getMessage) }

  /** The bundle `--zod M:T ...` / `--widgets U` prints, over modules already
    * loaded: `scan` is the umbrella's name and the modules to scan, `argv`
    * only goes into the header. */
  def generate(argv: List[String], scan: Option[(String, List[String])],
               requested: List[(String, String, Option[String])])
              (implicit env: SessionEnv): Either[String, String] =
    try {
      val found: List[Found] = scan match {
        case None         => Nil
        case Some((_, ms)) => widgetsIn(ms).fold(refuse, identity)
      }
      val unsupported = found.filter(f => uninhabited(f.props))
      val supported   = found.filterNot(f => uninhabited(f.props))

      // -- one walk over every root: the requested ones, then one per widget term
      val roots: List[(Type, String)] =
        requested.map { case (m, t, _) =>
          env.cons.get(Global(m, t)) match {
            case Some(c) => (c: Type, m)
            case None    => refuse("the module " + m + " declares no type " + t)
          }
        } ++ supported.map(f => (f.props, f.module))
      val b = Schema.exportMany(roots) match {
        case Left(e)  => refuse(e.report)
        case Right(x) => x
      }
      val (reqBodies, widgetBodies) = b.roots.splitAt(requested.length)
      val bodyOf: Map[Found, argonaut.Json] = supported.zip(widgetBodies).toMap
      def where(f: Found) = f.module + "." + f.term
      def propsLabel(f: Found) =
        if (uninhabited(f.props)) "no props (" + Schema.renderType(f.props) + ")" else Schema.renderType(f.props)

      // -- a name declared twice must mean one props type
      found.groupBy(_.name).toList.sortBy(_._1) foreach { case (n, fs) =>
        val kinds = fs.map(f => if (uninhabited(f.props)) None else Some(bodyOf(f))).distinct
        if (kinds.length > 1)
          refuse("the widget name \"" + n + "\" is declared with different props types: " +
               fs.map(f => where(f) + " : WidgetName " + propsLabel(f)).mkString(", "))
      }

      val requestedRoots = requested.zip(reqBodies).map { case ((m, t, a), body) =>
        Zod.Root(m + ":" + t, a, body) }
      // one root per distinct props body; the label of the first term that reached it
      val widgetRoots: List[(argonaut.Json, Zod.Root)] =
        supported.map(f => (bodyOf(f), f)).groupBy(_._1).toList.map { case (body, fs) =>
          val f = fs.map(_._2).minBy(where)
          (body, Zod.Root(f.module + ":" + Schema.renderType(f.props), None, body))
        }.sortBy(_._2.label)
      val registry = supported.map(f => Zod.Widget(f.name, widgetRoots.find(_._1 == bodyOf(f)).get._2.label))
        .distinct.sortBy(_.name)

      // -- the header: the command, what was scanned, what was read
      val header = new scala.collection.mutable.ListBuffer[String]
      header += "command: bin/ermine-schema " + argv.map(shellQuote).mkString(" ")
      scan foreach { case (w, ms) =>
        header += ""
        header += "scanned for `WidgetName T` terms: " + w + " and every module under its directory"
        val width = ms.map(_.length).max
        ms foreach { m =>
          val here = found.filter(_.module == m).sortBy(_.name)
          header += "  " + m.padTo(width, ' ') + "  " +
            (if (here.isEmpty) "no WidgetName term: not a widget"
             else here.map(f => f.name + " : " + propsLabel(f)).mkString(", "))
        }
      }
      header += ""
      header += "sources: the sha256 of every .e file this run read, by path under " + sourceRoot
      val files: List[(String, String)] = env.loadedFiles.toList.flatMap { case (sf, m) =>
        val rel = m.replace('.', '/') + ".e"
        val bytes: Option[Array[Byte]] = sf match {
          case Session.Filesystem(f, _) => Some(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(f)))
          case Session.Resource(_, url) =>
            val in = url.openStream()
            try Some(in.readAllBytes()) finally in.close()
          case _ => None
        }
        bytes.map { bs =>
          val h = sha256(bs)
          val src = new java.io.File(sourceRoot, rel)
          if (src.isFile && sha256(java.nio.file.Files.readAllBytes(src.toPath)) != h)
            System.err.println("warning: the " + rel + " this run read differs from " + src.getPath +
                               " (stale resources? run sbt core/copyResources)")
          (rel, h)
        }
      }.sortBy(_._1)
      files foreach { case (rel, h) => header += "sha256 " + h + " " + rel }

      val origins: Map[String, (String, Boolean)] = b.origins.map { case (d, (g, targs)) =>
        (d, (g.string, targs.forall(a => strip(a) match { case VarT(_) => true; case _ => false })))
      }
      Zod.renderBundle(b.defs, origins, requestedRoots ++ widgetRoots.map(_._2),
                       scan.map(_ => (registry, unsupported.map(_.name).distinct.sorted)),
                       header.toList).left.map("zod: " + _)
    } catch { case r: Refuse => Left(r.getMessage) }

  private def fail(msg: String): Nothing = {
    System.err.println(msg)
    System.out.flush()
    System.err.flush()
    sys.exit(1)
  }
}
