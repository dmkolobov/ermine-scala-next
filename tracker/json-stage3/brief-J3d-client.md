# J3d: widget prop types, the TypeScript client, the table adapter, one new widget

Branch `json-client`, worktree `~/research/ermine/ermine-scala-wt-json-client`, off
`json-encode` AFTER J3a (schema arms) and J3b (writer, `Layout/Doc.e`) have landed.
Budget 6 h. Read `brief-J-common.md` first, then `report-J3a.md`, `report-J3b.md` (and
`report-J3c.md` if J3c has landed when you start).

## Why

Design note §3.2 (document, dispatcher), §3.1a (Format), §4 (the de facto widget API:
§4.1 emission sites, §4.2 series, §4.3 meta, §4.4 format encodings), §5 Stage 3 row: "TS
dispatcher wrapping the existing 7 renderers with zod schemas generated from Ermine prop
types; client adapter that builds the `{formatted, raw, format}` cells the existing
renderers expect from `raw` + column `Format` via a port of `formatDisplay`; one new widget
end-to-end as the proof (one `data` + one TS component)". This stage does the scaffolding,
the TABLE widgets and the new widget; J3e does the chart adapters on your scaffolding, so
leave clean extension points and document them in your report.

Legacy code (read-only, separate repo `~/research/ermine/ermine-writers`, never edit it):
`writers/html/src/main/scala/com/clarifi/reporting/writers/HTMLWriter.scala`
(`tableRegular` ~1034-1060, drilldown ~1064-1096, `jsTabularRelArg` ~544-650, `jsFormat`
~269-347, `jsCondition` ~260, `getAlignment`/`getColumnType`), `writers/js/ermine/tables.js`
(`runTabular`), `writers/js/ermine/utils.js` (`formatDisplay` ~291-352), the export object
at `writers/js/ermine-htmlwriter.js:3571-3596`.

## Build

1. `modules/Layout/Widgets.e` (new; imports `Json`, `Layout.Doc`): record-style prop types,
   relations as `Inline r` / `Deferred r` / bare `[..r]` with a free row parameter where the
   widget is generic:
   - `data CellFormat` = an Ermine mirror of the legacy object form of `jsFormat` (all 15
     cases incl. `Conditional` with a `Condition` type, `ColorFormat` with an RGB type,
     `Alias` as a list of pairs, `Markdown`, `Pr1`/`Pr2`), named fields, `tag` spelled so the
     JSON is directly what `formatDisplay`'s object form reads, or document the adapter
     mapping. This is the pure-Ermine replacement of §3.1a's foreign `Format` for the new
     path; a converter from the foreign `Layout.Format` is OUT of scope (note it).
   - `data TableProps r` (cols/labels, per-column format, alignment, column type hint,
     row-group column, sorts, paginate, scroll, the relation), `data DrilldownTableProps r`
     (parent/child columns), and the smart constructors `table : TableProps r -> Node`,
     `drilldownTable : ...` using `Widget "table" (toJson p)` etc.
   - the NEW widget: `data ScorecardProps r` (title, label column, value column, optional
     delta column, a `CellFormat`, the relation) + `scorecard : ScorecardProps r -> Node`.
     (If you choose a different new widget, justify it in the report.)
   Leave the chart prop types to J3e but reserve the widget names in the plan:
   `table`, `drilldownTable`, `axisChart`, `pieChart`, `drilldownPieChart`, `styleBox`,
   `drilldownBar`, `treeMap`, `scorecard`.
2. `client/` (new, top level of the repo): `package.json` (pinned `zod@3`, `typescript@5`,
   `jsdom`, `fast-check`; `package-lock.json` committed; `node_modules` gitignored),
   `tsconfig.json` (strict), `src/`:
   - `generated/` -- zod for `Layout.Doc.Node` and every prop type, produced by
     `bin/ermine-schema --zod` (with J3a's row-polymorphic support) via
     `client/scripts/generate.sh`; `scripts/check-generated.sh` regenerates into a temp dir
     and diffs (the CI equality check of design note §3.5).
   - `document.ts`: the envelope schema (`version` 1, `settings`, `root`), `parseDocument`.
   - `relation.ts`: inline/deferred types, `resolveRelation(rel, fetchData)` that fetches
     `GET /data/<token>` for a deferred one (injectable fetch).
   - `format.ts`: a TypeScript port of `formatDisplay` to the object form, total over
     `CellFormat` (the legacy tuple form is lossy and is not ported).
   - `dispatcher.ts`: `render(target: Element, doc, registry, env)`; walks `Node`
     (`VFlow`/`HFlow`/`Grid`/`Tabbed` build plain DOM containers), and for `Widget` looks up
     `registry[name]`, validates props with its zod schema (a validation failure renders an
     error box naming the widget and zod path, never throws past the dispatcher), resolves
     relations, calls the renderer.
   - `legacy.ts`: the `htmlwriter` global's interface (typed from the Scala emission sites)
     and adapters for `table` and `drilldownTable`: build the DOM skeleton `tableRegular`
     emits server-side today, the `{formatted, raw, format}` cells from rows + `CellFormat`
     via `format.ts`, `cols`/`colType`/`colAlignments`/`sorts`/`paginate`/`scroll`/`isDD`,
     then `htmlwriter.runTabular(args)`.
   - `widgets/scorecard.ts`: the new widget as a plain-DOM TS component (no legacy code).
3. End to end: a report module under `core/src/test/resources/doc/` using `table` and
   `scorecard` -> JSON document (through `bin/ermine-serve` if J3c has landed, else an sbt
   `runMain`/test helper around `Write.doc` with SQLite in-memory) -> `client` test renders it
   in jsdom with a stub `htmlwriter` that records `runTabular` calls; the scorecard's DOM is
   asserted directly.

## Properties

- (a) Scala side (scalacheck, random declarations and values): random values of every prop
  type (generated Ermine source) with random literal relations render through `Write.doc`
  into documents that validate against the exported schemas (Validate) -- the document half
  of the contract.
- (b) Cross-language: a Scala test helper (or sbt `runMain`) writes N=200 such random
  documents to a temp dir; `client` runs `parseDocument` + the dispatcher over each in jsdom
  with the stub `htmlwriter`: zero validation failures, and every `runTabular` call's args
  satisfy the legacy interface and invariants (cells.length = rows x displayed columns;
  `raw` equals the wire cell; `formatted` equals `format.ts` on it). Script:
  `client/scripts/check-corpus.sh <dir>`; the orchestrator runs it at landing, so it must
  run from a clean checkout with `npm ci`.
- (c) TS side (fast-check): `format.ts` totality and legacy agreement -- for random
  `CellFormat` + random raw values, the port agrees with the legacy `formatDisplay`
  (import `writers/js/ermine/utils.js` directly from the ermine-writers checkout in the test,
  read-only; if it cannot load under node without its bundle deps, stub the imports it
  needs and say which), on every case the legacy object form supports.
- (d) Negative: random single mutations of valid documents are rejected by zod with a path,
  and the dispatcher renders the error box instead of throwing.
- (e) Generated zod is up to date (`check-generated.sh` exits 0) and `tsc --noEmit --strict`
  is green.

## Also

- `client/README.md`: how to install, generate, test, and how a new widget is added (one
  `data` + one TS component + one registry line). Add "§3.7e Stage 3 client as built" to the
  design note; tick J3d in the plan.
