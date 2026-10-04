# Signature check: a literal row on the left of a partition

2026-10-03. Branch `sig-litlhs`, from `widget-preview` 6d3cdde2.

## What changed

`(|K|) <- (p1..pk)` says the written-out row `K` is the disjoint union of the parts. A join
against a literal row leaves one in the body's residual, e.g. `join rows (project {key} rows)`.

| | before | now |
|---|---|---|
| as an obligation | dropped; warning NO VERDICT; signature accepted | decided |
| as a given | dropped; a refutation became NO VERDICT; signature accepted | decided |

The check encodes the shape with a variable of its own: `z <- (|K|)` and `z <- (p1..pk)`. This
is what the solver does for the same shape (`Constraints.PQueue.build`). `z` is chosen by the
check for an obligation and rigid for a given.

## Files

| file | change |
|---|---|
| `core/.../SigEntail.scala` | `encode` emits the two rows; `check` mints `z` and adds an obligation's `z` to the chosen set; `blame` judges a constraint's rows together and, when its two older rules find nothing, names the constraint that mentions the refuted column |
| `core/.../session/Session.scala` | interface key suffix `sigEntail=error` -> `sigEntail=error.2`: interfaces cached under the old check are rebuilt once |
| `tracker/lean/Rowpartition/LitLhs.lean` | the encoding is exact: `wanted_enc_iff`, `given_enc_iff`, `sigEntailsL_iff_encoded` |
| `tracker/tools/sigcheck.py` | the oracle reads the shape as a constant bit per label, not as a variable, so it stays an independent implementation |
| `scalacheck-binding/.../TestSigEntailDiff.scala` | the property that pinned NO VERDICT is replaced by three decisions; a random differential with literal wholes |
| `scalacheck-binding/.../TestSigEntail.scala` | two end-to-end properties |
| `scalacheck-binding/.../TestInterfaceKey.scala` | the new suffix |
| `core/src/test/resources/sigentail/*.tsv` | regenerated from one warn-mode sweep |
| `core/examples/Lang/LiteralRowJoin.e`, `LiteralRowContext.e` | 7 honest top-level signatures, one of them with a signed `let` inside (8 signature sites) |
| `core/examples/shouldfail/sig06` .. `sig10` | 5 dishonest signatures |
| `tracker/corpus-verdicts.expected` | re-recorded, see below |

## Evidence

Measured on this branch unless a row says otherwise.

| what | result |
|---|---|
| Lean | `LitLhs.lean` elaborates; both example modules decided by `decide` |
| random systems with literal wholes vs a reference with no encoder variable | 2,000 per run, 0 disagreements; a fixed-seed run of 40,000 on the prototype (26,707 with a literal whole): 0 disagreements; the reviewer's own 40,000 with the `ds` closure and repeated parts: 0 disagreements |
| the same, with the obligation's `z` made rigid (mutant) | 5 properties fail; 3,710 of 40,000 disagree, all false rejections |
| engine vs oracle on the corpus | 327 signatures: 317 accept, 10 reject, 0 no verdict; they agree on every one |
| corpus before the new examples, old compiler vs new | 168 files, 0 verdict differences, 0 message differences; NO VERDICT lines 3 -> 0 |
| the three stdlib signatures that warned | `Layout/Report/Relation.e` `largers`, `cutoffs`, `small`: accepted |
| check cost over the corpus | at most 207 decision nodes per signature (budget 1,000,000) |
| a 40-column literal row | import 0.11 s (old compiler, warning: 0.14 s); single runs, read off the REPL's own timing line, no log kept |

## The corpus expectations that moved

`tracker/corpus-verdicts.expected` gains 7 modules. 4 existing refusals print a different clause:

| module | was | is |
|---|---|---|
| `shouldfail/dup02`, `inc02`, `inc03`, `inc07` | one clause of the refutation, e.g. "a part contains it but the whole does not" | another clause of the same refutation at the same field and position, e.g. "the whole contains it but no part does" |

This is not the compiler change. It is the two new `Lang/` modules loading earlier in the batch:
with them moved out of the tree the four messages are unchanged (measured). Which clause is
printed depends on the ids the batch has minted so far; `corpus-run.sh`'s header records the
same effect between batch and per-file runs.

## Still open

| item | status |
|---|---|
| two literal column sets on the right of one partition | still NO VERDICT. Reached from source only as a given whose literals overlap, which no call can satisfy |
| a part, or a left-hand side, that is neither a variable nor a literal (`f Int`) | still NO VERDICT. Reached from source on both sides |
| the message prints solver variable ids (`_^586753A`) | ticket ROBUST-1, unchanged |
| the repeated-part rule (`v <- (a, a)` forces `a` empty) | not proved in Lean as an equivalence, for a literal or a variable on the left; covered by the random differential |
| a module that loaded with this warning and is in fact dishonest | now refused. None in the corpus; code outside it has not been swept |
| 2.11 back-port | not on this branch. Ported separately on `sig-litlhs-2.11`, from `backport-2.11` |
