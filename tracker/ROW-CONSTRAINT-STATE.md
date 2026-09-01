# Row-constraint work — state as of 2026-09-01

## ADOPTED 2026-09-01

Both changes are now the DEFAULT in `Constraints.GenRules`:
`ermine.genRules` defaults to `cut`, `ermine.labelCheck` defaults to `true`.
`-Dermine.genRules=all -Dermine.labelCheck=false` restores the previous compiler
exactly. Nothing is committed.

Adoption gates, all against the NEW defaults with no flags:
- 66-file corpus vs restored-old-behaviour: 15 differing line-pairs, ALL explained —
  14 are fresh-variable ids (the cut mints fewer, so the `Supply` counter shifts) and
  1 is field print order on a provably identical row set.
- `shouldfail/`: 40/40 still rejected, 0 modules loading.
- Per-file over `incomplete/` + `ai/` (45 modules, one invocation each):
  **exactly 4 verdicts change, `unsound01`-`unsound04`, LOAD -> REJECT.** Nothing else.
- `core/test` with no flags: **903/904**, the one failure being the pre-existing
  `Constraints.disjunction sound` generator. 4:42.

The VS Code extension is installed (`clarifi.ermine-lang@0.1.0`, packaged with vsce);
`bin/ermine-lsp` shares `bin/ermine`'s classpath so the editor runs these defaults.

DEFERRED to a later session: diagnostics. Two of six label-check rejections
(`witness03`, `unsound03`) can only name the field, not the constraint, because their
offending constraint is not in the file being compiled.

Handoff note. Everything below is DONE and verified unless marked otherwise.
Authoritative documents: `tracker/TICKET-row-constraint-decision.md` (1303 lines,
§0–§9) and `tracker/lean/README.md` (per-theorem status + axiom audit).

## The recommendation

**Take `cut`. Do not take `nongen`.** See ticket §7.10 / §7.11.

`cut` = disable ONLY the fresh-minting `else` branch of `commonSubexpression`
(`Constraints.scala`, guarded by `GenRules.cseMints`). Keeps the reuse and
folding branches, `splitConcrete`, and `resolution`.

Verified: cliff gone (CoStar8 156s→0.04s, RowStress8 277s→0.11s); 1447 stdlib
signatures with 2 textual diffs both PROVED equivalent; 1581 example entries with
26 diffs all PROVED equivalent; should-fail corpus 40/40 rejected with identical
messages; `core/test` 903/904 (known failure only); `repl-smoke` 4/4.

`nongen` is UNSOUND: accepts 5 ill-typed programs (`der06`, `der07`, `der08`,
`inc08`, `mis02`) and falsifies `Constraints.join example`.

## Working tree (nothing committed)

Modified:
- `core/.../Type.scala` — cached `ConcreteRho.hashCode` (value unchanged; verified
  zero baseline drift). Independent of the cut work.
- `core/.../Constraints.scala` — `GenRules` mode switch + `CommonSubexpressionMint`
  provenance tag. **Default `all` is bit-identical to shipped behaviour.**
- `core/.../Subst.scala` — Stage 0 tracing calls in `solve` and `reduce`.
- `scalacheck-binding/.../TestSurfaceParsers.scala`, `TestStatementExtents.scala`
  — corpus count 180 -> 271 (`TestSurfaceParsers.scala` only). CAUTION: that file has
  OTHER `?= <digits>` assertions (`inner.size ?= 2`). Anchor the replacement on the old
  number; an unanchored `\?= \d+` clobbers them and the failure reads
  "Expected 271 but got 2".
- `core/test` result 2026-09-01 with everything in place: **903/904**, the one failure
  being the pre-existing `Constraints.disjunction sound` generator. 4:39.

Untracked:
- `core/src/.../RowTrace.scala` — Stage 0 instrumentation, inert unless
  `-Dermine.rowTrace=<path>`.
- `core/examples/Ai/` — 10 reports + `Common.e` + README (all compile).
- `core/examples/shouldfail/` — 40 must-be-rejected cases + `RESULTS.md` matrix.
- `core/examples/incomplete/` — incompleteness corpus + the 4 unsound modules.
- `core/src/test/.../DisjProbe.scala` — loader-free solver probe: reproduces the
  soundness bug in ~400ms with controls, instead of a 30s module load. Keep.
- `tracker/lean/Audit.lean` — whole-environment axiom audit.
- `tracker/TICKET-row-constraint-decision.md`, `tracker/lean/`,
  `tracker/tools/gen-row-overlap.py`.

## How to reproduce anything

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.genRules=cut" bin/ermine <file.e> </dev/null
_JAVA_OPTIONS="-Dermine.genRules=cut" tracker/tools/g1-diff.sh run new /tmp/g1-cut   # g1-diff resets G1_PROPS
tracker/tools/g1-diff.sh compare /tmp/g1-cut tracker/g1-baseline
python3 tracker/tools/gen-row-overlap.py --out /tmp/probe                            # cliff probes
```
Lean: `export PATH="$HOME/.elan/bin:$PATH"; cd tracker/lean; lake env lean Rowpartition/X.lean`

## The label-check rule (added 2026-09-01, after the cut work)

A SECOND finding, independent of the cut: the shipped solver **accepts unsatisfiable
row constraints** (`core/examples/incomplete/unsound0*.e`, 4 modules). Pre-existing;
identical under `cut`. See ticket §7.13 for the full write-up and §7.12 for why
re-enabling `Constraints.disjunction` is NOT the fix (it does not terminate on the
prelude, or on `Constraints.join example`).

The candidate fix is `Constraints.labelClash` + the call in `Subst.solve`, behind
`-Dermine.labelCheck=true` (default false). Refutation-only: emits no partition, mints
no variable, ranges only over labels in a `ConcreteRho`.

Gates green so far:
- 129 stdlib modules load, 11.11s vs 11.17s with the flag off
- `core/examples` + `ai` + `shouldfail` (66 files): output **byte-identical**, 297 lines
- `DisjProbe` solver-level probe: label rule 0/10 wrong, solver 2/10 wrong
- Lean `Rowpartition/LabelProp.lean`: soundness + mechanized incompleteness, 0 sorry

- `core/examples/incomplete/`, BOTH rule modes: exactly 4 modules newly fail
  (`Unsound01`-`Unsound04`, the known bugs), **0 newly load**. 2 diff hunks each.

BLAME (fixed): `Subst.solve` now finds the input `Part` mentioning the offending field
and dies at its loc, restricted to the current file. `unsound01` -> `104:18`, the
constraint itself. Two cases (`witness03`, `unsound03`) still fall back to the module
header because their constraint is not in the compiled file. NOTE: `Loc` has TWO
source-bearing shapes, `Pos` and `Inferred(Pos)` -- matching only `Pos` silently
disables the search and looks like it works.

- wide schema (generator in scratchpad, regenerate with the snippet in ticket §7.13):
  400 labels/1 partition costs +90ms; 200 labels x 16 partitions costs +110ms, FLAT in
  the partition count. Cheap.

STILL OPEN: interaction with `reduce`'s second case unexamined. **Status is candidate, not recommendation.**

Lean audit is now mechanical, not spot-checked: `cd tracker/lean && lake env lean
Audit.lean` walks the whole environment (1197 theorems, 0 non-standard axioms).

## In flight when this was written

(Both workflows were stopped 2026-09-01 ~10:35 after delivering their headline
artifacts; the Lean modules they wrote are on disk and `lake build` succeeds on all
798 jobs, so `CutSearch.lean` was not left broken by the kill.)

Two workflows. Neither is required for the recommendation above; both are
supporting evidence.
Run IDs and transcripts (check `journal.jsonl` for `{"type":"result"}` lines):
- `wf_4f1a5042-f05` — lean-cut-safety-proofs
- `wf_6e143d84-dea` — ermine-incompleteness-corpus
- both under `~/.claude/projects/-home-dmitry-research-ermine/539eca98-*/subagents/workflows/`
- if a workflow died mid-run, its results are still in its `journal.jsonl`; the new
  Lean files, if written, are simply on disk under `tracker/lean/Rowpartition/`
  and can be verified directly with `lake env lean` regardless.

1. `lean-cut-safety-proofs` → `CutConcrete.lean` (minting introduces no concrete
   label, so it cannot lose a concrete-label refutation), `CutSearch.lean`
   (bounded exhaustive counterexample hunt, `decide` not `native_decide`),
   `SplitNecessary.lean` (why `nongen` loses exactly those 5).
2. `ermine-incompleteness-corpus` → `core/examples/incomplete/` — realistic data
   queries showing the four ways row inference is incomplete.

**When they land: verify independently, do not trust the self-reports.** Three
agent self-reports have been wrong this session (a module reported compiling
while the library root was broken; theorem counts unreproducible; a "compiles:
true" that raced a concurrent edit). Run `lake env lean` on every module plus the
root, and `#print axioms` on the headline theorems.

## Traps that cost time — do not rediscover

- The `:browse` pretty-printer WRAPS long types. Join continuation lines before
  parsing (see `tracker/tools/g1-normalize.py`); otherwise signature comparisons
  silently compare first lines and every equivalence check passes vacuously.
- `g1-diff.sh run` hard-resets `G1_PROPS`. Inject properties via `_JAVA_OPTIONS`.
- Any drift figure computed from `tracker/g1-baseline/ei` is measuring an
  artefact: `reduce` case 2 splices 121 DERIVED partitions per boot into
  committed output. Compare real builds, not residuals.
- Adding files under `core/examples/` breaks the hard-coded corpus count in
  `TestSurfaceParsers.scala`.
- One waiter per condition. Killing a long job orphans every watcher on it.
- Loading MANY heavy modules in ONE `bin/ermine` invocation StackOverflows in
  `StreamTUtils.chop` (the loader's StateT stream chain), after ~2 modules of
  `core/examples/incomplete/`. PRE-EXISTING: identical with `-Dermine.genRules=all
  -Dermine.labelCheck=false`. Consequence: **never compare corpora by batch-loading
  them** -- both runs die partway and the counts are partial. Compare per-file.
- Running `bin/ermine` on one `core/examples/Ai/*.e` file alone reports
  `Module not found: 'Ai.Common'`. Put `Common.e` first on the command line. (The
  EDITOR resolves it correctly since the Resident fix below; the CLI still does not.)
- LSP FIX 2026-09-01, `lsp/Resident.scala` `checkFile`: a module `A.B.C` resolves its
  siblings against the HIERARCHY ROOT, not its own directory -- `SourceFile.filesystem`
  appends the whole dotted path, so the old code looked for `<dir>/A/B/D.e` inside
  `<root>/A/B/`. The header is now parsed BEFORE the loader is built so the name is
  known. This affected any project with a module hierarchy, not just our corpus.
  `core/examples/ai` was renamed `Ai` to match its `Ai.*` namespace (the stdlib
  convention: `Native/`, `Relation/`, `Layout/` all match). Verified: 4 Ai modules
  give 0 diagnostics in the LSP; `tracker/tools/lsp-smoke.sh` PASS (82 checks).
- `core/examples/**` is TYPE-CHECKED by `TestTolerantRead`, not just parsed, and its
  property is "GOOD CODE READS SILENTLY" with a hard-coded tolerance of exactly 4 known
  broken files. Adding a corpus of deliberately-bad code breaks it. Fixed by excluding
  `shouldfail/`, `shouldfail-controls/` and `incomplete/` from that sweep's
  `corpusFiles` (`ai/` stays in: those are valid examples). `TestSurfaceParsers`'s
  2.3d property is what checks the rejected corpus.
- A module that DIVERGES makes `core/test` diverge. Name it `.slow` instead of `.e`;
  every walker filters on `.e`. `core/examples/incomplete/README.md` has the per-file
  timings. Four renamed 2026-09-01: `gu02`, `gu03`, `gu07`, `gu09`.
- `com.clarifi.reporting.writers.TestLegend` "extra args are ignored" is FLAKY: it
  falsified after 70 passed tests on one run and passed on the next, untouched.
- Those four diverge on PRISTINE code too (verified by stashing all three solver files
  and rebuilding): 90s timeout each, with `gu04` finishing in 14.6s as the control.
  NOT caused by the cut or the label check.
- `pkill -f <pattern>` MATCHES ITS OWN COMMAND LINE. This killed three separate runs
  this session, including one reported as a completed test. Split the literal:
  `P="Xms10""24m"; pkill -f "$P"`.
- Never run `sbt` concurrently with another `sbt` on this project; they share the target
  directory and the second invalidates the first.
