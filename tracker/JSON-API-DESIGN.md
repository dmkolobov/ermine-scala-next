# JSON API design — Ermine as the source of truth for the browser contract

Synthesis of six research lanes (runtime, typeclasses, schema, current-api,
data-path, precedent) plus a skeptic pass over their load-bearing claims,
2026-09-01; revised the same day after a completeness-critic pass (§7 lists
the corrections). Read-only investigation; nothing is implemented. Every claim below
cites file:line the researcher or the skeptic actually opened; §7 lists what
was refuted or is unverified so nobody builds on it.

Paths: `core/` = `ermine-scala/core/src/main/scala/com/clarifi/reporting/`,
`modules/` = `ermine-scala/core/src/main/resources/modules/`,
`html/` = `ermine-writers/writers/html/src/main/scala/com/clarifi/reporting/writers/`,
`js/` = `ermine-writers/writers/js/`.

## 0. TL;DR

**Decision: type-directed reflective serialization, no typeclasses.** Ermine
values are encoded by a Scala walker over `Runtime` that is guided by (a) the
constructor `Global` every `Data` node already carries and (b) a new
`DataConDecl` registry attached to each data type's `Con` at load time
(ordered constructors, field types, existentials). Params are decoded by the
inverse walker driven by the report binding's static type. Schemas are exported
by a third walker over `Type` + the same registry into JSON Schema 2020-12, from
which zod is generated in CI. Relations never go through the value walker: a
`Rel` becomes a `JRel` node that the document writer resolves inside the
runner's effect: inline rows-as-arrays by default, so the response is one JSON
object (§3.4a, a v1 requirement), or deferred per relation via an
`Inline`/`Deferred` wrapper or per request; buffered versus streamed inlining
is a request setting, not a design commitment; signed, scoped handles are the
hardening step for deferral. The 82-def
`Writer`, `Layout/Report.e`'s foreign block, `HTMLWriter`/`PruJS` and the JS `eval`
runtime are retired; a widget is one Ermine `data` declaration plus one TS
component. Rationale: the language has no instances or dictionaries (§2.2),
so "deriving" is an XL compiler project with nothing to build on; but every
runtime value is self-describing down to the constructor name (§2.1), the
checker retains constructor types (§2.3), and the one thing reflection lacks —
declared field types, names and order — is a ~50-line registry (§2.3). That
combination is automatic for user-defined types in user libraries, costs M,
and keeps the source of truth in Ermine declarations.

## 1. Problem statement

Production facts (from the user):

| Fact | Consequence |
|---|---|
| Ermine is used as `params -> report` only; interactivity lives in JS widgets | The report is a value; the writer's job is encoding, not UI |
| Signal/Selector/widget/button/foreignSink machinery is dead; JavaFX is dead | ~1,300 lines are deletable (§5); nothing in the new design models continuations |
| Browser `eval`s JavaScript source strings emitted by Scala | `js/ermine-htmlwriter.js:65 const lessEvilEval = eval`, `:3218 lessEvilEval(ups[1])(htmlwriter)`; `html/HTMLWriter.scala:414-425 runUpdates` builds `jsLambda` |
| A new widget touches `Writer.scala` + every concrete writer + a foreign line + the JS bundle | `core/writers/Writer.scala:89 abstract class Writer[F[_],C]` (82 `def`s: 17 final `*DMTL` adapters, ~33 abstract); `modules/Layout/Report.e:1704-1757` (46 `method` lines); `modules/Layout/Chart.e:214-223` (8 more) |

Why the Writer trait is the wrong axis: `data Report f z = Report (Writer f z -> f z)`
(`modules/Layout/Report.e:73-74`) is a tagless-final encoding of a *fixed* UI
algebra. Adding a widget means extending the algebra everywhere at once. The
existing JSON writers show the failure mode: `JsonWriter` implements the full
algebra with ten `Missing.*/WDefault.*` mixins, hardcodes domain column names
(`writers/json/.../JsonWriter.scala:189,251`), flattens layout (`:499-557`) and
leaves charts `ftodo` (`:465-496`); `JsonDebugWriter` has the right
`{type: ...}` shape (`:81-89`) but stubs everything but tables.

What is actually live today (current-api lane, verified): seven data-widget
renderers — `runTabular`, `runTimeSeries`, `runPiechart(Drilldown)`,
`runDrilldownBar`, `runStylebox` (`html/HTMLWriter.scala:810,1048,1078,1154,1249,1295`)
and an unprefixed `runTreeMap` (`:1130`) that **no JS file defines** (grep over
`js/` is empty; export object `js/ermine-htmlwriter.js:3571-3596`) — plus ~11
pure-HTML layout nodes. Every prop value is already JSON-shaped (`html/PruJS.scala:20-62`).

## 2. Automatic serialization of Ermine types

### 2.1 What the runtime gives for free (reflective walk)

`Runtime` is sealed with exactly ten shapes (`core/ermine/Runtime.scala:15,33,62,92,110,114,128,142,161,181,200`;
skeptic grep found no other subclass). Observed encodings (REPL, `-Dermine.typeCheck=true`):

| Ermine | Runtime | Evidence |
|---|---|---|
| Int/Long/Double/… literals | `Prim(boxed JVM value)` | `Term.scala:189 Lit(_, i) => Prim(i)` |
| Bool | `Data(Builtin.True|False)` (also `Prim(Boolean)` from foreign `Raw`) | `Type.scala:562-563`; `Session.scala:985-986` |
| `()` / tuples | `Arr()` / `Arr(elems)` | `Runtime.scala:193`; `Term.scala:184-187` |
| Records `{..r}` | `Rec(Map[String,Runtime])`, keys = **unqualified** field name | `Runtime.scala:300-303 fieldFun`; `Lib.scala:472` |
| List | cons cells `Builtin.Nil` / `Builtin.::` — not `Arr` | `Lib.scala:281-286` |
| Maybe / Nullable | `Just/Nothing`; `Some a` / `Null (Prim PrimT)` — Null carries the column type | `Lib.scala:292-302`; `Runtime.scala:384-392` |
| user `data T = C t1 t2` | `Data(Global(module,"C",fixity), positionalArgs)` | `Session.scala:785,809-819`; `Runtime.scala:344-346` |
| `Field r a` | `Data(Global(module,name), [Prim(PrimT)])` | `Session.scala:1363-1364` |
| Relation | `Rel(Ext)` — an unevaluated query; rows only via `Scanner.scanExt` in effect `G` | `Runtime.scala:92`; `relational/Scanner.scala:25-27,47-48` |
| Native `List#/Maybe#/Pair#/Map/Vector` | `Prim(scala collection)` whose elements are raw JVM values for prims but `Runtime` objects for Rec/Data/Arr; `Native.Map` values are always Runtime | `Lib.scala:160-172,331,354-355,310` |
| functions / IO / FFI / foreign data | `Fun`, `Data(IO,[Fun])`, `Prim(anything)` | `Runtime.scala:181`; `Session.scala:985-989` |
| `Box` | `Box(x)` behaves as `Prim(x)` (own `apply1`/`equals`); the encoder treats it as `Prim` | `Runtime.scala:62` |

Prior art: `core/remote/ErmineFormat.scala:98-117 runtimeW` is exactly this walk
(f0 binary target; `Fun` → error; Timestamp collapses into Date; Char/Float die).
Its sole consumer is the dead selector path (`html/HTMLWriter.scala:428,468`).

What the walk loses: constructor field **names** (none exist anywhere:
`syntax/Statement.scala:117 constructors: List[(List[TypeVar], TermVar, List[Type])]`,
`surface/Surface.scala:200 SConDef(exists, name, fields: List[STy])`), element
types of empty containers, module qualification of record keys (two modules'
`field x` collide as `"x"`), Long precision in the LSP `Json` ADT
(`core/ermine/lsp/Rpc.scala:27 Num(value: Double)`, printer `:49-50`, parser `:141-142`).

Hard constraints found:
- **Stack.** `nf` recurses non-tail (`Runtime.scala:116,130,163`); a structural
  walk of a 2,000-element list overflows the default stack (REPL:
  `replicate 1 2000 == replicate 1 2000` → StackOverflowError through
  `Data.equals:134/arrEq:270/Thunk.equals:207`; Java probe: `nf` SOE at n=2000).
  `bin/ermine:21` sets no `-Xss`. The encoder must walk `::` spines iteratively
  and never call `nf`. Tail-recursive consumption of 1e6 elements is fine.
- **Bottoms survive parent whnf** (`[1,<error: boom>]`, `Runtime.scala:142-152`);
  the encoder needs a per-node error policy.
- **Relations cannot be encoded reflectively**: `Rel` does not override `nf`
  (`Runtime.scala:17,92`); rows require `Scanner[G]`. Literal relations
  (`Rel(ExtRel(SmallLit(rows)))`, `Runtime.scala:356-366`) are the only exception.
- `Native.Relation.runRelation` yields `Rec` of `Prim(PrimExpr)` (`Lib.scala:933-934`)
  while `scanRelationDMTL` yields `Prim(Int)` etc. via `fromPrimExpr`
  (`Writer.scala:252-253`; `Runtime.scala:330-342`) — divergent; accept both.

### 2.2 Type-directed derivation: what exists

**There is no instance system.** `instance` is only a reserved keyword
(`parsing/package.scala:30`; `surface/SurfaceParsers.scala:34,838-848` has
`classStatementP` but no instance production; REPL: `instance Show Int` → parse
error). `class` with a body or context is refused
(`rename/NewPipeline.scala:468-473 "class bodies are not supported"`); a bodyless
`class` is silently dropped (`:474`) and its name lowers to a type *variable*, so
`Show a => a -> a` applied at `Int` type-checks with no instance and the
constraint is discarded at generalisation (`Subst.scala:1396-1402`;
`Constraints.scala:654-656` drops malformed constraints; REPL: `:type (useShow 1)`
→ `Int`, `:kind Show` → `undefined type`). **Any `class` in the production corpus
is inert today** (open question §6).

**Dictionaries are erased.** `Instance.build` / `ClassDef.destroy`
(`session/SessionState.scala:12-19,52-57`) have no call sites in core (grep);
`Term.eval` (`Term.scala:179-213`) has no dictionary nodes; builtin instances
build `Prim(())` "no dictionary to build" (`Lib.scala:194,207,247,1073,1114`);
`==` is `a.extract[Any] == b.extract[Any]` (`Lib.scala:228`). The only classes
are Scala builtins whose instances are arbitrary `reqs: List[Type] => Option[List[Type]]`
matchers, including a magic `Eq` over any product arity and any record row
(`Lib.scala:252-271`). A user `data Color` has no `Eq`/`Primitive` instance
(REPL: `No instance for (Eq Color)`), and instance matchers cannot see
constructors because a data type's `Con` carries only
`new ConDecl { def desc = "data" }` (`Session.scala:776`; `Subst.scala:1248-1249`;
`Type.scala:105-128` has no constructor slot).

The language's real idiom is the explicit dictionary/witness value:
`data Monad f = Monad (forall a. …)` (`modules/Control/Monad.e:7`), `Prim a` =
`Prim(PrimT)` (`modules/Prim.e:7-12`; `Lib.scala:163`), `Row r = Row (List (String, PrimT))`
(`modules/Relation/Row.e:21`), `header : {..r} -> Row r` (`modules/Record.e:23-24`),
`Format a` foreign witnesses (`modules/Layout/Format.e:18-20`).

### 2.3 What the checker retains (schema source)

`SessionEnv` (`session/SessionState.scala:81-94`) keeps `termNames: Map[Global,V[Type]]`
(every constructor's full type scheme via `primOp`, `Session.scala:69-77`),
`env`, `cons/privateCons: Map[Global,Type.Con]`, `classes`, `loadFile`,
`loadedModules`. Not kept: the parsed `Module` (`Dep.read` re-parses,
`Session.scala:386-397`; `depCache` holds `Dep`s only). Constructor order and
the universal/existential split are lost after load (`Forall.mk` filters and
reorders binders by occurrence, `Type.scala:367-376`).

But the ordered constructor list with core `Type`s **is** present at load time:
`NewPipeline.Read.module: Module` (`rename/NewPipeline.scala:50-52`) and the strict
`readModule` (`:60-64`) already used by `Dep.read` (`Session.scala:392-395`)
carry `DataStatement.constructors` (`syntax/Statement.scala:117`) into
`processTypeDefComponent` (`Session.scala:774-790`), which the LSP's
`TolerantCheck.checkWith` also calls (`session/TolerantCheck.scala:163`).

Fields: `field x : T` requires `T ∈ primTypes` or `Nullable` thereof
(`Session.scala:1358-1362`; `Type.scala:705-724` — Char/Float commented out),
installs `Con(g, FieldConDecl(ty), Field)` (`:1363`) and a runtime witness.
`Session.toHeader` (`:1263-1277`) already maps a closed row to
`Header = Map[String, PrimT]`. Caveat: `toHeader` uses `PrimT.withName(ty.string)`
which knows `"UUID"` but the con is `Builtin.GUID` (`PrimT.scala:215-226`;
`Type.scala:572`) — a `GUID` table column would `MatchError`; unexercised in stdlib.
**Records are flat maps of primitives; nested structure must be `data`.**

Type expression strings can be parsed against the env with `NewPipeline.replType`
(`rename/NewPipeline.scala:174`; Console `:kind`, `session/Console.scala:534-547`).
`Con` equality is by name only (`Type.scala:532-536`), so enriching `ConDecl` does
not disturb `.ei` files or the G1 oracle.

### 2.4 Strategy comparison

| Strategy | Works for user library types? | Loses | Decode params? | Schema? | Effort | Verdict |
|---|---|---|---|---|---|---|
| A. Pure reflective walk (`Runtime => Json`) | yes, immediately | field names; empty-container types; Long precision unless Json ADT fixed; Maybe-vs-Nullable-vs-null; relations | ambiguous (`Num` → Int/Long/Double, `[]` → List/tuple/unit, `{}` → Rec/Map/ctor) | no | S | seed of the encoder, insufficient alone |
| B. Reflective + `DataConDecl` registry + static type at the boundary (**chosen**) | yes | nothing for the serializable fragment; existential/function/foreign fields rejected at export | deterministic, type-directed | yes, from `Type` + registry | M | automatic, no syntax change |
| C. Builtin structural `Json a` constraint (Scala `Instance.reqs`) | yes, once registry exists | same as B (it only *rejects*) | — | — | S on top of B | add for compile-time errors at the widget boundary; needs `lsp/Resident.scala:212`-style scrub |
| D. `deriving` + real instances/dictionaries | — | — | — | — | XL | no parser, no dictionaries, untyped evaluator; also would start enforcing today's silently-discharged user constraints |
| E. Explicit `Codec a` witness values (Elm/PureScript style) | only where hand-written | nothing | yes | yes (witness doubles as schema) | M | keep as opt-in override for bespoke encodings; not the default (reintroduces per-type boilerplate) |
| F. Retrofit f0 with a JSON sink | no | names (F index is phantom: `f0/Writers.scala:11-12,23`; sums are positional bytes `f0/SumsWriters.scala:12-13`) | — | positional strings only (`f0/Languages.scala:27-28`) | L | reject; f0 stays for BackendServer/RemoteScanner/BulkLoad/HMAC handles |
| G. TS-first zod / shared IDL | — | row types; inverts the goal | — | — | M/L | reject |

What B still cannot do: name positional constructor fields. That is a language
gap, not a serializer gap — see §3.1 for the recommended (small) syntax change
and the convention that works without it.

## 3. Recommended architecture

### 3.1 The Ermine side: types are the contract

1. **Registry (core, S).** At `Session.scala:776` and `Lib.scala:43` replace the
   anonymous `ConDecl` with `DataConDecl(constructors: List[(Global, List[TypeVar], List[(Option[String], Type)])])`
   (existentials kept per constructor). Populated from `DataStatement` on both
   the batch and LSP paths (both call `processTypeDefComponent`). Scrub per
   module in `lsp/Resident.scala:212` like `classes`; merge in `SessionState +=/:=`.
   A third anonymous `ConDecl` is built in `Subst.scala:1249` (`checkTypeDefComponent`,
   reached from `Subst.checkModule`); confirm whether that path is live before
   Stage 0 and update it if so. `processTypeDefComponent` runs for every module
   before the Full/Interface split (`Session.scala:833`, `:855-873`), so
   `.ei`-loaded modules get the registry too.
2. **Named constructor fields (surface + core, M; optional but recommended).**
   Extend `dataConDef` (`surface/SurfaceParsers.scala:653-659`) to accept
   `C { x : Int, ys : List Int }`, carry names in `SConDef`/`DataStatement`, leave
   the runtime positional (`accumData` unchanged). Constructor field types are
   unrestricted, unlike `field` declarations (§3.1b), so this is the nesting
   construct. Without this, use the
   convention: all-nullary type → string enum; otherwise `{"tag": C, "args": [...]}`.
   With it: `{"tag": C, "x": 1, "ys": []}`. Widget props in the stdlib should use
   named fields. Operator constructors (`:+:`) and constructors that differ only
   by fixity precedence (`Name.scala:36` compares `fixity.con` only) are rejected
   at export: a tag must be an alphanumeric constructor name, otherwise
   `z.discriminatedUnion` has no stable key.
3. **`Json` stdlib type** (`modules/Json.e`):
   `data Json = JNull | JBool Bool | JNum Double | JInt Long | JStr String | JArr (List Json) | JObj (List (String, Json)) | forall r. JRel (Relation r)`
   with `rel : Relation r -> Json` as sugar. The encoder maps a `Json`
   value to itself (identity case in the walker); `JRel` is the only node that
   needs the runner's effect; delivery is chosen per relation with the
   `Inline`/`Deferred` wrappers, or per request by default (§3.4a). Escape hatch for widgets that need raw JSON.
4. **Document types** (`modules/Layout/Doc.e`): `data Node = Widget String Json | VFlow (List Node) | HFlow (List Node) | Grid … | Tabbed (List (String, Node)) | …`,
   `widget : String -> a -> Node; widget k p = Widget k (toJson# p)`. A report is
   `report : Params -> Node` (or `-> IO Node` where IO is needed). Layout
   combinators are ordinary constructors, not Writer methods.
5. **Minimal FFI** (load-verified reflectively like everything else,
   `tracker/07-ffi-verification.md:8-9`; declare as static `function`s to avoid
   the value/method blind spot `:35-38`):
   - `toJson# : a -> Json` — the reflective+registry walker (pure; `Rel` → `JData r Inline`).
   - `fromJson# : Prim a -> Json -> Maybe a` style helpers are **not** needed for
     params (see 3.3); optionally `parseJson# : String -> Maybe Json`.
   - no `handle#`: deferral is the `Deferred` wrapper, resolved by the runner (§3.4a).
   Nothing else. The 46+8 `method` lines and `Writer` go away for the new path.

Encoding policy (fixed in one Scala object, `core/json/Encode.scala`, documented
as *the* mapping; mirrored by the schema exporter and the params decoder):

| Ermine type | JSON | Note |
|---|---|---|
| Int/Short/Byte | number | exact |
| Long | **decimal string** | JSON numbers lose precision > 2^53; today `html/HTMLWriter.scala:229-238` already rounds via `extractDouble`. zod: `z.string().regex(/^-?\d+$/)` |
| Double | number; NaN/±Inf → encode error | `backends/SQLBackend.scala:111` already drops them on insert |
| Bool | boolean | both `Data(True)` and `Prim(Boolean)` accepted |
| String / Char | string | |
| Date | `"YYYY-MM-DD"` in GMT | DateT values are GMT-midnight (`sql/SqlExecution.scala:55-56,73`; `util/YMDTriple.scala`) |
| Timestamp | ISO-8601 with ms and `Z` | match Timestamp **before** Date (subclass) |
| GUID | canonical string | |
| Nullable a / Maybe a | `a \| null` | nested `Maybe (Maybe a)` rejected at export; decoder re-attaches the `PrimT` from the schema for `Null` |
| List a / Vector a / List# a | array | `::` spine walked iteratively |
| (a, b, …) / () | fixed-length array / `[]` | |
| `{..(\|f1..fn\|)}` closed record | object, unqualified keys, `additionalProperties:false` | keys in sorted order in both the encoder and the schema (`Rec` is an unordered `Map`, `Runtime.scala:161`); export fails on key collision across modules (§6) |
| open row `{..r}` | export error unless instantiated | encoder still works (it sees the Rec) |
| `data` all-nullary | string enum | |
| single-constructor `data` with named fields | plain object, no `tag` | the common props shape (§3.1b); a `Maybe` field is an optional key; a field of type `Spread Json` is merged into the parent object and exports as unknown additional properties. BUILT, Stage 1a (§3.7a); the `Spread` half BUILT in Stage 2b (§3.7b') |
| multi-constructor `data` with named fields | object, `"tag"` first, then the fields in declaration order | BUILT, Stage 1a (§3.7a) |
| `data` with positional fields | `{"tag": C, "args": [...]}` | |
| Relation r | `JData` → §3.4 | never inline in `toJson#` |
| Fun / IO / FFI / existential field / foreign Prim (except the widget-support witnesses, §3.1a) | encode error with location; export error | `Layout/Report.e:73 Report`, `Field.e:22 EField`, `Control/Monad.e:7` are the kind of types that must never reach the boundary |
| Bottom | encode error naming the path | fail the document on the wire. Alternative considered: an `{"error": path}` node so partially good documents survive (the REPL deliberately shows nested Bottoms, `Runtime.scala:142-152`); rejected for the wire because a widget cannot safely render a partial table; kept as a debug flag on the `:json` REPL command |

### 3.1a Foreign widget-support types (Format, Presentation, Legend, Column)

`Format a` (`modules/Layout/Format.e:18`), `Presentation`, `Legend` and `Column`
are foreign Scala witnesses, so the generic walker sees `Prim(x)` and the policy
above would reject every widget that carries a column format. Decision:
`Encode.scala` special-cases these four types on the Scala class of the `Prim`
payload and uses a hand-written codec for the `Format` ADT (15 cases incl.
`Pr2`, `Conditional`, `ColorFormat`, `Markdown`; `Condition` at
`core/writers/Legend.scala:580-612`, `Format` at `:616-948`), `Presentation`
and `Legend`. The matching JSON Schema fragments are hand-written once and
registered under `$defs` (`ermine:Layout.Format`, …) so zod derives them like
everything else. This is the only hand-maintained codec in the design; a
consistency test pins it to the ADT so a new `Format` case fails the build.
Longer term, replace the foreign witness with an Ermine `data Format` in the
stdlib so the generic path covers it; not required for Stage 3. Effort: M.

### 3.1b Nested objects: records are rows, `data` is structure

API responses are large objects whose entries are objects; a Highcharts config
is the canonical case. Ermine has two shapes and they must not be confused:

| Shape | Construct | Restriction | JSON |
|---|---|---|---|
| Tabular | `{..r}` records, `[..r]` relations | fields are primitive DB column types only: `Session.scala:1358-1361` looks each `field` type up in `primTypes` and dies with "Invalid field type". The runtime `Rec` is an unrestricted map (`Field.cons`, `Lib.scala:472`), but the only `Field` witnesses come from that declaration or from `existentialF` with a `Prim a` | flat object, or columns + rows |
| Nested | `data` constructors | arguments may be any type: records, lists, `Maybe`, other `data`, relations, `Json`; positional today | object with keys once named fields exist (§3.1 item 2); `tag` + `args` until then |

The record restriction is deliberate: `{..r}` doubles as the row type of
`[..r]`, and the primitive rule is what keeps `toHeader`, `project` and SQL
pushdown sound. Lifting it looks small because the runtime does not care, but
every relation operation would then have to reject non-primitive rows at its
use site, on top of the row-constraint cliff (`tracker/ROW-CONSTRAINT-STATE.md`).
**Rejected.** Nesting goes through `data`, which never touches rows.

Three ways to produce a nested object; the first two are used:

1. **Now, untyped: build `Json` directly.** `Json` is an ordinary Ermine type,
   so `hcConfig title ss = obj [("chart", obj [("type", str "line")]), ("title", obj [("text", str title)]), ("series", arr (map series ss))]`
   works in Stage 0 with no compiler change and copes with heterogeneous
   corners (a Highcharts point is a number, a pair or an object). The schema
   exporter can only say `unknown` for such a prop; TS validates it against the
   library's own types. For pass-through configs that is the correct source of
   truth anyway: Highcharts owns that contract, not Ermine.
2. **Soon, typed: named constructor fields** (§3.1 item 2, pulled forward to
   Stage 1 by this need). `data HcSeries = HcSeries { name : String, kind : String, points : List Double }`,
   `data HcConfig = HcConfig { title : HcTitle, xAxis : HcAxis, series : List HcSeries, extra : Spread Json }`.
   Policy (in the §3.1 table): a single-constructor type encodes as a plain
   object with no `tag`; a `Maybe` field is an optional key; a field of type
   `Spread Json` (a stdlib wrapper) is merged into the parent object at encode
   time and exports as unknown additional properties, which covers the long tail
   of options nobody wants to model.
3. **Not recommended:** lifting the record restriction (above).

Charts specifically: do not emit full Highcharts configs from Ermine. Emit a
small typed chart spec (titles, axes, formats) plus the series as a relation;
the TS widget maps it to Highcharts and builds the `[x, y]` arrays from
columns + rows client-side. Series data is the large part and it is tabular,
and library version churn stays out of Ermine. The `Json` builder remains the
escape hatch for a widget that genuinely needs a raw config.

### 3.2 Widget document shape (wire)

```
{ "version": 1,
  "settings": { "dateFormat": … },                       // replaces window.htmlWriterExtensions (HTMLWriter.scala:358,366)
  "root": { "kind": "vflow", "children": [
      { "kind": "widget", "widget": "table", "key": "t1",
        "props": { … zod-validated per widget … },
        "data": { "kind": "inline", "columns": [...], "rows": [[...]] }
              | { "kind": "deferred", "columns": [...], "token": "…", "expires": "…" } } ] } }
```

Rules: no strings containing HTML or JS; the inline-vs-handle choice is a tagged
union, not `Array.isArray` sniffing (`js/ermine/tables.js:1219`,
`js/ermine-htmlwriter.js:223,262`); dates are typed by the column descriptor, not
by "3-number array" sniffing (`js/ermine/utils.js:267-275`); `Format` is one
object schema derived from the `Format` ADT (`core/writers/Legend.scala:616-948`),
carried once per column, not per cell (`html/HTMLWriter.scala:544-550` repeats it
per cell; two incompatible encodings today `:208-227` vs `:269-347`); style hints
(`"no-table-pagination"`, `"hflow@cls"`, `html/HTMLWriter.scala:101-130,1057-1058`)
become typed props. The client is a ~20-line dispatcher `renderers[node.widget](target, node)`
over a registry of TS components; the existing `runTabular`/`runTimeSeries`/…
renderers can be wrapped as the first registry entries.

Date formatting is owned by the client from the typed column plus
`settings.dateFormat`; both the Highcharts format-string path
(`html/JsSettings.scala:18-29`, `wrapHeader`) and the ThreadLocal
`SimpleDateFormat` for tables (`html/HTMLRunner.scala:579-585`) go away.
Client-only table state (column reorder `currentTargets`, `tblExpansions` in
`js/ermine/tables.js`) stays client-only; the data endpoint takes no
column-order or expansion parameters (to confirm against production, §6 #21).

### 3.3 Params decoding

Today params enter as an opaque Scala `I` (`html/HTMLRunner.scala:85-87 ReportsCache[F, I]`,
`WSpec[Z] = I => Writer[F,Z] => F[Z]`), produced by `prepRun#`
(`ermine-writers/.../Layout/Writer/HTML/Runner.e:11-12`) via `Native.Function.function1`
which wraps the argument as `Prim(x)` (`Lib.scala:1331` — **not** `whnfForeign`,
see §7). The test server passes `SortedMap[String,String]`
(`ermine-writers/htmlTestServer/.../WebServer.scala:56,132-137`).

New: the report binding `report : Params -> Node` is looked up in
`SessionEnv.termNames` (its type scheme is there; `Session.eval` also returns
`(Type, Runtime)`, `Session.scala:691-704`). The runner decodes the request JSON
against `Params` with `core/json/Decode.scala`: Type-directed, building `Data`
via the constructor `Global` from the registry (`Runtime.accumData` semantics),
`Prim` values by `PrimT`, `Null` with its `PrimT` witness, `Rec` from a closed row
(`FieldConDecl` types), then applies `Fun.apply1`. Requirements: the entry type
must be **monomorphic and closed-row**; decode errors are reported with a JSON
path. Do not reuse `PrimT.coerce` (its Date pattern `"YYYY/mm/dd"` is week-year +
minutes, `PrimT.scala:239`). `primCata` (`modules/Prim.e:23-47`, `Lib.scala:1374`)
is the existing per-`PrimT` eliminator and can seed the typed primitive decoder.

### 3.4 Data handles, streaming, relation wire format

Today (data-path lane, all verified): regular tables are **always inline**
(`html/HTMLWriter.scala:1034-1035` passes literal `Local`; `:70-73 localIf`), each
cell an object `{formatted, raw, format}` with pre-rendered HTML
(`:544-550,609-645`) — a synthetic model puts this at ~8x rows-as-arrays
(§7: modelled, not measured). Paging via `tableData` re-runs the full query, sorts
in memory, slices, and runs a separate COUNT per page (`core/writers/Tabular.scala:242-253,260-266,273-276`;
`html/RelationRunner.scala:203-215` builds a fresh Tabular per request); no
`Limit` pushdown though the node exists (`relational/Rel.scala:41`). Handles embed
the whole `Ext` AST including every literal row with the column name repeated
per cell (`remote/RelationFormat.scala:24-25,274,454`; `mkRelation#` →
`SmallLit`, `Runtime.scala:356-366`), are signed under a constant namespace with
TTL `"never"` by default (`html/HTMLWriter.scala:445-448,454`), compared
non-constant-time (`html/HTMLHMAC.scala:88`), fall back to a random key
(`:113-118`), and can trigger DDL on replay (`MemoR` → `SqlCreateIfNotExists`,
`relational/SqlScanner.scala:915-923`). Only the relation is signed; legends,
presentations, op-lists and colours are unsigned f0 blobs evaluated server-side
(`html/HTMLWriter.scala:470-479`; `html/HTMLRunner.scala:450-454,476-477,490-492`).

The JDBC source itself streams: one `Record` per `rs.next` with fetchSize 10000
(`sql/SqlExecution.scala:47-51,90-91`), driven by a tail-recursive fold
(`relational/package.scala:93-110`); materialization comes only from
`Process.wrapping` (`machines/.../Process.scala:91-104`). The connection is one
per outer `Run.run` on a ThreadLocal (`Run.scala:149-171`; `backends/DB.scala:106-117`,
no pool in-repo), so streaming to the socket must happen inside `R.run` with
temp tables alive (`SqlScanner.scala:266-278`). Mem plans (hash joins, groupBy,
memo `SqlScanner.scala:657-665`) still materialize.

Design:

| Piece | Decision |
|---|---|
| Inline wire | `{"columns":[{name,type,nullable,len?,format?}],"rows":[[…]],"rowCount"}`; column `type` ∈ the 10 `PrimT` names (`PrimT.scala:74-213`); cells per §3.1 (Long as string, dates ISO, `null`); `Rel(ExtRel(RelEmpty(h)))` → `columns` from `h` and no rows; a header-less `EmptyRel` (`Lib.scala:342`) takes its columns from the static relation type when the runner knows it, otherwise encode error |
| Inline threshold | v1: every relation inline in the single response object (§3.4a), with a per-relation row/byte threshold logged; later: relations above the threshold switch to `Handle` without changing the document format |
| Handle v2 | opaque token = HMAC over (query AST bytes, legend/format descriptor, **scope** = {tenant/user/report id}, expiry) with mandatory TTL, constant-time compare, key required (no random fallback); literal relations above N bytes are spooled server-side by content hash and referenced by id, not embedded; `MemoR/TableProc/ProcedureCall` refused unless whitelisted; the signed payload stays f0 bytes (`rwriter`, `html/HTMLWriter.scala:468`): only the server reads it, the client sees an opaque token |
| Endpoint | `GET /data/{token}?start&limit&sort=[[col,dir]]&restrict=…` → NDJSON: line 1 column descriptors, one array per row, trailer `{"rowCount":…}` or `{"error":…}`; sort/limit pushed as `Rel` nodes; restricts typed by column `PrimT` (today Int-only, `html/HTMLRunner.scala:527-534`) |
| Streaming impl | `R.run(S.scanExt(ext, Process.apply(r => writeRow(r)), order))` with `Monoid[Unit]`; needs `Json.write(j, Appendable)` and a hand-rolled row encoder that bypasses the ADT in the hot loop; MySQL cursor streaming is not implemented today: the `Integer.MIN_VALUE` recipe at `sql/SqlExecution.scala:41-46` is a comment and `:49` sets 10000 unconditionally (production is MSSQL, so this matters only if MySQL is in use) |
| Formatting | client formats from `raw` + column `Format` (lands in Stage 3, §5); no server HTML (removes the `Markdown.scala:309 // todo escaping` XSS surface) |
| `Json.Num` | change to `Num(text: String)` (lexeme) with `double`/`long` accessors; printer writes text verbatim; parser stores the substring — a shared change with the LSP (`lsp/Rpc.scala:27,49-50,141-142`) |

### 3.4a Single-object responses with inline relations (v1 requirement)

Requirement (user, 2026-09-01): a report response is **one JSON object** with
every relation serialized inline in it; no separate data endpoint in v1. This
is compatible with writing during the scan: the document is printed from the
top, and each relation's rows are appended to its `rows` array as the cursor
yields them, so the client still receives and parses one object.

| Piece | Decision |
|---|---|
| Ermine | `JRel : forall r. Relation r -> Json` in `modules/Json.e`; `rel : Relation r -> Json` sugar; `toJson#` maps a runtime `Rel` to it and nothing else touches relations. Delivery wrappers `Inline r` / `Deferred r` below |
| Scala document | `core/json/Doc.scala`: the `lsp/Rpc.scala` JSON cases plus `Data(ext: Ext[Nothing,Nothing], header: Header, order: List[(String, SortOrder)])`; the header comes from the plan (`relational/Rel.scala:272 def header`), so column descriptors are written before the scan starts |
| Writer | `Write.doc[G[_]](d: Doc, out: Appendable)(implicit S: Scanner[G]): G[Unit]`; pure nodes append text; `Data` writes `{"columns":[…],"rows":[`, then `S.scanExt(ext, Process(rec => appendRow(out, rec)), order)` under `Monoid[Unit]` (`relational/Scanner.scala:25-27`), then `]}` |
| Effect | `type DB[+A] = Connection => A` (`backends.scala:6`): the whole document write is one `Connection => Unit` executed by `R.run`, so every relation in the document scans sequentially on one connection, in document order, with temp tables alive (`relational/SqlScanner.scala:266-278`) |
| Row encoder | hot loop over `Record = Map[ColumnName, PrimExpr]` in column order, appending text directly (no `Json` nodes); per-`PrimT` cases from the §3.1 policy table; string escaping shared with `lsp/Rpc.scala prString` |
| Column order | the widget's `Legend` when it gives one, else header keys sorted (`Header` is a `Map`) |
| Failure policy | follows the inlining strategy, a per-request setting (below): `Buffered` keeps HTTP error semantics, `Streamed` reports failures in an `"errors": [...]` array reserved as the **last** key of the top-level object; the client checks it before rendering. `Write.doc` has the same signature for both; only the sink changes |
| Transport | chunked encoding, no `Content-Length`; if a proxy insists on one, write into a buffer first and lose only the streaming benefit |
| Size guard | the client holds the whole object; the request's `data.threshold` turns any *bare* relation above it into `Deferred`; log per-relation row and byte counts in v1 to set the default (§6 #23) |

**Two switches, two homes.** The implementation commits to neither
streaming nor up-front materialisation; the runner resolves each `Data` node
with a policy `(Data, RequestConfig) => Buffered | Streamed | Defer`.

*Switch 1, delivery: now or deferred.* Visible to the client, so it lives in
Ermine types as wrappers the walker recognises by constructor `Global`:

```
data Inline   r = Inline   (Relation r)   -- rows in this response
data Deferred r = Deferred (Relation r)   -- header now, rows on re-request
```

A bare `Relation r` means "request default". The `data` slot is a tagged
union with the same `columns` in both arms, so the client renders the header
immediately either way:

```
{ "kind": "inline",   "columns": [...], "rows": [[...]], "rowCount": 2 }
{ "kind": "deferred", "columns": [...], "token": "…", "expires": "…" }
```

A deferred re-request (`GET /data/{token}`) returns exactly the inline object
for that one relation, so the client has a single data renderer. v1 token: a
random id keyed to a server-side cache of the plan with a TTL; the signed,
scoped Handle v2 of §3.4 is hardening, not a prerequisite. The schema exporter
sees the wrapper: `Inline r` exports only the inline arm, `Deferred r` only
the deferred arm, a bare `Relation r` the union.

*Switch 2, inlining strategy: buffered or streamed.* Invisible on the wire
except for failure semantics, so it stays out of Ermine types and is a
per-request setting with a server default. One row encoder, one `scanExt`
call; only the sink differs:

| Strategy | Sink | Failure |
|---|---|---|
| `Buffered` | rows stream into a per-relation text buffer, appended to the response on success; only text is held, no `Record`s | HTTP error status |
| `Streamed` | rows go straight to the response | `errors` trailer |

Request body: `{"params": {...}, "data": {"default": "inline" | "deferred", "strategy": "buffered" | "streamed", "threshold": rows}}`.
An explicit `Inline`/`Deferred` wrapper always wins over `data.default`.
v1 ships `Buffered` + `Deferred`; `Streamed` is added when a relation is large
enough to justify trailer semantics.

Still true from §3.4: Mem plans (hash joins, groupBy, memo) materialise on the
Scala side before the first row is emitted, and today's writers materialise
everything (`html/HTMLWriter.scala:556,1028`, `html/RelationRunner.scala:70,235`
via `Tabular.takeAll` → `Process.wrapping`, `core/writers/Tabular.scala:62,307`).
The NDJSON endpoint and Handle v2 in §3.4 become an optimisation for relations
above the threshold, not a v1 deliverable.


### 3.4b Fetching reports: `Params -> Fetch Node` (J3f, 2026-09-18)

`Layout.Doc.Node` never sees a row: a relation in a widget's props is a plan the writer scans
after evaluation (§3.4a). That is what makes deferral possible, and it is also why nothing like
the old `Layout.Report.scanRelation` (`Report.e:617`, CPS over the writer's effect,
`Writer.scala:246`) existed here: a heading with a total, a layout whose shape is in the data,
and a list transformed in memory and returned to SQL through `Relation.relation` (a `SmallLit`,
`Runtime.scala:386`) all need rows while the report is built.

| Decision | Choice | Rejected |
|---|---|---|
| where the continuation lives | a separate type `data Fetch a = Done a \| Scan Sort# Relation# (List Record# -> Fetch a)` in `modules/Layout/Fetch.e`; `Node` and the client's zod schema untouched | a `Scan` constructor inside `Node`: an existential function field in the exported wire type (`client/src/generated/doc.ts` is generated from `Node` and `check-generated.sh` fails the build if stale) |
| monad | none; CPS as before. `Relation.Scan` needs only a `RunScan` over a fixed result type, and `Cont` is over the continuation, not over `a` | a `Monad Fetch` instance: only needed to lift `vflow` over `Fetch`, which is not offered; a scan is hoisted above its layout, or several go in one `do` under `runScan` |
| row type erasure | `Sort#` / `Relation#` / `Record#`, as `scanRelationDMTL` erased it; `unsafeRecordIn#` restores `{..r}` | an existential row in the constructor |
| interpreter | `Runner.renderFetch`: decode, then evaluate AND write inside one `Run[DB].run`; every evaluation step (`evalStep`) takes `evalLock`, every scan runs outside it; rows go to the continuation as the Ermine list `fromList#` would build (`rowsRuntime`) | evaluating before the connection opens (impossible: the evaluation scans); holding `evalLock` across a scan (a slow query would block every other report) |
| delivery | a relation that survives into the final Node is still a plan and follows §3.4a; only the rows a `Scan` asked for are read early | -- |
| failure | a throwing continuation is the same 500 as a throwing report; a throwing scan is `ScanFailed(n)`, a 500 naming the report and the scan's position | -- |

Cost: a fetching report whose evaluation fails used to have opened its connection for nothing.
J3g removed that (§3.4c): the FIRST evaluation step runs before `cfg.run.run`, so a report that
fails to evaluate opens no connection at all, and one that scans opens exactly one
(`TestRunner (fx-conn)`, `(fxl-conn)`). Examples:
`core/src/test/resources/doc/Fetch{Headline,Running,Tabs,TopN,Fragments}.e`.

### 3.4c `Fetch Node` as the report type (J3g, 2026-09-18)

J3f left `Fetch` usable only above a layout: `Node` is what every layout combinator takes, so a
scan had to be hoisted to the top of the report (`scanRelation r (rows -> done (vflow [..]))`)
and no widget's smart constructor could scan. J3g lifts the layout instead. `Fetch` is still the
J3f type (§3.4b decisions stand: a separate CPS type, no `Monad` instance, the same interpreter),
and a report is now written as one `Fetch Node`, cut into fragments of type `... -> Fetch Node`.

| Decision | Choice | Rejected |
|---|---|---|
| lifts | plain functions in `modules/Layout/Fetch.e`: `map_Fetch`, `bind_Fetch`, `sequence_Fetch` (left to right), and the layouts `vflowF`, `hflowF`, `gridF`, `tabbedF` over `Fetch Node` (`Layout.Fetch` imports `Layout.Doc`; `Doc` does not import `Fetch`) | a `Monad Fetch` instance: `Relation.Scan` still only wants `RunScan_S`, `Cont` is still the monad over the continuation, and `do` notation would not make `vflowF` shorter |
| the report type | `Params -> Fetch Node`. `Params -> Node` is SUGAR: `resultKind` still classifies it, but the runner reads a value that is neither `Done` nor `Scan` as the document itself, so there is ONE interpreter and no `fetching` flag on `Report` | two render paths (J3f's `build`+`write` beside `renderFetch`): two orderings, two error vocabularies, two things to keep in step |
| where the connection opens | the first evaluation step (decode, apply, force) runs under `evalLock` BEFORE `cfg.run.run`. `Done`/a bare `Node` is written on the one connection the write opens; only a `Scan` opens one to continue evaluating in | keeping J3f's "evaluate inside the connection": a report that throws before any scan paid for a connection |
| a widget that scans | `Layout.Widgets.Headline`: `headline : HeadlineProps -> Node` (pure) beside `headlineOf : ... -> Field h Double -> rel r -> Fetch Node`, which scans, counts, sums and takes the maximum. Registry name `"headline"`, client component `client/src/widgets/headline.ts` | a `Fetch`-valued field inside `Node`: the wire and the generated zod stay what `Node` says |
| the prop names | `headlineTitle`, not `title`: `Layout.Widgets` re-exports every widget module into one scope, and `Layout.Widgets.Scorecard` already owns `title` (`Layout.Widgets.Chart` spells `chartTitle` for the same reason). Verified: with `title`, `title p` on a `ScorecardProps` in a module importing `Layout.Widgets` fails to unify | -- |
| order | `sequence_Fetch` and the layout lifts scan left to right, in the order the children are written (`TestRunner (fxl-order)`) | no order guarantee: a running total or a rank would be unreproducible |

Cost: a widget that owns its scan reads the relation itself, so a report that also shows the rows
in a table scans twice (`FetchHeadline.e` says so). `Fetch` has one operation, so nothing about a
widget makes this special; a caller holding the numbers uses `headline` and scans once.

### 3.4d One interpreter: call, splice and token as one step stream (J3h, 2026-09-18)

Until J3h there were two loops over one thing. `Write.doc` walked a document and, per relation,
scanned a plan and applied a SCALA continuation (splice the rows in, or mint a token);
`Runner.interpret` walked a `Fetch` and, per `Scan`, scanned a plan and applied an ERMINE
continuation. They met only when the second finished and called the first. Each had its own
failure type (`WriteFailure` with a path, `ScanFailed(n)`), and only the first had stats, log
lines and a threshold. J3h keeps one loop over one step type (`json/Interp.scala`), so a fetch
scan is logged and measured like a wire relation and a later kind of work -- a cached `Fetch`
behind a token, a batched `ScanMany` -- is a new step, not a third loop.

| Step | What the driver does | Built by | Was |
|---|---|---|---|
| `Eval(next)` | force `next()` and push the steps it answers | NOT the runner today -- see below; `TestDoc.fetchProgram` builds them | `evalStep` |
| `Call(order, ext, path, k)` | scan `ext` OUTSIDE the lock, collect every record, record a `RelationStats` for `path`, push `k(rows)` (the runner's continuation: one evaluation step under `evalLock`, answering the next steps) | `Runner.evalStep` on a `Scan` | `interpret` |
| `Emit(text)` | append the text | `Write.steps` | `Write.doc`'s `Text` |
| `Splice(data, threshold)` | scan into a `Rows.Sink` and write the inline object at `data.path`; over the threshold it writes the deferred handle instead | `Write.steps` | `Write.inlined` |
| `Token(data)` | `cache.put` and write the deferred handle | `Write.steps` | `Write.deferred` |

The `Eval` row is the one step the runner does not build (R2): a report's FIRST evaluation is
`render`'s own call to `Runner.evalStep`, which must happen before the driver starts (it is what
decides whether a connection is opened at all, §3.4c), and every later one is the `Call`'s
continuation, which the driver invokes after the scan and which answers the next steps directly.
`Eval` is therefore the driver's arm for a step stream that extends itself without a `Call` --
what a cached `Fetch` behind a token or a batched `ScanMany` would push -- and today only
`TestDoc (ip-fail)`'s generated programs build one. Wrapping the `Call` continuation in an
`Eval` would make the row literally true at the price of one more bind per scan on a chain that
is already 2,000 deep in `(ip-stack)`; the row says what happens instead.

What the lock covers: the runner's evaluation holds `evalLock` for forcing the value and for
WALKING it (`Doc.fromRuntime` reads the runtime), and nothing else. Turning the walked `Doc` into
the text runs of `Write.steps` reads no session state and happens outside the lock, as it did
before J3h -- it matters for a fetching report that folds its scanned rows into pure widgets
(`FetchRunning`, `FetchTopN`), whose printing would otherwise queue every other request.

`Interp.run(steps, out, cfg, cache)` consumes the stream inside one `G` action. `Write.doc` is
now `Interp.run(Write.steps(d, cfg), ..)`; `Write.relation` (the `/data/<token>` re-request) is a
one-`Splice` run; `Runner.render` is "first `Eval` under the lock and outside the connection
(§3.4c), then `Interp.run` inside one `cfg.run.run`". `Runner.interpret`, `renderFetch`, `write`
and `ScanFailed` are gone; `evalStep` answers STEPS instead of a `Doc`-or-scan, and `Write.one`,
`inlined`, `deferred` moved to `Interp` unchanged.

Four decisions this change makes:

| Decision | Choice | Rejected |
|---|---|---|
| **Stats** | a `Call` yields a `RelationStats` like a wire relation: `path` = `$.fetch[n]` (n = the scan's 1-based position in the report, the number `ScanFailed` used), `delivery` = a new `Delivery.Fetched`, `rows` = the records handed to the continuation, `columns` = 0 and `bytes` = 0 (nothing of it goes on the wire), `millis` from the scan's start. It is logged on `ermine.json.doc` in the same `line` shape, and `WriteStats.relations` holds it IN EXECUTION ORDER, so the fetch scans come before the wire relations (`TestRunner (ip-stats)`) | a separate list or a separate log: two places to look for "what did this request read". `Delivery` is not on the wire (`Wire.Inline`/`Wire.Deferred` are the wire's words) and nothing exported reads it, so the enum could take the fourth case |
| **Failure** | one exception type. A fetch scan that throws is `WriteFailure("$.fetch[n]", ..)` with `completed` = every step finished before it, fetch scans included; the 500 is therefore `cannot write $.fetch[n]: <why>`, the same sentence a wire relation gets, and the response's `error.path` is `$.fetch[n]`. A throwing CONTINUATION (Ermine) is unchanged: `<module>.report failed: ..`. The driver knows nothing of `RunError`, so an evaluation failure travels through it as `Runner.Abort` and is unwrapped outside | keeping `ScanFailed`: a second failure vocabulary for the same event, and a 500 whose path field was `null` although the failure had a perfectly good path |
| **Threshold** | `data.threshold` does NOT apply to a `Call`: a fetch scan reads every row, as J3f and J3g did. `(ip-stats)` pins it (its cases include thresholds of 0..4 and the fetch entries still carry every row) | capping a fetch scan: the report asked for the rows to compute with; half a list is a wrong answer, not a smaller one. A cap belongs with a way to say what the report should do when it hits one -- the open ticket "a cap on fetched rows" in the plan |
| **Order of effects** | byte-identical to J3g for every document: the wire relations still scan in document order, after the last `Eval`; nothing is reordered, nothing is batched | reordering scans (e.g. all scans of a document first): the wire contract says rows arrive in document order, and a deferred token minted early would change what `/data/<token>` returns |

Stack: the action is a right-nested chain of binds, one per STEP -- the shape `Write.doc` had
before J3h, with scans now in the same chain. Steps that an `Eval` or a `Call` answers go on a
work LIST, not on the JVM stack, so 2,000 sequential scans are 2,000 binds and no deeper
(`TestRunner (ip-stack)`: 2,000 scans through SQLite in 16 s). For a strict `G` (the `Id`
scanner of the tests) the whole chain still runs on the JVM stack, and the ceiling is around two
thousand relations, JIT-dependent: measured in one run, the J3g loop survived 2,240 relations
cold and 6,208 warm, the J3h driver 2,048 cold and 8,128 warm
(`tracker/json-stage3/logs/j3h-stack-probe.log`). J3h did not change that ceiling; it did not
raise it either, which would need a `BindRec`/trampolined driver and a `Scanner` that promises
one.

### 3.5 Schema export and zod

- `core/json/Schema.scala`: walk a **monomorphic** `Type` with `Subst.unfurlApp`
  (`Subst.scala:291-295`) + `Con.decl`: PrimT table → JSON Schema types;
  Nullable/Maybe → `anyOf [S, null]`; List/Vector → array; ProductT → tuple
  (`prefixItems`); closed `ConcreteRho` → object via `FieldConDecl`;
  `DataConDecl` → `oneOf` of `{tag, …}` objects or `enum`; aliases expanded
  (`Type.scala:477-499,523-527`) or emitted as `$defs`; Relation → the `data` union of §3.4a (`Inline r` exports only the inline
  arm, `Deferred r` only the deferred arm); errors with source location on Fun/IO/FFI/existential/open row.
  Deterministic output (declaration order, sorted keys, no `Loc`s);
  `x-ermine: {module, type, hash}` where `hash` is SHA-256 of the canonical
  schema text; the document runner embeds the same hash per widget so the
  generated zod asserts it before validating and reports schema drift instead
  of a confusing validation error.
- Entry points sharing that core: `bin/ermine-schema --root … Module.Type …`
  (new main; `bin/ermine:18-25` is a plain wrapper with no subcommands) and an
  `ermine/schema` LSP request (`lsp/Rpc.scala:345 onRequest`; the resident
  session avoids the ~6 s boot).
- TS: commit exported `*.schema.json` and `generated/*.ts` from
  `json-schema-to-zod`; CI regenerates and `git diff --exit-code`s. Tagged
  unions map 1:1 to `z.discriminatedUnion("tag", …)`. Breaking-change classifier
  over the JSON later (removed constructor/property, type change, new required
  → MAJOR).
- Consistency test (core/test, ErmineFixture): for each exported type, generate
  values, `toJson#`, and validate against the exported schema with a minimal
  in-repo JSON Schema checker (subset) — this is what guarantees the value walker
  and the type walker agree.

Source of truth: the Ermine `data`/`field` declarations. The mapping policy
(§3.1 table) lives in one Scala file and is the only thing TS must trust; the
generated zod is derived, never hand-edited. Whether that policy should live in
Scala or be overridable per type from Ermine (option E witnesses) is a team
decision to record (§6 #22).

### 3.6 Effort summary

Scale: S ≤ 3 days, M 1–3 weeks, L 1–2 months, XL a quarter or more. Estimates,
not measurements.

| Item | Effort |
|---|---|
| `Format`/`Presentation`/`Legend` Scala codec + `$defs` schema + consistency test (§3.1a) | M |
| Stage 3 client adapter: rows-as-arrays → renderer cells, `formatDisplay` port to the object form | M |
| `DataConDecl` registry + Resident scrub | S |
| `Json.Num` lexeme + `Json.write(Appendable)` | S |
| `Encode` (Runtime→Json, iterative spine, Bottom policy) + `toJson#` FFI | S–M |
| `Decode` (Type-directed Json→Runtime) + runner entry | M |
| `Schema` exporter + CLI + LSP request + zod codegen + CI check | M |
| Named constructor fields (parser/DataStatement/registry) | M |
| Builtin structural `Json a` constraint (compile-time rejection) | S |
| Document runner (replaces HTMLRunner page path), TS dispatcher, widget zod schemas for the 7 live widgets | M |
| Inline rows-as-arrays encoder | S |
| Single-object document writer: `Write.doc` in the DB effect, row encoder, errors trailer (§3.4a) | S–M |
| `Inline`/`Deferred` wrappers, request `data` config, resolver, v1 cache-token deferral endpoint (§3.4a) | S |
| NDJSON streaming endpoint | M |
| Handle v2 (scope, TTL, spool, pushdown) | L |
| Delete dead surface | S |

## 3.7 Stage 0 as built (2026-09-14, branch `json-encode`; 2.11: `json-encode-2.11`)

What landed, and where it departs from the text above.

- **AST: argonaut 6.2.6**, not a hand-rolled `Json` ADT (the user's call: one
  library, one version, published for both Scala 2.11 and Scala 3; the
  `Json.Num` lexeme fix is moot because argonaut keeps numbers as Long or
  BigDecimal).  The LSP's `lsp/Rpc.scala` ADT is untouched.  The Scala is
  written in the 2.11-and-3 intersection (implicit-style typeclasses only,
  no `given`/`enum`/`extension`), and the 2.11 branch carries a copy plus
  the three hook sites.
- **Registry: `DataConDecl.scala`** (a `ConDecl` on the data type's `Con`,
  built in `Session.processTypeDefComponent` and `Lib.dataDecl`; constructors
  by-name because the component's type map is completed after the `Con`
  exists).  Plus a process-wide constructor-name -> declaration map,
  because a runtime `Data` node carries only its constructor's `Global` and
  the FFI primitive runs without a `SessionEnv`; last writer wins on a
  reload, `SessionEnv.cons` stays the per-session truth.  `lsp/Resident`'s
  per-module scrub of `cons` needs no change (the decl rides on the Con);
  the global map keeps stale entries until the module re-registers.  The
  dead `Subst.checkTypeDefComponent` (no callers) still builds the anonymous
  decl.
- **Walker: `json/Encode.scala`**, generic in a `JsonBuilder[J]` with two
  instances: `ArgonautJson` (the wire, used by `:json` and the future runner;
  `rel` refuses) and `ErmineJson` (the stdlib `Json` data type, what
  `toJson#` returns; `rel` yields `JRel`).  Explicit stack: a 100,000-element
  list of records and 2,000 nested lists encode (TestJson); depth is bounded
  only by argonaut's printer, which recurses per level (`Json.fold`) and
  overflows the default stack near 20,000 levels.  The mapping table in
  §3.1 is implemented as written, with one refinement: a constructor the
  registry does not know encodes by its own arity (nullary -> string).
- **Ermine side**: the `Json` type and its constructors are declared in
  `Lib.json` (a Lib primitive's type cannot name a type a module declares
  later), `modules/Json.e` adds `toJson`, `render`, `pretty`, `parse` and
  the builders `jnull`, `bool`, `num`, `int`, `str`, `arr`, `obj`, `rel`.
  `JRel`'s row variable is existential, as `mkDataConstructor` does it.
  The builder for null is `jnull`, not `null`: a top-level binding named
  `null` loads inside a module but is "undefined term" in every REPL / `Session.eval`
  expression (NullTest probe, 2026-09-14; not chased — a REPL-pipeline
  quirk worth its own ticket).
- **REPL**: `:json <expr>` type-checks, evaluates and pretty-prints; an
  unencodable node prints `error: cannot encode <path>: <why>` with the path
  to it (`$[0].Holder[0]`).  A bottom at the ROOT is the console's own
  `runtime error: ...` (`ConsoleEnv.eval` inspects it before the encoder
  runs).  An expression of type `IO a` is NOT run: the `IO` value is an
  unknown constructor holding a `Fun`, so it fails at `$.IO[0]` with no side
  effect.  Smoke: `tracker/repl-tests/json.in`.
- **Gate (Stage 0 row of §5)**: TestJson 26/26 on both branches, full
  `core/test` 1096/1096 (Scala 3) and 761/761 (2.11), corpus verdicts
  identical to scala3-migration (89/79/0 over 168), REPL and LSP smokes
  green.  The stdlib sweep run alone classifies all 96 registered `data`
  types (Builtin excluded; more inside the full suite, where other suites'
  example modules register too, the registry being process-wide), 80
  constructor fields rejected with a location (18 functions, 11 rank-n fields, 8 `Field`
  witnesses, 5 `PrimT` witnesses, 39 fields of foreign types: Presentation 7,
  Magnitude 6, Format 3, the chart option witnesses, `Op`, `Relation#`,
  `Record#`, Color, SortDirection, PresRow, Legend#, SelectorEvent,
  Predicate, PrimExpr#) — the §3.1a hand-codec list, confirmed from the
  declarations rather than estimated.  `replicate 1 100000` encodes.
- **Two mapping details decided in code** (review finding, 2026-09-14): a
  hand-built `JInt` (`Json.int`) is a JSON number while an auto-encoded
  `Long` is a decimal string, the author's explicit choice versus the safe
  default; a `JObj` with a repeated key keeps the last, as argonaut does.
  Also noted, not fixed: `Constructor.existentials` is recorded but the
  classifier does not yet reject existential fields (Stage 2), and the
  walker recognises the stdlib `Json` constructors by module name, so a
  user module named `Json` would collide.
- **Not in Stage 0**: named constructor fields (Stage 1a, §3.7a), `Schema`,
  `Decode`, the `Json a` constraint, the document runner, the `:json` debug
  flag that would show partial documents with error nodes.

## 3.7a Stage 1a as built (2026-09-14, branch `json-fields`)

**Named constructor fields with generated selector functions.**

- **Syntax.** `SConDef` grows `fieldNames: Option[List[SName]]` and keeps
  `fields` as the positional list of field TYPES, so kind inference, the
  renamer's type walk and the LSP's enum/struct choice are untouched.  One
  spelling per constructor: `C { f : t, .. }` or `C t1 t2`; mixing is a
  parse error (the trailing atom is input the `|` level refuses), `C {}` and
  a field name repeated in one constructor are located parse errors.  `{`
  also opens a row-brace TYPE atom, so the brace parse is an `.attempt` and
  `data R = R {a, b}` still parses positionally -- but only the PARSE
  backtracks: once `{..}` has been read as fields the two refusals are
  raised outside the attempt, or they would be swallowed and replaced by a
  misleading row-brace error.
- **Representation.** `DataStatement` grows `selectors: List[Selector]`
  (default `Nil`, which is what keeps the dead `Subst.checkTypeDefComponent`
  honest), one entry per distinct field NAME of the declaration:
  `Selector(name, v: Option[TermVar], sites: List[(TermVar, Int)])`.  `v` is
  `None` when no selector can be typed -- the field's type mentions one of
  its constructor's existentials -- and the field is then still NAMED for
  the registry and the wire.  `sites` carries every `(constructor, index)`
  the selector reads, more than one when constructors of the type share the
  name.  The field TYPE is deliberately NOT stored: `processTypeDefComponent`
  reads it back out of `constructors` through `sites`, so a selector's type
  is by construction the very `Type` `mkDataConstructor` gave that argument,
  after the component's kind inference and substitution, with nothing to
  keep in step.  `definedTerms` includes the selectors.
- **How selectors enter the renamer.** Exactly as a constructor's own name
  does.  `Renamer.collectHeads` records binders for equations and signatures
  only, so a field name's span has no binder and `lctx.varFor` takes its
  placeholder branch, keyed by SPELLING -- the same V every in-module
  reference to the selector gets, which `processTypeDefComponent`'s term map
  then rewrites to the installed primOp.  Imports, exports, `hiding` and
  `private` therefore treat a selector like any other definition, and a
  `private data` block makes its selectors private (one more line beside the
  constructors).  Selectors are installed by `Session.mkFieldSelector`
  (a `primOp` beside `mkDataConstructor`) with the runtime
  `Runtime.selectData`, so the Full and the Interface load both get them and
  the `.ei` format needs no change (pinned: TestNamedFields' interface-parity
  property loads the same module with `useInterface` off, cold on and warm
  on and compares the encoded documents).
- **Collisions are refused AT THE FIELD.** The status quo for a
  constructor/`field`-witness clash is the loader's unpositioned
  `primOp: rebinding M.x`, or `error: loading would overwrite one existing
  global: x` at file:1:1 (probed 2026-09-14; note "two equations of the same
  name" is NOT an error in Ermine -- adjacent equations are alternatives,
  and only separated ones give `error: interleaved equations for f`).  So the
  selector case is refused earlier, as a positioned `Refusal` at the field
  name: against another declaration of the module (a constructor, a `field`,
  a `table`, a foreign name -- from a pre-scan of the surface statements, so
  order does not matter), against a top-level equation or signature, against
  an import (the equation head's own "would shadow global definition"), and
  against another data type's selector.  A field name shared by two
  constructors of ONE type with DIFFERENT types is refused the same way.
- **Runtime unchanged.** `accumData` is untouched: positional construction
  `Series "q1" [1.0]` and positional pattern matching work for a
  record-style constructor, which is what property (e) pins.  A selector is
  a `Fun` projecting one argument; applied to a constructor of the same type
  that lacks the field (`radius Dot`) it is a `Bottom` reading
  `Dot has no field radius`, not `whnfMatch`'s generic panic.  Record-style
  CONSTRUCTION and update syntax are not in this stage.
- **Wire form** (the §3.1 table's "named fields" row, now implemented): a
  record-style constructor is an object keyed in DECLARATION order --
  `{"name":"q1","points":[1.0]}` for a single-constructor type,
  `{"tag":"Circle","radius":1.5}` for a union.  A named field whose
  DECLARED type is headed by `Builtin.Maybe` and whose value is `Nothing` is
  OMITTED (`Nullable` is not: its `Null` carries a `PrimT` and its JSON is
  `null`, not an absent key); a field whose declared type is a type variable
  keeps the walker's `null`.  Positional constructors keep `{"tag","args"}`
  and all-nullary types keep the string enum, so a nullary constructor of a
  record-style union is still `{"tag":"Dot","args":[]}`.  `Encode.reject`
  and the stdlib sweep are unchanged.
- **Noted, not changed**: a PHANTOM type parameter (one no field mentions)
  gives the selector the scheme `forall {k} (a: k). T a -> t`, kind variable
  and all -- but so does the constructor (`forall {k} (a: k). t -> T a`), so
  the selector is consistent with what the type already had.  The LSP shows
  selectors as `KField` symbols and as declaration heads; record-style
  PRETTY PRINTING of the declaration is not built (rule 10), so `:browse`
  and hover still show positional fields.
  **Corrected 2026-09-16 (J3b's landing gate)**: those `KField` symbols were
  children of the DATA symbol, i.e. SIBLINGS of the constructors, and a
  constructor's span runs to the start of the next one — so every record
  constructor's range straddled its own fields' ranges, which
  `TestRenamer` 6.4 ("siblings are sorted, and no two of them straddle")
  forbids and no cursor-to-symbol client can resolve.  It went unseen
  because no module in the corpus had a record-style `data` until
  `Layout/Doc.e`.  A field symbol is now a child of the CONSTRUCTOR that
  declares it (`lsp/Symbols.scala`, the `SDataStatement` case), which is
  what LSP means by Field members and what this builder already did for
  every other container; a name shared by two constructors is one selector
  with two declaration sites and lists under each.  Pinned by two new
  properties in `TestNamedFields` (one over generated declarations, one
  exact tree).
- **Gate**: TestNamedFields 14/14 (nine `forAll` properties over random
  declarations), TestJson 27/27, the parser/renamer suites green, REPL and
  LSP smokes green, corpus verdicts 89 LOADED / 79 REJECTED / 0 UNKNOWN over
  168, unchanged.
### Stage 1b as built (2026-09-14, branch `json-schema`, off `json-encode`)

The SCHEMA EXPORTER half of Stage 1 (named constructor fields are the other
half, on their own branch).  What landed: `json/Schema.scala`
(`Type => JSON Schema 2020-12`, plus `LspSchema` for the request),
`json/Validate.scala` (a validator for exactly the subset the exporter
emits), `json/Zod.scala` (`JSON Schema => TypeScript`, zod 3),
`json/SchemaMain.scala` + `bin/ermine-schema`, the `ermine/schema` LSP
request (one line in `lsp/Definitions.scala`, four checks in
`tracker/tools/lsp-client.py`), eight committed fixtures under
`core/src/test/resources/schema/` and `scalacheck-binding/.../TestSchema.scala`.

Departures from §3.5 and decisions taken in code:

- **`export` is a Scala 3 keyword**, so the method is `Schema.exportType`
  (with a backticked `` `export` `` alias) -- the design note's spelling
  needs backticks in Scala 3 source.
- **Every `data` INSTANTIATION becomes a `$defs` entry** keyed
  `Module.Type_Arg...` (`Test.Tree`, `Either.Either_String_Int`) and is
  referenced by `$ref`, the ROOT included, so a recursive type terminates and
  a zod file has one named `const` per type.  Structural types (`Maybe`,
  `List`, tuples, records, relations) are inlined -- only a `data` can be
  recursive.
- **One constructor means no `oneOf`**: a single-constructor positional type
  exports as the bare `{"tag":…,"args":[…]}` object.  `oneOf` starts at two.
- **Determinism needed a printer change**: argonaut's `spaces2`/`nospaces`
  iterate the field MAP, which is neither insertion nor sorted order, so the
  canonical text is `Schema.text` = `pretty(PrettyParams.spaces2.copy(
  preserveOrder = true))` and `Schema.compact` = `nospacesWithOrder`.
  `$defs` are emitted sorted by key and record properties sorted by name, so
  neither declaration order nor module load order is observable (property c).
- **Type aliases**: `Type.expandAlias` reports `Unexpanded` whenever the
  outermost head is not itself an alias, so `type Ints = List Int` comes back
  as `Unexpanded(List Int)` -- an expansion all the same.  The exporter
  iterates to a FIXED POINT on "the type stopped changing", with a fuel bound.
- **Relation `[..r]`** exports the §3.4a columns+rows-as-arrays object, with
  the column descriptors as `prefixItems` of consts and the column `type`
  const spelled as the unqualified Ermine type name (`Int`, `Date`), with
  `Nullable` unwrapped.  The ENCODER does not produce this yet (Stage 3's
  `Write.doc`); the schema ships now so the TS side can be written against
  it.  The `Inline`/`Deferred` arms are Stage 3 too.
  **Revised in J3a** (2026-09-16, branch `json-wrappers`): a relation now
  exports the DELIVERY UNION of the wire contract in
  `tracker/JSON-STAGE3-PLAN.md` -- a bare `[..r]` is `oneOf [inline arm,
  deferred arm]`, `Json.Inline r` the inline arm alone, `Json.Deferred r` the
  deferred arm alone; each arm is a closed object with a `kind` const, the
  `columns`, and `rows`+`rowCount` (integer, minimum 0) or
  `token`+`expires`; a column descriptor gained a third const, `nullable`,
  and its `type` is now `Wire.columnType` of the field's `PrimT` rather than
  a type name read off the `Con`.  A relation over a row VARIABLE exports a
  GENERIC arm (any columns from `Wire.columnTypes`, rows of scalar cells)
  instead of being an error, so a widget props type `data TableProps r =
  TableProps { rows : Inline r }` has one schema for every `r`; the root of
  an export may leave a data type's row parameters abstract (`exportNamed`,
  `bin/ermine-schema -i Json Inline`), and a `$defs` key spells every type
  variable `_` (`Test.TableProps__`).  An open row outside a relation is
  still an error.
- **A constrained field type reads as rank-n before it reads as a row**: a
  constructor field declared `Field h Int` or `{..r}` with a free row
  variable arrives at the walker as a scheme, so the refusal says
  "polymorphic (rank-n)" rather than "open row".  Both name the constructor
  and the field index; only the wording differs.
- **`z.lazy` + `: z.ZodTypeAny`** for recursion: `tsc --strict` refuses a
  `const` whose inferred type depends on itself (TS7022), so a recursive def
  is annotated and its `z.infer` is `any`.  The runtime check stays exact.
- `x-ermine: {module, type, hash}` (§3.5's drift guard) is NOT implemented;
  the fixtures' byte equality plays that role inside this repository.

Gate (Stage 1 row of §5): `TestSchema` 19/19 + `TestJson` 26/26 = 45/45;
schemas and zod committed for `Ordering`, `Either String Int`,
`Relation.Sort.SortOrder`, `Layout.Report.Direction.Direction`,
`Layout.BorderOptions.BorderOptions Int`, a user record, a user relation and a
recursive user `data`; `npx tsc --noEmit --strict` green over all eight, and
the compiled zod accepts/rejects the encoder's documents at runtime; the
encode/schema consistency property green over 200 generated (type, value)
pairs plus 100 shrinking ones; LSP smoke 577 checks, REPL smoke green.

## 3.7c Stage 3 writer as built (2026-09-16, branch `json-doc`, stage J3b)

The document types, the document writer, the row encoder and the deferred-token
cache: `modules/Layout/Doc.e`, `core/json/Doc.scala`, `core/json/Write.scala`,
`core/json/PlanCache.scala`, `scalacheck-binding/.../TestDoc.scala`.

- **`Layout.Doc.Node`**: `Widget { name, props }`, `VFlow { children }`,
  `HFlow { children }`, `Grid { cells }`, `Tabbed { tabs }`, with
  `Tab { label, content }` — the names of §3.2 with no collision to rename
  (the generic walker of §3.7a turns them into `{"tag":"Widget","name":…,
  "props":…}`, and `Tab`, being a single-constructor type, has no `tag`).
  `widget n p = Widget n (toJson p)`; `vflow`/`hflow`/`grid`/`tabbed` are the
  constructors, `tabbed` taking `(label, node)` pairs.
- **`Doc`** is a small JSON tree (`DNull DBool DLong DNum DStr DArr DObj DRaw`)
  plus `Data(ext, columns, order, delivery, path)` for a relation.  `DocJson`
  is the third `JsonBuilder` beside `ArgonautJson` and `ErmineJson`: it forces
  the relation, reads the plan's header (`Typer.extTyper`, what `relation#`
  uses) and keeps the `Ext` for the writer, so **column descriptors are known
  before any scan**.  A header-less `EmptyRel` (`mkRelation# []`) is an encode
  error at its path unless a per-path `Header` hint is supplied;
  `Doc.headerOfType` turns a static `[a, b, c]` type into one (the only static
  hint supported: inside a widget's `props : Json` there is no static type
  left to read).
- **`Write.doc[G](doc, out, cfg, cache)(implicit Scanner[G], Guard[G])`** is
  ONE `G` action: text runs are appended as they come, each relation resolved
  in document order.  For `G = DB` that is one `Connection`, proved by a test
  that counts `Run[DB]`'s connections and compares the `Connection` each scan
  receives.  `Guard[G]` (instances for `DB` and `Id`) is the one addition to
  the design: `Scanner[G]` offers only a `Monad`, which cannot see the
  exception a scan throws, and a failure has to name the relation.
- **Row encoder**: `Rows.row` appends a `Record` as a JSON array in column
  order straight to a `StringBuilder`, per `PrimExpr` case, no `Json` nodes.
  The mapping is `Encode`'s on the value the runtime would lift the `PrimExpr`
  to, with one deliberate difference: a `DateExpr` is a date by its CASE even
  when the value inside is a `java.sql.Timestamp` (`PrimExpr.mapDate` makes
  those), because the column descriptor says `Date`.  Strings are escaped per
  RFC 8259 plus U+2028/U+2029 and any unpaired surrogate, so the text is
  always valid UTF-8 and safe to inline in a `<script>`-free page.
- **Delivery**: explicit `Inline`/`Deferred` wins, a bare relation takes
  `cfg.default`, and a bare relation resolved inline whose scan yields a
  (threshold+1)-th record STOPS there — the `Process` returns `Stop`, which
  ends the scan (the SQL driver closes its result set) and the relation goes
  out deferred instead.  `MemoryPlanCache` mints a 128-bit base64url token
  with a TTL and `Write.relation(token, …)` writes exactly the inline object
  the relation would have had.
- **Buffered failure semantics**: a failure anywhere throws `WriteFailure`
  (path, message, the relations already completed) when the action RUNS;
  `out` then holds the document up to but not including the failed relation's
  object — never a partial relation.  A runner that wants HTTP error semantics
  writes into a buffer and sends it only when the action returns.  A row the
  encoder REFUSES (a non-finite Double, a missing column) leaves its scan by
  `Stop`, the same exit the threshold uses, and the error is raised after the
  scan has returned: throwing from inside the machine would unwind through
  `EffectfulProcedure.withDriver` (`relational/package.scala:121-128`, which
  has no `finally`) and skip `rs.close`/`stmt.close` and `cleanTempTables` —
  a leaked cursor per failed report under a pooled `Run[DB]`.  The hole that
  remains is a scan that throws on its own; the cure is
  `try k(d) finally teardown()` in that shared code, carried as a ticket for
  J3c.
- **Two latent bugs this stage had to find** (both outside the JSON code).
  First, `record/RecordMap.scala`'s `SharingKeySet.get` inferred `Nothing` for
  `indexValueSeq`'s type parameter and compiled to `checkcast
  scala/runtime/Nothing$`, so EVERY lookup by key on a record from a SQL scan
  threw `ClassCastException` on Scala 3 (fixed here, one line, with a pinning
  property).  The JSON writer was NOT the first caller — `Op.eval`
  (`Op.scala:22`) via `SqlScanner.scala:581` already indexed scanned records by
  name, with no Scala 3 coverage — and since `get` also backs `apply`,
  `contains` and `Map.equals`, which on 2.13 CATCHES the exception and answers
  `false`, two equal scanned records compared unequal and
  `relational.uniqSorted`/`uniq` and any `Set[Record]` silently stopped
  deduplicating.  The fix restores relational-engine behaviour, so its real
  gate is the landing's full `core/test`, not the JSON suites; the 2.11
  `RecordMap` is a different file and probably does not need the line.
  Second, `SqlExecution.nextRecord` calls the emitter's `getUuid` before it
  checks `wasNull`, so a NULL in a `GUID` column throws
  `NullPointerException` (NOT fixed here — it is the DB layer's, and stage J3c
  should have it as a ticket).
- **Numbers**: 100,000 rows x 10 columns write in ~1.9 s through the test
  scanner (of which building the records is the larger half) into ~15 MB of
  text, holding ~28 MB of heap: the writer holds the text, not the records.
## 3.7b Stage 2a as built (2026-09-16, branch `json-decode`)

**The params decoder** (`core/json/Decode.scala`), the inverse of `Encode` on
the serializable fragment and the executable reading of what `Schema` exports.

- **Two phases.** `Decode.compile(ty)` walks the TYPE once -- the exporter's
  walk, the same alias expansion to a fixed point, the same `unfurl`, the same
  `$defs`-keyed handling of a `data` instantiation (`Schema.defName`) so a
  recursive type terminates -- and returns a `Decoder` that needs no
  `SessionEnv` to run. `entry(ty)` is that walk alone (the expanded type, or
  why it has no decoding); `decode(ty, j)` is compile-then-run. The RUN phase
  keeps an explicit stack, so neither a 100,000-element list nor a document
  nested past the parser's own depth grows the JVM stack, and JSON paths are
  parent-linked and rendered only for an error (eager path strings cost the
  square of the depth).
- **Refused at compile time**, each naming the offending part of the type:
  a type variable (including a PHANTOM data parameter -- the exporter accepts
  one, a decoded value has no type to carry it), a `forall`, an open row, a
  function, `IO`, `FFI`, a `Field`/`Prim`/`PrimT` witness, a foreign type, a
  relation and the `Inline`/`Deferred` wrappers (rows never come from the
  request), an existential field, a nested `Maybe (Maybe a)`, a `Nullable` of
  a type with no `PrimT` witness for its `Null`, an operator constructor, and
  a record-style field named `tag` in a type with several constructors.
- **Refused at run time** with the JSON path into the INPUT (`$`, `.key`,
  `[i]`, a positional constructor's arguments as `.args[i]`): a missing key is
  reported at the object, an unknown key at the key, a bad tag at `.tag`.
- **Values are what evaluation produces**, which the round-trip property
  pins: `Data` through the registry's constructor `Global`; `Bool` as
  `Data(True/False)`; `Nullable`'s `Null` carrying `primTypes(t).withNull`,
  the witness `Null Int` and a database read both carry; `Date` a
  `java.util.Date` at UTC midnight, `Timestamp` a `java.sql.Timestamp`;
  `List#`, `Maybe#` and `Pair#` storing `extract`ed elements as `::#`/`Just#`/
  `toPair#` do, but `Vector` storing what `Session.whnfForeign` gives (its
  builders are foreign, and an empty `Arr` -- the unit value -- arrives there
  as Scala's `()`).
- **Decisions in code.** An integer may be written `1.0` or `1e2` (JSON
  Schema's `integer`) but not `1.5`; `Long` is a decimal string only; a
  `Timestamp` is any ISO-8601 date-time WITH an offset (the encoder's
  `...SSS'Z'` included; zod's `.datetime()` is stricter, `Z` only) and keeps
  sub-millisecond nanos; a `Date` is `ISO_LOCAL_DATE`, strict, so `2026-02-30`
  is refused; a `GUID` must be the canonical 8-4-4-4-12 form. `Prim`'s
  argument is BY NAME and turns a throw into a `Bottom`, so every conversion
  is forced into a `val` first: a decode either fails with an `Error` or
  yields a value with no bottom in it (the agreement property checks that).
  `java.sql.Timestamp.from` MULTIPLIES AND WRAPS out-of-range instants (JDK
  21: year 999999999 comes back as year 169104628), so the instant is
  validated with `toEpochMilli` first.
- **Four bugs the new properties found in Stage 1 code**, fixed here:
  (1) the exporter made a record-style field of type `Nullable a` or `Maybe# a`
  an OPTIONAL key, but the encoder only omits a `Maybe` field and writes
  `null` for those two -- `Schema.constructor` now uses the encoder's test
  (`Builtin.Maybe` alone); (2) `Char` exported `maxLength: 1` without
  `minLength: 1`, so `""` validated and zod accepted it while the decoder
  refused; (3) `Validate`'s `uuid` format took `UUID.fromString`, which also
  accepts `"1-1-1-1-1"`, where zod's `.uuid()` and the decoder want the
  canonical form. `Validate` learned `minLength`, `Zod` renders `.min(n)`.
  (4) a record-style field NAMED `tag` in a type with several constructors
  overwrote the discriminator: the exporter emitted an arm whose `tag` had lost
  its `const` and whose `required` read `["tag","tag"]`, and the encoder wrote
  two `"tag"` keys, of which argonaut keeps the last. The decoder refused it
  from the start; `Schema.constructor` and `Encode.userData` now refuse it too
  -- the exporter and the decoder at the declaration (`T.C[i]`), the encoder at
  the value's own `$.tag` -- all three saying "collides with the
  discriminator", so no path produces the broken document. A DECLARATION-level
  refusal (the parser/`Session`, beside Stage 1a's other selector refusals)
  would be better still and is a separate ticket.
- **Known gaps, pinned as such** (the validator accepts what the decoder
  refuses, because the schema cannot say it): `Int` has no bounds in the
  schema, `Long` only a digit pattern, `Double`/`Float` no finite range, and
  Java's `$` in a `pattern` also matches before a final newline where
  ECMAScript's does not. Adding `minimum`/`maximum` to the `Int` schema would
  close the first and move every committed fixture, so it is left for after
  the Stage 3 landings.
- **The non-injective spots kept on purpose**: `Maybe Json` (and
  `Maybe# Json`) -- `Just JNull` and `Nothing` both encode as `null` and the
  decoder reads `null` as `Nothing` -- and, inherited from Stage 0, a
  whole-valued `JNum` (`JNum 2.0` renders as `2.0` and reads back as `JInt 2`,
  which is `parseJson#`'s own rule, so `TestSchema`'s `Json` generator always
  gives a `num` a fractional part). Nested `Maybe (Maybe a)` is refused for
  exactly this reason; a raw-JSON parameter was judged worth the loss. A
  record-style `Maybe` FIELD is injective even so (absent / `null` / value).
- **Tests**: `scalacheck-binding/TestDecode.scala`, ten properties over
  TestSchema's generated declarations and values -- round trip (200 cases and
  a shrinking one), agreement with `Validate` over 1,950 documents (the
  encoding plus twelve single mutations of it per case), the error-path
  distribution, `entry` on poisoned types, 100,000 records, and a 100,000-level
  document (far past what argonaut's own parser reads). The generator vocabulary in
  `TestSchema` grew the rows it lacked (Short, Byte, Float, Char, Date,
  Timestamp, GUID, Nullable, Vector, `List#`, `Maybe#`, `Pair#`, `Json`),
  which is what found the Stage 1 bugs above. The round trip compares JVM
  classes as well as structure, and excuses only the payload ambiguity just
  described -- the null WRAPPER is still compared, so answering a `Maybe`'s
  `Nothing` where a native `Maybe#`'s belongs fails (checked by mutation).
  Two test-hygiene fixes came with the review: `(e2)` reads back at three
  quarters of its measured parser depth instead of at the boundary (the
  measurement swings 4,100-21,000 between runs with the JIT state, and sitting
  on it overflowed one gate run in fifteen), and `TestJson` no longer declares
  three different `data Shape`s and two `data Series` in one process -- the
  `DataConDecl` registry is process-global and last-writer-wins, so
  concurrently-running properties could encode each other's values with the
  wrong field list (seen once in twenty runs).
## 3.7c Stage 3 writer as built (2026-09-16, branch `json-doc`, stage J3b)

The document types, the document writer, the row encoder and the deferred-token
cache: `modules/Layout/Doc.e`, `core/json/Doc.scala`, `core/json/Write.scala`,
`core/json/PlanCache.scala`, `scalacheck-binding/.../TestDoc.scala`.

- **`Layout.Doc.Node`**: `Widget { name, props }`, `VFlow { children }`,
  `HFlow { children }`, `Grid { cells }`, `Tabbed { tabs }`, with
  `Tab { label, content }` — the names of §3.2 with no collision to rename
  (the generic walker of §3.7a turns them into `{"tag":"Widget","name":…,
  "props":…}`, and `Tab`, being a single-constructor type, has no `tag`).
  `widget n p = Widget n (toJson p)`; `vflow`/`hflow`/`grid`/`tabbed` are the
  constructors, `tabbed` taking `(label, node)` pairs.
- **`Doc`** is a small JSON tree (`DNull DBool DLong DNum DStr DArr DObj DRaw`)
  plus `Data(ext, columns, order, delivery, path)` for a relation.  `DocJson`
  is the third `JsonBuilder` beside `ArgonautJson` and `ErmineJson`: it forces
  the relation, reads the plan's header (`Typer.extTyper`, what `relation#`
  uses) and keeps the `Ext` for the writer, so **column descriptors are known
  before any scan**.  A header-less `EmptyRel` (`mkRelation# []`) is an encode
  error at its path unless a per-path `Header` hint is supplied;
  `Doc.headerOfType` turns a static `[a, b, c]` type into one (the only static
  hint supported: inside a widget's `props : Json` there is no static type
  left to read).
- **`Write.doc[G](doc, out, cfg, cache)(implicit Scanner[G], Guard[G])`** is
  ONE `G` action: text runs are appended as they come, each relation resolved
  in document order.  For `G = DB` that is one `Connection`, proved by a test
  that counts `Run[DB]`'s connections and compares the `Connection` each scan
  receives.  `Guard[G]` (instances for `DB` and `Id`) is the one addition to
  the design: `Scanner[G]` offers only a `Monad`, which cannot see the
  exception a scan throws, and a failure has to name the relation.
- **Row encoder**: `Rows.row` appends a `Record` as a JSON array in column
  order straight to a `StringBuilder`, per `PrimExpr` case, no `Json` nodes.
  The mapping is `Encode`'s on the value the runtime would lift the `PrimExpr`
  to, with one deliberate difference: a `DateExpr` is a date by its CASE even
  when the value inside is a `java.sql.Timestamp` (`PrimExpr.mapDate` makes
  those), because the column descriptor says `Date`.  Strings are escaped per
  RFC 8259 plus U+2028/U+2029 and any unpaired surrogate, so the text is
  always valid UTF-8 and safe to inline in a `<script>`-free page.
- **Delivery**: explicit `Inline`/`Deferred` wins, a bare relation takes
  `cfg.default`, and a bare relation resolved inline whose scan yields a
  (threshold+1)-th record STOPS there — the `Process` returns `Stop`, which
  ends the scan (the SQL driver closes its result set) and the relation goes
  out deferred instead.  `MemoryPlanCache` mints a 128-bit base64url token
  with a TTL and `Write.relation(token, …)` writes exactly the inline object
  the relation would have had.
- **Buffered failure semantics**: a failure anywhere throws `WriteFailure`
  (path, message, the relations already completed) when the action RUNS;
  `out` then holds the document up to but not including the failed relation's
  object — never a partial relation.  A runner that wants HTTP error semantics
  writes into a buffer and sends it only when the action returns.  A row the
  encoder REFUSES (a non-finite Double, a missing column) leaves its scan by
  `Stop`, the same exit the threshold uses, and the error is raised after the
  scan has returned: throwing from inside the machine would unwind through
  `EffectfulProcedure.withDriver` (`relational/package.scala:121-128`, which
  has no `finally`) and skip `rs.close`/`stmt.close` and `cleanTempTables` —
  a leaked cursor per failed report under a pooled `Run[DB]`.  The hole that
  remains is a scan that throws on its own; the cure is
  `try k(d) finally teardown()` in that shared code, carried as a ticket for
  J3c.
- **Two latent bugs this stage had to find** (both outside the JSON code).
  First, `record/RecordMap.scala`'s `SharingKeySet.get` inferred `Nothing` for
  `indexValueSeq`'s type parameter and compiled to `checkcast
  scala/runtime/Nothing$`, so EVERY lookup by key on a record from a SQL scan
  threw `ClassCastException` on Scala 3 (fixed here, one line, with a pinning
  property).  The JSON writer was NOT the first caller — `Op.eval`
  (`Op.scala:22`) via `SqlScanner.scala:581` already indexed scanned records by
  name, with no Scala 3 coverage — and since `get` also backs `apply`,
  `contains` and `Map.equals`, which on 2.13 CATCHES the exception and answers
  `false`, two equal scanned records compared unequal and
  `relational.uniqSorted`/`uniq` and any `Set[Record]` silently stopped
  deduplicating.  The fix restores relational-engine behaviour, so its real
  gate is the landing's full `core/test`, not the JSON suites; the 2.11
  `RecordMap` is a different file and probably does not need the line.
  Second, `SqlExecution.nextRecord` calls the emitter's `getUuid` before it
  checks `wasNull`, so a NULL in a `GUID` column throws
  `NullPointerException` (NOT fixed here — it is the DB layer's, and stage J3c
  should have it as a ticket).
- **Numbers**: 100,000 rows x 10 columns write in ~1.9 s through the test
  scanner (of which building the records is the larger half) into ~15 MB of
  text, holding ~28 MB of heap: the writer holds the text, not the records.

## 3.7d Stage 3 runner as built (2026-09-16, branch `json-runner`, stage J3c)

Files: `core/.../ermine/json/Runner.scala` (the runner, `RunError`, `Request`,
`RunnerConfig`), `Server.scala` (the JDK `com.sun.net.httpserver` face),
`ServeMain.scala` + `bin/ermine-serve` (the CLI),
`core/src/test/resources/doc/Sales.e` (the example report),
`scalacheck-binding/.../TestRunner.scala` (16 properties).

### The pipeline

```
request JSON -> Request.parse -> Decode (compiled once per report)
             -> report : Params -> Node -> Doc.fromRuntime
             -> Write.doc inside ONE Run[DB].run -> one JSON object
```

Boot is one `SessionEnv` for the process: `Lib.preamble`, then `Layout.Doc`
and the configured `--preload` modules.  Module sources come from the
`--root` directories, in order, before the classpath.  Per REPORT, once and
cached by module name: `Session.eval(<report name>)` for `(Type, Runtime)`,
`Decode.reportSignature` to split `Params -> Result`, a check that the result
is `Layout.Doc.Node` with aliases expanded, and `Decode.compile` for the
parameter decoder.  A REFUSAL is not cached, so a module the operator is
about to add or a signature they are about to correct is retried.

### The wire, as implemented

```
POST /report/<Module.Name>   body {"params": .., "data": {..}}   -> the document
GET  /data/<token>                                               -> the inline object
GET  /health                 -> {"status":"ok","version":1,"modules":[..]}
```

Every response is `application/json; charset=utf-8` with a `Content-Length`;
`Buffered` means the document is written into a `StringBuilder` and sent only
when the write returned, so no partial document ever reaches a client.  A
failure is `{"error":{"path":..,"message":..}}` with `path` null when there is
none:

| Status | When | `path` |
|---|---|---|
| 400 | body not JSON / not an object / an unknown key at either level; `strategy: "streamed"`; a parameter the type refuses; a report whose type is not `Params -> Node` | `$`, `$.data.<key>`, `$.params...` |
| 404 | no such module, no binding of that name in it, no such route, unknown or expired token | null |
| 405 | the route used with another method (with `Allow`) | null |
| 413 | body over `--max-body` | null |
| 500 | the report threw, produced an unencodable document, or a scan failed | the DOCUMENT path, when there is one |

### Decisions taken in code

1. **A report that throws and a report that builds something unwritable are
   the same 500.**  An Ermine `error` inside the value reaches `Encode` as a
   `Bottom` and comes back as an `Encode.Error`, not as an exception, so the
   two cannot be told apart — and neither is the client's fault.  (J3b's
   sketch suggested a 400 for an encode error; a 400 would have made "a report
   that throws" a 400 too.)  The error's `path` is then the path in the
   RESPONSE document, which is why the body carries `path` separately from
   the status rather than pretending it is a request path.
2. **Unknown keys are refused** at the top level and inside `data`, so a
   client's `"treshold"` is an error instead of silence.
3. **A missing `params` key is `null`**, which is what a report over `Maybe`,
   `Json` or `()` wants; anything else refuses it at `$.params`.
4. **Module names are validated** (dot-separated identifiers) before they
   reach `SourceFile.filesystem`, which turns a name into a path.
5. **One evaluation at a time; scans and writes concurrent.**  See below.
6. **No `Doc.fromRuntime` hints.**  The runner knows the report's RESULT type
   (`Node`), never the type of a relation buried in a widget's props, so it
   has nothing to build a header hint from: a header-less `mkRelation# []` is
   a 500 that names `mkRelationWithHeader#` (pinned).
7. `MethodNotAllowed` (405) and `TooLarge` (413) live in `RunError` beside the
   runner's own three, so every body a client can see has one shape.
8. **A bad report SIGNATURE is a 400, a bad report VALUE is a 500.**  Neither
   is the client's fault, so the split is not about blame: the brief fixes the
   signature case at 400, and it is the one where retrying is pointless and
   the message says so, whereas a value that will not encode may depend on the
   very parameters that just type-checked.

### Concurrency

Evaluation is serialised behind one monitor: `Session.loadModules`,
`Session.eval`, the parameter decode, the application of the report and
`Doc.fromRuntime` (which forces the value).  Module loading mutates the
`SessionEnv`'s maps field by field and the process-global `DataConDecl`
registry, `Supply` is documented single-threaded, and `Runtime.Thunk.state` is
a non-volatile `var` whose whitehole latch guards against a cycle, not against
a data race.  Everything after that — the scan, the row encoding, the plan
cache — is concurrent: nothing in `Doc`/`Write`/`Rows` reads the session, each
request has its own `Appendable`, `MemoryPlanCache` is synchronized, and
`Run[DB]` gives each thread its own connection.  So N requests overlap on the
database and queue on the interpreter, which is where the cheap part is.  The
HTTP server uses a fixed pool (default 16) because the JDK server's default
executor would run every exchange on the dispatcher thread.

The monitor is PROCESS-WIDE (`Runner.evalLock` on the companion object), not
per instance: `DataConDecl`'s two registries are static and last-writer-wins
per `Global`, so two runners in one JVM -- two tenants, or a test fixture --
must exclude each other as well.  `GET /health` is the one path that does not
take it, reading a volatile snapshot of the loaded modules instead, so a
liveness probe cannot queue behind the slow report it is probing.

Three things J3d should know before it writes a browser client: there are **no
CORS headers**, so the client must be served from the same origin or go through
a proxy; a **413 is sent without draining the request body**, so a client still
uploading sees the connection close (curl reports the 413 and then exits 56);
and `Run[DB]` is **not a pool** -- each request opens and closes a JDBC
connection, and `--threads` bounds how many exist at once.

### Verified

`TestRunner`, 16 properties over report modules GENERATED as Ermine source
(random parameter type and value from `TestSchema.shape`, one to three literal
relations in each of the six delivery forms, a random `data` configuration):
end to end in process, the error paths, the same requests over HTTP giving
byte-identical bodies, concurrent requests agreeing with serial ones, one
connection per request, the example report, and the two DB-layer tickets J3b
handed on (a NULL GUID column, and a scan that throws being torn down) — both
now fixed, in `SqlEmitter.EmitUuid_Strings.getUuid` and
`relational/package.scala`'s `EffectfulProcedure.withDriver`.

## 3.7e Stage 3 client as built (2026-09-16, branch `json-client`, stage J3d)

The widget prop types and the TypeScript client. Files: the modules under
`core/src/main/resources/modules/Layout/Widgets/` plus the `Layout/Widgets.e`
umbrella, `client/` (the npm package), `core/src/test/resources/modules/Doc/
SalesReport.e`, `scalacheck-binding/src/main/scala/TestWidgets.scala`.

**One module per widget.** Ermine field selectors are MODULE-global: two `data`
types in one module may not both declare `columns`, and a field name may not shadow
a global in scope. So each widget's props live in their own module
(`Layout.Widgets.Table`, `.Drilldown`, `.Scorecard`, with `.Format` holding the
shared `CellFormat`), and `Layout/Widgets.e` re-exports them. J3e's chart widgets
follow the same pattern. The smart constructor for the regular table is `tabular`,
not `table`: `table` is an Ermine keyword. The registry NAME on the wire is still
`"table"`.

**`CellFormat` replaces the foreign `Format` on this path** (§3.1a). It is a pure
Ermine mirror of the object form of `HTMLWriter.jsFormat`, all fifteen cases. The
generic walker spells the discriminator `"tag"` with the CONSTRUCTOR NAME, so the
legacy `"type"` is exactly the constructor with a lower-cased first letter. Three
forced departures: `whenTrue`/`whenFalse` for Conditional's `then`/`else` (Ermine
keywords), `aliases` as a list of pairs rather than an object (the walker has no map
encoding), and `Currency` carries `places` (the legacy server reads it from
`CurrencyObj.settings`, a table the client does not have). A converter FROM the
foreign `Layout.Format` is out of scope: it is a Scala ADT with no Ermine
eliminator, so it needs a Scala-side fold.

**Relation fields.** `TableProps.rows` and `DrilldownTableProps.ddRows` are bare
`[..r]` (the request's `data.default` decides), `ScorecardProps.cards` is
`Inline r`. The row parameter is left FREE, so each widget has ONE schema whatever
relation it is used with (J3a's generic arm).

**The client.** `client/src/generated/` is zod written by
`bin/ermine-schema --zod`, one module per exported type plus an index carrying
`WIDGET_PROP_SCHEMAS` (registry name -> schema); `scripts/check-generated.sh`
regenerates into a temp dir and diffs, which is §3.5's equality check.
`src/dispatcher.ts` walks the `Node`, builds plain DOM for the layout constructors,
and for a `Widget` looks the name up, validates props with the generated zod,
deep-resolves every relation in them (so a widget added later resolves for free),
and calls the renderer; nothing a widget does throws past it — an unknown name,
invalid props, an unresolvable token and a renderer exception all render an error
box. `src/legacy.ts` rebuilds, on the client, the argument object
`HTMLWriter.tableRegular`/`drilldownTable` send to `htmlwriter.runTabular` today,
including the `{formatted, raw, format}` cells; `src/format.ts` is the port of
`formatDisplay` that computes `formatted`, which server-side is Scala
(`htmlEval` + `Format.basicEval`) and is not on the wire. `src/widgets/scorecard.ts`
is the new widget, plain DOM, no legacy code.

**HTML escaping moved with the formatting** (§3.4's trust boundary is unchanged, its
enforcement point is not). Today `HTMLWriter.htmlEval` decides, in Scala, what is escaped
and what is raw, and ships the answer. On this path `client/src/format.ts` decides:
`Default` and `Truncate` run the cell through `string_unhtml` (a detached `<span>`'s
`innerHTML`/`textContent` — byte for byte the legacy's own sink, `utils.js:41-48`),
`Verbatim` is the deliberate raw passthrough the legacy also has, and `Color`/`signSpan`
mint the same spans `htmlEval` substitutes for its markers. The source of truth (DB
content) and the escape hatch are the same; only the code that enforces it changed sides.

**`formatted` is not byte-identical to the server's**, and is not meant to be: a Date or
Timestamp cell arrives as its wire string rather than through `HTMLRunner.tabularDateFmt`'s
`MMM-dd-yyyy`, and `htmlEval`'s fallback branch replaces every space with `&nbsp;` while
the port (following the JS `formatDisplay`) does not. The cell's `format` key IS.

**Structural relation resolution has a boundary worth knowing.** `resolveRelations`
deep-walks the validated props and swaps out anything `isWireRelation` accepts, so a props
record that reproduced a whole relation arm would be swallowed. The test therefore requires
the WHOLE arm — `kind`, `columns` of real column descriptors, and `rows`+`rowCount` or
`token`+`expires` — not just `kind` and `columns`; `TableColumn` already declares a field
named `kind`, so the weaker test would have left a one-field-name margin for J3e's chart
descriptors. Pinned by `(p-relation-guard)`.

**What the client cannot reproduce**: column GROUPINGS (the `Legend`'s nested header
rows) — the skeleton emits one header row and `args.legend` is `null`, which nothing
in the local-relation path of `runTabular` reads.

**One value the adapter translates, not passes**: `runTabular`'s `sorts` is
`[column index, "asc" | "desc"]`, a STRING — DataTables builds the NAME of the comparator
it calls out of that second element (`oSort[sDataType + "-" + aaSort[k][1]]`), and the
server sends the same strings (`PruJS.scala:59` prints a `SortOrder` as
`x.toString.toLowerCase`). The Ermine type keeps the boolean `ColumnSort.descending`; the
translation belongs beside `alignmentOf`/`columnTypeOf` in `legacy.ts`.

## 3.7e (continued) Stage 3 charts as built (2026-09-16, branch `json-charts`, stage J3e)

The remaining live renderers of §4.1. New modules
`core/src/main/resources/modules/Layout/Widgets/{Chart,AxisChart,PieChart,StyleBox,DrilldownBar}.e`
(re-exported by `Layout/Widgets.e`), `client/src/charts.ts`, `client/test/charts.test.ts`,
four more generated zod modules, and the chart generators in `TestWidgets`.
`Doc/SalesReport.e` now also carries an `axisChart` and a `pieChart` over the same
relation, so the end-to-end test covers a chart through SQLite.

**The op-list handles become column names.** `selSeries`, `selCategory`, `selValue`,
`selExtra` and the meta's `colors` (§4.2) exist only to build the POST payload
`withTimeSeriesData` sends when a series' `data` is not an array
(`ermine-htmlwriter.js:221-248`). On this path the rows travel with the document, so the
prop types carry `seriesColumns`/`categoryColumns`/`valueColumn`/`extraColumns` instead and
`client/src/charts.ts` builds the legacy positional rows
`[[value…],[category…],[series…],cssColor|null, extra…]` (`RelationRunner.runRelation`
~70-80) from the inline relation. The same for the pie
(`[label, |value|, cssColor|null, child?, parent?]`) and for the style box, whose
`cellCounts` — JSON inside a JSON STRING, `HTMLWriter.scala:1263` /
`js/ermine/stylebox.js:87` — the adapter computes by doing client-side the
`AggregateByGroupE` sum the server does relationally.

**One callback could not be avoided: `styleBoxData`.** `withStyleBoxData`
(`ermine-htmlwriter.js:297-319`) has no `Array.isArray` local branch, unlike
`withTimeSeriesData` and `withPiechartData`. The 3x3 grid renders entirely from
`cellCounts`, so the widget works with no request, but the cell-click popup would need a
server: `relation` and `legend` go out as `null` and that POST fails into the legacy's own
error callback. `tableData` is unreachable from writer-generated pages and `treeMapData`
has no client caller, so this is the only one.

**`treeMap` is registered as unsupported**, i.e. deliberately NOT in `defaultRegistry()`:
`runTreeMap` is undefined in the bundle and `HTMLWriter.treeMap`'s Local branch is
`sys.error("todo")`, so the dispatcher's error box naming the widget is the honest answer.
`UNSUPPORTED_WIDGETS` states it in code.

**Chart formats are §4.4's lossy tuple, and the loss is now enumerated.**
`charts.ts::TUPLE_LOSS` has one row per `CellFormat` case saying whether
`formatDisplay`'s styleMap has the name at all and what the pair cannot carry;
`tupleIsLossless(f)` says whether THIS value survives. `(t-tuple)` drives 600 random
formats through the real legacy function: where the tuple is lossless the two agree
value for value, and where it is not the legacy must answer exactly what `Default`
answers — so the documented loss is checked to BE the loss, not asserted. A chart
therefore cannot format as the table beside it does; that is today's behaviour.

**One value in a chart row is FORMATTED, not raw: the pie's slice label.**
`RelationRunner.runPieChartData` builds position 0 as
`lc.format.basicEval(labels) extractNullableString ""` (`RelationRunner.scala:240`) —
always a String — and nothing in the browser formats it again: `args.labelFmt` reaches
only `hcutil.pieLegendOptions` (`ermine-htmlwriter.js:2422`), whose merged options end
with the pie's own `labelFormatter` interpolating `this.name` verbatim, and `this.name` is
`r[0]` out of `processPieData`. So `pieRows` applies `pieLabelFormat` through `format.ts`
and stringifies (a null label becomes `""`), the way `styleBoxCells` formats its
aggregate. Everything else in a chart row travels raw, because Highcharts formats it from
the tuple. (Found by the J3e review; the first cut sent the raw cell, which silently
ignored the prop and would have rendered a `[y,m,d]` array for a Date label column.)

**Departures worth recording.** An axis chart has ONE relation for all its series — a
CHOICE, not a typing limit: a per-series `seriesRows : [..r]` with
`chartSeries : List (ChartSeries r)` is typeable and strictly more general (different row
SETS over the same columns, a deferred token each); what no spelling here can express is
series over relations of different SHAPES, which would need an existential row.
`structure` (`SeriesStructure.Complex`) is not modelled, so `isSeriesLevelDD` is false. The style
box's `xBins`/`yBins` are pairs of NUMBERS rather than the server's pre-formatted strings
— their only consumer, `formatBounds` (`stylebox.js:183`), calls `.toFixed(3)`, which
throws on a string today. `cellCounts` keys the positions as the literal `xPosition` /
`yPosition` the renderer reads, so any column name works (server-side the widget only works
when the columns happen to be called that).
## 3.7b' Stage 2b as built (2026-09-16, branch `json-spread`)

(Numbered `3.7b'` and kept beside §3.7b: J3b's document writer takes §3.7c.)

`Spread Json`: the §3.1b item 2 escape hatch for the long tail of options
nobody wants to model, built as ONE rule shared by the encoder, the exporter
and the params decoder.

- **The type**: `data Spread a = Spread a` in `modules/Json.e` (an ordinary
  Ermine declaration, like `Inline`/`Deferred`; no `Lib.scala` primitive).
  Only `Spread Json` is meaningful. **`Spread` of a record or of any other
  type is refused**, deliberately: a record's and a `data`'s keys are known
  from their own declarations, so spreading one would be a second spelling of
  fields the constructor can already name, with its own collision rule, its
  own schema merge and its own decode split to maintain; `Json` is the one
  case nothing else covers.
- **Encode**: a NAMED constructor field whose DECLARED type is headed by
  `Json.Spread` is merged -- the keys of the `JObj` it holds are written into
  the constructor's own object, after every declared field, in the object's
  order. Errors, each naming the path: a merged key that collides with a
  DECLARED field name (an omitted `Maybe` field's name included -- the
  decoder reads such a key back as the field) or with `tag`; a key the
  spread repeats; a payload that is not an object; a second `Spread` field in
  one constructor; a `Spread` in a positional constructor; a `Spread` value
  anywhere else. The SPREAD field's own name is the one declared name that is
  NOT reserved: it is no key of any document of the type, so it is merged and
  gathered like any other, and reserving it would have made the encoder refuse
  a document the schema declares legal and the decoder accepts (J2b review
  finding 1).
- **Schema**: the spread field is NOT a property and the arm carries
  `additionalProperties: true` instead of the usual `false`; everything else
  about the arm is unchanged, so in a multi-constructor type the arm that
  carries the spread is open while its siblings stay closed. `Zod` renders
  such an object `.passthrough()` -- zod's default STRIPS unknown keys, which
  would throw the merged keys away.
- **Decode**: a constructor with a spread field no longer refuses a key it
  does not declare; every such key is gathered, in document order, into the
  `JObj` that field holds. The inverse of the merge, so `decode(encode v)` is
  `v` for a collision-free value.
- **One rule, three places**: the three declaration-level refusals (a second
  `Spread`, a positional `Spread`, `Spread` of anything but `Json`) are
  refused by the exporter, by `Decode.entry` AND by `Encode.rejections` (the
  stdlib sweep), at the same field index -- the pattern the `tag`-field
  collision established in J2a. The spread test reads the type as DECLARED
  (no alias expansion, which the encoder has no session for), so an alias for
  `Spread Json` is not a spread field anywhere and all three refuse it.
- **Tests**: `TestSchema.(s)` (80 random probes: merge order, an open arm,
  `.passthrough()`, and a collision that names both) and `(s-pins)`;
  `TestDecode.(s)` (60 probes: the gather, in document order) and `(s-pins)`;
  four new poisons in `TestDecode.(d)`; and `TestSchema.shape` grew a
  `spreadData` row, so the encode/schema property, the round trip and the
  `Validate`-vs-`Decode` agreement all cover spread types (35 of the round
  trip's 200 cases carry one).

## 4. Appendix: the de facto widget API (catalogue)

Corrected per skeptic (§7): the writer also emits `registerSource`,
`signalDepends`, `eventDepends` (dead selector path) and wrapper functions in
`wrapHeader`; `runTabular` takes a single map with `id` inside.

### 4.1 Emission sites (`html/HTMLWriter.scala`)

| # | Widget | JS call | Props (kind: inline / handle(S)=HMAC / handle(U)=unsigned f0 / JSONtext) |
|---|---|---|---|
| 1 | table (`tableRegular` 1034-1060) | `htmlwriter.runTabular({...})` | `id` uid; `cols` [String]; `rowgroupCol` int\|null; `colAlignments`; `colType` `"number"\|"date"\|"other"`; `relation` **always inline** `[[{formatted,raw,format}…]…]`; `legend` handle(U); `sorts` `[[i,"asc"\|"desc"]]`; `paginate`,`scroll` from style hints; `isDD:false` |
| 2 | drilldownTable (1064-1096) | `runTabular` | as #1 minus `rowgroupCol`; `relation` always inline `[{indent, content:[cells]}]` (`jsTreeTabularRelArg` 561-571, Remote branch commented out); `isDD:true` |
| 3 | axisChart (1099-1121 → 807-810) | `htmlwriter.runTimeSeries(uid, {type:"AxisChart", series:[…], meta})` | see 4.2/4.3 |
| 4 | pieChart / drilldownPieChart (1146-1186) | `runPiechart` / `runPiechartDrilldown` (alias) | `title`, `seriesName`, `legendOptions{type,location}`, `renderHints{type,enableDataLabels}`, `dataFmt`/`labelFmt` (lossy tuple), `parentCol`/`childCol`; Remote: `colors`,`labelCol`,`dataCol` handle(U), `relation` handle(S); Local: `relation` JSONtext rows `[label, \|value\|, cssColor\|null, child?, parent?]` |
| 5 | treeMap (1123-1141) | **`runTreeMap` — undefined in JS**; Local = `sys.error("todo")` | `labelColPres`,`intensityColPres`,`sizeColPres` handle(U); `tbl` handle(S); `parentCol`,`childCol` |
| 6 | styleBox (1188-1271) | `htmlwriter.runStylebox(uid,{…})` | `xTitle`,`yTitle`,`aField`,`aTitle`; `aFormat` tuple; `legend` handle(U); `xPositionField`,`yPositionField`; `rowLabels`,`columnLabels`; `showNumber` `"showNumber"\|"hiddenNumber"`; `xBins`,`yBins` pre-formatted; `cellCounts` **JSON inside a JSON string** (1263; `js/ermine/stylebox.js:87`); `relation` handle(S) |
| 7 | drilldownBarChartPC (1279-1313) | `htmlwriter.runDrilldownBar` (alias of runTimeSeries) | `meta`; `series` always inline JSONtext rows; `parentCol`,`childCol` |
| D | selector/widget/onEvent/button (1448-1783) | `registerSource`, `signalDepends`, `eventDepends`; `runUpdates` 414-425 emits `jsLambda` | **dead** |

### 4.2 `series[i]` (732-793)

| prop | shape | read by JS? |
|---|---|---|
| `type` | `"ChartSeries"` | no |
| `selSeries`, `selCategory`, `selValue` | handle(U) op-lists (`serializeNel(…)(opW)`) | yes (posted back, `js/ermine-htmlwriter.js:231-233`) |
| `selCategoryCols` | `[[col, desc:Bool]]` | yes |
| `selExtra` / `fmtExtra` | `[handle(U)]` / `[tuple]` | yes |
| `fmtSeries` | tuple format | yes |
| `data` | handle(S) **or** JSONtext rows (`Array.isArray` sniff at `:223`) | yes |
| `variant` | `"Line"\|"Bar"\|"Step"\|"Scatter"\|"StackedBar"\|"StackedArea"\|"BoxAndWhiskers"\|"Bubble"` | yes |
| `structure` | `{trees, correlation?}` (Line/Bar Complex) | yes |
| `zlabel` | Bubble | yes |
| `selCategoryTips`,`fmtCategoryTips`,`selValueTips`,`fmtValueTips` | — | **no (0 hits in bundle)** |

### 4.3 `meta` (665-713)

`type:"AxisChartData"`; `domain`/`range` = `{type:"Axis", label, tooltipLabel, format: tuple, scalarType:{name,isNumeric}|{name:"compound",types}, showTicks, constraints: {scaled:true, lowerBound, upperBound, displayScale:"Linear"|"Logarithmic"} | {scaled:false, sort:[…], tickOverrides:[[p,p]]}}` with dates as `[y,m,d]` (253-258); `title`; `orientation` `"vertical"|"horizontal"`; `legendOptions`; `renderHints`; `colors` handle(U).

### 4.4 Format encodings

| Encoding | Produced | Consumed | Coverage |
|---|---|---|---|
| `jsLayoutFormat` tuple `[Tag, arg]` (208-227): Conditional/ColorFormat/Markdown/Verbatim/DateRange → `[Tag,null]` | chart axes/series, pie, stylebox | `js/ermine/utils.js:291-352 formatDisplay` (no Pr2/Conditional/ColorFormat/Markdown handlers) | lossy |
| `jsFormat` object `{type:…}` incl. `condition` (260-347) | every inline table cell | `js/ermine/tables.js:218` (`type==='markdown'` only) | complete |
| f0 `wformatRW` (`remote/RelationFormat.scala:1010-1030`) | handles | server | **no `Pr2` arm** — `serializeLegend` on `Layout.Format.pr2` (`modules/Layout/Format.e:124`) throws MatchError |
| Scala ADT (`core/writers/Legend.scala:616-948`, `Condition` 580-612) | source of truth | — | 15 cases |

### 4.5 Callback protocol (`html/HTMLRunner.scala:540-553`)

| method | request | handler | response |
|---|---|---|---|
| `page`/`pagebody`/`pagecontrols` | `FormValues` (selector env); app params out-of-band as `I` | `runReport` → `HTMLWriter.run` | HTML fragment + `<script>` with `renderPage(htmlwriter){…}` (355-399) |
| `selectorUpdate*` | `SelReq` | `runUpdates` | `[{divId: html}, "(function(htmlwriter){…})"]` → `eval` — **dead** |
| `tableData` | `{tbl: handle(S), legend: handle(U), start, stop(-1=all), sort: ["^col"\|"vcol"], restricts: [[col, intStr]]}` (303-315) | `runTableData` (`RelationRunner.scala:203-223`) | `[[[cell…]…], totalSize]`, cells pre-rendered HTML — unreachable from writer-generated pages (tables inline) |
| `relation` | positional 6-tuple `[tbl, [selValue,selCategory,selSeries], selCategoryCols, colors, [childCol,parentCol], extraOps]` (444-457) | `runRelation` (42-85) | rows `[[valueNel],[catNel],[seriesNel],"#RRGGBB"\|null,…]`, dates `[y,m,d]` |
| `pieChartData` | `PieChartQuery{tbl,labelColPres,dataColPres,childCol,colors,restricts}` | 487-494 | `[[label,\|value\|,cssColor\|null,…]]` |
| `treeMapData` | `TreeMapQuery` | 508-515 | no client caller |
| `styleBoxData` | `StyleBoxQuery{tbl,legend,xPositionField,yPositionField,xPosition,yPosition}` (client also sends ignored `rowBins/columnBins`) | 502-506 | rows via `jsonPrepTabular` |

All responses pass through `escapeHighChars` (568-571) a second time.

### 4.6 Writer surface: live vs dead (`core/writers/Writer.scala`)

| Group | Methods | HTMLWriter status |
|---|---|---|
| live data | table 180, drilldownTable(2) 184-186, axisChart 191, pieChart 199, drilldownPieChart 206, styleBox 202, drilldownBarChartPC 209 | live (tables inline-only) |
| live layout | empty 96, atom 99, style 124, pref/max sizes 128-134, pad 143, grid 152, spans/flows 221-230, centered/border 232-234, tabbed/sideTabbed/collapsible 240-244, columnTable 158, scanRelation 246-252 | pure HTML/CSS (`HTMLWriter.scala:912-1445`) |
| stubs | treeMap 194 (broken), tree 218 (`label("todo: tree")` 1321), drilldownPieChart2/BarChart2 213-216 (`sys.error("todo")`, `Missing.scala:30-36`), backgroundColor/foregroundColor/borderSize/borderColor/scrolling 137-148 (identity), atomFont/wrapAtom → atom, image → markdown | drop or reimplement in TS |
| dead | `SelectorMode`/`SelectorEvent` 26-58, `type Signal` 93, textBox/textArea/selector/onEvent/button/widget/foreignSelector/foreignSink 269-292 | delete |

Core examples using any selector/button: only `core/examples/Yahoo.e:181,227`.

## 5. Migration plan

| Stage | What | Deletes | Effort | Gate |
|---|---|---|---|---|
| 0 — **cheapest first step** | In core only: `Json.Num` lexeme fix; `DataConDecl` registry; `core/json/Encode.scala` (`Runtime => Json`, iterative, registry-guided) exposed as `:json <expr>` in the REPL and `toJson#` in a new `modules/Json.e`; ErmineFixture tests over stdlib enums/ADTs and a scratch user module | nothing | S (days) | `core/test` green; `replicate 1 100000` encodes; every `data` in `modules/` either encodes or is rejected with a location |
| 1 | `Schema.scala` + `bin/ermine-schema` + `ermine/schema` LSP request; zod codegen + CI equality check; encode/schema consistency property test; named constructor fields in the parser/`DataStatement`/registry (pulled forward from Stage 2, §3.1b) | — | M | exported schemas for `Ordering`, `Either`, `SortOrder`, `Direction`, `BorderOptions`, a user record/relation type; zod compiles |
| 2 | `Decode.scala`; builtin `Json a` constraint; `Spread Json` wrapper | — | M | round-trip property: `decode(schema, encode v) == v` for the serializable fragment |
| 3 | `modules/Layout/Doc.e` (Node/widget/layout constructors) and a new **document runner** (new sbt module or `ermine-writers` successor): params JSON → `Decode` → `report` → `Encode` → `Write.doc` → one JSON object per response, relations inline by default or `Deferred` per relation/request, `Buffered` strategy first (§3.4a); rows-as-arrays plus a client adapter that builds the `{formatted, raw, format}` cells the existing renderers expect (`html/HTMLWriter.scala:544-550`, `js/ermine/tables.js:218`) from `raw` + column `Format` via a port of `formatDisplay` (`js/ermine/utils.js:291-352`) to the object form, so client-side formatting lands here, not in Stage 4; TS dispatcher wrapping the existing 7 renderers with zod schemas generated from Ermine prop types; one new widget end-to-end as the proof (one `data` + one TS component) | nothing yet; HTMLWriter untouched, runs in parallel | M | a production report ported to `Doc` renders identically |
| 4 (optional) | Handle v2 hardening of §3.4a deferral tokens (signing, scope, spool) + `Streamed` strategy + NDJSON endpoint for very large deferred relations; `Limit`/sort/restrict pushdown | `RelationRunner` callback protocol, `escapeHighChars`, `jsonPrepTabular`, `tabularDateFmt` | L | 100k×20 table pages in O(page); no server HTML |
| 5 | Delete the dead and superseded surface: `Writer.scala:26-58,93,269-292`; `Missing.scala:24-28,38-42`; `Layout/Report.e:68,797-1079,1704-1757`; `Layout/Chart.e:214-223`; `Layout/Report/SelectorMode.e`; `Layout/Writer.e:11,15-16,23-24`; then the whole `Report f z`/`Writer` algebra once no production report uses it; in `ermine-writers`: HTMLWriter, PruJS, HTMLRunner, JsonWriter, JsonDebugWriter, JavaFX, `js/ermine-htmlwriter.js:2913-3397` (+ `eval` at 65/3218, hallo/rangy deps) | ~1,300 lines dead now, ~5,000 after 3-4 | S each | production corpus grep for `using`/selector/`button`/`Report f z` first |

Stage ordering rationale: 0-2 are core-only, need no `ermine-writers` build,
and are the headline deliverable (automatic serialization + schemas). Stage 3
is where the browser becomes the only renderer. Stage 4 is the performance
work and is independent of 0-3 except for the column-descriptor format.
`ermine-writers` is a legacy sbt 0.13 / Scala 2.11 build (`ermine-writers/build.sbt:1`);
do not modify it in place — the document runner is new code.

## 6. Open questions and risks

| # | Question / risk | Experiment that resolves it |
|---|---|---|
| 1 | Does the production corpus contain `class`/`instance` declarations or constraints over user class names? They are silently inert today (§2.2); a redesign must not start enforcing them by accident | `grep -rn '^class\|^instance\|=> ' <prod>/**/*.e`; load each hit in `bin/ermine` and `:type` the constrained bindings |
| 2 | Which types reach widget boundaries in production — records + Maybe/List only, or `data` with function/foreign fields (`Atomic (Format a) a`, `Presentation`, `Legend`)? | Run the Stage-0 encoder over every top-level of type `… -> Report f z` in the prod corpus; count rejections by cause |
| 3 | Is `-Dermine.typeCheck=true` set in the production launcher? Without it every binding is `forall a. a` (`Session.scala:470-471,351-355`; `tracker/04-repl-working.md:41-56`) and type-directed decode/schema are meaningless | Inspect the production JVM args / `BridgeErmineEvaluator` (not in repo, `html/HTMLRunner.scala:41`) |
| 4 | Record key collisions: do two modules declare the same `field` name? (`Runtime.scala:300-303` drops the module) | `grep -rn '^field ' <prod> \| awk` for duplicate names; schema exporter errors on collision |
| 5 | Long as decimal string (decided, §3.1) vs number-when-safe | Decided: string. Count `Long` columns/fields in prod widget props; reopen only if TS ergonomics bite |
| 6 | Constructor tag stability when a `data` moves modules (`Data.name` is the defining module, `Name.scala:29-39`) | Use unqualified tags (chosen) and make the schema `$id` module-qualified; add a `stable-name` annotation only if a real move breaks a client |
| 7 | Are widget prop types ever genuinely polymorphic (e.g. `Column t k v`)? JSON Schema has no generics | Grep prod widget signatures; if yes, export per instantiation via `replType` |
| 8 | Is tenant/user/report identity available at the callback endpoint so Handle v2 can scope tokens? | Inspect the production bridge; if absent, tokens must at least carry TTL + report id |
| 9 | Does the production DB (jTDS/MSSQL per `Backends.cloudDB`) honour `fetchSize` for cursor streaming; how common are Mem-plan relations? | `Scanner.dumpRel` over prod reports (it is `sys.error` in the base trait, `relational/Scanner.scala:29-31`; only `SqlScanner.scala:281` overrides it, so this needs a SQL-backed scanner); JDBC streaming probe against a 1e6-row table |
| 10 | Should any server-side formatting survive (Markdown, Currency)? `Markdown.scala:312` does not escape | Inventory `Format` usage in prod; port `formatDisplay` (`js/ermine/utils.js:291-352`) to the object form and diff outputs |
| 11 | Is the PDF writer live (`ermine-writers/writers/pdf`, `js/pdfwriter.js`)? It shares the JS bundle | Ask; if live, the dispatcher must serve it |
| 12 | Is treeMap used anywhere? It is broken in the current bundle | grep prod for `treeMap`; drop if unused |
| 13 | Is `Layout.Format.pr2` used with a remote widget? (`wformatRW` lacks Pr2) | grep prod; the new Format JSON schema must be generated from the ADT, not hand-maintained |
| 14 | Stack safety of nested (non-list) structures and of `Data.equals` in production (`-Xss` unset) | Add `-Xss` to the launcher or make `nf`/`equals` iterative; measure with the Java probe from the runtime lane |
| 15 | NaN/Infinity policy (reject vs `null` vs string) | Query prod DB columns for NaN; pick reject unless data exists |
| 16 | Interaction with the `cut` row-constraint default (`tracker/ROW-CONSTRAINT-STATE.md`): the exporter's open-row detection (VarT of kind rho + `Part`) must follow any representation change | Covered by the encode/schema consistency test in Stage 1 |
| 17 | Doc comments: Ermine keeps none (grep `docComment` empty), so JSON Schema `description` has no source | Decide on a `_doc` convention or lexer work; low priority |
| 18 | Which style hints (`no-table-pagination`, `hflow@cls`, …) do production reports use? They become typed props | grep the prod corpus for `style "` and tally the hint strings |
| 19 | Do production widget signatures use open rows `{..r}` at the boundary? The exporter rejects them | grep prod top-level signatures for `{..`/`[..` with a free row variable; if common, export per instantiation |
| 20 | Which widgets receive large literal (`SmallLit`) relations, i.e. is handle spooling needed at all? | instrument `mkRelation#` sizes over the prod corpus |
| 21 | Does any server round-trip depend on client-only table state (`currentTargets`, `tblExpansions`)? | grep `js/ermine/tables.js` POST bodies; if yes the data endpoint needs column-order or expansion params |
| 22 | Should the wire mapping policy live in one Scala file (chosen) or be overridable per type from Ermine (option E witnesses)? | team decision; prototype one `Codec a` override in Stage 2 to price it |
| 23 | How large is the largest relation a production report inlines? It sets the §3.4a size threshold and decides whether Stage 4 handles are ever needed | log per-relation row and byte counts in the v1 document writer over the prod corpus |

## 7. Verification ledger

Do not build on the following.

### Refuted

| Lane / id | Claim | What the skeptic found |
|---|---|---|
| current-api C1 | "Every emitted JS call is one of the 7 widget renderers … `jsLambda` is the only function literal" | Also emitted: `htmlwriter.registerSource` (`HTMLWriter.scala:1460-1466,1677,1779`), `signalDepends` (`:1567,1607,1681`), `eventDepends` (`:1734`); `wrapHeader` (`:361,365`) declares `renderPage`/`go`. `runTabular` takes one map with `id` inside (`:1048`), not `(uid, map)`. Weaker true version: all *widget-rendering* calls go through the 7 names and all prop values are JSON-shaped |
| current-api C9 | "params cross into Ermine via `whnfForeign`'s `Fun` case" | Wrong mechanism: `prepRun#` uses `Native.Function.function1` = `Prim((x: Any) => f(Prim(x)).extract[Any])` (`Lib.scala:1331`); `whnfForeign` is only used by `marshalForeign` for foreign method calls. The design conclusion (`I` is opaque to Writer/HTMLRunner) survives |
| schema C12 | "The LSP path (`readModuleTolerant` + `TolerantCheck.types`) is the cheapest way to get ordered constructors without a core change" | `NewPipeline.Read.module` from the strict `readModule` already used by `Dep.read` carries `DataStatement.constructors` with core `Type`s; `TolerantCheck.types` does not contain constructors at all (`TolerantCheck.scala:292-295`). This is why §3.1 attaches `DataConDecl` at load time instead |

### Unverified / unclear (marked as such above)

- Production facts not in the repo: the value of `I`, the bridge
  (`BridgeErmineEvaluator`), `typeCheck` flag, DB driver, PDF writer status,
  treeMap/pr2/class usage (§6 #1-3, 8-9, 11-13).
- Payload sizes (25 MB vs ~204 MB, gzip figures) come from a Python model in the
  scratchpad, not from real `HTMLWriter` output; the ~8x ratio is structurally
  plausible (per-cell `{formatted,raw,format}` with a 3-field descriptor) but
  "measured" overstates it.
- Effort figures are estimates; "hours" for the reflective encoder is not
  checkable from code.
- `-Xss`/stack numbers (~2,000 elements) are specific to `nf`/`equals`; a leaner
  walker goes deeper but still nowhere near 1e6.

### Confirmed with corrections (cite the corrected line)

| Item | Correction |
|---|---|
| `Json.Num` printing | `lsp/Rpc.scala:49-50`, not 46-47 |
| Native `::#` | `Lib.scala:331`, not 344; `Native.Map` stores **values** unextracted (`Lib.scala:310`), keys raw |
| Magic `Eq` instance | `Lib.scala:252-271`; the `recordT => Some(List())` case is `:260`, not 239 |
| `runRelation` | `Lib.scala:925-934`, not 938 |
| `jsonPrepTabular` | `html/HTMLUtils.scala:35-49` (file is 92 lines), and it does **not** rewrite `<COLOR_FORMAT>` — colour spans are inline-only |
| `hmacR/hmacW` | `html/HTMLHMAC.scala:35-64` (file is 120 lines) |
| `serializeFormat`/`serializeOp` | defined (`HTMLWriter.scala:470-471`) but have no callers; formats travel inside presentation/legend handles |
| `EField` | `modules/Field.e:22`, not 69 |
| `Sinks.scala` Sink trait | `f0/Sinks.scala:5-9`, only impl `toOutputStream` at 24 |
| Writer DMTL count | 17 `def *DMTL` adapters (`Writer.scala:252-393`), not 22 (22 counts call sites and comments) |
| f0 status | `tracker/02-scalaz-and-machines.md:46` ("not needed at all") is stale: live in `remote/BackendServer.scala:22-33`, `remote/RemoteScanner.scala:76-83`, `backends/BulkLoad.scala`, `backends/DumpToFileBackend.scala:19`, and the HMAC handles |
| List literals | `[…]` lowers to `empty_Bracket`/`cons_Bracket` hooks (`rename/Lower.scala:190-194`), overridden per module (Vector.e, Validation.e); values of type `List a` are Builtin cons cells, but a bracket literal is not necessarily a List |
| Empty relations | `EmptyRel` (no header) is not the only empty shape: `Rel(ExtRel(RelEmpty(header)))` also exists (`Lib.scala:342`) |
| `class Show a` lowering | a *declared* bodyless class name goes through `TyLower.scala:198-200` (ToBinder → VarT), an *undeclared* name through `:205-207` (placeholder); both are VarT, same effect |
| Bool in `Prim` | `Prim(java.lang.Boolean)` occurs only from foreign `Raw`/`Bool#`; ordinary values are `Data(True/False)` |
| `primInstance.build` | builds `Prim(d)` (PrimT), not unit (`Lib.scala:1164`) — irrelevant since never invoked |
| MemoR replay DDL | `relational/SqlScanner.scala:915-923` (`memoProc` is `:657`), not 912-921 |
| Markdown unescaped plain text | `Markdown.scala:309` (`case MPlain(c) => c // todo escaping`), not 312 |
| NaN dropped on insert | `backends/SQLBackend.scala:111`, not 548-549 (the file is 181 lines) |
| MySQL `fetchSize=Integer.MIN_VALUE` | `sql/SqlExecution.scala:41-46` is a comment; `:49` sets 10000 unconditionally, so MySQL streaming is not implemented |
| Writer method count | 82 `def`s in `Writer.scala`; 17 are final `*DMTL` adapters, ~33 abstract; the earlier "60-method" figure was informal |
| `Rel` and `nf` | `Runtime.scala:17` is the base-class default `def nf = this`; `:92` is the `Rel` class header, which does not override it |
