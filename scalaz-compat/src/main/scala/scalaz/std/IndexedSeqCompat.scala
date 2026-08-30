package scalaz
package std

/** scalaz 7.0's `scalaz.std.indexedSeq`.
  *
  * The `IndexedSeq` instances were dropped after 7.0 (only `list`, `vector` and
  * `iterable` survive), but this codebase uses `IndexedSeq` as its sequence type
  * throughout the reporting and charting layers. The 7.0 original is built on
  * `CanBuildFrom`, which 2.13 removed, so this is a reimplementation of the same
  * instances against the modern collections rather than a verbatim copy.
  */
object indexedSeq extends IndexedSeqInstances with IndexedSeqFunctions

trait IndexedSeqInstances {
  implicit val indexedSeqInstance: Traverse[IndexedSeq] with MonadPlus[IndexedSeq]
    with Zip[IndexedSeq] with Unzip[IndexedSeq] with IsEmpty[IndexedSeq] =
    new Traverse[IndexedSeq] with MonadPlus[IndexedSeq]
        with Zip[IndexedSeq] with Unzip[IndexedSeq] with IsEmpty[IndexedSeq] {
      def point[A](a: => A): IndexedSeq[A] = IndexedSeq(a)
      def bind[A, B](fa: IndexedSeq[A])(f: A => IndexedSeq[B]): IndexedSeq[B] = fa flatMap f
      def empty[A]: IndexedSeq[A] = IndexedSeq.empty
      def plus[A](a: IndexedSeq[A], b: => IndexedSeq[A]): IndexedSeq[A] = a ++ b
      def isEmpty[A](fa: IndexedSeq[A]): Boolean = fa.isEmpty
      def zip[A, B](a: => IndexedSeq[A], b: => IndexedSeq[B]): IndexedSeq[(A, B)] = a zip b
      def unzip[A, B](a: IndexedSeq[(A, B)]): (IndexedSeq[A], IndexedSeq[B]) = a.unzip

      override def map[A, B](fa: IndexedSeq[A])(f: A => B): IndexedSeq[B] = fa map f
      override def length[A](fa: IndexedSeq[A]): Int = fa.length
      override def index[A](fa: IndexedSeq[A], i: Int): Option[A] = fa.lift(i)
      override def foldLeft[A, B](fa: IndexedSeq[A], z: B)(f: (B, A) => B): B = fa.foldLeft(z)(f)
      override def foldRight[A, B](fa: IndexedSeq[A], z: => B)(f: (A, => B) => B): B =
        fa.foldRight(z)((a, b) => f(a, b))
      override def foldMap[A, B](fa: IndexedSeq[A])(f: A => B)(implicit M: Monoid[B]): B =
        fa.foldLeft(M.zero)((b, a) => M.append(b, f(a)))

      def traverseImpl[F[_], A, B](fa: IndexedSeq[A])(f: A => F[B])(
        implicit F: Applicative[F]): F[IndexedSeq[B]] =
        F.map(std.vector.vectorInstance.traverse(fa.toVector)(f))(v => v: IndexedSeq[B])
    }

  implicit def indexedSeqMonoid[A]: Monoid[IndexedSeq[A]] = new Monoid[IndexedSeq[A]] {
    def zero: IndexedSeq[A] = IndexedSeq.empty
    def append(a: IndexedSeq[A], b: => IndexedSeq[A]): IndexedSeq[A] = a ++ b
  }

  implicit def indexedSeqEqual[A](implicit A: Equal[A]): Equal[IndexedSeq[A]] =
    new Equal[IndexedSeq[A]] {
      def equal(a: IndexedSeq[A], b: IndexedSeq[A]): Boolean =
        a.length == b.length && a.corresponds(b)(A.equal)
    }

  implicit def indexedSeqOrder[A](implicit A: Order[A]): Order[IndexedSeq[A]] =
    new Order[IndexedSeq[A]] {
      def order(a: IndexedSeq[A], b: IndexedSeq[A]): Ordering = {
        var i = 0
        while (i < a.length && i < b.length) {
          val o = A.order(a(i), b(i))
          if (o != Ordering.EQ) return o
          i += 1
        }
        Ordering.fromInt(a.length compare b.length)
      }
    }

  implicit def indexedSeqShow[A](implicit A: Show[A]): Show[IndexedSeq[A]] =
    Show.show(as => Cord("[", Cord.mkCord(",", as.map(A.show).toList: _*), "]"))
}

trait IndexedSeqFunctions {
  /** `[]` if empty, otherwise a `NonEmptyList`. */
  final def toNel[A](as: IndexedSeq[A]): Option[NonEmptyList[A]] =
    if (as.isEmpty) None
    else Some(NonEmptyList.nel(as.head, IList.fromList(as.tail.toList)))

  final def toZipper[A](as: IndexedSeq[A]): Option[Zipper[A]] =
    std.stream.toZipper(as.toStream)
}
