package com.clarifi.reporting
package record

import scala.collection.{immutable => imm, mutable}
import scala.collection.mutable.{ArrayBuffer, BitSet, Builder}

/** A `Map` that shares one key index between every record with the same shape.
  *
  * Records coming out of a scan all have the header's key set, so storing that
  * key set once and giving each record only an array of values is a large
  * memory win. `SharingKeySet` holds a `KeyCache` (key -> slot) that is
  * canonicalised through a weak map, plus the values array.
  *
  * Ported from the 2.11 original, which was built on `MapLike`,
  * `ImmutableMapFactory` and `CanBuildFrom` — all removed by the 2.13
  * collections redesign. The representation and the sharing behaviour are
  * unchanged; what moved is how the collection framework is told about them:
  *
  *  - `ImmutableMapFactory[RecordMap]` -> `MapFactory[RecordMap]`
  *  - the `CanBuildFrom` that noticed it was rebuilding from a `SharingKeySet`
  *    and reused its key cache -> `newSpecificBuilder`, which 2.13 asks the
  *    *source collection* for, so the key cache is reachable the same way
  *  - the `transform` override keeps its fast path explicitly.
  *
  * One thing does not survive: 2.13's `mapValues` and `filterKeys` return lazy
  * views rather than maps, so they can no longer be overridden to share keys.
  * `transform` and `filter` still do.
  */
sealed abstract class RecordMap[A, +B] extends imm.AbstractMap[A, B] with Serializable {
  override def empty: imm.Map[A, B] = RecordMap.empty[A, B]

  /** testing only */
  private[record] def rkeyCache: Option[RecordMap.KeyCache[A]]
}

object RecordMap extends scala.collection.MapFactory[RecordMap] {
  private[this] type ValueSeq[A] = Array[AnyRef]
  private[record] type KeyCache[A] = Map[A, Int]

  private[this]
  def indexValueSeq[A](vs: ValueSeq[A], i: Int): A = vs(i).asInstanceOf[A]

  private[this]
  def emptyKeyCache[A]: KeyCache[A] = Map()

  def apply[A, B](other: Map[A, B]): RecordMap[A, B] = fromMap(other)

  def apply[A, B](tr: IterableOnce[(A, B)]): RecordMap[A, B] = fromSeq(tr.iterator.toSeq)

  def from[A, B](it: IterableOnce[(A, B)]): RecordMap[A, B] = fromSeq(it.iterator.toSeq)

  def empty[A, B]: RecordMap[A, B] = EmptyRecMap.asInstanceOf[RecordMap[A, B]]

  def newBuilder[A, B]: Builder[(A, B), RecordMap[A, B]] =
    Map.newBuilder[A, B] mapResult (fromMap(_))

  private[this] def fromSeq[A, B](elems: Seq[(A, B)]): RecordMap[A, B] = {
    val vs = iPromiseToFillThis[B](elems.size)
    val (ks, fi) = elems.foldLeft((emptyKeyCache[A], 0)) {
      case (st @ (kc, i), (a, b)) =>
        kc get a match {
          case None =>
            vs(i) = b
            (kc updated (a, i), i + 1)
          case Some(ai) =>
            vs(ai) = b
            st
        }
    }
    vs trimEnd (vs.size - fi)
    SharingKeySet(ks, vs)
  }

  private object EmptyRecMap extends RecordMap[Any, Nothing] {
    def get(key: Any): Option[Nothing] = None
    def iterator: Iterator[(Any, Nothing)] = Iterator.empty
    def removed(key: Any): RecordMap[Any, Nothing] = this

    override def updated[B1 >: Nothing](key: Any, value: B1): imm.Map[Any, B1] =
      RecordMap((key, value))

    private[record] def rkeyCache = None
  }

  private[this] def iPromiseToFillThis[A](n: Int): ArrayBuffer[A] =
    ArrayBuffer.fill(n)(null.asInstanceOf[A])

  /** Builds a `RecordMap` that reuses `keyCache`, as long as every key written
    * is one the cache already knows; otherwise it falls back to a plain map
    * builder. This is what makes rebuilding a record cheap.
    */
  private[this] final class SameKeyBuilder[A, B](keyCache: KeyCache[A], from: Map[A, Any])
      extends Builder[(A, B), RecordMap[A, B]] {

    private[this] val vals: ArrayBuffer[B] = iPromiseToFillThis(keyCache.size)
    private[this] val bitted: BitSet = BitSet()
    private[this] var fallback: Option[Builder[(A, B), Map[A, B]]] = None

    def addOne(elem: (A, B)): this.type = {
      fallback match {
        case None => keyCache get elem._1 match {
          case None =>
            val fb = Map.newBuilder[A, B]
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
          SharingKeySet(keyCache, vals)
        else {
          val fb = Map.newBuilder[A, B]
          flushTo(fb)
          fromMap(fb.result())
        }
      case Some(fb) => fromMap(fb.result())
    }
  }

  /** Assumes that the KeyCache provided has entries for 0..keyCache.size */
  def createWithKeyCache[A, B](keyCache: KeyCache[A])(fill: Int => B): RecordMap[A, B] = {
    val n = keyCache.size
    val vals = new Array[AnyRef](n)
    for (i <- 0 until n) {
      vals(i) = fill(i).asInstanceOf[AnyRef]
    }
    new SharingKeySet(keyCache, vals)
  }

  private[this] val keyCacheCache: java.util.WeakHashMap[KeyCache[?], java.lang.ref.WeakReference[KeyCache[?]]] =
    new java.util.WeakHashMap

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
  final class SharingKeySet[A, B](private[RecordMap] val keyCache: KeyCache[A],
                                  values: ValueSeq[B])
      extends RecordMap[A, B] {

    def get(key: A): Option[B] = keyCache get key map (indexValueSeq(values, _))

    def iterator: Iterator[(A, B)] =
      keyCache.iterator map { case (k, i) => (k, indexValueSeq(values, i)) }

    override def size: Int = keyCache.size
    override def knownSize: Int = keyCache.size

    override def updated[B1 >: B](key: A, value: B1): imm.Map[A, B1] =
      (keyCache get key) match {
        case None =>
          SharingKeySet(keyCache updated (key, keyCache.size), values :+ value.asInstanceOf[AnyRef])
        case Some(i) =>
          new SharingKeySet(keyCache, values updated (i, value.asInstanceOf[AnyRef]))
      }

    override def concat[B1 >: B](xs: IterableOnce[(A, B1)]): imm.Map[A, B1] = {
      val other = xs.iterator.toSeq
      val maxSize = values.size + other.size
      val vals = new Array[AnyRef](maxSize)
      values.copyToArray(vals)

      val (ks, sz) = other.foldLeft((keyCache, values.size)) {
        case (st @ (kc, i), (key, v)) => kc get key match {
          case None    => vals(i) = v.asInstanceOf[AnyRef]; (kc updated (key, i), i + 1)
          case Some(j) => vals(j) = v.asInstanceOf[AnyRef]; st
        }
      }

      val trimmedVals = new Array[AnyRef](sz)
      vals.copyToArray(trimmedVals)
      SharingKeySet(ks, trimmedVals)
    }

    def removed(key: A): RecordMap[A, B] =
      keyCache get key match {
        case None => this
        case Some(i) => rebuild((k, j) => i != j, keyCache, values)
      }

    override def removedAll(keys: IterableOnce[A]): RecordMap[A, B] = {
      val subKeyCache = keyCache -- keys.iterator

      if (subKeyCache.size == keyCache.size) this
      else rebuild((k, i) => subKeyCache.contains(k), keyCache, values)
    }

    /** The key set cannot change, so fill a fresh value array in place rather
      * than going through a builder. */
    override def transform[C](f: (A, B) => C): imm.Map[A, C] = {
      val out = iPromiseToFillThis[C](values.size)
      keyCache foreach { case (k, i) =>
        out(i) = f(k, indexValueSeq(values, i))
      }
      new SharingKeySet(keyCache, out.asInstanceOf[ArrayBuffer[AnyRef]].toArray)
    }

    /** 2.13 asks the source collection for this when rebuilding a collection of
      * the same type, which is how the key cache stays shared. */
    override protected def newSpecificBuilder: Builder[(A, B), imm.Map[A, B]] =
      new SameKeyBuilder[A, B](keyCache, this)

    private[record] def rkeyCache: Option[RecordMap.KeyCache[A]] =
      Some(keyCache)
  }

  private[this]
  object SharingKeySet {
    /* Smart constructor canonicalizes the key cache for reduced memory footprint */
    def apply[A, B](kc: KeyCache[A], vs: ArrayBuffer[B]): SharingKeySet[A, B] =
      new SharingKeySet(canonicalizeKeyCache(kc), vs.asInstanceOf[ArrayBuffer[AnyRef]].toArray)

    def apply[A, B](kc: KeyCache[A], vs: ValueSeq[B]): SharingKeySet[A, B] =
      new SharingKeySet(canonicalizeKeyCache(kc), vs)
  }

  private[this]
  def rebuild[A, B](pred: (A, Int) => Boolean,
                    keyCache: KeyCache[A],
                    vals: ValueSeq[B]): SharingKeySet[A, B] = {

    val newSize = keyCache.foldLeft(0) {
      case (j, (key, i)) =>
        if (pred(key, i)) j + 1
        else j
    }
    val newVals = new Array[AnyRef](newSize)

    val (newKeyCache, n) = keyCache.foldLeft((emptyKeyCache[A], 0)) {
      case (st @ (kc, j), (key, i)) =>
        if (pred(key, i)) {
          newVals(j) = vals(i)
          (kc updated (key, j), j + 1)
        } else st
    }

    SharingKeySet(newKeyCache, newVals)
  }

  private[this]
  def fromMap[A, B](other: Map[A, B]): SharingKeySet[A, B] = {
    val vals = iPromiseToFillThis[B](other.size)

    val (keyCache, _) = other.foldLeft((emptyKeyCache[A], 0)) {
      case ((kc, i), (k, v)) =>
        vals(i) = v
        (kc updated (k, i), i + 1)
    }

    SharingKeySet(keyCache, vals)
  }
}
