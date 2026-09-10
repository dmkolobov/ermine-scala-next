# LSP Stage 4, item 7.0 — INDEPENDENT REVIEW of the direct measurement of the read

VERDICT ON THE ITEM: **FIX-THEN-ADVANCE**.
VERDICT ON THE STAGE: **agree 7.1**, with the number **~0.76 s (45 % of the round
trip)** rather than the report's 0.82 s / 48 %; band 0.67–0.83 s.  **7.2 first**,
confirmed.

Reviewer's run, branch `scala3-migration`, HEAD `69c7f1b` plus the item's
uncommitted deliverables.  Tier 0.  Nothing in the tree was edited except this
file; every harness is in the reviewer scratch
`<scratch>/review-7.0/`.  One JVM at a time throughout, load recorded per run,
0 `.ei` droppings (143 `.ei` in the tree, all tracked fixtures, count unchanged).

The item's four headline numbers were re-measured.  **Three of the four
reproduce; one does not, and one supporting claim is false.**

| the implementer's number | reviewer |
|---|---|
| parse 843.6 ms | **829.8 ms** — reproduces (1.7 %) |
| read 859.6 ms | **845.4 ms** — reproduces (1.7 %) |
| ratio **0.963** | **0.953** — does not reproduce; see F2 |
| cliff 0 of 154 / 1.07 s | **0 of 154 / 1.06 s** — reproduces exactly |
| "**all 591 statements parse alone**" | **529 of 591** — FALSE, and the check was vacuous; see F1 |

---

## 1. THE PHASE TABLE, re-measured

Run **C**, the reviewer's run of record.  `perf-client.py --rounds 70` through
the real server with `-Dermine.lsp.phases=true`, rows 21..70 = 50 measured reps
after 20 warm-ups, `Layout/Report.e` (1757 lines, 77,385 B).  **Load 0.97** at
start (2.45 at end; the bench JVM is ~1.0 of that).  Round trip median
**1.676 s** = read 0.850 + typecheck 0.510 + debounce 0.300 + residual 0.024;
spread 1.617–1.862 s; **reused 97 of 154** every round; cold `didOpen` 2.197 s;
boot **12.81 s / 129 modules**.

All figures in milliseconds.  "impl B" is the report's run of record.

| phase | **reviewer median** | min | p10 | p90 | max | share of check | impl B | C/B |
|---|---|---|---|---|---|---|---|---|
| `rpc.frame` | 0.081 | 0.055 | 0.056 | 0.129 | 0.155 | 0.006 % | 0.067 | 1.21 |
| `rpc.log` | 0.035 | 0.017 | 0.022 | 0.047 | 0.102 | 0.003 % | 0.036 | 0.97 |
| `rpc.json` | **0.307** | 0.295 | 0.298 | 0.467 | 0.552 | 0.023 % | 0.306 | 1.00 |
| `envcopy` | 0.009 | 0.008 | 0.008 | 0.011 | 0.014 | 0.001 % | 0.009 | 1.00 |
| `header` | **8.053** | 7.392 | 7.603 | 11.261 | 13.474 | 0.59 % | 8.210 | 0.98 |
| `scrub` | 2.058 | 1.960 | 1.987 | 2.161 | 2.514 | 0.15 % | 1.961 | 1.05 |
| `imports` | 0.039 | 0.036 | 0.037 | 0.046 | 0.052 | 0.003 % | 0.039 | 1.00 |
| **`parse`** | **829.841** | 799.298 | 814.813 | 849.082 | 862.577 | **60.9 %** | 843.553 | 0.98 |
| `syntax` | 0.036 | 0.030 | 0.032 | 0.045 | 0.082 | 0.003 % | 0.037 | 0.97 |
| `rename` | **5.043** | 4.381 | 4.613 | 5.469 | 7.858 | 0.37 % | 5.020 | 1.00 |
| `reassoc` | 0.677 | 0.468 | 0.597 | 0.875 | 1.269 | 0.05 % | 0.716 | 0.95 |
| `lowerctx` | 3.993 | 3.593 | 3.747 | 4.552 | 8.578 | 0.29 % | 4.087 | 0.98 |
| `lower` | 5.076 | 4.463 | 4.689 | 5.539 | 7.759 | 0.37 % | 5.165 | 0.98 |
| **`read.total`** | **845.371** | 814.032 | 829.085 | 864.993 | 878.959 | **62.0 %** | 859.629 | 0.98 |
| `notes.pre` | 0.080 | 0.073 | 0.075 | 0.094 | 0.128 | 0.006 % | 0.082 | 0.98 |
| `extents.scan` | **0.806** | 0.795 | 0.800 | 0.912 | 1.619 | 0.06 % | 0.736 | 1.10 |
| `extents.offsets` | **1.551** | 1.529 | 1.532 | 1.981 | 2.713 | 0.11 % | 1.585 | 0.98 |
| `keys.total` | 3.272 | 3.140 | 3.177 | 3.985 | 4.893 | 0.24 % | 3.229 | 1.01 |
| **`checkWith`** | **492.377** | 447.938 | 465.886 | 522.818 | 567.889 | **36.1 %** | 496.440 | 0.99 |
| `notes.post` | 0.048 | 0.042 | 0.045 | 0.058 | 0.084 | 0.004 % | 0.046 | 1.04 |
| ` └ index.symbols` | 0.417 | 0.356 | 0.389 | 0.492 | 0.806 | 0.03 % | 0.434 | 0.96 |
| `index` | **9.953** | 9.467 | 9.540 | 10.860 | 14.635 | 0.73 % | 10.116 | 0.98 |
| **`check.total`** | **1362.990** | 1314.057 | 1323.553 | 1406.981 | 1451.562 | 100 % | 1388.037 | 0.98 |

**The table reproduces.**  Every row is within 5 % of the implementer's run B
except `rpc.frame` (81 µs vs 67 µs — a 14 µs row) and `extents.scan` (0.81 vs
0.74 ms — a 0.07 ms row).  The two runs of record differ by 1.7 % on `parse`,
which is a *quarter* of the 8 % spread the implementer's own A/B pair showed.
**The 8 % drift is real but it is between-JVM, not within-JVM** — see F2, where
five orderings inside ONE JVM agree to 0.3 %.

Shares: parse is **98.2 % of the read** and **60.9 % of the check**; the read is
**62.0 % of the check** and **50.7 % of the round trip**.  Every share in the
implementer's §8 arithmetic is confirmed to the third digit.

### Reconciliation

Computed per round (medians do not add) with `harvest.py`, the implementer's
reducer, whose `top` list correctly excludes the `rpc.*` rows (they are recorded
before `check.total`'s window opens) and `index.symbols` (nested inside `index`):

| | impl B | **reviewer C** |
|---|---|---|
| read parts vs `read.total` | +0.036 ms (+0.004 %) | **+0.035 ms (+0.004 %)** |
| top-level parts vs `check.total` | +0.361 ms (+0.026 %) | **+0.359 ms (+0.027 %)** |

**The 0.1 % reconciliation claim holds on the reviewer's run too**, to the same
third digit.  This is the strongest thing in the item: the table is not a
sample share, it accounts for 99.97 % of the check by construction, and the
0.36 ms it does not account for is named correctly (the code between the timed
blocks in `Resident.checkFile`).

### Inertness, and the shipped configuration

A second server run with the property **off**, 40 rounds, load 1.21: round trip
**1.683 s**, read **0.840 s**, typecheck 0.510, boot 12.71 s, reused 97/154, and
**0 `phases:` lines in a 303 KB log**.  Against the property-on run's 1.676 /
0.850 that is −7 ms of round trip and +10 ms of read — i.e. the *enabled*
configuration is already indistinguishable from the shipped one, which bounds
the disabled one a fortiori.  The code fact is in F4: every site but one is a
single boolean field read.

---

## 2. THE RATIO, re-measured and attacked

Reviewer harnesses, scratch only: `RevBench.scala` (reproduction + validity
audit + per-extent CSV) and `OrderBench.scala` (five measurement orders in one
JVM).  Same protocol, 20 warm-ups / 50 reps, load 0.93 and 0.84 at start.

| measurement (bench JVM, ms) | **reviewer** | impl |
|---|---|---|
| extents | 591, 65,421 B, mean 110.7, median 50; 575 with a head word, 294 distinct | same |
| per-statement median | **0.614** | 0.595 |
| per-statement mean | **1.226** | 1.174 |
| per-statement p90 | **2.300** | 2.183 |
| per-statement max (the big `private` block) | **104.13** | 99.021 |
| sum of 591 slice parses | **736.2** (sweep-first) | 723.9 |
| whole file, same JVM | **772.4** (whole-last) | 751.7 |
| **RATIO** | **0.953** | **0.963** |
| residual (whole − sweep) | **36.3 ms (4.7 %)** | 27.8 ms (3.7 %) |
| `StatementExtents.scan` alone | 1.07 | 1.10 |

### Order effect: REFUTED as an explanation

The implementer's harness runs the 591-slice sweep first and the whole-file
parse last, so the whole-file side sees a warmer JIT.  Five regimes in one JVM:

| regime | sweep | whole | ratio | residual |
|---|---|---|---|---|
| implementer's order (sweep 1st, whole last) | 736.16 | 772.42 | **0.9531** | 36.26 (4.69 %) |
| reverse (whole 1st, sweep last) | 737.13 | 773.85 | **0.9525** | 36.72 (4.75 %) |
| interleaved, alternating every rep | 739.83 | 775.55 | **0.9539** | 35.72 (4.61 %) |
| first-of-each | 736.16 | 773.85 | **0.9513** | 37.69 (4.87 %) |
| last-of-each | 737.13 | 772.42 | **0.9543** | 35.29 (4.57 %) |

**0.9513–0.9543 — a 0.3 % band.**  Order is not the explanation for anything.
The ratio is a within-JVM quantity and it is stable; what is *not* stable is the
absolute whole-file number, which moved 772–796 ms across the reviewer's own two
JVMs (3 %) and 752–830 ms between the bench and the server (10 %).

### Compensating errors: four hypotheses, all dead or small

1. **The 591 `nanoTime` pairs per sweep.**  A wall-clocked sweep (one clock pair
   for the whole 591) is **754.80 ms** against the clocked sum's **756.46 ms** in
   the same rep loop: **1.7 ms, 0.22 %**.  Dead.
2. **591 `Supply.create.split` draws on the slice side against 1 on the
   whole-file side.**  Measured directly: **0.039 ms** for 591 draws, 0.005 %.
   Dead.
3. **JIT / order.**  Table above.  Dead.
4. **The slice side IS flattered, twice, and both are small.**  (i) The 591
   substrings and `ParseState`s are built OUTSIDE the timing loop; a real cache
   pays that once per miss, not 591 times, so this is the right choice for the
   ratio but it means the sweep is not a per-check cost.  (ii) `atLayoutBoundary`
   — which `statement` runs after every alternative — calls
   `StatementExtents.skipTrivia` over the text **after** the extent.  On a slice
   the input is exhausted and it skips nothing; in the file it skips the
   comment/blank-line run after every statement.  The file carries 11,964 bytes
   (15.5 %) of exactly that trivia.  This is the lookahead-past-the-extent hazard
   the survey names in §5(a), and **this harness is structurally blind to it**.

Both remaining biases push in the direction that flatters 7.1, and both are
inside the 4.7 % residual.  Neither moves the verdict.

### The decomposed residual — the number the report should have quoted

`SurfaceParsers.header` timed alone in the same JVM: **5.82 ms** (5.63 ms on a
second pass).  Sweep restricted to the 529 real statements (F1): **725.39 ms**.

    whole-file 773.85  −  header 5.82  −  529 real statements 725.39
      =  driver / layout / trivia residual  42.64 ms  =  5.5 % of the whole-file parse

That is the honest floor a slice cache pays if it reuses *inside* `module()`'s
`statement.attempt.sepEndBy(semi).between(virtualLeftBrace, virtualRightBrace)`
driver.  The implementer's **27.8 ms / 3.7 %** is at the optimistic end of a
**28–43 ms / 3.7–5.5 %** band, and it is a small difference of two large numbers
whose absolute values move 3–10 % between JVMs.  It should enter the roadmap as
a band, not a point.

### Sublinearity (the brief's 3(c))

Log-log fit over the 529 real statements: **ms = 2.52e-2 × bytes^0.837,
R² = 0.80** — **sublinear**, with a per-statement fixed cost of ~0.15–0.25 ms.
Per-byte cost by size decile falls monotonically-ish from **16.3 µs/B** (mean
18.6 B) to **9.2 µs/B** (mean 605 B); aggregate 11.3 µs/B, marginal
(through-origin) **9.65 µs/B**.  The implementer's 10.9 µs/B is the aggregate and
is right; "no fixed-cost cliff" is right; but there IS a per-statement fixed
cost, and it is why 591 small slices come to 4.7 % *less* than one whole-file
pass rather than more.  **Superlinearity would have re-ranked 7.3; there is
none, so 7.3's ranking is unaffected by this axis.**

---

## 3. FINDINGS

| id | severity | status | finding |
|---|---|---|---|
| F1 | **MAJOR** | CONFIRMED | "All 591 statements parse alone" is false (529 of 591) and the check that produced it could not fail |
| F2 | **MODERATE** | CONFIRMED | the ratio is 0.953, not 0.963, and the residual is 4.6–5.5 %, not 3.7 % |
| F3 | **MODERATE** | CONFIRMED | the "38 ms → 0.88 s" arithmetic double-counts the header, quotes the median where the expected value is 34x larger, and is only reachable under a cache design its own residual term contradicts |
| F4 | MINOR | CONFIRMED | one timed site is not inert: `Diagnostics.check` evaluates `System.nanoTime` eagerly with the property off |
| F5 | MINOR | CONFIRMED | private/database blocks are 18.9 % of the file's bytes and 22.3 % of the sweep; the expected miss cost is 20.5 ms, not 0.60 ms |
| F6 | MINOR | CONFIRMED | the per-statement parse is SUBLINEAR in bytes (exponent 0.837), with a real per-statement fixed cost |
| F7 | MINOR | REFUTED | the compensating-error hypotheses (clock overhead, `Supply` draws, JIT order) are all dead; two small residual biases remain, both flattering 7.1 |
| F8 | MINOR | CONFIRMED | the attribution table mixes SHARE and ABSOLUTE bases between rows |
| F9 | INFO | CONFIRMED | the header is parsed twice, but by two DIFFERENT grammars; ~14 ms, 1.0 % of the check; not a Stage-4 line today, a follow-on to 7.1b |
| F10 | INFO | CONFIRMED | both lsp-smoke gate directions are non-vacuous; output reaches the LSP log only |
| F11 | INFO | CONFIRMED | the 7.2 cliff reproduces exactly |
| F12 | INFO | CONFIRMED | `Rpc.scala`'s diff is timer-only; the run-based scanner is not in the tree |
| F13 | INFO | CONFIRMED | the strict path is unchanged in behaviour, by code and by four gates |

### F1 — "all 591 statements parse alone" is false, and the check was vacuous  (MAJOR)

The report's §4.2 states: "**All 591 statements parse alone (591 of 591).**  The
known divergence `statementFailure`'s docstring records … does not bite on a file
that parses whole."  Both sentences are unsupported, and the second is the one
that matters, because it is the survey's named risk for 7.1b.

`StmtBench.parseOne` is `SurfaceParsers.statement.run(ps, …).isRight`.
`SurfaceParsers.statement` is

    optionalSpace.skipOptional >> ((statementAlts(bindingStatement) << atLayoutBoundary).attempt | rawStatement)

`rawStatement` is a **total** per-character offside scan that always succeeds on
well-formed layout and yields an `SErrorStatement`.  So `.isRight` is true
whether the statement parsed or the parser fell off the end of every real
alternative.  **The check cannot fail.**

Two independent audits, in the reviewer's harness, agree to the unit:

* inspect the *result* of `statement.run` — **62 of 591** are `SErrorStatement`,
  i.e. `rawStatement` fallbacks;
* run `SurfaceParsers.statementFailure` (the real oracle: `statementAlts <<
  optionalSpace << eof`, no `.attempt`, forced to consume the whole extent) —
  **62 of 591** extents do not parse whole.

The 62 are exactly the **60 `import` + 2 `export`** extents.  `statementAlts` has
no import or export alternative, because in the whole-file parse imports are
consumed by `SurfaceParsers.header`, not by the statement driver;
`StatementExtents.scan` is a lexical splitter and does not know that.

**Effect on the ratio: small.**  The 62 are 2,024 B (3.1 % of extent bytes) and
**9.57 ms (1.32 %)** of the sweep, where the whole-file side pays the real header
parse (5.82 ms).  Restricting both sides to real statements moves the ratio from
0.953 to 0.945.  The report's conclusion survives.

**Effect on the item's credibility, and on 7.1b: not small.**  (i) The reuse unit
is **529 statements plus 62 header extents**, not 591 — 7.1b must key the header
separately or it will cache 62 `SErrorStatement`s.  (ii) The claim that the
slice-vs-whole divergence "does not bite" is not evidence: the harness would
report 591/591 on a file where it bit on every statement.  The survey's §5(a)
oracle (a 180-file differential asserting the spliced `SModule` equals a fresh
whole-file parse) remains entirely unaddressed and must not be treated as
partly discharged by this item.

### F2 — the ratio is 0.953 and the residual 4.6–5.5 %  (MODERATE)

Section 2 above.  The measurement is sound and the *conclusion* — "the parse
cost IS per-statement work" — stands with room: 95 % is not 96 %, and neither is
near enough to 1 for the difference to matter to the ranking.  What matters is
the complement: the residual the cache cannot remove is **36–43 ms**, not 28, and
that term dominates 7.1b's floor (F3).  The number that enters the roadmap
should be **ratio 0.95, residual 42.6 ms / 5.5 % (decomposed), 36 ms / 4.7 %
(raw whole-minus-sweep)**.

### F3 — the "38 ms → 0.88 s" arithmetic  (MODERATE)

The report's floor is `extents.scan 1.10 + one statement 0.60 + driver residual
27.80 + header 8.21 ≈ 38 ms`, giving "saving ~0.82 s of read; round trip
1.698 → ~0.88 s (48 %)".  The subtraction 1.698 − (0.860 − 0.038) = 0.876 is
correct.  Three things behind it are not.

1. **The header term is double-counted or out of scope.**  `Resident`'s
   `header` timer (8.05 ms) sits *outside* `read.total` — it is not part of the
   859.6 ms the saving is subtracted from, so adding it to the floor and then
   subtracting the result from `read.total` charges the cache for work the read
   never contained.  Meanwhile `module()`'s own header parse (measured directly:
   **5.82 ms**) is already inside the 27.8 ms residual.  Either way the 8.21 is
   wrong by ~8 ms.
2. **0.60 ms is the median, and the distribution is not median-shaped.**  A
   one-character edit does not land on a uniformly-chosen extent; it lands
   uniformly over the *text*.  Byte-weighted over the 529 real statements the
   **expected miss cost is 20.49 ms** (line-weighted 17.59 ms over 1,206
   statement lines), and the byte-weighted **p90, p95 and p99 are all 104 ms** —
   the single `private` block at lines 1586–1757 is 10,707 B, 13.8 % of the
   file's bytes, so **one edit in seven pays the p100**.  The report quotes the
   p100 correctly as 99 ms but pairs it with a median floor.
3. **The residual term contradicts the design that reaches 38 ms.**  Charging the
   cache 27.8 ms of driver residual presumes it reuses *inside* `module()`'s
   `sepEndBy(semi)` driver.  A design that instead runs `StatementExtents.scan`
   and splices per-extent trees never runs the driver and never pays it — and
   only that design gets near 38 ms.  Both are legitimate; the arithmetic mixes
   them.

Corrected, with the reviewer's numbers, server-scaled by 829.84/773.85 = 1.072:

| | conservative (cache keeps `module()`'s driver) | aggressive (cache replaces `module()`) |
|---|---|---|
| `extents.scan` | 0.81 | 0.81 |
| driver / trivia residual | **45.7** | — |
| one statement, median | 0.66 | 0.66 |
| **parse floor, median edit** | **47.2 ms** | 1.5 ms |
| parse floor, byte-weighted expected | 68.5 ms | 22.8 ms |
| parse floor, worst case (big `private`) | 158.2 ms | 112.5 ms |
| + rename/reassoc/lower/lowerctx/syntax (14.8, not cached) | | |
| **`read.total` floor** median / expected / worst | **62 / 83 / 173 ms** | 16 / 38 / 127 ms |
| **saving off `read.total` 845.4** | **0.783 / 0.762 / 0.672 s** | 0.829 / 0.808 / 0.718 s |
| **round trip 1.676 s →** | **0.893 / 0.914 / 1.004 s** | 0.847 / 0.868 / 0.958 s |
| **reduction** | **47 % / 45 % / 40 %** | 49 % / 48 % / 43 % |

**The number for the roadmap is 0.76 s / 45 %** (conservative design,
byte-weighted expected edit), with a **0.67–0.83 s** band across designs and
edit sites.  The implementer's 0.82 s is the *aggressive* design's *median-edit*
corner and should not be the headline.  Every cell above still clears the 200 ms
pooled gate by **3.4x–4.1x**, and every cell still beats the roadmap's
arithmetic estimate (0.55–0.68 s).  **The precondition — "if 7.0's parse number
is materially smaller the item does not start at all" — is cleared.**

### F4 — one site is not inert  (MINOR)

`Diagnostics.scala:143` is

    Phases.record("index", System.nanoTime - tIdx0)

The argument is evaluated eagerly, so the **shipped** configuration pays one
`System.nanoTime` per check that it did not pay before.  Every other one of the
27 timed sites goes through `Phases.now` (`if (enabled) System.nanoTime else 0L`)
or `Phases.add` (`if (enabled) …`), both of which reduce to one boolean field
read; nothing takes a by-name argument, so no disabled site builds a closure;
`Phases.enabled` is a `val` on an object, so it is a static field load the JIT
hoists.  The cost of the one lapse is ~25 ns against a 1.363 s check, on a line
whose immediate successor already calls `nanoTime` again — **immaterial**, and
`Diagnostics` is LSP-only, so it is not on the strict batch reader's path.  But
the report's §0 says "'off' is one boolean field read per call site — no clock
call", and that sentence is false as written.  Fix: wrap it (`if
(Phases.enabled) Phases.record(…)`) or correct the sentence.

Two smaller notes on the same axis.  `Rpc.receive`'s comment says "the clock
starts on the FIRST header byte"; it actually starts after `readLine()` has
returned the whole first header line, so `rpc.frame` excludes that line's read.
The intent (exclude the block waiting for the client) is served and the number
is if anything conservative, but the comment overstates.  And
`Phases.enabled` is read once at class-init, so the property cannot be flipped
at runtime — correct for a gate, worth stating.

### F5 — the private-block worst case is bigger than the report's framing  (MINOR)

Report.e has 7 `private` blocks (no `database` blocks) totalling **14,591 B =
23.0 % of statement bytes, 18.9 % of the file** and **159.1 ms = 22.3 % of the
591-slice sweep**:

| head | lines | bytes | ms (reviewer) |
|---|---|---|---|
| `private` | 1586–1757 | 10,707 | **104.13** |
| `private` | 1044–1074 | 1,939 | 27.67 |
| `private` | 731–752 | 1,074 | 15.23 |
| `private` | 1148–1154 | 322 | 3.32 |
| `private` | 473–477 | 293 | 4.35 |
| `private` | 395–397 | 142 | 2.69 |
| `private` | 391–393 | 114 | 1.72 |

The largest is one top-level extent spanning **172 lines, 9.8 % of the file**.
7.1b's p100 is therefore 104 ms (111 ms server-scaled), which the report has
right — but its *expected* miss cost is **20.5 ms**, 34x the median it quotes,
and the byte-weighted p90 is the p100.  **Does 7.1b's saving survive edits
landing there?  Yes** — even the p100 leaves 0.67 s of saving and a 1.00 s round
trip (F3).  But an editor session spent inside that block would see the *worst*
row of the table as its steady state, and the report should say so.

### F6 — sublinear, not superlinear  (MINOR)

Section 2.  The brief asked whether superlinearity would change 7.3's ranking;
it is absent (exponent 0.837, R² 0.80), so it does not.

### F7 — compensating errors  (REFUTED, with two small residual biases)

Section 2.  Clock overhead 0.22 %, `Supply` 0.005 %, order 0.3 %.  The two
remaining biases (hoisted slice construction; `atLayoutBoundary` skipping no
trivia on an exhausted slice) both flatter 7.1 and both sit inside the 4.7 %
residual.  The second is the survey's lookahead hazard and this harness cannot
see it.

### F8 — the attribution table mixes bases  (MINOR)

Recomputed from the survey's §0.1 numbers (implied seconds / 0.770 s) against
run C (measured / 845.4 ms), the brief's two rows plus a third:

| row | survey share | reviewer share | factor on SHARE | factor on ABSOLUTE | report says |
|---|---|---|---|---|---|
| parse | 91.4 % (0.70 s) | **98.2 %** (829.84) | **1.07x under** | 1.19x under | 1.07x (share), 1.21x (abs) |
| rename | 0.26 % (2 ms) | **0.60 %** (5.043) | **2.30x under** | 2.52x under | **2.5x** (absolute) |
| extent scan | 7.01 % (54 ms raw) | **0.28 %** (2.357) | **25.1x over** | 22.9x over | **23x** (absolute) |
| extent scan vs P5(a)-corrected ~4.7 ms | — | 2.357 | — | 1.99x over | 2.0x |
| lower (+`lowerctx`) | 1.17 % (9 ms) | 1.07 % (9.069) | 1.09x under | 0.99x | 0.97x |
| reassoc | 0.13 % (1 ms) | 0.08 % (0.677) | 1.62x over | 1.48x over | 1.4x |

Every direction and every order of magnitude in the report is confirmed.  The
presentational defect is that the headline parse factor is a SHARE ratio while
the other four rows are ABSOLUTE ratios; on one consistent basis the numbers
shift by 5–10 % and nothing else changes.  The report's three carried-forward
conclusions all hold: the parse share is honest and if anything the survey was
too kind to the rest; P5(a)'s 3.5x over-attribution precedent does **not** repeat
(the one wild row is a figure the survey had already flagged as superseded);
and `rename + reassoc + lower` is 14.8 ms, not 12 ms, which leaves Decision (b)
untouched (1.8 % of the read, 1.1 % of the check — still smaller than the
machine's own drift).

### F9 — the header is parsed twice, by two different grammars  (INFO)

Confirmed from the code.  `Resident.checkFile` runs
`ModuleParsers.moduleHeader(file.defaultModuleName)` over the whole buffer
(**8.05 ms**) to find the module's siblings before the loader is built;
`NewPipeline.read` then calls `SurfaceParsers.module`, whose first act is
`header(defaultName)` over the same text (**5.82 ms** measured alone in the bench
JVM, ~6.2 ms server-scaled), inside the 829.8 ms `parse`.  So it is ~14 ms of
header parsing per keystroke, not one 8 ms duplicate — and the two are
*different parsers over different grammars* (the `Er` header vs the surface
header), so "pure duplication" overstates it: removing one means making the
surface header serve `Resident`'s sibling-root need, which is a behaviour change.

**Is the 8 ms worth a Stage-4 line?  Not today.**  It is 0.6 % of the check and
one eighth of the between-run drift on the check itself; under GATE-POLICY it
could only be claimed by an interleaved A/B, and an A/B at that size is not worth
its own JVM time.  **After 7.1b it is worth taking**: against a 62–83 ms read
floor, 8 ms is 10–13 %.  Record it as a 7.1b follow-on, not as an item.

### F10 — the property gate tests both directions, non-vacuously  (INFO)

`lsp-client.py`'s two new checks.  Negative: the just-finished shipped run's log
is **303,143 bytes** and contains **0** occurrences of `phases:` — it would
contain many if the default flipped, so the assertion can fail.  Positive: a
second, sequential JVM with `-Dermine.lsp.phases=true` inserted at argv[1] and
its own log file produces **exactly 1** `phases:` line, matched by a regex that
requires both `parse=` and `check.total=`.  Output reaches the **LSP log only**:
`Diagnostics.run` calls the server's `log`, never `println`, and the positive
run's JSON-RPC framing survived intact, which is the direct evidence that nothing
reached stdout (Decision 4).  The two JVMs are strictly sequential (the first is
`wait()`ed).  Nit: `$LOG.phases` is created and never removed.

### F11 — the 7.2 cliff  (INFO)

Reproduced once, one server, load 1.02, the implementer's `cliff.py`:

| round | read s | typecheck s | reused | round trip |
|---|---|---|---|---|
| `didOpen` (cold) | 0.95 | 1.14 | **0 of 154** | 2.210 s |
| in-body edits 1–6 | 0.91–0.93 | 0.50–0.57 | 97 of 154 | 1.742–1.832 s |
| **one blank line at the top** | 0.91 | **1.06** | **0 of 154** | **2.293 s** |
| in-body, shifted (×2) | 0.89–0.92 | 0.51–0.56 | 97 of 154 | 1.757–1.785 s |

**+0.51 s of inference and +0.51 s of round trip (2.293 vs ~1.78 s, a 29 %
regression) for an edit that changed nothing**, and it is indistinguishable from
a cold open.  Recovery is immediate.  The roadmap's code-derived prediction (0 of
154) is exact; its "~0.5 s" is exact as the delta.  This matches the
implementer's §7 to within noise.

### F12 — the Rpc addendum  (INFO)

`Rpc.scala`'s diff is **timer-only**: `receive()` gains `Phases.now/add/count`
around the frame read and the log clip; `handle` gains `val parsed =
Json.parse(text)` with the existing match moved onto it plus the closing brace.
`Json.P`, `string()` and the scanner are untouched — the run-based variant lives
only in the implementer's scratch.  The measured 1.24x (355 → 286 µs) against the
survey's claimed 5x, and the 69 µs it would buy against a 1.68 s round trip
(0.004 %), make Decision (d)'s "do nothing" correct, now on an in-process number.
The recorded trap — `scala.collection.mutable.StringBuilder.append(cs, a, b)` is
(offset, **length**), not (start, end) — is worth its paragraph.  The reviewer
did not re-run the JSON microbenchmark: the decision does not turn on it, and it
would have cost a JVM to confirm a number that is four orders of magnitude below
the noise floor either way.

### F13 — the strict path  (INFO)

`NewPipeline.read`'s six timer pairs are `val tX = Phases.now` (returns `0L`,
no side effect) and `Phases.add(name, tX)` (returns `Unit`, no side effect).  No
control flow, no declaration order, no expression value changed;
`Phases.add("parse", tParse)` sits *after* the match, so a header/parse failure
still throws `Death` at the same point with the same message.  `readModule` is
`read(…, tolerant = false)` over the same traversal.  The property is set by
nothing in `bin/ermine`, `Console`, `sbt`, `corpus-run.sh`, `repl-smoke.sh` or
any test.  `Session.scala` has an empty diff; `git diff --stat` and
`git diff --stat -w` are identical (7 files, 127 insertions, 8 deletions).  The
evidence rather than the argument: `TestLoopTrace` 720/720, corpus 85/69/0,
REPL goldens byte-unmodified, `lsp-smoke` 456.

The reviewer notes and endorses the deliberate non-reindentation of
`checkFile`'s body under its new brace: a 230-line whitespace reflow would have
made `--stat` == `--stat -w` meaningless as a gate.

---

## 4. GATES (Tier 0), reviewer's run, each ONCE

| gate | required | reviewer result |
|---|---|---|
| `sbt core/compile core/copyResources` | green | **green** |
| `sbt 'core/testOnly *TestLoopTrace'` | 720/720 | **720 segments, 720 agree, 0 hashdiff, 0 eqdiff, 0 skipped, 0 nonpart, fuel 0; 3 of 3 properties proved** |
| `corpus-run.sh --batch` | 85 / 69 / 0 over 154 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** (one JVM, exit 0) |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` **empty** |
| `lsp-smoke.sh` | 456 | **456**, and both new checks verified non-vacuous (F10) |
| boot | 129 modules | **129** (12.71 s and 12.81 s across the two server runs) |
| `.ei` droppings | 0 | **0** — 143 `.ei` in the tree, every one tracked (`git ls-files` clean), count and mtimes unchanged |
| `git diff --stat` == `--stat -w` | identical | **identical** |
| strict path `Session.scala` | unchanged | **not in `git status`** |
| working tree | only the item's deliverables | **confirmed** (plus this report and a 7.2 brief written by the orchestrator) |
| lingering JVMs / polling shells | none | **none** at exit |

Tier 1 was not needed and not run: nothing in `scalaparsers`, `Subst.scala` or
`Type.scala` was touched.  The reviewer agrees with §2(d)'s **UNSEPARABLE**
disposition for layout/vsemi: `semi` runs per token, a `nanoTime` pair inside it
would cost more than what it measures, and a `scalaparsers` edit is Tier 1 by
the Stage-4 invariants.  The reviewer's decomposed residual (F2) is the best
Tier-0 answer available for that phase and should be recorded as such.

---

## 5. THE VERDICT

### On the item: FIX-THEN-ADVANCE

The instrumentation is well built, the table reconciles to 0.03 % on an
independent run, the shares reproduce to the third digit, the cliff reproduces
exactly, the strict path is untouched and the gate is pinned in both directions.
Three corrections must be made **before these numbers enter the roadmap**:

1. **F1** — strike "all 591 statements parse alone (591 of 591)" and the
   inference that the slice-vs-whole divergence "does not bite".  Replace with
   "529 of 591 extents are real statements; the other 62 are the module
   header's `import`/`export` lines, which `statementAlts` has no alternative
   for and which the whole-file parse consumes inside `header`.  The
   slice-vs-whole divergence is NOT tested by this harness."  Note that 7.1b's
   reuse unit is 529 + 62, not 591.
2. **F2** — the ratio is **0.95**; the residual is **42.6 ms / 5.5 %**
   decomposed, **36 ms / 4.7 %** raw, and it enters the roadmap as a band.
3. **F3** — the saving is **~0.76 s / 45 %** (band 0.67–0.83 s), and the floor
   arithmetic must pick a cache design and drop the header double-count.

**F4** is a one-line code fix or a one-sentence report fix; either is fine.
Nothing else blocks.  None of the three corrections changes the direction, which
is why this is FIX-THEN-ADVANCE and not BLOCK.

### On the stage: AGREE 7.1, at 0.76 s

Both of 7.1's conditions hold on the reviewer's numbers and neither is marginal:
per-statement work is **95 %** of the whole-file parse, and the parse is
**98.2 %** of the read.  Per-statement parse work is
0.953 × 0.982 × 0.620 = **58.0 % of the check** and **47.1 % of the round trip**
(implementer: 58.5 % / 47.8 %).

**The strongest case AGAINST 7.1, stated at full strength.**  It is not the
residual and it is not the drift; those were tested and are too small.  It is
that **7.3 subsumes 7.1**.  The survey says so itself in §5(a′): if the parser's
constant factor falls even **10x** — a fifth of the 48–52x §1.11 cites — the
whole-file parse goes 830 → 83 ms, the read to ~98 ms and the round trip to
~0.93 s, which is *the same place 7.1b's conservative floor lands* (0.89–1.00 s),
with **no cache, no span arithmetic, no high-water-mark soundness obligation, no
180-file splice differential, no GC-rooting of surface trees, and no 62-extent
header special case** — and it also takes the 12.7 s boot and every batch and
REPL path with it, which 7.1b cannot touch.  7.1b's win is capped twice, by a
residual it cannot remove (46 ms server-scaled) and by a per-miss cost that
reaches 112 ms one edit in seven; 7.3's is not capped at all.

Note also that the report's stated reason for de-ranking 7.3 — "0.60 ms of miss
is not a cost worth an architectural rewrite of the parser library" — is a
**non-sequitur**: 7.3 does not attack the 0.60 ms miss, it attacks the 830 ms
whole-file parse that 7.1b exists to avoid.  The right argument is the one the
report makes only in passing.

**Why that case loses anyway: risk, not arithmetic.**  7.3 is Tier 1 inside
`scalaparsers`, behind the 180-file differential, `ei-diff.sh --batch` on both
sides, `g1-validate.sh` and byte-exact REPL goldens.  This project already has a
reverted precedent for the localized version of it (P5(d), abandoned at 43 ms).
And the 48–52x is **tree-sitter-haskell's** number in a different system, not a
projection of a de-trampolined `scalaparsers`; nothing in the measured table
bounds 7.3's actual delivery.  7.1b is editor-path-only, its win is measurable
today at 0.67–0.78 s, and 3.4x–4.1x the 200 ms pooled gate.  **7.1 first.**

Two things the roadmap should record alongside the ranking, which the item does
not say:

* **7.3 and 7.1b must not both be budgeted as savings.**  If 7.3 lands, 7.1b's
  editor win largely evaporates; the roadmap must treat them as alternatives on
  the editor path and 7.3 as additive only on the batch/boot path.
* **7.3's re-ranking to the batch target is right and is stronger than stated.**
  A cold 129-module load parses every file exactly once and has no cache to hit;
  boot is 12.7 s, which is 7.5x the whole editor round trip.  That is where
  10.9 µs/byte is unamortisable, and it should be ranked there against P5(c).

**7.2 lands first: agreed, unchanged.**  It is independent of the 7.1/7.3
choice; its cliff is now measured on both sides at **+0.51 s of inference and
+0.51 s of round trip, a 29 % regression on an edit that changed nothing**; and
7.1b needs the span arithmetic regardless, because a cached surface tree carries
`Span`s and an insert above shifts every one of them.

---

## 6. Reviewer's artefacts

Scratch only, `<scratch>/review-7.0/` — nothing added to the tree:

| file | what |
|---|---|
| `runC.log` / `runC.table` / `runC.json` | the phase table, 70 rounds, property on |
| `runOff.log` / `runOff.json` | the shipped configuration, 40 rounds, property off |
| `RevBench.scala` | reproduction + validity audit + per-extent CSV + `Supply` and wall-clock controls |
| `OrderBench.scala` | five measurement orders in one JVM; `header` alone; real-statements-only sweep |
| `Audit.scala` | the `statementFailure` audit of all 591 extents |
| `revbench.txt`, `orderbench.txt`, `extents.csv`, `audit.csv` | raw outputs |
| `cliff.log` / `cliff.json` | the 7.2 cliff reproduction |
| `corpus/` | 154 batch outputs, 85/69/0 |

The three numbers a later item should quote from this review rather than from
the item's report: **ratio 0.95**, **driver residual 42.6 ms / 5.5 %**,
**7.1b saving 0.76 s (band 0.67–0.83 s)**.

STOPPED after this report, per the brief.
