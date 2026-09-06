# Brief: S2 — NO FALSE ACCEPTANCE: the shipped row solver accepts unsatisfiable systems; fix it behind a flag, prove the fix

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration` (HEAD `fde996a` + the uncommitted
S1 files; S1's prose corrections are being applied in the main tree by another agent — do NOT touch
`tracker/loopmodel/S1-*.md`, `tracker/ROW-CONSTRAINT-STATE.md`, `tracker/LOOP-MODEL-PLAN.md`, `tracker/lean/**` or
`tracker/lean/README.md` in Part A). Toolchains: Scala `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS=-Dermine.useInterface=false`; Lean `export PATH=$HOME/.elan/bin:$PATH` in `tracker/lean/` (Part B
only). One JVM at a time, `-XX:ActiveProcessorCount=2`; long runs under `setsid nohup` with a log (background shells
are capped at ten minutes); `pkill -f` matches itself (kill by PID); disk tight (gzip traces, delete `.ei` you cause).
No commits. sbt is allowed in the WORKTREE only.

## The bug (S1 review, `tracker/loopmodel/S1-REVIEW.md` §2.3–§2.6, §7.1, §9; seeds in
`/home/dmitry/.claude/jobs/880c725d/tmp/review-S1/` and, once S1's corrections land, `tracker/repro/satterm/seeds/unsat/`)

`Subst.solve` returns a substitution that VIOLATES a constraint it was given, on unsatisfiable inputs that pass
`labelCheckEarly`. Ten distinct seeds are confirmed accepted by the shipped compiler; two are five constraints long:

* `MIN1` (Z-1): `v6 <- (v7,v2)`, `v6 <- (v4,(|l35|))`, `v7 <- (v3,v1)`, `v3 <- (v2,v0)`, `v1 <- (v0,(|l22|))` — SOLVED at
  20/20 bases, `rho6 = {l22}` while the input puts `l35` in `rho6`. Mechanism: the loop reaches `.done` on an
  unrefuted residual (`{l22} <- ({l35}, v4)` is PUBLISHED, unchecked). Saturation is refutation-INCOMPLETE.
* `MIN2` (Z-2): `v2 <- (v3,v0)`, `v3 <- (v0,v1)`, `v2 <- (v1,(|l17|))`, `v2 <- ((|l17,l38|))`, `v5 <- (v2,v8)` — SOLVED
  at 4/20 bases (order-dependent), `l17` in two parts of one whole. Mechanism: the bare-row hole S1 named —
  `makeConcrete v1 {l17,l38}` finds the bare `v1 <- ((|l38|))`, `ensureSuperset` (containment, not equality) passes,
  `srs` is non-empty so `keepDefs` drops the bare row, `cancellation` emits nothing; the contradiction is deleted.
* `SURV1` (`U11/u00857`): `v5 <- (v2,v6,v0)`, `v5 <- (v2,v4,(|l1|))`, `v3 <- (v2,v1,v6,(|l20|))`, `v3 <- (v0,v4)` — SOLVED
  with every variable unbound; survives even `labelClash` on the saturated set (needs a case split).

Why the pre-loop check misses them: `labelCheckEarly` is UNIT PROPAGATION per label over the input (`LabelAlgo.lean`
proves it SOUND — clash ⇒ unsat — not COMPLETE), and these need a case split. Hunt figures: 99.90 % of random
unsatisfiable systems are caught by the label check; of the 11,048 that pass it, 665 seeds / 1,166 runs are
accepted by the model at shipped flags; the bare-row deletion fires in 1.6 % of runs.

What S1 proved and why it did not catch this: `run_noLoss`/`solve_sound` hold UNDER `SSat (sys s₀)`; "an accepted
program is well-typed" needs the converse — accepted ⇒ satisfiable — which is refutation completeness, and the loop
does not have it. In all 1,166 model false acceptances the OUTPUT system is itself unsatisfiable (the theorems
survive every witness).

## The fix, in three layers, ALL BEHIND A FLAG WHOSE DEFAULT IS OFF (adoption is the user's decision, not yours)

(i) **Bare-row exactness in `makeConcrete`**: at a bare definition `v <- ((|C|))` and a concrete instantiation
    `v := ((|fs|))`, require `C = fs` (refute otherwise) instead of `ensureSuperset`'s `C ⊆ fs`. Sound by
    `Loop/Sound.lean`'s `bare_refutes`; turns Z-2 into death-site 7 ("Row types failed to unify"), a refutation
    S1 already covers. Keep `ensureSuperset` for non-bare definitions.
(ii) **`checkLabels` on the saturated set** as well as on the input (`Subst.scala:1187`, `:1259`; the code's own
    comment cites `Rowpartition.refute_saturated_sound` and records the check was removed after "zero additional
    refutations" on the corpora — a fact about the corpora, not the algorithm). Catches all six minimised
    witnesses and 1,146/1,166 model false acceptances.
(iii) **A COMPLETE per-label decision** — unit propagation plus case split (DPLL over the booleans "l ∈ v" with the
    per-partition exactly-one constraints; the S1 reviewer's oracle and round 8's `satcheck.py` are the reference)
    — run on the solve's live input (the constraints with the current environment applied; note S1 review Z-6:
    `solve` does not `substType` its input first and the compiler's `SubstEnv` is long-lived — decide and state
    exactly what "the input" is at the compiler level so that the theorem in Part B is about what ships). This
    is the layer that gives the THEOREM: pass ⇒ satisfiable ⇒ (S1's `run_noLoss`) faithful output. Refutation
    message: the existing "Row partitions are unsatisfiable at field '…'" diagnostic with the label. Measure its
    cost: it is NP-hard in principle and tiny in practice (labels ≤ ~40, variables per solve ≤ hundreds) — say
    what the corpus's worst solve costs, including `incomplete/gu05`'s 1,372-partition solve.

Flag layout is yours to propose in the design note (one master flag, e.g. `-Dermine.rowSound`, default OFF, with
(iii) separately switchable for measurement is a reasonable shape); every flag default OFF; the SHIPPED behaviour
with flags off must be byte-identical.

## Part A — the Scala change, in a worktree, with gates (do this now; STOP after A5 and report)

A1 Create a worktree `~/research/ermine/ermine-scala-wt-s2` on a branch `row-sound`; implement (i), (ii), (iii)
   there behind the flags; keep the change small and local (`Constraints.scala` `makeConcrete`/`ensureSuperset`
   site; `Subst.scala` around `labelClash`/`checkLabels` and the pre-loop check; the DPLL as a small self-contained
   function next to `checkLabel`). Trace records: emit a `RowTrace` record for each new refutation site so the L2
   replay can see it (the model will mirror it in Part B).
A2 Design note `tracker/loopmodel/S2-DESIGN.md` (in the worktree; copied to the main tree at Part B): the exact
   compiler-level statement the fix targets ("if `Subst.solve` returns with the flag on, the constraints it was
   given, with the environment applied, are satisfiable"), where each layer runs, what "the input" is, the flag
   names, the diagnostics, and the cost model.
A3 Gates with the flags OFF — nothing may change: `core/test` (913/914 known: `Constraints.disjunction sound`
   starvation), `TestLoopTrace` (714/714), the L2 corpus row trace byte-identical (`tracker/tools/looptrace-corpus.sh`
   or the round-8 `gentrace.sh` recipe: `-Dermine.loadInSeries=true -Dermine.rowTrace=<file>`, compare with the
   main tree's trace), `.ei` unchanged, the 18 tracked seeds byte-identical at 10 bases (`run.sh sweep`).
A4 Gates with the flags ON: every seed in `seeds/unsat/` (and the reviewer's whole false-acceptance population,
   `review-S1/` — 665 seeds) REJECTED at all bases with the diagnostic naming the violated label — ZERO SOLVED;
   every SATISFIABLE tracked seed (`seeds/*.json`, `seeds/slow/NP01`… and round 8's 3,840 hunt seeds, which are
   satisfiable by construction) still SOLVED at 10 bases with the SAME substitution (no false rejection: this is
   the soundness half, and `LabelAlgo` covers only (ii)'s propagation — (iii)'s refutations must be checked
   against the oracle); `core/test` and `TestLoopTrace` (the model will disagree with the flag on until Part B —
   run the test with the flag off, and say so).
A5 The corpus with the flags ON, all eight groups (`incomplete/` included): list EVERY program that is newly
   rejected — each is an ill-typed program the shipped compiler accepts today, and the user needs the list —
   with the violated label and the source location; and the cost: `tracker/tools/perf-bench.sh` batch mode
   before/after (the P1 harness; report the machine's load with it), plus the per-solve maximum time of (iii).
   Then STOP and report; the orchestrator confirms Part B after S1 is committed.

## Part B — the model mirror and the theorem (Lean, main tree; only after the orchestrator's go)

B1 Mirror (i), (ii), (iii) in `Loop/*.lean` behind the same flags; prove the L2 differential with the flags ON
   agrees (the corpus replay and every seed), and OFF is unchanged (`git diff` on the pre-existing modules
   empty except the flag plumbing).
B2 Theorems: (i) the new death is a refutation (`bare_refutes`); (ii) sound (`refute_saturated_sound`); (iii) the
   per-label decision procedure, executable in Lean, SOUND (refutes ⇒ no model) and COMPLETE (passes ⇒ a model,
   constructed and checked against every constraint), plus the label-wise decomposition (`LabelClass.lean`/
   `LabelProp.lean` may have it: satisfiable iff every mentioned label's problem is satisfiable, unmentioned labels
   absent everywhere); then the top-level `solve_noFalseAccept`: flag on ∧ `run … = .solved s'` ⇒ `SSat (sys s₀)`,
   and with S1's `run_noLoss` the full chain "accepted ⇒ the output's models are models of the input". Instantiate
   on `MIN1`, `MIN2`, `SURV1` (REJECTED, kernel-checked) and `NP01` (SOLVED, unchanged).
B3 Report `tracker/loopmodel/S2-FIX.md` (statements verbatim, gates, the corpus list, the costs, side-by-side for
   anything weakened), the plan's S2 row (the orchestrator adds the section), README and state file additively.
   A reviewer re-runs everything. Adoption (default ON) is the user's decision and is not made here.

Outcomes, say which: (A-done) Part A with all gates green and the corpus list; (B-done) both parts; (BLOCKED)
with the exact obstacle. Constraints as always: audit 0 non-standard axioms, `#print axioms` in scratch under
`/home/dmitry/.claude/jobs/880c725d/tmp/S2/`, no `sorry`, no silent weakening, never `lake exe cache get`, no new
`require`, no new Lean project, never touch `~/research/leanwork`, `CutSearch.lean` out of the root import list.
Report early and keep it current (the machine lost power twice on 2026-09-05).
