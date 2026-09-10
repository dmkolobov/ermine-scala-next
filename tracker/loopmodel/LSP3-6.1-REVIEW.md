# LSP Stage 3, item 6.1 — independent review

Reviewer report, 2026-09-10 (Opus).  Brief `tracker/loopmodel/briefs/brief-LSP3-6.1-review.md`; implementer report
`tracker/loopmodel/LSP3-6.1-DIAGNOSTICS.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.1.  Branch
`scala3-migration`, HEAD `1c70a62` (core sources identical to `f09e086`) plus the uncommitted deliverables.
No commits, no edits outside this file and
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.1/`.
`tracker/lean/` and `tracker/LSP-ROADMAP.md` untouched; the working tree is byte-identical to how I found it
(`git diff` sha256 `7b90b721…` before and after this review); 0 `.ei` anywhere outside `tracker/g1-*`.

**VERDICT: FIX-THEN-ADVANCE.**  The batch-frozen invariant holds — I re-ran the whole tier and every number
reproduces, the REPL goldens never moved and no shipped code outside the editor path changed.  (a)'s ACCEPTED
survived my attempt to refute it.  (b) and (c) do what they claim.  Three cheap fixes are owed before the tick
(F1–F3 below, all documentation/fixture, no behaviour change); four further items are for the orchestrator.

---

## Gate table — implementer vs. me (one re-run each, one JVM at a time)

| gate | implementer | reviewer (this run) |
| --- | --- | --- |
| `sbt core/compile core/copyResources` | green | green (already built; no-op, 4 s) |
| `sbt 'core/testOnly *TestLoopTrace'` | 3/3; 720 solves / 720 segments / 720 agree, hashdiff 0, eqdiff 0 | **identical**: 3/3; `segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0` |
| `sbt 'core/testOnly *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestStage1Pins *TestReplDifferential'` | 69/69 (was 66; TestTolerantCheck 14→17) | **69/69, 0 failed** in 208 s; the three new properties pass, `TestStage1Pins`'s do-anchor pin passes unedited |
| `tracker/tools/corpus-run.sh --batch <out>` | 85 / 69 / 0 over 154 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** |
| `tracker/tools/repl-smoke.sh` | 8 groups / 66 checks | **8 groups / 66 checks**, all PASS (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5) |
| `tracker/repl-tests/*.expected` | byte-identical | **`git status tracker/repl-tests` clean** after the run |
| `tracker/tools/lsp-smoke.sh` | PASS, 205 checks (185 + 20) | **PASS, 205 checks**; the 20 new ones are BadImport.e ×11, BadSib.e ×3, BadReq.e ×3, BadHeader.e ×3 (list below) |
| `bin/ermine-lsp` boot | 129 modules | **129 modules in 11.7 s** (lsp-smoke log and my own probe both) |
| `.ei` hygiene | 0 | **0** outside `tracker/g1-*` |
| Report.e round trip, `perf-bench.sh editor -k 5` | AFTER 1.808 → 1.723, BEFORE 1.721 | **AFTER 1.629 s / BEFORE 1.667 s** — see below |

The 20 new lsp-smoke checks by fixture: `BadImport.e` — one diagnostic per failing import; missing module
squiggles its name; missing module names the module; unloadable sibling squiggles its name; sibling keeps the
loader's `file:line`; suppresses the undefined-term cascade; suppresses the unchecked cascade; healthy
definition still navigates; healthy definition still hovers; keeps only the missing-module diagnostic after the
sibling is fixed; the remaining one is the missing module.  `BadSib.e` — reports its own syntax error; clean once
fixed in the buffer; on disk untouched by the buffer edits.  `BadReq.e` — one diagnostic; squiggles the name in
the import list, not the header; says what is missing.  `BadHeader.e` — one diagnostic; positioned in this file,
not at 0:0; says what the header wanted.

### Perf — the interleaved pair I ran myself

`perf-bench.sh editor -k 5` on `Layout/Report.e`.  BEFORE is a scratch build of `f09e086`: the tree copied to
`<scratch>/before-tree` with the three shipped files replaced by their `f09e086` content (`git show`), recompiled
there (6 s, incremental) and its `tracker/repl-classpath.txt` repointed — the repo itself was never modified.

| run | median | read | typecheck | residual | reused | spread | load before/after |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AFTER (the tree) | **1.629 s** | 0.820 | 0.500 | 0.014 | 97/154 | 1.617–1.653 | 1.04 / 1.39 |
| BEFORE (`f09e086` build) | **1.667 s** | 0.825 | 0.515 | 0.024 | 97/154 | 1.632–1.693 | 0.60 / 0.81 |

AFTER is 38 ms **faster** than BEFORE — inside the ~50 ms floor and in the wrong direction for a regression, with
identical read time and identical reuse counters.  **The item does not move the editor round trip**, which is
what the code says it should be: a file whose imports all load takes the same single `Session.loadModules` call,
and the only new work on that path is building three small maps over the header's imports and mapping an empty
list.  The implementer's first AFTER (1.808) was indeed machine drift; their conclusion stands on my numbers too.

---

## 1. Batch frozen? — CONFIRMED

`git diff` touches five files; the three under `core/src/main` are `lsp/Resident.scala`, `lsp/Diagnostics.scala`
and `session/TolerantCheck.scala`.  `grep -rn TolerantCheck core/src scalacheck-binding` finds callers only in
`lsp/Resident.scala`, `lsp/Documents.scala` (the `Cache` type), and the two test suites — `Session.scala`'s only
mention is a comment.  `Session.scala`, `NewPipeline.scala`, `Subst.scala`, `Lower.scala`, `Type.scala`: not in
the diff.  `Diagnostics.check` is `run`'s old body moved verbatim (I diffed the two hunks line by line — the
`try`/`catch` arms, the index rebuild and the note mapping are unchanged); `run` keeps the timing line and the
publish.  `Note` gained `dependsOnBroken: Boolean = false` in last position with a default: `grep` finds no
positional pattern match on `Note` anywhere (the only `case … Note(` hits are constructor calls), the FFI path
(`ForeignNote` → `Note(n.report, n.severity, None, Some(n.span))`, TolerantCheck:183) is unaffected, and a
foreign note is neither `spelling` nor `dependsOnBroken` so the new filter cannot eat it.  Evidence from the
gates: REPL goldens byte-identical, `TestReplDifferential` green, `TestTolerantRead`'s agreement sweep (253 files
— 161 stdlib + 92 examples, its floor is the standing 180) green, corpus verdicts unchanged at 85/69/0.

## 2. (a) the do-anchor acceptance — ACCEPTED CONFIRMED (refutation attempted and failed)

Re-derived, not taken on trust.  `Subst.inferType` (`:876`) sets `implicit val tml: Located = e`; the `App` case
(`:914`) infers `tf`, calls `matchFunType`, then `val tx = inferType(gp, x)` — the continuation lambda is
inferred **on its own** — and only then `subsumeType(substType(i), tx)`.  `subsumeType` (`:527`) → `unifyType`
(`:270`) both die at `tml`, which is the application.  `Lam` (`:930`) binds its pattern through
`inferPatternType`, i.e. at fresh metas, never at an expected type.  `typeCheck` (`:633`), `typeCheckExplicitBinding`
(`:647`) and `typeCheckPattern` (`:972`) are each `infer…` + `subsumeType`: there is no checking mode in this
checker.  Every line reference in the report's ticket draft is accurate.

Reproduced both positions through the real LSP (my own scripted client, one server, `<scratch>/probe.out`):
`DoAnchor.e` → `6:23` (LSP 0-based) = `7:24` = the bind's rhs `liftDo`, message `failed to unify type Int with
type Bool`, no secondary location — the same statement line the batch pin asserts, which passed unedited in my
run.  `DoInner.e` (`unit (1 && True)`) → `7:26` = `8:27`, the offending subterm, so the desugar loses no
positions.  `LamApp.e` (`g (w -> w && True)`) → `7:4` = `8:5`, the head `g`: not do-specific.

**My refutation attempt.**  The brief's route — after the App-level clash, re-infer `mf`'s body with the argument
type bound and report the first inner `Located` that fails — is implementable *without touching Subst*: `inferType`,
`matchFunType`, `inferPatternType`, `subTerm` and `zipTerms` are all public, so an editor-only "explain" pass could
do, on catching a component's `Death`: parse the position out of the rendered report; find the App at that `Loc`
whose argument is a syntactic `Lam`; in a fresh `SubstEnv`, infer the function, `matchFunType` for the expected
domain `i`, unify the lambda's pattern type with `i` instead of a fresh meta, infer the body, and take the
position of whatever dies.  That much I confirm — so the report's sentence "the editor has no more information
than the batch path does" is **too strong** and should be softened (finding R6).  But it does not refute the
acceptance, for three reasons I checked rather than assumed: (i) binding the pattern at the expected domain *is*
the checking-mode `Lam` rule, written a second time outside the checker — the brief's own escape hatch ("does not
amount to bidirectional checking") is not met, and a second engine that can disagree with the compiler is exactly
what 5.4 was built to avoid; (ii) the pass needs the component's `Gamma` as it stood at the failure, which means
re-running `inferImplicitBindingTypes` for the SCC (TolerantCheck already owns that, but the plumbing is real
work); (iii) the App→`Loc` lookup is ambiguous by construction: `Lower`'s `SDo` mints `App(App(Var(bind at
mv.loc), mv), mf)` and both Apps carry `mv.loc`, so "the App at that position" has to be disambiguated by shape.
With fixtures and pins that is 1–2 days, not under a day, and it buys a position that can be wrong.  **ACCEPTED
stands.**  The one non-bidirectional alternative I can see — recording, per meta, the `Loc` that bound it, and
re-blaming the first mismatching bound meta — needs `Subst` bookkeeping, i.e. shared code under frozen batch
semantics, so it is the same ticket, not a cheaper one.  The ticket draft is accurate; it should also record
these two alternatives so the next owner does not re-derive them (R6).

## 3. (b) the design — probed on all six cases

Fixtures for these are under `<scratch>/review-6.1/fx/`; all results from one server run (`probe.out`,
`probe-opcascade.out`, `probe-typecascade.out`).

- **(i) a failed import plus an unrelated genuine typo.**  `Typo.e` (`import NoSuchModule` + `x =
  totallyUndefinedName`) publishes exactly ONE diagnostic — the import failure.  The real error IS hidden, as
  designed.  I accept the trade (the import is the error to act on first, and the same rule already governs
  broken statements since 5.4), and it is stated in the report and in the code comment — but NOT in `docs/lsp.md`,
  which documents the diagnostics contract in user terms including the "unchecked" note this rule now withholds
  (R5).
- **(ii) the narrowing was available and not used.**  `Explicit.e` (`import NoSuchModule using { alpha }` plus an
  unrelated `y = totallyUndefinedName`) also suppresses the unrelated name: the filter is unconditional on
  `failedImports.nonEmpty`.  The report's justification — an open `import M` has no list, so the narrow rule
  degenerates — is true and is the right call for the general case, but it does not address the hybrid (narrow
  when EVERY failed import carries an explicit list, wholesale otherwise), which is ~10 lines.  Not worth
  implementing now; worth saying that it was considered and declined (R3).
- **(iii) two failed imports.**  `TwoBad.e` → two Errors, `2:7-2:16` and `3:7-3:16` — exactly the module-name
  spans (`NoSuchOne`, `NoSuchTwo`, 9 characters each), each on its own line, in source order.  Exact-range check
  passes.  `BadImport.e` likewise: `2:7-2:19` (`NoSuchModule`, 12 chars) and `3:7-3:13` (`BadSib`, 6 chars).
  One caveat: when a token follows the module name the span runs to it, so `Explicit.e` squiggles `2:7-2:20` —
  one character wider than the name (R7, cosmetic, the project's standing span convention).
- **(iv) fix the sibling through didChange.**  Confirmed with NO save anywhere and without the smoke's
  `didSave` shortcut: open `ImpSib.e` (one import-failure diagnostic naming `SibBroken.e:5:8`), open
  `SibBroken.e` (its own syntax error at `4:7`), `didChange` the sibling to the fixed text (sibling clean), then
  `didChange` the importer alone → **0 diagnostics**, and the sibling's file on disk still contains `oops = = 3`.
  Note for the record: the importer is only re-checked when the client touches it — the server does not re-check
  dependents of an edited buffer.  That is the documented Stage-3 staleness rule, not a defect of this item.
- **(v) self and cyclic imports.**  No hang, no crash, and better than before.  `CycA.e`/`CycB.e` → `import CycB
  failed: error: circular dependency …` on the import line.  `Selfie.e` (`module Selfie` importing `Selfie`) →
  the same, on its import line.  `SelfBad.e` (self-import plus a syntax error) → TWO diagnostics: its own syntax
  error at `6:6-6:7` AND the import failure.  Each of these was a 0:0 diagnostic before the item.
- **(vi) the fast path.**  Code: `if (missing.isEmpty) Nil else try { Session.loadModules(missing); Nil } catch
  {…}` — one batch call, the retry loop reachable only from the catch.  Log: checking `Clean.e` (imports
  `Prelude`, resident) emits no `session: Loading` line at all; `ImpSib.e` emits `Loading SibBroken` twice (the
  batch attempt and the retry — a broken sibling is parsed twice, failure path only, R9).  Measurement: the perf
  pair above.  Confirmed.
- **`BadHeader.e`**: `0:17-0:17`, message `BadHeader.e:1:18: expected '.', where, or whitespace` — the parser's
  own position (`wehre`), in this file, not 0:0.  My BEFORE build gives the identical range, so this half was
  already sound and nothing regressed; but the range is ZERO-WIDTH, where the roadmap's (b) asked for "the
  header's extent" (R8).
- **`BadReq.e`**: `2:20-2:31`, message exactly `Module 'Bool' does not export term 'nosuchname'.` — the name in
  the import list (plus the trailing space, per R7), not the header.  On my BEFORE build the same file publishes
  `0:0-0:0` with the header-rendered report, so this fix is real and measured.

**The residual the rule does NOT cover (R2).**  The rule is keyed on the two note FLAGS, which exist only for
term names.  A name the failed module would have provided still cascades if it is an OPERATOR or a TYPE, because
those refusals come out of the read as structured diagnostics, not as flagged notes:

```
OpCascade.e:  import Prelude / import NoSuchModule / x = 1 <?> 2 / y = 3 <?> 4 / z = missingName 5
  -> 7 diagnostics: the import failure, and THREE per operator use
     ("unknown operator <?>", "ill-formed expression", "error node") x2 ;  `missingName` correctly silent
TypeCascade.e:  import NoSuchModule / f : Widget -> Widget …
  -> the import failure PLUS "error: undefined type" at 4:4
```

Three unactionable diagnostics per use is precisely the flood the rule was written to stop, and the report's
argument for wholesale suppression ("dozens of notes, none of them actionable, burying the import failure") is
weakened by its surviving on the operator path.  Not a blocker — the import failure is still published and still
first to act on, and "keep the syntax diagnostics" is a defensible line — but it must be disclosed rather than
left for a user to discover.

Other things I checked and found sound: the suppression cannot eat a type error (`MixErr.e` — a failed import
plus `n : Int / n = "no"` publishes BOTH, at `2:7-2:19` and at the definition), cannot eat a syntax diagnostic
(`SelfBad.e`), and cannot eat an FFI note (no flag set on those); a failed import's own `using`/`hiding` list is
skipped while other imports' lists are still checked; the throwaway env copy means a half-loaded module poisons
nothing.  One theoretical residual I could not construct a case for: if the batch load dies but every per-module
retry succeeds, the `Death` is now swallowed with no diagnostic at all — benign, because the retry loop has by
then actually loaded everything (R10, PLAUSIBLE, not demonstrated).

## 4. (c) the pin — verified, with one number to correct

The property drives `Diagnostics.check(resident, docs, uri, path, log)` — the same call `Diagnostics.run` makes,
which calls `Resident.checkFile` — over `corpusFiles ++ fixtureFiles`.  I re-derived the counts from the
filesystem: 161 stdlib + 92 `core/examples` (198 minus the 106 under `shouldfail`, `shouldfail-controls`,
`incomplete`) = **253**, plus **36** fixtures = 289 files; `notGoodCode` and the `walk` are copied from
`TestTolerantRead` verbatim, so the corpus definition is not weakened, and both floors (`>= 180`, `>= 30`) plus
the anti-vacuity floor (`seen >= 40`) are real.  The assertion is `start == end == 0:0`, so it catches exactly
the "gave up" shape and not a genuine position that happens to be at line 1.  **Exemptions: none, and none is
needed** — I confirmed no fixture is designed to fail at 1:1 (`BadHeader.e`, the only header-level failure, is at
`0:17`).

The BEFORE count: I reproduced it against a real build of `f09e086` (the scratch tree above) driving the same
fixtures through the LSP.  `BadImport.e` → `0:0-0:0 "Module not found: 'NoSuchModule'"`, one diagnostic, the
second import and every healthy definition unreported — exactly as reported.  But `BadReq.e` → `0:0-0:0
"…/BadReq.e:1:1: Module 'Bool' does not export term 'nosuchname'."` on that same build.  So the honest before
count over today's fixture set is **2, not 1**; the report's table says 1 under the heading "same property, same
files", because the number was taken with the import-list span fix already in the tree.  The report's own caveat
mentions the `BadReq.e` probe, so this is a labelling slip that UNDER-states the debt the item repaid, not an
inflated claim — but the number goes into the trackers, so it should be right (R1).

The `sk03` residual reproduces exactly as described: `core/examples/shouldfail/sk03_field_copy_append_self.e` →
`0:0-0:0 "…/sk03…e:1:1: …/modules/Field.e:22:24: Cannot unify skolem variable with empty relation"`.  It is out
of the sweep by the standing corpus rule (`shouldfail` is excluded for both this property and
`TestTolerantRead`), not by a special case invented here, and the same 1:1 outer position appears in the BATCH
verdict for that file in my corpus run — so it is a checker blame shape, not an editor position loss, and the
drafted ticket says so.  Correctly ticketed rather than hidden.

## 5. Findings

| id | severity | status | one line |
| --- | --- | --- | --- |
| R1 | medium | CONFIRMED | (c)'s BEFORE count is 2, not 1: `BadReq.e` also published at 0:0 on a real `f09e086` build |
| R2 | medium | CONFIRMED | The (b) rule covers term names only: an operator from a failed import still cascades 3 read diagnostics per use, and a type name draws "undefined type"; undisclosed |
| R3 | medium | CONFIRMED | The narrowing IS available for `import X using { … }` and was not used; the report's justification addresses only the open-import case, not the hybrid |
| R4 | medium | CONFIRMED | The roadmap's tick "the file's other diagnostics still publish" is not pinned: `BadImport.e` has no other diagnostics, so the smoke only asserts absences |
| R5 | nit | CONFIRMED | `docs/lsp.md` does not mention the new suppression rule (it documents the "unchecked" note that the rule now withholds) |
| R6 | nit | CONFIRMED | "The editor has no more information than the batch path does" is too strong — every Subst helper an explain-pass needs is public; the real argument is cost and divergence |
| R7 | nit | CONFIRMED | Import-name and import-list spans include the trailing space when a token follows (`Explicit.e` 2:7-2:20 for a 12-char name) |
| R8 | nit | CONFIRMED | `BadHeader.e`'s diagnostic is a zero-width range; the roadmap asked for "the header's extent" — unchanged by this item (my BEFORE build agrees), so wording to reconcile, not code |
| R9 | nit | CONFIRMED | On the failure path a broken sibling is parsed twice (batch attempt + retry); healthy path unaffected |
| R10 | nit | PLAUSIBLE | If a batch load dies but every per-module retry succeeds, the Death is swallowed silently; benign (the env is then complete), no case constructed |
| R11 | nit | CONFIRMED | The suppression is keyed on `spelling.isDefined`, so an undefined-term note for a var with no name survives — same shape as the existing 5.4 filter |

**R1** — `<scratch>/review-6.1/probe-before.out` has the raw JSON from the `f09e086` build: two fixtures at
`0:0-0:0`, `BadImport.e` and `BadReq.e`.  The fix is one number and one sentence in the report's (c) table:
either say 2 and drop the "measured separately" caveat, or relabel the row "before the import attribution, with
the import-list fix already in".  Everything else in (c) is right, including the honest note that the debt was
invisible before the fixtures existed.

**R2** — demonstrated above.  The fix I recommend is disclosure, not code: one paragraph in the report's "THE
RULE" section naming what is NOT suppressed (operators, type names) and a ticket draft for the orchestrator,
since suppressing read-phase diagnostics on an import failure is a bigger decision than this item's budget (they
are the same diagnostics a genuinely mistyped operator must still produce).  Left silent, the next person to
measure the cascade will think the rule is broken.

**R3** — `Explicit.e` under `<scratch>/review-6.1/fx/`.  I am NOT asking for the hybrid to be implemented: the
open-import case dominates and a rule that changes shape depending on whether every failed import happens to
carry a list is harder to explain than the one that is there.  I am asking for one sentence recording that the
narrowing was available in the list case and declined, so the decision is on the record where the next reader of
the rule will look.

**R4** — the roadmap's (b) tick condition says the file's other diagnostics still publish, and the behaviour IS
right (`MixErr.e`: import failure at `2:7-2:19` plus the type error, both published; `SelfBad.e`: syntax error
plus import failure).  But `BadImport.e` contains nothing that could produce another diagnostic, so the smoke
pins the tick only negatively (`len(ds) == 2` plus two "not present" checks): a regression that widened the
filter to drop every Error note would still leave exactly 2 and pass.  Fix: add two lines to `BadImport.e`
(`bad : Int` / `bad = "no"`), make the count 3, and assert the type error is among them.  That is the tick
condition, pinned positively, and it costs one lsp-smoke re-run (207 checks).

**R5–R11** are notes, not requests; R5 and R8 belong to the orchestrator's gate pass (`docs/lsp.md` is stale at
82 checks anyway, and the roadmap's lsp-smoke baseline must go 185 → 205, or 207 with R4).

## 6. Required before the tick

- **F1** — correct (c)'s before/after table to 2 → 0, or relabel the row (R1).
- **F2** — pin the roadmap's own tick condition positively: a definition with a genuine type error inside
  `BadImport.e`, asserted to publish alongside the two import failures (R4).  Re-run lsp-smoke only.
- **F3** — disclose the operator/type residual of the suppression rule in the report and draft the ticket (R2);
  add the one sentence for R3 while there.

None of these touches shipped code, so the gates I ran above stand except for the lsp-smoke count, which F2
moves by two.  With F1–F3 done, 6.1 ticks: (a) ACCEPTED with a reason a reader can check and a ticket that is
accurate, (b) implemented, positioned and pinned, (c) expected 0 and 0 measured over 289 files.
