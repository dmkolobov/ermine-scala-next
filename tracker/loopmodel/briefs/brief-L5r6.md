# Brief: L5 round 6 — the standard-library fragment, a cycle search up to renaming, and "incm empties"

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, clean at `1394df4`
(rounds 1–5 committed). Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`); compiler replays via
`tracker/repro/satterm` (Scala toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`-Dermine.useInterface=false`; bin/ermine allowed, sbt NOT). No Scala edits, no commits.

READ FIRST: `tracker/loopmodel/L5-REVIEW.md` "Round-5 review" — its judgement section and **R6.1–R6.3**
(≈ lines 2100–2150) ARE this brief; its W-1 (stdlib-boot inputs carry NO concrete labels; 373 row-carrying
boot solves), W-6 (the ten-turn pump on a three-label input) and the instrumented pump table; then
`tracker/loopmodel/L5-TERMINATION.md` §R5 (`Pump.lean`'s instrument, `Fragment.lean`'s `LinkOnly` and its
21 size lemmas, `Dequeue.lean`); the hunt tooling under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r5/` and
`review-L5r5/`; modules `Loop/{Fragment,Pump,Dequeue,Mints,Supply,Hygiene,Order,Step,Queue,Rules}.lean`.

## Checkpoints, in the order most likely to change what the compiler is certified for

R6.3 **The no-concrete-labels fragment — first.** Define `NoConc s` (every partition's concrete part empty,
     at the input and hence — prove it — along the run: `splitConcrete` and `resolution` need a nonempty
     concrete part or a concrete row, so both generative rules are unreachable; check every other rule and
     `makeConcrete`/`makeEmpty`/`unify` preserve it). Prove `noConc_terminates` with an explicit bound (the
     queues shrink or the vocabulary is fixed: `LinkOnly`'s size lemmas and `DefaultTerm.forms` are the
     tools). Then MEASURE the fragment against the corpus with the L2 replay records (`sin`'s `nRows`, the
     `scon` payloads): which solves of the stdlib boot and of the 110 examples are in it — the review says
     all 373 row-carrying boot solves; confirm from the traces and give the example-corpus figure. Outcome:
     "termination proved for every solve of the standard library boot" if that holds, stated exactly.
R6.1 **A state cycle up to renaming of minted ids.** Define a canonical form of `State` that quotients
     minted ids by first-occurrence order (the trace normaliser in `looptrace-diff.py` is the model) and add
     `looptrace --cycle` (or a Python pass over `--mints` output) that hashes canonical states along a run and
     reports a repeat. A repeat is `not_Terminates` in one line (`run` is deterministic): prove that lemma
     (`terminates_iff_no_cycle` or the one direction needed). Run it over the round-5 populations
     (`popJ`, `cand-deep`, the climbs) and a fresh 50,000-solve hunt biased as round 5's. Report: repeats found
     (→ replay through the compiler, prove W) or "no canonical repeat in N solves / M states", which is the
     strongest negative available.
R6.2 **"incm empties".** Recast: `Terminates s ↔ ∃ n, (run s n).incm = []` under the single pass; then
     state what would make the derived set saturate — `trim` refuses everything `proc` holds (round 3) plus
     guard completeness: every derivable partition at a key is either already in `proc` or a mint the guard
     permits, and permitted mints are bounded by `KMintRun.mints_le` — and find the exact gap between that
     and the loop (the re-mints of round 5 are derivations the guard permits AGAIN after a carrier is lost).
     State the residual as one lemma; attempt it; if it resists, say precisely what the ten-turn pump does
     to it.

Outcomes: R6.3 proved/measured; R6.1 W or a quantified negative; R6.2 T1/T2. Constraints as always: audit 0
non-standard axioms (3494 theorems / 852 jobs before you), `#print axioms` in scratch under
`/home/dmitry/.claude/jobs/880c725d/tmp/L5r6/`, no `sorry` in a finished module, no silent weakening, never
`lake exe cache get`, no new `require`, no new project, never touch `~/research/leanwork`, `CutSearch.lean` out
of the root import list, disk tight, gzip traces, long hunts under `setsid nohup` with a log, `pkill -f` matches
itself.

## Report
Append a dated "Round 6" section to `tracker/loopmodel/L5-TERMINATION.md` (statements verbatim, the fragment's
corpus coverage table with commands, the cycle search's counts, every compiler replay); update the plan's L5
row and the README additively; if R6.3 holds for the stdlib, add one paragraph to `tracker/ROW-CONSTRAINT-STATE.md`
stating exactly what is now certified. A reviewer re-runs everything.
