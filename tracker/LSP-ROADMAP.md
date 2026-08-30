# Ermine LSP roadmap — loop state file

This file is the durable state for the /loop driving the LSP work. Each
iteration: read this file, do the next unchecked item, verify against the
baselines, commit, tick the box, append one line to the iteration log.
Design forks not settled under "Decisions" go under "Blocked/Awaiting" and
stop the loop. Full rationale: tracker/TICKET-scoping-renamer.md (LSP
section) and tracker/TICKET-perf-type-inference.md (latency work, needed
before type-at-point features).

Status: Stage 0 in progress — 0.5 done · Seeded 2026-08-30 (session that shipped the
scoping fix, commits f9cf42a / 41b13cc).

## Baselines (hard invariants — never commit red)

- `sbt -batch core/test`: 761/762 (Constraints.disjunction sound is the
  known pre-existing failure, tracker/06-tests.md)
- `tracker/tools/repl-smoke.sh`: 3/3 suites
- `tracker/tools/lsp-smoke.sh`: 17/17 checks (from 0.4 on)
- All 129 stdlib modules load with type checking on (~6s warm, bin/ermine)
- Toolchain: export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH

## Decisions (pre-made; overridable with a note here, not silently)

1. **Protocol layer: hand-rolled.** The build has NO JSON dependency
   (scalaz only, and the migration branch is dependency-conservative);
   the needed LSP subset is small. Write a minimal JSON reader/printer and
   Content-Length JSON-RPC framing by hand. Revisit (lsp4j or a JSON lib)
   only if the subset outgrows ~initialize/didOpen/didChange/didSave/
   publishDiagnostics/definition/hover/shutdown.
2. **Location: inside core.** New package
   `core/src/main/scala/com/clarifi/reporting/ermine/lsp/` — no build.sbt
   changes, and `bin/ermine`'s cached classpath already covers it. A
   separate sbt subproject is Stage-1 business if ever.
3. **Concurrency: strictly single-threaded request handling.** SessionEnv
   is not thread-safe (its own scaladoc in TestErmine.scala says so).
   One request at a time off a queue; no exceptions.
4. **stdout is the protocol channel.** All logging to stderr or a file —
   the resident Session's Printer must not write to stdout (Console's
   banner/progress printing must be suppressed or redirected).
5. **The whole server runs useInterface=false** (added at 0.5; boot went
   ~7s -> ~13s, once). Checks: a stale .ei lets loadModule skip body
   inference (missed errors) and writebacks litter workspaces (found at
   0.4). Navigation: interface-loaded modules carry .ei-text locs, so
   stdlib jumps would land in interface files instead of sources.

## Stage 0 — diagnostics-on-save server with best-effort navigation

Checklist (each item ≈ one loop iteration):

- [x] **0.1 Scaffold**: `lsp/Rpc.scala` — minimal JSON model + parser +
  printer, Content-Length framing over stdio, request/notification
  dispatch loop, `initialize`/`initialized`/`shutdown`/`exit` handshake
  advertising: textDocumentSync (save + open), definitionProvider,
  hoverProvider. `lsp/Main.scala` entry point. Log file via system
  property. Verify with a hand-fed transcript (printf piped in), the way
  tracker/repl-tests does it.
- [x] **0.2 Resident session**: boot a SessionEnv the way ErmineFixture
  and Console do (Lib.preamble; typeCheck on; load Prelude+Layout once,
  ~6-12s, during `initialize` — report readiness via window/logMessage).
  Copy-per-request like ErmineFixture's `mkEnv` so a failed load never
  poisons the resident env. Printer must not touch stdout (Decision 4).
- [x] **0.3 Diagnostics on open/save**: didOpen/didSave of a `.e` file →
  parse+typecheck it against a session copy (Session.loadModule path; see
  also Console.scala:369 reloadChangedModules for the reload-on-change
  shape). Map Death/parse failures to LSP Diagnostic: scalaparsers
  positions are 1-based line/column — LSP is 0-based; the report body
  carries the caret text if a range is unavailable (end = start is fine).
  Clear diagnostics on a clean load. Files that import other workspace
  files: resolve imports against the file's directory (Console's
  loadArgs/fsloader machinery) — if this turns rabbit-hole, ship
  stdlib-imports-only first and note it here.
- [x] **0.4 Scripted client + smoke test**: `tracker/tools/lsp-smoke.sh` +
  a small python client speaking the framing; scenario: initialize, open
  a good file (no diagnostics), open a file with the variableShadow-style
  error pre-fix era... use a type error (e.g. `f : Int` / `f = "s"`),
  assert one diagnostic with the right line, shutdown. Wire into the
  repl-smoke pattern (PASS/FAIL lines). This is the regression harness
  for everything after.
- [x] **0.5 Go-to-definition (same file, then imports)**: keep the parsed
  Module + typed bindings per open document; hit-test Var occurrence
  Locs against the request position; answer the V's loc — termDef
  relocates each V to its actual definition site already
  (TermNameParsers.scala globalTermDef comment). For imported globals,
  answer the defining module's file+loc via the session's module map
  (SourceFile knows filenames). Misses answer null, never error.
- [ ] **0.6 Hover**: for a resolved name at position, show the inferred
  type from the session env (the :type machinery in Console is the
  reference); top-level and imported names only — local binder types are
  Stage-1+ territory (see perf ticket before promising type-at-point).
- [ ] **0.7 Editor wiring + demo**: a 10-line VS Code/eglot config snippet
  in docs/ or the ticket; record a full demo transcript (the 0.4 client
  run) below under "Gate evidence".

**GATE G0**: demo transcript recorded here; baselines green; then STOP the
loop and summarize for sign-off before Stage 1.

## Stage 1 — parse/rename separation, LSP-shaped surface AST

Do not start before G0 sign-off. Plan of record in
tracker/TICKET-scoping-renamer.md; sizing discussion from the review
session: surface AST (spans everywhere, error/hole nodes designed in, flat
op chains), renamer with occurrence->binder tables + scope-at-position as
first-class outputs, fixity re-association incl. prefix/postfix, desugaring
relocation (do-notation, list literals, relational sugar — the hard part).
Differential gate G1: typed ASTs byte-identical across all 129 stdlib
modules vs the old pipeline (.ei artifacts as oracle) + baselines + the 28
TestScopes properties, with the alias-refusal tests flipped to positive
Haskell-semantics tests. Expand into a checklist when opened.

## Stage 2 — error-tolerant parsing feeding the same surface AST

After G1. Sketch only: recovery at layout boundaries (statement extents
are lexically determined — same fact the block-re-parse correctness
argument rests on), error nodes into the Stage-1 AST, diagnostics keep
flowing mid-keystroke; then incremental reuse per unchanged statement.

## Blocked / Awaiting

(empty)

## Gate evidence

(empty)

## Iteration log

- 2026-08-30 seeded; no LSP code exists yet.
- 2026-08-30 0.1 done: lsp/Rpc.scala (hand-rolled JSON model+parser+printer,
  Content-Length framing, single-threaded dispatch) + lsp/Main.scala
  (initialize advertises openClose/save sync + definition + hover; shutdown
  gates later requests; exit codes per spec). Verified with a framed printf
  transcript: capabilities, -32601, -32700 resync, post-shutdown -32600,
  exit 0. Baselines: 761/762, smoke 3/3, 129 modules 5.8s. (First core/test
  run also errored TestMarkdown; gone on re-run and alone — flake, watching.)
  Note for 0.2: bin/ermine's progress bar writes to stdout — must be muted.
- 2026-08-30 0.2 done: lsp/Resident.scala — SessionEnv(_typeCheck=Some(true))
  + Lib.preamble + loadModules(Prelude,Layout), booted on `initialized` on
  the dispatch thread (initialize answers fast; queued requests wait behind
  boot); withEnv runs each request on a baseEnv.copy (mkEnv idiom); boot
  failure logs + window/logMessage type 1 and leaves it unbooted for retry.
  Session Printer feeds the log (progress bar split on \r), and Main steals
  System.out — protocol keeps the real fd, stray prints land in the log
  (covers Logging.initializeLogging's println and log4j console appender).
  Verified from $HOME (cwd-independent, classpath loader): stdout pure
  frames, "ready: 129 modules in 6.7s" logMessage, exit 0. Baselines:
  761/762 (no TestMarkdown flake this run), smoke 3/3, 129 modules.
- 2026-08-30 0.3 done: lsp/Diagnostics.scala + Resident.checkFile —
  didOpen/didSave/.e-gated: Session.load(Filesystem(path, exotic)) against
  a fresh env copy with SourceFile.filesystem(fileDir) prepended to the
  loader chain, so workspace-sibling imports resolve (no stdlib-only
  fallback needed). Death's rendered report leads "file:line:col:" —
  regexed back out, 1-based→0-based, end=start, caret text kept in the
  message; other-file/positionless reports anchor 0:0; didClose clears.
  Verified by transcript: type error Bad.e 4:1→(3,0), parse error Ugly.e
  3:5→(2,4) via didSave, Sib→Good sibling import clean, clear-on-close,
  ~0.0s per warm check. Baselines: 761/762, smoke 3/3.
- 2026-08-30 0.4 done: tracker/tools/lsp-smoke.sh + lsp-client.py (binary
  framing; fixtures tracker/lsp-tests/{Good,Bad,Ugly,Sib}.e) — 17 checks:
  capabilities, 129-module readiness, clean/type-error/parse-error lines,
  didSave path, sibling import, clear-on-close, shutdown/exit. Found and
  fixed a real 0.3 bug en route: checks ran with useInterface on, so a
  Foo.ei newer than Foo.e made loadModule skip body inference (missed
  errors after e.g. git checkout) and writebacks littered the workspace —
  Resident.checkEnv now pins useInterface off for checks (boot keeps
  interfaces for warm speed); harness asserts no .ei droppings. lsp-smoke
  is now a baseline: run it alongside core/test + repl-smoke from here on.
  Baselines: 761/762, smoke 3/3, lsp-smoke 17/17 twice.
- 2026-08-30 0.5 done: lsp/Definitions.scala + checkFile re-parse. The
  parser already resolves names: references are `v at occurrencePos` (same
  id as the def; termVar/termOp), termNames Vs sit at true def sites
  (globalTermDef), pattern binders share ids (mkLocalPatternVar) — so the
  index is one tree walk (occurrences by position + local def targets)
  over env.termNames globals, and definition = hit-test + two map lookups.
  Module AST comes from re-parsing the body after the check load, seeded
  with the module's own globals filtered out (first attempt self-shadowed
  every definition: "would shadow global definition Good.answer").
  Decision 5 added: whole server interface-free, else stdlib def locs
  point into .ei text. Misses answer null. lsp-smoke +6 checks: same-file
  equation, pattern binder, sibling Good.e, stdlib Bool.e (&&), miss, all
  green. Baselines: 761/762, repl 3/3, lsp 23/23.
