package com.clarifi.reporting
package record

import scala.collection.{immutable => imm, generic => g}
import g.CanBuildFrom
import scala.collection.mutable.{ArrayBuffer, BitSet, Builder}

sealed abstract class RecordMap[A, +B]
    extends /* imm.AbstractMap[A, B]
    with */ imm.Map[A, B]
    with imm.MapLike[A, B, RecordMap[A, B]]
    with Serializable {
  override def empty = RecordMap.empty[A, B]

  /** testing only */
  private[record] def rkeyCache: Option[RecordMap.KeyCache[A]]
}

sealed abstract class RecordMapLowPriorityImplicits
  extends g.ImmutableMapFactory[RecordMap] {

    /** $mapCanBuildFromInfo */
    implicit def canBuildFromLow[A, B]:
      CanBuildFrom[Map.Coll, (A, B), RecordMap[A, B]] = {
        val mcbf = new MapCanBuildFrom[A,B]
        new CanBuildFrom[Map.Coll, (A, B), RecordMap[A, B]] {
          def apply(): Builder[(A, B),RecordMap[A,B]] = mcbf.apply
          def apply(from: Map.Coll): Builder[(A,B), RecordMap[A,B]] = from match {
            case m : Coll => mcbf(m)
            case _ => mcbf()
          }
        }
      }
}

object RecordMap extends RecordMapLowPriorityImplicits {
  private[this] type ValueSeq[A] = ArrayBuffer[A]
  private[record] type KeyCache[A] = Map[A, Int]

  override def apply[A, B](elems: (A, B)*): RecordMap[A, B] = {
    val vs = iPromiseToFillThis[B](elems.size)
    val (ks, fi) = elems.foldLeft((Map.empty: KeyCache[A], 0)){
      case (st@(kc, i), (a, b)) =>
        kc get a match {
          case None =>
            vs(i) = b
            (kc updated (a, i), i + 1)
          case Some(ai) =>
            vs(ai) = b
            st
        }
    }
    vs trimEnd(vs.size - fi)
    new SharingKeySet(ks, vs)
  }

  def empty[A, B]: RecordMap[A, B] = EmptyRecMap.asInstanceOf[RecordMap[A, B]]

  private object EmptyRecMap extends RecordMap[Any, Nothing] {
    def get(key: Any): Option[Nothing] = None
    def iterator: Iterator[(Any, Nothing)] = Iterator.empty
    def +[B1 >: Nothing](kv: (Any, B1)): imm.Map[Any, B1] =
      Map(kv)
    def -(key: Any): RecordMap[Any, Nothing] = this

    private[record] def rkeyCache = None
  }

  sealed trait MoreSpecific

  implicit def canBuildFrom[A, B]
    (implicit bf: CanBuildFrom[Map[A, Any], (A, B), Map[A, B]]):
      CanBuildFrom[imm.Map[A, Any], (A, B), RecordMap[A, B]] with MoreSpecific =
    new MayShareKeys(bf)

  private[this] final class MayShareKeys[A, B]
    (bf: CanBuildFrom[Map[A, Any], (A, B), Map[A, B]])
      extends CanBuildFrom[imm.Map[A, Any], (A, B), RecordMap[A, B]]
      with MoreSpecific {

    def apply(): Builder[(A, B), RecordMap[A, B]] =
      bf() mapResult (new Proxying(_))

    def apply(from: Map[A, Any]): Builder[(A, B), RecordMap[A, B]] = from match {
      case sks: SharingKeySet[A, _] =>
        new SameKeyBuilder(sks.keyCache, bf, from)
      case _ =>
        bf(from) mapResult (new Proxying(_))
    }
  }

  private[this] def iPromiseToFillThis[A](n: Int): ValueSeq[A] =
    ArrayBuffer.fill(n)(null.asInstanceOf[A])

  private[this] final class SameKeyBuilder[A, B]
    (keyCache: KeyCache[A],
     bf: CanBuildFrom[Map[A, Any], (A, B), Map[A, B]],
     from: Map[A, Any])
      extends Builder[(A, B), RecordMap[A, B]] {

    private[this] val vals: ValueSeq[B] =
      iPromiseToFillThis(keyCache.size)
    private[this] val bitted: BitSet = BitSet()
    private[this] var fallback: Option[Builder[(A, B), Map[A, B]]] = None

    def +=(elem: (A, B)): this.type = {
      fallback match {
        case None => keyCache get elem._1 match {
          case None =>
            val fb = bf(from)
            flushTo(fb)
            fb += elem
            fallback = Some(fb)
          case Some(i) =>
            vals(i) = elem._2
            bitted += i
        }
          case Some(fb) =>
            fb += elem
      }
      this
    }

    private[this] def flushTo(fb: Builder[(A, B), Map[A, B]]): Unit =
      keyCache foreach { case (k, i) =>
        if (bitted contains i) fb += ((k, vals(i)))
      }

    def clear(): Unit = {
      bitted.clear()
      fallback = None
    }

    def result(): RecordMap[A, B] = fallback match {
      case None =>
        if (bitted.size == keyCache.size)
          new SharingKeySet(keyCache, vals)
        else {
          val fb = bf(from)
          flushTo(fb)
          new Proxying(fb.result())
        }
      case Some(fb) => new Proxying(fb.result())
    }
  }

  /** Assumes that the KeyCache provided has entries for 0..keyCache.size */
  def createWithKeyCache[A, B](keyCache: KeyCache[A])(fill: Int => B): RecordMap[A, B] = {
    val vals = iPromiseToFillThis[B](keyCache.size)
    for (i <- 0 to keyCache.size-1) {
      vals(i) = fill(i)
    }
    new SharingKeySet(keyCache, vals)
  }

  private[this] val keyCacheCache: java.util.WeakHashMap[KeyCache[_], java.lang.ref.WeakReference[KeyCache[_]]]
    = new java.util.WeakHashMap

  private[this] def storeKeyCache[A](kc: KeyCache[A]): KeyCache[A] = {
    keyCacheCache.put(kc, new java.lang.ref.WeakReference(kc))
    kc
  }

  private[this] def canonicalizeKeyCache[A](kc: KeyCache[A]): KeyCache[A] =
    keyCacheCache.get(kc) match {
      case null => storeKeyCache(kc)
      case ref => ref.get match {
        case null => storeKeyCache(kc)
        case kc => kc.asInstanceOf[KeyCache[A]]
      }
    }

  private[this]
  final class SharingKeySet[A, B](private[RecordMap] _keyCache: KeyCache[A],
                                  values: ValueSeq[B])
      extends RecordMap[A, B] {

    val keyCache: KeyCache[A] = canonicalizeKeyCache(_keyCache)

    private[this]
    def proxying: Map[A, B] = keyCache transform { case (_, i) => values(i) }

    def +[B1 >: B](kv: (A, B1)): imm.Map[A, B1] =
      (keyCache get kv._1) match {
        case None => proxying + kv
        case Some(i) =>
          new SharingKeySet(keyCache, values updated (i, kv._2))
      }

    def ++[B1 >: B](m: Map[A, B1]): imm.Map[A, B1] = {
       val vals = iPromiseToFillThis[B1](keyCache.size + m.size)
       values.copyToBuffer(vals)
       val (newKeyCache, sz) = m.foldLeft((keyCache, keyCache.size)) {
         case (st@(kc, i), (key, v)) => kc get key match {
           case Some(j) => vals(j) = v ; st
           case None => vals(i) = v ; (kc updated (key, i), i+1)
         }
       }
       vals.trimEnd(vals.size - sz)
       new SharingKeySet(newKeyCache, vals)
    }

    def -(key: A): RecordMap[A, B] =
      if (keyCache contains key) new Proxying(proxying - key)
      else this

    def get(key: A): Option[B] = keyCache get key map values
    def iterator: Iterator[(A, B)] =
      keyCache.iterator map { case (k, i) => (k, values(i)) }

    // Optimizations
    override def transform[C, That](f: (A, B) => C)
                          (implicit bf: CanBuildFrom[RecordMap[A, B], (A, C), That]): That =
      bf match {
        case bfr: MayShareKeys[A, C] =>
          // The keyset is guaranteed not to change, so we can skip
          // the filling checks in SameKeyBuilder.
          val out = iPromiseToFillThis[C](values.size)
          keyCache foreach { case (k, i) => out(i) = f(k, values(i)) }
          new SharingKeySet(keyCache, out): That
        case _ => super.transform(f)(bf)
      }

    override def mapValues[C](f: B => C): Map[A, C] =
      new SharingKeySet(keyCache, values map f)

    private[record] def rkeyCache: Option[RecordMap.KeyCache[A]] =
      Some(keyCache)
  }

  private[this]
  final class Proxying[A, +B](private[RecordMap] val inner: Map[A, B])
      extends RecordMap[A, B] {

    def +[B1 >: B](kv: (A, B1)): imm.Map[A, B1] = inner + kv
    def -(key: A): RecordMap[A,B] = new Proxying(inner - key)
    def get(key: A): Option[B] = inner get key
    def iterator: Iterator[(A, B)] = inner.iterator

    private[record] def rkeyCache = None
  }
}
