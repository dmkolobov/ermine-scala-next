# Step 4: porting `core`

## Milestone: `com.clarifi.reporting.ermine.**` compiles ✅

The Ermine language itself — parser, kinds/types/terms, inference (`Subst`),
row-constraint solver (`Constraints`), runtime, sessions and the REPL
(`Console`) — is clean on Scala 3.3.8. Remaining errors are all in the
surrounding ClariFI reporting stack (`relational`, `sql`, `backends`,
`writers`, `flatteners`, `record`), which the REPL pulls in only through
`Lib.scala`'s relational builtins.

## What the port actually required

Grouped by cause, largest first. Nothing here changes behaviour except where
noted.

### Scala 3 language removals
- **Procedure syntax** `def f(..) { .. }` — 110 defs across core + Promise.
  Rewritten mechanically by `tracker/tools/deprocedure.py`.
- **Existential types** (`forSome`) — 3 sites. `Class[T] forSome {type T}`
  became `Class[?]`. `((N, Numeric[N]) forSome {type N}) => Z` in `Lib`'s
  generic numeric dispatch cannot be expressed with a wildcard at all (the
  value and its `Numeric` are correlated), so it became a small trait with a
  polymorphic method — which in turn means its call sites can no longer be
  lambdas.
- **Type projections on structural types** `({type λ[α] = F[α]})#λ` — removed;
  now type lambdas.
- **kind-projector** `F[A, ?]` / `F[A, +?]` — the plugin is gone; ~20 sites
  became `[a] =>> F[A, a]`.
- **`export` is a hard keyword** — `ImportExportStatement.export` renamed to
  `isExport`. (`using` is only a *soft* keyword, so it could stay.)
- **Repeated params in a function type** — `(String, String*) => F[Nothing]`,
  the typer's error-reporting capability, became `Typer.Errs[F]`. Call sites
  are unchanged; only the ~25 signatures and 8 instances moved.
- **Explicit result types on implicit definitions** — ~45 sites.
- Infix method calls with explicit type arguments (`xs traverse_[Parser] f`),
  lambda parameters needing parentheses, tabs mixed with spaces.

### Scala 2.13 collections
- **`mapValues`/`filterKeys` return a lazy `MapView`.** Forced with `.toMap`
  *only* at the ~20 sites the compiler rejected — sites that stay generic keep
  the old lazy behaviour, so this is as close to a no-op as possible.
  Driven from the compile log by `tracker/tools/force_views.py`.
- `SynchronizedMap` (2 sites) → `ConcurrentHashMap`; `JavaConversions` →
  `scala.jdk.CollectionConverters`; `SortedMap#ordering` is no longer implicit.

### Inference differences that bite
- **A `def` that overrides a supertype member now infers the *overridden*
  result type**, not the more specific one. `Binding#close` and `CAlt#map`
  both silently widened (to `Binding` and `Iterable[B]`), breaking callers far
  away. Fixed by writing the specific return type.
- **Wildcard imports shadow inherited/enclosing members** more aggressively:
  `import scalaparsers._` shadowed the one-parameter `Parser`/`ParseState`
  aliases the `parsing` package object supplies, and `scalaz`'s `freshId`,
  `gets`, `modify`, `Name` and `Free` shadowed ermine's. The codebase already
  used `import scalaz.{Name => _, _}` in places — the same idiom, applied where
  Scala 3 now needs it.
- `String` is implicitly convertible to `scalaparsers.Document`, and in Scala 3
  `"fmt".format(..)` resolved to `Document#format` rather than `StringOps`.
  Those two sites became interpolation.
- Scala 2's `any2stringadd` is gone, so `document + "\n"` needed `.toString`.
- A `PartialFunction` built from nested `case` blocks now fixes its result type
  from the first branch (`uncurryPF` in `PrimExpr`).

### scalaz 7.0 → 7.2
- `Validation#flatMap` → `andThen`; `Validation.fromTryCatch` →
  `fromTryCatchNonFatal`.
- `@@` tags no longer unwrap implicitly → `Tag.unwrap`.
- `IO#unsafePerformIO` now takes `()`.
- `scalaz.std.indexedSeq` was removed → `scalaz.std.vector`.
- `Cobind#cojoin` gained a default, so implementations must say `override`.
- **State monad instances are no longer found through a type alias**
  (`type M[+X] = State[S,X]`), so the flatteners name them explicitly.
- `traverseU`/`Unapply` is ambiguous → `traverse` with the applicative named.

### Dependencies
- jline 1.0 → **jline 3** (a real rewrite of the REPL console; see the commit).
- log4j 1.2.15 → the Log4j 2 `log4j-1.2-api` bridge.
- JDBC drivers refreshed from their 2014 pins.
