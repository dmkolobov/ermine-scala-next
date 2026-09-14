package com.clarifi.reporting
package ermine

import scalaparsers.Document._
import scalaparsers.{Applied, Comonadic, Document, Inferred, Loc, Located, Pos, Supply}

import com.clarifi.reporting.ermine.Relocatable.preserveLoc
import com.clarifi.reporting.ermine.Term.{ termHasTermVars, subTerm, subTermEx, zipTerms, termVars }
import com.clarifi.reporting.ermine.Type.{
  expandAlias, Bad, Expanded, Unexpanded, subType, occursCheckType, zipTypes, typeVars, Con, ftvs, fskvs,
  dequantify, primTypes, Nullable, field, int, byte, short, long, string, char, float, double, date,
  recordT
}
import com.clarifi.reporting.ermine.Kind.{ subKind, occursCheckKind, zipKinds, productKind, kindVars }
import com.clarifi.reporting.ermine.ImplicitBinding.{ implicitBindingComponents }
import com.clarifi.reporting.ermine.syntax.{
  TypeDef, DataStatement, TypeStatement, FieldStatement, ForeignDataStatement, ClassBlock, SigStatement,
  ForeignFunctionStatement, ForeignMethodStatement, ForeignValueStatement, ForeignConstructorStatement, ForeignSubtypeStatement, TableStatement, Module
}
import com.clarifi.reporting.ermine.syntax.TypeDef.typeDefComponents
import com.clarifi.reporting.ermine.Pretty.{ prettyKind, prettyType }
import scala.collection.immutable.List
import scala.collection.mutable.ListBuffer
import scalaz.Scalaz._
import Constraints.{ Partition, RHSConcr, RHS, GenRules, labelClash }
import Constraints.Q.{ PQueue }

/**
 * This module contains most of the type inference and checking machinery.
 *
 * The inference algorithm is a moderately extended version of Daan Liejen's
 * HMF, which itself extends Hindley-Milner inference with support for higher
 * rank polymorphism. By default, ordinary Hindley-Milner types will be
 * inferred, and explicit type annotations may be used to access the first-class
 * polymorphism.
 *
 * Information on HMF is available on Liejen's publicaitons page:
 *   http://research.microsoft.com/en-us/people/daan/pubs.aspx
 * specifically:
 *   http://research.microsoft.com/apps/pubs/default.aspx?id=132621
 *
 * The extensions beyond HMF are for the row types needed to include relational
 * database access within the language. This is handled by collecting constraints
 * on the types during inference, and solving them at the end. Constrained types
 * take the form 'C => t', and row constraints may only occur at the outermost
 * top-level of a type, after initial quantifiers (this invariant is maintained
 * during the inference process).
 *
 * Complications arise in that there is no unique way to write the constraints
 * for many types with regard to number and ordering of variables. For instance:
 *
 *   forall x y z. (z <- (x,y)) => [..x] -> [..y] -> [..z]
 *   forall x y z. (z <- (y,x)) => [..x] -> [..y] -> [..z]
 *   forall v w x y z. (z <- (v,w,y), x <- (v,w)) => [..x] -> [..y] -> [..z]
 *   forall w v x y z. (z <- (w,v,y), x <- (w,v)) => [..x] -> [..y] -> [..z]
 *
 * are all equivalent. The ordering of the variables in the constraint is irrelevant,
 * and we can add partitionings that don't matter and still get a valid type.
 * However, HMF relies on there being a canonical number and ordering of the variables
 * in a quantifier in order to decide if two such types unify. HMF would not detect
 * that the last two types are the same, or that the first two are compatible with
 * the latter two.
 *
 * To rectify this, we note that variables v and w appear nowhere outside the
 * constraints, and that for x, y and z, the rest of the type gives a canonical
 * ordering. Viewing the constraint arrow as implication, we can make use of the
 * fact that:
 *
 *    forall a. (P => Q) = (exists a. P) => Q
 *
 * as long as a is not free in Q, to eliminate the constraint-only variables from the
 * types that HMF must consider. Thus, we consider the latter two types ill-formed,
 * and instead insist that they be written:
 *
 *   forall x y z. (exists v w. (z <- (v,w,y), x <- (v,w))) => [..x] -> [..y] -> [..z]
 *
 * This pushes the difficulty into the constraint solver, and allows HMF to just
 * work for the remaining portion of our types.
 */

trait Requirements {
  // @throws Death on conflict, returns None when there is no such instance
  def reqs(l: Located, p: List[Type]): Option[List[Type]]
  def supers(p: List[Type]): List[Type]
}

/**`
 * The SubstState needs to keep track of the instantiations of type and kind
 * variables over the course of type inference. We maintain the invariant that
 * all the types/kinds in the map are always fully substituted, so we never
 * need to further substitute something that we look up in one of the maps.
 */
class SubstEnv(
  val classes: Map[Global,Requirements] = Map(),
  val defaults: List[Type] = List(int),
  /** The signature-entailment mode for THIS session (S3; `SigEntail.Mode`).  A per-session
    * option rather than a global read-once flag so that one JVM can run a suite's `error`
    * properties beside its `off` ones with no `System.setProperty` (the fixture rule at the
    * top of TestErmine.scala), and so the language server can differ from a batch build.
    * `SessionEnv.sigEntail` is where it comes from; the process default is
    * `-Dermine.sigEntail` (`error`). */
  val sigEntail: SigEntail.Mode = SigEntail.defaultMode
) {
  var kinds:      Map[KindVar, Kind] = Map()
  var types:      Map[TypeVar, Type] = Map()
  var remembered: Map[Int, (Subst.Gamma, Type, Loc)] = Map()
  /** 6.2b (LSP interstage item, tracker/loopmodel/LSP-6.2b-HOOK.md): the type
    * `inferPatternType` minted for each PATTERN binder, keyed by the binder
    * `V`'s def-site `(line, column)` -- the same key
    * `TolerantCheck.Result.locals` uses.  The key carries NO file name; one
    * `SubstEnv` sees exactly one module, and that single-module invariant is
    * what makes the key safe (the 6.2b review's R-9).  EDITOR ONLY: nothing writes it
    * unless `recordBinders` is set, which only
    * `TolerantCheck.checkWith(wantLocals = true)` does, so every strict path
    * (`Session.loadModule`, the REPL, every batch entry) pays one boolean
    * test per guarded site and observes nothing.
    *
    * Kept EAGERLY SUBSTITUTED, exactly as `remembered` is, and for the same
    * reason: `restrictTypes` deletes a pattern meta from `types` at the end
    * of the `Lam` case and of `inferAltTypesPrime`, so a map holding the raw
    * meta and zonked after the component returns an unconstrained variable
    * (the 6.2 review's R-1 refutation, reproduced in the 6.2b report).
    *
    * The `instantiateType` line is on the checker's hottest path and it is
    * MANDATORY there.  Taking it at `restrictTypes` instead -- with only the
    * bindings about to disappear, which looks equivalent and is much cheaper
    * -- was BUILT AND MEASURED, and it is wrong: `generalize` rewrites an
    * entry's metas to the scheme's Bound variables, after which a binding this
    * map never picked up can no longer be applied, and the corpus sweep's
    * split-vs-hook disagreements went 14 -> 251 (6.2b report Sec. 9b). */
  var binderTypes: Map[(Int, Int), Type] = Map()
  /** 6.2c (LSP interstage item, tracker/loopmodel/LSP-6.2c-HEADS.md): the type
    * `inferImplicitBindingTypes` PUBLISHED for each implicit binding head -- the
    * GENERALISED SCHEME, constraints included -- keyed by the head `V`'s def-site
    * `(line, column)`, the same key `binderTypes` and `TolerantCheck.Result.locals`
    * use, and safe for the same reason (one `SubstEnv` sees one module; the 6.2b
    * review's R-9).  EDITOR ONLY: written only under `recordBinders`.
    *
    * WHY IT EXISTS.  A local head's own `V` holds Lower's meta, and
    * `subsumeType(tp, rp)` binds that meta to `rp` -- the UNBOUND, PRE-GENERALISATION
    * rho.  `generalize` then quantifies rp's free metas into the scheme and moves the
    * deferred constraints into its `q`, but it rewrites only the SCHEME: nothing ever
    * binds those metas again, so a zonk of the head's meta returns the rho for ever,
    * one frame behind the type the checker published and with the constraints gone
    * (`let go [] acc = acc / go (h::t) acc = go t (h * acc)` hovered
    * `List a -> a -> a` where the checker held `forall a. Num a => List a -> a -> a`
    * -- ticket E14).  The published scheme is handed out in the substitution map the
    * `Let` case applies to the BODY, so the head has no other way to reach it.
    *
    * Kept eagerly substituted at `instantiateType` ONLY, and deliberately NOT at
    * `unbind`/`generalize` as `binderTypes` is: an entry here is a SCHEME whose
    * quantified variables are `Bound`, and those two rewrites would drag it into
    * whichever instance the body happened to take first.
    *
    * TWO LIMITS, both inherited and both editor-only (6.2c review R-10).  The KIND
    * instantiation four lines up (`instantiateKind`: `hm.types = subKind(s, hm.types)`)
    * rewrites `hm.types` and rewrites neither this map nor `binderTypes`, so a scheme
    * recorded before one of its kind metas is solved keeps the unsolved kind meta --
    * the asymmetry the 6.2b review flagged in its Sec. 1.7.  And the update below is a
    * non-atomic read-modify-write on a shared `SubstEnv`, in a function whose own
    * comment says generalisation runs on several loader threads: unreachable, because
    * `recordBinders` is set only by `checkWith`, which the server drives
    * single-threaded (Decision 3) with a fresh `SubstEnv` per component -- but that
    * argument, and not the code, is what makes it safe. */
  var headTypes: Map[(Int, Int), Type] = Map()
  /** 6.2b: OFF on every strict path.  See `binderTypes` and `headTypes`. */
  var recordBinders: Boolean = false
  def fskvs:      Traversable[TypeVar] = Type.fskvs(types)
  def kindVars:   Traversable[KindVar] = Kind.kindVars(kinds) ++ Kind.kindVars(types)
}

/**
 * Subst is the monad we use to do type inference/checking and unification.
 * It is a basic state+error monad, which allows us to keep track of the
 * variable instantiations we've made for unification, and throw exceptions if
 * we have a type error. Throwing an error will effectively abort the state
 * changes, rolling back the instantiations.
 *
 * Subst also supports actions for creating fresh variables, and when fed with
 * an appropriate supply, is part of maintaining the invariant that each distinct
 * variable should have a globally unique id.
 */

object Subst {
  implicit def substAlias(e: Type)(implicit su: Supply): Type =
    expandAlias(e.loc, e) match {
      case Bad(d) => die(d)
      case Expanded(t) => t
      case Unexpanded(t) => t
    }

  // OMGWTFBBQ. There is no Monoid instance for List[A]?!
  private def rep[A](n: Int)(m: => A): List[A] = {
    val list = new ListBuffer[A]()
    for (i <- 1 to n) list += m
    list.toList
  }

  def lookupType(v: TypeVar)(implicit hm: SubstEnv): Option[Type] = hm.types.get(v)
  def lookupKind(v: KindVar)(implicit hm: SubstEnv): Option[Kind] = hm.kinds.get(v)

  def substKind(e: Kind)(implicit hm: SubstEnv) : Kind = e.subst(hm.kinds)
  def substType(e: Type)(implicit hm: SubstEnv) : Type = e.subst(hm.kinds, hm.types)

/*
  def nf(t: Type)(implicit su: Supply): Type = t.nf(su)
  ...
  def close(t: Type): Type = Subst((st, su, _) => Success(t.close(su), st))
  def close(t: Term): Subst[Term] = Subst((st, su, _) => Success(t.close(su), st))
  def close(b: ImplicitBinding): Subst[ImplicitBinding] = Subst((st, su, _) => Success(b.close(su), st))
  def close(b: ExplicitBinding): Subst[ExplicitBinding] = Subst((st, su, _) => Success(b.close(su), st))
  def close(b: Binding): Subst[Binding] = Subst((st, su, _) => Success(b.close(su), st))
*/

  /*
   * Removes the specified type variables from the instantiation map.
   * In various places, we know that a variable never escapes a certain
   * scope, and it is pointless to keep instantiations for those variables
   * around, so we throw them away to save space.
   */
  def restrictTypes(xs: TraversableOnce[TypeVar])(implicit hm: SubstEnv) = hm.types = hm.types -- xs

  /*
   * See restrictTypes
   */
  def restrictKinds(xs: TraversableOnce[KindVar])(implicit hm: SubstEnv) = hm.kinds = hm.kinds -- xs

  def occursFail(v: V[_], e: Located): Nothing =
    e.die("error: infinite type: variable " + v + " = " + e)

  /*
   * This is the primitive operation underlying the unification implementation.
   * It is important to note that a variable should never be instantiated twice,
   * instantiated to itself, or instantiated to an under-substituted kind/type.
   * This function does, however, keep the types in the map fully substituted
   * in light of the new instantiation.
   */

  def instantiateKind(v: KindVar, e: Kind)(implicit hm: SubstEnv) = hm.kinds.get(v) match {
    case Some(t) => e.die("error: reinstantiated kind: " + v + " to " + e + " but it was already bound to " + t)
    case None =>
      val s = Map(v -> e)
      hm.kinds = subKind(s, hm.kinds) + (v -> e)
      hm.types = subKind(s, hm.types)
  }

  /*
   * See instantiateKind
   */
  def instantiateType(v: TypeVar, e: Type)(implicit hm: SubstEnv): Unit = hm.types.get(v) match {
    // case Some(t) if e == t => warn(e.report("warning: reinstantiated type " + v + " to the same type " + e))
    case Some(t)           => e.die("panic: reinstantiated type " + v + " to " + e + " but it was already bound to " + t)
    case None              =>
      hm.types = subType(Map(v -> e), hm.types) + (v -> e)
      hm.remembered = hm.remembered.map { case (k, (g, t, loc)) => (k, (subType(Map(v -> e), g), subType(Map(v -> e), t), loc)) }
      // 6.2b: the site that makes the hook work at all -- see `SubstEnv.binderTypes`.
      // 6.2c: and the only site that keeps a published head scheme's FREE metas live
      // (`let g x = (x, y)` publishes `forall a. a -> (a, b)` before the body fixes
      // `b` at `Int`) -- see `SubstEnv.headTypes`.  One boolean test on the strict path.
      // 6.2c review R-8: the map is built only when there is something to rewrite,
      // so an editor check with both maps still empty allocates nothing here either.
      if (hm.recordBinders && (hm.binderTypes.nonEmpty || hm.headTypes.nonEmpty)) {
        val sv = Map(v -> e)
        if (hm.binderTypes.nonEmpty) hm.binderTypes = hm.binderTypes.map { case (k, t) => (k, subType(sv, t)) }
        if (hm.headTypes.nonEmpty)   hm.headTypes   = hm.headTypes.map   { case (k, t) => (k, subType(sv, t)) }
      }
  }

  /**
   * This is a higher level interface to the unification machinery than the above
   * instantiate functions. It will appropriately handle unifying a variable with
   * itself, but unifying under-substituted kinds/types _will_ lead to improper
   * instantiations, so it is important to keep values fully substituted during
   * checking.
   *
   * The function returns a fully-substituted version of the unified kind with
   * extra location information.
   */
  def unifyKind(e1: Kind, e2: Kind)(implicit hm: SubstEnv, tyl: Located): Kind = (e1,e2) match {
    case (VarK(u), VarK(v)) if u.id == v.id => e1
    case (VarK(v), e) if v.ty != Skolem =>
      if (occursCheckKind(v, e)) occursFail(v, e)
      else { instantiateKind(v, e); e }
    case (e, VarK(v)) if v.ty != Skolem =>
      if (occursCheckKind(v, e)) occursFail(v, e)
      else { instantiateKind(v, e); e }
    case (ArrowK(l1,c1, t1), ArrowK(l2, c2, t2)) =>
      val c3  = unifyKind(c1, c2)
      ArrowK(l1 unifiedWith l2, c3, unifyKind(substKind(t1), substKind(t2)))
    case _ if (e1 == e2) => e1
    case _ => tyl.die("error: failed to unify kind" :+: prettyKind(e1) :+: "with kind" :+: prettyKind(e2))
  }

  /**
   * See unifyKind
   */
  // probably needs to unify more kinds than we currently do
  def unifyType(e1z: Type, e2z: Type)(implicit hm: SubstEnv, su: Supply, tml: Located): Type = {
    val e1 = substAlias(e1z)
    val e2 = substAlias(e2z)
    (e1, e2) match {
      case (Memory(i, b), t) =>
        val tp = unifyType(b, t)
        val oldr = hm.remembered
        hm.remembered = oldr + (i -> (oldr(i)._1, tp, b.loc))
        tp
      case (t, Memory(i, b)) =>
        val tp = unifyType(t, b)
        val oldr = hm.remembered
        hm.remembered = oldr + (i -> (oldr(i)._1, tp, b.loc))
        tp
      case (VarT(u), VarT(v)) if u.id == v.id => e1
      case (VarT(v), e) if v.ty != Skolem =>
        if (occursCheckType(v, e)) occursFail(v, e)
        else { kindCheck(List(), e, v.extract) ; instantiateType(v, e); e }
      case (e, VarT(v)) if v.ty != Skolem =>
        if (occursCheckType(v, e)) occursFail(v, e)
        else { kindCheck(List(), e, v.extract) ; instantiateType(v, e); e }
      case (AppT(c1, t1), AppT(c2, t2)) =>
        val c3 = unifyType(c1, c2)
        val t3 = unifyType(substType(t1),substType(t2))
        AppT(substType(c3), t3)
      case (Forall(ln,kns,ns,q,nf), Forall(lm,kms,ms,p,mf)) =>
        if (!q.isTrivialConstraint) tml.die("Unable to unify with constraints", e1.toString, e2.report(e2.toString))
        if (!p.isTrivialConstraint) tml.die("Unable to unify with constraints", e2.toString, e1.report(e1.toString))
        if (!(kns.length == kms.length && ns.length == ms.length)) tml.die("Unable to unify with mismatched arity", e1.toString, e2.report(e2.toString))
        val sks = kns.zip(kms).map({ case (n,m) => fresh(n.loc.instantiatedBy(ln unifiedWith lm), n.name.orElse(m.name), Skolem, ()) }).toList
        val skvs = sks.map(VarK(_)).toList
        val nkm = zipKinds(kns,sks)
        val mkm = zipKinds(kms,sks)
        val nsp = subKind(nkm, ns)
        val msp = subKind(mkm, ms)
        val sts = nsp.zip(msp).map({
          case (n,m) =>
            val o = unifyKind(n.extract,m.extract)
            fresh(o.loc.instantiatedBy(ln unifiedWith lm), n.name.orElse(m.name), Skolem, o)
        }).toList
        val ntm = zipTypes(ns,sts)
        val mtm = zipTypes(ms,sts)
        unifyType(subType(ntm, nf), subType(mtm, mf))
        bientail(q,p)

        checkSkolemEscape(sts, List(), None, false)

        Forall(ln unifiedWith lm, kns, ns, substType(q), substType(nf))
      case (p : Exists, q) => tml.die("panic: unifying existential", q.report("note: with this type"))
      case (p, q : Exists) => tml.die("panic: unifying existential", p.report("note: with this type"))
      case _ if (e1 == e2) => e1
      case _ => tml.die("error: failed to unify type" :+: prettyType(e1) :+: "with type" :+: prettyType(e2))
    }
  }

  def checkSkolemEscape(ssz: Traversable[TypeVar], mask: Traversable[TypeVar], ot: Option[Type], suppress: Boolean)(implicit hm: SubstEnv, tml: Located): Unit =
    if (!suppress) {
      val ss = ssz.toSet

      ot match {
        case None => ()
        case Some(t) =>
          val escs = fskvs(t).filter(ss(_))
          if (escs nonEmpty)
            tml.die("error: skolem variables escape:", text("Type would have been:") :/+: prettyType(t, -1))
      }

      val hescs = fskvs(hm.types -- mask).filter(ss(_))
      if (hescs nonEmpty)
        tml.die("error: skolem variables escape in environment", hescs.mkString(", "))
    }

  def unfurlApp(p: Type, args: List[Type] = List()): Option[(Con, List[Type])] = p match {
    case AppT(f,x)      => unfurlApp(f, x::args)
    case c : Con        => Some((c, args))
    case _              => None
  }

  def bySuper(p: Type)(implicit hm: SubstEnv): List[Type] = unfurlApp(p) match {
    case Some((c,args)) => hm.classes.get(c.name) match {
      case None    => c.die("Unknown class")
      case Some(d) => p :: d.supers(args).flatMap(bySuper(_))
    }
    case None => List()
  }

  def byInst(p: Type)(implicit hm: SubstEnv): Option[List[Type]] = unfurlApp(p) match {
    case Some((c,args)) => hm.classes.get(c.name) match {
      case None    => c.die("Unknown class")
      case Some(d) => d.reqs(p.loc, args)
    }
    case None => None
  }

  def entails(ps: List[Type], p: Type)(implicit hm: SubstEnv): Boolean =
    ps.flatMap(bySuper(_)).exists(p == _) || (
      byInst(p) match {
        case None => false
        case Some(qs) => qs.forall { entails(ps,_) }
      }
    )

  def simplifyPredicates(ps0: List[Type])(implicit hm: SubstEnv): List[Type] = {
    def go(rs: List[Type], pss: List[Type]): List[Type] = pss match {
      case List()  => rs
      case p :: ps => if (entails(rs ++ ps, p)) go(rs, ps)
                      else go(p :: rs, ps)
    }
    go(List(), ps0)
  }

  def pnf(p: Type): Boolean = p match {
    case v : VarT  => true
    case AppT(l,_) => pnf(l)
    case c : Con   => false
    case _         => false
  }

  def isPNF(p: Type): Boolean = unfurlApp(p) match {
    case None => false
    case Some((c,args)) => args.forall(pnf(_))
  }

  def toPNFs(ps: List[Type])(implicit hm: SubstEnv, tml: Located): List[Type] =
    ps.flatMap(toPNF(_))

  def toPNF(p: Type)(implicit hm: SubstEnv, tml: Located): List[Type] = byInst(p) match {
    case None =>
      if (isPNF(p)) List(p)
      else tml.die("No instance for " + prettyType(p))
    case Some(ps) => toPNFs(ps)
  }

  def reduce(ps: List[Type])(implicit hm: SubstEnv, tml: Located): List[Type] = {
    val (parts,cs) = ps.partition(_.isInstanceOf[Part])
    parts ++ simplifyPredicates(toPNFs(cs))
  }

  case class Ambiguity(v: TypeVar, preds: List[Type]) {
    def default(implicit hm: SubstEnv): Option[Type] = {
      def simple(p: Type) = unfurlApp(p) match {
        case Some((c,List(VarT(u)))) => u == v
        case _ => false
      }
      if (preds forall simple)
        hm.defaults.filter({ c =>
          preds.forall(p => entails(List(),subType(Map(v -> c), p)))
        }).headOption
      else None
    }
  }

  def ambiguitiesIn(vs: List[TypeVar], ps: List[Type]): List[Ambiguity] =
    vs.map(v => Ambiguity(v, ps.filter(p => typeVars(p).exists(_ == v)))).filter(a => a.preds.nonEmpty)

  def ambiguities(vs: TypeVars, ps: List[Type]): List[Ambiguity] =
    ambiguitiesIn((typeVars(ps) -- vs).toList, ps)

  def defaultSubst(l: Located, ambs: List[Ambiguity])(implicit s: SubstEnv): Map[TypeVar,Type] =
    ambs.map(a => a.default match {
      case Some(d) => a.v -> d
      case None => a.v.die(
        "Unable to resolve ambiguous constraints" :+:
        oxford("and", a.preds.map(prettyType(_)))
      )
    }).toMap

  def split(g: Gamma, gs: TypeVars, ps: List[Type])(implicit hm: SubstEnv, tml: Located): (List[Type],List[Type]) = {
    val fs = typeVars(g)
    val gvs = fs.toSet
    val (ds, rs) = reduce(ps).partition { typeVars(_).forall(gvs) }
    val ambs = ambiguities(fs ++ gs, rs)
    (ds, (rs.toSet -- ambs.flatMap(_.preds)).toList)
  }

  def entail(p: Type, q: Type)(implicit hm: SubstEnv, su: Supply): Unit = {
    val (vs, ps) = unbindExists(Free,p)
    val (us, qs) = unbindExists(Free,q)
    for (q <- qs)
      if (q.isClassConstraint && !entails(ps,q))
        q.die(
          prettyType(q) :+: text("not entailed given known constraints"),
          ps.map(p => p.report("known constraint" :+: prettyType(p))):_*
        )
  }

  def bientail(p: Type, q: Type)(implicit hm: SubstEnv, su: Supply): Unit = {
    entail(p,q)
    entail(q,p)
  }

  /**
   * The matchFun functions assert that the type/kind passed in must be a function
   * space. With free variables and quantifiers, this is not a simple case of
   * pattern matching, so these helper functions will perform the necessary work,
   * and return the quantifier information, domain and codomain of the function
   * space.
   */
  def matchFunKind(ks: KindSchema)(implicit hm: SubstEnv, su: Supply, tyl: Located): (List[KindVar],Kind,Kind) = unbindKindSchema(Free,ks) match {
    case (vs, ArrowK(l, x, y)) => (vs, x, y)
    case (vs, VarK(v)) =>
      val li = v.loc.inferred
      val x = VarK(fresh(li, none, Free, ()))
      val y = VarK(fresh(li, none, Free, ()))
      instantiateKind(v, ArrowK(li, x, y))
      (vs, x, y)
    case _ => tyl.die("Could not match kind" :+: prettyKind(ks.body) :+: "against kind (k1 -> k2)")
  }

  /**
   * See matchFunKind
   */
  def matchFunType(tz: Type)
                  (implicit hm: SubstEnv, su: Supply, tml: Located): (List[KindVar],List[TypeVar],Type,Type,Type) = {
    val t = substAlias(tz)
    def rawMatch(r: Type) = r match {
      case AppT(AppT(Arrow(_), x), y) => (List(), x, y)
      case VarT(v)  =>
        val li = v.loc.inferred
        val x = fresh(li, none, Free, Star(li))
        val y = fresh(li, none, Free, Star(li))
        instantiateType(v, Arrow(li, VarT(x), VarT(y)))
        (List(x,y), VarT(x), VarT(y))
      case _ => tml.die("Could not match type" :+: prettyType(t) :+: "against type (t1 -> t2)")
    }
    unbind(Free,t) match {
      case (ks, ts, q, Memory(i, b)) =>
        val (l, x, y) = rawMatch(b)
        val oldr = hm.remembered
        hm.remembered = oldr + (i -> (oldr(i)._1, Arrow(b.loc)(x,y), b.loc))
        (ks, ts ++ l, q, x, y)
      case (ks, ts, q, b) =>
        val (l, x, y) = rawMatch(b)
        (ks, ts ++ l, q, x, y)
    }
  }

  /**
   * Ensures that the type t has a kind compatible with k.
   * The returned kind incorporates any unifications that happened to k
   * during the process.
   */
  def kindCheck(d: Delta, t: Type, k: Kind)(implicit hm: SubstEnv, su: Supply, tyl: Located): Kind = {
    val tks = inferKind(d, t)
    val (vs, tk) = unbindKindSchema(Free, tks)
    val kp = unifyKind(substKind(k), tk)
    restrictKinds(vs)
    kp
  }

  /**
   * Infers the kind of a given type.
   *
   * The Delta parameter keeps track of what variables may be generalized in
   * the local inference context.
   */
  def inferKind(d: Delta, t: Type)(implicit hm: SubstEnv, su: Supply): KindSchema = {
    val li = t.loc.inferred
    implicit val tyl: Located = t
    t match {
      case VarT(v)          => substKind(v.extract).schema
      case Arrow(_)         => ArrowK(li,Star(li), ArrowK(li, Star(li), Star(li))).schema
      case ProductT(_,n)    => productKind(li,n).schema
      case ConcreteRho(_,_) => Rho(li).schema
      case Part(_,x,ys)     =>
        kindCheck(d, x, Rho(li))
        for (y <- ys) kindCheck(d, substType(y), Rho(li))
        Constraint(li).schema
      case a@AppT(f, x) => a.memoizedKindSchema match {
        case Some(ks) => ks
        case None =>
          val (fvs, i, o) = matchFunKind(inferKind(d, f))
          val (xvs, kx) = unbindKindSchema(Free, inferKind(d, substType(x)))
          unifyKind(substKind(i), kx)
          val op = generalizeKind(substDelta(d), substKind(o)) at li
          restrictKinds(fvs ++ xvs)
          if (op.isClosed) { a.memoizedKindSchema = Some(op); op } else op
      }
      case Exists(l,xs,ts) =>
        val nxs = refreshList(Ambiguous(Skolem), l, xs)
        val kxs = nxs.map(_.extract)
        for (c <- subType(zipTypes(xs,nxs), ts)) kindCheck(kxs ++ d, substType(c), Constraint(li))
        restrictTypes(nxs)
        Constraint(li).schema
      case Forall(l,ks,ts,q,tp) =>
        val km = zipKinds(ks, refreshList(Skolem, l, ks))
        val sts = refreshList(Skolem, l, subKind(km, ts))
        val tks = sts.map(_.extract)
        val tm = zipTypes(ts, sts)
        kindCheck(tks ++ d, tp.subst(km, tm), Star(li))
        kindCheck(tks ++ d, q.subst(km, tm), Constraint(li))
        Star(li).schema
      case Con(_,_,_,s) => s
    }
  }

  /**
   * Checks that e2 subsumes e1. This means that a value of type e2 may be
   * used in any place that a value of type e1 is expected.
   *
   * Due to the way HMF works, this only handles 'one level' of the induced
   * subtyping relation that quantification provides. That is:
   *
   *   (forall a. a) <~ (forall a. a -> a)                 works
   *   ((forall a. a -> a) -> T) <~ ((forall a. a) -> T)   dies
   *
   * where T <~ U means T subsumes U.
   */
  /* S1 of the signature-entailment programme (`tracker/SIG-ENTAIL-PLAN.md`): `sig` names the
   * USER SIGNATURE this call is checking, and is `None` at every caller that is not checking
   * one.  It is an explicit parameter rather than a thread-local precisely because the
   * distinction the check needs is a property of the CALL, not of the dynamic extent: the
   * `App` case (:929-938, the call at :936) subsumes an argument against a function's domain, and an ambient
   * flag set by an enclosing signature check would wrongly claim it.  Under the default
   * (`-Dermine.sigEntail=off`) nothing reads it.  See SIG-1-SURVEY.md's caller table. */
  def subsumeType(e1: Type, e2: Type, sig: Option[SigEntail.Site] = None)(implicit hm: SubstEnv, su: Supply, tml: Located): (Type, Type) = {
    val (sks, sts, qz, r1) = unbind(Skolem, e1)
    val (tks, tts, pz, r2) = unbind(Free, e2)
    val r3 = unifyType(r1, r2)
    val q = substType(qz)
    val (qxs, qs) = unbindExists(Free, q)
    val (pxs, ps) = unbindExists(Free, substType(pz))
    val (ds, rs)  = ps.partition(p => Type.fskvs(p).isEmpty)
    /* THE SIGNATURE-ENTAILMENT CHECK (S3; `SigEntail.enforce`, design `SIG-2-DESIGN.md`
     * (d1)).  `rs` is the body's residual wanteds that mention one of the signature's
     * skolems -- the obligations the loop below computes an answer for and then throws away
     * (`entails` returns a Boolean nobody reads, and is class-only anyway, :313/:394) --
     * and `ds` the skolem-free half, which `enforce` needs because `W` is the closure of
     * `rs` under shared minted variables within `ps` (design (a3)).
     *
     * PLACEMENT.  Here, and only here:
     *   - only for a USER SIGNATURE, i.e. when `sig` is defined: `typeCheck` :658 (`ann`)
     *     and `typeCheckExplicitBinding` :676 (`sig`).  The `App` case (:943) subsumes an
     *     argument against a function's domain and passes `None`; it must keep doing so.
     *   - BEFORE `restrictTypes` (:557-560), which deletes the substitution entries a
     *     wanted still needs and hides the skolems;
     *   - reading the `qs`/`ps` captured at :546-548, never a re-`substType`d copy: that is
     *     what makes "no wanted can mention a given's existential" true (design (a1)), and
     *     it is the invariant S4's editor path must preserve.
     * `:555-556`'s class-only `entails` loop, `mkSimplified` and `ds` are untouched: the
     * check READS and never rewrites. */
    sig.foreach(s => SigEntail.enforce(s, qs, rs, ds, sts, pxs))
    for (r <- rs)
      entails(qs,r)
    restrictTypes(qxs) // ?
    restrictTypes(pxs) // ?
    restrictKinds(tks)
    restrictTypes(tts)
    val skss = sks.toSet
    val stss = sts.toSet
    val escs = hm.fskvs.filter(v => stss.contains(v)) ++ hm.kindVars.filter(skss(_))
    if (escs nonEmpty)
      tml.die(vsep(List(
        text("type t1 did not subsume t2: "),
        text("  t1 :") :+: prettyType(e2,-1),
        text("  t2 :") :+: prettyType(e1,-1),
        e2.report("t1"),
        e1.report("t2")
      )))
    // tml.die("error: escaping Skolem variables: " + escs.mkString(", "), e1.toString, e2.report(e2.toString))
    (q,mkSimplified(pz.loc, pxs, ds))
  }

  /**
   * Peels an existential quantifier off of a type, refreshing the variables quantified
   * to the given VarType, and returning the list of new variables.
   *
   * If the type is not existentially quantified, we may consider it to be wrapped in
   * an existential quantifying zero variables (which should technically never appear,
   * due to our keeping types in a normalized form), and appropriate values are returned.
   */
  def unbindExists(ty: VarType, t: Type)(implicit su: Supply): (List[TypeVar],List[Type]) = t match {
    case Exists(l,xs,qs) =>
      val nxs = refreshList(Ambiguous(ty), l, xs)
      (nxs, subType(zipTypes(xs, nxs), qs))
    case _ => (List(), List(t))
  }

  /**
   * Peels a universal quantifier off a type, similar to unbindExists.
   *
   * The returned values are the refereshed kind and type variables, the constraints,
   * and the freshened type inside the quantifier.
   */
  def unbind(ty: VarType, t: Type)(implicit su: Supply, hm: SubstEnv): (List[KindVar], List[TypeVar], Type, Type) = substAlias(t) match {
    case Memory(i, b) =>
      val (ks, ts, q, bp) = unbind(ty, b)
      (ks, ts, q, Memory(i, bp))
    case Forall(l,ks,ts,q,b) =>
      val nks = refreshList(ty, l, ks)
      val km  = zipKinds(ks, nks)
      val nts = refreshList(ty, l, subKind(km, ts))
      val tm  = zipTypes(ts, nts)
      hm.remembered = hm.remembered map { case (k, (g, t, loc)) => (k, (Type.sub(km, tm, g), t subst (km, tm), loc)) }
      // 6.2b: see `SubstEnv.binderTypes`.
      if (hm.recordBinders && hm.binderTypes.nonEmpty)
        hm.binderTypes = hm.binderTypes map { case (k, t) => (k, t.subst(km, tm)) }
      (nks,nts,q.subst(km,tm),b.subst(km,tm))
    case _ => (List(), List(), Exists(t.loc.inferred), t)
  }

  /**
   * See unbind.
   */
  def unbindKindSchema(ty: VarType, s: KindSchema)(implicit su: Supply): (List[KindVar],Kind) = {
    val nks = refreshList(ty, s.loc, s.forall)
    (nks, s.body.subst(zipKinds(s.forall,nks)))
  }

  /**
   * See unbind.
   */
  def unbindAnnot(g: Gamma, a: Annot)(implicit hm: SubstEnv, su: Supply): (List[KindVar], List[TypeVar],Type) = {
    val nks = refreshList(Free, a.loc, a.eksists)
    val km = zipKinds(a.eksists, nks)
    val nxs = refreshList(Free, a.loc, subKind(km, a.exists))
    val t = a.body.subst(km, zipTypes(a.exists, nxs))
    implicit val loc: Located = a
    kindCheck(delta(g), t, Star(a.loc.inferred))
    (nks, nxs, substType(t))
  }

  /**
   * A Delta is a context for keeping track of which kind variables may be generalized
   * over during a portion of kind checking.
   */
  type Delta = List[Kind]
  def substDelta(g: Delta)(implicit hm: SubstEnv): Delta = g.map(substKind(_)).toList
  def delta(g: Gamma): Delta = kindVars(g).map(VarK(_)).toList

  /**
   * A Gamma is a context for keeping track of which type variables may be generalized
   * over during a portion of type checking. Since types may also contain kinds, this
   * induces a Delta that may be extracted when switching from type checking to kind
   * checking.
   */
  type Gamma = List[TermVar]
  def substGamma(g: Gamma)(implicit hm: SubstEnv): Gamma = g.map(v => v.map(substType(_))).toList

  /**
   * Ensures that a term e has a type compatible with t, in context g.
   * Specifically, t must be subsumed by the inferred type of e.
   */
  def typeCheck(g: Gamma, e: Term, tz: Type)(implicit hm: SubstEnv, su: Supply): Unit = {
    val et = inferType(g, e)
    val t = substType(tz)
    implicit val tml: Located = e
    kindCheck(delta(g), t, Star(e.loc.checked))
    val (q,p) = subsumeType(substType(t), substType(et),
                            if (hm.sigEntail.on) Some(SigEntail.siteAt("ann", e.loc)) else None)
    // TODO: ADD warnings here later if we need to check subsumption involving constraints
    ()
  }

  /**
   * Checks that the given type for an explicit bindings is subsumed by the
   * inferred type, analogously to typeCheck.
   */
  def typeCheckExplicitBinding(g: Gamma, binding: ExplicitBinding)(implicit hm: SubstEnv, su: Supply): Unit = {
    val li = binding.loc.inferred
    implicit val tml: Located = binding
    val (kvs, tvs, ty) = unbindAnnot(g, binding.ty)
    kindCheck(delta(g), ty, Star(li))
    val typ = substType(ty)
    val args = rep(binding.arity) { VarT(fresh[Kind](li, None, Free, Star(li))) }
    val f = inferAltTypes(binding.loc, g, binding.alts, args) { r => args.foldRight(r)(Arrow(li, _, _)) }
    val (q,p) = subsumeType(typ, f,
                            if (hm.sigEntail.on)
                              /* THE SECONDARY LOCATION is the DECLARED TYPE's own (`typ.loc`,
                               * which the renamer built from the signature statement), not
                               * `binding.v.loc` and not `binding.ty.loc`: both of those are the
                               * EQUATION's head (`Lower.pairSigs` builds the `Annot` with the
                               * implicit binding's `loc`, and `:804` below rebuilds it with the
                               * binding's), so on a one-line body the diagnostic's two
                               * locations collapsed onto one line and the second told the
                               * reader nothing (S3 review M1). */
                              Some(SigEntail.siteOf("sig", binding.v, typ.loc))
                            else None)
    restrictKinds(kvs)
    restrictTypes(tvs)
    // _ <- unifyType(binding.ty, v.extract)
    ()
  }

  // we'll need thih-style split and defaulting as well, when we actually add classes

  // data Eq {k} (a : k) (b : k) = Eq (forall p. p a -> p b) -- can we eliminate these explicit kindArgs as we never monomorphize?

  // infer kinds for a mutually recursive block of type defs
  def inferTypeDefKindSchemas(bs: List[TypeDef])(implicit hm: SubstEnv, su: Supply): List[(KindSchema, TypeDef)] = {
    // make up variables for the result kinds
    val rks = bs.map(v => VarK(fresh[Unit](v.loc.inferred, None, Free, ()))).toList
    val bsp = bs.zip(rks).map { case (b,k) => b asRho k }
    val bspp = subType(bsp.map(b => b.v -> VarT(b.v)).toMap, bsp)
    // now that we all agree on variables, lets run inference
    bspp.zip(rks).foreach {
      case (b@DataStatement(l, v, kindArgs, typeArgs, cons), rk) =>
        implicit val tyl: Located = l
        unifyKind(substKind(b rho rk), substKind(v.extract))
        unifyKind(substKind(rk), Star(l.inferred))
        cons.foreach { case (es, _, ts) =>
          for (dd <- ts)
            kindCheck(typeArgs.map(t => substKind(t.extract)) ++ es.map(t => substKind(t.extract)),
              substType(dd), Star(l.inferred))
        }
      case (b@ClassBlock(l, v, kindArgs, typeArgs, ctx, privates, statements), rk) =>
        implicit val tyl: Located = l
        unifyKind(substKind(b rho rk), substKind(v.extract))
        unifyKind(substKind(rk), Constraint(l.inferred))
        statements.foreach {
          case SigStatement(lp,_,tz) => kindCheck(typeArgs.map(t => substKind(t.extract)), substType(tz), Star(lp.inferred))
          case _ => ()
        }
      case (TypeStatement(l, v, kindArgs, typeArgs, body), rk) =>
        val d = typeArgs.map(t => substKind(t.extract))
        val (kvs, k) = unbindKindSchema(Free, inferKind(d, substType(body)))
        implicit val tyl: Located = l
        unifyKind(k, substKind(rk))
        restrictKinds(kvs)
    }

    bspp.map {
      case b =>
        val gk = generalizeKind(Nil, substKind(b.v.extract))
        val typeArgs = b.typeArgs.map { a => a.map(substKind(_)) }
        (gk, b match {
          case DataStatement(l, v, kindArgs, _,        cons) =>
               DataStatement(l, v, kindArgs, typeArgs, cons.map { case (es, v, ts) => (es, v, ts.map(substType(_))) })
          case ClassBlock(l, v, kindArgs, _, ctx, privates, statements) =>
               ClassBlock(l, v, kindArgs, typeArgs, ctx, privates, statements.map {
                 case SigStatement(l,vs,t) => SigStatement(l,vs,substType(t))
                 case t => t
               })
          case TypeStatement(l, v, kindArgs, _, body) =>
               TypeStatement(l, v, kindArgs, typeArgs, substType(body))
        })
    }
  }

  /**
   * Infers the types of a binding group, either top level or local.
   *
   * At this point, the series of bindings has already been split into strongly
   * connected components so as to infer the most general types possible. The
   * procedure we take for this is as follows:
   *
   *   1) (Temporarily) assume given type annotations are correct, and make sure
   *      all variables thus defined are substituted into the other bindings.
   *   2) Infer each of the un-annotated components in topological order, substituting
   *      the inferred and generalized types into subsequent components as appropriate.
   *   3) Check that the explicitly annotated bindings actually have their specified
   *      type, given the inferred types for the implicit bindings.
   *
   * The returned map is for substituting variables with versions carrying a proper
   * type, as inferred by this process.
   *
   * The returned Gamma treats the binding group's type as being in the context,
   * which is appropriate for checking the body of a let.
   */
  def inferBindingGroupTypes(l: Loc,
                             g: Gamma,
                             is: List[ImplicitBinding],
                             es: List[ExplicitBinding],
                             slv: Boolean = false,
                             /* S5.1 follow-up (ticket C12): true ONLY for a MODULE's
                              * top-level binding group -- the one whose generalised types
                              * become the module's published signatures.  A `let`/`where`
                              * group reaches this function too (`inferType`'s `Let` case)
                              * and must stay false: a local scheme is re-instantiated by
                              * the inference around it, so simplifying it reshapes the
                              * enclosing signature.  See `Subst.deleteTautologies`. */
                             publishing: Boolean = false)(implicit hm: SubstEnv, su: Supply): (Gamma, List[Type], Map[TermVar,TermVar]) = {
    val etm = es map {
      case e =>
        val (_, tvs, ty) = unbindAnnot(g, e.ty)
        if (tvs.nonEmpty)
          e.die("panic: Unsupported scoped type variables: " + tvs)
        e.v -> ty
    } toMap
    val em = etm map { case (v, t) => (v, v as t) }
    val esp = es.map(e => e.subst(Map(), Map(), em))
    val isp = is.map(i => i.subst(Map(), Map(), em))
    val (ds, subs) = mapAccum_((List[Type](), Map():Map[TermVar,TermVar]), implicitBindingComponents(isp)) {
       case ((ds0, subs), is) =>
          val (ds,isp) = inferImplicitBindingTypes(l, g ++ toGamma(subs), subTerm(subs,is), slv, publishing)
          (ds ++ ds0, subs ++ isp)
    }
    for (e <- esp) typeCheckExplicitBinding(g, subTerm(subs, e.copy(ty = Annot.plain(e.loc, substType(etm(e.v))))))
    /* E11a: a DECLARED signature is published too, and it reaches the `.ei` through
     * `substType` -- whose `Exists.apply` ends in `p.toSet.toList`, so the constraint
     * list the interface carries is in the hash order of the SUBSTITUTED types, which
     * follows the ids this run drew.  That is the other half of ticket E11's "16 of 249
     * modules render a published type differently on a reuse with no edit": the
     * generalisation above never touches an explicit binding.  Same rule, same place --
     * the module's top-level group, where a signature is made. */
    val el = esp.map({ e =>
      val t = substType(etm(e.v))
      e.v -> e.v.as(if (publishing && Canonical.atPublication) Canonical.scheme(t, dropHints = false) else t)  // declared: the user's names
    }).toList
    is.foreach {
      case ImplicitBinding(_, v, _, Some(i)) =>
        hm.remembered = hm.remembered + (i -> (g, subs(v).extract, l))
      case _ => ()
    }
    (g ++ toGamma(subs), ds, el.toMap ++ subs)
  }

  /**
   * This function infers the types of a single strongly connected component.
   * The proper procedure for this is to infer while avoiding generalizing on
   * _any_ of the types in the binding group, and then generalize all the
   * types so inferred afterward.
   *
   * The returned map is for substituting variables with versions carrying the
   * type we have inferred.
   */
  def inferImplicitBindingTypes(l: Loc,
                                omgz: Gamma,
                                bs: List[ImplicitBinding],
                                slv: Boolean,
                                publishing: Boolean = false)(implicit hm: SubstEnv, su: Supply): (List[Type],Map[TermVar,TermVar]) = {

    val ((g, cs), ts) = mapAccum((omgz ++ bs.map(_.v), List[Type]()), bs) {
      case ((g, cs), b) =>
        val args = rep(b.arity) { VarT(fresh[Kind](b.loc.inferred, None, Free, Star(l))) }
        val r = inferAltTypes(b.loc, g, b.alts, args) {
          tau => args.foldRight(tau) { Arrow(b.loc.inferred, _, _) }
        }
        val tp = substType(b.v.extract)
        val (tks, tts, s, rp) = unbind(Free, r)
        val (_, csp) = unbindExists(Free, s)
        implicit val tml: Located = b
        subsumeType(tp, rp)
        restrictKinds(tks)
        restrictTypes(tts)
        ((substGamma(g), csp ++ cs), substType(tp))
    }
    val omg = substGamma(omgz)
    val gvs = typeVars(omg).toSet
    val (ds, rs) = cs.partition(c => typeVars(c).forall(gvs))
//    for (r <- rs)
//      for (c <- r.rowConstraints)
//        if (typeVars(c).exists(gvs))
//          l.die("Disallowed local row constraints on ambient variables")

    implicit val tml: Located = l
    val csp = if (slv) RowTrace.withSite("inferImplicitBindingTypes")(solve(Exists(l, List(), rs)))
              else Exists(l, List(), rs)
    (ds, bs.zip(ts).map({
      case (b,t) =>
        implicit val tml: Located = b
        /* R3, TRACE-ONLY: name the binding whose signature this `generalize` publishes,
         * for the `ramb` record.  `withBinding` is a no-op unless `-Dermine.rowTrace` is
         * set, and its argument is by-name, so nothing is rendered otherwise. */
        /* S5.1 follow-up (ticket C12): this is the generalisation whose result becomes a
         * binding's signature -- the same call `withBinding` names for the `ramb` record --
         * and `publishing` says whether THIS binding group is the module's top-level one.
         * The tautology deletion fires only when it is.  Every other `generalize`
         * (`inferType`'s let/lambda/annotation cases, `trySolveOn`) and `subsumeType`'s own
         * `mkSimplified` build an INTERMEDIATE scheme that later inference re-instantiates,
         * and deleting there reshapes residuals the deletion was never aimed at -- measured
         * both ways in `S5-HYGIENE.md` "Follow-up: publishing-only deletion".  Threaded as a
         * PARAMETER, never a global: generalisation is re-entrant and runs on several
         * loader threads. */
        val scheme = RowTrace.withBinding(b.v.toString)(
                       generalize(omg, csp, substType(t).forget, publishing))
        // 6.2c: the ONE place an implicit binding head's published type exists.  The
        // map below hands it to the BODY (`inferType`'s `Let` case substitutes it in);
        // the head's own `V` keeps Lower's meta, bound to the pre-generalisation rho,
        // and is what hover read until this record.  `b.v.loc` is the def-site `Pos`
        // Lower gave the head; an `Inferred`/builtin loc is not a def-site and is
        // skipped, exactly as the pattern-binder hook does.  See `SubstEnv.headTypes`.
        if (hm.recordBinders) b.v.loc match {
          case p: Pos => hm.headTypes = hm.headTypes + ((p.line, p.column) -> scheme)
          case _      => ()
        }
        b.v -> b.v.as(scheme)
    }).toMap)
  }

  def toGamma(m: Map[TermVar,TermVar]): Gamma = m.values.toList

  // NB: the inferred type has kind star
  /**
   * A variable's scheme as seen from ONE occurrence of it.  The scheme's constraints were
   * stated where the variable was defined -- a signature in this file, or one in the
   * stdlib -- but instantiating them here makes them obligations of this occurrence, and
   * when the set they join is unsatisfiable it is this occurrence, not the definition,
   * that the user can change.  So the row constraints (and the Exists that carries them)
   * are re-located to the occurrence before they enter the constraint set.  The Forall's
   * own location is kept: "where the type came from" is what the subsumption messages
   * report.  `Part` equality ignores location, so the solver sees the same set either way.
   *
   * Only a source position is worth moving to; a synthesised occurrence (`Loc.builtin`)
   * keeps the definition's location, and `Subst.solve` filters those out of the blame.
   * Follow-up item 1 in tracker/TICKET-editor-and-solver-followups.md.
   */
  /** The position a diagnostic should be REPORTED at.  `Inferred(p)` is the right location
    * to carry -- it records that the constraint was inferred from `p` -- but its `report`
    * appends "inferred from" to the message, which after a reason clause ("...but no part
    * does inferred from") is noise; the messages that use this say why in their own words. */
  def sourcePosition(x: Loc): Loc = x match {
    case Inferred(p) => p
    case _           => x
  }

  def instantiatedAt(at: Loc, t: Type): Type = at match {
    case Pos(_, _, _, _, _) | Inferred(_) => t match {
      case Forall(l, ks, ts, q, b) if q.hasRowConstraints => new Forall(l, ks, ts, relocateConstraints(at, q), b)
      case _                                              => t
    }
    case _ => t
  }

  private def relocateConstraints(at: Loc, q: Type): Type = q match {
    case Exists(_, xs, cs) => new Exists(at, xs, cs.map(relocateConstraints(at, _)))
    case p: Part           => p.at(at)
    case other             => other
  }

  def inferType(g: Gamma, e: Term, suppressEscapes:Boolean = false)(implicit hm: SubstEnv, su: Supply): Type = {
    val li = e.loc.inferred
    implicit val tml: Located = e
    val ty = e match {
      case Var(v)          => instantiatedAt(e.loc, substType(v.extract))
      case Rigid(e)        => inferType(g, e, suppressEscapes)
      case LitInt(_, i)    => int at li
      case LitByte(_, i)   => byte at li
      case LitShort(_, i)  => short at li
      case LitLong(_, l)   => long at li
      case LitString(_, s) => string at li
      case LitChar(_,c)    => char at li
      case LitFloat(_,f)   => float at li
      case LitDouble(_,d)  => double at li
      case LitDate(_,_)    => date at li
      case EmptyRecord(_)   => (recordT at li)(ConcreteRho(li, Set()))
      case Sig(l, x, ann) =>
        val (kvs, bvs,t) = unbindAnnot(g, ann)
        typeCheck(g, x, t)
        val tp = substType(t)
        restrictKinds(kvs)
        restrictTypes(bvs)
        location[Type].mod(_.instantiatedBy(li), tp)
      case Product(_, n) =>
        val vs = rep(n)(fresh(li, none, Free, Star(li)))
        val ts = vs.map(VarT(_):Type)
        Forall(li, List(), vs, Exists(li), ts.foldRight(ProductT(li, n)(ts:_*))(Arrow(li, _, _)))
      case Case(_, e, alts) =>
        val t = inferType(g, e, suppressEscapes)
        inferAltTypes(li, g, alts, List(t), suppressEscapes)(x => x)
      case Let(l, is, es, body) =>
        val (gp,ds,m) = inferBindingGroupTypes(l, g, is, es, true)
        val (ks, ts, c, t) = unbind(Free, inferType(gp, subTerm(m, body), suppressEscapes))
        val r = generalize(substGamma(gp), Exists(c.loc,List(),c :: ds.map(substType(_))), t)
        restrictKinds(ks)
        restrictTypes(ts)
        r
      case App(f, x) =>
        val tf = inferType(g, f, suppressEscapes)
        val (ks, txs, r, i, o) = matchFunType(tf)
        val gp = substGamma(g)
        val tx = inferType(gp, x, suppressEscapes)
        val pp = if (x.isAnnotated) { unifyType(substType(i), tx); Exists(li) }
             else {
               val (q,p) = subsumeType(substType(i), tx)
               if (q.hasRowConstraints) e.die("error: higher rank row constraint in application")
               else p
             }
        val op = generalize(substGamma(gp), substType(r ++ pp), substType(o))
        restrictKinds(ks)
        restrictTypes(txs)
        op
      case Lam(l, p, f) =>
        val pt = inferPatternType(g, p)
        val sigma = pt.extract
        val vsp = refreshList(Free, li, pt.vs)
        val expr = subTerm(zipTerms(pt.vs, vsp),f)
        val tauz = inferType(vsp ++ substGamma(g), expr, suppressEscapes)
        val (ks, ts, q, tau) = if (expr.isAnnotated) (List(),List(),Exists(li), tauz)
                               else unbind(Free,tauz)
        val tanns = pt.xs.map(v => substType(VarT(v))).toList
        val ptanns = tanns.filterNot(_.mono)
        if (ptanns nonEmpty) e.die("error: unannotated parameters used polymorphically")
        val r = generalize(substGamma(g), substType(q), substType(Arrow(li)(sigma, tau)))
        restrictKinds(ks)
        restrictTypes(ts ++ pt.xs)
        // we need to check for skolem escape in case a match introduced them.
        checkSkolemEscape(pt.ss, List(), Some(r), suppressEscapes)
        r
      case Hole(_) =>
        val a = fresh(li, none, Bound, Star(li))
        Forall(li, List(), List(a), Exists(li), VarT(a))
      case Remember(i, e) =>
        val t = inferType(g, e, suppressEscapes)
        hm.remembered = hm.remembered + (i -> (g,t,e.loc))
        Memory(i, t)
    }
    trySolveOn(substGamma(g), ty)
  }

  // gives back a list of term variables bound by the pattern and a list of type variables that were quantified
  case class Patterned[+A](
    extract: A,
    vs: List[TermVar] = List(),
    xks: List[KindVar] = List(),
    ss: List[TypeVar] = List(),
    xs: List[TypeVar] = List(),
    constraints: List[Type] = List()
  ) extends Comonadic[Patterned,A] with Applied[Patterned,A] {
    def self = this
    def lift[B](p: Patterned[B]) = p
    def extend[B](f: Patterned[A] => B) = Patterned(f(this),vs,xks,ss,xs,constraints)
    def map2[B,C](m: => Patterned[B])(f: (A,B) => C): Patterned[C] = Patterned(f(extract,m.extract), vs ++ m.vs, xks ++ m.xks, ss ++ m.ss, xs ++ m.xs, constraints ++ m.constraints)
  }

  def typeCheckPattern(g: Gamma, e: Pattern, tz: Type)(implicit hm: SubstEnv, su: Supply): Patterned[Unit] = {
    val pt = inferPatternType(g, e)
    val t = substType(tz)
    implicit val tml: Located = e
    kindCheck(delta(g), t, Star(e.loc.checked))
    val (q,p) = subsumeType(substType(t), substType(pt.extract))
    pt skip
  }

  def inferPatternTypes(g: Gamma, es: List[Pattern])(implicit hm: SubstEnv, su: Supply): Patterned[List[Type]] = {
    val ps = es.map(p => inferPatternType(g,p)).toList // TODO: this needs to do type substitution into the patterns once we have scoped type variables
    Patterned(ps.map(_.extract), ps.flatMap(_.vs), ps.flatMap(_.xks), ps.flatMap(_.ss), ps.flatMap(_.xs), ps.flatMap(_.constraints))
  }

  def kindChecks(g: Gamma, ts: List[Type], kind: Kind)(implicit hm: SubstEnv, su: Supply): Gamma = ts match {
    case t :: ts =>
      implicit val loc: Located = t
      kindCheck(delta(g), t, kind)
      kindChecks(substGamma(g), ts, kind)
    case _ => g
  }

  def inferAltTypesPrime(
    l: Loc,
    g: Gamma,
    alts: List[Alt],
    ts: List[Type],
    result: Type,
    qs : List[Type] = List(),
    rkinds: List[KindVar] = List(),
    rtypes: List[TypeVar] = List(),
    suppressEscapes: Boolean = false
  )(
    f: Type => Type
  )(
    implicit hm: SubstEnv, su: Supply
  ): Type = alts match {
    case alt :: alts =>
      val pts = inferPatternTypes(g, alt.patterns)
      val li = alt.loc.inferred
      val sigmas = pts.extract
      val freepts = pts.xs.flatMap(v => ftvs(substType(VarT(v))))
      //TODO: Review whether this call was actually necessary:
      //val vsp = refreshList(Free, li, pts.vs)
      val vsp = pts.vs
      val expr = subTerm(zipTerms(pts.vs, vsp), alt.body)
      val tauz = inferType(vsp ++ g, expr, suppressEscapes)
      val (ks, tvs, qz, tau) = if (expr.isAnnotated) (List(),List(),Exists(li), tauz)
                               else unbind(Free,tauz)
      implicit val tml: Located = alt
      val tanns = freepts.map(v => substType(VarT(v))).toList
      val ptanns = tanns.filterNot(_.mono)
      if (ptanns nonEmpty) alt.die("error: unannotated parameters used polymorphically")
      unifyType(substType(result), tau)
      val q = substType(qz)
      ts.zip(sigmas).foreach {
        case (t,sigma) => unifyType(substType(sigma), substType(t)); ()
      }
      checkSkolemEscape(pts.ss, rtypes ++ pts.xs, Some(substType(f(tau))), suppressEscapes)
      inferAltTypesPrime(l, g, alts, ts.map(substType(_)), substType(result), q :: qs, ks ++ rkinds ++ pts.xks, tvs ++ pts.xs ++ rtypes, suppressEscapes)(f)
    case List() =>
      implicit val tml: Located = l
      val r = generalize(substGamma(g), Exists(l.inferred,List(),qs.map(substType(_))), substType(f(result)))
      restrictKinds(rkinds)
      restrictTypes(rtypes)
      r
  }

  // infer the result type of an Alt given the types of what it is matching on
  def inferAltTypes(l: Loc, gz: Gamma, alts: List[Alt], ts: List[Type], suppressEscapes: Boolean=false)(f: Type => Type)(implicit hm: SubstEnv, su: Supply): Type = {
    val g = kindChecks(gz, ts, Star(l.inferred))
    val mess = ts.map(t => unbind(Free, substType(t))).toList
    val a = fresh[Kind](l.inferred, None, Free, Star(l.inferred))
    inferAltTypesPrime(l, g, alts, mess.map(_._4), VarT(a), List(), mess.flatMap(_._1), mess.flatMap(_._2), suppressEscapes) {
      t => Forall(l.inferred, List(), List(), Exists(l.inferred, List(), mess.map(_._3)), f(t))
    }
  }

  // the inferred type has kind star
  def inferPatternType(g: Gamma, e: Pattern)(implicit hm: SubstEnv, su: Supply): Patterned[Type] = {
    val li = e.loc.inferred
    implicit val tml: Located = e
    e match {
      case VarP(v) =>
        val (ks, ts, t) = unbindAnnot(g, v.extract)
        // 6.2b: the ONE place a pattern binder's type exists.  `v.loc` is the
        // def-site `Pos` Lower gave the binder (`Lower.Ctx.binderV`); an
        // `Inferred`/builtin loc is not a def-site and is skipped.
        if (hm.recordBinders) v.loc match {
          case p: Pos => hm.binderTypes = hm.binderTypes + ((p.line, p.column) -> t)
          case _      => ()
        }
        Patterned(t, List(v as t), ks, List(), ts)
      case StrictP(_,p) => inferPatternType(g, p)
      case LazyP(_,p)   => inferPatternType(g, p)
      case WildcardP(_) =>
        val v = fresh[Kind](li, None, Free, Star(li))
        Patterned(extract = VarT(v), xs = List(v))
      case LitIntP(_,i)     => Patterned(int at li)
      case LitByteP(_,i)    => Patterned(byte at li)
      case LitShortP(_,i)   => Patterned(short at li)
      case LitLongP(_,l)    => Patterned(long at li)
      case LitStringP(_, s) => Patterned(string at li)
      case LitCharP(_,c)    => Patterned(char at li)
      case LitFloatP(_,f)   => Patterned(float at li)
      case LitDoubleP(_,d)  => Patterned(double at li)
      case LitDateP(_,d)    => Patterned(date at li)
      case AsP(_,p1,p2) =>
        val pt1 = inferPatternType(g, p1)
        val pt2 = inferPatternType(g, p2)
        val t = substType(pt1.extract)
        unifyType(t, pt2.extract)
        (pt1 >> pt2) as substType(t)
      case ProductP(_,pats) =>
        val pts = inferPatternTypes(g, pats)
        val ts = pts.extract.map(substType(_)).toList
        pts as ProductT(li, ts.length)(ts:_*)
      case ConP(_,con,pats)    =>
        val pts = inferPatternTypes(g, pats)
        val ptau = unfurl(con.extract)
        val (sigmas, tau) = ptau.extract
        if (pts.extract.length != sigmas.length) e.die("error: expected constructor with " + ordinal(pts.extract.length,"argument","arguments"))
        sigmas.zip(pts.extract).foreach {
          case (sigma, pt) => unifyType(substType(pt), substType(sigma))
        }
        (pts >> ptau) as (substType(tau) at li)
    }
  }

  /** **TRACE-ONLY** (stage R3, `tracker/loopmodel/R3-DETERMINED.md`).  Rose's Definition 13
    * closure -- the whole is determined by the parts -- and Ermine's strictly larger closure,
    * which adds CANCELLATION: a part is determined by the whole and the other parts, because
    * the concrete part of a partition is always known.  The Lean statements, the closure
    * properties and the uniqueness theorem that gives them meaning are
    * `tracker/lean/Rowpartition/Determined.lean` (`roseAdd`, `cancelAdd`, `Determined`,
    * `determined_unique`).
    *
    * NOTHING HERE IS CALLED unless `-Dermine.rowTrace` is set: both call sites are inside
    * `if (RowTrace.enabled)`.  It reads a constraint list and returns sets; it draws no ids,
    * touches no `SubstEnv` and builds no `Type`.
    *
    * The Lean model gives every partition a VARIABLE left-hand side, because `PQueue.build`
    * mints one for a concrete row; a published `Part` may still have a `ConcreteRho` on the
    * left, and that is modelled here by `whole = None`, "already known", which is exactly
    * what the Lean carrier constraint `p <- ((|K|))` gives after one step of Rose's clause. */
  object Determinacy {
    /** One partition, read for the closure. */
    final case class P(whole: Option[TypeVar], parts: List[TypeVar], blocked: Boolean)

    private def isConcrete(t: Type): Boolean = t match {
      case ConcreteRho(_, _) => true
      case Con(_, _, _, _)   => true
      case _                 => false
    }

    private def isVar(t: Type): Boolean = t match {
      case VarT(_) => true
      case _       => false
    }

    /** Read the row constraints of a published list.  A right-hand side carrying anything
      * that is neither a variable nor a concrete row is BLOCKED: neither clause may fire
      * through it, which is the conservative reading (`mkSimplified.normalPart` calls the
      * same shape "something we don't know how to deal with"). */
    def read(ps: List[Type]): List[P] = ps.collect { case p: Part => p }.map { p =>
      val vs = p.rhs.collect { case VarT(v) => v }.distinct
      val blocked = p.rhs.exists(t => !isVar(t) && !isConcrete(t))
      p.lhs match {
        case VarT(v)          => P(Some(v), vs, blocked)
        case l if isConcrete(l) => P(None, vs, blocked)
        case _                => P(None, vs, true)
      }
    }

    /** Every row variable the partitions mention. */
    def vars(cs: List[P]): Set[TypeVar] =
      cs.foldLeft(Set[TypeVar]())((acc, p) => acc ++ p.whole.toSet ++ p.parts)

    /** The closure of `u0`: Rose's clause alone (`cancel = false`), or with cancellation. */
    def closure(cs: List[P], u0: Set[TypeVar], cancel: Boolean): Set[TypeVar] = {
      var d = u0
      var changed = true
      while (changed) {
        changed = false
        for (p <- cs if !p.blocked) {
          p.whole match {
            case Some(w) if !d(w) && p.parts.forall(d) => d = d + w; changed = true
            case _                                     => ()
          }
          // `p.whole.forall(d)` is TRUE for a concrete left-hand side: it is known outright.
          if (cancel && p.whole.forall(d))
            for (v <- p.parts if !d(v) && p.parts.forall(x => x == v || d(x))) {
              d = d + v; changed = true
            }
        }
      }
      d
    }

    /** The three side conditions of `Rowpartition.splice_entails_iff`, on the residual `cs`
      * for the variable `v` whose partition carries the concrete part `con`.  A transcription
      * of the `splice` record's own inline block; the corpus measurement checks the two agree
      * on every splice. */
    def conds(cs: List[Type], v: TypeVar, con: Set[Name]): (Boolean, Boolean, Boolean) = {
      def concrOf(t: Type): Set[Name] = t match {
        case ConcreteRho(_, s) => s
        case Con(_, n, _, _)   => Set(n)
        case _                 => Set()
      }
      val hlhs = !cs.exists { case Part(_, VarT(u), _) => u == v ; case _ => false }
      val hdis = cs.forall {
        case Part(_, _, rs) =>
          !rs.exists { case VarT(u) => u == v ; case _ => false } ||
            (rs.flatMap(concrOf).toSet & con).isEmpty
        case _ => true
      }
      val hdup = con.isEmpty || cs.forall {
        case Part(_, _, rs) => rs.count { case VarT(u) => u == v ; case _ => false } < 2
        case _              => true
      }
      (hlhs, hdis, hdup)
    }
  }

  def reduce(lc: Loc,
             csz: List[Type],
             es: List[TypeVar],
             ps: List[Partition])(implicit hm: SubstEnv, su: Supply, tml: Located) =
    ps.foldRight(csz) {
      case (Partition(v, RHSConcr(fs), inf), cs) =>
        RowTrace.log("concr\t" + RowTrace.site + "\t" + RowTrace.clean(lc.toString) +
                     "\t" + v + "\t" + fs.size + "\t" + inf.fold("INPUT")(_.toString))
        instantiateType(v, ConcreteRho(lc, fs))
        cs.map(substType _)
      case (Partition(v, RHS(abs, con), inf), cs) if v.ty.ambiguous || es.contains(v) =>
        /* `Rowpartition.splice_entails_iff` (tracker/lean/Rowpartition/Splice.lean) proves
         * this splice CONSERVATIVE under three side conditions -- `v` heads no constraint
         * of the emitted list, concrete parts disjoint, `v` not repeated in a right-hand
         * side -- and `Splice.DroppedPartition.dropped_can_lose` exhibits a system where
         * dropping the first of them loses a consequence of the input.  Guarding on them
         * was implemented, measured and REMOVED (2026-09-02): the first condition fails on
         * 90% of splices, and skipping those degrades published signatures from resolved
         * concrete rows to constrained polymorphic ones.  The conditions survive as a
         * trace-only diagnostic, computed only when `-Dermine.rowTrace` is set. */
        val csp = cs map {
          case Part(loc, l, rs) => Part(loc, l, rs flatMap {
              case VarT(`v`) => ConcreteRho(lc, con) :: abs.toList.map(VarT(_))
              case x         => List(x)
            }
          )
          case x => x
        }
        RowTrace.log("splice\t" + RowTrace.site + "\t" + RowTrace.clean(lc.toString) +
                     "\t" + v + "\t" + abs.size + "\t" + con.size +
                     "\t" + inf.fold("INPUT")(_.toString) +
                     "\t" + (csp != cs) + {
                       def concrOf(t: Type): Set[Name] = t match {
                         case ConcreteRho(_, s) => s
                         case Con(_, n, _, _)   => Set(n)
                         case _                 => Set()
                       }
                       val hlhs = !cs.exists { case Part(_, VarT(u), _) => u == v ; case _ => false }
                       val hdis = cs.forall {
                         case Part(_, _, rs) =>
                           !rs.exists { case VarT(u) => u == v ; case _ => false } ||
                             (rs.flatMap(concrOf).toSet & con).isEmpty
                         case _ => true
                       }
                       val hdup = con.isEmpty || cs.forall {
                         case Part(_, _, rs) => rs.count { case VarT(u) => u == v ; case _ => false } < 2
                         case _              => true
                       }
                       "\t" + hlhs + "\t" + hdis + "\t" + hdup
                     })
        /* R3 (`tracker/loopmodel/R3-DETERMINED.md`), TRACE-ONLY and a SEPARATE record: the
         * `splice` line above is untouched, so a trace with the `detm` lines filtered out is
         * byte-identical to one taken before this stage.  The two closures are evaluated on
         * `cs` -- the residual this fold has accumulated, which is the system a determinacy
         * guard would consult -- from `U0`, the variables of `cs` that the splice's OWN guard
         * does not count as existential.  Variables of `cs` that occur in no row constraint
         * cannot affect either closure (both clauses quantify over partitions), so reading
         * `U0` off the partitions rather than off `typeVars(cs)` gives the same answer. */
        if (RowTrace.enabled) {
          val dps  = Determinacy.read(cs)
          val dvs  = Determinacy.vars(dps)
          val u0   = dvs.filterNot(u => u.ty.ambiguous || es.contains(u))
          val rose = Determinacy.closure(dps, u0, false)
          val erm  = Determinacy.closure(dps, u0, true)
          val (chlhs, chdis, chdup) = Determinacy.conds(cs, v, con)
          RowTrace.log("detm\t" + RowTrace.site + "\t" + RowTrace.clean(lc.toString) +
                       "\t" + v + "\t" + rose(v) + "\t" + erm(v) +
                       "\t" + chlhs + "\t" + chdis + "\t" + chdup +
                       "\t" + u0.size + "\t" + dvs.size + "\t" + dps.length)
        }
        csp
      case (_, cs) => cs
    }

  def solve(csz: Type)(implicit hm: SubstEnv, su: Supply, tml: Located): Type = {
    val l = csz.loc
    val (es, cs) = unbindExists(Ambiguous(Free), csz)
    /* Trace-only, and the ONLY line of the solver stage L2 adds: the replay records that
     * let the Lean loop model re-run this exact solve (`RowTrace`'s FORMAT block, `sin` /
     * `slbl` / `svar` / `scon`).  It runs HERE because it must see the `Supply` before
     * `PQueue.build` draws from it and the constraint list before `Exists.apply` reorders
     * it.  Inert unless `-Dermine.rowTrace` is set: `solveInput`'s whole body is under
     * `if (enabled)`. */
    RowTrace.solveInput(l.toString, cs, su, hm.types)
    val (q0, esp) = PQueue.build(Exists(l, List(), cs))
    /* S4 (`tracker/loopmodel/S4-CHANGE.md`, ticket B5): the WRITTEN-PARTITION
     * NORMALISATION, `-Dermine.topNormalise`, DEFAULT OFF.  See `GenRules.topNormalise`
     * for the rule, the two side conditions and the soundness argument.
     *
     * WHERE IT RUNS, and why HERE (S4A review G-3).  `solve` has THREE input-reading
     * checks -- `labelCheckEarly`'s unit propagation, `rowSoundDecide`'s COMPLETE
     * per-label decision (default ON since 2026-09-06, with a no-verdict escape on
     * budget exhaustion) and `rowSoundSat` on the closure -- and then the loop.
     * Running the rewrite HERE, before all three, is the only placement on which every
     * one of them and the loop see the SAME live input; running it between two of them
     * would split `q` in two and `Loop/NoFalseAccept.lean`'s `solve_accepted_faithful`,
     * whose premises all mention ONE `q`, would need a bridge lemma before it meant
     * anything.  The subject of that theorem becomes the rewritten system, which is
     * logically EQUIVALENT to the user's -- `S4Top.read_of_top` backwards and
     * `S4Top.ssat_rewrite_fwd` forwards -- so "accepted implies the user's input is
     * satisfiable" transfers through `reads_of_rewrite`.  It is also the placement the
     * model can mirror: `Loop/Seed.lean`'s `solveSeed` applies it at exactly this point,
     * so `looptrace --replay` reproduces it.
     *
     * BLAME IS UNAFFECTED, and that is structural rather than lucky: `rowUnsat` below
     * searches `cs.flatMap(_.rowConstraints)` -- the user's own `Part`s, with their
     * `Loc`s -- and `cs` is not rewritten.  A partition carries no `Loc` at all.  The
     * one case that moves is a refutation blamed on the FRESH carrier, which appears in
     * no `Part`: the search then falls back to the first candidate `Part` mentioning the
     * field, which is still in the user's file.
     *
     * `esp` comes from `PQueue.build` and is untouched. */
    val (q, tnorms) =
      if (!GenRules.topNormalise) (q0, List())
      else Constraints.topNormalise(q0.toList, l) match {
        case (_, Nil)   => (q0, Nil)
        case (ps, recs) => (PQueue(ps), recs)
      }
    if (RowTrace.enabled && tnorms.nonEmpty) {
      val ttag = "\t" + RowTrace.site + "\t" + RowTrace.clean(l.toString) + "\t"
      def tsv(v: TypeVar): String = v.name.fold("")(_.toString) + "^" + v.id
      tnorms.foreach { case (v, c, f) =>
        RowTrace.log("tnorm" + ttag + tsv(v) + "\t" + tsv(c) + "\t(|" +
          f.toList.map(_.toString).sorted.mkString(",") + "|)")
      }
    }
    /* The per-concrete-label refutation, as a thunk, because WHERE it runs is a
     * question in its own right.  It reads `q` -- the INPUT partitions -- and nothing
     * else, so it is independent of `q.expand`; running it first costs nothing and
     * refutes an unsatisfiable input BEFORE the saturation can diverge on it.  That
     * matters: `Rowpartition/ResGuardDiverge.lean` exhibits a four-constraint
     * unsatisfiable system on which resolution has derivations of every length, guarded
     * or not, and the same system is refuted at a single label by this check.  It runs
     * first by default (`GenRules.labelCheckEarly`, adopted 2026-09-02);
     * `-Dermine.labelCheckEarly=false` moves it back after `expand`.  Moving it changes
     * WHICH error a module that fails both ways reports, which is why it spent a day
     * behind a flag: until the blame below pointed at the call site, the label clash was
     * reported at a stdlib signature where `expand`'s error had named the user's line.
     */
    def rowUnsat(lbl: Name, refuted: TypeVar, msg: String): Nothing = {
        // Blame the input constraint the propagation found violated, not the enclosing
        // scope: `tml` is whatever `solve` was called in, which for a module-level
        // binding group is the module header, and `l` is the constraint set's own
        // location, which can be anywhere its constraints came from.
        //
        // The candidates are the input `Part`s mentioning the field whose location is in
        // the file being compiled.  Since `instantiatedAt` moves a scheme's constraints
        // to the occurrence that instantiated them, a constraint reached through a stdlib
        // helper is located at the call site and qualifies; one that still carries a
        // foreign location (a synthesised occurrence) does not, and must not send the
        // user into the stdlib.  Prefer the candidate whose left-hand variable is the
        // refuted partition's; otherwise take the first.  With no candidate at all fall
        // back to `l` if it is in this file, else to `tml`.
        //
        // `Loc` has TWO source-bearing shapes, `Pos` and `Inferred(Pos)`; matching only
        // the first silently disables the search and looks like it works.  The report
        // is made at the underlying position: `Inferred.report` appends "inferred from"
        // to the message, which reads as nonsense after a reason clause.
        def file(x: Loc): Option[String] = x match {
          case Pos(fn, _, _, _, _)           => Some(fn)
          case Inferred(Pos(fn, _, _, _, _)) => Some(fn)
          case _                             => None
        }
        val here = file(tml.loc) orElse file(l)
        val candidates = cs.flatMap(_.rowConstraints).collect {
          case p@Part(ploc, lhs, rhs) if here.isDefined && file(ploc) == here && (lhs :: rhs).exists {
                 case ConcreteRho(_, f) => f contains lbl
                 case _                 => false
               } => p
        }
        val blame = candidates.collectFirst { case Part(ploc, VarT(v), _) if v == refuted => ploc }
          .orElse(candidates.headOption.map(_.loc))
          .getOrElse(if (file(l) == here) l else tml.loc)
        sourcePosition(blame).die("Row partitions are unsatisfiable at field '" + lbl + "': " + msg)
    }
    def checkLabels(source: List[(TypeVar, Constraints.RHS)]): Unit =
      if (GenRules.labelCheck)
        labelClash(source) foreach { case (lbl, refuted, msg) => rowUnsat(lbl, refuted, msg) }

    /* ---------------------------------------------------------------- *
     * S2 (`tracker/loopmodel/S2-DESIGN.md`), layers (ii) and (iii).      *
     * ADOPTED 2026-09-06: both DEFAULT ON.  With `-Dermine.rowSound=false`  *
     * not one line below runs and the solve is the shipped one,           *
     * instruction for instruction.                                        *
     * ---------------------------------------------------------------- */

    /* (iii)'s INPUT.  `solve` does NOT `substType` its constraints before
     * `PQueue.build` (the substitution happens at the `reduce` call below) and
     * `SubstEnv.types` is a long-lived mutable map shared by the whole checker
     * (S1 review Z-6), so `q`'s partitions may mention variables the
     * environment already binds.  Deciding `q` alone would therefore decide a
     * SUB-system: still sound to refute from, but not the property we want to
     * state.  The environment is added as FACTS rather than applied as a
     * substitution -- `v := ((|fs|))` becomes the partition `v <- ((|fs|))`,
     * `v := u` becomes the link `v <- (u)` -- which is equisatisfiable (the
     * environment is idempotent, so the two systems interpret each other) and,
     * unlike rebuilding a queue, draws NO ids from the `Supply`: `PQueue.build`
     * mints a variable for a non-variable left-hand side, and calling it twice
     * would change every id the solve goes on to hand out.
     *
     * A binding that is not row-shaped (not a variable, a `ConcreteRho` or a
     * `Con`) is COUNTED and skipped: the decision then runs on a sub-system, so
     * its refutations stay sound while the completeness half is claimed only
     * for solves with no such binding.  The count is traced (`rsound env`) so
     * that "this never happened on the corpus" is a measurement. */
    def liveInput: (List[(TypeVar, Constraints.RHS)], Int, Int) = {
      val base = q.toList.map(_.tup)
      var seen  = Set[TypeVar]()
      var todo  = base.foldLeft(List[TypeVar]()) { case (acc, (v, Constraints.RHS(a, _))) => v :: a.toList ++ acc }
      var extra = List[(TypeVar, Constraints.RHS)]()
      var facts = 0
      var opaque = 0
      while (todo.nonEmpty) {
        val v = todo.head; todo = todo.tail
        if (!seen(v)) {
          seen = seen + v
          hm.types.get(v) match {
            case None                       => ()
            case Some(VarT(u))              =>
              extra = (v, Constraints.RHS(Set(u), Set())) :: extra; facts += 1; todo = u :: todo
            case Some(ConcreteRho(_, f))    =>
              extra = (v, Constraints.RHS(Set(), f)) :: extra; facts += 1
            case Some(Con(_, nm, _, _))     =>
              extra = (v, Constraints.RHS(Set(), Set(nm))) :: extra; facts += 1
            case Some(_)                    => opaque += 1
          }
        }
      }
      (base ++ extra.reverse, facts, opaque)
    }

    /* (ii) the SAME unit propagation, on the SATURATED set.  Sound by
     * `Rowpartition.refute_saturated_sound`; the flag for it was removed on
     * 2026-09-02 after measuring zero additional refutations on both corpora,
     * which is a fact about the corpora (S1 review section 7.1: it catches
     * 1146 of the 1166 model false acceptances and all six compiler-confirmed
     * seeds).  It is INDEPENDENT of `GenRules.labelCheck`, so that (ii) can be
     * measured on its own. */
    def checkSaturated(source: List[(TypeVar, Constraints.RHS)]): Unit =
      labelClash(source) foreach { case (lbl, refuted, msg) =>
        RowTrace.rowSound("sat", l.toString,
                          lbl.toString + "\t" + refuted.toString + "\t" + RowTrace.clean(msg))
        rowUnsat(lbl, refuted, msg)
      }

    /* (iii) the complete per-label decision on the live input. */
    def decideLabels(): Unit = {
      val t0 = System.nanoTime
      val (source, facts, opaque) = liveInput
      val res = Constraints.labelDecide(source, GenRules.rowSoundBudget,
                                        GenRules.rowSoundSolveBudget)
      val dt  = System.nanoTime - t0
      GenRules.rowSoundNodes.addAndGet(res.nodes)
      var mx = GenRules.rowSoundMaxNanos.get
      while (dt > mx && !GenRules.rowSoundMaxNanos.compareAndSet(mx, dt)) mx = GenRules.rowSoundMaxNanos.get
      if (RowTrace.enabled && (facts > 0 || opaque > 0))
        RowTrace.rowSound("env", l.toString, facts + "\t" + opaque)
      res.verdict match {
        case Constraints.LabelSat =>
          RowTrace.rowSound("ok", l.toString,
            res.labels + "\t" + source.length + "\t" + res.nodes + "\t" + (dt / 1000))
        case Constraints.LabelNoVerdict(lbl, why, exhausted) =>
          if (exhausted) GenRules.rowSoundBudgetHits.incrementAndGet()
          else           GenRules.rowSoundCheckFails.incrementAndGet()
          /* THE ONE CONDITION UNDER WHICH THE THEOREM LAPSES, SAID OUT LOUD
           * (S2 review V-12).  A no-verdict refutes nothing, so the solve
           * proceeds exactly as it would with the flag off -- but it is also
           * the case `S2-DESIGN.md` §2 excludes, and until now the only signals
           * were a counter the compiler never reads and a trace record that
           * needs `-Dermine.rowTrace`.  One line per solve, on stderr, naming
           * the site: enough to notice, cheap enough not to matter, and it
           * cannot fire at the shipped defaults because the whole check is off.
           */
          System.err.println("warning: the row soundness check gave NO VERDICT at " +
            sourcePosition(l).toString + " (field '" + lbl + "': " + why +
            "); this solve is accepted on the shipped rules alone")
          RowTrace.rowSound("budget", l.toString,
            lbl.toString + "\t" + (if (exhausted) "budget" else "checkfail") +
            "\t" + RowTrace.clean(why))
        case Constraints.LabelRefuted(lbl, refuted, why) =>
          RowTrace.rowSound("decide", l.toString,
            lbl.toString + "\t" + refuted.toString + "\t" + res.nodes + "\t" + RowTrace.clean(why))
          rowUnsat(lbl, refuted, why)
      }
    }

    if (GenRules.labelCheckEarly) checkLabels(q.toList.map(_.tup))
    /* AFTER `labelCheckEarly`, so that an input unit propagation already
     * refutes reports exactly the message it reports today and the corpus
     * delta this stage measures is (iii)'s OWN refutations; BEFORE `expand`,
     * because refuting an unsatisfiable input before the saturation can
     * diverge on it is half the point (`Rowpartition/ResGuardDiverge.lean`). */
    if (GenRules.rowSoundDecide) decideLabels()
    /* E11c, the SECOND of the two order reads (`GenRules.solveDet`, DEFAULT OFF).
     * The SATURATED SET comes out of the finger
     * tree in `(rhs.hashCode, lhs.hashCode)` order (`Constraints.scala:499`), which a
     * constant shift of the id base PERMUTES, and `reduce` below folds RIGHT over it
     * splicing into an accumulator later arms read -- so the residual is a function of
     * the base.  Under ON read it in `canonKey` order instead: sorted rhs ids, sorted
     * label keys, lhs id -- an id ORDER, which a constant shift leaves alone. */
    var ps = { val ps0 = q.expand.toList
               if (GenRules.solveDet) ps0.sortWith(Constraints.Q.canonLt) else ps0 }
    if (GenRules.rowSoundSat) checkSaturated(ps.map(_.tup))
    /* Trace-only dump of the POPULATION, not just its counts: the input constraint
     * list as `solve` received it (a `Part`'s right-hand side is a List, so this is
     * the one place its ORDER is still visible), the partitions built from it, and
     * the saturated set with each partition's provenance.  Guarded on `enabled`
     * like every other record here; nothing is built when tracing is off. */
    if (RowTrace.enabled) {
      val tag = "\t" + RowTrace.site + "\t" + RowTrace.clean(l.toString) + "\t"
      def sv(v: TypeVar): String = v.name.fold("")(_.toString) + "^" + v.id
      def st(t: Type): String = t match {
        case VarT(v)           => sv(v)
        case ConcreteRho(_, f) => "(|" + f.toList.map(_.toString).sorted.mkString(",") + "|)"
        case Con(_, n, _, _)   => "(|" + n + "|)"
        case x                 => RowTrace.clean(x.toString)
      }
      def sp(p: Partition): String = p match {
        case Partition(v, RHS(abs, con), inf) =>
          inf.fold("INPUT")(_.toString) + "\t" + sv(v) + "\t" +
            abs.toList.map(sv).sorted.mkString(" ") + "\t" +
            con.toList.map(_.toString).sorted.mkString(",")
      }
      cs.flatMap(_.rowConstraints).zipWithIndex.foreach {
        case (Part(_, lhs, rs), i) =>
          RowTrace.log("in" + tag + i + "\t" + st(lhs) + "\t" + rs.map(st).mkString(" | "))
        case _ => ()
      }
      es.foreach(v => RowTrace.log("ex" + tag + sv(v)))
      q.toList.zipWithIndex.foreach { case (p, i) => RowTrace.log("inpart" + tag + i + "\t" + sp(p)) }
      ps.zipWithIndex.foreach { case (p, i) => RowTrace.log("sat" + tag + i + "\t" + sp(p)) }
    }
    RowTrace.log {
      // The INPUT population: the constraint list solve actually receives, and
      // the partitions built from it, against the SATURATED set it reduces over.
      val inParts = q.toList
      val rows    = cs.flatMap(_.rowConstraints)
      val arities = rows.map { case Part(_, _, rs) => rs.length ; case _ => 0 }
      val concrete = rows.exists {
        case Part(_, lhs, rs) => (lhs :: rs).exists { case ConcreteRho(_, f) => f.nonEmpty ; case _ => false }
        case _ => false
      }
      val derived = ps.filter(_._3.isDefined)
      val byRule  = derived.groupBy(_._3.get.toString).map { case (k, v) => k + ":" + v.length }
                           .toList.sorted.mkString(",")
      "solve\t" + RowTrace.site + "\t" + RowTrace.clean(l.toString) +
        "\t" + rows.length + "\t" + inParts.length + "\t" + ps.length +
        "\t" + derived.length + "\t" + concrete +
        "\t" + arities.sorted.mkString(";") + "\t" + (if (byRule.isEmpty) "-" else byRule)
    }
    // On the INPUT partitions (`q`), not the saturated set (`ps`).
    //
    // CORRECTED 2026-09-01 (ticket item 8a).  This comment used to justify the choice by
    // "propagation is monotone (`Rowpartition.forced_mono`), so the saturated set would be
    // strictly stronger".  That does not follow.  `forced_mono` is monotone in the SYSTEM
    // (`G subset G' -> Forced l G v x -> Forced l G' v x`), and `q.expand` is NOT a
    // superset of `q`: `makeEmpty`, `makeConcrete`, `destructiveSub` and `instantiate` all
    // DELETE partitions and rename variables.  So the saturated set is a different system,
    // not a larger one, and "strictly stronger" is an empirical question rather than a
    // corollary.  (The old comment also blamed rule 6's documented form, which is indeed
    // unsound -- `Rowpartition.Rule6Header.header_not_conservative` -- but `def resolution`
    // never implemented that form; it computes `Rowpartition.rule6`, which is sound.)
    //
    // What running the check on `ps` WOULD need is: input satisfiable => saturated set
    // satisfiable.  For the rule set the default `genRules=cut` runs, that is
    // `Rowpartition.CutRuleSteps.satisfiable_iff`; see the ticket for what it does not
    // yet cover.  Reading the input needs none of that: it depends only on the semantics
    // of the constraints the user wrote, which is what `Rowpartition/LabelProp.lean`
    // proves (`forced_sound`, `refuted_unsat`, `not_refuted_of_sat`).
    //
    // Reading `ps` instead is SOUND -- `Rowpartition.refute_saturated_sound`,
    // tracker/lean/Rowpartition/Saturate.lean -- and was measured on both corpora at ZERO
    // additional refutations, so the flag for it was removed again.  See item 8a.
    if (!GenRules.labelCheckEarly) checkLabels(q.toList.map(_.tup))
    Exists(l, List(), reduce(l, cs map (substType _), es, ps))
  }

  def trySolveOn(g: Gamma, ty: Type)(implicit hm: SubstEnv, su: Supply, tml: Located) = {
    val (ks, uvs, ex, t) = unbind(Free, ty)
    val (_, evs, cs) = Exists.unfurl(ex)
    val fevs = typeVars(cs) -- evs -- uvs
    if(fevs.toSet.isEmpty) {
      val csp = RowTrace.withSite("trySolveOn")(solve(ex.nf))
      generalize(substGamma(g), csp, substType(t))
    } else ty
  }

  // Split a type into the domain and codomain
//  def unfurl(vt: VarType, t: Type)(implicit su: Supply): Patterned[(List[Type], Type)] = t match {
//    case AppT(AppT(Arrow(_), a), b) => unfurl(vt, b) map { case (sigmas, tau) => (a :: sigmas, tau) }
//    case tz : Forall =>
//      val (ks, ts, cs, t) = unbind(vt, tz)
//      val qs = unfurl(vt, t)
//      Patterned((), List(), ks, ts, List(cs)) >> qs
//    case b => Patterned((List(),b))
//  }

  def unfurl(t: Type)(implicit su: Supply): Patterned[(List[Type], Type)] = t match {
    case AppT(AppT(Arrow(_), a), b)    => unfurl(b) map { case (sigmas, tau) => (a :: sigmas, tau) }
    case Forall(loc, ks, ts, cs, body) =>
      val qs = unfurl(body)
      qs.extract match {
        case (sigmas, tau) =>
          val tvs = typeVars(tau)
          val (parms, exts) = ts partition (tvs contains _)
          val rks = refreshList(Free, loc, ks)
          val frvs = refreshList(Free, loc, parms)
          val skvs = refreshList(Skolem, loc, exts)
          val km = (ks zip (rks map VarK)).toMap
          val tm = ((parms zip (frvs map VarT)) ++ (exts zip (skvs map VarT))).toMap
          qs >> Patterned((sigmas map (_ subst (km, tm)), tau subst (km, tm)),
                  List(), rks, skvs, frvs, List(cs subst (km, tm)))
      }
    case b                             => Patterned((List(), b))
  }

  // requires q : Constraint, q quantifies over no variables?, t : Star
  /**
   * This function computes a generalized version of a given type,
   * quantifying over the (truly) free variables in it. The Gamma is used
   * to determine which free variables are actually bound in outer scopes,
   * and should not be quantified over.
   *
   * q2 is expected to be a set of constraints.
   *
   * This will also appropriately handle the splitting of quantified variables
   * into forall for unambiguous variables and exists for variables that appear
   * only in constraints.
   */
  def generalize(g: Gamma, q2: Type, ty: Type, publishing: Boolean = false)(implicit hm: SubstEnv, su: Supply, tml: Located): Type = {
    val (_, _, q1, t) = dequantify(ty)
    val li = t.loc.generalized
    val q = Exists(li, List(), List(q1, q2))
    val ks = (kindVars(t) -- kindVars(g)).filter(_.ty != Skolem).toList
    val gs = typeVars(g).toList
    val ts = (typeVars(t) -- gs).filter(_.ty != Skolem).toList
    val nks = refreshList(Bound, li, ks)
    val km = zipKinds(ks,nks)
    val nts = refreshList(Bound, li, subKind(km, ts))
    val tm = zipTypes(ts,nts)
    val cs = Exists.unfurl(q.subst(km,tm))._3
    val xs = (typeVars(cs) -- nts -- gs).filter(_.ty != Skolem).toList
    val nxs = refreshList(Ambiguous(Bound), li, xs)
    hm.remembered = hm.remembered map { case (k, (g, t, loc)) => (k, (Type.sub(km, tm, g), t.subst(km,tm), loc)) }
    // 6.2b: see `SubstEnv.binderTypes`.
    if (hm.recordBinders && hm.binderTypes.nonEmpty)
      hm.binderTypes = hm.binderTypes map { case (k, t) => (k, t.subst(km, tm)) }
    val scheme = Forall(li,nks,nts, mkSimplified(tml.loc,nxs,subType(zipTypes(xs,nxs),cs),publishing), t.subst(km,tm))
    /* E11a (ticket E11): the canonical FORM.  Every list the scheme above carries came out
     * of a SET -- `ts`, `mkSimplified`'s constraints (through `Exists.apply`'s
     * `p.toSet.toList`), its existentials, a partition's right-hand side -- so its ORDER is
     * the order of the ids the `Supply` handed out, and two checks of one unedited module
     * render one and the same set two ways.  `Canonical.scheme` re-orders those four lists
     * against id-free keys; it adds, deletes and rewrites nothing.  Placed HERE and not in
     * `Pretty` because the `.ei` carries the order too (the interface writer serialises
     * this data), and an editor that agrees with the printer but not with the interface
     * would only move the flicker.
     *
     * `publishing` is the same flag `deleteTautologies` reads: the module's TOP-LEVEL
     * group, the one place a binding's signature is made.  An INTERMEDIATE generalisation
     * is re-instantiated by the inference around it, so its order reaches the solver's
     * queue -- measured both ways, `-Dermine.canon=all` against the default, in
     * `tracker/loopmodel/E11a-CANON.md`. */
    if (if (publishing) Canonical.atPublication else Canonical.atEveryGeneralisation)
      Canonical.scheme(scheme)
    else scheme
  }

  def generalizeKind(d: Delta, k: Kind)(implicit su: Supply): KindSchema = {
    val ks = (kindVars(k) -- kindVars(d)).filter(_.ty != Skolem).toList
    val nks = refreshList(Bound, k.loc, ks)
    KindSchema(k.loc.generalized, nks, subKind(zipKinds(ks,nks), k))
  }

  type Maps = (Map[TypeVar, Type], Map[TermVar, TermVar])
  def subTypeMaps[A:HasTypeVars](m: Maps, a: A): A = subType(preserveLoc(m._1), a)
  def subTermMaps[A:HasTermVars](m: Maps, a: A): A = subTermEx(Map(), preserveLoc(m._1), preserveLoc(m._2), a)
  def appendMaps(p: Maps, q: Maps): Maps = (p._1 ++ q._1, p._2 ++ q._2)

  /**
   * Runs type checking/inference on a module.
   */
  def checkModule(termNames: Map[Name,TermVar], m: Module, cm: Maps)(implicit hm: SubstEnv, su: Supply): Maps = {
    val mod = m.name
    var maps = mapAccum_(cm, m.fields) { checkFieldStatement(mod, termNames) }
    maps = mapAccum_(maps, m.foreignData) { checkForeignData(mod) }
    maps = mapAccum_(maps, typeDefComponents(m.types)) { checkTypeDefComponent(mod) }
    maps = mapAccum_(maps, m.foreigns) {
      (cm, s) => s match {
        case ForeignFunctionStatement(loc, v, ty, _, _) => checkForeignTerm(mod)(cm, v, ty)
        case ForeignMethodStatement(loc, v, ty, _)      => checkForeignTerm(mod)(cm, v, ty)
        case ForeignValueStatement(loc, v, ty, _, _)    => checkForeignTerm(mod)(cm, v, ty)
        case ForeignConstructorStatement(loc, v, ty)    => checkForeignTerm(mod)(cm, v, ty)
        case ForeignSubtypeStatement(loc, v, ty)        => checkForeignTerm(mod)(cm, v, ty)
      }
    }
    maps = mapAccum_(maps, m.tables) {
      case (cm, TableStatement(loc, db, vs, ty)) => mapAccum_(cm, vs.map(_._2)) { checkForeignTerm(mod)(_, _, ty) }
    }

    val is = subTermMaps(maps, m.implicits).map(_.close)
    val es = subTermMaps(maps, m.explicits).map(_.close)
    val bs : List[Binding] = is ++ es

    assertTermClosed(bs, maps._2.keySet ++ bs.map(_.v))
    assertTypeClosed(bs)

    // the two booleans are `slv` and, S5.1, `publishing`: this is a MODULE's top-level
    // binding group, so the C12 tautology deletion runs on what it generalises.
    val (_, ds, terms) = inferBindingGroupTypes(m.loc, Nil, is, es, true, true)
    for (d <- ds)
      if (!d.isTrivialConstraint)
        d.die("non-trivial deferred constraint in top level binding")


    val mp = m.subTerm(terms)
    val pts = mp.privateTerms

    val buf = new ListBuffer[(TermVar,TermVar)]()
    terms.foreach {
      case (k,v) if pts.contains(v) => ()
      case (k,v)                    => buf += (v -> v.copy(name = Some(global(mp.name, v))))
    }
    (maps._1, maps._2 ++ buf.toMap)
  }

  def checkTypeDefComponent(module: String)(cm: Maps, tds: List[TypeDef])(implicit hm: SubstEnv, su: Supply): Maps = {
    val dvs = tds.map(_.v)
    val tdsp = subTypeMaps(cm, tds).map(_.closeWith(dvs))
    tdsp.foreach(assertTypeClosed(_))
    val ktds = inferTypeDefKindSchemas(tdsp)
    var conMap: Map[TypeVar, Type] = null
    val cons = ktds map {
      case (ks, DataStatement(l, v, kindArgs, typeArgs, cons)) =>
        v -> Con(l, global(module, v), new ConDecl { def desc = "data" }, ks)
      case (ks, TypeStatement(l, v, kindArgs, typeArgs, body)) =>
        v -> Con(l, global(module, v), new TypeAliasDecl(kindArgs, typeArgs, { subType(preserveLoc(conMap - v), body) }), ks)
      case (ks, ClassBlock(l, v, kindArgs, typeArgs, ctx, privates, body)) =>
        v -> Con(l, global(module, v), new ConDecl { def desc = "class" }, ks)
    }
    conMap = cons.toMap
    mapAccum_((cm._1 ++ conMap, cm._2), ktds.zip(cons)) {
      case (s, ((_, DataStatement(l, v, kindArgs, typeArgs, cons)), (_, con))) =>
        (s._1, s._2 ++ cons.map {
          case (es, v, fields) =>
            val g = global(module, v)
            v -> fresh(v.loc, Some(g), Bound,
                  Forall.mk(v.loc.inferred,
                            con.schema.forall,
                            typeArgs ++ es,
                            Exists(v.loc.inferred),
                            subTypeMaps(s,fields).foldRight(con(typeArgs.map(VarT(_)):_*))((x, y) =>
                              Arrow(v.loc.inferred,x,y))))
        })
      case (s, _) => s
    }
  }

  def checkFieldStatement(module: String, termNames: Map[Name,TermVar])(cm: Maps, fs: FieldStatement)(implicit hm: SubstEnv, su: Supply): Maps = {
    val ty = subTypeMaps(cm, fs.ty)
    val otyp = ty match { case Nullable(typ) => primTypes.get(typ) map (_.withNull) ; case _ => primTypes.get(ty) }
    if (!otyp.isDefined) ty.die(text("Invalid field type:") :+: text(ty.toString))
    val maps = fs.vs.map { case v =>
      val name = global(module, v)
      val tyCon = Con(v.loc.inferred, name, FieldConDecl(ty), Field(v.loc.inferred).schema)
      val tmv = fresh(v.loc, Some(tyCon.name), Bound, field(tyCon, ty))
      termNames.get(v.name.get) match {
        case None    => (Map(v -> tyCon), Map() : Map[TermVar,TermVar])
        case Some(u) => (Map(v -> tyCon), Map(u -> tmv))
      }
    }
    maps.foldLeft(cm)(appendMaps)
  }

  // @throws Death
  def assertTermClosed[A:HasTermVars](t: A, ex: Set[TermVar] = Set()): Unit = {
    val ftmvs = termVars(t) -- ex
    if (ftmvs nonEmpty) die(vsep(ftmvs.map(v => v.report("error: undefined term")).toList))
  }

  // @throws Death
  def assertTypeClosed[A:HasTypeVars](t: A, ex: Set[TypeVar] = Set()): Unit = {
    val ftvs = typeVars(t) -- ex
    if (ftvs nonEmpty) die(vsep(ftvs.map(v => v.report("error: undefined type")).toList))
  }

  // @throws Death
  def assertKindClosed[A:HasKindVars](t: A, ex: Set[KindVar] = Set()): Unit = {
    val fkvs = implicitly[HasKindVars[A]].vars(t) -- ex
    if (fkvs nonEmpty) die(vsep(fkvs.map(v => v.report("error: undefined kind")).toList))
  }

  // @throws Death
  def checkForeignTerm(module: String)(cm: Maps, v: TermVar, t: Type)(implicit hm: SubstEnv, su: Supply): Maps = {
    val ty = subTypeMaps(cm, t).close
    implicit val loc: Located = ty
    kindCheck(Nil, ty, Star(ty.loc.inferred))
    val typ = substType(ty)
    assertTypeClosed(typ)
    (cm._1, cm._2 + (v -> fresh(v.loc, Some(global(module, v)), Bound, typ)))
  }

  // @throws Death
  def checkForeignData(module: String)(cm: Maps, fds: ForeignDataStatement): Maps = fds match {
    case ForeignDataStatement(loc, v, vs, clazz) =>
      val k = vs.foldRight(Star(loc.inferred) : Kind)((u, r) => ArrowK(loc.inferred, u.extract, r))
      // mirrors Session.processForeignDataStatement: a tolerated `foreign
      // data` keeps the name of the class it could not resolve (LSP-FFI)
      val decl = clazz.failure match {
        case Some(f) => TypeConDecl(clazz.cls, true, Some(f.className))
        case None    => TypeConDecl(clazz.cls, true)
      }
      val c = Con(loc, global(module, v), decl, k.schema)
      (cm._1 + (v -> c), cm._2)
  }

  // @throws Death
  def global(m: String, v: V[Any]): Global = v.name match {
    case Some(l : Local)                   => l global m
    case Some(g : Global) if g.module == m => g
    case _                                 => v.die("error: expected local name")
  }

  /*
   * Simplifies a constraint set to eliminate superfluous constra.
   * Uses the following heuristics:
   *
   * 1) Eliminate all but one permutation of a right hand side for
   *    partitions of a given variable. I.E.:
   *
   *      x <- Foo, y, Bar
   *      x <- Bar, Foo, y
   *
   * 2) Rules about existential variables are only useful inasmuch as
   *    they provide information about universal variables, so any
   *    rules that aren't transitively related to universal variables
   *    should be eliminated.
   *
   *      forall a. (exists w x y z. a <- (Foo,w), x <- (Bar,y), z <- (Bar,w)). ...
   *
   *    can be simplified to:
   *
   *      forall a. (exists w z. a <- (Foo,w), z <- (Bar, w)). ...
   */
  private case class NormalPart(loc: Loc, left: TypeVar, concrete: Set[Name], abstrakt: List[TypeVar]) {
    override def equals(a: Any) = a match {
      case NormalPart(_, l, c, a) => l == left && c == concrete && a.sortWith(_.id < _.id) == abstrakt.sortWith(_.id < _.id)
      case _ => false
    }
    // MUST agree with `equals` above, which ignores `loc` and compares `abstrakt` SORTED:
    // `List.distinct` buckets by `hashCode` and only compares within a bucket, so the
    // synthesised case-class hashCode (which hashes `loc`, and hashes `abstrakt` in ORDER)
    // sent two permuted copies of one constraint to different buckets and published both.
    // `V.hashCode` is `id.hashCode`, so hashing the ids is hashing the variables.
    override def hashCode: Int = (left.id, concrete, abstrakt.map(_.id).sorted).hashCode
    def part: Type = Part(loc, VarT(left), ConcreteRho(loc, concrete) :: abstrakt.map(VarT(_)))
  }

  /** S5.1 (ticket C12): the shape `r <- (t1, .., tk)` with `k >= 1`, no concrete part,
    * and every `ti` a DISTINCT bare variable.  `None` for anything else, and none of
    * those exclusions is decoration:
    *   - a CONCRETE part leaves `Foo` in the left-hand row, which is a condition on a
    *     row the caller fixes -- refuted in Lean as
    *     `DeadUndetermined.undetermined_not_deletable`;
    *   - `k = 0` says the left-hand row IS empty -- refuted as
    *     `TautoEmpty.tauto_empty_not_deletable`;
    *   - a REPEATED part is NOT the theorem's shape at all and must be rejected here
    *     rather than by the theorem: `mk r P {}` takes a `Finset`, so Lean's `{t, t}`
    *     IS `{t}`, whereas the surface constraint `r <- (t, t)` asserts `t` disjoint
    *     from itself, forcing `t` and hence `r` empty.  (The solver's own `RHS.build`
    *     collapses a repeat the same way `LoopRel.dedup` does, so this shape should
    *     not reach a published residual; it is excluded because it MUST be, not
    *     because it is expected.) */
  private def freshSplitShape(t: Type): Option[(TypeVar, List[TypeVar])] = t match {
    case Part(_, VarT(r), rs) =>
      val vs = rs.collect { case VarT(v) => v }
      val emptyConc = rs.count { case ConcreteRho(_, s) => s.isEmpty case _ => false }
      if (vs.length + emptyConc == rs.length && vs.nonEmpty &&
          vs.distinct.length == vs.length) Some((r, vs))
      else None
    case _ => None
  }

  /** S5.1 (ticket C12): delete a published partition that says nothing, and the
    * existentials it alone binds.
    *
    * THE THEOREM.  `Rowpartition/Determined.lean`'s `tauto_delete`:
    * `REquiv <ex U P, insert (mk r P {}) G> <ex, G>` when `P` is non-empty, `r` is not
    * in `P`, and every `p` in `P` occurs in no constraint of `G`.  Read on a signature:
    * the left-hand side is a row the CALLER fixes, the parts are all existential,
    * pairwise distinct, carry no concrete label and occur in no other published
    * constraint -- so every caller discharges it by taking one part to be the whole row
    * and the rest empty, and the qualification constrains nobody.  R3's
    * `dead_delete_of_pairwise` / `_le_one_part` are the MIRROR IMAGE (the dead
    * existential is the LEFT-hand side there) and do not cover this; that is
    * `R3-REVIEW.md` M-3, and it is why C12 waited for a theorem.
    *
    * This is the sibling of `normalPart`'s `a <- (a)` case (stage S3) and of the
    * `(|Foo|) <- (|Foo|)` case beside it.  It cannot live there: its side condition is
    * about the WHOLE published constraint set, not about one constraint.
    *
    * NARROWER than the theorem in three places (S5 review §1.5).  (i) The theorem allows
    * any `r` outside `P`, including an existential one -- `tauto_delete_no_hr` even drops
    * `r ∉ P` altogether; this requires `r` NOT to be a published existential, so the
    * deletion can never leave a binder bound by the `exists` and mentioned nowhere, and
    * `r ∉ P` follows from `!ex(r) && vs.forall(ex)`.  (ii) `occ` is computed over the
    * WHOLE published list, CLASS constraints included, so a part shared with a class
    * constraint blocks the deletion; the theorem's `allVars G` only knows about row
    * constraints.  (iii) Two candidates that share a part delete neither, for the same
    * reason: each is the other's "other constraint".
    *
    * WHY DELETING SEVERAL AT ONCE IS STILL THE THEOREM (S5 review Q-5).  `tauto_delete`
    * removes ONE constraint; `dead` may hold several.  The licence is the theorem
    * ITERATED, and the `occ` test is what makes the iteration legitimate: a surviving
    * candidate's parts occur in no other published constraint, so in particular not in
    * another candidate and not as another candidate's left-hand side, and its own
    * left-hand side is not a published existential.  So distinct candidates have disjoint
    * part sets and deleting one leaves every other still satisfying the side condition
    * against the smaller system.  The corresponding Lean statement (the iterated form) is
    * not written; it is noted as ticket work in `S5-REVIEW.md` Q-5 for the canonical-
    * residual programme, which is where it would first be leaned on.
    *
    * `-Dermine.tautoDelete`, DEFAULT ON since 2026-09-09 (`GenRules.tautoDelete` carries
    * the evidence).  It runs ONLY from the generalisation that publishes a MODULE's
    * signatures (`inferBindingGroupTypes`'s `publishing`), and that restriction is what
    * confines it: measured, single build, flag A/B over 268 interfaces / 3,481 published
    * bindings, exactly FOUR bindings move -- `Layout.Scan`'s `count`, `count'`, `sumBy`
    * and `avgBy'`, the signatures ticket C12 names -- and with the interface-key header
    * stripped exactly ONE file of 268 differs, on four lines.  Corpus verdicts and
    * messages unchanged; `boot` and `Wide` row traces byte-identical to the pre-change
    * compiler.  `tracker/loopmodel/S5-HYGIENE.md`, "Follow-up: publishing-only deletion". */
  private def deleteTautologies(ps: List[Type], pubExts: List[TypeVar])
      : (List[Type], List[TypeVar]) = {
    val ex = pubExts.toSet
    if (!GenRules.tautoDelete || ex.isEmpty) (ps, pubExts)
    else {
      val ixd = ps.zipWithIndex
      val cands = ixd.flatMap { case (p, i) =>
        freshSplitShape(p).filter { case (r, vs) => !ex(r) && vs.forall(ex) }
                          .map { case (_, vs) => (i, vs.toSet) }
      }
      if (cands.isEmpty) (ps, pubExts)
      else {
        val occ = ixd.map { case (p, i) => (i, typeVars(p).toSet) }
        val dead = cands.filter { case (i, vs) =>
          occ.forall { case (j, tvs) => j == i || (tvs & vs).isEmpty }
        }
        if (dead.isEmpty) (ps, pubExts)
        else {
          val di = dead.map(_._1).toSet
          val dv = dead.flatMap(_._2).toSet
          (ixd.filterNot { case (_, i) => di(i) }.map(_._1), pubExts.filterNot(dv))
        }
      }
    }
  }

  def mkSimplified(l: Loc, exts: List[TypeVar], ps: List[Type], publishing: Boolean = false)(implicit hm: SubstEnv, su: Supply, tml: Located): Type = {
    def isolated(acc: Set[TypeVar], parts: List[Type]): Set[TypeVar] = {
      val dirty = parts.foldLeft(Set[TypeVar]()) {
        case (d,p) =>
          val pvs = typeVars(p).toSet
          val dvs = pvs -- acc
          if(dvs.isEmpty) d else d ++ pvs.intersect(acc)
      }

      if(dirty.isEmpty) acc else isolated(acc -- dirty, parts)
    }
    def normalPart(t: Type): Option[Either[NormalPart,Type]] = t match {
      case p@Part(loc, l, rs) =>
        val (cs,vs,ts) = rs.foldLeft((Set[Name](),List[TypeVar](),List[Type]())) {
          case ((cs, vs, ts), VarT(v))           => (cs, v :: vs, ts)
          case ((cs, vs, ts), ConcreteRho(_, s)) =>
            val i = cs.intersect(s)
            if(i.nonEmpty)
              // at the constraint, not at its left-hand variable: the variable's location
              // is wherever the signature declared it, which for a stdlib helper's
              // constraint is the stdlib; the constraint's is the occurrence that
              // instantiated it (`instantiatedAt`)
              sourcePosition(loc).die("Fields appear twice in row: " + i.mkString(","))
            else (cs ++ s, vs, ts)
          case ((cs, vs, ts), c@Con(_, n, _, _)) => (cs + n, vs, ts)
          case ((cs, vs, ts), t)                 => (cs, vs, t :: ts)
        }
        if(!ts.isEmpty) Some(Right(p)) // There's something we don't know how to deal with
        else l match {
          case ConcreteRho(loc, s) =>
            if(vs.isEmpty && cs == s) None
            else if(cs.isEmpty && vs.length == 1) Some(Left(NormalPart(loc, vs.head, s, List())))
            else Some(Right(p))
          case VarT(v) =>
            // `a <- (a)` is an identity, not a condition: the sibling of the ConcreteRho
            // case just above, which already deletes `(|Foo|) <- (|Foo|)`.  It is true of
            // every row, so deleting it cannot weaken the published residual.
            if(cs.isEmpty && vs == List(v)) None
            else Some(Left(NormalPart(loc, v, cs, vs)))
          case _ => Some(Right(p))
        }
      case p => Some(Right(p))
    }
    val iso = isolated(exts.toSet, ps)
    val (classes, parts) = ps.partition(_.isClassConstraint)
    val (unknown, normal) = parts.map(normalPart).collect({ case Some(p) => p }).partition(_.isRight)
    val (dumb, extinct) = (normal.distinct.map(_.left.get.part) ++ unknown.map(_.right.get)).partition {
      p => (typeVars(p).toSet -- iso).nonEmpty
    }
    // solve constraints before throwing them away to ensure failure for unsatisfiable sets
    RowTrace.withSite("mkSimplified-extinct")(solve(Exists(l, List(), extinct)))
    val complex = reduce(classes)
    val am = ambiguitiesIn(exts, complex).map(_.v).toSet
    val lessComplex = complex.filterNot(p => typeVars(p).exists(am))
    val pruned = lessComplex ++ dumb
    val pubExts = exts filterNot (v => iso(v) || am(v))
    /* R3 (`tracker/loopmodel/R3-DETERMINED.md`), TRACE-ONLY: the ROW-AMBIGUITY criterion --
     * Rose's Definition 14 read through Definition 13 -- on the signature this call is about
     * to publish.  `ambiguitiesIn` above runs on the CLASS constraints only (`complex`); the
     * row parts (`dumb`) reach `pruned` without passing through it, and this record is the
     * measurement of what a criterion for them would say.  It changes nothing: `pubExts` is
     * the same list the `Exists` below always bound.
     *
     * `U0` is the variables the row constraints mention that are NOT published existentials.
     * That is exactly `fv(tau) ∪ universals` as far as the closure can tell, because a
     * variable of `tau` occurring in no constraint can never be used by either clause. */
    if (RowTrace.enabled) {
      val dps = Determinacy.read(pruned)
      if (dps.nonEmpty) {
        val dvs   = Determinacy.vars(dps)
        val exset = pubExts.toSet
        val u0    = dvs.filterNot(exset)
        val rose  = Determinacy.closure(dps, u0, false)
        val erm   = Determinacy.closure(dps, u0, true)
        val rowEx = pubExts.filter(dvs)
        val rU    = rowEx.filterNot(rose)
        val eU    = rowEx.filterNot(erm)
        RowTrace.log("ramb\t" + RowTrace.site + "\t" + RowTrace.clean(l.toString) +
                     "\t" + RowTrace.clean(RowTrace.binding) +
                     "\t" + pubExts.length + "\t" + rowEx.length +
                     "\t" + rU.length + "\t" + eU.length + "\t" + dps.length +
                     "\t" + rU.map(_.toString).sorted.mkString(" ") +
                     "\t" + eU.map(_.toString).sorted.mkString(" "))
      }
    }
    /* S5.1, ticket C12: the tautology deletion runs HERE, after the `ramb` record and
     * immediately before the signature is built, and ONLY when this call is the one that
     * publishes a binding's signature (`publishing`, threaded from
     * `inferImplicitBindingTypes`).  Three reasons for the position: the record above is
     * R3's measurement of the residual AS THE LOOP LEFT IT, which is what the L2
     * differential and `trace-ab.py` compare; the `extinct` solve above must still see
     * every constraint (deleting one before it could hide an unsatisfiable set); and an
     * INTERMEDIATE generalisation's residual is re-instantiated by the inference around
     * it, so deleting there reshapes signatures the deletion was not aimed at.  Nothing
     * between here and the `Exists` is traced. */
    val (kept, keptExts) =
      if (publishing) deleteTautologies(pruned, pubExts) else (pruned, pubExts)
    Exists(l, keptExts, kept)
  }
}
