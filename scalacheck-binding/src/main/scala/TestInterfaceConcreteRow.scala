package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.parsing.{ ErParseState, InterfaceParsers }
import com.clarifi.reporting.ermine.parsing.ErParseState.Implicits._
import com.clarifi.reporting.ermine.session.{ CheckMethod, Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.session.Session.SourceFile
import com.clarifi.reporting.ermine.tools.G1Compare
import scalaparsers.Loc
import scalaz.std.list._

import org.scalacheck._
import Prop._

import java.io.File
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.{ Files, Path, Paths, StandardCopyOption }

/** Stage F4, ticket E1 (`tracker/TICKET-stdlib-findings.md`, section E): the
  * interface PRINTER and the interface GRAMMAR must agree on the whole
  * published form, and they did not agree on a concrete row.
  *
  * `Pretty.ppName` spells a field label `Global(mod, name, Idfix)` fully
  * qualified — `(|Currency.currencyCode|)` — and `TypeParsers.rho`'s
  * `dottedName` accepted only `Upper(.Upper)+`, so a label whose last segment
  * starts LOWER case was unreadable.  `Session.dep`'s `preCk` therefore
  * answered `None`, the module was `CheckMethod.Full` on EVERY load and its
  * `.ei` was rewritten every time.  Nothing failed: the cost was silent.
  *
  * Three properties, in `TestInterfaceRoundTrip`'s / `TestInterfaceKey`'s style
  * (own temp workspace, `Session.depCache.clear()` under
  * `ErmineFixture.literalLock`, modules owning every interface they depend on):
  *
  *  1. `warm read of a published concrete row` — a module publishing
  *     `r <- (h, (|foo|))` warm-reads.  FAILS before the fix (warm = `Full`).
  *  2. `every corpus interface warm-reads, and none is rewritten` — the whole
  *     corpus (stdlib + `core/examples`) is generated into a temp tree with
  *     interfaces on and then loaded AGAIN over the same tree: every module with
  *     an `.ei` must be `CheckMethod.Interface` and no `.ei` may be rewritten.
  *     70 of 245 were rewritten forever before the fix.
  *  3. `every corpus interface parses and re-prints stably` — every one of those
  *     `.ei` parses with `InterfaceParsers.interfaceSigs`, re-prints through the
  *     printer `Dep.writeInterface` uses, and parses again to an
  *     ALPHA-EQUIVALENT type.  (Not to the same bytes; see that property.)
  */
object TestInterfaceConcreteRow extends Properties("Interface concrete row") {

  // ------------------------------------------------------------------ (1)

  /* NO IMPORTS, deliberately, for `TestInterfaceKey`'s reason: `preChecked`
   * answers `Interface` only when every import was itself interface-checked, so
   * a module importing the stdlib is warm only if the shared target tree's
   * `.ei` are current — and the dep cache is process-global while ScalaCheck
   * runs properties concurrently.  `Builtin` is implicitly imported into every
   * module (`ModuleParsers.scala:34`), which is where `Record` comes from. */
  private val srcRow =
    """module RowConc where
      |
      |-- THE SHAPE: a partition whose PART is a concrete row.  Published as
      |--   rSig : forall (r: rho). r <- ((|RowConc.foo|), h) => ...
      |rSig : r <- (h, (|foo|)) => Record r -> Record r
      |rSig x = x
      |
      |-- a concrete row as a TYPE, same lower-case label, same failure
      |tSig : Record (|bar|) -> Record (|bar|)
      |tSig x = x
      |
      |-- CONTROL: an UPPER-case label, which `dottedName` always could read
      |uSig : Record (|Baz|) -> Record (|Baz|)
      |uSig x = x
      |
      |-- a label with the other characters `tailChar` admits
      |oSig : Record (|a#b, c'd, e_1|) -> Record (|a#b, c'd, e_1|)
      |oSig x = x
      |""".stripMargin

  private def rowWorkspace(): Path = {
    val d = Files.createTempDirectory("ermine-row")
    Files.write(d.resolve("RowConc.e"), srcRow.getBytes(UTF_8))
    d
  }

  private def session(dir: Path)(implicit su: scalaparsers.Supply): SessionEnv = {
    implicit val printer: Printer = Printer.ignore
    implicit val e: SessionEnv = new SessionEnv(
      _typeCheck = Some(true), _useInterface = Some(true))
    Lib.preamble
    e.loadFile = SourceFile.inOrder(SourceFile.filesystem(dir.toString) _, e.loadFile)
    e
  }

  private def loadRow(dir: Path)(implicit su: scalaparsers.Supply): Option[CheckMethod] = {
    implicit val printer: Printer = Printer.ignore
    Session.depCache.clear()
    val e = session(dir)
    Session.loadModules(List("RowConc"))(e, su, printer)
    e.loadedModules.get("RowConc")
  }

  property("warm read of a published concrete row") = secure {
    implicit val su: scalaparsers.Supply = scalaparsers.Supply.create
    val dir = rowWorkspace()
    try prop1(dir) finally deleteTree(dir)
  }

  private def prop1(dir: Path)(implicit su: scalaparsers.Supply): Prop = {
    val ei = dir.resolve("RowConc.ei")

    ErmineFixture.literalLock.synchronized {
      val cold  = loadRow(dir)
      val wrote = Files.exists(ei)
      val body  = if (wrote) new String(Files.readAllBytes(ei), UTF_8) else ""
      val stamp = if (wrote) Files.getLastModifiedTime(ei) else null

      // the shape really is published: a partition with a concrete part, and a
      // fully-qualified lower-case label.  (Guards the property against a
      // future printer that spells it some other way and quietly stops
      // exercising the grammar this is about.)
      val publishesPart  = body.contains("<- ((|RowConc.foo|)") || body.contains(", (|RowConc.foo|))")
      val publishesLower = body.contains("(|RowConc.bar|)")

      val warm      = loadRow(dir)
      val unchanged = wrote && Files.getLastModifiedTime(ei) == stamp &&
                      new String(Files.readAllBytes(ei), UTF_8) == body

      (cold ?= Some(CheckMethod.Full))       :| s"cold $cold" &&
      wrote                                  :| "interface written" &&
      publishesPart                          :| s"no concrete part published:\n$body" &&
      publishesLower                         :| s"no lower-case label published:\n$body" &&
      (warm ?= Some(CheckMethod.Interface))  :| s"warm $warm (the .ei did not read back)\n$body" &&
      unchanged                              :| "the warm load rewrote the .ei"
    }
  }


  // ------------------------------------------------------------------ (2)

  /** The corpus: the stdlib module tree, and every `core/examples` directory
    * whose modules are meant to type-check.  `shouldfail/`, `bugs/`,
    * `shouldfail-controls/` and `incomplete/` are excluded — a module that does
    * not check publishes no `.ei`, and `incomplete/` holds modules that diverge. */
  private val stdlibRoot   = new File("core/src/main/resources/modules")
  private val exampleRoot  = new File("core/examples")
  private val exampleDirs  = List(
    exampleRoot,
    new File("core/examples/Ai"),      new File("core/examples/Wide"),
    new File("core/examples/Algebra"), new File("core/examples/Time"),
    new File("core/examples/Present"), new File("core/examples/Lang"))

  private def walkE(f: File): List[File] =
    if (f.isDirectory) Option(f.listFiles).toList.flatMap(_.toList.sortBy(_.getName).flatMap(walkE))
    else if (f.getName endsWith ".e") List(f) else Nil

  private def walkEi(f: File): List[File] =
    if (f.isDirectory) Option(f.listFiles).toList.flatMap(_.toList.sortBy(_.getName).flatMap(walkEi))
    else if (f.getName endsWith ".ei") List(f) else Nil

  /** The `module X where` a file declares, if it declares one. */
  private val moduleHeader = """(?m)^\s*module\s+([A-Za-z][A-Za-z0-9_.']*)\s+where""".r
  private def declaredModule(f: File): Option[String] = {
    val s = new String(Files.readAllBytes(f.toPath), UTF_8)
    moduleHeader.findFirstMatchIn(s).map(_.group(1))
  }

  /** Copy `files` (paths relative to `srcRoot`) into `dst`; answer the module
    * names whose DECLARED name matches their path, so
    * `SourceFile.filesystem(dst)` can find them by name. */
  private def stage(srcRoot: File, files: List[File], dst: Path): List[String] = {
    val out = List.newBuilder[String]
    for (f <- files) {
      val rel  = srcRoot.toPath.relativize(f.toPath).toString
      val name = rel.stripSuffix(".e").replace(File.separatorChar, '.')
      val tgt  = dst.resolve(rel)
      Files.createDirectories(tgt.getParent)
      Files.copy(f.toPath, tgt, StandardCopyOption.REPLACE_EXISTING)
      if (declaredModule(f) == Some(name)) out += name
    }
    out.result()
  }

  private final case class Corpus(
    root: Path, mods: List[String],
    cold: Map[String, CheckMethod], warm: Map[String, CheckMethod],
    eis: List[File], rewritten: List[String])

  /** The staged corpus is ~3.5 MB, so it is DELETED rather than left in the
    * system temp directory (R-5).
    *
    * FROM A SHUTDOWN HOOK, not from a `finally` in each property.  The tree is a
    * `lazy val` shared by two properties, so a `finally` has to know when the LAST
    * reader is done; the reference count that did that (initialised to 2, one per
    * property) assumed each property is evaluated exactly once, which is true only
    * at ScalaCheck's default one worker.  Raised to `-workers 4` for the item-6.0
    * pinning runs, each `secure` property is evaluated once per worker, the count
    * reached zero after the first two, and the tree was deleted under a reader
    * still walking it: `NoSuchFileException: .../examples/Accumulate.ei`.  A hook
    * cannot race a reader at all — it runs when the JVM is on its way out — and it
    * also survives a property that dies before its `finally`. */
  private def deleteTree(p: Path): Unit = ErmineFixture.deleteTree(p)

  private def deleteAtExit(root: Path): Unit =
    java.lang.Runtime.getRuntime.addShutdownHook(new Thread(() => deleteTree(root), "ermine-corpus-cleanup"))

  /** Trees an earlier run left behind (before this cleanup existed, or after a
    * kill -9).  Only ones older than an hour, so a concurrent run's tree is
    * never touched. */
  private def sweepStaleCorpusTrees(keep: Path): Unit =
    try {
      val tmp = Paths.get(System.getProperty("java.io.tmpdir"))
      val cutoff = System.currentTimeMillis - 3600000L
      val ds = Files.newDirectoryStream(tmp, "ermine-ei-corpus*")
      try ds.forEach { d =>
        if (d != keep && Files.isDirectory(d) &&
            Files.getLastModifiedTime(d).toMillis < cutoff) deleteTree(d)
      } finally ds.close()
    } catch { case _: Throwable => () }

  /** Generate the whole corpus into a temp tree with interfaces ON, then load
    * it a SECOND time in a fresh session over the same tree.  Built once.
    *
    * `ErmineFixture.literalLock` is held across the WHOLE thing — the staging,
    * BOTH passes, each `Session.depCache.clear()`, the mtime sleep and the
    * comparison — as `TestInterfaceKey` holds it across its five loads.  Nothing
    * this suite does touches the process-global dep cache outside it.  That is
    * the discipline, not a cure: the suites that make the cache racy
    * (`TestNewPipeline`, `TestLower`, `TestTolerantCheck`, `TestTolerantRead`,
    * `TestStage1Pins`, `TestEditorBuffers`) never TAKE this lock, so no amount
    * of locking here excludes them — see F4-REVIEW R-1 and ticket E4. */
  private lazy val corpus: Corpus = ErmineFixture.literalLock.synchronized {
    implicit val su: scalaparsers.Supply = scalaparsers.Supply.create
    implicit val printer: Printer = Printer.ignore

    val root = Files.createTempDirectory("ermine-ei-corpus")
    deleteAtExit(root)
    sweepStaleCorpusTrees(root)
    val libD = root.resolve("modules")
    val exD  = root.resolve("examples")
    Files.createDirectories(libD); Files.createDirectories(exD)

    val libMods = stage(stdlibRoot, walkE(stdlibRoot), libD)
    val exFiles = exampleDirs.flatMap(d =>
      Option(d.listFiles).toList.flatMap(_.toList).filter(f => f.isFile && (f.getName endsWith ".e")))
      .sortBy(_.getPath)
    val exMods  = stage(exampleRoot, exFiles, exD)
    val mods    = libMods ++ exMods

    def pass(): Map[String, CheckMethod] = {
      Session.depCache.clear()
      implicit val e: SessionEnv = new SessionEnv(_typeCheck = Some(true), _useInterface = Some(true))
      Lib.preamble
      e.loadFile = SourceFile.inOrder(
        SourceFile.filesystem(libD.toString) _, SourceFile.filesystem(exD.toString) _, e.loadFile)
      // ONE MODULE AT A TIME, each in its own try: the corpus is a mixture on
      // purpose and a module that does not check must not stop the rest.
      for (m <- mods) try Session.loadModules(List(m)) catch { case _: Throwable => () }
      e.loadedModules.toMap
    }

    val cold  = pass()
    val eis   = (walkEi(libD.toFile) ++ walkEi(exD.toFile)).sortBy(_.getPath)
    val stamp = eis.map(f => f.getPath -> Files.getLastModifiedTime(f.toPath)).toMap
    // mtime granularity: make sure a rewrite is observable
    Thread.sleep(1100)
    val warm  = pass()
    val rewritten = eis.filter(f => Files.getLastModifiedTime(f.toPath) != stamp(f.getPath))
                       .map(f => root.relativize(f.toPath).toString)
    Corpus(root, mods, cold, warm, eis, rewritten)
  }

  /** Parse an `.ei` body with the interface grammar.  `recognizedCons` is
    * seeded, as `Session.dep`'s `preCk` seeds it; NOTHING ELSE is, deliberately
    * — a published type is FULLY QUALIFIED, so `interfaceCon` resolves every
    * constructor out of `recognizedCons` and no import map is needed.  (Seeding
    * one is actively wrong here: an open import of every loaded module makes a
    * label like `label`, exported by four corpus modules, "ambiguous", which the
    * real reader never sees because it uses the MODULE's own imports.) */
  private def parseSigs(path: String, text: String)(implicit e: SessionEnv, su: scalaparsers.Supply)
      : List[(Name, Type)] = {
    val ps0 = ErParseState.mk(path, text, "F4")
    val ps  = ps0.copy(s = ps0.s.copy(recognizedCons = e.cons ++ e.privateCons))
    Session.parse(InterfaceParsers.interfaceSigs, ps)._2
  }

  /** Print signatures the way `Dep.writeInterface` does: sorted by name,
    * `Pretty.prettyVarHasType(_, FullyQualified)`, one per line. */
  private def printSigs(sigs: List[(Name, Type)]): String = {
    val w = new java.io.StringWriter()
    // NEGATIVE ids: `V.equals` is id-based and the printer's fresh-name map is
    // keyed on the var, so a synthetic term var must not collide with a type
    // var the parse minted from the Supply (which draws non-negative ids).
    val vs = sigs.sortBy(_._1.toString).zipWithIndex.map {
      case ((n, t), i) => V(Loc.builtin, -(i + 1), Some(n), Bound, t)
    }
    scalaparsers.Document.vsep(vs.map(Pretty.prettyVarHasType(_, Pretty.FullyQualified))).format(1000000, w)
    w.toString
  }

  /** Alpha-equivalence between a type and its own RE-PRINT.
    *
    * This is `G1Compare.alphaEq` with ONE change: it answers EVERY bijection,
    * lazily, instead of the first one it finds.  Binders are paired exactly as
    * `G1Compare` pairs them — `Forall` POSITIONALLY, `Exists` lazily through the
    * constraint multiset — so nothing is relaxed; the search is only completed.
    *
    * Why completeness is needed.  `Part.apply` REVERSES a partition's right-hand
    * side (its fold conses) and merges every concrete part into one
    * `ConcreteRho`, so a re-parse of `r <- (h, t)` is `Part(r, [t, h])`;
    * `G1Compare` already matches a `Part`'s rhs and an `Exists`' constraints as
    * MULTISETS for that reason.  But it answers one bijection per comparison,
    * and the first one a greedy match finds inside `c <- (rs, so)` against
    * `c <- (so, rs)` is the swap, which a later constraint then contradicts —
    * with nothing to backtrack into.  Measured on this corpus: plain
    * `G1Compare.alphaEq` falsifies property 3 on 15 of 245 interfaces; this
    * passes on all 245.  (Relaxing `Forall` to a lazy pairing as well was tried
    * and dropped: it buys nothing here and would only weaken the property.)
    *
    * Every case that can branch — `Forall`, `Exists`, `Part`, `AppT` — is
    * handled here so the completeness survives the recursion; the deterministic
    * leaves delegate to `G1Compare.alphaEq`, which stays the shared definition.
    * Like `G1Compare`, it does not compare binder KINDS. */
  private type Bij = G1Compare.Bij

  private def aeqs(a: Type, b: Type, e: Bij): LazyList[Bij] = (a, b) match {
    case (f1: Forall, f2: Forall) =>
      if (f1.ks.length != f2.ks.length || f1.ts.length != f2.ts.length) LazyList.empty
      else {
        // POSITIONAL, exactly as `G1Compare.alphaEq` does it
        val e2 = e.copy(
          tv = e.tv ++ f1.ts.map(_.id).zip(f2.ts.map(_.id)),
          kv = e.kv ++ f1.ks.map(_.id).zip(f2.ks.map(_.id)))
        // body before constraints: a search-order choice only (the universals the
        // body mentions are already pinned, so this prunes), not a semantic one
        for {
          e3 <- aeqs(f1.body, f2.body, e2)
          e4 <- aeqs(f1.constraints, f2.constraints, e3)
        } yield e4
      }
    case (x1: Exists, x2: Exists) =>
      if (x1.xs.length != x2.xs.length || x1.constraints.length != x2.constraints.length) LazyList.empty
      else {
        val e2 = e.copy(open1 = e.open1 ++ x1.xs.map(_.id), open2 = e.open2 ++ x2.xs.map(_.id))
        multiset(x1.constraints, x2.constraints, e2).map(_.copy(open1 = e.open1, open2 = e.open2))
      }
    case (p1: Part, p2: Part) =>
      aeqs(p1.lhs, p2.lhs, e).flatMap(multiset(p1.rhs, p2.rhs, _))
    case (AppT(f1, a1), AppT(f2, a2)) => aeqs(f1, f2, e).flatMap(aeqs(a1, a2, _))
    case (Memory(_, b1), Memory(_, b2)) => aeqs(b1, b2, e)
    case _ => G1Compare.alphaEq(a, b, e).to(LazyList)
  }

  /** Every way of matching `cs1` against a permutation of `cs2`. */
  private def multiset(cs1: List[Type], cs2: List[Type], e: Bij): LazyList[Bij] =
    cs1 match {
      case Nil => if (cs2.isEmpty) LazyList(e) else LazyList.empty
      case c1 :: rest =>
        LazyList.from(cs2.indices).flatMap(j =>
          aeqs(c1, cs2(j), e).flatMap(e2 => multiset(rest, cs2.patch(j, Nil, 1), e2)))
    }

  /** The names in `a` whose type is not alpha-equivalent to `b`'s. */
  private def alphaEqAll(a: List[(Name, Type)], b: List[(Name, Type)]): List[Name] = {
    val bm = b.toMap
    if (a.length != b.length) a.map(_._1)
    else a.collect { case (n, t) if !bm.get(n).exists(u => aeqs(t, u, G1Compare.Bij.empty).nonEmpty) => n }
  }

  /** Criterion (3) of ticket E1 at unit-test scale, through the REAL reader:
    * every `.ei` the corpus produces is read back by `Session.dep`'s `preCk`,
    * so the module is `CheckMethod.Interface` on the second load and its `.ei`
    * is not rewritten.  Before the fix, 70 of them were rewritten forever. */
  property("every corpus interface warm-reads, and none is rewritten") = secure {
    prop2(corpus)
  }

  private def prop2(c: Corpus): Prop = {
    val published = c.eis.map { f =>
      // <root>/modules/Layout/Report/Relation.ei -> Layout.Report.Relation
      val rel = c.root.relativize(f.toPath).toString
      rel.dropWhile(_ != File.separatorChar).drop(1).stripSuffix(".ei").replace(File.separatorChar, '.')
    }
    val notWarm = published.filter(m => c.warm.get(m) != Some(CheckMethod.Interface))

    (c.eis.length >= 200)  :| s"only ${c.eis.length} interfaces generated (expected the whole corpus)" &&
    (c.rewritten ?= Nil)   :| s"${c.rewritten.length} of ${c.eis.length} interfaces were rewritten on the " +
                              s"second load:\n${c.rewritten.take(30).mkString("\n")}" &&
    (notWarm ?= Nil)       :| s"${notWarm.length} of ${published.length} modules were not warm:\n" +
                              notWarm.take(30).map(m => s"  $m: ${c.warm.get(m)}").mkString("\n")
  }

  /** The GRAMMAR round-trip, over every `.ei` the corpus produces: it PARSES
    * with `InterfaceParsers.interfaceSigs`, re-prints through the printer
    * `Dep.writeInterface` uses, PARSES AGAIN, and the re-parse is
    * ALPHA-EQUIVALENT to the first.  That is the statement "the printer publishes
    * nothing the grammar cannot read, and reading it back does not change the
    * type" — the property this bug broke.
    *
    * It is deliberately NOT "re-prints to the bytes it was read from", because
    * that is false today for reasons that have nothing to do with this bug and
    * that F4 does not fix:
    *   - `Part.apply` REVERSES a partition's right-hand side (its fold conses),
    *     so `r <- (h, t)` parses to `Part(r, [t, h])` and re-prints reversed;
    *   - an existential's binder list and constraint list come back in an
    *     id-derived order, and ids are drawn fresh on every parse;
    *   - ticket B3: the printer publishes a free row variable it does not bind,
    *     and `qtyp` binds those on the way in, so a re-print carries a WIDER
    *     quantifier than the file did.
    * 196 of the 245 corpus interfaces DO re-print byte-identically; the count is
    * reported by `Prop.collect` rather than asserted, and byte identity becomes
    * attainable only with a canonicaliser (`ROSE-COMPARISON.md` §3 rank 3). */
  property("every corpus interface parses and re-prints stably") = secure {
    prop3(corpus)
  }

  private def prop3(c: Corpus): Prop = {
    implicit val su: scalaparsers.Supply = scalaparsers.Supply.create
    implicit val printer: Printer = Printer.ignore

    ErmineFixture.literalLock.synchronized {
      // a session holding the corpus' constructors, for `recognizedCons`
      Session.depCache.clear()
      implicit val e: SessionEnv = new SessionEnv(_typeCheck = Some(true), _useInterface = Some(true))
      Lib.preamble
      e.loadFile = SourceFile.inOrder(
        SourceFile.filesystem(c.root.resolve("modules").toString) _,
        SourceFile.filesystem(c.root.resolve("examples").toString) _, e.loadFile)
      for (m <- c.mods) try Session.loadModules(List(m)) catch { case _: Throwable => () }

      val bad = List.newBuilder[String]
      var sigCount = 0
      var byteStable = 0
      for (f <- c.eis) {
        val body = Session.splitInterfaceKey(new String(Files.readAllBytes(f.toPath), UTF_8))._2
        try {
          val t1 = parseSigs(f.getPath, body)
          sigCount += t1.length
          val s1 = printSigs(t1)
          val t2 = parseSigs(f.getPath + "<reprint>", s1)
          val s2 = printSigs(t2)
          if (s1 == s2) byteStable += 1
          val off = alphaEqAll(t1, t2)
          if (off.nonEmpty) bad += s"${f.getName}: re-parse differs at ${off.take(3).mkString(", ")}"
        } catch {
          case t: Throwable => bad += s"${f.getName}: ${t.toString.linesIterator.take(2).mkString(" ")}"
        }
      }
      val problems = bad.result()

      // the byte-identical count is REPORTED, not asserted: see the scaladoc.
      collect(s"$byteStable of ${c.eis.length} interfaces re-print byte-identically") {
        (sigCount >= 2000) :| s"only $sigCount signatures parsed" &&
        (problems ?= Nil)  :| s"${problems.length} of ${c.eis.length} interfaces did not round-trip " +
                              s"($byteStable of ${c.eis.length} re-print byte-identically):\n" +
                              problems.take(20).mkString("\n")
      }
    }
  }
}
