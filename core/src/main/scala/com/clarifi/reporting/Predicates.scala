package com.clarifi.reporting

import scalaz._
import Scalaz.{mapShow => _, _}
import scalaz.Show._
import scalaz.std.map.mapKeys

import util.{Clique, Keyed, PartitionedSet}
import ReportingUtils.simplifyPredicate
import Reporting._

object Predicates {

  def IsNull(expr: Op): Predicate = Predicate.IsNull(expr)

  def toFn(pp: Predicate): Record => Boolean = pp.apply[Record => Boolean](
    atom = b => (t: Record) => b,
    lt = (a, b) => (t: Record) => a.eval(t) lt b.eval(t),
    gt = (a, b) => (t: Record) => a.eval(t) gt b.eval(t),
    eq = (a, b) => (t: Record) => a.eval(t).equalsIfNonNull(b.eval(t)),
    not = p2 => (t: Record) => !p2.apply(t),
    or = (a, b) => (t: Record) => a.apply(t) || b.apply(t),
    and = (a, b) => (t: Record) => a.apply(t) && b.apply(t),
    isNull = e => (t: Record) => e.eval(t).isNull)

  /** Answer things known to be true about every row in
    * `∀r. Filter(r, p)`.
    */
  def constancies(p: Predicate): Reflexivity[ColumnName] = {
    val empty = Reflexivity.zero[ColumnName]
    val nothing = (empty, empty)
    // find tautologies and contradictions
    simplify(p).apply[(Reflexivity[ColumnName], Reflexivity[ColumnName])](
      atom = _ => nothing,
      lt = (_, _) => nothing,
      gt = (_, _) => nothing,
      eq = (l, r) => (l, r) match {
        case (Op.ColumnValue(cn, _), op) =>
          (Reflexivity.eq(cn, op), empty)
        case (op, Op.ColumnValue(cn, _)) =>
          (Reflexivity.eq(cn, op), empty)
        case _ => nothing
      },
      not = (pp) => pp.swap,
      or = (l, r) => (l, r) match {
        case ((taut1, contra1), (taut2, contra2)) =>
          ((taut1 || taut2), (contra1 || contra2))
      },
      and = (l, r) => (l, r) match {
        case ((taut1, contra1), (taut2, contra2)) =>
          ((taut1 && taut2), (contra1 && contra2))
      },
      isNull = e => nothing
    )._1
  }

  /** Public alias for `simplifyPredicate`. */
  def simplify(p: Predicate) = simplifyPredicate(p)

  /** Chain `ps` with OR. */
  def any(ps: Traversable[Predicate]) =
    if (ps.isEmpty) Predicate.Atom(false)
    else simplify(ps.tail.fold(ps.head)(Predicate.Or(_, _)))

  /** Chain `ps` with AND. */
  def all(ps: Traversable[Predicate]) =
    if (ps.isEmpty) Predicate.Atom(true)
    else simplify(ps.tail.fold(ps.head)(Predicate.And(_, _)))
}

/** Things that are true for every record in a relation.
  *
  * @tparam K Comparable, hashable record position identifier.
  */
sealed abstract class Reflexivity[K]
       extends Equals with Keyed[Reflexivity, K] {
  /** If a `K` is present, it has a constant PrimExpr value across
    * the relation, whether that value is known or unknown. */
  def consts: Map[K, Option[PrimExpr]]

  /** Ks I know something about. */
  def elements: Set[K]

  /** This and `other` are both true for each record. */
  def &&(other: Reflexivity[K])(implicit eqt: Equal[K]) = (this, other) match {
    case (KnownEmpty(), _) | (_, KnownEmpty()) => KnownEmpty[K]()
    case (ForallTups(consts, equiv), ForallTups(otherconsts, otherequiv)) =>
      (consts.keySet & otherconsts.keySet).toIterable map {k =>
        (consts(k), otherconsts(k)) match {
          // ∀u,v. u≢v ∧ (∀r∈R. r(q)≡u ∧ r(q)≡v) ⇒ R≡∅
          case (Some(v), Some(u)) if v /== u => None
          // ∀v. (∃u. ∀r∈R. r(q)≡v ∧ r(q)≡u) ⇒ (∀r∈R. r(q)≡v)
          // ∀u,v. (∀r∈R. r(q)≡u ∧ r(q)≡v) ⇒ u≡v
          case (u, v) => Some(k -> (u orElse v))
        }} match {
          case specifics if specifics exists (!_.isDefined) =>
            KnownEmpty[K]()
          case specifics =>
            ForallTups(consts ++ other.consts ++ specifics.map(_.get),
                       equiv |+| otherequiv)
        }
  }

  /** One of this or `other`, or perhaps both, are true for each
    * record. */
  def ||(other: Reflexivity[K])(implicit eqt: Equal[K]) = (this, other) match {
    case (KnownEmpty(), KnownEmpty()) => KnownEmpty[K]()
    case (ForallTups(_, _), KnownEmpty()) => this
    case (KnownEmpty(), ForallTups(_, _)) => other
    case (ForallTups(consts, equiv), ForallTups(otherconsts, otherequiv)) =>
      // we can only inherit what's evident from *both* p₁ and p₂.
      ForallTups((consts.keySet & other.consts.keySet).toIterable
                 map {k => (k, consts(k), other.consts(k))}
                 // ∀u,v. u≡v ⇔ ((∀r∈R. r(q)≡u ∨ r(q)≡v) ⇒ ∀r∈R. r(q)≡u)
                 // ∃u,v. (∀r∈R. r(q)≡u ∨ r(q)≡v) ⇏ ∃w. ∀r∈R. r(q)≡w
                 collect {case (k, cv@Some(v), Some(u)) if v === u => k -> cv}
                 toMap,
                 equiv require otherequiv)
  }

  /** Answer whether all ELTS are equivalent. */
  def equivalent(elts: Set[K]): Boolean

  /** Update constant values. */
  def varyConsts(f: Map[K, Option[PrimExpr]]
                  => Map[K, Option[PrimExpr]]): Reflexivity[K]

  /** Regroup.
    *
    * @note `fa <|*|> fb` must form an injection. */
  def group[A, B](fa: K => A)(fb: K => B): Map[A, Reflexivity[B]]

  /** Apply a parallel relational combine evaluated in the receiver's
    * environment. */
  def combineAll(combining: Map[K, Op],
                 opevalenv: PartialFunction[K, ColumnName],
                 boxcol: ColumnName => K,
                 retainBefore: Boolean = true)(implicit eqt: Equal[K]): Reflexivity[K]
}

/** Known equalities of a relation.
  *
  * @param equiv cliques of equivalent `K`s
  */
final class ForallTups[K](private[ForallTups] val partialConsts: Map[K, Option[PrimExpr]],
                          private[ForallTups] val equiv: PartitionedSet[K])
      extends Reflexivity[K] {
  // Resolve equivalence.
  lazy val consts: Map[K, Option[PrimExpr]] = partialConsts flatMap {
    case kp@(k, ope) => (equiv.graph(k) map (_ -> ope)) + kp
  }

  def elements = partialConsts.keySet | equiv.elements

  def varyConsts(f: Map[K, Option[PrimExpr]] => Map[K, Option[PrimExpr]]) =
    ForallTups(f(partialConsts), equiv)

  def equivalent(elts: Set[K]) =
    Set(0,1)(elts.size) || (equiv contains elts) || {
      (elts map consts.lift toSeq) match {
        case Seq(Some(Some(_))) => true
        case _ => false
      }
    }

  override def inj[B](f: K => B) =
    ForallTups(mapKeys(partialConsts)(f), equiv inj f)

  def propagate[B](f: K => Iterable[B]) =
    // emptiness test gives us FT(x→2,x↔y) propagate {x→∅,y→{z,r}} = FT(z→2,z↔r)
    // while maintaining FT({x→2,y→3},∅) propagate {x→∅,y→x} = FT(x→3)
    ForallTups((if (partialConsts.keys exists (f andThen (_.isEmpty))) consts
                else partialConsts)
               flatMap {case (k, v) => f(k) map ((_, v))},
               equiv propagate f)

  def replaceKeys(ren: PartialFunction[K, K]) = {
    val (renamedC, unrenamedC) = consts partition (ren isDefinedAt _._1)
    ForallTups(unrenamedC ++ mapKeys(renamedC)(ren),
               equiv replaceKeys ren)
  }

  def group[A, B](fa: K => A)(fb: K => B): Map[A, Reflexivity[B]] = {
    val groupedPcs =
      partialConsts groupBy (_._1 |> fa) mapValues (pc => mapKeys(pc)(fb))
    val groupedEqs = equiv.group(fa)(fb)
    groupedPcs.keySet | groupedEqs.keySet map {gk =>
      gk -> ForallTups(groupedPcs getOrElse (gk, Map.empty),
                       groupedEqs getOrElse (gk, PartitionedSet.zero))
    } toMap
  }

  def combineAll(combining: Map[K, Op],
                 opevalenv: PartialFunction[K, ColumnName],
                 boxcol: ColumnName => K,
                 retainBefore: Boolean)(implicit eqt: Equal[K]) = {
    import Op.{ColumnValue, OpLiteral}
    val evalEnv = consts collect {
      case (k, Some(v)) if opevalenv isDefinedAt k =>
        (opevalenv(k), OpLiteral(v))
    }
    val concreteKeys = (consts.keys collect opevalenv toSet)
    val comb = combining mapValues (_ simplify evalEnv)
    // here we transcend the temporal-barrier by treating "before" as
    // Left and "introduced after" as Right, letting the graph collect
    // appropriately and *then* dropping overwritten columns
    type Transient = Either[K, K]
    (inj(Left(_): Transient) && ForallTups(
      comb collect {
        case (k, OpLiteral(lit)) => (Right(k): Transient, Some(lit))
        case (k, op) if op.columnReferences subsetOf concreteKeys =>
          (Right(k): Transient, None)
      } toMap,
      PartitionedSet(comb collect {
        case (k, ColumnValue(col, _)) =>
          Clique(Set[Transient](Right(k), Left(boxcol(col))))
      }))) injColl {case Left(k) if !(combining isDefinedAt k) && retainBefore => k
                    case Right(k) => k}
  }

  def canEqual(o: Any) = o.isInstanceOf[ForallTups[_]]
  override def equals(o: Any) = o match {
    case o: ForallTups[_] => consts == o.consts && equiv == o.equiv
    case _ => false
  }
  override def hashCode = (ForallTups, consts, equiv).hashCode

  override def toString = "ForallTups(" + consts + "," + equiv + ")"
}

object ForallTups {
  def apply[K](consts: Map[K, Option[PrimExpr]],
               equiv: PartitionedSet[K]): Reflexivity[K] =
    if (Reflexivity.contradicts(equiv, consts))
      KnownEmpty[K]()
    else new ForallTups(consts, equiv)

  def unapply[K](v: Reflexivity[K]): Option[(Map[K, Option[PrimExpr]],
                                             PartitionedSet[K])] = v match {
    case v: ForallTups[K] => Some((v.consts, v.equiv))
    case KnownEmpty() => None
  }
}

/** The relation must be empty. */
case class KnownEmpty[K]() extends Reflexivity[K] {
  def consts = Map.empty

  def elements = Set.empty

  def varyConsts(f: Map[K, Option[PrimExpr]]
                  => Map[K, Option[PrimExpr]]) = this

  def equivalent(elts: Set[K]) = true

  def propagate[B](f: K => Iterable[B]) = KnownEmpty[B]()

  def replaceKeys(ren: PartialFunction[K, K]) = this

  override def filterKeys(keys: K => Boolean) = this

  def group[A, B](fa: K => A)(fb: K => B) = Map.empty

  def combineAll(combining: Map[K, Op],
                 opevalenv: PartialFunction[K, ColumnName],
                 boxcol: ColumnName => K,
                 retainBefore: Boolean)(implicit eqt: Equal[K]) = this
}

/** Utilities for `Reflexivity`s. */
object Reflexivity {
  implicit def ReflexivityShow[K: Show]: Show[Reflexivity[K]] = shows({
    case it@KnownEmpty() => it.toString
    case ForallTups(c, eq) => "ForallTups(%s,%s)" format (c.shows, eq.shows)
  })

  def unapply[K](x: Reflexivity[K]) = ForallTups unapply x

  /** Answer whether the equivalences of `equiv` contradict the
    * constant values mentioned in `consts`. */
  def contradicts[K, V: Equal](equiv: PartitionedSet[K], consts: Map[K, Option[V]]) =
    equiv.cliques exists {cq =>
      val cqKnown = cq.view flatMap (consts.lift map (_.join.toSeq))
      (cqKnown.headOption map (pvt => cqKnown exists (pvt /==))
       getOrElse false)
    }

  /** I don't know anything. */
  def zero[K]: Reflexivity[K] =
    ForallTups[K](Map.empty, PartitionedSet.zero)

  /** ∀r∈R. r(`col`)≡`value`. */
  def eq(col: ColumnName, value: Op): Reflexivity[ColumnName] = value match {
    case Op.ColumnValue(nm, _) =>
      ForallTups(Map.empty, PartitionedSet.single(col, nm))
    case Op.OpLiteral(prim) =>
      ForallTups(Map(col -> Some(prim)), PartitionedSet.zero)
    case _ => zero
  }

  /** Constancy of a literal relation. */
  def literal(atoms: NonEmptyList[Record]): Reflexivity[ColumnName] =
    ForallTups(atoms.tail.foldLeft(atoms.head){(consts, rec) =>
                 consts filter {case (k, v) => rec(k) === v}
               }.mapValues(some),
               PartitionedSet.zero)
  def literalSeq(atoms: Seq[Record]): Reflexivity[ColumnName] =
    ForallTups(atoms.tail.foldLeft(atoms.head){(consts, rec) =>
                 consts filter {case (k, v) => rec(k) === v}
               }.mapValues(some),
               PartitionedSet.zero)

}

/*
 * Tracks functional dependencies of a set of columns (abstractly represented by
 * a type K). The functional dependencies are stored in reverse, with a map from
 * each column to the sets of other columns that determine it. So for instance
 * the functional dependencies:
 *
 *    a b -> c ; b c -> d
 *
 * may be stored as:
 *
 *   Map(c -> Set(Set(a,b)), d -> Set(Set(b,c),Set(a,b)))
 *
 * Many operations seem to be simpler with this representation, rather than
 * the opposite choice of storing maps from sets of columns to sets of other
 * columns that they determine.
 *
 * A few normalizations will be maintained:
 *
 * 1) First, a mapping `a -> Set()`is the same as `a` not appearing in the map
 *    at all, so such entries should be removed. Note that this is distinct from
 *    `a -> Set(Set())` which represents that `a` is a constant.
 *
 * 2) Dependencies of `a` on sets of columns containing `a` are trivial, and
 *    should also not appear in the map.
 *
 * 3) If `a -> b` and `b -> c`, then `a -> c`. Similar rules hold if multiple
 *    columns appear on the left. When we make use of fundeps, we'll need to
 *    check things against this transitive closure anyhow, so it makes sense for
 *    the mappings to store that to begin with.
 *
 * 4) The rules `a b c -> d` and `a b -> d` are redundant. The second is strictly
 *    more powerful, so we may as well just store the minimal sets of columns that
 *    are known to determine each column.
 *
 * Rules for how fundeps are propagated across relational operators will be
 * explained at their implemenations below.
 */
case class Fundepped[K](determiners: Map[K, Set[Set[K]]]) {
  import Fundepped._

  /*
   * Adds a fundep to a set of fundeps.
   *
   * This may cause significant changes to the set, as various inference
   * rules will trigger.
   */
  def +(fd: (Set[K], K)): Fundepped[K] = fd match {
    case (det, k) =>
      val ss = index(determiners, k)
      Fundepped(normalize(determiners + (k -> (ss + det))))
  }

  /*
   * Adds a sequence of fundeps to the set.
   */
  def ++(fds: TraversableOnce[(Set[K], K)]) =
    Fundepped(normalize(accumulateFDs(fds, determiners)))

  /*
   * Combines two sets of fundeps. This operation is appropriate for
   * use when joining two relations. The fundeps on a join are the
   * union of the fundeps of the underlying relations.
   */
  def &&(other: Fundepped[K]): Fundepped[K] = {
    Fundepped(normalize(combineFDs(determiners,other.determiners)))
  }

  def --(ks: TraversableOnce[K]): Fundepped[K] = {
    val remove = ks.toSet

    Fundepped(filterFDs[K](!remove(_), determiners))
  }

  /*
   * Applies a function to the columns involved in the functional dependencies.
   *
   * If the function is not injective on the columns involved in the fundeps,
   * the resulting fundeps may not be normalized, or some dependencies may be
   * erased.
   */
  def injectiveMap[L](f: K => L) =
    Fundepped(mapFDs(f, determiners))

  /*
   * Applies a partial function to the columns involved in the functional
   * dependencies. Any dependency involving a column that is not in the
   * defined domain of the partial function will be removed.
   *
   * If the function is not injective on the columns involved in the fundeps,
   * the resulting dependencies may not be normalized, and some dependencies
   * may be omitted arbitrarily.
   */
  def injectiveCollect[L](f: PartialFunction[K,L]) =
    Fundepped(collectFDs(f, determiners))

  /*
   * Filters functional dependencies according to a predicate on columns.
   *
   * A fundep is removed completely if any of the columns involved fail
   * the predicate.
   */
  def filter(p: K => Boolean) =
    Fundepped(filterFDs(p, determiners))

  /*
   * Gives back the set of sets of columns that functionally determine
   * the given column.
   */
  def determinersOf(k: K) = index(determiners,k)

  /*
   * Returns a sequence of the functional dependencies stored.
   */
  def fundeps: Traversable[(Set[K], K)] =
    determiners.toTraversable flatMap {
      case (k, ss) => ss.toTraversable map ((_, k))
    }
}

object Fundepped {
  type FDs[K] = Map[K, Set[Set[K]]]

  /*
   * Maps a function over a set of functional dependencies.
   *
   * The assumption is that the function is injective on the set of
   * columns that are used in the stored fundeps, so that care
   * need not be taken to unify sets that are mapped to a common key.
   * If the function does map two columns to the same new column,
   * an arbitrary set of determining columns will be chosen.
   */
  private[Fundepped] def mapFDs[K,L](f : K => L, fds: FDs[K]): FDs[L] =
    fds.map {
      case (k, ss) => f(k) -> ss.map(_.map(f))
    }

  /*
   * Collects the results of mapping a partial function over a set of
   * functional dependencies.
   *
   * Any functional dependencies that involve failing columns will be
   * completely removed from the fundepss.
   *
   * It is expected that the partial function will be injective on the
   * columns involved in the fundeps. If this is not the case, then
   * arbitrary fundeps may be elided.
   */
  private[Fundepped] def collectFDs[K,L](f: PartialFunction[K,L], fds: FDs[K]): FDs[L] =
    removeTrivial(
      fds.collect {
        case (k, ss) if f.isDefinedAt(k) =>
          f(k) -> ss.collect { case s if s.forall(f.isDefinedAt) => s.map(f) }
      }
    )

  /*
   * Filters a set of functional dependencies according to a predicate
   * on columns.
   *
   * Any fundep that mentions a column that fails the predicate is
   * completely removed.
   */
  private[Fundepped] def filterFDs[K](p: K => Boolean, fds: FDs[K]): FDs[K] =
    removeTrivial(
      fds.collect {
        case (k, ss) if p(k) =>
          k -> ss.filter(_.forall(p))
      }
    )

  /*
   * Indexes into a fundep map to get the set of sets of determining columns.
   * If a key does not occur in the map, there are no such sets.
   */
  private[Fundepped] def index[K](m: FDs[K], k: K): Set[Set[K]] =
    m.getOrElse(k, Set())

  /*
   * Removes trivial fundeps (cases 1 and 2 above) from a set of fundeps
   */
  private[Fundepped] def removeTrivial[K](m: FDs[K]) =
    m map {
      case (k, ss) => k -> ss.filter(!_.contains(k))
    } filter {
      case (k, ss) => ss.nonEmpty
    }

  /*
   * Removes redundancies (case 3 above) from a set of fundeps.
   */
  private[Fundepped] def thin[K](ss: Set[Set[K]]): Set[Set[K]] = {
    ss.filter {
      s => ! ss.exists(t => t.subsetOf(s) && s != t)
    }
  }

  /*
   * Generates all sets reachable from dets in one step through fds (for each column).
   *
   * Example:
   *
   *     dets = Set(x,y,z)
   *     fds = Map(x -> Set(Set(a)), y -> Set(Set(b)))
   *     follow(dets,fds) = Set(Set(x,y,z), Set(a,y,z), Set(x,b,z), Set(a,b,z))
   *
   * Note that the original set happens to be returned as well.
   */
  private[Fundepped] def follow[K](dets: Set[K], fds: FDs[K]): Set[Set[K]] =
    dets.toList.traverse {
      k => Set(k) :: index(fds,k).toList
    } map (_.foldLeft(Set[K]())(_ union _)) toSet

  private[Fundepped] def normalizeStep[K](m: FDs[K]) =
    removeTrivial(
      m map {
        case (k, ss) =>
          val nss = ss.flatMap {
            s => follow(s, m)
          }
          k -> thin(nss)
      })

  /*
   * Normalizes a set of fundeps, recursively applying rules 1-4 above
   * until they result in no changes to the set.
   */
  private[Fundepped] def normalize[K](m: FDs[K]): FDs[K] = {
    val nm = normalizeStep(m)
    if (nm == m) nm
    else normalize(nm)
  }

  /*
   * Incorporates two internal sets of fundeps. This does not perform
   * any normalization.
   */
  private[Fundepped] def combineFDs[K](fdsl: FDs[K], fdsr: FDs[K]): FDs[K] =
    fdsr.foldLeft(fdsl) {
      case (m, (k, ss)) => m + (k -> index(m,k).union(ss))
    }

  /*
   * Turns a sequence of functional dependencies specified as
   * `x, y and z determine w` into a format suitable for use in Fundepped.
   *
   * This function does not normalize the set.
   */
  private[Fundepped] def accumulateFDs[K](fds: TraversableOnce[(Set[K], K)], base: FDs[K] = Map[K,Set[Set[K]]]()): FDs[K] =
    fds.foldLeft(base) {
      case (m, (s, k)) =>
        val ss = index(m, k)
        m + (k -> (ss + s))
    }

  private[Fundepped] def accumulateFDs[K](fds: (Set[K], K)*): FDs[K] =
    accumulateFDs(fds)

  def apply[K](fds: (Set[K], K)*): Fundepped[K] =
    Fundepped(normalize(accumulateFDs[K](fds)))

  def empty[K]: Fundepped[K] = Fundepped(Map[K,Set[Set[K]]]())

  private[this]
  def equate(l: Op, r: Op): Map[ColumnName, Set[Set[ColumnName]]] = {
    import Op.ColumnValue
    (l, r) match {
      case (ColumnValue(cl, _), ColumnValue(cr, _)) =>
        accumulateFDs(Set(cl) -> cr, Set(cr) -> cl)
      case (ColumnValue(cl, _), _) =>
        accumulateFDs(r.columnReferences -> cl)
      case (_, ColumnValue(cr, _)) =>
        accumulateFDs(l.columnReferences -> cr)
      case _ => Map()
    }
  }

  private[this]
  def fromPredNonNormalized(pred: Predicate): Map[ColumnName, Set[Set[ColumnName]]] = {
    import Predicate._

    // TODO: Try to expand supported predicates.
    //       Make sure we don't miss something due to negation.
    pred match {
      case Eq(left: Op, right: Op) => equate(left, right)
      case And(left: Predicate, right: Predicate) =>
        combineFDs(fromPredNonNormalized(left), fromPredNonNormalized(right))
      case _ => Map()
    }
  }

  def fromPredicate(pred: Predicate): Fundepped[ColumnName] =
    Fundepped(normalize(fromPredNonNormalized(pred)))

  /*
   * Structure for representing pertinent information about an Op
   * with respect to functional dependencies. For our purposes,
   * an Op can either be constant, an injective function of another
   * column, or merely a function of several other columns.
   */
  private[this] sealed abstract class OpInfo[+K] {
    def map[L](f: K => L): OpInfo[L]
    def columns: List[K]
  }
  private[this] case object Constant extends OpInfo[Nothing] {
    def map[L](f: Nothing => L) = this
    def columns = List()
  }
  private[this] case class Injective[+K](functionOf: K) extends OpInfo[K] {
    def map[L](f: K => L): Injective[L] = Injective(f(functionOf))
    def columns = List(functionOf)
  }
  private[this] class Plain[+K](val columns: List[K]) extends OpInfo[K] {
    def map[L](f: K => L) = Plain(columns.map(f))
  }
  private[this] object Plain {
    def apply[K](cs: List[K]) =
      if (cs.isEmpty) Constant
      else new Plain(cs)

    def unapply[K](p: Plain[K]): Some[List[K]] = Some(p.columns)
  }

  private[Fundepped] def opInfo(op: Op): OpInfo[ColumnName] = {
    import Op._
    def bin(ol: OpInfo[ColumnName], or: OpInfo[ColumnName]): OpInfo[ColumnName] =
      Plain(ol.columns ++ or.columns)

    def cat(ois: List[OpInfo[ColumnName]]): OpInfo[ColumnName] =
      Plain(ois.flatMap(_.columns))

    op match {
      case OpLiteral(_) => Constant
      case ColumnValue(col, _) => Injective(col)
      case Add(l, r) => (opInfo(l), opInfo(r)) match {
        case (Constant, or) => or
        case (ol, Constant) => ol
        case (ol, or) => bin(ol,or)
      }
      case Sub(l, r) => (opInfo(l), opInfo(r)) match {
        case (Constant, or) => or
        case (ol, Constant) => ol
        case (ol, or) => bin(ol,or)
      }
      case Mul(l, r) => bin(opInfo(l), opInfo(r))
      case FloorDiv(l, r) => bin(opInfo(l), opInfo(r))
      case DoubleDiv(l, r) => bin(opInfo(l), opInfo(r))
      case Pow(l, r) => bin(opInfo(l), opInfo(r))
      case Abs(i) => Plain(opInfo(i).columns)
      case Concat(xs) => cat(xs.map(opInfo))
      case If(b,t,f) => Plain(b.columnReferences.toList ++ opInfo(t).columns ++ opInfo(f).columns)
      case Coalesce(l, r) => bin(opInfo(l), opInfo(r))
      case DateAdd(x, _, _) => opInfo(x)
      case DateDiff(_, x, y) => bin(opInfo(x), opInfo(y))
      case Funcall(_, _, _, args, _) => cat(args.map(opInfo))
      case Lower(x) => Plain(opInfo(x).columns)
      case Upper(x) => Plain(opInfo(x).columns)
      case Windowed(a,w) => Plain(a.columnReferences.toList ++ w.columnReferences.toList)
    }
  }

  private[this] type EC = Either[ColumnName, ColumnName]
  private[this] def ecr(c: ColumnName): EC = Right(c)
  private[this] def ecl(c: ColumnName): EC = Left(c)

  /*
   * Computes the functional dependencies between old and new
   * columns given a set of column selections. This can be combined
   * with functional dependencies on the old columns to compute
   * dependencies for the new columns.
   *
   * The convention is for old columns to be promoted to Left, while
   * new columns are promoted to Right, which allows the same name to
   * be used in both old and new columns without their being confused.
   */
  private[this] def selFDs(sel: Map[Attribute, Op]): List[(Set[EC], EC)] = {
    sel.toList.flatMap {
      case (Attribute(c,_), op) => opInfo(op) match {
        case Injective(k) =>
          List(Set[EC](ecl(k)) -> ecr(c),
               Set[EC](ecr(c)) -> ecl(k))
        case oi => List(oi.columns.map(ecl(_)).toSet -> ecr(c))
      }
    }
  }

  /*
   * Given a set of selections of new columns in terms of old columns,
   * and a set of functional dependencies on the old columns, computes
   * an induced set of functional dependencies on the new columns.
   */
  def selections(sel: Map[Attribute, Op], fds: Fundepped[ColumnName]): Fundepped[ColumnName] =
    (fds.injectiveMap(ecl(_)) ++ selFDs(sel)).injectiveCollect{ case Right(c) => c }

  /*
   * Computes the induced functional dependencies for an aggregate-by-group.
   * The supplied fundeps should be those of the relation being aggregated,
   * and the supplied grouping columns are those of the underlying relation
   * determining how things will be chunked for the aggregations. The
   * specified selections and aggregations should explain how the result
   * columns are computed from the underlying columns.
   */
  def aggregations(
        sel: Map[Attribute, Op],
        aggs: List[(Attribute,AggFunc)],
        grps: List[ColumnName],
        fds: Fundepped[ColumnName]
      ): Fundepped[ColumnName] = {
    val grpSet : Set[Set[EC]] = Set(grps.map(ecl(_)).toSet)
    val grpFDs : Fundepped[EC] = Fundepped(aggs.map {
      case (Attribute(c, _), _) => ecr(c) -> grpSet
    } ++ sel.toList.map {
      case (Attribute(c, _), _) => ecr(c) -> grpSet
    } toMap)

    val totalFDs =
      fds.injectiveMap(ecl(_)) &&
      grpFDs ++
      selFDs(sel)

    totalFDs.injectiveCollect { case Right(c) => c }
  }

  /* Computes the functional dependencies after pivoting.
   * preCols is the set of columns that do not take part in the pivot
   * (these are group by columns, basically). keyCols is the set of columns
   * that determine pivoted column names, and valCols is the set of columns
   * that determine pivoted values. Neither of these end up in the output
   * relation. keyMap is the specification of how to compute the pivoted
   * columns, and contains the names we will pivot into. fds is the functional
   * dependencies of the underlying relation.
   *
   * In a pivot, preCols determine the columns created by the pivot, and
   * the fundeps within preCols should be preserved.
   */
  def pivot(
        preCols: Set[ColumnName],
        keyCols: Set[ColumnName],
        valCols: Set[ColumnName],
        keyMap: Map[Record,(ColumnName, Op, PrimExpr)],
        fds: Fundepped[ColumnName]
      ): Fundepped[ColumnName] = {
    val pcr = preCols.map(ecr)
    // Every output column is determined by the preCols set
    // TODO: try to glean more information from the keyMap?
    val pivotDeps : Fundepped[EC] = Fundepped(keyMap.map {
      case (_, (c, _, _)) => ecr(c) -> Set(pcr)
    })

    // output preCols are determined by input preCols
    val preDeps = Fundepped(preCols.toList.map(c => ecr(c) -> Set(Set(ecl(c)))).toMap)

    val totalFDs =
      fds.injectiveMap(ecl(_)) && preDeps && pivotDeps

    totalFDs.injectiveCollect { case Right(c) => c }
  }
  /*
   * Constructs a set of fundeps where all the columns in the Traversable
   * are constant.
   */
  def constants[K](cs: Traversable[K]): Fundepped[K] =
    Fundepped(cs.map((_,Set[Set[K]]())).toMap)

  /*
   * Represents accumulating functional dependency info.  Lists of columns are
   * mapped to the columns they determine, together with the functional mapping
   * on the values. If a column is not in the right-hand map, it is presumed not
   * to be determined by the list of columns. Similarly, if a column list is not
   * in the outer map, it is presumed to not determine any columns. This allows
   * for pruning of the stored data.
   */
  private[this]
  type Functions[K, V] = Map[List[K], Map[K, Map[List[V], V]]]

  /*
   * Computes all the functions satisfied by a single row of a relation.  In
   * reality, this only includes functions of two columns, as that is what we
   * will take into account when generating fundeps for a literal.  This is used
   * to control the overall fundep generation for literals, as the existing
   * functions are used to decide which determining sets to check during
   * accumulation. If functions of more columns are desired, this function
   * should be changed.
   */
  private[this]
  def vacuousFunctions[K:Order,V](row: Map[K, V]): Functions[K, V] = {
    def pairs(l: List[K]): List[List[K]] = l match {
      case x :: xs => xs.map(List(x,_)) ++ pairs(xs)
      case Nil => Nil
    }
    val kl : List[K] = row.keySet.toList.sortWith(implicitly[Order[K]].lessThan)
    (List[K]() :: kl.map(List(_)) ++ pairs(kl)).map {
      ks => ks -> row.collect {
        case (k, v) if !ks.contains(k) =>
          k -> Map(ks.map(row(_)) -> v)
      }
    } toMap
  }

  private[this]
  def prune[K,V](funs: Functions[K, V]): Functions[K, V] =
    funs.mapValues(_.filter { case (k, f) => f.nonEmpty })
        .filter { case (ks, fs) => fs.nonEmpty }

  /*
   * Incorporates a new row into a set of functional data. The resulting data
   * will contain all relationships that are still functional given the new row
   * and the old accumulated data.
   *
   * It is expected that the row contains every key mentioned in the function
   * data. Exceptions will result if this is not true.
   */
  private[this]
  def accumulateFunctions[K,V](funs: Functions[K, V], row: Map[K, V]) = {
    val newFuns : Functions[K, V] = funs.map {
      case (ks, fs) =>
        val vs = ks.map(row(_))
        ks -> fs.map {
          case (k, f) =>
            val v = row(k)
            val nf = f.get(vs) match {
              case Some(u) => if (u == v) f else Map[List[V], V]()
              case None => f + (vs -> v)
            }
            k -> nf
        }
    }
    prune(newFuns)
  }

  private[this]
  def fundepsOf[K,V](funs: Functions[K, V]): Fundepped[K] = {
    val fds = accumulateFDs(funs.toTraversable.flatMap {
      case (ks, kfs) => kfs.keySet.map(ks.toSet -> _)
    })
    Fundepped(normalize(fds))
  }

  /*
   * Computes the functional dependencies satisfied by a literal relation.
   * It is expected that all the Maps have identical key sets, and each
   * key maps to values that may be compared sensibly in different Maps
   * (that is, that the list represents a well formed/typed relation).
   */
  def literal[K:Order,V](nel: NonEmptyList[Map[K, V]]): Fundepped[K] = {
    // Written as an explicit loop for short circuiting
    def loop(acc: Functions[K, V], l: List[Map[K, V]], cutoff: Int): Fundepped[K] =
      l match {
        case Nil => fundepsOf(acc)
        case r :: rs if cutoff == 0 || acc.isEmpty => Fundepped.empty
        case r :: rs => loop(accumulateFunctions(acc, r), rs, cutoff-1)
      }

    loop(vacuousFunctions(nel.head), nel.tail, 100)
  }

  /*
   * Checks if a selection will preserve distinctness, given the known
   * fundeps about the old columns (which are given by the Header).
   */
  def preservesDistinctness(old: Header, fds: Fundepped[ColumnName], sel: Map[Attribute, Op]): Boolean = {
    val Fundepped(synthesis) = fds.injectiveMap(ecl) ++ selFDs(sel)

    /* for all old columns 'col'
     *   there exists a set 'S' of determining columns for 'col'
     *     such that all members of 'S' are new columns
     *
     * This means that the old rows are functions of the new rows,
     * so if new1 = new2, then f(new1) = f(new2). Since old rows
     * were distinct, this means that we cannot have two identical
     * new rows.
     */
    old forall { case (col, _) =>
      synthesis.getOrElse(Left(col), Set()) exists {
        _ forall { case Right(_) => true ; case Left(_) => false }
      }
    }
  }
}
