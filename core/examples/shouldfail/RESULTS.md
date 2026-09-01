# Should-fail corpus: refutation matrix across rule modes

Measured 2026-09-01 on branch `scala3-migration`.

Command per mode:

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.genRules=<MODE>" bin/ermine core/examples/shouldfail/*.e </dev/null
```

`rejected` = the module failed to load with a row-constraint error. 
`ACCEPTED` = the module type-checked and loaded, i.e. **the refutation was lost**.


## Headline

| mode | rejected | ACCEPTED (soundness regressions) | message changes among rejected |
|---|---|---|---|
| `all` | 40/40 | **0** | -- (baseline) |
| `cut` | 40/40 | **0** | 0 |
| `nongen` | 35/40 | **5** | 0 |

`cut` is a perfect match for `all` on all 40 cases: same verdict, same message.
`nongen` loses 5 refutations. No case changed its message while staying rejected,
so there is no diagnostic-quality regression anywhere in the matrix -- every
difference is an outright lost refutation.


## Per-case matrix

| case | error class | all | cut | nongen |
|---|---|---|---|---|
| `der01_rename_onto_existing_column.e` | 1 DUPLICATED FIELD (derived) | rejected | rejected (same msg) | rejected (same msg) |
| `der02_copy_column_onto_existing.e` | 1 DUPLICATED FIELD (derived) | rejected | rejected (same msg) | rejected (same msg) |
| `der03_row_remainder_readded.e` | 1 DUPLICATED FIELD (derived) | rejected | rejected (same msg) | rejected (same msg) |
| `der04_helper_drop_then_add.e` | 1 DUPLICATED FIELD (derived) | rejected | rejected (same msg) | rejected (same msg) |
| `der05_join_pinned_to_left_header.e` | 3 INCOMPATIBLE INSTANTIATIONS (derived) | rejected | rejected (same msg) | rejected (same msg) |
| `der06_shared_two_var_remainder.e` | 1 DUPLICATED FIELD (derived) | rejected | rejected (same msg) | **ACCEPTED** |
| `der07_shared_three_var_remainder.e` | 1 DUPLICATED FIELD (derived) | rejected | rejected (same msg) | **ACCEPTED** |
| `der08_shared_remainder_relations.e` | 1 DUPLICATED FIELD (derived) | rejected | rejected (same msg) | **ACCEPTED** |
| `dup01_partition_literal.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `dup02_signature_chain.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `dup03_join1_shared_column.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `dup04_joinby_shared_column.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `dup05_row_witness.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `dup06_cons_existing_field.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `dup07_append_overlapping_rows.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `dup08_copy_column_onto_itself.e` | 1 DUPLICATED FIELD | rejected | rejected (same msg) | rejected (same msg) |
| `inc01_project_from_emptied_row.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | rejected (same msg) |
| `inc02_project_from_columnless_relation.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | rejected (same msg) |
| `inc03_project_absent_field.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | rejected (same msg) |
| `inc04_except_absent_field.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | rejected (same msg) |
| `inc05_filter_absent_field.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | rejected (same msg) |
| `inc06_filter_dropped_column.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | rejected (same msg) |
| `inc07_has_helper_missing_column.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | rejected (same msg) |
| `inc08_project_absent_from_join_result.e` | 3 INCOMPATIBLE INSTANTIATIONS | rejected | rejected (same msg) | **ACCEPTED** |
| `inf01_partition_literal.e` | 2 INFINITE ROW | rejected | rejected (same msg) | rejected (same msg) |
| `inf02_substitution_chain.e` | 2 INFINITE ROW | rejected | rejected (same msg) | rejected (same msg) |
| `inf03_union_shrunken.e` | 2 INFINITE ROW | rejected | rejected (same msg) | rejected (same msg) |
| `inf04_except_recursive.e` | 2 INFINITE ROW | rejected | rejected (same msg) | rejected (same msg) |
| `inf05_union_two_fields.e` | 2 INFINITE ROW | rejected | rejected (same msg) | rejected (same msg) |
| `inf06_row_minus.e` | 2 INFINITE ROW | rejected | rejected (same msg) | rejected (same msg) |
| `inf07_record_drop.e` | 2 INFINITE ROW | rejected | rejected (same msg) | rejected (same msg) |
| `mis01_join_operands_irreconcilable.e` | 5 ROW MISMATCH | rejected | rejected (same msg) | rejected (same msg) |
| `mis02_join_result_annotation.e` | 5 ROW MISMATCH | rejected | rejected (same msg) | **ACCEPTED** |
| `mis03_union_mismatched_headers.e` | 5 ROW MISMATCH | rejected | rejected (same msg) | rejected (same msg) |
| `mis04_record_append_annotation.e` | 5 ROW MISMATCH | rejected | rejected (same msg) | rejected (same msg) |
| `sk01_row_append_self.e` | 4 SKOLEM ESCAPE | rejected | rejected (same msg) | rejected (same msg) |
| `sk02_record_append_self.e` | 4 SKOLEM ESCAPE | rejected | rejected (same msg) | rejected (same msg) |
| `sk03_field_copy_append_self.e` | 4 SKOLEM ESCAPE | rejected | rejected (same msg) | rejected (same msg) |
| `sk04_derived_skolem_substitution.e` | 4 SKOLEM ESCAPE | rejected | rejected (same msg) | rejected (same msg) |
| `sk05_derived_skolem_field_copy.e` | 4 SKOLEM ESCAPE | rejected | rejected (same msg) | rejected (same msg) |

## SOUNDNESS REGRESSIONS under `-Dermine.genRules=nongen`

Five programs that the shipped compiler rejects are **accepted** with no rule minting.
Each was re-verified in an isolated JVM (one file per boot), not only in the batch run.

### `der06_shared_two_var_remainder.e`

- error class: 1 DUPLICATED FIELD (derived)
- `all`: rejected -- `core/examples/shouldfail/der06_shared_two_var_remainder.e:64:1: Fields appear twice in row: Set(Shouldfail.Der06.b)`
- `cut`: rejected -- same message
- `nongen`: **ACCEPTED**, module loads

### `der07_shared_three_var_remainder.e`

- error class: 1 DUPLICATED FIELD (derived)
- `all`: rejected -- `core/examples/shouldfail/der07_shared_three_var_remainder.e:42:1: Fields appear twice in row: Set(Shouldfail.Der07.b)`
- `cut`: rejected -- same message
- `nongen`: **ACCEPTED**, module loads

### `der08_shared_remainder_relations.e`

- error class: 1 DUPLICATED FIELD (derived)
- `all`: rejected -- `core/examples/shouldfail/der08_shared_remainder_relations.e:40:1: Fields appear twice in row: Set(Shouldfail.Der08.b)`
- `cut`: rejected -- same message
- `nongen`: **ACCEPTED**, module loads

### `inc08_project_absent_from_join_result.e`

- error class: 3 INCOMPATIBLE INSTANTIATIONS
- `all`: rejected -- `Row types failed to unify:`
- `cut`: rejected -- same message
- `nongen`: **ACCEPTED**, module loads

### `mis02_join_result_annotation.e`

- error class: 5 ROW MISMATCH
- `all`: rejected -- `core/examples/shouldfail/mis02_join_result_annotation.e:42:1: error: failed to unify type (|orderId,`
- `cut`: rejected -- same message
- `nongen`: **ACCEPTED**, module loads


All five share one mechanism: a partition whose remainder is TWO OR MORE row
variables. `cancellation` needs a LONE variable (`xs.size == 1`,
Constraints.scala:1029), so the contradiction only becomes visible after some rule
mints a single fresh name for that remainder. Under `nongen` neither
`commonSubexpression` (Constraints.scala:1104, `GenRules.cseMints`) nor
`splitConcrete` (Constraints.scala:821, `GenRules.splitMints`) will mint, the
remainder is never named, and the row is never driven to a concrete value.


## Caveat on `cut`

`cut` disables ONLY `commonSubexpression`'s minting branch; `splitConcrete` still
mints. On this corpus `cut` is indistinguishable from `all`, which means the corpus
contains no case that `commonSubexpression`'s mint decides on its own -- in every
case here `splitConcrete`'s mint reaches the same contradiction. That is evidence
FOR the cut, but it is not proof the CSE mint is dead: the corpus simply has no
witness separating `cut` from `all`. (The flag is demonstrably live -- `nongen`,
which also sets `cseMints = false`, changes 5 verdicts.)


## Positive controls

`core/examples/shouldfail-controls/*.e` (control01, 04, 05, 06, 07) load cleanly under
all three modes, so no mode rejects a program it should accept.


## Note on message stability

`mis02_join_result_annotation.e` renders the second row as an unordered set, so the
field order inside `(|...|)` varies between runs of the SAME mode -- the authoring run
recorded `(|productName, productId, units, orderId|)`, this run produced
`(|units, productId, orderId, productName|)`. That is pre-existing set-iteration
nondeterminism in the diagnostic, not a rule-mode effect. Message comparison in this
matrix normalises fresh-variable ids (`r^590786`) and timings before diffing; it does
not normalise field order, so `mis02` would have shown a false message-diff had it
stayed rejected under `nongen`. It did not -- it was accepted outright.
