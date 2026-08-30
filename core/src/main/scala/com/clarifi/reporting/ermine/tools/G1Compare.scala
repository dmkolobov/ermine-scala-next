package com.clarifi.reporting.ermine.tools

import java.io.File
import scala.io.Source

import com.clarifi.reporting.ermine.{
  AppT, Arrow, ConcreteRho, Exists, Forall, Kind, ArrowK, Constraint, Field,
  Memory, Name, Part, ProductT, Rho, Star, Type, VarK, VarT }
import com.clarifi.reporting.ermine.parsing.{ ErParseState, InterfaceParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.syntax.Explicit
import com.clarifi.reporting.ermine.Global
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import scalaparsers.Supply

/** G1 oracle comparator (tracker/LSP-ROADMAP.md, Stage 1 item 1.1).
  *
  * Compares two trees of .ei interface files up to alpha-equivalence of
  * parsed types: both sides are parsed with the language's own qtyp
  * parser, then compared structurally with a variable bijection —
  * Forall binders positionally (a reordered quantifier list is a
  * difference), Exists binders and constraint lists (and Part right-hand
  * sides) by backtracking multiset match, since the constraint solver
  * emits those in an id-hash-dependent order that legitimately differs
  * between runs.  Never string comparison (rendered display names are
  * order-derived), never scalaz Equal[Type] (id-based).
  *
  * Usage:
  *   G1Compare <dirA> <dirB>                          compare *.ei trees
  *   G1Compare --pair <a.ei> <b.ei> --expect equal    fixture self-test
  *   G1Compare --pair <a.ei> <b.ei> --expect differ   fixture self-test
  * Exit 0 = expectation met (trees equivalent / pair as expected).
  */
object G1Compare {

  // ------------------------------------------------------------ alpha-eq

  /** tv/kv: committed bijections.  open1/open2: ids currently bindable on
    * first encounter (the enclosing Exists' binders) — Exists binders are
    * paired lazily through constraint matching rather than positionally. */
  final case class Bij(tv: Map[Int, Int], kv: Map[Int, Int],
                       open1: Set[Int], open2: Set[Int]) {
    def bindT(a: Int, b: Int): Bij = copy(tv = tv + (a -> b))
    def bindK(a: Int, b: Int): Bij = copy(kv = kv + (a -> b))
  }
  object Bij { val empty = Bij(Map(), Map(), Set(), Set()) }

  def alphaEq(a: Type, b: Type, e: Bij): Option[Bij] = (a, b) match {
    case (VarT(x), VarT(y)) =>
      e.tv get x.id match {
        case Some(m) => if (m == y.id) Some(e) else None
        case None =>
          if (e.tv.valuesIterator contains y.id) None
          else if (e.open1(x.id) && e.open2(y.id)) Some(e.bindT(x.id, y.id))
          else if (x.id == y.id) Some(e)                    // shared env var
          else if (x.name.isDefined && x.name == y.name) Some(e) // free by name
          else None
      }
    case (AppT(f1, a1), AppT(f2, a2)) =>
      alphaEq(f1, f2, e) flatMap (alphaEq(a1, a2, _))
    case (Arrow(_), Arrow(_))                     => Some(e)
    case (ProductT(_, n1), ProductT(_, n2))       => if (n1 == n2) Some(e) else None
    case (ConcreteRho(_, f1), ConcreteRho(_, f2)) => if (f1 == f2) Some(e) else None
    case (c1: Type.Con, c2: Type.Con)             => if (c1.name == c2.name) Some(e) else None
    case (f1: Forall, f2: Forall) =>
      if (f1.ks.length != f2.ks.length || f1.ts.length != f2.ts.length) None
      else {
        val e2 = e.copy(
          tv = e.tv ++ f1.ts.map(_.id).zip(f2.ts.map(_.id)),
          kv = e.kv ++ f1.ks.map(_.id).zip(f2.ks.map(_.id)))
        alphaEq(f1.constraints, f2.constraints, e2) flatMap (alphaEq(f1.body, f2.body, _))
      }
    case (x1: Exists, x2: Exists) =>
      if (x1.xs.length != x2.xs.length || x1.constraints.length != x2.constraints.length) None
      else {
        val e2 = e.copy(open1 = e.open1 ++ x1.xs.map(_.id), open2 = e.open2 ++ x2.xs.map(_.id))
        matchMultiset(x1.constraints, x2.constraints, e2) map
          (_.copy(open1 = e.open1, open2 = e.open2))
      }
    case (p1: Part, p2: Part) =>
      alphaEq(p1.lhs, p2.lhs, e) flatMap (matchMultiset(p1.rhs, p2.rhs, _))
    case (Memory(_, b1), Memory(_, b2)) => alphaEq(b1, b2, e)
    case _ => None
  }

  /** Backtracking permutation match with one consistent bijection. */
  private def matchMultiset(cs1: List[Type], cs2: List[Type], e: Bij): Option[Bij] =
    cs1 match {
      case Nil => if (cs2.isEmpty) Some(e) else None
      case c1 :: rest1 =>
        cs2.indices.iterator.flatMap { j =>
          alphaEq(c1, cs2(j), e) flatMap { e2 =>
            matchMultiset(rest1, cs2.patch(j, Nil, 1), e2)
          }
        }.nextOption()
    }

  def kindEq(a: Kind, b: Kind, e: Bij): Option[Bij] = (a, b) match {
    case (Star(_), Star(_)) | (Rho(_), Rho(_)) |
         (Field(_), Field(_)) | (Constraint(_), Constraint(_)) => Some(e)
    case (ArrowK(_, i1, o1), ArrowK(_, i2, o2)) =>
      kindEq(i1, i2, e) flatMap (kindEq(o1, o2, _))
    case (VarK(x), VarK(y)) =>
      e.kv get x.id match {
        case Some(m) => if (m == y.id) Some(e) else None
        case None    => Some(e.bindK(x.id, y.id))  // fresh unannotated kind metas
      }
    case _ => None
  }

  // ------------------------------------------------------------- parsing

  private def boot(): (SessionEnv, Supply, Printer) = {
    implicit val supply: Supply = Supply.create
    implicit val printer: Printer = Printer(_ => ())
    implicit val env: SessionEnv = new SessionEnv(_typeCheck = Some(true))
    Lib.preamble
    Session.loadModules(List("Prelude", "Layout"))
    (env, supply, printer)
  }

  /** name -> (raw line, parsed type); parse errors are fatal (the oracle
    * must never limp past unreadable input). */
  private def parseEi(f: File)(implicit env: SessionEnv, su: Supply): Map[String, (String, Type)] = {
    val text = { val s = Source.fromFile(f, "UTF-8"); try s.mkString finally s.close() }
    val raw = text.linesIterator.filter(_.trim.nonEmpty).map { l =>
      l.takeWhile(_ != ':').trim.stripPrefix("(").stripSuffix(")") -> l
    }.toMap
    // Interface types are FullyQualified and reference any loaded module
    // (nested ones included), so seed the parse state the way the REPL
    // does: an open import of every loaded module, plus the session cons.
    val allMods: Map[String, (Option[String], List[Explicit[Global]], Boolean)] =
      env.loadedModules.keysIterator.map(m => m -> ((None: Option[String]), List.empty[Explicit[Global]], false)).toMap
    val ps0 = ErParseState.mk(f.getPath, text, "G1")
      .importing(env.termNames, env.cons.keySet, allMods, env.termNameOrigins, env.consOrigins)
    val ps  = ps0.copy(s = ps0.s.copy(recognizedCons = env.cons ++ env.privateCons))
    val sigs = Session.parse(InterfaceParsers.interfaceSigs, ps)._2
    sigs.map { case (n, t) =>
      val k = n.toString
      k -> (raw.getOrElse(k, k), t)
    }.toMap
  }

  private def compareFiles(fa: File, fb: File)(implicit env: SessionEnv, su: Supply): List[String] = {
    val (a, b) = (parseEi(fa), parseEi(fb))
    val diffs = List.newBuilder[String]
    for (k <- (a.keySet -- b.keySet).toList.sorted) diffs += s"  only in A: ${a(k)._1}"
    for (k <- (b.keySet -- a.keySet).toList.sorted) diffs += s"  only in B: ${b(k)._1}"
    for (k <- (a.keySet & b.keySet).toList.sorted)
      if (alphaEq(a(k)._2, b(k)._2, Bij.empty).isEmpty) {
        diffs += s"  A: ${a(k)._1}"
        diffs += s"  B: ${b(k)._1}"
      }
    diffs.result()
  }

  // ---------------------------------------------------------------- main

  def main(args: Array[String]): Unit = {
    val rc = try run(args) catch {
      case e: Throwable => System.err.println("g1-compare: fatal: " + e); e.printStackTrace(); 2
    }
    System.exit(rc)
  }

  private def run(args: Array[String]): Int = {
    System.err.println("g1-compare: booting session for the type parser...")
    implicit val (env, supply, _) = boot()
    args.toList match {
      case dirA :: dirB :: Nil =>
        val (da, db) = (new File(dirA), new File(dirB))
        def eis(d: File): Map[String, File] = {
          def walk(f: File): List[File] =
            if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
            else if (f.getName endsWith ".ei") List(f) else Nil
          walk(d).map(f => d.toPath.relativize(f.toPath).toString -> f).toMap
        }
        val (ma, mb) = (eis(da), eis(db))
        var bad = 0
        for (k <- (ma.keySet -- mb.keySet).toList.sorted) { bad += 1; println(s"DIFF $k: only in $dirA") }
        for (k <- (mb.keySet -- ma.keySet).toList.sorted) { bad += 1; println(s"DIFF $k: only in $dirB") }
        var sigs = 0
        for (k <- (ma.keySet & mb.keySet).toList.sorted) {
          val ds = compareFiles(ma(k), mb(k))
          sigs += parseEi(ma(k)).size
          if (ds.nonEmpty) { bad += 1; println(s"DIFF $k:"); ds foreach println }
        }
        println(s"g1-compare: ${(ma.keySet & mb.keySet).size} files, $sigs signatures, ${if (bad == 0) "EQUIVALENT" else s"$bad differing"}")
        if (bad == 0) 0 else 1
      case "--pair" :: fa :: fb :: "--expect" :: want :: Nil =>
        val ds = compareFiles(new File(fa), new File(fb))
        val differ = ds.nonEmpty
        ds foreach println
        val ok = (want == "differ") == differ
        println(s"g1-compare: pair ${if (differ) "DIFFERS" else "EQUIVALENT"}, expected $want -> ${if (ok) "OK" else "WRONG"}")
        if (ok) 0 else 1
      case _ =>
        System.err.println("usage: G1Compare <dirA> <dirB> | --pair <a> <b> --expect equal|differ")
        2
    }
  }
}
