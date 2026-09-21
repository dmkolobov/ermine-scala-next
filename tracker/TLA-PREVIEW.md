# TLA-1: a checked TLA+ model of the preview protocol

| | |
|---|---|
| Status | **PARKED by the user, 2026-09-20.** To be done in a FRESH SESSION, after more of the widget-preview work (tracker/JSON-WIDGET-PLAYGROUND.md, §14) completes. Nothing is built. |
| Origin | The user's question, 2026-09-20: the preview is async interaction with failures; would TLA+ help, and how does it compare with Lean? |
| Evidence | `tracker/tla/EXPLORATION-2026-09-20.md`: the read-only Opus exploration, verbatim, written against HEAD 0ee08425. NO TOOL WAS RUN for it. |
| Draft | `tracker/tla/preview.tla`, 297 lines. **UNCHECKED: never parsed, never translated, never model-checked.** Its own header expects syntax errors and at least one wrong invariant. It shows shape and size only. |
| Gate | none. This is an instrument and a design document, not a gate (docs/gate-policy.md). |

## Decisions

| # | Decision | By | State |
|---|---|---|---|
| D1 | Do the TLA+ work, in a fresh session, later | the user, 2026-09-20 | DECIDED |
| D2 | TLA+ with TLC, not Lean, for this protocol. Lean stays the tool for unbounded algorithmic questions (solver termination, the loop model) | recommended by the exploration and by the orchestrator; the user asked for the ticket on that basis | RECOMMENDED, confirm at session start |
| D3 | Plain TLA+, one action per `lock.synchronized` block, not PlusCal | the exploration | RECOMMENDED |
| D4 | The spec is a CHECKED DESIGN DOCUMENT first (option a). Trace validation (option b) is NOT started: it needs a hot-path logging change (thread name and a monotonic serial per log line, job start/end, arm/disarm/clearCancel lines, unclipped answer fields). Revisit only after (a) has paid once | the exploration | RECOMMENDED |
| D5 | Complement: translate the spec's actions into a stateful ScalaCheck property over the real code, in the existing suite and gate (option c) | the exploration ("also do, if only one thing") | OPEN, the user's |
| D6 | Not used: P (no .NET here), Alloy 6 (awkward for counters and program counters), Apalache (WF/SF documented as unsupported; fairness is half the value) | the exploration | RECOMMENDED |

## Scope

In: four actors (client reducer in `editor/vscode/src/preview-core.js`, the RPC dispatch thread, the preview thread, the watchdog timer thread) and the evaluator ONLY as "the job ends in one of five ways" (ok / failed by returning / threw non-fatal / threw fatal / never ends). The queue, exactly-once answering, the crash contract, the watchdog with its arm epoch, WP-6's two-phase cancel, the stuck triple and `seq`, unordered delivery to the client.

Out, and no protocol model can find these: evaluator semantics (Bottom memoisation, Q14; the five catches that swallowed `Cancelled`; `Encode.spine`, WP-20; `ppRuntime`, WP-21), placement/roots/symlinks, performance, JSON shapes. The exploration's own words on the five catches: "the model would have asserted the bug away".

Properties: S1-S13 and L1-L5 in the exploration's section 2, each marked stated-in-tracker, read-from-code, or inferred.

## The first session (6-10 h to a useful model; 12-17 h for the whole inventory)

1. Fetch `tla2tools.jar` once. Reported from documentation as one self-contained file needing Java 11+; JDK 21 is at `~/.local/ermine-toolchain/jdk-21.0.12.1+1`. UNVERIFIED until downloaded and run. No TLA+ tool is on this machine today.
2. Model the QUEUE ONLY: render/schema/cancel/invalidate, `takeJob`, `runJob`'s `finally`, shutdown, thread death. Properties S1-S4, S10, L1. Bounds: 2 requests, 2 invalidates, 2 timer fires, 1 crash, all 5 outcomes, `CancelOn` FALSE then TRUE.
3. CALIBRATE: re-introduce WP-5B (delete the drain from `fireStuck` in the model) and confirm TLC produces the stranded-job counterexample. If it cannot re-find a defect already fixed, the MODEL is wrong.
4. Only then put the two conclusions that are BY READING ONLY in commit 0ee08425 to the checker: phase 2b colliding with clear -> discard -> answer, and "a Preview can cancel a second time".
5. Process as for every ticket here: one implementer, a separate reviewer, design reviewed as well as implementation.

## Defect replay, corrected count

The exploration's summary line says "6 unconditional yes, 3 conditional, 1 no". Its own table has ELEVEN rows and reads 6 yes / 4 conditional / 1 no (the orchestrator's recount, 2026-09-20):

| Verdict | Rows |
|---|---|
| yes | WP-5B stranded jobs; ordering needs `seq`; WP-7 lost recovery re-render; DM-2 shutdown inside the grace; phase 2b collision; second cancel |
| only if the spec models X | the timer-cancel race (arm epoch); a crash between dequeue and the in-flight record; `seq` reset across a restart; DM-1 answer-before-clear (needs an invariant tying the answer's content to the state at send time) |
| no | the watchdog clock covering the boot: a budget decision, invisible to an untimed model |

The last two "yes" rows are not past defects; they are open by-reading conclusions.

## Drop it if

- WP-6 stage 3 is declined and `ermine.preview.cancelOnTimeout` stays off for good (the two-phase watchdog, the most intricate part, becomes dead code).
- No further protocol tickets land (WP-13/WP-14 deferred): the payoff is on future changes.
- The calibration run fails and the abstraction cannot be repaired cheaply.
- Only one person can read the spec: a spec nobody can review is a second unreviewed artifact.
- It grows past about 500 lines or starts modelling the evaluator.

## Refresh before starting

The exploration's `:NNN` line references are to `lsp/Preview.scala` at 0ee08425 and will drift. Re-derive the action list from the code at the session's HEAD; treat the draft and the line numbers as a map, not as truth.
