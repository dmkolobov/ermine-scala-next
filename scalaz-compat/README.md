# scalaz compatibility shims, vendored

This project was written against **scalaz 7.0**. The migration targets
**7.2.36** (the newest line published for Scala 3 that still has all four
modules the code needs). Two APIs it uses were removed in 7.1 and so have
nothing to depend on:

| Vendored | Was in | Removed | Used by |
|---|---|---|---|
| `scalaz.IterV`, `Input`, `Enumerator`, `Iteratee` | the separate `scalaz-iterv` artifact | 7.1 | `Backend`, `DB`, `writers`, the `reporting` package object |
| `scalaz.concurrent.Promise` | `scalaz-concurrent` | 7.1 | `Backend`, `util.StreamTUtils` |

Both files are scalaz 7.0.7's own sources, changed only as far as Scala 3
requires (recorded in `tracker/`). Vendoring the removed types keeps every call
site behaving exactly as before; rewriting them onto `scalaz.iteratee` and
`scalaz.concurrent.Task` would be a semantic change well beyond this migration,
and is the obvious follow-up if the project later moves to scalaz 7.3.

Upstream: https://github.com/scalaz/scalaz v7.0.7, BSD 3-clause.
