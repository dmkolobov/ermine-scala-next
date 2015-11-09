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
    else simplify((ps.tail /:\ ps.head) (Predicate.Or(_, _)))

  /** Chain `ps` with AND. */
  def all(ps: Traversable[Predicate]) =
    if (ps.isEmpty) Predicate.Atom(true)
    else simplify((ps.tail /:\ ps.head) (Predicate.And(_, _)))
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
  def &(other: Fundepped[K]): Fundepped[K] = {
    val nm = other.determiners.foldLeft(determiners) {
      case (m, (k, ss)) => m + (k -> index(m,k).union(ss))
    }
    Fundepped(normalize(nm))
  }

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
   * Turns a sequence of functional dependencies specified as
   * `x, y and z determine w` into a normalized format suitable
   * for use in Fundepped.
   */
  private[Fundepped] def accumulateFDs[K](fds: TraversableOnce[(Set[K], K)], base: FDs[K] = Map[K,Set[Set[K]]]()): FDs[K] =
    fds.foldLeft(base) {
      case (m, (s, k)) =>
        val ss = index(m, k)
        m + (k -> (ss + s))
    }

  def apply[K](fds: (Set[K], K)*): Fundepped[K] =
    Fundepped(normalize(accumulateFDs[K](fds)))
}
