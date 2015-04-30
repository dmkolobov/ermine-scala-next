package com.clarifi.reporting.dmtl

import Document._

import scalaz._
import scalaz.Free._
import scalaz.Trampoline._
import scalaz.Scalaz._

sealed trait M[-I,+J,+A] extends Filtered[({type F[+B] = M[I,J,B]})#F] with Scoped[({type F[+B] = M[I,J,B]})#F] { that =>
  def self = that
  import M._
  def apply(s: I, xs: Stack): Trampoline[Result[J,A]]
  def run(s: I, xs: Stack = emptyStack): Result[J,A] = apply(s,xs).run
  // Functorial
  def map[B](f: A => B) = new M[I,J,B] {
    def apply(s: I, xs: Stack) = that(s, xs).map { _ map f }
  }
  // Filtered
  def lift[B](b: M[I,J,B]) = b
  def withFilter(p: A => Boolean): M[I,J,A] = new M[I,J,A] {
    def apply(s: I, xs: Stack) = that(s, xs) map {
      case r : Success[J,A] if !p(r.body) => Failure(None, xs)
      case r => r
    }
    override def withFilter(q: A => Boolean): M[I,J,A] = that.withFilter(x => p(x) && q(x))
  }

  // indexed monad
  def flatMap[K,B](f: A => M[J,K,B]) = new M[I,K,B] {
    def apply(s: I, xs: Stack) = that(s, xs).flatMap {
      case Success(b, t) => f(b)(t, xs)
      case f : Failure => suspend(Return(f))
    }
  }

  // MonadicPlus
  def |[B >: A](m: => M[I,J,B]) = new M[I,J,B] {
    def apply(s: I, xs: Stack) = that(s, xs) flatMap {
      case _ : Failure => m(s, xs)
      case x => suspend(Return(x))
    }
  }
  def orElse[B>:A](b: => B) = new M[I,J,B] {
    def apply(s: I, xs: Stack) = that(s, xs) map {
      case _ : Failure => Success(b, s)
      case x => x
    }
  }
  // context stack
  def scope(x: String) = new M[I,J,A] {
    def apply(s: I, xs: Stack) = that(s, x::xs)
  }
}

object M {
  type Stack = List[String]
  val emptyStack: Stack = List()

  def apply[I,J,A](f: (I, Stack) => Result[J,A]): M[I,J,A] = new M[I,J,A] {
    def apply(s: I, xs: Stack): Trampoline[Result[J,A]] = suspend(Return(f(s,xs)))
  }

  implicit def sl[S,A](lens : Lens[S,A]) = M { (s:S, _) => Success(lens.get(s), s) }

  implicit def ss[S,A](st: State[S,A]) = M { (s, _) => {
    val (s2, a) = st(s)
    Success(a, s2)
  }}

  implicit def se[S,A](e: Either[Document,A]) = e.fold(fail _, unit _)

  implicit def mMonad[S]: Monad[({type F[+A] = M[S,S,A]})#F] = new Monad[({type F[+A] = M[S,S,A]})#F] {
    def pure[A](a: => A) = new M[S,S,A] {
      def apply(s: S, xs: Stack): Trampoline[Result[S,A]] = suspend(Return(Success(a,s)))
      override def map[B](f: A => B) = pure(f(a))
    }
    override def fmap[A,B](a: M[S,S,A], f: A => B) = a map f
    def bind[A,B](a: M[S,S,A], f: A => M[S,S,B]) = a flatMap f
  }

  def warn[S](msg: String) = M { (s:S, _) => { println(msg); Success((), s) }}

  // OMGWTFBBQ. There is no Monoid instance for List[A]?!
  private def rep[S,A](n: Int)(m: M[S,A]): M[S,List[A]] =
    if (n == 0) unit(List[A]())
    else for {
      x <- m
      xs <- rep(n-1)(m)
    } yield x :: xs

  def unit[S,A](a: A): M[S,A] = M { (s:S, _) => Success(a,s) }
  def get[S]: M[S,S,S] = M { (s:S, _) => Success(s, s) }
  def put[S](s : S): M[Any,S,Unit] = M { (_:S, _) => Success((), s) }
  def mod[I,J](f : I => J): M[I,J,Unit] = M { (s:I, _) => Success((), f(s)) }
  def gets[S,A](f : S => A): M[S,S,A] = M { (s:S, _) => Success(f(s), s) }
  def fail(msg : Document): M[Any,Nothing,Nothing] = M { (_:S, xs:Stack) => Failure(Some(msg), xs) }
  def empty: M[Any,Nothing,Nothing] = M { (_:S, xs) => Failure(None, xs) }
}

// vim: set ts=4 sw=4 et:
