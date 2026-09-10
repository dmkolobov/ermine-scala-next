# LSP Stage 3, item 6.4 — document symbols and workspace symbols: REVIEW

Independent review of the implementer's uncommitted deliverables for `tracker/LSP-ROADMAP.md` § Stage 3,
item 6.4.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.4-review.md`; implementer's brief
`brief-LSP3-6.4.md`; implementer's report `LSP3-6.4-SYMBOLS.md`.  Branch `scala3-migration`, HEAD
`001fb43` plus the uncommitted tree.  I edited nothing but this file and my scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.4/`.
No commits.  One JVM at a time throughout; `.ei` count 0 before and after every run.

## VERDICT: FIX-THEN-ADVANCE

The item does what it says.  Every gate the implementer reported reproduces on my re-run, number for
number, including the two that carry the weight — the corpus symbol-tree property (0 malformed of 8159)
and the group/`moduleTerms` cross-check (3441 = 3441, 0 files disagreeing).  Both requests answer purely
from stored results; I read both handlers and there is no path from either to a parse, a rename, a check
or an inference.  The two places where the implementer contradicted the brief (§7a `Relation` is a
Scala-installed builtin; §7b a `foreign` declaration is not a term group) are both right, and both were
called out rather than worked around.

What holds it back from a clean ADVANCE is one inaccurate claim about ranges and the design question
sitting underneath it.  The report (§2c) says "Half-open, so siblings abut and do not overlap".  That is
false for two ordinary Ermine idioms, and it is false 171 times in the real corpus.  Nothing spec-illegal
follows, and the outline LIST renders correctly; what misrenders is every client feature that maps a
cursor to a symbol (breadcrumbs, sticky scroll, outline follow-cursor).  The fix list below is small.

### FIX BEFORE ADVANCE

1. **Correct §2c and `docs/lsp.md`** to say that a group's `range` may span a neighbouring group's, name
   the two idioms that do it (F1), and state which of the brief's two remedies is being taken or
   deliberately deferred.  A claim that a reviewer can falsify in 171 places must not stand in the report
   of record.
2. **Assert sortedness in the corpus property** (F3).  It holds — 0 unsorted levels over 358 files — and
   costs one line.  If sibling non-overlap is deliberately NOT asserted, say so next to it.
3. **Drop `private`/`database` Namespace containers from `workspace/symbol`** (F4), the same way imports
   and the `foreign` block are dropped: they are containers, not declarations.  One `filterNot`, and the
   empty-query smoke check should assert it.
4. **State the cross-container group case** (F2) in the report — the outline it produces contradicts
   itself, and it is currently undocumented rather than decided.

Everything else below is INFO or a pre-existing ticket.

---

## 1. Findings

| id | severity | status | one line |
|---|---|---|---|
| F1 | MEDIUM | CONFIRMED | Sibling ranges straddle for two common idioms — 171 pairs in 21 corpus files — and the report says they cannot. |
| F2 | MEDIUM | CONFIRMED | A group whose signature and equations straddle a `private` block yields an empty namespace beside a symbol whose name lives inside it. |
| F3 | LOW | CONFIRMED | The corpus property asserts neither sortedness (which holds) nor sibling non-overlap (which does not); the brief asked for both. |
| F4 | LOW | CONFIRMED | `private` and `database` container symbols leak into `workspace/symbol` results. |
| F5 | LOW | CONFIRMED (inherited) | Stdlib workspace hits point at `core/target/.../classes/modules/*.e`, the build-output copy, not the source. |
| F6 | INFO | CONFIRMED | "A query during boot answers `[]` and never waits" is true only before `initialized`; after it, the request queues behind the 12 s load. |
| F7 | INFO | CONFIRMED | The once-only session-list build (41 ms, 2157 `File.isFile` stats) sits inside the first request and is not itself gated. |
| F8 | INFO | CONFIRMED | `where`/`let`/`do` bindings are not symbols — correct, but stated nowhere. |

### F1 — MEDIUM — sibling ranges straddle; §2c says they cannot

The merge rule groups a spelling's statements across the WHOLE binding scope, not across adjacent
statements (`Symbols.scala`, `scopeSymbols`/`Grp`, `groups.getOrElseUpdate(spelling, …)`), and a group's
`range` is the union of those statements' spans.  So whenever another group's statement sits between a
group's first and last statement, the two ranges nest.  Two ordinary idioms do exactly that:

* **A block of signatures followed by a block of equations.**  `core/src/main/resources/modules/Layout/Column.e`
  lines 25–32 inside its `private` block gives `unsafeCol` 25–29, `unsafeFCol` 26–30,
  `unsafePhantomCol` 27–31, `unsafePhantomColK` 28–32 — a perfect staircase of nested siblings.
* **A multi-name signature whose equations are on separate lines.**  `Function.e`'s
  `($), ($!) : (a -> b) -> a -> b` gives `$` 36–37 and `$!` 36–38; `Layout/Format.e`'s
  `round, roundParens : …` the same.  The implementer's own fixture is in this class:
  `Syms.e` pins `symBoth` (18,0)–(19,11) and `symAlsoBoth` (18,0)–(20,15), which nest — and §2c
  describes that very pair as "siblings abut and do not overlap".

I measured it with the builder directly (scratch `Overlap.scala`, `Symbols.build` over stdlib +
`core/examples` + fixtures, no session): **358 files parsed, 9066 symbols, 171 straddling sibling pairs
in 21 files**, plus 2018 identical-range pairs (the multi-name `field`/`sig` case §2c does describe
correctly) and **0 unsorted levels**.  `Layout/Report.e`, the largest file at 511 symbols, has 0 straddles,
so this is idiom-specific, not universal.

**Is it a client problem?**  The LSP spec requires only that `range` contain `selectionRange` and that a
child sit inside its parent; it does not forbid sibling overlap.  Both required properties hold — verified
over 8159 symbols by the shipped property and 9066 by mine, 0 malformed.  The outline TREE is taken from
the `children` field, not re-derived from ranges, so the outline list itself is correct and correctly
ordered.  What `range` drives in a client is cursor→symbol lookup: breadcrumbs, sticky scroll, and the
outline's follow-cursor all walk siblings in order and take the first whose range contains the position.
On the Column.e staircase, a cursor on `unsafeFCol`'s own signature line resolves to `unsafeCol`; the
same on `unsafePhantomCol`'s and `unsafePhantomColK`'s.  Equation lines happen to resolve correctly,
because the ends increase in the same order as the starts.  So: renders sanely as a LIST, misattributes
signature lines in the breadcrumb.  That is a quality defect, not a correctness break, which is why this
is MEDIUM and not a BLOCK.

The brief named the two remedies: split the group, or set the range to the equations' extent only.  A
third — clamp a group's range to the maximal contiguous run of its own statements containing the
selection — keeps the adjacent sig+equation case the pins depend on (`Decls.e`'s `useAlias` 20–21) and
removes both straddling idioms.  That is a design call for the implementer; the review asks only that the
report stop asserting the opposite of what ships.

### F2 — MEDIUM — a group that straddles a `private` block contradicts its own outline

Probe (ii) of the review brief.  `private` blocks share the module's binding scope — `Renamer.collectHeads`
flattens them, which is exactly what makes the 3441 = 3441 cross-check work — but the symbol builder emits
a group in the container its FIRST statement stands in (`Grp.owner`, set on first sight of the spelling).
The two disagree whenever a group's statements cross the boundary.  Live, through the server
(scratch `fx/ProbeScope.e`, **0 diagnostics** — this is legal Ermine):

```
module ProbeScope where            privDef   k=13  r=(2,0)-(5,13)  sel=(5,2)-(5,9)
                                   private   k=3   r=(4,0)-(6,0)   sel=(4,0)-(4,7)
privDef : Int                      -- ^ an EMPTY namespace, beside a top-level symbol
                                   --   whose selectionRange is inside that namespace
private
  privDef = 1
```

The mirror cases, measured on the builder (scratch `Edge.scala`):

* equation inside `private` first, signature at top level after → `privDef` becomes a CHILD of the
  namespace and the namespace's range is stretched past its own block to cover the top-level signature;
* a group split across two `private` blocks → the first namespace's range is stretched over the second
  namespace entirely.

Containment is never violated (`Symbols.build`'s `sym` unions each parent over its children), so nothing
is spec-illegal — the nesting is simply wrong, and an empty `private` folder is a visible artefact.  I
found no instance of the cross-container shape in 358 corpus files, so the severity is bounded by rarity.
It is not mentioned in the report or in `docs/lsp.md`.

### F3 — LOW — the corpus property does not assert sortedness or non-overlap

`TestRenamer`'s "6.4 corpus: a symbol tree for every file, every range well formed" asserts non-empty
names, `range` ⊇ `selectionRange`, and child ⊆ parent.  The review brief asked whether it also asserts
that symbols are sorted by position and that sibling ranges do not overlap.  It asserts neither.
Sortedness **holds** — 0 unsorted levels over 358 files, measured independently — so the assertion is free
and should be added; sibling non-overlap does not hold (F1), and the report does not record that the
question was asked and answered.

### F4 — LOW — `private`/`database` containers leak into workspace results

`Symbols.install`'s `workspace/symbol` handler drops open-document symbols with `kind == KModule` (2),
which correctly removes imports and the `foreign` block container.  Nothing removes the `private` and
`database` containers (`KNamespace`, 3).  Observed live: with `ProbeScope.e` open, the empty query
returned 23 results, one of them `{"name": "private", "kind": 3}`.  A `private` block declares nothing,
exactly like an import.  The smoke's empty-query check asserts only the absence of kind 2, so it does not
see this.

### F5 — LOW, INHERITED — stdlib hits point at the build output, not the source

With no buffer open, `workspace/symbol "not"` answers

```
file:///home/dmitry/research/ermine/ermine-scala/core/target/scala-3.3.8/classes/modules/Bool.e  line 19
```

— the `copyResources` copy, not `core/src/main/resources/modules/Bool.e`.  That is where the resident
session loads its modules from, and `textDocument/definition` has answered the same path since 6.1: the
existing pin is `r["uri"].endswith("/Bool.e")`, which cannot tell the two apart.  **Not a 6.4 regression.**
But 6.4 is what makes it matter: browsing the stdlib is the point of workspace symbols, and a user who
edits the file they land in loses the edit at the next `copyResources`.  The 6.4 smoke's own assertions
(`endswith("/modules/Relation.e")`, `endswith("/modules/Relation/Sort.e")`) are the same shape, so they
would not notice a fix either.  Worth a ticket in its own right, not a 6.4 fix.

### F6 / F7 / F8 — INFO

* **F6.** There is no `Thread` or `Executor` anywhere under `lsp/`; dispatch is single-threaded.  A
  `workspace/symbol` sent before `initialized` answers `[]` (I measured 8.3 ms); one sent after
  `initialized` queues behind the ~12 s module load.  The report says exactly this in §4 and the smoke
  pins the before-`initialized` pair.  Recording it because "a query during boot never waits" is a
  narrower claim than it sounds.
* **F7.** The session name list is built inside the FIRST query: 41 ms on my run (2157 globals; the
  implementer measured 36–37 ms), which is 2157 `File.isFile` stats — not a parse or an inference, but
  filesystem IO on a request path.  End-to-end first query 42.8 ms; warm 0.40–0.64 ms.  Under the 50 ms
  bar, but the smoke's cost check is best-of-five taken AFTER the build, so the first-query cost is
  logged and not gated.  Acceptable as shipped.
* **F8.** `whereTop x = helper x where helper y = y` yields exactly one symbol (probe (vi)) — correct,
  the brief asked only for top-level groups — but neither the report nor `docs/lsp.md` says that
  `where`/`let`/`do` binders are deliberately not nested, and a hierarchical outline is exactly where a
  reader would look for them.

## 2. What I probed and what it answered

### 2a. The merge rule and the kind mapping (review brief §1)

All through the running server unless noted (`scratch/fx/*.e`, scratch `probe.py`; the builder directly
for shapes a check cannot reach).

| probe | result |
|---|---|
| (i) a sig with two names, equations for both | two symbols, each selecting its OWN equation head, both starting at the sig (`Syms.e` `symBoth` (18,0)–(19,11) / `symAlsoBoth` (18,0)–(20,15)) — correct, and F1 |
| (i′) two names, only one defined | `sigA` Variable 13 sel at its equation; `sigB` sig-only Function 12 with the sig's own range; the missing definition still gets its diagnostic |
| (ii) sig at top level, equations inside `private` | ONE scope (the renamer flattens; 0 diagnostics) but the tree disagrees — see **F2** |
| (iii) `(<^>) x y = …` with `infixl 6 <^>` | one symbol `<^>`, Function 12, no fixity symbol; `detail` = `forall a. Num a => a -> a -> a  infixl 6` — correct |
| (iv) `data Color = Color Int` | `Color` Struct 23 with exactly ONE `Color` Constructor 9 child; no duplicate at top level — correct |
| (v) `data MixedD = MNull \| MFull Int` | Struct 23 (mixed); `data OneNull = ONull` → Enum 10 — the rule is "every constructor nullary", as stated |
| (vi) `where` bindings | not symbols — correct, undocumented (**F8**) |
| (vii) a broken statement mid-file | `ProbeErr.e`: 1 diagnostic, no symbol for `badOne`, `beforeErr` (2,0)–(2,13) and `afterErr` (6,0)–(7,0) both listed at their true extents — nothing swallowed |
| (viii) containment / sorting / sibling overlap | containment holds by construction and is asserted (0 malformed of 8159 shipped, 9066 mine); sorting holds (0 violations) but is unasserted (**F3**); siblings DO overlap (**F1**) |
| class body vs top level | `class Cls a where dup : a -> a` beside a top-level `dup x = x` → Method 6 inside Interface 11, Function 12 at top level, `moduleTerms` has one `dup` — the scope split is right |

### 2b. Workspace symbols (review brief §2)

| probe | result |
|---|---|
| a query during boot | `[]` in 8.3 ms, sent before `initialized`; never null (**F6** for the caveat) |
| a stdlib module OPENED | `not` in container `Bool` collapses to one entry at the buffer's uri — dedupe by (module, name) works |
| …then EDITED | after a didChange inserting 3 lines and appending `reviewerProbeSym`, the `Bool.not` entry follows to line 22 and `reviewerProbeSym` appears at line 34 — the entry tracks the buffer, not the session |
| a re-export (`not`) | exactly two entries, `Bool` at `Bool.e:19` and `Relation.Predicate` at `Predicate.e:72` — one per definition site, no Prelude duplicate |
| `Relation` the type is a Builtin | absent from results (§7a is right — `Type.scala:615` `mkCon[AnyRef](Global("Builtin","Relation"), rho ->: star)`), while `SoftRelation` and `relation` are present |
| substring `elation` | 15 results: `SoftRelation`, `relation`, `relationWithHeader`, `fromRelation`, `softRelation`, `scanRelation`, `nonEmptyRelation`, the `_Relation` instance names — the substring path is unharmed by the builtin's absence |
| the 200 cap on `"a"` | 200 of 1071, **byte-identical across three consecutive calls**; 93 prefix-tier entries first (`abs`…), then substring matches in lowercased-name order truncated at `cons_Bracket`.  "Which 200" = all prefix matches plus the alphabetically first substring matches — total, stable, and consistent with the stated ranking |
| `not` vs `Not` | `q = query.toLowerCase` compared against a precomputed `s.lower`, so the two are the same query; nothing named exactly `Not` exists in the corpus |
| cost | list build 41 ms / 2157 globals; first query 42.8 ms end to end; warm `relation` 0.40–0.64 ms over six calls.  Matches the report (36 ms, 0.21–1.27 ms) |
| leakage | `private` containers appear (**F4**) |
| location target | build-output copy (**F5**) |

### 2c. The request-path rule (review brief §3)

Read both handlers.  `textDocument/documentSymbol` is `docs index uri` followed by a JSON render —
nothing else.  `workspace/symbol` is `Symbols.flatten` over stored trees, a `String.contains` per entry,
plus `sessionGlobals`, which is built once and whose only work is `Definitions.location` (a
`java.io.File.isFile` and a JSON object).  `Pretty.prettyType` runs in the request, which is the same
thing hover has done since 6.2 — a printer, not an analysis.  No parse, rename, check or inference is
reachable from either handler; there is no thread anywhere under `lsp/`, so single-threaded dispatch is
intact and the batch path is untouched (nothing outside `lsp/` changed in `core/src/main`).

**`Resident.Checked` did NOT grow** — `Resident.scala` gained only `loadedEnv`, a read-only accessor on
the existing `booted`.  What grew is `Definitions.DocIndex`, by one field: `symbols: List[Symbols.Sym]`,
511 `Sym` for `Layout/Report.e`.  Each `Sym` holds a `Type` reference that `TolerantCheck.types` already
retains, so the added retention is the node objects themselves.  The list is built ON the check path, in
`Definitions.index`, and I measured the consequence directly (below): the whole index build, symbols
included, is 12–18 ms of a ~1.6 s round trip.

## 3. Gate table — implementer vs mine

Every row re-run once by me on the final tree, one JVM at a time, load average under 2 at the start of
each timed run.

| gate | implementer | mine | |
|---|---|---|---|
| `sbt core/compile core/copyResources` | green | green (incremental no-op; class files at 05:16:12 are newer than every source, latest 05:16:05) | ✓ |
| `core/testOnly *TestLoopTrace` | 720 solves / 720 segments / 720 agree; hashdiff 0, eqdiff 0, nonpart 0, fuel 0 | identical, 3 properties passed | ✓ |
| `core/testOnly *TestTolerantRead *TestTolerantCheck *TestEditorBuffers *TestRenamer *TestReplDifferential` | 71/71, TestRenamer 27 | 71/71, 0 failed, 0 errors; TestRenamer 27 (ran twice, identical) | ✓ |
| 6.4 corpus symbol property | `files 252 \| symbols 8159 \| Class 225, Constructor 161, Enum 6, Field 1431, Function 1841, Module 2050, Namespace 181, Property 166, Struct 103, Variable 1995` | identical, string for string | ✓ |
| 6.4 group cross-check | `files 252 \| term groups 3441 \| moduleTerms 3441` | identical | ✓ |
| 6.3 lines unchanged | `occurrences 71248 \| exact 70897 \| backticked 39 \| parenthesised 306 \| behind a tab 6 \| other 0` | identical | ✓ |
| `corpus-run.sh --batch` | 85 / 69 / 0 over 154 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** | ✓ |
| `repl-smoke.sh` | 8 groups / 66 checks, goldens unmodified | 8 groups / 66 checks (2+5+9+12+6+4+23+5); `git status tracker/repl-tests` clean | ✓ |
| `lsp-smoke.sh` | 338 (306 + 32) | **PASS lsp (338 checks)**; 6.3's baseline of 306 confirmed in `LSP3-6.3-REFS.md` | ✓ |
| boot | 129 modules in 11.9 s | `session: ready — 129 modules in 11.8s` | ✓ |
| `.ei` | 0 | 0, checked after every JVM | ✓ |
| `git diff --stat` vs `--stat -w` | identical | identical (7 files, 466 insertions, 11 deletions) | ✓ |
| nothing outside `lsp/` in `core/src/main` | claimed | confirmed — the four modified `core/src/main` files are all under `.../ermine/lsp/` | ✓ |
| workspace-symbol cost | build 36 ms / 2157; queries 0.21–1.27 ms; first 37.8 ms | build 41 ms / 2157; warm 0.40–0.64 ms; first 42.8 ms | ✓ |
| `Report.e` index build | 7980 occurrences, 511 symbols, 13.8–14.0 ms warm | 7980 occurrences, 511 symbols, 54.2 cold / 17.6 / 14.4 / **12.3** ms | ✓ |
| `Report.e` round trip | 1.24–1.30 s warm before, 1.26–1.30 s after | 2.20 s cold, **1.76 / 1.61 / 1.64 s** warm | see note |

**Note on the round trip.**  My warm figure is ~25 % above the implementer's.  I did not run a matching
BEFORE (that is an A/B, and `tracker/GATE-POLICY.md` reserves interleaved A/B for adoption), so I cannot
attribute the difference, and my run followed a heavy corpus + `repl-smoke` sequence on the same machine.
The attribution question is settled by arithmetic instead: the only thing 6.4 adds to the check path is
the symbol walk inside `Definitions.index`, the whole of which — occurrences AND symbols — measures
12–18 ms warm, about **1 %** of a 1.6 s round trip, and the occurrence count is unchanged at 7980, which
says 6.3's half of the index was not disturbed.  The implementer's §1a claim that the round trip does not
move is not contradicted by anything I measured.

## 4. The report itself (review brief §5)

Accurate against my numbers everywhere I could check, with one exception.

* **§7a, `Relation` is a Scala-installed builtin — RIGHT CALL.**  Verified at `Type.scala:615`:
  `mkCon[AnyRef](Global("Builtin", "Relation"), rho ->: star)`, `Loc.builtin`, no `.e` declaration in the
  129 modules.  Listing it would mean inventing a position, and it is in exactly the class the brief's
  next clause asks be absent (`Just`).  Substituting `SoftRelation` + `relation` + a positive absence
  assertion, and adding `"sortorder"` as a second, cleaner case, is the right repair; I confirmed all
  three live, and that the substring query `elation` still returns 15 names.
* **§7b, a `foreign` declaration is not a term group — RIGHT CALL.**  `Renamer.collectHeads` walks
  signatures and equations only; taking the brief's sentence literally gave 3836 Function/Variable
  symbols against 3441 `moduleTerms`.  Comparing `Symbols.termGroups` (a function on the builder, not a
  restatement of the rule in the test) is a refinement, not a weakening: the alternative would have been
  to mis-kind foreign declarations to make an arithmetic identity come out.  It is exact, 3441 = 3441,
  0 files disagreeing, which I reproduced.
* **§2c is wrong** where it says "Half-open, so siblings abut and do not overlap" — F1, 171 counterexamples,
  including the report's own `symBoth`/`symAlsoBoth` example.  Fix 1 above.
* **Gaps stated?**  §7c is candid about what is inherited (tab-expanded columns / E8), what is pinned by
  a parser-only property rather than a fixture (`class`, `table`, `database`), and what is a deliberate
  plain choice (`Class 5` over `TypeParameter 26`, the name-range Location, the never-invalidated session
  list).  Missing from it: the cross-container group case (F2), `where` binders (F8), the `private`
  container leak (F4), and the sortedness/overlap question (F3).

## 5. Runs, in order

1. `sbt -batch -J-Xmx3g core/compile core/copyResources` — green, incremental no-op; class timestamps checked.
2. `scala-cli` scratch `Overlap.scala` over 358 corpus files (no session) — sortedness and sibling-overlap census.  Twice: once raw, once classifying identical-range vs straddling.
3. `scala-cli` scratch `Edge.scala` — six hand-built shapes through `Symbols.build` + `Renamer.rename`.
4. `java … lsp.Main` under scratch `probe.py` — 6 probe fixtures + 14 workspace queries, one server.
5. `sbt -batch 'core/testOnly *TestLoopTrace'` — 720/720/720.
6. `sbt -batch 'core/testOnly *TestTolerantRead *TestTolerantCheck *TestEditorBuffers *TestRenamer *TestReplDifferential'` — 71/71; run a second time to read the `Prop.collect` lines, identical.
7. `tracker/tools/corpus-run.sh --batch <scratch>/corpus` + `corpus-verdicts.py` — 85/69/0 over 154.
8. `tracker/tools/repl-smoke.sh` — 8 groups / 66 checks, goldens clean.
9. `tracker/tools/lsp-smoke.sh` — 338 checks, boot 129 in 11.8 s.
10. `java … lsp.Main` under scratch `report.py` — `Layout/Report.e` cold + 3 warm round trips, index line, and a straddle census of its 511-symbol tree (0 straddles).

`.ei` count checked after 4, 7, 8, 9 and 10: **0** outside `tracker/g1-*` every time.  Working tree at the
end carries exactly the implementer's changes plus this file.

---

# Second pass — the fix round

Reviewed against the updated `LSP3-6.4-SYMBOLS.md` (§2c and its new **THE RANGE RULE** section, §5's
new property, §7c.8–10, §7d), the new `Symbols.overlaps`/`beforeSym`/`Hit`/`Grp` code, the reworked
`TestRenamer` property, `lsp-client.py`, the new fixture `tracker/lsp-tests/Scope.e`, the edited
`Syms.e` pin, and `docs/lsp.md`.  Same rules: nothing edited but this file and my scratch directory,
one JVM at a time, no commits, `.ei` 0 at the end.

## VERDICT: ADVANCE

F1, F2, F3, F4 and F8 are closed, and closed properly — the range rule is a real rule with a stated
giveaway rather than a patch, the property calls the builder's own predicates instead of restating
them, and F5 is filed as a ticket with cause, impact, two fix options and its own gate (§7d).  My
independent census, using my own strict predicates rather than `Symbols.overlaps`, agrees with the
shipped numbers: **0 straddling sibling pairs over 358 files and 9066 symbols, down from 171 in 21
files; 0 unsorted levels.**  Every gate is green, and the pre-existing `Decls.e` pin is byte-identical
to the first round.

One nit to fold into the next commit, not worth holding the item for:

* **S1** — §2c and the new property's comment both name `symBoth, symAlsoBoth : Int` as a producer of
  identical sibling ranges.  The fix itself made that false; the item's own pin now reads
  `symBoth` (18,0)–(19,11) and `symAlsoBoth` (20,0)–(20,15), which are disjoint.  `docs/lsp.md` gets
  it right (`field fa, fb : Int` only).  Correct the two stale citations.

## Findings (second pass)

| id | severity | status | one line |
|---|---|---|---|
| S1 | LOW | CONFIRMED | §2c and the property's comment still cite `symBoth, symAlsoBoth` as an identical-range example; the fix made it false, and every identical pair in my census is `Field`/`Field`. |
| S2 | INFO | CONFIRMED | The disclosed giveaway is "a separated SIG belongs to no symbol"; the rule actually drops any statement outside the anchor's run — but a dropped EQUATION is unreachable in legal code (the checker refuses interleaved equations), and all 16 corpus orphan heads are signatures. |
| S3 | INFO | CONFIRMED | F2's mirror (equation at top level, signature inside `private`) still yields an empty `private` namespace — correct here, unlike the original F2, but undocumented. |
| S4 | INFO | CONFIRMED | A fixity declaration between a signature and its equation breaks the run and drops the signature; legal, absent from the corpus, follows from the rule. |
| S5 | — | POSITIVE | Side effect worth knowing: the outline of the separated-sig idiom now sorts by the equations, not by the signature block. |

### S1 — the identical-range example is now stale

`Symbols.overlaps` is strict, so the property must classify overlapping-but-not-identical (fail) from
identical (count).  1824 identical pairs are reported over 252 files; my census over 358 files finds
2018, and **every single one is `Field`/`Field`** — a multi-name `field fa, fb : Int` statement, one
symbol per name over one statement span.  The multi-name SIGNATURE case that §2c and the test comment
cite no longer produces identical ranges, because the run rule now splits it: `adjA, adjB : Int` with
`adjA = 1` and `adjB = 2` gives `adjA` the sig plus its own equation and `adjB` its equation alone
(measured on the builder), and the shipped `Syms.e` pin shows exactly that.  The construction that
DOES still produce identical Function ranges is a multi-name signature with **no** equations —
`noEqA, noEqB : Int` gives two Function 12 symbols over one span — of which the corpus has zero
instances.  Fix the two citations; the claim itself ("no two siblings overlap unless identical") is
sound and now asserted.

**Are identical sibling ranges fine for clients?**  Yes.  The spec forbids nothing here; the outline
list is built from `children`, so both names are listed and both are selectable, and a jump uses
`selectionRange`, which differs.  The only consequence is that a cursor→symbol lookup on that one line
returns the first of the pair — and the cursor really is inside both, because they share the statement.
That is a categorically different thing from the staircase F1 described, where a cursor sat inside a
symbol whose statement it had nothing to do with.

### S2 — the giveaway is slightly wider than stated, and harmlessly so

The rule keeps the maximal contiguous run of the group's own statements, in the container the SELECTION
stands in, containing that selection — and the selection is the first equation.  So anything of the
group outside that run is dropped, signature or not.  I probed three separated runs live:

```
three : Int        line 3   -> covered by NOTHING
sep   = 0          line 4   -> sep
three = 1          line 5   -> three     <- the range, the run around the FIRST equation
other = 2          line 6   -> other
three = 3          line 7   -> covered by NOTHING     <- an EQUATION with no symbol
```

But the file is not legal: the server answers `error: interleaved equations for three`.  So a dropped
equation is only reachable in a file that is already diagnosed, and the corpus bears that out — of
**6146 group statement heads in 358 files, 16 lie inside no symbol's range, and all 16 are signatures**
(`Layout/Legend.e`, `Layout/Presentation.e`, `Layout/Options.e`, `Syntax.e`, `Layout/SortPriority.e`,
`Layout/Magnitude.e`), zero equations.  0.26 % of heads, exactly the class §2c owns up to.  Suggest
widening the sentence from "a separated sig" to "any statement outside the run", and noting that an
equation can only be outside it in a file the checker already rejects.

### S3 / S4 — the shapes the fix does not change

* **Mirror of F2** (`mirror = 1` at top level, `mirror : Int` inside a `private` block — legal, one
  `moduleTerms` entry): the symbol is emitted at top level where its equation is, and the `private`
  block renders as an EMPTY namespace whose only statement is that signature.  This is not the original
  F2 pathology: there is no contradiction, because the symbol's `selectionRange` is where the symbol is
  emitted.  The block is empty because a signature belonging to a group defined elsewhere never gets a
  symbol of its own.  Correct, and worth one sentence somewhere.  The related shape — one group with
  equations in TWO containers — behaves the same way (one symbol at the anchor's container; the other
  container's equation covered only by the namespace) and, given the interleaved-equations diagnostic
  above, is almost certainly rejected by the checker too; I did not confirm that live.
* **A fixity line between a signature and its equation** (`(<%>) : …` / `infixl 6 <%>` / `(<%>) a b = a`)
  breaks contiguity, so the range is the equation alone and the signature line belongs to no symbol.
  Legal Ermine, absent from the corpus, and a direct consequence of the stated rule rather than a
  surprise.

### S5 — a positive side effect

Because the range now starts at the equations rather than at a distant signature, sibling ORDER changes
for the separated-sig idiom: my first-round repro `ProbeSep.e` used to list `sepA` (whose range began at
its signature on line 2) before `other` on line 4; it now lists `other` first and `sepA` at its
definition.  An outline of `Layout/Column.e`'s four `unsafe*` helpers now orders them by where they are
defined.  That is the better answer and it was not claimed, so it is recorded here.

## What I verified, item by item

| the coordinator's question | answer |
|---|---|
| independent straddle census | my own strict predicates over 358 files / 9066 symbols: **0 straddling pairs, 0 unsorted levels** (first round: 171 pairs in 21 files).  Shipped property, 252 files: 8411 sibling levels, 1824 identical pairs, **0 straddling** |
| abuttal semantics, once | `Syms.e` pins `private` (22,0)–(26,0) immediately followed by `foreign` (26,0)–(31,0) — they share an endpoint.  `Symbols.overlaps` uses `strictlyBefore` on BOTH endpoints, so that is an abuttal; a non-strict predicate would report it as an overlap, so the strictness is load-bearing and not decoration.  My census used an independently written strict predicate and agrees over the whole corpus |
| pins unchanged where nothing is separated | the `Decls.e` full-tree pin is **byte-identical** to the first round, `useAlias` (20,0)–(21,19) and `useEither` (22,0)–(24,0) included — those are adjacent sig+equation groups and the run rule keeps them whole.  `Syms.e` changed in exactly one place, `symAlsoBoth` (18,0)–(20,15) → (20,0)–(20,15), which is the fix |
| a group with THREE separated runs | range = the run around the FIRST EQUATION (the selection); the other run is in no symbol — see **S2**, and the file is diagnosed `error: interleaved equations` |
| are the other equations reachable? | by name, yes — one symbol, one `moduleTerms` entry, and 6.3's references/highlight still find every occurrence.  By RANGE, no: that line is inside no symbol.  Only reachable in an already-rejected file |
| F2 mirror: equation top, sig in `private` | legal; symbol at top level, empty `private` namespace — correct, not the original pathology (**S3**) |
| F2: equations in TWO containers | one symbol in the anchor's container; the other container's equation covered only by its namespace (**S3**) |
| F2 forward case, live | `Scope.e`: `private` (11,0)–(14,0) with `hidden` (12,2) and `helper` (13,2) as CHILDREN, and the top-level `hidden : Int` on line 9 in no symbol — exactly as §2c claims.  My first-round repro `ProbeScope.e` now shows `privDef` as a child of `private`; the empty-namespace-plus-outside-symbol shape is gone |
| F3: the property is not a restatement | it calls `Symbols.beforeSym` and `Symbols.overlaps`, the builder's own predicates, and counts identical ranges rather than failing them.  Both are new public functions on `Symbols` with their own scaladoc |
| F3: what are the 1824 identical pairs? | multi-name `field` statements, exclusively — see **S1** — and they are fine for clients |
| F4: Namespace filtered | `ownDecls` now filters `KModule \|\| KNamespace`.  Live: `workspace/symbol "private"` → `[]`; `"hidden"` and `"helper"` still return the declarations INSIDE the private block (container `Scope`); the empty query returns 10 results, kinds `[13]` only, no kind 3 |
| F8 | §7c.8 and `docs/lsp.md` now say `where`/`let`/`do` binders are deliberately not symbols and why |
| F5 | §7d, a full ticket: cause (classpath load + `copyResources`), impact, two fix options, scope, gate, and the observation that the existing `endswith` pins cannot see the fix |
| F6 / F7 | §7c.9 and §7c.10, both stating the limit of the claim rather than the claim |

## Gate table (second pass)

| gate | expected | mine |
|---|---|---|
| `sbt core/compile core/copyResources` | green | green; `Symbols.scala` 05:54:16 → `Symbols$.class` 05:54:24 |
| `core/testOnly *TestLoopTrace` | 720/720/720 | 720 solves / 720 segments / **720 agree**; hashdiff 0, eqdiff 0, nonpart 0, fuel 0; 3 properties |
| five targeted suites | 72/72, TestRenamer 28 | **72 passed, 0 failed, 0 errors**; TestRenamer properties counted: **28** |
| new sibling property | 0 straddling | `files 252 \| sibling levels 8411 \| identical-range pairs 1824 \| straddling pairs 0` |
| symbol totals unmoved by the range change | — | `files 252 \| symbols 8159 \| Class 225, Constructor 161, Enum 6, Field 1431, Function 1841, Module 2050, Namespace 181, Property 166, Struct 103, Variable 1995` — identical to the first round, so the rule changed ranges and not symbol identity |
| group cross-check | 3441 = 3441 | `files 252 \| term groups 3441 \| moduleTerms 3441` |
| 6.3 occurrence line | unchanged | `occurrences 71248 \| exact 70897 \| backticked 39 \| parenthesised 306 \| behind a tab 6 \| other 0` |
| `lsp-smoke.sh` | 344 | **PASS lsp (344 checks)** |
| boot | 129 | `session: ready — 129 modules in 11.7s` |
| `repl-smoke.sh` | 8 / 66, goldens clean | 8 groups / 66 checks; `git status tracker/repl-tests` clean |
| `.ei` | 0 | 0 |
| `git diff --stat` vs `--stat -w` | identical | identical (7 files, 578 insertions, 11 deletions) |
| nothing outside `lsp/` in `core/src/main` | — | confirmed; the new fixture is `tracker/lsp-tests/Scope.e` |
| `corpus-run.sh --batch` | 85/69/0 | **not re-run.**  Nothing outside `core/src/main/.../lsp/` has changed since the first pass, where I measured 85 LOADED / 69 REJECTED / 0 UNKNOWN over 154; the compiler cannot see this diff |

Runs, in order: compile; `scala-cli Census2.scala` (independent straddle / identical-range / orphan-head
census, twice — the second run classifying orphans as sig vs equation); `scala-cli Edge2.scala` (eight
edge shapes through `Symbols.build` + `Renamer.rename`); `java … lsp.Main` under scratch `probe2.py`
(`Scope.e`, three-run, `ProbeSep.e`, `ProbeScope.e`, four workspace queries); `TestLoopTrace`; the five
suites (twice — the second run only to count `TestRenamer`'s properties, identical output); `lsp-smoke.sh`;
`repl-smoke.sh`.  `.ei` checked after each; **0** throughout.
