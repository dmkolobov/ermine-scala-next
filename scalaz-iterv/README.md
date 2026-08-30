# scalaz-iterv, vendored

`scalaz.IterV` / `Input` / `Enumerator` / `Iteratee` are the Scalaz 6
compatibility iteratees. They shipped as the separate `scalaz-iterv` artifact
in 7.0 (which this project depended on), were deprecated there, and were
**removed in scalaz 7.1** — so there is nothing to depend on for Scala 3.

`Iteratee.scala` is scalaz 7.0.7's `scalaz-iterv` source verbatim, apart from
the Scala 3 fixes noted in `tracker/`. Vendoring the removed type keeps the
dozen call sites across `Backend`, `DB`, `writers` and the `reporting` package
object behaving exactly as before; porting them to `scalaz.iteratee` would be a
semantic rewrite well beyond this migration.

Upstream: https://github.com/scalaz/scalaz (v7.0.7), BSD 3-clause.
