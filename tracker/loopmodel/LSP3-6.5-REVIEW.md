# LSP Stage 3, item 6.5 — completion: INDEPENDENT REVIEW

Reviewer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.5-review.md`; implementer report
`tracker/loopmodel/LSP3-6.5-COMPLETION.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.5
(STAGE-3 INVARIANTS, Decision (c)); gates `tracker/GATE-POLICY.md`.  Branch `scala3-migration`, HEAD
`46f88e1` + the uncommitted deliverables, reviewed exactly as found.  No commits; nothing edited
except this file and my scratch directory
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.5/`.
One JVM at a time throughout; no background JVMs; `.ei` outside `tracker/g1-*` = 0 after every run;
`git status` at the end is byte-for-byte what it was at the start.

## VERDICT: **FIX-THEN-ADVANCE**

Every gate re-ran green at my hands, at the implementer's numbers, and the two `Renamer.scala` fixes
are correct — I checked them on eleven synthetic frame shapes and, independently of the shipped
property, in the REVERSE direction over the whole corpus (0 of 35 920).  Three things must land
before the commit, all of them **report/docs accuracy, no code**:

1. **R-1**: §4 and §11.3's claim that qualified completion is "correct and useful for a TYPE position
   … and for a qualified CONSTRUCTOR" is REFUTED by measurement.  It is correct for NOTHING in this
   fork.  Restate.
2. **R-2**: the gate table omits `*TestLower`, which the Stage-3 invariant (`tracker/LSP-ROADMAP.md`
   line 647) requires of any item touching `Renamer`.  I ran it: green.  Add the row.
3. **R-3**: `docs/lsp.md` never states the line-local comment/string gap, and never states the
   comment/string → `[]` rule at all.  The report states both; the docs are what the invariant says
   must carry the staleness/limits statement.  Add two sentences.

Nothing here is a defect in the shipped code and nothing blocks: the code is the code the gates
passed on.

---

## 1. THE SHARED FILE: is `rename/Renamer.scala` on the strict batch path?

**The tier does NOT grow.  Batch is frozen BY CONSTRUCTION, and the corpus/REPL/TestLoopTrace
results are CONFIRMATION, not proof.**  Established from the code, not from the gates:

* `Renamer.Result.frames` has exactly **two** readers in the whole tree: `Result.scopeAt`
  (`Renamer.scala:96`) and `TestRenamer.scala:622` (the new anti-vacuity counter).  Grep over
  `core/src/main` for `\bframes\b` returns only `Renamer.scala` itself, `Completion.scala:242`
  (a comment) and an unrelated `SqlEmitter` message; `Lower.scala`, `TyLower.scala` and
  `NewPipeline.scala` — the batch consumers of a `Renamer.Result` (`NewPipeline.scala:145`
  `Renamer.rename`) — never mention it.
* `scopeAt` has exactly **two** production callers, both under `lsp/`: `Completion.scala:247` and
  `References.scala:377` (6.3's rename-capture refusal).  Plus `TestRenamer.scala:117-118,589`.
* The renamer's own resolution does NOT go through `frames`.  `reference` →
  `lookup(env, n.spelling)` (`Renamer.scala:370`) reads the `Env`, a `List[Map[String,Int]]` that
  `term`/`statement` push and pop by hand and `collectFirst` reads innermost-first.  `s.frames` is a
  write-only side table on that walk.
* The do-binder edit is exactly that shape: `case SDo(_, stmts)` became `case SDo(dloc, stmts)`
  (naming a field that was already matched) and the `Frame(...)` it appends got a wider span.
  `cur = b :: cur` — the line resolution actually uses — is untouched, character for character.
* `Result.scopeAt` is a pure query on an already-built `Result`; its fold direction cannot reach a
  caller that does not call it.

So: no Tier 1.  The tier is Tier 0 **plus** the Renamer-touching suites the roadmap names, which is
`*TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestRenamer *TestLower` — see R-2.

## 2. Are the two fixes right?

### 2a. Fold direction, on every frame shape

The sort key is `(startLine - endLine, startCol - endCol)`, ascending, and the fold is now `foldLeft`
with `acc ++ f.bindings`.  For two frames A ⊇ B that both contain a position, `A.startLine ≤
B.startLine` and `A.endLine ≥ B.endLine` give `A.key1 ≤ B.key1`, and a tie in `key1` under nesting
forces both line pairs equal, so `key2` decides by the same argument on columns — and a tie in BOTH
forces the spans equal.  Frames containing one position are always nested (a frame is a lexical
scope), so **outermost-first is exact, and the innermost `++` wins**.  Equal spans fall to `sortBy`'s
stability, i.e. insertion order into the `List.newBuilder`, which is outer-first everywhere frames
are appended (module frame at `:245` before any statement; arg frame `:526` before where frame
`:535` before the body walk).

Checked, not argued, on eleven shapes (scratch `probe/`, `probe2/`; log `run-C-probe.log`,
`run-D-probe2.log`).  Every occurrence's `scopeAt` answer was compared to the binder the renamer
actually resolved it to, **and** the reverse (does `scopeAt` claim a local where the renamer used a
top level or left the name free):

| shape | result |
|---|---|
| `let` in `\λ` in a `case` alt in a `where` in an equation, **every binder spelled `x`** | all 4 nested frames + the two top levels agree, innermost wins at each depth |
| two sibling `let` frames on ONE line (`(let a=1 in a) + (let a=2 in a)`) | each `a` gets its own binder; no cross-talk |
| **a frame whose span equals its parent's** — the arg frame and the where frame of one equation are both `Frame(st.loc.span, …)` | where wins, which is what `lookup` does (`env3 = whB :: argB :: env`).  This case is real and the stable sort is load-bearing for it |
| single-statement module (module frame span == the statement's) | module frame first, statement's binders win |

### 2b. The do-binder frame span

`SDoBind`'s `loc.span` is `p.loc.span to t.loc.span` (`SurfaceParsers.scala:419`) — pattern start to
**rhs end** — and `SDo`'s is `span2(p1, p2)` (`:427`) where `p2` is the position after the laid-out
block, i.e. the start of the next token.  So the new frame is `[end of the whole bind statement,
start of the token after the do block)`, and because `Span.contains` is **half-open at the end**
(`col < endCol`, `Surface.scala:26-28`) it stops exactly at that next token rather than one past it.
That is precisely "from the bind statement to the end of the do block", one statement neither short
nor long.  Measured on the shapes that could break it:

| probe | frame | verdict |
|---|---|---|
| `zz <- g zz` shadowing a top-level `zz`, then `h zz`, then `later = zz` | `Span(4,13,6,1)` | rhs `zz` → the TOP LEVEL (binder NOT visible in its own rhs ✔); `h zz` → DoBound ✔; `later = zz` at 6:1 → TOP LEVEL, **the half-open end is what stops the leak** ✔ |
| multi-line rhs (`bb <- g\n bb`) | starts at the end of the SECOND line | rhs `bb` → top level ✔ |
| do inside a `where`, with a where sibling `v = 9` after it | `Span(5,19,7,5)` ends at the sibling's first column | the sibling's own `v` → WhereBound, not DoBound ✔ |
| nested do blocks, both binding `a` | inner `Span(5,18,7,3)` ⊂ outer `Span(3,11,8,1)` | inner wins inside, outer resumes at 7:3 ✔ |
| do inside parens, `(do … ) + aa` | ends at the `)` | `aa` after the `+` → top level ✔ |
| `let a = …` and `\a ->` inside a do block that binds `a` | let/lambda frames ⊂ do frame | the tighter frame wins, DoBound resumes after ✔ |
| do as a `case` alt body, top level referenced on the next line | `Span(5,26,7,1)` | ✔ |

### 2c. The property, re-run — and the direction it does not cover

Re-ran (`run-B-tests.log`).  `TestRenamer` 31 properties, the collect lines byte-identical to the
report: `files 252 | value-local occurrences 6643 | scopeAt disagreements 0 | type-level occurrences
12339`, `shadowed value-local occurrences 55`.  The property does compare **ids**, not spellings:
`r.scopeAt(sp.startLine, sp.startCol).get(n)` is matched against the occurrence's own
`ToBinder(id)` (`TestRenamer.scala:589`), with a `Some(other)`/`None` split that names the wrong
binder in the failure message.  Correct as specified.

**It is one-directional**, and the brief's question about a frame that reaches "one statement too
far" lives in the direction it skips: the property filters to occurrences that resolved to a
value-LOCAL binder (`localKind`), so an occurrence resolving to a TOP LEVEL or staying free while
`scopeAt` claims a local — exactly what an over-wide frame produces — is never looked at.  I ran
that direction myself, outside the tree (scratch `probe3/`, same 253-file corpus, same
`ModuleScope.Scope.empty`, type-level occurrences excluded because `scopeAt` is a value-scope layer):

```
parsed 252 | value-local occurrences checked 6643 | mismatch 0 | not-visible 0     (reproduces the shipped property exactly)
REVERSE: top-level/free value occurrences checked 35920 | FALSE-LOCAL 0
type-level occurrences skipped 28663
```

**0 of 35 920.**  The frames do not over-reach anywhere in the corpus.  I am not asking for this to
be added to the tree — the forward property plus this measurement is enough for 6.5 — but the
asymmetry is worth a line in the report so a later item does not assume the property covers it.

## 3. The context rules, probed

`Completion.contextAt` run directly on 24 lines (`run-D-probe2.log`).  Every rule behaves as the
report's table says:

| probe | answer | note |
|---|---|---|
| `import ` (col 7) | `Modules("")` | → 161 module names on Report.e's root, capped at 300, `isIncomplete` false under the cap.  **Yes, capped.** |
| `import Layout.` | `Modules("Layout.")` | prefix-match on the whole path ⇒ `Layout.*` **and nothing else**; `Layout` itself is correctly not offered (it does not start with `Layout.`) |
| `import Bool (not, an` / `import Bool using (not, an` | `Names("an")` | the stated gap, **CONFIRMED**.  See §5, F-4 |
| `x = Bool.n` | `Qualified("Bool","n")` | offers `not` with `Bool -> Bool`.  See §5, F-2 |
| `x = rec.fie`, `x = fooBar.baz`, `x = 3.n` | `Names(…)` | lower-initial paths are not module paths ✔ |
| `f : Bo` | `Names("Bo")` | **types ARE offered** — own types and constructors from 6.4's tree, imported types from the canonical type map, both `KClass`/`KConstructor`; the item list is position-blind for named types, as §3 says |
| `whe` | `Names("whe")` | `where` IS in `SurfaceParsers.keywords`, offered at tier 3 |
| `x = y -- comm`, `x = {- c -} y` (col 6), `x = "str` | `Dead` → `[]` | ✔ |
| `x = {- c -} y` (col 12), `x = "s" ++ no` | `Names(…)` | a CLOSED comment/string does not poison the rest of the line ✔ |
| `x = a <+` | `Names("")` | **operators are not completed** ✔ |
| `importX` | `Names("importX")` | the `\s+` in the import regex is doing its job ✔ |
| a line CONTINUING a block comment or string from an earlier line | `dead == false` | the stated line-local gap, **CONFIRMED**.  See R-3 |

Type variables: never offered, and it is a fact about the tables, not a policy — every `s.frames +=`
site in `Renamer.scala` (`:245, :526, :535, :552, :623, :638, :643, :664`) appends value binders
only; `TyParam`/`TyImplicit`/`KindParam` never enter a frame.  My own corpus sweep counts 28 663
type-level occurrences and `scopeAt` reports none of them.  **CONFIRMED as stated.**

## 4. Items, ranking, payload, timing, staleness

* **Tiers and dedup.**  `items` appends locals (kind ≠ `TopLevel`/`TyDef`, from `scopeAt`) → own
  (6.4 tree, then `moduleTerms`) → imported terms → imported types → keywords, then `dedup` keeps the
  FIRST per label.  So the brief's two duplicate cases: **a local shadowing an own top level ⇒ ONE
  item, tier 0** (and note this only works because of fix 7a — before it, `scopeAt` handed back the
  shadowed top level's id, the local was filtered out of tier 0 as a `TopLevel`, and the offer was
  the wrong binder with the wrong type); **an own top level also reachable through an import ⇒ ONE
  item, tier 1**, the one that carries a checked type.  Two imports of one spelling collapse earlier
  still: `scopeTerms` is keyed by `Local`, so `Prelude`'s and `Bool`'s `not` are one entry, and
  `canonical` returns `None` for the ambiguous list, so the item is offered with no `detail` rather
  than with a guessed one.  Correct.
* **`isIncomplete`.**  Set in exactly three places and each is right: truncation (`ms.size > Cap` /
  `hits.size > Cap`, computed BEFORE `take`), import-suppression (the empty-prefix branch, always
  true), and "no index yet" (`case None => (Nil, true)`, so a client cannot cache an empty list
  forever).  A prefixed answer under the cap is `false`; `Dead` is `(Nil, false)`.  Verified live:
  `prefix f` → 97 items `false`, `prefix fie` → 4 items `false`, empty → 300 items **`true`**.
* **Timing, re-measured** (`run-H-timing.log`, `timing-server.log`; `Layout/Report.e`, LSP line 1503
  = 1-based 1504, `      (fieldName parentId) …`; median of ten, load 1.9):

  | | server-side median (mine) | implementer | client round trip (mine) | items | JSON |
  |---|---|---|---|---|---|
  | prefix `f` | **2.45 ms** | 2.5 ms | 7.0 ms | 97 | 11 123 B |
  | prefix `fie` | **1.6 ms** | 1.6 ms | 2.1 ms | 4 | 398 B |
  | empty prefix | **1.65 ms** | 1.8 ms | 14.5 ms | 300 | **52 490 B** |
  | module context, cold walk | **4.0 ms** | 5.3 ms | 4.6 ms | 161 | — |
  | module context, cached | **0.3 ms** | 0.2–0.3 ms | 0.9 ms | 161 | — |

  `candidates in scope` is **1332**, from the standing log line, on the nose.  The empty-prefix JSON
  is 52 490 bytes to the byte.  The bar is 50 ms; the answer is 2.5.  The unfiltered 1332-item /
  180 752-byte figure needed a temporary build and I did not reproduce it, but 1332 is confirmed and
  52 490/300 = 175 B per capped item against 180 752/1332 = 136 B for a set that is mostly short
  imported names — **PLAUSIBLE**.
* **The module walk.**  `modulesUnder(root)` recurses the module root the CHECK computed
  (`Resident.Checked.root`, now on the index), depth ≤ 8, directories and `.e` files with an
  upper-initial name only, and is cached in a `private var fsCache` on the `Completion` **object** —
  so **per server (per JVM), keyed by root**, not per document — with a 5 s TTL.  A `.e` file that
  appears on disk while the editor is open is therefore seen within five seconds.  The mutable
  `var` is safe only because dispatch is single-threaded (Decision 3); that is an invariant, so it
  is fine, but it is now a second place that depends on it.
* **Staleness.**  Confirmed live in the smoke server log: the request sent before `initialized`
  logs `completion: [] , session still booting` in the same millisecond it arrives and answers
  `Json.Arr(Nil)` — an empty ARRAY, never `null`, with no wait beyond dispatch.  The two-sided pin
  (typed binder absent immediately after `didChange`, present after diagnostics) passed.

## 5. Findings

| id | severity | status | finding |
|---|---|---|---|
| F-1 | — | **CONFIRMED** | The shared file is frozen for batch by construction; the tier does not grow.  §1 above is the argument from the code; the green corpus/REPL/TestLoopTrace results are confirmation of it, not the proof.  No action. |
| F-2 | **MEDIUM** | **REFUTED (the report's claim)** | Qualified completion inserts text this fork cannot read **in every position**, not just for lower-initial terms.  The report (§4, §11.3) says it "is therefore correct and useful for a TYPE position … and for a qualified CONSTRUCTOR".  Measured against `Complete.e`, which imports `Bool` and where the unqualified baselines `zzD = not True` and `zzE : Bool` both check CLEAN: `zzA = Bool.not True` → `error: unknown operator .`; `zzB = Bool.True` → `error: unknown operator .`; `zzC : Bool.Bool` → `error: unknown type operator .`.  The dot is read as the composition operator in every one of them, because `varTerm`/`tyName` try `identTok` BEFORE `moduleQualCon`/`qualDottedName`, so the upper-initial segment is consumed as a plain identifier and the dotted alternative never runs.  The fork's actual idiom is the `_M` affix (`empty#_NM`, `lookup_M`, `at_V` in the stdlib), and `Renamer`/`ModuleScope` split no spelling on `.` anywhere.  **The item is still built as ordered** — the roadmap asks for `Bool.` by name and pins it in the smoke — and the smoke honestly asserts that the probe lines do not parse.  What must change is the report's sentence: qualified completion is a MODULE BROWSER whose insertions do not compile, in any position.  The right fix (bare label + an `import Bool (not)` `additionalTextEdit`, or the `_M` affix form) is a 6.6-shaped edit, not a 6.5 one — 6.6 is already the add-import item.  **Restate; do not fix here.** |
| F-3 | **MEDIUM** | **CONFIRMED, then closed by me** | The shipped scope-agreement property covers one direction only (occurrences that resolved to a value-local binder), so an over-wide frame — the failure mode the do-binder fix could have introduced — is outside it.  I ran the reverse over the same corpus: **0 FALSE-LOCAL of 35 920** top-level/free value occurrences, and my harness reproduces the forward numbers exactly (6643 / 0 / 0).  No code change owed; one sentence in the report so a later item does not over-trust the property. |
| F-4 | LOW | **CONFIRMED** | An import LIST is a name context (`import Bool (not, an` → `Names("an")`), so completion offers the file's own locals and keywords inside someone else's export list.  Wrong-but-harmless is the right call for 6.5: the items offered there are simply not what is wanted, nothing is inserted that misleads, and the alternative is a fourth context.  Stated in §2 and §11.4.  Leave it; it belongs with 6.6/6.7 if anyone minds. |
| F-5 | LOW | **CONFIRMED** | The gate table omits `*TestLower`, required by the Stage-3 invariant for any item touching `Renamer` (`LSP-ROADMAP.md:647-649`).  Neither the implementer's brief nor mine listed it.  I ran `core/testOnly *TestLower *TestNewPipeline`: **30/30, 0 failed** (Lower 28, NewPipeline 2).  Add the row. |
| F-6 | LOW | **CONFIRMED** | `docs/lsp.md` states neither the line-local comment/string gap nor the comment/string → `[]` rule at all — its context table has three rows and no "dead" row.  The report states both (§2, §11.2).  The invariant puts the user-facing limits statement in the docs.  Two sentences. |
| F-7 | LOW | **CONFIRMED** | Decision (c) names three workspace sources; the item adds a fourth (`env.loadedModules.keySet`, what THIS file's check had loaded — the only list `Layout.Scan` is in) and says so in §4.  Decisions are append-only and overridden "with a note, not silently": the note exists, but Decision (c) itself is unamended.  Orchestrator's line to add, not the implementer's (the roadmap is off-limits to both of us). |
| F-8 | INFO | **CONFIRMED** | The two new fixtures contain no `do` block, so fix 7b is pinned by the corpus property and by my probes, but by nothing end to end in lsp-smoke.  Cheap to close later (`Complete.e` + three lines); not owed at 6.5. |
| F-9 | INFO | **CONFIRMED** | Tab-expanded parser columns (ticket E8) are inherited exactly as `Definitions.scala:182` and `References.scala:100` inherit them (`chr + 1`, no `LineIndex` round trip on the way IN).  Same class as every request since 0.5, stated in §11.1.  `lineText` DOES strip a trailing `\r`, which matters — 142 of the 161 stdlib modules are CRLF. |
| F-10 | INFO | **CONFIRMED** | `DocIndex` now retains, per OPEN DOCUMENT, the check's `env.cons` and the ModuleScope's `termNames` (the session superset) in addition to the canonical maps it already held.  They are references to immutable maps largely shared with the session's, and the measured warm index (12.0–18.4 ms) and boot (12.0 s) did not move, so this is a note, not a cost.  A handler throwing inside a `detail` thunk cannot kill the server: `Rpc.scala:415` catches `Throwable` per request. |

## 6. Gates — implementer vs mine (each re-run ONCE, one JVM at a time, load < 2 at every start)

| gate | implementer | **mine** | |
|---|---|---|---|
| `sbt core/compile core/copyResources` | green | **green** (zinc up-to-date on the delivered tree; no new warnings) | ✔ |
| `TestLoopTrace` | 720/720/720, hashdiff 0 eqdiff 0 nonpart 0 fuel 0 | **720 solves / 720 segments / 720 agree; hashdiff 0, eqdiff 0, nonpart 0, rejected 36, fuel 0**; 3 properties | ✔ |
| `*TestRenamer* *TestTolerantCheck *TestTolerantRead *TestEditorBuffers` (+ `*TestReplDifferential`, per my brief) | 74/74 (four suites) | **78/78, 0 failed, 0 errors** — Renamer **31**, TolerantCheck 26, TolerantRead 11, EditorBuffers 6, ReplDifferential 1, LoopTrace 3 (one JVM with LoopTrace) | ✔ |
| `*TestLower` (roadmap-required, **omitted by both briefs**) | not run | **30/30** (Lower 28, NewPipeline 2) | ✔ new |
| TestRenamer collected data | `6643 / 0 / 12339`, `shadowed 55`, 6.3+6.4 lines unchanged | **identical, every line**: `files 252 \| value-local occurrences 6643 \| scopeAt disagreements 0 \| type-level occurrences 12339`; `shadowed 55`; `occurrences 71248 \| exact 70897 \| … \| behind a tab 6`; `symbols 8159`; `sibling levels 8411 \| straddling pairs 0`; `term groups 3441 \| moduleTerms 3441` | ✔ |
| REVERSE scope check (mine, outside the tree) | — | **0 FALSE-LOCAL of 35 920** over the same 252 files | ✔ new |
| `corpus-run.sh --batch` | 85/69/0 over 154 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**, 154 outputs, one JVM, exit 0 | ✔ |
| `repl-smoke.sh` | 8 groups / 66 checks, goldens clean | **8 PASS / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` clean | ✔ |
| `lsp-smoke.sh` | 386 (+42) | **PASS, 386 checks**; the 42 new ones enumerated from the diff, by fixture: **`Complete.e` 33** (clean 1, argument 3, empty prefix 2, where 3, let 5, own top level 1, own constructor 2, imported 3, sibling 1, string 1, the `Bool.`/`Nope.` probe + its parse assertion + its revert 5, staleness 5, cost 1), **`CompleteSib.e` 5** (clean 1, module context 4), **`LocalsBroken.e` 2**, **`initialize` capability 1**, **before-boot 1** = 42 | ✔ |
| boot | 129 modules in 11.9 s | **129 modules in 12.0 s** (and 12.3 s on a second run) | ✔ |
| Report.e round trip, one pair | 1.22–1.47 s (own protocol) | **1.692 s median** (perf-client protocol, rounds 2–4, reused 97/154, boot 12.01 s, load 1.2) | see note |
| completion cost | 2.5 / 1.6 / 1.8 ms, 5.3 cold walk | **2.45 / 1.6 / 1.65 ms, 4.0 cold walk, 0.3 cached**, 1332 candidates, 52 490 B empty answer | ✔ |
| `.ei` | 0 outside `tracker/g1-*` | **0**, checked after every JVM and at the end | ✔ |
| `git diff --stat` vs `--stat -w` | identical | **identical**; `git status --porcelain` at the end is exactly what it was at the start (7 M, 6 ??) | ✔ |

**Note on the round trip.**  1.692 s is `perf-client.py`'s protocol (a pinned digit edit that
invalidates 57 of 154 components), which is NOT the protocol behind the report's 1.22–1.47 s, so the
two numbers are not comparable and mine neither confirms nor refutes §1a.  It is in the same band as
`docs/lsp.md`'s standing 1.57 s baseline on a shared box, and I did not run an A/B: the item adds
five stored references and no walk, copy or render to `index`, which the unmoved warm-index figures
(12.0–18.4 ms) already say.  No perf A/B is owed — nothing entered inference or the check.

## 7. Is the report accurate?

Yes, against my numbers, with the three corrections above.  Every figure I could re-derive came back
identical or within run-to-run spread: 6643/0/12339/55, 71248/70897/6, 8159, 8411/0, 3441/3441,
85/69/0, 66 repl checks, 386 smoke checks, 129 modules, 1332 candidates, 52 490 bytes, 2.5 ms.  The
two grammar findings are the right findings and are correctly left as STATED GAPS rather than fixed
here — the import-list one (§11.4) is exactly right as written; the qualified-reference one (§4,
§11.3) is right that it found a real fork fact and wrong about its extent (F-2).  §1's "no file
outside `lsp/` changed except `rename/Renamer.scala`, whose change is confined to `Result.scopeAt`
and to the FRAMES table (which nothing on the batch path reads)" is correct as I verified it
independently in §1.

## 8. What I ran, in order

`run-A-compile.log` (compile+copyResources) · `run-B-tests.log` (LoopTrace + the five suites, 3m35s)
· `run-C-probe.log`, `run-D-probe2.log` (frame-shape and context-rule probes, scala-cli on
`export core/fullClasspath`) · `run-E-lspsmoke.log` + `lsp-smoke-server.log` (386) ·
`run-F-corpus.log` + `corpus/` (154 outputs, verdicts 85/69/0) · `run-G-repl.log` (66) ·
`run-H-timing.log` + `timing-server.log` (completion timing, Report.e) · `qual2-server.log`
(the F-2 grammar probe on `Complete.e`) · `run-K-lower.log` (TestLower + NewPipeline) ·
`probe3/` (the reverse corpus check) · `editor2.json` (Report.e round trip).  All under the scratch
directory.  Every `.e` buffer edit was made through `didChange` and reverted; `Report.e` and
`Complete.e` are byte-identical on disk to what they were.

STOP after this report.

---

# Second pass — the F-2…F-8 fixes

Scope: **only the fixes**.  Read: the updated `LSP3-6.5-COMPLETION.md` §4a, §8a, §11.3; the new
`Completion.importLines` / `importEdit` / `qualifiedExtras` / `moduleBefore` in `lsp/Completion.scala`;
the `TestRenamer` reverse property and context-rule cases; the `lsp-client.py` additions; the two
fixtures; `docs/lsp.md`.  Same rules: nothing edited but this file and my scratch directory, one JVM
at a time, no commits, `.ei` outside `tracker/g1-*` = 0, tree byte-identical at the end.

## VERDICT: **FIX-THEN-ADVANCE** (three statements; at most one small code edit)

Every round-one item is closed: R-1 (§4a now says a dotted reference parses in NO position, and the
item stops inserting one), R-2 (`*TestLower` is in the table and ran), R-3 (`docs/lsp.md` gained the
dead → `[]` row, the line-local gap AND the `using`-list gap), F-3 (the reverse property is in the
tree), F-8 (the do block is in `CompleteSib.e` with three live pins).  All gates re-ran green at the
implementer's numbers, and I applied the edits myself through my own client: the two mainline shapes
**check clean**.

What the fix round introduced or left, all of it "the applied edit does not check clean" in a shape
the report does not mention.  None of it touches batch (`Completion.scala` only), none is silent
corruption (the user gets a diagnostic immediately), so none blocks:

* **S-1** must be stated — an aliased import.
* **S-2** must be stated or fixed — a spelling that is both a type and a constructor.  The report's
  `dedup` rationale is now false and should not ship as written.
* **S-3** must be stated — `Module.` lists the module's ORIGIN names, not its exports.

If all three land as statements, no gate re-run is owed.  A code change for S-2 needs lsp-smoke only.

## Findings

| id | severity | status | finding |
|---|---|---|---|
| S-0 | — | **CONFIRMED** | The fix works in the mainline.  I applied the edits with my own client (scratch `pass2.py`): `zq = Layout.Scan.runner` in `CompleteSib.e` → `textEdit` range `{line 13, char 5}…{13, 23}` (char 5 IS the `L` of `Layout`, i.e. the first character of the **whole multi-segment path** — `moduleBefore` now returns that column and `A.B.C.na` gives 6), `newText` `runner`, `filterText` `Layout.Scan.runner`, no import edit (already imported) — **applied → 0 diagnostics**.  `q = Ring.Ring` in a TERM position → `import Ring using Ring` inserted at line 4 — **applied → 0 diagnostics**.  The smoke's own `Bool.not` and `Maybe.isJust` pins do the same and pass. |
| S-1 | **MEDIUM** | **NEW, unstated** | **An aliased import defeats both halves of the fix.**  `importLines`' regex captures group 1 and ignores `as B`, so `import Bool as B` counts as "Bool is imported" and NO import edit is added; but this fork exposes an aliased module's names **only in the affix form**.  Measured on a minimal buffer that checks clean with `import Bool as B`: `z = not True` → **1 diagnostic**, `z = not_B True` → **0**.  So `Bool.no\|` under an alias inserts a bare `not` that does not resolve, with no import edit to save it — the same failure the `using`-list case has, and unlike that one it is stated nowhere.  (The other half: `B.n\|` IS recognised as `Qualified("B","n")` — `B` is upper-initial — and `exportsOf` filters on `g.module == "B"`, which no Global matches, so it answers `[]`.  Benign, also unstated.)  Cheapest honest fix: have `importLines` return the alias too and skip the qualified extras (or offer the `_A` form) when the module is imported aliased; cheapest acceptable: say so in §4a and `docs/lsp.md` beside the `using`-list sentence. |
| S-2 | **MEDIUM** | **NEW, and it falsifies a rationale in the report** | **A spelling that is both a type and a constructor gets the wrong import edit in a TYPE position.**  `exportsOf` returns `open ++ terms ++ types` and `dedup` keeps the first, so `Ring` (a constructor in `terms`) swallows `Ring` (the type in `cons`); `isType` is decided by `i.kind == KClass`, so the item carries `import Ring using Ring` — the TERM form.  In a term position that is right (0 diagnostics, S-0).  In a TYPE position it is not: `q : Ring.Ring Int` offers exactly one item, kind 4, and **applied → 2 diagnostics** (`q : Ring Int` with a term-only import).  Round one's `dedup` comment — "a type and a constructor of the same spelling collapse the same way: the text to insert is identical either way" — was true before the fix and is **false now** that an `additionalTextEdits` rides on the item's kind.  Fix: either emit both `using X` and `using type X` for a label that is in both tables, or stop deduping across the two namespaces when their extras differ.  At minimum the `dedup` comment and §4a must stop claiming the collapse is free. |
| S-3 | **MEDIUM** (usefulness) / LOW (risk) | **NEW, unstated; pre-existing since round one** | **`Module.` lists the names whose Global ORIGIN is that module, not the names it exports.**  `exportsOf` filters `g.module == mod` on both tables, and re-exports keep their origin.  Measured: `Maybe.` → **16 items, every one a lower-initial function defined in `Maybe.e`** (`catMaybes`, `getJust`, `isJust`, `maybe`, …) — the type `Maybe` and both constructors `Just`/`Nothing` are **absent**, because `data Maybe` lives in `Native.Maybe` (`Native.Maybe.` answers `Just#`, `Maybe#`, `Nothing#`).  So the most obvious thing a user would type `Maybe.` for is the one thing it will not offer.  Nothing WRONG is emitted — what is offered is correct and its import edit checks clean — but §4 and `docs/lsp.md` both say "that module's exports", which is not what it is.  `Definitions.scala` already owns the chase (`Renamer.originOf` over `termOrigins`); wiring it in is a 6.6/6.7-sized change, not a 6.5 one.  State it. |
| S-4 | LOW | **CONFIRMED — stated, NOT pinned** | The coordinator's question: an already-imported module whose `using` list omits the picked name.  **Stated** in §4a ("WHAT IS STILL NOT DONE") and in `docs/lsp.md` ("the insertion will not resolve until that list is extended"), and §4a's "checks clean" claim is correctly scoped to the two pinned cases — **the item does not claim it universally.**  It is **not pinned**: measured on a minimal buffer clean with `import Bool using not`, the applied `z = otherwise` → **1 diagnostic**.  Both smoke pins are the clean shapes.  One negative check would make the gap a fact in the harness rather than a paragraph; optional. |
| S-5 | INFO | **CONFIRMED** | The CRLF terminator IS preserved where it matters — `import Maybe using isJust\r\n` when the anchor is a CRLF import line **and** when it is the CRLF `module … where` line.  The one fallback to `\n` is a CRLF buffer with **neither** a header nor an import (`anchor == -1`), which inserts at line 0 with an LF.  Cosmetic corner; `importEdit`'s `eol` guard could read `lines(0)` instead of `lines(anchor)`. |
| S-6 | INFO | **CONFIRMED** | Headerless and empty-import buffers are handled sanely: no `module` line + imports → insert after the last import; neither → insert at line 0.  `export M` counts as an import (correct — an export re-exports into scope), and `mod == ownModule` returns `None`. |
| S-7 | INFO | **CONFIRMED, with one caveat** | The reverse property (F-3) asserts the right thing and asserts **more** than my scratch run did.  The denominators reconcile exactly: I excluded every occurrence with `o.typeLevel` (28 663 of them) and checked **35 920**; the property excludes only occurrences whose RESOLVED BINDER kind is type-level (12 339) and falls back to `o.typeLevel` for non-`ToBinder` resolutions, keeping `Unresolved`/`Ambiguous`/`ToGlobal` **and the ~3 567 `TyDef`-resolved type-name occurrences** in — hence **39 487**, a superset of mine, and 0 either way with an anti-vacuity floor of 20 000.  Caveat: a `TyDef`-resolved occurrence is a TYPE-namespace reference being asked of a VALUE-namespace layer, so if a corpus file ever binds a value local spelled like a type in scope, the property fails for a namespace reason and not a scope one.  Using `o.typeLevel` for the `TyDef` case too would remove that false-positive surface.  Not owed now. |
| S-8 | — | **CONFIRMED** | F-8 closed properly.  `CompleteSib.e` gained a real `do` block (`doFn f fa fb = do dx <- fa; dy <- fb; unit (f dx dy)`) and three live pins: `dy <- \|fb` offers `dx` and **not** `dy`; `unit (f d\|x dy)` offers both; `dx <- \|fa` offers **neither** and does offer `fa`.  These are exactly the three the frame fix makes true, and they agree with the eleven synthetic shapes in the first pass. |
| S-9 | — | **CONFIRMED** | R-1/R-2/R-3 all closed.  §4a is now accurate about the grammar (`identTok` before the dotted alternatives; `unknown operator .` in term, constructor and type alike) and §11.3 no longer claims types and constructors work.  `docs/lsp.md` gained the comment/string → `[]` row, the "CURRENT LINE only" gap and the `using`-list caveat.  `*TestLower` is in the gate table and ran. |

## Gates — second pass (each run ONCE, one JVM at a time, load < 2 at every start)

| gate | implementer | **mine** | |
|---|---|---|---|
| `core/compile core/copyResources` | green | **green**, no new warnings | ✔ |
| six suites | 104/104, TestLower 28, TestRenamer 32 | **107/107, 0 failed, 0 errors** in one JVM (Renamer **32**, TolerantCheck 26, TolerantRead 11, EditorBuffers 6, **Lower 28**, ReplDifferential 1 = **104**, plus LoopTrace 3) | ✔ |
| `TestLoopTrace` | 720/720 | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, rejected 36, fuel 0; positive control fires (46 and 58 of 720 disagree under injection) | ✔ |
| reverse scope property | 0 false locals of 39 487 | **`top-level/free value occurrences 39487 \| false-local 0`** | ✔ |
| forward + anti-vacuity + context rules | 6643/0/12339, 55, 16 cases | **identical**, and 6.3/6.4's lines unchanged (`71248 \| 70897 \| … \| 6`; `8159`; `8411 \| 0`; `3441 \| 3441`) | ✔ |
| `lsp-smoke.sh` | 396 | **PASS, 396 checks** | ✔ |
| `repl-smoke.sh` | goldens clean | **8 PASS / 66 checks**; `git status tracker/repl-tests` clean | ✔ |
| boot | — | **129 modules in 11.8 s** | ✔ |
| corpus | not needed (`Completion.scala` only) | **not run**, agreed: the only source file changed since the first pass is `Completion.scala`, which no batch path loads; `Renamer.scala` is byte-identical to the tree I already ran 85/69/0 over | ✔ |
| `.ei` | 0 | **0** outside `tracker/g1-*`, after every JVM | ✔ |
| tree | — | `git status --porcelain` identical to the start (7 M, 7 ??); `git diff --stat` == `--stat -w` | ✔ |

## What I ran, second pass

`p2-run-A.log` (compile + LoopTrace + the six suites, one JVM, 3m43s) · `p2-lsp-server.log` +
lsp-smoke (396) · repl-smoke (66, goldens clean) · scratch `probe4/` (two scala-cli runs: `importLines`
/ `importEdit` over LF, CRLF, headerless, import-less, `using`-list, aliased and `export` buffers, plus
`contextAt`'s multi-segment start column) · `pass2.py` + `pass2-server.log` (live: the multi-segment
edit applied, the `using`-list case applied, the alias case, a constructor, a type, a same-spelling
collision) · `pass3.py` + `pass3-server.log` (the de-contaminated baselines behind S-1, S-2, S-3, S-4).
Every buffer edit went through `didChange` and was reverted; `Complete.e` and `CompleteSib.e` are
byte-identical on disk.

STOP after this section.
