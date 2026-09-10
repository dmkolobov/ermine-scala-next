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
                val cp  = try Integer.parseInt(hex, 16)
                          catch { case _: NumberFormatException => fail("bad \\u escape '" + hex + "'") }
                sb += cp.toChar
                pos += 4
              case e    => fail("bad escape '\\" + e + "'")
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
  */
final class Wire(in: InputStream, out: OutputStream, log: String => Unit) {

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
          val tClip = Phases.now
          log(">> " + clip(body))
          Phases.add("rpc.log", tClip)
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

  def send(msg: Json): Unit = {
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

  private def clip(s: String): String =
    if (s.length > 2000) s.substring(0, 2000) + "...[" + s.length + " chars]" else s
}

/** JSON-RPC dispatch, strictly one message at a time: SessionEnv is not
  * thread-safe (tracker/LSP-ROADMAP.md decision 3), so there is exactly one
  * loop and handlers run on it in arrival order.
  */
final class Server(wire: Wire, log: String => Unit) {
  import Rpc._

  private var requests      = Map.empty[String, Json => Json]
  private var notifications = Map.empty[String, Json => Unit]
  private var exitCode      = Option.empty[Int]

  private var idleQuietMs: Int          = 0
  private var idlePending: () => Boolean = () => false
  private var idleWork:    () => Unit    = () => ()

  def onRequest(method: String)(h: Json => Json): Unit      = requests += method -> h
  def onNotification(method: String)(h: Json => Unit): Unit = notifications += method -> h

  /** Deferred work: when `pending` says there is some AND the input
    * stream has been quiet for `quietMillis`, `work` runs on the
    * dispatch thread, between messages.  With nothing pending the loop
    * blocks on the stream exactly as before, so this costs no latency
    * on ordinary traffic. */
  def onIdle(quietMillis: Int)(pending: => Boolean)(work: => Unit): Unit = {
    idleQuietMs = quietMillis
    idlePending = () => pending
    idleWork    = () => work
  }

  /** End the run() loop after the current message. */
  def stop(code: Int): Unit = exitCode = Some(code)

  def respond(id: Json, result: Json): Unit =
    wire.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> id, "result" -> result))

  def respondError(id: Json, code: Int, message: String): Unit =
    wire.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "id" -> id,
      "error" -> Json.obj("code" -> Json.num(code), "message" -> Json.Str(message))))

  def notify(method: String, params: Json): Unit =
    wire.send(Json.obj("jsonrpc" -> Json.Str("2.0"), "method" -> Json.Str(method), "params" -> params))

  /** Some(code) after stop(code); None when the client closed the stream. */
  def run(): Option[Int] = {
    var open = true
    while (open && exitCode.isEmpty)
      if (idlePending() && !wire.ready(idleQuietMs))
        try idleWork()
        catch { case e: Throwable => log("rpc: idle work crashed: " + stackTrace(e)) }
      else wire.receive() match {
        case None       => open = false
        case Some(text) => handle(text)
      }
    exitCode
  }

  private def handle(text: String): Unit = {
    // 7.0(d): the JSON parse of the body just read.
    val tJson = Phases.now
    val parsed = Json.parse(text)
    Phases.add("rpc.json", tJson)
    parsed match {
      case Left(err) =>
        log("rpc: unparseable message: " + err)
        respondError(Json.Null, ParseError, "invalid JSON: " + err)
      case Right(msg) =>
        val id     = msg("id")
        val method = msg("method") flatMap (_.str)
        val params = msg("params") getOrElse Json.Null
        (method, id) match {
          case (Some(m), Some(reqId)) => request(m, reqId, params)
          case (Some(m), None)        => notification(m, params)
          case (None, Some(_))        => log("rpc: dropping response from client (we sent no request)")
          case (None, None)           => respondError(Json.Null, InvalidRequest, "message has neither method nor id")
        }
    }
  }

  private def request(method: String, id: Json, params: Json): Unit =
    requests get method match {
      case None    => respondError(id, MethodNotFound, "unknown method: " + method)
      case Some(h) =>
        try respond(id, h(params))
        catch {
          case RpcError(code, message) => respondError(id, code, message)
          case e: Throwable            =>
            log("rpc: " + method + " crashed: " + stackTrace(e))
            respondError(id, InternalError, method + " failed: " + e)
        }
    }

  private def notification(method: String, params: Json): Unit =
    notifications get method match {
      // Unknown "$/"-prefixed notifications are optional by protocol; drop
      // the rest quietly too, but note them in the log.
      case None    => if (!(method startsWith "$/")) log("rpc: ignoring notification " + method)
      case Some(h) =>
        try h(params)
        catch { case e: Throwable => log("rpc: notification " + method + " crashed: " + stackTrace(e)) }
    }
}
