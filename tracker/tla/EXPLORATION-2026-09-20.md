# Would TLA+ help the widget preview? An evidence-based assessment

**Note on deliverables:** `preview.tla` was written to
`/tmp/claude-1000/-home-dmitry-research-ermine/993fdba9-280c-4c9d-8d90-19fe4dad7266/scratchpad/tla/preview.tla`.
`report.md` could **not** be written — the harness refuses report/summary `.md` files from a
subagent ("Subagents should return findings as text, not write report files"). Its full
content is below; paste it to that directory if you want it on disk.

**Summary.** The preview really is a protocol: four actors, one lock, one timer, and a
client reducer, and its last three review rounds found interleaving defects by *reading*.
Of the nine protocol defects in its history, **six would have been caught by exhaustive
model checking of a spec a person would plausibly write**, three only if the spec modelled
something specific, one not at all; the five non-protocol defects (Bottom memoisation, the
five swallowed catches, symlink identity, the test-oracle bug, `Encode.spine`) would have
been caught by **none** of it. TLA+ with TLC is the right instrument *here* and Lean is not,
for one reason: the questions are "does some interleaving break this", the state space is
tiny and finite, and TLC does the search and prints the trace — whereas the repo's Lean style
earns its keep on unbounded algorithmic questions (solver termination) where TLC could not
even state the theorem. **Recommended: a 6-10 hour first session producing a checked TLC model
of the queue + watchdog + stuck protocol, plus one decision it settles that reading has not
(phase 2b vs clear→discard→answer). Not recommended: trace validation, yet.**

Nothing in this report was executed. No JVM was started. `preview.tla` is a **DRAFT SKELETON,
never parsed and never model-checked** — it says so at its top.

Sources read: worktree `/home/dmitry/research/ermine/ermine-scala-wt-widget-preview` at
HEAD `b7b93daa1fc47d92a148b5b958ecdf2e74e517af`. All `:NNN` below are lines in
`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala` unless another file is
named.

---

## 1. SCOPE: what is a protocol, and what is not

### 1.1 Actors

| Actor | What it is in the code | Why it is in the model |
|---|---|---|
| Client / extension | `editor/vscode/src/preview-core.js` (`stuckReduce`, `:302-370`) | it holds state (`highWater`, `stuck`, `running`) derived from two independently-sent edges; WP-7's defect lived here |
| RPC reader / dispatch thread | `Rpc.scala:429-440` loop; `Preview.render` `:553`, `Preview.schema` `:649`, `Preview.cancel` `:749`, `Preview.invalidate` `:766`, `Preview.shutdown` `:819` | the only producer into the queue and the only refuser; takes `Preview.lock` (`:80`) |
| Preview thread | `loop` `:1399`, `takeJob` `:895`, `runJob` `:940` | the single consumer; every "who answers" race has it on one side |
| Watchdog timer thread | `arm` `:2131`, `fire` `:2245`, `fireCancel` `:2276`, `firePhase2` `:2332`, `fireStuck` `:2367` | it answers, mutates and notifies *while the preview thread is still inside the job* |
| Evaluator | `Runtime.swhnf`'s head check, reached via `ErmineRuntime.armCancel`/`disarmCancel` at `:2288`, `:2336`, `:2359` | modelled **only** as "the job ends in one of five ways" — see 1.3 |

### 1.2 Shared state and messages worth modelling

| Shared state | Location | Written by |
|---|---|---|
| `jobs` queue | `:81` | dispatch (enqueue, displace, coalesce), preview (dequeue), timer (drain) |
| `inFlight`, `cancelledInFlight`, `answeredInFlight` | `:96`, `:97`, `:191` | preview + timer, decided by `claimAnswer` `:196` |
| `stuck`, `stuckWhy`, `stuckJob`, `stuckSeq` | `:128`, `:435`, `:142`, `:167` | timer sets (`fireStuck` `:2375-2387`), preview clears (`clearStuck` `:1298`) |
| `alive`, `stopping` | `:176`, `:98` | preview's outermost `finally` `:1421`; `shutdown` `:821` |
| `armEpoch`, `armed`, `cancelTask` | `:420`, `:407`, `:428` | preview arms/disarms, timer reads |
| `ErmineRuntime.cancelTarget` (process-global) | armed `:2288`, disarmed `:2336`, `:2359` | timer arms, preview clears |
| `bootToken` (at most one outstanding) | `:351`, minted `:712`, released `:696` | dispatch mints, preview/`answerAll` release |
| `dirtyGeneration` | `:216`, bumped per POST `:777` | dispatch |
| client `highWater` / `view` | `preview-core.js:292-294` | client reducer only |

Messages: `ermine/render`, `ermine/schema {binding}`, `$/cancelRequest`, the answers
(`{ok:true,…}`, `{ok:false,status,message,stuck?}`, JSON-RPC `-32800`, `-32603`),
`ermine/preview/stuck {stuck,message,seq}`, `window/showMessage`,
`ermine/preview/invalidated`, `window/workDoneProgress/create` + `$/progress`.

### 1.3 Deliberately NOT modelled

| Out of scope | Why |
|---|---|
| Evaluator semantics — thunks, whiteholes, `Bottom` memoisation, `Encode.spine` | the model's alphabet is "the job ended: ok / failed-by-returning / threw non-fatal / threw fatal / never ends". Q14's memoisation (tracker `:1963-2008`) is a *data* fact; no protocol abstraction can discover it |
| Placement, roots, shadowing, symlinks (`placeAndSession` `:1495`, `inferredRoot` `:1960`, `sameFile` `:1652`) | a pure function of the filesystem; one refusal outcome, no interleaving |
| Performance — boot seconds, RSS, the WP-6 stage 2 A/B | TLA+ has no clock and no cost model; §2.5's measured table is the right instrument |
| JSON shapes, scrubbing, redaction (rule A5) | covered by `TestLspRobustness` A-group; not state |
| Q16's double boot (tracker `:2056-2102`) | a *waste* question, not a safety one; modelling it only restates the question |

---

## 2. STATE / ACTION / PROPERTY INVENTORY

`T` = stated in `tracker/JSON-WIDGET-PLAYGROUND.md`; `C` = read directly out of the code;
`I` = inferred by me (not stated anywhere I found).

### 2.1 Actions

| Action | Code it abstracts | Notes |
|---|---|---|
| `ReqEnqueue(r,k)` | `:587` / `:667` | after a peek-mint-decide (`:566`, `:657`) that is *allowed to be wrong* |
| `ReqDisplaceRender(r)` | `:586` + `answerAll` `:685` | dequeues **all** renders, answers each `-32800` |
| `ReqRefuseDead/Stopping/Stuck` | `:569`, `:571`, `:579`/`:666` | the stuck refusal is result-shaped and carries the marker |
| `CancelRequest(r)` | `:749-760` | queued → removed+answered; in flight → *flag only* |
| `PostInvalidate` | `:766-805` | guarded by `alive ∧ ¬stopping ∧ ¬stuck`; **coalesced** into the earliest slot `:795` |
| `Shutdown` | `:819-828` | drains, then `cancelTimer` — DM-2's only clear on that path |
| `TakeJob` | `:895-923` | includes the loud `cancelArmedFor` check `:905` |
| `ArmWatchdog` / `Disarm` | `:2131-2167` / `:2172-2177` | the `armEpoch` bump is what makes a `cancel()` that lost the race harmless |
| `BootBegin` / `BootEnd` | `unwatched` `:2204-2208` | **the boot is deliberately unwatched**; the re-arm is in a `finally` |
| `JobEnds(outcome)` | `doRender` `:1659` / `doSchema` `:1730` | five outcomes (1.3) |
| `CatchCancelled` | `:996-1026` | order is **clear → discard → answer** (DM-1) |
| `CatchThrowable` | `:1027-1042` | sets `fatal = isFatal(e)` `:1033` first, by a store that cannot throw |
| `Fin*` (7 steps) | `:1044-1172` | disarm, clearCancel, releaseToken, claim+`crashAnswer`, clear `inFlight`, discard, clearStuck+recovered |
| `ThreadCrash` / `RescueInFlight` / `DrainOnDeath` | `:1407-1416`, `:1439`, `:1453` | a crash may land *between* dequeue and `runJob` (`:885-894`) |
| `FirePhase1Cancel` | `fireCancel` `:2276-2314` | arms the flag and does **nothing else** |
| `FirePhase2Fallback` | `firePhase2` `:2332-2346` | **clears the flag first**, then falls back |
| `FireStuckClaim/Answer/Drain/Notify` | `:2367-2455` | one locked step sets claim+stuck+stuckJob+seq **and takes the whole queue** |
| `Deliver(m)` | `Wire.send` is synchronised (`Rpc.scala:390`) but **two threads race into the monitor** | the unordered-delivery action; this is the heart of the `seq` design |
| `ClientNotification/AnswerMarker/Restart` | `preview-core.js:306-335`, `:337-342`, `:344-359` | rules (1), (3) and DD-2 |

### 2.2 Safety properties

| # | Property | Source | Code |
|---|---|---|---|
| S1 | every request answered **at most once** | T/C | `Rpc.deferredRequest` one-shot `Rpc.scala:641-646`; `claimAnswer` `:196` |
| S2 | one in flight, **at most one queued render** | T (§2.5) | `:586`; accessor `queuedRenders` `:839` |
| S3 | **at most one queued `Invalidate`** | C (stated at `:792`) | coalescing `:795` |
| S4 | no answer after a displacement answer for that id | I | `:586-591` |
| S5 | the cancel is armed **only** for the preview thread, **only** while its job runs, and is **cleared before the answer** that claims recovery | C (DM-1) | `:2288`, `:1020-1024`, `:905`, `:1051` |
| S6 | no job is handed out with a cancel armed | C (stated `:896`) | `:905-909` |
| S7 | `stuck ⇒ stuckSeq > 0 ∧ (stuckJob ≠ null ∨ forgotten-as-fatal)`; the triple never half-set | C | `:2375-2387`, `:1302-1309`, `forgetStuckJob` `:1181` |
| S8 | `seq` **strictly monotonic per server lifetime**, and the state implied by the highest `seq` is the server's state | T (§4 rule 1, IM-1) | `:2386`, `:1308` |
| S9 | `stuck: true` on **exactly** four answers (stuck refusal, watchdog's own, its drain's) and nothing else | T (Q8) | `:579`, `:666`, `:2413`, `:2418`; negative conjunct `:1040` |
| S10 | nothing left queued once stuck | C (review M1) | drain `:2399`, rationale `:2235-2244` |
| S11 | no cancel armed once the thread is idle or stopping | C (DM-2) | `:1051`, `:2497` |
| S12 | at most one outstanding boot token; every refused/displaced job releases its own | C | `:712`, `:691`, `:1054` |
| S13 | a stale timer task (epoch moved) changes nothing | C | `:2150`, `:2175`; guards `:2281`, `:2335`, `:2373` |

### 2.3 Liveness (needs the stated fairness)

| # | Property | Source | Fairness needed |
|---|---|---|---|
| L1 | every request **eventually** answered | T ("a request dropped without an answer is a request the client waits on for ever", `:581-585`) | WF on preview-thread steps, WF on the timer, WF on delivery |
| L2 | if the wedged job returns non-fatally, stuck **eventually** clears | T (Q10) | WF on `runJob`'s `finally` |
| L3 | the preview thread never dies leaving a request outstanding | T (M1 of stage A, `:169-176`) | none — `alive := false` precedes the drain |
| L4 | with `cancelOnTimeout`, every incident ends in 2a or 2b (never stays in phase 1) | I | WF on the grace timer |
| L5 | after a wedge that recovers, the **client** eventually re-renders | C (DM-2 of WP-7's review, `preview-core.js:322-331`) | WF on delivery + the reducer |

---

## 3. DEFECT REPLAY: would exhaustive checking have found it?

Strict reading. "Yes" = a spec someone would plausibly write *before knowing the answer*,
checked against §2, produces a counterexample.

### 3.1 Protocol defects

| # | Defect | Found? | One-line reason |
|---|---|---|---|
| 1 | **WP-5B**: jobs queued behind a wedged job stranded when the watchdog fired (`:2235-2244`) | **YES** | S10 (`stuck ⇒ queue empty`) or L1 fails on the first trace with a second request queued before the fire; the queue has no other consumer |
| 2a | the watchdog's `cancel()` could lose the race into `run` → **arm epoch** (`:2169-2177`) | **YES, only if** the spec models a timer task that may already be inside `run` when cancelled | that is a standard modelling choice (a fire guarded by a serial); without the epoch S13 fails |
| 2b | the watchdog clock **covered the boot** (`unwatched` `:2179-2208`) | **NO** | nothing is violated — the request *is* answered. It is a budget decision ("the timeout is about evaluation, not a 2-7 s boot"), invisible to an untimed model unless you first state the property you are trying to discover |
| 3 | **WP-5A**: the crash path could kill the preview thread silently; a job out of the queue but not yet in `runJob` (`:885-894`) | **YES, only if** the spec permits a crash *between* dequeue and the `inFlight` record | with that atomicity L1/L3 fail, and the trace is exactly `rescueInFlight`'s reason. The **fix** ("a reference store cannot throw") is a Java fact TLA+ cannot express — the model says *you need a rescue*, not *how to make the record safe* |
| 4a | notification ordering needed `seq` (Q8-Q12, IM-1) | **YES** | two threads, two edges, one unordered monitor: the canonical TLC counterexample; without `seq`, S8/L5 fail in ~4 steps |
| 4b | `seq` must **reset** across a restart (DD-2) | **YES, only if** the spec models a server restart with a surviving client | a second lifetime, and a modelling decision TLC cannot suggest |
| 5 | **WP-7**: the client lost the recovery re-render when the clear overtook the rise (`preview-core.js:322-331`) | **YES** | L5 with unordered delivery: TLC reorders `{stuck:false}` ahead of `{stuck:true}` and the client never re-renders. The clearest win in the list |
| 6 | **WP-6 DM-1**: answer-before-clear on the cancel arm (`:1000-1024`) | **YES, only if** the invariant ties the answer's *content* to the state at send time (S5's third clause) | the test that found it was red only 2 runs in 3; a model checker makes it deterministic — but someone must think to write "the answer claims X, so X must hold when it is sent" |
| 7 | **DM-2**: `shutdown` inside the grace leaked the armed cancel (`:2497`, clear path (4)) | **YES** | S11 fails: interleave `Shutdown` between `FirePhase1Cancel` and `FirePhase2Fallback`; the phase-2 task is cancelled and nothing clears the flag |
| 8 | **phase 2b colliding with clear→discard→answer** — traced BY READING ONLY, no test | **YES** | exactly what exhaustive enumeration decides and reading does not; the strongest single argument for the tool on this codebase |
| 9 | "**a `Preview` can cancel a second time**" — by reading only | **YES** | reachability of two live armings is an invariant check over the arming protocol (`armCancel` refuses, `:2288`); TLC answers it or exhibits the trace |

Score: **6 unconditional yes, 3 conditional, 1 no.**

### 3.2 Non-protocol defects — the honest half

| Defect | Found? | Reason |
|---|---|---|
| `Bottom` memoisation of thrown errors (Q14; `Runtime.scala:231`, `:245-250`) | **NO** | a value-level fact about the evaluator; a spec could carry `sessionPoisoned` as a boolean, but only once you already knew |
| **five catches swallowing `Cancelled`** (`Prim.apply`, `Box.apply`, `IO.Unsafe.eval`, the foreign invoke, `Bottom.thrown`) | **NO — and worse** | the spec's `CatchCancelled` action *assumes* the cancel propagates; the model would have asserted the bug away. DM-3 (`Bottom.thrown`) was found by a human reading catch arms |
| symlink path identity (`sameFile` `:1652`) | **NO** | filesystem semantics, out of the alphabet |
| the test-oracle bug (`4220cd89`, "the frame property's oracle mis-measured a body that starts with LF") | **NO** | a bug in the checking apparatus; a spec adds a *second* apparatus with the same exposure — this is a risk the model buys, not one it removes |
| `Encode.spine` unbounded on a cyclic list (WP-20), `ppRuntime` depth cap lost (WP-21) | **NO** | evaluator/printer termination; the repo's Lean style is the tool that *could* speak about these |

---

## 4. TOOL COMPARISON, for this job

"Offline" matters: the production environment is a closed network (§10). What counts is
whether the tool is *one file you can carry in*.

| Tool | What it gives here | Cost to write / maintain | Counterexample quality | Fairness & liveness | Bounded? | Offline | Learning curve |
|---|---|---|---|---|---|---|---|
| **TLA+ / TLC** | exhaustive interleaving of 4 actors over a small finite space; invariants + temporal properties | ~300-500 lines for §2; a day to first green, hours per change | **best of the list**: shortest trace, lasso for liveness, replayable | full: `WF`/`SF`, `[]`, `<>`, `~>` | bounded by your constants, exhaustive within them | **single self-contained `tla2tools.jar`, Java 11+** (TLC + PlusCal + SANY + TLaTeX) | moderate; the *modelling* judgement is the real cost |
| **PlusCal** (same jar) | processes with labels; reads like the Scala | same jar; translator writes the TLA+ | same | same | same | same jar | lower for a programmer, but labels re-invent atomicity boundaries this code already states as `synchronized` blocks |
| **Apalache** | symbolic (SMT/Z3); no explicit state explosion; needs type annotations | more per spec (types, idioms) | trace, SMT-shaped | **liveness experimental; `ENABLED`, `WF`, `SF` documented as not supported** | bounded by steps (BMC) | JVM 17/21 + bundled Z3; a release archive | steeper |
| **Quint** | TLA semantics, typed modern syntax, REPL, simulator, transpiles to TLA+/Apalache | comparable to TLA+; best feedback loop | good; simulator finds shallow bugs fast | via backends — inherits Apalache's limits when symbolic | same | npm/brew/nix/GitHub binaries — **needs a fetch**; Node **is** here (`/home/dmitry/.local/bin/node`) | lowest of the TLA family |
| **P** | actor/state-machine language with runtime monitors; "hot state" liveness | a different program, not a model of this one | good, executable | liveness via temperature; systematic *exploration*, not exhaustive | bounded by schedules explored | **.NET toolchain; nothing .NET on this machine** | moderate, whole ecosystem |
| **Alloy 6** | relational + temporal (`var` sigs, LTL) over bounded traces | compact for structure; awkward for counters, queues, three program counters | instances, browsable; less trace-shaped | LTL over bounded traces; no `WF_vars`-style idiom | bounded scope **and** trace length | **single jar, Java 17+** | moderate |
| **Lean 4 (proof)** | theorems, unbounded, for all inputs | very high: build an interleaving semantics before you can state anything | none — a failed proof is not a trace | whatever you encode | unbounded | **already installed** (`~/.elan/bin/lean`, `lake`; `tracker/lean/lean-toolchain` = `leanprover/lean4:v4.33.1`) | highest |
| **Lean 4 (executable model + exhaustive search — this repo's L1/L2 style)** | one artifact that is both a model and an oracle you can diff against real traces | high: you write the BFS, visited set, fairness, lasso detection and printer — all of which TLC gives free | as good as the printer you write | you implement it | you choose | **already installed** | high, but the team works this way |
| **No new tool: stateful ScalaCheck + deterministic scheduler** | properties over the **real code**, inside the existing gate | medium: seams exist (`beforeJob` `:450`, `duringBoot` `:458`, `timeoutMillis` `:227`, `graceMillis` `:262`), but `java.util.Timer` and real threads must be made schedulable | a failing seed, replayable; shrinking helps | none — you sample schedules | **random, not exhaustive** | nothing to download (`scalacheck-binding` already in core's test sources, `build.sbt:88-90`) | lowest; 10 properties already exist in `TestPreviewCancel` |

### 4.1 TLA+ vs Lean, directly, for this system

| Question | TLA+/TLC wins | Lean wins |
|---|---|---|
| "Can some interleaving of 4 threads break invariant P?" | **yes** — the tool's whole purpose; 3 threads × a queue of ≤2 × 5 outcomes is a state space TLC eats | no: you must build the interleaving semantics first |
| "Under fairness, is every request eventually answered?" | **yes** — `~>` plus `WF_vars`, with a lasso counterexample | no: liveness under fairness is a research-grade encoding |
| "Does this loop terminate for all inputs?" (the row solver) | no — unbounded data, no measure; TLC can only sample | **yes** — exactly `tracker/lean/Rowpartition/KeyedSplit.lean`, `KeyedRow.lean`, `DefaultTerm.lean` |
| "Does the model agree with the implementation over the whole corpus?" | possible (trace validation), but new machinery | **yes, already built**: `LOOP-MODEL-PLAN.md` L1→L2 is an executable Lean model diffed against the compiler |
| "Is the answer a theorem or a bounded check?" | bounded, and honest about it | **theorem** |
| Cost for the preview's questions | hours | days, for a worse answer |
| Cost for the solver's questions | cannot state them | the right instrument |

**They are not competitors here.** The Lean work is about an *algorithm over unbounded data
with a termination measure*; the preview is *finite-state concurrency*. Lean on the preview
would be 5-10× the effort for a weaker result (no fairness machinery, no counterexample
printer). TLC on the solver would be useless. The real overlap is the **working style** the
Lean programme established — an executable model whose traces are diffed against the real
thing — which transfers to TLA+ directly and is why trace validation is a natural *second*
step rather than a novelty.

---

## 5. THE CORRESPONDENCE PROBLEM: a spec is not the code

| Option | What it buys | What it costs | Verdict |
|---|---|---|---|
| **(a) Design document only** | a *checked* statement of §2's invariants; settles open questions (phase 2b collision, "cancel twice") before they are built; a reviewable artifact in the tracker's own idiom | drifts silently; a green TLC run proves nothing about `Preview.scala` | **take this first.** The tracker (§2.5, §4's rules, Q8-Q16) is *already* a prose spec — this only makes it executable |
| **(b) Trace validation** — log protocol events, check the log against the spec with TLC | mechanical correspondence; mirrors the repo's own `looptrace` diff; the published method (arXiv 2404.16075) is used by CCF and etcd | needs event logging the server lacks, a stable vocabulary, a harness; covers only schedules actually run | **second, if (a) pays.** Do not start here |
| **(c) ScalaCheck generators/oracles derived from the spec's actions** | tests the real code, in the existing gate, no new tier | a hand translation that can itself be wrong (see `4220cd89`); random, not exhaustive | **the pragmatic complement**; arguably the best value-per-hour if only one thing is done |

### 5.1 Which events a spec needs, and what the log carries today

The wire is already fully logged under `-Dermine.lsp.log`: **every** incoming message
(`Rpc.scala:605`, `">> <method>"`) and **every** outgoing frame (`Rpc.scala:390`, `"<<"`).
Format: `HH:mm:ss.SSS <text>` (`Main.scala:13-20`).

| Event a spec needs | In the log today? | Evidence |
|---|---|---|
| request arrives (`ermine/render`, `ermine/schema`, `$/cancelRequest`) | **yes** | `Rpc.scala:605` |
| answer sent (any shape) | **yes, but CLIPPED at 2000 chars**, and `document(...)` puts `document` *before* `generation`/`stale` (`:2120-2122`) — so on a real render **the fields a spec checks are exactly the ones clipped away** | `Rpc.scala:390`, `:243-244` |
| enqueue / displacement / refusal | **displacement and refusals yes** (`answerAll` `:692`); **plain enqueue no** | `:685-693` |
| job **started** (which job dequeued) | **no** | `takeJob` `:895` logs only the BUG case `:908` |
| job **ended ok** | **no** — the happy path is silent in `Preview` (only the wire `<<` line) | — |
| boot begin / end | **end yes** ("render session booted in Xs"); begin no | `:2052` |
| watchdog armed / disarmed / epoch | **no** (only the failure to arm) | `:2131-2177`, `:2165` |
| watchdog fired: phase 1 / phase 2b / stuck | **yes** | `:2304`, `:2310`, `:2342`, `:2403` |
| queue drained while stuck | **yes, per job** | `:2417` |
| stuck cleared, with `seq` | **yes** | `:1312` |
| `{stuck:true/false}` notifications with `seq` | **yes via the wire line** (small enough not to clip) | `:2450`, `:1373`, `Rpc.scala:390` |
| session discarded, and why | **yes** | `:2086` |
| thread crash / loop failure / stop | **yes** | `:1035`, `:1414`, `:1424` |
| cancel armed / cleared (`cancelTarget`) | **partly** — arming yes (`:2304`); `clearCancel` `:2357-2365` is **silent** except in the BUG case `:908` | — |
| **thread identity on every line** | **no** | `Main.scala:19` writes only a timestamp |
| **a monotonic event serial** | **no** — millisecond timestamps, so two threads can tie | `Main.scala:18` |

**Conclusion for (b):** the log carries most of the *external* protocol and roughly half the
*internal* transitions. To make it a trace-validation source you would add thread name + a
monotonic serial on every line (one change at `Main.scala:19`), a start/end line per job,
arm/disarm/clearCancel lines, and either raise `clip` for answers or log a compact structured
event beside the `<<` line. Small and self-contained — but a change on the hot path, and it
should be a decision, not a side effect.

---

## 6. DRAFT SPEC SKELETON

`…/scratchpad/tla/preview.tla`. **UNCHECKED: never parsed by SANY, never translated, never
run through TLC.** It contains the variable list with a code reference per variable, `Init`,
~30 named `Next` disjuncts each annotated with the line it abstracts, the fairness
conjunction, 13 safety invariants and 4 temporal properties from §2, and the bounds below.
Several action bodies are named stubs with their code reference — that is the "skeleton"
part; the bodies carrying the *interesting* atomicity (`TakeJob`, `FirePhase1Cancel`,
`FireGuard`) are written out.

**Why plain TLA+ and not PlusCal** (stated in the file's header): PlusCal's labels *are* its
atomicity boundaries, and here those boundaries are already explicit in the code — every
interesting step is a `lock.synchronized { … }` block (`:80` names the monitor and states what
may not be done under it). One action per locked block is a faithful translation; PlusCal
would ask me to re-invent the same boundaries as labels and hide them behind a translator.

Bounds for a first run, chosen so TLC plausibly finishes in minutes:

| Constant | Value | Why that is enough |
|---|---|---|
| `Reqs` | `{r1, r2}` | one in flight plus one queued is the whole "latest wins" rule |
| `MaxInv` | 2 | coalescing needs two posts to be observable |
| `MaxFire` | 2 | phase 1 then phase 2b |
| `MaxCrash` | 1 | the crash paths are independent |
| `CancelOn` | two runs, `FALSE` then `TRUE` | it is a default-OFF switch (`:249`); both behaviours ship |
| outcomes | all 5 | ok / failed-by-returning / threw non-fatal / threw fatal / wedged |

A state constraint caps `fireCount`, `invCount`, `crashCount` so the model is finite.
**Unverified**: I have not run TLC and cannot say the actual state count.

---

## 7. COST, TOOLING ON THIS MACHINE, RECOMMENDATION

### 7.1 What is already here

| Tool | Present? | Evidence |
|---|---|---|
| `tlc` / `tla2tools.jar` | **no** | `which tlc` → nothing; no `*tla2tools*` under `/home/dmitry` (maxdepth 3) |
| `apalache` | **no** | `which apalache` → nothing |
| `quint` | **no** | `which quint` → nothing |
| `java` | **not on PATH**, but **installed**: `/home/dmitry/.local/ermine-toolchain/jdk-21.0.12.1+1/bin/java` — the path `bin/ermine-lsp:23` uses | `command -v java` → nothing; `ls` of that path → present |
| Lean 4 | **yes** — `/home/dmitry/.elan/bin/{lean,lake,elan}`; `tracker/lean/lean-toolchain` = `leanprover/lean4:v4.33.1` | `command -v lean` |
| Node | **yes** — `/home/dmitry/.local/bin/node` (relevant only for Quint) | `command -v node` |
| ScalaCheck | **yes**, already in core's test sources | `build.sbt:88-90` (per tracker §11) |

So the only download the recommended path needs is **one file**: `tla2tools.jar`
(documented self-contained, Java 11+; JDK 21 already here). That is also the closed-network
answer: TLA+/TLC is the *only* candidate in §4 that is a single file with no toolchain fetch
and no runtime dependency beyond a JVM the project already ships with.

### 7.2 Effort

| Item | Estimate |
|---|---|
| First **checked** model: queue + one in flight + displacement + refusals + `takeJob` + `runJob`'s finally, with S1-S4, S10, L1 | **4-6 h** |
| Add the watchdog (arm/epoch/fire/fireStuck/drain) + S7, S8, S13, L2 | **+3-4 h** |
| Add WP-6's two phases + the cancel flag + S5, S6, S11, L4 | **+3-4 h** |
| Add the client reducer + unordered delivery + S9, L5 | **+2-3 h** |
| **Total covering §2 in full** | **12-17 h**, over 2-3 sessions |
| Maintenance | ~1-2 h per protocol change (e.g. WP-14's connection lifecycle) |

### 7.3 The first session, concretely

1. Fetch `tla2tools.jar` once (single file) and put it beside the other toolchain bits.
2. Write `preview.tla` for the **queue only**: render/schema/cancel/invalidate, `takeJob`,
   `runJob`'s `finally`, shutdown, thread death. Properties S1-S4, S10, L1.
3. Check it, then **deliberately re-introduce WP-5B** (delete the drain from `fireStuck`) and
   confirm TLC produces the counterexample. This is the calibration run: if the model cannot
   re-find a defect the team already fixed, the model is wrong, not the code.
4. Then, and only then, use it on the two things reading has **not** settled: **phase 2b
   colliding with clear→discard→answer**, and "**a `Preview` can cancel a second time**".
   Both are recorded in the tracker as read-only conclusions with no test.

### 7.4 What would make this not worth it

| Signal | Why it kills the case |
|---|---|
| WP-6 stage 3 is declined and `cancelOnTimeout` stays off for good | the two-phase watchdog — the most intricate part — becomes dead code, and the rest is small enough for the existing 10 properties |
| The preview is judged done and no further protocol tickets land (WP-13/WP-14 deferred) | the payoff is on *future* changes; the historical defects are already fixed |
| The calibration run (step 3) fails to re-find WP-5B | the abstraction is wrong and needs rework before it can be trusted |
| Nobody but one person can read TLA+ | the tracker's value is reviewers checking each other; a spec only one person can review is a second unreviewed artifact |
| It grows past ~500 lines, or starts modelling the evaluator | it stops being a protocol model and becomes a second implementation, with the `4220cd89` oracle risk |

### 7.5 Recommendation

| | |
|---|---|
| **Do** | (a) spec-as-design-document, in TLA+, checked by TLC, scoped to §1.1's four actors and §2's properties; 6-10 h to a useful first model; calibrate against WP-5B; then answer the two read-only conclusions |
| **Also do, if only one thing** | (c) — translate the spec's actions into a stateful ScalaCheck property in `TestPreviewCancel` (the seams already exist), because it tests the real code inside the existing gate |
| **Do not do yet** | (b) trace validation — it needs a hot-path logging change and a stable event vocabulary; revisit after (a) has paid once |
| **Do not use** | Lean for this protocol (5-10× cost, no fairness machinery, no counterexample printer); P (.NET absent); Alloy 6 (awkward for counters and three program counters); Apalache (liveness experimental, `WF`/`SF` documented unsupported — and fairness is half the value here) |

---

## Sources (documentation only; no third-party implementation source was read)

- [TLA+ tools (`tla2tools.jar`: TLC, PlusCal, SANY; Java 11+)](https://github.com/tlaplus/tlaplus)
- [Apalache — Supported Features](https://apalache-mc.org/docs/apalache/features.html); [PDR-017: Checking temporal properties](https://apalache-mc.org/docs/adr/017pdr-temporal.html) (liveness experimental; `ENABLED`/`WF`/`SF` not supported)
- [Apalache — Running the Tool](https://apalache-mc.org/docs/apalache/running.html) (JRE 17 or 21)
- [Validating Traces of Distributed Programs Against TLA+ Specifications (arXiv 2404.16075)](https://arxiv.org/pdf/2404.16075)
- [Trace Validation of Unmodified Concurrent Systems with OmniLink (arXiv 2601.11836)](https://arxiv.org/html/2601.11836v1)
- [Quint](https://quint.sh/); [Quint FAQ](https://quint.sh/faq)
- [P language](https://p-org.github.io/P/whatisP/)
- [Alloy 6](https://alloytools.org/alloy6.html); [Alloy download (single jar, Java 17+)](https://alloytools.org/download.html)

---

**Compliance notes.** No JVM, sbt, gate, smoke or CPU-heavy command was run; only `ls`,
`which`/`command -v`, `grep`, `sed`, `cat`, `git log`, file reads and web searches. Nothing
inside any git worktree was modified; `tracker/JSON-WIDGET-PLAYGROUND.md` was read only. No
monitors or background tasks were started. The only file written is `preview.tla` in the
scratchpad, labelled UNCHECKED at its top.
