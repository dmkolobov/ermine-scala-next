# LSP Stage 4, item 7.4 — THE ADAPTIVE DEBOUNCE, derived from the measured check time (Tier 0 + Tier 2 at adoption)

Implementer report.  Branch `scala3-migration`, from `85eb150` (7.0, 7.2, 7.1a and
7.1b committed).  No commit.  Scratch: `<scratch>/7.4/`.

**OUTCOME: GREEN.**  The acceptance is the small file and it moved **0.3204 -> 0.1719 s
(-149 ms, -46.4 %)** on an interleaved A/B; the largest module is unchanged (the
policy asks for the old 300 ms on every round of it).  lsp-smoke **494 -> 510**,
every other gate at its baseline.

> ### CLOSING ROUND — what changed after the review (`LSP4-7.4-REVIEW.md`, verdict ADVANCE, Tier 2 **1026/1026** clean)
>
> Four documentation fixes and one test-assertion relaxation; **no constant and no code semantics changed**.
>
> | id | disposition |
> |---|---|
> | **F-1** | The `Min` = 150 argument no longer overclaims.  It said 150 ms "coalesces within-word bursts at any speed"; at 40-60 wpm (200-300 ms per character) on a file whose check is at or below the floor it coalesces NOTHING and every character gets its own check.  The scaladoc, report §1.1 and `docs/lsp.md` now say that outright, with the reason it is acceptable: on such a file the check is cheaper than the window (<=43 % duty cycle, <=150 ms added request wait, fresher squiggles), and a check per character on an EXPENSIVE file is prevented by the clamp, not by the floor. |
> | **F-2** | "the window cannot jump between regimes on one slow check" is FALSE and is deleted: `[100,100,400,400,100]` has median 100 and one more 400 moves it to 400, so a period-2 cost alternates the window between 150 and 300 forever.  §2.1 now states that the CLAMP bounds the feedback, that the median only smooths, and that the alternation is harmless because both ends of it are clamp values. |
> | **F-3** | "a document's FIRST check is unchanged at 300" was vacuous -- didOpen/didSave check synchronously and pay no window, so `policy(Nil)` is reachable only by a didChange on a never-checked document.  Now stated as the defensive case, with the measurement: `Reader.e`'s first keystroke waited **150 ms off one sample**. |
> | **F-4** | The `debounce` initializationOption is documented beside `fastMode` (`docs/lsp.md` "Fast mode and the pinned debounce"), with a cross-reference from the Latency section. |
> | **F-5** | `lsp-client.py`'s audit was `waited == policy`, which would fail on a CORRECT server the first time a fixture queues two documents: `quiet()` waits the MINIMUM of the queued windows and runs both checks back to back.  Relaxed to `waited <= policy` with the reason in a comment; `policy == clamp(150, median, 300)` and the sample bound are unchanged. |
>
> `lsp-smoke.sh` re-run after the fixes: **PASS, 510 checks**.

THE POINT OF THE ITEM, in one line: a small file should stop waiting 300 ms for a
31 ms check, and the large file must not get worse.

## 1. THE POLICY

    D(C) = clamp(Min, Ratio x C, Max)     Min = 150 ms, Max = 300 ms, Ratio = 1

where **C is the MEDIAN of the last `Window` = 5 measured check times OF THAT
DOCUMENT** and **D = Max while a document has no history at all**.  In code:
`Diagnostics.Debounce` (the function and the four constants),
`Documents.Doc.checkMillis` (the samples, carried across an edit),
`Diagnostics.run` (records one sample per check),
`Diagnostics.install` (computes the window and logs what it waited),
`Server.onIdle` (the window became a by-name parameter, re-evaluated per loop
iteration).

### 1.1 The constants, argued from the tables rather than copied

clangd ships `DebouncePolicy{Min = 50 ms, Max = 500 ms, RebuildRatio = 1}`
[STAGE4-PRIOR-ART §5(f)].  Two of those three numbers are wrong for this server,
and the reason is structural, not a matter of taste.

**`Min` = 150 ms — bounded below by the interval between keystrokes.**  A window
shorter than the typing gap coalesces nothing.  THE ASSUMPTION, stated so it can
be argued with: sustained typing at 40-60 wpm is ~200-300 ms per character, a
fast typist at ~100 wpm is ~120 ms, and within-word digraphs reach 60-80 ms.
150 ms therefore coalesces any burst **faster than ~150 ms per character**, and
it deliberately does NOT coalesce slower steady typing: at 40-60 wpm, on a file
whose check is at or below the floor, **every character gets its own check**.
That is accepted, and the reason it is acceptable is that on such a file the
CHECK IS CHEAPER THAN THE WINDOW — a 20 ms check per 150 ms of quiet is at most a
~43 % duty cycle on the dispatch thread, a request that arrives waits at most one
20 ms check, and the squiggles are fresher for it.  What must not happen is a
check per character on an EXPENSIVE file, and the clamp is exactly what prevents
that: a file whose check exceeds 150 ms raises its own window to match it.
clangd's 50 ms is below every one of those typing figures, and Ermine cannot
afford it for a second reason clangd does not have:
**a check here runs to completion on the dispatch thread** (Decision 3; Stage 4
adds no thread), so every check that fires is a window in which a hover waits —
1.47 s measured at G3 on the largest file.  clangd's rebuild is cancellable and on
a worker, so it can afford to start one it will throw away.  (`Wire.ready` also
polls at 5 ms, so a window under ~25 ms would not be expressible accurately.)

**`Max` = 300 ms — the 300 ms of record, NOT clangd's 500.**  The ceiling is the
staleness a user tolerates in a squiggle, and 300 ms is the ceiling 5.3 chose for
exactly that reason.  The brief asks whether 500 is justified now that the check
is 0.55 s on the worst file.  It is not: raising the ceiling would make the
MEASURED round trip on `Layout/Report.e` worse (0.90 -> 1.10 s) to buy pile-up
protection this server already has for free.  **Checks cannot pile up here.**
Dispatch is single-threaded and `queued` holds ONE entry per uri behind a
versioned drop, so while a check runs the keystrokes behind it are not even
parsed, and what they leave when they are parsed is one pending check of the
newest version.  clangd's Max exists to bound a queue Ermine does not have.

**`Ratio` = 1 — "wait as long as the last check took".**  Since the versioned drop
already prevents pile-up, a ratio below 1 is tempting.  It is rejected because
with Min = 150 and Max = 300 the ratio is only live in the 150-300 ms band, and a
ratio below 1 would flatten that band to Min and make D a two-valued step
function.  Ratio 1 keeps the one property worth having there: **D >= C**, so at
most half of the dispatch thread goes to checks while someone types in a
mid-sized file, and a request that arrives waits at most one check.

**`Window` = 5, and the no-history case = Max.**  A median over five samples
outvotes two outliers (the realistic cluster is a cold open next to a GC pause)
and forgets one entirely in five checks.  No history means no cost model, so the
answer is the conservative end, the window this server waited before 7.4 — but
that case is **DEFENSIVE, not the ordinary first check**: didOpen and didSave
check SYNCHRONOUSLY and pay no window at all, so by the time a document's first
DEBOUNCED check is owed it already has the open's sample, and `policy(Nil)` is
reached only by a didChange on a document nothing has ever checked.  Measured:
`Reader.e`'s very first keystroke waited **150 ms off a single 125-151 ms sample**
(the reviewer's run: 144 ms), not 300.  Every check records a sample, a cold open
and a fast-mode check included, because the median is what decides and a bounded
median both outvotes and then forgets.

### 1.2 The function's output at the measured check times

| C (measured check) | provenance | D before 7.4 | **D after** |
|---|---|---|---|
| C (measured check) | provenance | D before 7.4 | **D after** | which term decides |
|---|---|---|---|---|
| **31 ms** | 7.0 §3, `Control/Monad/Reader.e`, 44 lines (`check.total` 30.7 ms) | 300 | **150** | Min |
| **22 ms** | THIS ITEM, the same file re-measured after 7.1b (median of 5, steady state) | 300 | **150** | Min |
| **52 ms** | THIS ITEM, `List.e`, 341 lines | 300 | **150** | Min |
| **~180 ms** | THIS ITEM, `Layout/Report/Keyed/Options.e`, 438 lines | 300 | **170-199** | Ratio x C |
| **~580 ms** | 7.1b §7 + THIS ITEM, `Layout/Report.e` warm (0.05 read + 0.50 typecheck + 0.03) | 300 | **300** | Max |
| **~1.1 s** | 7.1b, Report.e's worst site (0.17 read + 1.04 typecheck) | 300 | **300** | Max |
| **~2.3 s** | 7.1b §5, Report.e COLD (a first open) | 300 | **300** | Max |
| **3 s** | hypothetical | 300 | **300** | Max |
| none yet | a didChange on a document NOTHING has checked (defensive: didOpen/didSave check synchronously and pay no window, so the first DEBOUNCED check already has a sample) | 300 | **300** | the no-history default |

Read the table as the shape of the function: **it is flat at Max for every check
above 300 ms, flat at Min for every check below 150 ms, and equal to C in
between.**  Everything the stdlib actually contains is in the first four rows or
the fifth; the band is narrow on purpose, and the only file of the four measured
here that lives inside it is the 438-line one.  Two consequences worth stating:
the policy **can only shorten a wait, never lengthen one** (Max is the old
constant), and **the largest file is unchanged by construction**, which is what
makes "the large file must not get worse" true before any measurement.

## 2. NO OSCILLATION

### 2.1 The structural argument: the CLAMP bounds the feedback, and it saturates at the old constant

There is a feedback path, and it must be named rather than waved away: a longer D
coalesces more keystrokes into one check, which can make that check cost more, which
lengthens D.  **What bounds it is the CLAMP, not the median.**  Both ends of the loop
are clamped, and the upward saturation point is `Max` = 300 ms, which is EXACTLY the
window this server waited before 7.4 — so the worst the feedback can do is today's
behaviour.  Downward the fixed point is `Min` = 150 ms, which coalesces a burst on
§1.1's terms.

The median SMOOTHS; it does not bound, and it is worth being precise about that
because the obvious stronger claim is false.  One slow check CAN move a median of
five — from `[100, 100, 400, 400, 100]` (median 100) one further 400 gives
`[400, 100, 100, 400, 400]`, median 400 — so a document whose check cost alternates
with period two between, say, 100 ms and 400 ms will alternate its window between
150 and 300 ms indefinitely.  **That alternation is harmless, precisely because 150
and 300 are the clamp values**: every value the window can take is one this server
would have been happy to wait, the slow end being the old constant and the fast end
a window that still coalesces the bursts §1.1 cares about.  Outside the band the
function is FLAT, so jitter on a file whose check is well above or below 150-300 ms
cannot move D at all.

### 2.2 The measured sequences — D over the 15 rounds of `perf-client.py`

The after-side D, round by round, from the server's own `debounce:` lines (the
`median` it reports is C; pass 1 of each A/B shown, pass 2 agrees):

| file | D over rounds 1..15 (ms) |
|---|---|
| `Control/Monad/Reader.e` (44 lines) | 150 150 150 150 150 150 150 150 150 150 150 150 150 150 150 |
| `List.e` (341) | **300 260** 150 150 150 150 150 150 150 150 150 150 150 150 150 |
| `Layout/Report/Keyed/Options.e` (438) | **300 300** 199 187 181 176 176 181 187 187 196 196 172 172 170 |
| `Layout/Report.e` (1757) | 300 300 300 300 300 300 300 300 300 300 300 300 300 300 300 |

and the C behind them (the same lines' medians):

| file | C over rounds 1..15 (ms) |
|---|---|
| `Reader.e` | 125 77 30 26 22 21 19 17 17 17 16 16 16 15 14 |
| `List.e` | 429 260 92 82 72 66 58 55 55 52 52 52 52 52 52 |
| `Options.e` | 597 398 199 187 181 176 176 181 187 187 196 196 172 172 170 |
| `Report.e` | 2329 1550 772 728 684 682 642 626 619 585 585 585 585 586 586 |

**Monotone, then flat** on the two files that leave the band: the first one or two
rounds carry the cold open in the window and sit at Max, then D descends and stays
at Min for the rest of the run.  `Reader.e` is flat from the first keystroke,
because even its cold open (125-158 ms measured) is at or below Min, and
`Report.e` is flat at Max for all fifteen rounds of both after-side runs
(C descending 2329 -> 585 ms, never entering the band).  The one file inside
the band tracks C within **170-199 ms, a 29 ms range on a ~180 ms base (+-8 %)** —
which is the policy working, not instability: D follows the file's own check time,
and the same rounds' round-trip spread on the BEFORE side, where D was a constant,
was 0.455-0.498 s (9 %).  There is no alternation between two regimes anywhere in
the four sequences.

### 2.3 How the median forgets a cold check

A cold open is the big outlier (2.3 s on Report.e, 429 ms on List.e, 597 ms on
Options.e) and it is gone in a few keystrokes: with `Window` = 5 it stops BEING the
median at three warm samples and has left the window at five.  Measured above:
List.e is at Min by round 3, Options.e inside the band by round 3.  Pinned as a
property (`TestEditorBuffers`, "7.4 the median outvotes, then forgets, a cold
check"): for samples `[warm x n] ++ [cold]`, D is Max at n <= 1, Min from n = 2,
and `median` no longer returns anything but `warm` at n = 5.  The same mechanism
covers 7.2's scope-key drop and any GC pause: one expensive check is one sample.

## 3. THE BURST PIN — N keystrokes, exactly one check

Pinned twice, in two different senses of "real".

### 3.1 JVM-local, through the REAL dispatch loop (`TestEditorBuffers`, 3 new properties)

`loopFires(quietMs, n, gapMs, workMs, during)` builds a real `Wire` over a
`PipedInputStream`, a real `Server`, registers a real notification handler and a real
`onIdle`, runs `Server.run()` on a thread and writes `n` framed messages `gapMs`
apart.  The only fake thing is the unit of work: a counter and a sleep instead of a
check, because a check needs a booted session and this property needs to run in the
suite.  Results:

| property | case | fires |
|---|---|---|
| a burst is ONE check, at D_small | `quiet = 150`, 8 messages 20 ms apart | **1** |
| a burst is ONE check, at D_large | `quiet = 300`, 8 messages 20 ms apart | **1** |
| a keystroke DURING a check is exactly one more | `quiet = 150`, 4 messages, then 3 more written from inside a 200 ms "check" | **2** |

The third is the versioned-drop shape: while the work runs, the dispatch thread is
not reading, so the three keystrokes sit in the stream; when it returns they are
handled in order, leave ONE queue entry, and one further check follows.  (The
margins are wide on purpose -- a 20 ms gap would have to stretch 7x to split the
first two bursts -- but these three are wall-clock properties and that is stated
rather than hidden.)

### 3.2 Through the scripted client, against the real server (`lsp-smoke.sh`)

`tracker/lsp-tests/Burst.e` (new fixture, 8 lines) and `Layout/Report.e` (the
largest module, opened from the repo the way the existing FFI and rename fixtures
open stdlib files):

| fixture | what is sent | asserted |
|---|---|---|
| `Burst.e` | didOpen, then 8 didChange 20 ms apart, then 8 more | **3** `check: Burst` lines in the log (one open + one per burst), publishes exactly `didOpen, didChange, didChange`, **2** `debounce:` lines |
| `Burst.e` | the second burst's window | waited **150** ms with a median below 150 -- the FLOOR, measured end to end |
| `Layout/Report.e` | didOpen, then 6 didChange 20 ms apart | **2** `check: Layout.Report` lines, **1** `debounce:` line, waited **300** ms with a median above 300 -- the CEILING |
| every debounced check in the whole run | -- | `waited <= policy`, `policy == clamp(150, median, 300)` and `1 <= samples <= 5` on every line (**41 lines** in the run of record).  `<=` and not `==` because the loop has ONE quiet window and the queue can hold more than one document: `quiet()` waits the MINIMUM of the queued documents' windows and then runs their checks back to back, so a document whose own policy is 300 ms may legitimately be checked after a 150 ms wait because a cheaper sibling was owed one too (review finding F-5 -- the `==` form would have failed on a CORRECT server the first time a fixture queued two documents) |
| the phases run (`-Dermine.lsp.phases`) | `initializationOptions: {debounce: 250}` | `debounce PINNED at 250ms` in the log, and the one debounced check waited **250** ms while the policy asked for something else |

What it actually logged in the run of record (`<scratch>/7.4/lsp-smoke.log`):

    check: Burst read 0.01s, typecheck 0.00s (reused 0 of 1 components), surface 0 of 3 statements
    diagnostics: didOpen Burst.e -> 0 diagnostic(s) in 0.0s
    debounce: Burst.e waited 150ms (median 8ms of 1 checks, policy 150ms)
    check: Burst read 0.00s, typecheck 0.00s (reused 0 of 1 components), surface 2 of 3 statements
    diagnostics: didChange Burst.e -> 0 diagnostic(s) in 0.0s          <- 8 keystrokes, ONE check
    debounce: Burst.e waited 150ms (median 7ms of 2 checks, policy 150ms)
    check: Burst read 0.00s, typecheck 0.00s (reused 0 of 1 components), surface 2 of 3 statements
    diagnostics: didChange Burst.e -> 0 diagnostic(s) in 0.0s          <- 8 more, ONE more check

    check: Layout.Report read 0.95s, typecheck 1.05s (reused 0 of 154 components), surface 0 of 529 statements
    debounce: Report.e waited 300ms (median 2039ms of 1 checks, policy 300ms)   <- the CEILING
    check: Layout.Report read 0.05s, typecheck 0.59s (reused 97 of 154 components), surface 528 of 529 statements


## 4. THE A/B — the adoption gate

**THE PROTOCOL.**  `perf-client.py --rounds 15 --mode space`, interleaved
before/after/before/after, one JVM at a time, every side started under load < 1.3
(the loads are in §4.2), the two sides being two saved class trees
(`<scratch>/7.4/classes-{before,after}-{core,parsers}`, core AND parsers swapped in
the classpath; before = `85eb150`), round 1 discarded as JIT warm-up, steady state
rounds 2..15.  **NO pin on either side** -- the point is to see the policy; the
debounce column is HARVESTED from the server's own line on the after side and is the
0.300 constant on the before side, which logs none (§5).  The read and typecheck
columns are the server's own figures from its `check:` line, so they are controls,
not attributions.

### 4.1 The four files

**`Control/Monad/Reader.e`**, 44 lines

| pass | side | round trip | read | typecheck | debounce | residual | spread | cold open | reused |
|---|---|---|---|---|---|---|---|---|---|
| 1 | BEFORE | 0.320 s | 0.010 | 0.010 | **0.300** | 0.000 | 0.317-0.326 | 0.135 | 0/1 |
| 1 | AFTER | 0.171 s | 0.010 | 0.010 | **0.150** | 0.001 | 0.168-0.177 | 0.131 | 0/1 |
| 2 | BEFORE | 0.321 s | 0.010 | 0.010 | **0.300** | 0.001 | 0.316-0.326 | 0.150 | 0/1 |
| 2 | AFTER | 0.173 s | 0.010 | 0.010 | **0.150** | 0.003 | 0.169-0.180 | 0.158 | 0/1 |
| pooled | BEFORE | **0.3204 s** | 0.010 | 0.010 | **0.300** | 0.000 | | 0.143 | |
| pooled | AFTER | **0.1719 s** | 0.010 | 0.010 | **0.150** | 0.002 | | 0.145 | |
| **delta** | | **-0.149 s (-46.4 %)** | | +0.000 | **-0.150** | | | | |

**`List.e`**, 341 lines

| pass | side | round trip | read | typecheck | debounce | residual | spread | cold open | reused |
|---|---|---|---|---|---|---|---|---|---|
| 1 | BEFORE | 0.360 s | 0.010 | 0.040 | **0.300** | 0.011 | 0.351-0.380 | 0.409 | 7/13 |
| 1 | AFTER | 0.208 s | 0.010 | 0.040 | **0.150** | 0.014 | 0.206-0.339 | 0.437 | 7/13 |
| 2 | BEFORE | 0.356 s | 0.010 | 0.030 | **0.300** | 0.014 | 0.351-0.383 | 0.407 | 7/13 |
| 2 | AFTER | 0.217 s | 0.010 | 0.040 | **0.150** | 0.014 | 0.199-0.379 | 0.429 | 7/13 |
| pooled | BEFORE | **0.3583 s** | 0.010 | 0.035 | **0.300** | 0.012 | | 0.408 | |
| pooled | AFTER | **0.2124 s** | 0.010 | 0.040 | **0.150** | 0.014 | | 0.433 | |
| **delta** | | **-0.146 s (-40.7 %)** | | +0.005 | **-0.150** | | | | |

**`Layout/Report/Keyed/Options.e`**, 438 lines

| pass | side | round trip | read | typecheck | debounce | residual | spread | cold open | reused |
|---|---|---|---|---|---|---|---|---|---|
| 1 | BEFORE | 0.472 s | 0.020 | 0.070 | **0.300** | 0.079 | 0.455-0.526 | 0.594 | 0/0 |
| 1 | AFTER | 0.369 s | 0.020 | 0.080 | **0.184** | 0.083 | 0.337-0.477 | 0.609 | 0/0 |
| 2 | BEFORE | 0.469 s | 0.020 | 0.080 | **0.300** | 0.072 | 0.453-0.498 | 0.668 | 0/0 |
| 2 | AFTER | 0.350 s | 0.020 | 0.080 | **0.171** | 0.075 | 0.331-0.475 | 0.620 | 0/0 |
| pooled | BEFORE | **0.4703 s** | 0.020 | 0.075 | **0.300** | 0.075 | | 0.631 | |
| pooled | AFTER | **0.3596 s** | 0.020 | 0.080 | **0.177** | 0.079 | | 0.615 | |
| **delta** | | **-0.111 s (-23.5 %)** | | +0.005 | **-0.122** | | | | |

**`Layout/Report.e`**, 1757 lines

| pass | side | round trip | read | typecheck | debounce | residual | spread | cold open | reused |
|---|---|---|---|---|---|---|---|---|---|
| 1 | BEFORE | 0.903 s | 0.050 | 0.525 | **0.300** | 0.026 | 0.853-0.993 | 2.296 | 97/154 |
| 1 | AFTER | 0.893 s | 0.050 | 0.510 | **0.300** | 0.028 | 0.856-0.989 | 2.345 | 97/154 |
| 2 | BEFORE | 0.888 s | 0.050 | 0.515 | **0.300** | 0.027 | 0.869-0.955 | 2.268 | 97/154 |
| 2 | AFTER | 0.919 s | 0.050 | 0.535 | **0.300** | 0.030 | 0.867-1.007 | 2.307 | 97/154 |
| pooled | BEFORE | **0.8955 s** | 0.050 | 0.520 | **0.300** | 0.027 | | 2.282 | |
| pooled | AFTER | **0.9063 s** | 0.050 | 0.522 | **0.300** | 0.029 | | 2.326 | |
| **delta** | | **+0.011 s (+1.2 %)** | | +0.002 | **+0.000** | | | | |

**THE ACCEPTANCE IS THE SMALL FILE, and it is met**: `Control/Monad/Reader.e`
**0.3204 -> 0.1719 s, -149 ms (-46.4 %)**, with no overlap of the per-round spreads
(before 0.316-0.326, after 0.168-0.180) and the read and typecheck segments unmoved
at 0.010 / 0.010 s as controls.  The whole of the delta is the debounce
(-150 ms measured, -0.149 s in the round trip), which is what the item set out to
do: the wait was **94 % of that file's round trip** (0.300 of 0.3204 s; 7.0 measured
90 % of 0.333 s before 7.1b shortened the check), and it is now 87 % of 0.1719 s --
the 20 ms check has gone from a sixteenth of the round trip to an eighth.

**THE LARGE FILE DID NOT GET WORSE**, and it could not have: the after side waited
**300 ms on every one of its 30 steady-state rounds** (harvested, C settling at
585-605 ms, i.e. Max), the read is 0.050 s on both sides and the typecheck moved
+2 ms.  The round trip reads **0.8955 -> 0.9063 s, +11 ms (+1.2 %)**, which is
inside the per-round spreads (before 0.853-0.993, after 0.856-1.007), below the
~50 ms editor noise floor the roadmap asks every adoption item to name, and has no
mechanism: every term of the policy is identical on both sides for this file.  The
cold open (2.282 -> 2.326 s) is in the same category.

**THE TWO MIDDLE FILES** show both regimes.  `List.e` (341 lines, 7 of 13 groups
reused -- the bench's own proof the edit was real) settles at Min: **0.3583 ->
0.2124 s, -146 ms (-40.7 %)**.  `Layout/Report/Keyed/Options.e` (438 lines) is the
only one of the four whose check lands INSIDE the band, so its window tracks its
check time rather than a clamp: the harvested debounce is **0.177 s pooled** (not
0.150, not 0.300) and the round trip is **0.4703 -> 0.3596 s, -111 ms (-23.5 %)**.
That file is reported with `--allow-no-reuse` because it has **0 binding groups**
(`reused 0 of 0` on every round, before and after) -- its definitions are all
signature-led forms `TolerantCheck.groups` does not hold -- so the bench's
"the edit invalidated something" assertion is inapplicable, exactly as it is for the
44-line file's single group (7.0 §3 recorded the same thing).  `List.e` is the
medium file of record for that reason; Options.e is the evidence that the ratio term
is live and not decoration.

### 4.2 Run order and load

| leg | load at start |
|---|---|
| Reader.e before/after/before/after | 1.01 / 1.26 / 1.25 / 1.20 |
| List.e before/after/before/after | 0.98 / 1.23 / 1.29 / 1.17 |
| Options.e before/after/before/after | 1.12 / 1.19 / 1.27 / 1.17 |
| Report.e before/after/before/after | 1.12 / 1.27 / 1.27 / 1.23 |

Machine note, recorded because it is the honest condition of the measurement: the
user's desktop (firefox and friends) kept the 1-minute average oscillating between
~1.0 and ~2.5 throughout, so every leg waited for the dip below 1.3; the figure that
matters here is a wall-clock SLEEP rather than compute, and the interleaving puts
any drift on both sides.

## 5. THE BENCH-COMPARABILITY DECISION — BOTH, and which does what

The brief asks for one of two answers and gets both, because they answer different
questions:

1. **`tracker/tools/perf-bench.sh editor` PINS D = 300 ms**, via the new
   `initializationOptions.debounce` (perf-client's `--pin-debounce 300`).  It is the
   MEASUREMENT OF RECORD, and a measurement of record cannot have one of its own
   terms move underneath it: every editor figure the roadmap carries -- **1.616 s**
   at PERF-ROADMAP P1, **1.69 s** at G3, **0.896 s** after 7.1b -- includes a 300 ms
   debounce.  With the pin, the bench's before/after numbers stay directly
   comparable with all of them, and what it measures remains the READ and the
   TYPECHECK, which is what the roadmap ranks items on.
2. **perf-client.py now HARVESTS the window from the server**, per round, from the
   `debounce:` line, instead of subtracting its own 0.300 constant.  Without this the
   residual column would silently absorb the difference (on the small file the
   subtraction would have gone NEGATIVE: a 0.17 s round trip minus a 0.300 s
   assumption).  A pre-7.4 server logs no such line and the 0.300 constant remains
   the fallback, with a printed note saying which source was used -- which is what
   makes ONE script able to measure both sides of this item's A/B.

So: the bench pins, the client reports, and **7.4's own A/B runs perf-client
directly with NO pin on either side** -- that is the only way to see the policy at
all, and it is how the table in §4 was produced.  A reviewer re-running the bench
gets numbers comparable with G3's; a reviewer re-running §4 gets the policy.

## 6. WHAT CHANGED, AND WHAT DID NOT

| file | change |
|---|---|
| `core/.../lsp/Diagnostics.scala` | the `Debounce` object (the function, the four constants, the median, the pin) with the argument in its scaladoc; `install` computes the window per loop iteration and logs one `debounce:` line per debounced check; `run` records the measured cost into the document.  `DebounceMillis = 300` is gone |
| `core/.../lsp/Documents.scala` | `Doc.checkMillis` (<= 5 samples, most recent first), CARRIED ACROSS AN EDIT in `put` next to the index and the two caches; `recordCheck` and `checksFor` |
| `core/.../lsp/Rpc.scala` | `Server.onIdle`'s `quietMillis` became BY NAME and is re-evaluated once per wait (it was read once at install).  Three lines plus the comment that says why |
| `core/.../lsp/Main.scala` | `initializationOptions.debounce` pins a fixed window, 1..10000 ms, refused outside that range rather than clamped silently |
| `scalacheck-binding/.../TestEditorBuffers.scala` | 6 new properties: 3 on the policy function, 3 driving the real `Server`/`Wire` loop (the burst pin) |
| `tracker/tools/lsp-client.py` | the 7.4 fixtures: two bursts on `Burst.e`, one on `Layout/Report.e`, the floor and the ceiling, the per-line policy audit, the pin |
| `tracker/lsp-tests/Burst.e` | NEW, 8 lines |
| `tracker/tools/perf-client.py` | `--pin-debounce`, the per-round debounce harvest, `--allow-no-reuse` (for a module with one binding group or none -- 7.0 found `Reader.e` has one) |
| `tracker/tools/perf-bench.sh` | passes `--pin-debounce 300` (see §5) |
| `docs/lsp.md` | the rule as a function with its constants and reason, the three files' round trips, the `debounce:` log line, the pin; the Latency table's "0.30 debounce" row is now three rows |

NOT touched: `Resident.scala` (the per-check cost is already measured in
`Diagnostics.run`, which is the number the CLIENT waits for -- read + typecheck +
index + the publish's preparation -- so no new timer was needed anywhere),
`TolerantCheck`, `NewPipeline`, `SurfaceCache`, the strict reader, the batch path,
the request handlers.  No request triggers work; the batch is frozen; no new thread.

## 7. GATES

| layer | result |
|---|---|
| `sbt core/compile core/copyResources` | **green** (12 sources recompiled; `copyResources` clean) |
| `core/testOnly *TestLoopTrace` | **720 segments, 720 agree**, 0 hashdiff / 0 eqdiff / 0 skipped; 3 of 3 properties |
| targeted: `*TestEditorBuffers *TestTolerantCheck *TestSurfaceCache` | **64 of 64** (was 58; `TestEditorBuffers` 6 -> 12) |
| `corpus-run.sh --batch` | 154 outputs, **85 LOADED / 69 REJECTED / 0 UNKNOWN** (`corpus-verdicts.py`) -- the baseline exactly |
| `repl-smoke.sh` | **8 groups / 66 checks, all PASS**, goldens unmodified (2 + 5 + 9 + 12 + 6 + 4 + 23 + 5) |
| `lsp-smoke.sh` | **PASS, 510 checks** (494 after 7.1b, so **+16**: the two bursts and their window, the largest module's burst and its ceiling, the per-line policy audit, the pin, and the fixture hygiene checks) |
| boot | **129 modules in 12.2 s**, both smoke servers; 12.2-12.6 s across the 16 A/B runs |
| `.ei` droppings (`find`) | **0** new: `tracker/lsp-tests` 0, the module tree 0, `git status` 0; the 143 tracked baseline files untouched |
| `git diff --stat` == `git diff --stat -w --histogram` | **identical** (checked after every edit; one whitespace-only reflow in `perf-client.py` was restructured away rather than left in) |
| line endings | every changed file keeps the type `git show HEAD:<f> \| file -` reports; **0 CR** anywhere in the diff; the CRLF stdlib files are untouched (`Burst.e`, the one new file, is LF like every other fixture) |
| Tier 1 | NOT NEEDED -- nothing in `scalaparsers`, `Subst.scala` or `Type.scala` changed |
| Tier 2 | THE REVIEWER'S (brief 7.4.6); this item changes shipped behaviour, so it is owed.  The count it should come back with is **1026** (1020 after 7.1b + the 6 new `TestEditorBuffers` properties); the two known intermittents (E12 `TestInterfaceRoundTrip`, E13 `TestLegend`) get their one re-run per the standing rule |

Baselines a commit of this item must update (NOT touched here -- the brief forbids
editing `tracker/LSP-ROADMAP.md`): `lsp-smoke.sh` **494 -> 510**, `core/test`
**1020 -> 1026**.

### 7.1 Two things a reviewer should know before re-running

1. **A lingering shell from an earlier agent breaks `perf-bench.sh`'s preflight.**  A
   15-hour-old polling shell whose command line contains the literal string
   `'sbt-launch|bin/ermine|ermine-lsp'` is resident on this machine, and
   `pgrep -f 'sbt-launch|xsbt\.boot'` matches it, so `perf-bench.sh` refuses with
   "an sbt build is running".  It is not mine and not a JVM; this item's A/B calls
   `perf-client.py` directly (as 7.1b's did), so nothing was measured through the
   blocked path.  The same class of false positive is already documented in
   perf-bench's own header for the ermine-JVM guard.
2. **The load gate cost more wall time than the runs.**  Every leg waited for the
   1-minute average to dip below 1.3; the desktop kept pushing it to ~2.5.

## 8. VERDICT — **GREEN**

**THE ACCEPTANCE IS MET AND IT IS THE SMALL FILE**: `Control/Monad/Reader.e`'s round
trip is **0.3204 -> 0.1719 s (-149 ms, -46.4 %)**, interleaved, with non-overlapping
spreads and the read and typecheck segments unmoved as controls.  A 44-line file no
longer waits 300 ms for a 20 ms check; it waits 150, which is the floor the typing
interval sets.

**THE LARGE FILE DID NOT GET WORSE, BY CONSTRUCTION AND IN MEASUREMENT**: the policy
asked for 300 ms -- the pre-7.4 constant -- on every one of the 30 steady-state
rounds of both after-side runs on `Layout/Report.e`, and the round trip reads
0.8955 -> 0.9063 s, inside the per-round spreads and below the ~50 ms noise floor.
`Max` = 300 is what makes that a theorem rather than a hope: **the function can only
shorten a wait.**

**THE POLICY IS STATED, ARGUED AND AUDITABLE.**  `D = clamp(150, median of the last 5
measured check times of that document, 300)`, with every constant argued from 7.0's
and 7.1b's tables and from a structural difference from clangd (checks here are
uninterruptible on the dispatch thread, and the versioned drop makes pile-up
impossible), not copied from `{50, 500, 1}`.  Its output at the measured check times
is tabulated in §1.2; the server logs the decision on every debounced check; and
lsp-smoke asserts `waited == policy == clamp(150, median, 300)` on every one of those
lines, 41 of them in one run.

**NO OSCILLATION THAT MATTERS**: the feedback path exists, is named, and is bounded
by the CLAMP -- not by the median, which smooths without bounding (a period-2 check
cost does alternate the window, between 150 and 300, and both of those are values
this server was already happy to wait).  The measured D sequences over 15 rounds are
flat at Min (44-line), monotone then flat at Min (341-line), flat at Max (1757-line),
and inside the band track C within +-8 % (438-line).  A cold check is outvoted in two
keystrokes and gone in five, measured and pinned as a property.

**THE BURST IS PINNED TWICE**: 8 keystrokes 20 ms apart produce exactly one check and
one publish, at the floor and at the ceiling, through the real dispatch loop in the
suite and through the scripted client against the real server; a keystroke arriving
during a check produces exactly one more.

**NOTHING WAS WEAKENED.**  `--allow-no-reuse` is a new flag on a bench, used for two
files whose binding-group count makes the assertion inapplicable, and its default
stays strict; the one assertion that WAS relaxed in the closing round (`waited ==
policy` -> `waited <= policy`, F-5) was relaxed because the strict form was WRONG --
it would have failed on a correct server the first time two documents were queued
together -- and the clamp arithmetic it guards is unchanged.  Otherwise: the batch path, the strict reader and the request
handlers are untouched; no new thread; Tier 2 is owed and is the reviewer's.

## 9. RE-RUN RECIPE (for the reviewer)

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    S=<scratch>/7.4
    # the two class trees: `before` is a build of 85eb150, `after` is this tree
    cp -a core/target/scala-3.3.8/classes $S/classes-after-core    # and parsers
    # the A/B, one file at a time, interleaved, one JVM at a time, load < 1.3:
    FILE=core/src/main/resources/modules/Control/Monad/Reader.e LINE=43 \
      ANCHOR="ReaderT (" TAG=small EXTRA=--allow-no-reuse $S/ab.sh     # the ACCEPTANCE
    FILE=core/src/main/resources/modules/List.e LINE=152 ANCHOR="(tails xs)" TAG=med $S/ab.sh
    FILE=core/src/main/resources/modules/Layout/Report/Keyed/Options.e LINE=109 \
      ANCHOR="(Just l)" TAG=opt EXTRA=--allow-no-reuse $S/ab.sh        # the live-ratio case
    FILE=core/src/main/resources/modules/Layout/Report.e LINE=281 ANCHOR="cellsA 0 " TAG=big $S/ab.sh
    python3 $S/table.py                    # the tables in §4
    # the D and C sequences of §2.2:
    grep -o "waited [0-9]*ms (median [0-9]*ms of [0-9]*" $S/<tag>-after-1.log
    sbt -batch core/compile core/copyResources 'core/testOnly *TestLoopTrace' \
      'core/testOnly *TestEditorBuffers *TestTolerantCheck *TestSurfaceCache'
    tracker/tools/corpus-run.sh --batch $S/corpus ; tracker/tools/repl-smoke.sh
    tracker/tools/lsp-smoke.sh
    sbt -batch core/test                   # Tier 2, ALONE on the tree

`<scratch>/7.4/` holds `ab.sh`, `rest.sh`, `table.py`, the four class trees with
their classpath files, and the 16 A/B logs + JSON + transcripts (`<tag>-<side>-<pass>.{log,json,txt}`).

STOP after this report.
