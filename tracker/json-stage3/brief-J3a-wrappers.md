# J3a: relations in the schema exporter (the §3.4a union, the wrappers, the generic arm)

Branch `json-wrappers`, worktree `~/research/ermine/ermine-scala-wt-json-wrappers`, off
`json-s3-base`. Budget 4 h. Read `brief-J-common.md` first.

## Why

Stage 1b's exporter gives a relation `[..r]` the inline columns+rows object with no `kind`
tag and no deferred arm, which diverges from design note §3.4a. The contract commit on
`json-s3-base` has declared `Inline r` / `Deferred r` (modules/Json.e), the Json nodes
`JInline`/`JDeferred` (Lib.json) and `json/Wire.scala`. This stage makes the static side
match the wire contract in `tracker/JSON-STAGE3-PLAN.md`, which the document writer (J3b,
running in parallel) produces and the TS client (J3d, later) consumes.

Read: design note §3.4a, §3.5, "Stage 1b as built"; `json/Schema.scala`, `json/Zod.scala`,
`json/Validate.scala`, `json/Wire.scala`; `TestSchema.scala`; the fixtures under
`core/src/test/resources/schema/`.

## Build

1. Relation arms, built from `Wire` names (no string literals for keys):
   - inline arm: object, required `kind` (const `"inline"`), `columns`, `rows`, `rowCount`
     (integer, minimum 0); `additionalProperties: false`.
   - deferred arm: object, required `kind` (const `"deferred"`), `columns`, `token`
     (string, minLength 1), `expires` (string, format date-time); `additionalProperties: false`.
   - `columns`: as today (`prefixItems`, min/maxItems = n, sorted by name) but each
     descriptor has three required properties: `name` const, `type` const from
     `Wire.columnTypes` (Nullable unwrapped, as today), `nullable` const `true`/`false`
     (true exactly when the row field's type is `Nullable t`).
   - `rows`: as today.
2. Which arm: a bare `Relation r` (i.e. `[..r]`) exports `oneOf [inline, deferred]`;
   `Json.Inline r` exports the inline arm only; `Json.Deferred r` the deferred arm only.
   The wrappers are recognised by constructor `Global` (module `Encode.jsonModule`) BEFORE
   the generic `data` path, so they never become `$defs` entries or `{tag,args}` objects.
   The stdlib `Json` type itself (a field of type `Json`) keeps its current export.
3. Row-polymorphic relations. Widget prop types (J3d) will be declared like
   `data TableProps r = TableProps { title : String, rows : Inline r }` and need ONE schema
   for all `r`. Today an open row is an export error. Make a relation (bare or wrapped)
   whose row is a row VARIABLE (or has an open tail) export a generic arm/union: `columns`
   is `array` of `{name: string, type: enum Wire.columnTypes, nullable: boolean}` (all
   required, no additional properties), `rows` is `array` of `array` of
   `string | number | boolean | null`; everything else as in (1). An open row anywhere
   OUTSIDE a relation (a bare record `{..r}`) stays an error. Decide and document how a
   parameterised type is exported with its row parameter free: e.g. `exportNamed` /
   `bin/ermine-schema` accepting `Test.TableProps` with a row-kinded parameter left
   abstract (and still refusing a free `*`-kinded parameter). Keep `$defs` naming
   deterministic (e.g. the free variable spelled `_` or by its declared name -- pick one
   and pin it).
4. Zod: `z.discriminatedUnion("kind", [...])` for the union; the arms as `.strict()`
   objects; the generic arm with `z.enum([...])` and `z.union([z.string(), z.number(),
   z.boolean(), z.null()])` cells. `tsc --strict --noEmit` must stay green over every
   fixture (install `zod@3` and `typescript` in your scratchpad; the Stage 1b recipe is
   in the design note).
5. Validator: extend `json/Validate.scala` only as far as the new schema keywords need
   (`enum` if not already there, `minimum`, `minLength`, `format: date-time` -- say
   what "format" checking it does).
6. Fixtures: regenerate `UserRelation.*`; add `UserInline.*`, `UserDeferred.*` and one
   row-polymorphic props type fixture (e.g. `UserTableProps.*`). The byte-equality fixture
   property must cover them.
7. Docs: update the Schema.scala header comment and the design note's "Stage 1b as built"
   paragraph on relations (a short "revised in J3a" note, not a rewrite); tick J3a in the plan.

## Properties (random declarations and values)

- (a) For random row types (the TestSchema field pool, extended with `Nullable` fields and
  the Date/Timestamp/Short/Byte/GUID column types -- check `field` accepts them) and random
  row VALUES, a hand-built inline document (columns from the row type, rows from the values
  encoded cell by cell with `Encode` on each record field value, rowCount = rows) validates
  against the export of `[..r]` AND of `Inline r`, and fails against `Deferred r`; a random
  deferred document validates against `[..r]` and `Deferred r`, fails against `Inline r`.
  Build the cells from evaluated Ermine records, not from Scala-side guesses, so the
  property ties the schema to the encoder's mapping.
- (b) Negative: a single random mutation (wrong kind, dropped required key, extra key,
  wrong `nullable`, wrong column type, a row of the wrong length, a cell of the wrong JSON
  type) is rejected by the validator. Report the mutation mix.
- (c) Row-polymorphic: for a random props `data` with one row parameter, the SAME schema
  accepts inline documents for several random instantiations of `r`.
- (d) The existing consistency property keeps passing, and a random `data` whose fields
  include `Inline r`/`Deferred r` at a concrete row exports without error and its zod
  compiles (extend the generator so relations appear inside props types; values of those
  types cannot go through `Encode.toArgonaut`, so validate a hand-assembled document).
- (e) Determinism: the export of a type is byte-identical across declaration orders and
  load orders (the Stage 1b property c), now including wrapper-bearing types.

## Gate

Tier 0 per the common brief; TestSchema + TestJson + TestNamedFields with your additions;
`tsc --strict --noEmit` over all fixtures; the zod accepts/rejects a sample of generated
documents at runtime (node script under your scratchpad, invoked from your report).
