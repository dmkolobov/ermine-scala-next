package com.clarifi.reporting.dmtl

import Document._

import scalaz._
import scalaz.Free._
import scalaz.Trampoline._
import scalaz.Scalaz._

sealed trait M[S,+A] extends MonadicPlus[({type F[+B] = M[S,B]})#F,A] with Scoped[({type F[+B] = M[S,B]})#F,A] { that =>
  def self = that
  import M._
  def apply(s: S, xs: Stack): Trampoline[Result[S,A]]
  def run(s: S, xs: Stack = emptyStack): Result[S,A] = apply(s,xs).run
  // Functorial
  def map[B](f: A => B) = new M[S,B] {
    def apply(s: S, xs: Stack) = that(s, xs).map { _ map f }
  }
  // Filtered
  def lift[B](b: M[S,B]) = b
  def withFilter(p: A => Boolean): M[S,A] = new M[S,A] {
    def apply(s: S, xs: Stack) = that(s, xs) map {
      case r : Success[S,A] if !p(r.body) => Failure(None, xs)
      case r => r
    }
    override def withFilter(q: A => Boolean): M[S,A] = that.withFilter(x => p(x) && q(x))
  }
  // Monadic
  def flatMap[B](f: A => M[S,B]) = new M[S,B] {
    def apply(s: S, xs: Stack) = that(s, xs).flatMap {
      case Success(b, t) => f(b)(t, xs)
      case f : Failure => suspend(Return(f))
    }
  }
  // MonadicPlus
  def |[B >: A](m: => M[S,B]) = new M[S,B] {
    def apply(s: S, xs: Stack) = that(s, xs) flatMap {
      case _ : Failure => m(s, xs)
      case x => suspend(Return(x))
    }
  }
  def orElse[B>:A](b: => B) = new M[S,B] {
    def apply(s: S, xs: Stack) = that(s, xs) map {
      case _ : Failure => Success(b, s)
      case x => x
    }
  }

  // context stack
  def scope(x: String) = new M[S,A] {
    def apply(s: S, xs: Stack) = that(s, x::xs)
  }
}

object M {
  type Stack = List[String]
  val emptyStack: Stack = List()

  def apply[S,A](f: (S, Stack) => Result[S,A]): M[S,A] = new M[S,A] {
    def apply(s: S, xs: Stack): Trampoline[Result[S,A]] = suspend(Return(f(s,xs)))
  }

  implicit def sl[S,A](lens : Lens[S,A]) = M { (s:S, _) => Success(lens.get(s), s) }

  implicit def ss[S,A](st: State[S,A]): M[S,A] = M { (s, _) => {
    val (s2, a) = st(s)
    Success(a, s2)
  }}

  implicit def se[S,A](e: Either[Document,A]): M[S,A] = e.fold(fail _, unit _)

  implicit def mMonad[S]: Monad[({type F[+A] = M[S,A]})#F] = new Monad[({type F[+A] = M[S,A]})#F] {
    def pure[A](a: => A) = new M[S,A] {
      def apply(s: S, xs: Stack): Trampoline[Result[S,A]] = suspend(Return(Success(a,s)))
      override def map[B](f: A => B) = pure(f(a))
    }
    override def fmap[A,B](a: M[S,A], f: A => B) = a map f
    def bind[A,B](a: M[S,A], f: A => M[S,B]) = a flatMap f
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

  def get[S]: M[S,S] = M { (s:S, _) => Success(s, s) }
  def put[S](s : S): M[S,Unit] = M { (_:S, _) => Success((), s) }
  def mod[S](f : S => S): M[S,Unit] = M { (s:S, _) => Success((), f(s)) }
  def gets[S,A](f : S => A): M[S,A] = M { (s:S, _) => Success(f(s), s) }
  def fail[S](msg : Document): M[S,Nothing] = M { (_:S, xs:Stack) => Failure(Some(msg), xs) }
  def empty[S]: M[S,Nothing] = M { (_:S, xs) => Failure(None, xs) }
}
