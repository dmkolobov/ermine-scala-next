# Surface parser working notes (Stage 1, 2.3x)

## The five-way '{' (2.3a deliverable; rules bind 2.3b/2.3c)

Verified against the fused grammar. At a '{' the surface parser decides:

1. **Explicit layout block** — only where a laidout(...) production is
   expected (module body after `module X where {`, block bodies, explicit
   import lists): the enclosing production tries brace() FIRST
   (ParsingUtil.laidout), so position decides, not content.
2. **Kind-argument braces** — only immediately after the NAME position of
   `data`/`type`/`class`/`forall` heads: `data D {k} (a: k) = ...`.
   Positional; never ambiguous with 3-5 because it sits between a
   keyword-anchored name and the argument list.
3. **Row type** — only in TYPE position: `{..r}` (dots form) or `{a, b}`
   (field-set form). Type vs term position is decided by the grammar
   context (after ':', inside type atoms), never by content.
4. **Record literal vs 5. brace-list literal** — both in TERM position;
   the fused pipeline races `rec` vs `fieldList` and '=' decides:
   `{f = e, ...}` is a record iff the first item is followed by '=';
   otherwise it is a brace-list `{a, b}` (single_Brace/snoc_Brace hooks,
   with an optional `_Module` suffix after the closing brace). The
   surface parser commits after scanning the first item for '=' at
   depth 0 (one-token-past-item lookahead, no full backtracking race).
   `{}` parses as SBraceLit(Nil) — the fused fieldList crashes on it
   (head of empty list, masked by race order); the renamer rejects it
   with a diagnostic instead (pinned direction, item 2.3b).

## Span ends

token() consumes trailing whitespace before a following loc can look, so
2.3a span ends point at the next token's start. Statement extents are
exact at the start and safe (over-wide by trailing layout whitespace) at
the end. Tightening to token-end positions is 2.3b polish — do it before
4.3 rebases hit-testing onto real spans.

## Explicit-layout modules

`module X where { ... }` bodies are captured as one
`unparsed:explicit-layout-module` placeholder. No stdlib module uses
explicit layout (checked: the 161-file sweep encounters none — the
placeholder never appears in TestSurfaceParsers' run). Real support
lands with 2.3b statement grammar; the loud placeholder guards against
silent acceptance.

## The statement splitter is the recovery primitive

rawStatementChar implements the per-character offside rule (newline
re-arms; whitespace never decides; anything else must be onside). Stage 2
error recovery = catch a statement-parser failure, splitter-consume the
extent, emit SErrorStatement — the mechanism 2.3a already uses for
not-yet-implemented statement kinds.
