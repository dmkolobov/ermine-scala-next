package com.clarifi.reporting.flatteners

import collection.immutable.SortedSet

import scalaz._
import scalaz.Lens._
import scalaz.Scalaz._
import com.clarifi.reporting.Reporting._
import com.clarifi.reporting.{ TableHints, Record, ColumnName, TableName }
import com.clarifi.reporting.flatteners.Flatteners._
import com.clarifi.reporting.flatteners.Flatteners.Implicits._
import com.clarifi.reporting.util._
import NonEmptyList._

/** An `Indexee[K]` is used by the `Memo` class as the state type for memoizing keys of
  * type K. `counter` is the next id to use, and `content` has id mappings for
  * previously seen Ks.
  */
case class Indexee[K](counter: Int, content: Map[K, Int])

object Indexee {
  implicit def indexeeMonoid[K]: Monoid[Indexee[K]] = new Monoid[Indexee[K]] {
    val zero = Indexee[K](0, Map())
    def append(x: Indexee[K], y: => Indexee[K]) =
      Indexee(x.counter + y.counter, x.content |+| y.content)
  }
  def counter[K]: Lens[Indexee[K], Int] =
    Lens(x => Store(y => x copy (counter = y), x.counter))
  def content[K]: Lens[Indexee[K], Map[K, Int]] =
    Lens(x => Store(y => x copy (content = y), x.content))
}

/** Used by the `Memo` class and other combinators when adding a new piece of `Indexee[K]`
  * state onto an existing state type, `S`.
  */
case class ConsIndexee[K,S](head: Indexee[K], tail: S)

object ConsIndexee {
  type :::[K,S] = ConsIndexee[K,S]
  type :++[S,K] = ConsIndexee[K,S]
  type ::+[S,K] = ConsIndexee[K,Indexee[S]]
  implicit def consIndexeeMonoid[K,S: Monoid]: Monoid[ConsIndexee[K,S]] = new Monoid[ConsIndexee[K,S]] {
    val zero = ConsIndexee[K,S](mzero[Indexee[K]], mzero[S])
    def append(x: ConsIndexee[K, S], y: => ConsIndexee[K, S]) =
      ConsIndexee(x.head |+| y.head, x.tail |+| y.tail)
  }
  def head[K,S]: Lens[ConsIndexee[K,S], Indexee[K]] =
    Lens(x => Store(y => x copy (head = y), x.head))
  def tail[K,S]: Lens[ConsIndexee[K,S], S] =
    Lens(x => Store(y => x copy (tail = y), x.tail))
  def consUnit[K,S]: Lens[Indexee[K],ConsIndexee[K,Unit]] =
    Lens(x => Store(_.head, ConsIndexee(x, ())))
}

/** `Memo` represents a `RowFlattener` that emits only ids in the fact table -
  * values are inserted into `dimTableName` as (ID, key) pairs. If this flattener
  * sees the same key twice, it will re-emit the cached id for that key into
  * the fact table and insert nothing into the dimension table.
  *
  * The most common way to create a `Memo` is via `Memo.simple`.
  */
class Memo[S, K](
  val dimTableName: TableName, // table name to use for the dimension table
  val indexFieldName: String,  // column name to use for the id column in the dimension table
  val flattenKey: RowFlattener[S, K], // flattener for the keys
  val indexee: Lens[S, Indexee[K]] // lens into the Indexee for K
) extends RowFlattener[S, K] {
  val flattenIndex: RowFlattener[Unit, Int] = intKey(indexFieldName)
  val flattenIndexKey = flattenIndex lens Lens.trivialLens[S] join flattenKey table dimTableName

  val header = flattenIndex.header
  val factHints = flattenIndex.factHints.withFK(dimTableName, SortedSet((indexFieldName, indexFieldName)))

  val schema = flattenIndexKey.schema
  val hints = flattenIndexKey.hints

  val defaultIndex: Int = 0

  val counter: Lens[S, Int]         = Indexee.counter compose indexee
  val content: Lens[S, Map[K, Int]] = Indexee.content compose indexee

  def fresh: State[S, Int] = counter += 1

  def mapNames(f: TableName => TableName) = new Memo(f(dimTableName), indexFieldName, flattenKey, indexee)

  def lookup(k: K): State[S, (Int, Boolean)] = {
    val loc: Lens[S, Option[Int]] = content.member(k)
    loc flatMap {
      case None => for {
        id <- fresh
        _ <- loc := some(id)
      } yield (id, true)
      case Some(id) => (id, false).pure[M]
    }
  }

  def apply(key: K) = lookup(key) map {
    case (id, b) => {
      val (tup, _) = flattenIndex(id) eval (())
      (tup, if (b) flattenIndexKey((id, key)) else StreamT.empty[M,(TableName, Record)])
    }
  }
}

object Memo {
  def apply[S, K](
    table: TableName,
    idCol: ColumnName,
    k: RowFlattener[S, K],
    ix: Lens[S, Indexee[K]]
  ) = new Memo[S, K](table, idCol, k, ix)

  // todo - docs

  /** Creates a `Memo` flattener with `table` as the dimension table name, and `idColumn`
    * used as the column name for ids. A new `Indexee` is created for `K` and cons'd onto
    * the state.
    */
  def simple[S, K](table: TableName, idColumn: ColumnName, k: RowFlattener[S, K]) =
  new Memo[ConsIndexee[K,S], K](
    table,
    idColumn,
    k lens ConsIndexee.tail[K,S],
    ConsIndexee.head[K,S]
  )

  def autoId[S, K](idCol:ColumnName, k: RowFlattener[S, K]): RowFlattener[ConsIndexee[K,S], K] = {
    val keyCol = intKey(idCol).castS[Indexee[K]]
    k joinS RowFlattener(
      (_:K) => {
        for {
          newId <- Indexee.counter += 1
          r <- keyCol(newId)
        } yield r
      },
      keyCol.header,
      keyCol.schema,
      keyCol.factHints,
      keyCol.hints
    ) contramap (a => (a, a))
  }

  /** Creates a `PathMemo` (a `RowFlattener[ConsIndexee[(Int,K),S], NonEmptyList[K]`)
    * with the given dimension table name, parent id column name, and node id column name.
    * `k` is used for flattening the individual elements of the key.
    * `includeParentIdInRoot` indicates whether the parent id column should be
    * included in the fact table (this lets us find all immediate children of a node in
    * the fact table without having to first join with the dimension table).
    */
  def path[S,K](
    dimensionTable: TableName,
    parentId: ColumnName,
    nodeId: ColumnName,
    k: RowFlattener[S,K],
    includeParentIdInRoot: Boolean = false): PathMemo[ConsIndexee[(Int,K),S],K]
  = new PathMemo[ConsIndexee[(Int,K),S],K](
    dimensionTable,
    int(parentId) :: intKey(nodeId) :: k.lens(ConsIndexee.tail[(Int,K),S]) contramap bias3rFn,
    if (includeParentIdInRoot) intKey(parentId) :: intKey(nodeId) else intKey(nodeId) contramap ((p: (Int,Int)) => p._2),
    h => h.withFK(dimensionTable, SortedSet((nodeId,nodeId))),
    ConsIndexee.head[(Int,K),S])

  def labelTree[S,T,K,V](
    dimensionTable: TableName,
    factTable: TableName,
    parentId: ColumnName,
    nodeId: ColumnName,
    k: RowFlattener[S,K],
    v: RowFlattener[T,V]): TableFlattener[(ConsIndexee[(Int,K),S], T),LabelTree[K,V]]
  =
    path(dimensionTable, parentId, nodeId, k) orthogonalJoin v iterable factTable contramap (
      (lt: LabelTree[K,V]) => lt.asPathList.map { case (path,v) => (nel(path.head, path.tail),v) }
    )
}

/** A `RowFlattener[S, NonEmptyList[K]]` similar to `Memo`, in that duplicate keys
  * emit only the id for that key in the fact table and nothing in the dimension table,
  * but the structure of the dimension table is different. A `PathMemo` dimension table
  * has two id columns, a node id, and a parent node id, and common key prefixes are shared
  * (so emitting the keys [a,b] and [a,c] will produce just three rows in the dimension table,
  * one for a, one for b (with a parent node id pointing to 'a'), and one for c (with a
  * parent node id pointing to a).
  *
  * `Memo.path` is the most common way to construct a `PathMemo`.
  */
class PathMemo[S, K](
  dimTableName: TableName,
  dimRowFlattener: RowFlattener[S, (Int, Int, K)], // first Int in pair is parent id, second is node id
  factRowFlattener: RowFlattener[S, (Int, Int)], // first Int in pair is parent id, second is node id
  setFactHints: TableHints => TableHints,
  indexee: Lens[S, Indexee[(Int, K)]]
) extends RowFlattener[S, NonEmptyList[K]] {
  val dimTableFlattener = dimRowFlattener table dimTableName
  val header = factRowFlattener.header
  val factHints = setFactHints(factRowFlattener.factHints)
  val schema = dimTableFlattener.schema ++ factRowFlattener.schema
  val hints = dimTableFlattener.hints union factRowFlattener.hints

  val counter: Lens[S, Int] = Indexee.counter compose indexee
  val content: Lens[S, Map[(Int, K), Int]] = Indexee.content compose indexee

  def mapNames(f: TableName => TableName) = new PathMemo(f(dimTableName), dimRowFlattener.mapNames(f), factRowFlattener.mapNames(f), setFactHints, indexee)

  def fresh: State[S, Int] = counter += 1

  def lookup(parentId: Int, element: K): State[S, (Int, Boolean)] = {
    val loc: Lens[S, Option[Int]] = content.member((parentId, element))
    loc flatMap {
      case None => for {
        id <- fresh
        _ <- loc := some(id)
      } yield (id, true)
      case Some(id) => (id, false).pure[M]
    }
  }
  type T = (S, List[(Int, Int, K)], Int, Int) // S, Map from (parentId,k) -> childId, parentId, nodeId
  type N[X] = State[T, X]
  def freshen(k: K): State[T, Unit] = for {
    t <- init[T]
    (s, freshIds, _, parentId) = t
    p <- lensId[T]._1.lifts(lookup(parentId, k))
    (nodeId, fresh) = p
    s <- gets[T,S](_._1)
    _ <- put (
      ( s
      , if (fresh)
          ( parentId
          , nodeId
          , k) :: freshIds
        else freshIds
      , parentId
      , nodeId
      )
    )
  } yield ()

  def freshIds(kv: NonEmptyList[K]): State[S, (List[(Int, Int, K)], Int, Int)] =
    State[S, (List[(Int, Int, K)], Int, Int)](s => {
      val ((t, ids, pid, id), ()) = kv.traverse_[N](freshen).apply((s, List(), 0, 0))
      (t, (ids, pid, id))
    })

  def apply(kv: NonEmptyList[K]): State[S, (Record, DataSetS[S])] = for {
    idspidid <- freshIds(kv)
    (ids, pid, id) = idspidid
    tds1 <- factRowFlattener((pid, id))
    (tup, ds1) = tds1
  } yield (tup, ds1 ++ StreamTUtils.concatMapIterable[M,(Int,Int,K),(TableName,Record)](ids)(dimTableFlattener apply _))
}
