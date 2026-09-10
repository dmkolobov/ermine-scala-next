# LSP Stage 3, item 6.1 — diagnostics debt

Implementer report, 2026-09-09 (Opus).  Brief `tracker/loopmodel/briefs/brief-LSP3-6.1.md`; item of record
`tracker/LSP-ROADMAP.md` § Stage 3, item 6.1.  Branch `scala3-migration`, from HEAD `f09e086`.  No commits.
`tracker/LSP-ROADMAP.md` and `tracker/lean/` untouched.  Scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.1/`.

**OUTCOME: GREEN-ACCEPTED.**  (a) closes as ACCEPTED with the mechanism written out and a ticket drafted;
(b) and (c) are done and pinned.  Batch semantics are untouched: nothing outside `lsp/` and the editor-only
`TolerantCheck.Note` changed, the REPL goldens are byte-identical, `TestReplDifferential`, `TestStage1Pins`
(the do-anchor pin included, unchanged) and `TestTolerantRead`'s 253-file agreement sweep are green.

---

## (a) The do-anchor blame gap — ACCEPTED

### What was reproduced, in both paths

The pin `TestStage1Pins."a type error inside a do block anchors on the bind's rhs"` (batch, `failsAtLine ... 1`)
still passes.  The EDITOR path was driven over the real LSP for the same program
(`scratch/6.1/work/DoAnchor.e`, a scripted client in `scratch/6.1/probe.py`):

```
v = orElse 0 ((do w <- liftDo (Just 1)
                  unit (w && True)) maybeMonad)
```

editor diagnostic: `7:24: error: failed to unify type Int with type Bool` — line 7 col 24 is `liftDo`, i.e. the
bind's rhs, i.e. **statement line 1**, the same position the batch pin asserts, with the same message and no
secondary location.  Editor and batch agree because they are the same code: `TolerantCheck.guard` stores the
`Death`'s rendered report and `Diagnostics.fromReport` recovers its position.

### Which `Located` supplies the position, and why the inner clash is not seen at its own `Loc`

`Lower.scala`'s `SDo` case builds `App(App(Var(bind at mv.loc), mv), mf)`, and `App.loc = e1.loc`
(`Term.scala:70`), so the whole application's `Loc` is `mv.loc` — the bind's rhs.  In `Subst.inferType`
(`Subst.scala:877`) the implicit `tml: Located` is `e`, the term being inferred; in the `App` case
(`Subst.scala:914`) that is the application itself.  The clash is raised inside `subsumeType`
(`Subst.scala:527`) → `unifyType` (`Subst.scala:270`), both of which report at `tml` — hence `mv.loc`.

The brief's question — is the lambda body checked against a pushed-down expected type (so the clash would
happen INSIDE and carry `&&`'s `Loc`), or is `mf` inferred bottom-up and then subsumed? — has a definite
answer: **bottom-up, then subsumed**.  In the `App` case `tf` is inferred, `matchFunType` yields the expected
argument type `i`, then `tx = inferType(gp, x)` infers the CONTINUATION LAMBDA on its own (its binder's type
is a fresh meta, which the body pins to `Bool` via `&&` with no clash), and only then does
`subsumeType(substType(i), tx)` compare `Int -> …` against `Bool -> …`.  The Int and the Bool first meet at
the application, and the application is where it is reported.

Three pieces of evidence that this is inference structure and not a lost `Loc`:

1. **An intrinsic inner clash IS blamed inside.**  `scratch/6.1/work/DoInner.e`, the same do with
   `unit (1 && True)`, is blamed at `8:27` — statement line 2, on the offending subterm.  Nothing about the
   do-desugar loses positions.
2. **The anchoring is not do-specific.**  `scratch/6.1/work/LamApp.e`:
   ```
   g : (Int -> Bool) -> Bool
   g h = h 1
   v = g (w ->
            w && True)
   ```
   is blamed at `8:5` — the head `g` of the application, not the `w && True` on the next line.  Any
   application of an unannotated lambda whose parameter type clashes behaves this way; the `do` case merely
   inherits it, and it inherits it through the `bind` application the desugarer mints.
3. **There is no checking mode to push a type into.**  `Subst.typeCheck` (`Subst.scala:633`) is itself
   `inferType` followed by `subsumeType`, and so is `typeCheckExplicitBinding` (`:647`) and
   `typeCheckPattern` (`:972`).  This checker has no bidirectional descent anywhere: every judgement is
   bottom-up inference plus a subsumption at the boundary.

### Accepted: why the blame stays on the bind

Moving the blame to the inner subterm requires the checker to CHECK the continuation lambda against the
expected argument type instead of inferring it — that is, a checking-mode `Lam` rule in `Subst.inferType` (or
a `typeCheck` that descends rather than delegating to `inferType`).  That is a change to the shared type
checker, and it would move the reported position and often the message of **every application of an
unannotated lambda whose argument type clashes** — a batch-behaviour change (Tier 2 plus goldens), which
the Stage-2/Stage-3 frozen-semantics invariant forbids in this item.

The two cheaper repairs were considered and both fail:

- **Re-blaming in the editor only.**  What the editor HOLDS after the refusal is the rendered `Death` and
  nothing about which subterm's type participated — the clash never reached a subterm, it happened at the
  boundary.  It could of course compute more: `Subst`'s helpers are public, so an explain-pass could re-run
  the application in checking mode and report the inner clash.  The objection is cost and divergence, not
  access (review R6): that pass IS the bidirectional rule, written a second time, in an engine that would
  then disagree with the compiler about where errors are — the one thing an editor built beside a batch
  compiler must not do.  Rejected.
- **A `Loc`-propagation change in the do-desugar.**  The relocation `Var(bind at mv.loc)` is deliberate
  ("Appable parity": the fused pipeline relocated each minted application to its FIRST argument's loc so a
  type error blames the statement rather than the whole `do`).  Removing or changing it moves the blame to
  another OUTER position — the `do` keyword's span, or `mf`'s — never to the inner subterm, and it moves the
  batch pin and possibly REPL goldens for no gain.  Rejected.

So 6.1(a) closes as ACCEPTED: the pinned line stays on the bind's rhs, and the reason above is the record.
`TestStage1Pins`'s comment already says the asserted line is "the current behavior, not the ideal"; nothing
in it was edited.

### Ticket draft for the orchestrator (not filed by me)

> **Ticket (Stage 4+, Tier 2): check unannotated lambdas against the expected argument type.**  `Subst` is
> purely bottom-up: `inferType`'s `App` case infers the argument and then `subsumeType`s it against the
> function's domain, and `typeCheck` is `inferType` + `subsumeType` too, so no expected type is ever pushed
> into a `Lam`.  Consequence: a type error inside an unannotated lambda is blamed at the APPLICATION, not at
> the offending subterm — the do-anchor gap (6.1(a)) is one instance, `g (w -> w && True)` is the general
> one.  The fix is a checking-mode rule for `Lam` (bind the pattern at the expected domain, check the body
> against the expected codomain) with `App` using it when the argument is a syntactic lambda.  Scope: it
> changes the position, and sometimes the wording, of every such refusal — batch goldens (`tracker/repl-tests`,
> `TestStage1Pins`'s two anchor pins, the corpus batch verdict TEXT though not the verdicts) must be re-cut,
> so it is Tier 2 + goldens and belongs to its own item, not to a diagnostics-debt item under frozen batch
> semantics.

---

## (b) Unrecoverable-Death positions

### The debt, measured before the change

`tracker/lsp-tests/BadImport.e` (new fixture: one import that does not exist, one whose file has a syntax
error, plus healthy definitions) produced, before the change, exactly ONE diagnostic:

```
0:0-0:0  severity 1  "Module not found: 'NoSuchModule'"
```

The second broken import, and every healthy definition in the file, went unreported; the position carried no
information at all.

### The change (editor path only, `lsp/Resident.scala`)

1. **Attribution.**  `checkFile` still calls `Session.loadModules(missing)` ONCE — the fast path, the only one
   a healthy file takes, and the one that keeps the loader's parallelism, so nothing about the timing of a
   file whose imports are fine changes.  Only when that call dies (`Death` or `parsing.Recoverable`, the
   `TolerantCheck.guard` pair) does it re-load the missing modules ONE AT A TIME under a catcher, skipping
   the ones already in `loadedModules`.  One broken import can no longer hide another.  The env is the
   throwaway copy, so a half-loaded module poisons nothing.
2. **Position.**  Each failure becomes a `TolerantCheck.Note(Error)` with a `Span` on the MODULE NAME of its
   own import statement — `SImport.moduleSpan` from the tolerant read (the same span go-to-definition on an
   import uses), falling back to the header's `ImportExportStatement.loc` (the `import` keyword, six
   characters) if the read did not shape the header.  Notes are ordered by the import's source order.
   Message: `"import <M> failed: " + <the loader's own report>` — the report is kept verbatim because it
   names the import's file and the position inside it, which is the only part that says why.
3. **Continue anyway.**  The tolerant read and `TolerantCheck` run as before, so the rest of the file gets
   its diagnostics, its types and its navigation index.
4. **Import lists.**  A module that did not load exports nothing, so its `using`/`hiding` list would draw one
   "does not export" requirement note per name.  Those are skipped for failed modules only; other imports'
   lists are still checked.
5. **Fast mode.**  Import failures are published in fast mode too: they are neither a read product nor a
   check product but the same failure in both modes, and silence would leave a file full of unexplained
   undefined names.

### THE RULE (step 2), stated

> **While any import has failed to load, the editor drops every undefined-term note and every
> "unchecked: depends on a broken definition" note for the file, and keeps everything else** — the syntax
> diagnostics, the surviving imports' export requirements, and the type errors of every definition that could
> still be checked.

Wholesale, not "only the names the failed import's explicit list spelled": an open `import M` — the common
form, and both arms of the fixture — has no list to consult, so the narrow rule would degenerate to no rule
on exactly the case that needs one.  This is the same rule, for the same reason, that `checkFile` already
applies for a broken STATEMENT ("when no head word can be recovered … suppress undefined-term notes outright
while syntax errors stand", 5.4): while a name COULD NOT ARRIVE, its consequences are not diagnostics.  The
cost is that a genuine typo goes quiet until the import is fixed; the import failure is the error the user
must act on first, and it is now the one they see.

Implementation note: both kinds are recognised by FLAGS, not by matching rendered text.
`TolerantCheck.Note.spelling` already marked undefined-term notes; `Note.dependsOnBroken` (new, default
false, set at the one place that emits "unchecked") marks the other.  `TolerantCheck` is editor-path only,
so this touches no batch behaviour.

**What the rule does NOT suppress (review R2, disclosed 2026-09-10).**  The rule reaches TYPE-CHECK notes
about TERM names, because those are what carries `spelling`.  Two other consequences of a missing import
survive it:

- **Operators.**  An operator the failed module would have supplied is unknown to the RE-ASSOCIATOR, so the
  cascade is read-phase, not check-phase: `unknown operator <?>` (Reassoc) plus `ill-formed expression` and
  `error node` (Lower) — **three Error diagnostics per use**, none of them a `Note` and none of them
  reachable by a note filter.  The reviewer's `OpCascade.e` (two uses of a missing `<?>`) publishes six read
  diagnostics beside the one import failure; the plain undefined TERM in the same file (`z = missingName 5`)
  is suppressed correctly.
- **Type names.**  A type the failed module would have supplied draws `error: undefined type` from the type
  phase — a guarded `Death` note with no `spelling`, so the flag the rule keys on is absent.  The reviewer's
  `TypeCascade.e` shows it (`f : Widget -> Widget` → one `undefined type` beside the import failure).

Both are disclosed rather than fixed: suppressing READ-phase diagnostics on an import failure is a larger
decision than this item's budget allows, because they are the same diagnostics a genuinely mistyped operator
must still produce.  Ticket draft:

> **Ticket (Stage 3/4, editor path): the import-failure suppression rule covers term names only.**  6.1(b)
> withholds undefined-term and "unchecked" NOTES while an import has failed, but a missing module also costs
> (i) three READ diagnostics per use of an operator it would have supplied — `unknown operator` from
> `Reassoc`, then `ill-formed expression` and `error node` from `Lower` — and (ii) one `undefined type` note
> per type name it would have supplied (the note carries no `spelling`, which is the flag the rule keys on).
> Neither is reachable from `Resident.checkFile`'s note filter as it stands: (i) are `NewPipeline.Diag`s, not
> `Note`s.  Candidate shape: while an import failed, tag the read diagnostics whose head is an unresolved
> operator and the type-phase notes for unresolved type names, and withhold those the same way — which means
> a flag on `Diag` and on the type-phase note, since matching rendered text is not acceptable here (6.1's own
> rule).  The hard part is not the plumbing but the policy: the same three diagnostics are exactly right for
> a mistyped operator in a file whose imports are all fine, so the tag must distinguish "this operator is
> unknown because a module did not load" from "this operator is unknown".  Evidence: `OpCascade.e`,
> `TypeCascade.e`, `BigCascade.e` in the 6.1 review's scratch directory.

**The narrowing that was available and declined (review R3).**  For an import written `import X using { a; b }`
the explicit list DOES name what the failed module would have provided, so the rule could have been narrowed
to those spellings in that case; it was declined because the open `import X` — both arms of `BadImport.e` and
the common form in the corpus — has no list, so a rule that narrows only sometimes is harder to state and to
predict than one that behaves the same way for every failed import, and the hybrid's extra precision applies
exactly where the user has already told the editor which names they meant to get.

### After

```
2:7-2:19   severity 1  import NoSuchModule failed: Module not found: 'NoSuchModule'
3:7-3:13   severity 1  import BadSib failed: …/tracker/lsp-tests/BadSib.e:5:10: error: expected "-", case,
                       do, let, operator, pattern atom, term atom, or whitespace / broken = = 3 / ^
13:0-13:0  severity 1  …/BadImport.e:14:1: error: failed to unify type Int with type String
```

— one Error per failing import, on the module name; the file's OWN type error (`bad : Int` / `bad = "no"`)
published beside them, which is the roadmap's tick condition "the file's other diagnostics still publish";
`own`/`useOwn` still navigate and hover (`Int`); `use = sibAnswer` is silent.

### Step 3 — a header that will not parse

`tracker/lsp-tests/BadHeader.e` (`module BadHeader wehre`) publishes ONE diagnostic at `0:17-0:17`
(`BadHeader.e:1:18: expected '.', where, or whitespace`).  `fromReport` already positioned this correctly
because the report's first line names THIS file; the pin is that it does, that the position is the parser's
own, and that the END is not 0:0 either.  Verified before the change as well as after — this half of the
brief's step 3 was already sound and is now covered by a fixture and by (c).

### An extra 0:0 source found and closed while pinning (c)

An import list naming something the module does not export (`import Bool using { nosuchname }`) is the
editor's own check — batch gets it from `Dep.checkNames` — and it rendered at `mh.loc`, the module header:
line 1, column 1, i.e. LSP **0:0**, demonstrated on `scratch/6.1/work/BadReq.e` before the change.  The name
is in the import list and the read knows its span, so the note now carries the item's own span and a plain
message (`Module 'Bool' does not export term 'nosuchname'.`) instead of a rendered report anchored at the
header.  Fixture `tracker/lsp-tests/BadReq.e`, pinned in lsp-smoke; the span's end runs to where the next
token starts, as every surface span does.

### Fixtures added (`tracker/lsp-tests/`)

| file | what it is |
| --- | --- |
| `BadImport.e` | imports `NoSuchModule` (does not exist) and `BadSib` (its file will not load), plus `own : Int` / `own = 6`, `useOwn = own`, `use = sibAnswer` (a name from the broken sibling) and `bad : Int` / `bad = "no"` (a type error of its own, so the tick condition is pinned positively — review R4) |
| `BadSib.e` | defines `sibAnswer = 7` and has a syntax error (`broken = = 3`) |
| `BadHeader.e` | a header that will not parse (`module BadHeader wehre`) |
| `BadReq.e` | `import Bool using { nosuchname }` — an import list requirement |

---

## (c) The 0:0 sweep pin

`TestTolerantCheck`, three new properties, driving `Diagnostics.check` — the very call `Diagnostics.run`
makes — against a real `Resident` in the test JVM (no socket, no client).  `Diagnostics.run`'s body was split
into `Diagnostics.check(ermine, docs, uri, path, log): List[Json]` for this; `run` now adds only the timing
line and the publish, so what the property inspects is what the server publishes.

The sweep boots one `Resident` (shared under a lock, because `Resident.supply` is a single `Supply` and
ScalaCheck runs a `Properties` object's properties on a pool) and warms it with the whole stdlib, so a
per-file check does not re-load imports into its throwaway copy 289 times.

Files: **253 corpus files** (161 stdlib + 92 under `core/examples`, the standing 180-file rule's corpus minus
`shouldfail`, `shouldfail-controls`, `incomplete`) **+ 36 fixtures** in `tracker/lsp-tests` = **289 files**,
**71 diagnostics inspected** (70 as first measured, plus the one `BadImport.e` gained in the fix round) (the corpus is silent by construction — that is `TestTolerantRead`'s sweep — so
every position inspected comes from the fixtures; the property asserts `seen >= 40` so that "no diagnostic at
0:0" can never pass because nothing was published).

| | diagnostics at 0:0 |
| --- | --- |
| BEFORE — the fixtures against an unmodified `f09e086` build | **2** — `BadImport.e 0:0-0:0: Module not found: 'NoSuchModule'` and `BadReq.e 0:0-0:0: …:1:1: Module 'Bool' does not export term 'nosuchname'.` |
| AFTER | **0** |

Correction (review R1, 2026-09-10): my first table said 1.  That number came from a run in which the
import-list span fix of §(b) was already in the tree, so only `BadImport.e` was left to violate; the
reviewer re-measured both fixtures on a real `f09e086` build and both publish at 0:0 there
(`<review scratch>/probe-before.out`).  **The BEFORE count is 2 and the row above says so.**

No fixture is designed to fail at 1:1, so the expected count is 0 with no exemption list.  Honest caveat: the
"before" count is 2 rather than larger because the debt is invisible without a fixture that provokes it —
before `BadImport.e` and `BadReq.e` existed, nothing in the corpus or the fixture set reached either 0:0
path.

The other two new properties pin (b) itself in-JVM: the two import diagnostics with their exact spans, the
kept loader report (`BadSib.e:5:`), and the RULE (no "undefined term", no "unchecked" in the published set);
and the header failure's position.

### Known gap this property does NOT cover (recorded, not fixed)

A type error whose blame `Loc` is the BINDING GROUP's still renders at the module's own position — line 1,
column 1, LSP 0:0.  `TolerantCheck.checkWith` passes `m.loc` as the group `Loc` to
`inferImplicitBindingTypes`, so a refusal raised against the group's `Located` (rather than against a term)
carries it.  Demonstrated through the LSP on `core/examples/shouldfail/sk03_field_copy_append_self.e`:

```
0:0-0:0  "…/sk03_field_copy_append_self.e:1:1: …/modules/Field.e:22:24: Cannot unify skolem variable with
          empty relation"
```

It is out of the sweep because `shouldfail/` is out of the corpus by the standing rule, and out of this item
because the repair is a blame change in the checker, not a position recovery in the editor.  Ticket draft:

> **Ticket (Stage 3/4, editor path): group-level refusals land at 1:1.**  `TolerantCheck.checkWith` infers
> each SCC with `inferImplicitBindingTypes(m.loc, …)`, so any refusal raised at the group's `Located` — and
> any refusal whose own blame is inside an IMPORTED file, which then renders as "thisfile:1:1: otherfile:l:c:
> …" — reaches `Diagnostics.fromReport` as this file's 1:1 and publishes at 0:0.  Candidate fix, editor-only:
> pass the component's own `Loc`, or attach the component's first binding's span to the guarded note when the
> rendered report's outer position equals the module's.  Both move positions that lsp-smoke pins today, so it
> needs its own item with the fixture set re-measured.

---

## Diff summary

| file | change |
| --- | --- |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Resident.scala` | (b): per-import attribution after a failed batch load; import-failure notes on the module-name span; export-requirement notes anchored on the import-list item; the suppression rule; import failures published in fast mode too |
| `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Diagnostics.scala` | `run`'s body split into `check(...): List[Json]` so (c) can drive the editor path in-JVM; behaviour identical |
| `core/src/main/scala/com/clarifi/reporting/ermine/session/TolerantCheck.scala` | `Note.dependsOnBroken` flag (default false) set on the "unchecked" note; editor-path only |
| `scalacheck-binding/src/main/scala/TestTolerantCheck.scala` | three properties: the 0:0 sweep, the import-failure pin, the header-failure pin (14 → 17 properties) |
| `tracker/tools/lsp-client.py` | 22 new checks: `BadImport.e` (import failures, the rule, the file's own type error), `BadSib.e` buffer fix, `BadReq.e`, `BadHeader.e` |
| `tracker/lsp-tests/BadImport.e`, `BadSib.e`, `BadHeader.e`, `BadReq.e` | new fixtures |

`Session.scala`, `Subst.scala`, `Lower.scala`, `Type.scala` and every batch path: untouched.

## Gates (Tier 0 + the targeted suites), all run by me on the final tree

| gate | result |
| --- | --- |
| `sbt core/compile core/copyResources` | green |
| `sbt 'core/testOnly *TestLoopTrace'` | 3/3 properties; **720 solves / 720 segments / 720 agree**, 0 skipped, hashdiff 0, eqdiff 0 |
| `sbt 'core/testOnly *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestStage1Pins *TestReplDifferential'` | **69/69 passed, 0 failed** (before: 66 — the only count change is TestTolerantCheck 14 → 17) |
| `tracker/tools/corpus-run.sh --batch <scratch>/corpus-out2` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** |
| `tracker/tools/repl-smoke.sh` | **8 groups / 66 checks**, all PASS (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` clean — goldens byte-identical |
| `tracker/tools/lsp-smoke.sh` | **PASS, 207 checks** (185 + 22; 205 before the fix round, +2 from F2) |
| `.ei` hygiene | 0 `.ei` anywhere outside the checked-in `tracker/g1-*`; `find core/target -name '*.ei'` = 0 |

### Perf — Layout/Report.e read + check, `perf-bench.sh editor -k 5`

Run as a pair with a repeat, each side waiting for load < 1.3 (the harness's own guard is 1.5):

| run | median | read | typecheck | reused | spread |
| --- | --- | --- | --- | --- | --- |
| AFTER (1st) | 1.808 s | 0.930 s | 0.555 s | 97/154 | 1.756–1.849 |
| BEFORE (stashed core sources, recompiled) | 1.721 s | 0.875 s | 0.530 s | 97/154 | 1.681–1.764 |
| AFTER (2nd) | **1.723 s** | 0.855 s | 0.545 s | 97/154 | 1.681–1.752 |

The first AFTER run is machine drift, not the change: it ran with the 5-minute load average still falling
(`load_before=1.01 load_after=2.65` against `1.22 → 1.26` for the repeat), it moved the READ time too — which
this item cannot touch — and the repeat lands on the BEFORE median to within 2 ms.  **The item does not move
the editor round trip**, which is what the mechanism predicts: a file whose imports all load takes exactly
the old single `Session.loadModules` call, and Report.e's imports are all in the resident closure.

## Notes for the reviewer

- Re-running the gates once is enough; nothing here is timing-dependent except the perf pair, and the pair's
  conclusion rests on the repeat, not on the first run.
- `lsp-smoke`'s baseline note in `tracker/LSP-ROADMAP.md` (185) needs updating to **207** by the
  orchestrator; I did not edit the roadmap.
- Scratch artefacts (probe client, fixtures used for the (a) trace, both perf runs, both corpus runs) are
  under the scratch directory named at the top and are not part of the tree.

---

## Fix round (2026-09-10, after `tracker/loopmodel/LSP3-6.1-REVIEW.md`, verdict FIX-THEN-ADVANCE)

| finding | what changed |
| --- | --- |
| **F1** (R1) | The (c) BEFORE count is **2, not 1** — my figure was taken with the import-list span fix already in the tree, so only `BadImport.e` could still violate; on an unmodified `f09e086` build `BadReq.e` publishes at 0:0 as well.  The table and its caveat are corrected above, with the correction left visible rather than overwritten. |
| **F2** (R4) | `tracker/lsp-tests/BadImport.e` gained `bad : Int` / `bad = "no"`, and lsp-smoke now asserts that the type error publishes ALONGSIDE the two import failures (count 3), and still publishes after the sibling is fixed (count 2).  The roadmap's tick condition "the file's other diagnostics still publish" was pinned only by absences before; it is now pinned positively, so a filter that dropped every Error note would fail.  The in-JVM pin in `TestTolerantCheck` was moved in step (`ds.size == 3` plus one "failed to unify"); the exact import spans are unchanged and still asserted. |
| **F3** (R2, R3) | §"THE RULE" gained **"What the rule does NOT suppress"** — the operator cascade (three read-phase diagnostics per use) and `undefined type`, with the reviewer's evidence named — and a ticket draft for the orchestrator; plus one paragraph recording that narrowing by an explicit `import X using { … }` list was available and declined, with the reason. |
| **R5** (nit) | `docs/lsp.md` now describes the import-failure diagnostics, the sibling-buffer clear, and the suppression rule including what it does not cover.  The rest of that file is still due its 6.7 refresh (it says 82 checks). |
| **R6** (nit) | The "(a) editor-only re-blame" bullet no longer claims the editor lacks the information; the objection is stated as cost and divergence, which is what it is. |

Gates re-run for the fix round (the reviewer's stand: nothing else was touched):
**`tracker/tools/lsp-smoke.sh` PASS, 207 checks**, and `sbt 'core/testOnly *TestTolerantCheck'` **17/17**
(run because F2 moved a fixture that suite reads — leaving it red was not an option).  No shipped code changed
in this round.  R7–R11 were notes, not requests, and are left as the review records them.
