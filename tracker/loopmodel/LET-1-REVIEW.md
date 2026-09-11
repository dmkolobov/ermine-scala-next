# LET-1 review — a `let`-bound signature reaches the type checker again

**Verdict: FIX-THEN-ADVANCE.** The compiler change is correct and I found no behaviour
difference on the top-level/`where` path that matters; the corpus/`.ei`/G1 claims reproduce
exactly; the refusal channel surfaces correctly in batch, editor and REPL; there is no
kind-variable leak (proved with a positive control). The four edits below are documentation
and one missing pin — **none of them touches compiler code**, so re-gating is limited to
`*TestLetSignatures` plus one corpus file.

Reviewed in `ermine-scala-wt-let` (branch `let-signatures`, HEAD 3022672 + the implementer's
uncommitted tree). Report under review: `tracker/loopmodel/LET-1-FIX.md`. My scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/review-LET1/`.
Per the orchestrator's mid-review instruction the per-file corpus sweep was stopped at 110 of
154 files and item 4 completed with `--batch`; that is recorded in item 4 as measured, not claimed.

## The edit list (FIX-THEN-ADVANCE)

1. **Pin the new `let`-block interleaving refusal.** Sharing the implementation makes
   `let f 0 = 1; g y = y; f 1 = 2 in …` a refusal in a `let` block for the first time
   (measured: `IL.e:9:7: error: interleaved equations for f`). It is shipped batch behaviour
   with no test. Add one property to `TestLetSignatures` (`rejected(..., "interleaved
   equations")`), and, because the `let` channel RECORDS rather than throws, one line in
   §2's `Lower.BlockEnv` paragraph of LET-1-FIX.md saying the equation is still merged into
   the earlier group after the diagnostic (harmless — batch dies, the editor squiggles — but
   it is a real difference from the module path, which aborts the block).
2. **`core/examples/Lang/LetSignatures.e:20-21`**: "Every local signature below is one
   INFERENCE WOULD NOT PRODUCE" is false for four of the eleven local signatures — shapes 3
   (`widthOf`), 5 (`decorate`), 7 (`atRow`, the kind is written but the type is the inferred
   one) and `tag` in shape 9. Each of those four says so in its own comment, so the fix is
   the header sentence: "Most local signatures below are ones inference would not produce;
   four (3, 5, 7 and `tag` in 9) are the inferred type and are here for the SHAPE." LET-1-FIX.md
   §5a says "Two of the nine" — make it four.
3. **`tracker/loopmodel/LSP3-6.2-LOCALS.md:154-156`** still asserts, in the present tense,
   that a signed local is an ExplicitBinding via `NewPipeline.assemble`'s `lowerLet`/`pairSigs`
   "unlike `Lower.bindings`, which drops `SSigStatement`". Both halves are now wrong and
   `lowerLet` no longer exists. Add a dated one-line note (the file is a historical stage
   record, so amend rather than rewrite).
4. **LET-1-FIX.md §6a's `*TestLoopTrace` line ("VACUOUS on this branch")**: it is not. I ran
   it against the main checkout's binary (`-Dermine.looptrace=…/ermine-scala/tracker/lean/.lake/build/bin/looptrace`;
   the Lean sources are identical here — `diff -rq tracker/lean ../ermine-scala/tracker/lean`
   reports only `.lake`): **720 solves, 720 segments, 720 agree, 0 skipped, hashdiff 0, eqdiff 0**,
   positive control green. Replace the vacuity paragraph with that number. Also worth a
   sentence in §4d: see item 4 below on the 160-file batch.

Optional, not required: `pairSigs`' `missing definition` carries no `error:` prefix, so the
editor shows a bare "missing definition". That is the top level's existing text and the two
spellings now agree, so I would leave it.

## 1. One implementation — every semantic difference I found

I diffed the deleted `NewPipeline.collectBlock`/`pairSigs`/`lowerLet` against
`Lower.collectBlock`/`pairSigs`/`bindings` line by line. Differences, all of them:

| # | difference | effect on the module/`where` path |
|---|---|---|
| a | `case _ => ()` became `case other => throw Unsupported("statement in binding block", …)` | **none, unreachable.** `walk` builds a block only from `sts0.span(_.isInstanceOf[SEquation] \|\| _.isInstanceOf[SSigStatement])` (NewPipeline:381), and a `let`/`where` block parses `bindingStatement = sigStatement \| equationStatement` only (SurfaceParsers:789, used at :408 and :783). `SPrivateBlock` inside a block exists only in a CLASS body (`classPrivateP`, :685), and a non-empty class body is refused wholesale before lowering. In tolerant mode the throw would be a Phase.Assemble diagnostic instead of a silent skip — still unreachable. |
| b | `throw Refusal(...)` became `env.refuse(...)` | none: `NewPipeline`'s `blockEnv.refuse` throws the same `Refusal` with the same span and string, so the statements after the call site are as dead as they were. (In the `let` channel `refuse` returns, and the interleaved equation is then merged — edit 1.) |
| c | `pairSigs`' guarded block returns `Option[EB]` + `.flatten` instead of `EB` | none; `guard` is unchanged and `Some`/`None` compose identically. |
| d | `tctx.resetKindScope()` became `c.resetKindScope()` through a wired hook | none on the module path: `read` (NewPipeline:177) and `replTerm` (:245) both wire it to `() => tctx.resetKindScope()`, and `assemble` is called only from `read`. The only other `Lower.Ctx` construction sites are `TestLower:48,205`, whose fixtures contain no signature in a block (`grep "let " TestLower.scala` → two fixtures, both unsigned), so the no-op default is never reached. |
| e | **NEW: `resetKindScope` can now fire MID top-level statement**, from inside `Lower.term`, which it never did before | a theoretical difference: a module that uses one named kind-variable spelling in two annotations of ONE top-level statement, with a `let` signature between them, now gets two distinct kind variables where it used to get one. Zero shipped exposure (the three shipped `let` signatures are in `single'`, `hc'` and `median`, none of which has another annotation in the same statement), and no corpus module moved. Worth one sentence in LET-1-FIX §2. |
| f | the `let` path's binder resolution changed from `resolve(n) match { ToBinder(id) => binderV(id) … }` to `binderAtSite(n) getOrElse varFor(n)` | intended, and equal for an equation head: `Renamer.statement` records the head as an occurrence `ToBinder(id)` (:521-523) and `collectHeads` makes the FIRST equation head the def site (:198-227), so both spellings return the same memoised `V` at the same loc. A head whose binder `collectHeads` refused (the `:`-operator ledger) falls through to `varFor` on both. |
| g | group `Span` now carried in `let` blocks | new information only; nothing on the module path reads it differently. |

Grouping order (`LinkedHashMap` by spelling, alts appended, `lastEq` adjacency), the refusal
strings, the spans, `Annot.plain(i.loc, ty)`, `(im -- es.map(_.v)).values.toList`, module-wide
top-level sig pairing and `private`-block handling (`walk` recurses outside the guard,
`bindingBlock(intoPrivate)` unchanged) are otherwise byte-for-byte the same code.

## 2. The `let` refusal channel — probed in all three readers

`Lower.ctxEnv` records `Renamer.Diag` in `Ctx.diags`; `read` drains it into `Phase.Lower`
diagnostics after assemble's own, then `checkpoint()`.

* **Batch** — `shouldfail/let05`: `…let05_let_signature_no_definition.e:27:7: missing definition`,
  a positioned Death at the signature's own span. The `where` twin's text and anchor agree
  (`TestLetSignatures` pin 4 asserts both at column 9).
* **Editor** — my own LSP client (`probes/edprobe.py`, ad hoc, against
  `lsp/Main`): a file with a `let` orphan signature in statement 1 and a type error in
  statement 3 publishes **2 diagnostics**: `line 6 char 6 severity 1 "missing definition"`
  (0-based; = the `orphan` token) and the type error at line 13. `documentSymbol` still lists
  `a1 a2 a3 a4` and hover on `a2` answers `Probe.Ed1.a2 : Int`.
* **Editor, "no worse than a type error"** — the same file with the orphan replaced by a wrong
  `let` signature (2 diagnostics, same symbols) and by a plain top-level type error (2
  diagnostics, same symbols). **The let refusal costs exactly what a type error costs.**
* **REPL** — `:type (let g : Int -> Int in 1)` → `runtime error: <interactive>:1:6: missing
  definition` with the caret under `g`; `:type (let g : Int -> Int; g q = q in g "hello")` →
  `<interactive>:1:33: error: failed to unify type Int with type String`; the honest twin
  `:type (let g : a -> a; g q = q in (g 1, g True))` → `(Int, Bool)`.
* Other `pairSigs`-reachable refusals: none — `pairSigs` raises only `missing definition`.
  The block's other refusal (`interleaved equations`) is edit 1.
* Bonus (report §7.1): an unknown type in a `let` signature is now diagnosed like a top-level
  one — `BADTY.e:7:18: error: undefined type` against `BADTYTOP.e:5:12: error: undefined type`.
  No panic, no stack trace.

## 3. Kind scope — no leak, with a positive control

The mechanism is `TyLower.TCtx.kindPlaceholders`, memoised by spelling, cleared by
`resetKindScope` (TyLower:117-126). Probes (`probes/K*.e`, batch, interfaces off):

| probe | shape | result |
|---|---|---|
| `KCTL` | **control**: one spelling `k` twice in ONE signature, at `*` and at `rho` | **REJECTED** `7:37: error: failed to unify kind rho with kind *` — so a leak WOULD be visible |
| `K1` | `where w : forall (a : k). a -> Int` with a nested `let inner : forall (b : k). {..b} -> Int` | LOADED |
| `K1w` | the same thing spelled `where`-only (the a15a97e-compatible spelling) | LOADED |
| `K2` | a `let` signature using `k` (as `rho`), then a later top-level signature using `k` (as `*`) | LOADED |
| `K3` | the reverse order | LOADED |

The control makes K1-K3 meaningful: if the scope survived across a `where` signature and a
nested `let` signature, or across a `let` signature and the next top-level statement, each
would fail with the control's message. None does.

## 4. What the fix started checking — the claims reproduce

**Census, re-scanned independently.** My own scanner (nested `{- -}` and `--` stripping,
block column taken from the `let` keyword, statements at that column, signatures ON the `let`
line included — the implementer's and my first attempt both missed that form) over the 366
`.e` files of `core/src/main/resources/modules` + `core/examples`:
**20 `let`-block signature statements, of which exactly THREE are shipped** —
`Layout/Column/Unsafe.e:102`, `:113` (`unsafePres : Presentation r a -> Presentation r b`,
`= unsafeCoerce`) and `List/Util.e:37` (`m : Double`, `= getJust ' "Invalid index" ' at
midPoint sorted` inside `median : List Double -> Maybe Double`). All three read as honest:
two are the declared narrowing of `unsafeCoerce`, the third is documentation of a `Double`
the body already produces. The other 17 are in the seven new files. **Zero** shipped
`where`-in-`let` signatures: the four nested `where` signatures in the tree
(`Layout/Report.e:1153`, `Relation/Op.e:176`, `Algebra/Signatures.e:288`,
`Lang/FreeReportDsl.e:196`) all hang off a top-level equation, i.e. the module path.
Script: `review-LET1/census2.py`.

**Corpus.** Both class snapshots verified first: `snap-base/…/Lower$.class` still has
`bindings` returning `List[Nothing$]` and no `BlockEnv`; `snap-fix`'s `Lower$.class` and
`NewPipeline$.class` are **byte-identical to the current build**.

| schedule | files | base | fix | differences |
|---|---|---|---|---|
| per file (`-Dermine.useInterface=false`, same java line as `corpus-run.sh`) | **110 of 154** (sweep stopped by the orchestrator) | 60 LOADED / 50 REJECTED / 0 UNKNOWN | 60 / 50 / 0 | **0 of 110 differ** |
| `--batch`, like-for-like 154-file list | 154 | **85 / 69 / 0** | **85 / 69 / 0** | **2 of 154**: the snapshot PATH inside `sk03`/`sk05`'s message, nothing else |
| `--batch`, `corpus-run.sh` globs | 160 | 91 / 69 / 0 | 86 / 74 / 0 | the five `let0N` flip LOADED→REJECTED (the regression, on the corpus itself), the two paths, **and `mis01`** |

**The `mis01` difference is an artifact of comparing unequal file lists, not of the fix** — I
chased it because the report says "nothing else moved". In the 160-file batch,
`shouldfail/mis01_join_operands_irreconcilable.e:38:14` prints "a part contains it but the
whole does not" on the base side and "the whole contains it but no part does" on the fix side.
But the two sides are not comparable there: `let01`..`let05` LOAD on the base side and are
refused on the fix side, so the shared session state differs before `mis01` is read. Measured:
per file, both sides, twice each — the SAME clause all four times; `--batch` with the 154-file
list — the same clause on both sides. So it is session order, and the report's claim survives
(for the like-for-like comparison, which is the one that means anything).

**Interfaces.** `ei-classify.py` on the implementer's `ei-base`/`ei-fix`, re-run by me: 268
each side, none only on one side, **3474 identical / 3 alpha-equivalent / 4 order-only, 0
concrete↔polymorphic, 0 other**, 2 of 268 interfaces differing.
* `Layout/Column/Unsafe.ei :: single'` — I read both renderings in full: the only change is
  `ra`→`b` and `b`→`b1`, consistently in both of their positions. `hc'` in the same file and
  `List/Util.ei` (`median`) are **byte-identical**. G1Compare confirms: the baseline
  `tracker/g1-baseline/ei/Layout/Column/Unsafe.ei` holds the OLD names and
  `g1-validate.sh`'s drift check (`g1-diff.sh compare`) still says **no drift**, so the hard
  gate reads through the rename and needs no re-cut.
* `Relation/Predicate.ei` — the noise floor, confirmed by the implementer's same-build control
  (`LET1/ctl*-pred-*.ei`): **two boots of the UNFIXED build differ from each other** by 12
  lines (`ctlbase-pred-1` vs `ctlbase-pred-2`), while `Layout/Column/Unsafe.ei` is stable
  across boots of either build and differs across builds exactly by the rename above.
  `Relation/Predicate.e` has no local signature at all.

## 5. Pins and corpus examples

`TestLetSignatures`: **9 properties, all pass** (my run). Against brief §b: (1) all four block
shapes refused — `let`, `where`, `where`-in-`let`, `let`-in-`where`; (2) the honest polymorphic
signature at two types, plus its `where` twin; (3) the too-general signature refused;
(4) `missing definition` with BOTH the message and the anchor asserted for both spellings;
(5) the row twin as `KNOWN HOLE: a let signature with a too-weak context is ACCEPTED`, with
the sig-entail loop named in the source and the flip instruction spelled out — correctly
labelled for S3 to flip; (6) `TestTolerantCheck`'s `sigLet` twin; (7) the `TestScopes:104`
comment. Nits: pin 1's regex is only `failed to unify` and pin 3's is a four-way disjunction,
so either would accept a refusal for another reason — acceptable for a regression pin.

The seven new corpus files, run per file with interfaces off, against
`shouldfail/RESULTS.md`'s new class-7 table — **all five messages verbatim, character for
character**, and both positives load:

```
let01 …:34:6: error: failed to unify type Int with type String      let04 …:23:7: error: failed to unify type !a with type Int
let02 …:25:6: error: failed to unify type Int with type String      let05 …:27:7: missing definition
let03 …:19:17: error: failed to unify type Int with type String      control09 LOADED   Lang/LetSignatures.e LOADED
```
and `signedLocalsReport` evaluates in the REPL to exactly the report's
`(3,(7,"North"),7,80,"[North]",3,40,40,(42,"#41"))`.

**The header claim, tested on three of the nine shapes** (1 monomorphic, 2 polymorphic pair,
8 monomorphised row): one probe module with those three signatures DROPPED and each binding
used at a second type **LOADS** (so inference really gives `a -> a`, `(a,b) -> a` and the
row-polymorphic reader), and the same three uses with the declared signatures restored are
each REJECTED (`INF1/INF2/INF8`, `failed to unify`). So the claim holds for the shapes that
claim to narrow — and fails for the four that do not, which is edit 2.

`Lang/README.md` (eleven modules, thirteen `.e` files) and `RESULTS.md` (+ the control09 note,
+ the class-7 section) are the only count-bearing docs affected; `core/examples/README.md` and
`shouldfail-controls/README.md` carry no counts. `RESULTS.md`'s "40/40" headline is dated
2026-09-01 and the new section says explicitly that the rule-mode matrix does not apply to
class 7 — fair.

## 6. Editor

`TestTolerantCheck` "6.2: every LET and WHERE binder gets a type" passes with the new `sl`
assertion (`Bool -> Bool` AS DECLARED, beside `sw`); the 253-file 6.2 sweep is green with
`LetBound 165/165`, `WhereBound 92/92`. `lsp-smoke.sh` with this worktree's classpath:
**PASS, 483 checks** — the three new hovers on `Locals.e`'s signed `let` are at 0-based
(38,6), (39,6), (40,5), which I checked map to the signature, the def site and the use of
`slet` in the appended fixture (file lines 39-41); the fixture was appended, so no existing
line number moved. The `TolerantCheck.scala:323-334` comment is now true as written. The one
stale doc I found is edit 3 (`LSP3-6.2-LOCALS.md`); `docs/lsp.md` and `LSP-ROADMAP.md`'s
Decision (a) text say nothing that this change falsifies.

## 7. Gates I measured (Tier 2)

| gate | command | result |
|---|---|---|
| compile | `sbt -batch -J-Xmx3g core/compile core/copyResources` | clean, incremental, no new warnings |
| pins + scoping + stage1 | `core/testOnly *TestLetSignatures *TestScopes *TestStage1Pins` | **73 properties, 0 failed** (36 s), all 9 `Ermine let signatures` green |
| editor + REPL | `core/testOnly *TestTolerantCheck *TestTolerantRead *TestReplDifferential` | **59 properties, 0 failed** (293 s) |
| Lean loop differential | `core/testOnly *TestLoopTrace` with `-Dermine.looptrace=` the main checkout's binary | **3 properties, 0 failed; 720 solves, 720 segments, 720 agree, 0 skipped** (11 s) — the gate is NOT vacuous |
| `repl-smoke.sh` | worktree classpath | **8/8 PASS, 66 checks**, goldens byte-identical |
| `lsp-smoke.sh` | worktree classpath | **PASS, 483 checks** |
| `g1-validate.sh` | as is | **ALL GREEN, 9 checks**: 7 fixtures, double run EQUIVALENT (129 modules, 1447 signatures, 1301 normalised lines, 14 s/14 s), **no drift from `tracker/g1-baseline`** |
| corpus | see item 4 | 85/69/0 both sides over 154 (`--batch`, like-for-like); 0 of 110 differ per file |
| interfaces | `ei-classify.py` re-run | 268/268, 3474 identical, 2 interfaces differ, both accounted for |

I did not re-run the full `core/test` (the implementer's 1017/1017, 1405 s, is in
LET-1-FIX §6a and the gate policy forbids the triple-run), and I dispute none of its numbers.
`tracker/repl-classpath.txt` was regenerated from this worktree's `target/ermine-classpath`
for the three tools that read it and `git checkout`-ed back; every `.ei` I caused (129 under
`core/target/.../modules`, plus the probe dirs) is deleted — `find . -name '*.ei'` is back to
the 143 checked-in goldens. `tracker/GATE-POLICY.md` shows as modified in this worktree: that
is the orchestrator's 17:32 parallelism edit, not mine.

## 8. Landing / cherry-pick risk: **LOW, but the target has moved**

`../ermine-scala` is now **clean** (the 7.1a work the brief mentions was committed) and its
HEAD is **35f34c4**, eleven commits past `a15a97e` — LSP Stage 4 items 7.1a, 7.1b, 7.4, 7.5
and gate G4. Files in both diffs, with hunk ranges:

| file | main's hunks (a15a97e→35f34c4) | LET-1's hunks | overlap |
|---|---|---|---|
| `rename/NewPipeline.scala` | 52, 80, 88, 186 | 1, 172, 239, 272, 322, 501 | **none** (main's 186±3 vs LET-1's 172-178 — five lines apart) |
| `session/TolerantCheck.scala` | 57, 79, 487, 509, 689 | 323 | none |
| `TestTolerantCheck.scala` | 1224 | 182, 195 | none |
| `tracker/tools/lsp-client.py` | 14, 286, 413-446, 1486-1515, 2370+ | 871 | none |
| `rename/Lower.scala`, `TestScopes.scala`, `tracker/lsp-tests/Locals.e`, `Lang/README.md`, `shouldfail/RESULTS.md`, the 7 new files | untouched in main | — | none |

So the cherry-pick should apply with offsets only. Two obligations for whoever lands it:
* Stage 4 added `SurfaceCache`, `readModuleCached` and a `marks`/`surfaceCache` field on
  `Read`; all of it sits in `read`'s PARSE section, upstream of `assemble`, and LET-1's
  `lctx.resetKindScope` wiring is in the same `read` for all three paths, so the semantics
  compose. A future Stage 4 hunk in `assemble`'s block code (anchored positions,
  statement-extent reuse) WOULD collide with the shared block machinery — none exists today.
* The gates above were measured against `a15a97e`. On the merged tree at least
  `core/compile`, `*TestLetSignatures *TestTolerantCheck`, `repl-smoke.sh` and `lsp-smoke.sh`
  should be re-run, and **the lsp-smoke check count will be main's own plus 3, not 483** —
  main has added checks to `lsp-client.py` since. Do not read 483 as the post-landing number.
