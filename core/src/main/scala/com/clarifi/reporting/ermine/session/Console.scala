package com.clarifi.reporting
package ermine
package session

import scala.io.{ Source }

import org.jline.reader.{ EndOfFileException, LineReader, LineReaderBuilder, UserInterruptException }
import org.jline.reader.impl.completer.{ AggregateCompleter, ArgumentCompleter, FileNameCompleter, StringsCompleter }
import org.jline.terminal.{ Terminal, TerminalBuilder }
import org.jline.utils.InfoCmp.Capability
import scala.jdk.CollectionConverters._
import java.awt.Toolkit
import java.awt.datatransfer.{Clipboard, DataFlavor}

import java.util.Date
import java.io.{ PrintWriter, InputStream, FileInputStream, FileDescriptor, OutputStreamWriter }
import java.io.File.separator
import java.lang.Exception
import scala.collection.immutable.List
import scalaz.Monad
import scalaz.Scalaz._

import com.clarifi.reporting.ermine.parsing.{
  phrase, semi, eof,
  startingKeywords, otherKeywords,
  ParseState, ErParseState,
  ModuleHeader, ModuleParsers
}
import ErParseState.Implicits._
import com.clarifi.reporting.ermine._
import scalaparsers.{Death, DocException, Document, Supply}
import scalaparsers.Document._
import com.clarifi.reporting.ermine.Pretty.{
  prettyRuntime, prettyType, prettyKind, prettyVarHasType, prettyVarHasKind, prettyTypeHasKindSchema, prettyConHasKindSchema
}
import com.clarifi.reporting.ermine.Type.typeVars
import com.clarifi.reporting.ermine.Term.{ eval, termVars }
import com.clarifi.reporting.ermine.Subst.{ inferType, inferKind }
import com.clarifi.reporting.ermine.session.Session.{
  load, loadModule, loadModules, primOp, SourceFile, Filesystem, loadModulesInSeries, subst
}
import com.clarifi.reporting.ermine.session.Printer.{ benchmark, sayLn }
import syntax.{Renaming, Explicit, Statement, ImportExportStatement, ImportExportCommand, ModuleCommand, ExpressionCommand, EmptyCommand}

import com.clarifi.reporting.backends.{ SqlErmine, Runners }

case class Mark(currentResult: Int, imports: Map[String, (Option[String],List[Explicit[Global]],Boolean)], sessionEnv: SessionEnv)

case class ConsoleException(msg: Option[Document] = None) extends Exception(msg.getOrElse(text("error")).toString)

abstract class Action(val name: String, val alts: List[String], arg: Option[Document], desc: Document) {
  def apply(s: String)(implicit e: ConsoleEnv): Unit
  private def argDoc = arg match {
    case Some(n) => space :: n
    case None => empty
  }
  def doc = text("    " + name) :: argDoc :: column(n => (" " * (30 - n)) :: nest(2, desc))
  def matches(s: String) = name.startsWith(s) || alts.exists(_ startsWith s)
}

class ConsoleEnv(
  _sessionEnv: SessionEnv,
  val in: InputStream = new FileInputStream(FileDescriptor.in),
  val out: PrintWriter = new PrintWriter(new OutputStreamWriter(System.out)),
  // `dumb` lets the REPL still run when stdin is not a tty (a pipe, a test
  // harness, CI); jline 3 otherwise refuses to build a system terminal.
  val terminal: Terminal = TerminalBuilder.builder().system(true).dumb(true).build()
) {
  implicit val supply: Supply = Supply.create
  implicit val con: Printer = new Printer {
    def apply(s: String): Unit = {
      terminal.writer.print(s)
      terminal.writer.flush()
    }
  }

  // can't make this a val without losing sessionEnv = syntax. also, functions that take this often throw exceptions
  // so use the session(implicit s => ...) combinator instead
  def sessionEnv: SessionEnv = _sessionEnv

  var quit: Boolean = false
  var helpHinted: Boolean = false
  def helpHint: Unit = {
    if (!helpHinted) {
      sayLn("Use \":help\" to see a list of commands")
      helpHinted = true
    }
  }

  // mark/release
  var marks: List[Mark] = List()
  def sayLnMarks: Unit = {
    val n = marks.length
    sayLn(Ordinal(n, "entry", "entries") :+: text("in the mark stack."))
  }
  var namedMarks: Map[String, Mark] = Map()

  var currentResult: Int = 0

  def mark = Mark(currentResult, imports, sessionEnv.copy)
  def mark_=(m: Mark): Unit = {
    currentResult = m.currentResult
    imports = m.imports
    sessionEnv_=(m.sessionEnv)
  }

  // repl and autocomplete
  //
  // jline 1's SimpleCompletor was mutable (`setCandidateStrings`); jline 3's
  // StringsCompleter instead reads its candidates from a supplier on each
  // completion, so `updateCompletor` just swaps the collection below.
  @volatile private var candidateStrings: java.util.Collection[String] =
    new java.util.ArrayList[String]()

  val completor: StringsCompleter =
    new StringsCompleter(() => candidateStrings)

  val loadCompletor: ArgumentCompleter = new ArgumentCompleter(
    new StringsCompleter(":load", ":fsloader"),
    new FileNameCompleter
  )
  loadCompletor.setStrict(true)

  val argCompletor: ArgumentCompleter = new ArgumentCompleter(
    new AggregateCompleter(
      new StringsCompleter(
        (Console.actions.flatMap(a => a.name :: a.alts) ++ startingKeywords).asJava),
      completor
    ),
    completor
  )
  argCompletor.setStrict(false)

  val reader: LineReader = LineReaderBuilder.builder()
    .terminal(terminal)
    .completer(new AggregateCompleter(loadCompletor, argCompletor))
    .variable(LineReader.BELL_STYLE, "none")
    .build()

  /** jline 1 masked input with a reader-level echo character; jline 3 takes the
    * mask per `readLine`, so the toggle lives here.
    */
  var echoCharacter: java.lang.Character = null

  /** jline 1 returned null at end of input; jline 3 throws. */
  def readLine(prompt: String): String =
    try reader.readLine(prompt, echoCharacter)
    catch {
      case _: EndOfFileException   => null
      case _: UserInterruptException => ""
    }

  var imports: Map[String, (Option[String],List[Explicit[Global]],Boolean)] = Map() // module -> affix

  def asImported(g: Name): Name = g match {
    case g : Global => imports.get(g.module) match {
      case Some((as,explicits,_)) => g.localized(as, Explicit.lookup(g, explicits))
      case None => g
    }
    case _ => g
  }

  def updateCompletor: Unit = {
    val ps = parseState("")
    val names = otherKeywords ++ (ps.s.termNames.keySet ++ ps.s.typeNames.keySet ++ ps.s.kindNames.keySet).map(_.string)
    candidateStrings = new java.util.ArrayList[String](names.asJava)
  }

  def assumeClosed(t: Term)(doIt: => Unit): Unit = {
    val env = sessionEnv.env
    val undefinedTerms = (termVars(t) -- env.keySet).toList
    val undefinedTypes = typeVars(t).toList
    if (undefinedTerms.isEmpty && undefinedTypes.isEmpty) doIt
    else {
      sayLn(vsep(undefinedTerms.map(v => v.report("error: undefined term"))))
      sayLn(vsep(undefinedTypes.map(v => v.report("error: undefined type"))))
    }

  }

  def eval(t: Term)(k: Runtime => Unit): Unit = {
    assumeClosed(t) {
      Term.eval(t, sessionEnv.env) match {
        case b : Bottom => b.inspect
        case e => k(e)
      }
    }
  }

  def importing(m: String, affix: Option[String], exp: List[Explicit[Global]], using: Boolean): Unit = { imports = imports + (m -> (affix, exp, using)) }

  updateCompletor

  def sessionEnv_=(s: SessionEnv): Unit = {
    sessionEnv := s
    updateCompletor
  }

  def parseState(s: String) = ErParseState.mk("<interactive>", s, "REPL").importing(sessionEnv.termNames, sessionEnv.cons.keySet, imports, sessionEnv.termNameOrigins, sessionEnv.consOrigins)

  /** The console's import scope over the split pipeline (D3: command
    * ARGUMENTS parse there; the ':' command grammar itself stays). */
  def importScope: com.clarifi.reporting.ermine.rename.ModuleScope.Scope =
    com.clarifi.reporting.ermine.rename.ModuleScope.importing("REPL",
      com.clarifi.reporting.ermine.rename.ModuleScope.Scope.empty,
      sessionEnv.termNames, sessionEnv.cons.keySet, imports,
      sessionEnv.termNameOrigins, sessionEnv.consOrigins)
  def pipelineTerm(s: String): Term =
    com.clarifi.reporting.ermine.rename.NewPipeline.replTerm("<interactive>", s, imports)(sessionEnv, supply)
  def pipelineType(s: String): Type =
    com.clarifi.reporting.ermine.rename.NewPipeline.replType("<interactive>", s, imports)(sessionEnv, supply)


  def session[A](s: SessionEnv => A): Option[A] = {
    val envp = sessionEnv.copy
    try {
      val r = s(sessionEnv)
      updateCompletor
      Some(r)
    } catch { case e@Death(err, _) =>
      sessionEnv = envp
      sayLn(err)
      stackHint
      stackHandler = () => sayLn(e.getStackTrace.mkString("\n"))
      None
    }
  }

  def subst[A](s: SubstEnv => A): Option[A] = session(implicit hm => Session.subst(s))

  var stackHinted: Boolean = false
  def stackHint: Unit = {
    if (!stackHinted) {
      sayLn("Use \":stack\" to see a stack trace")
      stackHinted = true
    }
  }

  val ok = () => sayLn("OK")
  var stackHandler: () => Unit = ok

  def handling(a: => Unit) = try a catch {
    case e : DocException =>
      sayLn("runtime error:")
      sayLn(e.doc)
      stackHint
      stackHandler = () => e.printStackTrace(out)
    case e : Throwable =>
      sayLn("runtime error: " + e.getMessage)
      stackHint
      stackHandler = () => e.printStackTrace(out)
  }

  // if we have a bottom, we want to set the stackHandler
  def handlingBot(a: Throwable) = {
    stackHint
    stackHandler = () => a.printStackTrace(out)
  }

  def conMap(ps: ParseState) = Type.conMap("REPL", ps.s.typeNames, sessionEnv.cons)

  def fixCons[A](ps: ParseState, a: A)(implicit A: HasTypeVars[A]) =
    Type.subType(conMap(ps), a)
}

object Console {
  def writeLn(s: Document)(implicit e: ConsoleEnv) = sayLn(s)(e.con)
  def mark(implicit e: ConsoleEnv) = e.mark
  def session[A](s: SessionEnv => A)(implicit e: ConsoleEnv): Option[A] = e.session(s)
  def importing(m: String, affix: Option[String] = None)(implicit e: ConsoleEnv) = e.importing(m, affix, List(), false)
  def sessionEnv(implicit e: ConsoleEnv) = e.sessionEnv

  /** Partially reverse `sbt.JLine.fixTerminalProperty` (as of 0.13.0),
    * which might work for scala REPL, but not for us.
    *
    * This is a jline 1 property; jline 3 reads `org.jline.terminal.dumb`
    * instead, so it only matters when something else in the JVM still uses
    * jline 1.
    */
  private[reporting]
  def unfixSbtTerminalProperty(): Unit = {
    val termprop = "jline.terminal"
    Option(System.getProperty(termprop)) collect {
      case "none" => "jline.UnsupportedTerminal"
    } foreach (System.setProperty(termprop, _))
  }

  val header = """
    Commands available from the prompt:

    <expr>                    evaluate <expr>
    <statement>               evaluate <statement>"""

  val help = new Action(":help", List("help",":?"), None, "print this message") {
    def apply(s: String)(implicit e: ConsoleEnv): Unit = {
      writeLn(text(header) above vsep(actions.map(_.doc)))
    }
  }

  def loadProject(s: String)(implicit e: ConsoleEnv): Unit = {
    import e.{con,supply}
    benchmark(session(implicit se => load(Filesystem(s, exotic=true)))) {
      case Some(n) =>
        importing(n)
        "Importing module '" + n + "'"
      // name the FILE: in a batch load (many paths on one command line) the bare
      // message said nothing about which of them failed.  The verdict scripts grep the
      // prefix "Unable to load module", which is unchanged.
      case None    => "Unable to load module from '" + s + "'"
    }
  }

  val actions: List[Action] = List(
    new Action(":help", List("help",":?"), None, "print this message") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = { writeLn(text(header) above vsep(actions.map(_.doc))) }
    },
    new Action(":paste", List(), None, "Parse Ermine statements or expressions from the clipboard") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        val clipboard = Toolkit.getDefaultToolkit.getSystemClipboard
        val content = clipboard.getData(DataFlavor.stringFlavor)
        val str = content.toString
        writeLn(str)
        other(str)
      }
    },
    new Action(":quit", List("quit",":exit","exit"), None, "end this session") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = { e.quit = true }
    },
    new Action(":stack", List(), None, "print the stack trace of the last error") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = { e.stackHandler() }
    },
    new Action(":crash",List(),None,"crash") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = { 1/0; () }
    },
    new Action(":slowload",List(),None, "reload all of the modules for the current session (slowly and incorrectly)") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        import e.{con,supply}
        val prior = new Date()
        val old = e.mark
        val files = old.sessionEnv.loadedFiles
        e.mark = e.namedMarks("lib")
        val ok = e.session(implicit s => loadModules(files.values.toList)).isDefined
        if (!ok) {
          e.mark = old
          writeLn("Error during reload, reverting.")
        } else {
          val now = new Date()
          val secs = (now.getTime() - prior.getTime()) / 1000.0
          e.imports = old.imports
          writeLn("Reloaded" :+: ordinal(files.toList.length, "module","modules") :+: "successfully in" :+: secs.toString :+: text("seconds."))
        }
      }
    },
    new Action(":slowerload",List(),None, "reload all of the modules for the current session (slowly and incorrectly)") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        import e.{con,supply}
        val prior = new Date()
        val old = e.mark
        val files = old.sessionEnv.loadedFiles
        e.mark = e.namedMarks("lib")
        val ok = e.session(implicit s => loadModulesInSeries(files.values.toList)).isDefined
        if (!ok) {
          e.mark = old
          writeLn("Error during reload, reverting.")
        } else {
          val now = new Date()
          val secs = (now.getTime() - prior.getTime()) / 1000.0
          e.imports = old.imports
          writeLn("Reloaded" :+: ordinal(files.toList.length, "module","modules") :+: "successfully in" :+: secs.toString :+: text("seconds."))
        }
      }
    },
    new Action(":reload",List(),None, "reload all of the modules for the current session (intelligently)") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        val prior = new Date();
        val old = e.mark
        val lib = e.namedMarks("lib")
        import e.{con,supply}
        val ok = session{implicit s =>
          Session.reloadChangedModules(extraScrubbingModules=Set("REPL"),
                                       builtinEnv = lib.sessionEnv.copy)
        }.isDefined
        e.currentResult = 0
        if (!ok) {
          e.mark = old
        }
      }
    },
    new Action(":fsloader",List(), Some("<directory>"), "add a loader from a given file path") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        e.sessionEnv.loadFile = SourceFile.inOrder(
          SourceFile.filesystem(s) ,e.sessionEnv.loadFile)
      }
    },
    new Action(":mark",List(),Some("[key]"),"save the current session state for later release") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        val m = e.mark
        e.marks = m :: e.marks
        if (!s.isEmpty) {
          e.namedMarks = e.namedMarks + (s -> m)
          writeLn("Named mark created: " + s)
        }
        e.sayLnMarks
      }
    },
    new Action(":history",List(), None, "show the list of named marks") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        e.sayLnMarks
        e.namedMarks.keySet.toList match {
          case List() => writeLn("No named marks")
          case marks => writeLn("Named marks:" :+: nest(2, fillSep(punctuate(",", marks.map(text(_))))))
        }
      }
    },
    new Action(":release", List(), Some("[key]"), "restore to a given session state") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        if (s.isEmpty) e.marks match {
          case List() => writeLn("No marks!")
          case List(a) => e.mark = a
          case a :: as => e.mark = a
                          e.marks = as
                          e.sayLnMarks
        }
        else e.namedMarks.get(s) match {
          case Some(a) => e.mark = a
          case None    => writeLn("No such mark")
        }
      }
    },
    new Action(":load", List(), Some("<filename>"), "Load a module from a source file") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        loadProject(s)
      }
    },

    // parse and load
    new Action(":parse", List(), Some("<expr>"), "Parse and pretty print an expression") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit =
        writeLn(e.pipelineTerm(s).toString)
    },
    new Action(":eval", List(), Some("<expr>"), "Evaluate an expression") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit =
        e.eval(e.pipelineTerm(s)) { r => writeLn(prettyRuntime(r)) }
    },
    new Action(":imports", List(), None, "Summarize the currently imports") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        val modules = e.imports.toList.sortWith((p,q) => p._1 < q._1).map({
          case (k,(None,_,_))    => text(k)
          case (k,(Some(a),_,_)) => text(k) :+: "as" :+: text(a)
        }).toList
        writeLn("Imports:" :+: nest(2, fillSep(punctuate(",", modules))))
        writeLn("Files:" :+: nest(2, fillSep(punctuate(",",
           e.sessionEnv.loadedFiles.toList.sorted.map({
             case (k,v) => text(k.toString) :+: "=>" :+: text(v)
           }))))
        )
        writeLn("Modules:" :+: nest(2, fillSep(punctuate(",", e.sessionEnv.loadedModules.keySet.toList.sorted.map(text(_))))))
      }
    },
    new Action(":source", List(), Some("<module>"), "Show a module's Ermine source code") {
      def apply(s: String)(implicit e: ConsoleEnv) =
        writeLn(e.sessionEnv.loadedFiles.find(_._2 == s)
                map {case (mod, _) =>
                  val rawlines = ("""\r\n|\r|\n""".r split mod.contents view)
                  val lines =
                    if (rawlines.last isEmpty) rawlines.init else rawlines
                  val numwidth = lines.size.toString.size
                  "Contents of" :+: mod.toString :: text(":") above
                     vsep(lines.zipWithIndex map {case (line, n) =>
                       val sn = (n+1).toString
                       (" " * (numwidth - sn.size)) :: sn :: "  " :: text(line)} toStream)}
                getOrElse ("No module for" :+: s :: "."))
    },
    new Action(":groups", List(), Some("<module>"), "Show the binding groups for a module") {
      def apply(s: String)(implicit e: ConsoleEnv) = {
        // HACK: strip out term names for this module if it's already loaded, otherwise
        // get errors
        val e2Env = e.sessionEnv.copy
        e2Env.termNames = e.sessionEnv.termNames.filterKeys(g => g.module != s).toMap
        e2Env.loadedFiles.find(_._2 == s) map { case (mod, modName) =>
          Session.parseModule(modName, mod.contents, modName)(e.sessionEnv, e.supply) match {
            case Left(err) => writeLn(err.toString)
            case Right(m) => writeLn {
              ImplicitBinding.implicitBindingComponents(
                m.implicits ++ m.explicits.map(_ forgetSignature)
              ).map(bs => bs.map(_.v.name.get.string).mkString(", ")).mkString("\n\n")
            }
          }
        }
      }
    },
    new Action(":clear", List(), None, "Clear the screen") {
      def apply(s: String)(implicit e: ConsoleEnv) =
        if (!e.terminal.puts(Capability.clear_screen))
          writeLn("\n"*e.terminal.getHeight) // can't clear the screen? come on
        else e.terminal.flush()
    },
    new Action(":type", List(), Some("<expr>"), "Infer the type of an expression") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        val tmp = e.pipelineTerm(s).close(e.supply)
        e.assumeClosed(tmp) {
          import e.supply
          e.subst(implicit hm => inferType(List(), tmp, true)) match {
            case Some(ty) =>
              val ftvs = Type.typeVars(tmp).toList
              if (ftvs.isEmpty) writeLn(prettyType(ty, -1))
              else for (v <- ftvs) writeLn(v.report("unresolved type variable"))
            case None     => ()
          }
        }
      }
    },
    new Action(":uglytype", List(), Some("<expr>"), "Infer the type of an expression, dumping the raw syntax") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        import e.supply
        e.subst(implicit hm => inferType(List(), e.pipelineTerm(s), true)) match {
          case Some(ty) => writeLn(ty.toString)
          case None     => ()
        }
      }
    },
    new Action(":browse", List(), Some("[substring]"), "Show the types of all known terms (optionally filtered)") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        val (types, terms) = describeEnvironment(e.importScope, e.sessionEnv, s)
        def render(ts: Iterable[(Local, (Option[String], Document))]) =
          ((ts groupBy (_._2._1)
            mapValues (_.toSeq sortBy (_._1.string))).toSeq sortBy (_._1)
           foreach {case (mod, bindings) =>
             writeLn(mod map ("-- imported via" :+: _)
                     getOrElse text("-- defined in current module"))
             bindings foreach (p => writeLn(p._2._2))
          })
        render(types)
        render(terms)
      }
    },
    new Action(":kind", List(), Some("<type>"), "Infer the kind of a type") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        val fty = e.pipelineType(s).close(e.supply)
        val danglingTypes = typeVars(fty).toList
        if (danglingTypes.isEmpty) {
          import e.supply
          e.subst(implicit hm => inferKind(List(), fty)) match {
            case Some(ki) => writeLn(prettyTypeHasKindSchema(fty, ki))
            case None     => ()
          }
        } else {
          danglingTypes.foreach(t => writeLn(t.report("error: undefined type")))
        }
      }
    },
    new Action(":echo", List(), None, "Toggle character echo (for compatibility with some terminals)") {
      def apply(s: String)(implicit e: ConsoleEnv): Unit = {
        if (e.echoCharacter != null) {
          e.echoCharacter = null
          writeLn("Echo is on")
        }
        else {
          e.echoCharacter = java.lang.Character.valueOf(0)
          writeLn("Echo is off")
        }
      }
    }
  )

  /** Browse available types and terms prettily. */
  private def describeEnvironment(scope: com.clarifi.reporting.ermine.rename.ModuleScope.Scope,
                                  ss: SessionEnv,
                                  filt: String):
                              (Map[Local, (Option[String], Document)],
                               Map[Local, (Option[String], Document)]) = {
    val types = for {
      (tn: Local, List(cn: Global)) <- scope.canonicalTypes.filter(_._1.string.contains(filt))
      c <- ss.cons.get(cn).toList
    } yield ss.classes.get(c.name) match {
      case Some(cls) => (tn, Some(cn.module) -> cls.pretty)
      case None =>      (tn, Some(cn.module) -> (c.decl.desc :+: prettyConHasKindSchema(tn, c.schema)))
    }
    val terms = for {
      (tn: Local, List(cn)) <- scope.canonicalTerms.filter(_._1.string.contains(filt))
      mod = cn match {
        case Global(m, _, _) => Some(m)
        case _: Local => None
      }
      v <- scope.termNames.get(cn) match { case Some(x) => List(x); case None => Nil }
    } yield (tn, mod -> prettyVarHasType(v copy (name = Some(tn))))
    (types, terms)
  }

  def marked(s: String)(implicit e: ConsoleEnv): Unit = {
    e.namedMarks = e.namedMarks + (s -> e.mark)
  }

  def pushMark(implicit e: ConsoleEnv): Unit = {
    e.marks = e.mark :: e.marks
  }

  sealed trait Balance
  case object Balanced extends Balance
  case object Unbalanced extends Balance
  case object Borked extends Balance

  def balanced(s: String, stk: List[Char] = List()): Balance =
    if (s.length == 0) if (stk.isEmpty) Balanced else Unbalanced
    else s.head match {
      case c@('('|'['|'{') => balanced(s.tail, c :: stk)
      case ')' => stk match { case '(' :: xs => balanced(s.tail, xs)
                              case _         => Borked }
      case ']' => stk match { case '[' :: xs => balanced(s.tail, xs)
                              case _         => Borked }
      case '}' => stk match { case '{' :: xs => balanced(s.tail, xs)
                              case _         => Borked }
      case _ => balanced(s.tail, stk)
    }

  // parse an expression or statement
  def other(x: String)(implicit e: ConsoleEnv): Unit = {
    import e.{con,supply}
    var input = x
    var blank = false
    // D3: the fused StatementParsers.multiline probe is gone; a line
    // that ends mid-definition keeps the |> continuation heuristics
    val needMoar = x.trim.endsWith("=") || x.trim.endsWith("->") || x.trim.endsWith("do")
    val verbose = Set("case","let","where")
    while ((needMoar || (balanced(input) == Unbalanced) || verbose.exists(input.contains(_))) && !blank) {
      val last = e.readLine("|> ")
      blank = last == ""
      if (!blank) { input = input + "\n" + last }
    }
    val startLoc = scalaparsers.Pos.start("<interactive>", input)

    val mh = ModuleHeader(
      startLoc,
      "REPL",
      false,
      e.imports.map({
        case (m,(as, explicits, using)) => ImportExportStatement(startLoc, false, m, as, explicits, using)
      }).toList
    )
    // now we have input: import/export lines parse with the (kept)
    // header grammar; expressions and statement pastes ride the split
    // pipeline (expression tried first — `f = 3` fails it and falls
    // through to the module-statement load)
    def dispatch: syntax.Command =
      (ModuleParsers.importExportStatement << eof).run(e.parseState(input), e.supply.split) match {
        case Right((_, ie2)) => ImportExportCommand(ie2)
        case Left(_) if input.trim.isEmpty => EmptyCommand
        case Left(_) =>
          com.clarifi.reporting.ermine.surface.SurfaceParsers.expression("<interactive>", input) match {
            case Right(_) => ExpressionCommand(null)  // parsed; replTerm below re-parses with resolution
            case Left(_)  => ModuleCommand(null)
          }
      }
    dispatch match {
      case ImportExportCommand(ImportExportStatement(loc, false, module, as, explicits, using)) =>
        val oldSessionState = e.sessionEnv
        if (e.sessionEnv.loadedModules.contains(module)) e.importing(module, as, explicits, using)
        else {
          e.session(implicit s =>
            benchmark(loadModules(List(module))) {
              ss => "Loaded" :+: ordinal(ss.size,"module","modules")
            }
          ) match {
            case Some(n) => e.importing(module, as, explicits, using)
            case _ => ()
          }
        }

      case ImportExportCommand(ImportExportStatement(loc, true, module, as, explicits, using)) =>
        writeLn("Ignoring export command")

      case ModuleCommand(_) => e.session { implicit s =>
        val (psNew, m) = com.clarifi.reporting.ermine.rename.NewPipeline.readModule(
          "<interactive>", input, mh)(s, e.supply)
        loadModule(psNew, m, _ => None)
      }
      case EmptyCommand => ()
      case ExpressionCommand(_) =>
        val at = e.pipelineTerm(input).close(e.supply)
        e.subst(implicit hm => inferType(List(), at)) match {
          case Some(ty) => e.eval(at) { case r =>
            val n = e.currentResult
            val v = Global("REPL","res" + n)
            def isIO(t: Type): (Boolean, Boolean) = t match {
              case f: Forall => isIO(f.body)
              case AppT(Type.Con(_,Global("Builtin","IO",Idfix),_,_), ProductT(_,0)) => (true, true)
              case AppT(Type.Con(_,Global("Builtin","IO",Idfix),_,_), _) => (true, false)
              case _ => (false, false)
            }
            def remember: Unit = {
              e.session(implicit s => primOp(startLoc, v, r, ty))
              writeLn(nest(2, v.string :/+: ":" :/+: prettyType(ty, -1) :/+: "=" :/+: prettyRuntime(r)))
              e.currentResult = e.currentResult + 1
            }
            val (run, silent) = isIO(ty)
            if (run)
              e.sessionEnv.termNames.get(Global("IO.Unsafe","unsafePerformIO")).flatMap {
                e.sessionEnv.env.get(_)
              } match {
                case Some(unsafePerformIO) => {
                  // If our value is bottom, set the stack trace to be the wrapped error's stack trace to aid debugging.
                  val res = unsafePerformIO(r)
                  res match {
                    case Bottom(msg) =>{ try println(msg.apply.toString) catch { case t: Throwable => e.handlingBot(t) }}
                    case x => x // do nothing
                  }
                  if (silent) res.extract[Any]
                  else writeLn(prettyRuntime( res ))
                  }
                case None =>
                  writeLn("warning: IO.Unsafe.unsafePerformIO not available")
                  remember
              }
            else remember
          }
          case None => ()
        }
    }
  }

  private val command = "\\s*(\\S*)\\s*(.*)".r
  // of course with all this we don't really need the trampoline
  def repl(implicit e: ConsoleEnv): Unit = {
    var line: String = null
    while (!e.quit && { line = e.readLine(">> "); line != null }) {
      e.handling(
        line match {
          case command(name, arg) if name.length > 1 =>
            actions.filter(_ matches name) match {
              case a :: _ => a(arg)
              case _ if name(0) == ':' =>
                writeLn("Unknown command: " + name.tail)
                e.helpHint
              case _ => other(line)
          }
          case _ => other(line)
        }
      )
    }
  }

  def databasePrefix: String = "Environment.DB"

  def baseDatabases: SourceFile.Loader =
    SqlErmine modules (databasePrefix, Runners.debugDatabases)

  def prelude = List[String]("Prelude","Layout")

  def loadAll(xs: List[String])(implicit e: ConsoleEnv): Unit = {
    import e.{con,supply}
    if (session(implicit s => benchmark(loadModules(xs)) { ss => "Loaded" :+: ordinal(ss.size, "module","modules") }).isDefined)
      xs.foreach(importing(_))
    else writeLn("Unable to load" :/+: oxford("and", xs.map(text(_))))
  }

  def loadArgs(xs: Array[String])(implicit e: ConsoleEnv): Unit = {
    xs.foreach(loadProject)
  }

  def version     = "v0.4α"
  def copyright   = "Copyright 2011-2015"
  def allrights   = "S&P Capital IQ"

  def logo(n: String, l: List[String])(implicit e: ConsoleEnv): Unit = l match {
    case l1 :: l2 :: l3 :: l4 :: rest =>
      writeLn(l1)
      writeLn(l2 + " " + n + " " + version)
      writeLn(l3 + " " + copyright)
      writeLn(l4 + " " + allrights)
      for (s <- rest) writeLn(s)
    case _ => fancyLogo // logo(ermineLogo._1, ermineLogo._2)
  }

  def ermineLogo = ("Ermine", List(
    """   ____                    """,
    """  / __/_____ _  ( )__  __  """,
    """ / _//`__/  ' \/ /`_ \/ -) """,
    """/___/_/ /_/_/_/_/_//_/\__/ """
  ))

  def fancyLogo(implicit e: ConsoleEnv): Unit = {
    writeLn("")
    writeLn("                                    _,-/\"---,")
    writeLn("             ;\"\"\"\"\"\"\"\"\"\";         _`;; \"\"  «@`---v")
    writeLn("           ; :::::  ::  \"'      _` ;;  \"    _.../")
    writeLn("          ;\"     ;;  ;;;  '\",-`::    ;;,'\"\"\"\"")
    writeLn("         ;\"          ;;;;.  ;;  ;;;  ::`    ____")
    writeLn("        ,/ / ;;  ;;;______;;;  ;;; ::,`    / __/_____ _  ( )__  __")
    writeLn("        /;; _;;   ;;;       ;       ;     / _//`__/  ' \\/ /`_ \\/ -)")
    writeLn("        | :/ / ,;'           ;_ \"\")/     /___/_/ /_/_/_/_/_//_/\\__/ " + version)
    writeLn("        ; ; / /\"\"\"=            \\;;\\\"\"=  Copyright © 2011-15 S&P Capital IQ")
    writeLn("     ;\"\"\"';{::\"\"\"\"\"\"=            \\\"\"\"=")
    writeLn("     \\/\"\"\"")
  }

  def rock(args: Array[String])(implicit e: ConsoleEnv): Unit = {
    import e.supply
    fancyLogo
    writeLn("")
    importing("REPL")
    marked("nolib")
    val lib = session(implicit s => Lib.preamble)
    importing("Builtin")
    marked("lib")
    if (lib.isDefined) loadAll(prelude)
    else writeLn("warning: Unable to load lib.")

    // load files passed in the args
    loadArgs(args)

    e.sessionEnv.loadFile =
      SourceFile inOrder (baseDatabases, e.sessionEnv.loadFile,
                          SourceFile filesystem Seq("core", "examples").mkString(separator),
                          SourceFile classloader "com/clarifi/reporting/examples")
    repl
  }

  def main(args: Array[String]): Unit = {
    com.clarifi.reporting.util.Logging.initializeLogging
    unfixSbtTerminalProperty()
    try {
      implicit val env = new ConsoleEnv(new SessionEnv)
      env.reader.setVariable(LineReader.HISTORY_FILE, java.nio.file.Paths.get(".ermine_history"))
      rock(args)
    } catch {
      case e : Throwable =>
        println("panic: " + e.getMessage)
        e.printStackTrace
    }
  }
}
