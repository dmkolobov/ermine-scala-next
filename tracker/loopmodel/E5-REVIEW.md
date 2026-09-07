# E5 REVIEW — `core/examples/Lang/` judged as programs and as corpus

Reviewer pass over stage E5 (report `tracker/loopmodel/E5-EXAMPLES.md`, 1,152 lines; group
`core/examples/Lang/`: 12 `.e` modules, 7 negatives under `shouldfail/`, one `README.md` and one
`.slow`, all uncommitted). Brief `tracker/loopmodel/briefs/brief-E-review.md` with `$STAGE = E5`,
`$GROUP = Lang`, on top of `brief-E-common.md` and `brief-E5.md`. Repository at `740da34` when I
started; the group's wiring was committed under me at `6a63dbb` and the ticket's B5 extended at
`b6b7846`, neither of which touches anything I measured. The three row-solver defaults are as
adopted at `fe024a7`. Every `bin/ermine` below ran with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time, 2026-09-07. Scratch:
`/home/dmitry/.claude/jobs/880c725d/tmp/review-E5/`. Every `.ei` I caused was deleted
(`find core/examples -name '*.ei' | wc -l` is **0**). No commits; nothing edited outside this file
and that scratch directory. Findings are prefixed `L-`.

**The compiler I measured on.** S3's uncommitted `Subst.scala` change (a `hashCode` for
`NormalPart`, the `a <- (a)` tautology dropped) is in the tree *and in the compiled classes*:
`core/target/scala-3.3.8/classes/…/Subst$.class` fingerprints `8f54eee6211f4e0d309a444f54c1bd45`
before and after every run below — the same fingerprint E5 records in its §G0. E5's post-rebuild
numbers and mine were therefore taken on one compiler, and §4.5(b)'s "after" state is the one I saw.

---

## Verdict: **FIX-THEN-ADVANCE**

This is the best-instrumented group of the E series and the one with the most to teach. Every gate I
re-ran is green, and the census reproduces **figure for figure — nineteen of its twenty measures exactly**,
which no earlier group managed. The L2 differential is byte-for-byte what the report claims (88,037
and 58,289 segments, 0 skipped / 0 hashdiff / 0 eqdiff), all seven negatives reject with the
diagnostics recorded verbatim in their headers, all twelve `.ei` signature counts match, and
the report's verbatim `Helpers.ei` block is verbatim. Its two structural counts (16 helpers quantify
over a row, 5 carry an explicit row constraint) are exactly right. `Signatures.e` is honest work and
`README.md` is the best group README in `core/examples`.

What must be fixed is a layer above the measurements.

* **The one wrong census cell is the one the brief singled out**, and it is E4's mistake repeated
  verbatim: "per-key mints 29" is `--cycle`'s `maxmint`, the *minted-vocabulary size*. Over `Lang/`
  the true per-key maximum from `--mints` is **1**. E5 read `E4-REVIEW.md` — the report, the group
  README and `ProjectionCliff.slow` each cite it for the projection cliff — and reproduced the very
  claim that review's M-1 refuted, including
  "against E4's 12", a number E4's reviewer had already corrected to 11-and-mislabelled. (L-1)
* **Three of the eleven findings do not survive a minimal module.** `String.Markdown.link` *can*
  produce a link (L-2). A character literal is not rejected because its character is an operator
  symbol — the group's own `TextTables.e` writes `split_S '/' p` — it is rejected after a binary
  operator, where `'/'` and `'.'` fail too (L-3). And `filter` is not undefined in `Prelude`'s
  unqualified scope (L-4).
* **Two modules contradict the group's own headline finding.** `StatementParser.amountP` calls the
  raw, bombing `parseDouble`, so the parser this group ships returns `Just {… movementAmt =
  <error: For input string: "abc"> …}` — the exact defect §4.2 documents, inside the module that
  documents it (L-5). And `Helpers.parseIntTotal`, documented "`Parse.parseInt 10`, total", answers
  `Just <error: For input string: "99999999999999">` (L-6) — and §6.1's "there is no way to write
  one that does not" is refuted by an eight-line `safeInt` that I ran (L-7).
* **"The most expensive solve in the group" is attributed to the wrong binding in three files**,
  against E5's own §G3 table (L-8).

Set against that, the review turns up **three findings E5 missed that are stronger than several it
made**: `IO.catch` cannot catch a foreign exception either (L-9); an `IO.CSV` read *does* run and
what breaks it is `File.readFile`'s own `traceShow` (L-10); and a rank-2 function argument cannot be
*applied* at all, which is why every `Control.*` dictionary keeps its `forall` in a data field and
why the stdlib has no `foldFree` — though a `Nat`-wrapped `foldFree` **does** load and could have
gone into `Helpers.e` (L-11, L-17). Those three belong in the ticket.

Must-fix: **L-1 … L-8**. Should-fix: **L-9 … L-22**. The three best and three weakest modules are
in §5; the helper library is judged in §6; coverage against the brief in §7; wiring in §8.

---

## 1. Gates re-run

| gate | report | mine | verdict |
|---|---|---|---|
| G1(b) one batch, 12 modules | LOADED, 3.85 s own time | **LOADED**, own time **3.57 s**, wall 19.2 s | ✔ (L-19) |
| G1(c) seven negatives | REJECTED, diagnostics verbatim | **all seven REJECTED**, every message character-identical at the recorded line:col, 0.02–0.04 s each | ✔ exact |
| G1(d) corpus walkers | 20 properties green, no file-count line needed | `core/testOnly *TestSurfaceParsers *TestStatementExtents *TestTolerantRead`: **Total 20, Failed 0, Errors 0**, 97 s | ✔ exact |
| G2 differential, positives | 88,037 seg, 0/0/0, nonpart 1400 | **88,037 / 88,037 / 0 / 0 / 0, nonpart 1400, rejected 0, fuel 0** | ✔ **exact** |
| G2 differential, negatives | 58,289 seg, 0/0/0, nonpart 1033, rejected 0 | **58,289 / 58,289 / 0 / 0 / 0, nonpart 1033, rejected 0** | ✔ **exact** |
| G3 census | see §2 | **19 of 20 measures exact**; the 20th is L-1 | ✖ one cell |
| G3 derivation rules | Subst 551, Res 489, CSE 273, Canc 40, SplitConc 10, ResRow 2 | **identical, all six**; splices 1,022 / 409 changed / 301 dropped / 282 non-conservative — **identical** | ✔ exact |
| G4(b) `.ei` counts, all twelve | 74/57/38/34/31/26/26/25/23/22/20/16 | **74/57/38/34/31/26/26/25/23/22/20/16** | ✔ **exact** |
| G4(b) `Helpers.ei` §2 block | verbatim | every signature I spot-checked is **verbatim**, `Has` expansion and all | ✔ exact |
| G4(b) 70 public + 4 private | 74 lines | **74 lines: 70 public, and `mconcat`/`pbind`/`por`/`punit`** | ✔ exact |
| §2 "16 quantify over a row, 5 carry a constraint" | 16 / 5 | **16 / 5**, machine-counted over the published `.ei` | ✔ exact |

Per-file G1(a) (mine, on a machine running one other agent's sbt): see §1.1. Nothing near 30 s, no
module needs `.slow`, and **no budget diagnostic fired on any `.e` in the group** — I confirmed the
absence by grepping every per-file and batch log for `resource limit`.

`sbt core/test` I did not re-run in full (the walkers above are the three the brief names, and
another agent held the build). The single failure the report records, `Constraints.disjunction
sound`, is documented in `Constraints.scala`, reads no example file and is unrelated to this group;
E2, E3 and E4 all recorded it.

**Corpus size for the record: 356 `.e` files** with E5's 19 in the tree. The `TestSurfaceParsers`
constant really is derived and needs no wiring line, as the report says. Cosmetic and not E5's: the
three `TestStatementExtents` property *names* still read "(271 files)" — E4's review flagged the same.

### 1.1 Per-file loads (G1(a))

```
CsvIntake  0.23   DoNotation 0.36   ForeignJdk 0.31   FreeReportDsl 0.34
ReaderParams 0.32 RunningState 0.52 Signatures 0.13   StatementParser 0.16
TextTables 0.63   TreeAndMap 0.48   TypesAndRows 0.41     (Helpers 0.40–0.44 each time)
```

All eleven LOADED, zero `error:` lines, wall 14.6–15.8 s. The report's own-check range is
0.14–1.06 s against my 0.13–0.63 s; the ordering is the same and the difference is machine load (E5
measured under three JVMs, I under two). Nothing near 30 s. (L-19)

### 1.2 The seven negatives — the strongest part of the group

All seven reject, every message character-identical to the header, in 0.02–0.04 s after the module's
own parse, in five refutation classes:

```
lang01 27:1  error: failed to unify type (|jobQty, jobRef|) with type (|jobQty, jobRef, jobSite|)
lang02 24:13 Fields appear twice in row: Lang.Shouldfail.Lang02.assetRef
lang03 27:14 Fields appear twice in row: Lang.Shouldfail.Lang03.runningSum
lang04 26:27 error: failed to unify type Maybe with type List
lang05 28:1  error: failed to unify type (|orderQty, orderRef, orderTeam|) with type (|orderQty, orderRef|)
lang06 22:1  error: skolem variables escape: / Type would have been: Nu f -> !s
lang07 28:34 error: failed to unify kind * with kind !k
```

The report's observation that **none of the seven is a row-solver refutation** is correct and I
confirmed it independently: the negatives' L2 run reports `rejected=0` over 58,289 segments. Four
groups in, the corpus's refutation profile is `Wide`/`Algebra` almost all solver, `Present` one in
six, `Lang` none — a real result about what kind of mistake each half of the language makes, and the
best single sentence in the report.

`lang06` and `lang07` are refutation classes no other group has, as claimed.

### 1.3 The one-session recipe

`README.md` promises that the whole group loads into one REPL session and every binding can be
evaluated by name. **It does.** Machine-checked over every `^name :`, `^name =`, `field name` and
`data Name` in the twelve modules: **zero term names and zero field names occur in more than one
module.** E3's group failed this (five clashes) and E4's had three; E5 has none, and I evaluated
forty-odd bindings drawn from all eleven report modules in a single session with no `undefined term`.
That is a real improvement and it should be said.

---

## 2. The census (G3) — nineteen of twenty measures exact, and one mislabel

I traced the group myself (`-Dermine.useInterface=false -Dermine.loadInSeries=true
-Dermine.rowTrace=…`, 39.6 MB / 25.9 MB), replayed both traces (`looptrace --replay`, 15 s, clean),
and censused with `--depth`, `--cycle` and `--mints`, filtering to the 24,399 segments located inside
`core/examples/Lang/`.

| measure | report | mine | |
|---|---|---|---|
| solves attributable to the group | 24,399 | **24,399** | ✔ |
| verdicts | 24,399 SOLVED / 0 REJECTED | **identical** | ✔ |
| draws per solve, max / total | 1,245 / 4,482 | **1,245 / 4,482** | ✔ |
| solves that draw at all | 200 (0.82 %) | **200 (0.820 %)** | ✔ |
| dequeues, max / total | 226 / 4,671 | **226 / 4,671** | ✔ |
| chain depth, max | 2 | **2** | ✔ |
| **per-key mints, max** | **29** | **1** (`--mints`); `--cycle`'s `maxmint` is **29** | ✖ **L-1** |
| initial mints (`mint0`), max | 5 | **5** | ✔ |
| re-minted keys, max | 1 | **1** (`maxremint`; `maxcremint` is 2) | ✔ |
| distinct keys (`maxdkey`), max | 30 | **30** | ✔ |
| decision nodes (`states`), max | 227 | **227** | ✔ |
| splits, max / total | 3 / 10 | **3 / 10** | ✔ |
| resolution steps, max / total | 1,245 / 4,289 | **1,245 / 4,289** | ✔ |
| `concrete` share of dequeues | 19.9 % (929/4,671) | **19.89 % (929/4,671)** | ✔ |
| `concrete` share of solves | 3.23 % | **3.234 % (789)** | ✔ |
| vocabulary-fixed | 99.89 % | **99.889 %** | ✔ |
| generative rules | 0.11 % (27) | **0.111 % (27)** | ✔ |
| input row variables / partitions / labels, max | 16 / 13 / 14 | **16 / 13 / 14** | ✔ |
| derivation rules (six) | 551/489/273/40/10/2 | **identical, all six** | ✔ |
| splices | 1,022 / 409 / 301 / 282 | **identical, all four** | ✔ |

That is the most accurate census table the E series has produced. The five costliest sites and their
whole records reproduce exactly, including the ones I could have expected to drift:

```
drawn=1245 nres=1245 nsplit=0 steps=222 maxdepth=2 maxdkey=30 nvars=6 nparts=5 nlbl=5  TextTables.e(138:23)
drawn=1241 nres=1241 nsplit=0 steps=226 maxdepth=2 maxdkey=30 nvars=6 nparts=5 nlbl=5  RunningState.e(201:13)
drawn=1230 nres=1230 nsplit=0 steps=211 maxdepth=2 maxdkey=30 nvars=6 nparts=5 nlbl=5  TextTables.e(119:13)
drawn=218  nres=218  nsplit=0 steps=71  maxdepth=2 maxdkey=14 nvars=5 nparts=4 nlbl=4  TextTables.e(152:9)
drawn=207  nres=207  nsplit=0 steps=65  maxdepth=2 maxdkey=14 nvars=5 nparts=4 nlbl=4  FreeReportDsl.e(138:17)
```

and so do the three widest-and-cheapest (`nvars=16 nparts=13`, 4 and 12 draws). The report's central
claim — **cost tracks how many times one record is projected in one expression, not row width** — is
therefore exactly right, and its "`Time/` is wide and cheap, `Lang/` is narrow and dear" is the right
summary of the two ends of the corpus.

### 2.1 L-1 — "per-key mints 29" is `--cycle`'s vocabulary size (E4's M-1, E3's P-18, a third time)

**CONFIRMED, must fix.** `--cycle`'s `maxmint` is `max rep.maxMint mo.length` where `mo = mintOrder s`
(`tracker/lean/Rowpartition/Loop/Cycle.lean:407`): the size of the *minted-variable vocabulary* at a
step, not a per-key count. The per-key census is `looptrace --replay … --mints`, whose `max` column is
"the largest number of mints at ONE key". Over the whole of `Lang/`:

```
$ looptrace --replay Lang.tsv --mints   # filtered to core/examples/Lang/
solves=24399  max=1  remint=0  cmax=2  cremint=1  keys=3
```

**The true per-key mint maximum in `Lang/` is 1.** Two consequences for the report:

* "it reaches **29** per-key mints against a round-7/8 corpus bound of 11" (§ summary, §G3, §4.1's
  table, the README's table, `ProjectionCliff.slow`'s table, and the plan row) must go. Report
  `maxmint` under its real name — *minted vocabulary, max 29* — which is a genuine record and an
  interesting one, and the per-key max as 1.
* "and E4's 12, which was itself the first breach" is doubly wrong: E4's `maxmint` was **11** on final
  bytes (equal to, not above, the round-7/8 figure), and its per-key max was **1**. `E4-REVIEW.md`
  M-1 says exactly this, and E5 cites that review three times for the projection cliff. The claim
  that this group "breached" a per-key bound has no support at all: **no group in the E series has
  ever exceeded a per-key mint count of 1.**

The report's narrative does not depend on the cell. `nsplit=0 / nres=1245 / conc=0 / nvars=6` is
true, and it carries the whole argument.

### 2.2 The costliest sites — the same cliff E4 found, one rung further along

**Same shape, not a different one.** E4's costliest solve (`ValidationReport.e(214:14)`) is
`steps=73 drawn=218 nsplit=0 nres=218 maxdkey=14 nvars=6 nparts=5 nlbl=4`. E5's top three are
`nsplit=0 nres=drawn maxdkey=30 nvars=6 nparts=5 **nlbl=5**`. Identical shape at N = 5 instead of
N = 4 — and E5's own fourth and fifth (`nlbl=4`, `drawn=218` and `207`) sit on E4's rung to the
digit. The report is right to call it a second, independent sighting and right about the mechanism.

Two things the report does not say, and should:

* **The remedy is the annotation, and *only* the annotation.** I isolated the group's own helper
  shape. `showA hdr cells rows` with an unannotated five-projection cells lambda draws **1,230**;
  the same helper with `rows` and `cells` **swapped** (`showB hdr rows cells`, so the row-fixing
  argument is checked first) draws **1,233** — no help at all; the same call with the lambda's
  argument annotated at the concrete row draws **1** (`steps=2`). So the cost is not an artefact of
  argument order and cannot be engineered away in the helper's signature; writing the row down is
  the only fix, exactly as `incomplete/README.md` says of the star-join cliff. (Scratch:
  `probes/ArgOrder{,2,3}.e`.)
* **The three costliest solves in the E-series corpus are therefore avoidable by one token**, and
  they are in `TextTables`, `RunningState` and `FreeReportDsl` — modules whose point is text
  rendering, not row polymorphism. Showing both spellings side by side (the generic `showRows` call
  and the annotated one) would teach the lesson *and* leave the census number where it is on
  purpose. Worth a line in each header. (L-20)

`ProjectionCliff.slow` itself is a good artefact and the right extension (`.slow`, not a second
negative) — E4 already ships `proj01_seven_reads.e`, and what this file adds is the curve. Its
ladder (0 / 3 / 31 / 207 / 1,241 / 6,956 / budget) is consistent with E4's reviewer's independently
measured 3 / 33 / 207 / 1,243 / 6,795 / budget, and my own `ArgOrder.e` lands at 1,230 for N = 5,
between the two — the three probes differ only in what else is in the expression, which is the
honest reading of the small differences and is what the report says.

---

## 3. The eleven findings, each confirmed or refuted

Every one below was tested with a module or a REPL line of my own, in
`/home/dmitry/.claude/jobs/880c725d/tmp/review-E5/probes/`.

### §4.1 The projection cliff — **CONFIRMED** (ticket B5)

See §2.2. Shape, ladder, diagnostic and remedy all reproduce; the site attribution inside the group
is wrong (L-8) and the remedy is under-stated (L-20), but the finding itself is solid and is already
in the ticket as **B5**, where E4's review put it.

### §4.2 `Parse.parseInt`/`parseDouble` are not total — **CONFIRMED, and it is worse than reported**

```
>> parseInt 10 "1O2"           res1 : Maybe Int = (Just <error: For input string: "1O2">)
>> isJust (parseInt 10 "1O2")  res2 : Bool = True
>> parseDouble "12x"           res3 : Maybe Double = (Just <error: For input string: "12x">)
```

Yes: `isJust (parseInt 10 "1O2")` really is `True`. The mechanism the report gives is exactly right
and I read it out of the sources independently:

* `Session.scala:993` `perhapsForeign(FF(arg), v) = Prim(new FFI(perhapsForeign(arg, v)))`, and the
  inner call is `perhapsForeign(Raw, v) = Prim(v)` — so the by-name `v` is **forced inside
  `Prim.apply`**, at `Runtime.scala:51`, whose `catch { case e: Throwable => Bottom(throw e) }` turns
  the `NumberFormatException` into a *value*.
* `FFI` (`Runtime.scala:11`) is `class FFI[A](e: => A) { def eval = e }`, so the exception is already
  a `Bottom` before `eval` sees it; `Lib.scala:1311`'s `try { … t(Prim(r)) } catch { … c(Prim(err)) }`
  can never take its `catch`, `unsafeFFI` always returns `Right`, and `Parse.numberFormat`'s
  `Left e@(NumberFormatException _) -> Nothing` clause is dead code.

**What else the conversion hides — the report asks and does not answer.** Two things, both mine:

* **(a) `IO.catch` cannot catch a foreign exception either.** The report scopes the bug to `FFI` and
  `unsafeFFI`. It is not scoped to them: `perhapsForeign(IO(arg), v)` routes through the same `FF`
  branch, so an `IO` action built from a `foreign` declaration has its exception converted before any
  handler exists. Measured (`probes/LinkProbe.e`):

  ```
  caughtMissing = unsafePerformIO (catch (readFile "/definitely/not/here.txt") (e -> return "caught"))
  >> res7 : String = <error: /definitely/not/here.txt (No such file or directory)>
  ```

  `IO.catch` is `IO`'s only exception handler, and it does not run. **Every `IO` error path in the
  stdlib is unreachable for exceptions raised by the foreign call itself** — which is a bigger
  statement than §4.2 makes and belongs with it in the ticket.
* **(b) A plain (non-`FFI`) foreign is deferred, not swallowed.** `strCharAt "" 0` prints
  `runtime error: Index 0 out of bounds for length 0` in the REPL — the `Bottom` rethrows when
  forced. So the damage is confined to code that *tries to catch*: it converts a catchable exception
  into an uncatchable deferred one. That distinction is the right way to state the finding and the
  report does not draw it.

The consequence chain the report claims is real: `Validation.validateIntM errorMsg = maybe (Left
errorMsg) Right . parseInt 10`, so `validateInt "1O2"` is `Right <bomb>`, and `lookupInt`,
`lookupDouble`, `Layout.Validation.withValidation` and every `FormValidator` built on them inherit it.

**Ticket:** a new **A7** under *A. Runtime bugs*, or an extension of the A-group beside A1 — this is
the same family (a runtime conversion that makes a whole error path dead).

### §4.3 `String.Markdown.link` cannot produce a link — **REFUTED as stated**

The *type* claim is right and the module really is wrong: `link title loc = "[" ++ title "](" ++ loc
++ ")"` parses as `"[" ++ (title "](") ++ loc ++ ")"`, so `link : (String -> String) -> String ->
String` and it cannot be called as `link "My title" loc`. `TextTables.brokenLinkType` pins that and
is a good demonstration.

But "there is no argument you can pass that produces `[title](loc)`" (report §4.3), "can never
produce a link" (`TextTables.e` header) and "cannot produce a link" (§4.3's title,
`Helpers.mdLink`'s doc comment) are **false**. Pass the *prefixing function* and the shipped `link`
produces a correct link (`probes/LinkProbe.e`, both forms):

```
realLink  = link_MD (s -> "Docs" ++_S s) "https://example.invalid/a"
>> res0 : String = "[Docs](https://example.invalid/a)"
realLink2 = link_MD ((++_S) "SUP-77/A") "https://example.invalid/supplier"
>> res1 : String = "[SUP-77/A](https://example.invalid/supplier)"
```

`title "]("` with `title = (++) t` is `t ++ "]("`, which is precisely what the author meant to write.
So the correct statement is: **`link` takes its title pre-composed with `++`; every ordinary call
site is a type error, and `link ((++) title) loc` is the (unusable, undocumented) spelling that
works.** One missing `++` is still the whole fix, and it is still ticket-worthy — but the three
places in the group that say "can never" must be corrected. (L-2)

**Ticket:** *C. Wrong, misleading or missing API* — a new **C11**, one line.

### §4.4 The REPL EOF loop — **CONFIRMED**, and it is the already-ticketed A2

Same mechanism, different trigger string. Measured:

```
$ printf '"complete"\n' | bin/ermine     rc=124 (killed at 40 s)   3,900 '|>' prompts
$ printf '"complete"\n\n' | bin/ermine   rc=0, 8 s, 1 prompt, res0 : String = "complete"
```

(the report's 3,837 in 40 s; the difference is machine speed). `Console.scala:617`'s
`verbose.exists(input.contains(_))` plus `Console.scala:146`'s `null` at `EndOfFileException` against
`last == ""`. This is **exactly ticket A2**, whose recorded minimal input is `printf 'staircase\n'`;
`"complete"` is a second instance of the same substring trap (`comp-LET-e`), not a new finding. E5
presents it as its own finding (§4.4) while correctly noting E4 §4.7 found half of it; it should cite
A2 and stop. (L-14)

**Ticket:** already **A2**. Add `"complete"` as a second minimal input if anything.

### §4.5 The interface printer emits a scheme the parser rejects — **CONFIRMED (a), and (a) is what matters**

(a) `atAnyKind : forall {k} (a: k). a -> Int` is rejected with `failed to unify kind * with kind !k`
— reproduced as `shouldfail/lang07`, at 28:34, on the compiler in the tree. Correct, and the
minimal case really does need no rows and no library. Good negative.

(b) the *observation* that a `-Dermine.useInterface=true` load of an eta-delegating wrapper used to
publish `forall {a} … (a1: a)` before S3's change and does not after it: I could not test the
"before" state (that would mean reverting another agent's file and rebuilding, which the brief
forbids), and the report is careful to record correlation only, with timestamps and the class
fingerprint. On the compiler I measured — the same one, fingerprint
`8f54eee6211f4e0d309a444f54c1bd45` — **no wrapper in the group publishes a kind variable**, which is
consistent with the report's "after". Recorded as **PLAUSIBLE**; the honest framing is the report's
own, and its lesson ("the printer CAN emit a scheme the parser will not read, and nothing in the
build checks it") stands on (a) alone.

The dependence on S3 is worth one sentence to the orchestrator: if S3's change is reverted or
reworked, `Signatures.e`'s §1 and §3 comment blocks (which quote inferred schemes verbatim, and say
"Before 2026-09-07 03:22 both also carried an inferred KIND variable") go stale, and
`shouldfail/lang07` does **not** — it is a pure language fact. (L-15)

(c) the permutation of published partitions across two spellings of one function: I confirmed the
shipped side of it. `Helpers.ei` publishes `consRow … t <- (r, s)`, `pRecord … t <- (r, s)` and
`withRunning … t <- (r, c)`, all in the written order; `Signatures.e` records the *delegated*
wrappers coming back permuted. Both are consistent with what I see, and the conclusion — "an `.ei`
read as documentation will not always match the source it came from" — is right.

**Ticket:** the kind-variable half is already **B4** ("the compiler prints a type its own parser
cannot read back"); add `forall {k} (a: k). a -> Int` as B4's minimal case, since it is far smaller
than the `AsOp` witnesses B4 currently cites.

### §4.6 The four parse limits — **two confirmed, one confirmed-but-narrower, one refuted**

**(1) A suffixed bracket/brace literal cannot be a non-final argument — CONFIRMED.**

```
Pl1.e:4:16: error: expected eof or whitespace       u = const []_L "x"
Pl1b.e  LOADED                                      v = const ([]_L) "x" ;  w = const "x" []_L
```

**(1b) "The same limit stops a `]_L` being followed by `where`" — CONFIRMED for the shape that
motivated it, and narrower than stated.** The `TypesAndRows.e` shape fails:

```
Wh5.e:6:3: error: expected eof or whitespace
    tour5 = [ litOf 0, litOf 7 ]_L
      where litOf 0 = "literal zero"
```

so the module's parenthetical justification for thirteen top-level pattern functions is honest. But
it is not "a `]_L` cannot be followed by `where`": `k2 = length_L [1,2,3]_L` with a `where` under it
**loads** (`Pl8.e`), and so does a `where` whose bindings *contain* bracket literals (`Wh4.e`). The
failing case is a bracket literal that is the whole right-hand side. Worth the extra clause. (L-16)

**(2) A bracket literal is not a pattern — CONFIRMED.**

```
Pl2.e:5:19: error: expected '=', pattern atom, or whitespace     f [Just y, Just m]_L = "two"
```

**(3) "A character literal whose character is an operator symbol does not lex" — REFUTED as stated;
the real rule is positional.** Six modules:

| module | source | result |
|---|---|---|
| `Pl3b.e` | `dash = '-'` | **LOADS** |
| `Pl5.e` | `split_S '-' "a-b"` | **LOADS** |
| `Pl5c.e` | `split_S '.' …`, `split_S '|' …` | **LOADS** |
| `Ch1.e` | `c == '-'` | `error: unknown operator '-'` |
| `Ch3.e` | `c == '.'` | `error: unknown operator '.'` |
| `Ch2.e` | `c == '/'` | `error: unknown operator '/'` |
| `Ch4.e` | `c == ('-')` | `error: undefined term` |

So the criterion is **not** the character: `'-'`, `'.'` and `'|'` lex perfectly well in a
definition's head position and as a function argument — the group's own `TextTables.e` writes
`split_S '/' p` and `depthOf p = length_L (split_S '/' p)`, and `Helpers.stringChars` could have
been written with `'-'` directly. The criterion is **position**: after a binary operator the lexer's
maximal munch takes `'` and the character as one operator token, and `'/'` fails there exactly as
`'-'` does. The report's own sentence ("`'.'` and `'|'` are the same") is true only of the failing
position, and its exemption of `'/'` (implicit, since the group uses it) is unexplained.

Corrected statement, which is more useful to a reader: *a character literal immediately after a
binary operator is lexed as an operator (`c == '-'` → `unknown operator '-'`), for any character
that is an operator symbol including `/`; parenthesising does not help; put the literal in argument
or head position, or name it (`dashChar`).* (L-3)

**(4) There are no operator sections — CONFIRMED, both halves.**

```
Pl4.e:4:8:  error: ill-formed expression       g = (2 +)
Sec1.e:4:16: error: unknown operator +         addTwoRight = (+ 2)
```

and the bare `(+)` is a term (`Pl6.e` reaches a type error about its arity, so it parsed and
resolved). The report's fixity claim is also right: `infixl`, `infixr` and `infix` all work in
`TypesAndRows.e` and I confirmed `fixityWorks = (6.0,True,True)`.

**Ticket:** these are guide material rather than defects. Fold (1), (1b), (2), (3) as corrected and
(4) into **C10** ("small language facts worth a guide chapter"), which already collects this kind.

### §4.7 An `.ei` is neither a subset nor a superset — **CONFIRMED, both halves, both ways**

Machine-checked over the published interfaces, then tested by importing:

* `Helpers.ei` is **74 lines: 70 public + `mconcat`, `pbind`, `por`, `punit`** — the four `private`
  workers. `TypesAndRows.ei` carries `scaleBy` and `unwrap`. And they are **not importable**:
  `ImportProbe2.e` (`import Lang.Helpers`, uses `punit`) is `7:31: error: undefined term`
  **both with and without `-Dermine.useInterface=true`**.
* The five `foreign` declarations (`strLength`, `strIsEmpty`, `strCharAt`, `charIsDigit`,
  `charIsLetter`) appear in `Helpers.ei` **zero times** — and `ImportProbe.e` (`import Lang.Helpers`,
  uses `strLength`) **LOADS both ways**.

So the report's "over-reports (privates) and under-reports (foreigns) at the same time" is exactly
right, and it is the cleanest new tooling finding in the group.

**Ticket:** *D. Tooling* — there is no D-group for tooling defects yet (D is "claims that do not
reproduce"). Put it beside **B3** ("the `.ei` printer publishes a free row variable it does not
bind") as a new **B7**, since both are interface-printer defects that round-trip.

### §4.8 What `Prelude`'s unqualified scope binds — **five of seven rows confirmed, one refuted, one imprecise**

| row | report says | mine |
|---|---|---|
| `length s` | `List.length` | ✔ `:type length` is `forall a. List a -> Int` |
| `a ++ b` | `List.(++)` | ✔ |
| `a \|\| b` | `Layout.Report`'s selector disjunction | ✔ — my own probe hit it: `\|\|` in a `Bool` context gives `failed to unify type (SelectorEvent z) with type Bool` |
| `map f xs` | undefined | ✔ `List.map` is `private` (`List.e:284`), re-exported only as `map_List` |
| **`filter p r`** | **undefined** | ✖ **`filter` resolves**: `List.filter` is public (`List.e:224`) and `Prelude` exports `List` — `filter (n -> n > 2) [1,2,3,4]` is `[3,4]` in a module whose only unqualified import is `Prelude` (`probes/LinkProbe.e`) |
| `padRight`, `padLeft` | `Layout.Report`'s | ✔ `:type padRight` is `List ErasedMagnitude -> Report f a -> Report f a` |
| `empty_Bracket` | `List`'s | ✔ (`CsvIntake.e` must hide it, and does) |

The `filter` row is wrong (L-4). What is true, and is what the writer probably hit, is that
`filter` from `Prelude` is the **list** filter and a relational filter needs `filter_Pred` — a
different statement, and the one the "what you wanted" column already gives.

**Ticket:** already **C10**; add the `||` row, which is the sharpest of the seven and is not in C10
today.

### §4.9 `Data.Nu`'s seed is opaque — **CONFIRMED**

`shouldfail/lang06` reproduces (`skolem variables escape: / Type would have been: Nu f -> !s`), and
the module's account is right: `observe` is the only elimination, so `Nu f` is useless unless `f`
carries a value, which is why `FreeReportDsl.e` needs `Step` and not `Nxt`. `countUp` and `fibs`
having the same type with different seed types is the right demonstration of what the existential
buys, and I confirmed `nuTake 8 fibs = [0,1,1,2,3,5,8,13]`. Good finding, good negative, and a
refutation class no other group has.

**Ticket:** not a defect — guide material. **C10**.

### §4.10 The five smaller facts — **confirmed by source reading**

`Num` has no `mod` (checked `Num.e`); `Ord.ordMonoid` composes and `TreeAndMap.sortedLabels` proves
it (status before owner, `["Facilities","Commercial","Group",…]` — I re-derived the order by hand and
it is right); `Tree.join`'s `-- BUSTED:` comment sits above a working definition; `Map.union` is
left-biased and `Map` needs an `Ord k` value (I re-derived `unionLeftBiased` = 610,000 and
`unionSummed` = 2,570,000 from the data and both are right); `Field.withFieldCopy` mints a GUID name
and `copiedIsFresh` is `True`. All five stand.

### §4.11 Left recursion is caught at neither level — **CONFIRMED, and correctly handled**

`Parser a` is a function type; a diverging function is well-typed; there is nothing to reject, so
there is no negative. Documenting it in `StatementParser.e`'s header and saying so in the README
rather than inventing a negative is the right call, and is the sort of restraint the earlier groups
did not always show.

---

## 4. "What could NOT be written" — three of eight are wrong

### §6.1 A total number parser — **REFUTED**

The report says `Helpers.parseIntTotal` "avoids the problem rather than solving it: a string that is
all digits but overflows `Int` would still produce a bomb; the group has no such datum, **and there
is no way to write one that does not**."

There is. The bomb first (L-6):

```
>> parseIntTotal "99999999999999"           (Just <error: For input string: "99999999999999">)
>> isJust (parseIntTotal "99999999999999")  True
```

so the helper whose doc comment reads "`Parse.parseInt 10`, total" is **not total**, and the group's
whole workaround has a hole in it. And then the fix, eight lines, which I ran (`probes/Overflow.e`,
on top of `Lang/Helpers.e`):

```
safeInt s =
  let neg  = take_S 1 s == "-"
      body = if neg (drop_S 1 s) s
      cap  = if neg "2147483648" "2147483647"
  in if (looksLikeInt s
         && (length_S body < length_S cap
             ||_B (length_S body == length_S cap && body <= cap)))
        (parseIntTotal s) Nothing

>> probeOverflow : (Just 102, Nothing, Just 2147483647, Nothing)
```

A digit string of the right length compares lexicographically exactly as it compares numerically,
so the bound is a `String` comparison and needs nothing the language does not have. **`parseIntTotal`
should either carry this check or lose the word "total" from its name and its doc comment.** (L-7)

### §6.2 A `Free` interpreter using the stdlib's own eliminator — **CONFIRMED for the stdlib, MISSED for the group**

`Data/Free.e` really is 24 lines with `lowerFree : Monad m -> Free m a -> m a` and nothing else;
there is no `foldFree`, `iterM`, `runFree`, `FreeT` or `hoistFree`, and `lowerFree` demands the
command functor BE a monad. All true.

But the group's own method — *when the stdlib does not have the library, write it in `Helpers.e`*,
which it applies magnificently to the 20 missing parser combinators and to `accumAp` — was not
applied here, and it would have worked. `probes/FoldFree3.e` **loads**:

```
data Nat f m = Nat (forall x. f x -> m x)

foldFree : forall f m a. Monad_M m -> Nat f m -> Free_Fr f a -> m a
foldFree mm n (Pure_Fr a)  = unit_M mm a
foldFree mm n (Free_Fr fs) = case n of
  Nat k -> bind_M mm (k fs) (rest -> foldFree mm n rest)

runSay : forall a. Free_Fr Cmd a -> List a
runSay = foldFree listMonad (Nat sayNat)
```

Eight lines, generic in the command functor and the monad, and `FreeReportDsl.e`'s three
interpreters are three algebras over it. **The absence is the stdlib's; the omission is the
group's.** (L-17)

**And the language fact underneath, which is new and is worth more than several of the eleven
findings.** The *obvious* spelling — the natural transformation as a plain argument — does not
compile, and not for the DSL's reasons:

```
oneWay : forall f m. (forall x. f x -> m x) -> f Int -> m Int
oneWay nat a = nat a
-- Rank2b.e:6:1: error: failed to unify type (forall x. f x -> m x) with type (a -> b)
```

**A rank-2 function argument cannot be applied at all.** The signature parses; the term language
cannot use it. (The `data`-field form above does work — `probes/FoldFree3.e` loads — so the limit is
the *argument* position, not rank-2 itself.) Every rank-2 function in the stdlib is therefore in a
*data field*
(`data Monad f = Monad (forall a. a -> f a) …`, `Traversable`, `Cofree`, `Nu`, `F`), and the `Nat`
wrapper above is not a stylistic choice but the only working form. That single fact explains
`Data.Free`'s missing `foldFree`, `Control.Traversable`'s shape, and why `Data.Free.Church`'s `runF`
is "the exception" the report notices — it is the exception because `F`'s rank-2 field is inside a
`data`. (L-11)

**Ticket:** *B. Type-system holes* — a new **B8**: a `forall` in an argument position type-checks in
a signature and cannot be applied in a body; the `data`-field wrapper is the workaround. Two-line
repro above.

### §6.3 A `Validation` applicative using `Validation.e` — **CONFIRMED, with one wrong word**

`Validation.e` is a `FormValidator` library; there is no `Validation` type and no `Ap (Validation e)`;
`eitherAp` short-circuits; `accumAp` is the missing piece and is four lines. All correct, and
`CsvIntake.e`'s five-errors-against-two demonstration is the best thing in the group.

One word is wrong: `combineErrors` is **not** "non-exported". `Validation.e`'s only `private` block
is `arr` (line 112); `combineErrors` is a top-level export. The rest of the claim survives — its type
is `(a -> b -> c) -> String -> Either String a -> Either (List Err) b -> Either (List Err) c`, with
*different error types on the two sides*, so it is `liftA2` at one fixed shape and cannot be turned
into an `Ap (Either (List Err))`. Say "fixed at one shape", not "non-exported". (L-18)

### §6.4 Parser combinators using `Parse` — **CONFIRMED**

`Parse.e` is six `java.lang.*` parsers plus `parseBool`. The 20 combinators in `Helpers.e` are the
right response and `StatementParser.e` is the right demonstration. This is the largest gap between a
stdlib module's name and its contents in the tree, as the report says.

### §6.5 An `IO.CSV` read that runs — **REFUTED, and what actually breaks it is a stdlib bug**

The report says the read cannot be run because "there is no data file in this repository to point it
at". That is not what stops it. I pointed `readCSVFile` at a two-line CSV in my scratch and **the
read ran** — the file's contents appear in the session — and then the *value* came back bombed:

```
csvLines = length_L (unsafePerformIO_IOU (readCSVFile_CSV "…/probe-data.csv"))
>> 101,Aldgate Joinery,EMEA,2500000.00,A1,2009-04-17
   102,Brackenridge Mills,AMER,750000.00,B2,2011-01-08
   res4 : Int = <error: error invoking static foreign function: writeron object of type null;
                        expected an object of type class java.io.Console>
```

The cause is in `File.e`: `sourceToString# = map $ withSource# mkString#` and
`withSource# f s = let res = f s in let x = close# s in **traceShow res**`. `readFile` *traces its
own result*, `traceShow` writes through `java.lang.System.console()`, and in a piped or redirected
session that is `null`. So `File.readFile` — and therefore `File.fileLines`, `IO.CSV.readCSVFile`
and `readCSVURL`, everything in the module — **cannot return a value in a non-interactive session**,
and it dumps the whole file to stdout in an interactive one. That is a stdlib bug nobody has
recorded, and it is why the E5 author's `readCSVFile` never ran. (L-10)

What §6.5 should say: the read is expressible and runs; a data file next to the module would work
(relative to the JVM's cwd, which is the repository root under `bin/ermine`); the obstacle is
`File.readFile`'s `traceShow`. Two of the report's three surrounding statements are right and worth
keeping: `parseCSV` is `split ','` per line with no quoting, escaping or header handling, and the
whole intake really is `map (readRowsAs …) . readCSVFile`.

**Ticket:** *A. Runtime bugs* — a new **A8**: `File.readFile` traces its result through
`System.console()`; every `File`/`IO.CSV` read returns a bomb under a piped session and prints the
file under an interactive one. One-line fix (drop the `traceShow`, or route it through `stderr`).

### §6.6, §6.7, §6.8 — confirmed

* §6.6 the kind-variable scheme: confirmed as §4.5(a), and `Signatures.e`'s two `xFull` forms
  written at kind `*` with a note is the right accommodation.
* §6.7 `Tree.fromRel` outside a `Report`: confirmed by reading `Tree.e` and `Layout/Scan.e` — the
  only `RunScan List z` the stdlib builds is `Layout.Scan.runner` at `z = Report f z'`, so the
  relation-to-tree direction is report-only while `toRel`/`toRootedRel` are not. `treeSection` is
  the right shape and the asymmetry is worth the paragraph.
* §6.8 `String` has `uppercase` and no `lowercase` (`String.e:98`), and `Layout.Report` holds
  `padLeft`/`padRight`. Both confirmed; `TextTables.e` declaring its own `lowercase` in three lines
  of `foreign` mid-module is the best small demonstration of `foreign` in the group.

**Two cross-references in §6 are off by one section**: §6.1 cites "§4.1" for the `Parse` finding
(that is §4.2) and §6.6 cites "§4.4" for the kind variable (that is §4.5). (L-21)

---

## 5. The modules as programs

I read all twelve in full and checked every arithmetic claim against the data. **The arithmetic is
clean** — which, after E4 (three modules with invented headline numbers), is worth saying plainly. I
re-derived, by hand, every figure the report renders: `RunningState`'s seven `netAmt = grossAmt −
feeAmt` lines and the whole running trail to 90,947.07, `netAndFees` = (90947.07, 2502.93);
`FreeReportDsl`'s five `netSales = grossSales − discountAmt` lines, `netTotal` = 2,504,163.5,
`unitTotal` = 8,492, `countOf` = 12 and all five `firstFiveSmoothed` means; `TreeAndMap`'s subtree
roll-ups (Group 11,100,000 = the whole table; Technology 3,500,000), `unionLeftBiased` 610,000 and
`unionSummed` 2,570,000, and the composed-`Ord` sort order; `ForeignJdk`'s `ratedRms` 246.179…;
`TypesAndRows`'s `pinnedByWitness` 33,220,000. **Every one is right.** The trimmed renderings in
§G4 reproduce (I re-ran twenty of them in one session), including the two error values that are the
point.

### The three best

1. **`CsvIntake.e`** — the best module in the group and one of the best in the E series. It takes
   the one step the stdlib stops short of (`List (List String)` to `[..r]`), makes the type carry the
   header, and then earns its argument by *measuring* it: the same reader over the same bad CSV
   reports **five** errors under `accumAp` and **two** under `eitherAp`, and the header explains
   precisely why the two both come from line 2 ("`consRow` accumulates WITHIN a row whichever
   applicative is used over the rows; it is the traversal that short-circuits"). That parenthesis is
   the kind of care the rest of the corpus should aspire to. It also carries the only user-defined
   bracket literal in `core/examples`, with both of the consequences a reader needs to know
   (hide `Prelude`'s pair; every unsuffixed `[…]` in the module is now yours) spelled out.
2. **`TypesAndRows.e`** — the missing guide chapter, and it does not cheat. Kinds with a worked
   `(s : rho)` and `(f : * -> *)`, an existential that is used rather than described, `private` with
   the `.ei` consequence stated, three fixity declarations that are then *exercised*
   (`fixityWorks = (6.0, True, True)` distinguishes all three associativities), **every** pattern
   form including the lazy, strict and empty ones with a stdlib citation for each, and `Type.Eq` /
   `Type.Cast` / `Type.Remember` — three modules with no example anywhere — each used for what it is
   actually for. The `coerceEq` derivation (`subst` through a private `Wrap`) is the only place in
   the tree that shows how to move a value across a proved equality.
3. **`FreeReportDsl.e`** — the clearest demonstration in the corpus of what dictionary-passing buys:
   a monad that *did not exist until this file made one*, and then three interpreters over one
   program, with the Church encoding beside it showing that `runF` needs no functor. `Cofree` used
   as a moving average via `extend` is the only comonad use in the repository and it is the right
   one. Marked down only by §6.2/L-17: it documents the absence of `foldFree` where it could have
   supplied it.

Honourable mention: **`README.md`** is the best group README in `core/examples` — the "one thing to
know before reading any of it" section explains Ermine's substitute for `instance` better than any
prose in the tree, and the ten-things list is exactly what a newcomer needs.

### The three weakest

1. **`StatementParser.e`** — the group's front door (it is the command in `core/examples/README.md`)
   and it contradicts the group's own headline finding. `amountP` calls the raw, bombing
   `Parse.parseDouble`:

   ```
   >> parseLine "2011-03-30|REF00188|DEPOSIT|Nope|abc|2.00"
   (Just {sourceLine = "…", valueRef = "REF00188", postedOn = Tue Mar 29 …,
          movementAmt = <error: For input string: "abc">, movementKind = "DEPOSIT", …})
   >> isJust (parseLine "…|abc|2.00")     True
   ```

   A parser that *succeeds* with a bomb in the record, in the group whose most consequential finding
   is that `Parse` does this. `Helpers.parseDoubleTotal` exists, is never called from any module, and
   is what `amountP` should use. The report's own file table lists `parseDoubleTotal` among
   `StatementParser`'s helpers — it is not used there. (L-5)
2. **`Helpers.e`** — as a *library* it is excellent; as a *file* it is a grab-bag with loose edges.
   See §6.
3. **`ForeignJdk.e`** — the coverage is right and the six-forms table is genuinely useful, but a
   third of what it declares is decoration: `maxDouble`, `readLongIO`, `shout` and `decimalShown`
   are declared or defined and never used, `guidShown` duplicates `guidRoundTrip`, and the header's
   "declaring it twice at two types in the same module is how you get both [`abs` overloads]" is an
   assertion the module does not test — it writes `absInt` in Ermine instead. E4's review made the
   same criticism of `StyleGridHeatmap` ("coverage for its own sake"); it applies here. (L-22)

`TextTables.e` is not in either list but is the module a reader will enjoy most: four renderings of
one relation, all of which print, is the answer to `Present/`'s "there is no `render`", and
`splitCamelCase` / `allMatches` / `replaceAll` with a capture group had no example anywhere. Its
`brokenLinkType` binding is a clever way to pin a bug in a type — spoiled only by the claim around
it (L-2).

`ReaderParams.e` is solid and is the module closest to the production shape
(`tracker/JSON-API-DESIGN.md`'s params→report). One over-claim: its SHAPES block says "Five
`askField`s under ONE row variable in a single `lift`ed expression"; the largest single lifted
expression is `lift3_SR` over three, and the five only meet in `networkReport`'s `do` block. Also
worth knowing, and not said: because `Params` is a *concrete* row, none of its five projections
costs anything — `ReaderParams.e(167:46)` draws 4 — which is the positive half of the projection
cliff and the best possible advertisement for writing the parameter row down.

`RunningState.e`'s `postedRatios` is misnamed: it is `feeRatios` over the rows with a non-zero
*gross*, and has nothing to do with `postedMark`. (L-13)

`DoNotation.e` is the widest single module (five monads, `liftA2…liftA6`, `strength`, `mapply`,
`ifM`, `join`, `Alt`) and every claim in it checked out, including the subtle one — `ifM` runs one
branch, `chosen = (0,9)`. `TreeAndMap.e` is the module I learned most from: `toRootedRel` minting
ids off an infinite `List.Stream` is a genuinely surprising piece of stdlib and the file explains it
properly.

### The `do` / `Free` / `Reader` idioms

Idiomatic throughout, and the group is careful about the one thing that trips everyone: `do`
desugars to `Monad f -> f a`, `liftDo` is `const`, the block must be applied, and `'` is `infixl 0`
so a right-nested chain needs parentheses. Every `do` in the group uses the `(do …) ' dict` form and
`lineP`'s comment about the parentheses is exactly the note a reader needs at exactly the place they
need it. `addTwo` instantiated at five monads from one three-line body is the right way to make the
point that Ermine's `do` is monad-generic *because* the dictionary is an argument, and `lang04`
(applying a `Maybe`-built block to `listMonad`) is the right negative for it.

### The seven negatives as teaching

Each teaches a distinct lesson and each is minimal: a row that does not unify (`lang01`, `lang05`), a
disjointness violation caught at row *construction* rather than in the solver (`lang02`, `lang03` —
and the header of `lang02` says so, which is the useful part), the dictionary as an ordinary argument
(`lang04`), an existential that cannot leak (`lang06`), and a kind error (`lang07`). The two the
report calls out as new classes really are new. My only reservation is that `lang02` and `lang03`
teach the same mechanism twice; a seventh negative on something else — a `RowReader` whose cell type
disagrees with its field, say — would have covered more.

---

## 6. `Helpers.e`'s 70 bindings — library or grab-bag?

**Both, and the split is clean.** The 45-odd bindings that make up the four sub-libraries — the
parser (`Parser`, its three dictionaries and 13 combinators), the row reader (`RowReader`, `nilRow`,
`consRow`, `readRowsAs`, `runRowReader`, four cell readers), the five row traversals, the text
renderers — are a coherent library that a user would reuse, and they are the part the group actually
exercises: `foldRows` in six modules, `withRunning`, `foldMapL`, `sumMonoid`, `joinedMonoid` and
`Parser` in four each.

The grab-bag is at the edges. Machine-checked, **six public bindings have no call site anywhere in
the group, not even inside `Helpers.e`**: `allOrNothing`, `cellOr`, `orElseA`, `withDefaultA`,
`minMonoid`, and (`twiceOver` aside, which the REPL recipe evaluates) `inMonad`. A further thirteen
are internal machinery published as public API (`stringChars`, `charsAll`, `looksLikeInt`,
`looksLikeNumber`, `charsToString`, `mdRow`, `mdRule`, `pDigits`, `pSpaces`, `parserAp`, `dotChar`,
`strIsEmpty`, `charIsLetter`) — harmless, but they are why the count is 70 rather than ~50, and the
report leads with the 70. E4's group had **all 34** helpers called from a report module; E5 has six
that are called from nowhere. (L-12)

**Doc comments.** The brief asks for "a doc comment naming the row constraint it carries and why" on
every helper. **22 of 68 top-level signatures have no doc comment at all** (`runRowReader`,
`cellString`, `cellInt`, `cellDouble`, `runParser`, `parserMonad`, `parserAp`, `parserFunctor`,
`pSpaces`, `pDigits`, `pInt`, `pDouble`, `foldMapL`, `sumMonoid`, `countMonoid`, `maxMonoid`,
`minMonoid`, `charsToString`, `rpad`, `lpad`, `mdRow`, `mdRule`). Every one of the *five*
constraint-carrying helpers is documented, and documented well — `consRow`'s and `withRunning`'s
comments name the partition and say what it rules out, with a pointer to the negative that proves it
— so the brief's substantive requirement is met; the tail is not. (L-12)

**Call sites on a wide table.** The brief also asks for a call site on a table of at least a dozen
fields. `withRunning`, `traverseRows`, `checkedRel`, `foldRows`, `showRows` and `withState` all get
one (`RunningState`'s 13-column row). `consRow` (6 columns), `pRecord` (7) and `askField` (a
5-field parameter row) do not. Minor, and arguably right — a CSV reader over 13 columns would be
tedious — but it should be said rather than implied. (L-12)

**Two naming defects.** `countMonoid : Monoid Int` is integer *sum*, not counting; it is used as a
sum in `FreeReportDsl.unitTotal` (summing `unitsSold`) and as a count in `RunningState.extremes`,
which is fine but the name only describes one. And `parseIntTotal` / `parseDoubleTotal` are not total
(L-6/L-7).

**Header defects.** `Helpers.e`'s header says "FIVE THINGS THAT COST A COMPILE HERE" and then lists
**seven**; and it says "FIVE of those carry an explicit row CONSTRAINT" and then lists **four**
names, one of which (`traverseRows`) carries no constraint at all. The five are `consRow`,
`pRecord`, `withRunning`, `askField`, `localField` — which the `README.md` table gets right. (L-12)

---

## 7. Coverage against the brief

**Exercised, and new to `core/examples`.** Against the brief's list, with the import census as it
stood outside `Lang/`: `Control.Alt` (0 before), `Control.Comonad` (0), `Control.Monoid` (0),
`Control.Monad.State` (0), `Data.Free` (0), `Data.Free.Church` (0), `Data.Cofree` (0), `Data.Nu` (0),
`Syntax.Do` (0), `Syntax.Monad` (0), `Syntax.Reader` (0), `StringManip` (0), `String.Markdown` (0),
`List.Stream` (0), `Random` (0), `GUID` (0), `Type.Cast` (0), `Type.Eq` (0), and one-example modules
`Control.Traversable`, `Control.Monad.Reader`, `Tree`, `List.Util`, `IO.CSV`, `File`,
`Type.Remember`, `Constraint`, `Syntax.Either`, `Syntax.Maybe`. Plus the language items: `data` with
`(s : rho)` and `(f : * -> *)`, existentials, `foreign` in all six forms plus `private foreign`,
`private`, three fixity declarations, every pattern form, the whole row vocabulary, `field`
declarations, `Has`. **That is the brief's list very nearly complete, and it is the largest single
addition to the example corpus in the programme.**

Exercised *indirectly*, which the report should say because a reader grepping for the import will not
find it: `Control.Ap` (through `Control.Monad`'s re-export — every `Ap_M`), `Control.Monad.Cont`
(through `Prelude`, in `TreeAndMap.treeSection`'s `runCont`), `Parse` (through `Prelude`, which
`export`s it — `Helpers.parseIntTotal` calls `parseInt` with no import), `Error` and `Eq` (through
`Prelude`).

**Missed, and not accounted for in §6** — five names from the brief that no module in the group
imports, mentions, or explains the absence of:

* **`Control.Category`** — the brief names it; nothing in the group touches it. (`Validation.e`'s
  comment "there are no combinators for it, and `arr` is private" is the reason a `Validator` cannot
  be a `Category` here, and would have been a one-paragraph finding.)
* **`Control.Monad.Error`** and **`Control.Monad.Id`** — named in the brief; `RunningState.e` uses
  `StateT s Maybe` where `ErrorT` would have been the natural third transformer, and `Id` is the
  base every transformer stack needs.
* **`Syntax.Procedure`** — named in the brief; nothing.
* **`List.NonEmpty`** — named in the brief; `TreeAndMap.e` *consumes* a `NonEmpty` (`flatten_Tr`
  returns one and the module reaches for `toList_NS` from `Native.Stream` to get out of it) without
  ever naming the module or saying why. That is the closest miss and the easiest to close.

**A follow-up module** would take `Control.Category`, `Control.Monad.Error`, `Control.Monad.Id`,
`List.NonEmpty` and `Syntax.Procedure` in one file — "the transformer stack and the categories" —
and would close the brief's list. That is the single highest-value follow-up this group points at.

The brief also asked for `Eq`/`Ord` (4 examples before): `Ord` is well covered (`ordMonoid`,
`contramap`, `primOrd`, `fromLess`), `Eq` is not touched.

---

## 8. Wiring, checked against the tree

The orchestrator has **already applied and committed** (`6a63dbb`) most of E5's requested lines.
Checked line by line against the committed tooling:

| item | requested | in the tree |
|---|---|---|
| `looptrace-corpus.sh` `Lang)` / `Lang-shouldfail)` cases | §5(a) | ✔ lines 108–117, verbatim |
| `looptrace-corpus.sh` default group list | `… Lang Lang-shouldfail …` | ✔ line 53 |
| `corpus-run.sh` `files=` | §5(b) | ✔ lines 110–111 |
| `corpus-run.sh` batch hoist + `lang_done=0` | §5(b) | ✔ lines 138–142 |
| **`corpus-run.sh` per-file hoist** | §5(b) | ✖ **MISSING** |
| `corpus-run.sh` header comment (file counts) | not requested | ✔ updated to 151 files |
| `core/examples/README.md` directory row | §5(c) | ✔ line 23 (reworded, "eleven modules") |
| `core/examples/README.md` example command | §5(c) | ✔ line 33 |
| `core/examples/README.md` `shouldfail/` paragraph | §5(c) | ✔ |
| `TestSurfaceParsers.scala` | "not needed" | ✔ correct — 20 properties pass unchanged |

**The per-file hoist is missing** in the committed `corpus-run.sh` (lines 167–178), exactly as it
was for `Present/` when E4's review ran (M-10, since applied):

```bash
  case "$f" in
    core/examples/Ai/Common.e)    ;;
    …
    core/examples/Present/Helpers.e) ;;
    core/examples/Present/*)      args=( core/examples/Present/Helpers.e "$f" ) ;;
  esac      # <- no Lang/ arm
```

so a non-`--batch` `corpus-run.sh` loads every `Lang/` module **without `Lang/Helpers.e`** and every
one of them fails. The two lines E5 asked for are still needed:

```bash
    core/examples/Lang/Helpers.e) ;;
    core/examples/Lang/*)         args=( core/examples/Lang/Helpers.e "$f" ) ;;
```

**Two notes on what was applied.** (a) The `README.md` row says "**eleven** modules on the language
itself" where the group has ten reports plus `Helpers.e` and `Signatures.e` (twelve `.e` in
`Lang/`), and E5's requested wording said "ten modules"; the README under `Lang/` says "Ten
self-contained Ermine modules … a shared library … proofs". Pick one count and make the three agree.
(b) The `looptrace-corpus.sh` comment reads "every Lang module imports `Lang.Helpers`, and so **may**
every module under `Lang/shouldfail`" — accurate as softened: **five of the seven** negatives import
it, `lang06` and `lang07` do not, and hoisting the library is free. Better than the `Present/`
comment E4's review found false.

---

## 9. What moved under this review

Nothing in the compiler: `Subst$.class` is `8f54eee6211f4e0d309a444f54c1bd45` at the start and the
end of every run. The tree gained `tracker/TICKET-stdlib-findings.md` (`740da34`) while I worked,
and `B5`'s figures there were extended by E4's reviewer mid-review; my §2.2 numbers are consistent
with the extended B5.

I created no file under `core/examples`; the one data file my `IO.CSV` probe needed lives in my
scratch and is referenced by absolute path. All `.ei` deleted.

---

## 10. Findings

### Must fix before commit

* **L-1 — the census's one wrong cell is the headline one, and it is E4's M-1 repeated.**
  "per-key mints, max **29** … against a round-7/8 corpus bound of 11 and E4's 12, which was itself
  the first breach" is wrong three ways: 29 is `--cycle`'s `maxmint`, the *minted-vocabulary size*
  (`Cycle.lean:407`), not a per-key count; `--mints` gives the per-key maximum over `Lang/` as
  **1**; and E4's "12" was the same mislabel, corrected by `E4-REVIEW.md` M-1 to `maxmint` 11 and
  per-key 1. Delete the breach claim wherever it appears — report §summary, §G3 table, §4.1's
  ladder, `README.md`'s table, `ProjectionCliff.slow`'s table, and the `LOOP-MODEL-PLAN.md` row —
  and report `maxmint` under its real name (29 *is* a corpus record for minted vocabulary, and worth
  keeping as that). **CONFIRMED** by `looptrace --replay Lang.tsv --mints`.
* **L-2 — `String.Markdown.link` CAN produce a link.** `link ((++) "SUP-77/A") loc` returns
  `"[SUP-77/A](https://…)"`. Correct §4.3's title and body, `TextTables.e`'s header ("can never
  produce a link") and `Helpers.mdLink`'s doc comment ("cannot produce a link"): the defect is that
  `link` demands its title pre-composed with `++`, so no ordinary call site type-checks — not that
  no argument works. **REFUTED by a module that loads.**
* **L-3 — the character-literal rule is positional, not about the character.** `'-'`, `'.'` and
  `'|'` all lex in head and argument position (the group's own `TextTables.e` writes
  `split_S '/' p`); all of them, `'/'` included, fail immediately after a binary operator
  (`c == '/'` → `unknown operator '/'`). Restate §4.6(3), the `Helpers.e` comment and `README.md`
  item 6. **REFUTED as stated, CONFIRMED in the corrected form**, seven minimal modules.
* **L-4 — §4.8's `filter` row is wrong.** `List.filter` is public and `Prelude` exports `List`, so
  `filter` resolves; only `map` is `private` in `List.e`. Change the "you get" column to
  `List.filter`. **REFUTED by a module that loads.**
* **L-5 — `StatementParser.amountP` uses the bombing `parseDouble`.** The group's front-door module
  returns `Just {… movementAmt = <error: For input string: "abc"> …}` on a malformed amount — the
  exact defect §4.2 is about. Use `parseDoubleTotal` (which exists, and which the report's own file
  table already claims this module uses). **CONFIRMED in the REPL.**
* **L-6 — `parseIntTotal` is not total, and its doc comment says it is.**
  `parseIntTotal "99999999999999"` is `Just <error: …>`. Either add the range check (L-7) or drop
  "total" from the name and the comment; as it stands the group ships the same class of defect it
  documents. **CONFIRMED in the REPL.**
* **L-7 — §6.1's "there is no way to write one that does not" is false.** An eight-line `safeInt`
  that compares the digit string against `"2147483647"` lexicographically is total and I ran it:
  `(Just 102, Nothing, Just 2147483647, Nothing)`. **REFUTED by a module that loads.**
* **L-8 — "the most expensive solve in the group" is attributed to the wrong binding, in three
  places.** §4.1 and `README.md` say `TextTables.catalogueMarkdown`; `ProjectionCliff.slow`'s header
  says it too *and* gives it 1,241 draws / 27 mints. The report's own §G3 table says
  `catalogueMarkdown` (`TextTables.e(119:13)`) draws **1,230** and is **third**, behind
  `catalogueAscii` (`138:23`, 1,245) and `postingMarkdown` (`RunningState.e(201:13)`, 1,241). My
  census agrees with the table. Fix the three headers to name `catalogueAscii`, or say "the three
  five-projection cell lambdas, of which `catalogueMarkdown` is one". **CONFIRMED by re-census.**

### Should fix

* **L-9 — the §4.2 mechanism reaches `IO`, not just `FFI`; say so.** `IO.catch` cannot catch an
  exception raised by the foreign call: `catch (readFile "/nope") (e -> return "caught")` evaluates
  to `<error: /nope (No such file or directory)>`. Every `IO` error path in the stdlib is unreachable
  for foreign exceptions. Also worth the distinction that a *plain* foreign defers rather than
  swallows (`strCharAt "" 0` reaches the REPL as a runtime error), so the damage is confined to code
  that tries to catch. **CONFIRMED.**
* **L-10 — §6.5's reason is wrong and the real one is a stdlib bug.** `readCSVFile` *ran* over a
  file I pointed it at; the value came back `<error: … java.io.Console …>` because
  `File.withSource#` ends in `traceShow res`, which writes through `System.console()` — `null` in a
  piped session. `File.readFile`, `fileLines`, `IO.CSV.readCSVFile` and `readCSVURL` therefore
  cannot return a value non-interactively and dump the file to stdout interactively. Rewrite §6.5
  and file the bug. **CONFIRMED.**
* **L-11 — a rank-2 function argument cannot be applied.**
  `oneWay : forall f m. (forall x. f x -> m x) -> f Int -> m Int ; oneWay nat a = nat a` is
  `failed to unify type (forall x. f x -> m x) with type (a -> b)`. The `data`-field wrapper is the
  only working form. This is a language finding bigger than several of the eleven and it explains
  §6.2 and §6.4 and the shape of every `Control.*` dictionary. **CONFIRMED.**
* **L-12 — `Helpers.e`'s edges.** Six public bindings with no call site anywhere (`allOrNothing`,
  `cellOr`, `orElseA`, `withDefaultA`, `minMonoid`, `inMonad`); 22 of 68 signatures with no doc
  comment; `consRow`/`pRecord`/`askField` with no call site on a ≥12-field table; the header's "FIVE
  THINGS" followed by seven, and "FIVE … carry an explicit row CONSTRAINT" followed by four names,
  one of which (`traverseRows`) carries none. The `README.md` table gets the five right.
* **L-13 — `RunningState.postedRatios` is misnamed** (it filters on non-zero `grossAmt`, not on
  `postedMark`) and duplicates `feeRatios`'s body. Rename or delete.
* **L-14 — §4.4 is ticket A2, already filed.** Cite it rather than presenting it as an E5 finding;
  the *unbounded* half was E4's reviewer's, and the ticket records it. `"complete"` is a second
  minimal input, not a new mechanism. (My run: 3,900 prompts in 40 s; the blank-line control exits
  in 8 s.)
* **L-15 — say what S3's landing or reverting does to `Signatures.e`.** §1 and §3's comment blocks
  quote inferred schemes and the "before 2026-09-07 03:22" kind variable; those go stale if S3
  changes. `shouldfail/lang07` does not — it is a pure language fact. One sentence for the
  orchestrator.
* **L-16 — §4.6(1)'s `where` clause is narrower than stated.** A `]_L` that ends a right-hand side
  cannot be followed by `where`; a `]_L` that is a function's last *argument* can (`Pl8.e` loads).
  The `TypesAndRows.e` justification is honest; the general sentence is not.
* **L-17 — §6.2 should distinguish "the stdlib lacks it" from "it cannot be written".** An
  eight-line generic `foldFree` through a `Nat` wrapper loads (`probes/FoldFree3.e`) and would have
  turned `FreeReportDsl.e`'s three interpreters into three algebras. The group wrote the missing
  parser library and the missing accumulating applicative; it should say why it did not write this
  one.
* **L-18 — §6.3: `combineErrors` is exported.** Only `arr` is `private` in `Validation.e`. The
  substantive claim (it is `liftA2` at one fixed shape, with different error types on its two sides,
  so it cannot be reused as an `Ap`) survives; the word "non-exported" must go.
* **L-19 — the timings and two counts in `LOOP-MODEL-PLAN.md`'s E5 row disagree with the report.**
  The row says per-file own check "0.14–0.77 s" (report: 0.14–1.06 s; mine 0.13–0.63 s), batch
  "**5.15 s**" (report: 3.85 s; mine 3.57 s), and `Signatures.e` "four `xFull`/`xDeduped` pairs,
  three `xSimple` specialisations" where the file has **five and five** and the report says five and
  five. Reconcile the row with the report before committing.
* **L-20 — the remedy is worth measuring in the modules, not only in `.slow`.** The three costliest
  solves in the E-series corpus are one token from free: annotating the cells lambda takes
  `showRows`'s call from **1,230 draws to 1**, and swapping the helper's argument order does
  *nothing* (1,233). A two-line note in `TextTables.e` and `RunningState.e` showing both spellings
  would teach the lesson and leave the census number there on purpose.
* **L-21 — two §6 cross-references are off by one section** (§6.1 cites §4.1 for the `Parse`
  finding, which is §4.2; §6.6 cites §4.4 for the kind variable, which is §4.5).
* **L-22 — `ForeignJdk.e` declares more than it uses.** `maxDouble`, `readLongIO`, `shout`,
  `decimalShown` and `guidShown` are never used; the header's claim that declaring `abs` twice at
  two types gets both overloads is asserted, not shown (the module writes `absInt` in Ermine).
  Either use them or cut them.

---

## 11. Recommended ticket entries (recommendation only — I wrote nothing)

Into `tracker/TICKET-stdlib-findings.md`, under the headings it already has:

* **A (runtime bugs) — new A7: the foreign-exception conversion.** `Runtime.scala:51`'s `Prim.apply`
  catches any exception thrown while forcing a foreign result and returns `Bottom(throw e)`;
  `Session.scala:993`'s `perhapsForeign` forces inside it for both the `FF` and the `IO` branch. So
  `IO.Unsafe.eval`'s `try/catch` (`Lib.scala:1311`) never fires, `unsafeFFI` always returns `Right`,
  `Parse.numberFormat`'s `NumberFormatException` clause is dead code, and **`IO.catch` cannot catch a
  foreign exception either**. `parseInt 10 "1O2"` is `Just <bomb>` and `isJust` of it is `True`;
  every `Validation` validator and `Layout.Validation.withValidation` inherits it. Not a
  one-character fix — `Prim.apply`'s catch is how a `Bottom` reaches the printer — so it is a design
  question. (E5 §4.2; E5-REVIEW §3/L-9.)
* **A — new A8: `File.readFile` traces its own result.** `File.e`'s `withSource# f s = let res = f s
  in let x = close# s in traceShow res` writes through `System.console()`, which is `null` under a
  pipe: every `File`/`IO.CSV` read returns `<error: … expected an object of type class
  java.io.Console>` in a batch session and dumps the file to stdout in an interactive one. One-line
  fix. (E5-REVIEW §4/L-10.)
* **B (type-system holes) — new B7: an `.ei` is neither a subset nor a superset of the module.** It
  lists `private` bindings that an importer cannot resolve (with or without
  `-Dermine.useInterface=true`) and omits `foreign` declarations that an importer resolves fine.
  Belongs beside B3, the other interface-printer defect. (E5 §4.7; E5-REVIEW §3.)
* **B — new B8: a rank-2 function argument cannot be applied.**
  `forall f m. (forall x. f x -> m x) -> f Int -> m Int` type-checks as a signature and its argument
  cannot be used (`failed to unify type (forall x. f x -> m x) with type (a -> b)`). The
  `data`-field wrapper is the only working form, which is why every `Control.*` dictionary is shaped
  the way it is and why `Data.Free` has no `foldFree`. (E5-REVIEW §4/L-11.)
* **B4 — add E5's minimal case.** `atAnyKind : forall {k} (a: k). a -> Int` →
  `failed to unify kind * with kind !k` is far smaller than the `AsOp` witnesses B4 cites, and
  `core/examples/Lang/shouldfail/lang07_kind_variable_written.e` ships it. (E5 §4.5(a).)
* **B5 — no change needed.** E5's ladder and diagnostic are a second, independent confirmation of
  what E4's reviewer measured; the entry already says so. Worth adding one line: **the remedy is the
  annotation and only the annotation** — the helper's argument order makes no difference
  (1,230 vs 1,233 draws), the annotation takes it to 1.
* **C (wrong/misleading API) — new C11: `String.Markdown.link`.** `link title loc = "[" ++ title
  "](" ++ loc ++ ")"` — juxtaposition binds tighter, so `link : (String -> String) -> String ->
  String` and the only working call is `link ((++) title) loc`. One missing `++` is the fix.
  (E5 §4.3; corrected by E5-REVIEW §3/L-2.)
* **C10 — extend the guide-facts list** with: `||` unqualified is `Layout.Report`'s selector-event
  disjunction, not `Bool`'s (`&&` is unaffected); a character literal immediately after a binary
  operator is lexed as an operator, for any operator character including `/`; there are no operator
  sections (`(2 +)` is `ill-formed expression`, `(+ 2)` is `unknown operator +`, bare `(+)` is a
  term); a suffixed bracket literal cannot be a non-final argument, cannot be a pattern, and cannot
  end a right-hand side that a `where` follows; `Num` has no `mod`; `Data.Nu`'s seed cannot be
  projected. (E5 §4.6, §4.8, §4.9, §4.10.)

Nothing from E5 belongs in `tracker/TICKET-editor-and-solver-followups.md`: the one solver item
(the projection cliff) is already B5, and B5 already names the S4 stage.

---

## 12. Summary for the orchestrator

**ADVANCE after L-1 … L-8.** The Ermine does not need rewriting: five of the eight must-fixes are
sentences in headers and a report, two are one-line changes in `StatementParser.amountP` and
`Helpers.parseIntTotal`, and one is a census cell. The group is a large, accurate and genuinely
instructive addition to `core/examples`; its census is the most faithful the programme has produced;
its negatives and its one-session recipe are the best in the E series; and three of the findings my
own probes turned up (L-9, L-10, L-11) are stronger than several the report leads with and should be
carried into the ticket with the rest.

Add the two missing `corpus-run.sh` per-file lines (§8) when wiring.
