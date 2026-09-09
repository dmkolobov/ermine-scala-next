package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.session.{ CheckMethod, Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.session.Session.SourceFile

import org.scalacheck._
import Prop._

import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.{ Files, Path }

/** Stage S5.2 (`tracker/ROSE-COMPARISON.md` §3 rank 6): a published `.ei` is
  * KEYED by the solver configuration that produced it, and a key that does not
  * match the running configuration is stale in exactly the sense a newer source
  * is -- a full recheck, and a rewrite.
  *
  * Built on `TestInterfaceRoundTrip`'s shape: its own temp workspace, the
  * process-global dep cache cleared under `ErmineFixture.literalLock` (deps
  * cached by another suite carry that session's `useInterface` baked into their
  * read closures, which breaks the hash chain for a warm load).
  *
  * HOW THE TWO CONFIGURATIONS ARE VARIED.  Every key-bearing flag is a `val` of
  * `Constraints.GenRules`, read once at class-initialisation time, so a second
  * configuration cannot be produced inside one JVM by setting a property.  What
  * the mechanism actually rests on is the comparison of the key in the FILE with
  * the key of the RUNNING compiler, so configuration B is produced where it is
  * observable: the file's key is rewritten to another configuration's, which is
  * exactly what a tree built partly elsewhere looks like.  The third case -- no
  * key at all -- is every `.ei` written before this stage.
  */
object TestInterfaceKey extends Properties("Interface key") {

  /* NO IMPORTS, deliberately.  `preChecked` answers `Interface` only when EVERY import was
   * itself interface-checked, so a module that imports `Primitive` is warm only if the
   * stdlib's `.ei` in the shared target tree is current -- and the dep cache is
   * process-global while ScalaCheck runs properties concurrently, so a sibling suite that
   * builds the `Primitive` dep in a `useInterface=false` session between this property's
   * cold and warm loads makes the warm load `Full` through no fault of the mechanism under
   * test.  (That is the documented `TestInterfaceRoundTrip` flake class, and it fired here
   * once.)  `KeyA` imports nothing and `KeyB` imports only `KeyA`, so the only interfaces
   * this property depends on are the two it writes itself, in its own temp directory. */
  private val srcA =
    """module KeyA where
      |
      |kId x = x
      |
      |kConst x y = x
      |""".stripMargin

  private val srcB =
    """module KeyB where
      |import KeyA
      |
      |kUse = kConst kId
      |""".stripMargin

  private def workspace(): Path = {
    val d = Files.createTempDirectory("ermine-key")
    Files.write(d.resolve("KeyA.e"), srcA.getBytes("UTF-8"))
    Files.write(d.resolve("KeyB.e"), srcB.getBytes("UTF-8"))
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

  /** Load `KeyB` in a fresh session over `dir`; answer how each module was checked. */
  private def load(dir: Path)(implicit su: scalaparsers.Supply)
      : (Option[CheckMethod], Option[CheckMethod]) = {
    implicit val printer: Printer = Printer.ignore
    Session.depCache.clear()
    val e = session(dir)
    Session.loadModules(List("KeyB"))(e, su, printer)
    (e.loadedModules.get("KeyA"), e.loadedModules.get("KeyB"))
  }

  private def slurp(p: Path): String = new String(Files.readAllBytes(p), UTF_8)
  private def spit(p: Path, s: String): Unit = Files.write(p, s.getBytes(UTF_8))

  private def header(p: Path): String = slurp(p).takeWhile(_ != '\n')

  /** Replace the whole first line (the key header, if there is one). */
  private def setHeader(p: Path, h: Option[String]): Unit = {
    // `splitInterfaceKey` REMOVES the header line, so the body it answers is what an
    // unkeyed `.ei` holds and this round-trips an unkeyed file unchanged.
    val body = Session.splitInterfaceKey(slurp(p))._2
    spit(p, h.map(_ + "\n").getOrElse("") + body)
  }

  private def withProps[A](kvs: (String, String)*)(a: => A): A = {
    val old = kvs.map { case (k, _) => (k, Option(System.getProperty(k))) }
    kvs.foreach { case (k, v) => System.setProperty(k, v) }
    try a
    finally old.foreach {
      case (k, Some(v)) => System.setProperty(k, v)
      case (k, None)    => System.clearProperty(k)
    }
  }

  /** Properties that must NOT be in the key because they cannot change the bytes of a
    * successfully published interface.  `typeCheck`, `useInterface` and
    * `foreign.tolerant` are named but never SET here: each is a `SessionEnv` default
    * read from the system property at construction time, so setting one would reach
    * every property ScalaCheck happens to be running concurrently (that is how the
    * first version of this file made `TestInterfaceRoundTrip` fail).  They are checked
    * textually instead, which is the guard that matters: the failure mode is somebody
    * putting one INTO the key. */
  private val notInKey =
    List("rowtrace", "loadinseries", "foreign", "typecheck", "useinterface", "tolerant")

  /** The key is a pure function of the format version and `GenRules.toString`;
    * no property that cannot change published bytes is in it.  This is the
    * regression guard: adding one to the key fails here. */
  property("key is <format version>|<GenRules>, and holds no non-key flag") = secure {
    val k0 = Session.interfaceKey
    val expected = Session.interfaceFormatVersion.toString + "|" + Constraints.GenRules.toString
    // the two that CAN be flipped safely: both are read once, into a `val`, when
    // `RowTrace` initialises, so setting them here changes nothing anywhere.
    val flipped = withProps(
      "ermine.rowTrace"       -> (!java.lang.Boolean.getBoolean("ermine.rowTrace")).toString,
      "ermine.rowTrace.draws" -> (!java.lang.Boolean.getBoolean("ermine.rowTrace.draws")).toString
    )(Session.interfaceKey)
    val lower = k0.toLowerCase
    (k0 ?= expected)                                         :| s"key $k0" &&
    (flipped ?= k0)                                          :| s"flipped $flipped vs $k0" &&
    (notInKey.filter(lower.contains) ?= Nil)                 :| s"key mentions a non-key flag: $k0" &&
    (Session.interfaceHeader ?= "-- ermine-interface " + k0) :| Session.interfaceHeader
  }

  property("cold write keys, warm read matches, a wrong or missing key is stale") = secure {
    implicit val su: scalaparsers.Supply = scalaparsers.Supply.create
    implicit val printer: Printer = Printer.ignore
    val dir = workspace()
    val eiA = dir.resolve("KeyA.ei")
    val eiB = dir.resolve("KeyB.ei")

    ErmineFixture.literalLock.synchronized {
      // (1) COLD, configuration A: a full check that writes both interfaces, each
      //     carrying the running configuration's key as its first line.
      val cold = load(dir)
      val wrote = Files.exists(eiA) && Files.exists(eiB)
      val hdrA = if (Files.exists(eiA)) header(eiA) else "<missing>"
      val hdrB = if (Files.exists(eiB)) header(eiB) else "<missing>"

      // (2) WARM under A: read back, no body inference.
      val warm = load(dir)

      // (3) WARM under A with NON-KEY flags flipped: `loadInSeries` really does
      //     change how the session loads (`Session.loadModules` reads it on every
      //     call), and it must not invalidate the cache.
      val warmFlipped = withProps(
        "ermine.loadInSeries" -> "true",
        "ermine.rowTrace"     -> "false")(load(dir))

      // (4) CONFIGURATION B: the file says it was written by another compiler.
      val other = Session.interfaceFormatVersion.toString + "|another+configuration"
      setHeader(eiA, Some("-- ermine-interface " + other))
      setHeader(eiB, Some("-- ermine-interface " + other))
      val stale = load(dir)
      val rewrittenA = header(eiA)
      val rewrittenB = header(eiB)

      // (5) NO KEY AT ALL: every `.ei` written before stage S5.
      setHeader(eiA, None)
      setHeader(eiB, None)
      val unkeyedFirst = header(eiA)
      val unkeyed = load(dir)
      val rekeyedA = header(eiA)

      (cold ?= (Some(CheckMethod.Full), Some(CheckMethod.Full)))       :| s"cold $cold" &&
      wrote                                                            :| "interfaces written" &&
      (hdrA ?= Session.interfaceHeader)                                :| s"A header $hdrA" &&
      (hdrB ?= Session.interfaceHeader)                                :| s"B header $hdrB" &&
      (warm ?= (Some(CheckMethod.Interface), Some(CheckMethod.Interface))) :| s"warm $warm" &&
      (warmFlipped ?= (Some(CheckMethod.Interface), Some(CheckMethod.Interface)))
                                                                       :| s"flipped $warmFlipped" &&
      (stale ?= (Some(CheckMethod.Full), Some(CheckMethod.Full)))      :| s"stale $stale" &&
      (rewrittenA ?= Session.interfaceHeader)                          :| s"rewritten A $rewrittenA" &&
      (rewrittenB ?= Session.interfaceHeader)                          :| s"rewritten B $rewrittenB" &&
      (unkeyedFirst.startsWith("-- ermine-interface ") ?= false)       :| s"unkeyed $unkeyedFirst" &&
      (unkeyed ?= (Some(CheckMethod.Full), Some(CheckMethod.Full)))    :| s"unkeyed $unkeyed" &&
      (rekeyedA ?= Session.interfaceHeader)                            :| s"rekeyed $rekeyedA"
    }
  }
}
