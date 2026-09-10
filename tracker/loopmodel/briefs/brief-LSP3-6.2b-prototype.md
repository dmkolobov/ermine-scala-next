# Brief: LSP Stage 3, 6.2b — PROTOTYPE ONLY, in an isolated worktree: the pattern-binder recording hook (fork evidence)

THIS IS EVIDENCE-GATHERING FOR A DECISION THE USER HAS NOT MADE.  Nothing you produce lands in the main tree: you work
in a git WORKTREE, you make no commits anywhere, and your deliverable is a report plus a patch file.  The orchestrator
parked this fork in `tracker/LSP-ROADMAP.md` § Blocked/Awaiting because it is a `Subst.scala` change, which the
Stage-3 invariant says stops the item for the user; your job is to make that decision a yes/no with numbers.

Setup: `git worktree add /home/dmitry/research/ermine/ermine-scala-wt-62b HEAD`
(the main tree has 6.2 committed; check `git log -1`). Work ONLY in `/home/dmitry/research/ermine/ermine-scala-wt-62b`.
Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`, run from the worktree — it has its own `target/`; the first compile is a full one).
ONE JVM at a time, no background JVMs. Delete every `.ei` you cause. Do not touch `tracker/lean/`. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.2b/`. Read first:
`tracker/loopmodel/LSP3-6.2-LOCALS.md` §1 (why pattern binders are unreachable) and §8 (the three options; you
build option 1), the 6.2 review `LSP3-6.2-REVIEW.md` if present, `tracker/GATE-POLICY.md` (this IS a Tier-1 change:
`Subst.scala`), and the Stage-3 invariants in `tracker/LSP-ROADMAP.md`.

## What to build — the WORKABLE shape (the 6.2 review, R-1, refuted the first shape)
The 6.2 report's option 1 as first written ("record `t` in `inferPatternType`'s `VarP` case, merge and zonk after the
component") DOES NOT WORK: the recorded meta is removed from `hm.types` by `restrictTypes` (`Subst.scala:153`), reached
from the `Lam` case (`:942`, `restrictTypes(ts ++ pt.xs)`) and `inferAltTypesPrime` (`:1036`), because `:1055-1057`
returns that same var in `Patterned.xs`; a post-component zonk returns the unconstrained variable. Reproduce that
first (the reviewer's probe: `f x = x && True` — head meta zonks to `Bool -> Bool`, the recorded arg meta to `a`).
Then build the shape `Remember` uses: `SubstEnv` gains `var binderTypes: Map[(Int,Int), Type]` and a flag
`recordBinders` (OFF by default; only `TolerantCheck.checkWith(wantLocals = true)` turns it on inside its subst
blocks); record `v.loc -> t` in `inferPatternType`'s `VarP` case when on; and keep the recorded types EAGERLY
SUBSTITUTED wherever `hm.remembered` is — `instantiateType` (`:187`), `unbind` (`:586`), `generalize` (`:1624`) — under
the same flag, so that when `restrictTypes` drops the meta the recorded entry already carries what it was bound to.
Count the sites you touch and the lines; the number is part of the evidence. Then `TolerantCheck` merges
`hm.binderTypes` after each component (the pattern-binder class only — equation-argument binders already come from
6.2's arity split; the two must agree where they overlap: assert it). Extend the 6.2 sweep to expect lambda/case/do
binders and nested pattern vars typed in clean modules; extend `Locals.e`'s checks in the worktree's lsp-client.py.
Measure the FLAG-OFF cost on the batch target too: `perf-bench.sh batch -n 3` interleaved main tree vs worktree
(the flag check sits on the checker's hot path) — the user needs that number as much as the editor one.

## The evidence the decision needs (all in the worktree, one JVM at a time)
- TIER 0: compile+copyResources; `TestLoopTrace` 720/720; `corpus-run.sh --batch <outdir>` 85/69/0; `repl-smoke.sh`
  8/66 goldens unmodified; `lsp-smoke.sh` (6.2's count + yours).
- TIER 1, because `Subst.scala` changed: `tracker/tools/looptrace-corpus.sh` (18 groups, `LOOPTRACE_PAR=3`, ~15 min)
  and `trace-ab.py` against a pre-change run (ALL record kinds) — the pre-change run is the MAIN tree at HEAD (build
  it there ONLY when no other JVM runs; coordinate: the orchestrator may have another agent using the main tree —
  check `pgrep -af java` and wait); `ei-diff.sh --batch` with `-Dermine.loadInSeries=true` on both sides classified
  with `ei-classify.py` (expected: 0 differences — the flag is off in batch); `g1-validate.sh` 9/9.
- PERF: interleaved A/B on Layout/Report.e, `perf-bench.sh editor -k 15`, before = main tree (6.2 as committed,
  locals on) / after = worktree, before/after/before/after with load < 1.3: the four medians and the pooled delta.
  The 6.2 budget line was Δ ≤ 5% (~80 ms); state where this lands.
- The 180-file sweep time before/after.
- `git -C <worktree> diff > <scratch>/6.2b.patch` — the complete patch, and its line count for `Subst.scala` alone.

## Report `tracker/loopmodel/LSP3-6.2b-PROTOTYPE.md` (write it in the MAIN tree's tracker directory, the one file you
touch there): the hook (exact lines), where the recorded meta connects to inference (the `refreshList` question),
the sweep table, the perf table, every Tier 0 and Tier 1 number, the patch path and size, and a one-paragraph
recommendation. Then `git worktree remove --force /home/dmitry/research/ermine/ermine-scala-wt-62b` ONLY after the
patch file is saved (the orchestrator can re-apply it). STOP after the report.
