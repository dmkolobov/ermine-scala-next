package com.clarifi.reporting
package record

import scala.collection.GenTraversableOnce
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
  private[this] type ValueSeq[A] = Array[AnyRef]
  private[record] type KeyCache[A] = Map[A, Int]

  private[this]
  def indexValueSeq[A](vs: ValueSeq[A], i: Int): A = vs(i).asInstanceOf[A]

  private[this]
  def emptyKeyCache[A] : KeyCache[A] = Map()

  override def apply[A, B](elems: (A, B)*): RecordMap[A, B] = {
    val vs = iPromiseToFillThis[B](elems.size)
    val (ks, fi) = elems.foldLeft((emptyKeyCache[A],0)){
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
    SharingKeySet(ks, vs)
  }

  def apply[A, B](other: Map[A, B]): RecordMap[A, B] =
    fromMap(other)

  def apply[A, B](tr: TraversableOnce[(A, B)]): RecordMap[A, B] =
    apply(tr.toSeq:_*)

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
      bf() mapResult (fromMap(_))

    def apply(from: Map[A, Any]): Builder[(A, B), RecordMap[A, B]] = from match {
      case sks: SharingKeySet[A, _] =>
        new SameKeyBuilder(sks.keyCache, bf, from)
      case _ =>
        bf(from) mapResult (fromMap(_))
    }
  }

  private[this] def iPromiseToFillThis[A](n: Int): ArrayBuffer[A] =
    ArrayBuffer.fill(n)(null.asInstanceOf[A])

  private[this] final class SameKeyBuilder[A, B]
    (keyCache: KeyCache[A],
     bf: CanBuildFrom[Map[A, Any], (A, B), Map[A, B]],
     from: Map[A, Any])
      extends Builder[(A, B), RecordMap[A, B]] {

    private[this] val vals: ArrayBuffer[B] =
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
          SharingKeySet(keyCache, vals)
        else {
          val fb = bf(from)
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
  final class SharingKeySet[A, B](private[RecordMap] val keyCache: KeyCache[A],
                                  values: ValueSeq[B])
      extends RecordMap[A, B] {
    
    
    def +[B1 >: B](kv: (A, B1)): imm.Map[A, B1] =
      (keyCache get kv._1) match {
        case None =>
          SharingKeySet(keyCache updated (kv._1, keyCache.size), values :+ kv._2.asInstanceOf[AnyRef])
        case Some(i) =>
          new SharingKeySet(keyCache, values updated (i, kv._2.asInstanceOf[AnyRef]))
      }

    override def ++[B1 >: B](xs: GenTraversableOnce[(A, B1)]): imm.Map[A, B1] ={
       val maxSize = values.size + xs.size
       val vals = new Array[AnyRef](maxSize)
       values.copyToArray(vals)

       val (ks, sz) = xs.foldLeft((keyCache, values.size)) {
         case (st@(kc, i), (key, v)) => kc get key match {
           case None => vals(i) = v.asInstanceOf[AnyRef] ; (kc updated (key, i), i+1)
           case Some(j) => vals(j) = v.asInstanceOf[AnyRef] ; st
         }
       }
       
       val trimmedVals = new Array[AnyRef](sz)
       vals.copyToArray(trimmedVals)
       SharingKeySet(ks, trimmedVals)
    }

    def -(key: A): RecordMap[A, B] =
      keyCache get key match {
        case None => this
        case Some(i) => rebuild((k,j) => i != j, keyCache, values)
      }

    def --(keys: Traversable[A]): RecordMap[A, B] = {
      val subKeyCache = keyCache -- keys

      if (subKeyCache.size == keyCache.size) this
      else rebuild((k,i) => subKeyCache.contains(k), keyCache, values)
    }

    def get(key: A): Option[B] = keyCache get key map (indexValueSeq(values,_))

    def iterator: Iterator[(A, B)] =
      keyCache.iterator map { case (k, i) => (k, indexValueSeq(values, i)) }

    // Optimizations
    override def transform[C, That](f: (A, B) => C)
                          (implicit bf: CanBuildFrom[RecordMap[A, B], (A, C), That]): That =
      bf match {
        case bfr: MayShareKeys[A, C] =>
          // The keyset is guaranteed not to change, so we can skip
          // the filling checks in SameKeyBuilder.
          val out = iPromiseToFillThis[C](values.size)
          keyCache foreach { case (k, i) =>
            out(i) = f(k, indexValueSeq(values, i))
          }
          new SharingKeySet(keyCache, out.asInstanceOf[ArrayBuffer[AnyRef]].toArray): That
        case _ => super.transform(f)(bf)
      }

    override def mapValues[C](f: B => C): Map[A, C] =
      new SharingKeySet(keyCache, values map (x => f(x.asInstanceOf[B]).asInstanceOf[AnyRef]))

    override def filterKeys(p: A => Boolean): Map[A, B] =
      rebuild((key,i) => p(key), keyCache, values)

    private[record] def rkeyCache: Option[RecordMap.KeyCache[A]] =
      Some(keyCache)
  }
  private[this]
  object SharingKeySet {
    /* Smart constructor canonicalizes the key cache for reduced memory footprint */
    def apply[A,B](kc: KeyCache[A], vs: ArrayBuffer[B]): SharingKeySet[A, B] =
      new SharingKeySet(canonicalizeKeyCache(kc), vs.asInstanceOf[ArrayBuffer[AnyRef]].toArray)

    def apply[A,B](kc: KeyCache[A], vs: ValueSeq[B]): SharingKeySet[A, B] =
      new SharingKeySet(canonicalizeKeyCache(kc), vs)
  }


  private[this]
  def rebuild[A, B](pred: (A, Int) => Boolean,
                    keyCache: KeyCache[A],
                    vals: ValueSeq[B]): SharingKeySet[A, B] = {
                    
    val newSize = keyCache.foldLeft(0) {
      case (j, (key, i)) =>
        if (pred(key, i)) j+1
        else j
    }    
    val newVals = new Array[AnyRef](newSize)

    val (newKeyCache, n) = keyCache.foldLeft((emptyKeyCache[A], 0)) {
      case (st@(kc, j), (key, i)) =>
        if(pred(key, i)) {
          newVals(j) = vals(i)
          (kc updated (key, j), j+1)
        } else st
    }

    SharingKeySet(newKeyCache, newVals)
  }

  private[this]
  def fromMap[A,B](other: Map[A, B]): SharingKeySet[A, B] = {
    val vals = iPromiseToFillThis[B](other.size)

    val (keyCache, _) = other.foldLeft((emptyKeyCache[A], 0)) {
      case ((kc, i), (k, v)) =>
        vals(i) = v
        (kc updated (k, i), i+1)
    }

    SharingKeySet(keyCache, vals)
  }
}
