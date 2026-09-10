# LSP Stage 3, item 6.6 — quick fixes: INDEPENDENT REVIEW

Reviewer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.6-review.md`; implementer's report
`tracker/loopmodel/LSP3-6.6-QUICKFIX.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.6
with Decision (e); gates `tracker/GATE-POLICY.md`.  Branch `scala3-migration`, HEAD `45941de`
("Brief LSP3-6.6 review") plus the uncommitted deliverables.  No commits, no edits outside
`/tmp/…/scratchpad/review-6.6/` and this file.  One JVM at a time throughout; every `.ei` count
checked, none created.

**VERDICT: FIX-THEN-ADVANCE.**  Every gate reproduces, every number of the sweep reproduces to the
digit, and every rule row of both actions applies live through a scripted client and re-checks
clean.  No edit this item can emit is wrong.  What needs fixing is the RECORD: the largest refusal
class (117 of 168) is explained wrongly in both the report and `docs/lsp.md`, and the printer
ticket's item (2) cites two examples that belong to its item (1) — the ticket is what the next
implementer works from.  One latent one-line code hole (`fieldInScope`) and one mis-wired
unreachable path go with it.  List in §5.

---

## 0. Tier 0 scope, and the tree

* `git diff --stat` and `git diff --stat -w` are **IDENTICAL** (8 files, 709 insertions,
  21 deletions) — no file reformatted.
* Nothing outside `core/src/main/scala/…/lsp/` changed under `core/src/main`.  Confirmed by
  `git diff --stat`: the five modified `lsp/*.scala` plus the new `lsp/QuickFix.scala`.  No
  `Subst`, `Type`, `Pretty`, `Lower`, `TolerantCheck`, `Renamer`, `NewPipeline`.  **Tier 0.**
* `tracker/repl-classpath.txt` is **CLEAN in this tree** — `git status --porcelain
  tracker/repl-classpath.txt` prints nothing, last touched by `956ebf5`.  The brief's premise is
  stale (the implementer regenerated and reverted it, or never wrote it back); there is no content
  change to judge, cosmetic or real.
* `tracker/LSP-ROADMAP.md` and `tracker/lean/` untouched.  `tracker/loopmodel/briefs/
  brief-LSP3-6.7.md` is untracked and not this item's (the implementer says so).

## 1. THE SWEEP — reproduced, then interrogated

Re-run once, one JVM, load average 0.56 at launch:

```
sbt -batch -J-Xmx3g -Dermine.sweep.quickfix=true 'core/compile' 'core/copyResources' \
    'core/testOnly *TestTolerantCheck'          # 176 s, 27/27 passed
```

| | implementer | **reviewer** |
|---|---|---|
| files found | 253 | **253** |
| files excluded | 4 | **4** |
| unsigned top-level groups | 1334 | **1334** |
| insertions OFFERED | 1166 | **1166** |
| CLEAN | 1164 (99.83 %) | **1164 (99.83 %)** |
| PARSE-FAIL | 0 | **0** |
| TYPE-FAIL | 2 | **2** (`Validation.e` `empty_Bracket`, `cons_Bracket`) |
| SKIPPED | 168 | **168** — out of scope 117, free kind 36, `* ->` 10, `<:_Type.Cast` 2, field 3 |
| import-scanner disagreements | 0 over 249 | **0** |
| pairs equal only under the complete comparator | 6 | **6** |

**Reproduced independently, through the WIRE.**  I then re-derived the whole SKIPPED table a second
way, without the test: a scripted client that opens all 253 corpus files one at a time against the
live server, fires one `codeAction`, and reads the refusal reason the handler logs per group.
Subtracting the one file opened twice (`Layout/Report.e`, also used for the latency probe) and the
four broken files, the live census is **out of scope 117, free kind 36, star arrow 10, unlexable 2,
field identity 3 — 168**, identical bucket by bucket.  The sweep grades exactly what the shipped
handler refuses.  (Scratch: `probe2.log`, attribution script in the run record.)

### 1a. The 4 excluded files — NAMED (the report does not name them)

Identified live; all four have a non-silent check of their own, so nothing can be attributed:

| file | why |
|---|---|
| `core/examples/Interp.e` | `unknown operator ==` → ill-formed expression → error node, 2 undefined terms, 5 unchecked |
| `core/examples/Sample.e` | `panic: trailing virtual semicolon` |
| `core/examples/Yahoo.e` | 2 undefined terms, 13 unchecked |
| `core/examples/guide/HelloWorld.e` | a parse error and 1 undefined term |

These are the SAME four the 6.2 sweep excludes ("249 clean modules of 253", printed again on this
run).  The exclusion is right; the report should name them.

### 1b. (a) Is the complete comparator SOUND?

Read against `tools/G1Compare.scala`.  The sweep's `aeq` is the LazyList (all-bijections) version of
`G1Compare.alphaEq`, case for case; `sameTy` takes `strict || loose`, so CLEAN needs only the loose
one.  Verdict:

* **It does NOT accept the case the brief worries about.**  A `Forall`'s binders are matched
  POSITIONALLY (`f1.ts.map(_.id).zip(f2.ts.map(_.id))`), so "which of two same-kinded variables is
  which" is fixed by binder order and a swap is rejected unless every occurrence swaps with it.
  The only order-insensitive matching is `Part.rhs` and `Exists.constraints`, both genuinely
  order-insensitive in this row theory (`t <- (s, r)` and `t <- (r, s)` denote the same partition;
  an existential's binder order is not semantic).  `ConcreteRho` compares field lists by `Global`
  identity and `Type.Con` by full `Global` — both strict.
* **The implementer's completeness claim is accurate.**  `G1Compare.matchMultiset` already
  backtracks over which element of `cs2` to pair with; its incompleteness is one level DOWN — the
  single `Option[Bij]` that a nested `alphaEq` returns commits to one bijection when several exist.
  `aeq` returns all of them lazily, so it is the nondeterministic version of the same relation and
  is therefore strictly more permissive.  **6 pairs** needed it, reproduced.
* **ONE genuine over-acceptance, inherited not introduced (R-5, LOW).**  Neither comparator ever
  compares KINDS: `alphaEq`'s `Forall` case zips `ks` into `kv` and never calls `kindEq`, and the
  sweep's copy does the same.  Two types differing only in a binder's kind compare equal.  So §5's
  "alpha-equivalent" should read "alpha-equivalent UP TO KINDS".  The residual risk is narrow —
  CLEAN also requires a diagnostic-free re-check, and a kind that actually moved almost always draws
  one — but it is the one thing the criterion cannot see.

### 1c. (b) The 2 TYPE-FAILs: wrong types, or unfolded aliases?

**Unfolded aliases.  The inserted signature is CORRECT in both cases.**  `core/src/main/resources/
modules/Validation.e:16` is `type Err = (String, String)`.  The offered line writes the ALIAS
(`… Either (List Err) (Record (||))`); after the declaration the group's stored type renders the
EXPANSION (`… Either (List (String, String)) …`), so the comparator sees `Type.Con(Validation.Err)`
against a product and says unequal.  An alias is definitionally equal to its expansion, and the
re-check has ZERO diagnostics on both files, so the action is SAFE on those two — and the line it
offers is the more abstract of the two renderings, which is the better signature.  Under the honest
reading the corpus is **1166 / 1166 = 100 %**; under the literal criterion 99.83 %.  Both are above
the 95 % bar and the report says so.

One clarification the report owes (R-6): the sweep labels these two `type moved: concrete row (|…|)`
and `type moved: row constraint (<-)`.  Those are `shape()` buckets of the inserted TEXT, not
diagnoses — `cons_Bracket`'s text happens to contain `<-` and `empty_Bracket`'s contains `(|`.
Read as a reason, "row constraint" wrongly suggests a row-order failure.

### 1d. (c) The 117 "out of scope" — spot-checked, and the label is WRONG (R-1, MEDIUM)

I attributed all 117 to a (file, type name) pair from the live log and checked five classes by hand.
The report (§5a) and `docs/lsp.md` both say "the file genuinely does not import the type, and the
signature would not parse".  That is true of almost none of them.  Three sub-classes:

| sub-class | n | evidence |
|---|---|---|
| **the file's OWN type synonym already makes the name resolve — a FALSE NEGATIVE** | **31** | `Layout/Scan.e` declares `type Scan = Scan_S` and `type Legend = Legend_Lg`; 29 groups are refused for naming `Scan` and 2 for `Legend`.  PROOF: appending `probeScan : forall z a. Scan z a -> Scan z a` / `probeScan x = x` to `Layout/Scan.e` and re-checking gives **0 diagnostics**.  `inScope` chases `consOrigins`, which does not relate a synonym to the `Con` it expands to, so the identity test says no where the grammar says yes. |
| **the module IS imported, under an ALIAS** | most of the rest | `Layout/Scan.e`: `import Layout.Report as L`, `import Vector as V`, `import Layout.Column as C`, `import Layout.Presentation as P` → 8 `Report`, 3 `Vector`, 4 `Column`, … `Layout/Chart/Unsafe.e`: `import Native.Map as NM` → the report's own headline example (`axisChartData#`, "the type names Map") is an ALIASED import, not a missing one.  Likewise `Layout/Validation.e` (`import Validation as V` → `Err`), `Present/ValidationReport.e` (`import Map as M`), `Present/VarianceStyling.e` (`import Layout.Presentation as Pres`).  CONTROL: `Vector` and `Report` written bare in `Layout/Scan.e` both draw `undefined type`, so the REFUSAL is right — the reason is that only the affix spelling `Report_L` resolves and `Pretty` writes the bare name, i.e. **the ticket's own item (3)**, not a missing import. |
| **the type cannot be written at all** | **31** | `ErasedMagnitude` is `private data` in `Native/Magnitude.e` — 27 groups in `Layout/Report.e`, 4 in `Present/StyleGridHeatmap.e`.  No import exists that would help. |

**Could the action have qualified the name or added an import instead of skipping?**  For the
aliased class it could in principle write the affix form — that is exactly what 6.5's completion
does — but the affix form has to come out of the PRINTER, and making `ppType` honour `Qualification`
is a `Pretty.scala` change, i.e. Tier 1.  For the private class nothing helps.  For the synonym
class no edit is needed at all; the test is simply too strict.  **Skipping is the right call for
6.6** and the report states it — but §9 item 4's "an action that ALSO added the missing import would
serve them" is true of hardly any of the 117, and that sentence will send the next item down a
wrong road.

### 1e. (d) `FieldIdentity`: is the own-field exemption sound?  (R-3, LOW)

Not quite.  A field's `Global` is `Global(declaringModule + "." + name, name)` — the report's own
`Algebra.Deduplication.customerId` / `customerId` confirms the shape.  So the EXACT own-field test is
`g.module == ownModule + "." + g.string`.  What is implemented is

```scala
g.module == ownModule || g.module.startsWith(ownModule + ".") || scope.get(…).exists(_.contains(g))
```

and `startsWith` also exempts every field declared in a DESCENDANT module.  46 corpus modules import
a submodule of themselves (`Relation` ← `Relation.Op`, `Layout` ← `Layout.Report`, `Field` ←
`Field.Type`, `Native` ← 14 of them, …), so a re-exported field reached that way would skip the
strict test and could produce exactly the `(|Count, customerId|)` non-unification the test exists to
catch.  The corpus does not exercise it (1164/1166 clean, 3 refusals all `Count` in `Deduplication`
/ `ManagerChains`), so this is latent, not live.  The 450-insertion measurement behind the exemption
is sound as far as it goes — the strict test genuinely refuses own fields, because a module's own
names are not in `canonicalTerms` — but the exemption should be spelled exactly.  One line.

## 2. ADD IMPORT — every rule row applied LIVE and re-checked

Own fixtures in the scratch directory, driven through the real server with the edit APPLIED as a
client would apply it and the buffer re-checked.  **35/35 probes green** (`probe.py`, `probe1.out`).

| row | fixture | offered | applied edit | re-check |
|---|---|---|---|---|
| `using` list, BRACED | `import Maybe using { isJust; maybe }` | `add isNothing to the Maybe import list` | `(2,34)+"; isNothing"` → `{ isJust; maybe; isNothing }` | **clean** |
| `using` list, LAID OUT over lines | `import Maybe using` / `  isJust` / `  maybe` | same title | `(4,7)+"; isNothing"` → `  maybe; isNothing` | **clean** |
| `hiding` list of THREE, name in the MIDDLE | `import Function hiding flip; id; const` | `stop hiding id from Function` | delete `(2,27)-(2,31)` → `hiding flip; const` — one separator, exactly | **clean** |
| `hiding` list of ONE | (smoke, `Fix.e`) | `stop hiding id from Function` | the whole clause | clean |
| ALIASED | `import Bool as B`, undefined `not` | **no Bool action**; `import Relation.Predicate using not` still offered | — | — |
| OPEN | `import Bool`, `f = not True` | **no diagnostic at all** — the row is vacuous by construction | — | — |
| two candidates | (smoke) `Bool` + `Relation.Predicate` | two actions, `isPreferred` on neither | — | clean |
| one candidate | scratch sibling | one action, `isPreferred` true | — | **clean** |
| the 6.5 pinned gap | (smoke) `import Maybe using isJust` + `isNothing` | `add isNothing to the Maybe import list` | `; isNothing` | clean |
| CRLF | (smoke, `FixCrlf.e`) | import line ends `\r\n` | — | clean |
| open sibling, **never saved** | a buffer whose `neverSaved` exists only after a `didChange` | `import P7Sib using neverSaved`, preferred | new line | **clean** |

**The 6.5 negative pin was UPDATED, NOT DELETED.**  `git diff tracker/tools/lsp-client.py` contains
**zero deleted lines** — the whole change is +47 checks.  Block (10d) still asserts "completion: THE
STATED GAP — an existing `using` list is not extended", which remains TRUE: 6.6 does not change
completion's `additionalTextEdits`; it closes the gap with a code action, pinned separately in the
new block (6).  That is the right way round.

**The Prelude question (R-8, LOW).**  Candidates collapse through `termNameOrigins` to the origin,
so `import Prelude using isJust` + an undefined `not` offers `import Bool using not` and
`import Relation.Predicate using not` and **never** `add not to the Prelude import list` — the
one-word edit, on a module the file already imports, which would have worked.  Verified live (P5.e);
both offered edits do apply and re-check clean, so nothing is broken, but the smaller edit is not on
the menu.  The open-import row itself really does yield "none": with `import Bool` open there is no
diagnostic to fix (POpen.e, 0 diagnostics), so the row can only ever be reached through an already
in-scope name.  This limitation is defended in §3(a) but is not listed in §9; it should be.

**R-9 (LOW).**  The handler calls `addImport(d.text, idx.moduleName, m, s, Idfix)` — the fixity is
hardcoded (`QuickFix.scala:852`).  So even if an undefined OPERATOR ever reached this path (it
cannot: it is a read-phase `Diag` with no spelling), `written("++", Idfix)` yields `` `​`++`​` ``, not
`(++)`.  §3's "the machinery is there" is true of `written` and not of its only caller.

## 3. ADD SIGNATURE — edge cases and "add all"

All live on scratch fixture `P6.e`, applied and re-checked:

| edge case | result |
|---|---|
| operator head `(+++) a b = a` | `add signature: (+++) : forall a b. a -> b -> a`, inserted at (2,0) |
| BACKTICK head `` (`) a f = f a `` | `` (`) : forall a b. a -> (a -> b) -> b `` — `SName.form = ParenOp`, one backtick, exactly what the source wrote |
| head inside `private` | `  hiddenOne : Int` at (9,0) — indented WITH the equation, so it stays in the block |
| first equation preceded by a COMMENT line | `commented : Int` lands BETWEEN the comment and the equation, not above the comment |
| nullary equation | `answer = 42` → `answer : Int` (smoke), `commented = 1` → `commented : Int` |
| already signed | no action (smoke, `signed`) |
| staleness (index version ≠ buffer version) | `[]`, then answers once the check lands (smoke, both ways) |
| **"add all missing signatures (4)"** | 4 insertions, lines **[11, 9, 6, 2] descending**, applied → **re-checks CLEAN**, and no action remains |

**Is the staleness rule too strict?**  It is coarser than it needs to be and the report says so
(§9 item 8): the import edits are computed from the CURRENT buffer and would be safe.  In practice
the menu is empty only between a keystroke and the ~300 ms debounce, and a user opening the
lightbulb has stopped typing; the cost is a menu that is briefly empty rather than an edit at a line
that moved.  Stated, defensible, and pinned both ways.  I would leave it.

## 4. REQUEST PATH and cost — re-measured on Report.e

**Nothing parses or checks on the request path.**  Read line by line: the handler reads `d.text`
lexically (`imports`, `linesOf`, `eolOf`), the already-parsed `idx.module`, `idx.types`,
`idx.scopeTerms/scopeTypes`, `idx.termOrigins/typeOrigins`, and `d.diags`.  The only compute is
`Pretty.prettyType` per unsigned group, which is rendering.  Dispatch is single-threaded by
construction (`Rpc.ready` polls a quiet stream instead of using a second thread), so the unlocked
`var memo` is safe and `putIndex`/`putDiags`/`codeAction` cannot interleave.

| | implementer | **reviewer** (load 0.85–0.90) |
|---|---|---|
| first `codeAction` after a check, `Layout/Report.e` | 51 ms | **37.7 ms** |
| every request after | 0.1–0.4 ms | **0.3–0.7 ms** |
| actions returned | — | **119** (118 signature + 1 source) |

**What the first request computes:** every unsigned group's signature edit for the whole file —
which is what the `source` action's N needs — memoised on `(uri, version)`.  Report.e is the
worst case in the corpus by a wide margin (154 unsigned groups).

**R-4 (LOW).**  §1c says "36 groups on Report.e, most of them refused".  Live, Report.e answers
119 actions and logs **36 refusals**, so it has ~154 unsigned groups of which most are OFFERED.
The 36 is the refusal count, not the group count, and "most of them refused" is backwards.

**Report.e check round trip**, my machine, load 0.85, this tree only (I cannot re-run the BEFORE side
without stashing, which the brief forbids): **cold 1.97 s, warm 1.80 / 1.64 / 1.64 s**.  That sits
inside the implementer's AFTER band (1.39–2.48 s) and is much tighter than it, which supports the
implementer's own explanation of the spread ("load average 1.8–4.5 throughout: a game running").
The A/B conclusion "unmoved" is therefore not contradicted, but it is not independently confirmed
either — four stored references cannot cost anything, and that is the argument I am relying on.

## 5. THE PRINTER TICKET — three of four shapes reproduced verbatim

| ticket shape | reproduction |
|---|---|
| **(1) nested `* ->` loses its parentheses** | **CONFIRMED exactly.**  `data A (a: rho -> *)`, `(a: rho -> (* -> *))` and `(a: rho -> rho -> *)` all check clean; `(a: rho -> * -> *)` and `(a: * -> * -> *)` both fail with `expected '=', '{', eof, identifier, kinded binder, or whitespace`.  The failing element is exactly an `ArrowK` whose right operand is an `ArrowK` with `*` on the left, as the ticket says. |
| **(2) an `exists` binder's kind names an unquantified kind var** | Count reproduced (36 in the sweep, 36 live).  **But the ticket's two named examples are wrong** — see R-2. |
| **(3) `n_Module` regardless of `Qualification`** | **CONFIRMED exactly.**  `probe : Throwable <:_Type.Cast Object` draws `unknown type operator <:_Type`, then `unknown type operator .`, then `ill-formed expression` — the three diagnostics the ticket quotes. |
| **(4) a concrete row's field `Global`s do not round-trip** | **CONFIRMED exactly.**  Hover on `Algebra/Deduplication.e`'s `supersededCount` gives `Mem (|Count, customerId|)`; hand-inserting that very line yields `failed to unify type (|Count, customerId|) with type (|Count, customerId|)`.  And the ticket is right that this one is not the printer. |

**Correctly NOT fixed here.**  All four are `Pretty.scala` (or unification), a shared printer whose
output feeds `.ei` bytes and the G1 differential — Tier 1 under the Stage-3 invariant, which the
item is required to stop at and say so.  It does.

**R-2 (LOW).**  §7 item (2) gives `Relation/Op.e`'s `cons_Bracket` and `Syntax/Procedure.e`'s
`functionArg` as its examples.  Live, the server refuses BOTH under item (1): the log says "the
printer drops the parentheses a nested `* ->` kind needs" for `functionArg`, and for `negate`,
`dateRange`, `cons_Bracket` and `growthOf10k` in `Relation/Op.e`.  `functionArg`'s actual rendering
is `forall (a: rho -> * -> *) (b: rho) c. AsOp a => a b c -> FunctionArg` — no `exists`, no free kind
variable.  The genuine item-(2) examples are `Relation/Aggregate.e`'s `avg` (which
`QuickFix.freeKinds`'s own doc comment uses) and `Layout/Report/Relation.e`'s
`cutoffGroupedFldsPosNegRel'` (which the sweep prints).  Worth one more sentence too: `sigEdit`
tests `freeKinds` BEFORE `starArrow`, so a group carrying both lands in the FreeKind bucket, and the
two counts are not independent.

## 6. GATES — re-run once each, one JVM at a time

| gate | implementer | **reviewer** |
|---|---|---|
| `sbt core/compile core/copyResources` | green | **green** (the one pre-existing `NewPipeline.scala:361` deprecation) |
| `core/testOnly *TestLoopTrace` | 720/720/720, hashdiff 0 | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, fuel 0, skipped 0, rejected 36; 3 properties |
| `core/testOnly *TestQuickFix *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestRenamer*` | 94/94 | **94 / 94, 0 failed, 0 errors** — QuickFix **18**, TolerantCheck **27**, TolerantRead 11, EditorBuffers 6, Renamer 32 |
| the 6.6 sweep (`-Dermine.sweep.quickfix=true`) | 1166 / 1164 (99.83 %) | **identical, every number** (§1) |
| `corpus-run.sh --batch` | 85 / 69 / 0 over 154 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**, 154 outputs |
| `repl-smoke.sh` | 8 groups / 66 checks, goldens unmodified | **8 groups / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` **clean** |
| `lsp-smoke.sh` | 454 (407 + 47) | **454**; the +47 counted off the diff, and the diff has **zero deleted lines** |
| boot | 129 modules | **129** (asserted by the smoke, and again by every probe of mine) |
| `.ei` | 0 | **0** — nothing newer than the session start anywhere outside `target/`, `tracker/lsp-tests` clean |
| line endings | `--stat` == `--stat -w` | **identical** |
| codeAction cost, Report.e | 51 ms then 0.1–0.4 ms | **37.7 ms then 0.3–0.7 ms** |
| Report.e round trip | AFTER 1.39–2.48 s | **1.97 / 1.80 / 1.64 / 1.64 s** at load 0.85 — inside the band, and much tighter (§4) |

The +47 smoke checks by fixture: `Fix.e` 34 (signature single/all/refusal, the five import rows, the
`only` filter, staleness both ways, cost, on-disk unchanged), `FixCrlf.e` 6, `FixSib.e` 2, `FixTy.e`
0 direct (it exists so `Fix.e`'s `peek` can name an unimported type), capability + before-boot 2,
plus 3 shared clean/revert pins.

Not run, and rightly: Tier 1 (no solver, no `Type`/`Subst` construction, no Lean), Tier 2 (`core/test`
in full — not an adoption commit), no perf A/B (nothing enters inference; the §1b check-path pair is
the measurement this item owes and I re-measured its AFTER side).

## 7. FINDINGS

| id | severity | status | finding |
|---|---|---|---|
| **R-1** | MEDIUM | **CONFIRMED** | The largest refusal class is explained wrongly.  `OutOfScope` = 117 of 168 skips, and the report (§5a) and `docs/lsp.md` both say "the file genuinely does not import the type, and the signature would not parse".  Attributing all 117 live and probing five: **31 name a type the file DOES resolve, through its own type synonym** (`Layout/Scan.e`: `type Scan = Scan_S`, `type Legend = Legend_Lg`; appending `probeScan : forall z a. Scan z a -> Scan z a` there checks with **0 diagnostics**) — those are conservative FALSE NEGATIVES of `inScope`'s identity test, which chases `consOrigins` and cannot see through a synonym; **31 name a type that cannot be written at all** (`ErasedMagnitude` is `private data` in `Native/Magnitude.e` — 27 in `Report.e`, 4 in `StyleGridHeatmap.e`); and **most of the rest name a type the file DOES import, under an ALIAS** (`import Layout.Report as L`, `import Native.Map as NM` — including the report's own headline example `axisChartData#`/`Map`), where only the affix spelling resolves and the printer writes the bare name, i.e. the ticket's item (3).  Controls: `Vector` and `Report` written bare in `Layout/Scan.e` both draw `undefined type`, so the refusals themselves are right.  The action never emits a bad line — this is an accuracy defect, but it is in the item's central correctness narrative, and §9 item 4's "an action that ALSO added the missing import would serve them" is true of hardly any of the 117. |
| **R-2** | LOW | **CONFIRMED** | The printer ticket's item (2) cites two examples that belong to its item (1).  §7(2) names `Relation/Op.e`'s `cons_Bracket` and `Syntax/Procedure.e`'s `functionArg`; the live server refuses both as `StarArrow` ("the printer drops the parentheses a nested `* ->` kind needs"), and `functionArg` renders `forall (a: rho -> * -> *) (b: rho) c. AsOp a => a b c -> FunctionArg` — no `exists`, no free kind variable.  The real item-(2) examples are `Relation/Aggregate.e`'s `avg` and `Layout/Report/Relation.e`'s `cutoffGroupedFldsPosNegRel'`.  The ticket is what the next implementer works from, so the examples have to point at the shape they claim. |
| **R-3** | LOW | **CONFIRMED** | `fieldInScope`'s own-field exemption is broader than "own field": `g.module.startsWith(ownModule + ".")` exempts every field declared in a DESCENDANT module, where the exact own-field shape is `g.module == ownModule + "." + g.string`.  46 corpus modules import a submodule of themselves, so a field re-exported that way would skip the strict identity test and could produce exactly the `(|Count, customerId|)` non-unification the test exists to catch.  Latent — the corpus does not reach it — and a one-line fix. |
| **R-4** | LOW | **CONFIRMED** | §1c's "36 groups on Report.e, most of them refused" is backwards: Report.e answers **119** actions (118 signature + 1 source) and logs **36 refusals**, so it has ~154 unsigned groups of which most are OFFERED.  The first-request cost is real either way (37.7 ms here, 51 ms there). |
| **R-5** | LOW | **CONFIRMED** | Neither `G1Compare.alphaEq` nor the sweep's complete `aeq` ever compares KINDS — the `Forall` case zips `ks` into the bijection and never calls `kindEq` — so two types differing only in a binder's kind compare equal.  Inherited from the gate tool, not introduced, and the implementer's "strictly more permissive, agrees wherever G1Compare succeeds" is accurate.  §5 should say "alpha-equivalent UP TO KINDS"; it is the one thing the CLEAN criterion cannot see, bounded by the fact that CLEAN also requires a diagnostic-free re-check. |
| **R-6** | LOW | **CONFIRMED** | The 2 TYPE-FAILs are unfolded ALIASES and the inserted signatures are CORRECT (`Validation.e:16` is `type Err = (String, String)`; the re-check is silent on both).  The comparator sees the alias `Con` against its expansion.  The sweep's labels for them (`type moved: concrete row (|…|)` / `row constraint (<-)`) are `shape()` buckets of the inserted TEXT, not reasons, and "row constraint" reads like a row-order failure that did not happen.  Honest reading: 1166/1166. |
| **R-7** | LOW | **CONFIRMED** | The report does not name the 4 excluded files.  They are `core/examples/Interp.e`, `Sample.e`, `Yahoo.e` and `guide/HelloWorld.e`, all genuinely broken, and the same four the 6.2 sweep excludes (§1a). |
| **R-8** | LOW | **CONFIRMED** | Candidates collapse to the ORIGIN, so a re-exporter the file ALREADY imports with a `using` list is never offered: `import Prelude using isJust` + undefined `not` offers `import Bool using not` and `import Relation.Predicate using not`, never `add not to the Prelude import list`.  Both offered edits apply and re-check clean, so nothing is broken — but the smallest correct edit is off the menu.  Defended in §3(a); belongs in §9 as a stated limitation. |
| **R-9** | LOW | **CONFIRMED** | The one caller of `addImport` hardcodes `Idfix` (`QuickFix.scala:852`), so the operator path would write `` `​`++`​` `` rather than `(++)` even if it were reachable.  §3's "the machinery is there" is true of `written`, not of its caller.  Unreachable today (an unknown operator is a read-phase `Diag` with no spelling), so cosmetic. |
| **R-10** | INFO | **CONFIRMED** | Two stale bits in `QuickFix.scala`: the `imports` doc says a statement containing a `{- -}` "is scanned for its module and alias but never EDITED", which nothing implements and nothing needs (comments are blanked before the brace matcher runs); and `SkipOpaque` is unreachable (`insert` is `Some` whenever `isUsing` is defined, and the `None` case is taken by `SkipOpen` first). |

Nothing REFUTED.  No finding is a wrong edit: every rule row, every signature edge case and every
"add all" I applied through the wire re-checked clean, and the two sweep failures are correct
signatures graded by a comparator that cannot fold an alias.

## 8. FIX-THEN-ADVANCE — the list

Required before the item is ticked:

1. **R-1** — rewrite the `OutOfScope` explanation in `LSP3-6.6-QUICKFIX.md` §5a/§9(4) and in
   `docs/lsp.md` with the three sub-classes and their counts (own synonym 31 / unnameable 31 /
   aliased import, the remainder).  Note that 31 of them are refusals of signatures that WOULD have
   checked, and that no add-import action can serve the other two classes.
2. **R-2** — correct the printer ticket's item (2) examples to `Relation/Aggregate.e` `avg` and
   `Layout/Report/Relation.e` `cutoffGroupedFldsPosNegRel'`, and record that `freeKinds` is tested
   before `starArrow` so the two counts are not independent.
3. **R-3** — tighten `fieldInScope` to the exact own-field shape
   (`g.module == ownModule + "." + g.string`), and re-run the sweep to show the number does not move.
4. **R-7** — name the 4 excluded files in the sweep table.
5. **R-8** — add the "a re-exporter already imported with a list is never offered" limitation to §9.

Optional and cosmetic: **R-4**, **R-5** (one word in §5: "up to kinds"), **R-6**, **R-9**, **R-10**.

Nothing here blocks.  With items 1–5 the record matches what the code does, and the code is right.

---

### Run record (all one JVM at a time; scratch `/tmp/…/scratchpad/review-6.6/`)

| # | run | load at launch | result |
|---|---|---|---|
| 1 | `sbt … -Dermine.sweep.quickfix=true core/compile core/copyResources 'core/testOnly *TestTolerantCheck'` | 0.56 | 176 s, 27/27, sweep reproduced (`sweep1.log`) |
| 2 | `probe.py` — the rule table + signature edge cases + Report.e cost | 0.50 | 35/35 (`probe1.out`, `probe1.log`) |
| 3 | `probe.py --corpus` — all 253 files opened live, refusals logged | 0.69 | 62 s, 4 files not clean, SKIPPED table re-derived (`probe2.out`, `probe2.log`) |
| 4 | `probe3.py` — hand-inserted signatures for two refused groups | 0.79 | control established (`probe3.out`) |
| 5 | `probe4.py` — is `Scan`/`Legend`/`Vector`/`Report` writable in `Layout/Scan.e`? | 0.74 | `Scan` yes (0 diag), `Vector`/`Report` no |
| 6 | `sbt 'core/testOnly *TestQuickFix *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestRenamer*' 'core/testOnly *TestLoopTrace'` | 0.70 | 94/94 and 720/720 (`gates1.log`) |
| 7 | `corpus-run.sh --batch` | 2.00 | 85/69/0 of 154 (`corpus.log`) |
| 8 | `repl-smoke.sh` | 1.82 | 8 groups / 66 checks (`replsmoke.log`) |
| 9 | `lsp-smoke.sh` | 2.26 | 454 checks (`lspsmoke.log`) |
| 10 | `probe5.py` — printer ticket shapes (1) and (3) | 0.90 | both reproduced verbatim |
| 11 | `probe6.py` — ticket (4) + Report.e round trip | 0.85 | (4) reproduced verbatim; 1.97 / 1.80 / 1.64 / 1.64 s |
| 12 | `probe7.py` — the ticket's item-(2) examples | — | both are item (1) — R-2 |

No background JVMs, no polling shells left behind, no `.ei` created, no commits, nothing written
into the repository except this file.
