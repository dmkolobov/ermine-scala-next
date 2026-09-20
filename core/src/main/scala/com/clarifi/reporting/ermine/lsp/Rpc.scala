package com.clarifi.reporting.ermine.lsp

import java.io.{ InputStream, OutputStream }
import java.nio.charset.StandardCharsets.{ US_ASCII, UTF_8 }
import com.clarifi.reporting.ermine.session.Phases

/** Minimal JSON model for the LSP subset we speak.  Hand-rolled because the
  * build carries no JSON dependency (tracker/LSP-ROADMAP.md decision 1).
  */
sealed abstract class Json {
  /** Field lookup; None on non-objects and absent fields. */
  def apply(field: String): Option[Json] = this match {
    case Json.Obj(fields) => fields collectFirst { case (`field`, v) => v }
    case _                => None
  }
  /** Path lookup: j / "a" / "b". */
  def /(field: String): Option[Json] = apply(field)
  def str: Option[String]     = this match { case Json.Str(s)  => Some(s); case _ => None }
  def num: Option[Double]     = this match { case Json.Num(n)  => Some(n); case _ => None }
  def int: Option[Int]        = num map (_.toInt)
  def bool: Option[Boolean]   = this match { case Json.Bool(b) => Some(b); case _ => None }
  def arr: Option[List[Json]] = this match { case Json.Arr(vs) => Some(vs); case _ => None }
}

object Json {
  case object Null                                    extends Json
  final case class Bool(value: Boolean)               extends Json
  final case class Num(value: Double)                 extends Json
  final case class Str(value: String)                 extends Json
  final case class Arr(values: List[Json])            extends Json
  final case class Obj(fields: List[(String, Json)])  extends Json

  def obj(fields: (String, Json)*): Obj = Obj(fields.toList)
  def arr(values: Json*): Arr           = Arr(values.toList)
  def num(n: Int): Num                  = Num(n.toDouble)

  // ---------------------------------------------------------------- printing

  def print(j: Json): String = {
    val sb = new StringBuilder
    pr(j, sb)
    sb.toString
  }

  private def pr(j: Json, sb: StringBuilder): Unit = j match {
    case Null       => sb ++= "null"
    case Bool(b)    => sb ++= (if (b) "true" else "false")
    // LSP traffic is overwhelmingly integers (positions, versions); print
    // whole numbers without a fraction so clients reading them as ints work.
    case Num(n)     => if (n.isWhole && math.abs(n) < 1e15) sb ++= n.toLong.toString
                       else sb ++= n.toString
    case Str(s)     => prString(s, sb)
    case Arr(vs)    =>
      sb += '['
      var first = true
      vs foreach { v => if (!first) sb += ','; first = false; pr(v, sb) }
      sb += ']'
    case Obj(fs)    =>
      sb += '{'
      var first = true
      fs foreach { case (k, v) =>
        if (!first) sb += ','
        first = false
        prString(k, sb)
        sb += ':'
        pr(v, sb)
      }
      sb += '}'
  }

  private def prString(s: String, sb: StringBuilder): Unit = {
    sb += '"'
    s foreach {
      case '"'           => sb ++= "\\\""
      case '\\'          => sb ++= "\\\\"
      case '\b'          => sb ++= "\\b"
      case '\f'          => sb ++= "\\f"
      case '\n'          => sb ++= "\\n"
      case '\r'          => sb ++= "\\r"
      case '\t'          => sb ++= "\\t"
      case c if c < ' '  => sb ++= "\\u%04x".format(c.toInt)
      case c             => sb += c
    }
    sb += '"'
  }

  // ----------------------------------------------------------------- parsing

  def parse(input: String): Either[String, Json] = {
    val p = new P(input)
    try {
      p.ws()
      val v = p.value()
      p.ws()
      if (p.pos < input.length) Left("trailing content at offset " + p.pos)
      else Right(v)
    } catch { case Fail(msg, at) => Left(msg + " at offset " + at) }
  }

  private final case class Fail(msg: String, at: Int)
    extends Exception(msg) with scala.util.control.NoStackTrace

  private final class P(s: String) {
    var pos = 0

    def fail(msg: String): Nothing = throw Fail(msg, pos)

    def ws(): Unit =
      while (pos < s.length && " \t\n\r".indexOf(s.charAt(pos).toInt) >= 0) pos += 1

    def value(): Json = {
      if (pos >= s.length) fail("unexpected end of input")
      s.charAt(pos) match {
        case '{'                        => obj()
        case '['                        => array()
        case '"'                        => Str(string())
        case 't'                        => lit("true", Bool(true))
        case 'f'                        => lit("false", Bool(false))
        case 'n'                        => lit("null", Null)
        case c if c == '-' || c.isDigit => number()
        case c                          => fail("unexpected character '" + c + "'")
      }
    }

    private def lit(text: String, v: Json): Json =
      if (s.regionMatches(pos, text, 0, text.length)) { pos += text.length; v }
      else fail("invalid literal")

    private def number(): Json = {
      val start = pos
      if (s.charAt(pos) == '-') pos += 1
      while (pos < s.length && s.charAt(pos).isDigit) pos += 1
      if (pos < s.length && s.charAt(pos) == '.') {
        pos += 1
        while (pos < s.length && s.charAt(pos).isDigit) pos += 1
      }
      if (pos < s.length && (s.charAt(pos) == 'e' || s.charAt(pos) == 'E')) {
        pos += 1
        if (pos < s.length && (s.charAt(pos) == '+' || s.charAt(pos) == '-')) pos += 1
        while (pos < s.length && s.charAt(pos).isDigit) pos += 1
      }
      val text = s.substring(start, pos)
      try Num(text.toDouble)
      catch { case _: NumberFormatException => fail("malformed number '" + text + "'") }
    }

    private def string(): String = {
      pos += 1  // opening quote
      val sb = new StringBuilder
      var done = false
      while (!done) {
        if (pos >= s.length) fail("unterminated string")
        s.charAt(pos) match {
          case '"'  => pos += 1; done = true
          case '\\' =>
            pos += 1
            if (pos >= s.length) fail("unterminated escape")
            s.charAt(pos) match {
              case '"'  => sb += '"';  case '\\' => sb += '\\'; case '/' => sb += '/'
              case 'b'  => sb += '\b'; case 'f'  => sb += '\f'
              case 'n'  => sb += '\n'; case 'r'  => sb += '\r'; case 't' => sb += '\t'
              case 'u'  =>
                if (pos + 4 >= s.length) fail("truncated \\u escape")
                val hex = s.substring(pos + 1, pos + 5)
                // The four hex characters are NOT echoed: they come from
                // inside a string literal, and an unparseable body is logged
                // as this error alone (rule A6, JSON-WIDGET-PLAYGROUND §4).
                // The offset locates them for anyone holding the body.
                val cp  = try Integer.parseInt(hex, 16)
                          catch { case _: NumberFormatException => fail("bad \\u escape") }
                sb += cp.toChar
                pos += 4
              case _    => fail("bad escape")   // the character is not echoed: see above
            }
            pos += 1
          case c    => sb += c; pos += 1
        }
      }
      sb.toString
    }

    private def obj(): Json = {
      pos += 1  // '{'
      ws()
      val fields = List.newBuilder[(String, Json)]
      if (pos < s.length && s.charAt(pos) == '}') pos += 1
      else {
        var more = true
        while (more) {
          ws()
          if (pos >= s.length || s.charAt(pos) != '"') fail("expected field name")
          val k = string()
          ws()
          if (pos >= s.length || s.charAt(pos) != ':') fail("expected ':'")
          pos += 1
          ws()
          fields += (k -> value())
          ws()
          if (pos >= s.length) fail("unterminated object")
          s.charAt(pos) match {
            case ',' => pos += 1
            case '}' => pos += 1; more = false
            case _   => fail("expected ',' or '}'")
          }
        }
      }
      Obj(fields.result())
    }

    private def array(): Json = {
      pos += 1  // '['
      ws()
      val values = List.newBuilder[Json]
      if (pos < s.length && s.charAt(pos) == ']') pos += 1
      else {
        var more = true
        while (more) {
          ws()
          values += value()
          ws()
          if (pos >= s.length) fail("unterminated array")
          s.charAt(pos) match {
            case ',' => pos += 1
            case ']' => pos += 1; more = false
            case _   => fail("expected ',' or ']'")
          }
        }
      }
      Arr(values.result())
    }
  }
}

object Wire {
  /** The largest frame the server reads: 64 MiB, well above any document
    * a full-sync didChange carries and well below what would matter to
    * the heap. */
  val MaxFrame: Int = 64 << 20

  /** Every log line of a message body is clipped here.  In the companion
    * because the INCOMING line is logged by `Server.handle` now (WP-1,
    * JSON-WIDGET-PLAYGROUND §4) and must clip exactly as `send` does. */
  def clip(s: String): String =
    if (s.length > 2000) s.substring(0, 2000) + "...[" + s.length + " chars]" else s
}

object Rpc {
  val ParseError     = -32700
  val InvalidRequest = -32600
  val MethodNotFound = -32601
  val InvalidParams  = -32602
  val InternalError  = -32603
  /** LSP's own code (not JSON-RPC's): the request was well formed and
    * the server refused to do it.  6.3's rename refusals that are about
    * the WORKSPACE (a def-site in an unopened file, a stale index, a
    * capture) answer with this; the ones about the request itself (an
    * invalid or wrong-case new name, an operator) answer InvalidParams. */
  val RequestFailed  = -32803
  /** LSP's own code for a request the server will not finish because it was
    * cancelled: the queued render a newer one replaced, and the in-flight
    * one a `$/cancelRequest` named (JSON-WIDGET-PLAYGROUND §2.5). */
  val RequestCancelled = -32800

  /** How a deferred request handler answers: `Left((code, message))` or
    * `Right(result)`, from any thread, exactly once. */
  type Answer = Either[(Int, String), Json] => Unit

  /** Methods whose incoming body never reaches the log (rule A6 of
    * tracker/JSON-WIDGET-PLAYGROUND.md §8.1): `ermine/preview/connect`
    * carries the database password.  `Server.handle` logs
    * ">> <method> [redacted]" for these and the body for everything else. */
  val Redacted: Set[String] = Set("ermine/preview/connect")

  def stackTrace(e: Throwable): String = {
    val sw = new java.io.StringWriter
    e.printStackTrace(new java.io.PrintWriter(sw))
    sw.toString
  }
}

/** Throw from a request handler to answer a JSON-RPC error. */
final case class RpcError(code: Int, message: String)
  extends Exception(message) with scala.util.control.NoStackTrace

/** One JSON-RPC peer over Content-Length framed streams (the LSP base
  * protocol).  Reads and writes are raw bytes: Content-Length counts UTF-8
  * bytes, not characters.
  *
  * THREADS (WP-1).  `send` is safe from ANY thread: it is `synchronized`,
  * so one call writes one whole frame.  `receive` and `ready` are
  * DISPATCH-THREAD-ONLY: both read `in` a byte at a time with no lock, and
  * `receive` carries a frame's length across reads, so a second reader
  * would tear a frame in half.  Nothing in this tree reads off the
  * dispatch loop.
  */
final class Wire(in: InputStream, out: OutputStream, log: String => Unit) {
  import Wire.{ MaxFrame, clip }

  /** One framed message body, or None once the client closes the stream. */
  def receive(): Option[String] = {
    // 7.0(d)/Decision (d): the frame read of one full-sync didChange, in
    // process, against the survey's out-of-process ~369us figure.  The
    // clock starts on the FIRST header byte, so it excludes the block
    // waiting for the client and includes only what this server does with
    // the bytes.  Inert unless -Dermine.lsp.phases=true.
    var len  = -1
    var line = readLine()
    val tFrame = Phases.now
    if (line.isEmpty) None  // clean EOF between messages
    else {
      var eof = false
      while (!eof && line.exists(_.nonEmpty)) {
        val l = line.get
        val i = l.indexOf(':')
        if (i > 0 && l.substring(0, i).trim.equalsIgnoreCase("Content-Length")) {
          try len = l.substring(i + 1).trim.toInt
          catch { case _: NumberFormatException => log("wire: bad Content-Length in '" + l + "'") }
        }
        line = readLine()
        if (line.isEmpty) eof = true
      }
      if (eof) { log("wire: eof inside headers"); None }
      else if (len < 0) {
        // Without a length there is no way back in sync on the stream.
        log("wire: headers without Content-Length; closing")
        None
      } else if (len > MaxFrame) {
        // TestLspRobustness (review S2): the buffer is sized by the header,
        // so a client that says two gigabytes would have this JVM try to
        // allocate two gigabytes -- an OutOfMemoryError nothing catches.
        // A frame that size is a broken client, and after it the stream
        // cannot be resynchronised any more than after a missing length.
        log(s"wire: Content-Length $len exceeds the $MaxFrame-byte frame limit; closing")
        None
      } else {
        val buf   = new Array[Byte](len)
        var off   = 0
        var short = false
        while (off < len && !short) {
          val n = in.read(buf, off, len - off)
          if (n < 0) short = true else off += n
        }
        if (short) { log("wire: eof inside message body"); None }
        else {
          val body = new String(buf, UTF_8)
          Phases.add("rpc.frame", tFrame)
          Phases.count("rpc.bytes", len.toLong)
          // WP-1: the ">>" line used to be logged here, before the method
          // was known, which put the `ermine/preview/connect` body (the
          // database password) in the log file -- rule A6.  It is logged by
          // `Server.handle` now, after the parse, by method.  The "rpc.log"
          // phase moved with it.
          Some(body)
        }
      }
    }
  }

  /** Whether input is already waiting, giving it up to `millis` to turn
    * up.  The dispatch loop uses this to notice a QUIET stream, which is
    * how a debounced check fires without a second thread or a queue
    * (roadmap decision 3: one request at a time, no exceptions). */
  def ready(millis: Int): Boolean = {
    val deadline = System.nanoTime + millis * 1000000L
    var n = in.available()
    while (n <= 0 && System.nanoTime < deadline) {
      Thread.sleep(5)
      n = in.available()
    }
    n > 0
  }

  /** One whole frame, atomically.  `synchronized` (WP-1) so a second
    * sending thread -- the preview thread of JSON-WIDGET-PLAYGROUND
    * §2.3 -- cannot slip its header between this header and this body.
    * The monitor is held for the write of a whole document, so a large
    * answer to a slow client delays the next frame behind it; the render
    * side caps document size before it calls this (WP-5).  The "<<" line
    * is unchanged, and being inside the monitor it cannot interleave
    * either: no server-sent message carries a secret (§8 rule A5). */
  def send(msg: Json): Unit = synchronized {
    val body = Json.print(msg).getBytes(UTF_8)
    out.write(("Content-Length: " + body.length + "\r\n\r\n").getBytes(US_ASCII))
    out.write(body)
    out.flush()
    log("<< " + clip(new String(body, UTF_8)))
  }

  /** One header line, CRLF (tolerating bare LF) stripped; None at EOF. */
  private def readLine(): Option[String] = {
    val sb = new StringBuilder
    var c  = in.read()
    if (c < 0) None
    else {
      while (c >= 0 && c != '\n') { sb += c.toChar; c = in.read() }
      val line = sb.toString
      Some(if (line endsWith "\r") line.substring(0, line.length - 1) else line)
    }
  }
}

/** JSON-RPC dispatch, strictly one message at a time: SessionEnv is not
  * thread-safe (tracker/LSP-ROADMAP.md decision 3), so there is exactly one
  * loop and handlers run on it in arrival order.
  */
final class Server(wire: Wire, log: String => Unit) {
  import Rpc._

  private var requests      = Map.empty[String, Json => Json]
  private var deferred      = Map.empty[String, (Json, Json, Rpc.Answer) => Unit]
  private var notifications = Map.empty[String, Json => Unit]
  private var exitCode      = Option.empty[Int]

  private var idleQuiet:   () => Int     = () => 0
  private var idlePending: () => Boolean = () => false
  private var idleWork:    () => Unit    = () => ()

  def onRequest(method: String)(h: Json => Json): Unit      = requests += method -> h
  def onNotification(method: String)(h: Json => Unit): Unit = notifications += method -> h

  /** A request whose ANSWER is deferred (WP-1, JSON-WIDGET-PLAYGROUND
    * §2.3): `h` runs on the dispatch thread like any other handler, but
    * instead of returning a result it is handed the params and an `answer`
    * callback to keep.
    *
    *  - `answer` may be called from ANY thread: it reaches the client
    *    through the synchronised `Wire.send` and touches no dispatcher
    *    state.  That is what lets a background thread finish a request the
    *    dispatch loop has already moved past.
    *  - `answer` answers EXACTLY ONCE.  The first call wins; a second call
    *    sends NOTHING and is logged ("second answer ... ignored"), so one
    *    request is one response however many callers race.
    *  - a handler that throws BEFORE answering still yields exactly one
    *    response, by the same crash path a synchronous handler takes:
    *    `RpcError` becomes its own code and message, anything else is
    *    logged with its stack trace and answered `InternalError` with
    *    `method + " failed: " + e`.  A handler that throws AFTER answering
    *    (or after passing `answer` to a thread that already answered) has
    *    its throw logged only -- the answer already sent is not replaced.
    *  - a handler that keeps `answer` and NEVER calls it yields NO
    *    response, no log line and no timeout: this dispatcher has no
    *    deadline of its own and the request simply stays open until the
    *    client gives up or the process ends.  Whatever needs a deadline
    *    brings its own -- the preview's watchdog is WP-5 (§2.5).
    *  - the one-shot token is taken BEFORE the send, not after, so a `send`
    *    that throws (a closed pipe) is NOT retried by a later `answer`:
    *    that request is spent.  The exception from such a send propagates
    *    on whatever thread called `answer`, background thread included,
    *    where it is that thread's to handle -- `answer` catches nothing.
    *
    * A method registered both here and with `onRequest` is served by
    * `onRequest`: the synchronous map is consulted first. */
  def onRequestDeferred(method: String)(h: (Json, Rpc.Answer) => Unit): Unit =
    deferred += method -> ((_: Json, params: Json, answer: Rpc.Answer) => h(params, answer))

  /** The same, for a handler that needs THE REQUEST'S OWN ID as well as its
    * params -- everything `onRequestDeferred` promises holds unchanged.
    *
    * WP-5 (JSON-WIDGET-PLAYGROUND §2.5) is why it exists: `$/cancelRequest`
    * names a request by id, so the preview's queue has to know which id each
    * queued render belongs to in order to remove and answer THAT one.  The
    * id is not in the params of any LSP request -- it is the envelope's --
    * and nothing else in this dispatcher hands it to a handler, because
    * every other handler answers before it returns and never has to name
    * itself afterwards. */
  def onRequestDeferredWithId(method: String)(h: (Json, Json, Rpc.Answer) => Unit): Unit =
    deferred += method -> h

  /** Deferred work: when `pending` says there is some AND the input
    * stream has been quiet for `quietMillis`, `work` runs on the
    * dispatch thread, between messages.  With nothing pending the loop
    * blocks on the stream exactly as before, so this costs no latency
    * on ordinary traffic.
    *
    * 7.4: `quietMillis` is BY NAME and is re-evaluated on every loop
    * iteration that has pending work, which is what lets the window be
    * derived from what the pending work is measured to cost
    * (`Diagnostics.Debounce`).  It is read exactly once per wait, just
    * before the wait, so the value the caller computes is the value the
    * loop actually waits. */
  def onIdle(quietMillis: => Int)(pending: => Boolean)(work: => Unit): Unit = {
    idleQuiet   = () => quietMillis
    idlePending = () => pending
    idleWork    = () => work
  }

  /** End the run() loop after the current message.  DISPATCH THREAD ONLY,
    * for the same reason as `ask`: `exitCode` is a plain var, written here
    * and read by `run`'s loop condition, with no happens-before edge
    * between a background thread's write and that read -- the loop could
    * run on without ever seeing it.  Its one caller is a notification
    * handler (`Main.scala:301`), on the dispatch thread. */
  def stop(code: Int): Unit = exitCode = Some(code)

  def respond(id: Json, result: Json): Unit =
    wire.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> id, "result" -> result))

  def respondError(id: Json, code: Int, message: String): Unit =
    wire.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> id,
      "error" -> Json.obj("code" -> Json.num(code), "message" -> Json.Str(message))))

  /** THREAD RULE (WP-1; JSON-WIDGET-PLAYGROUND §2.3 and resolution 6e).
    * `notify`, `respond` and `respondError` -- hence a deferred `answer` --
    * are legal FROM ANY THREAD: each one call of the synchronised
    * `Wire.send` and no dispatcher state.  `ask` is DISPATCH-THREAD-ONLY
    * and is deliberately NOT made thread-safe: `clientRequestId` and
    * `clientPending` below are plain vars, written here and read by
    * `handle` on the dispatch loop, so a second thread calling `ask` could
    * mint a duplicate id or lose a continuation.  A server-to-client
    * request that background work needs (the work-done progress token of
    * §2.5) is issued by the dispatch thread when it enqueues the job. */
  def notify(method: String, params: Json): Unit =
    wire.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "method" -> Json.Str(method), "params" -> params))

  private var clientRequestId = 0
  private var clientPending   = Map.empty[Int, Json => Unit]

  /** A request TO the client (`client/registerCapability`, LSP-STALENESS
    * step 2).  The reply arrives on the dispatch loop like any other message
    * and `k` runs there, with the whole reply; nothing blocks on it.  Ids
    * are the server's own counter and never collide with the client's,
    * which live in a different direction.
    *
    * DISPATCH THREAD ONLY (the thread rule above, repeated here because
    * this is the method that breaks): `clientRequestId` and `clientPending`
    * are plain vars, written here and read by `handle`.  A background
    * thread calling this could mint a duplicate id or drop a continuation,
    * and it is not made thread-safe on purpose.  Use `notify` or a deferred
    * `answer` from a background thread instead. */
  def ask(method: String, params: Json)(k: Json => Unit): Unit = {
    clientRequestId += 1
    clientPending += clientRequestId -> k
    wire.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> Json.num(clientRequestId),
                       "method" -> Json.Str(method), "params" -> params))
  }

  /** Some(code) after stop(code); None when the client closed the stream. */
  def run(): Option[Int] = {
    var open = true
    while (open && exitCode.isEmpty)
      if (idlePending() && !wire.ready(idleQuiet()))
        try idleWork()
        catch { case e: Throwable => log("rpc: idle work crashed: " + stackTrace(e)) }
      else wire.receive() match {
        case None       => open = false
        case Some(text) => handle(text)
      }
    exitCode
  }

  /** The ">>" line for one incoming message.  Rule A6 (JSON-WIDGET-PLAYGROUND
    * §8.1) is absolute -- the connect body never reaches the log -- so the
    * body is logged only for a shape this dispatcher can actually read a
    * method out of:
    *
    *   - an object with a redacted method: the METHOD NAME only;
    *   - an object with any other string method, or with no method at all
    *     (a reply to one of our own requests, §8.1 rule A6): the body,
    *     clipped exactly as `Wire.send` clips the "<<" line;
    *   - an object whose `method` is present but is NOT a string, and any
    *     message that is not an object at all (a JSON array, i.e. a batch,
    *     or a bare literal): NO body.  Neither shape is dispatched by
    *     method, so `Rpc.Redacted` cannot be consulted for it, and both can
    *     carry a connect body -- `[{"method":"ermine/preview/connect",...}]`
    *     is the witness.  How they are ANSWERED is unchanged.
    */
  private def incomingLine(msg: Json, text: String): String = msg match {
    case Json.Obj(_) => msg("method") match {
      case None                             => Wire.clip(text)
      case Some(Json.Str(m)) if Redacted(m) => m + " [redacted]"
      case Some(Json.Str(_))                => Wire.clip(text)
      case Some(_)                          => "<non-string method> [redacted]"
    }
    case _           => "<non-object message> [redacted]"
  }

  private def handle(text: String): Unit = {
    // 7.0(d): the JSON parse of the body just read.
    val tJson = Phases.now
    val parsed = Json.parse(text)
    Phases.add("rpc.json", tJson)
    parsed match {
      case Left(err) =>
        // The body is NOT logged here: the method is unknown, so it could be
        // a mangled `ermine/preview/connect` (rule A6).  The parser's error
        // is all that goes out, and TestLspRobustness pins how much of the
        // input that error may quote.  The "rpc.log" phase is recorded on
        // this branch too, as it was when the line lived in `Wire.receive`
        // and every frame passed through it: the bucket still means "what
        // logging the incoming message cost", over the same population.
        val tBad = Phases.now
        log("rpc: unparseable message: " + err)
        Phases.add("rpc.log", tBad)
        respondError(Json.Null, ParseError, "invalid JSON: " + err)
      case Right(msg) =>
        val id     = msg("id")
        val method = msg("method") flatMap (_.str)
        val params = msg("params") getOrElse Json.Null
        // 7.0(d), and WP-1: the incoming line, now that the method is known.
        val tLog = Phases.now
        log(">> " + incomingLine(msg, text))
        Phases.add("rpc.log", tLog)
        (method, id) match {
          case (Some(m), Some(reqId)) => request(m, reqId, params)
          case (Some(m), None)        => notification(m, params)
          case (None, Some(rid))      =>
            rid.int.flatMap(i => clientPending.get(i).map(i -> _)) match {
              case Some((i, k)) =>
                clientPending -= i
                try k(msg)
                catch { case e: Throwable => log("rpc: reply handler for #" + i + " crashed: " + stackTrace(e)) }
              case None => log("rpc: dropping response from client (we sent no such request)")
            }
          case (None, None)           => respondError(Json.Null, InvalidRequest, "message has neither method nor id")
        }
    }
  }

  private def request(method: String, id: Json, params: Json): Unit =
    requests get method match {
      case Some(h) =>
        try respond(id, h(params))
        catch {
          case RpcError(code, message) => respondError(id, code, message)
          case e: Throwable            =>
            log("rpc: " + method + " crashed: " + stackTrace(e))
            respondError(id, InternalError, method + " failed: " + e)
        }
      case None    => deferred get method match {
        case Some(h) => deferredRequest(method, id, params, h)
        case None    => respondError(id, MethodNotFound, "unknown method: " + method)
      }
    }

  /** One deferred request: mint the exactly-once `answer`, hand it over,
    * and answer the handler's own crash with it (see `onRequestDeferred`). */
  private def deferredRequest(method: String, id: Json, params: Json,
                              h: (Json, Json, Rpc.Answer) => Unit): Unit = {
    val sent = new java.util.concurrent.atomic.AtomicBoolean(false)
    val answer: Rpc.Answer = a =>
      if (!sent.compareAndSet(false, true))
        log("rpc: second answer to " + method + " id=" + Json.print(id) + " ignored")
      else a match {
        case Right(result)         => respond(id, result)
        case Left((code, message)) => respondError(id, code, message)
      }
    try h(id, params, answer)
    catch {
      case RpcError(code, message) => answer(Left((code, message)))
      case e: Throwable            =>
        log("rpc: " + method + " crashed: " + stackTrace(e))
        answer(Left((InternalError, method + " failed: " + e)))
    }
  }

  private def notification(method: String, params: Json): Unit =
    notifications get method match {
      // The handler map is consulted FIRST, so a REGISTERED "$/" method is
      // delivered like any other: that is how WP-1 routes `$/cancelRequest`
      // (JSON-WIDGET-PLAYGROUND §2.5), with `onNotification`, and no
      // special case here.  UNREGISTERED "$/" notifications stay dropped --
      // they are optional by protocol -- and are not even logged; every
      // other unknown notification is dropped quietly but noted in the log.
      case None    => if (!(method startsWith "$/")) log("rpc: ignoring notification " + method)
      case Some(h) =>
        try h(params)
        catch { case e: Throwable => log("rpc: notification " + method + " crashed: " + stackTrace(e)) }
    }
}
