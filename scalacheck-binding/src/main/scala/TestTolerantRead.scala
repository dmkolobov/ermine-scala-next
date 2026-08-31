package com.clarifi.reporting

import com.clarifi.reporting.ermine.parsing.{ ErParseState, ModuleParsers }
import com.clarifi.reporting.ermine.rename.NewPipeline
import com.clarifi.reporting.ermine.session.{ Session => S, SessionEnv }
import com.clarifi.reporting.ermine.surface.{ SErrorStatement, SurfaceParsers }

import org.scalacheck._
import Prop._
import scalaparsers.{ Death, Supply }

import java.io.File

/** Stage 2 item 5.1: readModule (strict) and readModuleTolerant are ONE
  * traversal with tolerance off and on.  Two things keep them from
  * drifting apart, and both are checked over the whole corpus (stdlib
  * AND core/examples — the standing 180-file rule):
  *
  *  - AGREEMENT: on the same source in the same session the strict
  *    reader is silent exactly when the tolerant reader has no
  *    diagnostics, and when it dies it dies with the tolerant reader's
  *    FIRST diagnostic rendered byte-for-byte (NewPipeline.render is the
  *    shared renderer, so this compares the real refusal text).
  *  - SILENCE ON GOOD CODE: swept in dependency order, so each module is
  *    read with its imports loaded and ITSELF not — the env the strict
  *    reader sees inside Session.load.  Read a loaded module again and
  *    its own globals come back as imports ("would shadow global
  *    definition" for every head), which is exactly why the LSP's
  *    checkFile hoists the import load out of Session.load.
  */
object TestTolerantRead extends Properties("Tolerant read") {
  private val fx = ErmineFixture()
  import fx._

  /** The corpus sweep gets its OWN fixture.  ErmineFixture's loadModules
    * writes its result back into baseEnv to make later sessions fast, and
    * ScalaCheck runs a Properties object's properties concurrently — so
    * sharing `fx` with the pins below means the sweep's session may or
    * may not already hold part of the stdlib, depending on which
    * property won the race.  A module read while ITSELF loaded sees its
    * own globals arrive as imports and every top-level head draws "would
    * shadow global definition"; that is the whole point of the sweep's
    * dependency ordering, and it made this property fail about one run
    * in three.  (The fixture's own scaladoc says one per Properties
    * instance; one per PROPERTY is what a writeback-shared baseEnv
    * actually needs.) */
  private val sweepFx = ErmineFixture()

  private val stdlibRoot = new File("core/src/main/resources/modules")

  private def walk(f: File): List[File] =
    if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
    else if (f.getName endsWith ".e") List(f) else Nil

  private def corpusFiles: List[File] = walk(stdlibRoot) ++ walk(new File("core/examples"))

  private def slurp(f: File): String =
    new String(java.nio.file.Files.readAllBytes(f.toPath), "UTF-8")

  /** Both readers over one source in one session.  `strict` is the
    * rendered refusal, if any; `tolerant` is every diagnostic. */
  private def both(fileName: String, defaultName: String, src: String)
                  (implicit s: SessionEnv, su: Supply)
      : (Option[String], Either[String, List[NewPipeline.Diag]]) = {
    val (_, mh) = S.parse(ModuleParsers.moduleHeader(defaultName),
                          ErParseState.mk(fileName, src, defaultName))
    val strict =
      try { NewPipeline.readModule(fileName, src, mh); None }
      catch { case Death(e, _) => Some(e.toString) }
    val tolerant =
      try Right(NewPipeline.readModuleTolerant(fileName, src, mh).diagnostics)
      catch { case Death(e, _) => Left(e.toString) }   // a module body the
                                                       // splitter cannot even
                                                       // shape: both readers die
    (strict, tolerant)
  }

  private def agree(name: String, src: String, strict: Option[String],
                    tol: Either[String, List[NewPipeline.Diag]]): Prop = tol match {
    case Left(msg) =>
      (strict == Some(msg)) :| s"$name: tolerant died but strict said ${strict.map(_.take(160))}"
    case Right(ds) =>
      ((strict.isEmpty == ds.isEmpty) :|
        s"$name: strict=${strict.map(_.take(160))} tolerant=${ds.map(_.message).take(3)}") &&
      strict.map(r =>
        (ds.nonEmpty && r == NewPipeline.render(name, src, ds.head).toString) :|
          s"$name: strict rendering drifted\n--- strict ---\n$r\n--- tolerant ---\n" +
          ds.headOption.map(NewPipeline.render(name, src, _).toString).getOrElse("<none>")
      ).getOrElse(proved)
  }

  private final case class Item(f: File, defaultName: String, imports: Set[String], src: String)

  property("strict and tolerant agree, and the tolerant read is silent, over the corpus") = secure {
    val files = corpusFiles
    sweepFx.session { implicit s =>
      implicit val su: Supply = sweepFx.supply
      // Guard the precondition rather than trusting it: a preloaded
      // corpus module would silently turn the sweep into a shadow-
      // diagnostic parade instead of failing where the cause is.
      val preloaded = s.loadedModules.keySet & corpusFiles.map(_.getName.stripSuffix(".e")).toSet
      val items = files.flatMap { f =>
        val src = slurp(f)
        val dn = f.getName.stripSuffix(".e")
        try {
          val (_, mh) = S.parse(ModuleParsers.moduleHeader(dn),
                                ErParseState.mk(f.getPath, src, dn))
          Some(Item(f, dn, mh.importExports.map(_.module).toSet, src))
        } catch { case Death(_, _) => None }   // a header both readers refuse
      }
      // Sweep in dependency order: a module is read when its imports are
      // loaded and it is not.  Imports outside the corpus (Builtin and
      // friends, registered by Lib.preamble) never gate.
      val corpusNames = items.map(_.defaultName).toSet
      def satisfied(i: Item): Boolean =
        i.imports.forall(m => s.loadedModules.contains(m) || !corpusNames.contains(m.split('.').last))

      var pending = items
      var props = List.empty[Prop]
      var clean = 0
      var swept = 0
      val noisy = List.newBuilder[String]
      var progress = true
      while (progress && pending.nonEmpty) {
        val (ready, rest) = pending.partition(satisfied)
        progress = ready.nonEmpty
        ready.foreach { it =>
          val (strict, tol) = both(it.f.getPath, it.defaultName, it.src)
          props ::= agree(it.f.getPath, it.src, strict, tol)
          swept += 1
          tol match {
            case Right(Nil) => clean += 1
            case Right(ds)  => noisy += (it.f.getName + ": " +
              ds.map(d => (d.phase.name, d.span.startLine, d.message)).take(2).mkString)
            case Left(msg)  => noisy += (it.f.getName + " (unshapeable): " +
              msg.linesIterator.take(1).mkString)
          }
          try S.load(S.Filesystem(it.f.getPath, exotic = true)) catch { case Death(_, _) => () }
        }
        pending = rest
      }
      val bad = noisy.result()
      (preloaded.isEmpty :| s"session came preloaded with corpus modules: $preloaded") &&
      ((files.size >= 180) :| s"only ${files.size} corpus files") &&
      ((pending.isEmpty) :| s"never became ready: ${pending.map(_.f.getName).take(6)}") &&
      ((swept >= 180) :| s"only $swept files swept") &&
      // Four corpus entries are genuinely broken, and they are exactly
      // the examples "all interesting examples load" leaves out:
      // Sample.e (explicit layout — the splitter cannot shape it at all,
      // so both readers die on it identically), HelloWorld.e (an
      // unparseable statement), Interp.e (`==` never declared) and
      // Yahoo.e (a definition shadowing an imported global).
      ((clean >= swept - 4) :| s"$clean of $swept read clean; noisy: ${bad.take(6).mkString(" ;; ")}") &&
      ((bad.size <= 4) :| s"newly noisy: ${bad.mkString(" ;; ")}") &&
      props.foldLeft(proved: Prop)(_ && _)
    }
  }

  // ---- per-phase pins: each phase's first diagnostic IS the refusal ----

  private val pinImports = List("Function", "List", "Primitive")

  /** Five lines before the body: `module`, three imports, and a blank. */
  private def header(body: String): String =
    "module TR where\nimport Function\nimport List\nimport Primitive\n\n" + body

  /** (strict refusal, the tolerant reader's diagnostics).  A pin whose
    * body the splitter cannot shape at all would land in the Left; none
    * of them do, and `nonEmpty` below would catch it if one started to. */
  private def pin(src: String): (Option[String], List[NewPipeline.Diag]) =
    session { implicit s =>
      implicit val su: Supply = supply
      loadModules(pinImports)
      val (strict, tol) = both("TR", "TR", src)
      (strict, tol.getOrElse(Nil))
    }

  private def phasePin(what: String, body: String)(extra: List[NewPipeline.Diag] => Prop): Prop = {
    val src = header(body)
    val (strict, ds) = pin(src)
    (strict.isDefined :| s"$what: strict reader accepted it") &&
      (ds.nonEmpty :| s"$what: tolerant reader found nothing") &&
      agree("TR", src, strict, Right(ds)) && extra(ds)
  }

  property("syntax: an unparseable statement") =
    phasePin("syntax", "f = = 3\n") { ds =>
      ((ds.head.phase == NewPipeline.Phase.Syntax) :| ds.head.phase.name) &&
      // 5.2: the position is the parser's own — the second `=`, column 5
      // of the body line — not the statement's start
      ((ds.head.span.startLine == 6 && ds.head.span.startCol == 5) :| s"span ${ds.head.span}") &&
      ((ds.head.message contains "expected") :| ds.head.message) }

  property("syntax: an error on a continuation line is blamed there") =
    phasePin("syntax", "total a =\n  = a\n") { ds =>
      ((ds.head.span.startLine == 7 && ds.head.span.startCol == 3) :| s"span ${ds.head.span}") &&
      ((ds.head.message contains "expected") :| ds.head.message) }

  property("rename: shadowing an imported global") =
    phasePin("rename", "id = 1\n") { ds =>
      (ds.head.phase == NewPipeline.Phase.Rename) :| s"${ds.head.phase.name}: ${ds.head.message}" }

  property("reassoc: an unknown operator") =
    phasePin("reassoc", "v = 1 %%%% 2\n") { ds =>
      (ds.head.phase == NewPipeline.Phase.Reassoc) :| s"${ds.head.phase.name}: ${ds.head.message}" }

  property("assemble: a signature with no definition") =
    phasePin("assemble", "g : Int\n") { ds =>
      ((ds.head.phase == NewPipeline.Phase.Assemble) :| s"${ds.head.phase.name}: ${ds.head.message}") &&
      ((ds.head.message == "missing definition") :| ds.head.message) }

  property("assemble: equations of one name split by another statement") = {
    val src = header("f 0 = 1\ndata D = MkD\nf 1 = 2\n")
    val (strict, ds) = pin(src)
    (strict.isDefined :| "strict reader accepted it") &&
      (ds.nonEmpty :| "tolerant reader found nothing") &&
      agree("TR", src, strict, Right(ds)) &&
      // 5.1 fixed the cross-block case: it used to report Span(0,0,0,0),
      // which is not a position an editor can show
      ((ds.head.span.startLine == 8 && ds.head.span.startCol == 1) :| s"span ${ds.head.span}") &&
      ((ds.head.message contains "interleaved equations for f") :| ds.head.message)
  }

  property("every broken statement gets its own diagnostic") = {
    val src = header("good1 = 1\nbad1 = = 3\ngood2 = 2\nbad2 = ) 3\ngood3 = 3\n")
    val (strict, ds) = pin(src)
    (strict.isDefined :| "strict reader accepted it") &&
      ((ds.size == 2) :| s"got ${ds.size}: ${ds.map(d => (d.phase.name, d.span, d.message))}") &&
      (ds.forall(_.phase == NewPipeline.Phase.Syntax) :| ds.map(_.phase.name).toString) &&
      ((ds.map(_.span.startLine) == List(7, 9)) :| ds.map(_.span).toString)
  }

  // ---- 5.2b: the splitter is TOTAL ----------------------------------
  // Every one of these used to make SurfaceParsers.module return Left, so
  // the file yielded no SErrorStatement, no per-statement diagnostics and
  // no navigation at all.  The first two parse as a proper PREFIX of
  // their extent and leave junk behind; the third commits inside a
  // non-binding alternative, which `|` short-circuits on.

  private val brokenShapes: List[(String, String)] = List(
    "prefix parse, trailing operator" -> "total a b =\n  a +\n  b +\n  = 3\n",
    "prefix parse, leftover token"    -> "total a b =\n  a\n  ) b\n",
    "committed failure in `data`"     -> "data D = \n",
    "committed failure in a sig"      -> "g : \n",
    "a broken equation"               -> "f = = 3\n")

  property("the splitter is total: every broken shape still shapes the module") = secure {
    brokenShapes.map { case (what, body) =>
      val src = "module TR where\n\ngood1 = 1\n" + body + "good2 = 2\n"
      SurfaceParsers.module("TR", src, "TR") match {
        case Left(err) =>
          falsified :| s"$what: the splitter gave up: " +
            err.pretty.toString.linesIterator.take(1).mkString
        case Right(m) =>
          val kinds = m.statements.map {
            case _: SErrorStatement => "error"
            case _                  => "ok"
          }
          ((kinds.count(_ == "error") >= 1) :| s"$what: no error statement: $kinds") &&
          ((kinds.headOption.contains("ok") && kinds.lastOption.contains("ok")) :|
            s"$what: healthy neighbours lost: $kinds")
      }
    }.foldLeft(proved: Prop)(_ && _)
  }

  property("a prefix parse is blamed at the leftover, not at the head") = {
    val src = header("total a b =\n  a +\n  b +\n  = 3\n")
    val (strict, ds) = pin(src)
    (strict.isDefined :| "strict reader accepted it") &&
      (ds.nonEmpty :| "tolerant reader found nothing") &&
      agree("TR", src, strict, Right(ds)) &&
      // the statement starts at line 6; the junk is on line 9
      ((ds.head.span.startLine == 9 && ds.head.span.startCol == 3) :| s"span ${ds.head.span}")
  }

  property("a broken statement does not cost its healthy neighbours") = {
    val src = header("good1 = 1\nbad1 = = 3\ngood2 = 2\n")
    session { implicit s =>
      implicit val su: Supply = supply
      loadModules(pinImports)
      val (_, mh) = S.parse(ModuleParsers.moduleHeader("TR"), ErParseState.mk("TR", src, "TR"))
      val r = NewPipeline.readModuleTolerant("TR", src, mh)
      val bound = (r.module.implicits.map(_.v) ++ r.module.explicits.map(_.v))
        .flatMap(_.name.map(_.string)).toSet
      (bound.contains("good1") && bound.contains("good2")) :| s"bound: $bound"
    }
  }
}
