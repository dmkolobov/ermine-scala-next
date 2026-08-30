# Step 6: the 2.11 test suite, ported and running

`sbt core/test` — **733 of 734 properties pass.**

```
[info] + Ermine library.all modules load: OK, proved property.
[info] + Ermine library.interesting test modules load: OK, proved property.
[info] + Ermine library.all interesting examples load: OK, proved property.
...
[info] Failed: Total 734, Failed 1, Errors 0, Passed 733
```

That first line is the one that matters most: it type-checks every module in
the Ermine standard library. Together with the constraint-solver, relational,
flattener, SQL-emitter and graph properties, this is much stronger evidence the
port preserved semantics than the REPL smoke test alone.

26 test files / 4.8k LOC, plus `scalacheck-binding`'s sources (which the sbt
0.13 build also folded into core's tests).

## Dependencies

scalacheck 1.11.3 → **1.15.4**, with
`scalaz-scalacheck-binding 7.2.36-scalacheck-1.15` (that artifact pins the
scalacheck version, which is what fixes 1.15 rather than something newer).

## What the port needed

Mostly the same classes of change as `core`, plus scalacheck's own API drift:

- **`forAll { x: T => ... }` → `forAll { (x: T) => ... }`** — 28 sites. The
  script that did this (`tracker/tools/lambda_parens.py`) cannot tell a lambda
  from a parameter declaration containing `=>`, so it also rewrote
  `def f(g: A => B)` into `def f((g: A) => B)` in 21 places; those were undone
  and the remainder checked by hand against the original.
- **`property("x") = someLaws` no longer type-checks.** scalaz's
  `ScalazProperties.{equal,order,monoid}.laws` return a `Properties`, and
  scalacheck 1.15 will not take one where a `Prop` is expected. `include(...)`
  is the idiom; where a `Properties` is built *per sample* (inside a `forAll`)
  it has to be flattened with `Prop.all(ps.properties.map(_._2): _*)`.
- `Gen.value` → `Gen.const`; `Gen.sequence` needs a `Buildable` it will not
  infer for `Stream`, so one call became an explicit fold.
- Abstract methods now need declared result types; `Arbitrary` vals need
  explicit types or implicit search cannot see them (this one cascades — a
  single untyped `Arbitrary` produced 20 "no given instance" errors).
- `NonEmptyList`/`IList`, `@@` tag unwrapping, `mapValues` views, kind-projector
  and existential removals, exactly as in `core`.
- `FilterMonadic` and `CanBuildFrom` are gone; the one helper written against
  them takes a `List` now, which is all any call site passed.
- `TestErmine`'s fixture: a `lazy val` may not implement a strict `val` in
  Scala 3, an *abstract* lazy val is not a stable import path, and a *non-final*
  lazy val is not either — so the trait now declares it
  `protected final lazy val ermineFixture: ErmineFixture = ErmineFixture()`.
  It has to stay lazy: the trait's properties run while the implementing object
  is still being constructed.

## What the tests caught

**A real Scala 3 regression the REPL smoke test missed.**
`Ermine.Ops run` failed with

```
error invoking foreign function: apply on object of type class
com.clarifi.reporting.Op$Mul$; expected an object of type interface scala.Function2
```

Scala 3 case class companions no longer extend `FunctionN`. Ermine's `.e`
modules lean on that: they bind a companion as a value and call it through the
`Function2` interface —

```
value "com.clarifi.reporting.Op$Mul$" "MODULE$" mulModule : OpBin# a
method "apply" funcall2# : Function2 a b c -> (a -> b -> c)
```

— so under Scala 3 every one of those calls dies at run time. There are 30+
such bindings across `Op`, `Format`, `Chart`, `Axis` and `Windowed`, so the fix
went into the foreign invoker (`Session.foreignLift`): if the receiver does not
implement the declaring class of the resolved method, re-resolve the same name
and arity against the receiver's own class. Same method, same arity — only the
reflective handle differs. That fixed both `Ermine.Ops run` and
`Ermine legends.presentation coercion`.

Worth noting: nothing in the REPL smoke test exercised a relational `Op`
constructor, so this would have shipped unnoticed.

## The one remaining failure is a pre-existing broken test

```
! Constraints.disjunction sound: Gave up after only 0 passed tests.
  501 tests were discarded.
```

Every generated case is discarded, so the property never runs. Its generator
cannot satisfy its own precondition. `disjunctionGen` builds three partitions —
one on `x` and **two on `y`** —

```
Partition(y, RHS(avs ++ bvs ++ dvs ++ fvs, afs ∪ bfs ∪ dfs ∪ ffs))
Partition(y, RHS(avs ++ cvs ++ dvs ++ gvs, afs ∪ cfs ∪ dfs ∪ gfs))
```

and then a valuation in which `y` takes the value of the **third** partition
only:

```
vy = afs ++ cfs ++ dfs ++ gfs ++ setUnions(vas.values ++ vcs.values ++ vds.values ++ vgs.values)
```

The precondition `satisfies(f, Set(p1, p2, p3))` therefore needs the `b`/`f`
contributions to equal the `c`/`g` ones — which the generator only produces if
four variable lists and four field sets all come out empty at once, about a
1-in-600,000 draw against 501 attempts.

`TestConstraints.scala` is unchanged since the initial export apart from the
compile fixes above, and the seven *other* `Constraints.*` properties that use
the same `satisfies` all pass — so the constraint solver and `satisfies` are
fine; this one generator is the outlier. I have left it alone rather than
weaken a test to get a green run: an over-constrained precondition is the
test's bug, and how to fix it (probably requiring only one of the two `y`
partitions) is a judgement about intent that belongs to you.
