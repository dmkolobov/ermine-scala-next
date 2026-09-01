# A soundness bug: row constraints the shipped solver accepts and cannot satisfy

Measured 2026-09-01 on branch `scala3-migration`, default rule mode
(`-Dermine.genRules=all`), `-Dermine.useInterface=false`.

Four modules in this directory type-check, load, and export types that **no
instantiation can ever satisfy**. This is not the `nongen` regression recorded
in `core/examples/shouldfail/RESULTS.md`; minting is on and does not help.

| file | verdict | what it is |
|---|---|---|
| `unsound01_keyed_halves.e` | **LOADS** | satisfiable helper, contradictory call site, monomorphic annotation so nothing residualises |
| `unsound02_three_way_shard.e` | **LOADS** | same, split three ways instead of two |
| `unsound03_inferred_headers.e` | **LOADS** | no signature anywhere; the solver infers and prints the unsatisfiable set itself |
| `unsound04_dead_helper.e` | **LOADS** | signature unsatisfiable at every instance, discharged at a call site |
| `witness01_case1_left_empty.e` | rejected | per-label case analysis, case 1 of 4 |
| `witness01_case2_left_key.e` | rejected | case 2 of 4 |
| `witness01_case3_right_key.e` | rejected | case 3 of 4 |
| `witness01_case4_left_all.e` | rejected | case 4 of 4 |
| `witness03_grounded_call.e` | rejected | `unsound03`'s helper, one column group named |
| `control01_same_route_refuted.e` | rejected | same discharge route, a contradiction the solver does see |

Run:

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
cd ~/research/ermine/ermine-scala
ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
  core/examples/incomplete/unsound0{1_keyed_halves,2_three_way_shard,3_inferred_headers,4_dead_helper}.e </dev/null
```

## The query

Vertical sharding: a ledger is too wide, so its columns are divided into groups
and each group is written to its own table with the primary key stamped on, so
the shards can be re-joined later. Stated as a row property:

```
t  <- (l, s)                 -- the columns divide into two groups
lt <- ((|accountId|), l)     -- group l, plus the key, is a legal header
rt <- ((|accountId|), s)     -- group s, plus the key, is a legal header
```

This is satisfiable and useful — `good` in `unsound01_keyed_halves.e` is the
compiler-checked witness — **provided the ledger does not already contain
`accountId`**. If it does, the key is one of the columns being divided, so it
lands in `l` or in `s`, and that half gets `accountId` twice. Forgetting to drop
the key before splitting is the everyday form of this mistake, and catching it
is exactly what row types are for.

`bad` in `unsound01_keyed_halves.e` makes that mistake and compiles.

## Why it is a soundness bug and not a deferral

`bad` carries a monomorphic annotation, `[accountId, regionCode]`, mentioning
none of `l`, `s`, `lt`, `rt`. There is nothing to generalise over, so the solver
has to discharge the whole wanted set at the call site. `:browse` says it did:

```
bad : Relation (|accountId, regionCode|)
```

No constraint context. The set it declared solved is

```
(|accountId, regionCode|) <- (l, s)
lt <- ((|accountId|), l)
rt <- ((|accountId|), s)
```

## Proof of unsatisfiability

Only the label `accountId` matters. It is in `(|accountId, regionCode|)`, which
is `l (+) s`, so it is in `l` or in `s`. `accountId in l` contradicts
`lt <- ((|accountId|), l)`, whose parts must be disjoint; `accountId in s`
contradicts `rt <- ((|accountId|), s)`. No solution.

There are exactly four ground splits of `(|accountId, regionCode|)`, and the
compiler **rejects every one of them**:

| witness | `l` | `s` | observed |
|---|---|---|---|
| `case1_left_empty` | `(\| \|)` | `(\|accountId, regionCode\|)` | `witness01_case1_left_empty.e:23:31: Fields appear twice in row: Incomplete.Witness01A.accountId` |
| `case2_left_key` | `(\|accountId\|)` | `(\|regionCode\|)` | `witness01_case2_left_key.e:23:28: Fields appear twice in row: Incomplete.Witness01B.accountId` |
| `case3_right_key` | `(\|regionCode\|)` | `(\|accountId\|)` | `witness01_case3_right_key.e:28:1: Fields appear twice in row: Set(Incomplete.Witness01C.accountId)` |
| `case4_left_all` | `(\|accountId, regionCode\|)` | `(\| \|)` | `witness01_case4_left_all.e:23:28: Fields appear twice in row: Incomplete.Witness01D.accountId` |

The compiler refutes each case and accepts their disjunction.

## Why the solver misses it

The missing step is elimination: `accountId` is somewhere in `l (+) s`, it is not
in `l`, therefore it is in `s` — contradiction. Ermine documents that rule
(`Disjunction`, `Constraints.scala:1114-1121`) and implements it
(`Constraints.scala:1122`), but **all three of its call sites are commented out**
(`Constraints.scala:843`, `854`, `856`), so the shipped solver never fires it.

Nothing else reaches the contradiction, because the partition
`(|accountId, regionCode|) <- (l, s)` is a dead end for every remaining rule:

- `cancellation` (`Constraints.scala:1017`) needs a **lone variable** remainder
  (`xs.size == 1` / `ys.size == 1`, lines 1029 and 1031). Both remainders here
  are two variables wide.
- `splitConcrete` (`Constraints.scala:816`) declines on `concr.isEmpty`
  (line 817), so it never mints a name for `l (+) s`. This is the crucial
  difference from `core/examples/shouldfail/der06`–`der08`, where the
  two-variable remainder sits beside a concrete field and therefore *does* get
  minted a name — after which `cancellation` applies and the contradiction
  surfaces. Here the split carries no concrete part at all.
- `commonSubexpression` (`Constraints.scala:1089`) declines on `int.size < 2`
  (line 1094). The split shares one variable with `lt`'s partition and one with
  `rt`'s, never two.
- `resolution` (`Constraints.scala:1047`) matches only `RHS(Single(x), _)`.

So the facts "`accountId` is not in `l`" and "`accountId` is not in `s`" live in
the partitions of `lt` and `rt` and are never brought into contact with the
split. `unsound02_three_way_shard.e` widens the remainder to three variables,
which pushes `cancellation` further from firing, and is accepted too.

## The calibration

Two facts rule out the innocent explanations.

1. **"Signature constraints are only assumptions."** They stop being
   assumptions at a call site, which is why `core/examples/shouldfail/dup01`
   and `inf01` need their `use` line. `control01_same_route_refuted.e` is
   `unsound04_dead_helper.e` with the same `use` shape and a contradiction the
   solver can see, and it is rejected:
   `control01_same_route_refuted.e:29:1: Fields appear twice in row: Incomplete.Control01.amount`.
   Same route, opposite verdict.

2. **"The residual is just being deferred."** `bad` and `use` have no residual —
   their printed types are monomorphic with no constraint context. And where a
   residual *is* published (`unsound03_inferred_headers.e`), naming a single
   column group is enough to make the compiler reject it
   (`witness03_grounded_call.e`), so the published type was uninhabited.

## Scope, honestly stated

The gap needs the two halves to stay row variables. Ground either one and the
solver finds the contradiction immediately, which is what the witness files
show. That is not a mitigation: staying polymorphic in the halves is the normal
state of a reusable helper, and `unsound03_inferred_headers.e` reaches it from
ordinary library code with no signature written at all.

Two shapes that were tried and **are** caught, for the record:

- Relation-level `project_Rw (append_Rw (single_Rw accountId) cols) ledger`. The
  `Has` constraint that `project` adds gives the solver a partition of the
  ledger row whose remainder *does* carry a concrete field, `splitConcrete`
  mints a name for it, `cancellation` then transfers `accountId` into the other
  half, and substitution duplicates it. Rejected — with the source relation
  concrete *and* with it abstract.
- Any call site that names a concrete column group for either half.
