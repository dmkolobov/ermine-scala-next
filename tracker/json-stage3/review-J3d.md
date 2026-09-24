# Review of J3d (widget prop types, TypeScript client, table adapters, one new widget)

Independent review, 2026-09-16. Worktree `~/research/ermine/ermine-scala-wt-json-client`,
branch `json-client`, uncommitted against base `f7a7bfdb`. Reviewer did not write the stage.
Read: `brief-J-common.md`, `JSON-STAGE3-PLAN.md`, `brief-J3d-client.md`, `report-J3d.md`,
`report-J3a.md` (J3d notes), `brief-review.md`. Legacy read-only at `~/research/ermine/ermine-writers`.

## Summary

The stage is well built and honestly reported. The Ermine prop types, the generated zod, the
dispatcher, the error-box discipline and the new `scorecard` all check out against the plan's
wire contract and the legacy emission sites, and every departure the brief flagged is both
justified and (with one exception) documented. The properties are real: I mutated the Scala
anti-vacuity path and it failed as it should, and five consecutive TypeScript runs on five
different fast-check seeds were green.

One substantive defect: the `sorts` argument the table adapters hand `htmlwriter.runTabular`
carries a **boolean** where the legacy sends the **string** `"asc"`/`"desc"`, which is what
DataTables uses to build the name of the comparator it then calls. That breaks the one thing
this stage exists to do. Two smaller required fixes (an incomplete pin, a red `npm test`) and
one required documentation fix for J3e.

## Scope

`git diff --stat f7a7bfdb`: `.gitignore` (+2), `tracker/JSON-API-DESIGN.md` (+52, the new
§3.7e), `tracker/JSON-STAGE3-PLAN.md` (+11). Untracked: `client/` (30 tracked files),
`core/src/main/resources/modules/Layout/Widgets.e` and `Widgets/{Format,Table,Drilldown,Scorecard}.e`,
`core/src/test/resources/modules/Doc/SalesReport.e`, `scalacheck-binding/src/main/scala/TestWidgets.scala`,
`tracker/json-stage3/report-J3d.md`. Nothing under `core/examples/` (still 29 entries);
`tracker/repl-classpath.txt` untouched; `client/target/` is covered by the existing `target/`
rule. No production Scala changed. Scope is clean.

## Gates

Re-run by me (logs under `SP2 = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/rev-j3d/`):

| Gate | Result | Log |
|---|---|---|
| `sbt -batch core/compile core/copyResources` | success | `SP2/compile.log` |
| `core/testOnly TestJson TestSchema TestNamedFields TestDoc TestWidgets` | **Passed: Total 92, Failed 0** (matches the report) | `SP2/suites.log` |
| `cd client && npm ci && npm run build` (tsc 5.6.3, strict + `noUncheckedIndexedAccess`) | clean, exit 0 | `SP2/npmci.log`, `SP2/build.log` |
| `node --test "dist/test/*.test.js"` **exactly as README:39 says**, x3 | **30 pass / 3 fail** each run — see required fix 3 | `SP2/nodetest-{1,2,3}.log` |
| corpus + report fixtures regenerated, then `node --test` with `ERMINE_CORPUS`/`ERMINE_REPORT_DOC`, **x5** | **33/33 every run**; corpus figures reproduce the report exactly (200 documents, 425 widgets, 2666 cells, 176 deferred resolved, 15 CellFormat cases) | `SP2/full-{1..5}.log` |
| `client/scripts/check-generated.sh` | exit 0, "src/generated is up to date" | `SP2/checkgen.log` |

**Flakiness (brief point 4).** `(c-legacy)` runs on a random fast-check seed and compared
2606 / 2559 / 2519 / 2575 / 2546 pairs across the five runs — a different slice each time,
all green. No flakiness observed in five runs. The open issue (report #5) is accurately
stated; I would not fix the seed either.

Cited from the implementer's logs (`SP = .../scratchpad/j3d/`), verified by reading them, not
re-run because the diff cannot affect them:

- `*TestLoopTrace`: 720 solves / 720 segments / 720 agree / skipped=0 / hashdiff=0 / eqdiff=0,
  controls 46 and 58 of 720 (`SP/gate3-looptrace2.log`).
- Corpus: **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168** (`SP/gate4-verdicts.log`).
- `repl-smoke.sh` PASS, 9 groups (`SP/gate5-repl.log`); `lsp-smoke.sh` PASS 577 checks (`SP/gate5-lsp.log`).

## The departures from the brief (point 1)

**One module per widget — verified, and the right call.** I reproduced the claimed compile
error with a two-line probe (a scratch module on the classpath, `bin/ermine`'s Console):

```
data AProps = AProps { columns : Int }
data BProps = BProps { columns : Int }
-->  Probe/Sel.e:4:24: error: field selector columns is already a field selector of another
     data type
```

and a control module differing only in the second field's name (`bcolumns`) loads. The
brief's single `Layout/Widgets.e` really is a dead end once J3e adds five more widgets that
all want `columns`/`rows`/`series`. The `export`-umbrella plus `import ... using type X`
discipline is the right shape and is spelled out for J3e in three places (the module header,
README "Adding a widget", report extension point 1).

**`tabular` not `table`** — `table` is a keyword; the registry name on the wire is still
`"table"`, pinned by `(a-pin)` (byte-for-byte) and by `(b)`'s `widgetNames` assertion. Fine.

**`tag` -> legacy `type`, lower first letter** — I checked all fifteen cases against
`HTMLWriter.jsFormat` (HTMLWriter.scala:269-347) and `jsCondition` (:260-267). `legacyFormat`
(legacy.ts:99-138) is faithful, including the two places the legacy object form is lossy
(`round`/`integralRound` drop `color`; HTMLWriter.scala:315-322) and the `bg`/`fg`
**triples** rather than `{red,green,blue}` (HTMLWriter.scala:338-339). `whenTrue`/`whenFalse`
-> `then`/`else` and `aliases` list-of-pairs -> object are both correct. `Currency.places` is
genuinely absent from the Scala ADT (`Format.Currency(color, parens, symbol)`) and is read
from `CurrencyObj.settings` by `jsLayoutFormat` (:215) — adding it to the Ermine type is the
only way the client can format the cell, and it is documented in three places.

All four departures are documented for J3e. The one hazard that is **not** documented is
required fix 4 below.

## The legacy adapter (point 2)

`runTabular`'s argument object, compared key by key against `HTMLWriter.tableRegular`
(HTMLWriter.scala:1034-1060) and `drilldownTable` (:1064-1090):

| Key | Server | Client | Verdict |
|---|---|---|---|
| `id` | `uid + "_tabular"` | `${ctx.uid()}_tabular` | ok |
| `cols` | `displayRules.labels` | column headers | ok |
| `rowgroupCol` | `groupingColumnIndex : Option[Int]`; **absent on the drilldown** | `rowGroup ?? null`; absent on the drilldown | ok (`isnull` at tables.js:1220 accepts both) |
| `colAlignments` | `getAlignment` -> `"left"`/`"right"` (:1021) | same | ok |
| `colType` | `getColumnType` -> `"number"`/`"date"`/`"other"` (:519-526) | same | ok (client is stricter: the legacy can emit `false`) |
| `relation` | `rowAction` -> `{formatted, raw, format}` (:543-549); drilldown `jsTreeEntry` -> `{indent, content}` (PruJS.scala:41-45) | same, plus an extra `ix` | ok at runtime, comment wrong — see observation O1 |
| `legend` | `serializeLegend` | `null` | ok: `legend` is read only at tables.js:1398 for `sAjaxSource`, which nothing in the local path consumes |
| `sorts` | `deriveIndexedSort(t.ordering, ...)` -> `(Int, SortOrder)` | `[number, boolean]` | **WRONG — required fix 1** |
| `paginate`/`scroll`/`isDD` | booleans | booleans | ok |

**DOM skeleton.** `tableSkeleton` (legacy.ts:243-286) builds
`div.tabular_wrapper > table.tabular#<uid>_tabular > thead > tr > th*` and a `tbody`
placeholder row of the same width, with `+` prepended when `isDD`. That matches what
`tableRegular`/`drilldownTable` nest server-side, and it matches what DataTables needs:
`colNames` (tables.js:1235-1237) is `cols.length` entries, plus one for the `+` column when
`isDD`, and the `<th>` count must agree. `runTabular` writes its own `sTitle`
(`buildStickyHeader`, tables.js:1130, and the drilldown title at :1265-1270), so the sticky
span the client pre-builds is redundant but harmless. Column groupings are genuinely
unreproducible (no `Legend` on this path) and that is stated in the README, the design note
and the report.

`NULL_DISPLAY = "-"` is right: `jsPrimExprTabular` (HTMLWriter.scala:575-580) prints `"-"` for
a `NullExpr`, and the JS `formatDisplay` has no null case at all, so the rule genuinely
belongs in the adapter and not in the port. The `Constant` exception is correct
(`styleMap.Constant` ignores its input).

## The `format.ts` port (point 3)

I read the port against the real `formatDisplay` (utils.js:291-352), `round` (:12-16),
`isnull` (:6-8), `string_unhtml` (:41-48) and `nelpeHwDates` (:272-275), and against
`HTMLWriter.htmlEval` (:609-644) for the five cases the legacy styleMap does not have.

- The ten styleMap cases are reproduced exactly, oddities included: `Pr1` skipping `snd`,
  `Round` through `numberFormat` (string) vs `IntegralRound` through `round` (number),
  `Truncate`'s `max(2, n-3)`, `Currency` = `symbol + round(fst, places)` (so `$120.5`, not
  `$120.50` — faithful), `Percentage`'s `pad` switch, `DateRange`'s en dash.
- The five it does not have follow `htmlEval`: `Verbatim` = `pes.head` (:640), `Color` wraps
  in the two spans `htmlEval` substitutes for its `<COLOR_FORMAT>` markers (:611-618),
  `Conditional`/`Pr1` = `recursiveEval` (:627), `signSpan` mirrors the
  `<POSITIVE>`/`<NEGATIVE>` replacement for `color = true` (:629-638). `Markdown` formats with
  `base` and passes through rather than calling `markdownStringToHTML` (:621-625) — a stated gap.

**What `(c-legacy)` does and does not prove.** It loads the REAL legacy module text out of
`ermine-writers`, strips the `import`/`export` lines and evaluates the body against stubs
(`test/legacy-utils.ts`), so the comparison is against the original function, not a
re-reading of it. The `comparable()` filter is correct — it admits exactly the tuple-lossless
subset — and the property asserts non-vacuity twice (`compared > 500`, and all ten styleMap
tags actually seen). `(c-mutant)` shows a deliberately wrong `Truncate` is caught.

It does **not** prove:
1. `Highcharts.numberFormat`. The transcription in `src/format.ts` is injected as the
   legacy's own Highcharts stub (`legacy-utils.ts:77-80`), so `Round` and padded `Percentage`
   agree by construction. The report says this plainly (decision 10, open issue 6) and pins
   the transcription separately in `(c-pin)` with hand-computed values. Honest, and the only
   alternative is a highcharts dependency.
2. Any of the five non-tuple cases or the `color`/`negParens` flags. Those follow a *reading*
   of `htmlEval` and are covered only by the `(c-extra)` example pins. This is inherent — the
   legacy JS has no such cases to compare against — but it means five of fifteen `CellFormat`
   arms have example-grade evidence, not property-grade. Worth saying out loud in the report.

**The Alias fixes.** `format.ts:288-293` keeps the LAST matching pair, which is exactly what
`aliases[fst]` does on an object built from those pairs, and the empty-alias fallback
(`hit || fst`) matches `aliases[fst] || fst`. The `constructor`/`__proto__` deviation is real
and deliberate: `_.has` guards the styleMap lookup but the Alias lookup is a bare
`aliases[fst]`, so the legacy answers `Object.prototype`'s member; the list walk does not.
That is strictly safer, it is pinned in `(c-extra)`:151-152, and the fast-check arbitrary
holds alias keys to `[A-Za-z0-9]` (harness.ts:84-89) so the property never contradicts it.
Correct call, correctly documented.

## The dispatcher (point 6)

Error-box path: unknown name, no generated schema, zod refusal, unresolvable token and a
throwing renderer all produce `div.ermine-widget-error[data-widget][role=alert]` plus a
`RenderResult.errors` entry (dispatcher.ts:212-251). Nothing escapes except a caller error.
`(d-unknown)`, `(d-invalid)`, `(d-throws)`, `(d-deferred-fails)` and 400 single mutations in
`(d-mutation)` pin that; `(b-neg)` repeats it over the 200-document corpus. One cosmetic
asymmetry: a renderer that throws leaves the box *inside* `div.ermine-widget`, while the
other three paths return the box directly with no `div.ermine-widget` wrapper. Harmless.

Deep structural resolution: `isWireRelation` (relation.ts:81-85) accepts any object whose
`kind` is `"inline"`/`"deferred"` and whose `columns` is an array. Today nothing can collide —
props are validated by a `.strict()` generated zod first, and no prop record declares both
keys. But `TableColumn` already has a field literally named `kind`
(`Layout/Widgets/Table.e:37`), so the margin is one field name wide, and J3e's chart
descriptors are exactly the kind of record that would carry `kind` and `columns` together.
Acceptable; **not documented** — required fix 4.

Token handling is safe: `httpFetchData` `encodeURIComponent`s the token (relation.ts:99), so
a document cannot steer the request out of `<base>/data/`.

## Scala side (point 7)

**Non-vacuity, checked by mutation.** I changed `TestWidgets.scala:328` so that an optional
key (`rowGroup`/`cardDelta`) is DROPPED rather than retyped/added, ran
`core/testOnly ...TestWidgets`, and got what the comment predicts:

```
! (a) ... Falsified after 3 passed tests.
  scorecard ACCEPTED a mutant: {...}          <- cardDelta dropped
! (a-cov) ... Falsified after 0 passed tests.
  table ACCEPTED a mutant: {...}              <- rowGroup dropped
Failed: Total 5, Failed 2, Errors 0, Passed 3
```

So the anti-vacuity half of (a) is live, `Validate.check` discriminates, and the report's
stated reason for excluding `drop` on `Maybe` keys is correct. **Mutation reverted**
(md5 `5beaa1267cbe5f099aea0fea890ee233`, `git status` unchanged).

Generators are over random declarations and values (generated Ermine source: random `field`
declarations, random literal relations, random `CellFormat` trees to depth 2, random layout
trees to depth 2, random `WriteConfig`), not examples. `(a-cov)` asserts all three widgets,
all fifteen `CellFormat` constructors, both deliveries and both relation wrappers occur, and
that at least one mutant was refused.

**2.11 dialect.** Clean. No `given`/`using`/`enum`/`extension`/`export`/`derives`, no `?=>`,
no `LazyList`, no `CollectionConverters`, no Java 9+ API, no `f""`, no `*` wildcard or `as`
renames (`import org.scalacheck._` is the 2.11 form), no top-level definitions. **No `Either`
`map`/`flatMap`/`foreach`** — `checkA` returns `Either` and is consumed only by pattern match;
every `.foreach` in the file is on an `Option`. `Gen.alphaNumStr`, `Gen.sequence`,
`objectFieldsOrEmpty`, `withObject` are all already used by the landed `TestJson`/`TestDoc`/
`TestSchema`, so the port risk is the already-accepted one. The single new API is
`Json.jObjectAssocList` (TestWidgets.scala:334) — present since argonaut 6.0, so low risk, but
P3 should have it named.

`core/examples/` untouched; `SalesReport.e` sits under `core/src/test/resources/modules/Doc/`
(the module search path), which is the stated departure and does not move the corpus count.

## Security (point 8)

The only `innerHTML` writes in the package are `dispatcher.ts:100` and `:246`, both the
constant `""`, and `format.ts:115` (`domUnhtml`). There is no `insertAdjacentHTML`,
`outerHTML`, `document.write` or `eval` outside `test/legacy-utils.ts` (which deliberately
`new Function`s the legacy module text in a test). `scorecard.ts` builds everything with
`createElement` + `textContent`; `errorBox` uses `textContent`; tab labels use `textContent`;
`tableSkeleton` uses `textContent`.

`domUnhtml` sets `innerHTML` on a **detached** `<span>` from the render Document and reads
`textContent` back — byte for byte what the legacy `string_unhtml` does (utils.js:37-48,
same detached shared holder). So the sink is not new, though it is now reached client-side on
every `Default`/`Truncate` cell instead of server-side. The DOM-free `textUnhtml` fallback
exists for callers with no Document.

What the port *mints* — `Verbatim` (raw passthrough by design), `Color`'s spans, `signSpan`,
`DateRange`'s concatenation — is HTML that reaches `runTabular` and is injected by DataTables
(`drow = _.map(content, o => o.formatted)`, tables.js:1288, rendered as cell HTML). That is
exactly what happens today with the server's `htmlEval` output, from the same source of truth
(DB content), with the same `Verbatim` escape hatch. `colorHex` clamps each component to
0..255 and the zod refuses a non-integer, so `RGB` cannot inject CSS.

**Net: §3.4's XSS surface is preserved in kind, not widened; the escaping decision simply
moved from the Scala writer to `format.ts`.** That move is worth one sentence in §3.7e, which
currently says who computes `formatted` but not that the escaping moved with it.

---

# Required fixes

### 1. `sorts` must carry `"asc"`/`"desc"`, not a boolean — `client/src/legacy.ts:63,215-217,315,384`

**What.** `RunTabularArgs.sorts` is typed `[number, boolean][]` (legacy.ts:63) and
`sortPairs` (legacy.ts:215-217) emits `[s.sortColumn, s.descending]`, used at legacy.ts:315
(`table`) and legacy.ts:384 (`drilldownTable`).

The legacy sends a **string**. `HTMLWriter.scala:1056` and `:1085` pass
`deriveIndexedSort(t.ordering, ...)`, and `Tabular.ordering` is
`IndexedSeq[(Label, SortOrder)]` (`core/src/main/scala/com/clarifi/reporting/writers/Tabular.scala:77`),
serialised by `PruJS.scala:59` as `x.toString.toLowerCase` — i.e. `"asc"` / `"desc"`.

**Failure scenario.** `tables.js:1419` puts `sorts` straight into DataTables' `aaSorting`
(only element 0 is shifted, for the drilldown's `+` column; element 1 passes through
untouched). Then:

- Regular local table (`bServerSide: false`): `datatables.js:4019` computes the comparator as
  `oSort[(sDataType || 'string') + "-" + aaSort[k][1]]`. With `true` that is
  `oSort["ermine-htmlwriter-true"]`, which is not registered (`tables.js:127` shows the
  registered keys are `ermine-htmlwriter-asc`/`-desc`), so DataTables calls `undefined` and
  throws `TypeError` on the first draw — the table never renders. This fires for any table
  with a non-empty `sorts`, which includes the stage's own `Doc.SalesReport`
  (`[ColumnSort 1 True]`) and most of the 200-document corpus.
- Drilldown (`bServerSide: true`): no comparator lookup, but `_fnBuildAjaxData` sends
  `sSortDir_0 = true` and `tables.js:52 extractSort` tests `=== 'desc'`, so every sort
  silently degrades to ascending. `datatables.js:4053/4253` also compare against `"asc"`.

The corpus property cannot catch this: the stub `htmlwriter` only records the argument object,
and `corpus.test.ts:99-102` asserts the *wrong* contract (`typeof d === "boolean"`).

**Fix.**
```ts
// legacy.ts:63
sorts: [number, "asc" | "desc"][];
// legacy.ts:215-217
function sortPairs(sorts: ColumnSort[]): [number, "asc" | "desc"][] {
  return sorts.map((s) => [s.sortColumn, s.descending ? "desc" : "asc"]);
}
```
Keep `ColumnSort.descending : Bool` in Ermine — the translation belongs in the adapter, like
`alignmentOf`/`columnTypeOf`. Then update the assertions that encode the old shape:
`client/test/corpus.test.ts:99-102` (assert `d === "asc" || d === "desc"`),
`client/test/widgets.test.ts:59` (`[[1, "desc"]]`), `client/test/endtoend.test.ts:66`
(`[[1, "desc"]]`), and the `sorts` line in `report-J3d.md`'s property-(b) paragraph.

### 2. Pin `ColumnAlign`, `ColumnKind`, `Threshold` and `CellCondition` against the generated zod — `client/test/props.test.ts:43-124`

**What.** `src/props.ts` is hand-written, and `props.test.ts` pins field NAMES, optional keys
and `CellFormat`/`DocNode` arms — but never the enum VALUES of `ColumnAlign`
(props.ts:55) / `ColumnKind` (props.ts:58), nor the union arms of `Threshold` (props.ts:20-23)
or `CellCondition` (props.ts:26-32). The report claims "union arms and enum values"; for these
four types that is not so. (`COLUMN_TYPES` *is* pinned, at props.test.ts:112 — this is the
same check, missing for four more types.)

**Failure scenario.** J3e adds `AlignCenter` to `Layout.Widgets.Table.ColumnAlign`, or a
`Neq` arm to `CellCondition`. `check-generated.sh` passes (it regenerates). `tsc --strict`
passes — `props.ts` is hand-written, so the compiler never learns about the new case.
`props.test.ts` passes. At runtime `alignmentOf` (legacy.ts:203-205) silently answers
`"left"`, `columnTypeOf` (legacy.ts:207-213) falls off its switch and puts `undefined` into
`colType` (DataTables then treats the column as text and picks the wrong sort type), and
`evalCondition` (format.ts:132-141) falls off its switch returning `undefined`, so every
`Conditional` takes `whenFalse`. Nothing fails; the report just comes out wrong.

**Fix.** Add the assertions `(c-total)` already models for `CellFormat` (format.test.ts:52).
In `(p-table)`, after props.test.ts:50:
```ts
const col = unwrap(unwrap(TablePropsSchema).shape.columns)._def.type;
assert.deepStrictEqual([...(col.shape.align._def.values as string[])].sort(),
  ["AlignLeft", "AlignRight"]);
assert.deepStrictEqual([...(col.shape.kind._def.values as string[])].sort(),
  ["DateColumn", "NumberColumn", "OtherColumn"].sort());
```
and in `(p-format)` compare `unionTags` of the generated `CellCondition` and `Threshold`
(reachable from the `Conditional` arm's `condition`, and from any condition arm's threshold
field) against the tag lists `format.ts::evalCondition` and `props.ts` handle.

### 3. `npm test` is red from a clean checkout — `client/test/corpus.test.ts:28`, `client/test/endtoend.test.ts:22` vs `client/README.md:39,46-47` and `client/scripts/check-corpus.sh:19-20`

**What.** The fixture defaults in the tests resolve to `<client>/target/widget-corpus` and
`<client>/target/sales-report.json` (`path.resolve(__dirname, "../../target/...")` from
`client/dist/test`). README:46-47 documents them as `../target/...` and `check-corpus.sh:19-20`
writes `<repo>/target/...`. Nothing ever writes the client-local path.

**Failure scenario.** I ran exactly the command line the README gives at line 39
(`npm run build && node --test "dist/test/*.test.js"`) three times from a clean `npm ci`:
**30 pass, 3 fail** every time — `(b)`, `(b-neg)` and `(e2e)` `assert.fail` with "no corpus at
<client>/target/widget-corpus". `npm test` (package.json:"test") does the same. The
orchestrator running the obvious command at landing gets a red suite; the report's gate row
`node --test "dist/test/*.test.js"` -> 33/33 is true only with the two env vars set, which the
row does not say.

**Fix.** Either make the defaults agree with `check-corpus.sh`
(`path.resolve(__dirname, "../../../target/widget-corpus")` and `.../sales-report.json`), or
turn the three `assert.ok(...)` guards into a skip with the same diagnostic
(`t.skip("no corpus at ...; run WidgetCorpus first")`) so a fixture-less run is honestly
"30 passed, 3 skipped". Also add the env vars to README:39 and to the gate row in
`report-J3d.md`.

### 4. Document the `resolveRelations` false-positive hazard for J3e — `report-J3d.md` (extension points), `client/README.md` ("Adding a widget"), `client/src/relation.ts:81-85`

**What.** `isWireRelation` calls anything with `kind ∈ {"inline","deferred"}` and an array
`columns` a relation, and `resolveRelations` (relation.ts:121-137) swaps it out and stops
descending into it. Today no prop record can trigger it, because the generated zod is
`.strict()` and no record declares both keys — but `TableColumn` already declares a field
named `kind` (`Layout/Widgets/Table.e:37`), so the separation is one field name.

**Failure scenario.** J3e declares, say, `data AxisSpec = AxisSpec { kind : AxisKind, columns : List String }`.
If `AxisKind` has a constructor spelled so that it encodes to the string `"inline"`, the
dispatcher hands the widget that object untouched and never descends into it (so a relation
nested inside it is left deferred); spelled `"deferred"`, the dispatcher issues a
`GET /data/<that object's token>` and renders an error box when it 404s. Neither failure
points at the prop type.

**Fix.** One line in report-J3d.md's "Extension points J3e must use" and in README's "Adding
a widget": *a prop record must not declare both a `kind` and a `columns` field; the
dispatcher's structural relation resolution would mistake it for a relation.* Optionally
tighten `isWireRelation` to also require `rows` + `rowCount` (inline) or `token` + `expires`
(deferred), which removes the hazard outright and costs two lines.

---

# Optional suggestions (not blocking)

- **O1. The drilldown row comment and the report are wrong about `ix`.** `legacy.ts:10-12`
  and the report's "as built" section say `runTabular` gets `{indent, ix, content}` "as
  `jsTreeEntry` builds it". `PruJS.scala:41-45` emits only `{indent, content}`; `ix` is minted
  by `tables.js:121-124` itself. The extra key is inert (tables.js re-wraps each row as
  `{ix, row}` anyway), so this is a comment fix, not a code fix — but J3e and the 2.11 porter
  will read that comment as the legacy contract.
- **O2. `(b)`'s `formatted`/`format` assertions are near-tautological.** `corpus.test.ts:151-153`
  re-calls `tabularCell`/`legacyFormat`, the very functions that produced the values. Combined
  with the separate `raw`-against-the-wire check (:158-164) they do pin format-to-column
  alignment, which is worth having — but the report's phrasing ("`formatted` equals `format.ts`
  on it") reads as an independent check of the port, and it is not one. An independent check
  is impossible here (the server's `formatted` is not on the wire); just say so.
- **O3. `TestWidgets.mutate` never descends into arrays** (`TestWidgets.scala:317-321` walks
  objects only), so the Scala anti-vacuity mutation never reaches inside `columns[]` — a
  broken `TableColumn`/`CellFormat` sub-schema in `Validate` would not be caught by (a). The
  TS `mutateOnce` (`test/mutate.ts:15-24`) does walk arrays, so the zod side is covered; only
  `Validate` is not, and J3a's `(r-c)`/`(b)` cover it generically. Two extra lines in `walk`
  would close it.
- **O4. Dead assertion.** `dispatcher.test.ts:222`:
  `assert.ok(parsed.error.issues[0]?.path.length ?? 0 >= 0)` parses as `... ?? (0 >= 0)` and
  is always truthy. Presumably meant `(parsed.error.issues[0]?.path.length ?? 0) >= 0` — which
  is also always true; `assert.ok(parsed.error.issues.length > 0)` is the intended check.
- **O5. Display drift the report does not mention.** (a) A `Date`/`Timestamp` cell is rendered
  server-side today by `jsPrimExprTabular` through `HTMLRunner.tabularDateFmt`
  (`MMM-dd-yyyy`, HTMLRunner.scala:579-581); on the JSON path the cell arrives as the
  `yyyy-MM-dd` wire string and `Default` passes it through, so dates will *look* different.
  (b) `htmlEval`'s fallback branch replaces `" "` with `"&nbsp;"` in every non-special
  format's output (HTMLWriter.scala:641-643); the port does not. Both are cosmetic and
  arguably improvements, but "what reaches `runTabular` is byte-comparable with what the
  server sends today" (legacy.ts:24-27) is too strong as written — it holds for the `format`
  key, not for `formatted`.
- **O6. `legacyFormat`'s alias object.** `legacy.ts:132-136` builds `{}` and assigns
  `aliases[k] = v`, so a key `__proto__` invokes the prototype setter and the pair is silently
  dropped instead of stored. Inert today (only `format.type` is read, tables.js:219) and the
  fast-check arbitrary never generates it; `Object.create(null)` would make it exact.
- **O7. §3.7e could say that escaping moved.** The design-note addition says who computes
  `formatted`; adding "so HTML escaping of a cell now happens on the client, in the port,
  rather than in the Scala writer — the trust boundary of §3.4 is unchanged but its
  enforcement point moved" would save the next reader the analysis.
- **O8. For P3 (2.11 port):** the only new third-party API in `TestWidgets.scala` that no
  landed stage already uses is `Json.jObjectAssocList` (:334). Everything else
  (`Gen.alphaNumStr`, `Gen.sequence`, `Gen.pickN` via `TestSchema`, `objectFieldsOrEmpty`,
  `withObject`) is already exercised by `TestJson`/`TestDoc`/`TestSchema` on both branches.

---

# Verdict

**FIX-THEN-LAND** — required fixes 1-4 above. Fix 1 is a real runtime break in the legacy
adapter and must be applied before landing; 2 and 3 are small and mechanical; 4 is
documentation that J3e depends on. None of them requires another full review: re-run
`client/scripts/check-corpus.sh` and `core/testOnly ...TestWidgets` after applying them.
