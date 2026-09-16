# J3b: the document types and the document writer (relations inline, in the scan)

Branch `json-doc`, worktree `~/research/ermine/ermine-scala-wt-json-doc`, off
`json-s3-base`. Budget 5 h. Read `brief-J-common.md` first.

## Why

v1 requirement: one JSON object per response with every relation inline, written by new
code inside the database effect: each relation's columns come from the plan header and its
rows are appended during the scan, all relations on one connection in document order.
Design note §3.2, §3.4 (the "Streaming impl" and "Inline wire" rows), §3.4a (all of it),
§6 #23. The wire contract in `tracker/JSON-STAGE3-PLAN.md` is binding; the schema side
(J3a) and the decoder (J2a) are being built in parallel against the same contract; the
HTTP runner (J3c) comes after you and calls your API.

Read: `json/Encode.scala` (you add a third `JsonBuilder`), `json/Wire.scala`,
`modules/Json.e`; `relational/Scanner.scala`, `relational/SqlScanner.scala` (scanExt and
how headers are obtained -- `Typer.closedRel`, `ClosedExt`, `writers/Tabular.scala`'s use of
them), `relational/Ext.scala`, `relational/Rel.scala` (`SmallLit`, `header`),
`backends.scala` (`type DB[+A] = Connection => A`), `backends/DB.scala`,
`backends/Backends.scala` (`Scanners.SQLite`, `Runners.SQLite`), `Run.scala`,
`Runtime.scala` (`Rel`, `EmptyRel`), `Lib.scala` `runRelation` (~930) and `mkRelation#`,
`scalacheck-binding/.../TestInMemoryScan.scala` (a scanner in a test), `machines` `Process`.

## Build

1. `modules/Layout/Doc.e` (new): the layout vocabulary, record-style constructors so the
   generic encoder writes the wire:
   ```
   data Node = Widget { name : String, props : Json }
             | VFlow { children : List Node }
             | HFlow { children : List Node }
             | Grid { cells : List (List Node) }
             | Tabbed { tabs : List Tab }
   data Tab = Tab { label : String, content : Node }
   widget : String -> a -> Node   -- widget n p = Widget n (toJson p)
   vflow, hflow : List Node -> Node; grid : List (List Node) -> Node; tabbed : List (String, Node) -> Node
   ```
   Selector names collide with anything in scope are refused at the field; if one does,
   rename the FIELD, record the final names in the plan's wire contract, and say so.
   Check `:json` on a sample `Node` prints the expected `{"tag": ...}` shape.
2. `json/Doc.scala`: the document tree the writer consumes -- pure JSON nodes (argonaut or
   your own small ADT) plus `Data(ext, columns, order, delivery, path)` for a relation.
   A `DocJson extends JsonBuilder[Doc]` whose `rel(path, r, delivery)` forces `r` and builds
   `Data`: `columns` are the plan header's `(name, PrimT)` sorted by name (a `Header` is a
   `Map`); an `EmptyRel` with no header is an error at `path` unless a static type is
   supplied (take an optional `Type` hint; J3c may pass the relation's static row type --
   document what you support). `Doc.fromRuntime(node: Runtime): Either[Encode.Error, Doc]`
   runs the generic walker. The envelope: `Doc.document(root, settings)` =
   `{"version":1,"settings":settings,"root":root}`.
3. Row encoder (hot loop, no `Json` nodes): append one `Record` (`Map[ColumnName, PrimExpr]`)
   as a JSON array in column order straight to an `Appendable`/`StringBuilder`; per-PrimExpr
   cases matching `Encode` exactly (Long as decimal string, Date/Timestamp formats, non-finite
   Double is an error naming the relation path, row index and column, `NullExpr` is `null`,
   a nullable column's non-null value as its value); string escaping per RFC 8259 (reuse or
   match `lsp/Rpc.scala prString`; ` `/` ` escaped too); DateTimeFormatter
   instances shared and thread-safe. A column the header declares but a record lacks is an
   error, not a silent `null`.
4. `json/Write.scala`:
   `Write.doc[G[_]](d: Doc, out: Appendable, cfg: WriteConfig, cache: PlanCache)(implicit S: Scanner[G]): G[WriteStats]`
   (adjust the signature if needed; keep it generic in `G` with `S.M` as the monad). Pure
   nodes append text; a `Data` node is resolved by the delivery policy:
   - `WriteConfig(default: Delivery.Inline|Deferred, strategy: Buffered, threshold: Option[Long], ttlMillis, clock)`
     (only `Buffered` exists in v1; model `Strategy` as a sealed type with one case).
   - explicit `Inline`/`Deferred` win; `ByRequest` takes `default`.
   - INLINE, Buffered: `S.scanExt(ext, Process(rec => append row to a per-relation
     StringBuilder), order)` under `Monoid[Unit]` (or a counting monoid), then the object
     `{"kind":"inline","columns":[...],"rows":[...],"rowCount":n}` is appended to `out`
     after the scan succeeds. A failure anywhere fails the whole `G` action (HTTP error
     semantics); nothing partial is promised to the caller -- say what `out` holds on failure.
   - threshold: a BARE relation (`ByRequest`) delivered inline whose row count passes
     `threshold` goes out deferred instead; stop appending text once over (finish or abandon
     the scan -- report which `Process` allows). An explicit `Inline` ignores the threshold.
   - DEFERRED: no scan; `cache.put(ext, columns, order)` returns `(token, expires)`; write
     `{"kind":"deferred","columns":[...],"token":...,"expires":...}`.
   - Every relation in one `Write.doc` runs inside the ONE `G` action, sequentially, in
     document order -- for `G = DB` that is one `Connection` (prove it in a test).
   - `WriteStats`: per relation (path, delivery actually used, columns, rows, bytes, millis);
     log each at INFO via the project's log4j (`org.apache.log4j.Logger`, name
     `ermine.json.doc`) as one line: `relation <path> <delivery> rows=<n> bytes=<b> ms=<t>`.
   - `Write.relation[G](token, out, cache)(implicit S): G[Option[WriteStats]]`: the deferred
     re-request -- writes exactly the inline object for that relation; `None` when the token
     is unknown or expired.
5. `json/PlanCache.scala`: `trait PlanCache { def put(...): (String, java.time.Instant); def get(token, now): Option[Entry] }`;
   `MemoryPlanCache(ttlMillis, maxEntries, clock: () => Long, random: java.security.SecureRandom)`:
   128-bit token, base64url without padding, expiry checked on `get` and evicted, bounded
   (evict oldest past `maxEntries`), thread-safe (J3c serves concurrent requests).

## Properties (random declarations and values)

- (a) Writer vs encoder: for a random header (1..8 columns over all ten `PrimT`s, random
  nullability) and random records (0..200, random nulls in nullable columns, edge values:
  empty/unicode/control-char/quote/backslash strings, `Long.MinValue`, `-0.0`, dates before
  1970, timestamps with ms), scanning through a test `Scanner` that yields exactly those
  records produces text that argonaut parses, whose `columns` equal the sorted header with
  `Wire.columnType`/nullable, whose `rows[i][j]` equals `Encode.toArgonaut` of the record
  value (lift the `PrimExpr` the way the runtime would), and `rowCount` = n.
- (b) Real effect, one connection: random headers/records loaded into SQLite in-memory
  (`Runners.SQLite("jdbc:sqlite::memory:")` / a persistent connection, `Scanners.SQLite`),
  documents with several relations: the whole write runs in one `Run.run`, on one
  `Connection` (count connections through a wrapping `Run`), in document order, and each
  relation's rows equal what `S.collect` returns for it (compare as multisets unless an
  order is given). Record which PrimTs SQLite round-trips lossily and exclude them from
  THIS property only, with the reason, rather than weakening (a).
- (c) Delivery: for random documents mixing bare / `Inline` / `Deferred` relations and a
  random `WriteConfig`, every relation's written `kind` follows the resolution rules
  (explicit wins; default; threshold only for bare), `rowCount` agrees with `rows.length`,
  and deferred tokens resolve via `Write.relation` to exactly the object inline delivery
  would have written for that relation.
- (d) Nodes from Ermine: random `Node` trees built in generated Ermine source (widgets with
  random props from `TestSchema.shape`, relations from `mkRelation#` literals of random
  records, nested flows/grids/tabs) evaluate, `Doc.fromRuntime` + `Write.doc` produce a
  document whose non-relation parts equal `Encode.toArgonaut` of the same value with each
  relation replaced by the written relation object (a structural comparison).
- (e) Plan cache: random interleavings of put/get/clock advances against a model (a Map with
  expiry): same answers; tokens distinct over 10,000 puts; size bound holds; concurrent
  puts/gets from threads lose nothing.
- (f) Failure: a relation whose scan throws, or whose row has a non-finite Double, fails the
  whole action with an error naming the relation path, and stats/log say which.
- (g) Scale pin: 100,000 rows x 10 columns written through the test scanner in bounded
  heap (report ms and bytes; no hard timing assertion).

## Also

- A REPL command is not required. Add a "§3.7c Stage 3 writer as built" section to the design
  note (short) and tick J3b in the plan.
- Do not touch `Schema.scala`, `Zod.scala`, `Validate.scala` (J3a) or add `Decode.scala` (J2a).
