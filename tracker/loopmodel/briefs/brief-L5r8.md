# Brief: L5 round 8 — the mint CHAIN DEPTH: measure it, decompose the mint bound into it, hunt it

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, clean at `2f572a5`
(rounds 1–7 committed). Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`); compiler replays via
`tracker/repro/satterm` (Scala toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`-Dermine.useInterface=false`; bin/ermine allowed, sbt NOT). No Scala edits, no commits.

WHERE THE PROBLEM STANDS (round 7 + its review): `terminates_of_drawsAtMost` is a socket — any bound `k` on the
loop's draws yields `Terminates`; `drawn_unbounded_of_not_terminates` says a divergence draws unboundedly many ids;
`reaches_concSub` says the LABEL POOL IS FIXED along every run, unconditionally. So the whole open problem is: the
loop mints at keys `(v, C)` with `C` from a fixed finite set — is the set of sites `v` bounded, and is each key
minted boundedly often? A divergence must mint at unboundedly many DISTINCT left-hand sides, each beyond the
input's own being itself a minted name, i.e. an infinite chain `v₀ → v₁ → v₂ → …` where `vᵢ₊₁` is minted while a
partition of `vᵢ` is dequeued. Nobody has measured that chain. The reviewer's first datum (X-9(8)): in the six
example groups 227 of 230 `splitConcrete` mint sites are INPUT variables (the split barely chains), `resolution`
chains on about half its conclusions, and `incomplete/` is where the split chains at all (22 of 169).

READ FIRST: `tracker/loopmodel/L5-REVIEW.md` "Round-7 review" — X-7 (the `incomplete/` group: 34 files,
`np01_add_or_recompute.e(134:15)` re-mints a `splitConcrete` GUARD key, `gu05_star_join_4dim_concrete_signature.e(62:1)`
is the deepest real solve: 281 dequeues, ~149 loop draws, `cmax = 6`), X-8a (the pump IS the CARRIER key; 46 of
9,362 example solves re-mint one, up to four times), X-9(8)/(9), X-12 (this brief's origin); then
`tracker/loopmodel/L5-TERMINATION.md` §R7.1d–§R7.3c and §R7.7; modules `Loop/{VocFix,Pump,Mints,Cycle,Main,Supply,
Draws,Hygiene}.lean` (`PumpRep`, `CycleRep`, `carrierKeys`, `--mints`, `--cycle`, both now on the `--replay` and the
`json:` paths); tooling under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r7/` (`gentrace.sh`, `runcycle.sh`,
`runmints.sh`, `r7census2.py`, `agg.py`) and `/home/dmitry/.claude/jobs/880c725d/tmp/review-L5r7/` (`genic.sh`:
`incomplete/` traced one JVM per file under a 90 s cap; the mint-site census).

## Checkpoints, in order

R8.1 **Instrument the chain.** In the model: the DEPTH of every drawn id — input ids (present at the first dequeue,
     including `PQueue.build`'s mints) have depth 0; an id drawn at a step whose dequeued premise has left-hand side
     `v` has depth `depth v + 1`. Record per mint: the rule (`splitConcrete` / `resolution`), the site's depth, and
     the key's re-mint index (how many times this `(v, C)` — guard key AND carrier key — has been minted before).
     Report over BOTH populations (the seven groups AND `incomplete/`, from fresh traces): the depth histogram of
     all mints, the per-solve maximum depth, and the per-key re-mint maximum, cross-tabulated by the round-7 residue
     classes A1/A2/A3/B/C/D; list the ten deepest chains with their solves and what each link's rule was. Say
     whether the maximum depth is bounded by something the INPUT determines (its variable count, its partition
     count, `|L|`) across every corpus solve.
R8.2 **The decomposition lemma, in Lean.** State and prove over `Reaches`/the run: if along every step from `s₀`
     (a) every drawn id has depth ≤ `D`, and (b) every key is minted at most `R` times, then the loop draws at most
     `f(n, m, D, R)` ids — sites at depth `d+1` ≤ sites at depth `d` × `2^m` keys × `R`, with the label pool fixed by
     `reaches_concSub` — and hence `Terminates s₀` via `terminates_of_drawsAtMost`. This turns the open problem into
     exactly the TWO quantities R8.1 measures; make both hypotheses statements about the run that the instrument
     decides per solve (as `NoDrawB` did), and instantiate the theorem in Lean on the two real seeds of R8.4 with
     their measured `D` and `R`. Say precisely which of (a), (b) each earlier refutation (rounds 4–5's charging
     lemmas, the dequeue-order repair, W-9's 111) bears on.
R8.3 **Hunt each factor.** With the rounds 4–5 generator (empty-biased, cancellation partners, adversarial id
     bases; `tmp/L5r5/`, `tmp/L5r6/`) and the two real seeds as parents, the model as the fast oracle: the largest
     chain depth and the largest per-key re-mint count reachable. Report the growth curve of each against the
     input's size; every candidate exceeding the corpus maximum by ≥ 2 replayed through the shipped compiler at ten
     id bases (a run over the harness's time cap is a HANG candidate — report it at once, confirm under a longer
     cap). If either factor grows without bound in a family, drive it as round 5 drove the pump, and prove
     `not_Terminates` on the state if a genuine divergence appears (the W outcome).
R8.4 **Retire the synthetic pump seeds for two real ones.** Transcode `incomplete/np01_add_or_recompute.e(134:15)`
     and `incomplete/gu05_star_join_4dim_concrete_signature.e(62:1)` into tracked `json:` seeds under
     `tracker/repro/satterm/seeds/` (from their `sin`/`scon` records), verify each seed's model run reproduces the
     trace's draw and dequeue counts, sweep both on the shipped compiler at ≥ 20 id bases (`run.sh sweep`), and
     say whether `core/test`'s `TestLoopTrace` picks up new files in that directory (do NOT run sbt; the
     orchestrator runs `core/test` afterwards — if a code change is needed to include them, say exactly which).
R8.5 **`incomplete/` is a first-class group from now on.** Every census figure of this round is over EIGHT groups;
     the trace-generation script covers it (one JVM per file, 90 s cap, as the reviewer did); the vocabulary-fixed
     certified fractions are restated over the eight (round 7: seven groups 9,118/9,362 completed-solve population
     and 9,134/9,381 all-solves population; `incomplete/` 1,188/1,283 by the reviewer).

Outcomes, say which: (W) a compiler-reproduced divergence + `not_Terminates`; (T1) both factors bounded by the
input and proved → `Terminates` for every satisfiable `Wf s₀`; (T2) the decomposition lemma proved, both factors
measured, the exact remaining lemma(s) named with the strongest data for each.

Constraints as always: audit 0 non-standard axioms (3706 theorems / 855 jobs before you), `#print axioms` in
scratch under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r8/`, no `sorry` in a finished module, no silent weakening
(side-by-side table), never `lake exe cache get`, no new `require`, no new project, never touch
`~/research/leanwork`, `CutSearch.lean` out of the root import list, disk tight (gzip every trace; delete `.ei`
files you cause under `core/examples`), long runs under `setsid nohup` with a log (background shells are capped at
ten minutes), `pkill -f` matches itself (kill by PID). Traps: `decide` cannot see through `mk`/`slist`; no
`norm_num`; `Finset.mem_insert` not with `Finset.forall_mem_insert`. Census populations: state the predicate
(round 7's `≥ 1 inpart` record hides REJECTED solves — report both populations); `hashdiff`/`eqdiff` are computed
only by plain `--replay`, never by `--cycle`/`--mints` — cite a plain `--replay` for the differential.

## Report
Append a dated "Round 8" section to `tracker/loopmodel/L5-TERMINATION.md` — write it EARLY and keep it current —
with statements verbatim, the depth/re-mint tables with commands, the ten deepest chains, the hunt's parameters
and hit table, every compiler replay, and a side-by-side table for anything weakened; update the plan's L5 row
and the README additively; add to `tracker/ROW-CONSTRAINT-STATE.md` only what is newly certified. A reviewer
re-runs everything.
