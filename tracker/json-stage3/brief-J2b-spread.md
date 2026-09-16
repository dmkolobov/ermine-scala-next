# J2b: `Spread Json` (and, if time allows, the builtin `Json a` constraint)

Branch `json-spread`, worktree `~/research/ermine/ermine-scala-wt-json-spread`, off
`json-encode` AFTER J2a and J3a have landed. Budget 4 h. Read `brief-J-common.md` and
`report-J2a.md`, `report-J3a.md` first.

## Part 1: `Spread Json` (design note §3.1 table, §3.1b item 2)

- `modules/Json.e`: `data Spread a = Spread a`. Only `Spread Json` is meaningful; decide
  whether `Spread r` for a record type is also allowed (merging a closed record's keys)
  and justify; everything else is refused by the classifier/exporter with a location.
- Encode: a NAMED field of declared type `Spread Json` whose value is a `JObj` is merged into
  the parent object (after the declared fields, in the JObj's order); a key that collides
  with a declared field (or `tag`) is an encode error naming both; a non-object value is an
  error; at most one `Spread` field per constructor (refuse more at the declaration, with
  a location -- or define the merge order and pin it; pick one).
- Schema: the parent object drops `additionalProperties: false` (allows unknown additional
  properties) and the spread field is not a property; zod `.passthrough()` instead of
  `.strict()`.
- Decode: the declared fields are decoded as before; every remaining key goes into the
  spread `JObj` (in document order); a type with a spread field no longer refuses extra keys.
- Positional constructors: a `Spread` argument is refused (nothing to merge into).

Properties (random declarations and values): encode/schema consistency with spread fields
(extend `TestSchema.shape` with record-style data carrying a `Spread Json` field and random
`Json` objects, keys drawn to sometimes collide); decode round trip `decode(encode v) == v`
for collision-free values; collisions are errors naming both keys; Validate-vs-Decode
agreement from J2a extended to spread types.

## Part 2 (only if Part 1 is green with an hour left): the `Json a` constraint

Design note §3.6 "Builtin structural `Json a` constraint (compile-time rejection)". The user
has held off on class-constraint work in general (2026-09-12); this builtin is explicitly
requested for this programme, but it must NOT touch the class machinery's behaviour for any
other constraint. First write a one-page design in `tracker/json-stage3/J2b-constraint-design.md`:
where the check runs (after generalisation at `toJson`/`widget` call sites whose argument
type is fully instantiated? at module load for exported signatures mentioning `Json a`?),
what it reuses (`Encode.reject`, `Schema`'s walker), what error and location it gives, what
happens for a type variable still free at the call site, and the corpus impact. Implement
only if the design is a check with no inference changes (a post-typecheck pass over
instantiated `toJson#` call sites) and it passes Tier 0 with corpus verdicts unchanged;
otherwise stop at the design and report.
