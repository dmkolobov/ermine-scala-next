# Review: LSP Stage 4, item 7.1b — the statement-extent surface cache (ADOPTION)

Independent reviewer's report.  Branch `scala3-migration`, HEAD `d87e2cb` plus the uncommitted 7.1b
deliverables.  Brief: `tracker/loopmodel/briefs/brief-LSP4-7.1b-review.md`.  Implementer's report:
`tracker/loopmodel/LSP4-7.1b-CACHE.md`.  Scratch: `<scratch>/review-7.1b/`.  Nothing outside that
scratch and this file was edited; no commit; `tracker/lean/` and `tracker/LSP-ROADMAP.md` untouched.
One JVM at a time throughout; every `.ei` caused was deleted (`find`, see the gate table).

**VERDICT: ADVANCE.**  The invariant holds on my own runs: the seed-71 differential reproduces
exactly (2,613 steps, 54,274 hits, 0 `SModule` mismatches, 0 diagnostic mismatches), two fresh seeds
are equally clean, and eleven constructed attacks — including the two that decide soundness, an edit
inside the guard but outside the extent and identical text at a different start column — all come out
as a MISS with a correct tree.  The strict path is frozen: the diff is additive, and the 154-file
corpus is byte-identical to my OWN pre-change build.  The gate asked 200 ms on the read; I measure
**−788 ms** on an interleaved pair run in the opposite order from the implementer's.  Tier 2 is
**1019 properties, 1 failed, 0 errors** — the one failure is the documented `TestInterfaceRoundTrip`
cross-suite flake, which passes alone on this tree and which 7.1b cannot reach.  FIVE findings, all
LOW, none blocking: a cold-open cost the report understates, a stale latency table that is G4's by
rule, a latent non-termination guard worth one line, a duplicated extent scan already named by the
implementer, and the pre-existing Tier 2 flake.  (Three of them were fixed in a closing round while
this review was finishing; §9 says what I re-ran on the changed tree and what is still owed.)

---

## 1. THE STRICT PATH IS FROZEN (brief §1)

**The diff is additive and the editor-only entry is the only new caller.**  `git diff --numstat` on
`surface/SurfaceParsers.scala` is **158 insertions / 0 deletions**; the insertion is one block
containing `moduleCached` and a `private def posAt`.  `module`, `statement`, `statementBody`,
`statementFailure`, `moduleMarked` and `moduleP` are not edited — I read the whole hunk and diffed
the file against `HEAD`, not just its stat.  `moduleCached` calls the SAME driver
(`moduleP(fileName, defaultName, cached)`), which `module` has taken a statement parser since 7.1a, so
there is no second driver.  `Session.scala` does not appear in `git status` and has an empty diff.
`NewPipeline.read` gained two parameters with IDENTITY defaults (`cached = false`, `prev = None`), and
`Read` gained a trailing `surfaceCache: Option[...] = None`; every strict caller's behaviour is
unchanged by construction, and the strict branch still calls `SurfaceParsers.module`.

**No shared mutable state reaches the strict path.**  The one mutable cell in the parse is 7.1a's
`ParseState.mark`, whose default is `MarkOff`; `moduleCached` installs a live `new Mark` exactly as
`moduleMarked` does, in its own `ParseState`.  The REPL, the interface reader and the batch loader
keep `MarkOff`.

**Corpus byte-identity, against my own pre-change build.**  I exported `HEAD` with `git archive` into
`<scratch>/review-7.1b/pre`, compiled it there (`core/compile core/copyResources`, green), snapshotted
both class trees, and ran `corpus-run.sh --batch` twice with `ERMINE_CP` pointed at each.  Verdicts
**85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** on both sides; after normalising only the progress-bar
frames, the `(N.NN seconds)` / `N.NNs` timings and the classpath prefix (the two trees live in
different directories), **154 of 154 outputs are byte-identical** (`diff -rq` exit 0).

**The standing tripwires are green** (see the gate table): `TestReplDifferential` and
`TestTolerantRead`'s strict-vs-tolerant corpus agreement property both pass in the targeted run, and
`repl-smoke.sh` is 8 groups / 66 checks with `git status tracker/repl-tests/` EMPTY — the goldens are
byte-unmodified.

## 2. THE DIFFERENTIAL — reproduced, re-seeded, and attacked (brief §2)

### 2.1 Three runs of the corpus differential (mine) beside the implementer's

| | implementer, seed 71 | **me, seed 71** | **me, seed 913** | **me, seed 20260911** |
|---|---|---|---|---|
| files | 253 | **253** | **253** | **253** |
| steps | 2,613 | **2,613** | **2,612** | **2,615** |
| statements spliced | 73,648 | **73,648** | **73,803** | **73,775** |
| hits / misses | 54,274 / 19,374 | **54,274 / 19,374** | **54,346 / 19,457** | **54,334 / 19,441** |
| reuse | 73.69 % | **73.69 %** | **73.64 %** | **73.65 %** |
| **`SModule` mismatches** | 0 | **0** | **0** | **0** |
| **diagnostic mismatches** | 0 / 2,601 steps | **0 / 2,601** | **0 / 2,600** | **0 / 2,603** |
| end-span audit | 59,167 / 3,502 / 2,543 | **59,167 / 3,502 / 2,543** | — | — |
| wall | 384 s | 409 s | 381 s | 379 s |

Seed 71 reproduces **exactly**, counter for counter, including the end-span audit.  The two fresh
seeds move only the shapes that pick a random candidate (`merge`, `split`, `block-edit`,
`unreachable-edit`) and are equally clean.  The shipped property (`*TestSurfaceCache`) is green on its
sample AND on the whole corpus under `-Dermine.test.surfacecache.full=true` (4/4, 2m58s).

### 2.2 (a) Is `SModule` structural equality really total?  **Yes — the brief's worry is REFUTED.**

I enumerated every node type in `surface/Surface.scala`: the whole hierarchy is `final case class`es
over `Int`, `String`, `Boolean`, `List`, `Option`, tuples, `Fixity` (case classes/objects),
`java.util.Date`, and `Span`, which is `final case class Span(startLine, startCol, endLine, endCol)` —
four `Int`s.  There is **no `Array`, no function, no `Loc`/`Pos` and no identity-equality field
anywhere in the tree**, so `==` is a deep structural comparison and every span is compared.
`SErrorStatement`/`SErrorTerm`/`SPError`/`STyError` carry their `message: String`, and those are
compared too.  The one equality in the codebase that is NOT structural — `Pos.equals`, which ignores
the `current` source-line text — is not reachable from an `SModule`, because surface nodes hold
`Span`, never `Pos`.  It IS reachable from the `ParseState`, and `moduleCached` handles that: a hit
rebuilds the exit `Pos` from the NEW buffer with `posAt`, by the same rule `Pos.bump` uses (line start
to the next `\n`, plus the `ending` flag), so no stale line text can survive a hit into a later
diagnostic's caret line.  I checked `posAt` against `Pos.bump`/`Pos.start` line by line; they agree.

### 2.2b The soundness lemma, stated — because it is the thing a reader will doubt

The guard is a PREFIX-determinism argument and it is worth writing down, since the differential can
only sample it.  A parser reads input in order and, after each byte it has read, decides whether to
read another; so the set of positions it examines, and every decision it makes, is a function of the
bytes it has already examined plus the state it started in.  `moduleCached` compares exactly that:
the start state (offset by construction, start column, enclosing layout depth, `bol`) and the bytes
`[start, start + examinedLength)` that the previous parse of this statement examined — 7.1a's
high-water mark, which is monotone and therefore an UPPER bound on what this statement alone looked
at.  If all of them agree, the parse would examine the same positions again (it cannot discover a
reason to read further, because the only bytes that could give it one are the identical ones) and
produce the same tree.  Two corollaries I checked in the code rather than assuming: the mark being
CUMULATIVE makes the guard too wide, never too narrow (it can only refuse a hit); and a hit that
bumps the shared mark only to its own carried reach cannot under-guard the NEXT statement, because
that statement's own parse raises the mark past its own examination before its entry is recorded.

### 2.3 (b) An edit INSIDE the guard but OUTSIDE the extent — **MISS, confirmed three ways**

`<scratch>/review-7.1b/Attack.scala`, §A.  Three shapes, each a text where the edit falls strictly
after the statement's own extent:

* **the 7.0 §4.3 trivia shape** — a comment inserted between `a = 1` and the next statement.  I
  verified the extent text of `a` is byte-identical across the edit (`regionMatches` on the two
  buffers) and then recomputed the four conjuncts from the public `Entry`:
  `textEq=true guard=false examinedLen=8 extentLen=5`.  **The guard, and nothing else, refused the
  reuse**, the statement was re-parsed, and spliced == fresh.  This is the single most important check
  in the review: the mark is load-bearing, not decoration.
* **the Lean `private def` shape** — a following statement indented into a `private` block: the
  scanner fuses the extents, the absorbed statement is not served stale, spliced == fresh.
* **the 7.1a F1 `--` → `-` shape at a statement boundary** — a comment line that becomes an operator
  continuation: spliced == fresh, reuse 1 of 3.

### 2.4 (c) The END-SPAN finding — the implementer's correction stands

The brief's blanket rule ("re-derive every statement's end span from the next extent's start") would
have been wrong, and the numbers are reproducible: my own audit run prints **59,167 statements ending
at their extent's end, 3,502 at the NEXT extent's start, 2,543 elsewhere**, identical to the
implementer's.  The mechanism they name is the right one (`optionalSpace` is rolled back at a
top-level boundary; `virtualRightBrace`'s `layout` call is not), and the design reproduces both
classes by construction rather than by rule — a miss is parsed in situ over the whole buffer, and a
hit carries its end span, which is inside the guard (`endOffset <= examinedEnd`).

I verified the HIT side directly (Attack §I): one line inserted at the top of `Layout/Report.e`,
**529 of 529 statements reused**, spliced == fresh, and among those reused statements **both classes
are present** — 514 ending at the extent end and 14 at the next extent's start (1 elsewhere: the last
statement).  So a hit's shifted end span equals a fresh parse's in both classes, on real code.

### 2.5 (d) The header — re-parsed every check, and a header edit does NOT drop the file

Confirmed by code (`header` consumes the import/export extents before the statement driver runs, so
their keys are never looked up) and by measurement (`<scratch>/review-7.1b/Hdr.scala`): Report.e's
header block is 2,212 chars / **62 import-export extents** and re-parses in **8.0 ms**, exactly 7.0's
table figure and ~1 % of the 768 ms cold parse.  The decision to leave it uncached is right.

The brief's question — does editing the header region drop everything?  **No.**  Inserting a new
`import Vector` line into Report.e's header gives **529 hits / 0 misses, 28.0 ms, spliced == fresh**:
the statements' texts are untouched, every span moves by one line through `Anchors`, and only the
header is re-parsed.  An all-hit re-check of IDENTICAL text costs 28.1 ms, so the warm floor is
~28 ms, of which 8 ms is the header.  (A header that does not PARSE is §2.9 below.)

### 2.6 (e) Start column / layout depth with identical text — **MISS, and the guard alone would have said YES**

Attack §B.  The same two statements, indented by two columns (so both the start column and the
enclosing layout depth move, with every extent's text byte-identical).  Recomputing the conjuncts from
the entry for `b`: **`textEq=true guard=true`** — text equality AND 7.1a's forward mark would both
have allowed the reuse — and the cache reused **0 of 2**, because `e.startCol == s.loc.column` and
`e.depth == s.depth` failed.  Spliced == fresh.  This is the 7.1a review's F4 obligation discharged
and demonstrably load-bearing: without those two conjuncts the tree would have carried column-1 spans
for column-3 text (`Anchors` never moves columns, by rule).

### 2.7 (f) A statement MOVED past another — correct, by miss

Attack §C: `b` and `c` swapped, both texts byte-identical, both keys unchanged (the ordinal is per
head word).  Result: **reuse 0 of 3**, spliced == fresh, statements in the new order.  The key
selected the right candidates and the guard refused them — a moved statement's predecessor and
successor bytes changed inside its guard region.  Correct but conservative; the cost is a re-parse of
the two moved statements, which is the right trade.

### 2.8 (g) Two byte-identical statements (a duplicate definition)

Attack §D: `dup = 1` twice.  The cache holds `Key("dup",0)` and `Key("dup",1)`; each serves the
statement at its own ordinal, and because the ordinal is recomputed lexically from the new text every
check, the first `dup` can never be served the second one's tree.  With a later statement edited,
reuse 2 of 3, spliced == fresh, **and the tolerant read's diagnostics are identical warm vs cold**
(both empty here — adjacent equations with the same head are clauses of one definition in Ermine, not
a refusal; the differential's `shouldfail`-free corpus plus lsp-smoke's `ds_warm == ds_cold` on a
deliberately broken final text cover the diagnostic-bearing case).

### 2.9 (h) Key collisions and (i) a file that does not parse

* **Collision costs a hit, never a tree (CONFIRMED).**  A key only selects a candidate; reuse then
  requires the four conjuncts, two of which I have just shown to be independently load-bearing.  I
  also exercised the ordinal shift directly (Attack §G: a new `f` clause inserted before two existing
  ones, so every `f` ordinal moves): spliced == fresh.
* **A header failure (Attack §E2).**  Both `moduleMarked` and `moduleCached` refuse, with the SAME
  rendered `Err`.  In the server, `Resident.checkFile` reaches `readModuleCached` inside the
  `Death`-throwing read, so `docs.putSurface` is never called on that path and the document KEEPS the
  cache from its last good check.  That is sound, not stale, because the guard compares against the
  buffer the entry was built from rather than against "the previous check": I fed the kept cache to a
  later good text and got spliced == fresh with full reuse (2 of 2).  `BadHeader.e` covers the path
  end to end in lsp-smoke.

### 2.10 Two extra attacks of my own

* **A zero-consumption entry would loop the driver** (Attack §H).  `moduleCached`'s hit arm returns
  `Commit` after advancing the offset by `consumedLength`; an entry with `consumedLength == 0` would
  be a committed no-op inside `sepEndBy`.  Over the whole corpus — **6,954 entries** — there is **no
  such entry** (the miss path's `Pure` arm, which could create one, is unreachable for the same reason
  it would already loop `module` itself).  Recorded as finding **R-3** (latent, LOW).
* **EOF shapes** (Attack §F): a statement appended after the last one, and the final newline removed —
  spliced == fresh in both, with the last statement correctly missing (7.1a's "the end of input is
  inside the guard" rule, which `examinedUnchanged` implements by requiring equal remaining lengths
  when the mark runs past the buffer; I read that predicate's four branches and they are exact —
  a shorter new buffer always refuses).

### 2.11 Is the differential vacuous on the 153 CRLF corpus files?  **No** (my own check)

153 of the 253 corpus files are CRLF, and the cache's key comparison runs through
`StatementExtents.Offsets.offsetOf`, so a CRLF mismatch between the scanner's offsets and the parser's
would show up as a silent 0-reuse class covering half the corpus while the differential still reported
"0 mismatches".  `<scratch>/review-7.1b/Crlf.scala` checks it directly — one character inserted at a
mid-file statement's end, per file:

| | files | hits | misses | reused |
|---|---|---|---|---|
| CRLF | 119 | 2,163 | 119 | **94.8 %** |
| LF | 95 | 3,867 | 95 | **97.6 %** |

Exactly one miss per file in both classes, 0 spliced-vs-fresh mismatches.  The cache works on CRLF
files as well as on LF ones, and the reuse numbers in §2.1 are not carried by the LF half.

## 3. THE A/B AND THE MISS DISTRIBUTION (brief §3)

### 3.1 One interleaved pair, run in the OPPOSITE order (after/before/after/before)

`perf-client.py --rounds 15` on `Layout/Report.e`, two saved class trees (core AND parsers swapped),
one JVM at a time, every side started under load < 1.3, rounds 2..15 as the steady state.

| pass | side | load | round trip | **read** | typecheck (control) | debounce | residual | cold open |
|---|---|---|---|---|---|---|---|---|
| 1 | AFTER | 1.20 | 0.889 s | **0.050 s** | 0.515 s | 0.300 | 0.026 | 2.357 s |
| 1 | BEFORE | 1.23 | 1.689 s | **0.840 s** | 0.525 s | 0.300 | 0.028 | 2.289 s |
| 2 | AFTER | 1.16 | 0.903 s | **0.050 s** | 0.525 s | 0.300 | 0.027 | 2.348 s |
| 2 | BEFORE | 1.28 | 1.693 s | **0.835 s** | 0.525 s | 0.300 | 0.026 | 2.307 s |
| **pooled** | BEFORE | | **1.691 s** | **0.8375 s** | 0.525 s | | | 2.298 s |
| **pooled** | AFTER | | **0.896 s** | **0.0500 s** | 0.520 s | | | 2.353 s |
| **Δ (mine)** | | | **−0.795 s (−47.0 %)** | **−0.7875 s (−94.0 %)** | −0.005 s | 0 | −0.001 | **+0.055 s** |
| Δ (implementer) | | | −0.785 s | −0.790 s | +0.003 s | 0 | −0.001 | +0.027 s |

**The read moves by 788 ms pooled against a 200 ms gate — 3.9x it**, in the reverse run order, with no
overlap of the per-round spreads (before 1.626–2.050 s, after 0.840–1.042 s).  The typecheck segment
is the control and did not move (−5 ms on a 525 ms base), and component reuse was **97 of 154 on every
round of all four runs**, so the inference cache saw identical work.  My figures agree with the
implementer's to within 3 ms on the read and 10 ms on the round trip.  Against the two noise figures the
roadmap asks every adoption item to name explicitly: the ~50 ms editor noise floor and the
0.795–0.865 s read drift band — the read Δ is **788 ms, 16x the noise floor**, and the after-side read
(0.050 s) is an order of magnitude BELOW the bottom of the drift band, so the movement cannot be drift
in any reading of it.  (Machine note: a 19-hour-old idle `bloop` daemon from another tool was resident
throughout, at ~1 % CPU, on both sides of every interleaved run.)

### 3.2 The miss distribution, re-measured (all five points, not two)

7.0's in-process protocol (50 reps after 20 warm-ups, medians), `<scratch>/review-7.1b/Miss71b.scala`:

| keystroke | implementer | **me** |
|---|---|---|
| COLD whole-file parse (`moduleMarked`) | 751.8 ms | **768.5 ms** |
| COLD through `moduleCached`, no cache | 754.6 ms (+2.8) | **766.6 ms (−1.9)** |
| a body line (perf-client's site, line 281) | 29.2 ms | **29.5 ms** (528/529 reused) |
| the FIRST statement | 27.2 ms | **27.6 ms** |
| **inside the 10.7 KB `private` block (p99)** | 125.8 ms | **128.0 ms** |
| appending at the END of the file | 124.8 ms | **128.3 ms** |
| a blank line at the very top (every span moves) | 26.5 ms | **27.9 ms** (529/529 reused) |

Every point reproduces within 3 %.  The shape of the claim is confirmed: the miss is ONE statement,
the p99 is the big `private` block at ~4.5x the median keystroke, and the full-file re-anchor is the
CHEAPEST case, not the most expensive.  The cold path's own cost is at the noise floor (+2.8 ms
measured by the implementer, −1.9 ms by me — i.e. ≤ ~3 ms in process; see finding **R-1** for what it
costs on a cold JVM).

### 3.3 The worst case a user can reach, end to end

A keystroke INSIDE the 10.7 KB `private` block, driven through the real server (medians of 15 warm
rounds, both class trees, interleaved; the inference cache reuses 0 of 154 at this site, which is a
7.2-domain fact and identical on both sides):

| | before | **after** |
|---|---|---|
| read | 0.90 s | **0.17 s** |
| typecheck | 1.02 s | 1.04 s |
| debounce | 0.30 s | 0.30 s |
| **keystroke → diagnostics** | **≈2.22 s** | **≈1.51 s** |

So even at the p99 site the read drops by **0.73 s** and the worst round trip a Report.e editor sees
falls from ~2.2 s to ~1.5 s.  (`perf-client.py` refuses to SCORE this site — "a round reused NOTHING"
— because its harness asserts an in-body edit that keeps the scope key; the refusal is identical on
both sides, so I harvested the server's own `check:` lines from both logs instead.)

**The cold open**: 2.298 s → 2.353 s (+55 ms, mine) and 2.311 → 2.338 s (+27 ms, theirs); on the
server's own cold READ, 0.92/0.94 s → 1.01/1.00 s mine, 0.93/0.97 → 0.93/1.00 theirs.  See **R-1**.

## 4. RETENTION (brief §4)

Reproduced exactly with the implementer's harness (`Runtime` delta, 16 independent copies, six settled
GCs each), `Layout/Report.e`, 77,385 chars, 529 statements:

| held | implementer | **me** |
|---|---|---|
| the buffer alone | 75.7 KB | **75.7 KB** |
| the surface tree alone | 1,577.7 KB | **1,577.8 KB** |
| **the whole `SurfaceCache.Cache`** | **1,630.4 KB** | **1,630.4 KB** |

**What else is retained:** nothing beyond the tree, the 529 `Entry` records (Ints plus a subtree
reference — the entry trees are the SAME objects as the spliced `SModule`'s, so the tree is counted
once) and the `contents` String the entry set was built from, which in the server is the PREVIOUS
buffer (+76 KB).  `Read.marks` is NOT retained (an entry keeps one `Int`, `examinedLength`), and no
`Checked`/inference artifact is reachable from the cache.  `Doc.surface` is replaced wholesale by each
check (`putSurface`) and dropped on `didClose`, so nothing accumulates across keystrokes.

**The bound with ten open documents**, measured rather than extrapolated
(`<scratch>/review-7.1b/Heap10.scala`, the ten largest stdlib files, 172,426 source chars, 1,147
statements): **3.44 MB of caches**, plus ten previous buffers (~0.17 MB) — call it **3.6 MB**, ~20x
the source and ~0.1 % of the 3 GB editor heap.  The retention story is real and small.

## 5. THE 7.1a COUPLING (brief §5)

7.1a cost the editor read +20..48 ms and was accepted as this item's precondition.  With BOTH items
in, my before-side (HEAD, i.e. 7.1a already committed) reads 0.8375 s and my after-side reads
0.0500 s.  Against the Stage-3-opening baseline G3 records (**0.86 s read, 1.69 s round trip**) the
NET is therefore **read 0.86 → 0.05 s (−0.81 s), round trip 1.69 → 0.90 s (−0.79 s)**: 7.1a's down
payment is ~5 % of what 7.1b returns, and the pair is a net win by a factor of ~17 on the read.
The roadmap's REVERT rule (if 7.1b is reverted, 7.1a comes out with it) is **not triggered** — the
gate is met by 3.9x and the differential is clean.

## 6. FINDINGS

| id | severity | status | what |
|---|---|---|---|
| **R-1** | LOW | CONFIRMED (corrected in the closing round, §9) | The cold-open cost is understated.  §5.1 of the report says "the cold path pays 2.8 ms (0.4 %)", measured in process with the JIT warm; on a cold JVM the first check's READ is 0.92/0.94 → 1.01/1.00 s in my pair and 0.93/0.97 → 0.93/1.00 s in theirs, and the client-side cold OPEN is +55 ms (mine) / +27 ms (theirs).  The direction is consistent across all four pairs: a first open pays roughly **30–70 ms**, not 3 ms, because the scan, the `Offsets` index, the key map and 529 `Entry` allocations run interpreted.  It is ~2 % of a 2.3 s open and does not touch the gate (which is the warm read), but the roadmap and G4 should carry the honest number.  FIX: one sentence in the implementer's §5.1 / the roadmap's 7.1b paragraph.  No code change. |
| **R-2** | LOW | CONFIRMED (fixed in the closing round, §9) | `docs/lsp.md` still says "0.86 s read + 0.50 typecheck + 0.30 debounce" and "keystroke to diagnostics ≈1.7 s" (lines 478, 501), which is now wrong for the editor path by 0.79 s.  Per the Stage-3/4 rule in the roadmap ("docs/lsp.md is refreshed at the gate") this is **G4's job, not 7.1b's**, so it is not an omission of this item — but it is the one user-visible staleness the item creates, and it should be on G4's list explicitly. |
| **R-3** | LOW | CONFIRMED (latent; fixed in the closing round, §9) | A cache entry with `consumedLength == 0` would make the hit arm a committed no-op inside `sepEndBy(semi)` — a potential non-termination rather than a wrong tree.  The miss path's `Pure` arm is what could create one.  It cannot arise today: such a statement would already loop `module` itself, and over the whole corpus (6,954 entries) there is none.  Worth a one-line guard (`if (end > s.offset)` before `seen(pos) = ...`, i.e. do not CACHE a zero-consumption statement) whenever this file is next touched; not worth a round trip now. |
| **R-4** | LOW | OBSERVATION | `Resident.checkFile` now runs `StatementExtents.scan` twice per check (once in `moduleCached`, once in `TolerantCheck.keys`), ~2.3 ms each.  The implementer names it as an obvious follow-on and deliberately does not touch the check path.  I agree with the decision; it belongs in 7.3/7.7's scope, and the 2.3 ms is 4 % of the new 52 ms read, so it is now a visible share of the residual. |
| **R-5** | LOW | CONFIRMED (pre-existing, NOT 7.1b) | Tier 2 came back **1019 / 1 failed**, the failure being `TestInterfaceRoundTrip.new-pipeline cold write, fresh warm read, same answers` — *Expected Some(Interface) but got Some(Full)*.  It **passes alone** on this tree (1/1), and the cause is in the suite's own comment: `Session.depCache` is process-global, the property clears it inside `ErmineFixture.literalLock`, and any suite running in PARALLEL in the same JVM that does not take that lock can repopulate it between the clear and the warm load.  That is the flake the roadmap records as "the Interface round-trip flake" (2026-08-31 D3 part 1) and that the A1 and S2 reviewers hit before me — the third sighting AFTER the claimed root-cause fix.  Nothing in 7.1b touches the interface path (`readModule` strict, `ModuleParsers`, `useInterface=true`), and the corpus load verdicts are byte-identical to the pre-change build.  FOR THE ORCHESTRATOR: do not read my Tier 2 as red for 7.1b — but `tracker/GATE-POLICY.md`'s quarantine note blames "a concurrent process deleting `.ei` files", which is not what happened here; the note should say INTRA-run cross-suite parallelism, or the suite should be made to take the lock around both halves. |

Nothing in the diff produced a finding at MEDIUM or above.  Specifically checked and clean: the guard
predicate's four branches (`examinedUnchanged`); `Shift`'s coverage of the AST (I enumerated every
`case class` in `Surface.scala` and every one that can appear inside a statement is constructed in
`Shift` — only `SModule`/`SHeader`/`SImport`/`SImportItem`, which belong to the re-parsed header, are
absent, and `SName`/`Span` are handled by `copy`/`Anchors`); the join of marks and entries by POSITION
and against the statements that actually came out (`sepEndBy`'s rolled-back last iteration cannot
enter the cache); `posAt` against `Pos.bump`; the per-head-word ordinal; and the
`Documents.put`/`putSurface`/`didClose` lifecycle.

## 7. GATES (brief §6) — every one re-run once by me

All numbers below are MY runs, on the tree as reviewed (the 294/8 diff; see §9 for the closing round).

| gate | required | **my result** |
|---|---|---|
| `sbt core/clean core/compile core/copyResources` | green | **green**, 36 s, no new warning |
| my own pre-change build (`git archive HEAD` → scratch, `core/compile core/copyResources`) | green | **green**, 37 s — the before side of every comparison below |
| `core/testOnly *TestLoopTrace` | 720/720 | **720 solves / 720 segments / 720 agree, 0 skipped, hashdiff 0, eqdiff 0, nonpart 0, fuel 0**, 12.9 s; controls non-vacuous in the same run (id base +1: 46 of 720 disagree; `--flags=nongen`: 58 of 720) |
| the seven targeted suites + `*TestSurfaceCache` | green | **112 properties, 0 failed, 0 errors** (5m13s): Lower 3.4a 28, Tolerant check 47, Tolerant read 11, Surface parser 2.3a 12, Statement extents 4, NewPipeline 4.1c 2, REPL eval goldens 1, loop model trace 3, **Surface cache 4** |
| `*TestSurfaceCache` with the FULL corpus (`-Dermine.test.surfacecache.full=true`) | green | **4/4 properties, 0 failed**, 2m58s |
| `corpus-run.sh --batch` over 154 | 85 / 69 / 0 | **85 LOADED / 69 REJECTED / 0 UNKNOWN / 154**, one JVM, exit 0 — on BOTH class trees |
| corpus outputs vs my own pre-change build | byte-identical | **154 of 154 identical** (`diff -rq` exit 0), normalising only the progress frames, the `(N.NN seconds)`/`N.NNs` timings and the classpath prefix |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups, 66 checks, PASS**; `git status tracker/repl-tests/` EMPTY |
| `lsp-smoke.sh` | 480 + this item's 14 | **494 checks, PASS** — and I verified the arithmetic by running the PRE-CHANGE client against the pre-change build: **480**, so the delta is exactly the 14 new 7.1b checks, all of them executed (the four that sit behind `if len(splice_runs) >= 6` would silently drop the count to 490 if the log line were missing) |
| boot | 129 modules | **129 modules in 12.2 s** (the editor A/B's own boot line) |
| `.ei` droppings | 0 untracked | **143 `.ei` by `find`, all tracked, 0 untracked, 0 under `core/target`** — `g1-validate.sh` wrote 129 under `core/target/.../classes/modules` and they were deleted (`find core/target -name '*.ei' -delete`); re-checked after every JVM |
| `git diff --stat` == `--stat -w --histogram` | identical | **identical: 294 insertions, 8 deletions**, five modified files (the reviewed tree) |
| line endings | preserved | every touched file is LF, 0 `\r` bytes (`grep -c $'\r'`); the CRLF corpus files are read, never written |
| `g1-validate.sh` (owed: `SurfaceParsers` changed) | 9/9 | **9 PASS, G1 COMPARE: EQUIVALENT, no drift from `tracker/g1-baseline`** (129 files, 1447 signatures, double-run self-agreement) |
| **Tier 2 — `sbt -batch -J-Xmx3g core/test` ALONE on the tree** | 0 failed, 0 errors | **Total 1019, Passed 1018, Failed 1, Errors 0**, 1540 s (25:40), one JVM, nothing else running. The single failure is `TestInterfaceRoundTrip` ("Expected Some(Interface) but got Some(Full)") — the DOCUMENTED cross-suite dep-cache flake, and it **passes alone on this tree** (`core/testOnly *TestInterfaceRoundTrip`: 1/1). See finding **R-5** |
| Tier 1 | not owed | nothing under `parsers/`, `Subst.scala` or `Type.scala` is touched — I diffed the whole tree, not just the named files |

## 8. WHAT A USER NOW SEES, and the item's tick conditions (brief §7)

Keystroke to diagnostics on `Layout/Report.e` (1,757 lines, the largest stdlib module), from the
server's own phase numbers on my interleaved pair:

| | before | after |
|---|---|---|
| typical keystroke (a body line) | **1.69 s** = 0.84 read + 0.53 typecheck + 0.30 debounce | **0.90 s** = 0.05 read + 0.52 + 0.30 |
| worst site (the 10.7 KB `private` block) | **≈2.22 s** = 0.90 + 1.02 + 0.30 | **≈1.51 s** = 0.17 + 1.04 + 0.30 |
| first open of the file | 2.298 s | 2.353 s (+55 ms, finding R-1) |

The debounce is now 33 % of the round trip instead of 18 %, which is exactly the trigger Stage-4
Decision (e) wrote for 7.4; the implementer's reading of that is correct.

**Tick conditions, all present:** the differential is recorded with its seed (and now with two more);
the A/B's pooled read Δ is **788 ms ≥ 200 ms**; the heap figure is measured (1.63 MB/document,
3.44 MB for ten); Tier 2 is run.  The one piece of documentation the item leaves stale is
`docs/lsp.md`'s latency table — G4's job by the roadmap's own rule (finding R-2).

## 9. THE CLOSING ROUND — the tree changed under me, and what I re-ran on it

While my Tier 2 was running (its compile had already finished, so Tier 2 tested the tree as reviewed),
the implementer/coordinator acted on findings R-1, R-2 and R-3 in the working tree: two refusal
conjuncts in `SurfaceParsers.moduleCached` (`e.consumedLength > 0` in `reusable`; `end > s.offset`
before `seen(pos) = …` in `record`), a fifth property in `TestSurfaceCache` that poisons an entry by
hand and fails by DEADLINE rather than by assertion, a corrected §5.1 cold-open paragraph, and a
refreshed `docs/lsp.md` latency table carrying my numbers.  The diff is now **330 insertions /
17 deletions over 6 files** (`SurfaceParsers.scala` 170/0, `docs/lsp.md` 24/9), identical under
`git diff --stat -w --histogram`; the CODE has not moved since 03:07, and the only later edit is a
documentation tweak, so the re-runs below cover the exact bytes of every `.scala` file now on disk.

I read the delta and it is exactly the fix I asked for and nothing else: both additions can only
REFUSE a reuse or decline to record an entry, so neither can produce a tree a fresh parse would not
give, and `marks` are still recorded for a zero-consumption statement exactly as `moduleMarked` does.
The new property is honest — it builds a real cache, rewrites ONE entry's `consumedLength` to 0, runs
the splice on a daemon thread with `join(10000)`, and fails if it does not finish, which is the only
way to test for a spin.  Because the change is in the reuse predicate, I re-ran on the POST-FIX tree
rather than inheriting:

| re-run on the post-fix tree | result |
|---|---|
| `core/compile core/copyResources` | **green** |
| the nine targeted suites incl. `*TestSurfaceCache` | **113 properties, 0 failed, 0 errors** (was 112; the new property is the +1); `TestLoopTrace` 720/720, 0 skipped, fuel 0 |
| the corpus differential, seed 71, `--diags` | **2,613 steps, 54,274 hits / 19,374 misses, 0 `SModule` mismatches, 0 diagnostic mismatches** — counter for counter what the pre-fix tree gave, so the fix costs exactly zero reuse |
| the miss distribution, re-measured | cold 755.7 ms, body 28.9, private block 127.3, EOF 128.5, line shift 27.8 — unchanged within noise, so the extra conjunct costs nothing measurable |
| `corpus-run.sh --batch` + byte-identity vs my pre-change build | **85 / 69 / 0 over 154, and 154 of 154 byte-identical** |
| `repl-smoke.sh` / `lsp-smoke.sh` | **8 groups / 66 checks, goldens untouched** / **494 checks, PASS** |
| `g1-validate.sh` | **9 PASS, EQUIVALENT, no drift** |
| `TestInterfaceRoundTrip` alone | **1/1 PASS** (finding R-5) |
| `.ei` by `find` | **143, all tracked, 0 under `core/target`** |

**What the orchestrator still owes**, and it is small: Tier 2 was run on the pre-fix tree, so the
post-fix tree has a full `core/test` outstanding.  Everything else it would cover I have re-run above,
and the only code delta is two refusals, so I would take the Tier 0 set plus `*TestSurfaceCache`
(done above) as sufficient and let G4's Tier 2 be the one that covers the final shape — but that is
the orchestrator's call, and the honest statement is that no `core/test` has yet run on the exact
bytes that will be committed.

**The verdict is unchanged by the closing round: ADVANCE.**  One extra note for the roadmap: with the
read at 0.05 s the remaining round trip on `Report.e` is 0.52 s inference + 0.30 s debounce, so the
two items the arithmetic now favours are 7.4 (the adaptive debounce, whose Decision (e) precondition
this item just discharged) and whatever reduces the 0.52 s — not a second parse optimisation.  7.3
should be re-scoped or dropped against 7.1b's result rather than budgeted beside it, which is what
the roadmap's own NOTE (iii) already says.

## 10. RE-RUN RECIPE (for whoever checks this review)

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    S=<scratch>/review-7.1b
    # the pre-change side, built from HEAD, independent of the implementer's snapshot
    mkdir -p $S/pre && git archive HEAD | tar -x -C $S/pre && (cd $S/pre && sbt -batch core/compile core/copyResources)
    ERMINE_CP=$S/cp-before.txt tracker/tools/corpus-run.sh --batch $S/corpus-before   # and cp-after.txt
    for f in $S/corpus-{before,after}/*.out; do python3 $S/norm.py ...; done; diff -rq $S/cmp2-before $S/cmp2-after
    java -cp "$S/classes:$(cat tracker/repl-classpath.txt)" scratch71b.Diff71b 71  --diags --audit
    java -cp "$S/classes:$(cat tracker/repl-classpath.txt)" scratch71b.Diff71b 913 --diags
    java -cp "$S/classes:$(cat tracker/repl-classpath.txt)" scratch71b.Diff71b 20260911 --diags
    java -cp "$S/classes:$(cat tracker/repl-classpath.txt)" rev71b.Attack     # the eleven constructed attacks
    java -cp "$S/classes:$(cat tracker/repl-classpath.txt)" rev71b.Crlf       # CRLF vs LF reuse
    java -cp "$S/classes:$(cat tracker/repl-classpath.txt)" rev71b.Hdr        # the header's 8 ms, a new import
    java -cp "$S/classes:$(cat tracker/repl-classpath.txt)" rev71b.Heap10     # ten open documents
    TAG=r ORDER=ab PASSES=2 $S/ab.sh                                         # the A/B, reverse order
    TAG=p EDIT_LINE=1592 EDIT_ANCHOR=toEither# ORDER=ab PASSES=1 $S/ab.sh     # the p99 site, end to end

`<scratch>/review-7.1b/` holds `pre/` (my HEAD build), `cls-before`/`cls-after`/`cls-after2` with
their classpath files, the four A/B logs and the two p99 logs, the three differential transcripts plus
the post-fix one, `attack.txt`, `crlf`/`hdr`/`miss`/`heap`/`heap10` outputs, `tier2.log`,
`rt-alone.log`, both corpus runs with their normalised copies, `suites.log`/`suites2.log`,
`g1-validate.log`/`g1-validate2.log`, and `Attack.scala` / `Crlf.scala` / `Hdr.scala` / `Heap10.scala`
/ `norm.py` / `ab.sh` / `dotc.sh`.

STOP after this report.
