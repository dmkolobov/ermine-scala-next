# Review of J3b — the document types and the document writer

Independent review, 2026-09-16. Worktree `~/research/ermine/ermine-scala-wt-json-doc`, branch
`json-doc`, base `a7e8e050`; the stage is uncommitted. Reviewer did not write the stage.
Budget used: about 70 minutes. Scratch:
`/tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/`
(`rev-*.log`, `rm/Repro*.scala`).

**Verdict: FIX-THEN-LAND** — two required fixes, both small; see the end.

`tracker/json-stage3/brief-review.md` does not exist (the review brief for this programme was
never written; the only `brief-review.md` in the tree is the loop-model template at
`tracker/loopmodel/briefs/brief-review.md`). I followed that template's method plus the
attention points given in the task, and the verdict vocabulary the task specified.

---

## 1. What I re-ran (and did not)

| Gate | Implementer's log | This review |
|---|---|---|
| `core/compile core/copyResources` | `j3b/gate1-compile.log` success | re-ran, exit 0, no new warnings (`rev-compile.log`) |
| `core/testOnly TestDoc` | `j3b/testdoc11.log` 18/18 | re-ran twice, **18/18** both (`rev-testdoc-baseline.log`, `rev-testdoc-reverted.log`) |
| four suites 79/79 | `j3b/gate2-suites.log` | cited, not re-run (gate policy); sweep line checked, see §6 |
| `*TestLoopTrace` | `j3b/gate3-looptrace.log` | cited — **see §6, the model replay was SKIPPED** |
| corpus 89/79/0 over 168 | `j3b/gate4-corpus.log`, `gate4-verdicts.log` | cited, counts match |
| repl / lsp smokes | `j3b/gate5-repl.log`, `gate5-lsp.log` | cited, green (9 suites; 577 checks) |

New evidence produced by this review: an independent Scala 3.3.8 reproduction of the
`RecordMap` inference bug and of its downstream effect on `Map.equals` (§2), and a mutation
run of the row encoder (§7).

Worktree hygiene: `git status` is exactly the stage's set, `tracker/repl-classpath.txt` is
restored, no stray `.ei` under `core/examples`.

---

## 2. `record/RecordMap.scala` — the one change outside the JSON code

**The bug is real; I reproduced it independently** (`scratchpad/rm/Repro.scala`, Scala 3.3.8,
the same compiler the build uses). With the old spelling

```scala
def get(key: A): Option[B] = keyCache get key map (indexValueSeq(values, _))
```

`indexValueSeq[A](vs: ValueSeq[A], i: Int): A` has its type parameter only under
`ValueSeq[_] = Array[AnyRef]`, so nothing constrains it from the argument; `map`'s own result
type is still being inferred, so it is not pushed in either, and `A` is solved as `Nothing`.
Running the repro:

```
new:  Some(7)
old:  THREW java.lang.ClassCastException: class java.lang.Integer cannot be cast to
      class scala.runtime.Nothing$
iter: List((a,7))
```

The fix (`indexValueSeq[B](values, i)`) is the minimal correct one, and `iterator` really is
unaffected because its declared `Iterator[(A, B)]` fixes the parameter. **The fix cannot break
a caller that worked before**: every *successful* lookup threw, so no caller ever consumed a
value; the miss path is unchanged; `updated`, `concat`, `transform`, `removed`, `iterator` and
`newSpecificBuilder` are untouched.

**But the report and the new code comment understate the change.** Two corrections:

1. *"the first code in the repository to call `get` on a record that came out of
   `SqlExecution`"* is **false**. `Op.eval` (`core/.../Op.scala:22`,
   `case ColumnValue(n, _) => t.getOrElse(n, …)`) indexes a record by name, and
   `relational/SqlScanner.scala:581` applies exactly that to scanned records
   (`mapRecord`); `SqlScanner.scala:380` and `:424-425` build `RecordMap`s too. Those paths
   were latently broken on Scala 3 and are fixed by this line — they simply were not covered
   by the Scala 3 suites.
2. `get` is the primitive behind `apply`, `contains`, `getOrElse` **and `Map.equals`**, and
   2.13's `Map.equals` *catches* `ClassCastException` and answers `false`. I verified this
   (`scratchpad/rm/Repro2.scala`, same compiler):

   ```
   buggy.contains(a)  = THREW ClassCastException
   buggy(a)           = THREW ClassCastException
   buggy == buggy     = false          fixed == fixed     = true
   Set(buggy) has b2  = false          Set(fixed) has f2  = true
   ```

   So before this line, two equal records from a SQL scan compared **unequal, silently**. That
   disabled `relational.uniqSorted` / `uniq` (`relational/package.scala:35-58`, both spelled
   `r == now` / `m contains rest`) and any `Set[Record]` over scanned records. The fix
   therefore changes *relational engine* behaviour (duplicates are removed again), not only
   the JSON stage's. It is wrong-to-right, but the stage ran only the four JSON suites plus
   `TestLoopTrace`, corpus and the smokes — the relational/SQL/writers suites were not run.
   The landing `core/test` is the right gate; it must be read with this in mind, and the 2.11
   porter must be told the line is a behaviour change, not a JSON enabler.

---

## 3. The row encoder (`Write.scala` `Rows`) against `json/Encode.scala`, cell by cell

`PrimExpr` is `sealed` (`PrimExpr.scala:20`) with exactly eleven concrete subclasses
(`:348-484`); `Rows.cell` (`Write.scala:411-431`) matches all eleven, so it is exhaustive.
`Encode`'s path for a cell is `prim(path, e.value, b)` after `NullExpr` (`Encode.scala:290-293`),
which is what property (a) compares against via `Runtime.fromPrimExpr`.

| Cell | `Encode` | `Rows` | Agree |
|---|---|---|---|
| Int / Short / Byte | `b.int(intValue)` → number | `append(int)` (`.toInt` for Short/Byte) | yes |
| Long | `b.str(l.toString)` → decimal **string** | `'"' + long + '"'` | yes; `Long.MinValue` identical, no escaping needed |
| Double | non-finite refused, else `b.num` | non-finite → `RowError` naming column (sink adds the row), else `append(double)` | yes; `-0.0` → `"-0.0"`, `1e21` → `"1.0E21"` both sides |
| Bool | `b.bool` | `append(boolean)` | yes |
| String | `b.str`; JVM `null` → `b.nul` | escaped string; `null` → `null` | yes |
| Date | `dateFmt` UTC (but see below) | `dateFmt` UTC; `null` → `null` | deliberate divergence |
| Timestamp | `timestampFmt` UTC | same formatter pattern | yes |
| GUID | `u.toString` | same; `null` → `null` | yes |
| NullExpr | `b.nul` | `null` | yes |

**The DateExpr-around-Timestamp divergence is correct and I would keep it.** `PrimExpr.mapDate`
(`PrimExpr.scala:71-74`) builds `DateExpr(n, f(dt.extractTimestamp))`, i.e. a `DateExpr` whose
value is a `java.sql.Timestamp`. `Encode.prim` matches `java.sql.Timestamp` before
`java.util.Date` (`Encode.scala:287-288`) and would emit a full ISO timestamp under a column
whose descriptor says `"type":"Date"`. The binding contract in `JSON-STAGE3-PLAN.md` says
`Date` is `yyyy-MM-dd` (UTC), so the *writer* satisfies the contract and `Encode` is the one
that deviates. Pinned by `(a-pin)`. Worth a ticket against `Encode` (it affects `:json`,
`toJson#` and J2a's round-trip), not a change here.

**Escaping** (`Rows.string`, `:361-390`) is RFC 8259 — `"`, `\`, everything `< 0x20` (`\b \f \n
\r \t` by name, the rest `\u00XX`) — plus U+2028/U+2029 and any unpaired surrogate. I read the
`from`/`i` bookkeeping: a valid surrogate pair advances by two and is emitted in the bulk
`append(s, from, i)`; a lone high surrogate at the end and a lone low surrogate both fall to
the escape branch. DEL (0x7f) is not escaped, which is right. `/` and `</script>` are not
escaped, which is also right; the design note's "safe to inline" wording is already scoped to a
`<script>`-free page.

**Missing column** is an error, not a silent null (`Rows.row:441-443`), with the record's own
key list in the message. Minor: it uses `rec.getOrElse(c, null)`, so a record that genuinely
stored a JVM `null` value under a present key would be reported as "no such column". Cosmetic.

`stats.bytes` is genuine UTF-8 length; property (a) compares it against
`text.getBytes("UTF-8").length`, which also proves no unpaired surrogate reaches the text.

One hole in the "every document is valid UTF-8 and JS-safe" claim: `DRaw` (the runner's
`settings`) is written with argonaut's `nospacesWithOrder` (`Write.scala:154`), which escapes
neither U+2028/9 nor lone surrogates, and `Rows.utf8Length` would then mis-count a lone
surrogate (Java writes it as `?`, one byte). Settings are server configuration, so this is
theoretical — but it belongs in the J3c handoff.

---

## 4. One connection, document order, and what `Guard` does to the failure path

**Structurally guaranteed, not just tested.** `Write.doc` returns a single `G[WriteStats]`;
for `DB = Connection => A` scalaz's function monad binds as `c => f(fa(c))(c)`, so every
segment — text run or relation, in `segments` order — is applied to the *same* `c`, in order,
sequentially. `Run[DB].run` supplies exactly one connection
(`Run.ThreadLocalDC.run`, `Run.scala:162-170`). `delay(M)(a) = M.map(M.point(()))(_ => a)` is
`c => a` with `a` by-name, so nothing runs before the connection exists. Property (b) pins the
observable consequences: `opened == 1`, every scan's `Connection` `eq` the first, scan order
`eq` document order, stats order, and rows equal to `S.collect` / ordered `scanExt`.

`Guard[G]` is a justified addition: `Scanner[G]` carries only a `Monad`, which cannot observe
an exception, and a failure must name the relation. `Guard.db` wraps the `DB` action in
`try/catch NonFatal`; `Guard.id` is a deliberate no-op and is *sound only because* the writer
also wraps the strict construction in its own `try` at `Write.scala:249-251` — that is
correct as written, and property (f) runs the whole failure suite through `Guard.id`, which
exercises exactly that path. `failure` (`:310-320`) short-circuits on an already-wrapped
`WriteFailure`, so there is no double wrap and no duplicate ERROR line. (f) and (f-db) pin
`f.path`, `f.completed`, `out` == the exact prefix, one INFO per completed relation and one
ERROR for the failure.

Gap (minor): an exception while appending a **text** segment (`go`'s `Text` branch,
`:198`) is not wrapped, despite `WriteFailure`'s comment promising a `$` path for "outside any
relation"; and `Write.segments` runs eagerly at construction, so an exception there escapes
`Write.doc` itself rather than `Run.run`. The J3c handoff only says "catch `WriteFailure`
around `Run.run`". Worth one sentence.

---

## 5. Threshold `Stop` semantics and resource teardown

**The threshold path is correct.** `Sink.push` refuses the record at index `limit`, so the scan
reads exactly `threshold + 1` records and the buffer is dropped. `Plan.andThen` has
`case Stop => Stop` (`machines/Plan.scala:107`), `driveLeftId` has `case Stop => z`
(`relational/package.scala:101-102`), and `EffectfulProcedure.withDriver`
(`relational/package.scala:121-128`) then calls `teardown()`, which is
`() => { rs.close ; stmt.close }` (`sql/SqlExecution.scala:90`). So on the threshold path the
result set *is* closed. `(b-pin)` pins it on real SQLite: `scanned == 6` for `threshold = 5`,
the next relation still scans, one connection, and the token's re-request is byte-identical to
a direct inline write. `Write.resolve` implements the rules exactly (explicit wins; bare takes
the default; only a bare relation resolved inline is thresholded), and `threshold = 0` with a
0-row relation correctly stays inline.

**The teardown hole is on the other path, and this stage is what makes it reachable.**
`withDriver` has no `try/finally`. When `Rows.RowError` is thrown from inside the sink (a
non-finite Double, or a missing column), it unwinds *through* `withDriver`, so `teardown()` is
skipped — `ResultSet` and `PreparedStatement` stay open — and `SqlScanner.scanRel`'s
`cleanTempTables(ts)` is skipped too. The report calls this pre-existing, and the *defect* is;
but before this stage the processes fed by a scan (`Process.wrapping`, `uniq`, `sorting`)
essentially never threw, so nothing reached it. Today `DB.Run`'s `freshResource` closes the
connection immediately afterwards, which bounds the damage; with a pooled `Run` — which is
exactly what J3c will want for an HTTP server — it is a leaked server-side cursor per failed
report. This is cheap to avoid **inside the writer**; see required fix 1.

---

## 6. Plan cache, 2.11 dialect, and gate discrepancies

**`PlanCache`** — thread safety: every operation (`put`, `get`, `size`, `tokens`, and
`dropExpired`, called only from `put`) holds the instance monitor and the `LinkedHashMap` is
never exposed; `java.util.Base64.Encoder` and `SecureRandom.nextBytes` are both thread-safe.
Entropy: 16 bytes of `SecureRandom` = 128 bits, base64url without padding = 22 chars
`[A-Za-z0-9_-]`, with a collision re-draw. Property (e) pins 10,000 distinct tokens all
decoding to 16 bytes, 8 threads x 1,500 put+get losing nothing, and a model over random
put/get/clock interleavings including eviction order, the size bound and expiry-on-get.
Three notes, none blocking and all of them already in the report's open issues or harmless:
`clock()` is wall-clock, so an NTP step backwards can leave `entries` out of expiry order and
`dropExpired` (which stops at the first live entry) will retain expired plans — `get` still
refuses them, so only memory is affected; eviction past `maxEntries` drops the *eldest live*
entry, so a client can be 404'd on an unexpired token; the cache is unauthenticated and bounded
by entry count, not bytes (a `mkRelation#` literal's rows live in the entry).

**2.11 dialect** — I read every new file against `brief-J-common.md`'s list. Clean: no
`given`/`using`/`enum`/`extension`/`export`/`derives`, no top-level definitions, `Either` only
via `.right`/`.left` (`Doc.scala:116-147`), `scala.collection.JavaConverters` in the test, no
`LazyList`/`Using`/`sortInPlace`, JDK 8 only (`java.time`, `java.util.Base64`,
`DateTimeFormatter.formatTo(TemporalAccessor, Appendable)`, `Character.isSurrogate`).
`Guard[scalaz.Id.Id]` is the ordinary `Monad[Id]` shape. Default arguments before an implicit
list are fine on both. Two porting risks the report does not list:

- `TestDoc.capturingLog` (`:856-884`) uses **log4j 2 core** APIs directly
  (`org.apache.logging.log4j.core.*`, `Property.EMPTY_ARRAY`). This branch gets the 1.2 API
  through the 2.x bridge (`build.sbt:106-109`, log4j 2.25.3). If the 2.11 branch has real
  log4j 1.2, property (f)'s log assertions will not compile there and need a 1.2 appender.
- `TestDoc` uses `Gen.alphaNumStr`, `Gen.alphaLowerChar`, `rng.Seed`,
  `Gen.Parameters.default.withSize` (scalacheck 1.15.4 here); the 2.11 branch's scalacheck
  version must be checked.
- The `RecordMap` line itself is a *Scala 3* inference change; on 2.11 the old spelling most
  likely infers `B` correctly, so the porter should confirm rather than port blindly (the
  report already says to check the shape; the point is that the line may be unnecessary there).

**Two gate-report inaccuracies** (numbers that go into the trackers):

1. `gate3-looptrace.log` prints `[loop model trace] SKIPPED: the Lean model executable is
   absent (…/tracker/lean/.lake/build/bin/looptrace)` **twice** and then passes 3 properties.
   The common brief's gate is "720/720" and the report says "model agreement proved" — the
   model replay did not run in this worktree. J3b touches nothing the loop model covers, so
   the risk is nil, but the tracker should say "skipped (Lean binary absent in the worktree)",
   not "proved".
2. "stdlib JSON sweep **102** data types / 80 rejected fields (**unchanged**)". The base is
   **100** / 80 (every pre-J3b log on this machine says 100). 102 = 100 + `Layout.Doc.Node` +
   `Tab`; `TestErmine.modules` recurses into subdirectories, so `Layout/Doc.e` *is* swept. The
   rejection count is genuinely unchanged, which is the right outcome (both new types are in
   the encodable fragment) — but the type count is not, and "unchanged" hides the fact that
   the sweep did classify the new module.

---

## 7. Can the properties pass vacuously? — mutation run

Per the task: I mutated one row-encoder case in the stage's own file,
`Write.scala:428` `case e: ShortExpr => sb.append(e.value.toInt)` →
`sb.append(e.value.toInt & 0xffff)` (wrong only for negative shorts, and reachable only through
the random generator, not through any pin), and re-ran `TestDoc`:

```
Failed: Total 18, Failed 5, Errors 0, Passed 13
  falsified: (a), (a-cov), (b), (c), (c-cov)
  e.g.  want […,"4390-02-11",-32768]   got […,"4390-02-11",32768]
```
(`rev-testdoc-mutant.log`.) Then reverted and verified byte-for-byte (`diff` clean, md5
`b8b9ebec7945ff6345acce77196489ce` restored, `git status` back to the stage's set) and re-ran:
**18/18 green** (`rev-testdoc-reverted.log`). The properties are not vacuous, and the
anti-vacuity machinery inside (a) (mutating one cell of the written document and requiring the
comparator to reject it) is genuine rather than decorative.

Residual test-strength notes, not defects: `jsonEq` compares numbers as `BigDecimal`, so
property (a) cannot tell `-0.0` from `0.0` — the writer does emit `-0.0` (both `Double.toString`
and argonaut's rendering agree) but nothing pins the sign; a one-line addition to `(a-pin)`
would close it. And the deferred re-request re-scans the plan, so for an unordered relation
(`order = Nil`, which is every relation Ermine can build today) the re-requested row order need
not equal the inline write's; `(c)` and `(b-pin)` only exercise deterministic or tiny scans.
The client must not assume stability — worth a line in the J3c handoff.

---

## 8. Everything else I checked and found right

- `Layout/Doc.e`: ASCII, LF, no selector collision, `import List using map_List` (plain `map`
  is not exported). `:json` output (`j3b/repl/doc3.out`) is exactly the contract's shape, with
  `Tab` carrying no `"tag"` because it has one constructor. The plan's wire contract was
  updated with the settled names.
- `DocJson.rel` forces only to WHNF and reads the header from `Typer.extTyper` — no rows are
  materialised at encode time, so column descriptors really are known before any scan; a
  malformed plan, a bottom and a non-relation each become an `Encode.Error` at the path.
- `DocJson.obj`'s duplicate-key rule (first position, last value) matches argonaut's
  `JsonObject`; the fast path avoids rebuilding when there is no duplicate.
- `Doc.headerOfType` covers the ten column types and `Nullable t`, refuses anything else with
  the offending field named, and resolves `Local` field names in the given module; `(d-pin)`
  pins it including `GUID` (which `Session.toHeader` would `MatchError`).
- `Write.segments` is iterative, so tree depth and size never touch the JVM stack; `go`'s
  recursion costs a constant number of frames per *segment*, i.e. about two per relation —
  the report's "thousands are fine" is right.
- Buffered failure semantics: rows go to a per-relation `StringBuilder` and reach `out` only
  after the scan returns, so `out` is a prefix ending before the failed relation's object
  (including the separating comma, hence not valid JSON alone) — pinned exactly by (f).
- `WriteConfig.require` refuses `ByRequest` as a default and a negative threshold;
  `Strategy` has one case and is deliberately unread (so J3c can 400 `"streamed"`).
- The per-relation INFO line matches the brief's spelling, with ` scanned=<k> (over the
  threshold)` appended only when the threshold fired.
- The stage did not touch `Schema.scala`, `Zod.scala`, `Validate.scala`, and added no
  `Decode.scala`.
- The second bug the report found and did **not** fix is real: `SqlExecution.scala:78-84`
  builds `UuidExpr(n, emitter.getUuid(rs, x))` before `rs.wasNull`, and
  `SqlEmitter.scala:579` is `UUID.fromString(rs.getString(i))` → NPE on a NULL GUID. Only GUID
  is affected (every other branch tolerates a null). Correctly left as a J3c ticket, and
  correctly excluded from property (b) by *measurement* ((b-sql) prints
  `nulls it loses = List(UUID)`) rather than by assumption.

---

## Verdict

**FIX-THEN-LAND.** Required fixes:

**1. `core/src/main/scala/com/clarifi/reporting/ermine/json/Write.scala:459-470`
(`Rows.Sink.push` / `process`), with the check added at `Write.scala:254-255` (`inlined`).**

*Failure scenario.* A report whose relation has a `Double` column holding a NaN or an infinity,
or whose scan yields a record short of a declared column, throws `Rows.RowError` from inside
the sink. The exception unwinds through `EffectfulProcedure.withDriver`
(`relational/package.scala:121-128`), which has no `finally`, so `teardown()` — `rs.close;
stmt.close` — never runs, and `SqlScanner.scanRel`'s `cleanTempTables(ts)` never runs either.
Under today's `DB.Run` the connection is closed immediately afterwards and the cursor dies with
it; under the pooled `Run[DB]` that J3c will want for the HTTP server, every such request
leaks a server-side cursor (and, on SQL Server, a temp table) for the life of the pooled
connection.

*Fix.* Make the row error take the same exit the threshold does — `Stop`, which the driver
already tears down correctly — and rethrow it after the scan returns:

```scala
final class Sink(d: Doc.Data, limit: Long) {
  …
  var error: Rows.RowError = null
  def push(r: Record): Boolean =
    if (rows >= limit) { over = true; buffer = new java.lang.StringBuilder(0); false }
    else {
      if (rows > 0) buffer.append(',')
      try { row(buffer, r, cols); rows += 1; true }
      catch { case e: RowError => error = new RowError("row " + rows + ", " + e.getMessage); false }
    }
```

and in `Write.inlined`, inside the existing `attempt(...)` block, before the `sink.over` test:

```scala
if (sink.error != null) throw sink.error
else if (sink.over) deferred(…)
else { … }
```

`attempt` still wraps it into the same `WriteFailure` with the same message and the same ERROR
log line, and the buffered text is still discarded, so property (f) passes unchanged — please
add one assertion to (f) or (f-db) that the scan was torn down (e.g. that a second scan on the
same connection succeeds after a row failure). The `Table`-throws case cannot be fixed from the
writer; the complete cure is a `try k(d) finally teardown()` at
`relational/package.scala:121-128`, which is shared code and needs the full suite — carry that
as a ticket for J3c rather than doing it here.

**2. `core/src/main/scala/com/clarifi/reporting/record/RecordMap.scala:172-180` (the new
comment) and `tracker/json-stage3/report-J3b.md` / `tracker/JSON-API-DESIGN.md` §3.7c.**

*Failure scenario.* These three texts are what the 2.11 porter and the landing orchestrator
will act on, and all three currently misstate the change. (a) "the first code in the repository
to call `get` on a record that came out of `SqlExecution`" is false — `Op.eval`
(`Op.scala:22`) via `SqlScanner.scala:581` already did, and `SqlScanner.scala:380/424-425` build
`RecordMap`s too; (b) the comment omits that `get` also backs `apply`, `contains` and
`Map.equals`, and that 2.13's `Map.equals` swallows the `ClassCastException` and answers
`false`, so record equality — and therefore `relational.uniqSorted` / `uniq` and any
`Set[Record]` over scanned records — was silently broken and is now restored (verified, §2).
A porter reading the present comment will treat the line as a JSON-stage enabler and may skip
it or port it without re-running the relational suites. Also correct the two gate numbers in
the report: the stdlib sweep went **100 → 102** data types (not "unchanged"), and gate 3's
`TestLoopTrace` ran with the Lean model executable **absent** ("SKIPPED" twice in
`gate3-looptrace.log`), so "model agreement proved" should read "skipped in this worktree".

*Fix.* Rewrite the comment and the two report/design-note passages to say the above, and add
a line to the handoff log telling the orchestrator that the landing `core/test` is the real
gate for the `RecordMap` line because it changes relational-engine dedup behaviour.

Not required, but recommended while the files are open: pin `-0.0` in `(a-pin)`; add the
`settings`/`DRaw` escaping caveat and the "deferred re-request row order is not stable" caveat
to the J3c handoff section; note in the report that `TestDoc`'s log capture uses log4j 2 core
APIs and scalacheck 1.15 generators, both of which the 2.11 port must re-check.
