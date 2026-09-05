# Brief: L5 round 5 — drive the pump (a divergence witness), or the dequeue-order argument

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, clean at `e3cb56a`
(rounds 1–4 committed). Lean project `tracker/lean/` (`export PATH=$HOME/.elan/bin:$PATH`); compiler replays
via `tracker/repro/satterm/run.sh`/`sweep.sh` (Scala toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`-Dermine.useInterface=false`; bin/ermine allowed, sbt NOT). No Scala edits, no commits.

READ FIRST: `tracker/loopmodel/L5-REVIEW.md` "Round-4 review — 2026-09-05" — its U-4/T-9 (the pump) and its
four-checkpoint specification **R5.1–R5.4** (≈ lines 1440–1490) ARE this brief; then
`tracker/loopmodel/L5-TERMINATION.md` §R4 (the two refutation witnesses `redir.json` and `mint.json`, the
per-step hunt and its hit list — seeds 74 and 139 re-mint at the same (v,K) twice; §R4.4 as corrected), the
hunt tooling under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r4/` (`gen.py`, the per-step classifier), the
modules `Loop/{Mints,Refuted,Supply,Hygiene,Carried,Residual,Order,Step,Queue}.lean`, and
`tracker/satterm/KEYED-EMPTY-STAGE7B.md` §3 (how minting feeds the queue's own cleanup — the pump's fuel).

## Checkpoints, in the reviewer's order

R5.1 **Drive the pump; aim for W.** The pump: a mint at key (v,K) installs `v <- (w,K)` with fresh `w`;
     eliminating `w` (makeEmpty/unify/makeConcrete — all free moves) withdraws the carrier; the key is
     open again and the loop may mint at (v,K) a second time, installing `v <- (w',K)`, and so on. Two
     hunt seeds already close the first two links (re-mint at the same key twice). Build a generator that
     favours the third link: shapes where the fresh variable is forced empty/concrete/aliased right after
     the mint (the mint's own cancellation partner present in the input, as in W2/W3/G7), at adversarial
     dequeue orders (id bases), with the model as the fast oracle (`lake exe looptrace` with a generous
     fuel; count re-mints per key per solve). Report the maximum re-mints at one key found, the seeds,
     and REPLAY every candidate with ≥3 re-mints at one key through the compiler at ten id bases. A
     compiler run that exceeds the harness's time cap is a HANG candidate: report it at once with the
     seed, base and flags, and confirm with a second run under a longer cap. If a genuine divergence is
     found, prove it in Lean as `not_Terminates` on that initial state (the W outcome), in the style of
     `DefaultSatDiverge`/`KeyedLoop`.
R5.2 **The charging lemma, stated so it can be refuted.** "Between two minting steps at the same (v,K)
     the loop performs an elimination of a variable the loop did not mint for (v,K)" — or whatever exact
     form survives R5.1's data; state it in Lean over `Reaches`/`Trail`, and either refute it with R5.1's
     seeds or prove it. If it holds, derive the mint count for the loop from `KMintRun.mints_le` plus the
     elimination count, and say what bounds the eliminations of INPUT variables (at most |V₀|).
R5.3 **The dequeue order.** No measure in rounds 1–4 uses it. `Queue.lean` states `pop` as a function
     (deepest variable in the reverse-topological order, then smallest rhs hash, then most recent). The
     redirect's damage (a swallowed bare carrier) is transient in practice because the swallowing
     partition is dequeued and re-emitted before the key is examined again — make that a lemma: under
     the real order, between a carrier's loss at the redirect and the next examination of its key, the
     carrier is re-established; or show by a seed that it is not.
R5.4 **Otherwise, a stated fragment.** If R5.1 finds no witness and R5.2/R5.3 do not close, prove
     `Terminates` for an explicitly stated fragment (e.g. inputs whose one-part definitions are all
     concrete, or the no-redirect fragment), and state the residual precisely with the strongest
     refutation data.

Outcomes, say which: (W) a compiler-reproduced divergence + `not_Terminates`; (T1) `Terminates` for
every satisfiable `Wf s₀` with an explicit bound; (T2) a fragment + the exact residual.
Constraints as always: audit 0 non-standard axioms (3376 theorems / 849 jobs before you), `#print axioms`
in scratch under `/home/dmitry/.claude/jobs/880c725d/tmp/L5r5/`, no `sorry` in a finished module, no silent
weakening, never `lake exe cache get`, no new `require`, no new project, never touch `~/research/leanwork`,
`CutSearch.lean` out of the root import list, disk tight, gzip traces, `pkill -f` matches itself; long hunts
under `setsid nohup` with a log (background shells are capped at ten minutes).

## Report
Append a dated "Round 5" section to `tracker/loopmodel/L5-TERMINATION.md` (statements verbatim, the hunt's
generator parameters and hit table, every compiler replay with its command, outcomes, side-by-side table for
anything weakened); update the plan's L5 row and the README additively. A reviewer re-runs everything.
