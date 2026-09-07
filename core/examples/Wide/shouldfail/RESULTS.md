# `Wide/shouldfail` — the three ways to misuse a wide-table helper

Measured 2026-09-07 on branch `scala3-migration` at the adopted row-solver
defaults (`-Dermine.rowSound` on, `-Dermine.dequeuePolicy=smallcanon`,
`-Dermine.solveBudget=20000`).

Command per case:

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false" \
  bin/ermine core/examples/Wide/Helpers.e core/examples/Wide/shouldfail/<case>.e </dev/null
```

`Wide/Helpers.e` goes first: every case imports it, and the CLI cannot resolve
the module by name on its own.

## Verdicts

| case | what it does wrong | verdict | diagnostic (verbatim) |
|---|---|---|---|
| `pivot01_key_column_is_also_value.e` | pivots `period` keyed on `period` | rejected | `Fields appear twice in row: Wide.Shouldfail.Pivot01.period` |
| `win01_window_on_absent_column.e` | partitions by a column the relation has not got | rejected | `Row partitions are unsatisfiable at field 'Wide.Shouldfail.Win01.divisionName': the whole contains it but no part does` |
| `win02_running_total_ordered_by_measure.e` | running total of `amount` ordered by `amount` | rejected | `Fields appear twice in row: Wide.Shouldfail.Win02.amount` |

All three fail in well under a second each, on top of the shared boot.

## Why these three

They are the three distinct ways a wide-table helper can be misapplied, and
each one is caught by a different constraint in the helper's signature.

**`pivot01`** — `pivotBy`'s `r <- (k, v, i)` says the key columns, the value
columns and the identity columns partition the input row *disjointly*. A pivot
whose key is its own value asks for `r <- (period, period, i)`. The
duplicate-field detector refuses it. This is the constraint that makes a pivot
mean anything: without it, the transpose would have no well-defined identity.

**`win01`** — `rankWithin`'s `w <- (k, s)` and `r <- (w, o)` say the window's
columns are *inside* the relation. Partitioning by a name that is not there is
the ordinary typo — a column renamed upstream, a window left pointing at the old
name — and it is exactly the failure a reporting language has to catch, because
the SQL it would otherwise emit is not an error: it silently ranks the whole
table as one partition and the report is quietly wrong.

**`win02`** — `Relation.Windowed.windowed`'s `t <- (r, s)` unions the row the
window *function* reads with the row the *window* reads. A running total of
`amount` ordered by `amount` puts `amount` in both, and the union is disjoint.
The mistake is natural, because "running total of amount, in amount order" reads
like a sentence; the fix is to order by a date or a sequence, as
`Wide.TrialBalance` does.

## A note on the `win01` wording

The message reads *"the whole contains it but no part does"*, which describes the
opposite of the situation: here a **part** carries `divisionName` and the whole
does not.

Loading the same module in a BATCH rather than on its own prints the other clause:

```
per file:  … 'Wide.Shouldfail.Win01.divisionName': the whole contains it but no part does
in batch:  … 'Wide.Shouldfail.Win01.divisionName': a part contains it but the whole does not
```

so the string is not a description of the clash at all. It is the **reason
recorded for a unit-propagation step** (`Constraints.scala:2451` / `:2670`,
`setVar`/`assign`), and the refutation reports the label together with whichever
reason was attached to it last — which depends on what else the session holds.
Six pre-existing `core/examples/shouldfail/` modules do the same thing; this is
the seventh, and the first where both clauses can be checked against the program.

The verdict is right and the field named is the right field, in both modes.
Recorded here because a reader of the diagnostic will read it as a description
and be misdirected. Section 7.5 of `tracker/loopmodel/E1-EXAMPLES.md` has the
detail.
