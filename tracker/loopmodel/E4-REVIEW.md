# E4 review — `core/examples/Present/`: layout, charts, writers, validation and the report combinators

Reviewer's report on stage E4 (`tracker/loopmodel/E4-EXAMPLES.md`, 1,044 lines; group
`core/examples/Present/`, 17 `.e` files, uncommitted). Brief `briefs/brief-E-review.md` with
`$STAGE = E4`, `$GROUP = Present`, on top of `briefs/brief-E-common.md` and `briefs/brief-E4.md`.
Everything below was re-run by me on 2026-09-07 at `a80c5c5` (the Wide group now committed, so
`tracker/tools/sql-render.sh` is in the tree), one JVM at a time with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-E4/`. Every `.ei` I caused is deleted. Findings are
prefixed `M-`.

## Verdict: **FIX-THEN-ADVANCE**

The group is real work and the best of the E-series on subject matter: it documents by example the
half of the language that had none, its helper library is honest and reused, its negatives are
sharp, and every gate I re-ran is green — 11 modules load per file and in one batch, six negatives
are rejected with the recorded diagnostics, and the L2 differential is **0 skipped / 0 hashdiff /
0 eqdiff** on both the positive and the negative trace. What must be fixed before it is committed
is not the Ermine: it is the **arithmetic in three modules' headline numbers**, two **findings that
do not reproduce** (one of which cost the group two signatures it could have written), and the
**census table**, whose two loudest claims are wrong — including the one the brief singled out.

Required fixes are listed at the end (M-1 … M-8 are must-fix; M-9 … M-17 are should-fix).

**Two notes on the ground moving under this review.** (a) While I was measuring, E2's and E3's
groups were committed (`78fc221`, `2c38956`), so `core/examples` is now 354 `.e` files; nothing in
E4's gates is affected — I drove every command with explicit file lists. (b) At 03:30, after every
`bin/ermine` measurement below was taken, someone recompiled the compiler with an uncommitted
change to `Subst.scala` that (i) gives `NormalPart` a `hashCode` consistent with its `equals` (so
permuted duplicate partitions stop being published) and (ii) **deletes the `a <- (a)` tautology
from the residual**. If that change lands, `Present/Signatures.e` needs a revisit: its `taut` /
`tautIsFree` pair and the `c <- (c)` member of `scaledByFull`/`outOfRangeSimple`'s documented
inferred sets are exactly what it removes. The written signatures stay legal; the comments around
them go stale. Flagging it for the orchestrator rather than counting it against E4.

---

## 1. The gates, re-run

| gate | report | mine | verdict |
|---|---|---|---|
| G1(a) per-file load ×10 | all LOADED, 15–21 s wall | all LOADED, 15.8–21.0 s wall | ✔ reproduces |
| G1(b) one batch | 11 modules, 5.93 s of check time | 11 modules, **5.93 s** | ✔ reproduces |
| G1(c) six negatives | rejected, diagnostics verbatim | all six rejected, **all six messages verbatim** | ✔ reproduces |
| G2 differential, positives | 126,260 seg, 0/0/0 | **126,756** seg, 0 skipped / 0 hashdiff / 0 eqdiff | ✔ clean, count differs (M-9) |
| G2 differential, negatives | 59,493 seg, 0/0/0, 1 rejected | 59,493 seg, 0/0/0, 1 rejected, `#REJECTED 59353` identical | ✔ exact |
| G3 census | see §3 | see §3 | ✗ **two headline numbers wrong** |
| G4(b) `.ei` | 11 interfaces, round-trips | 11 interfaces, second `useInterface=true` load re-checks every module | ✔ reproduces |

Per-module batch times I measured (report's in brackets): Helpers 0.94 [0.87], AtomicAndRelation
1.36 [1.34], DrilldownExplorer 0.71 [0.71], FulcrumPanel 0.50 [0.51], SalesDashboard 0.47 [0.48],
Signatures 0.13 [0.14], SortShowcase 0.36 [0.38], StyleGridHeatmap 0.37 [0.36], ValidationReport
0.35 [0.38], VarianceStyling 0.44 [0.45], WriterOutputs 0.30 [0.31]. Nothing near 30 s, nothing
needs `.slow`, no budget diagnostic anywhere in the group.

`sbt -batch 'core/testOnly *TestSurfaceParsers *TestStatementExtents *TestTolerantRead'` (the three
corpus walkers the brief names): **Total 20, Failed 0, Errors 0**, 135 s. The file-count constant
really is gone — `TestSurfaceParsers.scala:99–102` now reads `val expected = moduleFiles.size` with
a `>= 250` floor and an explanatory comment naming this very wave of groups — so the report is
right that E4 needs no wiring line there and that E2's and E3's requests are discharged. **Corpus
size for the record: 354 `.e` files** (161 stdlib + 193 examples, 17 of them E4's) — the report's
333 was taken before the fifth group landed. Cosmetic and not E4's: three
`TestStatementExtents.scala` property *names* still say "(271 files)" though they assert only
`files >= 170`.

I did not re-run the full `sbt core/test` (289 s, and two other agents were writing groups on this
machine); the one failure the report records, `Constraints.disjunction sound`, is documented in
`Constraints.scala`, reads no example file, and is unrelated to this group.

**The negatives are the strongest part of the group.** All six reproduce to the character, at the
recorded line and column, in 0.03–0.06 s, across four refutation classes; and the report's
observation that **only one of six presentation mistakes reaches the row solver** (the other five
are caught by class resolution, unification or row construction) is correct and is a genuinely
useful thing to have measured.

## 2. The `.ei` and the helper library

`Helpers.ei` publishes 34 signatures and I checked each against the source: **no weakening, no
extra constraint, no residual the author did not write.** That claim of the report is true and it
is the most important one in it.

The count paragraph under it is not (M-3). Machine-counted over the published `Helpers.ei`:

| | report | actual |
|---|---|---|
| signatures | 34 | 34 ✔ |
| carrying a row partition | 11 | **12** |
| partition constraints in all | 14 | **15** |
| carrying an existential | 6 | **5** (its own parenthesis lists five) |
| carrying `AsOp`/`AsPresentation`/`Relational` | 16 | **14** |

The twelfth partition-carrying signature is `drilldownOf`, which publishes **two** (`v <- (label,
o)` and `r <- (r1, r2, v)`); `nestedOf` publishes **three**, not the two the report's list says.

Per-module `.ei` signature counts: nine of eleven match; **VarianceStyling is 24, not 21, and
SalesDashboard is 19, not 18** (M-9).

**Helpers as things a user would reuse.** I checked every one of the 34 for a call site outside
`Helpers.e`: **all 34 are called**, 30 of them from at least one report module and the remaining
four (`chartOfAll`, `writtenProfiled`, `relabelled`, `aliasedBy`) from exactly one — which is
honest, since each is the second form of a pair. Nothing is listed-but-uncalled, which is the
defect E3's group had. The heaviest-used are `labelled` (30 uses across 7 modules), `scaledBy` (18
across 5), `withFormats` (17 across 10) and `written` (13). The named five in the brief:
`withFormats` and `chartOf` are the two best helpers in the E-series so far — `chartOf`'s one
signature really is instantiated five ways from one line each, and `withFormats`' `r <- (k, m)` is
the right decomposition of a legend; `keyedGrid`'s three-part `r <- (k, v, i)` is the most
informative single constraint in the group; `nestedOf` is correct but is called once, and its
three published partitions make it the hardest to read; `written` is a four-line helper whose
value is entirely documentary — and, checked against the writers' own source, the documentation is
mostly right (M-6).

`Signatures.e` is good and its two central proofs hold up. I re-derived `unreconciled`'s inferred
constraint set in a module of my own containing nothing else, and it is **11 existentials, 14
constraints, 9 of them partitions** — exactly what the file claims, modulo variable names. The
`chartOf` half — that the inferred type knows *nothing* about rows and the written one is strictly
stronger — is also exactly right, and is the best argument in the group for a hand-written helper
library.

## 3. The census — the two claims the brief asked about

I traced the group myself (`-Dermine.useInterface=false -Dermine.loadInSeries=true
-Dermine.rowTrace=…`, 66 MB), replayed it (`looptrace --replay`, 55 s, clean), and censused it with
`--cycle`, `--depth` and `--mints`. **`--depth` and `--cycle` are modifiers of `--replay`, not
standalone modes**; run alone they print the usage banner, which is worth knowing for the next
reviewer.

| measure | report | mine (final bytes) |
|---|---|---|
| solves attributable to the group | 53,898 | 54,287 |
| **draws per solve, max** | **225** | **218** |
| draws per solve, mean | 0.015 | 0.0149 ✔ |
| solves that draw at all | 266 (0.49 %) | 271 (0.50 %) |
| dequeues (steps), max / total | 79 / 13,608 | **73** / 13,682 |
| chain depth, max | 2 | 2 ✔ |
| **per-key mints, max** | **12** | **1** (see below) |
| `--cycle`'s `maxmint`, max | (reported as per-key mints) | **11** |
| initial mints (`mint0`), max | 4 | 4 ✔ |
| re-minted keys, max | 1 | 1 ✔ |
| `concrete` share of dequeues | 22.6 % (3,077/13,608) | 22.6 % (3,094/13,682) ✔ |
| vocabulary-fixed | 99.81 % | 99.81 % ✔ |
| generative rules | 0.19 % (101) | 0.19 % (105) |
| splits, max / total | 3 / 127 | 3 / 131 |
| resolution steps, max / total | 225 / 447 | 218 / 441 |
| input row variables / partitions / labels, max | 16 / 13 / 30 | 16 / 13 / 30 ✔ |
| decision nodes (states), max | 80 | 74 (`steps` 73) |

### 3.1 The 225-draw solve: the SHAPE is right, the numbers are not, and it is worse than reported

**Confirmed.** The costliest solve in the group is `core/examples/Present/ValidationReport.e(214:14)`
and it is exactly the kind the report says:

```
depth  108415  trySolveOn  core/examples/Present/ValidationReport.e(214:14)  SOLVED
   steps=73 drawn=218 drawn0=0 maxdepth=2 nsplit=0 nres=218
   maxremint=0 maxcremint=1 maxdkey=14 nvars=6 nparts=5 nlbl=4  hist=1:200,2:18
```

**`nsplit=0`, `nres=218`: every draw is a `Resolution` step and none is a split.** That is a shape
the previous corpora did not reach and the report is right to lead with it. The count is **218,
not 225** (M-9), and the site is right.

The report's account of *why* is right in outline and loose in detail: it is one lambda that
projects the parameter record five times — but the five are `p ! pRegion` **twice** (lines 214 and
218, the second inside `selectedEntries`), plus `pAsOfYear`, `pMinAmount`, `pStatus`; four distinct
labels, which is what `nlbl=4` says. Each `p ! f` is a `Has`, each `Has` is an existential
partition, and the solver closes five partitions sharing one left-hand side against one another.

**Is it realistic or an artefact?** I isolated it. `ProbeCascade.e` in my scratch is nothing but a
row of unannotated lambdas projecting one record parameter N times:

| projections | draws (model replay) | steps | splits | compiler |
|---|---|---|---|---|
| 2 | 3 | 5 | 0 | loads |
| 3 | 33 | 24 | 0 | loads |
| 4 | 207 | 65 | 0 | loads |
| 5 | 1,243 | 220 | 0 | loads |
| 6 | **6,795** | 677 | 0 | loads |
| 7 | **35,923** | — | 0 | **REJECTED at 20,009 draws** |
| 8 | **185,848** | — | 0 | **REJECTED** |

(the model replays without the budget, so it reports the count the solve *would* have needed; the
compiler stops at 20,000). Growth is a steady **≈5.3–6× per extra projection**, every draw a
`Resolution`, never a split. And the same five projections under **one written partition**
(`forall r o. (r <- ((| p1, p2, p3, p4, p5 |), o)) => {..r} -> String`) cost **0 draws**.

Seven `p ! field` in one lambda — one line of ordinary Ermine, no helper, no relation, no
presentation — is rejected:

```
ProbeCascade2.e:8:9: Row solver resource limit reached (this is NOT a type error): the row
constraint solver drew 20009 fresh row variables at this signature, past the
-Dermine.solveBudget=20000 limit, so it was stopped rather than left to run.
```

So the shape is **entirely realistic** — it is the production shape the group exists to teach,
params → report — and it is **not** an artefact of `Layout.Validation`. Quite the opposite:
`reportParams`'s concrete four-field row is what holds `ValidationReport`'s cost down to 218 where
the same five projections with an open row cost **1,243**. The 218 is the *cheap* case.

The report's "**budget headroom 89×**" is therefore its most misleading sentence (M-2). The
headroom is not 89× a stable shape; it is a handful of `p ! field` in one lambda, and the group's
own idiom walks toward the cliff — a parameterised report over an open parameter row exhausts the
adopted budget at seven reads, with no relation, no join and no presentation anywhere near it. The
remedy is the one `Helpers.e` preaches everywhere else and `parameterised` does not take: write the
row down. `proj5pinned` costs nothing at all. This belongs in the report as a warning and in a
ticket.

### 3.2 "Per-key mints 12, the first to exceed the round-7/8 maximum of 11" — **refuted, twice**

First, on the final bytes `--cycle`'s `maxmint` is **11**, not 12: it *equals* the round-7/8 figure
rather than exceeding it.

Second, and more importantly, **`--cycle`'s `maxmint` is not a per-key mint count at all**. In
`tracker/lean/Rowpartition/Loop/Cycle.lean:407` it is `maxMint := max rep.maxMint mo.length` where
`mo = mintOrder s` — the size of the *minted variable vocabulary* at a step. The per-key mint
census is `looptrace --replay … --mints`, whose `max` column is "the largest mint count on any one
key". Over this group that column is:

```
max=1   remint=0   cmax=3   cremint=1   keys=3
```

**The true per-key mint maximum in `Present/` is 1.** This is precisely the mislabelling E3's
review recorded as P-18 (`Time` and `Ai` both 1, reported as 4 and 8); E4 has repeated it against a
different column and drawn a headline conclusion from it. The claim "this group is the first to
exceed [11]" must go (M-1). The same paragraph's "decision nodes (states)" is `states`, which P-18
also asked to be called `steps`.

The rest of the census reproduces well, and the honest summary the report draws — presentation
combinators are **narrow and deep** where the relational corpora are wide and flat — survives all
of this, because it rests on `nsplit=0 / nres=218 / nvars=6`, which is true.

Derivation rules over my trace (`rowtrace-summary.py`), report's in brackets: Substitution 945
[946], CommonSubexpression 675 [675], SplitConcrete 225 [217], Resolution 119 [120], Cancellation
29 [30], SplitKeyed 20 [20]; 1,326 [1,324] splices, 1,192 [1,187] changed, 48 [46] dropped, 864
[864] non-conservative.

## 4. The nine findings, each confirmed or refuted

**F1 — the writers all share one Ermine-facing type. CONFIRMED, with two over-claims.**
Every writer constructor in `/home/dmitry/research/ermine/ermine-writers` really does have the
shape `Scanner f -> Runner f -> Writer f z` (HTML → `HJS`, Json/JsonDebug → `Json`, Csv → `Csv`,
JavaFX → `JavaFXNode`, PDF → `HJS` after its two options), so `Helpers.written` is genuinely
writer-generic and the report's central architectural claim holds. But: (a) "**exactly one**
constructor" is wrong — `Layout.Writer.HTML` exports `htmlWriterLocal` *and* `htmlWriterRemote`,
`Json` and `JsonDebug` two each; (b) "**every one of them** defines its entry point with the same
four lines" is wrong — only **four of the six** do (`html`, `json`, `jsonDebug`, `csv`);
`JavaFX.e` exports nothing but the foreign constructor and `PDF.e` exports `pdfWriter`/`writePdf`
and no `harness` entry point at all (`grep -l function3` returns four files); and (c) the report's
table puts `jsonFancy`/`jsonDense` in the *constructor* column, but those are the entry points —
the constructors are `jsonWriterFancy`/`jsonWriterDense`. `WriterOutputs.e`'s own header gets (c)
right for HTML and Csv (`html`/`htmlLocal`, `csv`) and the report's table gets it wrong; the two
disagree with each other. (M-6)

**F2 — the `.ei` printer publishes a FREE row variable. CONFIRMED, and it is general.**
`Helpers.ei` really does print `missingKey : forall (h: rho) a (r: rho). (…, r <- (h, o)) => …`
with `o` bound nowhere. My own two-line module reproduces it:

```
carriesO : forall v o r n. (r <- (v, o), PrimitiveNum n) => Field v n -> n -> Relation r -> Relation r
   published as
carriesO : forall (v: rho) n (r: rho). (Builtin.PrimitiveNum n, r <- (v, o)) => …
```

so it is not a property of those three helpers: **any universally quantified row variable that
occurs only in a constraint is dropped from the quantifier and left free in the printed type.**
The interfaces still round-trip (my second `useInterface=true` load re-checked every module), so it
is a printer defect, not a soundness one — the report's framing is right. Ticket-worthy.

**F3 — `AsOp`-polymorphic inferred signatures are unwritable. CONFIRMED for three of five.**
With each body **alone** in a module (the precaution `Signatures.e`'s own header demands), the
existential class appears for `styledBy` (`exists (AsOp: b). AsOp op, Primitive a`), `hiddenBy`
(`exists (AsOp: b). AsOp op, Relation.Op.AsOp op`) and `outOfRange` (`exists (AsOp: d) (AsOp1: d)
…` with four class applications) — a variable named after the class, of an unnamed kind, with no
source syntax. But **`scaledBy` and `unreconciled` do not show it**: my probe infers
`iScaled : … (c <- (c), Relation.Op.AsOp b, PrimitiveNum a) => …` and `iRecon : … Relation.Op.AsOp
a, … AsOp f, … AsOp d …`, all real classes. So the count is **three**, not five, and
`Signatures.e`'s scaledBy comment ("the `AsOp b` is printed as `(exists (AsOp: d). AsOp b,
Relation.Op.AsOp b)`, TWO copies") is false as written. `Signatures.e`'s header also says "**Four**
of the helpers cannot have their inferred signature written down" and then lists **five** names.
(M-4)

**F4 — `Native.Record.header#` forces the MapView bug. CONFIRMED, and E1's scoping is exact.**
Evaluating `FulcrumPanel.bothHalves` prints `Panic: unexpected runtime value in Record.header# -
MapView(<not computed>)`. The mechanism, read out of
`core/src/main/scala/com/clarifi/reporting/ermine/session/Lib.scala`: `record#` (line **988**)
returns `Prim(m.mapValues(_.whnf))`, and on 2.13 `mapValues` yields a `MapView`; `scalaRecord#`
(1007), `scalaRecordIn#` (1012) and `header#` (**1017**, declared at 1016) all match
`case Prim(_: Map[String,Runtime])`, which a `MapView` is not. E1's review's three `.toMap`s at
**988 / 1007 / 1012** are the right three sites and fixing 988 alone would clear both panics.
Second confirmed site; ticket-worthy.

**F5 — `Console.other` treats `case`/`let`/`where` as substrings. CONFIRMED, characterised, and
the report's example list is wrong.** The minimal input is **one line containing the substring**,
piped with stdin at EOF. `printf 'staircase\n' | bin/ermine`:

```
exit=124 (killed at 60 s)   4,906 `|> ` prompts   19,319 bytes
```

against the control `printf 'staircas\n' | bin/ermine`: `exit=0, 0 prompts`. The loop is
`Console.scala:623–628`

```scala
val verbose = Set("case","let","where")
while ((needMoar || (balanced(input) == Unbalanced) || verbose.exists(input.contains(_))) && !blank) {
  val last = e.readLine("|> "); blank = last == ""; if (!blank) { input = input + "\n" + last }
}
```

with `readLine` (`Console.scala:146–151`) returning **`null`** on `EndOfFileException`. In Scala
`null == ""` is `false`, so `blank` never becomes true; each iteration appends `"\n" + null` — five
characters — and the guard then re-runs `balanced(input)` (a recursive O(n) character walk) and
three `String.contains` scans over the ever-longer string. **The loop cannot terminate**: it is
quadratic in time and unbounded in memory, at ~110 prompts/s here. So it is not merely "floods
`|>`": the session is dead. Two fixes, either sufficient: test the three words as *tokens*, or
treat a `null` read as end of input.

The report's and the README's list of unusable names is wrong twice: **`latest` does not contain
`let`** (l-a-t-e-s-t) and **`casing` does not contain `case`** (c-a-s-i-n-g). I checked `latest`
directly — `printf 'latest\n' | bin/ermine` exits 0 with zero prompts. `complete`, `delete`,
`palette`, `elsewhere` and `showcase` are all genuine. (M-5)

**F6 — the partition blame wording is backwards. CONFIRMED.** `chart01` is rejected at the right
field with "the whole contains it but no part does", and here the part (the series row) contains
`channelName` while the whole (the projected relation) does not. Independent reproduction of E1
§7.5, from a chart rather than a window; ticket-worthy.

**F7 — `Layout.Magnitude` is box sizes, not number scaling. CONFIRMED.**
`core/src/main/resources/modules/Layout/Magnitude.e` is three lines: `import List` and
`export Native.Magnitude`, and `Native/Magnitude.e` is `Magnitude a` (cells / pixels /
dimensionless), `Area`, `Volume`, `erasePhantom`, `MagnitudeList`. There is no numeric scaling in
it. Splitting the brief's `withMagnitudes` into `sizedTo`/`cappedAt` (layout) and `scaledBy`
(relational division) is the right call and is well documented in `VarianceStyling.e`.

**F8 — no type-level syntax for a record over a concrete row. REFUTED — and it cost the group two
signatures.** `Ord {..(| positionName |)}` is indeed a parse error (`expected '=', pattern atom, or
whitespace`, reproduced). But the interface printer's own spelling **works in source**:

```
byPositionRank : Ord (Record (| positionName |))
byPositionRank = fromLess (a b -> positionRank (a ! positionName) < positionRank (b ! positionName))
```

loads in 0.05 s. That is verbatim the `SortShowcase.e` definition the report says "had to be
dropped for this reason" (§6.3, §4.9(5)). The real limitation is narrower and should be stated as
such: **the `{..r}` sugar requires a row *variable*; for a concrete row, write `Record (| … |)`.**
Two signatures should go back into `SortShowcase.e`. (M-7)

**F9 — the `RUnion` cliff does not reproduce on `RUnion2` chained four deep. CONFIRMED.**
`FulcrumPanel.e` chains four `snoc_Brace`s, wraps, pattern-matches, pivots and joins two fulcrums
with `(><)` over a 30-column table, and checks in 0.50 s in batch; its largest solve draws 4.

**The rest of §4.9 and §6, briefly.** `infixl 0 '` (`Function.e:21`) ✔; `List.product`,
`Native.Magnitude.cells`, `Layout.Report.grid` and `Layout.Report.tree` all exist, so §4.9(1)'s
list of taken column names is right ✔; `fromNumericOp` really is the widening ✔; `map` coming from
`Syntax.List` rather than `Prelude`'s unqualified scope is consistent with every module in the
group importing `Syntax.List` ✔. §6.2 (a `StyleGrid` cannot be built from a relation — the type is
a fully materialised `List (Maybe String, List (Maybe String, a))` and nothing in the stdlib folds
a relation into one) and §6.5 (`pivotColumn` fixes the column's value type across the fulcrum) are
**PLAUSIBLE**: both follow from the published signatures, and I did not build a counterexample.

## 5. What can actually be produced without a database — is the report's answer the whole truth?

The report's answer is right as far as it goes and I confirmed both halves: `Layout/Writer.e`
declares `foreign data "com.clarifi.reporting.writers.Writer" Writer (f : * -> *) a` and exports
only `pureW`/`bindW`/`mapW`/`apW`/`runW`/`live`/`orEvent` — **no constructor** — so `Writer f z` is
uninhabited on this classpath and `harness` cannot be reached; and `Scanners.dumpQuery` needs an
emitter but no connection, so the relational half compiles to SQL and runs.

But it is **not** the whole truth, and the report should say so, because the answer changes what a
future stage can attempt (M-8). Two routes exist:

1. **The `Scanner`/`Runner` pair does NOT need a database.** The report says "every constructor of
   both is a database connection" (and `Present/README.md` repeats it). What the modules actually
   say is:

   ```
   Runners.e:   function "…backends.Runners" "SQLite"  sqlite : String -> Runner DB
   Scanners.e:  method  "SQLite"                       sqlite#: ScannersModule -> SMEnv f -> Scanner f
   ```

   A `Runner` is built from a **JDBC URL string**, and `jdbc:sqlite::memory:` is a legal one; the
   driver (`sqlite-jdbc-3.51.1.0.jar`) is already on `target/ermine-classpath`, which is how
   `tracker/tools/sql-render.sh` executes this group's queries today. And every relation in the
   group is a literal, so it compiles to a table-value constructor and needs **no schema** — that
   is precisely why `sql-render.sh` works against an empty database. So a live in-memory
   scanner/runner pair is available now, with no server and no fixture.

2. **The only genuinely missing piece is a concrete `Writer`, and that is a classpath, not a
   language limit.** `Writer` is `foreign data "com.clarifi.reporting.writers.Writer"`, resolved by
   name at load. The CSV and JSON writers have no JavaFX or browser dependency, and their Ermine
   modules are ordinary resources under `writers/{csv,json}/src/main/resources/modules/`. What it
   would take, and nothing more: build those two subprojects in `ermine-writers` (they are
   separate sbt modules), append their jar **and** their `modules/` resource root to
   `target/ermine-classpath`, then call `harness' (sqlite cachedSMEnv) (Runners.sqlite
   "jdbc:sqlite::memory:") csvWriter someReport`.

So the honest statement is not "a `Report` cannot be run here" but **"a `Report` cannot be run on
this build's classpath, and the half that is missing is one jar and one resource root."** A
follow-up stage that puts the CSV writer on the test classpath would turn `written` from a
type-check into a rendering, and would be the single highest-value follow-up this group points at.
I did not build it, as instructed — but the report should stop saying the obstacle is the
database, because it is not (M-6).

I did reproduce the report's SQL route: see §6.

## 6. The modules as programs

### The three best

1. **`ValidationReport.e`** — the only module in the group where parameters, presentation and data
   all meet, and the one that earns its header. `Layout.Validation` is twelve lines of stdlib with
   no example anywhere; this explains it, uses the accumulating applicative, and then makes the
   sharper point that a *data* check is a filter whose result is a relation of the same row, so the
   failures compose by `difference` and reuse the same legend. The fact table is planted with
   exactly the defects the text claims (three impossible FX rates, three null suppliers, one
   line where debit ≠ credit + net) and the SQL run returns exactly those rows. It is also the site
   of the group's one genuinely new solver shape.
2. **`WriterOutputs.e`** — answers the question the whole group is organised around, honestly:
   here is the pipeline, here is the type of every writer constructor, here is the four-line idiom,
   here is why none of it can run, and here is what can. The REPL type of `asDocument` — `(exists
   (b: rho). a <- ((|pMinValue, pRegion, pTitle|), b)) => …` — is the best single demonstration in
   the E-series that a report's parameter contract is a row constraint and is *inferred*.
3. **`FulcrumPanel.e`** — 30 columns, two fulcrum models side by side with the design trade-off
   stated in two sentences ("new quarter in the data, new column in the grid" against "each column
   gets its own format, label and group"), the `RUnion2` chain that settles the Ai README's cliff,
   and a live compiler bug found and documented rather than worked around. Its data is internally
   consistent and its header's "28 columns in the identifier part" checks out.

Honourable mention: `SortShowcase.e` is the best *teaching* module in the group — four things
called a sort, in four modules, contrasted on one table — and would be in the top three but for
the two signatures it dropped on a false premise (F8/M-7).

### The three weakest

1. **`SalesDashboard.e`** — the group's flagship and the module a reader will copy, and its three
   headline KPI tiles are **invented**. `kpi "Net revenue" (currency "USD" 1103283.6)` against a
   fact table whose `netRevenue` sums to **482,408.3**; `kpi "Average order" 73552.2` against
   **32,160.55**. Only `wholeNumber 15` is right. Everything else in the module is meticulous — I
   checked all fifteen rows for units × price = gross, gross − discount = net, net − COGS = margin
   and margin/net = marginPct, and every one holds — which makes the three wrong numbers worse, not
   better. Its header also says "five charts" where the module builds eight chart objects (five
   `chartOf`, one `chartOfAll`, one raw `chart_K`, one `pieOf`) and the report's own table says
   "six".
2. **`AtomicAndRelation.e`** — the widest surface coverage in the group and the least trustworthy
   prose. `acrossTheTop` states 9 measurands and 11 labs where the data has **11** and **12**;
   `staticSummary`'s "Largest share 0.184" is the *first* row's share, not the largest
   (**0.226**), while the module says in as many words that `staticSummary` and `dataSummary`
   "differ only in where the numbers come from" — they differ in the numbers; "four of the fourteen
   lines are under one per cent" — **three** are; "Cost per sample 11.5952" against 10,000,000/862,411 =
   **11.5954**. Against that, its `slices` relation is *exactly* the measurand aggregation of
   `sensors` to the last digit, which is careful work. At 418 lines it also reads as a tour
   of `Layout.Report` rather than as a factsheet.
3. **`StyleGridHeatmap.e`** — good on `styleBox`, which is genuinely the odd combinator out and had
   no example, and the risk register's `xPos`/`yPos` really are the 0-based bins of
   `probScore`/`impactScore`. But the treemap's root node is **18,130,000** where its six children
   — which match the register's category totals exactly — sum to **17,230,000**; the `StyleGrid` is
   a hand-written literal that no data feeds (the module says so, which helps); and `Volume`,
   `ratioA` and `someVolume` are there "because it is part of the published surface", which is
   coverage for its own sake.

`VarianceStyling.e` is not in either list but shares the tile defect: `tile "Budget $000" 1568.0 /
"Actual" 1680.0 / "Variance" 112.0` against real totals of **2,432.0 / 2,579.4 / 147.4**, on a fact
table whose fourteen rows are otherwise arithmetically perfect (variance = actual − budget and
variancePct = variance/budget hold on every line). Its `actualPres` is also misnamed: it presents
`varianceK`.

### The one-session recipe and cross-module names

E3's group failed the README's "load them all, then evaluate by name" recipe because top-level
names clashed across modules. **This group passes.** I ran the README's exact command and then
evaluated all nine reports by name in that session: all eleven modules import, all nine answer
`Report <function>`. Only three names are duplicated across modules — `shown` (ValidationReport,
SortShowcase), `inRegion` (DrilldownExplorer, WriterOutputs), `byCategory` (SalesDashboard,
StyleGridHeatmap) — and none of them is a report; evaluating `byCategory` in the shared session
answers `undefined term`, which is worth one line in the README but breaks nothing the recipe
promises. Field names repeat freely across modules (`regionName` in three, `currencyCode` in four)
and, as the report says, that is why a *field-level* REPL session has to be per module.

### Renderings — G4(c) reproduces exactly, and it convicts the dashboard

I re-ran the SQL route with the committed `tracker/tools/sql-render.sh`, driving it with
`ERMINE_RENDER_MODULES="Present/{Helpers,WriterOutputs,SalesDashboard,ValidationReport}.e"` and a
probe module of my own over the same nine relations:

```
names: 9 asked, 9 answered, 9 produced SQL
q_active (9 rows)   q_emea (5)   q_summary (3)   q_byRegion (9)   q_byCategory (3)
q_badRates (3)      q_orphans (3)   q_unbalanced (1)   q_clean (9)
```

Identical to the report's table, and the values match too — `q_summary` returns
1158300.0 / 199200.0 / 17400.0 by segment, `q_byRegion` opens `Q1 | AMER | 49.608599999999996`.
The report's correction to E1 §7.4 — that `aggregateByGroup` dumps fine and the "Don't know how to
dump a mem" limit is `groupBy`'s `Mem` — is right.

One thing the report did not notice about its own output. `q_byRegion` is `SalesDashboard`'s own
revenue relation, and executed it sums to **482.4083** thousand — 482,408.3 — on the same page
whose KPI tile reads `currency "USD" 1103283.6`. The group's own rendering route disproves the
group's own headline number. (M-8.)

## 7. Coverage against the brief

Exercised and new to `core/examples`: `Layout.Writer`, `Layout.Writer.Profiled`, `Layout.harness`
(all four forms), `Fulcrum.Dynamic`, `Fulcrum.Legendary`, `Layout.Report.StyleGrid`,
`Layout.Report.Relation`, `Layout.Report.Atomic` beyond one `val`, `Layout.Validation`,
`Layout.Column`, `Layout.Magnitude` (`Area`/`Volume`), `Layout.Color`, `Layout.Font`,
`Layout.BorderOptions`, `Layout.SortStrategy`, `Layout.SortPriority`, `Syntax.Selector`,
`DrilldownList`, `styleBox`, `treemapChart`, the whole selector API, `Layout.Report.SelectorMode`.
That is the brief's list nearly complete.

`Layout.Report.Atomic` and `Layout.Report.Direction` are exercised through `Layout`'s own
re-exports (`Atomic` ×14, `atom` ×11, `val` ×5; `Horizontal` once in `DrilldownExplorer.e`), which
is fine and worth the report saying, since a reader grepping for the import will not find it.

Missed, and not accounted for in §6 of the report:

* **`Layout.Column.Unsafe`** — named in the brief *and* in `Present/README.md`'s "no example at all
  of" list, but nothing in the group imports it or names `column#` / `Table#` / `finalize`. The
  README's claim is therefore false about a module the group did not in fact cover (M-11).
* **`Layout.Report.SelectorMode`** — `DrilldownExplorer.e`'s SHAPES EXERCISED block says
  "`Layout.Report.SelectorMode` **named directly**, and `widget`". It is not: `SelectorMode` occurs
  three times in that file and **all three are inside comments**. None of its six constructors
  (`DropDown`, `RadioButton`, `Slider`, `TextBox`, `CheckBox`, `TextArea`) is ever written. The
  widgets are used, the type is not. (M-11)
* **`Layout.Scan`** — a real, separate module (`scan = fromRelation_S runner`), unrelated to the
  `scan`/`runScan` of `Layout.Report` that `AtomicAndRelation.e` uses. Genuinely untouched.
* **`Layout.PresRow`** — untouched.

A follow-up module could take `Column.Unsafe`, `PresRow` and `Layout.Scan` — the three "how the
sausage is made" modules — in one file and would close the brief's list.

## 8. Wiring, checked against the tree

The orchestrator has **already applied** E4's requested lines to `tracker/tools/looptrace-corpus.sh`
(the `Present)` / `Present-shouldfail)` cases at lines 98–107, and `Present Present-shouldfail` in
the default group list at line 53) and to `core/examples/README.md` (row at line 23, command at
line 31, `Present/shouldfail/` at line 39). Both match what the report asked for.
`tracker/tools/corpus-run.sh` has the group in `files=` (lines 108–109) and the **batch** hoist
(lines 133–135).

**The per-file hoist is missing.** `corpus-run.sh`'s per-file loop (lines 158–166) still reads

```bash
  case "$f" in
    core/examples/Ai/Common.e)    ;;
    core/examples/Wide/Helpers.e) ;;
    core/examples/Ai/*)           args=( core/examples/Ai/Common.e "$f" ) ;;
    core/examples/Wide/*)         args=( core/examples/Wide/Helpers.e "$f" ) ;;
  esac
```

so a non-`--batch` `corpus-run.sh` loads every `Present/` module **without `Present/Helpers.e`** and
every one of them fails. The same gap exists for `Algebra/` and `Time/`. E4's report asked for
exactly these two lines and they have not been applied:

```bash
    core/examples/Present/Helpers.e) ;;
    core/examples/Present/*)      args=( core/examples/Present/Helpers.e "$f" ) ;;
```

Also: the comment the orchestrator copied into `looptrace-corpus.sh` says "every module under
`Present/shouldfail` imports `Present.Helpers`". It does not — only `leg02` and `chart01` do; the
other four are stdlib-only. Harmless (hoisting the library is free) but the comment is false, and
it is false for `Wide`/`Algebra`/`Time` too if they were written the same way.

`TestSurfaceParsers.scala` needs nothing, as the report says.

---

## Findings

### Must fix before commit

* **M-1 — the census's headline claim is a mislabelled metric (E3's P-18, again).** "Per-key mints,
  max 12 … the first to exceed the round-7/8 maximum of 11" is wrong twice: on the final bytes
  `--cycle`'s `maxmint` is **11**, and `maxmint` is the *minted-variable vocabulary size*
  (`Cycle.lean:407`), not a per-key count. `--mints` gives the per-key maximum for this group as
  **1**. Delete the claim; report `maxmint` under its real name and the per-key max as 1. Rename
  "decision nodes (states)" to `steps` (73), as P-18 asked. **CONFIRMED.**
* **M-2 — "budget headroom 89×" describes a shape that is one line from the cliff.** Measured
  ladder (my `ProbeCascade*.e`, each body alone in a module): 2…8 projections of one record
  parameter with an open row cost **3 / 33 / 207 / 1,243 / 6,795 / 35,923 / 185,848** draws —
  ≈5.3–6× per extra read — and **seven already exhausts the 20,000 budget**, with the resource
  diagnostic quoted in §3.1. The same five projections under one written partition cost **0**. Replace the headroom sentence with the
  ladder and the remedy, and say that `ValidationReport`'s 218 is the *concrete-row* case.
  **CONFIRMED.**
* **M-3 — four wrong counts in §2's "Counts" paragraph** (and repeated in the file table):
  partitions-carrying signatures 12 not 11, partition constraints 15 not 14, existentials 5 not 6,
  class constraints 14 not 16. **CONFIRMED** by machine count of the published `Helpers.ei`.
* **M-4 — §4.3 over-generalises.** The existential class appears for `styledBy`, `hiddenBy` and
  `outOfRange`; it does **not** appear for `scaledBy` or `unreconciled`. Fix the count (three, not
  five, and not "four" as `Signatures.e`'s header says before listing five), and delete the false
  sentence in `Signatures.e`'s `scaledBy` comment. **CONFIRMED by minimal modules.**
* **M-5 — the `Console.other` example list is wrong.** `latest` and `casing` contain none of the
  three substrings; `latest` demonstrably does not hang. Fix both the report §4.7 and
  `Present/README.md`, and state the mechanism as measured: `readLine` returns `null` at EOF, so
  the loop is not merely noisy — it never terminates. **CONFIRMED.**
* **M-6 — §4.1's writer table over-claims.** "Exactly one constructor" (HTML, Json and JsonDebug
  have two each) and "every one of them defines its entry point with the same four lines" (four of
  six; JavaFX and PDF have none) are both false, and the table lists entry points in the
  constructor column for Json/JsonDebug. **CONFIRMED against the writers' source.** Same finding in
  §6.1 and in `Present/README.md`: "every constructor of both [`Scanner` and `Runner`] is a
  database connection" is false — `Runners.sqlite : String -> Runner DB` takes a JDBC URL and
  `jdbc:sqlite::memory:` is one, with the driver already on this classpath. The obstacle to running
  a `Report` here is a missing writer jar, not a database (§5).
* **M-7 — §6.3 and §4.9(5) are wrong, and two signatures should be restored.**
  `Ord (Record (| positionName |))` is accepted; `SortShowcase.e`'s `byPositionRank` type-checks at
  it. Only the `{..r}` sugar requires a variable. Put the two signatures back and restate the
  limit. **REFUTED by a minimal module that loads.**
* **M-8 — the hand-written headline numbers contradict their own fact tables.** Three modules:
  `SalesDashboard.kpiRow` (1,103,283.6 / 73,552.2 against 482,408.3 / 32,160.55),
  `VarianceStyling.varianceReport`'s three tiles (1568 / 1680 / 112 against 2432.0 / 2579.4 /
  147.4), `AtomicAndRelation` (`staticSummary` largest share 0.184 against 0.226; `acrossTheTop`
  9 measurands and 11 labs against 11 and 12; "four … under one per cent" against three; cost per
  sample 11.5952 against 11.5954) and `StyleGridHeatmap.impactTree`'s root 18,130,000 against its
  children's 17,230,000. Every one of these is a number a reader will trust because the rest of the
  data is impeccable. Either compute them (`scanRelation`, as `dataSummary` already does) or make
  them match. **CONFIRMED by arithmetic over the module sources.**

### Should fix

* **M-9 — the report's G2/G3/G4(b) figures are not the final bytes**, despite the note saying they
  are: my trace has 126,756 segments against 126,260, the group census 54,287 solves against
  53,898, max draws 218 against 225, and `VarianceStyling.ei`/`SalesDashboard.ei` publish 24/19
  signatures against the reported 21/18. Re-measure or drop the "FINAL bytes" note.
* **M-10 — `corpus-run.sh`'s per-file hoist for `Present/` is missing** (§8). Without it the
  non-batch path fails every module in the group. The report asked for it; the orchestrator applied
  everything else.
* **M-11 — two headers claim coverage the modules do not have.** `Present/README.md`'s "no example
  at all of" list names `Layout.Column.Unsafe`, which the group does not exercise either; and
  `DrilldownExplorer.e`'s SHAPES EXERCISED block says "`Layout.Report.SelectorMode` named
  directly", where all three occurrences of the name are in comments and no constructor of the type
  is ever written. **CONFIRMED** by grep over the group.
* **M-12 — §4.7 says a piped session is "quadratic, and with stdin at EOF, unbounded".** Sharper
  and worth the words: it is an infinite loop caused by `null == ""` being false, so no amount of
  waiting ends it. Recommend the two-line fix (tokens, or `last == null` ⇒ blank).
* **M-13 — `SalesDashboard.e`'s header says "five charts"** where the module builds eight chart
  objects, and the report's file table says six. Pick one and make the three agree.
* **M-14 — `VarianceStyling.actualPres` presents `varianceK`**, not the actual. Rename to
  `variancePres`… which is taken; `varianceAmountPres` / `varianceBandPres` would do.
* **M-15 — the report's §G3 list of "the next four" solves** omits `VarianceStyling.e(177:3)`
  (drawn=13, the third-costliest in my trace) and gives `SortShowcase.e(160:3)` as 13 where it is
  12. Cosmetic, but it is a table of measurements.
* **M-16 — the wiring comment in `looptrace-corpus.sh`** ("every module under `Present/shouldfail`
  imports `Present.Helpers`") is false for four of the six negatives.
* **M-17 — one line for the README**: `shown`, `inRegion` and `byCategory` are defined in two
  modules each and are therefore unreachable unqualified in the one-session recipe.

### Recommended ticket entries (recommendation only — I wrote nothing)

New `tracker/TICKET-stdlib-findings.md`:

1. **`Native.Record` MapView** — `Lib.scala:988/1007/1012` need `.toMap`; two confirmed panic sites
   (`scalaRecord#` via `Relation.Pivot.pivot`, `header#` via `Legendary.emptyLF`). One-line fix,
   a test that forces a pivot and one that forces a fulcrum header. (E1 §7.2 + E4 §4.6, both
   independently reproduced.)
2. **`Console.other` continuation heuristic** — substring test on `case`/`let`/`where` plus a
   `null` EOF read makes any piped session containing such an identifier hang forever
   (`Console.scala:146,623`). Two-line fix.
3. **Interface printer drops a constraint-only row variable** — a universally quantified row
   variable occurring only in a constraint is printed free (F2, minimal repro in this review).
4. **Existential class variable in inferred residuals** — `(exists (AsOp: b). AsOp op, AsOp op)`
   for `AsOp`-polymorphic bodies (three of the five tested); open whether printer or residual.
5. **Partition blame wording** — "the whole contains it but no part does" is printed for the
   converse situation (E1 §7.5, E4 §4.8, two independent reproductions).

`tracker/TICKET-editor-and-solver-followups.md`:

6. **Resolution cascade on a projected record** — N `Has` constraints on one unannotated row
   variable cost ≈5.3–6× per additional projection (3 → 185,848 for N = 2 → 8) and exhaust the
   20,000-draw budget at N = 7 (measurements in §3.1). This is the production `params → report` shape. Worth a solver look
   (the closure is doing work a single left-hand-side index would avoid) and, until then, worth a
   line in the examples' README: *write the parameter row down*.
