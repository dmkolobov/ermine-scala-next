# Step 3: scalaz version choice, and `machines` vendored ✅

## The scalaz decision (this one matters)

The old build used **scalaz 7.0.7**. There is no Scala 3 build of 7.0, so a
version had to be chosen. Both candidates are published for Scala 3:

| | 7.3.9 | **7.2.36 (chosen)** |
|---|---|---|
| `scalaz-core` | ✅ | ✅ |
| `scalaz-effect` | ✅ | ✅ |
| `scalaz-iteratee` | ✅ | ✅ |
| `scalaz-concurrent` | ❌ **not published** | ✅ |
| `\/` variance | **invariant** | covariant (as in 7.0) |

I started on 7.3.9 and hit two blockers that 7.2.36 does not have:

1. **`scalaz.\/` became invariant in 7.3.** `machines` is built on
   `type T[-A,-B] = (A => Any) \/ (B => Any)`, so half of `Tee.scala` stops
   typechecking; the fixes were type ascriptions at every use site.
2. **`scalaz-concurrent` has no 7.3 Scala 3 artifact at all**, which strands
   `writers/jfx` and (originally) `SessionTask`.

7.2.36 is also simply closer to the 7.0 API the codebase was written against,
so it keeps the migration diff small. Switching to it took `machines` from
2 errors to 0 and let me revert every workaround I had added for 7.3.

**What 7.2 still does not give back** (real API changes, fixed properly):
- `scalaz.concurrent.Promise` was removed after 7.0 → `SessionTask` now uses a
  daemon `ExecutorService`, same semantics (see `core/.../session/SessionTask.scala`).
- `Free` became invariant in 7.1 → `Parser`'s `apply` needs
  `A @uncheckedVariance` to stay covariant as it was.
- `Free.Return` is no longer importable → `scalaz.Trampoline.delay`.

## `machines` (ermine-language/scala-machines) — vendored, 0 errors

971 LOC. Needed only two changes, both genuine Scala 3 removals:
- `({type λ[+α] = Machine[K, α]})#λ` → `[α] =>> Machine[K, α]`. Type projection
  on a structural type is **removed** in Scala 3, so every one of these had to go.
- The same declaration was also written across four lines
  (`implicit def f[K]:\n  A with\n  B =`), which Scala 3's indentation-aware
  parser rejects; collapsed onto one line.

Otherwise byte-identical to upstream.

`f0` turned out **not to be needed at all**: its only consumer,
`session/foreign/Fold.scala`, is commented out in its entirety upstream.
