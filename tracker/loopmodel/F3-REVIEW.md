# F3 — independent review

Independent review of stage F3 (`tracker/loopmodel/briefs/brief-F3.md`, report
`tracker/loopmodel/F3-FIXES.md`, outcome GREEN), against
`tracker/loopmodel/briefs/brief-F3-review.md`.  Tree `/home/dmitry/research/ermine/ermine-scala`,
HEAD `d837357` plus the UNCOMMITTED F3 deliverables.  Reviewer scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-F3/`.  No commits; nothing edited outside that
scratch and this file; every `.ei` I caused deleted.

## VERDICT: FIX-THEN-ADVANCE

**All seven fixes are correct and each is independently re-reproduced here, before and after.**  I
found no defect in any of them, and I could not break the K-1 guard: I built a compiler with only
`&& ss.length == cs.size` deleted and it ACCEPTS an unsatisfiable partition that the shipped build
rejects, so the length test is load-bearing exactly as claimed (§1).

**What must be fixed before this is committed is the measurement of K-1's blast radius**, which
three documents now assert — `F3-FIXES.md` §3.1/§3.4, `ROSE-COMPARISON.md` §3 Rank 1, and the new
dated note in `ROW-CONSTRAINT-STATE.md`.  "16 of 18 groups byte-identical segment for segment;
eight segments moved" is wrong twice: it is 11 segments in 3 groups by the implementer's OWN
instrument (the `incomplete` group was never compared), and 402 segments in all 18 groups under a
comparison that includes the ten record kinds that instrument silently skips.  Two number tables
also do not match the artifacts they cite.  None of this changes the verdict on the CHANGE; all of
it changes what two permanent tracker files will say forever.

### On the judgement call (§2 in full)

The mechanism the implementer names — "the id base shifts" — **is not the operating mechanism**, and
the evidence refutes it: I compared the `sin` supply bounds of all 3,205,346 segments and 17 of the
18 groups have none — the base moves by one id in 59 `incomplete` solves the report never compared,
and in none of the eight segments it is explaining — while ticket B6's blame-clause instability
(which DOES follow the id base, and which I reproduced: 13 modules on the shipped build) fires
**zero** times on the K-1-only build.  The real
mechanism is a hash-set iteration cascade that the compiler's own instrument documentation spells
out (`Exists.apply` puts the constraint list through `p.toSet.toList`), plus a genuine, intended
deletion visible in the `detm` records the instrument does not compare.  **The conclusion the
implementer drew is nevertheless right** — nothing observable moves on the isolated build — so this
is not a REDO.  It is FIX-THEN-ADVANCE because the call was made on a picture that was wrong by a
factor of ~50, which is the one thing a stop would have surfaced.

### To fix before committing

1. **N-1** — correct the segment count and group list in all three documents, and say which record
   kinds the comparison covers.  Withdraw "no id was consumed or spared anywhere": 59 `sin`
   records in the `incomplete` group carry a supply-lo one lower after the fix.
2. **N-2** — correct the 1,516 / 769 / 23 shape table to 1,896 / 389 / 23 in all three places, and
   add the positive result it hides (no firing had overlapping parts; every one-part firing was a
   true identity).
3. **N-3** — soften or measure `ROW-CONSTRAINT-STATE.md`'s "no … published interface moves"; no
   `.ei` snapshot was taken on the K-1-only build, and one signature's residual partition count
   does move there.
4. **N-5** — fix the position in the new corpus module's own comment (49:7 -> 50:7).
5. **N-8** — give `Time/Helpers.e`'s eight free-result-row helpers (and `Time/Signatures.e`'s three
   `yearFrac365*`) a ticket entry of their own; they are currently parked inside a FIXED entry.
6. **N-9** — "a renaming" is the wrong description of the two large `other` bindings; their
   partition shapes change (equivalently, not weakly).
7. **N-7** — the count slips ("twelve" bindings, "seven" helpers, "12 new" properties, the
   existential counts, the `Time-shouldfail` delta gloss).

N-4 and N-6 are notes for the next stage rather than blockers.

Every gate in §4 was re-run and every one passes at the reported number, including
`core/test` **937 / 1 failed / 936 passed** with the documented `Constraints.disjunction`
starvation, `TestLoopTrace` **720/720 skip 0**, the corpus **85 / 69 / 0 / 154** with
verdicts byte-identical to the implementer's, the model agreeing on `top` / `Present` /
`Algebra` / `Time`, byte-identical SQL renderings, both smokes, and the `.ei` sweep.

## Findings

Ranked; `CONFIRMED` = I ran it.

### N-1 (CONFIRMED, blocking-for-prose) — "eight segments of 3.2 M" is an instrument artifact; the real number is 402, in all 18 groups

`§3.1`, `§3.4(a)`, `ROSE-COMPARISON.md` and `ROW-CONSTRAINT-STATE.md` all say the K-1-only build
leaves **16 of 18 groups "identical segment for segment"** and moves **8 segments**.  That is the
output of `<F3-scratch>/trace-ab.py`, whose `KEEP` tuple is
`("step","learn","in","inpart","sat","solve","tnorm")`.  The `Algebra` trace carries **sixteen**
record kinds (`concr detm ex in inpart learn ramb rsound sat scon sin slbl solve splice step
svar`); `tnorm` is not among them, so the tool compares **six of sixteen**.  It never compares
`slbl`, `svar`, `scon`, `ex`, `concr`, `splice`, `detm`, `ramb` or `rsound`, and of `sin` it reads
only `nCs`, never the supply bounds or the block — so three of the four REPLAY records the Lean
model consumes, and both of the R3/S2 records added specifically so that residual and ambiguity
changes would be visible, are outside its field of view.  The report does not say so.

I re-diffed the implementer's own preserved traces (`lt-pre/traces` vs `lt-k1/traces`) comparing
**every** record and masking only `rsound ok`'s last field, which is wall-clock microseconds
(`Subst.scala:1429`).  Noise floor first: the implementer's own same-build control pair
(`lt-ctl1` vs `lt-ctl2`) is **IDENTICAL in 101,005 / 101,005 `Algebra` and 131,358 / 131,358
`Present` segments** under this comparison, so every difference below is the build.

| group | differing segments (raw) | group | differing segments (raw) |
|---|---|---|---|
| Ai | 30 | Present | 51 |
| Algebra | 60 | Present-shouldfail | 4 |
| Algebra-shouldfail | 1 | shouldfail | 2 |
| boot | 1 | shouldfail-controls | 2 |
| bugs | 1 | Time | 63 |
| guide | 1 | Time-shouldfail | 5 |
| incomplete | 123 | top | 4 |
| Lang | 7 | Wide | 43 |
| Lang-shouldfail | 2 | Wide-shouldfail | 2 |

**402 segments, and every one of the eighteen groups moves — not two.**  Classified
(`review-F3/perm-ab.py`: same per-kind record counts, and same record multiset once numeric ids
are erased): **305 CONTENT-DIFFERS, 96 PERMUTATION-ONLY, 1 KINDCOUNT-DIFFERS**.

The single most common difference is the same one in EVERY group, including `boot`, `bugs` and
`guide`, whose only differing segment it is: at
`core/target/.../modules/Relation/Op.e(165:3)` the `detm` record reads `… 2 6 6` before the fix
and `… 2 6 5` after — one fewer partition in the residual `Subst.reduce` has accumulated, in the
stdlib boot itself.  That is K-1 doing exactly what it was written to do, and the report never saw
it.

The good news, and it is real: the dominant class is `detm` — R3's determinacy record, written by
`Subst.reduce` at every splice on the residual it has accumulated — whose last field `nParts`
**decreases**: `6 -> 5` at `Relation/Op.e(165:3)`, `7 -> 5` at `Wide/Helpers.e(201:1)`,
`4 -> 3`, `3 -> 2`, `3 -> 0`.  That is the fix WORKING: the trivially-true concrete partition is
no longer in the residual.  It is exactly "the disappearance of a concrete-identity constraint" —
in a record the instrument was not looking at.  So the finding is against the measurement and the
three documents that repeat it, not against the change.

Concretely wrong sentences that should not be committed as they stand:
* `F3-FIXES.md` §3.1 table: "**16 of 18 groups byte-identical** segment for segment".
* `F3-FIXES.md` §3.4(a): "`Present` (3 of 131,358) and `Algebra` (5 of 101,005) differ … the other
  sixteen groups are identical segment for segment".
* `ROSE-COMPARISON.md`: "16 of the 18 groups are identical segment for segment".
* `ROW-CONSTRAINT-STATE.md`: "**16 of 18 groups identical** segment for segment".

### N-1 addendum (CONFIRMED) — even by the implementer's OWN instrument the answer is 11 segments in 3 groups, not 8 in 2

I ran `trace-ab.py` — the implementer's script, unmodified — over all eighteen groups of
`lt-pre` vs `lt-k1`.  Fifteen groups come back `IDENTICAL`; `Present` gives 3 and `Algebra` gives
5, as reported.  **`incomplete` gives 3 more**:

```
incomplete   segments=1905368  IDENTICAL=1905365  OTHER=3  (concrete identities in the PRE trace: 0)
```

all three at `core/examples/incomplete/RevenueShare.e(108:12)`.  So §3.1's "16 of 18 groups
byte-identical" and §3.4's "eight segments" are wrong even on the report's own terms: `incomplete`
was either never compared or its line was dropped.  And the three are not the same kind of thing
as the other eight:

* **the id base really does move here.**  I compared the `sin` records — the `Supply`'s bounds at
  the top of every solve — of all 3,205,346 segments.  Seventeen groups: **zero** differences.
  `incomplete`: **59**, starting at segment 1088215, every one of them `suLo` exactly one LOWER
  after the fix (`304928 305151 6 …` -> `304927 305151 6 …`), until the next block boundary
  absorbs it.  `trace-ab.py` cannot see this: its `IDENTICAL` test compares only `fa[2]`, the
  constraint count, and never `suLo`.  `ROW-CONSTRAINT-STATE.md`'s new note generalises from
  `Algebra` — "the `sin` supply-lo sequence is identical across all 101,005 `Algebra` segments,
  **so no id was consumed or spared anywhere**" — and the second half of that sentence is false.
* segment **1088214** fires a DIFFERENT RULE: pre `step concrete ^A1 <- (,pctOfRegion)`, post
  `step common:#0 ^A1 <- (,productLine salesRep amount bookingMonth region)`, and the segment
  carries `learn` 448 pre against 446 post (every other record kind identical in count, including
  `sat` 26, `splice` 16 and `solve` 1).  A different derivation reaching the same conclusion is
  more than a permutation.

Caveat, stated because the implementer's is: neither of us ran a same-build control on
`incomplete` (the `Algebra`/`Present` control pair does not cover it), so I can rule out
run-to-run noise for the other 399 differences and not for these 3.  The segment counts are
identical (1,905,368 both sides) and both runs report `timeouts=0 dropped=0`, which is consistent
with determinism but does not prove it.  Either way the report's claim needs the number and the
group list corrected, and the "no id base moves" sentence withdrawn or qualified.

### N-2 (CONFIRMED) — §3.4's shape table does not match the artifact it cites

The table says the guard's 2,308 firings in `Algebra` are **1,516** pure identities, **769**
two-part concrete splits and **23** empty-row cases.  Parsing the cited artifact
(`<F3-scratch>/k1fire-algebra.txt`, 2,308 `[K1FIRE]` lines) gives **1,896 / 389 / 23**.  The total
is right, the split is not, and the wrong split is copied verbatim into `ROSE-COMPARISON.md` and
`ROW-CONSTRAINT-STATE.md`, where it becomes permanent.

The same parse is a useful positive result and belongs in the report: of the 2,308 firings,
**every** one-part firing is a true identity (part set == whole set) and **no** two-part firing
has overlapping parts, so the guard never once fired on anything but a genuine partition of a
concrete row.

### N-3 (CONFIRMED) — a published signature's residual moves under K-1 alone, and the isolation never took an `.ei` snapshot

`ramb` is written by `Subst.mkSimplified` for every published signature carrying a row constraint.
A global multiset diff of `ramb` records (ids erased) between the pre build and the K-1-only build
is empty in seven of eight groups and, in `Present`, differs in exactly one binding:

```
only-A: ramb Layout/Report/Relation.e(38:1) cutoffGroupedFldsPosNegRel'  40 34 34 33 27
only-B: ramb Layout/Report/Relation.e(38:1) cutoffGroupedFldsPosNegRel'  40 34 34 33 26
```

— the residual's partition count drops 27 -> 26.  `ROW-CONSTRAINT-STATE.md`'s new note says "no
verdict, message or published interface moves because of them", and §3.1's isolation table has no
`.ei` row: the K-1-only build's published interfaces were never captured.  (The SHIPPED build's
`.ei` for that binding is 26 partitions on BOTH sides, which I checked by hand, so the published
type very likely does not move — but the claim as written is not measured.)

### N-4 (CONFIRMED) — the `.ei` gate covers about half the healthy corpus, including the module A3/A4 changes

The report's §5 admits `ei-sweep.sh` hoists only `Ai/Common.e`.  The magnitude is not stated.  In
the implementer's own chunk logs there are **59 `Module not found` failures on the pre side and 60
on the post side** (`Wide.Helpers` 12/13, `Lang.Helpers` 13/13, `Algebra.Helpers` 13/13,
`Present.Helpers` 10/10, `Time.Helpers` 9/9, plus `Ai.Common` and `YahooExtras` once each).
Counting captured interfaces against corpus files: **45 of the 92 healthy (non-`shouldfail`,
non-`incomplete`) corpus modules produce no `.ei` at all**, on either side — among them
`Time/FiscalTree.e`, the one example module this stage edits for A3/A4, and `Wide/Signatures.e`
and `Lang/Signatures.e`.  "Nothing weaker anywhere in the sweep" is true of the 224 interfaces the
sweep captured and says nothing about those 45.

### N-5 (CONFIRMED) — the new corpus module's own comment pins the wrong position

`core/examples/Time/shouldfail/date01_datediff_free_row.e` says "the POSITION and the verdict are
what this module pins" and then gives

```
core/examples/Time/shouldfail/date01_datediff_free_row.e:49:7: … 'startDate': the whole contains
it but no part does
```

The offending binding `bad` is on **line 50**, and what the build actually prints is

```
core/examples/Time/shouldfail/date01_datediff_free_row.e:50:7: Row partitions are unsatisfiable at
field 'Time.Shouldfail.Date01.endDate': a part contains it but the whole does not
```

The field and the clause are allowed to move (B6, and the comment says so); the position is not,
and it is off by one.

### N-6 (CONFIRMED, low) — three of the seven new date properties only discriminate on a non-UTC host

`TestDateAndScan`'s `monthNums` / `dayNums` / `yearNums`, `excelJan` / `periodQ2` and the two
quarter properties run under the HOST's default zone.  On a UTC build machine they pass on the
pre-fix compiler too — the A3 half of the regression guard evaporates.  Only "the accessors ignore
the JVM default timezone", which sets four zones explicitly, is host-independent.  It is also the
one that mutates `TimeZone.setDefault` globally; `build.sbt` does not disable parallel test
execution, so that write races every other test in flight.  Both are worth one line each in the
test's comment, or the zone list should be pushed into the three Ermine-level properties.

### N-7 (CONFIRMED, low) — small count slips in the prose

* `F3-FIXES.md` §3.3: "every one of the **twelve** non-identical bindings is accounted for below".
  The sweep has 6 `other` + 3 `only-in-B` = **nine** bindings in the table, plus 48 `order-only` and
  6 `alpha-equivalent` absorbed as churn.  Neither reading gives twelve.
* `F3-FIXES.md` §3.2 and the plan row: "925 before this stage + **12 new** (5 in `TestInMemoryScan`,
  7 in `TestDateAndScan`) = 937".  `TestDateAndScan` declares **ten** properties, not seven, so the
  decomposition is **922 + 15 = 937** — and 922 is exactly the total R3's plan row records, which is
  the check the sentence was trying to make.  The headline 937 is right.
* `F3-FIXES.md` §3.3's existential counts include the outer `forall` binders: `valueAsOf` binds
  **11** existentials (reported 15), `shareOfGroup` **17** (reported 23), `cutoffGroupedFldsPosNegRel'`
  **40** (reported 48 — and 40 is the number R3's own `ramb` record carries as `nEx`, with 34 row
  existentials).  The partition counts in the same table (8 -> 9, 14, 26) are all correct, and I
  confirmed `valueAsOf`'s side B really is side A's set PLUS `t <- (g, c1, r)`, i.e. stronger.
* `F3-FIXES.md` §2 and `TICKET-stdlib-findings.md` B1: "`Time/Helpers.e`'s **seven** date helpers
  declare `forall … out.`" — there are **eight**, all with a genuinely free result row:
  `dayCount`, `yearFrac365`, `monthsBetween`, `monthsSince`, `daysSince`, `daysUntil`, `yearsOn`,
  `yearFrac360` (lines 294, 299, 309, 315, 319, 325, 330, 336).
### N-8 (PLAUSIBLE, ticket) — the `dayCount` hole should have a ticket entry of its own

The brief asks whether §5's `Time/Helpers.e` hole deserves a ticket entry.  **Yes**, for three
reasons.

1. It is currently recorded only INSIDE `TICKET-stdlib-findings.md`'s B1 entry, which is now headed
   **FIXED in `<commit>`**.  Open work parked inside a closed entry is work nobody will find, and
   this one is a real hole: `combine_Op (dayCount_H …)` over a relation carrying neither date still
   type-checks and still fails at header computation, which is precisely the defect B1 was raised
   for.
2. The entry undercounts it: there are **eight** such helpers, not seven (N-7).
3. `core/examples/Time/Signatures.e` carries the same free result row in `yearFrac365Full`
   (`out <- (out)`, a tautology), `yearFrac365Deduped` and `yearFrac365Simple` — the last of which
   is explicitly labelled "What `Helpers.e` ships, specialised to `Date`".  Those three are
   deliberate S3 residual exhibits rather than oversights, but they mirror `Helpers.e` line for
   line, so whoever tightens `Helpers.e` has to decide about them too, and no document names the
   file.  (I checked the rest of `Time/Signatures.e`: the `pctChange*` and `safeDiv*` families all
   constrain `out` — `out <- (cur, prior)`, `out <- (num, den)` — so the hole there is exactly the
   three `yearFrac365*`.)

One short entry (say `B1a`) naming `Time/Helpers.e`'s eight, `Time/Signatures.e`'s three, and the
untouched primitives `dateDiff#` / `dateAdd#` is the right home.

### N-9 (CONFIRMED) — two `.ei` bindings §3.3 calls "a renaming" are not renamings

§3.3 dismisses `shareOfGroup` (`incomplete/RevenueShare`) and `cutoffGroupedFldsPosNegRel'`
(`Layout.Report.Relation`) as "a renaming … far past the classifier's budget".  The constraint
COUNTS are indeed unchanged (14 and 26), but the shapes are not.  Partition-arity histograms of the
published text:

| binding | pre | post |
|---|---|---|
| `shareOfGroup` | `{2: 9, 3: 5}` | `{2: 9, 3: 4, 4: 1}` |
| `cutoffGroupedFldsPosNegRel'` | `{1: 1, 2: 14, 3: 6, 4: 3, 5: 1, 6: 1}` | `{1: 1, 2: 14, 3: 5, 4: 3, 5: 2, 6: 1}` |

In `shareOfGroup` the difference is visible by hand: side A publishes `g <- (o, b, f)` where side B
publishes `i <- (o, f, e, d1)` — the same partition with `b` SUBSTITUTED into its own parts (`b <-
(e, d1)`, which both sides also publish).  The two are inter-derivable, so nothing is weaker; but
they are not alpha-variants, which is why `ei-classify.py` — correctly — refuses to certify them
and prints them in full.  The right wording is "an equivalent residual published in a more
expanded form", and it should say that the equivalence was argued rather than checked, because
neither the classifier nor I proved it for the 26-partition one.

---

## 1. The seven defects, before and after

Method note: `git stash` was not available to me, so where a "before" needed a different compiler I
built one — `git show HEAD:<path>` into scratch, compiled with `dotty.tools.dotc.Main` against
`target/ermine-classpath` into a scratch output directory, and that directory PREPENDED to the
classpath of `com.clarifi.reporting.ermine.session.Console`.  That gives a genuine pre/post pair
differing in exactly one source file, without touching the tree.  It is how K-1 below is measured
both ways.

### A1b — the three `MapView` equality/hash sites

**CONFIRMED, both ways, with a control I built myself.**  On the shipped build all five
`TestInMemoryScan` properties are `OK, proved property`.  I then took the CURRENT
`SqlScanner.scala` and `relational/package.scala`, reverted ONLY the three `.toMap`s (keeping the
`private[relational]` widening, which cannot change behaviour), compiled the two files against the
test classpath into a scratch directory and prepended it:

```
! the in-memory hash join matches on the key columns: Falsified after 0 passed tests.
  Expected Set(Map(k -> a, l -> 1, r -> 10), Map(k -> b, l -> 2, r -> 20)) but got Set()
! sorting groups by the columns already in order: Falsified after 0 passed tests.
  Expected List("(1,1)","(1,2)","(1,3)","(2,5)","(2,9)")
       but got List("(1,3)","(1,1)","(1,2)","(2,9)","(2,5)")
Found 4 failing properties.
```

Four of five falsified, the fifth (an already-sorted stream) passing on both as designed — exactly
the report's negative-control table.  The mechanism is the one stated: 2.13's `MapView` is a
`View`, which defines neither `equals` nor `hashCode`, so `kr == k` is always false, a `Map` keyed
by a view never hits, and the chunk predicate never groups.  The three `.toMap`s are at
`SqlScanner.scala:649`, `:719-720` and `package.scala:72`, which is what the ticket entry says.

### K-1 — the concrete identity, and whether the length test is load-bearing

**CONFIRMED, both ways, on a build pair differing only in `Type.scala`.**

*The identity reaches the solver before the fix and does not after.*  Probe
`review-F3/p/RvK1.e` (two signatures whose only constraint is a concrete identity, plus the call
sites that discharge them), `-Dermine.rowTrace -Dermine.loadInSeries=true`:

| | `sin` records for the module | solves with `nCs = 1` | `in`/`inpart`/`sat` records naming the module |
|---|---|---|---|
| pre (`HEAD:Type.scala`) | 22 | **2** | **6** |
| post (F3) | 22 | **0** | **0** |

and the pre-fix `in` record is exactly the shape the guard was meant to catch:
`in … RvK1.e(15:17) 0 (|RvK1.bar,RvK1.foo|) (|RvK1.bar,RvK1.foo|)`.

*The `ss.length == cs.size` test is load-bearing.*  Probe `review-F3/p/RvOverlap.e` declares
`((|foo, bar|) <- ((|foo, bar|), (|foo|))) => …` — equal sets, longer list, two parts sharing
`foo`, so the partition is UNSATISFIABLE.

* on the shipped F3 build it is **REJECTED**:
  `RvOverlap.e:14:16: Fields appear twice in row: RvOverlap.foo` (`Subst.normalPart`, `Subst.scala:1813`);
* on a build carrying F3's guard with **only** `&& ss.length == cs.size` deleted, the module
  **LOADS**: `Importing module 'RvOverlap' (0.07 seconds)`.

So without the length test the guard would have answered `Exists` — trivially true — to an
unsatisfiable constraint, and an unsound acceptance would have shipped.  The implementer's claim is
exactly right, and the guard as written is sound: I also checked all 2,308 firings recorded in
`k1fire-algebra.txt` and **no** firing has overlapping parts and **every** one-part firing is a
true identity.

### A4 — `formatQuarter`

**CONFIRMED, before and after in one run** (`review-F3/p/RvDate2.e` recomputes the pre-F3
`getMonth d / 4 + 1` with the 1-based index on the fixed build, so A4 is isolated from A3):

```
old formula   "Q2 Q2 Q2 Q2 Q3 Q3 Q3 Q3 Q4 Q4 Q4 Q4"   nums 1 1 1 1 2 2 2 2 3 3 3 3
new (shipped) "Q1 Q1 Q1 Q2 Q2 Q2 Q3 Q3 Q3 Q4 Q4 Q4"   nums 1 1 1 2 2 2 3 3 3 4 4 4
```

"Q1" was unreachable and January printed "Q2"; all twelve months are right now and `quarter` keeps
its 1-based meaning.  Matches the report line for line.

### A3 — one timezone

**CONFIRMED, before and after, five zones, one JVM** (`jshell` on the project classpath; `d =
YMDTriple(2011,1,1)`):

| default zone | OLD (`java.util.Date`) | NEW (`PrimExprs`) |
|---|---|---|
| America/Denver | y=110 m=11 dd=31 | y=111 m=0 dd=1 |
| UTC | 111 / 0 / 1 | 111 / 0 / 1 |
| Pacific/Kiritimati | 111 / 0 / 1 | 111 / 0 / 1 |
| Asia/Tokyo | 111 / 0 / 1 | 111 / 0 / 1 |
| Pacific/Niue | y=110 m=11 dd=31 | 111 / 0 / 1 |

`PrimExprs.ymdCalendar` reads `YMDTriple.ymdPivotTimeZone`, which is `GMT` — the same zone
`dateFormatterTLV` pins the formatters to and the same zone `YMDTriple.apply`/`unapply` use, so the
choice is the right one and the conventions (`getYear` = year − 1900, `getMonth` 0-based,
`getDate` 1-based) are preserved.  At the Ermine level, on this MDT machine:
`getMonth` `0 1 2 … 11`, `getDate` all `1`, `getYear` all `111`, `formatExcelDate @2011/1/1` =
`"Jan 1"`, `formatPeriodOr "custom" (1 Jan, 1 Apr)` = `"Q2 2011"`, `formatExcelPeriod (1 Jan, 31
Jan)` = `"Jan 1 to Jan 31"` — the report's after-column exactly.  Note that only Denver and Niue
DISCRIMINATE for this literal; Kiritimati and Tokyo agree with UTC before the fix as well, so the
"five zones, one answer" sweep is less sharp than it reads (see N-6).

`Time/FiscalTree.e`'s edit is the right response: the module's whole point was to display the
defect, its ten bindings are values rather than types, and the edit turns the exposé into the
record with an AFTER column.  No signature and no `.ei` byte moves.

### C5 — the three re-exports, and `sumBy'`

**CONFIRMED.**  `git show HEAD:core/src/main/resources/modules/Layout/Scan.e | grep -E
'removeK|removeBy|multiply'` is EMPTY, so the pre-fix `undefined term` is certain; on the shipped
build a module whose whole body is those three names loads and `:type` answers

```
removeK  : forall k z v. Eq k => k -> Scan z (k, v) -> Scan z (k, v)
removeBy : forall v k z. Eq k => (v -> k) -> k -> Scan z v -> Scan z v
multiply : forall t a f z k. (Record t -> a) -> Scan (Report f z) (k, Relation t) -> Scan (Report f z) (k, a)
```

The `.ei` sweep shows the residual shrink and nothing else: `sumBy'` goes `3 -> 2` constraints in
BOTH `Relation.Scan` and `Layout.Scan`, losing exactly `r <- (h, t)` with its two unbound
existentials, and the three re-exports appear as `only-in-B` (see §3).

### C2 — `join1`'s comment

**CONFIRMED** by reading: the comment now matches the constraints (`r <- (k, r1, r2)` is a
partition, so the operands' intersection is exactly `k`), and `join1`'s own published signature is
`identical` in the `.ei` sweep.  (`Relation.ei` as a FILE does move — eight bindings, all
`order-only` or `alpha-equivalent`, which is the id-shift churn the other stdlib edits produce, not
anything C2 did.)

### B1 — `dateDiff`'s signature

**CONFIRMED.**  The new corpus module is rejected at load on the shipped build (see N-5 for the
position discrepancy), and the `.ei` sweep shows the wrapper going from three constraints with a
free `r2` to six with `t <- (ro, so, rs)`, `r1 <- (ro, rs)`, `r2 <- (so, rs)` — strictly stronger,
and identical to `dateAdd'`'s shape one line above.  `corpus-run.sh --batch` moves 68 -> 69
REJECTED with exactly one new verdict line and no other verdict change (§4).

---

## 2. The judgement call: is the mechanism real, and should the stage have stopped?

**Short answer: the CONCLUSION is right, the MECHANISM as stated is not, and the stage should have
stopped just long enough to widen the instrument — not to redo the work.**

### 2.1 The eight are real, reproduced, and are permutations

I re-ran `trace-ab.py` myself on the preserved traces: `Algebra segments=101005 IDENTICAL=101000
OTHER=5 (concrete identities in the PRE trace: 0)` and `Present segments=131358 IDENTICAL=131355
OTHER=3 (concrete identities in the PRE trace: 0)`.
Reading the five `Algebra` ones in full: in each, the `sin` record is byte-identical on both sides
(e.g. `413253 413695 8` at `SoftSchema.e(177:11)`), the `in` multiset is the same two constraints,
and what differs is their order plus a permutation of the ids their existentials drew.  The
`rsound` line that also differs there (`ok 6 2 5 15` vs `ok 6 2 5 17`) is the check's WALL-CLOCK
microseconds (`Subst.scala:1429`) and is noise.

### 2.2 The mechanism is a hash-set iteration cascade, not an "id base shift"

`F3-FIXES.md` §3.4, `ROSE-COMPARISON.md` and `ROW-CONSTRAINT-STATE.md` all attribute the reorder to
the id base moving.  It is very nearly not that: I compared the `sin` supply bounds of all
3,205,346 segments and **seventeen of the eighteen groups have none at all** — the id base moves in
exactly 59 `incomplete` solves (N-1 addendum) and nowhere else, and certainly not in the eight
segments the report is explaining, whose `sin` records are byte-identical.  What actually
happens is written down in the compiler's own instrument documentation
(`RowTrace.scala`, the `scon` paragraph):

> `scon` is one element of the constraint list `PQueue.build` receives, **in the list's order**.
> `eqid` is the index of the FIRST element of the list this one is `equals` to, and `hash` is its
> `hashCode`: **`Exists.apply` puts the list through `p.toSet.toList`, so the order the solver
> actually sees is decided by exactly those two.**

`Part.hashCode` is `3 + 23*lhs.hashCode + 5*rhs.hashCode` (`Type.scala:397`).  Replacing one
element of that `Set[Type]` by an `Exists` changes the set, and a `HashSet`'s iteration order is a
function of its elements' hashes — so the SURVIVING constraints come out in a different order.
The instantiation that follows then mints their existentials in that new order, the ids permute,
and the permuted ids re-hash the next set.  That is content-dependent and local, which is exactly
what the eight segments look like; an id-base shift would be uniform and would show in `sin`.

**The decisive check against the id-base story is ticket B6 itself**, which the brief asks me to
compare with.  B6 says the refutation CLAUSE follows the id base.  On the SHIPPED build 13
REJECTED modules print a different clause and I reproduced that number exactly (`diff` of
`corpus-verdicts.py` over the implementer's `corpus-pre` and `corpus-final`: 13 modules changed,
plus the one added `date01` line, and no verdict moved).  On the **K-1-only** build the same diff
against the pre build is **completely empty** — not one verdict, not one message.  If K-1 shifted
the id base, B6 would have fired.  It did not.  So the report's own §3.4(b) is right that the 13
are B6 following the STDLIB edits, and its §3.4(a) is wrong that the eight are the same mechanism.

### 2.3 Could the collapse change WHICH constraints a solve receives?

For `Subst.solve`'s input: **no, on this corpus.**  Across the 3,205,346 segments of the pre-fix
trace there are ZERO concrete-identity `in` records (I reproduced the count), every one of the 402
differing segments carries the same `nCs`, and the eleven that differ in `in` records (8 + the
three in `incomplete`) carry the same constraint multiset.  `trace-ab.py` would have classified a
genuine deletion as `K1-empty` / `K1-mixed`; over all eighteen groups there are none.

For `Subst.reduce`'s RESIDUAL: **yes, and that is the fix working.**  This is what N-1 found in the
records the instrument skips.  A trivially-true concrete partition that used to survive into the
residual no longer does, so R3's `detm` record — `nParts` on the residual at each splice — drops:
`6 -> 5` at `Relation/Op.e(165:3)` (present in every group that loads the stdlib), `7 -> 5` at
`Wide/Helpers.e(201:1)`, `3 -> 0` at `Wide/BranchDeposits.e(181:25)`.  And `ramb`, the per-published-
signature record, moves once, in `Layout.Report.Relation.cutoffGroupedFldsPosNegRel'`
(27 -> 26 partitions; N-3).

So the honest one-line description of what K-1 does is not "it deletes constraints nothing ever
saw and permutes eight orderings".  It is: **it deletes trivially-true concrete partitions before
they can enter a residual; on this corpus none of them ever reached a solve, the residuals get
shorter in 305 segments across all 18 groups, and the constraint-set hashing that follows permutes
the solver's input order in 96 more, 11 of which show up in the queue's own records.**

### 2.4 Should it have stopped?

The stop rule was "if anything else moves, STOP and report before going on."  An order change in
`in`/`sat` is not a disappearance, so on a literal reading the trigger fired and the implementer
went on — which §5 admits and offers for review.  I would not call that alone a redo: the guard is
sound (§1, proved both ways), nothing observable moved on the isolated build, and the report put
the call where a reviewer would find it.

What does justify **FIX-THEN-ADVANCE** rather than a clean ADVANCE is that the decision was taken
on a measurement that was wrong by a factor of ~50 and whose blind spot was never disclosed.  The
first question a stop would have produced is "how much moved?", and the answer on the table would
have been 8 when the answer is 402 — or 11 on the report's own instrument, once `incomplete` is
included — and it would have surfaced one published signature's residual, a determinacy record in
every group, and the 59 `sin` records whose supply bound really does move.  None of that changes the verdict on the CHANGE; all of it
changes what the three permanent documents should say.

---

## 3. The `.ei` sweep, re-classified

I re-ran `tracker/tools/ei-classify.py` over the implementer's preserved snapshots (`ei-pre`,
`ei-post`, both taken `--batch` with `-Dermine.loadInSeries=true`, `.ei` deleted before each side)
and got a file **byte-identical to `ei-classify.txt`**:

```
interfaces: A 225  B 224  only-in-A ['core_examples_Wide_Leaderboard.ei']  only-in-B -
== 11 of 224 interfaces differ
== bindings by verdict: {'identical': 2450, 'order-only': 48, 'alpha-equivalent': 6, 'other': 6}
```

The sweep's own noise floor is zero, which I re-checked: `ei-classify.py` over the implementer's
same-build control pair gives `0 of 224 interfaces differ`, `{'identical': 2513}` — and
2,450 + 48 + 6 + 6 + 3 only-in-B = 2,513, so the A/B comparison accounts for every binding.

**No binding anywhere is `concrete->polymorphic`** — the classifier's name for a weaker published
type.  Every one of the nine bindings that is not `identical`, `order-only` or `alpha-equivalent`
is accounted for.  I agree with the verdicts on all nine and with the report's DESCRIPTION of
seven of them; the two large ones are described wrongly (N-9):

| binding | verdict | mine |
|---|---|---|
| `sumBy'` (`Relation.Scan`, `Layout.Scan`) | `other`, 3 -> 2 constraints | correct: the vacuous `r <- (h,t)` and its two unbound existentials, gone.  Nothing else in either signature moves |
| `dateDiff` (`Relation.Op`) | `other`, 3 -> 6 | correct, and STRONGER: `r2` free becomes `t <- (ro,so,rs), r1 <- (ro,rs), r2 <- (so,rs)` |
| `removeK`, `removeBy`, `multiply` (`Layout.Scan`) | `only-in-B` | correct: additions |
| `valueAsOf` (`incomplete/RunCalibration`) | `other`, 8 -> 9 | side B's constraint set is side A's PLUS `t <- (g, c1, r)`; a superset is stronger.  B6/E3 already record this residual as a function of the id base |
| `shareOfGroup` (`incomplete/RevenueShare`) | `other`, 14 partitions both | count unchanged, but NOT a renaming: one ternary partition becomes quaternary because `b` is substituted into its parts (N-9).  Equivalent, not weaker |
| `cutoffGroupedFldsPosNegRel'` (`Layout.Report.Relation`) | `other`, 26 partitions both | I counted the published text: **26 `<-` and 40 existential binders on BOTH sides** — but one ternary partition becomes 5-ary (N-9), so "a renaming" is wrong here too.  (And see N-3: on the K-1-ONLY build this binding's `ramb` residual is 27 -> 26, and no `.ei` was taken there) |

**The chunk-hoisting gap: reproduced, and larger than stated.**  `ei-sweep.sh` (copied from
`ei-diff.sh`) hoists `core/examples/Ai/Common.e` into any chunk holding an `Ai/` module and does
nothing of the kind for the other five group libraries — confirmed by reading both scripts.  The
consequence in the implementer's own chunk logs:

| missing import | pre side | post side |
|---|---|---|
| `Wide.Helpers` | 12 | 13 |
| `Lang.Helpers` | 13 | 13 |
| `Algebra.Helpers` | 13 | 13 |
| `Present.Helpers` | 10 | 10 |
| `Time.Helpers` | 9 | 9 |
| `Ai.Common`, `YahooExtras` | 1 each | 1 each |
| **total** | **59** | **60** |

`Wide_Leaderboard` is the only interface whose PRESENCE differs between the sides, which is what
the report says; but the absolute loss is 59/60 chunk failures per side, and counting captured
interfaces against corpus files, **45 of the 92 healthy corpus modules produce no `.ei` at all**
(N-4).  Nothing else is mis-hoisted — the two sides' failure sets are the same modulo the one-file
shift, and I found no interface captured on one side from a differently-composed chunk.  The
`Wide_Leaderboard` story checks out exactly as told: `ei-post.chunk37.log` carries
`Module not found: 'Wide.Helpers'` followed by
`Unable to load module from 'core/examples/Wide/Leaderboard.e'`, and on the pre side the module was
in `chunk36`, which did contain its library.

---

## 4. The gates, re-run

Everything below is my own run on this tree unless the row says otherwise.  One JVM at a time,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`.

| gate | report | mine | verdict |
|---|---|---|---|
| `corpus-run.sh --batch` | 85 / 69 / 0, 154 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** — and `corpus-verdicts.py` over my outdir is **byte-identical to the implementer's `corpus-final`**, messages included | PASS |
| the +1 REJECTED is B1's module and nothing else moves | yes | `diff` of the pre-fix and shipped verdict files: one added line (`date01`), 13 modules with a changed CLAUSE, **zero** changed verdicts — exactly §3.4(b)'s thirteen | PASS |
| the K-1-only corpus | 0 of 153 outputs differ | `diff` of `corpus-verdicts.py` over the implementer's `corpus-pre` and `corpus-k1` is **EMPTY**, messages included | PASS |
| `looptrace-corpus.sh`, `top` | agree = segments, skip 0 | `segments=92707 agree=92707 skip=0` | PASS |
| … `Present` | " | `segments=131392 agree=131392 skip=0` | PASS |
| … `Algebra` | " | `segments=101039 agree=101039 skip=0` | PASS |
| … `Time` | " | `segments=125134 agree=125134 skip=0` | PASS |
| the per-group delta | +10 / +34 / +59 / +350, total +737 | the four groups I re-ran give exactly the post numbers the report claims, and against the implementer's pre-fix run the deltas are +34 / +34 / +34 / +34.  I re-added all eighteen from the two logs: **+737**, and the split into nine `+10`, seven `+34`, one `+59` and `+350` is arithmetically right | PASS (see note) |
| `sql-render.sh` | byte-identical | `diff -rq` of my `sql/` and `out/` against the implementer's post-fix render: **EMPTY**; against their PRE-fix render: **also EMPTY**.  30 names, 15 SQL, 15 tables, the same nine `Mem` walls | PASS |
| `repl-smoke.sh` | 5 of 5, 47 checks | `PASS aliasing (2) pipedeof (12) relations (6) scoping (4) smoke (23)` = **47** | PASS |
| `lsp-smoke.sh` | 98 checks | `PASS lsp (98 checks)` | PASS |
| the `.ei` sweep | 11 of 224, nothing weaker | `ei-classify.py` re-run: output **byte-identical** to `ei-classify.txt`; no `concrete->polymorphic` anywhere (§3) | PASS |
| `TestInMemoryScan`, shipped build | 5 pass | **5 of 5 proved** | PASS |
| `TestInMemoryScan`, NEGATIVE CONTROL | 4 falsified | I rebuilt the control myself — current `SqlScanner.scala` and `package.scala` with ONLY the three `.toMap`s reverted, the `private[relational]` widening kept, compiled against the test classpath and prepended — and got **"Found 4 failing properties"** with exactly the predicted answers: the hash join `got Set()`, sorting `got List("(1,3)","(1,1)","(1,2)","(2,9)","(2,5)")`; the fifth (already-sorted stream) passes on both | PASS |
| `TestLoopTrace` | 720/720, skip 0 | from my own `core/test` run: `[loop model trace] 720 solves (20 seed x 6 bases + 600 generated); 720 segments; 720 agree; #summary segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`, and the two controls still disagree (46 of 720 at id base +1, 58 with `--flags=nongen`) | PASS |
| `sbt core/test` | 937 total, 1 failed, 936 passed | **`Failed: Total 937, Failed 1, Errors 0, Passed 936`** in 19:12; the one failure is `! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.` — the documented generator starvation.  All 937 are ScalaCheck properties, and **15** of them are this stage's two new suites (5 `in-memory scan paths (A1b)` + 10 `Date, dateDiff and Layout.Scan (F3)`), so the decomposition is 922 + 15, not the report's 925 + 12 (N-7) | PASS |
| `perf-bench batch -n 3` | 11.07 -> 11.17 s | **not re-run** — the machine was not quiet enough for the harness's own `load < 1.3` gate during this review, and a 0.9 % move a third of the run-to-run spread is not worth a contested measurement | not taken |
| `incomplete` model replay | not taken | **not taken** (same reason as the implementer: hours) | not taken |

Note on the delta gloss: "+34 in every group that also loads `Layout.Scan`" holds for six of the
seven `+34` groups (`top`, `Ai`, `Present`, `Time`, `Algebra`, `Lang`, and `Algebra-shouldfail`
through `Algebra/Helpers.e`), but `Time-shouldfail` is `+34 + 25` and its four modules import only
`Layout`, `Time.Helpers`, `Prelude`, `Relation.Op` and `Syntax.Relation`, none of which reaches
`Layout.Scan` by grep.  The DELTAS are measured and add up; the one-line explanation for them does
not cover that group.

---

## 5. The `MapView` sweep, spot-checked

The counts hold: `grep -rn "mapValues\|filterKeys\|\.view" core/src/main/scala` is **115** hits,
**9** of them in `Access.scala`, whose body really is inside a block comment (`/*` on line 2, `*/`
on line 359) and which produces **no class file** (`find core/target -name 'Access*.class'` is
empty).

Seventeen sites (thirteen rows) checked by hand, chosen to include every one where a lazy result
could plausibly be compared, hashed or used as a `Map` key:

| site | what it does | verdict |
|---|---|---|
| `Typer.scala:182` | `pivCols` is a `MapView`; only `keySet`, then `passCols ++ pivCols` into a strict `Header` | safe |
| `Reporting.scala:86` (`alignMap`) | `(m2 -- m.keySet).mapValues(oneR)` is `++`-ed onto a strict `Map`; the method returns `Map[K,V3]` | safe |
| `Optimizer.scala:310` | `.mapValues(...).toList` | safe |
| `Optimizer.scala:316` | `.filterKeys(...).toMap` | safe |
| `SqlScanner.scala:504` | `.view.map{...}.foldLeft(...)` | safe |
| `SqlScanner.scala:1035` | `.mapValues(...).toMap` | safe |
| `SqlScanner.scala:524`, `:557`, `:868`, `:973` | `Reflexivity.filterKeys`, i.e. `util.Keyed`'s OWN strict `filterKeys(A => Boolean): C[A]` | not `Map#filterKeys` at all |
| `Graph.scala:68` | `PartitionedSet`'s own override, body `(posns filterKeys p).toMap` | safe, and strict |
| `Graph.scala:109` | `posns ++ (… mapValues (tick +))` onto a strict `Map` | safe |
| `Graph.scala:138` | `posns.mapValues{…}.toMap ++ …` | safe |
| `Predicates.scala:187` (`group`) | `groupedPcs` is a view; only `keySet` and `getOrElse` | safe |
| `Predicates.scala:205` (`combineAll`) | `comb` is a view; only `collect{…} toMap` | safe |
| `KeyValueTabular.scala:73/75` | `a.view map … collect …` into `binaryReduce` | safe |

I then swept for the residue directly — every `filterKeys`/`mapValues` in `core/src` whose line
does not also contain `toMap`/`toList`/`toSeq`/`toSet`/`foldLeft`/`values`/`keySet` — and every hit
is one of the rows above or a `Keyed` override.  **No counterexample found; the sweep stands.**
The three fixes themselves are right: `.toMap` at the pivot's bootstrap key, at both of
`Tee.hashJoin`'s key functions, and on both sides of `sorting`'s chunk predicate, and I read
`sorting` to check the test drives the right thing (`inorder=[g Asc]`, `outorder=[g Asc, v Asc]`
gives `chunkCols = {g}`, `sortCols = [(v,Asc)]`, so the property's expected grouping is correct).

---

## 6. The prose

**The six ticket entries** (`TICKET-stdlib-findings.md` A1b, A3, A4, B1, C2, C5) are accurate,
specific and leave the hash as `<commit>` as instructed.  I checked every line number they cite on
the post-fix tree: `SqlScanner.scala:649` is the pivot's bootstrap key, `:719-720` are the hash
join's two key functions, `relational/package.scala:72` is the sort's chunk predicate — all three
correct.  A3's list of behaviours that change is right and complete as far as I can check: the
three accessors, `Date.formatExcelDate` (`Date.e:69-70` reads them), `Date.quarter`/`formatQuarter`,
`DateRange.formatPeriod`/`formatPeriodOr`/`formatExcelPeriod` (`DateRange.e:25`), and
`core/examples/Yahoo.e:76-78`, which really does write `getYear d + 1900` — so the
year-minus-1900 convention was load-bearing and keeping it was the right call.  Two count slips are
N-7.

**The `corpus-run.sh` comment** is now correct: I counted the corpus directory by directory and got
15 / 11 / 11 / 3 / 13 / 6 / 11 / 4 / 14 / 6 / 13 / 7 / 40 = **154**, exactly the note's numbers,
and the note now says the counts are a note rather than a check.

**The plan row, the state-file note and the memo's K-1 note** are the three places N-1 and N-2 need
applying.  All three repeat "16 of 18 groups identical segment for segment" and the 1,516 / 769 / 23
split; the state-file note and the memo are permanent records, so the wrong numbers should not be
committed.  The state-file note is otherwise a good one — it is additive, dated, changes no
decision, states the trap ("no concrete-identity constraint in the row trace does NOT mean
`Part.apply` never sees one"), and names what is still open in the same family (`a <- (a)` at
`Part.apply`, and `Part.isTrivialConstraint`).  Two sentences in it are not measured and should be
softened or measured: "no verdict, message or published interface moves because of them" — the
first two I reproduced (the K-1-only corpus diff is empty), the third was never measured (N-3).

**`§5`'s "not done" list** is honest and I agree with every item on it, including the one gate not
taken.  Its `Time/Helpers.e` entry should become a ticket entry of its own — see N-8 for why and
for the two things it currently gets wrong (eight helpers, not seven; and `Time/Signatures.e`,
which nothing mentions).

---

## 7. What I did not do

* **`perf-bench batch -n 3`** — not re-run; the machine did not stay under the harness's own
  `load < 1.3` gate while the review's own runs were in flight, and the reported move (11.07 ->
  11.17 s, 0.9 %, a third of the run-to-run spread) is not a number a contested measurement would
  improve.
* **The `incomplete` group's Lean replay** — not taken, for the reason the implementer gives
  (hours).  I did compare its COMPILER traces pre/post, which is what produced the N-1 addendum.
* **A same-build control on the `incomplete` trace** — not taken (≈10 minutes per side).  The
  noise floor is established on `Algebra` and `Present` only, from the implementer's own
  `lt-ctl1`/`lt-ctl2` pair, where my byte comparison gives 101,005/101,005 and 131,358/131,358
  IDENTICAL.

## 8. Reviewer artifacts

All in `/home/dmitry/.claude/jobs/880c725d/tmp/review-F3/`, none of it in the repository:

| file | what |
|---|---|
| `raw-ab.py` | pre/post segment diff over EVERY record kind, masking only `rsound ok`'s micros |
| `perm-ab.py` | classifies a differing segment as `PERMUTATION-ONLY` / `CONTENT-DIFFERS` / `KINDCOUNT-DIFFERS` |
| `kinds-ab.py`, `detm-ramb.py`, `ramb-ab.py`, `kindcount.py`, `seg.py` | the per-record-kind, `detm`, `ramb` and single-segment views |
| `rawall.log`, `permall.log`, `traceab-incomplete.log` | the 18-group results |
| `patch/Type.scala`, `patch/TypePre.scala`, `out/`, `outpre/` | the two counterfactual compilers (length test deleted; `HEAD`'s dead guard) |
| `patchA1b/`, `outA1b/` | the A1b negative control (three `.toMap`s reverted, widening kept) |
| `p/RvDate2.e`, `p/RvScan.e`, `p/RvK1.e`, `p/RvOverlap.e`, `a3.jsh` | the probes |
| `gate1.log` … `gate4.log`, `coretest-full.log`, `lt/`, `corpus/`, `render/` | the re-run gates |
| `ei-reclassify.txt` | `ei-classify.py` re-run; byte-identical to the implementer's |
