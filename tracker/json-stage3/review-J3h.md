# Review of J3h: one step interpreter (branch `json-unify`, base 910f288b)

Reviewer: independent (did not write the stage). Reviewed the uncommitted diff against
910f288b (8 tracked files) plus the untracked `json/Interp.scala` and `report-J3h.md`.
Logs I wrote are under `tracker/json-stage3/logs/review-j3h-*.log`. Time: about 1 h 15 min.

## Verdict summary

The stage does what the brief asks: one driver (`Interp.run`), one failure type, fetch scans
in `WriteStats`, byte-identical wire output, five suites green with no changed expectation.
Two things need fixing before landing, both small: the runner now serialises the whole pure
document to text INSIDE the process-wide `evalLock` (J3g did it outside), and the design note's
step table says `Runner` builds `Eval` steps when it never does. The rest is optional.

## 1. Interp.scala, the driver

| Question | Finding |
|---|---|
| Every scan outside `evalLock`, every evaluation inside it? | Yes. The only scans are `Interp.call` (`Interp.scala:135`) and `Interp.inlined` (`:159`), neither takes a lock. Evaluation happens in `Runner.evalStep` (`Runner.scala:521-522`, `evalLock.synchronized`), reached either directly from `render` (first step) or through the `Call` continuation `stepping` (`Runner.scala:536-537`), which the driver invokes at `Interp.scala:111` after the scan's bind has returned. |
| First evaluation outside `cfg.run.run`? | Yes: `render` calls `evalStep(.., 1, wcfg)` and only `drive` opens the connection (`Runner.scala:367`, `:495`). `(fxl-conn)` green in my run (`review-j3h-suites.log:508`, 130/130). |
| Constant JVM stack per step for `G = DB`? | `DB[A] = Connection => A` (`backends.scala:6`), so each `M.bind` adds one `apply` frame at run time and the depth is linear in STEPS, the shape `Write.doc` had. The work list (`go(k(rows) ++ tl, st)`, `go(more ++ tl, st)`) means a `Call`'s answer does not nest. `TestRunner (ip-stack)`: 2,000 sequential `bind_Fetch` scans through SQLite on the ordinary sbt test thread (`Test / fork := false`, `build.sbt:94`): 18,364 ms in my run (`review-j3h-suites.log:504`), 14,176 ms in the implementer's (`j3h-suites-4.log:76`). |
| The `Id` path's ~2,000 ceiling pre-existing? | Credible from `j3h-stack-probe.log`: 101 measurements in one JVM, coldest `J3g loop 2240, J3h driver 2048`, warm `6208 / 8128`, `2000 survives: J3g true, J3h true` on every line. The probe source was deleted, so what "J3g loop" measured is unverified beyond the log; the J3h driver is one `go` frame set per step as the old `Write.doc` was, so the same order is what I would expect. |
| A throwing `Call` tears the scan down? | Same contract as `inlined`: the scanner's own (the guard only maps the exception). `collect` never `Stop`s, so nothing is abandoned mid-scan by the driver. Unchanged from J3g's `interpret`. |
| `completed` right? | `call`'s `fail` reads `st.done.toList` at failure time (`Interp.scala:133`); `Splice` and `Token` read it when `go` reaches them, which for `DB` is at run time inside the previous bind's continuation. Fetch entries are included. Pinned by `TestDoc (ip-fail)`; my mutation A (below) confirms the pin. |
| `WriteFailure` paths for fetch vs wire? | `$.fetch[n]` from `Runner.fetchPath` carried on the `Call`; the relation's `data.path` on a `Splice`/`Token`. `TestRunner (ip-fail)` pins both 500s (`error.path` `$.fetch[2]` and `$.children[1].props`). |
| `Runner.Abort` ever escapes `drive`? | No. It is thrown only by `stepping`, which runs only inside a `Call` continuation, i.e. inside `Interp.run` inside `cfg.run.run` inside `drive`'s `try` (`Runner.scala:495-500`). It cannot be wrapped into a `WriteFailure`: `Guard.db.guard` wraps only the scan action (`Write.scala:76`), and `attempt` wraps only the write bodies; the continuation runs outside both. `Death`/`NonFatal` inside evaluation are caught by `evalStep` first. |
| Partial output leaking after k fetch scans? | `drive` answers `Left` on any throw and the HTTP server sends `out` only on `Right` (unchanged). `Call` writes nothing, so a failure during the fetch phase leaves `out` empty; `TestDoc (ip-fail)` asserts the output prefix in both arms. |
| Resource on failure | `Run.run` (`Run.scala:162-170`) has no catch; `freshResource` releases the connection and the thread-local is reset in `finally`. Same as J3g. |

Note: `Runner` never constructs a `Step.Eval` (grep: the only `Step.` in `Runner.scala` is the
`Call` at line 536). The first evaluation is `render`'s direct `evalStep`; every later one is the
`Call` continuation. The `Eval` arm of the driver is exercised only by `TestDoc.fetchProgram`.
Behaviourally equivalent; see fix 2.

## 2. Byte identity

- The wire arms `inlined`, `deferred`, `columns`, `logged`, `failure`, `attempt`, `delay` were
  diffed against `git show 910f288b:.../Write.scala`: identical except two continuation-line
  indents and a separator comment (`diff` of the two extracted blocks, 87 vs 89 lines).
- Threshold semantics: `Write.resolve` is unchanged; `Write.steps` applies it once per relation
  exactly as the old `one` did (`Deferred` -> `Token`, else `Splice(data, threshold)`); so a bare
  relation resolved inline whose scan exceeds `t` goes out deferred (`Rows.Sink` unchanged),
  explicit `Inline` gets `None`, explicit `Deferred` never scans.
- `/data/<token>`: `Write.relation` is `Splice(e.data, None)` in a fresh `WriteConfig(clock)`,
  so no threshold, `completed = Nil`, `WriteStats(List(rs), rs.bytes)` as before. `Runner.data`
  untouched.
- Evidence: 109/109 unchanged properties after the refactor and before any new one
  (`j3h-suites-1.log:480`), including `(fxl-sugar)`, the `TestDoc` wire pins and `(c)`.

## 3. The four decisions and `Delivery.Fetched`

All four are as the brief required and as 3.4d states. `Delivery.Fetched` and `columns = 0`
are safe at every `Delivery` match: `ErmineJson.rel` (`Encode.scala:682`, a `Left`),
`Doc.rel` (passes delivery through, `Doc.scala:195`), `ArgonautJson.rel` (refuses all),
`Write.resolve` (`case explicit`; a `Fetched` `Doc.Data` cannot exist since no builder makes
one), `WriteConfig.require` (rewritten to the two allowed values), the test builders in
`TestDoc:529` and `TestSchema:1226` (non-exhaustive but only receive walker deliveries; no
warning in `review-j3h-suites.log`). `RelationStats.columns` is read nowhere but the
constructor; `line` does not print it. `Wire.scala`, `Schema.scala`, `Zod.scala`, `client/`
do not mention `Delivery` (grep).

## 4. Properties

| Property | Judgement |
|---|---|
| `(ip-stats)` | 16 reports, 33 fetch scans over 111 rows, 32 wire relations deferred x17 inline x15 (`review-j3h-suites.log:476`, identical to `j3h-suites-4.log:63`); asserts >= 6 multi-scan reports, >= 30 fetched rows, both wire arms. Not vacuous. |
| `(ip-fail)` TestRunner | Two fixed programs (fetch scan 2 throws; wire relation after a good fetch throws); pins status, `error.path` and the message prefix. A pin beside the TestDoc property, as the standard allows. |
| `(ip-fail)` TestDoc | `forAllNoShrink` over 100 random programs, 1-3 calls and 1-3 splices, failure at a uniformly random step; asserts path, `completed` exactly, the count and rows of fetched entries, what each continuation heard, message and output prefix. No split of Call-vs-Splice failures is printed, but with those ranges both arms are reached many times in 100 cases. |
| `(ip-stack)` DB arm | Real: 2,000 scans, default test thread, path list checked at both ends. |
| `(ip-stack)` Id arm | Weak as a stack pin: 1 row per relation, flat `DArr`, 16 MB stack, n = 2,000 while the warm ceiling on the DEFAULT stack is already 8,128 relations (`j3h-stack-probe.log`). It would pass with a per-step cost several times larger. It is an honest departure (documented in the report and the property comment) but it pins little beyond "runs". See optional 1. |
| `(fxl-order)` | Same distribution as J3g (`review-j3h-suites.log:502`). |

Mutations:

- Implementer's (`Call` drops its rows): `Failed: Total 32, Failed 9, Errors 1, Passed 22`,
  `(fx2)` and `(ip-stats)` red (`j3h-mutation-call.log:10,84,112`).
- Mine, A: `completed` omits `Fetched` entries (both the `Call` failure and the `Splice`
  argument). `TestDoc (ip-fail)` red, "Falsified after 0 passed tests", `completed
  List($ip970193_[0])` vs expected four paths; everything else green, `Failed: Total 54, Failed
  1` (`review-j3h-mutation-completed.log:27-32,876`). So `TestDoc (ip-fail)` is the ONLY guard on
  `completed`, and it works.
- Mine, B: a `Call`'s stats entry prepended instead of appended. Red: `TestDoc (ip-fail)`
  (`completed List($.fetch[2], $.fetch[1])`), `TestRunner (ip-stats)` (`got
  ($.fetch[2],..),($.fetch[1],..)`), `TestRunner (ip-stack)` (`got List("$.fetch[2000]",
  "$.fetch[1999]", ..)`); `Failed: Total 54, Failed 3` (`review-j3h-mutation-order.log:36-41,
  834-843,852-856`).
- Both reverted from a byte copy and verified with `diff` (sha256 of `Interp.scala` equal to the
  copy taken before mutation A: `87a1983d...`).

## 5. Dialect, scope, docs

- Dialect: grep over the added lines for `given|using|enum|extension|export|derives|LazyList|
  CollectionConverters|List.of|isBlank|readString|java.net.http|?=>|import *|as|.toOption|
  Using` finds nothing; `Either` is used only through `.right` and `.left`; the `.map`/
  `.foreach`/`.getOrElse` hits are on `List`, `Option` and argonaut `Json#field` (Option).
  `Abort` is a package-level `private[json]` class, `Step` a sealed abstract class with a
  companion of `final case class`es, both fine on 2.11. Line endings: all five changed Scala
  files are LF (`file`).
- Scope: `git status --short` lists nothing under `client/`, `core/examples/`, and
  `tracker/repl-classpath.txt` is unmodified. The `brief-J3h-interp.md` change is the
  orchestrator's base-commit line, as the report says.
- Docs: 3.4d is short and its four decisions match the code. Plan row, handoff entry and the
  "cap on fetched rows" ticket are present (`JSON-STAGE3-PLAN.md:208, 402-420`). The `Runner`
  boxed pipeline and per-request paragraph and the `Write` object comment describe the new
  shape. Inaccuracies: fix 2 below.

## 6. Re-run and cited gates

- Mine, once: `sbt -batch core/compile core/copyResources 'core/testOnly *TestRunner
  *TestWidgets *TestDoc *TestJson *TestSchema *TestNamedFields'`: `Passed: Total 130, Failed 0,
  Errors 0, Passed 130` (`tracker/json-stage3/logs/review-j3h-suites.log:508`; 114 in the five
  suites + 16 `TestNamedFields`).
- Cited: `j3h-gate-final.log`: `compile PASS 5s`, `corpus PASS 53s 89 loaded / 79 rejected / 0
  unknown of 168; 0 differ from expected`, `lsp PASS 51s PASS lsp (582 checks)`. Nothing in the
  diff touches the loader, the corpus or the LSP, so I did not re-run them. `TestLoopTrace` is
  not in `gate.sh run commit`'s three gates and the diff cannot reach it; not run.
- Full `core/test` not run (forbidden).

## REQUIRED fixes

1. **`Runner.scala:521-543` (`evalStep`): the pure document is serialised to text under
   `evalLock`.** `document(node)` calls `Write.steps(Doc.document(d, cfg.settings), wcfg)`, and
   `Write.steps` runs `Write.segments`, which builds the JSON text of every pure node (`Rows.string`
   escaping, `DRaw(j).nospacesWithOrder` for the settings) -- inside `evalLock.synchronized`. In
   J3g `Doc.document` and `segments` ran outside the lock (`write` built `Write.doc` before
   `cfg.run.run`; `renderFetch` built it in the `DB` bind after `evalStep` had returned). Failure
   scenario: a fetching report folds its scanned rows into pure widgets (`FetchRunning`,
   `FetchTopN` do exactly this), so the text of every fetched row is now produced while holding
   the PROCESS-WIDE lock, and every other request's evaluation queues behind it; the `Runner`
   comment's "SCANNING AND WRITING ARE CONCURRENT ... nothing in `Doc`, `Write` or `Rows` reads
   the session" is no longer what happens. Fix: keep only `Doc.fromRuntime` under the lock and
   build the steps after it, e.g. have the `synchronized` block answer
   `Either[RunError, Either[Doc, List[Step]]]` (or a small sealed pair) and map
   `Left(d) => Write.steps(Doc.document(d, cfg.settings), wcfg)` outside it; `stepping` and
   `render` are unchanged in shape. Re-run `*TestRunner` only.

2. **Design note 3.4d step table (`tracker/JSON-API-DESIGN.md:550`) and `Write.scala:359`.**
   The `Eval` row says "Built by `Runner.evalStep`"; `Runner` never builds a `Step.Eval` (the
   first evaluation is `render`'s direct `evalStep` call, later ones the `Call` continuation).
   Either say so ("only `TestDoc` builds one; the runner's evaluations are the first `evalStep`
   and the `Call` continuations") or make `evalStep`'s `Call` continuation answer
   `List(Step.Eval(() => stepping(..)))` so the table is true (either is fine; the second also
   exercises the driver's `Eval` arm in production). `Write.scala:359` (the `Rows.Sink` comment)
   still says `Write.inlined`; it is `Interp.inlined`.

## Optional suggestions

1. `TestDoc (ip-stack)`: make the document arm mean something -- run it through `DB` on SQLite
   on the ordinary test thread, as `(b)` does, which is the promise `Write.doc` actually made
   ("for `DB` ... thousands are fine"); or, if it stays on `Id` with 16 MB, raise `n` to what
   that budget is known to carry (the probe says 8,128 on the default stack warm) so a doubled
   per-step cost would show.
2. `TestDoc (ip-fail)`: print how many of the 100 cases failed at a `Call` vs a `Splice`, in
   the style of the other distribution lines.
3. 3.4c's table rows (`JSON-API-DESIGN.md:506,508`) still describe `renderFetch` and
   `ScanFailed(n)` as current; one "superseded by 3.4d" note would stop a reader landing there.
4. `(ip-stack)`'s 2,000-scan arm costs 14-18 s of every suite run; the implementer already notes
   `n` is the knob.

FIX-THEN-LAND
