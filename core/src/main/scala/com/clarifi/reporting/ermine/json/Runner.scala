package com.clarifi.reporting.ermine.json

import argonaut.{ Json, Parse }
import com.clarifi.reporting.Run
import com.clarifi.reporting.backends.{ DB, Runners, Scanners }
import com.clarifi.reporting.relational.{ SMEnv, Scanner }
import com.clarifi.reporting.ermine.{ AppT, Global, Memory, Runtime, Type }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.syntax.Explicit
import scala.collection.immutable.List
import scala.util.control.NonFatal
import scalaparsers.{ Death, Supply }

/** How a request failed, with the HTTP status it maps to and the JSON body
  * `{"error":{"path":..,"message":..}}` every failure answers with.  `path`
  * is a JSON path into the REQUEST when there is one (`$.params.from`,
  * `$.data.strategy`) and `null` otherwise; a `Failed` raised by the writer
  * carries the path of the relation in the RESPONSE document instead, which
  * is the one case where the path is not the client's to fix -- the 500
  * status says so.
  *
  * `MethodNotAllowed` and `TooLarge` belong to the transport rather than to
  * `Runner`, but they are in the same vocabulary so that every response body
  * a client can see has one shape. */
sealed abstract class RunError(val status: Int) {
  def path: Option[String]
  def message: String

  /** `{"error":{"path":..,"message":..}}`, the body of every failure. */
  def body: String = {
    val sb = new java.lang.StringBuilder
    sb.append("{\"error\":{\"path\":")
    path match {
      case Some(p) => Rows.string(sb, p)
      case None    => sb.append("null")
    }
    sb.append(",\"message\":")
    Rows.string(sb, message)
    sb.append("}}")
    sb.toString
  }
}

/** The request is wrong: a body that is not JSON, an unknown key, a
  * parameter the report's type refuses, a report whose type is not
  * `Params -> Layout.Doc.Node`. */
final case class BadRequest(at: String, message: String) extends RunError(400) {
  def path: Option[String] = Some(at)
}
/** No such module, no such binding in it, or no such (or expired) token. */
final case class NotFound(message: String) extends RunError(404) {
  def path: Option[String] = None
}
/** The report, its module, or a scan failed: the server's fault. */
final case class Failed(message: String, at: Option[String] = None) extends RunError(500) {
  def path: Option[String] = at
}
/** The route exists but not for this method (the transport's). */
final case class MethodNotAllowed(message: String) extends RunError(405) {
  def path: Option[String] = None
}
/** The request body is over the server's cap (the transport's). */
final case class TooLarge(message: String) extends RunError(413) {
  def path: Option[String] = None
}

/** The request body of `POST /report/<Module>` (tracker/JSON-STAGE3-PLAN.md,
  * "Request body"):
  *
  * {{{
  *   {"params": <JSON of the report's Params type>,
  *    "data": {"default": "inline"|"deferred", "strategy": "buffered",
  *             "threshold": <rows>|null}}
  * }}}
  *
  * `data` and each of its keys are optional (inline, buffered, no
  * threshold); `params` is optional and absent means `null`, which is what a
  * report with no parameters (`Maybe`-only, or a `Json` parameter) wants.
  * Every key is closed: an unknown one at either level is a 400 naming it,
  * so a client's typo is not silently ignored.  `strategy: "streamed"` is
  * refused in v1. */
final case class Request(params: Json,
                         default: Delivery = Delivery.Inline,
                         strategy: Strategy = Strategy.Buffered,
                         threshold: Option[Long] = None)

object Request {
  val Params    = "params"
  val Data      = "data"
  val Default   = "default"
  val StrategyK = "strategy"
  val Threshold = "threshold"

  /** The empty request: no parameters, inline, buffered, no threshold. */
  val empty: Request = Request(Json.jNull)

  def parse(body: Json): Either[RunError, Request] =
    if (!body.isObject)
      Left(BadRequest("$", "the request body is a JSON object with the optional keys \"" +
                           Params + "\" and \"" + Data + "\""))
    else body.objectFieldsOrEmpty.find(k => k != Params && k != Data) match {
      case Some(k) =>
        Left(BadRequest("$." + k, "unknown request key; the body has \"" + Params + "\" and \"" + Data + "\""))
      case None =>
        val params = body.field(Params).getOrElse(Json.jNull)
        body.field(Data) match {
          case None                    => Right(Request(params))
          case Some(d) if d.isNull     => Right(Request(params))
          case Some(d) if !d.isObject  => Left(BadRequest("$." + Data, "\"" + Data + "\" is an object"))
          case Some(d)                 => data(d).right.map(c => Request(params, c._1, c._2, c._3))
        }
    }

  private def data(d: Json): Either[RunError, (Delivery, Strategy, Option[Long])] =
    d.objectFieldsOrEmpty.find(k => k != Default && k != StrategyK && k != Threshold) match {
      case Some(k) =>
        Left(BadRequest("$." + Data + "." + k, "unknown key; \"" + Data + "\" has \"" + Default +
                        "\", \"" + StrategyK + "\" and \"" + Threshold + "\""))
      case None =>
        delivery(d.field(Default)).right.flatMap { dv =>
          strategy(d.field(StrategyK)).right.flatMap { st =>
            threshold(d.field(Threshold)).right.map(t => (dv, st, t))
          }
        }
    }

  private def delivery(j: Option[Json]): Either[RunError, Delivery] = j match {
    case None                => Right(Delivery.Inline)
    case Some(v) if v.isNull => Right(Delivery.Inline)
    case Some(v) => v.string match {
      case Some(s) if s == Wire.Inline   => Right(Delivery.Inline)
      case Some(s) if s == Wire.Deferred => Right(Delivery.Deferred)
      case _ => Left(BadRequest("$." + Data + "." + Default,
                                "the default delivery is \"" + Wire.Inline + "\" or \"" + Wire.Deferred + "\""))
    }
  }

  private def strategy(j: Option[Json]): Either[RunError, Strategy] = j match {
    case None                => Right(Strategy.Buffered)
    case Some(v) if v.isNull => Right(Strategy.Buffered)
    case Some(v) => v.string match {
      case Some(s) if s == Strategy.Buffered.name => Right(Strategy.Buffered)
      case Some(s) if s == "streamed" =>
        Left(BadRequest("$." + Data + "." + StrategyK,
                        "the \"streamed\" strategy is not in version " + Wire.version + " of the wire; use \"" +
                        Strategy.Buffered.name + "\""))
      case _ => Left(BadRequest("$." + Data + "." + StrategyK,
                                "the strategy is \"" + Strategy.Buffered.name + "\""))
    }
  }

  private def threshold(j: Option[Json]): Either[RunError, Option[Long]] = j match {
    case None                => Right(None)
    case Some(v) if v.isNull => Right(None)
    case Some(v) => v.number.flatMap(_.toLong) match {
      case Some(n) if n >= 0L => Right(Some(n))
      case _ => Left(BadRequest("$." + Data + "." + Threshold,
                                "the threshold is a row count: a whole number of rows, or null"))
    }
  }
}

/** How a `Runner` is wired: where modules come from, what is loaded at boot,
  * the binding a report is looked up under, the database, the `settings`
  * object copied into every document, and the deferred plan cache's size and
  * time to live.
  *
  * `run` and `scanner` are passed rather than named so that a test can count
  * connections; `RunnerConfig.backend` builds the pair from a dialect name
  * and a JDBC URL. */
final case class RunnerConfig(roots: List[String] = List(),
                              preload: List[String] = List(),
                              reportName: String = "report",
                              run: Run[DB] = Runners.liteDB,
                              scanner: Scanner[DB] = Scanners.SQLite(SMEnv.dummySmenv),
                              settings: Json = Json.jEmptyObject,
                              ttlMillis: Long = 300000L,
                              maxTokens: Int = 1024,
                              clock: () => Long = WriteConfig.systemClock)

object RunnerConfig {
  /** The dialects `backends/Backends.scala` offers a scanner AND a runner for. */
  val dialects: List[String] = List("mssql", "mysql", "postgres", "sqlite", "vertica")

  /** A `Run[DB]` and a `Scanner[DB]` for a dialect name and a JDBC URL, or
    * why not (an unknown dialect, or a JDBC driver this JVM does not have --
    * `DB.Run` loads the driver class eagerly). */
  def backend(dialect: String, url: String): Either[String, (Run[DB], Scanner[DB])] = {
    val sms = SMEnv.dummySmenv
    try dialect.toLowerCase match {
      case "sqlite"                  => Right((Runners.SQLite(url), Scanners.SQLite(sms)))
      case "mssql" | "sqlserver"     => Right((Runners.MicrosoftSQLServer(url), Scanners.MicrosoftSQLServer(sms)))
      case "mysql"                   => Right((Runners.MySQL(url), Scanners.MySQL(sms)))
      case "postgres" | "postgresql" => Right((Runners.Postgres(url), Scanners.Postgres(sms)))
      case "vertica"                 => Right((Runners.Vertica(url), Scanners.Vertica(sms)))
      case other                     => Left("unknown dialect " + other + "; one of " + dialects.mkString(", "))
    } catch {
      case NonFatal(e) => Left("cannot open " + dialect + " at " + url + ": " + Runner.messageOf(e))
    }
  }
}

/** The document runner: parameters in, one JSON document out (design note
  * §3.3, §3.4a; tracker/JSON-STAGE3-PLAN.md).  New code, not
  * `writers/Ermine.scala`:
  *
  * {{{
  *   request JSON -> Decode -> report : Params -> Node -> Doc.fromRuntime
  *                          -> Write.doc inside one Run[DB].run -> one JSON object
  * }}}
  *
  * BOOT.  One `SessionEnv` for the process: `Lib.preamble`, then
  * `Layout.Doc` and the configured `preload` modules.  Module sources are
  * looked for in `cfg.roots` (in order) before the classpath, so a report
  * lives outside the jar.  A module named by a request is loaded on first
  * use and stays loaded.
  *
  * PER REPORT, ONCE.  `Session.eval` gives the binding's `(Type, Runtime)`;
  * `Decode.reportSignature` splits the type into `Params -> Result`; the
  * result must be `Layout.Doc.Node` (aliases expanded); `Decode.compile`
  * turns the parameter type into a `Decoder`, which needs no session
  * afterwards.  The four are cached per module: a request pays for a type
  * walk only the first time.
  *
  * PER REQUEST.  Decode `$.params`, apply the report, walk the value into a
  * `Doc`, then write the document inside ONE `Run[DB].run` so every relation
  * scans on one connection.  `Strategy.Buffered` means the caller gets the
  * text only when the write returns: `out` holds a prefix after a failure
  * and must be discarded (the HTTP server keeps a `StringBuilder` per
  * request and sends it only on `Right`).
  *
  * CONCURRENCY (the decision the brief asks to document).  Two locks' worth
  * of state, one lock -- and the lock is PROCESS-WIDE (`Runner.evalLock`),
  * not per instance, because part of what it guards is:
  *
  *  - EVALUATION IS SERIALISED.  `Session.loadModules`, `Session.eval` and
  *    everything that forces a `Runtime` run under one monitor.  Module
  *    loading mutates the `SessionEnv`'s eight maps field by field and the
  *    process-global `DataConDecl` registry -- two STATIC maps, written by
  *    `Session.loadModules`, last-writer-wins per `Global`, and read by both
  *    `Encode` and `Decode`, so a per-runner lock would let two runners
  *    overwrite each other's constructor field lists; `Supply` is documented
  *    single-threaded; and `Runtime.Thunk.state` is a non-volatile `var`
  *    (its whitehole latch protects against a cycle, not against a data
  *    race), so two threads forcing the same library thunk have no
  *    happens-before between them.  Evaluating a report is microseconds to
  *    milliseconds of CPU; the scan is where the time goes.  `GET /health` is
  *    the one thing that does NOT take the lock: it reads a volatile
  *    snapshot, so a probe answers while a slow report is evaluating.
  *  - SCANNING AND WRITING ARE CONCURRENT.  Nothing in `Doc`, `Write` or
  *    `Rows` reads the session, each request has its own `Appendable`, and
  *    `MemoryPlanCache` is synchronized (J3b).  `Run[DB]` hands each thread
  *    its own connection (`Run.ThreadLocalDC`).
  *
  * So N requests overlap on the database and queue on the interpreter.
  * Property (d) of `TestRunner` asserts that concurrent requests answer
  * exactly what the same requests answer one at a time.
  */
final class Runner(val cfg: RunnerConfig) {
  import Runner._

  private val log = org.apache.log4j.Logger.getLogger("ermine.json.runner")

  // `Supply` is documented single-threaded and ids must be globally unique;
  // per-thread supplies draw from the synchronized global block allocator.
  private val supplies = new ThreadLocal[Supply] {
    override def initialValue: Supply = Supply.create
  }
  private implicit def supply: Supply = supplies.get
  // session chatter (load progress) must not reach the response or stdout
  private implicit val printer: Printer = Printer.ignore

  private implicit val env: SessionEnv =
    new SessionEnv(_typeCheck = Some(true), _useInterface = Some(false))

  /** The deferred relations' plans.  One per runner, thread-safe, and
    * UNAUTHENTICATED: a token is a bearer credential for the rows behind it,
    * so a multi-tenant deployment wants one runner per tenant. */
  val plans: MemoryPlanCache =
    new MemoryPlanCache(cfg.ttlMillis, cfg.maxTokens, cfg.clock, new java.security.SecureRandom)

  private val reports = new java.util.concurrent.ConcurrentHashMap[String, Report]
  /** The monitor every use of the session and of a `Runtime` is taken under.
    * PROCESS-WIDE (`Runner.evalLock`), not per runner: part of what it guards
    * -- the `DataConDecl` registry -- is a pair of static maps shared by every
    * session in the JVM, so two runners must exclude each other too. */
  private val evalLock = Runner.evalLock

  /** What `GET /health` reads.  DECLARED BEFORE `booted`, whose initialiser
    * calls `snapshot()`: a field initialiser further down would run later and
    * blank it again. */
  @volatile private var loadedSnapshot: Set[String] = Set()

  /** Refresh the snapshot.  Called under `evalLock`, so it never races a load. */
  private def snapshot(): Unit = loadedSnapshot = env.loadedModules.keySet

  private val booted: Option[String] = evalLock.synchronized {
    try {
      if (cfg.roots.nonEmpty) {
        val fs: List[String => Option[Session.SourceFile]] =
          cfg.roots.map(r => Session.SourceFile.filesystem(r) _)
        env.loadFile = Session.SourceFile.inOrder((fs :+ env.loadFile): _*)
      }
      Lib.preamble
      Session.loadModules(NodeModule :: cfg.preload)
      snapshot()
      None
    } catch {
      case Death(d, _)  => Some(d.toString)
      case NonFatal(e)  => Some(messageOf(e))
    }
  }

  /** Why the boot failed, if it did.  Every request answers 500 with this. */
  def bootFailure: Option[String] = booted

  /** The modules loaded so far (the preloaded ones plus every module a
    * request has asked for).  Read from a volatile snapshot rather than from
    * the session, so `GET /health` answers while a slow report holds the
    * evaluation lock -- a liveness probe that blocks on the thing it is
    * probing is worse than useless. */
  def loadedModules: Set[String] = loadedSnapshot


  // ---------------------------------------------------------------------
  // POST /report/<module>

  /** Render `module`'s report against a request body already parsed as JSON.
    * The document is appended to `out`; on a `Left`, `out` holds a prefix
    * that must be discarded. */
  def render(module: String, body: Json, out: Appendable): Either[RunError, WriteStats] =
    Request.parse(body).right.flatMap(req => render(module, req, out))

  /** The same from the request body's TEXT: argonaut's parser is recursive,
    * so a deeply nested body overflows the stack (J2a measured ~4,200 levels
    * on a default stack).  That is a 400, not a crash. */
  def renderText(module: String, body: String, out: Appendable): Either[RunError, WriteStats] =
    parseBody(body).right.flatMap(j => render(module, j, out))

  def render(module: String, req: Request, out: Appendable): Either[RunError, WriteStats] =
    report(module).right.flatMap { rep =>
      build(rep, req).right.flatMap { root =>
        val wcfg = WriteConfig(default = req.default, strategy = req.strategy,
                               threshold = req.threshold, clock = cfg.clock)
        write(Doc.document(root, cfg.settings), out, wcfg)
      }
    }

  // ---------------------------------------------------------------------
  // GET /data/<token>

  /** The deferred re-request: the inline object of the relation behind
    * `token`, or 404 when the token is unknown or has expired.  The rows are
    * re-scanned, so they are the same ROWS as the first response, not
    * necessarily in the same order (J3b). */
  def data(token: String, out: Appendable): Either[RunError, WriteStats] = bootFailed match {
    case Some(e) => Left(e)
    case None =>
      try cfg.run.run(Write.relation[DB](token, out, plans, cfg.clock)(cfg.scanner, Guard.db)) match {
        case None     => Left(NotFound("no such token, or it has expired"))
        case Some(st) => Right(st)
      } catch {
        case f: WriteFailure => Left(Failed("cannot write " + f.path + ": " + f.message, Some(f.path)))
        case NonFatal(e)     => Left(Failed(messageOf(e)))
      }
  }

  /** The request body as JSON, or why not.  Catches `StackOverflowError`
    * from argonaut's recursive parser (J2a). */
  def parseBody(text: String): Either[RunError, Json] =
    try Parse.parse(text).fold(m => Left(BadRequest("$", "the request body is not JSON: " + m)), j => Right(j))
    catch {
      case _: StackOverflowError =>
        Left(BadRequest("$", "the request body is nested too deeply to parse"))
      case NonFatal(e) => Left(BadRequest("$", "the request body is not JSON: " + messageOf(e)))
    }

  // ---------------------------------------------------------------------

  private def bootFailed: Option[RunError] =
    booted.map(why => Failed("the runner did not boot: " + why))

  /** The compiled report for `module`, looked up once and kept. */
  private def report(module: String): Either[RunError, Report] = bootFailed match {
    case Some(e) => Left(e)
    case None =>
      val hit = reports.get(module)
      if (hit ne null) Right(hit)
      else evalLock.synchronized {
        val again = reports.get(module)
        if (again ne null) Right(again)
        else compile(module).right.map { r => reports.put(module, r); r }
      }
  }

  /** Load the module, find the binding, split and check its type, compile
    * the parameter decoder.  Called under `evalLock`.
    *
    * A refusal is NOT cached: a 404 for a module the operator is about to
    * drop in, or a 400 for a signature they are about to correct, must not
    * outlive the fix.  Only a report that works is remembered. */
  private def compile(module: String): Either[RunError, Report] =
    if (!moduleNameOk(module))
      Left(NotFound("no module named " + module))
    else if (!env.loadedModules.contains(module) && env.loadFile(module).isEmpty)
      Left(NotFound("no module named " + module))
    else {
      val loadFailed =
        try { Session.loadModules(List(module)); None }
        catch {
          case Death(d, _) => Some(d.toString)
          case NonFatal(e) => Some(messageOf(e))
        }
      snapshot()
      loadFailed match {
        case Some(why) => Left(Failed("module " + module + " does not load: " + why))
        case None =>
          val g = Global(module, cfg.reportName)
          if (!env.termNames.contains(g))
            Left(NotFound("module " + module + " has no binding named " + cfg.reportName))
          else {
            // THE BARE NAME, never an ascribed expression: on the 2.11 branch
            // `Session.eval` runs the fused `phrase(term)` without Console's
            // `fixCons`, so a type constructor inside a TERM is not resolved
            // through `Type.conMap` and infers a polymorphic scheme (P1's
            // finding).  A bare identifier evaluates the same on both.  This
            // is the runner's ONLY use of the evaluator, and it parses no type
            // expression at all -- there is no `NewPipeline.replType` here for
            // the 2.11 port to replace with `SchemaParse.typeExpr`.
            val evaluated =
              try Right(Session.eval(cfg.reportName, Map(Builtin -> everything, module -> everything)))
              catch {
                case Death(d, _) => Left(Failed("cannot evaluate " + module + "." + cfg.reportName + ": " + d.toString))
                case NonFatal(e) => Left(Failed("cannot evaluate " + module + "." + cfg.reportName + ": " + messageOf(e)))
              }
            evaluated.right.flatMap { case (ty, fn) =>
              Decode.reportSignature(ty).left.map(e => signatureRefusal(module, e.message)).right.flatMap {
                case (paramTy, resultTy) =>
                  if (!isNode(resultTy))
                    Left(signatureRefusal(module, "a report returns " + NodeModule + ".Node, not " +
                                                  Schema.renderType(resultTy)))
                  else Decode.compile(paramTy).left.map { e =>
                    BadRequest("$." + Request.Params,
                               "the parameter type " + Schema.renderType(paramTy) +
                               " of " + module + "." + cfg.reportName + " has no JSON reading: " + e.report)
                  }.right.map(d => new Report(module, paramTy, resultTy, d, fn))
              }
            }
          }
      }
    }

  private def signatureRefusal(module: String, why: String): RunError =
    BadRequest("$", module + "." + cfg.reportName + " is not a report: " + why)

  /** Decode the parameters, apply the report and walk the value into a
    * `Doc`.  All of it under `evalLock`; the relations inside the `Doc` are
    * plans, not rows, so the scan happens outside. */
  private def build(rep: Report, req: Request): Either[RunError, Doc] =
    evalLock.synchronized {
      rep.decoder(req.params) match {
        case Left(e) => Left(BadRequest("$." + Request.Params + e.path.substring(1), e.message))
        case Right(v) =>
          try Doc.fromRuntime(Runtime.swhnf(rep.fn).apply1(v)) match {
            // a bottom inside the value (an Ermine `error`, a failed foreign
            // call) reaches the walker as an encode error at its path, so
            // "the report threw" and "the report built something unwritable"
            // are the same 500 here
            case Left(e)  => Left(Failed(rep.module + "." + cfg.reportName +
                                         " produced a document that cannot be encoded: " + e.message, Some(e.path)))
            case Right(d) => Right(d)
          } catch {
            case Death(d, _) => Left(Failed(rep.module + "." + cfg.reportName + " failed: " + d.toString))
            case NonFatal(e) => Left(Failed(rep.module + "." + cfg.reportName + " failed: " + messageOf(e)))
          }
      }
    }

  private def write(d: Doc, out: Appendable, wcfg: WriteConfig): Either[RunError, WriteStats] =
    try Right(cfg.run.run(Write.doc[DB](d, out, wcfg, plans)(cfg.scanner, Guard.db)))
    catch {
      case f: WriteFailure => Left(Failed("cannot write " + f.path + ": " + f.message, Some(f.path)))
      case NonFatal(e)     => Left(Failed(messageOf(e)))
    }

  private def isNode(t: Type): Boolean = unfurl(t, List()) match {
    case (Type.Con(_, Global(NodeModule, "Node", _), _, _), Nil) => true
    case _                                                       => false
  }

  private final class Report(val module: String,
                             val paramTy: Type,
                             val resultTy: Type,
                             val decoder: Decode.Decoder,
                             val fn: Runtime)
}

object Runner {
  /** The evaluation monitor, ONE PER PROCESS.  A `Runner` has its own
    * `SessionEnv`, but `DataConDecl`'s two registries are static
    * (`ermine/DataConDecl.scala`), written by `Session.loadModules` and
    * last-writer-wins per `Global`, and the encoder and the decoder read them
    * -- so two runners loading two modules that declare the same `data` type
    * would overwrite each other's constructor field lists.  `Supply`'s
    * allocator and `Runtime.Thunk`'s non-volatile `state` are the other two
    * reasons, and they are equally indifferent to which runner is asking.
    * One lock, therefore, not one per instance: a second runner (a second
    * tenant, or a test fixture) is serialised against the first. */
  private[json] val evalLock = new Object

  private[json] val Builtin    = "Builtin"
  private[json] val NodeModule = "Layout.Doc"

  private[json] val everything: (Option[String], List[Explicit[Global]], Boolean) = (None, List(), false)

  /** A module name is dot-separated identifiers.  It reaches
    * `SourceFile.filesystem`, which splits it on `.` and joins the pieces
    * with the path separator, so anything else -- a slash, a `..`, an empty
    * piece -- is refused here rather than turned into a path. */
  def moduleNameOk(m: String): Boolean = {
    val parts = m.split('.')
    m.nonEmpty && !m.endsWith(".") && parts.length > 0 && parts.forall { p =>
      p.nonEmpty && Character.isLetter(p.charAt(0)) && {
        var i = 1
        var ok = true
        while (i < p.length) {
          val c = p.charAt(i)
          if (!(Character.isLetterOrDigit(c) || c == '_' || c == '\'')) ok = false
          i += 1
        }
        ok
      }
    }
  }

  private[json] def unfurl(t: Type, args: List[Type]): (Type, List[Type]) = t match {
    case AppT(f, a)   => unfurl(f, a :: args)
    case Memory(_, u) => unfurl(u, args)
    case other        => (other, args)
  }

  private[json] def messageOf(e: Throwable): String =
    Option(e.getMessage).getOrElse(e.toString)
}
