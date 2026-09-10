package com.clarifi.reporting.ermine

import scalaz._
import scalaparsers.{Loc, Located}
import scala.collection.immutable.List
import scala.collection.Iterable
import Equal._
import Show._

sealed abstract class Kind extends Located {
  def ->:(that: Kind) = ArrowK(Loc.builtin, that, this)
  def mono(f: Loc => Loc): Kind = this
  def subst(m : PartialFunction[V[Unit],Kind]): Kind = this
  def vars: Vars[Unit] = Vars()
  def isMono: Boolean = true
  def schema = KindSchema(this.loc, List(), this)
}

case class Rho(loc: Loc) extends Kind {
  override def equals(v: Any) = v match {
    case Rho(_) => true
    case _      => false
  }
  override def hashCode = 73 // chosen by rolling 20d6
}
case class Star(loc: Loc) extends Kind {
  override def equals(v: Any) = v match {
    case Star(_) => true
    case _       => false
  }
  override def hashCode = 57 // chosen by rolling 20d6
}
case class Field(loc: Loc) extends Kind {
  override def equals(v: Any) = v match {
    case Field(_) => true
    case _        => false
  }
  override def hashCode = 76 // chosen by rolling 20d6
}
case class Constraint(loc: Loc) extends Kind {
  override def equals(v: Any) = v match {
    case Constraint(_) => true
    case _             => false
  }
  override def hashCode = 84 // chosen by rolling 20d6
}
case class ArrowK(loc: Loc, i: Kind, o: Kind) extends Kind {
  override def mono(f: Loc => Loc) = ArrowK(loc, i.mono(f), o.mono(f))
  override def subst(m: PartialFunction[V[Unit],Kind]) = {
    // Return THIS when nothing underneath changed, so an untouched subtree
    // costs no allocation.  instantiateType substitutes a SINGLETON map across
    // the whole environment (Subst.scala:186) and most entries never mention
    // the variable -- but every constructor on the path must preserve physical
    // identity or the sharing is lost one level up.  Roadmap P7 Step 1.
    val ip = i.subst(m); val op = o.subst(m)
    if ((ip eq i) && (op eq o)) this else ArrowK(loc, ip, op)
  }
  override def vars = i.vars ++ o.vars
  override def isMono = i.isMono && o.isMono
}

case class VarK(v: V[Unit]) extends Kind with Variable[Unit] {
  override def mono(f: Loc => Loc) = Star(f(v.loc))
  override def subst(m: PartialFunction[V[Unit], Kind]) = m.lift(v).getOrElse(this)
  override def vars = Vars(v)
  override def isMono = false
  override def toString = v.toString
}

object Kind {
  import scalaparsers.Relocatable

  val star       = Star(Loc.builtin)
  val rho        = Rho(Loc.builtin)
  val constraint = Constraint(Loc.builtin)

  implicit def relocatableKind: Relocatable[Kind] = new Relocatable[Kind] {
    def setLoc(k: Kind, l: Loc) = k match {
      case Rho(_) => Rho(l)
      case Star(_) => Star(l)
      case Field(_) => Field(l)
      case Constraint(_) => Constraint(l)
      case ArrowK(_, i, o) => ArrowK(l, i, o)
      case VarK(v) => VarK(v.copy(loc = l))
    }
  }

  def zipKinds[A](xs: Iterable[A], ks: Iterable[V[Unit]]): Map[A,Kind] = xs.zip(ks.map(VarK(_):Kind)).toMap

  implicit def showKind: Show[Kind] = showA[Kind]
  implicit def equalKind: Equal[Kind] = equalA[Kind]

  def productKind(l: Loc, n: Int): Kind = if (n == 0) Star(l) else ArrowK(l, Star(l), productKind(l, n - 1))

  def monomorphize(k: Kind, f: (Loc => Loc) = (x => x)) = k.mono(f)
  def kindVars[A](a: A)(implicit A:HasKindVars[A]): Vars[Unit] = A.vars(a)
  def fkvs[A](a: A)(implicit A:HasKindVars[A]): Traversable[V[Unit]] = A.vars(a).filter(_.ty == Free)
  // NO empty-map fast path here, deliberately -- see roadmap P7 Step 1.  Adding
  // one (mirroring Type.subType:606-607) is semantically a no-op and it still
  // MOVED browse.txt bytes, because typeHasKindVars.sub is `t.map(_.subst(m))`
  // and Part.map goes through Part.apply, whose foldLeft REVERSES the RHS on
  // every pass.  The rendered order of a partition is therefore a function of
  // how many substitution passes happened to run.  Skipping a no-op pass flips
  // the parity: r <- (sr, xr, yr, o) became r <- (o, yr, xr, sr).
  def subKind[A](m: PartialFunction[V[Unit],Kind], a: A)(implicit A:HasKindVars[A]) = A.sub(m, a)

  implicit def kindHasKindVars: HasKindVars[Kind] = new HasKindVars[Kind] {
    def vars(k: Kind) = k.vars
    def sub(m: PartialFunction[KindVar, Kind], a: Kind) = a.subst(m)
  }

  def occursCheckKind(v: V[_], e: Kind) = e match {
    case VarK(_)    => false
    case _          => kindVars(e).contains(v)
  }
}

abstract class HasKindVars[A] {
  def vars(a: A): Vars[Unit]
  def sub(m: PartialFunction[KindVar, Kind], a: A): A
}

object HasKindVars {
  implicit def mapHasKindVars[K,A](implicit A:HasKindVars[A]): HasKindVars[Map[K,A]] = new HasKindVars[Map[K,A]] {
    def vars(xs: Map[K, A]) = xs.foldRight(Vars():Vars[Unit])((x,ys) => A.vars(x._2) ++ ys)
    def sub(m: PartialFunction[KindVar, Kind], xs: Map[K, A]): Map[K, A] = xs.map(p => (p._1, A.sub(m, p._2)))
  }

  implicit def listHasKindVars[A](implicit A:HasKindVars[A]): HasKindVars[List[A]] = new HasKindVars[List[A]] {
    def vars(xs: List[A]) = xs.foldRight(Vars():Vars[Unit])((x,ys) => A.vars(x) ++ ys)
    def sub(m: PartialFunction[KindVar, Kind], xs: List[A]): List[A] = xs.map(A.sub(m, _))
  }

  implicit def vHasKindVars[K,A](implicit A:HasKindVars[A]): HasKindVars[V[A]] = new HasKindVars[V[A]] {
    def vars(v: V[A]) = A.vars(v.extract)
    def sub(m: PartialFunction[KindVar, Kind], xs: V[A]): V[A] = xs.map(A.sub(m, _))
  }
}
