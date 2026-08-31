package com.clarifi.reporting

import java.io.File

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.syntax.{ Renaming, Single }
import com.clarifi.reporting.ermine.surface._

import org.scalacheck._
import Prop._
import scalaparsers.Supply

/** 2.3a parity: the resolution-free header agrees with the fused
  * pipeline's over every stdlib module, and the statement splitter
  * covers every file with plausible structure. */
object TestSurfaceParsers extends Properties("Surface parser 2.3a") {

  private implicit val supply: Supply = Supply.create

  private def moduleFiles: List[File] = {
    def walk(f: File): List[File] =
      if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
      else if (f.getName endsWith ".e") List(f) else Nil
    // stdlib AND the user-style example programs (Holes, the relational
    // examples, bugs/ regression cases) — different surface variety
    walk(new File("core/src/main/resources/modules")) ++ walk(new File("core/examples"))
  }

  private def read(f: File): String = {
    val s = scala.io.Source.fromFile(f, "UTF-8")
    try s.mkString finally s.close()
  }

  private def oldHeader(name: String, input: String) =
    ModuleParsers.moduleHeader(name).run(ErParseState.mk(name, input, name), supply.split)

  property("headers agree with the fused pipeline across the stdlib") = secure {
    val bad = List.newBuilder[String]
    var files = 0
    for (f <- moduleFiles) {
      val input = read(f)
      (oldHeader(f.getName, input), SurfaceParsers.module(f.getName, input, f.getName)) match {
        case (Right((_, oldH)), Right(m)) =>
          files += 1
          val h = m.header
          if (h.name != oldH.name) bad += s"${f.getName}: name ${h.name} vs ${oldH.name}"
          val oldImps = oldH.importExports
          if (h.imports.size != oldImps.size)
            bad += s"${f.getName}: ${h.imports.size} imports vs ${oldImps.size}"
          else for ((n, o) <- h.imports zip oldImps) {
            if (n.module != o.module) bad += s"${f.getName}: import ${n.module} vs ${o.module}"
            if (n.isExport != o.isExport) bad += s"${f.getName}/${o.module}: export flag"
            if (n.as != o.as || n.as.map(_.spelling) != o.as)
              if (n.as.map(_.spelling) != o.as) bad += s"${f.getName}/${o.module}: as ${n.as.map(_.spelling)} vs ${o.as}"
            val oldItems: Option[(Boolean, Int)] =
              if (o.using || o.explicits.nonEmpty) Some((o.using, o.explicits.size)) else None
            (n.items, oldItems) match {
              case (Some((u, xs)), Some((ou, on))) =>
                if (u != ou) bad += s"${f.getName}/${o.module}: using flag"
                if (xs.size != on) bad += s"${f.getName}/${o.module}: ${xs.size} items vs $on"
                val newNames = xs.map(_.name.spelling.stripPrefix("(").stripSuffix(")")).toSet
                val oldNames = o.explicits.map {
                  case Single(g, _)      => g.string
                  case Renaming(g, _, _) => g.string
                }.toSet
                if (newNames != oldNames) bad += s"${f.getName}/${o.module}: items $newNames vs $oldNames"
              case (None, None) => ()
              case (a, b) => bad += s"${f.getName}/${o.module}: item presence $a vs $b"
            }
          }
        case (Left(_), Left(_)) => files += 1  // agreement on rejection
        case (Left(err), Right(_)) => bad += s"${f.getName}: old rejects, new accepts: ${err.toString.linesIterator.next()}"
        case (_, Left(err))
            if f.getPath.endsWith("examples/Sample.e") || f.getPath.endsWith("guide/HelloWorld.e") =>
          files += 1  // legacy bodies the old pipeline rejects too; 2.3c
                      // statement grammar now fails them at the body
        case (_, Left(err)) => bad += s"${f.getName}: NEW header failed: ${err.toString.linesIterator.next()}"
      }
    }
    val failures = bad.result()
    (failures.isEmpty :| failures.take(6).mkString(" ;; ")) && ((files ?= 180) :| s"$files files")
  }

  property("the splitter covers every file with ordered, plausible statements") = secure {
    val bad = List.newBuilder[String]
    var fixities = 0
    var statements = 0
    for (f <- moduleFiles) {
      val input = read(f)
      val legacy = f.getPath.endsWith("examples/Sample.e") || f.getPath.endsWith("guide/HelloWorld.e")
      SurfaceParsers.module(f.getName, input, f.getName) match {
        case Left(err) if oldHeader(f.getName, input).isLeft || legacy => ()  // old rejects these too
        case Left(err) => bad += s"${f.getName}: ${err.toString.linesIterator.next()}"
        case Right(m) =>
          statements += m.statements.size
          // spans strictly ordered and statements non-empty for non-trivial files
          val spans = m.statements.map(_.loc.span)
          for ((a, b) <- spans zip spans.drop(1))
            if (b.startLine < a.startLine) bad += s"${f.getName}: unordered spans $a $b"
          // fixity statements really parse (not placeholders), and match an
          // independent regex count of fixity declarations
          val parsed = m.statements.count { case _: SFixity => true; case _ => false }
          val uncommented = input.replaceAll("(?s)\\{-.*?-\\}", "")
          val expected = uncommented.linesIterator.count(_.matches("^(infixl|infixr|infix|prefix|postfix)\\b.*"))
          fixities += parsed
          if (parsed != expected) bad += s"${f.getName}: $parsed fixity stmts vs $expected by regex"
          // nothing may remain unconsumed: every non-fixity statement is a
          // classified placeholder, never an unclassifiable mystery
          m.statements foreach {
            case SErrorStatement(_, msg) if !(msg startsWith "unparsed:") =>
              bad += s"${f.getName}: unexpected error statement $msg"
            case SErrorStatement(loc, msg) if (msg startsWith "unparsed:") && !legacy =>
              // 2.3c: EVERY statement on an old-parseable file parses for
              // real; the two exempted files are legacy syntax the fused
              // pipeline rejects too (verified via Session.parseModule)
              bad += s"${f.getName}:${loc.span.startLine}: $msg fell back to placeholder"
            case _ => ()
          }
      }
    }
    val failures = bad.result()
    (failures.isEmpty :| failures.take(6).mkString(" ;; ")) &&
    ((fixities > 30) :| s"only $fixities fixity statements found — sweep broken?") &&
    ((statements > 1000) :| s"only $statements statements")
  }

  property("2.3b term and pattern shapes parse as written") = secure {
    def stmts(body: String) =
      SurfaceParsers.module("t", "module T where\n" + body, "T")
        .toOption.map(_.statements).getOrElse(Nil)

    val chain = stmts("v = 1 + !! x") match {
      case List(SEquation(_, _, _, SChain(c), _)) =>
        (c.items.collect { case Right(o) => (o.name.spelling, o.posClass) }
          ?= List(("+", PostOperandPos), ("!!", OperandPos))) :| "chain ops"
      case other => falsified :| ("chain: " + other)
    }
    val neg = stmts("f q = -q + 1") match {
      case List(SEquation(_, _, _, SNeg(_, _, SChain(_)), _)) => proved
      case other => falsified :| ("neg: " + other)
    }
    val doTree = stmts("g = do w <- liftDo (Just 1); unit w") match {
      case List(SEquation(_, _, _, SDo(_, List(_: SDoBind, _: SDoExpr)), _)) => proved
      case other => falsified :| ("do: " + other)
    }
    val recVsBrace = (stmts("r = {f = 1, g = 2}"), stmts("b = {1, 2}_M")) match {
      case (List(SEquation(_, _, _, _: SRecordLit, _)),
            List(SEquation(_, _, _, SBraceLit(_, _, Some("M")), _))) => proved
      case other => falsified :| ("rec/brace: " + other)
    }
    val envl = stmts("s f op r = [| f = op, r > 1, p <- i |] r") match {
      case List(SEquation(_, _, _, SApp(SRelEnvelope(_, arrows), _), _)) =>
        (arrows.map(_.getClass.getSimpleName) ?= List("SCombineArrow", "SFilterArrow", "SRenameArrow")) :| "arrow kinds"
      case other => falsified :| ("envelope: " + other)
    }
    val pat = stmts("h (a@(x :: y) : Int) = a") match {
      case List(SEquation(_, _, List(SPParen(_, SPSig(_, SPAs(_, _, SPParen(_, SPChain(_))), _))), _, _)) => proved
      case other => falsified :| ("pattern: " + other)
    }
    chain && neg && doTree && recVsBrace && envl && pat
  }

  property("2.3c type shapes parse as written") = secure {
    def sigTy(body: String) =
      SurfaceParsers.module("t", "module T where\n" + body, "T")
        .toOption.map(_.statements).getOrElse(Nil) match {
        case List(SSigStatement(_, _, t)) => Some(t)
        case _ => None
      }
    val fa = sigTy("f : forall {k} (a: k) b. a -> b") match {
      case Some(STyForall(_, List(k), List(a, b), STyChain(c))) =>
        ((k.spelling, a.name.spelling, a.kind.isDefined, b.kind.isDefined) ?= ("k", "a", true, false)) &&
        ((c.items.collect { case Right(o) => o.name.spelling } ?= List("->")) :| "arrow op")
      case other => falsified :| ("forall: " + other)
    }
    val ex = sigTy("g : exists c. a <- (b, c)") match {
      case Some(STyExists(_, List(_), List(STyChain(c)))) =>
        (c.items.collect { case Right(o) => o.name.spelling } ?= List("<-")) :| "partition op"
      case other => falsified :| ("exists: " + other)
    }
    val sm = sigTy("h : some a. F a -> Int") match {
      case Some(STySome(_, _, List(_), _)) => proved
      case other => falsified :| ("some: " + other)
    }
    val row = sigTy("r : Record {..q} -> [A, B]") match {
      case Some(STyChain(c)) =>
        (c.items.collectFirst { case Left(STyApp(_, STyRowBrace(_, true, _))) => true }.isDefined :| "dots row") &&
        (c.items.collectFirst { case Left(STyRowBracket(_, false, inner)) => inner.size }.getOrElse(-1) ?= 2)
      case other => falsified :| ("rows: " + other)
    }
    fa && ex && sm && row
  }

  /** 2.3d: the 1.3b rejected corpus, re-checked under the new parser.
    * Decision (f): rejection-vs-acceptance parity is gate-hard, but a
    * refusal may legitimately MOVE to a later pass — each moved case is
    * recorded here with its owing pass, and that pass's item must flip
    * the disposition to a refusal when it lands. */
  property("2.3d rejected-corpus dispositions") = secure {
    sealed trait Disp
    case class ParsesNow(owedBy: String) extends Disp   // refusal moves to the named pass
    case object StillRejects extends Disp
    val corpus: List[(String, String, Disp)] = List(
      ("unknown op in chain",      "v = 1 %%% 2",                          ParsesNow("3.3 re-associate: no fixity for %%%")),
      ("op before its fixity",     "v = 1 :%: 2\ninfixl 5 :%:\n(:%:) x y = x", ParsesNow("3.3 re-associate: positional fixity env")),
      ("mixed assoc equal prec",   "infixl 5 <%>\ninfixr 5 <^>\n(<%>) x y = x\n(<^>) x y = y\nv = 1 <%> 2 <^> 3", ParsesNow("3.3 re-associate: ambiguous operator")),
      ("refix imported operator",  "infixr 3 &&",                          ParsesNow("3.3 fixity env: Multiple fixity definitions")),
      ("postfix+infix collision",  "infixl 5 :%:\npostfix 5 :%:\n(:%:) x y = x", ParsesNow("3.3 fixity env: shared bucket")),
      ("top-level import shadow",  "id = 1",                               ParsesNow("3.2 rename: would shadow global definition")),
      ("data-con operator binder", "v = let (::) a b = 7 in 1",            ParsesNow("3.2 rename: constructor binder refusal")),
      ("missing bracket hooks",    "v = [1, 2]",                           ParsesNow("3.4 desugar: empty_Bracket/cons_Bracket unresolved")),
      ("empty brace literal",      "v = {}",                               ParsesNow("3.2/3.4: renamer rejects {} (old crashes masked by race)")),
      ("bare prefix stacking",     "prefix 9 !!\n(prefix !!) q = 0 - q\nv = !! !! 5", StillRejects),
      ("dead underscore affix",    "v = 1 +_ 2",                           StillRejects))
    val bad = List.newBuilder[String]
    for ((label, body, want) <- corpus) {
      val r = SurfaceParsers.module(label, "module T where\n" + body, "T")
      val placeholderFree = r match {
        case Right(m) =>
          def ok(s: SStatement): Boolean = s match {
            case _: SErrorStatement => false
            case SPrivateBlock(_, ss) => ss.forall(ok)
            case _ => true
          }
          m.statements.forall(ok)
        case Left(_) => false
      }
      (want, placeholderFree) match {
        case (ParsesNow(_), true)  => ()
        case (StillRejects, false) => ()
        case (ParsesNow(owed), false) =>
          bad += s"$label: expected to parse (refusal owed by $owed) but was rejected/placeholdered"
        case (StillRejects, true) =>
          bad += s"$label: expected a parse rejection but it parsed"
      }
    }
    val failures = bad.result()
    failures.isEmpty :| failures.mkString(" ;; ")
  }
}



