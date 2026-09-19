package com.clarifi.reporting

import com.clarifi.reporting.ermine.lsp.{ BuildStamp, Diagnostics, Documents, Json, Resident, Rpc, RpcError, Server, Wire }
import com.clarifi.reporting.ermine.session.{ Printer, Session => S, SessionEnv }

import org.scalacheck._
import Prop._
import scalaparsers.{ Death, Supply }

import java.io.{ ByteArrayInputStream, ByteArrayOutputStream, File, OutputStream }
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.{ Files, Path, Paths }

/** LSP ROBUSTNESS (tracker/LSP-STALENESS.md, "coverage"): the server shell
  * and the staleness machinery, in this JVM, under input the smoke never
  * sends.  Three parts:
  *
  *   A. the wire and the dispatcher -- framing, the JSON codec, and a
  *      `Server` loop fed random well-formed, malformed and unknown
  *      traffic: it must answer every request exactly once, answer
  *      garbage with a parse error, and never stop before EOF;
  *   B. NEVER DARK -- corpus modules mutated by a small edit grammar go
  *      through `Diagnostics.check` (the call `Diagnostics.run` makes)
  *      against a real resident: the check returns a list, in bounded
  *      time, with sane ranges, and the ORIGINAL text checked right after
  *      publishes exactly what it publishes cold -- garbage in the caches
  *      poisons nothing;
  *   C. the staleness machinery -- source roots ahead of the classpath,
  *      `moduleUnder`/`checkoutRootOf`, reloads that leave the resident's
  *      name tables exactly as they were and reload a set closed under
  *      "imported by", and the failure path (a broken save, a deleted
  *      file) that leaves modules pending and brings them back.
  *
  * Everything that touches the resident holds `residentLock`: ScalaCheck
  * runs a Properties object's properties on a pool and `Resident.supply`
  * is one single-threaded Supply.
  */
object TestLspRobustness extends Properties("LSP robustness") {

  override def overrideParameters(p: Test.Parameters): Test.Parameters =
    p.withMinSuccessfulTests(40)

  private val quiet: String => Unit = _ => ()

  // ================================================================ A. wire

  private val genText: Gen[String] =
    Gen.listOf(Gen.frequency(
      (8, Gen.alphaNumChar),
      (2, Gen.oneOf(' ', '"', '\\', '\n', '\r', '\t', '/', '{', '}', '[', ']', ':', ',')),
      (1, Gen.oneOf('\u00e9', '\u65e5', '\u0001', '\u001f', '\u2028')))).map(_.mkString)

  private def genJson(depth: Int): Gen[Json] = {
    val leaf: Gen[Json] = Gen.frequency(
      (1, Gen.const(Json.Null)),
      (1, Gen.oneOf(true, false).map(Json.Bool(_))),
      (2, Gen.chooseNum(-1000000, 1000000).map(Json.num(_))),
      (3, genText.map(Json.Str(_))))
    if (depth <= 0) leaf
    else Gen.frequency(
      (3, leaf),
      (1, Gen.listOf(genJson(depth - 1)).map(Json.Arr(_))),
      (1, Gen.listOf(Gen.zip(genText, genJson(depth - 1))).map(Json.Obj(_))))
  }

  private implicit val arbJson: Arbitrary[Json] = Arbitrary(genJson(3))

  /** Every frame a byte stream holds, read back through the real Wire. */
  private def frames(bytes: Array[Byte]): List[String] = {
    val w = new Wire(new ByteArrayInputStream(bytes), OutputStream.nullOutputStream, quiet)
    Iterator.continually(w.receive()).takeWhile(_.isDefined).map(_.get).toList
  }

  property("A: print then parse is the identity on JSON values") = forAll { (j: Json) =>
    Json.parse(Json.print(j)) == Right(j)
  }

  property("A: a frame counts UTF-8 BYTES, and one send is one receive") = forAll { (j: Json) =>
    val out = new ByteArrayOutputStream
    new Wire(new ByteArrayInputStream(Array()), out, quiet).send(j)
    val got = frames(out.toByteArray)
    (got.size == 1) :| s"${got.size} frames" &&
      (got.headOption.map(Json.parse) == Some(Right(j))) :| "body differs"
  }

  property("A: several frames back to back are all received, in order") =
    forAll(Gen.listOfN(5, genJson(2))) { js =>
      val out = new ByteArrayOutputStream
      val w = new Wire(new ByteArrayInputStream(Array()), out, quiet)
      js foreach w.send
      frames(out.toByteArray).map(Json.parse) == js.map(Right(_))
    }

  /** One random edit of a text: a character dropped, inserted or replaced. */
  private def mutate(s: String): Gen[String] =
    for {
      i <- Gen.chooseNum(0, math.max(0, s.length - 1))
      c <- Gen.oneOf('{', '}', '[', ']', '"', '\\', ',', ':', 'x', '0', ' ')
      k <- Gen.chooseNum(0, 2)
    } yield k match {
      case 0 if s.nonEmpty => s.substring(0, i) + s.substring(i + 1)
      case 1               => s.substring(0, math.min(i, s.length)) + c + s.substring(math.min(i, s.length))
      case _ if s.nonEmpty => s.substring(0, i) + c + s.substring(i + 1)
      case _               => s
    }

  property("A: Json.parse never throws, on any text") =
    forAll(Gen.frequency((1, Gen.asciiStr), (1, genText),
                         (2, arbJson.arbitrary.map(Json.print).flatMap(mutate)))) { s =>
      Json.parse(s) match { case Left(_) | Right(_) => true }
    }

  property("A: the wire never throws on arbitrary bytes") =
    forAll(Gen.listOf(Gen.chooseNum(0, 255).map(_.toByte)).map(_.toArray)) { bytes =>
      val w = new Wire(new ByteArrayInputStream(bytes), OutputStream.nullOutputStream, quiet)
      // every call is total; None means the stream is considered closed
      val first = w.receive()
      if (first.isEmpty) w.receive().isEmpty else true
    }

  // --- the dispatcher under random traffic ---------------------------------

  sealed trait Traffic
  final case class Req(id: Int, method: String, params: Json) extends Traffic
  final case class Note(method: String, params: Json)         extends Traffic
  final case class Garbage(text: String)                      extends Traffic
  final case class Reply(id: Int, result: Json)               extends Traffic
  case object NoMethodNoId                                    extends Traffic

  private val genTraffic: Gen[Traffic] = Gen.frequency(
    (5, for { id <- Gen.chooseNum(1, 50); m <- Gen.oneOf("echo", "boom", "refuse", "nosuch"); p <- genJson(2) } yield Req(id, m, p)),
    (2, for { m <- Gen.oneOf("known", "unknown", "$/optional"); p <- genJson(1) } yield Note(m, p)),
    (2, Gen.frequency((2, genText), (2, arbJson.arbitrary.map(Json.print).flatMap(mutate)), (1, Gen.const("")))
          .filter(t => Json.parse(t).isLeft).map(Garbage(_))),
    (1, for { id <- Gen.chooseNum(1, 50); r <- genJson(1) } yield Reply(id, r)),
    (1, Gen.const(NoMethodNoId)))

  private def encode(ts: List[Traffic]): Array[Byte] = {
    val out = new ByteArrayOutputStream
    val w   = new Wire(new ByteArrayInputStream(Array()), out, quiet)
    def raw(text: String): Unit = {
      val b = text.getBytes(UTF_8)
      out.write(("Content-Length: " + b.length + "\r\n\r\n").getBytes(UTF_8)); out.write(b)
    }
    ts foreach {
      case Req(id, m, p)  => w.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> Json.num(id), "method" -> Json.Str(m), "params" -> p))
      case Note(m, p)     => w.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "method" -> Json.Str(m), "params" -> p))
      case Reply(id, r)   => w.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> Json.num(id), "result" -> r))
      case NoMethodNoId   => w.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "params" -> Json.Null))
      case Garbage(t)     => raw(t)
    }
    out.toByteArray
  }

  /** Run one Server over the traffic; answer (exit, every message it sent, the log). */
  private def serve(ts: List[Traffic]): (Option[Int], List[Json], List[String]) = {
    val out = new ByteArrayOutputStream
    val log = List.newBuilder[String]
    val server = new Server(new Wire(new ByteArrayInputStream(encode(ts)), out, log += _), log += _)
    var notes = 0
    server.onRequest("echo")   { p => p }
    server.onRequest("boom")   { _ => throw new RuntimeException("boom") }
    server.onRequest("refuse") { _ => throw RpcError(Rpc.RequestFailed, "refused") }
    server.onNotification("known") { _ => notes += 1 }
    val exit = server.run()
    (exit, frames(out.toByteArray).map(t => Json.parse(t).fold(e => sys.error("server sent unparseable JSON: " + e), identity)), log.result())
  }

  private def id(j: Json): Option[Json]     = j / "id"
  private def errCode(j: Json): Option[Int] = j / "error" flatMap (_ / "code") flatMap (_.int)

  property("A: the dispatcher answers every request exactly once and survives to EOF, whatever arrives") =
    forAll(Gen.listOf(genTraffic)) { ts =>
      val (exit, sent, _) = serve(ts)
      val reqs    = ts.collect { case r: Req => r }
      val garbage = ts.count { case _: Garbage => true; case NoMethodNoId => true; case _ => false }
      val responses = sent.filter(j => id(j).isDefined)
      // A client may reuse an id (its bug, not the server's): a response is
      // well shaped if it fits ANY request that carried that id.
      val byId: Map[Json, List[Req]] = reqs.groupBy(r => (Json.num(r.id): Json))
      val answered = reqs.forall(r => responses.exists(j => id(j) == Some(Json.num(r.id))))
      def fits(j: Json, r: Req): Boolean = r.method match {
        case "echo"   => (j / "result") == Some(r.params)
        case "boom"   => errCode(j) == Some(Rpc.InternalError)
        case "refuse" => errCode(j) == Some(Rpc.RequestFailed)
        case _        => errCode(j) == Some(Rpc.MethodNotFound)
      }
      val shapes = responses.forall { j =>
        id(j) match {
          case Some(Json.Null) => errCode(j).exists(c => c == Rpc.ParseError || c == Rpc.InvalidRequest)
          case Some(i)         => byId.get(i).exists(_.exists(fits(j, _)))
          case None            => true
        }
      }
      val nullIds = responses.count(j => id(j) == Some(Json.Null))
      (exit.isEmpty :| "run() must return None at EOF (no stop() was called)") &&
      (answered :| "a request went unanswered") &&
      (shapes :| "a response had the wrong shape for its request") &&
      ((nullIds == garbage) :| s"garbage frames: $garbage, id-null errors: $nullIds") &&
      ((responses.size == reqs.size + garbage) :| s"${responses.size} responses for ${reqs.size} requests and $garbage garbage frames")
    }

  property("A: an echo answers with its own params, byte for byte through the codec") =
    forAll(Gen.listOfN(3, genJson(3))) { ps =>
      val ts = ps.zipWithIndex.map { case (p, i) => Req(i + 1, "echo", p) }
      val (_, sent, _) = serve(ts)
      sent.map(j => j / "result") == ps.map(Some(_))
    }

  property("A: a reply to a server request runs its handler once; a reply to nothing is dropped") =
    forAll(Gen.chooseNum(1, 20), Gen.chooseNum(1, 20)) { (k, stray) =>
      val out = new ByteArrayOutputStream
      val log = List.newBuilder[String]
      // the server asks first; the client's replies are the whole input
      val replies = new ByteArrayOutputStream
      val rw = new Wire(new ByteArrayInputStream(Array()), replies, quiet)
      (1 to k) foreach (i => rw.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> Json.num(i), "result" -> Json.num(i * 10))))
      rw.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> Json.num(k + stray), "result" -> Json.Null))
      val server = new Server(new Wire(new ByteArrayInputStream(replies.toByteArray), out, quiet), log += _)
      var got = List.empty[(Int, Option[Int])]
      (1 to k) foreach (i => server.ask("client/x", Json.Null) { r => got ::= (i, r / "result" flatMap (_.int)) })
      server.run()
      (got.reverse == (1 to k).toList.map(i => (i, Some(i * 10)))) :| s"handlers saw $got" &&
        log.result().exists(_ contains "dropping response") :| "the stray reply was not logged as dropped"
    }

  // =========================================================== B. never dark

  private val residentLock = new Object
  private val stdlibRoot   = new File("core/src/main/resources/modules").getAbsoluteFile

  private def walk(f: File): List[File] =
    if (f.isDirectory) f.listFiles.toList.sortBy(_.getName).flatMap(walk)
    else if (f.getName endsWith ".e") List(f) else Nil

  private val notGoodCode = Set("shouldfail", "shouldfail-controls", "incomplete")

  private lazy val corpusFiles: List[File] =
    (walk(stdlibRoot) ++ walk(new File("core/examples").getAbsoluteFile))
      .filterNot(f => Option(f.getParentFile).exists(d => notGoodCode(d.getName)))

  private def stdlibModules: List[String] = {
    val root = stdlibRoot.getPath + File.separator
    walk(stdlibRoot).map(_.getPath.stripPrefix(root).stripSuffix(".e").replace(File.separator, ".")).sorted
  }

  /** A second root, outside every checkout, that part C writes modules into. */
  private lazy val extraRoot: Path = {
    val d = Files.createTempDirectory("ermine-lsp-robust")
    d.toFile.deleteOnExit()
    d
  }

  private def write(p: Path, text: String): Unit = {
    Files.createDirectories(p.getParent)
    Files.write(p, text.getBytes(UTF_8))
  }

  private val leafGood = "module Rob.Leaf where\n\nleaf : Int\nleaf = 1\n"

  /** ONE resident for parts B and C, booted with the temp root AHEAD of
    * the stdlib source root, both ahead of the classpath (step 1), and
    * warmed with the whole stdlib the way TestTolerantCheck's is. */
  private lazy val resident: Resident = {
    write(extraRoot.resolve("Rob").resolve("Leaf.e"), leafGood)
    write(extraRoot.resolve("Rob").resolve("Dep.e"),
          "module Rob.Dep where\n\nimport Rob.Leaf\n\nuseLeaf : Int\nuseLeaf = leaf\n")
    val r = new Resident(quiet)
    r.moduleRoots = List(extraRoot.toString, stdlibRoot.getPath)
    val ready = r.boot()
    implicit val s: SessionEnv = ready.env
    implicit val su: Supply = r.supply
    implicit val con: Printer = r.printer
    try S.loadModules(stdlibModules)
    catch { case Death(_, _) =>
      stdlibModules.foreach { m => try S.loadModules(List(m)) catch { case Death(_, _) => () } } }
    r
  }

  private def diagnose(f: File, docs: Documents): List[Json] =
    Diagnostics.check(resident, docs, f.toURI.toString, f.toPath, quiet)

  /** THE EDIT GRAMMAR: what a keystroke, a paste, a half-finished thought
    * or a corrupted buffer can do to a module. */
  private val junkLines: List[String] = List(
    "x = = 3", "(", ")", "where", "import NoSuchModule", "foo :", "\"unterminated",
    "{-", "-}", "\tf = 1", "let", "case x of", "data", "infixl 9 !!!", "module Nope where",
    "x = " + "(" * 60 + "1" + ")" * 60, "y = " + "(" * 80, "z = [" + List.fill(200)("1").mkString(",") + "]",
    "w = \u0000\u0001\u007f", "v = '\u2028'", "field q : Int", "export List", "\u65e5\u672c = 1",
    "a b c d e f g h = a", "x = x", "u = \\", "-- " + "x" * 3000)

  private sealed trait Edit
  private final case class Truncate(at: Int)             extends Edit
  private final case class DropLine(at: Int)             extends Edit
  private final case class InsertLine(at: Int, j: Int)   extends Edit
  private final case class DupLine(at: Int)              extends Edit
  private final case class SwapLines(a: Int, b: Int)     extends Edit
  private final case class ReplaceChar(at: Int, c: Char) extends Edit
  private final case class Splice(other: Int, at: Int)   extends Edit

  private val genEdit: Gen[Edit] = Gen.frequency(
    (2, Gen.chooseNum(0, 100000).map(Truncate(_))),
    (3, Gen.chooseNum(0, 100000).map(DropLine(_))),
    (4, Gen.zip(Gen.chooseNum(0, 100000), Gen.chooseNum(0, junkLines.size - 1)).map { case (a, j) => InsertLine(a, j) }),
    (1, Gen.chooseNum(0, 100000).map(DupLine(_))),
    (1, Gen.zip(Gen.chooseNum(0, 100000), Gen.chooseNum(0, 100000)).map { case (a, b) => SwapLines(a, b) }),
    (3, Gen.zip(Gen.chooseNum(0, 100000), Gen.oneOf('(', ')', '{', '}', '"', '\t', '=', '\\', '.', ' ', '\n')).map { case (a, c) => ReplaceChar(a, c) }),
    (1, Gen.zip(Gen.chooseNum(0, 100000), Gen.chooseNum(0, 100000)).map { case (o, a) => Splice(o, a) }))

  private def applyEdit(text: String, e: Edit, others: List[File]): String = {
    val lines = text.split("\n", -1).toList
    def idx(i: Int, n: Int) = if (n == 0) 0 else i % n
    e match {
      case Truncate(at)       => text.substring(0, idx(at, text.length + 1))
      case DropLine(at)       => if (lines.size <= 1) text else { val i = idx(at, lines.size); (lines.take(i) ++ lines.drop(i + 1)).mkString("\n") }
      case InsertLine(at, j)  => val i = idx(at, lines.size + 1); (lines.take(i) ++ List(junkLines(j)) ++ lines.drop(i)).mkString("\n")
      case DupLine(at)        => val i = idx(at, lines.size); (lines.take(i + 1) ++ lines.drop(i)).mkString("\n")
      case SwapLines(a, b)    => val (i, k) = (idx(a, lines.size), idx(b, lines.size)); lines.updated(i, lines(k)).updated(k, lines(i)).mkString("\n")
      case ReplaceChar(at, c) => if (text.isEmpty) text else { val i = idx(at, text.length); text.substring(0, i) + c + text.substring(i + 1) }
      case Splice(o, at)      =>
        val other = others(idx(o, others.size))
        val ot = new String(Files.readAllBytes(other.toPath), UTF_8)
        text.substring(0, idx(at, text.length + 1)) + ot.substring(idx(at, ot.length + 1))
    }
  }

  private def sane(ds: List[Json], text: String): List[String] = {
    val nLines = text.count(_ == '\n') + 1
    def at(d: Json, w: String, f: String) = (d / "range" flatMap (_ / w) flatMap (_ / f) flatMap (_.int)) getOrElse -1
    ds.flatMap { d =>
      val (sl, sc, el, ec) = (at(d, "start", "line"), at(d, "start", "character"), at(d, "end", "line"), at(d, "end", "character"))
      val msg = (d / "message" flatMap (_.str)) getOrElse ""
      val sev = (d / "severity" flatMap (_.int)) getOrElse -1
      List(
        if (sl < 0 || sc < 0 || el < 0 || ec < 0) Some("negative position " + d) else None,
        if (sl >= nLines + 1 || el >= nLines + 1) Some(s"line beyond the buffer ($sl-$el of $nLines)") else None,
        if (el < sl || (el == sl && ec < sc)) Some("end before start " + d) else None,
        if (msg.trim.isEmpty) Some("empty message") else None,
        if (sev < 1 || sev > 4) Some("severity " + sev) else None).flatten
    }
  }

  property("B: NEVER DARK -- a mutated corpus module is checked, in bounded time, with sane ranges, and poisons nothing") =
    forAll(Gen.chooseNum(0, 100000), Gen.nonEmptyListOf(genEdit).map(_.take(3))) { (pick, edits) =>
      residentLock.synchronized {
        val files = corpusFiles
        val f     = files(pick % files.size)
        val orig  = new String(Files.readAllBytes(f.toPath), UTF_8)
        val mut   = edits.foldLeft(orig)((t, e) => applyEdit(t, e, files))
        val uri   = f.toURI.toString
        // the cold truth: the original text in a fresh Documents
        val cold = { val d = new Documents; d.put(uri, orig, 1); diagnose(f, d) }
        // the run: mutated text, then the original again, in ONE Documents
        val docs = new Documents
        docs.put(uri, mut, 2)
        val t0 = System.nanoTime
        val dsMut = try Right(diagnose(f, docs)) catch { case e: Throwable => Left(e) }
        val ms = (System.nanoTime - t0) / 1000000L
        docs.put(uri, orig, 3)
        val warm = diagnose(f, docs)
        val problems = dsMut.toOption.map(sane(_, mut)).getOrElse(Nil)
        (dsMut.isRight :| s"${f.getName} with $edits: the check THREW ${dsMut.left.toOption.map(e => e.getClass.getName + ": " + e.getMessage)}") &&
        ((ms < 30000L) :| s"${f.getName} with $edits took ${ms}ms") &&
        (problems.isEmpty :| s"${f.getName} with $edits: $problems") &&
        ((warm == cold) :| s"${f.getName}: after $edits the original publishes ${warm.size} diagnostic(s), cold ${cold.size}")
      }
    }

  // ======================================================== C. staleness

  private val genSegs: Gen[List[String]] =
    Gen.nonEmptyListOf(Gen.zip(Gen.alphaUpperChar, Gen.listOf(Gen.alphaNumChar)).map { case (c, cs) => (c :: cs).mkString }).map(_.take(4))

  property("C: moduleUnder inverts the loader's path for a module under a root") =
    forAll(genSegs) { segs =>
      val root = Paths.get("/tmp/robust-root")
      val p    = segs.init.foldLeft(root)(_ resolve _).resolve(segs.last + ".e")
      Resident.moduleUnder(List(root.toString), p) == Some(segs.mkString(".")) &&
        Resident.moduleUnder(List(root.toString), p.resolveSibling(segs.last + ".txt")).isEmpty &&
        Resident.moduleUnder(List("/tmp/other-root"), p).isEmpty
    }

  property("C: checkoutRootOf finds the stdlib of the checkout a file is in, and nothing outside one") = secure {
    val inside = stdlibRoot.toPath.resolve("Bool.e")
    val deep   = new File("tracker/lsp-tests/Good.e").getAbsoluteFile.toPath
    (Resident.checkoutRootOf(inside) == Some(stdlibRoot.getPath)) :| s"inside: ${Resident.checkoutRootOf(inside)}" &&
      (Resident.checkoutRootOf(deep) == Some(stdlibRoot.getPath)) :| s"deep: ${Resident.checkoutRootOf(deep)}" &&
      Resident.checkoutRootOf(extraRoot.resolve("Rob").resolve("Leaf.e")).isEmpty :| "temp dir has no checkout"
  }

  property("C: a source root ahead of the classpath is where the resident reads from") = secure {
    residentLock.synchronized {
      val env = resident.loadedEnv.get
      val byModule = env.loadedFiles.map { case (sf, m) => m -> sf.toString }
      // (no claim about Rob.*: the C properties that load it run in any order)
      (byModule.get("Bool").exists(_ startsWith stdlibRoot.getPath) :| s"Bool from ${byModule.get("Bool")}") &&
        (byModule.get("Layout").exists(_ startsWith stdlibRoot.getPath) :| s"Layout from ${byModule.get("Layout")}")
    }
  }

  /** The name tables a reload must leave exactly as they were. */
  private def tables(env: SessionEnv) =
    (env.loadedModules.keySet, env.termNames.keySet, env.cons.keySet, env.classes.keySet)

  private def importsOf(env: SessionEnv): Map[String, Set[String]] =
    env.loadedFiles.toList.flatMap { case (sf, m) => S.depCache.get(sf).map { case (_, d) => m -> d.imports } }.toMap

  /** Loaded modules whose "imported by" closure is small enough to reload
    * in well under a second; computed the SLOW way (fixpoint), which is the
    * oracle the property compares the server's BFS against. */
  private def cheapModules(env: SessionEnv): List[(String, Set[String])] = {
    val imps = importsOf(env)
    def closure(m: String): Set[String] = {
      var s = Set(m); var grew = true
      while (grew) { val n = imps.collect { case (x, is) if !s(x) && (is & s).nonEmpty => x }.toSet; grew = n.nonEmpty; s ++= n }
      s
    }
    env.loadedFiles.values.toList.distinct.sorted.map(m => m -> closure(m)).filter(_._2.size <= 6)
  }

  property("C: reloading a loaded module reloads exactly its importers' closure and leaves the tables as they were") =
    forAll(Gen.chooseNum(0, 100000)) { pick =>
      residentLock.synchronized {
        val env    = resident.loadedEnv.get
        val cheap  = cheapModules(env)
        val (m, closure) = cheap(pick % cheap.size)
        val path   = env.loadedFiles.collectFirst { case (S.Filesystem(f, _), `m`) => Paths.get(f) }.get
        val before = tables(env)
        val r      = resident.reload(Set(path), Set()).get
        val after  = tables(env)
        ((cheap.size >= 5) :| s"only ${cheap.size} cheap modules") &&
          (r.failure.isEmpty :| s"$m: ${r.failure}") &&
          ((r.modules.toSet == closure) :| s"$m: reloaded ${r.modules}, closure $closure") &&
          (resident.pending.isEmpty :| "pending after a good reload") &&
          ((after == before) :| s"$m: tables changed: modules ${after._1 &~ before._1}/${before._1 &~ after._1}, terms ${(after._2 &~ before._2).size}/${(before._2 &~ after._2).size}")
      }
    }

  property("C: a path the resident never loaded reloads nothing") = secure {
    residentLock.synchronized {
      val before = tables(resident.loadedEnv.get)
      val r = resident.reload(Set(Paths.get("/tmp/nowhere/X.e"), new File("tracker/lsp-tests/Good.e").getAbsoluteFile.toPath), Set()).get
      r.nothing && tables(resident.loadedEnv.get) == before
    }
  }

  property("C: a broken save leaves the module and its dependents pending; the next good save brings them back") = secure {
    residentLock.synchronized {
      val env = resident.loadedEnv.get
      implicit val s: SessionEnv = env
      implicit val su: Supply = resident.supply
      implicit val con: Printer = resident.printer
      val leaf = extraRoot.resolve("Rob").resolve("Leaf.e")
      write(leaf, leafGood)
      if (!env.loadedModules.contains("Rob.Dep")) S.loadModules(List("Rob.Dep"))
      val before = tables(env)
      // broken
      write(leaf, "module Rob.Leaf where\n\nleaf : Int\nleaf = = 1\n")
      val r1 = resident.reload(Set(leaf), Set()).get
      val pending1 = resident.pending
      val gone = !env.loadedModules.contains("Rob.Leaf") && !env.loadedModules.contains("Rob.Dep") &&
                 !env.termNames.keySet.exists(g => g.module == "Rob.Leaf" || g.module == "Rob.Dep")
      // deleted: still pending, still gone
      Files.delete(leaf)
      val r2 = resident.reload(Set(), Set(leaf)).get
      // good again
      write(leaf, leafGood)
      val r3 = resident.reload(Set(leaf), Set()).get
      val after = tables(env)
      ((r1.modules == List("Rob.Dep", "Rob.Leaf")) :| s"r1 $r1") &&
        (r1.failure.isDefined :| "the broken save must fail") &&
        ((pending1 == Set("Rob.Dep", "Rob.Leaf")) :| s"pending after the broken save: $pending1") &&
        (gone :| "scrubbed modules must be out of the tables while pending") &&
        ((r2.failure.isDefined && r2.modules == List("Rob.Dep", "Rob.Leaf")) :| s"r2 $r2") &&
        ((r3.failure.isEmpty && r3.modules == List("Rob.Dep", "Rob.Leaf")) :| s"r3 $r3") &&
        (resident.pending.isEmpty :| "nothing pending after the good save") &&
        ((after == before) :| "tables differ after break/delete/restore")
    }
  }

  property("C: reloadStale sees a save no event reported, and only that") = secure {
    residentLock.synchronized {
      val env = resident.loadedEnv.get
      implicit val s: SessionEnv = env
      implicit val su: Supply = resident.supply
      implicit val con: Printer = resident.printer
      val leaf = extraRoot.resolve("Rob").resolve("Leaf.e")
      write(leaf, leafGood)
      if (!env.loadedModules.contains("Rob.Dep")) S.loadModules(List("Rob.Dep"))
      resident.reloadStale()   // settle
      val quiet0 = resident.reloadStale().get
      write(leaf, leafGood.replace("leaf = 1", "leaf = 2"))
      Files.setLastModifiedTime(leaf, java.nio.file.attribute.FileTime.fromMillis(System.currentTimeMillis + 2000))
      val r = resident.reloadStale().get
      (quiet0.nothing :| s"a settled tree reloads nothing, got $quiet0") &&
        ((r.modules == List("Rob.Dep", "Rob.Leaf") && r.failure.isEmpty) :| s"got $r")
    }
  }

  property("C: BuildStamp.annotate appends only to messages the build can explain and keeps every other field") =
    forAll(genJson(2), Gen.oneOf("undefined term x", "does not export", "class missing: a.b", "failed to unify", "expected term atom", "")) { (extra, msg) =>
      val d = Json.obj("range" -> extra, "severity" -> Json.num(1), "message" -> Json.Str(msg), "source" -> Json.Str("ermine"))
      val s = BuildStamp.Stale(Paths.get("/tmp/scala"), 2, Paths.get("/tmp/scala/A.scala"), 2000L, 1000L)
      val a = BuildStamp.annotate(d, s)
      val m = (a / "message" flatMap (_.str)).get
      (a / "range" == Some(extra)) && (a / "severity" == d / "severity") && (a / "source" == d / "source") &&
        (if (BuildStamp.explains(msg)) m.startsWith(msg + "\n\nnot built:") && m.contains("A.scala") else m == msg)
    }

  property("C: BuildStamp.scalaDir prefers the stdlib root's checkout and skips a root that is not one") = secure {
    BuildStamp.scalaDir(List(extraRoot.toString, stdlibRoot.getPath)) ==
      Some(stdlibRoot.toPath.getParent.getParent.resolve("scala").toAbsolutePath.normalize)
  }
}
