# `core/examples/Lang` — the language beyond relations

**Ten** self-contained report modules about the **value-level language a report is
written in**, plus a shared library of **seventy-one generic bindings** (`Helpers.e`) and
machine-checked proofs about their signatures (`Signatures.e`) — **twelve `.e` files** —
with seven negative modules under `shouldfail/` and one `.slow` module that measures a
compiler cliff (`ProjectionCliff.slow`).

Every other directory under `core/examples` is about relations. This one is about
monads, parsers, validation, state, readers, free structures, strings, trees, maps and
`foreign` — the half of the stdlib that had almost no example at all. Before this
directory:

`Control.Ap` · `Control.Alt` · `Control.Category` · `Control.Comonad` ·
`Control.Traversable` · `Control.Monoid` · `Control.Monad.{State,Reader,Error,Cont,Id}` ·
`Data.Free` · `Data.Free.Church` · `Data.Cofree` · `Data.Nu` · `Syntax.Do` ·
`Syntax.Monad` · `Syntax.Reader` · `Syntax.Procedure` · `Validation` · `Map` · `Tree` ·
`List.NonEmpty` · `List.Stream` · `List.Util` · `Vector` · `String` · `StringManip` ·
`String.Markdown` · `IO.CSV` · `File` · `Random` · `GUID` · `Type.Cast` · `Type.Eq` ·
`Type.Remember` · `Constraint`

had between them **no example, or one**. The language guide is two files and fifty-eight
lines (`guide/HelloWorld.e`, `guide/LetAndPatternMatching.e`); these are the missing
chapters.

Load the library first — every module imports it:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2" \
      bin/ermine core/examples/Lang/Helpers.e \
                 $(ls core/examples/Lang/*.e | grep -v 'Helpers\.e')

No two top-level names in this directory collide, so the whole group loads into one REPL
session and every binding below can be evaluated in it.

## The one thing to know before reading any of it

**Ermine has no instance system.** Every class in `Control.*` is a plain `data` value —
a dictionary — that you pass by hand:

    data Monad f = Monad (forall a. a -> f a) (forall a b. f a -> (a -> f b) -> f b)
    bind : Monad f -> f a -> (a -> f b) -> f b

`do` notation works anyway because `Syntax.Do` desugars a block into a **reader of the
dictionary**: `do …` has type `Monad f -> f a`, an ordinary monadic value must be lifted
in with `liftDo`, and the block is applied to the dictionary at the end
(`(do …) ' maybeMonad`). The `Syntax.X` modules are the alternative — each fixes one
monad and can therefore afford operators (`>>=_Mb`, `<$>_Eth`, `<*>_SR`). That is
Ermine's substitute for `instance`, and `Lang/DoNotation.e` shows all three spellings of
the same computation side by side.

## The modules

| file | subject | fact row | what it exercises |
|---|---|---|---|
| `StatementParser.e` | a bank statement parsed from text | 7 cols | parser combinators written in Ermine (`Parser`, its `Monad`/`Ap`/`Alt`); `pRecord` chained **six** deep, so a row variable travels under `Parser`; `Control.Alt` as a keyword table; `do` and hand-written `bind` side by side, proved equal |
| `CsvIntake.e` | a CSV read into a relation | 6 cols | `IO.CSV.parseCSV` for real; a row-polymorphic `RowReader` with a **user-defined bracket literal**; accumulating validation that reports **five** errors where `eitherAp` reports two; `Validation.FormValidator` for the report's own parameters |
| `RunningState.e` | a running balance, three ways | **13 cols** | `Control.Monad.State` and `StateT s Maybe`; `withRunning`'s `t <- (r, c)` at the group's widest row; `Layout.Report.scanRelationInOrder` driving the same fold from the relation; `Control.Monoid.mproduct` for two measures in one pass |
| `ReaderParams.e` | one report, three parameter sets | 11 cols | `Control.Monad.Reader` as the params→report production shape; `askField`'s `Has e h`; five projections of one parameter record; `local`; `Syntax.Reader`'s `<$$>`; `ReaderT r Maybe` |
| `FreeReportDsl.e` | a report DSL, run two ways | 8 cols | `Data.Free` (`freeMonad` from a hand-written `Functor`), three interpreters over one program; `Data.Free.Church` and `runF`; `Data.Cofree` as an infinite stream with `extend` as a moving average; `Data.Nu` with its seed genuinely hidden |
| `DoNotation.e` | one `do` block, five monads | 10 cols | `Syntax.Do` at `Maybe`, `Either`, `List`, `State` and `Parser`; `Syntax.Monad` vs `Syntax.Maybe` vs raw dictionaries; `liftA2`…`liftA6`, `tupleA2`, `strength`, `mapply`, `join`, `ifM`; `traverseRows` and `checkedRel` over a 10-column relation |
| `TextTables.e` | a relation rendered to text | 9 cols | `String` in full, `StringManip.allMatches` (regex through six `foreign` declarations), `String.Markdown`; four renderings of one relation — markdown, fixed-width ASCII, CSV and a sentence — **all of which print** |
| `TreeAndMap.e` | a category tree flattened and re-rolled | 8 cols | `Tree.unfold`/`fold`/`aggregate`/`identify`; `Tree.toRootedRel`'s three-part partition with ids **minted** by the stdlib; `Tree.fromRel` under `Layout.Scan.runner`; `Map` in full; `Ord` as a composable value |
| `ForeignJdk.e` | reaching the JVM | 10 cols | all six `foreign` forms (`data`, `constructor`, `method`, `function`, `value`, `subtype`) plus `private foreign`; `IO` vs `FFI` results; an overload narrowed by its declared type; `Random`'s seeded stream; `GUID` |
| `TypesAndRows.e` | the language itself | **12 cols** | `data` with `(s : rho)` and `(f : * -> *)`; existentials; `private`; fixity; **every pattern form**; the whole row vocabulary; `Type.Eq`, `Type.Cast`, `Type.Remember`; `Void`/`absurd` |
| `Helpers.e` | 71 public generic bindings | — | 16 quantify over a row; **5** carry an explicit row constraint (`consRow`, `pRecord`, `withRunning`, `askField`, `localField`) |
| `Signatures.e` | entailment proofs | — | **five** `xFull`/`xDeduped` pairs, a three-step `Has`-sugar round trip, **five** `xSimple` specialisations, two lemmas |

## What you can and cannot run

There is **no `render`**: a `Report` needs a `Layout.Writer` and every concrete writer
lives in the separate `ermine-writers` project, which is not on this build's classpath.
So a `Report` evaluates to `Report <function>` and its relations print their resolved
headers. See `core/examples/Present/README.md` for the full account.

This directory is the one place that gets round it, because **a markdown table is a
`String`**. Four bindings print a document you can read:

    >> catalogueMarkdown      -- Lang/TextTables.e
    >> catalogueAscii
    >> renderOf salesProgram  -- Lang/FreeReportDsl.e, the Free-monad interpreter
    >> spendTreeShown         -- Lang/TreeAndMap.e

## Ten things about the language that cost a compile here

Each is documented in the module that hit it. The seven modules under `shouldfail/` are about
the HELPERS rather than about the syntax; `lang07` below is the one syntax fact that got its own
negative.

1. **`length` is `List.length`.** `Prelude` exports `List` unqualified; the `String`
   length is a builtin registered as `String.length`, so write `length_S`.
   `import Prelude hiding length` makes `length` *undefined*, not the builtin.
2. **`++` is `List.(++)`**; string concatenation is `++_S`.
3. **`||` is `Layout.Report`'s selector-event disjunction**, not `Bool`'s. `Prelude`
   exports both and `Layout.Report` wins, so a boolean `or` is `||_B`. (`&&` is fine.)
4. **There are no operator sections.** `(2 +)` is `ill-formed expression`, `(+ 2)` is
   `unknown operator +`. Only the bare `(+)` exists; write a lambda.
5. **A bracket or brace literal with a module suffix cannot be a non-final argument.**
   `const []_L "x"` does not parse (`expected eof or whitespace`); `const ([]_L) "x"`
   does. A `]_L` that *ends a right-hand side* also cannot be followed by `where` — which
   is why `TypesAndRows.e`'s pattern tour is thirteen top-level functions — though a
   `]_L` in a function's last *argument* position can be.
6. **A character literal is rejected by POSITION, not by which character it is.** `'-'`,
   `'.'`, `'|'` and `'/'` all lex in head and argument position — `TextTables.e` writes
   `split_S '/' p`. Immediately after a **binary operator** the lexer takes `'` and the
   character as one operator token and every operator character fails: `c == '-'` is
   `unknown operator '-'`, and so are `c == '.'`, `c == '|'` and `c == '/'`.
   Parenthesising does not help (`c == ('-')` is `undefined term`); name the literal
   (`Helpers.dashChar`).
7. **`'` and `$` are both `infixl 0`**, so a right-nested chain needs parentheses.
8. **A bracket literal is not a pattern.** `[Just y, Just m]_L ->` is a parse error;
   cons patterns are the way.
9. **To define your own bracket literal you must hide `Prelude`'s**
   (`import Prelude hiding {empty_Bracket; cons_Bracket}`), and then *every* unsuffixed
   `[...]` in that module is the new literal.
10. **`Parse.parseInt` and `Parse.parseDouble` are not total.** They return
    `Just <bomb>`, not `Nothing`:

        >> parseInt 10 "1O2"
        res0 : Maybe Int = (Just <error: For input string: "1O2">)
        >> isJust (parseInt 10 "1O2")
        res1 : Bool = True

    `Runtime.scala:51`'s `Prim.apply` turns an exception raised while forcing a foreign
    result into a `Bottom` *value*, so `IO.Unsafe.eval`'s `try/catch` never fires and
    `Parse.numberFormat`'s `NumberFormatException` branch is dead code.
    `Helpers.parseIntTotal` / `parseDoubleTotal` are the workaround: check the string
    first — shape **and range**, because `parseInt 10 "99999999999999"` is all digits and
    still throws. `Lang/ForeignJdk.e` reproduces the bug from scratch, and shows that
    **`IO.catch` cannot catch it either**.

## The REPL trap, exactly

`Console.other` (`Console.scala:617`) decides a typed line is unfinished if it **contains
the substring** `case`, `let` or `where` — not the token, the substring — and
`ConsoleEnv.readLine` (`Console.scala:146`) returns **`null`** at end of input while the
loop tests `last == ""`. So from a script:

    $ printf '"complete"\n' | bin/ermine        # "comp-LET-e"
    >> |> |> |> |> |> …                          # forever

`null == ""` is false, so `blank` never becomes true, `"\nnull"` is appended to the input
on every pass, and `balanced` and `contains` rescan a string that grows without bound:
3,837 `|>` prompts in 40 seconds and still going. **One blank line after the offending
line fixes it** and the line then evaluates normally. Interactive sessions are fine —
you press return.

Nothing in this directory is named with one of those substrings, so every recipe here is
safe to pipe.

## `shouldfail/`

Seven negatives, each with its expected diagnostic recorded verbatim in its header.

| module | mistake | diagnostic class |
|---|---|---|
| `lang01_parser_row_mismatch.e` | a `pRecord` chain annotated one column short | row unification |
| `lang02_reader_field_twice.e` | a CSV reader reading one field twice | duplicate field |
| `lang03_running_column_exists.e` | a running-total column the input already has | duplicate field |
| `lang04_wrong_monad.e` | a `do` block applied to the wrong dictionary | type unification |
| `lang05_traverse_row_mismatch.e` | `traverseRel` dropping an annotated column | row unification |
| `lang06_escaping_existential.e` | projecting `Nu`'s hidden seed | skolem escape |
| `lang07_kind_variable_written.e` | the interface printer's own inferred scheme, written back | kind unification |

`lang07` is worth reading on its own: a `-Dermine.useInterface=true` load of an
eta-delegating wrapper emits `forall {a} … (a1: a)`, a scheme with the value type at an
inferred **kind** variable, and that scheme does not parse — `->` demands kind `*`. The
minimal case is `atAnyKind : forall {k} (a: k). a -> Int`.

## The projection cliff — `ProjectionCliff.slow`

`t ! f` on a record whose row is a VARIABLE is a `Has r f`, i.e. `exists c. r <- (f, c)`
— one existential row partition. **N projections of the same record in one expression
are N existential partitions over one whole, and the cost is roughly 6× per extra
projection:**

| N | draws | dequeues | minted vocabulary | module load |
|---|---|---|---|---|
| 1 | 0 | 0 | 0 | 0.14 s |
| 2 | 3 | 5 | 1 | 0.11 s |
| 3 | 31 | 23 | 5 | 0.13 s |
| 4 | 207 | 65 | 11 | 0.21 s |
| 5 | 1,241 | 217 | 27 | 0.68 s |
| 6 | 6,956 | 698 | 60 | 2.00 s |
| **7** | **> 20,000 — the draw budget fires** | — | — | 2.93 s, **REJECTED** |

(The last column is the minted-variable *vocabulary* size, `--cycle`'s `maxmint`. The
per-key mint count — `--mints` — is **1** over the whole group, as it is for every group
in the E series.)

```
Row solver resource limit reached (this is NOT a type error): the row constraint solver
drew 20009 fresh row variables at this signature, past the -Dermine.solveBudget=20000
limit, so it was stopped rather than left to run.
```

This is not an exotic shape. It is what you write to render a row —
`showRows hdr (t -> [t ! a, t ! b, t ! c, t ! d, t ! e, t ! f, t ! g]) rows` — for a
seven-column table. Three bindings in this group do it with five columns and they are the
three most expensive solves in the E-series corpus: `TextTables.catalogueMarkdown` (1,241
draws), `RunningState.postingMarkdown` (1,233) and `TextTables.catalogueAscii` (1,230). Their
*order* is not stable — all three sit within 1 % of one another — so treat them as a set.

The same cliff was found independently, at the same time, from the presentation side:
`core/examples/Present/shouldfail/proj01_seven_reads.e` is the negative for it and
`tracker/loopmodel/E4-REVIEW.md` carries a second ladder (3 / 33 / 207 / 1,243 / 6,795 /
budget) measured with bare `p ! f` projections instead of a list literal. That review also
found the stronger remedy: five projections under **one written partition**,
`forall r o. (r <- ((| p1, …, p5 |), o)) => {..r} -> String`, cost **zero** draws.

**The fix a user has is to write the row down**, and it is the *only* fix: reordering the
helper's arguments changes nothing (1,230 → 1,233 draws), while annotating the lambda's
argument takes the same call to **1 draw**. The seven projections with the argument
annotated `{q1, …, q7}` compile in **0.04 s**: with a concrete row there is no row
variable and no existential at all. `TextTables.e` and `RunningState.e` ship both
spellings side by side (`catalogueMarkdownPinned`, `postingMarkdownPinned`). That is the same shape
`core/examples/incomplete/README.md` records for the star-join cliff — "same eight
dimensions, and the type annotation is the only difference."

`ProjectionCliff.slow` carries the whole series and is `.slow` rather than `.e` because
`core/test` type-checks every `.e` under `core/examples` and this one does not compile. It is
not a second `shouldfail/` module because `Present/shouldfail/proj01_seven_reads.e` already
carries the refutation; what this file adds is the curve.

**Left recursion is not in this list.** `pMany p` where `p` can succeed without consuming
input loops forever, and Ermine says nothing about it: `Parser a` is a function type and
a diverging function is well-typed. There is no negative for it because there is nothing
to reject.
