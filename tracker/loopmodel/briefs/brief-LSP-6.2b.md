# Brief: LSP interstage item 6.2b — the pattern-binder hover hook (Tier 1: a flag-gated change in Subst.scala)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (51629452 or
later: LSP Stage 4 complete and G4 signed off; the signature-entailment work MERGED — `SigEntail.scala`, `Constraints.
scala`, `Subst.scala` +49/−4, the g1-baseline RE-CUT; new gate baselines below). Toolchain `export PATH=~/.local/
ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed (`core/clean core/compile
core/copyResources` if the E046 quirk bites). ONE JVM of YOURS at a time, no background JVMs, no lingering polling
shells; the user may have another sbt in a SEPARATE worktree (`ermine-scala-wt-*`) — fine for identity gates and
tests, NOT for timings: every A/B waits for load < 1.3 and says so. No commits. Do not touch `tracker/lean/` or
`tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause (`find`; the Tier 1 sweep writes many; never `tracker/g1-*`).
Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.2b/`.
READ FIRST: `tracker/LSP-ROADMAP.md` § "Interstage item 6.2b" and Stage 4 Decision (f); the Blocked/Awaiting FORK
entry "pattern-binder types beyond equation arguments"; `tracker/loopmodel/LSP3-6.2-LOCALS.md` §1 (why pattern
binders are unreachable) and §8; `LSP3-6.2-REVIEW.md` R-1 (the FIRST hook shape REFUTED: a meta recorded in
`inferPatternType` is dropped from `hm.types` by `restrictTypes` — `Subst.scala` `restrictTypes` :160, reached from
the `Lam` case and `inferAltTypesPrime` — so a post-component zonk returns the unconstrained variable; the WORKABLE
shape is `Remember`'s: eager substitution at `instantiateType` :189/:194, `unbind` :610/:619, `generalize`, and
the per-binding writes ~:232-238/:454) and R-2 (option 4, the arity split — already shipped, covers equation
arguments); `tracker/loopmodel/briefs/brief-LSP4-6.2b-prototype.md` (the earlier worktree-prototype brief: its
"workable shape" section is the design, its evidence list is this item's gate list — but this item lands in the MAIN
tree, no worktree); `tracker/GATE-POLICY.md` Tier 1; `tracker/SIG-ENTAIL-PLAN.md`'s 2026-09-12 LANDED entry (the new
baselines: core/test 1061/1061 alone; corpus --batch 88/70/0 of 158; 274 interfaces; lsp-smoke 551; g1 EQUIVALENT).

THE GOAL: hover on the 38% of local binders that still answer null — lambda arguments, `case` and `do` binders,
variables nested inside constructor/tuple patterns — by recording each pattern variable's type where the checker
mints it and keeping the record substituted as inference proceeds, behind a flag that is OFF on every strict path
so batch pays nothing and observes nothing. 6.2's equation-argument arity split stays; where both give a type they
must agree (assert it).

## What to build
6.2b.1 `SubstEnv` gains `var binderTypes: Map[(Int, Int), Type]` (keyed by the binder V's def-site (line, column)
      in THIS file — `v.loc` is a real `Pos`; skip `Inferred`/builtin locs) and `var recordBinders: Boolean = false`.
      In `inferPatternType`'s `VarP` case, after `unbindAnnot` yields `t`, if `recordBinders` and the loc is real:
      `binderTypes += key -> t`. Then keep the map SUBSTITUTED exactly where `hm.remembered` is: `instantiateType`
      (:189-194), `unbind` (:610-619), `generalize`, and any other site that rewrites `remembered` — audit every
      `hm.remembered =` write (`grep -n remembered Subst.scala`: :106, :194, :232-238, :454-455, :619, :814, :996)
      and decide for each whether `binderTypes` needs the same treatment (the per-binding `remembered` writes at
      :232/:238/:454/:814/:996 are ID-keyed Remember bookkeeping — probably not; say why). All of it under `if
      (hm.recordBinders)` so the flag-off path is one boolean test per site. `TolerantCheck.checkWith(wantLocals =
      true)` sets `recordBinders = true` inside each component's `Session.subst` block, and after inference merges
      `hm.binderTypes` (zonked with `substType`, rendered per Decision (a) — monotype, letters shared with the head
      via the 6.2 `prettyTypeIn` mechanism) into `Result.locals` for binders NOT already typed by the arity split;
      where both have a type, assert equality (alpha-equivalence via `AlphaEq` if letters differ) and report any
      disagreement as a finding. `TolerantCheck.check` and every batch entry never set the flag.
6.2b.2 THE REFUTATION TEST FIRST: reproduce 6.2's failure on a scratch probe (`f x = x && True`: the recorded arg meta
      zonks to `a` after `restrictTypes`) with the naive shape, THEN show the eager-substitution shape yields `Bool`
      — the same probe, both shapes, in the report. This is the item's soundness evidence and it must be seen to
      fail before it passes.
6.2b.3 TESTS. TestTolerantCheck: every remaining binder kind gets a type — a lambda argument, a `case` alternative
      binder, a `do` binder, a variable nested inside a constructor pattern and inside a tuple pattern, an as-pattern's
      inner variable; a where-bound polymorphic local's lambda argument shows the head's letters; a binder in a
      component that DIED is absent; fast mode → absent; the cache-invisibility set (warm == cold byte-identical)
      extended to the new binders; the 6.2 sweep property extended: over the corpus, EVERY value-local renamer binder
      in a clean module (Arg/LetBound/WhereBound/DoBound/CaseBound) has a type — report the table against 6.2's
      (LetBound 156/156, WhereBound 89/89, Arg-equation 2872/2872, Arg-other 39/1791, CaseBound 0/117, DoBound 0/31)
      and the residual class if any remains (state it, do not hide it). lsp-smoke: `Locals.e` gains hover on a
      lambda arg, a case binder, a do binder and a nested pattern var, at def-site and at a use, exact `Name : Type`
      strings; the 6.2 pins that asserted NULL for these must FLIP (they were written to fail when this lands — find
      them: LSP3-6.2-REVIEW.md R-5 names them) and the count grows from 551.
6.2b.4 TIER 1 — the checker changed, so all of it, against a pre-change build of HEAD in scratch (classes-before
      swap or a worktree with its own regenerated `tracker/repl-classpath.txt` — GATE-POLICY's worktree note):
      `looptrace-corpus.sh` (`LOOPTRACE_PAR=3`) both sides + `trace-ab.py` all record kinds (IDENTICAL, sinmoved 0, rc
      0 every group — the flag is off in batch, so not one Supply draw may move); `ei-diff.sh --snapshot --batch` with
      `-Dermine.loadInSeries=true` both sides + `ei-classify.py` (0 of 274 differ); `g1-validate.sh` 9/9 against the
      RE-CUT baseline. INTERLEAVED A/B ON BOTH TARGETS, load < 1.3: `perf-bench.sh batch -n 3` before/after/before/
      after (the flag test on the checker's hot path — must be inside the ~1% floor; report pooled and median-of-
      medians); `perf-bench.sh editor -k 15` (pins debounce 300) before/after/before/after — the record-and-
      substitute work is ON in the editor: report the typecheck-segment Δ and the round-trip Δ against the 6.2
      budget (≤ 5% of the round trip, ~45 ms of ~0.93 s); over budget → the hook stays OFF in Resident too and the
      item is PARKED with the number. Tier 0: compile+copyResources; `TestLoopTrace` 720/720; `corpus-run.sh --batch
      <outdir>` 88/70/0 of 158 AND byte-identical to the pre-change run; `repl-smoke.sh` 8 groups, goldens
      unmodified; `lsp-smoke.sh` 551 + yours; the targeted suites (`*TestTolerantCheck *TestTolerantRead
      *TestEditorBuffers *TestSurfaceCache *TestRenamer* *TestLower *TestSigEntail`); boot 129; `.ei` 0 by `find`;
      `git diff --stat` == `--stat -w --histogram`; CRLF preserved (check `Subst.scala`'s line endings).
6.2b.5 REPORT `tracker/loopmodel/LSP-6.2b-HOOK.md`: the refutation-then-success probe; the site audit (every
      `remembered` write, treated or not, why); the coverage table before/after; the agreement check with the arity
      split; Tier 1 results; both A/Bs; every gate number; what ships (the hook ON in Resident, or PARKED with the
      number). Outcomes: GREEN / PARKED / PARTIAL. No silent weakening; if any Tier 1 identity gate moves, STOP and
      report — do not tune. STOP after the report — a reviewer re-runs Tier 1 once.
