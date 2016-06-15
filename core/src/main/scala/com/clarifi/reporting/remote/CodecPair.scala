package com.clarifi.reporting
package remote

import f0.{Reader, Writer}

/** A pair of reader and writer with erased format.
  *
  * This both reduces the size of type information by changing "must
  * be this product of this and this sum and such" to "must come from
  * this exact CodecPair".  The error messages are also made much
  * friendlier this way.
  */
sealed abstract class CodecPair[A] {
  type F

  val R: Reader[A, F]
  val W: Writer[A, F]
}

sealed abstract class CodecPairDynamic[A] extends CodecPair[A] {
  val reifiedF: F
}

object CodecPair {
  def apply[A, F0](r: Reader[A, F0])(w: Writer[A, F0]): CodecPair[A] =
    new CodecPair[A] {
      type F = F0
      val R = r
      val W = w
    }

  def withSelfDescribing[A, F0](r: Reader[A, F0])(w: Writer[A, F0])(implicit F0: F0)
      : CodecPairDynamic[A] =
    new CodecPairDynamic[A] {
      type F = F0
      val reifiedF = F0
      val R = r
      val W = w
    }
}

/** Example for erasing the F type for a generic codec.  The only real
  * important thing is to make the definition a `val` or `lazy val`
  * instead of a `def` and exclude `type F` from the `val`'s
  * ascription; all other details can vary as needed to satisfy
  * different `R` and `W` arguments, via introduction of new types
  * like `CodecPair2`.
  */
abstract class CodecPair2[A[_, _]] {
  type F[L, R]

  def R[L, LF, R, RF](l: Reader[L, LF], r: Reader[R, RF])
      : Reader[A[L, R], F[LF, RF]]

  def W[L, LF, R, RF](l: Writer[L, LF], r: Writer[R, RF])
      : Writer[A[L, R], F[LF, RF]]

  def P[L, LF, R, RF](lr: Reader[L, LF], rr: Reader[R, RF],
                      lw: Writer[L, LF], rw: Writer[R, RF])
      : CodecPair[A[L, R]] =
    CodecPair(R(lr, rr))(W(lw, rw))
}
