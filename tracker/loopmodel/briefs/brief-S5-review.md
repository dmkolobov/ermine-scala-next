# Review brief: S5 — the tautology deletion (C12, now DEFAULT ON) and the `.ei` solver-configuration key

You are reviewing stage S5 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `f02bc3a`
plus the UNCOMMITTED deliverables). Implementer's brief `tracker/loopmodel/briefs/brief-S5.md`; report
`tracker/loopmodel/S5-HYGIENE.md` (§0-§4 the original delivery, then `## Follow-up: publishing-only deletion` which
supersedes §0/§4's verdict: `-Dermine.tautoDelete` flipped to DEFAULT ON after the second restriction met the
brief's criterion (c)). Changes: `tracker/lean/Rowpartition/Determined.lean` (`tauto_delete`, `tauto_delete_two`,
`ScanCount.count_tautology`, `TautoEmpty.tauto_empty_not_deletable`), `Subst.scala` (`deleteTautologies`, the
`publishing` parameter through `inferBindingGroupTypes` → `inferImplicitBindingTypes` → `generalize` →
`mkSimplified`), `Constraints.scala` (`GenRules.tautoDelete`, fingerprint token `+tauto`, OPEN GAP comments →
CLOSED), `Session.scala` (`interfaceKey` = `2|<GenRules.toString>` written as the `.ei`'s first line, checked in
`dep`'s `preCk` between the mtime test and the parse; missing/mismatched = stale), `tools/G1Compare.scala`
(`splitInterfaceKey`), NEW `scalacheck-binding/src/main/scala/TestInterfaceKey.scala`, `tracker/tools/ei-classify.py`
(reads the header as a `<<key>>` pseudo-binding), ticket C12, plan row S5, state file notes, memo rank 6 note. You
edit NOTHING except a scratch directory `/home/dmitry/.claude/jobs/880c725d/tmp/review-S5/` and your report
`tracker/loopmodel/S5-REVIEW.md`. ONE JVM at a time (`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, sbt
allowed); `sbt core/compile core/copyResources` before any `bin/ermine` gate; Lean via `lake env lean <scratch>`
(built; one confirming `lake build` fine; never while a `looptrace` runs); delete every `.ei` you cause; no commits.
Per `tracker/GATE-POLICY.md` this is an ADOPTION commit (a default flips): you re-run Tier 0, Tier 1 (the sweep
and the trace comparison) and Tier 2 (`sbt core/test` ALONE on the tree) ONCE; your numbers go into the trackers.

1. **The theorem.** `tauto_delete`: `REquiv ⟨ex ∪ P, insert (mk r P ∅) G⟩ ⟨ex, G⟩` for `P.Nonempty`, `r ∉ P`, every
   part fresh w.r.t. `G`. Re-elaborate; check the side conditions are all used (drop each and try to refute);
   confirm the necessity witness `tauto_empty_not_deletable` and how this relates to R3's `dead_delete_*` (mirror
   image: parts vs lhs). Is the Scala-only fourth exclusion (a repeated part, invisible to `Finset`) real, and does
   `deleteTautologies` implement EXACTLY the theorem's side condition — no wider (a concrete label, a part occurring
   in another published constraint, a universal part, `r` itself among the parts, an existential that is also the
   lhs of another constraint)? Build a probe module for each near-miss and show it is NOT deleted.
2. **The publishing restriction.** The `publishing` parameter: confirm the only `true` sites are the module top-level
   group (`Subst.checkModule` / `Session.loadModule` → `inferBindingGroupTypes`), that `let`/`where`/`Lam`/annotation
   generalisations, `trySolveOn` and `subsumeType` keep `false`, and that it is a parameter, not a global (the
   re-entrancy argument). Then the sweep, re-run by you as the single-build flag A/B (`ei-diff.sh --batch <out>
   "-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.loadInSeries=true -Dermine.tautoDelete=false"` against the default):
   3477 / 0 / 0 / 4, and at byte level exactly `Layout/Scan.ei` differing on exactly four lines with the key header
   stripped — reproduce. The four: `count` 1→0, `count'` 2→0, `sumBy` 3→2, `avgBy'` 3→2. Are the shortened
   signatures the ones a reader expects (write them out before/after)?
3. **The key.** Format `2|<GenRules.toString>`: is version 2 justified by an actual format change (the header line
   itself)? Where is it checked — reproduce cold write / warm read = Interface / flag flip (`-Dermine.topNormalise=
   false`) = Full + rewrite / missing key = Full / a NON-key flag flipped = still Interface — and list what the
   implementer excluded from the key and whether the exclusion is right (`rowTrace*`, `loadInSeries`,
   `foreign.tolerant`, `useInterface`, `typeCheck`, `solveBudget`? — which of these can change published bytes?).
   The header-strip trap (`InterfaceParsers.interfaceSigs` accepts no leading comment or blank line; a mistake makes
   every module recheck silently): verify with `G1Compare --pair` or the LSP boot log that interfaces are actually
   READ (method = Interface) after a warm load. The 143 checked-in unkeyed baselines: `G1Compare` and
   `TestTolerantRead` still pass. `TestInterfaceKey`: it was bitten twice by process-global state (system
   properties; `depCache` with concurrent properties) — read the final fixture and say whether any flake risk remains
   (run it 5x, and once inside the full suite).
4. **Gates, re-run once (adoption commit):** `lake build` 870 + `Audit.lean` 4,596 / 0 and `#print axioms` on the
   new declarations; `TestLoopTrace` 720/720; `corpus-run.sh --batch` 85 / 69 / 0 over 154 with the verdict listing
   byte-identical to a pre-change run (messages included); `trace-ab.py` pre-change build vs this build on `boot`
   and `Wide` (IDENTICAL, sinmoved 0) — build the pre-change compiler in scratch as F3's reviewer did; `sql-render.sh`
   byte-identical; `repl-smoke.sh`; `lsp-smoke.sh` 181; `sbt core/test` ALONE 940/940; the interleaved perf A/B is
   NOT required (the simplifier is post-loop and the boot has four affected signatures) — say so.
5. **The adoption itself.** The deletion is now shipped behaviour: state plainly what a user sees (four stdlib
   types shorter; any inferred type in user code whose published residual carried such a tautology is shorter too —
   estimate how common that is from the sweep), the rollback (`-Dermine.tautoDelete=false`), and that S5.2 made
   this the first adoption needing no manual cache wipe (verify: an `.ei` written before the flip is rebuilt on the
   next load because the key changed). Prose: ticket C12's two corrections, plan row, state-file notes, memo rank 6
   note, the `ei-classify.py` change, and the stale sentence in `LOOP-MODEL-HANDOFF.md` (the orchestrator fixes that).

Findings prefixed `Q-`, ranked, CONFIRMED (you ran it) or PLAUSIBLE. Verdict: ADVANCE / FIX-THEN-ADVANCE / REDO.
Write the report early and keep it current.
