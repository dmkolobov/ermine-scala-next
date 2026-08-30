# Findings while testing

Two things behave surprisingly. **Neither is a migration regression.** I have
left them alone: a migration should not quietly change behaviour. They are
written up here so you can decide.

- The second one is a **known bug already filed in this repo**, under
  `core/examples/bugs/` — the diagnosis below is the upstream author's, and it
  reproduces on this branch exactly as their report describes.
- For the first, `Term.scala` is byte-identical to the original at `8de8010`
  (`git diff 8de8010 --ignore-cr-at-eol -- .../Term.scala` is empty), so the
  code producing it is unchanged. I could not run the 2.11 build to confirm the
  *behaviour* empirically — its dependencies (`scala-parsers`, `f0`,
  `machines`) are no longer resolvable, which is what started this whole
  exercise.

`core/examples/bugs/` holds two reports, both runnable. Their current status on
this branch: `variableShadow.e` still reproduces (finding 2 below);
`variableCapture.e` does **not** — see the end of this file.

---

## 1. `let` in function position drops its arguments

```
>> (let f x = x + 1 in f 3)
res0 : Int = 4          -- correct

>> (let f x = x + 1 in f) 3
res1 : Int = <function>  -- wrong: should be 4
```

The type is inferred correctly (`Int`); only evaluation is wrong. In
`Term.eval` (`core/.../ermine/Term.scala:194`):

```scala
case Let(l, is, es, b) =>
  var envp: Env = null
  envp = env ++ (is ++ es).map(b => b.v -> evalBinding(b, envp))
  eval(b, envp)          // <- `stk` is not passed on
```

Every other case threads the argument stack — `Case` right above it even has a
comment about doing so. Dropping `stk` here means any pending arguments are
discarded when a `let` appears in function position. The fix is one word:
`eval(b, envp, stk)`.

`Term.scala` has **no changes** from the original in this migration
(`git diff 8de8010 --ignore-cr-at-eol -- .../Term.scala` is empty), so this is
upstream. I have not applied the fix.

## 2. A pattern variable may not shadow a global — already reported upstream

```
f (a :: t) = a     -- fine
f (h :: t) = h     -- error: ill-formed expression, expected ')', name, ...
```

...but only when `Prelude` (or `Layout`) is imported. The cause is not the
`::` pattern, which is what the message suggests. Written without the
parentheses the compiler says what it actually means:

```
f h = h
      ^ error: pattern variable shadows global binding Prelude.h
```

`Layout/Report.e:248` defines `h : Int -> String -> Report f z`, an HTML-heading
helper, and a pattern variable is not allowed to shadow a global binding. Any
name the Prelude happens to export behaves the same way; the parenthesised and
infix pattern paths just report it as a parse error instead of a shadowing one.

**This is a known bug, filed in this repo**: `core/examples/bugs/variableShadow.e`

```
-- this fails because fmt in the definition of foo isn't allowed
-- to shadow fmt in the global scope.
-- Load this file (i.e. into the repl using import) in order to see the bug.
module Foo where
import Layout
foo fmt = 1
```

It still reproduces on this branch, with the error it documents
(`pattern variable shadows global binding Layout.fmt`) — so the behaviour is
unchanged by the migration, and the diagnosis is the upstream author's, not
mine.

**Update (2026-08-30): fixed on this branch**, in a change separate from the
migration. Name resolution happens at parse time against a flat module-wide
environment (`canonicalTerms`); binders shadowed `termNames` but never that
map, so a binder colliding with an import was rejected — and `let` "unbound"
its names by deleting them instead of restoring, so
`f w = (let w = 10 in w) + w` lost the outer `w`. Binders (pattern variables
and `let`/`where` bindings) now shadow both maps with save/restore
(`LocalBlocks` in `parsing/TermNameParsers.scala`), and a block's bindings are
rewritten letrec-style where an earlier sibling referenced the shadowed outer
variable. Top-level definitions still may not shadow an import; a
block binding whose shadowed import is in scope under several names (import
aliases) is refused when a reference would be captured, `?[...]` references
rebind like plain ones, and data-constructor operators stay unshadowable —
see tracker/TICKET-scoping-renamer.md for the review that drove these and the
eventual renamer design. Covered by the
"Ermine scoping" properties (`scalacheck-binding/src/main/scala/TestScopes.scala`)
and `tracker/repl-tests/scoping.in`; `variableShadow.e` and this section's
examples now load, and `core/examples/guide/HelloWorld.e`'s `go (h::t)` parses
(that example still has the unrelated issues below).

This is also why the bundled example `core/examples/guide/HelloWorld.e` does not
load: its `sum` uses `go (h::t) acc`. Renaming `h`/`t` gets past it (I verified
the rest of that example — literal relations, field declarations, row types —
works; see `tracker/repl-tests/Relations.e`, which is that example's language
and relational half, and is part of the test suite).

Two further things in that same example are also unrelated to the migration:
- `tabular`/`defaultLegend` are not in scope from `import Prelude` alone.
- `employees |> { FavoriteColor ID => ... }` uses a selector syntax this branch
  does not have — the repo has a `closed/fancy-selectors` branch, and the file
  itself carries a commented-out alternative on the next line.

The example looks like it predates the current Prelude.

## The other filed bug no longer reproduces

`core/examples/bugs/variableCapture.e` reports that the type checker wrongly
unifies two `x`s bound in separate `let` clauses:

```
{-  For some reason, the type checker tries to unify both x's together, even
    though they're in separate let clauses.
  To replicate, load in repl.  Should receive "error: failed to unify type
  String with type Int"  -}
```

On this branch it loads cleanly, with type checking on — so whatever caused it
was fixed at some point before this migration. Worth knowing before anyone
chases it.
