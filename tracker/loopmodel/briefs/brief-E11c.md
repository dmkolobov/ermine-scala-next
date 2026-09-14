# Brief: E11c — the CAUSE of the SET class: make the solver's residual a function of the source (3 h)

Repo `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD = the commit "E11b Phase 1" (run
`git log --oneline -1`). You work in the MAIN checkout (nothing else runs there). Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11c/` (create it).
Toolchain/PATH notes: `~/.claude/projects/-home-dmitry-research-ermine/memory/ermine-scala-toolchain.md`. Follow
`tracker/GATE-POLICY.md`: parallel by default; but `g1-validate.sh`, `ei-diff.sh` snapshots and any test that writes
`.ei` into `core/target` must NOT overlap each other; never `lake build` while a `looptrace` binary runs; delete every
`.ei` you cause (`find core/target -name '*.ei'`); never commit; never flip a default. Budget 3 hours wall clock; at
the budget write up and stop. Report: `tracker/loopmodel/E11c-SOLVEDET.md`. No other tracker file changes.

## The problem and the decision behind this stage

Ticket E11 (tracker/TICKET-stdlib-findings.md E-section) / roadmap "Interstage item E11" (tracker/LSP-ROADMAP.md):
two COLD checks of one unchanged module in one JVM publish, for 5-8 bindings, two different residual constraint SETS
(entailment-equivalent; the run of record: `Relation.e:lookbackJoin`, `Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'`,
`Present/WriterOutputs.e:reportFor`, `Yahoo.e:investmentTableData`, `Yahoo.e:joinCumRet`, `Yahoo.e:joinTotalValue`).
E11a fixed the FORM. E11b (canonicalising the SET at publication by entailment deletion) was explored and REJECTED by
the user on 2026-09-13: `tracker/loopmodel/E11b-ORACLE.md` §1, §6 and its review show deletion closes 1 of 6 and the
approach is whack-a-mole (order-independence is coNP, ROSE-COMPARISON.md §4.3). The user's word: attack the CAUSE.
The only thing that differs between the two cold checks is the id base (the `Supply` has advanced; `Resident.checkFile`
with a fresh `Documents`). The dequeue order was already made base-invariant (`dequeuePolicy=smallcanon`, the default;
tracker/ROW-CONSTRAINT-STATE.md ~line 307), yet the class persists, so some OTHER choice on the solve path still reads
an absolute id. The strongest suspect: `V.hashCode = 38 + n * 17` (`core/src/main/scala/com/clarifi/reporting/ermine/Type.scala:169`),
so every hash-ordered `Set[TypeVar]` / `Map[TypeVar, _]` iteration on the solve path is a function of the base.

Read first (30 min): tracker/GATE-POLICY.md; the roadmap E11 section (E11a's DONE paragraph says how E11a audited
`Canonical` for id-independence: "every `.id`, `Set`, `Map`, `toList` audited; adversarial probe 0 mismatches of 6,591
for id renumbering" — that is the method); `tracker/loopmodel/E11a-CANON.md` §4 (the sweep, `logs/sweep-*.tsv` format)
and §10 (traces); `tracker/loopmodel/E11b-PROBE.md` §5-6 (the exact leftover per binding, `lookbackJoin` by hand);
`tracker/loopmodel/E11b-ORACLE.md` §6 (what the two variants of each pair look like); ROW-CONSTRAINT-STATE.md's
`smallcanon` paragraph and the "Cross-reference (2026-09-10)" paragraph near its end; `RowTrace.scala` (record kinds;
`-Dermine.rowTrace=<path>`), `tracker/tools/trace-ab.py` (its header explains the record kinds and the id-erasing
PERMUTATION-ONLY classification) and `tracker/tools/looptrace-corpus.sh`; the E11a form properties in
`scalacheck-binding/src/main/scala/TestTolerantCheck.scala` (`"E11a: four cold checks of one module publish ONE form
per constraint set"` at ~:1766 and `"E11a: the corpus sweep — two cold checks publish ONE form"` at ~:1822 — the
second pins SET as a CEILING of 6 and names the survivors in its failure message).

## Steps

1. **Locate (measurement, no source change).** Take `Relation.e` (`lookbackJoin`, 8 vs 9 constraints, the smallest
   case). Produce the row trace of its check at two id bases that publish DIFFERENT sets (the E11a property's cold
   checks, or `Resident.checkFile` twice in one JVM, or two batch loads with a different number of modules loaded
   before it — whatever reproduces the two variants fastest; say what you used). Diff the two traces with
   `trace-ab.py` (ALL record kinds) and find the FIRST record where the two runs diverge in something other than an
   id renumbering. Name the solver step and the code site (file:line) whose choice differs, and the mechanism (hash
   iteration order of a `Set[TypeVar]`; a `Map` keyed by `V`; `sortBy(_.id)` across a base boundary; a cache such
   as `Session.depCache` hit on one run and missed on the other; anything else). Repeat on ONE `Yahoo.e` binding if
   the first case's mechanism does not obviously cover it. Log every command.
2. **Audit.** Walk the publication path — `Constraints.scala`'s solver loop (queue, `makeConcrete`, split, `learn`,
   `step`, the per-label decision), `Subst.solve`, `reduce`, `mkSimplified` (`isolated`, the `partition`s, `distinct`,
   `deleteTautologies`), `generalize` — and table EVERY place a choice depends on a `TypeVar` id: cite file:line,
   the construct (`Set` iteration / `Map` iteration / `hashCode` / `sortBy id` / `toList`), and classify it
   BASE-INVARIANT (relative order of ids minted in the same sequence; a structural key) or BASE-DEPENDENT (absolute
   id value or hash). E11a's audit of `Canonical` is the template. Say which entries the step-1 divergence touches.
3. **STOP POINT.** If the divergence's cause is NOT a local order read (e.g. a cache hit/miss, a deliberate policy
   with a theorem behind it, or the ids differ in RELATIVE order because the two runs mint different variables), then
   write the report with steps 1-2 and a one-paragraph recommendation and STOP. The user has said: if this is not
   fruitful, do not chase it.
4. **Fix, flagged** (only if step 3 passed): `-Dermine.solveDet=true|false` (or a better name; read once at class
   init like `Constraints.GenRules` does, and note whether it must enter `Session.interfaceKey` — it changes what is
   published, so yes unless you show otherwise). Default OFF in this stage: OFF must be byte-identical to today.
   Under ON replace the base-dependent choices found in steps 1-2 by base-invariant ones (an ordering by a structural
   key such as `Canonical.key`'s ingredients, or by relative minting order — say which and why; do NOT change what
   the solver decides, only the order in which equal-priority choices are visited). Keep the change small and local;
   if it grows beyond the sites the audit named, stop and report.
5. **Measure and gate under ON.** (a) The E11a form properties with the SET ceiling read under the flag: run each
   3x; report FORM and SET counts (target SET 0; any survivor explained by a named cause). (b) Two-base stability:
   the corpus sweep at two id bases (E11a §4's method, or `ei-diff.sh --snapshot` of two builds/loads), SET 0.
   (c) Tier 0. (d) Tier 1: `looptrace-corpus.sh` ON vs a pre-change run through `trace-ab.py` (expect
   PERMUTATION-ONLY or explained CONTENT diffs; verdicts identical), `TestLoopTrace` 720/720 (the model agreement
   invariant — if this goes red, the change altered a decision, not an order: stop), `corpus-run.sh --batch` verdicts
   identical to before, `ei-diff.sh --batch` OFF-vs-ON classified with `ei-classify.py` (expected: identical /
   order-only / alpha for everything except the SET-class bindings, which should become ONE of their two known
   variants — classify those by hand against E11b-PROBE §5 and say which variant won), `g1-validate.sh` (baseline
   untouched under OFF; under ON report the drift and do NOT re-cut). Respect the no-overlap rule for g1/ei/.ei
   tests. (e) Under OFF: `ei-diff` against a pre-change snapshot IDENTICAL, `TestTolerantCheck` unchanged.
   Perf: one interleaved `perf-bench.sh batch -n 3` OFF/ON/OFF/ON when load < 1.3, run alone, reported as a
   figure not a verdict (adoption is the user's).

## Report `tracker/loopmodel/E11c-SOLVEDET.md`

Answer first: the cause (mechanism, file:line), whether it was fixable locally, and the SET count under ON. Then
the step-1 trace diff as an argument a reader can follow; the audit table; the change (diff summary, the flag, the
interface key); every gate with its figure and log path; NOT DONE; time spent.

## Acceptance (five points)

1. The first divergent solver step between two cold checks of `Relation.e` is identified with the code site and
   the mechanism, from a trace diff whose log is in scratch.
2. The audit table covers the whole publication path with file:line per entry and a BASE-INVARIANT /
   BASE-DEPENDENT classification.
3. Either the STOP POINT fired and the report says why in one paragraph, or the flagged fix exists with OFF
   byte-identical (ei-diff identical, TestTolerantCheck unchanged) and no default flipped.
4. If fixed: SET count 0 (or every survivor explained) on the E11a properties x3 and at two bases; Tier 0 green;
   Tier 1 under ON with TestLoopTrace 720/720, corpus verdicts identical, every `.ei` move classified.
5. Nothing committed; no `.ei` left under `core/target`; written up inside 3 hours with NOT DONE listed.
