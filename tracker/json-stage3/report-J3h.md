# J3h: one step interpreter for call, splice and token (branch `json-unify`, worktree `ermine-scala-wt-json-unify`)

Base J3g 5e37cced. Nothing committed; the tree is dirty for review (`git diff --stat`: 8 files,
484 insertions, 273 deletions, of which `tracker/json-stage3/brief-J3h-interp.md` is the
orchestrator's own edit, not mine; plus the new untracked `json/Interp.scala`, 242 lines, and
`tracker/json-stage3/logs/`).

There is now one loop over one step type. `json/Interp.scala` holds `Step`
(`Eval`/`Call`/`Emit`/`Splice`/`Token`) and the driver `Interp.run`, the only place in the JSON
stack where a scan happens. `Write.doc` is "segments to steps, then run"; `Write.relation` (the
`/data/<token>` re-request) is a one-`Splice` run; `Runner.render` is "first `Eval` under
`evalLock` outside the connection, then run inside one `cfg.run.run`". `Runner.interpret`,
`renderFetch`, `write` and `ScanFailed` are gone. A fetch scan is now a `RelationStats` at
`$.fetch[n]` in the same `WriteStats`, an INFO line in the same shape, and, when it throws, a
`WriteFailure` at that path.

Gates: `scripts/gate.sh run commit` 3/3 PASS, the five suites 114/114 (109 existing + 5 new),
the client untouched. The required mutation (a `Call` that drops its rows) is red on 9 properties
including (fx2) and (ip-stats).

## What was built

| File | What |
|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/json/Interp.scala` (NEW, 242 lines) | `sealed abstract class Step` with `Eval(next: () => List[Step])`, `Call(order, ext, path, k: List[Record] => List[Step])`, `Emit(text)`, `Splice(data, threshold)`, `Token(data)`; `object Interp` with `run[G](steps, out, cfg, cache)(implicit Scanner[G], Guard[G]): G[WriteStats]` and the wire arms `inlined`/`deferred`/`columns`/`logged`/`failure`/`attempt`/`delay` moved from `Write` unchanged. The driver is a work LIST: the steps an `Eval` or a `Call` answers are pushed onto the rest, so the chain of binds is one per step and nothing recurses per row or per document node. |
| `json/Write.scala` | `steps(d, cfg): List[Step]` (segments to steps; `resolve` is consulted ONCE, here, and the threshold it allows rides on the `Splice`); `doc` = `Interp.run(steps(d, cfg), ..)`; `relation(token, ..)` = `cache.get` then a one-`Splice` run. `one`, `inlined`, `deferred`, `columns`, `logged`, `failure`, `attempt`, `delay` deleted (moved). `segments`, `resolve`, `Rows`, `WriteConfig`, `RelationStats`, `WriteStats`, `WriteFailure`, `Guard`, `Strategy` unchanged; `WriteConfig`'s `require` now spells out "inline or deferred" rather than "not ByRequest" (the enum gained a fourth case). Object comment rewritten. |
| `json/Runner.scala` | `render` = report -> decode -> `evalStep(.., n = 1, wcfg)` under `evalLock` outside the connection -> `drive`. `evalStep` answers `Either[RunError, List[Step]]`: `Done`/a bare `Node` becomes `Write.steps(Doc.document(doc, settings), wcfg)`, a `Scan` becomes one `Step.Call` whose continuation is `stepping` (the same function on the rows, failing by `Abort`). `drive` runs the stream in one `cfg.run.run` and maps `Abort`/`WriteFailure`/`NonFatal` to a `RunError`. `interpret`, `renderFetch`, `write`, `ScanFailed` deleted; `Abort` and `Runner.fetchPath(n)` added. Class doc comment (the boxed pipeline) and the per-request paragraph rewritten. |
| `json/Encode.scala` | `Delivery.Fetched` ("fetched"), with a comment saying it is a statistic and never a value's delivery; `ErmineJson.rel` gained its (unreachable) case so the match stays total. |
| `scalacheck-binding/src/main/scala/TestRunner.scala` | `renderStats` (a render that keeps the `WriteStats`); `RecordingScanner` now throws on a literal relation whose first row's `rgName` is `BOOM` (the only way a generated Ermine report can fail a scan: the stdlib has no `table` primitive); `StatsCase` + `statsCase` generator; properties (ip-stats), (ip-fail), (ip-stack). |
| `scalacheck-binding/src/main/scala/TestDoc.scala` | `fetchProgram` (a step program shaped like a fetching report's: `Eval` -> `Call` -> `Eval` -> ... -> the document's `Splice`s) + `progGen`; properties (ip-fail) (driver level, over random programs) and (ip-stack) (2,000 inline relations). |
| `tracker/JSON-API-DESIGN.md` | New section 3.4d "One interpreter: call, splice and token as one step stream": the step table, what each thing became, the four decisions, and the measured stack ceiling. |
| `tracker/JSON-STAGE3-PLAN.md` | J3h row in the stages table; handoff entry; the open ticket "a cap on fetched rows" (decision 3) written out in it. |

## The four decisions, as made

| # | Decision | As made |
|---|---|---|
| 1 | **Stats** | A `Call` yields `RelationStats(path = "$.fetch[n]", delivery = Delivery.Fetched, columns = 0, rows = the records handed to the continuation, scanned = the same, bytes = 0, millis = from the scan's start)`, logged on `ermine.json.doc` through the unchanged `RelationStats.line`. `WriteStats.relations` holds every step's entry in EXECUTION order, so the fetch scans come first and the wire relations follow in document order. `n` is the scan's 1-based position in the report -- the number `ScanFailed` carried -- and it is assigned by `Runner.evalStep`, not by the driver: the `Call` step carries its own `path`, as `Splice`/`Token` carry `data.path`. I added `Delivery.Fetched` rather than a separate field after checking that `Delivery` is NOT exported: `Wire.scala` has its own strings (`Wire.Inline`, `Wire.Deferred`) for the `kind` on the wire, `Schema.scala`/`Zod.scala` never mention `Delivery`, and its only uses are `Doc.Data`, the two `JsonBuilder.rel` implementations, `Write.resolve` and `RelationStats`. |
| 2 | **Failure** | One exception type. A fetch scan that throws is `WriteFailure("$.fetch[n]", msg, completed, cause)` where `completed` is every step finished before it, fetch scans included; the runner's 500 is therefore `cannot write $.fetch[n]: <why>` with `error.path = "$.fetch[n]"`, the same sentence and the same path field a wire relation gets. `ScanFailed` is deleted. A throwing CONTINUATION (Ermine code) is unchanged: `<module>.report failed: <why>`, `error.path` null. NO existing test expectation changed (see below): (fx-err) is about a throwing continuation and still passes unchanged, (fxl-conn) asserts statuses and connection counts. The driver knows nothing of `RunError`, so an evaluation failure raised inside it travels as `Runner.Abort` (a `NoStackTrace` carrier) and `drive` unwraps it. |
| 3 | **Threshold** | `data.threshold` does NOT apply to a `Call`: a fetch scan reads every row, as J3f/J3g did. (ip-stats) pins it -- a third of its cases carry a threshold of 0..4 and the `$.fetch[n]` entries still report every row of the relation. Written up as the open ticket "a cap on fetched rows" in the plan's J3h handoff entry, with the reason it is not a one-line change (a cap needs a way for the report to say what to do when it hits one). |
| 4 | **Order of effects** | Byte-identical output. The wire relations still scan in document order after the last `Eval`; nothing is reordered or batched. Evidence: the 109 properties of the five suites passed with NO test change after the refactor (`j3h-suites-1.log:480`), among them (fxl-sugar), which compares a pure report and the same body under `done` byte for byte over 20 generated documents, the `TestDoc` wire-format pins, and (c), which compares in-process and HTTP bodies byte for byte. |

## Decisions the brief did not fix

| Decision | Choice and why |
|---|---|
| `Eval(next: () => List[Step])`, not `Eval(next: () => Runtime)` | The brief's table spells the step with a `Runtime`. That would put `Runtime`, `evalLock`, `DoneCon`/`ScanCon`, `Doc.fromRuntime` and the runner's error vocabulary inside the driver. Instead the runner supplies a thunk that answers the steps that follow: `Interp` imports nothing of the Ermine evaluator (its imports are `Record`, `SortOrder`, `Ext`, `Scanner`, `Plan`/`Process`), and the same driver serves `Write.doc`, which has no Ermine at all. The step table of 3.4d says so. |
| `Call` carries its `path`; `Splice` carries its `threshold` | Both keep the driver free of policy: the scan numbering is the report's (`Runner.fetchPath(n)`), and the delivery/threshold resolution is the document's (`Write.steps` calls `Write.resolve` once). The driver never consults `cfg` except for the clock. |
| How a `RunError` leaves the driver | `Runner.Abort(error)`, caught in `drive`. The alternative -- threading `Either[RunError, _]` through `run` -- would put the runner's failure type in the driver's signature and in `Write.doc`'s. Thrown-and-caught is what `WriteFailure` already does (`Write`'s comment: "thrown when the `G` action RUNS, never returned"). |
| Where a fetch scan's `columns` count goes | 0. The `Ext` has a header (`Typer.extTyper` could compute one), but nothing of a fetch scan is written, so the column count would be a number about a thing that does not exist on the wire. `RelationStats.line` does not print it. |
| Where (ip-fail) lives | Both places. `TestRunner (ip-fail)` is end to end and pins the 500's path and sentence for a fetch scan and for a wire relation. `TestDoc (ip-fail)` is over random STEP PROGRAMS through the `Id` scanner and pins `completed` (the thing an HTTP response cannot show), the rows each continuation received, and the output prefix. |
| How a generated Ermine report can fail a SCAN | `RecordingScanner` throws when it is asked to scan a literal relation whose first row's `rgName` is `BOOM`. There is no `table` primitive in the stdlib (checked: `modules/` has no relation-by-name constructor), so a plan over a missing table cannot be written in Ermine, and J3g's (fx-err) could only reach a throwing continuation. No other property generates that name. |
| (ip-stack)'s document arm runs on its own thread | The 2,000-relation document is written on a thread created with a 16 MB stack. Measured reason below: on the test pool's default stack the ceiling of the J3g loop and of the J3h driver are both around 2,000 and move with the JIT, so at 2,000 the property would be a coin toss about the JIT rather than about the code. The 2,000-SCAN arm (`TestRunner (ip-stack)`, the `DB` path, the real one) runs on the ordinary test thread and passes. |

## Departures from the brief

| Brief | What was done | Why |
|---|---|---|
| `Eval(next: () => Runtime)`; `Call(order, ext, k)`; `Splice(data)` | `Eval(() => List[Step])`, `Call(order, ext, path, k)`, `Splice(data, threshold)` | The three rows above: the driver stays free of the Ermine evaluator, of the scan numbering and of the delivery policy. The five step KINDS and what each does are the brief's. |
| "(ip-stack) ... likewise a document with 2,000 inline relations, as `Write.doc` promises today" | 2,000, but on a thread whose stack the property names (16 MB) | `Write.doc`'s promise was written for `DB`. On the strict `Id` path the whole chain is on the JVM stack, and 2,000 relations on the test pool's default stack overflowed in one run of my first version (`j3h-suites-2.log:392`, `StackOverflowError`). I then measured the OLD loop and the new driver side by side in one JVM (below): the ceiling is the same order and JIT-dependent, i.e. this is not a J3h regression but a property that cannot be written at 2,000 on a default stack and mean anything. |

## Anti-vacuity and the mutation check

- **MUTATION (required by the brief).** `Interp.call`'s `val got = rows.toList` replaced by
  `val got = Nil: List[Record]` -- the `Call` scans and then drops the rows. `core/testOnly
  *TestRunner`: `Failed: Total 32, Failed 9, Errors 1, Passed 22`
  (`tracker/json-stage3/logs/j3h-mutation-call.log:112`). (fx2) red -- `statuses 500/500 ...
  FetchRunning.report produced a document that cannot be encoded: an empty relation built from no
  rows carries no columns` (`:10-12`); (ip-stats) red on all 16 cases --
  `want List(($.fetch[1],fetched,2), ($.fetch[2],fetched,1), ($.children[2].props,inline,1))`,
  `got List(($.fetch[1],fetched,0), ($.fetch[2],fetched,0), ($.children[2].props,inline,1))`
  (`:84-90`); also red: (fx1), (fx3), (fx4), (fx5), (fxl-conn), (fxl-headline), (fxl-order),
  (ip-stack). Reverted from a byte-copy taken before the edit and verified with `diff`; the
  report's final suite run is after the revert.
- **(ip-stats) distribution, printed once per run**: `16 reports, 33 fetch scans over 111 rows,
  32 wire relations deferredx17 inlinex15` (`j3h-suites-4.log:63`). The property asserts at
  least 6 reports with two or more scans (so the ORDER of the fetch entries is tested), at least
  30 fetched rows in all, and that both wire delivery arms occurred.
- **(ip-fail) is `forAllNoShrink` over 100 random programs** (1-3 fetch calls, 1-3 wire
  relations, the failure at a random one of them) and asserts the failing path, `completed`
  exactly, the number of `Fetched` entries in `completed`, the rows each continuation received,
  the message, and the output prefix -- so it cannot pass on a run that failed at the wrong step
  or wrote the wrong text.
- **No existing expectation was changed.** The refactor was run against the 109 unchanged
  properties before a single new one was written: `Passed: Total 109, Failed 0, Errors 0,
  Passed 109` (`tracker/json-stage3/logs/j3h-suites-1.log:480`). That is the byte-identity and
  error-text evidence for decisions 2 and 4.

## Changed test expectations

None. No assertion, message or expected value in `TestRunner`, `TestDoc`, `TestWidgets`,
`TestJson` or `TestSchema` was edited; the diff in the two suite files is additions plus the
`RecordingScanner.scanExt` change (it now answers a throwing action for one reserved mark, and
`note` returns a `Boolean` instead of `Unit`), which no existing property observes -- (fxl-order),
the only user of that scanner, is green with the same distribution as J3g:
`24 trees, 95 leaf scans; leaves per tree 1x6 2x4 3x6 4x5 10x1 13x1 20x1; nodes bind_Fetch=14
gridF=3 hflowF=11 leaf=95 sequence_Fetch=8 tabbedF=2 vflowF=12` (`j3h-suites-4.log`, identical to
`suites-4.log:411` of J3g).

Error texts: the ONLY change is the fetch-scan 500, from `<module>.report: scan n failed: <why>`
to `cannot write $.fetch[n]: <why>` with `error.path = "$.fetch[n]"` (decision 2). Nothing
asserted the old text: (fx-err) is about a throwing continuation (`error "boom after the scan"`),
whose message still names the report. Unchanged: the (b3) refusal, the encode 500, the
evaluation 500, and every `Write` message.

## Gates

| Gate | Result | Log |
|---|---|---|
| `scripts/gate.sh run commit` (key `8a62cdccb7fa4b129cc0ed3ceb1c296d0d9f8e3e`, the tree of this stage with the design note and plan edits and without this report file) | `compile PASS 5s compiled`; `corpus PASS 53s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected`; `lsp PASS 51s PASS lsp (582 checks)` | `tracker/json-stage3/logs/j3h-gate-final.log`; per-gate logs under `/home/dmitry/research/ermine/ermine-scala/.gate-cache/8a62cdccb7fa4b129cc0ed3ceb1c296d0d9f8e3e/` |
| the same gate on the code before the doc edits (key `c5b3346422f85db15ce2880cc33b6dd4b837b9fb`) | `compile PASS 11s compiled`; `corpus PASS 51s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected`; `lsp PASS 51s PASS lsp (582 checks)` | `tracker/json-stage3/logs/j3h-gate-commit.log` |
| `sbt -batch 'core/testOnly *TestRunner *TestWidgets *TestDoc *TestJson *TestSchema'` (final) | `Passed: Total 114, Failed 0, Errors 0, Passed 114`, 71 s | `tracker/json-stage3/logs/j3h-suites-4.log:484` |
| the same five suites after the refactor, BEFORE any new property | `Passed: Total 109, Failed 0, Errors 0, Passed 109` | `tracker/json-stage3/logs/j3h-suites-1.log:480` |
| the mutation (evidence, not a gate) | `Failed: Total 32, Failed 9, Errors 1, Passed 22` | `tracker/json-stage3/logs/j3h-mutation-call.log:112` |
| the stack probe (evidence, not a gate; its two probe files were deleted after the run) | `inline relations one document survives: J3g loop 2240, J3h driver 2048` (the coldest of 101 measurements), `3200 / 7168` once, `6208 / 8128` for the other 99; `2000 survives: J3g true, J3h true` every time | `tracker/json-stage3/logs/j3h-stack-probe.log` |
| (ip-stack), the `DB` arm | `2000 sequential scans in 14176 ms, 2000 fetch entries` (16,416 ms in the run before) | `tracker/json-stage3/logs/j3h-suites-4.log:76` |
| the client | UNTOUCHED: `git status --short` lists no file under `client/`, and nothing in this stage alters the wire (the response bytes are the same, which (fxl-sugar) and the `TestDoc` pins assert). `npm test` NOT run. | `git status --short` |

The full `core/test` was NOT run (the brief forbids it). `tracker/repl-classpath.txt` is
untouched (`gate.sh` swaps and restores it). The gate key of the FINAL tree differs from the one
above by this file alone.

## Open issues

- **A cap on fetched rows** (decision 3, now a ticket in the plan). A `Fetch` scan reads every
  row of its plan into a `ListBuffer` and then into an Ermine list; a report that scans a large
  relation materialises it twice over in the JVM. `data.threshold` deliberately does not apply.
  The ticket needs a wire/language answer (a `Fetch` that fails at the cap, or one that tells the
  report it was truncated), not a driver change.
- **The strict path's stack ceiling** is about 2,000 relations or scans and moves with the JIT
  (measured above). It is the same before and after J3h and applies to `G = Id` (the test
  scanners); the `DB` path carried 2,000 scans and 2,000 relations in these runs. Raising it
  needs a trampolined driver, i.e. a `BindRec[G]` beside `Scanner[G]`'s `Monad`, which is a
  change to the scanner contract and was out of scope here.
- **(ip-stack)'s 2,000-scan arm costs 14-28 s** of the suite. It is the only property in the
  five suites that takes over ten seconds; if the suite budget matters more than the pin, the
  number to lower is `n` in that property.
- **The 2.11 port.** Nothing was ported. The new Scala is in the shared dialect: no `given`/
  `using`/`enum`/`extension`/`export`/`derives`, `Either` only through `.right`, no `LazyList`,
  no `CollectionConverters`, no JDK 9+ API; `Interp.scala`'s only collection is
  `scala.collection.mutable.ListBuffer`.
- **`Layout.Scan` (the old `Report f z` runner) and the legacy `Report`/`Writer` path are
  untouched**, as in J3f/J3g.
- **Not yet a step**: a cached `Fetch` behind a token and a batched `ScanMany` are the two kinds
  of work section 3.4d says are now a new step rather than a third loop. Neither is implemented.

## R1/R2 applied (review fixes, 2026-09-18)

`review-J3h.md` is FIX-THEN-LAND with two required fixes. Both applied in the worktree; nothing
else changed, nothing committed.

**R1. The pure document was serialised to text under `evalLock`.** `evalStep`'s `document(node)`
called `Write.steps(Doc.document(d, cfg.settings), wcfg)` inside `evalLock.synchronized`, so
`Write.segments` -- the JSON text of every pure node, including every row a fetching report folds
into a widget (`FetchRunning`, `FetchTopN`) -- ran under the PROCESS-WIDE lock. J3g printed
outside it.

| Change | File |
|---|---|
| `evalStep` split in two: `evaluate(rep, next, n, wcfg): Either[RunError, Either[Doc, List[Step]]]` is the `evalLock.synchronized` part (force the value; `Doc.fromRuntime` when the report is finished, because the WALK reads the runtime; the one `Call` when it asks for rows), and `evalStep` maps `Left(d) => Write.steps(Doc.document(d, cfg.settings), wcfg)` OUTSIDE the lock. `render` and `stepping` are unchanged in shape; both go through `evalStep`, so the first evaluation and every `Call` continuation both print outside the lock | `json/Runner.scala` |
| The doc comment says what the lock covers and why | `json/Runner.scala`, `json/Interp.scala` (`Step.Eval`), `tracker/JSON-API-DESIGN.md` 3.4d |

**R2. The design note said `Runner` builds `Eval` steps; it does not.** Corrected rather than
made true: wrapping the `Call` continuation in an `Eval` would add one more bind per scan to a
chain that is 2,000 deep in `(ip-stack)`, for a documentation nicety.

| Change | File |
|---|---|
| 3.4d's `Eval` row now reads "NOT the runner today -- see below; `TestDoc.fetchProgram` builds them", the `Call` row says its continuation IS the runner's next evaluation step, and a paragraph explains why (the first evaluation must happen before the driver starts, §3.4c; `Eval` is the arm for a stream that extends itself without a scan -- a cached `Fetch`, a batched `ScanMany`) | `tracker/JSON-API-DESIGN.md` |
| The object comment's "`Eval` and `Call` ... are only ever built by `Runner`" corrected to the same effect | `json/Interp.scala` |
| `Rows.Sink`'s comment: `Write.inlined` -> `Interp.inlined` | `json/Write.scala` |

Evidence after the fixes (one run each, as asked):

| Check | Result | Log |
|---|---|---|
| `sbt -batch 'core/testOnly *TestRunner'` | `Passed: Total 32, Failed 0, Errors 0, Passed 32`, 40 s; `(ip-stats) 16 reports, 33 fetch scans over 111 rows, 32 wire relations deferredx17 inlinex15`; `(ip-stack) 2000 sequential scans in 18838 ms, 2000 fetch entries` | `tracker/json-stage3/logs/j3h-suites-r.log:142`, `:132`, `:139` |
| `scripts/gate.sh run commit` (key `1a27d452b900115089d0d73380da638a0253b19f`) | `compile PASS 7s compiled`; `corpus PASS 54s 89 loaded / 79 rejected / 0 unknown of 168; 0 differ from expected`; `lsp PASS 53s PASS lsp (582 checks)` | `tracker/json-stage3/logs/j3h-gate-r.log` |
| scope | `git status --porcelain client/` empty; HEAD still 5e37cced (nothing committed) | -- |

`TestDoc`, `TestWidgets`, `TestJson` and `TestSchema` were NOT re-run: R1 is inside
`Runner.evalStep` (only `TestRunner` reaches it) and R2 is comments; their green is
`j3h-suites-4.log:484` (114/114) and the reviewer's `review-j3h-suites.log:508` (130/130).
The reviewer's optional suggestions 1-4 were not taken.
