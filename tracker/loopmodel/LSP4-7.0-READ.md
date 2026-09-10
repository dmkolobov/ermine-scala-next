# LSP Stage 4, item 7.0 — DIRECT MEASUREMENT of the read's phases

OUTCOME: **GREEN**, after a FIX ROUND against the independent review
(`tracker/loopmodel/LSP4-7.0-REVIEW.md`, verdict FIX-THEN-ADVANCE).  Every phase
in the item's list is measured except (d), layout/vsemi inside the whole-file
parse, which is UNSEPARABLE at Tier 0 with its reason.  The verdict is stated
with its arithmetic, at the reviewer's corrected number.

Branch `scala3-migration`.  Tier 0 only.  No behaviour change, no default flip,
no strict-path change, no commit.

> ### FIX ROUND, 2026-09-10 — what changed after the review
>
> | id | severity | disposition |
> |---|---|---|
> | **F1** | MAJOR | **FIXED, and re-measured.**  "All 591 statements parse alone" was FALSE and the check was vacuous.  §4.3 replaces it with a non-vacuous audit: **529 real statements + 62 header extents**, and the slice-vs-whole divergence is now MEASURED for the first time — **15 of 529 (2.8 %)**. |
> | **F2** | MODERATE | **FIXED.**  The ratio is **0.95**, not 0.963; the residual is **42.6–43.3 ms / 5.5–5.7 %** decomposed (header subtracted, sweep restricted to real statements) and 31.6–36.3 ms / 4.2–4.7 % raw.  Re-derived independently; §4.4–4.5, reported as a band. |
> | **F3** | MODERATE | **FIXED.**  The "38 ms → 0.88 s" floor is withdrawn.  §8 now carries the reviewer's corrected floors — miss **62 / 83 / 173 ms**, saving **0.783 / 0.762 / 0.672 s**, round trip **0.89 / 0.91 / 1.00 s** — headline **0.76 s / 45 %**, band 0.67–0.83 s. |
> | **F4** | MINOR | **FIXED IN CODE (one line).**  `Diagnostics.scala` evaluated `System.nanoTime` eagerly with the property off; it now goes through the guarded `Phases.add`.  The one other eager site (`read.total`, a subtraction of two clock values the shipped code already took) is wrapped too, so "off is one boolean field read per call site" is now true as written. |
> | **F5** | MINOR | **ADDED.**  §4.6: private/database blocks are **18.9 % of the file's bytes**; one edit in seven lands in the 98–104 ms block. |
> | **F6** | MINOR | **ADDED.**  §4.7: the per-statement parse is **SUBLINEAR** (ms ∝ bytes^0.829, R² 0.81).  7.3's ranking is unaffected on that axis. |
> | **F7** | MINOR | REFUTED by the reviewer (clock overhead 0.22 %, `Supply` 0.005 %, order 0.3 %); recorded in §4.5, including the two residual biases that flatter 7.1. |
> | **F8** | MINOR | **FIXED.**  §5 is recomputed on ONE declared base (share of the read), with absolutes as a clearly secondary column. |
> | **F9** | INFO | **CORRECTED.**  §5.2: the header is parsed twice by **two different grammars** (8.05–8.21 ms + 5.82–6.19 ms); not a Stage-4 line today, worth 10–13 % of the read after 7.1b. |
>
> Also added to §8, at the review's request, so the orchestrator can carry them
> into the roadmap: the strongest case AGAINST 7.1 and why it loses; and the two
> roadmap notes (7.1b and 7.3 must not both be budgeted as editor savings; 7.3's
> re-ranking to the batch target is stronger than this report first stated).
>
> **Whose numbers are of record.**  GATE-POLICY: the reviewer's.  Where the
> reviewer re-measured (run C, the ratio, the residual, the floors, the cliff),
> the reviewer's figure is the one quoted and this item's is shown beside it.
> Where the reviewer did not (the F1 audit — the review established the 62 and
> asked for the divergence count), the re-run in §4.3 is this item's, on the
> reviewer's protocol.

---

## 0. What was built, and what ships

`core/src/main/scala/com/clarifi/reporting/ermine/session/Phases.scala` (new):
`System.nanoTime` around each phase, accumulated by name, rendered as one line
per check.  **OFF unless `-Dermine.lsp.phases=true`**, and "off" is **one boolean
field read per call site** — no clock call, no allocation (nothing takes a
by-name argument, so a disabled site does not even build a closure), no map
touched.  `Phases.enabled` is a `val` on an object, i.e. a static field load the
JIT hoists; the property therefore cannot be flipped at runtime, which is what a
gate wants.  The line goes to the **LSP log**, never to stdout (roadmap
Decision 4: stdout is the protocol channel).

> **F4.**  As first written that sentence was false at one of the 27 sites:
> `Diagnostics.check` had `Phases.record("index", System.nanoTime - tIdx0)`,
> whose argument is evaluated eagerly — one `nanoTime` (~25 ns) per check in the
> shipped configuration.  It is now `Phases.add("index", tIdx0)`, which is
> `if (enabled) …`.  The only other site passing a computed value,
> `Phases.record("read.total", tRead - tRead0)` in `Resident`, is now wrapped in
> `if (Phases.enabled)`; it never called the clock (both operands are clock
> values the shipped log line already took), but wrapping it makes the claim
> exactly true rather than approximately true.

**IT SHIPS, behind the property.**  Reason: every later Stage-4 item is required
to state its saving as a fraction of this table (the Stage-4 invariant "NO NEW
BUDGET FOR THE READ WITHOUT 7.0"), and a reviewer, 7.1b and 7.4 all need to
re-cut the table with one flag rather than re-deriving the instrumentation.  The
review measured the shipped configuration directly: property OFF, 40 rounds,
round trip **1.683 s** against the property-ON run's 1.676 s, and **0 `phases:`
lines in a 303 KB log**.

Two lsp-smoke checks pin the gate in BOTH directions, and the review confirmed
both are non-vacuous (F10): the shipped run's log contains **0** `phases:` lines
(it would contain many if the default flipped), and a second, strictly
sequential JVM with the property produces **exactly 1**, matched by a regex
requiring both `parse=` and `check.total=`.  lsp-smoke 454 → **456**.

The `Rpc` run-based scanner (7.0.5) **does not ship** — see §6.

Timed sites, all additive and all inert when off:

| file | timers |
|---|---|
| `lsp/Rpc.scala` | `rpc.frame` (header + body bytes + UTF-8 decode), `rpc.log`, `rpc.json`, `rpc.bytes` |
| `lsp/Resident.scala` | `envcopy`, `header`, `scrub`, `imports`, `read.total`, `notes.pre`, `keys.total`, `checkWith`, `notes.post`; `Phases.reset()` at the end of `boot()` |
| `rename/NewPipeline.scala` | `parse`, `syntax`, `rename`, `reassoc`, `lowerctx`, `lower` |
| `session/TolerantCheck.scala` | `extents.scan`, `extents.offsets` |
| `lsp/Definitions.scala` | `index.symbols` |
| `lsp/Diagnostics.scala` | `index`, `check.total`, the emit + reset |

`boot()` resets because boot reads 129 modules through the same
`NewPipeline.read`: without it the FIRST check's line carried the whole boot's
parse (`parse=11058 ms` against `read.total=950 ms` in the first draft).

---

## 1. Protocol

P5(a)'s protocol: **50 measured reps after 20 warm-up reps**, medians AND spread
(min / p10 / p90 / max), 1-minute load average **< 1.3 at the start of every
measured run**, waited for and recorded.  The driver is the scripted client of
record, `tracker/tools/perf-client.py` (the `perf-bench.sh editor` shape: real
`didChange` → `publishDiagnostics` round trips through the real server), run with
`--rounds 70`; row 0 is the `didOpen` and rows 1..20 are the warm-ups, so rows
**21..70** are the 50 measured reps.

`perf-bench.sh` itself could not be used as the wrapper: its preflight
`pgrep -f 'sbt-launch|xsbt\.boot'` matched an unrelated orchestrator shell whose
command line merely NAMES those strings, so it refused every run.  The harness
was not modified; `perf-client.py` was invoked directly with the same JVM flags
perf-bench passes, and the preflight this item actually needs — one JVM, load
under 1.3, a current build — was done by hand and is recorded per run.

Runs: **A** and **B** are this item's (B carries `index.symbols`); **C** is the
reviewer's, and **C is the run of record for the trackers**.

---

## 2. THE PHASE TABLE — `Layout/Report.e` (1757 lines, 77,385 bytes)

Reviewer run **C** (load **0.97** at start; round trip median **1.676 s** = read
0.850 + typecheck 0.510 + debounce 0.300 + residual 0.024; spread 1.617–1.862 s;
reused 97/154 every round; cold `didOpen` 2.197 s; boot 12.81 s / 129 modules)
beside this item's run **B** (load **0.88**; round trip **1.698 s** = 0.860 +
0.510 + 0.300 + 0.026; spread 1.627–2.048 s; reused 97/154; boot 13.15 s).

All figures in **milliseconds**; spread columns are run C's.

| # | phase | **C (of record)** | min | p10 | p90 | max | share of check | B | C/B |
|---|---|---|---|---|---|---|---|---|---|
| — | `rpc.frame` (79,628 B) | 0.081 | 0.055 | 0.056 | 0.129 | 0.155 | 0.006 % | 0.067 | 1.21 |
| — | `rpc.log` | 0.035 | 0.017 | 0.022 | 0.047 | 0.102 | 0.003 % | 0.036 | 0.97 |
| — | `rpc.json` | **0.307** | 0.295 | 0.298 | 0.467 | 0.552 | 0.023 % | 0.306 | 1.00 |
| h | `envcopy` | 0.009 | 0.008 | 0.008 | 0.011 | 0.014 | 0.001 % | 0.009 | 1.00 |
| a | `header` (`ModuleParsers.moduleHeader`) | **8.053** | 7.392 | 7.603 | 11.261 | 13.474 | 0.59 % | 8.210 | 0.98 |
| h | `scrub` | 2.058 | 1.960 | 1.987 | 2.161 | 2.514 | 0.15 % | 1.961 | 1.05 |
| — | `imports` | 0.039 | 0.036 | 0.037 | 0.046 | 0.052 | 0.003 % | 0.039 | 1.00 |
| **c** | **`parse` (`SurfaceParsers.module`)** | **829.841** | 799.298 | 814.813 | 849.082 | 862.577 | **60.9 %** | 843.553 | 0.98 |
| — | `syntax` | 0.036 | 0.030 | 0.032 | 0.045 | 0.082 | 0.003 % | 0.037 | 0.97 |
| e | `rename` | **5.043** | 4.381 | 4.613 | 5.469 | 7.858 | 0.37 % | 5.020 | 1.00 |
| f | `reassoc` | **0.677** | 0.468 | 0.597 | 0.875 | 1.269 | 0.05 % | 0.716 | 0.95 |
| g | `lowerctx` | 3.993 | 3.593 | 3.747 | 4.552 | 8.578 | 0.29 % | 4.087 | 0.98 |
| g | `lower` (`assemble`) | **5.076** | 4.463 | 4.689 | 5.539 | 7.759 | 0.37 % | 5.165 | 0.98 |
| | **`read.total`** | **845.371** | 814.032 | 829.085 | 864.993 | 878.959 | **62.0 %** | 859.629 | 0.98 |
| — | `notes.pre` | 0.080 | 0.073 | 0.075 | 0.094 | 0.128 | 0.006 % | 0.082 | 0.98 |
| b | `extents.scan` | **0.806** | 0.795 | 0.800 | 0.912 | 1.619 | 0.06 % | 0.736 | 1.10 |
| b | `extents.offsets` | **1.551** | 1.529 | 1.532 | 1.981 | 2.713 | 0.11 % | 1.585 | 0.98 |
| h | `keys.total` | 3.272 | 3.140 | 3.177 | 3.985 | 4.893 | 0.24 % | 3.229 | 1.01 |
| **i** | **`checkWith` (the typecheck)** | **492.377** | 447.938 | 465.886 | 522.818 | 567.889 | **36.1 %** | 496.440 | 0.99 |
| — | `notes.post` | 0.048 | 0.042 | 0.045 | 0.058 | 0.084 | 0.004 % | 0.046 | 1.04 |
| h | ` └ index.symbols` (inside `index`) | 0.417 | 0.356 | 0.389 | 0.492 | 0.806 | 0.03 % | 0.434 | 0.96 |
| h | `index` (`Definitions.index`) | **9.953** | 9.467 | 9.540 | 10.860 | 14.635 | 0.73 % | 10.116 | 0.98 |
| | **`check.total`** | **1362.990** | 1314.057 | 1323.553 | 1406.981 | 1451.562 | 100 % | 1388.037 | 0.98 |

**Every row reproduces within 5 %** except two whose absolute size makes them
noise (`rpc.frame`, a 14 µs difference on an 81 µs row; `extents.scan`, 0.07 ms).
Shares are confirmed to the third digit: parse **98.2 % of the read**, **60.9 %
of the check**; read **62.0 % of the check**, **50.7 % of the round trip**.

This item's own A/B pair (run A at load 0.90: parse 912.05, read 928.31,
checkWith 539.53, check.total 1493.05) sits 8 % above B on every compute phase.
The review's five-orderings-in-one-JVM experiment (§4.5) settles what that is:
**the 8 % is BETWEEN-JVM drift, not within-JVM noise** — inside one JVM the same
quantities agree to 0.3 %.  It is still larger than every phase in the table
except `parse` and `checkWith` put together, so any later item claiming less than
~80 ms must be an interleaved A/B or it is claiming the weather.

### RECONCILIATION (7.0.1's requirement)

Medians do not add, so the reconciliation is computed **per round** and its
median taken:

| | run A | run B | **run C (reviewer)** |
|---|---|---|---|
| read parts vs `read.total` | +0.038 ms (+0.004 %) | +0.036 ms (+0.004 %) | **+0.035 ms (+0.004 %)** |
| top-level parts vs `check.total` | +0.378 ms (+0.025 %) | +0.361 ms (+0.026 %) | **+0.359 ms (+0.027 %)** |

The table accounts for **99.97 %** of the check by construction, on two
independent runs.  The unaccounted 0.36 ms is named: the code BETWEEN the timed
blocks in `Resident.checkFile` — the module-root walk and the
`SourceFile.inOrder` loader-chain construction, plus the `Checked` construction
and the `docs.putCache`/`putIndex` stores.

### (d) LAYOUT / VSEMI — **UNSEPARABLE at Tier 0** (the reviewer concurs)

`semi`, `laidout`, `offside`, `virtualLeftBrace`/`virtualRightBrace` and the
`IndentedLayout` stack all live in `parsers/src/main/scala/scalaparsers/`.  The
Stage-4 invariants make **any** change inside `scalaparsers` **Tier 1**, and this
item is Tier 0 by its own terms; separately, `semi` runs per token, so a
`nanoTime` pair inside it would cost more than the thing it measures.  The best
Tier-0 answer available for that phase is the DECOMPOSED RESIDUAL in §4.5
(**42.6–43.3 ms, 5.5–5.7 % of the whole-file parse**), and it should be recorded
as such.

---

## 3. THE PHASE TABLE — small file (`Control/Monad/Reader.e`, 44 lines, 1,148 B)

Load **0.94** at start.  Same 70-round protocol, rows 21..70, `--mode space` edit
on line 43.  Round trip **0.333 s**.  `didChange` frame 1,397 bytes.

| phase | median ms | min | p10 | p90 | max |
|---|---|---|---|---|---|
| `rpc.frame` | 0.012 | 0.010 | 0.011 | 0.017 | 0.032 |
| `rpc.json` | 0.062 | 0.027 | 0.029 | 0.090 | 0.158 |
| `envcopy` | 0.008 | 0.008 | 0.008 | 0.010 | 0.016 |
| `header` | 0.710 | 0.628 | 0.644 | 0.972 | 1.221 |
| `scrub` | 0.002 | 0.001 | 0.001 | 0.002 | 0.010 |
| `imports` | 0.018 | 0.016 | 0.016 | 0.022 | 0.025 |
| **`parse`** | **19.151** | 17.645 | 17.892 | 21.715 | 25.138 |
| `rename` | 2.639 | 2.400 | 2.427 | 3.128 | 4.327 |
| `reassoc` | 0.173 | 0.154 | 0.157 | 0.253 | 0.287 |
| `lowerctx` | 0.115 | 0.101 | 0.111 | 0.153 | 0.177 |
| `lower` | 0.326 | 0.249 | 0.261 | 0.386 | 0.448 |
| **`read.total`** | **22.695** | 20.671 | 21.136 | 25.225 | 29.649 |
| `extents.scan` + `.offsets` | 0.098 | — | — | — | — |
| `keys.total` | 0.282 | 0.243 | 0.255 | 0.356 | 0.478 |
| **`checkWith`** | **6.065** | 5.733 | 5.839 | 6.891 | 10.051 |
| `index` | 0.636 | 0.469 | 0.511 | 0.871 | 1.115 |
| **`check.total`** | **30.670** | 28.528 | 29.031 | 34.259 | 42.695 |

Per-round reconciliation: read +0.022 ms (+0.098 %), check +0.249 ms (+0.806 %).

Note on the driver: `perf-client.py` exited non-zero on this file because it
asserts `reused > 0`, and a 44-line module has **one** inference component, which
the edit invalidates (`reused 0 of 1` every round).  That assertion is about the
INFERENCE cache and is inapplicable at this size; all 70 rounds ran and all 71
phase lines were emitted, which is what the small file is measured for.

WHAT THE SMALL FILE SHOWS.

1. **The fixed costs are tiny and not where anyone looked.**  Env copy 8 µs,
   scrub 2 µs (this module is not in the resident closure), import step 18 µs,
   `keys` 0.28 ms, index 0.64 ms.  30.7 ms of check for a 44-line file is 62 %
   parse and 20 % inference.
2. **The debounce is 90 % of the small-file round trip** — 0.333 s of wall clock
   for 30.7 ms of work.  That is Decision (e)'s whole case, measured, and a
   bigger *relative* prize than anything 7.1 wins on Report.e.  It stays gated
   on 7.1/7.3 per Decision (e); the number is now on record.
3. **The parser's cost is per character, not per file.**  10.75 µs/B aggregate on
   Report.e, 16.7 µs/B on Reader.e — same order, no fixed-cost cliff at the file
   level.  There IS a per-statement fixed cost (§4.7).

---

## 4. THE SINGLE-STATEMENT NUMBER (7.0.3) — the one that ranks 7.1 against 7.3

JVM-local harnesses, **scratch only**, never added to `core/src`:
`StmtBench.scala` (the original) and `SliceAudit.scala` (the fix round's
non-vacuous audit + the re-derived residual), compiled against the build's own
classpath with the project's `scala3-compiler` 3.3.8.  Both build exactly the
repositioned `ParseState` that `SurfaceParsers.statementFailure` builds —
`Pos(fileName, firstLine, startLine, startCol, false)`, `input` = the slice from
the statement's line start to the extent end, `offset` = start − lineStart,
`layoutStack = List(IndentedLayout(startCol,"statement"),
IndentedLayout(1,"top level"))`, `bol = false` — and run
`SurfaceParsers.statement` on it.  20 warm-ups / 50 reps; `SliceAudit` ran at
load **0.77**.

### 4.1 What Report.e actually contains

| | survey §5(a) (ARITHMETIC) | MEASURED |
|---|---|---|
| top-level statements | "~315" | **591 extents = 529 real statements + 62 header extents** |
| mean bytes each | "~245" | **110.7** (median **50**; extent text 65,421 B) |

575 extents carry a head word and there are **294 distinct head words** — which
is almost certainly where "~315" came from, and it is the wrong unit: it is the
grouping `TolerantCheck.keys` uses for INFERENCE, not what a surface cache
reuses.  `TolerantCheck` reports 154 inference components.

### 4.2 The numbers (implementer's `StmtBench`, load 0.99; reviewer beside)

| measurement | impl | reviewer |
|---|---|---|
| per-statement median (over the real statements) | **0.648** | 0.614 |
| per-statement mean | 1.288 | 1.226 |
| per-statement p90 | 2.293 | 2.300 |
| per-statement max (the big `private` block) | **98.512** | 104.13 |
| whole file, `SurfaceParsers.module`, same JVM | 756.91 | 772.4 |
| `StatementExtents.scan` alone | 1.10 | 1.07 |
| `SurfaceParsers.header` alone | **6.189** | 5.82 |

The representative extent nearest the survey's 245-byte figure is
**`makeSelectorsLateBinding`, Report.e lines 916–919, 245 bytes** — 3.97 ms in
the original sweep.  It is **4.9x the file's MEDIAN extent (50 B)** and 6.1x its
median cost, which is why the brief's literal form of the ratio (591 × one
representative statement / whole-file) comes out ≫ 1.  That is the mean-vs-median
trap, not a broken measurement; the aggregate form is §4.4.

### 4.3 **F1 — the slice-vs-whole divergence, MEASURED (it was UNTESTED until now)**

The original report claimed "**All 591 statements parse alone (591 of 591)**" and
inferred that the divergence `statementFailure`'s docstring records "does not
bite".  **Both sentences were wrong, and the check behind them could not fail.**
`SurfaceParsers.statement` is

    optionalSpace.skipOptional >> ((statementAlts(bindingStatement) << atLayoutBoundary).attempt | rawStatement)

and `rawStatement` is a **total** per-character offside scan that always succeeds
on well-formed layout, yielding an `SErrorStatement`.  So `.run(...).isRight` is
true whether the statement parsed or every real alternative fell through.

`SliceAudit` replaces it with the only oracle that can fail: **compare the slice
parse's TREE against the tree the whole-file parse produced for the same
extent** — same statement KIND, then structural equality.

    extents                                                   591
      rawStatement FALLBACKS                                   62   (head 'import' 60, head 'export' 2)
      real statements                                         529
        agree with the whole-file tree, STRUCTURALLY          514
        same kind, DIFFERENT STRUCTURE                         15   (top-level span differs: 15; span equal, tree differs: 0)
        DIFFERENT KIND                                          0
        no whole-file statement at that start                   0

**The 62.**  Exactly the **60 `import` + 2 `export`** header lines, matching the
reviewer to the unit.  `statementAlts` has no import or export alternative
because in a whole-file parse those are consumed by `SurfaceParsers.header`, not
by the statement driver; `StatementExtents.scan` is a lexical splitter and does
not know that.  **7.1b's reuse unit is therefore 529 statements PLUS 62 header
extents, not 591** — a cache keyed on extents alone would store 62
`SErrorStatement`s and hand them to rename.  The header must be keyed
separately, or the extent list must be split at the first non-header extent.

**The 15 — and this is the finding, because nothing had ever tested it.**  All
15 are KIND-identical and differ **only in the statement's own top-level `Span`
end**, in one direction: the whole-file parse's span runs on to the start of the
NEXT statement, the slice's stops at the extent end.

| head | lines | slice span | whole-file span |
|---|---|---|---|
| `foreign` | 152–153 | 152:1–**153:106** | 152:1–**156:1** |
| `private` | 391–393 | 391:1–393:43 | 391:1–395:1 |
| `private` | 395–397 | 395:1–397:81 | 395:1–399:1 |
| `private` | 473–477 | 473:1–477:73 | 473:1–479:1 |
| `softRelation` | 642–643 | 642:1–643:67 | 642:1–647:1 |
| `private` | 731–752 | 731:1–752:61 | 731:1–754:1 |
| `pivotTabular` | 770–779 | 770:1–779:36 | 770:1–781:1 |
| `drilldownPivotTabular` | 781–791 | 781:1–791:36 | 781:1–794:1 |
| `sequenceSelector` | 908–910 | 908:1–910:31 | 908:1–912:1 |
| `makeSelectorsLateBinding` | 916–919 | 916:1–919:93 | 916:1–921:1 |
| `makeSelectors` | 924–927 | 924:1–927:33 | 924:1–929:1 |
| `private` | 1044–1074 | 1044:1–1074:135 | 1044:1–1076:1 |
| `scaled` | 1110–1111 | 1110:1–1111:55 | 1110:1–1113:1 |
| `private` | 1148–1154 | 1148:1–1154:42 | 1148:1–1157:1 |
| `private` | 1586–1757 | 1586:1–1757:86 | 1586:1–**1758:1** |

That is **`atLayoutBoundary` consuming trailing trivia**, made visible: in the
file, `statement` runs `StatementExtents.skipTrivia` over the comment/blank-line
run AFTER the extent and the span absorbs it; on a slice the input is exhausted
and it skips nothing.  It is the survey's §5(a) lookahead hazard, and the review
was right that the timing harness is structurally blind to it — but the TREE
harness is not, and it is **2.8 % of the real statements (15 of 529)**.

WHAT THIS MEANS FOR 7.1b, stated plainly:

* **The 7.1b differential would FAIL on 15 of 529 statements today**, not because
  the parse is wrong but because a spliced tree carries an extent-tight end span
  where a fresh whole-file parse carries a next-statement-start end span.  7.1b
  must either re-derive the top-level end span at splice time (it can: the next
  extent's start is right there in the scan) or its differential must normalise
  it — and *saying which* is part of the item, because the same `Span` is what
  the editor reports for a document symbol's range.
* **`atLayoutBoundary` is the high-water mark's reason for existing**, and this is
  the first direct evidence of it in this codebase: 15 statements demonstrably
  examine input past their own extent.  7.1a's `examinedLength` is not
  speculative.
* **What is NOT shown:** no kind divergence, no deep tree divergence, and no case
  where the slice SUCCEEDS on something the splitter rejected (Report.e has no
  broken statements).  `statementFailure`'s docstring divergence remains
  untested for BROKEN files, and the survey's 180-file multi-edit differential
  remains **entirely unaddressed** and must not be treated as partly discharged
  by this item.

### 4.4 THE RATIO — **0.95**

Two independent measurements, one JVM each, 20/50:

| | sweep | whole | **RATIO** |
|---|---|---|---|
| reviewer (of record), all 591 | 736.2 | 772.4 | **0.953** |
| reviewer, five orderings in one JVM | — | — | **0.9513–0.9543** |
| implementer re-run (`SliceAudit`), all 591 | 725.35 | 756.91 | **0.958** |
| implementer re-run, the 529 real statements only | 707.42 | 756.91 | 0.935 |

**RATIO = 0.95** (the original report's 0.963 was the optimistic edge).  The
0.3 % band across five orderings inside one JVM refutes order/JIT as an
explanation for anything; what is *not* stable is the absolute whole-file number
(752–830 ms across JVMs, 10 %), and the ratio is a within-JVM quantity.

**The conclusion is unchanged and is not close:** ~95 % of the whole-file parse is
reproduced by parsing each statement in isolation.  The parse cost IS
per-statement work.

### 4.5 THE RESIDUAL — a band, decomposed

The number that matters is the complement — what a cache cannot remove:

    RAW        whole − sweep(591)                 reviewer 36.3 ms (4.7 %)   impl 31.6 ms (4.2 %)
    DECOMPOSED whole − header − sweep(529 real)   reviewer 42.6 ms (5.5 %)   impl 43.3 ms (5.7 %)

    impl:     756.91 − 6.19 − 707.42 = 43.30 ms
    reviewer: 773.85 − 5.82 − 725.39 = 42.64 ms

**It enters the roadmap as 42.6–43.3 ms / 5.5–5.7 % decomposed, 32–36 ms /
4.2–4.7 % raw — a band, not a point**, because it is a small difference of two
large numbers whose absolutes move 3–10 % between JVMs.  It is the header parse
inside `module()`, the `statement.attempt.scope("statement").sepEndBy(semi)
.between(virtualLeftBrace, virtualRightBrace)` driver, `atLayoutBoundary`'s
trivia skipping, and the layout stack's bookkeeping.  It cannot be cut finer at
Tier 0 (§2(d)).

**Compensating errors: tested and dead** (reviewer, F7).  The 591 `nanoTime`
pairs per sweep: 1.7 ms, **0.22 %**.  591 `Supply.create.split` draws against 1:
0.039 ms, **0.005 %**.  Order/JIT: **0.3 %**.  Two residual biases remain and
**both flatter 7.1**: the 591 slices and `ParseState`s are built outside the
timing loop (right for a ratio, wrong for a per-check cost), and
`atLayoutBoundary` skips no trivia on an exhausted slice — the same effect §4.3
just measured in the trees.  Both sit inside the 4.7 % residual.

### 4.6 **F5 — the private-block worst case, and where an edit actually lands**

A one-character edit does not choose an extent uniformly; it lands uniformly over
the TEXT.  Over the 529 real statements, byte-weighted:

| | implementer | reviewer |
|---|---|---|
| **expected miss cost** | **19.39 ms** | 20.49 ms |
| byte-weighted p50 | 2.46 ms | — |
| byte-weighted **p90 = p95 = p99** | **98.51 ms** | 104 ms |
| p100 | 98.51 ms | 104.13 ms |
| uniform-over-extents mean / median | 1.288 / 0.648 ms | 1.226 / 0.614 |

Report.e has **7 `private` blocks** (no `database` blocks) totalling **14,591 B =
23.0 % of statement bytes and 18.9 % of the file**, and **150.7 ms = 22.1 % of the
sweep** (reviewer 22.3 %).  The largest is ONE top-level extent spanning
**172 lines, 9.8 % of the file** — so **one edit in seven lands in the ~100 ms
block**, and an editor session spent inside it sees the worst row of the table as
its steady state.  The saving survives that (§8: even the p100 leaves 0.67 s),
but 7.1b must quote **20.5 ms expected and ~104 ms p90**, never the 0.6 ms
median.

### 4.7 **F6 — the per-statement parse is SUBLINEAR**

Log-log fit over the 529 real statements:

    implementer:  ms = 2.50e-2 x bytes^0.829,  R2 = 0.81,  aggregate 10.75 us/B
    reviewer:     ms = 2.52e-2 x bytes^0.837,  R2 = 0.80,  aggregate 11.3 us/B,
                  marginal (through-origin) 9.65 us/B, per-statement fixed cost ~0.15-0.25 ms

**Sublinear, with a real per-statement fixed cost** — which is *why* 591 small
slices come to ~5 % LESS than one whole-file pass rather than more.  The brief
asked whether superlinearity would re-rank 7.3: **there is none, so 7.3's
ranking is unaffected on that axis.**

---

## 5. ATTRIBUTION — MEASURED against the survey's ARITHMETIC (7.0.4), on ONE base

> **F8.  THE DECLARED BASE IS THE SHARE OF THE READ.**  Survey shares are its
> implied seconds over the 0.770 s read of P1; measured shares are run C's
> milliseconds over its 845.4 ms read.  The factor is
> **survey share ÷ measured share**: **> 1 means the survey OVER-attributed the
> phase, < 1 means it UNDER-attributed it.**  The absolute column is SECONDARY
> and is shown only because the read itself has drifted (0.770 → 0.845 s); it
> uses the same convention on milliseconds.

| phase | survey share | **measured share (C)** | **FACTOR (share base)** | secondary: absolute |
|---|---|---|---|---|
| **parse** | 91.4 % (0.70 s) | **98.2 %** (829.84 ms) | **0.93 — UNDER-attributed 1.07x** | 0.84 — under 1.19x |
| extent scan (+`Offsets`) | 7.01 % (54 ms raw) | **0.28 %** (2.357 ms) | **25.1 — OVER-attributed 25.1x** | 22.9 — over 22.9x |
| ” vs the P5(a)-corrected ~4.7 ms | 0.61 % | 0.28 % | 2.19 — over 2.2x | 1.99 — over 2.0x |
| lower (incl. `lowerctx`) | 1.17 % (9 ms) | **1.07 %** (9.069 ms) | **1.09 — OVER-attributed 1.09x** | 0.99 — exact |
| rename | 0.26 % (2 ms) | **0.60 %** (5.043 ms) | **0.43 — UNDER-attributed 2.30x** | 0.40 — under 2.52x |
| reassoc | 0.13 % (1 ms) | **0.08 %** (0.677 ms) | **1.62 — OVER-attributed 1.62x** | 1.48 — over 1.48x |
| rename + reassoc + lower | 1.56 % (12 ms) | **1.75 %** (14.79 ms) | 0.89 — under 1.12x | 0.81 — under 1.23x |
| header parse | *absent from the survey* | 0.95 % (8.053 ms) | — | — |
| self-scrub | *absent* | 0.24 % (2.058 ms) | — | — |
| `TolerantCheck.keys` | *absent* | 0.39 % (3.272 ms) | — | — |
| `Definitions.index` (+ symbols) | *absent* | 1.18 % (9.953 ms) | — | — |
| typecheck (`checkWith`) | 0.515 s (P1, MEASURED not arithmetic) | 492.38 ms | — | 1.05 — the P1 figure holds |

**IS THE PARSE SHARE HONEST?  YES, and the survey was if anything too kind to the
rest.**  The parse is 98.2 % of the read, not 91.4 %.  **P5(a)'s 3.5x
over-attribution precedent does NOT repeat**: the one wildly over-attributed row
is the extent scan, and that is not sample bias — it is the survey quoting a
pre-P5(a) figure it had itself flagged as superseded; against the corrected
figure the residual is 2.2x on a 2.4 ms pass.

Two findings to carry forward.

**5.1 `rename` is ~2.3x what the profile said**, so Decision (b)'s "rename +
reassoc + lower ≈ 12 ms" is really **14.8 ms**.  **Decision (b) is UNAFFECTED**:
14.8 ms is 1.75 % of the read and 1.1 % of the check — still smaller than the
machine's own between-run drift.

**5.2 (F9) The header is parsed twice — by two DIFFERENT grammars.**
`Resident.checkFile` runs `ModuleParsers.moduleHeader` over the whole buffer
(**8.05 ms**) to find the module's siblings before the loader is built;
`NewPipeline.read` then calls `SurfaceParsers.module`, whose first act is
`header(defaultName)` over the same text (**5.82–6.19 ms** measured alone,
~6.2 ms server-scaled), inside the 829.8 ms `parse`.  That is **~14 ms of header
parsing per keystroke**, and "pure duplication" — as the first draft of this
report called it — **overstates it**: the two are different parsers over
different grammars (the `Er` header vs the surface header), so removing one means
making the surface header serve `Resident`'s sibling-root need, which is a
behaviour change.  **Not worth a Stage-4 line today** (0.6 % of the check, one
eighth of the drift, and GATE-POLICY would only let it be claimed by an
interleaved A/B not worth its JVM time).  **Worth taking after 7.1b**: against a
62–83 ms read floor, 8 ms is **10–13 %**.  Record it as a 7.1b follow-on, not as
an item.

---

## 6. THE Rpc ADDENDUM (7.0.5, Decision (d)) — MEASURED, and **DROPPED**

**The in-process number reproduces the survey's out-of-process figure.**  On a
79,628-byte frame, in the live server: `rpc.frame` **0.081 ms** (81 µs, headers +
body read + UTF-8 decode) and `rpc.json` **0.307 ms** (307 µs) — against the
survey's claimed ~369 µs, confirmed in process and 1.2x optimistic.  In a scratch
JVM on the same captured body it is 355 µs, which brackets it.

**The run-based scanner: implemented in scratch, measured, 1.24x — not 5x.**
`JsonBench.scala` copies `Rpc.scala`'s `P` verbatim and changes only `string()`:
scan a RUN of ordinary characters, append it in one call, and return a plain
`substring` when the string holds no escape.  Interleaved with the shipped
parser, **order alternating every rep**, 20 warm-ups + 100 reps, load 1.12:

| | median µs | min | p10 | p90 | max |
|---|---|---|---|---|---|
| shipped `Json.parse` | **355.4** | 325.5 | 329.1 | 470.7 | 1727.5 |
| run-based variant | **286.1** | 254.4 | 255.9 | 553.1 | 849.5 |
| | **1.24x, Δ 69.3 µs** | | | | |

(UTF-8 decode of the same 79,627 bytes: 49.6 µs.)  The survey claimed
369 → 61 µs, a **5x**.  Measured, it is **1.24x**.

**DROPPED.**  69 µs is **0.004 %** of the 1.676 s round trip — four orders of
magnitude below the ~50 ms editor noise floor.  It is a request-path change, so
as the brief says it would need **no perf A/B on the round trip** (at ~0.02 % of
it, an A/B could not see it either way) — but that cuts both ways.  Against it:

> **THE TRAP, recorded because the next attempt will hit it.**  The first draft
> of the variant was NOT byte-identical, and only the equality assertion caught
> it: `scala.collection.mutable.StringBuilder.append(cs, a, b)` takes
> **(offset, LENGTH)**, not (start, end).  A ten-line "obviously safe" change to
> the protocol reader silently corrupted every string with an escape in it — on a
> body that is 1,757 `\r\n` escapes long.  The fix was `java.lang.StringBuilder`,
> whose `append(CharSequence, start, end)` is (start, end).

Decision (d)'s "do nothing" **stands, now on an in-process number**.  `Rpc.scala`
is unchanged apart from timers (reviewer F12 confirms: `Json.P`, `string()` and
the scanner are untouched).

---

## 7. THE 7.2 CLIFF, MEASURED (7.0.6) — reproduced exactly

`cliff.py`, one server: `didOpen`, six in-body edits (perf-client's pinned digit
edit, no line-count change), then ONE `didChange` whose only additional change is
**a blank line inserted at the top of the file**, then two more in-body edits on
the shifted text.

| round | read s | typecheck s | **reused** | round trip (impl / reviewer) |
|---|---|---|---|---|
| `didOpen` (cold cache) | 0.95 | 1.14 | **0 of 154** | 2.217 / 2.210 s |
| in-body edits 1–6 | 0.90–1.04 | 0.50–0.64 | 97 of 154 | 1.775–1.989 / 1.742–1.832 s |
| **ONE BLANK LINE AT THE TOP** | 0.90 | **1.07 / 1.06** | **0 of 154** | **2.294 / 2.293 s** |
| in-body, shifted (×2) | 0.92–0.94 | 0.53–0.56 | 97 of 154 | 1.801–1.814 / 1.757–1.785 s |

`checkWith` on the top-insert round: **1060.2 ms**, against 496–633 ms on the
in-body rounds and 1100.7 ms on the cold `didOpen`.

**The roadmap's CODE-DERIVED prediction is confirmed exactly: reuse goes to
0 of 154**, on two independent runs.  Its "~0.5 s" is exact as the DELTA and low
as the absolute: the top-insert pays **1.06–1.07 s** of inference where the same
edit one line lower pays ~0.53 s, so the cliff costs **+0.51 s of inference and
+0.51 s of round trip — a 29 % regression for an edit that changed nothing**, and
it is indistinguishable from a cold open.  Recovery is immediate.

---

## 8. VERDICT

> ## **7.1** — build the surface-tree cache keyed by statement extent.
> ## Saving **~0.76 s (45 % of the round trip)**, band **0.67–0.83 s**.
> ## **7.2 lands first**, unchanged.

The arithmetic, on run C:

    per-statement work / whole-file parse   =  0.953
    parse / read                            =  829.84 / 845.37  =  0.982
    read / check                            =  845.37 / 1362.99 =  0.620
    read / round trip                       =    0.850 / 1.676  =  0.507

    => per-statement parse work is 0.953 x 0.982 x 0.620 = 58.0 % of the check
       and 47.1 % of the round trip.

Both of 7.1's conditions hold and neither is marginal: **per-statement work is
95 % of the whole-file parse** and **the parse is 98.2 % of the read**.

### 8.1 What 7.1b actually saves — the corrected floors (F3)

The first draft's "38 ms → 0.88 s" is **WITHDRAWN**.  It (i) added `Resident`'s
8.21 ms `header` to a floor that is then subtracted from `read.total`, which does
not contain it; (ii) used the **median** miss where the byte-weighted expected
miss is 34x larger; and (iii) charged a driver residual that only ONE of the two
cache designs pays, while quoting the other design's floor.  The reviewer's
corrected table, server-scaled by 829.84/773.85 = 1.072:

| | **conservative** (cache keeps `module()`'s driver) | aggressive (cache replaces `module()`) |
|---|---|---|
| `extents.scan` | 0.81 | 0.81 |
| driver / trivia residual | **45.7** | — |
| one statement, median | 0.66 | 0.66 |
| **parse floor, median edit** | 47.2 ms | 1.5 ms |
| parse floor, **byte-weighted expected** | 68.5 ms | 22.8 ms |
| parse floor, worst case (the big `private`) | 158.2 ms | 112.5 ms |
| + rename/reassoc/lower/lowerctx/syntax (14.8 ms, not cached) | | |
| **`read.total` floor** median / expected / worst | **62 / 83 / 173 ms** | 16 / 38 / 127 ms |
| **saving off `read.total` 845.4 ms** | **0.783 / 0.762 / 0.672 s** | 0.829 / 0.808 / 0.718 s |
| **round trip 1.676 s →** | **0.893 / 0.914 / 1.004 s** | 0.847 / 0.868 / 0.958 s |
| **reduction** | **47 % / 45 % / 40 %** | 49 % / 48 % / 43 % |

**The number for the roadmap is 0.76 s / 45 %** — the conservative design at the
byte-weighted expected edit — with a **0.67–0.83 s** band across designs and edit
sites.  Every cell clears the 200 ms pooled gate by **3.4x–4.1x**, and every cell
beats the roadmap's own arithmetic estimate (0.55–0.68 s).  **The precondition —
"if 7.0's parse number is materially smaller the item does not start at all" — is
cleared.**

7.1b must also budget for what §4.3 found: **62 header extents keyed separately**
(or it caches 62 `SErrorStatement`s) and **15 of 529 statements whose top-level
end `Span` a splice must re-derive** (or its differential fails on them).

### 8.2 The strongest case AGAINST 7.1, and why it loses

It is **not** the residual and **not** the drift; both were tested and are too
small.  It is that **7.3 subsumes 7.1**.  The survey says so in §5(a′): if the
parser's constant factor falls even **10x** — a fifth of the 48–52x §1.11 cites —
the whole-file parse goes 830 → 83 ms, the read to ~98 ms and the round trip to
~0.93 s, **the same place 7.1b's conservative floor lands (0.89–1.00 s)**, with no
cache, no span arithmetic, no high-water-mark soundness obligation, no 180-file
splice differential, no GC-rooting of surface trees and no 62-extent header
special case — and it also takes the 12.8 s boot and every batch and REPL path
with it, which 7.1b cannot touch.  7.1b's win is capped twice: by a residual it
cannot remove (~46 ms server-scaled) and by a per-miss cost that reaches ~112 ms
one edit in seven.  7.3's is not capped at all.

Note also that this report's first draft de-ranked 7.3 with a **non-sequitur** —
"0.60 ms of miss is not a cost worth an architectural rewrite".  7.3 does not
attack the 0.60 ms miss; it attacks the **830 ms whole-file parse that 7.1b
exists to avoid**.  That argument is withdrawn.

**Why 7.3 loses anyway: RISK, not arithmetic.**  7.3 is Tier 1 inside
`scalaparsers`, behind the 180-file differential, `ei-diff.sh --batch` on both
sides, `g1-validate.sh` and byte-exact REPL goldens.  This project already has a
reverted precedent for the localized version (P5(d), abandoned at 43 ms).  And
the 48–52x is **tree-sitter-haskell's** number in a different system, not a
projection of a de-trampolined `scalaparsers`: **nothing in the measured table
bounds 7.3's actual delivery.**  7.1b is editor-path-only, its win is measurable
today at 0.67–0.83 s, 3.4x–4.1x the pooled gate.  **7.1 first.**

### 8.3 Two notes the roadmap should record alongside the ranking

* **7.1b and 7.3 MUST NOT BOTH BE BUDGETED AS EDITOR SAVINGS.**  If 7.3 lands,
  7.1b's editor win largely evaporates.  They are **alternatives on the editor
  path**; 7.3 is additive only on the batch/boot path.
* **7.3's re-ranking to the BATCH target is right and is stronger than this
  report first stated.**  A cold 129-module load parses every file exactly once
  and has **no cache to hit**; boot is **12.8 s, 7.5x the whole editor round
  trip**.  That is where 10.75 µs/byte is unamortisable, and it should be ranked
  there against P5(c) — not de-ranked as an editor item and forgotten.

### 8.4 7.2 first — agreed, unchanged

Independent of the 7.1/7.3 choice; its cliff is now measured on both sides at
**+0.51 s of inference and +0.51 s of round trip, a 29 % regression on an edit
that changed nothing** (§7); and 7.1b needs the span arithmetic regardless,
because a cached surface tree carries `Span`s and an insert above shifts every
one of them — and §4.3 shows the top-level end span is already the thing a splice
has to get right.

---

## 9. GATES (Tier 0)

The full Tier 0 was run on the tree before the fix round, and the gates the fix
round can affect were re-run after it.  The reviewer's independent run is beside.

| gate | required | pre-fix | **post-fix** | reviewer |
|---|---|---|---|---|
| `sbt core/compile core/copyResources` | green | green | **green** | green |
| `sbt 'core/testOnly *TestLoopTrace'` | 720/720 | 720 segments, 720 agree, 0 hashdiff, 0 eqdiff, 0 skipped; 3/3 properties | — (untouched by the fix: LSP-path only) | **720/720, 3/3** |
| `sbt 'core/testOnly *TestTolerantCheck'` | green | — | **27 of 27 properties proved**, 108 s; the 253-file 6.2 sweep 249 clean, required-class misses 0 | — |
| `corpus-run.sh --batch` | 85 / 69 / 0 over 154 | 85 / 69 / 0 | — (untouched) | **85 / 69 / 0** |
| `repl-smoke.sh` | 8 groups / 66 checks | 8 groups, 66 checks; goldens unmodified | — (untouched) | **8 / 66**, goldens unmodified |
| `lsp-smoke.sh` | 456 | 456 | **456**, both directions verified: 0 `phases:` lines in the shipped log, exactly 1 in the property log | **456**, both non-vacuous |
| boot | 129 modules | 129 | **129** | 129 (12.71 / 12.81 s) |
| `.ei` droppings | 0 | 0 | **0** | 0 (143 tracked, count unchanged) |
| `git diff --stat` == `--stat -w` | identical | identical | **identical** | identical |
| strict path `Session.scala` | unchanged | empty diff | **empty diff** | not in `git status` |

`TestLoopTrace`, `corpus-run.sh` and `repl-smoke.sh` were not re-run after the fix
round: the only code change in it is `Diagnostics.scala` (LSP-only, not reachable
from the batch reader or the REPL) and one `if (Phases.enabled)` guard in
`Resident.scala` (likewise LSP-only).  `TestTolerantCheck` was run instead, per
the fix-round instruction, and exercises the editor check path end to end.

**`NewPipeline.scala` — why the strict `readModule` is unaffected.**  The diff is
six inserted lines in `read`, in two shapes only: `val tX = Phases.now` (returns
`0L`, no side effect when off) and `Phases.add(name, tX)` (returns `Unit`, no
side effect when off).  No control flow, no declaration order, no expression
value changed; `Phases.add("parse", tParse)` sits AFTER the match, so a
header/parse failure still throws `Death` at the same point with the same
message.  `readModule(f, c, mh)` is `read(…, tolerant = false)` over the same
traversal.  The property is set by nothing in `bin/ermine`, `Console`, `sbt`,
`corpus-run.sh`, `repl-smoke.sh` or any test.  The evidence rather than the
argument is the gate rows: `TestLoopTrace` 720/720, corpus 85/69/0, REPL goldens
byte-unmodified, `TestTolerantCheck` 27/27, `lsp-smoke` 456.

Tier 1 was NOT needed and NOT run: nothing in `scalaparsers`, `Subst.scala` or
`Type.scala`'s constraint construction was touched — which is exactly the
boundary §2(d) declined to cross.

The non-reindentation of `checkFile`'s body under its new brace is deliberate and
the reviewer endorsed it: `--stat` == `--stat -w` is a gate, and a 230-line
whitespace reflow would have made it meaningless.

---

## 10. Files changed

| file | what |
|---|---|
| `core/.../session/Phases.scala` | **NEW** — the property-gated timer accumulator |
| `core/.../rename/NewPipeline.scala` | 6 timers around parse / syntax / rename / reassoc / lowerctx / lower |
| `core/.../session/TolerantCheck.scala` | 2 timers inside `keys`: `extents.scan`, `extents.offsets` |
| `core/.../lsp/Resident.scala` | 9 timers in `checkFile` + `Phases.reset()` at the end of `boot()`; **F4**: `read.total` wrapped in `if (Phases.enabled)` |
| `core/.../lsp/Diagnostics.scala` | `index` and `check.total` timers; the one-line emit + reset; **F4**: `record(…, nanoTime − t)` → guarded `add(…, t)` |
| `core/.../lsp/Definitions.scala` | `index.symbols` timer around `Symbols.build` |
| `core/.../lsp/Rpc.scala` | `rpc.frame` / `rpc.log` / `rpc.bytes` in `receive`, `rpc.json` in `handle` — timer-only |
| `tracker/tools/lsp-client.py` | +2 checks pinning the property gate in both directions (454 → 456) |
| `tracker/loopmodel/LSP4-7.0-READ.md` | **NEW** — this report |

Scratch, deliberately NOT in the tree (`<scratch>/7.0/`): `StmtBench.scala`,
**`SliceAudit.scala`** (the fix round's non-vacuous F1 audit + the re-derived
residual, distribution and sublinearity fit), `JsonBench.scala`, `cliff.py`,
`harvest.py`, `didchange.json`, and the raw logs and tables of every run.

---

## 11. For the reviewer of the fix round

To re-cut the phase table (wait for load < 1.3 first):

    export JAVA_HOME=~/.local/ermine-toolchain/jdk-21.0.12.1+1
    cp="$(tr -d '\n' < tracker/repl-classpath.txt)"
    python3 tracker/tools/perf-client.py --rounds 70 \
      --file core/src/main/resources/modules/Layout/Report.e \
      --log /tmp/r.log --out /tmp/r.json --stderr /tmp/r.err \
      -- "$JAVA_HOME/bin/java" -Dermine.lsp.log=/tmp/r.log \
         -Duser.language=en -Duser.country=US -Dermine.lsp.phases=true \
         -cp "$cp" com.clarifi.reporting.ermine.lsp.Main
    python3 <scratch>/7.0/harvest.py /tmp/r.log 21 50

and `SliceAudit <Report.e> 20 50` for §4.3–4.7.

The numbers a later item should quote: **parse 829.8 ms**, **read 845.4 ms**,
**ratio 0.95**, **driver residual 42.6–43.3 ms / 5.5–5.7 %**, **529 real
statements + 62 header extents, 15 of 529 span-divergent**, **expected miss
20.5 ms / p90 ~104 ms**, **cliff 0 of 154 / 1.06 s**, **7.1b saving 0.76 s (band
0.67–0.83 s)**.  Everything in §8 follows from those.

STOPPED after this report.
