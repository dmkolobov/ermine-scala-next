# Step 2: `scalaparsers` ported to Scala 3 ✅

Vendored `ermine-language/ermine-parser` @ c5910bc (the published v0.2.3) into
`parsers/`, since no Scala 3 artifact exists and the 2.11 one is off Maven Central.

13 files / 1449 LOC. **Compiles clean on Scala 3.3.8 (0 errors).**

## Changes required

| Issue | Fix |
|---|---|
| kind-projector `Parser[S,+?]` (5 sites) | Scala 3 type lambda `[a] =>> Parser[S,a]`. Note: a variance annotation inside the lambda (`[+a] =>>`) is rejected in this position — Scala 3 checks variance structurally instead. |
| `scalaz.Free.{suspend, Return}` | `Return` is no longer importable as a term in 7.3. `suspend(Return(x))` ≡ `scalaz.Trampoline.delay(x)`. |
| `Trampoline` type | In 7.3 the type alias lives at `scalaz.Free.Trampoline`, while the companion with `delay`/`done`/`suspend` is `scalaz.Trampoline`. Import the former, qualify the latter. |
| Procedure syntax `def f(...) {` (2 sites) | `def f(...): Unit = {` |
| `case Commit(t,a,xs)` against a `ParseResult[S,_]` (2 sites) | Scala 3 GADT-narrows `Commit`'s **invariant** `S` to a fresh `S' <: S`, so `t: ParseState[S']` no longer conforms. Bound via a typed pattern `c: Commit[S @unchecked, A @unchecked]` and project the fields — same semantics Scala 2 inferred. |
| `Parser[S,+A].apply` returns `Trampoline[ParseResult[S,A]]` | **scalaz 7.0's `Free` was covariant in its result type; 7.3's is invariant**, so `A` landed in an invariant position. The trampoline is only produced, never consumed, so `A @uncheckedVariance` keeps the original variance soundly. |

Remaining warnings are pre-existing (non-exhaustive matches in `Document.fmt`, a
deprecated `Char + String`). No behavioural change made.
