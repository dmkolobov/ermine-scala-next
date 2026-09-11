# LSP Stage 4, item 7.4 — adaptive debounce: INDEPENDENT REVIEW (adoption, Tier 0 + Tier 2)

Reviewer's report.  Branch `scala3-migration`, HEAD `1137ffb` (the brief's `85eb150`
plus two brief commits) with the 7.4 deliverables UNCOMMITTED in the tree.  Nothing
was committed; the only files this review wrote are its scratch directory and this
report.  Implementer's report: `tracker/loopmodel/LSP4-7.4-DEBOUNCE.md`.

**VERDICT: ADVANCE.**  The acceptance reproduces on my own interleaved A/B
(`Control/Monad/Reader.e` **0.320 → 0.173 s, −147 ms, −45.9 %**, controls unmoved,
non-overlapping spreads), the large file is unchanged (`Layout/Report.e` **0.941 → 0.956 s, +15 ms, inside a
fully-overlapping spread**), every gate is at or above its baseline including `core/test` **1026 / 1026 green on the first run**,
and the burst pin has teeth (planted `Min = 10` splits the 8-keystroke burst into 4
checks; restored and hash-checked).  **Six findings, three LOW and three INFO, none of
them a defect in shipped behaviour**: three are places where the WRITTEN ARGUMENT claims
more than the function delivers (F-1 the Min justification, F-2 the no-oscillation
argument — I have a counterexample and a permanent 150/300 alternation, F-3 a vacuous
"first check unchanged"), one is a latent brittleness in a smoke assertion (F-5), one is
an observation about the cross-document `min` (F-5), one is where the option is
documented (F-4), and one is a bench flag that waives more than it should (F-6).  No
constant needs to change and no code path is wrong; the corrections make the case for the
item stronger.  None blocks adoption.

## 1. THE POLICY, READ OFF THE CODE

`Diagnostics.Debounce` is `D(C) = clamp(150, 1.0 × C, 300)` with `C = median` of
`samples.take(5)` (even-length median is the integer mean of the two middles),
`None → Max`.  I checked the four structural claims the brief names:

| claim | verdict | where |
|---|---|---|
| the median is PER-URI: a slow file cannot inflate a fast one's wait | **CONFIRMED** | the samples live on `Documents.Doc.checkMillis`, keyed by uri; `Diagnostics.run` records via `docs.recordCheck(uri, …)` and `install` reads `docs.checksFor(u)`.  There is no cross-document term in the median.  The CONVERSE is not true and is by design — see F-5 |
| the window survives an edit | **CONFIRMED** | `Documents.put` carries `prev.map(_.checkMillis) getOrElse Nil` into the new `Doc`, in the same breath as the index, the inference cache and the surface cache.  Positionally correct against the `Doc` constructor (`surface`, then `checkMillis`, then `diags`) |
| it is dropped on didClose | **CONFIRMED** | `didClose → docs drop uri` removes the whole `Doc`.  A re-open is a cold read with no cost model.  (Note: a didOpen on an ALREADY-open uri goes through `put`, so it KEEPS the history — but didOpen checks immediately and pays no debounce, so nothing observes it) |
| a new document's first check is unchanged | **CONFIRMED, but vacuously** | the first check of a document is always the `didOpen` one, which `install` runs SYNCHRONOUSLY and which pays no window at all.  The no-history `Max` branch is therefore unreachable for a `.e` file in practice: by the time a `didChange` is queued, the open's own cost is already one sample.  See F-3 |

### 1(a) Min = 150 — what "quiet for D" actually means, and the 120 ms typist

`Server.run` is `if (idlePending() && !wire.ready(idleQuiet())) idleWork() else wire.receive()`,
and `Wire.ready(ms)` is *"poll `in.available()` every 5 ms until a byte is there or
`ms` has passed"*.  So **the timer is RESET by every byte, and runs from the moment
the previous message finished being dispatched — not from the first keystroke of the
burst.**  "Quiet for D" means *no byte on stdin for D consecutive milliseconds*.
The consequence the brief asks about is therefore clean:

* **a 120 ms/char typist at D = 150 DOES still coalesce**, indefinitely — every
  keystroke lands inside the 150 ms window and restarts it, so the whole burst is one
  check that fires 150 ms after the last character.  I confirmed this end to end: the
  `TestEditorBuffers` loop property drives the real `Server`/`Wire` with 8 messages
  20 ms apart and fires once at `quiet = 150` AND at `quiet = 300`, and through the
  scripted client 16 keystrokes in two bursts produce exactly 3 `check: Burst` lines
  (open + one per burst) — reproduced, §3.
* **but the argument written in the scaladoc over-claims.**  It names "sustained prose
  at 40–60 wpm is ~200–300 ms per character" and then concludes "150 ms therefore
  coalesces within-word bursts at any speed and a steady fast typist's stream as
  well".  The first half of that is right (digraphs 60–80 ms, 100 wpm ≈ 120 ms); the
  phrase "at any speed" is not: at 200–300 ms per character — the interval the SAME
  sentence calls sustained typing — a 150 ms window does NOT coalesce, and every
  character gets its own check.  That is finding **F-1**.  It is an argument defect,
  not a behaviour defect: it only bites files whose check is ≤ 150 ms (that is exactly
  when D = Min), so the worst case is a 150 ms check every 200 ms — a 43 % duty cycle
  and a ≤ 150 ms wait for a hover — in exchange for squiggles that are 150 ms fresher
  per character.  The honest statement is "Min = 150 coalesces every burst FASTER than
  150 ms/char, and for slower typing buys freshness at a bounded duty cycle", not
  "coalesces at any speed".

### 1(b) Max = 300 — checks cannot pile up; the duty cycle CAN rise, with two documents

`install` holds `queued: LinkedHashMap[uri, version]` — **one entry per uri**
(`queued += uri -> v` replaces), and on firing it takes the whole map, clears it, and
drops any entry whose version the document no longer has.  **CONFIRMED: checks cannot
pile up**, and Max does not have to be raised to stop them.  The brief's real question
is the request-wait hazard, and the numbers are:

| situation | check | D | dispatch-thread duty cycle | pre-7.4 |
|---|---|---|---|---|
| `Layout/Report.e`, one document | 0.58 s | 0.300 (Max) | **66 %** | 66 % — IDENTICAL, D is the old constant |
| `Control/Monad/Reader.e`, one document | 0.031 s | 0.150 (Min) | **17 %** | 9.4 % |
| `Options.e`, one document, inside the band | 0.18 s | 0.18 (= C) | **50 %** — this is the `Ratio = 1 ⇒ D ≥ C` property, and it is exactly the "at most half" the docs claim | 37 % |
| **two documents queued together**, Reader.e + Report.e | 0.61 s back to back | 0.150 (the MIN over the two) | **80 %** | 67 % |

The last row is real and is the sharpest form of the hazard.  `install`'s `quiet()`
takes the **minimum** over every queued uri, and `idleWork` then runs ALL due checks
back to back inside one invocation, with no quiet gap between them — so two documents
edited between two fires do make the dispatch thread run consecutive checks, and after
7.4 the gap in front of that block can be 150 ms instead of 300 ms.  That is finding
**F-5**.  It is bounded and one-shot (after the fire `queued` is empty, and you only
type in one buffer, so the next round is single-document again), the total work is
unchanged, and the reachable trigger is a multi-file `WorkspaceEdit` echoed back as
two `didChange`s.  It is not a reason to hold the item, but "in practice one document
is queued" in the code comment is the whole justification for `min` and it deserves
the sentence above it rather than a parenthesis.

`Max = 300` rather than 500: CONFIRMED as the right call, and for a second reason the
report does not give — since `Max` IS the pre-7.4 constant, "the policy can only
shorten a wait" is a theorem about the function (I property-checked it: the shipped
`TestEditorBuffers` property asserts `d ≤ 300` over 100 random 5-sample windows), and
raising Max to 500 would forfeit exactly that theorem and make the largest file 200 ms
worse with no measured benefit.

### 1(c) Ratio = 1 — the §1.2 output table

Recomputed from the function, independently (`<scratch>/oscillation.txt` holds the
replica, which I cross-validated against 61 real `debounce:` lines — §3):
C = 31 → 150; 22 → 150; 52 → 150; 180 → 180 (the measured run gives 170–199 as C
moves); 580 → 300; 1100 → 300; 2300 → 300; 3000 → 300; no history → 300.  **The
table in §1.2 of the implementer's report is correct row for row.**  The band is live
only in 150..300, as claimed, and my lsp-smoke run of record exhibits it in the wild:
`Complete.e` waited 186, 177, 186, 177, 169, 155, 150, 150, 150 ms on nine
consecutive debounced checks — D tracking its own C one-for-one.

### 1(d) a request sent during the debounce window

**CONFIRMED, and nothing in this item touched request handling.**  The whole diff to
`Rpc.scala` is three lines: `idleQuietMs: Int` became `idleQuiet: () => Int` and
`onIdle`'s first parameter became by-name.  During the wait the loop is inside
`Wire.ready`, which returns as soon as a byte is available; the request is then read
and answered on the next iteration, so a hover in the window is answered with the same
≤ 5 ms polling granularity as before.  Shortening D does not lengthen any request: it
moves the *start* of the check earlier by (300 − D) ms, and the worst-case wait a
request can suffer is the length of the check, which this item does not change.  On the
file where that number is big (`Report.e`, the 1.47 s G3 measurement) D is unchanged at
300.

## 2. OSCILLATION — reproduced, and ONE claim refuted

### 2.1 The measured D series (my runs, `--rounds 15 --mode space`, no pin)

| file | D over rounds 1..15 (ms) | C behind it |
|---|---|---|
| `Control/Monad/Reader.e` (44) | 150 ×15 | 144 85 27 25 26 23 19 19 18 17 17 18 18 16 15 |
| `Layout/Report.e` (1757) | 300 ×15 | 2651 1696 742 751 742 728 707 707 652 652 652 652 652 654 638 |
| `Complete.e` (lsp-smoke, in-band) | 186 177 186 177 169 155 150 150 150 | — |

Flat at Min, flat at Max, and tracking C inside the band: the same shape the
implementer reports, on my own runs.  `Report.e`'s C never once enters the band
(638–2651 ms), so the ceiling is not a coincidence of one run.

### 2.2 The cold-open forgetting, including the TWO-outlier case the brief asks for

With the real medians (`<scratch>/oscillation.txt`):

* ONE cold sample (2329 ms) among warm 52 ms checks: D = **Max at 0 and 1 warm
  samples, Min from the 2nd**, and the cold sample is out of the window entirely at
  the 5th.  Matches the shipped property and the measured `List.e` sequence.
* TWO expensive samples (a 2329 ms cold open AND a 900 ms 7.2 scope-key drop on an
  import edit): D = **Max for THREE rounds (0, 1 and 2 warm samples), Min from the
  3rd**, both outliers out of the window at the 6th.  So a median of five with two
  outliers costs exactly one extra round at Max and is still robust — the answer to
  the brief's question is "one more round, then the same floor".  A THIRD outlier
  inside one window would hold Max until three warm samples outvote it, which is the
  window size minus two; the design degrades gracefully rather than cliff-edging.

### 2.3 Can D alternate 150/300 on consecutive rounds?  **YES — and the report's
structural argument for "no" is wrong as written**

Implementer's §2.1 says "*a median of five changes by at most one order statistic per
step: the window cannot jump between regimes on one slow check*".  The first clause is
true; the conclusion does not follow, and I have a counterexample:

    window (most recent first)  [100, 100, 400, 400, 100]  median 100  D = 150
    one 400 ms check arrives -> [400, 100, 100, 400, 400]  median 400  D = 300

One slow check moved D from the floor to the ceiling in a single step, because the
sample it EVICTED was a fast one.  And the alternation the brief asks about follows
immediately: feed the document a check cost that alternates 100 / 400 ms and D
settles into

    300 150 250 150 250 150 | 300 150 300 150 300 150 300 150 …

i.e. **D alternates Min/Max on consecutive rounds, forever** (a window of five over a
period-2 sequence is itself period-2: five consecutive samples are 3-and-2 one way,
then 3-and-2 the other).  140/320 ms gives the same.  This is finding **F-2**.

How much does it matter?  Behaviourally, very little: the alternation is bounded by
`[Min, Max]`, both ends are windows this server is willing to wait, and the driver is
the CHECK COST alternating — which needs a user alternating keystrokes between two
statements of very different cost (one that invalidates a big binding group and one
that does not).  I could not produce it on a real file within the budget of this
review, and none of the four measured files comes near it — `Complete.e`'s ±9 ms
wobble is D correctly tracking C, not a regime flip.  But the argument in §2.1 and in
the scaladoc ("NO OSCILLATION: … one slow check cannot move D unless it is the middle
of five") should be corrected to the true statement, which is the one that actually
does the work: **D is clamped into [150, 300] and D ≤ the pre-7.4 constant, so the
worst case of the feedback loop is today's behaviour** — not "it cannot alternate".

## 3. THE BURST PIN — reproduced, and PLANTED

### 3.1 Reproduced, both senses

| pin | my result |
|---|---|
| `TestEditorBuffers` "a burst 20 ms apart is ONE check, at D_small" (`quiet = 150`, 8 messages) | **fires = 1**, passes |
| the same at `D_large` (`quiet = 300`) | **fires = 1**, passes |
| "a keystroke arriving DURING a check produces exactly one more" (4 messages, 3 more written from inside a 200 ms check) | **fires = 2**, passes |
| `lsp-smoke`, `Burst.e`, 8 + 8 keystrokes 20 ms apart | **3** `check: Burst` lines (open + 2), publishes exactly `didOpen, didChange, didChange`, **2** `debounce:` lines both at **150** with medians of 8 and 7 ms |
| `lsp-smoke`, `Layout/Report.e`, 6 keystrokes 20 ms apart | **2** `check: Layout.Report` lines, **1** `debounce:` line at **300** with median **1993 ms** — the ceiling, end to end |
| the policy audit over the WHOLE run | I re-derived it myself rather than trusting the assertion: **61** `debounce:` lines in my run of record, and on every one of them `waited == policy == clamp(150, median, 300)` with `1 ≤ samples ≤ 5`.  **0 bad** |
| the pin | the phases server logs `debounce PINNED at 250ms (initializationOptions); the adaptive policy is off` and then `debounce: Good.e waited 250ms (median 64ms of 1 checks, policy 150ms, PINNED at 250ms)` — the loop waited the pin while the policy asked for 150 |

(The implementer's run had 41 such lines, mine 61.  The count is timing-dependent —
how many `didChange`s the client's own pacing lets coalesce — and the shipped
assertion correctly pins `≥ 3` rather than an exact count.)

### 3.2 The plant: does the pin have teeth?

I set `Debounce.Min = 150` → `10` in
`core/.../lsp/Diagnostics.scala`, recompiled, and ran `core/testOnly *TestEditorBuffers`:

    ! 7.4 a burst of keystrokes 20 ms apart is ONE check, at D_small: Falsified
      Expected 1 but got 4
    ! 7.4 the policy is clamp(Min, C, Max) over the median: Falsified  (Expected 10 but got 31)
    ! 7.4 the median outvotes, then forgets, a cold check: Falsified
    Failed: Total 12, Failed 3, Errors 0, Passed 9

**The burst pin HAS teeth**: with a 10 ms floor the 8-keystroke burst splits into
**four** checks and the property falsifies.  Two notes worth recording:

* the `D_large` burst (`quiet = 300`) and the during-a-check property **still passed**
  under the plant — the first because it does not read `Min` at all, the second because
  its 200 ms fake check dominates its 20 ms gaps.  So exactly ONE of the three loop
  properties is sensitive to `Min`; that is enough, but it is worth knowing which one
  is load-bearing.
* I then restored the file from the pre-plant copy and verified it byte for byte:
  `sha256 21d363d727e81720287089fab6f70f0c41a1d6459b4b6915baa01d9cf4f894fb` before and
  after, `sha256sum -c` OK, and the tree recompiled clean.  All four LSP sources were
  hashed again after the A/B class-tree work and match (`<scratch>/lsp-src.sha256`).

## 4. THE A/B — RE-MEASURED BY THE REVIEWER

**Protocol.**  `perf-client.py --rounds 15 --mode space`, interleaved before/after per
file, ONE JVM at a time, round 1 discarded, steady state rounds 2..15, the debounce
column HARVESTED from the server on the after side and the 0.300 fallback on the
before side (which logs no `debounce:` line — the fallback path is exercised and
prints its note, so I also confirmed that half of §5 for free).  The two sides are two
saved class trees: `before` is `core` rebuilt with the four LSP sources at `85eb150`
(`git checkout 85eb150 -- …`, compile, snapshot, restore, re-hash — all four sources
verified byte-identical afterwards); `after` is this tree.  The jar half of the
classpath is identical, and nothing outside `core` changed.
Scripts and logs: `<scratch>/ab.sh`, `<scratch>/{small,big}-{before,after}-N.{log,json,txt,load}`.

### 4.1 `Control/Monad/Reader.e`, 44 lines — THE ACCEPTANCE

| side | load | round trip | read | typecheck | debounce | residual | spread | cold open | reused |
|---|---|---|---|---|---|---|---|---|---|
| BEFORE | 0.90 | **0.320 s** | 0.010 | 0.010 | **0.300** (fallback) | 0.000 | 0.316–0.335 | 0.141 | 0/1 |
| AFTER | 1.03 | **0.173 s** | 0.010 | 0.010 | **0.150** (harvested, all 15 rounds) | 0.003 | 0.169–0.180 | 0.151 | 0/1 |
| **delta** | | **−0.147 s (−45.9 %)** | ±0 | ±0 | **−0.150** | | no overlap | | |

**Implementer: 0.3204 → 0.1719, −149 ms (−46.4 %).  Mine: 0.320 → 0.173, −147 ms
(−45.9 %).**  Same number inside 2 ms.  **The controls are unmoved** — read 0.010 and
typecheck 0.010 on both sides — and the whole delta is the debounce term, measured, not
attributed.  The per-round spreads do not overlap.  **THE ACCEPTANCE REPRODUCES.**

### 4.2 `Layout/Report.e`, 1757 lines — THE LARGE FILE

| side | load | round trip | read | typecheck | debounce | residual | spread | cold open | reused |
|---|---|---|---|---|---|---|---|---|---|
| BEFORE | 1.35 | **0.941 s** | 0.060 | 0.550 | **0.300** (fallback) | 0.027 | 0.915–1.057 | 2.620 | 97/154 |
| AFTER | 1.85 | **0.956 s** | 0.060 | 0.570 | **0.300** (harvested, all 15 rounds) | 0.030 | 0.907–1.063 | 2.666 | 97/154 |
| **delta** | | **+0.015 s (+1.6 %)** | ±0 | +0.020 | **±0** | | fully overlapping | | |

**Implementer: 0.8955 → 0.9063, +11 ms (+1.2 %).  Mine: 0.941 → 0.956, +15 ms
(+1.6 %).**  Same sign, same magnitude, same conclusion: inside the per-round spread
(which straddles it completely), below the ~50 ms editor noise floor, and with no
mechanism — the after side's window was **300 ms on every one of its 15 rounds**
(harvested from the server, C descending 2651 → 638 ms and never entering the band),
the read is identical and the typecheck moved 20 ms, which is the same size as the
run-to-run drift.  `Max = 300` makes this a property of the function, not of the run.

**Honest condition of the measurement.**  This desktop's 1-minute average oscillated
between ~0.8 and ~3.2 all session (the user's own applications; the implementer
recorded the same).  The SMALL-file pair ran at 0.90 / 1.03, comfortably inside the
1.3 gate.  The LARGE-file pair started at 1.35 / 1.85 — above the gate — after three
attempts to catch a dip; a first large-file BEFORE run at load 3.22 gave 0.885 s and is
recorded but excluded.  I am reporting the pair rather than hiding it because the
conclusion does not turn on it: the two sides ran within two minutes of each other on
the same rising load, the drift is on both sides, the difference is +1.6 % against a
15 % spread, and the term this item changes is provably identical on the two sides.
Taken with the implementer's two pairs at loads 1.12–1.27 the finding is settled.

## 5. BENCH COMPARABILITY

* **`perf-bench.sh editor -k 5` ran**, at load 1.04, and **the debounce column reads
  `0.300`** — "debounce: harvested from the server, all 0.300s", i.e. the pin took AND
  the harvest confirms it rather than assuming it.  Round trip **0.987 s** (spread
  0.977–1.018, read 0.080 + typecheck 0.580 + debounce 0.300 + residual 0.037, 97 of
  154 reused, cold open 2.453, boot 13.1 s).  Against 7.1b's **0.896 s** of record that
  is +10 %, and the cause is the machine and `-k 5`, not 7.4: `-k 5` leaves only FOUR
  steady rounds and a colder JIT, the load floor today is ~1.0 against 7.1b's quiet
  machine, and the read segment came out 0.080 against 0.050.  The control that settles
  it is §4.2: at `-k 15` in this same session the PRE-7.4 tree measured 0.941 s.  So the
  bench is comparable in the sense that matters — its own constant did not move — and I
  would not re-cut the roadmap figure from a `-k 5` run.
* **`perf-client.py` unpinned** (the §4 runs): the harvest works and reports its source
  — "harvested from the server, all 0.300s" on `Report.e`, "all 0.150s" on `Reader.e`,
  and on the pre-7.4 server "no 'debounce:' lines in the log — using the fixed 0.300s
  constant (a pre-7.4 server)".  Both branches exercised, both printed.  Without this
  the small file's residual column would have gone to −0.13 s, so the change is
  necessary, not decorative.
* **Documented?**  Yes in `docs/lsp.md` (the new "The debounce is derived from the
  measured check time" block names the option, its unit and its 1–10000 range) and in
  `perf-bench.sh`'s header.  It is NOT in the vscode README or `package.json`, and
  should not be: it is not a user setting.  Small gap — the docs' own "Fast mode"
  section is where a reader looks for initializationOptions and the debounce pin is
  described two sections away under Latency; one cross-reference would close it
  (**F-4**, INFO).
* **Does the pin leak into the real editor?**  **No.**  `Diagnostics.Debounce.pinnedMillis`
  starts `None` and is set only from `initializationOptions.debounce` in
  `Main.initialize`; `editor/vscode/src/extension.js` sends
  `initializationOptions: { fastMode: … }` and no `debounce` key, so the shipped client
  gets the adaptive policy.  Out-of-range values are refused and logged rather than
  clamped, which is the right failure mode for a measurement knob.  Unlike `fastMode`
  there is no `workspace/didChangeConfiguration` path to it — deliberate and correct.

### 5.1 The preflight the implementer could not get past

`perf-bench.sh`'s preflight did **not** refuse for me: it ran, printed
`load 1.04, .ei present 0`, and completed.  The guard is
`pgrep -f 'sbt-launch|xsbt\.boot' && fail "an sbt build is running"`, and `pgrep -f`
matches on the FULL command line of every process — including the shell that is running
the agent's command, if that command line happens to contain the literal pattern.  That
is almost certainly what the implementer hit: not a 15-hour-old lingering shell but a
self-match from an enclosing `bash -c` whose own text contained
`'sbt-launch|bin/ermine|ermine-lsp'`.  It is the same class of false positive the
script's header already documents for the ermine-JVM guard, it is harmless (it fails
CLOSED), and nothing was worked around — I report what I saw, which is that the path is
not blocked.

## 6. FINDINGS

| id | severity | status | one line |
|---|---|---|---|
| **F-1** | LOW | CONFIRMED | the written justification for `Min = 150` contradicts its own figures: it names 200–300 ms/char sustained typing and then claims 150 ms coalesces "at any speed" |
| **F-2** | LOW | CONFIRMED | "the window cannot jump between regimes on one slow check" is false, and an alternating check cost makes D alternate 150/300 forever — the clamp, not the median, is what makes the feedback safe |
| **F-3** | INFO | CONFIRMED | "a new document's first check is unchanged at 300" is vacuous: the first check is the `didOpen` one and pays NO window; the no-history branch is unreachable for a `.e` file |
| **F-4** | INFO | CONFIRMED | the `debounce` initializationOption is documented under Latency but not beside `fastMode`, where a reader looks for initializationOptions |
| **F-5** | LOW | CONFIRMED | `quiet()` takes the MINIMUM window over ALL queued documents; with two documents queued the thread runs their checks back to back after the shorter window (duty cycle 67 % → 80 %), and the smoke audit's `waited == policy` would then fail spuriously |
| **F-6** | INFO | CONFIRMED | `--allow-no-reuse` waives BOTH bench assertions, including the "reused EVERYTHING" flattering-measurement guard, which is not the one you want to lose |

**F-1 — `Min = 150` is argued from a figure that refutes it.**  The scaladoc and
`docs/lsp.md` both say the floor must exceed the gap between keystrokes "or a burst
stops coalescing and every character gets its own check", give the sustained-typing gap
as 200–300 ms per character, and then conclude that 150 ms "coalesces within-word
bursts at any speed and a steady fast typist's stream as well".  The last clause is
true for within-word digraphs (60–80 ms) and for 100 wpm (~120 ms) — I verified the
120 ms case from the loop semantics and the 20 ms case end to end — but NOT for the
200–300 ms interval the same sentence calls sustained typing.  At 40–60 wpm, on a file
whose check is at or below 150 ms, 7.4 turns one check per burst into one check per
character.  This is BOUNDED and arguably what you want (the squiggle is 150 ms fresher
every character; the duty cycle is at worst 150/350 ≈ 43 % and the hover wait at worst
one 150 ms check), and it does not touch any file whose check exceeds 150 ms.  It is
a documentation fix, not a code fix: say "Min = 150 coalesces every burst faster than
150 ms per character, and below that speed it buys freshness at a bounded duty cycle",
and the constant survives the correction unchanged.

**F-2 — the no-oscillation argument proves less than it claims.**  §2.1 of the
implementer's report and the scaladoc's "NO OSCILLATION" paragraph rest on "a median of
five changes by at most one order statistic per step" and "one slow check cannot move D
unless it is the middle of five".  Counterexample (§2.3): window `[100,100,400,400,100]`
has median 100 → D = 150; one 400 ms check arrives, evicting a 100, giving
`[400,100,100,400,400]`, median 400 → D = 300.  Floor to ceiling in one step.  And a
period-2 check cost (100/400 ms, or 140/320 ms) drives D into a permanent
`300 150 300 150 …` alternation, because a five-window over a period-2 sequence is
itself period-2.  I could not produce this on a real module and none of the five files
measured in this review or the implementer's comes close to it (`Complete.e`'s
186/177 ms wobble is D tracking C correctly, not a regime flip), so the PRACTICAL claim
"no oscillation was observed" stands on the evidence.  What should change is the
argument: the property that actually protects the server is the one the report already
states one paragraph earlier — **both ends are clamped and the upper clamp IS the
pre-7.4 constant, so the worst case of the feedback loop is today's behaviour** — and
that survives alternation intact.  Drop the "cannot jump" sentence.

**F-3 — the no-history default is a branch nothing reaches.**  `install`'s `didOpen`
handler calls `run(…)` SYNCHRONOUSLY; only `didChange` queues.  So by the time any
document can pay a window it has been checked at least once and `checkMillis` is
non-empty, and `policy(Nil) = Max` is dead code for a `.e` file (it is live only for a
document whose open-check was skipped — a non-`.e` path, which cannot be queued either).
The measured runs show this plainly: `Reader.e`'s very first debounced check already
waited 150 ms, off a single 144 ms sample.  Nothing is wrong; the row in §1.2 and the
sentence in `docs/lsp.md` ("so a file's FIRST check waits exactly what it waited before
7.4") should say that a file's first check is immediate and pays no window at all, and
that the first DEBOUNCED check is derived from the open's own cost.

**F-4 — where the option is documented.**  `docs/lsp.md` describes `debounce` fully
(unit, range, purpose) inside the Latency section's new debounce block.  A reader
looking for initializationOptions finds the "Fast mode" section, which describes
`fastMode` and its `workspace/didChangeConfiguration` twin and does not mention
`debounce`.  One cross-reference, plus a sentence saying the pin is deliberately NOT
reachable from `didChangeConfiguration` (it is a measurement knob, not a setting),
closes it.  The vscode README correctly does not list it.

**F-5 — the cross-document minimum.**  `quiet()` is
`queued.keysIterator.map(u => Debounce.millis(docs.checksFor(u))).min`, and the code
comment justifies it with "(In practice one document is queued: you type in one
buffer.)"  That is true of typing and not true of a multi-file `WorkspaceEdit` echoed
back as two `didChange`s, which is a shape this server can itself produce.  When it
happens, `idleWork` runs BOTH checks back to back inside one invocation with no quiet
gap, after the SHORTER of the two windows: `Reader.e` + `Report.e` is 0.61 s of solid
dispatch-thread work behind a 150 ms gap, a duty cycle of 80 % against the 67 % the same
pair would have had before 7.4.  It is one-shot (the queue is cleared by the fire), the
total work is identical, and no request can wait longer than the same single check it
would have waited for anyway — so this is an observation, not a defect.  The part worth
acting on is the pin: with two documents due, the `debounce:` line prints the shared
`waited` beside each document's own `policy`, so `waited != policy` legitimately, and
`lsp-client.py`'s `waited == policy == clamp(150, median, 300)` audit would fail on a
correct server the first time a fixture queues two documents.  Relax it to `waited <=
policy` (or assert equality only when one document is due) before someone writes that
fixture.

**F-6 — `--allow-no-reuse` waives the guard you want least.**  The flag turns off both
`reused == 0` ("the edit was not the in-body edit this bench assumes") and
`reused >= components` ("the flattering measurement PERF-ROADMAP warns about").  For the
two files it is used on the waiver is genuinely inapplicable — `Reader.e` has ONE
binding group and `Options.e` has NONE — but a future user of the flag on a bigger file
loses the flattering-measurement guard silently.  Splitting it into `--allow-no-reuse`
and keeping the "reused everything" assertion armed would cost one line.  (Also
cosmetic, same file: `wait_at = dict(zip((id(r) for r in edit_rounds), waits))` keys a
dict by `id()` of live dicts; it is correct because `edit_rounds` holds the references,
but a plain index would be less surprising.)

### 6.1 Coverage note (not a finding)

Two behaviours the item argues for are pinned only indirectly.  That `checkMillis`
survives an edit is visible in the smoke log (`Edit.e … of 1 / 2 / 3 / 4 / 5 checks`
climbing across consecutive `didChange`s, which is only possible if `put` carries it),
and that it is dropped on `didClose` is not pinned at all — no fixture closes and
reopens a document and asserts the window went back to the no-history default.  Neither
is worth a new item; a reviewer should just know they rest on reading `Documents.put`
and `Documents.drop`.

## 7. docs/lsp.md — checked against my own numbers

| what the docs say | verdict |
|---|---|
| "Published on didOpen, on didSave, and 150–300 ms after the last didChange" | accurate |
| `D = clamp(150 ms, C, 300 ms)`, C = median of the last five measured check times of that document | accurate, and it is the rule as a function with its constants, which is what the roadmap item asks for |
| "D = 300 ms while a document has no history (so a file's FIRST check waits exactly what it waited before 7.4)" | the formula is right, the parenthetical is wrong — **F-3** |
| "The floor is 150 ms because a window shorter than the gap between keystrokes stops coalescing a burst — sustained typing is ~200–300 ms per character and a fast typist ~120 ms" | self-refuting as written — **F-1** |
| "the queue holds one entry per document and a superseded check is dropped before it starts" | accurate (`queued += uri -> v`, then the versioned drop) |
| "Between the two, the window tracks the check time one-for-one, so at most half the dispatch thread goes to checking while you type" | accurate — the qualifier "between the two" is doing the work, and inside the band the figure is exactly 50 % at the edge |
| "a small file stopped waiting 300 ms for a 20 ms check (0.32 → 0.17 s)" | **reproduced: 0.320 → 0.173 s** |
| "the largest module did not move, because its check is 0.58 s and the policy asks for the ceiling" | **reproduced: +15 ms, inside spread, window 300 ms on every round.**  Two pedantic notes: the cost the policy actually uses is the whole of `Diagnostics.run` (0.64–0.75 s in my runs, not 0.58, because it includes the index build and the publish's preparation), and on this machine today the round trip is 0.94–0.99 s rather than 0.90 — both differences are pre-existing and neither changes the row's claim |
| the Latency table's three keystroke rows (LARGEST 0.90, SMALL 0.17, MID 0.21) | the SMALL row is mine to 3 ms; the LARGEST row is 7.1b's and the pin is what keeps it comparable; the MID row I did not re-measure |
| the example log line `debounce: Report.e waited 300ms (median 551ms of 5 checks, policy 300ms)` | the format is exactly what the server emits (mine: `waited 300ms (median 1993ms of 1 checks, policy 300ms)`) |
| the pin: "A client may pin a fixed window with the `debounce` initializationOption (milliseconds, 1–10000)" | accurate; placement only — **F-4** |

## 8. GATES

Run on this tree, in this order, one JVM at a time, nothing re-run except where noted.

| layer | expected | result |
|---|---|---|
| `sbt core/compile core/copyResources` | green | **green** |
| `core/testOnly *TestLoopTrace` | 720/720 | **720 segments, 720 agree**, hashdiff 0 / eqdiff 0 / skipped 0, `nonpart=0 rejected=36 fuel=0`; 3 of 3 properties |
| `core/testOnly *TestEditorBuffers *TestTolerantCheck *TestSurfaceCache` | 64 | **64 of 64**, `TestEditorBuffers` 12 properties (6 → 12) |
| `corpus-run.sh --batch` | 85 / 69 / 0 | **154 outputs, 85 LOADED / 69 REJECTED / 0 UNKNOWN** — the baseline exactly |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups, 66 checks, all PASS** (2+5+9+12+6+4+23+5), goldens unmodified (`git status` clean under `tracker/` except the item's own files) |
| `lsp-smoke.sh` | 510 | **PASS, 510 checks** (494 after 7.1b, +16) |
| boot | 129 | **129 modules in 12.3 s** (13.1 s under the bench) |
| `.ei` by `find` | 0 new | **0 left**: 143 on disk at the end, all 143 tracked (`tracker/g1-baseline/ei`), 0 untracked.  My Tier-2 run DID drop **7** into `core/target/scala-3.3.8/classes/modules/` (`Bool`, `Function`, `Function/Endo`, `Ord`, `Primitive`, `Control/Category`, `Control/Monoid`, all stamped inside the `core/test` window); they are gitignored build output, they are pre-existing `core/test` behaviour and nothing to do with 7.4, and I deleted them by `find` |
| `git diff --stat` == `--stat -w --histogram` | identical | **identical** (9 files, 533+/32−, both forms byte for byte) |
| line endings | unchanged | every changed file reports the same `file -` type as `git show HEAD:<f>`; **0 CR** in the whole diff; `Burst.e` is LF like the other fixtures; the CRLF stdlib is untouched.  (`docs/lsp.md` differs only in `file`'s "very long lines (506 → 654)" note — the new table row — not in line endings) |
| Tier 1 | not needed | agreed: nothing in `scalaparsers`, `Subst.scala` or `Type.scala` changed |
| **Tier 2: `sbt -batch -J-Xmx3g core/test` ALONE** | **1026** | **1026 properties, Failed 0, Errors 0, Passed 1026** — exactly the predicted 1020 + 6, on the FIRST run, 1429 s (23:49), one JVM alone on the tree.  Neither E12 (`TestInterfaceRoundTrip`) nor E13 (`TestLegend`) went red, so no re-run was used |

The 16 new lsp-smoke checks, listed: Burst.e clean on open; a burst of 8 keystrokes
still publishes, and publishes clean; a second burst of 8 is exactly one more check;
`Layout/Report.e` clean on open; a burst on the largest module publishes clean; Burst.e
on disk untouched by the buffer edits; sixteen keystrokes in two bursts produce exactly
two checks; one check, one publish; each burst waited exactly one window; a small
file's window is the FLOOR, 150 ms; a burst on the largest module is also exactly one
check; the largest module waits the CEILING, 300 ms; every debounced check logged its
policy; `waited == clamp(150, median, 300)` on every debounced check over at most 5
samples; `initializationOptions.debounce` pins the window; a pinned window is what the
loop waits, whatever the policy says.  = 16.

### 8.1 The wall-clock properties under a loaded suite

The three new `TestEditorBuffers` properties drive the real dispatch loop against real
wall-clock sleeps, which is the obvious flake risk: a `Thread.sleep(20)` that stretches
past 150 ms would split the burst and falsify the pin.  They were green in the targeted
run (a quiet machine) AND green inside the full `core/test`, which runs suites in
parallel and pushed the 1-minute load average to **8–12**.  A 20 ms gap would have to
stretch more than 7× to break the D_small pin and more than 15× to break D_large, and
the plant shows the margin is being spent on the right thing.  I am satisfied these are
as robust as a wall-clock property gets; if one ever does flake, it belongs in
GATE-POLICY next to E12/E13 rather than being weakened.

## 9. VERDICT — **ADVANCE**

**THE ACCEPTANCE REPRODUCES, ON MY OWN INTERLEAVED A/B.**  `Control/Monad/Reader.e`
**0.320 → 0.173 s, −147 ms (−45.9 %)**, read and typecheck unmoved at 0.010 s each as
controls, per-round spreads disjoint, both legs under load 1.3, the whole delta in the
debounce term which the server itself reported.  Beside the implementer's −149 ms
(−46.4 %) that is the same measurement.

**THE LARGE FILE DID NOT GET WORSE, AND COULD NOT HAVE.**  `Layout/Report.e`
**0.941 → 0.956 s, +15 ms (+1.6 %)** against a 0.907–1.063 s spread, with the after
side's window harvested at **300 ms on every one of 15 rounds** (C 638–2651 ms, never in
the band).  Beside the implementer's +11 ms, same sign and size.  `Max = 300` being the
pre-7.4 constant is what makes "the policy can only shorten a wait" a property of the
function rather than a hope, and it is the single best decision in the item.

**THE POLICY IS AUDITABLE AND THE ARITHMETIC HOLDS.**  I re-derived
`clamp(150, median, 300)` independently over all **61** `debounce:` lines of my
lsp-smoke run of record: **0 disagreements**, `1 ≤ samples ≤ 5` everywhere, the floor
measured end to end on `Burst.e` and the ceiling on `Layout/Report.e`.  The burst pin
holds through the real `Server`/`Wire` loop and through the scripted client, and the
**plant proves it has teeth** (`Min = 10` ⇒ the 8-keystroke burst becomes 4 checks and
the property falsifies; restored and hash-verified).  The bench pins 300 and reads
0.300; the pin does not leak into the shipped editor; the harvest's pre-7.4 fallback
works and says so.

**EVERY GATE AT OR ABOVE BASELINE, INCLUDING TIER 2 ON THE FIRST RUN:**
compile green, `TestLoopTrace` 720/720, targeted 64/64, corpus 85/69/0, repl-smoke
8 groups / 66 checks, lsp-smoke **510** (+16, listed), boot 129, `.ei` 0 left,
`git diff --stat` identical to `--stat -w --histogram`, line endings unchanged, and
**`core/test` 1026 / 1026, Failed 0, Errors 0** — no E12/E13 re-run needed.

**WHY NOT FIX-THEN-ADVANCE.**  Every finding is about the WRITTEN ARGUMENT or a test's
future brittleness, not about behaviour: no constant changes, no code path is wrong, and
the three corrections (F-1, F-2, F-3) make the case for the item *stronger*, not weaker —
the constants survive all three intact, because what actually protects the server is the
clamp and the fact that its upper end is the old constant.  I would fold them into the
scaladoc and `docs/lsp.md` in the commit that lands the item, together with F-5's
one-line relaxation of the smoke audit (`waited <= policy`), and that is editorial work a
committer can do without another measurement.  Nothing here is worth a second round
trip through the loop.

**BASELINES A COMMIT MUST UPDATE** (untouched here, as the brief requires):
`lsp-smoke.sh` **494 → 510**, `core/test` **1020 → 1026**.

STOP after this report.
