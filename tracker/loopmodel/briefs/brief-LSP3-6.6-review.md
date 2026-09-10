# Review brief: LSP Stage 3 item 6.6 — quick fixes (add import, add type signature)

You are reviewing item 6.6 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `c933b61`
plus the UNCOMMITTED deliverables: new `lsp/QuickFix.scala`, `scalacheck-binding/src/main/scala/TestQuickFix.scala`,
fixtures `tracker/lsp-tests/{Fix,FixSib,FixTy,FixCrlf}.e`; modified `lsp/{Definitions,Diagnostics,Documents,Main,
Completion}.scala`, `TestTolerantCheck.scala`, `tracker/tools/lsp-client.py`, `docs/lsp.md`; report
`tracker/loopmodel/LSP3-6.6-QUICKFIX.md`). Implementer's brief `tracker/loopmodel/briefs/brief-LSP3-6.6.md` (note: its
`import M (a, b)` wording was wrong — this grammar has `using`/`hiding` lists; the implementer corrected it); item of
record `tracker/LSP-ROADMAP.md` § Stage 3, 6.6 with the STAGE-3 INVARIANTS and Decision (e); gates
`tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.6/` and your
report `tracker/loopmodel/LSP3-6.6-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time (a research agent is running WITHOUT a JVM alongside you;
that is fine), no background JVMs, no lingering polling shells; `sbt core/compile core/copyResources` before any
`bin/ermine` gate; delete every `.ei` you cause; do not touch `tracker/lean/`; no commits. Confirm first: nothing
outside `core/src/main/.../lsp/` changed in `core/src/main` (implementer: no Subst/Type/Pretty/Lower/TolerantCheck/
Renamer/NewPipeline) — Tier 0; `git diff --stat` == `--stat -w`. `tracker/repl-classpath.txt` shows as modified — it
is a regenerated cache; say whether the content change is real (a classpath entry moved) or cosmetic.

1. **THE SWEEP (Decision e — the item's one correctness measurement).** `-Dermine.sweep.quickfix=true`, gated out of the
   shipped suite: 253 files (4 excluded — which, why), 1334 groups, 1166 insertions, CLEAN 1164 (99.83%), PARSE-FAIL 0,
   TYPE-FAIL 2 (Validation.e `empty_Bracket`/`cons_Bracket`: a `type Err = (String,String)` alias unfolded, re-check
   silent), SKIPPED 168 (out-of-scope 117, free kind var 36, nested `* ->` 10, `<:_Type.Cast` 2, field round-trip 3).
   RE-RUN IT (one JVM) and reproduce every number. Then interrogate the classification: (a) CLEAN means "re-check has
   zero diagnostics AND every group's type is alpha-equivalent to the original" — the implementer moved from
   rendered-text comparison (81%) to `G1Compare.alphaEq` plus a COMPLETE all-bijections comparator after finding
   kind-binder/row-constraint ORDER differences; is the complete comparator sound (does it accept anything it should
   not — e.g. two types differing only in which of two same-kinded variables is which, where that difference is
   semantic?), and how many pairs needed it (6)? (b) the 2 TYPE-FAILs: an alias unfolded in the rendered type — is the
   inserted signature WRONG (a different type) or merely less abstract (the alias's expansion, equal as a type)? If
   equal-as-a-type, why is it a TYPE-FAIL and not CLEAN under alphaEq — because the comparator sees the alias node?
   Decide which it is; it changes whether the action is safe on those two. (c) SKIPPED out-of-scope 117: the
   rendered type names a constructor the file's scope does not have (identity test via consOrigins, printer spelling
   incl. `n_Module`) — spot-check five: could the action have QUALIFIED the name or added an import instead of
   skipping? Is skipping the right call for 6.6 (yes if stated)? (d) FieldIdentity: imported row fields strict, own
   fields exempt — "the strict test cost 450 good insertions": verify the exemption is sound (an own field's Global
   always round-trips?).
2. **Add import.** The rule table (own module none; not imported → `import M using name` after the last import; open
   import none; aliased none — `ModuleHeader.imports` dies on a duplicate module import, so no edit exists; `using`
   list without the name → `; name` appended, inside braces when braced; `hiding` with the name → delete the item or
   the clause). Probe each row live through the scripted client with the edit APPLIED and re-checked: the braced and
   the laid-out `using` list forms; a `hiding` list of one; a `hiding` list of three with the name in the middle
   (separator handling); a candidate set of two modules (two actions, `isPreferred` on neither); the 6.5 pinned gap
   (`import Maybe using isJust` + `isNothing`) now closed — confirm the 6.5 negative pin was updated, not deleted;
   CRLF fixture; a name exported by an open sibling not yet saved. Candidates collapse through `termNameOrigins` to
   the ORIGIN module — so for Prelude's re-export of Bool.not the action says `import Bool using not`, not Prelude:
   is that what a user wants when their file imports Prelude openly? (The open import row says "none" — check that
   the Prelude case really yields none.)
3. **Add signature.** Insertion at (first equation line, col 0) with copied indent; head from `SName.form`; flat
   rendering; `source` action "add all missing signatures (N)" with edits line-descending. Probe: an operator head
   `(+) a b = ...`; a backtick head; a head inside `private`; a group whose first equation is preceded by a comment
   line; a nullary equation; a group already signed (none); staleness → `[]` (index version ≠ buffer version — is
   that too strict? a codeAction fires on every cursor move and the debounce is 300 ms, so during typing the menu is
   empty; acceptable, stated?). Apply "add all" on a fixture with 3 unsigned groups and re-check clean.
4. **Request path.** codeAction 51 ms on the FIRST request after a check, 0.1-0.4 ms after (memo keyed uri+version):
   what does the first request compute (all candidate actions for the whole file?) and is 51 ms on Report.e the
   worst case or a small file's? Re-measure on Report.e. Nothing parses/checks on the request path — read it.
5. **The printer ticket** (report §7): four shapes (nested `* ->` loses parens; exists-binder kind names an
   unquantified kind var; `ppType` operator cases write `n_Module` regardless of Qualification; concrete-row field
   Globals do not round-trip — not the printer). Reproduce one probe each; is the ticket accurate and correctly NOT
   fixed here (Pretty.scala would be a shared-printer change touching .ei bytes → Tier 1)?
6. **Gates, re-run ONCE.** compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly *TestQuickFix
   *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestRenamer*'` (94/94; QuickFix 18); `corpus-run.sh
   --batch <outdir>` 85/69/0; `repl-smoke.sh` 8/66 goldens clean; `lsp-smoke.sh` 454 (list the 47 new by fixture);
   boot 129; `.ei` 0; Report.e round trip one pair (implementer's spread 1.27-2.41 s is wide — was the machine
   loaded? your load must be < 1.5).
7. **The report.** Accurate? Gaps stated (type names out of scope — an "undefined type" note has no spelling and
   carrying one is Subst → Tier 1; operators unreachable)?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), the reproduced sweep
table, gate table (implementer vs yours), verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why). STOP after the report.
