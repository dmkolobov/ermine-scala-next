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
}
