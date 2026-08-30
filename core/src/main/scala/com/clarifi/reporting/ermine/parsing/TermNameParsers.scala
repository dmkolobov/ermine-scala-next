package com.clarifi.reporting.ermine.parsing
import ErParseState.Lenses._
import scalaparsers.Diagnostic._
import TypeParsers.unspecifiedType
import com.clarifi.reporting.ermine.{freshId => _, _}

trait TermNameParser extends NameParser {
  def termName: Parser[Name]      = get.flatMap(u => name(u.s.canonicalTerms))
  def localTermName: Parser[Name] = get.flatMap(u => localName(u.s.canonicalTerms))

  // definitions which bind local names
  // ->foo<- : Int
  // data ->Foo<- a b c = ->Bar<- Int a
  // At the top level a definition may not shadow an import; inside an open
  // `let`/`where` block it binds a fresh local that shadows whatever the name
  // meant outside the block, until LocalBlocks.close restores the maps.
  def termDef: Parser[TermVar] = gets(_.s.localBlocks) flatMap {
    case List() => globalTermDef
    case _      => localTermDef
  }

  private def globalTermDef: Parser[TermVar] = for {
    p <- loc
    n <- termName
    _ <- if (!n.isInstanceOf[Local]) raise(p, "error: term definition would shadow global definition " + n)
         else unit(())
    l =  termNames.member(n)
    m <- gets(l.get(_))
    r <- m match {
      case Some(v) =>
        val vp = v at p
        modify(l.set(_, Some(vp))) as vp // update the term map to point to the _actual_ definition location for future reference
      case None => for {
        k <- unspecifiedType(p)
        v <- freshId.map(V(p,_,Some(n),Bound,k))
        _ <- modify(l.set(_, Some(v)))
      } yield v
    }
  } yield r

  private def localTermDef: Parser[TermVar] = for {
    p <- loc
    u <- get
    n <- bindingName(u.s.canonicalTerms)
    _ <- u.s.canonicalTerms.get(n) match {
      case Some(List(g : Global)) if n.string.startsWith(":") =>
        raise(p, "error: cannot bind " + n + ": it would shadow the data constructor " + g)
      case _ => unit(())
    }
    b = u.s.localBlocks.head
    l = termNames.member(n)
    m <- gets(l.get(_))
    r <- m match {
      case Some(v) if b.bound(n) || !b.openTerms.contains(n) =>
        // another equation for a name this block already binds, or a forward
        // reference placeholder made inside this block: keep its variable
        val vp = v at p
        (modify(l.set(_, Some(vp))) >> LocalBlocks.note(n, None, vp)) as vp
      case _ => for {
        // a fresh binder, shadowing an enclosing binder or an import (if any)
        k <- unspecifiedType(p)
        v <- freshId.map(V(p,_,Some(n),Bound,k))
        outer = m orElse (u.s.canonicalTerms.get(n) match {
          case Some(List(g : Global)) => u.s.termNames.get(g)
          case _ => None
        })
        _ <- modify(l.set(_, Some(v)))
        _ <- modify(canonicalTerms.member(n).set(_, Some(List(n))))
        _ <- LocalBlocks.note(n, outer, v)
      } yield v
    }
  } yield r

  def termOpVar(fix: Fixity, f : Fixity => Boolean): Parser[TermVar] = attempt(
    for {
      p <- loc
      s <- op
      //todo: Fix
      Some(List(n)) <- gets(_.s.canonicalTerms.get(Local(s,fix)))
      if f(n.fixity) // == fix
      l = termNames.member(n)
      m <- gets(l.get(_))
      r <- m match {
        case Some(v) => unit(v at p)
        case None => for {
          k <- unspecifiedType(p)
          v <- freshId.map(V(p,_,Some(n),Bound,k))
          _ <- modify(l.set(_, Some(v)))
        } yield v
      }
    } yield r,
    fix match {
      case Idfix => "identifier"
      case Prefix(_) => "prefix term operator"
      case _ => "term operator"
    }
  )

  def termOp(fix: Fixity, f : Fixity => Boolean): Parser[Var] = for {
    p <- loc
    v <- termOpVar(fix, f)
  } yield Var(v at p)

  // term variables inside of a term somewhere which use local or global names
  def termVar: Parser[TermVar] = for {
    p <- loc
    n <- termName
    l = termNames.member(n)
    m <- gets(l.get(_))
    r <- m match {
      case Some(v) => unit(v at p)
      case None => for {
        k <- unspecifiedType(p)
        v <- freshId.map(V(p,_,Some(n),Bound,k))
        _ <- modify(l.set(_, Some(v)))
      } yield v
    }
  } yield r



}

/** Parser actions bracketing a `let`/`where` binding block. While a block is
  * open, termDef binds fresh locals that shadow the surrounding scope in both
  * termNames and canonicalTerms; close restores both maps for the names the
  * block bound. `shadows` answers outer -> block variable, so a block's
  * bindings — and, for `where`, the body that parsed before the clause — can
  * be rewritten where they referenced the outer variable before the shadowing
  * binding was reached (letrec scoping); checkShadows restricts that map to
  * what is safe to rewrite. */
object LocalBlocks {
  import ErParseState.Lenses.{ localBlocks => blocks }

  def open: Parser[Unit] =
    modify(s => blocks.set(s, LocalBlock(s.s.termNames, s.s.canonicalTerms) :: s.s.localBlocks))

  /** Record that the innermost block bound `n` (shadowing `outer`, if any) as `v`. */
  def note(n: Local, outer: Option[TermVar], v: TermVar): Parser[Unit] =
    modify(s => blocks.set(s, s.s.localBlocks match {
      case b :: bs => b.copy(bound = b.bound + n, shadowed = b.shadowed ++ outer.map(_ -> v)) :: bs
      case bs      => bs
    }))

  def shadows: Parser[Map[TermVar, TermVar]] =
    gets(_.s.localBlocks.headOption.map(_.shadowed).getOrElse(Map()))

  /** Restrict `sh` to shadowed outer variables that actually occur in `occurring`
    * (the rest need no rewrite), and refuse the block when such a variable is in
    * scope under more than one name: the rewrite is by variable, so it would
    * capture references made through the other names (e.g. a module-affixed
    * import alias of the shadowed import). */
  def checkShadows(l: scalaparsers.Pos, sh: Map[TermVar, TermVar], occurring: Vars[Type]): Parser[Map[TermVar, TermVar]] =
    get.flatMap(u => {
      val used = sh.filter(kv => occurring.contains(kv._1))
      // count aliases against the maps as they stood when the block OPENED:
      // the current canonicalTerms already carries the block's own overrides,
      // which would hide the very name being shadowed
      val (canon, terms) = u.s.localBlocks.headOption match {
        case Some(b) => (b.openCanonicals, b.openTerms)
        case None    => (u.s.canonicalTerms, u.s.termNames)
      }
      def aliases(v: TermVar) = canon.toList.collect {
        case (a, List(g : Global)) if terms.get(g).exists(_ == v) => a.toString
      }.sorted
      used.keys.map(v => (v, aliases(v))).find(_._2.length > 1) match {
        case Some((v, as)) =>
          raise(l, "error: binding " + used(v).name.getOrElse(used(v)) + " would capture references to " +
                   v.name.getOrElse(v) + ", which is in scope under multiple names: " + as.mkString(", ") +
                   "; rename the binding or hide one of the imports")
        case None => unit(used)
      }
    })

  def close: Parser[Unit] =
    modify(s => s.s.localBlocks match {
      case b :: bs =>
        def restore[K, W](m: Map[K, W], saved: Map[K, W], k: K): Map[K, W] =
          saved.get(k) match { case Some(w) => m + (k -> w); case None => m - k }
        ErParseState.erpsLens.set(s, s.s.copy(
          termNames      = b.bound.foldLeft(s.s.termNames)((m, n) => restore(m, b.openTerms, n : Name)),
          canonicalTerms = b.bound.foldLeft(s.s.canonicalTerms)(restore(_, b.openCanonicals, _)),
          localBlocks    = bs))
      case List() => s
    })
}

// can recognize any name, upper or lower case
object TermNameParsers extends TermNameParser {
  def identStart = letter
  override def ident = super.ident | literalIdent
  def opStart = opChar
}

/** Names suitable for signing or term definition. */
object TermBindingParsers extends TermNameParser {
  def identStart = lower
  def opStart = opChar
  override def ident = super.ident | literalIdent
}

object DataConParsers extends TermNameParser {
  def identStart = upper
  def opStart = ch(':')
}

object PatternVarParsers extends TermNameParser {
  def identStart = lower
  def opStart = satisfy(c => c != ':' && isOpChar(c))
  override def ident = super.ident | literalIdent
}
