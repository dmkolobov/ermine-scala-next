# Brief: E5 — `core/examples/Lang/`: the language beyond relations — monads, parsers, validation, strings, IO

Read `tracker/loopmodel/briefs/brief-E-common.md` FIRST; it carries the conventions, rules, wiring policy and
gates. This file says only what E5 covers. Stage name `E5`; group `core/examples/Lang/`, module prefix `Lang.`,
helper library `Lang/Helpers.e`, report `tracker/loopmodel/E5-EXAMPLES.md`.

WHAT IS UNDER-EXAMPLED HERE. The functional-programming half of the stdlib has essentially no examples:
`Control.Functor` (2), `Control.Monad` (3), `Control.Ap`, `Control.Alt`, `Control.Category`, `Control.Comonad`,
`Control.Traversable`, `Control.Monoid`, `Control.Monad.{State,Reader,Error,Cont,Id}`, `Data.Free` /
`Data.Free.Church` / `Data.Cofree` / `Data.Nu`, `Syntax.Do` / `Syntax.Monad` / `Syntax.Reader` /
`Syntax.Procedure` / `Syntax.Either` (1) / `Syntax.Maybe` (3) / `Syntax.List` (2); `Either`, `Maybe`, `Validation`,
`Error`; `Parse` (1) — a parser-combinator library; `String`, `StringManip`, `String.Markdown`; `Map`, `Tree`,
`List.NonEmpty` / `List.Stream` / `List.Util`, `Vector`; `Type.Cast` / `Type.Eq` / `Type.Remember` (1);
`Eq`/`Ord` (4); `IO`, `IO.CSV`, `File` (reading a CSV into a relation — the way real data arrives), `Random`,
`GUID`. Also the language itself: `data` declarations with type parameters and kinds (`(s : rho)`), `forall`/
`exists` in signatures, `foreign` bindings (`Relation/Windowed.e` shows the form), `private`, operator
sections and fixity declarations, pattern matching, `where`/`let`, `case`, records and row syntax
(`{..r}`, `[..r]`, `(| f, g |)`), `field` declarations, the `Has r c` constraints.

READ, beyond the common list: every module named above (public signatures at least), `Prelude.e`,
`core/examples/syntaxExample.e`, `Interp.e`, `Holes.e`, `guide/*.e`, `Parse.e` in full, `IO/CSV.e`, the
`foreign` blocks in `Relation/Windowed.e` and `Relation/Pivot.e`.

## What to build (eight to ten modules plus `Helpers.e`)

* `Helpers.e`: generic helpers that are about the LANGUAGE, with explicit signatures: `traverseRows`
  (`Control.Traversable` over a relation's rows into a `Validation`), `validateRow` (a `Validation`-accumulating
  checker over a generic record), `parseLedgerLine` (a `Parse` parser producing a record), `readCsvAs` (an
  `IO.CSV` reader into a relation with a declared header — say what the type looks like), `withState`
  (`Control.Monad.State` threading a running total through a fold over rows), `askConfig` (`Reader` for report
  parameters — the params→report production shape), `orElse`/`firstOf` (`Alt`), `fold`/`foldMap` over
  `Monoid`s of measures, `remember` (`Type.Remember`), `markdownOf` (`String.Markdown` rendering of a small
  table); two with `xFull`/`xSimple` pairs.
* Modules: a parser for a bank-statement text format feeding a relation and a report; a validation report
  that accumulates every error in a CSV before rejecting (`Validation`, not `Either`); a `State`-threaded
  running-balance fold compared with the relational scan; a `Reader`-parameterised report (the same report
  under three parameter sets); a `Free`/`Cofree` interpreter example that builds a small report DSL and runs it
  two ways (render vs describe); a `Syntax.Do` showcase across `Maybe`/`Either`/`List`; a strings-and-markdown
  report (`StringManip`, `String.Markdown`) that renders to text; a `Tree`/`Map` report (a category tree
  flattened and re-rolled); a `foreign` example if one can be written safely against a JDK class (say if
  not); plus the `Lang/shouldfail/` negative (a parser with an infinite left recursion caught at the type or
  runtime level? — pick what the language actually rejects; a `Validation` misuse) with expected diagnostics.

The point for users: the language guide is two files; these are the missing chapters. The point for the
corpus: where these touch relations (`traverseRows`, `readCsvAs`, `withState` over rows) the solver sees row
variables under monadic types — a shape the census has never measured (G3).
