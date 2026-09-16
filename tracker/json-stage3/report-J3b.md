# J3b as built: the document types and the document writer

Branch `json-doc`, worktree `~/research/ermine/ermine-scala-wt-json-doc`, off `json-s3-base` a7e8e050. Uncommitted. 2026-09-16, 05:57-06:46 built, 07:07-07:25 the two review fixes (about 70 min of the 5 h budget). (Report text written by the implementer agent, saved to this path by the orchestrator: the agent's harness blocked writing `.md` files.)

## Files built

| File | What |
|---|---|
| `core/src/main/resources/modules/Layout/Doc.e` (new, 53 lines) | `Node`, `Tab`, `widget`, `vflow`, `hflow`, `grid`, `tabbed` |
| `core/src/main/scala/com/clarifi/reporting/ermine/json/Doc.scala` (new, 219) | the document tree, `DocJson` (the third `JsonBuilder`), `Doc.fromRuntime`, `Doc.document`, `Doc.headerOfType`, `Doc.relations` |
| `.../json/Write.scala` (new, 472) | `Write.doc`, `Write.relation`, `Write.resolve`, `WriteConfig`/`Strategy`/`RelationStats`/`WriteStats`/`WriteFailure`/`Guard`, and `Rows` (hot-loop row encoder) |
| `.../json/PlanCache.scala` (new, 91) | `PlanCache`, `MemoryPlanCache` (128-bit base64url tokens, TTL, bound, thread-safe) |
| `scalacheck-binding/src/main/scala/TestDoc.scala` (new, ~1030) | properties (a)-(g) + pins: **20 properties** (18 + the two the review asked for) |
| `core/src/main/scala/com/clarifi/reporting/record/RecordMap.scala` (1 line + comment) | a Scala-3 inference bug that made every lookup by key on a scanned record throw, and silently broke record EQUALITY — see Bugs |
| `tracker/JSON-API-DESIGN.md` | new §3.7c "Stage 3 writer as built" |
| `tracker/JSON-STAGE3-PLAN.md` | J3b ticked, settled field names written into the wire contract, handoff line |

## Final `Layout.Doc` field names (the wire)

Nothing had to be renamed; no selector collided.

```
data Node = Widget { name : String, props : Json }
          | VFlow  { children : List Node }
          | HFlow  { children : List Node }
          | Grid   { cells : List (List Node) }
          | Tabbed { tabs : List Tab }
data Tab  = Tab { label : String, content : Node }
```

`:json` on a sample (REPL log `.../scratchpad/j3b/repl/doc3.out`):

```
{"tag":"VFlow","children":[{"tag":"Widget","name":"text","props":"hi"},
 {"tag":"Tabbed","tabs":[{"label":"a","content":{"tag":"HFlow","children":[]}},
  {"label":"b","content":{"tag":"Grid","cells":[[],[{"tag":"Widget","name":"n","props":2}]]}}]}]}
```

`Tab` is single-constructor, so it carries **no** `"tag"`. `Doc.e` imports `Json` and `List using map_List` (plain `map` is not exported by `List`).

## Decisions taken in code

1. **`Guard[G]`, a typeclass beside `Scanner[G]`** (instances `DB`, `Id`). `Scanner[G]` gives only a `Monad`, which cannot see the exception a scan throws, and a failure must name the relation. A `G` without an instance does not compile.
2. **What `out` holds on failure**: a prefix ending *before* the failed relation's object — never a partial relation (Buffered: rows go to a per-relation `StringBuilder`, appended only after the scan returns). The prefix is not valid JSON on its own, so J3c must buffer and send only on success. `WriteFailure(path, message, completed, cause)`.
2a. **A refused row leaves its scan by `Stop`, not by an exception** (review fix 1). `Rows.Sink.push` records the `RowError` and returns `false`; `Write.inlined` rethrows it inside the same `attempt` block once the scan has returned, so the failure, its message and its ERROR log line are unchanged — but the scan is torn down first. Throwing from inside the machine would unwind through `EffectfulProcedure.withDriver` (`relational/package.scala:121-128`, no `finally`), skipping `rs.close`/`stmt.close` (`sql/SqlExecution.scala:90`) and `SqlScanner.scanRel`'s `cleanTempTables` — one leaked server-side cursor per failed report under the pooled `Run[DB]` J3c will want. Pinned: `(f)` asserts every scan that started was also torn down (the test scanner records teardowns), and `(f-db)` asserts a second write on the *same* persistent connection succeeds after a refused row. Mutation-checked: reverting `push` to the throwing form falsifies `(f)` with "scans 1, teardowns 0" (`fix-mutant.log`).
3. **The threshold abandons the scan**: the sink's `Process` returns `Stop` on the (threshold+1)-th record; `Plan.andThen` propagates it, the driver stops, `EffectfulProcedure`'s teardown closes the SQL result set, buffered text is dropped. A thresholded relation therefore reads exactly `threshold + 1` records (pinned). `RelationStats` has both `rows` (written, 0 when deferred) and `scanned`.
4. **`WriteConfig` has no `ttlMillis`** — the TTL belongs to the `PlanCache`, which mints the token and owns `expires`. Config is `(default, strategy, threshold, clock)`; `default` may not be `ByRequest` (`require`).
5. **`cache.put` takes the whole `Doc.Data`** (so the entry carries the relation's `path` for the log line and the re-request's stats).
6. **A `DateExpr` is a date by its CASE**, even around a `java.sql.Timestamp` (`PrimExpr.mapDate` makes those); `Encode` dispatches on the JVM class and would print a timestamp, contradicting `"type":"Date"`. The only place row encoder and `Encode` differ; pinned.
7. **Escaping is RFC 8259 plus U+2028/U+2029 and any unpaired surrogate**, so every document is valid UTF-8 and JS-safe.
8. **A repeated object key keeps the first position, last value**, as argonaut does.
9. **Number split**: `DLong` integral (Int/Short/Byte and a hand-built `JInt`), `DNum` a finite double via `Double.toString`; `DRaw(argonaut.Json)` is `settings`, written verbatim.
10. **Static hints**: `Doc.fromRuntime(rt, hints)` with `String => Option[Header]` keyed by walker path, plus `Doc.headerOfType(ty, module)` for a closed `[a,b,c]` type (`GUID` -> `UuidT`; `Session.toHeader` would `MatchError` on GUID). Without one, a header-less `EmptyRel` is an encode error at its path.
11. **Stack**: the document is flattened iteratively into text runs and relations, then bound once per segment — for `DB` the stack grows with the number of *relations*, not rows or nodes.
12. **`bytes` is UTF-8 bytes**, the figure §6 #23 wants.

## Departures from the brief

- `WriteConfig` drops `ttlMillis`; `clock` is only the ms clock (decision 4).
- `PlanCache.put(data: Doc.Data)` instead of `put(ext, columns, order)` (decision 5).
- `Write.doc`/`Write.relation` need the extra implicit `Guard[G]` (decision 1).
- (b)'s exclusions are **measured** by property (b-sql), not assumed: NULL in a GUID column (DB-layer bug below), strings with a NUL or a lone surrogate (JDBC cannot carry them), doubles beyond ~1e300 (emitter literals lose them). Every column *type* round-trips exactly.
- One file outside the brief's list changed: `record/RecordMap.scala`. `Schema.scala`, `Validate.scala`, `Zod.scala` untouched; no `Decode.scala`.

## Bugs found outside the JSON code

1. **FIXED here — `record/RecordMap.scala:172`.** `SharingKeySet.get` was `keyCache get key map (indexValueSeq(values, _))`; `indexValueSeq`'s type parameter occurs only under `ValueSeq` (= `Array[AnyRef]`), so with `map`'s result type still being inferred it came out `Nothing` and the `asInstanceOf` compiled to `checkcast scala/runtime/Nothing$` — **every** successful lookup by key on a record from a SQL scan threw `ClassCastException` on Scala 3. Fix: `map (i => indexValueSeq[B](values, i))`, pinned by property (b-pin). `iterator` was already safe (its declared type fixes the inference).
   **Corrected after review — the blast radius is the relational engine, not just JSON.** (i) The JSON writer was *not* the first caller: `Op.eval` (`Op.scala:22`) indexes a record by name and `SqlScanner.scala:581` applies it to scanned records (`SqlScanner.scala:380`, `:424-425` build `RecordMap`s too); those paths were latently broken on Scala 3 with no Scala 3 coverage. (ii) `get` also backs `apply`, `contains`, `getOrElse` **and `Map.equals`**, and 2.13's `Map.equals` *catches* the `ClassCastException` and answers `false` — so two equal records out of a SQL scan compared **unequal, silently**, which disabled `relational.uniqSorted`/`uniq` (`relational/package.scala:35-58`) and any `Set[Record]` over scanned records. The fix restores record equality and therefore duplicate removal: a wrong-to-right **behaviour change in the relational engine**, whose real gate is the landing's full `core/test`, not the four JSON suites this stage ran. The 2.11 `RecordMap` is a different file and most likely infers `B` correctly there — the porter should confirm rather than port blindly.
2. **NOT fixed — `sql/SqlExecution.scala:67-88` with `sql/SqlEmitter.scala:579` (`EmitUuid_Strings.getUuid`).** `nextRecord` builds the cell before asking `rs.wasNull`, so a NULL in a `GUID` column calls `UUID.fromString(null)` -> `NullPointerException`. Only GUID is affected. It is the DB layer's bug; **J3c should carry it as a ticket** — any report with a nullable GUID column fails its scan.

## Landing-gate fix: the LSP symbol tree of a record-style `data`

The landing's full `core/test` on bf832e46 falsified `Renamer 3.2a.6.4 corpus:
siblings are sorted, and no two of them straddle` with 7 straddling pairs, all
in `Layout/Doc.e`: `'Widget' Rng(31,13,32,11)` straddles `'name' Rng(31,22,31,27)`
and `'props' Rng(31,37,31,43)`, and the same for VFlow/children, Grid/cells,
Tabbed/tabs.

**Root cause** (Stage 1a, commit 07975c76, `lsp/Symbols.scala`): a record-style
constructor's field selectors were emitted as **siblings** of the constructor,
under the data symbol — while a constructor's span runs to the start of the next
constructor, so it *contains* its own fields' spans. Overlapping-but-not-equal
sibling ranges are precisely what a client that maps a cursor to a symbol
(breadcrumbs, sticky scroll, outline-follow-cursor) cannot resolve. No module in
the corpus had a record-style `data` until `Layout/Doc.e`, so the corpus property
had never seen one; **every user module with record constructors had the broken
tree since Stage 1a**.

**Fix** (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Symbols.scala`,
the `SDataStatement` case): a field symbol is now a **child of the constructor
that declares it**. That is what LSP means by Field members (Field inside the
Class/Struct/Constructor that declares them) and it is what this builder already
does for every other container — a class's methods, a `private`/`foreign`/
`database` block's statements, a data type's constructors. `sym()` already unions
children's ranges into the parent, so containment holds by construction; the
constructor keeps its full span (valuable for cursor→symbol), which the
alternative fix — shortening the constructor's range to its name — would have
destroyed for positional constructors too. A field NAME shared by two
constructors is one selector but two declaration sites, and each site lists under
its own constructor (the old code de-duplicated by spelling, which threw away the
second site).

Blast radius (corrected by the follow-up review): `documentSymbol`, and
`workspace/symbol` for OPEN documents -- `Symbols.scala:607-625` flattens every
open document's tree as its branch (a), so the one observable change there is
that a field name shared by two constructors now answers at both declaration
sites instead of one (exactly one instance corpus-wide, `children` in `Doc.e`,
hence `symbols 8273 -> 8274`); completion is unaffected because
`Completion.scala:319` dedupes by label. `termGroups` (the moduleTerms
cross-check) skips `KField` and recurses through `KConstructor`, so it is
unchanged; `Definitions`' declaration-head list (the other half of Stage 1a) is
untouched. Also noted by the review: `(f-db) a refused row leaves the
connection usable` does not discriminate under the mutation (SQLite tolerates
a leaked ResultSet); `(f)`'s teardown counter is the real pin.

**No pinned expectation had to change.** `tracker/tools/lsp-client.py`'s symbol
pins (`Decls.e`, `Syms.e`, `Broken.e`) and every fixture under
`tracker/lsp-tests/` use positional constructors only — no `.e` fixture in the
repository declares a record-style `data` — so the smoke's 577 checks are
untouched and stay green.

**New pins** (`TestNamedFields`, where the record syntax is generated):
- *"the symbol tree of a generated record `data` is well formed"* — over random
  declarations from the suite's own generator: every level sorted, no two
  siblings straddling, every range containing its selection and its children,
  and the shape (constructors are the type's children; a record constructor's
  own field names, in declaration order, are ITS children; each is a `KField`;
  a positional constructor has none). Coverage is printed: 84% of generated
  modules carry at least one record field, up to 12.
- *"the symbol tree of a record `data`, exactly (the Layout.Doc shape)"* — an
  exact tree over a fixture with two record constructors that SHARE a field name
  plus a nullary one, so the shared-name rule and the Enum/Struct choice are
  pinned too.

**Mutation check**: with `Symbols.scala` reverted to the sibling shape, the
corpus property fails with exactly the 7 pairs from the landing log and both new
properties fail (`sym-mutant.log`); restored byte-identically (md5
`f1b9838178b19bdd3f8b7f9d63e8f6e8`) and green again.

**Gates re-run after the symbol-tree fix** (logs in the same directory):

| Gate | Result | Log |
|---|---|---|
| `core/compile core/copyResources` | success, no new warnings | `sym-gate1-compile.log` |
| `TestDoc + TestJson + TestSchema + TestNamedFields + TestRenamer` | **117/117** (20 + 28 + 19 + 16 + 34); the corpus symbol properties now report **straddling pairs 0** (was 7) over 258 files, 8532 sibling levels | `sym-gate2-suites.log` |
| `TestNamedFields` alone | 16/16, the two new properties among them | `sym-testnf1.log` |
| mutation check (old sibling shape) | corpus property falsified with exactly the landing log's 7 pairs, both new properties falsified; restored byte-identically | `sym-mutant.log` |
| LSP smoke | **PASS, 577 checks** (unchanged), no pinned expectation touched | `sym-gate5-lsp3.log` |

The smoke needed one note: `lsp-smoke.sh` caps the client at 120 s, and the first
attempt hit that cap under a load average of 29 from the sibling worktrees' builds
(the server's own log shows the client had driven the entire script to `shutdown` /
`exiting with code 0`, so nothing was stuck). Re-running the IDENTICAL client command
with a 420 s cap: exit 0, `PASS lsp (577 checks)`. The script itself was not edited.

The symbol census moved as the fix predicts: `Field 1468 -> 1469` and
`symbols 8273 -> 8274`, because `Layout/Doc.e`'s `children` is declared by
BOTH `VFlow` and `HFlow` and now lists under each constructor instead of once
under the type; `sibling levels 8531 -> 8532` is the one constructor level that
gained children.

## E11a data point (not fixed, as instructed)

`TestTolerantCheck` run ALONE on this tree, three times: E11a
("four cold checks of one module publish ONE form per constraint set")
**green all three times**, suite 58/58 each run
(`e11a-run1.log`, `e11a-run2.log`, `e11a-run3.log`). The landing run's
`SET class grew past its ceiling 3: (reportFor,4)` did not reproduce in
isolation on this tree.

## Gates (Tier 0)

Logs in `/tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/j3b/`.

| # | Gate | Result | Log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources` | success; only the three `Either#right` deprecations the dialect requires | `gate1-compile.log` |
| 2 | `core/testOnly TestJson TestSchema TestNamedFields TestDoc` | **81/81** after the review fixes (28 + 19 + 14 + 20; base 61, `TestDoc` 20); stdlib JSON sweep **100 -> 102** data types (`Layout.Doc.Node` and `Tab`, which the sweep does classify) with **80** rejected fields — the rejection count, not the type count, is what is unchanged; schema fixtures 8/8 match | `fix-gate2-suites.log` (pre-fix 79/79: `gate2-suites.log`) |
| 3 | `core/testOnly *TestLoopTrace` | FIRST RUN (`gate3-looptrace.log`): 3 properties pass but the model replay was **SKIPPED** — "the Lean model executable is absent (.../tracker/lean/.lake/build/bin/looptrace)", printed twice — so the report's earlier "model agreement proved" was wrong. RE-RUN with `-Dermine.looptrace=` pointing at the binary built in the sibling `json-wrappers` worktree: **720 solves, 720 segments, 720 agree, 0 skipped, 0 hashdiff/eqdiff, 24.5 s**, positive controls detecting 46/720 and 58/720 — the brief's 720/720 | `fix-gate3-looptrace.log` |
| 4 | `corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged | `gate4-corpus.log`, `gate4-verdicts.log` |
| 5 | `repl-smoke.sh` | green: aliasing 2, ffi 5, ffi-tolerant 9, json 20, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5 | `gate5-repl.log` |
| 5 | `lsp-smoke.sh` | PASS, 577 checks | `gate5-lsp.log` |

`tracker/repl-classpath.txt` was regenerated for the smokes and restored with `git checkout`. `TestDoc`-only runs: `testdoc11.log` (18/18, pre-review) and `fix-testdoc1.log` (**20/20**, after the review fixes and the two added pins). Gates 1, 4 and 5 were not re-run after the fixes: the change is confined to `json/Write.scala` and `TestDoc`, plus comments in `RecordMap.scala`.

## The properties

(a) writer vs `Encode` over random headers (1..8 columns, all ten `PrimT`s, random nullability) and 0..200 random records (nulls, `Long.MinValue`, `-0.0`, pre-1970 dates, ms timestamps, empty/unicode/control/quote/backslash/surrogate strings): text parses, columns are the sorted header with `Wire.columnType`/`nullable`, `rows[i][j]` equals `Encode.toArgonaut` of the lifted `PrimExpr`, `rowCount` = n, `stats.bytes` = UTF-8 length. **Anti-vacuity**: each case's document is mutated in one cell and the comparator must reject it. (a-cov) 300 fixed cases requiring all ten types, nulls, an empty relation and every nasty string to occur. (a-pin) byte-for-byte wire spelling; date/timestamp formats and the `DateExpr`-around-Timestamp decision.
(b) SQLite, 2..4 relations per document, whole write inside one `Run.run`: connections opened = 1, every scan gets the same `Connection`, document order, and rows equal `S.collect`/ordered `scanExt`. (b-sql) measures what SQLite carries. (b-pin) `RecordMap.get`; on SQLite a thresholded bare relation defers, reads threshold+1, the next relation still scans, and its token re-requests text identical to the direct inline write.
(c) delivery over random documents and random `WriteConfig` — kind, `rowCount`, deferred keys/token/expiry, byte-identical re-request, exactly which relations were scanned with which pull counts. (c-cov) 200 fixed cases covering all five outcomes.
(d) 80 fixed-seed `Node` trees built as **generated Ermine source** (props from `TestSchema.shape`, relations in all eight wrapper forms, nested flows/grids/tabs): the document equals `Encode`'s with each relation replaced by the written object, key order included. (d-pin) the empty-relation hint path.
(e) `MemoryPlanCache` against a model under random put/get/clock interleavings; 10,000 distinct 22-char tokens; 8 threads x 1,500 puts+gets lose nothing.
(f) scan-throws / non-finite Double / missing column each fail the whole action with a `WriteFailure` naming path (and row/column), `completed` attached, `out` = exactly the prefix, one INFO line per completed relation and an ERROR line for the failure (captured via a log4j-2 appender on `ermine.json.doc`), **and every scan that started was torn down** (the refused-row cases included). (f-db) the same on SQLite, plus: after a refused row, a second write on the same persistent connection succeeds. (a-pin, added) `DoubleExpr` canonicalises `-0.0` to `+0.0` (`PrimExpr.scala`'s `if (value == 0.0)`), so no `PrimExpr` can carry a negative zero and the reviewer's "the writer does emit `-0.0`" cannot arise; the pin also fixes `1.0E21`, `-1.5`, `4.9E-324` and what a raw `-0.0` would print.
(g) scale pin: 100,000 x 10 -> 15,341,781 bytes, ~1.9-4.4 s on a loaded machine, ~28 MB heap held with the text retained, exactly 100,000 driver pulls. No timing assertion.

## Open issues

- Nullable GUID columns throw in the SQL scan (bug 2) — ticket for J3c/DB layer.
- **Ticket for J3c**: `EffectfulProcedure.withDriver` (`relational/package.scala:121-128`) has no `finally` around `teardown()`, so a scan that throws *on its own* (a SQL error, a bottom in a literal) still skips `rs.close`/`stmt.close` and `cleanTempTables`. The writer no longer reaches that path for a refused ROW (review fix 1), but the cure — `try k(d) finally teardown()` — is shared code that needs a full `core/test`, so it was deliberately not done here.
- The landing's full `core/test` is the real gate for the `RecordMap` line: it restores record equality for scanned records, so `relational.uniqSorted`/`uniq` and `Set[Record]` deduplicate again (bug 1).
- SQLite loses doubles beyond ~1e300 through the emitter's literals (not chased).
- `Strategy` has one case and `WriteConfig.strategy` is never read — it exists so J3c can refuse `"streamed"` with a 400 and `Streamed` can land without a signature change.
- A deferred token holds the relation's **plan**; for `mkRelation#` literals the plan holds the rows, so the cache holds them until the TTL expires. Bounded by count, not bytes.
- 2.11 port (P2) carries `Guard`, `Rows`, `PlanCache` verbatim plus `Layout/Doc.e`. Three porting risks the review found:
  - `TestDoc.capturingLog` uses **log4j 2 core** APIs directly (`org.apache.logging.log4j.core.*`, `Property.EMPTY_ARRAY`); this branch gets the 1.2 API through the 2.x bridge. If the 2.11 branch has real log4j 1.2, property (f)'s log assertions will not compile and need a 1.2 `AppenderSkeleton`.
  - `TestDoc` uses scalacheck 1.15.4 generators (`Gen.alphaNumStr`, `Gen.alphaLowerChar`, `rng.Seed`, `Gen.Parameters.default.withSize`); check the 2.11 branch's scalacheck version.
  - The `RecordMap` line is a *Scala 3* inference fix; on 2.11 the old spelling most likely infers `B` correctly, so the line may be unnecessary there — confirm, do not port blindly.
- `DRaw` (the runner's `settings`) is printed with argonaut's `nospacesWithOrder`, which escapes neither U+2028/U+2029 nor lone surrogates, and `Rows.utf8Length` would mis-count a lone surrogate there. Settings are server configuration, so this is theoretical — but if J3c ever lets a client supply settings, escape them first.
- An exception while appending a **text** segment is not wrapped into a `WriteFailure` (only relation work is), and `Write.segments` runs eagerly inside `Write.doc`, so a failure there escapes the call rather than `Run.run`. Neither is reachable from a `Doc` the walker built.
- The deferred re-request RE-SCANS the plan, and every relation Ermine can build today has `order = Nil`, so the re-requested row ORDER need not equal the inline write's. The client must not assume stability (`Write.relation` guarantees the same rows, not the same order).

## What J3c must know to call Doc / Write / PlanCache

```scala
import com.clarifi.reporting.ermine.json._
import com.clarifi.reporting.backends.DB

// 1. evaluate `report : Params -> Node`, apply it, then:
val root = Doc.fromRuntime(node)                 // Either[Encode.Error, Doc]; hints optional
  .fold(e => badRequest(e.report), identity)     // "cannot encode $.x: why"

// 2. envelope; settings verbatim
val document = Doc.document(root, settingsJson)  // argonaut.Json overload; default {}

// 3. one action, one connection
val cfg = WriteConfig(default   = if (req.deferred) Delivery.Deferred else Delivery.Inline,
                      strategy  = Strategy.Buffered,   // refuse "streamed" with a 400
                      threshold = req.threshold)       // Option[Long], bare relations only
val cache = new MemoryPlanCache(ttlMillis, maxEntries, () => System.currentTimeMillis,
                                new java.security.SecureRandom)   // ONE per server, thread-safe
val out = new java.lang.StringBuilder                              // buffer, not the socket
val stats = runner.run(Write.doc[DB](document, out, cfg, cache))   // Run[DB].run
// send 200 + out.toString only here

// 4. GET /data/<token>
val body = new java.lang.StringBuilder
runner.run(Write.relation[DB](token, body, cache)) match {
  case Some(st) => ok(body.toString)   // exactly the inline object for that relation
  case None     => notFound            // unknown or expired
}
```

- Implicits needed: `Scanner[DB]` (`Scanners.SQLite(sms)`, `Scanners.MicrosoftSQLServer(sms)`, ...) and `Guard.db`; call as `Write.doc[DB](...)` so `G` is fixed.
- **Failure is an exception**: catch `WriteFailure` around `Run.run`. `f.path` is the walker path, `f.message` names row index and column, `f.completed` lists relations already written; `out` holds the prefix and must be discarded. A refused ROW tears its scan down before the failure is raised, so the connection stays usable; a scan that throws on its own does not (the `relational/package.scala` ticket above) — with a pooled `Run[DB]`, a failed request may still leak a cursor until that lands.
- The deferred re-request re-scans the plan and relations carry no order, so `Write.relation` returns the same ROWS, not necessarily the same ORDER, as the inline write. Do not build a client that assumes stable row order across the two.
- `settings` reaches the wire verbatim through argonaut's printer, which does not escape U+2028/U+2029 or lone surrogates — fine for server configuration, not for client-supplied JSON.
- Every relation logs at INFO on `org.apache.log4j.Logger` named `ermine.json.doc`: `relation <path> <delivery> rows=<n> bytes=<b> ms=<t>` (plus ` scanned=<k> (over the threshold)`). Same numbers in `WriteStats.relations` — the data for §6 #23.
- Resolution is `Write.resolve(requested, cfg)`: explicit wrapper wins; threshold applies only to a bare relation resolved inline.
- Tokens are opaque, 22 chars `[A-Za-z0-9_-]`; `expires` is `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`; a token stops resolving at `expires`. The cache is unauthenticated — scope it per session if more than one tenant is served.
- `mkRelation# []` (header-less empty relation) is an **encode error**: pass `Doc.fromRuntime(node, path => headers.get(path))` and build headers with `Doc.headerOfType(ty, module)(sessionEnv)`.
- `Doc.relations(doc)` lists relation nodes in document order.
- Nothing in the writer is `Session`-dependent or thread-local; concurrent requests are fine with their own `out` and `Run`; the cache is shared and synchronized.
