# Review of J3c (the document runner), independent

Reviewer: an agent that did not write the stage. Worktree `~/research/ermine/ermine-scala-wt-json-runner`,
branch `json-runner`, base `03676cbe`. Reviewed: `git diff 03676cbe` plus the untracked
`json/{Runner,Server,ServeMain}.scala`, `bin/ermine-serve`, `core/src/test/resources/doc/Sales.e`,
`scalacheck-binding/.../TestRunner.scala`, `tracker/json-stage3/report-J3c.md`. About 1 h 40.

Verdict at the bottom: **FIX-THEN-LAND** (4 fixes, one substantive and three documentary).

## What I re-ran

| What | Result | Log |
|---|---|---|
| `sbt -batch core/compile core/copyResources 'core/testOnly TestRunner TestDoc TestJson TestSchema TestNamedFields'` | **103/103, 0 failed** (TestRunner 16, TestDoc 20, TestJson 28, TestSchema 25, TestNamedFields 14); 93 s | `<scratch>/review-j3c/rerun-suites.log` |
| my own mutant: `Runner.data`'s unknown-token `NotFound` -> `200 {}` | **falsified (b2) and (b5)**, 14 others green; reverted, md5 back to `ea46f338…`, no `MUTANT` string left | `<scratch>/review-j3c/mutant-token.log` |
| `bin/ermine-serve --root core/src/test/resources/doc --preload Sales --port 0`, walkthrough replayed over a socket | every documented line reproduced byte for byte | `<scratch>/review-j3c/serve.log` |

(`<scratch>` = `/tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad`.)

Cited, not re-run (the diff cannot plausibly move them and the stage has green logs):
TestLoopTrace 720/720 (`j3c/gate3-looptrace-lean.log`), corpus 89/79/0 over 168
(`j3c/gate4-corpus.log`, `gate4-verdicts.log`), REPL and LSP smokes (`j3c/gate5-repl.log`,
`gate5-lsp.log`). `tracker/repl-classpath.txt` is unmodified in the tree, as the report says.

Live replay, all matching the plan's walkthrough: `/health` 200; the Sales document
(1117 bytes, `Content-length: 1117`); `matched 3`, `total 4350.75`; `["deferred","inline","deferred"]`
and `rowCount 4` for the `threshold: 4` request; the token resolving to the 8 line items;
`404 no module named Nope`, `400 $.params.fromDay`, `400 $.data.strategy`,
`404 no such token`, `405 this route takes POST`, `413` on an oversized body;
`/report/../../etc/passwd`, `/report/..%2f..%2fetc%2fpasswd` and `/report/%252e%252e` all 404.

## 1. The concurrency model

**The claims hold.** I checked each one rather than taking the comment's word:

- *Nothing outside the lock touches the interpreter.* `render` takes `evalLock` for
  `compile` (`Runner.scala:367`) and for decode + `apply1` + `Doc.fromRuntime`
  (`Runner.scala:437`); only `write` (`:456`) runs outside it, over a `Doc`. The one field
  of `Doc` that could smuggle interpreter state is `Doc.Data.ext`. It cannot:
  `Rel` stores its `Ext` strictly (`ermine/Runtime.scala:92`; the `=> Ext` in
  `Rel.apply`, `:104-107`, exists only to route an exception into `Bottom`, and
  `new Rel(h)` forces it there), every `Ext`/`Mem`/`Relation` node is a strict case class
  with no `Runtime`-typed, by-name or lazy field, and every construction site
  (`Runtime.scala:386,395`; `Lib.scala:341-355` and the combinators) forces the rows to
  `PrimExpr` through `.nf`/`toPrimExpr` before the `Rel` exists. `Typer.extTyper` has no
  laziness either. So the scan reads immutable pure data.
- *Per-thread connections.* `Run.ThreadLocalDC.run` (`Run.scala:150-170`) keeps a
  `java.lang.ThreadLocal[Option[Resource]]` and `DB.Run` (`backends/DB.scala:106-117`)
  opens a fresh `Connection` per outermost `run` and closes it in a `finally`. One
  connection per request, released at the end — confirmed by `(e)` and by my reading.
  Note this is *not* pooling: a request against a real server opens and closes a JDBC
  connection. `--threads` bounds the concurrent count, which is what the doc claims.
- *Supplies.* `Runner.scala:260` is a per-Runner per-thread `Supply`; blocks come from the
  synchronised global allocator, so ids stay disjoint. Bounded by the pool size.
- *Safe publication.* `reports` is a `ConcurrentHashMap` and `Report` has only `val`s;
  `Runner`'s own fields are `val`s frozen by the constructor.

**The gap** is that the monitor is per-`Runner` while part of what it guards is
process-global — required fix 1 below.

**Is (d) strong enough?** It proves what it says (8 cases x 2 rounds through the socket,
bodies byte-identical to the serial ones modulo tokens/expiry), but it is weaker than it
reads, for two reasons:

- `TestRunner.scala:742` renders all 8 modules serially *first* "so every module is compiled
  and cached", which means `report()` then returns on the lock-free fast path
  (`Runner.scala:365`) and the concurrent phase never exercises `compile()` /
  `Session.loadModules` under contention — the riskiest thing the lock protects. In
  practice the suite covers it anyway: ScalaCheck runs the 16 properties concurrently over
  the one `runner`, and (b2)/(b3)/(b4)/(b5)/(b6)/(b7)/(log)/(ex) each write and compile
  fresh modules while (d) is running. So it is a gap in the *assertion*, not in the
  execution. Suggestion (c) below.
- `results.put(i, masked(text))` (`:756`) runs twice per thread, so round 2 overwrites
  round 1: a wrong first answer that the second round gets right is invisible.

Neither is a correctness defect in the runner, so neither is a required fix.

## 2. HTTP correctness and safety

Everything the brief asks about checks out:

- **Body cap before the body is read.** `Server.body` (`:140-155`) reads in 8 KiB chunks
  and stops the moment `buf.size + n > maxBody`, so the peak is `maxBody` + one chunk, not
  the client's whole body. Exactly `maxBody` is accepted (the test is `>`).
- **`Content-Length` is bytes, not chars.** `sendText` (`:175-186`) uses
  `text.getBytes("UTF-8").length`. Verified live rather than by reading: with
  `--settings '{"locale":"en-GB","note":"café — ünïcode"}'` the response is
  `Content-length: 1254` for 1249 characters, and a 404 echoing the module name `Nöpe` is
  `Content-length: 57` for 56 characters.
- **Module names / traversal.** `Runner.moduleNameOk` (`:485-499`) runs *before*
  `env.loadFile` and before anything reaches `SourceFile.filesystem`: parts are non-empty,
  start with a letter, and contain only letter/digit/`_`/`'`, so `..`, `/`, `\`, a `%`, an
  empty segment and a trailing dot are all refused as 404. Verified live for three shapes
  including a double-encoded one.
- **Status mapping** matches the brief and the design-note table: 400 (`Request.parse`,
  decode, signature), 404 (module, binding, token, route), 405 with `Allow`, 413, 500.
- **No partial document.** `Server.report` (`:116-127`) renders into a `StringBuilder` and
  calls `sendText` only on `Right`; on `Left` the prefix is dropped. This is the whole point
  of Buffered and it is implemented correctly.
- **The `StackOverflowError` guard** is around argonaut's parse only (`Runner.parseBody`,
  `:348-354`) — which is the right place: I probed the real boundary with a
  `report : Json -> Node` module and a fresh server, and depths 50…950 all answer 200 while
  1000…8000 all answer `400 "the request body is nested too deeply to parse"`. There is no
  window where the parse succeeds and a later walk overflows (`Write.segments` is an
  explicit-stack loop, `Doc.relations` likewise, and `Encode` is pinned stack-safe by
  TestJson). 
- **A handler that throws.** `dispatch` (`:71-92`) catches `NonFatal`, tries to send a 500,
  swallows a second failure, and closes the exchange in a `finally` that also logs. An
  `Error` (only reachable via a VM condition today) would escape the catch but still hit the
  `finally`, so the exchange is closed and the client sees an empty reply rather than a
  half-document. Acceptable; see suggestion (f).
- **Headers**: `application/json; charset=utf-8` on every response including errors;
  `Allow` on 405.

## 3. The two shared-code fixes

**`SqlEmitter.EmitUuid_Strings.getUuid` (`:588`, NULL -> null UUID).** Sound on every path.
`getUuid` has exactly one declaration (`SqlEmitter.scala:62` abstract) and one
implementation (`:588`), and exactly one call site: `SqlExecution.nextRecord:81`. That call
site builds `simpleExpr` and asks `rs.wasNull` two lines later (`:84`) for *every* column
type, so reading the string and answering `null` keeps `wasNull` set exactly as
`rs.getInt`/`getDouble` do. `UuidExpr` (`PrimExpr.scala:348`) is a plain case class that
never touches its value, and `RecordMap.createWithKeyCache` (`RecordMap.scala:141-148`)
fills the array eagerly in a loop, so the cell is built and discarded before the next column
is read — no lazy cell can move the `wasNull` question. A NULL in a *non*-nullable GUID
column now reaches `sys.error("Unexpected NULL in field of type …")` instead of an NPE,
which is the same treatment every other type gets. CRLF is preserved: 1071 of 1071 lines of
`SqlEmitter.scala` end CRLF, the new hunk included.

**`EffectfulProcedure.withDriver` `try k(d) finally teardown()` (`relational/package.scala:133-136`).**
I looked for a caller that relies on teardown *not* running after an exception and found
none. `withDriver` is called only from `foldLeftM` (`:121`) and `execute` (`:153`) in the
same trait, plus the nested `withDriver` of `tee` (`:172-176`); the three `setup`
implementations in the tree are `SqlExecution.scala:32` (`rs.close; stmt.close`, idempotent),
`Mem.scala:467` (`() => ()`), and the test procedures. Nothing calls `teardown` itself, so
there is no double-teardown path. A teardown that throws now replaces the original
exception — the comment says so; see suggestion (i) for the `addSuppressed` refinement.

Both are shared relational code and the landing's full `core/test` is their real gate, as
the report says. On their own merits they are right.

## 4. The `TestDoc` changes

Correct consequences of the GUID fix.

- `sqliteExact = primCtors` (`:350`): `primCtors` (`:43-45`) ends with `b => UuidT(b)` and
  `primGen` draws `b` at random, so `(b)` now really does generate nullable GUID columns —
  the old `primCtors.dropRight(1) ++ List(UuidT(false))` pinned them non-nullable.
- `badNulls.isEmpty` (`:506`): this is the *measurement* `(b-sql)` takes against a live
  SQLite, and it passed in my own run, which is direct end-to-end evidence that a NULL GUID
  now round-trips. `badTypes.isEmpty` passed too.
- `dImps` (`:612-623`): adding Date/GUID/Prim/Native.Maybe/Native.Pair/Vector-as-V matches
  `TestSchema.imps`; the diagnosis (a J2a/J3b merge gap, red on the tip before this stage)
  is confirmed by `j3c/testdoc-alone.log` on the unmodified tree.

I did not see the one-off `column types lost: List(Timestamp)` the report mentions; it did
not reproduce in my run either. Leave it as a suspected load-dependent flake in J3b's
`(b-sql)` for the landing to watch.

## 5. Decision 1 (encode errors / `Bottom` are 500 with a document path)

**Agree.** An Ermine `error` inside the value is indistinguishable from an unencodable
document because both arrive as `Encode.Error`, and neither is something the client can fix
by changing the request — the parameters already passed the report's own type. The brief
also requires "a report that throws -> 500", which a 400 would have made unreachable. Giving
the failure a path into the *response* document is more useful than `null`, and the 500
status tells a client not to read it as a request path.

Two consequences worth recording rather than changing:

- The plan's prose now contradicts it — required fix 2.
- A report whose *signature* is wrong is a 400 (`Runner.scala:430`) even though that is
  equally the operator's fault and not the client's. The brief asked for 400, so it stays,
  but the design note should say in one sentence why the two differ (suggestion (l)).

## 6. Dialect (2.11-and-3)

Clean. No `given`/`using`/`enum`/`extension`/`export`/`derives`, no `LazyList`, no
`CollectionConverters` (`scala.collection.JavaConverters` at `TestRunner.scala:704,764`), no
`Using`, no Java 9+ API (`com.sun.net.httpserver`, `URLDecoder`, `String#matches`,
`String#split(Char)`, `Character.isLetterOrDigit` are all JDK 8). `ThreadLocal` is the
anonymous-subclass form at `Runner.scala:260` and `TestRunner.scala:81`, not
`ThreadLocal.withInitial`; `ThreadFactory` and `HttpHandler` are anonymous classes, not SAM
lambdas. Every `Either` goes through a projection — `.right.map`, `.right.flatMap`,
`.left.map`, and `res.right.toOption` at `TestRunner.scala:722`; I found no `map`/`flatMap`/
`foreach`/`getOrElse`/`toOption` applied to an `Either` directly (every `getOrElse` in the
new files is on an `Option`). Stable-identifier patterns are avoided with guards
(`Request.delivery`, `:131-132`). Non-ASCII appears only as `§` inside comments.

## 7. Scope and docs

Only `relational/package.scala`, `sql/SqlEmitter.scala`, `TestDoc.scala` and the two tracker
documents are modified; the rest is new files. Nothing under `core/examples/` (the example
report is under `core/src/test/resources/doc/`, so the corpus count is unmoved — confirmed
by the cited 89/79/0). `tracker/repl-classpath.txt` is untouched. `bin/ermine-serve` is +x
and the same shape as `bin/ermine-schema`. The design note's §3.7d and the plan's walkthrough
are short and, apart from fixes 2 and 4, accurate — I checked the walkthrough against a live
server rather than trusting the transcript.

## 8. Vacuity

The implementer's two mutants (`mutantA.log`, `mutantB.log`) are the right shape: each
falsifies a disjoint pair of properties and leaves the rest green, which is the evidence
that the properties discriminate rather than all firing on any change. I ran a third of my
own — `Runner.data`'s unknown-token `NotFound` replaced by `200` with `{}`
(`Runner.scala:338`) — and (b2) ("an unknown module or binding is 404", whose last clause
fetches a bogus token) and (b5) ("an expired token is 404") both failed, while (a), (c),
(d), (e) and the rest stayed green, i.e. the 404 path is genuinely pinned and the mutation
did not leak into the happy path. Reverted and verified by md5 and by grep.

The anti-vacuity guards inside the properties are real, not decorative: (a) asserts all six
relation forms occurred, that both kinds occurred, and that at least one token was
re-requested; (b1) asserts more than 20 mutations were actually refused; (c-cov)/(a-cov) in
TestDoc do the same job there.

# Required fixes

**1. The evaluation monitor is per-`Runner`, but part of what it guards is process-global.**
`core/src/main/scala/com/clarifi/reporting/ermine/json/Runner.scala:278`
(`private val evalLock = new Object`).
*Failure scenario.* The lock's stated justification (class comment, `:232-247`) is the
process-global `DataConDecl` registry, `Supply`, and the non-volatile `Runtime.Thunk.state`.
The registry really is process-global — two static `ConcurrentHashMap`s at
`ermine/DataConDecl.scala:55-56`, written by `Session.loadModules` via
`session/Session.scala:915` — and its semantics are last-writer-wins per `Global`. Two
`Runner` instances in one JVM therefore evaluate concurrently with no mutual exclusion: two
tenants whose modules share a module name and declare the same `data` type overwrite each
other's `DataConDecl`, after which `Decode`/`Encode` read the wrong constructor field list.
J2a already had to fix exactly this shape of bug once ("the PROCESS-GLOBAL `DataConDecl`
registry turns into a cross-property race", plan handoff log, 2026-09-16 ~09:30). This is
not hypothetical guidance-wise: `report-J3c.md` open issue 1 tells operators to run
**"One `Runner` per tenant"**, and `TestRunner` itself builds two (`runner` and
`clockedRunner`, `:100` and `:112`, both `lazy val`s reachable from properties that
ScalaCheck runs concurrently), so their boots can overlap today.
*Fix.* Move the monitor to the companion: add `private[json] val evalLock = new Object` to
`object Runner` and make the field `private val evalLock = Runner.evalLock`. Two lines, no
behavioural change for a single runner (which is all `ServeMain` builds), and it removes a
latent test flake. If a process-wide monitor is judged too coarse, the alternative is to
delete the "one `Runner` per tenant" recommendation from open issue 1 and state in the class
comment that one `Runner` per JVM is the supported configuration — but one of the two must
happen before this lands, because the shipped guidance is currently unsafe on the shipped
design.

**2. The plan's wire contract contradicts decision 1 about `path`.**
`tracker/JSON-STAGE3-PLAN.md:155-157` (added by this stage): "Errors are
`{"error":{"path":..,"message":..}}` with `path` null when the failure is not at a place in
the request".
*Failure scenario.* A 500 carries a path into the **response document** (`Runner.scala:446`,
`:459`), which is by definition not a place in the request, so the plan's own sentence says
that path should have been `null`. The plan is the binding wire contract and J3d is about to
generate a TypeScript client from it; an author who reads only this sentence will treat a
non-null `path` as a JSON pointer into the request they sent.
*Fix.* Reword to match the design note's table (`JSON-API-DESIGN.md` §3.7d): `path` is a
path into the request for a 400, `null` for 404/405/413, and for a 500 the path of the
failing node in the **response document** when there is one.

**3. Three comments now describe the opposite of what this stage shipped.**
`core/src/main/scala/com/clarifi/reporting/ermine/json/Write.scala:463-465` says
"`EffectfulProcedure.withDriver` (`relational/package.scala:121-128`), which has no
`finally`" — it now has one, and the code moved to `:133-136`.
`scalacheck-binding/src/main/scala/TestDoc.scala:128-129` ("`withDriver` only runs it when
the machine finishes") and `:961-963` ("which has no `finally`") say the same thing.
*Failure scenario.* These three are the justification the 2.11 porter and J3d will read for
the `Stop` exit in `Write.Sink`; leaving them asserting the pre-fix behaviour of the very
function this stage changes will send someone to re-derive or re-"fix" it.
*Fix.* Update the three comments: `withDriver` tears down in a `finally` as of J3c, and
`Stop` remains the exit the writer uses so a refused row keeps the buffered-prefix semantics
and its `WriteFailure` (that reason is unchanged and still correct).

**4. The design note undercounts the properties.** `tracker/JSON-API-DESIGN.md:969` and
`:1052` both say `TestRunner` has 15 properties. There are 16 — my re-run lists (a), (b1)…
(b7), (c), (c-routes), (log), (d), (e), (ex), (sql-guid), (sql-teardown) — and the report and
the plan both say 16. *Fix.* 15 -> 16 in both places.

# Suggestions (not required)

(a) `(d)` warms every module serially before the concurrent phase (`TestRunner.scala:742`),
so `compile()`/`Session.loadModules` is never the thing under contention in the property
that is about contention. Consider firing the threads at modules that have not been compiled
yet and computing the serial reference afterwards.

(b) `(d)`'s `results.put(i, …)` (`:756`) overwrites round 1 with round 2; keep both rounds so
a wrong first answer cannot hide.

(c) Every string the suite generates is `Gen.alphaNumChar` (`TestRunner.scala:130`,
`TestSchema.litString:109-110`), so no response body in any property contains a multi-byte
character and the `Content-Length` assertion in `http()` (`:622-624`) could not catch a
`text.length` regression. The code is right — I verified it by hand — but one non-ASCII case
(a `settings` value, or a module name in `(c-routes)`) would pin it.

(d) A 413 answers without draining the request body, so a client still sending sees the
connection close: with a 5 MB body against the 4 MiB default, `curl` reports the 413 and
then exits 56. Fine for a back-end server; worth a line in the design note.

(e) `/health` takes `evalLock` (`Runner.loadedModules`, `:301`), so a slow report makes the
liveness probe hang exactly when an operator needs an answer — and open issue 5 says there
is no timeout on `apply1`. Caching the module set in a volatile updated under the lock would
decouple them.

(f) `Server.dispatch` catches `NonFatal` only (`:82`). There is no reachable
`StackOverflowError` today (I probed the boundary), but a `case _: StackOverflowError` beside
it would keep the "every failure a client sees has one shape" promise if a future decoder
recurses deeper than argonaut's parser.

(g) A HEAD response sends no `Content-Length` (`Server.scala:180` passes `-1` for HEAD);
RFC 7230 says a HEAD response should carry the length a GET would. HEAD is not in the
contract, so this is cosmetic.

(h) `Server.decode` (`:210-212`) double-decodes: `URI.getPath` has already percent-decoded,
so `/report/%252e%252e` arrives at `moduleNameOk` as `..`. It is refused (404, verified),
and validation being last is what makes it safe — but the second decode buys nothing.

(i) `withDriver`'s `finally` masks the original exception when `teardown()` throws;
`e.addSuppressed(t)` (JDK 7+) would keep both. The comment already owns the trade-off.

(j) `Allow: GET` on `/health` and `/data` omits `HEAD`, which both routes accept.

(k) No CORS headers anywhere. J3d's TypeScript client cannot call this server from a browser
on another origin; worth one line in §3.7d so J3d is not surprised.

(l) One sentence in §3.7d on why a bad report *signature* is a 400 while a bad report *value*
is a 500 (the brief asked for the former; decision 1 argues the latter).

# Verdict

**FIX-THEN-LAND** — fix 1 (two lines in `Runner.scala`, or the documentary alternative) and
the three documentary fixes 2, 3 and 4. Everything else is sound: the wire contract is
implemented as specified, the concurrency claims are true as far as the interpreter is
concerned, both DB tickets are correctly fixed and properly pinned, the properties
discriminate (three independent mutants, one of them mine), and the suites are green on a
re-run I did myself (103/103).
