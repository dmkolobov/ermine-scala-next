package com.clarifi.reporting.ermine.editor

import com.clarifi.reporting.{ermine => L}
import com.clarifi.reporting.ermine.{syntax => S}
import scalaz.Scalaz._
import scalaz.Monad
import com.clarifi.reporting.ermine.MonadicPlus

object Backend {
  type MCursor[A] = Cursor[S.Module,A]
  type Loc = Cursor[Any,Any]
}

import Backend.{ MCursor, Loc }

trait Backend[F[_],E,S] {
  sealed trait Action[P,R] {
    def apply(params: P): F[R]
  }

  case class TypeOf(ty: F[L.Type]) extends Action[Unit, L.Type] {
    def apply(u: Unit) = ty
  }
  case class LocalEnvironment(env: F[List[L.TermVar]]) extends Action[Unit, List[L.TermVar]] {
    def apply(u: Unit) = env
  }
  case class Environment(mkEnv: (L.Type, Option[String]) => F[List[L.TermVar]])
      extends Action[(L.Type, Option[String]), List[L.TermVar]] {
    def apply(p: (L.Type, Option[String])) = mkEnv(p._1, p._2)
  }
  case class Eval(tm: F[L.Term]) extends Action[Unit, L.Term] {
    def apply(u: Unit) = tm
  }
  case class Rename(go: String => F[Unit]) extends Action[String, Unit] {
    def apply(s: String) = go(s)
  }
  // todo: removing references to Diff, fix up Action (DONE)
  // still need to convert between cursors and nodes (DONE)
  // need a way of keeping nodes-cursors mapping synchronized
  // also need to fix up nodes-cursors mapping in response to inserts, adds, removes
  // view needs to provide functions from Term -> Node; from Statement -> Node, etc

  // see introduceCaller
  case class IntroduceCaller(f: F[(MCursor[L.Term],MCursor[L.Term])]) extends Action[Unit, (MCursor[L.Term],MCursor[L.Term])] {
    def apply(u: Unit) = f
  }
  case class IntroduceCallees(f: F[MCursor[L.Term]]) extends Action[Unit, MCursor[L.Term]] {
    def apply(u: Unit) = f
  }
  case class DeclareLocal(f: (Option[String], Int) => F[MCursor[L.ImplicitBinding]]) extends Action[(Option[String],Int), MCursor[L.ImplicitBinding]] {
    def apply(p: (Option[String],Int)) = f.tupled(p)
  }
  case class AddArgument(f: Option[String] => F[Unit]) extends Action[Option[String], Unit] {
    def apply(o: Option[String]) = f(o)
  }
  case class Extract(c: F[MCursor[L.ImplicitBinding]]) extends Action[Unit, MCursor[L.ImplicitBinding]] {
    def apply(u: Unit) = c
  }
  case class Remove(d: F[Unit]) extends Action[Unit, Unit] {
    def apply(u: Unit) = d
  }

  def initialState: S
  def loadState(m: S.Module): S
  def at[A](loc: MCursor[A])(m: S): Option[A]

  def run[A](initial: S, fa: F[A]): Either[E,(A,S)]

  def addImport(module: String): F[Unit]
  def removeImport(module: String): F[Unit]
  def listImports: F[List[String]]

  def availableActions[A](loc: MCursor[A]): F[List[Action[P,R] forSome { type P ; type R }]]

  /** Returns the type at the given location. */
  def typeOf(loc: MCursor[L.Term]): F[L.Type]
  def typeOfBinding(loc: MCursor[L.ImplicitBinding]): F[L.Type]
  
  /** the required type for a replacement at the given location */
  def typeOfReplacement(loc: MCursor[L.Term]): F[L.Type] =
    replace(loc, L.Hole(L.Loc.builtin)).flatMap(_ => typeOf(loc))

  /** The list of local variables, and their types. Example, for `f x y z = [?]`,
    * this would return x, y, z.
    */
  def localEnvironment(loc: MCursor[L.Term]): F[List[L.TermVar]]

  /** Find all terms in the global environment subsumed by f and whose name "matches" the given name. */
  def globalEnvironment(f: L.Type, name: Option[String]): F[List[L.TermVar]]

  /** Find all terms in either the local or global environment subsumed by f and whose name
    * "matches" name, if specified. */
  def environment(loc: MCursor[L.Term], f: L.Type, name: Option[String]): F[List[L.TermVar]]

  //NOTE: Once we upgrade to scalaz 7, we can remove this in favor of the version on Monad
  private def filterM[A](l: List[A])(f: A => F[Boolean]): F[List[A]] =
    l match {
      case Nil => F.pure(List())
      case h :: t => F.bind(f(h))(b => if (b) filterM(t)(f) map (h :: _) else filterM(t)(f))
    }

  def indirectMatches(loc: MCursor[L.Term], f: L.Type, name: Option[String]): F[List[(L.TermVar,L.Term,L.Type)]] = {
    val all = for {
      gs <- globalEnvironment(f, name)
      ls <- localEnvironment(loc)
    } yield (ls ++ gs)

    def applyNHoles(f: L.Term, n: Int): L.Term =
      (0 until n).foldLeft(f)((t, _) => L.App(t, L.Hole(L.Loc.builtin)))

    def functionReturns(f: L.Type, t: L.Type, nArgs: Int = 1): F[List[(Int,L.Type)]] =
      f match {
        case L.Forall(_,ks,ts,c,body) => functionReturns(body,t,nArgs) // TODO: revisit, prob need to apply forall to type args
        case L.AppT(L.AppT(L.Arrow(_), _), x) => for {
          b <- matches(x, t)
          n <- functionReturns(x, t, nArgs+1).map { l =>
                 if (b) (nArgs,x) :: l
                 else l
               }
        } yield n
        case _ => F.pure(List())
      }
    // if : forall a. Bool -> a -> a -> a
    // if ? : forall a. a -> a -> a
    // (if ? ?) : forall a . a -> a
    // (if ? Int) : Int -> Int
    val direct = all.flatMap(tvs => filterM(tvs)(tv => matches(tv.extract, f))).map(_.map(tv => (tv,L.Var(tv),tv.extract)))

    val indirect = all.flatMap { tvs => F.traverse(tvs) {
        tv => functionReturns(tv.extract, f).
              map(_.map(n => (tv,applyNHoles(L.Var(tv), n._1), n._2)))
      }
    } map (_ flatten)
    (direct |@| indirect)(_ ++ _)
  }

  /** Returns true if t1 "matches" t2, meaning that all values of type t1 are
    * considered a value of type t2. Put another way, given a : t1, and f: t2 -> x,
    * matches(t1, t2) means that f a is well-typed. */
  def matches(t1: L.Type, t2: L.Type): F[Boolean]

  /** Evaluate the expression at the given location. */
  def eval(loc: MCursor[L.Term]): F[L.Term]

  /** Replace the value at the given location. Also handles rename, if the thing
    * pointed to is a name. */
  def replace[A](loc: MCursor[A], replacement: A): F[Unit]

  /** Wraps the given location in a function call.
    * Example: given `x + [y]`, introduceCaller([y]) will result in `x + ? y`.
    * The returned cursors will point at the hole, and the new location of the
    * original term: (?, y)
    */
  def introduceCaller(loc: MCursor[L.Term]): F[(MCursor[L.Term],MCursor[L.Term])]

  /** Applies the given location to an additional argument. So, given
    * `sqrt : Double -> Double`, introduceCallee([sqrt]) yields sqrt ?.
    * The returned cursor is the location of the added argument.
    */
  def introduceCallee(loc: MCursor[L.Term]): F[MCursor[L.Term]]

  /** Introduce a new top-level declaration with the given number of args -
    * if no name provided, one will be provided for you (and it won't be pretty). */
  def declareTopLevel(name: Option[String], argCount: Int): F[MCursor[L.ImplicitBinding]]

  /** Introduce a new top-level declaration with the given number of args -
    * if no name provided, one will be provided for you (and it won't be pretty). */
  def declareLocal(name: Option[String], argCount: Int, c: MCursor[L.Term]): F[MCursor[L.ImplicitBinding]]

  /** Add an argument to a binding.
    * f x y z = ...  ==>  f x y z w = ... */
  def addArgument(loc: MCursor[L.ImplicitBinding], name: Option[String]): F[Unit]

  /** Given a term variable, finds all the places in the module it is used.
    */
  def references(v: L.TermVar): F[List[MCursor[L.Term]]]

  /** Removes whatever is pointed to by the given cursor, failing if this would result in
    * an ill-typed program. */
  def remove[A](c: MCursor[A]): F[Unit]

  /** F must be a monad which allows failure with error type E. */
  def accessFailure[A](f: F[A]): F[Either[E,A]]

  /** Returns true if v is a binary operator. */
  def isBinOp(v: L.TermVar): Boolean = v.name map (_.fixity match {
    case L.Infix(_,_) => true
    case _ => false
  }) getOrElse false

  /** Returns Some(precedence)` of the given variable, or None if
    * v is not a binary operator.
    */
  def precedence(v: L.TermVar): Option[Int] = v.name flatMap (_.fixity match {
    case L.Infix(prec,_) => Some(prec)
    case _ => None
  })

  /** F is a monad. */
  implicit def F: Monad[F]
  // implicit def toMonadPlus[A](fa: F[A]): MonadicPlus[F,A]
}

sealed trait Cursor[A,B] {
  def ++[C](c: Cursor[B,C]): Cursor[A,C] = c match {
    case Empty() => this.asInstanceOf[Cursor[A,C]] // GADT fail
    case _       => Compose(this, c)
  }
  def last: Cursor[D,B] forSome { type D } = this
}
case class Compose[A,B,C](f: Cursor[A,B], g: Cursor[B,C]) extends Cursor[A,C] {
  override def last = g.last
}
case class Empty[A]() extends Cursor[A,A] {
  override def ++[C](c: Cursor[A,C]) = c
}

object Cursors {

  def at[A,B](c: Cursor[A,B])(ctx: A): Option[B] = c match {
    case Modules.Field(n) => ctx.fields.find(_.vs.exists(_.name.get == n))
    case Modules.Binding(v) => ctx.implicits.find(_.v == v)
    case Fields.Name(pos) => ctx.vs.drop(pos).headOption.map(_.name.get)
    case Fields.Type => Some(ctx.ty)
    case Bindings.Name => Some(ctx.v.name.get)
    case Bindings.Alt(pos) => ctx.alts.drop(pos).headOption
    case Alts.Param(pos) => ctx.patterns.drop(pos).headOption
    case Alts.Body => Some(ctx.body)
    case Params.Name => ctx match { case L.VarP(v) => Some(v.name); case _ => None }
    case Terms.Fn => ctx match { case L.App(f,_) => Some(f); case _ => None }
    case Terms.Arg => ctx match { case L.App(_,arg) => Some(arg); case _ => None }
    case Terms.LetBinding(v) => ctx match { case L.Let(_,is,_,_) => is.find(_.v == v); case _ => None }
    case Terms.LetBody => ctx match { case L.Let(_,_,_,body) => Some(body); case _ => None }
    case Terms.Record(pos) => sys.error("todo") // need to pull out nth argument of a Product(_,n) where pos < n // ctx match {
    case Compose(f,g) => at(f)(ctx).flatMap(x => at(g)(x))
    case Empty() => Some(ctx.asInstanceOf[B])
  }

// this would be a lot easier if function applications were actual lists of arguments in the AST
//  def nthArg(n: Int, t: Term): Term => Option[Term] =

  object Modules {
    /** GADT from which we can extract a (Module => Option[T]) */
    case class Field(field: L.Name) extends Cursor[S.Module,S.FieldStatement]
    case class Binding(ref: L.TermVar) extends Cursor[S.Module,L.ImplicitBinding]
  }

  object Fields {
    case object Type extends Cursor[S.FieldStatement,L.Type]
    case class Name(pos: Int) extends Cursor[S.FieldStatement,L.Name]
  }

  object Bindings {
    case object Name extends Cursor[L.ImplicitBinding,L.Name]
    case class Alt(pos: Int) extends Cursor[L.ImplicitBinding,L.Alt]
  }

  object Alts {
    case class Param(pos: Int) extends Cursor[L.Alt,L.Pattern]
    case object Body extends Cursor[L.Alt,L.Term]
  }

  object Params {
    case object Name extends Cursor[L.Pattern,Option[L.Name]]
    // @todo - add ability to descend into patterns
  }

  object Terms {
    case object Fn extends Cursor[L.Term,L.Term]
    case object Arg extends Cursor[L.Term,L.Term]
    case class  LetBinding(v: L.TermVar) extends Cursor[L.Term,L.ImplicitBinding]
    case object LetBody extends Cursor[L.Term,L.Term]
    case class  Record(pos: Int) extends Cursor[L.Term,L.Term]
    // todo - indexing into literal
  }
}

/** Logic for maintaining a bidirectional mapping between
  * `Node` values and `Cursor` values.
  */
trait PathTranslator[N] {
  def cursor(n: N): Option[MCursor[Any]]
  def node(cur: MCursor[Any]): Option[N]
}
