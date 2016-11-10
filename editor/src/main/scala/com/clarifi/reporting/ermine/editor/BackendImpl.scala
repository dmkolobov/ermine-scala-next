package com.clarifi.reporting
package ermine.editor

import com.clarifi.reporting.ermine.session.{ SessionEnv, Session, Printer }
import com.clarifi.reporting.ermine.session.Session.{ loadModules }
import com.clarifi.reporting.ermine.syntax.{ Module, ImportExportStatement, FieldStatement }
import com.clarifi.reporting.ermine.{ die => _, _ }
import scalaparsers._
import scalaparsers.Diagnostic._
import com.clarifi.reporting.ermine.Subst.subsumeType
import com.clarifi.reporting.ermine.Runtime.Thunk

import scalaz.{Success => _, Failure => _, Name => _, Free => _, _}
import scalaz.Free.{ suspend, Return, Trampoline }
import scalaz.Monad

// Scalaz._ imports assorted implicits.  This messes with importing specific objects, like scalaz.syntax.monad
// since you'll get ambiguous references to the same implicit, which means it won't be used and e.g. map can't be found
// TODO:  get rid of this import, and replace it with what we need to actually import.
import scalaz.Scalaz._

//import scalaz.syntax.monad._

import Cursors._

sealed abstract class EditorSession[+A] extends MonadicPlus[EditorSession, A] { that =>
  def self: EditorSession[A] = that
  def lift[B](m: EditorSession[B]) = m
  def apply(state: Module, env: SessionEnv, su: Supply): Trampoline[Result[Module, A]]
  def run(state: Module, env: SessionEnv, su: Supply): Result[Module, A] = apply(state, env, su).run
  def flatMap[B](f: A => EditorSession[B]) = new EditorSession[B] {
    def apply(state: Module, env: SessionEnv, su: Supply) = that(state, env, su) flatMap {
      case Success(a, t) => f(a)(t, env, su)
      case e : Failure   => suspend(Return(e))
    }
  }
  def map[B](f: A => B): EditorSession[B] = new EditorSession[B] {
    def apply(state: Module, env: SessionEnv, su: Supply) = that(state, env, su).map(_ map f)
  }
  def orElse[B >: A](b: => B) = new EditorSession[B] {
    def apply(state: Module, env: SessionEnv, su: Supply) = {
      val envp = env.copy
      that(state, env, su) map {
        case e : Failure =>
          env := envp
          Success(b, state)
        case m => m
      }
    }
  }
  def |[B >: A](m: => EditorSession[B]) = new EditorSession[B] {
    def apply(state: Module, env: SessionEnv, su: Supply) = {
      val envp = env.copy
      that(state, env, su) flatMap {
        case e : Failure =>
          env := envp
          m(state, env, su)
        case n => suspend(Return(n))
      }
    }
  }
  def when(b: Boolean) =
    if(b) skip
    else new EditorSession[Unit] {
           def apply(state: Module, env: SessionEnv, su: Supply) =
           suspend(Return(Success((), state)))
         }

  def withFilter(p: A => Boolean) = new EditorSession[A] {
    def apply(state: Module, env: SessionEnv, su: Supply) = {
      that(state, env, su) map {
        case Success(a, t) =>
          if(p(a)) Success(a, t)
          else Failure(Some("withFilter"), List())
        case e => e
      }
    }
  }
}

object EditorSession {
  def supplied[A](m: Supply => A): EditorSession[A] = new EditorSession[A] {
    def apply(state: Module, env: SessionEnv, su: Supply) = suspend(Return(
      try { Success(m(su), state) }
      catch { case Death(d,_) => Failure(Some(d), Nil) }
    ))
  }
  def suppliedSubst[A](m: Supply => SubstEnv => A): EditorSession[A] = new EditorSession[A] {
    def apply(state: Module, env: SessionEnv, su: Supply) = suspend(Return(
      try { Success(Session.subst(m(su))(env), state) }
      catch { case Death(d,_) => Failure(Some(d), Nil) }
    ))
  }
/*
  def supplied[A](m: Supply => EditorSession[A]): EditorSession[A] = new EditorSession[A] {
    def apply(state: Module, env: SessionEnv, su: Supply) = m(su)(state,env,su)
  }
*/
  def session[A](m: SessionEnv => A): EditorSession[A] = new EditorSession[A] {
    def apply(state: Module, env: SessionEnv, su: Supply) = suspend(Return(
      try { Success(m(env),state) }
      catch { case Death(d,_) => Failure(Some(d), Nil) } // TODO: convert stacktrace to stack
    ))
  }
  def subst[A](m: SubstEnv => A): EditorSession[A] = session(implicit e => Session.subst(m))
  def apply[A](f: Module => SessionEnv => Supply => Result[Module, A]): EditorSession[A] =
    new EditorSession[A] {
      def apply(st: Module, env: SessionEnv, su: Supply) = suspend(Return(f(st)(env)(su)))
    }
  val editorPos = Pos("editor","",1,1,false)

  def get: EditorSession[Module] = EditorSession(s => _ => _ => Success(s, s))
  def gets[A](f: Module => A): EditorSession[A] = EditorSession(s => _ => _ => Success(f(s), s))
  def modify(f: Module => Module): EditorSession[Unit] =
    EditorSession(s => _ => _ => Success((), f(s)))
  def put(m: Module): EditorSession[Unit] =
    EditorSession(s => _ => _ => Success((), m))
  def supply: EditorSession[Supply] = EditorSession(st => _ => su => Success(su, st))
  implicit def editorSessionDiagnostic: Diagnostic[EditorSession] = new Diagnostic[EditorSession] {
    def fail(d: Document) = EditorSession(_ => _ => _ => Failure(Some(d), List()))
    def empty             = EditorSession(_ => _ => _ => Failure(None, List()))
  }
  implicit def editorSessionMonad: Monad[EditorSession] = new Monad[EditorSession] {
    def bind[A,B](a: EditorSession[A])(f: A => EditorSession[B]) = a flatMap f
    def point[A](x: => A) = EditorSession(st => _ => _ => Success(x, st))
  }
  def unit[A](x: A): EditorSession[A] = x.pure[EditorSession]
}

import EditorSession.{ editorPos, get, gets, unit, modify, put, supply, supplied, session, suppliedSubst }

class BackendImpl extends Backend[EditorSession, Option[Document], (Module,SessionEnv,Supply)] {
  type MCursor[A] = Cursor[Module,A]
  implicit def F: Monad[EditorSession] = EditorSession.editorSessionMonad
  def initialState = (Module(editorPos,"editor"), new SessionEnv, Supply.create)
  def loadState(m: Module) = (m, new SessionEnv, Supply.create)

  def importedVars(se: SessionEnv, m: Module): Map[TermVar, TermVar] =
    se.termNames.filterKeys { g => m.importExports.exists(_.exported(false, g)) }.map { case (_, v) => v -> v }

  def remembered[A](loc: MCursor[A])(f: (Int, A) => A): EditorSession[(Set[TermVar], Type)] =
    gets(lens(loc, _)) flatMap {
      case None        => fail[EditorSession]("Invalid cursor")
      case Some((a,k)) =>
        EditorSession { state => implicit se => implicit su =>
          Session.subst {
            implicit hm => {
              val i = su.fresh
              val mCheck = k(f(i, a))
              try {
                val imports = importedVars(se, mCheck)
                val ms = Subst.checkModule(Map(), mCheck, (Map(), imports))
                val (gamma, ty, _) = hm.remembered(i)
                val locals = gamma.toSet ++ (ms._2.values filterNot (imports.contains _))
                Success((locals, ty), state)
              }
              catch { case Death(d, _) => Failure(Some(d), Nil) }
            }
          }
        }
    }

  def typeOfBinding(loc: MCursor[ImplicitBinding]) = remembered(loc)((i,b) => b copy (remember = Some(i))) map (_._2)

  def typeOf(loc: MCursor[Term]) = remembered(loc)((i,tm) => Remember(i,tm)) map (_._2)

  def references(v: TermVar): EditorSession[List[MCursor[Term]]] = {
    def findTerm(cur: MCursor[Term], tm: Term): List[MCursor[Term]] = tm match {
      case Var(u) if v == u     => List(cur)
      case App(f,x)             => findTerm(Compose(cur, Terms.Fn), f) ++ findTerm(Compose(cur, Terms.Arg), x)
      case Let(l, is, es, body) =>
        findBindings(cur, Terms.LetBinding(_), is) ++ findTerm(Compose(cur, Terms.LetBody), body) // no explicit cursors
      case Case(l, e, as)       => List() // no cursors
      case Lam(l, pat, body)    => List() // no cursors
      case Sig(l, b, a)         => List() // no cursors
      case Rigid(b)             => List() // no cursors
      case _                    => List() // no occurrences
    }
    def findBindings[A](let: MCursor[A], b: TermVar => Cursor[A,ImplicitBinding], is: List[ImplicitBinding]) = is flatMap {
      case ImplicitBinding(_, v, as, _) =>
        val bnd = Compose(let, b(v))
        as.zipWithIndex flatMap {
          // The variable we're looking for shouldn't occur in the patterns
          case (Alt(_,_,body), n) => findTerm(Compose(bnd,Compose(Bindings.Alt(n),Alts.Body)), body)
        }
    }
    gets(_.implicits) map (is => findBindings(Empty(), v => Modules.Binding(v), is))
  }

  def renameField(loc: MCursor[FieldStatement], old: Name, name: String) = for {
    mn <- gets(_.name)
    (fs, k) <- lensM(loc)
    n = Global(mn, name)
    _ <- k(fs.copy(vs = fs.vs.map(v => if(v.name == Some(old)) v copy (name = Some(n)) else v)))
  } yield ()

  def renameParameter(loc: MCursor[Pattern], name: String) = for {
    (p, k) <- lensM(loc)
    _ <- p match {
      case VarP(v) => k(VarP(v copy (name = Some(Local(name)))))
      case _       => fail[EditorSession]("Cannot process non-variable patterns.")
    }
  } yield ()

  def availableActions[A](loc: MCursor[A]) = {
    def termActions(c: MCursor[Term]): EditorSession[List[Action[P,Q] forSome { type P ; type Q }]] = for {
      m <- get
      optional = lens(c,m) match {
        case Some((Let(_,_,_,_),_)) => List(DeclareLocal((s,i) => declareLocal(s,i,c)))
        case _ => List()
      }
    } yield List[Action[P,Q] forSome { type P ; type Q }](
              Eval(eval(c)),
              IntroduceCaller(introduceCaller(c)),
              IntroduceCallees(introduceCallee(c)),
              TypeOf(typeOf(c)),
              LocalEnvironment(localEnvironment(c)),
              Environment((f,n) => environment(c,f,n))
            ) ++ optional
    def bindingActions(c: MCursor[ImplicitBinding]): List[Action[P,Q] forSome { type P ; type Q }] =
      List(TypeOf(typeOfBinding(c)), AddArgument(s => addArgument(c, s)))

    loc.last match {
      case Cursors.Modules.Field(n)    => unit(List(Rename(s => renameField(loc, n, s))))
      case Cursors.Modules.Binding(v)  => unit(bindingActions(loc))
      case Cursors.Fields.Type         => unit(List()) // no special actions on Types yet
      case Cursors.Fields.Name(n)      => unit(List()) // no special actions on Names
      case Cursors.Bindings.Name       => unit(List()) // no special actions on Names
      case Cursors.Bindings.Alt(n)     => unit(List()) // no special actions on Alts yet
      case Cursors.Alts.Param(n)       => unit(List(Rename(s => renameParameter(loc, s))))
      case Cursors.Alts.Body           => termActions(loc)
      case Cursors.Params.Name         => unit(List()) // no special actions on Names
      case Cursors.Terms.Fn            => termActions(loc)
      case Cursors.Terms.Arg           => termActions(loc)
      case Cursors.Terms.LetBinding(v) => unit(bindingActions(loc))
      case Cursors.Terms.LetBody       => termActions(loc)
      case Cursors.Terms.Record(n)      => termActions(loc)
      case Empty()                     => unit(List())
      case _                           => sys.error("Bad last")
    }
  }

  def listImports = session { _.loadedModules.keySet.toList }

  def addImport(module: String) = supply flatMap (su =>
    session(implicit se =>
      // written at Dan's request
      se.loadedModules.contains(module) && { loadModules(List(module))(se, su, Printer.ignore); true }
    ) flatMap {
      case true => modify(m => m copy (importExports = ImportExportStatement(editorPos, false, module, None) :: m.importExports))
      case _    => unit(())
    }
  )

  def removeImport(module: String) = modify(m => m copy (importExports = m.importExports.filter(_.module != module)))

  private def fv(n: Option[Name]): EditorSession[TermVar] =
    supplied(implicit su => fresh(editorPos, n, Bound, VarT(fresh(editorPos, None, Free, Star(editorPos)))))

  private def fpat(n: Option[Name] = None): EditorSession[Pattern] = supplied(implicit su => {
      val t = fresh(editorPos, None, Bound, Star(editorPos))
      VarP(fresh(editorPos, n, Bound, Annot(editorPos, List(), List(t), VarT(t))))
  })

  def declareTopLevel(name: Option[String], argCount: Int) = for {
    m <- get
    n <- name match {
      case Some(s) => if(m.implicits.exists(b => b.v.name.map(_ == Local(s)).getOrElse(false)))
                        fail[EditorSession]("Binding with name '" + s + "' exists.")
                      else
                        unit(Some(Local(s)))
      case None    => unit(None)
    }
    v <- fv(n)
    args <- fpat().replicateM(argCount)
    bnd = ImplicitBinding(editorPos, v, List(Alt(editorPos, args, Hole(editorPos))))
    _ <- modify(m => m copy (implicits = bnd :: m.implicits))
  } yield Cursors.Modules.Binding(v)

  def declareLocal(name: Option[String], argCount: Int, c: MCursor[Term]) = for {
    (tm, k) <- lensM(c)
    v <- tm match {
      case Let(l, is, es, body) =>
        val mn = name map (Local(_))
        for {
          _ <- failUnless[EditorSession](mn.isDefined && (is.exists(_.v.name == mn) || es.exists(_.v.name == mn)),
                 "Name already exists in binding group.")
          v <- fv(mn)
          ps <- fpat().replicateM(argCount)
          b = ImplicitBinding(editorPos, v, List(Alt(editorPos, ps, Hole(editorPos))))
          _ <- k(Let(l, b :: is, es, body))
        } yield Compose(c, Cursors.Terms.LetBinding(v))
      case _ => fail[EditorSession]("A local binding can only be added to an existing binding group.")
    }
  } yield v

  def environment(loc: MCursor[Term], f: Type, name: Option[String]) = for {
    le <- localEnvironment(loc)
    ge <- globalEnvironment(f, name)
  } yield le ++ ge

  def localEnvironment(loc: MCursor[Term]) = remembered(loc)((i,tm) => Remember(i,tm)) map (_._1.toList)

  def globalEnvironment(t: Type, name: Option[String]) = for {
    tms <- session { _.termNames }
    terms = tms.toList.collect {
      case (g, v) if name.map(g.string == _).getOrElse(true) => v
    }.distinct
  } yield terms

  private def reflect(r: Runtime): EditorSession[Term] = session(_.termNames)  flatMap { termNames =>
    r.nf match {
      case Data(g,arr)   => termNames.get(g) match {
        case None        => fail[EditorSession]("Unable to reflect runtime value into term.")
        case Some(v)     => arr.toList.traverse(reflect(_)) map (_.foldLeft(Var(v):Term)(App(_,_)))
      }
      case Arr(arr)      => arr.toList.traverse(reflect(_)) map (_.foldLeft(Product(editorPos,arr.length):Term)(App(_,_)))
      case Bottom(e)     => termNames.get(Global("Error", "error")) match {
        case None        => fail[EditorSession]("Unable to reflect runtime value into term.")
        case Some(v)     => unit(App(Var(v),LitString(editorPos, "bottom")))
      }
      case EmptyRel      => (termNames.get(Global("Native.List","mkRelation#")) |@|
                            termNames.get(Global("Native.List","Nil#"))){
                             (e, n) => unit(App(Var(e), Var(n)))
                           } getOrElse fail[EditorSession]("Unable to reflect runtime value into term.")
      case Thunk(_)      => sys.error("Internal error: nf returned Thunk")
      case Prim(p)       => p match {
        case p:Double    => unit(LitDouble(editorPos,p))
        case p:String    => unit(LitString(editorPos,p))
        case p:Int       => unit(LitInt(editorPos,p))
        case p:Float     => unit(LitFloat(editorPos,p))
        case p:Short     => unit(LitShort(editorPos,p))
        case p:Long      => unit(LitLong(editorPos,p))
        case p:Byte      => unit(LitByte(editorPos,p))
        case p:Boolean   => (if (p) termNames.get(Global("Builtin","True"))
                             else   termNames.get(Global("Builtin","False"))).
                            map(v => unit(Var(v))).getOrElse(
                              fail[EditorSession]("Unable to reflect runtime value into term."))
        case _           => fail[EditorSession]("Unable to reflect runtime value into term.")
      }
      case _             => fail[EditorSession]("Unable to reflect runtime value into term.")
    }
  }

  def eval(loc: MCursor[Term]) = for {
    (tm, k) <- lensM(loc)
    env <- session(_.env)
    rf <- reflect(Term.eval(tm,env))
  } yield rf

  def introduceCaller(loc: MCursor[Term]) = for {
    (x, k) <- lensM(loc)
    _ <- k(App(Hole(editorPos),x))
  } yield (Compose(loc, Cursors.Terms.Fn), Compose(loc, Cursors.Terms.Arg))

  def addArgument(loc: MCursor[ImplicitBinding], name: Option[String]) = for {
    (ImplicitBinding(l, v, alts, r), k) <- lensM(loc)
    p <- fpat(name map (Local(_)))
    nalts = alts map {
      case Alt(al, ps, body) => Alt(al, ps ++ List(p), body)
    }
    _ <- k(ImplicitBinding(l, v, nalts, r))
  } yield ()

  private def removePrime[A,B](c: Cursor[A,B], x: A): EditorSession[A] = c match {
    case Compose(c1, c2) => lens(c1, x) match {
      case None => fail[EditorSession]("Invalid cursor")
      case Some((y, k)) => removePrime(c2, y) map k
    }
    case Modules.Field(n) =>
      val newFields = x.fields flatMap {
        case FieldStatement(l, vs, ty) =>
          val nvs = vs filter (v => v.name.get != n)
          if(nvs.isEmpty)
            List()
          else
            List(FieldStatement(l, nvs, ty))
      }
      unit(x copy (fields = newFields))
    case Modules.Binding(v) =>
      val es = x.explicits.filter(_.v != v)
      val is = x.implicits.filter(_.v != v)
      unit(x copy (explicits = es, implicits = is))
    case Terms.LetBinding(v) => x match {
      case Let(l, is, es, body) =>
        val nis = is.filter(_.v != v)
        val nes = es.filter(_.v != v)
        unit(Let(l, nis, nes, body))
      case _                    => fail[EditorSession]("Invalid cursor")
    }
    case Bindings.Name => unit(x copy (v = x.v copy (name = None)))
    case Bindings.Alt(n) => x match {
      case ImplicitBinding(loc, v, alts, re) => alts.splitAt(n) match {
        case (l, List())      => unit(ImplicitBinding(loc, v, l, re))
        case (l, _ :: r)      => unit(ImplicitBinding(loc, v, l ++ r, re))
      }
    }
    case Terms.Fn => x match {
      case App(_,y) => unit(y) // type check
      case _       => fail[EditorSession]("Invalid cursor")
    }
    case Terms.Arg => x match {
      case App(f,_) => unit(f) // type check
      case _       => fail[EditorSession]("Invalid cursor")
    }
    case _ => fail[EditorSession]("Cannot remove given element.")
  }

  def remove[A](loc: MCursor[A]) =
    get flatMap (removePrime(loc, _)) flatMap { m =>
      EditorSession { state => implicit se => implicit su =>
        Session.subst { implicit hm =>
          try {
            Subst.checkModule(Map(), m, (Map(), importedVars(se, m)))
            Success((), state)
          }
          catch { case Death(d, _) => Failure(Some(d), Nil) }
        }
      } >> put(m)
    }

  def replace[A](loc: MCursor[A], rep: A) = for {
    (_, k) <- lensM(loc)
    v <- k(rep)
  } yield v

  def introduceCallee(loc: MCursor[Term]) = for {
    (f, k) <- lensM(loc)
    _ <- k(App(f, Hole(editorPos)))
  } yield Compose(loc, Cursors.Terms.Arg)

  def accessFailure[A](f: EditorSession[A]) = new EditorSession[Either[Option[Document],A]] {
    def apply(st: Module, env: SessionEnv, su: Supply) = {
      val envp = env.copy
      f(st,env,su) map {
        case Success(a,s) => Success(Right(a), s)
        case Failure(e,_) =>
          env := envp
          Success(Left(e), st)
      }
    }
  }

  def at[A](loc: MCursor[A])(s: (Module,SessionEnv,Supply)) = Cursors.at(loc)(s._1)
  def matches(t1: Type, t2: Type) = suppliedSubst(implicit su => implicit hm => {
    implicit val tml: Located = editorPos
    subsumeType(t2, t1)
  }).as(true).orElse(false)

  def run[A](s: (Module, SessionEnv, Supply), m: EditorSession[A]) = {
    val envp = s._2.copy
    m.run(s._1, s._2, s._3) match {
      case Success(a, mp) => Right((a,(mp,s._2,s._3)))
      case Failure(e, _)  =>
        s._2 := envp
        Left(e)
    }
  }

  private def lens[A,B](c: Cursor[A,B], ctx: A): Option[(B, B => A)] = c match {
    case Modules.Field(n) => ctx.fields.span(! _.vs.exists(_.name.get == n)) match {
      case (lfs, fs :: rfs) => Some((fs, nfs => ctx copy (fields = lfs ++ (nfs :: rfs))))
      case _                => None
    }
    case Modules.Binding(v) => ctx.implicits.span(_.v != v) match {
      case (l, x :: r) => Some((x, y => ctx copy (implicits = l ++ (y :: r))))
      case _           => None
    }
    case Fields.Name(pos) => ctx.vs.splitAt(pos) match {
      case (l, x :: r) => Some((x.name.get, y => ctx copy (vs = l ++ ((x copy (name = Some(y))) :: r))))
      case _           => None
    }
    case Fields.Type => Some((ctx.ty, ty => ctx copy (ty = ty)))
    case Bindings.Name => Some((ctx.v.name.get, n => ctx copy (v = ctx.v copy (name = Some(n)))))
    case Bindings.Alt(pos) => ctx.alts.splitAt(pos) match {
      case (l, x :: r) => Some((x, y => ctx copy (alts = l ++ (y :: r))))
      case _           => None
    }
    case Alts.Param(pos) => ctx.patterns.splitAt(pos) match {
      case (l, x :: r) => Some((x, y => ctx copy (patterns = l ++ (y :: r))))
      case _           => None
    }
    case Alts.Body => Some((ctx.body, body => ctx copy (body = body)))
    case Params.Name => ctx match {
      case VarP(v) => Some(v.name, n => VarP(v copy (name = n)))
      case _ => None
    }
    case Terms.Fn => ctx match {
      case App(f,x) => Some((f, g => App(g,x)))
      case _ => None
    }
    case Terms.Arg => ctx match {
      case App(f,x) => Some((x, y => App(f,y)))
      case _        => None
    }
    case Terms.LetBinding(v) => ctx match {
      case Let(l, is, es, body) => is.span(_.v != v) match {
        case (pre, x :: post) => Some((x, y => Let(l, pre ++ (y :: post), es, body)))
        case _                => None
      }
      case _                    => None
    }
    case Terms.LetBody => ctx match {
      case Let(l, is, es, body) => Some((body, bd => Let(l, is, es, bd)))
      case _                    => None
    }
    case Terms.Record(pos) => sys.error("todo") // need to pull out nth argument of a Product(_,n) where pos < n // ctx match {
    case Compose(f,g) => lens(f, ctx) flatMap {
      case (ctx2, k1) => lens(g, ctx2) map {
        case (ctx3, k2) => (ctx3, x => k1(k2(x)))
      }
    }
    case Empty() => Some((ctx.asInstanceOf[B], x => x.asInstanceOf[A]))
  }
  private def lensM[B](c: MCursor[B]): EditorSession[(B, B => EditorSession[Unit])] =
    get flatMap { m =>
      lens(c, m) match {
        case None => fail[EditorSession]("Invalid cursor")
        case Some((v, k)) => unit((v, u => put(k(u))))
      }
    }
}
