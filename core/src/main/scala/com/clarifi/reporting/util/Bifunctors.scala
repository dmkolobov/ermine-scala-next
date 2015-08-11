package com.clarifi.reporting.util

import scalaz.{
  Applicative, Bifunctor, Bitraverse, Functor, Monoid, Traverse,
  Unapply
}

/** Utilities for scalaz bifunctors. */
object Bifunctors {
  type UnapplyAux[TC[_[_]], MA, M0[_]] = Unapply[TC, MA]{type M[A] = M0[A]}

  implicit class OnBitraverseOps[F[_,_]](val F: Bitraverse[F]) extends AnyVal {
    def bitraverseU[A, B, MC, MD, M[_]](fa: F[A, B])(f: A => MC, g: B => MD)
                   (implicit U1: UnapplyAux[Applicative, MC, M],
                    U2: UnapplyAux[Applicative, MD, M]): M[F[U1.A, U2.A]] =
      (F.bitraverse(fa)(U1.leibniz.subst[A => ?](f))
                   (U2.leibniz.subst[B => ?](g))(U1.TC))
  }

  implicit class OnTraverseOps[F[_]](val self: Traverse[F]) {
    /** @todo Use version from scalaz 7.1 instead. */
    def bicompose[G[_,_]](implicit G0: Bitraverse[G]): Bitraverse[λ[(α, β) => F[G[α, β]]]] =
      new TraverseBitraverse[F, G] {
        val F = self
        val G = G0
      }
  }

  /** Every functor is a bifunctor with the left parameter being a
    * phantom.
    */
  def phantomLeft[F[_]](implicit F0: Functor[F]): Bifunctor[λ[(α, β) => F[β]]] =
    new PhantomLeftBifunctor[F] {
      val F = F0
    }
}

private abstract class PhantomLeftBifunctor[F[_]] extends Bifunctor[λ[(α, β) => F[β]]] {
  def F: Functor[F]

  override def bimap[A, B, C, D](fa: F[B])(f: A => C, g: B => D) =
    F.map(fa)(g)
}

private abstract class TraverseBitraverse[F[_], G[_,_]]
    extends Bitraverse[λ[(α, β) => F[G[α, β]]]] {
  def F: Traverse[F]
  def G: Bitraverse[G]

  override def bimap[A, B, C, D](fa: F[G[A, B]])(f: A => C, g: B => D) =
    F.map(fa)(G.bimap(_)(f, g))

  override def bifoldMap[A,B,M](fa: F[G[A, B]])(f: A => M)(g: B => M)(implicit M: Monoid[M]): M =
    F.foldMap(fa)(G.bifoldMap(_)(f)(g))

  override def bifoldRight[A,B,C](fa: F[G[A, B]], z: => C)(f: (A, => C) => C)(g: (B, => C) => C): C =
    F.foldRight(fa, z)((gab, z) => G.bifoldRight(gab, z)(f)(g))

  def bitraverseImpl[M[_] : Applicative, A, B, C, D](fab: F[G[A, B]])(f: A => M[C], g: B => M[D]): M[F[G[C, D]]] =
    F.traverse(fab)(G.bitraverse(_)(f)(g))
}
