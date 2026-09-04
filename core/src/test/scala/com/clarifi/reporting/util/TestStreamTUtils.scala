package com.clarifi.reporting
package util

import scalaz.{State, StreamT}
import State.{modify, state}
import scalaz.syntax.functor._
import org.scalacheck.{Gen, Prop, Properties}
import Prop.{?=, forAll, propBoolean}

object TestStreamTUtils extends Properties("StreamT utilities") {
  property("toStreamT/toIterable round-trip") = forAll {
    (xs: List[Int]) =>
      ?=(StreamTUtils toIterable (StreamTUtils toStreamT xs) toList,
         xs)
  }

  property("runStreamTOut trampolines long streams") = forAll{(n: Short) =>
    val len = (n:Int) - java.lang.Short.MIN_VALUE
    val sstream = StreamT.unfoldM[[a] =>> State[Int, a], Unit, Int](len){n =>
      if (n <= 0) state(None)
      else modify((_:Int) + 2) as Some(((), n - 1))
    }
    val (p, sti) = StreamTUtils.runStreamTOut(sstream, -5)
    val before = p.fulfilled
    val slen = (StreamTUtils toIterable sti).size // run it once
    val after = p.fulfilled
    ((?=(before, len == 0) :| "unfulfilled before iff not empty")
       && (?=(slen, len) :| "length matches")
       && (after :| "fulfilled after")
       && (?=(p.get, len * 2 - 5) :| "output is final state"))
  }

  // ---------------------------------------------------------------------------------
  // Dependency order: the iterative `chop`/`prune`/`dfs`/`postOrder`/`reverseTopSort`
  // against the recursive definitions they replaced.
  //
  // The order is load-bearing -- the module loader and `Constraints.Q.TypeVarGraph` run
  // on it, it feeds the id supply and ids reach published interfaces -- so the property
  // is not "the new code is a topological sort" but "the new code returns EXACTLY what
  // the old code returned".  `Reference` below is the old code, verbatim; it overflowed
  // the stack on a batch module load (TICKET-editor-and-solver-followups.md section 4)
  // because `chop` recursed once per sibling and `postOrder` appended quadratically, and
  // the last two properties here are that regression, at a size the old code cannot do.
  // ---------------------------------------------------------------------------------

  private object Reference {
    import scalaz._
    import scalaz.Scalaz._
    import scalaz.Tree
    import Tree._

    type Forest[A] = Stream[Tree[A]]

    def generate[A](children: A => Stream[A], a: A): Tree[A] =
      node(a, children(a).map(b => generate(children, b)))

    def chop[A](forest: Forest[A]) : State[Set[A], Forest[A]] = forest match {
      case Node(v,ts) #:: us =>
        for {
          s <- init
          a <- if (s contains v) chop(us)
               else for {
                 _  <- put(s + v)
                 as <- chop(ts)
                 bs <- chop(us)
               } yield node(v,as) #:: bs
        } yield a
      case _ => Stream().pure[[a] =>> State[Set[A], a]]
    }

    def prune[A](forest: Forest[A]): Forest[A] = chop(forest) eval Set()

    def dfs[A](children: A => Stream[A], vs: Stream[A]) : Forest[A] =
      prune(vs.map(generate(children,_)))

    def postOrder[A](tree : Tree[A]): Stream[A] = tree match {
      case Node(a,ts) => ts.flatMap(postOrder) ++ Stream(a)
    }

    def reverseTopSort[A](vertices: Stream[A])(children: A => Stream[A]): Stream[A] =
      dfs(children, vertices) flatMap postOrder
  }

  /** A strict rendering of a forest, so two forests can be compared for equality
    * without relying on `Tree`'s `Equal` instance or on stream identity. */
  private case class Shape[A](label: A, kids: List[Shape[A]])
  private def shape[A](t: scalaz.Tree[A]): Shape[A] =
    Shape(t.rootLabel, t.subForest.toList.map(shape))
  private def shapes[A](f: Stream[scalaz.Tree[A]]): List[Shape[A]] = f.toList.map(shape)

  /** 16 vertices and up to a hundred edges: dense, cyclic, with repeated edges and
    * repeated roots, which is where the pruning and the visited-set threading show. */
  private val vertex: Gen[Int] = Gen.choose(0, 15)
  private val graph: Gen[(List[Int], List[(Int, Int)])] =
    for {
      vs <- Gen.listOf(vertex)
      es <- Gen.listOf(Gen.zip(vertex, vertex))
    } yield (vs, es)

  private def childrenOf(edges: List[(Int, Int)]): Int => Stream[Int] = {
    val m = edges.groupBy(_._1).map { case (k, ps) => k -> ps.map(_._2).toStream }
    (v: Int) => m.getOrElse(v, Stream.empty)
  }

  property("reverseTopSort agrees with the recursive definition") = forAll(graph) {
    case (vs, es) =>
      val ch = childrenOf(es)
      ?=(StreamTUtils.reverseTopSort(vs.toStream)(ch).toList,
         Reference.reverseTopSort(vs.toStream)(ch).toList)
  }

  property("dfs builds the same pruned forest") = forAll(graph) {
    case (vs, es) =>
      val ch = childrenOf(es)
      ?=(shapes(StreamTUtils.dfs(ch, vs.toStream)),
         shapes(Reference.dfs(ch, vs.toStream)))
  }

  property("chop threads the same visited set") = forAll(graph, Gen.listOf(vertex)) {
    case ((vs, es), seen) =>
      val ch = childrenOf(es)
      val s0 = seen.toSet
      val fN = vs.toStream.map(StreamTUtils.generate(ch, _))
      val fR = vs.toStream.map(Reference.generate(ch, _))
      ((?=(StreamTUtils.chop(fN) exec s0, Reference.chop(fR) exec s0) :| "final state")
        && (?=(shapes(StreamTUtils.chop(fN) eval s0), shapes(Reference.chop(fR) eval s0))
              :| "pruned forest"))
  }

  property("postOrder agrees with the recursive definition") = forAll(graph) {
    case (vs, es) =>
      val ch = childrenOf(es)
      val forest = StreamTUtils.dfs(ch, vs.toStream).toList // pruned, hence finite
      ?=(forest.map(StreamTUtils.postOrder(_).toList),
         forest.map(Reference.postOrder(_).toList))
  }

  property("on a DAG every child precedes its parent") = forAll(graph) {
    case (vs, es) =>
      // orient every edge from the larger vertex to the smaller: acyclic by construction
      val dag = es.collect { case (a, b) if a != b => (a max b, a min b) }
      val ch = childrenOf(dag)
      val order = StreamTUtils.reverseTopSort(vs.toStream)(ch).toList
      val pos = order.zipWithIndex.toMap
      order.forall(v => ch(v).forall(c => pos.get(c).forall(_ < pos(v)))) :|
        ("order " + order + " against edges " + dag)
  }

  // The regression.  50,000 is far past the ~10,000 frames the recursive `chop` fits in
  // a default JVM stack, and past the point where `postOrder`'s quadratic append matters.
  private val bigN = 50000

  property("a 50k-vertex chain does not overflow the stack") = {
    val ch = (i: Int) => if (i + 1 < bigN) Stream(i + 1) else Stream.empty[Int]
    val order = StreamTUtils.reverseTopSort(Stream(0))(ch).toList
    val forest = StreamTUtils.dfs(ch, Stream(0))
    ((?=(order.length, bigN) :| "every vertex once")
      && (?=(order.head, bigN - 1) :| "deepest first")
      && (?=(order.last, 0) :| "root last")
      && (?=(StreamTUtils.postOrder(forest.head).toList, order) :| "postOrder agrees"))
  }

  property("50k roots with no edges do not overflow the stack") = {
    val ch = (_: Int) => Stream.empty[Int]
    ?=(StreamTUtils.reverseTopSort((0 until bigN).toStream)(ch).toList, (0 until bigN).toList)
  }
}
