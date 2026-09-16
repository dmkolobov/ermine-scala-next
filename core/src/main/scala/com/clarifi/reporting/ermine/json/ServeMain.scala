package com.clarifi.reporting.ermine.json

import argonaut.{ Json, Parse }
import scala.collection.immutable.List

/** `bin/ermine-serve`: the document runner behind HTTP.
  *
  * {{{
  *   bin/ermine-serve --root core/src/test/resources/doc --preload Sales --port 8080
  *   curl -s localhost:8080/report/Sales -d '{"params": {"fromDay": "2026-01-01", ...}}'
  * }}}
  *
  * Flags:
  * {{{
  *   --root DIR         a module source root, searched before the classpath (repeatable)
  *   --preload Module   load at boot rather than on the first request (repeatable)
  *   --db URL           the JDBC url            (default jdbc:sqlite::memory:)
  *   --dialect NAME     sqlite|mssql|mysql|postgres|vertica  (default sqlite)
  *   --port N           0 binds an ephemeral port            (default 8080)
  *   --report-name NAME the binding a module's report lives under  (default report)
  *   --ttl SECONDS      how long a deferred token resolves   (default 300)
  *   --max-tokens N     deferred plans kept at once          (default 1024)
  *   --threads N        request threads = concurrent connections (default 16)
  *   --max-body BYTES   the request body cap                 (default 4194304)
  *   --settings JSON    the document's "settings" object     (default {})
  * }}}
  *
  * The bound port is printed on stdout as `listening on <port>` -- the one
  * thing this program writes there, so a script that asked for port 0 can
  * read it.  Everything else (session chatter, request lines) is log4j's.
  */
object ServeMain {

  private val usage =
    "usage: ermine-serve [--root DIR]... [--preload Module]... [--db URL] [--dialect NAME]\n" +
    "                    [--port N] [--report-name NAME] [--ttl SECONDS] [--max-tokens N]\n" +
    "                    [--threads N] [--max-body BYTES] [--settings JSON]"

  final case class Options(roots: List[String] = List(),
                           preload: List[String] = List(),
                           url: String = "jdbc:sqlite::memory:",
                           dialect: String = "sqlite",
                           port: Int = 8080,
                           reportName: String = "report",
                           ttlSeconds: Long = 300L,
                           maxTokens: Int = 1024,
                           threads: Int = Server.defaultThreads,
                           maxBody: Int = Server.defaultMaxBody,
                           settings: Json = Json.jEmptyObject)

  /** Parse the command line.  `Left` is what to print and die with. */
  def options(args: List[String]): Either[String, Options] = {
    def go(as: List[String], o: Options): Either[String, Options] = as match {
      case Nil => Right(o)
      case "-h" :: _ | "--help" :: _ => Left(usage)
      case flag :: rest =>
        def need(k: String => Either[String, Options]): Either[String, Options] = rest match {
          case v :: more => k(v).right.flatMap(oo => go(more, oo))
          case Nil       => Left(flag + " needs a value\n" + usage)
        }
        def int(v: String, what: String)(k: Int => Options): Either[String, Options] =
          try Right(k(v.toInt)) catch { case _: NumberFormatException => Left(what + " is a number, not " + v) }
        def long(v: String, what: String)(k: Long => Options): Either[String, Options] =
          try Right(k(v.toLong)) catch { case _: NumberFormatException => Left(what + " is a number, not " + v) }
        flag match {
          case "--root"        => need(v => Right(o.copy(roots = o.roots :+ v)))
          case "--preload"     => need(v => Right(o.copy(preload = o.preload :+ v)))
          case "--db"          => need(v => Right(o.copy(url = v)))
          case "--dialect"     => need(v => Right(o.copy(dialect = v)))
          case "--port"        => need(v => int(v, "--port")(n => o.copy(port = n)))
          case "--report-name" => need(v => Right(o.copy(reportName = v)))
          case "--ttl"         => need(v => long(v, "--ttl")(n => o.copy(ttlSeconds = n)))
          case "--max-tokens"  => need(v => int(v, "--max-tokens")(n => o.copy(maxTokens = n)))
          case "--threads"     => need(v => int(v, "--threads")(n => o.copy(threads = n)))
          case "--max-body"    => need(v => int(v, "--max-body")(n => o.copy(maxBody = n)))
          case "--settings"    => need(v => Parse.parse(v).fold(
                                    m => Left("--settings is a JSON object: " + m),
                                    j => if (j.isObject) Right(o.copy(settings = j))
                                         else Left("--settings is a JSON object")))
          case other           => Left("unknown option " + other + "\n" + usage)
        }
    }
    go(args, Options())
  }

  def main(args: Array[String]): Unit = {
    com.clarifi.reporting.util.Logging.initializeLogging
    options(args.toList) match {
      case Left(m) =>
        System.err.println(m)
        sys.exit(if (m == usage) 0 else 1)
      case Right(o) => RunnerConfig.backend(o.dialect, o.url) match {
        case Left(m) =>
          System.err.println(m)
          sys.exit(1)
        case Right(backend) =>
          val runner = new Runner(RunnerConfig(
            roots      = o.roots,
            preload    = o.preload,
            reportName = o.reportName,
            run        = backend._1,
            scanner    = backend._2,
            settings   = o.settings,
            ttlMillis  = o.ttlSeconds * 1000L,
            maxTokens  = o.maxTokens))
          runner.bootFailure.foreach { why =>
            System.err.println("the runner did not boot: " + why)
            sys.exit(1)
          }
          val server = Server(runner, o.port, o.threads, o.maxBody)
          server.start()
          // the ONE thing on stdout, so `--port 0` is scriptable
          println("listening on " + server.boundPort)
          System.out.flush()
      }
    }
  }
}
