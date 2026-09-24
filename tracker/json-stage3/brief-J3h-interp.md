# J3h: one step interpreter for call, splice and token (Change B)

Branch `json-unify`, worktree `~/research/ermine/ermine-scala-wt-json-unify`, on top of J3g,
committed as 910f288b (your base; the review diff is against it). Budget 6 h. Read `brief-J-common.md`,
`brief-J3g-lift.md` and `report-J3g.md`, design note §3.4a/§3.4b/§3.4c, then `json/Write.scala`
(`segments`, `doc`, `relation`, `resolve`, `one`, `inlined`, `deferred`, `Rows.Sink`),
`json/Runner.scala` (`render`, `renderFetch`, `interpret`, `evalStep`, `data`),
`json/PlanCache.scala`, and the suites `TestDoc`, `TestRunner`, `TestWidgets`.

## Why

Two loops do one thing. `Write.doc` walks a `Doc` of plans and, per relation, scans the plan and
applies a Scala continuation (splice the rows into the output, or mint a token and write the
handle). `Runner.interpret` walks a `Fetch`, and per `Scan` scans the plan and applies an Ermine
continuation. They meet only when the second finishes and calls the first. Each has its own
failure type (`WriteFailure` with a path; `ScanFailed(n)`), and only the first has stats, log
lines and a threshold. After J3h there is ONE loop over ONE step type, so a Fetch scan is logged
and measured like a wire relation, and later work (a cached `Fetch` behind a token, a batched
`ScanMany`) is a new continuation kind, not a third loop.

## Build (`json/`; new file `Interp.scala` or a name you prefer)

A step is one of:

| step | does | today |
|---|---|---|
| `Eval(next: () => Runtime)` | under `evalLock`, force `next()`: `Done node` becomes the segments of its `Doc`; `Scan srt rel k` becomes a `Call` | `evalStep` |
| `Call(order, ext, k)` | scan `ext` OUTSIDE the lock, collect the rows, then `Eval(() => k(rows))` | `interpret` |
| `Emit(text)` | append text | `Write.doc`, `Text` |
| `Splice(data)` | scan `data.ext` into a `Rows.Sink`, write the inline object at `data.path`; threshold as today | `Write.inlined` |
| `Token(data)` | `cache.put`, write the deferred handle | `Write.deferred` |

One driver `run[G](steps, out, cfg, cache)(implicit S: Scanner[G], X: Guard[G]): G[WriteStats]`
consumes a step stream inside one `G` action; `Eval` and `Call` produce further steps (the
stream is lazy or the driver is a loop over a work list; either way constant JVM stack per
relation, as `Write.doc` promises today). `Write.doc` becomes "segments to `Emit`/`Splice`/`Token`
steps, then `run`"; `Write.relation` (the `/data/<token>` path) is a one-`Splice` run;
`Runner.render` is "first `Eval` under the lock outside the connection (J3g), then `run` inside
`cfg.run.run`". `interpret`, `evalStep`, `renderFetch`, `build`, `write` go away or become thin
wrappers; say which in the report.

Decisions this change MAKES (state them in the design note; they are not optional):

1. **Stats.** A `Call` step yields a `RelationStats` like a wire relation: `path` is `$.fetch[n]`
   (n = 1-based position of the scan in the report), `delivery` is a new `Delivery.Fetched`
   (or a separate field -- keep the wire's `Delivery` enum untouched if it is exported anywhere;
   check `Wire.scala`/`Schema`), `rows` = records handed to the continuation, `bytes` = 0,
   `millis` from the scan's start. It is logged on `ermine.json.doc` with the same `line` shape.
   `WriteStats.relations` therefore includes them, in execution order (the fetch scans come
   before every wire relation). Say in the report what `TestRunner` asserted about `relations`
   before and what changed.
2. **Failure.** One exception type. `WriteFailure(path, message, completed, cause)` with path
   `$.fetch[n]` replaces `ScanFailed`; the runner's 500 text for a failed fetch scan may change
   from `": scan n failed: "` to the `cannot write $.fetch[n]: ...` form ONLY if you update
   (fx-err)/(fx-conn) and list the change; a throwing CONTINUATION (Ermine code) stays "the
   report failed" as today.
3. **Threshold.** The request's `data.threshold` does NOT apply to a `Call` step in J3h: an
   in-memory scan reads every row, as J3f does. Write that down as the open ticket it is
   ("a cap on fetched rows") in the plan's open list; do not implement a cap.
4. **Order of effects.** Byte-identical output for every document J3g renders today. Wire
   relations still scan in document order after the last `Eval`; nothing is reordered.

Dialect: brief-J-common.md (implicits only, `.right.map`, no 2.13-only collections).

## Properties

- Every existing property in `TestDoc`, `TestRunner`, `TestWidgets` passes. Any expectation you
  change (a message text, the `relations` list) is listed in the report with the reason. The
  wire format pins in `TestDoc` are the byte-identity guarantee: do not weaken them.
- (ip-stats) over random fetching reports (reuse J3g's generator of `sequence_Fetch`/`bind_Fetch`
  trees), `WriteStats.relations` lists one `$.fetch[n]` entry per scan, n increasing, each with
  the row count the continuation received, followed by the wire relations in document order.
- (ip-fail) a throwing fetch scan is a `WriteFailure` whose `completed` lists exactly the scans
  and relations finished before it; a throwing wire scan after k fetch scans lists those k.
- (ip-stack) a report with 2,000 sequential scans (a `sequence_Fetch` over 2,000 tiny literal
  relations, or `bind_Fetch` nested 2,000 deep) renders without a stack overflow; likewise a
  document with 2,000 inline relations, as `Write.doc` promises today. Run once, cite the log.
- (ip-data) `/data/<token>` still returns the inline object of the deferred relation (existing
  J3b/J3c properties), now through the driver.
- Mutation check: break `Call` so rows are dropped, run `TestRunner` (fx2) and (ip-stats), confirm
  red, revert; note it in the report.

## Gates

`scripts/gate.sh run commit` in the worktree, plus `sbt -batch 'core/testOnly *TestRunner
*TestWidgets *TestDoc *TestJson *TestSchema'`. The client is untouched (say so; if it is not,
`cd client && npm test`). No full `core/test`.

## Docs

Design note §3.4d "One interpreter": the step table above, the four decisions, what
`Write.doc`/`interpret` became. Plan: J3h row, handoff entry, the "cap on fetched rows" ticket
in the open list. Update the object comments of `Write` and `Runner` (the boxed pipeline in
`Runner`'s doc comment shows the old shape).

## Report

`tracker/json-stage3/report-J3h.md`, the shape `brief-J-common.md` asks for. Do not commit.
