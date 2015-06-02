package com.clarifi.reporting.util

import scalaz.Name

/** A `Monad` stack where outputs may be produced without considering
  * inputs.
  */
object Lazy {
  trait Functor[F[_]] {
    def map[A, B](fa: F[A])(f: Name[A] => B): F[B]
  }

  trait Apply[F[_]] extends Functor[F] {
    /** NB: f action comes before fa action */
    def ap[A, B](fa: F[A])(f: F[Name[A] => B]): F[B]
  }

  trait Applicative[F[_]] extends Apply[F] {
    def point[A](a: => A): F[A]
    override def map[A, B](fa: F[A])(f: Name[A] => B): F[B] =
      ap(fa)(point(f))
  }

  trait Bind[F[_]] extends Apply[F] {
    def flatMap[A, B](fa: F[A])(f: Name[A] => F[B]): F[B]

    // TODO: this implementation forces 'f' before producing the B
    // value.  Is this OK? -SMRC
    override def ap[A, B](fa: F[A])(f: F[Name[A] => B]): F[B] =
      flatMap(f)(f => map(fa)(fa => f.value.apply(fa)))
  }

  trait Monad[F[_]] extends Applicative[F] with Bind[F]

  object Syntax {
    final class `Lazy ops`[F[_], A](val _self: F[A]) {
      @inline def map[B](f: Name[A] => B)(implicit L: Functor[F]): F[B] =
        L.map(_self)(f)

      @inline def ap[B](f: F[Name[A] => B])(implicit L: Apply[F]): F[B] =
        L.ap(_self)(f)

      @inline def flatMap[B](f: Name[A] => F[B])(implicit L: Bind[F]): F[B] =
        L.flatMap(_self)(f)
    }

    @inline def lazyM[F[_], A](fa: F[A]): `Lazy ops`[F, A] =
      new `Lazy ops`(fa)

    final class `Any Lazy ops`[F[_], A](val _self: F[A]) {
      def lazyM: `Lazy ops`[F, A] = Syntax.lazyM(_self)
    }

    @inline implicit def `Any Lazy ops`[F[_], A](_self: F[A]) =
      new `Any Lazy ops`(_self)
  }
}
