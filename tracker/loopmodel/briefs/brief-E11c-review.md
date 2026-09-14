# Brief: review of E11c — the cause of the SET class, flagged fix (1 h)

Repo `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD `ebd2de1b` plus the implementer's
UNCOMMITTED working-tree change (five files: `SCC.scala`, `Binding.scala`, `syntax/Statement.scala`,
`Constraints.scala`, `Subst.scala`; `git diff` is the change under review). Under review:
`tracker/loopmodel/E11c-SOLVEDET.md`, written against `tracker/loopmodel/briefs/brief-E11c.md` (read the brief first).
The implementer's scratch is `<s>` = `/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11c/`.
Your scratch: `<s>/../e11c-review/` (create it). You change NO source, NO Lean, and NO tracker file except your
review `tracker/loopmodel/E11c-REVIEW.md`. Delete every `.ei` you cause under `core/target`. Never `lake build`;
never commit; never flip a default. Budget 1 hour; at the budget, write up what you have.

Per `tracker/GATE-POLICY.md`: CITE the implementer's logs by path for every figure you accept; re-run only the
targeted suites for the code under review and what you dispute. No whole-corpus looptrace, no full `core/test`.
`g1-validate.sh`, `ei-diff.sh` snapshots and any test that writes `.ei` into `core/target` must NOT overlap each
other (run those serially; everything else may run in parallel).

## What to do

1. **The change itself.** Read the diff. The claim is "no rule, guard or verdict reads either order": (a) the SCC
   driver walking the vertex list in source order is a different but equally valid topological order of the
   condensation — check that nothing downstream (`inferBindingGroupTypes`, the editor's per-SCC cache in
   `TolerantCheck`, the `.ei` writer) assumed the old order; (b) `Subst.scala:1630`'s saturated set is now SORTED by
   `Q.canonLt` before `reduce` — check that this is the ONLY consumer whose output depends on that list's order (the
   first draft of the report listed `resolvents`, `concRows`, `learnPartitions`, `liveInput`, `topFamilies` as
   inheriting the tree order: are those inside the solve the Lean model replays, and does the sort touch them?), that
   `canonLt` is a TOTAL order on the elements that can occur (ties? two partitions with the same sorted ids, labels
   and lhs?), and that the sort is invariant under a constant id shift as claimed. Read `GenRules.solveDet` and its
   `Session.interfaceKey` token.
2. **Close the implementer's NOT DONE items 2 and 8** (report §7): (a) OFF byte-identity on the FINAL build —
   `tracker/tools/ei-diff.sh --batch --snapshot <dir> "-Dermine.loadInSeries=true"` then `diff -r <s>/ei-pre <dir>`,
   expect empty; (b) `tracker/tools/ei-classify.py <s>/ei-pre <s>/ei-on` (the ON snapshot landed at 22:23) —
   expected identical / order-only / alpha everywhere except `lookbackJoin` and `drilldownKeyValueTable2`; classify
   those two by hand (the report says each loses ONE entailed conjunct: check the entailment as E11a-REVIEW did for
   `lookbackJoin`, i.e. derive the dropped conjunct from the survivors). Remember `ei-classify.py`'s known matcher and
   parser defects (E11a-REVIEW "The 47"): a red from it needs a hand re-check, not a verdict.
3. **Re-run the targeted suites on the FINAL build under ON**: `sbt -Dermine.solveDet=true 'core/testOnly
   *TestLoopTrace'` (must be 720/720 — the report's figure may be from the intermediate build), `corpus-run.sh
   --batch` under ON vs OFF (verdicts identical), and the two E11a properties in `TestTolerantCheck` under ON
   (`"E11a: four cold checks..."`, `"E11a: the corpus sweep..."`; the fixture's session-option mechanism if the flag
   is per-session, else `-D`): report their FORM/KIND/SET figures.
4. **The two survivors.** `lookbackJoin`: the report says it is stable over six cold checks of its own module but
   moves across the sweep's larger base jumps. That is either a THIRD order read or a relative-order change (the
   two runs minting different variables, or a dependency read from `.ei` on one run and inferred on the other).
   Decide which from `<s>/exp-lbj.log` and the sweep logs; if you can, reproduce with two loads at very different
   bases and diff the traces the way step 1 of the implementer's brief did. `cutoffGroupedFldsPosNegRel'`: confirm
   it is the variable-split case (E11b-PROBE §5.4) and not an order read. Say for each whether it is "beyond a
   solver re-ordering" or "one more local read", with evidence.
5. **Adoption readiness.** The report says published signatures get strictly smaller on two bindings under ON. If
   the user flips the default this is a Tier 2 adoption (`sbt core/test` in full, interleaved batch A/B, g1
   baseline re-cut with before/after). List what the adoption commit would need that is not yet done, and any
   reason NOT to adopt that you can see.

## Review `tracker/loopmodel/E11c-REVIEW.md`

Verdict first: ACCEPT / ACCEPT WITH FIXES / BLOCK, with items R-1.. (blocking marked). Then per point: what you
did, what you found, the log path. State what you did NOT check. Time spent. Plain language.
