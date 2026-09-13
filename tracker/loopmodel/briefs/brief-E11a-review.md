# Review brief: item E11a — a canonical FORM for published schemes (ADOPTION: Tier 2, interface classification, g1 re-cut)

You are reviewing item E11a in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `9976b78d`,
code identical to `8a8455ce`; plus the UNCOMMITTED deliverables: `core/.../ermine/Type.scala` (+234, the canonical form
and its keys), `core/.../ermine/Subst.scala` (30/2), `core/.../ermine/Pretty.scala` (14/1, labels sorted),
`core/.../session/TolerantCheck.scala` (45/53, `displayScheme` now on the shared key), `scalacheck-binding/.../
TestTolerantCheck.scala` (136/1), the RE-CUT `tracker/g1-baseline/` (browse.txt 95/95 + 38 `.ei`), and the report
`tracker/loopmodel/E11a-CANON.md`). NOTE: the implementer was stopped by an accidental interrupt during its Tier 2 run;
the orchestrator re-ran Tier 2 and filled the report's §11 (performance), §12 (gates) and §13 (numstat) from the
implementer's logs — those three sections are the orchestrator's prose over the implementer's numbers, and you check them
like any other claim. Implementer's brief `tracker/loopmodel/briefs/brief-E11a.md`; item of record `tracker/LSP-ROADMAP.md`
§ "Interstage item E11"; ticket E11 (`tracker/TICKET-stdlib-findings.md`, incl. its prohibition on closing by alpha-
equivalence); `tracker/ROSE-COMPARISON.md` rank 3 and §4 (`IsCanonicaliser`, `OrderIndependent`);
`tracker/ROW-CONSTRAINT-STATE.md` (solver-order sensitivity, `smallcanon`, the per-label decision tooling);
`tracker/GATE-POLICY.md` (Parallelism rules; ADOPTION tier). You edit NOTHING except a scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-e11a/` and your
report `tracker/loopmodel/E11a-REVIEW.md`. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed. No commits, no `git stash` (instrument by copy, restore by copy, verify by md5). Do not touch `tracker/lean/`.
Delete every `.ei` you cause (`core/test` drops them too). No lingering polling shells. The before build is READY at
`/home/dmitry/research/ermine/ermine-scala-wt-e11a` (worktree at the pre-change code, compiled, its own
`tracker/repl-classpath.txt` and `target/ermine-classpath` regenerated — do not revert or commit that file). The
implementer's logs are under `<scratch>/e11a/logs/` and its sweep/probe sources under `<scratch>/e11a/` (cite what you
reuse). Wall-clock budget 3.5 hours.

1. **THE RULE — attack its id-independence, not its taste.** Read `Type.scala`'s canonical form (the file's header
   states the rule by hand: body variables coloured by first occurrence; constraints keyed by structure with labels
   sorted; existentials coloured by iterated refinement over the keys of the constraints that mention them, four
   rounds capped; a tie fixpoint, "rule 7"). (a) Grep the key and the refinement for every `.id`, `hashCode`,
   `Set`/`Map` iteration and `toList` and show each is either order-insensitive or ordered by an id-free key — one
   table, no exceptions. (b) Build the adversarial probe: take five published schemes with ≥ 3 existentials (the
   report's `Relation.lookbackJoin`, `Layout/Chart.seriesW`, `Keyed.keyValueTabular`, and two of your choice from
   `Relation/Op`), apply a RANDOM bijective renumbering of every variable id and a random shuffle of every list
   (binders, constraints, right-hand sides, label sets) BEFORE canonicalisation, ten seeds each, and assert the
   rendered output is byte-identical to the unshuffled one. A scratch `runMain` under `scalacheck-binding/` is fine;
   delete it after. (c) Is the four-round cap ever reached on the corpus (does the report count refinement rounds)?
   Construct a scheme where two existentials stay indistinguishable after refinement (an automorphism — two
   symmetric row variables) and say what the tie fixpoint does with it: deterministic, or dependent on the input
   order? If the latter, that is a finding with the witness. (d) `OrderIndependent` (ROSE §4) is NOT claimed — two
   `REquiv` sets may still render differently; confirm the report says so and that the SET class is exactly that.
2. **THE 47 "OTHER" PAIRS.** `ei-classify.py` before-vs-after (`logs/ei-classify-ba2.log`): identical 2461,
   order-only 1000, alpha-equivalent 15, **other 47**. The brief's gate was NONE in other; the report claims a
   complete matcher shows them alpha/order-equivalent and explains why the tool's matcher fails. Re-check
   INDEPENDENTLY: your own matcher (or `scalacheck-binding/AlphaEq.scala` through a scratch harness) over all 47,
   each pair's verdict listed; then say whether `ei-classify.py` needs its matcher fixed (a follow-up ticket, not a
   change here) and whether any of the 47 is a real type change. `Relation.lookbackJoin` (report §7) is the one
   binding whose constraint SET moved between before and after: verify with the per-label decision tooling
   (`ROW-CONSTRAINT-STATE.md` A1's "complete per-label decision") that old and new sets are entailment-EQUIVALENT,
   not weaker or stronger; if the tooling cannot decide it, say so and hand-derive it.
3. **TWO-BASE STABILITY — the item's purpose.** `logs/ei-classify-2base.log`: two after-side snapshots at different id
   bases, 6 of 274 interfaces differ (5 other + 1 order-only). Reproduce with YOUR OWN two bases (e.g. a warm-up load
   of a different module before the snapshot, and `-Dermine.loadInSeries=false`): the differing set must be exactly
   the SET class the report lists (E11b's targets — the report says six bindings in §14 and five in some sweeps;
   reconcile the count and list them by def-site), and every other interface byte-identical. Then the editor: run
   `<scratch>/review-7.2/nondet.py` (or the implementer's `logs/nondet-after.txt` recipe) for six cold rounds on
   `WriterOutputs.e`: `reportFor` renders in exactly TWO forms (the SET pair), never four; `asDocument` and
   `writerOutputs` in one.
4. **THE CORPUS PROPERTY.** `TestTolerantCheck`'s new property runs two cold checks of every clean module and splits
   the differences into FORM (asserted 0), KIND (3 — what is that class? the report names it; verify each of the 3 at
   source and say whether it is a form defect the rule should cover or a real second frame) and SET (pinned as a
   ceiling with def-sites). Confirm the assertion is on RENDERED STRINGS, not alpha-equivalence (ticket E11 forbids
   the loosening). Confirm the property's runtime (two checks × 253 modules — how long does `TestTolerantCheck` take
   now vs 6.2c's run?) and that it is deterministic (run it twice; the SET list must not move).
5. **THE g1 RE-CUT.** 39 files. `g1-diff.sh compare <old baseline> <new baseline>` must be EQUIVALENT
   (`logs/g1-oldnew.log`; re-run it from `git stash`-free copies: `git show HEAD:tracker/g1-baseline/...` into a
   scratch dir). Classify the 95 browse.txt line changes (rhs order / binder order / label order / constraint order)
   with counts; anything that is not one of those four classes is a finding. Confirm `g1-validate.sh` 9/9 on the
   final tree and that the drift tripwire's own comment ("never re-cut the baseline to make it green; explain it")
   is honoured by the report's §6 explanation.
6. **TRACES.** After side (`logs/lt-after.log`): 18 groups, agree = segments, skip 0 — reproduce once in parallel
   (`LOOPTRACE_PAR=3`, main tree). Read `logs/trace-ab.log`: `KINDCOUNT-DIFFERS` on Ai (5,937), Wide (2,558),
   Algebra (477) means the solver did DIFFERENT WORK there. Corpus verdicts are identical and interfaces equivalent,
   so the work differs without changing results — but the per-file corpus times show `Wide/WardRoster.e` 1.44 -> 0.69 s
   (−52 %) and `Ai/IncidentSeverity.e` −24 %. Attribute one of them: mint counts before/after on that module (the trace has
   them); say whether canonical order changed the solver's path in a way `ROW-CONSTRAINT-STATE.md`'s keyed-split
   guarantees still cover (they should: the guards are order-independent by proof — cite the theorem), and whether
   any module got SLOWER by > 10 % (the report says none; verify from `<scratch>/e11a/cb-*/` vs `ca-*/`).
7. **THE PRINTER CHANGE.** Labels sort by name UNCONDITIONALLY (no `canon=off` for it). Every consumer moves:
   error messages with rows, browse, `.ei`, hover, REPL. `repl-smoke.sh` 8/66 and its goldens did NOT move — check
   WHY (do the goldens contain no multi-label concrete row, or were they already in name order?); if a golden would
   have moved and did not, that is a finding. Hover a stdlib binding with a multi-label row through the real server
   and confirm the sorted form.
8. **FLAG AND STRICT PATH.** `-Dermine.canon` = `publication` (default) / `all` / `off`. Confirm the default flip is
   declared as an ADOPTION in the report and roadmap, that `off` restores the pre-E11a DATA form byte-for-byte on one
   `.ei` (compare against the worktree's), and that the 6.2c local-head display (`displayScheme` on the shared key)
   renders every 6.2c pin unchanged (lsp-smoke 573 says so; hover `LetAndPatternMatching.e` and `Heads.e` once).
9. **TIER 0 RE-RUN ONCE** (parallel): compile; TestLoopTrace 720/720; `TestTolerantCheck` (57) with both sweep lines
   quoted and the 6.2b/6.2c pinned sets unchanged; corpus verdicts 89/79/0 of 168 both sides; repl-smoke; lsp-smoke
   573; boot 129; `.ei` 0; diff parity; line endings — `Type.scala` and `Pretty.scala` are CRLF and must stay so
   (`file` on each; a `git diff` that shows `^M` churn is a finding).
10. **TIER 2**: the orchestrator's run is at `<scratch>/e11a/logs/core-test-2.log`; run the full `core/test` ALONE
    once yourself (expect 1068 + the item's properties, 0 failed), E12/E13 one re-run each. Record wall time.
11. **REPORT** `tracker/loopmodel/E11a-REVIEW.md`: verdict first (ACCEPT / ACCEPT WITH FIXES with numbered R-items,
    file:line, one-line change / REJECT); what you refuted with command and output; the id-independence table and the
    adversarial probe result; the 47 verdicts; the two-base result; the g1 classification; the trace attribution;
    every gate with figure and log path; the E11b target list you confirm; NOT CHECKED. When done: no JVM of yours,
    no `.ei`, no probe source in the tree, worktree untouched apart from its `repl-classpath.txt`, and `git status
    --short` showing exactly the implementer's files, the g1 re-cut, the review brief and your report.
