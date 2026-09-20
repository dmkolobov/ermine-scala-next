package com.clarifi.reporting.ermine.session

import com.clarifi.reporting.ermine.{ V, Global, Runtime, Type, Kind, Requirements, Pretty, SigEntail }
import com.clarifi.reporting.ermine.surface.Span
import com.clarifi.reporting.ermine.Type.subType
import com.clarifi.reporting.ermine.parsing.{ ModuleHeader }
import com.clarifi.reporting.ermine.Pretty.{ prettyType, ppType, ppName, ppVar }
import scalaparsers.Document._
import scala.collection.mutable.ListBuffer
import scalaz.Scalaz._
import scalaparsers.{Located, Loc, Document}

case class ClassDef(
  loc: Loc,
  name: Global,
  args: List[V[Kind]],
  sups: List[Type],
  destroy: Runtime => List[Runtime],
  instances: Map[Int, Instance]
) extends Requirements with Located {
  def ++(delta: Map[Int,Instance]) = ClassDef(loc, name, args, sups, destroy, instances ++ delta)
  def +(delta: (Int, Instance)) = ClassDef(loc, name, args, sups, destroy, instances + delta)
  def supers(ts: List[Type]): List[Type] = subType(args.zip(ts).toMap, sups)

  def resolve(args: List[Type]): List[Instantiation] = {
    val b = new ListBuffer[Instantiation]
    for (i <- instances.values)
      for (reqs <- i.reqs(args))
        b += Instantiation(i, args, reqs)
    b.toList
  }

  // @throws Death when the instance is ambiguous
  def reqs(l: Located, args: List[Type]): Option[List[Type]] = {
    resolve(args) match {
      case List()  => None
      case List(x) => Some(x.reqs)
      case xs => l.die(
        "Instance resolution for class " :+: name.toString :+:
        " is ambiguous for type arguments:" :+: oxford("and", args.map(prettyType(_))),
        xs.map(_.report("ambiguous instance")):_*
      )
    }
  }
  def pp: Pretty[Document] = for {
    nameDoc <- ppName(name)(Pretty.Unqualified)
    argDocs <- args.traverse(ppVar(_)(Pretty.Unqualified))
    supDocs <- sups.traverse(ppType(_)(Pretty.Unqualified))
  } yield if (sups.isEmpty) "class" :+: nameDoc :+: fillSep(argDocs)
          else              "class" :+: nameDoc :+: fillSep(argDocs) :+: nest(4, group(vcat(text("|") :: supDocs)))
  def pretty: Document = vsep(pp.run :: instances.values.flatMap(_.pretty).toList.sortBy(_.toString))
}

abstract class Instance(
  val id: Int
) extends Located {
  def reqs(p: List[Type]): Option[List[Type]]
  def build(d: List[Runtime]): Runtime
  def pretty: List[Document]
}

case class Instantiation(
  instance: Instance,
  args: List[Type],
  reqs: List[Type]
) extends Located {
  def loc = instance.loc
}

sealed trait CheckMethod {
  import CheckMethod._
  def <>(c: CheckMethod): CheckMethod = (this, c) match {
    case (Interface,Interface) => Interface
    case _ => Full
  }
}
object CheckMethod {
  case object Interface extends CheckMethod
  case object Full extends CheckMethod
}

/** ONE note left by a tolerated `foreign` statement (LSP-FFI).
  *
  * `module` is the module whose statement it is, `span` the class or
  * member span in THAT module's source, `severity` the LSP one (2 for a
  * binding that will not resolve, 3 for the opaque-type note a missing
  * `foreign data` class leaves), and `report` the rendered
  * "file:line:col: warning|note: ..." text — the same shape every Death
  * has, so the editor maps it the same way.  Recorded only when
  * `SessionEnv.foreignTolerant`; with the option off a foreign failure is
  * the Death it has always been and no note exists.
  */
case class ForeignNote(module: String, span: Span, severity: Int, report: String)

class SessionEnv(
  var env:             Map[V[Type],Runtime]           = Map(), // vars here are all for global names
  var termNames:       Map[Global,V[Type]]            = Map(),
  var termNameOrigins: Map[Global, List[Global]]      = Map(), // Control.Monad.Functor => Control.Functor.Functor
  var cons:            Map[Global,Type.Con]           = Map(),
  var privateCons:     Map[Global,Type.Con]           = Map(),
  var consOrigins:     Map[Global,List[Global]]       = Map(),
  var loadFile:        Session.SourceFile.Loader      = Session.SourceFile.defaultLoader,
  var loadedFiles:     Map[Session.SourceFile,String] = Map(), // filenames that have been loaded already
  var loadedModules:   Map[String, CheckMethod]       = Map("Builtin" -> CheckMethod.Interface),
  var classes:         Map[Global,ClassDef]           = Map(),
  var classOrigins:    Map[Global, List[Global]]      = Map(),
     _typeCheck:       Option[Boolean]                = None,
     _useInterface:    Option[Boolean]                = None,
     _foreignTolerant: Option[Boolean]                = None,
     _sigEntail:       Option[SigEntail.Mode]         = None,
     _registerDecls:   Option[Boolean]                = None
) { that =>
  def copy: SessionEnv = copyWith(Some(that.registerDecls))

  /** `copy`, with declaration registration OFF: the copy the language
    * server runs a request against (`Resident.withEnv`), and the only
    * caller that wants a copy to differ from what it was copied from.
    * See `registerDecls` below. */
  def copyNotRegistering: SessionEnv = copyWith(Some(false))

  /** The one constructor call behind both, so a field added to
    * `SessionEnv` is carried by `copy` and by `copyNotRegistering` at
    * once. */
  private def copyWith(registerDecls: Option[Boolean]): SessionEnv = {
    val e = new SessionEnv(that.env, that.termNames, that.termNameOrigins, that.cons, that.privateCons, that.consOrigins, that.loadFile, that.loadedFiles, that.loadedModules, that.classes, that.classOrigins, Some(that.typeCheck),Some(that.useInterface),Some(that.foreignTolerant),Some(that.sigEntail),registerDecls)
    // NOT the notes: a copy is what a forked load (SessionTask.fork) or a
    // fresh editor check runs in, and `+=` merges its notes back.  Carrying
    // them forward would report every module's warnings on every file.
    e
  }

  val typeCheck : Boolean = _typeCheck.getOrElse(java.lang.Boolean.getBoolean("ermine.typeCheck"))
  val useInterface : Boolean =
    _useInterface.getOrElse(java.lang.Boolean.parseBoolean(System.getProperty("ermine.useInterface","true")))

  /** LSP-FFI (tracker/LSP-FFI-TOLERANCE.md): tolerate a `foreign`
    * declaration whose class or member this JVM does not have, or has
    * with another signature.  DEFAULT OFF — `bin/ermine`, the REPL and
    * `core/test` keep today's hard failure with byte-identical messages;
    * the language server's `Resident` turns it ON, and the editor gets a
    * warning plus a stub instead of a dead module. */
  val foreignTolerant : Boolean =
    _foreignTolerant.getOrElse(java.lang.Boolean.getBoolean("ermine.foreign.tolerant"))

  /** SIGNATURE ENTAILMENT (`tracker/SIG-ENTAIL-PLAN.md` S3): whether a declared
    * signature's ROW constraints are checked against the body's obligations, and
    * what a failure costs.  DEFAULT `error` (`-Dermine.sigEntail=off|warn|error`).
    * Per session rather than global so that one JVM can hold a suite's `error`
    * properties beside its `off` ones with no `System.setProperty`, and so the
    * language server can differ from a batch build; it reaches the checker as
    * `SubstEnv.sigEntail` through `Session.subst`. */
  val sigEntail : SigEntail.Mode = _sigEntail.getOrElse(SigEntail.defaultMode)

  /** WIDGET PREVIEW WP-3 (`tracker/JSON-WIDGET-PLAYGROUND.md` §2.2): whether a
    * `data` declaration this session checks is written into the PROCESS-WIDE
    * constructor registry (`DataConDecl.register`, `DataConDecl.scala`), which
    * the JSON encoder reads for a runtime `Data` node that has no env in reach
    * (`json/Encode.scala` `userData`, through `toJson#`).
    *
    * DEFAULT ON, and no system property: every load that means to publish a
    * module's shape keeps writing it -- `bin/ermine`, the REPL, `core/test`,
    * both `Lib.preamble`s, the resident's own boot and reloads, and a render
    * session.  A process-wide `-D` would be the wrong shape for this flag: the
    * point is that two envs in ONE JVM differ, and turning registration off
    * globally would silently break `toJson#` for everybody.
    *
    * The language server's per-request copies (`Resident.withEnv`, via
    * `copyNotRegistering`) turn it OFF.  Those check the OPEN BUFFER on every
    * debounced keystroke, so a half-typed `data` there would overwrite the
    * shape a JSON encode elsewhere in the JVM reads, and no invalidation fires
    * for a `didChange`.  A check copy's own readers are unaffected: the `Con`
    * it builds carries the decl, and `json/Schema` and `json/Decode` read the
    * `Con` before they fall back to the registry; a check never evaluates, so
    * `toJson#` never runs on a copy. */
  val registerDecls : Boolean = _registerDecls.getOrElse(true)

  /** The tolerated failures, in the order they were declared.  Loads may
    * run on forked copies (SessionTask), so appending is synchronized. */
  var foreignNotes: List[ForeignNote] = Nil

  def noteForeign(n: ForeignNote): Unit = synchronized { foreignNotes = foreignNotes :+ n }


  def +=(sp: SessionEnv): Unit = {
    env             = env ++ sp.env
    termNames       = termNames ++ sp.termNames
    termNameOrigins = termNameOrigins ++ sp.termNameOrigins
    cons            = cons ++ sp.cons
    privateCons     = privateCons ++ sp.privateCons
    consOrigins     = consOrigins ++ sp.consOrigins
    // no loadFile union, so skip
    loadedFiles     = loadedFiles ++ sp.loadedFiles
    loadedModules   = loadedModules ++ sp.loadedModules
    classes         = classes ++ sp.classes ++
      (classes.keySet.intersect(sp.classes.keySet).map {
        k => k -> (classes(k) ++ sp.classes(k).instances)
      })
    classOrigins    = classOrigins ++ sp.classOrigins // is this enough, or do we need the keySet.intersect?
    // a forked load's tolerated foreign failures come home with it
    foreignNotes    = foreignNotes ++ sp.foreignNotes
  }
  def :=(s: SessionEnv): Unit = {
    env = s.env
    termNames = s.termNames
    termNameOrigins = termNameOrigins ++ s.termNameOrigins
    cons = s.cons
    privateCons = s.privateCons
    consOrigins = consOrigins ++ s.consOrigins
    loadFile = s.loadFile
    loadedFiles = s.loadedFiles
    loadedModules = s.loadedModules
    classes = s.classes
    classOrigins = classOrigins ++ s.classOrigins
    foreignNotes = s.foreignNotes
  }
}
