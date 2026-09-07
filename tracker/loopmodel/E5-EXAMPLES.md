# E5 — `core/examples/Lang/`: the language beyond relations — monads, parsers, validation, strings, IO

Stage E5 of `tracker/LOOP-MODEL-PLAN.md`. Brief `tracker/loopmodel/briefs/brief-E5.md` on top of
`briefs/brief-E-common.md`. Repository at `40f80aa` (branch `scala3-migration`), the three
row-solver defaults adopted (`-Dermine.rowSound` ON, `dequeuePolicy=smallcanon`,
`solveBudget=20000`). Every `bin/ermine` below ran with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time, 2026-09-07, on a
machine shared with two other example-writing agents.

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false" \
      bin/ermine core/examples/Lang/Helpers.e core/examples/Lang/<M>.e

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/E5/`. Boot is 13–16 s of every wall figure and
is excluded from the per-module times.

**Outcome: GREEN. Reviewed 2026-09-07 (`E5-REVIEW.md`, FIX-THEN-ADVANCE, L-1…L-22); all eight
must-fixes and every applicable should-fix applied, and every gate re-run on the corrected
bytes. §8 is the old → new audit trail.** Twelve `.e` modules under `core/examples/Lang/` — `Helpers.e` (71 public
generic bindings), `Signatures.e`, and **ten** reports — plus **seven** negatives under
`shouldfail/`, one `.slow` module that measures a compiler cliff, and a group `README.md`;
**19 `.e` files** and one `.slow`. Everything that should load,
loads, per file and in one batch; all seven negatives are rejected with the diagnostics recorded
in their own headers; the L2 differential over the group is **90,694 segments, 0 skipped /
0 hashdiff / 0 eqdiff** (and **58,779** more over the negatives, likewise clean). `sbt
core/test` is **913/914, the one pre-existing failure**. Every report evaluates in the REPL, and — for the first
time in this corpus — four bindings render a document you can actually read, because a markdown
table is a `String`.

The census (G3) is the headline: this group's costliest solve draws **1,241**
partitions against E4's previous record of 225, every one of them a `Resolution` step, and its
minted-variable VOCABULARY reaches **27** — a corpus record. (Its per-key mint count is **1**,
as it is for every group in the E series; the earlier draft of this report mislabelled the
vocabulary figure as a per-key count, which is E4's M-1 repeated — see §8.) The shape is new and
it is *not* a wide row: it is **one record projected five times inside one expression**.
Section 4.1 measures the series 1…7 in isolation and finds that **seven projections do not
compile at all**: the adopted draw budget fires with the diagnostic it was adopted to give.
E4's reviewer found the same cliff from the presentation side at the same time and E4 now ships
`Present/shouldfail/proj01_seven_reads.e` for it; §4.1 is an INDEPENDENT reproduction with a
second probe shape, and it is what puts this group's three costliest solves where they are.

---

## 1. The file table (G5)

| module | subject | fields per fact row | helpers used | shapes exercised | check, per file | in batch |
|---|---|---|---|---|---|---|
| `Helpers.e` | 71 public generic bindings | — | — | 16 quantify over a row; **5** carry an explicit row constraint | 0.43–0.48 s | 0.44 s |
| `StatementParser.e` | a bank statement parsed from text into a relation | **7** | `pRecord`×6, `pUpTo`, `pInt`, `pLit`, `pMany`, `parseAll`, `runParser`, `firstOf`, `parserMonad`/`parserFunctor`/`parserAlt`, `pipeChar`, `foldMapL`, `joinedMonoid`, `parseDoubleTotal` | a parser-combinator library written in Ermine; `pRecord`'s `t <- (r, s)` chained SIX deep, so a row variable travels under `Parser`; `Control.Alt` as a keyword table; `do` and hand-written `bind` proved to agree at run time | 0.14 s | 0.12 s |
| `CsvIntake.e` | a CSV read into a relation, every error at once | **6** | `consRow`×6, `nilRow`, `readRowsAs`, `runRowReader`, `cellInt`, `cellDouble`, `cellString`, `parseIntTotal`, `dashChar`, `foldMapL`, `joinedMonoid`, `errsAp` | a **user-defined bracket literal** for `RowReader`; accumulating validation (5 messages) against `eitherAp` (2); `IO.CSV.parseCSV` for real; `relationWithHeader`; `Validation.FormValidator` beside it | 0.26 s | 0.25 s |
| `RunningState.e` | a running balance, three ways | **13** | `withRunning`, `withState`, `scanRows`, `mapMRows`, `foldRows`, `traverseRows`, `checkedRel`, `showRows`, `sumMonoid`, `maxMonoid`, `countMonoid` | `withRunning`'s `t <- (r, c)` at the group's widest row; `Control.Monad.State` and `StateT s Maybe`; `scanRelationInOrder` driving the same fold from the relation; `mproduct` | 0.53 s | 0.43 s |
| `ReaderParams.e` | one report, three parameter sets | **11** | `askField`×5, `localField`, `runWith` | `Control.Monad.Reader` as the params→report shape; `Has e h` and its expansion; `Syntax.Reader`'s `lift2`/`lift3`/`<$$>`; `local`; `ReaderT r Maybe` | 0.27 s | 0.22 s |
| `FreeReportDsl.e` | a report DSL run two ways | **8** | `foldMapL`, `joinedMonoid`, `mdTable`, `foldRows`, `sumMonoid`, `countMonoid` | `Data.Free` with a hand-written command functor and three interpreters over one program; `Data.Free.Church` + `runF`; `Data.Cofree` as an infinite stream with `extend`; `Data.Nu` with the seed genuinely hidden | 0.35 s | 0.30 s |
| `DoNotation.e` | one `do` block, five monads | **10** | `traverseRows`, `checkedRel`, `foldRows`, `maxMonoid`, `firstOf`, `parseIntTotal`, `parserMonad`, `pToken`, `pInt`, `parseAll` | `Syntax.Do` at `Maybe`/`Either`/`List`/`State`/`Parser`; `Syntax.Monad` vs `Syntax.Maybe` vs raw dictionaries; `liftA2`…`liftA6`, `tupleA2`, `strength`, `mapply`, `join`, `ifM`; `Control.Alt` at `Maybe` | 0.32 s | 0.25 s |
| `TextTables.e` | one relation rendered four ways, all readable | **9** | `showRows`, `mdTable`, `mdLink`, `rpad`, `lpad`, `foldMapL`, `joinedMonoid` | `String` in full; `StringManip.allMatches` (regex through six `foreign` declarations); `String.Markdown` and its broken `link`; a `foreign` `toLowerCase` added in three lines | 0.67 s | 0.46 s |
| `TreeAndMap.e` | a category tree flattened and re-rolled | **8** | `mdTable`, `foldRows` | `Tree.unfold`/`fold`/`aggregate`/`identify`/`toString'`; `Tree.toRootedRel`'s three-part partition with ids MINTED by the stdlib; `Tree.fromRel` under `Layout.Scan.runner`; `Map` in full; `Ord` composed with `ordMonoid` | 0.46 s | 0.36 s |
| `ForeignJdk.e` | reaching the JVM | **10** | `parseIntTotal`, `foldRows`, `sumMonoid` | all six `foreign` forms plus `private foreign`; `IO` vs `FFI` results; an overload narrowed by its declared type; `Random`'s seeded stream; `GUID`; the `Prim.apply` bug reproduced from scratch | 0.42 s | 0.39 s |
| `TypesAndRows.e` | the language itself | **12** | `foldRows`, `sumMonoid`, `sameShapeAs` | `data` with `(s : rho)` and `(f : * -> *)`; existentials; `private`; three fixity declarations; EVERY pattern form; the whole row vocabulary; `Type.Eq`/`Type.Cast`/`Type.Remember`; `Void`/`absurd` | 0.39 s | 0.29 s |
| `Signatures.e` | the entailment proofs | — | — | **five** `xFull`/`xDeduped` pairs, a three-step `Has`-sugar round trip, **five** `xSimple` specialisations, two lemmas, and the one scheme that cannot be written | 0.13 s | 0.11 s |
| `shouldfail/` ×7 | seven negatives | 1–13 | the helper each misuses | five distinct refutation classes — see G1(c) | 0.03–0.07 s each | — |
| `ProjectionCliff.slow` | the projection cliff, N = 1…7 | 7 | — | the draw budget FIRING, and the same seven projections at a concrete row costing nothing | REJECTED in 2.93 s | — |

Per-file wall clock is **14.3–15.2 s** per module, of which 13–14 s is the stdlib boot; own check
time 0.13–0.67 s. **Nothing is over 30 s, nothing among the `.e` files
needed `.slow`, and the draw budget never fired on one** — `ProjectionCliff.slow` is the
deliberate exception and is not a `.e` file (§4.1).

---

## 2. The helper signatures, verbatim, with their published residuals (G5)

Below, each signature exactly as written in `Helpers.e`, followed by the line
`core/examples/Lang/Helpers.ei` publishes under a `-Dermine.useInterface=true` load. **No
weakening, no extra constraint, no residual the author did not write**: every published line is
the written one with `Has` expanded, type synonyms unfolded and names qualified.

`Helpers.ei` holds **75** lines: the 71 public bindings and the four `private` workers
(`punit`, `pbind`, `por`, `mconcat`), which an interface lists even though an importer cannot
resolve them (§4.7). The five `foreign` declarations appear in it **not at all**, and are
importable anyway (§4.7). E5's reviewer tested both halves by importing: `punit` is
`undefined term` with and without `-Dermine.useInterface=true`, and `strLength` resolves both
ways.

### applicative accumulation

```
accumAp : forall e. (e -> e -> e) -> Ap_M (Either e)
errsAp  : Ap_M (Either (List Err))
allOrNothing : forall e a. (e -> e -> e) -> List (Either e a) -> Either e (List a)
```
published: `accumAp : forall e. (e -> e -> e) -> Control.Ap.Ap (Either.Either e)`;
`errsAp : Control.Ap.Ap (Either.Either (Builtin.List (Builtin.String, Builtin.String)))` — the
`Err` synonym unfolded to the pair; `allOrNothing` unchanged.

### traversals over rows — the corpus shapes

```
traverseRows : forall f r a. Ap_M f -> ({..r} -> f a) -> List {..r} -> f (List a)
```
published: `forall (f: * -> *) (r: rho) a. Control.Ap.Ap f -> (Builtin.Record r -> f a) -> Builtin.List (Builtin.Record r) -> f (Builtin.List a)`

```
mapMRows : forall m r a. Monad_M m -> ({..r} -> m a) -> List {..r} -> m (List a)
traverseRel : forall f r s. Ap_M f -> ({..r} -> f {..s}) -> List {..r} -> f (Relation (|..s|))
checkedRel : forall r. ({..r} -> List Err) -> List {..r} -> Either (List Err) (Relation (|..r|))
foldRows : forall r m. Monoid_Mo m -> ({..r} -> m) -> List {..r} -> m
```
published unchanged modulo qualification; `traverseRel`'s result prints as
`f (Builtin.Relation s)` and `checkedRel`'s as `Either.Either (Builtin.List (Builtin.String, Builtin.String)) (Builtin.Relation r)`. **None of the four carries a residual constraint**: the
row is a plain quantified variable, and everything the body needs is discharged against it.

### the CSV row reader

```
data RowReader (r : rho) = RowReader (List String -> Either (List Err) {..r})

nilRow : RowReader (| |)
consRow : forall t r s a. t <- (r, s)
       => (Field r a, Int, String -> Maybe a) -> RowReader s -> RowReader t
readRowsAs : forall r. RowReader r -> Row_R r -> List (List String) -> Either (List Err) [..r]
runRowReader : forall r. RowReader r -> List String -> Either (List Err) {..r}
```
published: `consRow : forall (r: rho) a (s: rho) (t: rho). t <- (r, s) => (Builtin.Field r a, Builtin.Int, Builtin.String -> Builtin.Maybe a) -> Lang.Helpers.RowReader s -> Lang.Helpers.RowReader t` — the partition **in the written order**, not the permuted one inference
produces for a delegating wrapper (§4.4); `nilRow : Lang.Helpers.RowReader (||)`;
`readRowsAs` with `[..r]` printed as `Builtin.Relation r`.

### the parser

```
data Parser a = Parser (String -> Maybe (a, String))

pRecord : forall t r s a. t <- (r, s) => Field r a -> Parser a -> Parser {..s} -> Parser {..t}
pNil    : Parser {}
```
published: `pRecord : forall (r: rho) a (s: rho) (t: rho). t <- (r, s) => Builtin.Field r a -> Lang.Helpers.Parser a -> Lang.Helpers.Parser (Builtin.Record s) -> Lang.Helpers.Parser (Builtin.Record t)`; `pNil : Lang.Helpers.Parser (Builtin.Record (||))`.

```
runParser : forall a. Parser a -> String -> Maybe (a, String)
parseAll  : forall a. Parser a -> String -> Maybe a
pSat  : (Char -> Bool) -> Parser Char
pLit  : String -> Parser String
pMany : forall a. Parser a -> Parser (List a)
pSome : forall a. Parser a -> Parser (List a)
pSepBy : forall a b. Parser b -> Parser a -> Parser (List a)
pToken : forall a. Parser a -> Parser a
pUpTo  : Char -> Parser String
```
published unchanged; `pSepBy`'s two variables print in the order `forall b a`.

### State

```
withState : forall r s a. ({..r} -> s -> (a, s)) -> s -> List {..r} -> (List a, s)
scanRows  : forall r s. (s -> {..r} -> s) -> s -> List {..r} -> List s
withRunning : forall t r c n. t <- (r, c)
           => Field c n -> (n -> {..r} -> n) -> n -> List {..r} -> List {..t}
```
published: `withRunning : forall (c: rho) n (r: rho) (t: rho). t <- (r, c) => Builtin.Field c n -> (n -> Builtin.Record r -> n) -> n -> Builtin.List (Builtin.Record r) -> Builtin.List (Builtin.Record t)`.

### Reader

```
askField : forall e h a. Has e h => Field h a -> Reader_Rd {..e} a
runWith  : forall e a. {..e} -> Reader_Rd {..e} a -> a
localField : forall e h a b. Has e h => Field h a -> (a -> a) -> Reader_Rd {..e} b -> Reader_Rd {..e} b
```
published — **and this is the one interesting rewrite**: `Has` is sugar for
`exists c. e <- (h, c)` and the interface writes the sugar out, while `Reader e a` is a type
synonym for `e -> a` and the interface unfolds it too:

```
askField : forall (h: rho) a (e: rho). (exists (c: rho). e <- (h, c))
        => Builtin.Field h a -> Builtin.Record e -> a
localField : forall (h: rho) a (e: rho) b. (exists (c: rho). e <- (h, c))
          => Builtin.Field h a -> (a -> a) -> (Builtin.Record e -> b) -> Builtin.Record e -> b
runWith : forall (e: rho) a. Builtin.Record e -> (Builtin.Record e -> a) -> a
```

`Lang/Signatures.e` §4 proves the sugar and the expansion entail one another, in both
directions.

### Alt, Monoid, text, types

```
firstOf : forall f a. Alt_Alt f -> List (f a) -> f a
orElseA : forall f a. Alt_Alt f -> f a -> f a -> f a
withDefaultA : forall f a. Alt_Alt f -> a -> f a -> f a
foldMapL : forall a m. Monoid_Mo m -> (a -> m) -> List a -> m
joinedMonoid : String -> Monoid_Mo String
showRows : forall r. List String -> ({..r} -> List String) -> List {..r} -> String
mdTable : List String -> List (List String) -> String
sameShapeAs : forall a. a -> a -> a
inMonad : forall f a. Monad_M f -> (Monad_M f -> f a) -> f a
twiceOver : forall m. Monad_M m -> m Int -> m Int
```
published unchanged modulo qualification. `showRows` is the only one of these that carries a
row, and it carries it with no constraint at all.

---
## 3. The gates

### G0 — the tree this was measured on, and the one change that moved under it

The repository is shared with two other agents, and one of them modified the COMPILER while
this stage was running. `git diff` at the time of the final measurements:

```
 core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala | 13 ++++++++++++-
```

— `Subst.NormalPart` gets a `hashCode` that agrees with its `equals` (so `List.distinct` stops
publishing two permuted copies of one constraint), and the tautology `a <- (a)` is deleted
during normalisation. The source was edited at **03:22:53** and the classes were rebuilt at
**03:56:08**; every number in G1–G4 below was re-taken **after** that rebuild, on one compiler,
with the fingerprint of `Subst$.class` recorded before and after the run to prove it did not
move again.

**Nothing else moved.** The whole gate set was run on both sides of the rebuild and the two
agree exactly: 88,037 / 58,289 segments, 0 skipped / 0 hashdiff / 0 eqdiff, and a census
identical figure for figure (1,245 max draws, 29 max minted vocabulary, 24,399 attributable solves,
the same five costliest sites). `sbt core/test` is 913/914 on both sides. `Lang/Helpers.ei` is
byte-identical.

One measurement of mine did move, and it is a finding in its own right (§4.5): before the
change, `-Dermine.useInterface=true` over an eta-delegating wrapper emitted a scheme with an
inferred KIND variable, `forall {a} … (a1: a)`, which the surface parser rejects. After it, no
delegated wrapper in this group emits a kind variable at all. `Lang/Helpers.ei` is
**byte-identical** across the change, so nothing in §2 is affected; what changed is the
inference for *unannotated* wrappers, which is exactly what `Signatures.e` reads.

### G1(a) — every module loads, per file

Command per row: `bin/ermine core/examples/Lang/Helpers.e core/examples/Lang/<M>.e`, one JVM
each, `-Dermine.useInterface=false`, on the corrected bytes (§8) and the post-rebuild compiler
(§G0).

```
CsvIntake        wall=14.7s   Helpers 0.48 s   CsvIntake        0.26 s
DoNotation       wall=15.2s   Helpers 0.48 s   DoNotation       0.42 s
ForeignJdk       wall=14.5s   Helpers 0.47 s   ForeignJdk       0.32 s
FreeReportDsl    wall=14.4s   Helpers 0.46 s   FreeReportDsl    0.35 s
ReaderParams     wall=14.5s   Helpers 0.43 s   ReaderParams     0.27 s
RunningState     wall=14.8s   Helpers 0.44 s   RunningState     0.53 s
Signatures       wall=14.7s   Helpers 0.45 s   Signatures       0.13 s
StatementParser  wall=14.6s   Helpers 0.47 s   StatementParser  0.14 s
TextTables       wall=15.1s   Helpers 0.46 s   TextTables       0.67 s
TreeAndMap       wall=15.0s   Helpers 0.45 s   TreeAndMap       0.46 s
TypesAndRows     wall=14.3s   Helpers 0.47 s   TypesAndRows     0.39 s
```

All LOADED. Wall clock 14.3–15.2 s per module, 13–14 s of which is the stdlib boot; own check
time **0.13–0.67 s**. E5's reviewer measured 0.13–0.63 s independently on the pre-correction
bytes, in the same order — the earlier 1.06 s figure in this report was machine load, not a
module. **Nothing over 30 s; no module needed `.slow` for slowness, and no budget diagnostic
fired on any `.e` in the group.**

`core/examples/Lang/ProjectionCliff.slow` is `.slow` for the other reason — it does not compile
at all, by design, and §4.1 is the measurement it exists to carry.

### G1(b) — every module loads in one batch

```
$ ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false" \
    bin/ermine core/examples/Lang/Helpers.e core/examples/Lang/{CsvIntake,DoNotation,\
    ForeignJdk,FreeReportDsl,ReaderParams,RunningState,Signatures,StatementParser,\
    TextTables,TreeAndMap,TypesAndRows}.e

Importing module 'Lang.Helpers'         (0.44 seconds)
Importing module 'Lang.CsvIntake'       (0.25 seconds)
Importing module 'Lang.DoNotation'      (0.39 seconds)
Importing module 'Lang.ForeignJdk'      (0.25 seconds)
Importing module 'Lang.FreeReportDsl'   (0.30 seconds)
Importing module 'Lang.ReaderParams'    (0.22 seconds)
Importing module 'Lang.RunningState'    (0.43 seconds)
Importing module 'Lang.Signatures'      (0.11 seconds)
Importing module 'Lang.StatementParser' (0.12 seconds)
Importing module 'Lang.TextTables'      (0.46 seconds)
Importing module 'Lang.TreeAndMap'      (0.36 seconds)
Importing module 'Lang.TypesAndRows'    (0.29 seconds)
                                total    3.62 s, wall 18 s
```

(E5's reviewer measured **3.57 s** on the pre-correction bytes; the report's earlier 5.15 s and
3.85 s were the same twelve modules under heavier machine load.)

`Helpers.e` must come first: every module imports it.

**No two top-level names in the group collide.** Checked mechanically over every `^name :`,
`^name =`, `field name` and `data Name` in the twelve modules, before and after the corrections:
zero duplicates across files. E5's reviewer confirmed this independently and records that E3's
group had five clashes and E4's three, so E5 is the first E-series group with none. That is what
makes the group `README.md`'s single-session recipe work, and G4 evaluates 141 expressions in
ONE session to prove it.

### G1(c) — the seven negatives, each REJECTED with the recorded diagnostic

Command: `bin/ermine core/examples/Lang/Helpers.e core/examples/Lang/shouldfail/<M>.e`.
Each header carries its message verbatim; all seven reproduce.

| module | mistake | diagnostic | class |
|---|---|---|---|
| `lang01_parser_row_mismatch.e` | a `pRecord` chain annotated one column short | `failed to unify type (\|jobQty, jobRef\|) with type (\|jobQty, jobRef, jobSite\|)` | row unification |
| `lang02_reader_field_twice.e` | a CSV reader reading one field twice | `Fields appear twice in row: Lang.Shouldfail.Lang02.assetRef` | duplicate field |
| `lang03_running_column_exists.e` | a running-total column the input row already has | `Fields appear twice in row: Lang.Shouldfail.Lang03.runningSum` | duplicate field |
| `lang04_wrong_monad.e` | a `do` block applied to `listMonad` over `Maybe` actions | `failed to unify type Maybe with type List` | type unification |
| `lang05_traverse_row_mismatch.e` | `traverseRel` dropping an annotated column | `failed to unify type (\|orderQty, orderRef, orderTeam\|) with type (\|orderQty, orderRef\|)` | row unification |
| `lang06_escaping_existential.e` | projecting `Data.Nu`'s hidden seed | `skolem variables escape:` / `Type would have been: Nu f -> !s` | skolem escape |
| `lang07_kind_variable_written.e` | the interface printer's own inferred scheme, written back | `failed to unify kind * with kind !k` | kind unification |

**Five refutation classes**, and — this is worth knowing about the corpus — **none of them is a
row-solver refutation**. The negatives' L2 run reports `rejected=0`: every one of the seven is
caught by unification, by row *construction*, by the skolem check or by kind checking, all
before `Subst.solve` is reached. E4's presentation negatives were 1-in-6 solver refutations and
the `Wide`/`Algebra` join negatives were nearly all of them; a group about the LANGUAGE is at
the opposite end. Each rejection is 0.03–0.07 s after the module's own parse.

Two of them (`lang06`, `lang07`) are refutation classes no other group has.

### G1(d) — `sbt core/test`

**913 / 914, Failed 1, Errors 0** (`sbt -batch core/test`), run TWICE — once before the
compiler rebuild of §G0 (**333 s**) and once after it (**397 s**), the second with the
`Subst$.class` fingerprint recorded before and after the run and unchanged
(`8f54eee6211f4e0d309a444f54c1bd45`). Identical verdict both times:

```
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
[info] Failed: Total 914, Failed 1, Errors 0, Passed 913
```

The single failure is the **pre-existing** `Constraints.disjunction sound`, recorded by E2, E3
and E4, documented twice in `Constraints.scala`, deterministic, and reading no example file.

Every corpus-wide property passes over the enlarged tree, with E5's 19 new `.e` files in it:

```
[info] + Surface parser 2.3a.headers agree with the fused pipeline across the stdlib: OK, proved property.
[info] + Tolerant read.strict and tolerant agree, and the tolerant read is silent, over the corpus: OK, proved property.
[info] + Statement extents.extent text is unchanged by the index (271 files): OK, proved property.
[info] + loop model trace.the Lean loop model reproduces the compiler's trace, segment for segment: OK, proved property.
[info] + REPL eval goldens.corpus matches goldens: OK, proved property.
```

**No wiring line is needed for `TestSurfaceParsers.scala`**: the file-count constant that
tripped for E2 and E3 is now derived, and it passes unchanged. **Corpus size for the record:
356 `.e` files** with E5's 19 in the tree (161 stdlib + 195 under `core/examples`). E5's reviewer
re-ran the three walkers the brief names
(`core/testOnly *TestSurfaceParsers *TestStatementExtents *TestTolerantRead`) and got
**Total 20, Failed 0, Errors 0** in 97 s.

`ProjectionCliff.slow` is invisible to all of these — the walkers filter on `.e` — which is
exactly why it has that extension.

### G2 — the L2 differential on the group

    ERMINE_JAVA_OPTS="-Xmx3000m -XX:ActiveProcessorCount=2 -Dermine.useInterface=false \
      -Dermine.loadInSeries=true -Dermine.rowTrace=<scratch>/Lang.tsv" bin/ermine <12 files>
    tracker/lean/.lake/build/bin/looptrace --replay <scratch>/Lang.tsv
    tracker/tools/looptrace-diff.py --segments --lean … --scala … --report …

**The eleven positive modules plus `Helpers.e`** (corrected bytes, §8):

```
#summary  segments=90694  replayed=90694  skipped=0  hashdiff=0  eqdiff=0  nonpart=1419  rejected=0  fuel=0

segments: scala=90694 lean=90694 compared=90694
AGREE   90694
SKIP    0
hashdiff segments: 0
eqdiff segments: 0
```

**The seven negatives (`Helpers.e` + `shouldfail/*.e`):**

```
#summary  segments=58779  replayed=58779  skipped=0  hashdiff=0  eqdiff=0  nonpart=1037  rejected=0  fuel=0
AGREE   58779   SKIP 0   hashdiff 0   eqdiff 0
```

**0 skipped / 0 hashdiff / 0 eqdiff on both runs.** Trace 40.6 MB (positives) and 26.0 MB
(negatives); ermine 22 s; the model replays 90,694 segments in **15.7 s**.

This is the fourth clean run of this differential over this group: pre-rebuild (88,037 / 58,289),
post-rebuild (identical), E5's reviewer's own trace (identical again, "byte-for-byte what the
report claims"), and now the corrected bytes. The segment counts rise with the corrections
because the corrections add code — `foldFree`, the pinned lambdas, the `Control.Category` and
`ErrorT` sections — not because anything moved.

`rejected=0` on the NEGATIVES is itself a result: none of E5's seven refutations is a row-solver
refutation (G1(c)). Four groups in, that makes the corpus's refutation classes:
`Wide`/`Algebra` almost all solver, `Present` one in six, `Lang` none — which E5's reviewer
confirmed independently and calls "the best single sentence in the report".

Derivation rules over the whole positive trace (`rowtrace-summary.py`): `Substitution` 552,
`Resolution` **487**, `CommonSubexpression` 273, `Cancellation` 43, `SplitConcrete` 10,
`ResolutionRow` 2. Note the shape: **`Resolution` is the second-biggest rule here and
`SplitConcrete` is almost absent** (10, against `Present`'s 217 and the relational groups'
hundreds). That is the signature of a corpus made of record projections rather than joins.
1,033 splice firings of which 415 changed the output; 315 dropped, 283 non-conservative.

### G3 — the census over the group

`--depth`, `--cycle` **and `--mints`** over the same replay, filtered to the **26,213** segments
whose location is inside `core/examples/Lang/` (the trace also carries the 64,481-segment stdlib
boot, identical on both sides).

| measure | **`Lang/` (this group)** | `Present/` (E4) | `Time/` (E3) | `Ai/` (E3 control) | round 7/8 corpus |
|---|---|---|---|---|---|
| solves attributable to the group | **26,213** | 53,898 | 43,258 | 20,393 | — |
| verdicts | 26,213 SOLVED, 0 REJECTED | 53,898 / 0 | 43,256 / 2 | 20,393 / 0 | — |
| **draws per solve, max** | **1,241** | 225 | 13 | 52 | — |
| draws per solve, total | 4,494 | 447 | 471 | 525 | — |
| solves that draw at all | 223 (**0.85 %**) | 0.49 % | 1.1 % | 1.7 % | — |
| dequeues (steps), max / total | **217** / 4,726 | 79 / 13,608 | 60 / 16,360 | 137 / 10,035 | — |
| chain depth, max | **2** | 2 | 2 | 3 | ≤ 4 |
| **minted vocabulary, max** (`--cycle` `maxmint`) | **27** | 11 | 4 | 8 | ≤ 11 |
| **per-key mints, max** (`--mints`) | **1** | 1 | 1 | 1 | 1 |
| initial mints, max (`mint0`) | 5 | 4 | — | — | — |
| re-minted keys, max | 1 | 1 | 0 | 0 | — |
| distinct keys, max (`maxdkey`) | 30 | 21 | — | — | — |
| decision nodes (states), max | **218** | 80 | 60 | 137 | — |
| splits, max / total | 1 / 9 | 3 / 127 | 4 / 349 | 8 / 303 | — |
| **resolution steps, max / total** | **1,241 / 4,281** | 225 / 447 | 7 / 471 | 41 / 525 | — |
| `concrete` branch, share of dequeues | 20.4 % (963/4,726) | 22.6 % | 19.0 % | 15.5 % | ~25 % |
| `concrete` branch, share of solves | 3.09 % | 5.38 % | 6.2 % | 5.7 % | — |
| vocabulary-fixed (`grew=false`) | **99.89 %** | 99.81 % | 99.49 % | 99.09 % | 97.4 % |
| generative rules (`grew=true`) | 0.11 % (28 solves) | 0.19 % | 0.51 % | 0.91 % | ~2.6 % |
| input row variables, max | 16 | 16 | 42 | 11 | — |
| input partitions, max | 13 | 13 | 24 | 7 | — |
| label table, max | 14 | 30 | 31 | 14 | — |

**The mint row, correctly labelled.** `--cycle`'s `maxmint` is `max rep.maxMint mo.length` where
`mo = mintOrder s` (`Cycle.lean:407`) — the size of the MINTED-VARIABLE VOCABULARY at a step, not
a per-key count. The per-key census is `looptrace --replay … --mints`, and over `Lang/`:

```
Lang/ --mints:  solves=26213  max=1  remint=0  cmax=2  cremint=1  keys=1
```

**The per-key mint maximum is 1**, which is what every E-series group reports. An earlier draft of
this report gave `maxmint` as "per-key mints, 29 … against a round-7/8 bound of 11 and E4's 12,
which was itself the first breach" — three errors in one cell, and the same mislabel E4's review
(M-1) and E3's (P-18) had already corrected. **No group in the E series has ever exceeded a
per-key mint count of 1.** What IS a corpus record is the vocabulary figure, 27. (L-1.)

**Budget headroom, and why the number is not the point.** The largest draw count in the group is
**1,241** against the adopted `solveBudget=20000` — 6.2 % of it, nominally 16× headroom. E5's
reviewer showed (as E4's had) that this ratio is the wrong statistic: the headroom is not a
property of a stable shape, it is a count of `t ! f`s in one lambda, and **two more columns in
the same lambda crosses it** (§4.1). The honest statement is that every module here sits at
N = 5 and the budget fires at N = 7.

**What moved, and what shape this group reaches that the corpus did not.**

Three numbers are records for the E series, and all three are the same phenomenon:

```
 drawn=1241 nres=1241 nsplit=0 conc=0 steps=217 states=218 maxmint=27 grew=true
     core/examples/Lang/TextTables.e(135:13)    -- catalogueMarkdown's cell lambda, 5 projections
 drawn=1233 nres=1233 nsplit=0 conc=0 steps=215 states=216 maxmint=27 grew=true
     core/examples/Lang/RunningState.e(209:13)  -- postingMarkdown's,               5 projections
 drawn=1230 nres=1230 nsplit=0 conc=0 steps=211 states=212 maxmint=26 grew=true
     core/examples/Lang/TextTables.e(171:23)    -- catalogueAscii's,                5 projections
 drawn=210  nres=210  ...  maxmint=12
     core/examples/Lang/FreeReportDsl.e(153:17) -- factRows',                       4 projections
 drawn=207  nres=207  ...  maxmint=11
     core/examples/Lang/TextTables.e(185:9)     -- catalogueCsv's,                  4 projections
```

* **1,241 draws** against E4's 225 — 5.5× the previous maximum, and 95× `Time/`'s.
* **every one of them a `Resolution` step, with zero splits and zero `concrete`** — E4 found the
  first solve of this kind; this group's costliest five are ALL of this kind.
* **a minted vocabulary of 27** against E4's 11.

The three are the same three bindings before and after §8's corrections; their ORDER is not
stable — on the pre-correction bytes it was `catalogueAscii` 1,245, `postingMarkdown` 1,241,
`catalogueMarkdown` 1,230 — because each of the three sits within ±1 % of the others and
unrelated edits in the same module move them by a few draws. Quote them as a set of three, not
as a ranking; an earlier draft of this report named `catalogueMarkdown` alone as "the most
expensive solve in the group" while its own table said otherwise (L-8).

**And the annotated spellings, in the same modules, cost 1 draw each.** `catalogueMarkdownPinned`
(`TextTables.e:152–156`) and `postingMarkdownPinned` (`RunningState.e:220–221`) are the same
tables with the cells lambda's argument annotated at the concrete row; every one of their
projections is `drawn=1`. E5's reviewer additionally measured that reordering `showRows`'s
arguments changes nothing (1,230 → 1,233). **The annotation is the only fix, and it is one
token.** (L-20.)

And the cause is not a wide row. Look at the input systems: `nvars=6 nparts=5 nlbl=5`. **Six row
variables.** The group's WIDEST input systems are somewhere else entirely and cost almost
nothing:

```
 nvars=16 nparts=13 nlbl=1 drawn=4 nres=0  CsvIntake.e(232:65)    -- the 6-column intake's filter
 nvars=16 nparts=13 nlbl=1 drawn=5 nres=0  ReaderParams.e(167:46) -- an 11-column predicate
 nvars=16 nparts=13 nlbl=2 drawn=7 nres=2  TreeAndMap.e(279:55)   -- Tree.fromRel's continuation
```

So the corpus now has both ends measured. `Time/` is **wide and cheap** (42 input variables, 13
draws); `Lang/` is **narrow and dear** (6 input variables, 1,241 draws). The variable that
predicts cost is neither the row width nor the partition count: it is **how many times one
record is projected inside one expression**, and §4.1 measures that series in isolation —
0, 3, 31, 207, 1,241, 6,956, and then the budget. E5's reviewer confirmed this conclusion
("exactly right") and the whole table apart from the mint cell.

`ReaderParams.e` is the positive half of the same lesson and is worth naming: its `Params` is a
CONCRETE row, so its five `askField` projections cost **4 draws between them** where five
projections of a row variable cost 1,241.

### G4(a) — every report EVALUATED in the REPL

There is no `render`. All twelve modules were loaded into ONE session (no two top-level names
collide) and **141 expressions were evaluated; zero unintended errors**. Exactly five values
print an error, and all five ARE the point:

| binding | prints | the finding |
|---|---|---|
| `parseInt 10 "1O2"` | `Just <error: For input string: "1O2">` | §4.2 |
| `ForeignJdk.notCaught` | the same, from a `foreign` declared in the module | §4.2 |
| `StatementParser.bombedAmount` | `Just (<error: For input string: "abc">,"rest")` | §4.2, and why `amountP` uses the total parser |
| `CsvIntake.diskLines` | the file, then `<error: … java.io.Console …>` | §4.13 |
| `ForeignJdk.caughtMissing` | `<error: /definitely/not/here.txt …>` | §4.12 |

    bin/ermine core/examples/Lang/Helpers.e core/examples/Lang/{…11 modules…}.e < g4.in

Trimmed renderings. **Four of these are documents you can read** — the only such output in
`core/examples`.

```
############ StatementParser — text parsed into a relation
>> parsedRows   : List (Record (|sourceLine, movementAmt, valueRef, narrative,
                                 movementKind, runningBal, postedOn|))  -- 7 rows, all parsed
     {sourceLine = "2011-03-01|REF00181|DEPOSIT|Opening balance brought forward|12500.00|12500.00",
      valueRef = "REF00181", postedOn = Mon Feb 28 17:00:00 MST 2011, movementAmt = 12500.0,
      movementKind = "DEPOSIT", narrative = "Opening balance brought forward", runningBal = 12500.0}, …
>> badLineResult : Nothing          -- "TRANSFERRED" is not in the keyword table
>> dateAgreement : Bool = True      -- the hand-written binds and the `do` block agree
>> statementRel  : Relation (|… 7 columns …|)

############ CsvIntake — five errors where `Either` gives two
>> intakeErrors : List (String, String) =
  [("partyId","unreadable cell 0: 1O2"),("creditLimit","unreadable cell 3: $750000.00"),
   ("riskGrade","unreadable cell 4: A+"),("onboardedOn","unreadable cell 5: 2010-XI-30"),
   ("onboardedOn","unreadable cell 5: ")]
>> shortCircuited : Left [("partyId","unreadable cell 0: 1O2"),
                          ("creditLimit","unreadable cell 3: $750000.00")]
                                    -- the first bad LINE only; lines 3 and 4 unmentioned
>> goodIntake : Right <relation with … partyId -> IntT, onboardedOn -> DateT …>

############ RunningState — the running balance, and a table you can read
>> closingBalance : Double = 90947.07
>> balanceTrail   : [250000.0,165375.0,208510.2,48270.20000000001,46420.20000000001,
                     143025.07,90947.07]
>> netAndFees     : (90947.07,2502.9300000000003)      -- two measures, one pass (`mproduct`)
>> feeRatios      : Nothing                            -- one posting has a zero gross
>> guardedRun     : Just ([…the same seven…],90947.07) -- StateT s Maybe
>> overdrawnRun   : Nothing                            -- the same fold without the opening row
>> postingMarkdown : String =
  "| Seq | Ref | Kind | Net | Running |
   | --- | --- | --- | --- | --- |
   | 1 | PST-4401 | OPENING | 250000.0 | 250000.0 |
   | 2 | PST-4402 | INVOICE | -84625.0 | 165375.0 |
   … | 7 | PST-4407 | INVOICE | -52078.0 | 90947.07 |"

############ ReaderParams — one report, three parameter sets
>> northSelection, coastSelection, allRegionsSelection : Relation (|… 11 columns …|)
>> bothCaptions : ["North at or above 12.0","North at or above 24.0"]           -- `local`
>> strictNorth : Just "Region North"  >> strictAll : Nothing                    -- ReaderT Maybe

############ FreeReportDsl — one program, three interpreters
>> describeOf salesProgram : ["text: # Bicycle sales, Q1 2011","text: ## By line and channel",
     "table: Q1 detail (5 rows, 4 columns)","total: Net sales","total: Units",
     "text: Prepared from `quarterFacts`."]
>> countOf salesProgram : Int = 12
>> renderOf salesProgram : String =
  "# Bicycle sales, Q1 2011
   ## By line and channel
   ### Q1 detail
   | Line | Channel | Units | Net |
   | --- | --- | --- | --- |
   | Road bikes | Retail | 412 | 593280.0 |
   … | Apparel | Online | 2210 | 171496.0 |
   **Net sales**: 2504163.5
   **Units**: 8492.0
   Prepared from `quarterFacts`."
>> churchDescription : ["text: # Bicycle sales, Q1 2011","total: Net sales",
                        "text: Prepared from `quarterFacts`."]
>> firstFive         : [593280.0,1114750.0,224437.5,400200.0,171496.0]
>> firstFiveSmoothed : [854015.0,669593.75,312318.75,285848.0,85748.0]   -- Cofree `extend`
>> nuTake 6 countUp  : [0,1,2,3,4,5]
>> nuTake 8 fibs     : [0,1,1,2,3,5,8,13]     -- the SAME type, a different hidden seed

############ DoNotation — one `do` block, five monads
>> maybeSum    : Just 42          >> listSum   : [11,12,13,21,22,23]
>> statefulSum : (201,102)        >> parsedSum : Just 42
>> fourWaysAgree : True           -- `do`, Syntax.Monad, Syntax.Maybe and Syntax.Either agree
>> pairsOfLegs : six ordered pairs -- the list monad as a comprehension
>> sixWide     : Just ["a","b","c","d","e","f"]      -- liftA6
>> chosen      : (0,9)            -- ifM runs ONE branch
>> firstCarrier : Just "Maersk"   -- Control.Alt over a table
>> densities   : Nothing          -- traverseRows in Maybe; one row has no weight
>> spoiltShipments : Left [("weightKg","SHP-9005: zero weight")]

############ TextTables — one relation, four readable renderings
>> catalogueMarkdown : String =
  "| SKU | Title | Brand | List | Stock |
   | --- | --- | --- | --- | --- |
   | SKU-1001 | **Carbon Road Frame** | *Velodyne* | 2450.0 | 34 |
   … | SKU-1006 | **Thermal Bib Tight Pro** | *Fjordkit* | 189.0 | 96 |"
>> catalogueAscii : String =
  "SKU         TITLE                     BRAND       LIST        STOCK
   ----------  ------------------------  ----------  ----------  -------
   SKU-1001    Carbon Road Frame         Velodyne        2450.0       34
   … SKU-1006    Thermal Bib Tight Pro     Fjordkit         189.0       96"
>> catalogueCsv : "SKU-1001,carbonRoadFrame,Velodyne,2450.0\n…"
>> tidyTitles   : ["Carbon Road Frame","Alloy Touring Wheelset",…]   -- splitCamelCase
>> priceCodes   : [["77"],["77"],["31"],["52"],["52"],["31"]]        -- StringManip.allMatches
>> markedRefs   : ["SUP-<77>/A",…]                                   -- replaceAll with a group
>> supplierLinks: ["[SUP-77/A](https://example.invalid/supplier/SUP-77/A)",…]  -- mdLink
>> brokenLinkType : (String -> String) -> String -> String           -- the shipped `link`

############ TreeAndMap
>> spendTreeShown : "Tree( ("Group",4000000.0), Tree( ("Commercial",900000.0)), … )"
>> nodeCount 8   >> treeDepth 3
>> leafLabels  : ["Platform","Data","Facilities","Logistics","Commercial"]
>> rolledUp    : [("Group",1.11E7),("Technology",3500000.0),…]   -- Tree.aggregate
>> numberedPairs : [(100,"Group"),(101,"Technology"),…]          -- Tree.identify
>> reRolledRel : Relation (|parentKey, nodeKey, nodeLabel, nodeBudget|)  -- ids MINTED
>> ownerTallyList : [("Ada Nwosu",1),("Board",1),("Ravi Menon",2),…]
>> unionLeftBiased : Tom Achterberg 610000.0   >> unionSummed : Tom Achterberg 2570000.0
>> sortedLabels : ["Facilities","Commercial","Group",…]   -- Ord composed with ordMonoid

############ ForeignJdk
>> maxInt : 2147483647     >> piValue : 3.141592653589793
>> scaledDecimals : [(1,4,"-120.5"),(5,2,"-0.00047"),(0,5,"-98500"),(6,7,"-1.750000")]
>> notCaught      : (Just <error: For input string: "1O2">)   -- §4.2, from scratch
>> caughtProperly : Just 102
>> guardedRead    : Nothing     >> guardedReadOk : Just 102   -- Helpers.parseIntTotal
>> firstRandoms   : [-2084821589,-1446856711,-634631282,-2003970265,-452295648,1819184432]
>> sameSeedSameStream : True    >> guidRoundTrip : True
>> ratedRms       : 246.17913531952024

############ TypesAndRows
>> fixityWorks : (6.0,True,True)          -- infixl, infixr, infix
>> shownValues : ["42","a string","3.25","yes"]      -- an existential
>> patternTour : ["literal zero","literal other","con Nothing","con Just 3","nested Left x",
     "nested Right 9","nested Nothing","as 3 head 1","as empty","tuple one/1","lazy two",
     "strict 5","wildcard"]                          -- every pattern form
>> rowsAndRows : Row [("assetTag",StringT(0,false)),…]  -- append and minus on `Row`
>> keySplit    : ({assetTag,assetName}, {…10 more…})    -- spanT
>> copiedIsFresh : True    >> copiedType : "StringT(0,false)"
>> roundTripped : 1729     -- Type.Eq subst
>> widened : 42.0          >> narrowed : (Just 42,Nothing)   -- Type.Cast
>> pinnedEmpty : List Double = []                            -- Type.Remember.unify
>> pinnedByWitness : 3.322E7

############ Signatures
>> permutationHolds : True   >> sugarHolds : True
>> pRecordSimple : Parser (Record (|ledgerRef, ledgerAmt|))
>> sameFieldTwice : ("L-1","L-1")   -- `Has r h1, Has r h2` does NOT say the two are disjoint
>> twiceOver maybeMonad (Just 5) : Just 10
```

**The bindings added by §8's corrections, evaluated in the same session:**

```
############ Helpers / StatementParser — the total parser, and the bomb it replaces
>> parseIntTotal "102" / "99999999999999" / "2147483647" / "2147483648"
                     : (Just 102, Nothing, Just 2147483647, Nothing)   -- L-6/L-7 fixed
>> bombedAmount      : Just (<error: For input string: "abc">,"rest")  -- what amountP used to do
>> goodAmount        : Nothing                                          -- what it does now

############ TextTables — the link that works, and the annotated lambda
>> workingLink            : "[SUP-77/A](https://example.invalid/supplier)"   -- L-2
>> catalogueMarkdownPinned: the same table as catalogueMarkdown, 1 draw against 1,241

############ DoNotation — Id, ErrorT, and the four previously-uncalled helpers
>> identitySum, identitySumNamed : 42, 42          -- a sixth monad, and `inMonad`
>> dividedOk   : Id (Right 42.0)      >> dividedBad : Id (Left "divide by zero")
>> dividedOverMaybe : (Just (Right 42.0), Just (Left "divide by zero"))
>> preferredCarrier : Just "Hapag"    >> carrierOrHouse : Just "house account"
>> allCarrierCodes  : Right [1,2,3]
>> everyBadCode     : Left "bad ref; bad weight"   -- accumulating, not short-circuiting
>> weightOrZero     : [Just 18400.0,Just 0.0,Just 0.0]
>> weightRange      : (9100.0,33800.0)             -- min and max in ONE pass

############ FreeReportDsl — the eliminator the stdlib does not ship
>> countedByFold : 12 -> 6   -- `foldFree` in `State Int`; `countOf` counts LINES, this
                             --   counts COMMANDS, which is the honest difference
>> foldedProgram : [()]      -- the same program in the list monad

############ TreeAndMap — List.NonEmpty, named
>> rootLabel   : "Group"
>> restLabels  : ["Technology","Platform","Data","Operations","Facilities","Logistics",
                  "Commercial"]

############ ForeignJdk — the declarations that were decoration, now used
>> bothAbsOverloads : (42,42.5)      -- one Java method, two Ermine names, two types
>> decimalStrings   : ["120.5","0.00047","98500","1.750000"]   -- `subtype` in use
>> shouted, readLongUnsafe, representable — the `method`, `IO` and `value` forms
>> caughtMissing    : <error: /definitely/not/here.txt (No such file or directory)>  -- §4.12

############ TypesAndRows — rank-2 and Control.Category
>> rank2Works     : ([7],[])      -- the rank-2 field, applied
>> revaluedTwice  : 1080470.0     -- three transformations folded through catEndoMonoid
>> categoryIdIsId : True

############ CsvIntake — the real file
>> diskLines : the three CSV lines, then
   <error: error invoking static foreign function: writeron object of type null;
           expected an object of type class java.io.Console>                    -- §4.13
```

### G4(b) — the `.ei` for every module, and the round trip

`-Dermine.useInterface=true` over the whole group writes twelve interfaces (corrected bytes;
E5's reviewer reproduced the pre-correction counts 74/57/38/34/31/26/26/25/23/22/20/16 exactly):

```
Helpers.ei 75   TypesAndRows.ei 64   DoNotation.ei 50   TreeAndMap.ei 37
FreeReportDsl.ei 35   ForeignJdk.ei 32   ReaderParams.ei 26   Signatures.ei 26
TextTables.ei 25   CsvIntake.ei 24   RunningState.ei 21   StatementParser.ei 19
                                                            (signatures each, 434 total)
```

§2 lists what `Helpers.ei` publishes for every helper. A **second** `useInterface=true` load,
which reads those interfaces back instead of re-inferring, checks every module again and also
resolves a `foreign` name through the interface:

```
Importing module 'Lang.Helpers' (0.66 seconds) … 'Lang.TypesAndRows' (0.32 seconds)
Importing module 'ForeignProbe' (0.02 seconds)      -- `strLength` from Lang.Helpers
```

so the interfaces round-trip, including the `private` lines they should not carry and the
`foreign` lines they do not carry (§4.7). **All `.ei` files were deleted afterwards**, as the
gate requires; `find core/examples -name '*.ei' | wc -l` is **0**. `Helpers.ei` is
byte-identical before and after the compiler rebuild of §G0.

### G5 — this report, the plan row, the wiring lines, and what could not be written

Sections 1, 2, 5 and 6; the plan row is appended to `tracker/LOOP-MODEL-PLAN.md` after E4's.

---
## 4. Findings

Fourteen, each with a minimal module or a two-line REPL repro. Every one is about the LANGUAGE or
its toolchain, which is what this group is for. §§4.12–4.14 were found by E5's reviewer and are
added here with their probes; §§4.3, 4.6(3) and 4.8 have been corrected where the reviewer
refuted them, with the refutation shown rather than the claim quietly dropped.

### 4.1 THE PROJECTION CLIFF: seven `!`s on one record in one expression do not compile

`t ! f` on a record whose row is a VARIABLE is a `Has r f`, i.e. `exists c. r <- (f, c)` — one
existential row partition. **N projections of the same record in one expression are N
existential partitions over one whole**, and the solver resolves them against one another. The
cost, measured one module per N, one JVM each, at the shipped defaults:

| N | draws | dequeues | minted vocabulary | module load |
|---|---|---|---|---|
| 1 | 0 | 0 | 0 | 0.14 s |
| 2 | 3 | 5 | 1 | 0.11 s |
| 3 | 31 | 23 | 5 | 0.13 s |
| 4 | 207 | 65 | 11 | 0.21 s |
| 5 | **1,241** | 217 | **27** | 0.68 s |
| 6 | **6,956** | 698 | **60** | 2.00 s |
| **7** | **> 20,000 — the draw budget FIRES** | — | — | 2.93 s, **REJECTED** |

```
core/examples/Lang/ProjectionCliff.slow:1:1: Row solver resource limit reached (this is NOT a
type error): the row constraint solver drew 20009 fresh row variables at this signature, past
the -Dermine.solveBudget=20000 limit, so it was stopped rather than left to run.  Raise the
limit with -Dermine.solveBudget=<n>, simplify the row constraints at this signature, or report
it.
```

The ratio is a steady ~6× per extra projection and it crosses the budget at seven. **This is
not an exotic shape**: it is what anyone writes to render a row of a table —

```
showRows hdr (t -> [t ! a, t ! b, t ! c, t ! d, t ! e, t ! f, t ! g]) rows
```

— for a SEVEN-column table. THREE bindings in this group are exactly this with five columns, and
they are the three most expensive solves in the whole E series (§G3):
`TextTables.catalogueMarkdown` (1,241 draws), `RunningState.postingMarkdown` (1,233) and
`TextTables.catalogueAscii` (1,230) — a set, not a ranking: all three are within 1 % of one
another and unrelated edits in the same module reorder them.

**The user's fix is to write the row down, and it is the ONLY fix.** E5's reviewer isolated the
remedy on this group's own helper shape: reordering `showRows`'s arguments so that the
row-fixing one is checked first changes **nothing** (1,230 draws becomes 1,233), while
annotating the lambda's argument at the concrete row takes the same call to **1 draw, 2 steps**.
The seven projections with the argument annotated `{q1, …, q7}` load in **0.04 s**: with a
concrete row there is no row variable and no existential at all. That is the same signature the
star-join cliff has in `core/examples/incomplete/README.md` — "same eight dimensions, and the
type annotation is the only difference." `TextTables.e` and `RunningState.e` now ship BOTH
spellings side by side (`catalogueMarkdownPinned` at 1 draw beside `catalogueMarkdown` at
1,230; `postingMarkdownPinned` beside `postingMarkdown`).

**Independently found, twice.** E4's reviewer isolated the same cliff at the same time, from
the presentation side, with a differently-shaped probe (`ProbeCascade.e`: bare `p ! f`
projections rather than a list literal), and got 3 / 33 / 207 / 1,243 / 6,795 / budget against
my 3 / 31 / 207 / 1,241 / 6,956 / budget — the same curve, the small differences being the one
extra variable my list literal introduces. E4 now ships
`core/examples/Present/shouldfail/proj01_seven_reads.e` as the negative, and `E4-REVIEW.md`
carries the ladder and the conclusion that E4's "89× budget headroom" was its most misleading
sentence. **E5 is not first; it is the second, independent measurement**, and it is the one that
explains this group's three costliest solves.

E4's reviewer also found the stronger remedy: five projections under **one WRITTEN partition**
(`forall r o. (r <- ((| p1, …, p5 |), o)) => {..r} -> String`) cost **0 draws** — not merely
cheaper, free. `ProjectionCliff.slow`'s `p7fixed` shows the concrete-row version of the same
point (0.04 s).

The whole series ships as `core/examples/Lang/ProjectionCliff.slow`, `.slow` rather than `.e`
because `core/test` type-checks every `.e` under `core/examples` and N = 7 does not compile. It
is deliberately NOT a second `shouldfail/` module: E4's `proj01_seven_reads.e` already carries
the refutation, and what this file adds is the CURVE, which is worth having in the tree but not
worth a 26 MB row trace and a minutes-long Lean replay on every `looptrace-corpus.sh` run.



### 4.2 `Parse.parseInt` and `Parse.parseDouble` are not total, and the way they fail is worse than throwing

Two lines, no example code, no imports:

```
>> parseInt 10 "1O2"
res0 : Maybe Int = (Just <error: For input string: "1O2">)
>> isJust (parseInt 10 "1O2")
res1 : Bool = True
```

`Just` wrapping a bomb. **Every validator built on `Parse` reports SUCCESS and then throws at
the point of use**, with no field name attached and no way for the caller to have known. This
is the most consequential defect the group found, because `Parse` is the only string-to-number
route the stdlib has and `Validation.e`'s entire library (`validateInt`, `validateDouble`,
`lookupInt`, `lookupDouble`, and therefore `Layout.Validation.withValidation`) is built on it.

**The mechanism**, precisely. `Parse.numberFormat` is

```
numberFormat m = case unsafeFFI m of
  Left e@(NumberFormatException _) -> Nothing
  Left e  -> raise e
  Right n -> Just n
```

and `IO.Unsafe.unsafeFFI` calls the `eval` primop, `Lib.scala:1311`:

```scala
primOp(Global("IO.Unsafe","eval"), fun3((t,c,e) => try {
  val r = e.extract[FFI[_]].eval
  t(Prim(r))
} catch { case err: Throwable => c(Prim(err)) }), …)
```

which looks correct. It is defeated one level down. Forcing the `FFI` runs
`Session.scala:993`'s `perhapsForeign(Raw, v) = Prim(v)`, and `Runtime.scala:51`'s
`object Prim`:

```scala
def apply(p: => Any) = try {
  val pForced = p
  pForced match { case r: Runtime => r; case p => new Prim(p) }
} catch { case e: Throwable => Bottom(throw e) }
```

**`Prim.apply` catches the exception and returns a `Bottom` VALUE.** So `eval`'s own
`try/catch` can never fire, `unsafeFFI` always takes its `Right` branch, and
`numberFormat`'s `NumberFormatException` clause is dead code. (`parseBool`, written in Ermine,
is correct — it returns `Nothing`.)

**Reproduced from scratch** in `Lang/ForeignJdk.e`, so it is visibly the FFI mechanism and not
`Parse`: the module declares its own `function "java.lang.Integer" "parseInt" readIntFFI :
String -> Int -> FFI Int`, runs it through `unsafeFFI`, and `notCaught` is `Just <error: …>`
while `caughtProperly` (a good string) is `Just 102`.

**The workaround that works from Ermine** is to check the STRING first, which is what
`Helpers.parseIntTotal` / `parseDoubleTotal` do (`Character.isDigit` over
`Helpers.stringChars`, one optional minus, at most one decimal point). Every cell reader and
every parser in the group routes through them. The difference is visible in `Lang/CsvIntake.e`:
with `Parse` the bad-CSV intake reported **two** errors and silently accepted two bombs; with
the total readers it reports **five**, which is the number of things actually wrong.

Not fixed here: `Prim.apply`'s `catch` is load-bearing elsewhere (it is how a `Bottom` reaches
the printer as `<error: …>` instead of killing the REPL), so this is a design question, not a
one-character fix, and recompiling the compiler mid-stage would invalidate every measurement in
this report.

### 4.3 `String.Markdown.link` demands its title pre-composed, so no ordinary call site works

`String/Markdown.e` is eight lines and one of its three functions is wrong:

```
link title loc = "[" ++ title "](" ++ loc ++ ")"
```

`title "]("` is an APPLICATION — juxtaposition binds tighter than `++` — so the module
type-checks with

```
link : (String -> String) -> String -> String
```

and `link "My title" loc` is a type error. `TextTables.brokenLinkType` pins that type, and it
compiles, which is the demonstration.

**What this report first said, and what is actually true.** The earlier draft said "there is no
argument you can pass that produces `[title](loc)`", and `TextTables.e`'s header said "can never
produce a link". E5's reviewer refuted both with a module that loads (L-2): pass the title
**pre-composed with `++`** and the shipped `link` is correct.

```
>> link_MD ((++_S) "SUP-77/A") "https://example.invalid/supplier"
res : String = "[SUP-77/A](https://example.invalid/supplier)"
```

because `title "]("` with `title = (++) t` is `t ++ "]("`, which is exactly what the author meant
to write. `TextTables.workingLink` now evaluates this. The correct statement is therefore: **the
function works only when its title argument is a prefixing function, so every ordinary call site
is a type error and the one working spelling is undocumented and unguessable.** A single missing
`++` is still the whole fix.

### 4.4 The REPL trap, exactly: a substring, and a `null`

E4 §4.7 recorded that `Console.other` treats `case`/`let`/`where` as SUBSTRINGS. The complete
mechanism has a second half, and together they make the loop unbounded rather than merely long.

`Console.scala:617`:

```scala
val verbose = Set("case","let","where")
while ((needMoar || (balanced(input) == Unbalanced) || verbose.exists(input.contains(_))) && !blank) {
  val last = e.readLine("|> ")
  blank = last == ""
  if (!blank) { input = input + "\n" + last }
}
```

and `Console.scala:146`:

```scala
def readLine(prompt: String): String =
  try reader.readLine(prompt, echoCharacter)
  catch { case _: EndOfFileException => null; case _: UserInterruptException => "" }
```

**At EOF `readLine` returns `null`, and `null == ""` is false in Scala.** So `blank` never
becomes true, `"\nnull"` is appended to `input` on every pass, and `balanced` and `contains`
rescan a string that grows by five characters each time. Measured:

```
$ printf '"complete"\n' | bin/ermine        # "comp-LET-e"
rc=124 (killed by timeout 40)  elapsed=40s  3,837 '|>' prompts and still going

$ printf '"complete"\n\n' | bin/ermine      # one blank line after it
rc=0  elapsed=9s
>> |> res0 : String = "complete"
```

(E5's reviewer measured **3,900** prompts in the same 40 s on a less loaded machine, and the
blank-line control exiting in 8 s. The count is a machine-speed figure, not a constant.)

Minimal input: **any line containing the substring `case`, `let` or `where` — including inside
a string literal or an identifier — followed by end of input rather than a blank line.**
`"complete"` is enough; the line is never even parsed. Two independent one-line fixes:
`blank = (last == null || last == "")`, and testing for the three keywords as tokens rather
than as substrings.

No name in `core/examples/Lang/` contains one of the three substrings, so every recipe in the
group README is safe to pipe.

**This is ticket A2, already filed**, whose recorded minimal input is `printf 'staircase\n'`;
`"complete"` is a second instance of the same substring trap (`comp-LET-e`), not a new mechanism,
and the *unbounded* half was E4's reviewer's. E5's contribution is the second minimal input and
the measured prompt count (the reviewer's own run: **3,900** prompts in 40 s, with the blank-line
control exiting in 8 s). Cited rather than claimed. (L-14.)

### 4.5 The interface printer emitted a scheme the surface language rejects — and stopped

Two facts, one stable and one that moved under this stage.

**(a) The stable one.** A kind-polymorphic value type cannot be written, because `->` demands
kind `*` on both sides. The minimal case needs no rows, no records and no library:

```
atAnyKind : forall {k} (a: k). a -> Int
atAnyKind x = 1
-- error: failed to unify kind * with kind !k
```

`Lang/shouldfail/lang07_kind_variable_written.e` is that module, and it is rejected on every
version of the tree this stage saw.

**(b) The one that moved.** Before **2026-09-07 03:22**, `-Dermine.useInterface=true` over an
eta-delegating wrapper wrote exactly such a scheme. `iAskField f = askField f` published

```
iAskField : forall {a} (h: rho) (a1: a) (e: rho). (exists (c: rho). e <- (h, c))
         => Builtin.Field h a1 -> Builtin.Record e -> a1
```

— an `.ei` that does not round-trip through the surface parser. After another agent's
uncommitted `Subst.scala` change was compiled (§G0), the same wrapper publishes

```
iAskField : forall (h: rho) a (e: rho). (exists (c: rho). e <- (c, h))
         => Builtin.Field h a -> Builtin.Record e -> a
```

with the value type at kind `*` and no `{a}` anywhere. Four delegated wrappers in
`<scratch>/Infer.e` behaved the same way, before and after. I did not verify causation — that
would mean reverting another agent's file and rebuilding — so what is recorded is the
correlation, the timestamps and the fingerprint. The observation is worth keeping either way:
**the printer CAN emit a scheme the parser will not read**, and nothing in the build checks that
it does not.

**(c) And the partitions are permuted, unpredictably.** On the current compiler the four
wrappers publish

```
iConsRow    : … t <- (r, s) …    -- the shipped order
iPRecord    : … t <- (s, r) …    -- permuted, same body shape, same shipped order as consRow
iWithRunning: … t <- (r, c) …    -- the shipped order
jWithRunning: … d <- (c, a) …    -- the same function written out rather than delegated: permuted
iAskField   : … (exists c. e <- (c, h)) …   -- `Has e h` expands with its parts the other way
                                            --   round from the way `Constraint.e` writes it
```

The permutation is harmless — the right-hand side of a partition is a SET and `Signatures.e`
proves the pairs entail one another in both directions — but it is not stable across two
spellings of the same function, so **an `.ei` read as documentation will not always match the
source it came from.**

### 4.6 Four parse limits a writer of examples will hit

Each has a one-line repro; all four cost a compile here.

1. **A bracket or brace literal with a module suffix cannot be a non-final argument.**

   ```
   u = const []_L "x"     -- error: expected eof or whitespace   (at the "x")
   v = const ([]_L) "x"   -- fine
   w = const "x" []_L     -- fine: last argument
   ```

   Brace literals are the same: `const {a1}_Simple_Lg "x"` fails identically. It hit five times
   across the group (`CsvIntake`, `DoNotation` ×5, `FreeReportDsl`, `TypesAndRows`).

   **The `where` clause is narrower than this report first said** (L-16). A `]_L` that is the
   whole right-hand side cannot be followed by `where` — which is the shape `TypesAndRows.e` hit,
   and why its pattern tour is thirteen top-level functions — but a `]_L` in a function's last
   *argument* position can be (`k2 = length_L [1,2,3]_L` with a `where` under it loads), and so
   can a `where` whose bindings merely contain bracket literals.

2. **A bracket literal is not a pattern.** `[Just y, Just m, Just d]_L ->` is
   `expected "-", operator, or whitespace`: `[…]_M` desugars to `cons_Bracket_M` applications,
   which are terms. Cons patterns are the way.

3. **A character literal is rejected by POSITION, not by which character it is.** The earlier
   draft of this report said the criterion was the character; E5's reviewer refuted that with
   seven minimal modules (L-3), and this group's own `TextTables.e` writes `split_S '/' p`.

   | source | result |
   |---|---|
   | `dash = '-'` | LOADS |
   | `split_S '-' "a-b"`, `split_S '.' …`, `split_S '\|' …` | LOAD |
   | `c == '-'` | `error: unknown operator '-'` |
   | `c == '.'` | `error: unknown operator '.'` |
   | `c == '/'` | `error: unknown operator '/'` |
   | `c == ('-')` | `error: undefined term` |

   The criterion is position: **immediately after a binary operator** the lexer's maximal munch
   takes `'` and the character as one operator token, and every operator character fails there,
   `/` included. In head or argument position they all lex. Parenthesising does not help; naming
   the literal does, which is what `Helpers.dashChar`, `dotChar` and `pipeChar` are for — and why
   every comparison in `Helpers.e` is against a name.

4. **There are no operator sections.** `(2 +)` is `error: ill-formed expression`; `(+ 2)` is
   `error: unknown operator +`. Only the bare `(+)` is a term. The brief listed "operator
   sections and fixity declarations" as under-exampled; fixity declarations exist and are
   exercised in `TypesAndRows.e` (`infixl`, `infixr`, `infix`, and `infix type` in
   `Constraint.e`), sections simply do not.

### 4.7 An `.ei` is neither a subset nor a superset of the module's surface

Two facts, measured on this group's own interfaces.

* **`private` bindings ARE listed.** `Lang/Helpers.ei` carries `punit`, `pbind`, `por` and
  `mconcat`; `Lang/TypesAndRows.ei` carries `scaleBy` and `unwrap`. They are nevertheless not
  importable: a module that says `import Lang.Helpers` and mentions `punit` gets
  `error: undefined term`, under `-Dermine.useInterface=true` as well as without it.
* **`foreign` declarations are NOT listed.** `Helpers.e`'s `strLength`, `strIsEmpty`,
  `strCharAt`, `charIsDigit` and `charIsLetter` appear nowhere in `Helpers.ei` — and a module
  that imports `Lang.Helpers` resolves `strLength` perfectly well.

So an `.ei` is a compilation cache, not a published API, in both directions. Reading one as
documentation over-reports (privates) and under-reports (foreigns) at the same time.

### 4.8 What `Prelude`'s unqualified scope actually binds

E4 §4.9(2) recorded that `map` needs `Syntax.List`. The list is longer, and every entry cost a
compile here:

| you write | you get | what you wanted |
|---|---|---|
| `length s` | `List.length` | `length_S` (a builtin registered as `String.length`) |
| `a ++ b` | `List.(++)` | `++_S` |
| `a \|\| b` | `Layout.Report.(\|\|)`, selector-event disjunction | `\|\|_B` |
| `map f xs` | undefined | `Syntax.List`, imported explicitly |
| `filter p r` | `List.filter` (it *does* resolve) | `filter_Pred`, for a relation |
| `padRight`, `padLeft` | `Layout.Report`'s | your own name |
| `empty_Bracket` | `List`'s | `import Prelude hiding {…}` |

`import Prelude hiding length` does **not** reveal the builtin: it makes `length` undefined.
The builtin's `Global` is `("String","length")`, so `length_S` after `import String as S` is
the only spelling. `&&` is unaffected — `Layout.Report` does not define it.

**One row of this table was wrong** and E5's reviewer refuted it with a module that loads (L-4):
`filter` is **not** undefined. `List.filter` is public (`List.e:224`) and `Prelude` exports
`List`, so `filter (n -> n > 2) [1,2,3,4]` is `[3,4]`. Only `map` is `private` in `List.e` and
therefore reachable only through `Syntax.List`. What is true of `filter`, and is what the writer
actually hit, is that the resolved one is the LIST filter and a relational filter needs
`filter_Pred`.

### 4.9 `Data.Nu`'s seed is genuinely opaque, which makes `Nu f` useless for most `f`

```
data Nu f = forall s. Unfold (s -> f s) s
seedOf (Unfold f x) = x
-- error: skolem variables escape:   Type would have been: Nu f -> !s
```

`observe : Functor f -> Nu f -> f (Nu f)` is the only elimination, so a `Nu f` yields nothing
observable unless `f` itself carries a value. `Nu Nxt` where `data Nxt a = Nxt a` is an
infinite chain of nothing; `Nu Step` where `data Step a = Step Int a` is a stream of `Int`.
`Lang/FreeReportDsl.e` shows both, and `countUp` (seed `Int`) and `fibs` (seed `(Int, Int)`)
have the same type — which is what the existential is for.
`Lang/shouldfail/lang06_escaping_existential.e` is the negative.

### 4.10 Five smaller facts

1. **There is no `mod`.** `Num` has `+ - * / pow abs neg toInt toDouble` and nothing else; `/`
   on `Int` is integer division, so a remainder is `a - (a / b) * b`.
2. **`Ord` is a value and therefore composes.** `Ord.ordMonoid : Monoid (Ord a)` with
   `Ord.contramap` gives "sort by status, then by owner" as `mappend ordMonoid (contramap … )
   (contramap … )`, which no class-based `Ord` can express as cheaply.
   `Lang/TreeAndMap.e` uses it.
3. **`Tree.join` carries a `-- BUSTED:` comment above a definition that works.** The comment
   records that the more natural spelling of the same signature did not type-check; the shipped
   one, at different variable names, does.
4. **`Map.union` is left-biased and `Map` needs an `Ord k` VALUE at construction.**
   `Map.valueMonoid : Ord k -> (v -> v -> v) -> Monoid (Map k v)` is the grouping primitive; it
   is what makes `foldRows` over maps work.
5. **`Field.withFieldCopy` mints a GUID-named field.** `uniqExistentialF` calls `GUID.guid`, so
   the copy's `fieldName` is a fresh 36-character uuid and differs on every run.
   `Lang/TypesAndRows.e` says so and checks the deterministic consequence instead.

### 4.11 Left recursion is not a type error, and there is no negative for it

`pMany p` where `p` can succeed without consuming input loops forever, and so does
`expr = bind expr (…)`. Ermine says nothing about either: `Parser a` is a function type and a
diverging function is well-typed. The brief asked for "a parser with an infinite left recursion
caught at the type or runtime level"; **it is caught at neither**, so
`Lang/StatementParser.e` documents it and `shouldfail/` has no module for it. What the language
*does* reject about a parser is a row disagreement, and that is `lang01`.

### 4.12 `IO.catch` cannot catch a foreign exception either

§4.2 scoped the `Prim.apply` conversion to `FFI` and `unsafeFFI`. It is not scoped to them, and
E5's reviewer showed it (L-9). `Session.scala:993`'s `perhapsForeign` routes the `IO` branch
through the same `FF` case, so an `IO` action built from a `foreign` declaration has its
exception converted to a `Bottom` VALUE before any handler exists — and `IO.catch` is `IO`'s only
handler:

```
caughtMissing = unsafePerformIO (catch (readFile "/definitely/not/here.txt") (e -> return "caught"))
>> caughtMissing
res : String = <error: /definitely/not/here.txt (No such file or directory)>
```

The handler does not run. **Every `IO` error path in the stdlib is unreachable for an exception
raised by the foreign call itself.** That is a bigger statement than §4.2 makes.

The distinction worth drawing, and the reason the bug is survivable at all: a PLAIN
(non-`FFI`, non-`IO`) foreign only DEFERS. `Helpers.strCharAt "" 0` reaches the REPL as
`runtime error: Index 0 out of bounds for length 0`, because the `Bottom` rethrows when forced.
So the conversion does not lose the exception; it converts a **catchable** one into an
**uncatchable deferred** one, and the damage is confined to code that tries to catch.
`Lang/ForeignJdk.e` section 4b ships both bindings.

### 4.13 `File.readFile` traces its own result, so every `File`/`IO.CSV` read returns a bomb

`File.e`:

```
withSource# f s = let res = f s in let x = close# s in traceShow res
sourceToString# = map $ withSource# mkString#
```

`readFile` **traces its own result**. `IO.trace` writes through `IO.printLn`, which is
`printLn# (writer# mkConsole)` where `mkConsole` is `java.lang.System.console()` — `null` under a
pipe or a redirect. Measured on `Lang/CsvIntake.e`, piped:

```
>> diskLines
101,Aldgate Joinery,EMEA,2500000.00,A1,2009-04-17
102,Brackenridge Mills,AMER,750000.00,B2,2011-01-08
103,Cheviot Castings,APAC,1200000.00,A2,2010-11-30
res0 : List (List String) =
  <error: error invoking static foreign function: writeron object of type null;
          expected an object of type class java.io.Console>
```

The READ SUCCEEDED — those three lines are the file, dumped to stdout by the trace. What failed
is the trace call, and by §4.12's mechanism it takes the value with it. So `File.readFile`,
`File.fileLines`, `IO.CSV.readCSVFile` and `readCSVURL` **dump the file and then hand back a
bomb**, in every session. One line of `File.e` is the whole fix. (Found by E5's reviewer, L-10;
this is why §6.5's original reason — "there is no data file to point it at" — was wrong.)

### 4.14 A rank-2 function ARGUMENT cannot be applied, which is why every dictionary is a `data`

A rank-2 signature is accepted; a rank-2 argument cannot be used (L-11):

```
oneWay : forall f m. (forall x. f x -> m x) -> f Int -> m Int
oneWay nat a = nat a
-- error: failed to unify type (forall x. f x -> m x) with type (a -> b)
```

The signature parses and elaborates. The term language cannot apply the argument. Put the same
`forall` in a DATA FIELD and it works, which is what `Helpers.Nat` is:

```
data Nat f m = Nat (forall x. f x -> m x)
applyNat (Nat k) fx = k fx        -- fine
```

**That one fact explains the shape of the whole `Control.*` hierarchy.** Every dictionary in the
stdlib keeps its polymorphism in a field rather than taking it as an argument — `Monad`,
`Traversable`, `Comonad`, `Category`, `F`, `Nu` — and it is why `Data/Free.e` has no `foldFree`
(its natural type takes a natural transformation as an argument) while `Data.Free.Church`'s
`runF` needs no functor at all: `F`'s rank-2 is already inside a `data`. It is also why the
`foldFree` this group now ships (§6.2) needs the `Nat` wrapper.

`Lang/TypesAndRows.e` section 9 is the worked demonstration; the failing form is quoted there
rather than shipped as an eighth negative, because `lang06` and `lang07` already carry the two
type-level refutation classes and what earns this a place is the consequence, which a reader
meets in every `Control` signature.


---

## 5. Wiring lines the orchestrator must add

E5 edits nothing outside `core/examples/Lang/`, `tracker/loopmodel/E5-EXAMPLES.md` and its own
row in `tracker/LOOP-MODEL-PLAN.md`. **Three** shared files need an addition; a fourth does not.

**(a) `tracker/tools/looptrace-corpus.sh`** — a `Lang)` case beside `Present)`, and
`Lang Lang-shouldfail` in the default group list (line 53):

```bash
    # Lang/ is the Ai/ case with a different library: every Lang module imports
    # `Lang.Helpers`, and so does every module under Lang/shouldfail (stage E5, 2026-09-07).
    Lang) mapfile -t gf < <( { echo core/examples/Lang/Helpers.e
                               find core/examples/Lang -maxdepth 1 -name '*.e' \
                                    ! -name 'Helpers.e' | sort; } ) ;;
    Lang-shouldfail)
          mapfile -t gf < <( { echo core/examples/Lang/Helpers.e
                               find core/examples/Lang/shouldfail -maxdepth 1 -name '*.e' \
                                 | sort; } ) ;;
```

and

```bash
groups="${LOOPTRACE_GROUPS:-boot top Ai Wide Wide-shouldfail Present Present-shouldfail Time Time-shouldfail Algebra Algebra-shouldfail Lang Lang-shouldfail shouldfail bugs guide shouldfail-controls incomplete}"
```

**(b) `tracker/tools/corpus-run.sh`** — add the group to `files` (line 105) and hoist
`Helpers.e` in both the batch and the per-file paths:

```bash
files=( core/examples/*.e core/examples/Ai/*.e core/examples/Wide/*.e \
        core/examples/Wide/shouldfail/*.e core/examples/Algebra/*.e \
        core/examples/Algebra/shouldfail/*.e core/examples/Time/*.e \
        core/examples/Time/shouldfail/*.e core/examples/Present/*.e \
        core/examples/Present/shouldfail/*.e core/examples/Lang/*.e \
        core/examples/Lang/shouldfail/*.e core/examples/shouldfail/*.e )
```

batch loop: add `lang_done=0` to the initialiser beside `present_done=0`, then

```bash
      core/examples/Lang/Helpers.e) ;;
      core/examples/Lang/*)
        if [[ $lang_done == 0 ]]; then bfiles+=( core/examples/Lang/Helpers.e ); lang_done=1; fi
        bfiles+=( "$f" ) ;;
```

per-file loop:

```bash
    core/examples/Lang/Helpers.e) ;;
    core/examples/Lang/*)         args=( core/examples/Lang/Helpers.e "$f" ) ;;
```

**(c) `core/examples/README.md`** — one row in the directory table (after the `Algebra/` row)
and one example command (after the `Algebra` line in the code block):

```markdown
| `Lang/` | ten modules about the **language** rather than about relations — monads and `do`, parser combinators, applicative validation, `State`, `Reader`, `Data.Free`/`Cofree`/`Nu`, strings and markdown, `Tree`/`Map`, and every `foreign` declaration form | `Lang/Helpers.e` |
```

```bash
bin/ermine core/examples/Lang/Helpers.e core/examples/Lang/TextTables.e
```

and, in the `shouldfail/` paragraph, `Lang/shouldfail/` alongside `Present/shouldfail/`.

**(c2) Two corrections to what has already been wired** (E5's reviewer, §8 of the review; both
are in files E5 does not edit):

* **`corpus-run.sh`'s per-file hoist is still MISSING.** The batch arm and the `files=` list
  landed at `6a63dbb`; the two per-file lines did not, so a non-`--batch` `corpus-run.sh` loads
  every `Lang/` module without `Lang/Helpers.e` and every one of them fails. Exactly the same gap
  E4's review found for `Present/`. The lines are in (b) above:

  ```bash
      core/examples/Lang/Helpers.e) ;;
      core/examples/Lang/*)         args=( core/examples/Lang/Helpers.e "$f" ) ;;
  ```

* **`core/examples/README.md`'s row says "eleven modules"**; the group has **ten** report modules
  plus `Helpers.e` and `Signatures.e`, i.e. **twelve `.e` files**. `core/examples/Lang/README.md`
  now says exactly that, so the shared row is the one to change.

**(d) `TestSurfaceParsers.scala` — NOT needed.** The file-count constant that tripped for E2
and E3 is now derived, and `Surface parser 2.3a.headers agree with the fused pipeline across
the stdlib` passes over the enlarged tree with E5's 19 files added (G1(d)).

---

## 6. What could NOT be written, and why

Eight things, in descending order of how much they matter to a reader. **Three of them were
wrong** and are corrected below with the reviewer's own probes: a total integer parser CAN be
written (§6.1), a generic `foldFree` CAN be written and now is (§6.2), and an `IO.CSV` read DOES
run (§6.5).

### 6.1 A total number parser — WITHDRAWN, and the helper fixed

The earlier draft said `Helpers.parseIntTotal` "avoids the problem rather than solving it: a
string that is all digits but overflows `Int` would still produce a bomb … **and there is no way
to write one that does not**." Both halves were wrong, and E5's reviewer showed it (L-6, L-7).

The bomb was real and was in the shipped helper:

```
>> parseIntTotal "99999999999999"           (Just <error: For input string: "99999999999999">)
>> isJust (parseIntTotal "99999999999999")  True
```

— the group shipping, in the helper written to avoid the defect, the very defect §4.2 documents.
And the fix needs nothing the language has not got: a digit string of equal length orders
lexicographically exactly as the number does, so the bound is a `String` comparison.
`Helpers.parseIntTotal` now carries it:

```
parseIntTotal s =
  let neg  = take_S 1 s == "-"
      body = if neg (drop_S 1 s) s
      cap  = if neg "2147483648" "2147483647"
      inRange = length_S body < length_S cap
                ||_B (length_S body == length_S cap && body <= cap)
  in if (looksLikeInt s && inRange) (parseInt 10 s) Nothing

>> (parseIntTotal "102", parseIntTotal "99999999999999",
    parseIntTotal "2147483647", parseIntTotal "2147483648")
res : (Just 102, Nothing, Just 2147483647, Nothing)
```

`parseDoubleTotal` needs no range clause and the asymmetry is worth a reader's attention:
`Double` saturates rather than throwing, so `parseDoubleTotal` of a thirty-three-digit literal is
`Just 1.0E33` while the same string must be refused by `parseIntTotal`. Both doc comments now say
so. **What remains true of §6.1 is only that `Parse` itself cannot be made total from Ermine** —
the shape-and-range guard sidesteps it rather than fixing it, and a `Parse` call that throws for
any other reason would still return `Just <bomb>`.

### 6.2 A `Free` interpreter using `Data.Free`'s own eliminator — the stdlib's absence, corrected in `Helpers.e`

The stdlib half stands: `Data.Free.lowerFree : Monad m -> Free m a -> m a` requires the command
functor to BE a monad, so it cannot run a DSL, and there is no `foldFree`, `iterM`, `runFree`,
`FreeT` or `hoistFree` in `Data/Free.e`'s twenty-four lines.

**But the group's own method — when the stdlib has not got the library, write it in `Helpers.e` —
was not applied here, and it should have been** (E5's reviewer, L-17). `Helpers.foldFree` now
ships, eight lines, generic in the command functor and the monad, needing no `Functor f` at all:

```
data Nat f m = Nat (forall x. f x -> m x)

foldFree : forall f m a. Monad_M m -> Nat f m -> Free_Fr f a -> m a
foldFree mm n (Pure_Fr a)  = unit_M mm a
foldFree mm n (Free_Fr fs) = case n of
  Nat k -> bind_M mm (k fs) (rest -> foldFree mm n rest)
```

and `Lang/FreeReportDsl.e` now carries `countedByFold`, one of its interpreters rewritten as an
algebra over it (`cmdToState` in `State Int`), beside the three hand-written ones — which are
kept, because recursion over `Pure`/`Free` is what a reader should see first.

The `Nat` wrapper is not a stylistic choice: §4.14 is the reason it is the only working form, and
it is also why `Data.Free.Church`'s `runF` is "the exception" — the Church encoding's rank-2 is
already inside a `data`.

### 6.3 A `Validation` applicative, using `Validation.e`

The brief and the module name both suggest `Validation.e` is an applicative-validation library.
It is not: it is a `FormValidator` library whose accumulation lives inside one helper fixed at a
single shape,

```
combineErrors : (a -> b -> c) -> String -> Either String a -> Either (List Err) b
             -> Either (List Err) c
```

whose two sides have DIFFERENT error types, so it is `liftA2` at one fixed shape and cannot be
reused as an `Ap`. (The earlier draft called it "non-exported"; E5's reviewer corrected that —
`Validation.e`'s only `private` binding is `arr`, and `combineErrors` is exported. L-18.) There
is no `Validation` type, no
`Ap (Validation e)`, and `Either`'s shipped `eitherAp` short-circuits. `Helpers.accumAp` is the
missing piece and is four lines; it differs from `eitherAp` in exactly one clause. It is
deliberately **not** a monad, and cannot be: `bind` cannot accumulate because the second
computation does not exist until the first has succeeded.

### 6.4 Parser combinators, using `Parse`

`Parse` is six `java.lang.*` number parsers and `parseBool`. The 20 combinators in `Helpers.e`
are what a reader who finds `Parse` in the import census expects to be there. This is the
largest single gap between what the stdlib's module names promise and what they contain.

### 6.5 An `IO.CSV` read that runs — WITHDRAWN; the read runs and a stdlib bug spoils it

The earlier draft said the read could not be run because "there is no data file in this
repository to point it at". That was not the obstacle, and E5's reviewer refuted it by pointing
`readCSVFile` at a file (L-10). `core/examples/Lang/customers.csv` now sits beside the
module and `Lang/CsvIntake.e`'s `intakeFromDisk` and `diskLines` read it for real; paths are
relative to the JVM's working directory, which is the repository root under `bin/ermine`.

What breaks it is `File.readFile`'s own `traceShow` — §4.13, a stdlib bug nobody had recorded.
The read succeeds, the file is dumped to stdout, and the value comes back a bomb.

Two of the three surrounding statements survive and are worth keeping: the whole intake really is
`map (readRowsAs …) . readCSVFile`, so the row reader composes with `IO` through `Syntax.IO`'s
functor and nothing else changes; and `parseCSV` is `split ','` per line with no quoting, no
escaping and no header handling.

### 6.6 The inferred scheme with a kind variable

§4.5. `forall {a} … (a1: a)` was emitted by the interface printer and is rejected by the surface
parser. Two of `Signatures.e`'s `xFull` forms had to be written at kind `*` instead, with a
note saying so.

### 6.7 `Tree.fromRel` outside a `Report`

`Tree.fromRel : RunScan List z -> …` needs a `RunScan List z`, and the only one the stdlib
provides is `Layout.Scan.runner`, whose `z` is `Report f z'`. So the relation-to-tree direction
can only be taken inside a report (`Lang/TreeAndMap.e`'s `treeSection`), while tree-to-relation
(`toRel`, `toRootedRel`) works anywhere. A `RunScan List (List a)` would make the former usable
from a value, and nothing in the stdlib builds one.

### 6.8 Two small things the stdlib simply lacks

`String` has `uppercase` and no `lowercase` (`Lang/TextTables.e` declares one in three lines of
`foreign`); and `Layout.Report`'s `padLeft`/`padRight` occupy the two obvious names for string
padding, so `Helpers` calls its own `lpad`/`rpad`.

---

## 7. Coverage against the brief: what is exercised, and what is not (added post-review)

E5's reviewer checked the brief's list against the group and found five names unaccounted for
(§7 of `E5-REVIEW.md`). Four are now used and one has a reason.

| brief item | status |
|---|---|
| `Control.Category` | **now used** — `TypesAndRows.e` §10: `fCategory` at `(->)`, `idC`, and `catEndoMonoid` folding three same-type transformations into one through `foldMapL` |
| `Control.Monad.Id` | **now used** — `DoNotation.e`: `addTwo` at a SIXTH monad, and `Helpers.inMonad` applied to an `Id` block |
| `Control.Monad.Error` | **now used** — `DoNotation.e` §1b: `ErrorT String Id` and `ErrorT String Maybe` side by side, so the two failure modes (`Nothing` = the base gave up, `Just (Left e)` = the computation said why) are distinguishable rather than redundant |
| `List.NonEmpty` | **now used and named** — `TreeAndMap.e`: a flattened tree is never empty, so `NonEmpty` is its honest type; `(:|)`, `head`, `tail`, `map` |
| `Syntax.Procedure` | **not used, and cannot be here.** Its own header says "You should not import it; the syntax is always available": it is the desugaring target of a `database "db" procedure "name" f n : …` declaration, which names a **stored procedure in a live database**. There is no database on this build's classpath (the same reason `Present/` cannot run a writer), and a `procedure` declaration against a non-existent one is not an example, it is a stub |
| `Eq` | **not used, and there is nothing to use.** `Eq.e` is fifteen lines of which every one is inside a block comment: it declares a class the language does not have. `==` is the builtin `eq#`, used throughout the group. The module is a design note, not an API |

Exercised INDIRECTLY, which a reader grepping for the import will not find (the reviewer's
point, worth stating): `Control.Ap` through `Control.Monad`'s re-export — every `Ap_M` in the
group; `Control.Monad.Cont` through `Prelude`, in `TreeAndMap.treeSection`'s `runCont`; `Parse`
through `Prelude`, which `export`s it, so `Helpers.parseIntTotal` calls `parseInt` with no
import of its own; `Error` and `Eq` likewise through `Prelude`.

**The follow-up this group points at**, and the reviewer's own recommendation: one more module
taking `Syntax.Procedure`'s shape (against a stub scanner), a full transformer stack
(`ReaderT`/`StateT`/`ErrorT` over `Id`), and `Control.Category` at something other than `(->)`.
`Control.Category`'s interesting instances are `Validator` and `Op`, and `Validation.e`'s own
comment ("I'm not wild about exposing any of Validator's variance … there are no combinators for
it, and `arr` is private") is the reason a `Validator` cannot be given one from outside the
module — itself a finding a follow-up should record.

---

## 8. Post-review corrections — 2026-09-07

`tracker/loopmodel/E5-REVIEW.md` (1,107 lines, findings L-1…L-22) returned
**FIX-THEN-ADVANCE**: every gate reproduced, nineteen of the census's twenty measures exactly,
all twelve `.ei` counts and the whole §2 interface block verbatim, and the one-session recipe
machine-checked. What follows is every change made in response, old → new. Sections 1–7 above
are the corrected text; this section is the audit trail.

### The eight must-fixes

| # | was | is |
|---|---|---|
| **L-1** | "per-key mints, max **29** … against a round-7/8 corpus bound of 11 and E4's 12, which was itself the first breach" (§summary, §G3, §4.1, `README.md`, `ProjectionCliff.slow`, the plan row) | **29 is the minted-variable VOCABULARY** (`--cycle`'s `maxmint` = `max rep.maxMint mo.length`, `Cycle.lean:407`) and is reported as that — a corpus record for that measure. The **per-key** census is `--mints`: `solves=24399 max=1 remint=0 cmax=2 cremint=1 keys=3`, so the per-key maximum is **1**, as it is for every E-series group. The "breach" claim is withdrawn everywhere; E4's "12" was the same mislabel, corrected by `E4-REVIEW.md` M-1 to `maxmint` 11 and per-key 1 |
| **L-2** | "`String.Markdown.link` cannot produce a link"; "there is no argument you can pass that produces `[title](loc)`"; `TextTables.e`'s "can never produce a link"; `Helpers.mdLink`'s "cannot produce a link" | **`link ((++) "SUP-77/A") loc` returns `"[SUP-77/A](…)"`.** §4.3 retitled and rewritten; `TextTables.workingLink` now evaluates it; the `Helpers.mdLink` doc comment corrected. The defect is that the title must be a PREFIXING FUNCTION, so no ordinary call site type-checks and the working spelling is undocumented |
| **L-3** | "A character literal whose character is an operator symbol does not lex" (§4.6(3), `Helpers.e`, `README.md` item 6) | **The rule is POSITIONAL.** `'-'`, `'.'`, `'|'` and `'/'` all lex in head and argument position — this group's own `TextTables.e` writes `split_S '/' p`. After a **binary operator** every operator character fails, `/` included; parenthesising does not help. Restated in all three places with the reviewer's seven-module table |
| **L-4** | §4.8's table: `filter p r` → "undefined" | **`filter` resolves**: `List.filter` is public (`List.e:224`) and `Prelude` exports `List`. Only `map` is `private`. The row now reads `List.filter`, and the true statement — a relational filter needs `filter_Pred` — is spelled out |
| **L-5** | `StatementParser.amountP` called the raw `Parse.parseDouble`, so `parseLine` **succeeded** with a bomb in the record — the exact defect §4.2 documents, in the group's front door | `amountP` uses `Helpers.parseDoubleTotal`. The bombing version is kept as `bombedAmountP`/`bombedAmount`, next to `goodAmount`, as the teaching contrast, and never builds a row |
| **L-6** | `Helpers.parseIntTotal`, doc comment "`Parse.parseInt 10`, total", answered `Just <error: For input string: "99999999999999">` | It now checks **shape and RANGE**: a digit string of equal length orders lexicographically as the number does, so the `Int` bound is a `String` comparison. `(parseIntTotal "102", …"99999999999999", …"2147483647", …"2147483648")` = `(Just 102, Nothing, Just 2147483647, Nothing)`. `parseDoubleTotal` needs no range clause — `Double` saturates rather than throwing — and its comment now says why |
| **L-7** | §6.1: "there is no way to write one that does not [bomb]" | **Withdrawn.** §6.1 rewritten; the eight-line range check is in `Helpers.parseIntTotal`. What survives is only that `Parse` itself cannot be made total from Ermine — the guard sidesteps it |
| **L-8** | "`TextTables.catalogueMarkdown` … is the most expensive solve in the whole group" (§4.1, `README.md`, `ProjectionCliff.slow`, which also gave it 1,241 draws / 27 mints) | There are **three** five-projection cell lambdas and they are within 1 % of one another, so they are quoted as a SET everywhere. On the pre-correction bytes the reviewer and this report both measured `catalogueAscii` 1,245 / `postingMarkdown` 1,241 / `catalogueMarkdown` 1,230; on the corrected bytes it is `catalogueMarkdown` 1,241 / `postingMarkdown` 1,233 / `catalogueAscii` 1,230. The instability of the ORDER is now stated rather than a ranking asserted |

### The three findings the review added (now §§4.12–4.14)

* **§4.12, L-9** — `IO.catch` cannot catch a foreign exception either: `catch (readFile "/nope") …`
  evaluates to `<error: /nope (No such file or directory)>`. `perhapsForeign` routes the `IO`
  branch through the same `FF` case, so **every `IO` error path in the stdlib is unreachable for
  an exception raised by the foreign call itself**. With the distinction the reviewer drew: a
  PLAIN foreign only defers (`strCharAt "" 0` reaches the REPL as a runtime error), so the
  conversion turns a catchable exception into an uncatchable deferred one. `ForeignJdk.e` §4b
  ships `caughtMissing` and `deferredNotSwallowed`.
* **§4.13, L-10** — `File.readFile` traces its own result. `withSource# f s = … traceShow res`
  writes through `System.console()`; under a pipe the file is dumped to stdout and the value
  comes back a bomb. `CsvIntake.e` now reads a real file
  (`core/examples/Lang/customers.csv`) through `intakeFromDisk`/`diskLines` and documents
  the measured output.
* **§4.14, L-11** — a rank-2 function ARGUMENT cannot be applied
  (`oneWay nat a = nat a` → `failed to unify type (forall x. f x -> m x) with type (a -> b)`),
  while the same `forall` in a data field works. That explains the shape of every `Control.*`
  dictionary and why `Data.Free` has no `foldFree`. `TypesAndRows.e` §9 is the worked
  demonstration, with `Applier`/`applyNat`/`rank2Works`.

### The should-fixes applied

| # | change |
|---|---|
| **L-12** | `Helpers.e`: the six bindings with no call site anywhere now have one — `allOrNothing`, `cellOr`, `minMonoid`, `orElseA`, `withDefaultA` and `inMonad` are all exercised in `DoNotation.e`. All **22** undocumented signatures now carry a doc comment (68 of 68). The header's "FIVE THINGS" now says SEVEN, and its row-constraint list names the correct **five** (`consRow`, `pRecord`, `withRunning`, `askField`, `localField`) instead of four with `traverseRows` wrongly among them |
| **L-13** | `RunningState.postedRatios` → `grossFeeRatios`: it filters on `grossAmt`, not on `postedMark` |
| **L-14** | §4.4 now cites **ticket A2** rather than presenting the EOF loop as an E5 finding, and credits the unbounded half to E4's reviewer |
| **L-15** | §G0 and `Signatures.e` §1 already recorded the S3 dependence; §4.5 now says explicitly that `shouldfail/lang07` is a pure language fact and survives whatever S3 does, while `Signatures.e`'s quoted schemes do not |
| **L-16** | §4.6(1): the `where` clause narrowed — a `]_L` that is the whole right-hand side cannot be followed by `where`; one in a function's last argument position can |
| **L-17** | `Helpers.foldFree` + `Helpers.Nat` now ship (8 lines, no `Functor f` needed), and `FreeReportDsl.countedByFold` is one of the file's interpreters rewritten as an algebra over it. §6.2 rewritten to distinguish "the stdlib lacks it" from "it cannot be written" |
| **L-18** | §6.3: "non-exported" → "fixed at one shape". `Validation.e`'s only `private` binding is `arr` |
| **L-19** | the plan row's timings and `Signatures.e` counts reconciled with this report (five pairs, five specialisations; batch 3.57 s) |
| **L-20** | the remedy is now measured in the modules, not only in `.slow`: `TextTables.catalogueMarkdownPinned` and `RunningState.postingMarkdownPinned` are the same tables with the lambda's argument annotated — 1 draw against 1,230 and 1,241 — and both headers say so. §4.1 carries the reviewer's datum that reordering `showRows`'s arguments changes nothing (1,230 → 1,233) |
| **L-21** | the two off-by-one cross-references in §6 fixed (§6.1 → §4.2, §6.6 → §4.5) |
| **L-22** | `ForeignJdk.e`: `maxDouble` (in `representable`), `readLongIO` (in `readLongUnsafe`), `shout` (in `shouted`) and `decimalShown` (in `decimalStrings`) are now used, and the header's `abs`-overload claim is **shown** — `absI : Int -> Int` and `absOf : Double -> Double` are the same two words of Java at two declared types, evaluated as `bothAbsOverloads` |

Coverage against the brief (L-… §7 of the review) is §7 above: `Control.Category`,
`Control.Monad.Id`, `Control.Monad.Error` and `List.NonEmpty` are now used; `Syntax.Procedure`
and `Eq` have precise reasons.

### Two things the review asked for that are NOT done, and why

* **A seventh negative on a different mechanism.** The reviewer notes `lang02` and `lang03` teach
  the same mechanism twice and suggests, say, a `RowReader` whose cell type disagrees with its
  field. Not added: that refutation is `failed to unify type` — `lang01`'s and `lang05`'s class —
  so it would be the fourth instance of one class rather than a new one. The gap the review
  identifies is real; the module that closes it belongs with the follow-up in §7.
* **`corpus-run.sh`'s missing per-file hoist** (review §8). Confirmed still missing at the time of
  writing; it is shared tooling and E5 does not edit it. The two lines are in §5(b) and the
  orchestrator has been told.

### Gates after the corrections

Re-run in full on the corrected bytes — see §3, which now carries these numbers. Summary:
the batch and all eleven per-file loads green, all seven negatives rejected with unchanged
diagnostics, the L2 differential 0 skipped / 0 hashdiff / 0 eqdiff on both traces, the census
recomputed **with `--mints`**, and every `.ei` deleted.
