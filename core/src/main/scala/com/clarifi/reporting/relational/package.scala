package com.clarifi.reporting

import com.clarifi.machines._

import scala.collection.SeqLike

import scalaz._
import Scalaz.Id
import scalaz.syntax.foldable._
import scalaz.syntax.order._
import scalaz.std.option._
import scalaz.std.list._
import scalaz.std.vector._

package object relational {
  import SortOrder._

  sealed abstract class JoinMode {
    import JoinMode._

    def reverse = this match {
      case Left => Right
      case Right => Left
      case _ => this
    }
  }

  object JoinMode {
    case object Inner extends JoinMode
    case object Left  extends JoinMode
    case object Right extends JoinMode
    case object Full  extends JoinMode
  }

  def uniqSorted: Process[Record,Record] = {
    def filter(now: Record): Process[Record, Record] =
      Plan.await[Record] flatMap { case r =>
        if (r == now) filter(now)
        else Plan.emit(r) >> filter(r)
      }
    Plan.await[Record] flatMap { r => Plan.emit(r) >> filter(r) }
  }

  def uniq(sortedBy: Set[String]): Process[Record, Record] = {
    def filter(m: Set[Record], key: Record): Process[Record, Record] =
      Plan.await[Record] flatMap { case r =>
        val (k, rest) = r partition { case (c, v) => sortedBy contains c }
        if (k == key)
          if (m contains rest) filter(m, key)
          else Plan.emit(r) >> filter(m + rest, key)
        else Plan.emit(r) >> filter(Set(rest), k)
      }
    Plan.await[Record] flatMap { case r =>
      val (k, rest) = r partition { case (c, v) => sortedBy contains c }
      Plan.emit(r) >> filter(Set(rest), k)
    }
  }

  def sorting(inorder: List[(String, SortOrder)], outorder: List[(String, SortOrder)]): Process[Record, Record] = {
    val (pre, post) = ((inorder.map(some).toStream ++ Stream.continually(none)) zip outorder
                       span { case (x, y) => x == some(y) })
    val chunkCols = pre collect {case (Some((s, _)), _) => s} toSet
    val sortCols = (post map (_._2) toList)
    if (sortCols.isEmpty) Process.apply(i => i)
    else
      Process.grouping(
        (t1: Record, t2: Record) => (t1 filterKeys chunkCols) == (t2 filterKeys chunkCols)).
        outmap(sort(_, sortCols)) andThen Machine.flattened((x: Vector[Record] => Any) => x)
  }

  type ClosedExt = Closed[Ext]
  type ClosedRel = Closed[Relation]
  type ClosedMem = Closed[Mem]

  implicit def memClosedMem(mem: Mem[Nothing, Nothing]) = Typer.closedMem(mem)

  implicit def relClosedRel(rel: Relation[Nothing, Nothing]) = Typer.closedRel(rel)

  implicit def extClosedExt(ext: Ext[Nothing, Nothing]) = Typer.closedExt(ext)

  /** Ordering on records that have all columns in `ord`. */
  def recordOrd(ord: List[(String, SortOrder)]): Order[Record] =
    Order.order((x, y) => ord.foldMap{
      case (n, Asc) => x(n) ?|? y(n)
      case (n, Desc) => y(n) ?|? x(n)
    })

  def sort[R](ts: SeqLike[Record, R], order: List[(String, SortOrder)]): R =
    ts sorted recordOrd(order).toScalaOrdering

  type OrderedProcedure[M[+_], +A] = List[(String, SortOrder)] => M[Procedure[scalaz.Id.Id, A]]

  def driveLeftId[K, A, B, C](drv: K => Option[Any])(m: Machine[K, A])(g: A => B)(initial: C)(f: (C, B) => C): C = {
    @annotation.tailrec
    def go(m: Machine[K, A], z: C): C = m match {
      case Stop =>
        z
      case Emit(a, k) => 
       // val next = k()
       // val x = g(a)
        go(k(), f(z, g(a)))
      case Await(recv, success, failure) =>
        go( drv(success).map(recv)
                        .getOrElse(failure())
          , z
          )
      case Return(x) => x  // shut up warning
      }
    go(m, initial)
  }

  abstract class EffectfulProcedure[A] extends Procedure[Id, A] { self =>
    def setup: (Driver[Id, K], () => Unit)

    override def foldLeftM[B >: A, C](initial: C)(f: (C,B) => C): Id[C] =
      withDriver( d => driveLeftId(d.apply _)(machine)(x => x: B)(initial)(f))

    def withDriver[R](k: Driver[Id, K] => R): R = {
      val (d, teardown) = setup
      val result = k(d)
      teardown()
      result
    }

    override def map[B](f: A => B): EffectfulProcedure[B] =
      new EffectfulProcedure[B] {
        type K = self.K
        def machine = self.machine.outmap(f)
        def setup = self setup
      }

    override def andThen[B](p: Process[A, B]): EffectfulProcedure[B] =
      new EffectfulProcedure[B] {
        type K = self.K
        def machine = self.machine andThen p
        def setup = self setup
      }

    override def execute[B >: A](implicit B: Monoid[B]): Id[B] =
      withDriver(d => driveLeftId[K, B, B, B](d.apply _)(machine)(x => x:B)(B.zero)((x,y) => B.append(x,y)))

    override def tee[B,C](p: Procedure[Id, B])(t: Tee[A, B, C]): Procedure[Id, C] = p match {
      case ep : EffectfulProcedure[B] => new EffectfulProcedure[C] {
          type K = self.K \/ ep.K

          def machine: Machine[K, C] = tee2(self.machine, ep.machine)(t)

          def setup: (Driver[Id, K], () => Unit) = {
            val (d1, teardown1) = self.setup
            val (d2, teardown2) = ep.setup
            (d1 * d2, () => { teardown1() ; teardown2() })
          }
        }
      case _ => new Procedure[Id, C] {
        type K = self.K \/ p.K

        def machine = tee2(self.machine, p.machine)(t)

        def withDriver[R](k: Driver[Id, K] => R): R = {
          val (d1, teardown) = self.setup
          p.withDriver[R] { d2 =>
            val result = k(d1 * d2)
            teardown()
            result
          }
        }
      }
    }
  }

  // copy of Tee.tee, from commit ce83d244dbc02a6160986bd521d27f6f34fedd11
  // Ran into a weird issue where old version of machines was being used, causing a stack overflow,
  // even though ivy should be pulling the right version
  // as a temparary hack, include the function we need here
  //TODO: test on another machine, figure out what's going on, and remove this function.
   /**
  * Feeds the output of two machines into a `Tee`. The result is a machine whose
  * inputs are described by the coproduct of the inputs of the two machines.
  */
  def tee2[A, AA, B, BB, C](
      ma: Machine[A, AA],
      mb: Machine[B, BB]
      )(t: Tee[AA, BB, C]): Machine[A \/ B, C] = {
    @annotation.tailrec
    def annihilate(
        ma: Machine[A,AA],
        mb: Machine[B,BB],
        t: Tee[AA,BB,C]
        ): Machine[A \/ B, C] = t match {
      case Stop => Stop
      case Emit(o, k) => Emit(o, () => tee2(ma, mb)(k()))
      case Await(k, s, f) => s match {
        case -\/(kl) => ma match {
          case Stop => annihilate(ma, mb, f())
          case Emit(a, next) => annihilate(next(), mb, k(kl(a)))
          case Await(g, kg, fg) =>
            Await(g andThen ((m: Machine[A, AA]) => tee2(m, mb)(t)),
                \/.left(kg),
                () => tee2(fg(), mb)(t))
          case Return(x) => x  // shut up warning
        }
        case \/-(kr) => mb match {
          case Stop => annihilate(ma, mb, f())
          case Emit(b, next) => annihilate(ma, next(), k(kr(b)))
          case Await(g, kg, fg) =>
            Await(g andThen ((m: Machine[B, BB]) => tee2(ma, m)(t)),
            \/.right(kg),
            () => tee2(ma, fg())(t))
          case Return(x) => x  // shut up warning
        }
      }
      case Return(x) => x  // shut up warning
    }
    annihilate(ma, mb, t)
  }
  def procedureFromSource[O](s: com.clarifi.machines.Source[O]) = new EffectfulProcedure[O] {
    type K = Nothing
    def machine = s
    def setup = (Driver.Id[Nothing](x => x), () => ())
  }

  type Minus[+M,+R] = MinusI[M,R] // XXX it's bizarre this has to go here and not next to MinusI
}
