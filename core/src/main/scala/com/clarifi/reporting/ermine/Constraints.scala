package com.clarifi.reporting
package ermine

/*
 * This module handles the constraint solving for row types in
 *
 * After much consideration, we decided that the necessary constraints for
 * our row types could be collapsed into a single one: partitioning. Here,
 * partitioning will be denoted <-. First some rules and conventions:
 *
 * 1) Only single variables may appear to the left of a partition.
 * 2) Variables are written lowercase: a, b, c, x, y, z
 * 3) Field constants are written uppercase: C, D, E, F
 * 4) Said field constants are equivalent to singleton rows: C denotes (| C |)
 * 5) An empty right-side, x <- , expresses that x is empty
 * 6) Sequences of variables or constants use a regex-like convention for
 *    multiplicity
 *   a) x*  -- 0 or more variables
 *   b) D+  -- 1 or more concrete fields
 *   c) y++ -- 2 or more variables
 * 7) Rules that infer something about partitioning of a sequence of variables
 *    xQ, where Q inhabits {*,+,++,...} will be written (x <- ..)Q
 * 8) Named individuals or sequences are expected to be coherent, distinct and
 *    disjoint over an entire inference rule:
 *   a) x* y* -- two disjoint sequences of 0 or more variables
 *   b) x x   -- the same variable twice
 *   c) f <- x+ y*, f <- x+ z* ...
 *       -- three disjoint sequences of variables
 *
 * ---------------
 * Inference Rules
 * ---------------
 *
 * This section describes the inference rules used by the solver to gain new
 * information. Unless otherwise noted, the rules are not destructive, so
 * if the first half of a rule applies to the constraint environment, the
 * second half will be added, but the constraints in the first half will
 * not be removed from the environment.
 *
 * Inference rules will be written vertically, with a vertical list of initial
 * constraints, followed by a bar, followed by the vertical list of output
 * constraints.
 *
 *  Self-substitution
 *
 *   If a variable is partitioned into itself and additional variables,
 *   those additional variables can only be empty.
 *
 *    a <- a b*
 *    ---------
 *      b <-
 *
 *
 *  Empty partition
 *
 *   If a variable is empty, and it is partitioned into one or more variables,
 *   those variables can only be empty.
 *
 *    a <-
 *    a <- x+
 *    -------
 *    (x <-)+
 *
 *
 *  De-duplication
 *
 *   If a partition includes a given variable twice, that variable can only be
 *   empty.
 *
 *    a <- C* x* b b
 *    --------------
 *         b <-
 *
 *
 *  Split concrete
 *
 *   If a variable is partitioned into some fields and more than one variable,
 *   it is useful to name that sequence of variables.
 *
 *    a <- C+ x++
 *    -----------
 *     u <- x++    (u fresh)
 *     a <- C+ u
 *
 *
 *  Cancellation
 *
 *   If we have two partitions of a variable, and the intersection of the
 *   partitions leaves a lone variable as the remainder of one, then we
 *   can infer that that single variable must be partitioned into the
 *   remainder of the other.
 *
 *    a <- C* x* z
 *    a <- C* x* D* d*
 *    ----------------
 *       z <- D* d*
 *
 *
 *  Resolution
 *
 *   If we have two partitions of a variable, each containing a lone variable
 *   on the right, we may infer that the left variable contains all the fields
 *   from both rules, and that each of the lone right variables contain the
 *   fields missing from their rule.
 *
 *     a <- C+ D* x
 *     a <- y  D* E+
 *    ---------------
 *    a <- C+ D* E+ z  (z fresh)
 *       x <- E+ z
 *       y <- C+ z
 *
 *   CORRECTED 2026-09-01.  This diagram used to pair each lone variable with the
 *   concrete part of ITS OWN premise (`x <- C* z`, `y <- E* z`), which is UNSOUND:
 *   premise 1 forces `x` disjoint from `C`, while `x <- C* z` forces `C` inside
 *   `x`, so the two together force `C` empty and the rule reports a type error on
 *   a program that has none.  Mechanised as
 *   `Rowpartition.Rule6Header.header_not_conservative` and
 *   `Rule6Header.header_makes_unsat` in `tracker/lean/Rowpartition/Rules.lean`,
 *   with an explicit two-label counterexample.  The prose above always described
 *   the correct crossed pairing, and `def resolution` always implemented it
 *   (`bots = concr2 -- int` for `x`, `tops = concr1 -- int` for `y`), which is
 *   `Rowpartition.rule6` -- proved sound there.  Only the diagram was wrong.
 *
 *
 *  Substitution
 *
 *   We may substitute a variable with its partition.
 *
 *      a <- D* b x*
 *       b <- F* y*
 *    ----------------
 *    a <- D* F* x* y*
 *
 *
 *  Common partition
 *
 *   If two variables are partitioned identically, we may unify them.
 *
 *    a <- A* x*
 *    b <- A* x*
 *    ----------
 *      a <- b
 *
 *
 *  Common subexpression
 *
 *   It is useful to give names to the largest common variable subexpression
 *   between two rules.
 *
 *    a <- C* x++ y*
 *    b <- D* x++ z*
 *    --------------
 *       w <- x++     (w fresh)
 *     a <- C* w y*
 *     b <- D* w z*
 *
 *
 *  Disjunction
 *
 *   If we know that a set of variables lack a set of fields and variables,
 *   we may be able to infer that another variable set _has_ the respective,
 *   fields and variables.
 *
 *    r1 <- A* a* C* c* z+       S* s*
 *    r2 <- A* a* C* c*    R* r* T* t*
 *    r2 <- A* a*    u+ z+ R* r* U*
 *    C* c* non-empty
 *    --------------------------------------
 *    u+ <- C* c* v (v fresh)
 *
 *  Generalized cancellation !!
 *
 *   We may apply cancellation in a case without a lone variable so long as
 *   we give a name to the multiple variables in question.
 *
 *    a <- C* e* x++
 *    a <- C* e* D* d*
 *    ----------------
 *        u <- x++      (u fresh)
 *       u <- D* d*
 *
 *
 * ----------------
 * Error conditions
 * ----------------
 *
 * Certain constraints or combinations thereof are verifiably
 * unsatisfiable.
 *
 *  Duplicated field
 *
 *   A field cannot appear twice in a row.
 *
 *    a <- C* x* D D
 *    --------------
 *    a inconsistent
 *
 *  Incompatible fields
 *
 *   If we have a concrete substitution for a variable, it must
 *   contain all the fields that other rules say the variable contains.
 *
 *         a <- C* D*
 *         a <- D* E+ x*
 *    ------------------------
 *    C* doesn't subsume E+ x*
 *
 *  Infinite fields
 *
 *   A variable cannot both contain and be disjoint from a field.
 *
 *    a <- C+ a x*
 *    ------------
 *
 * ---------
 * Miscelany
 * ---------
 *
 * Applying the above rules only to learn things, never throwing anything
 * away, and the necessity of comparing every partition against every other
 * for each pass, one would probably expect an algorithm using the rules
 * above to not perform very well. So, a strategy for discarding partitions
 * when possible is desirable. The following are some ideas:
 *
 * 1) Whenever we have a concrete substitution for a variable, we would like
 *    to eliminate partitions involving it. However, we have to take care
 *    not to lose any information. There are two safeguards that we believe
 *    are sufficient:
 *
 *     a) along with the concrete substitution a <- C*, perform all other
 *        substitutions for left-a rules
 *     b) ensure that at least one substitution occurs (i.e. that a is on
 *        the right of at least one rule)
 *
 *    these together ensure that, for instance, in the case of a <- b c
 *    the information that b is disjoint from c is not lost, because we've
 *    substituted 'b c' in for 'a' in some other rule.
 *
 *    In addition, we must inform the standard unifier that we have a
 *    concrete substitution for the variable. This will ensure that rules
 *    about it are never needed later, because the variable will have been
 *    replaced with a concrete expression.
 *
 *    Given these safeguards, we should be able to eliminate all rules
 *    mentioning the concretized variable from the solver state.
 *
 * 2) At some point, constraint solving must end, and we must collapse the
 *    constraint environment into something that can be preprended to a
 *    type. At this point, we can trim the constraint environment by
 *    searching for a small set of constraints that imply the others.
 */

// scalaz's Name and Free shadow ermine's own (Name.scala, Vars.scala)
import scalaz.{Name => _, Free => _, _}
import Scalaz._
import Tags._
import scalaparsers.{Loc, Located, Supply}
import scalaparsers.Document._

import com.clarifi.reporting.util._
import StreamTUtils._

import Type._

object Constraints {
  import Subst._
  // a handy pattern
  object Single {
    def unapply[A](s: Set[A]): Option[A] =
      if(s.size == 1)
        Some(s head)
      else
        None
  }

  /* Invariant: the set of partitioning constraints will always contain
   * sets on the right-hand side. Duplicates will be detected upon rule
   * formation, and the relevant inference or error rule applied
   * immediately.
   *
   * Further, the names of constants in the set of parts should be
   * unique.
   */

  type Fields = Set[Name]

  def displayRHS: RHS => String = {
    case RHS(a, c) =>
      "(|" + c.mkString(", ") + (if(a isEmpty) "" else " ..") + "|)"
  }

  def displayFields(s: Set[String]) = "(|" + s.mkString(", ") + "|)"

  // LongModuleName.foo, LongModuleName.bar gets displayed as
  // LongModuleName.{foo, bar}
  def displayFactoredRow(fs: Fields, indent: String): String = {
    def factorQualifier(p: (Option[String],List[Name])): String =
      p._1.map(_ + ".").getOrElse("") +
      (if (p._2.length == 1) p._2.head.string
       else {
         val newline = if (p._2.length < 4) "" else "\n  " + indent
         "{ " + newline + p._2.map(_.string).sorted.mkString(", "+newline) + " }"
       })
    val factored = fs.toList.groupBy(_.qualifier).toList.
                   sortBy(_._1).map(factorQualifier)
    if (fs.size < 4) indent + factored.mkString(", ")
    else             indent + factored.mkString(",\n" + indent)
  }

  /* The death both row-compatibility checks raise: S1's death site 7,
   * "Row types failed to unify".  Factored out so that `ensureExactly` (S2
   * layer (i)) reports in exactly the words `ensureSuperset` has always used;
   * the two differ in WHEN they fire, never in what they say. */
  private def rowUnifyDeath(loc: Loc, sub: Fields, sup: Fields)(implicit tml: Located): Nothing =
    die {
      "Row types failed to unify: " :/:
      "R1 = " :/: displayFactoredRow(sub, "  ") :/:
      "R2 = " :/: displayFactoredRow(sup, "  ") :/:
      loc.report("R1") :/:
      tml.report("R2")
    }

  // @throws SubstException
  def ensureSuperset(loc: Loc, sub: Fields, sup: Fields)(implicit tml: Located) =
    if (!(sub subsetOf sup)) rowUnifyDeath(loc, sub, sup)

  /* S2 layer (i), `-Dermine.rowSound.bare` (default OFF).  At a BARE definition
   * `v <- ((|C|))` -- no abstract part at all -- a concrete instantiation
   * `v := ((|fs|))` forces `C = fs`, not merely `C subsetOf fs`: the two are
   * definitions of the SAME row.  `Rowpartition/Loop/Sound.lean`'s `bare_refutes`
   * is that statement (two different bare rows for one variable refute the
   * system), so refusing `C != fs` here is a REFUTATION and never a false
   * rejection.  It matters because `makeConcrete`'s `destructiveSub` then
   * DELETES the bare row (`keepDefs` keeps only definitions with two or more
   * abstract parts, and `cancellation` emits nothing for a bare one), so a `C`
   * waved through by containment is lost with nothing in its place -- the hole
   * `S1-SOUNDNESS.md` section S1.1 row 4 names and seed `MIN2` walks through.
   */
  // @throws SubstException
  def ensureExactly(loc: Loc, sub: Fields, sup: Fields)(implicit tml: Located) =
    if (sub != sup) rowUnifyDeath(loc, sub, sup)

  private def predOr[A](p1: A => Boolean, p2: A => Boolean)(x: A): Boolean = p1(x) || p2(x)

  // The right hand side of a partition constraint
  case class RHS(abstr: Set[TypeVar] = Set(), concr: Fields = Set()) {
    def isConcrete = abstr isEmpty

    def isEmpty = (abstr isEmpty) && (concr isEmpty)

    def -(v: TypeVar): RHS = RHS(abstr - v, concr)

    def contains(v: TypeVar): Boolean = abstr contains v

    // @throws SubstException
    def merge(rhs: RHS)(implicit tml: Located): (RHS, Set[TypeVar]) = rhs match {
      case RHS(abs, con) => {
        val aint = abstr & abs
        val cint = concr & con

        if (cint.isEmpty) (RHS((abstr ++ abs) -- aint, concr ++ con), aint)
        else tml.die("Fields appear twice in row: " + cint)
      }
    }

    // @throws SubstException
    def substitute(v: TypeVar, rhs: RHS)(implicit tml: Located): (RHS, Set[TypeVar]) =
      if(abstr contains v) (this - v) merge rhs
      else (this, Set())

    def vars: Vars[Kind] = Vars(abstr)

    def toTypes(loc: Loc): List[Type] = {
      val vs = abstr.toList.map(VarT(_))
      if(concr.isEmpty)
        vs
      else
        ConcreteRho(loc, concr) :: vs
    }
  }

  // RHS views
  object RHSEmpty {
    def unapply(rhs: RHS): Boolean = rhs isEmpty
    def apply(): RHS = RHS()
  }
  object RHSAbstr {
    def unapply(rhs: RHS): Option[Set[TypeVar]] = rhs match {
      case RHS(abs, con) if con isEmpty => some(abs)
      case _                            => none
    }
    def apply(abstr: Set[TypeVar]): RHS = RHS(abstr, Set())
  }
  object RHSConcr {
    def unapply(rhs: RHS): Option[Fields] = rhs match {
      case RHS(abs, con) if abs isEmpty => some(con)
      case _                            => none
    }
    def apply(concr: Fields): RHS = RHS(Set(), concr)
  }

  object RHS {
    def build(ts: List[Type])(implicit tml: Located): (RHS, List[TypeVar]) = {
      val (abs, con, e) = ts.foldLeft((Set[TypeVar](), Set[Name](), Set[TypeVar]())) {
        case ((a, c, e), ConcreteRho(l, s)) =>
          val i = c.intersect(s)
          if(i.nonEmpty)
            tml.die("Fields appear twice in row: " + i.mkString(","))
          else (a, c ++ s, e)
        case ((a, c, e), VarT(v)) =>
          if(a.contains(v) || e.contains(v))
            (a - v, c, e + v)
          else
            (a + v, c, e)
        case ((a, c, e), Con(_, n, _, _)) => (a, c + n, e)
        case (_, t) => tml.die(t.report("panic: Malformed constraint, RHS" :+: text(t.toString)))
      }
      (RHS(abs, con), e.toList)
    }
  }

  type IntMap[TypeVar] = Map[Int, TypeVar]

  object Q {
    def substSet(u: TypeVar, v: TypeVar, s: Set[TypeVar]) = if(s contains u) s - u + v else s

    // Invariant: sort is a valid topological sorting of nodes given edges
    case class TypeVarGraph(nodes: Set[TypeVar], edges: Map[TypeVar, Set[TypeVar]], sort: Map[TypeVar, Int]) {
      def +(p: (TypeVar, Set[TypeVar])): (TypeVarGraph, Boolean) = p match {
        case (u, vs) => {
          val newNodes = nodes ++ vs + u
          val newEdges = edges.get(u) match {
            case None    => edges + (u -> vs)
            case Some(s) => edges + (u -> (s ++ vs))
          }

          def indexMap(s: Stream[TypeVar]): Map[TypeVar, Int] =
            s.zip(Stream.from(0)).toMap

          def edgeFun(v: TypeVar): Stream[TypeVar] = newEdges.get(v) cata (_.toStream, Stream[TypeVar]())

          if(sort.contains(u) && vs.forall(v => sort.contains(v) && (sort(v) < sort(u))))
            (TypeVarGraph(newNodes, newEdges, sort), false)
          else
            (TypeVarGraph(newNodes, newEdges,
              indexMap(reverseTopSort(newNodes.toStream)(edgeFun))), true)
        }
      }

      def + : Partition => (TypeVarGraph, Boolean) = {
        case Partition(u, RHS(vs, _), _) => this + (u -> vs)
      }

      def rename(u: TypeVar, v: TypeVar): TypeVarGraph = {
        val nnodes = substSet(u, v, nodes)
        val nedges = edges map { case (k, s) => (if(k == u) v else k, substSet(u, v, s)) }
        val nsort = if(sort contains u) sort - u + (v -> sort(u)) else sort
        TypeVarGraph(nnodes, nedges, nsort)
      }
    }

    object TypeVarGraph {
      def empty: TypeVarGraph = TypeVarGraph(Set(), Map(), Map())
    }

    // (empty(priority, (right hash, left hash)), size)
    type PSQK = (Option[(Int, (Int, Int))], Int)
    type PSQI = FingerTree[PSQK, Partition]

    def pr(graph: TypeVarGraph): Reducer[Partition, PSQK] = {
      def mon: Monoid[PSQK] = new Monoid[PSQK] {
        val zero = (none, 0)
        def append(s1: PSQK, s2: => PSQK): PSQK = {
          val sz = s1._2 + s2._2

          s1._1 match {
            case None => (s2._1, sz)
            case Some((prl, tpl)) => s2._1 match {
              case None => (s1._1, sz)
              case Some((prr, tpr)) => (some((prl min prr, tpr)), sz)
            }
          }
        }
      }
      UnitReducer[Partition, PSQK] { case Partition(lhs, rhs, _) =>
        (some(graph.sort(lhs), (rhs.hashCode, lhs.hashCode)), 1) } {mon}
    }

    def heapify(q: PSQI, graph: TypeVarGraph): PSQI = {
      implicit def r: Reducer[Partition, PSQK] = pr(graph)

      // I think this should replace the reducer
      q.foldRight(FingerTree.empty)(_ +: _)
    }

    def part[K: Order](q: PSQI, f: PSQK => K, k: K): (PSQI, PSQI, PSQI) = {
      val (less, geqs) = q.split(f(_) gte k)
      val (equal, greater) = geqs.split(f(_) gt k)

      (less, equal, greater)
    }

    def rhsLookup(rhs: RHS, q: PSQI, exe: Boolean): Option[TypeVar] = if(exe) rhs match {
      case RHSEmpty()          => None // Don't common-out empty partitions
      case RHSAbstr(Single(_)) => None // nor unification partitions
      case _ => q.foldRight(none[TypeVar])((p: Partition, r) => if(p._2 == rhs) some(p._1) else r)
    } else None

    // Inserts a partition into the queue, returning a new queue and an updated
    // graph. The boolean determines whether the rule should be processed for
    // common right-hand sides.
    def insert(p: Partition, q: PSQI, graph: TypeVarGraph, process: Boolean): (PSQI, TypeVarGraph) =
      if(p.isSelfUnification) (q, graph)
      else {
        val (hcr, hcl) = p match {
          case Partition(lhs, rhs, _) => (rhs.hashCode, lhs.hashCode)
        }

        val (rlt, req, rgt) = part(q, (_._1.map(_._2._1)), some(hcr))

        val (llt, leq, lgt) = part(req, (_._1.map(_._2._2)), some(hcl))

        def sandwich: (PSQI, TypeVarGraph) = {
          val (newGraph, reheap) = graph + p

          def hp(nq: PSQI) = if(reheap) heapify(nq, newGraph) else nq

          val left  = hp(rlt <++> llt)
          val right = hp(leq <++> lgt <++> rgt)

          (left <++> (p +: right), newGraph)
        }

        if(leq any (p == _)) (q, graph)
        else rhsLookup(p._2, req, process) match {
          case Some(v) =>
            insert(Partition(v, RHSAbstr(Set(p._1)), CommonPartition), q, graph, false)
          case None    => sandwich
        }
      }

    def pop(q: PSQI, graph: TypeVarGraph): Option[(Partition, PSQI)] = {
      val priority = q.measure._1.map(_._1)

      val (lhs, rhs) = q.split(k => k._1.map(_._1) == priority)

      rhs.viewl.fold(none, (p, rest) => some((p, lhs <++> rest)))
    }

    class PQueue(val q: PSQI, graph: TypeVarGraph) extends ForeachIterable[Partition] {

      override def foreach[U](f: Partition => U): Unit = q.foreach(x => { f(x) ; () })

      // Inserts a partition into the queue without any processing
      def +(p: Partition): PQueue = {
        val (nq, ng) = insert(p, q, graph, false)

        new PQueue(nq, ng)
      }

      // Iterated +
      def ++(ps: Traversable[Partition]): PQueue = ps.foldLeft(this)(_ + _)

      // Iterated +
      def ++(ps: PQueue): PQueue = ps.foldLeft(this)(_ + _)

      // Inserts a partition into the queue, checking for common right-hand
      // sides and making a unification instead if applicable.
      def +!(p: Partition): PQueue = {
        val (nq, ng) = insert(p, q, graph, true)

        new PQueue(nq, ng)
      }

      // Iterated +!
      def ++!(ps: Traversable[Partition]): PQueue = ps.foldLeft(this)(_ +! _)

      // Iterated +!
      def ++!(ps: PQueue): PQueue = ps.foldLeft(this)(_ +! _)

      def dequeue: Option[(Partition, PQueue)] =
        pop(q, graph) map (_ :-> (new PQueue(_, graph)))

      override def filter(pred: Partition => Boolean): PQueue = {
        implicit def r: Reducer[Partition, PSQK] = pr(graph)
        val nq = q.foldRight(FingerTree.empty)((e,r) => if(pred(e)) e +: r else r)

        new PQueue(nq, graph)
      }

      override def partition(pred: Partition => Boolean): (Set[Partition], PQueue) = {
        implicit def r: Reducer[Partition, PSQK] = pr(graph)
        val (ps, nq) = q.foldRight((Set[Partition](),FingerTree.empty)){
          case (e, (l, r)) => if(pred(e)) (l + e, r) else (l, e +: r)
        }

        (ps, new PQueue(nq, graph))
      }

      override def isEmpty: Boolean = q.isEmpty

      override def size: Int = q.measure._2

//      def toSet: Set[Partition] = q.foldLeft(Set[Partition]())(_ + _)

      def foldRight[R](z: => R)(f: (Partition, => R) => R): R = q.foldRight(z)(f)

      override def foldLeft[R](z: R)(f: (R, Partition) => R): R = q.foldLeft(z)(f)

      def foldM[M[_]:Monad,R](z: R)(f: (R, Partition) => M[R]): M[R] =
        q.foldRight((z: R) => z.pure[M])((p, k) => (z: R) => f(z, p) >>= k).apply(z)

      def findRHS(rhs: RHS): Option[TypeVar] = {
        val i = rhs.hashCode

        def onRHS(p: Int => Boolean): PSQK => Boolean = {
          case (None             , _) => true
          case (Some((_, (r, _))), _) => p(r)
        }

        val (_, geqs) = q.split(onRHS(i <= _))
        val (eqs, _) = geqs.split(onRHS(i < _))

        eqs.foldRight[Option[TypeVar]](none) {
          case (Partition(lhs, rhs2, _), r) =>
            if(rhs == rhs2) some(lhs)
            else            r
        }
      }

      override def forall(p: Partition => Boolean): Boolean = q all p
      override def exists(p: Partition => Boolean): Boolean = q any p

      def contains(p: Partition): Boolean = p match {
        case Partition(lhs, rhs, _) =>
          part(q, (_._1.map(_._2)), some((rhs.hashCode, lhs.hashCode)))._2 any (p == _)
      }

      override def toString: String = foldRight("")((p, s) => "\n  " + p.toString + s)

      def expand(implicit hm: SubstEnv, su: Supply, tml: Located): PQueue = incorporateAll(this, PQueue())

      def vars: Vars[Kind] = foldRight(Vars() : Vars[Kind])((p, r) => r ++ Vars(p._1) ++ p._2.vars)

      def toType(loc: Loc, quantified: Set[TypeVar]): Type = {
        val toQuant = (vars -- quantified).toList
        val ps = foldRight(List() : List[Type])((p, r) => Part(loc, VarT(p._1), p._2.toTypes(loc)) :: r)

        ps match {
          case List(p) if toQuant.isEmpty => p
          case _ => Exists.mk(loc, toQuant, ps)
        }
      }
    }

    object PQueue {
      private def empty: PQueue = {
        implicit def r: Reducer[Partition, PSQK] = pr(TypeVarGraph.empty)
        new PQueue(FingerTree.empty, TypeVarGraph.empty)
      }

      def apply(ps: Partition*) = empty ++ ps
      def apply(ps: Traversable[Partition]) = empty ++ ps

      // @throws SubstException
      def build(v: TypeVar, t:Type)(implicit tml: Located): PQueue = t match {
        case VarT(v) => PQueue(Partition(v, RHSAbstr(Set(v))))
        case ConcreteRho(_, s) => PQueue(Partition(v, RHSConcr(s)))
        case _ => tml.die(t.report("Non-row in expected row position", t.toString))
      }

      // @throws SubstException
      def build(t: Type)(implicit su: Supply, tml: Located): (PQueue,List[TypeVar]) = {
        def aux(t: Type): (List[Partition], List[TypeVar]) = t match {
          case e : Exists =>
            val (us, ts) = unbindExists(Ambiguous(Free), e)
            val (pss, vss) = ts.map(aux _).unzip
            (pss.flatten, vss.flatten)
          case Part(loc, VarT(v), rhsz) =>
            val (rhs, es) = RHS.build(rhsz)
            (Partition(v, rhs) :: es.map(u => Partition(u, RHSEmpty())), List())
          case Part(loc, lhs, rhs) => // lhs is not a variable
            val v = fresh(loc, none, Ambiguous(Free), Rho(loc.inferred))
            val (rhs1, es1) = RHS.build(rhs)
            val (rhs2, es2) = RHS.build(List(lhs))
            (Partition(v, rhs1) :: Partition(v, rhs2) :: (es1 ++ es2).map(u => Partition(u, RHSEmpty())), List())
          case _ =>
            (List(),List())
            // t.die("panic: malformed constraint:" :+: text(t.toString))
        }
        val (ps, vs) = aux(t.nf)
        (PQueue(ps), vs)
      }
    }
  }

  import Q.PQueue

  // An enumeration for inference rules, used to track which rule
  // introduced a particular partition.
  sealed trait Inference
  case object Resolution          extends Inference
  case object Cancellation        extends Inference
  case object SelfSubstitution    extends Inference
  case object Substitution        extends Inference
  case object PartitionEmpty      extends Inference
  case object SplitConcrete       extends Inference
  case object CommonPartition     extends Inference
  case object DeDuplication       extends Inference
  case object CommonSubexpression extends Inference
  /** Stage 0 provenance: the fresh-minting branch of `commonSubexpression`
   *  ONLY -- the one the row-constraint ticket proposes to cut. The reuse and
   *  folding branches keep `CommonSubexpression`. `Inference` is never
   *  inspected, and `Partition.equals`/`hashCode` ignore it, so this split is
   *  behaviour-neutral. */
  case object CommonSubexpressionMint extends Inference

  /** Stage 2 provenance (`tracker/satterm/KEYED-SPLIT-STAGE2.md`): the KEYED REUSE
   *  branch of `splitConcrete`, taken only when `-Dermine.splitKey=true` and the
   *  resolvent reverse lookup finds a name for `v \ concr`.  It emits ONE partition,
   *  `w <- (abstr)`, and mints nothing -- the Lean `KeyedSplit.kSplitReuseResult`.
   *  `Inference` is never inspected and `Partition.equals`/`hashCode` ignore it, so
   *  the tag itself is behaviour-neutral; it exists so `-Dermine.rowTrace` can count
   *  how often the branch fires. */
  case object SplitKeyed           extends Inference

  /** Stage 5 provenance (`tracker/satterm/KEYED-ROW-STAGE5.md`): the CONCRETE-ROW REUSE
   *  branch of `splitConcrete`, taken only when `-Dermine.splitRow=true` and the premise's
   *  left-hand side is concrete `C` while some variable `w` already carries the complement
   *  row `C \ concr`.  It emits ONE partition, `w <- (abstr)` -- the same conclusion the
   *  keyed reuse emits -- and mints nothing; the Lean is `KeyedRow.K2SplitStep.row` /
   *  `kSplitReuseResult`, entailed by `KeyedRow.concRow_reuse_sat` and
   *  `K2RowApp.models_iff`.  `Inference` is never inspected and `Partition.equals`/
   *  `hashCode` ignore it, so the tag itself is behaviour-neutral; it exists so
   *  `-Dermine.rowTrace` can count how often the branch fires. */
  case object SplitRow             extends Inference

  /** Stage 5 provenance: the CONCRETE-ROW REUSE branch of `resolution`, taken only when
   *  `-Dermine.resRow=true`, the resolvent reverse lookup MISSED, and the same
   *  concrete-row lookup hits at the resolvent row `C \ (concr1 ++ concr2)`.  It emits the
   *  two conclusions `x <- (w, D \ C)`, `y <- (w, C \ D)` that the `resGuard` reuse emits,
   *  with the carrier `w` in place of a fresh name.  The Lean is `KeyedRow.K2ResStep.row`,
   *  entailed by `K2ResStep.row_models_iff`.  Behaviour-neutral as a tag, as above. */
  case object ResolutionRow        extends Inference

  /** Stage 7 provenance (`tracker/satterm/KEYED-EMPTY-STAGE7.md`): the EMPTY-ROW branch of
   *  `splitConcrete`, taken only when `-Dermine.emptyRow=true`, the premise's left-hand side
   *  is concrete with EXACTLY the premise's own concrete part (`myRow(v) = concr`, so the
   *  complement row `C \ concr` is EMPTY), and some variable is already known to denote the
   *  empty row -- either still queued, or in the `SubstEnv` where `makeEmpty` retained the
   *  fact after deleting the partition.  The Lean reuse `KeyedRow.K2SplitStep.row` at that
   *  carrier `z` emits `z <- (abstr)`; this branch emits instead the PROPAGATION which that
   *  conclusion plus `makeEmpty z` force -- `x <- ()` for every `x ∈ abstr`
   *  (`KeyedEmpty.propPart`, and `KeyedEmpty.group_forced_empty` for the entailment) --
   *  because in the compiler the carrier has already left both queues and a partition about
   *  it would make `makeEmpty` reinstantiate an instantiated variable.  See the long
   *  correspondence note at `def splitConcrete`.  `Inference` is never inspected and
   *  `Partition.equals`/`hashCode` ignore it, so the tag itself is behaviour-neutral; it
   *  exists so `-Dermine.rowTrace` can count how often the branch fires. */
  case object SplitEmpty           extends Inference

  /** Stage 7 provenance: the EMPTY-ROW branch of `resolution`, taken only when
   *  `-Dermine.emptyRow=true`, both earlier lookups missed, and the RESOLVENT row
   *  `F \ (concr1 ++ concr2)` is empty with an empty-row carrier known.  The resolvent `z`
   *  a mint would name denotes `∅`, so the two conclusions the `resGuard` reuse emits,
   *  `x <- (z, D \ C)` and `y <- (z, C \ D)`, become the bare concrete `x <- ((|D \ C|))`
   *  and `y <- ((|C \ D|))`, which is what this branch emits.  Behaviour-neutral as a tag,
   *  as above. */
  case object ResolutionEmpty      extends Inference

  /** Which generative rules are allowed to mint fresh variables.
   *
   *  `-Dermine.genRules=all` (DEFAULT) -- shipped behaviour, unchanged.
   *  `-Dermine.genRules=cut`  -- the five-line cut of the row-constraint ticket:
   *      `commonSubexpression`'s MINTING branch returns nothing; its reuse and
   *      folding branches, and `splitConcrete`/`resolution`, are untouched.
   *  `-Dermine.genRules=nongen` -- the fully NON-GENERATIVE calculus: no rule
   *      mints. That is the object `tracker/lean/Rowpartition/Canonical.lean`
   *      proves terminating and meaning-preserving.
   *
   *  Read once at class-init from a system property, so a run is a constant and
   *  nothing depends on evaluation order. Default `all` means the shipped
   *  compiler is bit-identical to before this switch existed. */
  object GenRules {
    /* ADOPTED 2026-09-01 (ticket §7.10/§7.11): `cut` is the default.  It deletes only
     * the fresh-minting `else` branch of `commonSubexpression`, keeping REUSE, FOLD,
     * `splitConcrete` and `resolution`.  `-Dermine.genRules=all` restores the previous
     * shipped behaviour exactly; `nongen` is UNSOUND and is kept only to reproduce that. */
    private val mode: String = System.getProperty("ermine.genRules", "cut")
    val cseMints: Boolean   = mode == "all"
    val splitMints: Boolean = mode == "all" || mode == "cut"
    val resolves: Boolean   = mode == "all" || mode == "cut"
    /* Orthogonal to `mode`: re-enables the Disjunction rule, whose three call
     * sites shipped commented out.  Experiment for the row-constraint ticket. */
    val disjRule: Boolean   = System.getProperty("ermine.disjunction", "false") == "true"
    /* Orthogonal: the refutation-only per-concrete-label check (`labelClash`). */
    /* ADOPTED 2026-09-01 (ticket §7.13): the per-concrete-label refutation is on.  It
     * closes a soundness hole -- the solver accepted constraint sets with no solution
     * (`core/examples/incomplete/unsound0*.e`).  `-Dermine.labelCheck=false` disables it. */
    val labelCheck: Boolean = System.getProperty("ermine.labelCheck", "true") == "true"
    /* Orthogonal: guard `resolution`'s mint with the resolvent reverse lookup, the way
     * `splitConcrete` already guards its own (ticket item 8c).
     *
     * `Rowpartition/ResGuard.lean` proves the guard is not a semantic change
     * (`GResStep.satisfiable_iff`, `GResStep.entails_iff`, `resolvent_unique`);
     * `ResGuardTerm.lean` proves the guarded rule TERMINATES on every satisfiable system,
     * which the unguarded rule does not (`Cut.resSeed_diverges` runs on a system that has
     * a model); `ResGuardDiverge.lean` proves the guard does NOT buy termination in
     * general -- the remaining divergent seeds are all unsatisfiable.  `labelCheck`
     * refutes `gSeed` in particular (`gSeed_refuted`) but NOT every such seed:
     * `DefaultDiverge.lean` (`not_CRule`, 2026-09-02) exhibits an unsatisfiable system on
     * which this rule set diverges and which the input check does not refute.
     *
     * ADOPTED 2026-09-02 (ticket item 8c): DEFAULT ON.  `-Dermine.resGuard=false` restores
     * the previous behaviour exactly.  The evidence:
     *   - proved not a semantic change (`GResStep.satisfiable_iff`, `guard_loses_nothing`,
     *     `resolvent_unique`) and terminating on every SATISFIABLE system, with the
     *     unconditional version proved FALSE so the boundary is known;
     *   - 66-file example corpus and 34-file incompleteness corpus: 0 files differ,
     *     verdicts identical, `shouldfail/` 40/40 still rejected;
     *   - `core/test` 903/904 with the flag ON, the one failure being the pre-existing
     *     `Constraints.disjunction sound` generator; `Constraints.resolution sound` itself
     *     passes 100 tests under the guard;
     *   - and it is not merely insurance: `core/examples/incomplete/gu05_star_join_4dim_
     *     concrete_signature.e` goes from ~12.0s of solve time to ~1.1s, an 11x reduction,
     *     in BOTH rule modes.  `resolution` fires on 18 example modules (and zero stdlib
     *     ones), so the corpus zeros above are the guard running on real code. */
    val resGuard: Boolean = System.getProperty("ermine.resGuard", "true") == "true"
    /* Orthogonal: run `labelClash` BEFORE `q.expand` rather than after.  The check reads
     * only the input partitions, so this is free; what it buys is refuting an
     * unsatisfiable input before the saturation gets a chance to diverge on it
     * (`Rowpartition/ResGuardDiverge.lean`: a four-constraint unsatisfiable system on
     * which resolution, guarded or not, has derivations of every length is refuted at
     * one label).  What it costs is that a module which fails both ways reports the
     * label clash instead of whatever `expand` would have raised.
     *
     * ADOPTED 2026-09-02: DEFAULT ON.  On the 66-file corpus it changes no verdict
     * (23 LOADED / 43 REJECTED, `shouldfail/` 40/40) and 26 messages, all in
     * `shouldfail/`; each now names the field and the reason where it used to quote an
     * internal variable ("Infinite row partition for 'r2^579383'", "Incompatible
     * instantiations of '579503'", a bare "R2").  It was measured and DECLINED the day
     * before because 11 of the 26 blamed a stdlib signature: the check blamed wherever
     * the offending constraint was located, and a constraint instantiated from a stdlib
     * helper's type was located in the stdlib.  That was follow-up item 1 (blame the
     * call site); `Subst.instantiatedAt` and `Term.sub` now keep every constraint at
     * the occurrence that incurred it, and all 26 blame the user's call site.  The
     * incompleteness corpus (34 files) is unchanged.  `-Dermine.labelCheckEarly=false`
     * restores the late position exactly. */
    val labelCheckEarly: Boolean =
      System.getProperty("ermine.labelCheckEarly", "true") == "true"
    /* Orthogonal: key `splitConcrete`'s mint guard on the pair (lhs, concrete part) --
     * the resolvent reverse lookup `resolution` already uses -- instead of on the GROUP.
     *
     * Shipped (syntactic) guard: mint a name for the group `abstr` unless some partition
     * of the system is a bare `d <- abstr`.  Groups can be manufactured without end, so
     * nothing bounds split branching.  KEYED guard: mint unless some partition of the
     * system is `v <- (z, concr)` for a single variable `z` -- i.e. unless the system
     * already names `v \ concr`.  Under a model the minted variable's row is FORCED by
     * that pair alone (`v <- (u, concr)` forces `rho u = rho v \ concr`), so this is the
     * keying the semantics already imposes, and it is the keying `resolution`'s guard has
     * had since `resGuard` was adopted.  On a hit the rule REUSES: it gives the existing
     * name `w` the new group as a bare definition, `w <- (abstr)`, and mints nothing.
     *
     * `Rowpartition/KeyedSplit.lean` licenses it:
     *   - `terminatesOnSatKeyed` -- the whole calculus (`KDefaultStep` = the non-generative
     *     rules + the KEYED split + guarded resolution) terminates on EVERY satisfiable
     *     input in EVERY run order, with the explicit bound `KRun.length_le`;
     *   - `keyed_vs_syntactic : TerminatesOnSatKeyed /\ ~TerminatesOnSat` -- the same
     *     statement is FALSE for the shipped guard (`DefaultSatDiverge.not_TerminatesOnSat`,
     *     witness `W2`);
     *   - `ksplit_reuse_sat` / `KSplitStep.reuse_models_iff` -- the reuse branch is pure
     *     entailment and does not move the model set at all;
     *   - `ksplit_mint_conservativeExt` -- the mint branch is still a conservative
     *     extension at the fresh name.
     * It says NOTHING about ill-typed (unsatisfiable) input: guarded resolution still
     * diverges on `ResGuardDiverge.gSeed`, and the label check plus `RHS.merge` remain the
     * only defences there.  The two calculi are INCOMPARABLE, not nested
     * (`split_mint_not_keyed`), so the emitted NAME differs from the shipped rule's.
     *
     * ADOPTED 2026-09-03: DEFAULT ON.  `-Dermine.splitKey=false` restores the previous
     * behaviour exactly.  The evidence (`tracker/satterm/KEYED-SPLIT-STAGE2.md`):
     *   - proved not a semantic change (`ksplit_reuse_sat`, `KSplitStep.reuse_models_iff`,
     *     `ksplit_mint_conservativeExt`) and TERMINATING on every satisfiable system in
     *     every run order (`terminatesOnSatKeyed`), with the shipped guard's version of the
     *     same statement proved FALSE (`keyed_vs_syntactic`), so the boundary is known;
     *   - 66-file example corpus and 34-file incompleteness corpus: 0 files differ,
     *     verdicts identical (23/43 and 18/16), `shouldfail/` 40/40 still rejected;
     *   - 188 published interfaces / 1932 bindings: no signature weaker; the only two
     *     bindings attributable to the flag are alpha-equivalent and equivalent-modulo-a-
     *     forced-name, everything else appears in a same-configuration control run;
     *   - `core/test` 903/904 with the flag ON, the one failure being the pre-existing
     *     `Constraints.disjunction sound` generator; `repl-smoke` 4/4, `lsp-smoke` 98/98;
     *   - and it is not merely insurance: `core/examples/incomplete/gu05_star_join_4dim_
     *     concrete_signature.e` goes from ~6.2s of module time to ~1.2s, a 5x reduction,
     *     because five keyed reuses take its largest solve from 1372 saturated partitions
     *     to 458.  The branch fires 77 times over 18 of the 110 example modules (and zero
     *     stdlib ones), so the corpus zeros above are the guard running on real code.
     * What it does NOT buy: anything for ill-typed input (guarded resolution still diverges
     * on `ResGuardDiverge.gSeed`; the label check and `RHS.merge` remain the defences), and
     * the theorem is about the additive rule set, not about `incorporateAll`'s deletions
     * (`makeConcrete`/`destructiveSub` absorb exactly the `v <- (z, K)` witnesses the key
     * needs).  Stage 3 (`Rowpartition/KeyedLoop.lean`, `tracker/satterm/KEYED-LOOP-STAGE3.md`)
     * answered that: with the concretisation step added, the keyed calculus does NOT
     * terminate on all satisfiable input (`not_TerminatesOnSatKeyedLoop`, witness `W3`), the
     * mechanism is real here at about half of the id bases, and what stops it is `common`
     * unifying the re-minted name with the deleted witness's -- a loop property no relation
     * states.  The corpus count of such re-mints is unchanged by this flag (157 vs 156). */
    val splitKey: Boolean = System.getProperty("ermine.splitKey", "true") == "true"
    /* Orthogonal, Stage 5 (`tracker/satterm/KEYED-ROW-STAGE5.md`): widen the mint guard of
     * `splitConcrete` ONE MORE STEP, from the lone witness `v <- (z, K)` to the CONCRETE-ROW
     * carrier -- `v <- ((|C|))` together with `w <- ((|C \ K|))`.  Under a model those two
     * concrete definitions ARE the lone witness (`KeyedRow.conc_lone_sat`), so `w` already
     * denotes `v \ K`, which is what a mint would have named; the branch gives `w` the group
     * as a bare definition, `w <- (abstr)`, and mints nothing.  A NAME, never silence -- the
     * design rule of `tracker/ROW-CONSTRAINT-STATE.md`.
     *
     * `Rowpartition/KeyedRow.lean` licenses it:
     *   - `KeyedRow.K2SplitStep.row` / `K2RowApp` is the branch; `concRow_reuse_sat` and
     *     `K2RowApp.models_iff` say it does not move the model set at all;
     *   - `Carried G v K := Resolved G v K \/ ConcCarried G v K` is the widened guard, and
     *     `K2MintApp.toSplitApp` says every mint that survives it is a mint the SHIPPED rule
     *     would take, so the branch only ever replaces mints;
     *   - `mintsBoundedOnSat_splitFragment` -- with this branch and a faithful model of
     *     `makeConcrete`/`destructiveSub` (`concretizeSrs`), the split fragment mints
     *     BOUNDEDLY on satisfiable input under the loop's deletions, in every run order,
     *     which is exactly what Stage 3 proved FALSE for the keyed guard
     *     (`KeyedLoop.not_TerminatesOnSatKeyedLoop`, witness `W3`).  The mechanism is
     *     `carried_concretizeSrs` ("once carried, always carried"): the two ways a key
     *     witness dies are the two ways it becomes a concrete-row carrier.
     * Scope: the SPLIT fragment only.  `KeyedRow.not_MintsBoundedOnSatKeyed2` shows the
     * whole loop-extended calculus is still unbounded with guarded `resolution` as shipped
     * (witness `W4`, which has NO split premise), which is what `ermine.resRow` below is
     * for; and nothing here is about ill-typed input.
     *
     * ADOPTED 2026-09-03: DEFAULT ON.  `-Dermine.splitRow=false` restores the previous
     * behaviour exactly.  The evidence (`tracker/satterm/KEYED-ROW-STAGE5.md`):
     *   - proved not a semantic change (`KeyedRow.concRow_reuse_sat`,
     *     `K2RowApp.models_iff` -- the model set does not move) and, for the SPLIT
     *     fragment, MINT-BOUNDED under the loop's own deletions on every satisfiable input
     *     in every run order (`mintsBoundedOnSat_splitFragment`), which is exactly the
     *     statement Stage 3 proved FALSE for the keyed guard alone
     *     (`KeyedLoop.not_TerminatesOnSatKeyedLoop`, witness `W3`); and the rule AS WRITTEN
     *     here is a step of that calculus (`KeyedRowScala.scalaRowSplit_step`, for the spec
     *     the lookup really meets, `MyRowSpec`/`ConcRowSpec`, on a modelled system);
     *   - `W3` in the real solver: the re-mint happens at 55 of 100 id bases with the flag
     *     off and at NONE with it on, same solved system -- the rule does in every order
     *     what `common` does in some;
     *   - 66-file example corpus and 34-file incompleteness corpus: 0 files differ,
     *     verdicts identical (23/43 and 18/16), `shouldfail/` 40/40 still rejected;
     *   - 188 published interfaces / 1,933 bindings: NO signature weaker; the one binding
     *     attributable to this flag, `incomplete/np01.inferredRestate`, LOSES a forced
     *     existential (7 -> 6) and is equivalent to the shipped one;
     *   - `core/test` 903/904 with the flag on, the one failure being the pre-existing
     *     `Constraints.disjunction sound` generator; `repl-smoke` 4/4, `lsp-smoke` 98/98;
     *   - population, stated honestly: it is INSURANCE, not a speed-up.  It fires 4 times
     *     over 3 of the 110 example modules and at 17 of 100 `NE6` bases, taking corpus
     *     split mints 637 -> 626 and kept-definition mints 157 -> 154 with all 133
     *     consumers still finding a name; no timing moved (ResStar 5-9, RowStress 10/14,
     *     CoStar8 and `gu05` all inside their own run-to-run spread).
     * COVERAGE, stated at adoption: the bound is against the loop's CONCRETISATION
     * deletions (`concretizeSrs`).  `makeEmpty`/`unify` deletions are NOT in the relation,
     * and the Scala lookup cannot see an emptied carrier -- 74 of the corpus's 157
     * kept-definition mints have an EMPTY complement and stay mints; what stops those from
     * chaining is eager empty propagation, unformalised (Stage 6). */
    val splitRow: Boolean = System.getProperty("ermine.splitRow", "true") == "true"
    /* Orthogonal, Stage 5: the same widening for `resolution`'s mint guard.  When the
     * resolvent reverse lookup misses, fall through to the concrete-row lookup at the
     * RESOLVENT row: if `v <- ((|C|))` and some `w <- ((|C \ (concr1 ++ concr2)|))`, then
     * `w` already denotes the resolvent and the rule emits the two conclusions about the
     * lone variables with `w` in place of the fresh name.
     *
     * `Rowpartition/KeyedRow.lean`: `K2ResStep.row` is the branch, `K2ResStep.row_models_iff`
     * says it does not move the model set (`conc_lone_sat` manufactures the resolvent, then
     * `ResGuard.reuse_sat` draws both conclusions unchanged), `K2ResStep.mint_toGRes` says
     * every mint that survives the widened guard is a shipped guarded mint, and
     * `mintsBoundedOnSatKeyed2Star` is the point: with BOTH guards widened this way the
     * whole loop-extended calculus mints boundedly on every satisfiable input in every run
     * order, with the explicit bound `|allVars G0| + hmeas L rho G0`.
     * `keyed2_star_vs_shipped_res : MintsBoundedOnSatKeyed2Star /\ ~MintsBoundedOnSatKeyed2`
     * is the contrast in one line: without THIS flag the statement is false.
     *
     * Note `fresh` is still drawn at the same point in both branches of ONE call (as
     * `resGuard` already arranged), so the reuse itself draws no extra id.  The TOTAL number
     * of draws in a run can still differ, because a run that reuses derives fewer partitions
     * and therefore calls `resolution` fewer times -- each call draws one id whether or not
     * it emits anything (measured on the `W4c` control: 3 draws with the flag off, 1 with it
     * on, at the same input).
     *
     * ADOPTED 2026-09-03: DEFAULT ON.  `-Dermine.resRow=false` restores the previous
     * behaviour exactly.  The evidence (`tracker/satterm/KEYED-ROW-STAGE5.md`):
     *   - proved not a semantic change (`K2ResStep.row_models_iff`; the two conclusions are
     *     the ones `resGuard`'s reuse already emits, with an existing name in place of the
     *     fresh one) and every mint that survives the widened guard is a shipped guarded
     *     mint (`K2ResStep.mint_toGRes`); the rule AS WRITTEN is a step of the calculus
     *     (`KeyedRowScala.scalaRowRes_step`);
     *   - it is the flag that completes the theorem: with BOTH branches the whole
     *     loop-extended calculus mints boundedly on every satisfiable input in every order
     *     (`mintsBoundedOnSatKeyed2Star`, bound `|allVars G0| + hmeas L rho G0`), and
     *     `keyed2_star_vs_shipped_res` says the same statement is FALSE with `resolution`
     *     left as shipped (`not_MintsBoundedOnSatKeyed2`, the split-free witness `W4`);
     *   - 66-file and 34-file corpora: 0 files differ, verdicts identical, `shouldfail/`
     *     40/40 -- including `inc08_project_absent_from_join_result.e` and
     *     `mis02_join_result_annotation.e`, the two modules where this branch actually
     *     fires, which stay REJECTED with the same message (the refutation-safety check);
     *   - 188 published interfaces: NO signature weaker and NO binding attributable to this
     *     flag at all;
     *   - `core/test` 903/904 with the flag on; `repl-smoke` 4/4, `lsp-smoke` 98/98;
     *   - population: 19 firings over 5 of the 110 example modules, taking resolution's
     *     conclusions 1,748 -> 1,696 (and 1,644 with `splitRow` as well); no timing moved,
     *     including the `ResStar` family, which cannot reach the branch because the
     *     resolution premise's left-hand side never becomes concrete there.
     * COVERAGE, stated at adoption: the bound is against the loop's CONCRETISATION
     * deletions (`concretizeSrs`).  `makeEmpty`/`unify` deletions are NOT in the relation,
     * and the Scala lookup cannot see an emptied carrier -- 74 of the corpus's 157
     * kept-definition mints have an EMPTY complement and stay mints; what stops those from
     * chaining is eager empty propagation, unformalised (Stage 6). */
    val resRow: Boolean = System.getProperty("ermine.resRow", "true") == "true"
    /* Orthogonal, Stage 7 (`tracker/satterm/KEYED-EMPTY-STAGE7.md`): make the EMPTY row
     * visible to the two concrete-row branches above.  Both of them look for a carrier of
     * the complement row `C \ K`; when `K = C` that complement is EMPTY, and the only
     * carrier it could have is a variable already known to denote `∅` -- which `makeEmpty`
     * has DELETED from both queues, keeping the fact in the `SubstEnv` instead.  That is
     * 74 of the corpus's 157 kept-definition mints (`KEYED-ROW-STAGE5.md` §B7-2), and the
     * hole Stage 6 found in the mint bound.
     *
     * `Rowpartition/KeyedEmpty.lean` licenses it:
     *   - `makeEmptyD` is the compiler's `makeEmpty` made faithful, and `carried_not_invariant`
     *     / `hmeas_increases` show Stage 4's invariant FAILS at it in exactly one way: the
     *     deleted `v <- ()` was the carrier of the EMPTY row;
     *   - `makeEmptyE v G = insert (mk v ∅ ∅) (makeEmptyD v G)` is the same step with that
     *     fact RETAINED -- which is what the `SubstEnv` does -- and `carried_makeEmptyE`
     *     makes `Carried` an unconditional invariant again;
     *   - `mintsBoundedOnSatKeyed3E`: with it, minting is bounded on every satisfiable input
     *     in every order of the calculus with BOTH deletions (concretisation and
     *     `makeEmpty`), by Stage 4's own bound `|allVars G0| + hmeas L rho G0`;
     *   - `G7_mints` is the 74-of-157 shape as a theorem (a satisfiable system whose split
     *     group is FORCED empty, on which all three lookups miss and the rule mints) and
     *     `G7_blocked` says ONE visible `e <- ()`, anywhere, turns that mint into a reuse.
     * The branch is LOOKUP-ONLY: `v <- ()` is NOT re-enqueued (it would be dequeued, call
     * `makeEmpty` again and reinstantiate `v`), and what the branch EMITS is the propagation
     * the Lean reuse plus its forced `empty` step derive -- see `def splitConcrete` and
     * `def resolution`.  Scope: nothing here is about ill-typed input, and `unify` -- the
     * other deletion that moves a fact into the `SubstEnv` -- is still unmodelled.
     *
     * DEFAULT OFF pending the adoption gates in `tracker/satterm/KEYED-EMPTY-STAGE7.md`.
     * `-Dermine.emptyRow=true` enables it. */
    val emptyRow: Boolean = System.getProperty("ermine.emptyRow", "false") == "true"
    /* ------------------------------------------------------------------ *
     * S2 (`tracker/loopmodel/S2-DESIGN.md`): NO FALSE ACCEPTANCE.          *
     * ------------------------------------------------------------------ *
     * The shipped solver ACCEPTS unsatisfiable row systems.  Ten seeds are
     * confirmed on the compiler (`tracker/loopmodel/S1-REVIEW.md` Z-1/Z-2 and
     * its Appendix B; `tracker/repro/satterm/seeds/unsat/`), the shortest five
     * constraints long.  Two mechanisms:
     *   - the loop reaches `.done` on a residual it never refuted (saturation is
     *     refutation-INCOMPLETE), and
     *   - `makeConcrete` deletes a bare definition `v <- ((|C|))` with `C` a
     *     PROPER subset of the concrete instantiation, because `ensureSuperset`
     *     tests containment where the semantics forces equality.
     * `labelCheckEarly` misses them because it is unit propagation, which is
     * SOUND but not COMPLETE (`Rowpartition/LabelAlgo.lean`); every one of these
     * needs a case split.
     *
     * Three layers, each separately switchable, ALL DEFAULT OFF.  With them off
     * the compiler is byte-identical to before this switch existed; adoption is
     * a decision for the user, not for this stage.
     *
     *   `-Dermine.rowSound=true`            -- master: turns all three on.
     *   `-Dermine.rowSound.bare=true|false` -- (i)   bare-row EXACTNESS in
     *       `makeConcrete`: at a bare definition `v <- ((|C|))` and a concrete
     *       instantiation `v := ((|fs|))`, require `C = fs` rather than
     *       `C subsetOf fs`.  Sound: `Rowpartition/Loop/Sound.lean`'s
     *       `bare_refutes` (two DIFFERENT bare rows for one variable refute the
     *       system).  Refutation site: `ensureExactly`, the same
     *       "Row types failed to unify" death `ensureSuperset` raises.
     *   `-Dermine.rowSound.saturated=true|false` -- (ii)  run `labelClash` on the
     *       SATURATED set as well as on the input.  Sound:
     *       `Rowpartition.refute_saturated_sound`.  This is the flag removed on
     *       2026-09-02 at "zero additional refutations on both corpora" -- a fact
     *       about the corpora, not about the algorithm (S1 review, section 7.1:
     *       it catches 1146 of 1166 model false acceptances).
     *   `-Dermine.rowSound.decide=true|false` -- (iii) a COMPLETE per-label
     *       decision (`labelDecide`): unit propagation PLUS case split, run on
     *       the solve's LIVE INPUT -- the input partitions together with the
     *       `SubstEnv` bindings of every variable they mention, because
     *       `Subst.solve` does NOT `substType` its input before `PQueue.build`
     *       and the environment is long-lived (S1 review Z-6).  This is the layer
     *       that carries the theorem: pass ==> satisfiable.
     *   `-Dermine.rowSound.budget=<n>`      -- decision nodes per label for (iii),
     *       default 200000; `-Dermine.rowSound.solveBudget=<n>` caps their SUM over
     *       one solve, default 1000000.  The problem is NP-complete (Schaefer's one-in-three),
     *       so the budget is what keeps a pathological solve from hanging; on
     *       exhaustion the check returns NO VERDICT and refutes nothing, which is
     *       why the theorem in `S2-DESIGN.md` carries the budget as a hypothesis.
     *       Exhaustion is COUNTED (`GenRules.rowSoundBudgetHits`) and traced
     *       (`RowTrace` kind `budget`) so that "it never fired" is a measurement
     *       rather than an assumption.
     */
    private val rowSoundAll: Boolean =
      System.getProperty("ermine.rowSound", "false") == "true"
    private def rowSoundFlag(n: String): Boolean =
      System.getProperty(n, if (rowSoundAll) "true" else "false") == "true"
    val rowSoundBare: Boolean   = rowSoundFlag("ermine.rowSound.bare")
    val rowSoundSat: Boolean    = rowSoundFlag("ermine.rowSound.saturated")
    val rowSoundDecide: Boolean = rowSoundFlag("ermine.rowSound.decide")
    val rowSoundBudget: Int     =
      try System.getProperty("ermine.rowSound.budget", "200000").toInt
      catch { case _: NumberFormatException => 200000 }
    /** Layer (iii)'s cap on the decision nodes ONE SOLVE may spend, summed over
      * its labels; `-Dermine.rowSound.solveBudget`, default 1000000.  S2 review
      * V-12: the per-label budget alone bounds the worst case at `#labels` times
      * the per-label cost (measured at 0.20 s for 200000 nodes), which is
      * seconds on a wide solve.  Exhaustion is NO VERDICT, refutes nothing, and
      * is now VISIBLE -- see `Subst.solve`'s `decideLabels`. */
    val rowSoundSolveBudget: Long =
      try System.getProperty("ermine.rowSound.solveBudget", "1000000").toLong
      catch { case _: NumberFormatException => 1000000L }
    /** Times (iii) ran out of a BUDGET (per label or per solve) and returned NO
      * VERDICT.  Read by the S2 measurement harness; never read by the compiler. */
    val rowSoundBudgetHits = new java.util.concurrent.atomic.AtomicLong(0L)
    /** Times (iii)'s FAIL-SAFE fired instead: a total assignment failed its own
      * check, which would be a propagator bug.  Counted apart from the budget so
      * that "0 budget exhaustions" cannot absorb it (S2 review V-8). */
    val rowSoundCheckFails = new java.util.concurrent.atomic.AtomicLong(0L)
    /** Decision nodes (iii) has spent, and the largest single `solve` bill. */
    val rowSoundNodes      = new java.util.concurrent.atomic.AtomicLong(0L)
    val rowSoundMaxNanos   = new java.util.concurrent.atomic.AtomicLong(0L)
    /* REMOVED 2026-09-02, both measured and declined; see
     * `tracker/TICKET-row-solver-8abc.md` and the Lean that still licenses them.
     *   `ermine.labelCheckSaturated` -- run the check on `q.expand` instead of the input.
     *     Sound (`Rowpartition.refute_saturated_sound`), but it refuted ZERO additional
     *     programs on the 66-file example corpus AND the 34-file incompleteness corpus,
     *     which is item 8a's own stopping condition.
     *   `ermine.spliceGuard` -- skip a `Subst.reduce` splice that is not provably
     *     conservative.  Correct (`Rowpartition.reduce2G_backward`), but its precondition
     *     fails on 90% of splices and diffing the published `.ei` showed it DEGRADES
     *     signatures, turning resolved concrete rows into constrained polymorphic ones.
     * The proofs are kept; the flags were dead weight. */
    override def toString =
      mode + (if (disjRule) "+disj" else "") + (if (labelCheck) "+label" else "") +
        (if (labelCheckEarly) "-early" else "") + (if (resGuard) "+resguard" else "") +
        (if (splitKey) "+splitkey" else "") + (if (splitRow) "+splitrow" else "") +
        (if (resRow) "+resrow" else "") + (if (emptyRow) "+emptyrow" else "") +
        (if (rowSoundBare) "+rsbare" else "") + (if (rowSoundSat) "+rssat" else "") +
        (if (rowSoundDecide) "+rsdecide" else "")
  }
  case object Disjunction         extends Inference

  case class Partition(_1: TypeVar, _2: RHS, inf: Option[Inference]) {
    def tup: (TypeVar, RHS) = (_1, _2)

    override def toString: String = {
      def pvar: TypeVar => String = {
        case V(_,i,_,ty,_) => '^' + ty.toString.toLowerCase + i.toString
      }
      def prhs: RHS => String = {
        case RHS(abs,con) => ( abs.map(pvar).mkString(" ")
                             , con.mkString(" ")).toString
      }
      val pinf = inf.cata(x => x.toString + ": ", "")

      pinf + pvar(_1) + " <- " + prhs(_2)
    }

    override def equals(v: Any) = v match {
      case Partition(u, r, _) => _1 == u && _2 == r
      case _                  => false
    }

    override def hashCode: Int = (_1, _2).hashCode

    def isSelfUnification: Boolean = _2 match {
      case RHSAbstr(Single(u)) => u == _1
      case _                   => false
    }
  }

  object Partition {
    def apply(v: TypeVar, rhs: RHS, inf: Inference): Partition = Partition(v, rhs, some(inf))
    def apply(v: TypeVar, rhs: RHS): Partition = Partition(v, rhs, none)
    def apply(p: (TypeVar, RHS)): Partition = Partition(p._1, p._2, none)
  }

  def ruleInvolves(u: TypeVar): Partition => Boolean = {
    case Partition(v, rhs, _) => u == v || rhs.contains(u) }

  def trim(ps: Set[Partition], cs: PQueue): Set[Partition] =
    ps.filter(p => !(cs contains p))

  def findRHS(ps: PQueue, cs: PQueue, s: Set[Partition])(rhs: RHS): Option[TypeVar] =
    // scalaz 7.0 unwrapped @@ tags implicitly; 7.1+ needs Tag.unwrap
    Tag.unwrap(First(cs.findRHS(rhs)) |+| First(ps.findRHS(rhs)) |+| First(s.find(_._2 == rhs).map(_._1)))

  /* Merges a well-formed constraint into cs.
   *
   * We also take care of the following rules here:
   *
   *  Common partition
   *
   *    a <- A* x*
   *    b <- A* x*
   *    ----------
   *      a <- b
   */

  def combine(q1: PQueue, q2: PQueue)(implicit hm: SubstEnv, su: Supply, tml: Located): PQueue =
    if(q1.size < q2.size)
      incorporateAll(q2, q1)
    else
      incorporateAll(q1, q2)

  def incorporateAll(incm: PQueue, proc: PQueue)(implicit hm: SubstEnv, su: Supply, tml: Located): PQueue = incm.dequeue match {
      case None => proc
      case Some((r@Partition(v, rhs, _), rest)) =>
//        System.err.println(r)
//        println("incoming")
//        println(rest.toString)
//        println("processed")
//        println(proc.toString)
//        println("--------------------")
        /* Trace-only: one `step` record per dequeue, naming the branch taken, and one
         * `learn` record per partition the general branch derived.  Inert unless
         * `-Dermine.rowTrace` is set (`RowTrace.enabled` is a constant). */
        def stepLog(branch: String): Unit =
          if (RowTrace.enabled)
            RowTrace.log("step\t" + RowTrace.site + "\t" + branch + "\t" + RowTrace.clean(r.toString) +
                         "\tincm=" + rest.size + "\tproc=" + proc.size)
        val (nincm, nproc) = proc findRHS(rhs) match {
          case Some(u) => stepLog("common:" + u.id); unify(v, u, rest, proc) // common partition
          case None    => rhs match {
            case RHSEmpty()          => stepLog("empty"); makeEmpty(v, rest, proc)
            case RHSConcr(concr)     => stepLog("concrete"); makeConcrete(v, concr, rest, proc)
            case RHSAbstr(Single(u)) => stepLog("unify:" + u.id); unify(u, v, rest, proc)
            case RHS(abstr,concr)    =>
              stepLog("learn")
              val learned = learnPartitions(v, rhs, rest, proc)
              if (RowTrace.enabled)
                learned.foreach(p => RowTrace.log("learn\t" + RowTrace.site + "\t" +
                                                  (if (proc contains p) "seen" else "new") + "\t" +
                                                  RowTrace.clean(p.toString)))
              (rest ++! trim(learned, proc), proc + r)
          }
        }
        incorporateAll(nincm, nproc)
    }

  /*
   *  Self substitution
   *
   *    a <- a b*
   *    ----------
   *     (b <-)*
   *
   *    a <- C+ a b*
   *    ------------
   *       error
   */
  // @throws SubstException
  def selfSubstitution(v: TypeVar, abstr: Set[TypeVar], concr: Fields)(implicit tml: Located): Set[Partition] =
    if(concr isEmpty) (abstr - v).map(u => Partition(u, RHS(), SelfSubstitution))
    else tml.die("Infinite row partition for '" + v + "'")

  /* The actual calculation of the split concrete rule
   *
   *  Split concrete
   *
   *    a <- C+ x++
   *    -----------
   *     u <- x++    (u fresh)
   *     a <- C+ u
   *
   * CORRESPONDENCE WITH `Rowpartition/KeyedSplit.lean` (`-Dermine.splitKey`, DEFAULT ON
   * since 2026-09-03).  Write `c` for the premise `v <- (abstr, concr)`, so `c.lhs = v`,
   * `vset c = abstr`, `c.conc = concr`; `G` is the current system.  The three branches
   * below are, in order:
   *
   *   syntactic reuse  `rhss(RHSAbstr(abstr)) = Some(u)`, i.e. `Names G u (vset c)`.
   *       Emits `c.lhs <- (u, c.conc)`.  This is `Cut.SplitReuseApp` / `splitReuseResult`,
   *       which the keyed calculus keeps VERBATIM: it is one of the `NonGenStep` rules of
   *       `KDefaultStep`, not part of `KSplitStep`, so `splitKey` must not touch it.
   *   keyed reuse      `splitKey` and `resolvent(concr) = Some(w)`, i.e. `mk c.lhs {w}
   *       c.conc ∈ G` -- exactly `KSplitReuseApp G c w` (its other three premises,
   *       `c ∈ G`, `c.conc ≠ ∅`, `2 ≤ |vset c|`, are the guards above and the caller).
   *       Emits `mk w (vset c) ∅` = `w <- (abstr)` = `kSplitReuseResult`.  No fresh id is
   *       drawn -- `fresh` is called only in the mint branch below.
   *   mint             otherwise.  With `splitKey` on, `resolvent(concr) = None` is
   *       `¬ Resolved G c.lhs c.conc`, which is `KSplitApp.unresolved`, so this branch is
   *       `KSplitStep.mint`.  With `splitKey` off it is `Cut.SplitApp` as shipped.
   *
   * `Resolved G v K` is `∃ z, mk v {z} K ∈ G` (`ResGuard.lean`, `def Resolved`), and
   * `resolvent` is `learnPartitions`'s `findResolvent`, which is exactly that lookup
   * restricted to the `v` at hand.  ONE DIFFERENCE, and it is nil in effect:
   * `findResolvent` ranges over `proc ++ incm`, i.e. `G` MINUS the premise `c` itself
   * (`incorporateAll` re-adds the dequeued partition to `proc` only after
   * `learnPartitions` returns).  `c` cannot be a witness for its own key -- a witness has
   * a SINGLE abstract variable and `c` reaches this rule only with `2 ≤ |abstr|` -- so
   * `¬Resolved (G \ {c}) v concr = ¬Resolved G v concr`, and the Scala guard is the Lean
   * guard, not an approximation of it.
   *
   * THAT ARGUMENT IS NOW A THEOREM, not the prose it used to be:
   * `Rowpartition/KeyedSplitScala.lean` (2026-09-03).
   *   `resolved_erase_iff`   `Resolved (G.erase c) v K <-> Resolved G v K`, given
   *       `2 ≤ |vset c|`: exactly the argument above.  `ksplit_guard_erase_iff` states it
   *       in the guard's own vocabulary, and `ksplitApp_erase_iff` /
   *       `ksplitReuseApp_erase_iff` say `KSplitApp` / `KSplitReuseApp` are unchanged
   *       when their lookup is computed on `G.erase c`.  (Not
   *       `KSplitApp (G.erase c) c u <-> KSplitApp G c u` -- its premise `c ∈ G` fails on
   *       `G.erase c`; it is the GUARD that is insensitive to the erase.)
   *   `named_erase_iff`,     the same question for the SYNTACTIC lookup above, which
   *   `names_erase_iff`      `findRHS` also computes on `incm ++ proc`.  It closes for a
   *       DIFFERENT reason, which the prose here never mentioned: that lookup's witnesses
   *       are BARE partitions (`conc = ∅`) and this rule runs only when `concr` is
   *       nonempty.
   *   `scalaSplit`,          the three branches below as a function, in this order, with
   *   `scalaSplit_step`      the two lookups as arguments meeting `RhssSpec` /
   *       `ResolventSpec` on `G.erase c` -- and ADEQUACY: whatever it returns is a
   *       `KDefaultStep` of `G`, i.e. a step of the calculus proved to terminate on every
   *       satisfiable system (`KeyedSplit.terminatesOnSatKeyed`).  `scalaSplitOf_step` is
   *       the same for the closed function; `scalaSplit_eq_none_iff` pins the only no-op
   *       to the `concr.isEmpty || abstr.size < 2` early return, so no branch is silently
   *       dropped.
   *
   * The batch `s` that `resolution` also consults is empty here: `splitConcrete` is the
   * INITIAL value of `learnPartitions`' fold, so no partition of this batch exists yet.
   *
   * CORRESPONDENCE WITH `Rowpartition/KeyedRow.lean` (`-Dermine.splitRow`, DEFAULT OFF;
   * Stage 5, `tracker/satterm/KEYED-ROW-STAGE5.md`).  The FOURTH branch below, between the
   * keyed reuse and the mint:
   *
   *   concrete-row reuse   `splitRow` and `concRow(concr) = Some(w)`, i.e. `v` has a bare
   *       concrete definition `mk c.lhs ∅ C ∈ G` and `w` carries the complement,
   *       `mk w ∅ (C \ c.conc) ∈ G` -- exactly `KeyedRow.K2RowApp G c w C`.  Emits
   *       `mk w (vset c) ∅` = `w <- (abstr)` = `kSplitReuseResult`, the SAME conclusion the
   *       keyed reuse emits, and draws no fresh id.  Entailed by the environment:
   *       `KeyedRow.concRow_reuse_sat`, `K2RowApp.models_iff`.  With the flag on, the mint
   *       branch's guard is `¬ Carried G v concr` (`KeyedRow.Carried`), and
   *       `K2MintApp.toSplitApp` says every mint that survives it is a mint the shipped rule
   *       would take.
   *
   * ONE DIFFERENCE FROM THE LEAN, deliberate and in the safe direction: `K2RowApp` has no
   * `c.conc ⊆ C` premise (soundness derives it from the model, `concRow_reuse_sat`), while
   * `concRow` below ASKS for it.  On satisfiable input the two agree -- `makeConcrete`'s
   * `ensureSuperset` enforces it -- and on unsatisfiable input the Scala refuses the branch
   * where the Lean would take it, so no refutation can be lost to it.  Every firing of the
   * Scala branch is therefore a `K2RowApp`, which is what `KeyedRowScala.scalaRowSplit_step`
   * proves.
   *
   * WHERE THE CONCRETE ROW LIVES (the faithfulness note the Lean cannot supply).  The Lean
   * asks `mk v ∅ C ∈ G`.  In the compiler a NONEMPTY concrete row of `v` is a bare partition
   * `Partition(v, RHS(Set(), C))` in the `proc` queue and NOWHERE ELSE: `makeConcrete` does
   * not call `instantiateType`, and it returns the dequeued partition to `proc`
   * (`nproc + Partition(v, RHSConcr(fs))`), so after `makeConcrete v` the fact is exactly a
   * queue partition.  The EMPTY row is the one exception: `makeEmpty` records
   * `v := ConcreteRho(∅)` in the `SubstEnv` and DELETES every partition mentioning `v`, so a
   * variable already made empty is invisible to `concRows` and can never be the carrier `w`
   * (a `w <- ()` still sitting in `incm`, not yet dequeued, IS visible).  `unify` likewise
   * moves `v := VarT(u)` into the `SubstEnv` and removes `v`'s partitions.  So the lookup is
   * a lower bound on the Lean's `∈ G`: it can only miss, never hit spuriously.
   *
   * CORRESPONDENCE WITH `Rowpartition/KeyedEmpty.lean` (`-Dermine.emptyRow`, DEFAULT OFF;
   * Stage 7, `tracker/satterm/KEYED-EMPTY-STAGE7.md`).  The FIFTH branch below, between the
   * concrete-row reuse and the mint, is the ONE case the Stage 5 lookup structurally cannot
   * reach -- the complement row is EMPTY:
   *
   *   empty-row reuse   `emptyRow` and `emptyRow(concr) = Some(z)`, i.e. `mk c.lhs ∅ C ∈ G`
   *       with `C = c.conc` (so the complement `C \ c.conc` is `∅`) and some `mk z ∅ ∅`
   *       KNOWN -- still queued, or in the `SubstEnv`, which is where `makeEmpty` left it
   *       after deleting the partition.  That is `KeyedRow.K2RowApp G c z C` on a
   *       `makeEmptyE` image: the systems in which the emptied variable's fact is RETAINED,
   *       which are exactly the ones `KeyedEmpty.mintsBoundedOnSatKeyed3E` bounds.
   *       `KeyedEmpty.G7_mints` is this premise shape as a theorem -- a SATISFIABLE system
   *       whose split group is forced empty, on which all three earlier lookups miss -- and
   *       `G7_blocked` says one visible `e <- ()` turns the mint into a reuse.  It is 74 of
   *       the corpus's 157 kept-definition mints (`KEYED-ROW-STAGE5.md` §B7-2).
   *
   * WHAT THE BRANCH EMITS, and why it is not the Lean's conclusion verbatim.  `K2RowApp`
   * emits `mk z (vset c) ∅` = `z <- (abstr)`.  The compiler must NOT emit that: `z` has been
   * instantiated (`instantiateType(z, ConcreteRho(∅))`) and deleted from both queues, so a
   * partition about `z` would re-enter the queues, and once its group is erased it would
   * reach `makeEmpty z` a second time -- `instantiateType`'s "panic: reinstantiated type".
   * (Re-enqueueing `z <- ()` itself is worse: it is dequeued, calls `makeEmpty` again, and
   * cycles.  The repair is LOOKUP-ONLY.)  What the branch emits instead is the propagation
   * that the Lean conclusion FORCES one step later: in the Lean, `makeEmptyE z` applied to a
   * system containing both `z <- ()` and `z <- (S)` derives `x <- ()` for every `x ∈ S`
   * (`KeyedEmpty.propPart`, `mem_makeEmptyD`'s third disjunct), and when `z` occurs nowhere
   * else -- which is exactly what "deleted from both queues" means -- that step ADDS those
   * and nothing more (`KeyedEmptyScala.emptyReuse_compose`).  So the Scala step is the Lean
   * reuse composed with its forced `empty` step, so one step here is TWO steps of
   * `KeyedEmpty.K3ELoopStep` (`KeyedEmptyScala.splitEmpty_two_steps`).  The adequacy for the
   * rule as a whole is `KeyedEmptyScala.scalaEmptySplit_run` -- every system the five-branch
   * rule returns is reachable by a run of that relation -- for the spec the lookup really
   * meets (`EmptyRowSpec`, which is Stage 5's `ConcRowSpec` at `C \ K = ∅` with the
   * environment's retained empties as a second source), and `scalaEmptySplit_bounded` states
   * the resulting bound.
   *
   * The emitted set is entailed by the PREMISE ALONE, with no carrier:
   * `KeyedEmpty.group_forced_empty` -- if `mk u ∅ K ∈ G` and a definition of `u` has concrete
   * part `K`, then every variable of its group denotes `∅` in every model.  The carrier is
   * asked for anyway, because it is what makes the step a step of the RELATION that has the
   * bound.  And it is what the default reaches the long way round: mint `u <- (abstr)` and
   * `v <- (u, concr)`, cancellation against `v <- ((|C|))` derives `u <- ()`, and
   * `makeEmpty u`'s `aux` emits these same partitions.  The rule does in every order what
   * the mint plus cancellation plus `makeEmpty` do in some. */
  def splitConcrete(v: TypeVar, abstr: Set[TypeVar], concr: Fields, rhss: RHS => Option[TypeVar],
                    resolvent: Fields => Option[TypeVar] = _ => none,
                    concRow: Fields => Option[TypeVar] = _ => none,
                    emptyRow: Fields => Option[TypeVar] = _ => none)(implicit su: Supply): Set[Partition] =
    if(concr.isEmpty || abstr.size < 2) Set()
    else // split concrete
      rhss(RHSAbstr(abstr)) match {
        case Some(u) => Set(Partition(v, RHS(Set(u), concr), SplitConcrete))
        case None if !GenRules.splitMints => Set()
        case None    =>
          (if (GenRules.splitKey) resolvent(concr) else none) match {
            case Some(w) =>
              // KEYED REUSE: `v <- (w, concr)` is already present, so `w` denotes
              // `v \ concr`, which is what a mint would have named.  Give the existing
              // name the new group as a bare definition and mint nothing.  Entailed by
              // the environment: `Rowpartition.ksplit_reuse_entails`.
              Set(Partition(w, RHSAbstr(abstr), SplitKeyed))
            case None =>
              (if (GenRules.splitRow) concRow(concr) else none) match {
                case Some(w) =>
                  // CONCRETE-ROW REUSE (Stage 5): `v <- ((|C|))` and `w <- ((|C \ concr|))`
                  // are both present, so `w` denotes `v \ concr` just as a lone witness
                  // would (`KeyedRow.conc_lone_sat`).  Same conclusion as the keyed reuse,
                  // no fresh id.  Entailed: `KeyedRow.concRow_reuse_sat`.
                  Set(Partition(w, RHSAbstr(abstr), SplitRow))
                case None =>
                  (if (GenRules.emptyRow) emptyRow(concr) else none) match {
                    case Some(_) =>
                      // EMPTY-ROW REUSE (Stage 7): `v <- ((|C|))` with `C = concr`, so the
                      // complement is `∅` and some `z <- ()` is known -- in the queues or in
                      // the `SubstEnv`.  The group is FORCED empty
                      // (`KeyedEmpty.group_forced_empty`), so emit the propagation the Lean
                      // reuse plus its `makeEmptyE` step derive, and mint nothing.  The
                      // carrier itself is deliberately NOT mentioned: it has left the queues.
                      abstr.map(x => Partition(x, RHSEmpty(), SplitEmpty))
                    case None =>
                      val u = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))
                      Set( Partition(u, RHSAbstr(abstr), SplitConcrete)
                         , Partition(v, RHS(Set(u), concr), SplitConcrete))
                  }
              }
          }
      }

  /* The lookup that is passed when the Stage 5 flags -- and, since Stage 7, the empty-row
   * flag -- are off: one shared constant, so the default allocates no closure per
   * `learnPartitions` call. */
  private val noConcRow: Fields => Option[TypeVar] = _ => none

  /* When the above special case rules haven't fired, we need to collect
   * up new rules based on the rule we're about to add, and the other
   * rules that have been incorporated already.
   */
  // @throws SubstException
  def learnPartitions(v: TypeVar, rhs1: RHS, incm: PQueue, proc: PQueue)
                     (implicit hm: SubstEnv, su: Supply, tml: Located): Set[Partition] =
    if(rhs1.abstr contains v) selfSubstitution(v, rhs1.abstr, rhs1.concr)
    else {
      /* The reverse lookup that guards `resolution`'s mint -- and, under
       * `-Dermine.splitKey=true`, `splitConcrete`'s: every partition of `v` whose
       * right-hand side is a lone variable, indexed by its concrete part.  This IS
       * `Rowpartition.Resolved G v K` (`∃ z, mk v {z} K ∈ G`) restricted to the `v` at
       * hand.  It consults `proc` and `incm`, i.e. the whole current system except the
       * partition being dequeued (which `incorporateAll` returns to `proc` only after this
       * call) and except the current batch (which `findResolvent`'s `s` argument adds for
       * `resolution`; `splitConcrete` runs before any batch partition exists, so it passes
       * `Set()`).  The dequeued partition can never be a witness for its own key: a
       * witness has a single abstract variable and `resolution`/`splitConcrete` reach the
       * lookup only with a lone variable on each side / with `2 ≤ |abstr|` respectively.
       * Built at most once per call, and only when one of the two flags is on -- the
       * lambda below is never invoked otherwise, so this costs nothing when both are
       * off. */
      lazy val resolvents: Map[Fields, TypeVar] = {
        def add(m: Map[Fields, TypeVar], p: Partition): Map[Fields, TypeVar] = p match {
          case Partition(u, RHS(Single(w), con), _) if u == v => m + (con -> w)
          case _                                             => m
        }
        incm.foldLeft(proc.foldLeft(Map[Fields, TypeVar]())(add))(add)
      }
      def findResolvent(s: Set[Partition])(k: Fields): Option[TypeVar] =
        s.collectFirst {
          case Partition(u, RHS(Single(w), con), _) if u == v && con == k => w
        } orElse resolvents.get(k)
      /* Stage 5 (`tracker/satterm/KEYED-ROW-STAGE5.md`), the CONCRETE-ROW reverse lookup
       * that widens both mint guards under `-Dermine.splitRow` / `-Dermine.resRow`.  One
       * pass over `proc ++ incm` collecting every BARE CONCRETE partition `u <- ((|con|))`
       * (`RHS(abs, con)` with `abs.isEmpty`) into `con -> u`, and, on the way, `v`'s own
       * concrete row.  This is `KeyedRow.ConcCarried`'s pair of memberships:
       * `mk v ∅ C ∈ G` is `myRow = Some(C)` and `mk w ∅ (C \ k) ∈ G` is `rows.get(C -- k)`.
       *
       * WHERE THE CONCRETE ROW LIVES.  A nonempty concrete row is a bare partition in the
       * queues and nothing else -- `makeConcrete` never touches the `SubstEnv` and returns
       * `Partition(v, RHSConcr(fs))` to `proc`.  The EMPTY row is the exception:
       * `makeEmpty` writes `v := ConcreteRho(∅)` into the `SubstEnv` and deletes every
       * partition mentioning `v`, so an already-emptied variable cannot be a carrier here
       * (one still queued in `incm` can).  See the long note at `def splitConcrete`.
       *
       * `k ⊆ C` is asked explicitly, which `KeyedRow.K2RowApp` does not (it gets it from
       * the model); on satisfiable input `ensureSuperset` makes the two agree, and on
       * unsatisfiable input asking it can only REFUSE a reuse the Lean would take, never
       * take one it would not.  So every firing is a `K2RowApp`.
       *
       * Like `resolvents` this ranges over `proc ++ incm`, i.e. the whole current system
       * minus the dequeued premise; unlike `findResolvent` it does NOT consult the current
       * batch `s`, so `resolution`'s use of it sees one partition set less than its
       * resolvent lookup does.  That direction is safe (fewer reuses, never a wrong one).
       * Both the map and the lambda are built only when a flag is on: with both off,
       * `noConcRow` is passed and the lazy val is never forced, so the default costs one
       * unforced `lazy val` cell per `learnPartitions` call and nothing else. */
      lazy val concRows: (Map[Fields, TypeVar], Option[Fields]) = {
        def add(m: (Map[Fields, TypeVar], Option[Fields]), p: Partition)
            : (Map[Fields, TypeVar], Option[Fields]) = p match {
          case Partition(u, RHS(abs, con), _) if abs.isEmpty =>
            (m._1 + (con -> u), if (u == v) some(con) else m._2)
          case _ => m
        }
        incm.foldLeft(proc.foldLeft((Map[Fields, TypeVar](), none[Fields]))(add))(add)
      }
      def findConcRow(k: Fields): Option[TypeVar] = {
        val (rows, myRow) = concRows
        myRow.filter(k subsetOf _).flatMap(c => rows.get(c -- k))
      }
      val concRow: Fields => Option[TypeVar] =
        if (GenRules.splitRow || GenRules.resRow) findConcRow else noConcRow
      /* Stage 7 (`tracker/satterm/KEYED-EMPTY-STAGE7.md`), the EMPTY-ROW lookup that widens
       * both mint guards once more under `-Dermine.emptyRow`.  It is `findConcRow` with the
       * complement pinned to the EMPTY row -- the one row the fold above can never find a
       * carrier for, because `makeEmpty` deletes every partition mentioning the variable it
       * empties and keeps the fact in the `SubstEnv` (`instantiateType(v, ConcreteRho(∅))`).
       * So the second source here is that environment, read exactly where the compiler
       * writes it, which is the Lean's `KeyedEmpty.makeEmptyE` -- the step with `v <- ()`
       * RETAINED -- implemented literally.
       *
       * The first test, `myRow.filter(c => (k subsetOf c) && (c -- k).isEmpty)`, is
       * `findConcRow`'s two tests with `C \ k = ∅`, i.e. `C = k`: the premise's left-hand
       * side is concrete with exactly the premise's own concrete part, so its group is
       * FORCED empty (`KeyedEmpty.group_forced_empty`).  The second, `rows.get(∅)`, is the
       * carrier a queue still holds -- with `-Dermine.splitRow` on, that case has already
       * been taken by the branch above, so this arm matters only when the empty-row flag is
       * used alone.  The third, `envEmptyRow`, is the retained fact.
       *
       * TWO HONEST DIFFERENCES from Stage 5's lookup, both recorded in the report's
       * faithfulness note.  (i) `hm.types` holds the empties of the WHOLE inference, not of
       * this solve's system, so unlike `concRows` this lookup is an UPPER bound on the
       * Lean's `EmptyKnown G`: it can answer where the current system has no carrier.  That
       * costs nothing in soundness -- what the branch emits is entailed by the premise
       * alone, with no carrier -- but it means a firing is a `K2RowApp` of the system PLUS
       * the environment, which is the state the Lean models (`KeyedEmptyScala`).  (ii) the
       * scan returns the FIRST empty instantiation the map iterates over; which one it is
       * cannot reach the output, because the branches below do not mention the carrier.
       *
       * COST: the scan is `hm.types.collectFirst`, forced at most once per `learnPartitions`
       * call and only after the two cheap tests above have passed, so with the flag off (and
       * with it on but the complement nonempty) nothing is allocated or walked.  It is the
       * same order as the map rebuild `instantiateType` already does on every instantiation. */
      lazy val envEmptyRow: Option[TypeVar] =
        hm.types.collectFirst { case (z, ConcreteRho(_, fs)) if fs.isEmpty => z }
      def findEmptyRow(k: Fields): Option[TypeVar] = {
        val (rows, myRow) = concRows
        myRow.filter(c => (k subsetOf c) && (c -- k).isEmpty)
             .flatMap(_ => rows.get(Set[Name]()) orElse envEmptyRow)
      }
      val emptyRow: Fields => Option[TypeVar] =
        if (GenRules.emptyRow) findEmptyRow else noConcRow
      proc.foldLeft[Set[Partition]](
           splitConcrete(v, rhs1.abstr, rhs1.concr, findRHS(incm, proc, Set()),
                         findResolvent(Set()), concRow, emptyRow)
         ){
           case (s, Partition(u, rhs2, _)) =>
             if(u == v) {
               val rps = resolution(v, rhs1, rhs2, findResolvent(s), concRow, emptyRow)
               val cps = cancellation(v, rhs1, rhs2)
               val dps = if(!GenRules.disjRule) Nil else proc.toList.flatMap {
                 case Partition(w, rhs3, _) if w != v => disjunction(rhs3, rhs1, rhs2) ++ disjunction(rhs3, rhs2, rhs1)
                 case _                               => Set[Partition]()
               }
               (s ++ rps ++ cps ++ dps)
             }
             else {
               val csps = commonSubexpression(v, rhs1, u, rhs2, findRHS(incm, proc, s))
               val sps  = substitution(v, rhs1, u, rhs2)
               val dps  = if(!GenRules.disjRule) Nil else proc.toList.flatMap {
                 case Partition(w, rhs3, _) =>
                   if(w == u && rhs2 != rhs3)
                     disjunction(rhs1, rhs2, rhs3) ++ disjunction(rhs1, rhs3, rhs2)
                   else if(w == v && rhs1 != rhs3)
                     disjunction(rhs2, rhs1, rhs3) ++ disjunction(rhs2, rhs3, rhs1)
                   else
                     Set[Partition]()
               }
               (s ++ csps ++ sps ++ dps)
             }
         }
    }

  def simpleSubst(v: TypeVar, u: TypeVar, w: TypeVar)(r : Partition): PQueue = {
    def f(z: TypeVar) = if(z == v || z == u) w else z
    r match {
      case Partition(z, RHS(abs,con), inf) => {
        def g(b: Boolean): Int = if(b) 1 else 0

        val multi = g(abs contains v) + g(abs contains u)
                  + g(abs.contains(w) && (w != v) && (w != u))

        if(multi > 1)
          PQueue(Partition(f(z), RHS(abs - v - u - w, con), inf),
                 Partition(w, RHSEmpty(), DeDuplication))
        else
          PQueue(Partition(f(z), RHS(abs map f, con), inf))
      }
    }
  }

  /* This handles unification of two variables, once the rules have
   * determined that such a thing should happen. This is another
   * destructive procedure, as all references to one should be
   * replaced with the other in our constraints.
   */
  // @throws SubstException
  def unify(v: TypeVar, u: TypeVar, incm: PQueue, proc: PQueue)(implicit hm: SubstEnv): (PQueue, PQueue) =
    if (v == u) (incm, proc) else instantiate(v, u, incm, proc)

  def replace(v: TypeVar, u: TypeVar, p: Partition): PQueue = p match {
    case Partition(z, RHS(abs, con), inf) =>
      def f(w: TypeVar) = if(w == v) u else w
      val partp = Partition(f(z), RHS(abs.map(f _), con), inf)
      if(abs.contains(v) && abs.contains(u))
        PQueue(partp, Partition(u, RHSEmpty(), DeDuplication))
      else PQueue(partp)
  }

  // @throws SubstException
  def instantiate(v: TypeVar, u: TypeVar, incm: PQueue, proc: PQueue)(implicit hm: SubstEnv): (PQueue, PQueue) = {
    val (pps, nproc) = proc partition ruleInvolves(v)
    val (qps, nincm) = incm partition ruleInvolves(v)
    val nps = pps ++ qps
    instantiateType(v, VarT(u))
    (nps.foldLeft(nincm)((nq, p) => nq ++! replace(v,u,p)), nproc)
  }

  /* Empty is a somewhat special concrete substitution. It's probably best to
   * handle it separately.
   *
   * This handles the partition empty rule:
   *
   *   a <-
   *   a <- x+
   *  ---------
   *   (x <-)+
   *
   * as well as a special case of one of the incompatibility rules: a row
   * cannot both be empty and have fields.
   *
   * This 'destructively' modifies both cs and rs to incorporate the fact that
   * v has been made empty, collecting up additional rules that are a
   * consequence of v being made empty.
   *
   * This also informs the normal unifier that v is the empty row.
   */
  // @throws SubstException
  def makeEmpty(v: TypeVar, incm: PQueue, proc: PQueue)(implicit hm: SubstEnv, tml: Located): (PQueue, PQueue) = {
    def aux(s: Set[Partition], rhs: RHS): Set[Partition] = rhs match {
      case RHSEmpty()      => s
      // The emptied variable is EXCLUDED from the propagation: a self-referential
      // definition v <- (v, w) would otherwise manufacture `v <- ()` for v itself, which is
      // re-enqueued and dequeued into a SECOND makeEmpty(v), and instantiateType's `die`
      // rejects the (no-op) re-binding -- "panic: reinstantiated type v to
      // ConcreteRho(-,Set()) but it was already bound to ConcreteRho(-,Set())" on a
      // SATISFIABLE program, at whichever id bases the queue order lets the second step run
      // (11 of 100 for tracker/repro/satterm/seeds/PANIC3.json; the self-reference need not
      // be in the input -- the loop derives it).  `selfSubstitution` above uses (abstr - v)
      // for the same reason.  Sound: `v <- ()` is recorded by this very call's
      // instantiateType below.
      case RHSAbstr(abstr) => s ++ (abstr - v).map(u => Partition(u, RHSEmpty(), PartitionEmpty))
      case _               => tml.die("Incompatible instantiations of '" + v + "'")
    }

    val (pps, procd) = proc partition ruleInvolves(v)
    val (qps, incmg) = incm partition ruleInvolves(v)

    val nps = (qps ++ pps).foldLeft(Set[Partition]()){
      case (s, Partition(u, rhs, inf)) =>
          if(u == v) aux(s, rhs)
          else s + Partition(u, rhs - v, inf)
    }

    if (v.ty == Skolem) tml.die(v.report("Cannot unify skolem variable with empty relation", v.toString))

    instantiateType(v, ConcreteRho(Loc.builtin, Set()))
    (incmg ++! trim(nps,procd), procd)
  }

  /* Given a substitution, a partition set, and a set of incoming rules,
   * computes all the rules that need to be added due to the substitution.
   */

  // @throws SubstException
  def subPartitions(v: TypeVar, sub: RHS, proc: PQueue, incm: PQueue)(implicit tml: Located): Set[Partition] = {
    def reduce(s: Set[Partition], r: Partition) = r match {
      case Partition(u, rhs, old) if rhs contains v =>
        val (nrhs, es) = rhs substitute (v, sub)
        (s ++ es.map(w => Partition(w, RHS(), DeDuplication)) + Partition(u, nrhs, old))
      case Partition(u, rhs, _) => s
    }
    incm.filter(_._1 != v).foldLeft(proc.foldLeft(Set[Partition]())(reduce))(reduce)
  }

  /* Handles the case where we have a concrete substitution for a variable.
   */
  def makeConcrete(v: TypeVar,
                   fs: Fields,
                   incm: PQueue,
                   proc: PQueue)(implicit hm: SubstEnv, tml: Located): (PQueue,PQueue) = {
    val rhss = (proc.toSet.filter(p => p._1 == v).map(_._2)
             ++ incm.toSet.filter(p => p._1 == v).map(_._2))
      // Check superset compatibility for the concrete instantiation
    rhss.foreach {
      /* S2 layer (i): a BARE definition of `v` is an EQUATION, not a lower
       * bound.  Only reachable with `-Dermine.rowSound.bare=true`; with the
       * flag off this is `ensureSuperset` on every definition, as shipped. */
      case RHS(abstr, concr) if GenRules.rowSoundBare && abstr.isEmpty =>
        if (concr != fs)
          RowTrace.rowSound("bare", v.loc.toString,
            v.toString + "\t" + concr.toList.map(_.toString).sorted.mkString(",") +
            "\t" + fs.toList.map(_.toString).sorted.mkString(","))
        ensureExactly(v.loc, concr, fs)
      case RHS(_, concr) => ensureSuperset(v.loc, concr, fs)
    }
    val can = rhss.foldLeft(Set[Partition]()){
      case (s, rhs) => s ++ cancellation(v, RHSConcr(fs), rhs)
    }
    val (nincm, nproc) = destructiveSub(v, RHSConcr(fs), incm, proc)
    (nincm ++! can, nproc + Partition(v, RHSConcr(fs)))
  }

  /* Given a rule, a set of incoming rules, and a partition set, computes the
   * partition set and new set of incoming rules appropriate for destructively
   * substituting rhs for v.
   */
  // @throws SubstException
  def destructiveSub(v: TypeVar,
                     rhs: RHS,
                     incm: PQueue,
                     proc: PQueue)(implicit hm: SubstEnv, tml: Located): (PQueue, PQueue) = {
    val (pps, procd) = proc partition(p => p._1 == v)
    val (qps, incmg) = incm partition(p => p._1 == v)
    val keep = !((pps union qps).isEmpty)
    val srs = (pps ++ qps).map(_._2).foldLeft(subPartitions(v, rhs, procd, incmg)){
      case (s, rhs) => s ++ subPartitions(v, rhs, procd, incmg)
    }
    val p : Partition => Boolean = { case Partition(u, rhs, _) => u != v && !rhs.contains(v) }
    val nproc0 = if((srs isEmpty) && keep) proc else procd filter p
    val nincm0 = if((srs isEmpty) && keep) incm else incmg filter p
    /* Keep the DEFINITIONS of `v` that have two or more abstract parts (2026-09-02,
     * tracker/TICKET-substitution-gap.md).  The filter above used to drop every partition
     * with `v` on the left along with the mentions it rewrites.  A definition with ONE
     * abstract part is re-expressed by `makeConcrete`'s cancellation (`v <- (x, D)`,
     * `v <- C`  ==>  `x <- C \ D`); a definition with two or more has no variable-headed
     * form without `v`, so deleting it deleted the NAME `v` for the row `x ++ y`.  Under
     * the cut, `commonSubexpression` only reuses names and never mints, so a partition
     * dequeued later that shares `x ++ y` found nothing to fold against -- and whether it
     * was dequeued before or after the deletion was decided by the queue key, i.e. by the
     * variable ids.  That was the whole of the build-order-dependent published types
     * (`Ai/HeadcountPlan.labelled` and friends).  Keeping the definitions is sound -- they
     * were already in the set (`Rowpartition.NameLoss.concretizeKeep_sound`) -- and
     * restores the fold (`keep_recovers_fact`); measured on the example and stdlib
     * corpora it strengthened four published signatures and weakened none. */
    val keepDefs = !((srs isEmpty) && keep)
    val defs: Partition => Boolean = { case Partition(_, RHS(abs, _), _) => abs.size >= 2 }
    val nproc = if (keepDefs) nproc0 ++ pps.filter(defs) else nproc0
    val nincm = if (keepDefs) nincm0 ++! qps.filter(defs) else nincm0
    (nincm ++! trim(srs,nproc), nproc)
  }

  /*
   * Rules
   */

  /* Cancellation
   *
   *  a <- C* x* z
   *  a <- C* x* D* y*
   *  ----------------
   *     z <- D* y*
   */
  def cancellation(v: TypeVar, rhs1: RHS, rhs2: RHS): Set[Partition] = (rhs1, rhs2) match {
    case (RHS(abs1, con1), RHS(abs2, con2)) => {
      val absInt = abs1 & abs2
      val conInt = con1 & con2

      // v <- C* e* F* x*
      // v <- C* e* G* y*
      val xs = abs1 -- absInt
      val ys = abs2 -- absInt
      val fs = con1 -- conInt
      val gs = con2 -- conInt

      if(fs.isEmpty && xs.size == 1)
        Set(Partition(xs.head, RHS(ys, gs), Cancellation))
      else if (gs.isEmpty && ys.size == 1)
        Set(Partition(ys.head, RHS(xs, fs), Cancellation))
      else
        Set()
    }
  }

  /* Resolution
   *
   *    a <- C+ D* x
   *    a <- y  D* E+
   *   ---------------
   *   a <- C+ D* E+ z  (z fresh)
   *      x <- E+ z
   *      y <- C+ z
   */
  /* The resolvent lookup that guards the mint, under `-Dermine.resGuard=true`.
   *
   * `resolvent(K)` answers "does the environment already name the row `v \ K`?".  The
   * first conclusion, `v <- (z, K)` with `K = concr1 ++ concr2`, IS that naming: it says
   * exactly `z = v \ K`.  So if a partition of that shape is already present, its
   * variable is FORCED EQUAL to the one this rule would mint -- `Rowpartition.ResGuard`,
   * `resolvent_unique` -- and reusing it loses nothing (`guard_loses_nothing`).
   *
   * Note `fresh` is still called in the guarded branch, at the same point.  That keeps
   * the `Supply` sequence identical in both modes, so a guarded run and an unguarded run
   * differ only in the partitions they derive, never in variable numbering.
   *
   * CORRESPONDENCE WITH `Rowpartition/KeyedRow.lean` (`-Dermine.resRow`, DEFAULT OFF;
   * Stage 5, `tracker/satterm/KEYED-ROW-STAGE5.md`).  Write `C = concr1`, `D = concr2`,
   * `K = C ∪ D = all`; the premises are `v <- (x, C)` and `v <- (y, D)` with `C \ D ≠ ∅`
   * and `D \ C ≠ ∅` -- exactly `ResGuard.ResPair G v x y C D`.  The three branches are:
   *
   *   reuse (shipped, `resGuard`)   `resolvent(all) = Some(w)`, i.e. `mk v {w} K ∈ G`.
   *       Emits `resReuseResult` = `x <- (w, D \ C)`, `y <- (w, C \ D)` -- which is
   *       `bots = concr2 -- int` and `tops = concr1 -- int` below.  `GResStep.reuse`.
   *   concrete-row reuse (NEW)      `resRow` and `concRow(all) = Some(w)`, i.e.
   *       `mk v ∅ F ∈ G` and `mk w ∅ (F \ K) ∈ G` -- exactly the premises of
   *       `KeyedRow.K2ResStep.row`, which emits the SAME `resReuseResult`.  Entailed:
   *       `K2ResStep.row_models_iff` (`conc_lone_sat` manufactures `v <- (w, K)` out of
   *       the two concrete definitions, then `ResGuard.reuse_sat` draws both conclusions).
   *   mint (otherwise)              `resResult`, `K2ResStep.mint`; its guard is then
   *       `¬ Carried G v K`, and `K2ResStep.mint_toGRes` says every such mint is a shipped
   *       guarded mint, so the branch only ever replaces mints.
   *
   * The `K ⊆ F` side condition and the note on where a concrete row actually lives are at
   * `def splitConcrete` and at `learnPartitions`' `concRows`; `concRow` here is the same
   * lookup, at the RESOLVENT row `F \ K` instead of the split's `C \ concr`.  `fresh` is
   * still drawn before the match, so the reuse draws no id of its own; the run's TOTAL draw
   * count can still fall, because fewer derived partitions means fewer calls to this rule.
   *
   * ONE MORE DIFFERENCE FROM `findResolvent`, in the safe direction: `concRow` does NOT
   * consult the current batch `s`, only `proc ++ incm`.  So this branch sees one partition
   * set less than the shipped resolvent lookup does; that can only refuse a reuse, never
   * take a wrong one.
   *
   * CORRESPONDENCE WITH `Rowpartition/KeyedEmpty.lean` (`-Dermine.emptyRow`, DEFAULT OFF;
   * Stage 7, `tracker/satterm/KEYED-EMPTY-STAGE7.md`).  A FOURTH branch, taken when both
   * lookups above miss and the RESOLVENT row is EMPTY:
   *
   *   empty-row reuse   `emptyRow` and `emptyRow(all) = Some(z)`, i.e. `mk v ∅ F ∈ G` with
   *       `F = all` (so the resolvent row `F \ all` is `∅`) and some `mk z ∅ ∅` known -- in
   *       the queues or in the `SubstEnv`, where `makeEmpty` retained it.  That is
   *       `KeyedRow.K2ResStep.row` at the carrier of the empty row, on a `makeEmptyE` image.
   *   The conclusions are the reuse's, `x <- (z, bots)` and `y <- (z, tops)`, with the
   *       carrier's row substituted in: `z` denotes `∅`, so they are the BARE CONCRETE
   *       `x <- ((|bots|))` and `y <- ((|tops|))`, which is what the branch emits.  As in the
   *       split, the carrier is not mentioned -- it has left the queues, and a partition
   *       about it would reach `makeEmpty` twice.  Entailed by the premises alone:
   *       `v <- (x, C)` with `v <- ((|F|))` forces `rho x = F \ C`, which is `D \ C = bots`
   *       when `F = C ∪ D` (`KeyedEmptyScala.res_empty_forced`, `res_empty_F`).  As in the
   *       split, one step here is TWO steps of `KeyedEmpty.K3ELoopStep`
   *       (`KeyedEmptyScala.resEmptyReuse_compose`, `resEmpty_two_steps`), the adequacy for
   *       the whole rule is `scalaEmptyRes_run` and the bound is `scalaEmptyRes_bounded`.
   *       It is again what the DEFAULT reaches the long way round -- mint `z`, then
   *       cancellation derives `z <- ()` and `makeEmpty z` substitutes it into both
   *       conclusions. */
  def resolution(v: TypeVar, rhs1: RHS, rhs2: RHS,
                 resolvent: Fields => Option[TypeVar] = _ => none,
                 concRow: Fields => Option[TypeVar] = _ => none,
                 emptyRow: Fields => Option[TypeVar] = _ => none)(implicit su: Supply): Set[Partition] =
    if (!GenRules.resolves) Set() else (rhs1, rhs2) match {
    case (RHS(Single(x), concr1), RHS(Single(y), concr2)) =>
      val z = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))
      val int = concr1 & concr2
      val tops = concr1 -- int
      val bots = concr2 -- int
      if(tops.isEmpty || bots.isEmpty) Set() // Such cases are handled by cancellation
      else {
        val all = concr1 ++ concr2
        (if (GenRules.resGuard) resolvent(all) else none) match {
          case Some(w) =>
            // REUSE: `v <- (w, all)` is already present, so emit only the two
            // conclusions about the lone variables.  Entailed by the environment:
            // `Rowpartition.ResGuard.res_reuse_entails`.
            Set(Partition(x, RHS(Set(w), bots), Resolution),
                Partition(y, RHS(Set(w), tops), Resolution))
          case None =>
            (if (GenRules.resRow) concRow(all) else none) match {
              case Some(w) =>
                // CONCRETE-ROW REUSE (Stage 5): `v <- ((|F|))` and `w <- ((|F \ all|))` are
                // both present, so `w` already denotes the resolvent `v \ all`.  Same two
                // conclusions as the reuse above.  Entailed: `KeyedRow.K2ResStep.row_models_iff`.
                Set(Partition(x, RHS(Set(w), bots), ResolutionRow),
                    Partition(y, RHS(Set(w), tops), ResolutionRow))
              case None =>
                (if (GenRules.emptyRow) emptyRow(all) else none) match {
                  case Some(_) =>
                    // EMPTY-ROW REUSE (Stage 7): `v <- ((|F|))` with `F = all`, so the
                    // resolvent row is `∅` and some `z <- ()` is known.  The two conclusions
                    // of the reuse with `z` denoting `∅` are these bare concrete ones; the
                    // carrier is not mentioned, and nothing is minted.
                    Set(Partition(x, RHSConcr(bots), ResolutionEmpty),
                        Partition(y, RHSConcr(tops), ResolutionEmpty))
                  case None =>
                    Set(Partition(v, RHS(Set(z), all), Resolution),
                        Partition(x, RHS(Set(z), bots), Resolution),
                        Partition(y, RHS(Set(z), tops), Resolution))
                }
            }
        }
      }
    case _ => Set()
  }

  // @throws SubstException
  def subBody(v: TypeVar, rhs1: RHS, u: TypeVar, rhs2: RHS)(implicit tml: Located): Set[Partition] =
    if(rhs2 contains v) {
      val (nrhs, es) = rhs2 substitute (v, rhs1)
      (es.map(v => Partition(v, RHS(), DeDuplication)) + Partition(u, nrhs, Substitution))
    } else Set()

  /* Substitution
   *
   *  a <- D* b x*
   *  b <- E* y*
   *  ------------
   *  a <- D* E* x* y*
   */
  // @throws SubstException
  def substitution(v: TypeVar, rhs1: RHS, u: TypeVar, rhs2: RHS)(implicit tml: Located): Set[Partition] =
    subBody(v, rhs1, u, rhs2) ++ subBody(u, rhs2, v, rhs1)

  /* Common subexpression
   *
   *  a <- C* E* x++ y*
   *  b <- D* E* x++ z*
   *  -----------------
   *   w <- x++          (w fresh)
   *   a <- C* E* w y*
   *   b <- D* E* w z*
   */

  def commonSubexpression(v: TypeVar, rhs1: RHS, u: TypeVar, rhs2: RHS, rhss: RHS => Option[TypeVar])(implicit su: Supply): Set[Partition] =
    (rhs1, rhs2) match {
      case (RHS(abstr1, concr1), RHS(abstr2, concr2)) =>
        val int = abstr1 & abstr2
        val rhsCommon = RHSAbstr(int)
        if(int.size < 2) Set()
        else rhss(rhsCommon) match {
          case Some(z) =>
            Set(Partition(v, RHS((abstr1 -- int) + z,concr1), CommonSubexpression),
                Partition(u, RHS((abstr2 -- int) + z,concr2), CommonSubexpression))
          case None =>
            if(rhs1 == rhsCommon)
              Set(Partition(u, RHS((abstr2 -- int) + v, concr2), CommonSubexpression))
            else if(rhs2 == rhsCommon)
              Set(Partition(v, RHS((abstr1 -- int) + u, concr1), CommonSubexpression))
            else if (!GenRules.cseMints) Set()
            else {
              val z = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))
              Set(Partition(z, rhsCommon, CommonSubexpressionMint),
                  Partition(v, RHS((abstr1 -- int) + z, concr1), CommonSubexpressionMint),
                  Partition(u, RHS((abstr2 -- int) + z, concr2), CommonSubexpressionMint))
            }
        }
    }

  /* Disjunction
   * r1 <- A* a*       P* z+ C* c* S* s*
   * r2 <- A* a* R* r*       C* c* T* t*
   * r2 <- A* a* R* r* P* z+    u+ U*
   * C* c* non-empty
   * --------------------------------------
   * u+ <- C* c* v (v fresh)
   */
  def disjunction(rhs1: RHS, rhs2: RHS, rhs3: RHS)(implicit su: Supply): Set[Partition] = {
    val RHS(abs1, con1) = rhs1
    val RHS(abs2, con2) = rhs2
    val RHS(abs3, con3) = rhs3

    val conAll = con1 intersect con2 intersect con3
    val absAll = abs1 intersect abs2 intersect abs3
    val conC = (con1 intersect con2) -- conAll
    val absc = (abs1 intersect abs2) -- absAll
    val absr = (abs2 intersect abs3) -- absAll
    val absz = (abs1 intersect abs3) -- absAll
    val absu = abs3 -- absz -- absr -- absAll

    val v = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))

    val r : Set[Partition] = if(absz.isEmpty || (conC.isEmpty && absc.isEmpty)) Set()
            else absu.size match {
              case 0 => Set()
              case 1 =>
                val u = absu.head
                Set(Partition(u, RHS(absc + v, conC), Disjunction))
              case _ =>
                val us = fresh(Loc.builtin, none, Ambiguous(Free), Rho(Loc.builtin))
                Set(Partition(us, RHSAbstr(absu), Disjunction), Partition(us, RHS(absc + v, conC), Disjunction))
            }
//    if(r.nonEmpty) {
//      System.err.println("RHS1: " + rhs1)
//      System.err.println("RHS2: " + rhs2)
//      System.err.println("RHS3: " + rhs3)
//      System.err.println("Inferred")
//      r.foreach(System.err.println(_))
//      System.err.println("-----")
//    }
    r
  }

  /* ------------------------------------------------------------------ *
   * Per-concrete-label refutation.                                       *
   *                                                                      *
   * A partition `v <- (u1..un, C)` says the parts are pairwise disjoint   *
   * and union to v.  Project onto a single label L: at most one part      *
   * carries L, and v carries L iff some part does.  That is a boolean     *
   * constraint over the bits [L in x]; a ConcreteRho pins its bit and     *
   * unit propagation does the rest.  A clash at any ONE label refutes the *
   * whole set, since every solution induces a consistent assignment.      *
   *                                                                      *
   * This rule is REFUTATION-ONLY.  It emits no partition and mints no     *
   * variable, so it cannot feed the saturation loop and cannot change any *
   * type that is inferred for an accepted program -- the property that    *
   * makes it usable where `disjunction` is not.  It ranges only over      *
   * labels that occur in some ConcreteRho, so a fully abstract helper     *
   * signature has no labels to check and is untouched.                    *
   *                                                                      *
   * It propagates without case splitting, hence is linear per label and   *
   * INCOMPLETE by construction: deciding these systems in general is      *
   * Schaefer's one-in-three problem.  Refusing to search is what makes    *
   * the failure mode deterministic.                                       *
   * ------------------------------------------------------------------- */
  /** The first label at which propagation refutes `ps`: the label, the partition (by its
    * left-hand variable) whose constraint the propagation found violated, and the reason.
    * The partition is what lets the caller blame ONE input constraint rather than any that
    * happens to mention the label. */
  def labelClash(ps: List[(TypeVar, RHS)]): Option[(Name, TypeVar, String)] = {
    val labels: Set[Name] = ps.foldLeft(Set[Name]()) { case (s, (_, r)) => s ++ r.concr }
    labels.view.flatMap(l => checkLabel(ps, l).map { case (v, m) => (l, v, m) }).headOption
  }

  /** Unit-propagate the bits `[l in x]`; Some((v, msg)) means a contradiction, detected
    * while processing the partition of `v`. */
  private def checkLabel(ps: List[(TypeVar, RHS)], l: Name): Option[(TypeVar, String)] = {
    var bits    = Map[TypeVar, Boolean]()
    var changed = true
    var clash: Option[(TypeVar, String)] = None
    var at: TypeVar = null

    def note(m: => String): Unit = if (clash.isEmpty) clash = Some((at, m))
    def setVar(v: TypeVar, b: Boolean, why: => String): Unit = bits.get(v) match {
      case Some(b0) => if (b0 != b) note(why)
      case None     => bits = bits + (v -> b); changed = true
    }

    while (changed && clash.isEmpty) {
      changed = false
      for ((v, RHS(abstr, concr)) <- ps if clash.isEmpty) {
        at = v
        val conBit  = concr contains l
        val absList = abstr.toList
        val known   = absList.map(bits.get)
        val ones    = known.count(_ == Some(true)) + (if (conBit) 1 else 0)
        val unknown = absList.filter(!bits.contains(_))

        if (ones > 1)
          note("two parts of one partition both contain it")
        else {
          if (ones == 1) {
            // exactly one part carries l: the whole does, every other part does not
            setVar(v, true, "a part contains it but the whole does not")
            // NB `unknown` was computed BEFORE the line above, so when `v` is a part of
            // its own partition it is still listed here and this loop sets it false
            // after setting it true.  That is the RIGHT conclusion -- a variable that is
            // a part of its own partition is forced empty -- but it must not report an
            // empty explanation, which is what the message below used to be.
            for (u <- unknown) setVar(u, false, "two parts of one partition both contain it")
          }
          if (bits.get(v) == Some(false)) {
            if (conBit) note("a part contains it but the whole does not")
            for (u <- unknown) setVar(u, false, "a part contains it but the whole does not")
          }
          if (ones == 0 && unknown.isEmpty)
            setVar(v, false, "the whole contains it but no part does")
          if (bits.get(v) == Some(true) && ones == 0) unknown match {
            case Nil      => note("the whole contains it but no part can")
            case u :: Nil => setVar(u, true, "the whole contains it but no part can")
            case _        => ()
          }
        }
      }
    }
    clash
  }

  /* ------------------------------------------------------------------ *
   * S2 layer (iii): the COMPLETE per-label decision.                     *
   * `-Dermine.rowSound.decide` (default OFF).                            *
   * ------------------------------------------------------------------ *
   * `checkLabel` above is unit propagation: SOUND (a clash refutes the
   * system -- `Rowpartition/LabelProp.lean`'s `refuted_unsat`) but NOT
   * COMPLETE.  Every one of the ten seeds on which the shipped compiler
   * accepts an unsatisfiable row system passes it, because each needs a CASE
   * SPLIT (`tracker/loopmodel/S1-REVIEW.md` sections 2.3-2.6, Appendix B).
   *
   * WHAT IS DECIDED.  A partition `v <- (u1..uk, C)` says the parts are
   * pairwise disjoint and union to `v`.  Project onto ONE label `l`: with bits
   * `b[x] = [l in rho x]` and `c = [l in C]`, the constraint is exactly
   *
   *     b[u1] + ... + b[uk] + c  <=  1        and   b[v] = that sum.
   *
   * The system is satisfiable IFF every label's boolean problem is (a model is
   * assembled label by label; a label mentioned in no concrete set has the
   * all-false model, so only the MENTIONED labels need deciding -- the same
   * label range `labelClash` walks).  The bit problem is 1-in-3-SAT when a
   * whole is known present, hence NP-complete, hence the search below and the
   * budget on it.
   *
   * HOW.  DPLL: `propagate` is `checkLabel`'s fixpoint made worklist-driven
   * and re-using its five rules and its five messages verbatim, so a
   * refutation that propagation alone would have found is reported in exactly
   * the words the shipped check uses; `search` then branches on the first
   * unassigned bit (FALSE first) and recurses.  A branch that assigns every
   * bit without a clash is VERIFIED against every partition directly before
   * SAT is returned -- so "passes" means "a model was exhibited and checked",
   * not "no rule complained".  If that verification ever fails the answer is
   * NO VERDICT, never UNSAT: a bug in the propagator can then cost a
   * refutation but can never cause a false rejection.
   *
   * BUDGET.  `budget` bounds the DECISION NODES per label.  On exhaustion the
   * result is `LabelNoVerdict` and nothing is refuted, which is why the
   * theorem in `S2-DESIGN.md` carries "the budget was not exhausted" as a
   * hypothesis and why exhaustion is counted and traced rather than silent.
   */
  sealed abstract class LabelVerdict
  /** Every mentioned label's problem has a model, and each model was checked. */
  case object LabelSat extends LabelVerdict
  /** No model at `label`; `at` is the partition (by its left-hand variable) at
    * which the search's first clash was detected, for blame. */
  case class LabelRefuted(label: Name, at: TypeVar, why: String) extends LabelVerdict
  /** The search stopped without an answer.  Refutes nothing.  `exhausted` is
    * true when a BUDGET ran out (per label or per solve) and false when the
    * fail-safe fired -- a total assignment that failed its own check.  The two
    * are counted separately: a counter named `budgetHits` must not silently
    * absorb a propagator bug (S2 review V-8). */
  case class LabelNoVerdict(label: Name, why: String, exhausted: Boolean) extends LabelVerdict

  /** `verdict`, the decision nodes spent, and how many labels were decided. */
  case class DecideResult(verdict: LabelVerdict, nodes: Long, labels: Int)

  /** Decide every mentioned label.  Returns the FIRST refutation in label
    * order if there is one, else the first no-verdict, else `LabelSat`.
    *
    * TWO caps, and both can lapse the theorem (`S2-DESIGN.md` §2's hypothesis):
    * `budget` bounds the decision nodes at ONE label, and `solveBudget` bounds
    * their SUM over the whole solve.  The per-solve cap is S2 review V-12: the
    * per-label budget alone bounds the worst case at `#labels x 0.2 s`, which
    * is seconds on a wide solve, and this bounds it once.
    *
    * ORDER (S2 review V-13a): `labels` is a `Set[Name]`, so the iteration is
    * HASH order -- deterministic for a build, not sorted.  It decides only
    * WHICH of several refuting labels is reported, never whether the system is
    * refuted: the loop runs to the first refutation and a refutation at any
    * label is a refutation of the system. */
  def labelDecide(ps: List[(TypeVar, RHS)], budget: Int, solveBudget: Long): DecideResult = {
    val labels: Set[Name] = ps.foldLeft(Set[Name]()) { case (s, (_, r)) => s ++ r.concr }
    var nodes    = 0L
    var refuted: LabelVerdict = null
    var unknown: LabelVerdict = null
    val it = labels.iterator
    while (it.hasNext && (refuted eq null)) {
      val l = it.next()
      if (nodes >= solveBudget) {
        if (unknown eq null)
          unknown = LabelNoVerdict(l, "the solve's decision budget of " + solveBudget +
            " nodes was spent before this field was decided", true)
      } else {
        // never let one label spend more than the solve has left
        val left = solveBudget - nodes
        val cap = if (left < budget.toLong) left.toInt else budget
        val (v, n) = decideLabel(ps, l, cap)
        nodes += n
        v match {
          case LabelSat            => ()
          case r: LabelRefuted     => refuted = r
          case u: LabelNoVerdict   => if (unknown eq null) unknown = u
        }
      }
    }
    val verdict = if (refuted ne null) refuted else if (unknown ne null) unknown else LabelSat
    DecideResult(verdict, nodes, labels.size)
  }

  /** One label's problem, decided completely.  `(verdict, decision nodes)`.
    *
    * BLAME (S2 review V-13b): `firstAt`/`firstWhy` record the FIRST clash seen anywhere in
    * the search and are NOT reset between branches, so a search-refutation's blamed variable
    * need not belong to the branch that closes the proof.  Deliberate, and it changes
    * nothing that is checked: the LABEL is fixed by the caller's loop, the verdict is fixed
    * by the search, and `Subst.solve`'s `rowUnsat` uses the variable only to PREFER one
    * input `Part` over another when several mention the field -- with a fallback that is a
    * real source position either way.  Resetting it per branch would pick a different
    * arbitrary clash, not a better one. */
  private def decideLabel(ps: List[(TypeVar, RHS)], l: Name, budget: Int): (LabelVerdict, Long) = {
    // ---- index the variables in order of FIRST APPEARANCE (so the search is
    // ---- a function of the partition list's order, not of a hash set's).
    val index = new scala.collection.mutable.LinkedHashMap[TypeVar, Int]
    def ix(v: TypeVar): Int = index.getOrElseUpdate(v, index.size)
    val m     = ps.length
    val lhsA  = new Array[Int](m)
    val partA = new Array[Array[Int]](m)
    val conA  = new Array[Boolean](m)
    var i = 0
    ps.foreach {
      case (v, RHS(abstr, concr)) =>
        lhsA(i)  = ix(v)
        partA(i) = abstr.toList.map(ix).toArray
        conA(i)  = concr contains l
        i += 1
    }
    val n    = index.size
    val vars = index.keysIterator.toArray

    if (n == 0) return ((LabelSat: LabelVerdict), 0L)

    // partitions mentioning each variable, so propagation revisits only those
    val occ: Array[Array[Int]] = {
      val b = Array.fill(n)(new scala.collection.mutable.ArrayBuffer[Int]())
      var k = 0
      while (k < m) {
        b(lhsA(k)) += k
        partA(k).foreach(u => if (u != lhsA(k)) b(u) += k)
        k += 1
      }
      b.map(_.toArray)
    }

    val bits   = new Array[Byte](n)   // 0 unknown, 1 true, 2 false
    val trail  = new Array[Int](n)
    var tlen   = 0
    val stack  = new Array[Int](m)
    val queued = new Array[Boolean](m)
    var slen   = 0
    var conflict  = false
    var firstAt   = -1
    var firstWhy: String = null
    var nodes     = 0L
    var budgetOut = false
    var checkFailed = false

    def push(k: Int): Unit = if (!queued(k)) { queued(k) = true; stack(slen) = k; slen += 1 }
    def clearQueue(): Unit = { while (slen > 0) { slen -= 1; queued(stack(slen)) = false } }
    def note(at: Int, why: String): Unit = {
      conflict = true
      if (firstWhy eq null) { firstAt = at; firstWhy = why }
    }
    def assign(u: Int, b: Byte, at: Int, why: String): Unit =
      if (bits(u) == 0) {
        bits(u) = b; trail(tlen) = u; tlen += 1
        val os = occ(u); var j = 0
        while (j < os.length) { push(os(j)); j += 1 }
      } else if (bits(u) != b) note(at, why)

    /* `checkLabel`'s five rules, in `checkLabel`'s order, on the worklist. */
    def propagate(): Unit = {
      while (slen > 0 && !conflict) {
        slen -= 1
        val k = stack(slen); queued(k) = false
        val lhs   = lhsA(k)
        val parts = partA(k)
        val con   = conA(k)
        var ones  = if (con) 1 else 0
        var unkN  = 0
        var j = 0
        while (j < parts.length) {
          val b = bits(parts(j))
          if (b == 1) ones += 1 else if (b == 0) unkN += 1
          j += 1
        }
        if (ones > 1) note(lhs, "two parts of one partition both contain it")
        else {
          // the UNKNOWN parts as of NOW, exactly as `checkLabel` snapshots them
          // before it assigns the whole -- which is what makes a variable that
          // is a part of its own partition come out forced empty.
          val unk = new Array[Int](unkN)
          var u = 0; j = 0
          while (j < parts.length) { if (bits(parts(j)) == 0) { unk(u) = parts(j); u += 1 }; j += 1 }
          if (ones == 1) {
            assign(lhs, 1, lhs, "a part contains it but the whole does not")
            j = 0
            while (j < unkN && !conflict) {
              assign(unk(j), 2, lhs, "two parts of one partition both contain it"); j += 1
            }
          }
          if (!conflict && bits(lhs) == 2) {
            if (con) note(lhs, "a part contains it but the whole does not")
            j = 0
            while (j < unkN && !conflict) {
              assign(unk(j), 2, lhs, "a part contains it but the whole does not"); j += 1
            }
          }
          if (!conflict && ones == 0 && unkN == 0)
            assign(lhs, 2, lhs, "the whole contains it but no part does")
          if (!conflict && bits(lhs) == 1 && ones == 0) {
            if (unkN == 0) note(lhs, "the whole contains it but no part can")
            else if (unkN == 1) assign(unk(0), 1, lhs, "the whole contains it but no part can")
          }
        }
      }
      if (conflict) clearQueue()
    }

    /** A TOTAL assignment, checked against every partition directly. */
    def verify(): Boolean = {
      var k = 0
      var ok = true
      while (k < m && ok) {
        val parts = partA(k)
        var ones = if (conA(k)) 1 else 0
        var j = 0
        while (j < parts.length) { if (bits(parts(j)) == 1) ones += 1; j += 1 }
        if (ones > 1) ok = false
        else if ((ones == 1) != (bits(lhsA(k)) == 1)) ok = false
        k += 1
      }
      ok
    }

    def search(): Boolean = {
      var u = -1
      var z = 0
      while (z < n && u < 0) { if (bits(z) == 0) u = z; z += 1 }
      if (u < 0) {
        val ok = verify()
        if (!ok) checkFailed = true
        return ok
      }
      nodes += 1
      if (nodes > budget) { budgetOut = true; return false }
      var res = false
      var b   = 2                                   // FALSE first, then TRUE
      while (!res && b >= 1 && !budgetOut) {
        val mark = tlen
        conflict = false
        bits(u) = b.toByte; trail(tlen) = u; tlen += 1
        val os = occ(u); var j = 0
        while (j < os.length) { push(os(j)); j += 1 }
        propagate()
        if (!conflict) res = search()
        if (!res) {
          while (tlen > mark) { tlen -= 1; bits(trail(tlen)) = 0 }
          clearQueue()
          conflict = false
        }
        b -= 1
      }
      res
    }

    // ---- root propagation: every partition once ------------------------
    var k = 0
    while (k < m) { push(k); k += 1 }
    propagate()
    val verdict: LabelVerdict =
      if (conflict) LabelRefuted(l, if (firstAt >= 0) vars(firstAt) else vars(0), firstWhy)
      else if (search()) LabelSat
      else if (budgetOut)
        LabelNoVerdict(l, "search budget exhausted after " + nodes + " decisions", true)
      else if (checkFailed)
        LabelNoVerdict(l, "a complete assignment failed its own check; no verdict is claimed", false)
      else
        LabelRefuted(l,
          if (firstAt >= 0) vars(firstAt) else vars(0),
          "no assignment of this field to the parts satisfies every partition" +
          " (complete search, " + nodes + " cases; unit propagation alone does not see it)")
    (verdict, nodes)
  }
}
