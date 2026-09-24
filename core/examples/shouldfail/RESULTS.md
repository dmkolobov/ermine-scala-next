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
all three modes, so no mode rejects a program it should accept.  `control09_let_signatures.e`
was added 2026-09-11 for error class 7 and loads cleanly too (it is not a row-rule case, so
it was measured under the defaults only).


## Note on message stability

`mis02_join_result_annotation.e` renders the second row as an unordered set, so the
field order inside `(|...|)` varies between runs of the SAME mode -- the authoring run
recorded `(|productName, productId, units, orderId|)`, this run produced
`(|units, productId, orderId, productName|)`. That is pre-existing set-iteration
nondeterminism in the diagnostic, not a rule-mode effect. Message comparison in this
matrix normalises fresh-variable ids (`r^590786`) and timings before diffing; it does
not normalise field order, so `mis02` would have shown a false message-diff had it
stayed rejected under `nongen`. It did not -- it was accepted outright.


## 2026-09-02: messages under today's defaults (`labelCheckEarly` on, call-site blame)

The per-file header comments above each `.e` record the message observed on 2026-09-01;
this table supersedes them. Verdicts are unchanged (40/40 rejected; the whole 66-file
corpus stays 23 LOADED / 43 REJECTED). 32 of the 40 messages changed: 26 are now
raised by the per-concrete-label check running BEFORE saturation (`GenRules.labelCheckEarly`,
default on since 2026-09-02) and name the field and the reason; the other 6
keep their text but move to the call site or out of the stdlib, because constraints are
now located at the occurrence that instantiated them and `Term.sub` keeps occurrence
positions (`tracker/TICKET-editor-and-solver-followups.md` §1). No message points into the
stdlib any more except `sk03`/`sk05`'s pre-existing "Cannot unify skolem variable" at
`Field.e:22:24`, which is unchanged and not a row-constraint message. Fresh-name counters
are shown as `^N`.

Reproduce: `tracker/tools/corpus-run.sh <base>` on the previous build,
`tracker/tools/corpus-run.sh <new>` on this one, `tracker/tools/corpus-verdicts.py <base> <new>`.

| case | before (2026-09-01 defaults) | after (2026-09-02 defaults) |
|---|---|---|
| `der01_rename_onto_existing_column.e` | `der01_rename_onto_existing_column.e:41:7: Fields appear twice in row: Set(Shouldfail.Der01.b)` | `der01_rename_onto_existing_column.e:41:7: Row partitions are unsatisfiable at field 'Shouldfail.Der01.b': two parts of one partition both contain it` |
| `der02_copy_column_onto_existing.e` | `der02_copy_column_onto_existing.e:39:7: Fields appear twice in row: Set(Shouldfail.Der02.b)` | `der02_copy_column_onto_existing.e:39:7: Row partitions are unsatisfiable at field 'Shouldfail.Der02.b': the whole contains it but no part does` |
| `der03_row_remainder_readded.e` | `<stdlib>/Relation/Row.e:32:34: Fields appear twice in row: Shouldfail.Der03.b` | `der03_row_remainder_readded.e:43:7: Fields appear twice in row: Shouldfail.Der03.b` |
| `der04_helper_drop_then_add.e` | `der04_helper_drop_then_add.e:38:1: Fields appear twice in row: Set(Shouldfail.Der04.b)` | `der04_helper_drop_then_add.e:40:7: Row partitions are unsatisfiable at field 'Shouldfail.Der04.b': the whole contains it but no part does` |
| `der05_join_pinned_to_left_header.e` | `der05_join_pinned_to_left_header.e:53:1: R2` | `der05_join_pinned_to_left_header.e:55:7: Row partitions are unsatisfiable at field 'Shouldfail.Der05.c': the whole contains it but no part does` |
| `der06_shared_two_var_remainder.e` | `der06_shared_two_var_remainder.e:64:1: Fields appear twice in row: Set(Shouldfail.Der06.b)` | `der06_shared_two_var_remainder.e:66:7: Row partitions are unsatisfiable at field 'Shouldfail.Der06.b': the whole contains it but no part does` |
| `der07_shared_three_var_remainder.e` | `der07_shared_three_var_remainder.e:42:1: Fields appear twice in row: Set(Shouldfail.Der07.b)` | `der07_shared_three_var_remainder.e:44:7: Row partitions are unsatisfiable at field 'Shouldfail.Der07.b': the whole contains it but no part does` |
| `der08_shared_remainder_relations.e` | `der08_shared_remainder_relations.e:40:1: Fields appear twice in row: Set(Shouldfail.Der08.b)` | `der08_shared_remainder_relations.e:42:7: Row partitions are unsatisfiable at field 'Shouldfail.Der08.b': the whole contains it but no part does` |
| `dup01_partition_literal.e` | `dup01_partition_literal.e:23:1: Fields appear twice in row: Shouldfail.Dup01.a` | `dup01_partition_literal.e:25:7: Fields appear twice in row: Shouldfail.Dup01.a` |
| `dup02_signature_chain.e` | `dup02_signature_chain.e:24:1: Fields appear twice in row: Set(Shouldfail.Dup02.a)` | `dup02_signature_chain.e:26:7: Row partitions are unsatisfiable at field 'Shouldfail.Dup02.a': a part contains it but the whole does not` |
| `dup03_join1_shared_column.e` | `dup03_join1_shared_column.e:30:7: Fields appear twice in row: Set(Shouldfail.Dup03.x)` | `dup03_join1_shared_column.e:30:7: Row partitions are unsatisfiable at field 'Shouldfail.Dup03.x': a part contains it but the whole does not` |
| `dup04_joinby_shared_column.e` | `dup04_joinby_shared_column.e:30:7: Fields appear twice in row: Set(Shouldfail.Dup04.x)` | `dup04_joinby_shared_column.e:30:7: Row partitions are unsatisfiable at field 'Shouldfail.Dup04.x': the whole contains it but no part does` |
| `dup05_row_witness.e` | `<stdlib>/Relation/Row.e:32:34: Fields appear twice in row: Shouldfail.Dup05.a` | `dup05_row_witness.e:23:5: Fields appear twice in row: Shouldfail.Dup05.a` |
| `dup06_cons_existing_field.e` | no position: bare `Fields appear twice in row: ...` | `dup06_cons_existing_field.e:22:7: Fields appear twice in row: Shouldfail.Dup06.a` |
| `dup07_append_overlapping_rows.e` | `<stdlib>/Relation/Row.e:29:36: Fields appear twice in row: Shouldfail.Dup07.b` | `dup07_append_overlapping_rows.e:23:5: Fields appear twice in row: Shouldfail.Dup07.b` |
| `dup08_copy_column_onto_itself.e` | `<stdlib>/Relation.e:251:29: Fields appear twice in row: Shouldfail.Dup08.a` | `dup08_copy_column_onto_itself.e:24:7: Fields appear twice in row: Shouldfail.Dup08.a` |
| `inc01_project_from_emptied_row.e` | `inc01_project_from_emptied_row.e:31:7: Incompatible instantiations of '579503'` | `inc01_project_from_emptied_row.e:31:7: Row partitions are unsatisfiable at field 'ShouldFail.Inc01.amount': a part contains it but the whole does not` |
| `inc02_project_from_columnless_relation.e` | `inc02_project_from_columnless_relation.e:29:7: Incompatible instantiations of '579369'` | `inc02_project_from_columnless_relation.e:29:7: Row partitions are unsatisfiable at field 'ShouldFail.Inc02.amount': a part contains it but the whole does not` |
| `inc03_project_absent_field.e` | `inc03_project_absent_field.e:34:7: R2` | `inc03_project_absent_field.e:34:7: Row partitions are unsatisfiable at field 'ShouldFail.Inc03.shipDate': a part contains it but the whole does not` |
| `inc04_except_absent_field.e` | `inc04_except_absent_field.e:34:7: R2` | `inc04_except_absent_field.e:34:7: Row partitions are unsatisfiable at field 'ShouldFail.Inc04.shipDate': the whole contains it but no part does` |
| `inc05_filter_absent_field.e` | `inc05_filter_absent_field.e:35:7: R2` | `inc05_filter_absent_field.e:35:7: Row partitions are unsatisfiable at field 'ShouldFail.Inc05.region': a part contains it but the whole does not` |
| `inc06_filter_dropped_column.e` | `inc06_filter_dropped_column.e:36:7: R2` | `inc06_filter_dropped_column.e:36:7: Row partitions are unsatisfiable at field 'ShouldFail.Inc06.amount': the whole contains it but no part does` |
| `inc07_has_helper_missing_column.e` | `inc07_has_helper_missing_column.e:35:1: R2` | `inc07_has_helper_missing_column.e:37:7: Row partitions are unsatisfiable at field 'ShouldFail.Inc07.customerId': the whole contains it but no part does` |
| `inc08_project_absent_from_join_result.e` | `inc08_project_absent_from_join_result.e:48:12: R2` | `inc08_project_absent_from_join_result.e:48:12: Row partitions are unsatisfiable at field 'ShouldFail.Inc08.regionName': the whole contains it but no part does` |
| `inf01_partition_literal.e` | `inf01_partition_literal.e:24:1: Infinite row partition for 'r^N'` | `inf01_partition_literal.e:26:7: Row partitions are unsatisfiable at field 'Shouldfail.Inf01.a': two parts of one partition both contain it` |
| `inf02_substitution_chain.e` | `inf02_substitution_chain.e:23:1: Infinite row partition for 's^N'` | `inf02_substitution_chain.e:25:7: Row partitions are unsatisfiable at field 'Shouldfail.Inf02.b': a part contains it but the whole does not` |
| `inf03_union_shrunken.e` | `inf03_union_shrunken.e:1:1: Infinite row partition for 'r2^N'` | `inf03_union_shrunken.e:23:18: Row partitions are unsatisfiable at field 'Shouldfail.Inf03.a': two parts of one partition both contain it` |
| `inf04_except_recursive.e` | `inf04_except_recursive.e:20:1: Infinite row partition for 'r^N'` | `inf04_except_recursive.e:22:7: Row partitions are unsatisfiable at field 'Shouldfail.Inf04.a': two parts of one partition both contain it` |
| `inf05_union_two_fields.e` | `inf05_union_two_fields.e:1:1: Infinite row partition for 'r2^N'` | `inf05_union_two_fields.e:23:18: Row partitions are unsatisfiable at field 'Shouldfail.Inf05.a': a part contains it but the whole does not` |
| `inf06_row_minus.e` | `inf06_row_minus.e:1:1: Infinite row partition for 's^N'` | `inf06_row_minus.e:26:17: Row partitions are unsatisfiable at field 'Shouldfail.Inf06.a': two parts of one partition both contain it` |
| `inf07_record_drop.e` | `inf07_record_drop.e:1:1: Infinite row partition for 't^N'` | `inf07_record_drop.e:25:21: Row partitions are unsatisfiable at field 'Shouldfail.Inf07.a': two parts of one partition both contain it` |
| `mis01_join_operands_irreconcilable.e` | `mis01_join_operands_irreconcilable.e:38:14: R2` | `mis01_join_operands_irreconcilable.e:38:14: Row partitions are unsatisfiable at field 'ShouldFail.Mis01.city': a part contains it but the whole does not` |

## class 6 SIGNATURE CONTEXT TOO WEAK -- REJECTED since S3 (2026-09-11)

Five modules that MUST NOT load, and since stage S3 of `tracker/SIG-ENTAIL-PLAN.md` none of
them does.  They were pinned on 2026-09-10 as ACCEPTED: a declared signature's row
constraints were never checked against the body's obligations (`Subst.subsumeType` discarded
the skolem-mentioning wanteds, :535-536 and :553 at `a15a97e`), so each module loaded and
its `crash` evaluated in the REPL to `<error: key not found: health>` -- sig04 to a record
carrying that error in a field its printed TYPE does not have, sig05 the same hole through
an expression annotation.  S3 implements the S2 decision procedure
(`tracker/loopmodel/SIG-2-DESIGN.md`) inside `subsumeType` for user signatures only, with
`-Dermine.sigEntail=error` as the DEFAULT; each module is now refused with a two-location
diagnostic whose primary position is the term that generated the obligation and whose
secondary ("declared at") is the DECLARED TYPE on the signature line -- not the equation's
head, which is where the first implementation put it and which collapses onto the primary on a
one-line body (S3 review M1).  Each header carries its own message verbatim; the witness
sentence carries no ids and no positions at all, so it is reproducible run to run (review M2).

sig03 is the let-bound twin.  Until LET-1 (`cff6c42`) it was refused at the CALL by
ordinary inference, because the renamer DROPPED let-bound signatures; with LET-1 merged the
signature reaches `typeCheckExplicitBinding` and S3 rejects it at the signature, which is
where its header always said the blame belonged.

MEASURED WITH THE STDLIB CORRECTIONS APPLIED (branch `sig-fixes`, the seven shipped
signatures S1 found not entailed: `unify1`, `partialLookup`, `cons_Bracket`,
`Keyed.softRelation`, `Keyed.keyValueTabular`, `Relation.cutoffs`, `Relation.others`).
Without them the stdlib boot is refused first under `error` -- `DrilldownList.e:20:98` and
`Relation.e:114:3` -- and no corpus module reaches its own diagnostic at all.  A sweep of
the uncorrected tree under `error` therefore says nothing about these five; measure them
with the corrections, or under `-Dermine.sigEntail=warn`, which reports the same
diagnostics and accepts.

| file | class | `all` | `cut` | `nongen` |
|---|---|---|---|---|
| `sig01_unconstrained_signature.e` | 6 SIGNATURE CONTEXT TOO WEAK | **rejected** 70:17 (declared at 69:13) | **rejected** | **rejected** |
| `sig02_wrong_label_signature.e` | 6 SIGNATURE CONTEXT TOO WEAK | **rejected** 45:18 (declared at 44:14) | **rejected** | **rejected** |
| `sig03_let_bound_signature.e` | 6 SIGNATURE CONTEXT TOO WEAK | **rejected** 70:25 (declared at 69:21, `sig local`) | **rejected** | **rejected** |
| `sig04_unconstrained_modify.e` | 6 SIGNATURE CONTEXT TOO WEAK | **rejected** 48:8 (declared at 47:8) | **rejected** | **rejected** |
| `sig05_annotated_lambda.e` | 6 SIGNATURE CONTEXT TOO WEAK (annotation site) | **rejected** 48:19 (declared at 48:12, `ann <annot>`) | **rejected** | **rejected** |

All five report `the signature does not entail this row constraint`, at the label class
`health` (the one shape the plan's original refutation trick also decided), with the witness
"every row empty".  The three rule-mode columns are MEASURED under
`-Dermine.sigEntail=warn` (which reports the same diagnostic and accepts, so the five
modules can be measured in one JVM against an uncorrected stdlib): all three modes produce
byte-identical diagnostics at the positions above, which is expected -- the check reads the
signature's own constraints and the body's residual, and `genRules` changes neither.
`sig05` reports TWICE under `warn`, once per spelling (48:19 `crash`, 49:19 `crash2`);
under `error` the module dies at the first.

Controls, both of which MUST LOAD and do: `shouldfail-controls/control08_sig_declared.e`
(the same bodies with honest signatures, in four spellings) and
`shouldfail-controls/control09_let_signatures.e`.  Under `-Dermine.sigEntail=off` all five
modules load again exactly as they did at S0 -- the escape hatch, pinned in
`TestSigEntail`'s flag group.  Command as at the top of this file, plus
`-Dermine.genRules=<MODE>`; the REPL evidence needs `:load` of the module followed by
`crash`.

## 2026-09-11: error class 7, LET SIGNATURE (LET-1)

Five new negatives pin a REGRESSION the corpus could not see: between 2026-08-31
(`faa5769`, the commit that made the split pipeline the only module path) and 2026-09-11,
the renamer's lowering of a `let` block DISCARDED every signature in it, so a `let`-bound
signature reached neither the type checker nor the editor.  **At `a15a97e` every one of
these five modules LOADED** -- that is the regression, and it is why they exist.  A `where`
on a top-level equation was never affected (it goes through the module path's own signature
pairing), which is why `let02`/`let03` are here: the two NESTED shapes went through the
`let` path and were dropped too.

Fix and full account: `tracker/loopmodel/LET-1-FIX.md`.  Control:
`core/examples/shouldfail-controls/control09_let_signatures.e` (the same five shapes with
signatures their bodies satisfy) -- it MUST LOAD, and does.

Measured 2026-09-11 on branch `let-signatures`, per file, interfaces off:

```
ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine core/examples/shouldfail/let0N_*.e </dev/null
```

| case | error class | verdict | message (verbatim, `all`) | at a15a97e |
|---|---|---|---|---|
| `let01_let_signature_monomorphic.e` | 7 LET SIGNATURE | rejected | `let01_let_signature_monomorphic.e:34:6: error: failed to unify type Int with type String` | **LOADED** |
| `let02_where_in_let.e` | 7 LET SIGNATURE | rejected | `let02_where_in_let.e:25:6: error: failed to unify type Int with type String` | **LOADED** |
| `let03_let_in_where.e` | 7 LET SIGNATURE | rejected | `let03_let_in_where.e:19:17: error: failed to unify type Int with type String` | **LOADED** |
| `let04_let_signature_too_general.e` | 7 LET SIGNATURE | rejected | `let04_let_signature_too_general.e:23:7: error: failed to unify type !a with type Int` | **LOADED** |
| `let05_let_signature_no_definition.e` | 7 LET SIGNATURE | rejected | `let05_let_signature_no_definition.e:27:7: missing definition` | **LOADED** |

These five are ordinary unification and lowering refusals, not row-rule refusals, so the
`all` / `cut` / `nongen` matrix above does not apply to them: no row rule runs, and the
message is the same under every mode.
