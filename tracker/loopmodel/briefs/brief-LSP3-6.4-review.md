# Review brief: LSP Stage 3 item 6.4 — document symbols and workspace symbols

You are reviewing item 6.4 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `498dbbc`
plus the UNCOMMITTED deliverables: new `lsp/Symbols.scala`; `lsp/Definitions.scala`, `Diagnostics.scala`,
`Resident.scala`, `Main.scala`; `scalacheck-binding/src/main/scala/TestRenamer.scala`; `tracker/tools/lsp-client.py`;
fixture `tracker/lsp-tests/Syms.e`; `docs/lsp.md`; report `tracker/loopmodel/LSP3-6.4-SYMBOLS.md`). Implementer's brief
`tracker/loopmodel/briefs/brief-LSP3-6.4.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.4 with the STAGE-3
INVARIANTS and Decision (c); gates `tracker/GATE-POLICY.md`. You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.4/` and your
report `tracker/loopmodel/LSP3-6.4-REVIEW.md`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs, no lingering polling shells; `sbt core/compile
core/copyResources` before any `bin/ermine` gate; delete every `.ei` you cause (the boot writes 129 into the target
module tree); do not touch `tracker/lean/`; no commits. Confirm first: no file outside `core/src/main/.../lsp/` changed
in `core/src/main` (the implementer says so) — then the tier is Tier 0; and `git diff --stat` equals `--stat -w`.

1. **The kind mapping and the merge rule.** Groups merge a spelling's sigs and equations within one BINDING SCOPE;
   class bodies are their own scope (Method). Probe: (i) a sig with TWO names (`a, b : Int`) and equations for
   both — two symbols, each with the right range?; (ii) a name with a sig at top level and equations inside a
   `private` block (are those one scope or two? what does the renamer do — `moduleTerms` — and does the symbol
   builder agree?); (iii) an operator equation `(+) a b = ...` with a fixity line — one symbol, fixity in detail,
   no fixity symbol; (iv) a `data` with a constructor named like the type (`data Color = Color Int`) — Struct with
   one Constructor child, no duplicate; (v) `Enum` only when EVERY constructor is nullary — a mixed one is Struct;
   (vi) a `where` block's bindings — NOT symbols (top-level groups only), or are they children? the brief did not
   ask for nesting into where blocks; check what ships and that it is stated; (vii) `SErrorStatement` mid-file —
   neighbours still listed, and the broken statement's extent does not swallow the next group's range;
   (viii) `range` contains `selectionRange` and children inside parents — the corpus property asserts it; make sure
   it also asserts the symbols are SORTED by position and that no two sibling ranges overlap (they should not, for
   top-level statements — a sig on line 3 and its equation on line 9 with another group between them is ONE symbol
   whose range spans the other group: is that a containment violation for a client? The spec says children must
   be inside the parent, siblings may overlap — say whether clients (VS Code outline) render that sanely, and
   whether the group should instead be split or its range set to the equations' extent only).
2. **Workspace symbols.** Source, dedupe, ranking (exact/prefix/substring/lower/container), cap 200, empty query =
   open buffers only; the stdlib list built ONCE after boot (36 ms, 2157 globals). Probe: a query during boot
   (`[]` not null, and no wait); a query after a stdlib module has been OPENED in the editor and then edited — does
   the open-buffer copy shadow the stdlib entry (dedupe by (module, name)) and follow the edit?; a re-export
   (Prelude's `not`) — one entry at Bool.e, not two; `Relation` the type is Builtin — confirm absent, and that the
   substring query `elation` still finds `SoftRelation` etc.; the 200 cap on a one-letter query — which 200, and is
   the ranking stable across calls; case: `not` vs `Not`. Cost: re-measure one warm query (< 5 ms claimed) and the
   list build.
3. **Request-path rule.** Nothing on `documentSymbol`/`workspace/symbol` parses, checks or infers: read the handlers.
   `Checked` grew? Memory per open document (what is now retained: module tree, renamed tables, contents, locals,
   symbols?) — is the symbol list built on the check path (13.5 → 14.0 ms index, so yes?) or lazily; either is fine
   if the round trip holds — the implementer says 1.24-1.30 → 1.26-1.30 s.
4. **Gates, re-run ONCE.** compile+copyResources; `TestLoopTrace` 720/720; `sbt 'core/testOnly *TestTolerantRead
   *TestTolerantCheck *TestEditorBuffers *TestRenamer *TestReplDifferential'` (71/71, TestRenamer 24 → 27);
   `corpus-run.sh --batch <outdir>` 85/69/0 over 154; `repl-smoke.sh` 8/66 goldens clean; `lsp-smoke.sh` 338 (list
   the 32 new checks); boot 129; `.ei` 0; Report.e round trip one pair (the symbol build is on the check path).
5. **The report.** Accurate against your numbers? The two corrected brief expectations (`Relation` is Builtin;
   foreign declarations are not term groups) — right calls? Gaps stated?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each), gate table
(implementer vs yours), verdict ADVANCE / FIX-THEN-ADVANCE (list) / BLOCK (why). STOP after the report.
