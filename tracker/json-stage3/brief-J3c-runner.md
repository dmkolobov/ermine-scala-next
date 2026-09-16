# J3c: the document runner (params in, one JSON document out, over HTTP)

Branch `json-runner`, worktree `~/research/ermine/ermine-scala-wt-json-runner`, off
`json-encode` AFTER J2a (decoder) and J3b (writer) have landed there. Budget 5 h. Read
`brief-J-common.md` first, then `tracker/json-stage3/report-J2a.md` and `report-J3b.md`
(the as-built APIs you call; they override anything below that disagrees).

## Why

Design note §3.3 (params), §3.4a (request body, delivery, deferral endpoint), §5 Stage 3
row. The runner is new code, not ermine-writers: request JSON -> `Decode` -> apply
`report : Params -> Node` -> `Doc.fromRuntime` -> `Write.doc` inside `Run.run` on one
connection -> one JSON object.

Read: the two reports above; `json/Decode.scala`, `json/Doc.scala`, `json/Write.scala`,
`json/PlanCache.scala`, `modules/Layout/Doc.e`; `json/SchemaMain.scala` (how a CLI boots a
session: `Lib.preamble`, `Session.loadModules`, `SessionEnv` flags, a stderr `Printer`);
`session/Session.scala` (`eval`, `loadModules`, `termNames` and how a top-level binding's
TYPE is found -- `Session.eval` returns `(Type, Runtime)`); how module source roots are
searched (find the property/flag, e.g. how `bin/ermine` finds a user module by name);
`backends/Backends.scala` (`Scanners`, `Runners`), `backends/DB.scala`, `Run.scala`.

## Build

1. `json/Runner.scala`: `final class Runner(cfg: RunnerConfig)` where the config names module
   roots, the modules to preload, the report binding name (default `report`), a
   `Run[DB]` + `Scanner[DB]` (from a dialect name + JDBC URL: sqlite, mssql, mysql, postgres,
   vertica -- only what `Backends.scala` offers), `settings` JSON, plan-cache TTL/size.
   - `Runner.render(module: String, body: argonaut.Json, out: Appendable): Either[RunError, WriteStats]`:
     parse the request (`params`, `data.default|strategy|threshold`, refusing unknown `data`
     keys and `strategy: "streamed"` in v1), look up `<module>.<report>`, split its type with
     `Decode.reportSignature`, check the result type is `Layout.Doc.Node` (aliases expanded),
     decode params (error paths prefixed `$.params`), apply, force, `Doc.fromRuntime`,
     `run.run(Write.doc[DB](...))`.
   - `RunError` = `BadRequest(path, message)` | `NotFound(message)` | `Failed(message)` with
     the HTTP status and a JSON body `{"error":{"path":..,"message":..}}` for each.
   - `Runner.data(token: String, out): Either[RunError, WriteStats]` for the deferred
     re-request.
   - Boot once; decide and DOCUMENT the concurrency model (is evaluating two reports at
     once in one `SessionEnv` safe? Thunk memoisation, the process-wide registry, module
     loading). If unsure, serialise evaluation behind a lock and keep scanning/writing
     concurrent only where proven safe. A property below tests whatever you choose.
2. `json/Server.scala` + `json/ServeMain.scala` + `bin/ermine-serve`: the JDK's
   `com.sun.net.httpserver.HttpServer` (no new dependencies): `POST /report/<Module.Name>`
   (body: the request object; response `application/json; charset=utf-8`, the document),
   `GET /data/<token>` (the inline object), `GET /health`. Buffered => the response is
   written only after `Write.doc` succeeds, with a `Content-Length`. Errors map to 400 /
   404 / 405 / 413 (a configurable body size cap) / 500 with the JSON error body. Log one
   INFO line per request (module, status, ms, bytes) beside J3b's per-relation lines.
   CLI flags: `--root DIR` (repeatable), `--preload Module` (repeatable), `--db URL`,
   `--dialect NAME`, `--port N` (0 = ephemeral, print the bound port on stdout),
   `--report-name NAME`, `--ttl SECONDS`, `--settings JSON`.
3. An example report under `core/src/test/resources/doc/` (NOT `core/examples/`): a small
   params `data` with named fields (a date range, a `Maybe` filter, an enum), a relation
   built from literal rows filtered by the params, one bare relation, one `Deferred`, laid
   out with `VFlow`/`Grid`. `README` lines in the plan showing a curl session against it
   with sqlite in-memory.

## Properties (random declarations and values)

- (a) End to end, in process: for random `Params` types and values (`TestSchema.shape`,
  closed and monomorphic) and a GENERATED report module whose `report` echoes the params
  into widget props and includes random literal relations (bare/Inline/Deferred), a random
  request (`data` config) renders a document that (i) parses, (ii) whose props equal
  `Encode.toArgonaut` of the params, (iii) whose relation objects follow the delivery rules
  and carry the literal rows, (iv) whose deferred tokens resolve through `Runner.data` to
  the inline object.
- (b) Errors: random mutations of the params JSON give 400 with a path under `$.params`;
  an unknown module/binding 404; a report of the wrong type (not `P -> Node`, polymorphic
  `P`, open row) 400 naming the reason; a report that throws 500; expired token 404 (drive
  the plan cache's clock).
- (c) Over HTTP: start the server on an ephemeral port inside the test, send the SAME random
  requests as (a) through `java.net.HttpURLConnection`, and require byte-identical bodies to
  the in-process render (modulo tokens/expiry: compare after replacing them) and the right
  status codes.
- (d) Concurrency: N random requests fired concurrently produce the same bodies (modulo
  tokens) as the same requests run serially.
- (e) One connection per request: count connections through a wrapping `Run` -- one per
  `POST /report` however many relations, one per `GET /data`.

## Also

- Log per-relation row and byte counts (J3b's lines) and per-request lines; add the curl
  walkthrough and "§3.7d Stage 3 runner as built" to the design note; tick J3c in the plan.
- Do not edit ermine-writers. Do not add dependencies to build.sbt.
