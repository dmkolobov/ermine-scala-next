# JSON widget playground: edit a widget, see it rendered, inside VS Code

> **STATUS: WP-1, WP-2, WP-3, WP-4 AND WP-5 (STAGES A, B AND C) ARE BUILT; EVERYTHING
> ELSE IS DESIGN ONLY.** No other ticket has been started. WP-5 was built in three reviewed
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
| A non-terminating **evaluation** | pure Ermine loops run under `Runner.evalLock` (`Runner.scala:538-540`) and cannot be stopped from outside (*external*: `Thread.stop` throws on JDK 21). The honest promise: **a runaway evaluation blocks no LSP request until it exhausts the heap cap, then the server exits and the client restarts it**. A watchdog (`java.util.Timer`) answers the request after `ermine.preview.timeoutSeconds` (default 60) with "evaluation did not finish", in a notification carrying the **Ermine: Restart Language Server** button (`ermine.restartServer`, `extension.js:241`), marks the preview stuck, and every later `ermine/render` is answered the same way without queueing (**Q8, decided 2026-09-20**: those answers, and the watchdog's own, and the ones its queue drain sends, carry `"stuck": true`, and an `ermine/preview/stuck {stuck: true}` notification goes out beside the `window/showMessage`; **Q10, decided 2026-09-20**: the stuck state CLEARS if the job the watchdog fired on ever returns -- never on a `java.lang.Error` -- and a `{stuck: false}` notification plus an INFO `window/showMessage` then asks the client to re-render, because every `invalidate` posted during the wedge was dropped). An allocating loop (a fold over an infinite list; `swhnf` builds thunk chains as it goes, `Runtime.scala:215-238`) then hits `-Xmx` (§2.2) and `-XX:+ExitOnOutOfMemoryError` (*external*: since JDK 8u92) turns the OOM into a clean exit that `vscode-languageclient` restarts, up to 5 times in 3 minutes (*external*); the panel recovers as §7.2 describes. A CPU-bound loop pins one core for the process life until the user restarts (**MEASURED 2026-09-20: NO WITNESS EITHER WAY. Every loop that goes through `swhnf` reached `-Xmx` instead of pinning a core for ever, and the one candidate for a loop INSIDE a primitive did not spin at all. The claim is neither confirmed nor refuted; see the measured block below**). The resident keeps answering until then: it does not take `evalLock` and is on another thread. The watchdog exists so the user is told at 60 s rather than at OOM. WP-6 makes cancel real (next row) |
| Cooperative cancel (WP-6, gated on a perf A/B) | a `@volatile` cancel flag on a per-thread evaluation context, checked at the head of `Runtime.swhnf` (`Runtime.scala:215`): `if (cancelled) throw Cancelled`. The watchdog and an in-flight `$/cancelRequest` set it. The unwinding thunk writes `Bottom` back into the thunks on its chain (`:231`, `:238`), which poisons the render session's stdlib thunks, so a cancel **discards the `Runner`** (the next render boots a new one) and the runaway's chains become garbage; the resident is untouched. Cost: one volatile read per force on the evaluator's hot loop, hence a Tier-2 instrument run (`perf-bench.sh`, an interleaved A/B; it "has never moved", `docs/gate-policy.md:105`) before adoption. Unverified: that every Ermine loop passes through `swhnf` (a loop inside one primitive would not) |
| `$/cancelRequest` | queued: removed and answered `-32800`; in flight: marked, its eventual answer replaced by `-32800`, the work not interrupted until WP-6 (no hook into `SqlExecution` either way); during a boot: honoured when the boot ends (answer `-32800`, boot kept) |
| `stale` | a **hint**; `invalidated` is the mechanism. A `@volatile` generation counter is bumped by `invalidate`, snapshotted at render start and compared just before `send`; a mismatch sets `"stale": true`, and the `invalidated` notification that follows makes the extension re-render (§3). An `invalidate` that lands after the comparison is not lost, only its banner is late. **AS BUILT (WP-5 stage A), DIFFERS FROM THE LETTER ABOVE -- for the user to confirm**: the counter is bumped when an `invalidate` is **posted** (on the dispatch thread) and snapshotted when a render is **enqueued**, not when it starts. The literal reading cannot work on a single-threaded queue: an `invalidate` that ran as a job could never move the counter *during* a render, so `stale` would be dead code; and a snapshot taken at render *start* would call a render fresh that was enqueued before an invalidate still queued behind it. Bumping per post can flag a render whose invalidation turns out empty -- a false positive, which is what "a hint" permits. The WP-5 stage A review judged this strictly better than the literal reading |
| Boot progress | the first render **or schema** (Q7, decided 2026-09-20: a first pick boots on the SCHEMA request, which is exactly when the user is waiting, so a schema job mints its token through the same dispatch-side `mintBootToken` and under the same at-most-one-outstanding-`create` rule), and every post-discard boot, reports "Ermine preview: booting the render session" through LSP work-done progress (`window/workDoneProgress/create`, then `$/progress` begin / end, `cancellable: false`, *external*: LSP 3.15+), guarded by the client's `window.workDoneProgress` capability. The `create` request is sent by the dispatch thread when it enqueues the job (§2.3); the `$/progress` notifications go from the preview thread through the synchronised `send` |

What a restart costs, stated once: a fresh process, the ~13 s boot (`Resident.scala:24`),
every per-document inference cache (cold first check ~2.5 s against ~0.9 s warm,
`editor/vscode/README.md:117-118`), the workspace-symbol table, the held connection and its
`##` tables (§7.2), and the compiled report.

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
| 6 | extension | if the picked report's module is in `modules` (the set includes dependents, so saving `Layout/Widgets/Foo.e` names every report that imports it), re-send `ermine/render` with the last params, and re-request the params schema (§6). **Q11 (decided 2026-09-20, option (iii)): and ALSO re-render when the picked report's OWN FILE is created or changed while its last answer was a PLACEMENT 404**, which no `invalidated` can announce -- a file with no readable header has no module NAME for the notification to carry, and since Q5/Q7 it is refused at placement before `Runner` is ever asked. NOT on a `Runner` 404 (a missing BINDING on a module that loaded): that module is in `loadedModules`, so `invalidated` already fires for it and the extra trigger would double-render | new |
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
| `ermine/render` | request | `{uri, binding, params, roots, generation}` -> `{ok: true, document, generation, stale?}` or `{ok: false, status, message, path?, generation, stuck?}` | `uri` -> module via `Resident.moduleUnder(cfg.roots, path)`; a file that cannot be PLACED under any root is a **404 whose message says why** (Q5, decided 2026-09-20): it is not a `.e` file, it cannot be read, its module header does not parse, or its module name is deeper than the directories above it. A readable `.e` file whose header parses is always under its OWN inferred root (§2.4), so the 404 is unreachable for it -- which is why the old text, "not under a module root", was true of nothing. **THE 400 AND 404 TEXTS NAME THE FILE AND NEVER A DIRECTORY** (Q5's convention; the 409 below is the one exception and says why). `roots` are the absolute `ermine.preview.roots` (§2.4). Delivery is always inline, buffered, no threshold (`Runner.scala:72-80`): **no `data` field on this wire**. `status`/`message`/`path` are `RunError`'s (`Runner.scala:25-65`: `BadRequest` 400 at `:47`, `NotFound` 404 at `:51`, `Failed` 500 at `:55`): 400 with a JSON path for a bad param or a binding that is not a report (`:466-470`, `:472-476`), 404 for module or binding (`:447`, with the request's binding in the text), 500 for load, eval, scan, write, and for a document over the size cap (§2.3). **409 (Q7, decided 2026-09-20)** for a SHADOWED PICK: the final root chain resolves the picked file's module name to a different file, so neither this render nor a schema may use it, and nothing is loaded. **THE 409 IS THE ONE TEXT THAT PRINTS A PATH**, and the orchestrator's decision on the apparent contradiction with the sentence above is recorded here: Q5's file-name-only convention governs the 400 and 404 texts; the 409 prints the SHADOWING file's path and the root it sits under because that is the only useful thing it can say (the picked file is still named by its name alone -- the request supplied its URI), and rule A5 (§8.1) covers **URLs, hosts and passwords**, not a source path under a directory the client or the server configured as a module root. 409 costs no new vocabulary: `Preview.failure` takes a status NUMBER and `RunError`, which the HTTP server shares, is not on this path. The message never carries a JDBC URL (§8, rule A5). **`stuck: true` (Q8, decided 2026-09-20)** is present on EXACTLY the failures that mean §2.5's WEDGE -- the refusal `render` sends while stuck, the watchdog's own answer, and the answers its queue drain sends -- and on NOTHING ELSE, in particular not on the job crash handler's 500, which is a report that ran and failed. The `-32800` paths (a displaced render, a cancelled one, the shutdown drain, and the watchdog's answer to a request that had been CANCELLED) are JSON-RPC ERRORS with no result object, so they carry no marker and the client learns the state from `ermine/preview/stuck` instead. Answered through `onRequestDeferred` from the preview thread |
| `ermine/preview/reports` | request | `{uri}` -> `{module, reports: [{binding, type}]}` or `{error}` | §3.2; dispatch thread; a lookup, or one cold check for an unopened file |
| `ermine/preview/invalidated` | notification, server -> client | `{modules}` | §3 step 5 |
| `ermine/preview/stuck` | notification, server -> client | `{stuck: true \| false, message, seq}` | **Q8, decided 2026-09-20.** `true` from the watchdog's `fire` (TIMER thread), `false` from Q10's recovery (PREVIEW thread), each **beside** a `window/showMessage` and never instead of one -- the standard message is what any LSP client shows, this row is what a BANNER can hold. Both through `notify`, never `ask` (§2.3), outside the queue's monitor, guarded, scrubbed. WP-7's panel reads it, and the **Ermine: Restart Language Server** button is the panel's: the LSP shape that carries actions (`window/showMessageRequest`) is a REQUEST whose answer names the chosen action TO THE SERVER, and the protocol gives a server no way to make the client run the client-side `ermine.restartServer` (*external*, unverified here). **THE CLIENT CONTRACT, four rules (IM-1 of the Q8-Q12 review):** (1) `seq` is a monotonic counter minted in the SAME locked step that flips the state, so a client KEEPS THE HIGHEST `seq` IT HAS SEEN AND IGNORES ANYTHING LOWER -- the two edges are sent by different threads with nothing ordering them, and a collision really can put the `false` on the wire before the `true`. **`seq` IS PER-PROCESS AND RESTARTS AT 1**, so the client RESETS its high-water mark when the language client goes **Stopped -> Running** (§5's own row for that transition): a restart is the remedy the watchdog's message names, and a client that kept the old mark across one would ignore the fresh server's `{stuck: true, seq: 1}` for the life of its session (DD-2 of the second review); (2) this notification is **AUTHORITATIVE** for the stuck state; (3) the `"stuck": true` marker on an ANSWER is **per-request**, not a state: it says why THAT request was refused, and one stale stuck refusal may legitimately arrive after a clear (it was decided before it); (4) the `window/showMessage` that accompanies each edge is **advisory** and may arrive in either order relative to it -- it carries no `seq` and a client must not derive state from it |
| `ermine/schema` | request, extended | `{uri, binding, roots}` -> the schema, or `{error, stuck?}`, alongside `type`/`name` | **with a `binding` key the request is a preview-queue job** answered from the render session (§6); the `type`/`name` forms stay on the resident (`Schema.scala:807-816`). **Q7, decided 2026-09-20**: the binding form carries the same three keys a render identifies its report by, and resolves it through the SAME function, so a schema and a render share one session in either order. Its `{error}` texts are a render's reasons word for word -- Q5's "cannot read `<name>`", "no module header could be read from `<name>`", "not an Ermine source file: `<name>`", the 409 shadow text -- scrubbed, file names only. `{module, binding}` is GONE: a request with `binding` and no `uri` is `{error}` naming the key. **CONSEQUENCE FOR THE EXTENSION (WP-7/WP-8)**: because a schema now computes the root set the same way, a schema whose `roots` DIFFER from the last render's DISCARDS that session and boots another, exactly as a render with different roots does (§2.4). The extension must send the SAME `roots` on both, for the same picked report. **`stuck: true` (Q8) sits BESIDE `error`** on the two refusals that mean the wedge -- the one `schema` sends while stuck, and the one the watchdog's queue drain sends -- and on no other `{error}` |
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
| Recycling is the **extension's** reconnect | after N renders or T idle minutes (defaults in WP-14, Q2), on **Ermine: Disconnect Database**, or after a scan closes the connection, the server closes it and sends `ermine/preview/disconnected {reason}`; the extension, which has `SecretStorage`, sends a fresh `connect`. The server never reconnects on its own |
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
| Consequences of a Windows host | the extension host stays on Windows, so `SecretStorage` is backed by the OS credential store (*external*) and the JVM truststore is the Windows JDK's (`Windows-ROOT`, Q3, §7.3). Portability note, not a live question: on a Linux host `SecretStorage` is backed by the keyring (*external*) and the truststore by that JDK's `cacerts` |

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
| Render session | group D, under `residentLock` as B/C are (`:34`, `:307`) | render `Sales.report`; mutate the report file; `invalidate`; render again: the document differs. Mutate a **widget** module the report imports: the report is in the invalidated set. Render a module whose evaluation throws: the resident still answers a check (`Resident.checkFile`, `Resident.scala:401`) and the next render works. A `$/cancelRequest` for a queued render answers `-32800` and the queue is empty. `ermine/schema {uri, binding: "report", roots}` from the queue equals `exportNamed("Sales", "Query")` under the render env, on the session the render before it booted. `ermine/preview/reports` on `Sales.e` lists `report : Query -> Node` and nothing else. **(Q4)** A report whose LOAD failed is a 500 "does not load"; the file is fixed; `invalidate` of its path sends `ermine/preview/invalidated` NAMING it and the next render is `{ok:true}` with the fixed content. **(Q5)** The 404 for a file that cannot be placed names the cause -- "cannot read Gone.e" for a file that is not there, "no module header could be read from WpBadHeader.e" for one whose header does not parse. **(Q6)** Two fresh reports in two DIFFERENT directories, both named as `roots` on every request, render first / second / first again, all `ok:true`, and the session boots exactly ONCE across the three (counted from `Preview`'s own "render session booted" log line; each of the three properties runs on a bench of ITS OWN, not the group's shared one, because these requests move the root set and the shared bench's must never move). A report under NO configured root still renders and DOES re-boot, which is §2.4's zero configuration unchanged. One module NAME under two configured roots: the PICKED file is the one rendered, whichever root it is in. **(Q7)** A schema asked FIRST, on a fresh bench, boots the session and answers the params schema of a workspace report (`$id`, `$ref`, the four properties, the three required), and the render that follows answers `ok` -- ONE boot across both, counted from `Preview`'s own log line. `ermine/schema` with a `binding` and NO `uri` is an `{error}` naming the key, while the `type` and `name` forms still answer `ermine:Ord/Ordering` from the resident. A pick SHADOWED by a resident `moduleRoots` entry (the bench is given one of its own, holding a copy of the same module name) is `{ok:false, status: 409}` with no document, naming the picked file, the shadowing file and the root; the schema answers `{error}` with the SAME text; and a non-shadowed module on that bench still renders its own contents with no second boot. A pick that reaches its root THROUGH A SYMLINK, while the resident root holds the real spelling, still renders its own contents -- the `sameFile` tolerance of the review's must-fix -- or SKIPS LOUDLY with a `collect` label where the platform refuses symbolic links. The 400/404 property also pins the two bad-`roots` SHAPES the first cut dropped silently: `roots` that is not an array, and an entry that is not a string, are each a 400 naming `roots` and what kind of value it was, and the same refusal reaches `ermine/schema` in its `{error}` shape (that property now holds `residentLock` and forces the bench's `docs`: its Q7 half asks `ermine/schema` over the WIRE, and the handler exists only once `Definitions.install` has run -- see the row's note below). **(Q8, decided 2026-09-20)** The watchdog property now also asserts `"stuck": true` on the fired answer and on a later REFUSED render, an `ermine/preview/stuck {stuck: true}` notification, and -- the conjunct that catches the shared-`refusal` bug -- that a render SERVED after the recovery whose evaluation crashes carries NO `stuck` key; the crash-handler property carries the same negative conjunct on its own 500; the watchdog-drain and cancelled-then-wedged properties assert the marker on the drained schema's `{error}` and its absence from the `-32800` (which has no `result` at all). **(Q10)** The watchdog property now releases the wedged job and waits for `ermine/preview/stuck {stuck: false}` and an INFO `window/showMessage` asking for a re-render, then proves the state really ended by getting a THIRD render SERVED; the cancelled-then-wedged property does the same after its -32800. A property OF ITS OWN pins the other side of Q10(b): a wedged job released by throwing an `OutOfMemoryError` leaves the preview stuck, logs no "no longer stuck", and announces nothing -- read off a recording `notify` and a log after the preview thread has been JOINED. **(Q9)** One property, no bench and no boot, over `applySettings`: `0` sets the field and logs once; `3601` and an ill-typed `timeoutSeconds` are each refused out loud and leave the field alone. **(DM-1, as corrected by DD-1)** A property of its own, and the only one in the group that pays TWO boots, because nothing cheaper is a real witness (`discardSession` on a preview that never booted does nothing and logs nothing). FOUR scenarios on ONE booted bench, in an order that keeps the boot count unambiguous: **(a) the CONTROL** -- a wedged render that comes back `ok: true` must NOT discard and must NOT re-boot, and its recovery message must not claim a discard; **(b) THE REACHABLE CASE** -- a wedged render of `WpBoom` comes back with a 500 **by returning normally** (`threw` is false), and the recovery must log the discard and say so in its message; **(c)** the next render then really does boot (`boots` 1 -> 2, counted from `Preview`'s own log line); **(d)** a wedge released by THROWING discards too, at no extra boot. (b) is what the first cut got wrong and what the throwing scenario alone could never have caught. **(DM-2)** The `isFatal` property runs its scenario TWICE, once released by an `OutOfMemoryError` and once by a `ControlThrowable` -- the second is not an `Error` and is exactly what `isInstanceOf[Error]` alone missed. **(IM-1)** A property STAGES the notification collision rather than racing for it: the bench's `notify` parks the TIMER thread inside the `{stuck:true}` send until the preview thread has sent `{stuck:false}`, asserts the arrival order really was `false, true` (or the property is vacuous), and then asserts that the HIGHEST `seq` says `stuck:false` | **pr**; group D boots a render session, seconds each, MEASURED in WP-5 and kept under 60 s total or the suite is split. **MEASURED with Q7's four properties (2026-09-20), three runs**: **18.2 s** for `core/testOnly ...TestLspRobustness` ALONE; **25.7 s** and **46.7 s** for two runs of the same tree with `TestRunner` and `TestSchema` in the same JVM. The spread is CONTENTION, not Q7. **THOSE Q7 FIGURES WERE WRONG AND ARE CORRECTED HERE (2026-09-20, against the run's own log)**: the sentence said "the four Q7 properties cost 7.4 s of it (shadowed pick 1.6 s, two spellings 5.8 s, schema-first and the missing-uri case the rest)", which cannot be read at all -- 1.6 + 5.8 is already 7.4, leaving nothing for "the rest". The log says **shadowed pick 1.6 s, two spellings 5.8 s, schema-first 3.4 s, the missing uri 0.0 s = 10.8 s**, not 7.4 s. Meanwhile one pre-existing property, `ermine/schema {binding}`, took 16.3 s in that run against a fraction of that alone -- it holds `residentLock` while the other two suites take the process-wide `Runner.evalLock`, which is where the spread comes from. **RE-MEASURED 2026-09-20 WITH THE Q8/Q9/Q10 PROPERTIES**, four runs: group D was **34.7 s** for `core/testOnly ...TestLspRobustness` ALONE (61 properties, 47 s of suite wall time; that figure PREDATES the `docs`-ordering fix above and the review's own properties), and **34.4 s**, **18.6 s**, **37.5 s** on three runs with `TestRunner` and `TestSchema` in the same JVM (128 properties, 79 s / 59 s / 66 s). The **18.6-37.5 s** spread across runs of the SAME tree is the contention this row already describes and nothing else. The five properties added across the batch and its review cost **5.7 s between them**: `watchdog, the stuck state and the recovery` 0.3 s, `Q10: isFatal keeps the stuck state` 0.3 s, `Q9: applySettings on timeoutSeconds` 0.0 s, `IM-1: the stuck notification's seq` 0.3 s -- none of those four boots a render session -- and **`DM-1: the poisoned session is discarded` 4.8 s, which is two boots and is the whole of the increase**. **RE-MEASURED AGAIN AFTER THE BATCH'S TWO REVIEWS (2026-09-20)**, which added the DD-1, DM-2 and IM-1 properties: **23.2 s** and **40.4 s** for `core/testOnly ...TestLspRobustness` ALONE on two runs (63 properties, 46 s and 56 s of suite wall time). The 17 s between those two runs is not the new properties -- `DD-1: the poisoned session is discarded` cost 4.9 s in both -- it is **the RESIDENT's own ~13 s boot landing on whichever property forces it first**, which in the 40.4 s run was the pre-existing `Q7: the missing uri, and the resident's forms` (16.4 s there, 0.0 s when something else has already paid it). That is the same scheduling effect this row describes above, now with a named instance. *The combined figure for the final tree -- with `TestRunner` and `TestSchema` in the same JVM -- is reported to the orchestrator and deliberately NOT written here: it can only be known after the run that must be the last thing to touch this tree, and a tracker edit after a green run would break that rule.* **The 45 s line is not crossed on any run, and THE SPLIT IS THEREFORE NOT TAKEN.** It remains available if a later batch crosses it again: either group D moves to a suite class of its own, or it is cut into the queue/watchdog properties and the root-set ones (Q6 and Q7, each already on a bench of its own). **ONE PRE-EXISTING ORDERING HAZARD WAS SURFACED AND FIXED** while measuring this: the 400/404 property asks `ermine/schema` over the wire (Q7 gave it that conjunct) but never forced the bench's lazy `docs`, so a schedule that ran it before any property that does answered `-32601 unknown method: ermine/schema`; it now forces `docs` under `residentLock` like the three properties that already did. The 60 s ceiling in this row is not breached on any run | seconds to a minute |
| Runner | `TestRunner` (`:112`, `:806` already runs properties concurrently over one runner) | `invalidate` of an unloaded path is a no-op; `invalidate` then `render` reloads the module (loaded-set delta); two report-typed bindings in one module render two documents; `new Runner(cfg)` with an explicit `run` loads no JDBC driver (`CountingRun`, `TestRunner.scala:77`); **(Q4)** a module whose LOAD FAILED renders 500 and is named by the next `invalidate` -- of its own path, of the path of a broken module it IMPORTS, and of a loaded healthy module's path -- while a file under no root and a directory still name nothing, and the fix renders 200 and takes it back out; a module that is pending and then LOADED as another module's dependency is pruned and NOT named; a pending module whose file is DELETED is named while the file is there and not after the retry's 404 | **pr** | seconds |
| Emitters | `TestSqlEmitters` | the SQLite string for a windowed relation contains `over (`; no emitter output contains `TODO`; `UnsupportedOnDialect` for `tryCast` on SQLite | **pr** | seconds |
| Classifier | new, with a fake driver | §8.3 | **pr** | seconds |
| End to end | `tracker/tools/lsp-client.py`, run by `tracker/tools/lsp-smoke.sh` (`scripts/gates.sh:115-120`) | `reports`, render, edit, `invalidated`, render: differs; the schema binding mode on `Sales` (domain is `Query`); **(Q7)** the same binding request in its new shape (`uri`, `binding`, `roots`), and one more check: the schema of a SECOND report asked BEFORE any render of it -- §6's first-pick order -- placed in the SAME temp root so Q6's rule keeps the gate to one render-session boot | `lsp` (**commit**). **Q7 RE-MEASURED 2026-09-20, one direct run each side, exactly as `gate_lsp` runs it** (`with_own_classpath` from `target/ermine-classpath`, restored byte-identically, sha256 checked): **640 checks in 46.7 s before, 641 checks in 47 s after** -- one request changed shape, one check added, and the gate is still a `commit` gate by the same rule. **BUILT AND MEASURED 2026-09-20 (WP-5 stage C)**: 628 checks in 44.5 s before, 640 checks in 46.7 s after -- one preview boot of 1.6 s and one cold check of the copied `Sales.e`. The rule "if the gate passes ~90 s it moves to `pr`" is NOT triggered, so the gate stays at `commit` and `scripts/gates.sh` is unchanged. Under `docs/gate-policy.md` §5 ("gates must catch their mutants ... whenever a gate's definition or scope changes"): the gate's DEFINITION (`gate_lsp`) and its `GATE_SCOPE` string are both unchanged -- checks were added INSIDE `lsp-client.py`, and the files they newly reach (`lsp/Preview.scala`, `lsp/Definitions.scala`) were already inside `$E/lsp/*.scala` -- so the declaration needs no edit, and the gate's catch surface can only grow (before this, no smoke request reached `Preview.scala` at all). The harness was NOT run here: its lanes check out HEAD and run HEAD's `tracker/tools`, so it must follow the commit. The command is `scripts/mutate-and-verify.sh --gates lsp --classes obo,swap,guard,mapord -n 1 --seed 2` | ~1 min |
| Host page | `client` `npm test` (the existing harness plus the `applyMessage` reducer, §5) | every message sequence the extension can send leaves a consistent state (no document and a banner, or a document and its dimming flag) | new `gate_client` in `scripts/gates.sh`, entering at **nightly** per policy; promotion after one recorded catch | seconds |
| Instruments | results written into this document, never gate evidence | the credential gate (§8.4); the `##` count (`tempdb.sys.tables`) after an hour and after Disconnect; RSS and boot seconds before/after preview boot (§2.2); heap after a watchdog fire (§2.5); the bundle checklist (§5); the `perf-bench.sh` A/B for WP-6 | none | human / machine-dependent |

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
| Q1 | which global the writers bundle puts on `window` (`htmlwriter` vs `ermine_htmlwriter`) | WP-11 |
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
| Q13 | a stuck preview takes the WHOLE SERVER down at `-Xmx` about two minutes after the watchdog fires (MEASURED, §2.5), which is not the story §2.5 tells | nothing; decide with WP-6 |
| Q14 | a render that fails by a TRANSIENT error leaves that failure MEMOISED in the render session's thunks, so a binding of a module nobody edits re-throws the old error for the life of the session | nothing; decide with WP-12/WP-13 |

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
the directories above it"), which `Preview` answers before `Runner` is asked. **A 404 from
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

**Q13 IS STILL OPEN AND IS THE USER'S.** Nothing below chooses among (i), (ii) and (iii); it
records what the questions decided on 2026-09-20 changed about the ground Q13 stands on, so
that whoever answers it is not reading a stale map.

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
| WP-6 | cooperative cancel: the flag checked at the head of `Runtime.swhnf`, set by the watchdog and by an in-flight `$/cancelRequest`; the `Runner` discarded on cancel | a looping render is cancelled within a second and the next render boots a new session; the resident's tables are unchanged; **adopted only if** the `perf-bench.sh` interleaved A/B shows no movement (instrument, written here) | pr + instrument / ~1 day; gated |
| WP-7 | extension: **Ermine: Preview Report...** as a (file, binding) picker over `ermine/preview/reports` with per-workspace memory and free-text fallback, **Ermine: Render Report to JSON** into an untitled editor tab, `ermine.preview.roots` (resource scope, absolutised), re-render on `invalidated`, the `ermine.maxHeap` export; **(Q11, decided 2026-09-20) re-render when the picked report's own file is created or changed while its last answer was a PLACEMENT 404** (not a `Runner` 404: that module loaded, so `invalidated` already covers it and a second trigger would double-render) -- no server change, and the only residual case the notification cannot cover; **(Q8/Q10) the stuck banner of §5**, fed by `"stuck": true` on a refusal and by `ermine/preview/stuck`, carrying the **Ermine: Restart Language Server** button and clearing on `{stuck: false}`; **(Q9) the `ermine.preview.timeoutSeconds` and `maxDocumentBytes` exports, with "0 = no watchdog" in the setting's description** | on `core/src/test/resources/doc/Sales.e` with no setting the picker offers `report : Query -> Node`; the tab shows a 400 naming `$.params.fromDay` (WP-8 turns it into a document); saving `Sales.e` updates the tab with no restart; no webview | manual + commit smoke / ~1 day |
| WP-8 | params: `.ermine/preview/<Module>/<binding>.params.json`, the skeleton from the schema on first pick, `<binding>.schema.json` beside it with a relative `$schema`, `$schema` stripped before sending, re-render on save, the orphan message, the one `.gitignore` line | `Sales` renders a document on first pick with no hand-written JSON; completion and a red squiggle for a wrong key in `Sales/report.params.json`; saving it re-renders; renaming the binding shows "no params for"; `git status` shows the params file and not the schema | commit smoke + manual / ~1 day |
| WP-9 | webpack browser bundle: config, `npm run bundle` / `bundle:watch`, `devtool: 'source-map'`, output under `client/dist/browser/` | `npm test` unchanged; the bundle checklist of §5 passes under a CSP without `unsafe-eval` | nightly (`npm test`) + checklist / ~half a day |
| WP-10 | webview panel: host page, CSP, `localResourceRoots`, the `applyMessage` reducer and its `node --test`, banner states (initial, error, stale, unsaved, switching, offline, fast mode), `retainContextWhenHidden`, bundle watcher -> reload; `gate_client` registered at nightly | `Sales` renders inline; editing `client/src/widgets/scorecard.ts` updates the panel without a restart; a 400 from a bad param shows `path` in the banner; the reducer property passes; `scripts/gate.sh run nightly` runs `gate_client` | nightly + manual / ~2 days |
| WP-11 | Q1 and the legacy renderers in the panel | `table` renders through `runTabular`; the global's name is written into `client/src/index.ts` and `legacy.ts` | checklist / ~half a day |
| WP-12 | `mssql-jdbc` `jre11` in `build.sbt`; one real connect to the work server from the preview; `sqlPrimT`'s `"date"` mapping checked; Q3 answered | a connect succeeds (MEASURED, with the truststore answer written into §7.3); the first-connect TLS behaviour is recorded as observed | instrument / ~half a day plus the wait for the server |
| WP-13 | profiles (user scope only) + `ermine/preview/connect` + the four-way classifier with `kept` + `Throwable` catch and scrub + URL credential refusal + `SecretStorage` keyed by `sha256(url + "\0" + user)` + trace-`verbose` refusal in the one `connect()` + **Forget Database Password**; no `untrustedWorkspaces` declaration; the Settings-Sync answer written into §8.2 | the credential gate (§8.4) passes in full; the fake-driver classifier test passes; a workspace-scope profile is ignored and named once | pr + instrument / ~2 days |
| WP-14 | held connection lifecycle: the §7.2 switch sequence, Disconnect command, `disconnected` notification, extension-driven reconnect, re-render after every connect, recycling defaults (Q2), reconnect on `Running`, status-bar item `id (dialect) @ host`, the file-backed SQLite profile documented. **THE CLOSE THIS TICKET PUTS IN `discardSession` MUST NOT BLOCK** (review S3, 2026-09-20): Q10's recovery calls `discardSession` from `runJob`'s `finally`, AFTER `disarm()`, so it runs with no watchdog over it and with the stuck state ALREADY CLEARED -- a `Connection.close()` that hangs on a dead socket would wedge the preview thread in a state nothing would fire on and nothing would refuse. It is free today (`DelegatingRun.clear()` closes nothing); this ticket owns giving that close a timeout, or moving it off the preview thread | a 1-hour session against MSSQL leaves no `##` tables after Disconnect (count in `tempdb.sys.tables`, MEASURED); a profile switch mid-render discards the old answer; killing the server and letting the client restart it ends in a rendered document; no password *field* in `lsp/Preview.scala` (code review), the driver's `Connection` acknowledged to hold it until close | instrument + manual / ~1.5 days |
| WP-15 | SQLite emitter gaps: `EmitOver_UsingOver` mixin, bracket names, parenthesised joins | `TestSqlEmitters` pins each string; a windowed report previews on SQLite with rows | pr / ~half a day |
| WP-16 | engine gaps: `UnsupportedOnDialect` at the §9.2 sites, 500 banner, deploy-dialect badge | no emitter output contains `TODO`; `tryCast` on SQLite shows the banner naming `tryCast` and `sqlite` | pr / ~1 day |
| WP-17 | closed-environment packaging: vendored `client/node_modules` or internal registry, driver jar offline, `bin/ermine-lsp.cmd` (and a PowerShell twin) with `resolveServer` choosing it on Windows. **THE WINDOWS WRAPPERS MUST CARRY THE JVM POLICY, not just the classpath** (Q12, 2026-09-20): `-Xmx${ERMINE_LSP_XMX:-2g}` with the 64m floor, `-XX:+ExitOnOutOfMemoryError`, AND `-XX:+DisplayVMOutputToStderr` behind the same cached, java-keyed probe `bin/ermine-lsp` uses -- §10 says the deployment machines are Windows, so that is exactly where Q12's unframed OOM line on the protocol channel matters, and today neither the flag nor the cap reaches them | a fresh clone on a work machine runs WP-7 and WP-10 with no network and no WSL; the credential gate passes on Windows | manual / ~1 day |
| WP-18 | docs: `docs/JSON-GUIDE.md` §9/§10/§12 (the guide's `Runner.scala:259-280` reference at `:1571` has drifted to `:287-288`), `client/README.md` "Adding a widget" (`ermine/schema` from the render session replaces eleven boots), `editor/vscode/README.md` | the three documents describe the loop as built; MEASURED figures replace the mined ones here | none / ~half a day |
| WP-19 | **optional, out of the loop**: dual-emit T-SQL diff in the panel via `dumpRel` / `dumpClosed` | only if relation authoring in the panel is asked for | -- |
