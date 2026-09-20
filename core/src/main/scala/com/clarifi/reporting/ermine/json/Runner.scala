package com.clarifi.reporting.ermine.json

import argonaut.{ Json, Parse }
import com.clarifi.reporting.{ Record, Run, SortOrder }
import com.clarifi.reporting.backends.{ DB, Runners, Scanners }
import com.clarifi.reporting.relational.{ ClosedExt, SMEnv, Scanner }
import com.clarifi.reporting.ermine.{ AppT, Data, Global, InfixR, Memory, Prim, Runtime, Type }
import com.clarifi.reporting.ermine.session.{ Lib, Printer, Session, SessionEnv }
import com.clarifi.reporting.ermine.syntax.Explicit
import scala.collection.immutable.List
import scala.util.control.{ NonFatal, NoStackTrace }
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
  * parameter the report's type refuses, a report whose type is neither
  * `Params -> Layout.Doc.Node` nor `Params -> Layout.Fetch.Fetch Layout.Doc.Node`. */
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
  *   request JSON -> Decode -> report : Params -> Fetch Node
  *                          -> first Eval (under evalLock, no connection yet)
  *                          -> Interp.run inside ONE Run[DB].run:
  *                                Call  (rows for the report)   -> Eval -> ...
  *                                Emit / Splice / Token          -> one JSON object
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
  * result must be `Layout.Fetch.Fetch Layout.Doc.Node` or, as sugar for
  * `done` of it, `Layout.Doc.Node` (aliases expanded); `Decode.compile`
  * turns the parameter type into a `Decoder`, which needs no session
  * afterwards.  The four are cached per module: a request pays for a type
  * walk only the first time.
  *
  * PER REQUEST, ONE PATH (J3g), ONE LOOP (J3h).  Decode `$.params`, then
  * take the FIRST EVALUATION STEP -- apply the report and force the result
  * -- under `evalLock` and before any connection is opened.  It answers a
  * list of `Step`s: a `Params -> Node` report, and a fetching one that never
  * scans, answer the document's `Emit`/`Splice`/`Token` steps; a
  * `Scan order plan k` answers one `Call`, whose rows go to `k` as an Ermine
  * list and whose continuation is the next evaluation step.  `Interp.run`
  * consumes the stream inside ONE `Run[DB].run`, each evaluation step taking
  * `evalLock` on its own and every scan running OUTSIDE it, so a slow query
  * blocks no other report.  `Strategy.Buffered` means the caller gets the
  * text only when the run returns: `out` holds a prefix after a failure and
  * must be discarded (the HTTP server keeps a `StringBuilder` per request
  * and sends it only on `Right`).  A relation that survives into the final
  * Node is still a plan and is delivered as the request asks; only the rows
  * a `Scan` asked for are read early, and a report that fails to evaluate
  * opens no connection at all.
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

  /** The compiled reports, keyed by the PAIR `(module, binding)` (WP-4).  A
    * module may declare several report-typed bindings -- `report`,
    * `emptyReport`, `wideReport` -- and the editor's preview picks one by
    * TYPE, not by name (JSON-WIDGET-PLAYGROUND §3.2); `cfg.reportName` is
    * only the default the HTTP route `POST /report/<Module>` supplies.
    *
    * `invalidate` evicts from here by module. */
  private val reports = new java.util.concurrent.ConcurrentHashMap[(String, String), Report]
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

  /** THIS SESSION'S post-`Lib.preamble`, pre-load env (WP-4), the guard
    * `Session.scrub` takes as its `builtins`: `Lib` installs names under the
    * module they belong to -- `asOp` and class `AsOp` are
    * `Global("Relation.Op", ...)`, declared in Scala and merely COMMENTED in
    * `Relation/Op.e` -- so a scrub by module name alone would delete them
    * and re-reading the file could not put them back.  `Session.scrub` says
    * a WRONG snapshot fails silently, so it is taken here and nowhere else.
    *
    * DECLARED BEFORE `booted`, whose initialiser assigns it: a field
    * initialiser further down would run later and blank it again.  `null`
    * only when the boot died before the preamble returned, which is also a
    * `booted` failure, and `invalidate` answers the empty set either way. */
  @volatile private var builtins: SessionEnv = null

  private val booted: Option[String] = evalLock.synchronized {
    try {
      if (cfg.roots.nonEmpty) {
        val fs: List[String => Option[Session.SourceFile]] =
          cfg.roots.map(r => Session.SourceFile.filesystem(r) _)
        env.loadFile = Session.SourceFile.inOrder((fs :+ env.loadFile): _*)
      }
      Lib.preamble
      builtins = env.copy
      Session.loadModules(NodeModule :: FetchModule :: cfg.preload)
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

  /** Render `module`'s DEFAULT report -- the binding `cfg.reportName` names
    * -- against a request body already parsed as JSON.  The document is
    * appended to `out`; on a `Left`, `out` holds a prefix that must be
    * discarded.
    *
    * This is the HTTP route's entry point (`Server.scala`'s
    * `POST /report/<Module>`); the preview passes a binding explicitly. */
  def render(module: String, body: Json, out: Appendable): Either[RunError, WriteStats] =
    render(module, cfg.reportName, body, out)

  /** Render one `(module, binding)` pair (WP-4). */
  def render(module: String, binding: String, body: Json, out: Appendable): Either[RunError, WriteStats] =
    Request.parse(body).right.flatMap(req => render(module, binding, req, out))

  /** The same from the request body's TEXT: argonaut's parser is recursive,
    * so a deeply nested body overflows the stack (J2a measured ~4,200 levels
    * on a default stack).  That is a 400, not a crash. */
  def renderText(module: String, body: String, out: Appendable): Either[RunError, WriteStats] =
    renderText(module, cfg.reportName, body, out)

  /** The same, for one `(module, binding)` pair. */
  def renderText(module: String, binding: String, body: String, out: Appendable): Either[RunError, WriteStats] =
    parseBody(body).right.flatMap(j => render(module, binding, j, out))

  /** ONE PATH (J3g), ONE LOOP (J3h).  A report is `Params -> Fetch Node`; a
    * report typed `Params -> Node` is read as `done` of its value, so the
    * difference is in the FIRST STEP'S VALUE, not in the report's type.
    *
    * Decode, then take that first step -- apply the report to its parameters
    * and force the result -- under `evalLock` and BEFORE `cfg.run.run` opens a
    * connection.  It answers the STEPS that follow: the document's
    * `Emit`/`Splice`/`Token` when the report is finished, or one `Call` when
    * it asks for rows.  `Interp.run` then consumes them inside one
    * `cfg.run.run`, whichever they are, so the scans of a `Fetch` and the
    * relations of the document are read, logged and counted by the same
    * loop.  A report whose evaluation fails therefore costs no connection,
    * whether it scans or not. */
  def render(module: String, req: Request, out: Appendable): Either[RunError, WriteStats] =
    render(module, cfg.reportName, req, out)

  /** The same, for one `(module, binding)` pair (WP-4). */
  def render(module: String, binding: String, req: Request, out: Appendable): Either[RunError, WriteStats] =
    report(module, binding).right.flatMap { rep =>
      val wcfg = WriteConfig(default = req.default, strategy = req.strategy,
                             threshold = req.threshold, clock = cfg.clock)
      decode(rep, req).right.flatMap { v =>
        evalStep(rep, () => Runtime.swhnf(rep.fn).apply1(v), 1, wcfg).right.flatMap(ss => drive(ss, out, wcfg))
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
  // WP-4: what the editor's preview session asks of a runner besides a
  // render -- the parameter schema of one binding, and invalidation.

  /** The JSON Schema of `(module, binding)`'s PARAMETER type
    * (JSON-WIDGET-PLAYGROUND §6): the report is compiled first -- through
    * the same cache a render uses, so the schema costs a load only when the
    * render would have -- and the schema is then exported from the very
    * `paramTy` the decoder was compiled from.  The params file's squiggles
    * and the 400s a bad value earns therefore cannot disagree.
    *
    * ONE `evalLock` SECTION over BOTH halves (review S2), not one per half:
    * the export reads the session's `cons`, and between a compile and an
    * export that took the lock separately an `invalidate` could scrub the
    * very module whose type is about to be walked, so a schema request that
    * raced a save would 500 for a reason the client cannot act on.  A Java
    * monitor is reentrant and `report` takes this same monitor, so calling
    * it from inside costs nothing but re-entry. */
  def paramSchema(module: String, binding: String): Either[RunError, Json] =
    evalLock.synchronized {
      report(module, binding).right.flatMap { rep =>
        Schema.exportType(rep.paramTy, module)(env).left.map { e =>
          Failed("the parameter type " + Schema.renderType(rep.paramTy) + " of " + module + "." +
                 binding + " has no JSON schema: " + e.message, Some(e.path))
        }
      }
    }

  /** Forget the modules `paths` names, and everything loaded that imports
    * one of them: the answer is the module names invalidated, which
    * `JSON-WIDGET-PLAYGROUND` §3 step 5 sends on to the editor so it can
    * re-render the reports that moved.
    *
    * THE ALGORITHM, in order:
    *  1. `paths` -> modules through THIS session's own `loadedFiles`
    *     (`Session.loadedByPath`: where each module was read from), plus
    *     `Session.moduleUnder(cfg.roots, p)` for a path no load ever read --
    *     the file deleted from the first root, served from the second, and
    *     then restored, which arrives as a creation of a path nobody loaded
    *     and must still invalidate `A.B`.  That second rule is filtered by
    *     `loadedModules`, so a path naming a module this session never
    *     loaded contributes nothing;
    *  2. nothing named -> the empty set, and NOTHING is touched;
    *  3. otherwise the closure through `Session.dependentsOf`: the modules
    *     themselves plus every loaded module that imports one of them,
    *     transitively;
    *  4. `Session.scrub` of that closure against this runner's own
    *     `builtins` snapshot -- the names are out of the env and the
    *     modules out of `loadedModules`;
    *  5. EVICTION.  Every `reports` entry whose MODULE is in the closure
    *     goes.  That covers both halves of what a stale cached report is: a
    *     report of a changed module, and a report of an unchanged module
    *     that IMPORTS a changed one -- the second is in the closure exactly
    *     because `dependentsOf` collects importers, so one test on the key's
    *     module is the whole rule.  (A cached `Report` holds the evaluated
    *     closure of its binding, so leaving one behind would keep rendering
    *     the old widget after its module was scrubbed.)
    *  6. refresh the `/health` snapshot and answer the closure.
    *
    * NO EAGER RELOAD: the next `render`/`paramSchema` for an evicted pair
    * calls `compile`, which loads the module from disk on demand -- and
    * answers 404 if the file is gone, which is what a deletion should do.
    *
    * `plans` IS DELIBERATELY LEFT ALONE.  A token is a bearer credential for
    * the rows of one relation already delivered, not a cache of the module:
    * the route that mints tokens is the HTTP server's, which never calls
    * this, and the preview mints none (every preview render is
    * `Delivery.Inline`, buffered, no threshold -- JSON-WIDGET-PLAYGROUND
    * §2.4).  So a token minted before an invalidate goes on resolving
    * against the plan it was minted for until its TTL expires, which is what
    * `GET /data/<token>` promises, and clearing the cache here would turn a
    * save in the editor into a 404 for an unrelated client's re-request.
    *
    * Under `evalLock`, like every other use of this session: `invalidate`
    * mutates the env, and a render on another thread must not be walking it.
    *
    * A boot that failed invalidates nothing: every request answers 500 from
    * `bootFailed` regardless, and there is no `builtins` snapshot to scrub
    * against.
    *
    * The import edges come from the process-global `Session.depCache`
    * (`dependentsOf` reads it): a module whose entry is missing contributes
    * no edge and is not collected as an importer.  Nothing in the product
    * ever clears that cache -- four TEST suites do, which is why the
    * properties that pin this hold `ErmineFixture.literalLock`. */
  def invalidate(paths: Set[java.nio.file.Path]): Set[String] = evalLock.synchronized {
    if (booted.isDefined || (builtins eq null)) Set()
    else {
      val byPath = Session.loadedByPath(env)
      def modulesOf(p: java.nio.file.Path): Set[String] = {
        val n = Session.normalize(p)
        byPath.get(n).toSet ++ Session.moduleUnder(cfg.roots, n).filter(env.loadedModules.contains)
      }
      val direct = paths.flatMap(modulesOf)
      if (direct.isEmpty) Set()
      else {
        val dirty = Session.dependentsOf(env, direct)
        Session.scrub(env, builtins, dirty)
        val keys = reports.keySet.iterator
        while (keys.hasNext) if (dirty(keys.next()._1)) keys.remove()
        snapshot()
        log.info("invalidate: " + dirty.toList.sorted.mkString(", "))
        dirty
      }
    }
  }

  // ---------------------------------------------------------------------

  private def bootFailed: Option[RunError] =
    booted.map(why => Failed("the runner did not boot: " + why))

  /** The compiled report for one `(module, binding)` pair, looked up once
    * and kept.  `invalidate` is what takes an entry back out. */
  private def report(module: String, binding: String): Either[RunError, Report] = bootFailed match {
    case Some(e) => Left(e)
    case None =>
      val key = (module, binding)
      val hit = reports.get(key)
      if (hit ne null) Right(hit)
      else evalLock.synchronized {
        val again = reports.get(key)
        if (again ne null) Right(again)
        else compile(module, binding).right.map { r => reports.put(key, r); r }
      }
  }

  /** Load the module, find the binding, split and check its type, compile
    * the parameter decoder.  Called under `evalLock`.
    *
    * A refusal is NOT cached: a 404 for a module the operator is about to
    * drop in, or a 400 for a signature they are about to correct, must not
    * outlive the fix.  Only a report that works is remembered. */
  private def compile(module: String, binding: String): Either[RunError, Report] =
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
          val g = Global(module, binding)
          if (!env.termNames.contains(g))
            Left(NotFound("module " + module + " has no binding named " + binding))
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
              try Right(Session.eval(binding, Map(Builtin -> everything, module -> everything)))
              catch {
                case Death(d, _) => Left(Failed("cannot evaluate " + module + "." + binding + ": " + d.toString))
                case NonFatal(e) => Left(Failed("cannot evaluate " + module + "." + binding + ": " + messageOf(e)))
              }
            evaluated.right.flatMap { case (ty, fn) =>
              Decode.reportSignature(ty).left.map(e => signatureRefusal(module, binding, e.message)).right.flatMap {
                case (paramTy, resultTy) =>
                  resultKind(resultTy) match {
                    case None =>
                      Left(signatureRefusal(module, binding,
                                            "a report returns " + NodeModule + ".Node or " +
                                            FetchModule + ".Fetch " + NodeModule + ".Node, not " +
                                            Schema.renderType(resultTy)))
                    case Some(_) =>
                      Decode.compile(paramTy).left.map { e =>
                        BadRequest("$." + Request.Params,
                                   "the parameter type " + Schema.renderType(paramTy) +
                                   " of " + module + "." + binding + " has no JSON reading: " + e.report)
                      }.right.map(d => new Report(module, binding, paramTy, resultTy, d, fn))
                  }
              }
            }
          }
      }
    }

  private def signatureRefusal(module: String, binding: String, why: String): RunError =
    BadRequest("$", module + "." + binding + " is not a report: " + why)

  private def decode(rep: Report, req: Request): Either[RunError, Runtime] =
    rep.decoder(req.params).left.map(e => BadRequest("$." + Request.Params + e.path.substring(1), e.message))

  /** Run a step stream on ONE connection (J3h): the pure path's document
    * steps, or the `Call` the first evaluation step asked for and everything
    * it leads to.  Every failure a driver run can raise arrives here -- a
    * scan or a row through `WriteFailure`, the Ermine side through `Abort`,
    * which carries the `RunError` the evaluation step made. */
  private def drive(steps: List[Step], out: Appendable, wcfg: WriteConfig): Either[RunError, WriteStats] =
    try Right(cfg.run.run(Interp.run[DB](steps, out, wcfg, plans)(cfg.scanner, Guard.db)))
    catch {
      case a: Abort        => Left(a.error)
      case f: WriteFailure => Left(Failed("cannot write " + f.path + ": " + f.message, Some(f.path)))
      case NonFatal(e)     => Left(Failed(messageOf(e)))
    }

  // ---------------------------------------------------------------------
  // the report as steps: Layout.Fetch.Fetch Node

  /** One evaluation step as the STEPS that follow it: the document's when the
    * report is finished (`Done`, or a bare `Node`), or the one `Call` it asks
    * for (`Scan`), whose continuation is this same function on the rows.  `n`
    * is the scan's 1-based position in the report -- what `$.fetch[n]` counts
    * -- so the numbering is the report's and the driver only carries the path.
    *
    * WHAT THE LOCK COVERS (R1).  `evaluate` holds `evalLock` for the forcing
    * and the WALK (`Doc.fromRuntime` reads the runtime, so it must); turning
    * the walked `Doc` into the text runs of `Write.steps` reads nothing of the
    * session and happens HERE, outside the lock, as it did before J3h.  It
    * matters for a fetching report that folds its scanned rows into pure
    * widgets (`FetchRunning`, `FetchTopN`): serialising those rows under a
    * PROCESS-WIDE lock would queue every other request's evaluation behind
    * this one's printing.
    *
    * The first step is taken by `render`, outside any connection, and its
    * failure is a `Left`; every later step is taken INSIDE the driver, where
    * a `Left` cannot be returned, so `stepping` throws it as an `Abort`. */
  private def evalStep(rep: Report, next: () => Runtime, n: Int, wcfg: WriteConfig): Either[RunError, List[Step]] =
    evaluate(rep, next, n, wcfg).right.map {
      case Left(d)      => Write.steps(Doc.document(d, cfg.settings), wcfg)
      case Right(steps) => steps
    }

  /** The part of a step that must hold `evalLock`: force the value, and walk
    * it when the report is finished (`Left` a `Doc`) or read the scan it asks
    * for (`Right` one `Call`).
    *
    * A value that is neither `Done` nor `Scan` IS the Node: that is how a
    * report typed `Params -> Node` is read as `done` of its value without a
    * second path (J3g).  `resultKind` has already refused anything else, so
    * the walker is not being asked to guess. */
  private def evaluate(rep: Report, next: () => Runtime, n: Int, wcfg: WriteConfig)
      : Either[RunError, Either[Doc, List[Step]]] =
    evalLock.synchronized {
      def failed(why: String): RunError = Failed(rep.module + "." + rep.binding + " failed: " + why)
      def document(node: Runtime): Either[RunError, Either[Doc, List[Step]]] =
        Doc.fromRuntime(node) match {
          case Left(e)  => Left(Failed(rep.module + "." + rep.binding +
                                       " produced a document that cannot be encoded: " + e.message, Some(e.path)))
          case Right(d) => Right(Left(d))
        }
      try Runtime.swhnf(next()) match {
        case Data(DoneCon, Array(node)) => document(node)
        case Data(ScanCon, Array(srt, rel, k)) =>
          val order = Runtime.swhnf(srt).extract[List[(String, SortOrder)]]
          Runtime.swhnf(rel) match {
            case Prim(c: ClosedExt) =>
              Right(Right(List(Step.Call(order, c.out, fetchPath(n),
                                         rows => stepping(rep, () => k.apply1(rowsRuntime(rows)), n + 1, wcfg)))))
            case other              => Left(failed("scan " + n + " is not a relation: " + other))
          }
        // not a Fetch constructor: the report is a `Params -> Node`, and its
        // value is the document
        case other => document(other)
      } catch {
        case Death(d, _) => Left(failed(d.toString))
        case NonFatal(e) => Left(failed(messageOf(e)))
      }
    }

  /** `evalStep` inside the driver: a failure leaves as an `Abort`, which
    * `drive` unwraps into the same `RunError` the first step would have
    * returned. */
  private def stepping(rep: Report, next: () => Runtime, n: Int, wcfg: WriteConfig): List[Step] =
    evalStep(rep, next, n, wcfg) match {
      case Left(e)      => throw new Abort(e)
      case Right(steps) => steps
    }

  /** The rows as the Ermine `List Record#` a `Scan` continuation takes:
    * what `Native.List.fromList#` builds from the writer's
    * `scanRelationDMTL` argument, cell by cell through `fromPrimExpr`. */
  private def rowsRuntime(rows: List[Record]): Runtime =
    rows.foldRight(Lib.Nil: Runtime) { (r, acc) =>
      Data(ConsCon, Array(Prim(r.map { case (c, v) => (c, Runtime.fromPrimExpr(v)) }), acc))
    }

  private final class Report(val module: String,
                             val binding: String,
                             val paramTy: Type,
                             val resultTy: Type,
                             val decoder: Decode.Decoder,
                             val fn: Runtime)
}

/** A `RunError` on its way out of `Interp.run`.  The driver knows steps,
  * an `Appendable` and `WriteFailure`; a failure of the ERMINE side (a
  * report or a continuation that throws, a document that cannot be encoded)
  * is none of those, so it travels through the driver as this and `drive`
  * unwraps it.  J3h: `ScanFailed` is gone -- a fetch scan that throws is a
  * `WriteFailure` at `$.fetch[n]`, like any other relation. */
private[json] final class Abort(val error: RunError)
    extends RuntimeException(error.message) with NoStackTrace

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

  private[json] val Builtin     = "Builtin"
  private[json] val NodeModule  = "Layout.Doc"
  private[json] val FetchModule = "Layout.Fetch"
  /** The constructors of `Layout.Fetch.Fetch`, as the evaluator names them. */
  private[json] val DoneCon: Global = Global(FetchModule, "Done")
  private[json] val ScanCon: Global = Global(FetchModule, "Scan")
  private[json] val ConsCon: Global = Global(Builtin, "::", InfixR(5))

  private[json] val everything: (Option[String], List[Explicit[Global]], Boolean) = (None, List(), false)

  /** Where the n-th scan of a report is, for its `RelationStats`, its log
    * line and any failure: `$.fetch[n]`, 1-based, in the order the report
    * asked for them.  It is not a path into the document (the rows of a
    * fetch scan are not in the document); it is the path into the REPORT the
    * `Delivery.Fetched` entries of `WriteStats.relations` are named by. */
  private[json] def fetchPath(n: Int): String = "$.fetch[" + n + "]"

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

  private def isNode(t: Type): Boolean = unfurl(t, List()) match {
    case (Type.Con(_, Global(NodeModule, "Node", _), _, _), Nil) => true
    case _                                                       => false
  }

  /** `Some(false)` for `Node`, `Some(true)` for `Fetch Node`, `None` for
    * anything else -- the test a binding's RESULT type has to pass to be a
    * report at all.
    *
    * PUBLIC, and on the companion rather than on an instance, since WP-4:
    * the language server applies it to the types its document index already
    * holds, to list a file's report-typed bindings for the preview picker
    * (JSON-WIDGET-PLAYGROUND §3.2) -- a lookup on the dispatch thread, with
    * no `Runner` in reach and nothing evaluated.  `compile` applies the same
    * function to the type the evaluator inferred, so the picker's list and
    * the runner's 400 cannot disagree about what a report is. */
  def resultKind(t: Type): Option[Boolean] = unfurl(t, List()) match {
    case (Type.Con(_, Global(NodeModule, "Node", _), _, _), Nil)                    => Some(false)
    case (Type.Con(_, Global(FetchModule, "Fetch", _), _, _), List(a)) if isNode(a) => Some(true)
    case _                                                                          => None
  }

  private[json] def unfurl(t: Type, args: List[Type]): (Type, List[Type]) = t match {
    case AppT(f, a)   => unfurl(f, a :: args)
    case Memory(_, u) => unfurl(u, args)
    case other        => (other, args)
  }

  private[json] def messageOf(e: Throwable): String =
    Option(e.getMessage).getOrElse(e.toString)
}
