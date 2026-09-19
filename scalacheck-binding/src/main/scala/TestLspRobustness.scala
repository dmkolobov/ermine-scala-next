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

  override def overrideParameters(p: Test.Parameters): Test.Parameters = {
    val q = p.withMinSuccessfulTests(40)
    // -Dlsp.robust.seed=<base64 from a "failing seed" line> replays a run
    sys.props.get("lsp.robust.seed").flatMap(s => org.scalacheck.rng.Seed.fromBase64(s).toOption)
      .fold(q)(q.withInitialSeed)
  }

  private def trace(e: Throwable): String =
    e.getClass.getName + ": " + e.getMessage + "\n    " +
      e.getStackTrace.take(12).map(_.toString).mkString("\n    ")

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

  /** Frames with every way a header can be wrong: the length negative, zero,
    * short, long, non-numeric, duplicated, missing, bare-LF terminated, the
    * blank line missing, and one that claims more than the frame limit. */
  private val genFrame: Gen[(String, Array[Byte])] = {
    val body = genText.map(_.getBytes(UTF_8))
    def hdr(len: String, sep: String = "\r\n", blank: Boolean = true) =
      ("Content-Length: " + len + sep + (if (blank) sep else "")).getBytes(UTF_8)
    body.flatMap { b =>
      Gen.oneOf[(String, Array[Byte])](
        ("exact", hdr(b.length.toString) ++ b),
        ("exact-lf", hdr(b.length.toString, "\n") ++ b),
        ("short", hdr(math.max(0, b.length - 1).toString) ++ b),
        ("long", hdr((b.length + 1).toString) ++ b),
        ("zero", hdr("0") ++ b),
        ("negative", hdr("-1") ++ b),
        ("nan", hdr("many") ++ b),
        ("dup", ("Content-Length: 1\r\n" + "Content-Length: " + b.length + "\r\n\r\n").getBytes(UTF_8) ++ b),
        ("missing", ("Content-Type: x\r\n\r\n").getBytes(UTF_8) ++ b),
        ("noblank", hdr(b.length.toString, blank = false) ++ b),
        ("huge", hdr((Wire.MaxFrame.toLong + 1).toString) ++ b),
        ("max-int", hdr(Int.MaxValue.toString) ++ b))
    }
  }

  property("A: a frame's header decides what the wire reads, and a header cannot make it allocate") =
    forAll(genFrame) { case (kind, bytes) =>
      val w = new Wire(new ByteArrayInputStream(bytes), OutputStream.nullOutputStream, quiet)
      val t0 = System.nanoTime
      val r  = w.receive()
      val ms = (System.nanoTime - t0) / 1000000L
      val bodyLen = bytes.length - (new String(bytes, UTF_8).indexOf("\n\n") match {
        case -1 => new String(bytes, UTF_8).indexOf("\r\n\r\n") + 4
        case i  => i + 2 })
      val ok = kind match {
        case "exact" | "exact-lf" | "dup" => r.exists(_.getBytes(UTF_8).length == bodyLen)
        // one byte short may cut a multi-byte character, which decodes to a
        // replacement: only the LENGTH IN CHARACTERS is comparable
        case "short"                      => r.exists(_.length <= new String(bytes, UTF_8).length)
        case "zero"                       => r == Some("")
        case "long"                       => r.isEmpty      // eof inside the body
        case "negative" | "nan" | "missing" | "noblank" => r.isEmpty
        case "huge" | "max-int"           => r.isEmpty && ms < 1000
        case _                            => true           // a shrunk kind
      }
      ok :| s"$kind: got ${r.map(_.length)} in ${ms}ms"
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

  /** Run one Server over the traffic; answer (exit, every message it sent,
    * the log, how many known notifications the handler saw). */
  private def serve(ts: List[Traffic], stopAt: Option[Int] = None): (Option[Int], List[Json], List[String], Int) = {
    val out = new ByteArrayOutputStream
    val log = List.newBuilder[String]
    val server = new Server(new Wire(new ByteArrayInputStream(encode(ts)), out, log += _), log += _)
    var notes = 0
    server.onRequest("echo")   { p => p }
    server.onRequest("boom")   { _ => throw new RuntimeException("boom") }
    server.onRequest("refuse") { _ => throw RpcError(Rpc.RequestFailed, "refused") }
    server.onRequest("stop")   { _ => server.stop(stopAt.getOrElse(0)); Json.Null }
    server.onNotification("known") { _ => notes += 1 }
    val exit = server.run()
    (exit, frames(out.toByteArray).map(t => Json.parse(t).fold(e => sys.error("server sent unparseable JSON: " + e), identity)), log.result(), notes)
  }

  /** What the server must send for one message, in arrival order: the
    * server is single-threaded and answers as it reads. */
  private def expected(t: Traffic): Option[Json => Boolean] = t match {
    case Req(i, "echo", p)   => Some(j => id(j) == Some(Json.num(i)) && (j / "result") == Some(p))
    case Req(i, "boom", _)   => Some(j => id(j) == Some(Json.num(i)) && errCode(j) == Some(Rpc.InternalError))
    case Req(i, "refuse", _) => Some(j => id(j) == Some(Json.num(i)) && errCode(j) == Some(Rpc.RequestFailed))
    case Req(i, _, _)        => Some(j => id(j) == Some(Json.num(i)) && errCode(j) == Some(Rpc.MethodNotFound))
    case Garbage(_)          => Some(j => id(j) == Some(Json.Null) && errCode(j) == Some(Rpc.ParseError))
    case NoMethodNoId        => Some(j => id(j) == Some(Json.Null) && errCode(j) == Some(Rpc.InvalidRequest))
    case Note(_, _) | Reply(_, _) => None
  }

  private def id(j: Json): Option[Json]     = j / "id"
  private def errCode(j: Json): Option[Int] = j / "error" flatMap (_ / "code") flatMap (_.int)

  property("A: the dispatcher answers every message in order, once, with the right shape, and runs to EOF") =
    forAll(Gen.listOf(genTraffic)) { ts =>
      val (exit, sent, log, notes) = serve(ts)
      val want = ts.flatMap(expected)
      val positional = sent.size == want.size && sent.zip(want).forall { case (j, p) => p(j) }
      val known   = ts.count { case Note("known", _) => true; case _ => false }
      val unknown = ts.count { case Note("unknown", _) => true; case _ => false }
      val optional = ts.count { case Note("$/optional", _) => true; case _ => false }
      (exit.isEmpty :| "run() must return None at EOF (no stop() was called)") &&
      (positional :| s"${sent.size} messages sent for ${want.size} expected; first mismatch at ${sent.zip(want).indexWhere { case (j, p) => !p(j) }}") &&
      ((notes == known) :| s"$known known notifications, handler saw $notes") &&
      ((log.count(_ contains "ignoring notification unknown") == unknown) :| "unknown notifications are logged, one each") &&
      ((!log.exists(_ contains "ignoring notification $/")) :| s"$optional optional notifications must not be logged")
    }

  property("A: stop() from a handler ends the loop with that code, and later messages are not answered") =
    forAll(Gen.listOf(genTraffic), Gen.listOf(genTraffic), Gen.chooseNum(0, 9)) { (before, after, code) =>
      val ts = before ++ List(Req(99, "stop", Json.Null)) ++ after
      val (exit, sent, _, _) = serve(ts, Some(code))
      val want = before.flatMap(expected) :+ ((j: Json) => id(j) == Some(Json.num(99)) && (j / "result") == Some(Json.Null))
      (exit == Some(code)) :| s"exit $exit" &&
        (sent.size == want.size && sent.zip(want).forall { case (j, p) => p(j) }) :| s"${sent.size} sent, ${want.size} expected before the stop"
    }

  property("A: idle work runs when the stream is quiet, and a throwing work is logged and does not end the loop") =
    forAll(Gen.chooseNum(0, 4), Gen.oneOf(true, false)) { (pending0, throwing) =>
      val out = new ByteArrayOutputStream
      val log = List.newBuilder[String]
      // one notification, then EOF: the loop sees a quiet stream after it
      val server = new Server(new Wire(new ByteArrayInputStream(encode(List(Note("known", Json.Null)))), out, quiet), log += _)
      var pending = pending0
      var ran = 0
      server.onNotification("known") { _ => () }
      server.onIdle(5)(pending > 0) { pending -= 1; ran += 1; if (throwing) throw new RuntimeException("idle boom") }
      val exit = server.run()
      (exit.isEmpty :| "EOF ends the loop") &&
        ((ran == pending0) :| s"idle work ran $ran times for $pending0 pending") &&
        ((log.result().count(_ contains "idle work crashed") == (if (throwing) pending0 else 0)) :| "crashes are logged, one each")
    }

  property("A: an echo answers with its own params, byte for byte through the codec") =
    forAll(Gen.listOfN(3, genJson(3))) { ps =>
      val ts = ps.zipWithIndex.map { case (p, i) => Req(i + 1, "echo", p) }
      val (_, sent, _, _) = serve(ts)
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

  /** The LSP fixtures, broken ON PURPOSE (review B1): the corpus is silent
    * by construction, so without these the cold-vs-warm comparison could
    * only see a poisoned cache ADD diagnostics, never suppress them. */
  private lazy val fixtureFiles: List[File] = walk(new File("tracker/lsp-tests").getAbsoluteFile)

  private def stdlibModules: List[String] = {
    val root = stdlibRoot.getPath + File.separator
    walk(stdlibRoot).map(_.getPath.stripPrefix(root).stripSuffix(".e").replace(File.separator, ".")).sorted
  }

  /** A second root, outside every checkout, that part C writes modules into;
    * removed, contents and all, when the JVM exits (`deleteOnExit` would
    * leave a non-empty directory behind). */
  private lazy val extraRoot: Path = {
    val d = Files.createTempDirectory("ermine-lsp-robust")
    Runtime.getRuntime.addShutdownHook(new Thread(() => {
      val s = Files.walk(d)
      try s.sorted(java.util.Comparator.reverseOrder[Path]).forEach(p => Files.deleteIfExists(p))
      catch { case _: java.io.IOException => () }
      finally s.close()
    }))
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
    val lines  = text.split("\n", -1)
    val nLines = lines.length
    def at(d: Json, w: String, f: String) = (d / "range" flatMap (_ / w) flatMap (_ / f) flatMap (_.int)) getOrElse -1
    // an END may sit one past the line: "unexpected end of input" on a
    // truncated buffer ends one character after the last one, and editors
    // clamp it (Bool.e truncated to `other`: 25:5-25:6 on a 5-char line)
    def inLine(l: Int, c: Int, slack: Int) = l >= 0 && l < nLines && c >= 0 && c <= lines(l).length + slack
    ds.flatMap { d =>
      val (sl, sc, el, ec) = (at(d, "start", "line"), at(d, "start", "character"), at(d, "end", "line"), at(d, "end", "character"))
      val msg = (d / "message" flatMap (_.str)) getOrElse ""
      val sev = (d / "severity" flatMap (_.int)) getOrElse -1
      List(
        if (sl < 0 || sc < 0 || el < 0 || ec < 0) Some("negative position " + d) else None,
        if (sl >= nLines || el >= nLines) Some(s"line beyond the buffer ($sl-$el of $nLines)") else None,
        // E8: a character is a position IN the line's text (end may sit one past it)
        if (!inLine(sl, sc, 0) || !inLine(el, ec, 1)) Some(s"character beyond its line ($sl:$sc-$el:$ec)") else None,
        if (el < sl || (el == sl && ec < sc)) Some("end before start " + d) else None,
        if (msg.trim.isEmpty) Some("empty message") else None,
        if (sev < 1 || sev > 4) Some("severity " + sev) else None).flatten
    }
  }

  /** A diagnostic as a comparable string: the build-stamp hint stripped
    * (its five-second memo could straddle the two checks), and the ids of
    * unification variables blanked -- FINDING ROBUST-1: the SIG-3 message
    * ("the signature does not entail this row constraint") prints raw
    * metavariables, `r^776214S`, so two checks of the SAME text publish
    * different messages (tracker/lsp-tests/SigEntail.e, found by this
    * property with an identity edit).  Everything else must match exactly. */
  private def key(d: Json): String = Json.print(d match {
    case Json.Obj(fs) => Json.Obj(fs.map {
      case ("message", Json.Str(m)) =>
        "message" -> Json.Str(m.split("\n\nnot built:")(0).replaceAll("\\^[0-9]+", "^N"))
      case f => f })
    case other => other
  })

  property("B: NEVER DARK -- a mutated corpus or fixture module is checked, in bounded time, with sane ranges, and poisons nothing") =
    forAll(Gen.chooseNum(0, 100000), Gen.nonEmptyListOf(genEdit).map(_.take(3))) { (pick0, edits) =>
      residentLock.synchronized {
        val pick  = math.abs(pick0)   // the shrinker may go negative
        // half the picks from the fixtures, which HAVE diagnostics, so the
        // cold-vs-warm comparison sees suppression as well as addition
        val files = if (pick % 2 == 0) corpusFiles else fixtureFiles
        val f     = files((pick / 2) % files.size)
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
        val warmOr = try Right(diagnose(f, docs)) catch { case e: Throwable => Left(e) }
        val warm = warmOr.getOrElse(Nil)
        val problems = try dsMut.toOption.map(sane(_, mut)).getOrElse(Nil) catch { case e: Throwable => List("sane threw: " + trace(e)) }
        val same = warm.map(key).sorted == cold.map(key).sorted
        // what the run actually exercised, in the report
        collect(if (mut == orig) "edit was an identity" else "text changed")(
        collect(if (cold.isEmpty) "cold: silent" else "cold: has diagnostics")(
        collect(if (dsMut.toOption.exists(_.nonEmpty)) "mutated: has diagnostics" else "mutated: silent")(
        (dsMut.isRight :| s"${f.getName} with $edits: the check THREW ${dsMut.left.toOption.map(trace)}") &&
        (warmOr.isRight :| s"${f.getName} after $edits: the check of the ORIGINAL text THREW ${warmOr.left.toOption.map(trace)}") &&
        ((ms < 30000L) :| s"${f.getName} with $edits took ${ms}ms") &&
        (problems.isEmpty :| s"${f.getName} with $edits: $problems") &&
        (same :| s"${f.getName}: after $edits the original publishes ${warm.size} diagnostic(s), cold ${cold.size}" +
                  (if (warm.size == cold.size) s"\n    cold: ${cold.map(key).sorted}\n    warm: ${warm.map(key).sorted}" else "")))))
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

  /** The import graph read OFF THE SOURCES with a regular expression --
    * not off `Session.depCache`, which is what the server reads (review
    * S3): `import X` / `export X` at the start of a line, block comments
    * blanked first.  Only Filesystem-loaded modules have a source to read. */
  private def importsOf(env: SessionEnv): Map[String, Set[String]] = {
    val header = """(?m)^\s*(?:import|export)\s+([A-Z][\w.]*)""".r
    env.loadedFiles.toList.collect { case (S.Filesystem(f, _), m) if new File(f).isFile =>
      val text = new String(Files.readAllBytes(Paths.get(f)), UTF_8).replaceAll("(?s)\\{-.*?-\\}", "")
      m -> header.findAllMatchIn(text).map(_.group(1)).toSet
    }.toMap
  }

  /** Loaded modules whose "imported by" closure is small enough to reload
    * in well under a second; computed the SLOW way (fixpoint over the
    * source-read graph), which is the oracle the property compares the
    * server's depCache BFS against. */
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

  private def leafTerms(env: SessionEnv): Set[String] =
    env.termNames.keySet.collect { case g if g.module == "Rob.Leaf" => g.string }

  property("C: a broken save leaves the module and its dependents pending; the next good save brings them back") = secure {
    residentLock.synchronized {
      val env = resident.loadedEnv.get
      implicit val s: SessionEnv = env
      implicit val su: Supply = resident.supply
      implicit val con: Printer = resident.printer
      val leaf = extraRoot.resolve("Rob").resolve("Leaf.e")
      write(leaf, leafGood)
      if (!env.loadedModules.contains("Rob.Dep")) S.loadModules(List("Rob.Dep"))
      resident.reloadStale()
      val before = tables(env)
      try {
      // broken
      write(leaf, "module Rob.Leaf where\n\nleaf : Int\nleaf = = 1\n")
      val r1 = resident.reload(Set(leaf), Set()).get
      val pending1 = resident.pending
      val gone = !env.loadedModules.contains("Rob.Leaf") && !env.loadedModules.contains("Rob.Dep") &&
                 !env.termNames.keySet.exists(g => g.module == "Rob.Leaf" || g.module == "Rob.Dep")
      // deleted: still pending, still gone
      Files.delete(leaf)
      val r2 = resident.reload(Set(), Set(leaf)).get
      // good again, with one MORE name: the witness that the disk was read
      // (`leaf` itself must stay: Rob.Dep uses it)
      write(leaf, leafGood + "leaf3 : Int\nleaf3 = 3\n")
      val r3 = resident.reload(Set(leaf), Set()).get
      val terms3 = leafTerms(env)
      // and back to the original, so the tables can be compared
      write(leaf, leafGood)
      val r4 = resident.reload(Set(leaf), Set()).get
      val after = tables(env)
      ((r1.modules == List("Rob.Dep", "Rob.Leaf")) :| s"r1 $r1") &&
        (r1.failure.isDefined :| "the broken save must fail") &&
        ((pending1 == Set("Rob.Dep", "Rob.Leaf")) :| s"pending after the broken save: $pending1") &&
        (gone :| "scrubbed modules must be out of the tables while pending") &&
        ((r2.failure.isDefined && r2.modules == List("Rob.Dep", "Rob.Leaf")) :| s"r2 $r2") &&
        ((r3.failure.isEmpty && r3.modules == List("Rob.Dep", "Rob.Leaf")) :| s"r3 $r3") &&
        ((terms3 == Set("leaf", "leaf3")) :| s"after the extended save Rob.Leaf defines $terms3") &&
        ((r4.failure.isEmpty && resident.pending.isEmpty) :| "nothing pending after the good save") &&
        ((after == before) :| "tables differ after break/delete/restore")
      } finally { write(leaf, leafGood); resident.reloadStale() }
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
      try {
        write(leaf, leafGood + "leaf2 : Int\nleaf2 = 2\n")
        Files.setLastModifiedTime(leaf, java.nio.file.attribute.FileTime.fromMillis(System.currentTimeMillis + 2000))
        val r = resident.reloadStale().get
        val terms = leafTerms(env)
        (quiet0.nothing :| s"a settled tree reloads nothing, got $quiet0") &&
          ((r.modules == List("Rob.Dep", "Rob.Leaf") && r.failure.isEmpty) :| s"got $r") &&
          ((terms == Set("leaf", "leaf2")) :| s"the re-read Rob.Leaf defines $terms")
      } finally { write(leaf, leafGood); resident.reloadStale() }
    }
  }

  /** STALENESS step 2, end to end in this JVM (review S5): a document that
    * uses a name from a module that just changed on disk.  The inference
    * cache keys on the document's own text, so after the reload the stale
    * answer can be reused; `Documents.dropCaches` is what makes the next
    * check see the change, and `Diagnostics.recheckAll` is what publishes
    * it for every open document. */
  property("C: after a reload, dropCaches makes the next check see the change and recheckAll publishes it") = secure {
    residentLock.synchronized {
      val env = resident.loadedEnv.get
      implicit val s: SessionEnv = env
      implicit val su: Supply = resident.supply
      implicit val con: Printer = resident.printer
      val leaf = extraRoot.resolve("Rob").resolve("Leaf.e")
      val use  = extraRoot.resolve("Rob").resolve("Use.e")
      // Rob.Leaf starts with an extra name that Use.e depends on; the save
      // under test removes it (Rob.Dep uses only `leaf` and stays healthy)
      write(leaf, leafGood + "leaf2 : Int\nleaf2 = 2\n")
      write(use, "module Rob.Use where\n\nimport Rob.Leaf\n\nuseIt : Int\nuseIt = leaf2\n")
      if (!env.loadedModules.contains("Rob.Leaf")) S.loadModules(List("Rob.Leaf"))
      resident.reloadStale()
      try {
        val docs = new Documents
        val uri  = use.toUri.toString
        docs.put(uri, new String(Files.readAllBytes(use), UTF_8), 1)
        val d0 = Diagnostics.check(resident, docs, uri, use, quiet)
        write(leaf, leafGood)
        val r  = resident.reload(Set(leaf), Set()).get
        val stale = Diagnostics.check(resident, docs, uri, use, quiet)      // may reuse the cached answer
        docs.dropCaches()
        val fresh = Diagnostics.check(resident, docs, uri, use, quiet)
        // recheckAll publishes through a Server: read what it sent
        val out = new ByteArrayOutputStream
        val server = new Server(new Wire(new ByteArrayInputStream(Array()), out, quiet), quiet)
        Diagnostics.recheckAll(server, resident, docs, quiet)
        val published = frames(out.toByteArray).map(t => Json.parse(t).toOption.get)
          .filter(j => (j / "method" flatMap (_.str)) == Some("textDocument/publishDiagnostics"))
        val forUse = published.filter(j => (j / "params" flatMap (_ / "uri") flatMap (_.str)) == Some(uri))
        val count  = forUse.headOption.flatMap(j => j / "params" flatMap (_ / "diagnostics") flatMap (_.arr)).map(_.size)
        collect(if (stale.isEmpty) "without dropCaches: stale answer reused" else "without dropCaches: change seen")(
          (d0.isEmpty :| s"before the change: $d0") &&
          ((r.modules.contains("Rob.Leaf") && r.failure.isEmpty) :| s"reload $r") &&
          ((fresh.size == 1 && (fresh.head / "message" flatMap (_.str)).exists(_ contains "undefined term")) :| s"after dropCaches: $fresh") &&
          ((published.size == 1 && count == Some(1)) :| s"recheckAll published ${published.size} for the one open document, ${count} diagnostic(s)"))
      } finally { write(leaf, leafGood); Files.deleteIfExists(use); resident.reloadStale() }
    }
  }

  property("C: Documents answers garbage URIs with None and never throws") =
    forAll(Gen.oneOf("", "http://x/y.e", "file:", "::", "file:///a b.e", "file:///%zz.e", "not a uri", "file:///", "\u0000")) { u =>
      val docs = new Documents
      (docs.pathFor(u).isEmpty || u.startsWith("file:///")) && docs.put(u, "module X where\n", 1).forall(_ => u.startsWith("file:///"))
    }

  property("C: BuildStamp.annotate appends only to messages the build can explain and keeps every other field") =
    forAll(genJson(2), Gen.oneOf(
        ("x.e:3:1: error: undefined term", true), ("Module 'Bool' does not export term 'q'.", true),
        ("warning: class missing: a.b", true), ("member unloadable: p.q", true),
        ("failed to unify Int with String", false), ("expected term atom", false), ("", false),
        ("import X failed: Module not found: 'X'", false))) { (extra, mx) =>
      val (msg, expect) = mx
      val d = Json.obj("range" -> extra, "severity" -> Json.num(1), "message" -> Json.Str(msg), "source" -> Json.Str("ermine"))
      val s = BuildStamp.Stale(Paths.get("/tmp/scala"), 2, Paths.get("/tmp/scala/A.scala"), 2000L, 1000L)
      val a = BuildStamp.annotate(d, s)
      val m = (a / "message" flatMap (_.str)).get
      (a / "range" == Some(extra)) && (a / "severity" == d / "severity") && (a / "source" == d / "source") &&
        (if (expect) m.startsWith(msg + "\n\nnot built:") && m.contains("A.scala") else m == msg)
    }

  property("C: BuildStamp.scalaDir prefers the stdlib root's checkout and skips a root that is not one") = secure {
    BuildStamp.scalaDir(List(extraRoot.toString, stdlibRoot.getPath)) ==
      Some(stdlibRoot.toPath.getParent.getParent.resolve("scala").toAbsolutePath.normalize)
  }
}
