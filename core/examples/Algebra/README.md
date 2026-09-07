# `core/examples/Algebra` — the relational-algebra corners

Eleven self-contained reports plus a helper library (`Helpers.e`), a signature-proof
module (`Signatures.e`) and six negative modules (`shouldfail/`). They exist to
cover the parts of `Relation.e` and its satellites that had no example at all:
outer joins with defaults, set operations, semi- and anti-joins, transitive
closure, deduplication, key-value schemas, self-joins, `Relation.Scan` and
`Relation.Process`.

Everything here type-checks. Load the library first — every module imports it:

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
    ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2" \
      bin/ermine core/examples/Algebra/Helpers.e \
        $(ls core/examples/Algebra/*.e | grep -v 'Helpers\.e')

or, from the REPL, `:load core/examples/Algebra/Helpers.e`, then the module you
want, then `:import Algebra.<Module>` and evaluate a relation or a report by
name. (There is no `render` command — see the note at the end.)

## The reports

| file | subject | what it exercises |
|---|---|---|
| `OrderLedger.e` | order lines, five dimensions, three of them incomplete | `joinWithDefault` (the stdlib's only `exists`-quantified constraints), `leftJoinOr`/`rightJoinOr`, semi- and anti-joins, 16-column fact row |
| `BillOfMaterials.e` | a BOM exploded | transitive closure by path doubling, `leafRows`, `Relation.RTree`, `accumulate` roll-up, `copyColumn` |
| `Customer360.e` | six systems, six names for one customer | six `rename`s to one key, `partialLookup`, `dedupeBy`, a 19-column joined row, and the `Relation.UnifyFields` finding |
| `InventorySnapshots.e` | two snapshots reconciled | `union` / `difference` / intersection-as-join, added vs removed vs changed, `unionAllWithHeader` |
| `Deduplication.e` | a change feed, latest wins | `groupBy` with four different group functions, `firstBy`/`lastBy`, the builtin `Count` field |
| `SoftSchema.e` | key/value telemetry widened three ways | hand-written pivot, `Relation.Pivot`, `Layout.Report.SoftRelation` |
| `ManagerChains.e` | an org chart | self-join done properly, `join1`, closure over projected edges, `leafRows` |
| `LedgerScan.e` | a general ledger, scanned | `Relation.Scan` directly: `groupBy1`/`groupBy1'`, `mapK`, `sortK`, `pickK`, `filterK`, `removeK`, `sumBy'`, `count'` |
| `RateStatistics.e` | interlaboratory runs, four averages | `Relation.Process` (`medianBy`, `weightedMeanBy`, `weightedHarmonicMeanBy`) against `Relation.Aggregate` |
| `KeyDiscipline.e` | readings valued | `join` vs `join1` vs `joinBy` vs `joinBy'`, `memoRelWithPK`, `letRWithPK`, `replaceColumn` |
| `Comprehensions.e` | one report in two syntaxes | `Syntax.Relation`'s `[\| … \|]` in all three clause forms and combined, each proved to have the same type as its longhand; `rightJoinWithDefault`, `unsafeRightJoin`, `partialLookup'`; a running total computed relationally and by scanning |

`Helpers.e` holds thirty-three row-polymorphic helpers with explicit signatures;
`Signatures.e` proves for four of them that the hand-written signature and the
one the compiler infers entail each other. The fourth is the sharpest:
`runningTotal`'s two hand-written constraints are equivalent to the twenty-one
the compiler infers when the signature is removed, so nineteen of them are
noise.

## Three things this directory found out

**`Relation.UnifyFields.unify1` cannot unify fields.** Its constraints force the
two operands to agree on every column but one each, and the column being renamed
appears in no constraint at all, so the cross-schema call its name promises is
rejected. `Helpers.alias` (plain `rename`) is what the reports use.
`Customer360.e` and `shouldfail/alg03` have the measurement.

**`Relation.join1` is not "the intersection is nonempty".** `r <- (k, r1, r2)`
is a partition, so the two operands' remainders must be DISJOINT — `join1 f`
means `f` is the whole key, exactly like `joinBy {f}`. `KeyDiscipline.e`
spelling 4 and `shouldfail/alg05`.

**A row variable written in the `[f1, f2]` relation-type syntax is read as a
LABEL.** `mk : Field c String -> [a, c]` checks, and `mk` is reported as
`forall (c: rho). Field c String -> Relation (|a, c|)` where the `c` in the
result is a fixed label rather than the argument's row — so `mk c1` has type
`Relation (|a, c|)`, not `Relation (|a, c1|)`, and the mistake surfaces at some
later call site. Write `[..r]` with a partition constraint instead.
`SoftSchema.e` says so where it would otherwise have used such a helper.

## Seeing the numbers

`core/examples/Ai/README.md` says `render <theReport>`. There is no such term in
any stdlib module and no such REPL command: a `Report` is a function of a
`Writer`, and every concrete `Writer` lives in the separate `ermine-writers`
project. In the REPL a report evaluates to `(Report <function>)` and a relation
evaluates to its computed HEADER — still a real check, because computing the
header runs the whole relational expression.

To see actual ROWS, compile a relation to SQL and run it:

    ERMINE_RENDER_MODULES="core/examples/Algebra/Helpers.e $(ls core/examples/Algebra/*.e | grep -v 'Helpers\.e')" \
      tracker/tools/sql-render.sh <probe>.e <outdir>

Eighteen of this directory's relations render real tables that way, and every
row count matches what the module's header claims. Two limits: a `Mem`
(everything `groupBy` produces) answers "Don't know how to dump a mem", and
`closure`'s `materialize` emits a temp-table `insert` the runner cannot execute.
`tracker/loopmodel/E2-EXAMPLES.md` §G4(a) has the tables and the numbers.
