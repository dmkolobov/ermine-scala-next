# Ermine LSP roadmap — loop state file

This file is the durable state for the /loop driving the LSP work. Each
iteration: read this file, do the next unchecked item, verify against the
baselines, commit, tick the box, append one line to the iteration log.
Design forks not settled under "Decisions" go under "Blocked/Awaiting" and
stop the loop. Full rationale: tracker/TICKET-scoping-renamer.md (LSP
section) and tracker/TICKET-perf-type-inference.md (latency work, needed
before type-at-point features).

Status: STAGE 2 COMPLETE — AWAITING GATE G2 SIGN-OFF (2026-08-31).
5.1-5.5 done; 5.6 DEFERRED with evidence (see its entry).  The read path
is error-tolerant end to end, reports every phase's diagnostics, blames
syntax errors where the parser actually gave up, the splitter is TOTAL,
checking runs on open BUFFERS as they are typed, TYPE checking reports
every independent error including in the healthy part of a broken file,
and unchanged binding components are no longer re-inferred.
NEXT: nothing — the loop stopped at G2.  Say the word to open Stage 3. · Seeded 2026-08-30 (session that shipped the
scoping fix, commits f9cf42a / 41b13cc).

## Baselines (hard invariants — never commit red)

- `sbt -batch core/test`: all green except `Constraints.disjunction sound`
  (the one known pre-existing failure, tracker/06-tests.md) — 761/762 as of
  Stage 0; suites GROW, so a commit that adds tests updates the count in
  its iteration-log line, and green-except-the-known-one is the invariant
- `tracker/tools/repl-smoke.sh`: all suites PASS (4 as of D2)
- `tracker/tools/lsp-smoke.sh`: all checks PASS (98 as of the 2026-09-02
  declaration-navigation work; it read 82 before that, the G2 line's 77
  having gone stale)
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
- [x] **2.3c Parser: types + data/class/foreign statements** (quantifier/
  row forms, kind-arg braces, class blocks).
- [x] **2.3d Parse differential**: all 180 .e files parse (161 stdlib +
  19 core/examples — user-style surface variety the stdlib lacks); the
  1.3b rejected corpus re-checked (refusals that move to rename time are
  recorded as such); '{' rules and missing-hook acceptance verified
  against the corpus.

### 3.x Rename, re-associate, desugar

- [x] **3.1 Module scope as a pure function**: replicate importing()
  (using/hiding, localized rename-then-affix, |+| alias merge,
  collapseNames incl. singleton-skip, origins); the 1.3b golden
  differential goes green HERE. Distinguish real scope (canonicalTerms
  domain) from the session-global termNames superset — scope-at-position
  must not leak loaded-but-unimported globals (1.3b corpus asserts).
- [x] **3.2a Renamer: module-level terms**: binder heads collected before
  rhs resolution; id-unification classes preserved (sig+forwards+
  equations share one id; one id per pattern binder shared with term
  refs); outputs: occurrence->binder, binder->def-site with spans,
  scope-at-position, each occurrence recording resolved binder + import
  path + origin global (collapseNames only collapses multi-alias names —
  hover labels need origin); unresolved names keep placeholder tolerance.
- [x] **3.2b Renamer: local scopes + diagnostics**: let/where/do/class/
  patterns per the 1.3a pins (LocalBlocks/checkShadows/subTerm repair
  made unnecessary by construction — but NOT deleted, Decision d);
  classLookup/Class.forName relocated here (error text/position
  preserved; classMap global-state dependency noted); failures are Death
  with "file:line:col:" rendering (Diagnostics regex + no(...)/
  sessionProof compatibility).
- [x] **3.2c Renamer: types + kinds**: canonicalTypes/typeNames/kindNames
  tables; qtyp/closed quantification-set computation reproduced exactly,
  asserted by the 1.3a pins; kindOf/kindAfter twin lands with it.
- [x] **3.3 Fixity re-association**: port shuntingYard from
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
- [x] **3.4a Desugar after rename: literals/negation/list-patterns/
  records** — per tracker/desugar-hooks.md channels; expansion SHAPE
  bit-for-bit (foldRight lists/records/list-patterns, EmptyRecord at
  open-brace loc), locs per Decision h; AST-level differential per sugar:
  revive TestRelations.scala:193-214's tnodes-equality shape — old fused
  desugar output vs new post-rename output, id/loc-insensitive.
- [x] **3.4b Desugar: bracket/brace hooks + do** (alias-sensitive channel
  with _Module suffixes; reverse-foldLeft do, Lam(WildcardP) effect
  statements, last-statement-is-expression; missing-hook acceptance per
  1.3b corpus); tnodes differentials for both.
- [x] **3.4c Desugar: relArrows** — region-scoped referent+fixity
  override on combine/filter sub-expressions ONLY (never rename arrows;
  1.3b fixtures place a rebound op and `not` in each arrow kind and
  adjacent to the envelope); col/prim rewrite keyed on renamed binders,
  descent-stop set preserved exactly; Function.id for empty envelopes.

### 4.x Integration, convergence, LSP rebase

- [x] **4.1 Typecheck integration + pipeline switch + fixture twins**: new
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
- [x] **4.2 Differential convergence**: SAME-COMMIT dual boots (old + new,
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
- [x] **4.3 LSP rebase onto the renamer**: Definitions.index +
  Resident.checkFile rebuilt on occurrence->binder/def-site tables
  (delete the re-parse and the self-global filter, Resident.scala:83-96);
  real spans replace point+len hit-tests; add a positive local
  goto-DEFINITION check (newly enabled); hover on locals STAYS null —
  local binder types are gated on tracker/TICKET-perf-type-inference.md,
  not on the renamer; "ill-formed expression" checks updated in the same
  commit if the message moved (Decision f); all lsp-smoke checks green
  (count grows; update Baselines note per its rule).
- [x] **4.4 Flip the alias-refusal tests (new pipeline only)**: TestScopes
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

**Post-G1 debt checklist** (G1 signed off 2026-08-30; do in order):
- [x] **D0 Interface round-trip test** (Decision g precondition): a
  repeatable test — new-pipeline load with useInterface on writes .ei
  into a temp workspace, a FRESH session warm-loads from them, and the
  warm session's types/env answers match the cold session's.
- [x] **D1 REPL/eval/Remote cutover**: Session.eval (expressions) and
  the statement paths route through SurfaceParsers+Renamer+Reassoc+
  Lower against session scope; Console commands keep their own parsers.
- [x] **D2 scoping.in aliased-shadow line**: document the semantics
  change (alias-capture programs now legal).
- [x] **D3 delete fused scoping machinery**: LocalBlocks, checkShadows,
  rewriteShadowed, insert-on-miss placeholders.
- [x] **D4 Localized threading removal** (resolved by the D3 deletion:
  every TERM binder production died; Localized survives only inside the
  kept interface-type/kind grammar, where it is load-bearing and inert).
- [x] **D5 fold bindingName/localName** (moot: deleted with the grammar).
- [x] **D6 whole-block fixity + module-level pre-scan flips**
  (Decisions a, e).
- [x] **D7 statement-extent scanner for Stage 2** (columns/strings/
  comments/bracket+let-in/case-of closers; flag the virtualLeftBrace
  col-max-depth merge corner).
- [x] **D8 revisit import-bypassing desugar resolution** (Decision b:
  bypass RETAINED by design — the stdlib is written against it; the
  desugar target module must simply be loaded in-session, which
  dependency loading guarantees).

## Stage 2 — error-tolerant checking in the editor (checklist, planned 2026-08-31; adversarially reviewed by two critics, findings integrated)

GOAL: the LSP keeps producing diagnostics and navigation while the file
is broken and while it is being typed; then unchanged code stops being
re-inferred.  Foundations in place: the surface parser is statement-
tolerant (per-item `.attempt` + rawStatement -> SErrorStatement with
exact extents), and surface/StatementExtents is the pure lexical extent
scanner (D7, verified over 180 files).

STAGE-2 INVARIANTS (hard):
- BATCH SEMANTICS ARE FROZEN.  `Session.load`/loadModule keep strict
  refusals byte-for-byte (repl-smoke suites + the TestReplDifferential
  goldens are the tripwire).  Error tolerance is an EDITOR-PATH
  feature: new tolerant entry points live beside, never inside, the
  strict ones.
- The resident LSP session stays interface-free (Decision 5) and
  single-threaded (decision 3).  Hover on locals stays null until the
  perf ticket closes (tracker/TICKET-perf-type-inference.md).
- Every sweep covers stdlib AND core/examples (the 180-file rule).
- lsp-smoke's check count GROWS with each item: update the Baselines
  note in the same commit (it was 31 at the start of the stage; 39 after
  5.1).

- [x] **5.1 Tolerant read path + full diagnostics collection**.
  NewPipeline grows `readModuleTolerant(fileName, contents, mh)`
  returning (core Module, SModule, ParseState, Renamer.Result,
  List[Diag]) — the SModule must come along: Definitions.index's
  fixity bridge reads it (Resident.Checked keeps carrying it).  Diags
  collect from EVERY phase: each SErrorStatement (syntax), every
  renamer diagnostic, every Reassoc diagnostic, every assemble
  refusal, every Lower diagnostic.  Tolerant assemble/lowering runs
  PER STATEMENT under a catcher for Death AND Lower.Unsupported AND
  RuntimeException — Reassoc leaves SErrorTerm/SPError/STyError nodes
  in the tree and Lower/TyLower throw non-Death exceptions on them
  (Lower.scala Unsupported sites; TyLower sys.error panics), so a
  Death-only collector would crash the editor path.  Enumerated
  assemble Deaths to convert in tolerant mode: interleaved equations
  (fix its cross-block case first: it currently reports Span(0,0,0,0),
  an invalid LSP position — give it the colliding equation's span),
  missing-definition sig pairing, and the class-body refusal.
  `readModule` (strict) becomes a thin wrapper that dies on the first
  diag of the EARLIEST PHASE, each phase preserving its own emission
  order (parse Err -> first SErrorStatement -> renamer walk order ->
  reassoc -> assemble in statement order -> lower) — this is today's
  throw order, NEVER a position-sorted merge; the strict rendering
  must stay byte-identical (goldens + repl smoke verify).
  Resident.checkFile switches to the tolerant entry: navigation and
  syntax diagnostics come from the same parse, and a broken file gets
  a FRESH index for its healthy statements instead of a stale one.
  Type checking still runs strict Session.load in this item; its
  single Death becomes one more diagnostic.  lsp-smoke grows: a
  fixture with TWO broken statements publishes two syntax diagnostics;
  goto-definition answers on the healthy statements of a broken file.
- [x] **5.2 Precise in-statement syntax positions** (repay the Ugly.e
  coarsening, D3 log).  The splitter's `.attempt` discards the real
  failure; recover it by re-running the `statement` grammar over the
  broken statement's extent with a repositioned ParseState
  (`ps copy (loc = Pos(file, startLine, startCol), input = slice)` —
  the evalInContext precedent).  TWO REQUIREMENTS from review:
  (a) seed the layoutStack with IndentedLayout(layoutCol, ...) — the
  default is column 1 and inner vsemi decisions drift for indented
  module bodies; (b) the re-parse may SUCCEED where the splitter
  rejected (context the slice lacks — the committed trailing-comment/
  vsemi interplay in the splitter history): fall back to the
  statement-start position when no Err is harvested.  lsp-smoke:
  Ugly.e's diagnostic returns to line 3 col 5 with an expectation
  message; add a continuation-line-error fixture asserting the
  position lands mid-statement.
- [x] **5.2b The splitter's PREFIX-PARSE hole** (found building 5.2's
  continuation-line fixture; the roadmap did not anticipate it).  The
  tolerant splitter only recovers when the statement grammar FAILS.
  When it SUCCEEDS on a proper prefix of the extent and leaves junk
  behind — `total a b =\n  a\n  ) b`, or a chain ending in a trailing
  operator followed by a new-looking line — `statement` returns that
  prefix, the leftover has no home, and the whole `sepEndBy(semi)` /
  virtualRightBrace driver dies: `SurfaceParsers.module` returns Left,
  so the file gets NO SErrorStatement, no per-statement diagnostics and
  no navigation (it falls back to the one Death diagnostic, correctly
  positioned, which is why this was invisible until now).  Half-typed
  code is full of prefix-parseable statements, so 5.3 makes this
  common.  FIX: `statement` must require the real alternatives to
  consume the WHOLE extent — a statement-boundary lookahead (next
  significant character at or left of the layout depth, or end of
  input) after the real alternatives, with the pair attempted so a
  failure falls through to `rawStatement`.  The lookahead must be
  purely lexical (StatementExtents already has the scanner; `layout`
  itself pops layout contexts and must not be used for peeking).
  RISK: this changes what `SurfaceParsers.module` returns for every
  file, so it needs the 180-file differential (statement starts
  unchanged; TestStatementExtents and TestSurfaceParsers are the
  oracles) and the REPL goldens in the same commit.

- [x] **5.3 In-memory documents + didChange**.  Today the server reads
  the SAVED file (sync kind 0; no didChange registered — Main.scala:65)
  so mid-keystroke anything is impossible.  Add: TextDocumentSync FULL
  (full-text didChange bodies; incremental deltas are a later
  optimization) — and update lsp-client.py's initialize.sync check to
  assert `change == 1` in the same commit; a per-uri document store
  (text + version) maintained by didOpen/didChange/didClose — consider
  folding it with Definitions.Docs into one per-uri record; checkFile
  and the workspace-sibling loader prefer open buffers over disk so
  cross-file checks see unsaved edits.  BUFFER SOURCEFILES ARE A NEW
  SUBCLASS with content-bearing identity and lastModified = document
  version: reusing Session.Literal (module-name-keyed equality) or
  serving buffers through mtime-keyed Filesystem deps re-opens the
  process-global depCache poisoning class fixed at D0/D3 part 3b —
  add a smoke check that a didChange to a SIBLING module is seen by
  the importing file's next check.  Debounce (~300ms) with versioned
  drop of stale checks (single-threaded dispatch makes this a queue
  check, not a race).  lsp-smoke drives didChange with broken-then-
  fixed text asserting diagnostics appear and clear WITHOUT didSave,
  and after a didChange that moves a definition down a line,
  goto-definition answers at the NEW position without a save.
- [x] **5.4 Tolerant type checking** (diagnostics for the healthy part
  of a broken file).  An editor-path variant of the load phases with
  per-unit error capture, structured per review: EACH BINDING SCC
  INFERS IN ITS OWN subst BLOCK (a Death mid-component inside one
  shared SubstEnv leaves partial meta bindings on module-wide shared
  placeholder Vs, spuriously constraining later components; fresh
  SubstEnv per component threads only the generalized `subs` — the
  structure inferBindingGroupTypes already has); the per-binding
  explicits loop captures per binding.  SCCs that fail — and,
  TRANSITIVELY, SCCs depending on failed or skipped ones — are
  reported "unchecked: depends on a broken definition", never
  silently inferred against unconstrained metas (they would typecheck
  to lies).  When the file has syntax errors, suppress undefined-term
  diags whose spelling matches a broken statement's head word
  (StatementExtents.headWord / first token of the extent) — the
  REFERRING statements mint the placeholders, so match by spelling,
  or fall back to suppressing undefined-term diags entirely while
  syntax errors exist.  The session copy is discarded either way;
  partial results never enter a real session.  lsp-smoke: a fixture
  with two INDEPENDENT type errors publishes both.  REVISIT while
  here: the do-anchor blame gap (D3 log); fix if the per-SCC check
  order makes it cheap, else keep the pin and note.
- [x] **5.5 Incremental re-inference per unchanged SCC**.  Review
  killed the naive form: renamer binder ids and Lower's supply-minted
  Vs are FRESH EVERY RUN and shared across statements, so cached
  lowered trees cannot mix with a fresh run — and parse+rename+lower
  are cheap (inference dominates; the perf ticket's own finding).
  Therefore: parse+rename+lower the WHOLE module every check;
  the reuse target is PER-SCC INFERENCE RESULTS, keyed by an
  alpha-invariant fingerprint of the SCC's lowered terms plus the
  types of the globals it references, retained per uri in the doc
  store (surface module, extents, per-SCC results — bounded by
  open-document count).  The invalidation unit GROUPS sig+equations
  (module-wide pairing by shared V — a sig edit changes its group's
  ExplicitBinding without touching the head set).  Scope-bearing
  edits (import/export, fixity, type/data/class/field/table/foreign,
  any change to the top-level head set) drop the whole cache —
  conservative and correct beats clever.  If a stable-binder-identity
  scheme looks necessary for deeper reuse, STOP: that is its own
  design item for the Blocked/Awaiting section, not a side quest.
  Measure keystroke-to-diagnostics on Layout/Report.e (1400 lines)
  before and after; record the numbers in the log.
- [ ] **5.6 (stretch) Nested extents** — **DEFERRED 2026-08-31, with
  evidence, per this item's own "defer without guilt if 5.1-5.5 land
  first".**  Both of its stated motivations were checked and neither
  survived:
  (a) "so 5.2's re-parse can work inside a long where-block" — it
  already does.  statementFailure re-runs the real grammar with the
  binding alternative COMMITTING, so the failure it recovers is
  whatever committed deepest, block or no block.  Nested.e's error
  inside a `where` is blamed at 6:17, the second `=` in the block, not
  at the statement head; lsp-smoke pins it.
  (b) "so 5.5's invalidation can work inside a long where-block" — it
  cannot, and nested extents would not help.  The invalidation unit is
  a binding SCC, and implicitBindingComponents runs over m.implicits,
  which is TOP-LEVEL bindings only: a where-block's bindings are
  lowered into a Let inside their owner's alt and are never a component
  of their own.  Finer extents would give nothing finer to invalidate.
  What nested extents would still buy is narrow: the undefined-term
  head-word suppression falls back to "suppress all" when the broken
  statement sits inside a private/database block (not a top-level
  item), and the syntax diagnostic's END would come from a scanner
  rather than the parsed span in the case where statementFailure
  recovers nothing.  Neither is worth the differential a new scanner
  mode would need.  Reopen if a real editor session shows otherwise.

KNOWN PRE-EXISTING DIVERGENCE (out of Stage-2 scope, tracked here so it
is not rediscovered): assemble ignores bare SClassStatements entirely,
so nothing registers in s.classes for bare class declarations — the
fused pipeline registered the class head.  Worth its own item when
classes matter.

**GATE G2**: lsp-smoke green with the new fixtures (multi-diagnostic
broken files, didChange without save incl. the sibling-buffer check,
positions per 5.2, both type errors per 5.4, nav-after-didChange, and
a timing line from 5.5); core/test, repl smoke suites and the REPL
goldens BYTE-UNCHANGED (batch strictness frozen); boot 129.  STOP the
loop and summarize for sign-off before any Stage 3 planning.

## Blocked / Awaiting

**GATE G1 — awaiting sign-off (2026-08-30).** Stage 1 checklist complete
(commits 8b1e07f..b42d132).  Every gate layer ran dry: .ei 1447/1447
alpha-equal, browse/groups/importing goldens, G1Resolution 8223/8223,
warm-reload matrix, eval + scoping corpus under both pipelines, 4.4
flips.  TWO KNOWN DELTAS need explicit acceptance: (1) lookbackJoin's
residual constraint set in Relation.ei — the documented solver-order
sensitivity (the reason -Dermine.loadInSeries exists); logically
equivalent, textually different constraint hypergraphs.  (2) browse
kind-meta rendering entropy (scanInOrder-class sigs render s: rho vs a
kind var, INVERTED between the pipelines' .ei/browse outputs); the .ei
alpha-eq comparator is the authority and accepts them.  Post-G1 debt
list unchanged below.  Say the word to open Stage 2 (fused-machinery
deletion + the debt list).

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
- 2026-08-30 2.3c done: the full type grammar (row types with dots forms
  incl. banana, forall/exists/some quantifiers with kind-brace groups and
  kinded binders, ->/=>/<- as chain pseudo-ops, kind-mode atoms */rho/phi/
  constraint incl. unicode spellings, qualified dotted names) replaced
  every raw type capture; plus field/table(dotted names, database form)/
  type-alias/data(per-con foralls)/class(context+body)/foreign(6 forms +
  per-item private wrapper, class names as strings)/private/database
  statements. THE WHOLE SURFACE GRAMMAR NOW STANDS: 3654 statements
  parse for real across 178 old-parseable files, zero placeholders, zero
  failures; the two legacy files the fused pipeline also rejects now fail
  cleanly (agreement on rejection, exemptions in the test). Found en
  route: per-item `private` inside foreign blocks (Font.e — new
  SForeignPrivate node); pattern sigs need the `some` annot quantifier
  (Field.e/Chart.e); bare `private` + col-1 comment must yield an EMPTY
  private block (comment-only raw extents are whitespace — Error.e;
  recorded in surface-notes as a G1 parity question, the col-max-depth
  corner made concrete). Test now asserts zero unparsed:* of ANY kind on
  non-legacy files + type-shape properties. Baselines: 805 (804+known;
  one flake, 4th sighting, cleared on re-run), repl 3/3, lsp 27/27.
- 2026-08-30 2.3d done: the 180-file differential was already standing in
  TestSurfaceParsers (parse + agreement-on-rejection); the new piece is
  the rejected-corpus DISPOSITION table — each 1.3b refusal re-checked
  under the new parser and pinned as either still-parse-time (bare
  prefix stacking, dead underscore) or parses-now-with-the-refusal-owed
  (5 cases owed by 3.3's fixity env/re-associator, 2 by 3.2's renamer,
  2 by 3.2/3.4) — the ledger is in surface-notes and asserted in the
  suite, so each owing item must flip its dispositions when it lands.
  PHASE 2.x (surface syntax) COMPLETE. Baselines: 806 (805+known),
  repl 3/3, lsp 27/27.
- 2026-08-30 3.1 done: rename/ModuleScope.scala — importing() as a pure
  function (using/hiding, localized rename-then-affix, list-concat alias
  merge, collapseNames with the singleton-skip quirk, both origins
  fixups), with the termNames-superset-vs-canonical-scope distinction
  documented on the Scope type per the leak pin. G1Importing gains a
  `verify` mode comparing old-vs-new IN PROCESS over all 129 headers +
  6 synthetics (value lists compared sorted — order only feeds ambiguity
  message text): ALL MATCH on the first run. g1-validate.sh now runs the
  differential as a standing layer. Baselines: 806 (805+known), repl 3/3,
  lsp 27/27.
- 2026-08-30 3.2a done: rename/Renamer.scala — the TERM-SIDE RENAMER,
  and more than the item asked: with the surface AST in hand, whole-block
  scoping is a pure tree operation, so let/where/do/case/lambda frames
  shipped alongside module-level terms (binder heads collected before any
  rhs — LocalBlocks/checkShadows/subTerm have no reason to exist in this
  pipeline). Resolution: frames -> own top-levels -> canonical scope
  (fixity-bucket probes for operators; NEVER the termNames superset);
  ToGlobal carries importedAs + origin (hover labels); unresolved names
  tolerated per the pin; sig+equations share one binder with def-site =
  LAST equation (globalTermDef relocation parity). Outputs: occurrences,
  binder table with def-site spans + kinds, frames with scopeAt query.
  Ledger refusals recorded as diagnostics: top-level import shadow +
  ':'-constructor binders (both binder paths). TestRenamer: 10 properties
  incl. do unbind-before-rhs/rebind-after, where-shadows-argument, alias
  non-capture by construction, scope-at-position. Ledger dispositions
  flip when Death wiring lands (3.2b). Baselines: 816 (815+known),
  repl 3/3, lsp 27/27.
- 2026-08-30 3.2b done (local scopes already shipped in 3.2a):
  renameOrDie throws Death with Pos.report rendering (asserted:
  "t:3:1: error: ..." + source line + caret — Diagnostics regex and
  no(...)/sessionProof compatible); classLookup relocated to a rename
  pass (StatementParsers.classLookup reused with its process-global
  classMap cache, dependency noted; failures diagnosed at the class-name
  span, "error loading '...'"); class bodies bind through the
  topLevelHeads path (member cross-refs resolve, import shadowing
  refused; their dead type processing stays a typecheck matter per the
  pins). TestRenamer 13/13. Baselines: 819 (818+known), repl 3/3,
  lsp 27/27.
- 2026-08-30 3.2c done: type/kind renaming — references through binder
  frames then canonicalTypes (fixity-bucket probes for type ops; arrows
  and kind atoms builtin, incl. '*'-as-chain-op awareness the 3.3
  re-associator will need); per-ANNOTATION implicit quantification
  (first free lowercase var binds, later share — matching the pinned
  per-signature independence; mechanism-level equivalence with the fused
  typeNames-persistence+generalization is 4.1's differential obligation,
  noted in code); forall/exists/some frames with kind braces visible to
  binder kinds (push-order bug caught by the props); data/type/class
  declaration heads scope their types incl. per-constructor foralls;
  field/table/foreign types wired. kindOf/kindAfter fixture twins
  DEFERRED to 4.1 (they need typecheck integration to produce Kinds).
  TestRenamer 18/18. Baselines: 824 (823+known), repl 3/3, lsp 27/27.
- 2026-08-30 3.3 done: rename/Reassoc.scala — ParsingUtil's shuntingYard
  ported as a pure pass (exact clear/finish: LT pops, EQ L/L reduces,
  EQ R/R shifts, mixed EQ = "ambiguous operator of precedence" verbatim;
  unary keeps AssocL; "ill-formed expression" for arity failures);
  positional FixityEnv (imports from canonical keys, module fixity
  statements textually, block ParenFixityBinder declarations extending
  the env inside their let/where per Decision a, "Multiple fixity
  definitions" on duplicate buckets incl. the postfix/infix share);
  unary-minus SNeg wrapper survives around the re-associated chain;
  type arrows as pseudo-ops (0R/0R/1N; Forall/Part construction stays
  for 3.4); '*'-at-operand-position becomes the star atom. ALL FIVE
  ledger dispositions FLIPPED to re-associator diagnostics (asserted;
  surface-notes updated). TestReassoc 13/13. Baselines: 837 (836+known),
  repl 3/3, lsp 27/27.
- 2026-08-30 3.4a done: rename/Lower.scala — surface->core lowering for
  the structural cases + this slice's G-channel sugars: whole-chain
  primNeg, Field.cons foldRight onto EmptyRecord, Builtin.Nil/:: list
  patterns (:: carries InfixR(5) IN THE GLOBAL — Name equality includes
  the bucket; the hook table already said so and the differential caught
  the miss), Product spines for tuples/sections, Remember(Hole).
  Un-reassociated chains and 3.4b/c sugars are loud Unsupported.
  TestLower revives the tnodes shape for real: OLD fused testParse output
  vs NEW parse->rename->reassoc->lower, alpha-compared modulo ids/locs
  over a booted fixture — 6/6 after fixing the binder-site join (pattern
  binders are sites, not occurrences; Lower joins through the binder
  table's def-site spans). Deferred notes: pattern-CHAIN re-association
  to 3.4b; sig/annotation lowering to 4.1. Baselines: 843 (842+known),
  repl 3/3, lsp 27/27.
- 2026-08-30 3.4b done (user asked "is custom bracket syntax properly
  handled?" — answer now VERIFIED yes): channel-A hook lowering — the
  _Module/_alias suffix is part of the Local looked up through the
  canonical scope; missing/ambiguous hooks and the empty brace are
  diagnosed (ledger flips); expansion shapes exact (foldRight brackets
  from empty_Bracket, foldLeft braces from single_Brace, reverse-fold do
  over Syntax.Do.bind with Lam(WildcardP) effect statements and the
  last-must-be-expression/non-empty refusals). Pattern-chain
  re-association landed in Reassoc (con-ops through the yard, InfixR(5)
  ::). Differentials cover ALL THREE stdlib witness shapes: plain [1,2,3]
  via List hooks; [1,2]_L alias-suffixed (the DateRange.e/Date.e idiom);
  Vector.e as a custom hook PROVIDER with List's hooks hidden (the
  Relation.e idiom) — old-vs-new alpha-equal. Also: separate fixtures
  per import family (baseEnv write-back pollution). TestLower 11/11.
  Baselines: 848 (847+known), repl 3/3, lsp 27/27.
- 2026-08-30 3.4c done — THE HARD ONE, and PHASE 3.x IS COMPLETE.
  Channel R implemented across all three passes: the renamer rebinds the
  15-op set + `not` to Relation.Predicate/Op globals inside combine/
  filter arms only (never rename; override beats every scope layer, as
  bindName did); Reassoc applies the forced fixities via an overrides
  layer that outranks textual declarations; Lower ports desugarRelArrows
  exactly — Function.id empty case, catafy with the column set evolving
  by SPELLING from empty (combine adds `as`, rename swaps from->to),
  col-wrapping of in-column Vars and prim-wrapping of literals with the
  precise descent-stop set, combine(op, Var as), rename(Var from, Var
  to), later arrows composing LEFT via Function.(.) InfixR(9). Five
  differentials (each arm kind, rebound ops, `not`, column evolution,
  full composition) alpha-equal vs the fused output. En route:
  insert-on-miss PARITY for placeholders — occurrences of one unknown
  spelling share one V module-wide, as the fused termVar's termNames
  insertion does (the column-evolution diff caught per-occurrence
  minting). TestLower 16/16. Baselines: 853 (852+known), repl 3/3,
  lsp 27/27.
- 2026-08-30 4.1a done (first slice of 4.1): EVAL-LEVEL INTEGRATION —
  lowered terms run through the REAL inference (Session.subst +
  Subst.inferType) and the REAL evaluator (Term.eval against the session
  env; global Vs share ids with the session so the eval env resolves
  directly), producing values identical to the fused pipeline for all
  five relocated sugars: whole-chain negation (-6, not -4), bracket
  literals through List hooks, pattern cons destructuring, grouped let
  equations, do over Maybe. The checklist's value-level eval fixtures
  are hereby landed. TestLower 21/21. Remaining in 4.1 (next
  iteration(s)): type/annotation lowering, module assembly feeding
  Session.loadModule's contract, the -Dermine.pipeline switch, fixture
  twins (testParse/kindOf), dual-pipeline suite runs with the :130/:133
  exemption. Baselines: 858 (857+known), repl 3/3, lsp 27/27.
- 2026-08-30 4.1b done: rename/TyLower.scala — surface->core type/kind/
  annotation lowering mirroring TypeParsers exactly: -> as Arrow apps;
  => flattening Product-packed constraints into Forall(Nil,Nil,Exists.mk,
  body); <- as Part(l.inferred, lhs, flattened); rows applying recordT/
  relationT to ConcreteRho (unresolved field names localize to the
  module) or the dotted row var; explicit forall/exists with written
  binders and kinded-binder kinds; implicit sig vars stay FREE metas
  shared per TyImplicit binder; `some` becomes the Annot existentials;
  results .nf-normalized. KEY CONTRACT FIND (differential caught it):
  the fused pipeline lowers type REFERENCES to named VarTs — one shared
  V per Global, substituted to Cons later by loadModule's Type.conMap —
  so TyLower mints the same and exposes its conVars as the typeNames map
  4.1c will hand loadModule. Seven type differentials vs TypeParsers.typ
  via the G1 comparator (arrows/forall/implicits/getF partition shape/
  rows/tuples/kinded binders): all green. TestLower 28/28. Baselines:
  865 (864+known), repl 3/3, lsp 27/27.
- 2026-08-30 4.1c done — THE INTEGRATION MILESTONE: NewPipeline.scala
  assembles a core Module (moduleBody-parity bucketing, adjacency
  binding blocks, checkBindings-parity sig pairing by shared V with
  Annot.plain and "missing definition" preserved, data/type/field/
  table/foreign lowering, private tracking) plus the ParseState contract
  (canonical maps, termNames+placeholders, TyLower conVars + own type
  defs as typeNames) — and a WHOLE MODULE (sigs, equations, polymorphic
  data + constructor use, tuples) LOADS AND TYPECHECKS through
  Session.loadModule with every exported type alpha-equal to the old
  load. Fixes en route: sig names are now binder OCCURRENCES (also gives
  the LSP goto-def from signatures); declaration type/kind args join the
  renamer's binder ids so constructor fields share their Vs (the rigid-
  skolem unification failure caught it). The -Dermine.pipeline=new
  switch is LIVE in Session.dep's read closure (Decision d: REPL command
  parsing stays fused). First full-boot attempt under the new pipeline
  runs deep into the stdlib and dies at Control/Monoid.e:11:36
  ("undefined type" — `Monoid (m, n)` tuple-of-vars in a sig result) —
  4.2's convergence loop opens there. Baselines (old path untouched):
  866 (865+known), repl 3/3, lsp 27/27.

- 2026-08-30 (4.2 batch 1): CONVERGENCE TO FULL BOOT. Nine divergences
  fixed, in boot order: (1) Lower/TyLower minted V ids from per-module
  negative counters — module N+1's ids collided with module N's Vs
  living in s.env (V equality is id-only), tripping loadModule's
  overwrites3 "would overwrite existing global in the environment";
  both now mint from the session Supply, like the fused parser.
  (2) Stale .ei files sent loadModule down the interface remap path
  ("pre-checked types failed"): convergence boots now clean *.ei first
  (the interface layer gets its own oracle pass later). (3) Fixity
  declarations are part of declared NAMES: binder Vs, constructor
  placeholders and `infix type` type names now carry the declared
  fixity (Function.e exported `.` as Idfix; List.NonEmpty's (:|)).
  (4) ParenOp references probe the infix/postfix canonical bucket, per
  NameParsers.opName — Num.e's (+_P) affixed paren-op refs. (5) Sig
  pairing is module-wide by shared V (a `private sig` group pairs with
  equations outside it — List.e's `private map`); let/where pairing
  stays block-local. (6) hookVar falls back to the module's own
  bindings (internalVar parity — List.e defines and uses
  empty_Bracket). (7) Term and pattern sig ANNOTATIONS lower for real
  (Sig node; the annot rides the pattern var's extract per
  mkLocalPatternVar) — IO.e's rank-2 `(kf : some r. K r)`; Reassoc now
  rewrites sig types inside let/where blocks and pattern sigs.
  (8) private foreign members are marked private (Vector.toList# was
  leaking and made Scanners' toList# ambiguous). (9) `{}` is the empty
  record (fused rec production), not an empty brace literal. RESULT:
  `-Dermine.pipeline=new` boots Prelude+Layout — all 129 modules parse,
  rename, reassociate, lower, and TYPECHECK. Also: the pipeline switch
  became session-level (SessionEnv.pipelineNew) because the JVM
  property is process-global and concurrently-running test properties
  saw each other's flag (three suites falsified under the full run,
  green in isolation — the concurrency-flake protocol caught it);
  tests now set _pipelineNew on their own session copy. Baselines:
  866 (865+known disjunction), repl 3/3, lsp 27/27.

- 2026-08-30 (4.2 batch 2): THE .ei DIFFERENTIAL RUNS DRY, one known
  delta. Same-commit dual boots (g1-diff.sh run old|new) compared: six
  more divergences fixed. (1) literalIdentTok kept the ``..`` marks and
  raw escapes in the SPELLING — NameParsers yields the middle,
  unescaped. (2) Unresolved TYPE spellings now share one V module-wide
  in TyLower (typeNames insert-on-miss parity) — `(AsOp opl, AsOp opr)`
  under a term-only import bound TWO constraint vars (the AsOp1 rename
  in Layout/Presentation). (3) Reassoc now rewrites BINDER KINDS
  everywhere (data/alias/class args, foreign-data args, forall/exists/
  some binders): `(f : * -> *)` parsed as a chain and TyLower.kind
  silently minted a meta (now a loud error). (4) Foreign-data arg kinds
  default to Star (localTypes' explicit default — no body ever pins
  them); Vector/Scanner/SMEnv kinds were generalizing into {a}.
  (5) An UNKNOWN kind name is a NAMED kind variable scoped to its
  statement (KindParsers kindVar — `data Sort (r:row)` schema-
  quantifies row), and conFor INSTANTIATES kind schemas per reference
  rather than sharing the quantified vars. (6) private data
  constructors, private fields/tables mark privateTerms/Types (five
  constructors were leaking into :browse). Verdict: G1Compare says
  1447/1447 signatures alpha-equal except lookbackJoin's residual
  constraint set — the documented solver-order-sensitive case (the
  reason -Dermine.loadInSeries exists); recorded as G1 KNOWN-DELTA.
  Browse layer: g1-normalize.py now joins wrapped entries and sorts
  exists-block binders/atoms; residue is 14 signature pairs of
  alpha-renaming / constraint-order / kind-meta-rendering noise, all
  ruled equal by the .ei comparator (kind-meta rendering entropy is
  INVERTED between the pipelines for scanInOrder: old .ei pins s:rho
  where new keeps s:a, and the browse shows the opposite) — recorded
  as browse KNOWN-DELTA with the .ei comparator as authority.
  Baselines: 866 (865+known), repl 3/3, lsp 27/27; the Legend flake
  re-ran green (6th sighting).

- 2026-08-30 (4.2 batch 3, verification-only): five more oracle layers
  run dry with NO code changes. :groups dumps byte-identical old|new
  (compare's diff was already silent). G1Importing verify: 129 modules
  + 6 synthetics ALL MATCH under BOTH pipelines. Warm interface-backed
  reload: full matrix (old|new pipeline x old|new .ei) boots 129
  modules warm (~6s) and compiles fresh examples through the interface
  remap path cleanly (Accumulate.e, GroupBy.e). Eval layer: repl-smoke
  3/3 (33 checks) under the new pipeline WITH THE PARALLEL LOADER —
  first proof the new pipeline is safe without loadInSeries (note: a
  loadInSeries console boot prints "Loaded two modules", which the
  smoke filter's `Loaded [0-9]*` regex drops — flag left off).
  Examples sweep (the 19-file half of the 180-file rule): 18/19
  identical outcomes; guide/HelloWorld.e is a MOVED REFUSAL (fused
  parse-time "unmatched '{'" 43:42 -> new typecheck "undefined term"
  48:21 at the t2 reference), recorded in the surface-notes ledger.
  Remaining 4.2 layers: occurrence->def-site differential (the big
  one — also 4.3's spec), scope-at-position sampling, 1.3 corpus/
  TestScopes pipeline parameterization, 32 non-boot modules under new.

- 2026-08-30 (4.2 batch 4): OCCURRENCE->DEF-SITE DIFFERENTIAL BUILT AND
  DRY (tools/G1Resolution.scala — also 4.3's spec). Old side: fused
  moduleBody re-parse (own-module globals filtered from seeding, the
  0.5 nav trick) walking Var/ConP occurrences to binder locs by V id,
  with the POST-PARSE termNames end-state as the def-site authority;
  new side: renamer occurrence table (ToBinder -> defSite, ToGlobal ->
  session V loc). RESULT: 136 files, 8223 shared occurrences, ZERO
  mismatches. It caught and fixed TWO real parity bugs first: (1)
  collectHeads def-sites — a LET/WHERE binding captures its V at the
  FIRST EQUATION (sig binds only when no equation follows), while the
  top level keeps the last def-like mention IN FILE ORDER including
  inside private groups (collectHeads now descends SPrivateBlock/
  SDatabaseBlock — Native.Magnitude's `private erasePhantom =` case);
  (2) ParenOp binder/reference SName spans now START AT THE OPEN PAREN
  (fused loc convention; was the op token). One-way occurrences are
  explained noise (new-side def-like mentions and type-level names;
  old-side desugar-minted and class-body vars); skips = the 5
  documented own-export re-parse modules + examples needing imports
  beyond the tool's boot (covered end-to-end by the :load sweep) +
  Sample.e (both sides refuse). Baselines: 866 (865+known), .ei
  differential still 1 known delta, repl 3/3, lsp 27/27.

- 2026-08-30 (4.2 batch 5 — 4.2 COMPLETE): the last corpus layers run
  under the new pipeline. (a) TestErmineModulesNewPipeline: all 161
  library modules (129 boot + the 32 non-boot), Layout.Report.KeyedTest
  and the sample examples load through the live switch, 3/3.
  (b) TestScopesNewPipeline: the whole 1.3 scoping corpus (26 props)
  through the switch — ErmineFixture(statementsViaNew = true) wraps
  each property's statements in a `module Test` Literal and S.loads it;
  the two alias-capture refusals are gated old-only per the 4.4
  exemption (they flip to positive there). Three harness traps found on
  the way, all fixed in the fixture: the baseEnv writeback/copy tear
  (envLock), and Session.Literal's name-keyed equality making the
  process-global depCache replay the first "Test" module forever
  (evict under ErmineFixture.literalLock, serialized because the key is
  name-global). (c) scope-at-position layer: SUBSUMED by G1Resolution —
  it samples resolution at all 8223 real occurrence positions, denser
  than any sampled-position probe; the residual gap (scope domains at
  NON-occurrence positions, i.e. completion) is deferred to 4.3 where a
  consumer exists. 4.2's KNOWN DELTAS for the G1 sign-off: (1)
  lookbackJoin's residual constraint set (.ei; solver-order, documented
  pre-existing sensitivity); (2) browse kind-meta rendering entropy
  (inverted between pipelines for scanInOrder-class sigs; .ei
  comparator is the authority). Suite grows to 896 (895 green + known
  disjunction); repl 3/3, lsp 27/27.

- 2026-08-30 (4.3): LSP REBASED ONTO THE RENAMER TABLES.
  Resident.checkFile now returns Checked(env, name, surface module,
  Renamer.Result): after Session.load (so sibling imports are in
  termNames), the file goes through SurfaceParsers + ModuleScope +
  Renamer.rename — the fused re-parse AND its self-global filter are
  deleted (the top-level binder frame shadows the module's own loaded
  globals; the renamer's shadow diags go unused for navigation).
  Definitions.index flattens the occurrence table: each occurrence
  carries its REAL SPAN, a Target (ToBinder -> the binder's def-site
  span in-file; ToGlobal -> the session V's relocated loc), and a hover
  payload (ToGlobal, or the TopLevel-binder bridge through
  Local(spelling, declared fixity).global(name) — hover on locals stays
  null per the perf ticket).  The point+len hit test over walked core
  Vs is gone.  lsp-smoke grows 27 -> 31: sig-name mention jumps to the
  equation, where-local goto-definition, hover-on-where-local null, and
  sig-mention hover — all pass first run.  Type-level names inside the
  file now navigate too (TyDef binder spans), for free.  Baselines:
  896 (895+known), repl 3/3, lsp 31/31.

- 2026-08-30 (4.4): ALIAS-REFUSAL FLIPS LANDED. Under the new-pipeline
  parameterization only, four positive properties assert plain Haskell
  scoping: an alias-affixed reference (id_F) survives a plain-name
  shadow in where and in let; the combined-capture program (id_F
  untouched AND plain id captured, one expression); and the letrec
  early-plain-name-reference case binding the block's shadowing
  binding.  The old-pipeline suite keeps the two capture REFUSALS
  verbatim (:130/:133) — no machinery deletion, no scoping.in edit
  (post-G1 debt).  The flip properties import Prelude WITHOUT Primitive
  (flipImps): with both, `+` is ambiguous by design (the
  operator-imported-twice pin), which is a corpus-authoring constraint,
  not a pipeline bug.  Suite: 900 (899 green + known disjunction);
  repl 3/3, lsp 31/31.  STAGE 1 CHECKLIST COMPLETE — stopping at GATE
  G1 for sign-off.

- 2026-08-30 (G1 SIGN-OFF): user accepted both known deltas ("keep
  going").  Post-G1 debt phase opened as checklist D0-D8; the loop
  resumes on D0.

- 2026-08-30 (D1): REPL/EVAL CUTOVER. Session.eval routes expressions
  through the split pipeline when the session does: new
  SurfaceParsers.expression (phrase(term) over the resolution-free
  grammar), Renamer.renameTerm (bare-term entry, no module frame),
  NewPipeline.replTerm (rename -> Reassoc.term under import fixities ->
  Lower with annot wiring -> conMap substitution).  Unlike a module
  load, nothing links a REPL term later, so replTerm refuses any free
  variable left after lowering ("undefined term" at its position) —
  without this, unresolved names and missing desugar primitives reached
  eval as PANICs (caught by the new TestReplDifferential corpus, 21
  expressions evaluated through BOTH paths, agreement required).  One
  intentional relaxation documented there: the fused phrase(term) never
  parsed multi-equation let blocks in one expression ("end of layout
  not found"); the surface grammar does.  evalInNamedModuleContext
  rides eval; evalInContext has no users and stays fused until D3
  deletes it or ports it.  bin/ermine and bin/ermine-lsp now pass
  -Dermine.pipeline=new (the shipped cutover); repl-smoke.sh defaults
  to the new pipeline with REPL_PIPELINE=-Dermine.pipeline=old as the
  old-path override — 3/3 under BOTH.  Corpus-authoring note repeated:
  importing Primitive and Prelude together makes + ambiguous (the
  operator-imported-twice pin).  Suite 902 (901+known); lsp 31/31.

- 2026-08-30 (D2): the aliased-shadow semantics change is now a smoke
  suite: tracker/repl-tests/aliasing.in loads Aliasing.e (id_F survives
  a plain-name where-shadow; the combined-capture program) and asserts
  the evaluated values.  The legacy REPL_PIPELINE=old override skips
  aliasing.in by design — those programs are refusals under the fused
  pipeline until D3 retires it.  Smoke: 4 suites new, 3 legacy.

- 2026-08-31 (D3 part 1): the fused REPL surface is gone. Session.eval
  has no fused branch (every expression rides replTerm; parity was
  pinned first); evalInContext (fused module-text eval, zero users) is
  deleted; TestReplDifferential became the REPL eval GOLDEN corpus (22
  entries with exact type/value/refusal pins; one unify-message golden
  is a pattern because type-var NAMES follow supply draws).  Two
  root-cause fixes landed on the way: (1) Dep closures no longer bake
  their creation session s typeCheck/useInterface — the gate moved to
  make() with the live session, ending cross-suite dep-cache poisoning
  (the Interface round-trip flake); (2) ErmineFixture supplies are
  per-thread (Supply is documented single-threaded; the shared instance
  raced lo under ScalaCheck pool and handed two threads the same id —
  the recurring eval:unbound flake class, 7+ sightings, now
  root-caused).  Next: D3 part 2 — retire the fused MODULE path
  (dep read branch, pipelineNew flag collapse, test-twin merge), then
  delete the grammar itself.  Suite 902 (901+known), repl 4 suites,
  lsp 31/31.

- 2026-08-31 (D3 part 2): THE FUSED MODULE PATH IS RETIRED.  Session.dep
  reads every module through NewPipeline unconditionally; the
  SessionEnv.pipelineNew switch, withPipelineNew, the -Dermine.pipeline
  property, the bin-script flags, repl-smoke's REPL_PIPELINE override,
  and g1-diff run-old are all gone (g1-diff old fails fast with a
  retirement note).  The old/new test twins merged: ONE TestScopes
  (statements via Literal loads; the fused capture refusals deleted,
  the 4.4 flips unconditional), ONE TestErmineModules, the round-trip
  test drops its fused cross-read phase.  Two regressions surfaced and
  fixed: (1) interleaved equations of one name were silently MERGED by
  the 4.2 pairing rewrite — now refused (gatherBindings parity, caught
  by the Stage-1 pin); (2) batch module loads silently DROPPED
  unparseable statements (the tolerant splitter feeds editor flows) —
  readModule now refuses the first SErrorStatement; the Ugly.e refusal
  message/position moved per Decision f (statement start; Stage 2
  restores in-statement precision).  The fused STATEMENT path survives
  ONLY in the test fixture legacy branch, pending pin-by-pin conversion
  (D3 part 3) — TestStage1Pins and several TestErmine props still pin
  fused behaviors through it.  Suite 871 (870+known; twins removed),
  repl 4 suites, lsp 31/31.

- 2026-08-31 (D3 part 3a): TestStage1Pins CONVERTED to the pipeline
  statement path (34/34).  Real fixes shaken out: (1) term chains can
  OPEN with prefix operators — operand tried first, so ?[w] keeps its
  lexeme (the fused-only paren-stacked-prefix pin exposed the gap; bare
  stacking now parses and the YARD refuses it, ledger flipped to
  ParsesNow); (2) class statements with a body or context REFUSE at
  assemble (the fused type processing died with undefined type; the
  split pipeline was silently IGNORING bodies); (3) do-desugar bind
  applications relocate to their first argument (Appable parity) so
  errors blame the statement; the residual do-anchor QUALITY gap —
  blame lands on the bind rhs (line 1) where fused reached the inner
  subterm (line 2), because the checker infers the continuation lambda
  independently and clashes at the subsume — is pinned as-is and
  tracked as Stage-2 diagnostics debt.  Moved-refusal message updates
  per Decision f (unknown operator / undefined term / hook not in
  scope / unparseable statement); failsAtLine learned the module-
  wrapper line offset.  Two REPL goldens updated for the chain-start
  change (still refusals, same positions, better messages).  Suite 871
  (870+known), repl 4, lsp 31/31.

- 2026-08-31 (D3 part 3b): TestErmine's main suite CONVERTED (27/27 on
  the pipeline statement path — circular definitions, ill-kinded
  data/type refusals, := naming all green).  The conversion exposed a
  vicious fixture bug: kindAfter runs loadStatements (the Test Literal
  loads) and then kindOf -> testParse -> the FIXTURE's loadModules,
  whose baseEnv WRITEBACK captured the session WITH the dynamic Test
  module — and since Literal equality is name-keyed, the written-back
  loadedFiles entry short-circuited every later property's Test load
  (ill-kinded modules 'loaded' by not loading at all; := resolving
  to a stale module).  testParse now loads via Session.loadModules (no
  writeback), and the writeback itself fails LOUDLY if the session
  holds a dynamic Test module.  Remaining fused-grammar consumers:
  kindOf/testParse (fused type parser) and the fixture legacy branch
  (now unused?) — next: convert kindOf, drop the legacy branch, DELETE
  the fused term/statement machinery.  Suite 871 (870+known), repl 4,
  lsp 31/31.

- 2026-08-31 (D3 COMPLETE — the deletion): TermParsers, PatternParsers,
  TermNameParsers (LocalBlocks, checkShadows, rewriteShadowed, the
  insert-on-miss termDef machinery), StatementParsers, moduleBody and
  the command grammar are DELETED; G1Resolution and G1Importing retired
  (their differentials completed their purpose); TestSurfaceLexer
  (pure fused-vs-surface differential) deleted with its oracle.  Kept:
  the header/import grammar (ModuleParsers with small local name
  parsers), TypeParsers/KindParsers/NameParsers (the interface reader
  parses .ei types through them; TestLower tyDiff still differentials
  against them), classLookup extracted to parsing/ForeignClasses.
  Conversions: TestLower term diff props assert diag-free lowering +
  inference (the tnodes oracle died with the grammar; values ride
  evalDiff and the smoke corpora); the fixture legacy branch,
  statementsViaNew flag and testParse are gone — loadStatements IS the
  Literal path.  Suite 869 (868+known), repl 4, lsp 31/31, boot 129.
  D5 (fold bindingName/localName) is MOOT — both died with the files.

- 2026-08-31 (D4/D6/D8): D4 resolved by the deletion (Localized remains
  only in the kept interface-type grammar).  D6 SHIPPED: a fixity
  declaration now governs its WHOLE scope — block or module — in both
  buckets; the fused textual-order asymmetry (uses before the decl were
  unknown operators) retired with one line in FixityEnv.lookup.
  "Multiple fixity definitions" still refuses duplicates.  Four pins
  flipped to the positive semantics (two in TestStage1Pins, two in
  TestReassoc).  D8 decided: import-bypassing desugar resolution stays
  — it is the language contract the stdlib is written against.
  gatherBindings/checkBindings/implicitBindingSpan deleted from
  syntax/Statement.scala (orphaned by D3).  Suite 869 (868+known),
  repl 4, lsp 31/31, boot 129.  REMAINING DEBT: D7 statement-extent
  scanner — the Stage 2 prerequisite.

- 2026-08-31 (D7 — DEBT COMPLETE): surface/StatementExtents.scala — the
  pure lexical statement-extent scanner (Stage 2's recovery primitive).
  Handles line/block comments as whitespace anywhere, string and char
  literals (a lone quote is the (') operator), explicit-bracket depth
  keeping items open across dedents, and the let-in closer (an `in` for
  an open `let` continues the item even at the layout column —
  Report.e:1004 found it immediately).  The virtualLeftBrace
  col-max-depth merge corner is documented in the header: an inner
  block at exactly the top column reads as a new item, same as the
  parser's own per-character-offside splitter.  Differential vs the
  surface parser across all 180 corpus files: starts agree exactly
  (1000+ statements), scanner ends sit within the parsed span and
  before the next statement.  Suite 871 (870+known), repl 4, lsp 31/31.
  THE POST-G1 DEBT LIST IS DONE.

- 2026-08-31 (5.1 — the tolerant read path): NewPipeline grew
  `readModuleTolerant`, and `readModule` is now the SAME traversal with
  tolerance off.  Diagnostics are structural (`Diag(phase, span,
  message)`) and collected from every phase; `render` is the one
  renderer both paths use, so the batch refusal text cannot drift.
  Strict mode short-circuits at a phase boundary and guards nothing, so
  it dies exactly where it died before — including on raw crashes.
  Tolerant mode guards EACH statement (collectBlock, walk, pairSigs)
  against Refusal, Lower.Unsupported, Death and any other NonFatal, per
  the review finding that a Death-only collector would crash the editor
  path on the SErrorTerm/STyError nodes Reassoc leaves behind.  Two
  invalid LSP positions fixed on the way: assemble's cross-block
  interleaved-equations refusal (was Span(0,0,0,0), now the colliding
  equation's head) and Reassoc.yard's two operand-stack refusals (were
  Span(0,0,0,0), now the enclosing chain's span — found by the new
  corpus sweep, on Interp.e).  Syntax diagnostics take their END from
  D7's StatementExtents (matched to the SErrorStatement by start), so a
  broken statement squiggles over itself instead of over the blank lines
  after it; the START, which is all the strict path renders, is
  unchanged.
  LSP: `Resident.checkFile` now hoists Session.load's OWN import step
  (Session.scala:718) out in front of the tolerant read, so the read
  sees the env the strict reader sees inside `Session.load` — imports
  in, the module's own globals NOT.  That ordering is load-bearing, not
  cosmetic: re-reading an already-loaded module makes its own globals
  arrive as imports and every top-level head draws "would shadow global
  definition" (137 of 180 corpus files, measured).  Type checking is
  still strict `Session.load`, run only when the read is clean — with
  diagnostics outstanding it would merely re-report the earliest of
  them.  The navigation index is now rebuilt from the same parse that
  produced the diagnostics, so a broken file's healthy statements
  navigate instead of decaying to the last clean save.  Diagnostics
  publishes real RANGES now (start..end), not zero-width carets.
  New suite TestTolerantRead (8 properties): the 180-file sweep runs in
  DEPENDENCY ORDER (each module read with its imports loaded and itself
  not) and asserts both agreement — strict is silent exactly when
  tolerant is, and its refusal is byte-identical to `render` of
  tolerant's FIRST diagnostic — and silence, 176/180 clean.  The four
  that are not are exactly the examples "all interesting examples load"
  leaves out: Sample.e (explicit layout, unshapeable by the splitter —
  both readers die identically), HelloWorld.e, Interp.e, Yahoo.e.  Plus
  per-phase pins (syntax/rename/reassoc/assemble), the cross-block span,
  two broken statements giving two diagnostics, and healthy neighbours
  surviving.  lsp-smoke +8 (39): Ugly.e's range covers its statement,
  Broken.e publishes two syntax diagnostics at the right lines with
  non-empty ranges, and goto-definition on that broken file answers for
  both a same-file binder and a sibling-module global.
  Suite 879 (878+known), repl 4, lsp 39/39, boot 129.

- 2026-08-31 (5.2 — precise in-statement syntax positions): the D3
  coarsening is repaid.  `SurfaceParsers.statement` is factored into
  `statementAlts(binding) | rawStatement`, and the new
  `statementFailure(file, contents, extent)` re-runs the real grammar
  over one broken statement's extent to recover the failure the
  splitter's `.attempt` threw away.  Three things make it land right:
  the recovery runs the binding alternative WITHOUT `.attempt` (that is
  the whole point — the committed failure is what carries the
  position); the slice starts at the beginning of the statement's first
  LINE with `offset` moved to the statement, so the caret line reads
  whole and every later position is already absolute; and the layout
  stack is seeded at the statement's OWN column (its block's layout
  column) over the top-level context, since scalaparsers defaults to 1
  and inner vsemi decisions drift for anything more indented.  The
  extent must parse ENTIRELY (`<< eof` on the slice), so a prefix
  parsing is not mistaken for the statement parsing; a re-parse that
  still succeeds falls back to the extent and the coarse message, per
  the review's requirement (b).  `offsetOf` counts columns the way
  Pos.bump does (tab to the next multiple of 8, CRLF's '\r' an
  ordinary column), so CRLF sources map correctly.
  Positions moved for BATCH refusals too, deliberately: Decision (f)
  makes error text/anchor drift a log entry, not a gate, and the D3
  entry promised "Stage 2 restores in-statement precision" for exactly
  this refusal.  One code path, so TestTolerantRead's strict/tolerant
  byte-identity property still holds.  Ugly.e is back at 3:5 with
  "expected ... term atom ..." instead of "unparseable statement" at
  3:1.  Cost is zero on clean loads — the re-parse only runs when an
  SErrorStatement exists.
  FOUND, NOT FIXED: the splitter's prefix-parse hole — filed as 5.2b
  above and next in the queue.  It is why the obvious continuation-line
  fixture (`a +` / `b +` / `= answer`) could not be used: the statement
  parses as a prefix, the leftover has no home, and the whole module
  parse dies before any SErrorStatement exists.
  lsp-smoke +4 (43): Ugly.e at line 2 char 4 with an expectation
  message, Broken.e's two diagnostics on their offending tokens (the
  second `=`, the `)`), and a new Cont.e fixture whose error is blamed
  on the continuation line while `fine = answer` below it still
  navigates to Good.e.  TestTolerantRead +1 (9): the two syntax pins
  now assert the precise column, one of them on a continuation line.
  Suite 880 (879+known), repl 4, lsp 43/43, boot 129.

- 2026-08-31 (5.2b — the splitter is TOTAL): `statement` becomes
  `((statementAlts(bindingStatement) << atLayoutBoundary).attempt |
  rawStatement)`, closing both ways the splitter used to lose a whole
  module.  (1) PREFIX PARSE: the real grammar succeeded on a proper
  prefix of the extent and the leftover had no home, so
  `sepEndBy(semi)`/virtualRightBrace died — `atLayoutBoundary` now
  requires the next significant character to open a new layout item
  (at or left of the layout depth, or end of input, or an explicit
  `;`/`}`), and a statement that does not fill its item falls through
  to the extent capture.  (2) COMMITTED FAILURE OUTSIDE the binding
  alternative: `|` short-circuits on an Err, so a broken `data` head
  or sig never reached `rawStatement` at all — the `.attempt` moved
  from the binding alternative to the WHOLE real grammar.  Since 5.2
  recovers the committed failure by re-parsing, nothing is lost by
  capturing first and asking later: positions stay the parser's own.
  `atLayoutBoundary` is purely lexical (StatementExtents.skipTrivia,
  new) BECAUSE `layout` pops layout contexts and so cannot be used to
  peek.
  Corpus differential clean: TestStatementExtents' 180-file
  start/end agreement, TestSurfaceParsers' splitter coverage and
  rejected-corpus dispositions, and the tolerant sweep's 176/180 all
  unchanged — no clean file's shaping moves.
  ROOT-CAUSED A NEW FLAKE rather than re-running it: the corpus sweep
  failed about one full-suite run in three with "159 of 180 read
  clean" and a parade of "would shadow global definition".  Cause:
  ErmineFixture.loadModules writes its result back into baseEnv, and
  ScalaCheck runs a Properties object's properties CONCURRENTLY, so
  the sweep's session inherited whatever the pin properties had
  already loaded — and a module read while itself loaded sees its own
  globals as imports.  Fix: the sweep gets its own ErmineFixture (the
  fixture's scaladoc says one per Properties instance; a writeback-
  shared baseEnv needs one per PROPERTY), plus a precondition guard
  that names the cause instead of leaving a confusing count.  Four
  consecutive full-suite runs green after the fix.
  lsp-smoke +4 (47): a new Prefix.e fixture — the `a +` / `b +` /
  `= answer` shape 5.2 could not use — publishes one diagnostic blamed
  on its leftover, and `fine = answer` below it still navigates to
  Good.e.  TestTolerantRead +2 (11): five broken shapes all still
  shape the module with their healthy neighbours intact, and the
  prefix parse is blamed at the leftover.
  Suite 882 (881+known), repl 4, lsp 47/47, boot 129.

- 2026-08-31 (5.3 — in-memory documents): the server checks the BUFFER
  now, not the saved file.  TextDocumentSync is FULL (change: 1), and
  lsp/Documents.scala is the per-uri record — text, version, and the
  navigation index folded together, because a check, a definition
  request and the sibling loader all have to agree on what the file
  currently says.  Definitions.Docs is gone into it.
  `Session.Buffer(fileName, contents, version)` is the new SourceFile,
  per the review's requirement: identity is CONTENT-BEARING and
  lastModified IS the document version.  Both halves matter, and the
  suite pins both — Literal's module-name keying would replay one
  editor's text into every other session's load of that name, and a
  Filesystem dep's mtime does not move when a buffer changes, so the
  dep built from the SAVED text would be served back (the D0/D3-part-3b
  poisoning class).  Superseded buffers are evicted from depCache on
  each edit; that is hygiene, the mtime guard is the correctness.
  ONE TRAP FOUND THE HARD WAY: SourceFile.toString is the fileName
  threaded into every ParseState and every Pos built from one, so
  decorating it ("Bad.e<buffer 1>") silently broke both the Diagnostics
  position regex and every definition location — TestEditorBuffers pins
  it now.
  checkFile resolves through open buffers FIRST (`docs.loaderFor(dir)`
  ahead of the filesystem loader), so a cross-file check sees a
  sibling's unsaved edits; the buffer loader does not require the file
  to exist, which is exactly the never-saved-module case the filesystem
  loader cannot serve.
  Debounce without a second thread or a queue: `Server.onIdle` runs
  deferred work when `pending` says there is some AND the input stream
  has been quiet (`Wire.ready`, ~300ms).  With nothing pending the loop
  blocks on the stream exactly as before, so ordinary traffic pays no
  latency.  didOpen and didSave are acts and check at once; didChange
  is a keystroke and only queues, one entry per uri, with the versioned
  drop guarding the case where a newer edit was handled while an
  earlier check ran.  Measured in the smoke log: didChange 15.085 ->
  check 15.396, 311ms.
  lsp-smoke +10 (57): sync asserts change == 1; a new Edit.e fixture is
  broken and fixed through didChange alone with diagnostics appearing
  and clearing and NO save (and the file on disk verified untouched); a
  definition that moves down a line is found at its new position; and
  the SIBLING check — Good.e's buffer moves `answer` down a line and
  goto-definition from Edit.e lands on the new line, in text that was
  never written to disk.  New suite TestEditorBuffers (6).
  Suite 888 (887+known), repl 4, lsp 57/57, boot 129.

- 2026-08-31 (5.4 — tolerant type checking):
  session/TolerantCheck.scala is the editor-path variant of
  loadModule's phases — a NEW entry point beside it, never a flag
  inside it, and it installs nothing (the caller checks a session copy
  that is thrown away).  The statement phases (fields, foreignData,
  typeDefs, foreigns, tables) run one unit at a time under a catcher.
  THE STRUCTURAL POINT, per the review: EACH BINDING SCC INFERS IN ITS
  OWN SubstEnv.  A Death part-way through a component leaves its
  half-solved metas bound on module-wide shared placeholder Vs, and
  every later component would then be inferred against them — reporting
  consequences of the first error instead of its own.  Only the
  generalized `subs` crosses a component boundary, which is the
  structure inferBindingGroupTypes already had; the explicits loop
  likewise checks each binding in its own SubstEnv.
  A component that fails, and TRANSITIVELY any component depending on
  a failed or skipped one, is reported "unchecked: depends on a broken
  definition" (LSP severity 3, Information — it is not an error, and
  one broken definition can gray out half a file).  They are never
  inferred against unconstrained metas: they would typecheck to lies,
  and `types` deliberately omits them.  Undefined terms are one note
  per name instead of assertTermClosed's single vsep'd Death, and each
  carries its SPELLING — which is what Resident matches against the
  head word of every statement the splitter could not parse, so one
  syntax error does not light up every reference to the name it was
  going to define.  A binding that mentions an undefined term is failed
  SILENTLY (the undefined term is the explanation); its dependents
  still say unchecked.
  The editor path no longer runs Session.load at all, so two things
  moved with it: hover on the module's own top-levels now reads
  TolerantCheck's `types` (which also means a broken file's healthy
  definitions keep their hovers), and Dep.checkNames' import-list
  requirements are re-done in checkFile — dropping them silently would
  have lost a diagnostic class.
  SILENCE ON GOOD CODE is the property that matters most and it is
  pinned where it cannot rot: TestTolerantRead's 180-file sweep now
  type checks every module it reads clean and requires zero notes
  (176/176; the sweep went 40s -> 51s).  TestTolerantCheck (7) covers
  what needs broken input: two independent errors both reported, an
  earlier failure leaving a later independent component alone,
  transitive unchecked with no types minted, undefined-term spelling,
  no second note on a silently-failed binding, and the healthy part of
  a broken file still checked.
  DO-ANCHOR GAP: still pinned as-is.  The blame lands on the bind rhs
  because the checker infers the continuation lambda independently and
  clashes at the subsume — nothing about per-SCC ordering makes that
  cheaper to fix, so it stays Stage-3 diagnostics debt.
  lsp-smoke +11 (68): TwoErr.e publishes BOTH type errors (loadModule
  would report only the first); Cascade.e publishes its syntax error
  and the healthy definition's type error with NO undefined-term
  cascade; Chain.e publishes one error and two Information "unchecked"
  notes, the second of them transitive.
  Suite 895 (894+known), repl 4, lsp 68/68, boot 129.

- 2026-08-31 (5.4b — a module must not be in scope while it is checked):
  found while taking 5.5's baseline measurement, which is the only
  reason it was found at all: opening Layout/Report.e in the editor
  published 329 diagnostics, every one of them "term definition would
  shadow global definition".  CAUSE: every module implicitly imports
  ITSELF (ModuleParsers.scala:34, `Map("Builtin" -> all, name -> all)`),
  and the resident session holds the whole Prelude/Layout closure — so
  for any of those 129 modules, checkFile's scope contained the
  module's own globals and topLevelHeads refused every head.  5.1's
  import hoist stopped US from loading the module under check; it could
  do nothing about the module the BOOT had already loaded.  (Latent
  before 5.1, which is when renamer diagnostics started being
  published rather than discarded — so: my regression, ~15 hours old.)
  FIX: scrub the module out of the check COPY first, exactly the way
  Session.reloadChangedModules' scrubber does — env, termNames,
  termNameOrigins, cons, privateCons, consOrigins, classes,
  classOrigins, loadedFiles, loadedModules.  lsp-smoke +1 (69): open
  the stdlib's own Bool.e and require zero diagnostics.
  Suite 895 (894+known), repl 4, lsp 69/69, boot 129.

- 2026-08-31 (5.5 — per-SCC inference reuse).  MEASURED FIRST, on
  Layout/Report.e (1757 lines), and the measurement revised one of this
  item's own premises.  Before: read 0.89s + typecheck 1.03s,
  keystroke-to-diagnostics median 2.24s (0.30s of it the debounce).
  After: read 0.80s + typecheck 0.45s, 114 of 154 components reused,
  median 1.57s.  So a 56% cut in inference and 30% end to end — but
  parse+rename+lower is NOT the cheap part the checklist assumed
  ("inference dominates; the perf ticket's own finding"): at 0.80s it
  is now 64% of the remaining work.  Whatever comes after 5.5 should
  aim there, and the perf ticket should be re-read with this number.
  DESIGN.  Parse+rename+lower runs whole every check, as the review
  required (fresh binder ids make cached trees unmixable).  The reuse
  unit is a binding SCC, keyed by a fingerprint of its own group text
  plus the fingerprints of the module-local groups it references —
  fingerprints, not inferred types, because they are alpha-invariant by
  construction while every V in a fresh run has a fresh id.  A group is
  one spelling's sig AND equations (module-wide pairing by shared V),
  and explicit bindings are groups too, so a sig edit invalidates the
  dependents that were inferred against its annotation.  START LINES
  are in the group text and note-bearing components are never cached:
  between them a reused entry cannot carry a note or a Loc that has
  drifted.  Scope-bearing edits — imports, fixity, type/data/class/
  field/table/foreign, private and database blocks, any change to the
  top-level head set, and the versions of the OTHER open buffers —
  move the scopeKey and drop the whole map.  A spelling the extent
  scanner cannot name (operators) is simply never cached.
  A no-op-looking edit taught something worth writing down: appending
  trailing whitespace changes NO fingerprint, because an extent ends
  just past its last significant character.  The first measurement used
  exactly that edit and flattered the cache; the numbers above are from
  a real in-body edit.
  TestTolerantCheck +7 (14): the cache is INVISIBLE — a body edit, an
  edit that introduces an error, one that fixes it, and a signature
  edit each produce byte-identical notes and types warm and cold; a new
  definition or a scope-key change reuses nothing; an unchanged module
  reuses every component.  lsp-smoke +4 (73): breaking an UPSTREAM
  definition through didChange reports it AND unchecks its dependent
  (invalidation reaching downstream, not masked by a stale entry), and
  fixing it clears both.
  Also ticked the stale Stage-1 4.1 box — completed at 4.1c on
  2026-08-30 and covered by the G1 sign-off; it was only ever unticked
  because the item was split into 4.1a/b/c.
  Suite 902 (901+known), repl 4, lsp 73/73, boot 129.
- 2026-09-08 LSP-FFI (a DETOUR, not Stage 3; the loop stays stopped at G2):
  the server now tolerates a `foreign` declaration whose class or member
  this JVM does not have.  The user is pointing it at an older Scala 2
  fork whose divergence IS the FFI (the writer trait), and today any
  foreign resolution failure kills its module at load, which the editor
  showed as ONE diagnostic for the file with every dependent unchecked.
  A session option `ermine.foreign.tolerant` (`SessionEnv._foreignTolerant`)
  is ON in `Resident` and OFF everywhere else: the binding is installed at
  its DECLARED type as a `Bottom` stub, so the module and its dependents
  type-check, navigate and hover, and only EVALUATING it fails; the
  failure becomes a warning (severity 2) positioned on the class-name or
  member string it is about, carried as a `TolerantCheck.Note` with a real
  Span.  All nine failure kinds: class missing, class unloadable, member
  missing, arity mismatch, return type not assignable, field missing,
  constructor missing, subtype of a missing class, and `foreign data` of a
  missing class — which is SILENT (an opaque type needs no class) and
  warns only at the site that needs it, the test being
  `Type.foreignLookup == classOf[UnresolvedForeign]`.  Also fixed in BOTH
  modes: `ForeignClasses.classLookup` caught `Exception`, so a class that
  is present but will not LINK threw `NoClassDefFoundError` past it — an
  uncaught crash in batch, and in the editor no diagnostic at all (it
  unwound to Rpc's notification guard).  With the option off the batch
  before/after diff over twelve fixtures is that crash becoming a
  positioned `error loading '…'`, and nothing else.  Report
  `tracker/LSP-FFI-TOLERANCE.md`; fixtures `tracker/lsp-tests/Ffi*.e`.
  Gates: compile+copyResources, TestLoopTrace 720/720, corpus --batch
  85/69/0 over 154, lsp-smoke 150 (98 + 52 new), repl-smoke 7/7 with the
  five old goldens byte-unchanged plus `ffi` and `ffi-tolerant`
  (repl-smoke grew a per-case `<name>.opts` file for JVM flags),
  core/test 938/938, boot 129 modules in 12.5-13.4s.
- 2026-09-09 LSP-FFI fix round, after an independent review
  (tracker/loopmodel/LSP-FFI-REVIEW.md, FIX-THEN-ADVANCE; it reproduced
  every gate, rebuilt all nine kinds against its own modules and probe
  classes, and showed default-off byte-identical over all 154 corpus
  outputs against a compiler built from HEAD).  The BLOCKER: the
  NoClassDefFoundError hole closed at `Class.forName` was still open one
  layer down.  `getMethod`/`getField`/`getConstructor` resolve the
  signature classes of everything they search, so a class that LOADS but
  whose members mention an absent class threw an Error past
  `TolerantCheck.guard` AND `Diagnostics.run` into Rpc's notification
  guard — the file was published NOTHING, which is the very symptom the
  stage claimed to fix, and is exactly the shape of a stale fork jar.
  Fixed by naming the catch set once (`parsing.Recoverable` = NonFatal
  plus the LinkageError family), using it at all four reflective sites
  and at both guards, adding `member/field/constructor unloadable` kinds
  at the member span, and giving the Error path a POSITION in default
  mode (it was an uncaught crash before, so no message moved).  Also
  adopted: an Information note (severity 3) for a `foreign data` whose
  class is missing — the opaque type is fine, but total silence made a
  stale FFI indistinguishable from an intact one; exact literal spans
  (`spanned` ends a token where the next begins, so every class/member
  range ran one character long); the REPL rollback keeps its warnings; a
  negative class-lookup cache (measured: 3 ms of a 324 ms round trip on a
  40-binding file — kept for determinism of cost, not speed);
  `TypeConDecl.isInstance` raises on the sentinel instead of silently
  answering "no match"; and a SELF-CONTAINED probe jar
  (tracker/lsp-tests/jsrc + tracker/tools/build-probejar.sh: compile
  `Missing`, then delete it) replacing the log4j-dependent kind-2
  fixture, which also gives the three linkage regressions.  Gates:
  TestLoopTrace 720/720, corpus 85/69/0 over 154 AND 0 of 154 outputs
  differ from the pre-fix run once timings are normalised, lsp-smoke 181
  (98 + 83 new), repl-smoke 7/7 with the five old goldens still
  unmodified, boot 129 in 12.8s.

## Gate evidence (G2, recorded 2026-08-31)

Stage 2 shipped in seven commits, b401325..HEAD, on branch
scala3-migration.  Every one of them was green on all four baselines
before it landed.

BATCH STRICTNESS FROZEN — the gate's hard half.  Across the whole
stage (`git diff f7aaed6..HEAD`), the only batch-path file touched is
Session.scala, at **27 insertions and 0 deletions**: the `Buffer`
SourceFile subclass plus its two cases in sourceFileTypeScore /
sourceFileOrdering.  Nothing was removed or altered.  The REPL golden
corpus (tracker/repl-tests/*.expected) is byte-unchanged, and
repl-smoke's four suites pass unmodified.  Error tolerance lives
entirely in new entry points — NewPipeline.readModuleTolerant beside
readModule, TolerantCheck beside loadModule — never in a flag inside a
strict one.  TestTolerantRead's agreement property is the standing
tripwire: over all 180 corpus files, the strict reader is silent
exactly when the tolerant one is, and when it dies it dies with the
tolerant reader's first diagnostic rendered byte-for-byte.

BASELINES AT GATE
- core/test: 902 total, 901 pass, 1 fail — `Constraints.disjunction
  sound`, the one known pre-existing failure (tracker/06-tests.md).
  Was 871 when the stage opened; +31 are this stage's own pins.
- tracker/tools/repl-smoke.sh: 4 suites PASS (aliasing 2, relations 6,
  scoping 4, smoke 23).
- tracker/tools/lsp-smoke.sh: 77 checks PASS (31 when the stage
  opened).
- bin/ermine: Loaded 129 modules, 6.0s warm.
- No .ei droppings in tracker/lsp-tests.

WHAT THE GATE ASKED FOR, AND WHERE IT IS CHECKED
- multi-diagnostic broken files: Broken.e publishes two syntax
  diagnostics on their offending tokens; TwoErr.e publishes BOTH
  independent type errors, which loadModule structurally cannot do.
- didChange without save, including the sibling-buffer check: Edit.e is
  broken and fixed through didChange alone with the file on disk
  verified untouched; Good.e's buffer moves `answer` down a line and
  goto-definition from Edit.e lands on the new line, in text never
  written to disk.
- positions per 5.2: Ugly.e is back at 3:5 with an expectation message;
  Cont.e is blamed on its continuation line; Prefix.e on its leftover;
  Nested.e inside its where-block.
- both type errors per 5.4: TwoErr.e, plus Cascade.e (a broken file's
  healthy definition still checked, no undefined-term cascade) and
  Chain.e (one error, two transitive "unchecked" notes).
- nav after didChange: a definition that moves down a line is found at
  its new position without a save.
- a timing line from 5.5: Layout/Report.e, 1757 lines —
  keystroke-to-diagnostics median **2.24s before, 1.57s after**;
  inference 1.03s -> 0.45s, 114 of 154 components reused.

TWO THINGS FOUND THAT THE CHECKLIST DID NOT ANTICIPATE, both fixed and
pinned: the splitter's prefix-parse hole (5.2b — a statement parsing as
a proper prefix of its extent killed the whole module parse, so the
file got no diagnostics at all) and a module being in its own scope
while checked (5.4b — every module implicitly imports itself, so any of
the 129 already-loaded stdlib modules drew a shadow refusal on every
top-level head; 329 of them on Report.e).

ONE NUMBER WORTH CARRYING FORWARD: after 5.5, parse+rename+lower is
0.80s of the 1.57s round trip — 64%, not the rounding error the
checklist's "inference dominates" assumed.  tracker/TICKET-perf-type-
inference.md should be re-read against that before Stage 3 picks a
target.

STOP.  The loop is stopped for sign-off, per the gate.

## Post-G2: navigation for every declaration (2026-09-02)

Not a Stage-3 item — a defect found by asking for go-to-definition on a
`field`.  Only names the RENAMER binds (equations, signatures, local
binders) and imported ordinary terms answered `textDocument/definition`.
Everything installed by the SESSION instead answered null: `field` and
`table` declarations, data constructors, every foreign declaration, and
every imported TYPE.

ROOT CAUSE, one line.  `Session.primOp` took a `loc` argument and built
its variable with `Loc.builtin` anyway (Session.scala:69), so the
definition site of every name it installs was discarded at installation.
`Definitions.index` read `v.loc` for its navigation target and got
`builtin`, which is not a file.  Fixed by keeping the argument, and by
passing a better one where the statement position was standing in for a
name position: `field a, b : Int` declares two names at two columns, and
foreign/table declarations name themselves after their keyword.  The
2-arg overload still passes `Loc.builtin`, so Scala-installed builtins
(`Just`, `True`, `Int`, `Maybe`) keep answering null — correctly: they
have no source.

THREE MORE GAPS, all in `lsp/Definitions.scala`:
- Type occurrences looked their Global up in `termNames`, which only
  holds terms, so no imported type ever navigated.  They go through
  `env.cons` now.  `data Color = Color Int` gives ONE Global to a type
  and a constructor, so the table cannot be chosen by fallback order:
  `Renamer.Occurrence` carries a `typeLevel` flag (set by the type-side
  walk's new `occurTy`) and the flag picks the table.
- `Inferred(p)` is a real position wearing a report-time wrapper, and
  field cons carry it; `positionOf` reads through it.
- Declaration HEADS were not occurrences at all, so hovering the `fa` in
  `field fa : Int` said nothing where `fa` a line below said its type.
  The heads come from the surface tree (`ownDecls`), which also serves as
  the navigation fallback when the session has nothing — that is what
  keeps own-field and own-constructor navigation alive in FAST MODE and
  in a file whose check died.  Operators named in a fixity declaration
  point at their equation; `import Layout.Scan` points at the file, via
  `loadedFiles` inverted.

VERIFIED: core/test 903/904 (the known `Constraints.disjunction sound`),
repl-smoke 4/4, lsp-smoke 98/98 (+16, fixture `tracker/lsp-tests/Decls.e`
covering own/imported fields, constructors, foreigns, types, aliases,
declaration heads, fixity mentions, imports, a fast-mode pair and the
undefined-name miss), bin/ermine 129 modules.  Layout/Report.e checks in
0.90s read + 1.05s cold typecheck, unmoved.  Interfaces are unaffected:
`writeInterface` prints name and type only.
