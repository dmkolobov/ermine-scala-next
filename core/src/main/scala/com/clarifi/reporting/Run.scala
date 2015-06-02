package com.clarifi.reporting

/** A G-algebra for "running" a value in G
  * where G is usually some monad.
  *
  * @note identity law: run(fa) == run(run(fa).point[G]) | Applicative[G]
  * @note distributive law: run(f)(run(fa)) == run(fa <*> f) | Apply[G]
  */
trait Run[G[_]] {
  def run[A](a: G[A]): A
}

object Run {
  import scalaz.{Applicative, Name}

  def runLazyM[G[_]](implicit R: Run[G], G: Applicative[G]): util.Lazy.Monad[G] =
    new util.Lazy.Monad[G] {
      def point[A](a: => A): G[A] = G.point(a)

      override def map[A, B](fa: G[A])(f: Name[A] => B): G[B] =
        point(f(Name(R.run(fa))))

      def flatMap[A, B](fa: G[A])(f: Name[A] => G[B]): G[B] =
        f(Name(R.run(fa)))
    }
}
