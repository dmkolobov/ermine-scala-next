# JSON widget playground: edit a widget, see it rendered, inside VS Code

> **STATUS: WP-1, WP-2, WP-3, WP-4, WP-5 (STAGES A, B AND C) AND WP-7 (WITH Q15's SERVER-SIDE
> `reason` KEY) ARE BUILT. WP-6's COOPERATIVE CANCEL WAS BUILT (stage 1, `0ee08425`), MEASURED
> (stage 2, `92c974be`) AND IS NOW REMOVED FROM THE TREE (WP-24, 2026-09-20, BY THE USER'S
> DECISION). EVERYTHING ELSE IS DESIGN ONLY.**
> **WP-24, 2026-09-20 (evening), THE USER'S DECISION.** On the in-evaluator cancel: *"That
> sounds super sketchy."* They chose instead to ACCEPT the wedge and contain it in the CALLER,
> and then confirmed that the cancel instrumentation inside general Ermine evaluation is to be
> REMOVED. So `Runtime.scala`, `lsp/Preview.scala`, `session/Lib.scala` and `session/Session.scala`
> are restored to their `325c3d09` content (byte for byte, MEASURED by blob hash) and
> `scalacheck-binding/src/main/scala/TestPreviewCancel.scala` is deleted. **NOTHING OF THE
> MECHANISM IS IN THE TREE**: no `Cancelled`, no `cancelTarget`/`cancelWhy`, no `swhnf` head
> check, no five catch arms, no `ermine.preview.cancelOnTimeout`, no two-phase watchdog. **THE
> WATCHDOG IS AGAIN EXACTLY WHAT IT WAS AT `325c3d09`: ONE PHASE -- `fire`
> (`Preview.scala:2069`) claims the job under `lock` and does the stuck mark, the `seq` mint, the
> drain and the notification INLINE. (`fireStuck` is not a method in this tree: `0ee08425` minted
> that name when it split `fire` in two, and the split went with it.)**
> **WHAT REPLACES IT IS WP-22 -- the wedge guard and caller-owned recovery, EXTENSION ONLY --
> WHICH IS NOT BUILT.** Q13 is RE-OPENED AND RE-DECIDED (§13). Everything below about WP-6 is
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
> `ermine-scala-wt-widget-preview`, forked from `json-encode` at `a0830244`; this document is
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
| **Cooperative cancel -- WP-6 STAGE 1: BUILT 2026-09-20 (`0ee08425`), MEASURED (stage 2, `92c974be`), REMOVED 2026-09-20 (WP-24)** | **NONE OF THIS IS IN THE TREE. It was removed by WP-24 on 2026-09-20 on the user's decision (§13, Q13), and everything after this paragraph is the DESIGN RECORD of a mechanism that was built and measured -- not a description of the code.** WHAT THE WATCHDOG DOES NOW is exactly what it did at `325c3d09`, the commit before stage 1: ONE PHASE. `fire` (`private def fire(job: Answering, epoch: Long, why: String)`, `Preview.scala:2069`) claims the job under `lock` and does all of it INLINE -- sets `stuck`/`stuckJob`, mints `stuckSeq`, drains the queue, answers the wedged request and every drained job with `stuck: true`, and sends the `window/showMessage` and `ermine/preview/stuck {stuck: true}` pair of the row above. **There is no `fireStuck` in this tree**: `0ee08425` minted that name when it split `fire` into a two-phase watchdog, and the name went out with the split (MEASURED: `git show 325c3d09:...Preview.scala \| grep -c fireStuck` = 0). NOTHING interrupts an evaluation: the honest promise is this table's own -- a runaway evaluation blocks no LSP request until it exhausts the heap cap, then the server exits and the client restarts it -- and §4's client-contract rule (5) is WITHDRAWN with the mechanism. The recovery that follows that restart is what WP-22 guards, and WP-22 is NOT BUILT. **AS BUILT, and it departs from this row's earlier text in four places the design review found; §14's WP-6 row carries the reasons.** ONE GLOBAL `Runtime.cancelTarget: Thread` beside `Runtime.cancelWhy: Cancelled`, both `@volatile` and both `private[Runtime]`. **THE WRITE ORDER IS ENFORCED, not asked of the caller** (S1/S2 of the stage 1 review): the fields are `private[Runtime]` and every write goes through `Runtime.armCancel(target, why)` -- reason first, target second, and it REFUSES (answering `false`) when another thread's arming is live, which a caller must then say out loud and fall back from -- or `Runtime.disarmCancel(target)`, which clears only that target's own arming, in the reverse order. `swhnf` still reads the field DIRECTLY: a method with a monitor in it is exactly what must not be on every force. And the check is at the **HEAD** of `Runtime.swhnf`, unconditionally, on every call: `val ct = cancelTarget; if ((ct ne null) && (ct eq Thread.currentThread)) throw cancelWhy`. **NOT a per-thread context and NOT `Thread.interrupt`**: `Preview.takeJob` reads an `InterruptedException` as "stop", `ForeignClasses.Recoverable` and the backends react to an interrupt, third-party code may clear the flag, and a JDBC driver may abort its connection on one. **NOT inside `swhnf`'s `case old =>` branch**, which the review proposed as the cheaper placement and then FALSIFIED: `json/Encode.scala`'s `spine` walks a list with `while (true) { Runtime.swhnf(cur) ... }`, and on a CYCLIC list (`repeat a = t where t = a :: t`, `List.e:29-30`) every thunk it re-reads is already `Evaluated`, so that branch is never entered again and a check there would never fire. `Cancelled` is a **`ControlThrowable`**: stackless, EXCLUDED by `NonFatal` so `swhnf`'s own capture does not memoise it as a `Bottom`, and NOT an `Error` (`ForeignClasses.Recoverable` swallows an arbitrary `Error` into a failed reflective lookup, `ForeignClasses.scala:26` is the arm that lets a `ControlThrowable` through). **FIVE CATCHES THAT WOULD HAVE SWALLOWED IT** gained `case c: Cancelled => throw c` as their first arm, and without them the cancel silently does not work: `Prim.apply` and `Box.apply` (`Runtime.scala`), `IO.Unsafe.eval` (`session/Lib.scala`, which would hand the cancel to the Ermine program's own error continuation), the foreign invoke (`session/Session.scala`, which re-wraps what it catches as a `RuntimeException` -- which IS `NonFatal`, so `swhnf` would capture and memoise it) and -- **the fifth, FOUND BY THE STAGE 1 REVIEW (DM-3) and not by the build** -- `Bottom.thrown` (`Runtime.scala`). A `Bottom`'s body is usually a bare `throw`, but two in `core` FORCE (`session/Lib.scala`'s stdlib `error`, `Bottom(error(s.extract[String]))`, and its `pipe#` failure, `Bottom(... + rel.whnf)`), and `thrown` is what `json/Encode.scala`, `json/Doc.scala`, `Pretty.ppRuntime` and `Bottom.toString` all call -- so a cancel raised by that forcing was CAUGHT AND RETURNED AS A VALUE: a bogus error node inside a 200, or a job that "succeeded" with the cancel's own text in its document. Bounded (the next `swhnf` re-throws), and now closed. **THE WATCHDOG IS TWO-PHASE.** At `timeoutMillis`, PHASE 1 arms the flag and does NOTHING else: no answer, no stuck mark, no queue drain, no notification. If the cancel TAKES (phase 2a), `Preview.runJob` answers 500 with the timed-out text reworded ("evaluation did not finish after Ns, so it was CANCELLED ..."), **without** §4's `stuck` marker, then **DISCARDS THE RENDER SESSION UNCONDITIONALLY** -- the escape leaves WHITEHOLED thunks with this thread still in their `pending` queue, and a later same-thread force of one would memoise `Bottom(sys.error("infinite loop detected"))` -- and clears the flag. If it has NOT taken after `graceMillis` (1000 ms, a constant with a test seam, not a user setting), PHASE 2b **CLEARS THE FLAG FIRST** and then does exactly what the watchdog did before WP-6: claim, stuck, `stuckJob`, `seq`, drain, `stuckRefusal`, `window/showMessage`, `{stuck: true}` -- and Q10's recovery applies to it unchanged. **WHAT THE CANCEL CANNOT STOP, because none of it reaches `swhnf`**: a loop inside ONE primitive, the relational row loop (`relational/package.scala`'s `driveLeftId`), a JDBC scan, and a thread parked in `SessionTask`'s `future.get` or in a thunk's `latch.await`. Phase 2b is the fallback for every one of them, which is why it is not optional. **A USER `$/cancelRequest` STILL DOES NOT INTERRUPT** -- `Preview.cancel` is untouched (queued: removed and `-32800`; in flight: marked, answer replaced). **THE FLAG IS CLEARED IN FIVE PLACES**, and the list is the review's: (1) **BEFORE THE ANSWER on the cancel path** -- `runJob`'s `Cancelled` arm does `clearCancel` then `discardSession` then `finish`, because the answer says the preview is serving renders again and the session was rebuilt, and both must be TRUE when it goes on the wire (DM-1: with the clear only in the `finally`, a client could read the answer while the flag still named the preview thread; MEASURED by the review as two reds in three runs); (2) phase 2b, before it falls back; (3) `runJob`'s `finally`, for EVERY job, as the idempotent catch-all; (4) `Preview.cancelTimer`, which both `shutdown` and the death drain call -- **DM-2: the fourth path, and the one no other clear reaches**, because a `shutdown()` inside the grace cancels the timer so phase 2b never runs while the preview thread is wedged and reaches neither the `finally` nor `takeJob`; harmless in the shipped server, but in the UNFORKED test JVM one stale target makes every later `swhnf` in every suite take the slow side of the branch for the life of the process; (5) `Preview.takeJob`, which logs loudly and clears if it ever finds one armed. A slow scan that legitimately finishes after the fire must not die at its next force.

**WITHDRAWN 2026-09-20 BY WP-24, BECAUSE IT WAS A CONSEQUENCE OF THE CANCEL AND THERE IS NO CANCEL.** With stage 1 removed, no render is ever cancelled, so nothing unwinds the preview thread's `swhnf` chain deliberately and no thunk is left `Whitehole` with an uncounted `CountDownLatch` that way; WP-14's row no longer points here. **THE ONE RESIDUE, DERIVED BY READING (`Runtime.scala:229-231` at `325c3d09`) AND UNVERIFIED**: `swhnf`'s own `catch { case NonFatal(e) => r = Bottom(throw e) }` captures every ORDINARY failure and writes a `Bottom` back, so an ordinary error leaks no latch. Only a throwable that `NonFatal` EXCLUDES can escape the chain the same way -- a `VirtualMachineError`, `ThreadDeath`, an `InterruptedException`, a `LinkageError` or a `ControlThrowable` -- and with `Cancelled` gone nothing on the preview's own path raises one deliberately. **`InterruptedException` is out for a second, independent reason**: the only blocking call in `swhnf` is `t.latch.await` (`Runtime.scala:222`), which sits in the `Whitehole` branch OUTSIDE the `try`, so an interrupt there would indeed escape -- but NOTHING IN THE TREE INTERRUPTS THE PREVIEW THREAD. `Preview` only ever READS an interrupt, in `takeJob`, where it means "stop" and is re-asserted (`Preview.scala:852`, `catch { case _: InterruptedException => stopping = true; Thread.currentThread.interrupt() }`). So the one that is actually reachable is the `OutOfMemoryError` that ends the process anyway. What follows is the record as it was written: **THE CONVERSE CASE, DERIVED BY READING AND UNVERIFIED (S3 of the stage 1 review).** The cancel unwinds the PREVIEW thread's chain without `writeback`, so every thunk it passed is left `Whitehole` **with its `CountDownLatch` never counted down**. `discardSession` throws the `Runner` away but releases no latch. So ANOTHER thread that later reaches one of those thunks -- a scan's chunk producer, `SessionTask`'s pool -- takes `swhnf`'s `Whitehole` branch, finds itself absent from `pending`, and parks on `t.latch.await` **for ever**. They are daemon threads, so the JVM can still exit; what leaks is one thread and whatever its queue retains, per cancelled render that had a concurrent scan. Not reachable in stage 1 (the stage A backend opens one connection per run and the properties run no concurrent scan), which is why it is unverified; WP-13/WP-14 are where it becomes reachable, and WP-14's row carries it. Cost: one volatile load and one predictable null-branch per force, in the binary whether the switch is on or off. **`perf-bench.sh` CANNOT MEASURE IT** -- it is a typechecker bench. §11's Instruments section carries the instrument that DID, `tracker/tools/eval-bench.sh`, and its figures (BUILT AND RUN 2026-09-20, write-up reviewed and corrected): nothing distinguishable on an ordinary build-and-fold workload, and on the `swhnf`-densest one a suggested but NOT established ~5 %, which belongs to the whole stage 1 commit and not to this row's load alone. Stage 3, flipping the default, is the user's -- and the flip adds no PER-FORCE cost, because the check is in the binary either way, but it is not behaviourally free: §14(d) and (f) are what it turns on (the unconditional session discard on a taken cancel, the two-phase watchdog, and `isFatal`'s exception, which is sound only while that discard is unconditional) |
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
| `ermine/render` | request | `{uri, binding, params, roots, generation}` -> `{ok: true, document, generation, stale?}` or `{ok: false, status, message, path?, reason?, generation, stuck?}` | `uri` -> module via `Resident.moduleUnder(cfg.roots, path)`; a file that cannot be PLACED under any root is a **404 whose message says why** (Q5, decided 2026-09-20): it is not a `.e` file, it cannot be read, its module header does not parse, or its module name is deeper than the directories above it. A readable `.e` file whose header parses is always under its OWN inferred root (§2.4), so the 404 is unreachable for it -- which is why the old text, "not under a module root", was true of nothing. **THE 400 AND 404 TEXTS NAME THE FILE AND NEVER A DIRECTORY** (Q5's convention; the 409 below is the one exception and says why). `roots` are the absolute `ermine.preview.roots` (§2.4). Delivery is always inline, buffered, no threshold (`Runner.scala:72-80`): **no `data` field on this wire**. `status`/`message`/`path` are `RunError`'s (`Runner.scala:25-65`: `BadRequest` 400 at `:47`, `NotFound` 404 at `:51`, `Failed` 500 at `:55`): 400 with a JSON path for a bad param or a binding that is not a report (`:466-470`, `:472-476`), 404 for module or binding (`:447`, with the request's binding in the text), 500 for load, eval, scan, write, and for a document over the size cap (§2.3). **`reason` (Q15, DECIDED by the user 2026-09-20)** is a machine-readable string beside `status`, present on EXACTLY the failures `Preview`'s OWN FRONT HALF decides -- the ones about PLACING the picked file, before `Runner` is asked -- and on nothing else. The vocabulary is CLOSED and STABLE (it is wire contract; `Preview.Reason`): `not-a-file-uri` (400, the URI names no file), `not-ermine-source`, `unreadable`, `no-module-header`, `header-deeper-than-path`, `not-placed` (404, the last being the general fallback, unreachable as built) and `shadowed` (409). **A 404 FROM THE `Runner` -- no such module, no such binding -- CARRIES NO `reason` KEY, AND THAT ABSENCE IS THE DISCRIMINATOR**: it is what lets WP-7's Q11 trigger tell a placement 404 from a `Runner` 404 without matching the message text, and it is why the bad-`roots` 400 (the CLIENT's error, not a placement decision) carries none either. An OLD server sends none anywhere, so a client reading `reason` degrades to "never trigger" rather than to triggering wrongly. `json/Runner.scala` and `RunError` are untouched: `bin/ermine-serve` is unchanged. **409 (Q7, decided 2026-09-20)** for a SHADOWED PICK: the final root chain resolves the picked file's module name to a different file, so neither this render nor a schema may use it, and nothing is loaded. **THE 409 IS THE ONE TEXT THAT PRINTS A PATH**, and the orchestrator's decision on the apparent contradiction with the sentence above is recorded here: Q5's file-name-only convention governs the 400 and 404 texts; the 409 prints the SHADOWING file's path and the root it sits under because that is the only useful thing it can say (the picked file is still named by its name alone -- the request supplied its URI), and rule A5 (§8.1) covers **URLs, hosts and passwords**, not a source path under a directory the client or the server configured as a module root. 409 costs no new vocabulary: `Preview.failure` takes a status NUMBER and `RunError`, which the HTTP server shares, is not on this path. The message never carries a JDBC URL (§8, rule A5). **`stuck: true` (Q8, decided 2026-09-20)** is present on EXACTLY the failures that mean §2.5's WEDGE -- the refusal `render` sends while stuck, the watchdog's own answer, and the answers its queue drain sends -- and on NOTHING ELSE, in particular not on the job crash handler's 500, which is a report that ran and failed. The `-32800` paths (a displaced render, a cancelled one, the shutdown drain, and the watchdog's answer to a request that had been CANCELLED) are JSON-RPC ERRORS with no result object, so they carry no marker and the client learns the state from `ermine/preview/stuck` instead. Answered through `onRequestDeferred` from the preview thread |
| `ermine/preview/reports` | request | `{uri}` -> `{module, reports: [{binding, type}]}` or `{error}` | §3.2; dispatch thread; a lookup, or one cold check for an unopened file |
| `ermine/preview/invalidated` | notification, server -> client | `{modules}` | §3 step 5 |
| `ermine/preview/stuck` | notification, server -> client | `{stuck: true \| false, message, seq}` | **Q8, decided 2026-09-20.** `true` from the watchdog's `fire` (TIMER thread), `false` from Q10's recovery (PREVIEW thread), each **beside** a `window/showMessage` and never instead of one -- the standard message is what any LSP client shows, this row is what a BANNER can hold. Both through `notify`, never `ask` (§2.3), outside the queue's monitor, guarded, scrubbed. WP-7's panel reads it, and the **Ermine: Restart Language Server** button is the panel's: the LSP shape that carries actions (`window/showMessageRequest`) is a REQUEST whose answer names the chosen action TO THE SERVER, and the protocol gives a server no way to make the client run the client-side `ermine.restartServer` (*external*, unverified here). **THE CLIENT CONTRACT, four rules (IM-1 of the Q8-Q12 review):** (1) `seq` is a monotonic counter minted in the SAME locked step that flips the state, so a client KEEPS THE HIGHEST `seq` IT HAS SEEN AND IGNORES ANYTHING LOWER -- the two edges are sent by different threads with nothing ordering them, and a collision really can put the `false` on the wire before the `true`. **`seq` IS PER-PROCESS AND RESTARTS AT 1**, so the client RESETS its high-water mark when the language client goes **Stopped -> Running** (§5's own row for that transition): a restart is the remedy the watchdog's message names, and a client that kept the old mark across one would ignore the fresh server's `{stuck: true, seq: 1}` for the life of its session (DD-2 of the second review); (2) this notification is **AUTHORITATIVE** for the stuck state; (3) the `"stuck": true` marker on an ANSWER is **per-request**, not a state: it says why THAT request was refused, and one stale stuck refusal may legitimately arrive after a clear (it was decided before it); (4) the `window/showMessage` that accompanies each edge is **advisory** and may arrive in either order relative to it -- it carries no `seq` and a client must not derive state from it. **(5) WITHDRAWN 2026-09-20 BY WP-24, WITH THE MECHANISM THAT MOTIVATED IT: A CLIENT GETS ONE RISING EDGE PER WATCHDOG INCIDENT AGAIN**, and rules (1)-(4) are the whole contract, exactly as they were at `325c3d09`. A client may still be shut down and restarted by ITSELF after `{stuck: true}` -- that is WP-22's caller-owned recovery, which is NOT BUILT and changes nothing on this wire. The withdrawn rule is kept as the record: **(5) WP-6 STAGE 1 (2026-09-20), REMOVED: A CANCEL THAT SUCCEEDS SENT NO PAIR AT ALL.** With `ermine.preview.cancelOnTimeout` on, the watchdog's first deadline cancels the evaluation, and the incident ends with one 500 and a rebuilt render session: no `{stuck: true}`, no `{stuck: false}`, and no `"stuck": true` on the answer. So **a client must not expect one rising edge per watchdog incident**, and must not read a missing falling edge as a wedge. The pair is sent only when the cancel did NOT take within the grace and phase 2b fell back to this row's own behaviour (§2.5) |
| `ermine/schema` | request, extended | `{uri, binding, roots}` -> the schema, or `{error, reason?, stuck?}`, alongside `type`/`name` | **with a `binding` key the request is a preview-queue job** answered from the render session (§6); the `type`/`name` forms stay on the resident (`Schema.scala:807-816`). **Q7, decided 2026-09-20**: the binding form carries the same three keys a render identifies its report by, and resolves it through the SAME function, so a schema and a render share one session in either order. Its `{error}` texts are a render's reasons word for word -- Q5's "cannot read `<name>`", "no module header could be read from `<name>`", "not an Ermine source file: `<name>`", the 409 shadow text -- scrubbed, file names only, **and since Q15 with the same machine-readable `reason` beside `error`, under the same rule: only the front half's own failures carry one**. `{module, binding}` is GONE: a request with `binding` and no `uri` is `{error}` naming the key. **CONSEQUENCE FOR THE EXTENSION (WP-7/WP-8)**: because a schema now computes the root set the same way, a schema whose `roots` DIFFER from the last render's DISCARDS that session and boots another, exactly as a render with different roots does (§2.4). The extension must send the SAME `roots` on both, for the same picked report. **`stuck: true` (Q8) sits BESIDE `error`** on the two refusals that mean the wedge -- the one `schema` sends while stuck, and the one the watchdog's queue drain sends -- and on no other `{error}` |
| `ermine/preview/connect` | request | `{profile: {id, dialect, driver, url, user?, scanner, settings}, password?}` -> `{ok: true, host}` or `{ok: false, class: "auth" \| "driver" \| "connect", kept, message}` | §8. The **body is never logged** (WP-1). Absent `user` means `DriverManager.getConnection(url)` (the local SQLite case) |
| `ermine/preview/disconnect` | request | `{}` -> `{ok: true}` | closes the held connection and discards the `Runner` (§7.2); the next render answers `{ok: false, status: 503, message: "not connected"}` until the extension connects again |
| `ermine/preview/disconnected` | notification, server -> client | `{reason}` | after a recycle or a failed scan that closed the connection; the extension reconnects (§7.2) |
| `$/cancelRequest` | notification | `{id}` | §2.5 |
| `window/workDoneProgress/create`, `$/progress` | request then notifications, server -> client | the LSP shapes (*external*) | §2.5 boot progress; the `create` from the dispatch thread through `ask`, the `$/progress` from the preview thread through `notify` |

`Rpc.scala` changes (WP-1), all in one file:

| Line (at a04f179c) | Change |
|---|---|
| `Wire.receive` logs the raw body before the method is known (`:318`) | the incoming log line moves to `Server.handle` after `Json.parse` (`:442-452`) and is `">> <method> [redacted]"` for methods in `Rpc.Redacted = Set("ermine/preview/connect")`; the unparseable branch (`:449`) keeps logging the parser's error only. That error never carries body text: the parser echoes at most one character (`Rpc.scala:121`) or a number token (`:144`), never a string. **Corrected at WP-1:** that was false as mined -- at a04f179c two escape errors (`Rpc.scala:166`, `:169`) quoted up to four characters from INSIDE a string literal (`bad \u escape 'ZZZZ'`, `bad escape '\q'`). WP-1 removed both echoes, leaving the offset, and pins the claim with a property (`TestLspRobustness`, A group): every quoted fragment is at most one character or a number token, and no two-character UPPER-CASE window of the input appears anywhere in the error. The second half is a marker check, not a check over every substring: every fixed word in a parser message is lower-case, so an upper-case pair can only have been echoed, while searching for arbitrary two-character substrings would falsify a sound parser on a collision with its own English ("of" inside "offset").  The property's own comment carries the alphabet argument |
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

| Item | Decision | Note |
|---|---|---|
| Node build | `tsc -p tsconfig.json` and `npm test` untouched (`client/package.json:12`, `:16`) | webpack is additive |
| Bundle | `entry: src/index.ts`, `ts-loader`, `target: 'web'`, `library: {name: 'ErmineClient', type: 'window'}`, output `client/dist/browser/ermine-client.js`, under the already-ignored `client/dist/` (`.gitignore:11`) | the host script reads `window.ErmineClient.parseDocument` etc. |
| `devtool` | `'source-map'` explicitly | *external*: `mode: 'development'` defaults to `eval`, which a webview CSP without `unsafe-eval` blocks silently |
| Host page CSP | `default-src 'none'; script-src ${cspSource}; style-src ${cspSource} 'unsafe-inline'; img-src ${cspSource} data:` | the legacy renderers inject styles |
| Legacy renderers | a second `<script>` from a second `localResourceRoots` entry at the `ermine-writers` checkout's built bundle; the host passes the global into `render`'s env, read as `ctx.env.htmlwriter` (`client/src/legacy.ts:327-333`) | without it `scorecard`/`headline`/`crosstab` render and `table`/`drilldownTable`/charts show the dispatcher's error box, the designed "unsupported" behaviour (`JSON-GUIDE.md:1648-1652`) |
| **The writers global** | **open (Q1)**: `client/src/index.ts:5` documents `window.htmlwriter`; the writers entry assigns `window.ermine_htmlwriter` (`../ermine-writers/writers/js/htmlwriter.js:11`) and the object `legacy.ts` types is `const htmlwriter = {}` (`ermine-htmlwriter.js:45`). Never observed in a real browser here | WP-11 |
| Host-page logic | the extension <-> webview message protocol (`render`, `error`, `stale`, `stuck`, `reloadBundle`, `unsaved`, `switching`, `offline`) is the only new logic on the client side; its state transition is a pure `applyMessage(state, msg)` in `client/src/host/`, built by the same webpack config and run under `node --test` beside `client/test/harness.ts` (`client/package.json:16`) | the DOM output of `parseDocument -> render` is already covered in jsdom; scroll, `retainContextWhenHidden` and panel lifetime are VS Code's behaviour, not ours; `@vscode/test-electron` downloads VS Code and is impossible offline (§10) |
| Initial state | before the first render: "Pick a report: **Ermine: Preview Report...**"; while a render runs: a thin progress bar, the last document kept | |
| Errors | `{ok: false}` -> a banner with `status`, `message`, `path`; the last good document stays below, dimmed. A load failure shows there **and**, for the same file, in Problems through the resident's own diagnostics (`Main.scala:188`) -- unless fast mode is on, when the banner adds "fast mode is on: type errors are not shown in Problems" (`config().get("fastMode")`, the same read as `extension.js:69-71`) and the preview status item carries the "(fast)" suffix | |
| Unsaved | a non-blocking hint "unsaved: Chart.e" in the banner area whenever a `.e` document in the workspace is dirty (`workspace.textDocuments.some(d => d.isDirty && d.languageId === "ermine")`, *external*): the preview follows saves (§2.4) and that must be visible, not documented. Rendering is never refused for it: a buffer closed without saving would leave nothing dirty and the hole open, and the two-file loop (widget module + renderer) is mid-edit as a normal state | |
| Stale | `stale: true` -> the banner "re-rendering" until the next answer | §2.5 |
| **Stuck (Q8, decided 2026-09-20)** | `stuck: true` on an answer, or `ermine/preview/stuck {stuck: true}`, -> a banner carrying the message and **the Restart Language Server button** (`ermine.restartServer`, the extension's own command): this is where resolution A4 puts it, because the LSP cannot make a client run a client-side command from a `window/showMessageRequest` answer (*external*). `ermine/preview/stuck {stuck: false}` (Q10: the wedged evaluation came back) clears the banner, and its message asks for a re-render -- every `invalidated` of the stuck interval was dropped unsent, so the panel's document may be behind the files. The standard `window/showMessage` arrives beside each of them and needs no panel. **THE `seq` IS PER-PROCESS**: the panel keeps the highest it has seen and ignores lower ones, and RESETS that mark on the **Stopped -> Running** transition in the row below, because a restarted server counts from 1 again (§4's rule (1), DD-2) | §2.5, §13 Q8/Q10 |
| Switching | during a profile or roots switch (§7.2): the last document dimmed under "switching to `<id>`" | |
| Server stopped | on the client's `Stopped` state (`onDidChangeState`, *external*): banner "server stopped -- last document kept", status "Ermine: preview offline", the document dimmed. On `Running`: the reconnect flow of §7.2 and a re-send of the last render. Scroll and drilldown are lost, as for a bundle change (a hot restart, not a hot reload). By construction every input the loop needs -- picked (file, binding), params path, active profile id, last document, `generation` -- lives in the extension; the server holds nothing across a restart except the database | |
| Lifetime | `retainContextWhenHidden: true` (*external*; costs memory, keeps drilldown state); a bundle change re-sets `webview.html` and **loses** scroll and drilldown state -- accepted | |
| Bundle reload | `createFileSystemWatcher` on `client/dist/browser/ermine-client.js`, debounced ~200 ms (unverified atomicity of webpack's write), cache-busting query on the script URI, re-send the last document | |
| Bundle checklist | once per bundle-config change, by hand (jsdom cannot answer it): no console error under the CSP, `window.ErmineClient.parseDocument` present, `table` renders through the writers global | WP-9 / WP-10 done-when |
| Two windows | each window spawns its own `bin/ermine-lsp` (`extension.js:179`), hence its own preview session and its own held connection: two boots' memory (capped, §2.2) and two sets of `##` tables (§7) | stated, not solved |
| Multi-root | the server reads every folder's stdlib (`Main.scala:106-117`); the extension uses `folders[0]` for the server path only (`extension.js:43-46`). Profiles are user-scope (§8), so no folder question arises there; `ermine.preview.roots` and the params directory are per the picked report's workspace folder (§2.4, §6) | |

**WP-9 / WP-10 / WP-11: FINDINGS OF A READ-ONLY DESIGN REVIEW, 2026-09-20. NOTHING IS DECIDED HERE
AND NOTHING WAS BUILT.** The rows above stand; these are findings against them. **Nobody has run a
browser or VS Code on this branch**, so every claim about rendering, CSP enforcement or webview
behaviour below is UNOBSERVED; the labels are the review's own.

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
| U2 | dates in the skeleton | **today**, the only rule that always decodes -- **with the done-when reworded**: `Sales`'s rows span 2026-01-05..2026-03-17 (`Sales.e:84-93`), so a skeleton written today selects NO rows and the first document is EMPTY until the dates are edited. The params file is opened for editing right after it is written |
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
| **S2 send it** | read the params at send time, strip the top-level `$schema`, cap, send; watcher + `onDidSaveTextDocument` through the existing `scheduleRender` coalescer; invalid JSON = a refusal in the tab, NOT a render | a hand-written params file renders; editing and saving re-renders in place; a corrupted file shows the parse error and does not render |
| **S3 first pick writes** | the first `ermine/schema` client: the ordering rule (no file -> schema first; file present -> render first), the pick-staleness guard, skeleton write (NEVER overwrite), `.schema.json` write-if-different, the two `.gitignore` files | on a clean checkout, picking `Sales.report` writes both files and renders; a second pick does not rewrite the params file; `git status` shows the params file only |
| **S4 edges** | orphan message, non-object params roots (`Int`, an all-nullary enum, `Maybe`), a pick with no module, a non-identifier binding, the credential warning, `fx.schema` wiring on recovery/restart, the preview-only note for the docs | each edge has a unit test or a named log line; the WP-7 checklist gains §A |

**§A -- WHAT STAYS FOR THE MANUAL CHECKLIST (all of it unobserved):** a wrong key squiggles; key
completion offers `fromDay`/`toDay`/`onlyRegion`/`orderBy`; `orderBy` completes to
`ByDay`/`ByAmount`/`ByUnits` (the `$ref`->`$defs` hop, D3's go/no-go); **the `$schema` line itself
is not squiggled** (D1); saving re-renders in place; an external edit (`git checkout`) re-renders;
editing the params type updates `report.schema.json` and the editor picks it up without a window
reload; a renamed binding shows "no params for"; `git status` shows the params file and not the
schema; a report outside every workspace folder writes no file and says so once; a skeleton whose
dates match no row gives an empty document or a 500.

**WP-8 EXPORTS `paramsFingerprint` FOR WP-22**, over the CANONICAL JSON ACTUALLY SENT (stable key
order, after the `$schema` strip) rather than the file's text, so that re-formatting a params file
does not clear the wedge mark. If WP-22 lands first its fingerprint is a constant (`{}`); WP-8
makes it real.

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
(`DB.scala:106-116`; `JSON-GUIDE.md:1577-1583`). For a scanning report (§0) the documented
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
| Recycling is the **extension's** reconnect | after N renders or T idle minutes (defaults in WP-14, Q2), on **Ermine: Disconnect Database**, or after a scan closes the connection, the server closes it and sends `ermine/preview/disconnected {reason}`; the extension sends a fresh `connect`. **AMENDED 2026-09-20 (§8's amendment block): this row used to say "the extension, which has `SecretStorage`" -- there is no secret store.** What the extension puts in that fresh `connect` is the open half of §8's UNCONFIRMED proposal: either a password it still holds in the extension host's MEMORY for the window's lifetime (if the user confirms that proposal), in which case the reconnect stays automatic, or -- the stricter variant, equally open -- a password it must PROMPT for again, in which case the reconnect becomes a click. Nothing here decides which. The server never reconnects on its own |
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
| `build.sbt` ships mysql-connector-j, jTDS and sqlite-jdbc only, so `--dialect mssql` fails at `Class.forName` today | MINED, not run | `build.sbt:111-113`; `DB.scala:107`; `JSON-GUIDE.md:1587-1589` |
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

**PROPOSED BY THE ORCHESTRATOR, NOT YET CONFIRMED BY THE USER -- the lifetime of the prompted
password.** Held in the EXTENSION HOST'S MEMORY for the lifetime of the editor window: never on
disk, never sent to a webview, and not retained by the server after the connect. FORGOTTEN on
window close or reload, on **Ermine: Disconnect Database**, and after a failed login (A8). The
reason to hold it at all is WP-14's EXTENSION-DRIVEN RECONNECT, which must keep working after a
server restart -- and the Q13 re-decision makes a server restart ROUTINE rather than rare. **The
stricter variant, also open**: prompt on every connect and hold nothing, at the price that a
reconnect stops being automatic and becomes a click. Neither is built; both are one function in
`extension.js` and unobserved.

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
| Every launcher is bash | `bin/ermine`, `bin/ermine-lsp`, `bin/ermine-schema`, `bin/ermine-serve`; the default server path is `bin/ermine-lsp` under the first folder (`package.json:43-47`; `extension.js:49-55`). **Windows gets native `.cmd`/PowerShell wrappers** (`bin/ermine-lsp.cmd` at least, doing what `bin/ermine-lsp:12-74` does: the classpath cache, `-Dermine.lsp.log`, the heap cap of §2.2 -- `-Xmx` and `-XX:+ExitOnOutOfMemoryError`, `:20-63` since WP-5 stage C -- and `ERMINE_JAVA_OPTS`); `resolveServer` picks the wrapper when `process.platform === "win32"` (*external*). No WSL |
| Consequences of a Windows host | **AMENDED 2026-09-20: the `SecretStorage` half of this row FALLS AWAY -- the user dropped the secret store (§8's amendment), so there is nothing at rest for a host credential store to back, and the prompted password never leaves the extension host's memory.** What remains host-dependent: the JVM truststore is the Windows JDK's (`Windows-ROOT`, Q3, §7.3). Portability note, not a live question: on a Linux host `SecretStorage` is backed by the keyring (*external*) and the truststore by that JDK's `cacerts` |

## 11. Testing

`tracker/GATE-POLICY.md` is superseded (`:1-3`) by `docs/gate-policy.md`: tiers `commit`
(compile, corpus, lsp; ~2.5 min, budget 3 min), `pr` (+ `suites` = full `core/test`, lean;
20 min), `nightly`; "a new gate enters at `nightly` and moves up on evidence"
(`docs/gate-policy.md:52-56`, `:87-92`); environment-dependent checks are instruments, not
gates (`:28-29`, `:98-101`). No gate below exceeds 20 min, so nothing needs the user's
approval under `:91`. Each WP done-when in §14 names its tier.

| Layer | Where | Properties (each is a WP done-when) | Tier | Cost per run |
|---|---|---|---|---|
| Wire / dispatcher | `TestLspRobustness` A-group | a deferred handler answering from another thread still yields "every message answered in order, once" -- the synchronous answers keep their positions and every deferred one is answered exactly once, in any order; two threads calling `send` concurrently produce frames a `Wire` reads back intact; a body for a redacted method never appears in the captured log, an unredacted one does, and neither a JSON array nor a non-string `method` logs a body either; a parse error quotes at most one character of the input or a number token, and no two-character upper-case window of the input appears in it (the marker check of §4), with the same claim re-checked through `Server.handle` on an unparseable frame carrying a secret; `$/cancelRequest` reaches a registered handler while other `$/` notifications are dropped with no answer and no `ignoring notification` line (they do get the ordinary `">>"` line, like every other incoming message) | `suites` (**pr**): `scalacheck-binding/src/main/scala` is in core's test sources (`build.sbt:88-90`) | seconds |
| Registration flag | group D in `TestLspRobustness` | check a buffer whose `data Heading` gained a field; `DataConDecl.forConstructor(Global("Sales", "Heading"))` still has four fields | **pr** | seconds |
| Render session | group D, under `residentLock` as B/C are (`:34`, `:307`), and -- since **ROBUST-3** (2026-09-20, `tracker/LSP-STALENESS.md`) -- under `ErmineFixture.literalLock` for the whole body of every property that RENDERS, through the `renderingD` wrapper | render `Sales.report`; mutate the report file; `invalidate`; render again: the document differs. Mutate a **widget** module the report imports: the report is in the invalidated set. Render a module whose evaluation throws: the resident still answers a check (`Resident.checkFile`, `Resident.scala:401`) and the next render works. A `$/cancelRequest` for a queued render answers `-32800` and the queue is empty. `ermine/schema {uri, binding: "report", roots}` from the queue equals `exportNamed("Sales", "Query")` under the render env, on the session the render before it booted. `ermine/preview/reports` on `Sales.e` lists `report : Query -> Node` and nothing else. **(Q4)** A report whose LOAD failed is a 500 "does not load"; the file is fixed; `invalidate` of its path sends `ermine/preview/invalidated` NAMING it and the next render is `{ok:true}` with the fixed content. **(Q5)** The 404 for a file that cannot be placed names the cause -- "cannot read Gone.e" for a file that is not there, "no module header could be read from WpBadHeader.e" for one whose header does not parse. **(Q6)** Two fresh reports in two DIFFERENT directories, both named as `roots` on every request, render first / second / first again, all `ok:true`, and the session boots exactly ONCE across the three (counted from `Preview`'s own "render session booted" log line; each of the three properties runs on a bench of ITS OWN, not the group's shared one, because these requests move the root set and the shared bench's must never move). A report under NO configured root still renders and DOES re-boot, which is §2.4's zero configuration unchanged. One module NAME under two configured roots: the PICKED file is the one rendered, whichever root it is in. **(Q7)** A schema asked FIRST, on a fresh bench, boots the session and answers the params schema of a workspace report (`$id`, `$ref`, the four properties, the three required), and the render that follows answers `ok` -- ONE boot across both, counted from `Preview`'s own log line. `ermine/schema` with a `binding` and NO `uri` is an `{error}` naming the key, while the `type` and `name` forms still answer `ermine:Ord/Ordering` from the resident. A pick SHADOWED by a resident `moduleRoots` entry (the bench is given one of its own, holding a copy of the same module name) is `{ok:false, status: 409}` with no document, naming the picked file, the shadowing file and the root; the schema answers `{error}` with the SAME text; and a non-shadowed module on that bench still renders its own contents with no second boot. A pick that reaches its root THROUGH A SYMLINK, while the resident root holds the real spelling, still renders its own contents -- the `sameFile` tolerance of the review's must-fix -- or SKIPS LOUDLY with a `collect` label where the platform refuses symbolic links. The 400/404 property also pins the two bad-`roots` SHAPES the first cut dropped silently: `roots` that is not an array, and an entry that is not a string, are each a 400 naming `roots` and what kind of value it was, and the same refusal reaches `ermine/schema` in its `{error}` shape (that property now holds `residentLock` and forces the bench's `docs`: its Q7 half asks `ermine/schema` over the WIRE, and the handler exists only once `Definitions.install` has run -- see the row's note below). **(Q8, decided 2026-09-20)** The watchdog property now also asserts `"stuck": true` on the fired answer and on a later REFUSED render, an `ermine/preview/stuck {stuck: true}` notification, and -- the conjunct that catches the shared-`refusal` bug -- that a render SERVED after the recovery whose evaluation crashes carries NO `stuck` key; the crash-handler property carries the same negative conjunct on its own 500; the watchdog-drain and cancelled-then-wedged properties assert the marker on the drained schema's `{error}` and its absence from the `-32800` (which has no `result` at all). **(Q10)** The watchdog property now releases the wedged job and waits for `ermine/preview/stuck {stuck: false}` and an INFO `window/showMessage` asking for a re-render, then proves the state really ended by getting a THIRD render SERVED; the cancelled-then-wedged property does the same after its -32800. A property OF ITS OWN pins the other side of Q10(b): a wedged job released by throwing an `OutOfMemoryError` leaves the preview stuck, logs no "no longer stuck", and announces nothing -- read off a recording `notify` and a log after the preview thread has been JOINED. **(Q9)** One property, no bench and no boot, over `applySettings`: `0` sets the field and logs once; `3601` and an ill-typed `timeoutSeconds` are each refused out loud and leave the field alone. **(DM-1, as corrected by DD-1)** A property of its own, and the only one in the group that pays TWO boots, because nothing cheaper is a real witness (`discardSession` on a preview that never booted does nothing and logs nothing). FOUR scenarios on ONE booted bench, in an order that keeps the boot count unambiguous: **(a) the CONTROL** -- a wedged render that comes back `ok: true` must NOT discard and must NOT re-boot, and its recovery message must not claim a discard; **(b) THE REACHABLE CASE** -- a wedged render of `WpBoom` comes back with a 500 **by returning normally** (`threw` is false), and the recovery must log the discard and say so in its message; **(c)** the next render then really does boot (`boots` 1 -> 2, counted from `Preview`'s own log line); **(d)** a wedge released by THROWING discards too, at no extra boot. (b) is what the first cut got wrong and what the throwing scenario alone could never have caught. **WHAT THE PROPERTY OBSERVES, stated because the name suggests more than it checks**: it observes the DISCARD firing -- `Preview`'s own log line, and the extra boot in (c) that proves the session really went -- and NOT a poisoned binding being re-thrown from a session that survived. The memoised `Bottom` of DM-1 is the REASON for the discard and is nowhere asserted here; a property that pinned it would have to render a second report that shares a thunk with the wedged one and watch it fail, which is a fixture this group does not have. **(DM-2)** The `isFatal` property runs its scenario TWICE, once released by an `OutOfMemoryError` and once by a `ControlThrowable` -- the second is not an `Error` and is exactly what `isInstanceOf[Error]` alone missed. **(IM-1)** A property STAGES the notification collision rather than racing for it: the bench's `notify` parks the TIMER thread inside the `{stuck:true}` send until the preview thread has sent `{stuck:false}`, asserts the arrival order really was `false, true` (or the property is vacuous), and then asserts that the HIGHEST `seq` says `stuck:false` | **pr**; group D boots a render session, seconds each, MEASURED in WP-5 and kept under 60 s total or the suite is split. **MEASURED with Q7's four properties (2026-09-20), three runs**: **18.2 s** for `core/testOnly ...TestLspRobustness` ALONE; **25.7 s** and **46.7 s** for two runs of the same tree with `TestRunner` and `TestSchema` in the same JVM. The spread is CONTENTION, not Q7. **THOSE Q7 FIGURES WERE WRONG AND ARE CORRECTED HERE (2026-09-20, against the run's own log)**: the sentence said "the four Q7 properties cost 7.4 s of it (shadowed pick 1.6 s, two spellings 5.8 s, schema-first and the missing-uri case the rest)", which cannot be read at all -- 1.6 + 5.8 is already 7.4, leaving nothing for "the rest". The log says **shadowed pick 1.6 s, two spellings 5.8 s, schema-first 3.4 s, the missing uri 0.0 s = 10.8 s**, not 7.4 s. Meanwhile one pre-existing property, `ermine/schema {binding}`, took 16.3 s in that run against a fraction of that alone -- it holds `residentLock` while the other two suites take the process-wide `Runner.evalLock`, which is where the spread comes from. **RE-MEASURED 2026-09-20 WITH THE Q8/Q9/Q10 PROPERTIES**, four runs: group D was **34.7 s** for `core/testOnly ...TestLspRobustness` ALONE (61 properties, 47 s of suite wall time; that figure PREDATES the `docs`-ordering fix above and the review's own properties), and **34.4 s**, **18.6 s**, **37.5 s** on three runs with `TestRunner` and `TestSchema` in the same JVM (128 properties, 79 s / 59 s / 66 s). The **18.6-37.5 s** spread across runs of the SAME tree is the contention this row already describes and nothing else. The five properties added across the batch and its review cost **5.7 s between them**: `watchdog, the stuck state and the recovery` 0.3 s, `Q10: isFatal keeps the stuck state` 0.3 s, `Q9: applySettings on timeoutSeconds` 0.0 s, `IM-1: the stuck notification's seq` 0.3 s -- none of those four boots a render session -- and **`DM-1: the poisoned session is discarded` 4.8 s, which is two boots and is the whole of the increase**. **RE-MEASURED AGAIN AFTER THE BATCH'S TWO REVIEWS (2026-09-20)**, which added the DD-1, DM-2 and IM-1 properties: **23.2 s** and **40.4 s** for `core/testOnly ...TestLspRobustness` ALONE on two runs (63 properties, 46 s and 56 s of suite wall time). The 17 s between those two runs is not the new properties -- `DD-1: the poisoned session is discarded` cost 4.9 s in both -- it is **the RESIDENT's own ~13 s boot landing on whichever property forces it first**, which in the 40.4 s run was the pre-existing `Q7: the missing uri, and the resident's forms` (16.4 s there, 0.0 s when something else has already paid it). That is the same scheduling effect this row describes above, now with a named instance. *The combined figure for the final tree -- with `TestRunner` and `TestSchema` in the same JVM -- is reported to the orchestrator and deliberately NOT written here: it can only be known after the run that must be the last thing to touch this tree, and a tracker edit after a green run would break that rule.* **The 45 s line is not crossed on any run, and THE SPLIT IS THEREFORE NOT TAKEN.** **THE MARGIN, stated so that the next batch knows what it is spending**: the highest group-D figure measured is 40.4 s, so there is about **5 s** to the 45 s line -- one property that boots a render session (DD-1 costs 4.9 s for its two boots) or one property that lands on the resident's own ~13 s boot is enough to cross it, and the second of those is a scheduling accident rather than a cost. It remains available if a later batch crosses it again: either group D moves to a suite class of its own, or it is cut into the queue/watchdog properties and the root-set ones (Q6 and Q7, each already on a bench of its own). **ONE PRE-EXISTING ORDERING HAZARD WAS SURFACED AND FIXED** while measuring this: the 400/404 property asks `ermine/schema` over the wire (Q7 gave it that conjunct) but never forced the bench's lazy `docs`, so a schedule that ran it before any property that does answered `-32601 unknown method: ermine/schema`; it now forces `docs` under `residentLock` like the three properties that already did. The 60 s ceiling in this row is not breached on any run. **THE GROUP-D LOCK RULE, ADDED BY ROBUST-3 (2026-09-20) AFTER A `pr` GATE RED** (tree key `cae6f47f42cc3a6cf0c99b0c46e61f1a1d4ff890`, `suites` FAIL, `Failed: Total 1284, Failed 2, Errors 0`, 863 s; the whole ticket is in `tracker/LSP-STALENESS.md`): the old convention -- *`literalLock` for properties whose VERDICT reads `Session.depCache`* -- was wrong by omission, because **EVERY RENDER AND EVERY SCHEMA READS THAT CACHE**. `Preview.placeAndSession` runs §2.5's mtime scan at the head of both (`lsp/Preview.scala:1339` -> `Runner.invalidateStale`, `json/Runner.scala:599`), and a foreign `Session.depCache.clear()` landing PART WAY THROUGH that walk yields a dirty set that is not closed under importers, which `Session.scrub` then turns into dangling names and a 500 inside a stdlib file (READ; the product half is WP-25). **THE RULE NOW**: a group-D property that can reach `doRender` / `doSchema` / `doInvalidate` holds `literalLock` for its whole body via `renderingD`, which forces `bench` -- and, with `withResident = true`, `resident` -- BEFORE taking the lock, keeping `previewLock` -> `residentLock` -> `literalLock`; `Bench.bootMillis` takes it for the group's one warm-up render, the one render `renderingD` cannot wrap. **20 of the 30 group-D `timedD` properties are wrapped**; the 9 that are not never build a `Runner` (every job they post is held or thrown in `beforeJob`, or there is no job at all: the five watchdog / stuck properties, `Q9`, `the schema job at shutdown`, `daemon and shutdown`, and `Q7: the missing uri`, whose binding form is refused by `SchemaRequest.parse` on the dispatch thread and whose other two forms are answered by the resident), and `ermine/preview/reports` keeps `withDepCache`, which is strictly stronger. **RE-MEASURED ON THE FIXED TREE (2026-09-20), THREE RUNS**: group D **30.3 s** and **29.4 s** for `core/testOnly ...TestLspRobustness` ALONE (63 properties; the first invocation was 13 s of `core/Test/compile` plus **65 s** of `testOnly`, the second **83 s** of `testOnly` with nothing to compile), and **31.1 s** with the four CLEARING suites in the same JVM (`*TestLspRobustness *TestInterfaceRoundTrip *TestInterfaceKey *TestNamedFields *TestInterfaceConcreteRow`, 84 properties, 169 s) -- **all green; the three figures are within a second of each other, which is INFERRED (one mixed run against two solo runs) to mean the serialisation costs group D little -- a row that itself attributes an 18-40 s spread to contention cannot carry a one-second claim as MEASURED**. The boot is 2.3-2.9 s of it. The longest wrapped property, which is the BOUND ON HOW LONG THE FOUR CLEARING SUITES CAN BE HELD OFF, is `DD-1: the poisoned session is discarded` at **4.7-5.6 s** (it pays two render-session boots), then `Q6: zero configuration` 4.4-4.7 s. **THE RED RUN'S 23.7 s FOR `Q7: the shadowed pick` IS NOT THAT BOUND**: that figure is the resident's own ~13 s boot landing on whichever property forces it first -- the effect this row already names -- and `withResident` now forces it OUTSIDE the lock; the same property costs 1.9-2.7 s on these runs. **A GREEN RUN CANNOT PROVE A TIMING RACE FIXED**: the argument is the lock, by reading, and these runs only say the fix did not break anything and did not cost the cap | seconds to a minute |
| **Cooperative cancel (WP-6 stage 1) -- REMOVED 2026-09-20 (WP-24)** | `TestPreviewCancel.scala` -- **DELETED by WP-24**; while it existed it was a suite of its own, sharing group D's harness through `PreviewSupport` | **`TestPreviewCancel.scala` IS DELETED AND ITS TEN PROPERTIES NO LONGER RUN; the mechanism they covered is not in the tree. The row is kept as the record of what was tested, and the two things it left behind are KEPT: `PreviewSupport.scala` (the shared harness, which `TestLspRobustness` imports) and `TestLspRobustness`'s own one-line order-dependence fix. AS IT STOOD:** **`TestPreviewCancel`, a suite OF ITS OWN**, sharing group D's harness through the new package-private `PreviewSupport` (the `Bench`, `LogSink`, the temp-root and fixture helpers, `previewLock`, the resident and `residentLock`, and the small answer accessors, all MOVED there unchanged). It is a separate suite because group D is measured at 23-42 s against this table's 60 s cap and five more render-session properties would cross it; the lock order `previewLock` -> `residentLock` -> `literalLock` is `PreviewSupport`'s and holds across BOTH suites, which matters because `core/test` is unforked and parallel. TEN PROPERTIES. Five are `Runtime`-level and cost MILLISECONDS: a cancel armed for ANOTHER thread leaves this thread's forcing alone; a cancel armed for THIS thread throws `Cancelled` at the head of `swhnf` and the thunk is NOT memoised (forcing it again with the flag clear answers the real value, because the check fires before the thunk is entered at all); a cancel that unwinds a thunk ALREADY BEING FORCED leaves a WHITEHOLE, so re-forcing it on the same thread is a permanent "infinite loop detected" -- which is the evidence for the unconditional discard and for `isFatal`'s WP-6 exception; a `Cancelled` raised inside a `Prim` or a `Box` body ESCAPES rather than becoming a `Bottom` (the regression test for two of the five swallowing catches); and -- ADDED BY THE STAGE 1 REVIEW (DM-3) -- a `Bottom` whose body FORCES does not catch the cancel and hand it back as a value, reached through `Bottom.toString` because `thrown` is `private[ermine]`. **THE `IO.Unsafe.eval` AND FOREIGN-INVOKE ARMS REMAIN UNVERIFIED BY TEST, and the earlier reason given for that was wrong**: the review showed `IO.Unsafe.eval` IS reachable from a booted session -- `Prelude` re-exports `IO.Unsafe`, and `Field.e`'s `unsafePerformIO guid`, `IO.e`'s `trace` and `Random.e` all reach it. What is not cheap is a fixture that loops INSIDE that primitive's `try` rather than after it: the loop has to be forced by the FFI action itself (`trace (toString (spin n)) 1`, where `printLn` forces the non-terminating string inside `e.extract[FFI[_]].eval`), and getting those imports past the documented `Prelude`-plus-`Primitive` ambiguity is a typecheck gamble that was not taken inside this batch's run budget. The shape is written down here so the next batch can add it in minutes; both arms were fixed by the same one-line rule as `Prim.apply`, which IS covered. Five are render-session properties on their own benches: with the switch ON a looping report is CANCELLED (500 carrying "evaluation did not finish after" and "CANCELLED", NO `stuck` key, NO `ermine/preview/stuck` of either polarity, `wp5/ping` answered meanwhile, and the next render BOOTS -- the witness for the discard); a job held in `beforeJob`, which the cancel cannot reach, falls back to phase 2b's `{stuck: true}` and the flag is ALREADY CLEAR when the job resumes, so it completes normally and Q10's recovery runs with no discard; with the switch OFF the watchdog takes today's path and never arms the flag (its TEARDOWN arms the flag by hand, because with the switch off nothing else can stop the loop and it would hold the process-wide `Runner.evalLock` for the life of the JVM -- the property says so where it does it, and since I4 of the stage 1 review the teardown runs BEFORE the verdict is built AND again from the `finally`, so that an exception while building the verdict cannot leak the spinning thread); a `$/cancelRequest` in flight still answers `-32800`, never arms the flag, and does NOT discard; and a document holding a CYCLIC list (`repeat`) is cancelled too, which is the `Encode.spine` case that falsified the cheaper placement | **pr** | **MEASURED 2026-09-20, AS A RANGE AND NOT A NUMBER**, because the figure moves with what else is in the JVM: the stage 1 reviewer measured **18.0 / 21.2 / 21.2 s** for the suite alone on an idle box, and FIVE CONSECUTIVE runs in one sbt session after the review's fixes gave **20 / 19 / 18 / 17 / 19 s** (`Passed: Total 10, Failed 0, Errors 0, Passed 10` every time; the suite's own cumulative clock read 16.4-18.6 s). The five `Runtime` properties cost 0.0 s between them; the five bench properties are 1.9-6.9 s each and pay six render-session boots. **THE SUITE HOLDS `previewLock` FOR ITS WHOLE LENGTH** -- every property, including the `Runtime`-level ones, which must serialise because the cancel flag is ONE global reference -- so it SERIALISES AGAINST GROUP D: the two never overlap, and each one's wall time is added to, not hidden inside, the other's. Group D was 31.3-42.0 s across the same runs, inside its own 60 s cap and unchanged by the extraction. The combined figure for the final tree is reported to the orchestrator and deliberately NOT written here, for the reason the row below gives |
| Runner | `TestRunner` (`:112`, `:806` already runs properties concurrently over one runner) | `invalidate` of an unloaded path is a no-op; `invalidate` then `render` reloads the module (loaded-set delta); two report-typed bindings in one module render two documents; `new Runner(cfg)` with an explicit `run` loads no JDBC driver (`CountingRun`, `TestRunner.scala:77`); **(Q4)** a module whose LOAD FAILED renders 500 and is named by the next `invalidate` -- of its own path, of the path of a broken module it IMPORTS, and of a loaded healthy module's path -- while a file under no root and a directory still name nothing, and the fix renders 200 and takes it back out; a module that is pending and then LOADED as another module's dependency is pruned and NOT named; a pending module whose file is DELETED is named while the file is there and not after the retry's 404 | **pr** | seconds |
| Emitters | `TestSqlEmitters` | the SQLite string for a windowed relation contains `over (`; no emitter output contains `TODO`; `UnsupportedOnDialect` for `tryCast` on SQLite | **pr** | seconds |
| Classifier | new, with a fake driver | §8.3 | **pr** | seconds |
| End to end | `tracker/tools/lsp-client.py`, run by `tracker/tools/lsp-smoke.sh` (`scripts/gates.sh:115-120`) | `reports`, render, edit, `invalidated`, render: differs; the schema binding mode on `Sales` (domain is `Query`); **(Q7)** the same binding request in its new shape (`uri`, `binding`, `roots`), and one more check: the schema of a SECOND report asked BEFORE any render of it -- §6's first-pick order -- placed in the SAME temp root so Q6's rule keeps the gate to one render-session boot | `lsp` (**commit**). **Q7 RE-MEASURED 2026-09-20, one direct run each side, exactly as `gate_lsp` runs it** (`with_own_classpath` from `target/ermine-classpath`, restored byte-identically, sha256 checked): **640 checks in 46.7 s before, 641 checks in 47 s after** -- one request changed shape, one check added, and the gate is still a `commit` gate by the same rule. **BUILT AND MEASURED 2026-09-20 (WP-5 stage C)**: 628 checks in 44.5 s before, 640 checks in 46.7 s after -- one preview boot of 1.6 s and one cold check of the copied `Sales.e`. The rule "if the gate passes ~90 s it moves to `pr`" is NOT triggered, so the gate stays at `commit` and `scripts/gates.sh` is unchanged. Under `docs/gate-policy.md` §5 ("gates must catch their mutants ... whenever a gate's definition or scope changes"): the gate's DEFINITION (`gate_lsp`) and its `GATE_SCOPE` string are both unchanged -- checks were added INSIDE `lsp-client.py`, and the files they newly reach (`lsp/Preview.scala`, `lsp/Definitions.scala`) were already inside `$E/lsp/*.scala` -- so the declaration needs no edit, and the gate's catch surface can only grow (before this, no smoke request reached `Preview.scala` at all). The harness was NOT run here: its lanes check out HEAD and run HEAD's `tracker/tools`, so it must follow the commit. The command is `scripts/mutate-and-verify.sh --gates lsp --classes obo,swap,guard,mapord -n 1 --seed 2` | ~1 min |
| Host page | `client` `npm test` (the existing harness plus the `applyMessage` reducer, §5) | every message sequence the extension can send leaves a consistent state (no document and a banner, or a document and its dimming flag) | new `gate_client` in `scripts/gates.sh`, entering at **nightly** per policy; promotion after one recorded catch | seconds |
| Instruments | results written into this document, never gate evidence | the credential gate (§8.4); the `##` count (`tempdb.sys.tables`) after an hour and after Disconnect; RSS and boot seconds before/after preview boot (§2.2); heap after a watchdog fire (§2.5); the bundle checklist (§5); **WP-6 STAGE 2's EVALUATOR A/B: BUILT AS `tracker/tools/eval-bench.sh` AND RUN 2026-09-20; the figures, the deviations and what each number is a number OF are in the section below** | none | human / machine-dependent |

**THE MECHANISM THIS INSTRUMENT MEASURED IS NO LONGER IN THE TREE** (WP-24, 2026-09-20: stage 1
was removed by the user's decision, §13's Q13). **THE FIGURES BELOW STAY, UNCHANGED, AS THE
RECORD OF WHAT IT COST WHILE IT WAS THERE**, and so does `tracker/tools/eval-bench.sh`. Nothing
here is withdrawn and nothing here is strengthened: what this instrument supports is the
sentence it ends in and no more -- *"The instrument suggests a cost of roughly 5% on the
swhnf-densest workload; it does not establish one."* Its A side, `325c3d09`, is once again the
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
| A and B | **A = a clean build of `325c3d09`'s tree** (WP-7's tip, the last commit before stage 1) and **B = the stage 1 tree**, in two worktrees, so neither side is an incremental build of the other |
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
| The two trees | **A** = `325c3d09` in a throwaway detached worktree, `ermine-scala-wt-wp6-perfA`, a fresh checkout and so a clean build of every subproject. **B** = `0ee08425` in `ermine-scala-wt-widget-preview`, whose **`core` was cleaned and rebuilt** for this (`sbt core/clean core/compile core/copyResources`) 76 seconds after A's build, same sbt 1.10.7, same JDK. **SCOPED CLAIM, corrected by the review**: neither side is an incremental build of the other, and **B's `core` is not an incremental build of itself** -- but B's `f0`, `parsers`, `machines` and `scalaz-compat` were NOT cleaned and are pre-existing incremental artefacts, and all five class directories are on the classpath. `wp6-s2-buildA.log` compiles f0 (11 files), parsers (14), scalaz-compat (3), machines (12) and core (179); `wp6-s2-buildB.log` compiles core (179) only |
| The driver | ONE copy of ONE file drives both sides -- the script is not copied into the trees at all, it is pointed at each tree's classpath, so there is only one thing to check. The two `target/ermine-classpath` files are identical once the tree prefix is stripped (21 entries each) and both `modules/` directories hold 64 entries; no `.e` module differs between the commits (`git diff 325c3d09 0ee08425`) |
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
| 5 | **Isolate the head check**: a third tree = `0ee08425` with ONLY the `swhnf` head check reverted, A/B against B | clean `core` ~40 s + **~11 min** | separates the head check from the `Prim.apply` / `Box.apply` / `Bottom.thrown` catch arms, and makes the attribution language true instead of assumed |
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
| Drive the loop off `bin/ermine-serve` | a JVM boot per `.e` edit (`Runner.scala:411-420`; `JSON-GUIDE.md:1452-1453`); no host page, no CORS (`JSON-GUIDE.md:1593-1603`); a credential would be an argument (`bin/ermine-serve:32-33`) |
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
| Q1 | which global the writers bundle puts on `window` (`htmlwriter` vs `ermine_htmlwriter`) | **ANSWERED BY READING 2026-09-20** (WP-9/10/11 design review, §5's findings block): it is **`window.ermine_htmlwriter`**, assigned **only inside a `DOMContentLoaded` listener** (`ermine-writers/writers/js/htmlwriter.js:10-13`), and `client/src/index.ts:5` documents the wrong name. The timing, not the name, is the half that bites. Nothing decided, nothing built; WP-11 still owns writing it down |
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
| Q13 | a stuck preview takes the WHOLE SERVER down at `-Xmx` about two minutes after the watchdog fires (MEASURED, §2.5), which is not the story §2.5 tells | **DECIDED 2026-09-20 BY THE USER: option (ii), PRIORITISE WP-6.** Stage 1 (the mechanism) is BUILT behind `ermine.preview.cancelOnTimeout`, DEFAULT FALSE; stage 2 is the evaluator instrument of §11; stage 3, ADOPTION -- flipping that default -- is the user's. Resolved. **RE-OPENED AND RE-DECIDED BY THE USER THE SAME DAY, 2026-09-20 (evening). The line above is kept as history, not overwritten.** **THE NEW ANSWER: option (iii) -- ACCEPT THE WEDGE, CONTAIN IT IN THE CALLER (WP-22), AND REMOVE THE CANCEL (WP-24).** The user's words, verbatim. On the in-evaluator cancel: *"That sounds super sketchy."* On accepting the wedge and containing it: *"I like 3 honestly. One thing to watch for would be an infinite re-render loop. We'd want some sort of confirmation before rendering a report which wedged and was killed the first time around and it didn't change."* On where the memory belongs (quoted WITHOUT the surrounding italics, because the user's own text contains asterisks): "I think "remembering" is an extension concern. I like this approach infinitely better than modifying the language all for a way to recover a stuck render( especially since most of the solutions you mentioned, indicate that responsiblity for solving this happens with the *caller* )" They then confirmed that the cancel instrumentation inside general Ermine evaluation is to be removed. **THE REASON IS THE DESIGN, NOT THE PERFORMANCE FIGURE**: a preview-only recovery does not justify instrumenting the language's evaluator, and responsibility for a stuck render belongs with the caller. Stage 2's instrument neither decided this nor could: what it says is §11's own sentence, *"The instrument suggests a cost of roughly 5% on the swhnf-densest workload; it does not establish one."* **STAGE 3 IS MOOT** -- there is no default left to flip. Resolved again, by removal (WP-24, done); what answers Q13 now is **WP-22, which is NOT BUILT**, and until it is, the behaviour is the one this row started from: the server dies at `-Xmx` about two minutes after the watchdog fires, and the client restarts it |
| Q14 | a render that fails by a TRANSIENT error leaves that failure MEMOISED in the render session's thunks, so a binding of a module nobody edits re-throws the old error for the life of the session | nothing; decide with WP-12/WP-13 |
| Q16 | `placeAndSession` calls `ensureSession` BEFORE it refuses an unplaceable file, so a request that is going to be refused anyway can still discard and re-boot the render session when its roots differ | nothing; OPEN, the user's |
| Q17 | the `Stopped -> Running` recovery re-render RE-ISSUES the render that killed the server (`preview-core.js:355` emits `rerender` on that transition, `extension.js:471` turns it into a real `ermine/render` of the same pick), and the **Restart Language Server** button in our own stuck notification (`extension.js:452-456`) takes THE SAME PATH -- so the one remedy we offer during a wedge is itself a loop trigger. READ from the code by the WP-24 design review; **UNOBSERVED in a real editor by anyone** | **DECIDED 2026-09-20: BY WP-22** -- one mark for the current pick, one consultation site (that `rerender` effect), and a confirmation instead of an automatic re-render when the report that wedged has not changed. Under Q13's new answer this path fires by design on every incident, which is why the guard is what makes accepting the wedge safe. WP-22 is NOT BUILT, so the loop is reachable today |
| Q18 | under Q13's new answer the SERVER keeps no self-defence at all: after a restart it is a new process and cannot know what wedged the last one, so only the CALLER spans the restart and `bin/ermine-serve`, `bin/ermine` and every non-VS-Code client are unprotected | **OPEN, and ACCEPTED as a known hole unless the user says otherwise.** It is the same fact that makes the extension the right owner (the user: responsibility "happens with the *caller*"). Two consequences to state rather than fix: the extension-only memory does not cross windows -- a second VS Code window on the same folder does not see the mark until it reloads (cross-window `Memento` visibility UNVERIFIED) -- and WP-23 (a server-side deliberate exit) stays PARKED, not started |
| Q19 | **the committed legacy writers bundle is a webpack-4 `eval` build (574 `eval("`, 1 `new Function`, MEASURED), so a webview CSP without `'unsafe-eval'` would not load it (INFERRED, never watched failing) -- and WP-9's and WP-11's done-whens depend on it loading** | **OPEN, THE USER'S.** Three options, from §5's findings block, none taken: (i) add `'unsafe-eval'` to `script-src` for the preview webview only -- one word, and the webview's content is already the developer's own workspace and database, but it is a documented weakening of a documented recommendation; (ii) rebuild the writers bundle with a non-eval `devtool` -- a 2019 toolchain (webpack 4, `node-sass@^4`) under node 24, likely a fight (unverified), and a 5 MB artifact to commit in the sibling repo; (iii) ship the preview without the legacy renderers -- `scorecard`/`headline`/`crosstab` render, `table`/`drilldownTable`/charts show the designed "unsupported" box, and WP-11 becomes "not yet". **It is a security decision, not an engineering one** |
| Q20 | **should `Session.scrub` be hardened (WP-25), and if so when?** ROBUST-3 (2026-09-20) showed that `scrub` is only correct if its caller's module set is CLOSED UNDER IMPORTERS, and that nothing checks it: `e.env` is filtered by the V's OWN defining module while `e.termNames` / `termNameOrigins` / `cons` are filtered by the KEY's module (`session/Session.scala:811-827`), so a non-closed set deletes a definer and leaves every re-exporter's name pointing at it, and the next load dies with `undefined term` inside a stdlib file the user never touched instead of an honest "not in scope". IN THE PRODUCT the non-closed set is NOT reachable today by the path ROBUST-3 found (the LSP never removes a `Filesystem` key from `Session.depCache` -- `lsp/Documents.scala:77`, `:111` evict `Buffer` keys only -- so `dependentsOf` always has complete edges); WP-26 is the one INFERRED way it could become reachable. The proposed change is ONE LINE plus a pinning property, and its evidence is measured (13 of 30 random subsets fail the property today). **IT TOUCHES THE SESSION CORE, which every suite and the REPL load through, so building it is THE USER'S CALL and nothing has been built.** | nothing; WP-25 is NOT BUILT |

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
and `schemaError` puts it beside `error`. **NOTHING ELSE CARRIES ONE**: a 404 from the `Runner`,
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
| WP-6 | **BUILT (stage 1, `0ee08425`), MEASURED (stage 2, `92c974be`) AND REMOVED FROM THE TREE (WP-24, 2026-09-20), BY THE USER'S DECISION (§13, Q13). NONE OF (a)-(i) BELOW IS IN THE CODE; they are kept, unedited, as the design record of what was built and why -- read them as history, not as behaviour.** What the watchdog does now is what it did at `325c3d09`: ONE PHASE -- `fire` (`Preview.scala:2069`) claims the job under `lock` and does the stuck mark, the `seq` mint, the drain and the notification inline (§2.5). `fireStuck` was `0ee08425`'s name for the second half of the split and does not exist here. Stage 3 is moot: there is no default left to flip. **WHAT REPLACES THIS TICKET IS WP-22, WHICH IS NOT BUILT.** AS BUILT AND AS MEASURED, THE RECORD: **cooperative cancel. STAGE 1 IS BUILT (2026-09-20), AND REVIEWED: the independent design-and-implementation review returned RED with four MUST-FIX items (DM-1 the answer-before-clear ordering, DM-2 the `shutdown`-inside-the-grace leak, DM-3 `Bottom.thrown`, and the `previewLock` race in the new suite's own `R` properties), all fixed here; **STAGE 2 IS BUILT AND RUN (2026-09-20)** -- `tracker/tools/eval-bench.sh`, figures in §11's Instruments section -- **AND STAGE 3 IS NOT BUILT AND IS THE USER'S.** This row was AMENDED to the reviewed design, which departs from its own earlier letter in four places, each recorded here rather than folded away. **(a) THE FLAG.** ONE GLOBAL `@volatile Runtime.cancelTarget: Thread` beside `@volatile Runtime.cancelWhy: Cancelled`, and the check is at the **HEAD of `Runtime.swhnf`**, unconditionally, on every call -- one volatile load and one predictable null-branch; `Thread.currentThread` is reached only while a cancel is armed. NOT a per-thread evaluation context and NOT `Thread.interrupt`: `Preview.takeJob` reads an `InterruptedException` as "stop", `ForeignClasses.Recoverable` and the backends react to an interrupt, third-party code may clear the flag, a JDBC driver may abort its connection. NOT inside `swhnf`'s `case old =>` branch: the design review proposed that cheaper placement and then FALSIFIED it -- `json/Encode.scala`'s `spine` walks a list with `while (true) { Runtime.swhnf(cur) }`, and on a CYCLIC list every thunk it re-reads is already `Evaluated`, so that branch is never entered. **(b) `Cancelled` IS A `ControlThrowable`**: stackless, EXCLUDED by `NonFatal` so `swhnf`'s own capture does not memoise it, and NOT an `Error` -- `ForeignClasses.Recoverable` swallows an arbitrary `Error` into a failed reflective lookup and lets a `ControlThrowable` through (`ForeignClasses.scala:26`, verified by reading before it was relied on). **(c) THE FIVE CATCHES THAT WOULD HAVE SWALLOWED IT**, which this row did not name and without which a cancel silently does not work: `Prim.apply` and `Box.apply` (`Runtime.scala`), `IO.Unsafe.eval` (`session/Lib.scala` -- it would hand the cancel to Ermine-level error handling), the foreign invoke (`session/Session.scala` -- it re-wraps as a `RuntimeException`, which IS `NonFatal` and would be memoised) and **`Bottom.thrown` (`Runtime.scala`), THE FIFTH, FOUND BY THE STAGE 1 REVIEW (DM-3)**: two `Bottom` bodies in `core` FORCE, and `thrown` is what `Encode`, `Doc`, `Pretty.ppRuntime` and `toString` call, so a cancel could be caught there and RETURNED AS A VALUE. Each gained `case c: Cancelled => throw c` as its FIRST arm and was NOT otherwise narrowed. **THE EARLIER CLAIM THAT "every other `catch` of `Throwable` ... was audited and passes a `Cancelled` through" WAS FALSE and is corrected here**: the audit covered `catch` clauses on the call path and missed a by-name body that forces INSIDE one. With `Bottom.thrown` closed, the sweep stands for the rest. **(d) THE WATCHDOG IS TWO-PHASE**, and only when the switch is on; off, `fire` behaves EXACTLY as before. Phase 1 at `timeoutMillis`: arm the flag and NOTHING else -- no answer, no stuck mark, no drain, no notification. Phase 2a, the cancel took: answer 500 with the timed-out text reworded, WITHOUT §4's `stuck` marker (`refusal`, not `stuckRefusal`), **DISCARD THE SESSION UNCONDITIONALLY** -- the escape leaves WHITEHOLED thunks with this thread in `pending`, which a later same-thread force would memoise as "infinite loop detected", and the discard must not ride on the stuck machinery because `stuck` was never set and `clearStuck` returns 0 -- then clear the flag. Phase 2b, `graceMillis` (1000 ms, a constant) later and still in flight: CLEAR THE FLAG FIRST, then do exactly what the watchdog did before, and Q10's recovery applies unchanged. **(e) A USER `$/cancelRequest` DOES NOT INTERRUPT** -- a deliberate departure from this row's earlier text, for three recorded reasons: the extension passes no `CancellationToken` today so nothing sends one, a discard costs a boot, and the watchdog covers the case that matters. `userAsked` is on the `Cancelled` class for a future client and nothing sets it true. **(f) `isFatal` GAINS ONE DOCUMENTED EXCEPTION**: a `Cancelled` is NOT fatal for the stuck machinery, although it is a `ControlThrowable` and so fails that method's half (2). It is sound ONLY because the cancel path discards the session unconditionally; if that discard is ever made conditional the exception must go with it, and `isFatal`'s scaladoc says so. **(g) WHAT THE MECHANISM CANNOT CANCEL**, because none of it reaches `swhnf`: a loop inside ONE primitive, the relational row loop (`relational/package.scala`'s `driveLeftId`), a JDBC scan, and a thread parked in `SessionTask`'s `future.get` or a thunk's `latch.await`. **Phase 2b is the fallback for all of them.** **(h) THE FLAG IS CLEARED IN FIVE PLACES**: before the ANSWER on the cancel path (DM-1 -- `clearCancel`, `discardSession`, then `finish`, so the answer's claim is true when it is sent), at phase 2b before the fallback, in `runJob`'s `finally` for every job, in `Preview.cancelTimer` (DM-2 -- the `shutdown`-inside-the-grace path that no other clear reaches, and the one that matters in the unforked test JVM), and in `Preview.takeJob`, which logs loudly. **THE WRITES THEMSELVES ARE BEHIND `Runtime.armCancel` / `Runtime.disarmCancel`** (S1/S2), which enforce the order and the identity guard in one place and let an arm be REFUSED when another thread's is live; the fields are `private[Runtime]` and `swhnf` reads them directly. **(i) THE SWITCH** is `ermine.preview.cancelOnTimeout`, read by `applySettings` by both routes like the other two settings, ill-typed values refused out loud, DEFAULT FALSE. It is NOT exported in `editor/vscode/package.json`: an export is only useful once the default is a live question, which is stage 3's, and adding it now would offer the user a switch this document says is not theirs to flip yet. **DEFAULT-OFF DOES NOT MAKE THE CHANGE FREE** -- the load and the branch are in the binary regardless, and FLIPPING THE DEFAULT ADDS NO PER-FORCE COST for the same reason. Stage 2 measured what carrying them costs: nothing distinguishable on an ordinary fold, and a suggested but not established ~5 % on the `swhnf`-densest workload (§11) | **STAGE 1 (done 2026-09-20)**: `TestPreviewCancel`'s **ten** properties (§11) pass [**count corrected 2026-09-20 by WP-24's review: this cell read "nine"; §11 and `0ee08425`'s own message both say TEN (5 `Runtime`-level, 5 through a real bench)**], `TestLspRobustness` is unchanged and still inside its cap, and a looping render is cancelled and the next render boots a new session, MEASURED. **STAGE 2 (done 2026-09-20; its WRITE-UP reviewed RED and corrected without re-measuring)**: the evaluator A/B of §11's Instruments row, BUILT as `tracker/tools/eval-bench.sh` and RUN in two worktrees with the editor closed (`lsp=0 console=0 serve=0 ermine-jvm=0` checked before every one of the 30 forks). THE ANSWER IS NOT ONE NUMBER, AND IT IS WEAKER THAN A NUMBER: on the ordinary build-and-fold workload nothing is distinguishable (+2.9 % and -1.4 % in two runs, every test p >= 0.12, estimators disagreeing in sign). On the `swhnf`-densest workload -- re-folding a list whose cells are already `Evaluated`, which is the shape the head placement exists for -- **W2 moved +5.8 % and +4.9 % in the same direction in two runs with the pair order reversed, and every estimator (fork medians, pooled mean, pooled median, per-fork minima, every leave-one-fork-out) agrees in sign; a central estimate is about +5 %. No test on 5 forks per side reaches conventional significance -- exact stratified permutation over both runs p = 0.089, Mann-Whitney on the A-first run p = 0.095, sign tests p = 0.38 and 1.0 -- and a hierarchical bootstrap CI on the ratio includes zero in both runs. The instrument suggests a cost of roughly 5% on the swhnf-densest workload; it does not establish one.** [**quotation corrected 2026-09-20 by WP-24's review: this cell rendered that sentence's percent sign as "5 %"; §11's verbatim block is the authoritative copy and reads "5%", which is what Q13 and §11's own lead now quote character for character**] Two further corrections the review forced: the delta is the WHOLE STAGE 1 COMMIT's effect on evaluation (the head check PLUS the `case c: Cancelled => throw c` arms in `Prim.apply`, `Box.apply` and `Bottom.thrown`, whose bytecode sizes were never measured), not the head check alone; and the derived <= 73 ns per check is an UPPER bound from a LOWER bound on the count, so it is compatible with a true cost of 1 ns and cannot be used to argue the load is not the cause -- at a realistic 40-100 `swhnf` calls per element-visit it falls to 2.4-7.3 ns. The check does add 44 bytes of bytecode to `swhnf` (216 -> 260), which excludes the bytecode-size inlining threshold story and nothing more. §11 carries the table, the tests, the six deviations, what is MEASURED versus DERIVED versus UNVERIFIED, and the costed options that would make this decisive (none run). **STAGE 3, THE USER'S**: the default is flipped only by them, on stage 2's figures | pr (stage 1, done) + instrument (stage 2) + the user (stage 3) |
| WP-7 | extension: **Ermine: Preview Report...** as a (file, binding) picker over `ermine/preview/reports` with per-workspace memory and free-text fallback, **Ermine: Render Report to JSON** into an untitled editor tab, `ermine.preview.roots` (resource scope, absolutised), re-render on `invalidated`, the `ermine.maxHeap` export; **(Q11, decided 2026-09-20) re-render when the picked report's own file is created or changed while its last answer was a PLACEMENT 404** (not a `Runner` 404: that module loaded, so `invalidated` already covers it and a second trigger would double-render), told apart by **Q15's `reason` key** (§4) -- ONE SMALL SERVER CHANGE, in `lsp/Preview.scala` only, decided by the user after WP-7's review showed no client-side test could be exact; **(Q8/Q10) the stuck banner of §5**, fed by `"stuck": true` on a refusal and by `ermine/preview/stuck`, carrying the **Ermine: Restart Language Server** button and clearing on `{stuck: false}`, **with the `seq` high-water mark RESET on the language client's Stopped -> Running transition** (§4's rule (1), DD-2: `seq` is per-process and restarts at 1, so a client that kept the old mark across the restart the watchdog's own message asks for would ignore the fresh server's `{stuck: true, seq: 1}` for the life of its session); **(Q9) the `ermine.preview.timeoutSeconds` and `maxDocumentBytes` exports, with "0 = no watchdog" in the setting's description** | on `core/src/test/resources/doc/Sales.e` with no setting the picker offers `report : Query -> Node`; **the tab shows `{"status": 400, "path": "$.params", "message": "the required key \"fromDay\" is missing"}`** (WP-8 turns it into a document); saving `Sales.e` updates the tab with no restart; moving `Sales.e` away and back re-renders it by itself; no webview. **THE 400's WORDING IS THE MEASURED ONE and this row was amended (2026-09-20)**; AS FIRST WRITTEN it read "the tab shows a 400 naming `$.params.fromDay`", which no client can produce: a MISSING required key is reported at the path of the OBJECT that should have held it with the key in the message (`json/Decode.scala:723-725`), and `$.params.fromDay` is the path of a key that is PRESENT and ill-typed -- `{"fromDay": 5}` answers "expected a date string yyyy-MM-dd, found the number 5" there, which is WP-8's case, measured. A per-key path for a missing key would be a change in `json/Decode.scala` and was NOT made | manual + commit smoke / ~1 day |
| WP-8 | **AMENDED 2026-09-20. WHAT THE USER DECIDED ("go for it") IS EXACTLY U1-U8, the eight questions the WP-8 design review put to them** (its §5, "Questions that are the user's"), each taken as the review recommended it. **D1-D8 are the DEFECTS the review found in this row and S1-S4 is its four-stage BUILD PLAN -- the review's own recommendations, not the user's decisions**; they are recorded, not ratified. All of it, with the reworded done-when, is in §6's amendment block, which draws the same line and is authoritative for this ticket. WP-8 NEEDS NO SERVER CHANGE (no Scala compiles, no JVM gate moves), and it EXPORTS `paramsFingerprint` for WP-22.** The row as written: params: `.ermine/preview/<Module>/<binding>.params.json`, the skeleton from the schema on first pick, `<binding>.schema.json` beside it with a relative `$schema`, `$schema` stripped before sending, re-render on save, the orphan message, the one `.gitignore` line | **REWORDED (U2/D4): `Sales` renders a document on first pick with no hand-written JSON -- EMPTY until the dates are edited, because the skeleton's "today" selects none of `Sales`'s 2026-01..03 rows, and the file is opened for editing straight after it is written.** As written: `Sales` renders a document on first pick with no hand-written JSON; completion and a red squiggle for a wrong key in `Sales/report.params.json`; saving it re-renders; renaming the binding shows "no params for"; `git status` shows the params file and not the schema | commit smoke + manual / ~1 day |
| WP-9 | **READ §5's WP-9/10/11 FINDINGS BLOCK (2026-09-20) BEFORE STARTING THIS: a read-only design review, nothing decided.** Its D1 (the committed writers bundle is an `eval` build, new **Q19**), D4 (two entries + a nonce), D5 (ts-loader or tsc-first, open) and D9 (this row's tier gates nothing; two checklist rows can be node tests) all land on this row. As written: webpack browser bundle: config, `npm run bundle` / `bundle:watch`, `devtool: 'source-map'`, output under `client/dist/browser/` | `npm test` unchanged; the bundle checklist of §5 passes under a CSP without `unsafe-eval` | nightly (`npm test`) + checklist / ~half a day |
| WP-10 | **READ §5's WP-9/10/11 FINDINGS BLOCK (2026-09-20) BEFORE STARTING THIS: a read-only design review, nothing decided.** Its D10 (`applyMessage` is a PRESENTATION reducer only; every decision stays in `preview-core.js`), D11 (the message list must carry WP-22's `held` and must NOT encode §4's withdrawn rule (5)), D4's nonce and D6 (the writers' CSS needs a `localResourceRoots` entry and a `<link>`) land here, as does the missing "the bundle is not built" banner. As written: webview panel: host page, CSP, `localResourceRoots`, the `applyMessage` reducer and its `node --test`, banner states (initial, error, stale, unsaved, switching, offline, fast mode), `retainContextWhenHidden`, bundle watcher -> reload; `gate_client` registered at nightly | `Sales` renders inline; editing `client/src/widgets/scorecard.ts` updates the panel without a restart; a 400 from a bad param shows `path` in the banner; the reducer property passes; `scripts/gate.sh run nightly` runs `gate_client` | nightly + manual / ~2 days |
| WP-11 | **READ §5's WP-9/10/11 FINDINGS BLOCK (2026-09-20) BEFORE STARTING THIS: a read-only design review, nothing decided.** **Q1 is ANSWERED BY READING** (`window.ermine_htmlwriter`, assigned only on `DOMContentLoaded`), so this row's remaining work is writing that into `client/src/index.ts`/`legacy.ts` and waiting for the event -- and **this row's done-when depends on Q19**, because none of it runs while the writers bundle needs `'unsafe-eval'`. As written: Q1 and the legacy renderers in the panel | `table` renders through `runTabular`; the global's name is written into `client/src/index.ts` and `legacy.ts` | checklist / ~half a day |
| WP-12 | `mssql-jdbc` `jre11` in `build.sbt`; one real connect from the preview; `sqlPrimT`'s `"date"` mapping checked; Q3 answered. **DONE-WHEN SPLIT 2026-09-20, because the user plans a LOCAL SQL Server with a password (§8's amendment)** | **(a) LOCALLY, and enough to unblock WP-13/WP-14**: the driver resolves in `build.sbt`, a connect to the local server succeeds (MEASURED), the `"date"` mapping is checked, and the prompted-password path is exercised end to end. **(b) ON THE WORK NETWORK ONLY**: Q3 -- whether the internal CA is in the JDK's `cacerts` or `Windows-ROOT` is needed -- and the first-connect TLS behaviour recorded as observed, with the truststore answer written into §7.3. (a) does not answer (b), and (b) is what the wait for the work server is for | instrument / ~half a day each half |
| WP-13 | **AMENDED 2026-09-20 -- DECIDED BY THE USER: NO SECRET STORE. `SecretStorage`, the `sha256(url + "\0" + user)` key and the "Forget Database Password" command are DROPPED from this row; the password is PROMPTED for (§8's amendment carries the user's words and what stays regardless -- A1, A2, A4, A5/A6, A7, A9, A10 and the §8.4 gate).** The row is otherwise unchanged and is kept as written, **with the two DROPPED items struck through below so that this list cannot be read as a done-when**: profiles (user scope only) + `ermine/preview/connect` + the four-way classifier with `kept` + `Throwable` catch and scrub + URL credential refusal + ~~`SecretStorage` keyed by `sha256(url + "\0" + user)`~~ **(DROPPED -- the extension PROMPTS)** + trace-`verbose` refusal in the one `connect()` + ~~**Forget Database Password**~~ **(DROPPED -- there is nothing to forget)**; no `untrustedWorkspaces` declaration; the Settings-Sync answer written into §8.2 | the credential gate (§8.4) passes in full; the fake-driver classifier test passes; a workspace-scope profile is ignored and named once | pr + instrument / ~2 days |
| WP-14 | **AMENDED 2026-09-20 -- DECIDED BY THE USER: NO SECRET STORE (§8's amendment).** The EXTENSION-DRIVEN RECONNECT in this row is what makes the prompted password's lifetime a live question: PROPOSED, NOT YET CONFIRMED, the prompt is held in the extension host's memory for the window's lifetime so a reconnect after a server restart stays automatic; the stricter variant makes every reconnect a click. Unchanged otherwise: held connection lifecycle: the §7.2 switch sequence, Disconnect command, `disconnected` notification, extension-driven reconnect, re-render after every connect, recycling defaults (Q2), reconnect on `Running`, status-bar item `id (dialect) @ host`, the file-backed SQLite profile documented. **THE CLOSE THIS TICKET PUTS IN `discardSession` MUST NOT BLOCK** (review S3, 2026-09-20): Q10's recovery calls `discardSession` from `runJob`'s `finally`, AFTER `disarm()`, so it runs with no watchdog over it and with the stuck state ALREADY CLEARED -- a `Connection.close()` that hangs on a dead socket would wedge the preview thread in a state nothing would fire on and nothing would refuse. It is free today (`DelegatingRun.clear()` closes nothing); this ticket owns giving that close a timeout, or moving it off the preview thread. **THE TWO WP-6 CLAUSES THAT FOLLOW ARE WITHDRAWN (WP-24, 2026-09-20): the cancel is removed, so this ticket no longer owns either of them.** The close-that-hangs half above stands on its own (it is the rare recovery path again, not a common one), and the converse latch leak was a CONSEQUENCE OF THE CANCEL -- §2.5's own note now says so and this pointer is withdrawn with it. Kept as the record: **WP-6 STAGE 1 WIDENED THIS AND MADE IT COMMON (2026-09-20)**: the cancel path discards the session UNCONDITIONALLY, from the same `finally` and with the same `disarm()` already done, so with `ermine.preview.cancelOnTimeout` on, EVERY watchdog incident whose cancel takes ends in an unwatched `discardSession` -- the ordinary path, not the rare recovery one. A close that hangs there wedges the preview thread on the common case. **AND THIS TICKET OWNS THE CONVERSE LEAK (S3 of the WP-6 stage 1 review, DERIVED BY READING AND UNVERIFIED)**: a cancel unwinds without `writeback`, so the thunks it passed keep their `CountDownLatch` uncounted, and `discardSession` releases none of them -- a SCAN'S CHUNK PRODUCER (or any `SessionTask` pool thread) that later reaches one parks on `latch.await` for ever. Daemon threads, so the JVM still exits; what leaks is one thread and its retained queue per cancelled render that had a concurrent scan. It is unreachable while the stage A backend opens one connection per run and nothing scans concurrently, and this ticket is where a real database makes it reachable | a 1-hour session against MSSQL leaves no `##` tables after Disconnect (count in `tempdb.sys.tables`, MEASURED); a profile switch mid-render discards the old answer; killing the server and letting the client restart it ends in a rendered document; no password *field* in `lsp/Preview.scala` (code review), the driver's `Connection` acknowledged to hold it until close | instrument + manual / ~1.5 days |
| WP-15 | SQLite emitter gaps: `EmitOver_UsingOver` mixin, bracket names, parenthesised joins | `TestSqlEmitters` pins each string; a windowed report previews on SQLite with rows | pr / ~half a day |
| WP-16 | engine gaps: `UnsupportedOnDialect` at the §9.2 sites, 500 banner, deploy-dialect badge | no emitter output contains `TODO`; `tryCast` on SQLite shows the banner naming `tryCast` and `sqlite` | pr / ~1 day |
| WP-17 | closed-environment packaging: vendored `client/node_modules` or internal registry, driver jar offline, `bin/ermine-lsp.cmd` (and a PowerShell twin) with `resolveServer` choosing it on Windows. **THE WINDOWS WRAPPERS MUST CARRY THE JVM POLICY, not just the classpath** (Q12, 2026-09-20): `-Xmx${ERMINE_LSP_XMX:-2g}` with the 64m floor, `-XX:+ExitOnOutOfMemoryError`, AND `-XX:+DisplayVMOutputToStderr` behind the same cached, java-keyed probe `bin/ermine-lsp` uses -- §10 says the deployment machines are Windows, so that is exactly where Q12's unframed OOM line on the protocol channel matters, and today neither the flag nor the cap reaches them | a fresh clone on a work machine runs WP-7 and WP-10 with no network and no WSL; the credential gate passes on Windows | manual / ~1 day |
| WP-18 | docs: `docs/JSON-GUIDE.md` §9/§10/§12 (the guide's `Runner.scala:259-280` reference at `:1571` has drifted to `:287-288`), `client/README.md` "Adding a widget" (`ermine/schema` from the render session replaces eleven boots), `editor/vscode/README.md` | the three documents describe the loop as built; MEASURED figures replace the mined ones here | none / ~half a day |
| WP-19 | **optional, out of the loop**: dual-emit T-SQL diff in the panel via `dumpRel` / `dumpClosed` | only if relation authoring in the panel is asked for | -- |
| WP-20 | **NOT BUILT, found by WP-6 stage 1's design review**: a LENGTH CAP on `json/Encode.scala`'s `spine`. It walks a `::` spine with `while (true) { Runtime.swhnf(cur) ... }` and `buf += args(0)`, and a CYCLIC list (`repeat a = t where t = a :: t`) makes it run until the heap is gone. **CORRECTED 2026-09-20 (WP-24 and its design review): WP-6 IS REMOVED, so nothing stops it ANYWHERE, the preview included** -- the sentence that used to say "WP-6 makes the PREVIEW able to stop it" is withdrawn. And a premise correction worth keeping beside the ticket: **`Encode.spine` ALLOCATES** -- `buf += args(0)` adds one `ListBuffer` cell per step (READ, `Encode.scala:233-247`) -- so WP-20 is an ALLOCATING wedge, contained by the heap cap in the only sense that cap contains anything (the process exits, MEASURED §2.5), and it is NOT an example of a wedge that never dies. The realistic never-dying wedge is a BLOCKED preview thread (a parked `future.get`, a thunk's `latch.await`, a JDBC socket read, WP-14's hanging `Connection.close()`), which WP-13/WP-14 make reachable and which nothing in the tree can produce today. Nothing stops the spine in `bin/ermine-serve`, in `bin/ermine`, or anywhere else `Encode` is used, and `swhnf` is not where the fix belongs -- a spine longer than any document could carry is an ERROR at its own index, in the same shape `spine` already uses for a bottom or a foreign tail. Deliberately NOT built with WP-6: a cap is a wire-visible behaviour change for every encoder caller and wants its own decision about the number | a report whose document holds an infinite list answers a 500 naming the path and the cap instead of exhausting the heap; `TestJson` and `TestRunner` unchanged | pr / ~2 h |
| WP-21 | **NOT BUILT, found by WP-6 stage 1's design review**: `Pretty.ppRuntime`'s DEPTH CAP IS LOST on the general-constructor arm. `ppRuntime(e, d)` refuses to go past `d > 10` (`Pretty.scala:368`) and passes `d + 1` down its own arms, but `case Data(n, arr) => ppAppNR(n, arr.toList)` (`:383`) hands the children to `ppAppNR`, whose every arm calls `ppRuntime(x)` with the DEFAULT `d = 0` (`:325-332`). So the counter resets at each constructor and `Runtime.toString` on a CYCLIC user data value never stops -- and `Runtime.toString` is what every "Panic: unexpected runtime value" message, every `Bottom` description and the REPL's own printing go through. The list arm is safe (`asList` answers a `(zs, truncated)` pair); it is the general one that is not. Deliberately NOT built with WP-6: it is a pre-existing defect on a different path, and threading `d` through `ppAppNR` touches every printer arm | a cyclic `data` value prints `...` at the cap instead of hanging; the REPL and `TestErmine`'s printing are unchanged | pr / ~2 h |
| WP-22 | **NOT BUILT. The wedge guard and caller-owned recovery, EXTENSION ONLY, one ticket** -- what replaces WP-6 under Q13's 2026-09-20 re-decision. **(a) THE MARK. DECIDED BY THE USER**: the memory lives in the EXTENSION (*"I think "remembering" is an extension concern"*), and a report that WEDGED AND HAS NOT CHANGED is not re-rendered without a confirmation (*"We'd want some sort of confirmation before rendering a report which wedged and was killed the first time around and it didn't change"*). **THE PRINCIPLE ABOVE IS THE USER'S; THE SHAPE THAT FOLLOWS IS THE DESIGN REVIEW'S RECOMMENDATION**, the same line letter (b) draws -- the record's fields, its key encoding and the SET/CLEAR trigger lists were not put to the user and are not decided. ONE mark for the CURRENT pick only -- never a map -- `{key, reason, at, rootsFingerprint, paramsFingerprint}` keyed by `uri + "\u241f" + binding`, with roots and params in the VALUE so that changing them CLEARS rather than mints a second mark. SET by a `stuck: true` answer, by `ermine/preview/stuck {stuck: true}`, and by a `Stopped` transition while a render of that pick was in flight. CLEARED by `{stuck: false}` (Q10's recovery -- the load-bearing clear, without which a 300 s scan under a 60 s watchdog is held for ever), by an `invalidated` naming the pick's module, by any `.e` save, by a pick / roots / params change, and by any explicit user render, which IS the confirmation. The "it didn't change" test is a PROXY, not a proof: the wedge is usually in a DEPENDENCY, so a content hash of the picked file would be wrong, and the two signals used err towards asking less. **(b) THE CONSULTATION, AT EXACTLY ONE SITE** -- the shape below is the DESIGN REVIEW'S RECOMMENDATION; the PRINCIPLE (ask before re-rendering a report that wedged and has not changed) is THE USER'S: the `rerender` effect of the `Stopped -> Running` transition (`preview-core.js:355` -> `extension.js:471`), where the automatic render is replaced by ONE NON-MODAL `showWarningMessage` offering **Render anyway** / **Not now** (Escape = "Not now", never consent), plus a fourth `statusBarState` branch `held` with the precedence **offline > stuck > held > rendering > idle**. The other automatic triggers are each self-evidently a change and are NOT suppressed: `invalidated`, the Q11 watcher, a roots change, and `{stuck: false}`. New PURE `markKey` / `guardReduce` / `shouldAutoRender` / `heldMessage` in `preview-core.js`, each with `node --test` cases; **`stuckReduce` IS NOT CHANGED** (its four rules, DD-2 and its pinned properties stay as they are). **(c) RECOMMENDED BY THE WP-24 DESIGN REVIEW AND NOT YET CONFIRMED BY THE USER -- all of this letter is a recommendation, not a decision**: that on `{stuck: true}` the EXTENSION ITSELF restarts the server after a grace (the review's "B-EXT": arm a timer, disarm it on `{stuck: false}`, on expiry call the extension's existing `restart(context)`, `extension.js:259`), through a new setting `ermine.preview.killAfterStuckSeconds` **defaulting to 0 = OFF until the WP-7 manual checklist has been run once**; that THE KILL MUST NOT SHIP WITHOUT (a) AND (b), because a client-initiated `stop()` is an EXPECTED close and so (INFERRED from the handler's documented purpose, **UNVERIFIED** -- the library's source was not read) is NOT counted by `vscode-languageclient`'s "crashed 5 times in the last 3 minutes" limiter, which makes the guard the SOLE bound; and that the mark be MIRRORED into `context.workspaceState` under `ermine.preview.wedge` beside `PICK_KEY`, restored in `restorePick` and discarded when its key does not match, with the module global still the authority for the live decision because `Memento.update` is async. **THE KEY FINDING THIS TICKET EXISTS FOR (READ from the code, 2026-09-20): THE LOOP IS REACHABLE TODAY** -- see Q17. **EVERY CLAIM ABOUT VS CODE'S OWN BEHAVIOUR IS UNOBSERVED BY ANYONE**: nobody on this branch has run the extension, and §2.11 and §2.13-2.14 of `tracker/WP-7-MANUAL-CHECKLIST.md` -- the steps that would first SHOW the loop -- have never been run. NOT BUILT AND NOT TO BE BUILT HERE: any server change, content hashing or mtime tracking, a new command, a modal, `globalState` or a file on disk, a map of marks, any backoff beyond the one grace. **CARRIED FOLLOW-UP, NOT WP-22's OWN WORK**: the restored `lsp/Preview.scala` still carries `325c3d09`'s forward references to WP-6 (`:100-101`, `:699`, `:2037`, and seven asides), whose promises WP-24 withdrew; WP-24 left the Scala byte-identical on purpose, so **the next change that touches `Preview.scala` -- this one, if it ever does -- corrects those comments in passing.** It is a comment edit and belongs to no ticket of its own | `node --test test/preview-core.test.js` green with the new table cases and two properties -- "an automatic `Running` re-render is issued only with a clear mark" and "an explicit render is never suppressed"; `node test/load-test.js` unchanged; **manual**: `tracker/WP-7-MANUAL-CHECKLIST.md` §2.7-2.14 re-run with a wedging report, showing that after the restart the tab does NOT re-render and the status bar reads `held`, that **Render anyway** renders and re-wedges, and that editing the report's module clears the mark | commit (`node --test`) + manual / ~1 day |
| WP-23 | **PARKED. DO NOT START: a server-side deliberate exit (the design review's "B-SRV").** If it is ever built: exit from the `java.util.Timer` thread only after `Wire.send`'s own `out.flush()` has returned (READ, `Rpc.scala:385-390`), **never** `Server.stop`, whose scaladoc says DISPATCH THREAD ONLY (READ, `Rpc.scala:490-497`); a free exit code (17 -- `Main` uses 0, 1 and 2, and the JVM's OOM path uses 3); discriminated by a last `ermine/preview/exiting {reason, seq}` notification and **NEVER by the exit code**, which `vscode-languageclient`'s documented close handling does not carry (*external*, UNVERIFIED); a grace long enough to leave Q10's recovery its chance, not the 1000 ms of WP-6; a setting `ermine.preview.exitOnWedgeSeconds`, default 0. **UNPARK TRIGGER, and nothing else**: a wedge observed where WP-22's client-initiated `client.stop()` did NOT kill the server -- one whose DISPATCH thread is also wedged. Nothing today can produce that: the dispatch thread answers a hover in 0.00 s while the preview is wedged (MEASURED, §2.5), `Preview.shutdown()` sets `stopping`, drains, cancels the timer and returns without joining the preview thread (READ), and the preview thread is a daemon. The shape that would never die is a BLOCKED preview thread, which WP-13/WP-14 make reachable | -- | -- **do not start** |
| WP-24 | **DONE 2026-09-20: WP-6 stage 1 REMOVED from the tree, by the user's decision (§13, Q13).** The instrument was `git checkout 325c3d09 -- <path>` for the four files stage 1 touched (`Runtime.scala`, `lsp/Preview.scala`, `session/Lib.scala`, `session/Session.scala`) plus `git rm scalacheck-binding/src/main/scala/TestPreviewCancel.scala`, and **NOT `git revert 0ee08425`**, which would have deleted the record (WP-20, WP-21, stage 2's figures, the amended rows) and undone two keepers. VERIFIED BEFORE THE CHECKOUT: `325c3d09` is `0ee08425`'s SINGLE PARENT and exactly one commit separates them, and all four files are byte-identical at `0ee08425` and at HEAD `9cdd4bac` (the two later commits, `92c974be` and `9cdd4bac`, touched only `tracker/`), so restoring from `325c3d09` reproduces the pre-WP-6 content exactly -- MEASURED afterwards with `git hash-object <path>` against `git rev-parse 325c3d09:<path>`, all four EQUAL, and `Runtime.scala` is 413 lines, 100 % CRLF, no bare LF. **KEPT AT HEAD CONTENT, UNTOUCHED**: `PreviewSupport.scala` (the shared harness `TestLspRobustness` imports), `TestLspRobustness.scala` (which carries the unrelated one-line order-dependence fix `bench.schema(58, gone, "report")`, Q16), the comments-only `extension.js` hunks of `0ee08425` (WP-7's two doc blocks, which say nothing about the cancel -- checked, no correction needed), `tracker/tools/eval-bench.sh`, `tracker/tla/`, and every tracker line. **THE RESTORED SOURCE CARRIES `325c3d09`'s OWN FORWARD REFERENCES TO WP-6, AND THEY ARE NOW FALSE PROMISES.** `lsp/Preview.scala` mentions WP-6 ten times; the three that promise behaviour are `:100-101` ("an evaluation that cannot be interrupted (WP-6 is what makes it interruptible)"), `:699` ("the work is not interrupted (WP-6 does that)") and `:2037` ("a loop nothing in the process can interrupt (WP-6 is the ticket that makes it interruptible)"); the other seven (`:137`, `:762`, `:975`, `:1090`, `:1095`, `:1110`, `:1118`) are design asides in the same direction. **EVERY ONE OF THOSE PROMISES IS WITHDRAWN** -- there is no ticket that makes an evaluation interruptible. **THE SCALA WAS DELIBERATELY NOT EDITED**: byte-identity with `325c3d09` is this change's evidence, and one comment edit would destroy it. Correcting those comments belongs to the NEXT change that touches `Preview.scala` (recorded in WP-22's row). Four comments in the two kept test files NAMED `TestPreviewCancel` as a live second suite. **THE THREE PRESENT-TENSE ONES WERE REWORDED -- COMMENTS ONLY, NO CODE** (`PreviewSupport.scala`'s header, `TestLspRobustness.scala:58-65` and `:1508-1511` -- **the committed-tree numbering, since ROBUST-3 commits first and adds lines above both**): each now says that the harness was extracted for a second suite, `TestPreviewCancel`, which WP-24 removed with WP-6's cancel, and that the extraction was KEPT because `TestLspRobustness` uses it. The fourth (`TestLspRobustness.scala:2069` in the committed tree, "EXPOSED BY, NOT CAUSED BY") is left exactly as it is: it is true as history. "`TestLspRobustness` unchanged" in the done-when means its BEHAVIOUR; both files are LF-only before and after (checked with a CR count) | `core/compile` + `core/Test/compile` green; the three kept suites RECOMPILED FROM SOURCE against the restored `Preview.scala` (MEASURED: `compiling 3 Scala sources`, COMPILE-OK), which is how "does anything kept depend on a member stage 1 added" was answered -- by compiling, not by reading; `TestLspRobustness` `Passed: Total 63, Failed 0, Errors 0` in 52 s (inside §11's 60 s cap for group D, which no longer serialises against a second preview suite) and `TestRunner` `Passed: Total 40, Failed 0, Errors 0` in 42 s; `editor/vscode`: `node --check` on both sources and `npm run test:preview` 39/39; `git grep -n -E "Cancelled\|cancelOnTimeout\|armCancel\|disarmCancel\|cancelArmedFor\|cancelTarget\|cancelWhy\|fireCancel\|firePhase2"` over `core/` finds only the pre-existing `Rpc.RequestCancelled` (-32800). The `pr` gate is the orchestrator's and runs once, after review | pr / ~2 h |
| WP-25 | **NOT BUILT. Found by ROBUST-3 (2026-09-20), the test-harness fix for the `pr` gate red on tree key `cae6f47f42cc3a6cf0c99b0c46e61f1a1d4ff890`; the DECISION TO BUILD IT IS THE USER'S (§13, Q20).** `Session.scrub` (`session/Session.scala:811-827`) is ASYMMETRIC and relies, unchecked, on its caller handing it a set of modules CLOSED UNDER IMPORTERS. `e.env` is filtered by the **V's own defining** `Global`'s module (`v.name`); `e.termNames`, `termNameOrigins`, `cons`, `privateCons`, `consOrigins`, `classes`, `classOrigins` are filtered by the **key's** module (READ). So a set that holds a DEFINER but not its RE-EXPORTERS removes the definer's `termNames` key and its `env` entries while every re-exported key survives pointing at a value that is gone: `Control.Monad.Functor`, `Control.Alt.Functor` and `Control.Ap.Functor` all still name `Control.Functor.Functor` after a scrub of `{Control.Functor, Maybe}`, and the next read of `Maybe.e:53` -- whose `Functor` collapses to the ORIGIN because two import paths reach it (`rename/ModuleScope.scala:67-78`) -- dies in `Subst.assertTermClosed` (`Subst.scala:1919`) with `undefined term`, inside a stdlib file the user never touched, rather than with an honest "not in scope". PROPOSED HARDENING, ONE LINE, so that any set is safe: after the `e.env` filter, `e.termNames = e.termNames filterNot { case (g, v) => (mine(g) && !b.termNames.contains(g)) \|\| !e.env.contains(v) }`. THE PIN, and it is a better test than trying to pin the race: *for any subset S of the loaded modules, after `scrub(e, builtins, S)` every `e.termNames` value is still in `e.env`* -- **MEASURED by ROBUST-3's probe: it FAILS TODAY on 13 of 30 random subsets** and the definer/re-exporter case reproduces the gate's exact message byte for byte. **THE TYPE SIDE IS UNVERIFIED**: `cons` / `privateCons` are keyed by module the same way while a `Con` carries its own module, so the shape looks identical, but no probe was run on it -- check it in the same ticket. NOT REACHABLE IN THE PRODUCT TODAY by the path ROBUST-3 found: in `bin/ermine-lsp` nothing removes a `Filesystem` key from `Session.depCache` (`lsp/Documents.scala:77`, `:111` evict `Buffer` keys only; the REPL's `reloadChangedModules` revert, `Session.scala:899-905`, is not in the server), so `dependentsOf` always has complete edges and the set is closed by construction. This is hardening against a class of caller, not a live bug | `core/test` green; the pin above passes for all 30 probe subsets and fails on the unhardened tree; the corpus and `lsp` gates unchanged | **pr** (session core) / ~half a day |
| WP-26 | **NOT BUILT, INFERRED BY READING AND NOT MEASURED, likelihood LOW. Found by ROBUST-3 (2026-09-20).** `Session.depCache` is PROCESS-GLOBAL and shared by the resident and the render session, but the staleness question it answers is PER SESSION: `Runner.staleFiles` (`json/Runner.scala:568-574`) asks `Session.depCache.get(sf).map(_._1) != sf.lastModified`. If the RESIDENT re-parses a file the render session has also loaded (the user edits it and the watcher fires), the SHARED entry is refreshed with the new mtime, and the render session's own scan then reports that file as CURRENT -- so the preview keeps serving the OLD module. That defeats §2.5's *"fresh files, whoever saved them"* for exactly the files both sessions hold, which is every stdlib module the report imports. SYMPTOM: usually a stale preview document. THE WORSE CASE, and the one that ties this to WP-25: if the refreshed entry also carries a CHANGED IMPORT LIST, `Session.dependentsOf` (`session/Session.scala:771-783`) loses a real importer edge -- it builds the graph from that same cache -- and the dirty set stops being closed under importers, which is the state WP-25 is about; the user would then see a 500 naming a file they did not touch. Needs an import line added or removed in a file BOTH sessions hold, which is why the likelihood is low. WHAT A MEASUREMENT WOULD BE (nothing cheaper is honest): boot a resident and a render session in one JVM over one root, render a report that imports a workspace module, edit that module (first its body, then its import list), let the RESIDENT reload it, then render again and assert the document followed the file -- a group-D property with a real `Resident` beside the bench, which group D does not have today. POSSIBLE SHAPES, neither designed: key the cache by session, or have `staleFiles` compare against what THIS session loaded rather than against the shared entry | a property of the shape above is RED before the change and green after; §2.5's row re-measured | **pr** / ~1 day, after WP-25 |
