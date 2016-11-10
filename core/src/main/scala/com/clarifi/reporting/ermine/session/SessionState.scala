package com.clarifi.reporting.ermine.session

import com.clarifi.reporting.ermine.{ V, Global, Runtime, Type, Kind, Requirements, Pretty }
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

class SessionEnv(
  var env:             Map[V[Type],Runtime]           = Map(), // vars here are all for global names
  var termNames:       Map[Global,V[Type]]            = Map(),
  var termNameOrigins: Map[Global, List[Global]]      = Map(), // Control.Monad.Functor => Control.Functor.Functor
  var cons:            Map[Global,Type.Con]           = Map(),
  var privateCons:     Map[Global,Type.Con]           = Map(),
  var consOrigins:     Map[Global,List[Global]]       = Map(),
  var loadFile:        Session.SourceFile.Loader      = Session.SourceFile.defaultLoader,
  var loadedFiles:     Map[Session.SourceFile,String] = Map(), // filenames that have been loaded already
  var loadedModules:   Set[String]                    = Set("Builtin"),
  var classes:         Map[Global,ClassDef]           = Map(),
  var classOrigins:    Map[Global, List[Global]]      = Map(),
     _typeCheck:       Option[Boolean]                = None
) { that =>
  def copy = new SessionEnv(that.env, that.termNames, that.termNameOrigins, that.cons, that.privateCons, that.consOrigins, that.loadFile, that.loadedFiles, that.loadedModules, that.classes, that.classOrigins, Some(that.typeCheck))

  val typeCheck : Boolean = _typeCheck.getOrElse(java.lang.Boolean.getBoolean("ermine.typeCheck"))

  def +=(sp: SessionEnv) {
    env             = env ++ sp.env
    termNames       = termNames ++ sp.termNames
    termNameOrigins = termNameOrigins ++ sp.termNameOrigins
    cons            = cons ++ sp.cons
    privateCons     = privateCons ++ sp.privateCons
    consOrigins     = consOrigins ++ sp.consOrigins
    // no loadFile union, so skip
    loadedFiles     = loadedFiles ++ sp.loadedFiles
    loadedModules   = loadedModules | sp.loadedModules
    classes         = classes ++ sp.classes ++
      (classes.keySet.intersect(sp.classes.keySet).map {
        k => k -> (classes(k) ++ sp.classes(k).instances)
      })
    classOrigins    = classOrigins ++ sp.classOrigins // is this enough, or do we need the keySet.intersect?
  }
  def :=(s: SessionEnv) {
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
  }
}
