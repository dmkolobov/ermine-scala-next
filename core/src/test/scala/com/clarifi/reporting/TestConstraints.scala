package com.clarifi.reporting

import org.scalacheck._
import Prop._
import Gen._

import scalaparsers._
import ermine._
import Constraints._
import Q._
import Subst.{ solve, substType }

import scalaz.{Free => _, Name => _, _}
import Scalaz._
import scalaz.scalacheck.ScalaCheckBinding.GenMonad

object TestConstraints extends Properties("Constraints") {
  implicit val su: Supply = Supply.create
  implicit val tml: Located = Loc.builtin

  def hm: SubstEnv = new SubstEnv()

  // Utility functions
  def setUnions[A](ss: Traversable[Set[A]]): Set[A] = ss.foldLeft(Set[A]())(_ ++ _)
  def mapUnions[K,A](ss: Traversable[Map[K,A]]): Map[K,A] = ss.foldLeft(Map[K,A]())(_ ++ _)

  def constraintProp(m: SubstEnv => Any): Prop = secure {
    try { m(hm) ; passed } catch { case d : Death => falsified :| d.getMessage }
  }

  def constraintProof(m: SubstEnv => Any): Prop = secure {
    try { m(hm) ; proved } catch { case d : Death => falsified :| d.getMessage }
  }

  def constraintWrap(m: SubstEnv => Prop): Prop = secure {
    try { m(hm) } catch { case d : Death => falsified :| d.getMessage }
  }

  // Valuations of partition sets
  type Valuation = Map[TypeVar, Set[Name]]

  def disjoint[A](s1: Set[A], s2: Set[A]): Boolean = (s1 & s2) isEmpty

  def valSet(f: Valuation, vs: Set[TypeVar]): Set[Name] = vs.foldLeft(Set[Name]()) {
    case (fs, v) => fs ++ f(v)
  }

  def satisfies(f: Valuation, r: Partition): Prop = {
    val vs = f.keySet.toSet

    r match {
      case Partition(v, RHS(abstr, con), _) => {
        val abs = abstr & vs

        val rightVal = valSet(f, abs) ++ con

        val leftRight = if(vs contains v)
                          if(abs == abstr)
                            f(v) == rightVal
                          else
                            rightVal subsetOf f(v)
                        else
                          true

        (abs.forall(v => disjoint(f(v), con)) &&
        abs.forall(v => (abs - v).forall(u => disjoint(f(v), f(u)))) &&
        leftRight) :| r.toString
      }
    }
  }

  def satisfies(f: Valuation, rs: Traversable[Partition]): Prop = Prop.all(rs.map(satisfies(f, _)).toList:_*)

  def satisfies(f: Valuation, ps: PQueue): Prop = satisfies(f, ps.toSet)

  // Scalacheck stuff
  def fields: Gen[Set[Name]] = {
    def fieldName = for {
      n <- choose(3,7)
      c <- alphaUpperChar
      l <- listOfN(n, alphaChar)
    } yield Local(c + l.foldRight("")(_ + _))

    (choose(0,3) >>= (listOfN(_, fieldName))) map (_.toSet)
  }

  def cfresh(n: Option[Name] = None): TypeVar = fresh(Loc.builtin, n, Free, Rho(Loc.builtin))

  def variables(n: Int): Gen[List[TypeVar]] = choose(0, n) map (k => (0 until k).toList map (_ => cfresh()))

  def valuatedVariables(n: Int): Gen[(List[TypeVar], Valuation)] = {
    val vv: Gen[(TypeVar, Set[Name])] = for {
      fs <- fields
    } yield (cfresh(), fs)

    for {
      k <- choose(0, n)
      vvs <- vv.replicateM(k)
    } yield (vvs.map(_._1), vvs.toMap)
  }

  def ruleVars: Partition => Set[TypeVar] = { case Partition(x, RHS(ys, _), _) => ys + x }

  def collectVars(rs: Set[Partition], cs: PQueue): Set[TypeVar] =
    cs.foldLeft(setUnions(rs map ruleVars))((s,r) => s ++ ruleVars(r))

  def soundness(f: Valuation)(m: SubstEnv => Set[Partition]): Prop =
    constraintWrap { se =>
      val s = m(se)
      satisfies(f, s)
    }

  def soundness2(f: Valuation)(m: SubstEnv => (PQueue, PQueue)): Prop =
    constraintWrap { se =>
      val (rs, cs) = m(se)
      satisfies(f, cs) && satisfies(f, rs)
    }

  def soundnessQueue(f: Valuation)(m: SubstEnv => PQueue): Prop =
    constraintWrap { se =>
      val cs = m(se)
      satisfies(f, cs)
    }


  property("empty constraint") = constraintProp { implicit se =>
    val v = cfresh()
    solve(Part(Loc.builtin, VarT(v), List()))
    substType(VarT(v)) match {
      case ConcreteRho(_, s) => s isEmpty
      case _                 => false
    }
  }

  property("concrete constraint") = constraintProp { implicit se =>
    val v = cfresh()
    val f = Set[Name](Local("Foo"))
    solve(Part(Loc.builtin, VarT(v), List(ConcreteRho(Loc.builtin, f))))
    substType(VarT(v)) match {
      case ConcreteRho(_, `f`) => proved
      case _                   => falsified
    }
  }

  // Valuation generators
  def splitConcreteGen: Gen[(TypeVar, TypeVar, Set[TypeVar], RHS, Valuation)] = for {
    (vs, vl) <- valuatedVariables(25)
    a = cfresh()
    u = cfresh()
    cs <- fields
    ufs = setUnions(vl.values)
    afs = cs ++ ufs
  } yield ( a, u
          , vs.toSet
          , RHS(vs.toSet, cs)
          , vl + (a -> afs) + (u -> ufs))

  def commonSubexpressionGen: Gen[(TypeVar, TypeVar, TypeVar, Set[TypeVar], RHS, RHS, Valuation)] = for {
    cs <- fields
    ds <- fields
    a = cfresh()
    b = cfresh()
    w = cfresh()
    (xs, vxs) <- valuatedVariables(10)
    (ys, vys) <- valuatedVariables(10)
    (zs, vzs) <- valuatedVariables(10)
    vw = setUnions(vxs.values)
    va = cs ++ vw ++ setUnions(vys.values)
    vb = ds ++ vw ++ setUnions(vzs.values)
  } yield ( a, b, w, xs.toSet
          , RHS((xs ++ ys).toSet, cs)
          , RHS((xs ++ zs).toSet, ds)
          , vxs ++ vys ++ vzs + (a -> va) + (b -> vb) + (w -> vw)
          )

  def cancellationGen: Gen[(TypeVar, TypeVar, RHS, RHS, Valuation)] = for {
    (ys, vys) <- valuatedVariables(10)
    (zs, vzs) <- valuatedVariables(10)
    a = cfresh()
    x = cfresh()
    cs <- fields
    ds <- fields
    xfs = setUnions(vzs.values)
    afs = cs ++ xfs ++ setUnions(vys.values)
  } yield ( a, x, RHS(ys.toSet + x, cs)
          , RHS(ys.toSet ++ zs.toSet, cs ++ ds)
          , vys ++ vzs + (a -> afs) + (x -> xfs)
          )

  def randRHS(inc: TypeVar, vali: Set[Name]): Gen[(RHS, Set[Name], Valuation)] = for {
    (vs, vvs) <- valuatedVariables(5)
    gs <- fields
    comb = gs ++ vali ++ setUnions(vvs.values)
  } yield (RHS(vs.toSet + inc, gs), comb, vvs)

  def subGenCommon(x: TypeVar, vxs: Set[Name]): Gen[(PQueue, PQueue, Valuation)] = for {
    vs1 <- variables(5)
    vs2 <- variables(5)
    f = (v: TypeVar) => randRHS(x, vxs) map {
          case (rhs, vv, m) => (Partition(v, rhs), m + (v -> vv)) }
    tup1 <- vs1.traverse(f)
    tup2 <- vs2.traverse(f)
    (parts1, vals1) = tup1.unzip
    (parts2, vals2) = tup2.unzip
    valMap = mapUnions(vals1) ++ mapUnions(vals2)
  } yield ( PQueue(parts1)
          , PQueue(parts2)
          , valMap)

  def subGenMixed: Gen[(TypeVar, RHS, PQueue, PQueue, Valuation)] = for {
    fs <- fields
    x = cfresh()
    (es, ves)  <- valuatedVariables(5)
    vxs = fs ++ setUnions(ves.values)
    rhs = RHS(es.toSet, fs)
    (incm, proc, g) <- subGenCommon(x, vxs)
  } yield (x, rhs, incm, proc, g ++ ves + (x -> vxs))

  def emptyGen: Gen[(TypeVar, PQueue, PQueue, Valuation)] = for {
    bs <- variables(8)
    ds <- variables(8)
    x = cfresh()
    vl = (bs.map(b => b -> Set[Name]()) ++ ds.map(d => d -> Set[Name]())).toMap
    tup <- subGenCommon(x, Set[Name]())
    (incm, proc, g) = tup
  } yield ( x, incm +! Partition(x, RHSAbstr(bs.toSet))
          , proc + Partition(x -> RHSAbstr(ds.toSet))
          , g ++ vl + (x -> Set[Name]()))

  def resolutionGen: Gen[(TypeVar, TypeVar, TypeVar, RHS, RHS, Valuation)] = for {
        cs <- fields
        ds <- fields
        es <- fields
        fs <- fields
        a = cfresh()
        x = cfresh()
        y = cfresh()
      } yield ( a, x, y
              , RHS(Set(x), cs ++ ds)
              , RHS(Set(y), es ++ es)
              , Map( a -> (cs ++ ds ++ es ++ fs)
                   , x -> (ds ++ es ++ fs)
                   , y -> (cs ++ ds ++ fs)))

  def substitutionGen: Gen[(TypeVar, TypeVar, RHS, RHS, Valuation)] = for {
    fs <- fields
    gs <- fields
    x = cfresh()
    y = cfresh()
    (as, vas) <- valuatedVariables(6)
    (bs, vbs) <- valuatedVariables(6)
    vx = fs ++ setUnions(vas.values)
    vy = vx ++ gs ++ setUnions(vbs.values)
  } yield ( x, y, RHS(as.toSet, fs)
          , RHS(bs.toSet + x, gs)
          , vas ++ vbs + (x -> vx) + (y -> vy))

  def divide(fs: Set[Name]): Gen[(RHS, Valuation)] = for {
    vs <- variables(5)
    (nfs, vl) <- divideAmong(fs, vs)
  } yield (RHS(vs.toSet, nfs), vl)

  def divideAmong(fs: Set[Name], vs: List[TypeVar]): Gen[(Set[Name], Valuation)] = for {
    k <- choose(0, fs.size)
    (ls, rs) = fs.splitAt(k)
    (rest, vl) <- vs.foldLeftM((rs, Map() : Valuation)) {
      case ((remaining, acc), v) => for {
        j <- choose(0, remaining.size)
        (ls, rs) = remaining.splitAt(j)
      } yield(rs, acc + (v -> ls))
    }
  } yield (ls ++ rest, vl)

  def unifyGen: Gen[(TypeVar, TypeVar, PQueue, PQueue, Valuation)] = for {
    fs <- fields
    x = cfresh()
    y = cfresh()
    (as, vas) <- valuatedVariables(6)
    vxy = fs ++ setUnions(vas.values)
    (rhs1, vl1) <- divide(vxy)
    (rhs2, vl2) <- divide(vxy)
    (rs3, cs3, vl3) <- subGenCommon(x, vxy)
    (rs4, cs4, vl4) <- subGenCommon(y, vxy)
  } yield ( x, y
          , rs3 ++! rs4 +! Partition(y, rhs2), cs3 ++ cs4 + Partition(x -> rhs1)
          , vas ++ vl1 ++ vl2 ++ vl3 ++ vl4 + (x -> vxy) + (y -> vxy))

  def selfSubGen: Gen[(TypeVar, Partition, Valuation)] = for {
    // x <- x ys
    ys <- variables(10)
    x = cfresh()
    fs <- fields
  } yield ( x
          , Partition(x, RHS(ys.toSet + x), none)
          , ys.map(y => y -> Set[Name]()).toMap + (x -> fs))

  def disjunctionGen: Gen[(Partition, Partition, Partition, Valuation)] = for {
    // x <- A* a* B* b* C* c*       E* e*
    afs <- fields
    (avs, vas) <- valuatedVariables(6)
    bfs <- fields
    (bvs, vbs) <- valuatedVariables(6)
    cfs <- fields
    (cvs, vcs) <- valuatedVariables(6)
    efs <- fields
    (evs, ves) <- valuatedVariables(6)
    // y <- A* a* B* b*       D* d* F* f*
    dfs <- fields
    (dvs, vds) <- valuatedVariables(6)
    ffs <- fields
    (fvs, vfs) <- valuatedVariables(6)
    // y <- A* a*       C* c* D* d* G* g*
    gfs <- fields
    (gvs, vgs) <- valuatedVariables(6)
    x = cfresh()
    y = cfresh()
    vx = afs ++ bfs ++ cfs ++ efs ++ setUnions(vas.values ++ vbs.values ++ vcs.values ++ ves.values)
    vy = afs ++ cfs ++ dfs ++ gfs ++ setUnions(vas.values ++ vcs.values ++ vds.values ++ vgs.values)
  } yield ( Partition(x, RHS((avs ++ bvs ++ cvs ++ evs).toSet, afs union bfs union cfs union efs))
          , Partition(y, RHS((avs ++ bvs ++ dvs ++ fvs).toSet, afs union bfs union dfs union ffs))
          , Partition(y, RHS((avs ++ cvs ++ dvs ++ gvs).toSet, afs union cfs union dfs union gfs))
          , vas ++ vbs ++ vcs ++ vds ++ ves ++ vfs ++ vgs + (x -> vx) + (y -> vy)
          )

  def queueGen: Gen[(PQueue, Valuation)] = choose(0,8) >>= (_ match {
    case 0 => for {
      tup <- splitConcreteGen
      (v, u, _, rhs, f) = tup
    } yield (PQueue(Partition(v, rhs)), f - u)
    case 1 => for {
      tup <- commonSubexpressionGen
      (a, b, w, vs, rhs1, rhs2, f) = tup
    } yield (PQueue(Partition(a, rhs1), Partition(b, rhs2)), f - w)
    case 2 => for {
      tup <- cancellationGen
      (a, _, rhs1, rhs2, f) = tup
    } yield (PQueue(Partition(a, rhs1), Partition(a, rhs2)), f)
    case 3 => for {
      tup <- subGenMixed
      (v, rhs, rs, cs, f) = tup
    } yield (cs ++ rs + Partition(v, rhs), f)
    case 4 => for {
      tup <- emptyGen
      (v, rs, cs, f) = tup
    } yield (cs ++ rs + Partition(v, RHS()), f)
    case 5 => for {
      tup <- resolutionGen
      (a, _, _, rhs1, rhs2, f) = tup
    } yield (PQueue(Partition(a, rhs1), Partition(a, rhs2)), f)
    case 6 => for {
      tup <- substitutionGen
      (x, y, rhs1, rhs2, f) = tup
    } yield(PQueue(Partition(x, rhs1), Partition(y, rhs2)), f)
    case 7 => for {
      tup <- unifyGen
      (x, y, rs, cs, f) = tup
    } yield (cs ++ rs + Partition(x, RHSAbstr(Set(y))), f)
    case 8 => for {
      tup <- selfSubGen
    } yield (PQueue(tup._2), tup._3)
    case 9 => for {
      (p1, p2, p3, v) <- disjunctionGen
    } yield (PQueue(p1, p2, p3), v)
  })

  // Generates a random 'situation', which consists of a set of incoming
  // partitions, a constraint set, and a valuation that aims to be consistent
  // with them.
  def situationGen: Gen[(PQueue, PQueue, Valuation)] = for {
    rsf <- queueGen
    csg <- queueGen
    (rs, f) = rsf
    (cs, g) = csg
  } yield (rs, cs, f ++ g)

  property("resolution sound") = {
    forAll(resolutionGen) { case (a, x, y, r1, r2, f) =>
      val rule1 : Partition = Partition(a, r1)
      val rule2 : Partition = Partition(a, r2)

      val vs = Set(a, x, y)

      (satisfies(f, rule1) && satisfies(f, rule2)) ==>
      soundness(f)(_ => resolution(a, r1, r2))
    }
  }

  property("split concrete sound") = {
    forAll (splitConcreteGen) { case (a, u, vs, r1@RHS(abs,con), f) =>
      val rule = Partition(a, r1)

      val vars = vs ++ ruleVars(rule) + u

      satisfies(f, rule) ==>
        (soundness(f)(_ => splitConcrete(a, abs, con, findRHS(PQueue(), PQueue(), Set())))
          && soundness(f)(_ => splitConcrete(a, abs, con,
               findRHS(PQueue(), PQueue() + Partition(u -> RHSAbstr(vs)), Set()))))
    }
  }


  property("common subexpression sound") = {
    forAll (commonSubexpressionGen) { case (a, b, w, xs, r1, r2, f) =>
      val rule1 = Partition(a, r1)
      val rule2 = Partition(b, r2)

      val vars = xs ++ ruleVars(rule1) ++ ruleVars(rule2) + w

      (satisfies(f, rule1) && satisfies(f, rule2)) ==>
        (soundness(f)(_ => commonSubexpression(a, r1, b, r2, findRHS(PQueue(), PQueue(), Set())))
          && soundness(f)(_ => commonSubexpression(a, r1, b, r2,
                findRHS(PQueue(),
                        PQueue(Partition(w -> RHSAbstr(xs))),
                        Set()))))
    }
  }

  property("cancellation sound") = {
    forAll (cancellationGen) { case (a, x, r1, r2, f) =>
      val rule1 = Partition(a, r1)
      val rule2 = Partition(a, r2)

      (satisfies(f, rule1) && satisfies(f, rule2)) ==>
      soundness(f)(_ => cancellation(a, r1, r2))
    }
  }

  property("subPartitions sound") = {
    forAll (subGenMixed) { case (x, rhs, rules, cs, f) =>
      (satisfies(f, Partition(x, rhs)) &&
       satisfies(f, rules) &&
       satisfies(f, cs)) ==>
       soundness(f)(_ => subPartitions(x, rhs, cs, rules))
    }
  }

  property("destructiveSub sound") = {
    forAll (subGenMixed) { case (x, rhs, rules, cs, f) =>
      (satisfies(f, Partition(x, rhs)) &&
       satisfies(f, rules) &&
       satisfies(f, cs)) ==>
       soundness2(f)(implicit hm => destructiveSub(x, rhs, rules, cs))
    }
  }

  property("substitution sound") = {
    forAll (substitutionGen) { case (x, y, rhs1, rhs2, f) =>
      (satisfies(f, Partition(x, rhs1)) &&
       satisfies(f, Partition(y, rhs2))) ==>
       (soundness(f)(_ => substitution(x, rhs1, y, rhs2)) &&
       soundness(f)(_ => substitution(y, rhs2, x, rhs1)))
    }
  }

  property("makeEmpty sound") = {
    forAll (emptyGen) { case (x, rules, cs, f) =>
      (satisfies(f, Partition(x, RHS())) &&
       satisfies(f, rules) &&
       satisfies(f, cs)) ==>
       soundness2(f)(implicit hm => makeEmpty(x, rules, cs))
    }
  }

  property("unify sound") = {
    forAll (unifyGen) { case (x, y, rs, cs, f) =>
      (satisfies(f, rs) && satisfies(f, cs)) ==>
      (soundness2(f)(implicit hm => Constraints.unify(x, y, rs, cs)) &&
       soundness2(f)(implicit hm => Constraints.unify(y, x, rs, cs)))
    }
  }

  property("self-substitution sound") =
    forAll (selfSubGen) { case (x, rule, f) =>
      satisfies(f, Set(rule)) ==>
      soundness(f)(_ => selfSubstitution(x, rule._2.abstr, rule._2.concr))
    }

  property("disjunction sound") =
    forAll (disjunctionGen) { case (p1@(Partition(_,r1,_)), p2@(Partition(_,r2,_)), p3@(Partition(_,r3,_)), f) =>
      satisfies(f, Set(p1, p2, p3)) ==>
      soundness(f)(_ => Constraints.disjunction(r1, r2, r3))
    }
/*
  property("incorporateAll sound") =
    forAll (situationGen) { case (rs, cs, f) =>
      (satisfies(f, rs) && satisfies(f, cs)) ==>
      soundnessQueue(incorporateAll(rs, cs), f)
    }
*/

  property("join example") = {
    val fst : Set[Name] = Set(Local("Fst"))
    val snd : Set[Name] = Set(Local("Snd"))
    val thd : Set[Name] = Set(Local("Thd"))

    val flds = fst union snd union thd

    def chk(c: Set[Name], v: TypeVar)(implicit hm: SubstEnv): Prop = substType(VarT(v)) match {
      case ConcreteRho(_, `c`) => passed
      case _                   => falsified
    }

    constraintWrap { implicit hm => {
        val a = cfresh()
        val b = cfresh()
        val c = cfresh()
        val d = cfresh()
        val e = cfresh()
        val f = cfresh()

        solve(Exists(Loc.builtin, List(), List(
          Part(Loc.builtin, VarT(d), List(VarT(a), VarT(b))),
          Part(Loc.builtin, VarT(e), List(VarT(b), VarT(c))),
          Part(Loc.builtin, VarT(f), List(VarT(a), VarT(b), VarT(c))),
          Part(Loc.builtin, VarT(d), List(ConcreteRho(Loc.builtin, fst union snd))),
          Part(Loc.builtin, VarT(e), List(ConcreteRho(Loc.builtin, snd union thd)))
        )))

        chk(fst, a) && chk(snd, b) && chk(thd, c) && chk(flds, f)
      }
    }
  }

  def infGen: Gen[Option[Inference]] = choose(0,9) flatMap {
    case 0 => None
    case 1 => Some(Resolution)
    case 2 => Some(Cancellation)
    case 3 => Some(SelfSubstitution)
    case 4 => Some(Substitution)
    case 5 => Some(PartitionEmpty)
    case 6 => Some(SplitConcrete)
    case 7 => Some(CommonPartition)
    case 8 => Some(DeDuplication)
    case 9 => Some(CommonSubexpression)
  }

  def vGen: Gen[TypeVar] = choose(0,10000) flatMap (i => V(Loc.builtin, i, None, Free, Rho(Loc.builtin)))

  def abstrsGen: Gen[(Partition, Partition)] = for {
    lhs <- vGen
    n   <- choose(3, 5)
    l   <- listOfN(n, vGen)
    il  <- infGen
    ir  <- infGen
  } yield (Partition(lhs, RHSAbstr(l.toSet), il), Partition(lhs, RHSAbstr(l.reverse.toSet), ir))

  property("similar partitions") = Prop.forAll(abstrsGen) {
    case (l, r) => l == r &&
                   l.hashCode == r.hashCode &&
                   l._1.hashCode == r._1.hashCode &&
                   l._2.hashCode == r._2.hashCode
  }

  property("add partitions") = Prop.forAll(listOf(abstrsGen))(l => {
    val (fst, snd) = l.unzip
    val q1 = PQueue() ++ fst
    val q2 = q1 ++ snd

    q1.size == q2.size
  })

  property("incorporate twice") = Prop.forAll(listOf(abstrsGen))(l => {
    val (fst, snd) = l.unzip
    def part(p: Partition): Type = p match {
      case Partition(l, r, _) =>
        Part(Loc.builtin, VarT(l), ConcreteRho(Loc.builtin, r.concr) :: r.abstr.toList.map(VarT(_)))
    }

    constraintWrap { implicit hm => {
      val q1 = incorporateAll(PQueue(fst), PQueue())
      val (q2, _) = PQueue.build(substType(Exists(Loc.builtin, List(), snd.map(part _))))
      val q3 = incorporateAll(q2, q1)

      q1.size == q3.size
    }}
  })

  property("queue rhs hash sorted") = Prop.forAll(listOf(abstrsGen))(l => {
    val (fst, snd) = l.unzip
    constraintWrap { implicit hm => {
        val q1 = incorporateAll(PQueue(fst), PQueue())
        val q2 = q1.toList.map(p => p._2.hashCode)
        (q2 == q2.sorted) :| "sorting"
      }
    }
  })
}
