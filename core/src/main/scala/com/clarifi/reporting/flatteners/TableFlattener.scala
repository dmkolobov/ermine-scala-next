package com.clarifi.reporting.flatteners

import scalaz._
import scalaz.Scalaz._
import scalaz.Lens._

import scalaz.concurrent.Strategy

import com.clarifi.reporting.Reporting._
import com.clarifi.reporting.flatteners.Flatteners._
import com.clarifi.reporting.util.StreamTUtils._
import com.clarifi.reporting._

/**
 * Like `RowFlattener`, except that all emitted rows are associated with
 * a named table. The combinators allowed for TableFlattener are a bit different
 * than those for `RowFlattener`. In particular, `join` is not defined for
 * `TableFlattener`, since there is no single "root" table, but `streamT`,
 * which converts a `TableFlattener[S,A] => TableFlattener[S,StreamT[Id,A]]` is
 * defined.
 */
abstract class TableFlattener[S,-A] extends Flattener[TableFlattener,S,A] {
  type M[+X] = State[S,X]
  // Scala 3 will not unify scalaz's IndexedStateT instances through this
  // alias on its own, so name the monad explicitly.
  implicit val MMonad: Monad[M] = StateT.stateMonad[S]
  def apply(a: A): DataSetS[S]
  def schema: Map[TableName, Header]
  def roots: Set[TableName]
  def hints: Hints

  /** Inserts the rows output by `t(x)` before outputing the rows for this flattener.
    * Does not affect the schema or hints for this `TableFlattener`. */
  def prepend[B](t: TableFlattener[Unit,B])(x: B) = TableFlattener[S,A](
    a => t.lens(Lens.trivialLens)(x) ++ apply(a),
    schema,
    roots,
    hints
  )

  def contramap[B](f: B => A): TableFlattener[S,B] = TableFlattener[S,B](
    a => apply(f(a)),
    schema,
    roots,
    hints
  )

  def either[B](that: TableFlattener[S,B]) = TableFlattener[S,Either[A,B]](
    _.fold(this(_),that(_)),
    this.schema ++ that.schema,
    this.roots ++ that.roots,
    this.hints union that.hints
  )

  def lens[T](l: Lens[T,S]): TableFlattener[T,A] = {
    type N[+X] = State[T, X]
    TableFlattener[T,A](
      (a: A) => this(a).trans[N](l.liftsNT),
      schema,
      roots,
      hints
    )
  }

  // TODO: there is logically a foreign key constraint on the linkage from the roots of the old table flattener
  // to the new unnamed row being emitted by the row flattener
  def row(col: ColumnName, counter: Lens[S,Int]): RowFlattener[S,A] = {
    val root = intKey(col).trivial[S]
    val aug = root augment this
    RowFlattener[S,A](
      a => for {
        n <- counter += 1
        tt <- root(n)
      } yield (tt._1, aug((n,a))),
      root.header,
      schema,
      root.factHints,
      aug.hints // TODO: add foreign key constraints to each of aug.rootTables to the 'fact' table.
    )
  }

  def localState(s0: S) : TableFlattener[Unit, A] = {
    type N[+X] = State[Unit, X]
    val tau = new (Id ~> N) {
      def apply[C](c: C) = State((u:Unit) => (u,c))
    }
    TableFlattener[Unit, A](
      (a: A) => StreamT.runStreamT(apply(a), s0).trans[N](tau),
      schema,
      roots,
      hints
    )
  }
  // def join(rhs: RowFlattener[S,B]): TableFlattener[S,(A,B)]

  def mapRootColumnNames(f: ColumnName => ColumnName): TableFlattener[S,A] = {
    def hack[V](tt: (TableName, Map[ColumnName, V])): (TableName, Map[ColumnName, V]) =
      if (roots contains tt._1)
        (tt._1, tt._2.map(f.first[V]))
      else
        tt
    TableFlattener[S, A](
      a => this(a).map(hack),
      this.schema.map(hack),
      this.roots,
      hints.rehintAll(roots, _ rename f)
    )
  }

  // TODO: check confirm neither flattener contains each other's roots?
  def tuple[B](that: TableFlattener[S,B]): TableFlattener[S, (A,B)] =
    TableFlattener[S, (A,B)](
      ab => this(ab._1) ++ that(ab._2),
      this.schema ++ that.schema,
      this.roots ++ that.roots,
      this.hints union that.hints
    )

  def orthogonalTuple[T,B](that: TableFlattener[T,B]): TableFlattener[(S,T), (A,B)] =
    lens(firstLens[S,T]).tuple(that.lens(secondLens[S,T]))

  def unfold[K](g: K => Option[(A, K)]) : TableFlattener[S, K] = {
    lazy val f : TableFlattener[S, K] = TableFlattener[S, K](
      k1 => g(k1) match {
        case None => StreamT.empty[M, (TableName, Record)]
        case Some((a, k2)) => this(a) ++ f(k2)
      },
      schema,
      roots,
      hints
    )
    f
  }

  def reroot(implicit witness: S =:= Unit): TableFlattener[Unit, A] =
    TableFlattener[Unit, A](
      a => this(a).asInstanceOf[DataSetS[Unit]],
      schema,
      schema.keySet.toSet,
      hints
    )

  def rerootS: TableFlattener[S, A] =
    TableFlattener[S, A](this.apply, this.schema,
                         this.schema.keySet.toSet, this.hints)

    
  private def iterableImpl: TableFlattener[S, Iterable[A]] =
    this unfold ((it: Iterable[A]) =>
      if (it.isEmpty) none
      else some ((it.head, it.tail)))

  def iterable: TableFlattener[S,Iterable[A]] = iterableImpl contramap ((i: Iterable[A]) => i.toStream)
  def streamT[B<:A]: TableFlattener[S,StreamT[Id,B]] = TableFlattener[S,StreamT[Id,B]](
    s => s.trans(new (Id ~> M){
      def apply[A](x: A) = x.pure[M]
    }).flatMap(x => this(x)),
    schema,
    roots,
    hints
  )
}

object TableFlattener {
  def apply[S,A](
                  f: A => DataSetS[S],
                  s: Map[TableName, Header],
                  r: Set[TableName],
                  h: Hints
                  ): TableFlattener[S,A] = new TableFlattener[S,A] {
    def apply(a: A) = f(a)
    val schema = s
    val roots = r
    val hints = h.check(s)
    def mapNames(t: TableName => TableName) = {
      def fixNames[A](x: (TableName,A)): (TableName,A) = (t(x._1), x._2)
      TableFlattener(f(_).map(fixNames), s.map(fixNames), r.map(t), h.mapNames(t))
    }
  }

  /** Like `persistExisting`, but permit operating over stateful
    * flatteners, and yield the final state.
    */
  def persistExistingS[G[+_], S, A](backend:Backend[G], f: TableFlattener[S,A], batchSize: Int = 5000)(a: A, s0: S): Kleisli[G, Source, S] = {
    implicit val M = backend.M
    for {
      ran <- Kleisli{ (_: Source) => M.point(runStreamTOut(f(a), s0))}
      (scary, statefree) = ran
      _ <- backend.populateSchema(f.schema.transform((tn,hdr) => (RefID(tn.name),hdr)),
                                 statefree, batchSize)
    } yield scary.get
  }

  /** Like persist, but does not create the tables associated with the given flattener's schema. */
  def persistExisting[G[+_], A](backend:Backend[G], f: TableFlattener[Unit,A], batchSize: Int = 5000)(a: A): Kleisli[G, Source, Unit] =
    backend.populateSchema(f.schema.transform((tn,hdr) => (RefID(tn.name),hdr)), StreamT.runStreamT(f(a),()), batchSize)

  def persistExistingConcurrently[G[+_], S, A](
    runner: Run[G],
    backend: Backend[G],
    source: Source,
    f: TableFlattener[S,A],
    batchSize: Int = 5000,
    threads: Int = 3
  )(a: A, s0: S) = {
    val (ps, stream) = runStreamTOut(f(a), s0)
    backend.populateSchemaConcurrently(
      runner,
      f.schema.transform((tn,hdr) => (RefID(tn.name), hdr)),
      source,
      stream,
      batchSize,
      threads
    )
    ps.get
  }

  /** Persist an object of type A using the given flattener. The rename function is used to provide
   * the materialized table names. The returned Map's keys are the meaningful table names used by f.
   * @param batchSize hint to the Backend to control the number of inserts rolled into each load.
   */
  def persist[G[+_], A](backend:Backend[G], f: TableFlattener[Unit,A],
                        batchSize: Int = 5000)(a: A): Kleisli[G, Source, Map[TableName,Header]] = {
    import Kleisli._
    implicit def M: Monad[G] = backend.M
    for {
      schema <- backend.createSchema(x => RefID(x.name), f.schema.map{ case (tname, hdr) => (tname -> (hdr, f.hints.tables(tname))) })
      _ <- backend.populateSchema(schema, StreamT.runStreamT(f(a), ()), batchSize)
      _ <- backend.createIndices(schema, f.hints)
      src <- ask[G, Source]
    } yield (schema mapValues { case (ridr,hdr) => hdr }).toMap
  }

}
