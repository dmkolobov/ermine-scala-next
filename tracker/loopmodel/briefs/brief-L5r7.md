# Brief: L5 round 7 — certify the user-facing fragment, and list the residue solve by solve

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, clean at `157a3f3`
(rounds 1–6 committed). Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`); compiler replays via
`tracker/repro/satterm` (Scala toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`-Dermine.useInterface=false`; bin/ermine allowed, sbt NOT). No Scala edits, no commits.

THE FRAMING (from the user, 2026-09-05): Ermine is a reporting language; users always end with concrete fields,
even with extensive row-polymorphic helper libraries. Round 6's certification (every standard-library row solve
terminates: the NoConc fragment, 15,377/15,377) is therefore a FLOOR. This round is about the solves USER
PROGRAMS produce — the example corpus — and its residue.

READ FIRST: `tracker/loopmodel/L5-REVIEW.md` "Round-6 review" (W-6a…W-6g, W-9: the input-only widening is NOT an
invariant — 111 solves fire a generative rule unblocked by `Substitution`/`CommonSubexpression`; the honest
target is the VOCABULARY-FIXED condition, 9,120 of 9,340 = 97.6 % of example solves); `L5-TERMINATION.md` §R6
(`NoConc.lean`'s proof shape: preservation + `measure3` bound + `unorderedHash_perm`; R6.3.4a's table); the
census tooling under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r6/` and `review-L5r6/`; modules
`Loop/{NoConc,Cycle,Mints,Supply,Hygiene,Order,Step,Rules}.lean`.

## Checkpoints, in order

R7.1 **The vocabulary-fixed fragment.** Define `VocabFixed s₀` as the run-level property "no generative rule
     fires along the run from s₀" or, better, an INPUT-checkable condition that implies it — find the
     strongest such condition the corpus data supports (R6.3.4a: 9,146 solves never fire either rule; what
     distinguishes them from the 111 that fire after unblocking?). Prove preservation and `Terminates` with an
     explicit bound, reusing `NoConc.lean`'s machinery (`measure3`, the queue length bound, `KDist`). If only
     the run-level version is provable, say so and prove `terminates_of_noMint` for it — then the
     certification is "every solve on which the model's trace shows no mint", checkable per solve.
R7.2 **Measure against the examples, solve by solve.** From the L2/L4 replay records of all seven groups:
     how many of the 9,362 example solves are in the fragment (target ≥ 9,120), and for EVERY solve outside
     it, one row: module, location, the rule that mints (`SplitConcrete`/`Resolution`), the number of mints,
     the key's shape (concrete part, whether the parent's whole row is concrete, whether it is a join/projection
     shape), and the model's dequeue count. That table IS the open problem, stated as a list of report shapes.
     Add `cycleRun` to `replayMain` (round 6 W-6g) so `--cycle` runs over corpus replays too, and run the cycle
     detector over every residue solve.
R7.3 **The residue's shape.** Classify the residue rows: which are the Stage 5/7b patterns (keyed reuse,
     empty-row), which are ResStar-like projections, which are single mints that are immediately concretised
     (the B1 shape). For each class say what the round-5 pump needs that the class lacks, or does not. If a
     class admits a per-class termination lemma (e.g. "one mint, then NoConc"), prove it and move those solves
     into the certified population — report the final certified fraction of example solves.
R7.4 **State the open problem precisely** in `tracker/ROW-CONSTRAINT-STATE.md` and the plan's L5 row: the
     certified population (stdlib 100 %, examples N %), the residue as a named list of shapes with counts, and
     what a divergence would have to look like within those shapes (the round-5 pump specialised to them).

Constraints as always: audit 0 non-standard axioms (3611 theorems / 854 jobs before you), `#print axioms` in
scratch under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r7/`, no `sorry` in a finished module, no silent
weakening, never `lake exe cache get`, no new `require`, no new project, never touch `~/research/leanwork`,
`CutSearch.lean` out of the root import list, disk tight, gzip traces, long runs under `setsid nohup` with a log
(background shells are capped at ten minutes), `pkill -f` matches itself.

## Report
Append a dated "Round 7" section to `tracker/loopmodel/L5-TERMINATION.md` (statements verbatim, the census with
commands, the residue table in full, the classification, the final certified fractions); update the plan's L5
row, the README and the state file additively. A reviewer re-runs everything.
