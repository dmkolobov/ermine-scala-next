package com.clarifi.reporting.util

import scalaz._
import scala.collection.immutable.{ Set }
import scalaz.Scalaz._
import scalaz.concurrent.{Promise, Strategy}

object StreamTUtils {
  import scalaz.StreamT._

  def make[F[_]:Foldable,A](s: F[A]): StreamT[Id,A] =
    s.foldr(empty[Id,A])(x => y => x :: y)

  def wrapEffect[M[+_]:Functor,A](m: M[StreamT[M,A]]): StreamT[M,A] =
    StreamT[M,A](m map { Skip[StreamT[M,A]](_) })

  def concatMapIterable[M[_],A,B](m: Iterable[A])(f: A => StreamT[M,B])(implicit M: Applicative[M]): StreamT[M, B] =
    StreamT[M,B](
      if (m isEmpty) M.pure(Done)
      else M.pure(Skip(f(m.head) ++ concatMapIterable[M,A,B](m.tail)(f)))
    )

  def toStreamT[A](f: Iterable[A]): StreamT[Id,A] = StreamT[Id,A](
    if (f.isEmpty) Done
    else Yield(f.head, toStreamT(f.tail)))

  def toIterable[A](s: StreamT[Id,A]): Iterable[A] = new Iterable[A] {
    def iterator: Iterator[A] = new Iterator[A] {
      var cursor = s
      def hasNext: Boolean = !cursor.isEmpty
      def next: A = unconsId(cursor)
        .cata ({case (h, t) => cursor = t; h},
               throw new NoSuchElementException("next on empty stream"))
    }
  }

  /** Partition into `n`-sized chunks, each chunk represented with an
    * arbitrary strict Scala iterable.
    */
  def chunk[A, C <: Iterable[Any], M[_]](n: Int, s: StreamT[Id, A]
          )(implicit cbf: scala.collection.Factory[A, C],
            M: Applicative[M]
          ): StreamT[M, C] = {
    def take(acc: scala.collection.mutable.Builder[A, C], n: Int, s: StreamT[Id, A]
            ): (C, StreamT[Id, A]) =
      if (n <= 0) (acc.result(), s)
      else unconsId(s) match {
        case Some((a, s)) => take(acc += a, n - 1, s)
        case None => (acc.result(), s)
      }
    StreamT.unfoldM(s){s => take(cbf.newBuilder, n, s).point[M] map {
                         case r if !r._1.isEmpty => Some(r)
                         case _ => None
                       }}
  }

  private def unchunk[A](s: StreamT[Id, Iterable[A]]): StreamT[Id, A] =
    s flatMap toStreamT

  /** Precache by one step. */
  private def precache[A](s: StreamT[Need, A]
                        )(implicit strat: Strategy): StreamT[Need, A] =
    StreamT.unfoldM(s){s =>
      val p = Promise(s.uncons.value)
      Need(p.get)
    }

  /** Chunked precalculation of a stream. */
  def precached[A](s: StreamT[Id, A], batchSize: Int
                 )(implicit strat: Strategy): StreamT[Id, A] =
    unchunk(StreamT.unfold(precache(chunk[A, Vector[A], Need](batchSize, s))){
              s => s.uncons.value
            })

  def unconsId[A](s: StreamT[Id,A]): Option[(A, StreamT[Id,A])] = s.step match {
    case Done => None
    case Skip(f) => unconsId(f())
    case Yield(a, f) => Some((a, f()))
  }

  @deprecated("Prefer scalaz.StreamT.runStreamT", "Cantor_47")
  def runStreamT_[S,A](as: StreamT[[a] =>> State[S, a], A])(s: S) = StreamT.runStreamT(as,s)
  def runStreamT[S:Monoid,A](as: StreamT[[a] =>> State[S,a], A]) = StreamT.runStreamT(as,mzero[S])

  /** A variant of [[scalaz.StreamT]]`#runStreamT` that delivers the
    * final state to the resulting promise.
    *
    * If you force the promise before you run the stream, you sleep
    * forever.  If you run the stream more than once, you crash on the
    * second.  **Don't do these things.**
    *
    * In fact, try not to use this function at all.
    *
    * @param stream stateful stream to trampoline state through
    * @param s0 initial state
    * @param ex strategy that sticks to combinators applied to the
    *           resulting promise
    * @author SMRC
    */
  private[reporting]
  def runStreamTOut[S,A](stream : StreamT[[a] =>> State[S, a],A], s0: S)
                        : (Promise[S], StreamT[Id,A]) = {
    val scary = Promise.emptyPromise[S](Strategy.Sequential)
    def rec(stream: StreamT[[a] =>> State[S, a],A], s0: S): StreamT[Id, A] =
      StreamT[Id,A]{
        val (s1, sa) = stream.step(s0)
        sa((a, as) => Yield(a, rec(as, s1)),
           as => Skip(rec(as, s1)),
           {scary.fulfill(s1); Done})
      }
    (scary, rec(stream, s0))
  }

  type Forest[A] = Stream[Tree[A]]
  import Tree._

  def generate[A](children: A => Stream[A], a: A): Tree[A] =
    node(a, children(a).map(b => generate(children, b)))

  /* DEPENDENCY ORDER, iteratively (2026-09-03).  `chop`/`prune`/`dfs`/`postOrder` compute
   * the depth-first order the module loader and the constraint solver's `TypeVarGraph`
   * (`Constraints.Q`) run on.  They used to be the textbook Haskell definitions, and both
   * shapes fail at scale: `chop` recursed once per SIBLING as well as once per level, so
   * its stack depth was the NUMBER OF NODES rather than the depth of the forest, and
   * `postOrder` built its result by left-nested lazy `++`, which is quadratic.  Loading
   * many modules in one JVM overflowed the stack there, which is why every corpus tool
   * used to run one file per JVM (TICKET-editor-and-solver-followups.md section 4).
   *
   * They are now iterative -- an explicit stack, a visited set, an accumulated result --
   * and produce EXACTLY the order the recursive definitions produced, node for node.
   * That is the requirement, not an optimisation: the order feeds the id supply and ids
   * reach published interfaces.  `TestStreamTUtils` keeps the old definitions verbatim as
   * a reference and compares the two on random forests and random graphs.
   */

  /** The engine of `chop` and `prune`: one frame per OPEN node, holding the siblings not
    * yet visited and the pruned children accumulated so far.  Marks a vertex when it is
    * first reached in the same order the recursive `chop` did, so the visited set it
    * returns is the same set.  It does NOT force an already-visited node's subforest,
    * where the recursive version did (`Tree.Node.unapply` is strict in both components);
    * that is unobservable, since `children` is a pure lookup at every call site.
    */
  private def chopRun[A](forest: Forest[A], visited0: Set[A]): (Set[A], Forest[A]) = {
    class Frame(val label: Option[A], var rest: Forest[A]) {
      val kids = Vector.newBuilder[Tree[A]]
    }
    var visited = visited0
    var stack: List[Frame] = new Frame(None, forest) :: Nil
    var result: Forest[A] = Stream.empty
    while (stack.nonEmpty) {
      val f = stack.head
      f.rest match {
        case t #:: us =>
          f.rest = us
          val v = t.rootLabel
          if (!visited(v)) {
            visited = visited + v
            stack = new Frame(Some(v), t.subForest) :: stack
          }
        case _ =>
          stack = stack.tail
          val kids = f.kids.result().to(Stream)
          f.label match {
            case None    => result = kids
            case Some(v) => stack.head.kids += node(v, kids)
          }
      }
    }
    (visited, result)
  }

  def chop[A](forest: Forest[A]) : State[Set[A], Forest[A]] =
    State[Set[A], Forest[A]]((s: Set[A]) => chopRun(forest, s))

  def prune[A](forest: Forest[A]): Forest[A] = chopRun(forest, Set[A]())._2

  def dfs[A](children: A => Stream[A], vs: Stream[A]) : Forest[A] = prune(vs.map(generate(children,_)))

  def postOrder[A](tree : Tree[A]): Stream[A] = {
    val out = Vector.newBuilder[A]
    var stack: List[(A, Forest[A])] = (tree.rootLabel, tree.subForest) :: Nil
    while (stack.nonEmpty) {
      val (a, ts) = stack.head
      ts match {
        case t #:: us =>
          stack = (t.rootLabel, t.subForest) :: (a, us) :: stack.tail
        case _ =>
          out += a
          stack = stack.tail
      }
    }
    out.result().to(Stream)
  }

  /** `dfs(children, vertices) flatMap postOrder`, computed without building the forest at
    * all: one explicit stack, and `children` applied at most once per REACHED vertex.
    */
  def reverseTopSort[A](vertices: Stream[A])(children: A => Stream[A]): Stream[A] = {
    val out = Vector.newBuilder[A]
    var visited = Set[A]()
    var roots = vertices
    while (roots.nonEmpty) {
      val v0 = roots.head
      roots = roots.tail
      if (!visited(v0)) {
        visited = visited + v0
        var stack: List[(A, Stream[A])] = (v0, children(v0)) :: Nil
        while (stack.nonEmpty) {
          val (v, cs) = stack.head
          cs match {
            case c #:: rest =>
              stack = (v, rest) :: stack.tail
              if (!visited(c)) {
                visited = visited + c
                stack = (c, children(c)) :: stack
              }
            case _ =>
              out += v
              stack = stack.tail
          }
        }
      }
    }
    out.result().to(Stream)
  }

  def foreach[A](aas: StreamT[Id, A])(f: A => Unit): Unit = aas.step match {
    case Yield(a,as) => { f(a); foreach[A](as())(f); }
    case Skip(as) => foreach[A](as())(f)
    case Done => ()
  }

}
