# brief-S3 — the budget (Opus implementer, 4 h; ONLY on S2's proved negative)

Worktree `~/research/ermine/ermine-scala-wt-subsume-s3`, branch `subsume-s3`. Read `brief-S-common.md`, Part B,
`SUBSUME-STAGE0.md`, `SUBSUME-STAGE1A.md`, `SUBSUME-STAGE1B.md`, `SUBSUME-STAGE2.md` and their reviews. Report:
`tracker/satterm/SUBSUME-STAGE3.md`. A Lean prover may be split off in parallel by the orchestrator for the
theorem (see below); if so, the launch message names the worktree it works in and you coordinate through the
report files only.

## Why we are here

S2 reported "not available": `<orchestrator fills: theorem names of the negative results>`. The unbounded check
can fail to answer; deliverable 2 of the prompt applies: bail out under a budget whose exhaustion is a COUNTED,
TRACED, SAFE outcome — never a silent acceptance, never a hang.

## The theorem FIRST (Lean, `tracker/lean/Rowpartition/SubsumeBudget.lean` or under `Loop/` if the budget sits in
the loop; the orchestrator says which from S0's finding of WHERE the time goes)

Modelled on `Loop/Budget.lean` (`budget_terminates`, `stepBud_died_sys`) and `S2-DESIGN.md`'s budget-as-hypothesis:
1. the budgeted check terminates for every input;
2. it agrees with the unbounded check whenever the unbounded check answers within the budget;
3. exhaustion implies the unbounded check would not have answered within the budget (so exhaustion is reachable
   only where the unbounded check would not have answered — the prompt's wording; make the "within the budget"
   qualifier explicit and prove exactly that, no more, no less).
`lake build`, `Audit.lean` 0 non-standard, `#print axioms`, README entry. The Scala follows the theorem's shape.

## The Scala

- `-Dermine.subsume.budget=<n>` steps (the unit is what the theorem counts — nodes visited by the walk, or
  draws, or dequeues — say which and why it is the unit the theorem converts into termination); default value
  from S0's FAVOURABLE-run measurements with a margin (state the measurement, the margin, the number).
- Exhaustion COUNTED (a `GenRules`-style counter beside `rowSoundBudgetHits`) and TRACED (`RowTrace` kind, e.g.
  `sbudget`), and the outcome on exhaustion is the SAFE one for a rejection path: the program is REFUSED with a
  diagnostic that names the budget and the flag, never accepted. The B1 twin that must CHECK must still check
  (the budget must not fire on the favourable path; that is what the margin is for — measure it).
- Flag default: the budget ON changes behaviour only where the checker did not terminate before — argue that in
  the report from the theorem (2)+(3) and from the corpus (0 budget hits over the 168-file corpus and the full
  suite) and let the user decide the default. Ship default OFF unless the orchestrator's launch message says the
  user decided otherwise (they have not).
- Pins: the S2 pins (B1 on a deadline, the unsat generator, the positive twins) with the budget ON; a pin that
  a tiny budget refuses B1 with the budget diagnostic and increments the counter; a pin that the default budget
  never fires on the positive twins.
- Gates: Tier 0 + Tier 1 (as brief-S2 lists them), corpus verdicts byte-identical to S0's baseline with the
  budget ON and OFF, budget-hit count over the corpus (expected 0), the B1 property alone three times, and the
  interleaved boot timing ON vs OFF.

## Deliverables

`SUBSUME-STAGE3.md`: the theorem names/statements/axioms, the unit and the default with its derivation, the
counter and trace record, every gate number with its log, the corpus hit count, the argument for/against the
default, and the answer: *bounded* (with the budget) — or, if even the budgeted check cannot be made safe, say
why with the theorem. List every changed file. No commits.
