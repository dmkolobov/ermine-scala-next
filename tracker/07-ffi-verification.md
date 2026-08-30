# What actually verifies the FFI surface

Ermine's `.e` modules reach Scala by *string name*, so a Scala-level grep or
the compiler can tell you nothing about them. This records what does.

## Module loading checks almost everything

Loading a module resolves every foreign declaration in it reflectively and
fails loudly on any mismatch. Verified by deliberately breaking one of each
kind:

| broken declaration | error at load |
|---|---|
| `data "com.clarifi.reporting.NoSuchClassAtAll" Nope#` | `error loading '...'` / `ClassNotFoundException` |
| `method "noSuchMethodHere" bogus# : JStr# -> JStr#` | `method noSuchMethodHere with domain  not found in class java.lang.String` |
| `function "...foreign.Vector" "noSuchFunction" bogus : Int -> Int` | `method noSuchFunction with domain int not found in class ...` |
| `value "com.clarifi.reporting.Op$Mul$" "NO_SUCH_FIELD" bogus : MulM#` | `static field NO_SUCH_FIELD not found in class ...` |

Return types are checked too — two of the three foreign declarations this
migration had to fix were caught exactly this way:

```
Native/NonEmpty.e:15:3: expected return type scala.collection.immutable.List
                        does not match foreign return type class scalaz.IList
Map.e:132:3:            expected return type scala.collection.immutable.SortedMap
                        does not match foreign return type class java.lang.Object
```

So `Loaded 129 modules` is a real assertion: every class, member, parameter
domain and return type named across the whole standard library resolves. That
is broader coverage than the test suite gives, and it runs on every REPL start.

## The one thing it does not check

A foreign **value** and the **method** it is passed to are separate
declarations. Load time verifies each independently; nothing verifies that the
value's class implements the interface the method was resolved on — only
Ermine's type system connects them, and it is not reflective.

`tracker/repl-tests/` does not cover this; it was demonstrated with a module
that binds `Op.Mul`'s companion (a *2*-arg case class) as a **3**-arg function:

```
foreign
  value "com.clarifi.reporting.Op$Mul$" "MODULE$"
      mulAsF3 : Function3 Int Int Int Int

boom = funcall3# mulAsF3 1 2 3
```

The `MODULE$` field exists and `scala.Function3.apply` exists with a conforming
return type, so **it loads clean**. The failure appears only when called, and
appears *inside the result* rather than as a thrown error:

```
>> boom
res0 : Int =
  <error: error invoking foreign function: apply on object of type class
   com.clarifi.reporting.Op$Mul$; expected an object of type interface scala.Function3>
```

This is exactly the shape of the real regression in `06-tests.md`: Scala 3
stopped making case class companions extend `FunctionN`, so the value stopped
implementing the interface while both halves of the declaration stayed
individually valid. Load time could not see it; one property test caught it.

## Audit of that shape

Since it is the only blind spot, it is worth enumerating rather than sampling.
Scanning the `.e` modules for `value "...$" "MODULE$"` bound at a function type
gives **47** bindings, concentrated in `Layout/Format.e` (18),
`Relation/Aggregate/Unsafe.e` (8), `Relation/Op/Unsafe.e` (7) and
`Layout/Chart/Unsafe.e` (7). Against the built classpath:

- 6 companions still implement `FunctionN` directly
- 38 do not, and are reached through the `foreignLift` fallback (they have an
  `apply` of the right arity on their own class)
- 3 were false positives — `Op$FloorDiv$`, `AggFunc$Count$` and
  `scalaz.Ordering$GT$` are not bound at a function type at all; the scan's
  lookahead ran into the following declaration

**Nothing is unresolvable.** Note the fallback matches on the arity of the
*resolved method* at run time, not on how the `.e` file spelled the type, so
bindings that hide the arity behind an alias (`OpBin#`, `OpUn#`) are handled
too.

## Caveat

This audit says every such binding *can* resolve. It does not say every one has
been *invoked*. If you want that, instrument `Session.foreignLift` to log each
binding it dispatches, run `sbt core/test` plus the REPL tests, and diff against
the declared set.
