# Brief: L5 — `LoopStrict` and the loop-level mint bound (the termination theorem)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`. LEAN ONLY (no Scala
edits, no sbt); `bin/ermine`/the repro harness may be used to replay a witness. Lean project
`tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`); Scala toolchain for replays
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`
(check `ps` for a running sbt first — another agent, L4, runs `core/test`). The tree carries a staged
L2 state and unstaged L3/L4 work; touch only your own new modules, import lines in
`tracker/lean/Rowpartition.lean`, additive README edits, the plan's L5 row, and your report.

READ FIRST: `tracker/LOOP-MODEL-PLAN.md` (the L5 section is the contract; the "Known scope limits"),
`tracker/loopmodel/L3-THEOREMS.md` (all of it; especially §2 (i), R2.4, **R2.5 the residual `weaken`
catalogue — six sites with the Scala each must model**, §4 (ii) and §4c), `tracker/loopmodel/L3-REVIEW.md`
(**§6d** — the exact guard mismatch: the loop's `concRows`/`resolvents` lookups scan `proc ++ incm`
while `sys s` also holds the environment's facts, so `Carried (sys s)` holds where the loop's lookup
misses and the loop MINTS where the relation would reuse; plus the re-review sections), then the Lean:
`Loop/Refine.lean` (`sys`, `LoopRel`, every `weaken` site), `Loop/RefineLearn.lean`
(`step_refines_all`, `SupOk`/`SupFresh`, `RunSupOk`, the `*_run` lemmas), `Loop/RefineConcrete.lean`,
`Loop/Order.lean` (`Terminates`, `run_mono`, the four order properties, `learnChain_card`, `NoSelfUnif`,
`NoInfRow`), `Loop/Wf.lean`, and the relation library: `KeyedRow.lean` (`Carried`, `hmeas`,
`mintsBoundedOnSatKeyed2Star`, `carried_concretizeSrs`), `KeyedEmpty.lean` (`makeEmptyE`, `EmptyKnown`,
`mintsBoundedOnSat_emptyPersisting`, `hmeas_increases`), `KeyedRowScala.lean` (`concRow_none_uncarried`,
the `G.erase c` bookkeeping), `ResGuardTerm.lean` (`gmeas`, `unfired`), `DefaultTerm.lean` (`forms`).
Also `tracker/satterm/KEYED-EMPTY-STAGE7B.md` §3 (the mint→empty→erase cascade that PRUNES the queue —
the loop's minting is load-bearing for its own queue size).

## Deliverables, as checkpoints (report as you go; each must leave build and audit green)

### C1 — `LoopStrict`
A relation with NO arbitrary-deletion constructor: the non-generative rules, `K2SplitStep`/`ResStep`/
`K2ResStep`/`splitFree`/`dedup`/`renameLhs`/`linkSymm`/`emptyProp` as in `LoopRel`, plus exactly the
deletions of R2.5 as constructors, each stated as the precise set transformation the Scala performs
(the `empty` dequeue = `makeEmptyE` composed with the `++!` `CommonPartition` redirect; the `concrete`
dequeue = `concretizeSrs` composed with `keepDefs` and `can`; the dequeued partition leaving `incm`;
the queue drops of `trim`/`++!`; `instantiate`'s removal at BOTH argument orders). Soundness of each
(one direction). Then `step_refines_strict`, the L3 theorem re-proved against `LoopStrict` under the
same hypotheses as `step_refines_all`. Acceptance: `LoopRel.weaken` is used nowhere in the `step`
refinement.

### C2 — the supply invariant, preserved
Close L3's R-C: prove `SupOk`/`SupFresh` preserved by `step` (`SupFresh.step` needs "every variable of
`sys s'` is in `sys s` or is the drawn id" — prove that vocabulary lemma for each branch; a `learn`
step may draw more than one fresh id — say how many and iterate), so that `RunSupOk` becomes a
theorem from the initial state rather than a per-state hypothesis. Then `run_refines_strict`.

### C3 — the loop-level mint bound (the theorem)
The obstacle (L3 review §6d): the relation's mint guard `¬ Carried (sys s) v K` is false in
situations where the loop's queue lookup misses, so a loop mint is not a relation mint. Choose and
JUSTIFY an approach; candidates, in the order I would try them:
  (a) a queue-visible system `qsys s` (queues only) and the guard `¬ Carried (qsys s) v K` as the
      loop's actual guard; show `hmeas`-style measure over `qsys` decreases at every loop mint and
      is non-increasing at every other `LoopStrict` step EXCEPT the deletions — then bound the
      deletions' damage: `makeEmpty`/`instantiate` remove a variable from the queues PERMANENTLY
      (it lives in the env thereafter and `Wf`/`NoSelfUnif`-style invariants say it never
      returns), so each variable can be "lost to the queue view" at most once, and the measure
      can increase only by the loss of that variable's carriers — bounded by (number of variables
      ever in the system) × (per-variable carrier weight), which the mint budget itself bounds
      circularly unless minted variables' losses are charged to their own mint; make that
      charging explicit;
  (b) the single-pass bound: each dequeue removes one partition (`learnChain_card`), each rule
      fires at most once per (premise, partner) pair per solve, and the premises are bounded by the
      vocabulary (`forms`) — which needs the vocabulary bound, i.e. the mint bound again; use (a)
      for the mints and (b) for the rest;
  (c) if neither closes, the precise obstacle as a lemma statement, and a serious witness hunt:
      a satisfiable `Wf s₀` on which `run` exhausts any fuel — try the empty-row engines (W2, W3,
      G7 shapes) at adversarial id bases and the `rowclosure.py` generator biased to empties —
      replaying any candidate through the COMPILER (`tracker/repro/satterm/run.sh` with a `json:`
      seed); a compiler hang is a real bug and must be reported at once.
Outcome, say which: (T1) `Terminates s₀` for every satisfiable `Wf s₀` (with `SupOk`/`SupFresh`
at the initial state) with an explicit bound; (T2) under a stated extra hypothesis, with the missing
lemma named and why it resists; (W) a witness with its compiler replay. Unsatisfiable input is out
of scope, but state whether the loop can loop on it.

### C4 — the Stage 7b variant, if C3 is T1
If T1 holds for the shipped flags, state whether it holds with `emptyRow = true` (the model has the
flag; the L3 review's `emptyRow` note and `KeyedEmpty`'s `mintsBoundedOnSatKeyed3E` apply) and
whether the Stage 7b variant would need a new guard case — one paragraph, no new Scala.

## Constraints
`lake build Rowpartition` and `lake env lean Audit.lean` (0 non-standard axioms; 2935 theorems /
838 jobs before you) green at every checkpoint; `#print axioms` for every headline in a SCRATCH file
under `/home/dmitry/.claude/jobs/880c725d/tmp/L5/`, never in a module; no `sorry` in a finished
module (a PARTIAL checkpoint says so and quantifies); never `lake exe cache get`, no new `require`, no
new Lean project, never touch `~/research/leanwork`, `CutSearch.lean` stays out of the root import
list; disk is tight; no commits; `pkill -f` matches itself. Traps: `decide` cannot see through
`mk`/`slist` (`simp [vset_mk, ...]` first); no `norm_num`; `Finset.card_insert_of_notMem`;
`Finset.mem_insert` must not share a simp call with `Finset.forall_mem_insert`. Expect more than one
round: write `tracker/loopmodel/L5-TERMINATION.md` EARLY with statements verbatim and keep it current;
a reviewer will re-run everything and read every statement for hidden weakening.

## Report
For C1–C4: statements VERBATIM, outcome, new constructors with soundness lemmas, the measure and
where it decreases/increases, the audit/build figures, files with line counts, and anything you could
not prove, stated plainly with original and proved statements side by side if you weakened anything.
Update the plan's L5 row and the README additively.
