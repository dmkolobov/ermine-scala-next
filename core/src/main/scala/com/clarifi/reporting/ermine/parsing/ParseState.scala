package com.clarifi.reporting.ermine.parsing

import com.clarifi.reporting.ermine._

import scala.collection.immutable.List
import scalaz.{ Name => _, _ }
import scalaz.Scalaz._
import com.clarifi.reporting.ermine.syntax.{Renaming, Single, Explicit}

/** Used to track the current indentation level
  *
  * @author EAK
  */

case class ErParseState(
  moduleName:     String,
  canonicalTerms: Map[Local, List[Name]] = Map(), // used to patch up fixity and to globalize local names
  canonicalTypes: Map[Local, List[Name]] = Map(), // "
  termNames:      Map[Name, V[Type]] = Map(),
  typeNames:      Map[Name, V[Kind]] = Map(),
  kindNames:      Map[Name, V[Unit]] = Map(),
  /* Note - a given global *can* have two origins.  For example, if Foo exports Bar.bar and Baz.bar, Foo.bar itself
     is ambiguous.  This should probably be an error at module definition time.*/
  termOrigins:    Map[Global, List[Global]] = Map(), // e.g. Control.Monad.Functor => List(Control.Functor.Functor)
  typeOrigins:    Map[Global, List[Global]] = Map()  // "
) {
  def importing( sessionTerms: Map[Global,TermVar]
               , cons: Set[Global]
               , m: Map[String, (Option[String], List[Explicit[Global]], Boolean)]
               , sessionTermOrigins: Map[Global, List[Global]] // current global map of origins from the session env
               , sessionTypeOrigins: Map[Global, List[Global]] // "
               ) = {
    def imported(isType: Boolean, g: Global): Boolean = m.get(g.module) match {
      case Some((_, explicit, using)) =>
        if(using) // using: only import things mentioned explicitly
          explicit.exists(e => g == e.global && isType == e.isType)
        else // hiding: don't import things mentioned explicitly unless they're renamed
          explicit.forall {
            case Single(n,t) => n != g || isType != t
            case _           => true
          }
      case None => false
    }
    def toGlobal(n:Name) =
      n match {
        case (g: Global) => g
        case (l:Local) => l.global(moduleName)
      }
    // We don't want to have Control.Monad.Functor, Control.Ap.Functor, and Control.Functor.Functor all in scope.
    // So, collapse those all down to a single name
    def collapseNames(origins: Map[Global, List[Global]])(m: Map[Local, List[Name]]): Map[Local, List[Name]] = {
      def greatestAncestors(g: Global): List[Global] = {
        val g2: List[Global] = origins.applyOrElse(g, (x: Global) => List(x))
        if (g2 == List(g)) g2 else g2.flatMap(greatestAncestors(_))
      }
      m mapValues {
        case List(x) => List(x)
        case xs => {
          val collapse = xs.flatMap(x => greatestAncestors(toGlobal(x))).toSet.toList
          collapse
        }
      }}
    def localImportsToGlobals(m: Map[Local, List[Name]]) : Map[Global, List[Global]] = {
      m.collect( {
        case (l, xs) => (toGlobal(l), xs.map(toGlobal(_)))
      })
    }
    def local(isType: Boolean): PartialFunction[Global,(Local,List[Global])] = {
      case (g: Global) if imported(isType, g) => m(g.module) match {
        case (as, explicits, _) => (g.localized(as, Explicit.lookup(g, explicits.filter(_.isType == isType))), List(g))
      }
    }
    val newps = copy(
      // First, fix up the origins to include previous imports
      termOrigins = termOrigins ++ sessionTermOrigins
    , typeOrigins = typeOrigins ++ sessionTypeOrigins
    )
    val newps2 = newps.copy(  // because collapseNames needs them all to be there.
      canonicalTerms = collapseNames(newps.termOrigins)(canonicalTerms |+| sessionTerms.keySet
                                                                           .collect(local(false))
                                                                           .map( Map(_) )
                                                                           .fold(Map())( _ |+| _))
    , canonicalTypes = collapseNames(newps.typeOrigins)(canonicalTypes |+| cons.collect(local(true))
                                                                  .map( Map(_) )
                                                                  .fold(Map())( _ |+| _))
    , termNames = termNames ++ sessionTerms
    )
    val newps3 = newps2.copy( // now, fix up Origins to have what we just imported
      termOrigins = termOrigins ++ localImportsToGlobals( newps2.canonicalTerms )
    , typeOrigins = typeOrigins ++ localImportsToGlobals( newps2.canonicalTypes )
    )
    newps3
  }
}

object ErParseState {
  import scalaparsers.{ParseState => SPPS}

  def mk(filename: String, content: String, module: String) =
    SPPS.mk(filename, content, ErParseState(moduleName = module))

  private[ermine] val erpsLens: ParseState @> ErParseState =
    Lens.lensu((p, s) => p.copy(s=s), _.s)

  private[this] def inParseState[A](il: ErParseState @> A): ParseState @> A =
    il compose erpsLens

  private def moduleNameLens: ErParseState @> String =
    Lens lensu ((e, s) => e copy (moduleName = s), _.moduleName)
  private def kindNamesLens = Lens[ErParseState, Map[Name, V[Unit]]](s => Store(n => s.copy (kindNames = n), s.kindNames))
  private def typeNamesLens = Lens[ErParseState, Map[Name, V[Kind]]](s => Store(n => s.copy (typeNames = n), s.typeNames))
  private def termNamesLens = Lens[ErParseState, Map[Name, V[Type]]](s => Store(n => s.copy (termNames = n), s.termNames))
  private def canonicalTermsLens = Lens[ErParseState, Map[Local, List[Name]]](s => Store(n => s.copy (canonicalTerms = n), s.canonicalTerms))
  private def canonicalTypesLens = Lens[ErParseState, Map[Local, List[Name]]](s => Store(n => s.copy (canonicalTypes = n), s.canonicalTypes))
  object Lenses {
    def moduleName     = inParseState(moduleNameLens)
    def kindNames      = inParseState(kindNamesLens)
    def typeNames      = inParseState(typeNamesLens) // These would be inline, but !@&*#(& scala
    def termNames      = inParseState(termNamesLens)
    def canonicalTerms = inParseState(canonicalTermsLens)
    def canonicalTypes = inParseState(canonicalTypesLens)
  }

  object Implicits {
    implicit class ParseStateErParseState(val _value: SPPS[ErParseState])
        extends AnyVal {
      def importing( sessionTerms: Map[Global,TermVar]
                   , cons: Set[Global]
                   , m: Map[String, (Option[String], List[Explicit[Global]], Boolean)]
                   , sessionTermOrigins: Map[Global, List[Global]]
                   , sessionTypeOrigins: Map[Global, List[Global]]) =
        erpsLens mod (_.importing(sessionTerms, cons, m, sessionTermOrigins, sessionTypeOrigins), _value)
    }
  }
}
