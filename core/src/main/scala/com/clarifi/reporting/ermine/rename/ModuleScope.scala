package com.clarifi.reporting.ermine.rename

import com.clarifi.reporting.ermine.{ Global, Local, Name, Type, V }
import com.clarifi.reporting.ermine.syntax.{ Explicit, Renaming, Single }

/** Module scope construction as a PURE function (tracker/LSP-ROADMAP.md,
  * Stage 1 item 3.1): an exact replica of ErParseState.importing
  * (parsing/ParseState.scala:41-107) with the parse state dependency made
  * explicit — same using/hiding semantics, same localized rename-then-
  * affix keys, same list-concat alias merging, same collapseNames
  * greatest-ancestor chase INCLUDING its singleton-skip quirk, same
  * origins fixups.  Verified against the original over all 129 stdlib
  * headers and the synthetic corpus by `G1Importing verify`
  * (tracker/tools/g1-validate.sh runs it).
  *
  * The renamer resolves REFERENCES through canonicalTerms/canonicalTypes
  * (the real scope); termNames is the session-global superset that only
  * desugar hooks may consult by Global key (tracker/desugar-hooks.md
  * channel G) — using it for plain references would leak every loaded
  * global into every module (pinned: "a loaded-but-unimported global is
  * undefined at typecheck").
  */
object ModuleScope {

  type ImportSpec = (Option[String], List[Explicit[Global]], Boolean)

  final case class Scope(
    canonicalTerms: Map[Local, List[Name]],
    canonicalTypes: Map[Local, List[Name]],
    termNames: Map[Name, V[Type]],
    termOrigins: Map[Global, List[Global]],
    typeOrigins: Map[Global, List[Global]])

  object Scope { val empty = Scope(Map(), Map(), Map(), Map(), Map()) }

  /** Map merge with list-concat on collisions (scalaz |+| on
    * Map[K, List[V]]). */
  private def merge[K, A](a: Map[K, List[A]], b: Map[K, List[A]]): Map[K, List[A]] =
    b.foldLeft(a) { case (acc, (k, vs)) =>
      acc.updated(k, acc.getOrElse(k, Nil) ++ vs)
    }

  def importing(
      moduleName: String,
      prior: Scope,
      sessionTerms: Map[Global, V[Type]],
      cons: Set[Global],
      m: Map[String, ImportSpec],
      sessionTermOrigins: Map[Global, List[Global]],
      sessionTypeOrigins: Map[Global, List[Global]]): Scope = {

    def imported(isType: Boolean, g: Global): Boolean = m.get(g.module) match {
      case Some((_, explicit, using)) =>
        if (using) explicit.exists(e => g == e.global && isType == e.isType)
        else explicit.forall {
          case Single(n, t) => n != g || isType != t
          case _            => true
        }
      case None => false
    }

    def toGlobal(n: Name): Global = n match {
      case g: Global => g
      case l: Local  => l global moduleName
    }

    def collapseNames(origins: Map[Global, List[Global]])(cm: Map[Local, List[Name]]): Map[Local, List[Name]] = {
      def greatestAncestors(g: Global): List[Global] = {
        val g2 = origins.applyOrElse(g, (x: Global) => List(x))
        if (g2 == List(g)) g2 else g2.flatMap(greatestAncestors)
      }
      cm.map {
        case (k, List(x)) => k -> List(x)  // the singleton-skip quirk: a
                                           // single-name entry keeps its
                                           // import-path name un-collapsed
        case (k, xs)      => k -> xs.flatMap(x => greatestAncestors(toGlobal(x))).toSet.toList
      }
    }

    def localImportsToGlobals(cm: Map[Local, List[Name]]): Map[Global, List[Global]] =
      cm.map { case (l, xs) => toGlobal(l) -> xs.map(toGlobal) }

    def local(isType: Boolean, g: Global): Option[(Local, List[Name])] =
      if (imported(isType, g)) m(g.module) match {
        case (as, explicits, _) =>
          Some((g.localized(as, Explicit.lookup(g, explicits.filter(_.isType == isType))), List(g)))
      } else None

    val termOrigins0 = prior.termOrigins ++ sessionTermOrigins
    val typeOrigins0 = prior.typeOrigins ++ sessionTypeOrigins

    val importedTerms = sessionTerms.keysIterator.flatMap(local(false, _).map { case (k, v) => Map(k -> v) })
      .foldLeft(Map.empty[Local, List[Name]])(merge)
    val importedTypes = cons.iterator.flatMap(local(true, _).map { case (k, v) => Map(k -> v) })
      .foldLeft(Map.empty[Local, List[Name]])(merge)

    val canonicalTerms = collapseNames(termOrigins0)(merge(prior.canonicalTerms, importedTerms))
    val canonicalTypes = collapseNames(typeOrigins0)(merge(prior.canonicalTypes, importedTypes))

    Scope(
      canonicalTerms = canonicalTerms,
      canonicalTypes = canonicalTypes,
      termNames = prior.termNames ++ sessionTerms,
      termOrigins = prior.termOrigins ++ localImportsToGlobals(canonicalTerms),
      typeOrigins = prior.typeOrigins ++ localImportsToGlobals(canonicalTypes))
  }
}
