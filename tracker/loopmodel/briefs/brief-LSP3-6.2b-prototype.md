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

## What to build (option 1 from the 6.2 report, and nothing wider)
1. `SubstEnv` gains `var binderTypes: Map[(Int, Int), Type] = Map()` and `var recordBinders: Boolean = false`
   (or an `Option` — say). In `Subst.inferPatternType`'s `VarP` case (~:1055), AFTER `unbindAnnot` yields `t`: if
   `hm.recordBinders` and `v.loc` is a real `Pos` (not `Inferred`/builtin — the same test 6.2's `collectLocals`
   uses), `hm.binderTypes += (v.loc.line, v.loc.column) -> t`. NOTHING else in `Subst` changes. Note `t` is the
   pattern's type BEFORE the body is inferred; it is a meta (or contains metas) that the body's inference will
   constrain — so the ZONK must happen after inference (in `TolerantCheck`), not at record time. Check whether the
   `Lam` case's `refreshList` (~:930) re-ids the vars so that the recorded `t` no longer connects to what inference
   constrained — if so, record at the point where the connection is live (say where and why) or show that `subst`
   composition still reaches it.
2. `TolerantCheck.checkWith(wantLocals = true)` sets `hm.recordBinders = true` inside each component's `Session.subst`
   block and, after inference, merges `hm.binderTypes` mapped through `Subst.substType` into `Result.locals`
   (the `let`/`where` path from 6.2 stays as is; pattern binders now fill the rest). `TolerantCheck.check` and
   every batch path never set the flag.
3. Extend the 6.2 sweep property to expect the FULL reachable set: `Arg`, `CaseBound`, `DoBound` binders in clean
   modules all have a local type — report the new table (6.2's was 284 of 5056; the target is ~5056 minus the
   class of legitimate misses, which you enumerate). Extend `Locals.e`'s smoke checks to hover an arg, a case and a
   do binder with exact `Name : Type` strings (in the worktree's copy of lsp-client.py).

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
