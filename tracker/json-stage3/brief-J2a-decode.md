# J2a: the params decoder (type-directed JSON -> Runtime)

Branch `json-decode`, worktree `~/research/ermine/ermine-scala-wt-json-decode`, off
`json-s3-base`. Budget 4 h. Read `brief-J-common.md` first.

## Why

The document runner (J3c) takes `{"params": ...}` from the request, decodes it against the
report's `Params` type and applies `report : Params -> Node`. Design note §3.3; §5 Stage 2
row ("round-trip property: decode(schema, encode v) == v for the serializable fragment").

Read: design note §3.1 (the mapping table), §3.3, §3.7/3.7a (named fields: tag rules,
omitted `Nothing` fields); `json/Encode.scala` (THE mapping -- the decoder is its inverse),
`json/Schema.scala` (the static walker you mirror: alias expansion to a fixed point,
`unfurl`, `resolve`, how it reads `DataConDecl`), `DataConDecl.scala`, `Runtime.scala`
(`Data`, `Prim`, `Rec`, `Arr`, `NullableValue`, `accumData`), `PrimT.scala`.

## Build `core/.../ermine/json/Decode.scala`

- `Decode.decode(ty: Type, j: argonaut.Json)(implicit s: SessionEnv): Either[Decode.Error, Runtime]`
  with `final case class Error(path: String, message: String)` (`report` like Encode's).
  Paths are JSON paths into the INPUT document: `$`, `.key`, `[i]` (a positional
  constructor's arguments are `.args[i]`). The runner prefixes `$.params`.
- `Decode.entry(ty: Type)(implicit s: SessionEnv): Either[Decode.Error, Type]`: accept only a
  monomorphic, closed-row type (after alias expansion); refuse type variables, `forall`,
  open rows, and anything with no decoding (below), with a message naming the offending
  part. `decode` calls it first. Also a helper the runner will use:
  `Decode.reportSignature(ty): Either[Error, (Type, Type)]` splitting `P -> R` (aliases
  expanded) and refusing a non-function or polymorphic scheme.
- Mapping (inverse of Encode, strict): Int/Short/Byte from JSON integers in range (refuse
  fractions and out-of-range); Long from a decimal string (`^-?[0-9]+$`, in range); Double
  from any number; Bool; String; Char from a one-character string; Date from `yyyy-MM-dd`
  (GMT midnight -- check what runtime class a Date value is, `java.util.Date` vs
  `java.sql.Date`, by evaluating one in Ermine, and produce exactly that); Timestamp from
  the encoder's format (decide whether to also accept other ISO-8601 offsets; document);
  GUID; `Maybe a` (null -> `Nothing`, else `Just`); `Nullable a` (null -> `Null` carrying the
  column's `PrimT` witness, else the value as the runtime represents a non-null Nullable --
  check `NullableValue` and what `Encode` accepts); `List a` / `Vector a` / `List# a` as
  their runtime representations (check each by evaluating a literal); tuples and `()`;
  closed records `{..(|f..|)}` -> `Rec` (exact key set: missing and extra keys are errors);
  `data`: all-nullary -> string enum; named fields single-constructor -> object without tag;
  named fields multi-constructor -> `tag` + fields; a missing key whose declared type is
  `Maybe` -> `Nothing`; extra keys -> error; positional -> `{tag, args}`; type arguments
  substituted into constructor field types (`DataConDecl` constructors with existentials
  -> refuse); the stdlib `Json` type -> `Encode.fromArgonaut` (identity, any JSON).
  Refuse with a path: relations, `Inline`/`Deferred`, `JRel`-bearing positions are fine
  only inside a `Json` value (they cannot arise from parsed JSON anyway), functions, IO,
  FFI, foreign types, Field/PrimT witnesses.
- Build `Data` through the constructor `Global` from the registry exactly as
  `Runtime.accumData` would (a decoded value must be `==` to the evaluated one).
- Iterative or depth-bounded: the argonaut parser bounds depth, but do not recurse per
  LIST ELEMENT (a 100,000-element list must decode).
- Do not reuse `PrimT.coerce` (its date pattern is wrong, design note §3.3).

## Properties (random declarations and values)

- (a) Round trip: for random `(Type, Runtime)` from `TestSchema.shape` (extend the shape
  vocabulary if Char/Short/Byte/Date/Timestamp/GUID/Nullable/Vector/record-style data are
  missing -- coordinate by ADDING cases, and keep `TestSchema`'s existing properties green;
  J3a is editing TestSchema's relation parts in parallel, so keep your TestSchema diff to
  new generator entries and visibility changes), `decode(ty, encode(v)) == v` (Runtime
  equality after forcing; write a stack-safe comparison if `==` recurses).
- (b) Agreement with the schema: for random documents (valid encodings and single random
  mutations of them), `Validate(exportType(ty), j)` is empty IFF `decode(ty, j)` succeeds.
  Any disagreement is a bug in one of the two; fix the decoder, or report the validator
  gap and pin it.
- (c) Error paths: for a mutation at JSON path p that makes the document invalid, the
  decoder's error path is p or an ancestor of p no more than one level up (a missing
  required key reports the object). Report the distribution.
- (d) Entry: random polymorphic / open-row / function-containing types are refused by
  `entry` with a message; random closed ones accepted.
- (e) Scale: a list of 100,000 records decodes; nesting to the parser's depth decodes or
  fails cleanly (no StackOverflowError escapes).

## Also

- A `:decode <Type> <json>` REPL command is NOT required; if you add one, add a smoke case.
- Record the Stage 2 as-built notes in a new "§3.7b Stage 2a as built" section of the
  design note (short) and tick J2a in the plan.
