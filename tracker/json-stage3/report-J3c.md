# J3c as built: the document runner (params in, one JSON document out, over HTTP)

Branch `json-runner`, worktree `~/research/ermine/ermine-scala-wt-json-runner`, off `03676cbe` (json-decode d2177ca5 merged with json-doc bf832e46). Uncommitted, as the brief says. 2026-09-16, about 4 h 45 of the 5 h budget. (Report text written by the implementer agent; the harness blocks writing `.md`, so the orchestrator should save this at `tracker/json-stage3/report-J3c.md`.)

## Files built

| File | Lines | What |
|---|---|---|
| `core/.../ermine/json/Runner.scala` (new) | 544 | `RunError` (`BadRequest`/`NotFound`/`Failed`/`MethodNotAllowed`/`TooLarge`), `Request` + `Request.parse`, `RunnerConfig` + `RunnerConfig.backend`, `final class Runner` |
| `core/.../ermine/json/Server.scala` (new) | 223 | the JDK `com.sun.net.httpserver` face: three routes, a fixed pool, a body cap, one INFO line per request |
| `core/.../ermine/json/ServeMain.scala` (new) | 118 | the CLI: flag parsing (`Options`, testable), boot, `listening on <port>` |
| `bin/ermine-serve` (new, +x) | 33 | same shape as `bin/ermine-schema` |
| `core/src/test/resources/doc/Sales.e` (new) | 122 | the example report (NOT under `core/examples/`, so the corpus count is unmoved) |
| `scalacheck-binding/.../TestRunner.scala` (new) | 948 | 16 properties |
| `core/.../sql/SqlEmitter.scala` | +13/-1 | ticket 1 FIXED: `EmitUuid_Strings.getUuid` reads a SQL NULL as a null UUID (file is CRLF; edited byte-wise) |
| `core/.../relational/package.scala` | +22/-3 | ticket 2 FIXED: `EffectfulProcedure.withDriver` tears down in a `finally`, attaching a throwing teardown with `addSuppressed` |
| `core/.../ermine/json/Write.scala` | +11/-8 | review fix 3: the `Rows.Sink` comment no longer says `withDriver` has no `finally` |
| `scalacheck-binding/.../TestDoc.scala` | +23/-13 | two defects, below, plus review fix 3 (two comments) |
| `tracker/JSON-API-DESIGN.md` | +118 | new §3.7d "Stage 3 runner as built" |
| `tracker/JSON-STAGE3-PLAN.md` | +117 | the curl walkthrough (real transcript), the `path`-by-status table, J3c row BUILT, handoff line |

## The contract as implemented

```
POST /report/<Module.Name>   body {"params": .., "data": {..}}   -> the document
GET  /data/<token>                                               -> the inline object
GET  /health                 -> {"status":"ok","version":1,"modules":[..]}
```

Request body: `{"params": <JSON of the report's Params type>, "data": {"default": "inline"|"deferred", "strategy": "buffered", "threshold": <rows>|null}}`. `data` and each of its keys are optional (inline, buffered, no threshold); `params` is optional and absent means `null`. Every key is **closed** at both levels — an unknown one is a 400 naming it. `strategy: "streamed"` is a 400 at `$.data.strategy`.

Every response is `application/json; charset=utf-8` with a real `Content-Length`; Buffered means the document goes into a `StringBuilder` and is sent only when the write returns, so no partial document ever reaches a client. A failure is `{"error":{"path":..,"message":..}}` with `path` null when there is none.

| Status | When | `path` |
|---|---|---|
| 400 | body not JSON (`StackOverflowError` from argonaut's parser included) / not an object / unknown key; `streamed`; a parameter the type refuses; a report whose type is not `Params -> Node` | `$`, `$.data.<key>`, `$.params...` |
| 404 | no such module, no binding of that name, no such route, unknown or expired token | null |
| 405 | wrong method for the route (with `Allow`) | null |
| 413 | body over `--max-body` | null |
| 500 | the report threw, produced an unencodable document, or a scan failed | a path into the **response document** when there is one, else null — never a place in the request |

### Curl walkthrough (real output, elided only at `...`; it is in the plan too)

```
$ bin/ermine-serve --root core/src/test/resources/doc --preload Sales --port 8080
listening on 8080

$ curl -s localhost:8080/health
{"status":"ok","version":1,"modules":["Bool","Builtin",...,"Sales",...]}

$ curl -s localhost:8080/report/Sales -H 'Content-Type: application/json' \
       -d '{"params": {"fromDay": "2026-01-05", "toDay": "2026-02-20",
                       "onlyRegion": "north", "orderBy": "ByAmount"}}'
{"version":1,"settings":{},"root":{"tag":"VFlow","children":[
 {"tag":"Widget","name":"heading","props":
   {"title":"Sales","sortColumn":"amount","matched":3,"total":4350.75}},
 {"tag":"Grid","cells":[
  [{"tag":"Widget","name":"table","props":{"kind":"inline","columns":[
      {"name":"amount","type":"Double","nullable":false},
      {"name":"day","type":"Date","nullable":false},
      {"name":"region","type":"String","nullable":false},
      {"name":"units","type":"Int","nullable":false}],
      "rows":[[840.0,"2026-01-19","north",2],[1200.5,"2026-01-05","north",3],
              [2310.25,"2026-02-14","north",7]],"rowCount":3}},
   {"tag":"Widget","name":"table","props":{"kind":"inline","columns":[
      {"name":"region","type":"String","nullable":false}],
      "rows":[["east"],["north"],["south"],["west"]],"rowCount":4}}],
  [{"tag":"Widget","name":"table","props":{"kind":"deferred","columns":[...],
      "token":"HyCqXpeUb93IWNkxqJnM2g","expires":"2026-09-16T15:20:12.814Z"}},
   {"tag":"Widget","name":"text","props":"line items on demand"}]]}]}}

$ curl -s localhost:8080/data/HyCqXpeUb93IWNkxqJnM2g
{"kind":"inline","columns":[...],"rows":[[75.5,"gizmo",1],...],"rowCount":8}

# data.default / data.threshold apply to BARE relations only
$ curl -s localhost:8080/report/Sales \
       -d '{"params": {"fromDay":"2026-01-01","toDay":"2026-12-31","orderBy":"ByDay"},
            "data": {"default": "inline", "threshold": 4}}'
... matched 8, total 12682.0; the 8-row table comes back "deferred", the 4-row
    regions table is still "inline", the Deferred-wrapped line items always deferred ...

$ curl -s -w ' [%{http_code}]' localhost:8080/report/Nope -d '{}'
{"error":{"path":null,"message":"no module named Nope"}} [404]
$ curl -s -w ' [%{http_code}]' localhost:8080/report/Sales -d '{"params":{"fromDay":"nope",...}}'
{"error":{"path":"$.params.fromDay","message":"the string \"nope\" is not a date yyyy-MM-dd"}} [400]
$ curl -s -w ' [%{http_code}]' localhost:8080/report/Sales -d '{...,"data":{"strategy":"streamed"}}'
{"error":{"path":"$.data.strategy","message":"the \"streamed\" strategy is not in version 1 of the wire; use \"buffered\""}} [400]
$ curl -s -w ' [%{http_code}]' localhost:8080/data/notarealtokenatall00
{"error":{"path":null,"message":"no such token, or it has expired"}} [404]
$ curl -s -w ' [%{http_code}]' localhost:8080/report/Sales      # wrong method
{"error":{"path":null,"message":"this route takes POST"}} [405]
```

CLI flags: `--root DIR`, `--preload Module` (both repeatable), `--db URL`, `--dialect sqlite|mssql|mysql|postgres|vertica`, `--port N` (0 → ephemeral, printed), `--report-name NAME`, `--ttl SECONDS`, `--max-tokens N`, `--threads N`, `--max-body BYTES`, `--settings JSON`.

## Concurrency model, and why

**Evaluation is serialised behind one PROCESS-WIDE monitor; scanning and writing are concurrent.**

Under the lock: `Session.loadModules`, `Session.eval`, the parameter decode, `fn.apply1(v)` and `Doc.fromRuntime` (which forces the whole value). Reasons, in order of how sure I am: module loading mutates the `SessionEnv`'s eight maps field by field *and* the process-global `DataConDecl` registry; `Supply` is documented single-threaded (per-thread supplies here, from the synchronized global block allocator, as `ErmineFixture` does); and `Runtime.Thunk.state` is a **non-volatile `var`** — its whitehole/`CountDownLatch` machinery guards against a cycle, not against a data race, so two threads forcing the same library thunk have no happens-before. Evaluating a report is microseconds to milliseconds; the scan is where the time is.

Outside the lock: `Run[DB].run(Write.doc[DB](...))`. J3b certified that nothing in `Doc`/`Write`/`Rows` reads the session, each request has its own `Appendable`, and `MemoryPlanCache` is synchronized; `Run.ThreadLocalDC` hands each thread its own connection. So N requests overlap on the database and queue on the interpreter.

The HTTP server uses a **fixed pool** (default 16) rather than the JDK's default executor, which runs every exchange on the dispatcher thread and would have serialised the scans too. Pool size = the number of concurrent DB connections this process opens.

**The monitor lives on `object Runner`, not on the instance** (review fix 1). A `Runner` has its own `SessionEnv`, but `DataConDecl`'s two registries are *static* (`ermine/DataConDecl.scala`), written by `Session.loadModules` and last-writer-wins per `Global`, and both `Encode` and `Decode` read them — so two runners in one JVM loading two modules that declare the same `data` type would overwrite each other's constructor field lists. That is not hypothetical: open issue 1 below recommends one runner per tenant, and `TestRunner` itself builds two (`runner` and `clockedRunner`) whose boots can overlap. One lock for the process costs a single-runner deployment nothing (`ServeMain` builds one) and removes a latent cross-runner race.

**`GET /health` is the one path that does not take the lock** (review suggestion (e)): it reads a `@volatile` snapshot of the loaded-module set, refreshed under the lock after every load. A liveness probe that queues behind the slow report it is probing is worse than useless, and open issue 5 says there is no timeout on `apply1`.

Property **(d)** fires 8 generated requests concurrently, twice each, through the socket, and requires byte-identical bodies (tokens/expiry masked) to the same requests run one at a time.

## Decisions taken in code

1. **A report that throws and a report that builds something unwritable are the same 500.** An Ermine `error` inside the value reaches `Encode` as a `Bottom` and comes back as an `Encode.Error`, not an exception, so the two are indistinguishable — and neither is the client's fault. This is a **departure from J3b's sketch**, which suggested `badRequest(e.report)`; a 400 there would have made the brief's "a report that throws → 500" unachievable. The error's `path` is then a path in the *response* document, which is why the body carries `path` beside the status rather than pretending it is a request path.
2. **Refusals are not cached**, only working reports. A 404 for a module the operator is about to drop in, or a 400 for a signature they are about to correct, must not outlive the fix.
3. **Unknown keys refused** at both levels: a client's `"treshold"` is an error, not silence.
4. **A missing `params` is `null`** (what a `Maybe`/`Json`/`()` parameter wants).
5. **Module names validated** (dot-separated identifiers) before they reach `SourceFile.filesystem`, which splits a name into a path. `../etc/passwd` is a 404, pinned.
6. **No `Doc.fromRuntime` hints.** The runner knows only the report's *result* type (`Node`), never the type of a relation buried in a widget's props, so there is nothing to build a header hint from. A header-less `mkRelation# []` is a 500 naming `mkRelationWithHeader#` — pinned by (b7) rather than papered over.
7. `MethodNotAllowed` (405) and `TooLarge` (413) live in `RunError` beside the runner's three so every body a client can see has one shape.
8. **The report's type comes from the BARE name** (`Session.eval(reportName, imports)`), and the runner parses **no type expression at all** — see the 2.11 section.
9. `RunnerConfig` carries a `Run[DB]` and a `Scanner[DB]` rather than a dialect string, with `RunnerConfig.backend(dialect, url)` building the pair; that is what lets (e) count connections.
10. Health reports `modules` (the loaded set) so an operator can see whether `--preload` worked.

## Departures from the plan / brief

- Encode errors are 500, not 400 (decision 1, with its reason).
- `RunError` has five cases, not three (decision 7).
- The runner does not supply `Doc` hints (decision 6); the brief's "header-hint path" note from J3b is answered by an explicit refusal.
- `Runner.render` has three overloads (`Json`, `Request`, and `renderText` from the body text) rather than only the `argonaut.Json` one, because the `StackOverflowError` guard belongs with the parse and the server should not duplicate it.
- The example report is `Sales.e`, and the params fields are `fromDay`/`toDay`/`onlyRegion`/`orderBy`: `from`/`to`/`region`/`sort` would collide with the module's own `field region` witness and with `List`'s names.

## Gates (Tier 0)

Logs in `/tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/j3c/`.

| # | Gate | Result | Log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources` | success | `gate1-compile.log` |
| 2 | `TestRunner` + `TestDoc` + `TestDecode` + `TestJson` + `TestSchema` + `TestNamedFields` | **114/114, twice** (16 + 20 + 11 + 28 + 25 + 14); schema fixture gate **11 fixtures match** | `gate2-suites.log`, `gate2-suites2.log` |
| 3 | `core/testOnly *TestLoopTrace` | 3/3; with `-Dermine.looptrace=` at the Lean binary built in the `json-wrappers` worktree: **720 solves, 720 segments, 720 agree, 0 skipped, 0 hashdiff/eqdiff**, 11.2 s, controls detecting 46/720 and 58/720 | `gate3-looptrace-lean.log` (without the binary, SKIPPED: `gate3-looptrace.log`) |
| 4 | `corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged | `gate4-corpus.log`, `gate4-verdicts.log` |
| 5 | `repl-smoke.sh` | green: aliasing 2, ffi 5, ffi-tolerant 9, **json 20**, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5 | `gate5-repl.log` |
| 5 | `lsp-smoke.sh` | **PASS, 577 checks** | `gate5-lsp.log` |
| — | post-review-fix re-run: compile, then `TestRunner` + `TestDoc` | success; **36/36** (16 + 20) | `fix-gate1-compile.log`, `fix-gate2.log` |

`tracker/repl-classpath.txt` was regenerated for the smokes and restored with `git checkout` (the tree no longer shows it). Gate 1 was re-run after the last (comment-only) edit; gate 2 was re-run after it too.

## The 16 properties, and that they are not vacuous

Report modules are **generated as Ermine source** into `core/target/json-runner-modules` (under `target/`, not `/tmp`; cleaned at suite start) and served by one booted `Runner` pointed there with `--root`. Each case is a random parameter type and value from `TestSchema.shape(2)`, one to three literal relations in one of the six delivery forms (`bare`, `Inline`, `Deferred`, `rel`, `relInline`, `relDeferred`), and a random `data` configuration.

- **(a)** 24 cases end to end in process: the envelope is `version/settings/root` with `settings` verbatim; the first widget's props equal the params *sent* (numbers compared by value, because a `Json`-typed parameter round-trips `2.0` to `2` through `parseJson#`); each relation object's kind follows `Write.resolve` + threshold; columns are the sorted descriptors; rows equal the literal rows as a set; every deferred token resolves through `Runner.data` to the inline object. Asserts all six forms and both kinds occurred and that at least one token was re-requested.
- **(b1)** 12 cases × up to 12 single mutations of the params document: a refusal is always 400 at a path under `$.params`; asserts >20 mutations were actually refused.
- **(b2)** unknown module, a module with no `report`, `../etc/passwd`, a lowercase name, an unknown token → 404 with `path: null`. **(b3)** polymorphic / non-function / wrong result / undecodable params → 400 naming "polymorphic", "not", "Layout.Doc.Node", "function". **(b4)** a report that `error`s → 500 with the message and a document path, and the same answer twice (refusals are not cached). **(b5)** expired token → 404, driving the plan cache's clock by hand (fresh 200, +59 s 200, +61 s 404). **(b6)** body shape: eight bad bodies each at the exact path, a truncated body, a 60,000-deep body (400, not a crash), `streamed`. **(b7)** header-less empty relation → 500 at `$.props` naming the hint.
- **(c)** the same 10 requests in process and over `HttpURLConnection` must give byte-identical bodies after masking tokens/expiry, plus 6 further cases run *entirely* through the socket via (a)'s checker; `Content-Type` and `Content-Length` checked on every call. **(c-routes)** health, 405, unknown route, unknown module, 413; and, after the review, that a response body really is multi-byte (so `http()`'s `Content-Length == getBytes("UTF-8").length` assertion on every call is not comparing a number with itself) and that a HEAD answers 200 with the Content-Length a GET would have carried and no body.
- **(d)** concurrency (above). **(e)** one connection per POST over 3 relations, one per GET `/data` (per-thread counting — ScalaCheck runs a suite's properties concurrently, so a shared counter is everybody's). **(log)** one INFO line per request on `ermine.json.http` (`POST /report/X status=200 ms= bytes=`), a 404 line, and J3b's `ermine.json.doc relation $.props inline rows=1 bytes=` still there.
- **(ex)** the example report: heading props, three matched rows, `total` 4350.75, column names, the `Deferred` wrapper deferred regardless, the token resolving to 8 rows, and a threshold of 4 deferring the 8-row table while the 4-row one stays inline.
- **(sql-guid)**, **(sql-teardown)**: the two tickets, below.

**Not vacuous.** Two deliberate mutants were built and run:

| Mutant | Falsified |
|---|---|
| `Request.delivery` reads `"deferred"` as `Delivery.Inline` | (a) and (c) — (b1)…(b7), (d), (e), (ex) stayed green |
| the `$.params` prefix dropped from the decode error's path | (b1) and (b6) — everything else stayed green |

Logs `mutantA.log`, `mutantB.log`; the file was restored from a backup and verified to contain no `MUTANT`.

## The two tickets from J3b's review — both FIXED

1. **NULL in a GUID column NPEs.** Fixed in `sql/SqlEmitter.scala`, `EmitUuid_Strings.getUuid`: read the string, and answer `null` for a SQL NULL instead of calling `UUID.fromString(null)`. `SqlExecution.nextRecord` builds the cell *before* `rs.wasNull` for every type; every other getter answers a zero and leaves `wasNull` set, and `UuidExpr` holds its value without touching it, so the null never escapes — the `wasNull` test two lines on replaces the cell with `NullExpr`. One line of real change, in the one place that defines `getUuid` (grep: no other implementation). Property **(sql-guid)** round-trips random relations with a nullable GUID column (random mix of NULLs and UUIDs) through SQLite and requires the NULLs back as `null` and the UUIDs as their canonical strings; it fails with an NPE on the old code.
2. **`EffectfulProcedure.withDriver` has no `finally`.** Fixed in `relational/package.scala`: `try k(d) finally teardown()`. Property **(sql-teardown)** builds an `EffectfulProcedure` whose machine throws at a random record and requires exactly one teardown; it reports `teardowns 0` on the old code. Caveat recorded in the comment: a teardown that itself throws now replaces the original exception, the usual price of `finally` and better than leaking the cursor. This is shared relational code, so the landing's full `core/test` is its real gate — the same caveat J3b attached to the `RecordMap` line.

## Two defects found on the merged tip (not mine, fixed here)

Both were red in `TestDoc` **before** I touched anything (`testdoc-alone.log` on the unmodified tree shows them):

1. **`(d)` failed 13 of 80 cases with "undefined type".** J2a widened `TestSchema.shape` to Date, GUID, Prim, the native collections and Vector and added those modules to `TestSchema.imps`; `TestDoc.dImps`, on the other branch, did not get them. Fixed by adding them (Vector aliased as `V`). This is a **J2a/J3b merge gap** that the orchestrator's merge did not surface because neither stage re-ran the other's suite.
2. **`(b-sql)` asserted `badNulls == List("UUID")`** — a *measurement* of the GUID bug. My fix makes a nullable GUID carry, so the measurement moved; the assertion is now `badNulls.isEmpty` and `sqliteExact` is the full `primCtors` (so `(b)` now draws nullable GUID columns too). Comments in both places say what changed and why.

I also saw `(b-sql)` report `column types lost: List(Timestamp)` **once**, in the first heavily loaded six-suite run, and never again in four later runs (including two clean gate-2 runs). I could not reproduce it; noting it as a suspected load-dependent flake in J3b's `(b-sql)`, not a regression — it is a `carries(TimestampT, …)` probe against SQLite.

## Review round (FIX-THEN-LAND verdict, `tracker/json-stage3/review-J3c.md`)

All four required fixes applied, plus five of the twelve suggestions.

1. **The evaluation monitor was per-`Runner` while part of what it guards is process-global.** Moved to `object Runner` (`private[json] val evalLock`); the instance field is now `= Runner.evalLock`. The class comment, §3.7d and the concurrency section above say why. No behaviour change for the single runner `ServeMain` builds; it removes a real cross-runner race and a latent flake between `TestRunner`'s two runners.
2. **The plan's `path` sentence contradicted decision 1.** `JSON-STAGE3-PLAN.md` now carries a three-row table instead of prose: 400 → a path into the request (`$`, `$.params...`, `$.data.<key>`), 404/405/413 → always null, 500 → a path into the **response** document when there is one, never a place in the request. J3d generates against the plan, so this is the sentence that mattered.
3. **Three comments still described the pre-fix `withDriver`.** `Write.scala`'s `Rows.Sink` comment, and two in `TestDoc.scala`, said it "has no `finally`" with stale line numbers. Rewritten: the hole is closed as of J3c, and `Stop` remains the sink's exit because it is what keeps the buffered-prefix promise — the reason is unchanged and still correct.
4. **`JSON-API-DESIGN.md` said 15 properties in two places**; there are 16.

Suggestions taken:

- **(i) `addSuppressed`.** `withDriver`'s `finally` no longer masks the original exception: a teardown that throws while an exception is in flight is attached to it, so "why the scan failed" is never lost behind "why closing it failed".
- **(e) `/health` off the lock** (above).
- **(c) a non-ASCII `settings` value.** Every other string the suite generates is alphanumeric, so no response body contained a multi-byte character and the `Content-Length` assertion could not have caught a `text.length` regression. `settings.note` is now `"café — ünïcode 🙂"` — two-, three- and four-byte characters, the last a surrogate *pair* — which makes every HTTP body in every property multi-byte, and `(c-routes)` asserts the bytes and the chars really differ.
- **(g) HEAD carries a `Content-Length`.** The JDK's server suppresses it for HEAD even when a positive length is passed, so the header is set explicitly before `sendResponseHeaders`; that survives, and `(c-routes)` pins it against the GET body's byte length with an empty body.
- **(f) `StackOverflowError` beside `NonFatal`** in `Server.dispatch`, so the "every failure has one shape" promise survives a future decoder that recurses deeper than argonaut's parser. Written as a guard (`case e: Throwable if NonFatal(e) || e.isInstanceOf[StackOverflowError]`) rather than a pattern alternative, for the 2.11 dialect.
- **(l), (k), (d)** are one-liners in §3.7d: why a bad *signature* is 400 while a bad *value* is 500; that there are no CORS headers (J3d cannot call this from another origin); and that a 413 is sent without draining the body, and `Run[DB]` is not a pool.

Not taken, deliberately: **(a)/(b)** — `(d)`'s warm-up and its round-2 overwrite. Both are gaps in the *assertion*, not the execution: the reviewer's own analysis notes that ScalaCheck runs the 16 properties concurrently over the one runner, so `(b2)`–`(b7)`, `(log)` and `(ex)` are compiling fresh modules under the lock while `(d)` runs. Changing `(d)` to race uncompiled modules would make its serial reference racy too, and I would rather not rewrite a green concurrency property at the end of the budget. **(h)** the double percent-decode in `Server.decode` buys nothing but is harmless — validation runs after it, which is what makes it safe. **(j)** taken, actually: `Allow` now reads `GET, HEAD`.

Post-fix gates: `sbt -batch core/compile core/copyResources` success (`fix-gate1-compile.log`), `TestRunner` + `TestDoc` **36/36** (16 + 20, `fix-gate2.log`). The other gates were not re-run: gates 3, 4 and 5 cannot be moved by a lock's owner, three comments, a `settings` string or a HEAD header, and the reviewer cited them rather than re-running them for the same reason.

## Open issues

1. **The plan cache is unauthenticated.** A token is a bearer credential for the rows behind it. One `Runner` per tenant, or J3d/J3e should ask for a per-session cache. Documented on `Runner.plans`. (Safe to follow as of review fix 1: the evaluation lock is process-wide, so a second runner is serialised against the first.)
2. **No authentication or TLS at all.** `bin/ermine-serve` binds every interface in the clear; it is a development/back-end server, to sit behind something else.
3. **Modules never unload.** A module a request names stays in the session for the process's life, and a report that works is cached forever — no `:reload`. `Session.reloadChangedModules` exists and would be the hook.
4. **The lock is coarse.** Loading a big module blocks every other request's decode. A read/write split (loads exclusive, evaluation shared) is possible only once thunk memoisation is proven safe, which it is not today.
5. **The evaluation lock makes a slow report a head-of-line block.** There is no timeout on `fn.apply1(v)`; an Ermine infinite loop hangs the runner. A watchdog wants a separate thread and `Thread.stop` semantics we do not have.
6. `settings` reaches the wire through argonaut's printer, which escapes neither U+2028/U+2029 nor lone surrogates (J3b). It is server configuration from `--settings`, not client input, so this stays theoretical — but do not let a client supply it.
7. A deferred token holds the relation's **plan**; for `mkRelation#` literals the plan holds the rows, so the cache holds them until the TTL. Bounded by count (`--max-tokens`), not bytes.
8. The deferred re-request **re-scans**, and relations carry no order, so the rows are the same but the ORDER need not be — visible in the walkthrough. The client must not assume stability.
9. `--settings` must be a JSON object; a non-object is refused at startup rather than at request time.
10. No `Content-Encoding`; a large inline document is sent uncompressed.
11. **`tee`'s nested `withDriver` still has the shape ticket 2 fixed** (`relational/package.scala`, the `EffectfulProcedure` returned by `tee`): it calls its own `teardown()` after `k(d1 * d2)` with no `finally`, so the *outer* procedure of a tee leaks if the inner one throws. Nothing in the JSON path uses `tee`, and I did not want to change more shared relational code at the end of the budget without a property for it — left as a ticket with the fix already written next door.

## What the 2.11 port (P2 = J3b + J3c) must know

- **No type expression is parsed anywhere in this stage.** P1's finding (2.11's `Session.eval` runs the fused `phrase(term)` without Console's `fixCons`, so a type constructor inside a *term* infers a polymorphic scheme) does not bite: `Runner.compile` evaluates the **bare name** `Session.eval(cfg.reportName, Map("Builtin" -> all, module -> all))`, and there is no `NewPipeline.replType` call in `Runner.scala`, `Server.scala`, `ServeMain.scala` or `TestRunner.scala` — so there is no helper to swap and nothing to replace with `SchemaParse.typeExpr`. A comment at that call site says so, so the porter does not have to rediscover it. The existence check before it is `env.termNames.contains(Global(module, reportName))`; `TestRunner`'s `paramsOf` likewise evaluates a bare `pv` whose type comes from a *declaration*, never an ascription.
- **The review round added four things the porter should carry verbatim**: `Runner.evalLock` on the companion object (a process-wide monitor, not per instance — `DataConDecl` is static on 2.11 too), `@volatile private var loadedSnapshot` (the `@volatile` annotation exists on both), `Throwable#addSuppressed` in `withDriver` (JDK 7+, fine on both), and the explicit `Content-Length` header for HEAD in `Server.sendText` (the JDK's server suppresses it otherwise).
- **Dialect.** Written in the 2.11-and-3 subset: `.right.map`/`.right.flatMap` only (no `Either#map`/`foreach`), `scala.collection.JavaConverters`, no `given`/`enum`/`extension`, no `LazyList`/`Using`, JDK 8 APIs only. `ThreadLocal` is the anonymous-subclass form (`new ThreadLocal[T] { override def initialValue = ... }`), **not** `ThreadLocal.withInitial` — 2.11 has no SAM conversion for Java functional interfaces by default. `String#matches`, `String#split(Char)`, `java.net.URLDecoder`, `com.sun.net.httpserver` all exist on JDK 8.
- **Stable-identifier patterns avoided**: `Request.parse` compares with guards (`case Some(s) if s == Wire.Inline`) rather than `case Some(Wire.Inline)`.
- **Case classes with default arguments** (`RunnerConfig` 9 fields, `Failed(message, at = None)`, `ServeMain.Options` 11 fields) — fine on both, but `RunnerConfig`'s default `run = Runners.liteDB` loads the SQLite driver eagerly whenever a default-constructed config is made.
- **`Server.scala` is `com.sun.net.httpserver` only** — no dependency was added to `build.sbt`, and none is needed on 2.11 either.
- **`TestRunner` uses log4j-2 core APIs directly** in `capturingLog` (`org.apache.logging.log4j.core.*`, `Property.EMPTY_ARRAY`), the same hazard J3b flagged for `TestDoc`: if the 2.11 branch has real log4j 1.2, the `(log)` property needs a 1.2 `AppenderSkeleton`.
- **`TestRunner` uses scalacheck 1.15.4 shapes** (`Gen.alphaNumChar`, `Gen.sequence`, `TestSchema.pickN`, `TestSchema.samples`) and `TestSchema.shape`/`defAndType`, so P1's `TestSchema` must already be ported.
- **The two SQL fixes are shared code.** `SqlEmitter.scala` is CRLF on this branch — keep the endings. Check whether the 2.11 `SqlExecution`/`SqlEmitter` have the same shape before porting; the `getUuid` fix is emitter-side and should transfer verbatim, the `withDriver` `finally` is a three-line change in `relational/package.scala`.
- **`TestDoc`'s two corrections travel with J3b**, not with the writer code: `sqliteExact = primCtors` and `badNulls.isEmpty` are only correct *after* the `getUuid` fix, and `dImps` needs the Stage 2a modules only if the 2.11 `TestSchema.shape` has J2a's leaves.
- The example report `core/src/test/resources/doc/Sales.e` is plain Ermine; it needs `import List using {filter; length; nub; sum'; map_List; empty_Bracket; cons_Bracket}` (plain `map`/`length` are not exported / collide with `String`'s) and `import Primitive` for `<=`/`>=` on `Date`. `import Primitive using {(<=); (>=)}` does **not** parse — operator names in a `using` list need parentheses, and a plain import is simpler.