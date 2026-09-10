# LSP Stage 3, item 6.7 — INDEPENDENT REVIEW (wiring, docs, demo, and the G3 gate numbers)

Reviewer report, 2026-09-10 (Opus).  Brief `tracker/loopmodel/briefs/brief-LSP3-6.7-review.md`; implementer's
report `tracker/loopmodel/LSP3-6.7-WIRING.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3, 6.7 and
**GATE G3**; `tracker/GATE-POLICY.md`.  Branch `scala3-migration`, tree at `a4b13a8` plus the item's
uncommitted deliverables.  No commits; `tracker/lean/` and `tracker/LSP-ROADMAP.md` untouched; the only file
this review writes in the repo is itself.  Scratch (every log named below):
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.7/`.

**VERDICT: FIX-THEN-ADVANCE**, and the fix round has since landed — **ADVANCE once R-20 is corrected**
(one sentence).  Every gate is green on my own run including Tier 2 at **988/988 in 26 m 56 s**, the
extension and the demo reproduce, `git diff -- core/src` is empty, and the two latency numbers G3 and
Stage 4 depend on are reproduced within 1 %.  The docs as reviewed carried three defects that a report or
the shipped code contradicts (R-1, R-2, R-3) and four that over- or under-state what shipped (R-4 … R-7),
all prose, none in `core/src`; the fix list is § 7.  While my `core/test` was running the implementer
applied all ten items — **verified in § 9** — introducing one new wording error, **R-20**, in a sentence that
describes MY measurement.  Line references in §§ 1–6 are to the files AS REVIEWED (before that fix round).

---

## 1. The numbers, first (this is what "Gate evidence (G3)" should quote)

### 1a. Keystroke → diagnostics: an interleaved pair against the Stage-3 opening commit

`tracker/tools/perf-bench.sh editor -k 15` on `core/src/main/resources/modules/Layout/Report.e`, four runs,
**before / after / before / after**, one JVM at a time, nothing else running.  BEFORE is a scratch worktree of
**`78d860f`** (the Stage-3 opening, no Stage-3 code), built and given its OWN `tracker/repl-classpath.txt` —
the tracked one holds the main tree's absolute paths and would have measured the main tree twice (trap
recorded here because it is silent).  Both trees are on the same ext4 filesystem; the harness (perf-bench.sh,
perf-client.py) is byte-identical at the two commits, so the instrument is constant.

| run | tree | median | read | typecheck | debounce | residual | reused | cold open | boot | load before |
|---|---|---|---|---|---|---|---|---|---|---|
| B1 | `78d860f` | **1.793 s** | 0.920 | 0.540 | 0.300 | 0.021 | 97/154 | 2.222 | 12.88 | 1.31 |
| A1 | final tree | **1.697 s** | 0.860 | 0.500 | 0.300 | 0.025 | 97/154 | 2.148 | 12.71 | 0.97 |
| B2 | `78d860f` | **1.724 s** | 0.890 | 0.510 | 0.300 | 0.019 | 97/154 | 2.178 | 12.91 | 0.95 |
| A2 | final tree | **1.690 s** | 0.855 | 0.510 | 0.300 | 0.029 | 97/154 | 2.205 | 12.85 | 1.00 |

Pooled: **BEFORE 1.759 s, AFTER 1.694 s, Δ = −65 ms in favour of the final tree** (pairwise −96 ms and
−34 ms; both sides identical at 97 of 154 components reused).  Logs `perf-B1/`, `perf-A1/`, `perf-B2/`,
`perf-A2/`.

**So 1.86 vs 1.57 is machine drift, and now it is measured rather than asserted.**  The G2-era figure was
1.57 s = 0.80 read + 0.45 typecheck + 0.30 debounce.  Today the SAME CODE — `78d860f`, before a line of
Stage 3 — reads 0.89–0.92 s (+0.10) and typechecks 0.51–0.54 s (+0.07), i.e. **+0.17…0.19 s, which is the
whole of the 1.57 → 1.76 gap**, on a tree that cannot contain the cause.  Stage 3's own contribution to the
round trip is not merely "under budget", it is **negative on both pairs**.  The alternative hypothesis in the
brief — the index/symbol build now sitting on the check path — is refuted independently: that build is
12.9–18.7 ms warm (§ 1c), two orders below the gap, and the reuse counter is unchanged.  The implementer's
reading ("machine drift … a user-facing 'what does it feel like' number, not a regression verdict",
`LSP3-6.7-WIRING.md` § 3a note 1) is CONFIRMED.

One residual on the doc's number itself: 1.859 s was taken at `load_before=1.34`, `load_after=2.22`; my four
runs at 0.95–1.31 put the shipped tree at **1.690–1.697 s**.  The honest user-facing range today is **≈1.7 s
on a quiet machine, ≈1.9 s on a busy one** — see R-19, a NIT.

### 1b. Worst-case request wait during a check — reproduced

My own probe (`rlat.py`, written for this review; same protocol shape as the implementer's, independent
code), a `didChange` on Report.e then a hover sent just past the 300 ms debounce, timed send → response:

| | implementer | reviewer (this run) |
|---|---|---|
| hover sent at | +352 ms | +352 ms (352 / 352 / 353) |
| **wait, send → answer** | **1468 ms** median (1450 / 1477 / 1468) | **1453 ms** median (1384 / 1453 / 1612) |
| keystroke → that answer | 1820 ms | 1806 ms |
| the same hover on an IDLE server | 0.61 ms | 0.58 ms |

Within 1 % on the headline and on the control; the ~2500× idle/busy ratio, which is the whole content of the
parked worker-thread fork, reproduces exactly.  `rlat.out`, `rlat-lsp.log`.  The doc's rounding to **1.47 s**
is right, and its explanation — one check minus the 352 ms already elapsed, which is why it sits below the
1.86 s round trip — is arithmetically correct.

### 1c. The rest of the table — spot-checks (I ran all of them; two were asked for)

| row | doc / implementer | reviewer | verdict |
|---|---|---|---|
| code action, first after a check / after | 51.9 ms / 0.68–1.09 ms | **51.7 ms** / 0.67–1.33 ms | reproduced |
| `workspace/symbol`, first / warm | 60.7 ms / 1.58 ms | **47.6 ms** / 1.11 ms | same shape, first query is disk-cache sensitive |
| `documentSymbol` | 32.4 ms (398 top-level, 511 all) | **20.8 ms** (398 / 511) | counts exact; time is a client round trip, spread-dominated |
| index build, cold / warm | 66 ms / 13–23 ms | **56.4 ms** / 12.9–18.7 ms (median 14.5) | reproduced; 7980 occurrences, 511 symbols exact |
| completion | "**server side** 6.5 ms" | round trip **6.87 ms**; **server's own log line 1.6–2.7 ms** | **mislabelled — R-1** |
| session boot | 12–15 s, 129 modules | 12.4 / 12.5 / 12.7 / 12.85 / 12.88 / 12.91 s | reproduced (my six boots sit at the low end) |

The completion row is the one real defect: the server prints its own cost
(`completion: Report.e name prefix='f' 97 items of 1332 in scope in 2.1 ms`), which is what 6.5 measured
(2.5 ms) and what the doc should quote for a row labelled "server side"; 6.5 ms is the CLIENT round trip, and
it is 6.5's own client figure for the identical row (`LSP3-6.5-COMPLETION.md:321`).

---

## 2. `git diff -- core/src` — EMPTY, confirmed

`git diff --stat -- core/src` prints nothing; the whole diff is four files
(`docs/lsp.md`, `editor/vscode/README.md`, `editor/vscode/package.json`, `editor/vscode/test/load-test.js`,
645/401 lines) plus four new files (`tracker/tools/lsp-demo.py`, `lsp-demo.sh`,
`tracker/lsp-tests/G3-demo.txt`, the item's report).  No `.e`, no Scala, no fixture moved.  `*.vsix` is
gitignored, so the rebuilt 0.1.1 and the deleted 0.1.0 are correctly invisible to git.  6.7 ships no server
change, as its brief requires.

---

## 3. The extension

`npm run test:grammar` → **PASS**, 359 files / 36,800 lines tokenized, 9 rule groups (`x-grammar.log`).
`npm run test:load` → **PASS** on the first try on the fixed harness: activate in 8 ms, live handshake,
tooltip `Ermine session ready: 129 modules in 12.5s`, `providers registered by the client: 9` (`x-load.log`).
**`pgrep -af ermine-lsp` after the run: nothing** — no leaked JVM, which was the specific failure the
implementer hit and fixed.

**The stub fix was the right call.**  `node_modules/@types/vscode/index.d.ts:2465-2592` defines
`CodeActionKind` as a class with `static readonly Empty` and an instance `append(parts: string)`, so the real
editor's `asCodeActionKind` path (`protocolConverter.js:641-663`) either hits the kind map or calls
`Empty.append(...)` on a real object; nothing in the extension or the server was involved.  The old stub's
generic rule ("any capitalised static is `0`") made both branches fail — `if (result)` is false on `0` even
on a map HIT, and `0.append` throws.  Fixing the extension or the server to dodge that would have been fixing
a fiction.  The new stub reproduces `value`/`append`/`contains`/`intersects` and the eleven named instances
faithfully.  It does not hide a real client failure — but see R-17: the rule that produced the failure is
still in place for every OTHER vscode class the stub does not special-case.

**The new assertions test what they claim.**  `test/load-test.js:284-316` reads the client's ACTUAL
`languages.register*` calls off a recording proxy: the nine provider names are asserted with
`registered.includes(...)` (registering nothing fails all nine), the trigger character is read out of
`registerCompletionItemProvider`'s variadic argument list (`comp.args.slice(2).includes(".")`), and the kinds
are read out of `registerCodeActionsProvider`'s third argument
(`ca.args[2].providedCodeActionKinds → "quickfix,source"`, order-sensitive).  None is a hard-coded tautology.
Two limits, both NIT: the provider COUNT is logged but not asserted (an EXTRA registration passes silently),
and the whole block is skipped when `target/ermine-classpath` is absent (disclosed in the README).

**The vsix.**  `ermine-lang-0.1.1.vsix`, 324 files / 1.83 MB uncompressed / 479 KB on disk, contains
`extension/syntaxes/ermine.tmLanguage.json`, `extension/src/extension.js`,
`extension/language-configuration.json`, `extension/readme.md` (the rewritten one) and
`extension/package.json` with `"version": "0.1.1"`.  315 of the 324 entries are the nine runtime packages
`.vscodeignore` re-allows after excluding `node_modules/**` — `vscode-languageclient` and its dependency
closure, which a VS Code extension must ship.  `.vscodeignore` is UNCHANGED in this diff, so the packaging
rule is 0.1.0's rule: no new bloat, only the new content.  `ermine-lang-0.1.0.vsix` is gone from disk and was
never tracked.

**Eglot (6.7.2).**  I re-read the snippet and the capability list: nothing Stage 3 added needs client-side
configuration (trigger characters are advertised, `xref`/`imenu`/`eglot-rename`/`eglot-code-actions` bind
from the capabilities, the server answers CodeAction literals).  "No change needed" is correct, and the docs
now say so explicitly rather than by implication.

---

## 4. The demo transcript — reproducible, and complete against GATE G3

`tracker/tools/lsp-demo.sh > <scratch>/G3-demo-rerun.txt` re-run on this tree: 249 lines, exit 0.  Normalising
timings only (`s`/`ms` figures), **`diff` against the committed `tracker/lsp-tests/G3-demo.txt` is EMPTY** —
every request, every position, every response body, every count and every ordering is identical.  That is a
stronger reproducibility than "modulo timings" asked for.  No `.ei` and no fixture change:
`git status tracker/lsp-tests` shows only the new transcript.

Against the roadmap's GATE G3 line and the Stage-3 items, the twelve steps cover: the advertised capability
list (10) · diagnostics on a broken file and their clearing by `didChange` with the file untouched on disk
(6.1) · definition to a sibling and to an imported module (post-G2 + 6.1) · hover on a top level, on both
equation arguments with a shared letter supply, on a `let` binder at def-site and use, on a polymorphic
`where` helper, on a type's kind, **and the `case` binder answering null** (6.2, residual shown not hidden) ·
references local and global with Decision (c)'s `window/showMessage` verbatim, and highlight Write/Read
(6.3) · prepareRename, rename applied and re-checked clean, and two refusals (6.3, Decision (d)) ·
documentSymbol with ranges, selection ranges, details and nested constructors (6.4) · three
`workspace/symbol` queries including a builtin that is absent, **with E9 stated in place** (6.4) · five
completions including the qualified `Maybe.` mechanism with its `filterText`, `textEdit` and
`additionalTextEdit` (6.5) · both quick fixes, each applied by the client and re-checked (6.6) · clean
shutdown.  Nothing in G3's list is unrepresented.

---

## 5. GATES — my own run, in the brief's order, one JVM at a time

| gate | implementer | **reviewer (this run)** | log |
|---|---|---|---|
| `sbt -batch -J-Xmx3g core/compile core/copyResources` | green | **green** (no-op, 1 s) | `g0-compile.log` |
| `sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'` | 720/720 | **720 solves / 720 segments / 720 agree**, skipped 0, hashdiff 0, eqdiff 0, rejected 36; 3 properties, 0 failed; controls fired (46 and 58 of 720) | `g1-looptrace.log` |
| `tracker/tools/corpus-run.sh --batch` | 85/69/0 of 154 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** | `g2-corpus.log` |
| `tracker/tools/repl-smoke.sh` | 8 groups / 66 checks | **8 groups / 66 checks, all PASS** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests` **clean** | `g3-repl.log` |
| `tracker/tools/lsp-smoke.sh` | PASS 454 | **PASS, 454 checks** | `g4-lsp.log` |
| `tracker/tools/g1-validate.sh` | 9/9, no drift | **9/9 PASS** — 7 comparator fixtures, double-run self-agreement (129 modules, 1447 signatures, EQUIVALENT), **no drift from `tracker/g1-baseline`**; 2 m 15 s | `g5-g1validate.log` |
| `bin/ermine-lsp` boot | 129 in 14.0 s | **`Ermine session ready: 129 modules in 12.4s`**, clean shutdown/exit, code 0 | `g6-boot.log` |
| **Tier 2** `sbt -batch -J-Xmx3g core/test` ALONE | **988 passed, 0 failed, 0 errors**, 25 m 56 s | **Passed: Total 988, Failed 0, Errors 0** in **26 m 56 s** (12:02:53 → 12:29:52, `rc=0`); zero `[info] x`/`!` lines | `g7-coretest.log` |

`.ei` hygiene: 0 before; **129 appear during `g1-validate.sh`** (its two full-inference boots publish
interfaces by design) and were deleted with a delete scoped to `core/target`; the LSP boot, lsp-smoke, the
demo and the latency probe write **none** (Decision 5's interface-free session — the brief's expectation that
the boot writes 129 does not hold on this tree, and the implementer's correction is right).  `git status
tracker/g1-baseline` clean throughout; the 143 tracked `tracker/g1-*` files were never in reach.  Final count
in `core/target` and in `tracker/lsp-tests`: **0 / 0**.

On the 6.0 determinism claim: this is the **fifth** full `core/test` on this tree lineage (6.0's three at
943/943, the implementer's at 988/988, mine) and the second on the FINAL tree, which is the pair G3 asks for.

---

## 6. Findings

Severity is mine.  CONFIRMED means I verified both sides myself (source, report and — where it is a number —
a measurement).  Every line/section reference is to the uncommitted files as reviewed.

| id | sev | status | one line |
|---|---|---|---|
| R-1 | MAJOR | CONFIRMED | `docs/lsp.md:477` labels the completion figure "server side"; 6.5 ms is the CLIENT round trip — the server's own log line says 1.6–2.7 ms |
| R-2 | MAJOR | CONFIRMED | `docs/lsp.md:412-419`'s 68/49/33 breakdown of the 117 refusals is in NAME OCCURRENCES (150 across 117), presented as a partition of 117 |
| R-3 | MAJOR | CONFIRMED | `docs/lsp.md:197` states the stale-index refusal as "ANY open document"; the shipped rule checks all documents only for a GLOBAL key |
| R-4 | MINOR | CONFIRMED | `docs/lsp.md:202-203` "References and highlight are correct on all of those" is false for the tab case, five lines above the paragraph that says so |
| R-5 | MINOR | CONFIRMED | `docs/lsp.md:118` "every ARGUMENT of an equation … at any depth" drops the three conditions the shipped split actually has |
| R-6 | MINOR | CONFIRMED | `docs/lsp.md:65-67` gives the wrong reason for the operator half of E7's cascade |
| R-7 | MINOR | CONFIRMED | `docs/lsp.md:51-52` promises a broken sibling's fix clears the importer "on the next check"; the server does not re-check dependents |
| R-8 | MINOR | CONFIRMED | `docs/lsp.md:327-334` omits the third `isIncomplete: true` case — the document whose first check has not landed |
| R-9 | MINOR | CONFIRMED | `editor/vscode/README.md:74,185` "the 180-file corpus" — the corpus is 253 files and the grammar test tokenizes 359 |
| R-10 | MINOR | CONFIRMED | `docs/lsp.md:222-225` states the dropped-line rule as "a separated signature"; the rule drops ANY statement outside the run |
| R-11 | MINOR | CONFIRMED | the same 33-vs-31 unit confusion is already in `tracker/TICKET-stdlib-findings.md:603,606` and the roadmap's 6.6 paragraph |
| R-12 | NIT | CONFIRMED | `docs/lsp.md:152` "chased through ANY re-export chain" — a multi-ancestor origin refuses instead, and there is a 32-hop cap |
| R-13 | NIT | CONFIRMED | `docs/lsp.md:183`'s "(a stdlib name)" hardens the one refusal message 6.3's second pass called misleading |
| R-14 | NIT | CONFIRMED | `docs/lsp.md:266-267` omits the intra-tier tiebreakers that make the workspace-symbol order total |
| R-15 | NIT | CONFIRMED | `docs/lsp.md:315-316` "not recognised as a module at all" — it IS recognised as qualified and answers `[]` |
| R-16 | NIT | CONFIRMED | ticket **E6** (the do-anchor blame gap, ACCEPTED at 6.1) appears nowhere in `docs/lsp.md`, though E7/E8/E9/E10 all do |
| R-17 | NIT | CONFIRMED | the stub rule that caused the RED (`0` for every capitalised static) is fixed at one site, not at the rule; the 9-provider COUNT is logged, not asserted |
| R-18 | NIT | CONFIRMED | `.vscodeignore` packages `test/**` and every `*.d.ts` into the vsix — inherited from 0.1.0, not a regression |
| R-19 | NIT | CONFIRMED | the doc's 1.86 s is the busy-machine end of today's range; the shipped tree measures 1.69–1.70 s at load ≈1.0 |
| R-20 | MINOR | CONFIRMED | **NEW, from the fix round**: the rewritten latency row says the interleaved pair was "on the same tree"; it was `78d860f` against the final tree, on the same MACHINE |

**R-1 — the completion row is a client round trip wearing a server-side label.**  `docs/lsp.md:477` reads
"a completion, server side | 6.5 ms | median of 10, prefix `f` at line 1504, 97 items".  6.5 measured that
exact row from the server's own standing log line at **2.5 ms** (`LSP3-6.5-COMPLETION.md:317`, reviewer
2.45 ms) and recorded **6.5 ms as the client round trip for the same row** (`:321`).  My run settles it: the
client round trip was 6.87 ms (median of 10) while the log lines for those same ten requests read 12.0, 4.9,
2.7, 2.5, 2.3, 1.9, 2.1, 1.7, 1.8, 1.6 ms — a warm server median of ≈2.2 ms.  The measurement is fine and
the number is honest for what it is; the LABEL is wrong, and it is the one row in the table whose label
changes what a reader concludes (6.5's whole "50 ms bar" argument is about server time).  Fix: call it a
round trip, or quote the log line and put the round trip beside it.  The same qualifier was dropped from the
`documentSymbol` row, which its own source calls "the JSON round trip for the whole tree, not the build".

**R-2 — 68 + 49 + 33 is 150, and the doc presents it as 117.**  `LSP3-6.6-QUICKFIX.md:400-401` says it in
one sentence the doc did not carry: "the sweep now classifies every NAME each refusal cites (**117 refusals
cite 150 type names between them, so these are name occurrences, not groups**)".  The doc's bullet at
`:412-419` gives 68 (aliased) + 49 (unnameable) and then "**33 are a false negative**" — and because
68 + 49 = 117 exactly, the bullet reads as a closed partition that then overflows by 33.  The review's census
of the same class in GROUPS is **31** (`LSP3-6.6-REVIEW.md:128`: 29 groups naming `Scan`, 2 naming `Legend`),
which is what the roadmap's 6.6 paragraph records.  Nothing here is factually wrong in either document; the
two are in different units and neither says which.  Fix: "117 refusals, which cite 150 type names between
them: 68 … 49 … 33 …", and where the doc says "the scope test 33" (`:427`) beside "the printer 48" — 48 is
GROUPS (`LSP3-6.6-QUICKFIX.md:557`) — say "31 groups (33 name occurrences)".  R-11 is the same defect already
propagated into the ticket.

**R-3 — the rename staleness rule is stated one notch stricter than it ships.**  `docs/lsp.md:197-200`:
"ANY open document has been edited since its last check".  `References.scala:339-347` is
`val toVersion = if (isGlobal(key)) docs.all else docs.all.filter(_.uri == home.uri)`, with the comment "A
local key cannot leave its own file, so it checks only that one" — and 6.3 pinned exactly that in lsp-smoke
("a LOCAL rename in the same instant still succeeds").  As written the doc tells a user that renaming a
`let` binder is refused whenever any other buffer is mid-debounce, which is the behaviour 6.3 deliberately
did not ship, and it is the case that keeps rename usable while typing.  One clause fixes it.

**R-4 — a contradiction inside five lines.**  `docs/lsp.md:202-203` says "References and highlight are
correct on all of those, `` `literal` `` names included"; `:205-211` then says every range this server
produces — "a diagnostic, a definition target, a hover hit-test, **a highlight**, a symbol" — is seven
columns per tab to the right on a tab-indented line, which is why rename refuses.  6.3's second pass measured
it live.  The literal claim is right; the "all of those" is not, and the fix is three words ("except a name
behind a tab").

**R-5 — the equation-argument class is described without its conditions.**  `docs/lsp.md:118` promises
"every ARGUMENT of an equation, top-level or in a `where`, at any depth".  `TolerantCheck.scala:253-280`
records an argument only when: the head's type unfolds to exactly `arity` arrows (otherwise **nothing** is
recorded for that binding); the pattern is a bare `VarP` or an `AsP`'s outer var (so `f !x = …` and `~x`
answer null); and the domain is `mono` (a rank-N argument is skipped — the orchestrator's own pre-commit fix,
because Decision (a) forbids a `forall` on a local).  The roadmap's DONE paragraph states two of the three;
the doc states none, and its residual list at `:123-124` does not name them, so a reader is told those shapes
are covered.  The numbers (3156 / 5056 / 62.4 % / 1900) are all exact — this is wording, not arithmetic.

**R-6 — right conclusion, wrong mechanism, for half of E7.**  `docs/lsp.md:65-67` explains the surviving
cascade as "read- or type-phase diagnostics that carry no name, which is the flag the suppression rule keys
on".  True for `undefined type` (a guarded Death note with no `spelling`); false for the operator cascade,
which escapes because those three are `NewPipeline.Diag`s and **not Notes at all** — a note filter cannot
reach them however they are named (`LSP3-6.1-DIAGNOSTICS.md:176-177`, ticket E7).  "Neither is a note the
filter can reach" would cover both.

**R-7 — the one staleness the doc does paper over.**  `docs/lsp.md:51-52`: "Fixing a broken sibling in ITS
buffer clears the importing file's diagnostic on the next check, with no save anywhere."  6.1's review
records that the server does NOT re-check dependents of an edited buffer, so the importer's next check is
whenever the user next touches the importing buffer.  The doc's own header (`:13-15`) promises staleness is
"stated where it bites rather than papered over"; this is the one place it is not.

**R-8 — the third `isIncomplete`.**  `docs/lsp.md:327-334` gives two cases (empty prefix, cap bites).  The
shipped rule has three: 6.5's report and `Completion.scala:583` (`case None => (Nil, true)`) mark a document
whose first check has not finished as incomplete — which is precisely the boot case the doc describes three
paragraphs later as "an empty list, never null", without saying the client is told to ask again.  A client
author reading only this doc would cache the empty list.

**R-9 — "the 180-file corpus", twice, in the extension README** (`:74`, `:185`).  The checked corpus is 253
files (161 stdlib + 92 examples) — `docs/lsp.md` says 253 consistently — and the grammar test does not use
that corpus at all: it globs both trees unfiltered, and my run printed "**359 files, 36800 lines**".  The
substantive claims around both mentions (one tab-bearing file; the tokenizer runs over the whole corpus) are
right; only the label is stale.  It survives in `LSP3-6.6-QUICKFIX.md:21` too, harmlessly.

**R-10 — the dropped source line has more than one cause.**  `docs/lsp.md:222-225` attributes it to "a
signature separated from its equations by another group" and names two idioms.  The shipped rule drops any
statement outside the anchor's contiguous run; 6.4's second pass named a third legal producer the doc does
not — a fixity declaration between a signature and its equation.  Legal Ermine, absent from the corpus, and
one clause ("any statement outside that run") covers it.

**R-11 — the unit confusion is already downstream.**  `tracker/TICKET-stdlib-findings.md:603,606` says "33
refusals" and "(5) returns 33" for the class the 6.6 review counted as 31 groups; the roadmap's 6.6 paragraph
says 31.  Out of this item's scope to edit (and I edited nothing), but the number the orchestrator writes
into G3 should be the one with units on it.

**R-12 … R-19** are one-liners in the table above and need no paragraph; R-17 is the only one I would act on
soon — the stub's generic rule will produce the identical RED the next time the client dereferences a vscode
class the stub does not model, and this item's own experience is the argument for fixing the rule rather than
the site.

### What I checked and found clean (no finding)

`git diff -- core/src` empty · every one of the ten stale-number candidates (82, 98, 185, 207, 233, 237, 306,
344, 386, 407) absent from both `docs/lsp.md` and the README, as are the old latency figures 1.57 / 0.80 /
0.45 / "~13 s" / "2157 names, ~40 ms" · the harness paragraph's 454 / 8 groups–66 checks / 85-69-0-of-154 all
match my runs · 6.2's 62.4 % and its four residual classes, the letter-agreement note in both directions, the
kinds and the fast-mode null · 6.3's local/global keys, re-export canonicalisation, `import M using n`
entries, alias mentions, the coverage warning's wording, both incomplete-without-refusal cases, and all nine
Decision (d) refusals (the doc has exactly nine bullets and every refusal in the report appears; only the
boot refusal is unlisted) · 6.4's post-fix range rule, the sibling-overlap claim with the right example, the
17-row kind table row for row, the workspace sources/exclusions/cap/empty-query/2157 · 6.5's four contexts,
four module-name sources (Decision (c) as amended), the refuted-and-fixed qualified-insert mechanism, the
alias affix form, the type/constructor double offer, the three `Module.` limits, ranking, the 1332-name /
176 KB measurement (which matches 6.5's own prose exactly), the 300 cap, type variables, staleness · 6.6's
six-case import table, MaxImports 8 alphabetical, `isPreferred`, the 142-of-161 CRLF count (verified by
`file` on the tree), the three non-goals, 1334 / 1166 / 1164 / 99.83 % against 95 %, PARSE-FAIL 0, TYPE-FAIL 2
alias-unfolded, the alpha-equivalence-up-to-kinds caveat and the 81 %/145 text-comparison note, 117+36+10+3+2
= 168, staleness REFUSED, `context.only`, literals never Commands, no `codeAction/resolve`, the tab refusal
with no corpus group in that class · E8 and E9 stated where a user hits them, with E9 also inside the
transcript · the extension filtering nothing (`clientOptions` has no middleware, no capability override, no
feature list).

---

## 7. The fix list (FIX-THEN-ADVANCE)

Do these before the orchestrator writes the G3 evidence; all are prose in files this item already owns.

1. **R-1** `docs/lsp.md:477` — relabel the completion row as a client round trip, or quote the server's log
   line (≈2.2 ms warm, 6.5's 2.5 ms) with the round trip beside it.  Consider restoring "round trip" to the
   `documentSymbol` row while there.
2. **R-2** `docs/lsp.md:412-419` and `:427` — carry the report's units sentence ("117 refusals cite 150 type
   names"), and give the false-negative class as "31 groups (33 name occurrences)" beside the printer's 48
   groups.
3. **R-3** `docs/lsp.md:197` — say that a GLOBAL rename version-checks every open document and a LOCAL rename
   only its own file.
4. **R-4** `docs/lsp.md:202` — "correct on all of those **except a name behind a tab**".
5. **R-5** `docs/lsp.md:118` (and `README.md:43,80`) — state the equation-argument class with its conditions:
   a plain-variable argument, when the binding's own type shows `arity` arrows and the argument's type is a
   monotype.
6. **R-6** `docs/lsp.md:65-67` — "neither is a note the suppression filter can reach".
7. **R-7** `docs/lsp.md:51-52` — add that the importer is re-checked when it is next touched, not when the
   sibling is fixed.
8. **R-8** `docs/lsp.md:330-334` — name the third `isIncomplete: true` case.
9. **R-9** `editor/vscode/README.md:74,185` — "253-file corpus" / "the whole corpus (359 `.e` files)".
10. **R-10** `docs/lsp.md:222` — widen "a separated signature" to "any statement outside that run".

R-11 … R-19 are optional; R-17 deserves a ticket rather than a line.

## 8. What G3 asks for that is still NOT satisfied

I confirm the implementer's § 6a, with nothing added and nothing removed: **6.2 is PARTIAL** by its own
letter (3156 of 5056 = 62.4 %; the residual is the roadmap's FORK, and the doc names it); **E8** and **E9**
are user-visible and open, now written into the docs, the README and the transcript rather than absorbed;
**E7** (the operator/type cascade the suppression rule cannot reach) and the group-level 0:0 refusal are
documented residuals — I saw the 0:0 shape myself in the corpus run's `shouldfail_sk03` verdict; **6.6's ship
bar is met** (99.83 % against 95 %), so there is no shortfall there; and `npm run test:load` had been RED
since 6.6 landed for a test-harness reason nobody noticed, which is now green and, more usefully, now asserts
the registrations that would catch the next one.

---

## 9. The fix round, verified (added after §§ 1–8 were written)

While my Tier-2 run was in progress the implementer applied all ten items of § 7 to `docs/lsp.md` and
`editor/vscode/README.md` and appended a FIX ROUND paragraph to `LSP3-6.7-WIRING.md`.  I re-checked the tree
afterwards; no JVM was involved on either side, and the Tier-2 result is unaffected (nothing outside prose
moved — `git diff --stat -- core/src` is still empty, and the diff is still the same four files, now
903/114/6/59 lines).

| item | applied as | verdict |
|---|---|---|
| R-1 | `docs/lsp.md:505` now gives "**≈2.2 ms** server side, **6.5–6.9 ms** client round trip", with the log line named and 6.5's 2.5 ms cited; the hover and `documentSymbol` rows say "client round trip" | correct — ≈2.2 ms is the median of the ten log lines I measured |
| R-2 | `:435` "Those 117 refusals cite **150 type names** between them"; `:441` and `:451` "**31 groups (33 name occurrences)**" beside the printer's "48 **groups**" | correct, units now explicit on both sides |
| R-3 | `:213-216` a GLOBAL rename version-checks every open document, a LOCAL rename only its own file | matches `References.scala:339-347` |
| R-4 | `:218` "correct on all of those EXCEPT a name behind a tab", pointing at the column note | correct |
| R-5 | `:124-132` the equation-argument bullet now carries all three conditions (plain variable; `arity` arrows or nothing recorded; monotype domain) | matches `TolerantCheck.scala:253-280` exactly, including the `f !x` / `f ~x` case |
| R-6 | `:69-74` "Neither is a note the suppression filter can reach" — the operator's three are read-phase diagnostics, the type one a note with no name | matches `LSP3-6.1-DIAGNOSTICS.md:172-183` and ticket E7 |
| R-7 | `:51-56` the importer's squiggle clears only when the importer is next CHECKED; the server does not re-check dependents | matches 6.1's review |
| R-8 | `:353-355` the cap and the not-yet-checked document both set `isIncomplete: true` | matches `Completion.scala:583` |
| R-9 | README `:74` "253-file corpus", `:188` "the whole corpus (359 `.e` files)" | matches my grammar-test run's own count |
| R-10 | `:241` "any statement outside that run is left OUT of the range", with the fixity declaration named | matches 6.4's second pass |
| R-19 | `:501` the row now reads "≈1.7 s quiet, ≈1.9 s busy" with both load figures and both splits | good, and it quotes my pair |

**R-20, the one thing to correct before this is quoted as G3 evidence.**  That same row ends "The gap is the
machine, not the build: an interleaved pair **on the same tree** measured 1.759 s before / 1.694 s after."
The pair was not on one tree — that reading makes the experiment vacuous.  It was a build of the Stage-3
opening commit `78d860f` (before) against this tree (after), on the same MACHINE, interleaved
B/A/B/A (§ 1a).  Replace "on the same tree" with "against a build of the Stage-3 opening commit".

With that one clause fixed, I have nothing further: the docs then describe what shipped, and the gate numbers
in § 5 are the ones to write into "Gate evidence (G3)".
