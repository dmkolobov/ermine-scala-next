# Brief: LSP Stage 3, item 6.1 — diagnostics debt (do-anchor blame, unrecoverable-Death positions, a 0:0 sweep pin)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (6.0 is
committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs. No commits. Do not touch
`tracker/lean/` or `tracker/LSP-ROADMAP.md` (the orchestrator edits those). Delete every `.ei` you cause (never the
checked-in ones under `tracker/g1-*`). Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.1/`.
Item of record: `tracker/LSP-ROADMAP.md` § Stage 3, item **6.1** (read it, the STAGE-3 INVARIANTS above it, and the
Stage-3 Decisions); gates `tracker/GATE-POLICY.md`; the fixture rule at the top of
`scalacheck-binding/src/main/scala/TestErmine.scala` (never `System.setProperty` a per-call-read flag).

THE HARD INVARIANT FOR THIS ITEM: BATCH SEMANTICS ARE FROZEN. `Session.load`/`loadModule` refusals, the REPL goldens
(`tracker/repl-tests/*.expected`) and `TestReplDifferential` stay BYTE-IDENTICAL, and `TestTolerantRead`'s 180-file
agreement property stays green. Any change that moves a batch message or position is out of scope for (b) and (c)
and is the decision point in (a) — see below. Everything here is the EDITOR path: `lsp/Diagnostics.scala`,
`lsp/Resident.scala`, `session/TolerantCheck.scala`, `rename/NewPipeline.scala` (tolerant entry only).

## (a) The do-anchor blame gap — budget HALF an iteration, fix-or-explain
The pin: `TestStage1Pins` "a type error inside a do block anchors on the bind's rhs" — the program
`v = orElse 0 ((do w <- liftDo (Just 1)\n  unit (w && True)) maybeMonad)` is blamed at line 1 (the bind
application, relocated to its first argument's loc: `Lower.scala` SDo case, `App(App(Var(bind at mv.loc), mv), mf)`)
where the fused pipeline blamed line 2 (the `w && True` subterm). The 5.4 log says the checker infers the
continuation lambda `mf` independently and the Int-vs-Bool clash surfaces at the SUBSUME of the application, so
the blame Loc is the App's. What to do, in order:
1. Reproduce through BOTH paths: the pin (batch, `failsAtLine` → line 1) and the editor (`TolerantCheck` on the
   same module: what line does the note carry?). Trace in `Subst.inferType`'s `App` case (~:914) and
   `subsumeType` (~:527) exactly which `Located` supplies the report position, and why the inner clash inside
   `mf`'s body is not reported at its own Loc (is the lambda body checked against an expected type pushed down —
   in which case the clash happens INSIDE and should carry `&&`'s Loc — or is `mf` inferred bottom-up and then
   subsumed, so the clash is only visible at the App?).
2. Decide which of three it is and act:
   - EDITOR-ONLY improvement possible (e.g. the tolerant check can re-blame: when the App's two sides are a `bind`
     application and a lambda whose body has a concrete-type clash, report at the innermost Located whose type
     participates) WITHOUT touching `Subst`: do it, pin it in `TestTolerantCheck` (note at line 2), leave the batch
     pin as-is and write in the pin's comment that the editor now blames line 2.
   - A SHARED change in `Subst` that would move the batch message/position: DO NOT MAKE IT. Write the precise
     mechanism and the change it would take under a heading "Accepted: why the blame stays on the bind" in your
     report, so 6.1(a) closes as ACCEPTED with reasons a reader can check. (Such a change is a batch-behaviour
     change — Tier 2 plus goldens — and belongs to its own ticket, which you draft as a paragraph for the
     orchestrator.)
   - It is a Loc-propagation slip in `Lower`'s do-desugar (the relocation `bind at mv.loc` choosing the wrong
     side) that changes ONLY the position of an already-refusing program: then it is a candidate for both paths,
     but it moves the pin and possibly REPL goldens — stop and report before changing anything; the orchestrator
     decides.
   Half an iteration means: if after ~3 hours of machine+reading time you are not in one of the three states,
   write up where you are and move to (b).

## (b) Unrecoverable-Death positions
Today `Resident.checkFile` parses the header, then `Session.loadModules(missing.sorted)` for the imports not yet
loaded, then the tolerant read. A missing import module, or an import whose FILE will not load (syntax error, its own
unloadable import, a foreign failure in non-tolerant mode — no, foreign is tolerant in the editor), throws a `Death`
that `Diagnostics.run` turns into ONE diagnostic via `fromReport`; when the report's first line names another file
(the import's), or carries no position (`Module not found: 'X'`), it lands at **0:0** (`Diagnostics.scala` :183-187).
Fix, editor path only:
1. Load the missing imports ONE AT A TIME under a catcher (Death and `parsing.Recoverable`, as `TolerantCheck.guard`
   does), so one broken import does not hide another. For each failure produce a `TolerantCheck.Note` (Error) with
   a real `Span` on the IMPORT STATEMENT that named the module: `ModuleHeader.importExports` carry `loc: Pos` per
   `ImportExportStatement` (header parse; available before the tolerant read), and the tolerant read's
   `SModule.header.imports` carry `SImport.moduleSpan` (exact module-name span) — prefer the exact span when the
   read succeeds, the header Pos otherwise. Message: the loader's own report text (which names the import's file
   and position — keep it, the user needs it), prefixed so it reads as "import X failed: ...".
2. Then CONTINUE: run the tolerant read and check anyway, so the rest of the file still gets its diagnostics and
   navigation. The names the failed import would have provided are now `undefined term` notes — decide and STATE
   the rule (suppress undefined-term notes while any import failed? or only those spelled in the failed import's
   explicit list?), implement it, pin it. Do not let a failed import produce an "unchecked" cascade that hides the
   real error; do not let it produce hundreds of undefined-term notes either.
3. A header that will not parse still dies (that is a syntax error in THIS file with a position in this file —
   `fromReport` positions it already); verify with a fixture that its position is right and its END is not 0:0.
4. Fixtures under `tracker/lsp-tests/`: `BadImport.e` importing (i) a module that does not exist and (ii) a sibling
   `BadSib.e` whose body has a syntax error, plus a healthy definition of its own and a use of a name from (ii).
   lsp-smoke checks: two Error diagnostics on the two import statements (exact ranges: the module-name span), with
   messages naming the missing module / the sibling's file:line; the healthy definition still navigates and hovers;
   the rule from step 2 is visible (say what is asserted); fixing `BadSib.e` through didChange clears the second
   import diagnostic on `BadImport.e`'s next check (the sibling-buffer path). Count grows from 185; the number goes
   in your report.

## (c) The 0:0 sweep pin
A `TestTolerantCheck` (or `TestTolerantRead`) property over the 180 corpus files (stdlib + `core/examples`, the
existing `corpusFiles`/`sweepFx` machinery): every diagnostic and note the editor path produces (there should be
none on clean modules — the existing sweep already requires zero notes) AND every diagnostic the editor path
produces for the `tracker/lsp-tests/*.e` fixtures (which are broken on purpose) has a position other than 0:0
unless the fixture is DESIGNED to fail at 1:1. Drive `Resident.checkFile` (or the same calls it makes) from the
test rather than the LSP client, so this is a JVM-local property. Expected: 0 violations after (b); show the count
BEFORE (b) as well — that number is the evidence (b) was needed.

## Gates (Tier 0; the item touches TolerantCheck/Resident/Diagnostics, so also the targeted suites)
`sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'` 720/720; `sbt 'core/testOnly
*TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestStage1Pins *TestReplDifferential'` all green with the
counts before/after; `tracker/tools/corpus-run.sh --batch <scratch outdir>` 85 / 69 / 0 over 154 (it NEEDS the outdir
argument); `tracker/tools/repl-smoke.sh` 8 groups / 66 checks with `tracker/repl-tests/*.expected` unmodified
(`git status`); `tracker/tools/lsp-smoke.sh` (185 + yours). Layout/Report.e read+check time before/after
(`ERMINE_LSP_LOG` timing line or `perf-bench.sh editor -k 5`, one pair — this item must not move it; say the numbers).

## Report `tracker/loopmodel/LSP3-6.1-DIAGNOSTICS.md`
(a)'s trace and which of the three states it ended in (with the "Accepted" paragraph or the pinned improvement);
(b)'s design (the undefined-term rule) and fixtures; (c)'s before/after counts; the diff summary; every gate number.
Outcomes: (GREEN) all three done; (GREEN-ACCEPTED) (a) closed as accepted with reasons, (b)(c) done; (PARTIAL)
which and why. No silent weakening; do not edit `tracker/LSP-ROADMAP.md`; STOP after the report — a reviewer
re-runs the gates once.
