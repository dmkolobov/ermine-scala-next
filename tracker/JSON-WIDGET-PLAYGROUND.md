# JSON widget playground: edit a widget, see it rendered, inside VS Code

> **STATUS: WP-1, WP-2, WP-3, WP-4, WP-5 (STAGES A, B AND C) AND WP-7 (WITH Q15's SERVER-SIDE
> `reason` KEY) ARE BUILT. WP-6's COOPERATIVE CANCEL WAS BUILT (stage 1, `b7b93daa`), MEASURED
> (stage 2, `02787f99`) AND IS NOW REMOVED FROM THE TREE (WP-24, 2026-09-20, BY THE USER'S
> DECISION). EVERYTHING ELSE IS DESIGN ONLY.**
> **WP-24, 2026-09-20 (evening), THE USER'S DECISION.** On the in-evaluator cancel: *"That
> sounds super sketchy."* They chose instead to ACCEPT the wedge and contain it in the CALLER,
> and then confirmed that the cancel instrumentation inside general Ermine evaluation is to be
> REMOVED. So `Runtime.scala`, `lsp/Preview.scala`, `session/Lib.scala` and `session/Session.scala`
> are restored to their `0a092242` content (byte for byte, MEASURED by blob hash) and
> `scalacheck-binding/src/main/scala/TestPreviewCancel.scala` is deleted. **NOTHING OF THE
> MECHANISM IS IN THE TREE**: no `Cancelled`, no `cancelTarget`/`cancelWhy`, no `swhnf` head
> check, no five catch arms, no `ermine.preview.cancelOnTimeout`, no two-phase watchdog. **THE
> WATCHDOG IS AGAIN EXACTLY WHAT IT WAS AT `0a092242`: ONE PHASE -- `fire`
> (`Preview.scala:2069`) claims the job under `lock` and does the stuck mark, the `seq` mint, the
> drain and the notification INLINE. (`fireStuck` is not a method in this tree: `b7b93daa` minted
> that name when it split `fire` in two, and the split went with it.)**
> **WHAT REPLACES IT IS WP-22 -- the wedge guard, EXTENSION ONLY. ITS LETTERS (a) AND (b) ARE
> BUILT AS OF 2026-09-20 (extension 0.1.6, `editor/vscode`, JavaScript AND DOCS ONLY -- no Scala,
> no server, no wire change); ITS LETTER (c) -- the extension-owned restart after a grace -- WAS
> CONFIRMED BY THE USER (2026-09-20, ~23:50: *"the extension may restart."*) AND IS **NOW BUILT
> TOO, 2026-09-21, AS THIS TICKET'S STAGE 2** (extension 0.1.6 -> **0.1.7**, again JavaScript AND
> DOCS ONLY -- no Scala, no server, no wire change). **ITS SETTING IS
> `ermine.preview.restartAfterStuckSeconds` (the design review called it
> `killAfterStuckSeconds`; "restart" is what it does) AND ITS DEFAULT IS 0 = NEVER, SO OUT OF THE
> BOX NOTHING RESTARTS ANYTHING.** The default is OFF because the design review advised OFF until
> the manual checklist has been run once in a real editor and **THE USER CONFIRMED THE MECHANISM,
> NOT THE DEFAULT, AND HAS NOT BEEN ASKED ABOUT IT** -- the orchestrator will ask.
> `tracker/WP-7-MANUAL-CHECKLIST.md` §2.28-2.32c are the TEN steps that would observe it and, like
> every other step in that file, NONE HAS BEEN RUN.**
> **FIVE DECISIONS THE USER MADE ON 2026-09-20 (~23:50) ARE FOLDED IN BELOW, each where it
> belongs and each quoting them exactly**: the prompted database password lives in the extension
> host's memory for the editor window (§8's amendment, §7.2, WP-13, WP-14); WP-22(c) above;
> **WP-25 (*"harden unloading"*) and WP-9 (*"do a second worktree for the bundle"*) ARE BEING
> BUILT NOW IN SEPARATE WORKTREES** -- `ermine-scala-wt-wp6-perfA`/`wp25-scrub` and
> `ermine-scala-wt-wp9-bundle`/`wp9-bundle` -- **neither is built, reviewed or merged, and
> nothing of either is in this worktree** (**BOTH CLAUSES SUPERSEDED 2026-09-21: WP-9 merged at
> `cdd90193`, WP-25 at `c73d4e7c` -- see the two amendments below**); and Q19 is decided:
> `'unsafe-eval'` in the PREVIEW
> WEBVIEW's CSP only (*"oh yeah unsafe-eval sounds great. We'll remove it later on if need be"*),
> with WP-9's own bundles still required to contain no `eval`. **Side worktrees write their own
> as-built notes and do not edit this document; their rows are amended at merge.**
> **AMENDED 2026-09-21: WP-9 IS NOW BUILT, REVIEWED AND MERGED, so "neither is built, reviewed
> or merged" above now holds for WP-25 ALONE.** (**SUPERSEDED LATER THE SAME DAY BY THE WP-25
> AMENDMENT BELOW: IT NOW HOLDS FOR NEITHER.**) WP-9 -- the webpack browser bundle and the
> panel's presentation reducer skeleton -- was built on `wp9-bundle` as `c2c83cdb`, reviewed
> **DESIGN GREEN / IMPLEMENTATION GREEN** by an independent reviewer, and merged into
> `widget-preview` at `cdd90193`. Its as-built note, `tracker/WP-9-AS-BUILT.md`, is **FOLDED
> INTO THIS DOCUMENT** (§5's Bundle, `devtool`, writers-global, Host-page-logic, Stuck and
> checklist rows and its findings block; §11's Host page row; §13's Q1; §14's WP-9, WP-10,
> WP-11 and WP-17 rows), **and this document is the authority from here on.**
> **NOTHING IN WP-9 HAS RUN IN A BROWSER OR IN A VS CODE WEBVIEW.** No CSP has been enforced
> against these bundles by anything, no panel has loaded them, and §5's third bundle-checklist
> row ("`table` renders through the writers global") is untouched and still human -- it is no
> longer blocked on a DECISION, Q19 having been taken, only on a browser. Every WP-9 figure in
> this document comes from `node`, `webpack` and `node --test` on this machine.
> **TWO OF ITS DESIGN CHOICES ARE THE ORCHESTRATOR'S, NOT THE USER'S, AND BOTH ARE REVERSIBLE**:
> tsc-first instead of `ts-loader` (webpack's input is the `tsc` output) and two webpack entries
> rather than one. **The user's decisions about the bundle are three**: webpack itself, the
> second worktree (*"do a second worktree for the bundle."*) and Q19.
> **AMENDED 2026-09-21 (later the same day): WP-25 IS NOW BUILT, REVIEWED AND MERGED TOO**, so
> "neither is built, reviewed or merged" holds for NEITHER side worktree -- both have landed, and
> **BOTH THEIR AS-BUILT FILES ARE NOW FOLDED IN: WP-9 earlier today, WP-25 now.** WP-25 --
> `Session.scrub` made safe for ANY set of modules, the user's *"harden unloading."* (§13, Q20) --
> was built on branch `wp25-scrub` (worktree `ermine-scala-wt-wp6-perfA`) as `ee093b46`, reviewed
> by an independent reviewer over TWO passes -- **RED** on the origins-coverage claim, then
> **DESIGN GREEN / IMPLEMENTATION GREEN** after the reviewer ran its own DROP and FILTER controls
> and conceded both disputed points -- and merged into `widget-preview` at `c73d4e7c`. **THE `pr`
> GATE IS GREEN ON THE MERGED TREE** (MEASURED, content key
> `3f07799de8b3ee6376c808c805dd84cbbfd3d427`, read from `.gate-cache/`): compile PASS; corpus PASS
> (89 loaded / 79 rejected / 0 unknown of 168, 0 differ from expected); lsp PASS **641 checks**;
> suites PASS **`Passed: Total 1292, Failed 0, Errors 0`** in 675 s. **`lean` IS UNAVAILABLE IN
> THIS WORKTREE** -- there is no `tracker/lean/.lake` here, so that gate answers "unavailable"
> instead of a verdict (READ, `scripts/gates.sh:144`): neither green nor red. Its as-built note,
> `tracker/WP-25-AS-BUILT.md`, is **FOLDED INTO THIS DOCUMENT** (§11's new "Session scrub (WP-25)"
> row and the Render-session row's *"the product half is WP-25"* sentence; §13's Q20; §14's WP-25
> and WP-26 rows and the new WP-28), **and this document is the authority from here on.**
> **WHAT WP-25 DOES NOT DO IS IN ITS §14 ROW, UNDER "KNOWN, MEASURED LIMITS"**: "safe" means no
> name outlives what it names and every module can still be read, and NOT "not stale"; after a
> scrub of a NON-importer-closed set `lsp/Definitions.canonWith` can answer an INCOMPLETE RENAME
> (two keys, MEASURED, and no fix exists); nothing exercises `Resident.reloadModules` against a
> real widening; and the REPL's `:reload` was not run. **WP-26 IS RE-SCOPED, NOT CLOSED, AND IS
> STILL NOT BUILT** (§14).
> What (a)+(b) are, where they live and what was tested is
> in WP-22's own row (§14) and in Q17; **every claim about VS CODE's behaviour in them is
> UNOBSERVED BY ANYONE** -- `tracker/WP-7-MANUAL-CHECKLIST.md` §2.15-2.27 is the list to tick and
> says so at the top. Q13 is RE-OPENED AND RE-DECIDED (§13). Everything below about WP-6 is
> KEPT as the design record of what was built and measured, each place saying so; stage 2's
> figures (§11) stay as the measurement they were, and `tracker/tools/eval-bench.sh` stays.
> **AS BUILT ON 2026-09-20, AND KEPT HERE AS THE RECORD OF WHAT WAS REMOVED:**
> **WP-6 (cooperative cancel) was FUNDED by the user on 2026-09-20, as Q13's option (ii), and its
> STAGE 1 -- the mechanism -- is BUILT behind `ermine.preview.cancelOnTimeout`, DEFAULT FALSE.
> STAGE 2 -- the evaluator perf instrument -- IS BUILT AND RUN (2026-09-20), AND ITS WRITE-UP WAS
> REVIEWED (DESIGN RED / IMPLEMENTATION RED) AND CORRECTED WITHOUT RE-MEASURING:
> `tracker/tools/eval-bench.sh`, an interleaved A/B over two worktrees with the editor closed.
> **ITS FIGURES ARE IN §11's Instruments section, and what they support is weaker than the first
> write-up said.** On the ordinary build-and-fold workload the stage 1 commit is not
> distinguishable from the machine; on the `swhnf`-densest workload -- re-folding a list whose
> cells are already `Evaluated` -- **W2 moved +5.8 % and +4.9 % in the same direction in two runs
> with the pair order reversed, every estimator agrees in sign, a central estimate is about +5 %,
> and NO test on 5 forks per side reaches conventional significance** (stratified permutation
> p = 0.089, Mann-Whitney p = 0.095, bootstrap CI includes zero). **The instrument SUGGESTS a
> cost of roughly 5 %; it does not ESTABLISH one**, and the delta belongs to the whole stage 1
> commit rather than to the one volatile load. STAGE 3 (ADOPTION, which is flipping that default)
> is NOT built and is the USER's call; note that the flip adds no PER-FORCE cost, because the
> check is in the binary either way -- though it is not behaviourally free, since with the switch
> on a taken cancel DISCARDS the render session unconditionally and the watchdog becomes
> two-phase, with `isFatal`'s documented exception riding on that discard (§14(d) and (f), §11).
> Stage 1 was built to the DESIGN REVIEW's shape and not to §14's earlier letter, in four places
> that row now names.**
> No other ticket has been started. WP-5 was built in three reviewed
> stages. **THREE DEVIATIONS from its §14 row, each named in full rather than folded away:**
> (i) the row's last done-when reads "an allocating loop ends in a clean exit the client
> restarts", and only the CLEAN EXIT half was exercised (measured: exit code 3, §2.5); "the
> client restarts it" is `vscode-languageclient`'s documented behaviour (*external*, up to
> 5 times in 3 minutes) and nothing in this repository runs VS Code, so it is asserted from
> the documentation and NOT measured.
> (ii) "heap after a watchdog fire (allocating and NON-ALLOCATING loop)": the allocating case
> is measured, the non-allocating case **has no witness**. Two `swhnf` loops that should have
> had a constant live set both reached `-Xmx` and exited instead, and the one candidate for a
> loop INSIDE a primitive (catastrophic regex backtracking) did not spin on JDK 21. So the
> row's "non-allocating loop" was measured as far as it can be here, and what it measured is
> that the case could not be constructed -- §2.5 says so with its numbers.
> (iii) the row also says "and the `ermine.maxHeap` setting". Only the SERVER end is built:
> the launcher honours `ERMINE_LSP_XMX`. The VS Code setting and the export that would give
> it a value are DEFERRED TO WP-7. The justification is that a setting with no export is
> inert -- both halves live in `editor/vscode` and are one change -- not that WP-7's row
> claims them; WP-7 is simply where they now are. No `editor/vscode` file is touched by WP-5.
> What each built ticket is, and the only files it changes --
> this document aside, which every ticket touches:
>
> - **WP-1**: `send` synchronised, `onRequestDeferred`, `$/cancelRequest` routed, the incoming
>   log line moved after the parse and redacted by method; the `TestLspRobustness` A group.
>   Files: `Rpc.scala`, `TestLspRobustness.scala`.
> - **WP-2**: `scrub` and `dependentsOf` lifted from `Resident` into `Session` with `builtins`
>   a parameter; `Resident` calls them at its four sites. Files: `Session.scala`,
>   `Resident.scala`.
> - **WP-3**: `SessionEnv._registerDecls`, default on and carried by `copy`; the registration in
>   `processTypeDefComponent` consults it; `Resident.withEnv` -- the one per-request copy site
>   -- takes a `copyNotRegistering` copy; the one `TestLspRobustness` D property. Files:
>   `SessionState.scala`, `Session.scala`, `Resident.scala`, `TestLspRobustness.scala`.
> - **WP-4**: `Runner` with `reports` keyed by `(module, binding)`,
>   `report`/`compile`/`render`/`renderText` per pair with `cfg.reportName` still the HTTP
>   route's default, `paramSchema(module, binding)`, `Runner.resultKind` public on the
>   companion, a `builtins` snapshot after the runner's own preamble, and
>   `invalidate(paths): Set[String]` under `evalLock` -- scrub the closure, evict `reports`, no
>   eager reload; `Backends.scannerFor(dialect, variant)`; `lsp/DelegatingRun.scala`; the four
>   `TestRunner` properties of §11's "Runner" row. Files: `json/Runner.scala`,
>   `backends/Backends.scala`, the new `lsp/DelegatingRun.scala`, `TestRunner.scala`, and --
>   for the review's layering item only -- `Session.scala` and `Resident.scala`, where
>   `normalize`, `moduleUnder` and `loadedByPath` move into `Session` beside
>   `dependentsOf`/`scrub` and `Resident` keeps forwarders, so that `json` does not import
>   `lsp`.
> - **WP-5 stage A**: the preview thread and the `Preview` object in `lsp/` -- one daemon
>   thread owning the render session, lazy boot of the `Runner` on the first `ermine/render`
>   with the roots of §2.4 and a local in-memory SQLite behind a `DelegatingRun`,
>   `ermine/render` answered through `onRequestDeferred` with §4's two shapes (`uri` ->
>   module, `inferredRoot`, absolute `roots`, the root-change discard, 404 / 400 / 503, no
>   JDBC URL in a message), the queue of §2.5 (one in flight, at most one queued render,
>   latest wins, `-32800` for the replaced one, jobs in queue order, `generation` echoed),
>   `$/cancelRequest` for a queued and for an in-flight render, the mtime scan at the head of
>   every render, the `stale` counter, and `invalidate` posted from `afterReload` with
>   `ermine/preview/invalidated`; the `TestLspRobustness` D render-session properties.
>   The preview thread cannot end abnormally (a pre-allocated last-resort answer in a
>   `finally`, every step of the crash handler guarded, a bounded outer catch-all, and a
>   render refused with an error rather than queued if the thread is gone), and every line
>   it logs is scrubbed of JDBC URLs by construction (rule A5 covers logs).
>   Files: the new `lsp/Preview.scala`, `Rpc.scala` (a deferred handler that is given the
>   request's id, and the `-32800` constant), `Documents.scala` (`pathFor` lifted to the
>   companion), `json/Runner.scala` (`invalidateStale`), `Main.scala` (the install and the
>   `afterReload` post), `TestLspRobustness.scala`.
>   NOT stage A, and named as seams in `Preview.scala`: the watchdog and the "stuck" state,
>   `ermine.preview.maxDocumentBytes`, `ermine/schema {binding}` on the queue,
>   `ermine/preview/reports`, work-done progress (stage B, below); the launcher's `-Xmx` and
>   `ermine.maxHeap`, the `lsp-client.py` smoke and the measured instruments (stage C);
>   profiles, `connect`, `disconnect` and the held connection (WP-13, WP-14).
> - **WP-5 stage B**: the five things stage A named as seams.
>   (1) THE WATCHDOG AND THE STUCK STATE (§2.5): a daemon `java.util.Timer`, created by the
>   first arming and not before, armed when a job that owes an answer starts. THE CLOCK
>   COVERS THE EVALUATION AND NOT THE BOOT: the boot is bracketed -- disarmed as it begins and
>   re-armed as it ends, however it ends -- for a render and for a schema alike, because §2.5's
>   watchdog row is about "a non-terminating evaluation" while the boot is a row of its own
>   with its own progress report, and a boot is seconds (Q6 measures 2.3-7.3 s) that the
>   timeout's wording does not account for. Each arming carries an epoch, so a task whose
>   `cancel()` lost the race into `run` does nothing. After
>   `ermine.preview.timeoutSeconds` (default 60) the in-flight request is answered with a 500
>   "evaluation did not finish", the preview is marked STUCK, EVERY JOB ALREADY IN THE QUEUE
>   is answered with the same refusal in its own shape (the thread is wedged, so nothing else
>   would ever read them), and every later `ermine/render` and `ermine/schema` is answered
>   the same way WITHOUT queueing -- with the message the arming that FIRED was built from,
>   repeated, not rebuilt from a setting that may have changed. The
>   watchdog's answer and the job's own cannot both reach the wire or the log: one claim
>   under the queue's monitor decides which, with `Rpc.Answer`'s one-shot as the backstop.
>   The notification is `window/showMessage` (LSP's own server-to-client notification) from
>   the timer thread through the synchronised `send`, as §4 requires ("the render watchdog
>   therefore uses a `Timer` thread and the synchronised `send`, not the idle slot"); it NAMES
>   the **Ermine: Restart Language Server** action (`ermine.restartServer`) in its text rather
>   than carrying it as a clickable item, because the LSP shape that carries actions
>   (`window/showMessageRequest`) is a REQUEST and `ask` is dispatch-thread-only (§2.3). The
>   button itself is the panel's banner, WP-7, which is where resolution A4 already put it.
>   (2) `ermine.preview.maxDocumentBytes` (default 16 MB, §2.3), counted in UTF-8 bytes over
>   the writer's buffer -- no second copy of an over-large document -- and answered 500
>   "document too large for the panel" before `send`.
>   (3) `ermine/schema` WITH A `binding` KEY is a preview-queue job answered by
>   `Runner.paramSchema` from the render session (§6); the `type`/`name` forms still answer
>   synchronously from the resident. A schema job is an `Answering` like a render, so cancel,
>   shutdown and a dead thread all answer it; "latest wins" is a rule about renders, so a
>   newer render does not displace it. **SUPERSEDED BY THE Q7 FOLLOW-UP BELOW** (2026-09-20),
>   and left standing only as what stage B built: as stage B shipped it, a schema never
>   changed the root set -- it answered from the session a render had booted and boots one
>   over `ermine.moduleRoots` alone if there was none, because `ermine/schema` then carried no
>   `uri` and no `roots`. Since Q7 the request carries both, the `moduleRoots`-only fallback
>   is DELETED, and a schema computes and uses the same root set a render would -- which also
>   means a schema whose `roots` differ from the last render's discards the session and
>   re-boots, exactly as a render does.
>   (4) `ermine/preview/reports {uri}` (§3.2) on the DISPATCH thread, in `Definitions.scala`
>   beside the index it reads: the stored symbol tree's top-level term groups, filtered by
>   `Runner.resultKind` on the codomain after at most one `->` (retried on the type's normal
>   form, which is what expands an alias), rendered as hover renders a type. A file with no
>   index is checked once from disk, and the index of that check is not stored.
>   (5) BOOT PROGRESS (§2.5): `window/workDoneProgress/create` from the DISPATCH thread when
>   it enqueues a render and no session is up, then `$/progress` begin/end from the preview
>   thread around the boot, `cancellable: false`, guarded by the client's
>   `window.workDoneProgress` capability. No `$/progress` is sent for a token whose `create`
>   the client REFUSED -- PER TOKEN, so a client that refuses one create is asked again on the
>   next boot rather than written off -- and no second `create` is issued while an earlier one
>   is UNANSWERED, which means a client that never answers one turns boot progress off for
>   itself for the life of the server (the alternative is `Server.ask`'s continuation map
>   growing without bound). Either way the render proceeds; only the progress is lost. TWO BOOTS REPORT NOTHING, stated rather than
>   hidden: one that follows a root-set change INSIDE one render, because the dispatch thread
>   cannot predict it without doing preview-thread work (the inferred root is a file read and
>   a header parse) -- Q6's case; and one a SCHEMA job pays, because §2.5's progress row is
>   about renders and `ermine/schema` carries nothing the dispatch thread could key a token to.
>   **THE SECOND OF THOSE TWO IS NO LONGER TRUE** since the Q7 follow-up below: a schema now
>   carries a `uri` and `roots`, so it mints a token through the same `mintBootToken` and its
>   boot reports like a render's. Only Q6's case -- a root-set change INSIDE one render or one
>   schema -- is still silent.
>   Files: `lsp/Preview.scala`, `lsp/Definitions.scala` (the `ermine/schema` split and
>   `ermine/preview/reports`), `lsp/Main.scala` (the two settings, the capability, the
>   install order), `lsp/Rpc.scala` (one type alias), `TestLspRobustness.scala`.
>   NOT stage B: the launcher's `-Xmx`/`-XX:+ExitOnOutOfMemoryError` and `ermine.maxHeap`,
>   the `lsp-client.py` smoke and the measured instruments -- RSS, boot seconds and heap
>   after a watchdog fire (stage C).
>
> - **WP-5 stage C**: the launcher's heap policy, the smoke, and the measured instruments.
>   (1) `bin/ermine-lsp:20-84` adds `-Xmx${ERMINE_LSP_XMX:-2g}` and
>   `-XX:+ExitOnOutOfMemoryError`. THE TWO FLAGS ARE DECIDED SEPARATELY, on WORDS of
>   `ERMINE_JAVA_OPTS` and never on a substring of it: `-Xmx` is skipped when a word already
>   sets the maximum heap (`-Xmx...` or `-XX:MaxHeapSize=...`), while
>   `-XX:+ExitOnOutOfMemoryError` is ALWAYS added unless a word already names it with either
>   sign, because §2.5's whole recovery story depends on it (one line to reverse). §2.2's
>   sentence is ambiguous about that second flag and this is the reading, written down.
>   The word test is not decoration: a substring test on the variable made
>   `-Dermine.lsp.log=/tmp/-Xmx-logs/a.log` drop BOTH flags silently (the review's probe).
>   An `ERMINE_LSP_XMX` that is not a heap size (`^[1-9][0-9]*[kKmMgGtT]$`: a non-zero number
>   and a k/m/g/t suffix, which is what the JVM takes) is refused on stderr and `2g` used: a
>   launcher that refuses to start is a server the editor cannot run at all, whereas a bad
>   `-Xmx` inside `ERMINE_JAVA_OPTS` is the JVM's own to refuse ("Invalid maximum heap size",
>   exit 1, before any LSP frame).
>   Nothing else in the launcher moved: the classpath cache, `ERMINE_LSP_LOG` and the
>   `JAVA_HOME` search are untouched. **No other way of starting the server goes through it**:
>   `tracker/tools/lsp-smoke.sh`, `lsp-demo.sh` and `perf-client.py` build the `java` command
>   line themselves from `tracker/repl-classpath.txt`, and `TestLspRobustness` starts no
>   process at all, so the `lsp` gate is not affected by the cap and does not test it.
>   (2) `tracker/tools/lsp-client.py` gains §11's "End to end" row as twelve checks against
>   a COPY of `core/src/test/resources/doc/Sales.e` under a temp root of the run's own:
>   `ermine/preview/reports` lists `report : Query -> Node` and nothing else; `ermine/render`
>   answers `{ok:true, document, generation}`; the file is edited on disk and a
>   `workspace/didChangeWatchedFiles` event goes in, exactly as the staleness section's own
>   scenario does it; `ermine/preview/invalidated` names `Sales`; the second render's document
>   differs, and differs BY THE EDIT; `ermine/schema` answers `ermine:Sales/Query` with
>   `Query`'s four fields and three required ones (stage C sent `{module, binding}`; since the
>   Q7 follow-up below the same check sends `{uri, binding, roots}`, and one more check asks
>   for a second report's schema before any render of it). THE SMOKE NOW
>   DECLARES `window.workDoneProgress`, so the boot's `window/workDoneProgress/create` is
>   asked for and answered and the `$/progress` begin/end pair is checked; the second server
>   in that file declares no capabilities and is the negative case.
>   MEASURED: the gate went from 628 checks in 44.5 s to 640 checks in 46.7 s, so it stays a
>   `commit` gate (§11's rule was "if it passes ~90 s it moves to `pr`"); `scripts/gates.sh`
>   is unchanged.
>   (3) The instruments of §2.2 and §2.5 are measured and written there.
>   Files: `bin/ermine-lsp`, `tracker/tools/lsp-client.py`, this document. NO Scala, NO
>   `editor/vscode`, NO gate registry change.
>
> - **Q4 AND Q5 FOLLOW-UP (2026-09-20)**: the two open questions of §13 the user decided,
>   both built as option (i).
>   **Q4** (a follow-up to WP-4): `Runner` keeps a private PENDING-LOAD set -- the modules a
>   `compile` tried to LOAD and could not (a parse error, a type error, a broken import, a
>   file that vanished mid-load), bounded at `Runner.maxPendingLoads` = 32 with oldest-first
>   eviction -- and any `invalidate` whose paths name a module (a loaded one through
>   `loadedFiles`, or an UNLOADED one under a root) unions that set into its answer, so the
>   save that FIXES a broken report finally names it and `ermine/preview/invalidated` goes
>   out. A successful compile takes the module back out; a 404 for a module no root has and a
>   malformed module name are refused before any load and are NOT recorded, so §11's "(inv1)
>   `invalidate` of an unloaded path is a no-op" stays true whenever nothing is pending.
>   `invalidateStale` does NOT union the set: the render it heads retries the load anyway, and
>   the mtime scan must go on sending no notification. Known and accepted cost, written into
>   the code: while a report is broken, saving ANY `.e` file under a root costs one extra
>   render attempt of that report (up to 32 names can ride along on one `invalidate`).
>   `bin/ermine-serve` never calls `invalidate`, so its behaviour is unchanged. Two tightenings
>   from this follow-up's own review: `invalidate0` PRUNES loaded modules out of the set before
>   it reads it (a pending module can be pulled back in as another module's dependency), and the
>   pre-load 404 CLEARS a module whose file no root has any more.
>   **Q5**: `inferredRoot` STAYS in the root set (§2.4's zero-configuration promise) and the
>   404 is made honest instead -- "not an Ermine source file: <name>", "cannot read <name>",
>   "no module header could be read from <name>", or "the module header of <name> names
>   <module>, which is deeper than the directories above it" -- in place of "not under a module
>   root", which was true of nothing a readable file could do. The message names the FILE and
>   never a directory, and still goes through `failure`'s scrub; `generation` is echoed as
>   before.
>   Files: `json/Runner.scala`, `lsp/Preview.scala`, `TestRunner.scala`,
>   `TestLspRobustness.scala`.
>
> - **Q6 FOLLOW-UP (2026-09-20)**: the third open question the user decided, BUILT. The
>   render's root set no longer puts the picked report's INFERRED root ahead of
>   `ermine.preview.roots` when the CONFIGURED roots already place the file -- so two reports
>   in two configured directories give the SAME list and §2.4's discard-on-change stops
>   re-booting the render session on every switch. "Place" is two tests, and the second is the
>   sound one: the configured roots must name the path with the module name its own header
>   declares, AND must resolve that name back to THIS file, which is the question the LOADER
>   asks. Zero configuration is untouched, `ermine/schema` is untouched, and the SET of roots
>   never changes -- only the order, which is the behaviour change §2.4 records. Three
>   group-D properties. Riding along: `bin/ermine-lsp` gains a 64m FLOOR under
>   `ERMINE_LSP_XMX` (`1k` and `1m` are heap sizes by spelling and "Too small maximum heap" to
>   the JVM), and §2.5's and §2.2's instrument figures are corrected against their logs.
>   Files: `lsp/Preview.scala`, `TestLspRobustness.scala`, `bin/ermine-lsp`, this document.
>
> - **Q7 FOLLOW-UP (2026-09-20)**: the fourth open question the user decided, BUILT, in two
>   halves. (1) **THE BINDING FORM OF `ermine/schema` IDENTIFIES THE REPORT THE WAY A RENDER
>   DOES**: `{uri, binding, roots}` -> the schema or `{error}`, resolved by ONE shared function
>   (`Preview.placeAndSession`) that a render and a schema both go through -- path from the URI,
>   Q5's honest reasons, `rootSet` with Q6's rule, `ensureSession`, the mtime scan, `moduleUnder`
>   -- so the two cannot drift, they share ONE session in either order, and §6's first-pick order
>   (schema, then render) works for a workspace module. `ensureSchemaSession` and its
>   `moduleRoots`-only fallback are GONE, with both of the stage B review's consequences; the old
>   `{module, binding}` form is NOT kept (a request with `binding` and no `uri` is an `{error}`
>   naming the key), because no extension code depends on it yet and keeping it would keep its
>   wrong-module hazard. **The `type`/`name` forms on the resident are untouched.** A schema that
>   will BOOT now mints a boot progress token through the very same dispatch-side
>   `mintBootToken`, under the very same at-most-one-outstanding-`create` rule -- so §2.5's
>   "TWO BOOTS REPORT NOTHING" loses its second case, and only Q6's root-change re-boot is left
>   silent. Watchdog, queueing, cancel, stuck, shutdown, the boot bracket and the arm epoch are
>   UNCHANGED and were verified, not re-designed. (2) **A SHADOWED PICK IS AN ERROR, NOT A SILENT
>   SUBSTITUTION**: the resident's `moduleRoots` keep LEADING the chain (§2.2 wants equal
>   shapes), but when the FINAL root set resolves the picked file's module name to a DIFFERENT
>   file -- the loader's own first-existing-file rule -- the render answers
>   `{ok:false, status: 409, message, generation}` and the schema `{error}` with the same text,
>   naming both files and the root that shadows, before any load. Files: `lsp/Preview.scala`,
>   `lsp/Definitions.scala` (one comment), `TestLspRobustness.scala`, `tracker/tools/lsp-client.py`,
>   this document.
>
> - **Q8, Q9, Q10, Q11 AND Q12 FOLLOW-UP (2026-09-20)**: five more open questions the user decided ("per the
>   orchestrator's recommendations"), each as CHANGED BY AN INDEPENDENT DESIGN REVIEW that ran first and
>   rewrote three of them. **Q13 is untouched and stays the user's.**
>   **Q8** (BUILT): a STUCK-ONLY `"stuck": true` marker on exactly four answers -- the two refusals `render`
>   and `schema` send while stuck, the watchdog's own, and its queue drain's -- through a second
>   `Answering.stuckRefusal` method, so the job CRASH handler's 500 cannot carry it (the review's must-fix:
>   the first recommendation put the flag on the shared `refusal`). Plus `ermine/preview/stuck
>   {stuck, message}`, a new §4 notification, sent BESIDE the existing `window/showMessage` and never instead
>   of it. The `-32800` paths carry no marker and cannot: a JSON-RPC error has no result object.
>   **Q9** (PROSE ONLY, no mechanism, one cheap property): `0` stays the off switch; the question's own claim
>   that the group-D properties need the SETTING is struck (they set the FIELD); nothing sends these settings
>   until WP-7 (VERIFIED: `extension.js` sends `fastMode` only).
>   **Q10** (BUILT): `stuck` clears when the job the watchdog fired on RETURNS -- never on a `java.lang.Error`
>   (`e.isInstanceOf[Error]`, chosen over `NonFatal`, which calls an `AssertionError` non-fatal) -- silently
>   while stopping, with the late job's own answer still discarded, and with a notification that asks for a
>   re-render because every `invalidate` of the wedge was dropped. `dirtyGeneration` is NOT bumped, and Q10's
>   text says why it would be inert.
>   **Q11** (NOTHING BUILT): the orchestrator's server-side recommendation was WITHDRAWN by the review and the
>   case is the extension's (WP-7, §3 step 6); the two reasons are recorded in Q11.
>   **Q12** (MEASURED, then BUILT, step 1 only): `-XX:+DisplayVMOutputToStderr` moves the VM's OOM
>   termination line off fd 1 -- measured on the `WpBlow` fixture, stdout ends at the last complete frame and
>   stderr, EMPTY before, carries the line -- and `bin/ermine-lsp` now adds it behind a cached one-off probe
>   keyed on the java binary. NO descriptor duplication -- nothing in this repository goes through the
>   launcher, so a second wire descriptor would ship untested on the one path a mistake in it
>   would break everything (an earlier portability reason was WITHDRAWN: `bin/ermine-lsp` is
>   itself bash, so on Windows neither mechanism ships today -- that is WP-17's gap). Q12 is NOT moot under any Q13 outcome: the measured run died BEFORE any fire.
>   **THE BATCH'S OWN DESIGN+IMPLEMENTATION REVIEW (2026-09-20) WAS RED AND CHANGED THREE
>   THINGS**, each folded into the texts above: (DM-1) "a job that came back of its own accord
>   poisoned nothing" was FALSE -- `Runtime.swhnf` memoises a `NonFatal` throw into every thunk
>   on the chain, so a wedge that ends by an exception poisons the session's shared bindings,
>   exactly as §2.5's WP-6 row already says of a cancel; recovery now DISCARDS the render
>   session when the job THREW, and the same mechanism is recorded as new open question **Q14**
>   for the transient-failure case, which is not built; (DM-2) `isFatal` is
>   `isInstanceOf[Error] || !NonFatal(e)`, because `swhnf`'s only capture is `NonFatal` and the
>   complement escapes a force WITHOUT writeback, leaving whiteholed thunks that later read as a
>   permanent "infinite loop detected" -- `ControlThrowable` and `InterruptedException` are in
>   that complement and are not `Error`s; (IM-1) the two `ermine/preview/stuck` edges are sent
>   by two threads with nothing ordering them, so both now carry a monotonic `seq` minted in the
>   same locked step as the state flip, and §4 states the client contract (keep the highest
>   `seq`; the notification is authoritative; the answer marker is per-request; the
>   `window/showMessage` is advisory).
>   Files: `lsp/Preview.scala`, `json/Runner.scala` (one comment), `bin/ermine-lsp`,
>   `TestLspRobustness.scala`, this document. No `editor/vscode` file, no gate registry change.
>
> - **WP-7 (2026-09-20)**: THE EXTENSION'S HALF OF THE LOOP, WITH NO PANEL. Two commands
>   (**Ermine: Preview Report...**, a (file, binding) picker over `ermine/preview/reports` with
>   per-workspace memory and a free-text fallback; **Ermine: Render Report to JSON**), ONE untitled
>   JSON tab reused and updated in place, `ermine.preview.roots` (resource scope, absolutised against
>   the folder that owns the pick, the SAME list on `ermine/render` and `ermine/schema` by
>   construction), the generation counter and its discard, re-render on `ermine/preview/invalidated`,
>   Q11's own-file watcher, the stuck state (status bar + an error notification carrying
>   **Ermine: Restart Language Server**, the four client rules of §4 including the `seq` reset on
>   Stopped -> Running), "preview offline" and the re-send on Running, and the settings exports:
>   `ermine.preview.timeoutSeconds` ("0 = no watchdog" in its description) and
>   `ermine.preview.maxDocumentBytes` through BOTH routes the server reads, plus `ermine.maxHeap`
>   as `ERMINE_LSP_XMX` -- which closes WP-5's deviation (iii), the setting that had no export.
>   Version 0.1.5.
>   **THE SHAPE**: every decision is a pure function in the NEW `editor/vscode/src/preview-core.js`
>   (roots, generation, the stuck machine, both re-render rules, the three request builders, the
>   settings payloads, the heap spelling) with no `require("vscode")` in it, unit-tested by the NEW
>   `editor/vscode/test/preview-core.test.js` under `node --test` (30 tests, table cases plus a
>   generated-sequence check over the stuck machine's invariants); `src/extension.js` is glue.
>   Run it with `cd editor/vscode && npm run test:preview`; it needs no `node_modules` and no VS
>   Code. **NO new gate**: §11 puts client tests at `nightly` and `scripts/gates.sh` is unchanged.
>   Files: `editor/vscode/src/preview-core.js` (new), `editor/vscode/test/preview-core.test.js`
>   (new), `editor/vscode/src/extension.js`, `editor/vscode/package.json`, `editor/vscode/README.md`,
>   `tracker/WP-7-MANUAL-CHECKLIST.md` (new), this document, and -- for Q15 and one doc nit --
>   `lsp/Preview.scala` (the `reason` key, plus a comment on `evalFailed`'s over-coverage) and
>   `TestLspRobustness.scala`.
>   **NOT WP-7, and not built**: the webview panel and every banner state that needs one (WP-10),
>   params files, the skeleton and the `$schema` registration (WP-8), profiles, `connect`/`disconnect`
>   and the database password prompt (WP-13/WP-14; **no `SecretStorage` -- dropped 2026-09-20, §8's amendment**), the `.cmd` wrappers (WP-17).
>   **ONE SMALL SERVER CHANGE RIDES WITH IT, and it is the whole of Q15**: `lsp/Preview.scala` now
>   puts a machine-readable **`reason`** beside `status` on exactly the failures its OWN FRONT HALF
>   decides -- the placement ones -- from a closed vocabulary (`not-a-file-uri` 400;
>   `not-ermine-source`, `unreadable`, `no-module-header`, `header-deeper-than-path`, `not-placed`
>   404; `shadowed` 409), on the render shape and beside `ermine/schema`'s `error`. **A 404 out of
>   the `Runner` carries no `reason` at all, and that absence is the discriminator.** `Runner` and
>   `RunError` are UNTOUCHED, so `bin/ermine-serve` and every HTTP answer are exactly as they were.
>   Files: `lsp/Preview.scala`, `TestLspRobustness.scala` (the existing 404/400 property gains the
>   `reason` values, the Runner-404 negative and the schema shape).
>   **THE TICKET'S OWN done-when DID NOT SURVIVE CONTACT WITH THE SERVER, MEASURED with a Node
>   driver against a real `bin/ermine-lsp` (an instrument, not a gate; it is not in the tree)**: the
>   done-when's "a 400 naming `$.params.fromDay`" is NOT what a MISSING key answers -- `params: {}`
>   gives `{"status":400,"message":"the required key \"fromDay\" is missing", "path":"$.params"}`
>   and `params: null` gives `"expected an object (Query), found null"` at the same path, while
>   `$.params.fromDay` is the path of a key that is PRESENT and ill-typed (`{"fromDay": 5}` ->
>   `"expected a date string yyyy-MM-dd, found the number 5"` at `$.params.fromDay`), which is
>   WP-8's case. The letter would need a per-key path for a missing key in `json/Decode.scala`
>   (`:723-725`), which was NOT made -- the §14 row now carries the measured text and keeps the
>   original wording visible as "as first written". WP-7 therefore sends **`{}` and not `null`**,
>   because that is the shape that names the first missing key -- and the shape under which a report
>   whose parameters are all optional renders instead of being refused.
>   **NONE OF THE VS CODE BEHAVIOUR HAS BEEN OBSERVED BY ANYONE**: nothing here runs VS Code and the
>   extension was not installed, packaged or loaded into any editor. `tracker/WP-7-MANUAL-CHECKLIST.md`
>   is the list to tick, and says the same thing at the top.
>
> **Which suites were run, and what they said, is recorded in each ticket's commit message, not
> here**: a banner that names a suite goes stale the moment the next ticket runs a different
> set, and a claim about a suite THIS tree has not run is worse than no claim.
> The work lives on branch `widget-preview` in the worktree
> `ermine-scala-wt-widget-preview`, forked from `json-encode` at `739e161d`; this document is
> committed there. Every claim about this codebase is MINED from reading the source at that
> commit (2026-09-19) and carries a `file:line`; nothing was run or measured unless a row says
> MEASURED. Claims about third-party software (VS Code, vscode-languageclient, webpack, JDBC
> drivers, SQLite, SQL Server, the LSP specification) are tagged *external* and were not
> verified in this repository. Gates run against the worktree:
> `scripts/gate-tier0.sh -C widget-preview`, `scripts/corpus-sweep.sh -C widget-preview`, and
> the in-tree `scripts/gate.sh run commit|pr` from inside it.

## 0. What the preview is for

Two surfaces, one of which this document builds:

| Surface | What is edited | Rows come from | Oracle | In this document |
|---|---|---|---|---|
| **Widget and parameter work** | a widget module `Layout/Widgets/<Foo>.e`, its TypeScript renderer, the params a report is fed | inline literal relations (`Sales.e` imports `Relation` and defines `report : Query -> Node`, `core/src/test/resources/doc/Sales.e:107`; every relation in it is built from literal rows, `:111-117`, which the scanner emits as a `LiteralSqlTable`, `SqlScanner.scala:1034-1035`, through whatever connection is held) | SQLite in memory. The document *shape* -- widget names, props, layout -- does not depend on the dialect; cell values can differ only where §9.3 lists an engine difference | **yes, the whole loop** |
| **Relation / query authoring** | a relation that scans a real database | SQL Server | only SQL Server. SQLite is a best-effort stand-in, §9 | **only as a profile** (§7); the T-SQL diff view is optional and last (WP-19) |

The first row's honesty argument holds for literal relations. A report that reads `table`
declarations (`Session.scala:1695`) through `Layout.Fetch.scanRelation` (`Fetch.e:69`) needs
those tables to exist in the preview database: a file-backed SQLite the developer fills, or
an MSSQL profile (§7.1). The preview does not create tables and ships no seed-script
mechanism.

Scope: a developer edits (a) an Ermine widget module, (b) its renderer, (c) the parameters,
and sees the rendered document without restarting a JVM or running a build by hand. The
unit the preview shows is a **report**: a top-level binding of type `Node`, `Params -> Node`,
`Fetch Node` or `Params -> Fetch Node` (`Runner.scala:591-595`). Any such binding in any
module is previewable; nothing depends on what it is called (§3.2). Out of scope: deployment,
multi-tenant serving, class-constraint work (on hold), and the 2.11 back-port.

## 1. What exists, and what each edit costs today

| Surface | To see the result today | Why | Evidence |
|---|---|---|---|
| Ermine widget module | restart `bin/ermine-serve` (a JVM boot) and re-request | a module named by a request "is loaded on first use and stays loaded"; a working report "is cached forever; there is no `:reload`" | `json/Runner.scala:215-219`, `:296`, `:411-420`; `docs/JSON-GUIDE.md:1452-1453` |
| TypeScript renderer | `npm run build` (`tsc`), then nowhere to look: no host page, no bundle, no dev server | `client/` is CommonJS with `tsc` as its only build; nothing watches; the only `.html` in the repo is `docs/tutorial.html` | `client/tsconfig.json:5`; `client/package.json:11-18`, `:19-28`; `find` for `*.html` |
| zod for a new prop type | `npm run generate`: one `bin/ermine-schema --zod` per type, eleven JVM boots | the loop at `generate.sh:33-38` | `client/scripts/generate.sh:18-30`, `:33-38` |
| Parameters | hand-write JSON and `curl` it | `POST /report/<Module>` is the only way in, and it reaches one binding per module, `RunnerConfig.reportName`, default `"report"` | `json/Server.scala:16-18`, `:102-112`; `json/ServeMain.scala:13-26`; `Runner.scala:173`, `:445` |

`parseDocument` -> `render` has only ever run in jsdom under `node --test` with a stub
`htmlwriter` that records calls instead of drawing (`client/test/harness.ts:1-4`, `:31-42`);
the documented browser call is `client/src/index.ts:3-7`.

Assets the design stands on:

| Asset | Where | Used for |
|---|---|---|
| A resident session booted once (~13 s), interface-free, foreign-tolerant, watching `**/*.e` through the client and reloading changed modules plus dependents on the dispatch thread | `lsp/Resident.scala:14-18`, `:24`, `:118-121`, `:205-241`, `:251`; `lsp/Main.scala:199-208`, `:256-268` | the watcher event is the trigger of the loop (§3); the resident itself is **not** touched by the renderer (§2) |
| A per-document symbol tree built on the check path, each symbol carrying the check's inferred `Type`, rendered on demand | `lsp/Symbols.scala:120-122`, `:156-157`, `:287`, `:449-455`; `lsp/Definitions.scala:96-103`, `:1023-1026`; `Documents.scala:59` | listing a module's report-typed bindings for the picker (§3.2) |
| A custom request answered from that process, `ermine/schema` | `lsp/Definitions.scala:226-228`; `json/Schema.scala:800-815` | precedent for `ermine/render`; extended with a binding mode that the render session answers (§6) |
| `Runner`: boots its own `SessionEnv`, loads a module on demand, caches a working report, evaluates under a process-wide lock, scans outside it, inside ONE `cfg.run.run` | `json/Runner.scala:273`, `:287-288`, `:311-326`, `:411-420`, `:429-436`, `:495-496`, `:538-540`, `:624` | the render session **is** a `Runner` (§2) |
| `Runners.fromPersistentConnection(conn)`: a `Run[DB]` over one held connection | `backends/Backends.scala:49-51` | the preview's connection (§7) |
| `Scanners.MicrosoftSQLServer` / `...NoTransactions` | `backends/Backends.scala:26-27` | profile `scanner` knob (§7) |
| `Statement.setQueryTimeout(300)` on every prepared statement | `sql/SqlExecution.scala:47-50`; `backends/DB.scala:39-45` | the only bound a scan has today (§2.5) |
| `TestLspRobustness`: wire and dispatcher fuzz, a resident under mutation, reload properties | `scalacheck-binding/src/main/scala/TestLspRobustness.scala:168`, `:241`, `:455`, `:554`, `:583`, `:655` | where the render endpoint is property-tested (§11) |
| `tracker/tools/lsp-client.py`: `request()` and an `ermine/schema` section | `:57`, `:605-624` | the end-to-end smoke |
| Extension 0.1.4: LSP client over stdio, four commands, first-folder server path | `editor/vscode/src/extension.js:43-46`, `:49-55`, `:145-151`, `:179`, `:241-256`; `editor/vscode/package.json:5`, `:75-92` | grep for `createWebviewPanel`, `createFileSystemWatcher`, `secrets`, `isTrusted`, `untrustedWorkspaces`: 0 hits -- all new |

The LSP never touches a database today: no `Connection`, `Run[DB]` or `Scanner[` under
`core/src/main/scala/com/clarifi/reporting/ermine/lsp/` (grep, 0 files).

## 2. Decision: a second, render-only session in the LSP process, on its own thread

### 2.1 Where the render runs -- three options against the source

| Option | What it requires | What the source says | Verdict |
|---|---|---|---|
| **(A)** render on the dispatch thread, sharing the resident's env | `Runner` refactored over a foreign env | `Runner.booted` is not a constructor parameter: it rewrites `env.loadFile` (`Runner.scala:316`), re-runs `Lib.preamble` (`:318`), loads `Layout.Doc`/`Layout.Fetch` (`:319`) into an env built `_typeCheck=true, _useInterface=false` without tolerance (`:287-288`), whereas the resident is `_foreignTolerant = Some(true)` (`Resident.scala:118-120`). `Session.loadModules(List("Sales"))` (`Runner.scala:436`) would put workspace modules into the resident, which `tracker/LSP-STALENESS.md:40` rejects for `reloadChangedModules`. And the first preview would boot on the dispatch thread: `booted` is a constructor `val` (`:311`) | rejected: sound only after a refactor larger than the feature, and the workspace-module leak remains |
| **(B)** share the resident's env under a new lock ordered against `Runner.evalLock` | a lock taken by `reload`, `checkFile`, `ermine/schema` and the render | `SessionEnv.copy` reads eleven `var`s non-atomically (`session/SessionState.scala:95-113`); every `Runtime` in `env.env` is shared by copies and `Thunk.state` is a non-volatile `var` (`Runner.scala:257-260`); a runaway evaluation holding that lock would freeze diagnostics too | rejected: the lock would have to cover every check, so a slow render stalls typing anyway, and the copy-torn window stays |
| **(C)** a second session: the renderer keeps building its own `SessionEnv` exactly as `Runner` does today, booted lazily, invalidated by the same `**/*.e` events | proof that two sessions coexist in one JVM (§2.2) | `Runner` needs no constructor change: it already owns its env (`:287-288`). The resident is never read or written by the renderer | **adopted** |

### 2.2 Can two sessions coexist in one JVM? Every process-wide mutable object on the load/eval path

| State | Where | Written by | Two sessions | Verdict |
|---|---|---|---|---|
| `DataConDecl` registry: two `ConcurrentHashMap[Global, DataConDecl]` | `ermine/DataConDecl.scala:55-56`; `register` `:58-62` | four writers: the resident's boot and reloads (disk, `Resident.scala:126-127`, `:130`, `:214-215`); the render session's boot and `compile` (disk, `Runner.scala:315`, `:436`); both `Lib.preamble`s (`Lib.scala:45`, `:1472`); and **the editor's tolerant check**, which runs `Session.processTypeDefComponent` (`TolerantCheck.scala:862` -> `Session.scala:896`, `:915`) for every type declaration of the file being checked, reading the **open buffer** (`Resident.scala:412-413`; `Documents.scala:46`) on every debounced keystroke | Keyed by `Global(module, name)`; the file's own comment: entries are "facts about a declaration (module + name -> shape); reloading a module re-registers and overwrites ... Two sessions in one JVM defining the same module.name with different shapes (only the test fixture does this) see the last writer" (`:44-54`). Readers fall back to the registry only when the `Con` in hand carries no decl (`json/Schema.scala:240`, `:319`; `json/Decode.scala:232`, `:402`; `json/Encode.scala:631`) plus `Encode.userData`'s lookup for a runtime `Data` node, which has no env in reach (`Encode.scala:400`; `DataConDecl.scala:46-48`) -- the reader `toJson#` reaches (`Lib.scala:1478`), which three widgets use (`Scorecard.e:13`, `PieChart.e:23`, `StyleBox.e:28` import `Json`). The fourth writer is the problem: with `Chart.e` open and a field added to a props constructor but not saved, a render of the **saved** `Chart` meets the **buffer's** declaration; the guard `c.fields.length == args.length` (`Encode.scala:414`) fails, `named` is `None`, and the props encode as `{"tag", "args"}` (`:478-481`) instead of an object, which the renderer's zod refuses; a nullary constructor given a field in the buffer flips `isEnum` (`:401-404`) the same way. No invalidation fires for a `didChange`. **WP-3 silences that writer**: `SessionEnv` gains `_registerDecls` (default on; carried by `copy`, `SessionState.scala:113`, so `SessionTask.fork`'s copies inherit it, `SessionTask.scala:27`); `Session.scala:915` registers only when it is on; `Resident.withEnv` (`:143`, the one place every check copy is made) turns it off. A check copy's own readers are unaffected: the `Con` carries its decl (`Session.scala:923`) and Schema/Decode read the `Con` first; checks never evaluate, so `toJson#` never runs on a copy. After WP-3 every writer loads **disk content**, and entries from two sessions differ only in `Supply`-minted ids, which every reader is insensitive to (`Encode.scala:399-414` uses `isEnum`, `constructor(g)`, field names). The registry is already written from several threads inside one session's load: `loadMore` forks each module's make onto a cached pool (`Session.scala:639`, `:656`, `:672`; `session/SessionTask.scala:19-24`, `:26-37`), so a second session adds no new kind of write | **no collapse** once WP-3 lands. One window remains: between the resident re-registering a changed shape from disk and the render session reloading it, a render in flight can encode a `Data` node with the new field list. §2.5 makes that answer `stale` and the loop replaces it |
| `Supply` block allocator | `parsers/src/main/scala/scalaparsers/Supply.scala:7-10` (`synchronized`), `:18` | every `fresh` that exhausts a block | the resident has one supply (`Resident.scala:33`); `Runner` one per thread (`Runner.scala:280-283`); ids are globally unique by construction | fine |
| `Session.depCache` | `Session.scala:110`, "process-global" `:280` | every load, keyed by content-bearing `SourceFile` | already shared between the resident and every per-check copy; `Resident.reload` takes its dirty set from its own `loadedFiles`, not from the cache (`Resident.scala:160-166`, `:178-197`) | fine; the render session does the same (§3) |
| `SessionTask.pool`, a cached pool with no bound | `SessionTask.scala:19-24` | every parallel load | a render's module load and a check's import load compete for **cores**, not for threads; on a 4-core laptop a check slows while a render loads. `-Dermine.loadInSeries=true` (`Session.scala:682`) is the existing knob for a starved machine | stated; no code |
| `ForeignClasses.classMap` / `failureMap` | `parsing/ForeignClasses.scala:41`, `:52` | class lookups during load | a class missing for one session is missing for the other: same JVM | fine (mined, not run) |
| `Phases` | `session/Phases.scala:23-25`, `:42`, `:49` | inert unless `-Dermine.lsp.phases=true`; `record` is `synchronized` (`:43`) when on | a render in flight would add its load timings to the next check's phase line; nothing corrupts, and `perf-bench.sh` refuses to run while any ermine JVM is alive, the editor included (`docs/gate-policy.md:105`), so a preview cannot pollute a recorded figure | fine; stated |
| `Runner.evalLock` | `Runner.scala:624`, "PROCESS-WIDE" `:247`, `:298` | `Runner` only; the resident never takes it | stays that way: the resident is never blocked by a render | fine |
| `Lib` object-level values | `Lib.scala:165-192`: `Con`s and two constant `Data` nodes (`:168`, `:180`) | none after class init | already shared by the resident and its copies; no thunk among them | fine |
| `Type.Con.memoizedKindSchema`, a non-volatile `var` on `Con`s `Lib` shares | `ermine/Type.scala:231` | kind-schema memoisation on either thread | the write is idempotent | benign |
| `Runtime.Thunk.state` | `Runner.scala:257-260` | forcing | each session's `Lib.preamble` (`Lib.scala:1495`) installs its own primitives into its own env; no `Runtime` is shared across the two envs (mined: no object-level `Runtime` in `Lib` other than the two constants) | fine |
| JDBC `DriverManager` | `backends/DB.scala:107`, `:130` | `Class.forName` | process-global registry of drivers, read-only after load | fine |

The long-term shape is a per-session constructor index (a `decls` map on `SessionEnv` beside
`cons`, threaded into `Encode.encode`/`userData` through the primitive `Lib.json` installs
with the env in scope, `Lib.scala:1443`, `:1478`), which would make the static registry
test-only (`TestJson.scala:121`, `TestSchema.scala:754`, `TestNamedFields.scala:436` read it)
and shrink the `evalLock` rationale (`Runner.scala:614-619`) to `Supply` and `Thunk.state`.
It is about a day of threading a parameter through every JSON test and is **not** scheduled;
it becomes mandatory the day a second registry *reader* appears.

**Cost.** Two booted sessions in the editor's server process: the resident's 129 modules
(`Resident.scala:110`) plus a render session holding `Lib.preamble`, the `Layout.Doc`/
`Layout.Fetch` closure and the picked report's closure. `Layout.Fetch` imports `Native.*`,
`Control.Monad`, `Control.Monad.Cont`, `Function`, `List`, `Pair`, `Relation.Sort`,
`Relation.Scan` (`Fetch.e:45-55`), so a large fraction of the resident's modules is loaded
twice. **Was unmeasured; MEASURED 2026-09-20 below.** No launcher set a heap cap until
WP-5 stage C (`bin/ermine-lsp:18-31` as this was written, `:18-84` now; the extension still
sets only `ERMINE_LSP_LOG`, `extension.js:145-146`), so the cap was the JDK default,
a quarter of RAM (*external*): 3984 MB on the 15.6 GB dev box (`tracker/PERF-ROADMAP.md:139`;
MEASURED again 2026-09-20, `java -XshowSettings:vm -version` says 3.89G),
~2 GB on an 8 GB laptop, and §5's two-windows row makes that four sessions. WP-5 caps it:
`-Xmx${ERMINE_LSP_XMX:-2g}` and `-XX:+ExitOnOutOfMemoryError` in the launcher unless
`ERMINE_JAVA_OPTS` already names `-Xmx`; a setting `ermine.maxHeap` (default `"2g"`) the
extension exports as `ERMINE_LSP_XMX` beside `ERMINE_LSP_LOG`, restarting the server on a
change as `serverPath` does (`extension.js:275-280`). Two windows on an 8 GB laptop are then
4 GB of JVM heap by construction. **The launcher half is BUILT** (WP-5 stage C,
`bin/ermine-lsp:18-84`); the `ermine.maxHeap` SETTING and its export as `ERMINE_LSP_XMX` are
WP-7's row in §14 ("the `ermine.maxHeap` export"), so until WP-7 the variable is honoured but
only an environment that already carries it reaches the server.

**MEASURED 2026-09-20 (WP-5 stage C). An instrument, never gate evidence.** One run on the
15.6 GB dev box (JDK 21.0.12.1, load under 1.5, `-Xmx2g` from the new launcher default),
driven by a scratch client over one `bin/ermine-lsp` process: `VmRSS` from
`/proc/<pid>/status`, heap from `jcmd <pid> GC.heap_info`, and EVERY POINT READ TWICE -- as
it stands, and again after `jcmd <pid> GC.run` -- because RSS alone is dominated by garbage
nobody has asked the collector for, and can FALL across a boot that really costs memory. It
did: 775 MiB before the preview boot, 740 MiB after it, while the live set went UP.

**UNITS, once, for this section and §2.5: MiB is kB/1024 and GiB is MiB/1024**, which is what
`/proc/<pid>/status` and `jcmd` report in; nothing here is a power of ten.

| point | seconds | RSS | RSS after a full GC | live heap after a full GC |
|---|---|---|---|---|
| the resident session ready, 129 modules | 11.4 s (`Ermine session ready: 129 modules in 11.4s`) | 775 MiB (793488 kB) | 282 MiB (288436 kB) | 22 MiB (22576K) |
| after the first `ermine/render` of `Sales`, which boots the render session | the render 2.2 s, of which the session boot 1.9 s (`preview: render session booted in 1.9s`) | 740 MiB (758072 kB) | 342 MiB (349964 kB) | 30 MiB (30519K) |
| a second render of the same report, warm | 0.0 s | 342 MiB (349928 kB) | 342 MiB (350628 kB) | 29 MiB (30010K) |

**The second session costs about 60 MiB of RSS and 8 MiB of live heap** on this fixture,
against a 2 GiB cap. That is far less than "a large fraction of the resident's modules is
loaded twice" suggests, and the reason is the `Session.depCache` row of the table above:
both sessions load through that one process-global cache, and the render session holds
`Lib.preamble`,
the `Layout.Doc`/`Layout.Fetch` closure and one compiled report rather than 129 modules. The
boot the user waits for is still the RESIDENT's 11.4 s; the preview's 1.9 s happens behind
§2.5's progress bar. `Sales`'s rendered document is 1242 bytes, four orders of magnitude
under `ermine.preview.maxDocumentBytes`. `ERMINE_LSP_XMX=256m` still boots the resident
(11.8 s, RSS 412 MiB, 22 MiB live), so the 2 GiB default is a ceiling and not a requirement.
STILL UNMEASURED: a second WINDOW (§5's row), a report whose closure is larger than
`Sales`'s, and anything on a machine that is not this one. A STUCK preview is a different
number entirely -- it occupies the whole cap; see §2.5.

### 2.3 Which thread

The render session runs on **one dedicated daemon thread** ("the preview thread": a
single-thread executor owned by the LSP, `setDaemon(true)` as `SessionTask.scala:22`, so a
looping render cannot keep a forked test JVM alive). The dispatch thread never touches the
render env; the preview thread never touches the resident. This is the resident's own
invariant (`Rpc.scala:364-368`; `Resident.scala:14-18`) applied to a second env on a second
thread.

Why not the dispatch thread:

| Fact | Evidence | Consequence on the dispatch thread |
|---|---|---|
| `Runner` boots in its constructor | `Runner.scala:311-326` | the first preview freezes every LSP request for the boot; the comparable resident boot is ~13 s (`Resident.scala:24`) -- unmeasured for the smaller session |
| a scan is bounded only by the 300 s statement timeout | `SqlExecution.scala:50`; `DB.scala:43` | a slow SQL Server query freezes diagnostics for up to five minutes |
| the reader and the dispatcher are one loop | `Rpc.scala:429-440` | `$/cancelRequest` cannot even be read while a render runs |

What the preview thread costs, and where it is paid:

| Change | Where | Ticket |
|---|---|---|
| `Wire.send` is unsynchronised (`Rpc.scala:340-346`); a second sending thread could interleave frames | make `send` `synchronized`. The monitor is then held for the write of a whole document; a multi-megabyte answer to a slow client delays the dispatch thread's next `publishDiagnostics` behind it. Bounded by the pipe and by the cap below | WP-1 |
| a document larger than the panel can survive | `ermine.preview.maxDocumentBytes` (default 16 MB): a rendered document over it is answered 500 "document too large for the panel" **before** `send` | WP-5 |
| a request handler answers synchronously (`Rpc.scala:471-481`) | add `onRequestDeferred(method)(params, answer: Either[(code, msg), Json] => Unit)`; the answer callback may run on any thread and answers exactly once | WP-1 |
| `$/` notifications are dropped (`Rpc.scala:488`) | route `$/cancelRequest` to a handler | WP-1 |
| `Server.ask` / `clientPending` are plain vars (`Rpc.scala:413-426`) | rule: the preview thread uses `notify` (through the synchronised `send`) and the deferred answer only, **never** `ask`; a server-to-client request the preview needs (the progress token, §2.5) is issued by the dispatch thread when it enqueues the job | WP-5 |

### 2.4 The render session, concretely

| Item | Decision | Evidence |
|---|---|---|
| Construction | `new Runner(RunnerConfig(roots = ermine.moduleRoots ++ inferredRoot(uri) ++ roots, run = delegatingRun, scanner = scannerFor(profile)))` on the preview thread, on the first `ermine/render` (lazy: no profile read, no driver class, no connection before then) | `Runner.scala:171-179`; resident roots at `Main.scala:106-117`. Passing `run` explicitly avoids the default `Runners.liteDB`, which is a `def` (`Backends.scala:39`) forcing the `lazy val` `DB.sqliteTestDB` (`DB.scala:140`) and loading the SQLite driver (`Runner.scala:174`) |
| Roots | `moduleRoots` (the resident's own, so both sessions register equal shapes, §2.2), then the picked report's **inferred root** (the server derives it as `checkFile` does: parse the header, walk up one directory per extra segment of the module name, `Resident.scala:428-434`), then `ermine.preview.roots` -- `type: array of string`, `scope: "resource"` (*external*: per-folder), default `[]`, resolved by the extension against the workspace folder that owns the picked report (`getConfiguration("ermine", folderUri)`, *external*) and sent as **absolute** paths in every `ermine/render`, because a relative root would resolve against the server's cwd (`Main.scala:102-104`), which is `server.root` (`extension.js:151`). Distinct, then the classpath (`Runner.scala:313-316`). A single-segment module anywhere previews with **no setting**; empty means "the report's own tree and the stdlib". A change to the set **discards the `Runner`**: roots are immutable config (`:171`). **Q6, decided 2026-09-20 and BUILT** (§13): the inferred root is added only when the CONFIGURED roots -- `moduleRoots` then `ermine.preview.roots`, normalised and distinct -- do not already PLACE the file, and "place" is two tests, both required (`Preview.scala:1184-1195`, `:1229-1230`, after Q7 moved them). (1) `Session.moduleUnder(configured, path)` answers the very module name the file's HEADER declares: `moduleUnder` takes the FIRST root in the list that contains the path (`Session.scala:739-744`, `collectFirst`), so `/w` listed before `/w/sub` makes `/w/sub/Rpt.e` "sub.Rpt" and the file must go under its own root instead. (2) THE SOUND HALF: those same roots must resolve that NAME back to THIS file. The loader never asks `moduleUnder`; it walks the chain asking each root for `<root>/A/B.e` and takes the first that EXISTS (`Session.scala:378-382`, chained at `Runner.scala:415-416`), so without this test a report picked under a later root would be rendered from an earlier root's copy of the same module name, silently. When both hold, the inferred root IS one of the configured entries (if `path == r/<module>.e` then `inferredRoot(path) == r`), so dropping it changes the SET not at all -- only its POSITION -- and the chain becomes the plain configured order, the same list for every report under a configured root, which is what stops the switch re-booting. Otherwise it is added exactly as before, ahead of `ermine.preview.roots`, so the picked file's own tree keeps the first say. **THE BEHAVIOUR CHANGE, plainly**: when the same module NAME exists under two configured roots, the CONFIGURED ORDER now decides which one the session resolves, not the picked file's own tree. The picked report's OWN module is exempt -- test (2) is exactly the statement that the configured order already answers with the picked file, and when it does not, the inferred root goes in and the picked file wins as before. Any OTHER name -- a widget two roots both define -- now follows the configured order. **WHAT THAT LOOKS LIKE TO A USER, stated rather than left to be discovered**: a report that used to load its OWN directory's copy of such a module can now pick up the other root's copy, and if the two have drifted the render fails to typecheck -- a 500 about a module the developer did not edit. Nothing warns about the ambiguity: neither the loader nor the preview notices that two configured roots offer the same module name, so the only signal is the error itself. Test D "one name, two roots" pins both directions for the picked report's own module, which is the case the rule makes safe. **Q7, decided 2026-09-20 and BUILT** (§13): the resident's `moduleRoots` still LEAD the chain -- §2.2's equal-shapes argument is why -- but a PICK THEY SHADOW is now an ERROR and not a silent substitution. After the final root set is fixed, `Preview.shadowedPick` (`:1012`) asks the loader's own question over it (`resolvedUnder`, `:1245`: the first root that has `<root>/A/B.e`), from the shared front half `placeAndSession` (`:926`); when the answer is a file OTHER than the one picked, the render is `{ok:false, status: 409}` and the schema `{error}`, both naming the picked file, the shadowing file and the root it sits under, and nothing is loaded. WHICH ROOTS CAN STILL SHADOW, pinned rather than assumed: a resident `moduleRoots` entry, always, since it precedes everything in both branches above; and a configured root only when NO root could be inferred for the pick (an unreadable file, a header that does not parse, a module name deeper than the directories above it) and the path is under a configured root all the same, so that `rootSet` has no inferred root to splice in. WHICH CANNOT, **and only when a root could be INFERRED for the pick -- the qualifier the sentence turns on**: an earlier entry of `ermine.preview.roots` cannot shadow a pick whose own root was inferred, because either the configured chain already resolves the module back to the picked file (test (2) above) or the file's own inferred root goes in AHEAD of `req.roots`. With no inferred root there is nothing to splice, and a configured root CAN shadow and earns the 409 -- which is the second case in the list just above. In particular the case that looks dangerous and is not: the inferred root EQUALS a LATER configured root (picked in `B`, with `A` listed first holding the same name) -- test (2) fails, `B` goes in ahead of `A`, and the pick wins, which is what test D "one name, two roots" already pinned | |
| Settings spelling (WP-7) | **`initialize` and a settings push do not agree, and the extension must send both**: the server reads `ermine.preview.timeoutSeconds` / `ermine.preview.maxDocumentBytes` from `initializationOptions.preview.*` (no `ermine` wrapper -- `initializationOptions` is already the server's own object, as `fastMode` and `debounce` are), and from a `workspace/didChangeConfiguration` push as either `settings.ermine.preview.*` or `settings.preview.*` | as built, WP-5 stage B |
| Reads saved files, not buffers | `Runner` loads through `Session.SourceFile.filesystem` (`:315`); the resident's checks read open buffers (`Resident.scala:397-400`) but the resident env itself loads from disk too | the preview follows **saves**; the panel says so with an "unsaved: Chart.e" hint (§5) |
| Always typechecks | `Runner` is `_typeCheck = Some(true)` (`Runner.scala:288`) and must be: `Session.eval` infers the report's type (`Session.scala:830`) and `Decode.reportSignature` consumes it (`Runner.scala:464`). `ermine.fastMode` skips the typecheck in **checks** only (`Main.scala:65-70`), so in fast mode a type error has no squiggle and the preview shows a 500 "module does not load": the banner is the only diagnostic, and says so (§5) | |
| Foreign tolerance OFF | `Runner` leaves `_foreignTolerant` unset -> default off (`SessionState.scala:130`) | a module with an unresolved foreign binding is a warning plus a stub in the editor (`Session.scala:1405-1411`) and a load failure in the preview (500 banner, §5). That is `bin/ermine-serve`'s behaviour, i.e. the deploy shape; stated, not hidden |
| Report cache | keyed by `(module, binding)`; `compile(module, binding)` evaluates the bare binding name as today (`Runner.scala:445`, `:458`); `cfg.reportName` stays the default for `bin/ermine-serve`'s route | `:296`, `:411-420`, `:445`, `:458`, `:485`, `:541` read `cfg.reportName` today |
| `plans` | unused: every render is `Delivery.Inline`, `Strategy.Buffered`, no threshold, so no deferred token is minted | `Runner.scala:293-294`, `:72-80` |
| Profile switch, roots change, connect / disconnect / recycle | connect, disconnect and recycle inside one profile swap the target of `delegatingRun` (a `RunDB` whose `run` forwards to a `@volatile` current `Run[DB]`), no `Runner` change. A switch of profile, or of `ermine.preview.roots`, runs the sequence in §7.2: disconnect, **discard the `Runner`** (`RunnerConfig.run`/`scanner`/`settings`/`roots` are immutable case-class fields, `:171-179`), which evicts `reports` and the compiled closure with it, connect, re-render (a new boot, unmeasured seconds, with progress) | |

### 2.5 One render in flight, what a timeout can do, what cancel means

| Rule | Mechanism |
|---|---|
| **One in flight, at most one queued, latest wins** | the preview thread's queue holds jobs `boot`, `invalidate(paths)`, `render(id, uri, binding, params, roots, generation)`, `schema(id, module, binding)`, `connect`, `disconnect`, `discard`. A new `render` replaces a queued one, which is answered `-32800` (*external*: LSP `RequestCancelled`). The running one finishes. Ordering between jobs is queue order |
| Generation | every `render` carries the extension's `generation` counter and every answer echoes it; the extension discards an answer with an older generation than its current one (a render started on the previous profile finishes and is ignored, §7.2) |
| Fresh files, whoever saved them | at the head of every render the session runs `reloadStale`'s test (`Resident.scala:271-273`: `depCache(sf)._1 != sf.lastModified`) over its **own** `loadedFiles` -- one `stat` per loaded file, ~150 files, milliseconds -- and invalidates what moved, so edits from outside VS Code and clients without dynamic watchers (`Main.scala:214-217`) are seen without the watcher |
| The held connection is used by one thread only | so `DB.transaction`'s `setAutoCommit` toggling (`DB.scala:19-29`, called per scan from `SqlScanner.scala:193-195`) is never interleaved, and `fromPersistentConnection` handing every caller the same `Connection` (`Backends.scala:49-51`) is safe |
| A scan hang ends by itself | the existing 300 s `setQueryTimeout` (`SqlExecution.scala:50`) raises an `SQLException`; the render answers 500; the preview thread is free again |
| A non-terminating **evaluation** | pure Ermine loops run under `Runner.evalLock` (`Runner.scala:538-540`) and cannot be stopped from outside (*external*: `Thread.stop` throws on JDK 21). The honest promise: **a runaway evaluation blocks no LSP request until it exhausts the heap cap, then the server exits and the client restarts it**. A watchdog (`java.util.Timer`) answers the request after `ermine.preview.timeoutSeconds` (default 60) with "evaluation did not finish", in a notification carrying the **Ermine: Restart Language Server** button (`ermine.restartServer`, `extension.js:241`), marks the preview stuck, and every later `ermine/render` is answered the same way without queueing (**Q8, decided 2026-09-20**: those answers, and the watchdog's own, and the ones its queue drain sends, carry `"stuck": true`, and an `ermine/preview/stuck {stuck: true}` notification goes out beside the `window/showMessage`; **Q10, decided 2026-09-20**: the stuck state CLEARS if the job the watchdog fired on ever returns -- never on a `java.lang.Error` -- and a `{stuck: false}` notification plus an INFO `window/showMessage` then asks the client to re-render, because every `invalidate` posted during the wedge was dropped). An allocating loop (a fold over an infinite list; `swhnf` builds thunk chains as it goes, `Runtime.scala:215-238`) then hits `-Xmx` (§2.2) and `-XX:+ExitOnOutOfMemoryError` (*external*: since JDK 8u92) turns the OOM into a clean exit that `vscode-languageclient` restarts, up to 5 times in 3 minutes (*external*); the panel recovers as §7.2 describes. A CPU-bound loop pins one core for the process life until the user restarts (**MEASURED 2026-09-20: NO WITNESS EITHER WAY. Every loop that goes through `swhnf` reached `-Xmx` instead of pinning a core for ever, and the one candidate for a loop INSIDE a primitive did not spin at all. The claim is neither confirmed nor refuted; see the measured block below**). The resident keeps answering until then: it does not take `evalLock` and is on another thread. The watchdog exists so the user is told at 60 s rather than at OOM. **This row used to end "WP-6 makes cancel real (next row)"; that promise is WITHDRAWN (WP-24, 2026-09-20): WP-6's cancel was built, measured and REMOVED, so nothing makes cancel real and the next row is the design record of what was taken out.** What contains a runaway evaluation is the heap cap and the process exit, and what contains the RE-RENDER that follows the restart is WP-22, which is not built |
| **Cooperative cancel -- WP-6 STAGE 1: BUILT 2026-09-20 (`b7b93daa`), MEASURED (stage 2, `02787f99`), REMOVED 2026-09-20 (WP-24)** | **NONE OF THIS IS IN THE TREE. It was removed by WP-24 on 2026-09-20 on the user's decision (§13, Q13), and everything after this paragraph is the DESIGN RECORD of a mechanism that was built and measured -- not a description of the code.** WHAT THE WATCHDOG DOES NOW is exactly what it did at `0a092242`, the commit before stage 1: ONE PHASE. `fire` (`private def fire(job: Answering, epoch: Long, why: String)`, `Preview.scala:2069`) claims the job under `lock` and does all of it INLINE -- sets `stuck`/`stuckJob`, mints `stuckSeq`, drains the queue, answers the wedged request and every drained job with `stuck: true`, and sends the `window/showMessage` and `ermine/preview/stuck {stuck: true}` pair of the row above. **There is no `fireStuck` in this tree**: `b7b93daa` minted that name when it split `fire` into a two-phase watchdog, and the name went out with the split (MEASURED: `git show 0a092242:...Preview.scala \| grep -c fireStuck` = 0). NOTHING interrupts an evaluation: the honest promise is this table's own -- a runaway evaluation blocks no LSP request until it exhausts the heap cap, then the server exits and the client restarts it -- and §4's client-contract rule (5) is WITHDRAWN with the mechanism. The recovery that follows that restart is what WP-22 guards, and **WP-22's (a)+(b) ARE BUILT as of 2026-09-20 (extension only, extension 0.1.6): the automatic re-render after a restart is no longer issued for a pick that wedged this server and has not changed -- it asks. Its letter (c), an extension-owned kill, is NOT built. Every claim about the editor's own behaviour there is UNOBSERVED (§14's WP-22 row, Q17).** **AS BUILT, and it departs from this row's earlier text in four places the design review found; §14's WP-6 row carries the reasons.** ONE GLOBAL `Runtime.cancelTarget: Thread` beside `Runtime.cancelWhy: Cancelled`, both `@volatile` and both `private[Runtime]`. **THE WRITE ORDER IS ENFORCED, not asked of the caller** (S1/S2 of the stage 1 review): the fields are `private[Runtime]` and every write goes through `Runtime.armCancel(target, why)` -- reason first, target second, and it REFUSES (answering `false`) when another thread's arming is live, which a caller must then say out loud and fall back from -- or `Runtime.disarmCancel(target)`, which clears only that target's own arming, in the reverse order. `swhnf` still reads the field DIRECTLY: a method with a monitor in it is exactly what must not be on every force. And the check is at the **HEAD** of `Runtime.swhnf`, unconditionally, on every call: `val ct = cancelTarget; if ((ct ne null) && (ct eq Thread.currentThread)) throw cancelWhy`. **NOT a per-thread context and NOT `Thread.interrupt`**: `Preview.takeJob` reads an `InterruptedException` as "stop", `ForeignClasses.Recoverable` and the backends react to an interrupt, third-party code may clear the flag, and a JDBC driver may abort its connection on one. **NOT inside `swhnf`'s `case old =>` branch**, which the review proposed as the cheaper placement and then FALSIFIED: `json/Encode.scala`'s `spine` walks a list with `while (true) { Runtime.swhnf(cur) ... }`, and on a CYCLIC list (`repeat a = t where t = a :: t`, `List.e:29-30`) every thunk it re-reads is already `Evaluated`, so that branch is never entered again and a check there would never fire. `Cancelled` is a **`ControlThrowable`**: stackless, EXCLUDED by `NonFatal` so `swhnf`'s own capture does not memoise it as a `Bottom`, and NOT an `Error` (`ForeignClasses.Recoverable` swallows an arbitrary `Error` into a failed reflective lookup, `ForeignClasses.scala:26` is the arm that lets a `ControlThrowable` through). **FIVE CATCHES THAT WOULD HAVE SWALLOWED IT** gained `case c: Cancelled => throw c` as their first arm, and without them the cancel silently does not work: `Prim.apply` and `Box.apply` (`Runtime.scala`), `IO.Unsafe.eval` (`session/Lib.scala`, which would hand the cancel to the Ermine program's own error continuation), the foreign invoke (`session/Session.scala`, which re-wraps what it catches as a `RuntimeException` -- which IS `NonFatal`, so `swhnf` would capture and memoise it) and -- **the fifth, FOUND BY THE STAGE 1 REVIEW (DM-3) and not by the build** -- `Bottom.thrown` (`Runtime.scala`). A `Bottom`'s body is usually a bare `throw`, but two in `core` FORCE (`session/Lib.scala`'s stdlib `error`, `Bottom(error(s.extract[String]))`, and its `pipe#` failure, `Bottom(... + rel.whnf)`), and `thrown` is what `json/Encode.scala`, `json/Doc.scala`, `Pretty.ppRuntime` and `Bottom.toString` all call -- so a cancel raised by that forcing was CAUGHT AND RETURNED AS A VALUE: a bogus error node inside a 200, or a job that "succeeded" with the cancel's own text in its document. Bounded (the next `swhnf` re-throws), and now closed. **THE WATCHDOG IS TWO-PHASE.** At `timeoutMillis`, PHASE 1 arms the flag and does NOTHING else: no answer, no stuck mark, no queue drain, no notification. If the cancel TAKES (phase 2a), `Preview.runJob` answers 500 with the timed-out text reworded ("evaluation did not finish after Ns, so it was CANCELLED ..."), **without** §4's `stuck` marker, then **DISCARDS THE RENDER SESSION UNCONDITIONALLY** -- the escape leaves WHITEHOLED thunks with this thread still in their `pending` queue, and a later same-thread force of one would memoise `Bottom(sys.error("infinite loop detected"))` -- and clears the flag. If it has NOT taken after `graceMillis` (1000 ms, a constant with a test seam, not a user setting), PHASE 2b **CLEARS THE FLAG FIRST** and then does exactly what the watchdog did before WP-6: claim, stuck, `stuckJob`, `seq`, drain, `stuckRefusal`, `window/showMessage`, `{stuck: true}` -- and Q10's recovery applies to it unchanged. **WHAT THE CANCEL CANNOT STOP, because none of it reaches `swhnf`**: a loop inside ONE primitive, the relational row loop (`relational/package.scala`'s `driveLeftId`), a JDBC scan, and a thread parked in `SessionTask`'s `future.get` or in a thunk's `latch.await`. Phase 2b is the fallback for every one of them, which is why it is not optional. **A USER `$/cancelRequest` STILL DOES NOT INTERRUPT** -- `Preview.cancel` is untouched (queued: removed and `-32800`; in flight: marked, answer replaced). **THE FLAG IS CLEARED IN FIVE PLACES**, and the list is the review's: (1) **BEFORE THE ANSWER on the cancel path** -- `runJob`'s `Cancelled` arm does `clearCancel` then `discardSession` then `finish`, because the answer says the preview is serving renders again and the session was rebuilt, and both must be TRUE when it goes on the wire (DM-1: with the clear only in the `finally`, a client could read the answer while the flag still named the preview thread; MEASURED by the review as two reds in three runs); (2) phase 2b, before it falls back; (3) `runJob`'s `finally`, for EVERY job, as the idempotent catch-all; (4) `Preview.cancelTimer`, which both `shutdown` and the death drain call -- **DM-2: the fourth path, and the one no other clear reaches**, because a `shutdown()` inside the grace cancels the timer so phase 2b never runs while the preview thread is wedged and reaches neither the `finally` nor `takeJob`; harmless in the shipped server, but in the UNFORKED test JVM one stale target makes every later `swhnf` in every suite take the slow side of the branch for the life of the process; (5) `Preview.takeJob`, which logs loudly and clears if it ever finds one armed. A slow scan that legitimately finishes after the fire must not die at its next force.

**WITHDRAWN 2026-09-20 BY WP-24, BECAUSE IT WAS A CONSEQUENCE OF THE CANCEL AND THERE IS NO CANCEL.** With stage 1 removed, no render is ever cancelled, so nothing unwinds the preview thread's `swhnf` chain deliberately and no thunk is left `Whitehole` with an uncounted `CountDownLatch` that way; WP-14's row no longer points here. **THE ONE RESIDUE, DERIVED BY READING (`Runtime.scala:229-231` at `0a092242`) AND UNVERIFIED**: `swhnf`'s own `catch { case NonFatal(e) => r = Bottom(throw e) }` captures every ORDINARY failure and writes a `Bottom` back, so an ordinary error leaks no latch. Only a throwable that `NonFatal` EXCLUDES can escape the chain the same way -- a `VirtualMachineError`, `ThreadDeath`, an `InterruptedException`, a `LinkageError` or a `ControlThrowable` -- and with `Cancelled` gone nothing on the preview's own path raises one deliberately. **`InterruptedException` is out for a second, independent reason**: the only blocking call in `swhnf` is `t.latch.await` (`Runtime.scala:222`), which sits in the `Whitehole` branch OUTSIDE the `try`, so an interrupt there would indeed escape -- but NOTHING IN THE TREE INTERRUPTS THE PREVIEW THREAD. `Preview` only ever READS an interrupt, in `takeJob`, where it means "stop" and is re-asserted (`Preview.scala:852`, `catch { case _: InterruptedException => stopping = true; Thread.currentThread.interrupt() }`). So the one that is actually reachable is the `OutOfMemoryError` that ends the process anyway. What follows is the record as it was written: **THE CONVERSE CASE, DERIVED BY READING AND UNVERIFIED (S3 of the stage 1 review).** The cancel unwinds the PREVIEW thread's chain without `writeback`, so every thunk it passed is left `Whitehole` **with its `CountDownLatch` never counted down**. `discardSession` throws the `Runner` away but releases no latch. So ANOTHER thread that later reaches one of those thunks -- a scan's chunk producer, `SessionTask`'s pool -- takes `swhnf`'s `Whitehole` branch, finds itself absent from `pending`, and parks on `t.latch.await` **for ever**. They are daemon threads, so the JVM can still exit; what leaks is one thread and whatever its queue retains, per cancelled render that had a concurrent scan. Not reachable in stage 1 (the stage A backend opens one connection per run and the properties run no concurrent scan), which is why it is unverified; WP-13/WP-14 are where it becomes reachable, and WP-14's row carries it. Cost: one volatile load and one predictable null-branch per force, in the binary whether the switch is on or off. **`perf-bench.sh` CANNOT MEASURE IT** -- it is a typechecker bench. §11's Instruments section carries the instrument that DID, `tracker/tools/eval-bench.sh`, and its figures (BUILT AND RUN 2026-09-20, write-up reviewed and corrected): nothing distinguishable on an ordinary build-and-fold workload, and on the `swhnf`-densest one a suggested but NOT established ~5 %, which belongs to the whole stage 1 commit and not to this row's load alone. Stage 3, flipping the default, is the user's -- and the flip adds no PER-FORCE cost, because the check is in the binary either way, but it is not behaviourally free: §14(d) and (f) are what it turns on (the unconditional session discard on a taken cancel, the two-phase watchdog, and `isFatal`'s exception, which is sound only while that discard is unconditional) |
| `$/cancelRequest` | queued: removed and answered `-32800`; in flight: marked, its eventual answer replaced by `-32800`, the work NOT INTERRUPTED AT ALL (no hook into `SqlExecution` either way). **This used to read "not interrupted until WP-6"** -- WP-6's cancel was built and then REMOVED (WP-24, 2026-09-20), so nothing interrupts an evaluation on any path; during a boot: honoured when the boot ends (answer `-32800`, boot kept) |
| `stale` | a **hint**; `invalidated` is the mechanism. A `@volatile` generation counter is bumped by `invalidate`, snapshotted at render start and compared just before `send`; a mismatch sets `"stale": true`, and the `invalidated` notification that follows makes the extension re-render (§3). An `invalidate` that lands after the comparison is not lost, only its banner is late. **AS BUILT (WP-5 stage A), DIFFERS FROM THE LETTER ABOVE -- for the user to confirm**: the counter is bumped when an `invalidate` is **posted** (on the dispatch thread) and snapshotted when a render is **enqueued**, not when it starts. The literal reading cannot work on a single-threaded queue: an `invalidate` that ran as a job could never move the counter *during* a render, so `stale` would be dead code; and a snapshot taken at render *start* would call a render fresh that was enqueued before an invalidate still queued behind it. Bumping per post can flag a render whose invalidation turns out empty -- a false positive, which is what "a hint" permits. The WP-5 stage A review judged this strictly better than the literal reading |
| Boot progress | the first render **or schema** (Q7, decided 2026-09-20: a first pick boots on the SCHEMA request, which is exactly when the user is waiting, so a schema job mints its token through the same dispatch-side `mintBootToken` and under the same at-most-one-outstanding-`create` rule), and every post-discard boot, reports "Ermine preview: booting the render session" through LSP work-done progress (`window/workDoneProgress/create`, then `$/progress` begin / end, `cancellable: false`, *external*: LSP 3.15+), guarded by the client's `window.workDoneProgress` capability. The `create` request is sent by the dispatch thread when it enqueues the job (§2.3); the `$/progress` notifications go from the preview thread through the synchronised `send` |

What a restart costs, stated once: a fresh process, the ~13 s boot (`Resident.scala:24`),
every per-document inference cache (cold first check ~2.5 s against ~0.9 s warm,
`editor/vscode/README.md:117-118`), the workspace-symbol table, the held connection and its
`##` tables (§7.2), and the compiled report.

**THE BOOT FIGURES IN THIS DOCUMENT ARE THREE DIFFERENT CLAIMS AND ARE NOT TO BE CONFLATED**
(resolved 2026-09-20 by WP-24, from this document's own history; no new measurement):

| Figure | What it is | Status |
|---|---|---|
| **11.4 s** at 775 MiB RSS | the RESIDENT session becoming ready over 129 modules, `Ermine session ready: 129 modules in 11.4s`, one run of a real `bin/ermine-lsp` on this box (§2.2's WP-5 stage C table) -- the boot a user waits for | **MEASURED** (one run, an instrument, never gate evidence) |
| **~13 s** | `Resident.scala:24`'s own comment, "boot is ~13s instead of ~7s, once", about running interface-free; it is what this paragraph and §2.2's option table cite | **READ** from a code comment, not measured |
| **"11-13 s boot"** | WITHDRAWN AS UNVERIFIED by WP-6 stage 2's corrected write-up (§11) | that withdrawal is about the BOOT INSIDE THE EVAL-BENCH FORKS, whose only two logs carrying a boot time read 16.3 s and 20.2 s under `PrintCompilation`. **It does not withdraw the 11.4 s row**: different process, different workload, different instrument |

**MEASURED 2026-09-20 (WP-5 stage C). An instrument, never gate evidence.** Each case is one
run on the 15.6 GB dev box (JDK 21.0.12.1, load 1.0-2.9), one `bin/ermine-lsp` process per
run driven by a scratch client, `VmRSS` from `/proc/<pid>/status`, heap from
`jcmd <pid> GC.heap_info`, cores busy from the `utime`+`stime` delta in `/proc/<pid>/stat`.
Units are §2.2's (MiB = kB/1024). `ermine.preview.timeoutSeconds` was set to **10** through
`initializationOptions` for the three WATCHDOG cases; the `WpBlow` case below ran with the
SHIPPED 60 s clock, which is why no watchdog answer appears in its row. Four report modules,
written for this and kept OUT OF THE TREE because no gate needs them:

```
module WpChain where
import Int; import Json; import List using {length; repeat}; import Layout.Doc

report : Int -> Node
report n = rawWidget "chain" (length (repeat n))

module WpSpin where
import Int; import Json; import Layout.Doc

spin : Int -> Int
spin n = spin n

report : Int -> Node
report n = rawWidget "spin" (spin n)

module WpBlow where
import Int; import Json; import List using {iterate; length}; import Layout.Doc

grow : List Int            -- a TOP-LEVEL binding, so the head of the infinite
grow = iterate (x -> x) 1  -- list is retained for the render session's life

report : Int -> Node
report n = rawWidget "blow" (length grow)

module WpRegex where
import Int; import Json; import Layout.Doc
import List using {replicate}; import String using {concat; replaceAll}

input : String             -- 40 'a's and a final '!' the pattern cannot consume
input = replaceAll "a$" "!" (concat (replicate "a" 41))

report : Int -> Node
report n = rawWidget "regex" (replaceAll "(a+)+$" "x" input)
```
(the `import` lines are one per line in the files; joined here to keep four modules on one
screen)

`WpChain` folds over the stdlib's CYCLIC list (`repeat a = t where t = a :: t`,
`List.e:29-30`) with `length = foldl (x _ -> x + 1) 0` over a bang-patterned accumulator
(`:49-51`, `:119-120`), so ON PAPER its live set is one cons cell and one `Int`; `WpSpin`
re-enters with the very argument thunk it was given and builds no datum at all. Neither
stayed inside the heap.

| case | when the watchdog answered | heap and RSS just after the fire | what followed |
|---|---|---|---|
| `WpChain`, `-Xmx2g` (the launcher default), **three runs, and every triple below is in RUN ORDER, earliest first** | 12.2 / 12.1 / 12.0 s -- the 10 s clock plus the ~2 s session boot the clock deliberately does NOT cover (the bracket above) | RSS 1.93 / 2.02 / 1.91 GiB; G1 heap committed 1.77 / 1.78 / 1.77 GiB (1.77 in two of the three runs; the 12.1 s run committed 1.78), 518 / 673 / 421 MiB used | used 1.58-1.73 GiB at +30 s (4.65 cores busy), 1.91 GiB at +60 s (2.15 cores), and **GONE before +120 s in the two runs that were allowed to get there: exit code 3**, `-XX:+ExitOnOutOfMemoryError`. The remaining run -- the EARLIEST, the one whose watchdog answered at 12.2 s -- sampled only to +60 s and was killed by the instrument there while it was still alive, so it says nothing about +120 s |
| `WpSpin`, `-Xmx2g` | 12.5 s | RSS 2.31 GiB; heap 2.00 GiB committed, 1.98 GiB used | gone about 5 s later, before the next request could be answered |
| `WpBlow`, `ERMINE_LSP_XMX=256m` (the launcher's variable, honoured) | it never fired: the shipped 60 s clock was still running when the OOM arrived | heap 256 MiB committed, 254 MiB used at the last sample, +6.4 s | **exit code 3 after 8.6 s**, stderr EMPTY, and the JVM's own line written UNFRAMED to STDOUT |
| `WpRegex`, `-Xmx2g` -- the review's candidate for a spin INSIDE ONE PRIMITIVE | **it never fired: the render ANSWERED `{"ok":true,...}` in 2.1 s**, almost all of it the session boot | -- | the document carried the input back unchanged (`"aaaa...!"`, no match); at +30, +60 and +120 s the process was IDLE -- **0.00 cores busy**, RSS between 699 and 703 MiB (703 at +30 s, 699 at +60 and +120 s), heap used between 212 and 213 MiB, 29 MiB live after a full GC -- and it answered a second hover before the instrument killed it |

**PROVENANCE, because the file names moved.** The two EARLIER `WpChain` runs (watchdog at
12.2 s and 12.1 s) were made before the program was split into a file of its own, and their
logs therefore record the file name `WpSpin.e`. The LATEST run (12.0 s) was made as
`WpChain.e` after the split, and it is the run the triples above end on (1.91 GiB, 421 MiB)
and the ONLY one whose instrument recorded processor occupancy, so 4.65 and 2.15 cores are
its figures and not the other two runs'. The `WpSpin` row is a DIFFERENT program -- the bare self-call
-- and has one run, made after the split.

What the watchdog does was measured on `WpChain` in all three runs, and it is §2.5's own row:
the request is answered `{"ok":false,"status":500,"message":"evaluation did not finish after
10s; the preview is stuck until the language server is restarted -- run \"Ermine: Restart
Language Server\" (ermine.restartServer)","generation":1}` -- **THAT IS THE WORDING AT THE TIME
OF THE MEASUREMENT; Q10 reworded it** (2026-09-20), because "stuck until the language server is
restarted" became the worst case rather than the only one once the state could clear: the text
now says the preview recovers by itself if the evaluation ever finishes and names the restart
as what to do if it does not. The status, the shape, the generation echo and both restart
substrings are unchanged, and nothing else in this block is affected. `window/showMessage`
type 1 carries the same text; **the resident answered a `textDocument/hover` in 0.00 s while the
preview thread was wedged** (`Good.answer : Int`); and the next `ermine/render` was refused
with the same message, its own generation echoed, without queueing.

Three things this adds to, or takes back from, the mined text above:

1. **NO `swhnf` LOOP STAYED INSIDE THE HEAP -- and that is all this shows.** Both loops that
   reach `Runtime.swhnf` grew without bound, which the mechanism there explains: `swhnf`
   carries a `chain: List[Thunk]` that only `writeback` unwinds (`Runtime.scala:215`, `:237`,
   `:247`), and every updatable thunk it enters is whiteholed with a `pending` thread set and
   a `latch` before the recursive call (`:229-237`) -- so a self-call that never reaches a
   value adds a frame, a thunk, a set and a latch per step and lets go of none of them. A fold
   over an infinite list is only the most obvious instance. **The CPU-bound exception is NOT
   disproved**: the row's "a CPU-bound loop pins one core" would need a loop that takes no
   `swhnf` step, i.e. one inside a single primitive, and the review's candidate for that --
   catastrophic regex backtracking through `replaceAll#` (the foreign method onto
   `java.lang.String.replaceAll`, `String.e:68-69`, `:103`) -- **did not spin**: `(a+)+$`
   against 40 a's and a `!` answered in under a millisecond, and so did twelve further
   patterns tried directly against JDK 21 -- `(a+)+b`, `^(a+)+$`, `(a|a)+$`, `(a|aa)+$`,
   `^(a|a?)+$`, `(x+x+)+y`, `(a*)*b`, `(a|a?)+b`, `([a-z]+)+#`, `(a+)+\z`, `(?:a+)+b`,
   `(a|aa)+c`, over 47 pattern/input combinations, anchored and unanchored, with and without
   the required trailing literal actually present in the input, every one under 2 ms.
   **That twelve-pattern sweep is NOT REPRODUCIBLE FROM THE RECORD**: it was run as a scratch
   `java` program whose OUTPUT was never saved, so the numbers in this sentence rest on the
   run and not on a log. The finding the row depends on is the one in the table above, which
   IS on the record: `WpRegex` through the real server answered `{"ok":true}` in 2.1 s and the
   process was idle for two minutes afterwards.
   JDK 21's `Pattern` defeats the classic cases. So: no witness either way, and the promise
   keeps its CPU-bound clause.
2. **The cap is not only a ceiling on runaways; a stuck preview OCCUPIES it.** RSS reached
   2.3 GiB within a minute of the fire under `-Xmx2g`, and the whole server -- resident,
   caches, held connection -- goes with it about two minutes after the fire. That, and not
   the 60 MiB of §2.2, is the number a user with two windows should think about. It is also a
   different user story from "blocks no LSP request", which is Q13.
3. **`-XX:+ExitOnOutOfMemoryError`'s termination line goes to the JVM's STDOUT**, which for a
   server on stdio is the PROTOCOL CHANNEL: measured, the last bytes before EOF were
   `Terminating due to java.lang.OutOfMemoryError: Java heap space\n`, unframed, straight
   after a well-formed `$/progress` frame. `Main.stealStdout` does not and cannot cover it --
   it replaces `System.out` at the Java level, and this line is written by the VM itself.
   That is Q12. What a client makes of the trailer is *external* and was not exercised. Nor
   was "`vscode-languageclient` restarts it, up to 5 times in 3 minutes": the client library's
   documented behaviour (*external*), and nothing in this repository runs VS Code. What WAS
   measured is the clean exit itself -- exit code 3, and no process left behind.

Dropped from earlier drafts, on this evidence: "never stalls diagnostics" is narrowed to
"never blocks the dispatch thread"; "cancellable" is narrowed to the rows above.

## 3. The loop: save -> reload -> invalidate -> re-render

| Step | Thread | What happens | Evidence |
|---|---|---|---|
| 1 | client | the `**/*.e` watcher the server registered fires for any `.e` in the workspace, stdlib or not | `Main.scala:199-208` |
| 2 | dispatch | `workspace/didChangeWatchedFiles` reloads the resident's own closure (unchanged) | `Main.scala:256-268`; `Resident.scala:251`, `:243-250` ("files the resident did not load ... are ignored here") |
| 3 | dispatch | `afterReload` (`Main.scala:179`), which both the watch handler (`:268`) and the `ermine.reloadModules` command (`:277`) call, posts `invalidate(changed ++ removed)` to the preview thread (a no-op before the preview has booted), so the manual reload path invalidates too | new |
| 4 | preview | `Runner.invalidate(paths)`, under `evalLock` (`TestRunner` runs properties concurrently over one runner, `TestRunner.scala:112`, `:806`): paths -> modules through the render session's **own** `loadedFiles` (`Session.Filesystem`, as `Resident.loadedByPath` does, `Resident.scala:178-183`) plus `Resident.moduleUnder(cfg.roots, p)` for a file restored after deletion (`:699-704`, `:262-265`); closure through `depCache` imports as `dependentsOf` does (`:186-197`); scrub the closure (§3.1); evict every `(module, binding)` key of those modules from `reports` (`Runner.scala:296`). **No eager reload**: the next render's `compile` loads on demand (`:432-436`). **Q4 (2026-09-20)**: a `compile` whose module LOAD failed records that module in a private, per-`Runner` pending set (bounded, oldest first), and an `invalidate` whose paths name a module -- loaded through `loadedFiles`, or UNLOADED under a root -- unions that set into its answer, so the save that FIXES a broken report names it here and step 5 sends it; a successful compile takes it back out, and `invalidateStale` does not union it | new; because eviction is keyed on the render session's loaded set, a workspace report module (`Sales`) is covered -- the resident's reload set could never name it |
| 5 | preview | if the dirty set is non-empty: `ermine/preview/invalidated {modules}` | new |
| 6 | extension | if the picked report's module is in `modules` (the set includes dependents, so saving `Layout/Widgets/Foo.e` names every report that imports it), re-send `ermine/render` with the last params, and re-request the params schema (§6). **Q11 (decided 2026-09-20, option (iii)): and ALSO re-render when the picked report's OWN FILE is created or changed while its last answer was a PLACEMENT 404**, which no `invalidated` can announce -- a file with no readable header has no module NAME for the notification to carry, and since Q5/Q7 it is refused at placement before `Runner` is ever asked. NOT on a `Runner` 404 (a missing BINDING on a module that loaded): that module is in `loadedModules`, so `invalidated` already fires for it and the extra trigger would double-render. **THE TEST IS EXACT SINCE Q15 (decided by the user 2026-09-20 and BUILT)**: a placement failure carries a machine-readable `reason` (§4) and a `Runner` 404 carries none, so WP-7 tests `status === 404 && typeof reason === "string"` and matches no message text. The two triggers are then DISJOINT by construction -- while a placement 404 stands the module was never loaded, so `invalidated` cannot name it; a `Runner` 404 has no `reason`, so the watcher does nothing there -- and no coalescing window is load-bearing for it | new |
| 6b | extension | **AND, SINCE WP-22 (BUILT 2026-09-20, letters (a)+(b)): the re-render that follows a LANGUAGE SERVER RESTART is CONDITIONAL.** Step 6's two triggers above are unchanged and are never suppressed -- an `invalidated` and the Q11 watcher are each evidence that something changed -- but the third automatic trigger, the `rerender` effect of the client's `Stopped -> Running` transition (§5's "Server stopped" row), now asks first when the picked report is the one that WEDGED this server and nothing has changed since: one non-modal **Render anyway** / **Not now**, and a `held` status-bar state. The mark and the consultation are `markKey`/`guardReduce`/`shouldAutoRender`/`heldMessage` in `editor/vscode/src/preview-core.js`; `stuckReduce` is unchanged. See WP-22's row and Q17 | new; **UNOBSERVED in any editor** |
| 7 | preview | render; answer; the panel repaints | §4 |

### 3.1 The scrub, shared

`Resident.scrub` (`Resident.scala:286-301`) removes a module set from an env down to its
builtin state, guarded by a post-preamble `builtins` copy (`:122`) so `Lib`-installed names
survive. `Runner.invalidate` needs the same ten lines and the same guard. WP-2 lifts `scrub`
and `dependentsOf` into `Session` (with the `builtins` env as a parameter) and makes `Runner`
take a `builtins` snapshot after its own `Lib.preamble` (`Runner.scala:318`); the resident
keeps calling the lifted versions at its four call sites (`scrub` at `Resident.scala:212`,
`:231`, `:461`; `dependentsOf` at `:208`), pinned by the existing C properties
(`TestLspRobustness.scala:554`, `:583`, `:655`).

### 3.2 Which report is rendered: selected by type, not by name

A widget module has no report of its own (`Layout/Widgets/*.e`, eleven modules today). The
panel renders **a report the developer picks**, and the unit of the pick is a
**(file, binding) pair**: any top-level binding whose type is a report type is previewable,
a module may declare several (`report`, `emptyReport`, `wideReport`, each with its own
params file, §6), and no binding name is privileged. Expecting a binding literally called
`report` is an artefact of the HTTP route `/report/<Module>` (`Server.scala:16`;
`Runner.scala:173`) and has no place in an editor.

**Ermine: Preview Report...** is two steps. First a file: `.e` files under the workspace
(`workspace.findFiles("**/*.e")`, *external*). Then a binding, from a new request
`ermine/preview/reports {uri}`, answered on the dispatch thread as a **lookup over the stored
document index**: the symbol tree `Definitions.index` builds on every check
(`Definitions.scala:1023-1026`, stored as `DocIndex.symbols`, `:103`) carries, per top-level
term group (`Symbols.termGroups`, `Symbols.scala:496-500`), the type the check inferred for
that spelling -- `TolerantCheck.types` first, the session's `termNames` for names a check
installs rather than binds (`Symbols.scala:156-157`, `:287`; `Sym.ty`, `:120`). The server
filters those symbols with the same test the runner applies to a compiled report:
`resultKind` (`Runner.scala:591-595`), made public, applied to the codomain after at most one
`->` (aliases expanded through the index's own `cons`, the check env's Con table,
`Definitions.scala:127`, `:1035`), and answers `{module, reports: [{binding, type}]}` with the
type rendered as hover renders it (`Pretty.prettyType`, `Symbols.scala:450`). The picker
shows `binding : type` and remembers the pair per workspace (`workspaceState`, *external*).
Two things this rests on, stated: a file with no index (never opened, never checked) is
checked once by the server for this request, from disk through `checkFile`
(`Resident.scala:401`, `:412-413`) and `Definitions.index` (`Definitions.scala:635`), a cold
check of ~2.5 s (`editor/vscode/README.md:117`) on the dispatch thread -- the one preview
request that analyses there, and it is a user command, not a navigation request; and the
filter is a candidate list, so the picker also accepts a typed binding name, and a binding
that is not a report is a 400 at render (`Runner.scala:466-470`). Neither
`workspace/symbol` (its `SymbolInformation` carries no type, `Symbols.scala:469-472`, and its
session globals exclude workspace modules, `:640-644`) nor a regex over the file's text
(`^report\s*:` finds one privileged name and misses a signature-less binding) is the
mechanism.

Saving a widget module re-renders the picked report through step 6 only if the report
imports the widget; if it does not, nothing changes and the status bar says "not used by
<Module>.<binding>". The harness for a new widget is therefore an ordinary report module
under a preview root -- `core/src/test/resources/doc/Sales.e` is one -- not a hidden
convention.

## 4. Wire

All new methods are `ermine/...`, beside `ermine/schema` (`Definitions.scala:226-228`).

| Method | Direction | Shape | Notes |
|---|---|---|---|
| `ermine/render` | request | `{uri, binding, params, roots, generation}` -> `{ok: true, document, generation, stale?, trace}` or `{ok: false, status, message, path?, reason?, generation, stuck?, trace?}` | `uri` -> module via `Resident.moduleUnder(cfg.roots, path)`; a file that cannot be PLACED under any root is a **404 whose message says why** (Q5, decided 2026-09-20): it is not a `.e` file, it cannot be read, its module header does not parse, or its module name is deeper than the directories above it. A readable `.e` file whose header parses is always under its OWN inferred root (§2.4), so the 404 is unreachable for it -- which is why the old text, "not under a module root", was true of nothing. **THE 400 AND 404 TEXTS NAME THE FILE AND NEVER A DIRECTORY** (Q5's convention; the 409 below is the one exception and says why). `roots` are the absolute `ermine.preview.roots` (§2.4). Delivery is always inline, buffered, no threshold (`Runner.scala:72-80`): **no `data` field on this wire**. `status`/`message`/`path` are `RunError`'s (`Runner.scala:25-65`: `BadRequest` 400 at `:47`, `NotFound` 404 at `:51`, `Failed` 500 at `:55`): 400 with a JSON path for a bad param or a binding that is not a report (`:466-470`, `:472-476`), 404 for module or binding (`:447`, with the request's binding in the text), 500 for load, eval, scan, write, and for a document over the size cap (§2.3). **`reason` (Q15, DECIDED by the user 2026-09-20)** is a machine-readable string beside `status`, present on EXACTLY the failures `Preview`'s OWN FRONT HALF decides -- the ones about PLACING the picked file, before `Runner` is asked -- and on nothing else. The vocabulary is CLOSED and STABLE (it is wire contract; `Preview.Reason`): `not-a-file-uri` (400, the URI names no file), `not-ermine-source`, `unreadable`, `no-module-header`, `header-deeper-than-path`, `not-placed` (404, the last being the general fallback, unreachable as built) and `shadowed` (409). **WP-13 (2026-09-24, Q-S4 (a)) adds `not-connected` (503, disconnected; see the `disconnect` row)** -- and the four `connect-*` reasons, which appear only on `ermine/preview/connect` answers. **A 404 FROM THE `Runner` -- no such module, no such binding -- CARRIES NO `reason` KEY, AND THAT ABSENCE IS THE DISCRIMINATOR**: it is what lets WP-7's Q11 trigger tell a placement 404 from a `Runner` 404 without matching the message text, and it is why the bad-`roots` 400 (the CLIENT's error, not a placement decision) carries none either. An OLD server sends none anywhere, so a client reading `reason` degrades to "never trigger" rather than to triggering wrongly. `json/Runner.scala` and `RunError` are untouched: `bin/ermine-serve` is unchanged. **409 (Q7, decided 2026-09-20)** for a SHADOWED PICK: the final root chain resolves the picked file's module name to a different file, so neither this render nor a schema may use it, and nothing is loaded. **THE 409 IS THE ONE TEXT THAT PRINTS A PATH**, and the orchestrator's decision on the apparent contradiction with the sentence above is recorded here: Q5's file-name-only convention governs the 400 and 404 texts; the 409 prints the SHADOWING file's path and the root it sits under because that is the only useful thing it can say (the picked file is still named by its name alone -- the request supplied its URI), and rule A5 (§8.1) covers **URLs, hosts and passwords**, not a source path under a directory the client or the server configured as a module root. 409 costs no new vocabulary: `Preview.failure` takes a status NUMBER and `RunError`, which the HTTP server shares, is not on this path. The message never carries a JDBC URL (§8, rule A5). **`stuck: true` (Q8, decided 2026-09-20)** is present on EXACTLY the failures that mean §2.5's WEDGE -- the refusal `render` sends while stuck, the watchdog's own answer, and the answers its queue drain sends -- and on NOTHING ELSE, in particular not on the job crash handler's 500, which is a report that ran and failed. The `-32800` paths (a displaced render, a cancelled one, the shutdown drain, and the watchdog's answer to a request that had been CANCELLED) are JSON-RPC ERRORS with no result object, so they carry no marker and the client learns the state from `ermine/preview/stuck` instead. Answered through `onRequestDeferred` from the preview thread **`trace` (WP-35 server half, DB programme S2b, BUILT 2026-09-24/25, `tracker/db/OBSERVABILITY.md` §4):** APPENDED LAST on every answer from a render that RAN (ok, failed, crash, the watchdog's stuck answer with `partial: true` and `running: {path, sql, sinceMs}`), absent on a render refused before it ran (displaced -32800, refused while stuck, drained). Shape: `{v: 1, generation, partial, wallMs, phases: [{name, ms, attributed?, cached?}], queries: [{path, delivery, dialect?, sql?, sqlBytes?, statements?, setup?, sqlEmitMs, execMs, fetchMs, dbMs, ms, rowsRead, rows, scanned, columns, bytes, deferred, overThreshold?, error?, message?}], totals: {dbMs, otherMs, wallMs, queueMs, relations, queries, rowsRead, rows, bytes, documentBytes?}, connection: {kind, dialect, database?, profile?}, running?, truncated?}`; `dbMs + otherMs == wallMs`; SQL capped at 16 KiB with a marker; no URL/user/host/password; no setting |
| `ermine/preview/reports` | request | `{uri}` -> `{module, reports: [{binding, type}]}` or `{error}` | §3.2; dispatch thread; a lookup, or one cold check for an unopened file |
| `ermine/preview/invalidated` | notification, server -> client | `{modules}` | §3 step 5 |
| `ermine/preview/stuck` | notification, server -> client | `{stuck: true \| false, message, seq}` | **Q8, decided 2026-09-20.** `true` from the watchdog's `fire` (TIMER thread), `false` from Q10's recovery (PREVIEW thread), each **beside** a `window/showMessage` and never instead of one -- the standard message is what any LSP client shows, this row is what a BANNER can hold. Both through `notify`, never `ask` (§2.3), outside the queue's monitor, guarded, scrubbed. WP-7's panel reads it, and the **Ermine: Restart Language Server** button is the panel's: the LSP shape that carries actions (`window/showMessageRequest`) is a REQUEST whose answer names the chosen action TO THE SERVER, and the protocol gives a server no way to make the client run the client-side `ermine.restartServer` (*external*, unverified here). **THE CLIENT CONTRACT, four rules (IM-1 of the Q8-Q12 review):** (1) `seq` is a monotonic counter minted in the SAME locked step that flips the state, so a client KEEPS THE HIGHEST `seq` IT HAS SEEN AND IGNORES ANYTHING LOWER -- the two edges are sent by different threads with nothing ordering them, and a collision really can put the `false` on the wire before the `true`. **`seq` IS PER-PROCESS AND RESTARTS AT 1**, so the client RESETS its high-water mark when the language client goes **Stopped -> Running** (§5's own row for that transition): a restart is the remedy the watchdog's message names, and a client that kept the old mark across one would ignore the fresh server's `{stuck: true, seq: 1}` for the life of its session (DD-2 of the second review); (2) this notification is **AUTHORITATIVE** for the stuck state; (3) the `"stuck": true` marker on an ANSWER is **per-request**, not a state: it says why THAT request was refused, and one stale stuck refusal may legitimately arrive after a clear (it was decided before it); (4) the `window/showMessage` that accompanies each edge is **advisory** and may arrive in either order relative to it -- it carries no `seq` and a client must not derive state from it. **(5) WITHDRAWN 2026-09-20 BY WP-24, WITH THE MECHANISM THAT MOTIVATED IT: A CLIENT GETS ONE RISING EDGE PER WATCHDOG INCIDENT AGAIN**, and rules (1)-(4) are the whole contract, exactly as they were at `0a092242`. A client may still be shut down and restarted by ITSELF after `{stuck: true}` -- that is WP-22's caller-owned recovery, and **as of 2026-09-21 (WP-22(c), extension 0.1.7) the VS Code client DOES exactly that**, after a grace, under `ermine.preview.restartAfterStuckSeconds` whose DEFAULT IS 0 = never: it arms on the rising edge, disarms on the falling one, and on expiry calls `client.stop()` and starts a new client (WP-22(c) review F2: what `stop()` PUTS ON THIS WIRE -- whether it sends `shutdown` and `exit` at all, and whether it kills the process afterwards -- is `vscode-languageclient`'s own behaviour and is UNVERIFIED here, its source unread; what IS READ, `Main.scala:336-353`, is that a server which receives `shutdown` then `exit` answers, calls `preview.shutdown()` and reaches `System.exit`, with a wedged preview thread unable to stop it because that thread is a daemon and `System.exit` halts the JVM regardless). **IT CHANGES NOTHING ON THIS WIRE**: no new method, no new key, no new notification, and the server is not changed in any way -- it cannot tell that restart from any other client-initiated one, which is exactly why the caller is the one that has to remember (Q18). The withdrawn rule is kept as the record: **(5) WP-6 STAGE 1 (2026-09-20), REMOVED: A CANCEL THAT SUCCEEDS SENT NO PAIR AT ALL.** With `ermine.preview.cancelOnTimeout` on, the watchdog's first deadline cancels the evaluation, and the incident ends with one 500 and a rebuilt render session: no `{stuck: true}`, no `{stuck: false}`, and no `"stuck": true` on the answer. So **a client must not expect one rising edge per watchdog incident**, and must not read a missing falling edge as a wedge. The pair is sent only when the cancel did NOT take within the grace and phase 2b fell back to this row's own behaviour (§2.5) |
| `ermine/schema` | request, extended | `{uri, binding, roots}` -> the schema, or `{"parameters": false}` for a report with NO parameters (WP-34), or `{error, reason?, stuck?}`, alongside `type`/`name` | **WP-34 (Q27 option (i), 2026-09-24): a binding typed `Node` or `Fetch Node` is a report with no parameters, and its schema answer is the MARKER `{"parameters": false}` (`Runner.NoParameters`), exactly one key -- NOT a JSON Schema document, not even the schema of `{}`, so no client path can write a params skeleton or a `<binding>.schema.json` from it. The extension (0.1.16, `preview-core.js` `isNoParametersAnswer`/`schemaAnswerOutcome` -> `noParameters`) writes nothing on the first pick, renders with `{}`, holds the "no params file" line (`holdsParamsNotice`), and the D8 refresh and Write Params Skeleton write nothing. `ermine/render` for such a report accepts `params` `{}`, `null` or absent; anything else is a 400 at `$.params`, *"M.b takes no parameters; send {} or leave "params" out (it was sent the key "k")"*. An OLDER extension reads the marker as a schema and writes a `null` params file (the render still succeeds).** **with a `binding` key the request is a preview-queue job** answered from the render session (§6); the `type`/`name` forms stay on the resident (`Schema.scala:807-816`). **Q7, decided 2026-09-20**: the binding form carries the same three keys a render identifies its report by, and resolves it through the SAME function, so a schema and a render share one session in either order. Its `{error}` texts are a render's reasons word for word -- Q5's "cannot read `<name>`", "no module header could be read from `<name>`", "not an Ermine source file: `<name>`", the 409 shadow text -- scrubbed, file names only, **and since Q15 with the same machine-readable `reason` beside `error`, under the same rule: only the front half's own failures carry one**. `{module, binding}` is GONE: a request with `binding` and no `uri` is `{error}` naming the key. **CONSEQUENCE FOR THE EXTENSION (WP-7/WP-8)**: because a schema now computes the root set the same way, a schema whose `roots` DIFFER from the last render's DISCARDS that session and boots another, exactly as a render with different roots does (§2.4). The extension must send the SAME `roots` on both, for the same picked report. **`stuck: true` (Q8) sits BESIDE `error`** on the two refusals that mean the wedge -- the one `schema` sends while stuck, and the one the watchdog's queue drain sends -- and on no other `{error}` |
| `ermine/preview/connect` | request | **AS BUILT 2026-09-24 (WP-13 server half, DB programme stage 2a; `tracker/db/SERVER.md` §6):** `{profile: {id, dialect, url, user?, driver?, scanner?}, password?}` -> `{ok: true, id, dialect, host, database, server, seq}` or `{ok: false, class: "auth" \| "driver" \| "unreachable" \| "profile", message, kept, reason}` with `reason` = `connect-auth` \| `connect-driver` \| `connect-unreachable` \| `connect-profile` (Q-S4 (a)). A connect refused while STUCK is the same failure shape, class `unreachable`, `kept: true`, plus `"stuck": true` | §8. The **body is never logged** (WP-1). Absent `user` means no `user`/`password` connection property (the SQLite case); a `password` without a `user` is a `profile` refusal. `profile` (Q-S3 (a)) is answered BEFORE ANY SOCKET and before the queue: a malformed profile, an unknown dialect or `noTransactions` off SQL Server (`Backends.scannerFor`), a URL not starting `jdbc:` or whose subprotocol disagrees with `dialect`, a URL carrying credentials (A9 keys in any case, or `//user:pass@`), a relative `jdbc:sqlite:` path (Q-S5 (b)) or an absolute one that does not exist. Everything else is a PREVIEW-QUEUE JOB ordered after the render in flight: `Class.forName(driver)`, `DriverManager.getConnection(url, props)` with `user`/`password` as `Properties` entries and, for SQL Server, `loginTimeout` = half `ermine.preview.timeoutSeconds` clamped to 1..15 s (15 when the watchdog is off). Classes per §8.3 on SQLState/vendor code only: `18456`/`28000` -> `auth, kept:false`; `18486`/`18487`/`18488` -> `auth, kept:true`; `ClassNotFoundException`/`LinkageError`/"No suitable driver" -> `driver`; everything else (refused, DNS, TLS, timeout, an unknown database) -> `unreachable`. On success the previous connection is closed off-thread (2 s bounded wait), the render session discarded, the new one HELD (`Runners.fromPersistentConnection`). `host`/`database` are parsed from the URL (`getCatalog` if the URL names none), `server` is the driver's product version, `seq` counts successful connects per process. Every failure `message` and every log line is scrubbed of the profile's url, host and user (A10); a document is never scrubbed |
| `ermine/preview/disconnect` | request | `{}` -> `{ok: true}` | closes the held connection and discards the `Runner` (§7.2); the next render answers `{ok: false, status: 503, message: "not connected", reason: "not-connected", generation}` until a connect SUCCEEDS (Q-S2 (a); a failed connect leaves it disconnected), answered BEFORE placement so it costs no boot; `ermine/schema` still works (it scans nothing). A queue job; idempotent. **BUILT 2026-09-24** |
| `ermine/preview/disconnected` | notification, server -> client | `{reason}` | after a recycle or a failed scan that closed the connection; the extension reconnects (§7.2). **BUILT 2026-09-24**: before every render with a held connection the preview asks `isValid(2)`; a dead connection is dropped (session discarded, closed off-thread, disconnected) and this is sent with `reason: "connection-lost"` (the one reason today); that render answers the 503 `not-connected` |
| `$/cancelRequest` | notification | `{id}` | §2.5 |
| `window/workDoneProgress/create`, `$/progress` | request then notifications, server -> client | the LSP shapes (*external*) | §2.5 boot progress; the `create` from the dispatch thread through `ask`, the `$/progress` from the preview thread through `notify` |

`Rpc.scala` changes (WP-1), all in one file:

| Line (at e0d2f9df) | Change |
|---|---|
| `Wire.receive` logs the raw body before the method is known (`:318`) | the incoming log line moves to `Server.handle` after `Json.parse` (`:442-452`) and is `">> <method> [redacted]"` for methods in `Rpc.Redacted = Set("ermine/preview/connect")`; the unparseable branch (`:449`) keeps logging the parser's error only. That error never carries body text: the parser echoes at most one character (`Rpc.scala:121`) or a number token (`:144`), never a string. **Corrected at WP-1:** that was false as mined -- at e0d2f9df two escape errors (`Rpc.scala:166`, `:169`) quoted up to four characters from INSIDE a string literal (`bad \u escape 'ZZZZ'`, `bad escape '\q'`). WP-1 removed both echoes, leaving the offset, and pins the claim with a property (`TestLspRobustness`, A group): every quoted fragment is at most one character or a number token, and no two-character UPPER-CASE window of the input appears anywhere in the error. The second half is a marker check, not a check over every substring: every fixed word in a parser message is lower-case, so an upper-case pair can only have been echoed, while searching for arbitrary two-character substrings would falsify a sound parser on a collision with its own English ("of" inside "offset").  The property's own comment carries the alphabet argument |
| `Wire.send` (`:340-346`) | `synchronized`; the `<<` line (`:345`) is unchanged: no server-sent message carries a secret, and after §8's scrub none carries a URL or a host either |
| `Server.request` answers synchronously (`:471-481`) | `onRequestDeferred`; the property "A: the dispatcher answers every message in order, once, with the right shape, and runs to EOF" (`TestLspRobustness.scala:371`, and `:352-370` for what "in order" means once an answer is deferred) is extended to a deferred handler answering from another thread |
| `$/` dropped (`:488`) | `onNotification("$/cancelRequest")` is consulted first |
| nothing sends from a second thread | `notify` from the preview thread is legal once `send` is synchronised; `ask` stays dispatch-only (§2.3) |

The dispatch loop has **one** idle slot (`Rpc.scala:394-397`), taken by the diagnostics
debounce; the render watchdog therefore uses a `Timer` thread and the synchronised `send`,
not the idle slot.

## 5. The panel and the bundle

Decision (the user's): **webpack, watch-to-disk**; no `webpack-dev-server` (a webview cannot
load from it under its CSP, *external*).

**FIRST PLAYTEST OBSERVATIONS 2026-09-23** (the user, a real VS Code, extension 0.1.14; the first
time anything in this section was OBSERVED rather than read or measured in jsdom;
`tracker/PLAYTEST-RESULTS.md` "Findings"):

| observed | what |
|---|---|
| the panel opens beside | with `ermine.preview.target` = `panel`, **Ermine: Preview Report...** opened the `Ermine preview` webview in a column beside the editor |
| the notice page renders | the page-build failure below reached the user as the panel's notice page (`buildPanelNoticeHtml`), not as a blank panel: the S2 fallback works in a real webview |
| **the CSP guard bug (F1)** | the notice read *the preview page could not be built: buildPreviewHtml: cspSource "'self' https://*.vscode-cdn.net" contains a character that would change the policy*. The 0.1.14 guard refused any space or quote; no page was ever built. FIXED in 0.1.15 (commit pending): each space/tab-separated token must be exactly one CSP source expression |
| **the real `cspSource`** | `'self' https://*.vscode-cdn.net` (MEASURED by the user): a list, one entry a quoted keyword. Every test before 0.1.15 used a single bare token, and this section's CSP rows assumed one. The page's CSP for that value is now pinned: `default-src 'none'; script-src 'self' https://*.vscode-cdn.net 'unsafe-eval'; style-src 'self' https://*.vscode-cdn.net 'unsafe-inline'; img-src 'self' https://*.vscode-cdn.net data:;` |
| not yet observed | whether any document DRAWS in the panel (E2), the writers under the CSP (E3/E9): the page never got built |
| **F3: the panel drew, but not legibly (0.1.15 + the bundle)** | with F1 fixed the page loaded and `Sales` drew, but, in the user's words, *"I can't see shit in the widgets generated. Text is too light, and it doesn't look like it's populating properly."* Reproduced headlessly with the real `buildPreviewHtml` and bundles (`scratch-widget-preview/panel-render/DIAGNOSIS.md`). There were three causes. (1) `runTabular` only QUEUES a table. The legacy page draws it with `ermine_htmlwriter_conf.renderFunction(ermine_htmlwriter)` after `renderPage` (`HTMLWriter.scala` `wrapHeader`), and the page never made that call, so every table was a header and a row of `.`. (2) The page's text was `--vscode-foreground` (`#9e9e9e` in the user's theme), which writers cells inherit: 2.2:1 on `#E9E9E9`, at the writers' 10px. (3) `Grid` had no CSS, and the writers size each table to the WINDOW, so tables overlapped their neighbours and the one-column table was drawn at 0px height, whatever the timing (after two animation frames, after 500 ms, or alone). **FIXED in `client/src/host/page.ts`, commit pending; no new `.vsix`.** The page calls `renderFunction` once after each render. The document is on white paper with `#222` text, at 12px in tables. There is grid and table-pair layout CSS. MEASURED in the harness (`scratch-widget-preview/panel-fix/RESULTS.md`): rows 8/4/8 all visible; 8/4/8 → 3/4/8 → 8/4/8 over three renders; cells 13.1:1 or better and headers 6.49:1 in dark and light themes; two tables per grid row at 1200 and 1600px, stacked at 800px. Pinned by `(pg-f3-*)`, with reverse mutants killed by name. The review's M-1 is fixed: the page-error box inside the paper is `#b00020`, 7.33:1 |
| **F3 observed fixed** | **OBSERVED by the user, 2026-09-23** (VS Code 1.139.0, Vue Theme): after the bundle rebuild the panel drew `Sales` with its tables (*"It renders now, the tables show up"*), and it re-rendered on a params-file save and on a `Sales.e` save (*"yup, it updates"*). Whether that reload came from the bundle watcher or from re-running the command is NOT recorded. |

| Item | Decision | Note |
|---|---|---|
| Node build | `tsc -p tsconfig.json` and `npm test` untouched (`client/package.json:12`, `:16`) | webpack is additive |
| Bundle | **AMENDED 2026-09-23 BY WP-10 S2 (AS BUILT; REVIEWED AND COMMITTED `26d22f61`): the `ermine-host` entry is now `dist/src/host/page.js` (the panel PAGE, which re-exports the reducer), `ermine-host.js` 24,885 B (MEASURED, `ls -l` after `npm run bundle`; was 10,832 B), still no zod and under 64 KiB (`(b-host-surface)`, now against `page.ts`'s exports).** **AMENDED 2026-09-21, WP-9 AS BUILT AND MERGED** (`tracker/WP-9-AS-BUILT.md`, folded in here; this document is now the authority). **TWO ENTRIES, NO LOADERS**: `ermine-client` (`library: {name: 'ErmineClient', type: 'window'}`, from `dist/src/index.js`) and `ermine-host` (`{name: 'ErmineHost', type: 'window'}`, from `dist/src/host/index.js`), `target: 'web'`, `mode: 'development'`, `optimization.moduleIds/chunkIds: 'named'`, output `client/dist/browser/[name].js` with `[file].map` beside each, under the already-ignored `client/dist/` -- **`.gitignore:10`, not the `:11` this row used to cite (D3, MEASURED, and re-checked on the merged tree)**. webpack's INPUT is the `tsc` OUTPUT, so `bundle` = `npm run build && webpack` and `bundle:watch` = `node client/scripts/bundle-watch.js`, which runs one full `tsc` and then `tsc --watch` and `webpack --watch` together; a bare `webpack --watch` watches `dist/src/`, i.e. not the files being edited, and fails outright from a clean checkout (MEASURED by the WP-9 review). **THE SUPERSEDED WORDING, KEPT AS HISTORY: `entry: src/index.ts`, `ts-loader`, one entry, output `client/dist/browser/ermine-client.js`.** Dropping `ts-loader` (the design review's D5, recommendation (b)) is **THE ORCHESTRATOR's decision for this build, NOT the user's** -- taken on the review's recommendation, with the user told -- and it is REVERSIBLE: two constants and two commented blocks in `client/webpack.config.js` (READ). **Q19 does not touch this row**: `'unsafe-eval'` permits `eval`, not inline `<script>`, so D4's second entry is required exactly as before | the host script reads `window.ErmineClient.parseDocument` etc. The whole vendored closure is `webpack 5.111.1` + `webpack-cli 7.2.3`, exact-pinned, and nothing else, permanently (MEASURED, §14's WP-17 row carries the delta) |
| `devtool` | `'source-map'` explicitly. **AMENDED 2026-09-21: AS BUILT THIS IS PINNED BY A TEST, not only by the config.** `(b-no-eval)` in `client/test/bundle.test.ts` fails if either output contains `eval(` or `new Function` (MEASURED on the built bundles: 0 and 0), and `(b-sourcemap)` fails unless a separate `.map` sits beside each bundle and the `sourceMappingURL` names it rather than an inline `data:` URI -- an inline one would mean an eval-flavoured devtool. The "D9's static test" the CSP row above names is that file and those two tests | *external*: `mode: 'development'` defaults to `eval`, which a webview CSP without `unsafe-eval` blocks silently |
| Host page CSP | **AMENDED 2026-09-23 BY WP-11 (= WP-10 S4, AS BUILT; REVIEWED GREEN/GREEN AND COMMITTED `56f608cd`): THE POLICY IS UNCHANGED, CHARACTER FOR CHARACTER** (`'unsafe-eval'` stays, no `blob:`, no `font-src`, no `connect-src`; re-pinned on the page WITH the writers by `panel S4 (csp)`). `localResourceRoots` is now ONE list of at most TWO entries, `core.previewResourceRoots(bundle.dir, writers.root)`: the bundle folder and, only when the page loads anything from it, the writers' `web/` folder (`glue pins (WP-11) the writers`; `panel S4 (roots)` checks every URI the page references lies under one of them). **AMENDED 2026-09-23 BY WP-10 S2: WIRED.** `setPanelHtml` builds the page with `core.buildPreviewHtml({cspSource: webview.cspSource, client, host}, {stamp})` from `asWebviewUri` of `<root>/client/dist/browser/*.js`; `localResourceRoots` is exactly that directory (`core.previewResourceRoots`, the writers' slot empty until S4); `enableScripts: true`, `enableForms: false`, `enableCommandUris` left `false`. A failed bundle check gets a DIFFERENT, static page (`core.buildPanelNoticeHtml`, CSP `default-src 'none'; style-src 'unsafe-inline';`, no script). **AMENDED 2026-09-23 BY WP-10 S1 (BUILT: `core.previewCsp` / `core.buildPreviewHtml`; reviewed and committed `1d83b5a8`; wired since by S2). THE POLICY AS BUILT, one line, asserted character for character by `panel (csp)` in `editor/vscode/test/preview-core.test.js`: `default-src 'none'; script-src ${cspSource} 'unsafe-eval'; style-src ${cspSource} 'unsafe-inline'; img-src ${cspSource} data:;`. NO NONCE (the design review's W3): the second webpack entry removed the need, `acquireVsCodeApi()` lives in the host bundle, and `panel (html)` asserts ZERO inline `<script>` bodies -- so D4's second half is RETIRED, not built. NO `blob:` (U5, TAKEN) and NO `font-src` (F3: 0 `@font-face` in the writers CSS, MEASURED by the review). `default-src 'none'` keeps `connect-src` shut, which is F2's check that the preview mints no deferred token (U6, TAKEN: `fetchData` is a rejecting stub, S3). A `cspSource` containing whitespace, `;`, `,`, a quote, `<`, `>`, `&` or a backslash is REFUSED (the builder throws), never escaped into the policy. Whether a webview ENFORCES any of this is UNOBSERVED -- jsdom enforces no CSP.** The row as written: `default-src 'none'; script-src ${cspSource}; style-src ${cspSource} 'unsafe-inline'; img-src ${cspSource} data:` -- **AMENDED 2026-09-20 BY THE USER'S Q19 DECISION: `script-src` also carries `'unsafe-eval'`, IN THIS WEBVIEW ONLY** (*"oh yeah unsafe-eval sounds great. We'll remove it later on if need be"*), because the committed writers bundle is a webpack-4 `eval` build (D1, MEASURED: 574 `eval(`) and would otherwise be blocked silently. **OUR OWN bundles must still contain no `eval(` and no `new Function`** (D9's static test), so the day the writers bundle is rebuilt the flag comes out. D4's nonce is unaffected | the legacy renderers inject styles; the eval is the LEGACY bundle's, not ours |
| Legacy renderers | **AMENDED 2026-09-23 BY WP-11 (= WP-10 S4, AS BUILT; REVIEWED GREEN/GREEN AND COMMITTED `56f608cd`): D6 IS BUILT.** The page loads `htmlwriter.js` FIRST, then `ermine-client.js`, then `ermine-host.js`, from `ermine.preview.writersPath` (U3; empty = `<resolveServer().root>/../ermine-writers/writers/html/src/main/resources/web`, THIS MACHINE's sibling layout, not a guarantee), with THREE `<link>`s: **`common.css`, `htmlwriter.css`, `htmlwriter_classic.css`**. The theme was chosen by READING the CSS files (none has an `@import`, MEASURED by `grep`): `htmlwriter.css`'s own comment removes DataTables' sort arrows ("so that they arent visible. but sorting still works"); `htmlwriter_classic.css` has no `url()` and paints sorted cells white / `#E9E9E9`, the grey of `common.css`'s `.tabular`; `htmlwriter_dark.css`'s header comment says it "Add[s] back in the sorting arrow indicators", three times through `url("/content/themes/base/images/mainSprite.png")`, which a webview can never load, so every arrow would be an empty 7x5 box. **CONSEQUENCE FOR W7: only ONE of the two named sprites can reach the console** -- `common.css:125`'s `url("/CIQDotNet/images/TopMenuBar/tmbllsprite.png?urwvid=1")` (on `.headerlabel`); `mainSprite.png` lives only in the dark sheet the panel does not load (INFERRED from the files; no browser has shown either). `javafxwriter.css` is not loaded. **AMENDED 2026-09-23 (the design review's W7 and W9). SCRIPT ORDER, BUILT IN S1 by `buildPreviewHtml`: writers -> client -> host, classic `<script src>`, no `defer` / `async` / `type=module`, because the writers assign `window.ermine_htmlwriter` inside a `DOMContentLoaded` LISTENER and listeners fire in registration order (READ; UNOBSERVED in a browser). The writers slot is optional until S4. THE CSS (D6): three `<link>`s -- `common.css`, `htmlwriter.css`, one theme; NOT `javafxwriter.css` -- the slot BUILT in S1, the URIs S4's (`ermine.preview.writersPath`, U3). TWO `url()`s WILL FAIL in a webview and are EXPECTED console noise, not a broken panel: `common.css` -> `/CIQDotNet/images/TopMenuBar/tmbllsprite.png?urwvid=1` and `htmlwriter_dark.css` -> `/content/themes/base/images/mainSprite.png` (MEASURED by the review). jQuery (14 webpack modules) and Highcharts (11) are BUNDLED in the writers bundle (MEASURED by the review), so no extra `<script>`. The style-box click-through always POSTs and CANNOT work under `default-src 'none'`: it fails silently BY DESIGN. `treeMap` stays deliberately unregistered.** a second `<script>` from a second `localResourceRoots` entry at the `ermine-writers` checkout's built bundle; the host passes the global into `render`'s env, read as `ctx.env.htmlwriter` (`client/src/legacy.ts:327-333`) | without it `scorecard`/`headline`/`crosstab` render and `table`/`drilldownTable`/charts show the dispatcher's error box, the designed "unsupported" behaviour (`JSON-GUIDE.md:1686-1690`) |
| **The writers global** | **AMENDED 2026-09-23 BY WP-11 (= WP-10 S4): THE HOST SIDE IS VERIFIED BY READING AND PINNED IN JSDOM, NOT OBSERVED IN A BROWSER.** `client/src/host/page.ts` was NOT changed: `boot` registers its `DOMContentLoaded` listener when the host script (script 3) runs, i.e. after the writers' listener (script 1), and posts `ready` from it; `renderDocument` reads `win.ermine_htmlwriter` at RENDER time, which is after the extension answered `ready`. `(pg-writers-global)` in `client/test/page.test.ts` drives the REAL client in a JSDOM with a stub listener registered first: the order is `writers`, then `ready with the global present`; `table` reaches the stub's `runTabular`; without the global `table` is its own `.ermine-widget-error` under the writers banner. Two reverse mutants die by that name: `ready` posted without waiting for `DOMContentLoaded`, and the global captured at boot. **CLOSED IN CODE 2026-09-21 BY WP-9. The superseded wording, kept as history: *"open (Q1): `client/src/index.ts:5` documents `window.htmlwriter`"* -- BOTH HALVES ARE NOW FALSE**: the file no longer says that, and Q1 is not open. The global is `window.ermine_htmlwriter`, assigned ONLY inside a `DOMContentLoaded` listener (`../ermine-writers/writers/js/htmlwriter.js:10-13`, READ), and the name AND the timing are written into `client/src/index.ts`, `client/src/legacy.ts` and `client/README.md`; `requireHtmlWriter`'s error text now names the real global and the timing, pinned by `(w-no-writer)` in `client/test/widgets.test.ts`. **The client's LOOKUP was never wrong**: it reads `ctx.env.htmlwriter`, an ENV KEY the host fills, and the package reads no writers global anywhere (MEASURED: a recursive grep of `client/src` for the global and for `window.` leaves one non-comment hit, `src/legacy.ts:339`, inside the error-message string). Narrower than "reads no global at all", which would be false: `client/src/format.ts:121` reads the ambient `document`, guarded by `typeof document !== "undefined"`. The object `legacy.ts` types is still `const htmlwriter = {}` (`ermine-htmlwriter.js:45`). **Still never observed in a real browser here: nothing of WP-9 has run in a browser or a webview** | WP-11, now the BROWSER half only |
| Host-page logic | **AMENDED 2026-09-23 BY WP-10 S2: THE PAGE EXISTS** -- `client/src/host/page.ts` `boot(win, api)`: `acquireVsCodeApi()` once (autostart, only where it exists), `ready` after DOMContentLoaded, every post through the pure `pageStep` (snapshot envelopes only, a `seq` not above the last applied is ignored, re-render ONLY when the document's generation or payload changed), banner / hint / dimming from `presentation()`, the stuck banner's **Restart Language Server** button posting `{type: "intent", kind: "restartServer"}`. **AMENDED 2026-09-21: THE REDUCER SKELETON EXISTS** -- `client/src/host/index.ts` (307 lines) with **19** `node --test` cases in `client/test/host.test.ts`; WP-10 owns the panel around it. `applyMessage(state, msg)` is a **PRESENTATION reducer ONLY (D10)**: it decides what the panel SHOWS for a message it is handed and arbitrates nothing -- not `seq`, not "is this answer current", not "did the wedge clear", all of which stay EXTENSION-side, split between `editor/vscode/src/preview-core.js` (decidable from data alone) and `editor/vscode/src/extension.js:447-456` (needs the editor; the as-built cites `:277-285`, which was right on `wp9-bundle` before WP-22 stage 2 pushed the comment down -- READ on the merged tree). **NINE message kinds, not the eight listed as written** (`render`, `error`, `stale`, `stuck`, `reloadBundle`, `unsaved`, `switching`, `offline`, **plus WP-22's `held`**, D11), and §4's withdrawn rule (5) is not encoded. Banner precedence, highest first: `offline > stuck > held > reloading > switching > error > stale > initial`, with `initial` = §5's "Pick a report" so a panel with no document always says something. Dimming rule, one sentence: **a document on screen is dimmed exactly when nothing is currently trying to replace it**. **Any ANSWER (`render` or `error`) clears a `reloadBundle` announcement** -- it was the only latch without a falling edge and it outranks `error`, so without the edge it would have masked every later failure for the life of the panel (MEASURED by the review: raised, it wins 16.5 % of generated states). An unknown kind returns the state BY IDENTITY, so a newer extension cannot blank an older panel; blank `message` strings are normalised at the boundary, a defect the properties found. `held` carries no panel button (WP-22's **Render anyway** is extension-side, and a second one would be a second decision site). The module imports NOTHING -- not `../document`, not zod -- which is why `ermine-host.js` is 10,832 B | the DOM output of `parseDocument -> render` is already covered in jsdom; scroll, `retainContextWhenHidden` and panel lifetime are VS Code's behaviour, not ours; `@vscode/test-electron` downloads VS Code and is impossible offline (§10). Built by the same webpack config, as its second entry |
| Document / JSON toggle (WP-31) | **BUILT 2026-09-23, client bundle only (§14 WP-31); NOT OBSERVED IN VS CODE (E15).** A toolbar between the banner and the paper, **Document** / **JSON**; JSON is `JSON.stringify(document, null, 2)` or the error's four fields, in a `textContent`-only `<pre>` on the paper. The choice is VIEWER-LOCAL (`setState`/`getState`, never posted, not in the reducer); a toggle never re-renders; the document it hides is laid out off-stage because the writers draw a `display:none` document wrong (MEASURED). The raw answer is not in the panel (Q28) | banners keep precedence: the toolbar is below them; the toolbar and the `<pre>` are not dimmed |
| Initial state | **AMENDED 2026-09-23 BY WP-10 S2 (AS BUILT):** the reducer's `initial` banner text is what is drawn; there is no progress bar -- `stale` draws the banner "re-rendering" above the kept document instead. before the first render: "Pick a report: **Ermine: Preview Report...**"; while a render runs: a thin progress bar, the last document kept | |
| Errors | **AMENDED 2026-09-23 BY WP-10 S3: the fast-mode suffix stays composed extension-side exactly as S1 built it (no tenth kind), and a WIDGET that asks for a deferred relation shows its OWN error box, not a banner:** the page's `fetchData` (`client/src/host/page.ts` `refuseDeferred`, U6) REJECTS (reworded by WP-10 S5 round 2, Q24) with, at S3, "the preview delivers every relation inline -- inline is the only delivery its render request asks for -- so it cannot fetch the deferred relation "<token>" (the panel has no network access: its CSP has no connect-src)", the dispatcher draws `div.ermine-widget-error[data-widget][role=alert]` with "a deferred relation could not be resolved: ..." in place of that widget, and the page logs it once to the output channel; nothing is fetched (`(pg-fetch-deferred-box)`: no `fetch` or `XMLHttpRequest` in either realm). **AMENDED 2026-09-23 BY WP-10 S2: WIRED** -- every `{ok:false}` answer and every params refusal reaches the panel through `core.panelAnswerStep` beside the `lastAnswer` assignment, with the fast-mode sentence read from `ermine.fastMode` at post time. **AMENDED 2026-09-23 BY WP-10 S1 (W5), BUILT: the fast-mode sentence is composed EXTENSION-SIDE into the `error` message by `core.panelMessagesFor` (`core.FAST_MODE_SUFFIX` = ` -- fast mode is on: type errors are not shown in Problems`); the reducer gets NO tenth kind. S1 appends it to EVERY `error` while fast mode is on, not only to load failures: the suffix is a GENERAL REMINDER that fast mode hides type errors, not a claim about that error. The narrower reading IS decidable (`shouldRefreshSchema`, `preview-core.js` ~:3672, already tells a 400 at `$.params` (the report compiled) from a 404/409 (no report reached) from a 500), so appending only on 500 is a one-line change left to a later stage -- AN S1 DECISION, reviewed GREEN with this correction (the S1 review's must-fix 1: the earlier wording said the reading was not decidable, which was false). A blank server message still says "the render failed" before the suffix, so the banner never reads as the suffix alone. A params refusal (`paramsRefusalAnswer`) is an `error` like any other.** `{ok: false}` -> a banner with `status`, `message`, `path`; the last good document stays below, dimmed. A load failure shows there **and**, for the same file, in Problems through the resident's own diagnostics (`Main.scala:188`) -- unless fast mode is on, when the banner adds "fast mode is on: type errors are not shown in Problems" (`config().get("fastMode")`, the same read as `extension.js:69-71`) and the preview status item carries the "(fast)" suffix | |
| Unsaved | **AMENDED 2026-09-23 (W6): NOT WIRED -- no producer exists in `extension.js` (MEASURED by the design review: no `isDirty`, no `textDocuments` scan). S1 BUILT the pure half: `core.unsavedNames(documents)` (dirty `languageId === "ermine"` documents by base name, sorted, de-duplicated) and the `unsaved` slot of `core.panelView`; **NOT WIRED IN S2 (as built 2026-09-23: `panelViewNow` passes `unsaved: []`) -- OPEN (W6), no stage owns it yet.** a non-blocking hint "unsaved: Chart.e" in the banner area whenever a `.e` document in the workspace is dirty (`workspace.textDocuments.some(d => d.isDirty && d.languageId === "ermine")`, *external*): the preview follows saves (§2.4) and that must be visible, not documented. Rendering is never refused for it: a buffer closed without saving would leave nothing dirty and the hole open, and the two-file loop (widget module + renderer) is mid-edit as a normal state | |
| Stale | **AMENDED 2026-09-23 BY WP-10 S2: WIRED** -- `pending` is `renderInFlight || coalesceTimer !== undefined`, and a snapshot is posted from `setPreviewStatus`, so the scheduled, sent and settled edges all reach the panel. **AMENDED 2026-09-23 BY WP-10 S1, BUILT: `stale` is sent `true` while a render is pending OR when the last current answer carries the server's own `stale: true` (§2.5, read off the answer), and it is sent AFTER the answer pair because both answers clear it.** `stale: true` -> the banner "re-rendering" until the next answer | §2.5 |
| **Stuck (Q8, decided 2026-09-20)** | **AMENDED 2026-09-23 (the design review's W2), SETTLED: "the panel keeps the highest `seq`" is NOT meant literally, and WP-10 does NOT move the mark into the panel.** Arbitration cannot recover a dropped message, and the extension is the single writer (D10): `core.panelMessagesFor` takes `stuckReduce`'s ARBITRATED state whole (via `core.panelView`) and NEVER reads an answer's own `stuck` key, because rule (3) decides whether that per-request marker applies -- `panel (stuck)` pins both arms against a REAL captured `stuck:true` answer, and the reverse mutant that reads the answer's key is killed by it. `(h-stuck-no-arbitration)` stands unchanged. The conditional sentence below ("if this row's wording is meant literally...") is RETIRED. The row as written: `stuck: true` on an answer, or `ermine/preview/stuck {stuck: true}`, -> a banner carrying the message and **the Restart Language Server button** (`ermine.restartServer`, the extension's own command): this is where resolution A4 puts it, because the LSP cannot make a client run a client-side command from a `window/showMessageRequest` answer (*external*). `ermine/preview/stuck {stuck: false}` (Q10: the wedged evaluation came back) clears the banner, and its message asks for a re-render -- every `invalidated` of the stuck interval was dropped unsent, so the panel's document may be behind the files. The standard `window/showMessage` arrives beside each of them and needs no panel. **THE `seq` IS PER-PROCESS**: the panel keeps the highest it has seen and ignores lower ones, and RESETS that mark on the **Stopped -> Running** transition in the row below, because a restarted server counts from 1 again (§4's rule (1), DD-2). **AMENDED 2026-09-21 BY WP-9 AS BUILT (D10): "the panel keeps the highest it has seen" IS THE EXTENSION KEEPING IT.** The panel's `applyMessage` is presentation only and applies a lower `seq` as sent -- `(h-stuck-no-arbitration)` in `client/test/host.test.ts` pins exactly that -- and the independent WP-9 review agreed the split is right and that THIS ROW is the thing to amend, not the reducer. **If this row's wording is meant literally, WP-10 must move the mark into the panel and that test must be rewritten**; note too that `Webview.postMessage` is DOCUMENTED to drop messages to a webview that is not live, so panel-side arbitration could not recover a message that never arrived anyway (see WP-10's row) | §2.5, §13 Q8/Q10 |
| Switching | **AMENDED 2026-09-23 (W6): NOT WIRED, and cannot be until WP-13/14 (profiles) exist. The kind stays in the reducer (tested); `core.panelView`'s `switching` slot has no producer, so every snapshot sends `{kind: "switching", to: null}`, which keeps the slice overwritten.** during a profile or roots switch (§7.2): the last document dimmed under "switching to `<id>`" | |
| Server stopped | **AMENDED 2026-09-23 BY WP-10 S2 (AS BUILT):** `offline` is `stuckState.running === false` in the view, posted from `setPreviewStatus` on every transition; the panel's answers are NOT cleared on `Stopped -> Running` (the tab keeps its content across a restart and so does the panel), only on a pick change and at teardown. on the client's `Stopped` state (`onDidChangeState`, *external*): banner "server stopped -- last document kept", status "Ermine: preview offline", the document dimmed. On `Running`: the reconnect flow of §7.2 and a re-send of the last render -- **WHICH SINCE WP-22 (BUILT 2026-09-20) IS CONDITIONAL: if the picked report is the one that WEDGED this server and nothing has changed since, the re-send is REPLACED by one non-modal `showWarningMessage` offering Render anyway / Not now, and the status bar gains a fifth state, `held` (`$(warning) Ermine preview: held`), with the precedence offline > stuck > held > rendering > idle. The Stopped edge itself SETS the mark when a render of the pick was in flight (reason `died-mid-render`), which is the case where the JVM exits before the watchdog ever fires. `Not now` and a dismissal are the same answer; only `Render anyway` renders, and it clears the mark. A panel (WP-10) therefore has a NINTH message to carry, `held` -- §5's findings block D11 says so too.** Scroll and drilldown are lost, as for a bundle change (a hot restart, not a hot reload). By construction every input the loop needs -- picked (file, binding), params path, active profile id, last document, `generation` -- lives in the extension; the server holds nothing across a restart except the database | |
| Lifetime | **AMENDED 2026-09-23 BY WP-10 S3:** the panel now owns a second thing, the bundle watcher (Bundle reload row): created with the panel, disposed with it and in `disposePreview`, its one timer cleared with it; a bundle reload is one more `webview.html` set, so it lowers the ready latch like any other and the answer of a render in flight across it arrives in the new page's `ready` snapshot (H4, modelled). The page registers its `message` listener BEFORE it posts `ready` (the S2 review's N2 / R23, now pinned by `(pg-boot-listener-first)`). **AMENDED 2026-09-23 BY WP-10 S2: BUILT.** The ready latch (`panelReady`) is lowered at creation, on every `webview.html` set and on dispose; nothing is posted or queued before the page's `ready`; `ready` and `onDidChangeViewState` with `panel.visible` each post one full snapshot; `retainContextWhenHidden: true`; `onDidDispose` clears the globals; `disposePreview()` disposes the panel. The extension posts ONE shape, `{kind: "snapshot", seq, messages}` (`core.panelSnapshot`) -- the discriminant is `kind` (S1's `page.ts` contract), not `type`. **RENAMES AGAINST THE DESIGN REVIEW'S §2(c), as built:** the envelope is `{kind: "snapshot", seq, messages}` (the review wrote `kind` too, and S2 added `seq`); the intent is `{type: "intent", kind: "restartServer"}` (the review wrote `action`); the log is `{type: "log", message}` with no `where`. **AMENDED 2026-09-23 (the design review's W1; U2 TAKEN as (c)): THE RESYNC IS MANDATORY, and `retainContextWhenHidden` is a SEPARATE optimisation for scroll and drilldown only, never the delivery guarantee.** The vendored `@types/vscode@1.134.0` contradicts itself, verbatim: `index.d.ts:10018-10019` *"Messages can only be posted to live webviews (i.e. either visible webviews or hidden webviews that set `retainContextWhenHidden`)"* against `:10076-10077` *"You cannot send messages to a hidden webview, even with `retainContextWhenHidden` enabled."* Which sentence is true is UNVERIFIED; playtest step E5 settles it. The resync is ONE `{kind: "snapshot", messages}` ENVELOPE of `core.panelMessagesFor(view)`, folded from a FRESH state by `client/src/host/page.ts`'s `receive` (S1 BUILT the fold; S2 posts it on `ready` and on `onDidChangeViewState` when the panel is visible). **S1 FOUND (MEASURED, `(pg-h7-abandoned-reload)`) that loose messages are NOT always equivalent**: a reload announced and then abandoned before the FIRST answer leaves `reloading` raised on the one-by-one path, since only an answer lowers it. So S2 posts snapshot ENVELOPES, not loose messages. The row as written: `retainContextWhenHidden: true` (*external*; costs memory, keeps drilldown state); a bundle change re-sets `webview.html` and **loses** scroll and drilldown state -- accepted | |
| Bundle reload | **AMENDED 2026-09-23 BY WP-10 S3: BUILT AS W4 SAYS; REVIEWED 2026-09-23 DESIGN GREEN / IMPLEMENTATION RED ON A DOCS MUST-FIX, CORRECTED, COMMITTED `3b162527`; NEVER RUN IN VS CODE.** `watchBundle(dir)` in `extension.js` -- the ONE `createFileSystemWatcher` for it, `new RelativePattern(Uri.file(<root>/client/dist/browser), core.BUNDLE_WATCH_GLOB = "*.js")`, created by `openPanel` with the panel (both its branches) and disposed by `unwatchBundle` from the panel's `onDidDispose` and from `disposePreview`: **no panel, no watcher.** Its THREE arms (create, change AND delete) build `core.bundleWatchEvent(kind, uri.fsPath)` into ONE pure coalescer, `core.bundleWatchStep(state, input)` with `Date.now()` passed in: every event pushes ONE shared deadline `core.BUNDLE_QUIET_MS` = **250 ms** out (the whole folder, not per file); the FIRST event of a burst is announced -- a snapshot whose view has `reloading: core.bundleReloading(...)` true, i.e. the reducer's existing `reloadBundle` kind ("the client bundle changed; reloading") over the kept document; only a quiet period reloads, ONCE: `reloadBundle` re-checks the folder with S2's pure `previewBundleCheck` (this replaces the "`existsSync` of both entries" below) and calls `setPanelHtml` -- the page with a fresh `?v=Date.now()` on both scripts when whole, the static notice page when absent or half-built, and the page again when it returns (H4) -- which lowers the ready latch, so the new page's `ready` brings the snapshot (with `reloading` false again). One output-channel line per reload (`core.bundleReloadLine`), plus `setPanelHtml`'s own `preview: <title> -- <message>` line when the bundle is not whole (two lines then; the S3 review's N2). **What the vendored typings say (READ, not observed; the S3 review's M1)** (`editor/vscode/node_modules/@types/vscode/index.d.ts:13977-13979` and `:13996-14001`): "paths that do not exist in the file system will be monitored with a delay until created and then watched depending on the parameters provided. If a watched path is deleted, the watcher will suspend and not report any events until the path is created again." and "file events from deleting a folder may not include events for the contained files. [...] performance optimizations are in place to fold multiple events that all belong to the same parent operation (e.g. delete folder) into one event for that parent." So the W10 first run should recover once the folder is created, but `rm -rf` of the FOLDER most likely reports nothing and does NOT flip the page to the notice (deleting the FILES does); in every silent case S2's re-check on the next explicit command recovers. Playtest E8 records which happens. **THE S3 AMENDMENT ENDS HERE. AMENDED 2026-09-23 (the design review's W4), S3's to build: one webpack build writes FOUR files and a `*.js` glob matches two, so the watcher watches the FOLDER -- `createFileSystemWatcher(new RelativePattern(Uri.file(browserDir), "*.js"))`, the documented out-of-workspace form -- on create AND change, coalesced over >= 200 ms, with `existsSync` of both entries before reloading; then `reloadBundle`, a fresh `?v=` stamp on both script URIs (`buildPreviewHtml`'s `opts.stamp`, BUILT in S1), `panelReady = false`, and the new page's `ready` brings the snapshot back. What is re-sent is the SNAPSHOT, not only "the last document".** The row as written: `createFileSystemWatcher` on `client/dist/browser/ermine-client.js`, debounced ~200 ms (unverified atomicity of webpack's write), cache-busting query on the script URI, re-send the last document | |
| Bundle checklist | **AMENDED 2026-09-23 BY WP-11 (= WP-10 S4): THE THIRD, NON-FATAL STATE IS BUILT -- the writers missing.** `core.previewWritersCheck(where, listing)` over `fs.readdirSync` of the writers folder; `core.writersState(listing)` is `present` (`htmlwriter.js` + the three sheets), `half` (the script, not every sheet: the script and the sheets there load) or `missing` (no `htmlwriter.js`, or no folder -- FAIL-CLOSED: the page is built WITHOUT the writers). Unlike the bundle's two banners this one IS a snapshot message, because the page and its host script do load: the reducer's **`error`** kind (no tenth kind), status 0, no path, the check's own sentence; a failed answer keeps the one error slot and carries the writers sentence as a suffix (W5's pattern). Chosen because it is the only kind whose meaning is "this failed and nothing is trying to fix it"; `held`/`stuck`/`switching`/`unsaved` would each print something false and the rest carry no text. **Its cost, stated**: the document is DIMMED while the writers are missing, and the banner replaces the `initial` text before the first render. **And (the WP-11 review's N2, MEASURED on the real reducer): the banner also HIDES *re-rendering*** -- `error` outranks `stale`, so while the writers are missing or half there a render in flight shows no banner of its own until its answer lands; and the `half` state (a style sheet missing, the widgets still drawing) dims the whole document too. One output-channel line per page built. The writers folder is NOT watched: an explicit command re-checks a page built without the whole writers and re-sets it only when the fresh checks differ (`core.panelRecheck` / `core.panelReload`); a bundle rebuild re-checks too; a server restart does not. **The playtest rows: "`table` renders through the writers global" (E9) stays HUMAN, joined by E10 (a `pieChart` draws), E3 (no CSP violation but the one sprite) and E11 (a style-box click is inert).** **AMENDED 2026-09-23 BY WP-10 S2: THE BANNERS ARE BUILT, AS A STATIC PAGE, NOT AS A SNAPSHOT.** `core.previewBundleCheck(dir, listing)` over `fs.readdirSync` of `<resolveServer().root>/client/dist/browser`, fail-closed (`ok` only when BOTH entries are listed): `absent` ("The preview bundle is not built", the path, `npm install` + `npm run bundle`), `half` ("HALF-BUILT", which is present, which is missing, delete and rebuild), `no-root`. The reducer's `error` kind was NOT used: with `ermine-host.js` missing no script runs, so nothing could fold a snapshot and `ready` never comes. One output-channel line per page set. An existing panel re-checks on the next explicit command. **AMENDED 2026-09-23 (the design review's W10): "the bundle is not built" is the DEFAULT first experience on a fresh checkout (`client/dist/` is gitignored, and the review found this worktree with no `client/node_modules` and no `client/dist/browser` on 2026-09-22 -- both are present NOW, 2026-09-23, MEASURED by `ls`), so S2's missing-bundle and half-built banners are first-class features, not edge cases.** *as written*: "once per bundle-config change, by hand (jsdom cannot answer it): no console error under the CSP, `window.ErmineClient.parseDocument` present, `table` renders through the writers global". **AMENDED 2026-09-21 BY WP-9 AS BUILT: TWO OF THE THREE ROWS ARE NOW NODE TESTS** in `client/test/bundle.test.ts` -- the static half of "no console error under the CSP" is `(b-no-eval)` (no `eval(`, no `new Function` in either output), and "`parseDocument` present" is `(b-surface)`, whose expected key set is DERIVED from `require("../src/index")` rather than hand-written; `(b-host-surface)` does the same for `window.ErmineHost` and also pins that `ermine-host.js` carries no zod and stays under 64 KiB, and `(b-same-dom)` pins that the bundle and the CommonJS build render one document to identical `innerHTML` in the same JSDOM. **THE THIRD ROW, "`table` renders through the writers global", IS UNTOUCHED, STILL HUMAN, AND NEEDS A REAL WEBVIEW -- NOTHING OF WP-9 HAS RUN IN A BROWSER OR A VS CODE WEBVIEW.** It is **no longer blocked on a DECISION** (Q19 is decided), only on a browser. The five bundle tests SKIP, naming `npm run bundle`, when `dist/browser/` is WHOLLY absent, and FAIL loudly on a half-built one | WP-9 / WP-10 done-when. jsdom enforces no CSP, so "no console error under the CSP" keeps a human half too |
| Two windows | each window spawns its own `bin/ermine-lsp` (`extension.js:179`), hence its own preview session and its own held connection: two boots' memory (capped, §2.2) and two sets of `##` tables (§7) | stated, not solved |
| Multi-root | the server reads every folder's stdlib (`Main.scala:106-117`); the extension uses `folders[0]` for the server path only (`extension.js:43-46`). Profiles are user-scope (§8), so no folder question arises there; `ermine.preview.roots` and the params directory are per the picked report's workspace folder (§2.4, §6) | |

**WP-9 / WP-10 / WP-11: FINDINGS OF A READ-ONLY DESIGN REVIEW, 2026-09-20. NOTHING IS DECIDED HERE
AND NOTHING WAS BUILT.** The rows above stand; these are findings against them. **Nobody has run a
browser or VS Code on this branch**, so every claim about rendering, CSP enforcement or webview
behaviour below is UNOBSERVED; the labels are the review's own.

**AMENDED 2026-09-21, AFTER WP-9 WAS BUILT (`c2c83cdb`) AND MERGED (`cdd90193`). The findings
below are KEPT UNEDITED as the review's own record**; what became of each is: **Q1** --
answered by reading, and now CLOSED IN CODE (§5's writers-global row, §13's Q1 row, §14's
WP-11 row). **D1** -- unchanged, and its consequence is what the user's Q19 decision answers.
**D4** -- TAKEN: two entries; the nonce is still WP-10's. **D5** -- TAKEN as its recommendation
(b), tsc-first, **BY THE ORCHESTRATOR AND NOT BY THE USER**, and reversible in
`client/webpack.config.js`; the row below still reads "OPEN ... and is the user's", which is
the superseded wording. **D9** -- its two automatable checklist rows ARE node tests now
(`client/test/bundle.test.ts`), but `gate_client` STILL DOES NOT EXIST (MEASURED), so they
gate nothing until WP-10 registers it. **D10** -- followed to the letter, except that the
extension-side split is TWO files, not one: `editor/vscode/src/extension.js:447-456` itself
retracts the wording "every decision is in `src/preview-core.js`". **D11** -- all nine kinds,
`held` included, are in the reducer. **D3** -- FIXED in the Bundle row (`.gitignore:10`).
**D6**, **D8** -- untouched; WP-10's and WP-17's. **AND NOBODY HAS STILL RUN A BROWSER OR VS
CODE ON THIS BRANCH**: every WP-9 number is from `node`, `webpack` and `node --test`.

| # | Finding | Label |
|---|---|---|
| **D1** | **The committed legacy writers bundle is a webpack-4 `eval` build.** `ermine-writers/.../web/htmlwriter.js` (5,157,473 bytes) opens with webpack 4's bootstrap, contains **574 occurrences of `eval("`** -- the `devtool: 'eval'` module wrapper -- and **1 `new Function`**. Its own build scripts pass `--mode=development` in both variants and the `devtool` line is commented out | **MEASURED** (byte count, `grep -c`, samples, build scripts READ) |
| | **Consequence**: §5's `script-src ${cspSource}` without `'unsafe-eval'` would block every one of those module evaluations, so `window.ermine_htmlwriter` never appears and **WP-9's done-when ("the bundle checklist passes under a CSP without `unsafe-eval`") and WP-11's ("`table` renders through `runTabular`") are unsatisfiable as written** | **INFERRED** -- nobody has watched it fail in a webview |
| | Rebuilding that bundle is not cheap: `writers/js/node_modules` is absent and its devDeps are a 2019 toolchain (webpack 4, `node-sass@^4`, eslint-loader) under node 24 | READ; the rebuild itself **unverified** |
| **Q1** | **ANSWERED BY READING, no browser needed** (new Q19 is what stays open). `ermine-writers/writers/js/htmlwriter.js:10-13`: `document.addEventListener('DOMContentLoaded', () => { window.Object.assign(window, {ermine_htmlwriter, ermine_htmlwriter_conf}); ... })`. So the global is **`window.ermine_htmlwriter`**, and it is assigned **only on `DOMContentLoaded`** -- host code that reads it at script-evaluation time gets `undefined`, which `client/src/legacy.ts:326-333` would report as the designed "unsupported widget" box rather than as a timing bug. `client/src/index.ts:5` documents `window.htmlwriter` and is **wrong**. The config has no `library` field and `externals: ['window']`, so the side-effecting assignment is the only export path; `ermine_htmlwriter_conf` IS set at module top level, which is a red herring for a readiness probe | **READ** (both strings also present in the built bundle, MEASURED) |
| **D4** | **One webpack entry and a nonce-less CSP are inconsistent** with putting the host reducer in `client/src/host/`: under `script-src ${cspSource}` the host page may contain no inline `<script>` at all, not even `const vscode = acquireVsCodeApi()`. Wants **two entries** (`ermine-client`, `ermine-host`) **and a nonce** (VS Code's own documented pattern) | READ + external docs |
| **D5** | **`ts-loader` is optional**: `npm run build` already emits CommonJS, so webpack can take `dist/src/index.js` and need no loader -- one fewer package to vendor forever, at the cost of `.js` rather than `.ts` source-map frames. **OPEN: this contradicts a stated ticket decision and is the user's** | READ |
| **D9** | **WP-9's tier gates nothing**: its done-when is "`npm test` unchanged", and `gate_client` **does not exist** (MEASURED: zero hits in `scripts/`, `docs/`). **Two of §5's three checklist rows can be node tests** -- (i) the built bundle contains no `eval(` and no `new Function` (exactly the check that would have caught D1), (ii) `window.ErmineClient`'s surface in a JSDOM matches `client/src/index.ts`'s exports. Only "`table` renders through the writers global" stays human | MEASURED + READ |
| **D10** | **Two reducers, one specification.** WP-7 already shipped a pure reducer on the extension side (`preview-core.js`, 651 lines, `node --test`); WP-10's `applyMessage` would be a second one in another language over overlapping state. Design rule the review recommends: **`applyMessage` is a PRESENTATION reducer only** -- every decision (is this answer current, should we re-render, did the wedge clear) stays in `preview-core.js`, and the message protocol is the boundary | READ |
| **D11** | **§5's eight-message list is stale in both directions**: rule (5) of §4 is **WITHDRAWN** (WP-24), so the reducer must expect one rising edge per watchdog incident again; and **WP-22 adds a ninth message, `held`**, which a reducer written from an older copy of this document would not carry. Retrofitting a state into a reducer whose property is "every message sequence leaves a consistent state" means re-deriving the property | READ |
| Smaller | **D3**: §5's Bundle row cites `.gitignore:11` for `client/dist/`; it is `:10` (MEASURED). **D6**: the writers' CSS (`common.css`, `htmlwriter.css`, the two themes) is nowhere in §5, so `table`/charts would render unstyled even when they render. **D7**: a `mode: development`, unminified client bundle should land in the low hundreds of KB, two orders below the 5.0 MiB writers bundle, so size is not a design constraint (INFERRED). **D8**: `client/dist/browser/` is built, not committed, and a packaged `.vsix` cannot carry it (`.vscodeignore` ships `src/`, `syntaxes/` and a subset of `node_modules`; the client lives outside `editor/vscode/`), so on a `.vsix` install without the repo the panel has no script -- consistent with the extension already declaring itself not self-contained, but **nowhere written down** | MEASURED / READ / INFERRED as marked |
| The plan | Stage 0 decide Q19 and D5 · 1 add `webpack`/`webpack-cli` (+`ts-loader` only if D5 goes that way), exact-pinned, refresh the lockfile · 2 the config (two entries, `library: {name:'ErmineClient', type:'window'}`, `devtool: 'source-map'`) · 3 `client/test/bundle.test.ts` carrying D9's two properties · 4 the host reducer skeleton · 5 amend §5. **Only stage 1 needs the network, and THE REGISTRY IS REACHABLE FROM THIS MACHINE (MEASURED)**, so the advice is to do stage 1 here and commit the lockfile, leaving the closed-network question as "how do we move `node_modules` from this lockfile" rather than "can we resolve webpack at all" (WP-17's, §10) | MEASURED + design |


**WP-10 STAGE 1 (THE PURE HALF), AS BUILT 2026-09-23; REVIEWED 2026-09-23 (DESIGN GREEN / IMPLEMENTATION GREEN, one tracker must-fix) AND COMMITTED `1d83b5a8`. AS OF S1, NOTHING WAS WIRED (S2 wired it):
`src/extension.js` is untouched, no panel exists, nothing is posted, no setting was added.**
Built on the read-only WP-10 design review (`scratch-widget-preview/wp10-design/DESIGN-REVIEW.md`,
F1-F3, (a)-(i), H1-H10, W1-W10); its W1-W10 corrections are folded into the rows above
(Host page CSP, Legacy renderers, Errors, Unsaved, Stale, Stuck, Switching, Lifetime, Bundle
reload, Bundle checklist) and into §14's WP-10 and WP-11 rows. The implementer's report is
`scratch-widget-preview/wp10-s1/IMPL-REPORT.md`.

**U1-U7: TAKEN RECOMMENDATIONS, BY THE ORCHESTRATOR, NOT THE USER. THE USER HAS NOT BEEN ASKED
ANY OF THEM.** Each is the design review's own recommendation (its §6) except U7, which the
review left to the orchestrator. Any of them is the user's to overturn.

| # | Question | Taken as | Where it lands |
|---|---|---|---|
| U1 | keep the JSON tab or replace it? | **(b)** a setting `ermine.preview.target: panel \| json \| both`, default `panel` | S1 declares the contract (`core.panelTarget`, `PANEL_TARGETS`); S2 contributes and reads the setting |
| U2 | `retainContextWhenHidden` vs a resync | **(c)** the resync is MANDATORY; retain is a separate scroll/drilldown optimisation | S1 built the snapshot (`panelMessagesFor`) and its fold (`page.ts`); S2 posts it |
| U3 | where the two resource roots come from | **(c)** the bundle dir from `resolveServer().root`; the writers dir from a NEW setting `ermine.preview.writersPath` (sibling default) | S2 (bundle) / S4 = WP-11 (writers) |
| U4 | action buttons in the panel | **(b)** Restart only -- what the reducer already has; `held` carries no button | S1: `panel (snapshot)` asserts no message carries an action |
| U5 | `blob:` in `img-src` | **no** | S1: the CSP, asserted |
| U6 | the deferred-fetch design | **(a)** `fetchData` is a rejecting stub; no fetch message pair; `connect-src` stays shut | S3 |
| U7 | `gate_extension` tier | **commit**, on the measured cost (~2 s, no `node_modules`) | S1: registered in `scripts/gates.sh` |

**THE USER'S EARLIER DECISIONS, NOT RE-OPENED**: a second render session, the preview thread,
webpack, `'unsafe-eval'` in the preview CSP only (Q19), the prompted DB password for the window,
no in-evaluator cancel. **NOT S1's TO DECIDE, AND NOT DECIDED**: Q21, the
`restartAfterStuckSeconds` default, and the U7 `.gitignore` reading that belongs to WP-8 (a
different U7 from this table's).

**What S1 built** (`editor/vscode/src/preview-core.js:5102-5430`, exports at `:5595`;
`client/src/host/page.ts`; `scripts/gates.sh:123-139`):

| Export | Decision it holds |
|---|---|
| `panelMessagesFor(view)` | THE WHOLE extension -> panel protocol: `render` (last GOOD document) -> `error` (last current answer, if not ok) -> `stale` -> `stuck` -> `held` -> `offline` -> `switching` -> `unsaved` -> `reloadBundle` (only while announced). A SNAPSHOT: the six latch slices are sent on BOTH edges every time, so a panel that missed posts is put right by the next list |
| `panelView(parts)` | THE SHARED BUILDER, per `preview-core.test.js`'s header rule: S2's glue and every test build the view with it, from `answers`, `stuckState` (the ARBITRATED wedge and the offline flag), `mark` + `pick` + `restartedByUs` (through `heldMessage`), `pending`, `unsaved`, `fastMode`, `switching` (no producer: W6), `reloading` |
| `panelAnswerStep` / `initialPanelAnswers` | the displaced (`isDisplaced`) and generation (`isCurrentGeneration`) decisions, by the same functions and in the same order as `renderNow`; returns the answers BY IDENTITY when nothing is to be shown |
| `unsavedNames(documents)` | §5's Unsaved hint, pure; **not wired by S2 -- open (W6)** |
| `buildPreviewHtml(uris, opts)` / `previewCsp` / `PREVIEW_ROOT_ID` | the host page: the CSP line, up to three CSS links, a root element, then classic `<script src>` writers -> client -> host with a `?v=` stamp on the latter two, every URI HTML-escaped, ZERO inline script |
| `panelTarget` / `PANEL_TARGETS` / `FAST_MODE_SUFFIX` / `PANEL_MESSAGE_KINDS` | U1's contract; W5's sentence; the nine kinds (pinned equal to `client/src/host/index.ts`'s `MESSAGE_KINDS` by reading that file) |
| `client/src/host/page.ts` `receive` / `foldSnapshot` | the resync ENVELOPE `{kind: "snapshot", messages}` folded from `initialHostState()`, REPLACING the state; a malformed one returns the state by identity; `MESSAGE_KINDS` stays nine. No DOM yet. Re-exports the reducer's whole surface so S2 can move the `ermine-host` webpack entry to it; **until then it is NOT in the bundle** |
| `gate_extension` (commit) | `node --test test/preview-core.test.js` in `editor/vscode`; UNAVAILABLE (exit 3) with no `node` on PATH; `GATE_NOSCOPE` because `scripts/mutate.py`'s operators are Scala-shaped |

**MEASURED vs INFERRED** (MEASURED = run here and the output read; INFERRED = derived, not observed):

| Claim | Label |
|---|---|
| `node --test test/preview-core.test.js`: **333 tests, 333 pass, 0 fail** (313 before S1; +20) | MEASURED |
| `client` `npm test`: **100 tests, 97 pass, 0 fail, 3 skip** (90 before S1; +10 in `test/page.test.ts`) | MEASURED |
| `gate_extension`'s body, run once directly: `SUMMARY 333 tests, 333 pass, 0 fail`, exit 0; on a copy with one test broken it prints `332 pass, 1 fail` and exits 1 | MEASURED |
| `node test/load-test.js` once: `PASS -- the extension loads, activates and registers correctly` (the server's own `session ready: 129 modules`) | MEASURED |
| 14 real `ermine/render` outcomes captured from ONE `bin/ermine-lsp` boot and checked in as `editor/vscode/test/fixtures/panel-answers.json`: `ok` (WpInt, Sales, burst x2), 400 (`$.params`; `$.params.fromDy`), 404 runner (no `reason`) and placement (`reason: "unreadable"`), 500 (`Sales` 2099 dates: "an empty relation built from no rows carries no columns"; **AMENDED 2026-09-23 by Q21: that entry is REPLACED by `error-500-wpempty`, re-captured from `tracker/playtest/fixtures/WpEmpty.e` (path `$.props`), because the fixed `Sales` now renders an empty range -- `scratch-widget-preview/q21-sales/`**), `stuck: true` 500 (WpSpin, 4 s watchdog, 5.1 s), the SAME refusal for WpInt / WpChain / WpBlow while stuck, and the server's own `-32800 "replaced by a newer render"` for the middle of three back-to-back renders; one `ermine/preview/stuck {stuck: true, seq: 1}` notification | MEASURED |
| WpChain and WpBlow were NOT observed wedging on their own: one boot can wedge once, so both appear only as stuck refusals | MEASURED (the limit of the capture) |
| `(pg-h7-incremental)`: over generated extension histories driven through the REAL `panelAnswerStep` / `stuckReduce` / `guardReduce` / `panelView`, posting each view's list one message at a time leaves the panel in EXACTLY the state the last view's snapshot folds to (1500 runs) | MEASURED |
| **FOUND BY S1**: that equality FAILS for one history -- a reload announced and then ABANDONED before the FIRST answer leaves `reloading` raised on the one-by-one path (only an answer lowers it). The first version of the test assumed the divergence held after an answer too, and FAILED: once an answer exists every list re-sends it, which lowers the latch. Pinned by `(pg-h7-abandoned-reload)`; **so S2 posts snapshot ENVELOPES, never loose messages** | MEASURED |
| the CSP is enforced as intended; the scripts run in that order; `window.ermine_htmlwriter` exists at render time; `acquireVsCodeApi()` exists; `postMessage` drop/ordering; `retainContextWhenHidden` semantics | **UNOBSERVED** -- no browser and no VS Code ran; the playtest (Group E) is the observer |
| a displaced render reaches the glue as a rejection carrying `code` or `data.code` -32800 | the wire shape MEASURED (`code: -32800` in the capture); the `data.code` form READ from `isDisplaced`, not observed |

**The reverse-mutant battery** (on a COPY rebuilt per mutant; `scratch-widget-preview/wp10-s1/mutate.py`,
results `mutants.json`): **24 run, 24 KILLED BY NAME, 0 survivors** (MEASURED; control first: the unmutated copy green on both suites, and the unmutated gate exits 1 on a copy with one test broken). The six the plan required: CSP altered (M01 `'unsafe-eval'` dropped, M02 `blob:` added) -> `panel (csp)`; script order swapped (M03 host before client, M04 writers last) -> `panel (html)`; an inline script added (M05) -> `panel (html)`; one kind dropped (M09 `offline`) -> `panel (table)`, `panel (snapshot)`, `panel (explorer)`; the fold made non-incremental (M22 snapshot folded ONTO the current state) -> `(pg-snapshot-replaces)`, `(pg-h7-drops)`, `(pg-h7-abandoned-reload)`; a displaced render producing a message (M11) -> `panel (displaced)`, `panel (real answers)`, `(pg-h7-real)`. The others: `defer` added, escaping removed, a hostile `cspSource` accepted, the stuck LOWER edge omitted (also `(pg-h7-incremental)`), the generation check removed, `stuck` read off the answer, `reloadBundle` first, `stale` first, the fast suffix dropped, `held` given an action, `held` for another pick's mark, an error forgetting the good document, clean documents reported unsaved, an extra `page.ts` export, a malformed snapshot blanking the panel, and `gate_extension` passing a RED suite (killed by the gate-on-red check). The full table is in the implementer's report.

**OPEN, AND S2's**: the glue itself; the H1/H2/H3/H9 async models; the glue pins (one
`createWebviewPanel`, guarded posts, the latch consumed once); contributing `ermine.preview.target`;
moving the `ermine-host` entry to `page.ts` and re-checking `(b-host-surface)` (no zod, < 64 KiB).

**WP-10 STAGE 2 (THE PANEL GLUE), AS BUILT 2026-09-23; REVIEWED 2026-09-23 (DESIGN GREEN / IMPLEMENTATION RED on two test must-fixes, fixed in round 2) AND COMMITTED `26d22f61`. NOTHING HAS RUN IN VS
CODE OR A BROWSER** -- every claim below is from `node --test`, JSDOM and webpack. Extension
0.1.11 -> 0.1.12. The implementer's report is `scratch-widget-preview/wp10-s2/IMPL-REPORT.md`.
S1's "OPEN, AND S2's" list above is closed by it.

| Built | Where | Decision it holds |
|---|---|---|
| `present(answer, reveal)` | `extension.js`, called where `showAnswer` was (both arms of `renderNow`) | U1 via `core.presentRoute(core.panelTarget(...))`: `json` = `await showAnswer(answer, reveal)` exactly (the function's text is pinned by sha256, unchanged); `panel` = `openPanel()` ONLY when `reveal` + a snapshot; `both` = both, tab first. The latch is still consumed once at the top of `renderNow`; `present` never reads it |
| `openPanel()` | the ONE `createWebviewPanel` (`ViewColumn.Beside`, `preserveFocus`, `retainContextWhenHidden`) | create-or-reveal, one panel per window; reached only from `present` on `reveal` (the two commands, Render anyway, the first-pick carry) -- never an automatic re-render |
| `postSnapshot(why)` | the ONE `postMessage` | `if (!panel \|\| !panelReady) return false`; `core.panelSnapshot(panelViewNow(), ++seq)`; a throw is logged. Called from `setPreviewStatus` (so stale / stuck / offline / held-cleared / answers), `holdRender` (first line), `present`, `ready`, visible |
| `panelViewNow()` | `core.panelView` over the module globals | `answers: panelAnswers` (stepped by `core.panelAnswerStep` beside BOTH `lastAnswer =` sites), `stuckState`, `wedgeMark`, `picked`, `restartedByUs`, `pending`, `fastMode`; `unsaved: []` and `switching: null` (W6, NOT WIRED), `reloading: false` (S3) |
| `onPanelMessage` | `core.panelInbound` | `ready` -> latch up + snapshot; `intent {kind: restartServer}` -> `vscode.commands.executeCommand("ermine.restartServer")` (the palette's door; the wedge guard is untouched); `log` -> `preview panel: ...` in the channel; anything else ignored and named. A message from a panel that is not the current one is dropped |
| bundle check + notice page | `checkPreviewBundle` / `setPanelHtml`; `core.previewBundleDir` / `previewBundleCheck` / `buildPanelNoticeHtml` | see the Bundle checklist row |
| the page | `client/src/host/page.ts` (`pageStep`, `documentKey`, `boot`, `refuseDeferred`), webpack entry moved | see the Host-page logic row; `fetchData` is U6's rejecting stub naming the token (S3 finalises the wording) |
| `ermine.preview.target` | `package.json` (enum `panel/json/both`, default `panel`, window scope) | `test/load-test.js` checks the enum and default equal `core.PANEL_TARGETS` / `PANEL_TARGET_DEFAULT` and that activation creates no panel |

**The S1 review's `target=both` note (the refusal arm has no generation check), CLOSED BY
ARGUMENT AND PINNED, not by a code change**: the refusal arm now steps `panelAnswerStep` too,
whose generation check cannot refuse there -- `mayStillSend` has just compared the render's
generation with the live one and nothing between that verdict and `present(refusal, ...)`
awaits. A glue pin fails if an `await` is ever added in that gap.

**MEASURED vs INFERRED:**

| Claim | Label |
|---|---|
| `npm run test:preview`: **365 tests, 365 pass, 0 fail** after the review's round 2 (333 before S2; 363 in round 1) | MEASURED |
| `client` `npm test` with the bundle rebuilt: **112 tests, 109 pass, 0 fail, 3 skip** (100 before; +12; the 3 skips need sbt-built fixtures) | MEASURED |
| `(b-host-boot)`: the BUILT `ermine-host.js` + `ermine-client.js` in a JSDOM with a stub `acquireVsCodeApi`: called once, nothing posted before DOMContentLoaded, `ready` once, a snapshot draws the `(w-scorecard)` fixture through `window.ErmineClient`, a stale toggle keeps the same DOM node | MEASURED (JSDOM, not a webview) |
| the design's H1 / H2 / H3 / H7 / H9 and a 250-run interleaving explorer over `panelGlueModel` (the glue statement for statement over a fake panel that drops hidden posts and throws after dispose): no post before `ready`, none after dispose, at most one live panel, a visible ready panel ends on `panelMessagesFor(view)` | MEASURED (model) |
| the fake panel's contract -- a hidden webview drops posts, a disposed one throws, `webview.html` reloads the page and the new page says `ready` | INFERRED from `@types/vscode` (READ; F1: the typings contradict each other on hidden + retain) |
| the page's `ready` reaches the extension; `onDidChangeViewState` fires on becoming visible; the panel opens beside without focus; the notice page renders | UNOBSERVED (no VS Code) |

**Reverse mutants** (on a COPY rebuilt per mutant; `scratch-widget-preview/wp10-s2/mutate.py`,
results `mutants.json`): **26 run, 26 KILLED BY NAME, 0 survivors** (MEASURED; control green first). **The glue (`extension.js`) mutants die ONLY by the source pins** -- the model is a copy of the glue, so it cannot see a glue edit; the models kill the pure-builder and page mutants and show each hazard with a model mutant beside it. The table is in the implementer's report (every
mutant the orchestrator named is in it: post before ready, no resync on visible, a second
panel, the latch consumed twice, the tab path changed under json, loose messages, render on
every snapshot, the Restart intent bypassing the command, the bundle check fail-open).

**A QUESTION FOR THE USER, NOT DECIDED (the S2 review's N4)**: the command **Ermine: Render Report to JSON** keeps its title, but under the default `ermine.preview.target: panel` it renders into the panel, not JSON. Rename it (e.g. "Ermine: Render Report")? Renaming changes the palette entry the playtest checklist names, so it was NOT done.

**H-NUMBERS**: the `panel S2 H<n>` tests use the design review's §3 numbering (H1 disposed/replaced panel, H2 an answer overtaken by a newer render, H3 `ready` before/after the first render, H7 a hidden panel drops posts, H9 the reveal latch / one panel). Round 1 had used its own numbers; renamed in the review's round 2.

**OPEN, AND S3-S5's**: the bundle watcher + `reloadBundle` (H4), the final `fetchData`
wording, `gate_client` at nightly (the client tests above still gate nothing), the `unsaved`
producer (W6), WP-11's writers (S4), the playtest's Group E (S5).

**WP-10 STAGE 3 (FETCH STUB, WATCHER, BANNERS), AS BUILT 2026-09-23. REVIEWED 2026-09-23 DESIGN GREEN / IMPLEMENTATION RED ON A DOCS MUST-FIX (M1, the folder delete), CORRECTED, COMMITTED `3b162527`. NOTHING
HAS RUN IN VS CODE OR A BROWSER** -- every claim below is from `node --test`, JSDOM and webpack.
Extension 0.1.12 -> 0.1.13. The implementer's report is `scratch-widget-preview/wp10-s3/IMPL-REPORT.md`.
S2's "OPEN, AND S3-S5's" list above is closed by it except the `unsaved` producer (W6), S4 and S5.

| Built | Where | Decision it holds |
|---|---|---|
| the coalescer | `editor/vscode/src/preview-core.js` `bundleWatchStep(state, input)`, `bundleWatchEvent(kind, fsPath)` (THE shared builder the glue's arms and the model both call), `initialBundleWatch`, `bundleReloading`, `bundleReloadLine`, `BUNDLE_WATCH_GLOB = "*.js"`, `BUNDLE_QUIET_MS = 250` | W4: ONE deadline for the whole folder, pushed by every create / change / delete of a `.js`; the first event of a burst is announced; only a quiet period reloads, once; a timer that fires early re-arms for the rest; dispose disarms. The clock is an argument |
| the watcher | `extension.js` `watchBundle(dir)` (the ONE `createFileSystemWatcher` for it: `RelativePattern(Uri.file(<root>/client/dist/browser), "*.js")`), `unwatchBundle()`, `bundleStep(input)` (the one timer), `reloadBundle(events)` | created by `openPanel` (both branches), disposed from the panel's `onDidDispose` and from `disposePreview`: never without a panel. The announcement is a snapshot whose view has `reloading` true (the reducer's own `reloadBundle` banner); the reload re-checks the folder with S2's `previewBundleCheck` and calls `setPanelHtml` (page with a fresh stamp / notice page), which drops the ready latch; the new page's `ready` resyncs |
| the fetch stub | `client/src/host/page.ts` `refuseDeferred` | **REWORDED BY WP-10 S5 ROUND 2** to *this preview does not fetch deferred relations, and the report asked for deferred delivery of "<token>" (the panel has no network access: its CSP has no connect-src)* -- the S3 wording below was false for `Sales.e` (Q24). U6, S3's wording: *the preview delivers every relation inline -- inline is the only delivery its render request asks for -- so it cannot fetch the deferred relation "<token>" (the panel has no network access: its CSP has no connect-src)*. It touches nothing; the dispatcher's per-widget box shows it |
| `gate_client` | `scripts/gates.sh`, **nightly**, 1200 s | see §11's row |
| R23 | `(pg-boot-listener-first)` | the page's `message` listener is registered before `ready` (it already was; now a test says so) |

**What the user sees during `npm run bundle:watch` (playtest E7, INFERRED -- nothing here has run
in VS Code):** (1) starting it runs one full `tsc` (writes `dist/src`, not watched) and then
`webpack --watch`'s first build, which writes the bundle folder: with a panel open that is ONE
*"the client bundle changed; reloading"* banner and ONE reload about 250 ms after the last write
-- the same document redrawn by the new page from its `ready` snapshot. (2) Saving
`client/src/widgets/scorecard.ts`: `tsc --watch` rewrites `dist/src/...` (outside the watched
folder), `webpack --watch` rebuilds, and webpack 5 skips writing an output whose bytes did not
change (MEASURED once here: `npm run bundle` printed `ermine-client.js ... [compared for emit]`
and left its mtime alone while `ermine-host.js` was `[emitted]`), so a scorecard edit rewrites
`ermine-client.js` (+ its map) only: one `.js` event burst, one banner, one reload, scroll and
drilldown lost. (3) If `tsc --watch` writes its outputs more than webpack's aggregate window apart,
webpack may build TWICE for one save; two builds more than 250 ms apart are two reloads (never a
broken page: a half-written folder is the HALF-BUILT notice for that moment). (4) A type error:
`tsc` still emits (no `noEmitOnError` in `client/tsconfig.json`, READ), so the panel reloads with
whatever was emitted. (5) Ctrl-C on `bundle:watch` leaves the files, so the panel does nothing.
(6) Deleting the bundle FILES turns the panel into the *not built* page and the next build turns
it back. **Deleting the FOLDER (`rm -rf client/dist/browser`) most likely does NOT flip it** (READ,
the S3 review's M1) (`editor/vscode/node_modules/@types/vscode/index.d.ts:13977-13979` and `:13996-14001`): "paths that do not exist in the file system will be monitored with a delay until created and then watched depending on the parameters provided. If a watched path is deleted, the watcher will suspend and not report any events until the path is created again." and "file events from deleting a folder may not include events for the contained files. [...] performance optimizations are in place to fold multiple events that all belong to the same parent operation (e.g. delete folder) into one event for that parent." A non-recursive `*.js` pattern does not
match the folder itself, so the page stays up (its scripts are loaded) until the folder is re-created
by a build -- or the next explicit command re-checks (S2). Playtest **E8 must record which happens**
for both deleting the files and deleting the folder.

**MEASURED vs INFERRED:**

| Claim | Label |
|---|---|
| `npm run test:preview`: **382 tests, 382 pass, 0 fail** (365 before S3; +17) | MEASURED |
| `client` `npm test` after `npm run bundle`: **114 tests, 111 pass, 0 fail, 3 skip** (112 before; +2 new, `(pg-fetch-refuses)` reworded) | MEASURED |
| `gate_client`'s body, run once directly in the worktree: `SUMMARY 114 tests, 111 pass, 0 fail, 3 skipped`, exit 0; `gate.sh`'s registry lists `client nightly 1200` | MEASURED |
| `node test/load-test.js` once: `PASS -- the extension loads, activates and registers correctly` (tooltip `Ermine session ready: 129 modules in 13.0s`) | MEASURED |
| `ermine-host.js` 25,390 B after `npm run bundle` (24,885 before; the new wording), still under 64 KiB | MEASURED (`ls -l`) |
| one reload per four-file build, two for two builds apart, one for two inside the window; the notice page on a vanished / half-built bundle and the page again on its return; an answer in flight across a reload arriving with the new `ready`; no watcher without a panel; the watcher, its listeners and its timer disposed with the panel and at teardown | MEASURED on the MODEL (`panelGlueModel`, the glue statement for statement over a virtual clock and a fake file system); the glue is held to the model by the S3 source pins |
| a webpack write is several watcher events (the model uses two per `.js` write) | INFERRED; the count is UNVERIFIED |
| VS Code fires the watcher for `<root>/client/dist/browser` (outside the workspace, possibly absent at the start, possibly deleted and re-created) | **UNVERIFIED**; the fallback is S2's re-check on the next explicit command |
| a widget asking for a deferred relation shows its own error box, the page logs it once, and nothing reaches `fetch` / `XMLHttpRequest` | MEASURED in JSDOM with the REAL client (`(pg-fetch-deferred-box)`); the CSP blocking a fetch is UNOBSERVED (jsdom enforces no CSP) |

**Reverse mutants** (on a COPY rebuilt per mutant; `scratch-widget-preview/wp10-s3/mutate.py`,
results `mutants.json`): **26 run, 26 KILLED BY NAME, 0 survivors** (MEASURED; control green first).
Every one the orchestrator named is in it: debounce removed (T01 glue, T01b core -- four reloads),
coalescer keyed per file (T02), delete arm dropped (T03 glue, T03b core), watcher not disposed
(T04 panel close, T04b teardown), reload posted without an html reset (T05), notice page not
restored (T06), `fetchData` resolving (T07), `connect-src` added (T08 page, T08b notice page),
`gate_client` FAIL instead of UNAVAILABLE without `node_modules` (T09); plus R23 (T11, the S2
review's survivor, now killed by `(pg-boot-listener-first)`). **The glue mutants die only by the
`glue pins (WP-10 S3) ...` tests**, as in S2.

**OPEN NIT (the S3 review's N3, recorded, not fixed)**: if `ermine.serverPath` or the workspace root changes while a WORKING panel is open, the watcher stays on the OLD bundle folder -- `openPanel`'s re-check runs only when the page is not ok, and `reloadBundle` loads from the new folder only when the old one fires. An edge case; a fix is re-watching in `reloadBundle`.

**OPEN, AND S4-S5's (plus W6)**: WP-11's writers (S4), the playtest's Group E (S5, whose E7/E8 are
the first observation of everything above), the `unsaved` producer (W6). The questions for the
user from S2 (the command's title) and before are unchanged.

**WP-11 (= WP-10 STAGE 4): THE LEGACY WRITERS IN THE PANEL, AS BUILT 2026-09-23; REVIEWED 2026-09-23 DESIGN GREEN / IMPLEMENTATION GREEN (five nits N1-N5, all closed by S5) AND COMMITTED `56f608cd`.
NO BROWSER AND NO VS CODE HAS RUN THIS** -- every claim below is from `node --test`, JSDOM and
webpack, and **this stage's done-when is the PLAYTEST (E3, E9, E10, E11), not a node test**:
nothing that matters about the writers (do they load under the CSP, does `table` draw through
`runTabular`, does a `pieChart` draw, what does the console say) is observable in node, and the
tests below do not pretend otherwise. Extension 0.1.13 -> 0.1.14 (S3 is committed, `3b162527`).
The implementer's report is `scratch-widget-preview/wp11/IMPL-REPORT.md`.

| Built | Where | Decision it holds |
|---|---|---|
| the writers check | `editor/vscode/src/preview-core.js`: `previewWritersDir(raw, folder, serverRoot)` (the setting through `absoluteRoots`, which gained an optional setting-name argument so refusals name `ermine.preview.writersPath`; empty = the sibling default), `writersState(listing)`, `previewWritersCheck(where, listing)` (`state`, `script`, `styles`, `root`, `missing`, `message`), `writersLine(check)` | U3; fail-closed on `htmlwriter.js`; the three sheets `PREVIEW_WRITERS_STYLES` |
| the page | `previewPageUris(cspSource, bundle, writers, uriOf)` into S1's `buildPreviewHtml` slots | writers -> client -> host; the sheets in order; only from `writers.root` |
| the banner | `panelView`'s new `writers` slot (`panelWritersNotice`), `panelMessagesFor`'s `error` | see the Bundle checklist row |
| the re-check | `panelRecheck(bundle, writers)`, `panelReload(before..., after...)` | not watched; a command re-checks, reloads only on a change |
| the glue | `extension.js`: `panelWriters`, `checkPreviewWriters()`, `panelOptions(bundle, writers)`, `setPanelHtml(panel, bundle, writers)` (+ the one channel line), `openPanel` (both branches), `reloadBundle`, `panelViewNow` (`writers: panelWriters`), both disposal sites | one `localResourceRoots` list; the setting read once per check |
| the setting | `package.json` `ermine.preview.writersPath` (string, default `""`, window scope); `test/load-test.js` checks it and that its default resolves to the sibling folder | U3 |

**MEASURED vs INFERRED:**

| Claim | Label |
|---|---|
| `npm run test:preview`: **400 tests, 400 pass, 0 fail** (382 before WP-11; +18) | MEASURED |
| `node test/load-test.js` once: `PASS`; it printed `writers default /home/dmitry/research/ermine/ermine-writers/writers/html/src/main/resources/web: present` and the tooltip `Ermine session ready: 129 modules in 12.9s` | MEASURED |
| client `npm test` after `npm run bundle`: **115 tests, 112 pass, 0 fail, 3 skip** (114 before; +`(pg-writers-global)`) | MEASURED |
| the writers folder on this machine lists `common.css`, `htmlwriter.css`, `htmlwriter.js`, `htmlwriter_classic.css`, `htmlwriter_dark.css`, `iejson.js`, `javafxwriter.css`; `htmlwriter.js` is 5,157,473 B; no CSS file has an `@import`; `url(` appears once in `common.css` (`:125`) and three times in `htmlwriter_dark.css` (`:10`, `:173`, `:188`), zero times in `htmlwriter.css` and `htmlwriter_classic.css` | MEASURED (`ls -la`, `grep -n`) |
| the default `<root>/../ermine-writers/...` resolves to that folder from this worktree | MEASURED (`node test/load-test.js` prints the state) |
| the page with the writers is built in the order and with the CSP pinned; the banner, the re-check and the roots behave as the model says | MEASURED on the pure core and the MODEL (`panelGlueModel` extended statement for statement) |
| the writers' `DOMContentLoaded` listener runs before the host's, so `ready` is posted with the global present | READ (`writers/js/htmlwriter.js:10-13`, the design review) + MEASURED with a STUB listener in JSDOM; UNOBSERVED with the real bundle |
| the writers bundle loads under the CSP; `table` draws through `runTabular`; a `pieChart` draws; only `tmbllsprite.png` is blocked; a style-box click is inert and logged | **UNVERIFIED -- the playtest's (E3, E9, E10, E11)** |
| jQuery and Highcharts are bundled inside `htmlwriter.js` (no extra script) | MEASURED by the design review (14 and 11 webpack modules), not re-measured |

**Reverse mutants** (on a COPY rebuilt per mutant; `scratch-widget-preview/wp11/mutate.py`,
results `mutants.json`): **30 run, 30 KILLED BY NAME, 0 survivors** (MEASURED; control green first); every one the orchestrator
named is in it (script order swapped, a CSS link dropped, an unescaped URI, the CSP changed, the
writers root missing from `localResourceRoots`, `writersState` fail-open on a folder without
`htmlwriter.js`, the banner omitted, the model given a field the glue does not pass, the
`DOMContentLoaded` order inverted in `page.ts`).

**OPEN (plus W6)**: the playtest's Group E -- WRITTEN by S5 (below), NEVER RUN -- whose E3/E9/E10/E11
are the first observation of everything in this block; the `unsaved` producer (W6). Not WP-11's and
not decided: Q21, the `restartAfterStuckSeconds` default, U7's `.gitignore` reading, the command's
title (Q22), the panel's U1-U7 (Q23).

**WP-10 STAGE 5 (THE PLAYTEST GUIDE'S GROUP E), AS BUILT 2026-09-23 on HEAD `56f608cd`, UNCOMMITTED
AT THE TIME OF WRITING. NOTHING IN IT HAS BEEN RUN IN VS CODE.** Documentation, one test and one
wording fix; extension still 0.1.14. The implementer's report is
`scratch-widget-preview/wp10-s5/IMPL-REPORT.md`.

| Built | Where |
|---|---|
| Group E, E1-E14, in the A-D shape (setup, do, EXPECTED quoted from the code with `file:line`, failure line naming what to paste), every step NEVER RUN; E5 is F1's experiment with an optional console listener that tells the two `@types/vscode` sentences apart; E8 records which of files / folder flips the notice page, with the typings quoted; E11 has NO fixture (no report-typed binding in the repository draws a `styleBox`, MEASURED by grep) and is OPTIONAL; E13 `target` json/both; E14 the writers-missing banner | `tracker/WP-7-MANUAL-CHECKLIST.md` |
| A8 scoped to `target: json`; `tracker/playtest/settings.example.json` sets `"ermine.preview.target": "json"` for Groups A-C (the panel is the default since 0.1.12, and they are written against the tab); the 30-minute path gains E2, E5, E8, E9; the open decisions are five (Q21, the restart default, U7's `.gitignore`, Q22, Q23) and the stale C-step numbers in them are corrected (C21, C22-C28) | the checklist, the settings example |
| a Group E table and Q22/Q23 answer rows | `tracker/PLAYTEST-RESULTS.md` |
| 0.1.14 packaged (`ermine-lang-0.1.14.vsix`, 852,896 B after round 2, 334 files, MEASURED); the client bundle and the writers checkout as prerequisites; `target` and `writersPath` in the settings table; `check-server.py` re-run (exit 0, `129 modules in 13.5s`); §13 rewritten for the panel | `tracker/PLAYTEST-SETUP.md` |
| WP-11 nits: N1 one test pins all six `ermine.preview.roots` refusal texts exactly (the review's R18b now dies by name); N2 the dimming/`re-rendering` sentence (README 0.1.14, the Bundle checklist row above); N3 `not a array` -> `not an array` in `previewWritersDir` (its one pin updated); N4 `<checkout>` is the checkout that holds `bin/ermine-lsp` (README 0.1.12-0.1.14); N5 the install line names 0.1.14 | `editor/vscode/src/preview-core.js`, `test/preview-core.test.js`, `README.md`, `tracker/PLAYTEST-SETUP.md` |

**A FINDING, NOW THE USER'S QUESTION Q24 (§13):** the design review's F2 / U6 premise that "the preview
never mints a deferred token" is FALSE for a report that asks for `Deferred` itself.
`core/src/test/resources/doc/Sales.e:129 (was :116 before the Q21 fix moved it)` does ("always deferred, whatever the request asks for"),
and S1's MEASURED capture of `Sales.report` (`scratch-widget-preview/wp10-s1/captures.json`,
`ok-sales`) carries a `kind: "deferred"` table with a token. The panel refuses it by name, which is
the designed behaviour, but the refusal's own TEXT ("the preview delivers every relation inline --
inline is the only delivery its render request asks for") and `page.ts`'s comment ("A document that
reaches this was not made by the preview's render request") were both false for such a report.
**Round 2 of S5 reworded both** (`client/src/host/page.ts` `DEFERRED_REFUSAL`, now *"this preview does
not fetch deferred relations, and the report asked for deferred delivery of "<token>" (the panel has no
network access: its CSP has no connect-src)"*; `client/test/page.test.ts` `(pg-fetch-refuses)` pins it
whole). **Consequence for §14: WP-10's done-when "`Sales` renders inline" is NOT met by `Sales` as
written** (one refused table, two unregistered widgets); which fixture the done-when should name, and
whether U6 stands, is Q24. E2 says what the playtester will see.

**Q24 DECIDED 2026-09-23 (the user: *"Do (a) and (d) now, file (c)."*):** U6 stands; WP-10's done-when names
`Doc/SalesReport.e`; `heading` and `text` renderers are built (client only); the fetch message pair is
WP-30 (§14), not built. MEASURED while building (d): all three of `Sales`'s tables are refused by the
`TableProps` schema (a bare relation), so the deferred one's box says `its props are invalid --
columns.0.column: Required`, not the refusal; the refusal text above is reached only by a widget whose
props VALIDATE and hold a deferred arm.

**Q25 DECIDED 2026-09-23 (the user: *"I'm pretty sure I want typed widget schemas in the typescript rather than matching runtime ermine values fallibly"*; then *"Rewrite it."*), option (A) plus the principle
that the client's widget vocabulary is the TYPED one, its zod GENERATED from `Layout.Widgets.*`:** the
`Widget.schema` override Q24 (d) added for `heading`/`text` is DELETED (`client/src/dispatcher.ts`
looks up `WIDGET_PROP_SCHEMAS` only), `heading` and `text` are `Layout/Widgets/Heading.e` and
`Layout/Widgets/Text.e` with generated zod, and `Sales.e`'s body is typed. MEASURED: the typed `Sales`
draws in the panel with no error box, and its items table is INLINE -- a typed table cannot force
deferral -- so the refusal text above is reached by no fixture today (WP-30, §14). The runner's untyped
fixture is `core/src/test/resources/doc/SalesRaw.e`. As-built: `scratch-widget-preview/q25/IMPL-REPORT.md`.
How a typed deferred table should exist is **Q26** (§13, NOT ASKED YET). **Independent of Q25:** the same
change fixes two pins in `client/test/corpus.test.ts` `(b)` that were ALREADY STALE at b7faef3a (the
widget-name list lacked `crosstab`/`headline`, and the `cells > 1000` floor sat above the measured 929); both
fail at HEAD whenever `target/widget-corpus` exists. The name list is now derived from the registry.

## 6. Parameters as files, with a schema, under the report's module

| Item | Decision | Evidence |
|---|---|---|
| Layout | `<workspace folder of the picked report>/.ermine/preview/<Module>/<binding>.params.json`, with `<binding>.schema.json` beside it: **a directory per module, a file per binding**. `<Module>` is the dotted module name from the file's header (`module Sales where`, `Sales.e:1`; the index's `moduleName`, `Definitions.scala:98`, which `ermine/preview/reports` also answers), used as one directory name, not split into a path, so `ls .ermine/preview` lists modules and `Layout.Widgets.Foo` is one entry | |
| Rejected layouts | a flat `<Module>.<binding>.params.json` is unreadable because module names contain dots (`Layout.Widgets.Foo.report.params.json` does not say where the module ends); one file per module keyed by binding is a merge-conflict surface, every report's params in one JSON object | |
| The committed file is the default | the params file is ordinary committed source: whoever clones renders the same first document. There is **no** defaults binding in the module (a `<binding>Args` convention would be another privileged name, rejected for the reason §3.2 gives) and no computed defaults: a rolling date range has to be literal JSON, and the honest place for that logic is the report itself -- for example a `Maybe Date` the report interprets as "today" when absent | `Sales.e:58-63` has four required fields |
| First pick | when no params file exists the extension writes a **skeleton from the schema**, ~40 lines, no dependency: walk the exported schema; required properties get `""` / `0` / `false` / the first `enum` value / today for `format: date` / `{}` recursively; optional (`Maybe`) keys are omitted. Wrong-but-typed values are a 400 with a path (`Runner.scala:473`, `:488`), which the file's squiggles already explain. The skeleton is written to disk for the developer to edit and commit | |
| Rename | renaming the binding orphans its file: the panel says "no params for `<binding>`" and offers the skeleton; the orphan is visible in `git status` and is the developer's to move or delete. Nothing fails silently | |
| Git | one `.gitignore` line, `**/.ermine/preview/**/*.schema.json`: only the generated schema is ignored; the params file is not | today's `.gitignore` has no `.ermine` entry |
| Saving re-renders | a watcher on the params file (`createFileSystemWatcher`, *external*) re-sends the last render with the new params | |
| Schema source | `ermine/schema {uri, binding, roots}` is a **preview-queue job** answered from the render session: `Runner.paramSchema(module, binding)` = `report(module, binding)` (`Runner.scala:411-420`, cached, under `evalLock`) then `Schema.exportType(rep.paramTy, module)` (`Schema.scala:184`; `Report.paramTy`, `Runner.scala:598`) under the render env. The schema is therefore exported from the **same** `paramTy` the decoder was compiled from (`:472-476`), so the params schema and the 400s can never disagree, and it queues behind renders like every preview job. **Q7 (decided 2026-09-20): SCHEMA-BEFORE-RENDER IS SUPPORTED AND SHARES THE SESSION** -- the request carries `uri` and `roots` and computes its module and root set with exactly the functions a render uses, so the first pick above (no params file, write the skeleton from the schema, then render) costs ONE boot across both and can no longer describe a same-named module from another root by mistake. **WP-7/WP-8 MUST SEND THE SAME `roots` ON BOTH**: the root set is still §2.4's discard key, so a schema with different roots throws the render session away and the next render pays a boot -- the cost Q7 removed, put back by a client that disagrees with itself | the resident cannot answer it: `LspSchema.answer` runs on a resident copy whose loader chain is `moduleRoots` + classpath (`Schema.scala:807-810`; `Resident.scala:126-127`), preview roots exist only in the render session, so `Sales` would be module-not-found; and the binding mode *evaluates* a workspace module's top level, which §2.3 keeps off the dispatch thread. The existing `name` mode looks a **type** name up in `s.cons` (`Schema.scala:206-210`); a report's params type may be an alias from another module or an anonymous record, so a binding mode is needed. `Sales.e:107` happens to name it (`Query`) |
| Why it fits | params are required monomorphic and closed-row (`JSON-GUIDE.md:1218-1221`; `Decode.scala:99`, `:128`) | the describable fragment |
| Registration | the extension writes `<binding>.schema.json` beside the params file and puts `"$schema": "./<binding>.schema.json"` in the params file (*external*: VS Code's JSON language service honours a relative `$schema`). No write into the user's `json.schemas` setting | the extension strips `$schema` before sending, since every request key is closed (`Runner.scala:101-103`) |
| Refresh | the schema is regenerated on every `invalidated` that names the report's module | |

**AMENDED 2026-09-20 -- THE WP-8 DESIGN REVIEW, AND THE USER'S "go for it" TO ALL EIGHT OF ITS
RECOMMENDATIONS.** The rows above are kept as written; what follows amends them. Every claim about
VS Code's own behaviour below is **UNOBSERVED BY ANYONE** -- nobody on this branch has run the
editor -- and is marked so in the review itself.

**U1-U8, DECIDED BY THE USER (2026-09-20), each the review's recommendation:**

| # | Question | DECIDED |
|---|---|---|
| U1 | the generated `<binding>.schema.json`: verbatim, or rewritten for the editor? | **drop `$id`, keep `$defs`/`$ref`** -- the file's own path is its identity, and a custom-scheme base (`ermine:Sales/Query`, `Schema.scala:191`) may defeat `$ref` resolution (unverified) |
| U2 | dates in the skeleton | **today**, the only rule that always decodes -- **with the done-when reworded**: `Sales`'s rows span 2026-01-05..2026-03-17 (`Sales.e:84-93`), so a skeleton written today selects NO rows. **THE CONSEQUENCE RECORDED HERE WAS WRONG AND IS WITHDRAWN (S1 review, 2026-09-21, MEASURED): the first render is NOT an empty document, it is a 500** -- see the S1 block below, and **Q21, which is the user's.** The params file is opened for editing right after it is written |
| U3 | regenerating a skeleton after the params type changes | **an explicit `Ermine: Write Params Skeleton` command that overwrites after confirmation**; never a silent merge into committed source |
| U4 | two files declaring one module share one params file | **accept and document**; a path hash makes the file unreadable and it is meant to be committed |
| U5 | a key that looks like a credential in a committed params file | **warn once per file** (`/pass\|pwd\|secret\|token\|api[-_]?key/i`), never block: a report may legitimately take a `token` parameter. §8's A1/A5/A6/A9 are unaffected |
| U6 | client-side params size cap | **1 MiB with a named refusal**; the only bound today is the server's `Wire.MaxFrame` 64 MiB, over which the reader CLOSES THE CONNECTION (`Rpc.scala:238`, `:331-337`) |
| U7 | `.gitignore` shape | **a generated `.ermine/preview/.gitignore` carrying `*.schema.json` and `*.db`, beside the files, PLUS the repo line** -- the single repo line is inert in any other workspace folder and leaves WP-14's `local.db` tracked |
| U8 | should `bin/ermine-serve` ever read these files? | **no: preview-only.** No new file IO on the deploy path, and a committed preview default must not silently become a production one |

**D1-D8, the defects the review found in the ticket as written (READ/INFERRED as marked there):**

| # | Defect | Fix now decided |
|---|---|---|
| D1 | `"$schema"` in the params file is itself an invalid property: `Sales.Query` is record-style, so its schema carries `additionalProperties: false` (`Schema.scala:606`) -- the line that makes validation work would be the first squiggle (INFERRED + external reports; exact VS Code behaviour unverified) | inject `"$schema": {"type":"string"}` into the object the root `$ref` NAMES, not the root |
| D2 | "walk the exported schema" cannot start: the exported root is `{$ref: "#/$defs/<Module>.<Type>"}` with NO `properties` (gate-asserted, `tracker/tools/lsp-client.py:3398-3407`) | the walker's first step is a `$ref` hop; `$defs` lookups and a visited-set are mandatory, and the vocabulary includes `oneOf`, `anyOf`, `enum`, `items`, `prefixItems`, `format` |
| D3 | a custom-scheme `$id` may break `$ref` resolution in the editor (unverified) | U1's strip; the manual checklist's `orderBy` completion is the go/no-go |
| D4 | the skeleton's "today" dates make the committed default non-deterministic AND, for `Sales`, empty | U2's reworded done-when |
| D5 | the one `.gitignore` line is in the wrong scope and contradicts `RESOLUTIONS.md:236`'s `local.db` claim | U7 |
| D6 | "the panel says 'no params for `<binding>`'" -- **WP-8 predates the panel** (WP-9/WP-10) | status-bar message + output-channel line + a one-shot notification offering "Write params skeleton" |
| D7 | a schema answer carries no `generation` and no pick identity (`SchemaRequest(uri, binding, roots)`), so a late answer can write a `.schema.json` for a pick the user has changed | capture the pick at send; pure `isCurrentSchemaAnswer(pickAtSend, pickNow)` |
| D8 | regenerating the schema on every `invalidated` is a disk write plus a queued preview job on every save of the report module OR any module it imports | write-if-different, and ask only when the render answered `ok` or a 400 at `$.params*` |

**WP-8 NEEDS NO SERVER CHANGE.** Everything it uses is already on the wire (`RenderRequest.params`
spliced verbatim, `ermine/schema {uri, binding, roots}` on the preview queue, the `fx.schema` seam
at `extension.js:466-470`, the stuck/recovery texts). **No Scala compiles and no JVM gate moves**;
the client's `npm test` is not a registered gate today (WP-10 registers `gate_client` at nightly),
so each stage runs it by hand.

**THE FOUR-STAGE PLAN (one implementer + one reviewer per stage; none starts a JVM):**

| Stage | Content | Done when |
|---|---|---|
| **S1 pure core** | `paramsPaths`, `skeletonFrom`, `schemaFileFor`, `paramsToSend`, `paramsFingerprint`, `shouldRerenderOnParamsSave`, `isCurrentSchemaAnswer`, plus a committed `sales-query.schema.json` fixture | `npm test` green; the Sales fixture yields `{"$schema":"./report.schema.json","fromDay":<today>,"toDay":<today>,"orderBy":"ByDay"}` with `onlyRegion` ABSENT (a `Maybe` field is omitted, not null); `oneOf`, `prefixItems`, the recursion cap and a non-object root each have a test; `schemaFileFor` drops `$id` and injects `$schema` into `$defs["Sales.Query"].properties` |
| **S2 send it** -- **BUILT AND INDEPENDENTLY REVIEWED 2026-09-21 (RED on both axes, on reproduced defects; all nine must-fixes applied); see the S2 block below** | read the params at send time, strip the top-level `$schema`, cap, send; watcher + `onDidSaveTextDocument` through the existing `scheduleRender` coalescer; invalid JSON = a refusal in the tab, NOT a render | a hand-written params file renders (**MEASURED against a real server without an editor: `ok=true`, a 1220-byte document**); editing and saving re-renders in place (**UNOBSERVED -- editor glue**); a corrupted file shows the parse error and does not render (**unit-tested; the tab itself is UNOBSERVED**) |
| **S3 first pick writes** -- **BUILT 2026-09-21, NOT YET REVIEWED; see the S3 block below** | the first `ermine/schema` client: the ordering rule (no file -> schema first; file present -> render first), the pick-staleness guard, skeleton write (NEVER overwrite), `.schema.json` write-if-different, the two `.gitignore` files (the generated one AND the repo line) | on a clean checkout, picking `Sales.report` writes both files and renders; a second pick does not rewrite the params file; `git status` shows the params file only; **AND: `schemaFileFor` is ALWAYS called on the server's FRESH `ermine/schema` answer and NEVER on the `.schema.json` S3 itself wrote** -- it is a pure function of what it is handed, so a root-level copy tracks the entry it was cloned from only within one call, and feeding the written file back leaves the copy silently stale while the shared entry beside it moves on (MEASURED by the S1 review; a test records the hazard). **AS BUILT (2026-09-21): the first two clauses are MEASURED on the shipped code against a real server** -- picking `Sales.report` writes all three files, a second pass rewrites neither the params file nor the schema file, and the edited params file survives; `git status` shows the params file and the generated `.gitignore` and NOT the schema. **The third clause holds by construction and by source pin**: `core.paramsWritePlan` has exactly one caller and the refresh path cannot name the params path. **The first clause -- "and renders" -- is Q21's**: with today's dates it is the 500 |
| **S4 edges** -- **BUILT 2026-09-23; REVIEWED RED/RED 2026-09-23 BY AN INDEPENDENT REVIEWER; FIX ROUND APPLIED THE SAME DAY, RE-REVIEW PENDING; see the S4 block below** | orphan message **and U3's `Ermine: Write Params Skeleton` command, which D6 offers and which the plan assigns to neither S3 nor S4 in so many words -- it goes here, with D6**, non-object params roots (`Int`, an all-nullary enum, `Maybe`) beyond the write S3 already does, a pick with no module, a non-identifier binding, the credential warning (**done by S2**), ~~`fx.schema` wiring on recovery/restart~~ (**TAKEN BY S3, 2026-09-21, because S3 is what builds the schema client; recorded rather than silently moved**), the preview-only note for the docs | each edge has a unit test or a named log line; the WP-7 checklist gains §A. **AS BUILT (2026-09-23): MET.** Every edge has a table test AND a named line; the command, the orphan notice and the five non-object roots each have their own tests; the five roots are MEASURED end to end against a real server and all five render `ok=true`; the checklist gains B22-B27 (its §A is now Group B, which the 2026-09-22 rewrite made of it). **THE ONE ITEM NOT COVERED IS NAMED RATHER THAN QUIETLY DROPPED**: a renamed MODULE leaves a whole stale directory that nothing looks inside, because detecting it costs one `ermine/preview/reports` -- a job that COMPILES a module -- per `.e` file in the workspace |

**§A -- WHAT STAYS FOR THE MANUAL CHECKLIST (all of it unobserved). SINCE S2 (2026-09-21) IT ALSO
CARRIES**: that a hand-written params file renders a document; that saving it re-renders in place
and that ONE save costs ONE render; that an edit from outside the editor re-renders; that invalid
JSON shows the refusal and does not render; that deleting the file renders with `{}`; that a report
outside every workspace folder says so once and writes nothing; that a re-format while `held` ASKS
rather than re-rendering (the review's M6, the user's own sentence); and that the params watcher is
installed at all -- the ONE source mutant of twenty-seven that survives the unit suite. They are
`tracker/WP-7-MANUAL-CHECKLIST.md` §2.33-2.42. **AND SINCE S3 (2026-09-21) TEN
MORE, §2.43-2.52**: that the first pick writes the three files and opens the
params document without stealing focus; that it costs ONE render and not two;
that `git status` shows the params file and the generated `.gitignore` and not
the schema; that the `$schema` line is not squiggled (D1) and a wrong key IS;
that completion offers the four keys and the three enum values (D3's go/no-go,
the `$ref` -> `$defs` hop); that a second pick and a window reload leave an
edited params file alone; that editing the params TYPE rewrites the schema
file and the editor follows it without a reload (G17) while an unrelated save
does not touch it (D8); that a read-only workspace says so once, renders with
`{}` and does not retry per render; and that a report which wedged is never
handed a schema request. **AND SINCE S4 (2026-09-23) SIX MORE, B22-B27** (the
checklist was rewritten into lettered groups on 2026-09-22, so §A is now its
Group B): that `Ermine: Write Params Skeleton` asks in a MODAL that names the
file and that Escape, Cancel and every near miss leave it untouched and ask the
server nothing; that **Replace** rewrites it, refreshes the schema file, opens
the document and costs ONE render carrying `explicit`; that the command with no
params file shows no dialog and CREATES; that renaming a binding in `Sales.e`
earns the orphan notice once per session and leaves the old file on disk; that
the notice's button writes for the report picked NOW; and that each of the five
non-object params roots writes its own file and prints its own sentence.
**THE ORIGINAL LIST:** a wrong key squiggles; key
completion offers `fromDay`/`toDay`/`onlyRegion`/`orderBy`; `orderBy` completes to
`ByDay`/`ByAmount`/`ByUnits` (the `$ref`->`$defs` hop, D3's go/no-go); **the `$schema` line itself
is not squiggled** (D1); saving re-renders in place; an external edit (`git checkout`) re-renders;
editing the params type updates `report.schema.json` and the editor picks it up without a window
reload; a renamed binding shows "no params for"; `git status` shows the params file and not the
schema; a report outside every workspace folder writes no file and says so once; a skeleton whose
dates match no row gives an empty document or a 500 -- **MEASURED 2026-09-21: it is the 500; see Q21**. **AMENDED 2026-09-23 (Q21 decided): with `Sales.e` fixed it is an empty document -- `ok=true`, the `byDay` table with four columns and zero rows (MEASURED, `scratch-widget-preview/q21-sales/` (one `bin/ermine-lsp` boot, `captures.json`; `IMPL-REPORT.md` has the exact lines)).**

**WP-22 HAS NOW DEFINED `paramsFingerprint` (2026-09-20), SO WP-8 REUSES IT AND MINTS NO SECOND ONE** -- `editor/vscode/src/preview-core.js`, exported and tested; WP-8's job is only to CALL it with the params it actually sends (after the `$schema` strip) at the two places the mark is minted. **AND ONLY A DIGEST MAY EVER BE STORED** (the WP-22 review's M3): the mark is written into `workspaceState`, a params value can carry a database password, so the function answers a SHA-256 of the canonical form and a test asserts no part of the input appears in it. The paragraph below is the original requirement and still holds word for word. **WP-8 EXPORTS `paramsFingerprint` FOR WP-22**, over the CANONICAL JSON ACTUALLY SENT (stable key
order, after the `$schema` strip) rather than the file's text, so that re-formatting a params file
does not clear the wedge mark. If WP-22 lands first its fingerprint is a constant (`{}`); WP-8
makes it real.

**S1 (THE PURE CORE) IS BUILT AND INDEPENDENTLY REVIEWED, 2026-09-21 -- PURE ONLY: NOTHING IS WIRED
AND NOTHING IS WRITTEN TO DISK.** The review returned RED on both axes with five must-fixes (D-1,
D-2, D-3, I-1, I-2); all five and every nit are applied, and each is recorded in its own place
below rather than in a separate list. `editor/vscode/src/preview-core.js` gains one section and `editor/vscode/test/preview-core.test.js`
gains 70 tests (96 -> 166, all green under `npm run test:preview`; `node test/load-test.js` also
green, because `src/extension.js` requires the file). **`src/extension.js` IS UNTOUCHED**: no
watcher is registered, no command is contributed, no `workspace.fs` call exists, nothing new goes
on the wire, and `package.json` still says 0.1.7. Nobody has observed any of this in VS Code, and
S1 adds nothing that could be observed there. `tracker/WP-7-MANUAL-CHECKLIST.md` is untouched for
the same reason. The gate tier is unchanged: **no Scala compiles and no JVM gate moves**.

| Function (all pure, all exported) | What it DECIDES |
|---|---|
| `paramsPaths(pick, folderPath, flavour)` | `.ermine/preview/<Module>/<binding>.params.json`, `<binding>.schema.json` beside it, `previewDir` and `gitignorePath` for U7's file, and `schemaRef = ./<binding>.schema.json`. Refuses, each with a NAMED reason and a sentence: `no-pick`, `no-workspace-folder`, `outside-workspace` (G1 -- a prefix compare on normalised absolute paths, never `path.relative`, whose `resolve` would fall back to `process.cwd()`), `no-module` (G6), `unsafe-module` / `unsafe-binding` (G3 -- a WHITELIST: an Ermine identifier, dotted for a module, at most 120 characters), `reserved-name` (G4 -- CON/PRN/AUX/NUL/COM1-9/LPT1-9 as ANY minted segment, case-insensitively, read off the part before the first dot so `NUL.params.json` is caught). The path FLAVOUR is an argument (`posix` / `win32`, default the host's) so every Windows rule is table-tested on Linux |
| `skeletonFrom(schema, today, schemaRef)` | `{value, embeddable}` or `{problem}`. First step is the `$ref` hop into `$defs` (D2); a `$defs` table and a visited set; required properties get a value in DECLARATION order, `Maybe` keys are OMITTED; `enum` -> first member, `const` -> it, `oneOf`/`anyOf` -> the first alternative that YIELDS a value, `items` -> `[]`, `prefixItems` -> one per position, `maxItems: 0` -> `[]`; `format: date` -> `today` (U2, injected, no clock here), `date-time` -> `today + T00:00:00.000Z` (the exporter's own `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`, `json/Encode.scala:203`, which is what the decoder's mandatory-offset `ISO_OFFSET_DATE_TIME` takes, `json/Decode.scala:461`), `uuid` -> the nil UUID. Recursion in a REQUIRED position fails that BRANCH naming the `$defs` entry, so a `Tree` whose first constructor is the nullary `Leaf` still gets `{"tag":"Leaf","args":[]}` and only an all-recursive type answers `{problem}`. A non-object root (G5) gets its value and `embeddable: false` |
| `schemaFileFor(schema)` / `schemaFileText(obj)` | U1's `$id` drop, `$schema`/`$ref`/`$defs` kept, D1's `"$schema": {"type":"string"}` injection, then a stable 2-space pretty-print with a trailing newline so D8's write-if-different compares meaningful bytes. Never mutates, idempotent |
| `paramsToSend(text, maxBytes)` | Cap (U6, 1 MiB, UTF-8 bytes of the TEXT) -> empty-file check -> parse -> strip the top-level `$schema` and only when the root is an object (G20) -> credential warning (U5, never a refusal). Invalid JSON and an over-cap file are REFUSALS: the render does not happen (G7) |
| `shouldRerenderOnParamsSave` / `isCurrentSchemaAnswer` | G9's client-side trigger (path equality, case-INSENSITIVE on win32) and D7's staleness guard |
| `credentialKeyWarning(keys)`, `paramsGitignoreText` | The sentence U5 shows and the file U7 asks for (`*.schema.json`, `*.db`, a comment saying it is generated and that the `*.params.json` beside it are NOT ignored) |

**D1 IS WIDER THAN THE REVIEW FOUND IT, AND S1 CLOSES THE WIDER HOLE.** D1 says to inject the
`$schema` property into "the object the root `$ref` names". That is only one of three root shapes
the exporter can produce, because `exportType` splices the root schema's own fields next to
`$schema`/`$id` (`json/Schema.scala:195`): a `data` params type gives `{"$ref": ...}` (D1's case),
a RECORD params type (`report : {..(|a,b|)} -> Node`, `json/Schema.scala:412-419`) gives an INLINE
`{"type":"object", ..., "additionalProperties": false}` AT THE DOCUMENT ROOT, and a
multi-constructor `data` gives a `oneOf` of arms each of which is a closed object. Injecting only
into the `$defs` entry would leave the second squiggling its own `$schema` line and the third
squiggling it in every arm. `schemaFileFor` therefore walks root -> `$ref` -> `oneOf`/`anyOf`
alternatives and injects into every closed object it reaches; the root document's own `properties`
IS the sibling of the root document's own `additionalProperties`, so injecting there is correct,
and D1's "not the root" holds precisely for the `$ref` case it was written about. An open (`Spread`)
object is left alone, and an optional key added to every `oneOf` arm cannot make two arms match one
value because the `tag` consts still discriminate. **This is pinned as a property**, not a claim:
for 4000 generated schemas in the exporter's vocabulary the skeleton must validate against the
schema FILE under a small validator written in the test file.

**AND D1 HAS A SECOND HALF, FOUND AND MEASURED BY THE S1 REVIEW (2026-09-21) -- THE DESIGN'S OWN
FAILURE WITH THE SIGN REVERSED.** Injecting into the object a root `$ref` NAMES is wrong whenever
that `$defs` entry ALSO describes a nested position, because then the editor accepts a NESTED
`$schema` key -- which `paramsToSend` does not strip (G20 is top-level-only, deliberately) and
which the server refuses. The committed golden
`core/src/test/resources/schema/UserTree.schema.json` is the case: `Test.Tree` is the root `$ref`'s
target AND what the `Node` arm's `args.prefixItems` refer to. The refusal is MEASURED, not read:
control E of the render table above answered `400 "the key \"$schema\" is not allowed here"`
(`json/Decode.scala:755-756` via `:848-849`). **THE FIX IS A ROOT-LEVEL COPY**: when the entry is
reachable from anywhere but the root, a copy of it is minted under a fresh `$defs` name, the
injection goes into the COPY, and the ROOT `$ref` is pointed at it; the shared entry is left
untouched so every nested occurrence still forbids `$schema`, and the copy's own inner `$ref`s
still name the ORIGINAL, which is what makes it one level and no more. The copy's name cannot
collide with an exported one: `Schema.defName` runs every name through `sanitise`
(`json/Schema.scala:721-722`), which turns anything that is not a letter, a digit, `_` or `.` into
`_`, so `-params-root` is unreachable for the exporter -- and `-` is unreserved in a URI and needs
no JSON Pointer escaping. **Nothing is copied speculatively**: the copy is made, the injection is
tried on it, and a copy that changed nothing (an enum, an open object, a tuple) is thrown away --
which is also why `Sales` is byte-for-byte what it was before the fix, and why `schemaFileFor`
stays idempotent. **Pinned two ways**: a table test over the `UserTree` fixture (a nested `$schema`
must be REFUSED by the written file and a top-level one ACCEPTED), and a property over 12000
generated schemas asserting both that a `$schema`-declaring `$defs` entry is named only from
root-level positions and that, at every object position of a real value, THE FILE IS NEVER MORE
PERMISSIVE THAN THE SCHEMA THE SERVER EXPORTED (MEASURED: 2398 copies minted, 6679 root positions,
482 closed nested positions, 37 open ones).

**THE COPY PUTS ONE OBLIGATION ON S3, AND IT IS THE ONLY ONE THIS SECTION CREATES. S3 MUST ALWAYS
CALL `schemaFileFor` ON THE SERVER'S FRESH `ermine/schema` ANSWER AND MUST NEVER READ ITS OWN
WRITTEN `.schema.json` BACK INTO IT.** `schemaFileFor` is a pure function of what it is handed: it
cannot diff a copy against a LATER version of the entry it was cloned from, so a copy tracks its
original only within the call that made it. Feed the written file back after the params type has
changed and the copy silently keeps the OLD shape while the shared entry beside it carries the new
one -- MEASURED by the S1 re-review (a field added upstream never reaches the copy), and pinned by
a test that performs the forbidden round-trip so the behaviour is recorded rather than discovered.
The fresh answer costs one request, and it is what D8's write-if-different compares against anyway.
The S3 row of the four-stage plan carries this as an explicit done-when.

**THE FIXTURE IS READ-DERIVED, NOT CAPTURED, AND S2 MUST REPLACE IT.**
`editor/vscode/test/fixtures/sales-query.schema.json` is what the exporter WOULD answer for
`Sales.report`'s parameter type. No JVM ran: it was built by reading
`core/src/main/scala/com/clarifi/reporting/ermine/json/Schema.scala` (`exportType` :184-196 with the root splice at :195,
`dataType` :512-536, `constructor` :571-616, the builtins :327-339, `dialect` :126),
`core/src/test/resources/doc/Sales.e:53-63`, and the commit-tier `lsp` gate's own assertions
(`tracker/tools/lsp-client.py:3398-3407`), which pin `$id`, `$ref` and Query's four properties and
three required keys. **S2'S OBLIGATION TO CAPTURE AND DIFF IS DISCHARGED (S1 REVIEW, 2026-09-21,
MEASURED): the review started a real `bin/ermine-lsp` (no sbt: `target/ermine-classpath` was
present and not stale), sent one `ermine/schema {uri, binding, roots}`, and the answer is
BYTE-IDENTICAL to this file** -- same bytes, same key order, so `schemaFileText` exposes no
ordering difference either. The driver is `scratchpad/wp8-review/capture.py` (about 40 s) and the
captured answer is `scratchpad/wp8-review/real-schema.json`; S2 may re-run it rather than cite it.
The skeleton it yields is
`{"$schema":"./report.schema.json","fromDay":<today>,"toDay":<today>,"orderBy":"ByDay"}` with
`onlyRegion` ABSENT, over the REAL capture as well as over the fixture.

**WHAT THAT SKELETON THEN RENDERS WAS ALSO MEASURED, AND THE CONSEQUENCE THIS BLOCK USED TO RECORD
WAS FALSE.** It said the first document would be EMPTY until the dates are edited. It is not
empty; it is a 500. The review sent the skeleton's params back on a real `ermine/render`, with four
controls in one boot:

| # | params | answer |
|---|---|---|
| A | the skeleton (today's dates) | **`ok=false, status=500`** -- "Sales.report produced a document that cannot be encoded: an empty relation built from no rows carries no columns; give it a header (mkRelationWithHeader#) or a static hint", `path: $.children[1].cells[0][0].props` |
| B | the gate's in-range params | `ok=true` |
| C | `{"fromDay": 5, ...}` | `400` -- "expected a date string yyyy-MM-dd, found the number 5" |
| D | `fromDay` only | `400` -- "the required key \"toDay\" is missing" |
| E | the skeleton **plus** a top-level `$schema` | `400` -- **"the key \"$schema\" is not allowed here"** |

C and D show a bad skeleton WOULD have earned a 400 pointing at a key -- D's MESSAGE names the
missing key, and C's message names the defect (the review did NOT capture C's `path`; WP-7's own
earlier measurement recorded it as `$.params.fromDay`, in `tracker/WP-7-MANUAL-CHECKLIST.md`'s
findings list). A earned no 400 at all, so **the skeleton decodes correctly and the 500 is not a
skeleton defect**. B shows the report itself is fine. E
shows the `$schema` strip (G20) is mandatory rather than theoretical -- and is the measurement D-1
below turns on. **WHAT TO DO ABOUT A IS THE USER'S CALL: section 13, Q21. WP-8'S FIRST DONE-WHEN
CLAUSE ("`Sales` renders a document on first pick") IS BLOCKED ON IT.** **AMENDED 2026-09-23: Q21 IS
DECIDED (fix the example, ticket the engine as WP-29) and the clause is MET as written -- A now answers
`ok=true` with an empty four-column `byDay` table (MEASURED, `scratch-widget-preview/q21-sales/` (one `bin/ermine-lsp` boot, `captures.json`; `IMPL-REPORT.md` has the exact lines)).** A test still asserts the
part that is true -- that today's date lies outside every `Sales` row -- and its comment now
records the 500 instead of the empty document.

| G-item | S1 |
|---|---|
| G1 report outside every workspace folder | **CLOSED (pure half)**: `outside-workspace` / `no-workspace-folder`, and a property over 6000 hostile module/binding draws that no answered path escapes the folder. **CLOSED OUTRIGHT BY S2 (2026-09-21)**: `paramsFolderFor` picks the INNERMOST containing folder and never `folders[0]`, the fallback sends `{}` and says so once per pick, and three source pins hold each site to it |
| G2 / U4 two files, one module, one params file | **ACCEPTED AND DOCUMENTED** in the function's own comment; keyed by module, never hashed |
| G3 binding that is not a filename | **CLOSED**: a whitelist, plus a table row for each of fourteen named hazards -- the design review's G3 row names two of them (`<+>` and `/`), the other twelve are S1's |
| G4 Windows reserved device names | **CLOSED in the pure core**, refused on every platform; case-insensitivity of the Windows FS (`Sales` vs `sales` colliding as two modules) is NOT addressed and is not S1's |
| G5 non-object params roots | **CLOSED (pure half)**: value plus `embeddable: false`. The message that says the editor cannot validate such a file is glue: S4, **which built it and then MEASURED all five shapes end to end (2026-09-23)** |
| G6 a pick with no module | **CLOSED (pure half)**: `no-module` |
| G7 the file does not parse | **CLOSED (pure half)**: `invalid-json` carrying the parser's message, render refused. **CLOSED OUTRIGHT BY S2**: `paramsRefusalAnswer` -> the existing `tabContent` path, `status: null`, the reason under `paramsProblem`; MEASURED that nothing reaches the server (control F). The TAB ITSELF is unobserved |
| G12 / U6 size cap | **CLOSED (pure half)**: 1 MiB of UTF-8 text, `too-large`. **S2 makes it a refusal in the tab** like every other `paramsToSend` problem |
| G13 / U5 credentials | **CLOSED (pure half)**: top-level keys, one warning per file, never a refusal. **S2 shows it**: one `showWarningMessage` per params file per session, keyed by path so a pick change does not re-warn; the notification's arrival is UNOBSERVED |
| G19 `paramsFingerprint` | **CLOSED**: REUSED, not re-minted; tests pin that a re-format, a key reorder and a changed `$schema` line all keep the fingerprint while any value change moves it, and that the digest holds no part of the input. **S2 CALLS IT WITH THE PARAMS ACTUALLY SENT**, at the `params` event and on every SET event, which is what makes changing the parameters clear the wedge mark -- **and the S2 review's M3 found the one class where it did not**: `null`, `{}` and "no file" were ONE digest, so a report that wedged with no file could not be un-held by writing a file holding `null`. Fixed: `undefined` alone means "nothing was sent", which is also what keeps a mark persisted by 0.1.7 meaning what it meant |
| G20 `$schema` stripping | **CLOSED**: top level only, object root only |
| D1 / D2 / D7 / D8 | **CLOSED in the pure core** (injection incl. the wider hole above; the `$ref` hop; `isCurrentSchemaAnswer`; stable bytes for write-if-different) |
| G8 never overwrite, write failures | **NOT S1** -- glue (S3) |
| G9 what re-renders on a save | **CLOSED BY S2**: `onDidSaveTextDocument` and a `createFileSystemWatcher` on the params path, both through the existing 150 ms coalescer, the watcher re-created on a pick change and when the module is learned and disposed with the Q11 one. That one save costs ONE render is modelled against the real `COALESCE_MS`; that the two editor events arrive at all is UNOBSERVED |
| G10 does the server need to know | settled already: no |
| G11 where errors are shown | **S2 for the params half**: the untitled tab, through `tabContent`, plus one channel line per distinct problem per pick and one notification for a credential-looking key |
| G14 `ermine/schema` on the preview queue, G15 the first-pick ordering | **NOT S1** -- S3 |
| G16 / U3 the "Write Params Skeleton" command | **NOT S1**; S1 supplies the function it will call. **BUILT BY S4, 2026-09-23** |
| G17 the editor's schema cache | **NOT S1** -- manual checklist |
| G18 / U8 preview-only | **NOT S1** -- a docs note, S4 |
| U7 the generated `.gitignore` | **HALF**: the TEXT and the PATH of the generated `.ermine/preview/.gitignore` are here; WRITING it is S3, and so is **the repo line, which U7 also asks for and which is not dropped** -- the S1 review caught a code comment arguing against it, and that comment is corrected |
| D3 / D4 / D5 / D6 | **NOT S1**: D3 is a manual checklist go/no-go, D4 is the reworded done-when (asserted in a test, nothing to build), D5 is U7's write (S3), D6 is the orphan message (S4) |

**WHAT THE S1 REVIEW MEASURED BEYOND THE TWO CORRECTIONS ABOVE, recorded so nobody re-does it.**
(i) Every one of the **twelve committed exporter goldens** in `core/src/test/resources/schema/`
produces a sensible skeleton, has its `$id` dropped, and is idempotent under `schemaFileFor`; the
injection sites are exactly right -- the **document root** for `UserRecord` (a RECORD params type,
an inline closed object at the root, with no `$ref` at all: the case D1 as written would have left
squiggling its own line), `UserInline` and `UserDeferred`; **both `oneOf` arms** for `UserRelation`
and `Either`; the **`$defs` entry** for `BorderOptions` and `UserTableProps`; **nothing at all**
for `UserSpread` (open, a `Spread` field) and the three bare enums (`Direction`, `Ordering`,
`SortOrder`). `UserTree` is the twelfth and is now the **root-level COPY** the D-1 fix mints.
(ii) The test generator's distribution is healthy (nothing below ~900 draws over 4000 schemas), and
it draws every builtin of `json/Schema.scala:327-339`. (iii) **TEN MUTANTS, ALL KILLED.** The first
review's six -- a `Maybe` field written as `null` instead of omitted; `Long` written as the number
`0`; `date-time` without its offset; `schemaFileFor` forgetting the `oneOf` arms; `paramsToSend`
stripping a NESTED `$schema`; `paramsPaths` allowing `.`/`..` in a name -- were each killed by BOTH
a table row AND a property, so the properties have independent teeth. The narrow re-review added
four against the new code: M1 injecting into a shared `$defs` entry in place (the D-1 hole itself),
M2 pointing the root `$ref` at the original rather than the copy, M3 injecting into the copy AND
the original, M4 never discarding a copy that changed nothing, and M8 taking the payload again for
a required `Nullable`. **TWO OF THOSE ARE CAUGHT BY ONE TEST EACH AND ARE THEREFORE LOAD-BEARING
ROWS: M4 dies only to the table test "nothing is copied when the injection would change nothing",
and M8 only to the `anyOf` table test.** Anyone deleting or loosening either is removing the only
thing that notices. (iv) **THE STRUCTURAL ORACLE HAS A KNOWN BLIND SPOT**, recorded rather than
fixed: `assertSchemaKeyIsRootOnly` treats a `$ref` reached through `oneOf`/`anyOf` as a root
position but does NOT follow a CHAINED `$ref` (root -> `A`, where `A` is itself `{"$ref": "#/$defs/B"}`),
so it would misclassify `B`'s position. The exporter never chains a `$ref` -- a `$defs` body is an
arm object, a `oneOf` of arms, or an `enum` (`json/Schema.scala:526-532`) -- and the generator never
draws one, so the blind spot is unreachable from any schema this code can be handed; the
implementation itself follows chains correctly. (iv) The 96
pre-existing tests are byte-identical -- the test diff is one appended hunk with zero deleted lines.
(v) Three constructs the exporter emits that the generator did not draw were named: an
`additionalProperties: true` object (count 0 -- and it is precisely the branch the injector
short-circuits on), an inline record at a nested VALUE position, and relation positions. **The
first is now drawn** (MEASURED: 577 open against 6873 closed over 2000 schemas); the other two stay
covered by table tests, which is recorded as a distribution gap rather than a hole.

**THREE SMALL THINGS THE S1 REVIEW SETTLED OR CORRECTED, each one line here so the code and this
document agree.**
1. **THE NAME WHITELIST IS NOT "AN ERMINE IDENTIFIER", and the code comment that said so was
   wrong.** Against `parsers/src/main/scala/scalaparsers/ParsingUtil.scala` it is NARROWER in two
   ways that cost something and WIDER in two that cost nothing. **A binding or module name
   containing `#` (a legal tail character, `:351`, by convention marking a native) or any
   NON-ASCII letter (`letter = satisfy(_.isLetter)`, `:121`, so `Métier` is legal Ermine) GETS NO
   PARAMS FILE and renders with the inline `{}`, with a named message.** `#` is kept out because
   the path becomes part of a `file:` URI in the editor, where `#` opens a fragment; non-ASCII
   because a Windows code page, a case-folding rule and `git`'s `core.precomposeunicode` disagree
   there and none of it has been observed. Widening either is available and cheap; it is recorded
   as a limitation, not as a decision nobody can revisit. (The whitelist also ACCEPTS a leading `_`
   and a lowercase module start, which Ermine does not -- harmless over-acceptance.)
2. **A REQUIRED `Nullable`/`Maybe#` KEY GETS `null`, NOT THE PAYLOAD'S SKELETON.** The review
   found the code and its own stated rule pointing opposite ways. Rule 2 is "the smallest value
   that decodes", and `null` is both smaller and the SAME "absent" answer an optional `Maybe` key
   gets by being left out. The payload was not merely longer, it was wrong as a default: `""` for a
   `Nullable String` filter means "match the empty string", not "no filter", and a date means a
   real range nobody asked for. `oneOf` keeps the first-arm rule -- the exporter never puts a null
   arm in one, and a recursive union needs its base case. A `Maybe X` params ROOT is therefore
   `null`, which is exactly what `docs/JSON-GUIDE.md:1329-1331` says such a report wants.
3. **U5'S CREDENTIAL PATTERN IS NOT WIDENED HERE, AND THE WARNING NOW SAYS WHAT IT LOOKS FOR.**
   `/pass|pwd|secret|token|api[-_]?key/i` over-warns (`passenger`, `bypass`, `tokenize`) and is
   SILENT on `connectionString`, `dsn`, `jwt`, `auth`, `bearer`, `privateKey` and `credential` --
   while the warning text used to claim it covered "a connection string". The pattern is the
   user's, written down, so S1 corrects the TEXT rather than quietly extending the rule: the
   warning now names what it checks and what it misses, so nobody reads its silence as a
   clearance. **Widening the pattern is available to the user** and needs nothing but a new regex.

**TWO IMPLEMENTATION DEFECTS THE S1 REVIEW FOUND, both fixed, both now pinned.** (I-1) `JSON.parse`
makes `__proto__` an ORDINARY OWN property, so `params[key] = value` reached `Object.prototype`'s
setter: the key was SILENTLY DROPPED and the answered object was re-prototyped (MEASURED:
`"polluted" in params` true). The wire payload and the fingerprint were unaffected -- but the S2/S3
glue reads that object with `in`, `for...in` and spread. The same pattern in the skeleton walker
mis-diagnosed a required `__proto__` key as "unsatisfiable", which it is not. Both sites now use
`Object.defineProperty`. (I-2) A leading **UTF-8 BOM** made a perfect file "not valid JSON" -- and
VS Code writes one whenever `files.encoding` is `utf8bom`, which section 10's Windows machines make
likely. One leading BOM is now dropped before parsing; anything else still reports itself. **The
byte cap counts the BOM**, because the cap bounds the file as read off the disk and "the file is N
bytes" should match what the developer's own tools say.

**THE ONE DECISION S1 HAD TO MAKE THAT NOTHING ABOVE SETTLED: AN EMPTY PARAMS FILE IS A NAMED
REFUSAL, NOT `{}`.** `docs/JSON-GUIDE.md:1329-1331` says a MISSING `params` key decodes as `null`,
but a missing key is a file that does not EXIST -- S3's case, which sends WP-7's measured `{}`. A
file that exists and holds only whitespace is a different event (a truncated write, an editor
crash, a `git checkout` caught mid-flight), and rendering it as `{}` would silently discard
parameters the developer believes are there and show a document that looks fine. So an empty file
is `{"reason": "empty"}` with its own sentence -- not `JSON.parse`'s "Unexpected end of JSON
input", which tells a developer looking at an empty file nothing -- and it does not render, the
same answer invalid JSON gets and for the same reason.

**S2 (SENDING IT) IS BUILT, 2026-09-21 -- `editor/vscode` ONLY, JavaScript and
documentation, extension 0.1.7 -> 0.1.8. NOTHING IS WRITTEN TO DISK, NO SCHEMA IS ASKED FOR, NO
SCALA COMPILES AND NO JVM GATE MOVES.** S1's pure core is now wired: with a params file ALREADY
PRESENT (hand-written or committed) the extension reads it from DISK at SEND time, sends its
content as `params`, and re-renders when it changes. The skeleton, the `<binding>.schema.json`, the
two `.gitignore` files and the `ermine/schema` client remain S3's, untouched. **IT HAS NOT BEEN
REVIEWED, AND NOBODY HAS RUN IT IN VS CODE** -- every editor behaviour below is UNOBSERVED and is
on `tracker/WP-7-MANUAL-CHECKLIST.md` §2.33-2.42, ten new steps.

| What was added | Where | What it decides |
|---|---|---|
| `paramsFolderFor(fsPath, folderPaths, flavour)` | `preview-core.js` | **G1's glue half, closed.** WHICH workspace folder owns the report: the INNERMOST one that contains it, never `folders[0]`. `rootsFor`'s first-folder fallback is defensible for a SETTING and would, for a FILE, read -- and in S3 write -- `.ermine/preview/` inside an unrelated repository |
| `meansFileMissing(err)` | `preview-core.js` | ENOENT / `FileNotFound` / ENOTDIR / `EntryNotFound` -> the ordinary "there is no params file" case, which renders with `{}`. **EVERYTHING ELSE REFUSES**, and that is S2's own decision: rendering `{}` over a params file that exists but could not be read is exactly the silent-wrong-document failure S1 refused an EMPTY file for |
| `mayStillSend(atSend, now)` | `preview-core.js` | **THE FUNCTION THIS STAGE EXISTS FOR.** Reading the file puts an `await` between deciding to render and sending. Six named refusals -- `pick-cleared`, `pick-changed`, `roots-changed`, `superseded`, `server-restarted`, `no-client` -- in a MOST-SPECIFIC-FIRST order that is itself tested, because picking renders and so a pick change also bumps the generation: testing the generation first would report every pick change as "superseded" |
| `paramsRefusalAnswer(problem, path, generation)` | `preview-core.js` | A refusal dressed as an ANSWER so the tab shows it through the existing `tabContent` path. `status` is **null** (no server was asked) and the named reason travels under **`paramsProblem`**, never under `reason`, which is the server's closed Q15 vocabulary and what `isPlacement404` switches on |
| `markParamsFor`, `paramsNoticeKey`, `paramsMissingNotice`, `paramsPaths(...).relativeGlob` | `preview-core.js` | the mark's params (the in-flight render's, else the last sent); one notice per distinct problem per pick; the missing-file sentence; and the params path spelled as a folder-relative GLOB, which is what lets a watcher report a file whose DIRECTORY does not exist yet |
| `prepareParams`, `readParamsFile`, `paramsPathsFor`, `workspaceFolderPaths`, `paramsNoticeOnce`, `installParamsWatcher` | `extension.js` | the disk, the watcher and the notifications, and nothing else |

**THE SEND PATH, IN ORDER, AND THE ORDER IS PINNED** (`renderNow`, `extension.js`): take the
generation and capture `{pick, clientEpoch}` -> spinner on, **latch NOT taken** -> `await
prepareParams` -> `core.mayStillSend` and ABANDON if it refuses -> emit the notices and the
credential warning (only now, so nothing describes a report the user has left) -> a REFUSAL shows
in the tab and returns -> the guard's `params` event with the params actually sent -> take the
latch -> `sendRequest`. **AND, SINCE THE REVIEW'S M6, ONE MORE STEP BETWEEN THE GUARD AND THE
LATCH: the consultation** -- if the mark still stands for this pick and the trigger brings no
evidence of change, nothing is sent and the held question is asked instead. Source pins hold every
step of that order, and each one was written after MEASURING which mutant the obvious pin missed: a
pin that only checks `mayStillSend` is CALLED survives deleting the `if (!verdict.send)` block
entirely, and a pin that only checks `shouldAutoRender` is called survives `if (false && ...)`.

**WHY THE LATCH MOVED, AND WHAT ELSE DID NOT.** `inFlightRender` -- WP-22's M1 latch, which decides
`died-mid-render` -- is now taken immediately before the request instead of before the read: a
render that is never sent must not be able to mark a report as having died mid-render. The SPINNER
(`renderInFlight`) still starts before the read, because reading is this render working. Every exit
releases what it took: an abandon and a refusal both clear the spinner under the existing `mine ===
generation` guard and take no latch at all.

**THE GENERATION IS TAKEN BEFORE THE READ, DELIBERATELY.** This render supersedes whatever was in
flight the moment it is decided on, so an older answer that lands during the read is discarded by
the existing generation check rather than overwriting what this one is about to show -- including a
refusal.

**WHAT CLEARS THE WEDGE MARK NOW.** WP-22 put `paramsFingerprint` in the mark's VALUE and said WP-8
would hand it the params actually sent; it does. Every SET event (`answer`, the `Stopped` edge,
`notification`, `killedByUs`) now carries the params of the render in flight, else the last sent,
and the `params` event is fired at send with `paramsToSend(...).params`. So a value change CLEARS
the mark and a re-format, a key reorder or a moved `$schema` line does not -- the comparison is of
what the server sees. **THE FIRST CUT DID NOT SUPPRESS A PARAMS SAVE WHILE `held`, AND THAT WAS
WRONG -- IT IS THE S2 REVIEW'S M6, AND IT IS NOW FIXED.** The argument made for it (WP-22 has
exactly ONE consultation site, and `invalidated`, the Q11 watcher and a roots change are not
suppressed either) does not hold: those three fire BECAUSE something changed and nothing can tell
otherwise, while for params the extension COMPUTES the evidence, before the send, in the same
function. A re-format while held now ASKS, through the same question and the same `held` status,
and the consultation is still ONE function -- `shouldAutoRender`, whose trigger vocabulary grew --
reached from a second place. The sentence that stood here, recording the silent re-render as
honest, is WITHDRAWN: it contradicted the user's own words.

**ONE PRE-EXISTING PROPERTY OF THE COALESCER, RECORDED AND NOT CHANGED** (review nit 8):
`scheduleRender` is a TRAILING-EDGE debounce, so a writer that touches the params file more often
than every 150 ms starves the render entirely. It is not new -- the Q11 watcher and `invalidated`
have always gone through it -- but the params watcher is a new source of bursts (a formatter, a
`git checkout`), so the property is written down rather than discovered.

**RE-RENDERING ON CHANGE: TWO TRIGGERS, ONE RENDER.** `onDidSaveTextDocument` (through
`shouldRerenderOnParamsSave`) and a `createFileSystemWatcher` on the params path both go through the
existing 150 ms `scheduleRender` coalescer, so one save in the editor -- which fires both -- costs
one render; a model test pinned to the real `COALESCE_MS`, read out of the glue, says so. The
watcher is created beside the Q11 watcher, disposed with it, and re-created on a pick change **and
when the module name is learned**, because the module IS the directory. A DELETED file is watched
too and the next render sends `{}`.

**MEASURED 2026-09-21 AGAINST A REAL `bin/ermine-lsp`, ONE BOOT, NO EDITOR**
(`scratchpad/wp8-s2/measure.py`, log beside it). Real files are written to disk in a scratch
workspace holding a copy of `core/src/test/resources/doc`, read back through the EXACT shipped
chain (`paramsFolderFor` -> `paramsPaths` -> the bytes -> UTF-8 -> `paramsToSend` ->
`renderParams`) and sent:

| file on disk | answer |
|---|---|
| A in-range params with a top-level `$schema` line | **`ok=true`**, a 1242-byte document (1220 with the deferred fetch's per-render `token` and `expires` masked, which is how B and C are compared) |
| B the same bytes with a UTF-8 BOM | `ok=true`, **the same document** |
| C the same keys REORDERED, with a different `$schema` | `ok=true`, **the same document**, and the same `paramsFingerprint` as A (`78ed8848...`) |
| D a key the params type does not have (`fromDy`) | **`400` "the key \"fromDy\" is not allowed here"** |
| E no params file at all | `400` "the required key \"fromDay\" is missing" -- WP-7's own measured `{}` |
| F a file that is not JSON | **REFUSED BY THE CLIENT** (`invalid-json`): nothing reached the server |
| G a file holding literally `null` | `400` "expected an object (Query), found null" -- the value reached the wire AS `null` |

A == B and A == C are compared as documents with the deferred fetch's per-render `token` and
`expires` masked; the server exited 0. **THE ONE STEP THIS CANNOT COVER is
`vscode.workspace.fs.readFile` itself**, which resolves only inside VS Code; the decode either side
of it is the same `Buffer.from(bytes).toString("utf8")`.

**ONE THING S2 CHANGED THAT WAS NOT ON ITS LIST, WITH ITS REASON.** `renderParams`'s sentinel for
"no parameters" moved from `null` to `undefined` (`preview-core.js`), and it is the only
pre-existing test line S2 moved. WP-7's measured behaviour is unchanged -- no file still sends `{}`
-- but `paramsToSend` can legitimately answer `null` (a file holding `null`, which is what a
`Maybe`-rooted report wants and what S1's own skeleton mints for such a root), and the old coercion
would have sent `{}` for it and turned a correct params file into a 400 nobody could explain.
Control G above is that value reaching the wire.

**S2 DOES NOT DEPEND ON Q21**, and Q21 is untouched. Q21 asks what the FIRST PICK should show when a
SKELETON's defaults select no rows; S2 writes no skeleton and needs a hand-written file, so the
question does not arise until S3. With the file above, `Sales.report` renders a document (control A).

**WHAT IS GLUE AND THEREFORE UNOBSERVED BY ANYONE**: that `vscode.workspace.fs.readFile` answers
`FileNotFound` with that `code`; that a `RelativePattern` rooted at the workspace folder reports a
file appearing inside a directory that did not exist; that the watcher fires at all, and once rather
than twice, for one save; that `onDidSaveTextDocument` and the watcher land inside the same 150 ms
window; that the refusal is legible in the untitled tab; that the credential warning appears; and
that VS Code's JSON language service complains about the `$schema` line pointing at a file S3 has
not written yet. **AND SINCE THE REVIEW'S ROUNDS**: that `workspace.fs.stat` answers a size at all
(the cap is applied before the read when it does), and that a read can HANG, which the new 5 s
bound exists for. **REMOTE AND VIRTUAL WORKSPACES ARE OUT OF SCOPE AND SAID SO**: `Uri.file(fsPath)`
discards the scheme and the authority, so both the read and the watcher are local-only (review M7);
the claim that they were not is withdrawn from the code comment, the source pin and the checklist.
**The MUTATION RUN's own limit is recorded in §11 and in the review blocks below**: 14 + 27 + 18
run across the three build rounds and 15 more by the final re-check, all killed but one, and that
one prose-preserving survivor -- `installParamsWatcher` returning before it registers anything --
can be seen only by §2.35 of the manual checklist.


**S2 WAS INDEPENDENTLY REVIEWED THE SAME DAY -- DESIGN RED, IMPLEMENTATION RED, ON DEFECTS THE
REVIEW REPRODUCED -- AND ALL NINE MUST-FIXES AND ELEVEN NITS ARE APPLIED HERE.** The review also
verified a great deal green and its own words are kept where they are the record: the send-path
ORDER and every interleaving re-derived from `extension.js` rather than from the model; the latch
move ("strictly better than before"); no lost render of the WP-7 class; the refusal's inability to
be mistaken for a server answer; and the real-server controls reproduced exactly, plus two the
review added -- **a NESTED `$schema` earns the server's `400 the key "$schema" is not allowed
here` (MEASURED, which turns the README's claim from hypothetical into measured), and one byte over
the cap is refused client-side while exactly 1 MiB reaches the server (the cap is `>`, as
documented).**

| # | What was wrong | What it is now |
|---|---|---|
| **M1** | **`roots-changed` COULD NOT FIRE IN THE REAL GLUE, and the model hid it.** `const sentPick = picked` captured a REFERENCE while the roots handler MUTATES `picked.roots` in place, so `mayStillSend` compared an array with itself; the model's test REPLACED the pick object, the one shape the glue never produces. MEASURED both ways: the glue's shape answered `{"send":true}` where the model answered `roots-changed`, and the render went out carrying the NEW roots under the OLD generation | **`core.renderAttempt` (`preview-core.js`) takes a frozen SNAPSHOT before the read** -- the pick copied, its roots array copied, the whole thing frozen -- and everything after the await reads that. The model gained the glue's own mutators (`rootsChangeInPlace`, `serverStopped`, `serverRestarted`, `tearDown`) and a test asserts the copy survives BOTH an assignment and a `push` |
| **M2** | **`mayStillSend`'s INPUTS were unpinned: four neutering mutants survived all 196 tests** (`clientEpoch: sentEpoch` -> `clientEpoch`, `pick: sentPick` -> `picked`, `generation: mine` -> `generation`, and the request built from `picked`), each making the function vacuously true for its own arm | **THE FOUR ARE NOW UNEXPRESSIBLE, not merely caught**: there is no object literal after the await to mutate. The snapshot is built BEFORE it (where reading a live global is correct), the live side is read at the comparison through `core.previewNow`, and the request comes from `core.renderRequest(attempt, params)`. Nine further pins hold the remaining glue call sites |
| **M3** | **`paramsFingerprint` still collapsed `null` into `{}`**, contradicting S2's own sentinel change one function away: `fp(null) == fp({}) == fp(undefined)`, so a report that wedged with NO FILE could not be un-held by writing a file holding `null` | `undefined` only. `undefined` still maps to `{}` **deliberately**, because every mark WP-22 and 0.1.7 persisted carries `fingerprint({})` and must keep meaning "no params" when 0.1.8 reads it back: an upgraded window behaves exactly as it did |
| **M4** | **the module was learned and NOTHING re-rendered**, so a params file on disk was ignored for that pick until some other trigger; the code comment said "the next render will find the file" and there was no next render | `refreshModule` schedules one, through the coalescer, with the new `module-learned` trigger -- which brings no evidence of change and is therefore one the consultation below can refuse |
| **M5** | **a restart performed INSIDE `vscode-languageclient` on the SAME client object moves no `clientEpoch`**, so a render whose read spanned it would reach the fresh process without passing WP-22's one consultation site. **UNVERIFIED** (the library's source is unread, per the project rule) | a `stopCount`, bumped in `onClientStopped` and compared in `mayStillSend` beside the epoch, with its own abandon reason `server-stopped`. A DEFENCE against unverified behaviour, said so in the code |
| **M6 (DESIGN)** | **a params save while `held` with an UNCHANGED fingerprint re-rendered the wedge with no question** -- a re-format, a format-on-save, a touched `$schema` line -- and §A of this document RECORDED that as expected. It is the user's own sentence: *"We'd want some sort of confirmation before rendering a report which wedged and was killed the first time around AND IT DIDN'T CHANGE"* | **`renderNow` now consults `shouldAutoRender` itself**, immediately after the guard's `params` event -- the one moment at which the extension KNOWS whether anything changed, because it has just computed the fingerprint -- and shows the SAME held question through the SAME `holdRender`. **It is still ONE decision function, now reached from two places**, and its trigger vocabulary grew rather than a second decision being minted: the refused set is `restart`, `params-file`, `module-learned`, and a test walks `invalidated`, `file-event`, `roots` and `recovered` proving each CLEARS the mark before it schedules anything |
| **M7 (DOCS)** | **the remote/virtual-workspace claim was FALSE in three places**: `vscode.Uri.file(fsPath)` discards the scheme and authority, so the read and the watcher both address a local path on such a workspace | **WITHDRAWN in all three** (the code comment, the source pin's message, the checklist) and recorded as a stated limitation: **LOCAL WORKSPACES ONLY**. Making it true means carrying the folder's own `Uri` through the pick and `Uri.joinPath`, and the whole extension is `fsPath`-based (the pick, `paramsPaths`, `rootsFor`, and the server is a local process), so it is a ticket, not a line |
| **M8/M9 (DOCS)** | the mutation counts disagreed across three places and the WP-8 row hid the survivor; the checklist's §2.40 and §2.41 demanded contradictory setups for one fixture and §2.41 never said where its file went | the counts below are one number, re-run after this round; §2.40 and §2.41 have their own fixtures and the section says where every file goes, with a new §2.41b for M6 |

**THE NITS, ALL APPLIED**: VS Code's `FileNotADirectory` joins `ENOTDIR` and the `err.name` fallback
is a SUBSTRING test (`"EntryNotFound (FileSystemError)"` is a shape VS Code has been seen to
produce); a `stat` applies the 1 MiB cap **before** `readFile` materialises the file in the
extension host (`paramsTooLargeToRead`, and a provider that cannot stat is simply read); the read is
BOUNDED at 5 s with a named refusal, because **a hang is not a throw** and everything that releases
the spinner is after the await (`stopQuietly`'s own lesson, F1 of the WP-22(c) review);
`shouldRerenderOnFileEvent` now reads a separate `lastServerAnswer`, so a params refusal -- which no
server gave -- cannot disarm the Q11 watcher; `disposePreview` clears the pick and sets a disposed
flag, which makes `pick-cleared` REACHABLE (it was dead) and stops a render in its read from sending
into a torn-down window. **TWO NITS ARE RECORDED AND NOT FIXED**: a transient read error (EBUSY, a
flaky mount) refuses with no retry -- the tab shows it, and the next save retries; and
`scheduleRender` is a TRAILING-EDGE debounce, so a writer touching the params file faster than every
150 ms starves the render entirely (pre-existing, and the params watcher is a new source of bursts:
a formatter, a `git checkout`).

**WHAT S3 MUST KNOW ABOUT THIS WATCHER** (the review's item 10, recorded here before S3 starts). The
glob is the EXACT params path, so S3 writing `<binding>.schema.json` or `.ermine/preview/.gitignore`
matches nothing and triggers no render. But **S3's SKELETON write DOES match `onDidCreate`**, so S3
must (a) expect its own write to schedule a render and must not also render explicitly, or it pays
two; and (b) **never rewrite the params file in response to an answer**, which would be a
write -> watcher -> render -> write loop with no bound.

**MUTANTS, ONE RUNNING TOTAL, AND EXACTLY ONE SURVIVOR THROUGHOUT.** Round one: 14 run, 13
killed. Round two (the first review's fifteen re-expressed plus this build's own): 27 run, 26
killed. Round three (the nine of the review's whose shape the delta round changed, re-expressed,
plus one per new decision): 18 entries, 17 run and killed, 1 **unexpressible** -- R2's "the
captured epoch is the live one" has no form left now that the snapshot is built before the await,
and its defect is P15's, which dies. **AND, MEASURED BY THE FINAL RE-CHECK ITSELF: 15 more run, 13
killed, 2 PROVABLY EQUIVALENT** -- the held token without its params fingerprint (a moved
fingerprint CLEARS the mark, so two refusals against one mark always carry the same fingerprint)
and consultation site 1 calling `shouldAutoRender` instead of `mayAutoRender` (it passes no
`scheduledAt`, so the two agree by construction). **THE ONLY SURVIVOR IN ANY ROUND IS R7**,
`installParamsWatcher` returning before it registers anything: a guard kept and neutered, which no
pin can see and no model can reach, observable only by `tracker/WP-7-MANUAL-CHECKLIST.md` §2.35 (on a copy of `src` +
`test` outside the worktree, each against the shipped suite; `scratchpad/wp8-s2-mutants/mutate3.py`).
Four of the review's own could no longer be APPLIED -- the shape they mutated does not exist -- and
were re-expressed as "the snapshot is taken after the read", which dies. **FOUR DIE TO A MODEL
TEST** (the fingerprint collapse, the dropped `FileNotADirectory`, the exact-match `name` fallback,
and a snapshot that shares the roots ARRAY), the rest to a source pin. **THE ONE SURVIVOR IS
`installParamsWatcher` RETURNING BEFORE IT REGISTERS ANYTHING** -- a guard kept and neutered, which
no pin can see and no model can reach, because the watcher's REGISTRATION is editor glue.
`tracker/WP-7-MANUAL-CHECKLIST.md` §2.35 is its only observer, and it says so.


**AND A DELTA RE-REVIEW THE SAME DAY: IMPLEMENTATION GREEN, DESIGN RED ON THREE THINGS FOUND BY
EXHAUSTIVE EXPLORATION -- ALL THREE FIXED HERE.** The re-reviewer verified every must-fix above as
fixed (the frozen snapshot "the right shape, and it kills the whole class"; every read after the
await classified; M4 cannot loop; M5 loses no render; the read bound and the stat guard sound;
teardown clean) and then drove **the REAL reducers, in the glue's real order, over every sequence
of a 13-event alphabet up to depth 5 -- 579,194 of them** -- asking one question of each: did a
render reach the wire for a report whose mark still stood, with no user action? **5,097 did.**

| # | What the explorer found | What it is now |
|---|---|---|
| **D1** | **`roots` with an UNMOVED fingerprint rendered a held report.** `guardReduce`'s `roots` case keeps the mark when the resolved list did not move, and the glue schedules on `affectsConfiguration` either way, so `TRIGGER_ROOTS` -- which was not in `UNCONFIRMED_TRIGGERS` -- walked past the consultation. **The justification recorded for leaving it out proves the opposite**: if the resolved list is the render session's discard key and it did not move, then nothing that matters changed | `TRIGGER_ROOTS` is in `UNCONFIRMED_TRIGGERS`, and **THE MEMBERSHIP RULE IS NOW WRITTEN DOWN, in the code and here: a trigger may stay OUT of the refused set only if, whenever the glue schedules it, the guard event it fed has CLEARED the mark.** Under that rule `invalidated`, `file-event` and `recovered` qualify (each tested, one predicate on both sides) and `roots` does not. MEASURED on the implementer's 13-event alphabet: this family alone is 1,218 of the violations that survive the other fix (the re-reviewer's wider 15-event alphabet counts 1,851 for the same family) |
| **D2** | **`shouldAutoRender` FAILED OPEN on an unknown trigger** -- `undefined`, `null`, `""`, `0`, a typo -- so a mutant that simply forgot to forward the trigger through the coalescer neutered BOTH consultation sites for every automatic render and survived all 210 tests of the round before this one | the closed `RENDER_TRIGGERS` is the vocabulary: anything outside it is treated as UNCONFIRMED **and** reported by `triggerProblem`, which the glue logs as a BUG line -- the restart reducer's clockless-arm philosophy. The vocabularies are unified: `applyStuck`'s own `"restart"` / `"recovered"` / `"answer"` strings, which overlapped `RENDER_TRIGGERS` **by luck**, are now the constants (`TRIGGER_ANSWER` is declared for the third, with a comment saying `stuckReduce` can never emit a rerender for it). The pre-existing test that pinned fail-open is rewritten and says why the policy changed |
| **D3** | **"Not now" was not remembered**, so under format-on-save a held report asked once per save | the refusal is remembered as `core.heldPromptToken(mark)` -- the mark's key, its `at` and its params fingerprint -- and `core.shouldAskHeld` re-asks only when that token moves. **ONLY `params-file` IS REMEMBERED**: a RESTART is a new event the user caused or the server suffered and always asks again, and so do `module-learned` and `roots`. Between questions the `held` status bar keeps saying so and each suppressed re-ask is ONE channel line. Consent, a new mark, another pick and a teardown all reset it |
| **DOC** | §14's WP-22 row claimed evidence triggers can never reach the consultation with a mark standing. **False twice**: for `roots` (D1), and for the other three through the window -- `invalidated` clears and schedules, the report wedges AGAIN inside the 150 ms and the params read, and the render then fires PERMITTED (the explorer's families B and C: 2,466 sequences on the 13-event alphabet, 4,020 on the re-reviewer's 15-event one) | **OPTION (b) WAS BUILT, not (a).** `scheduleRender` records `Date.now()`, `renderNow` carries it, and `core.markMintedAfter` holds a non-explicit render whose mark is NEWER than the trigger that scheduled it. It is one pure function and one argument, it fails OPEN on a missing or non-numeric clock (it refines an already-safe decision), and it makes the tracker sentence TRUE instead of hedged. The argument for it over (a): the evidence was real when the render was scheduled, but by the time it would be sent the report has wedged the server again, and sending it is the one thing WP-22 exists to stop -- the server would refuse it anyway while stuck, and what the developer wants there is the question, not a refusal in the tab |

**MEASURED, BEFORE AND AFTER, AND THE ALPHABET IS PART OF THE NUMBER.** Over the implementer's
run of the re-reviewer's script -- **a 13-event alphabet, 579,194 exhaustive sequences**,
`scratchpad/wp8-s2/explore-after.js`, with the clock and the schedule time threaded through as the
glue threads them: **5,097 violations -> 0.** The oracle keeps its teeth on that alphabet: undoing
D1 alone answers **1,218** (all `roots`), and undoing families B/C alone answers **2,466** --
`recovered` 822, `invalidated` 822, `file-event` 822, matching the re-reviewer's count for that
family exactly. **THE RE-REVIEWER'S OWN ALPHABET IS WIDER (15 events) AND GIVES BIGGER NUMBERS FOR
THE SAME TWO FAMILIES: 1,851 for `roots` and 4,020 for B/C**, so a figure quoted anywhere must say
whose alphabet it came from. **THE FINAL RE-CHECK RAN ITS OWN, AGAINST THE FIXED TREE: 813,615
EXHAUSTIVE SEQUENCES AND 3,200,000 RANDOM STEPS, 0 SAFETY VIOLATIONS AND 0 LIVENESS DEAD ENDS**,
including the "Not now" then re-mint scenario walked explicitly (a re-minted mark changes the
token's `at`, so the question is asked again). **WHAT NO EXPLORER CAN SEE IS D2**: every such model
passes declared constants, so a trigger nothing declared never occurs in it -- D2 is covered by
mutation and by a table test, not by exploration, and that is why both exist.

**LAST-WINS IN THE COALESCING WINDOW STAYS, AND D1 IS WHAT MAKES IT SOUND.** The window keeps the
last trigger rather than the most conservative one, and that is safe precisely because of the
membership rule: every trigger NOT in `UNCONFIRMED_TRIGGERS` has already cleared the mark by the
time it schedules, so a window ending in an evidence trigger has no mark to walk past, and one
ending in an unconfirmed trigger consults it. Before D1, `roots` broke that. Keeping the most
conservative label instead would change no outcome under the rule and would hide which event
actually asked for the render, which is what the channel line is for. **`scheduledAt` IS LAST-WINS
TOO**: it is taken inside `scheduleRender` on every call, so the trigger and the time always come
from the SAME call and cannot describe different events. First-wins was rejected for the time as
well -- it would date the render by an event the window has since superseded, so a mark minted
between the first trigger and the last would look older than the render and the hold would not
fire, which is the opposite of what it is for.

**THE FINAL RE-CHECK (2026-09-21) RETURNED DESIGN GREEN AND IMPLEMENTATION GREEN**, against its
own exploration quoted above and its own fifteen mutants; what it left was documentation, and two
of those were corrections rather than additions: the `markMintedAfter` comment described a
backwards-clock check that does not exist (the behaviour -- fail CLOSED there, one question -- is
right and is now written down as what it is), and §14's WP-8 row still carried an older test
count. The one code line it prompted is `TRIGGER_ANSWER` joining `UNCONFIRMED_TRIGGERS`: it can
change no behaviour today (`stuckReduce` emits no rerender for an answer, which a test now
asserts) and it puts the safe side of the only way it could ever matter in the code rather than in
a comment -- which is how D1 happened.

**FOUR PINS THE RE-REVIEW FOUND MISSING, ALL ADDED**: `verdict` must be ASSIGNED FROM
`core.mayStillSend` (calling it and discarding the answer on the next line survived every earlier
pin); `lastServerAnswer` must be WRITTEN as well as read; the bounded read must be the one
`prepareParams` actually calls; and `scheduleRender` must FORWARD its trigger and its schedule
time. **TWO NITS**: the client the verdict saw is captured as `sentClient` and is the one the
request is sent to, and the placement-404 log line names the snapshot's path.


**S3 (THE FIRST PICK WRITES) IS BUILT, 2026-09-21 -- `editor/vscode` ONLY,
JavaScript, JSON and documentation, extension 0.1.8 -> 0.1.9, PLUS ONE LINE IN
THIS REPOSITORY'S OWN `.gitignore`. NO SCALA COMPILES AND NO JVM GATE MOVES.
IT HAS NOT BEEN REVIEWED, AND NOBODY HAS RUN IT IN VS CODE.** It is the first
version of this extension that writes to the developer's disk; every editor
behaviour below is UNOBSERVED and is on
`tracker/WP-7-MANUAL-CHECKLIST.md` §2.43-2.52, ten new steps.

| What was added | Where | What it decides |
|---|---|---|
| `isoDay(when)` | `preview-core.js` | `YYYY-MM-DD` in the machine's OWN timezone, not a UTC slice: west of Greenwich the slice is tomorrow's for most of the working day, and U2's rule is "today". Pure -- the glue owns the clock, as it does for the restart reducer |
| `schemaOrder(paths, fileMissing)` | `preview-core.js` | **G15, decided per case.** No params file -> the SCHEMA first (that render is a certain 400 anyway: control E of S2's table) and the skeleton is written from the answer; a file present -> the RENDER first and the schema only refreshes the generated file; no paths at all -> neither, and the render goes with the inline `{}` S2 already explains once per pick. `fileMissing` is a STRICT `true`: an "I do not know" must never be read as "there is no file" |
| `shouldRefreshSchema(answer, trigger)` + `SCHEMA_REFRESH_TRIGGERS` | `preview-core.js` | **D8, and one thing D8 as written did not say.** The ANSWER must say the report compiled (`ok`, or a 400 at `$.params*`) -- and the TRIGGER must be one that could have moved the parameter TYPE. The five that can are `explicit`, `invalidated`, `module-learned`, `roots`, `file-event`. `params-file` is excluded twice over: editing the parameters cannot change their type, AND it is the trigger the skeleton's own creation fires, so leaving it out is what stops a first pick asking for the schema twice in a row. `restart` and `recovered` are the `fx.schema` seam's own. An undeclared trigger refreshes nothing -- D2's fail-closed policy, applied again |
| `schemaAnswerOutcome(answer)`, `schemaRequestFailure(err)` | `preview-core.js` | The four ways a schema request can fail, each NAMED and NONE of them blocking the render: a `{error}` (`Preview.schemaError`), Q8's `{error, stuck:true}` refusal (`Preview.Schema.stuckRefusal`), an answer that is not an object at all, and a JSON-RPC error or transport rejection. Every one falls back to `{}` and is said ONCE per reason per pick |
| `mayUseSchemaAnswer(atSend, now, pickNow)` | `preview-core.js` | **D7, and BOTH tests, neither redundant.** `mayStillSend` knows the restart, the stop counter, the generation and the teardown but its pick identity is `markKey`'s -- uri and binding. `isCurrentSchemaAnswer` knows the MODULE, which is the DIRECTORY the file would be written into, and the roots in order. A header edited from `module Sales` to `module Sales2` moves the second and not the first, and a test asserts exactly that gap |
| `schemaFileNeedsWrite(existing, next)` | `preview-core.js` | D8's write-if-different, as a decision rather than an `if` in the glue. A file that could not be READ compares unequal and is written: "we do not know what is there" is not "it is already right" |
| `paramsWritePlan(paths, schema, today)` | `preview-core.js` | The bytes, the paths and THE ORDER: `.gitignore` (`ifAbsent`), `<binding>.schema.json` (`ifDifferent`), `<binding>.params.json` (`ifAbsent`) -- **the params file LAST, because its creation is what the S2 watcher sees** and the schema it points at must already be on disk. A skeleton that has no finite value writes NOTHING, not some of it. A non-object root (G5) still gets its params file, without a `$schema` key, and still gets the schema file |
| `paramsWrittenNotice`, `schemaProblemNotice`, `schemaNoticeKey` | `preview-core.js` | The two sentences and the one-notice-per-(pick, reason) key, shaped so it cannot collide with S2's `paramsNoticeKey` |
| `TRIGGER_SCHEMA` | `preview-core.js` | A new render trigger, declared in `RENDER_TRIGGERS` and -- **under the written membership rule, which FORCES it** -- in `UNCONFIRMED_TRIGGERS`. The glue schedules a refresh on a render's ANSWER, and `guardReduce`'s `answer` case KEEPS the mark for a non-stuck answer (that case only ever SETS), so it cannot qualify to stay out |
| `createFileWithoutOverwriting`, `applyWritePlan`, `writeTextFile`, `readTextIfPresent`, `ensureDirectory`, `openParamsDocument`, `requestSchema`, `firstPickSchemaAndWrite`, `refreshSchemaFile`, `refreshSchemaFor`, `forgetSchemaAttempts`, `schemaNoticeOnce`, `todayForSkeleton` | `extension.js` | the disk, the document and the requests, and nothing else |

**TWO SENTENCES OF THIS BLOCK WERE FALSE WHEN IT WAS WRITTEN, AND THE REVIEW
MEASURED BOTH.** "The one thing this extension will ever write over is ZERO
CONTENT" was not true twice: the test was `after.trim() === ""`, so a file
holding only WHITESPACE was written over (M-5); and nothing stopped a write
going THROUGH a symbolic link, so a `<binding>.schema.json` symlinked outside
the workspace was written through from the REFRESH path -- which is reachable
from an ANSWER, the one thing this section says an answer can never do -- and
a DANGLING params symlink had the skeleton created at its outside target
(M-3). "Three source pins hold it" was true of the STRINGS and not of the
filesystem: the pin that guards `refreshSchemaFile` checks that the text
`paramsPath` does not occur in it, and a symlink defeats that without
changing a character. **Both are fixed below and the sentences now say what
the code does.**

**NEVER OVERWRITE A PARAMS FILE, AND THE RACE IS ANSWERED RATHER THAN
NARROWED.** `vscode.workspace.fs.writeFile` OVERWRITES, documented and
unconditionally, so "stat, then write" is a check-then-act race: a `git
checkout`, a second window or a colleague's script can create the file
between the two, and the write then destroys committed source. So the params
file and the generated `.gitignore` go through
`WorkspaceEdit.createFile(uri, {overwrite: false, ignoreIfExists: true,
contents})` -- the documented way to ask the editor for a create that SKIPS an
existing file (*external*; `contents` has been on those options since VS Code
1.74 and this extension requires ^1.75.0). **WHETHER IT IS ATOMIC AT THE
FILESYSTEM LEVEL IS UNVERIFIED** -- nobody has run this extension and the
library's source is not read -- so the answer is not trusted and the file is
READ BACK. The read-back decides: our bytes -> `created`; OTHER bytes ->
`existed`, and that file is left exactly as it is; **ZERO LENGTH** (and not "empty": the S3
review's M-5) -> `contents` was not honoured, and this is the ONE overwrite
this extension performs, because zero bytes hold nothing anyone can lose and
a zero-byte params file is a named REFUSAL in S1. Whitespace is somebody's
bytes and is left alone; the case this branch exists for -- an editor that
honoured the create and dropped its `contents` -- produces a genuinely
zero-length file. A LOOK BEFORE the create was added after the measurement run
caught the reporting defect it exists for (below).

**THE WRITE PATH IS REACHABLE FROM ONE BRANCH, AND THAT IS STRUCTURAL.** The
S2 review's item 10 asked S3 to make "never rewrite the params file in
response to an answer" impossible rather than merely avoided. It is:
`core.paramsWritePlan` has exactly ONE caller, `firstPickSchemaAndWrite`,
which has exactly ONE caller, `renderNow`'s no-file branch; and
`refreshSchemaFile` -- the only thing an ANSWER can reach -- builds no plan
and **never names the params path at all** (a source pin reads its body with
the comments stripped and says so). Three pins hold that chain, and a fourth
holds that the branch expects its own write to schedule the render and
schedules nothing itself.

**AND ITS OTHER HALF: ONE RENDER, NOT TWO.** The S2 review established that
the skeleton's creation matches the params watcher's glob. So the no-file
branch ABANDONS its own render, writes, and leaves the render to the
watcher's `onDidCreate`. The reveal a first pick would otherwise lose --
`pickReport` renders with `reveal: true`, the watcher does not reveal -- is
carried across on a one-shot latch that is consumed at the top of the next
`renderNow`. **THE ONE EXCEPTION, AND IT CANNOT LOOP**: when the params file
turned out to be somebody ELSE's (the race above), no create event of ours
exists, so that branch schedules a render itself -- and `firstPickTried`
already holds the pick, so the no-file branch cannot be re-entered for it.

**A SCHEMA REQUEST IS AN AUTOMATIC ACTION ON THE PREVIEW QUEUE, NOT A READ,
AND IT CAN WEDGE THE SERVER.** READ from the Scala rather than assumed:
`Preview.schema` enqueues a `Schema` job (`:603-623`), `doSchema` calls
`Runner.paramSchema` under the render session (`:1554-1567`), and
`paramSchema` -> `report(module, binding)` -> `compileOnce` runs
`Session.loadModules(List(module))` and then `Session.eval(binding, ...)`
inside `evalLock` (`json/Runner.scala:845-852`). Loading TYPE-CHECKS the
module and evaluating forces the binding to WHNF. The server says it in its
own comment (`lsp/Preview.scala:596-598`): *"THE WATCHDOG covers it:
`paramSchema` compiles the report, which evaluates the binding, which is the
very thing that can fail to terminate."* `doSchema` also sets `evalFailed` on
a status >= 500, the same as a render. **So all three sites go through WP-22's
ONE consultation before anything is sent** -- the first-pick request with the
RENDER'S OWN trigger (an explicit pick is consent and is never refused; a
`params-file` save of a held report is refused exactly as its render would
be), the post-render refresh with `TRIGGER_SCHEMA`, and the `fx.schema` seam
with the trigger `applyStuck` was given. What it does NOT do is evaluate the
report's BODY: `Session.eval` forces the top level, and for
`report : Query -> Node` that is a closure. A report written point-free whose
own definition diverges would wedge on the schema alone; nothing measured
that, and nothing needs to, because the guard covers it either way.

**`fx.schema` IS WIRED, AND THAT ITEM CAME FROM S4's ROW.** The four-stage
plan lists "`fx.schema` wiring on recovery/restart" under S4. S3 took it,
because S3 is what builds the schema client and leaving the seam logging a
sentence about itself for one more stage buys nothing; it is recorded here
rather than silently moved. What it now does: forget the first-pick attempt
(so a report whose write failed while the server was wedged gets another go)
and refresh the schema file, through the same consultation. It refreshes ONLY
where a params file exists -- a `<binding>.schema.json` with nothing beside it
is referenced by nothing and costs a preview job that compiles and evaluates
the report to produce.

**U7's SECOND HALF IS AN INTERPRETATION, AND IT IS FLAGGED AS ONE.** U7 asks
for the generated `.ermine/preview/.gitignore` "PLUS the repo line". S1's
ledger says "WRITING it is S3, and so is the repo line", which is ambiguous
between *the extension writes into the user's root `.gitignore`* and *this
change adds the line to this repository*. **S3 TOOK THE SECOND READING**:
`**/.ermine/preview/**/*.schema.json` is now in this worktree's own
`.gitignore`, with a comment saying the `*.params.json` beside them are
deliberately not ignored, and **the extension writes only the self-contained
generated file**. The argument: editing a file the developer maintains, from
an extension, without asking, is intrusive in a way nothing else here is; the
generated file already covers every workspace folder including WP-13/WP-14's
`*.db`; and the repo line's stated purpose -- "a checkout should say what it
ignores in the place people look" -- is about a CHECKOUT, which is this one.
**THE ALTERNATIVE IS NAMED AND NOT BUILT**: offering it through a
notification button ("Add the line to .gitignore?") the first time a schema
file is written. **The reviewer and the user should confirm the reading.**

**MEASURED 2026-09-21 AGAINST A REAL `bin/ermine-lsp`, ONE BOOT, NO EDITOR**
(`scratchpad/wp8-s3/measure.py`, `measure.log` beside it). A scratch
workspace holds a copy of `core/src/test/resources/doc` plus two modules
written for this and kept OUT of the tree: `WpInt` (`report : Int -> Node`,
WP-7's own `WpSpin` shape minus the spin -- G5's non-object root) and
`WpTree` (`data Tree = Leaf | Branch Tree Tree`, the recursive golden shape
D-1 turns on). For each report: one real `ermine/schema`, then the SHIPPED
`paramsWritePlan` / `schemaFileFor` / `schemaFileText` / `skeletonFrom` over
that answer, the three files written to a real disk in the plan's own order
and with its own modes, then the written params file read BACK through the
shipped S2 chain and SENT as `ermine/render`:

| report | schema | skeleton written | run 2 | first render |
|---|---|---|---|---|
| `Sales.report` | 488 bytes, `$schema`/`$id`/`$ref`/`$defs` | `{"$schema":"./report.schema.json","fromDay":"2026-09-21","toDay":"2026-09-21","orderBy":"ByDay"}` -- `onlyRegion` ABSENT | schema SKIPPED, params `existed`, **bytes identical** | **`ok=false, status=500`**, `$.children[1].cells[0][0].props` -- Q21 |
| the same, dates edited to 2026-01-05..2026-03-17 | | | | **`ok=true`, a 1407-byte document** |
| `WpInt.report` (G5) | 105 bytes, `$schema`/`$id`/`type` | `0` -- `embeddable: false`, **no `$schema` key** | schema SKIPPED, params `existed` | **`ok=true`**, an 86-byte document |
| `WpTree.report` (D-1) | 586 bytes, a `oneOf` of two arms | `{"$schema":"./report.schema.json","tag":"Leaf","args":[]}` | schema SKIPPED, params `existed` | **`ok=true`**, a 111-byte document |

**AND THE D-1 ROOT-LEVEL COPY IS NOW MEASURED END TO END against a REAL
exporter answer rather than against a committed golden.** `WpTree`'s written
file drops `$id`, mints `WpTree.Tree-params-root`, points the ROOT `$ref` at
the copy, injects `"$schema": {"type":"string"}` into BOTH arms of the COPY
only, leaves the shared `WpTree.Tree` forbidding a nested `$schema`, and the
copy's own inner `$ref`s still name the ORIGINAL -- one level and no more,
exactly as the mechanism was written.

**WRITE-IF-DIFFERENT AND NEVER-OVERWRITE WERE MEASURED, NOT ARGUED.** Run 2
over the same answer: the schema file `skipped`, its sha256 identical across
the two runs, the params file `existed` and its bytes UNTOUCHED. Then the
params file was EDITED and the whole plan applied again -- the edit survived,
which is the "a second pick does not rewrite the params file" done-when,
measured on the shipped code rather than on a model.

**ONE DEFECT THE MEASUREMENT RUN ITSELF FOUND, AND IT WAS IN S3's OWN CODE.**
The first run reported `wrote=['gitignore','params']` on a second pass over
files it had not touched: the read-back cannot tell "we created it" from "it
was already there holding exactly these bytes", and `createFile` with
`ignoreIfExists` does not say. That is not cosmetic -- `{wrote: true}` is what
makes `renderNow` abandon its render and wait for a watcher event, and the
notice and `openParamsDocument` would have fired for a file the extension did
not write, opening a document over what the developer is typing. A LOOK
BEFORE the create now answers `existed` for any file that is already there;
it decides nothing about safety (the create skips an existing file whatever
it says) and everything about what is SAID. The pathological remainder -- a
file appearing between the look and the create WITH THE SAME BYTES -- is
reported as `created`, and both answers are safe because nothing was
overwritten either way.

**Q21 IS UNTOUCHED AND S3 DOES NOT CHOOSE.** S3's code is IDENTICAL under
options (a) "keep today and accept the 500" and (b) "give `Sales.e`'s
relations a header hint" -- (b) is a change to the example and to nothing
here. Under (c), "change U2's date rule itself", what moves is
`todayForSkeleton` (`extension.js`) and the `today` argument `skeletonFrom`
already takes: `isoDay` would be replaced by whatever rule (c) chooses, one
call site, and no other function in either file would change. The done-when
"`Sales` renders a document on first pick" is still BLOCKED. **AMENDED 2026-09-23: the user chose
(b) plus a ticket (Q21, WP-29); S3's code did not move, and the done-when is MET as written.**

| G-item | S3 |
|---|---|
| G8 never overwrite, write failures | **CLOSED.** `ifAbsent` through `createFile(overwrite:false, ignoreIfExists:true)` plus a read-back; a write failure is one notice, one attempt, and the render goes with `{}`. What is UNVERIFIED is whether that create is atomic, and the read-back is why it need not be trusted |
| G14 `ermine/schema` on the preview queue | **CLOSED**: `schemaParams(attempt.pick)`, the SAME roots as the render (Q7, one boot), through the frozen snapshot, discarded by `mayUseSchemaAnswer` |
| G15 the first-pick ordering | **CLOSED**: `schemaOrder`, decided per case, with the no-paths case named |
| D7 / D8 | **CLOSED in the glue**: the staleness guard is asked and acted on; write-if-different is MEASURED to skip, and the refresh is narrowed by both the answer and the trigger |
| U2 the file is opened for editing | **CLOSED (glue half)**: once per path per session, `preserveFocus`, beside. Its ARRIVAL is UNOBSERVED |
| U7 the two `.gitignore` files | **CLOSED, with the second half as an INTERPRETATION** (above) |
| G5 non-object roots | **the WRITE half is closed here** (a params file with no `$schema` key, and a notice saying the editor will not validate it), MEASURED on `WpInt`. S4 still owns the rest of its message -- **and closed it on 2026-09-23, with all five shapes measured** |
| G16 / U3 the "Write Params Skeleton" command | **NOT S3.** The four-stage plan does not list it under S3 or S4; D6 -- the orphan message that OFFERS it -- is S4's, so the command goes with D6. Nothing about it is built **here; S4 built both, 2026-09-23** |
| G17 the editor's schema cache | **NOT S3** -- manual checklist §2.50 |
| G6 / G1 / G3 / G4 | unchanged: `paramsPaths`'s refusals are S1's, and S3 writes nothing for any of them |

**WHAT IS GLUE AND THEREFORE UNOBSERVED BY ANYONE**: that
`WorkspaceEdit.createFile` is atomic, or honours `contents` at all; that
`workspace.fs.createDirectory` is recursive; that the skeleton's creation
fires the S2 watcher's `onDidCreate` (if it does not, the first pick shows NO
document rather than two, and the report renders on the next trigger --
§2.45); that `openTextDocument`/`showTextDocument` with `preserveFocus` really
does leave the cursor where it was; that VS Code's JSON language service
resolves a relative `$schema`, does not squiggle the `$schema` line (D1) and
re-reads the file when it changes on disk (G17); and that a `.gitignore`
written while the window is open reaches its SCM view.

**TESTS AND MUTANTS.** 216 -> 249 under `npm run test:preview`, green;
`node test/load-test.js` green. The 216 pre-existing tests are unchanged
except ONE assertion -- `UNCONFIRMED_TRIGGERS`'s pinned list, which grew by
`schema`, with the membership-rule derivation written beside it. **33
mutants run on a copy of `src` + `test` outside the worktree, 33 killed, 0
survivors** (`scratchpad/wp8-s3/mutate.py`) -- **AND THAT SENTENCE NEEDS THE
CORRECTION IN THE REVIEW BLOCK BELOW: this set did NOT cover the
neutered-guard class** (a body kept and its effect removed), of which the
review found three live instances. EIGHT of them are REVERSE mutants --
changes a reader might think equivalent: the racing params file not
re-rendered, an empty read-back left alone, the look-before dropped, the
reveal latch not consumed, `isoDay` using the UTC slice, `fileMissing` read
loosely, the params document opened every render, and `fx.schema` back to
logging. **FIVE SURVIVED THE FIRST ROUND AND EACH EXPOSED A WEAK PIN**,
including the most dangerous mutant of the set (the params write swapped for
`workspace.fs.writeFile`, which destroys committed source) and a pin whose
`indexOf` comparison passed on `-1`; all five pins were strengthened and the
round re-run. **THE LIMIT IS THE SAME ONE S2 RECORDED**: most of these die to
a SOURCE PIN rather than to a model, because the model is written from the
glue -- what pins cannot see is a body kept and neutered, and
`tracker/WP-7-MANUAL-CHECKLIST.md` §2.43-2.52 is the only observer of those.

**S3 WAS INDEPENDENTLY REVIEWED THE SAME DAY -- DESIGN RED, IMPLEMENTATION
RED, ON DEFECTS THE REVIEW REPRODUCED -- AND ALL FIVE MUST-FIXES AND TEN NITS
ARE APPLIED HERE (2026-09-21/23).** The review also verified a great deal
green and its own words are the record where they are: the never-overwrite
chain reproduced END TO END ON A REAL DISK through a scripted `vscode` rather
than in a model (absent -> `created`; committed source present -> `existed`
with zero `fs.writeFile` calls; a file appearing between the look-before and
the create -> `existed` with the user's work intact; `applyEdit` false ->
`failed`, nothing created; a directory at the path -> `failed`); the write
plan's order and modes; D7's two-test staleness check and D8's
answer-and-trigger narrowing, each caught by mutation when removed; the third
consultation site over **1,948,716 explored sequences, 0 held renders, 0 held
schema requests, 0 held file writes**; `fx.schema` asking ONE question per
restart rather than two (`refreshSchemaFor` only logs, and only `fx.rerender`
calls `holdRender`); the U7 reading, verified with `git check-ignore` in a
throwaway repo (both `*.params.json` TRACKED, all three `*.schema.json`
IGNORED, `local.db` TRACKED -- which is what U7 says the repo line should
leave); Q21 byte-unchanged but for a pure insertion; and the implementer's
own real-server numbers reproducing byte for byte.

| # | What was wrong | What it is now |
|---|---|---|
| **M-1** | **THE FOURTH OCCURRENCE OF THIS BRANCH'S RECURRING DEFECT** (after WP-22(c)'s M1, its delta review, and WP-8 S2's M1). `prepareParams` built four object literals; the model's read-settlers built their own; the model's `renderNow` read a model CONSTANT where the glue reads `prepared.paths`. **Deleting the one word `paths,` from the missing-file literal made `schemaOrder(undefined, true)` answer "render first, write nothing" -- THE WHOLE STAGE DEAD, no file ever written and no schema ever asked for -- with 249 of 249 tests green** (MEASURED by the review, reproduced by the implementer before the fix) | **THE CLASS IS CLOSED STRUCTURALLY, NOT BY ANOTHER PIN.** Every object the glue hands one of its own decisions is minted by ONE exported pure builder that the MODEL calls too, so a field cannot be present on one side and absent on the other: `preparedParams` (with the closed `PREPARED_KINDS` and a FAIL-CLOSED default), `createOutcome`, `writeOutcome`, `writeFailedProblem` and `schemaAbandoned`. The audit the must-fix asked for found `writeFailedProblem` as a fifth: the model's sentence differed from the glue's, so a test could pass on a message the developer never sees -- and N-5's whole point is in that sentence. `renderAttempt` was already one builder both call |
| **M-2** | **`applyWritePlan`'s `else` was FAIL-OPEN at the one site that can destroy committed source.** Any `mode` that was not the exact string `"ifAbsent"` fell through to an unconditional `workspace.fs.writeFile`. **MEASURED on a real disk: an entry `mode: "ifabsent"` -- one lowercase letter -- overwrote `{"COMMITTED":"SOURCE"}` with the skeleton and reported `{"wrote":["params"]}`** (reproduced before the fix). Not live, and a fail-OPEN default in a file that fails CLOSED everywhere else it matters | `core.writeStep(file, paramsPath)` decides, purely and table-tested: `ifAbsent` -> create; `ifDifferent` -> write-if-different; **anything else -> a NAMED REFUSAL**; and **the params file is refused by any route but the create whatever the mode says**, identified BOTH by its `what` and by its path, so neither a mislabelled entry nor a retyped mode can reach an overwrite. The modes and the `what`s are `core` constants shared by the plan that produces them and the loop that consumes them, so a typo is unwritable rather than merely caught |
| **M-3** | **SYMLINKS: S1 handed them to S3 IN THE SHIPPED SOURCE and S3 neither resolved them nor said it did not.** `preview-core.js`'s own comment said "S3 resolves before it writes"; there was no `realpath`, `lstat` or type-`stat` anywhere. **MEASURED, reproduced before the fix**: a `<binding>.schema.json` symlinked outside the workspace was written THROUGH by `refreshSchemaFile` -- **reachable from an ANSWER**, which §6 and §14 both say can never touch a file -- and a DANGLING params symlink had the skeleton created at its outside target | **REFUSE, which is what a pure decision plus one `stat` can honestly do.** Before ANY write, every existing directory component under `.ermine/` and every target is `stat`ed (`core.writeTargetPaths`, outermost first) and `core.writeTargetProblem` turns a `FileType.SymbolicLink` BIT -- a bitmask, so `SymbolicLink \| File` and `SymbolicLink \| Directory` both count -- into a named refusal; the report renders with `{}`. The check runs BEFORE `createDirectory`, because that would happily make the module directory inside a symlinked `preview/`. S1's comment is corrected to say what S3 does, and this block's two false sentences are corrected above. **MEASURED AFTER THE FIX on a real disk**: the schema file, the params file and a symlinked `preview/` directory each refuse with `symlink`, and the outside file stays `PRECIOUS`. **N-c, corrected**: a link to a DIRECTORY stats as **66** (`SymbolicLink \| Directory`), not 65 -- an earlier summary said 65, which is a link to a FILE. The code was right either way, because it tests the BIT and not the number, and a table test now walks 64, 65, 66 and 72 |
| **M-4 (DESIGN)** | **THE ONE-RENDER HAND-OFF: a first pick could show NO document at all, and say nothing.** `renderNow` abandoned after a successful write and left the render entirely to the S2 watcher's `onDidCreate`. On a FIRST pick nothing has ever called `showAnswer`, so if that event does not fire -- and NOBODY HAS EVER RUN THIS EXTENSION IN VS CODE -- there is no tab, no error and no line saying one is expected. The implementer flagged it and shipped it anyway on the orchestrator's instruction; the review judged silence the wrong failure mode for the feature's first minute, and **the orchestrator agrees** | The branch now calls `scheduleRender` itself, exactly as its own `raced` arm already did. A watcher event INSIDE the 150 ms window merges (`scheduleRender` clears and re-arms the one timer); one OUTSIDE costs a second IDENTICAL render -- one preview-queue job, NO boot (same session, same roots), and its `params` event computes the same fingerprint so the mark is untouched. The pin is re-expressed as **"at most one render per coalescing window, and nothing renders outside the coalescer"** |
| **M-5 (DOCS + ONE LINE)** | the README promised the params file is never overwritten "**not by anything in this version**", while the code wrote over any file whose read-back `trim()`ed to empty -- **and MEASURED, that includes WHITESPACE, not only zero bytes** | `after === ""`. Zero content is the stated rule; whitespace is somebody's bytes; and the case the branch exists for (an editor that honoured `createFile` and dropped its `contents`) produces a genuinely zero-length file. The README states the exception, and the symlink refusal, where the promise is made |

**AND THE TEN NITS, EACH APPLIED OR ANSWERED.**
**N-1** the pin protecting the only unbounded loop this stage could have
passed on a COMMENTED-OUT `firstPickTried.add(...)` (MEASURED: 249/249 green
under that mutant). Every pin that matches STATEMENT text now reads the
source through `codeOf`, which strips comments -- **and the audit was applied
to the S2 pins test as well, not only S3's**, which turned up one S2 pin that
keyed on a trailing comment (`// consent resets it`) and is now matched as
the statement and its neighbour.
**N-2** two prose-preserving mutants survived at D8's write-if-different (the
helper called, its answer ignored, once per site). There is now ONE site --
`writeIfDifferent` -- and the write is a CONSEQUENCE of the decision rather
than a statement beside it.
**N-3** an explicit pick of a previously-wedged report whose params type has
NO required fields was HELD seconds after the user asked for it: the skeleton
strips to `{}`, which fingerprints identically to what wedged, so the
watcher's `params-file` render was refused. **M-4's scheduled render carries
THIS render's own trigger**, so consent stays consent; the review's
`edge-empty.js` scenario is now a test.
**N-4 -- THE REVIEW'S PREMISE IS INACCURATE AND THE IMPLEMENTER SAYS SO.** It
reads the consenting render as carrying `restart`; `holdRender`'s answer
calls `renderNow("Render anyway", true, core.TRIGGER_EXPLICIT)`, and
`explicit` **is** in `SCHEMA_REFRESH_TRIGGERS`. So the seam's purpose is not
lost in the held case: after consent the schema IS re-asked, provided the
answer qualifies and a params file exists. The orchestrator's lean ("the
explicit render should qualify") is what the code already did; it is now
asserted rather than assumed, with a source pin on that `renderNow` call.
**N-5** a stray DIRECTORY named `.gitignore` aborted the whole plan and
`firstPickTried` then disabled params files for that workspace folder.
The generated `.gitignore` is a convenience: its failure is said once and the
params and schema files are written anyway. A failed PARAMS file still stops
the branch, which is the other half.
**N-6** the D8 refresh is fire-and-forget, uncoalesced and uncancelled. The
review's cost argument is recorded as **INFERRED, not measured**: renders are
coalesced at 150 ms so there is at most one refresh per render, and in an
ordinary save loop it is a CACHE HIT -- `Runner.report` memoises the compiled
report and `invalidate` evicts it (`json/Runner.scala:745-755`), and the
render that just ran repopulated it, so the added cost is a queue round-trip
plus `Schema.exportType` rather than a recompile. Nobody has measured that.
CONFIRMED by reading and by test: a refresh whose attempt is no longer
current returns on `outcome.abandoned` BEFORE its symlink check and before
its write.
**N-7** a schema that later answers `{error}` leaves the last good
`.schema.json` on disk. Deliberate, and now stated: the editor keeps
completing and validating against the type it last knew while the developer
fixes the module, the file is generated and gitignored, and the next answer
that compiles rewrites it.
**N-8** `isoDay`'s comment overstated ("west of Greenwich the slice is
tomorrow's for most of the working day" is true of the far west; at UTC-4 it
flips at 20:00 local). Corrected, and the review's own point added: **the
question is moot**, because the language server is the LOCAL process sharing
this machine's timezone and the feature has no server-side "today" at all.
**N-9** `revealNextRender` could leak to an unrelated later render if the
watcher never fired. M-4's explicit schedule consumes it promptly; the pin
holds that the latch is armed BEFORE the render that consumes it is
scheduled.
**N-10** a freshly built `renderAttempt` handed to `firstPickSchemaAndWrite`
silently vacates the MODULE half of D7, which `mayStillSend` does not
compare. Pinned.
**N-11** "guard skipped at `applyStuck`'s rerender" has survived every
mutation round on this branch and was twice recorded as irreducible glue.
**It is not**: the statement is pinnable exactly as the other two sites are,
and it is closed here, because S3 added a third site and the three should be
held alike.

**MEASURED BY THE REVIEW, RECORDED SO NOBODY RE-DOES IT.** Three real-server
cases beyond the implementer's four, one boot, no editor
(`scratchpad/wp8s3-review/remeasure.py`): **(A)** a report OUTSIDE every
workspace folder -- `paramsFolderFor` null, `paramsPaths` `no-workspace-folder`,
`schemaOrder` render-first/no-write, **nothing written and no schema asked
for**, and the render still happens (`400`, the required key); **(B)** a
second workspace folder NESTED in the first -- the INNERMOST wins, the files
land under `.../nested/.ermine/preview/Nest/`; **(C)** a record params type
with a `Maybe` field and a `Nullable` field -- the real exporter answers
`{"opt":{"type":"string"}, "nul":{"anyOf":[{"type":"integer"},{"type":"null"}]},
required:["need","nul"]}` and the skeleton is
`{"$schema":"./report.schema.json","need":"","nul":null}`: **`opt` OMITTED and
`nul` NULLED**, which is S1's rule 2 and its corrected `Nullable` rule
meeting a real answer, and the server renders it `ok=true`. **(D)** the
control reproduced the implementer's numbers exactly.

**THE REVIEW'S 24 REVERSE MUTANTS, AND WHAT CLOSED EACH.** Against the tree
as reviewed: 19 killed, **5 survivors** -- `firstPickTried.add` COMMENTED OUT
(N-1), `schemaFileNeedsWrite` called and ignored at each of two sites (N-2,
twice), a freshly built snapshot (N-10), the guard skipped at
`applyStuck`'s rerender (N-11, pre-existing) -- **plus M13, the M-1 mutant,
which is the finding**. Against the tree as it now stands: **every one of
them dies**, four to a pin that was strengthened or added (N-1 by comment
stripping, N-2 by collapsing two sites into one whose write is a consequence,
N-10 and N-11 by a statement pin) and M13's whole class by the builders. Nine
of the review's 24 can no longer be APPLIED at all because the shape they
mutate is gone; they are re-expressed in the implementer's round-2 set.

**AN HONEST CORRECTION TO THE BLOCK ABOVE.** It says "33 mutants run, 33
killed, 0 survivors, 8 of them REVERSE". That is true of that set and it
**did not cover the neutered-guard class** -- a body kept and its effect
removed (`if (false && ...)`, a statement commented out, a helper called and
its answer discarded). §11 states that limit correctly in general terms; the
"0 survivors" line reads as if the reverse set had covered it, and none of
the eight did. N-1, N-2 and N-11 are live instances the review found. The
round-2 set below is built to include that class deliberately.

**ROUND 2, AFTER THE REVIEW: 42 MUTANTS RUN ON A COPY OUTSIDE THE WORKTREE,
42 KILLED, 0 SURVIVORS** (`scratchpad/s3r/mutate2.py`), covering every
must-fix and every nit, the review's 24 re-expressed against the new shape,
round 1's own re-checked, and the neutered-guard class deliberately: a
statement commented out, a guard kept as `if (false && ...)`, a helper called
and ignored, a builder bypassed, a bitmask compared for equality, and
`FILE_TYPE_SYMLINK` read as `0` -- which is what the load test's `vscode`
stub would answer for `vscode.FileType.SymbolicLink`, and the reason the
number is written in `preview-core.js` rather than read off the editor's API.
**Two survived the first pass of round 2 and each named a weak pin**: the
render after the write guarded away with `if (false)` (the pin counted calls,
not statements) and `applyWritePlan` called without the params path to
compare (the belt, silently dropped). Both pins are now statement pins.

**THE EXPLORER, RE-RUN AGAINST THE FIXED TREE.** The review's own
`explore-s3.js` -- the real reducers and the real S3 pure functions in the
glue's order, with the logical clock wired to `markMintedAfter` -- answers
**0 held renders, 0 held schema requests, 0 held file writes** at depth 5
(177,155 sequences) and depth 6 (**1,948,716**). The implementer's extended
alphabet adds the S2 watcher's own `onDidCreate` as a 15th event, which is
what M-4 makes reachable alongside the scheduled render: **271,452 sequences
at depth 5 and 3,257,436 at depth 6, all three counts 0**.

**TESTS: 249 -> 261**, green, and `node test/load-test.js` green. The one
pre-existing assertion that moved is S2's `UNCONFIRMED_TRIGGERS` list (it
grew by `schema`); nothing else of the 216 is touched.

**AND A DELTA RE-REVIEW (2026-09-23): DESIGN GREEN, IMPLEMENTATION RED on ONE
reproduced defect plus three surviving neutering mutants. All three are
fixed.** It confirmed what the previous round built -- M-1 could not be broken
(the `paths` mutant, a builder bypass and a wrong-kind call all die), M-4 is
one call site and N-3 is repaired, M-3's policy works where it is invoked
(posix and win32, the bitmask, and `FILE_TYPE_SYMLINK = 64` confirmed against
`@types/vscode` `index.d.ts:9437`) -- **and it conceded both of the previous
round's disagreements**: N-4's consenting trigger really is `explicit`, and
the `applyStuck` guard mutant really does die now.

| # | What was wrong | What it is now |
|---|---|---|
| **D-1** (reachable from an ANSWER) | **`schemaAnswerOutcome` answered a BARE `{reason, message}` for its three server-side failures while `requestSchema`'s other two returns were WRAPPED `{problem: ...}`.** Both callers test `outcome.problem`, which is `undefined` for the bare shape, **so every server-side failure fell straight through the handler.** MEASURED on a real disk with a stub client, for all three: the D8 refresh then wrote the literal text `undefined\n` into `<binding>.schema.json` -- the params file untouched, but the editor's validation target destroyed -- and on the first-pick path the named reasons `error` / `stuck` / `no-schema` were DEAD CODE and the per-reason notice said nothing at all. **This is the defect a faithful model cannot see**: the model reproduced the GLUE correctly, and the glue and the pure core disagreed about a SHAPE | **One builder, `schemaOutcome`, mints all three arms**, every key always present, and a call naming none of them FAILS CLOSED into a problem. The model calls the same builder. **And a defence in depth at the write**: `schemaFileBytes` is the only thing that may produce the bytes of a `<binding>.schema.json`, and it refuses anything that does not ROUND-TRIP to a JSON object; `writeIfDifferent` and `writeTextFile` each refuse a non-string. So a write of the six-letter word is impossible by CONSTRUCTION, not only because the control flow now returns. `schemaFileText` is deliberately NOT narrowed -- it renders the PARAMS file too, whose value may legitimately be a number or `null` (G5, MEASURED on `WpInt`). **The builder audit is finished**: the model's literal `{abandoned: still}` (M-1's shape with the sign reversed), `firstPickSchemaAndWrite`'s nine `{wrote: ...}` returns and `writeIfDifferent`'s two are now `core.firstPickResult` and `core.writeResult` on both sides |
| **D-2** | **`statType` answered `null` on ANY throw, so a path that EXISTS but cannot be stat'd (EACCES) voided the symlink defence entirely.** MEASURED: a schema symlink outside the workspace was written THROUGH | "Not there" and "cannot tell" are different answers. `statType` returns `{type}`, `{missing:true}` (via `core.meansFileMissing`, the predicate S2 already wrote for this distinction) or `{unknown}`, and `writeTargetProblem` **refuses on `unknown`** with its own named reason `unstattable`. A `stat` that answers without a numeric `type` is also "cannot tell": a provider with no types cannot rule a link out either. MEASURED after the fix: EACCES on a path that exists -> `unstattable`; ENOENT on an absent path -> `null`; a typeless stat -> `unstattable`; ordinary files -> `null` |
| **D-3** | **the three M-3 glue sites had NO pin**: `statType` always null, and either `if (linked)` kept but neutered as `if (false && linked)`, all survived 261/261 | Whole-statement pins, comment-stripped, at both `if (linked)` sites and on `statType`'s return shape, in the same form as the M-4 pin |

**NITS**: **N-c** a link to a DIRECTORY is **66**, not 65 -- the code tests the
bit and was right either way, the sentence is corrected and a table test now
walks 64/65/66/72. **N-d** §2.45b now says that a watcher event landing
OUTSIDE the 150 ms window still carries `params-file` and may ask on an
empty-params report -- small, because the document has already arrived from
the scheduled render. **N-e** the as-built paragraph's "33 killed, 0
survivors" now points at the correction that follows it.

**MUTANTS, ROUND 3: 55 RUN ON A COPY, 55 KILLED, 0 SURVIVORS**
(`scratchpad/s3r/mutate2.py`, `round3-clean.log`), the round-2 set plus
thirteen for D-1, D-2 and D-3 -- including the shapes that made this round
necessary: a bare problem returned again, `schemaOutcome` failing open, the
refresh writing without `schemaFileBytes`, `writeTextFile` accepting a
non-string, `statType` collapsing its three answers into one, and each
`if (linked)` neutered. **One survived the first pass and is worth naming**:
removing `schemaFileBytes`'s round-trip check changes nothing for any input
reachable from the wire (`JSON.parse` never produces a `toJSON`), so no
behavioural test can kill it -- it is pinned instead, because "impossible by
construction" was the requirement. The reviewer's own 24 against this tree:
15 killed, 8 not applicable (their shape is gone; each is re-expressed in the
round-3 set), and 1 **provably equivalent** (`const attempt` -> `let attempt`,
with `attempt` never reassigned). **TESTS: 261 -> 266.**


**S4 (THE EDGES) IS BUILT, 2026-09-23 -- `editor/vscode` ONLY, JavaScript,
JSON and documentation, extension 0.1.9 -> 0.1.10. NO SCALA COMPILES AND NO
JVM GATE MOVES. IT WAS REVIEWED RED/RED (DESIGN RED, IMPLEMENTATION RED) ON
2026-09-23 BY AN INDEPENDENT REVIEWER; A FIX ROUND HAS BEEN APPLIED AND THE
RE-REVIEW IS PENDING (the orchestrator amends this sentence once it is in).
NOBODY HAS RUN IT IN VS CODE.** See **"S4 review and fix round"** at the end
of this block. It is the last stage of the four-stage plan, and it is the first version in
which anything in this extension can REPLACE a params file -- through one
command, after one modal, and through a permission that is the CALLER's
argument rather than a mode an entry carries. Every editor behaviour below is
UNOBSERVED and is on `tracker/WP-7-MANUAL-CHECKLIST.md` B22-B27, six new steps.

| What was added | Where | What it decides |
|---|---|---|
| `WRITE_EXPLICIT_OVERWRITE` + `writeStep(file, paramsPath, allowExplicitOverwrite)` | `preview-core.js` | **U3's one door, locked from the OUTSIDE.** The mode does not authorise itself: `writeStep` refuses it unless the caller ALSO passes `allowExplicitOverwrite === true`, and refuses it for anything that is not the params file. Every pre-S4 call site passes two arguments, so for the automatic path the third is `undefined` **for ever** -- which is what keeps M-2's rule ("the params file is refused by any route but the create") true of `firstPickSchemaAndWrite` word for word |
| `skeletonCommandPlan(paths, schema, today, replace)` | `preview-core.js` | The same plan as `paramsWritePlan` with ONE mode moved -- ONE shared body, two entry points -- so the command and the first pick cannot write different skeletons. `replace` is a STRICT `true` (`schemaOrder`'s own discipline: an "I do not know" must never read as a confirmation). MEASURED: the two plans are byte-identical apart from that mode, for all six real schemas |
| `skeletonCommandVerdict`, `skeletonConfirmation`, `SKELETON_REPLACE`, `skeletonConfirmed`, `skeletonStillApplies`, `skeletonReplacedNotice`, `skeletonCommandResult`, `SKELETON_COMMAND` | `preview-core.js` | may the command run (a pick, a client, a params path -- and a `paramsPaths` refusal answers with ITS OWN reason and sentence, so the command and the automatic path cannot disagree about why a report has no params file); the modal's exact words, which NAME THE FILE; the one string that consents; and whether an answer given to the modal still describes the report it was asked about |
| `paramsRootShape`, `rootShapeSentence`, and `shape` on the write plan | `preview-core.js` | **G5's other half.** S3's notice said what the file is NOT ("not a JSON object") and left the developer to open it and guess. This says what it IS, per shape, and every sentence is derived from a REAL exporter answer (the table below) |
| `directoryListing`, `orphanParamsFiles`, `orphanNoticeKey`, `orphanNoticeText`, `orphanListingNotice`, `ORPHAN_BUTTON`, `FILE_TYPE_FILE`, `PARAMS_SUFFIX` | `preview-core.js` | **D6.** Which params files under this module's directory name a binding the server no longer offers, and what to say about each -- once per (module, binding) per SESSION |
| `writeParamsSkeletonCommand`, `writeSkeletonNow`, `noticeOrphanParamsFiles`, `orphanNotices`, `openParamsDocument(fsPath, always)` | `extension.js` | the command, its write, the scan and the notifications, and nothing else |

**THE COMMAND'S ORDER, AND EVERY STEP OF IT IS PINNED** (`writeParamsSkeletonCommand`,
`extension.js`): `core.skeletonCommandVerdict` (a refusal is SHOWN as well as
logged -- the user just asked for this) -> read the file; **with none, this is
a first pick and takes the SAME race-safe `ifAbsent` create, with no modal,
because nothing can be lost** -> the MODAL, naming the file -> `core.skeletonStillApplies`
-> the guard's `render/explicit` event, which CLEARS the mark exactly as
`renderCommand` does -> WP-22's ONE consultation with `TRIGGER_EXPLICIT` ->
the snapshot, taken **AFTER** the modal -> `ermine/schema` -> the symlink check
-> the write with the permission -> the document -> `scheduleRender` carrying
`explicit`. **NOTHING IS ASKED OF THE PREVIEW QUEUE UNTIL THE USER HAS
ANSWERED**, which is pinned as an ordering and not only as a call count.

**WHY THE SNAPSHOT IS TAKEN AFTER THE MODAL, AND WHY `mayStillSend` IS NOT THE
GAP CHECK HERE.** A modal is the widest `await` this extension has -- minutes,
not milliseconds. Taking the snapshot afterwards means a server RESTART during
the question simply sends the request to the server that is running when they
answer, which is what they asked for. `mayStillSend` would have been the wrong
function anyway: its `superseded` arm refuses when the generation has moved,
which is right for a render (a newer one is already going) and WRONG here -- a
background save-triggered render must not cancel what the user explicitly asked
for. What DOES have to hold across the modal is the pick's IDENTITY including
its MODULE (the directory the file lands in) and its ROOTS, which is exactly
`isCurrentSchemaAnswer`'s four fields, so D7's function is REUSED and dressed
with a sentence rather than a second identity test being minted. A test asserts
the gap it closes: `markKey` answers the SAME for `module Sales` and
`module Sales2`.

**THE COMMAND MAY RUN WHILE HELD, AND IT CLEARS THE MARK -- WITH THE
CONSULTATION STILL ASKED.** An explicit command is the user in front of the
machine asking for this exact thing, which is the consent WP-22 already accepts
from "Render anyway" and from the render command; so the guard gets
`{type: "render", explicit: true}` and the mark goes. The consultation is then
asked anyway, with `TRIGGER_EXPLICIT`, which `mayAutoRender` never refuses.
**That site is not decorative**: it is what keeps every route to an
`ermine/schema` job going through the ONE consultation, so a future caller
arriving with another trigger is JUDGED rather than waved through -- and a
mutant that hands it `params-file` is in the set below. **The laundering
question is answered from the other end too**: `writeParamsSkeletonCommand` has
exactly ONE direct caller (the `registerCommand` in `activate`), the orphan
notification's button goes through `vscode.commands.executeCommand` -- the
palette's own door -- and a dismissed, ignored or differently-answered
notification runs nothing. All three are pinned and all three are mutated.

**ONE CONSEQUENCE OF CLEARING THE MARK BEFORE THE WORK, RECORDED RATHER THAN
DISCOVERED.** The guard event fires before the schema request, so a command
whose schema fails, or whose write fails, leaves the mark CLEARED -- and the
next automatic trigger for that report is then permitted rather than held.
This is not new and it is not an accident: `renderCommand` has always done
exactly the same (§14's WP-22 row records it as "the render command clears
the mark BEFORE `renderNow`, which no-ops when the client is mid-restart, so
that consent carries forward... defensible -- the user did ask"), and the
argument is the same one. The alternative -- clear it only on a successful
write -- would mean the user answering a modal, watching the command fail for
an unrelated reason, and then being asked the held question anyway. It is
named here so that a reviewer weighs it rather than finds it.

**D6, AND WHAT IT DELIBERATELY DOES NOT COVER.** After `ermine/preview/reports`
answers for the pick's file -- in the picker and in `refreshModule`, the two
places such an answer is already in hand, so it costs ONE `readDirectory` and
no server request -- the bindings the server offers are compared with the
`*.params.json` files under `.ermine/preview/<Module>/`. Each file naming a
binding that is not offered earns ONE notice per (module, binding) per SESSION:
a channel line and a `showWarningMessage` with a single **Write Params
Skeleton** button. **NOTHING IS EVER DELETED**, and a source pin asserts the
extension contains no `workspace.fs.delete`, no `fs.unlink` and no `rmSync` at
all. **IT FAILS CLOSED IN FOUR PLACES**, each of which is a way of calling a
file stale when it is not: a listing that could not be read (a problem, not an
empty directory -- `statType`'s D-2 distinction again); `reports` that is not an
ARRAY (the server could not list the file); `reports` that is EMPTY (the module
almost certainly does not compile right now, which is the worst possible moment
to call every params file stale); and an entry that is not a plain FILE (a
directory or a symbolic link is left alone, because naming one stale is advice
to delete something we did not write). **A RENAMED MODULE IS NOT COVERED AND
THAT IS RECORDED RATHER THAN HIDDEN**: the whole `.ermine/preview/<OldModule>/`
directory is then stale and nothing looks inside it, because this scan is only
ever asked about the CURRENT pick's module. Knowing better needs a map from
module name to file that the extension does not have: `ermine/preview/reports`
answers for ONE file, so the cheapest honest implementation is one request per
`.e` file in the workspace, each of which COMPILES a module on the preview
queue. That is not what a pick should cost. The stale directory is visible in
`git status` like any other committed file, and a test asserts the gap so that
it is a decision rather than a discovery.

**MEASURED 2026-09-23 AGAINST A REAL `bin/ermine-lsp`, ONE BOOT, NO EDITOR**
(`scratchpad/wp8-s4/measure.py`, `write.js` beside it, logs `run.log` and
`run2.log`). A scratch workspace holds a copy of `core/src/test/resources/doc`
plus five modules written for this: `WpInt` (`Int`), `WpEnum` (an all-nullary
`data`), `WpMaybe` (`Maybe String`), `WpJson` (`Json`) and `WpUnit` (`()`).
For each: one real `ermine/schema`, then the SHIPPED `paramsWritePlan` /
`skeletonCommandPlan` / `schemaFileFor` / `skeletonFrom` / `paramsRootShape` /
`paramsWrittenNotice` over that answer, the files written to a real disk in the
plan's own order and modes, then the written params file read BACK through the
shipped S2 chain and SENT as `ermine/render`:

| report | the exporter's root | skeleton | the notice's sentence | first render |
|---|---|---|---|---|
| `Sales.report` (the control) | `$ref` -> a closed object | `{"$schema":…,"fromDay":"2026-09-23","toDay":"2026-09-23","orderBy":"ByDay"}` | *ordinary committed source* (an object root explains itself) | **`ok=false, 500`** -- Q21, unchanged |
| `WpInt` | `{"type":"integer"}`, 105 bytes | `0` | *Its parameters are a single whole number, so the file holds just that number.* | **`ok=true`**, 84 bytes |
| `WpEnum` | `$ref` -> `{"enum":["Spring","Summer","Autumn"]}`, 193 bytes | `"Spring"` | *Its parameters are one of "Spring", "Summer", "Autumn", so the file holds just that value.* | **`ok=true`**, 94 bytes |
| `WpMaybe` | `{"anyOf":[{string},{null}]}`, 146 bytes | `null` | *Its parameters are optional (a single string), so the file holds just that value, and `null` means there is none.* | **`ok=true`**, 89 bytes |
| `WpJson` | `{}` -- only `$schema` and `$id`, 88 bytes | `null` | *Its parameters are any JSON value at all (the report takes a `Json`), so the file holds just that value; `null` is the smallest one that decodes.* | **`ok=true`**, 88 bytes |
| `WpUnit` | `{"type":"array","maxItems":0}`, 118 bytes | `[]` | *Its parameters are the empty tuple `()`, so the file holds just the empty array `[]` and there is nothing in it to edit.* | **`ok=true`**, 86 bytes |

**SO S4's OWN DONE-WHEN IS MET FOR ITEM 3: every non-object params root the
exporter can produce DECODES**, measured rather than argued, and each has its
own sentence. The same run also measured **U3's plan against the automatic
one: `[gitignore ifAbsent, schema ifDifferent, params explicitOverwrite]`
versus `[… params ifAbsent]`, with the three files' BYTES identical**, for all
six reports. The five fixtures are checked in at
`tracker/playtest/fixtures/Wp{Enum,Maybe,Json,Unit}.e` (beside S3's `WpInt.e`)
and their captured schemas at `editor/vscode/test/fixtures/wp*.schema.json`, so
the unit tests read REAL answers rather than hand-made ones. **The server
exited 1 rather than 0 in both runs**: the driver sends `exit` without
`shutdown`, which is what the LSP specification says exit code 1 is for, and
`scripts/liveness.sh` read `lsp=0` before and after.

**ONE LIVE TRAP S4 FOUND IN THE PINS' OWN TOOL, AND IT IS THE MOST IMPORTANT
THING IN THIS BLOCK.** `codeOf` -- N-1's comment stripper, which every
statement pin on this branch reads its source through -- was two regular
expressions, and `\/\*[\s\S]*?\*\/` does not know what a STRING is.
`extension.js` contains one: `vscode.workspace.findFiles("**/*.e")` in
`pickReport` holds the two characters that OPEN a block comment. Nothing closed
it, so the non-greedy regex simply failed to match and the file survived **by
luck**. S4 added a JSDoc block after `renderCommand`; its `*/` closed the
comment, and `codeOf` then deleted **124 lines** of `pickReport`,
`renderCommand` and the head of `activate` from what every pin reads.
**MEASURED: the picker's own `renderNow("the report was picked", true,
core.TRIGGER_EXPLICIT)` pin went from passing to FAILING with the source line
untouched** -- and had the new block landed a little further down the file, the
same deletion would have been SILENT and every pin inside those 124 lines would
have stopped protecting anything. That is precisely the failure N-1 exists to
prevent, one level down, in the tool N-1 built. `codeOf` is now a scanner that
knows single, double and template strings with their escapes, and regular
expression literals (`preview-core.js`'s `SAFE_NAME` contains a quote), and
strips comments and nothing else; there is a table test for it and an assertion
that the stripped `extension.js` still contains its last function. **Both
shapes are mutants below (T1, T2) and both die.**

**AND A SECOND, SMALLER ONE OF THE SAME FAMILY**: the S3 pin that holds the
params document's open compared two `indexOf`s, and S4 moved the second needle
(`core.paramsWrittenNotice(paths, plan.embeddable)` gained `plan.shape`). It
went to `-1`, and `anything > -1` is TRUE -- the pin stayed green and protected
nothing. Both needles are now asserted PRESENT before they are ordered. The S3
review had already found one `-1` comparison of this shape; this is the second,
and it is recorded so the next reviewer greps for the pattern rather than
rediscovering it.

| G-item | S4 |
|---|---|
| G5 non-object params roots | **CLOSED OUTRIGHT.** S3 closed the WRITE half; S4 measured all five shapes end to end and gives each its own sentence. `paramsRootShape` also names the string builtins (`date`, `date-time`, `uuid`, `Long`, `Char`) and fails to `unknown` rather than guessing |
| G6 a pick with no module, G3 a non-identifier binding | **CLOSED OUTRIGHT** (they were "closed (pure half)" since S1): each has a table test asserting the named reason AND the sentence, that `preparedParams` carries both into a channel line once per (pick, reason), that `schemaOrder` answers render-first/no-write, that both write plans refuse, that the COMMAND refuses with the SAME reason and the SAME sentence, and that the orphan scan cannot run for them (an early return, pinned) |
| G16 / U3 the "Write Params Skeleton" command | **CLOSED.** Built here, with the modal, the overwrite mode and the permission chain |
| D6 the orphan message | **CLOSED for a renamed or removed BINDING; a renamed MODULE is NOT COVERED and is recorded above** |
| G18 / U8 preview-only | **CLOSED (the docs note).** `editor/vscode/README.md` already said `bin/ermine-serve` never reads these files; S4 verified the sentence is there and left it as it stands |
| G13 / U5 credentials | unchanged: S2's, and S4 adds nothing |
| G17 the editor's schema cache | still the manual checklist's (B7) |

**WHAT IS GLUE AND THEREFORE UNOBSERVED BY ANYONE**: that
`showWarningMessage(text, {modal: true}, "Replace")` really is modal and really
resolves to the button's exact string; that Escape resolves to `undefined`;
that `vscode.workspace.fs.readDirectory` answers `[name, FileType][]` and
throws a `FileNotFound` for a directory that is not there; that a notification
with one button appears at all and that its `.then` fires; that
`vscode.commands.executeCommand` reaches our own registration; that
`openTextDocument`/`showTextDocument` shows a file that is ALREADY open a
second time; and that `registerCommand` for a seventh command does not collide
with anything. `tracker/WP-7-MANUAL-CHECKLIST.md` B22-B27 is the list that
would observe them, and it has never been run. **AND THE `.vsix` IS NOT BUILT**:
`editor/vscode/ermine-lang-0.1.9.vsix` is still 0.1.9 and does not contain any
of this. S4 ran with no `npm install`, so whoever plays this through packages
0.1.10 first or runs the extension from source; the checklist and
`tracker/PLAYTEST-RESULTS.md` both say so.

**TESTS: 266 -> 303**, green under `npm run test:preview`; `node test/load-test.js`
green (and it is what proves the seventh command is registered, because it
checks `contributes.commands` against what `activate` registers). **NO PRE-EXISTING TEST WAS
DELETED** -- the test diff is 1527 insertions against 21 deletions -- **and
what moved among them is exactly what S4's own shape moves, each named**: two
assertions in S3's non-object-root test, which now pass `plan.shape`; the
MODEL's `applyWritePlan`, which takes the new third argument because a model
must mutate exactly what the glue mutates; `codeOf` itself; and SIX assertions
in the S3 pins test -- three call COUNTS (`applyWritePlan` 2 -> 3,
`writeTextFile` 3 -> 4, `symlinkProblem` 2 -> 3), `applyWritePlan`'s signature,
`writeStep`'s call, and the params-document pin whose `-1` hazard is described
above -- each re-expressed with the S4 rule written into its message. **41 MUTANTS RUN ON A COPY OF `src` + `test` OUTSIDE THE WORKTREE**
(`scratchpad/wp8-s4/mutate.py`): round 1 **38 killed, 2 survivors and 1
unappliable**; both survivors were fixed by a stronger pin and round 2 is **41
run, 41 killed, 0 survivors** (`round1.log`, `round2.log`). **THE TWO THAT
SURVIVED ROUND 1 ARE WORTH NAMING, because both are the neutered-guard class
the S3 review named**: `if (existing !== null)` around the whole modal block
turned into `if (false)` -- so the command overwrote committed source with NO
QUESTION AT ALL and 303 tests stayed green, because the two pins on the modal
matched text that was still present but unreachable -- and
`openParamsDocument`'s own `&& always !== true`, dropped at the DEFINITION
while the call site stayed exactly as the pin reads it. Both are now
whole-statement pins. **EIGHT OF THE 41 ARE REVERSE MUTANTS** -- a
case-insensitive consent compare, `markKey` in place of the four-field check,
`replace` read loosely, the shape computed and its sentence dropped, the orphan
key made per-pick, the notices never forgotten, the command's render carrying
`params-file`, and the `always` open dropped -- **and THREE are the dangerous
direction**: the AUTOMATIC first-pick path given the overwrite permission, the
permission dropped from the command, and a dismissed notification running the
command anyway.

**S4 DOES NOT CHOOSE Q21 EITHER, AND NOTHING IN IT DEPENDS ON THE ANSWER.**
The command writes the same skeleton the first pick writes, from the same
`today` argument and the same one call site (`todayForSkeleton`), so under
option (c) exactly one thing still moves. `Sales`'s first render is still the
500 (MEASURED again above, on the shipped S4 code), and the checklist's B23
says so rather than calling it a defect of that step.

**S4 REVIEW AND FIX ROUND (2026-09-23).** An independent reviewer returned
**RED/RED** (`scratch-widget-preview/wp8s4-review/REVIEW.md`, read-only, HEAD
edb0b74c). The fix round below was applied the same day in this worktree,
UNCOMMITTED; **the re-review is pending**, and the orchestrator amends this
block once it is in. Report: `scratch-widget-preview/wp8s4-fix/FIX-REPORT.md`.

| id | what the review MEASURED | the fix | where |
|---|---|---|---|
| M-1 | `writeStep`'s overwrite arm used `isParams`, a DISJUNCTION (label OR path): `{what: params, path: <schema file / .gitignore / /etc/passwd>}` with the permission OVERWROTE it, end to end over a real disk. Not live (one plan builder mints the mode) | the overwrite arm now needs BOTH the `params` label AND `path === paramsPath` (`isTheParamsFile`); the older `params-not-creatable` refusal keeps the disjunction, which is right there. **Stricter than the reviewer's path-only variant**: a `schema`-labelled entry on the params path, which S4 let through "identified by its path", is now refused too, and that one pinned row was changed to say so | `src/preview-core.js` `writeStep`; test "S4 U3: the overwrite mode needs the CALLER's permission" (+12 rows: 3 targets x 4 `paramsPath` values) |
| M-2 | the refresh's `if (outcome.abandoned)` pin compared `indexOf`s with no presence check (`-1 < x`), over RAW source: deleting the guard (R16) left 303/303 green | positions bound, each asserted `> 0`, the guard's body asserted to `return`, source read through `codeOf` | test "S3 N-6" |
| M-3 | the command CLEARED the wedge mark before the work; a schema request that died or a symlink refusal left nothing written, nothing rendered and the hold gone (`probe/mark.js`) | **DESIGN CHANGE:** the mark is cleared only inside `if (written.wrote)`, beside `revealNextRender = true` / `scheduleRender(...)`. The `mayAutoRender(..., explicit)` consultation stays where it was and is now observable: with an automatic trigger it HOLDS (the "cannot LAUNDER" test now asserts held / no schema request / no write / mark intact) | `src/extension.js` `writeParamsSkeletonCommand`; README |
| M-4 | `firstPickModel` passed `paramsWrittenNotice(paths, plan.embeddable)` while the glue passed `plan.shape`; neither model reproduced `openedParamsFiles`' dedupe; R14/R15 died by pin only | two SHARED PURE BUILDERS the glue and both models call: `core.skeletonWrittenNotice(paths, plan, replace)` and `core.claimParamsDocument(opened, path, always)`. R14/R15's core forms now die by BEHAVIOUR (model tests over `WpInt`/`WpUnit`/`WpJson` roots; the command run twice opens twice) | `src/preview-core.js`, both models |
| DECISION | modal-to-write TOCTOU: a file saved during the `ermine/schema` round trip was DESTROYED (`probe/overwrite.js` case 4) | **RE-READ AND REFUSE.** After the schema answer and the symlink check, immediately before the write, the params file is re-read; a replace goes ahead only over the SAME string read before the modal. Changed or removed -> refused by name (`params-changed`), nothing written, no render, hold untouched. Pure decision `core.skeletonBytesStillApply`; model option `mutantNoReread` is the first cut and DESTROYS the edit. It narrows the window to the re-read-to-write gap; `workspace.fs` has no compare-and-swap, so it does not close it | `writeSkeletonNow(attempt, paths, replace, existing)` |
| nit 1 | a binding made PRIVATE looks orphaned | orphan sentence adds "(it was renamed or removed, or the module has made it private)" | `orphanNoticeText`; B25 |
| nit 2 | case-sensitive orphan compare on win32 | the binding and the `.params.json` suffix are compared case-folded **on win32 only** | `orphanParamsFiles`; win32/posix test |
| nit 3 | R24 (the unreadable-directory line never said) SURVIVED | shared `core.orphanNoticePlan(found, pick, seen, dir)`; the glue and the model log what it answers | glue scan + model + pin |
| nit 4 | two overlapping invocations each show a modal and each write | **NOT DONE** (benign; no in-flight latch). The TOCTOU re-read means the second of two overlapping replaces now REFUSES if the first has already written | — |
| nit 5 | consent-widening mutants HUNG the suite (R13) | `deferred()` is bounded: an awaited deferred nobody settles within 8 s rejects by name (timer `unref`ed, no unhandled rejections). R13 is now killed BY NAME | test helper |
| nit 6 | `paramsRootShape(true)` fell to the generic sentence | one `anyRootShape()` builder for `true`, `$defs` -> `true` and `{}` | `paramsRootShape` |
| nit 7 | the "Render anyway" pin read RAW source | reads through `codeOf` | test "S3 N-4" |

**MUTANTS.** The reviewer's independent battery was **25 on a copy: 22 killed,
1 killed-by-HANG (R13), 2 SURVIVORS (R16, R24)** — beside the implementer's 41
(41 killed) above, which it does not replace. **Both survivors are closed and
the hang now fails by name.** The fix-round battery — the reviewer's 25 (nine
re-targeted where the fix moved their text, same mutation) plus 21 new reverse
mutants (M-1 x3, M-2 x2, M-3 x2, M-4 x2 + two glue forms of R14/R15 + a core
form of R24, TOCTOU x4, nits x6) — is **46 run, 46 KILLED BY NAME, 0 hangs, 0
survivors, 0 unappliable** (MEASURED on a copy outside the worktree,
`wp8s4-fix/mut-fix.log`). **TESTS 303 -> 312**, `pass 312 fail 0`.
**RE-REVIEW (2026-09-23): DESIGN GREEN, IMPLEMENTATION RED on ONE test pin**
(`wp8s4-rereview/REVIEW.md` M-1): the TOCTOU pin checked needle order only, so
a post-modal read re-assigned into `existing` (V3/V3b; MEASURED on a real disk,
the edit was destroyed), `bytes.apply = true` (V4) and a neutered decision (V6)
survived 312/312. **Round 2**: the ask-and-obey is pinned as one contiguous
block and `const existing` as the only assignment; nit pins for V8/V11/V21, a
command per-shape model test (V13), the G15 pin's presence check, and the
"was removed or could not be read" wording. **313 tests, `pass 313 fail 0`; the
reviewer's 7 TOCTOU mutants + V8/V11/V13/V21 = 11 run, 11 KILLED BY NAME**
(`wp8s4-fix/mut-r2.log`). Left: nit 2 (decoded-text compare, stated in the
code) and nit 5 (macOS case fold).
Glue-side mutants still die by SOURCE PIN — a pin is the only thing that can
see `extension.js` here — while every decision the fix round moved into core
dies by BEHAVIOUR through a model.

## 7. Backends: profiles and one held connection

### 7.1 Profiles

`RunnerConfig.backend(dialect, url)` (`Runner.scala:183-199`) is a closed five-way match that
pairs one `Run[DB]` with one `Scanner[DB]`, fixes the driver class per dialect
(`Backends.scala:33-37`), and puts the URL into its refusal string (`:198`). The preview does
not call it. A **profile** is the unit of configuration, under `ermine.preview.profiles` in
**user** settings only (§8):

| Knob | Values | Meaning |
|---|---|---|
| `id` | string | label for the status bar and the picker |
| `dialect` | `sqlite` / `mssql` / `mysql` / `postgres` / `vertica` (`Runner.scala:183`) | chooses the **emitter**: new `Backends.scannerFor(dialect, scanner)` returning `Scanner[DB]` only |
| `driver` | JDBC class name | default per dialect as `Backends.scala:33-37`; overridable |
| `url` | JDBC URL **without credentials** (rule A9) | |
| `user` | optional | present: `DriverManager.getConnection(url, user, password)`; absent: `getConnection(url)` |
| `scanner` | `default` / `noTransactions` | `Scanners.MicrosoftSQLServer` vs `MicrosoftSQLServerNoTransactions` (`Backends.scala:26-27`), unreachable from any command line today |
| `settings` | JSON object | the document's `settings` object |
| `deploy` | boolean | marks the profile whose dialect the badge compares against (§9.4) |

A built-in profile `local` = `{dialect: sqlite, url: "jdbc:sqlite::memory:"}` is the default
and needs no configuration. Because the connection is **held**, the in-memory database
persists across renders (a `create table` once is possible), unlike `bin/ermine-serve`,
whose `Run[DB]` opens and closes per request and starts empty every time
(`DB.scala:106-116`; `JSON-GUIDE.md:1615-1621`). For a scanning report (§0) the documented
alternative is a **file-backed SQLite**, a user profile with `url: "jdbc:sqlite:<path>.db"`,
filled by the developer with `sqlite3`, DB Browser or a script of their own: zero server
code, and the data outlives a restart and a recycle. There is **no seed-script mechanism**
(no `seed: [paths]` run on connect): whether such a fixture is committed, and where the file
lives, is the developer's choice, not the tool's.

### 7.2 Connection lifecycle -- who owns reconnection

| Rule | Mechanism |
|---|---|
| The server holds a `Connection`, never a password field | `connect` runs `Class.forName(driver)` then `DriverManager.getConnection(...)` on the preview thread, wraps the result in `Runners.fromPersistentConnection` (`Backends.scala:49-51`) and swaps it into `delegatingRun`. `lsp/Preview.scala` references the `password` string by nothing after the call. Stated, not mitigated: Java strings cannot be zeroed, and the driver's `Connection` retains its connection properties, password included, for reconnect and failover (*external*, mssql-jdbc) until it is closed -- the claim is true of the server's code and false of the heap |
| `DB.RunUser` is **not** the tool | it is a per-run reconnecting closure over the password (`DB.scala:129-138`, zero callers): it would hold the secret for the process's life and open a connection per render |
| Recycling is the **extension's** reconnect | after N renders or T idle minutes (defaults in WP-14, Q2), on **Ermine: Disconnect Database**, or after a scan closes the connection, the server closes it and sends `ermine/preview/disconnected {reason}`; the extension sends a fresh `connect`. **AMENDED 2026-09-20 (§8's amendment block): this row used to say "the extension, which has `SecretStorage`" -- there is no secret store.** What the extension puts in that fresh `connect` is the open half of §8's rule, **WHICH THE USER DECIDED ON 2026-09-20** (*"prompted pass lives for the window."*), so this row can now say it plainly: the extension reconnects with **the password it still holds in the extension host's MEMORY**, and the reconnect therefore stays AUTOMATIC. It prompts again only after a window reload, an **Ermine: Disconnect Database**, or a failed login (A8). The stricter variant -- prompt on every connect, hold nothing, reconnect becomes a click -- was NOT chosen. The server never reconnects on its own, and none of this is built |
| Every successful `connect` re-sends the last render | so a render that lands between `disconnected` and the new `connect` (answered `503 not connected`) is replaced without waiting for the next save. The trace-`verbose` refusal (rule A7) lives in the extension's **one** `connect()` function, so the unattended recycle path cannot bypass it; while refused, the status bar reads "disconnected: trace is verbose" |
| Temp tables | MSSQL temp tables are `##global` (`SqlEmitter.scala:621`); neither the SQLite nor the MSSQL emitter drops them (`EmitNoDropTempTable`, `:431-433`, mixed into both `:676-683`, `:834-849`; `cleanTempTables` is a no-op, `SqlScanner.scala:240-248`). With a per-request connection the server reclaims them at session end; with a held one they accumulate in `tempdb` until a recycle. Names are GUID-fresh (`SqlScanner.scala:305`), so the measure is a **count**, never a collision |
| Cursor leaks on a failing scan | closed at J3c: `withDriver` tears down in a `finally` (`relational/package.scala:136-142`) |

A **profile switch** is a sequence, not a sentence; every step is a preview-queue job, so
ordering is queue order and the in-flight render simply finishes first:

| Step | Who | What |
|---|---|---|
| 1 | extension | bump `generation`; an answer with an older generation is discarded (§2.5) |
| 2 | extension | status bar "switching to `<id>`"; the panel keeps the last document dimmed under a "switching" banner (§5) |
| 3 | extension -> server | `ermine/preview/disconnect` |
| 4 | server | close the connection; **discard the `Runner`** (§2.4), which evicts `reports` and the compiled closure |
| 5 | extension -> server | `ermine/preview/connect {profile, password?}` after the rule-A3 prompt if the secret is missing; the A7 refusal applies here as everywhere |
| 6 | extension -> server | on `ok`, re-send the last render (the new `Runner` boots lazily inside it, with §2.5's progress) |

The same sequence runs when any field of the **active** profile, or `ermine.preview.roots`,
changes (`onDidChangeConfiguration`, `extension.js:262`); a change to an inactive profile
does nothing. Steps 5-6 are also the recovery after a server crash or restart (§5, "server
stopped"): on `Running` the extension prompts only if the secret is gone, reconnects and
re-renders.

### 7.3 Driver

| Fact | Status | Evidence |
|---|---|---|
| `Runners.MicrosoftSQLServer` loads `com.microsoft.sqlserver.jdbc.SQLServerDriver` | MINED | `Backends.scala:34` |
| `build.sbt` ships mysql-connector-j, jTDS and sqlite-jdbc only, so `--dialect mssql` fails at `Class.forName` today | MINED, not run | `build.sbt:111-113`; `DB.scala:107`; `JSON-GUIDE.md:1625-1627` |
| jTDS is used only by `Runners.cloudDB` | MINED | `Backends.scala:41-43` |
| `mssql-jdbc` with the `jre11` classifier: one artifact | *external* (jre11 runs on 11+) | the server runs on JDK 21 (`build.sbt:1`; `bin/ermine-lsp:25`); the 2.11 back-port is out of scope |
| mssql-jdbc defaults `encrypt=true`; an internal CA fails the first connect; `-Djavax.net.ssl.trustStoreType=Windows-ROOT` via `ERMINE_JAVA_OPTS` (`bin/ermine-lsp:20`) is the usual bridge | *external*, **to verify in WP-12** (Q3) | this is why the auth failure classifier (§8.3) must not treat a TLS failure as a wrong password |
| `MsSqlEmitter.sqlPrimT` maps `"date"` by type name with the comment "jtds gives x = varchar for dates" | MINED | `SqlEmitter.scala:881-882`; written against a driver this design does not use; one real check in WP-12 |

## 8. Authentication (standalone; read this if you read nothing else)

Settled constraints: the work SQL Server does **not** accept AD authentication; integrated
auth / Kerberos are unavailable there and not proposed. **SQL auth (user + password) is the
path.** Local runs use SQLite with no credential. Work machines are Windows, and the
extension host runs on Windows (§10).

### 8.1 Rules

| # | Rule | Mechanism | Status |
|---|---|---|---|
| A1 | No password field anywhere in settings | the `contributes.configuration` schema for `ermine.preview.profiles` declares `{id, dialect, driver, url, user, scanner, settings, deploy}` and nothing else | design |
| A2 | Profiles are read from **user scope only** | `getConfiguration("ermine").inspect("preview.profiles").globalValue` (*external*); a workspace- or folder-scope value is ignored and named once in the output channel | design; see the threat model |
| A3 | The password lives in `SecretStorage`, keyed by `sha256(url + "\0" + user)` | `context.secrets.get/store/delete` (*external*, since VS Code 1.53; the extension already requires `^1.75.0`, `package.json:8-9`, `:98`). Prompt with `showInputBox({password: true})` naming the **host** and user; store only after `connect` answers `ok`. A changed URL or user is a new key and prompts again, so a stored secret can never be replayed against a host it was not typed for. Command **Ermine: Forget Database Password** deletes the key of the active profile. On Windows the store behind it is the OS credential store (*external*) | design |
| A4 | The secret travels over the existing stdio JSON-RPC channel, in `ermine/preview/connect` | `extension.js:145-151`, `:179` already spawn the server on stdio. Never a command-line argument: `bin/ermine-serve:32-33` forwards `"$@"`, which `ps` shows | design |
| A5 | The server never puts a URL, a host or a password in anything a client or a log sees | the URL is not logged and not answered: `connect` answers `host` only; `RunError` messages come from `Runner`, which never sees the URL under this design (the preview does not use `RunnerConfig.backend`, whose refusal string carries it, `Runner.scala:198`); the status bar shows `id (dialect) @ host`. The driver's own text is covered by A10 | design |
| A6 | The wire log never records the connect body | `Rpc.scala:318` logs every incoming body to `ERMINE_LSP_LOG` (`bin/ermine-lsp:4`, `:19`; set from `ermine.logFile`, `extension.js:145-146`; clipped at 2000 chars, `:360`, which is more than a connect). WP-1 redacts by method (§4). Redaction keys on the method, so the three shapes that have none are settled explicitly: a message that is not an object, and an object whose `method` is not a string, log **no body** (either could hide a connect, e.g. `[{"method":"ermine/preview/connect",...}]`); a message with no `method` at all is a REPLY to one of our own `ask`s and **is logged in full**, by design. That is safe only while no reply can carry a secret: today the tree has exactly one `ask`, `client/registerCapability` (`Main.scala:203`, LSP-STALENESS step 2), and its reply carries a registration outcome the handler reads as `error` present or absent (`Main.scala:209-212`, the match; the continuation opens at `:208` and closes at `:213`) -- nothing a client would not already know. **Any future `ask` whose reply could carry one must extend the redaction**, which then needs the request-id-to-method map that resolution A5(iii) judged unnecessary | **DONE (WP-1)**; the rule binds WP-13 |
| A7 | The client trace never records it either | `ermine.trace.server` (`package.json:63-72`) at `verbose` logs request params to the output channel (*external*, vscode-languageclient). The extension **refuses to connect while the trace is `verbose`** and says why, in its one `connect()` function so the recycle path is covered (§7.2); `messages` and `off` log method names only (*external*) | design |
| A8 | After one authentication failure, no stored password is retried without a new prompt | §8.3 | design |
| A9 | No credentials inside the URL | before `connect` the extension refuses a `url` matching `/(^\|[;?&])\s*(password\|pwd\|user\|userName\|integratedSecurity\|authentication)\s*=/i` (*external*: mssql-jdbc property names) with "credentials belong in `user` and the prompt". This closes the Settings-Sync path (T2) at the only place the URL enters | design |
| A10 | Every driver message is scrubbed at the source | the connect handler catches `Throwable` (not `NonFatal`: an `ExceptionInInitializerError` from a driver's static initialiser is a `LinkageError`), never rethrows, and builds every answered message as `e.getClass.getSimpleName + ": " + scrub(msg)` where `scrub` replaces the profile's `url`, `user` and the URL's host with `<url>`/`<user>`/`<host>`; classification reads `getSQLState`/`getErrorCode` only (the shape `SqlScanner.scala:190` already renders). `Server.request`'s crash path (`Rpc.scala:478-480`, which logs the stack trace and answers `method + " failed: " + e`) is unreachable for `connect`, and the `<<` log line needs no redaction because nothing secret is ever in the answer. The predicted case: `DriverManager.getConnection` with no driver accepting the URL throws "No suitable driver found for <url>" (*external*, JDK), the full URL, on the first typo in `jdbc:sqlserver://` | design |

**AMENDED 2026-09-20 -- DECIDED BY THE USER: THE VS CODE SECRET STORE IS DROPPED. THE PASSWORD IS
PROMPTED FOR.** The user's words: *"I'd like to avoid the whole secret store for now. Let's just
prompt."* The rules above are kept as written and amended here, not overwritten.

| Rule | After the decision |
|---|---|
| **A3** (`SecretStorage` keyed by `sha256(url + "\0" + user)`) | **SUPERSEDED.** No `SecretStorage`, no hash key, no **Forget Database Password** command. The extension PROMPTS (`window.showInputBox` with `password: true`, *external*, unobserved) and passes what it gets to `ermine/preview/connect` |
| **A8** (no stored password retried without a new prompt) | **STANDS, trivially**: nothing is stored, so every connect that needs a password asks |
| **T2** (Settings Sync) | the question "is `SecretStorage` synced?" **falls away**; A1 already keeps settings free of a password and A9 keeps one out of the URL |
| **T4** (other extensions in the host) | no longer relevant to a secret at rest; the prompted value never leaves the extension host except in the `connect` request |
| §8.4's gate rows naming a stored secret ("the secret is gone from `SecretStorage`", "the secret is still stored") | re-read as **"the next connect prompts again"** and **"no password is held on disk anywhere"**. The greps those rows run are unchanged and still the evidence |
| **WHAT IS UNCHANGED BY THIS, and is the reason the decision costs nothing in safety** | A1 (no password in settings), A2 (user scope), A4 (stdio, never argv), **A5/A6 (the server never logs or answers a URL, a host or a password; `ermine/preview/connect` is redacted in the wire log -- BUILT in WP-1)**, A7 (the trace-`verbose` refusal), A9 (URL-credential refusal), A10 (every driver message scrubbed at source), and the credential gate of §8.4 |

**DECIDED 2026-09-20 BY THE USER -- the lifetime of the prompted password.** Their words:
*"prompted pass lives for the window."* The orchestrator's proposal below is therefore the
DECISION, unchanged in substance and no longer a proposal; the label is what changed, and the
paragraph is amended rather than overwritten. **The stricter variant named at the end of it --
prompt on every connect, hold nothing -- IS NOT CHOSEN.** Nothing here is built yet: it is
WP-13/WP-14's to build, and every claim about the editor in it stays unobserved.

Held in the EXTENSION HOST'S MEMORY for the lifetime of the editor window: never on
disk, never sent to a webview, and not retained by the server after the connect. FORGOTTEN on
window close or reload, on **Ermine: Disconnect Database**, and after a failed login (A8). The
reason to hold it at all is WP-14's EXTENSION-DRIVEN RECONNECT, which must keep working after a
server restart -- and the Q13 re-decision makes a server restart ROUTINE rather than rare. **The
stricter variant, NOT CHOSEN (2026-09-20, by the same decision)**: prompt on every connect and
hold nothing, at the price that a reconnect stops being automatic and becomes a click. Recorded
because it is the alternative that was on the table, not because it is still open. Neither is
built; both are one function in `extension.js` and unobserved.

**ALSO RECORDED, THE USER'S STATED PLAN (2026-09-20)**: stand up a LOCAL SQL Server with a
password, to unblock WP-12, WP-13 and WP-14 without the work network. Consequence for WP-12's
done-when, which should be SPLIT: a real connect, the `sqlPrimT` `"date"` mapping and the driver
dependency can all be MEASURED against the local server; **Q3 (is the work server's internal CA
in the JDK's `cacerts`, or is `Windows-ROOT` needed) still needs the WORK NETWORK** and cannot be
answered locally.

Precedent, cited not measured: Microsoft's `vscode-mssql` keeps connection profiles in
settings without the password, the secret in the OS store, and hands it to a separate
tools-service process over JSON-RPC stdio (*external*). It shows driver messages verbatim,
which is fine when the profile is in settings anyway; this design copies its secret-store
split, not its message handling.

### 8.2 Threat model

| Adversary | What they can reach | What stops them | What does not |
|---|---|---|---|
| T1 another account or process on the same machine | files under the checkout; the process list | A1 (settings carry no password); A4 (no argv); A6/A7/A10 (no log); `git add -A` after A6 finds nothing to leak | a heap dump or a debugger attached to the JVM (not addressed) |
| T2 synced settings | whatever Settings Sync carries | A1: the synced profile is url + user only, and A9 keeps a password out of the url. Whether `SecretStorage` is synced is *external* and **unverified**; the design assumes it is machine-local and WP-13's done-when records the answer here | |
| T3 an authored workspace (a colleague's repo with a committed `.vscode/settings.json`), trusted or not | any workspace-scope setting | A2: workspace profiles are ignored. A3: even a user-scope profile edited to another host has no secret under the new key; the prompt names the host. **The extension is not activated in Restricted Mode**, so no server and no preview run there (next paragraph) | `ermine.serverPath` (`package.json:43-47`; `extension.js:49-51`) already lets a workspace choose the executable the extension spawns -- a larger, pre-existing hazard; in a trusted workspace it is the user's trust decision, and this document says so rather than pretending the JDBC URL is the risk |
| T4 other extensions in the host | | `SecretStorage` is per-extension (*external*) | |
| T5 the log files | `ERMINE_LSP_LOG`, the output channel | A6, A7, A10, verified by the gate in 8.4 | |

Today the extension declares no `capabilities.untrustedWorkspaces` (grep, 0 hits), so it is
not activated in Restricted Mode at all (*external*); "the preview is off in an untrusted
workspace" is therefore already true and **stays true: the declaration stays absent.**
Declaring `supported: "limited"` would *activate* the extension there with only the named
settings blanked, and the server path is not only a setting: `resolveServer` falls back to
`<first workspace folder>/bin/ermine-lsp` (`extension.js:52-54`), spawned with
`cwd: server.root` (`:148-151`), so Restricted Mode would execute the untrusted repository's
own shell script as the language server -- a regression `restrictedConfigurations` cannot
reach, because it protects a *setting*, not a path derived from the folder. Nothing the
extension offers works without the server, so `limited` would buy nothing; the TextMate
grammar is a static contribution and keeps working (*external*, unverified). Should someone
later declare `limited` for another reason, `startClient` (`extension.js:126`) must first gate
on `vscode.workspace.isTrusted` and resume on `onDidGrantWorkspaceTrust` (*external*).

### 8.3 Failure classification

`connect` classifies on the driver's exception and answers a `class` and a `kept` flag;
`SqlScanner` already renders `getErrorCode`/`getSQLState` (`SqlScanner.scala:189-190`), so
both are available.

| Class | Signal | Extension does | Secret |
|---|---|---|---|
| `auth`, `kept: false` | `SQLException` with SQLState `28000`, or vendor error `18456` for SQL Server (*external*, mssql-jdbc's login failure) | shows the scrubbed message once; **deletes** the secret; marks the profile "prompt next time"; does not retry until the user renders again | deleted |
| `auth`, `kept: true` | vendor errors `18486` (account locked), `18487` (password expired), `18488` (must change) (*external*: corroborated by Microsoft's documentation and an Azure Data Studio issue, not by a driver run) | shows the message naming the reason; marks "prompt next time"; **never** an unattended retry, so a recycle cannot keep a locked account locked | kept |
| `driver` | `ClassNotFoundException` from `Class.forName`, or "No suitable driver" (the URL prefix matched no registered driver: a configuration error, not a network one) | shows "driver <class> not on the classpath (WP-12)" or "no driver accepts this URL" | kept |
| `connect` | every other exception: TLS (`encrypt=true` against an internal CA, §7.3 -- the failure this design predicts on the **first** connect), DNS, refused, timeout | shows the scrubbed message; no re-prompt; the stored password is kept because it was never rejected | kept |

Pinned with a fake `java.sql.Driver` registered in the test JVM (*external*:
`DriverManager.registerDriver`) that throws an `SQLException` with SQLState `28000` for one
URL, vendor code `18487` for a second, a plain `SQLException` whose message contains the URL
for a third, and accepts nothing for a fourth: the classifier answers `auth/false`,
`auth/true`, `connect` and `driver` respectively, never `auth` for the third, and the third's
message is answered with `<url>` while the log has 0 hits for the URL and the host (WP-13).

### 8.4 The credential gate

Run once, with `ermine.logFile` set **and** `ermine.trace.server` at each level:

| Setting | Expected |
|---|---|
| `verbose` | the extension refuses to connect; grep of the output channel for `preview/connect` finds the refusal line only, no request |
| `messages` + log file | connect succeeds; grep of `ERMINE_LSP_LOG` and of the output channel for the password: 0 hits; grep for the JDBC URL and for the host: 0 hits; `settings.json` has no password |
| wrong password | class `auth`, `kept: false`; the secret is gone from `SecretStorage` (`secrets.get` is `undefined`); the next render prompts |
| a URL no driver accepts | class `driver`; grep of the log and the output channel for the URL and the host: 0 hits; the secret is still stored |
| a URL carrying `password=` | refused by the extension before any request; nothing in the log |
| TLS failure (WP-12's first connect, if it happens) | class `connect`; the secret is still stored |

## 9. Dialect fidelity

No test in this repository executes the same relation against two dialects:
`core/src/test/scala/com/clarifi/reporting/sql/TestSqlEmitters.scala` compares emitted SQL
**strings** (grep for `scanRel`, `Run[DB]`, `DriverManager`, `getConnection`: 0 hits);
`Profiler.scala:281-295` names MySQL, SQL Server and Vertica but is a hand-run `object`
(`:37`). Every row below is MINED from `sql/SqlEmitter.scala` and `relational/SqlScanner.scala`.

`SqliteEmitter` mixes in 7 traits (`SqlEmitter.scala:676-683`), `MsSqlEmitter` 15
(`:834-849`); 5 are shared. Production is MSSQL.

### 9.1 Emitter gaps: SQLite could run these, the SQLite emitter does not emit them -- fixable

| Feature | SQLite emitter today | MSSQL emitter | Fix | Why it is an emitter gap |
|---|---|---|---|---|
| window functions (`Relation/Windowed.e:31`) | base `emitOver` splices `"TODO I don't yet know how to play %s over %s"` **into the SQL** (`:269-271`); `LOOP-MODEL-PLAN.md:249` (iii) calls it a silent wrong answer | `EmitOver_UsingOver` (`:538-558`), mixed in at `:843` only | `class SqliteEmitter ... with EmitOver_UsingOver` | `tracker/tools/tsql2sqlite.py:10-12`: SQLite "supports OVER(...) since 3.25" and E1 ran windowed reports on SQLite that way (*external* fact, recorded in-repo; sqlite-jdbc `3.51.1.0`, `build.sbt:113`, bundles a newer engine, *external*) |
| column names needing quoting | `emitColumnName(s) = s` (`:38`) | `[s]` (`:616-617`) | a bracket-name trait for the SQLite emitter (not `EmitName_MsSql`, which also renames temp tables to `##`, `:615-629`) | `tsql2sqlite.py:10`: "SQLite accepts [bracket] identifiers" |
| non-left-deep joins | `emitJoinOn` emits both operands bare (`:253-263`) | accepted | parenthesise the right operand | `LOOP-MODEL-PLAN.md:249` (iv): SQLite's flat join grammar rejects it |

`TestSqlEmitters` compares strings, so each mixin is pinned for free (WP-15).

### 9.2 Engine gaps: SQLite lacks the function -- refuse, do not splice

| Feature | SQLite path today | MSSQL | Failure mode today |
|---|---|---|---|
| `dateAdd` (`Relation/Op.e:144`) | `sys.error("todo - sqlite dateadd function")` (`:699-701`) | `dateadd` (`:877-879`) | a Scala exception, loud |
| `dateDiff` (`Op.e:160`) | `FunSqlExpr("datediff", ...)` for every dialect (`SqlScanner.scala:110`) | same text | SQLite has no `datediff` (*external*): SQL error at scan |
| `stddev` / `variance` (`Relation/Aggregate.e:29-30`) | `STDDEV_POP`/`STDDEV_SAMP`/`VAR_POP`/`VAR_SAMP` (`:328-348`) | `STDEVP`/`STDEV`/`VARP`/`VAR` (`:606-612`) | SQLite has none built in (*external*): SQL error |
| `tryCast` null-on-fail (`Op.e:65`) | `emitTryCast(true)` splices `"TODO I don't yet know how to write try_cast"` (`:276-278`) | `TRY_CAST(` (`:597-599`) | **silent wrong answer** |
| stored-procedure relations | `" exec "` (`:191`) | same | no procedures in SQLite (*external*) |

Mitigation: a typed `UnsupportedOnDialect(feature, dialect)` thrown by the base `emitOver`
(after 9.1 makes SQLite inherit `OVER`), `emitTryCast(true)`, the SQLite `emitDateAddName`,
and the `datediff`/stddev sites on emitters that lack them; `ermine/render` answers it as a
500 whose message names the feature and the dialect, and the panel shows it as a banner.
No emitter output ever contains `TODO` afterwards (WP-16).

### 9.3 Same query, different rows, no error either side (best-effort; stated in the badge)

| Construct | SQLite | MSSQL | Consequence |
|---|---|---|---|
| concatenation with NULL | `a \|\| b` (`:321`) | `Concat(a, b)` (`:573-575`) | `NULL` vs `''` (*external* engine semantics) |
| integer division of negatives | bare `/` (`:356`) | `floor(floor(a) / floor(b))` (`:631-635`) | truncation vs floor (*external*) |
| `GROUP BY` / `DISTINCT` on strings | engine default collation | server collation, commonly case-insensitive (*external*) | group counts differ; nothing in the emitter controls collation |
| `Date` literal | epoch milliseconds, `d.getTime.toString` (`:696`), column type `integer` (`:724`) | `'yyyy-MM-dd'` (`:199-201`, `:211`) | time-of-day survives on SQLite only |
| `Timestamp` | formatted string into an `integer` column (`:203-205`, `:725`) | `CAST('...' AS DATETIME2)` (`:860-862`) | unverified how SQLite stores it |
| nullability, string length | never `not null`; `text` without length (`:716-727`, `:717`) | `nn` appends ` not null` (`:864`); `nvarchar(<l>)`, `1000` when unspecified (`:866-867`) | the preview accepts what production rejects |

### 9.4 What this decides

For the widget/parameter surface the rows are inline and the preview is faithful in shape;
values differ only where 9.3 applies. For relation authoring the honest tool is an MSSQL
profile (§7). The status bar shows a **"preview dialect != deploy dialect"** badge whenever
the active profile's emitter differs from the `deploy: true` profile's (WP-16). The dual-emit
diff (render answering the SQL it ran via `dumpRel`, `SqlScanner.scala:281`, beside what the
deploy emitter would run via `dumpClosed`, `relational/Scanner.scala:44-45`) is
query-authoring tooling, not part of the loop: **optional, last** (WP-19).

## 10. Closed-environment constraints

| Constraint | Consequence |
|---|---|
| No internet in the loop | no CDN script in the webview; `client/node_modules/` is gitignored (`.gitignore:9`) and absent here, so `webpack`, `ts-loader` and their closure need a vendored copy or an internal registry |
| Driver artifact | `mssql-jdbc`, classifier `jre11` (§7.3), in the offline Ivy/Coursier cache before `sbt` resolves; `bin/ermine-lsp` rebuilds its classpath cache when `build.sbt` is newer (`bin/ermine-lsp:12-16`, same as `bin/ermine-serve:21-27`) |
| Every launcher is bash | **AMENDED 2026-09-24 BY WP-33: the CLIENT's toolchain no longer is** -- `npm run generate` / `npm run check-generated` are node (`client/scripts/generate.js`, `check-generated.js`) and launch java directly, not through `bin/ermine-schema`; what follows is WP-17's remaining scope. `bin/ermine`, `bin/ermine-lsp`, `bin/ermine-schema`, `bin/ermine-serve`; the default server path is `bin/ermine-lsp` under the first folder (`package.json:43-47`; `extension.js:49-55`). **Windows gets native `.cmd`/PowerShell wrappers** (`bin/ermine-lsp.cmd` at least, doing what `bin/ermine-lsp:12-74` does: the classpath cache, `-Dermine.lsp.log`, the heap cap of §2.2 -- `-Xmx` and `-XX:+ExitOnOutOfMemoryError`, `:20-63` since WP-5 stage C -- and `ERMINE_JAVA_OPTS`); `resolveServer` picks the wrapper when `process.platform === "win32"` (*external*). No WSL |
| Consequences of a Windows host | **AMENDED 2026-09-20: the `SecretStorage` half of this row FALLS AWAY -- the user dropped the secret store (§8's amendment), so there is nothing at rest for a host credential store to back, and the prompted password never leaves the extension host's memory.** What remains host-dependent: the JVM truststore is the Windows JDK's (`Windows-ROOT`, Q3, §7.3). Portability note, not a live question: on a Linux host `SecretStorage` is backed by the keyring (*external*) and the truststore by that JDK's `cacerts` |

## 11. Testing

`tracker/GATE-POLICY.md` is superseded (`:1-3`) by `docs/gate-policy.md`: tiers `commit`
(compile, corpus, lsp, **and since WP-10 S1 `extension`** -- `node --test editor/vscode/test/preview-core.test.js`, ~2 s, no `node_modules`, registered straight at commit by the orchestrator's U7 on its measured cost; **and since WP-32 S2 `generated`** -- `node client/scripts/check-fresh.js`, ~2 s, no JVM, needs `client/node_modules` for tsc; ~2.5 min, budget 3 min), `pr` (+ `suites` = full `core/test`, lean;
20 min), `nightly`; "a new gate enters at `nightly` and moves up on evidence"
(`docs/gate-policy.md:52-56`, `:87-92`); environment-dependent checks are instruments, not
gates (`:28-29`, `:98-101`). No gate below exceeds 20 min, so nothing needs the user's
approval under `:91`. Each WP done-when in §14 names its tier.

| Layer | Where | Properties (each is a WP done-when) | Tier | Cost per run |
|---|---|---|---|---|
| Wire / dispatcher | `TestLspRobustness` A-group | a deferred handler answering from another thread still yields "every message answered in order, once" -- the synchronous answers keep their positions and every deferred one is answered exactly once, in any order; two threads calling `send` concurrently produce frames a `Wire` reads back intact; a body for a redacted method never appears in the captured log, an unredacted one does, and neither a JSON array nor a non-string `method` logs a body either; a parse error quotes at most one character of the input or a number token, and no two-character upper-case window of the input appears in it (the marker check of §4), with the same claim re-checked through `Server.handle` on an unparseable frame carrying a secret; `$/cancelRequest` reaches a registered handler while other `$/` notifications are dropped with no answer and no `ignoring notification` line (they do get the ordinary `">>"` line, like every other incoming message) | `suites` (**pr**): `scalacheck-binding/src/main/scala` is in core's test sources (`build.sbt:88-90`) | seconds |
| Registration flag | group D in `TestLspRobustness` | check a buffer whose `data Heading` gained a field; `DataConDecl.forConstructor(Global("Sales", "Heading"))` still has four fields (since Q25, 2026-09-23, the fixture is `doc/SalesRaw.e` and the global `SalesRaw.Heading`: the typed `Sales.e` declares no `data Heading`) | **pr** | seconds |
| Render session | group D, under `residentLock` as B/C are (`:34`, `:307`), and -- since **ROBUST-3** (2026-09-20, `tracker/LSP-STALENESS.md`) -- under `ErmineFixture.literalLock` for the whole body of every property that RENDERS, through the `renderingD` wrapper | render `Sales.report`; mutate the report file; `invalidate`; render again: the document differs. Mutate a **widget** module the report imports: the report is in the invalidated set. Render a module whose evaluation throws: the resident still answers a check (`Resident.checkFile`, `Resident.scala:401`) and the next render works. A `$/cancelRequest` for a queued render answers `-32800` and the queue is empty. `ermine/schema {uri, binding: "report", roots}` from the queue equals `exportNamed("Sales", "Query")` under the render env, on the session the render before it booted. `ermine/preview/reports` on `Sales.e` lists `report : Query -> Node` and nothing else. **(Q4)** A report whose LOAD failed is a 500 "does not load"; the file is fixed; `invalidate` of its path sends `ermine/preview/invalidated` NAMING it and the next render is `{ok:true}` with the fixed content. **(Q5)** The 404 for a file that cannot be placed names the cause -- "cannot read Gone.e" for a file that is not there, "no module header could be read from WpBadHeader.e" for one whose header does not parse. **(Q6)** Two fresh reports in two DIFFERENT directories, both named as `roots` on every request, render first / second / first again, all `ok:true`, and the session boots exactly ONCE across the three (counted from `Preview`'s own "render session booted" log line; each of the three properties runs on a bench of ITS OWN, not the group's shared one, because these requests move the root set and the shared bench's must never move). A report under NO configured root still renders and DOES re-boot, which is §2.4's zero configuration unchanged. One module NAME under two configured roots: the PICKED file is the one rendered, whichever root it is in. **(Q7)** A schema asked FIRST, on a fresh bench, boots the session and answers the params schema of a workspace report (`$id`, `$ref`, the four properties, the three required), and the render that follows answers `ok` -- ONE boot across both, counted from `Preview`'s own log line. `ermine/schema` with a `binding` and NO `uri` is an `{error}` naming the key, while the `type` and `name` forms still answer `ermine:Ord/Ordering` from the resident. A pick SHADOWED by a resident `moduleRoots` entry (the bench is given one of its own, holding a copy of the same module name) is `{ok:false, status: 409}` with no document, naming the picked file, the shadowing file and the root; the schema answers `{error}` with the SAME text; and a non-shadowed module on that bench still renders its own contents with no second boot. A pick that reaches its root THROUGH A SYMLINK, while the resident root holds the real spelling, still renders its own contents -- the `sameFile` tolerance of the review's must-fix -- or SKIPS LOUDLY with a `collect` label where the platform refuses symbolic links. The 400/404 property also pins the two bad-`roots` SHAPES the first cut dropped silently: `roots` that is not an array, and an entry that is not a string, are each a 400 naming `roots` and what kind of value it was, and the same refusal reaches `ermine/schema` in its `{error}` shape (that property now holds `residentLock` and forces the bench's `docs`: its Q7 half asks `ermine/schema` over the WIRE, and the handler exists only once `Definitions.install` has run -- see the row's note below). **(Q8, decided 2026-09-20)** The watchdog property now also asserts `"stuck": true` on the fired answer and on a later REFUSED render, an `ermine/preview/stuck {stuck: true}` notification, and -- the conjunct that catches the shared-`refusal` bug -- that a render SERVED after the recovery whose evaluation crashes carries NO `stuck` key; the crash-handler property carries the same negative conjunct on its own 500; the watchdog-drain and cancelled-then-wedged properties assert the marker on the drained schema's `{error}` and its absence from the `-32800` (which has no `result` at all). **(Q10)** The watchdog property now releases the wedged job and waits for `ermine/preview/stuck {stuck: false}` and an INFO `window/showMessage` asking for a re-render, then proves the state really ended by getting a THIRD render SERVED; the cancelled-then-wedged property does the same after its -32800. A property OF ITS OWN pins the other side of Q10(b): a wedged job released by throwing an `OutOfMemoryError` leaves the preview stuck, logs no "no longer stuck", and announces nothing -- read off a recording `notify` and a log after the preview thread has been JOINED. **(Q9)** One property, no bench and no boot, over `applySettings`: `0` sets the field and logs once; `3601` and an ill-typed `timeoutSeconds` are each refused out loud and leave the field alone. **(DM-1, as corrected by DD-1)** A property of its own, and the only one in the group that pays TWO boots, because nothing cheaper is a real witness (`discardSession` on a preview that never booted does nothing and logs nothing). FOUR scenarios on ONE booted bench, in an order that keeps the boot count unambiguous: **(a) the CONTROL** -- a wedged render that comes back `ok: true` must NOT discard and must NOT re-boot, and its recovery message must not claim a discard; **(b) THE REACHABLE CASE** -- a wedged render of `WpBoom` comes back with a 500 **by returning normally** (`threw` is false), and the recovery must log the discard and say so in its message; **(c)** the next render then really does boot (`boots` 1 -> 2, counted from `Preview`'s own log line); **(d)** a wedge released by THROWING discards too, at no extra boot. (b) is what the first cut got wrong and what the throwing scenario alone could never have caught. **WHAT THE PROPERTY OBSERVES, stated because the name suggests more than it checks**: it observes the DISCARD firing -- `Preview`'s own log line, and the extra boot in (c) that proves the session really went -- and NOT a poisoned binding being re-thrown from a session that survived. The memoised `Bottom` of DM-1 is the REASON for the discard and is nowhere asserted here; a property that pinned it would have to render a second report that shares a thunk with the wedged one and watch it fail, which is a fixture this group does not have. **(DM-2)** The `isFatal` property runs its scenario TWICE, once released by an `OutOfMemoryError` and once by a `ControlThrowable` -- the second is not an `Error` and is exactly what `isInstanceOf[Error]` alone missed. **(IM-1)** A property STAGES the notification collision rather than racing for it: the bench's `notify` parks the TIMER thread inside the `{stuck:true}` send until the preview thread has sent `{stuck:false}`, asserts the arrival order really was `false, true` (or the property is vacuous), and then asserts that the HIGHEST `seq` says `stuck:false` | **pr**; group D boots a render session, seconds each, MEASURED in WP-5 and kept under 60 s total or the suite is split. **MEASURED with Q7's four properties (2026-09-20), three runs**: **18.2 s** for `core/testOnly ...TestLspRobustness` ALONE; **25.7 s** and **46.7 s** for two runs of the same tree with `TestRunner` and `TestSchema` in the same JVM. The spread is CONTENTION, not Q7. **THOSE Q7 FIGURES WERE WRONG AND ARE CORRECTED HERE (2026-09-20, against the run's own log)**: the sentence said "the four Q7 properties cost 7.4 s of it (shadowed pick 1.6 s, two spellings 5.8 s, schema-first and the missing-uri case the rest)", which cannot be read at all -- 1.6 + 5.8 is already 7.4, leaving nothing for "the rest". The log says **shadowed pick 1.6 s, two spellings 5.8 s, schema-first 3.4 s, the missing uri 0.0 s = 10.8 s**, not 7.4 s. Meanwhile one pre-existing property, `ermine/schema {binding}`, took 16.3 s in that run against a fraction of that alone -- it holds `residentLock` while the other two suites take the process-wide `Runner.evalLock`, which is where the spread comes from. **RE-MEASURED 2026-09-20 WITH THE Q8/Q9/Q10 PROPERTIES**, four runs: group D was **34.7 s** for `core/testOnly ...TestLspRobustness` ALONE (61 properties, 47 s of suite wall time; that figure PREDATES the `docs`-ordering fix above and the review's own properties), and **34.4 s**, **18.6 s**, **37.5 s** on three runs with `TestRunner` and `TestSchema` in the same JVM (128 properties, 79 s / 59 s / 66 s). The **18.6-37.5 s** spread across runs of the SAME tree is the contention this row already describes and nothing else. The five properties added across the batch and its review cost **5.7 s between them**: `watchdog, the stuck state and the recovery` 0.3 s, `Q10: isFatal keeps the stuck state` 0.3 s, `Q9: applySettings on timeoutSeconds` 0.0 s, `IM-1: the stuck notification's seq` 0.3 s -- none of those four boots a render session -- and **`DM-1: the poisoned session is discarded` 4.8 s, which is two boots and is the whole of the increase**. **RE-MEASURED AGAIN AFTER THE BATCH'S TWO REVIEWS (2026-09-20)**, which added the DD-1, DM-2 and IM-1 properties: **23.2 s** and **40.4 s** for `core/testOnly ...TestLspRobustness` ALONE on two runs (63 properties, 46 s and 56 s of suite wall time). The 17 s between those two runs is not the new properties -- `DD-1: the poisoned session is discarded` cost 4.9 s in both -- it is **the RESIDENT's own ~13 s boot landing on whichever property forces it first**, which in the 40.4 s run was the pre-existing `Q7: the missing uri, and the resident's forms` (16.4 s there, 0.0 s when something else has already paid it). That is the same scheduling effect this row describes above, now with a named instance. *The combined figure for the final tree -- with `TestRunner` and `TestSchema` in the same JVM -- is reported to the orchestrator and deliberately NOT written here: it can only be known after the run that must be the last thing to touch this tree, and a tracker edit after a green run would break that rule.* **The 45 s line is not crossed on any run, and THE SPLIT IS THEREFORE NOT TAKEN.** **THE MARGIN, stated so that the next batch knows what it is spending**: the highest group-D figure measured is 40.4 s, so there is about **5 s** to the 45 s line -- one property that boots a render session (DD-1 costs 4.9 s for its two boots) or one property that lands on the resident's own ~13 s boot is enough to cross it, and the second of those is a scheduling accident rather than a cost. It remains available if a later batch crosses it again: either group D moves to a suite class of its own, or it is cut into the queue/watchdog properties and the root-set ones (Q6 and Q7, each already on a bench of its own). **ONE PRE-EXISTING ORDERING HAZARD WAS SURFACED AND FIXED** while measuring this: the 400/404 property asks `ermine/schema` over the wire (Q7 gave it that conjunct) but never forced the bench's lazy `docs`, so a schedule that ran it before any property that does answered `-32601 unknown method: ermine/schema`; it now forces `docs` under `residentLock` like the three properties that already did. The 60 s ceiling in this row is not breached on any run. **THE GROUP-D LOCK RULE, ADDED BY ROBUST-3 (2026-09-20) AFTER A `pr` GATE RED** (tree key `cae6f47f42cc3a6cf0c99b0c46e61f1a1d4ff890`, `suites` FAIL, `Failed: Total 1284, Failed 2, Errors 0`, 863 s; the whole ticket is in `tracker/LSP-STALENESS.md`): the old convention -- *`literalLock` for properties whose VERDICT reads `Session.depCache`* -- was wrong by omission, because **EVERY RENDER AND EVERY SCHEMA READS THAT CACHE**. `Preview.placeAndSession` runs §2.5's mtime scan at the head of both (`lsp/Preview.scala:1339` -> `Runner.invalidateStale`, `json/Runner.scala:599`), and a foreign `Session.depCache.clear()` landing PART WAY THROUGH that walk yields a dirty set that is not closed under importers, which `Session.scrub` then turns into dangling names and a 500 inside a stdlib file (READ; the product half is WP-25 -- **BUILT, REVIEWED AND MERGED 2026-09-21 at `c73d4e7c`: see this section's "Session scrub (WP-25)" row, §14's WP-25 row and `tracker/WP-25-AS-BUILT.md`. THE OTHER HALF, WP-26's staleness, IS NOT BUILT**). **THE RULE NOW**: a group-D property that can reach `doRender` / `doSchema` / `doInvalidate` holds `literalLock` for its whole body via `renderingD`, which forces `bench` -- and, with `withResident = true`, `resident` -- BEFORE taking the lock, keeping `previewLock` -> `residentLock` -> `literalLock`; `Bench.bootMillis` takes it for the group's one warm-up render, the one render `renderingD` cannot wrap. **20 of the 30 group-D `timedD` properties are wrapped**; the 9 that are not never build a `Runner` (every job they post is held or thrown in `beforeJob`, or there is no job at all: the five watchdog / stuck properties, `Q9`, `the schema job at shutdown`, `daemon and shutdown`, and `Q7: the missing uri`, whose binding form is refused by `SchemaRequest.parse` on the dispatch thread and whose other two forms are answered by the resident), and `ermine/preview/reports` keeps `withDepCache`, which is strictly stronger. **RE-MEASURED ON THE FIXED TREE (2026-09-20), THREE RUNS**: group D **30.3 s** and **29.4 s** for `core/testOnly ...TestLspRobustness` ALONE (63 properties; the first invocation was 13 s of `core/Test/compile` plus **65 s** of `testOnly`, the second **83 s** of `testOnly` with nothing to compile), and **31.1 s** with the four CLEARING suites in the same JVM (`*TestLspRobustness *TestInterfaceRoundTrip *TestInterfaceKey *TestNamedFields *TestInterfaceConcreteRow`, 84 properties, 169 s) -- **all green; the three figures are within a second of each other, which is INFERRED (one mixed run against two solo runs) to mean the serialisation costs group D little -- a row that itself attributes an 18-40 s spread to contention cannot carry a one-second claim as MEASURED**. The boot is 2.3-2.9 s of it. The longest wrapped property, which is the BOUND ON HOW LONG THE FOUR CLEARING SUITES CAN BE HELD OFF, is `DD-1: the poisoned session is discarded` at **4.7-5.6 s** (it pays two render-session boots), then `Q6: zero configuration` 4.4-4.7 s. **THE RED RUN'S 23.7 s FOR `Q7: the shadowed pick` IS NOT THAT BOUND**: that figure is the resident's own ~13 s boot landing on whichever property forces it first -- the effect this row already names -- and `withResident` now forces it OUTSIDE the lock; the same property costs 1.9-2.7 s on these runs. **A GREEN RUN CANNOT PROVE A TIMING RACE FIXED**: the argument is the lock, by reading, and these runs only say the fix did not break anything and did not cost the cap | seconds to a minute |
| **Cooperative cancel (WP-6 stage 1) -- REMOVED 2026-09-20 (WP-24)** | `TestPreviewCancel.scala` -- **DELETED by WP-24**; while it existed it was a suite of its own, sharing group D's harness through `PreviewSupport` | **`TestPreviewCancel.scala` IS DELETED AND ITS TEN PROPERTIES NO LONGER RUN; the mechanism they covered is not in the tree. The row is kept as the record of what was tested, and the two things it left behind are KEPT: `PreviewSupport.scala` (the shared harness, which `TestLspRobustness` imports) and `TestLspRobustness`'s own one-line order-dependence fix. AS IT STOOD:** **`TestPreviewCancel`, a suite OF ITS OWN**, sharing group D's harness through the new package-private `PreviewSupport` (the `Bench`, `LogSink`, the temp-root and fixture helpers, `previewLock`, the resident and `residentLock`, and the small answer accessors, all MOVED there unchanged). It is a separate suite because group D is measured at 23-42 s against this table's 60 s cap and five more render-session properties would cross it; the lock order `previewLock` -> `residentLock` -> `literalLock` is `PreviewSupport`'s and holds across BOTH suites, which matters because `core/test` is unforked and parallel. TEN PROPERTIES. Five are `Runtime`-level and cost MILLISECONDS: a cancel armed for ANOTHER thread leaves this thread's forcing alone; a cancel armed for THIS thread throws `Cancelled` at the head of `swhnf` and the thunk is NOT memoised (forcing it again with the flag clear answers the real value, because the check fires before the thunk is entered at all); a cancel that unwinds a thunk ALREADY BEING FORCED leaves a WHITEHOLE, so re-forcing it on the same thread is a permanent "infinite loop detected" -- which is the evidence for the unconditional discard and for `isFatal`'s WP-6 exception; a `Cancelled` raised inside a `Prim` or a `Box` body ESCAPES rather than becoming a `Bottom` (the regression test for two of the five swallowing catches); and -- ADDED BY THE STAGE 1 REVIEW (DM-3) -- a `Bottom` whose body FORCES does not catch the cancel and hand it back as a value, reached through `Bottom.toString` because `thrown` is `private[ermine]`. **THE `IO.Unsafe.eval` AND FOREIGN-INVOKE ARMS REMAIN UNVERIFIED BY TEST, and the earlier reason given for that was wrong**: the review showed `IO.Unsafe.eval` IS reachable from a booted session -- `Prelude` re-exports `IO.Unsafe`, and `Field.e`'s `unsafePerformIO guid`, `IO.e`'s `trace` and `Random.e` all reach it. What is not cheap is a fixture that loops INSIDE that primitive's `try` rather than after it: the loop has to be forced by the FFI action itself (`trace (toString (spin n)) 1`, where `printLn` forces the non-terminating string inside `e.extract[FFI[_]].eval`), and getting those imports past the documented `Prelude`-plus-`Primitive` ambiguity is a typecheck gamble that was not taken inside this batch's run budget. The shape is written down here so the next batch can add it in minutes; both arms were fixed by the same one-line rule as `Prim.apply`, which IS covered. Five are render-session properties on their own benches: with the switch ON a looping report is CANCELLED (500 carrying "evaluation did not finish after" and "CANCELLED", NO `stuck` key, NO `ermine/preview/stuck` of either polarity, `wp5/ping` answered meanwhile, and the next render BOOTS -- the witness for the discard); a job held in `beforeJob`, which the cancel cannot reach, falls back to phase 2b's `{stuck: true}` and the flag is ALREADY CLEAR when the job resumes, so it completes normally and Q10's recovery runs with no discard; with the switch OFF the watchdog takes today's path and never arms the flag (its TEARDOWN arms the flag by hand, because with the switch off nothing else can stop the loop and it would hold the process-wide `Runner.evalLock` for the life of the JVM -- the property says so where it does it, and since I4 of the stage 1 review the teardown runs BEFORE the verdict is built AND again from the `finally`, so that an exception while building the verdict cannot leak the spinning thread); a `$/cancelRequest` in flight still answers `-32800`, never arms the flag, and does NOT discard; and a document holding a CYCLIC list (`repeat`) is cancelled too, which is the `Encode.spine` case that falsified the cheaper placement | **pr** | **MEASURED 2026-09-20, AS A RANGE AND NOT A NUMBER**, because the figure moves with what else is in the JVM: the stage 1 reviewer measured **18.0 / 21.2 / 21.2 s** for the suite alone on an idle box, and FIVE CONSECUTIVE runs in one sbt session after the review's fixes gave **20 / 19 / 18 / 17 / 19 s** (`Passed: Total 10, Failed 0, Errors 0, Passed 10` every time; the suite's own cumulative clock read 16.4-18.6 s). The five `Runtime` properties cost 0.0 s between them; the five bench properties are 1.9-6.9 s each and pay six render-session boots. **THE SUITE HOLDS `previewLock` FOR ITS WHOLE LENGTH** -- every property, including the `Runtime`-level ones, which must serialise because the cancel flag is ONE global reference -- so it SERIALISES AGAINST GROUP D: the two never overlap, and each one's wall time is added to, not hidden inside, the other's. Group D was 31.3-42.0 s across the same runs, inside its own 60 s cap and unchanged by the extraction. The combined figure for the final tree is reported to the orchestrator and deliberately NOT written here, for the reason the row below gives |
| Runner | `TestRunner` (`:112`, `:806` already runs properties concurrently over one runner) | `invalidate` of an unloaded path is a no-op; `invalidate` then `render` reloads the module (loaded-set delta); two report-typed bindings in one module render two documents; `new Runner(cfg)` with an explicit `run` loads no JDBC driver (`CountingRun`, `TestRunner.scala:77`); **(Q4)** a module whose LOAD FAILED renders 500 and is named by the next `invalidate` -- of its own path, of the path of a broken module it IMPORTS, and of a loaded healthy module's path -- while a file under no root and a directory still name nothing, and the fix renders 200 and takes it back out; a module that is pending and then LOADED as another module's dependency is pruned and NOT named; a pending module whose file is DELETED is named while the file is there and not after the retry's 404; WP-34 `(b3z)`: a `Node`/`Fetch Node` binding is a report with no parameters -- `Doc.SalesReport` renders with `{}`, with no params and with `null`, a key or a non-object is a 400 at `$.params`, `paramSchema` answers `{"parameters":false}`, and a zero-parameter `Fetch Node` renders; `(b3)`'s `report : Int` names the three report shapes | **pr** | seconds |
| **Session scrub (WP-25)** | **NEW SUITE, 2026-09-21: `scalacheck-binding/src/main/scala/TestScrub.scala`**, over TWO fixtures -- `Layout.Doc`'s closure (20 files, ~2 s) and `Prelude` + `Layout`, the **130 modules** `lsp.Resident.boot` loads (one ~13 s boot; the small fixture CANNOT hold the defect, having no re-export chain three deep). **NO PROPERTY'S VERDICT READS PROCESS-GLOBAL STATE**: both fixtures snapshot their own importer graph at boot rather than calling `Session.dependentsOf`, which reads the `Session.depCache` four other suites `clear()`. **THE LOCK RULE IS THE SUITE'S OWN**: it holds `ErmineFixture.literalLock` and **forces its fixtures BEFORE taking it** -- sbt runs one `Properties` object's properties in parallel, and the first cut, which took the lock inside the fixture's initializer and again in a property that forced it, deadlocked for seven minutes (`tracker/WP-25-AS-BUILT.md` §8) | **8 properties** (MEASURED: `Passed: Total 8, Failed 0, Errors 0`, `wp25-green3.log`). SMALL FIXTURE: any subset is safe to unload -- the four entity invariants, the passed set really left, **the returned set intersected with what was loaded is exactly what left**, **the greatest-ancestor walk is unchanged**, `gone` within `dependentsOf(s)`, the net removed nothing; the closure of a known module is exactly its re-exporters (`Control.Functor` gives `{Control.Alt, Control.Ap, Control.Functor, Control.Monad}`), which is what would catch a regression to the importer closure; ROBUST-3's thirty seeded subsets; scrubbing EVERY module leaves the builtins whole; reloading what scrub unloaded restores a fresh session (four sets, including ROBUST-3's `{Control.Functor, Maybe}`). BIG FIXTURE: **the resident's own session: any subset is still safe** (the reviewer's two named cases -- `{Native}` and its six-module subset -- plus 25 seeded subsets of 1-6 modules); **a read after a failed reload resolves what a whole session resolves** (scrub `{Native}`, reload NOTHING, read the witness -- **with its control asserted first**, the review's proposed witness having died on an unscrubbed session too); **the definition index's canonical keys survive a scrub** (0 moved keys and 0 split buckets for importer-closed sets and for a sample of `checkFile`-shaped single-module scrubs, and **exactly `{Prelude.head#, Prelude.tail#}`** for `{Native}` -- the one measured exception, pinned BY NAME; §14's WP-25 row says why no fix exists) | **pr** | **~24 s alone** (MEASURED, `wp25-green3.log`: `core/Test/compile` 7 s + `core/testOnly *TestScrub` 17 s), of which one ~13 s `Prelude` + `Layout` boot. **INSIDE THE `pr` GATE'S `suites` IT IS PART OF `Passed: Total 1292, Failed 0, Errors 0`, 675 s** (MEASURED on the merged tree, content key `3f07799de8b3ee6376c808c805dd84cbbfd3d427`; the previous green on this line was **1284** at key `e622dd10...`, so the delta is exactly these 8 properties) |
| Emitters | `TestSqlEmitters` | the SQLite string for a windowed relation contains `over (`; no emitter output contains `TODO`; `UnsupportedOnDialect` for `tryCast` on SQLite | **pr** | seconds |
| Classifier | new, with a fake driver | §8.3 | **pr** | seconds |
| End to end | `tracker/tools/lsp-client.py`, run by `tracker/tools/lsp-smoke.sh` (`scripts/gates.sh:115-120`) | `reports`, render, edit, `invalidated`, render: differs; the schema binding mode on `Sales` (domain is `Query`); **(Q7)** the same binding request in its new shape (`uri`, `binding`, `roots`), and one more check: the schema of a SECOND report asked BEFORE any render of it -- §6's first-pick order -- placed in the SAME temp root so Q6's rule keeps the gate to one render-session boot | `lsp` (**commit**). **Q7 RE-MEASURED 2026-09-20, one direct run each side, exactly as `gate_lsp` runs it** (`with_own_classpath` from `target/ermine-classpath`, restored byte-identically, sha256 checked): **640 checks in 46.7 s before, 641 checks in 47 s after** -- one request changed shape, one check added, and the gate is still a `commit` gate by the same rule. **BUILT AND MEASURED 2026-09-20 (WP-5 stage C)**: 628 checks in 44.5 s before, 640 checks in 46.7 s after -- one preview boot of 1.6 s and one cold check of the copied `Sales.e`. The rule "if the gate passes ~90 s it moves to `pr`" is NOT triggered, so the gate stays at `commit` and `scripts/gates.sh` is unchanged. Under `docs/gate-policy.md` §5 ("gates must catch their mutants ... whenever a gate's definition or scope changes"): the gate's DEFINITION (`gate_lsp`) and its `GATE_SCOPE` string are both unchanged -- checks were added INSIDE `lsp-client.py`, and the files they newly reach (`lsp/Preview.scala`, `lsp/Definitions.scala`) were already inside `$E/lsp/*.scala` -- so the declaration needs no edit, and the gate's catch surface can only grow (before this, no smoke request reached `Preview.scala` at all). The harness was NOT run here: its lanes check out HEAD and run HEAD's `tracker/tools`, so it must follow the commit. The command is `scripts/mutate-and-verify.sh --gates lsp --classes obo,swap,guard,mapord -n 1 --seed 2` | ~1 min |
| **Extension decisions** | `editor/vscode/test/preview-core.test.js` under `node --test`, over `src/preview-core.js`; no `node_modules`, no VS Code, no JVM | roots absolutisation and refusal; the generation discard; the stuck machine (§4's four rules, DD-2, the two random-sequence checks); both re-render rules; the three request builders carrying the same `roots`; the two settings payloads and `ermine.maxHeap`; both quick-pick lists; the status bar's text and its precedence. **SINCE WP-22 (2026-09-20) ALSO THE WEDGE GUARD**: `markKey`, the fingerprints, `guardReduce`'s whole lifecycle table, `stuckEventApplies` (pinned to agree with `stuckReduce` event for event), `shouldAutoRender`, `heldMessage`, the `held` status branch, and three properties -- an automatic `Running` re-render only with a clear mark, an explicit render never suppressed, a foreign mark never consulted. **AND, SINCE THE WP-22 REVIEW (2026-09-20)**: `rejectionMeansServerGone` (which rejection shapes mean the server went away, with the documented codes in a table test), `promptAnswerApplies` (the held question's answer belongs to the report it asked about), `markPickFor`, the SHA-256 fingerprints (a test asserts no part of the input appears in one), the `restored` effect, and M1's property -- a server death generated in BOTH orderings, with the pre-review code run as a mutant over the same sequences and caught. **AND, SINCE WP-22(c) / STAGE 2 (2026-09-21): THE RESTART TIMER** -- `restartGraceSetting` (the client-only setting, validated the way the two wire settings are), `restartReduce`'s whole event table (arm on the rising edge only; disarm on the recovery, on every clientState edge, on the setting going to 0 and on deactivate; fire only for the LIVE arm serial, only while stuck and Running, and never inside the 30 s floor), `restartArmedSeconds`, `restartNotice`, `stuckNotificationText`, the `killed-by-us` mark reason, and SEVEN more properties -- a fire only ever while stuck and Running for the live serial, NO fire with the setting at 0 (the default), every fire preceded by a mark for the pick it restarts, **after a fire the Stopped -> Running it causes never auto-renders** (the composition of stage 1 and stage 2, and the property that matters), the timer's stuck/running mirror pinned to `stuckReduce` event for event, and an end-to-end walk-through. **TWO MUTANTS OF OUR OWN, KILLED, WITH THREE MEASURED COUNTS (corrected after the review, which caught the arithmetic: two mutants, three counts, not "three mutants"): a fire with no mark (60 unmarked fires, 28 of which re-rendered the wedge) and a reducer that ignores the expiry's serial (145 restarts for incidents that were over); the real code scores 0 on each.** **AND SEVEN SOURCE MUTANTS MEASURED BY THE REVIEW (2026-09-21), on a copy of `src` + `test` outside the worktree, each run against the SHIPPED suite: the two above, plus "the accepted `{stuck:false}` no longer disarms", "the 30 s floor removed", "`killedByUs` overwrites a truer reason", "`Starting` no longer disarms" and "the `RESTART_GRACE_MAX` clamp removed" -- ALL SEVEN KILLED. **TWO GLUE MUTANTS SURVIVED AND CANNOT BE OTHERWISE**: removing `fireRestart`'s coalescer clear, and removing the restart guard. Neither is in any model -- they are editor glue, in the same class as the coalescing window and the tab -- and both are now in the UNOBSERVED list and in the manual checklist (review N4). **MEASURED 2026-09-20: 39 tests before WP-22, 58 at the first build, 66 after the review's must-fixes, **67 after the delta review** (`pass 67 fail 0`); MEASURED 2026-09-21: 83 at WP-22(c)'s first build, 88 after its review, 95 after the delta re-review, **96 after the final re-check** (`pass 96 fail 0`); **MEASURED 2026-09-21 (WP-8 S1): 166 (`pass 166 fail 0`), (WP-8 S2): 196 (`pass 196 fail 0`), after the S2 REVIEW's round: 210, and after its DELTA re-review: 216 (`pass 216 fail 0`)** -- the eight new ones are the ASYNC MODEL of `restart`/`startClient` (seven interleavings plus two mutants of the fix), the arm-time stretch reaching the number the user is told, the clockless-arm `bug` effect, the one-shot "we restarted it" token, the glue source pins, and the final re-check's own 2b scenario (a timed-out stop still reaches the guard's one consultation and holds).** **AND, SINCE WP-8 S2 (2026-09-21): THE PARAMS FILE'S SEND PATH** -- `paramsFolderFor` (the workspace folder that CONTAINS the report, innermost first, never `folders[0]`, win32 included), `meansFileMissing` (which read failures mean "no such file" and therefore `{}`, and which refuse), `mayStillSend` (the six ways the world can move during the read, in a most-specific-first order that is itself pinned), `paramsRefusalAnswer` (a refusal dressed as an answer, `status: null`, its reason under `paramsProblem` and not under the server's closed `reason`), `markParamsFor`, `paramsNoticeKey` / `paramsMissingNotice` and `relativeGlob`; **A SECOND ASYNC MODEL** -- `sendModel`, in `restartModel`'s style -- driving nine interleavings of `renderNow`'s send path by hand (the ordinary one; a pick change, a newer render, a restart, a roots change and the client going away during the read; a refusal; a refusal whose pick has moved; a missing file; a `null` file), plus the guard end to end (a params change clears the mark, a re-format and a moved `$schema` line do not, a save while `held` clears the hold) and the 400 path (no mark, no arm, the latch released); and a COALESCER model pinned to the real `COALESCE_MS` read out of the glue. **ACROSS THE THREE BUILD ROUNDS: 14 + 27 + 18 SOURCE MUTANTS RUN, ALL KILLED BUT ONE, PLUS 15 RUN BY THE FINAL RE-CHECK ITSELF (13 killed, 2 provably equivalent, each with its reason); ONE SURVIVOR IN TOTAL, NAMED** (on a copy of `src` + `test` outside the worktree, each run against the shipped suite; the first build's own fourteen are a subset and all still die): the gap check deleted, the gap check NEUTERED but kept (`if (false && ...)`), the guard not fed, the guard fed `lastParamsSent` instead of this render's params, both save triggers rendering directly, a refusal that still sends, the latch taken before the read, `folders[0]` instead of the containing folder, the delete watch dropped, the OUTERMOST nested folder winning, every read error read as "missing", the gap's order reversed, and `renderParams` coercing `null` back to `{}`. **FOUR DIE TO A MODEL TEST AND THE REST TO A SOURCE PIN**, which is that pin's measured limit, and **ONE PROSE-PRESERVING MUTANT SURVIVES AND CANNOT BE OTHERWISE**: `installParamsWatcher` returning before it registers anything -- the watcher's REGISTRATION is editor glue in no model, exactly like WP-22(c)'s two survivors, and `tracker/WP-7-MANUAL-CHECKLIST.md` §2.35 is the only thing that can see it. **AND SINCE THE REVIEW'S ROUND**: the snapshot `core.renderAttempt`, `core.previewNow` and `core.renderRequest` (M1/M2), the `stopCount` arm (M5), the extended trigger vocabulary and the SECOND place WP-22's one consultation is reached from (M6), `paramsTooLargeToRead` / `paramsReadTimedOut`, `lastServerAnswer`, and the model-fidelity rule now written into the test file's own header. **AND SINCE THE DELTA RE-REVIEW**: the membership rule for `UNCONFIRMED_TRIGGERS` asserted rather than stated (a trigger stays out only if its guard event clears whenever it schedules), the closed `RENDER_TRIGGERS` with `triggerProblem` naming anything else, `markMintedAfter` / `mayAutoRender` (a render whose mark is newer than its own trigger), and `heldPromptToken` / `shouldAskHeld` (a refused question remembered per mark and per params, for `params-file` only). **THE EXHAUSTIVE EXPLORER IS AN INSTRUMENT, NOT A GATE** -- `scratchpad/wp8-s2/explore-after.js`, 579,194 sequences over the real reducers in the glue's order, 5,097 violations before this round and 0 after, with its oracle re-checked by undoing each fix (1,218 and 2,466). It is recorded here because re-running it is how anyone would check a change to the trigger vocabulary. **AND SINCE WP-8 S3 (2026-09-21): THE FIRST PICK THAT WRITES** -- MEASURED **249 (`pass 249 fail 0`)**, 33 new: `isoDay` (the machine's own day, not a UTC slice), `schemaOrder` (G15, per case, with `fileMissing` a STRICT `true`), `shouldRefreshSchema` + `SCHEMA_REFRESH_TRIGGERS` (D8's answer AND its trigger, fail-closed on an undeclared one), `schemaAnswerOutcome` / `schemaRequestFailure` (the four named failures, none of which blocks a render), `mayUseSchemaAnswer` (D7, with a test that shows `mayStillSend` ALONE does not notice a module rename, which is why both are asked), `schemaFileNeedsWrite`, `paramsWritePlan` (the order, the per-file modes, the non-object root, the refusals, idempotence), two PROPERTIES over the same generated schemas S1 uses (every plan puts the params file LAST and `ifAbsent` and inside the folder; the written skeleton validates against the written schema FILE), and a **THIRD ASYNC MODEL** -- `firstPickModel` over a model disk -- driving the whole first-pick sequence by hand: the ordinary one (three files, the document opened, ONE render from the watcher), a pick change, a MODULE rename, a restart, a stop, a teardown, a newer render, a roots change IN PLACE, a params file APPEARING during the schema request, a read-only workspace, an editor that creates the file without its contents, every schema failure, a failed attempt not retried per render, two first picks in quick succession, and a HELD report never handed a schema request -- plus five mutants as options on that same model. **33 SOURCE MUTANTS RUN ON A COPY, 33 KILLED, 0 SURVIVORS, EIGHT OF THEM REVERSE** (`scratchpad/wp8-s3/mutate.py`); five survived the first round, each exposing a weak pin -- including the params write swapped for `workspace.fs.writeFile`, which destroys committed source, and a pin whose `indexOf` comparison passed on `-1` -- and all five pins were strengthened. **AND SINCE THE S3 REVIEW (2026-09-21/23): 249 -> 261**, twelve more covering the five must-fixes and the nits that are testable here -- `preparedParams` (every outcome carries `paths`, and a kind nothing declares FAILS CLOSED), the other four glue-shape builders, `writeStep` (an unknown mode is a named refusal; the params file is refused by any route but the create, by `what` AND by path), `writeTargetPaths` / `writeTargetProblem` (the components outermost first, the `SymbolicLink` bit as a MASK, the workspace folder itself deliberately excluded), the symlink async scenarios over a model disk that can now HOLD symlinks, M-5's zero-bytes-not-whitespace rule, N-3's empty-params scenario as a mutant pair, N-4 asserted rather than assumed, N-5's gitignore-is-a-convenience and its other half, and N-6's abandon-before-write. **ROUND 2 MUTANTS: 42 RUN ON A COPY, 42 KILLED, 0 SURVIVORS**, built to include the NEUTERED-GUARD class the round-1 set did not reach -- a statement commented out, a guard kept as `if (false && ...)`, a helper called and its answer discarded, a builder bypassed, a bitmask compared for equality. **THE EXPLORER**: the review's `explore-s3.js` answers 0/0/0 at depth 5 (177,155) and depth 6 (1,948,716); the implementer's extended alphabet, which adds the S2 watcher's own `onDidCreate` as a 15th event, answers 0/0/0 at 271,452 and **3,257,436**. **AND SINCE THE DELTA RE-REVIEW (2026-09-23): 261 -> 266**, five more for D-1 (every schema failure reaches its own notice and LEAVES THE SCHEMA FILE ALONE, driven end to end through a model `refreshSchemaFile`; the first-pick half; and that a write of the literal text `undefined` is unreachable by construction), D-2 (a path that exists but cannot be stat'd refuses) and N-c (a link to a directory is 66, and the bit is what is tested). **MUTANTS ROUND 3: 55 RUN, 55 KILLED, 0 SURVIVORS.** **AND SINCE WP-8 S4 (2026-09-23): THE EDGES** -- MEASURED **303 (`pass 303 fail 0`)**, 37 new (**AND THE S4 FIX ROUND, 2026-09-23: 313 after round 2, `pass 313 fail 0`, 10 new -- the M-1 row the table never had, the shared notice/open/orphan-plan builders through both models, the TOCTOU decision as a table + model + MUTANT, M-3's hold across every failing path + MUTANT, the win32 fold; see §6's "S4 review and fix round"**): `writeStep`'s third argument (the overwrite PERMISSION is the caller's, not the mode's -- every pre-S4 call site passes two arguments, so the automatic path can never reach it), `skeletonCommandPlan` (the same plan with ONE mode moved, byte-identical otherwise, with a STRICT `replace === true`), `skeletonCommandVerdict` / `skeletonConfirmation` / `skeletonConfirmed` / `skeletonStillApplies` (only the exact string `Replace` consents; a header edit during the modal abandons where `markKey` would not have noticed -- asserted as the gap it closes), `paramsRootShape` and `rootShapeSentence` over the FIVE REAL captured non-object roots plus every string builtin, `directoryListing` (three arms, all keys always present, fail-CLOSED on anything else) and `orphanParamsFiles` (the listing shapes: none, matching, one stale, several, a stale module DIRECTORY, a symlink, an unreadable directory, a `reports` that is absent, not an array, or EMPTY -- each of the last three calling NOTHING stale), plus a FOURTH ASYNC MODEL, `commandModel`, driving U3's command by hand through the widest await this extension has: the ordinary run, a decline in five spellings, no file at all, a params file that APPEARS during the schema request, a pick change and a HEADER EDIT while the modal is on screen, a restart DURING the modal (fine) and during the schema (abandons), every schema failure, a read-only workspace, a symlink, and a HELD report (which runs and clears the mark) -- and the orphan scan end to end over a model `readDirectory`. **41 SOURCE MUTANTS ON A COPY, ROUND 1: 38 killed, 2 survivors; ROUND 2 AFTER TWO STRENGTHENED PINS: 41 run, 41 KILLED, 0 SURVIVORS** (`scratchpad/wp8-s4/mutate.py`, `round1.log`, `round2.log`), eight of them REVERSE and three in the dangerous direction (the automatic path given the permission; the permission dropped; a dismissed notification running the command). **THE TWO ROUND-1 SURVIVORS WERE BOTH THE NEUTERED-GUARD CLASS**: `if (existing !== null)` around the whole modal turned into `if (false)` -- the command then overwrote committed source with NO question and 303 tests stayed green -- and `openParamsDocument`'s own `&& always !== true` dropped at the definition while the call site stayed as the pin reads it. **AND S4 FOUND A LIVE TRAP IN `codeOf` ITSELF**, the comment stripper every statement pin reads through: it did not know what a STRING is, and `findFiles("**/*.e")` opens a block comment -- unclosed and therefore harmless by LUCK until S4 added a JSDoc whose `*/` closed it, at which point 124 lines of `pickReport`, `renderCommand` and `activate` vanished from what every pin reads (MEASURED: the picker's trigger pin failed with its source line untouched). It is a scanner now, with its own table test and its own two mutants. `node test/load-test.js` (which activates the extension against a real `bin/ermine-lsp`) is unchanged and green -- re-run at stage 2, `PASS`, live step `129 modules in 14.3s`, and at WP-8 S3, `PASS`, `129 modules in 14.3s`; WP-34: the `{"parameters": false}` marker read as "no parameters" and only the exact marker, the held "no params file" line (`holdsParamsNotice`), the zero-parameter first pick / D8 refresh / Write Params Skeleton writing nothing (the S3 and S4 models carry the glue's arms, with mutants), and the `glue pins (WP-34)` source pin | **nightly** (§11's own rule: no new gate; `scripts/gates.sh` is unchanged) | ~0.15 s, plus ~15 s for the load test |
| **The generators in `preview-core.test.js`, as a FINDING** | measured by the WP-22 review, 2026-09-20, and by WP-22's own build | **THE LCG THE TWO WP-7 GENERATORS USE IS BADLY SKEWED**: `seed = (seed * 1103515245 + 12345) & 0x7fffffff` overflows 2^53, so its low bits are destroyed. MEASURED: `% 2` gives **1992 zeros in 2000 draws** (seed 20260920; WP-22's own note says 1994/6 from another seed -- same substance), and `% 4` and `% 8` are identical; `% 3`, `% 7` and `% 9` are uniform, which is why the two tests still pass. CONSEQUENCES, both measured by the review: `test:294` ("every generated message sequence leaves the state consistent") draws only **24 `{stuck:false}` notifications out of 4074**, so §4's falling edge -- the path the wedge guard's clear rides on -- is 0.2 % of the run; and `test:356` ("the final state is the highest-seq notification's") has its oracle decided by a `{stuck:false}` **exactly once in 400 runs**, so a mutant that ignores the `stuck` field fails 1 of 400 -- one draw from vacuous. Neither test is vacuous today and neither was touched (WP-22 left them exactly as they are and used a 32-bit xorshift for its own generators). **THE TICKET IS WP-27, NOT BUILT** | -- (a finding, not a gate) | -- |
| Host page | `client` `npm test` (the existing harness plus the `applyMessage` reducer, §5) | every message sequence the extension can send leaves a consistent state (no document and a banner, or a document and its dimming flag). **AS OF WP-9 (2026-09-21) THIS EXISTS AS A TEST**: `(h-prop-consistent)` in `client/test/host.test.ts`, whose clause (7) is literally "no document and a banner" (`document === null` implies `banner !== null`) and whose clauses (5) and (6) are "a document and its dimming flag" (`showDocument` iff there is a document; nothing dimmed that is not on screen). 19 cases in that file, 90 tests in the suite (from 65) | **new `gate_client` in `scripts/gates.sh`, entering at nightly per policy; promotion after one recorded catch -- STILL DOES NOT EXIST (MEASURED, 2026-09-21): until WP-10 registers it the property runs under `npm test` and GATES NOTHING** | seconds |
| **Panel protocol (WP-10 S1, 2026-09-23)** | `editor/vscode/test/preview-core.test.js`, 20 new `panel (...)` tests over `core.panelMessagesFor` / `panelView` / `panelAnswerStep` / `unsavedNames` / `panelTarget` / `buildPreviewHtml` / `previewCsp`; gated by **`gate_extension` (commit)** | the CSP character for character, and no nonce / `blob:` / `font-src` / `connect-src`; a hostile `cspSource` refused; script order writers -> client -> host, classic, stamped, **zero inline `<script>` bodies**; every URI HTML-escaped; the CSS links optional, ordered, at most three; each of the nine kinds produced by a view from the SHARED builder (table); every latch sent on BOTH edges in the order the reducer needs; `held` carries no action; a displaced render (`-32800`, both shapes) changes nothing BY IDENTITY; an answer behind the generation is discarded; an error keeps the last good document; `stale` from the answer's own key and after the answer pair; W5's fast-mode suffix; `stuck` from the ARBITRATED state only (rule (3) both arms, on a REAL captured `stuck:true` answer); H6 (`held` survives a bare Stopped -> Running, lowered by the guard's own `{stuck:false}` clear, never spoken for another pick); `switching` not wired; **14 REAL answers captured from one `bin/ermine-lsp` boot** (`test/fixtures/panel-answers.json`: ok x4, 400 x2, 404 runner + placement, 500 encode, stuck:true x4, the server's own -32800) each mapped to its stream; a 3000-view explorer on the xorshift (WP-27's LCG avoided) | **commit** | ~2 s for the whole file (333 tests) |
| **Panel page fold (WP-10 S1, 2026-09-23)** | `client/test/page.test.ts` (10 tests) over `client/src/host/page.ts`, under `client` `npm test`; **gated since WP-10 S3 by `gate_client` (nightly)** | the arbitrary draws all nine kinds; **H7: a snapshot's fold equals the same messages received one by one** (1000 runs); a snapshot REPLACES any prior state (1000); `receive` is pure; a malformed snapshot returns the state BY IDENTITY and `snapshot` is not a tenth reducer kind; `page.ts` re-exports the reducer's whole surface (so S2 can move the `ermine-host` entry to it); **`(pg-h7-incremental)`: over generated EXTENSION histories driven through the REAL `preview-core.js` reducers, posting each view's messages one by one equals the snapshot of the last view** (1500); `(pg-h7-drops)`: a panel that missed any subset of posts is restored exactly by the next snapshot (1500); `(pg-h7-abandoned-reload)`: the one divergence S1 found, pinned; `(pg-h7-real)`: captured answers drawn through the real reducer as the banner they should be | nightly once `gate_client` exists (S3) | ~2 s after `tsc` |
| **Panel glue (WP-10 S2, 2026-09-23)** | `editor/vscode/test/preview-core.test.js`: `panel S2 (...)` tests (envelope, inbound, route, bundle check, notice page, roots), `panelGlueModel` driven through the design review's H3 (ready after / before the first answer), H7 (hidden drops, visible resyncs), H1 (close and teardown mid-render), H2 (an answer overtaken by a newer render posts nothing, settled out of order), H9 (two commands, one panel), the latch, the three targets, the Restart intent, the absent / half-built bundle, a pick change and a 250-run explorer, with a model mutant beside each hazard; seven `glue pins (WP-10 S2) ...` tests reading `extension.js`; gated by **`gate_extension` (commit)** | no post before `ready`, none after dispose, one live panel, the page ends on the truth; ONE `createWebviewPanel`, ONE guarded `postMessage` of `core.panelSnapshot`'s envelope, the latch consumed once, `showAnswer`'s text unchanged (sha256), Restart through `executeCommand("ermine.restartServer")`. **Not observable here**: anything VS Code does |
| **Panel page (WP-10 S2, 2026-09-23)** | `client/test/page.test.ts` `(pg-step-*)`, `(pg-key)`, `(pg-boot-*)` (the REAL `boot` in a JSDOM) and `client/test/bundle.test.ts` `(b-host-boot)` (the BUILT bundle); under `client` `npm test`; **gated since WP-10 S3 by `gate_client` (nightly); `(b-host-boot)` only where the bundle is built** | re-render exactly when the document key changes (500 runs over envelopes built by the extension's own builders); toggles never re-render; an older `seq` and every loose message ignored; `ready` once, after DOMContentLoaded; the banner, dimming and the one button from `presentation()`; no `window.ErmineClient` is a drawn, logged error |
| **Bundle watcher + fetch stub (WP-10 S3, 2026-09-23)** | `editor/vscode/test/preview-core.test.js`: `panel S3 (step)` / `(reload line)` over `core.bundleWatchStep` / `bundleWatchEvent` / `bundleReloading` / `bundleReloadLine`; `panelGlueModel` extended with the watcher, a virtual clock and a fake file system, driven through `panel S3 watcher (one build)` (a four-file webpack write: ONE announcement, ONE reload after the quiet period), `(two builds)` (apart: two; inside the window: one), `H4 (vanish/appear)`, `H4 (W10 first experience)`, `H4 (reload mid-render)`, `(lifetime)`, a 200-run explorer, and model mutants (no debounce = four reloads; delete arm dropped; notice never left; reload without an html reset; watcher not disposed); `panel S3 (csp)` (no `connect-src` in either page, the notice CSP or either source file); three `glue pins (WP-10 S3) ...` tests; `gate_client (WP-10 S3)` runs the gate function over a stub `npm`; gated by **`gate_extension` (commit)**. `client/test/page.test.ts` `(pg-fetch-refuses)`, `(pg-fetch-deferred-box)` (the REAL client renders a deferred `table`: its own error box, one log line, zero `fetch`/`XMLHttpRequest`) and `(pg-boot-listener-first)` (R23); under **`gate_client` (nightly)** | one reload per build, only after a quiet period, only with a panel; the page follows the bundle away and back; nothing lost across a reload; `connect-src` never appears. **Not observable here**: whether VS Code reports the events (above all for a folder that did not exist), webpack's write timing | commit (extension) / nightly (client) | the extension file ~3 s; the client suite ~15 s after `tsc` |
| **`gate_client` (WP-10 S3, 2026-09-23)** | `scripts/gates.sh` `gate_client`, **nightly**, timeout 1200 s: `npm test` in `client/` (tsc, then `node --test dist/test/*.test.js`); never builds the bundle | UNAVAILABLE (exit 3) with no `npm` or no `client/node_modules`; FAIL (1) on any failing test or when no counts were printed (tsc failed); PASS (0) when `pass + skipped == tests` -- the 3 sbt-fixture skips (and the 5 bundle skips where `dist/browser` is absent) are counted, not failed; one `SUMMARY <t> tests, <p> pass, <f> fail, <s> skipped` line | nightly (enters there per `docs/gate-policy.md`) | ~15 s |
| **The writers in the panel (WP-11 = WP-10 S4, 2026-09-23)** | `editor/vscode/test/preview-core.test.js`: `panel S4 (html)` x3, `(csp)`, `(writersState)`, `(check)`, `(dir)`, `(roots)`, `(banner)`, `(recheck)` over the pure core; `panel S4 model (missing)`, `(present / half)`, `(fixed)`, `(still missing)`, `(bundle rebuild)`, `MUTANTS` over `panelGlueModel`; `glue pins (WP-11) the writers`; `model = glue (WP-11)` (the model's view fields read out of this test file and compared with `panelViewNow`'s); `client/test/page.test.ts` `(pg-writers-global)` (REAL client, JSDOM, stub writers listener); `test/load-test.js` (the setting and its default) | writers -> client -> host, the three sheets, escaping, the exact CSP; fail-closed on `htmlwriter.js`; the setting through the roots' absolutiser; at most two resource roots; the banner as `error`; re-check on a command / a rebuild, no reload when nothing changed; the host posts `ready` after the writers' listener and reads the global at render time | commit (`gate_extension`) + nightly (`gate_client`). **Whether the real writers bundle runs in a webview is the playtest's (E3, E9-E11), not a test's** |
| **zod generator (WP-32 S1, 2026-09-23)** | `scalacheck-binding/src/main/scala/TestSchema.scala`: `(e2)` rewritten, `(e3)`, `(e4)`, `(w1)`, `(w2)` new; `(gate)`'s `UserTree.zod.ts` fixture regenerated (the only fixture with a recursive type) | **(e2)** a recursive type is DECLARED (`export type Test_Tr = | .. | ..`) and its const annotated `z.ZodType<Test_Tr>`, no `ZodTypeAny`, no `z.infer` of it; **(e3)** a recursive record is an `interface` (a `Maybe` field is `k?:`), a mutually recursive pair are both declared and annotated, a non-recursive def keeps `z.infer`; **since WP-32 S3** also a 3-cycle `Ca -> Cb -> Cc -> Ca` reached from `Ba` (recursive only through the cycle, not a member): all three members declared + annotated `z.ZodType<X>`, `Ba` and the root keep `z.infer` -- the S1 review's Tarjan tree-edge mutant M13 (`low(v) min index(w)` on a tree edge) splits `{Ca}` off `{Cb, Cc}` there, so `Ca` loses its declaration (REASONED, and replayed on a Python replica of `Zod.plan`'s Tarjan: `scratch-widget-preview/wp32-s3/mut/tarjan-replica.py`; not run against a mutated Zod.scala); **(e4)** `SchemaMain.generate` over two roots sharing a def emits it ONCE, with short names (`Sh`, `ShSchema`), an `=Alias` (`Bee`) replacing the def's own short name, the command line in the header, and an unknown `Module:Type` refused by name; **(w1)** the scan over the REAL `Layout.Widgets` finds exactly the pinned 13 names (12 registry keys + `treeMap`) at their props types, the `WidgetRegistry` block is byte-pinned, `CellFormat` is emitted once, and the header's `sha256` of `Layout/Doc.e` and every scanned module equals the sha256 of the classpath bytes; **(w2)** one name at two props types is refused with a message naming both terms. MEASURED: `-f \((e|e2|e3|e4|w1|w2)\)` PASS 6/6 in 9 s; `(gate)` PASS 1/1 in 8 s. Out-of-band (not gates): `tsc --noEmit --strict` over the generated module with the client's tsconfig and zod 3.23.8, and the props.ts assignability script (`scratch-widget-preview/wp32-s1/`) | **commit** (inside `suites`/TestSchema, as the suite already is) | ~17 s for the six + gate |
| **Typed registry + generated-file checks (WP-32 S2, 2026-09-23)** | `client/scripts/check-fresh.js`, run by **`gate_generated` (commit, 120 s)** and as the first step of **`gate_client` (nightly)**; `client/test/generated.test.ts` (7 tests) and `(w-generated-only)` in `client/test/widgets.test.ts`, under `client` `npm test`; `gate_client`'s stub test in `editor/vscode/test/preview-core.test.js` | **check-fresh**: (a) every `// sha256` line of `client/src/generated/widgets.ts`'s header recomputed over `core/src/main/resources/modules`, and every `.e` under `Layout/Widgets/` must be listed; (b) the `// generator sha256` lines `generate.sh` writes for `json/{Schema,SchemaMain,Zod}.scala` recomputed; (b2, S2 review M-1) the `// body sha256:` line `generate.sh` writes, recomputed over everything below it, so a HAND EDIT of the generated text fails (`TextProps` `.strict()` -> `.passthrough()` passed (a)-(c) and tsc before it); (c) every `export const X: z.ZodType<X> = E;` declaration assignable BOTH ways to zod's one-step inference AND identical to it (tsc) -- the identity half added after S2's mutant M4c (an extra OPTIONAL key in `Layout_Doc_Tab` passes mutual assignability). **Tests**: `(g-tsc)` tsc refuses a registry with a name not in `WidgetRegistry` (TS2353), a renderer for the wrong props type (TS2322) and a missing name (TS2741), against a control that compiles; `(g-no-name-lists)` no `src`/`test` file has an array literal of 3+ widget names; `(g-wire)` relation.ts's types equal the generated relation arms (runtime + mutual assignability); `(g-condition)`/`(g-adapters)` the hand-written switches cover every generated arm (typed samples: a new arm is a tsc error); `(w-generated-only)` registry keys === `WIDGET_PROP_SCHEMAS` keys at runtime. Reverse mutants (`scratch-widget-preview/wp32-s2/mut/`): hash edited, generator hash edited, widget module dropped from the header, arm added, key made optional, optional key added -> check-fresh FAILS; registry entry removed / wrong renderer -> tsc FAILS; corpus list hard-coded -> `(g-no-name-lists)` FAILS; `.passthrough()` hand edit -> check-fresh FAILS (`EDITED: the generated body does not match its // body sha256`); `props as never` or `registry[key] as Widget<any>` re-added in `dispatch` -> COMPILES: **KNOWN GAP, a lint that no gate or test runs** (review N-2). `(g-wire)` checks relation.ts against the generated arms by MUTUAL ASSIGNABILITY only, which misses an extra optional key (the blind spot check-fresh closed with its identity check); **NOTED, not fixed** (review N-4). `(g-tsc)` pins diagnostic codes plus the offending key, not message text (N-1); `(d-prototype-names)`: `constructor`/`toString`/`__proto__` get the registry's box (own-property lookups on both the schema map and the registry, N-3) | **commit** (`generated`) / **nightly** (`client`) | ~2 s check-fresh; ~3 s `(g-tsc)` |
| **Missing-schema message (WP-32 S3, 2026-09-23)** | `client/test/dispatcher.test.ts` `(d-no-schema)`, under `client` `npm test` | a registry a JS caller built with a key the generator never found (`gauge`) gets exactly "no props schema was generated for it -- declare `xName : WidgetName (XProps r)` in a Layout.Widgets module and run client/scripts/generate.sh" (the old text, "add it to client/scripts/generate.sh", pointed at a list that S2 deleted, and nothing pinned it). Reverse mutant (a copy, `scratch-widget-preview/wp32-s3/mut/`): the message reworded -> `(d-no-schema)` FAILS, 13/14 in dispatcher.test.js | **nightly** (`client`) | ms |
| Instruments | results written into this document, never gate evidence | the credential gate (§8.4); the `##` count (`tempdb.sys.tables`) after an hour and after Disconnect; RSS and boot seconds before/after preview boot (§2.2); heap after a watchdog fire (§2.5); the bundle checklist (§5); **WP-6 STAGE 2's EVALUATOR A/B: BUILT AS `tracker/tools/eval-bench.sh` AND RUN 2026-09-20; the figures, the deviations and what each number is a number OF are in the section below** | none | human / machine-dependent |

**THE MECHANISM THIS INSTRUMENT MEASURED IS NO LONGER IN THE TREE** (WP-24, 2026-09-20: stage 1
was removed by the user's decision, §13's Q13). **THE FIGURES BELOW STAY, UNCHANGED, AS THE
RECORD OF WHAT IT COST WHILE IT WAS THERE**, and so does `tracker/tools/eval-bench.sh`. Nothing
here is withdrawn and nothing here is strengthened: what this instrument supports is the
sentence it ends in and no more -- *"The instrument suggests a cost of roughly 5% on the
swhnf-densest workload; it does not establish one."* Its A side, `0a092242`, is once again the
content of the four files stage 1 changed. **The figures are NOT the reason WP-6 was removed;
the reason is the design (§13, Q13).**

**WP-6 STAGE 2: THE PERF INSTRUMENT, AS DESIGNED AND AS BUILT.** §2.5's WP-6 row used to
name `perf-bench.sh` for this. **`perf-bench.sh` CANNOT ANSWER IT**: it is a TYPECHECKER bench,
and what WP-6 adds is one volatile load and one branch at the head of `Runtime.swhnf` -- the
EVALUATOR's hottest function, which a typechecker bench barely enters. It would report "no
movement" whatever the cost was. The instrument stage 2 runs instead:

| Item | Decision |
|---|---|
| Where | a new `tracker/tools/eval-bench.sh`, hand-rolled; nothing existing measures evaluation |
| The workload | ONE JVM per fork, boot the session ONCE, then a pure fold dominated by `swhnf` (no IO, no scan, no printing) |
| The repetitions | K = 15 per fork; the first 5 DISCARDED as warm-up; the median of the last 10 is the fork's figure |
| The heap | fixed `-Xmx` on both sides, so a GC difference cannot be read as a cost |
| The forks | 5 per side, INTERLEAVED AT FORK LEVEL -- A, B, A, B, ... -- so a machine that drifts during the run drifts through both sides |
| The noise floor | **an A-vs-A pair FIRST**, same tree both sides, to MEASURE what "no movement" looks like on the day. Without it the decision rule has no scale |
| The decision rule | no movement iff `abs(median(B) - median(A)) <= max(the A-vs-A spread, 2% of median(A))` |
| A and B | **A = a clean build of `0a092242`'s tree** (WP-7's tip, the last commit before stage 1) and **B = the stage 1 tree**, in two worktrees, so neither side is an incremental build of the other |
| The cost | an estimated 20-30 minutes during which **the user's editor must be closed**: an LSP server on the same box is a second JVM competing for cores |

**FOUR CONDITIONS THE STAGE 1 REVIEW ADDED, each of which the run is invalid without:**

1. **STATE THE `swhnf` CALL COUNT PER ITERATION AND REPORT A DERIVED PER-CALL COST.** What WP-6
   adds is one volatile load and one branch PER FORCE, so a whole-workload delta is
   uninterpretable on its own: a 1% move over 10^9 forces and over 10^6 forces are different
   findings. Count the calls (a counting build, or derive it from the fold's shape) and divide.
2. **DEFINE "the A-vs-A spread" BEFORE THE RUN, and say which statistic it is** -- e.g. the
   range of the five A-fork medians, or their interquartile range. A decision rule whose
   threshold is named only after the numbers are in is not a rule.
3. **THE BENCH DRIVER MUST BE BYTE-IDENTICAL ON BOTH SIDES.** A and B differ by one change to
   `Runtime.scala`; if the harness is also rebuilt or edited between sides, the comparison
   measures two changes. Either the driver is copied unchanged into both worktrees (checked by
   sha256) or it is an Ermine script run through `bin/ermine`, where the driver is the same
   binary on both sides.
4. **EACH ITERATION MUST RUN LONG ENOUGH FOR THE JIT TO SETTLE, or the compilation state must
   be reported.** The check is a load and a branch in the hottest method in the evaluator;
   whether C2 has compiled `swhnf` and whether it has hoisted the load out of the loop is the
   whole question, so an iteration that finishes in the interpreter measures nothing. Report
   what was done (a warm-up count, `-XX:+PrintCompilation`, or a stated duration per iteration).

**AS BUILT AND RUN, 2026-09-20; AND REVIEWED, WHICH RETURNED DESIGN RED / IMPLEMENTATION RED.**
The instrument is `tracker/tools/eval-bench.sh`, written from scratch for this (nothing was
copied to a new path; it CALLS `scripts/liveness.sh` and nothing else). It never runs sbt and
never writes into a tree: it reads each side's own `target/ermine-classpath` and starts a plain
`java -cp` REPL, so sbt's JVM is not in any number. It REFUSES to run -- exit 3, nothing started
-- when `scripts/liveness.sh` reports a foreign Ermine JVM or an sbt, and it re-checks BEFORE
EVERY FORK. **The review confirmed the arithmetic, the order-swap relabelling and the run
hygiene, and returned RED on the CONCLUSIONS: a threshold that was one draw of a high-variance
statistic was written up as a resolution, an upper bound was read as an estimate, and four
sentences were false against the logs they cited. Everything below is the corrected text; the
figures themselves did not change, and NO new measurement was taken to produce this revision.**

| Item | As built |
|---|---|
| The two trees | **A** = `0a092242` in a throwaway detached worktree, `ermine-scala-wt-wp6-perfA`, a fresh checkout and so a clean build of every subproject. **B** = `b7b93daa` in `ermine-scala-wt-widget-preview`, whose **`core` was cleaned and rebuilt** for this (`sbt core/clean core/compile core/copyResources`) 76 seconds after A's build, same sbt 1.10.7, same JDK. **SCOPED CLAIM, corrected by the review**: neither side is an incremental build of the other, and **B's `core` is not an incremental build of itself** -- but B's `f0`, `parsers`, `machines` and `scalaz-compat` were NOT cleaned and are pre-existing incremental artefacts, and all five class directories are on the classpath. `wp6-s2-buildA.log` compiles f0 (11 files), parsers (14), scalaz-compat (3), machines (12) and core (179); `wp6-s2-buildB.log` compiles core (179) only |
| The driver | ONE copy of ONE file drives both sides -- the script is not copied into the trees at all, it is pointed at each tree's classpath, so there is only one thing to check. The two `target/ermine-classpath` files are identical once the tree prefix is stripped (21 entries each) and both `modules/` directories hold 64 entries; no `.e` module differs between the commits (`git diff 0a092242 b7b93daa`) |
| The workload | TWO, not one, both pure and both evaluated as a single REPL expression over a pipe. **W1 BUILD-AND-FOLD** `sum (range 0 200000)`: a strict left fold (`foldl f !z`, `List.e:49-52`) over a lazily produced list -- every cons cell built and forced once. **W2 REFOLD** `(xs -> sum xs + sum xs) (range 0 200000)`: the same list folded TWICE through one shared lambda binding, so the second fold walks cells that are already `Evaluated` -- `swhnf`'s shortest path and therefore its DENSEST. W2 exists because it is the shape §14's WP-6 row says the check sits at the head FOR. **That W2 does what it claims is MEASURED**: A-side W2/W1 = 2.027/1.217, and net of the stated fixed overhead 1.937/1.127 = 1.72, so the second fold costs about 0.72x the first rather than 1.0x -- the cells were reused, not rebuilt |
| What the timer measures | the interval between writing one expression to the REPL's stdin and reading its answer line: parse + typecheck + evaluation of ONE line. A fixed per-iteration overhead of about **90 ms** rides on every figure -- DERIVED from a 4-point sizing probe (N = 100 k / 200 k / 400 k / 800 k, 3 reps each) as the intercept of a straight line. **UNVERIFIED: that probe's output was not retained** (`tracker/tools/../../` scratch only held the script, `wp6-s2-proto.sh`). It cancels in a difference ONLY IF it is identical on both sides, which is an assumption and not a measurement |
| The repetitions | K = 15 per workload per fork, first 5 discarded, fork figure = median of the last 10. Side figure = median of the five fork medians. 100 measured iterations per workload per side per run |
| The heap and flags | identical on both sides: `-Dermine.typeCheck=true -Dermine.useInterface=false -XX:+UseG1GC -Xms2g -Xmx2g`. `useInterface=false` also means NO `.ei` file is written into either tree |
| The forks | 5 per side, INTERLEAVED A,B,A,B,... as designed |
| The machine | Temurin `openjdk 21.0.12.1 2026-08-18 LTS` (`21.0.12.1+1-LTS`) on both sides. CPU governor **`powersave`** -- recorded, not changed. `liveness.sh` read `sbt=0 console=0 lsp=0 serve=0 ermine-jvm=0` before every one of the 30 forks |

**WHAT A -> B IS, stated correctly (the review's finding, and the earlier text was wrong).** The
A/B compares TWO COMMITS, not one line of code. `Runtime.scala` gains the head check in `swhnf`
**and** a `case c: Cancelled => throw c` arm prepended to the catch in `Prim.apply`, `Box.apply`
and `Bottom.thrown`; `Prim.apply` and `Box.apply` are on the path of every primitive application.
Those arms cost nothing on the non-throwing path, but they change those methods' bytecode size
and exception tables, **and their sizes were never measured here**. So every delta below is the
WHOLE STAGE 1 COMMIT'S EFFECT ON EVALUATION, and the instrument cannot apportion it between the
head check and the catch arms. (For a decision about shipping the commit that is arguably the
right comparison; for a sentence about "one volatile load" it is not.) Separating them needs a
third tree with only the head check reverted -- NOT RUN, costed below.

**THE NOISE STATISTIC WAS NAMED IN WRITING BEFORE THE FIRST MEASURED RUN**, in
`tracker/tools/eval-bench.sh`'s header. **The evidence is a filesystem mtime and a hash, because
the script is UNTRACKED**: mtime **19:11:16**, sha256
**`31a17568cbc178c3daea15cd4354bd084ec682eb30236e52baa2b5533a76f3e3`**, against a first measured
fork at **19:16:45** (`wp6-s2-noise.log:2`) and a smoke run at 19:11:43 that used it. *The script has since been edited to fix three bugs the review found, so its hash no longer
matches; the two values above are the pre-registration record and are what a later reader should
check the claim against. Committing the script would make this checkable without them.*
**THE THREE RUNS ABOVE WERE DRIVEN BY THE PRE-EDIT SCRIPT** (sha256 `31a17568cbc178c3daea15cd4354bd084ec682eb30236e52baa2b5533a76f3e3` in full). **The version
in the tree is `626d6157bc0c7de2b85556641c292e009bcf0231f3c814a4ee1438b60e981774`; its fixes were checked by reading and by exercising every path that starts no
JVM (`--help`, the four usage errors, the liveness parse against `scripts/liveness.sh:140`), and
it has NEVER driven a fork end to end. The next run is also its first exercise.** The statistic, verbatim
from that header: `spread_AA = |median(A2) - median(A1)| / median(A1)`, as a percent, where A1
and A2 are the two SIDES of a run in which BOTH sides are the SAME tree and `median(X)` is the
median of that side's five fork medians -- deliberately the SAME statistic the A/B run reports as
`B/A - 1`, computed where the true answer is known to be zero. The decision rule is the design's,
unchanged: **no movement iff `|median(B) - median(A)| <= max(spread_AA, 2 % of median(A))`**, per
workload.

**THREE BUGS IN THE INSTRUMENT ITSELF, FOUND BY THE REVIEW AND FIXED AFTERWARDS. None of them
can have moved a recorded figure, and the evidence for that is in the logs.** (1) The coprocess
EXIT trap was `trap 'kill "$REPL_PID" 2>/dev/null' EXIT`, and bash UNSETS `REPL_PID` once the
coprocess has gone, so under `set -u` the trap itself raised `REPL_PID: unbound variable` and
**the kill never ran** -- a failed fork could leave a JVM behind. It fired exactly once, at
`wp6-s2-measure.log:52`, in the DIAG B stage, i.e. AFTER every measured run; and a leaked JVM
would in any case have been caught by the next fork's liveness re-check as `console=N` and
refused the run, which never happened. (2) The liveness guard FAILED OPEN: a missing or broken
`scripts/liveness.sh` yielded an empty line, every count defaulted to 0, and the function returned
success -- so the refusal could have been silently disabled. It never was (`scripts/liveness.sh`
was present and answered on all 30 forks). (3) `EVAL_BENCH_TIMEOUT` was documented as a
per-ITERATION cap but was a cap on ONE LINE READ, so a fork that kept emitting output could run
unbounded -- **which is exactly what happened to both diagnostic forks**, and is why condition 4
is only half-evidenced. All three are fixed, plus three nits (`--help` printed three lines of
code; a value-less `--a` exited 1 rather than the documented 2; a failed run left partial rows at
the `<label>.csv` path where a later analysis could read a half-run as a run -- they are now
`<label>.csv.partial`). The fixes were verified WITHOUT starting a JVM.

**THREE THINGS THE FIX PASS LEFT KNOWN AND UNFIXED**, recorded rather than quietly carried:
(i) the per-iteration deadline is computed with an `awk` fork INSIDE the timed window, and
`remaining` forks `awk` again per read, which adds an estimated **0.1-0.5 % to every iteration**.
It is identical on both sides, so a RATIO from the edited script is still comparable -- but
**absolute seconds from it are NOT byte-comparable with the 2026-09-20 figures above**, and a run
that mixes the two would be wrong. The fix is to hoist the deadline above `t0` and use
`EPOCHREALTIME` integer arithmetic instead of `awk`; NOT DONE. (ii) `abandon()`'s `rm -f` branch
is unreachable, because `$CSV` always holds at least its header row -- so a refusal before the
FIRST fork leaves a header-only `.partial` file rather than no file. Harmless, untidy, NOT DONE.
(iii) `abandon()`'s parameter is named `why` but carries an exit CODE. NOT DONE.

**THE FIGURES.** Every time is SECONDS OF WALL CLOCK for ONE evaluation of the named expression
in an already-booted session; every percentage is of the A-side median. `B/A` above 1 means the
STAGE 1 TREE (the whole commit; the switch off and nothing armed) is SLOWER. All three runs are
5 forks per side, K=15 with the first 5 discarded, 100 measured iterations per workload per side.

| Run | Workload | A median (s) | B median (s) | B/A | delta (ms) | fork-median range A / B | pairs B>A |
|---|---|---|---|---|---|---|---|
| **NOISE, A vs A** (the same tree both sides; the two columns are A1 and A2, and neither is the stage 1 tree) | W1 | 1.018 | 0.945 | 0.9286 | -72.7 | 0.364 (35.8 %) / 0.907 (95.9 %) | 2/5 |
| **NOISE, A vs A** | W2 | 1.696 | 1.644 | 0.9696 | -51.6 | 0.470 (27.7 %) / 0.592 (36.0 %) | 3/5 |
| **A/B** (A first in each pair) | W1 | 1.217 | 1.252 | 1.0287 | +34.9 | 0.114 (9.4 %) / 0.147 (11.7 %) | 4/5 |
| **A/B** | W2 | 2.027 | 2.144 | **1.0577** | +116.9 | 0.239 (11.8 %) / 0.232 (10.8 %) | 4/5 |
| **A/B ORDER-SWAPPED** (B first in each pair; the table's A and B columns are re-labelled so that B is still the stage 1 tree) | W1 | 1.206 | 1.188 | 0.9856 | -17.5 | 0.245 / 0.260 | 2/5 |
| **A/B ORDER-SWAPPED** | W2 | 1.948 | 2.043 | **1.0487** | +94.8 | 0.286 / 0.247 | 3/5 |

**THE VERDICT FOR W2, IN THE REVIEW'S OWN WORDS AND ASKED FOR VERBATIM.** *"W2 moved +5.8% and
+4.9% in the same direction in two runs with the pair order reversed, and every estimator (fork
medians, pooled mean, pooled median, per-fork minima, every leave-one-fork-out) agrees in sign; a
central estimate is about +5%. No test on 5 forks per side reaches conventional significance --
exact stratified permutation over both runs p = 0.089, Mann-Whitney on the A-first run p = 0.095,
sign tests p = 0.38 and 1.0 -- and a hierarchical bootstrap CI on the ratio includes zero in both
runs. The instrument suggests a cost of roughly 5% on the swhnf-densest workload; it does not
establish one."*

**THE TESTS.** Computed by the STAGE 2 REVIEW and **RE-DERIVED HERE from the same CSVs; every
EXACT figure reproduced exactly** once the review's convention is applied -- **the review's
p-values are TWO-SIDED, and two-sided is the figure that answers the pre-registered rule, which
takes an absolute value**. All the tests below are exact (no sampling); the bootstrap interval is
resampled, so it reproduces only to within Monte Carlo error (my [-4.0 %, +14.8 %] against the
review's [-4.2 %, +14.9 %], and [-5.2 %, +13.0 %] against [-5.2 %, +12.9 %]).

| Run / workload | permutation, median diff | Mann-Whitney exact | sign test | paired permutation |
|---|---|---|---|---|
| A/B W1 (+2.87 %) | p = 0.1190 | U = 18, p = 0.3095 | 4/5, p = 0.375 | p = 0.625 |
| A/B W2 (+5.77 %) | p = 0.1190 | U = 21, p = 0.0952 | 4/5, p = 0.375 | p = 0.250 |
| SWAP W1 (-1.45 %) | p = 1.000 | p = 1.000 | 2/5, p = 1.0 | p = 1.000 |
| SWAP W2 (+4.87 %) | p = 0.5238 | U = 15, p = 0.6905 | 3/5, p = 1.0 | p = 0.625 |

Pooling both A/B runs with run as a block (exact stratified permutation, 63 504 relabellings,
statistic = mean of the two blocks' `B/A - 1`): **W2 observed +5.32 %, p = 0.0887**; W1 observed
+0.71 %, p = 0.818. One-sided, the same computation gives W2 p = 0.054 (and Mann-Whitney
one-sided on the A-first run p = 0.048). **The pre-registered rule takes an absolute value, so the
two-sided p is the one that answers the registered question; the one-sided figures answer a
directional question chosen after the data were seen, and are recorded only so that a reader who
quotes one knows which it is.** Hierarchical bootstrap of the ratio (resample forks,
then iterations, 20 000 reps, my re-derivation): A/B W2 95 % CI **[-4.0 %, +14.8 %]**, SWAP W2
**[-5.2 %, +13.0 %]** -- both include zero. Estimator agreement, W2: leave-one-fork-out A/B +4.03/+5.61/+4.72/+6.31/
+4.57 % and SWAP +4.31/+3.34/+2.07/+8.37/+8.28 %, all positive; pooled 50 iterations A/B mean
+4.84 % and median +5.57 %, SWAP +4.36 % and +4.73 %.

**W1: NOT DISTINGUISHABLE, AND NOT AT A STATED RESOLUTION.** Every test gives p >= 0.12 and the
estimators disagree in sign (the fork-median headline for the swap run is -1.45 % while its
pooled mean is +3.06 %, and its leave-one-out spans -4.63 % to +4.51 %). **The earlier phrase
"at this instrument's resolution, which is 7.1 %" is WITHDRAWN**: 7.1 % was one draw, and one
wild fork set it (noise A2 fork 4 = 1.836 s against a side median of 0.945 s). The true statement
is that **this instrument cannot resolve a few percent at 5 forks per side**, on either workload.

**THE THRESHOLD IS ONE DRAW, AND BOTH DRAWS WERE LOW.** `spread_AA` is a single realisation of a
high-variance statistic. Splitting the noise run's own ten fork medians every possible way (252
splits) and recomputing `|med2 - med1| / med1` gives, for **W2**, null median **8.75 %**, p90
**12.04 %**, max **14.76 %** -- and the drawn value was **3.04 %**, below the median of its own
null. For **W1** the null is median **11.22 %**, p90 **26.53 %**, max **36.12 %**, and the drawn
value was **7.14 %**, also below its own null median. A second noise pair could plausibly have
returned 8-9 % for W2, under which the same rule reads "no movement". **The W2 verdict is a
coin-flip on one draw, and that is why the sentence above is "suggests", not "establishes".**
**ONLY W2's VERDICT IS SENSITIVE TO ITS OWN DRAW, and the asymmetry is worth being precise about.**
A LOW threshold makes "movement" easier and "no movement" HARDER to declare. W1 drew low (7.14 %
against a null median of 11.22 %) and was declared no-movement anyway, so its verdict survives its
draw and would survive a typical one. W2 also drew low (3.04 % against 8.75 %), and there the draw
is load-bearing: at the null's median draw the same rule would have read "no movement" for W2.

**AND THE CAVEAT IS SYMMETRIC, which the first write-up got wrong by stating it only for W1.**
The noise run ran first and its conditions were not those of the runs it calibrates, and that
cuts BOTH ways: the large absolute W1 threshold makes **"no movement" easier to declare for W1**,
and the low W2 draw makes **"movement" easier to declare for W2**. Each verdict is flattered by
the draw in its own direction. Stating it for one workload only reads as advocacy.

**THE RULE ALSO GIVES OPPOSITE VERDICTS TO EQUALLY STRONG EVIDENCE.** Inside the same A-first run,
W1 (+2.87 %) and W2 (+5.77 %) have IDENTICAL permutation p-values (0.1190) and identical sign
counts (4/5). The rule separates them only because the noise run happened to return 7.14 % for one
and 3.04 % for the other. The rank test does mildly favour W2 (Mann-Whitney 0.095 against 0.310).

**THE MACHINE WAS NOT STATIONARY, and the noise run got the worst of it.** Per-fork 1-minute load
averages read off each run's own `liveness` lines: **noise 0.68 -> 2.55 -> 2.94 -> 2.06 -> 3.26 ->
2.84 -> 2.54 -> 2.26 -> 4.23 -> 8.46**, while the A/B run held 3.11-4.53 and the swap run
3.07-7.37. Fork medians drift upward through the noise run at +5.6 %/fork and +13.1 %/fork (W1)
and +3.5 % and +7.2 %/fork (W2); in the A/B run the slopes are within +/-1 %/fork. **The noise
floor was not a floor, it was a ramp.** The earlier sentence *"load 0.68 at the start and 4.22 at
the end of the last run (the tail is this bench's own JVMs)"* is withdrawn twice over: it quoted
the wrong run's end and the attribution to the bench's own JVMs was never established.
**FOR THE RECORD, and it is the orchestrator's error, not the box's**: another read-only agent
and the orchestrator were doing light shell and web work on this machine during the noise run
(19:16-19:26). Nothing Ermine ran -- all 30 liveness lines read `sbt=0 console=0 lsp=0 serve=0
ermine-jvm=0` -- but the box was not quiet, and the noise run is the run that paid for it.

**THE FIRST FORK OF A RUN IS CONTAMINATED even after five warm-ups.** In the swap run, fork 1 of
the stage 1 tree has W2 warm-ups of **3.15, 2.64, 3.14, 3.33, 3.28 s** against that fork's
measured median of **2.094 s**. Dropping fork 1 from both sides moves **A/B W2 from +5.77 % to
+4.03 %** (and A/B W1 from +2.87 % to +2.57 %, SWAP W2 from +4.87 % to +4.31 %). Recorded as a
known artefact of this instrument; no figure above drops it, because dropping a fork after the
numbers are in is the thing the pre-registered rule exists to prevent.

**CONDITION 1: THE `swhnf` COUNT PER ITERATION, AND WHAT THE DERIVED PER-CALL COST DOES AND DOES
NOT SHOW.** The count is **DERIVED, NOT MEASURED** -- a counting build would mean editing
`Runtime.scala`, which this run was not allowed to do -- and it is a LOWER BOUND. Per list element
the evaluator must at least: force the list argument to match `(x :: xs)` (`Pattern.scala:135`'s
`r.whnf`), and, because that argument is an unevaluated `Thunk`, re-enter `swhnf`'s own
tail-recursive head to write the result back (`Runtime.scala:378`) -- 2; force the scrutinee of
`case start >= end of` inside `range` -- 1; force the strict accumulator of `foldl f !z` -- 1.
`swhnf` is `@annotation.tailrec` (`Runtime.scala:332`), so its self-calls are jumps back to the
head and EACH ONE RE-RUNS THE CHECK. That is **>= 4 per element**, so at N = 200 000: **>= 8 x 10^5
checks per W1 iteration** and **>= 1.6 x 10^6 per W2 iteration**.

| Workload | delta per iteration (A/B run / swap run) | checks per iteration (derived lower bound) | derived cost per check (upper bound, with sign) |
|---|---|---|---|
| W1 | +34.9 ms / -17.5 ms | >= 8 x 10^5 | <= +44 ns / **-22 ns** |
| W2 | +116.9 ms / +94.8 ms | >= 1.6 x 10^6 | <= +73 ns / <= +59 ns |

**THE EARLIER SENTENCE "which is far too large for one volatile load" IS STRUCK; IT WAS AN INVALID
INFERENCE** (the review's must-fix). A LOWER bound on the count gives an UPPER bound on the cost,
and an upper bound of 73 ns is entirely compatible with a true cost of 1 ns. Refuting "it is the
load" would need an UPPER bound on the count, which is not in evidence. **The bound is also very
likely a gross undercount**: `Runtime.appl` (`Runtime.scala:396-399`) calls `swhnf(v)` once per
spine step, so `foldl f (f z x) xs` and `(+) z x` alone add about five more per element before any
pattern machinery. W2 spends about 5.1 microseconds per element-visit; W2 has 4 x 10^5 element-visits per
iteration (200 000 cells walked twice), so at a realistic **40-100 `swhnf` calls per element-visit
the derived figure falls to 2.4-7.3 ns** -- 116.9 ms / (4 x 10^5 x 40) = 7.3 ns and / (4 x 10^5 x
100) = 2.9 ns on the A-first run, 5.9 ns and 2.4 ns on the swap run -- which is the range of a
volatile load acting as a compiler barrier in the hottest loop. *(An earlier revision printed
"1.5-7 ns"; the arithmetic is above and the slip was the review's, repeated here uncorrected.)* **What the bound actually
shows is that the count is too crude to decide the question.** A counting build decides it and is
**NOT BUILT** (costed below).

**CONDITION 4: THE JIT STATE -- HALF-EVIDENCED, and three earlier sentences about it were false.**
A diagnostic fork per side ran under `-XX:+PrintCompilation` (it measures nothing; the flag
perturbs). What the logs actually show:

- `Runtime$::swhnf` is **216 bytes** on A and **260 bytes** on B (+44), reaching **tier 4 (C2)** at
  **16 432 ms** (A, `wp6-s2-c2-A.log:15690`) and **20 559 ms** (B, `:15360`), with OSR tier-4
  compiles at 16 745 ms and 21 118 ms.
- **THE BOOT HAD ALREADY FINISHED.** The `Loaded 129 modules` line sits at **~16 289 ms** on A
  (`wp6-s2-c2-A.log:15148`, between compilation stamps 16 287 and 16 289) and **~20 244 ms** on B
  (`wp6-s2-c2-B.log:14654`). So `swhnf` reaches C2 **inside the FIRST WARM-UP ITERATION**, about
  140-320 ms after the boot -- *not* "during the boot", as the first write-up said. The conclusion
  survives, because the first MEASURED iteration is the sixth; the stated reason did not.
- **THE "11-13 s boot" FIGURE IS WITHDRAWN AS UNVERIFIED**: no artifact retains it, and the two
  logs that do carry a boot time say 16.3 s and 20.2 s under `PrintCompilation`.
- **"Neither log shows any later `swhnf` compilation or `made not entrant`" WAS FALSE FOR B.**
  After B's tier-4 compile there are `20609 ... 3 ... made not entrant`, `20908 ... % 2`,
  `21118 ... % 4` and `21167 ... % 2 ... made not entrant` (`wp6-s2-c2-B.log:15367,15435,15527,
  15528`). VERIFIED BENIGN in the only sense that matters here: every retirement names **tier 3 or
  tier 2**, i.e. a lower-tier version being displaced once tier 4 exists, and no tier-4 `swhnf`
  method is retired in either log.
- **NEITHER DIAGNOSTIC FORK COMPLETED.** A failed at W2 iteration 4 (`exit 5`, a read timeout whose
  mechanism is **unverified** -- no GC log, no thread dump); B was stopped by hand at W1 iteration
  3 with **two warm-up rows** in its CSV. So on B there is no compilation evidence at all from
  inside the measured window. **Condition 4 is therefore HALF-EVIDENCED**: the tier-4 timestamps
  are real and both precede the first measured iteration, and the claim that nothing deoptimised
  *during the measured window* rests on A's partial log alone.

**THE BYTECODE READING, WEAKENED TO WHAT IS SHOWN.** 216 -> 260 bytes is measured. On this JDK
`MaxInlineSize` is 35 and `FreqInlineSize` is 325, so both sizes sit in the same coarse class and
**the bytecode-size threshold story alone is excluded** -- that is all. The earlier claim that
"the obvious 'it stopped being inlinable' story is EXCLUDED" is too strong: `InlineSmallCode`
(compiled native size) and the caller's node-count and inline budget both scale with callee size,
and a 20 % growth of the evaluator's hottest method can change what else fits alongside it.
**UNVERIFIED: the `-XX:+PrintFlagsFinal` output for those two flags was not retained** -- they are
HotSpot defaults and almost certainly right, but nothing on disk proves it for this JVM.

**SIX DEVIATIONS FROM THE DESIGN, each named as a deviation rather than folded away.**

1. **TWO WORKLOADS, NOT ONE.** The design says "a pure fold dominated by `swhnf`". W1 is that
   fold. W2 was ADDED because W1 alone would have answered the wrong question: the check sits at
   the HEAD of `swhnf` precisely for the already-`Evaluated` path, and W1 barely exercises it.
2. **A THIRD RUN, ORDER-SWAPPED, WAS ADDED.** The design interleaves at fork level but always runs
   A first inside a pair, which leaves a within-pair position effect unmeasured. Estimated
   position effect: second-minus-first was +5.77 % in run 1 and -4.64 % in run 2, averaging
   +0.5 %, against an averaged tree effect of +5.3 %. The control is right in SHAPE and powerless
   in SIZE: one replicate of each order constrains nothing quantitatively, and in the swap run the
   two sides trend in OPPOSITE directions across forks (+1.2 %/fork and -3.0 %/fork on W2), which
   a common box drift cannot produce.
3. **THE `swhnf` COUNT IS A DERIVED LOWER BOUND, NOT A COUNT**, so the per-call figures are bounds
   rather than values -- and, as above, too crude to settle what they were first used to settle.
4. **THE DRIVER IS ONE FILE POINTED AT TWO CLASSPATHS**, not two copies checked by sha256. That is
   stronger for the driver, but condition 3's concern is broader than the driver ("if the harness
   is also rebuilt or edited between sides"), so it is a departure, not a strict improvement.
5. **ONLY `core` WAS CLEAN-REBUILT ON B** (see the table above); the design's clean-build
   requirement is met for A in full and for B's `core` only.
6. **THE WRITE-UP WAS REVISED AFTER REVIEW WITHOUT RE-MEASURING.** Every figure in it comes from
   the three runs of 2026-09-20; the corrections are to claims, not to data.

**WHAT THIS A/B ACTUALLY DECIDES, stated as a fact about the mechanism and not as a
recommendation.** Flipping `ermine.preview.cancelOnTimeout` adds **no per-force cost at all**: the
head check and the three catch arms are in the binary either way, and the switch only governs
whether the watchdog ARMS `cancelTarget` after a timeout -- at which point one render is already
wedged and the branch is taken on one thread for at most a grace period. So these figures bear on
**whether stage 1's check is acceptable to carry in the evaluator at all**, which is a question
about the commit that is already on this branch. They do not bear on the PER-FORCE cost of the
flip, because the flip has none. **They are also not the whole of the flip's cost**: turning the
switch on turns on §14(d) and (f) -- the UNCONDITIONAL discard of the render session on a taken
cancel (a boot, and every memoised thunk in it, per cancelled render), the two-phase watchdog, and
`isFatal`'s documented exception, which is sound only for as long as that discard stays
unconditional. Those are behavioural costs and this instrument says nothing about them.

**WHAT WOULD MAKE THIS DECISIVE -- NOT RUN, and the user's to choose.** Costed by the review from
this run's own logs (about 65 s per fork; a 5+5-fork run took 9.3-11.0 min wall). Every one of
these needs the editor closed.

| # | What | Machine time | What it buys |
|---|---|---|---|
| 1 | **A counting build**: one scratch worktree of B with a static counter in `swhnf`, one untimed fork | clean `core` ~40 s + 1 fork ~2 min = **~3 min** | turns `>= 4`/element into a real count and settles whether `<= 73 ns` is or is not compatible with the volatile load. Highest value per minute. Needs permission to edit Scala in a throwaway tree |
| 2 | **A second A-vs-A noise pair, AFTER the A/B pairs**, under the same load | **~11 min** | two draws of `spread_AA` instead of one; would expose or refute the 3.04 % low draw. Still not a distribution |
| 3 | **15 forks per side, both orders** | 2 runs x 30 forks x 65 s = **~65 min** | the decisive experiment. From the observed fork-median CV of 4.6 % (A-side W2), detecting a 5 % shift at 80 % power / alpha 0.05 needs ~13-14 forks per side; at 15 the p = 0.089 either becomes a result or collapses |
| 4 | **`performance` governor** for the duration (`cpupower frequency-set -g performance`, root) | **~0 min**, pair with #3 | cuts the fork-to-fork spread that is the whole problem. Alone it changes the numbers without making them decisive |
| 5 | **Isolate the head check**: a third tree = `b7b93daa` with ONLY the `swhnf` head check reverted, A/B against B | clean `core` ~40 s + **~11 min** | separates the head check from the `Prim.apply` / `Box.apply` / `Bottom.thrown` catch arms, and makes the attribution language true instead of assumed |
| 6 | **A denser micro-workload** (four folds over one shared list, or `length` over a range sized to ~2 s/iteration) | **~0 extra**, replaces W2 | raises the signal against the ~90 ms fixed overhead. Not comparable with the existing figures |
| 7 | **Discard fork 1 of each run** | **0 min**, re-analysis only | removes the demonstrably contaminated first fork; moves A/B W2 to +4.03 % |

Cheapest package the review names: **#1 + #2 + #7, about 14 minutes of machine time**; full
confidence **#1 + #3 + #4 + #5, about 80 minutes**. None of it was run.

**WHAT THIS RUN DOES NOT MEASURE.** The ARMED case: every figure above is the unarmed path
(`cancelTarget` null). It does not measure a render session, the LSP, or anything with IO in it.
It cannot apportion its own delta between the head check and the catch arms. And it is a
ONE-MACHINE, ONE-DAY, `powersave`-governor, 5-fork instrument: evidence about this box on this
afternoon, not a portable constant.

It is an INSTRUMENT and never gate evidence (`docs/gate-policy.md:28-29`, `:98-101`). Its result
is an input to STAGE 3 -- flipping `ermine.preview.cancelOnTimeout` -- which is the user's call
and nobody else's.

**AMENDED 2026-09-20 (WP-24): THERE IS NO STAGE 3.** The mechanism these figures measured was
REMOVED from the tree on the user's decision (§13, Q13), so there is no default left to flip and
nothing is waiting on this instrument. What its result is now is the record of what the removed
commit cost while it was carried, at the strength its own closing sentence gives it.

## 12. Alternatives rejected

| Alternative | Why |
|---|---|
| Drive the loop off `bin/ermine-serve` | a JVM boot per `.e` edit (`Runner.scala:411-420`; `JSON-GUIDE.md:1452-1453`); no host page, no CORS (`JSON-GUIDE.md:1631-1641`); a credential would be an argument (`bin/ermine-serve:32-33`) |
| A dev server (static route + CORS + `webpack-dev-server`) | a second process, a second cache to invalidate, a webview that cannot load from it (*external*) |
| Options (A) and (B) of §2.1 | see the table |
| A separate render process | reopens the settled second-session decision; the heap cap and the restart path cover what it would buy |
| Reuse `Session.reloadChangedModules` for invalidation | its dirty set is the process-global `depCache` (`LSP-STALENESS.md:36-40`) |
| Refuse to render while any `.e` buffer is dirty | does not close the registry hole (a buffer closed unsaved leaves its shape registered and nothing dirty) and would block the two-file loop's normal state (§5, "unsaved") |
| A per-session constructor index now | the right long-term shape, a day of work through every JSON test; the registration flag closes the hole in ten lines (§2.2) |
| `ermine/schema {binding}` answered by the resident with the preview roots appended to its chain | workspace report modules would enter the resident (`LSP-STALENESS.md:40`) and the binding would be evaluated on the dispatch thread (§6) |
| A privileged binding name (`report`), found by a `^report\s*:` regex | one report per module, one spelling, a signature-less binding missed; the picker lists by type (§3.2) |
| A defaults binding (`<binding>Args`) seeding the params file | another privileged name; the committed params file is the default (§6) |
| A stdlib record type for previews | new surface; a report-typed binding already is the unit |
| Flat `<Module>.<binding>.params.json`; one params file per module | §6 |
| Seed SQL files run on connect | no seed mechanism; a file-backed SQLite the developer fills is enough (§7.1) |
| `capabilities.untrustedWorkspaces: limited` | activates the extension in Restricted Mode and spawns the untrusted checkout's `bin/ermine-lsp` (§8.2) |
| Redact the `<<` log line per request id | unnecessary once every answered message is scrubbed at the source (A10); adds state to `Rpc.scala` |
| WSL for Windows machines | native wrappers keep the extension host, the secret store and the truststore on Windows (§10) |
| `DB.RunUser` for credentials | holds the password for the process's life and reconnects per run (§7.2) |
| A password field in the profile; integrated auth | §8 |

## 13. Open questions (none blocks WP-1..WP-6)

| # | Question | Blocks |
|---|---|---|
| Q1 | which global the writers bundle puts on `window` (`htmlwriter` vs `ermine_htmlwriter`) | **ANSWERED BY READING 2026-09-20** (WP-9/10/11 design review, §5's findings block): it is **`window.ermine_htmlwriter`**, assigned **only inside a `DOMContentLoaded` listener** (`ermine-writers/writers/js/htmlwriter.js:10-13`), and `client/src/index.ts:5` documents the wrong name. The timing, not the name, is the half that bites. **CLOSED 2026-09-21: WP-9 WROTE IT DOWN, IN CODE** -- the name and the timing are in `client/src/index.ts`, `client/src/legacy.ts` and `client/README.md`, `requireHtmlWriter`'s error text names the real global and the timing, and `(w-no-writer)` in `client/test/widgets.test.ts` pins that text. There is **no behaviour change in the lookup**: the client reads `ctx.env.htmlwriter`, an env key the host fills, and never read a writers global (MEASURED). **The superseded closing clause, kept as history: *"Nothing decided, nothing built; WP-11 still owns writing it down"* -- false as of 2026-09-21; what is left to WP-11 is a browser** |
| Q2 | recycling defaults (renders / idle minutes) for a held MSSQL connection | WP-14 |
| Q3 | is `Windows-ROOT` needed, or is the internal CA in the JDK's `cacerts` | WP-12 |
| Q4 | how a module whose LOAD FAILED is invalidated once it is fixed | **DECIDED 2026-09-20** (option (i), built); resolved |
| Q5 | §2.4 and §4 disagree: the 404 "not under a module root" is unreachable for a readable file | **DECIDED 2026-09-20** (option (i), built); resolved |
| Q6 | a roots change discards the `Runner`, and the inferred root is part of the roots, so previewing two reports in two directories re-boots the render session each time | **DECIDED 2026-09-20** (the refinement, built); resolved |
| Q7 | `ermine/schema {module, binding}` carries no `uri` and no `roots`, so a schema asked before the first render cannot see a workspace module | **DECIDED 2026-09-20** (the request carries `uri`/`binding`/`roots` and shares the render's resolution; a shadowed pick is an error), built; resolved |
| Q8 | §2.5 asks the watchdog's NOTIFICATION to carry the **Restart Language Server** button, and no LSP server-to-client notification carries an action | **DECIDED 2026-09-20** (the orchestrator's recommendation as changed by the design review: a STUCK-ONLY `"stuck": true` marker plus `ermine/preview/stuck`), built; resolved |
| Q9 | `ermine.preview.timeoutSeconds: 0` turns the watchdog off entirely as built: is an off switch wanted at all, and should `0` be it? | **DECIDED 2026-09-20** (the orchestrator's recommendation as changed by the design review: option (i), PROSE ONLY -- nothing built but one property over the existing `applySettings`); resolved |
| Q10 | what `stuck` means if the wedged job DOES come back: as built it never clears | **DECIDED 2026-09-20** (the orchestrator's recommendation as changed by the design review: option (ii), clear when the fired-on job RETURNS and never on a `java.lang.Error`), built; resolved |
| Q11 | a report whose module did NOT EXIST when it was first rendered is still not named when its file appears | **DECIDED 2026-09-20** (the design review WITHDREW the orchestrator's server-side recommendation: option (iii), the extension's, nothing built in `Runner`); resolved |
| Q12 | the JVM's own OOM termination line is written to STDOUT -- the LSP protocol channel -- unframed, after the last frame (MEASURED, §2.5) | **DECIDED 2026-09-20** (the orchestrator's recommendation as changed by the design review: step 1 only -- `-XX:+DisplayVMOutputToStderr`, MEASURED to work, added behind a cached probe; no descriptor duplication), built; resolved |
| Q13 | a stuck preview takes the WHOLE SERVER down at `-Xmx` about two minutes after the watchdog fires (MEASURED, §2.5), which is not the story §2.5 tells | **DECIDED 2026-09-20 BY THE USER: option (ii), PRIORITISE WP-6.** Stage 1 (the mechanism) is BUILT behind `ermine.preview.cancelOnTimeout`, DEFAULT FALSE; stage 2 is the evaluator instrument of §11; stage 3, ADOPTION -- flipping that default -- is the user's. Resolved. **RE-OPENED AND RE-DECIDED BY THE USER THE SAME DAY, 2026-09-20 (evening). The line above is kept as history, not overwritten.** **THE NEW ANSWER: option (iii) -- ACCEPT THE WEDGE, CONTAIN IT IN THE CALLER (WP-22), AND REMOVE THE CANCEL (WP-24).** The user's words, verbatim. On the in-evaluator cancel: *"That sounds super sketchy."* On accepting the wedge and containing it: *"I like 3 honestly. One thing to watch for would be an infinite re-render loop. We'd want some sort of confirmation before rendering a report which wedged and was killed the first time around and it didn't change."* On where the memory belongs (quoted WITHOUT the surrounding italics, because the user's own text contains asterisks): "I think "remembering" is an extension concern. I like this approach infinitely better than modifying the language all for a way to recover a stuck render( especially since most of the solutions you mentioned, indicate that responsiblity for solving this happens with the *caller* )" They then confirmed that the cancel instrumentation inside general Ermine evaluation is to be removed. **THE REASON IS THE DESIGN, NOT THE PERFORMANCE FIGURE**: a preview-only recovery does not justify instrumenting the language's evaluator, and responsibility for a stuck render belongs with the caller. Stage 2's instrument neither decided this nor could: what it says is §11's own sentence, *"The instrument suggests a cost of roughly 5% on the swhnf-densest workload; it does not establish one."* **STAGE 3 IS MOOT** -- there is no default left to flip. Resolved again, by removal (WP-24, done); what answers Q13 now is **WP-22, whose (a)+(b) were BUILT the same day (2026-09-20)**. The behaviour this row started from is UNCHANGED in the server and always will be -- it dies at `-Xmx` about two minutes after the watchdog fires, and the client restarts it -- and what WP-22 changed is only what happens NEXT: that restart no longer re-renders the report that wedged unless something changed or the user says so. **The loop is closed in the code that decides and UNOBSERVED in the editor that runs it** (Q17) |
| Q14 | a render that fails by a TRANSIENT error leaves that failure MEMOISED in the render session's thunks, so a binding of a module nobody edits re-throws the old error for the life of the session | nothing; decide with WP-12/WP-13 |
| Q16 | `placeAndSession` calls `ensureSession` BEFORE it refuses an unplaceable file, so a request that is going to be refused anyway can still discard and re-boot the render session when its roots differ | nothing; OPEN, the user's |
| Q17 | the `Stopped -> Running` recovery re-render RE-ISSUES the render that killed the server (`preview-core.js:355` emits `rerender` on that transition, `extension.js:471` turns it into a real `ermine/render` of the same pick), and the **Restart Language Server** button in our own stuck notification (`extension.js:452-456`) takes THE SAME PATH -- so the one remedy we offer during a wedge is itself a loop trigger. READ from the code by the WP-24 design review; **UNOBSERVED in a real editor by anyone** | **DECIDED 2026-09-20: BY WP-22** -- one mark for the current pick, one consultation site (that `rerender` effect), and a confirmation instead of an automatic re-render when the report that wedged has not changed. Under Q13's new answer this path fires by design on every incident, which is why the guard is what makes accepting the wedge safe. **BUILT THE SAME DAY (WP-22 (a)+(b), extension 0.1.6): the automatic render is no longer issued for a marked pick, and the SAME site covers the Restart Language Server button, because `restart(context)` produces exactly the `Stopped` then `Running` edges a crash does (READ, `extension.js` `restart` -> `stopQuietly` -> `startClient`). The decision is unit-tested -- `test/preview-core.test.js`, 67 tests, including the property "over any event sequence an automatic Running re-render is issued only with a clear mark". THE ARRIVAL IS NOT AND CANNOT BE, HERE: that a crash-restart really produces a `Stopped` edge, what a dismissed `showWarningMessage` resolves to, and whether `workspaceState` survives what we think it survives are all UNOBSERVED (`tracker/WP-7-MANUAL-CHECKLIST.md` §2.15-2.27). So the loop is closed BY CONSTRUCTION in the code that decides, and unverified in the editor that runs it** |
| Q18 | under Q13's new answer the SERVER keeps no self-defence at all: after a restart it is a new process and cannot know what wedged the last one, so only the CALLER spans the restart and `bin/ermine-serve`, `bin/ermine` and every non-VS-Code client are unprotected | **OPEN, and ACCEPTED as a known hole unless the user says otherwise.** It is the same fact that makes the extension the right owner (the user: responsibility "happens with the *caller*"). Two consequences to state rather than fix: the extension-only memory does not cross windows -- a second VS Code window on the same folder does not see the mark until it reloads (cross-window `Memento` visibility UNVERIFIED) -- and WP-23 (a server-side deliberate exit) stays PARKED, not started. **UNCHANGED BY WP-22(c) (2026-09-21), AND WORTH SAYING AGAIN NOW THAT SOMETHING DOES END A WEDGE**: the thing that ends it is the VS CODE EXTENSION restarting its own client. The server still has no watchdog on its own life, still cannot tell our restart from any other, and still carries nothing across one; `bin/ermine-serve`, `bin/ermine` and every non-VS-Code client get NOTHING from (c) -- a wedge there still ends only at `-Xmx` (MEASURED, about two minutes after the fire) or, for a wedge that allocates nothing, never. The hole did not move; only VS Code got a floor under it |
| Q19 | **the committed legacy writers bundle is a webpack-4 `eval` build (574 `eval("`, 1 `new Function`, MEASURED), so a webview CSP without `'unsafe-eval'` would not load it (INFERRED, never watched failing) -- and WP-9's and WP-11's done-whens depend on it loading** | **DECIDED 2026-09-20 BY THE USER: OPTION (i) -- ALLOW `'unsafe-eval'`, IN THE PREVIEW WEBVIEW'S CSP ONLY.** Their words, after the trade was explained to them: *"oh yeah unsafe-eval sounds great. We'll remove it later on if need be"*. So the committed `eval`-built writers bundle loads AS IT IS and WP-9/WP-11's done-whens become satisfiable; the weakening is scoped to that one webview, whose content is already the developer's own workspace and database. **THREE THINGS THIS DOES NOT CHANGE, and they are the reason it is reversible**: (a) **WP-9's OWN bundles must still contain no `eval(` and no `new Function`** -- D9's static test stays a done-when -- so the flag can be dropped the day the writers bundle is rebuilt; (b) the bundle has **still never been watched loading or failing** in a webview by anyone (D1's consequence is INFERRED), so this decision removes a blocker, not a doubt; (c) `devtool: 'source-map'` stays required for our own bundles (§5). The three options are kept below as the record of what was weighed; (ii) and (iii) were not taken: (i) add `'unsafe-eval'` to `script-src` for the preview webview only -- one word, and the webview's content is already the developer's own workspace and database, but it is a documented weakening of a documented recommendation; (ii) rebuild the writers bundle with a non-eval `devtool` -- a 2019 toolchain (webpack 4, `node-sass@^4`) under node 24, likely a fight (unverified), and a 5 MB artifact to commit in the sibling repo; (iii) ship the preview without the legacy renderers -- `scorecard`/`headline`/`crosstab` render, `table`/`drilldownTable`/charts show the designed "unsupported" box, and WP-11 becomes "not yet". **It is a security decision, not an engineering one** |
| Q20 | **should `Session.scrub` be hardened (WP-25), and if so when?** ROBUST-3 (2026-09-20) showed that `scrub` is only correct if its caller's module set is CLOSED UNDER IMPORTERS, and that nothing checks it: `e.env` is filtered by the V's OWN defining module while `e.termNames` / `termNameOrigins` / `cons` are filtered by the KEY's module (`session/Session.scala:811-827`), so a non-closed set deletes a definer and leaves every re-exporter's name pointing at it, and the next load dies with `undefined term` inside a stdlib file the user never touched instead of an honest "not in scope". IN THE PRODUCT the non-closed set is NOT reachable today by the path ROBUST-3 found (the LSP never removes a `Filesystem` key from `Session.depCache` -- `lsp/Documents.scala:77`, `:111` evict `Buffer` keys only -- so `dependentsOf` always has complete edges); WP-26 is the one INFERRED way it could become reachable. The proposed change is ONE LINE plus a pinning property, and its evidence is measured (13 of 30 random subsets fail the property today). **IT TOUCHES THE SESSION CORE, which every suite and the REPL load through, so building it is THE USER'S CALL and nothing has been built.** **DECIDED 2026-09-20 BY THE USER: BUILD IT.** Their words: *"harden unloading."* **IT IS BEING BUILT NOW, IN A SEPARATE WORKTREE** -- `ermine-scala-wt-wp6-perfA`, branch `wp25-scrub` -- and is **NOT YET BUILT, NOT REVIEWED AND NOT MERGED**; nothing of it is in this worktree or on `widget-preview`. Side worktrees write their own as-built notes and do not edit this document; WP-25's row is amended here when it merges **ANSWERED 2026-09-21 -- DECIDED BY THE USER, BUILT, REVIEWED AND MERGED. THE QUESTION'S TEXT ABOVE IS KEPT AS HISTORY, AND EVERYTHING IN IT FROM "IT IS BEING BUILT NOW" IS SUPERSEDED**: the hardening was built as `ee093b46` on `wp25-scrub` and merged into `widget-preview` at `c73d4e7c`, with the `pr` gate green on the merged tree (content key `3f07799de8b3ee6376c808c805dd84cbbfd3d427`: compile, corpus, lsp **641 checks**, suites **`Passed: Total 1292, Failed 0, Errors 0`**; `lean` UNAVAILABLE in this worktree). **THE PROPOSED ONE-LINE CHANGE WAS REFUTED BY MEASUREMENT AND WAS NOT SHIPPED**: over the same 30 seeded subsets it removes the dangling names (16 of 30 today, 0 with the drop) but kills **8 of 30 reloads**, and only **14 of 30** surfaces then match a fresh load; on ROBUST-3's own reproduction it dies with the SAME message. What shipped instead WIDENS the set over re-exporters, REPAIRS the origins tables by splice, and RETURNS the set it scrubbed by. **THE "13 of 30" ABOVE IS ONE OF THREE DIFFERENT QUESTIONS**, not a contradiction: 13 of 30 is ROBUST-3's narrower `termNames -> env` probe on its own seed, 16 of 30 the shipped multi-table form on this ticket's seed, 25 of 30 a flat origins form from a first red run that is no longer used. §14's WP-25 row and `tracker/WP-25-AS-BUILT.md` are the record, limits included | **ANSWERED; nothing.** WP-25 is merged; WP-26 (re-scoped, see §14) is not built |
| Q21 | **DECIDED 2026-09-23 BY THE USER: fix the example and file a ticket** -- their words, *"Let's fix Sales.e now, and file a ticket for zero-rows."* That is option (b) below plus its wider question answered as a ticket: `core/src/test/resources/doc/Sales.e` builds `byDay` with `relationWithHeader {region, day, amount, units}`, and **the first pick with today's dates now answers `ok=true`** -- the heading at `matched: 0`, the `byDay` table with its four columns and `"rows": []`, `"rowCount": 0`; the in-range render (2026-01-05..2026-03-17) is the SAME 1407-byte document as before the change, deferred token and expiry aside, and the `ermine/schema` answer is unchanged (MEASURED, `scratch-widget-preview/q21-sales/` (one `bin/ermine-lsp` boot, `captures.json`; `IMPL-REPORT.md` has the exact lines)). **The engine gap is WP-29 (§14), NOT BUILT, not scheduled.** The text below is the question as it stood. **what should the FIRST PICK of a report show when the skeleton's defaults select no rows?** MEASURED 2026-09-21 by the S1 review against a real server: `Sales.report` with the skeleton's today-dates answers **`ok=false, status=500`** -- *"Sales.report produced a document that cannot be encoded: an empty relation built from no rows carries no columns; give it a header (mkRelationWithHeader#) or a static hint"*, `path $.children[1].cells[0][0].props`. Controls in the same boot: the gate's in-range params render `ok=true`; a MISSING key earns a 400 whose MESSAGE names it ("the required key \"toDay\" is missing"), and a WRONG-TYPED date earns a 400 whose message names the defect ("expected a date string yyyy-MM-dd, found the number 5") -- **the review did not capture that second answer's `path`**; WP-7's own earlier measurement recorded it as `$.params.fromDay` (`tracker/WP-7-MANUAL-CHECKLIST.md`, its findings list, where a MISSING key is reported at its object's path with the key in the MESSAGE and only a PRESENT ill-typed key gets the deeper path). Both are 400s that point at a key, and A earned no 400 at all -- **so the skeleton decodes correctly and this is not a skeleton defect**. It is date-independent from here on: every `Sales` row is in 2026-01..03. The options, recorded neutrally and NOT chosen: **(a)** keep U2's "today" and accept that `Sales`'s first pick is this 500 until the dates are edited -- the done-when is then reworded to say exactly that, and U2's "the params file is opened for editing right after it is written" is what makes it a workable first minute; **(b)** give `core/src/test/resources/doc/Sales.e`'s relations a header hint so an empty result encodes -- this changes the example, and raises a wider question of its own: ANY report whose query returns no rows hits the same 500, so is that an engine limitation deserving its own ticket rather than a fix to one example? **(c)** change U2's date rule itself. | **WP-8's FIRST DONE-WHEN CLAUSE** ("`Sales` renders a document on first pick with no hand-written JSON"); nothing else -- S1 is pure and is unaffected, **AND S3 (BUILT 2026-09-21) DOES NOT CHOOSE EITHER, WHICH IS A DECISION IT HAD TO MAKE AND DID NOT**: its code is IDENTICAL under (a) and (b) -- (b) changes `Sales.e` and nothing in the extension -- and under (c) exactly one thing moves, `todayForSkeleton` (`editor/vscode/src/extension.js`), which fills in the `today` argument `skeletonFrom` has taken since S1; no other function in either file would change. S3 MEASURED both halves on the bytes the shipped code writes: today's dates give the 500, and the same file with 2026-01-05..2026-03-17 renders `ok=true`, a 1407-byte document. The manual checklist's §2.43 points at this question rather than calling the 500 a defect of that step, **and S2 (2026-09-21) does not depend on this question either**: S2 writes no skeleton and needs a HAND-WRITTEN file, so the first-pick question does not arise until S3. With such a file `Sales.report` renders a document (MEASURED, section 6's S2 control A). **S4 (2026-09-23) DOES NOT CHOOSE EITHER, AND ADDS ONE PLACE THE ANSWER WOULD REACH AND NO MORE**: U3's command writes the same skeleton from the same `todayForSkeleton` call site, so under option (c) that ONE call still moves and nothing else does. S4 re-MEASURED the 500 on the shipped code (section 6's S4 table), and the manual steps that show it are B1 and now B23 |
| Q22 | **should the command "Ermine: Render Report to JSON" be renamed?** Under `ermine.preview.target: panel` (the default since 0.1.12) it renders into the panel, not JSON. Found by the WP-10 S2 review (N4); recorded in §5's WP-10 S2 block. A rename (e.g. "Ermine: Render Report") changes the palette entry every playtest step names, so it was NOT done | nothing blocks on it; the user's, NOT ASKED YET. Options: (a) keep the title; (b) rename, and update the checklist, the README and `package.json` together. Neutral: the playtest can run either way; the checklist names it in the open decisions (4) and asks in `tracker/PLAYTEST-RESULTS.md` |
| Q23 | **the panel's seven design choices, U1-U7 of the WP-10 design review, were TAKEN BY THE ORCHESTRATOR, NOT THE USER -- the user has NOT been asked any of them** (§5's "U1-U7" block): U1 `ermine.preview.target`, default `panel`, the tab kept; U2 `retainContextWhenHidden` AND a mandatory resync; U3 the bundle from `resolveServer().root`, the writers from `ermine.preview.writersPath` with a sibling default; U4 Restart as the panel's only button; U5 no `blob:`; U6 a rejecting `fetchData`, no fetch message pair (**taken on F2, which proved false: Q24**); U7 `gate_extension` at commit | nothing blocks on it; the user's, NOT ASKED YET. Each is overturnable; the playtest's E5 (U2, and F1's contradiction), E8 and E14 (U3), E6 (U4), E3 (U5) and E2's `Sales` note (U6 -- see §5's WP-10 STAGE 5 finding) produce the evidence. Asked in `tracker/PLAYTEST-RESULTS.md` |
| Q24 | **(d)'s HAND-WRITTEN SCHEMAS WERE SUPERSEDED 2026-09-23 BY Q25 (below): `heading` and `text` are typed `Layout.Widgets.*` modules with GENERATED zod now, and the `Widget.schema` override is deleted; `Sales` renders with no box.** **DECIDED 2026-09-23 BY THE USER: *"Do (a) and (d) now, file (c)."*** (a) BUILT: the rejecting `fetchData` stays, and WP-10's done-when (§14) now names the inline fixture `core/src/test/resources/modules/Doc/SalesReport.e`; `client/src/host/page.ts`'s U6 comment no longer calls F2 a premise that holds. (d) BUILT: native `heading` and `text` renderers (`client/src/widgets/heading.ts`, `client/src/widgets/text.ts`, each with its own hand-written schema through `Widget.schema`, since neither is a `Layout.Widgets.*` module and `WIDGET_PROP_SCHEMAS` is generated), registered in `defaultRegistry()`; client tests 115 -> 121 (118 pass, 3 skip on sbt fixtures). (c) FILED as WP-30 (§14), NOT BUILT, not scheduled. (b), the preview-side inline override, was NOT chosen. **A MEASURED correction to the question as asked:** `Sales`'s three tables are ALL boxes in the panel, not one: `Sales.e` gives `table` a bare relation, which the generated `TableProps` schema refuses (`its props are invalid -- columns.0.column: Required`), and validation precedes the fetch, so the deferred table's box says THAT, not the refusal (`client/test/widgets.test.ts` `(w-sales-panel)`). THE QUESTION AS IT WAS ASKED: **U6 was taken on a FALSE premise, and WP-10's done-when names a report that cannot meet it.** The design review's F2 said the preview never mints a deferred token; `core/src/test/resources/doc/Sales.e:129 (was :116 before the Q21 fix moved it)` asks for `Deferred` itself ("always deferred, whatever the request asks for") and S1's MEASURED capture (`scratch-widget-preview/wp10-s1/captures.json`, `ok-sales`) holds a `kind: "deferred"` table with a token, which the panel refuses (an error box; §5's WP-10 STAGE 5 finding). §14's done-when "`Sales` renders inline" is therefore not met by `Sales` as written | DECIDED (above); it was: Options: **(a)** keep the refusal stub and make an inline fixture the done-when (`core/src/test/resources/modules/Doc/SalesReport.e`, playtest E2/E9/E10); **(b)** a preview-side override forcing inline delivery, so `Sales`'s deferred table arrives inline; **(c)** the fetch message pair U6 deferred (panel -> extension -> `client.sendRequest`, `connect-src` still shut); **(d)** with any of them, register `heading`/`text` renderers so `Sales`'s other two boxes draw. Asked in `tracker/PLAYTEST-RESULTS.md` |
| Q25 | **DECIDED 2026-09-23 BY THE USER: *"I'm pretty sure I want typed widget schemas in the typescript rather than matching runtime ermine values fallibly"*, then *"Rewrite it."* Option (A), plus a PRINCIPLE: the client's widget vocabulary is the TYPED one, whose zod schemas are GENERATED from the Ermine `Layout.Widgets.*` modules; the client never accepts bare runtime values.** BUILT (uncommitted at the time of writing; `scratch-widget-preview/q25/IMPL-REPORT.md`): two new typed widget modules, `core/src/main/resources/modules/Layout/Widgets/Heading.e` (`HeadingProps {title, sortColumn, matched, total}`, constructor `heading`) and `Layout/Widgets/Text.e` (`TextProps {body}`, constructor `plainText`), with generated zod (`client/src/generated/heading.ts`, `text.ts`); the `Widget.schema` override and `(w-own-schema)` are DELETED -- no other widget used the override -- and the invariant is now `(w-generated-only)`: every registered name has a GENERATED schema and no renderer carries one. `core/src/test/resources/doc/Sales.e`'s REPORT BODY is typed (heading, text, three `tabular` tables); its params type is byte-for-byte unchanged and `ermine/schema` for Sales is BYTE-IDENTICAL to `editor/vscode/test/fixtures/sales-query.schema.json` (MEASURED, one `bin/ermine-lsp` boot). The untyped shape the runner tests needed moved to a new fixture, `core/src/test/resources/doc/SalesRaw.e` (TestRunner `(ex)`, TestLspRobustness group D's `data Heading` property, the JSON guide's §9 walkthrough). MEASURED in the panel's terms: every widget of the captured typed Sales document validates against the GENERATED schemas, in range, with today's dates (Q21) and in the burst; `client/test/widgets.test.ts` `(w-sales-panel)` draws it with NO error box. **WHAT (A) DID NOT GIVE WP-30:** a typed table CANNOT FORCE deferral -- `TableProps.rows` is `[..r]`, a bare relation, not `Deferred r` (`Layout/Widgets/Table.e:39-44`) -- and the preview's render request asks inline with no threshold (the request body is params only, `lsp/Preview.scala:1501`), so the typed Sales's items table arrives INLINE and no fixture puts a token in the panel. WP-30's done-when therefore still needs a fixture, and how one should exist is Q26 (see §14) | DECIDED (above). The question as it was asked: **WP-30 needs a report whose table is deferred AND whose props the client validates. Which?** Found by the Q24 review (`scratch-widget-preview/q24-review/REVIEW.md`), MEASURED: `core/src/test/resources/doc/Sales.e` hands `table` a BARE relation (the relation arm itself as props), the generated `TableProps` (`Layout/Widgets/Table.e:39-44`) wants `TableColumn`s plus `rowGroup/sorts/paginate/scroll/rows`, and the dispatcher validates (`client/src/dispatcher.ts:227-229`) before it resolves relations (`:233-236`), so all three of Sales's tables are boxes in the panel and the deferred one never reaches the refusal (`client/test/widgets.test.ts` `(w-sales-panel)`). **The split is DELIBERATE**: `docs/JSON-GUIDE.md:1090-1093` (at b7faef3a) says Sales's `heading`, `text` and bare-relation `table` are outside the typed widget vocabulary and the report exercises the RUNNER, not the client; `Doc/SalesReport.e` is the typed one. `table` is the plain typed shape (`tabular : TableProps r -> Node`, `rows : [..r]`, which may itself be deferred; `Table.e:9-11`, `:50-54`), not the J3i Fetch shape (only `crosstabOf`/`headlineOf`). `Sales.e` is the ONLY fixture using `Deferred`, so nothing today could make WP-30's pair draw a table Options: **(A)** rewrite `Sales.e`'s tables typed (`tabular`): reverses JSON-GUIDE:1090-1093's runner-only role, TestRunner `(ex)` counts relations by the `kind` key and `TableColumn` has a `kind` field (rework), and the S1/panel-answers capture and JSON-GUIDE's walkthrough cites need redoing; **(B)** keep `Sales` runner-only and add a NEW typed fixture with a `Deferred` relation in `TableProps.rows` (a sibling of `Doc/SalesReport.e`): one `.e` file and its capture, and `Sales` stays at three boxes by design; **(C)** the client's `table` accepts a bare relation arm (a `Widget.schema` override or a generator change) and draws default columns from the relation's column descriptors: a second shape for the generated contract, and `(w-own-schema)` needs a third category; **(D)** leave it: WP-30 stays unscheduled with no fixture and this is re-asked when WP-30 is scheduled. Asked in `tracker/PLAYTEST-RESULTS.md` |
| Q26 | **WP-30 needs a TYPED report whose table arrives DEFERRED. How should one exist?** Found by the Q25 review (`scratch-widget-preview/q25-review/REVIEW.md`), MEASURED: `Layout.Widgets.Table.TableProps.rows : [..r]` refuses `Deferred r` ("failed to unify type Relation with type Deferred"); the generated table zod DOES accept the deferred arm; the preview's render request is params only (`lsp/Preview.scala:1501`), so every bare relation arrives inline. So no typed fixture today puts a token in the panel | NOT ASKED YET; blocks WP-30's done-when only. Options: **(a)** change the `Layout.Widgets.Table` contract so a report can force deferral (e.g. a `rows` type admitting `Deferred r`): the generated contract and its zod move, and Table.e's "one schema per widget" comment needs rethinking; **(b)** let the preview's request ask for deferred delivery for a chosen report (e.g. a `data` section beside the params file, or a setting) -- the same knob as Q24 (b) in the OPPOSITE direction (Q24 (b) forced inline and was not chosen): a new preview input and a wire/UX question; **(c)** a test-only fixture that builds the TableProps-shaped record itself (`rawWidget "table"` over a report-local record whose `rows` is `Deferred r`), still validated by the GENERATED zod: an untyped Ermine report, against the spirit of Q25 (its wire shape matching is INFERRED, not measured); **(d)** leave WP-30 without a manual fixture until it is scheduled (the client/page tests already cover the refusal box with a hand-built document, `client/test/page.test.ts` `(pg-fetch-deferred-box)`). Asked in `tracker/PLAYTEST-RESULTS.md` |
| Q27 | **DECIDED 2026-09-24, option (i), BUILT AS WP-34 (not reviewed, not committed).** The user, after `Doc/SalesReport.e` was refused: *"we should fix SalesReport.e also: currently cant preview it on account `report` binding signature issue"*; the orchestrator chose option (i) (fix the RUNNER, not the example) and told the user: a binding of type `Node` or `Fetch Node` is a report with NO parameters, rendered with `{}` or no `params` and applied to nothing; any key is a 400 at `$.params`; `ermine/schema` answers `{"parameters": false}` and the extension writes no params file (§4, WP-34). `SalesReport.e` is unchanged and renders (scorecard, table, axisChart, pieChart; MEASURED, `scratch-widget-preview/wp34/IMPL-REPORT.md`). THE ORIGINAL QUESTION, KEPT AS HISTORY: **A zero-parameter binding (`report : Node`) is offered by the picker but refused at render. Which side moves?** Found by the first playtest (F2, 2026-09-23, MEASURED by the user): `Doc/SalesReport.e` → `report` answers 400 *"Doc.SalesReport.report is not a report: a report must be a function Params -> Node, not Node"* (`json/Decode.scala:122-140`); the picker lists bare `Node` knowingly (`lsp/Definitions.scala:393-397`). Options: **(i)** the runner treats `Node` as `{} -> Node` (an empty params record; the picker stays as it is, `SalesReport` renders, E10 gets its fixture back); **(ii)** `SalesReport` gains a parameter and the picker stops offering bare `Node` (the runner's rule stands; the picker and the README agree with it). Meanwhile: README corrected (0.1.15), checklist E1/E2/E9 use `Sales.e`, E10 has NO FIXTURE. **NOT ASKED YET.** | E10; WP-10 done-when wording |
| Q28 | **Should the panel's JSON view show the RAW wire answer?** Found building WP-31 (2026-09-23, READ): the extension posts the panel reducer messages, not the answer (`preview-core.js` `panelMessagesFor`/`panelErrorMessage`), so after a failure the JSON view shows `{status, message, path, reason}` where the JSON tab shows the whole `{ok:false, status, message, path, reason, generation, stale?}`; `message` may carry the fast-mode suffix or the writers note; and a missing writers bundle is an `error` (status 0) that the JSON view shows even over a good document. Options: **(a)** forward the last answer verbatim to the page (e.g. an `answer` field on the snapshot envelope, beside `messages`) and show `tabContent(answer)` byte-for-byte: an EXTENSION change (a new `.vsix`), and the envelope grows by one document per post; **(b)** leave it (the document case is already exact; the gap is stated in `client/README.md`). **NOT ASKED YET**; offered, not built. | nothing; WP-31's error case only |

**Q4, in full** (found by the WP-4 review, 2026-09-20). A module that failed to load is in
neither `loadedFiles` nor `loadedModules`, and `Runner.invalidate` derives its module set from
exactly those two (`json/Runner.scala`, step 1 of its doc comment: `Session.loadedByPath`, then
`Session.moduleUnder(cfg.roots, p)` filtered by `loadedModules`). So after a render answers 500
"module does not load", saving the fix invalidates NOTHING: `invalidate` answers the empty set,
no `ermine/preview/invalidated` goes out (§3 step 5 sends nothing for an empty set), the
extension never re-renders (§3 step 6), and the panel keeps the 500 banner until the user picks
the report again. The same is true of a file the broken module imports. The resident meets the
same shape and compensates with a `pendingReload` set -- the modules a reload scrubbed and could
not load back, retried by the next reload (`lsp/Resident.scala:179`, `:182`, `:197`, `:219`);
`Runner` has no equivalent, because until WP-4 it never scrubbed. Options, none built:
(i) a `pendingLoad` set in `Runner`, named by every `compile` that fails, returned by any
`invalidate` whose paths name a module under a root whether or not it is loaded -- the resident's
answer, in the runner; a `Runner` change, so a **follow-up to WP-4**;
(ii) the extension re-renders on ANY `.e` save while its last answer was a load failure -- no
server change, one wasted render per save in the broken state; lands in **WP-7**, the extension;
(iii) the server sends `invalidated` for every watched change while the last render failed to
load -- the same rule, moved to the server, where it knows what "the last render" was; lands in
**WP-5**, the `Preview` object that owns the queue and the notification.
Whichever is chosen, the loop only closes in the extension, which is why the table says WP-7.
It does not block WP-4 or WP-5: `Runner.invalidate` is exactly as specified in §3 step 4 and
§11's Runner row ("`invalidate` of an unloaded path is a no-op") stays true whichever option
wins -- (i) would make a *failed* module no longer count as unloaded, which is a change to what
is loaded, not to the rule.

**DECIDED by the user on 2026-09-20: option (i), and BUILT** as a follow-up to WP-4. `Runner`
keeps a private `pendingLoad` set, added to at the one place a load is ATTEMPTED (`compile`,
after `Session.loadModules`, when the module is still not in `env.loadedModules`) and removed
from whenever a `compile` leaves the module loaded -- so a 404 for an unknown binding, a 400
signature refusal and an evaluation error all take a module OUT, while a module no root has and
a malformed module name are refused before any load and are never recorded. `invalidate` unions
the set into its answer whenever its paths name at least one module: a loaded one through
`loadedFiles`, or an UNLOADED one under a root (which is what the fix to a broken report looks
like on the wire). A pending module is NAMED and nothing else -- not scrubbed, nothing evicted
for it -- which is all `Preview` needs to send `ermine/preview/invalidated`; that job is
unchanged. `invalidateStale` does NOT union the set, because the render it heads is about to
retry the load anyway and because the mtime scan must go on sending no notification. The set is
bounded at `Runner.maxPendingLoads` = 32, oldest first. The cost, stated rather than hidden:
while a report is broken, saving ANY `.e` file under a root costs one extra render attempt of
it. The loop still only CLOSES in the extension (WP-7), which now has an `invalidated`
notification to act on. "`invalidate` of an unloaded path is a no-op" holds exactly whenever
nothing is pending, and its other two paths -- a file under no root, a directory -- name nothing
even when something is.

**TWO TIGHTENINGS, found by the review of this follow-up (2026-09-20) and BUILT.**
(1) *A pending module can be LOADED.* Report `A` imports a broken `W`, so `A` is pending; `W` is
fixed; a later `compile(B, _)` for a `B` that imports `A` loads `A` as a DEPENDENCY, and nothing
but `compile(A, _)` would have taken `A` out -- so every module-naming `invalidate` from then on
named a module that was loaded and healthy (the reviewer's probe:
`invalidate(B.e) = List(Q4A, ...)   (A is loaded and healthy: true)`). `invalidate0` now PRUNES
the loaded modules out of the set, under `evalLock`, before the `nonEmpty` gate and before the
union, which makes the set's invariant true wherever it is read: **it holds only modules that
are not loaded**.
(2) *A pending module whose file is DELETED.* It stayed pending for the life of the `Runner` and
every module-naming `invalidate` carried the dead name, because the retry's pre-load 404 ("no
module named X") did not clear it. That branch now clears it: a file no root has cannot be fixed
by a save of something else, and the retry IS the answer to "is it back?".
**The cost, stated:** in the worst case up to `Runner.maxPendingLoads` = 32 names ride along on
one `invalidate`, so a client with several broken reports open pays one render attempt for each.
**The partial-load doubt is SETTLED** (this review): `Session.loadModule` writes every env table
only after type inference and the overwrite checks, so a load that died leaves nothing of the
module behind -- the retry is an ordinary load and no scrub of a failed module is needed
(probed with a module of two `data` declarations and a late failing term: retried 200, including
when the fix widens the data shape and when broken and fixed a second time).

**Q5, in full** (found while building WP-5 stage A, 2026-09-20). §2.4 puts the picked
report's **own inferred root** in the render session's root set, and §4 promises
`404 "not under a module root"` for a file under none of them. Together these cannot both
bite: any readable file whose header parses is, by construction, under the root its own
module name implies, so the 404 is unreachable for it. **As built**: both, literally. The
404 therefore fires exactly when no root can be **inferred** -- an unreadable, non-existent
or unparseable file (a report the developer deleted while the panel still points at it), or
a path that is not a `.e` file at all. That is a real case and the group-D property pins it,
but it is not what §4's sentence sounds like. Options: (i) reword §4 to say what
the 404 means (no root could be inferred and none was configured); (ii) drop `inferredRoot`
from §2.4 and require `ermine.preview.roots` for anything outside `moduleRoots`, which makes
the 404 mean what it says and costs every single-segment module a setting -- the thing §2.4
added `inferredRoot` to avoid. It blocks nothing: WP-7 is where the picker decides what to
send, so the answer is wanted before that.

**DECIDED by the user on 2026-09-20: option (i), and BUILT.** `inferredRoot` stays in the root
set -- it is §2.4's zero-configuration promise and WP-7's done-when -- and the 404 is made
honest instead. `Preview.inferredRoot` now answers `Either[String, String]`, carrying the
REASON it could infer nothing, and the render's 404 says it: "not an Ermine source file:
`<name>`" (the path is not a `.e` file, which is the one case `moduleUnder` refuses on its
own), "cannot read `<name>`" (deleted or unreadable -- the stale-pick case), "no module header
could be read from `<name>`", or "the module header of `<name>` names `<module>`, which is
deeper than the directories above it". The FILE NAME only: the exception's own text carries an
absolute path (`Session.Filesystem.contents` dies with "File '<path>' does not exist.", and a
parser error carries the source name it was built with), so it goes to the server log and not
to the wire; the message still passes through `failure`'s scrub and `generation` is still
echoed. The root is inferred ONCE per render, before `rootSet`, so the honest message costs no
second read of the file. **Q6 remains open and is linked**: the inferred root is exactly why
previewing a report in a second directory discards and re-boots the render session.

**Q6, in full** (same origin). §2.4 makes the root set immutable config and says a change to
it **discards the `Runner`**; `inferredRoot` puts the picked report's own directory in that
set. So previewing report A in one directory and report B in another discards and re-boots
the render session on every switch, in both directions, for ever. **MEASURED**: 2.3-7.3 s per
boot for the group-D fixture (`TestLspRobustness`, the render-session group's own `collect`
label across four runs), which loads `Lib.preamble`, `Layout.Doc` and `Layout.Fetch` over the
stdlib source root. A real workspace's report is **unmeasured** and will be slower. Options,
none built: (i) accept -- a developer works on one report at a time, and the panel shows
progress (stage B); (ii) keep a small map of `Runner`s keyed by root set, evicting the
least-recently-used, which multiplies the memory of §2.2 by however many are kept;
(iii) drop `inferredRoot` from the **discard key** while keeping it in the roots -- unsound
as stated, because the runner's loader chain really is different, so it would mean rebuilding
only the loader, which `RunnerConfig` does not allow today.

**DECIDED by the user on 2026-09-20: a REFINEMENT of (i), and BUILT.** Not "accept", and not
the cache of (ii): the inferred root is not added AT ALL when the configured roots already
place the file, which removes the re-boot in the case that caused the question -- two reports
in two directories that are both in `ermine.preview.roots` -- and leaves everything else
alone. WHAT WAS BUILT, in four lines. `Preview.rootSet` now computes the CONFIGURED roots
first (`moduleRoots` then the request's, normalised, distinct) and adds the inferred root only
when `configuredPlaces` is false. `configuredPlaces` is two tests and both are needed:
`Session.moduleUnder(configured, path)` must answer the module name the file's own HEADER
declares (it takes the first root in the list that CONTAINS the path, so a root above the
file's own would name it something else), and `resolvedFile` -- the LOADER's question, the
first configured root that has `<root>/A/B.e` -- must answer THIS file, which is what keeps a
report picked under a later root from being rendered out of an earlier root's copy of the same
module name. `inferredRoot` answers `Either[String, Placed]` so the header's module name is
available beside the root and the file is read and parsed ONCE, with Q5's four honest failure
reasons unchanged. `ensureSchemaSession` is untouched, the wire is untouched (404 texts, the
400s, the 503, the generation echo), and zero configuration is untouched: a file under none of
the configured roots still gets its own root and still re-boots, which one of the three new
group-D properties pins. **IT NEVER CHANGES THE SET, ONLY THE ORDER** -- when the test passes,
the inferred root is provably one of the configured entries, so `distinct` would have dropped
the duplicate anyway and only its POSITION was ever at stake -- and §2.4 records the one
consequence: for a module NAME that exists under two configured roots, the configured order
now decides, where the inferred root used to give the picked file's directory the first say
ahead of `ermine.preview.roots`. The picked report's own module is exempt by the second test.

**THE CACHE OF OPTION (ii) IS NOT BUILT**, and the number that decision would turn on is now
measured: stage C's instrument (§2.2) puts a second session at **about 60 MiB of RSS and 8 MiB
of live heap** on the `Sales` fixture, against the launcher's 2 GiB default. That is small
enough that keeping two or three `Runner`s would cost little heap -- and it is also small
enough that the refinement above removes the switch cost without spending any. If a later
ticket wants (ii) as well (for roots that genuinely differ -- a report outside every
configured root), those are the figures to argue from, and the fixture is not a real
workspace's report.

**Q7, in full** (found while building WP-5 stage B, 2026-09-20). §4's row gives
`ermine/schema` the keys `{module, binding}` and nothing else, and §6 says the binding form is
answered from the render session. But the render session's roots are computed per render from
`moduleRoots ++ inferredRoot(uri) ++ request roots` (§2.4), and a schema request names no
`uri` and no `roots`, so it cannot compute them. **As built**: a schema job answers from the
session A RENDER BOOTED, whatever its roots are, and boots one over `ermine.moduleRoots` alone
only when there is none. It must not do anything else: calling `ensureSession` with a
root set of its own would DISCARD the render session whenever the sets differed (§2.4), making
a schema request cost the next render a boot. TWO CONSEQUENCES OF THE FALLBACK, both found by
the stage B review: (a) it can answer WRONGLY and not merely "no module named ..." -- if a
module of the SAME NAME exists under the resident's `moduleRoots`, the schema exported is that
module's, not the workspace report's, and the difference is invisible to the client; this
cannot arise once a render has booted the session, which is the only order §6's loop uses;
(b) the session it boots has the resident's roots, so the FIRST RENDER after it discards that
session and boots again (§2.4's root-set rule), which is a second boot the user waits for. In §6's own loop the render comes first (the
panel renders, then the extension writes the params skeleton from the schema), so the failing
order is the unusual one; §3 step 6's refresh is also after a render. Options, none built:
(i) accept, and have the extension render before it asks (it already holds the picked (file,
binding)); (ii) give `ermine/schema`'s binding form a `uri` and `roots` like `ermine/render`,
so it computes the same root set -- new wire surface, §4's to decide; (iii) let the preview
remember the last root set it booted and re-boot with it, which differs from (i) only after a
`discard`. It blocks nothing: WP-8 is where the extension decides when to ask.
**A THIRD CONSEQUENCE, found by the Q6 review (2026-09-20) and recorded here because it is
the same question, not a new one**: the resident's `moduleRoots` always LEAD the root set,
so a PICKED report whose header names a module that also exists under a resident root is
not the file the render loads -- the resident's copy is. Q6's refinement leaves that exactly
as it was (the inferred root was always spliced after `moduleRoots`, never before them), and
whether the picked file should out-rank `moduleRoots` is part of this same decision. Nothing
is built for it.

**DECIDED by the user on 2026-09-20, BOTH PARTS, and BUILT.**

**(1) The binding form identifies the report the way a render does**: `{uri, binding, roots}`
-> the schema, or `{error}` -- option (ii) of the three above, which §4's row now records.
It computes the module and the root set with EXACTLY the functions a render uses, because the
front half of `doRender` was FACTORED OUT and both go through it
(`Preview.placeAndSession`): the path from the `uri`, `inferredRoot` with Q5's four honest
reasons kept in its `Left`, `rootSet` with Q6's rule, `ensureSession`, §2.5's mtime scan,
`Session.moduleUnder` over the FINAL roots, and Q7's own shadow test. It answers either
"cannot serve, and here is the reason and the status" or the module; each caller then dresses
that in ITS OWN SHAPE -- §4's `{ok:false, status, message, generation}` for a render,
`{error}` for a schema -- and does its own work (the 503 "not connected" and the document
under the size cap; or `paramSchema`). So a schema and the render that follows it share ONE
session in either order, a first-pick schema for a workspace module works, and a same-named
module under another root cannot be described by mistake.
THE THREE CONSEQUENCES, each as decided:
 - `ensureSchemaSession` AND ITS `moduleRoots`-ONLY FALLBACK ARE GONE, with both of the
   stage B review's failures: (a) the wrong module of that name, and (b) the second boot the
   first render used to pay. The schema's error texts now carry a render's reasons word for
   word, scrubbed, file names only.
 - PROGRESS: a schema that will boot now MINTS A BOOT TOKEN, through the very same
   dispatch-side `mintBootToken`, on the very same thread, under the very same
   at-most-one-outstanding-`create` rule (the `bootToken` CAS and `createPending`). It is
   three lines and no new mechanism -- `progress` moved from `Render` onto the `Answering`
   trait -- and it is now WORTH having, because a first pick boots ON THE SCHEMA REQUEST,
   which is exactly when the user is waiting. §2.5's "TWO BOOTS REPORT NOTHING" therefore
   loses its second case: only Q6's root-set change INSIDE one render OR ONE SCHEMA is still
   silent (a schema can now move the root set too, so the case is not a render's alone).
 - THE OLD `{module, binding}` FORM IS NOT KEPT. There is no extension code yet (WP-7/WP-8),
   so a compatibility path would only preserve the wrong-module hazard: a request with
   `binding` and no `uri` is `{error}` naming the missing key. The `type`/`name` forms on the
   resident are untouched, and `Definitions.scala` still branches on the PRESENCE of
   `binding`.
The watchdog, the queue's rules (one render in flight, latest wins, a schema never displaced),
cancel, stuck, shutdown, the boot bracket and the arm epoch are UNCHANGED for schema jobs:
verified against the code and the group-D properties, not re-designed.

**(2) A shadowed pick is an error, not a silent substitution.** The resident's `moduleRoots`
keep LEADING the chain -- §2.2's reason stands: both sessions must register EQUAL SHAPES for a
shared module name, and that is what leading buys. But when the FINAL root set resolves the
picked file's module name to a DIFFERENT file (the loader's own first-existing-file rule,
`resolvedFile`, which Q6 added), neither a render nor a schema may use the other file:
the render answers `{ok:false, status: 409, message, generation}`, the schema `{error}` with
the same text, and nothing is loaded. **409** because nothing about the request is malformed
(400), the module IS found (404), and the render never ran (500); it needs no new vocabulary
anywhere -- `Preview.failure` takes a status NUMBER, and `json/Runner.scala`'s `RunError`,
which the HTTP server shares, is not on this path and is untouched.
**WHAT IS PRINTED**: the picked file's NAME (the request supplied its URI), and the SHADOWING
FILE'S PATH together with the ROOT it sits under. Rule A5 is about JDBC URLs, hosts and
credentials, and this message goes through the same scrub as every other; the shadowing file
is an Ermine source file in a directory the CLIENT or the SERVER configured as a module root,
not a secret, and naming it is the only useful thing the answer can say -- "something shadows
this" would leave the developer with nothing to look at.
**WHICH ROOTS CAN STILL SHADOW, worked out and pinned rather than assumed.** A resident
`moduleRoots` entry, ALWAYS: it precedes everything in both branches of `rootSet`. And a
CONFIGURED root, but only when no root could be INFERRED for the pick (an unreadable file, a
header that does not parse, a module name deeper than the directories above it) while the path
is under a configured root all the same -- `rootSet` then has no inferred root to splice in,
and before Q7 that case rendered the other file silently. **WHICH CANNOT**: an earlier entry
of `ermine.preview.roots`. Either the configured chain already resolves the module back to the
picked file (Q6's test (2)), or it does not and the file's own inferred root goes in AHEAD of
`req.roots`. That covers the case the question asks about explicitly -- the inferred root
EQUALS a LATER configured root, i.e. the file is picked in `B` while `A`, listed first, holds
the same module name: test (2) fails, `B` is spliced in ahead of `A`, and the pick wins. Test
D "one name, two roots" is exactly that case and is unchanged.
The check costs what `resolvedFile` costs -- at most one `File.exists` per root, no read, and
one `Files.isSameFile` on the would-be-refusal path -- and it runs BEFORE THE LOAD, between
`moduleUnder` and `renderText`/`paramSchema`, so nothing of the wrong file is ever parsed,
typechecked or evaluated.

**TWO SPELLINGS OF ONE FILE ARE NOT A SHADOW** (the review's must-fix, 2026-09-20, BUILT).
`Session.normalize` is `toAbsolutePath.normalize` (`Session.scala:733-735`): purely syntactic,
it does not follow a symbolic link. So one directory reachable under two spellings -- a
symlinked workspace, where `moduleRoots` holds `/data/proj/reports` and the editor sends
`/home/me/proj/reports/Rpt.e` -- made the first cut refuse a legitimate pick 409, naming two
paths that are the SAME FILE. That configuration rendered before Q7, so this was a regression
and not a new refusal. The string test is now the FAST path and `Preview.sameFile`
(`Files.isSameFile`, false on ANY throwable, asked only when the two strings already differ)
decides. **Q6's `configuredPlaces` test (2) got the same one-line tolerance**, for the same
reason: the stakes there are lower -- a mismatch only splices the inferred root in, which is
benign and costs a re-boot -- but it is literally the same question, and two answers to it
would be exactly the drift the pair of tests exists to prevent. One group-D property pins the
symlinked pick; where the platform refuses symbolic links it SKIPS LOUDLY, with a `collect`
label in the suite's own report, rather than passing quietly.

**WHERE THE CHECK SITS, decided by the orchestrator and recorded rather than left implicit**:
AFTER `ensureSession`, which is where `doRender` already put the boot. Moving it earlier would
change which refusal WINS among the 400, the 404 and the 500 a failed boot answers, and the
boot is not wasted work -- it is the session the next request reuses. A shadowed FIRST pick
therefore still pays the boot it would have paid, and is then refused.

**WHAT PART 2 DOES AND DOES NOT PROTECT, neutrally.** It fixes the silent WRONG-FILE render:
a picked file whose module name a root earlier in the chain also holds is refused instead of
quietly replaced. It does NOT by itself guarantee §2.2's equal-shapes invariant, because a
workspace module can still RE-DEFINE THE NAME of a module the resident got from the
CLASSPATH -- as the pick itself, or through an import -- and `resolvedUnder` never sees the
classpath, which `Runner` appends AFTER the roots (`Runner.scala:313-316`). That hole is
pre-existing, is unchanged by Q7, and nothing is built for it.

**Q8, in full** (same origin). §2.5 says the watchdog answers the request "in a notification
carrying the **Ermine: Restart Language Server** button (`ermine.restartServer`)", and §4 says
"the render watchdog therefore uses a `Timer` thread and the synchronised `send`, not the idle
slot" -- i.e. `notify`, never `ask` (§2.3's thread rule). Those cannot all hold: the LSP
specification's server-to-client NOTIFICATION that shows a message, `window/showMessage`, has
only `{type, message}` (*external*); the shape that carries actions,
`window/showMessageRequest`, is a REQUEST whose response names the chosen action, and `ask` is
dispatch-thread-only. **As built**: `window/showMessage` with `type: 1`, whose text NAMES the
action -- "run \"Ermine: Restart Language Server\" (ermine.restartServer)" -- and the clickable
button is the panel's banner, which is where resolution A4 already puts it ("Lands in WP-7").
Options, none built: (i) accept -- the message names the command, the panel has the button;
(ii) issue `window/showMessageRequest` from the dispatch thread, which needs a way to wake that
thread with no client traffic: the one idle slot is the diagnostics debounce's (§4), so it
would mean a second idle hook in `Rpc.scala` and a dispatch loop that polls while a message is
pending; (iii) a custom `ermine/preview/stuck` notification carrying `{message, command,
title}`, which the extension turns into a button -- a new §4 row, and not a standard LSP
mechanism. It blocks nothing: WP-7 owns the banner either way.

**THE QUESTION'S OWN RATIONALE WAS WRONG, and the correction is the first thing to record
(design review, 2026-09-20).** Option (ii) is not blocked by REACHABILITY. The dispatch
thread is perfectly able to `ask`: the very next `ermine/render` a stuck preview refuses is
handled ON that thread, and it could issue a `window/showMessageRequest` there with no idle
hook and no polling at all. What actually kills (ii) is the SHAPE OF THE ANSWER: the response
to `window/showMessageRequest` names the chosen action **to the server**, and the LSP gives a
server no way to make the client run a CLIENT-SIDE command -- `ermine.restartServer` is the
extension's own, registered in `extension.js`, and `workspace/executeCommand` runs the other
way round (*external*, unverified here). So the button would light up and do nothing unless
the extension implemented it, and if the extension is implementing it, WP-7's banner is the
better place: it is visible without a modal, it survives the message being dismissed, and
resolution A4 already put it there.

**DECIDED by the user on 2026-09-20 ("per the orchestrator's recommendations"), AS CHANGED BY
THE DESIGN REVIEW, and BUILT**: option (i) is kept -- the message NAMES the action and the
button is the panel's -- and option (iii) is added ALONGSIDE it, not instead of it, in the
narrow form the review specified. Two things ship.

**(1) A STUCK-ONLY MARKER ON THE ANSWER.** `"stuck": true` rides on §4's render failure shape
and beside `ermine/schema`'s `error`, on **exactly four** answers: the two refusals `render`
and `schema` send while stuck, the watchdog's own answer, and each answer of the queue drain
the watchdog performs. **NOT on the job CRASH handler's 500**, and not on any other refusal.
That distinction is the whole design and it is enforced by the TYPE: `Answering` has two
methods, `refusal` (the crash handler's) and `stuckRefusal` (`withStuck(refusal(...))`), and
the marker lives only in the second. The review's must-fix was exactly this -- the first
recommendation put the flag inside the shared `refusal`, which would have told the panel that
every ordinary 500 from a broken report was a wedged preview, and no test over the stuck paths
alone would have noticed. The crash-handler property now carries the conjunct that does
(§11).
**THE `-32800` PATHS CARRY NO MARKER, and cannot**: a displaced render, a cancelled one, the
shutdown drain, and the watchdog's answer to a request that had already been CANCELLED are
JSON-RPC ERRORS -- `{code, message}` and no result object -- so there is nowhere to put a
field. Those clients learn the state from the notification below instead. Written down here
because it looks like an omission and is a consequence of the wire shape.

**(2) `ermine/preview/stuck {stuck: true|false, message}`**, a new §4 notification row.
`true` is sent by the watchdog's `fire`, from the TIMER thread, **beside** the existing
`window/showMessage` and not instead of it -- the standard message is what any LSP client
shows without knowing this server at all, and the custom one is what carries a state a banner
can hold. `false` is sent at Q10's recovery, from the PREVIEW thread, together with a
`window/showMessage` of the INFO type. Both go through `notify` and never `ask` (§2.3's
thread rule), outside the queue's monitor, each send separately guarded, and through the §8.1
scrub.

Files: `lsp/Preview.scala`, `TestLspRobustness.scala`, this document. No `editor/vscode` file:
the button is WP-7's, fed by this field and this notification.

**Q9, in full** (found while building WP-5 stage B, 2026-09-20). `applySettings` accepts
`ermine.preview.timeoutSeconds` in 0..3600 and treats **0 as "no watchdog at all"**: no timer
is armed, a render may run for ever, and the preview never becomes stuck. Nothing in §2.5 asks
for an off switch; the argument there is the opposite one -- "the watchdog exists so the user
is told at 60 s rather than at OOM" -- and a developer who turns it off gets a preview whose
only remaining bound is `-Xmx` and the restart that follows it (stage C). It was built this
way because a range that starts at 1 has no way to say "do not watch", and because the
group-D properties need a way to disable the watchdog while they set a queue up. Options,
none built: (i) keep it, and document 0 in the setting's description as "no watchdog";
(ii) refuse 0 like any other out-of-range value, and give the properties their own seam
instead of the setting; (iii) keep 0 but say it once through `window/showMessage` when it is
applied, so a preview that will never time out is never a silent surprise. It blocks nothing.

**ONE OF THE QUESTION'S OWN REASONS IS FALSE, and is struck here rather than carried forward
(design review, 2026-09-20).** "It was built this way ... because the group-D properties need
a way to disable the watchdog while they set a queue up" is not true of any property in the
suite: every one of them writes `Preview.timeoutMillis` -- the `private[reporting]` FIELD and
test seam -- directly, and not one of them ever calls `applySettings`. So the setting owes the
tests nothing, and option (ii) was never blocked by them. It is refused on its own merits
below.

**DECIDED by the user on 2026-09-20, AS CHANGED BY THE DESIGN REVIEW: option (i), and NO
MECHANISM IS BUILT.** `0` stays the off switch and keeps its existing log line,
"`timeoutSeconds = 0 (the watchdog is off)`". No `window/showMessage` on apply -- option (iii)
is refused because `workspace/didChangeConfiguration` fires on edits to unrelated settings and
a modal that reappears whenever the user changes their font size is worse than the silence it
replaces; the log line is the record, and WP-7 will document "0 = no watchdog" in the
setting's own description, which is where a developer looks before they type it.

**NOTHING SENDS THESE SETTINGS YET, which is why this costs nothing today.** VERIFIED in the
extension as it stands: `editor/vscode/src/extension.js:159` sends
`initializationOptions: { fastMode: ... }` and `:266-267` sends
`settings: { ermine: { fastMode: ... } }` -- `fastMode` and nothing else. `timeoutSeconds` and
`maxDocumentBytes` reach `Preview.applySettings` only from a client that writes them by hand,
until WP-7 exports them.

**WHAT `0` DOES NOT REMOVE, stated because "off" reads as "unbounded" and it is not:**
 - **the heap bound is still there and can arrive first.** MEASURED (§2.5): the `WpBlow` run
   died at **8.6 s** with the shipped **60 s** clock still running. A watchdog turned off
   changes nothing about `-Xmx` or `-XX:+ExitOnOutOfMemoryError`; for an allocating runaway
   the clock was never the binding constraint;
 - **nothing drains the queue.** `fire` is the ONLY drain -- `render` and `schema` refuse NEW
   requests once stuck, but a job already queued behind a wedged one has no other reader, and
   a schema job has no displacement rule that would remove it either. With the watchdog off
   there is no `fire`, so a wedge accumulates **one blocked client request per schema asked**
   (§6's ordinary loop asks for one per pick) until the process dies. That is the real cost of
   the off switch, and it is the argument for raising the value rather than turning it off.

**THE HONEST REMEDY FOR A LEGITIMATELY SLOW SCAN is Q10 plus a bigger number**, not `0`: Q10
makes a wedge that resolves itself end by itself, so a timeout set slightly too low now costs
a banner and a re-render rather than a restart.

**ONE PROPERTY WAS ADDED** (§11, group D; no bench, no boot, 0.0 s): `0` sets the field and
logs it once; `3601` and a `timeoutSeconds` that is a STRING are each refused, out loud,
naming what arrived, and leave the field exactly where `0` left it. There was no property on
`applySettings` at all before this.

**Q10, in full** (same origin). §2.5 says the watchdog "marks the preview stuck, and every
later `ermine/render` is answered the same way without queueing", and says nothing about the
state ever ending: as built `stuck` is set once and never cleared, so the remedy is the server
restart the notification names. But the wedged evaluation CAN come back -- a `Fetch` that was
merely slow, a scan that hit the 300 s statement timeout (§2.5's own row) -- and the preview
thread is then alive, idle and refusing everything until the user restarts a process that is
working. After the stage B fix the queue is EMPTY at that moment (the watchdog drains it), so
clearing `stuck` would leave no half-answered state behind. Options, none built: (i) keep it
permanent, which is what §2.5's sentence literally says and what the restart action assumes;
(ii) clear `stuck` when the wedged job finally ends, and send a second notification saying the
preview is working again; (iii) clear it only when the job ends AND the session is discarded,
so nothing evaluated under a poisoned heap survives -- which is also what WP-6's cooperative
cancel does to the runner. It blocks nothing, and WP-6 is where the same question is asked of
a cancel.

**DECIDED by the user on 2026-09-20, AS CHANGED BY THE DESIGN REVIEW: option (ii), and
BUILT.** `stuck` clears WHEN THE JOB THE WATCHDOG FIRED ON ACTUALLY RETURNS, and at no other
time. Not option (iii) as written -- the discard is not conditioned on the heap -- but **the
recovery DOES discard the render session when the wedged job ended by THROWING**, which is
option (iii)'s mechanism applied for the reason that actually holds. The first cut of this
text said "a job that came back of its own accord poisoned nothing"; **that was FALSE for the
exception case** and item 1b below is the correction.

**WHAT WAS BUILT, in seven parts.**
 1. **WHICH job.** `fire` records `stuckJob` in the same locked step that sets `stuck`, and
    `runJob`'s `finally` -- the one place in the file that knows a job has really finished --
    clears the three fields through ONE `clearStuck(reason, onlyFor)` under the queue's
    monitor, only when the job that just ended IS that one. `clearStuck` takes `null` for
    "whatever the watchdog fired on", which is the shape WP-6's cancel will reuse rather than
    write a second, subtly different version of. It also mints the `seq` of item 6.
 1b. **A WEDGE THAT COMES BACK *FAILED* LOSES ITS SESSION; ONE THAT COMES BACK *OK* KEEPS IT**
    (DM-1 of the first Q8-Q12 review, **with its witness corrected by DD-1 of the second**).
    `Runtime.swhnf` captures a `NonFatal` failure as `Bottom(throw e)` (`Runtime.scala:231`)
    and `writeback` memoises that value into EVERY thunk on the chain (`:245-250`) --
    including the render session's SHARED bindings, which outlive the render. So a wedge that
    came back failed leaves a session in which those bindings re-throw the OLD failure for
    ever, while the recovery tells the panel the preview is serving renders again. **§2.5's
    own WP-6 row already says this of a cancel** -- "the unwinding thunk writes `Bottom` back
    into the thunks on its chain, which poisons the render session's stdlib thunks, so a
    cancel **discards the `Runner`**" -- and it is the same mechanism, so it gets the same
    answer.
    **THE FIRST CUT KEYED THE DISCARD ON `threw`, AND THAT WAS THE WRONG WITNESS.** The
    poisoning path that MATTERS returns NORMALLY: `Encode` turns a `Bottom` into
    `Left(bottom(...))` (`Encode.scala:295`, `:242`, `:514`, and `Doc.scala:212-214`) and
    `Runner` nets every `NonFatal` failure into `Left(Failed(...))` (`Runner.scala:508`,
    `:845`, `:883-886`, `:929-930`), which `doRender` answers as a **500 by returning**. So
    after a wedge that came back FAILED, `threw` was false, nothing was discarded, and the
    panel was told the preview served again over memoised failures. The only throws
    `runJob`'s catch ever sees are what escapes those nets -- an `Error`, a `ControlThrowable`,
    or this file's own front half -- which is why a property that throws from `beforeJob`
    proves the mechanism and **not** its reachability.
    **THE WITNESS IS NOW THE OUTCOME.** `doRender` and `doSchema` record, where they answer,
    whether the answer was an EVALUATION failure, and `runJob`'s `finally` discards when the
    stuck state was cleared for this job AND (`threw` OR that flag). **THE RULE IS A `RunError`
    OF STATUS >= 500 out of `renderText`/`paramSchema`, which is exactly `Runner`'s `Failed`**,
    and `Failed` is minted at precisely the sites that net a FORCING failure (the four cited
    above). Deliberately excluded, each because nothing of the report was forced: `BadRequest`
    (400) -- a params object that does not decode (`Runner.scala:873`), a binding whose
    signature is not a report -- and `NotFound` (404), both decided before or beside forcing;
    this file's own 400/404/409 from placement and its 500 for a boot that failed (which
    `ensureSession` has already thrown away); the 503; and **this file's own 500s after a
    SUCCESSFUL render** -- the document-size cap and "the rendered document is not JSON" --
    where the evaluation completed and wrote real values back.
    **IT FIRES ONLY AFTER A WATCHDOG FIRE.** An ordinary, un-wedged 500 sets the flag and
    nothing happens, because the `finally` reads it only when the stuck state was cleared for
    that job. The un-wedged case is **Q14's**, and it is the user's.
    **WHAT THIS COSTS, plainly**: a slow scan that ends in its own 300 s `setQueryTimeout`
    (§2.5's row) AFTER a watchdog fire now costs ONE re-boot of the render session -- §2.2
    measures a boot at 1.9-7.3 s -- because that answer is a `Failed` and this rule cannot
    tell it from a memoised failure without looking inside the session. The same failure
    WITHOUT a fire costs nothing. A wedge that comes back with `ok: true` costs nothing
    either, and a property pins that.
    **THE ORDERING TRAP, found by the review and written into `clearStuck`'s scaladoc for
    WP-6**: `post`, `discard()` and `invalidate` all refuse while `stuck`, so a discard posted
    BEFORE the clear is silently dropped and one posted after it lands behind whatever else
    has arrived. The recovery therefore clears FIRST and then calls the private,
    preview-thread `discardSession` directly, which is neither queued nor refusable. WP-6's
    cancel runs on another thread and has no such shortcut.
 2. **NEVER ON A `java.lang.Error`, AND NEVER ON ANYTHING THE RUNTIME DOES NOT CAPTURE.** The
    test is `e.isInstanceOf[Error] || !NonFatal(e)` -- **TWO independent halves**. The first
    cut had only the first, which the review (DM-2) showed was not enough.
     - `isInstanceOf[Error]` asks **is this JVM still believable**. `java.lang.Error`'s own
       contract is the argument (*external*, its javadoc: "indicates serious problems that a
       reasonable application should not try to catch"); it covers `OutOfMemoryError` through
       `VirtualMachineError`, `LinkageError` and `AssertionError`, plus whatever a future JDK
       adds, with no list here to go stale. `NonFatal` alone would not do: it classes an
       `AssertionError` as non-fatal, so an assertion that blew up inside the evaluator would
       announce "recovered".
     - `!NonFatal(e)` asks **did the runtime get to clean up**, and it is about
       `Runtime.swhnf`, not about the JVM. `swhnf`'s ONE capture is
       `catch { case NonFatal(e) => r = Bottom(throw e) }` (`Runtime.scala:231`), so a
       throwable that is NOT `NonFatal` escapes a force WITHOUT reaching `writeback`, leaving
       every thunk on the chain in state `Whitehole` with the preview thread still in its
       `pending` queue (`:229-237`). A later force of one of those thunks **on that same
       thread** takes the `pending.exists(sameId)` branch and memoises `Whitehole.result` --
       `Bottom(sys.error("infinite loop detected"))` (`:196`) -- a permanent and WRONG
       diagnosis. `NonFatal`'s complement is exactly `VirtualMachineError`, `ThreadDeath`,
       `InterruptedException`, `LinkageError`, `ControlThrowable`, and **the last two are not
       `Error`s**, which is why the first half misses them.
    **THE `StackOverflowError` ASYMMETRY IS DELIBERATE, and its reason is the SECOND half, not
    the heap**: a stack overflow usually leaves a healthy JVM, but it is a
    `VirtualMachineError` and therefore not `NonFatal`, so it unwound without writeback and
    left whiteholes behind. Refusing to clear costs exactly the behaviour this preview had
    before Q10 -- the restart the watchdog already names -- while clearing wrongly tells a
    user the preview works when it does not. THE CASE THAT MAKES THE FIRST HALF CONCRETE: the
    launcher adds `-XX:+ExitOnOutOfMemoryError`, so in the shipped server an OOM usually ends
    the process first -- but the unforked gate JVM has no such flag, nor does a user who sets
    `-XX:-ExitOnOutOfMemoryError`.
    **THE "WRAPPED `Error`" GAP IS NARROWER THAN THE FIRST CUT CLAIMED** (review): such an
    `Error` reads as non-fatal here, but the WRAPPER *was* `NonFatal`, so `swhnf` did capture
    it and did write it back -- there are no whiteholes, only a poisoned `Bottom`, and item 1b
    discards the session for exactly that. What is left of the gap is the first half alone: a
    JVM that may be sick is called healthy. Unwrapping causes would be a guess about a chain
    this file did not build.
 3. **SILENT WHILE STOPPING.** During a `shutdown` the state is cleared and nothing is sent:
    a "the preview recovered" banner on the way out would be true for under a second. Every
    send is separately guarded, as every send in this file is.
 4. **THE LATE JOB'S OWN ANSWER IS STILL DISCARDED**, exactly as before: the client already
    has the watchdog's answer, `finish` finds the claim taken, logs "finished after the
    watchdog answered it" once, and sends nothing. Recovery changes who may be served NEXT,
    not who answered THEN.
 5. **THE CLIENT IS TOLD TO RE-RENDER AND TO ASK FOR THE SCHEMA AGAIN** (Q8's notification,
    `{stuck: false}`, plus a `window/showMessage` of the INFO type). It is not politeness:
    every `invalidate` posted while the preview was stuck was DROPPED at the `!stuck` guard in
    `Preview.invalidate`, so the extension missed every `ermine/preview/invalidated` of that
    whole interval and §3 step 6 never fired -- **and every `ermine/schema` asked meanwhile
    was REFUSED**, by `schema`'s own stuck branch or by the watchdog's queue drain, which in
    §6's loop is one per pick. When the session was also discarded (item 1b) the message says
    so, so the user is not surprised by the boot the next render pays.
 6. **A SEQUENCE NUMBER ON BOTH EDGES** (IM-1 of the Q8-Q12 review). `{stuck: true}` is the
    TIMER thread's, the LAST of `fire`'s sends; `{stuck: false}` is the PREVIEW thread's, the
    FIRST of `recovered`'s. **Nothing ordered them**, so a job released the instant the
    watchdog fired could put the FALSE on the wire first and a client reading arrival order
    would latch a stuck banner on a healthy preview with no falling edge ever to follow --
    and the existing properties could not see it, because they hold the wedged job until the
    rising edge has ARRIVED. A monotonic `seq` is now minted in the SAME locked step that
    flips the state (`fire`'s claim, and `clearStuck`) and carried on the notification, so the
    wire order stops mattering. §4's row states the client contract.

**`dirtyGeneration` IS NOT BUMPED AT RECOVERY, and the reasoning is recorded because "bump the
counter" is the obvious reflex and it is INERT here.** `stale` is
`dirtyGeneration.get != r.dirtyAt`, comparing the value when a render is ENQUEUED with the
value when it is ANSWERED. Nothing can be enqueued while stuck (`render`, `schema` and `post`
all refuse), so the first post-recovery render is enqueued AFTER any bump this path could
make and would snapshot the bumped value -- the two reads agree and no `stale` appears. A bump
would therefore either do nothing at all or, if it were contrived to straddle the enqueue,
flag a render that really was fresh. WHAT MAKES THE FIRST POST-RECOVERY RENDER HONEST IS
ALREADY THERE: §2.5's mtime scan runs at the head of every render and reloads every LOADED
module whose file moved on disk, which is every save made during the wedge. WHAT IT CANNOT
COVER is a module the session never loaded -- the fix to a report whose load failed, Q4's
case -- and that is exactly what the re-render the notification asks for is for.

**THRASHING, stated rather than discovered later.** A second wedge immediately after a
recovery thrashes: stuck -> recovered, once per render, for as long as `timeoutSeconds` is
below a legitimately slow scan. The remedy is to raise the timeout (Q9), not to turn the
watchdog off. And "recovered" can still be **seconds** from the `-Xmx` exit that §2.5
measured: the `WpBlow` run reached the cap in 8.6 s, so a job that comes back after a fire is
not evidence that the heap is healthy -- which is the second reason (2) above is as wide as
it is.

**THE WATCHDOG'S OWN MESSAGE IS UNCHANGED**, and that is a decision: it still says "the
preview is stuck until the language server is restarted -- run \"Ermine: Restart Language
Server\"". It is now the WORST CASE rather than the only case, and it is quoted verbatim in
§2.5's MEASURED block and pinned by a group-D property. The falling edge corrects it with its
own message and its own notification, which is where a banner should read it from.

Files: `lsp/Preview.scala`, `TestLspRobustness.scala`, this document.

**Q11, in full** (found by the Q4 review, 2026-09-20). Q4's pending set records a module only
when a LOAD WAS ATTEMPTED for it. A module that no root has is refused BEFORE any load --
`compile`'s `NotFound("no module named X")`, `json/Runner.scala` -- so it is never recorded, and
the `moduleUnder` half of `invalidate`'s `direct` set is filtered by `loadedModules`, which such
a module is also not in. So a report the extension picks before its file exists, or one whose
file is deleted and then RESTORED, renders 404 and then **nothing names it when the file
appears**: no `ermine/preview/invalidated` goes out and the panel keeps its 404 banner until the
user picks the report again. It is the same shape as Q4 and outside Q4's wording, which is about
the 500 "module does not load". Options, none built:
(i) accept it -- the 404 case is rarer than the 500 case, and a developer who has just created
the file is about to pick it anyway;
(ii) remember the NOT-FOUND module names in a second bounded set, and name one only when an
invalidated path maps through `Session.moduleUnder` to exactly that module name -- precise, no
over-notification (unlike the pending set, which rides along on any module-naming path), and
§11's "(inv1) `invalidate` of an unloaded path is a no-op" stays true for every path nobody ever
asked for;
(iii) the extension re-renders on file-CREATION events for the picked report's own path, which
is **WP-7**, the extension, and needs no server change.
It blocks nothing; the answer is wanted before WP-7, which is where the loop closes.

**DECIDED by the user on 2026-09-20: option (iii), the EXTENSION's, and NOTHING IS BUILT IN
`Runner`.** The orchestrator's original recommendation was option (ii) -- a second bounded
not-found set in `Runner` -- and the design review WITHDREW it. Two reasons, both about the
code as it now stands and both recorded so that nobody proposes (ii) again:

1. **THE SET WOULD NEVER BE POPULATED THROUGH THE PREVIEW.** Since Q5 and Q7 a picked FILE
   that cannot be read is refused AT PLACEMENT -- `Preview.inferredRoot` answers "cannot read
   `<name>`" and `placeAndSession` turns that into the 404 -- **before `Runner` is asked
   anything at all**. `Runner.compile`'s `NotFound("no module named X")`, which is what (ii)
   would have recorded, is reached only by a caller that already has a module NAME, and the
   preview never has one for a file it could not read. And even if the set existed and were
   filled some other way, `ermine/preview/invalidated {modules}` is keyed on module NAMES:
   for a file with no readable header there is no name to send, so the notification could not
   name it either.
2. **A MISSING IMPORT IS ALREADY Q4's.** A report whose file exists but whose import does not
   is a LOAD FAILURE, which Q4's pending set records and Q4's `invalidate` already names when
   the import is created.

What is genuinely left is exactly one path: **the picked report's OWN file appearing or
reappearing**, which the extension is watching anyway because it is the file the user picked.
So WP-7 re-renders when that path is created or changed while its last answer was a
**PLACEMENT 404 ONLY** -- one of Q5's four reasons ("cannot read `<name>`", "not an Ermine
source file", "no module header could be read from", "names `<module>`, which is deeper than
the directories above it"), which `Preview` answers before `Runner` is asked.
**HOW WP-7 TELLS THE TWO APART, settled by Q15 (2026-09-20) and not left to the message text**:
the wire gave both 404s the same shape, so the first cut of WP-7 approximated the test with "the
server never named this file's module", which its own review falsified -- the module name is a
CACHE the pick carries, so Q11's own scenario (a report picked while it existed, then deleted,
then restored) never fired. The user then decided Q15: the preview's front half puts a closed
`reason` on its own failures and the `Runner`'s 404 has none. The test is now exact. **A 404 from
the `Runner` is DELIBERATELY EXCLUDED** (review SHOULD-FIX 6): a `Runner` 404 is "no binding
named X" on a module that DID load, so that module is in `loadedModules` and an edit to its
file already sends `ermine/preview/invalidated`; adding the extra trigger would double-render
on every save of a report whose binding was mistyped. One trigger, one render. That item is
added to WP-7's row in §14 and to §3 step 6.

**THE BLIND SPOT BOTH OPTIONS SHARED, so that (iii) is not sold as more than it is**: a report
under a preview root that lies OUTSIDE the workspace folders depends on what the client's file
watcher reports, and VS Code's watcher is scoped to the workspace (*external*, not exercised
here). Neither a server-side set nor an extension-side watcher sees a creation nobody reports.

**Q12, in full** (MEASURED by WP-5 stage C, 2026-09-20). With `-XX:+ExitOnOutOfMemoryError`
the JVM writes `Terminating due to java.lang.OutOfMemoryError: Java heap space` and exits.
Measured, that line lands on **fd 1**, unframed, immediately after a well-formed `$/progress`
frame and immediately before EOF -- and fd 1 is the LSP protocol channel. The repository
treats stdout as sacred: `Main.stealStdout` (`lsp/Main.scala:22-37`) replaces `System.out`
with a sink that turns every stray `println` into a log line "(decision 4)", and
`lsp-client.py`'s phase-timer check exists to assert that timings never reach stdout. Neither
covers this line, and NOT because anyone forgot: `System.setOut` rebinds a Java field, while
this line is written by the VM itself to the file descriptor. No JVM flag redirects only that
message (`-XX:+DisplayVMOutputToStderr` moves all VM output and is *external*, unverified
here). Options, none built:
(i) ACCEPT it. The process is exiting anyway, the bytes arrive after the last complete frame,
and what a client does with a trailing fragment before EOF is *external*: a
client's reader would at worst log a parse error on a stream that is about to close. Cost:
nothing; risk: a client that treats malformed input as fatal reports the wrong cause;
(ii) MAKE fd 1 SAFE IN THE PROCESS. At startup `Main` duplicates fd 1, points the `Wire` at
the duplicate and reopens fd 1 on the log (or `/dev/null`), so nothing the VM or a native
library writes to fd 1 can reach the client. This is what `stealStdout` does one level up, and
it would subsume it. Cost: a small native-ish dance (`FileDescriptor`/`FileOutputStream`, or
an `ERMINE_LSP_*` wrapper doing `3>&1 1>log`), plus every framing test now has to know which
descriptor is the wire;
(iii) DROP `-XX:+ExitOnOutOfMemoryError` and handle the OOM in-process: catch it where the
preview thread already catches `Throwable`, answer the request, log, and call `System.exit`
ourselves after a clean shutdown. Cost: an `OutOfMemoryError` caught in a thrashing JVM is
not reliably actionable (that is the flag's whole reason for existing), and §2.5's recovery
would depend on code that runs with no heap left.
It blocks nothing; the answer is wanted before WP-7, which is when a user first sees the
panel go dark.

**DECIDED by the user on 2026-09-20, AS CHANGED BY THE DESIGN REVIEW: option (ii), but ONLY
ITS FIRST STEP -- the JVM flag -- MEASURED FIRST AND THEN BUILT. The descriptor-duplication
step is NOT built.**

**THE PROBE (a), MEASURED 2026-09-20.** `"$java" -XX:+DisplayVMOutputToStderr -version` on
this JDK (Temurin 21.0.12.1+1) exits **0**, so the option is recognised here.

**THE INSTRUMENT (b), MEASURED 2026-09-20**, alone on the machine, the same `wp5c-instrument.py
--mode blow` driver and the same `WpBlow` fixture as stage C, at `ERMINE_LSP_XMX=256m`, this
time with `ERMINE_JAVA_OPTS="-XX:+DisplayVMOutputToStderr"`. The driver already captured
stderr to a file (`--stderr`), so nothing was added to it. **The line MOVES.**

| | stage C baseline | with the flag |
|---|---|---|
| exit code | 3 | 3 |
| time to the exit | 8.6 s | 8.7 s |
| last bytes on **stdout** | `...{"kind":"end"}}` **`Terminating due to java.lang.OutOfMemoryError: Java heap space\n`** | `...{"kind":"end"}}` -- a complete frame and then EOF |
| **stderr** | **EMPTY (0 bytes)** | `Terminating due to java.lang.OutOfMemoryError: Java heap space` (63 bytes) |

So the unframed trailer leaves the protocol channel entirely and lands where an editor already
shows a server's stderr. **AND IT FIXES A SECOND THING NOBODY HAD NAMED**: today the crash is
UNEXPLAINED in the client's output channel, because stderr was empty (measured, both runs of
stage C and this one's baseline) -- the client saw a stream that stopped. After the flag the
reason is there to read.

**WHAT WAS BUILT (c): `bin/ermine-lsp` adds `-XX:+DisplayVMOutputToStderr`, behind a guard that
cannot stop the server from starting.** An unrecognised `-XX` option makes the JVM print
"Unrecognized VM option" and exit **1 before any LSP frame**, which the editor sees as a server
that died at startup -- so the flag is added only when a cached one-off
`java -XX:+DisplayVMOutputToStderr -version` probe says this java accepts it. The verdict is
cached beside the classpath (`target/ermine-vmout-probe`), keyed on the java binary's PATH,
MTIME and SIZE, so a different `JAVA_HOME` or a toolchain upgraded in place re-probes instead
of inheriting the answer. If the probe cannot run at all -- no such java, an unwritable
`target/` -- the flag is simply not added. **`-XX:+IgnoreUnrecognizedVMOptions` is NOT used**:
it would silence every future typo in that file as well. The flag is never added when a WORD of
`ERMINE_JAVA_OPTS` already names `DisplayVMOutputToStderr` with either sign, which is the same
word test the other two flags use. **PROBED with stub javas** (ten checks, all green): an
accepting stub gets the flag; a rejecting stub does not; a second run with the same java hits
the cache and invokes java ONCE, not twice; a changed java path re-keys the cache; the same
path with a moved mtime re-probes; `-XX:-...` and `-XX:+...` in `ERMINE_JAVA_OPTS` are each
honoured exactly once; a java that does not exist gets no flag.
**AND CONFIRMED END TO END, MEASURED 2026-09-20**: the same `WpBlow` instrument re-run through the
MODIFIED launcher with NO `ERMINE_JAVA_OPTS` at all -- exit code 3 after 8.5 s, stdout ending at the last
complete `$/progress` frame, stderr carrying the 63-byte termination line, and
`target/ermine-vmout-probe` holding the real java's key and `yes`. The launcher does it by itself.

**THE DESCRIPTOR-DUPLICATION STEP IS NOT BUILT, and this is why.** Option (ii)'s second half is
`Main` dup()ing fd 1, pointing `Wire` at the duplicate and reopening fd 1 on the log.
**THE REASON IS THAT NOTHING WOULD EXERCISE IT**: no harness in this repository goes through
`bin/ermine-lsp` at all (`lsp-smoke.sh`, `lsp-demo.sh` and `perf-client.py` each build the
`java` command line themselves from `tracker/repl-classpath.txt`, and `TestLspRobustness`
starts no process), so a second wire descriptor would ship untested, on the one path a
mistake in it would break everything. The flag achieves the measured outcome with one word
and needs no new descriptor at all.
**A PORTABILITY ARGUMENT WAS OFFERED FIRST AND IS WITHDRAWN** (review): "POSIX-only while §10's
deployment machines are Windows" does not distinguish the two options, because `bin/ermine-lsp`
is ITSELF a bash script and is what `extension.js` launches -- on Windows today NEITHER
mechanism ships. That is WP-17's gap, not an argument for the flag; see its row in §14.
**AND A POINT IN THE FLAG'S FAVOUR THE REVIEW ADDED**: `-XX:+DisplayVMOutputToStderr` moves the
VM's WHOLE tty stream, not just the OOM line -- and every line of that stream on fd 1 was, by
construction, unframed bytes in the protocol channel. So nothing legitimate is lost by moving
it, and more than the one measured line is gained.

**IT IS NOT MOOT UNDER ANY Q13 OUTCOME, correcting this document's own claim.** Q13's option
(iii) says an exit at the watchdog's fire "makes Q12 moot". It does not: the MEASURED `WpBlow`
run **died at 8.6 s, BEFORE any watchdog fire at all** (the shipped 60 s clock was still
running). An OOM that arrives before the watchdog is untouched by anything Q13 decides, so the
line on fd 1 is Q12's to fix whichever way Q13 goes.

Files: `bin/ermine-lsp`, this document. NO Scala, NO `editor/vscode`, NO gate registry change;
the instrument is machine-dependent and is never gate evidence.

**Q13, in full** (MEASURED by WP-5 stage C, 2026-09-20). §2.5 promises that "a runaway
evaluation blocks no LSP request until it exhausts the heap cap", and the watchdog is there so
that the user is told at 60 s rather than at OOM. Measured, the second half arrives much
sooner than that wording suggests: under the launcher's `-Xmx2g` default a stuck preview took
the WHOLE SERVER down **about two minutes after the watchdog fired** (`WpChain`, two runs,
exit code 3), taking the resident session, its per-document inference caches, the
workspace-symbol table and -- once WP-13/WP-14 exist -- the held connection and its `##`
tables with it. Between the fire and the exit the process also held 2.3 GiB of RSS, which on
an 8 GB laptop with two windows is most of the machine. The watchdog's message ("the preview
is stuck until the language server is restarted") is therefore true but understated: the
restart is coming anyway, and the user does not choose when. Options, none built:
(i) ACCEPT and SAY SO. The panel's stuck banner (WP-7) and the `window/showMessage` text say
that the server will restart itself shortly and that unsaved editor state is not at risk.
Cost: a wording change; the resident still dies;
(ii) PRIORITISE WP-6 (cooperative cancel). The flag at the head of `Runtime.swhnf` is what
makes the runaway stop allocating at all; with it, the watchdog's answer is the end of the
incident rather than the start of a two-minute countdown. Cost: WP-6's own perf A/B gate, and
the `Runner` discard it already specifies;
(iii) EXIT DELIBERATELY AT THE FIRE. When the watchdog fires, answer, notify, and shut the
server down cleanly instead of waiting for the OOM -- a predictable restart at 60 s in place
of an unpredictable one at 60 s + 2 min. (This option was first written down as one that
"makes Q12 moot"; it does not -- see the note below.) Cost: it throws away a
resident that was working, and a preview that would have finished at 61 s never gets to.
It blocks nothing; the answer is wanted with WP-6. If the primitive-loop case of §2.5's
finding 1 ever finds a witness, this question gains a second shape -- a stuck preview that
does NOT end in an exit and so never restarts at all.

**Q13 WAS DECIDED BY THE USER ON 2026-09-20: OPTION (ii), PRIORITISE WP-6.** What the notes
below record is what the questions decided the same day changed about the ground Q13 stood on;
they are kept because they remain true of the options not taken. Three things the decision
adds to them:

 - **WHAT IT DOES AND DOES NOT BUY, stated plainly.** With the switch ON, a runaway evaluation
   that reaches `Runtime.swhnf` -- which is every loop MEASURED in §2.5 -- ends at the
   watchdog's own deadline instead of starting a two-minute countdown to `-Xmx`: the render
   answers 500, the render session is thrown away, the resident, its caches and (once WP-13
   and WP-14 exist) the held connection all survive, and the preview serves the next render.
   What it does NOT touch is the case §2.5's finding 1 could find no witness for -- a loop
   inside ONE primitive -- nor a JDBC scan, nor the relational row loop, nor a parked thread.
   For all of those phase 2b falls back to option (i)'s behaviour, and the two-minute
   countdown is back. So (ii) narrows Q13, it does not close it;
 - **IT IS THREE STAGES AND ONLY THE FIRST IS BUILT.** Stage 1 is the mechanism, default OFF,
   which costs a load and a branch per force and changes NOTHING about how the server behaves
   until the switch is set. Stage 2 MEASURED that cost (§11's Instruments section; `perf-bench.sh`
   is blind to it): not distinguishable on an ordinary fold, a suggested but not established
   ~5 % on the `swhnf`-densest one, and the flip itself adds nothing further. STAGE 3 IS THE DEFAULT, and it is the user's, under the standing rule that
   no default is flipped without them;
 - **(iii) IS NOT TAKEN AND IS NOT DEAD.** An exit at the fire remains the only answer for the
   cases the cancel cannot reach, and this document keeps its argument above: a legitimately
   slow scan argues against it, the heap argues for it. Nothing here decides it.

 - **WHAT Q8 AND Q10 COST OR BUY UNDER OPTION (iii).** If the server exits at the fire there
   is no preview left to hold a stuck state, so Q10's recovery never happens and Q8's
   `{stuck: false}` is never sent; the `{stuck: true}` edge and the `"stuck": true` marker
   still go out, once, immediately before the process ends -- which is precisely what tells
   the panel to show a banner rather than go blank. So (iii) does not waste Q8; it makes
   Q10's falling edge unreachable. Under (i) and (ii) both are load-bearing. The code is
   written either way and would simply stop firing.
 - **Q12 IS NOT MOOT UNDER ANY OPTION.** The MEASURED `WpBlow` run died at **8.6 s, before
   any watchdog fire**, so an exit at the fire cannot come first; the JVM's OOM line on fd 1
   is reached by a path no Q13 option intercepts. Q12 is therefore decided and built
   independently.
 - **A LEGITIMATELY SLOW SCAN ARGUES AGAINST (iii); THE HEAP ARGUES FOR IT.** §2.5's own rows
   allow an evaluation to take up to the 300 s statement timeout, and Q10 exists because a
   wedged job really can come back -- under (iii) that render costs a HARD kill of the whole
   server (resident, caches, and once WP-13/WP-14 exist the held connection) for being slower
   than `ermine.preview.timeoutSeconds`, where under (i) and (ii) it costs a banner and a
   re-render. **The counterweight, which this batch itself supplies**: "recovered" can be
   SECONDS from the `-Xmx` exit -- the `WpBlow` run reached the cap in 8.6 s -- so a job that
   comes back after a fire is NOT evidence that the heap is healthy, and Q10's falling edge
   can be followed by an exit the user did not choose either way. Both facts are inputs; this
   note weighs neither.
 - **THE POISONED SESSION (DM-1, and Q14) IS AN INPUT TO (ii) AND (iii).** A wedge that ends
   by throwing memoises its failure into the render session's shared thunks
   (`Runtime.scala:231`, `:245-250`), which is why recovery now discards the session and why
   §2.5's WP-6 row already discards the `Runner` on a cancel. Under (ii) that discard is
   WP-6's own and already specified; under (iii) the whole process goes, so the question does
   not arise; under (i) it is the behaviour built here. Q14 asks the same question of an
   ordinary transient failure and is open.
 - **(ii) IS OTHERWISE UNCHANGED**: WP-6's cooperative cancel still needs its perf A/B, and
   `clearStuck` was deliberately written with a `null` "whatever the watchdog fired on" case,
   and with the ordering trap documented in its scaladoc, so that a cancel reuses it rather
   than writing a second one.

**Q14, in full** (found by the Q8-Q12 review while deciding Q10's DM-1, 2026-09-20; **widened
by the second review's DD-1**; NOTHING IS BUILT and nothing here decides it). Q10's item 1b
discards the render session when the job the WATCHDOG fired on comes back FAILED, because
`Runtime.swhnf` captures a `NonFatal` failure as `Bottom(throw e)` (`Runtime.scala:231`) and
`writeback` memoises it into every thunk on the chain (`:245-250`). **That mechanism is not
special to a wedge, and it is not special to a rare failure either.** It is **EVERY
NON-THROWING RENDER FAILURE -- the common path**: `Encode` turns a `Bottom` into
`Left(bottom(...))` (`Encode.scala:295`, `:242`, `:514`; `Doc.scala:212-214`) and `Runner` nets
every `NonFatal` failure into `Left(Failed(...))` (`:508`, `:845`, `:883-886`, `:929-930`), so
an ordinary report that dies while being forced answers a 500 **by returning** and leaves its
memoised failure behind. The consequence is that a shared binding forced during that render
keeps the old failure, so a LATER render of a module **nobody edited** re-throws it, and no
`invalidate` clears it because no file changed. Today the render answers 500 and the session
lives on.
**AFTER DD-1, THE WEDGE CASE IS COVERED AND THIS IS THE REST**: when the watchdog has fired,
Q10's recovery discards the session on exactly this outcome. When it has NOT fired -- which is
every ordinary failing render, the case a developer meets while iterating -- nothing discards,
and that is this question. It matters most for a failure that is TRANSIENT and has nothing to
do with the source (a dropped connection, a scan that hit the 300 s `setQueryTimeout`, a driver
reloading -- all of which arrive once WP-12/WP-13 put a real database behind the delegate),
because a deterministic failure re-thrown is simply the right answer given again.

**IT IS PRE-EXISTING AND IT IS NOT THE PREVIEW'S ALONE**: `Runner` is the same class
`bin/ermine-serve` uses, and its `reports` cache and session outlive a request there too. WP-5
only made it easy to notice, because a preview session is long-lived by design and a developer
re-renders the same report.

Options, none built:
(i) **ACCEPT.** Most evaluation failures are DETERMINISTIC -- a type error, a bad param, a
report that divides by zero -- and for those, re-throwing the memoised value is exactly right
and costs nothing. A transient failure is rarer, and the remedy the user already has is
"change something and save", which invalidates.
(ii) **DISCARD THE RENDER SESSION AFTER EVERY EVALUATION 500.** Simple, uniform, and the same
line DM-1 already added. Cost: a boot (§2.2: 1.9-7.3 s measured) after every failing render,
including the deterministic ones the developer is iterating on, which is exactly when a fast
loop matters most.
(iii) **DISCARD ONLY FOR ERROR CLASSES KNOWN TO BE TRANSIENT.** §8.3's classifier already
sorts driver failures into `auth` / `driver` / `connect`, and `connect` is the transient one.
Cost: a list to keep, and a failure it does not recognise is silently (i).
(iv) **MAKE THE SCAN'S FAILURE NOT MEMOISE.** Narrowest and deepest: the value a failing
`scanRelation` yields would have to be a thunk the runtime does not write back, which is a
change to `Runtime`/`Runner`, not to the preview, and would need its own argument about what
else depends on memoised bottoms.

It blocks nothing. The answer is wanted with **WP-12/WP-13**, when a render first talks to a
database that can drop a connection.

**Q15, in full** (found by WP-7's own review, 2026-09-20; **DECIDED by the user the same day
and BUILT**). §4 gave a PLACEMENT 404 -- the preview's own front half refusing a file it cannot
read, cannot parse a header from, or cannot place (Q5's reasons) -- and a `Runner` 404 -- "no
module named X", "no binding named X", on a file that reads perfectly well -- **the same wire
shape**: `{ok:false, status:404, message, generation}`. Q11's whole trigger turns on telling
them apart, and the only difference was the MESSAGE TEXT.

**WHY THE CLIENT COULD NOT DO IT.** WP-7 first shipped an approximation -- "a 404 whose file the
server never named a module for" -- and its review falsified it in one line: the module name is a
CACHE the pick carries, learned at pick time and persisted per workspace, so Q11's own named case
(a report picked while its file existed, then deleted or moved away, then restored) never fired.
Every other client-side test lands in the same place: the client cannot know which half of the
server refused it, because the server does not say.

**OPTIONS**, as put to the user: (i) a machine-readable `reason` / `kind` on the preview's own
failures -- a few lines in `Preview.cannotPlace` and the two dressing sites -- so the test is on a
structured field and the extra work is nil; (ii) keep a client-side approximation, at the cost of
one extra `ermine/preview/reports` request per file event on a 404 and a dedupe that has to be
argued rather than seen; (iii) nothing built, and Q11's trigger stays wrong in its own named case.

**DECIDED: (i), and BUILT** (2026-09-20). `lsp/Preview.scala` gains `Preview.Reason`, a CLOSED and
STABLE vocabulary -- `not-a-file-uri` (400), `not-ermine-source`, `unreadable`, `no-module-header`,
`header-deeper-than-path`, `not-placed` (404) and `shadowed` (409) -- carried by
`CannotServe(status, message, reason)` and by a new `Unplaceable(reason, message)` that
`inferredRoot` and `cannotPlace` answer with, so a site that mints a message cannot forget its
reason. `failure` appends `reason` after `path` and before `generation` (no existing key moves)
and `schemaError` puts it beside `error`. **EXTENDED 2026-09-24 (Q-S4 (a), the user; WP-13 server half):** the vocabulary GAINS `not-connected` (the render 503 while disconnected, decided by the preview itself before `Runner` is asked) and `connect-auth`, `connect-driver`, `connect-unreachable`, `connect-profile` (on `ermine/preview/connect` failures only, one per `class`). Same contract: closed, stable, minted only in `Preview`; a `Runner` answer still carries none. **NOTHING ELSE CARRIES ONE**: a 404 from the `Runner`,
the bad-`roots` 400 (the client's error, not a placement decision), the 503, every 500 -- all have
no `reason` key, and that ABSENCE is what the extension reads. An older server sends none
anywhere, so a client degrades to "never trigger", never to triggering wrongly.
`json/Runner.scala` and `RunError` are UNTOUCHED and `bin/ermine-serve` is unchanged: the HTTP
route never sees this.

**THE 409 AND THE 400 WERE A CHOICE AND IT IS RECORDED**: `shadowed` and `not-a-file-uri` are in
because they are decided by the very same front half, in the same `match`, and cost one `Some`
each; the vocabulary was NOT grown to anything the front half does not itself decide. The
extension reads only "404 with a reason".

**TESTS**: the existing group-D property "a file that cannot be placed under a root is a 404
saying why" now also asserts `unreadable` for a file that is gone, `no-module-header` for an
unparseable header, `not-a-file-uri` for a non-file URI, **no `reason` at all for a `Runner` 404**
(a binding that does not exist on a module that loads -- the conjunct that makes the absence a
rule rather than an accident), the same `reason` beside `ermine/schema`'s `error`, and none on the
bad-`roots` 400. No new bench, no new property. MEASURED on the changed tree:
`core/testOnly com.clarifi.reporting.TestLspRobustness` = **PASS 63/63 in 55 s**.

**Q16, in full** (found 2026-09-20 while building WP-6 stage 1; NOTHING IS BUILT and nothing
here decides it). `Preview.placeAndSession` does its steps in this order: the path from the
URI, the report's inferred root, the ROOT SET, **`ensureSession(roots, ...)`**, the mtime scan,
and only THEN the module lookup that can answer 400/404/409. So a request that will be refused
anyway -- a file that is gone, a header that does not parse, a URI that is not a file -- has
already computed a root set and handed it to `ensureSession`; and if that set differs from
`rootsInUse`, `ensureSession` DISCARDS the session in hand and boots another (§2.4: roots are
immutable `RunnerConfig` fields). The refusal then goes out, and the NEXT ordinary render,
whose roots are the usual ones, discards that session and boots a third. **Two boots, several
seconds each (§2.2 measures 1.9-7.3 s), for a request that rendered nothing.**

**HOW IT WAS FOUND, because the path matters.** It is not hypothetical and it is not new: a
group-D property has sent `ermine/schema {uri, binding, roots: []}` on the suite's SHARED bench
since Q15, and `[]` is a value `rootEntries` ACCEPTS (absent, `null` and `[]` all mean "no
roots", unlike a non-array or a non-string entry, which are refused at parse on the dispatch
thread and never queued). With no request roots and no inferrable root the set is `[<the
resident's roots>]` where the bench's session holds `[<the resident's roots>, <the temp
root>]`, so the two boots above happened -- and the property that asserts the shared bench
booted EXACTLY ONCE failed, but only on the schedules where it ran after that one. WP-6's new
`TestPreviewCancel` takes the same `previewLock` and changed the pool's interleaving, which is
how a latent order dependence became a reproducible red. **THE TEST WAS FIXED** (that request
now names the bench's own roots, which is not the case it is testing) **AND `Preview` WAS NOT**;
this question is what, if anything, the server should do.

Options, none built:
(i) **ACCEPT.** The cost is bounded -- two boots per refused request whose roots differ -- and
a real client does not send differing roots for the same picked report (§4 tells the extension
to send the SAME `roots` on a render and a schema). The case is reachable mainly from a client
bug or a hand-written request;
(ii) **PLACE FIRST, THEN ENSURE THE SESSION.** Move the `path` / `moduleUnder` / `cannotPlace`
decision ahead of `ensureSession`, so a request that cannot be served never touches the
session. **THE COST IS RECORDED AND IS NOT ZERO**: it changes WHICH REFUSAL WINS between the
400/404 and the 500 a FAILED BOOT answers, and `shadowedPick`'s scaladoc already records the
orchestrator's 2026-09-20 decision to keep the present order for exactly that reason -- plus
"the boot is not wasted work: it is the session the next request reuses", which stops being
true only for requests that are refused;
(iii) **DO NOT DISCARD FOR A ROOT SET THAT IS A SUBSET** of the one in use, or keep the session
and answer from it. Narrowest, and the least principled: §2.4's discard-on-change is a rule
about what the loader will read, and weakening it needs its own argument.

**THE STAGE 1 REVIEWER'S ADVICE, recorded AS ADVICE and not as a decision**: they would take
(ii) and place before ensuring the session -- a request that cannot be served should not touch
the session at all, and the refusal-ordering cost is a smaller thing to reason about than a
re-boot a user cannot see. The question STAYS OPEN and is the user's; this note records a view,
not an answer.

It blocks nothing. The answer is wanted whenever §2.4's root-set rule is next opened.

## 14. Tickets, in dependency order

Every ticket lands on `widget-preview` in `ermine-scala-wt-widget-preview`. Costs are
estimates from the shape of the change, not measurements; tiers are `docs/gate-policy.md`'s.

**This table is authoritative for ticket numbers.** `JSON-WIDGET-PLAYGROUND-RESOLUTIONS.md`
numbers them differently, and the offset is not constant: its own table
(`RESOLUTIONS:380-392`) INSERTS two tickets, `WP-2b NEW` (`:384`, `_registerDecls`) and
`WP-4b NEW` (`:387`, cooperative cancel), which this table numbers WP-3 and WP-6. So its
"WP-3" (`:385`, and `:84`, `:155` in the prose) and its "WP-4" (`:386`, and `:151`) are ONE
behind -- they are this table's WP-4 and WP-5 -- and everything after its inserted `WP-4b` is
further behind still: its "WP-5" (`:388`, the picker and `ermine.preview.roots`) is this
table's **WP-7**, and its "WP-6 / WP-7" (`:390`, the bundle and the host reducer) are this
table's WP-9 and WP-10. Read the ticket here.

| # | Ticket | Done when | Tier / cost |
|---|---|---|---|
| WP-1 | `Rpc.scala`: `send` synchronised; `onRequestDeferred`; `$/cancelRequest` routed; incoming log line moved after parse and redacted by method (`Rpc.Redacted`); `notify` legal from a second thread | the four A-group properties in §11 pass; a captured log of an `ermine/preview/connect` round trip contains `[redacted]` and not the body | pr / ~half a day |
| WP-2 | lift `scrub` and `dependentsOf` from `Resident` into `Session` with `builtins` as a parameter; `Resident` calls them | C properties `:554`, `:583`, `:655` pass unchanged; `git diff --stat` of `Resident.scala` is deletions plus the four call sites (`:208`, `:212`, `:231`, `:461`) and the `builtins` threading | pr / ~2 h |
| WP-3 | `_registerDecls` on `SessionEnv` (default on, carried by `copy`), consulted at `Session.scala:915`, off on every `Resident.withEnv` copy | the group-D registration property in §11; `TestJson`, `TestSchema`, `TestNamedFields` unchanged | pr / ~2 h |
| WP-4 | `Runner`: `reports` keyed by `(module, binding)`, `report`/`compile(module, binding)`, `cfg.reportName` the default for the HTTP route; `paramSchema(module, binding)`; `resultKind` public; `builtins` snapshot after its preamble; `invalidate(paths: Set[Path]): Set[String]` under `evalLock` (scrub the closure, evict `reports`, no eager reload); `Backends.scannerFor(dialect, variant)`; a `delegatingRun: RunDB` in `lsp/` | the four `TestRunner` properties in §11; `bin/ermine-serve` behaviour unchanged (`TestRunner` green) | pr / ~1 day |
| WP-5 | the preview thread and `Preview` object in `lsp/`: lazy boot on first `ermine/render`, daemon thread, `uri` -> module, `inferredRoot`, absolute `roots`, queue with one in flight / one queued / latest wins, `generation` echo, mtime scan per render, `stale` generation counter, watchdog with the restart button, document-size cap, `invalidate` posted from `afterReload`, `ermine/preview/invalidated`, `ermine/schema {binding}` routed to the queue, `ermine/preview/reports` on the dispatch thread, work-done progress; launcher `-Xmx${ERMINE_LSP_XMX:-2g}` + `-XX:+ExitOnOutOfMemoryError` and the `ermine.maxHeap` setting | group D properties; `lsp-client.py` smoke; RSS, boot seconds and heap after a watchdog fire (allocating and non-allocating loop) MEASURED and written into §2.2/§2.5; a render whose evaluation loops is answered by the watchdog and the resident still answers a hover; an allocating loop ends in a clean exit the client restarts | pr + commit + instruments / ~3 days |
| WP-6 | **BUILT (stage 1, `b7b93daa`), MEASURED (stage 2, `02787f99`) AND REMOVED FROM THE TREE (WP-24, 2026-09-20), BY THE USER'S DECISION (§13, Q13). NONE OF (a)-(i) BELOW IS IN THE CODE; they are kept, unedited, as the design record of what was built and why -- read them as history, not as behaviour.** What the watchdog does now is what it did at `0a092242`: ONE PHASE -- `fire` (`Preview.scala:2069`) claims the job under `lock` and does the stuck mark, the `seq` mint, the drain and the notification inline (§2.5). `fireStuck` was `b7b93daa`'s name for the second half of the split and does not exist here. Stage 3 is moot: there is no default left to flip. **WHAT REPLACES THIS TICKET IS WP-22, WHICH IS NOT BUILT.** AS BUILT AND AS MEASURED, THE RECORD: **cooperative cancel. STAGE 1 IS BUILT (2026-09-20), AND REVIEWED: the independent design-and-implementation review returned RED with four MUST-FIX items (DM-1 the answer-before-clear ordering, DM-2 the `shutdown`-inside-the-grace leak, DM-3 `Bottom.thrown`, and the `previewLock` race in the new suite's own `R` properties), all fixed here; **STAGE 2 IS BUILT AND RUN (2026-09-20)** -- `tracker/tools/eval-bench.sh`, figures in §11's Instruments section -- **AND STAGE 3 IS NOT BUILT AND IS THE USER'S.** This row was AMENDED to the reviewed design, which departs from its own earlier letter in four places, each recorded here rather than folded away. **(a) THE FLAG.** ONE GLOBAL `@volatile Runtime.cancelTarget: Thread` beside `@volatile Runtime.cancelWhy: Cancelled`, and the check is at the **HEAD of `Runtime.swhnf`**, unconditionally, on every call -- one volatile load and one predictable null-branch; `Thread.currentThread` is reached only while a cancel is armed. NOT a per-thread evaluation context and NOT `Thread.interrupt`: `Preview.takeJob` reads an `InterruptedException` as "stop", `ForeignClasses.Recoverable` and the backends react to an interrupt, third-party code may clear the flag, a JDBC driver may abort its connection. NOT inside `swhnf`'s `case old =>` branch: the design review proposed that cheaper placement and then FALSIFIED it -- `json/Encode.scala`'s `spine` walks a list with `while (true) { Runtime.swhnf(cur) }`, and on a CYCLIC list every thunk it re-reads is already `Evaluated`, so that branch is never entered. **(b) `Cancelled` IS A `ControlThrowable`**: stackless, EXCLUDED by `NonFatal` so `swhnf`'s own capture does not memoise it, and NOT an `Error` -- `ForeignClasses.Recoverable` swallows an arbitrary `Error` into a failed reflective lookup and lets a `ControlThrowable` through (`ForeignClasses.scala:26`, verified by reading before it was relied on). **(c) THE FIVE CATCHES THAT WOULD HAVE SWALLOWED IT**, which this row did not name and without which a cancel silently does not work: `Prim.apply` and `Box.apply` (`Runtime.scala`), `IO.Unsafe.eval` (`session/Lib.scala` -- it would hand the cancel to Ermine-level error handling), the foreign invoke (`session/Session.scala` -- it re-wraps as a `RuntimeException`, which IS `NonFatal` and would be memoised) and **`Bottom.thrown` (`Runtime.scala`), THE FIFTH, FOUND BY THE STAGE 1 REVIEW (DM-3)**: two `Bottom` bodies in `core` FORCE, and `thrown` is what `Encode`, `Doc`, `Pretty.ppRuntime` and `toString` call, so a cancel could be caught there and RETURNED AS A VALUE. Each gained `case c: Cancelled => throw c` as its FIRST arm and was NOT otherwise narrowed. **THE EARLIER CLAIM THAT "every other `catch` of `Throwable` ... was audited and passes a `Cancelled` through" WAS FALSE and is corrected here**: the audit covered `catch` clauses on the call path and missed a by-name body that forces INSIDE one. With `Bottom.thrown` closed, the sweep stands for the rest. **(d) THE WATCHDOG IS TWO-PHASE**, and only when the switch is on; off, `fire` behaves EXACTLY as before. Phase 1 at `timeoutMillis`: arm the flag and NOTHING else -- no answer, no stuck mark, no drain, no notification. Phase 2a, the cancel took: answer 500 with the timed-out text reworded, WITHOUT §4's `stuck` marker (`refusal`, not `stuckRefusal`), **DISCARD THE SESSION UNCONDITIONALLY** -- the escape leaves WHITEHOLED thunks with this thread in `pending`, which a later same-thread force would memoise as "infinite loop detected", and the discard must not ride on the stuck machinery because `stuck` was never set and `clearStuck` returns 0 -- then clear the flag. Phase 2b, `graceMillis` (1000 ms, a constant) later and still in flight: CLEAR THE FLAG FIRST, then do exactly what the watchdog did before, and Q10's recovery applies unchanged. **(e) A USER `$/cancelRequest` DOES NOT INTERRUPT** -- a deliberate departure from this row's earlier text, for three recorded reasons: the extension passes no `CancellationToken` today so nothing sends one, a discard costs a boot, and the watchdog covers the case that matters. `userAsked` is on the `Cancelled` class for a future client and nothing sets it true. **(f) `isFatal` GAINS ONE DOCUMENTED EXCEPTION**: a `Cancelled` is NOT fatal for the stuck machinery, although it is a `ControlThrowable` and so fails that method's half (2). It is sound ONLY because the cancel path discards the session unconditionally; if that discard is ever made conditional the exception must go with it, and `isFatal`'s scaladoc says so. **(g) WHAT THE MECHANISM CANNOT CANCEL**, because none of it reaches `swhnf`: a loop inside ONE primitive, the relational row loop (`relational/package.scala`'s `driveLeftId`), a JDBC scan, and a thread parked in `SessionTask`'s `future.get` or a thunk's `latch.await`. **Phase 2b is the fallback for all of them.** **(h) THE FLAG IS CLEARED IN FIVE PLACES**: before the ANSWER on the cancel path (DM-1 -- `clearCancel`, `discardSession`, then `finish`, so the answer's claim is true when it is sent), at phase 2b before the fallback, in `runJob`'s `finally` for every job, in `Preview.cancelTimer` (DM-2 -- the `shutdown`-inside-the-grace path that no other clear reaches, and the one that matters in the unforked test JVM), and in `Preview.takeJob`, which logs loudly. **THE WRITES THEMSELVES ARE BEHIND `Runtime.armCancel` / `Runtime.disarmCancel`** (S1/S2), which enforce the order and the identity guard in one place and let an arm be REFUSED when another thread's is live; the fields are `private[Runtime]` and `swhnf` reads them directly. **(i) THE SWITCH** is `ermine.preview.cancelOnTimeout`, read by `applySettings` by both routes like the other two settings, ill-typed values refused out loud, DEFAULT FALSE. It is NOT exported in `editor/vscode/package.json`: an export is only useful once the default is a live question, which is stage 3's, and adding it now would offer the user a switch this document says is not theirs to flip yet. **DEFAULT-OFF DOES NOT MAKE THE CHANGE FREE** -- the load and the branch are in the binary regardless, and FLIPPING THE DEFAULT ADDS NO PER-FORCE COST for the same reason. Stage 2 measured what carrying them costs: nothing distinguishable on an ordinary fold, and a suggested but not established ~5 % on the `swhnf`-densest workload (§11) | **STAGE 1 (done 2026-09-20)**: `TestPreviewCancel`'s **ten** properties (§11) pass [**count corrected 2026-09-20 by WP-24's review: this cell read "nine"; §11 and `b7b93daa`'s own message both say TEN (5 `Runtime`-level, 5 through a real bench)**], `TestLspRobustness` is unchanged and still inside its cap, and a looping render is cancelled and the next render boots a new session, MEASURED. **STAGE 2 (done 2026-09-20; its WRITE-UP reviewed RED and corrected without re-measuring)**: the evaluator A/B of §11's Instruments row, BUILT as `tracker/tools/eval-bench.sh` and RUN in two worktrees with the editor closed (`lsp=0 console=0 serve=0 ermine-jvm=0` checked before every one of the 30 forks). THE ANSWER IS NOT ONE NUMBER, AND IT IS WEAKER THAN A NUMBER: on the ordinary build-and-fold workload nothing is distinguishable (+2.9 % and -1.4 % in two runs, every test p >= 0.12, estimators disagreeing in sign). On the `swhnf`-densest workload -- re-folding a list whose cells are already `Evaluated`, which is the shape the head placement exists for -- **W2 moved +5.8 % and +4.9 % in the same direction in two runs with the pair order reversed, and every estimator (fork medians, pooled mean, pooled median, per-fork minima, every leave-one-fork-out) agrees in sign; a central estimate is about +5 %. No test on 5 forks per side reaches conventional significance -- exact stratified permutation over both runs p = 0.089, Mann-Whitney on the A-first run p = 0.095, sign tests p = 0.38 and 1.0 -- and a hierarchical bootstrap CI on the ratio includes zero in both runs. The instrument suggests a cost of roughly 5% on the swhnf-densest workload; it does not establish one.** [**quotation corrected 2026-09-20 by WP-24's review: this cell rendered that sentence's percent sign as "5 %"; §11's verbatim block is the authoritative copy and reads "5%", which is what Q13 and §11's own lead now quote character for character**] Two further corrections the review forced: the delta is the WHOLE STAGE 1 COMMIT's effect on evaluation (the head check PLUS the `case c: Cancelled => throw c` arms in `Prim.apply`, `Box.apply` and `Bottom.thrown`, whose bytecode sizes were never measured), not the head check alone; and the derived <= 73 ns per check is an UPPER bound from a LOWER bound on the count, so it is compatible with a true cost of 1 ns and cannot be used to argue the load is not the cause -- at a realistic 40-100 `swhnf` calls per element-visit it falls to 2.4-7.3 ns. The check does add 44 bytes of bytecode to `swhnf` (216 -> 260), which excludes the bytecode-size inlining threshold story and nothing more. §11 carries the table, the tests, the six deviations, what is MEASURED versus DERIVED versus UNVERIFIED, and the costed options that would make this decisive (none run). **STAGE 3, THE USER'S**: the default is flipped only by them, on stage 2's figures | pr (stage 1, done) + instrument (stage 2) + the user (stage 3) |
| WP-7 | extension: **Ermine: Preview Report...** as a (file, binding) picker over `ermine/preview/reports` with per-workspace memory and free-text fallback, **Ermine: Render Report to JSON** into an untitled editor tab, `ermine.preview.roots` (resource scope, absolutised), re-render on `invalidated`, the `ermine.maxHeap` export; **(Q11, decided 2026-09-20) re-render when the picked report's own file is created or changed while its last answer was a PLACEMENT 404** (not a `Runner` 404: that module loaded, so `invalidated` already covers it and a second trigger would double-render), told apart by **Q15's `reason` key** (§4) -- ONE SMALL SERVER CHANGE, in `lsp/Preview.scala` only, decided by the user after WP-7's review showed no client-side test could be exact; **(Q8/Q10) the stuck banner of §5**, fed by `"stuck": true` on a refusal and by `ermine/preview/stuck`, carrying the **Ermine: Restart Language Server** button and clearing on `{stuck: false}`, **with the `seq` high-water mark RESET on the language client's Stopped -> Running transition** (§4's rule (1), DD-2: `seq` is per-process and restarts at 1, so a client that kept the old mark across the restart the watchdog's own message asks for would ignore the fresh server's `{stuck: true, seq: 1}` for the life of its session); **(Q9) the `ermine.preview.timeoutSeconds` and `maxDocumentBytes` exports, with "0 = no watchdog" in the setting's description** | on `core/src/test/resources/doc/Sales.e` with no setting the picker offers `report : Query -> Node`; **the tab shows `{"status": 400, "path": "$.params", "message": "the required key \"fromDay\" is missing"}`** (WP-8 turns it into a document); saving `Sales.e` updates the tab with no restart; moving `Sales.e` away and back re-renders it by itself; no webview. **THE 400's WORDING IS THE MEASURED ONE and this row was amended (2026-09-20)**; AS FIRST WRITTEN it read "the tab shows a 400 naming `$.params.fromDay`", which no client can produce: a MISSING required key is reported at the path of the OBJECT that should have held it with the key in the message (`json/Decode.scala:723-725`), and `$.params.fromDay` is the path of a key that is PRESENT and ill-typed -- `{"fromDay": 5}` answers "expected a date string yyyy-MM-dd, found the number 5" there, which is WP-8's case, measured. A per-key path for a missing key would be a change in `json/Decode.scala` and was NOT made | manual + commit smoke / ~1 day |
| WP-8 | **BUILT, ALL FOUR STAGES — S1, S2, S3 AND S4 — 2026-09-21..23. S1, S2 AND S3 HAVE BEEN INDEPENDENTLY REVIEWED; **S4 WAS REVIEWED RED/RED ON 2026-09-23 BY AN INDEPENDENT REVIEWER, A FIX ROUND HAS BEEN APPLIED, AND THE RE-REVIEW IS PENDING** (the orchestrator amends this once it is in). THE FIRST DONE-WHEN CLAUSE IS STILL BLOCKED ON Q21, WHICH IS THE USER'S, AND NO STAGE HAS CHOSEN IT.** **AMENDED 2026-09-23: Q21 IS DECIDED BY THE USER (fix `Sales.e`, ticket the engine as WP-29) AND THE FIRST DONE-WHEN CLAUSE IS MET AS WRITTEN** -- `Sales.e` builds `byDay` with `relationWithHeader`, and the first pick's today-dates skeleton renders `ok=true` with an empty four-column table (MEASURED, `scratch-widget-preview/q21-sales/` (one `bin/ermine-lsp` boot, `captures.json`; `IMPL-REPORT.md` has the exact lines)); every "BLOCKED ON Q21" below is superseded by this sentence. No extension code moved. Nothing in this ticket has been observed in VS Code by anyone, and the packaged `.vsix` is still 0.1.9 (S4 ran with no `npm install`). **S4 OF FOUR (THE EDGES) IS BUILT, 2026-09-23; REVIEWED RED/RED THE SAME DAY (4 must-fixes: the overwrite arm's fail-open DISJUNCTION, a -1-tolerant pin, the wedge hold spent before the work, a model that dropped `plan.shape`; plus the modal-to-write TOCTOU as a decision); FIX ROUND APPLIED, RE-REVIEW PENDING — see §6's "S4 review and fix round". `editor/vscode` ONLY — JavaScript, JSON and documentation, extension 0.1.9 -> 0.1.10; NO Scala, NO server change, NO wire change.** It builds **U3's `Ermine: Write Params Skeleton`**, the first and only thing in this extension that may REPLACE a params file — after a MODAL that names the file, where only the exact string `Replace` consents — and it is locked from the outside rather than by care: the new `explicitOverwrite` mode does NOT authorise itself, `core.writeStep` refuses it unless the CALLER also passes the permission, exactly one call site passes it, and every pre-S4 call site passes two arguments so the automatic path can never reach it. The command clears the wedge mark (an explicit command is consent, as the render command already is) and still asks WP-22's one consultation with `explicit`, so a future caller with another trigger is judged; `writeParamsSkeletonCommand` has ONE direct caller and the orphan notification's button goes through `executeCommand`. It builds **D6's ORPHAN NOTICE** — the params files under `.ermine/preview/<Module>/` compared with the bindings `ermine/preview/reports` offers, once per (module, binding) per SESSION, with a button and **nothing ever deleted** (pinned: the extension contains no `fs.delete`, no `unlink`, no `rmSync`) — failing CLOSED on an unreadable directory, on a `reports` that is not an array, on an EMPTY one, and on anything that is not a plain file. **A RENAMED MODULE IS NOT COVERED AND IS RECORDED AS SUCH**: detecting it costs one `ermine/preview/reports`, a job that COMPILES a module, per `.e` file in the workspace. It closes **G5** outright: all FIVE non-object params roots — `Int`, an all-nullary enum, `Maybe X`, `Json`, `()` — were MEASURED end to end against a real `bin/ermine-lsp` and **all five render `ok=true`** (`scratchpad/wp8-s4/measure.py`), and the first-pick notice now says what the value MEANS rather than only that it is not an object. It closes **G6 and G3** outright with a table test each (the named reason, the sentence, the channel line, no write, no schema request, and the orphan machinery unreachable). **TESTS 266 -> 303**, green, with a FOURTH ASYNC MODEL for the command; **41 mutants on a copy, round 2: 41 killed, 0 survivors**, eight of them REVERSE and three in the dangerous direction. **THE INDEPENDENT REVIEWER'S OWN BATTERY WAS 25: 22 KILLED, 1 KILLED ONLY BY HANGING THE SUITE (R13), 2 SURVIVORS (R16, a -1-tolerant pin; R24, the unreadable-directory line) — all three closed in the fix round; the fix-round battery (the 25 re-targeted + 21 new reverse mutants) is 46 run, 46 killed BY NAME, 0 hangs, 0 survivors, and the suite is 303 -> 313 after round 2 (MEASURED, `scratch-widget-preview/wp8s4-fix/`).** **THE TWO THAT SURVIVED ROUND 1 WERE BOTH NEUTERED GUARDS** — `if (false)` around the whole modal (the command then overwrote committed source with no question, 303 tests green) and `openParamsDocument`'s `always` dropped at its definition — and both are now whole-statement pins. **AND S4 FOUND A LIVE TRAP IN THE PINS' OWN TOOL**: `codeOf` did not know what a string is, and `findFiles("**/*.e")` opens a block comment; it was unclosed and therefore harmless by LUCK until S4 added a JSDoc whose `*/` closed it, at which point **124 lines of `pickReport`, `renderCommand` and `activate` disappeared from what every statement pin reads** (MEASURED: the picker's trigger pin failed with its source line untouched). Had the new block landed a few lines later the deletion would have been SILENT. `codeOf` is a scanner now, with a table test and two mutants of its own. **A SECOND `-1` PIN was found and fixed** (the params-document pin compared two `indexOf`s and one needle moved to `-1`, where `> -1` is true) — the S3 review had already found one of that shape. The as-built detail, the measured table, the UNOBSERVED list and the six new manual steps (B22-B27) are in section 6's S4 block. **S3 OF FOUR (THE FIRST PICK WRITES) IS BUILT AND INDEPENDENTLY REVIEWED, 2026-09-21/23. THE REVIEW RETURNED DESIGN RED AND IMPLEMENTATION RED ON DEFECTS IT REPRODUCED; ALL FIVE MUST-FIXES AND TEN NITS ARE APPLIED.** The findings that matter beyond S3: **M-1, the FOURTH occurrence of this branch's model/glue divergence** -- deleting the one word `paths,` from `prepareParams`'s missing-file literal turned the WHOLE STAGE off, no file ever written and no schema ever asked for, with 249 of 249 tests green (MEASURED, reproduced) -- now closed STRUCTURALLY, by minting every object the glue hands one of its own decisions in ONE exported builder the MODEL calls too; **M-2**, a fail-OPEN `else` at the one site that can destroy committed source (`mode: "ifabsent"` overwrote `{"COMMITTED":"SOURCE"}` on a real disk), now a fail-CLOSED pure `writeStep` that refuses the params file by any route but the create; **M-3, SYMLINKS, which S1 handed to S3 in the shipped source and S3 neither resolved nor mentioned** -- a schema file symlinked outside the workspace was written THROUGH from the REFRESH path, which is reachable from an ANSWER -- now a `stat`-and-refuse policy over every target and every `.ermine/` component; **M-4**, the one-render hand-off, which could show NO document and NO message on a first pick, now an explicit `scheduleRender` carrying THIS render's own trigger (which also repairs N-3); and **M-5**, a README promise stronger than the code (whitespace, not only zero bytes, was written over). **42 mutants round 2, 42 killed, 0 survivors**, and the explorer answers 0 at 1,948,716 and 3,257,436 sequences. **TESTS 249 -> 261, and 266 after a delta re-review the same week** -- DESIGN GREEN, IMPLEMENTATION RED on **D-1**, a shape disagreement between the glue and the pure core that no faithful model can see: three of the five schema failures answered a BARE problem where the callers tested a WRAPPED one, so they fell through the handler and the D8 refresh wrote the literal text `undefined` into the schema file (MEASURED, reachable from an ANSWER); plus **D-2**, `statType` reading every throw as "not there" and voiding the symlink defence, and **D-3**, three M-3 sites with no pin. All fixed; **55 mutants, 55 killed**. The review's own table, its three added real-server cases, its 24-mutant table with what closed each, and an honest correction to "33 killed, 0 survivors" (it did not cover the neutered-guard class) are in section 6's review block. **AS FIRST BUILT, 2026-09-21:** `editor/vscode` ONLY -- JavaScript, JSON and documentation, extension 0.1.8 -> 0.1.9, plus ONE line in this repository's own `.gitignore`; NO Scala, NO server change, NO wire change. IT IS THE FIRST VERSION OF THE EXTENSION THAT WRITES TO THE DEVELOPER'S DISK.** On the first pick of a report with NO params file it asks `ermine/schema {uri, binding, roots}` -- with the SAME roots the render carries (Q7, one boot) -- writes `.ermine/preview/.gitignore`, `<binding>.schema.json` and the skeleton `<binding>.params.json` in that order, and opens the params document beside the render without stealing focus (U2). On later renders it keeps only the SCHEMA file fresh (D8). **THE PARAMS FILE IS NEVER OVERWRITTEN**, and the check-then-write race is answered rather than narrowed: `WorkspaceEdit.createFile({overwrite:false, ignoreIfExists:true, contents})` (documented; whether it is ATOMIC is UNVERIFIED, so the file is READ BACK) and the one thing this extension will ever write over is ZERO CONTENT. **THE WRITE PATH IS REACHABLE FROM ONE BRANCH ONLY** -- `renderNow`'s no-file branch -- which makes the write -> watcher -> render -> write loop unwritable rather than avoided, and three source pins hold it (`core.paramsWritePlan` has exactly one caller; `firstPickSchemaAndWrite` one; `refreshSchemaFile` cannot name the params path at all). **A SCHEMA REQUEST IS AN AUTOMATIC ACTION ON THE PREVIEW QUEUE AND GOES THROUGH WP-22's ONE CONSULTATION**, now reached from a THIRD place, because `Runner.paramSchema` COMPILES the report -- `Session.loadModules` then `Session.eval(binding, ...)` under `evalLock` (`json/Runner.scala:849-852`), and `lsp/Preview.scala:596-598` says so in the server's own words: *"THE WATCHDOG covers it: `paramSchema` compiles the report, which evaluates the binding, which is the very thing that can fail to terminate."* **`fx.schema` IS WIRED** (it only logged before), taking that item from S4's row with its reason recorded. **NEW PURE FUNCTIONS**: `isoDay`, `schemaOrder` (G15), `shouldRefreshSchema` + `SCHEMA_REFRESH_TRIGGERS` (D8), `schemaAnswerOutcome`, `schemaRequestFailure`, `mayUseSchemaAnswer` (D7), `schemaFileNeedsWrite`, `paramsWritePlan`, `paramsWrittenNotice`, `schemaProblemNotice`, `schemaNoticeKey`, and `TRIGGER_SCHEMA` -- declared in `RENDER_TRIGGERS` and, under the written membership rule, in `UNCONFIRMED_TRIGGERS`. **33 new tests, 216 -> 249, green**, including a THIRD ASYNC MODEL (the whole first-pick sequence over a model disk) and 24 new source pins. **33 MUTANTS RUN ON A COPY, 33 KILLED, 0 SURVIVORS, 8 OF THEM REVERSE MUTANTS** (`scratchpad/wp8-s3/mutate.py`); five of them survived the first round and the pins that let them through were strengthened, and ONE was a real defect the mutation run itself found (see below). **MEASURED against a real `bin/ermine-lsp`, one boot, no editor** (`scratchpad/wp8-s3/measure.py`, log beside it), with the SHIPPED functions writing real files: see section 6's S3 block for the table. **WHAT IT DOES NOT DO**: U3's `Ermine: Write Params Skeleton` command is NOT built, because the four-stage plan assigns it to neither S3 nor S4 explicitly and D6 -- the orphan message that offers it -- is S4's; the repo `.gitignore` line is added to THIS checkout BY THIS CHANGE rather than written into the user's root file by the extension, **and that reading of U7 is the implementer's INTERPRETATION, flagged here for the reviewer and the user** (the alternative, offering it through a notification button, is named and not built). **THE FIRST DONE-WHEN CLAUSE IS STILL BLOCKED ON Q21, AND S3 DOES NOT CHOOSE**: S3's code is identical under options (a) and (b); under (c) only `isoDay`'s caller and `skeletonFrom`'s `today` argument move. MEASURED on the bytes the shipped code writes: `Sales`'s first pick answers the 500, and the same file with in-range dates renders `ok=true`, a 1407-byte document. ~~**S4 IS NOT BUILT.**~~ (**true when S3 was written; S4 WAS BUILT 2026-09-23 -- see the head of this cell**) **S2 OF FOUR (SENDING IT) IS BUILT, 2026-09-21, AND IS NOT YET REVIEWED. `editor/vscode` ONLY -- JavaScript and documentation, extension 0.1.7 -> 0.1.8; NO Scala, NO server change, NO wire change, and NOTHING IS WRITTEN TO DISK.** With a params file already present the extension reads it from DISK at SEND time (`vscode.workspace.fs`, section 2.4's "saved files, not buffers"), sends its content as `params`, and re-renders when it changes -- `onDidSaveTextDocument` and a `createFileSystemWatcher` on the params path, both through the existing 150 ms coalescer. S1's pure core gains `paramsFolderFor` (G1: the INNERMOST workspace folder containing the report, never `folders[0]`), `meansFileMissing`, `mayStillSend` (**the stage's reason for existing**: the read is an `await` between deciding to render and sending, and a pick change, a roots change, a newer render, a restart or the client going away during it must ABANDON rather than send stale params for the wrong pick), `paramsRefusalAnswer`, `markParamsFor`, `paramsNoticeKey`, `paramsMissingNotice` and `relativeGlob`; the glue gains `prepareParams`, `readParamsFile`, `paramsPathsFor`, `workspaceFolderPaths`, `paramsNoticeOnce` and `installParamsWatcher`, and the wedge mark is now fed the params actually sent at every site that can SET it. **50 new tests, 166 -> 216, green**, including a SECOND ASYNC MODEL of the send path in `restartModel`'s style. **MUTANTS ACROSS ALL THREE BUILD ROUNDS: 14 + 27 + 18 RUN, ALL KILLED BUT ONE, PLUS 15 MORE RUN BY THE FINAL RE-CHECK ITSELF (13 killed, 2 provably equivalent).** **THE ONE SURVIVOR, IN EVERY ROUND, IS NAMED**: `installParamsWatcher` returning before it registers anything, a guard kept and neutered, which no pin can see and no model can reach -- `tracker/WP-7-MANUAL-CHECKLIST.md` §2.35 is its only observer. **MEASURED against a real `bin/ermine-lsp` with no editor** (`scratchpad/wp8-s2/measure.py`): a real in-range file on disk renders `ok=true`; a BOM and a key reorder render the SAME document; a wrong key earns `400 "the key \"fromDy\" is not allowed here"`; an unparseable file never reaches the server. **S2 DOES NOT DEPEND ON Q21** -- it needs a hand-written file, so the first-pick question does not arise until S3. **IT WAS INDEPENDENTLY REVIEWED THE SAME DAY -- DESIGN RED, IMPLEMENTATION RED, ON REPRODUCED DEFECTS -- AND ALL NINE MUST-FIXES AND ELEVEN NITS ARE APPLIED**: the `roots-changed` arm could not fire in the real glue (the pick was captured by REFERENCE while the roots handler mutates it in place) and the model's own test hid it; four ways of neutering the gap check survived the whole suite; `paramsFingerprint` still collapsed `null` into `{}`; learning the module name rendered nothing; **and the DESIGN one, which is the user's own sentence: a params save while `held` whose parameters had NOT changed re-issued the wedge with no question, and this document recorded that as settled.** It now asks, through the same held question, from a SECOND place that reaches the SAME one consultation function. **AND A DELTA RE-REVIEW THE SAME DAY RETURNED IMPLEMENTATION GREEN AND DESIGN RED ON THREE MORE, ALL FIXED**: it drove the real reducers in the glue's order over 579,194 sequences and found **5,097 renders of a held report with no user action** -- a `roots` change that moved nothing (D1), an undeclared trigger permitted by a fail-OPEN consultation (D2), and an evidence trigger whose report wedged again inside the coalescing window (families B and C). **The same exploration now answers 0**, `roots` is in the refused set under a written membership rule, an unknown trigger is refused AND named, a render whose mark is newer than its own trigger is held, and "Not now" is remembered per (mark, params) so that format-on-save asks once rather than once per save (D3). The as-built detail, the review's own table, the control table and the UNOBSERVED list are in section 6's S2 block; the eleven new manual steps are `tracker/WP-7-MANUAL-CHECKLIST.md` §2.33-2.42 (with §2.41b). ~~**S3 AND S4 ARE NOT BUILT.**~~ (**true when S2 was written; S3 WAS BUILT the same day, later, and S4 on 2026-09-23 -- see the head of this cell**) **S1 OF FOUR (THE PURE CORE) IS BUILT AND INDEPENDENTLY REVIEWED, 2026-09-21. THE REVIEW RETURNED RED ON BOTH AXES WITH FIVE MUST-FIXES; ALL FIVE AND EVERY NIT ARE APPLIED HERE.** The review also CAPTURED a real `ermine/schema` answer and it is BYTE-IDENTICAL to the read-derived fixture, so S2's capture-and-diff obligation is discharged. Two of its findings matter beyond S1: **D-1**, the design's own failure with the sign reversed -- injecting the `$schema` property into a SHARED `$defs` entry let the editor accept a NESTED `$schema` that the strip does not remove and the server 400s (MEASURED) -- now fixed with a root-level COPY; and **D-2**, a recorded consequence that was false: `Sales` on first pick does NOT render an empty document, it answers a **500** (MEASURED, with controls showing the skeleton itself decodes). The false claim is withdrawn everywhere, the measurement is recorded in section 6, and **WP-8'S FIRST DONE-WHEN CLAUSE IS BLOCKED ON Q21, WHICH IS THE USER'S.** **S1 IS PURE ONLY: `editor/vscode/src/preview-core.js` gains `paramsPaths`, `skeletonFrom`, `schemaFileFor`, `schemaFileText`, `paramsToSend`, `shouldRerenderOnParamsSave`, `isCurrentSchemaAnswer`, `credentialKeyWarning` and `paramsGitignoreText`, plus a READ-DERIVED (NOT CAPTURED) fixture `test/fixtures/sales-query.schema.json` SINCE CONFIRMED BYTE-IDENTICAL TO A REAL CAPTURE, plus a verbatim copy of the `UserTree` exporter golden as the recursive fixture D-1 turns on; 68 new tests, 96 -> 164, green. `src/extension.js` IS UNTOUCHED -- nothing is wired, no watcher is registered, nothing is written to disk, nothing new goes on the wire, and the extension is still 0.1.7. `paramsFingerprint` is REUSED, not re-minted. S1 found that D1 is wider than the review had it (a RECORD params root and a multi-constructor root also need the `$schema` injection, not just the object a root `$ref` names) and closes the wider hole; details, the G-item ledger and the one decision S1 had to make itself (an EMPTY params file is a named refusal, not `{}`) are in section 6's S1 block. S2, S3 and S4 were not built THAT DAY; S2 was built the same day, later -- see the head of this cell.** **AMENDED 2026-09-20. WHAT THE USER DECIDED ("go for it") IS EXACTLY U1-U8, the eight questions the WP-8 design review put to them** (its §5, "Questions that are the user's"), each taken as the review recommended it. **D1-D8 are the DEFECTS the review found in this row and S1-S4 is its four-stage BUILD PLAN -- the review's own recommendations, not the user's decisions**; they are recorded, not ratified. All of it, with the reworded done-when, is in §6's amendment block, which draws the same line and is authoritative for this ticket. WP-8 NEEDS NO SERVER CHANGE (no Scala compiles, no JVM gate moves), and it EXPORTS `paramsFingerprint` for WP-22.** The row as written: params: `.ermine/preview/<Module>/<binding>.params.json`, the skeleton from the schema on first pick, `<binding>.schema.json` beside it with a relative `$schema`, `$schema` stripped before sending, re-render on save, the orphan message, the one `.gitignore` line | **AMENDED 2026-09-23: THE FIRST CLAUSE ("`Sales` renders a document on first pick with no hand-written JSON") IS MET AS WRITTEN** -- Q21 decided by the user, `Sales.e` fixed, the today-dates first pick MEASURED `ok=true` with an empty four-column `byDay` table (`scratch-widget-preview/q21-sales/` (one `bin/ermine-lsp` boot, `captures.json`; `IMPL-REPORT.md` has the exact lines)); the "BLOCKED ON Q21" sentences that follow are superseded. The manual half is still unrun. **ALL FOUR STAGES BUILT; S4's OWN DONE-WHEN IS MET (2026-09-23) — each edge has a unit test or a named log line, and the WP-7 checklist gained B22-B27 — BUT THE ROW'S FIRST CLAUSE IS STILL BLOCKED ON Q21, AND THE MANUAL HALF IS STILL UNRUN.** **FIRST CLAUSE BLOCKED ON Q21 (2026-09-21). THE U2/D4 REWORDING THAT STOOD HERE IS WITHDRAWN**, because it was measurably false: it promised that `Sales` renders a document on first pick, an empty one until its dates are edited. The S1 review sent the skeleton's own params to a real server and the answer is `ok=false, status=500` ("an empty relation built from no rows carries no columns"), with controls showing the skeleton itself decodes -- the measurement and its five-row control table are in §6's S1 block, and what first pick SHOULD show is **Q21, the user's**. Until Q21 is answered this clause has no agreed wording and WP-8 cannot be signed off against it. THE OTHER CLAUSES STAND UNCHANGED: completion and a red squiggle for a wrong key in `Sales/report.params.json`; saving it re-renders; renaming the binding shows "no params for"; `git status` shows the params file and not the schema. HISTORY, struck, kept only so the record is legible: as ORIGINALLY written the first clause read "`Sales` renders a document on first pick with no hand-written JSON", and the 2026-09-20 rewording added a promise of an empty first document to it | commit smoke + manual / ~1 day |
| WP-9 | **BUILT, REVIEWED AND MERGED 2026-09-21.** Commit `c2c83cdb` on branch `wp9-bundle` (worktree `ermine-scala-wt-wp9-bundle`), reviewed **DESIGN GREEN / IMPLEMENTATION GREEN** by an independent reviewer -- every number reproduced, all five bundle tests mutation-live, the merge surface empty -- and merged into `widget-preview` at `cdd90193`. `tracker/WP-9-AS-BUILT.md` IS FOLDED INTO THIS DOCUMENT (§5's Bundle, `devtool`, writers-global, Host-page-logic, Stuck and checklist rows and its findings block, §11's Host page row, §13's Q1, and this row); **this document is now the authority and that file is history**. **NOTHING IN WP-9 HAS RUN IN A BROWSER OR IN A VS CODE WEBVIEW: no CSP has been enforced against these bundles by anything, no panel has loaded them, and every figure below is from `node`, `webpack` and `node --test`.** WHAT IS IN THE TREE: `client/webpack.config.js` (81 lines) with TWO entries -- `ermine-client`/`window.ErmineClient` and `ermine-host`/`window.ErmineHost` -- `devtool: 'source-map'`, no loaders; `client/src/host/index.ts`, the presentation reducer (nine kinds, 19 `node --test` cases); `client/test/bundle.test.ts` (5 tests); `client/scripts/bundle-watch.js`; and Q1's corrections in `src/index.ts`, `src/legacy.ts`, `README.md`. **TWO DEPARTURES FROM §5's Bundle ROW ARE THE ORCHESTRATOR's DECISIONS -- REVERSIBLE, AND NOT THE USER'S**: tsc-first instead of `ts-loader` (the review's D5, recommendation (b); two constants in `webpack.config.js` switch it back) and the second entry (D4, forced by §5's own nonce-less CSP). **THE USER'S DECISIONS HERE ARE THREE AND ONLY THREE**: webpack itself (settled, §5), the second worktree (*"do a second worktree for the bundle."*) and Q19. MEASURED: `ermine-client.js` **327,103 B** and `ermine-host.js` **10,832 B**, byte-identical across rebuilds, **zero** `eval(` and **zero** `new Function` in either; the client suite went **65 -> 90 tests** (82 pass / 8 skip with no bundle built, 87 pass / 3 skip with one, 0 fail either way); the dependency delta WP-17 needs is **+95 packages** (lockfile 69 -> 164 entries) and **`client/node_modules` 49 -> 81 MB**. **STILL OPEN, AND NOT WP-9's**: whether the built bundle is COMMITTED (`client/dist/` is gitignored at `.gitignore:10`, untouched -- WP-17's call), WP-17's vendoring choice, and PRODUCTION MODE / MINIFICATION (`mode: 'development'` only, nothing minified, no `production` config -- not decided; adding it later is a `--mode` argument). UNVERIFIED: byte-stability across a webpack patch bump, and whether webpack's watch write is atomic enough for §5's 200 ms debounce. **THE ROW AS IT STOOD WHILE IT WAS BEING BUILT IS KEPT BELOW AS HISTORY; its Q19 paragraph is the USER'S DECISION and stands exactly as written.** **BEING BUILT NOW, 2026-09-20, IN A SEPARATE WORKTREE BY THE USER'S AUTHORISATION** (*"do a second worktree for the bundle"*): `ermine-scala-wt-wp9-bundle`, branch `wp9-bundle`. **NOTHING OF IT IS IN THIS WORKTREE OR ON `widget-preview`, and it is not built, not reviewed and not merged.** Side worktrees write their own as-built notes files and do NOT edit this document; this row is amended when it merges. **ITS Q19 IS NOW DECIDED (§13): `'unsafe-eval'` is allowed in the PREVIEW WEBVIEW's CSP only, so the committed writers bundle loads as it is -- and WP-9's OWN bundles must STILL contain no `eval(` and no `new Function`, which is D9's static test and stays a done-when, so the flag can be removed the day the writers bundle is rebuilt.** **READ §5's WP-9/10/11 FINDINGS BLOCK (2026-09-20) BEFORE STARTING THIS: a read-only design review, nothing decided.** Its D1 (the committed writers bundle is an `eval` build, new **Q19**), D4 (two entries + a nonce), D5 (ts-loader or tsc-first, open) and D9 (this row's tier gates nothing; two checklist rows can be node tests) all land on this row. As written: webpack browser bundle: config, `npm run bundle` / `bundle:watch`, `devtool: 'source-map'`, output under `client/dist/browser/` | *as written*: "`npm test` unchanged; the bundle checklist of §5 passes under a CSP without `unsafe-eval`". **AS ACHIEVED, 2026-09-21. MET**: `npm test` is green from a clean checkout -- **90 tests, 82 pass, 0 fail, 8 skip** with no bundle built (from **65 / 62 pass / 3 skip** before WP-9), and **87 pass / 3 skip** under `npm run test:bundle` with one built; the five bundle tests SKIP by design when `dist/browser/` is wholly absent and FAIL on a half-built one; `npm run bundle` exits 0 with nothing on stderr and is byte-deterministic; **two of §5's three checklist rows are node tests now**. **NOT MET**: the third checklist row, "`table` renders through the writers global" -- it needs a REAL WEBVIEW and **is no longer blocked on a decision** (Q19 is decided), but nobody has run one; and the CSP half is untested by anything, jsdom enforcing no CSP. The as-written clause "under a CSP without `unsafe-eval`" is superseded by Q19 FOR THE WRITERS BUNDLE and kept in force FOR OURS, where `(b-no-eval)` pins it | nightly (`npm test`) + checklist / ~half a day |
| WP-10 | **AMENDED 2026-09-24 BY WP-34 (Q27 DECIDED, option (i)): `Doc/SalesReport.e` (`report : Node`) RENDERS again, so the done-when MAY NAME IT beside the typed `Sales`; F2 no longer applies.** **AMENDED 2026-09-23 BY PLAYTEST F3: THE PANEL DREW THE LEGACY TABLES EMPTY, GREY AND OVERLAPPING. FIXED IN THE CLIENT BUNDLE, commit pending (§5's F3 row; `scratch-widget-preview/panel-fix/IMPL-REPORT.md`).** `page.ts` now makes the legacy page's tail call, `conf.renderFunction(htmlwriter)`, once after each render. It draws the document on white paper and adds grid and table layout CSS. The done-when (the typed `Sales` renders inline) needs E2 re-run in VS Code after `npm run bundle`. **AMENDED 2026-09-23 BY THE FIRST PLAYTEST: THE FIRST OBSERVED DEFECT (F1).** In a real VS Code the panel never built its page: the 0.1.14 `cspSourceProblem` refused VS Code's real `webview.cspSource`, `'self' https://*.vscode-cdn.net` (a list with a quoted keyword; every test had used one bare token), and the notice page said so. FIX (0.1.15, commit pending): the guard accepts exactly the CSP source-expression grammar per space/tab-separated token (quoted keyword, scheme-source, host-source) and refuses anything else by token; the page's CSP for the real value is pinned exactly; four reverse mutants killed by name (`scratch-widget-preview/playtest-f1/IMPL-REPORT.md`). Also F2: `Doc/SalesReport.e` (`report : Node`) is refused at render, so of the done-when's two fixtures only the typed `Sales` can be shown (Q27). **AMENDED AGAIN 2026-09-23 BY Q25 (the user: *"I'm pretty sure I want typed widget schemas in the typescript rather than matching runtime ermine values fallibly"*; *"Rewrite it."*): `Sales` IS TYPED NOW and draws in the panel with NO error box (`client/test/widgets.test.ts` `(w-sales-panel)`, over the re-captured `ok-sales`), so the done-when may name it beside `Doc/SalesReport.e`; its items table is INLINE (a typed table cannot force deferral), so nothing in it reaches the refusal.** **AMENDED 2026-09-23 BY Q24 (the user: *"Do (a) and (d) now, file (c)."*): THE DONE-WHEN'S FIXTURE IS NOW AN INLINE ONE, `core/src/test/resources/modules/Doc/SalesReport.e` (the report Group E's E2/E9/E10 already use), NOT `Sales`. The panel's rejecting `fetchData` (U6) STAYS; `heading` and `text` now have native renderers in the client (`client/src/widgets/heading.ts`, `text.ts`, uncommitted at the time of writing), so `Sales`'s heading and text draw. `Sales` in the panel is NOT a done-when: its deferred items table is a box BY DESIGN until WP-30 -- and, MEASURED by Q24's implementer (`client/test/widgets.test.ts` `(w-sales-panel)`), ALL THREE of its tables are boxes today for an EARLIER reason: `Sales.e` hands `table` a BARE relation, not `TableProps`, so the client's generated schema refuses each one (`its props are invalid -- columns.0.column: Required`) BEFORE any fetch; the deferred one never reaches the refusal.** **AMENDED 2026-09-23 BY WP-10 S5: S1-S5 ALL BUILT. S1-S4 were each independently reviewed and are committed (`1d83b5a8`, `26d22f61`, `3b162527`, `56f608cd` = WP-11); S5 (= the playtest guide's Group E, E1-E14, plus WP-11's nits N1-N5 and the 0.1.14 `.vsix`) is built and uncommitted at the time of writing -- see §5's WP-10 STAGE 5 block. NOTHING OF WP-10 HAS RUN IN VS CODE: its done-when is Group E. THE DONE-WHEN'S "`Sales` renders inline" IS NOT MET BY `Sales` AS WRITTEN (it asks for a `Deferred` relation, which the panel refuses): Q24 in §13.** **THE S4 TEXT, KEPT AS HISTORY: STAGE 4 OF 5 (= WP-11, THE WRITERS) IS BUILT (reviewed since and committed `56f608cd`); STAGES 1-3 ARE COMMITTED (`1d83b5a8`, `26d22f61`, `3b162527`). S5 (the playtest's Group E) REMAINED.** S4: extension 0.1.13 -> 0.1.14, `editor/vscode` + client tests/README + docs only (no Scala, no server or wire change, `client/src` unchanged): see the WP-11 row and §5's WP-11 block. **THE STAGE 3 TEXT, KEPT AS HISTORY: STAGE 3 OF 5 (FETCH STUB, WATCHER, BANNERS) IS BUILT; REVIEWED 2026-09-23 DESIGN GREEN / IMPLEMENTATION RED ON A DOCS MUST-FIX, CORRECTED, COMMITTED SINCE (`3b162527`); STAGES 1 AND 2 ARE COMMITTED (`1d83b5a8`, `26d22f61`). S4 (= WP-11, the writers) AND S5 (the playtest's Group E) REMAIN.** S3: extension 0.1.12 -> 0.1.13, `editor/vscode` + `client/src/host/page.ts` + `client/test` + `scripts/gates.sh` only (no Scala, no server or wire change): the bundle watcher (W4: the folder, `*.js`, one coalesced reload per build after a 250 ms quiet period, the reducer's `reloadBundle` banner meanwhile; the notice page when the bundle vanishes or is half-built and the page again when it returns, H4), U6's rejecting `fetchData` with its final wording, `connect-src` pinned absent, and **`gate_client` registered at nightly**. See the WP-10 STAGE 3 block in §5. NOTHING HAS RUN IN VS CODE. **THE STAGE 2 TEXT, KEPT AS HISTORY: STAGE 2 OF 5 (THE PANEL GLUE) IS BUILT (reviewed since and committed `26d22f61`); STAGE 1 IS COMMITTED (`1d83b5a8`). S3, S4 (= WP-11) AND S5 REMAIN.** S2: extension 0.1.11 -> 0.1.12, `editor/vscode` + `client/src/host/page.ts` + `client/webpack.config.js` only (no Scala, no server or wire change); `extension.js` creates ONE panel on the reveal latch, posts ONE envelope shape behind the ready latch, resyncs on `ready` and on visible, routes answers by `ermine.preview.target` (default `panel`, the `json` tab byte-identical), and shows a static not-built / half-built page; the host bundle's entry is the page bootstrap. See the WP-10 STAGE 2 block in §5. NOTHING HAS RUN IN VS CODE. **THE STAGE 1 TEXT, KEPT AS HISTORY:** **STAGE 1 OF 5 (THE PURE HALF) IS BUILT, 2026-09-23 (reviewed since and committed `1d83b5a8`). `editor/vscode` + `client/src/host` + `scripts/gates.sh` ONLY -- JavaScript, TypeScript, one gate and documentation; extension 0.1.10 -> 0.1.11; NO Scala, NO server change, NO wire change, and `src/extension.js` IS UNTOUCHED: no panel is created and nothing is posted yet.** It follows the WP-10 design review (`scratch-widget-preview/wp10-design/DESIGN-REVIEW.md`), whose staged plan is: **S1** the pure half (BUILT) · **S2** the panel glue (`createWebviewPanel`, `localResourceRoots`, `asWebviewUri`, `ready`/snapshot, `onDidChangeViewState`, dispose, the missing/half-built-bundle banners, the `ermine.preview.target` setting, `present()` replacing `showAnswer` on the reveal latch; H1/H2/H3/H9 async models) · **S3** the rejecting `fetchData`, the bundle watcher (W4), `reloadBundle` -> `webview.html`, the `log` intent, `gate_client` at nightly (H4) · **S4** = WP-11, the writers `<script>` + three CSS `<link>`s + `ermine.preview.writersPath` + the writers-missing banner, whose done-when is the playtest · **S5** the playtest guide's Group E (E1-E12). **S1 BUILT**: `core.panelMessagesFor(view)` (the whole extension -> panel protocol, a SNAPSHOT carrying every slice on both edges), its SHARED view builder `core.panelView(parts)` + `core.panelAnswerStep` / `initialPanelAnswers` (the displaced / generation decisions, by the same functions `renderNow` uses) + `core.unsavedNames`, `core.panelTarget` (U1's contract, not yet a setting), `core.buildPreviewHtml(uris, opts)` + `core.previewCsp` (the CSP exactly, no inline script, writers -> client -> host); `client/src/host/page.ts` (the snapshot fold, no DOM, re-exporting the reducer so S2 can move the `ermine-host` entry to it); **`gate_extension` registered at COMMIT** (U7); 20 extension tests (313 -> 333) and 10 client tests (90 -> 100); 14 REAL answers captured from one `bin/ermine-lsp` boot. See §5's "WP-10 S1" block for the as-built detail, U1-U7 as TAKEN, the measured table and the mutant battery. **THE REST OF THIS CELL IS AS IT STOOD BEFORE S1; W1-W10 have been folded into §5's rows, and D4's nonce (below) is RETIRED by W3, not built.** **READ §5's WP-9/10/11 FINDINGS BLOCK (2026-09-20) BEFORE STARTING THIS: a read-only design review, nothing decided.** Its D10 (`applyMessage` is a PRESENTATION reducer only; every decision stays in `preview-core.js`), D11 (the message list must carry WP-22's `held` and must NOT encode §4's withdrawn rule (5)), D4's nonce and D6 (the writers' CSS needs a `localResourceRoots` entry and a `<link>`) land here, as does the missing "the bundle is not built" banner. As written: webview panel: host page, CSP, `localResourceRoots`, the `applyMessage` reducer and its `node --test`, banner states (initial, error, stale, unsaved, switching, offline, fast mode), `retainContextWhenHidden`, bundle watcher -> reload; `gate_client` registered at nightly. **WHAT WP-9 ESTABLISHED FOR THIS ROW (2026-09-21, folded in from `tracker/WP-9-AS-BUILT.md`).** (1) The host reducer `client/src/host/index.ts` EXISTS and is **PRESENTATION ONLY**: it does **not** arbitrate `seq`, and `(h-stuck-no-arbitration)` pins that it applies a lower `seq` as sent. **The extension is the single writer of that decision** (D10; the split is `preview-core.js` for what is decidable from data and `extension.js:447-456` for what needs the editor). (2) **`Webview.postMessage` is DOCUMENTED to DROP messages to a webview that is not live, and its `true` return "does not mean that the message was actually received"** (`@types/vscode`, READ by the WP-9 review); **ordering is not documented either way (UNVERIFIED)**. The consequence is NOT panel-side arbitration -- arbitration cannot recover a message that never arrived -- but **`retainContextWhenHidden: true`** (already in §5's Lifetime row) **or a resync snapshot on `onDidChangeViewState`**. (3) The message list this panel carries **must include WP-22's `held`** (nine kinds), and the reducer's banner precedence and dimming rule are in §5's Host-page-logic row. (4) **The writers' CSS (D6) and the webview NONCE (D4's second half) are THIS ROW's, untouched by WP-9**, as are `localResourceRoots` and the "bundle is not built" banner. (5) **A packaged `.vsix` CANNOT carry the bundle** (D8): the client lives outside `editor/vscode/`, so a `.vsix` install without the repo has no script -- written down here, at last. (6) `gate_client` **still does not exist** (MEASURED): this row registers it, and until then `client/test/host.test.ts` and `client/test/bundle.test.ts` run under `npm test` and gate nothing. | **an inline fixture renders in the panel: `core/src/test/resources/doc/Sales.e` (checklist E2, E9), no error box** (AMENDED BY PLAYTEST F2, 2026-09-23: `Doc/SalesReport.e` and E10 left this list, since `report : Node` is refused at render; Q27. AMENDED BY Q25, 2026-09-23: `Sales` is typed and qualifies again; AMENDED BY Q24, 2026-09-23; was "`Sales` renders inline", which `Sales` as written cannot meet -- its deferred items table shows the refusal box BY DESIGN until WP-30, and its bare-relation tables are refused by the table schema); editing `client/src/widgets/scorecard.ts` updates the panel without a restart; a 400 from a bad param shows `path` in the banner; the reducer property passes; `scripts/gate.sh run nightly` runs `gate_client` | nightly + manual / ~2 days |
| WP-11 | **AMENDED 2026-09-25 BY S2f-1 (DB programme): D6's three sheets are FOUR. `javafxwriter.css` holds Highcharts' styled-mode rules, and the writers draw every chart in styled mode, so without it every `axisChart`/`pieChart` drew as a black box (MEASURED headlessly; E10 would have failed). It is linked last; `page.ts` counters its JavaFX-window rules (white `body`, fixed `.timeseries`) and holds each chart to 320 px over the writers' window-sized div. Tables unchanged (19 px rows, same stripes). `tracker/db/OBSERVABILITY.md` §11.** **AMENDED 2026-09-23 BY PLAYTEST F3: `table` through `runTabular` was necessary but not sufficient.** The writers draw only when `ermine_htmlwriter_conf.renderFunction` is called, and the page now calls it after each render. Two writers behaviours are countered in page CSS, scoped to the document, and MEASURED in a headless harness: the table pair is sized to the window, and a one-column table's scroller gets the empty main part's 0px height. The writers were NOT changed. E9's eight rows are what the harness draws. **AMENDED 2026-09-23 BY WP-10 S5: REVIEWED DESIGN GREEN / IMPLEMENTATION GREEN AND COMMITTED (`56f608cd`); THE REVIEW'S FIVE NITS ARE CLOSED -- N1 all six `ermine.preview.roots` refusal texts pinned exactly by one test (R18b now dies by name), N2 the dimming / hidden-`re-rendering` sentence in the README and §5's Bundle checklist row, N3 `not an array`, N4 the `<checkout>` wording, N5 the install line names 0.1.14. ITS DONE-WHEN IS THE PLAYTEST: checklist Group E -- E3, E9, E10, E14 (E11 has no fixture; OPTIONAL).** **THE BUILD TEXT, KEPT AS HISTORY: BUILT (AS WP-10 S4); ITS DONE-WHEN IS THE PLAYTEST, NOT A NODE TEST.** Extension 0.1.14. The page loads `htmlwriter.js` first, then the client and host bundles, with `common.css`, `htmlwriter.css`, `htmlwriter_classic.css` (the classic theme chosen by reading the CSS: the dark one re-adds sort arrows through a sprite a webview cannot load), from the new setting `ermine.preview.writersPath` (window scope, absolutised by the roots' own `absoluteRoots`; empty = `<checkout>/../ermine-writers/writers/html/src/main/resources/web`, this machine's layout, not a guarantee), granted as the second `localResourceRoots` entry; the CSP is unchanged. Without `htmlwriter.js` the page loads without the writers (each legacy widget is its own error box), the banner is the reducer's `error` (the document dims) and one channel line is written; the folder is not watched, an explicit command re-checks. See §5's WP-11 block (MEASURED vs INFERRED, the mutant battery). **NO BROWSER AND NO VS CODE HAS RUN ANY OF IT.** **THE S1-S3 TEXT, KEPT AS HISTORY: WP-11 IS STAGE S4 OF WP-10's FIVE-STAGE PLAN (the design review's §5).** S1 built its two SLOTS in `core.buildPreviewHtml` -- the writers `<script>` FIRST, before the client and host bundles, and up to three CSS `<link>`s (`common.css`, `htmlwriter.css`, one theme) -- both optional and unused until S4 supplies the URIs from the new setting `ermine.preview.writersPath` (U3, TAKEN: default `<checkout>/../ermine-writers/writers/html/src/main/resources/web`, the sibling layout being this machine's, MEASURED by the review). **What the browser will find (W9, MEASURED by the review)**: jQuery (14 webpack modules) and Highcharts (11) are BUNDLED in the writers bundle, so no extra `<script>`; no export module, so no `blob:`; the style-box click-through always POSTs and CANNOT work under `default-src 'none'` -- it fails silently BY DESIGN; two sprite `url()`s in the CSS will be blocked (§5's Legacy renderers row names them); `treeMap` stays deliberately unregistered. **S4's done-when is the PLAYTEST** (E9 `table` through `runTabular`, E10 a `pieChart` draws, E3 no CSP violation but the two sprites, E11 the style-box click is inert) -- nothing new is observable in node. **AMENDED 2026-09-21: Q1 IS NOW CLOSED IN CODE BY WP-9** (`c2c83cdb`, merged into `widget-preview` at `cdd90193`): the global's name AND its `DOMContentLoaded` timing are written into `client/src/index.ts`, `client/src/legacy.ts` and `client/README.md`, so the "write it down" half of this row IS DONE and **what remains is a BROWSER**. Its **Q19 dependency is DISCHARGED** (the user decided Q19 on 2026-09-20), and nothing of WP-9 has run in a browser or a webview. The wording below is kept as history. **READ §5's WP-9/10/11 FINDINGS BLOCK (2026-09-20) BEFORE STARTING THIS: a read-only design review, nothing decided.** **Q1 is ANSWERED BY READING** (`window.ermine_htmlwriter`, assigned only on `DOMContentLoaded`), so this row's remaining work is writing that into `client/src/index.ts`/`legacy.ts` and waiting for the event -- and **this row's done-when depends on Q19**, because none of it runs while the writers bundle needs `'unsafe-eval'`. As written: Q1 and the legacy renderers in the panel | *as written*: "`table` renders through `runTabular`; the global's name is written into `client/src/index.ts` and `legacy.ts`". **AMENDED 2026-09-21: THE SECOND HALF IS DONE** -- WP-9 wrote the name AND the `DOMContentLoaded` timing into `client/src/index.ts`, `client/src/legacy.ts` and `client/README.md`, and `(w-no-writer)` pins the error text. **WHAT IS LEFT IS A BROWSER**: `table` rendering through `runTabular` in a real webview. Its Q19 dependency is DISCHARGED. **AMENDED 2026-09-23 BY THE BUILD: DONE-WHEN = THE PLAYTEST** -- E9 `table` renders through `runTabular`, E10 a `pieChart` draws, E3 the webview console shows no CSP violation except `common.css`'s one sprite (`tmbllsprite.png`), E11 a style-box click does nothing and logs; and with `ermine.preview.writersPath` pointed at an empty folder, the writers banner and the per-widget error boxes | checklist / ~half a day |
| WP-12 | `mssql-jdbc` `jre11` in `build.sbt`; one real connect from the preview; `sqlPrimT`'s `"date"` mapping checked; Q3 answered. **DONE-WHEN SPLIT 2026-09-20, because the user plans a LOCAL SQL Server with a password (§8's amendment)** | **(a) LOCALLY, and enough to unblock WP-13/WP-14**: the driver resolves in `build.sbt`, a connect to the local server succeeds (MEASURED), the `"date"` mapping is checked, and the prompted-password path is exercised end to end. **(b) ON THE WORK NETWORK ONLY**: Q3 -- whether the internal CA is in the JDK's `cacerts` or `Windows-ROOT` is needed -- and the first-connect TLS behaviour recorded as observed, with the truststore answer written into §7.3. (a) does not answer (b), and (b) is what the wait for the work server is for **(a) BUILT 2026-09-24 (DB programme, role server; `tracker/db/SERVER.md`): `mssql-jdbc` `13.6.0.jre11` in `build.sbt` (resolves; the classpath gains exactly one jar, sha256 in SERVER.md §0), the launchers' classpath cache rebuilt, and a JDBC smoke (`scalacheck-binding/src/main/scala/TestMsSqlSmoke.scala`, runnable as `tracker/tools/db-smoke.sh`) that connects to the local server with `encrypt=true;trustServerCertificate=true`, runs `SELECT 1`/`@@VERSION`, reads a `date` column through `MsSqlEmitter.sqlPrimT` and creates+drops a `##` temp table (live output in SERVER.md §3). **GATED 2026-09-24: the PR-tier gate `db` (`scripts/gates.sh`, SERVER.md §5) runs `TestMsSqlSmoke` + `TestDbReports` with the password from `db.env`; without `ERMINE_DB_*` both suites register nothing and print "DB suites: not requested", so `suites` never sees a SKIPPED property. STAGE-2 NIT: the gate must not depend on the tier the user has loaded -- it should load xs into its OWN database (e.g. `ErmineGate`, the loader's `load` gaining `--db`); keying on ErmineSales's load stamp and answering UNAVAILABLE off tier xs are the workaround (SERVER.md §5).** NOT built by (a) and moved to WP-13: the connect FROM THE PREVIEW and the prompted-password path end to end (SERVER.md §2 is their design). (b) unchanged.** **WP-12(b)'s SERVER HALF BUILT 2026-09-24 (DB programme stage 2a, `tracker/db/SERVER.md` §6): the connect FROM THE PREVIEW is wired (`ermine/preview/connect` with the password in the request, held connection, `TestPreviewDbLive` MEASURED against ErmineSales); the prompted-password end to end needs the extension half (stage 2c) and a VS Code run. Q3 (work network CA) is still (b)'s and untouched.** **What a DB-backed report needs (DB programme, role reports, 2026-09-24, `tracker/db/REPORTS.md`): nothing in the language or the runner. A module states its relations as `table name : [f1, ...]` (bare name, no `database` block; the column names equal the field names and the column types equal the field types, `Nullable T` for a NULL column), and the host supplies the pair `RunnerConfig(run, scanner)`; `DB.RunUser(driver)(url, user, password)` is the per-request run with a login. MEASURED: the seven twins of the Doc fixtures (`doc/DbFetch*.e`, `modules/Doc/DbSalesReport.e`) render on ErmineSales at tier xs the same documents as the in-memory originals, modulo the order of unordered inline rows, with no T-SQL error (`TestDbReports`, `tracker/tools/db-reports.sh`). What is missing is only on the product paths: `RunnerConfig.backend` / `ermine-serve --db` take no user or password, and the preview is fixed to in-memory SQLite (WP-13).** | instrument / ~half a day each half |
| WP-13 | **SERVER HALF BUILT 2026-09-24 (DB programme stage 2a, `tracker/db/SERVER.md` §6, uncommitted at writing): `ermine/preview/connect`/`disconnect` as preview-queue jobs, validation before any socket (class `profile`), the §8.3 classifier with `kept` (class `connect` spelled `unreachable`), `Throwable` catch + A10 scrub of url/host/user, server-side A9 refusal, the held connection (`Runners.fromPersistentConnection`), the 503 `not-connected`, `disconnected {reason: connection-lost}` on an `isValid` failure, login timeout under the watchdog; the classifier is pinned on constructed exceptions (`TestPreviewProfile`), not a fake registered `Driver` as below; the live connect/render/disconnect/wrong-password run is `TestPreviewDbLive` (the `db` gate). NOT server-side and still open: the extension half (profiles from user scope, the prompt, the trace-`verbose` refusal: stage 2c), the §8.4 credential gate in VS Code, the Settings-Sync answer.** **DESIGN ON THE CODE: `tracker/db/SERVER.md` §2 (2026-09-24, DB programme), with open questions Q-S1..Q-S5, ANSWERED (a),(a),(a),(a),(b).** **EXTENSION HALF BUILT 2026-09-24 (DB programme stage 2c, role extension; extension 0.1.17, uncommitted, unobserved in a real editor):** `ermine.preview.profiles` + `ermine.preview.profile`, **USER SCOPE ONLY (A2, restored by the orchestrator after a first cut with resource scope): `application` scope in package.json, read only as `inspect(...).globalValue` (`core.userScopeProfilesCheck`); a workspace- or folder-scope value is IGNORED and named once in the channel and in the status bar ("profiles set in workspace settings are ignored (user settings only)"); both present = the user value; a mutant that honours the workspace value is killed by name**; validation in `preview-core.js` `profilesCheck` (unknown id, duplicate ids, a `password` key, URL credentials per A9 plus `user@host`, relative `jdbc:sqlite:` per Q-S5 (b), dialect vocabulary = `Backends.scannerFor`'s); ONE `connect()` in `extension.js` driven by `core.connectReduce` (on each entry into Running = activation and after a restart, on a profile or trace change, **Ermine: Connect Database**, Retry, and `ermine/preview/disconnected`); A7's verbose refusal inside the reducer so no path bypasses it; the password prompted with `showInputBox({password, ignoreFocusOut})` and held in ONE `Map` keyed by `sha256(id, url, user)`, read once (the argument of `core.connectRequest`), written once, cleared on Disconnect, on class `auth` or `kept:false`, on teardown and when no profile has the key; the automatic reconnect with the held password re-sends the last render ONCE, and after a restart the `Running` edge's own re-render is DEFERRED to the connect's answer so WP-22's consultation decides it under `restart`; a connect neither consults nor clears the wedge mark; the 503 `not-connected` dressed with the command (no new panel button, U4), a failed connect shown as a 503 banner with Q-S4's `connect-*` reason; a second status bar item (`id (dialect) @ host` / `id: <class>`, hidden with no profile); one `db:` channel line per event. Tests: `editor/vscode/test/connect-core.test.js` (validation table, the state-machine model over the glue's own builders, a 400-sequence leak property, glue pins over `extension.js` incl. "the password reaches no sink", and the four reverse mutants killed by name). The server as built answers class `unreachable` where §4 says `connect`; both are read. NOT done here: the §8.4 credential gate (needs a real editor + server), the fake-driver classifier test (server half).** **AMENDED TWICE ON 2026-09-20, BOTH TIMES BY THE USER. SECOND: THE PROMPTED PASSWORD'S LIFETIME IS DECIDED** -- their words, *"prompted pass lives for the window."* -- so §8's paragraph is no longer a proposal: what this ticket builds is a password held in the EXTENSION HOST'S MEMORY for the editor window's lifetime, never on disk, never in a webview, forgotten on reload, on Disconnect and after a failed login, and the stricter prompt-every-time variant is NOT chosen. FIRST: **NO SECRET STORE. `SecretStorage`, the `sha256(url + "\0" + user)` key and the "Forget Database Password" command are DROPPED from this row; the password is PROMPTED for (§8's amendment carries the user's words and what stays regardless -- A1, A2, A4, A5/A6, A7, A9, A10 and the §8.4 gate).** The row is otherwise unchanged and is kept as written, **with the two DROPPED items struck through below so that this list cannot be read as a done-when**: profiles (user scope only) + `ermine/preview/connect` + the four-way classifier with `kept` + `Throwable` catch and scrub + URL credential refusal + ~~`SecretStorage` keyed by `sha256(url + "\0" + user)`~~ **(DROPPED -- the extension PROMPTS)** + trace-`verbose` refusal in the one `connect()` + ~~**Forget Database Password**~~ **(DROPPED -- there is nothing to forget)**; no `untrustedWorkspaces` declaration; the Settings-Sync answer written into §8.2 | the credential gate (§8.4) passes in full; the fake-driver classifier test passes; a workspace-scope profile is ignored and named once | pr + instrument / ~2 days |
| WP-14 | **AMENDED TWICE ON 2026-09-20, BOTH TIMES BY THE USER: NO SECRET STORE, AND THE PROMPTED PASSWORD'S LIFETIME IS NOW DECIDED** (*"prompted pass lives for the window."*), which is what this row's EXTENSION-DRIVEN RECONNECT needed: **the reconnect is AUTOMATIC because the extension still holds the password in the extension host's memory**; it prompts again only after a window reload, a Disconnect or a failed login. The question this row used to carry is closed and the text that follows is kept as the record. NO SECRET STORE (§8's amendment). PREVIOUSLY PROPOSED AND NOT YET CONFIRMED, now DECIDED: the prompt is held in the extension host's memory for the window's lifetime so a reconnect after a server restart stays automatic; the stricter variant makes every reconnect a click. Unchanged otherwise: held connection lifecycle: the §7.2 switch sequence, Disconnect command, `disconnected` notification, extension-driven reconnect, re-render after every connect, recycling defaults (Q2), reconnect on `Running`, status-bar item `id (dialect) @ host`, the file-backed SQLite profile documented. **THE CLOSE THIS TICKET PUTS IN `discardSession` MUST NOT BLOCK** (review S3, 2026-09-20): Q10's recovery calls `discardSession` from `runJob`'s `finally`, AFTER `disarm()`, so it runs with no watchdog over it and with the stuck state ALREADY CLEARED -- a `Connection.close()` that hangs on a dead socket would wedge the preview thread in a state nothing would fire on and nothing would refuse. It is free today (`DelegatingRun.clear()` closes nothing); this ticket owns giving that close a timeout, or moving it off the preview thread. **THE TWO WP-6 CLAUSES THAT FOLLOW ARE WITHDRAWN (WP-24, 2026-09-20): the cancel is removed, so this ticket no longer owns either of them.** The close-that-hangs half above stands on its own (it is the rare recovery path again, not a common one), and the converse latch leak was a CONSEQUENCE OF THE CANCEL -- §2.5's own note now says so and this pointer is withdrawn with it. Kept as the record: **WP-6 STAGE 1 WIDENED THIS AND MADE IT COMMON (2026-09-20)**: the cancel path discards the session UNCONDITIONALLY, from the same `finally` and with the same `disarm()` already done, so with `ermine.preview.cancelOnTimeout` on, EVERY watchdog incident whose cancel takes ends in an unwatched `discardSession` -- the ordinary path, not the rare recovery one. A close that hangs there wedges the preview thread on the common case. **AND THIS TICKET OWNS THE CONVERSE LEAK (S3 of the WP-6 stage 1 review, DERIVED BY READING AND UNVERIFIED)**: a cancel unwinds without `writeback`, so the thunks it passed keep their `CountDownLatch` uncounted, and `discardSession` releases none of them -- a SCAN'S CHUNK PRODUCER (or any `SessionTask` pool thread) that later reaches one parks on `latch.await` for ever. Daemon threads, so the JVM still exits; what leaks is one thread and its retained queue per cancelled render that had a concurrent scan. It is unreachable while the stage A backend opens one connection per run and nothing scans concurrently, and this ticket is where a real database makes it reachable | a 1-hour session against MSSQL leaves no `##` tables after Disconnect (count in `tempdb.sys.tables`, MEASURED); a profile switch mid-render discards the old answer; killing the server and letting the client restart it ends in a rendered document; no password *field* in `lsp/Preview.scala` (code review), the driver's `Connection` acknowledged to hold it until close | instrument + manual / ~1.5 days |
| WP-15 | SQLite emitter gaps: `EmitOver_UsingOver` mixin, bracket names, parenthesised joins | `TestSqlEmitters` pins each string; a windowed report previews on SQLite with rows | pr / ~half a day |
| WP-16 | engine gaps: `UnsupportedOnDialect` at the §9.2 sites, 500 banner, deploy-dialect badge | no emitter output contains `TODO`; `tryCast` on SQLite shows the banner naming `tryCast` and `sqlite` | pr / ~1 day |
| WP-17 | **ADDED 2026-09-24 FROM THE WP-33 REVIEW (recorded by WP-34, NOT BUILT): the repository has NO `.gitattributes`, so Git for Windows' default CRLF conversion (`core.autocrlf=true`) would rewrite `client/src/generated/widgets.ts` and the 36 LF-only `.e` files on clone, and `npm run check-generated` would then fail on a fresh Windows checkout (the generator writes LF). A `* text=auto eol=lf` rule, or a per-path one for the generated file and `*.e`, is this row's, not built here.** **DEFERRED BY THE USER 2026-09-24, NOT DROPPED.** Their words: *"we use windows at work"* / *"do the node port now, WP-17 later"*. WP-33 (the port) removed the client's two bash dependencies (`client/scripts/generate.sh`, `check-generated.sh`, now one-line shims onto node scripts that `package.json` no longer calls); `generate.js` launches java DIRECTLY, not via `bin/ermine-schema`, so the client's generate/check path has no bash at all. **Remaining scope of this row: `bin/ermine-lsp`, `bin/ermine-schema` (still bash, no longer on the client's path), `bin/ermine-serve` and the REPL launcher `bin/ermine`** (and `client/scripts/check-corpus.sh`, bash, which WP-33 did not port: it writes the corpus with sbt). **The first Windows run is a FIRST PLAYTEST: nothing in this codebase has ever run on Windows.** Add to its checklist WP-33's unverified win32 half: `npm run generate` and `npm run check-generated` on a work machine (java via `JAVA_HOME` or `PATH` as `java.exe`; the first-run classpath build through `sbt.bat`/`sbt.cmd` under cmd.exe; `check-generated` reporting "up to date", i.e. the Windows output byte-identical, LF-only). closed-environment packaging: vendored `client/node_modules` or internal registry, driver jar offline, `bin/ermine-lsp.cmd` (and a PowerShell twin) with `resolveServer` choosing it on Windows. **THE WINDOWS WRAPPERS MUST CARRY THE JVM POLICY, not just the classpath** (Q12, 2026-09-20): `-Xmx${ERMINE_LSP_XMX:-2g}` with the 64m floor, `-XX:+ExitOnOutOfMemoryError`, AND `-XX:+DisplayVMOutputToStderr` behind the same cached, java-keyed probe `bin/ermine-lsp` uses -- §10 says the deployment machines are Windows, so that is exactly where Q12's unframed OOM line on the protocol channel matters, and today neither the flag nor the cap reaches them. **WHAT WP-9 MEASURED FOR THIS ROW (2026-09-21, folded in from `tracker/WP-9-AS-BUILT.md`; the probes marked BY THE REVIEW were run by WP-9's independent reviewer, not by its implementer).** The webpack bundle adds **+95 packages** to `client/` (lockfile 69 -> 164 entries; `npm ci` "added 163 packages") and takes `client/node_modules` from **49 MB to 81 MB** (MEASURED). The vendored closure is exactly `webpack 5.111.1` + `webpack-cli 7.2.3`, exact-pinned, because WP-9 is tsc-first and uses no loaders. BY THE REVIEW: **no install scripts in any of the 163 packages** (no postinstall, no node-gyp), **no native or prebuilt binaries** (zero `os`/`cpu`-gated and zero `optional` entries), every lockfile entry carries `resolved` + integrity so `npm ci --offline` against a primed cache is viable, **no network at build or test time**, and no version churn among the 68 pre-existing packages. Licences: 141 MIT, 7 ISC, 5 Apache-2.0, 5 BSD-3-Clause, 3 BSD-2-Clause, 1 MIT-0, and **one that is none of those -- `caniuse-lite`, CC-BY-4.0, a DATA licence, not an OSI software licence**; nothing copyleft. Worth naming to whoever signs off the vendoring, no more than that. Neither bundle nor either source map contains an absolute checkout path, so a COMMITTED bundle would be checkout-independent. **TWO THINGS STAY OPEN AND ARE THIS ROW'S**: the vendoring choice itself (vendored `node_modules` vs internal registry), and **whether `client/dist/browser/` is committed at all** -- `client/dist/` is gitignored at `.gitignore:10` and WP-9 did not touch it. | a fresh clone on a work machine runs WP-7 and WP-10 with no network and no WSL; the credential gate passes on Windows | manual / ~1 day |
| WP-18 | docs: `docs/JSON-GUIDE.md` §9/§10/§12 (the guide's `Runner.scala:259-280` reference at `:1571` has drifted to `:287-288`), `client/README.md` "Adding a widget" (`ermine/schema` from the render session replaces eleven boots), `editor/vscode/README.md` | the three documents describe the loop as built; MEASURED figures replace the mined ones here | none / ~half a day |
| WP-19 | **optional, out of the loop**: dual-emit T-SQL diff in the panel via `dumpRel` / `dumpClosed` | only if relation authoring in the panel is asked for | -- |
| WP-20 | **NOT BUILT, found by WP-6 stage 1's design review**: a LENGTH CAP on `json/Encode.scala`'s `spine`. It walks a `::` spine with `while (true) { Runtime.swhnf(cur) ... }` and `buf += args(0)`, and a CYCLIC list (`repeat a = t where t = a :: t`) makes it run until the heap is gone. **CORRECTED 2026-09-20 (WP-24 and its design review): WP-6 IS REMOVED, so nothing stops it ANYWHERE, the preview included** -- the sentence that used to say "WP-6 makes the PREVIEW able to stop it" is withdrawn. And a premise correction worth keeping beside the ticket: **`Encode.spine` ALLOCATES** -- `buf += args(0)` adds one `ListBuffer` cell per step (READ, `Encode.scala:233-247`) -- so WP-20 is an ALLOCATING wedge, contained by the heap cap in the only sense that cap contains anything (the process exits, MEASURED §2.5), and it is NOT an example of a wedge that never dies. The realistic never-dying wedge is a BLOCKED preview thread (a parked `future.get`, a thunk's `latch.await`, a JDBC socket read, WP-14's hanging `Connection.close()`), which WP-13/WP-14 make reachable and which nothing in the tree can produce today. Nothing stops the spine in `bin/ermine-serve`, in `bin/ermine`, or anywhere else `Encode` is used, and `swhnf` is not where the fix belongs -- a spine longer than any document could carry is an ERROR at its own index, in the same shape `spine` already uses for a bottom or a foreign tail. Deliberately NOT built with WP-6: a cap is a wire-visible behaviour change for every encoder caller and wants its own decision about the number | a report whose document holds an infinite list answers a 500 naming the path and the cap instead of exhausting the heap; `TestJson` and `TestRunner` unchanged | pr / ~2 h |
| WP-21 | **NOT BUILT, found by WP-6 stage 1's design review**: `Pretty.ppRuntime`'s DEPTH CAP IS LOST on the general-constructor arm. `ppRuntime(e, d)` refuses to go past `d > 10` (`Pretty.scala:368`) and passes `d + 1` down its own arms, but `case Data(n, arr) => ppAppNR(n, arr.toList)` (`:383`) hands the children to `ppAppNR`, whose every arm calls `ppRuntime(x)` with the DEFAULT `d = 0` (`:325-332`). So the counter resets at each constructor and `Runtime.toString` on a CYCLIC user data value never stops -- and `Runtime.toString` is what every "Panic: unexpected runtime value" message, every `Bottom` description and the REPL's own printing go through. The list arm is safe (`asList` answers a `(zs, truncated)` pair); it is the general one that is not. Deliberately NOT built with WP-6: it is a pre-existing defect on a different path, and threading `d` through `ppAppNR` touches every printer arm | a cyclic `data` value prints `...` at the cap instead of hanging; the REPL and `TestErmine`'s printing are unchanged | pr / ~2 h |
| WP-22 | **AMENDED 2026-09-21 BY WP-8 S2's REVIEW (M6), AND IT IS THE ONE CHANGE TO THIS TICKET'S SHAPE SINCE IT WAS BUILT: THE ONE CONSULTATION IS NOW REACHED FROM TWO PLACES.** `shouldAutoRender` is still the ONLY function that decides whether an automatic render may go, and it is still the only place the mark is read for that purpose -- but `renderNow` now asks it too, immediately after WP-8 has fed the guard the params it is about to send. THE REASON IS THE USER'S OWN SENTENCE: *"We'd want some sort of confirmation before rendering a report which wedged and was killed the first time around AND IT DIDN'T CHANGE."* A params file SAVE is a render trigger that carries no evidence of change, and at that one moment the extension KNOWS whether anything changed, because it has just computed the fingerprint; the first cut of S2 re-issued the wedge for a re-format and this document recorded it as settled. `shouldAutoRender`'s trigger vocabulary grew instead of a second decision being minted. **AMENDED AGAIN THE SAME DAY BY THE DELTA RE-REVIEW, WHICH FALSIFIED THE SENTENCE THAT STOOD HERE** ("none of them can reach the consultation with a mark standing"): it was false TWICE, and both halves are now fixed rather than documented away. (i) **`roots` reached it**, because its guard event clears only when the resolved list MOVED while the glue schedules either way -- so the REFUSED set is now `restart`, `params-file`, `module-learned` **and `roots`**, under a membership rule written into the code: *a trigger may stay OUT only if, whenever the glue schedules it, the guard event it fed has CLEARED the mark*. (ii) **The other three reached it through the window**: `invalidated` clears and schedules, the report wedges AGAIN inside the 150 ms and the params read, and the render fires with a fresh mark standing. So a non-explicit render is ALSO held when the mark is NEWER than the trigger that scheduled it (`core.markMintedAfter`, fed by a `scheduledAt` the coalescer records). **MEASURED over 579,194 generated sequences driving the real reducers in the glue's order: 5,097 such renders before, 0 after.** An undeclared trigger is now refused and named too (`triggerProblem`), where it used to be permitted. Everything below is unchanged. **LETTERS (a) AND (b) ARE BUILT, 2026-09-20, EXTENSION ONLY -- JavaScript and documentation, NO SCALA, NO SERVER CHANGE, NO WIRE CHANGE; extension 0.1.5 -> 0.1.6. LETTER (c) IS NOW CONFIRMED BY THE USER (2026-09-20, §13's own row) AND IS STILL NOT BUILT IN THIS CHANGE: it is the NEXT change, the same ticket's STAGE 2.** **STAGE 2 IS NOW BUILT TOO -- 2026-09-21, extension 0.1.6 -> 0.1.7, again JavaScript AND DOCS ONLY. EVERY SENTENCE BELOW IS KEPT AS IT WAS WRITTEN ON 2026-09-20 and is the record of that day; what stage 2 actually built, with `file:line`, is in the SECOND `AS BUILT` BLOCK at the end of this cell. THE SETTING IS `ermine.preview.restartAfterStuckSeconds`, NOT `killAfterStuckSeconds`, AND ITS DEFAULT IS 0 = NEVER: the user confirmed the MECHANISM and has NOT been asked about the DEFAULT.** The wedge guard, one ticket -- what replaces WP-6 under Q13's 2026-09-20 re-decision. **THE TEXT BELOW IS THE TICKET AS WRITTEN; WHAT WAS ACTUALLY BUILT IS IN THE `AS BUILT` BLOCK AT THE END OF THIS CELL, WITH `file:line`.** **(a) THE MARK. DECIDED BY THE USER**: the memory lives in the EXTENSION (*"I think "remembering" is an extension concern"*), and a report that WEDGED AND HAS NOT CHANGED is not re-rendered without a confirmation (*"We'd want some sort of confirmation before rendering a report which wedged and was killed the first time around and it didn't change"*). **THE PRINCIPLE ABOVE IS THE USER'S; THE SHAPE THAT FOLLOWS IS THE DESIGN REVIEW'S RECOMMENDATION**, the same line letter (b) draws -- the record's fields, its key encoding and the SET/CLEAR trigger lists were not put to the user and are not decided. ONE mark for the CURRENT pick only -- never a map -- `{key, reason, at, rootsFingerprint, paramsFingerprint}` keyed by `uri + "\u241f" + binding`, with roots and params in the VALUE so that changing them CLEARS rather than mints a second mark. SET by a `stuck: true` answer, by `ermine/preview/stuck {stuck: true}`, and by a `Stopped` transition while a render of that pick was in flight. CLEARED by `{stuck: false}` (Q10's recovery -- the load-bearing clear, without which a 300 s scan under a 60 s watchdog is held for ever), by an `invalidated` naming the pick's module, by any `.e` save, by a pick / roots / params change, and by any explicit user render, which IS the confirmation. The "it didn't change" test is a PROXY, not a proof: the wedge is usually in a DEPENDENCY, so a content hash of the picked file would be wrong, and the two signals used err towards asking less. **(b) THE CONSULTATION, AT EXACTLY ONE SITE** -- the shape below is the DESIGN REVIEW'S RECOMMENDATION; the PRINCIPLE (ask before re-rendering a report that wedged and has not changed) is THE USER'S: the `rerender` effect of the `Stopped -> Running` transition (`preview-core.js:355` -> `extension.js:471`), where the automatic render is replaced by ONE NON-MODAL `showWarningMessage` offering **Render anyway** / **Not now** (Escape = "Not now", never consent), plus a fourth `statusBarState` branch `held` with the precedence **offline > stuck > held > rendering > idle**. The other automatic triggers are each self-evidently a change and are NOT suppressed: `invalidated`, the Q11 watcher, a roots change, and `{stuck: false}`. New PURE `markKey` / `guardReduce` / `shouldAutoRender` / `heldMessage` in `preview-core.js`, each with `node --test` cases; **`stuckReduce` IS NOT CHANGED** (its four rules, DD-2 and its pinned properties stay as they are). **(c) CONFIRMED BY THE USER, 2026-09-20 (~23:50), IN FOUR WORDS: *"the extension may restart."* IT IS STAGE 2 OF THIS TICKET AND IS NOT BUILT HERE.** The design review's conditions below are kept exactly as they were and are now the ORCHESTRATOR'S BUILD PLAN rather than a recommendation: (i) **the guard is its hard prerequisite, and the guard is now built** -- a client-initiated `stop()` is an EXPECTED close, so (INFERRED, UNVERIFIED) it is not counted by the library's "crashed 5 times in the last 3 minutes" limiter, which makes (a)+(b) the SOLE bound once the extension starts killing the server itself; (ii) **a grace period before the kill, which `{stuck:false}` DISARMS** -- without that disarm a 300 s scan under a 60 s watchdog is killed for being slow (§13's Q10, the load-bearing clear); (iii) **the setting's DEFAULT is not decided**: the design review advised `ermine.preview.killAfterStuckSeconds` default **0 = OFF** until the manual checklist has been run once by a human, **the user has NOT been asked about the default specifically** (they confirmed the mechanism, not its default), and **the orchestrator will build it default OFF and ask**. What the review wrote, kept verbatim as the record: that on `{stuck: true}` the EXTENSION ITSELF restarts the server after a grace (the review's "B-EXT": arm a timer, disarm it on `{stuck: false}`, on expiry call the extension's existing `restart(context)`, `extension.js:259`), through a new setting `ermine.preview.killAfterStuckSeconds` **defaulting to 0 = OFF until the WP-7 manual checklist has been run once**; that THE KILL MUST NOT SHIP WITHOUT (a) AND (b), because a client-initiated `stop()` is an EXPECTED close and so (INFERRED from the handler's documented purpose, **UNVERIFIED** -- the library's source was not read) is NOT counted by `vscode-languageclient`'s "crashed 5 times in the last 3 minutes" limiter, which makes the guard the SOLE bound; and that the mark be MIRRORED into `context.workspaceState` under `ermine.preview.wedge` beside `PICK_KEY`, restored in `restorePick` and discarded when its key does not match, with the module global still the authority for the live decision because `Memento.update` is async. **THE KEY FINDING THIS TICKET EXISTS FOR (READ from the code, 2026-09-20): THE LOOP IS REACHABLE TODAY** -- see Q17. **EVERY CLAIM ABOUT VS CODE'S OWN BEHAVIOUR IS UNOBSERVED BY ANYONE**: nobody on this branch has run the extension, and §2.11 and §2.13-2.14 of `tracker/WP-7-MANUAL-CHECKLIST.md` -- the steps that would first SHOW the loop -- have never been run. NOT BUILT AND NOT TO BE BUILT HERE: any server change, content hashing or mtime tracking, a new command, a modal, `globalState` or a file on disk, a map of marks, any backoff beyond the one grace. **AS BUILT (2026-09-20), file by file. `editor/vscode/src/preview-core.js` (pure, no `require("vscode")`, +~300 lines): `markKey` (`uri + "\u241f" + binding`), `canonicalJson`/`fingerprint`, `rootsFingerprint` (ORDER-SENSITIVE: the roots are a loader chain), `paramsFingerprint` (WP-8's hook -- key-order-INsensitive canonical JSON; with no params today every mark carries the fingerprint of `{}`), `isMark`/`markMatches`, `guardReduce(mark, event) -> {mark, effects:{set, cleared, reason, why}}` over the eleven event types (`answer`, `notification`, `clientState`, `invalidated`, `save`, `pick`, `roots`, `params`, `render`, `restore`, and an unknown type that changes nothing), `stuckEventApplies`, `shouldAutoRender(mark, pick, trigger)`, `heldMessage`, `TRIGGER_RESTART`, and a `held` branch in `statusBarState` with the precedence **offline > stuck > held > rendering > idle** re-stated in its comment and pinned by a test. **`stuckReduce` IS BYTE-FOR-BYTE UNCHANGED** -- its rules, its `seq` handling and its pinned properties are untouched, and nothing in it was needed. `editor/vscode/src/extension.js` (glue only): `WEDGE_KEY = "ermine.preview.wedge"` beside `PICK_KEY`; the module globals `wedgeMark` (the authority) and `heldPromptOpen`; `applyGuard` (the mark's only writer: stores, logs once, mirrors into `workspaceState` without waiting on the `Thenable`); `rememberWedge`; `holdRender` (the one non-modal `showWarningMessage(text, "Render anyway", "Not now")`, where ONLY the exact string `Render anyway` consents and a dismissal -- `undefined` -- is `Not now`); `applyStuck` gains a `trigger` parameter and IS THE ONE CONSULTATION SITE (`shouldAutoRender(wedgeMark, picked, trigger)` guarding the `fx.rerender` branch, which is where the automatic render used to be issued unconditionally); the guard events are fed from the `invalidated` handler, the `ermine/preview/stuck` handler, `onDidChangeState`'s `Stopped` edge (carrying `renderInFlight`), `renderNow`'s answer, `pickReport`, `renderCommand`, the roots arm of the configuration listener, a NEW `onDidSaveTextDocument` registration in `activate`, and `restorePick`. `editor/vscode/test/preview-core.test.js`: 19 new tests (39 -> 58). `editor/vscode/package.json` 0.1.6, `editor/vscode/README.md` (a 0.1.6 changelog entry, the status-bar paragraph, the test description, and the two `.vsix` file names in the install snippet, which still said 0.1.3). **THE ONE THING THE TWO REDUCERS SHARE, AND WHY**: a `{stuck:false}` that `stuckReduce` IGNORES under §4's rule (1) (its `seq` is at or below the high-water mark) must not clear the mark either, or the banner would say stuck while the guard said nothing was wrong, and the next restart would re-render the wedge. So the glue computes `stuckEventApplies(stuckState, event)` BEFORE `stuckReduce` sees the event and passes the answer to `guardReduce` as `applies`; a property asserts the predicate agrees with `stuckReduce` event for event over 4000 generated events. **ORDERINGS THAT WERE BUILT FOR DELIBERATELY**: the wedged ANSWER and `{stuck:true}` arrive in either order (MEASURED over the wire: the answer came first in every run) and SET is idempotent per key, so the FIRST mark stands with its `at` and its reason; a `Stopped` with a render in flight marks `died-mid-render` even when the watchdog never fired (MEASURED, §2.5: `WpBlow` at `-Xmx256m` exited 3 at 8.6 s with no fire); a second restart while held asks again (one question per restart) but never stacks a second question while the first is on screen, and never loses the mark. **REVIEWED 2026-09-20 (independent, DESIGN GREEN / IMPLEMENTATION GREEN) AND THE THREE MUST-FIXES ARE APPLIED.** **M1, AND THE CONSEQUENCE THE FIRST WRITE-UP LEFT OUT**: `died-mid-render` used to rest on `renderInFlight` still being true when the `Stopped` handler ran, while `renderNow`'s continuation cleared it as soon as the in-flight request rejected -- and WHICH RUNS FIRST IS DECIDED INSIDE `vscode-languageclient`, unobservable here. **Losing that race lost the mark, and the restart then re-rendered a wedge that had already killed one JVM** -- exactly the small-`-Xmx` case (`WpBlow` at 256m, exit 3 at 8.6 s, no watchdog fire, MEASURED §2.5), which is the one incident the watchdog mark does NOT cover. It is now ORDER-INDEPENDENT in both directions: a new latch `inFlightRender = {generation, pick}` is released only by a SETTLED result, so the `Stopped` handler sees the render whichever way the race falls, and `renderNow`'s catch marks the wedge itself when the rejection is not one a published specification lets us read as the peer's own answer. SET is idempotent per key, so both firing costs nothing. The classification is PURE (`rejectionMeansServerGone`, `preview-core.js`), with its evidence in its comment: DOCUMENTED settled codes are JSON-RPC 2.0's -32700/-32600/-32601/-32602 and the LSP's -32002/-32001/-32800/-32801/-32802/-32803; **everything else, including every shape we cannot name, means the server went away and marks** -- a spurious question costs one click, a missed one reopens the loop. **-32603 IS NOT SETTLED, AND THE DELTA REVIEW (2026-09-20) IS WHY -- IT IS THIS SERVER'S OWN CRASH ANSWER** (READ in the Scala, re-verified here before the edit): `Rpc.InternalError` is -32603 (`Rpc.scala:252`) and `Preview.scala:207-208` pre-allocates `crashAnswer = Left((InternalError, "the preview failed"))` for one situation only -- the PREVIEW THREAD died -- which `rescueInFlight` (`:1263`) gives to the render that was in flight, `drainOnDeath` (`:1277`) to everything queued behind it, and `:523`/`:614` to every later render ("the preview thread is not running"). A FATAL error kills that thread and leaves the JVM alive (`isFatal`, `:1086`, is any `Error`, so a `StackOverflowError` out of a runaway recursive evaluation qualifies), so **there is no connection drop and no `Stopped` edge at all**: reading -32603 as "the peer answered" left no mark, and the Restart Language Server button the user then reaches for re-rendered the pick straight back into the same overflow. **That is Q17's loop by another door, and it was live in the first build.** A render whose handler merely threw now costs one prompt, which is the right side to be wrong on. **-32800 STAYS SETTLED, and the airtight reason is the shutdown contract** (`Preview.scala:764-766`, found by the same review): every QUEUED job that owes an answer is answered -32800 while an IN-FLIGHT one "finishes and is answered normally", so a dying render never comes back as -32800; §2.5's three producers are all the server's own queue and a crashed process sends none of them. The GUESS is named as one: that the library rejects pending requests with something outside that list (community reports say a private -32099..-32096 band), UNVERIFIED, its source not read. **M2**: the held question has no deadline, and its answer used to be applied to whatever was current when the user finally clicked -- the reviewer's S11 spent consent given for `Sales.report` on a different report the user had picked meanwhile. The pick the question is ABOUT is now captured when it is shown and checked by the pure `promptAnswerApplies`. **M3**: a fingerprint is now a SHA-256 DIGEST (node's own `crypto`, so `preview-core.js` stays editor-free), because the mark is persisted: `paramsFingerprint` is WP-8's hook and WP-8 will hand it the params it actually sends -- the reviewer's probe put a connection-string password straight into the mark -- and `rootsFingerprint` held absolute paths that `PICK_KEY` does not persist at all. A test asserts no part of the input appears in the fingerprint. The unfingerprintable case HOLDS (one fixed sentinel, so two of them compare equal and the mark stands); the comment that claimed it cleared was wrong and is corrected, as is the claim about `Date`s, which all canonicalise as `{}`. **ALSO FROM THE REVIEW**: `stuckEventApplies` is now `!(typeof seq === "number" && seq <= highWater)`, which is EXACTLY `stuckReduce`'s test at `seq: NaN` too (`<=` and `>` are not complements there; latent, since JSON cannot carry NaN, but 'exactly' was claimed and is now true), and the agreement generator draws NaN, Infinity, non-numbers, absent and EQUAL seqs and post-reset answers; the Q11 watcher now clears the mark (its own file changed: the same evidence a save is); a stuck answer marks the pick captured AT SEND and a stuck notification the in-flight render's pick, not whatever is current a minute later (`markPickFor`); a restore that DISCARDS now removes the stale key from `workspaceState` and a restore that KEEPS logs as a restore rather than as a fresh wedge; `heldPromptOpen` is reset on a pick change and on teardown, so a notification left unanswered cannot silence every later question; and the `Memento.update` Thenable has a rejection arm. **FIVE BEHAVIOURS RECORDED RATHER THAN CHANGED** (the first review's N6 and N7, and three the delta review named). **Superseded renders**: with a render of A in flight the user can pick B and the server can then die, and the mark goes to whichever rejection lands last -- both outcomes are safe (A is the report that was running, B is the one a restart would re-render) and neither can re-render a wedge unasked. **Two benign GONE shapes cost one prompt each**: a request issued into a client that is not running yet, and a coalesced render firing into the window while the server is down. The delta review's optional filter -- ignore the rejection in `renderNow`'s catch when `stuckState.running === false` -- is **NOT BUILT**, deliberately: it trades a prompt for a branch that could hide a real death. **A future `CancellationToken`**: a render cancelled through one would reject with no JSON-RPC code and so would classify as a death and mark; whoever adds cancellation adds its shape to `SETTLED_BY_PEER_CODES`. And the two from the first review: the render command clears the mark BEFORE `renderNow`, which no-ops when the client is mid-restart, so that consent carries forward to the next restart's unguarded auto-render (defensible -- the user did ask); and `{stuck:false}`-clears-and-re-renders can cycle at the watchdog period for a report that is merely SLOW, each turn visible as a banner and a toast, bounded by attention rather than by code. **WHAT IS GLUE AND THEREFORE UNOBSERVED BY ANYONE**: that a crash-restart produces the `Stopped` edge at all, and in which order relative to the rejection (M1 removes the DEPENDENCE on the answer, not the ignorance); what a dismissed or timed-out `showWarningMessage` resolves to; the status bar item's warning background; the `onDidSaveTextDocument` registration; and the `workspaceState` mirror and its restore. `tracker/WP-7-MANUAL-CHECKLIST.md` §2.15-2.27 is the list that would observe them, and it has never been run. **NOT BUILT, AS THE TICKET SAYS** (true on 2026-09-20; the first clause was SUPERSEDED BY STAGE 2 the next day and the rest still holds): letter (c)'s KILL (no `ermine.preview.killAfterStuckSeconds`, no grace timer, no extension-owned `restart(context)`), no server change of any kind, no content hashing or mtime tracking, no new command, no modal, no `globalState`, no file on disk, no map of marks, no backoff. **ONE PART OF LETTER (c) WAS BUILT, AND SAYING SO IS THE POINT OF THIS SENTENCE**: the `workspaceState` MIRROR (`ermine.preview.wedge` beside `PICK_KEY`, restored in `restorePick`, discarded when its key -- or its roots fingerprint -- does not match the restored pick, with the module global still the authority because `Memento.update` is async). The letter grouped it with the kill; the build moved it into (a), where it costs nothing and buys an honest status bar after a window reload. THE KILL IS UNTOUCHED AND UNCONFIRMED.** **AS BUILT, STAGE 2 (2026-09-21): THE RESTART. `editor/vscode` ONLY -- JavaScript, JSON and documentation; NO Scala, NO server change, NO wire change, and `stuckReduce` and `guardReduce`'s existing rows are again untouched.** **THE SETTING**: `ermine.preview.restartAfterStuckSeconds` (`package.json`, `contributes.configuration`, window-scoped, **`"type": "integer"`** -- review N3, so VS Code's own settings UI refuses `2.5` instead of the extension silently turning the feature off -- 0..3600, **default 0 = never**; review N7 moved this project's process note OUT of that end-user description and into this document, where the reason the default is 0 belongs), validated by the PURE `restartGraceSetting` (`preview-core.js:954`) in `previewSettings`'s own style -- nonsense is NAMED and falls back to OFF (not to some grace nobody asked for), a value above `RESTART_GRACE_MAX` = 3600 is CLAMPED and named, and the problem is logged and shown ONCE per distinct text (`extension.js:106` `restartGraceValue`). **IT IS NOT ON THE WIRE**: it is absent from `settingValues`, from `initializationOptions` and from `didChangeConfigurationParams` on purpose -- the server has no such setting and learns nothing about this feature. **THE PURE REDUCER**: `restartReduce(state, event) -> {state, effects:{arm, disarm, fire, seconds, serial, why}}` (`preview-core.js:1054`) with `initialRestartState` (`:990`), `restartArmedSeconds` (`:1201`), `restartNotice` (`:1212`) and `stuckNotificationText` (`:1221`). **IT HOLDS NO CLOCK**: the glue owns the one `setTimeout` and hands the expiry back as an EVENT carrying the SERIAL of the arm it belongs to (`extension.js:794` `armRestartTimer`), and every arm mints a new serial, so a timer armed for an earlier incident CANNOT fire and does not even disarm the live one -- the watchdog's own arm-epoch idea. **ARM** on the RISING edge of the stuck state (an accepted stuck ANSWER or an accepted `{stuck:true}` notification, whichever comes first -- the answer did in every measured run -- and never both: one grace per incident), while Running and with the setting non-zero; **AND, SINCE THE REVIEW (D1), WHEN THE SETTING IS TURNED ON WHILE THE PREVIEW IS ALREADY STUCK AND THE CLIENT IS RUNNING.** The first build refused that and the reviewer was right that it stranded the likeliest user there is: the person who reaches for this setting BECAUSE the preview is wedged, with no second rising edge coming (§4's rule (5) is withdrawn). The old justification -- "it keeps 'armed implies a rising edge' true, which is what makes the serial mean something" -- did not hold: the reducer already re-armed on a setting change while armed, and every arm mints a fresh serial unconditionally. **THE ARM'S DELAY IS `max(the setting, what is left of the floor)` (review D2)**, so the number on the notification is the one the restart will actually happen at. **DISARM** on an accepted `{stuck:false}` (Q10's recovery, THE LOAD-BEARING ONE -- without it a slow-but-finite render is killed for being slow), on every clientState edge (Stopped, Starting, and Running, which resets the stuck state anyway), on a setting change to 0, and on deactivate. **A PICK CHANGE DOES NOT DISARM, AND THAT IS A DECISION WITH AN ARGUMENT**: the wedge is the SERVER's state, not the pick's -- once stuck, the server refuses EVERY later render the same way (§2.5) and `ermine/preview/stuck` is per PROCESS -- so picking another report changes only which report is refused; and because §4's rule (5) was WITHDRAWN there is ONE rising edge per incident, so a disarm there would have no way back and would leave the server wedged for the rest of the session exactly when the user is working around it. What IS pick-scoped is the MARK, and it stays so. **FIRE** only for the live serial, only while still stuck and still Running, only with the setting non-zero, only with a clock on the event, and only outside **`RESTART_FLOOR_MS` = 30 s since the last restart** -- a last-resort rate limit that survives a bug in the guard, in the glue or in the library, argued against three numbers: the MEASURED ~14 s boot (so a storm cannot exceed ~2 restarts a minute), the 60 s default watchdog (so the floor cannot bite a default configuration) and the fact that the only configurations it can bite are deliberately aggressive ones. A clock that moved BACKWARDS refuses too. **THE FLOOR NEVER STRANDS AN INCIDENT (review D2, and the first build did strand one)**: it is applied at ARM time by stretching the delay, and at EXPIRY -- reachable only when the arm carried no clock or the clock moved -- by RE-ARMING for what is left, with a new serial. It never disarms. The reviewer walked the case that made this a bug: `timeoutSeconds` 5 with a 5 s grace, a fire, "Render anyway", a second wedge, an expiry 11 s after the first fire -- refused AND disarmed, `stuck` for the rest of the session, with a notification still promising a restart in 5 s. **AND THE FIRE DOES NOT CONSUME THE FLOOR (review D3)**: `lastFireAt` is moved by the glue's `fired` answer and by nothing else, so a fire `fireRestart` REFUSES (nothing to attribute the wedge to, no extension context, the mark did not take, a restart already under way) leaves the floor's memory alone; the refusal is remembered as `lastRefusal`, shown in the stuck tooltip and in one warning notification, because a refusal that reaches only the output channel leaves a wedged server and a user who is told nothing. **THE GLUE** (`extension.js`): `restartState`/`restartTimer` (`:415`), `applyRestart` (`:765`), `clearRestartTimer` (`:781`), `armRestartTimer` (`:794`), `fireRestart` (`:814`); fed from the `ermine/preview/stuck` handler (`:575`), `onDidChangeState` (`:613`), `renderNow`'s answer path (`:964`), the configuration listener (`:1292`), `activate` (`:1325`) and the teardown (`:1095`). **THE ACCEPTANCE IS COMPUTED ONCE AND SHARED**: `stuckEventApplies` is evaluated before `stuckReduce` moves and handed to BOTH the guard and the timer (`:964` hoists it into `answerApplies`), so the banner, the mark and the grace cannot disagree about whether an event happened; a property pins the timer's stuck/running MIRROR against `stuckReduce` event for event (4245 comparisons, 2244 of them stuck). **THE FIRE NEVER HAPPENS WITHOUT A MARK, AND THAT IS THE WHOLE SAFETY ARGUMENT**: `fireRestart` attributes the wedge with `markPickFor` (the in-flight render's pick, else the current one), REFUSES TO RESTART if neither exists (it logs why), sends a new guard event `killedByUs` (`preview-core.js:637`, reason `killed-by-us`, `:441`, added to the closed vocabulary; SET is idempotent per key so `watchdog` and `died-mid-render` KEEP their reason and their `at`), re-checks `markMatches` and refuses if the mark did not take, cancels any coalesced render (which would otherwise reach the FRESH server without passing the one consultation site), and only then calls the EXISTING `restart(context)`. The `Stopped` then `Running` edges it produces are the ones a crash produces, so the restart lands on WP-22 (b) and ASKS. **`restart(context)` GAINED A GUARD, AND THE REVIEW MADE IT SAFE (F1)**: the user's Restart button and a fire can collide -- the grace is only disarmed when the client REPORTS `Stopped`, which happens inside `client.stop()` -- and two interleaved `stopQuietly`/`startClient` pairs would leave two clients and possibly two JVMs. The first build used a plain `restartInFlight` latch, and the reviewer found the one way stage 2 could make an EXISTING feature worse: `stopQuietly` awaits `client.stop()` with no bound and catches only a THROW, so a `stop()` that never settles left the latch true for the life of the window and **the Restart Language Server command and button then did nothing for the rest of the session, in exactly the situation they exist for**. TWO CHANGES. (1) **The decision is pure**: `core.restartAttempt(underway, source)` (`preview-core.js:1392`) -- an automatic restart is REFUSED while any restart is under way (and reports `fireRefused`, so the floor is not consumed), a USER restart is NEVER refused and SUPERSEDES the one under way; the glue (`extension.js:347-379`) mints an epoch per restart, clears `client` BEFORE awaiting so the same client cannot be stopped twice, and makes the superseded run abandon at its checkpoint instead of starting a second client. (2) **`stopQuietly` bounds its wait** (`extension.js:293-331`, `STOP_TIMEOUT_MS` = 5000): a hang is not a throw, so the wait is raced against a timer and, when the bound is reached, we carry on and say so LOUDLY -- naming `ps -ef \| grep lsp.Main` and the possibility of two live servers. Both arms of the race are handled, so a `stop()` that rejects late cannot surface as an unhandled rejection. **UX**: the stuck notification and the status-bar tooltip carry one extra sentence while a grace is armed, naming the seconds and the setting that stops it; the fire logs ONE channel line; no new command, no modal, no new status-bar state (offline then held are the existing ones); the **Restart Language Server** button is unchanged. **TESTS: 67 -> 88** (`npm run test:preview`, `pass 88 fail 0`; 83 at the first build, 88 after the review), 21 new: the setting's table, the reducer's whole event table (arm, every disarm, the setting's four cases, the stale serial, the floor's two applications, the missing clock, the unknown event, `fired`/`fireRefused`), the UX texts including the PUNCTUATED join, `killed-by-us` as a mark, `restartAttempt`'s table, the review's own walk-throughs (D1's turn-it-on-while-stuck, D2's stranding scenario), N2's wording flag and F4's restore-clears-the-store, and SEVEN properties -- a fire only while stuck and Running for the live serial (275 fires, 1725 stale timers, 195 arms stretched by the floor), NO fire with the setting at 0 (1436 expiries offered), every fire preceded by a mark for its pick (213 fires, 0 refusals), the composed one that matters -- **after a fire the Stopped -> Running it causes NEVER auto-renders** (210 checked) -- the mirror agreement, and the end-to-end walk-through. **TWO MUTANTS OF OUR OWN, KILLED, WITH THREE MEASURED COUNTS** (the first write-up said "three mutants" and named two; the review caught the arithmetic, F3): `fireRestart` WITHOUT the `killedByUs` SET fires with no mark 60 times over the same 400 sequences and re-renders the wedge 28 times (the real code: 0 and 0); a reducer that IGNORES the expiry's serial restarts the server 145 times for incidents that were over (the real reducer: 0), measured as a per-step differential so the two can never drift apart. **AND SEVEN SOURCE MUTANTS MEASURED BY THE REVIEW (2026-09-21), ALL KILLED BY THE SHIPPED SUITE**: those two, plus "the accepted `{stuck:false}` no longer disarms", "the 30 s floor removed", "`killedByUs` overwrites a truer reason", "`Starting` no longer disarms" and "the `RESTART_GRACE_MAX` clamp removed". **TWO GLUE MUTANTS SURVIVED THAT ROUND**: removing `fireRestart`'s coalescer clear, and removing the restart guard -- neither was in any model. **THE DELTA RE-REVIEW FOUND THREE MORE (five in all) AND FOUR OF THE FIVE ARE NOW KILLED** by the async model and the source pins; see the delta-review paragraph at the end of this cell. Only the coalescer clear is still untestable here. **EVERY CLAIM ABOUT VS CODE IS STILL UNOBSERVED**, and the new glue is: that `client.stop()` kills a wedged server rather than only stopping the conversation (the library's own behaviour, *external*, UNVERIFIED -- if it does not, a second JVM is started beside the first and, for a non-allocating wedge, the first never dies), that `setTimeout` in the extension host fires when we think, that `affectsConfiguration` reports this key, and that the notification and tooltip text land as written. **AND, NAMED BECAUSE THE REVIEW'S OWN MUTATION RUN PROVED THEM UNTESTABLE HERE (N4): `fireRestart`'s COALESCER CLEAR and the RESTART GUARD (`restartAttempt` + the epoch + `stopQuietly`'s 5 s bound) -- removing either from the source leaves the whole shipped suite green**, because neither is in any model: they are editor glue, in the same class as the coalescing window and the untitled tab. The checklist now has a step for each. `tracker/WP-7-MANUAL-CHECKLIST.md` §2.28-2.32 are the five steps (default changes nothing; the feature; a slow render is NOT killed; turning it off mid-grace; no double restart) and they ask the tester to watch the process list. **THE DOWNGRADE HOLE, RECORDED (review F4)**: the mark's reason vocabulary is CLOSED, so a mark written by 0.1.7 with reason `killed-by-us` FAILS `isMark` in 0.1.6 -- installing the older `.vsix` over the newer one discards that mark, and the next `Stopped -> Running` in 0.1.6 re-renders the report that wedged, once. It costs one prompt and one re-wedge, it needs a deliberate downgrade, and it is the price of a closed vocabulary (the alternative -- accepting unknown reasons -- would let any shape at all count as a mark). **THE HALF THAT IS OURS GOING FORWARD IS FIXED**: `guardReduce`'s restore branch now emits `cleared` for a stored value that is NOT a mark (`preview-core.js:683-695`), so `applyGuard` removes the stale `workspaceState` key instead of re-discarding it on every activation for ever -- stage 1's own N3 rule, applied to the one branch that missed it. NOTHING stored still clears nothing. **THE DELTA RE-REVIEW (2026-09-21, DESIGN GREEN / IMPLEMENTATION RED ON TWO GLUE DEFECTS THE SUITE COULD NOT SEE), AND WHAT IT CHANGED.** The pure half was re-verified over 2.33 million exhaustive plus 40,000 random sequences with 0 violations of eleven invariants, and every pure mutant was killed; both findings were in the GLUE, which no model reached. **M1: D2's ARM-TIME FLOOR STRETCH WAS DEAD CODE IN THE SHIPPED EXTENSION.** `arm()` stretches the delay to the floor only when the event carries a clock, and the three events that can arm were sent from `extension.js` as bare object literals with NO clock (`:643`, `:1059`, `:1388`), while `expiry`, `fired` and `fireRefused` did pass one. So the announced number was always the raw setting, the expiry-time backstop this row called "normally unreachable" was the ONLY path that ran, and the sentence this document printed about it was the inverse of the truth. **THE OUTCOME WAS NEVER WRONG** -- two started restarts still landed exactly 30,000 ms apart, and both were held -- **only what the user was told.** The test model could not see it because `runGlue` supplied `at` on exactly the events the glue omitted it from. FIXED IN BOTH HALVES: the clock is passed at all three sites, and **every reducer event is now built by a PURE BUILDER that takes the clock as an argument** (`core.restartEvents.*`, `preview-core.js:1096-1131`), `extension.js` constructs none of its own, `runGlue` calls the same builders, and `arm()` REFUSES TO PRETEND -- an arm with no clock where the clock would have decided something emits a `bug` effect that the glue logs as `preview: BUG — …` (`extension.js:838`), with a test. A grep-shaped test pins the shape (every `core.restartReduce` call goes through a builder); it says in its own comment that it is a SOURCE PIN, not a behaviour test, and why one is justified here. **AND THE STRETCHED NUMBER NOW SAYS WHY**: "…in 27 s… It is not before 27 s, because the language server was restarted less than 30 s ago and restarts are limited to one every 30 s (you asked for 5 s)", in the notification, in the tooltip and in the channel's arm line. **M2: THE SUPERSEDING RESTART OPENED A TWO-CLIENT WINDOW.** `startClient` awaits `warmClasspath`, which on a cold checkout runs sbt for MINUTES, and only then assigns the module global; a restart arriving inside that window found `client` already cleared, skipped the stop and raced into its own start -- two clients, two server JVMs, one referenced by nothing, never stopped, its handlers still wired to these globals, and which one won decided by whichever warm-up finished last. FIXED: one `startEpoch` for restarts and starts alike; `startClient(context, epoch)` re-checks after its await and bails BEFORE constructing anything (`extension.js:157-175`); `restart` re-checks after `startClient` and stops a stray if one slipped through (`:395-404`); and **every handler a client registers is epoch-guarded** (`installPreviewHandlers(c, epoch)`, `:611-620`), so a stale client's notifications cannot reach `applyStuck`, `applyGuard` or `applyRestart`. **THE INTERLEAVINGS ARE TESTED WITH AN ASYNC MODEL** of `restart`/`startClient`/`stopQuietly` built on promises the test settles by hand (`restartModel`, `test/preview-core.test.js`): a restart during the warm-up, during the stop, user-after-timer, timer-after-user, user-after-user, a late-settling (bounded-out) stop, and a throwing start -- each asserting at most one live client, every non-current client stopped, one stop per client, and the guard released. The two mutants of the fix are run through the same model and do their own damage (the checkpoint removed: two live clients; `client` cleared after the await: the same client stopped twice). **(d): "we restarted it" IS NOW A ONE-SHOT TOKEN.** It survived for ever, so a SPONTANEOUS death ten minutes later was described as "the language server was restarted to clear it". `fired` mints `restartPending`; the single Stopped -> Running it causes spends it into `restartedByUs` for that edge -- the edge the held question is asked on -- and every later Running reads false. **A REFUSED FIRE STILL STRANDS THE INCIDENT, BY DESIGN**: nothing re-arms after `fireRefused` (re-arming would fire into the same refusal every N seconds), so the preview stays stuck until the user acts -- which is why D3 made the refusal VISIBLE, in the stuck tooltip and in one warning notification, rather than only in the output channel. **THE GLUE MUTANTS, RE-RUN ON A COPY OF `src` + `test` OUTSIDE THE WORKTREE (MEASURED 2026-09-21, baseline `pass 95 fail 0`), AND WHERE EACH STANDS NOW**: (1) the `startClient` epoch checkpoint removed -- **KILLED** (`fail 1`); (2) `client` cleared AFTER the stop await -- **KILLED**; (3) the 5 s stop bound removed -- **KILLED**; (4) `fireRestart` skipping `restartAttempt` -- **KILLED**; (5) M1's clockless arm, the clock dropped from the three arming builder calls -- **KILLED**; (6) `fireRestart`'s coalescer clear removed -- **SURVIVES**, and is the one that stays in the UNOBSERVED list with the manual step (§2.32b) that would see it. **WHAT KILLS THEM IS WORTH SAYING EXACTLY, BECAUSE IT IS NOT THE MODEL**: an async model is a model, so mutating `extension.js` cannot make it fail; what fails is the SOURCE PIN. The async model's job is to show that the invariant is real and that the fix's own mutations break it (the checkpoint removed leaves two live clients; `client` cleared late stops one client twice), and the pins' job is to notice if the shape drifts back. Both were needed: **MEASURED, the first cut of the pins let (2) and (5) through**, and they were tightened until the run above was five out of six. **NOT BUILT BY STAGE 2**: no server change of any kind, no `ermine/preview/exiting` and no exit code (that is WP-23, still PARKED), no new command, no modal, no backoff beyond the one grace and the floor, no persistence of the timer (a window reload forgets the grace, as it forgets the incident), and NO CHANGE TO THE DEFAULT, which is 0 and stays 0 until the user says otherwise.** **CARRIED FOLLOW-UP, STILL OPEN AND STILL NOT WP-22's OWN WORK (WP-22 EDITED NO SCALA AT ALL, so the comments below are exactly as WP-24 left them)**: the restored `lsp/Preview.scala` still carries `0a092242`'s forward references to WP-6 (`:100-101`, `:699`, `:2037`, and seven asides), whose promises WP-24 withdrew; WP-24 left the Scala byte-identical on purpose, so **the next change that touches `Preview.scala` -- this one, if it ever does -- corrects those comments in passing.** It is a comment edit and belongs to no ticket of its own | **MET, EXCEPT THE MANUAL HALF, WHICH NOBODY CAN MEET HERE.** **MEASURED 2026-09-21 (STAGE 2): `npm run test:preview` `tests 83 / pass 83 / fail 0` and `node test/load-test.js` PASS (live step `Ermine session ready: 129 modules in 14.3s`, run twice, 18.9 s and 14.3 s), with `scripts/liveness.sh` reading `lsp=0` before and after. **REVIEWED THE SAME DAY (independent, DESIGN GREEN / IMPLEMENTATION GREEN): the safety property held over 2,304,960 EXHAUSTIVE sequences and 40,000 random ones through a glue order the reviewer re-derived, with pick changes, the coalescer and the timer handle modelled -- 0 violations -- and seven source mutants were killed by the shipped suite. ONE code must-fix (F1, the restart guard), three documentation must-fixes (F2, F3, F4) and three design must-argues (D1, D2, D3) WERE ALL APPLIED, plus seven nits; AFTER THEM `tests 88 / pass 88 / fail 0` and `node test/load-test.js` PASS again (live step `129 modules in 15.1s`; `liveness.sh` `lsp=0` before and after). **A DELTA RE-REVIEW THE SAME DAY RETURNED DESIGN GREEN / IMPLEMENTATION RED ON TWO GLUE DEFECTS NO TEST HERE COULD SEE (M1 and M2, both fixed below, with (d) and the doc corrections), AFTER WHICH `tests 95 / pass 95 / fail 0` and `node test/load-test.js` PASS (live step `129 modules in 14.2s`, `lsp=0` before and after). **A FINAL RE-CHECK RETURNED DESIGN GREEN / IMPLEMENTATION GREEN WITH ONE MUST-FIX (the edge the epoch guard silenced, recorded below), after which `tests 96 / pass 96 / fail 0` and `node test/load-test.js` PASS (live step `129 modules in 14.4s`, `lsp=0` before and after).** The STAGE 2 counts are in the `AS BUILT, STAGE 2` block above.** MEASURED 2026-09-20 (stage 1, kept as the record): `npm run test:preview` (`node --test test/preview-core.test.js`) `tests 67 / pass 67 / fail 0` (39 before WP-22, 58 at the first build, 66 after the first review's must-fixes, 67 after the delta review's -32603 fix), carrying the new table cases -- every SET row, every CLEAR row, every near miss that must NOT clear, the restore rules, the reasons vocabulary -- and THREE properties: "over any event sequence an automatic `Running` re-render is issued ONLY with a clear mark" (219 restarts, 59 of them held, on the pinned seed), "an explicit render is NEVER suppressed" and "a foreign mark is never consulted", plus the agreement property between `stuckEventApplies` and `stuckReduce` (6000 events, now including the adversarial `seq` shapes), and -- since the review -- M1's own property: the glue model generates a server death in BOTH orderings AND a rejection with no `Stopped` edge at all (the -32603 shape), and asserts something about EVERY death it generates -- a gone one marks, a settled one leaves the mark exactly as it was. **MEASURED: 2063 deaths generated, 2063 asserted, 0 SKIPPED** (693 rejection-first, 649 stopped-first, 721 rejection-only; 546 with a render in flight), **with the pre-review code run as a mutant over the same sequences and caught 363 times.** The delta review found that the property's first shape SKIPPED every settled death (`if (!d.gone) continue` -- 257 of 783 skipped, 112 of them unremembered), which is exactly how the -32603 misclassification hid inside a green suite; nothing is skipped now and the count itself is asserted. `node test/load-test.js` unchanged and green (`PASS -- the extension loads, activates and registers correctly`, with its live step reaching `Ermine session ready: 129 modules in 14.1s`). **A generator note, MEASURED while writing these**: the LCG the older properties use is degenerate modulo 8 (1994/6 over 2000 draws), so the new generators use a 32-bit xorshift; the OLD generators were left exactly as they are. **manual**: `tracker/WP-7-MANUAL-CHECKLIST.md` §2.15-2.27 was WRITTEN for this ticket and is UNRUN, like every other step in that file | commit (`node --test`) + manual / ~1 day |
| WP-23 | **PARKED. DO NOT START: a server-side deliberate exit (the design review's "B-SRV"). STILL PARKED AFTER WP-22(c) SHIPPED (2026-09-21): (c) is the client-side half ("B-EXT") and THE UNPARK TRIGGER BELOW IS UNCHANGED -- a wedge where our `client.stop()` did NOT kill the server. Nobody has run (c) in an editor, so nobody has observed that either way; §2.28-2.32 of the manual checklist ask the tester to watch the process list for exactly that.** If it is ever built: exit from the `java.util.Timer` thread only after `Wire.send`'s own `out.flush()` has returned (READ, `Rpc.scala:385-390`), **never** `Server.stop`, whose scaladoc says DISPATCH THREAD ONLY (READ, `Rpc.scala:490-497`); a free exit code (17 -- `Main` uses 0, 1 and 2, and the JVM's OOM path uses 3); discriminated by a last `ermine/preview/exiting {reason, seq}` notification and **NEVER by the exit code**, which `vscode-languageclient`'s documented close handling does not carry (*external*, UNVERIFIED); a grace long enough to leave Q10's recovery its chance, not the 1000 ms of WP-6; a setting `ermine.preview.exitOnWedgeSeconds`, default 0. **UNPARK TRIGGER, and nothing else**: a wedge observed where WP-22's client-initiated `client.stop()` did NOT kill the server -- one whose DISPATCH thread is also wedged. Nothing today can produce that: the dispatch thread answers a hover in 0.00 s while the preview is wedged (MEASURED, §2.5), `Preview.shutdown()` sets `stopping`, drains, cancels the timer and returns without joining the preview thread (READ), and the preview thread is a daemon. The shape that would never die is a BLOCKED preview thread, which WP-13/WP-14 make reachable. **THAT LAST SENTENCE IS WRONG AND IS CORRECTED HERE (WP-22(c) review, carried; the original is kept above as the record).** READ, 2026-09-21, in this worktree: `Main.scala:336-341` answers `shutdown`, `:342-346` handles `exit` by calling `preview.shutdown()` and `server.stop(code)`, and `:348-353` reaches `System.exit(code)` when `server.run()` returns; `Preview.shutdown()` (`:773-782`) sets `stopping`, drains the queue with -32800 and cancels the timer WITHOUT joining the preview thread; and the preview thread is a DAEMON (`:2203-2207`). **So a BLOCKED -- or spinning -- preview thread does not keep this JVM alive once `exit` arrives**: `System.exit` halts it whatever that thread is doing, and a daemon would not have held it open anyway. What a blocked preview thread DOES do is never die BY ITSELF, because it allocates nothing and so never reaches `-Xmx`: that is a reason for WP-22(c) to exist, not a reason to unpark this ticket. **THE SHAPE THAT WOULD SURVIVE OUR STOP IS THE ONE THIS ROW ALREADY NAMES TWO SENTENCES EARLIER: A WEDGED DISPATCH THREAD**, because it is the dispatch thread that must receive `exit` and let `run()` return. Nothing today can produce one (MEASURED, §2.5: a hover answered in 0.00 s while the preview was wedged) | -- | -- **do not start** |
| WP-24 | **DONE 2026-09-20: WP-6 stage 1 REMOVED from the tree, by the user's decision (§13, Q13).** The instrument was `git checkout 0a092242 -- <path>` for the four files stage 1 touched (`Runtime.scala`, `lsp/Preview.scala`, `session/Lib.scala`, `session/Session.scala`) plus `git rm scalacheck-binding/src/main/scala/TestPreviewCancel.scala`, and **NOT `git revert b7b93daa`**, which would have deleted the record (WP-20, WP-21, stage 2's figures, the amended rows) and undone two keepers. VERIFIED BEFORE THE CHECKOUT: `0a092242` is `b7b93daa`'s SINGLE PARENT and exactly one commit separates them, and all four files are byte-identical at `b7b93daa` and at HEAD `0c104416` (the two later commits, `02787f99` and `0c104416`, touched only `tracker/`), so restoring from `0a092242` reproduces the pre-WP-6 content exactly -- MEASURED afterwards with `git hash-object <path>` against `git rev-parse 0a092242:<path>`, all four EQUAL, and `Runtime.scala` is 413 lines, 100 % CRLF, no bare LF. **KEPT AT HEAD CONTENT, UNTOUCHED**: `PreviewSupport.scala` (the shared harness `TestLspRobustness` imports), `TestLspRobustness.scala` (which carries the unrelated one-line order-dependence fix `bench.schema(58, gone, "report")`, Q16), the comments-only `extension.js` hunks of `b7b93daa` (WP-7's two doc blocks, which say nothing about the cancel -- checked, no correction needed), `tracker/tools/eval-bench.sh`, `tracker/tla/`, and every tracker line. **THE RESTORED SOURCE CARRIES `0a092242`'s OWN FORWARD REFERENCES TO WP-6, AND THEY ARE NOW FALSE PROMISES.** `lsp/Preview.scala` mentions WP-6 ten times; the three that promise behaviour are `:100-101` ("an evaluation that cannot be interrupted (WP-6 is what makes it interruptible)"), `:699` ("the work is not interrupted (WP-6 does that)") and `:2037` ("a loop nothing in the process can interrupt (WP-6 is the ticket that makes it interruptible)"); the other seven (`:137`, `:762`, `:975`, `:1090`, `:1095`, `:1110`, `:1118`) are design asides in the same direction. **EVERY ONE OF THOSE PROMISES IS WITHDRAWN** -- there is no ticket that makes an evaluation interruptible. **THE SCALA WAS DELIBERATELY NOT EDITED**: byte-identity with `0a092242` is this change's evidence, and one comment edit would destroy it. Correcting those comments belongs to the NEXT change that touches `Preview.scala` (recorded in WP-22's row). Four comments in the two kept test files NAMED `TestPreviewCancel` as a live second suite. **THE THREE PRESENT-TENSE ONES WERE REWORDED -- COMMENTS ONLY, NO CODE** (`PreviewSupport.scala`'s header, `TestLspRobustness.scala:58-65` and `:1508-1511` -- **the committed-tree numbering, since ROBUST-3 commits first and adds lines above both**): each now says that the harness was extracted for a second suite, `TestPreviewCancel`, which WP-24 removed with WP-6's cancel, and that the extraction was KEPT because `TestLspRobustness` uses it. The fourth (`TestLspRobustness.scala:2069` in the committed tree, "EXPOSED BY, NOT CAUSED BY") is left exactly as it is: it is true as history. "`TestLspRobustness` unchanged" in the done-when means its BEHAVIOUR; both files are LF-only before and after (checked with a CR count) | `core/compile` + `core/Test/compile` green; the three kept suites RECOMPILED FROM SOURCE against the restored `Preview.scala` (MEASURED: `compiling 3 Scala sources`, COMPILE-OK), which is how "does anything kept depend on a member stage 1 added" was answered -- by compiling, not by reading; `TestLspRobustness` `Passed: Total 63, Failed 0, Errors 0` in 52 s (inside §11's 60 s cap for group D, which no longer serialises against a second preview suite) and `TestRunner` `Passed: Total 40, Failed 0, Errors 0` in 42 s; `editor/vscode`: `node --check` on both sources and `npm run test:preview` 39/39; `git grep -n -E "Cancelled\|cancelOnTimeout\|armCancel\|disarmCancel\|cancelArmedFor\|cancelTarget\|cancelWhy\|fireCancel\|firePhase2"` over `core/` finds only the pre-existing `Rpc.RequestCancelled` (-32800). The `pr` gate is the orchestrator's and runs once, after review | pr / ~2 h |
| WP-27 | **NOT BUILT. Found by the WP-22 review (2026-09-20), test-generator hygiene, `editor/vscode` only.** Replace the LCG in the TWO generators WP-7 left in `editor/vscode/test/preview-core.test.js` (`test:294` "every generated message sequence leaves the state consistent" and `test:356` "the final state is the highest-seq notification's") with the 32-bit xorshift that is already in the same file (WP-22's generators use it). **THE REASON, MEASURED**: `seed = (seed * 1103515245 + 12345) & 0x7fffffff` overflows 2^53 and its low bits are destroyed -- `% 2` gives 1992 zeros in 2000 draws -- so `test:294` sees 24 `{stuck:false}` notifications in 4074 and `test:356`'s oracle is decided by a falling edge exactly ONCE in 400 runs (a mutant that ignores the `stuck` field fails 1 of 400). Neither test is vacuous today; both are one draw away from being so, and both cover §4's rules, which the wedge guard now rides on. **NOT A BUG IN THE PRODUCT**: nothing outside the test file uses these generators. WP-22 deliberately did NOT touch them -- changing a passing test's generator inside another ticket hides whatever it then finds | the two generators use the xorshift; both tests still pass; the falling-edge counts are re-measured and written into §11's finding row; a mutant that ignores `stuck` now fails a large fraction of runs rather than 1 of 400 | **commit** (`node --test`, no gate, no JVM) / ~1 h |
| WP-25 | **BUILT, REVIEWED AND MERGED 2026-09-21.** Commit `ee093b46` on branch `wp25-scrub` (worktree `ermine-scala-wt-wp6-perfA`), merged into `widget-preview` at `c73d4e7c`; its as-built note is `tracker/WP-25-AS-BUILT.md`, folded into this document here. **DECIDED BY THE USER, 2026-09-20** -- their words, *"harden unloading."* (§13, Q20). **REVIEWED BY AN INDEPENDENT REVIEWER OVER TWO PASSES**: **RED** on the origins-coverage claim -- round 1 claimed no dangling origin was reachable, and that was false on the resident's own 130-module session (MEASURED: `scrub({Native})` leaves **85** `termNameOrigins` and **26** `consOrigins` entries keyed by a LIVE name and pointing at a DEAD one) -- then **DESIGN GREEN / IMPLEMENTATION GREEN** after the reviewer ran its OWN DROP and FILTER implementations as controls and **conceded both disputed points** (`tracker/WP-25-AS-BUILT.md` §12). **`pr` GATE GREEN ON THE MERGED TREE** (MEASURED, content key `3f07799de8b3ee6376c808c805dd84cbbfd3d427`, read from `.gate-cache/`): compile PASS 18 s; corpus PASS 48 s (89 loaded / 79 rejected / 0 unknown of 168, 0 differ from expected); lsp PASS **641 checks** in 56 s; suites PASS **`Passed: Total 1292, Failed 0, Errors 0`** in 675 s. **`lean` IS UNAVAILABLE IN THIS WORKTREE** -- there is no `tracker/lean/.lake` here, so that gate answers "unavailable" rather than a verdict (READ, `scripts/gates.sh:144`): it is neither green nor red. **THE "PROPOSED HARDENING, ONE LINE" BELOW IS REFUTED, NOT BUILT.** MEASURED over the SAME 30 seeded subsets (`wp25-design.log`), as "dangling / reload died / surface equals a fresh load": **today's scrub 16 / 0 / 30 of 30**; **the proposed drop 0 / 8 of 30 / only 14 of 30** -- it removes the dangling entries and then leaves the re-exporter in `loadedFiles` LOOKING LOADED, so `loadModules` never reads it back and the name is gone from every importer of it; **closing over RE-EXPORTERS (shipped) 0 / 0 / 30 of 30**; closing over IMPORTERS 0 / 0 / 30 of 30. And on ROBUST-3's own reproduction the drop **dies with the SAME message as today's scrub**, because the renamer answers `Unresolved` with NO diagnostic (`rename/Renamer.scala:381`, *"unknown constructors die at typecheck"*) and `Lower.varFor` then mints a placeholder: the honest "not in scope" the proposal aimed at **does not exist on this path**. **WHAT WAS BUILT INSTEAD** (`session/Session.scala:846-891`; the helpers' line numbers are given against `c73d4e7c`, the as-built's own having already drifted). **(1) IT CLOSES ITS ARGUMENT OVER RE-EXPORTERS** -- `reExportClosure` (`Session.scala:1045-1069`), from the session's OWN tables and never from `Session.depCache`; a module RE-EXPORTS when one of its name keys holds an entity belonging to another module. MEASURED on the 130-module session, closure of ONE module: **re-export max 6 / mean 1.8 modules**, against **the importer closure's max 96 / mean 29.3** (`dependentsOf`; the same sweep's name-level importer form measures 96 / 25.8, `wp25-opt.log`). It is NOT the importer closure: a module that merely USES a name it does not re-export keeps its own values and dangles nothing -- that is staleness, the caller's question. **(2) IT REPAIRS THE ORIGINS TABLES BY SPLICE** -- `reorigin` and `greatestAncestors` (`Session.scala:965-1011`): for every key that is still a name and points at a scrubbed name, replace that ancestor by ITS OWN greatest ancestors computed over the table AS IT WAS BEFORE the scrub, so the walk reaches exactly the name it reached before. **DROP AND FILTER WERE MEASURED NOT TO REPAIR** (`wp25-splice.log`, `wp25-cheap.log`; the witness is `module T where import Prelude; import Native.List; t = Nil#` and the control is that witness on the UNSCRUBBED session): no repair leaves 85 entries and the witness DIES; **DROP takes the count to 0 and the witness STILL DIES**; **FILTER takes it to 0, the witness still dies, and it wrongly LOADS the genuinely ambiguous case**; **SPLICE gives 0 and the witness LOADS**, with the ambiguous case dying exactly as the control does. **WHY THE TABLE IS NOT THE POINT**: `Renamer.resolveGlobal` (`rename/Renamer.scala:158-164`) resolves only a ONE-ELEMENT answer and compares NAMES, not entities, so what has to be preserved is **THE WALK** -- MEASURED, `{Native}` moves **111** greatest-ancestor answers before the repair and **0** after, and for an importer-closed set `reorigin` repairs **0** entries, because a key whose ancestor was scrubbed is then itself scrubbed. **(3) IT RETURNS THE SET IT SCRUBBED BY**: `Resident.reloadModules` (`lsp/Resident.scala:189-240`, the scrubs at `:208` and `:230`, the report at `:238`) reloads, pends and REPORTS that set; `Runner.invalidate0` (`json/Runner.scala:680-736`, the scrub at `:723`) evicts the reports, logs and answers with it; and `Resident.checkFile` (`:432-441`) **DELIBERATELY IGNORES it**, with the reason in the code -- `e` there is a throwaway per-request copy, and an acyclic import graph (`Session.acyclic`, `Session.scala:104-106`) guarantees the module does not import its own re-exporters, so the check never needs them back. **THE TYPE SIDE IS NO LONGER UNVERIFIED -- IT IS MEASURED** (`tracker/WP-25-AS-BUILT.md` §2, on the 130-module session): **`cons` DOES dangle** (174 of 401 entries aliased; `cons->cons=3` in the first failing seeded subset); **`privateCons` shows 0 of 78 aliased** -- never observed to alias, so that arm of the closure has never fired (MEASURED 0, plus INFERRED: same code path, closed the same way); **`classes` shows 0 of 14 and CANNOT alias by construction** -- no source-level `instance` statement exists (`instance` is in `parsing/package.scala:30`'s `startingKeywords` and no parser consumes it), so `s.classes` is written only under the class's OWN name; **`classOrigins` is EMPTY and has NO WRITER anywhere in the repo**. Both dead-by-construction arms say so in the code. **THE THREE COUNTS ARE THREE DIFFERENT QUESTIONS, NOT A CONTRADICTION**: **13 of 30** is ROBUST-3's narrower `termNames -> env` probe on its own seed (the figure this row carried, below); **16 of 30** is the shipped MULTI-TABLE reachable form on this ticket's seed (`wp25-final.log`, measured out of tree against the unhardened scrub); **25 of 30** is a FLAT origins form printed by the first red run and no longer used. **COST, MEASURED** (`wp25-timing2.log`; one process, one 130-module `Prelude` + `Layout` session, the two columns INTERLEAVED and each run twice with the lower taken): **+1.5 to +3.0 ms per scrub on the per-keystroke path** (`Resident.checkFile` scrubs once per debounced keystroke, against a ~50 ms editor budget) and **+0.8 ms on an importer-closed reload** (`dependentsOf(Maybe)`, 77 modules, 2.28 -> 3.11 ms). **Both are MICROBENCHMARKS, not an end-to-end `didChange` round trip.** The chain repair alone costs +1.07 ms where it fires and +0.51 ms where it does not (`wp25-n8.log`, one input with and without it); the rejected whole-table prune measured 6.9-7.8 ms on the same shapes. **KNOWN, MEASURED LIMITS.** **(a) "SAFE" MEANS: NO NAME OUTLIVES WHAT IT NAMES, AND ANY MODULE CAN BE READ AFTERWARDS. IT DOES NOT MEAN "NOT STALE"** -- `Type.Con.equals` compares only the NAME (`Type.scala:567-570`) and an alias holds the same object, so a stale type alias does not split type identity, but it carries a stale `Type.Con.decl`. **(b) `lsp/Definitions.canonWith` IS NOT REPAIRED AND NO FIX EXISTS.** After `scrub({Native})` ALONE, **two** canonical keys still in scope MOVE -- `Prelude.head#` and `Prelude.tail#`, whose `Native.head#` / `Native.tail#` each have TWO greatest ancestors -- because `canonWith` (`lsp/Definitions.scala:839-853`) follows only a single-element entry and STOPS at a multi-element one, returning a different LIVE name. `canonTerm` / `canonType` feed `gkey` -> `GlobalKey` (`:856-859`), the bucketing key for definition, references and **rename**, so this is **an INCOMPLETE RENAME edit set -- a wrong edit, not a missing answer**. **No value can restore the old answer**: it was `Native.head#`, a name in the module just unloaded. **EXPOSURE IS A NON-IMPORTER-CLOSED SET ONLY -- the WP-26 case**: MEASURED 0 of 130 importer-closed shapes (every product caller today), 1 of 130 single-module `checkFile`-shaped scrubs (only `{Native}`, 2 keys), 0 of 25 arbitrary subsets, and **0 split buckets everywhere**; `lsp/Main.scala:224-226` also drops the symbol and quickfix caches after each reload. **PINNED BY NAME in `TestScrub`**, so any change to it fails. **(c) THREE `Relation.*` ORIGIN ENTRIES DANGLE ON ONE SUBSET BY DESIGN**: on the reviewer's six-module subset `R:termNameOrigins = 3` -- entries naming a greatest ancestor whose module really was unloaded (`Relation.append` goes on naming `Relation.Row.append`), a spelling that is ambiguous with or without the scrub (MEASURED control). **THE ACCEPTANCE CRITERION DEMANDING 0 THERE WAS WITHDRAWN ON THE REVIEWER'S RECOMMENDATION**, whose instruction was *"do NOT ship FILTER"*: DROP and FILTER both reach 0 there while INTRODUCING walk movement (3) where round 1 and SPLICE have none. **(d) A SPLICED ENTRY SURVIVES THE RELOAD OF THE SCRUBBED MODULE**: the repaired entry belongs to a module that was NOT scrubbed, so reloading `{Native}` does not rewrite it -- `Prelude.Nil#` still records `Native.List.Nil#` where a fresh load records `Native.Nil#` -- until the KEY'S OWN module is next read. It is walk-equivalent, and the review measured 0 walk movement and the witness reading after that reload (READ, `Session.scala:937-944`). **(e) NOTHING EXERCISES `Resident.reloadModules` AGAINST A REAL WIDENING** -- with dep-cache edges intact `dependentsOf` is already importer-closed, so the closure adds nothing and `reorigin` repairs nothing, which is why the LSP suites are green either way; both paths are exercised only by `TestScrub` and the probes. **UNVERIFIED.** **(f) THE REPL's `:reload` WAS NOT RUN** -- `reloadChangedModules` is untouched, and the argument is from the diff, not a measurement. **UNVERIFIED**; see the new WP-28. **THE ROW AS IT STOOD BEFORE THE MERGE, KEPT AS HISTORY (its two marked claims are superseded above):** **DECIDED 2026-09-20 BY THE USER -- *"harden unloading"* -- AND BEING BUILT NOW IN A SEPARATE WORKTREE**: `ermine-scala-wt-wp6-perfA`, branch `wp25-scrub`. **NOT YET BUILT, NOT REVIEWED, NOT MERGED, and nothing of it is in this worktree.** Side worktrees write their own as-built notes and do not edit this document; this row is amended when it merges. The ticket as written, and the evidence for it: Found by ROBUST-3 (2026-09-20), the test-harness fix for the `pr` gate red on tree key `cae6f47f42cc3a6cf0c99b0c46e61f1a1d4ff890`; the DECISION TO BUILD IT IS THE USER'S (§13, Q20).** `Session.scrub` (`session/Session.scala:811-827`) is ASYMMETRIC and relies, unchecked, on its caller handing it a set of modules CLOSED UNDER IMPORTERS. `e.env` is filtered by the **V's own defining** `Global`'s module (`v.name`); `e.termNames`, `termNameOrigins`, `cons`, `privateCons`, `consOrigins`, `classes`, `classOrigins` are filtered by the **key's** module (READ). So a set that holds a DEFINER but not its RE-EXPORTERS removes the definer's `termNames` key and its `env` entries while every re-exported key survives pointing at a value that is gone: `Control.Monad.Functor`, `Control.Alt.Functor` and `Control.Ap.Functor` all still name `Control.Functor.Functor` after a scrub of `{Control.Functor, Maybe}`, and the next read of `Maybe.e:53` -- whose `Functor` collapses to the ORIGIN because two import paths reach it (`rename/ModuleScope.scala:67-78`) -- dies in `Subst.assertTermClosed` (`Subst.scala:1919`) with `undefined term`, inside a stdlib file the user never touched, rather than with an honest "not in scope". PROPOSED HARDENING, ONE LINE **[REFUTED BY MEASUREMENT 2026-09-21 AND NOT SHIPPED -- see above]**, so that any set is safe: after the `e.env` filter, `e.termNames = e.termNames filterNot { case (g, v) => (mine(g) && !b.termNames.contains(g)) \|\| !e.env.contains(v) }`. THE PIN, and it is a better test than trying to pin the race: *for any subset S of the loaded modules, after `scrub(e, builtins, S)` every `e.termNames` value is still in `e.env`* -- **MEASURED by ROBUST-3's probe: it FAILS TODAY on 13 of 30 random subsets** **[one of THREE different questions -- see the reconciliation above]** and the definer/re-exporter case reproduces the gate's exact message byte for byte. **THE TYPE SIDE IS UNVERIFIED** **[NOW MEASURED -- see above]**: `cons` / `privateCons` are keyed by module the same way while a `Con` carries its own module, so the shape looks identical, but no probe was run on it -- check it in the same ticket. NOT REACHABLE IN THE PRODUCT TODAY by the path ROBUST-3 found: in `bin/ermine-lsp` nothing removes a `Filesystem` key from `Session.depCache` (`lsp/Documents.scala:77`, `:111` evict `Buffer` keys only; the REPL's `reloadChangedModules` revert, `Session.scala:899-905`, is not in the server), so `dependentsOf` always has complete edges and the set is closed by construction. This is hardening against a class of caller, not a live bug | **MET, MEASURED, AND WIDENED BY THE REVIEW.** The shipped pin is the WALK, not the table: *for every name still in scope, `collapseNames`' greatest-ancestor walk answers what it answered before the scrub*. `TestScrub`, **8 properties, `Passed: Total 8, Failed 0, Errors 0`** (§11's "Session scrub (WP-25)" row), shown RED as designed twice -- `Failed: Total 7, Failed 2` against the pre-repair origins code, where **every small-fixture property was green on the broken tree**, and `Failed: Total 8, Failed 1` with the canonical-keys conjunct temporarily demanding 0 for `{Native}`. `core/test` green as the `pr` gate's `suites` (**1292**, 0 failed); the corpus and `lsp` gates unchanged (`lsp` **641 checks**, PASS). **ORIGINAL DONE-WHEN, KEPT AS HISTORY**: `core/test` green; the pin above passes for all 30 probe subsets and fails on the unhardened tree; the corpus and `lsp` gates unchanged | **pr** (session core) / ~half a day **ESTIMATED; IT ACTUALLY RAN TO THREE ROUNDS AND TWO INDEPENDENT REVIEW PASSES -- nine sbt runs, listed in `tracker/WP-25-AS-BUILT.md` §6** |
| WP-26 | **RE-SCOPED 2026-09-21 BY WP-25's MERGE -- NOT CLOSED, AND STILL NOT BUILT.** The severity of its "worse case" changed, its substance did not; the clause about the 500 is struck below FOR THE MECHANISM THIS TICKET NAMES, and the original text is otherwise kept and amended in place. **WHAT WP-26 IS NOW, both parts STILL INFERRED BY READING AND NOT MEASURED**: **(1) THE STALENESS HALF** -- the shared `depCache` entry's mtime, refreshed by the resident, makes the render session keep serving an OLD module; symptom, a stale preview document; and **(2) NEW, FOUND BY WP-25** -- a set that is not importer-closed is now unloaded and reloaded correctly, but `lsp/Definitions.canonWith` can then answer an **INCOMPLETE RENAME** (MEASURED: 2 keys after `scrub({Native})`, `Prelude.head#` and `Prelude.tail#`; §14's WP-25 row, limit (b)), and no repair exists -- so this ticket is where that exposure lives. **The measurement it needs is unchanged**: a group-D property with a real `Resident` beside the bench. **NOT BUILT.** ORIGINAL TEXT, AMENDED IN PLACE: **NOT BUILT, INFERRED BY READING AND NOT MEASURED, likelihood LOW. Found by ROBUST-3 (2026-09-20).** `Session.depCache` is PROCESS-GLOBAL and shared by the resident and the render session, but the staleness question it answers is PER SESSION: `Runner.staleFiles` (`json/Runner.scala:568-574`) asks `Session.depCache.get(sf).map(_._1) != sf.lastModified`. If the RESIDENT re-parses a file the render session has also loaded (the user edits it and the watcher fires), the SHARED entry is refreshed with the new mtime, and the render session's own scan then reports that file as CURRENT -- so the preview keeps serving the OLD module. That defeats §2.5's *"fresh files, whoever saved them"* for exactly the files both sessions hold, which is every stdlib module the report imports. SYMPTOM: usually a stale preview document. THE WORSE CASE, and the one that ties this to WP-25: if the refreshed entry also carries a CHANGED IMPORT LIST, `Session.dependentsOf` (`session/Session.scala:771-783`) loses a real importer edge -- it builds the graph from that same cache -- and the dirty set stops being closed under importers, which is the state WP-25 is about; *"the user would then see a 500 naming a file they did not touch"* -- **STRUCK 2026-09-21 FOR THE MECHANISM WP-26 NAMES, and kept quoted as history: since WP-25 merged at `c73d4e7c` a NON-CLOSED set yields a CORRECT, if larger, unload and a CLEAN reload. MEASURED: 30 of 30 mid-walk splits reload clean, plus the reviewer's own 25 subsets on the resident's session with `reload-died=0`. It is NOT a claim that no 500 is reachable by any route.** Needs an import line added or removed in a file BOTH sessions hold, which is why the likelihood is low. WHAT A MEASUREMENT WOULD BE (nothing cheaper is honest): boot a resident and a render session in one JVM over one root, render a report that imports a workspace module, edit that module (first its body, then its import list), let the RESIDENT reload it, then render again and assert the document followed the file -- a group-D property with a real `Resident` beside the bench, which group D does not have today. POSSIBLE SHAPES, neither designed: key the cache by session, or have `staleFiles` compare against what THIS session loaded rather than against the shared entry | a property of the shape above is RED before the change and green after; §2.5's row re-measured | **pr** / ~1 day, after WP-25 |
| WP-28 | **NOT BUILT. Found by WP-25 (2026-09-21); a DRIFT TRAP, NOT A CORRECTNESS HOLE.** `Session.reloadChangedModules` -- the REPL's `:reload` path -- carries its OWN inline scrub (`session/Session.scala:1105-1118`, the block after `val scrubbing = dirtyModules ++ extraScrubbingModules` at `:1100`): a second, weaker scrub over a DIFFERENT set of tables. It touches `env`, `termNames`, `cons`, `loadedFiles` and `loadedModules` and **MISSES FIVE** -- **`termNameOrigins`, `privateCons`, `consOrigins`, `classes` and `classOrigins`** (READ). **IT IS NOT EXPOSED TO THE DEFECT TODAY** (READ, `tracker/WP-25-AS-BUILT.md` §3c): it computes an IMPORTER-CLOSED set itself -- the transitive-importer closure `go` (`Session.scala:1087-1091`), closed by construction -- its only caller-supplied extra is `Set("REPL")`, which nothing re-exports, and its failure path restores the session wholesale (`sessionEnv := oldState`, `Session.scala:1148`). The work is to FOLD IT INTO `Session.scrub` so the two cannot drift. **NOTE `:reload` WAS NOT RUN BY WP-25** -- that argument is from the diff, not a measurement (UNVERIFIED) | the REPL path scrubs through `Session.scrub` and nothing else scrubs; `TestScrub`'s invariants hold across a `reloadChangedModules` cycle; `core/test` green and the REPL smoke unchanged | **pr** (session core) / ~half a day |
| WP-29 | **NOT BUILT, NOT SCHEDULED. Filed 2026-09-23 by the user's Q21 decision (§13). "Zero-rows relations lose the header the compiler knew."** **THE MECHANISM (READ, and the 500 MEASURED):** `relation` (`Relation.e:23-24`) is `mkRelation# (toList# r)`; the primitive (`session/Lib.scala:341-343`) calls `buildRelation` (`Runtime.scala:376-377`), which for an EMPTY list returns the header-less sentinel `EmptyRel` (`Runtime.scala:110`) -- types are erased at runtime and the header is read off the first record, so with no record there is no header. The JSON encoder then has nothing to put in `columns` and refuses (`json/Doc.scala:205-210`): *"an empty relation built from no rows carries no columns; give it a header (mkRelationWithHeader#) or a static hint"*, a 500 at the relation's path (`$.children[1].cells[0][0].props` for the old `Sales`, `$.props` for `tracker/playtest/fixtures/WpEmpty.e`). **The type checker knew the row type** (`relation : List {..r} -> Relation (|..r|)`); only the runtime lost it. `relationWithHeader : Row r -> List {..r} -> [..r]` (`Relation.e:26-30`) is the same function with the header passed as a value: `mkRelationWithHeader#` (`session/Lib.scala:345-350`) builds `RelEmpty(header)` for an empty list and calls `buildRelation` otherwise. **Why the runner cannot fill the gap** (`scalacheck-binding/src/main/scala/TestRunner.scala:608-611`, the (b7) `RgEmpty` property's comment): `Doc.fromRuntime(node, hints)` could take a header per walker path, but the runner has only the report's RESULT type (`Layout.Doc.Node`), never the type of a relation buried in a widget's props, so there is nothing to build a hint from. **Today's workaround** is per example: `Sales.e`'s `byDay` uses `relationWithHeader {region, day, amount, units}` (Q21's fix; the Row literal as in `core/examples/Lang/CsvIntake.e:137-138`, which gets `single_Brace`/`snoc_Brace` through `import Prelude` (`Prelude.e:43`); `Sales.e` imports no Prelude, so it names `import Relation.Row using {single_Brace; snoc_Brace}`). **THREE DIRECTIONS, RECORDED NEUTRALLY; THE USER CHOOSES LATER, AND NONE IS CHOSEN:** **(a) the compiler passes the row type as evidence** when elaborating `relation`, so an empty list builds `RelEmpty(header)` exactly as the `WithHeader` variant does -- a compiler-side elaboration change; the user's call; done when: `relation []` at a known row type encodes as a zero-row table with that type's columns, `TestRunner`'s (b7) `RgEmpty` is rewritten to expect that document (or to a genuinely row-polymorphic case that still 500s), `WpEmpty.report` renders `ok=true`, and `core/test` plus the corpus sweep are unchanged. **(b) the encoder emits a ZERO-COLUMN table** (`columns: []`, `rows: []`) instead of refusing, and the client's table widget says "no rows" -- ENGINE-ONLY, no compiler change; **whether the client's table widget (the writers' `runTabular`) accepts zero columns is UNCHECKED**; done when: `json/Doc.scala`'s `EmptyRel` arm with no hint yields that shape, (b7) is rewritten to expect it, `WpEmpty.report` renders `ok=true`, and the panel is OBSERVED drawing a zero-column table as "no rows" rather than an error box (a playtest step, since it needs the webview). **(c) status quo**: the `WithHeader` discipline in every example and report that can select no rows, plus a LINT that flags plain `relation` over a list that is not statically non-empty; done when: the lint exists and names every such site in `core/examples`, `core/src/test/resources/doc` and the stdlib, each flagged site is fixed or waived with a reason, and the 500's message names the lint. Whichever is chosen, `editor/vscode/test/fixtures/panel-answers.json`'s `error-500-wpempty` case (captured from `WpEmpty.e`) and `TestRunner`'s (b7) are the two pins that move. | one of (a)/(b)/(c), chosen by the user, with its done-when as above | **(a) pr + a compiler change / unestimated; (b) pr + a playtest step / ~half a day plus the client check; (c) pr / ~a day for the lint** |
| WP-30 | **AMENDED 2026-09-23 BY Q25 (DECIDED, option (A); §13): `Sales.e` is typed, but a typed table CANNOT CARRY A FORCED `Deferred` (`TableProps.rows : [..r]`), and the preview asks inline with no threshold, so the typed `Sales` has NO deferred table and NO fixture today puts a token in the panel with props the client validates. The "BLOCKED ON Q25" text below is superseded by this: WP-30 is now **BLOCKED ON Q26 (§13, NOT ASKED YET)** -- how a TYPED report whose table arrives deferred should exist: a `Layout.Widgets.Table` contract change, a preview request that asks for deferred delivery (the opposite direction from Q24 (b), which forced INLINE and was not chosen; the user has not ruled on this one), a test-only fixture, or none until WP-30 is scheduled. That is the user's question, not this ticket's. The raw `Deferred` shape survives only in `core/src/test/resources/doc/SalesRaw.e`, the runner's untyped fixture, which the client refuses by design.** **NOT BUILT, NOT SCHEDULED. Filed 2026-09-23 by the user's Q24 decision (§13, *"Do (a) and (d) now, file (c)."*). "Deferred relations in the panel: the fetch message pair."** **WHY:** the panel's `fetchData` (`client/src/host/page.ts` `refuseDeferred`, U6) REJECTS every deferred token, and a report that asks for `Deferred` itself (`core/src/test/resources/doc/Sales.e:129`) gets a token from the preview's own render request (S1 capture `scratch-widget-preview/wp10-s1/captures.json` `ok-sales`: `"token": "d9Rfeu3GLhTiPjKEqMkpww"`, `"expires"` 5 min after the render). **WHERE THE TOKEN LIVES (READ, and one step INFERRED):** the render session keeps ONE long-lived `Runner` (`core/src/main/scala/com/clarifi/reporting/ermine/lsp/Preview.scala:1868`, `new Runner(RunnerConfig(roots = roots, run = del, scanner = sc))`, stored in the preview's `runner` field), whose `MemoryPlanCache` minted the token, and `Runner.data(token, out)` exists (`json/Runner.scala:500`) -- so the store is IN the LSP process. That a `data` call from the LSP request thread can reach it safely (the preview thread owns the session; a re-boot on restart or a roots change REPLACES the runner and drops every token; Stage A's SQLite is "opened per run ... holding nothing between renders", so a data call re-runs the plan on a fresh connection) is INFERRED and is the FIRST thing to trace. **THE DESIGN (a sketch, nothing decided):** page -> extension: an intent `{kind: "fetchData", token, id}` (or a request/response pair over `postMessage`); extension -> server: `client.sendRequest("ermine/preview/data", {token, generation})`; the answer (the relation arm's rows, or a refusal naming the token) goes back to the page, which settles the pending `fetchData` promise by `id`. `connect-src` STAYS ABSENT from the CSP: the page still opens no connection of its own. The wedge guard (WP-22) is NOT involved -- a fetch is not a render -- but **the request must carry the generation of the document that held the token, and a token from a stale generation (after a re-render or a re-boot) is REFUSED BY NAME** rather than served or silently empty. **TTL AND CAPACITY:** `bin/ermine-serve` takes `--ttl SECONDS` (default 300) and `--max-tokens N` (default 1024) (`json/ServeMain.scala:21-22`, `:72-73`, into `RunnerConfig` at `:104-105`); the preview passes NEITHER, so it runs on `RunnerConfig`'s defaults, the same 300 000 ms and 1024 (`json/Runner.scala:177-178`). Whether the preview should expose them as settings, or mirror the serve defaults silently, is this ticket's decision; an expired token must be refused by name ("expired"), as `GET /data/<token>` refuses it. **BLOCKED ON Q25 (§13), MEASURED BY Q24:** the only fixture with a `Deferred` relation is `core/src/test/resources/doc/Sales.e`, and it hands `table` a BARE relation, which the client's generated `TableProps` schema refuses before any fetch (`its props are invalid -- columns.0.column: Required`, `client/test/widgets.test.ts` `(w-sales-panel)`). That split is DELIBERATE (`docs/JSON-GUIDE.md:1090-1093` (at b7faef3a): `Sales`'s `heading`, `text` and bare-relation `table` are outside the typed widget vocabulary; the report exercises the RUNNER, not the client; `Doc/SalesReport.e` is the typed one). So no fixture today could show the message pair drawing a table; which report should carry a typed deferred table is the user's question Q25, not this ticket's. **Option (b) of Q24 -- a preview-side override forcing inline delivery -- was REJECTED by the user's choice** and is not this ticket. **TESTS:** an H-style model of the pair (page intent -> extension -> `ermine/preview/data` -> page promise), including a re-render between the ask and the answer; **a mutant that serves a STALE generation's token must die by name**; the extension's `test:preview` and the client's `npm test` green. | **BLOCKED ON Q26: a deferred table in the fixture Q26 chooses draws in the panel WITH ITS ROWS** -- NO SUCH FIXTURE EXISTS (AMENDED BY Q25, 2026-09-23: the typed `Sales`'s items table is inline, see the head of this cell) -- and a stale or expired token shows a box naming it | commit + manual / ~2 days, NOT SCHEDULED |
| WP-31 | **BUILT 2026-09-23 (client bundle only; no new `.vsix`, no extension change); NOT REVIEWED, NOT COMMITTED, NOT OBSERVED IN VS CODE. "The panel's Document / JSON toggle."** The user's words: *"On the same panel I'd like an ability to see the JSON sent to the 'frontend' by Ermine."* and *"build the JSON toggle once F3 lands."* **AS BUILT** (`client/src/host/page.ts`): a `role="toolbar"` between the banner and the paper with two buttons, **Document** and **JSON** (`aria-pressed` on the one showing; Tab/Enter/Space as for any button), hidden until the panel has a document or an error. **JSON** shows, in a `<pre>` filled with `textContent` only (never `innerHTML`), `jsonViewText(host)`: exactly `JSON.stringify(document, null, 2)` after a document (the JSON tab's `ok` case, `preview-core.js` `tabContent`), or the panel's `error` fields `{status, message, path, reason}` pretty-printed the same way after a failure. That is NOT the tab's whole `{ok:false, ...}` answer: the panel is never sent the raw answer, so `ok`/`generation`/`stale` are missing, the fields are reducer-normalised, `message` may carry the fast-mode suffix or the writers note, and a missing writers bundle shows as an `error` (status 0) even over a good document (Q28 offers forwarding the raw answer as an extension change). **VIEWER-LOCAL** (design review §2(a)): the choice is kept with `setState`/`getState` (merged), restored when the page is re-created, never posted, not in the reducer or `PageModel`; no `WebviewPanelSerializer` is registered, so a new panel or a window reload starts in Document. **NEVER A RE-RENDER:** a toggle only sets `hidden` on the document element and shows the `<pre>`; the F3 `renderFunction` call and the render-only-on-change rule are untouched; a new document while JSON shows updates the `<pre>` and renders the hidden document once. **MEASURED (headless Chromium, `scratch-widget-preview/json-toggle/IMPL-REPORT.md`):** the writers draw a `display:none` document as one-row 38px skeletons (and DataTables logs `andSelf is not a function`), so the document hidden by the JSON view is laid out OFF-STAGE (`.ermine-offstage`: invisible, zero content height -- the box is 20px tall from the paper's padding -- clipped, out of the flow); after that fix a hidden render matched a visible one (3/4/8 rows, same heights and widths; the review measured the `outerHTML` byte-identical). **Review 2026-09-23: DESIGN GREEN / IMPLEMENTATION RED on tests only (M1: a throwing `getState`/`setState` and the banner's visibility in the JSON view were untested); fixed by `(pg-json-state-throws)` and a banner assertion in `(pg-json-error)`, the reviewer's three surviving mutants now killed by name.** **Nit (N3, recorded, not changed):** the root is now `position:relative`, so it, not `body`, is the `offsetParent` of everything in the document; the F3 table geometry is unchanged, but a writers popup placed with `offsetParent`-relative arithmetic could shift by the banner-plus-toolbar height (none observed: `Sales` has no popups; E15 lists it as a failure to watch for). The `andSelf` console error is a latent WRITERS bug, recorded as F4 in `tracker/PLAYTEST-RESULTS.md`. Toolbar contrast, theme colours (`--vscode-button-*` pressed, `--vscode-editor-foreground` otherwise): 11.14:1 / 12.33:1 in the Vue Theme, 4.51:1 / 12.63:1 in a Light+ approximation; the `<pre>` 15.91:1. **TESTS:** `(pg-json-toolbar)`, `(pg-json-shows-document)`, `(pg-json-error)`, `(pg-json-render-while-json)`, `(pg-json-state)`, `(pg-json-text-only)`, `(pg-json-css)`; `(pg-json-state-throws)`; nine reverse mutants each killed by name; client `npm test` 135/135, `test:preview` 405/405. | the toggle shows the answer as the JSON tab does (within Q28's stated gap) without re-rendering, and remembers the choice per panel; OBSERVED in VS Code by checklist step E15 | commit + manual (E15) / built |
| WP-32 | **AMENDED 2026-09-24 BY WP-33: `client/scripts/generate.sh` and `check-generated.sh` are now one-line shims onto `generate.js` / `check-generated.js` (node); every `generate.sh` timing below was measured on the bash version, and the generated file's first line still names `generate.sh` (byte identity).** **S1 COMMITTED 04b975b5 (review GREEN). S2 COMMITTED 1af68aaa (review GREEN, M-1 fixed). S3 BUILT 2026-09-23 (the remainder and docs); NOT REVIEWED, NOT COMMITTED. "Typed widget schemas, generated in one call, discovered from Ermine."** The user's decisions: *"I'm pretty sure I want typed widget schemas in the typescript rather than matching runtime ermine values fallibly"*; `generate.sh` *"feels kinda clunky"*; the registry shape `type WidgetName = keyof WidgetRegistry` with `WidgetRegistry` mapping widget names to props types; and on the recursive-schema wrinkle (the generator emitted recursive schemas as `z.ZodTypeAny`, so `z.infer` was `any` and `client/src/props.ts` hand-wrote their types) *"we'll definitely want to fix the wrinkle on our end if we can"*. Designs: `scratch-widget-preview/schema-gen-design/DESIGN-A.md` (discover from the `WidgetName` values) and `DESIGN-B.md` (one JVM call, one committed file). **S1 (this stage, `json/Zod.scala`, `json/Schema.scala`, `json/SchemaMain.scala`, `bin/ermine-schema`, `Layout/Widgets.e`):** (1) every def of a recursive strongly-connected component is DECLARED (`export interface` for a record, `export type X = | .. | ..` for a union, in zod's inferred shape) and its const annotated `z.ZodType<X>`; non-recursive defs keep `z.infer`; emission order is Kahn over the components, identical to the old order on every existing output (MEASURED: regenerating `client/src/generated` changes only the recursive defs' lines; `heading.ts`, `text.ts`, `index.ts` byte-identical). (2) `bin/ermine-schema --zod M:T[=Alias] ...`: one walk (`Schema.exportMany`), each def once, short names. (3) `bin/ermine-schema --widgets Layout.Widgets`: scans the umbrella and every module under `Layout/Widgets/` for terms DECLARED there of type `Layout.Doc.WidgetName T` (re-exports skipped via `termNameOrigins`), evaluates each for its string, emits `WidgetRegistry`, `WidgetName`, `WIDGET_PROP_SCHEMAS: { [K in WidgetName]: z.ZodType<WidgetRegistry[K]> }` and `UNSUPPORTED_WIDGETS` (a `T` with no constructors: `data Unsupported` + `treeMapName` added to `Layout/Widgets.e`); the header names every scanned module (a module with no `WidgetName` term is "not a widget"), the exact command, and the sha256 of every `.e` file read (93 for the client's call). MEASURED: `bin/ermine-schema --widgets Layout.Widgets Layout.Doc:Node=DocNode Layout.Doc:Tab=DocTab Layout.Widgets.Format:CellFormat` **5.40 s and 5.66 s wall** (two runs, byte-identical output), one JVM, 35,110 B, against `client/scripts/generate.sh` **38.42 s** (13 JVMs, 14 files); 12 registry keys + `treeMap`; `tsc --noEmit --strict` (client tsconfig, zod 3.23.8) over it: 0 errors -- which proves only ONE direction: the `z.ZodType<X>` annotation guarantees the schema's output is assignable to the declaration; a WIDENED declaration is NOT caught by tsc (the review widened one three ways and tsc still passed, `scratch-widget-preview/wp32-s1-review/tsc/mut/`); the eq-probe (assignability in both directions, `wp32-s1-review/eq-probe.py`) is the check that catches it, it passes on today's output, and S2 registers it in the client gate; mutual assignability against every one of props.ts's 33 types: 31 identical both ways, the 2 differences are `DocNode`/`DocTab`, where the generated `Widget` arm has `props?: unknown` and props.ts `props: unknown` -- the generator is RIGHT and cannot emit the other (zod infers `z.unknown()` keys as optional and accepts an object without `props`; a probe with `props: unknown` fails the `z.ZodType<Layout_Doc_Node>` annotation, TS2322). Consequence until S2: `client/scripts/check-generated.sh` now reports `client/src/generated` STALE (the recursive defs' lines changed); no gate runs it. **S2 (the client, BUILT 2026-09-23; `scratch-widget-preview/wp32-s2/IMPL-REPORT.md`):** `client/scripts/generate.sh` is ONE call, `bin/ermine-schema --widgets Layout.Widgets Layout.Doc:Node=DocNode Layout.Doc:Tab=DocTab`, into ONE file `client/src/generated/widgets.ts` (the 13 per-type files and the hand-built `index.ts` deleted), its first lines the sha256 of `json/{Schema,SchemaMain,Zod}.scala`; `check-generated.sh` diffs that file (MEASURED exit 0). `client/src/props.ts` and `test/props.test.ts` DELETED; every prop type is imported from the generated module; `index.ts` re-exports it whole. `Registry = { [K in WidgetName]: Widget<WidgetRegistry[K]> }` (`dispatcher.ts`); `defaultRegistry()` is a cast-free literal of it (a missing/extra key or a wrong renderer is a tsc error, MEASURED on a copy); `Widget<P>.render` is a PROPERTY `(ctx, props: Resolved<P>) => void | Promise<void>` (a property so strict function types check it contravariantly; `void |` kept because every renderer is synchronous). **The relation positions, decided:** the generated props types keep the WIRE relation; a renderer receives `Resolved<P>` (`relation.ts`: every `kind: "deferred"` arm removed), which is what `resolveRelations` now returns; props.ts's `R` parameter is gone. `renderWidget` checks `name in WIDGET_PROP_SCHEMAS`, then a generic `dispatch<K extends WidgetName>` looks up `registry[key]` and `WIDGET_PROP_SCHEMAS[key]` at the same `K` and calls `widget.render(ctx, props)` -- `props as never` removed; the error texts unchanged. Gates: **`generated` (commit)** and the first step of **`client` (nightly)** run `client/scripts/check-fresh.js` (§11's WP-32 S2 row), which since the review's M-1 also checks a `// body sha256:` of the generated text. Known gaps (review N-2, N-4): a cast reintroduced in `dispatch` compiles and nothing catches it; `(g-wire)` is assignability-only. MEASURED: `npm test` 129/129 (bundle built, corpus present; 128 before the review's `(d-prototype-names)`), `npm run test:preview` 405/405, `tsc --noEmit --strict` clean, headless Sales render 8/4/8 rows as before. **Owed to S2/S3 by the S1 review (`scratch-widget-preview/wp32-s1-review/REVIEW.md`):** (a) the eq-probe in the client gate; (b) the `.e`-hash staleness test cannot see changes to the generator's own Scala, so the client gate must also key on `Zod.scala`/`SchemaMain.scala` (e.g. their sha256 in the header, or `check-generated.sh` in a gate); (c) TestSchema `(e3)` needs a 3-cycle case (A -> B -> C -> A; a Tarjan tree-edge mutant is uncaught today). **Decided: keep `props?: unknown`** in the generated `DocNode` -- every `WIDGET_PROP_SCHEMAS` entry is an object schema, so a missing `props` is refused one step later. **S3 (BUILT 2026-09-23; `scratch-widget-preview/wp32-s3/IMPL-REPORT.md`):** (1) TestSchema `(e3)` gains a 3-cycle `Ca -> Cb -> Cc -> Ca` reached from `Ba` (a def recursive only THROUGH the cycle): the three members declared + `z.ZodType<X>`, `Ba` and the root keep `z.infer`; the S1 review's M13 (Tarjan tree edge folding `index(w)`) now makes `Ca` non-recursive there, so the property fails under it -- REASONED and replayed on a Python replica of the Tarjan (`wp32-s3/mut/tarjan-replica.py`: old fixtures SAME under M13, the new one DIFFERENT), not run against a mutated Zod.scala (one sbt run was budgeted); MEASURED `core/testOnly *TestSchema*` PASS 31/31. (2) `Layout.Widgets.widgetNames` DELETED with the `import List` only it used (no module, test, doc or client code read it; the client test's `widgetNames` is a local); `client/src/generated/widgets.ts` regenerated (MEASURED 5.0 s wall): only the `// body sha256:` line and the `Layout/Widgets.e` sha256 line changed. (3) the dispatcher's missing-schema text is now "no props schema was generated for it -- declare `xName : WidgetName (XProps r)` in a Layout.Widgets module and run client/scripts/generate.sh", pinned by the new `(d-no-schema)` (nothing pinned the old text; §11). Wording nit, RECORDED not fixed (S3 review N-3): `(XProps r)` reads as mandatory though five of the thirteen names have no row parameter (`crosstab`, `headline`, `heading`, `text`, `treeMap`), and "a Layout.Widgets module" means the umbrella or any module under `Layout/Widgets/`; changing it means a rebundle and a re-pin. (4) docs (the S3 review's M-1 then removed three more per-type-generator passages from JSON-GUIDE: the `--zod -i` note in the zod section, the client quick-start block and its stale "60 tests" count, and the "client's equivalent" of the schema gate, now `check-fresh.js`): JSON-GUIDE's widget table rebuilt from the generated registry (12 keys + `treeMap`, each with its name term, module and props type; `headline`, `crosstab` were missing), "Adding a widget" rewritten to the two edits + one command, the zod section's per-type/`--zod` text replaced by the one-file generator and its two checks; `client/README` counts 129 (S2) / 130 (S3). MEASURED at S3: client `npm run bundle` rc 0 and `npm test` 130/130, `editor/vscode` `npm run test:preview` 405/405, `check-fresh.js` / the `generated` gate body rc 0. **The ticket, before -> after:** places a widget is named 8 (DESIGN-B §1) -> 2 CHECKED (its `WidgetName` term in Ermine, its `defaultRegistry()` line; tsc names a missing or extra key) + 1 UNCHECKED (the JSON-GUIDE widget table, documentation: nothing keeps it in sync with `WidgetRegistry`; S3 review N-4), so 3 in all; `generate.sh` 38.42 s / 13 JVMs / 14 files -> ~5 s / 1 JVM / 1 file; staleness check in no gate (`check-generated.sh`, manual) -> the `generated` gate at commit (JVM-free, hashes + body hash + exactness); `client/src/props.ts` (33 hand-written types) -> deleted, every type generated; recursive schemas `z.ZodTypeAny` -> declared and exact; `props as never` in `dispatch` -> removed, BUT a reintroduced cast still compiles and no gate or test catches it (S2 review N-2: the lint gap, RECORDED, not fixed), and `(g-wire)` stays assignability-only (N-4). Report: `scratch-widget-preview/wp32-s1/IMPL-REPORT.md`. | S1: `(e2)`-`(w2)` + `(gate)` (commit, TestSchema); S2: `generated` (commit) + `client` (nightly); S3: `(e3)` 3-cycle (commit, TestSchema), `(d-no-schema)` (nightly, `client`) | S1 done; S2 done; S3 built, review owed |
| WP-33 | **BUILT 2026-09-24; NOT REVIEWED, NOT COMMITTED. The client's generator in node, so it runs on Windows with no shell** (the user: *"we use windows at work"* / *"do the node port now, WP-17 later"*). `client/scripts/generate.js` does what `generate.sh` + `bin/ermine-schema` did, in node's stdlib only: the classpath cache `target/ermine-classpath` (rebuilt when missing, empty or older than `build.sbt` by `sbt -batch "export core/fullClasspath"`, stdout filtered as before: lines starting `[` and blank lines dropped, the last kept; one addition, a trailing CR stripped per line); java from `JAVA_HOME/bin/java` else `PATH` (`java.exe` on win32; bash used `PATH` only); `-Dermine.typeCheck=true` + `ERMINE_JAVA_OPTS` split as bash's `read -r -a` does (first line, spaces/tabs, no quote handling); `SchemaMain --widgets Layout.Widgets Layout.Doc:Node=DocNode Layout.Doc:Tab=DocTab`; the same header (sha256 by node's crypto over the same bytes), `\n` only, atomic temp+rename, the same final line. `client/scripts/check-generated.js`: regenerate to a temp dir, compare bytes, the same two messages and exit codes (on a difference it prints the first differing line, not `diff -u`). `package.json` `generate`/`check-generated` call node; the two `.sh` are one-line `sh` shims (callers and docs that name them keep working; the file's first line and `check-fresh.js`'s `regenerate: client/scripts/generate.sh`, pinned in `editor/vscode/test/preview-core.test.js`, unchanged). `scripts/gates.sh` unchanged (neither gate called the `.sh`). **MEASURED on this box (Linux):** `generate.sh` (the bash original) and `generate.js` into scratch paths: `cmp` identical, and identical to the committed `widgets.ts` (sha256 `0b5071f4...`), 5.2 s / 5.1 s; `check-generated.js` rc 0 "up to date"; both shims rc 0; `client/test/generator.test.ts` 13 tests, incl. `(gen-jvm-identity)` (one real JVM run, skips by name without java or a built classpath cache); three reverse mutants on copies each killed by name (header reordered: `(gen-header-order)`, `(gen-roundtrip)`, ...; body hash over the pre-newline bytes: `(gen-body-hash)`; `os.EOL` as newline: `(gen-lf)`, which stubs `os.EOL = "\r\n"`); the `client` gate body 143/143, `generated` gate body rc 0, `editor/vscode` `npm run test:preview` 405/405. **NOT COVERED: the win32 branch is UNVERIFIED on a Windows machine** -- only unit-tested with `process.platform` stubbed (java.exe; `sbt.bat` before `sbt.cmd` on `PATH`/`Path`, run through cmd.exe with the task quoted, since node refuses to spawn a .bat without a shell); the sbt sample in `(gen-sbt-filter)` is RECONSTRUCTED, not captured (no sbt run was budgeted). Listed under WP-17's checklist. Report: `scratch-widget-preview/wp33/IMPL-REPORT.md`. | `client` (nightly): `generator.test.ts` 13 tests | built, review owed |
| WP-34 | **BUILT 2026-09-24; NOT REVIEWED, NOT COMMITTED. Q27 option (i): the runner accepts ZERO-PARAMETER reports.** `Decode.reportSignature` answers `(Option[Type], Type)`: a non-function is `(None, t)`; `Runner.compileOnce` accepts it when `resultKind(t)` is `Node` or `Fetch Node` (`Report.paramTy`/`decoder` are `None`) and otherwise refuses *"... is not a report: a report is a Layout.Doc.Node, a Layout.Fetch.Fetch Layout.Doc.Node, or a function to one, not T"*; `render` applies nothing (the value is the first step); `decode` accepts `{}`/`null`/absent and 400s anything else at `$.params` naming the keys; `paramSchema` answers `Runner.NoParameters` = `{"parameters": false}` (§4). Polymorphic and type-variable refusals unchanged. Extension 0.1.16: `schemaOutcome.noParameters`, `firstPickResult.noParameters`, `isNoParametersAnswer`, `noParametersNotice`, `holdsParamsNotice`; `extension.js` `noParametersPicks` (forgotten with `firstPickTried`), the held "no params file" line, and a `noParameters` arm in `firstPickSchemaAndWrite`, `refreshSchemaFile` and `writeSkeletonNow`. Tests: `TestRunner` `(b3z)` (SalesReport `{}`/absent/`null` ok with scorecard/table/axisChart/pieChart; a key and `3` -> 400 at `$.params`; schema marker; a zero-parameter `Fetch Node`), `(b3)`'s `RgNotFn` now `report : Int` -> the new text; `TestDecode` updated; node: 7 new tests incl. a glue pin and two model mutants. MEASURED on one `bin/ermine-lsp` boot: reports lists `report : Node`, render ok, schema marker, Sales's schema and `ok-sales` byte-equal to the committed fixtures. Report: `scratch-widget-preview/wp34/IMPL-REPORT.md`. **REVIEW 2026-09-24 (`scratch-widget-preview/wp34-review/REVIEW.md`): DESIGN GREEN, IMPLEMENTATION RED on M1 (the command model lacked the `noParameters` arm) and M2 (this row); both fixed in round 2.** OPEN NITS, not fixed: **N1** stale `Runner.scala` prose (`BadRequest` doc `:44-46`, class doc `:221-224` "`Params -> Result`", `Request` doc `:76-77` "a report with no parameters (`Maybe`-only, or a `Json` parameter)"), left because the pr gate was running on the Scala; **N2** `(b3z)`'s zero-parameter `Fetch Node` is `done (...)`, so the `Scan` arm of a zero-parameter report is covered by argument (it is the SAME `evaluate` the function case scans through), not by a test -- a `scan ... (\rows -> done ...)` fixture would close it, and was not added because the Scala was frozen for the gate; **N4** no test pins that a listed `Node`/`Fetch Node` binding's params file is NOT called an orphan (the review's mutant R11 survives; one `orphanParamsFiles` table row would pin it); **N5** a pick learned as zero-parameter stays so until a re-pick, a restart or a recovery: if the report gains a parameter meanwhile, renders send `{}` (a 400 naming the missing field) and no "write one" line appears until a re-pick; Write Params Skeleton asks fresh (said in README 0.1.16). | `(b3z)`, `(b3)` (`RgNotFn` = `report : Int`) and `TestDecode` green in `core/test`; the 8 WP-34 node tests in `preview-core.test.js` (the marker table, the hold table, the first pick, the control with parameters, the D8 refresh, two model mutants, the glue pin) plus round 2's Write Params Skeleton test green; E2's `SalesReport` sub-step and E10 run in VS Code with 0.1.16 | `TestRunner`/`TestDecode` under `suites` (**pr**); node under `extension` (**commit**) / built, review owed |
| WP-35 | **RENDER OBSERVABILITY. SERVER HALF BUILT 2026-09-24/25 (DB programme S2b, the server-trace role; `tracker/db/OBSERVABILITY.md`); NOT REVIEWED, NOT COMMITTED.** A per-render `RenderTrace` (`core/.../reporting/RenderTrace.scala`) travels explicitly Preview -> `Runner` (new `renderText`/`render` overloads) -> `Interp` (`WriteConfig.trace`, default `Off`), and by a thread-local installed only around `Runner.drive`'s one `Run[DB].run` into `SqlExecution.scanQuery` (SQL text, `execMs`, a `nanoTime` pair around each `rs.next()`) and `SqlScanner.sequenceSql` (setup statements timed when they RUN); every other caller, `bin/ermine-serve` included, gets `Off` and captures nothing. `trace` is APPENDED LAST to every render answer from a job that ran (§4 row), tied to its job (a field of `Render`, answered once) and carrying the answer's generation; the watchdog's stuck answer carries a PARTIAL trace naming the running relation and SQL; a late job's trace goes to the log only. Phases are disjoint and sum to `wallMs` (`scan` and `other` ATTRIBUTED, the rest MEASURED); `dbMs + otherMs == wallMs` by construction. **Evidence:** `TestRenderTrace` 8/8 (unit properties on an injected clock + one preview-path property: trace last on ok/failed/stuck, partial names `$.fetch[1]`, displaced carries none); `TestRenderTraceLive` (env-gated, added to the `db` gate) 1/1 at tier s: seven twins, every rerunnable query's `rowsRead` == the JDBC row count of its own SQL, dialect mssql, database ErmineSales, SQLite twin dialect sqlite. **Cost** (interleaved A/B, tier m, 5 rounds): +0.2% / +1.5% median wall with the per-row clock, inside the noise, so `fetchMs` stays and there is no setting. **Found:** `groupBy ... (sumBy ...)` is a `Mem` aggregated by Ermine: `DbFetchTopN` reads 388 rows at tier s (7,701 at m) to hand the report 8 (12). The attributed phase the panel text below calls `encode` is named **`scan`** on the wire. **PANEL HALF BUILT 2026-09-24 (DB programme S2d, the panel role); NOT REVIEWED, NOT COMMITTED. The render trace, shown: "we want to see the queries generated, the results scanned, time spent in db vs elsewhere ... valuing minimal configuration".** Design `scratch-widget-preview/db/DESIGN-OBSERVABILITY.md` §2-§4, answers Q-O1..Q-O6 all (a) (`tracker/db/DECISIONS.md`; NO setting). The server half (S2b, `trace` appended LAST to every render answer) is server-trace's. **Extension** (`editor/vscode/src/preview-core.js`, fenced `S2d trace (panel)`): `traceOf(answer, joined)` normalises the answer's `trace` (only listed keys are copied, so no url/user/password can reach the panel; SQL capped at 16 KiB UTF-8 at a character boundary with `\n-- [ermine: truncated, N more bytes]` when the server did not cap it); `panelView.trace` = `traceOf(answers.last)`, the last CURRENT answer's, ok or failed; a TENTH panel kind `{kind: "trace", trace, generation}` after the answer pair, so every resync snapshot carries it; the status bar's idle text gains `· 412 ms` and its tooltip `render 412 ms: db 310 ms, 3 queries, 1,676 rows (sales-mssql)`; ONE output-channel line per answered render, e.g. `preview: render 110 ok 58 ms (server 51 ms: db 11 ms, 3 queries, 19 rows; scan 31 ms, session 4.5 ms, other 4.8 ms) sales-mssql / ErmineSales`, `... FAILED 500 at $.fetch[2] after 1 query (db 12 ms): <message>`, `... STUCK after 60,012 ms (server 60,001 ms so far: ...; still running $.fetch[1] for 59,800 ms)`; no SQL in the channel. **Panel** (`client/src/host/index.ts`, `page.ts`): the reducer keeps the trace opaque and drops it on a `render` of another generation; a third toolbar view **Document | JSON | Trace**, viewer-local like JSON: headline, connection line, a phase bar in CSS widths (db first, `other` last, widths sum to 100%), a per-query table (#, relation, delivery, rows, scanned, db, total, dialect, share), each SQL in a `<details>` `<pre>` set by textContent with a **Copy** button (clipboard, else the text is selected and the log says so), notes (deferred, "the database returned 388 rows; Ermine reduced them to 8", over threshold, failed query), and the partial state of a stuck render naming the running query and its SQL. **Evidence:** `npm run test:preview` 451/451 (with the extension role's connect-core; 14 S2d tests incl. glue pins); client `npm run bundle && npm test` 156 (155 pass, 1 skipped: no java; 12 new S2d tests, one over server-trace's MEASURED DbFetchTopN trace); reverse mutants all killed by name (a displaced render's line, the good document's trace instead of the failed answer's, SQL via innerHTML, phase widths swapped, trace not cleared on a new generation); headless screenshots `scratch-widget-preview/db/panel-trace/panel-trace-{dark,light}.png` (+ `-stuck-`, `-narrow` 390 px), drawn from server-trace's MEASURED DbFetchTopN trace (tracker/db/OBSERVABILITY.md §4; the stuck shot is hand-made), every Trace text element >= 5.19:1 MEASURED in both themes. **Open:** `ermine-host.js` is 61 KB of the bundle test's 64 KiB zod-sentinel cap. **S2f BUILT 2026-09-25 (the trace as Ermine data; NOT REVIEWED, NOT COMMITTED; extension 0.1.18, not packaged).** `Layout.Trace` (the §4 keys as types; `Spread Json` for the keyword keys `table`/`database`), `Doc/TraceReport.e` (`report : Trace -> Node`), **Ermine: Save Render Trace** / **Ermine: Preview Render Trace** (the current answer's trace to `.ermine/preview/Doc.TraceReport/report.params.json` through `applyWritePlan`, modal before a replace, then the ordinary pick via `commitPick`). TestRunner `-f trace` 2/2, `npm run test:preview` 476/476, 4 reverse mutants killed by name; headless `scratch-widget-preview/db/s2f/trace-report-dark.png`. **Found and FIXED S2f-1 (amends WP-11 D6):** every chart drew as a black box in the panel (the writers draw Highcharts in styled mode, and its rules live only in `javafxwriter.css`, which D6 had left out as "JavaFX's"). The page now links it as the FOURTH sheet, with three page-CSS counters (body colour, `.timeseries` position, a 320 px chart height over the writers' window-sized div); tables unchanged (MEASURED). `tracker/db/OBSERVABILITY.md` §11. |
| WP-36 | **BUILT 2026-09-25 (client bundle only; no new `.vsix`); NOT REVIEWED, NOT COMMITTED, NOT OBSERVED IN VS CODE. "A `tabbed` document's other tabs keep one placeholder row."** **SYMPTOM (MEASURED headless, the real panel over a served `doc/DbFetchTabs.e` document at tier s, 8 tabs):** tab 0 shows 160 `tbody tr`, tabs 1..7 show 1 (the skeleton's `...` row) before AND after each tab is clicked, although the JSON carries every tab's rows (`scratch-widget-preview/db/wp36/run-before.log`). **MECHANISM (READ):** `tableWidget` appends a skeleton and calls `runTabular` (`client/src/legacy.ts:365`); the writers' table callback builds its DataTable ONLY `if (isVisible(document.getElementById(tid)))` (`ermine-writers/writers/js/ermine/tables.js:1375-1376`) and registers itself in `updateCallbacks` (`tables.js:1598`), which only `runResize` walks (`ermine-writers/writers/js/ermine-htmlwriter.js:2888`, exported `:3568`, and on window `resize` debounced 100 ms, `:3521`). `renderTabbed` renders every tab eagerly with tabs 1..n `hidden`, and its click handler only toggled classes and `hidden`: nothing re-ran the callbacks. **FIX:** one generic "content shown" hook, `contentShown(env, shown)` (`client/src/dispatcher.ts:61`), called by the tab click after un-hiding a panel that WAS hidden (`client/src/dispatcher.ts:256`; clicking the showing tab does nothing). It calls `env.onShown` if a host set one (new optional `RenderEnv` field), else `env.htmlwriter.runResize()` when the writers export it (they do: `typeof window.ermine_htmlwriter.runResize` is `function` in the shipped `htmlwriter.js`, MEASURED), else dispatches a window `resize` event (the writers' 100 ms debounce). `HtmlWriter` gains optional `runResize?(): void` (`client/src/legacy.ts:117`) and `invalidateRegion?(uid)` (`:122`). Any future hiding container calls the same function. **COST (READ):** `runResize` runs EVERY registered callback, but a table already built takes the `isInit` branch (`tables.js:1377-1378`), which only resizes (`doResizeTables`); a hidden table's callback does nothing; so a switch builds the newly shown tables once and resizes the rest, and charts' callbacks `setSize` (`ermine-htmlwriter.js:2326-2333`). Acceptable per click. A writers-side alternative (NOT done, vendored): have `runTabular` watch its element with an `IntersectionObserver`/`ResizeObserver` and build on first visibility, which would fix every host and not only our tabs. **EVIDENCE:** client `(d-tab-shown)` in `client/test/dispatcher.test.ts` (runResize exactly once per switch to a hidden tab, none for the showing tab, a window `resize` without the export, `onShown` handed the un-hidden panel); the reverse mutant (the call removed) fails it at `the switch to tab two runs runResize exactly once`. `npm test` 160 tests: 159 pass / 0 fail / 1 skipped; `npm run test:preview` 476/476; `check-generated` up to date. Headless after (`scratch-widget-preview/db/wp36/run-after.log`, `probe-tabs-check.js`): 160, 64, 84, 108, 82, 90, 110, 78 `tbody tr` per tab after its click (each twice the tab's JSON rows: two `dataTable`s per table, MEASURED); screenshot `scratch-widget-preview/db/wp36/tabs-japan-dark.png`. Manual: WP-7 checklist E16, `tracker/db/DOGFOOD.md` §14. **REVIEW MF-1 (FIXED 2026-09-25, `scratch-widget-preview/db/REVIEW-WP36.md`):** ids restarted at `ermine_1` on every render and nothing trimmed the writers' page-global `updateCallbacks` (`ermine-htmlwriter.js:61`), so after a re-render the first click on a never-visited tab ran the OLD render's callback, which found the NEW table by id and drew the old rows (MEASURED by the reviewer: 96 `tbody tr` in 3 tables of old dates where 10 in 2 were expected, `wp36/review-rerender.log`). Fix, both halves: (1) ids are unique per render: the dispatcher's default prefix is `ermine_r<N>` (`client/src/dispatcher.ts:155`) and the page passes `ermine_p<token>` (`client/src/host/page.ts:955`), so a stale callback's `getElementById` is null and `isVisible(null)` is falsy (READ: `utils.js:50`; the pie and style-box callbacks call `sizeToHighestParent` first, a jQuery no-op on an empty set); (2) the page retires the replaced render's prefix with the writers' exported `invalidateRegion` (`client/src/host/page.ts:931`, and again if a superseded render finishes late), which deletes only prefix-keyed bookkeeping and calls `trimUpdateCallbacksPfx` (READ: `ermine-htmlwriter.js:3024-3095`), so the list no longer grows with every render. `RenderResult` carries `idPrefix`. Tests: `(d-rerender-stale)` (a fake of the writers' by-id callback list: after render B, a click builds B's 1 row only) and `(pg-retire-prefix)` (distinct prefixes; the second render retires the first's, clearing the document retires the last); each fails on its reverse mutant (default prefix back to `ermine`; the `retire(drawnPrefix)` call removed). Headless after: `wp36/review-rerender-after.log` tab 1 = 10 `tbody tr` / 2 tables with render B's dates, in both the plain and the click-first mode. **NOT DONE:** not observed in a VS Code webview; the first tab's column widths look narrow (the `Units` header clipped) at HEAD too, not WP-36's. |
| WP-37 | **IN PROGRESS 2026-09-25 (branch `typed-columns`, worktree `ermine-scala-wt-typedcols`, base `74405fea`); NOT REVIEWED, NOT COMMITTED. "Typed widget columns."** The programme, its decisions D1-D9 (the user, 2026-09-25), the design as type-checked, the roles and the as-built log are in `tracker/TYPED-COLUMNS.md`; the fleet's board is `scratch-widget-preview/typedcols/BOARD.md`. **WHAT:** a widget prop never names a relation column by a `String` in the authoring API (D1). A table column is a `Column r` built from a `Field` -- `col`, `numCol`, `dateCol` -- whose `Has r h` constraint is settled where the columns meet the relation, so a column the relation does not have is a TYPE error; `textColumn`, `numberColumn` and the string `simpleTable` are REMOVED (D2). Sorts and row groups are marked on the column (`sortAsc`/`sortDesc`/`groupRows`) and lowered to the wire indices (D5). Fixed column roles of the other widgets become named `Field` slots with a partition constraint (D4). `...Unsafe` modules keep a `rawColumn : String -> Column r` escape hatch nothing in the stdlib or fixtures imports (D7). **WHAT DOES NOT CHANGE:** the wire -- `TableColumn`/`TableProps`, the schema exporter, `client/src/generated/widgets.ts`, the bundle (D3) -- and every migrated report's document JSON, byte for byte (D8; the before/after dump in `TYPED-COLUMNS.md` §3). **NOT IN SCOPE:** shrinking the wire to the used columns (D9, WP-38). User docs: `docs/JSON-GUIDE.md` §8 "Table columns". |
| WP-38 | **NOT BUILT, NOT SCHEDULED. Filed 2026-09-25 by WP-37's D9. "Send only the columns a widget uses."** After WP-37 a widget's columns are `Field`s whose membership in the relation row is proved (`Has r h`), but the relation still travels WHOLE: a table showing two of a relation's six columns sends all six in `rows` (inline or behind a token). The option: lower the used fields to a projection of the relation (an unsafe row, since the projected row is computed from a runtime column list rather than written as a type) before encoding, so the wire carries only what some widget reads. **OPEN QUESTIONS (none answered):** (1) one relation shared by several widgets (`Doc/SalesReport.e`'s four widgets over one `sales`) -- project to the union, or per widget; (2) whether projecting away a key column can change the row count (it would if duplicate rows collapse; NOT CHECKED), which would change `rowCount` and what a widget shows; (3) the deferred-token path, whose cache holds the relation as scanned. Out of WP-37 by D9 (`tracker/TYPED-COLUMNS.md` §0). |
| F-1 (= NEW-3) | **FIXED 2026-09-26; NOT REVIEWED, NOT COMMITTED. "`groupBy {region} (sumBy amount)` over a `table` is aggregated in Ermine."** **SYMPTOM (MEASURED, render trace + `sys.dm_exec_query_stats`, tier s):** `DbFetchTopN`'s `$.fetch[1]` read 388 rows for 8 region totals (7,701 for 12 at tier m); the fixture header called it "the SQL aggregate". **MECHANISM (READ):** `Relation.groupBy` does `asMem r` unconditionally because its per-group function is arbitrary Ermine (`core/src/main/resources/modules/Relation.e:130-132`), so the SQL is a plain `select ... from [sales] order by region`. The engine already had the pushed form: `Relation.Aggregate.aggregateByGroup` (`core/src/main/resources/modules/Relation/Aggregate.e:50-52`) lowers to the relational `AggregateByGroup` (`core/src/main/scala/com/clarifi/reporting/ermine/session/Lib.scala:630-640`), compiled to GROUP BY by `SqlScanner.scala:892-895`. **FIX:** `byRegion = aggregateByGroup_Aggregate (sum_Aggregate amount) {region} amount sales` (target field = `amount`, so the row and the wire are unchanged) in `doc/FetchTopN.e`, `doc/DbFetchTopN.e`, `doc/FetchFragments.e`, `doc/DbFetchFragments.e`; headers corrected; rule in `docs/JSON-GUIDE.md` §9 ("SQLite for local play, and a real database"). The ~30 `groupBy k (sumBy f)` in `core/examples/` (in-memory literals, several teaching `groupBy` itself) were NOT rewritten. **EVIDENCE:** 18 documents (TopN `keep` 0/1/2/3/8/20, Fragments x3 params, in-memory and DB twins) byte-identical before/after (`scratch-widget-preview/db/f1/{before,after}`, `diff -r` empty); rows returned 388 -> 8, SQL now `select (SUM(..amount)) [amount], (..region) [region] from [sales] .. group by ..region order by SUM(..amount) desc`; TestRunner `(fx4-sql)` pins GROUP BY + SUM in the SQL of both twins' `$.fetch[1]` and rowsRead == rows == 4 in-memory (fails on the reverse mutant); TestRenderTrace (t1) pin moved 8 -> 4. `doc/trace-sample.json` kept (predates F-1, noted in `Doc/TraceReport.e`). | `(fx4-sql)` green; OBSERVABILITY.md §9 item 1 | S / done |

## History rewrite, 2026-09-24

GitHub refused every push of this repository (HTTP 500 from `receive-pack`, even for the root commit alone): 21 commits from 2015-2018 at the root of every branch had `author`/`committer` lines without an email (`ClariFI Ermine Team`, `McGraw Hill Financial`, `amita_shukla`, and `dmitry.kolobov@spglobal.com` with no brackets), which git tolerated and GitHub's server-side fsck does not. The history was rewritten through a `fast-export` / `fast-import` round trip that repaired those 42 lines and nothing else (`git filter-repo` could not parse them): every commit's hash changed, no tree changed (verified for all 77 branch tips), 59 tags carried over, strict `fsck` clean. The four branches `default`, `scala3-migration`, `json-encode` and `backport-2.11` were pushed from the rewritten repository, then the local repository was migrated by moving refs only (138: 77 branches, 59 tags, 2 detached worktree HEADs), with every pre-rewrite ref saved under `refs/backup/pre-rewrite/`; no working tree, index or uncommitted edit moved. The old-to-new commit map is `tracker/COMMIT-MAP-2026-09-24.txt` (1236 rows); every commit hash cited in this branch's TRACKED TEXT FILES was rewritten from it (Markdown, the gate-audit data tables and logs, scripts, the TLA+ files; two passes, the second after an independent review found the first covered Markdown only and missed one 40-character hash; in all 845 citation occurrences (382 in the first pass, 463 in the second)), with two deliberate exceptions: the map itself and the captured test fixture `editor/vscode/test/fixtures/panel-answers.json`, which records what a real server answered and is left byte-for-byte. Hashes named in commit MESSAGES before this date refer to the pre-rewrite history and must be read through the map. Other branches' documents still cite pre-rewrite hashes. Rollback: `scratch-widget-preview/rewrite/migrate-local.sh restore` (ephemeral script; the backup refs are what matters).
