# Step 5: the REPL runs ✅

```
$ bin/ermine
...
Loaded 129 modules (12.38 seconds)
>> :type reverse
forall a. List a -> List a
>> 1 + 2
res0 : Int = 3
```

All 129 Prelude and Layout modules load and type-check on Scala 3.

## Getting the REPL up took four more fixes

### 1. jline 1 → jline 3 (`Console.scala`)
jline 1.0 is long gone. jline 3 replaces `ConsoleReader` with
`LineReader`/`Terminal` and changes three things the REPL relied on:
- `SimpleCompletor` was mutable (`setCandidateStrings`); jline 3's
  `StringsCompleter` instead takes a `Supplier<Collection<String>>` and asks it
  on each completion, so `updateCompletor` now just swaps the collection.
- character echo moved from a reader property to a per-`readLine` mask, so the
  `:echo` toggle keeps its state in `ConsoleEnv`.
- end of input is an exception, not a `null`. `ConsoleEnv.readLine` restores the
  null-at-EOF contract the repl loop is written against.
`TerminalBuilder` is also given `.dumb(true)` so the REPL still runs when stdin
is not a tty — which is what makes the smoke test below possible.

### 2. Three foreign declarations had drifted
The `.e` modules bind Scala/Java methods by name and check the reflected
signature against the declared Ermine type, so library changes surface here:
- `StringOps` moved out of `scala.collection.immutable` in 2.13.
- `NonEmptyList`'s `list` and `tail` return `scalaz.IList` since 7.1.
  `Native/NonEmpty.e` now declares `IList#` and converts at the boundary, so
  every Ermine-visible name (`listNel#`, `tail#`, `nel#`) keeps its old type.
- 2.13 erases `SortedMap`'s `empty` and `updated` return types to `Object`.
  `Map.e` already had this problem for `-` and already had a `MapIsObject`
  coercion for it; the other two now go through the same door.

### 3. `-Dermine.typeCheck=true` (the subtle one)
The REPL came up and evaluated correctly, but **every** type printed as
`forall a. a`:

```
>> :type reverse
forall a. a
>> 1 + 2
res0 : forall a. a = 3
```

Values were right, so it looked cosmetic. It is not: `Session.dep` reads

```scala
if (!s.typeCheck) ((_,_,_) => Some(untyped))
```

and `untyped` maps every binding to `forall a. a`. With it off, no module code
is type-checked at all. `s.typeCheck` reads the `ermine.typeCheck` system
property, which **the sbt 0.13 build used to set** from an
`enable-type-checking` task wired into `compile` — a build detail that is easy
to lose in a build rewrite, and that nothing else complains about.

The tell was that a binding defined *at the REPL* typed correctly while the
same binding loaded *from a file* did not: the REPL path calls
`loadModule(ps, m, _ => None)`, the file path goes through `Session.dep`.

With the flag: `(+)` is `forall n. Num n => n -> n -> n` and `[1,2,3]` is
`List Int`.

### 4. `.ei` interface caching made runs non-deterministic
Ermine caches each type-checked module as a pretty-printed `.ei` file beside the
class files, and prefers it on the next run (12.4s → 5.9s). The cached form is
more explicit about kind quantification, so `:type fst` answers
`forall {a b} (a1: a) (b1: b). (a1, b1) -> a1` from cache and
`forall a b. (a, b) -> a` from a fresh check. The smoke test therefore runs with
`-Dermine.useInterface=false`, and the build excludes `*.ei` from packaged
resources (as the old build did) so a stale interface never ships in a jar.

## Testing

`tracker/tools/repl-smoke.sh` drives the REPL from
`tracker/repl-tests/smoke.in` and diffs against `smoke.expected` — 23 checks
covering inferred types (including a class constraint and a `let`-bound
polymorphic function), arithmetic, lists, `Maybe`, tuples, higher-order
functions and folds. It passes, and is deterministic across runs.
