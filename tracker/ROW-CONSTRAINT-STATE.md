# Row-constraint work — state as of 2026-09-01

## 2026-09-01, later the same day: items 8a / 8b / 8c ANSWERED

See `tracker/TICKET-row-solver-8abc.md`.

**ADOPTED 2026-09-02: `ermine.resGuard` now DEFAULTS TO TRUE** — `resolution`'s mint is guarded
by the resolvent reverse lookup. `-Dermine.resGuard=false` restores the previous behaviour
exactly. Gates under the new default: `core/test` 903/904 (known failure only), 66-file and
34-file corpora 0 files differ, `shouldfail/` 40/40 rejected, `lsp-smoke` PASS 82.
The win: `core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e` goes from ~12.0s
of solve to ~1.1s. `resolution` fires on 18 example modules and ZERO stdlib ones.

The other three flags stay DEFAULT OFF, each for a measured reason:

    -Dermine.labelCheckSaturated=true  0 additional refutations on BOTH corpora -> leave the
                                       check reading the input (ticket 8a's own criterion)
    -Dermine.labelCheckEarly=true      verdicts identical but 26 of 66 messages change: better
                                       text, 11 worse locations -> revisit after follow-up item 1
    -Dermine.spliceGuard=true          its precondition fails on 90% of splices, and the .ei
                                       diff shows it DEGRADES signatures (resolved concrete rows
                                       become constrained polymorphic) -> do not adopt

Seven new Lean modules (`ResGuard`, `ResGuardTerm`, `ResGuardDiverge`, `Saturate`, `Splice`,
`LabelAlgo`, `SpliceGuard`); `lake env lean Audit.lean` reports 1465 theorems, 0 non-standard
axioms.

Headline: guarding `resolution` terminates on every SATISFIABLE system
(`guarded_terminates_of_satisfiable`) and not in general (`gSeed_diverges`), and there is
a SECOND cliff — driven by `resolution`, not `commonSubexpression`, on a well-typed
program — that the guard removes (`ResStar5`: >240s off, 0.2s on). `resolution` fires zero
times in a stdlib boot, which is why no existing corpus could see it;
`tracker/tools/gen-res-star.py` builds the population that can.


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

STILL OPEN: interaction with `reduce`'s second case unexamined. (The "candidate, not
recommendation" status this file used to carry is SUPERSEDED — both changes were
adopted as defaults; see the ADOPTED section at the top.) Remaining work across this
and the editor is collected in `tracker/TICKET-editor-and-solver-followups.md`.

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

- A NUMBER BELONGS TO AN INSTRUMENT, NOT TO THE COMPILER. A 66-file corpus sweep
  compares VERDICTS and ERROR MESSAGES and nothing else: a module that loads prints
  only `Importing module 'X'`, and `-Dermine.useInterface=false` suppresses the `.ei`
  where signatures live. Measured: `grep -lE 'forall|rho|<-' *.out` matches 0 of 66.
  So a corpus `0 differ` says NOTHING about published types — that surface needs
  `tracker/tools/ei-diff.sh`. On 2026-09-02 a predicted "15 differing line-pairs" for
  the cumulative check came back 0 purely because the 15 had been carried over from an
  `.ei` diff; the prediction was wrong, the measurement was fine. Same class of error
  as comparing against a moving baseline.
- A ZERO IS SUSPECT UNTIL THE INSTRUMENT IS SHOWN CAPABLE OF A NON-ZERO. Three times
  on 2026-09-02 a "0 differ" meant "measured nothing" (`.ei` contamination, a missing
  `PATH`, a metric on the wrong predicate). Positive control for the corpus harness:
  `core/examples/incomplete/unsound0[1-4]*.e` flip LOADED -> REJECTED under
  `-Dermine.labelCheck`, so run them through the same normalisation and classifier and
  confirm a non-zero before believing a zero.
- `corpus-verdicts.py` reads a LIVE directory. The file currently being written has no
  terminator yet and classifies as UNKNOWN, so a sweep in flight always shows exactly
  one UNKNOWN tracking the write head. Not a timeout. Wait for the run to end.
- A full-text corpus diff needs the boot PROGRESS BAR normalised as well as the
  `(N.NN seconds)` timings — it carries per-run wall-clocks, so without it all 66 pairs
  differ by exactly 2 lines and the diff looks meaningful when it is pure noise.

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
- LSP FIX 2026-09-01 (2), `lsp/Resident.scala` `checkFile`: it scrubbed the module
  under check by NAME, which deleted that module's BUILTINS -- `Lib` installs `asOp`
  and class `AsOp` as `Global("Relation.Op", ...)`, and they are only COMMENTED in
  `Relation/Op.e`. Re-reading the source cannot restore them. Now guarded with
  `|| builtinEnv.contains(...)`, the way `Session.reloadChangedModules` always did.
  Only `Relation.Op` and `Layout.Presentation` carry builtins (`grep '[a-z]Mod =' Lib.scala`).
- LSP FIX 2026-09-01 (1), `lsp/Resident.scala` `checkFile`: a module `A.B.C` resolves its
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
- **`bin/ermine` WRITES `.ei` interface files, and `ermine.useInterface` defaults to TRUE.**
  So the SECOND side of any A/B corpus comparison reads the interfaces the FIRST side just
  wrote and never re-runs the solver on those modules. This invalidated a 66-file
  comparison on 2026-09-01 before it was caught: the tell was the type-hole report vanishing
  from `Holes.e` and `LayoutTesting.e` on side B, and the stdlib boot dropping from 12.4s to
  5.6s. `tracker/tools/corpus-run.sh` now deletes `core/examples/**/*.ei` before each run
  AND passes `-Dermine.useInterface=false`. Any hand-rolled comparison must do both.
- **Never TIME anything while another build runs.** A full `res-guard-bench.sh` table was
  invalidated on 2026-09-01 by contention with a `lake build`: `ResStar3` was recorded as
  TIMEOUT at 90s and, re-run alone, solves in 0.05s. The table was discarded and re-run.
  Probes measure wall time; anything else on the machine is measurement error.
- **`bin/ermine` exits 0 even when the module fails to load.** It prints "Unable to load
  module" and then reads EOF from stdin and quits cleanly, so an exit-code comparison sees
  nothing. Read the verdict out of the output text --
  `tracker/tools/corpus-verdicts.py <dir> [<dir2>]` classifies LOADED/REJECTED per file and
  diffs two runs, including the error message.
- **`lake` 5.0.0 has no `-j` / `--jobs` option** (both are rejected). To bound memory,
  build modules one at a time (`lake build Rowpartition.X`) and/or set `LEAN_NUM_THREADS`.
- **`tracker/lean/Rowpartition/CutSearch.lean` does not build on this machine.**
  `lake build Rowpartition.CutSearch` is OOM-killed (`Lean exited with code 137`) at 15 GB,
  both with default parallelism and with `LEAN_NUM_THREADS=1`, once with nothing else
  running. It is therefore NOT imported by `Rowpartition.lean` and its 125 theorems are
  NOT covered by `Audit.lean` -- contrary to what README.md used to claim. Everything else
  is: `lake env lean Audit.lean` reports **1465 theorems, 0 non-standard axioms**.
