package com.clarifi.reporting.flatteners

import collection.immutable.SortedSet

import scalaz._
import scalaz.Scalaz._
import scalaz.Lens._

import com.clarifi.reporting.{PrimExpr, PrimT, ColumnName, Record, Header, TableName}
import com.clarifi.reporting.Reporting._
import com.clarifi.reporting.{Hints,TableHints}
import com.clarifi.reporting.util.StreamTUtils

/**
 * This represents a flattener of A that produces a single row of data,
 * possibly with suplemental tables. It uses a state type S to track
 * meta-information about how it populates the supplemental tables. The 'virtual' table
 * corresponding to the row of this flattener is called the _fact table_ or _root table_.
 *
 * The main combinators are `contramap` (for changing the input type, `A`), `lens`
 * (for changing the state type, `S`), and `join`, for concatenating the output rows
 * of two flatteners. There are RowFlatteners for all the primitives in the `Flatteners`
 * object, and RowFlatteners that memoize their results to a side dimension table in
 * `Memo`
 *
 * // TODO: clean up naming - not very consistent
 *
 * @author EAK, PSC, JAT
 */
abstract class RowFlattener[S, -A] extends Flattener[RowFlattener, S, A] {

  type M[+B] = State[S,B]
  // Scala 3 will not unify scalaz's IndexedStateT instances through this
  // alias on its own, so name the monad explicitly.
  implicit val MMonad: Monad[M] = StateT.stateMonad[S]

  def apply(a: A): State[S, (Record, DataSetS[S])]

  def header: Header

  /** Index, primary and foreign key information for the row represented by this `RowFlattener`. */
  def factHints: TableHints

  def contramap[B](f: B => A): RowFlattener[S,B] = RowFlattener[S,B](
    a => apply(f(a)),
    header,
    schema,
    factHints,
    hints
  )

  /** Modify the state type of this flattener using the given lens. */
  def lens[T](l: Lens[T,S]): RowFlattener[T,A] = {
    type N[+X] = State[T, X]
    RowFlattener[T,A](
      (a: A) => State[T, (Record, DataSetS[T])](t => {
        val (td1, td2) = l.lifts(apply(a)).apply(t)
        (td1, (td2._1, td2._2.trans[N](l.liftsNT)))
      }
      ),
      header,
      schema,
      factHints,
      hints
    )
  }

  /** Applies the given transformation to the fact table's hints. This might be used
   * after the fact to add a primary key or an extra foreign key to the fact table.
   */
  def rehintRoot(f : TableHints => TableHints) = RowFlattener[S,A](
    (a: A) => this(a),
    header,
    schema,
    f(factHints),
    hints
  )

  /** Reorders the columns in the fact table using the given total order - if cols does not include
   * all columns in the fact table, the given columns are moved to the front in addition to given
   * the specified order relative to each other. */
  def reorder(cols: List[ColumnName]) = {
    val unknown = cols.toSet -- header.keySet
    if (!unknown.isEmpty)
      sys.error("cannot reorder columns not present in this table: " + unknown + ", known columns: " + header.keySet)
    else
      rehintRoot(_.reorder(cols ++ (header.keySet -- cols)))
  }

  /** Adds an index on the given columns in the fact table of this `RowFlattener`.*/
  def index(cols: Set[ColumnName] = header.keys.toSet): RowFlattener[S,A] =
    rehintRoot(_.withIndex(SortedSet(cols.toSeq: _*), false))

  /** Combine the two flatteners such that the fact table has the concatenation of both column sets.
   * Hints and schema are updated appropriately. Note that the two flatteners must share the same
   * state in order to be joined. The flatteners can be built up using `joinS`, `skipS`, and `joinPure`
   * (or their operator equivalents - `:++`, `!++`, and `:+`) or can use explicit lensing to
   * bring their states into alignment.
   */
  def join[B](that: RowFlattener[S,B]): RowFlattener[S,(A,B)] = RowFlattener[S,(A,B)](
    ab => for {
      lhs <- this(ab._1)
      rhs <- that(ab._2)
    } yield (lhs._1 ++ rhs._1, lhs._2 ++ rhs._2),
    header ++ that.header,
    schema ++ that.schema,
    (factHints join that.factHints).withOrderings(this.header.keySet, that.header.keySet),
    hints union that.hints
  )

  /** Operator alias for `join` */
  def ++[B](head: RowFlattener[S,B]): RowFlattener[S,(A,B)] = this join head

  /** Right-associative operator alias for `join` */
  def ::[B](head: RowFlattener[S,B]): RowFlattener[S,(B,A)] = head join this

  /** Join with a flattener that adds one additional `Indexee` state. */
  def joinS[T,B](fb: RowFlattener[Indexee[T],B]): RowFlattener[ConsIndexee[T,S],(A,B)] =
    this.lens(ConsIndexee.tail[T,S]) join fb.lens(ConsIndexee.head[T,S])

  /** Operator alias for `joinS` */
  def :++[T,B](fb: RowFlattener[Indexee[T],B]): RowFlattener[ConsIndexee[T,S],(A,B)] =
    this joinS fb

  /** Operator alias for `joinPure`. */
  def :+[B](fb: RowFlattener[Unit,B]): RowFlattener[S,(A,B)] = this joinPure fb

  /** Join a pure flattener with this, lensing the pure flattener to give it the same state. */
  def joinPure[B](fb: RowFlattener[Unit,B]): RowFlattener[S,(A,B)] = this ++ fb.castS

  /** Operator alias for skipS. */
  def :![T](fb: RowFlattener[Indexee[T],_]): RowFlattener[ConsIndexee[T,S],A] = this skipS fb

  /** Drop the tail state of a `ConsIndexee` when the tail state is `Unit`. */
  def headS[T](implicit g: S =:= ConsIndexee[T,Unit]): RowFlattener[Indexee[T],A] =
    this.asInstanceOf[RowFlattener[ConsIndexee[T,Unit],A]].lens(ConsIndexee.consUnit)

  /** Conses T onto the state but ignores it, using fb as a witness of the type. Avoids the need to
   * supply type annotations to `lens` for the common case where an existing flattener witnesses the
   * type being cons'd onto the state. */
  def skipS[T](fb: RowFlattener[Indexee[T],_]): RowFlattener[ConsIndexee[T,S],A] = this.lens(ConsIndexee.tail[T,S])

  /** Converts this flattener to the given state via the trivial lens, assuming the current state is `Unit`. */
  def castS[S2](implicit u: S =:= Unit): RowFlattener[S2,A] =
    this.asInstanceOf[RowFlattener[Unit,A]].lens(Lens.trivialLens[S2])

  /** Join of two flatteners with distinct states. This probably is not what you want - you get horrible state types. */
  def orthogonalJoin[T,B](fb: RowFlattener[T, B]): RowFlattener[(S,T),(A,B)] =
    lens(firstLens[S,T]) join (fb.lens(secondLens[S,T]))

  /** Convert this `Flattener` to a pure flattener by binding the initial state argument. */
  def localState(s0: S): RowFlattener[Unit, A] = {
    type N[+X] = State[Unit, X]
    val tau = new (Id ~> N) {
      def apply[C](c: C) = State((u:Unit) => (u,c))
    }
    RowFlattener[Unit, A](
      (a: A) => State[Unit, (Record, DataSetS[Unit])](
        (u: Unit) => {
          val (s1, (record, ds)) = apply(a)(s0)
          ((), (record, StreamT.runStreamT(ds,s1).trans[N](tau)))
        }
      ),
      header,
      schema,
      factHints,
      hints
    )
  }

  /** Modify the root column names using the given function. */
  def mapRootColumnNames(f: ColumnName => ColumnName): RowFlattener[S, A] =
    RowFlattener[S,A](
      v => this(v) map { case (tup, ds) => (tup map (f.first[PrimExpr]), ds) },
      header map (f.first[PrimT.Type]),
      schema,
      factHints.rename(f),
      hints // TODO: when we add keys that link to the 'fact' table, this may have to adjust the target field of those keys
    )

  /** Adds the row represented by this row flattener as a column to all the root tables in `that`. */
  def augment[V](that: TableFlattener[S, V]): TableFlattener[S, (A, V)] = {
    TableFlattener[S, (A,V)](
      av => StreamT[M, (TableName, Record)](
        this(av._1) map { case (row, ds1) =>
          StreamT.Skip[DataSetS[S]](
            ds1 ++ that(av._2).map { tt =>
              if (that.roots(tt._1)) (tt._1, row ++ tt._2)
              else tt
            }
          )
        }
      ),
      this.schema ++ that.schema.transform((tn,hd) =>
        if (that.roots(tn)) hd ++ this.header
        else hd),
      that.roots,
      this.hints union that.hints.rehintAll(that.roots,
        (tn,th) => this.factHints join th withOrderings (this.header.keySet, that.schema(tn).keySet) mapFKs ((tn,fk) =>
        // if both tables are roots, we add this row flatteners columns to the FK
          if (that.roots(tn)) fk ++ this.header.keys.map(k => (k,k))
          else fk))
    )
  }

  def augmentWith[B](a: A, tf: TableFlattener[S,B]): TableFlattener[S,B] =
    this augment tf contramap ((b:B) => (a,b))

  def key[V](that: TableFlattener[Unit, V]): TableFlattener[S, (A, V)] =
    this augment that.reroot.lens(Lens.trivialLens[S])

  /** Promote this `RowFlattener` to a `TableFlattener` by picking a table name for the root table. */
  def table(root: TableName): TableFlattener[S,A] =
    TableFlattener[S,A](
      a => StreamT[M,(TableName, Record)](
        State[S, StreamT.Step[(TableName,Record), DataSetS[S]]](s0 => {
          val (s1, (tup, ds)) = this(a)(s0)
          (s1, StreamT.Skip(ds ++
                            ((root, tup) :: StreamT.empty[M, (TableName, Record)])))
        })
      ),
      schema + (root -> header),
      Set(root),
      hints + (root -> factHints) // TODO: and add links from hints to root for any links to the old root 'fact' table, when we support them
    )
  // NB: You betterr not try to flatten an iterable that returns rows that conflict
  def iterable(tableName: TableName): TableFlattener[S, Iterable[A]] = this table tableName iterable

  def streamT[B<:A](tableName: TableName): TableFlattener[S, StreamT[Id,B]] =
    this iterable tableName contramap (StreamTUtils.toIterable[B])
}

object RowFlattener {
  def apply[S,A](
                  f: A => State[S, (Record, DataSetS[S])],
                  h: Header,
                  s: Map[TableName, Header],
                  th: TableHints,
                  dh: Hints
                  ) : RowFlattener[S,A] = {
    if (!th.check(h,s))
      sys.error("Invalid root table hints\n" + dh)
    new RowFlattener[S,A] {
      def apply(a: A) = f(a)
      val header = h
      val schema = s
      val factHints = th
      val hints = dh.check(s)
      def mapNames(t: TableName => TableName) = {
        def fixNames[A](x: (TableName,A)): (TableName,A) = (t(x._1), x._2)
        RowFlattener(f(_).map{ case (t, d) => (t, d.map(fixNames)) }, h, s.map(fixNames), th.mapNames(t), dh.mapNames(t))
      }
    }
  }
}
