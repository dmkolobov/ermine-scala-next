# Findings while testing

Two things behave surprisingly. **Both are pre-existing in the 2.11 source, not
migration regressions** — I checked the original at `8de8010` in each case. I
have left them alone: a migration should not quietly change behaviour. They are
written up here so you can decide.

I could not run the 2.11 build to confirm empirically — its dependencies
(`scala-parsers`, `f0`, `machines`) are no longer resolvable, which is what
started this whole exercise — so "pre-existing" here means "the code that
produces it is byte-identical to the original".

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

## 2. A name exported by the Prelude cannot be used as a pattern variable

```
f (a :: t) = a     -- fine
f (h :: t) = h     -- error: ill-formed expression, expected ')', name, ...
```

...but only when `Prelude` (or `Layout`) is imported. `Layout/Report.e:248`
defines

```
h : Int -> String -> Report f z
```

an HTML-heading helper, so with the Prelude in scope `h` resolves to that
binding and the pattern parser will not take it as a fresh variable. Any
single-letter name the Prelude happens to export behaves the same way.

This is why the bundled example `core/examples/guide/HelloWorld.e` does not
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
