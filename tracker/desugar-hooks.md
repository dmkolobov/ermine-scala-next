# Desugar hook table (Stage 1 spec — roadmap item 1.4, Decision (e))

Every name the parser resolves while desugaring, verified against the
code 2026-08-30. The post-rename desugarer (roadmap 3.4) must resolve
exactly these, through the channel listed. Line numbers: parsing/
TermParsers.scala unless marked P (PatternParsers.scala).

## Channels

- **A — alias-sensitive**: a `Local` looked up through canonicalTerms at
  the literal's position; the `_Module` SUFFIX IS PART OF THE LOCAL NAME
  (e.g. `[x]_L` looks up `cons_Bracket_L`), so import aliases decide the
  meaning. The renamer must expose alias-aware lookup to the desugarer.
- **G — loaded-global**: a `Global` looked up directly in termNames,
  which importing() seeds with EVERY loaded module's exports — works
  without importing the provider (Decision (b): reproduce as-is for G1).
- **R — relArrows region**: inside `[| ... |]`, ~15 operators are
  temporarily REBOUND (fixity and referent) via bindFixity/bindName
  around the sub-parse — applied to the COMBINE (`c = expr`) and FILTER
  (bare expr) arms ONLY, never the RENAME arm (`to <- from`); see
  relArrow at :137-141 — the wrap sits on those two alternatives.

## Term-level hooks

| Surface form        | Hook (as resolved)                   | Ch | Site |
|---------------------|--------------------------------------|----|------|
| `[a, b]` / `[..]_M` | `Local("empty_Bracket"[+"_M"])`      | A  | :206 |
|                     | `Local("cons_Bracket"[+"_M"])`       | A  | :207 |
| `{a, b}` / `{..}_M` | `Local("single_Brace"[+"_M"])`       | A  | :96  |
|                     | `Local("snoc_Brace"[+"_M"])`         | A  | :97  |
| `{f = v, ...}`      | `Global("Field","cons")`             | G  | :79  |
| `do` statements     | `Global("Syntax.Do","bind")`         | G  | :255 |
| leading `-` chain   | `Global("Builtin","primNeg")`        | G  | :333 |
| `[| |]` empty       | `Global("Function","id")`            | G  | :151 |
| `[| |]` rename arm  | `Global("Relation","rename")`        | G  | :178 |
| `[| |]` composition | `Global("Function",".",InfixR(9))`   | G  | :189 |
| `[| |]` col wrap    | `Global("Relation.Op","col")`        | G  | :156 |
| `[| |]` prim wrap   | `Global("Relation.Op","prim")`       | G  | :159 |

## Pattern-level hooks

| Surface form   | Hook (as resolved)                  | Ch | Site  |
|----------------|-------------------------------------|----|-------|
| `[p, q]` pat   | `Global("Builtin","Nil")`           | G  | P:62  |
|                | `Global("Builtin","::",InfixR(5))`  | G  | P:63  |

## relArrows rebinding set (channel R; fixities are FORCED)

predCombs (:110-115), rebound as `Global("Relation.Predicate", n, fix)`:
`<=` `>=` `<` `==` `!=` `>` all InfixN(4) · `not` Idfix · `&&` InfixR(3)
· `||` InfixR(2)

opCombs (:117-122), rebound as `Global("Relation.Op", n, fix)`:
`+` `-` InfixL(6) · `*` `/` `//` InfixL(7) · `++` InfixL(5)

The col/prim rewrite (insertPrims, :153-170) then walks the RESOLVED
combine/filter expressions with a left-to-right evolving column set,
descent stopping at Lam/Case/Let/Var/Product/EmptyRecord/Hole/Remember —
it consumes rename OUTPUT and produces new global references, so in the
new pipeline it must run as a desugar-stage pass with rename-table
access (roadmap 3.4c).

## Behavioral notes the desugarer must preserve

- Missing A-channel hooks: warn + BACKTRACKABLE failure (other grammar
  alternatives may still parse the text another way) — pinned in
  TestStage1Pins ("expected '_' or whitespace" is what the fixture
  corpus observes for `[1, 2]` without List).
- G-channel lookups bypass imports entirely (pinned: a module can `do`
  without importing Syntax.Do provided it is loaded).
- Expansion shapes (Decision (h): shapes bit-for-bit, locs per the
  Synthesized policy): foldRight for brackets/records/list-patterns,
  foldLeft for braces, reverse-foldLeft for do, EmptyRecord at the open
  brace for records, `Function.id` for an empty envelope,
  `Lam(loc, WildcardP, _)` for effect-only do statements, and the
  last-do-statement-must-be-an-expression check.
