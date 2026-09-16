package com.clarifi.reporting.ermine.json

import com.sun.net.httpserver.{ HttpExchange, HttpHandler, HttpServer }
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.util.concurrent.{ ExecutorService, Executors, ThreadFactory }
import java.util.concurrent.atomic.AtomicInteger
import scala.collection.immutable.List
import scala.util.control.NonFatal

/** The HTTP face of the document runner (design note §3.4a), on the JDK's own
  * `com.sun.net.httpserver` -- no new dependency, and nothing in the request
  * path that is not already in the jar.
  *
  * {{{
  *   POST /report/<Module.Name>   body: the request object, response: the document
  *   GET  /data/<token>           response: the deferred relation's inline object
  *   GET  /health                 response: {"status":"ok","modules":[..]}
  * }}}
  *
  * Every response is `application/json; charset=utf-8` with a
  * `Content-Length`: the `Buffered` strategy writes the whole document into a
  * `StringBuilder` and sends it only when `Runner` returns a `Right`, so a
  * failed scan yields a clean error object and never a truncated document.
  * Failures are `{"error":{"path":..,"message":..}}` with the status
  * `RunError` carries: 400 a bad request, 404 an unknown module / binding /
  * token / route, 405 a route used with the wrong method, 413 a body over
  * `maxBody`, 500 a report or a scan that failed.
  *
  * One INFO line per request on `ermine.json.http`, beside J3b's per-relation
  * lines on `ermine.json.doc`:
  * `POST /report/Sales status=200 ms=41 bytes=1180`.
  *
  * THREADS.  A fixed pool, because the JDK server's default executor runs
  * every exchange on the dispatcher thread, which would serialise the scans
  * as well as the evaluation.  `Runner` serialises evaluation on its own and
  * lets the scans overlap, so the pool size is the number of concurrent
  * DATABASE connections this process will open (`Run[DB]` is one connection
  * per thread), not a request queue depth.
  */
final class Server(val runner: Runner, port: Int, threads: Int, maxBody: Int, backlog: Int) {
  import Server._

  private val http: HttpServer = HttpServer.create(new InetSocketAddress(port), backlog)
  private val pool: ExecutorService = Executors.newFixedThreadPool(threads, new ThreadFactory {
    private val n = new AtomicInteger(0)
    def newThread(r: Runnable): Thread = {
      val t = new Thread(r, "ermine-serve-" + n.incrementAndGet())
      t.setDaemon(false)
      t
    }
  })

  http.setExecutor(pool)
  http.createContext("/", new HttpHandler {
    def handle(ex: HttpExchange): Unit = Server.this.dispatch(ex)
  })

  /** The port actually bound (the interesting one when 0 was asked for). */
  def boundPort: Int = http.getAddress.getPort

  def start(): Unit = http.start()

  /** Stop accepting, give `delaySeconds` to the exchanges in flight, then
    * shut the pool down (`HttpServer.stop` does not touch a supplied one). */
  def stop(delaySeconds: Int): Unit = {
    http.stop(delaySeconds)
    pool.shutdown()
  }

  private def dispatch(ex: HttpExchange): Unit = {
    val t0 = System.currentTimeMillis
    val method = ex.getRequestMethod
    val path = ex.getRequestURI.getPath
    var status = 500
    var bytes = 0L
    try {
      val (st, by) = route(ex, method, path)
      status = st
      bytes = by
    } catch {
      // a bug in this file, or a client that hung up mid-response.  A
      // StackOverflowError is not reachable today (the only recursive step in
      // the request path is argonaut's parse, which `Runner.parseBody` already
      // guards) but is caught beside NonFatal so that "every failure a client
      // sees has one shape" survives a future decoder that recurses deeper.
      case e: Throwable if NonFatal(e) || e.isInstanceOf[StackOverflowError] =>
        status = 500
        bytes = try send(ex, Failed(Runner.messageOf(e))) catch { case NonFatal(_) => 0L }
    } finally {
      ex.close()
      if (log.isInfoEnabled)
        log.info(method + " " + path + " status=" + status + " ms=" + (System.currentTimeMillis - t0) +
                 " bytes=" + bytes)
    }
  }

  private def route(ex: HttpExchange, method: String, path: String): (Int, Long) =
    if (path == Health)
      if (method == "GET" || method == "HEAD") (200, sendText(ex, 200, health))
      else notAllowed(ex, "GET, HEAD")
    else if (path.startsWith(ReportPrefix))
      if (method == "POST") report(ex, path.substring(ReportPrefix.length))
      else notAllowed(ex, "POST")
    else if (path.startsWith(DataPrefix))
      if (method == "GET" || method == "HEAD") data(ex, path.substring(DataPrefix.length))
      else notAllowed(ex, "GET, HEAD")
    else {
      val e = NotFound("no such route: " + path + "; this server has POST " + ReportPrefix +
                       "<Module>, GET " + DataPrefix + "<token> and GET " + Health)
      (e.status, send(ex, e))
    }

  private def notAllowed(ex: HttpExchange, allow: String): (Int, Long) = {
    ex.getResponseHeaders.set("Allow", allow)
    val e = MethodNotAllowed("this route takes " + allow)
    (e.status, send(ex, e))
  }

  private def report(ex: HttpExchange, module: String): (Int, Long) =
    body(ex) match {
      case Left(e) => (e.status, send(ex, e))
      case Right(text) =>
        val out = new java.lang.StringBuilder
        // Buffered: the text is sent only when the whole write succeeded, so a
        // failed scan's prefix (J3b) never leaves this method.
        runner.renderText(decode(module), text, out) match {
          case Left(e)  => (e.status, send(ex, e))
          case Right(_) => (200, sendText(ex, 200, out.toString))
        }
    }

  private def data(ex: HttpExchange, token: String): (Int, Long) = {
    val out = new java.lang.StringBuilder
    runner.data(decode(token), out) match {
      case Left(e)  => (e.status, send(ex, e))
      case Right(_) => (200, sendText(ex, 200, out.toString))
    }
  }

  /** The request body as text, or 413.  Reads at most `maxBody` bytes and
    * then one more: a body that does not fit is refused without buffering
    * it, so a client cannot spend the server's heap. */
  private def body(ex: HttpExchange): Either[RunError, String] = {
    val in = ex.getRequestBody
    val buf = new ByteArrayOutputStream
    val chunk = new Array[Byte](8192)
    var over = false
    var n = in.read(chunk)
    while (n >= 0 && !over) {
      if (buf.size + n > maxBody) over = true
      else {
        buf.write(chunk, 0, n)
        n = in.read(chunk)
      }
    }
    if (over) Left(TooLarge("the request body is over the " + maxBody + " byte limit"))
    else Right(new String(buf.toByteArray, "UTF-8"))
  }

  private def health: String = {
    val sb = new java.lang.StringBuilder
    sb.append("{\"status\":")
    Rows.string(sb, runner.bootFailure.map(_ => "error").getOrElse("ok"))
    sb.append(",\"").append(Wire.Version).append("\":").append(Wire.version)
    sb.append(",\"modules\":[")
    var first = true
    runner.loadedModules.toList.sorted.foreach { m =>
      if (!first) sb.append(',')
      first = false
      Rows.string(sb, m)
    }
    sb.append("]}")
    sb.toString
  }

  private def send(ex: HttpExchange, e: RunError): Long = sendText(ex, e.status, e.body)

  private def sendText(ex: HttpExchange, status: Int, text: String): Long = {
    val bs = text.getBytes("UTF-8")
    ex.getResponseHeaders.set("Content-Type", "application/json; charset=utf-8")
    // The length is in BYTES, never characters: a document with a non-ASCII
    // character in it (a `settings` string, a module name in an error) has
    // more bytes than chars, and a Content-Length short of the body truncates
    // it for every client.  For a HEAD the JDK server turns this into the
    // Content-Length header a GET would have carried and sends no body, which
    // is what RFC 7230 asks for.
    val head = ex.getRequestMethod == "HEAD"
    if (head) ex.getResponseHeaders.set("Content-Length", Integer.toString(bs.length))
    ex.sendResponseHeaders(status, bs.length.toLong)
    if (!head) {
      val os = ex.getResponseBody
      try os.write(bs) finally os.close()
    }
    bs.length.toLong
  }
}

object Server {
  private val log = org.apache.log4j.Logger.getLogger("ermine.json.http")

  val Health: String       = "/health"
  val ReportPrefix: String = "/report/"
  val DataPrefix: String   = "/data/"

  /** Defaults: a 16-thread pool and a 4 MiB body cap. */
  val defaultThreads = 16
  val defaultMaxBody = 4 * 1024 * 1024
  val defaultBacklog = 0

  def apply(runner: Runner, port: Int,
            threads: Int = defaultThreads,
            maxBody: Int = defaultMaxBody,
            backlog: Int = defaultBacklog): Server =
    new Server(runner, port, threads, maxBody, backlog)

  /** A path segment, percent-decoded.  A module name has no character that
    * needs escaping, but a client that escapes anyway must still be
    * understood, and `Runner.moduleNameOk` refuses whatever comes out. */
  private[json] def decode(segment: String): String =
    try java.net.URLDecoder.decode(segment, "UTF-8")
    catch { case NonFatal(_) => segment }
}
