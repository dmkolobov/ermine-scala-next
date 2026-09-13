package com.clarifi.reporting
package ermine

import com.clarifi.reporting.{ PrimT }
import scalaparsers.Document.{ ordinal, text }
import com.clarifi.reporting.ermine.Relocatable.{ preserveLoc }
import scala.collection.Iterable
import scalaz.{ Show, Equal }
import scalaz.Scalaz._
import scalaparsers.{Document, Loc, Located, Supply}
import scala.collection.immutable.List
import java.util.{Date, UUID}
import java.sql.Timestamp
import Kind._
import Type._
import Show._

import scala.reflect._

/** Types
 *
 * @author EAK
 */

sealed abstract class Type extends Located {
  def map(f: Kind => Kind): Type = this
  /**
   * Fixes up a type to comply with the various invariants we
   * expect of them.
   *
   * This also expands all aliases.
   */
  def nf(implicit supply: Supply): Type = nfWith(List())
  /**
   * The internal implementation of nf, which keeps track of a stack
   * of types that the type in question is applied to.
   */
  def nfWith(stk: List[Type])(implicit su: Supply): Type = stk.foldLeft(this)(AppT(_,_))
  /**
   * The Java/Scala class that the type corresponds to for the
   * purposes of FFI marshalling.
   */
  def foreignLookup: Class[_] = implicitly[ClassTag[AnyRef]].runtimeClass
  def unboxedForeign: Boolean = false
  /**
   * A convenience function that allows us to write
   *   f(x,y,z)
   * instead of
   *   AppT(AppT(AppT(f,x),y)z)
   */
  def apply(those: Type*): Type = those.foldLeft(this)(AppT(_, _))
  def =>:(t:       (Type,List[Type])) : Type = Forall(Loc.builtin, List(), List(), Exists(Loc.builtin, List(), List(       Part(Loc.builtin,t._1,t._2))), this)
  def =>:(ts: List[(Type,List[Type])]): Type = Forall(Loc.builtin, List(), List(), Exists(Loc.builtin, List(), ts.map(t => Part(Loc.builtin,t._1,t._2))), this)
  def =>:(t: Type): Type = Forall(Loc.builtin, List(), List(), t, this)
  def ->:(that: Type): Type = Arrow(Loc.builtin, that, this)
  def subst(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type]): Type = this
  def mono: Boolean = true
  def isTrivialConstraint: Boolean = false
  def hasRowConstraints: Boolean = rowConstraints nonEmpty
  def rowConstraints: List[Type] = List()
  def isClassConstraint: Boolean = false
  def ++(t: Type) = Exists.mk(loc orElse t.loc, List(), List(this, t))
  def at(l: Loc): Type

  // TODO: actually close the type!
  /**
   * Looks through the type for unquantified variables and quantifies
   * them. This specifically ignores variables with capitalized names,
   * as we have determined that auto-quantifying those covers up
   * what should be unbound constructor errors frequently (due to our
   * mostly adhering to a Haskell-like naming convention).
   */
  def close(implicit supply: Supply): Type = closeWith(List()).nf
  /**
   * The internal implementation of close; takes a list of additional
   * variables to not be quantified.
   */
  def closeWith(vs: List[TypeVar])(implicit supply: Supply): Type = {
    val rvs = (typeVars(this) -- vs).toList.filter {
      v => !v.name.isDefined || v.name.get.string.charAt(0).isLower
    }
    if (rvs.isEmpty) this
    else Forall.mk(loc, List(), rvs, Exists(loc.inferred), this)
  }
  /**
   * Refreshes the quantified variables using the given supply, to maintain
   * the Barendregt convention in the face of subsitution.
   */
  def barendregtAlpha(implicit supply: Supply): Type = this

  /**
   * Replaces any Memory constructors with the body of the Memory
   */
  def forget: Type = this
}

/**
 * ConDecls represent various information about the way a type
 * constructor was declared, and the consequences thereof. It
 * is an open trait so that the subtypes that contain specific
 * information can appear near where that information is actually
 * used. A minimal interface that is necessary for all ConDecls
 * is of course specified.
 */
trait ConDecl {
  /**
   * This is the Class that is expected to correspond to the Con's
   * type in Scala. It is used when looking up foreign functions
   * and the like.
   */
  def foreignLookup: Class[_] = implicitly[ClassTag[AnyRef]].runtimeClass
  def unboxedForeign: Boolean = false
  /**
   * A short description of the declaration source of the Con
   */
  def desc: String
  /**
   * If the Con is a type alias, this should expand to the appropriate
   * type, given the argument list. Other types should just re-apply
   * themselves, and can use the default definition.
   */
  def expandAlias(l: Loc, self: Type, args: List[Type])(implicit su: Supply): AliasExpanded = Unexpanded(self(args:_*))
  def isInstance(p: Any): Boolean = foreignLookup.isInstance(p)
  def isTrivialConstraint: Boolean = false
  def rowConstraints: List[Type] = Nil
  def isClassConstraint: Boolean = false
}


object ClassDecl extends ConDecl {
  def desc = "class"
  override def isClassConstraint = true
}


/**
 * We enforce by construction that all row types appearing in a type
 * are either a variable, subject to some constraints, or fully
 * concrete. This is the concrete portion of that invariant.
 */
case class ConcreteRho(loc: Loc, fields: Set[Name] = Set()) extends Type {
  override def equals(v: Any) = v match {
    case ConcreteRho(_, fs) => fields == fs
    case _                  => false
  }
  // `fields.hashCode` is O(|fields|), and a row type is re-hashed on every
  // insertion into a Set or Map of Types -- Exists.apply's `p.toSet.toList`
  // being the frequent one. Memoized lazily so the cost is paid once per row
  // and only if the row is actually hashed. The VALUE is unchanged, so no
  // hash-ordered structure observes a difference.
  private[this] lazy val cachedHash: Int = fields.hashCode * 111
  override def hashCode = cachedHash
  def at(l: Loc) = ConcreteRho(l, fields)
  override def closeWith(vs: List[TypeVar])(implicit su: Supply) = this
}

/**
 * The type constructor of ordered pairs of size n
 */
case class ProductT(loc: Loc, n: Int) extends Type {
  override def foreignLookup: Class[_] =
    if (n == 0) implicitly[ClassTag[Unit]].runtimeClass
    else implicitly[ClassTag[AnyRef]].runtimeClass
  override def unboxedForeign = n == 0
  override def equals(v: Any) = v match {
    case ProductT(_, m) => m == n
    case _ => false
  }
  override def hashCode = 38 + n * 17;
  def at(l: Loc) = ProductT(l, n)
  override def closeWith(vs: List[TypeVar])(implicit su: Supply) = this
}

/**
 * Function space
 */
case class Arrow(loc: Loc) extends Type {
  override def foreignLookup = implicitly[ClassTag[Function1[_,_]]].runtimeClass
  override def nfWith(stk: List[Type])(implicit su: Supply) = stk match {
    case l :: r :: rest => Arrow(loc, l, r).apply(rest:_*)
    case _              => this.apply(stk:_*)
  }
  override def unboxedForeign = true
  override def equals(v: Any) = v match {
    case Arrow(_) => true
    case _        => false
  }
  override def hashCode = 94 // chosen by rolling 20d8 vs water elementals
  def at(l: Loc) = Arrow(l)
  override def closeWith(vs: List[TypeVar])(implicit su: Supply) = this
}

object Arrow {
  /**
   * This is a smart constructor that helps ensure that the types it produces
   * match certain invariants. For instance the type:
   *
   *    T -> forall a. U
   *
   * is reworked to:
   *
   *    forall a. T -> U
   */
  def apply(a: Loc, e1: Type, e2: Type): Type = (e1,e2) match {
    case (Forall(d,List(),List(),p,x), Forall(e,ks,ts,q,y)) => Forall(d orElse e, ks, ts, p ++ q, AppT(AppT(Arrow(a), x), y))
    case (Forall(d,List(),List(),p,x), y)                   => Forall(d orElse y.loc, List(), List(), p, AppT(AppT(Arrow(a), x), y))
    case (Forall(d,ks,ts,p,_), _) if p.hasRowConstraints    => sys.error(e1.report("higher rank row constraint").toString)
    case (x, Forall(d,ks,ts,q,y))                           => Forall(d, ks,ts, q, AppT(AppT(Arrow(a), x), y))
    case (x, y)                                             => AppT(AppT(Arrow(a), x), y)
  }
}

case class AppT(e1: Type, e2: Type) extends Type {
  def loc = e1.loc
  override def map(f: Kind => Kind) = {
    val a = e1.map(f); val b = e2.map(f)
    if ((a eq e1) && (b eq e2)) this else AppT(a, b)
  }
  override def nfWith(stk: List[Type])(implicit su: Supply) = e1.nfWith(e2.nf :: stk)
  override def foreignLookup = e1.foreignLookup
  override def unboxedForeign = e1.unboxedForeign
  // Physical-identity short-circuit; see the note on ArrowK.subst.  NOTE that
  // returning `this` also SHARES memoizedKindSchema below instead of resetting
  // it to None.  Sound, because only CLOSED schemas are ever cached
  // (Subst.scala:495) and those cannot depend on the substitution -- but it is
  // a behaviour change to kind-inference caching, not a pure allocation win.
  override def subst(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type]) = {
    val a = e1.subst(ks, ts); val b = e2.subst(ks, ts)
    if ((a eq e1) && (b eq e2)) this else AppT(a, b)
  }
  var memoizedKindSchema: Option[KindSchema] = None
  override def mono = e1.mono && e2.mono
  def at(l: Loc) = AppT(e1 at l, e2)
  override def barendregtAlpha(implicit supply: Supply) = AppT(e1.barendregtAlpha, e2.barendregtAlpha)
  override def isClassConstraint = e1.isClassConstraint
  override def forget = AppT(e1.forget, e2.forget)
}
case class VarT(v: TypeVar) extends Type with Variable[Kind] {
  override def map(f: Kind => Kind) = VarT(v.map(f))
  override def toString = v.toString
  override def subst(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type]): Type =
    // The LEAF of every traversal, and what allocated most: a variable NOT in
    // the substitution still rebuilt a fresh V (a case class) inside a fresh
    // VarT on every pass, even under an empty kind map.  Roadmap P7 Step 1.
    ts.lift(v) match {
      case Some(t) => t
      case None =>
        val k = subKind(ks, v.extract)
        if (k eq v.extract) this else VarT(v map (_ => k))
    }
  def at(l: Loc) = VarT(v at l)
}

/**
 * Exists is one of the constraint types, and exists to deal with
 * variables that occur only in constraints. Such variables should
 * _always_ be existentially quantified.
 */
class Exists(val loc: Loc, val xs: List[TypeVar] = List(), val constraints: List[Type] = List()) extends Type {
  override def map(f: Kind => Kind) = new Exists(loc, xs.map(_.map(f)), constraints.map { _ map f })
  override def toString = s"""Exists($loc, [${xs.mkString(", ")}],[${constraints.mkString(", ")}])"""
  override def nfWith(stk: List[Type])(implicit su: Supply) = Exists.mk(loc,xs,constraints.map(_.nf)).apply(stk:_*)
  override def subst(km: PartialFunction[KindVar,Kind], tm: PartialFunction[TypeVar,Type]) =
    Exists(loc, xs.map {_ map {_ subst km}}, constraints.map(_.subst(km,tm)))
  override def mono = false
  override def isTrivialConstraint = constraints.forall(_.isTrivialConstraint)
  override def rowConstraints = constraints.flatMap(_.rowConstraints)
  def at(l: Loc) = Exists(l, xs, constraints)
  override def closeWith(vs: List[TypeVar])(implicit su: Supply) = this
  override def barendregtAlpha(implicit supply: Supply) = {
    val nxs = xs map (v => v copy (id = supply.fresh))
    val xm  = xs.zip(nxs.map(VarT(_))).toMap
    Exists(loc, nxs, constraints.map(_.barendregtAlpha.subst(Map(), xm)))
  }
}

object Exists {
  def unit = Exists(Loc.builtin, List(), List())

  /**
   * A helper function for treating Exists and other constraints
   * uniformly when trying to peel off the former and get its
   * contents.
   */
  def unfurl(t: Type): (Loc, List[TypeVar], List[Type]) = t match {
    case Exists(l, xs, cs) => (l, xs, cs)
    case t                 => (t.loc, List(), List(t))
  }

  /**
   * A smart constructor. Maintains the invariant that we don't have
   * Exists-of-Exists, flattening down to a single exists quantifying
   * all the variables.
   */
  def apply(l: Loc, xs: List[TypeVar] = List(), q: List[Type] = List()): Type =
    if (xs.isEmpty && q.length == 1) q.head
    else {
      val (lp, ys, p) = q.foldLeft((l, xs, List[Type]())) {
        case ((lp, zs, r), Exists(l, xs, cs)) => (lp orElse l, zs ++ xs, r ++ cs)
        case ((lp, zs, r), t) => (lp orElse t.loc, zs, t :: r)
      }
      new Exists(lp, ys, p.toSet.toList)
    }

  def unapply(f : Exists): Option[(Loc, List[TypeVar], List[Type])] =
    Some((f.loc, f.xs, f.constraints))

  /**
    * a smarter smart constructor, which reorders the type arguments properly
    */
  def mk(l: Loc, xs: List[TypeVar], q:List[Type]) = {
    val xm = xs.toSet
    val nxs = typeVars(q).filter(xm(_)).toList
    Exists(l,nxs,q)
  }
}

/**
 * Universal quantification.
 *
 * We have both kind and type polymorphism, so Forall has list of both sorts of
 * variables. Every Forall also contains constraints that apply to the body,
 * which ensures that constraints do not occur at arbitrary places within
 * types (unless that is done via an otherwise empty Forall).
 */
class Forall(val loc: Loc, val ks: List[KindVar], val ts: List[TypeVar], val constraints: Type, val body: Type) extends Type {
  override def map(f: Kind => Kind) = new Forall(loc, ks, ts.map(_.map(f)), constraints.map(f), body.map(f))
  override def toString = s"""Forall($loc,[${ks.mkString(", ")}],[${ts.mkString(", ")}],${constraints.toString},${body.toString})"""
  override def nfWith(stk: List[Type])(implicit supply: Supply) =
    Forall.mk(loc,ks,ts,constraints.nf(supply),body.nf(supply)).apply(stk:_*)
  override def foreignLookup = body.foreignLookup
  override def unboxedForeign = body.unboxedForeign
  override def subst(km: PartialFunction[KindVar,Kind], tm: PartialFunction[TypeVar,Type]) =
    Forall(loc, ks, ts.map{_ map {_ subst km}}, constraints.subst(km,tm), body.subst(km,tm))
  override def mono = false
  def at(l: Loc) = Forall(l,ks,ts,constraints,body)
  // override def closeWith(vs: List[TypeVar])(implicit su: Supply) = this
  override def barendregtAlpha(implicit supply: Supply) = {
    val ncs = constraints.barendregtAlpha(supply)
    val nb  = body.barendregtAlpha(supply)
    val nks = ks.map(v => v copy (id = supply.fresh))
    val km  = ks.zip(nks.map(VarK(_))).toMap
    val nts = ts.map(v => subKind(km, v copy (id = supply.fresh)))
    val tm  = ts.zip(nts.map(VarT(_))).toMap
    Forall(loc, nks, nts, ncs.subst(km, tm), nb.subst(km, tm))
  }
  override def forget = Forall(loc, ks, ts, constraints.forget, body.forget)
}

object Forall {
  /**
   * A smart constructor that maintains the invariant that there are no foralls of
   * foralls. This is important for HMF checking.
   */
  def apply(l: Loc, ks: List[KindVar], ts: List[TypeVar], q: Type, b: Type): Type =
    if (ks.isEmpty && ts.isEmpty && q.isTrivialConstraint) b
    else b match {
      case Forall(lp, ksp, tsp, p, bp) => Forall(l orElse lp, ks ++ ksp, ts ++ tsp, q ++ p, bp)
      case _ => new Forall(l, ks, ts, q, b)
    }
  def unapply(f : Forall): Option[(Loc, List[KindVar], List[TypeVar], Type, Type)] =
    Some((f.loc, f.ks, f.ts, f.constraints, f.body))

  /**
   * A smarter smart constructor, which reorders the type arguments properly
   */
  def mk(l: Loc, ks: List[KindVar], ts: List[TypeVar], q: Type, b: Type): Type = b match {
    case Forall(bl, bks, bts, bq, bb) => mk(l orElse bl, ks ++ bks, ts ++ bts, q ++ bq, bb)
    case _ =>
      val km = ks.toSet
      val tm = ts.toSet
      val ats = typeVars(b)
      val nts = ats.filter(tm(_)).toList
      val nks = (kindVars(nts) ++ kindVars(b)).filter(km(_)).toList
      Forall(l,nks,nts,q,b)
  }
}

/**
 * This class represents a partition of the left side into several
 * right hand sides. We maintain no invariant that the left hand must
 * be a variable or whatnot; that is handled upon translation into a
 * format that the constraint solver can handle.
 */
class Part(val loc: Loc, val lhs: Type, val rhs: List[Type]) extends Type {
  override def map(f: Kind => Kind) = Part(loc, lhs.map(f), rhs.map(_ map f))
  override def subst(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type]) = Part(loc, lhs.subst(ks, ts), rhs.map(_.subst(ks,ts)))
  def at(l: Loc) = Part(l, lhs, rhs)
  override def closeWith(vs: List[TypeVar])(implicit su: Supply) = this
  override def equals(v: Any) = v match {
    case Part(_, lhp, rhp) => lhs == lhp && rhs == rhp
    case _ => false
  }
  override def isTrivialConstraint = false
  override def rowConstraints = List(this)
  override def hashCode = 3 + 23 * lhs.hashCode + 5 * rhs.hashCode
  override def toString = "Part(" + lhs.toString + ", " + rhs.toString + ")"
  override def barendregtAlpha(implicit supply: Supply) = Part(loc, lhs.barendregtAlpha(supply), rhs.map(_.barendregtAlpha(supply)))

  override def forget = new Part(loc, lhs.forget, rhs.map(_.forget))
}

object Part {
  /**
   * A smart constructor that does some obvious simplifications
   * without having to get into full constraint solving.
   */
  def apply(l: Loc, lh: Type, rh: List[Type]) = {
    val (ts, rcl, ss) = rh.foldLeft((List[Type](), l, List[Name]())) {
      case ((ts,l,ss), ConcreteRho(lp, s)) => (ts, lp orElse l, s.toList ++ ss)
      case ((ts,l,ss), other) => (other ::ts, l, ss)
    }
    lh match {
      // `ss` is a List[Name] and `cs` a Set[Name], so `ss == cs` was ALWAYS FALSE and this
      // guard was dead: a concrete identity was rebuilt below and reached the solver
      // (stage F3, item K-1; `ROSE-COMPARISON.md` §3 Rank 1's dated correction).  The
      // length test is what the old spelling could not have expressed and the case below
      // (`ss.toSet.size == ss.length`) does: `ss` is the concatenation of EVERY concrete
      // part, so equal sets with a longer list means two parts share a label, which is
      // unsatisfiable rather than trivially true and must be left for the solver.
      case ConcreteRho(lclhs, cs) if ts.isEmpty && ss.toSet == cs && ss.length == cs.size =>
        Exists(l) // (|Foo, Bar|) <- (|Foo,Bar|), and (|Foo,Bar|) <- ((|Foo|), (|Bar|))
      case ConcreteRho(lclhs, cs) if ts.length == 1 && ss.isEmpty =>
        new Part(l, ts(0), List(lh)) // flop the concrete rho to the right
      case _ if ts.isEmpty && ss.isEmpty => new Part(l,lh,Nil)           // a <- ()
      case _ if ss.isEmpty => new Part(l,lh, ts)                         // a <- b,c
      case _ if ss.toSet.size == ss.length =>                            // a <- ( (|Foo,Bar,Baz|), quux)
        new Part(l,lh,ConcreteRho(rcl, ss.toSet) :: ts)
      case _ => new Part(l,lh,rh) // otherwise: leave it alone, its complicated
    }
  }
  def unapply(p: Part) = Some((p.loc, p.lhs, p.rhs))
}

case class Memory(id: Int, body: Type) extends Type {
  def loc = body.loc
  override def map(f: Kind => Kind): Type = Memory(id, body map f)
  override def nfWith(stk: List[Type])(implicit su: Supply): Type = Memory(id, body.nf).apply(stk:_*)
  override def foreignLookup: Class[_] = body.foreignLookup
  override def unboxedForeign: Boolean = body.unboxedForeign
  override def subst(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type]): Type =
  {
    val b = body subst (ks, ts)
    if (b eq body) this else Memory(id, b)
  }
  override def mono: Boolean = body mono
  override def isTrivialConstraint: Boolean = body isTrivialConstraint
  override def rowConstraints: List[Type] = body rowConstraints
  override def isClassConstraint: Boolean = body isClassConstraint
  override def at(l: Loc): Type = Memory(id, body at l)
  override def barendregtAlpha(implicit supply: Supply): Type = Memory(id, body barendregtAlpha)
  override def forget = body
}

case class PrimConDecl(override val foreignLookup: Class[_]) extends ConDecl {
  val box = PrimConDecl.boxes(foreignLookup.toString)
  override val unboxedForeign = true
  override val desc = "primitive"
  override def isInstance(a: Any) = box.isInstance(a)
}

object PrimConDecl {
  lazy val boxes: Map[String, Class[_]] = Map(
    "byte" -> classOf[java.lang.Byte],
    "short" -> classOf[java.lang.Short],
    "int" -> classOf[java.lang.Integer],
    "long" -> classOf[java.lang.Long],
    "float" -> classOf[java.lang.Float],
    "double" -> classOf[java.lang.Double],
    "char" -> classOf[java.lang.Character]
  )
}

/** The stand-in `Class` of a `foreign data` whose class this JVM does
  * not have (LSP-FFI).  It is never instantiated and never matches
  * anything: its only job is to be recognisable by identity, so a
  * reflective lookup that would need the real class reports "the class
  * is missing" at the site that needs it rather than "no such method". */
final class UnresolvedForeign private ()

case class TypeConDecl(
  override val foreignLookup: Class[_],
  override val unboxedForeign: Boolean,
  /** The class name a tolerated `foreign data` could not resolve
    * (LSP-FFI kind 9).  The TYPE exists and is opaque — Ermine code may
    * mention it freely — but `foreignLookup` is the `UnresolvedForeign`
    * sentinel, so every operation that actually needs the class (a
    * reflective method/field/constructor lookup, or marshalling across
    * that boundary) can name it in its warning. */
  unresolved: Option[String] = None
) extends ConDecl {
  def desc = "data"

  /** A foreign pattern match asks the decl whether a runtime value is one
    * of these (Pattern.scala), and with no class there is nothing to ask
    * — the sentinel would answer a flat `false` and the match would
    * silently take the wrong branch (LSP-FFI review finding P-6).  Say so
    * instead.  This is RUN time only: the editor never evaluates, and a
    * batch run only reaches it with `ermine.foreign.tolerant` on. */
  override def isInstance(a: Any): Boolean = unresolved match {
    case Some(cn) =>
      sys.error("foreign type has no class on this JVM: " + cn +
                " — a pattern match against it cannot be decided")
    case None => foreignLookup.isInstance(a)
  }
}

case class FieldConDecl(fieldType: Type) extends ConDecl {
  def desc = "field"
}

class TypeAliasDecl(kindArgNames: List[KindVar], typeArgNames: List[TypeVar], body: => Type) extends ConDecl {
  override def foreignLookup: Class[_] = sys.error("foreign lookup not allowed on a type alias")
  override def unboxedForeign: Boolean = false
  def desc: String = "type"
  override def expandAlias(l: Loc, self: Type, args: List[Type])(implicit supply: Supply): AliasExpanded =
    if (args.length < typeArgNames.length)
      Bad(l.report(ordinal(typeArgNames.length,"argument", "arguments") :+: "expected, but" :+: args.length.toString :+: text("received")))
    else {
      val (xs, ys) = args.splitAt(typeArgNames.length)
      Type.expandAlias(l, subType(preserveLoc(typeArgNames.zip(xs).toMap), body).barendregtAlpha, ys)
    }

  override def isInstance(p: Any): Boolean = sys.error("isInstance not allowed on a type alias")
  override def isTrivialConstraint = body.isTrivialConstraint
  override def rowConstraints = {
    println("Warning: using rowConstraints on a typeAlias. This is probably wrong!")
    body.rowConstraints
  }
  override def isClassConstraint = {
    println("Warning: using classConstraints on a typeAlias. This is probably wrong!")
    body.isClassConstraint
  }
}

object Type {
  trait AliasExpanded {
    def map(f: Type => Type): AliasExpanded
  }
  case class Expanded(t: Type) extends AliasExpanded {
    def map(f: Type => Type) = Expanded(f(t))
  }
  case class Unexpanded(t: Type) extends AliasExpanded {
    def map(f: Type => Type) = Unexpanded(f(t))
  }
  case class Bad(d: Document) extends AliasExpanded {
    def map(f: Type => Type) = Bad(d)
  }

  /**
   * Represents most of the constructors at the type level (aside from
   * arrow and the relational types). Technically, this also includes
   * type functions that compute; aliases.
   */
  // this has to live in Type._ because otherwise the old DOS-style file handling provided by windows doesn't like CON.class
  case class Con(loc: Loc, name: Global, decl: ConDecl, schema: KindSchema) extends Type {
    def at(l: Loc) = Con(l, name, decl, schema)
    override def nfWith(stk: List[Type])(implicit su: Supply) = decl.expandAlias(loc, this, stk) match {
      case Bad(_) => this.apply(stk:_*)
      case Expanded(t) => t.nf
      case Unexpanded(t) => t
    }
    override def map(f: Kind => Kind) = Con(loc, name, decl, schema map f)
    override def foreignLookup: Class[_] = decl.foreignLookup
    override def unboxedForeign = decl.unboxedForeign
    override def subst(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type]) = Con(loc, name, decl, schema.subst(ks))
    override def equals(v: Any) = v match {
      case Con(_, oname, _, _) => name == oname
      case _ => false
    }
    override def hashCode = 92 + 13 * name.hashCode
    override def toString = name.toString + "@" + loc.toString // loc.report(name.toString).toString
    override def closeWith(vs: List[TypeVar])(implicit su: Supply) = this
    override def isTrivialConstraint = decl.isTrivialConstraint
    override def rowConstraints   = decl.rowConstraints
    override def isClassConstraint = decl.isClassConstraint
  }

  def mkConEx[C:ClassTag](s: Global, ks: KindSchema, unboxed: Boolean = true): Con =
    Con(Loc.builtin,s,TypeConDecl(implicitly[ClassTag[C]].runtimeClass, unboxed), ks)

  def mkCon[C:ClassTag](s: Global, k: Kind = star, unboxed: Boolean = true): Con =
    Con(Loc.builtin,s,TypeConDecl(implicitly[ClassTag[C]].runtimeClass, unboxed), k.schema)

  def mkPrimCon[C:ClassTag](s: Global): Con =
    Con(Loc.builtin,s,PrimConDecl(implicitly[ClassTag[C]].runtimeClass), star.schema)

  def mkRuntimeCon(s: Global, k: Kind = star, unboxed: Boolean = true): Con =
    Con(Loc.builtin,s,TypeConDecl(implicitly[ClassTag[Object]].runtimeClass, unboxed), k.schema)
  // todo: make this a foreign?

  def mkClassCon(s: Global, k: KindSchema = (star ->: constraint).schema): Con =
    Con(Loc.builtin,s, ClassDecl, k)

  // forward references into the prelude
  val bool      = mkCon[Boolean](Global("Builtin","Bool"), star, true) // constructors True and False
  val True      = Data(Global("Builtin","True"))
  val False     = Data(Global("Builtin","False"))
  val int       = mkPrimCon[Int](Global("Builtin","Int"))
  val long      = mkPrimCon[Long](Global("Builtin","Long"))
  val string    = mkCon[String](Global("Builtin","String"))
  val char      = mkPrimCon[Char](Global("Builtin","Char"))
  val float     = mkPrimCon[Float](Global("Builtin","Float"))
  val double    = mkPrimCon[Double](Global("Builtin","Double"))
  val byte      = mkPrimCon[Byte](Global("Builtin","Byte"))
  val date      = mkCon[Date](Global("Builtin","Date"))
  val uuid      = mkCon[UUID](Global("Builtin","GUID"))
  val timestamp = mkCon[Timestamp](Global("Builtin","Timestamp"))
  val short     = mkPrimCon[Short](Global("Builtin","Short"))
  val field     = mkRuntimeCon(Global("Builtin","Field",Idfix), rho ->: star ->: star, false)
  val nullable  = mkRuntimeCon(Global("Builtin","Nullable",Idfix), star ->: star, false)
  val ffi       = mkCon[FFI[_]](Global("Builtin","FFI",Idfix), star ->: star, true)
  val io        = mkRuntimeCon(Global("Builtin", "IO"), star ->: star, false)
  val recordT    = mkCon[AnyRef](Global("Builtin", "Record"), rho ->: star)
  val relationT = mkCon[AnyRef](Global("Builtin", "Relation"), rho ->: star)

  import scalaparsers.Relocatable
  implicit def relocatableType: Relocatable[Type] = new Relocatable[Type] {
    def setLoc(k: Type, l: Loc) = k at l
  }
  implicit def equalType: Equal[Type] = new Equal[Type] {
    def equal(t1:Type,t2:Type): Boolean = (t1,t2) match {
      case (Con(_,n,_,_), Con(_,m,_,_))               => n == m
      case (ConcreteRho(_,n), ConcreteRho(_,m))       => n == m
      case (ProductT(_,n), ProductT(_,m))             => n == m
      case (Arrow(_), Arrow(_))                       => true
      case (AppT(t11,t12), AppT(t21,t22))             => equal(t11,t21) && equal(t12,t22)
      case (VarT(v), VarT(w))                         => v == w
      case (Forall(_,kn,tn,q,t), Forall(_,km,tm,p,s)) => (kn == km) && (tn == tm) && (q === p) && equal(t,s)
      case (Part(_,v,c), Part(_,u,d))                 => equal(v,u) && (c === d)
      case _                                          => false
    }
  }

  implicit def TypeShow: Show[Type] = showA[Type]

  def expandAlias(l: Loc, e: Type, args: List[Type] = List())(implicit su: Supply): AliasExpanded = e match {
    case AppT(a,b)    => expandAlias(l, a, b :: args)
    case Con(_,c,d,k) => d.expandAlias(l, e,args)
    case Memory(i, b) => expandAlias(l, b, args) map (Memory(i, _))
    case _            => Unexpanded(e(args:_*))
  }

  def zipTypes[A](xs: Iterable[A], ks: Iterable[TypeVar]): Map[A,Type] = xs.zip(ks.map(VarT(_):Type)).toMap

  // import HasKindVars._

  implicit def typeHasKindVars: HasKindVars[Type] = new HasKindVars[Type] {
    def vars(t: Type): KindVars = t match {
      case Arrow(_)                => Vars()
      case AppT(e1, e2)            => vars(e1) ++ vars(e2)
      case Con(_, _, _, k)         => kindVars(k)
      case VarT(v)                 => v.extract.vars
      case Forall(_, vs, ts, q, b) => (kindVars(ts) ++ vars(b)) -- vs // deliberately excludes q
      case Exists(_, xs, q)        => kindVars(xs) ++ kindVars(q)
      case Part(_,v,c)             => vars(v) ++ kindVars(c)
      case Memory(_, body)         => vars(body)
      case _                       => Vars()
    }
    def sub(m: PartialFunction[KindVar,Kind], t: Type): Type = t.map(_.subst(m))
  }

  def typeVars[A](a: A)(implicit A:HasTypeVars[A]): Vars[Kind] = A.vars(a)
  def allTypeVars[A](a: A)(implicit A:HasTypeVars[A]): TypeVars = A.allVars(a)
  def ftvs[A](a: A)(implicit A:HasTypeVars[A]):  Traversable[TypeVar] = A.vars(a).filter(_.ty == Free)
  def fskvs[A](a: A)(implicit A:HasTypeVars[A]): Traversable[TypeVar] = A.vars(a).filter(_.ty == Skolem)

  // die, Liskov! die!
  def subType[A](ts: PartialFunction[TypeVar,Type], a: A)(implicit A:HasTypeVars[A]): A = ts match {
    case m : Map[TypeVar,Type] if m.isEmpty => a
    case _ => A.sub(Map(), ts, a)
  }

  def sub[A](ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type], a: A)(implicit A:HasTypeVars[A]): A = (ks,ts) match {
    case (km : Map[KindVar,Kind], tm: Map[TypeVar,Type]) if km.isEmpty && tm.isEmpty => a
    case _ => A.sub(ks, ts, a)
  }

  def conMap(mod: String, cvs: Map[Name, TypeVar], cons: Map[Global, Con]): Map[TypeVar,Type] =
    cvs.collect {
      case (n : Global, vn) if cons.contains(n) =>
        val c = cons(n)
        (vn, c) //  at vn.loc)
      case (n : Local, vn) if cons.contains(n.global(mod)) =>
        val c = cons(n.global(mod))
        (vn, c at vn.loc)
    }

/*
  def replaceCons[A](cvs: Map[Name, TypeVar], cons: Map[Global, Con], a: A)(implicit A: HasTypeVars[A]): A = {
    val map : Map[TypeVar, Type] = cons.collect {
      case (n, c) if cvs.contains(n) =>
        val vn = cvs(n)
        (vn, c at vn.loc)
    }
    A.sub(Map(), map, a)
  }
*/

  // dangerous, may result in unannotated variables
  def dequantify(e: Type): (List[KindVar], List[TypeVar], Type, Type) = e match {
    case Forall(_, ks, ts, q, t) => (ks, ts, q, t)
    case t => (List(), List(), Exists.unit, t)
  }

  implicit def typeHasTypeVars: HasTypeVars[Type] = new HasTypeVars[Type] {
    def vars(t: Type): TypeVars = t match {
      case AppT(e1, e2)        => vars(e1) ++ vars(e2)
      case VarT(v)             => Vars(v)
      case Forall(_,ks,ts,_,b) => vars(b) -- ts
      case Exists(_,xs,qs)     => typeVars(qs) -- xs
      case Part(_, t, ts)      => vars(t) ++ typeVars(ts)
      case Memory(_, body)     => vars(body)
      case _                   => Vars()
    }
    def allVars(t: Type): TypeVars = t match {
      case AppT(e1, e2)         => allVars(e1) ++ allVars(e2)
      case VarT(v)              => Vars(v)
      case Forall(_,ks,ts,cs,b) => allVars(b) ++ allVars(cs) -- ts
      case Exists(_,xs,qs)      => typeVars(qs) -- xs
      case Part(_, t, ts)       => allVars(t) ++ allTypeVars(ts)
      case Memory(_, body)      => vars(body)
      case _                    => Vars()
    }
    def sub(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type], t: Type): Type = t.subst(ks,ts)
  }

  def occursCheckType(v: V[_], e: Type): Boolean = e match {
    case VarT(_)       => false
    case _             => typeVars(e).contains(v)
  }

  object Nullable {
    def unapply(ty: Type) = ty match {
      case AppT(con, t) if con == nullable => Some(t)
      case _                               => None
    }
  }

  val primNumTypes : Map[Type,PrimT] = Map(
    int    -> PrimT.IntT(),
    long   -> PrimT.LongT(),
//    float  -> PrimT.FloatT(),
    double -> PrimT.DoubleT(),
    byte   -> PrimT.ByteT(),
    short  -> PrimT.ShortT()
  )

  val primDateTypes : Map[Type,PrimT] = Map(
    date -> PrimT.DateT(),
    timestamp -> PrimT.TimestampT()
  )

  val primTypes : Map[Type,PrimT] = primNumTypes ++ primDateTypes ++ Map(
    string -> PrimT.StringT(0),
    bool   -> PrimT.BooleanT(),
    uuid   -> PrimT.UuidT()
//    char   -> PrimT.CharT(),
  )
}

abstract class HasTypeVars[A] {
  def vars(a: A): TypeVars
  /** Should include even ambiguous variables */
  def allVars(a: A): TypeVars
  def sub(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar, Type], a: A): A
}

object HasTypeVars {
  implicit def mapHasTypeVars[K,A](implicit A:HasTypeVars[A]): HasTypeVars[Map[K,A]] = new HasTypeVars[Map[K,A]] {
    def vars(xs: Map[K, A]) = xs.foldRight(Vars():TypeVars)((x,ys) => A.vars(x._2) ++ ys)
    def allVars(xs: Map[K, A]) = xs.foldRight(Vars():TypeVars)((x,ys) => A.allVars(x._2) ++ ys)
    def sub(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar,Type], xs: Map[K, A]): Map[K, A] = xs.map(p => (p._1, A.sub(ks, ts, p._2)))
  }

  implicit def listHasTypeVars[A](implicit A:HasTypeVars[A]): HasTypeVars[List[A]] = new HasTypeVars[List[A]] {
    def vars(xs: List[A]) = xs.foldRight(Vars():TypeVars)((x,ys) => A.vars(x) ++ ys)
    def allVars(xs: List[A]) = xs.foldRight(Vars():TypeVars)((x,ys) => A.allVars(x) ++ ys)
    def sub(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar, Type], xs: List[A]): List[A] = xs.map(A.sub(ks, ts, _))
  }

  implicit def vHasTypeVars[K,A](implicit A:HasTypeVars[A]): HasTypeVars[V[A]] = new HasTypeVars[V[A]] {
    def vars(v: V[A]) = A.vars(v.extract)
    def allVars(v: V[A]) = A.allVars(v.extract)
    def sub(ks: PartialFunction[KindVar,Kind], ts: PartialFunction[TypeVar, Type], xs: V[A]): V[A] = xs.map(A.sub(ks, ts, _))
  }
}

/** Item E11a: the CANONICAL FORM of a published constrained scheme, and the
  * ID-FREE keys that define it.
  *
  * The defect (ticket E11, LSP Stage 4 item 7.2's review R-4): four cold checks
  * of ONE unedited module render one and the same constraint set four ways.
  * Nothing about the set moves -- what moves is its FORM.  Every list a
  * published scheme carries is built from a SET, so it comes out in id order:
  * `Subst.generalize`'s `ts = typeVars(t) -- gs` (the universal binders, and
  * `Pretty.ppForall` names them before it prints the body, so the LETTERS
  * follow), `mkSimplified`'s constraint list (through `Exists.apply`'s
  * `p.toSet.toList`), its existential binder list, and a partition's
  * right-hand side.  Two checks of one file draw different ids -- the `Supply`
  * has advanced -- so they order those lists differently.
  *
  * THE RULE, stated so a reader can apply it by hand to a scheme
  * `forall <ts>. (exists <xs>. c1, ..., cn) => body`:
  *
  *   1. Every variable gets a COLOUR that mentions no id.  A variable the BODY
  *      shows is `#i`, `i` its first-occurrence index in a pre-order walk of the
  *      body.  An existential starts at its name (`@n`) or, nameless, at `?`,
  *      and is then REFINED (step 2).
  *   2. A constraint's KEY is its structure serialised with variables by
  *      colour, a concrete row by its labels SORTED BY NAME, a constructor by
  *      its name, and a partition's right-hand side by its members' keys
  *      SORTED.  Refinement: an existential's next colour is the sorted
  *      multiset of the keys of the constraints that mention it, with itself
  *      marked; colours are then re-ranked to their sort position.  Repeat
  *      until the partition of the existentials stops refining (a colour
  *      refinement in the Weisfeiler-Leman sense; four rounds cap it).
  *   3. Each partition's right-hand side is ordered CONCRETE ROW FIRST (labels
  *      by name), then the rest by key.
  *   4. The constraints are ordered by key.
  *   5. The EXISTENTIAL binders are ordered by first occurrence in the ordered
  *      constraints -- which is what assigns their letters.
  *   6. The UNIVERSAL binders are ordered by first occurrence in the BODY, then
  *      in the ordered constraints.
  *
  * Two schemes that differ only in the ids their `Supply` handed out get the
  * same form, because no step reads an id: `.id` appears only as the KEY of a
  * position map or of a colour map, never as a value that is compared or
  * ordered.  Ties survive only between constraints (or right-hand-side members)
  * that the refinement cannot tell apart, and those are isomorphic under the
  * renaming their own order induces -- so they RENDER the same either way,
  * which is what the ticket asks for.  It is not a proof of canonicity: colour
  * refinement is incomplete for graph isomorphism in general, and
  * `ROSE-COMPARISON.md` rank 3 asks for the key to be PROVED invariant.  The
  * measurement that stands in for the proof is the corpus FORM count
  * (`tracker/loopmodel/E11a-CANON.md`).
  *
  * This is a form and not a simplification: no constraint is added, deleted or
  * rewritten, and `new Part` / `new Exists` are used deliberately -- the smart
  * constructors rewrite concrete rows and re-`toSet` the constraint list, which
  * is the very reordering this object exists to remove.  Deleting a redundant
  * constraint is E11b's and needs an entailment oracle.
  *
  * `TolerantCheck.displayScheme` (item 6.2c) applies the SAME rule to a local
  * head after its display filter, so the editor's heads and the published
  * schemes have one canonical form.
  */
object Canonical {
  import Type.typeVars

  /** `publication` (the default) canonicalises the generalisation that
    * publishes a module's top-level signatures and nothing else; `all` also
    * canonicalises the INTERMEDIATE generalisations, whose residuals the
    * inference around them re-instantiates, so their order feeds the solver's
    * queue; `off` restores the pre-E11a form.  The choice is a measurement --
    * see the report's "where it runs". */
  private val mode: String = System.getProperty("ermine.canon", "publication")
  val atPublication: Boolean         = mode != "off"
  val atEveryGeneralisation: Boolean = mode == "all"

  /** the type variables of `t`, in order of FIRST OCCURRENCE (6.2c's, moved
    * here so the editor and the publisher share one definition). */
  def varOrder(t: Type): List[Int] = {
    val acc  = scala.collection.mutable.ListBuffer.empty[Int]
    val seen = scala.collection.mutable.Set.empty[Int]
    def go(x: Type): Unit = x match {
      case VarT(v)               => if (seen.add(v.id)) acc += v.id
      case AppT(f, a)            => go(f); go(a)
      case Forall(_, _, _, q, b) => go(q); go(b)
      case Exists(_, _, cs)      => cs.foreach(go)
      case Part(_, l, r)         => go(l); r.foreach(go)
      case Memory(_, b)          => go(b)
      case _                     => ()
    }
    go(t); acc.toList
  }

  /** a variable's POSITION as a sort key: zero-padded, so `#0009` sorts before
    * `#0011` and the order a reader sees is the order the body introduces. */
  private def pad(p: Int): String = {
    val s = p.toString
    "#" + ("0" * math.max(0, 4 - s.length)) + s
  }

  /** a concrete row's labels, sorted by name -- the same order `Pretty` prints
    * them in since this item. */
  private def labels(fs: Set[Name]): String =
    fs.toList.map(_.toString).sorted.mkString(",")

  /** `t` serialised with every variable replaced by `colour`, and nameless
    * variables the colour map does not cover by their first-occurrence order
    * WITHIN `t`.  No id reaches the string. */
  private def render(t: Type, colour: TypeVar => Option[String]): String = {
    val local = scala.collection.mutable.Map.empty[Int, Int]
    def go(x: Type): String = x match {
      case VarT(v)               => colour(v) getOrElse ("?" + local.getOrElseUpdate(v.id, local.size))
      case ConcreteRho(_, fs)    => "{" + labels(fs) + "}"
      case Con(_, n, _, _)       => "C" + n.toString
      case AppT(f, a)            => "(" + go(f) + " " + go(a) + ")"
      case Forall(_, _, _, q, b) => "F[" + go(q) + "|" + go(b) + "]"
      case Exists(_, _, cs)      => "E[" + cs.map(go).sorted.mkString(",") + "]"
      case Part(_, l, r)         => "P[" + go(l) + "<-" + r.map(go).sorted.mkString(",") + "]"
      case Memory(_, b)          => go(b)
      case other                 => other.toString
    }
    go(t)
  }

  /** 6.2c's key, moved: one constraint serialised with each variable replaced
    * by its position in the BODY's first-occurrence order (`pos`), by its name
    * when the body does not mention it, and by its first-occurrence order
    * within the constraint otherwise.  `TolerantCheck` compares kept sets with
    * it; the ORDERING below uses the refined colours instead.
    *
    * The `ConcreteRho` and `Con` cases are E11a's correction: without them a
    * row fell through to `other.toString`, which prints `fields` -- a
    * `Set[Name]` -- in ITERATION order, so the key that exists to be id-free
    * carried the very label order this item removes. */
  def constraintKey(t: Type, pos: Map[Int, Int]): String =
    render(t, v => pos.get(v.id).map(pad) orElse v.name.map("@" + _.toString))

  /** an id-free colour for every variable of `cs`: `#i` for one the body shows,
    * a refined `?k` for an existential.  See the rule, steps 1-2. */
  private def colours(cs: List[Type], bodyPos: Map[Int, Int]): Map[Int, String] = {
    val fixed: Map[Int, String] = bodyPos.map { case (id, p) => (id, pad(p)) }
    val free = cs.flatMap(c => typeVars(c).toList).distinct.filterNot(v => fixed.contains(v.id))
    if (free.isEmpty) fixed
    else {
      val occ: Map[Int, List[Type]] =
        free.map(v => v.id -> cs.filter(c => typeVars(c).exists(_.id == v.id))).toMap
      var col: Map[Int, String] =
        free.map(v => v.id -> (v.name.map("@" + _.toString) getOrElse "?")).toMap
      var seen  = -1
      var round = 0
      var more  = true
      while (more && round < 4) {
        val all = fixed ++ col
        val raw = free.map { v =>
          val sigs = occ(v.id).map(c =>
            render(c, w => if (w.id == v.id) Some("!") else all.get(w.id))).sorted
          v.id -> (col(v.id) + "|" + sigs.mkString("&"))
        }.toMap
        val rank = raw.values.toList.distinct.sorted.zipWithIndex.toMap
        col = raw.map { case (id, s) => (id, "?" + rank(s)) }
        if (rank.size == seen) more = false
        seen  = rank.size
        round = round + 1
      }
      fixed ++ col
    }
  }

  /** the rule's step 3: a partition's right-hand side, concrete row first. */
  private def orderRhs(t: Type, col: Map[Int, String]): Type = t match {
    case p: Part =>
      new Part(p.loc, p.lhs, p.rhs.sortBy {
        case ConcreteRho(_, fs) => (0, labels(fs))
        case other              => (1, render(other, v => col.get(v.id)))
      })
    case other => other
  }

  /** an ID-FREE FINGERPRINT of a whole scheme: two schemes with equal keys are
    * the same constraint SET over the same body, whatever ids their `Supply`
    * drew and in whatever order the solver left them.  It is the oracle that
    * splits the E11 defect in two: two renderings of one key are a FORM
    * difference (this item's, and 0 after it), two keys are a SET difference
    * (E11b's residual).  Note what it is NOT: an entailment check.  Two
    * different keys can still be two spellings of the same meaning -- that is
    * exactly the redundancy E11b deletes -- so a difference in this key is a
    * difference in the SET, not in what the set says. */
  def key(t: Type): String = t match {
    case Forall(_, ks, _, q, body) =>
      val (_, _, cs0) = Exists.unfurl(q)
      val bodyPos = varOrder(body).zipWithIndex.toMap
      val col     = colours(cs0, bodyPos)
      val cs1     = cs0.sortBy(render(_, v => col.get(v.id)))
      val pos     = (varOrder(body) ++ cs1.flatMap(varOrder)).distinct.zipWithIndex.toMap
      val c       = (v: TypeVar) => pos.get(v.id).map(pad)
      "A[" + ks.length + "|" + render(body, c) + "|" + cs1.map(render(_, c)).sorted.mkString(";") + "]"
    case other => render(other, _ => None)
  }

  /** THE canonical form of a published scheme: the rule, steps 3-6.  Anything
    * that is not a `Forall` is already its own form. */
  /** `dropHints`: an INFERRED scheme's existentials carry the solver's name hints,
    * which differ run to run and made a canonical ORDER still render two ways
    * (review R-1); a lowercase hint is replaced by a positional letter.  A
    * capitalised hint is a class-named constraint variable (`AsOp opl`) and is
    * kept -- stable, and the readable form.  A DECLARED signature's names are
    * the user's and are never touched (`dropHints = false`). */
  def scheme(t: Type, dropHints: Boolean = true): Type = t match {
    case Forall(l, ks, ts, q, body) =>
      val (ql, xs, cs0) = Exists.unfurl(q)
      val bodyPos = varOrder(body).zipWithIndex.toMap
      val col     = colours(cs0, bodyPos)
      /* Refinement leaves a tie exactly between two constraints it cannot tell
       * apart -- an AUTOMORPHISM of the set, two existentials with the same
       * name and the same occurrence profile (`ChartsExample.stackedPair`'s two
       * `AsOp`s).  A tie broken by the incoming list order is broken by ids, and
       * the two orders do NOT render alike, because the binder order that names
       * the letters is fixed by the constraints the tie does not touch.  So:
       * re-sort against the POSITIONS the current order gives the existentials,
       * to a fixpoint.  Each round is a function of the round before, so the
       * result is still id-free; the cap keeps a cycle (never seen on the
       * corpus) from depending on how long we iterate. */
      var cs1 = cs0.map(orderRhs(_, col)).sortBy(render(_, v => col.get(v.id)))
      var settled = false
      var round   = 0
      while (!settled && round < 4) {
        val pos  = (varOrder(body) ++ cs1.flatMap(varOrder)).distinct.zipWithIndex.toMap
        val pcol = (v: TypeVar) => pos.get(v.id).map(pad)
        val next = cs1.map(orderRhs(_, pos.map { case (i, p) => (i, pad(p)) }))
                      .sortBy(render(_, pcol))
        settled = next.map(render(_, pcol)) == cs1.map(render(_, pcol))
        cs1     = next
        round   = round + 1
      }
      val xorder  = cs1.flatMap(varOrder).distinct.zipWithIndex.toMap
      // E11a review R-1: an existential's NAME HINT is the solver's and differs
      // run to run (`Pretty.fresh` prefers a hint over a positional letter), so a
      // stable ORDER still rendered two ways.  Published existentials are nameless
      // and take positional letters; universals keep theirs (a signature's, or the
      // body's).  The user's call, 2026-09-13.
      val nxs     = xs.sortBy(v => xorder.getOrElse(v.id, Int.MaxValue)).map { v =>
        v.name match {
          case Some(Local(n, _)) if dropHints && n.nonEmpty && n.head.isLower => v.copy(name = None)
          case _ => v
        }
      }
      val torder  = (varOrder(body) ++ cs1.flatMap(varOrder)).distinct.zipWithIndex.toMap
      val nts     = ts.sortBy(v => torder.getOrElse(v.id, Int.MaxValue))
      val nq      = if (nxs.isEmpty && cs1.length == 1) cs1.head else new Exists(ql, nxs, cs1)
      Forall(l, ks, nts, nq, body)
    case other => other
  }
}
