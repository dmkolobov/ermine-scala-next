# Ermine LSP roadmap — loop state file

This file is the durable state for the /loop driving the LSP work. Each
iteration: read this file, do the next unchecked item, verify against the
baselines, commit, tick the box, append one line to the iteration log.
Design forks not settled under "Decisions" go under "Blocked/Awaiting" and
stop the loop. Full rationale: tracker/TICKET-scoping-renamer.md (LSP
section) and tracker/TICKET-perf-type-inference.md (latency work, needed
before type-at-point features).

Status: Stage 1 — 2.3b done (terms+patterns, 2929 real stmts); next item 2.3c (types+statements) · Seeded 2026-08-30 (session that shipped the
scoping fix, commits f9cf42a / 41b13cc).

## Baselines (hard invariants — never commit red)

- `sbt -batch core/test`: all green except `Constraints.disjunction sound`
  (the one known pre-existing failure, tracker/06-tests.md) — 761/762 as of
  Stage 0; suites GROW, so a commit that adds tests updates the count in
  its iteration-log line, and green-except-the-known-one is the invariant
- `tracker/tools/repl-smoke.sh`: all suites PASS (3 as of Stage 0)
- `tracker/tools/lsp-smoke.sh`: all checks PASS (27 as of Stage 0)
- All 129 stdlib modules load with type checking on (~6s warm, bin/ermine)
- Toolchain: export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
- KNOWN FLAKE: core/test suites run concurrently in one JVM and rarely
  interfere (seen 2026-08-30 twice: TestMarkdown errored at 0.1;
  TestStage1Pins+TestScopes at 1.3b — different suites each time, always
  green on re-run and in isolation). Protocol: a red that is not the
  known Constraints failure gets ONE re-run before diagnosis; if it
  reproduces, it is real — do not commit.

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
- [x] **0.6 Hover**: for a resolved name at position, show the inferred
  type from the session env (the :type machinery in Console is the
  reference); top-level and imported names only — local binder types are
  Stage-1+ territory (see perf ticket before promising type-at-point).
- [x] **0.7 Editor wiring + demo**: a 10-line VS Code/eglot config snippet
  in docs/ or the ticket; record a full demo transcript (the 0.4 client
  run) below under "Gate evidence".

**GATE G0**: demo transcript recorded here; baselines green; then STOP the
loop and summarize for sign-off before Stage 1.

## Stage 1 — parse/rename separation, LSP-shaped surface AST

G0 signed off 2026-08-30. Plan of record: tracker/TICKET-scoping-renamer.md.
Checklist expanded 2026-08-30 from a 6-reader code sweep + 3-critic
adversarial review (workflows wf_f1abd102 / wf_acc10f56; full reports in
the session tool-results). Pipeline of record:
parse (resolution-free, spans, flat chains, sugar kept as nodes)
-> rename (occurrence->binder/def-site tables + scope-at-position)
-> fixity re-association (positional env, region overrides)
-> desugar -> typecheck (Session.loadModule contract frozen).
Old and new pipelines COEXIST until after G1 (Decision d below); the fused
machinery is deleted post-G1, never before.

### Stage-1 Decisions (append-only; override with a note, not silently)

- (a) Block-binder fixity keeps today's textual-order asymmetry through G1
  (a binder's `(infixl 5 op)` groups only uses parsed after it). Whole-block
  Haskell semantics is tracked post-G1 debt.
- (b) Import-bypassing global-mode desugar resolution (Syntax.Do.bind,
  Field.cons, Builtin.primNeg/Nil/::, Relation.*, Function.id/.) is
  reproduced as-is for G1; revisit after.
- (c) Top-level shadow refusal stays negative (TestScopes #17 guards it).
- (d) REPL/eval/Remote stay on the fused pipeline through G1. The new
  pipeline is reachable via a module-load switch (-Dermine.pipeline=new,
  built in 4.1); cutover + machinery deletion are post-G1 items.
- (e) Module-level fixityStatements replay in textual order for G1 parity
  ("Multiple fixity definitions" and "forward reference to an operator
  with unknown precedence" must fire exactly as today; Vector.e-style
  as-affix workarounds must keep parsing). Whole-module pre-scan: post-G1.
- (f) Rejection-vs-acceptance parity is GATE-HARD; error text/position
  parity is gate-hard only where lsp-smoke or the Diagnostics regex
  depends on it ("ill-formed expression", the "file:line:col:" prefix);
  other message/anchor drift is recorded in the iteration log, not red
  (commit points move when resolution mutations leave the parser).
- (g) Interface-backed loading under the new pipeline is out of Stage-1
  scope; one warm interface-backed reload layer runs at 4.2, and the full
  round-trip is a precondition of the post-G1 REPL cutover.
- (h) Synthesized-node locs use Synthesized(originSpan), never borrowed
  locs; 3.4 preserves expansion SHAPE bit-for-bit, locs follow this
  policy (the oracle layers are loc-insensitive). Death reports over
  synthesized locs must still render "file:line:col:" for the regex.

### 1.x Gate and spec groundwork (no pipeline code before these)

- [x] **1.1 G1 oracle harness**: one-line patch sorting Dep.writeInterface
  lines by name (Session.scala:424-427; parse-back is order-insensitive).
  tracker/tools/g1-diff.sh PARAMETERIZED old|new: delete every .ei under
  classes/modules, one full-inference bin/ermine boot (writes .ei, dumps
  :browse and :groups), normalize, compare. Comparator: parsed-type
  alpha-equivalence for ALL lines via InterfaceParsers (byte-equal as fast
  path only; constraint sets compared as multisets under one consistent
  variable bijection — never string-sort, never scalaz Equal[Type]);
  the same normalization applies to the :browse dump. Validation BOTH
  ways: (i) old-pipeline double-run must self-agree 129/129 THROUGH the
  comparator with zero file skips (the 5 order-churn files +
  Relation/Predicate.ei are its acceptance tests, not exemptions; use
  -Dermine.loadInSeries if churn defeats it); (ii) mutation tests — a
  dropped constraint, Int->Long, inconsistently renamed exists binder,
  reordered quantifiers, a missing line must each flag red. The script
  asserts 129 .ei files and ~1473 lines per side and full-inference
  evidence (wall >10s) before any diff counts. Baseline snapshot commits
  to tracker/g1-baseline/ as a DRIFT TRIPWIRE only (see 4.2).
- [x] **1.2 Reword gate G1** (edit the GATE line below into the roadmap):
  normalized .ei equivalence + :browse + :groups (binding-group SCCs;
  124/129 via G1Groups, 5 deterministic PARSE-ERROR markers per 1.1) +
  occurrence->def-site differential (see 4.2 — the direct resolution
  oracle) + AST-level desugar differentials (3.4) + value-level eval
  fixtures (4.1/4.2) + rejected-program corpus + 1.3 property corpus
  under BOTH pipelines + the 32 non-boot modules via core/test's
  all-modules property + relArrows modules and Math.e asserted
  specifically + one warm interface-backed reload of the new pipeline.
- [x] **1.3a Spec pins: scoping quirks** (properties against the OLD
  pipeline, in scalacheck-binding behind a pipeline-parameterized fixture
  so they re-run under the new one at 4.1): class-body scoping incl.
  classPrivateBlock/localTypes kind-arg/context scoping and the
  OMGWTFPolarBear silent-discard branch (record: keep or diagnose);
  do-binder unbind-before-rhs/rebind-after; where-body-parsed-first;
  ?[...]/Remember occurrence visibility; qtyp/closed implicit type
  quantification (TypeParsers.scala:271-310: which vars quantify, the
  snapshot boundaries, "improperly quantified variable" refusal, same
  type-var name across two sigs); pattern binders shadowing both maps;
  interleaved-equations adjacency (gatherBindings grouping vs sig
  floating vs missing/duplicate errors); error-in-sugar anchors (one type
  error inside each of do, list literal, record, relArrows — anchor
  parity or a Decision noting the accepted delta).
- [x] **1.3b Spec pins: operators + rejected corpus + importing golden**:
  prefix/postfix chains (incl. trailing postfix); block-binder fixity
  textual-order; ambiguous imported operator (silent at term level, loud
  at type level); unary minus over the whole chain; equal-prec
  mixed-assoc "ambiguous operator of precedence"; "Multiple fixity
  definitions" vs imports; forward-reference-unknown-precedence;
  postfix+infix bucket collision. Rejected corpus (acceptance parity is
  gate-hard per Decision f): unknown op in chain, ambiguous reference,
  "would shadow global definition", ':'-constructor binder, alias-capture
  refusals (flip at 4.4), loaded-but-not-imported global reference
  (typecheck-time failure today — the termNames-superset leak test),
  unknown plain identifier (placeholder tolerance), missing bracket/brace
  hooks (today: warn + backtrackable failure other alternatives can mask
  — record actual acceptance). importing(): capture harness + golden
  outputs of ErParseState.importing over all 129 module headers PLUS a
  synthetic corpus (multi-alias same-module, hiding+rename, using {},
  duplicate-import die()); the differential assertion against the new
  pure function executes in 3.1.
- [x] **1.4 Hook table + roadmap bookkeeping**: write and commit
  tracker/desugar-hooks.md — every desugar hook (name, fixity, _Module
  suffix rule, source module, resolution channel: alias-sensitive /
  loaded-global / relArrows-region) per the desugaring inventory; the
  relArrows override applies to combine/filter sub-expressions ONLY,
  never rename arrows. Confirm the Decisions block above is in force.

### 2.x Surface syntax

- [x] **2.1 Surface AST** (new package surface/): header nodes (imports
  participate in layout; duplicate-import die() covered); the 10
  top-level statement forms + 6 foreign sub-forms + FixityStatement KEPT
  + where as its own node + ErrorStatement(span, diag); terms/patterns/
  types mirroring core's 20/15/10 plus sugar-only nodes (DoExpr,
  ListLit/BraceLit with _Module suffix, RecordLit, RelEnvelope with
  per-arrow kind, Neg, Hole, RememberBracket, sections, Paren, flat
  OpChain = interleaved operand|op-occurrence with lexeme-as-written +
  span + syntactic position-class); type-level ->/=>/<- as chain ops
  (pseudo-fixities 0R/0R/1N), row/quantifier forms. Spans everywhere;
  occurrences carry surface spelling incl. alias affix and
  paren-operator form; foreign sub-forms carry the class-name STRING +
  span only (Class.forName leaves parsing — resolution moves to 3.2b).
- [x] **2.2 Tokenizer parity**: port the op lexer byte-for-byte (3 guards,
  maximal munch, `_Module` affix as one token, backtick/apostrophe ops vs
  double-backtick literal idents; keep DataConParsers' ':'-lexeme split —
  lexical, safe); property-test against the old `op` parser over all
  stdlib sources.
- [x] **2.3a Parser: header + statements + layout** onto the surface AST —
  no name maps, no insert-on-miss, no LocalBlocks, no mid-parse fixity;
  statement order preserved verbatim; the five-way '{' disambiguation
  rules (record vs brace-list via '=', kind-arg blocks, row types,
  explicit layout) as an explicit documented deliverable; skip-to-layout-
  boundary recovery primitive designed (activation is Stage 2).
- [x] **2.3b Parser: terms + patterns** (flat chains, sugar nodes,
  BraceLit accepts zero elements — the fieldList empty-brace crash dies
  by construction; renamer rejects instead).
- [ ] **2.3c Parser: types + data/class/foreign statements** (quantifier/
  row forms, kind-arg braces, class blocks).
- [ ] **2.3d Parse differential**: all 180 .e files parse (161 stdlib +
  19 core/examples — user-style surface variety the stdlib lacks); the
  1.3b rejected corpus re-checked (refusals that move to rename time are
  recorded as such); '{' rules and missing-hook acceptance verified
  against the corpus.

### 3.x Rename, re-associate, desugar

- [ ] **3.1 Module scope as a pure function**: replicate importing()
  (using/hiding, localized rename-then-affix, |+| alias merge,
  collapseNames incl. singleton-skip, origins); the 1.3b golden
  differential goes green HERE. Distinguish real scope (canonicalTerms
  domain) from the session-global termNames superset — scope-at-position
  must not leak loaded-but-unimported globals (1.3b corpus asserts).
- [ ] **3.2a Renamer: module-level terms**: binder heads collected before
  rhs resolution; id-unification classes preserved (sig+forwards+
  equations share one id; one id per pattern binder shared with term
  refs); outputs: occurrence->binder, binder->def-site with spans,
  scope-at-position, each occurrence recording resolved binder + import
  path + origin global (collapseNames only collapses multi-alias names —
  hover labels need origin); unresolved names keep placeholder tolerance.
- [ ] **3.2b Renamer: local scopes + diagnostics**: let/where/do/class/
  patterns per the 1.3a pins (LocalBlocks/checkShadows/subTerm repair
  made unnecessary by construction — but NOT deleted, Decision d);
  classLookup/Class.forName relocated here (error text/position
  preserved; classMap global-state dependency noted); failures are Death
  with "file:line:col:" rendering (Diagnostics regex + no(...)/
  sessionProof compatibility).
- [ ] **3.2c Renamer: types + kinds**: canonicalTypes/typeNames/kindNames
  tables; qtyp/closed quantification-set computation reproduced exactly,
  asserted by the 1.3a pins; kindOf/kindAfter twin lands with it.
- [ ] **3.3 Fixity re-association**: port shuntingYard from
  ParsingUtil.scala:385-440 (Op.scala is a commented-out duplicate — do
  not port it) as a pure pass over flat chains, exact clear/finish
  semantics and "ambiguous operator of precedence" verbatim; positional
  fixity env (imports via Name, fixity statements per Decision e, block
  binders at textual position per Decision a, relArrows override set);
  prefix/postfix by recorded position class; unary minus = primNeg over
  the ENTIRE re-associated chain; type-level pseudo-fixities with
  Forall/Part/flattenConstraints construction moved to desugar; decide
  sys.error("termL2...") -> diagnostic; "ill-formed expression" message +
  anchor preserved as a design constraint (lsp-client update happens at
  4.3, not here).
- [ ] **3.4a Desugar after rename: literals/negation/list-patterns/
  records** — per tracker/desugar-hooks.md channels; expansion SHAPE
  bit-for-bit (foldRight lists/records/list-patterns, EmptyRecord at
  open-brace loc), locs per Decision h; AST-level differential per sugar:
  revive TestRelations.scala:193-214's tnodes-equality shape — old fused
  desugar output vs new post-rename output, id/loc-insensitive.
- [ ] **3.4b Desugar: bracket/brace hooks + do** (alias-sensitive channel
  with _Module suffixes; reverse-foldLeft do, Lam(WildcardP) effect
  statements, last-statement-is-expression; missing-hook acceptance per
  1.3b corpus); tnodes differentials for both.
- [ ] **3.4c Desugar: relArrows** — region-scoped referent+fixity
  override on combine/filter sub-expressions ONLY (never rename arrows;
  1.3b fixtures place a rebound op and `not` in each arrow kind and
  adjacent to the envelope); col/prim rewrite keyed on renamed binders,
  descent-stop set preserved exactly; Function.id for empty envelopes.

### 4.x Integration, convergence, LSP rebase

- [ ] **4.1 Typecheck integration + pipeline switch + fixture twins**: new
  pipeline feeds Session.loadModule's frozen contract incl. the type/kind
  side (ps.s.typeNames consumption, Session.scala:812-816); a module-load
  switch (-Dermine.pipeline=new) reachable from bin/ermine routes module
  loading through the new pipeline while REPL command parsing stays fused
  (Decision d) — this is what makes g1-diff.sh old|new real; ErmineFixture
  parameterized over pipelines; testParse gets a differently-typed twin
  (callers pattern-match core nodes). TestScopes + TestErmine + the 1.3
  corpus green under BOTH pipelines EXCEPT TestScopes :130/:133, which
  are expected-fail (accepted, not refused) under the new pipeline until
  4.4 — listed exemption, not a regression. Value-level eval fixtures for
  each relocated sugar land here (they need eval through the new
  pipeline).
- [ ] **4.2 Differential convergence**: SAME-COMMIT dual boots (old + new,
  ~28s) are the primary comparison; tracker/g1-baseline is a drift
  tripwire only (old-vs-baseline mismatch STOPS the loop for explanation,
  never a silent re-cut). Layers: normalized .ei + :browse + :groups +
  occurrence->def-site differential (dump sorted occ file:line:col ->
  def file:line:col per module from the old typed core — Var occurrence
  locs share def ids — and from the new renamer's tables; diff across
  all 180 files (stdlib + examples); this is the direct resolution oracle AND 4.3's spec) +
  scope-at-position differential at sampled stdlib positions vs the old
  canonicalTerms-domain snapshot + warm interface-backed reload of the
  new pipeline (boot #2 consumes boot #1's .ei, 129 modules clean,
  Decision g) + eval fixtures + rejected corpus. Iterate until dry.
- [ ] **4.3 LSP rebase onto the renamer**: Definitions.index +
  Resident.checkFile rebuilt on occurrence->binder/def-site tables
  (delete the re-parse and the self-global filter, Resident.scala:83-96);
  real spans replace point+len hit-tests; add a positive local
  goto-DEFINITION check (newly enabled); hover on locals STAYS null —
  local binder types are gated on tracker/TICKET-perf-type-inference.md,
  not on the renamer; "ill-formed expression" checks updated in the same
  commit if the message moved (Decision f); all lsp-smoke checks green
  (count grows; update Baselines note per its rule).
- [ ] **4.4 Flip the alias-refusal tests (new pipeline only)**: TestScopes
  :130/:133 -> positive Haskell semantics under the new-pipeline
  parameterization (old-pipeline run keeps refusal expectations for
  exactly these two); add the combined-capture property (id_F untouched
  AND plain id captured, one program) and the positive
  letrec-early-reference-through-plain-name case. NO machinery deletion,
  NO scoping.in edit here (post-G1).

**GATE G1**: every 1.2 layer green; 1.3 corpus + TestScopes(+flips) green
per the 4.1 exemption rule; baselines green (delta-tolerant per the
Baselines section); old pipeline still serving REPL. STOP the loop and
summarize for sign-off before Stage 2.

**Post-G1 tracked debt** (not Stage 1; do not start without sign-off):
REPL/eval/Remote cutover to the new pipeline (precondition: interface
round-trip test per Decision g) -> scoping.in aliased-shadow line -> delete
LocalBlocks/checkShadows/rewriteShadowed/insert-on-miss/Localized threading
(Localized removal is its own item — it threads through every binder
production) -> fold bindingName/localName -> block-binder whole-block
fixity + module-level pre-scan flips (Decisions a, e) -> statement-extent
scanner for Stage 2 (columns/strings/comments/bracket+let-in/case-of
closers; flag the virtualLeftBrace col-max-depth merge corner) -> revisit
import-bypassing desugar resolution (Decision b).

## Stage 2 — error-tolerant parsing feeding the same surface AST

After G1. Sketch only: recovery at layout boundaries (statement extents
are lexically determined — same fact the block-re-parse correctness
argument rests on), error nodes into the Stage-1 AST, diagnostics keep
flowing mid-keystroke; then incremental reuse per unchanged statement.

## Blocked / Awaiting

(empty — G0 signed off 2026-08-30, user: “keep going”)

## Gate evidence (G0, recorded 2026-08-30)

Demo = the 0.4 scripted client run (`tracker/tools/lsp-smoke.sh`), 27/27:
server booted via the same entry point `bin/ermine-lsp` wires into editors
(docs/lsp.md has the eglot/VS Code snippets). Protocol excerpts, uris
abbreviated:

- initialize -> `{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"textDocumentSync":{"openClose":true,"change":0,"save":true},"definitionProvider":true,"hoverProvider":true},"serverInfo":{"name":"ermine-lsp","version":"0.1"}}`
- boot (interface-free): `session: ready — 129 modules in 12.8s`
- didOpen Bad.e -> `{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:…/lsp-tests/Bad.e","diagnostics":[{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}},"severity":1,"source":"ermine","message":"…/lsp-tests/Bad.e:4:1: error: failed to unify type Int with type St…`
- definition of `&&` (Nav.e) -> `{"jsonrpc":"2.0","id":5,"result":{"uri":"file:…/classes/modules/Bool.e","range":{"start":{"line":7,"character":0},"end":{"line":7,"character":2}}`
- hover on `twice` -> `{"jsonrpc":"2.0","id":9,"result":{"contents":{"kind":"plaintext","value":"Nav.twice : forall a. a -> a"}}}`
- misses answer null; didClose clears; no .ei written next to fixtures.

Baselines at gate: core/test 761/762 (known Constraints failure only),
repl-smoke 3/3, lsp-smoke 27/27. Commits f0ba9b4 (0.1), 0f3a12c (0.2),
d3bde88 (0.3), 3665e06 (0.4), 0b8f30e (0.5), a978805 (0.6), + this one
(0.7). Stage 0 complete — loop stopped for sign-off per the gate.

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
- 2026-08-30 0.6 done: hover in lsp/Definitions.scala off the same index —
  DocIndex gains id -> (label, Type): termNames Vs carry their inferred
  type as the V payload (extract), rendered per request with
  Pretty.prettyType(ty, -1) as plaintext "Module.name : type"; the file's
  own top-levels (fresh re-parse ids) bridge by name via
  Local.global(moduleName) into termNames. Locals answer null (Stage-1
  per roadmap; perf ticket gates type-at-point). Rendered samples:
  "Good.answer : Int", "Nav.twice : forall a. a -> a"; && labels as
  Prelude.&& (re-export; termNameOrigins could refine — polish, not now).
  lsp-smoke 27/27; baselines 761/762, repl 3/3.
- 2026-08-30 0.7 done: bin/ermine-lsp launcher (classpath cache like
  bin/ermine, JAVA_HOME defaulted to the toolchain — bare `java` isn't on
  editor PATHs), docs/lsp.md (server description, eglot mode+wiring,
  VS Code thin-client snippet, harness pointer), launcher smoke-tested by
  handshake, demo transcript recorded under Gate evidence. Baselines:
  761/762, repl 3/3, lsp 27/27. STAGE 0 COMPLETE — stopping the loop at
  gate G0 for sign-off.
- 2026-08-30 Stage 1 expanded into 24 items via 6-reader sweep +
  3-critic adversarial review (~1M tokens of workflow evidence). Headline
  corrections vs the seed sketch: G1 "byte-identical .ei" is unachievable
  (ids thread-timing-dependent; 6/129 files churn between identical runs)
  -> normalized alpha-equivalence + layered oracles incl. a direct
  occurrence->def-site resolution differential; resolution failures steer
  today's grammar -> rejected-program corpus is gate-hard; the fused
  machinery CANNOT be deleted pre-G1 (old pipeline serves REPL + oracle)
  -> deletion moved to post-G1 debt; a -Dermine.pipeline switch (4.1) is
  what makes the oracle able to measure the new pipeline at all; qtyp/
  closed implicit quantification and relArrows region boundaries pinned
  as spec tests before any pipeline code. Baselines section made
  delta-tolerant (was stale at 17/17). Loop resumes at 1.1.
- 2026-08-30 1.1 done: writeInterface sorted by name; G1Compare (boots for
  the type parser, parses both sides via a new InterfaceParsers.interfaceSigs
  with all-module importing + cons++privateCons recognizedCons, alpha-eq
  with positional forall binders / search-matched exists+Part multisets);
  G1Groups (dedicated SCC dump — REPL :groups can't re-parse most loaded
  modules; own-global-filtered re-parse works for 124/129, the 5 stubborn
  ones — Field, Native.List, String, Type.Eq, Relation — are deterministic
  PARSE-ERROR markers, gap documented, covered by 4.2's occ->def oracle);
  g1-diff.sh run/compare + g1-normalize (browse wrap-joining) +
  g1-validate + 7 mutation fixtures (incl. eq-reordered-forall: Forall.mk
  canonicalizes binder order — presentation, not semantics). Found en
  route: parallel makes give thread-timing Supply draws that reach .ei
  bytes through the solver's id-hash queue as genuinely non-alpha-equiv
  residual constraints (lookbackJoin) — added -Dermine.loadInSeries gate
  (default off) and the oracle runs serial. Validation: fixtures 7/7,
  double-run self-agreement 129/129 EQUIVALENT (1447 sigs, 1672 browse
  entries, groups identical). Baseline committed to tracker/g1-baseline/.
  Baselines: 761/762, repl 3/3, lsp 27/27.
- 2026-08-30 1.2 done (bookkeeping): the reworded gate shipped with the
  checklist expansion; layer list updated for 1.1's findings (serial-load
  oracle runs, groups 124/129 + 5 markers). All oracle mechanics live in
  tracker/tools/g1-*.
- 2026-08-30 1.3a done: TestStage1Pins.scala, 19 properties pinning the
  fused pipeline where the stdlib differential is blind. Discoveries worth
  the item on their own: (1) CLASS BODIES ARE DEAD — every member sig/
  default and every context dies in loadModule with "undefined type";
  only bare `class C a` / `class C {a}` load (no stdlib witness ever
  existed; pins record refusal as the spec — resurrecting classes is not
  Stage-1 business); (2) `data D = MkD a` LOADS but the constructor is
  unusable (rigid skolem !a refuses MkD 5), and `type T = a` loads too —
  the "improperly quantified variable" diagnostic has no trigger we could
  find (1.3b corpus TODO); (3) witnessed the ambiguous-operator silent
  term-level failure live (`+` under Prelude+Primitive dies as a layout
  error) and pinned it. Also pinned: do-binder unbind-before-rhs (by
  value, via maybeMonad) and rebind-after (by type, both directions),
  where-body repair, pattern-binder alias survival, per-sig implicit
  quantification, interleaved-equation refusal, error anchors on the
  right line inside list literals and do blocks. Error-in-sugar anchors
  for records and relArrows ride 1.3b with their fixtures. core/test now
  781 (780 green + known Constraints failure); repl 3/3; lsp 27/27.
- 2026-08-30 1.3b done: TestStage1Pins grows to 34 (all green; core/test
  796). Operator family pinned by probe-then-pin: prefix ops need the
  `(prefix op)` binder form and stack only parenthesized; postfix binds
  by precedence incl. trailing; unary minus CONFIRMED whole-chain by
  value (f q = -q + 1; f 5 = -6); block-binder inline fixity refuses
  earlier siblings / governs later ones; "ambiguous operator of
  precedence" and "Multiple fixity definitions" verbatim; op-before-
  fixity and unknown-op die as layout errors (the reader-cited "forward
  reference to an operator with unknown precedence" message was NOT
  reproducible — noted in the pin). Corpus: missing bracket hooks
  ("expected '_' or whitespace"), loaded-but-unimported global and
  unknown identifier both parse then die "undefined term" (placeholder
  tolerance pinned). G1Importing tool + tracker/g1-importing-golden.txt:
  per-module sha256 of sorted canonicalTerms/Types over all 129 headers
  (deterministic across runs) + full dumps for synthetic using/hiding/
  using-{} headers. Discovery: importing one module twice — even under
  different aliases — is REFUSED ("Duplicate module imports not correctly
  handled"), so multi-name visibility arises only via re-exports; the
  refusal is part of the golden. Deferred: record/relArrows error anchors
  (ride 3.4 fixtures), improperly-quantified trigger still unfound.
- 2026-08-30 flake note: the 1.3b commit's full-suite run showed 2
  extra reds (a stage1 pin + a TestScopes property, exception flavor);
  clean 795/796 on immediate re-run — concurrency flake, second sighting.
  Protocol added to Baselines. The commit's code was green.
- 2026-08-30 1.4 done: tracker/desugar-hooks.md committed — every hook
  verified against the code (not the reports): channels A/G/R, the exact
  relArrows rebinding sets with forced fixities, and the grammar-level
  proof that the R-region wraps combine/filter arms only (relArrow
  :137-141 applies bindingPredCombs/bindingOpCombs to those two
  alternatives; rename parses outside the wrap). Decisions block
  confirmed in force. GROUNDWORK (1.x) COMPLETE: oracle validated both
  ways, 34 spec pins, importing goldens, hook spec. Next: 2.1 surface
  AST — the build phase begins.
- 2026-08-30 2.1 done: surface/Surface.scala — the full what-was-written
  AST: Span (half-open, 1-based, hit-testable) + Real/Synth SLoc per
  Decision (h); SName keeps spelling-as-written (incl. _Module affix)
  with NameForm (Plain/ParenOp/(prefix op)/(postfix op)/(infixl 5 op)
  binder) and the syntactic fixity bucket; generic flat Chain[A] of
  operand|OpOcc with syntactic PosClass (used by term, pattern, and type
  chains — ->/=>/<- ride the type chains as pseudo-ops); all sugar as
  nodes (SDo/SListLit+suffix/SBraceLit/SRecordLit/SRelEnvelope with
  per-arrow kinds/SNeg/SHole/SRemember); error nodes in all four ADTs;
  statements mirror the 10+6 core forms with SFixity KEPT in-tree, SWhere
  as its own node attached to equations/alts, foreign forms carrying
  class-name strings+spans only; SModule preserves statement order
  verbatim. TestSurface (3 structural props) locks Span arithmetic and
  composability; field adjustments as 2.3's parser meets reality are
  expected. Baselines: core/test 799 (798+known), repl 3/3, lsp 27/27.
- 2026-08-30 2.2 done: surface/Lexer.scala — the op lexer as a pure
  function, character classes verbatim (opChars/nonopChars/unicode punct
  classes), affix-in-lexeme, three guards, the three op-start flavors
  (term/datacon-':'-only/patvar-non-':'), and one deliberate quirk kept:
  '_' after op chars with no tail char fails the WHOLE op (the fused
  parser commits into the affix group; skipOptional cannot rewind).
  TestSurfaceLexer: stdlib sweep (every op-char offset of all 161
  sources x 3 flavors, old-success => same-new-lexeme, >10k comparisons)
  + crafted corners both directions (affixes, dead underscore, |], key
  ops, dash-comment threshold, unicode MATH_SYMBOL, backtick/apostrophe
  ops). All green first run. Bonus find while reading NameParsers: the
  "forward reference to an operator with unknown precedence" message
  DOES exist (opName) but is raised via backtrackable fail(), so
  alternatives always swallow it — that is why 1.3b could not reproduce
  it and why users see layout errors instead. Baselines: core/test 801
  (800+known), repl 3/3, lsp 27/27.
- 2026-08-30 2.3a done: surface/SurfaceParsers.scala — Parsing[Unit]
  instantiation (same generic layout engine as the fused pipeline, no
  state for name maps to hide in); full header grammar (module/import/
  export, as-aliases, using/hiding items with renames); fixity
  statements parsed for real; every other statement captured by the
  per-char offside splitter as a classified placeholder with exact
  extent (the splitter IS Stage 2's recovery primitive). Two bugs found
  by the parity tests: the offside check must never fire on leading
  whitespace (continuation lines broke at col 1), and the test's own
  fixity regex counted a declaration inside Eq.e's block comment.
  TestSurfaceParsers: headers agree with ModuleParsers across all 161
  files (names, imports, aliases, flags, item sets); splitter covers
  every file, fixity counts match an independent regex, spans ordered.
  tracker/surface-notes.md records the five-way '{' rules, the span-end
  caveat, and the explicit-layout placeholder. Baselines: core/test 803
  (802+known), repl 3/3, lsp 27/27.
- 2026-08-30 examples coverage (user feedback): the lexer and 2.3a
  parity sweeps now include core/examples/*.e (19 files; Holes,
  relational examples, bugs/ regression cases) — 180 files total, all
  green with no changes needed to the parser. The old pipeline's example
  behavior was already baseline-protected (core/test's all-examples load
  property); the NEW pipeline now sweeps them too, and 2.3d/4.2 are
  reworded to 180 files. Examples reach new-pipeline TYPE checking at
  4.1 (the parameterized fixture runs the load-all properties under both
  pipelines).
- 2026-08-30 2.3b done: full term + pattern grammars in SurfaceParsers —
  flat chains via adjacency-classified OpOccs, whole-chain SNeg, do/let/
  case/lambda, list/brace/record literals (record-vs-brace by '=' after
  first item, per surface-notes), relational envelopes with per-arrow
  kinds, holes/?[..], literal idents (``x``), paren-op references (.),
  as-patterns/strict/lazy/list patterns, ':'-chains; sigs and term/pattern
  annotations capture their type extents raw (comment- and string-aware
  scanner; pattern sigs stop at top-level '->' only OUTSIDE parens).
  Debug trail worth keeping: opTok slice over-grab broke 0.0/0.0; the
  '|'-before-']' lexer guard needs the REAL stream, not the slice (broke
  every [| |] envelope); col-1 comment lines are whitespace to the
  splitter; stale bol after block-comment whitespace; trailing-comment
  commit needed item-level attempt. Sweep: 180 files, ZERO file failures,
  2929 statements parse for real, zero binding placeholders outside two
  legacy files the OLD pipeline also rejects (Sample.e, guide/HelloWorld.e
  — verified via parseModule; exemptions documented in the test).
  Remaining placeholders are 2.3c's statements (private/data/type/field/
  foreign). Shape properties added (chain classes, neg, do, rec/brace,
  arrow kinds, nested pattern sig). Baselines: 804 (803+known), repl 3/3,
  lsp 27/27.
