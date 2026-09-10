# Ermine LSP roadmap — loop state file

This file is the durable state for the /loop driving the LSP work. Each
iteration: read this file, do the next unchecked item, verify against the
baselines, commit, tick the box, append one line to the iteration log.
Design forks not settled under "Decisions" go under "Blocked/Awaiting" and
stop the loop. Full rationale: tracker/TICKET-scoping-renamer.md (LSP
section) and tracker/TICKET-perf-type-inference.md (latency work, needed
before type-at-point features).

Status: STAGE 4 OPEN (2026-09-10).  G3 SIGNED OFF 2026-09-10 (the user:
"fold the stage 4 draft in and open it").  Stage 3 shipped 6.0-6.7 (6.2 as
PARTIAL; the pattern-binder Subst.scala FORK stays under Blocked/Awaiting,
the user's decision).  Stage 4 checklist 7.0-7.6 + GATE G4 below, folded in
from the draft; the prior-art survey is tracker/loopmodel/STAGE4-PRIOR-ART.md.
7.0 DONE: parse is 98% of the read (844 of 860 ms), per-statement
parse work is ~58% of the check, VERDICT 7.1 (statement cache) with 7.2
first; 7.3 re-ranked to the batch target.  NEXT: 7.2 (anchored positions:
the +0.52 s top-of-file cliff), then 7.1a (Tier 1 high-water mark) and 7.1b.  Orchestration as in Stage 3: brief -> fresh Opus
implementer -> fresh Opus reviewer -> Tier 0 -> commit.
· Seeded 2026-08-30 (session that shipped the scoping fix, commits f9cf42a /
41b13cc).

## Baselines (hard invariants — never commit red)

- `sbt -batch core/test`: all green — 988/988 at GATE G3 (2026-09-10; 943
  at F4 plus Stage 3's properties); two consecutive full runs of the final
  tree agree.
  `Constraints.disjunction sound` is QUARANTINED behind
  `-Dermine.test.disjunction=true` (tracker/GATE-POLICY.md), so "green"
  means green; it was 761/762 with that failure visible at Stage 0.
  Suites GROW, so a commit that adds tests updates the count in its
  iteration-log line.  The F4-era intermittence (942 + 1 error one run
  in two, `Module not found: 'Test'`) was FIXED by Stage 3 item 6.0 on
  2026-09-09: a test flipped `ermine.loadInSeries` process-wide.  Three
  consecutive full runs 943/943 since; a red run is real again.
- `tracker/tools/repl-smoke.sh`: all suites PASS (8 groups / 66 checks as of
  2026-09-09 — `ffi` and `ffi-tolerant` were added by the LSP-FFI detour; the
  gate policy's "7/7" and this line's old "4 as of D2" were both stale)
- `tracker/tools/lsp-smoke.sh`: all checks PASS (456 after Stage 4 item 7.0,
  2026-09-10; 454 at GATE G3;
  407 after 6.5; 344 after 6.4; 306 after 6.3; 237 after 6.2; 207 after 6.1; 185 as of 2026-09-09,
  re-measured when Stage 3 was planned; 98 after the 2026-09-02
  declaration-navigation work, 181 after the LSP-FFI fix round; it read
  82 before that, the G2 line's 77 having gone stale)
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

## Stage 3 — types at every binder, and the editor features the tables already pay for (checklist, planned 2026-09-09; G2 signed off 2026-09-09)

GOAL: the editor answers hover on LOCAL binders and on type names, finds
references, renames, lists symbols, completes names, and offers the two
quick fixes Ermine code needs most (add import, add signature) — all from
the tables the last check already built, at no added per-keystroke cost
beyond one budgeted substitution walk.

WHAT CHANGED SINCE THE STAGE-2 PLAN, and shapes this one:
- The perf premise moved.  Stages 0, 1 and 2 each gated hover-on-locals
  on tracker/TICKET-perf-type-inference.md ("type-at-point needs faster
  inference").  Since 5.4 the editor path RUNS inference on every check,
  one fresh SubstEnv per binding SCC (TolerantCheck.checkWith), and Lower
  gives every local binder V a fresh meta as its type (Lower.Ctx.binderV
  via `unspecified`).  So a local's type is one `Subst.substType` under
  that component's SubstEnv, inside a block that already exists — a zonk
  per binder, not a check.  The gate is no longer latency; it is keeping
  the walk cheap and the strict path untouched.
- The perf loop has moved NEITHER target (PERF-ROADMAP status: P1/P2/
  P5(a) done, "neither target has moved measurably"; the editor floor is
  ~50 ms and the read, 0.80 s of Report.e's 1.57 s, dominates).  So
  nothing in this stage may add a check, an inference or a parse to any
  REQUEST path: every request answers from tables the last check built.
  The one per-check addition (6.2's zonk) has a measured budget.
- Hover on an arbitrary SUB-EXPRESSION is out of reach and out of scope:
  inference does not annotate the tree (only `Remember` nodes leave
  `hm.remembered`).  Binders only.  A typed-tree design is Stage 4+ and
  belongs with the perf ticket.
- Post-G2 (2026-09-02) navigation already covers every declaration kind,
  and the LSP-FFI detour (2026-09-08/09, committed) made the server
  survive a stale FFI.  Both are DONE and not repeated here; their
  fixtures are the floor lsp-smoke starts from (185 checks, re-measured
  2026-09-09 at planning).

STAGE-3 INVARIANTS (hard):
- BATCH SEMANTICS STAY FROZEN (the Stage-2 invariant, unchanged).  6.2
  touches TolerantCheck and reads Lower's binder Vs; both are editor-
  path.  `Session.load`/loadModule, the REPL goldens (tracker/repl-tests/
  *.expected) and TestReplDifferential stay byte-identical;
  TestTolerantRead's 180-file agreement property stays the tripwire.  If
  an item needs a change in Subst.scala or Type.scala, that is Tier 1
  (GATE-POLICY) and the item stops to say so before making it.
- NO REQUEST TRIGGERS WORK.  hover/definition/references/rename/symbols/
  completion/codeAction read Documents' stored index and TolerantCheck
  results.  Staleness between a keystroke and the next debounced check
  is ACCEPTED and documented, never papered over with an inline check.
- Single-threaded dispatch stays (Decision 3).  A request that arrives
  during a check waits for it.  The gate records that worst case (one
  Report.e check, ~1.3 s).  A worker-thread check is a PARKED Stage-4
  fork (Blocked/Awaiting), not a Stage-3 side quest.
- Decision 5 stays: the resident session is interface-free.
- Every sweep covers stdlib AND core/examples (the 180-file rule).
- lsp-smoke's count GROWS with each item; the Baselines note is updated
  in the same commit.  docs/lsp.md is refreshed at the gate (it still
  says 82 checks).
- GATES per tracker/GATE-POLICY.md.  Tier 0 before every commit
  (compile+copyResources, TestLoopTrace 720/720, corpus --batch
  85/69/0 over 154, repl-smoke 7/7, lsp-smoke).  Items touching
  TolerantCheck/Lower/Renamer/Definitions also run
  `testOnly *TestTolerantCheck *TestTolerantRead *TestEditorBuffers
  *TestRenamer *TestLower`.  Tier 1 only if the solver, Type.scala's
  constraint construction or executable Lean is touched (not expected).
  Tier 2 (full `core/test`, ALONE on the tree) once, at G3.  Implementer
  runs, reviewer re-runs once, orchestrator runs Tier 0 — no third full
  run (6.0 is the documented exception).  One JVM at a time.  Never
  commit red.

### Stage-3 Decisions (append-only; override with a note, not silently)

- (a) Local hover shows the binder's MONOTYPE after solving, with the
  enclosing binding's generalized metas rendered as type variables; no
  `forall` on locals (the top-level's hover shows the scheme).  Explicit
  local signatures show as declared.  Rendering uses the same printer
  as top-level hover.
- (b) Local types are collected in the editor path only: `checkWith`
  grows a `wantLocals` parameter (default false; `check` keeps false).
  A reused 5.5 cache entry carries its locals: valid because the
  fingerprint contains the group's start lines AND its whole text, and
  top-level statements start at column 1, so any edit that could move a
  def-site changes the key.
- (c) Workspace = the open buffers + the resident session's loaded
  modules + the `.e` files under the checked file's module root (for
  import completion).  No persistent workspace index in Stage 3.
  References and rename SAY what they covered: a `window/showMessage`
  warning whenever unopened importers may exist.
  AMENDED 2026-09-10 (6.5, review F-7): for completion the module-name
  workspace has a FOURTH source — the modules THIS file's check loaded
  (`Layout.Scan` is in none of the other three).
- (d) Rename never edits a file that is not open; never renames to or
  from an operator spelling; refuses a capture (the new name already
  bound in a frame containing an occurrence, or a global the occurrence
  would then resolve to); refuses on a stale index (document version ≠
  the version the index was built from) with a ResponseError "check
  pending" rather than a partial edit.
- (e) The 6.6 signature quick fix is offered WITHOUT server-side re-
  checking (a codeAction request fires on every cursor move; a check
  costs a round trip).  Its correctness is measured ONCE by a corpus
  sweep at the item's gate, with the shipping bar set there.
- (f) The bare-`class`-statement divergence (assemble registers nothing;
  the fused pipeline registered the head) is NOT a Stage-3 item: fixing
  it changes what batch registers, which the frozen-semantics invariant
  forbids here.  It gets its own ticket when classes matter.
- (g) 5.6 nested extents stays DEFERRED with its 2026-08-31 evidence;
  nothing in this stage needs it (completion uses renamer FRAMES, which
  are nested already).

### Checklist (each item ≈ one loop iteration; the acceptance criteria are the tick conditions)

- [x] **6.0 Suite hygiene — make Tier 2 deterministic** (debt: F4 review
  R-1, 2026-09-09; re-scoped 2026-09-09 after the user asked whether the
  flake is fixable).  THE FACT: `core/test` on one unchanged tree was
  943/943 on one run and 942 + 1 error on the other — TestLower's
  `negation applies primNeg to the whole chain` dying with
  `Death: Module not found: 'Test'`; never reproduced in isolation
  (TestLower alone 2x, with TestInterfaceConcreteRow 2x).  THE REVIEW'S
  MECHANISM IS UNVERIFIED: R-1 blamed six suites touching
  `Session.depCache`/`loadModules` without `ErmineFixture.literalLock`.
  A code read (2026-09-09) does not confirm that path: the message is
  produced only when `SourceFile.forModule("Test")` reaches
  `NotFound.contents`, i.e. when a session's `loadedModules` LACKS the
  Test entry every fixture seeds into its baseEnv (or a cached Dep names
  Test as an import, which none does — loadStatements strips it).  A
  dep-cache hit or miss cannot delete a loadedModules key; the forked
  makes merge with `+=` (a union), which cannot either; the only removers
  are the fixture writeback `:=` (under envLock, per fixture) and
  `reloadChangedModules` (no test calls it).  So: a cross-suite race in
  one JVM (`Test / fork := false`, suites parallel) is the only shape
  that fits the record, and WHICH race is not known.
  STEP 1 — PIN, budget one iteration: a probe in ErmineFixture (mkEnv
  asserts/logs when the copy it hands out lacks "Test", with the fixture
  identity, thread and the writeback history), then run the parallel
  suite — the module-loading suites together, then the full suite — up
  to five times.  A firing probe names the mechanism; the fix is written
  against THAT, and the mechanism replaces this paragraph.  A fix
  written against an unverified mechanism is how R-1's own claim came
  about.
  STEP 2 — FIX, or FALL BACK.  If the probe does not fire within the
  budget, make the harness deterministic BY CONSTRUCTION instead: tag
  the module-loading suites (TestNewPipeline, TestLower,
  TestTolerantCheck, TestTolerantRead, TestStage1Pins,
  TestEditorBuffers, the TestInterface* suites) so sbt runs them
  serially (`Tags.exclusive` / testGrouping); measure and record the
  wall-clock cost of `core/test` before and after, once each.  While
  there: the 3.5 MB/run `ermine-ei-corpus` temp-tree leak (R-5) gets a
  delete in a finally.  Probe code does not ship: it comes out with the
  fix, or stays behind a system property, the item says which.
  ACCEPTANCE: two consecutive full `core/test` runs green by the
  implementer and one by the reviewer — three in total, the ONE place
  this stage runs a tier three times, because the claim under test is
  determinism (recorded here as the exception to GATE-POLICY's "no
  third run"); the mechanism written here (or the fallback and its
  cost); no `/tmp/ermine-*` tree left behind by a run; suite count
  unchanged.  First because G3 is a Tier-2 gate, and a gate that is red
  one run in two is a gate nobody can use.
  DONE 2026-09-09 (implementer + reviewer, both Opus; reports
  tracker/loopmodel/LSP3-6.0-HYGIENE.md and LSP3-6.0-REVIEW.md).  THE
  PROBE FIRED and the mechanism is neither R-1's nor the code read's:
  TestInterfaceKey's second property set `ermine.loadInSeries=true` with
  System.setProperty, process-wide, for 14-28 ms; `Session.loadModules`
  re-reads the flag per call; `loadModulesInSeries` asks the loader for
  EVERY name without subtracting `s.loadedModules`; every fixture import
  map names the sourceless `Test` — so whichever concurrent property was
  loading died.  Deterministic under the flag (TestLower 28/28 with the
  exact message); the window observed live 5/5 pre-fix, 0/3 post-fix;
  rate ~0.43 deaths per full run against one-in-two observed.  The code
  read's negative was right (no `loadedModules` key is ever removed; the
  dying session had `Test` all along) and its positive was incomplete:
  it missed that the series branch never looks.  FIX, test-side only:
  the property calls `Session.loadModulesInSeries` directly (same
  assertion, property counts unchanged 2/1/3/33); `withProps` refuses
  any property not read once at class init; the rule is written at
  ErmineFixture.  LEAK: `ermine-key` and `ermine-rt` leaked (30 trees
  deleted), now `finally`-deleted via ErmineFixture.deleteTree; the
  shared corpus deletes from a shutdown hook (lives for an interactive
  sbt JVM's lifetime, stated).  THREE full `core/test` runs 943/943
  (1,533 / 1,463 / 1,673 s).  Review verdict FIX-THEN-ADVANCE, report
  edits only (Builtin is a second sourceless module; hook lifetime).
  Follow-up ticket E5 (loader schedules agree) filed, Tier 2 + sweep.

- [x] **6.1 Diagnostics debt.**
  (a) THE DO-ANCHOR BLAME GAP (Stage-2 diagnostics debt; D3 and 5.4
  log): a type error inside a `do` bind blames the bind's rhs (line 1)
  where the fused pipeline reached the inner subterm (line 2), because
  the checker infers the continuation lambda independently and clashes
  at the subsume.  Budget: half an iteration.  Fix if it is a Loc-
  propagation change in the do-desugar or in the editor path (batch
  goldens must stay byte-identical either way); otherwise write the
  precise reason under this item and close it as ACCEPTED.  Tick
  condition: the pinned line flips to the inner subterm's, OR the
  written reason is here.
  (b) UNRECOVERABLE-DEATH POSITIONS: a header that will not parse, or an
  import that will not load, still publishes ONE diagnostic, and when
  the report names another file it lands at 0:0.  Anchor an import
  failure on the failing `import` statement's span (the tolerant read
  succeeded — only the LOAD of the import failed — so the surface tree
  and its import spans are in hand) and a header failure on the
  header's extent.  lsp-smoke: `BadImport.e` (one import that does not
  exist, one whose file has a syntax error) squiggles each import line
  with the loader's message; the file's other diagnostics still publish.
  (c) A sweep pin: over the 180 files, no editor-path diagnostic or note
  is emitted at 0:0 (TestTolerantCheck property; expected 0).
  DONE 2026-09-10, GREEN-ACCEPTED (implementer + reviewer Opus; reports
  tracker/loopmodel/LSP3-6.1-DIAGNOSTICS.md, LSP3-6.1-REVIEW.md; review
  FIX-THEN-ADVANCE, three report/fixture fixes applied, no shipped-code
  change in the fix round).  (a) ACCEPTED: the continuation lambda is
  inferred bottom-up then subsumed at the App (`Subst` has no checking
  mode), so Int and Bool first meet at the bind application; an
  intrinsic inner clash IS blamed inside (DoInner.e 8:27) and a plain
  `g (w -> w && True)` anchors the same way — the pin stays at line 1;
  the reviewer's refutation attempt (editor-only re-blame) found it
  buildable but a second checking engine, 1-2 days, declined; ticket E6.
  (b) DONE: imports load one at a time only after the batch load fails;
  each failure is an Error note on its import statement's module-name
  span carrying the loader's report verbatim; the check CONTINUES.  Rule:
  while any import failed, undefined-term and "unchecked" notes are
  withheld wholesale (flags, never text); syntax diagnostics, surviving
  imports' requirements and type errors still publish (pinned positively
  by BadImport.e's own type error).  Residual disclosed: operators and
  type names a failed module would supply still cascade read diagnostics
  — ticket E7.  Import-list "does not export" notes moved from the header
  (0:0) to the name span (BadReq.e).  (c) DONE: `Diagnostics.check` split
  from `run` so a JVM-local property drives the editor path over 253
  corpus files + 36 fixtures = 289 files, 71 diagnostics: BEFORE 2
  (BadImport.e, BadReq.e at 0:0), AFTER 0.  Known residual outside the
  corpus: group-level refusals at `m.loc` (shouldfail/sk03), recorded.
  Fixtures BadImport/BadSib/BadHeader/BadReq.e; lsp-smoke 185 -> 207;
  TestTolerantCheck 14 -> 17; docs/lsp.md paragraph added.  Perf: the
  reviewer's interleaved pair on Report.e 1.667 s before / 1.629 s after
  — inside the 50 ms floor, unmoved.

- [x] **6.2 Types at every binder** (the stage's headline; the item
  Stages 0, 1 and 2 each deferred to the perf ticket, whose premise 5.4
  dissolved).  Hover on a LOCAL binder — Arg, LetBound, WhereBound,
  DoBound, CaseBound (Renamer.BinderKind) — at its def-site and at every
  use; hover on TYPE names, own and imported, showing the kind (from
  `env.cons` / TolerantCheck's type phase).  MECHANISM: inside each
  component's `Session.subst { implicit hm => ... }` block in
  TolerantCheck.checkWith (implicit AND explicit paths), after inference
  succeeds, walk the component's alts collecting Bound Vs whose loc is a
  real Pos in this file (VarP/AsP pattern vars, Let/where binding vs,
  lambda args) and record `Subst.substType(v.extract)` keyed by def-site
  (line, col).  `Result` grows `locals: Map[(Int, Int), Type]`; cache
  entries grow to carry them (Decision b); note-bearing components stay
  uncached as before.  Definitions.index joins ToBinder occurrences ->
  BinderInfo.defSite -> locals so `Occ.hover` fills for locals; type
  occurrences get a kind hover.  RENDERING per Decision (a).
  PERF BUDGET: keystroke-to-diagnostics on Layout/Report.e, INTERLEAVED
  A/B (before/after/before/after, `tracker/tools/perf-bench.sh editor
  -k 15`, load < 1.3 on both sides): Δ ≤ 5% of the round trip (≈ 80
  ms).  Over budget -> the zonk stays behind `wantLocals=false`, the
  item moves to Blocked/Awaiting with the number, and the stage goes on
  without it.  TESTS: TestTolerantCheck — every binder kind gets a
  type; a where-bound polymorphic local shows its solved monotype; an
  explicit local sig shows as declared; cache INVISIBILITY extends to
  locals (warm == cold, byte-identical, over the 5.5 edit set); the
  180-file sweep requires every Bound V with a real Pos in a clean
  module to have a local type (no silent misses).  lsp-smoke: fixture
  `Locals.e` — hover on an arg, a let, a where, a do and a case binder,
  each at def-site and at a use; hover on a local after a didChange
  that moves its definition; hover on a local in the healthy statement
  of a broken file; hover on `Bool` and on an own `data` type shows the
  kind; a local in fast mode answers null (nothing computes it).
  DONE 2026-09-10 as PARTIAL BY THE ITEM'S LETTER, 62.4% of local binders
  typed (implementer + reviewer Opus, two review passes; reports
  tracker/loopmodel/LSP3-6.2-LOCALS.md, LSP3-6.2-REVIEW.md).  THE PREMISE
  WAS HALF FALSE.  True for BINDING HEADS: `inferImplicitBindingTypes`
  subsumes Lower's meta, so a `let`/`where` head's zonk is its type
  (LetBound 156/156, WhereBound 89/89 on the 253-file sweep).  False for
  PATTERN binders: `Lower.pattern` replaces the binder V's meta with
  `Annot.annotAny` (id -1) and `Subst.inferPatternType` mints a fresh
  meta through `unbindAnnot` into a body copy; nothing this side holds
  it, and a zonk of the binder's own meta returns an unconstrained
  variable (reproduced live by both agents).  RECOVERED WITHOUT A
  CHECKER CHANGE (the reviewer's option 4): an EQUATION'S argument
  binders are typed by splitting the head's own inferred/declared type
  by `arity` — conservative (only when the unbound chain yields exactly
  `arity` arrows; only bare VarP directly under the alt), 2872/2872 on
  the sweep, the class computed independently from the surface tree.
  Signed pattern vars read their declaration.  RESIDUAL (1900 binders,
  37.6%): lambda arguments, `case` and `do` binders, variables nested in
  constructor/tuple patterns — the FORK in Blocked/Awaiting (a
  `Subst.scala` change; the invariant stopped it for the user).
  RENDERING (Decision a): monotype via the hover printer; a binding's
  argument types share ONE letter supply with the head
  (`Pretty.prettyTypeIn` warms the letter state at REQUEST time, zero
  cost on the check path): `g : forall a b. a -> b -> a` gives `x : a`,
  `y : b`; the residual caveat (a `where` local's letters vs its
  enclosing binding's) is stated in docs/lsp.md.  CACHE (Decision b):
  `Cache.Entry` carries locals; the reviewer's five attacks on the
  drift invariant all held (column-1 top-levels are enforced by the
  parser).  KINDS: type occurrences hover `Name : kind` via
  `Pretty.ppKindSchema`.  Fast mode -> null and died-component -> absent
  are pinned.  PERF (the gate): interleaved A/B on Report.e, implementer
  1.621/1.679/1.706/1.621 pooled -13.5 ms; reviewer 1.615 -> 1.606;
  fix round 1.631 -> 1.610 — every pair inside the 5%/80 ms budget and
  below the noise floor; locals ship ON.  lsp-smoke 207 -> 237;
  seven targeted suites 121 -> 124.  Second review pass on the arity split:
  twelve adversarial shapes, no wrong type; three pre-commit fixes applied by
  the orchestrator (Pretty.scala's CRLF restored — 99 of 154 core sources are
  CRLF, no .gitattributes; rank-N domains skipped via `mono`, a `forall` on a
  local being what Decision (a) forbids; an anti-vacuity floor on the
  equation-argument class).  Code committed 11be9bb.

- [x] **6.3 References, document highlight, rename** — from the renamer
  tables (`occurrences` with ToBinder/ToGlobal, `binders`, `frames`);
  no new analysis.  `textDocument/references` (honouring
  includeDeclaration) and `textDocument/documentHighlight` (Write at
  the def-site, Read at uses): for a local, every occurrence in the
  file resolving to its binder id; for a module top-level or an
  imported global, every occurrence across OPEN documents whose
  `ToGlobal.origin` matches, plus the def-site (Decision c: the
  coverage warning whenever the defining module is not itself an open
  buffer, or is in the stdlib).  `textDocument/prepareRename` +
  `textDocument/rename`: a WorkspaceEdit over exactly the references
  set, under Decision (d)'s refusals; the new name must be a valid
  Ermine identifier of the same case class (a constructor stays
  capitalised, a term stays lower); operators refused.  TESTS: a
  TestRenamer property over the 180 files — every ToBinder occurrence's
  binder has a defSite inside the file, no two occurrence spans
  overlap, def-sites are unique per id: the table integrity references
  and rename stand on.  lsp-smoke: fixture `Refs.e` (with `Sib.e`) —
  references on a local (def + 3 uses); references on a top-level from
  an importing OPEN sibling (both files, both counts); highlight kinds;
  rename a local (an edit at every site, none elsewhere); rename to a
  capturing name -> error; rename to an operator -> error; rename on a
  stale index (didChange, then rename before the debounce) -> "check
  pending" error; rename a top-level across two open buffers -> edits
  in both plus the coverage warning.
  DONE 2026-09-10 (implementer + reviewer Opus; reports
  tracker/loopmodel/LSP3-6.3-REFS.md, LSP3-6.3-REVIEW.md).  Every `Occ`
  now carries a stored KEY: `LocalKey(binderId)` — the set is every
  occurrence in the document with that id plus the binder's def-site,
  which the index now carries for EVERY local binder; `GlobalKey(origin)`
  — `ToGlobal.origin`, never the written-through name, so an alias
  import and its canonical name are one name — the set is every
  occurrence in every OPEN buffer: uses, the defining module's signature
  and equation heads, the declaration head, the fixity mention and the
  `import M using (n)` list entries (newly indexed), plus the def-site
  even when its file is not open.  Highlight is the same key in the
  requesting document (Write at the def-site, Read elsewhere).  RENAME
  refusals, all checked before any edit is built so no partial edit
  exists on any path: invalid identifier or wrong case class (the
  surface Lexer's classification, not a regex); operator either side;
  capture three ways (`scopeAt` at every occurrence, `moduleTerms` and
  TyDef binders, the canonical import maps); stale index for ANY document
  in the edit; an Ambiguous mention; a def-site in a file that is not
  open; a name mentioned under more than one spelling (alias or qualified
  use), which a textual rename cannot follow.  The coverage warning
  (Decision c) is one `window/showMessage` per global request.  A BUG
  FIXED ON THE WAY: occurrence spans ran to the NEXT TOKEN (a `token`
  eats trailing whitespace), so a rename would have swallowed the space
  after every name — `Definitions.nameLen` measures by spelling.
  TestRenamer 18 -> 23: table integrity over 252 of 253 corpus files
  (Sample.e does not parse), 71,248 occurrences, 16,506 binders, 3,441
  moduleTerms: 0 bad ToBinder, 0 overlaps, 0 shared def-sites, 0 bad
  moduleTerms.  ONE SHARED FILE: `NewPipeline.Read` gained a defaulted
  `scope` field, set at its single construction site and read only by
  the editor (the reviewer checked the batch cost).  Index build on
  Report.e +2..7 ms warm (7305 -> 7980 occs); round trip unmoved.
  THE REVIEW FOUND TWO WRONG-EDIT PATHS the implementer's fixtures did
  not reach, both fixed in the fix round: (R1) `ToGlobal.origin` is the
  module the name was IMPORTED FROM, not the defining module, so a
  re-exported name (Prelude re-exporting Bool.not) had a different key
  from its definition — rename from Bool.e succeeded and left the open
  importer broken; keys are now canonicalised across re-export hops at
  index time, with a same-spelling-different-key refusal as the belt.
  (R2) backtick literal identifiers: the spelling is the stripped middle
  and the span starts at the backtick, so the replace range was wrong
  (14 such names in Layout/Report.e) — `Definitions.nameExtent` now
  measures against the SOURCE (exact / backticked / parenthesised / behind
  a tab: 70,897 / 39 / 306 / 6 of 71,248 corpus occurrences, 0
  unclassified); references and highlight are correct for all classes,
  RENAME REFUSES non-exact names (whether the new name needs backticks is
  a grammar question, and the literal carries its own escapes), with
  prepareRename answering null first.  A pre-existing bug the new property
  found: parser columns are TAB-EXPANDED to 8-column stops (`Pos.bump`),
  so every LSP range on a tab-indented line is in the wrong units —
  ticket E8; a name behind a tab is never renamed.  (R3) the stale-index refusal covered only
  documents with a hit; every open document is version-checked now for a
  global rename.  The shared-file risk was REFUTED: the strict path drops
  the `Read`, nothing is retained per module in batch memory.
  lsp-smoke 237 -> 287 -> 306 (fix round); five targeted suites 68/68
  (TestRenamer 18 -> 24).  Index build on Report.e 12-16 ms warm after the
  fix round, 3x under the floor; round trip unchanged.
  GAPS stated in the report's §6 (the reviewer's fuller list): operator
  import-list items are not indexed (references-completeness only —
  operators cannot be renamed); a multi-equation definition's def-site
  is its last equation.
  Second review pass: ADVANCE — the re-export fix re-broken four ways
  (stdlib case both directions, a two-hop chain, a type re-export, a
  multi-ancestor origin that refuses rather than edits) and held; two
  refusal messages mislead (wording only, S4) and the belt over-refuses
  by design (stated).  Ticket E8 filed for the tab-column model.

- [x] **6.4 Document symbols and workspace symbols.**
  `textDocument/documentSymbol` (hierarchical): from the surface tree +
  StatementExtents — one symbol per top-level group (sig + equations
  merged; detail = the TolerantCheck type when known), data/type/class
  (constructors as children), field, table, foreign (block children),
  import; SymbolKind per kind; `range` = the statement extent,
  `selectionRange` = the head name.  Works on a broken file's healthy
  statements.  `workspace/symbol`: case-insensitive substring over the
  resident session's globals that have a real file Loc (termNames,
  cons — the tables navigation already uses) plus every open document's
  own declarations; capped at 200.  lsp-smoke: Decls.e's symbol list
  (names, kinds, ranges, nesting) pinned; workspace query "twice" finds
  Nav.twice at its Location; "Relation" finds the stdlib type in its
  SOURCE file (Decision 5 makes this true); a broken file lists its
  healthy symbols; a builtin (`Just`) is NOT listed (no source).
  DONE 2026-09-10 (implementer + reviewer Opus; reports
  tracker/loopmodel/LSP3-6.4-SYMBOLS.md, LSP3-6.4-REVIEW.md).  The unit is
  the TERM GROUP, not the statement: a spelling's signatures and equations
  in one binding scope merge into one symbol (range = union of their
  statement spans, selectionRange = the first equation's head, or the
  sig's when there is none).  Kinds: argument-taking group Function,
  nullary Variable, class-body group Method; `data` Struct (Enum when
  every constructor is nullary) with Constructor children carrying the env
  type; `type` alias and `foreign data` Class; `class` Interface; `field`
  Field and `table` Object one per name; `import` and the `foreign` block
  Module; `private`/`database`/`foreign private` Namespace; foreign
  function/method/subtype Function, value Property, constructor
  Constructor; a fixity declaration is no symbol (appended to the
  operator's detail); a broken statement is no symbol and its neighbours
  still list.  Ranges go through the existing `Lines`/`nameExtent`
  conversion (E8 inherited, no second column model).  `workspace/symbol`:
  every open document's flattened tree plus the resident session's
  globals with a real file Loc (builtins drop out because `Loc.builtin`
  yields no location), re-exports deduped by definition site, ranked
  exact > prefix > substring > lower-cased name > container, capped at
  200, empty query = open buffers only; the stdlib list is built ONCE
  after boot (36 ms, 2157 globals) and a query costs 0.2-1.3 ms.
  Corpus property (TestRenamer 24 -> 27): 8159 symbols over 252 files,
  0 malformed, and term groups 3441 == moduleTerms 3441 in every file.
  Two brief expectations corrected, not worked around: the `Relation`
  TYPE is a Scala-installed builtin with no source (pinned absent; the
  stdlib query is pinned on SoftRelation/SortOrder instead), and a
  foreign declaration is Function-kinded but not a term group.
  THE REVIEW (FIX-THEN-ADVANCE) caught the report claiming "siblings do
  not overlap" when a group's range was the UNION of its sig and equation
  spans — 171 straddling sibling pairs in 21 corpus files where a sig
  block and its equations are separated by other groups (spec-legal, but
  cursor-to-symbol lookup misrenders on the sig lines).  Fix round: a
  group's range is the contiguous run of its own statements containing
  the selectionRange; sibling non-overlap and sortedness are now ASSERTED
  by the corpus property (straddles 171 -> 0 over 252 files; 1824
  identical-range sibling pairs counted, not failed);
  `private`/`database` containers no longer leak into workspace/symbol;
  a group is emitted in the container of its SELECTION, so a sig at top
  level with its equation inside `private` is a child of the namespace
  with the stray sig outside its range (no empty namespace).  Inherited, ticketed as E9: stdlib hits point at
  the target module tree, not core/src/main/resources — since 6.1's
  navigation, made visible by symbols.  lsp-smoke 306 -> 338 -> 344 (fix
  round); five suites 72/72 (TestRenamer 24 -> 28); Report.e round trip unmoved (symbols built
  on the check path, ~0.3 ms of a 12-18 ms index build).
  Second review pass: ADVANCE; independent census 0 straddling / 0
  unsorted over 358 files and 9066 symbols; the identical-range example
  in the report was stale and is corrected in an orchestrator's note.

- [x] **6.5 Completion** — the consumer the scope-at-position layer has
  waited for since 4.2 ("deferred to where a consumer exists").
  `textDocument/completion` from the last check's tables and the
  CURRENT buffer text (for the word prefix at the cursor and the
  `import ` / qualified-name context), never a check: (1) locals
  visible at the position via `Renamer.Result.scopeAt` (BinderKind ->
  CompletionItemKind; detail = the 6.2 type); (2) the module's own top-
  levels (`moduleTerms`; detail from TolerantCheck.types); (3) imported
  names in the file's scope (the ModuleScope the check built; detail
  from env); sortText ranks locals > own > imported; (4) after `import `
  or `import X.`: module names from the loaded modules and the `.e`
  files under the module root; (5) after `Module.`: that module's
  exports; (6) keywords.  Prefix-filtered SERVER-side (a Prelude-
  importing file has thousands of names — measure the unfiltered
  payload once and record it); trigger character `.`.  Staleness
  accepted: a binder typed since the last debounced check is not
  offered until that check lands (docs/lsp.md says so).  LATENCY:
  completion on Report.e answers in < 50 ms server-side (the log line
  prints it); over that is a bug, not a budget.  lsp-smoke: fixture
  `Complete.e` — an arg offered inside its function and not outside; a
  where-bound offered in the body only; own top-level; an imported name
  with its type; `import La` offers the Layout modules; `Bool.` offers
  Bool's exports; a keyword; a broken file completes from its healthy
  part; a request during boot answers an empty list, not null.
  DONE 2026-09-10 (implementer + reviewer Opus; reports
  tracker/loopmodel/LSP3-6.5-COMPLETION.md, LSP3-6.5-REVIEW.md).  CONTEXT
  is lexical, one line of buffer text: a line whose first word is
  `import`/`export` followed only by a dotted name is MODULE context; an
  identifier preceded by `.` after an upper-initial dotted path is
  QUALIFIED; otherwise NAME; inside a `--` comment, a same-line `{- -}` or a
  string the answer is `[]`; the prefix is an identifier, so operators are
  never completed.  ITEMS in `sortText` tiers: locals from
  `Renamer.Result.scopeAt` (detail = the 6.2 type via prettyTypeIn) <
  own declarations (the 6.4 symbol tree plus renamer-bound top levels) <
  imported terms and types from the check's ModuleScope (types from the
  V, kinds from cons) < keywords; case-insensitive matches below exact
  within a tier; one item per label.  Module names from FOUR sources: the
  resident's loaded modules, the `.e` files under the module root, the
  open buffers, and what THIS file's check loaded (Layout.Scan is in none
  of the first three).  Type variables are never offered — TyParam,
  TyImplicit and KindParam binders are in no frame (12,339 of 18,982 local
  occurrences): the scope layer is a VALUE-scope layer.  EMPTY PREFIX:
  the unfiltered payload on Report.e was measured once — 1,332 items,
  181 KB, 34 ms — and the shipped answer is locals + own only, capped at
  300, `isIncomplete: true` (a conforming client would otherwise cache
  the partial list and never see the imports); prefixed answers are
  `isIncomplete: false`.  TIMING on Report.e line 1504, server-side
  median of 10: 2.5 ms for prefix `f`, 1.8 ms empty, module context 5.3
  ms cold / 0.2 ms cached — bar 50 ms.  TWO BUGS IN THE 4.2 LAYER, never
  tested until it had a consumer: `scopeAt` folded so the OUTERMOST
  binding won (88 corpus disagreements) and a `do` binder's frame covered
  only its own bind statement (33 more) — both fixed in Renamer.scala,
  which the strict path never reads for frames (see the review); the
  scope-agreement property is now 0 of 6,643 value-local occurrences over
  252 files, 55 shadowed occurrences as anti-vacuity (TestRenamer 28 ->
  31).  Staleness stated in docs/lsp.md and pinned deterministically.
  THE REVIEW REFUTED the report's grammar claim: a dotted reference does
  not parse in ANY position (`identTok` is tried before the qualified
  forms, so `.` is always composition) — `Bool.not`, `Bool.True` and
  `: Bool.Bool` all fail; qualified completion now REPLACES the whole
  `Module.prefix` span with the bare name, carries `filterText` =
  `Module.label` so the client's own filter matches the dotted text, and
  adds an `import M using <name>` additionalTextEdit (the form this
  grammar has; `using type` for types) after the last import when M is
  not imported — pinned end to end: edits applied by the client and
  re-sent, the file checks clean; an existing `using` list is never
  extended (6.6's add-import job).  The reviewer
  also ran the REVERSE scope property (every local `scopeAt` reports at an
  occurrence is what the occurrence resolved to): 0 false locals of 39,487 in the
  shipped TestRenamer property (the reviewer's independent run: 0 of
  35,920 under a narrower denominator).  An import LIST is treated as a name context
  (wrong but harmless, stated).  THE SECOND REVIEW PASS found three
  qualified-completion shapes whose applied edit does not check clean,
  none silent: an ALIASED import (`import Bool as B`) exposes names only
  in the affix form — `importLines` now reads `as A` and the item inserts
  `not_B` (applied buffer clean); the alias as a QUALIFIER (`B.n|`) still
  answers nothing (stated); a TYPE and a CONSTRUCTOR of one spelling were
  collapsed into one item carrying the wrong import form (`using` vs
  `using type`) — fixed, both items now offered; `Module.` lists names
  whose ORIGIN is that module, not its exports (`Maybe.` shows no
  `Just`/`Nothing`, which originate in Native.Maybe) — stated as a gap;
  and an existing `using` list is never extended (pinned as the
  diagnostic it leaves, so 6.6 can close it visibly).  Decision (c) amended: the module-name
  workspace has a FOURTH source, what this file's check loaded.  lsp-smoke 344 ->
  386 -> 396 -> 407 (two fix rounds); six suites 104/104 (TestRenamer 28 -> 32,
  TestLower 28); Report.e round trip unmoved.

- [x] **6.6 Quick fixes (textDocument/codeAction).**  (a) ADD IMPORT: on
  an undefined-term note (Note.spelling, carried since 5.4), candidates
  = loaded modules exporting that spelling (termNames origins) ∪ open
  siblings declaring it; one `quickfix` action per candidate, editing
  the existing `import M (...)` list when M is already imported with a
  list, else inserting `import M (name)` after the last import (after
  the header when there are none); `diagnostics` set to the note.
  (b) ADD TYPE SIGNATURE: on an implicit top-level binding whose group
  has no sig (surface tree) and whose TolerantCheck type exists: insert
  `f : <type>` on the line above the first equation, same indentation;
  also a `source`-kind action for the whole file ("add all missing
  signatures").  The rendering must PARSE BACK; Decision (e) says how
  that is verified: a one-off sweep over the 180 files inserting the
  inferred signature for every unsigned top-level and re-running the
  tolerant check on the copy — record insertions, clean re-checks and
  the failing shapes (renderer bugs; G1's kind-meta entropy is the
  known one).  SHIP BAR: ≥ 95% clean; the failing shapes become a
  renderer ticket, listed here.  lsp-smoke: fixture `Fix.e` — an
  undefined `not` offers "import Bool (not)" whose edit, applied by the
  client script and re-sent as didChange, clears the diagnostic; a name
  exported by two modules offers two actions; an unsigned binding
  offers a signature whose applied edit re-checks clean; a signed
  binding offers none.
  DONE 2026-09-10 (implementer + reviewer Opus; reports
  tracker/loopmodel/LSP3-6.6-QUICKFIX.md, LSP3-6.6-REVIEW.md).  ADD IMPORT:
  candidates are the session globals of the undefined spelling collapsed
  through `termNameOrigins` to their ORIGIN module, plus open siblings'
  own terms, at most 8, `isPreferred` only when exactly one; the edit is
  decided lexically from the CURRENT buffer (comments masked): not
  imported -> `import M using name` after the last import (after the
  module line when none); a `using` list lacking the name -> append `;
  name` (inside braces when braced) — which closes the gap 6.5 pinned as
  its diagnostic; a `hiding` list naming it -> delete the item or the
  whole clause; own module, open import and aliased import -> no action
  (an alias puts `name_A` in scope, and a duplicate module import is a
  header refusal, so no edit exists).  This grammar has NO `import M (a,
  b)` form: the plan's wording was wrong and the implementer corrected
  it.  Type names are out of scope (the "undefined type" note carries no
  spelling; carrying one is a `Subst.scala` change) and operators are
  unreachable (an unknown operator is a read Diag, not a Note).  ADD
  SIGNATURE: `<indent><head> : <type>` at the first equation's line,
  head from the surface `SName.form` (fixity proved wrong on
  Function.e's backtick operator), rendered FLAT by the hover printer;
  top level and private/database blocks, not class bodies; a
  `source`-kind "add all missing signatures (N)" with edits sorted
  line-descending; STALENESS REFUSED (index version != buffer version ->
  `[]`): a code action is an edit, not an answer.  THE SWEEP (Decision e,
  `-Dermine.sweep.quickfix=true`, gated out of the shipped suite): 253
  files, 1334 unsigned groups, 1166 insertions offered, CLEAN 1164 =
  99.83%, PARSE-FAIL 0, TYPE-FAIL 2 (Validation.e: a `type Err` alias
  unfolded in the rendering — the signatures are correct and re-check
  silently; honest reading 1166/1166 usable), SKIPPED 168 by named reason (the rendered type
  names a constructor the file cannot write 117 — the review re-derived
  the class: 31 groups (33 name occurrences) are types the file resolves
  through its OWN synonym, a
  false negative of the scope test stated as a gap; 31 name a `private
  data`; most of the rest are imported under an alias; a free kind
  variable 36; a nested `* ->` kind losing its parens 10; `<:_Type.Cast`
  2; a row field Global that does not round-trip 3).  Ship bar 95% -> GREEN, both
  actions, no syntactic filter.  CLEAN's equivalence is alpha-equivalence UP TO
  KINDS, `G1Compare.alphaEq` plus a complete all-bijections variant: rendered-
  text comparison had first reported 81%, 145 of its "failures" being
  kind-binder and row-constraint ORDER.  PRINTER TICKET drafted from the
  skips: nested `* ->` parens, exists-binder kind variables, `ppType`'s
  operator cases ignoring Qualification (`n_Module`) — 48 groups would
  return if fixed; the field round-trip is not the printer's.
  codeAction: 51 ms on the first request after a check, 0.1-0.4 ms after
  (memo keyed on uri+version).  THE REVIEW (FIX-THEN-ADVANCE, record
  fixes plus one line): 35 of 35 live rule-table probes green with every
  edit applied over the wire and re-checked clean; the sweep re-derived
  a second way (live per-group refusal log) to the same 168; the
  own-field exemption tightened from a module-prefix test to the exact
  shape (it also exempted descendant modules' fields); stated
  limitation: origin-collapse never offers a re-exporter already
  imported with a `using` list.  lsp-smoke 407 -> 454; TestQuickFix 18
  new, TestTolerantCheck 26 -> 27; Report.e round trip unmoved.
  Ticket E10 (the printer's four unreadable shapes + the synonym false
  negative) filed.

- [x] **6.7 Editor wiring, docs, demo.**  VS Code: the client library
  serves completion/rename/references/symbols/codeAction on its own —
  add the completion trigger character, check the `ermine` fence on
  hover markdown still renders, rebuild the vsix.  Eglot: verify over
  the scripted transcript (no code).  docs/lsp.md rewritten: the new
  feature list, the current counts, a RE-MEASURED latency table (round
  trip, worst-case request wait during a check, completion time), and
  the staleness/coverage statements from Decisions (c)(d).  Record the
  G3 demo transcript under "Gate evidence (G3)".
  DONE 2026-09-10 (implementer + reviewer Opus; reports
  tracker/loopmodel/LSP3-6.7-WIRING.md, LSP3-6.7-REVIEW.md).  VS Code:
  the client filters nothing — verified by reading and now by
  measurement (the load test asserts all nine providers register, the
  `.` trigger and the `quickfix,source` kinds); THE LOAD TEST HAD BEEN
  RED SINCE 6.6 LANDED and leaked a server JVM each run — its `vscode`
  stub answered 0 for every capitalised static, so registering code-
  action kinds threw inside the client; fixed in the stub (real VS Code
  has the method; the extension and server were never implicated);
  vsix rebuilt as ermine-lang-0.1.1, 0.1.0 removed, no new bloat.  Eglot
  needs no change.  docs/lsp.md REWRITTEN whole (405 -> 540 lines) to
  what shipped, every refusal and gap included, E8/E9 stated where a
  user hits them, no stale count survives; README with a "three things
  that will surprise you" section.  Demo transcript
  tracker/lsp-tests/G3-demo.txt from tracker/tools/lsp-demo.sh — twelve
  steps covering every capability, reproducible byte-for-byte modulo
  timings.  The latency table and the full gate run are in "Gate
  evidence (G3)" below.  Review FIX-THEN-ADVANCE: eleven prose fixes
  (a completion figure labelled server-side was the client round trip;
  refusal counts needed their units; three rules needed a clause), all
  applied while the reviewer's core/test ran; one last sentence
  corrected by the orchestrator.

**GATE G3**: lsp-smoke green with the new fixtures (Locals, Refs, Decls
symbols, Complete, Fix, BadImport); Tier 0 green; Tier 2 = full
`core/test` ALONE on the tree, green — and deterministic after 6.0 (its
three runs recorded); REPL goldens and TestReplDifferential BYTE-
UNCHANGED (batch strictness frozen); TestTolerantRead's 180-file
agreement property green; the 6.2 perf line recorded (interleaved A/B,
within budget, or the item parked with its number); the 6.6 sweep
numbers recorded; boot 129; no `.ei` droppings in tracker/lsp-tests.
STOP the loop and summarize for sign-off before any Stage 4 planning.

## Stage 4 — the read, and the wait (checklist, drafted 2026-09-10 from tracker/loopmodel/STAGE4-PRIOR-ART.md; folded in and OPENED 2026-09-10 on the user's word, which also signed off G3)

GOAL: make the editor round trip shorter where it is actually spent — in the
READ, not in inference — and make the one remaining interactivity cost (a
request that arrives during a check) either shorter or honestly answered, all
without touching batch semantics, without a new thread, and without an identity
scheme.  Stage 3 established the premise: inference is not the bottleneck, every
Stage-3 feature added nothing measurable, and requests already answer in
milliseconds from stored tables.  Stage 4 spends its whole budget on the parse
and on the policy around it, and it spends the FIRST item proving that the
numbers everything else is ranked against are real.

THE PERF PREMISE, with provenance.  Read every figure with its tag.

- MEASURED (`tracker/tools/perf-bench.sh editor`, `Layout/Report.e`, 1757
  lines / 77,385 bytes, PERF-ROADMAP P1 baseline of record, commit 5d17377,
  2026-08-31): round trip **1.616 s** = read **0.770 s** + typecheck **0.515 s**
  + debounce **0.300 s** (policy, not work) + residual **0.017 s**.
- MEASURED (LSP roadmap "Gate evidence (G2)", 2026-08-31, the same file): the
  keystroke-to-diagnostics median went **2.24 s -> 1.57 s** across item 5.5;
  inference **1.03 s -> 0.45 s**; **114 of 154** components reused; the read
  (parse+rename+lower) is **0.80 s** of the 1.57 s, i.e. 64 %.
- MEASURED (item 6.7 / GATE G3, 2026-09-10, the reviewer's run at load
  0.95-1.31, `perf-bench.sh editor -k 15`): round trip **1.69-1.70 s** =
  read **0.86** + typecheck **0.50** + debounce 0.30 + 0.03, 97/154 reused;
  the 1.57 -> 1.7 s change since G2 is MACHINE DRIFT, measured by an
  interleaved pair against the Stage-3 opening commit 78d860f (before
  1.759 / after 1.694); worst-case request wait during a check **1.45 s**
  (idle hover 0.58 ms).  THIS is the split G4 compares against, and the
  before-side of every Stage-4 A/B.
- MEASURED (item 6.2, 2026-09-10, interleaved A/B, `perf-bench.sh editor -k 15`,
  both sides under load 1.3, report `tracker/loopmodel/LSP3-6.2-LOCALS.md` §6):
  pooled BEFORE **1.6635 s** vs AFTER **1.6500 s**, Δ **−13.5 ms**; the fix
  round **1.631 -> 1.610 s**, Δ **−21 ms**.  Both inside the 5 % / 80 ms budget
  and below the harness's noise floor.  The read segment wandered **0.795-0.865 s**
  between runs of an unchanged tree — that spread is the machine, and it is
  larger than most things this stage could win by tuning.
- MEASURED (item 6.5, 2026-09-10, server-side median of 10 on Report.e line
  1504): completion **2.5 ms** for prefix `f`, **1.8 ms** empty, **5.3 ms** cold /
  **0.2 ms** cached for module context; the unfiltered payload once, **1,332
  items / 181 KB / 34 ms**.  Requests are not the problem.
- ARITHMETIC (survey §0.1, from PERF-ROADMAP P2's 1970-sample editor profile;
  the middle column of that table is the survey author's arithmetic on sample
  shares): parse ≈ **0.70 s** — 91.4 % of the read; extent scan ≈ 0.054 s (since
  cut 11.5x by P5(a)); lower ≈ 9 ms; rename ≈ 2 ms; reassoc ≈ 1 ms.  Rename +
  reassoc + lower together are **1.1 % of samples ≈ 12 ms**.
- THE WARNING THAT GOVERNS ALL OF THE ABOVE ARITHMETIC.  PERF-ROADMAP: "READ
  EVERY PERCENTAGE IN THIS SECTION AS AN UPPER BOUND."  P5(a) measured one
  directly and JFR had over-attributed it **3.5x** (profile 4.7 % ≈ 66 ms;
  direct microbenchmark of the identical pass **18.80 ms**, then 1.64 ms after
  the fix; 50 reps after 20 warm-ups).  Item **7.0 is the direct measurement
  that replaces the arithmetic**, and no later item may be judged against a
  profile share.
- MEASURED, WITH A DISCLOSED DEVIATION (survey §4.3): a standalone Java
  microbenchmark — NOT the Ermine build, not sbt, not `bin/ermine` — put the
  full-sync `didChange` frame at 79,538 bytes, its parse with this project's own
  scanner at ~369 µs, an incremental frame at ~2 µs, and the string splice at
  6-16 µs, against a ~1,300,000 µs check.  That is 0.03 % of one check.  The
  survey flags it as indicative and asks for `perf-bench.sh` before anything is
  decided on it; Decision (d) below decides only to do nothing, which needs no
  re-measurement.
- CODE-DERIVED, NOT YET MEASURED (survey §5(b-lite), reading
  `TolerantCheck.keys`): each group's key contains the statement's START LINE, so
  **inserting one line at the top of the file changes every key and reuse falls
  to 0 of 154**, paying the whole ~0.5 s of inference for an edit that changed
  nothing.  Item 7.2 measures the cliff before it fixes it.
- MEASURED (G3, above): a request arriving during a check waits for it,
  **1.45 s** median on Report.e — the figure of record.

## STAGE-4 INVARIANTS (hard)

Carried from Stage 3 unchanged:

- BATCH SEMANTICS ARE FROZEN.  `Session.load`/`loadModule`, `NewPipeline.readModule`,
  `SurfaceParsers.module` and the REPL goldens (`tracker/repl-tests/*.expected`,
  `TestReplDifferential`) stay byte-identical.  Every new entry point lives BESIDE
  a strict one, never as a flag inside it.  `TestTolerantRead`'s 180-file
  agreement property is the standing tripwire.
- NO REQUEST TRIGGERS WORK.  hover/definition/references/rename/symbols/
  completion/codeAction keep answering from the last check's stored tables.
  Staleness is documented, never papered over with an inline check.
- Decision 5 stays: the resident session is interface-free (`useInterface=false`).
- Single-threaded dispatch stays (Decision 3) — see Decision (c) below, which
  makes that a Stage-4 position rather than an inherited default.
- Every sweep covers stdlib AND `core/examples` (the 180-file rule; 253 files
  through `Resident.checkFile` in the 6.2-era sweeps).
- lsp-smoke's check count GROWS with each item (454 as of 6.6); the Baselines
  note is updated in the same commit.
- GATES per `tracker/GATE-POLICY.md`.  Tier 0 before every commit.  **Tier 1 for
  any change inside `scalaparsers` (the parser library — `ParseState`, `Parser`,
  the `Free` interpreter), `Subst.scala` or `Type.scala`'s constraint
  construction**; an item that discovers it needs one STOPS and says so.  Tier 2
  (full `core/test`, ALONE on the tree) at adoption and once at G4.  Perf is
  measured ONLY as an interleaved A/B on an adoption item, never as a single-side
  figure, never under load.  Implementer + reviewer per item, the reviewer's
  numbers are the ones that enter the trackers, no third full run.  ONE JVM at a
  time.  Never commit red.

New, and specific to this stage:

- **NO IDENTITY IN A CACHE KEY, AND NO ID IN A CACHED VALUE THAT ESCAPES.**  The
  5.5 fingerprint cache stays keyed on text and stays alpha-invariant: a cached
  artifact may cross a run boundary only if it is CLOSED (a generalized scheme's
  own `V`s; a parsed statement's spans).  No renamer binder id and no
  Supply-minted `V` may enter a key or leave a cache entry [survey §0.2].
- **A REUSED SURFACE TREE MUST BE BYTE-FOR-BYTE WHAT A FRESH PARSE WOULD GIVE.**
  The oracle is a differential over the 180-file corpus (stdlib + examples) with
  SYNTHETIC EDIT SEQUENCES, asserting the spliced `SModule` equals a fresh
  whole-file parse **and that the diagnostics are equal** — rust-analyzer's
  `fuzz.rs` comments its diagnostics assertion out behind a FIXME [survey §1.6];
  Ermine cannot, because the diagnostics ARE the product.  Multi-edit, not
  single-edit: swift-syntax #3397 is invisible to single-edit tests [survey §1.9].
- **REUSE METADATA SURVIVES REUSE.**  Whatever guard a cached statement carries
  (the high-water mark of 7.1a) is carried FORWARD into the next cache entry, not
  merely checked once [survey §1.9, §1.12(3)].
- **NO NEW THREAD IN THIS STAGE** (Decision (c)).
- **NO NEW BUDGET FOR THE READ WITHOUT 7.0.**  Every item after 7.0 states its
  expected saving as a fraction of 7.0's DIRECTLY MEASURED phase table, and its
  gate compares against that table.

### Stage-4 Decisions (append-only; override with a note here, not silently)

- **(a) Caching SURFACE trees by statement extent needs no identity scheme, and
  is therefore not blocked by the question 5.5 parked.**  `surface/Surface.scala`
  nodes carry only an `SLoc`/`Span` and literal payloads — no node id, no binder
  id, no supply draw — and `SName`'s fixity at parse time is LEXICAL, the fixity
  environment being applied later by Reassoc.  A parsed statement therefore
  depends on nothing but its own text and its layout column: it is a closed
  value, and reusing it is the same soundness argument that already licenses the
  5.5 inference cache to splice a previous run's generalized `Type` [survey §0.2,
  §5(a)].  The identity problem bites only OPEN artifacts (lowered trees), and
  Stage 4 does not cache those.
- **(b) Stable binder / `V` identity is DEFERRED, with the number.**  Rename +
  reassoc + lower are ~12 ms (ARITHMETIC, survey §0.1); 7.0 will say what they
  really are.  Whatever a stable-id scheme is worth, it is not worth it for read
  latency.  It is also expensive to gate: `V.equals`/`hashCode` are purely the
  integer id, and id ORDER is observably load-bearing in batch — `Session.scala`'s
  own note on `-Dermine.loadInSeries` ("parallel makes draw `Supply` ids in
  thread-timing order, which reaches interface bytes through the constraint
  solver's id-hash queue"), and PERF-ROADMAP P10, where the id base alone moved
  GU05 from **743 to 47,317 draws** (MEASURED).  Any id redesign is Tier 1 plus a
  GU05 sweep at ≥ 25 bases on both sides.  If it is ever revisited, the prior art
  says do it Zinc's way — a De-Bruijn-style renumbering during the HASHING
  traversal, leaving runtime ids alone [survey §5(b)] — not an id-space redesign.
- **(c) The worker thread is DEMOTED from "the Stage-4 fork" to a parked entry
  (7.6), and `fastMode` is promoted in its place.**  A worker removes **0 ms** of
  compute from the 1.616 s round trip; its entire value is turning the ~1.3 s
  worst-case request wait into ~0 [survey §3.9, §5(d)].  Four of six surveyed
  servers bought most of that perceived latency with no thread at all (Roslyn's
  frozen-partial two-pass, VS Code's syntax-server routing, Dart's cooperative
  yielding, clangd's stale-AST reads), and Ermine's `fastMode` is already most of
  the frozen-partial design — it skips the check, keeps the read's index and
  carries the cache forward.  The three hazards a thread must answer are unchanged
  and unaddressed (`Session.depCache` is a process-global map mutated by
  `Documents.put`/`drop` mid-check; the `Supply` is shared and its draw order is
  observable; the `Documents` map is read by the sibling loader).  The survey does
  support this demotion; if the user wants the wait gone before the read is fast,
  the unpark trigger is written into 7.6.
- **(d) Incremental `didChange` is DECLINED.**  It attacks a fraction of the
  0.017 s residual; the wire/parse half is 0.03 % of one check (MEASURED with the
  disclosed deviation, survey §4.3); its supposed second benefit — handing the
  server the edit range 7.1 wants — is obtainable free by comparing statement
  texts, which `TolerantCheck.keys` already does and which Lean deliberately
  prefers over LSP edit ranges [survey §1.7, §5(e)].  Against that sits a real
  client bug class with no protocol-level detector (LSP #1706 asked for a checksum
  and was refused), and the nearest institutional precedent — Metals, same JVM,
  same lsp4j — closed the request wontfix in 2019 and is still Full in 2026
  [survey §4.2, §4.4].  Keep `change: 1`.  ONE CORRECTNESS NOTE recorded here so
  it is not lost: `Diagnostics.scala` reads `contentChanges.lastOption.text`,
  which is right for Full and silently wrong for Incremental; that line changes
  first if the capability is ever flipped.  The same measurement found `Rpc.scala`'s
  char-at-a-time string scanner costs the 369 µs and a run-based scanner measured
  ~61 µs — a ~5x win on a step that is 0.02 % of the round trip; 7.0 measures it
  in-process and it ships only if it is free (see 7.0(h)).
- **(e) The debounce becomes ADAPTIVE, but only AFTER the read is faster.**
  PERF-ROADMAP P6 already orders it last among the [E] items and says why:
  "shortening it while a check costs 1.27 s just queues more work".  It is 19 % of
  the round trip now and would be ~30 % of what remains after 7.1, which is
  exactly when it becomes worth deriving from the measured check time, clangd's
  way (`DebouncePolicy{Min=50 ms, Max=500 ms, RebuildRatio=1}`) [survey §5(f)].
  7.4 is therefore gated on 7.1 or 7.3 having landed a measured saving.
- **(f) The 6.2b pattern-binder hook keeps its place unchanged: its own Tier-1
  item, only if lambda/`case`/`do` hover is wanted, and that is the user's call.**
  Nothing in Stage 4 depends on it; it is not scheduled here.  The review's
  finding stands — the workable shape is FOUR sites on the checker's hot path
  (`instantiateType`, `unbind`, `generalize`, and the `Remember`-style eager
  substitution), behind a flag OFF in batch — and the recording-hook shape as
  first written is REFUTED (`restrictTypes` removes the recorded meta).  It stays
  in Blocked/Awaiting, listed in 7.6 with its trigger.
- **(g) 7.1 and 7.3 are ALTERNATIVES ranked by 7.0, not a sequence.**  If a
  245-byte statement parses in 0.05 ms rather than ~2.2 ms, the read stops being
  the target and the statement cache is unnecessary [survey §5(a′)].  7.0 decides
  which of them the stage builds; the loop does not start both.

### Checklist (each item ≈ one implementer + reviewer iteration; the acceptance criteria are the tick conditions)

- [x] **7.0 DIRECT MEASUREMENT of the read's phases.**  THE ITEM EVERY LATER ITEM
  IS JUDGED AGAINST, and the one that retires the arithmetic in the premise
  above.  Instrumented timers (System.nanoTime around each phase, behind a system
  property, printed to stderr — NOT a profiler, NOT sample shares), on
  `Layout/Report.e` through `Resident.checkFile`, P5(a)'s protocol: **50 reps
  after 20 warm-up reps, medians, machine load < 1.3**.  Phases, each reported
  separately: (a) header parse; (b) `StatementExtents.scan`; (c)
  `SurfaceParsers.module` — the whole-file parse; (d) layout/vsemi work inside it
  if it can be separated without changing behaviour, else stated as
  unseparable; (e) `Renamer`; (f) `Reassoc`; (g) `Lower`; (h)
  `Definitions.index`, the env copy and the self-scrub; plus `Rpc` frame read +
  JSON parse of one full-sync `didChange` (Decision (d)).  ALSO, and this is what
  ranks 7.1 against 7.3: **one extracted 245-byte top-level statement parsed
  through `SurfaceParsers.statement` with `statementFailure`'s repositioned
  `ParseState`, same 50/20 protocol** — that single number is 7.1's per-miss cost
  AND it says how much of the whole-file parse is per-statement work versus
  per-character trampoline overhead.  Report the ratio (315 × per-statement
  time) / (whole-file parse time) explicitly.  ACCEPTANCE: a table in the item's
  report with every phase MEASURED, its rep count and its spread; each row
  compared against the survey's ARITHMETIC row with the over/under-attribution
  factor named (P5(a) found 3.5x once — find out whether the parse share is
  honest); a one-line verdict "7.1 / 7.3 / neither" with the arithmetic that
  supports it; the instrumentation ships behind a property or comes out, and the
  item says which.  No behaviour change, no default flip: Tier 0.  If (h)'s Rpc
  number reproduces the survey's 369 µs in-process, the run-based scanner is a
  ten-line optional addendum measured the same way, adopted only if it is free
  and byte-identical on the framing tests; otherwise it is dropped and said so.
  DONE 2026-09-10 (implementer + reviewer Opus; reports
  tracker/loopmodel/LSP4-7.0-READ.md, LSP4-7.0-REVIEW.md).  THE ARITHMETIC
  IS RETIRED AND WAS HONEST: property-gated timers (`session/Phases.scala`,
  `-Dermine.lsp.phases=true`, off by default, one boolean per site, output to
  the LSP log) around every phase of `Resident.checkFile`, 50 reps after 20
  warm-ups on Layout/Report.e at load < 1.3, reconciling to the check total
  within 0.03%.  Medians: PARSE 844 ms of a READ of 860 ms (98.1%, the
  survey's arithmetic said 91.4% — UNDER-attributed 1.07x); checkWith 496;
  header 8.2 (parsed TWICE — once by Resident, once inside
  SurfaceParsers.module); index 10.1; lower 9.3; rename 5.0; keys 3.2;
  scrub 2.0; extents 2.3; the wire and JSON of a 79,628-byte didChange 0.37
  — check total 1388 ms, round trip 1.70 s.  Layout/vsemi work inside the
  parse is UNSEPARABLE at Tier 0 (it lives in scalaparsers).  A 44-line
  file checks in 31 ms, so the debounce is 90% of its round trip.
  THE RATIO (Decision g): Report.e has 591 top-level extents at mean 111
  bytes (the survey's "315 at 245 B" counted distinct head words); each
  parsed alone through statementFailure's repositioned ParseState — median
  0.60 ms, mean 1.17, p90 2.2, max 99 ms (the 10.7 KB `private` block);
  Σ slice parses vs the whole-file parse in the same JVM: RATIO 0.953
  (the reviewer's five measurement orders: 0.951-0.954; the implementer's
  first 0.963 omitted the header's share), splitter residual 43 ms (5.5%).
  The review caught a VACUOUS check: 62 of the 591 extents are `import`/
  `export` header lines, and "parses alone" was always true because the
  statement grammar falls back to a total raw-statement rule — the reuse
  unit for 7.1b is 529 statements + 62 header extents, and the slice-vs-
  whole divergence is now MEASURED with a non-vacuous oracle (the slice's
  tree against the whole-file tree for the same extent): 514 of 529 agree
  structurally, 15 (2.8%) differ ONLY in the statement's own top-level
  Span END — the whole-file parse runs on to the next statement's start,
  the slice stops at the extent — no kind or deep-tree divergence.  That
  is `atLayoutBoundary` consuming trailing trivia made visible: the first
  direct evidence that 7.1a's high-water mark is not speculative, and a
  constraint on 7.1b (its splice must re-derive the end span from the
  next extent's start, or its differential fails on 15 of 529 today).  Parse cost is 10.9
  µs/byte and SUBLINEAR in bytes (ms ∝ bytes^0.84); private/database
  blocks are 18.9% of the file's bytes, so one edit in seven lands in
  the 104 ms block.  The header is parsed TWICE, by two different
  grammars (8 + 6 ms).
  ATTRIBUTION vs the survey: extents 23x over raw / 2x over the P5(a)-
  corrected figure; lower exact; rename 2.5x under; reassoc 1.4x over;
  rename+reassoc+lower = 15 ms, Decision (b) unaffected.  THE 7.2 CLIFF
  MEASURED: a body edit keeps 97/154 (typecheck 0.53-0.64 s); one blank
  line at the top -> 0/154, typecheck 1.07 s, round trip 2.29 s vs 1.79:
  +0.52 s.  Rpc addendum DROPPED: in-process 306 µs reproduces the survey;
  a run-based scanner is 1.24x (69 µs), not 5x, and a first draft was
  silently not byte-identical (StringBuilder.append is (offset, length)).
  VERDICT: **7.1** — per-statement parse work is 0.963 x 0.981 x 0.619 =
  ~58% of the check, ~47% of the round trip; a one-character edit leaves
  all other extents identical, so the expected miss is 62 / 83 / 173 ms
  (byte-weighted mean / p90 / p99 with header and residual) and the
  saving 0.78 / 0.76 / 0.67 s — round trip 0.89 / 0.91 / 1.00 s, 3.4-4.1x
  the 200 ms gate (the implementer's first 0.82 s double-counted the
  header and used the median miss).  THE STRONGEST CASE AGAINST 7.1, from
  the review: 7.3 SUBSUMES it — a 10x parser win lands the round trip
  where 7.1b's floor does, with no cache and no soundness obligation, and
  takes the 12.7 s boot too; it loses on RISK (Tier 1 in scalaparsers, the
  reverted P5(d) precedent, 48-52x borrowed from another system), not
  arithmetic.  Two roadmap notes carried from it: 7.1b and 7.3 must not
  BOTH be budgeted as editor savings; 7.3's batch re-ranking is stronger
  than stated.  7.2 lands first (agreed).  lsp-smoke 454 -> 456.
  NOTES CARRIED INTO 7.1 FROM THIS ITEM'S REVIEW: (i) 7.1b's reuse unit
  is 529 statements + 62 header extents (import/export lines are
  raw-statement fallbacks); (ii) 7.1b's splice must re-derive each
  statement's top-level end span from the next extent's start, or the
  differential fails on the 15 divergent statements today; (iii) 7.1b and
  7.3 must NOT both be budgeted as editor savings — 7.3 subsumes 7.1b at
  10x and is re-ranked to the batch target, where the 12.8 s boot is 7.5x
  the round trip and no cache can help; (iv) the header is parsed twice by
  two grammars (8 + 6 ms), worth 10-13% of the read AFTER 7.1b.

- [ ] **7.1 Surface-tree cache keyed by statement extent** (conditional on 7.0's
  verdict; Decision (a) and (g)).  TWO ITERATIONS, because the first is a
  Tier-1 parser-library change and must be reviewed on its own.

  **7.1a — the high-water mark (Tier 1).**  `statement` is
  `statementAlts(bindingStatement) << atLayoutBoundary`, and `atLayoutBoundary`
  runs `StatementExtents.skipTrivia` over the text AFTER the extent, so
  byte-equality of a statement's own text is NOT sufficient for reuse — this is
  Lean's `private def` counterexample in miniature and Lezer's 0.15.0 bug exactly
  [survey §1.7, §1.3].  Five independent systems converged on the same fix and it
  is one integer: the furthest input offset the parse examined [survey §1.10].
  In a combinator parser that is a `var furthest` in `ParseState` and one `max` in
  the position-advancing primitive — which is precisely the thing Lean's note says
  "does not exist currently".  Store `examinedLength = furthest − start` per
  statement.  ACCEPTANCE: the mark is recorded and observable; the batch path is
  byte-identical (Tier 1: `looptrace-corpus.sh` + `trace-ab.py`, `ei-diff.sh
  --batch` with `-Dermine.loadInSeries=true` on both sides, `g1-validate.sh`),
  because this touches the parser library; an interleaved A/B on BOTH targets
  (batch load and editor round trip) showing the counter is free; a test that
  the mark exceeds the extent for at least one real corpus statement (an
  anti-vacuity floor — a mark that never exceeds the extent has not been shown to
  work).  USELESS ON ITS OWN: it ships only as 7.1b's precondition, or not at all.

  **7.1b — the cache (Tier 0 + Tier 2 at adoption).**  A new editor-path-only
  entry beside `NewPipeline.readModuleTolerant`; `SurfaceParsers.module` and
  `readModule` are not touched.  THE KEY: `(headWord, ordinal among extents with
  that headWord)` — rust-analyzer's `ErasedFileAstId` with its warning attached,
  the disambiguator scoped PER head word, never global — which is exactly the
  grouping `TolerantCheck.keys` already computes [survey §2.1, §5(a)].  WHAT
  INVALIDATES: an entry is reused iff (1) its extent text is byte-identical AND
  (2) no edit intersects `[start, start + examinedLength)`.  Statement merging and
  splitting need no special case: `StatementExtents.scan` recomputes every
  boundary lexically FROM THE NEW TEXT on every check and its starts are pinned
  against the parser's own splitter over 180 files, so a deleted space that fuses
  two statements shows up as a changed extent list, not as a silently reused
  stale tree — Ermine's position here is better than Lean's, which compares
  against the old command list and settles for "go up two commands" [survey §1.7].
  THE SPLICE: every top-level statement starts at column 1 and `Span` is
  `(startLine, startCol, endLine, endCol)`, so re-anchoring a reused statement is
  PURELY ADDITIVE on the two line fields — no column arithmetic, where Lezer needs
  a `cutAt` walk and a 25-character margin [survey §5(a)].  Misses are parsed from
  their own slice with `statementFailure`'s repositioned `ParseState`
  (`layoutStack = List(IndentedLayout(startCol, "statement"), IndentedLayout(1,
  "top level"))`, `bol = false`), then `SModule(fileName, header, statements)` is
  reassembled and handed to the UNCHANGED rename -> reassoc -> lower -> check
  pipeline.  KNOWN DIVERGENCE TO CLOSE: `statementFailure`'s own docstring records
  that a slice re-parse may SUCCEED where the splitter rejected (context the slice
  lacks); the differential is what decides whether that is a bug or a
  cache-miss-only path.  THE DIFFERENTIAL (the invariant above): over the 180-file
  corpus, for a generated SEQUENCE of edits per file (insert/delete a character,
  a line, a whole statement; edit at the top, the middle and the end; an edit
  that merges two statements and one that splits one), assert the spliced
  `SModule` equals a fresh whole-file parse AND the diagnostics are equal.
  EXPECTED SAVING: **0.55-0.68 s, 34-42 % of the round trip** — ARITHMETIC
  (survey §5(a)) built on the ~0.70 s parse and ~315 statements, i.e. exactly the
  figure 7.0 replaces; the item restates it against 7.0's table before it starts,
  and if 7.0's parse number is materially smaller the item does not start at all.
  BUDGET/GATE: interleaved A/B (before/after/before/after, load < 1.3) on
  Report.e; the read segment must move by at least **200 ms** pooled — anything
  smaller is inside the 0.795-0.865 s machine drift and does not justify a second
  module driver; under that, the item is REVERTED and the number recorded, the
  P5(d) precedent.  RETENTION, stated because a JVM makes it real: reference-based
  reuse makes the cache a GC root for the trees it holds; it is per open document
  and replaced wholesale per check, so it is bounded, and the item says so with a
  measured heap figure [survey §1.9].  Tier 2 at adoption (it changes shipped
  editor behaviour), plus the seven targeted suites.

- [ ] **7.2 (b-lite) Anchored positions, so the 5.5 inference cache survives an
  edit that shifts lines.**  Independent of 7.0's verdict; small; it removes a
  cliff that costs the full inference segment.  TODAY: `TolerantCheck.keys` puts
  each statement's START LINE into its group's text (`x.startLine + ":" +
  off.text(x)`), so inserting one line at the top drops reuse to **0 of 154**
  (CODE-DERIVED; the item MEASURES it first, as its before-number).  THE FIX,
  which needs no identity scheme: store positions RELATIVE to the group's start
  line, drop the start line from the key, add Δ at lookup.  `Entry.locals` is
  `Map[(Int, Int), LocalTy]` keyed by def-site, so it is one map transformation at
  read time; the `Type`s' `Loc`s only matter for notes and note-bearing components
  are never cached (the class comment says so).  This is rust-analyzer's anchored
  `Span` with its stated rationale — "storing absolute ranges will require
  recomputation on every change in a file at all times" — and Roslyn's green-node
  rule [survey §2.1, §5(b-lite)].  IT IS ALSO THE SPAN ARITHMETIC 7.1b NEEDS, so
  the two share one helper and 7.2 should land first whichever way 7.0 votes.
  ACCEPTANCE: the before/after reuse count for a one-line insertion at the top of
  Report.e (0/154 -> the number, MEASURED both sides); Decision (b) of Stage 3 —
  the drift invariant — restated and re-attacked, because it was the argument
  that put the start line in the key (the reviewer's five attacks on it are in the
  6.2 report and must be re-run against the anchored form); cache INVISIBILITY
  holds — warm == cold, byte-identical, over the 5.5 edit set extended with
  line-shifting edits; every `Loc` that ESCAPES to the client is re-anchored (the
  item enumerates them: hover, definition, references, highlight, rename edits,
  symbols, code actions) and lsp-smoke gains a fixture per escape route asserting
  a position AFTER a line-shifting `didChange`; 6.2's `locals` keys specifically
  pinned.  Tier 0 + the seven targeted suites; Tier 2 at adoption.

- [ ] **7.3 The parse constant factor — P5(c) reopened AS AN INVESTIGATION, with
  a kill criterion.**  P5(c) named the target and stopped: the `Free` trampoline
  is 52.6 % of editor samples and `Parser.run` alone 23.2 % (ARITHMETIC, P2's
  profile), and P5(d) TRIED a localized fix and reverted it at 43 ms, below the
  ~50 ms floor, with the finding that matters: most parsing is SEQUENCING inside
  grammar rules rather than repetition, so `many`/`some` are a small share of
  total binds and **no localized combinator fix can reach that cost — P5(c) is
  architectural or nothing** (MEASURED, interleaved B,A,B,A, 1.611 -> 1.568 s
  pooled; read 0.800 -> 0.788 s).  THE NEW EVIDENCE the survey brings [§1.11] is
  a system with the SAME profile signature — allocation inside combinator
  plumbing — where inlining the combinators gave **3.65x**, removing the combinator
  layer **48.2x** and a C++->C port **52.8x** (`tree-sitter-haskell`, third-party
  report, not measured here).  SCOPE: an INVESTIGATION producing evidence, not a
  rewrite.  Deliverable: (i) 7.0's per-statement number decomposed — how much of
  it is grammar work versus `Free` interpretation, measured by a targeted
  microbenchmark of one hot grammar rule with and without the trampoline on a
  SCRATCH copy in an isolated worktree; (ii) a written estimate of what a
  de-trampolined `Parser` would cost to build and to gate (it is the parser
  library: Tier 1, the 180-file differential, byte-exact REPL goldens, and it is
  the same object `bin/ermine`'s batch load runs through); (iii) a recommendation.
  KILL CRITERION, written before the work starts: if the prototype's measured
  improvement on ONE hot rule projects to less than **300 ms** of the Report.e
  read, or if it cannot be shown byte-identical on the 180-file differential, the
  item is CLOSED with the number and P5(c) is marked "measured, not worth it" —
  no third attempt without new evidence, the P5(d) rule.  NO PRODUCTION CODE in
  this item; nothing merged; the worktree is deleted.  Tier 0 on the main tree
  (which is untouched).

- [ ] **7.4 Adaptive debounce, derived from the measured check time** (Decision
  (e); gated on 7.1b or 7.3 having landed a measured saving — if neither did, this
  item is skipped and the reason recorded).  Replace the fixed 300 ms with
  clangd's shape: `debounce = clamp(Min, RebuildRatio × measured_check_time, Max)`
  over a rolling median of the last N checks, `Resident` already logging the
  number on every check.  Starting constants to be argued in the item from 7.0's
  and 7.1b's tables, not copied: clangd ships `{50 ms, 500 ms, ratio 1}` [survey
  §5(f)].  ACCEPTANCE: the round-trip median on Report.e AND on a small file
  (both MEASURED, interleaved A/B), because the whole point is that a small file
  stops waiting 300 ms for nothing; a pinned test that a burst of N keystrokes
  produces exactly one check; no oscillation — the policy is stated as a function
  and the item shows its output at the measured check times of the fast and slow
  file; the number, the rule and the reason are written into docs/lsp.md.
  Tier 0; Tier 2 at adoption (it changes shipped behaviour).

- [ ] **7.5 Ticket triage — which of E5-E10 this stage takes.**  One iteration,
  and it takes only the ones that are editor-path Tier 0.  DISPOSITIONS:
  - **E8 (parser columns tab-expanded to 8-column stops)** — **TAKE**.  Every
    editor range on a tab-indented line is 7 columns right of the text per tab
    (6 of 71,248 corpus occurrences, `core/examples/GridExample.e`).  User-facing
    and small: the boundary conversion in one helper every range goes through,
    editor path only, Tier 0.  NOT the `Pos` fix, which is Tier 2 + goldens.
  - **E9 (stdlib navigation lands in the BUILD OUTPUT)** — **TAKE**.  A user who
    edits the file `workspace/symbol` lands in loses the edit at the next
    `copyResources`.  Rewrite the target tree back to
    `core/src/main/resources/modules` at the LSP boundary
    (`Definitions.location`), editor path only, Tier 0 — and the pins must become
    tree-distinguishing, since every current pin is `uri.endswith("/Bool.e")`-shaped
    and cannot see the bug.
  - **E7 (import-failure suppression covers term names only)** — **TAKE IF CHEAP,
    otherwise state and defer**.  Operators cost three read diagnostics per use
    and type names one note, all cascading from one failed import.  Editor path,
    Tier 0, but the ticket says the hard part is POLICY not plumbing (the same
    three diagnostics are right for a genuinely mistyped operator), so the item
    ships a flag-based tag or writes down why it cannot be stated.
  - **E5 (`loadModulesInSeries` vs `loadModules` on already-loaded modules)** —
    **NOT THIS STAGE**: a one-line loader change, but shipped loader behaviour, so
    Tier 2 + Tier 1's `ei-diff.sh` sweep in series + `g1-validate.sh`.  It rides
    along with the next Tier-2 commit that is due anyway; the item notes which.
  - **E6 (lambda blame at the application)** — **NOT THIS STAGE**: a checking-mode
    rule for `Lam` moves the position and sometimes the wording of every such
    refusal — REPL goldens, two `TestStage1Pins` anchor pins and the corpus verdict
    TEXT all re-cut.  Tier 2 + goldens, its own item, and frozen batch semantics
    forbid it here.
  - **E10 (`Pretty` writes four type shapes the grammar cannot read back)** —
    **SPLIT**: (5), the quick fix's blindness to the file's own type synonyms
    (33 refusals), is editor path and Tier 0 — TAKE if 7.5 has room.  (1)-(3), the
    printer proper (48 groups), change published `.ei` bytes because the same
    printer writes interfaces: Tier 1 with the interface sweep and a re-cut
    `g1-baseline`.  NOT THIS STAGE.
  ACCEPTANCE: each taken ticket closed with its own lsp-smoke fixture (count
  grows); each deferred one has its disposition and tier written back into
  `tracker/TICKET-stdlib-findings.md` in the same commit, so the ticket file and
  the roadmap agree.

- [ ] **7.6 PARKED, with triggers** (no work in this stage; listed so the forks
  do not go missing).
  - **The 6.2b pattern-binder `Subst` hook** (Decision (f)).  TRIGGER: the user
    says lambda/`case`/`do` hover is wanted.  Then it is its own Tier-1 item in
    the workable four-site shape, behind a flag OFF in batch, with a perf line for
    the flag check on the BATCH target, sized as a day with review.  Until then
    the 62.4 % equation-argument coverage stands.
  - **Checks on a worker thread** (Decision (c)).  TRIGGER: 6.7's measured
    worst-case request wait is still over ~500 ms AFTER 7.1b or 7.3 has landed —
    i.e. the cheap moves failed to make the wait tolerable.  The cheaper thing to
    try FIRST, and the thing to try before any thread: promote `fastMode` to the
    first pass of every check with the accurate pass enqueued behind it, which
    publishes navigation and syntax diagnostics without new concurrency [survey
    §5(d)].  If a thread is nonetheless built, it must answer `depCache`, the
    `Supply` (give the worker `Supply.split`, never share the block allocator) and
    the `Documents` map, per the parked fork and survey §3.9.
  - **A proper incremental parser** — parked permanently unless the front end is
    replaced for other reasons.  See "What this stage does NOT do".

**GATE G4** (written before any code, per the roadmap's format):

- GREEN: Tier 0 on every commit (`core/compile core/copyResources`, `TestLoopTrace`
  720/720, `corpus-run.sh --batch` verdicts unchanged at 85/69/0 over 154,
  `repl-smoke.sh` 8 groups, `lsp-smoke.sh` at its new grown count); the seven
  targeted suites on any item touching TolerantCheck/Lower/Renamer/Definitions;
  **Tier 1 for 7.1a and for anything else that reaches into `scalaparsers`**
  (`looptrace-corpus.sh` + `trace-ab.py`, `ei-diff.sh --batch` in series on both
  sides classified with `ei-classify.py`, `g1-validate.sh`); **Tier 2 = full
  `core/test` ALONE on the tree**, green, once at the gate and at each adoption
  commit; REPL goldens and `TestReplDifferential` BYTE-UNCHANGED;
  `TestTolerantRead`'s 180-file agreement property green; boot 129 modules; no
  `.ei` droppings in `tracker/lsp-tests`.
- NUMBERS RECORDED: (1) **7.0's directly measured phase table**, before and after
  the stage, with the over/under-attribution factor against the survey's
  arithmetic named for each row; (2) an **interleaved A/B** (before/after/before/
  after, both sides under load 1.3) for EVERY adoption item — 7.1b, 7.2, 7.4 —
  with the pooled Δ and an explicit statement of whether it clears the ~50 ms
  editor noise floor and the 0.795-0.865 s read drift; (3) the **corpus
  differential** for 7.1b: 180 files × the synthetic multi-edit sequence, spliced
  parse == fresh parse AND diagnostics equal, with the edit-sequence generator
  and its seed recorded; (4) the reuse counts for 7.2 (0/154 -> N on a top-of-file
  line insertion); (5) the worst-case request wait, re-measured, next to 6.7's
  figure; (6) a heap figure for 7.1b's retention; (7) every REVERTED item with the
  number that killed it (the P5(d) precedent — a measured negative is a result).
- G3 was signed off 2026-09-10 and 6.7's latency table is in "Gate evidence
  (G3)"; 7.1b and 7.4 are judged against it.
- **STOP the loop and summarize for sign-off before any Stage 5 planning.**

### What this stage does NOT do

- It does not build an incremental parser.  matklad, who implemented block
  re-parse in rust-analyzer: "In practice, incremental reparsing doesn't actually
  matter much for IDE use-cases" — and it is still not enabled.  Lezer sets a
  ~1 KB floor below which it does not reuse; Ermine's mean top-level statement is
  ~245 bytes, four times BELOW that floor.  Wagner & Graham's canonical paper has
  no measured speedup and its author puts layout-sensitive languages outside the
  model; tree-sitter's answer for Haskell layout is 3,471 lines of hand-written C
  [survey §1.1-1.3, §1.6, §5(c)].  Sub-statement granularity also has nothing to
  invalidate: 5.6 established that a `where`-block is never a binding component of
  its own.
- It does not switch `textDocumentSync` to Incremental (Decision (d)).
- It does not add a thread, and it does not change Decision 3 (Decision (c)).
- It does not build a stable binder / `V` identity scheme (Decision (b)), and it
  does not cache LOWERED trees — only surface trees, which carry no identity.
- It does not touch `Subst.scala` or `Type.scala`.  6.2b stays parked (Decision (f)).
- It does not change batch semantics, the strict reader, the REPL goldens or the
  `.ei` printer.  E6 and E10(1)-(3) are named and deferred for exactly that reason.
- It does not add hover on arbitrary sub-expressions.  Inference does not annotate
  the tree; that is a typed-tree design and it belongs with whatever follows 6.2b.
- It does not shorten the debounce before the check is shorter (Decision (e)).
- It does not re-rank anything on a profiler share.  After 7.0, shares are for
  deciding where to look, never for deciding what was won.

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

**FORK 6.2 — pattern-binder types beyond equation arguments need a hook in
`Subst.scala` (2026-09-10; the user's decision).**  Item 6.2 delivered hover on
`let`/`where` binders, signed pattern binders, EQUATION-ARGUMENT binders (the
reviewer's option 4: the head's inferred type split by arity, no checker change
— see the item's DONE paragraph for the coverage number) and kinds on type
names, within its perf budget.  The residual unreachable class is lambda
arguments, `case` binders, `do` binders and variables nested inside
constructor/tuple patterns: `Lower.pattern` replaces the binder V's meta with
`Annot.annotAny`, and `Subst.inferPatternType` mints a fresh meta through
`unbindAnnot` that nothing this side holds (report
tracker/loopmodel/LSP3-6.2-LOCALS.md §1).  The Stage-3 invariant says a
`Subst.scala` change stops the item for the user, so it stopped.  THE OPTIONS
(report §8, corrected by the review): (1) a recording hook in `inferPatternType`
— REFUTED AS FIRST WRITTEN: the recorded meta is removed from `hm.types` by
`restrictTypes` (Subst.scala:153, reached from the `Lam` case :942 and
`inferAltTypesPrime` :1036), so a post-component zonk returns the unconstrained
variable the item failed on; the WORKABLE shape is the one `Remember` uses —
eager substitution at `instantiateType` (:187) plus `unbind` (:586) and
`generalize` (:1624), four sites on the checker's hot path behind a flag that is
OFF in batch.  Tier 1 (differential + interface sweep + g1-validate) plus a
perf line for the flag check on the batch target.  (2) an editor-only annot
rewrite — REJECTED, it empties `Patterned.xs` and the editor would accept
programs batch rejects.  (3) `Remember` wrappers on local occurrences — a second
engine in spirit.  RECOMMENDATION: (1) in its workable shape, as its own Tier-1
item "6.2b", sized as a day with review, only if lambda/case/do hover is
wanted; the equation-argument coverage from option 4 may be enough.  A
prototype brief exists (tracker/loopmodel/briefs/brief-LSP3-6.2b-prototype.md,
isolated worktree, evidence only) but was NOT run overnight: after the review's
finding it is a four-site checker change, and that is the user's call before
any JVM time goes into it.  Stage 3 continued past it: 6.3-6.7 do not depend
on it.

**PARKED design fork (2026-09-09; does NOT block Stage 3): checks on a
worker thread.**  Decision 3 keeps dispatch single-threaded, so a hover
or completion that arrives during a check waits for it (~1.3 s worst
case on Report.e; G3 records the measured figure).  A worker design must
answer, before Stage 4 considers it: the SessionEnv copy is made on the
dispatch thread and then owned by exactly one thread; `Session.depCache`
is process-global and mutated by Documents.put/drop mid-check; the
Supply is shared; the Documents map is read by the sibling loader while
the check runs.  Not undertaken in Stage 3.

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

- 2026-09-09 (STAGE 3 PLANNED — no code).  G2 signed off by the user
  today.  Read first: the status line, Stage 2 + GATE G2, the post-G1
  debt list (all eight done), the 2026-09-08/09 LSP-FFI entries
  (committed; a detour, not Stage 3), TICKET-perf-type-inference.md and
  GATE-POLICY.md.  Re-measured lsp-smoke at planning: 185 PASS, no .ei
  droppings.  Three findings shaped the plan: (1) the hover-on-locals
  gate was a LATENCY premise that 5.4 dissolved — TolerantCheck infers
  every SCC in its own SubstEnv and Lower types every binder with a
  fresh meta, so local types are one substType per binder inside a
  block that already runs (6.2, with a measured budget); (2) the perf
  loop has moved neither target, so no REQUEST path may add work —
  everything answers from the last check's tables; (3) core/test is
  intermittent (F4 review R-1), and G3 is a Tier-2 gate, so making the
  suite deterministic is 6.0 — re-scoped the same day, after the user
  asked whether the flake is fixable: a code read could not confirm
  R-1's depCache-without-lock mechanism (nothing on that path can drop
  the seeded Test entry from loadedModules), so 6.0 is now pin-first
  with a probe, fix against what fires, and a fall back to running the
  module-loading suites serially if nothing does.  Checklist 6.0-6.7 + GATE G3 written
  under "Stage 3"; Stage-3 Decisions (a)-(g); the worker-thread check
  parked under Blocked/Awaiting.  STOPPED for the user's review of the
  plan before implementing anything.

- 2026-09-10 (7.0 DONE): see the item's DONE paragraph.  The arithmetic
  was honest (parse 98% of the read; the survey said 91%); the verdict is
  7.1 with 7.2 first; the reviewer corrected the ratio (0.953), the
  residual band and the saving (0.76 s, not 0.82), and caught a vacuous
  "parses alone" check whose replacement found the slice-vs-whole end-span
  divergence 7.1a exists to guard.  Implementer ~57 + 16 min, reviewer
  ~34 min.  Baselines: TestLoopTrace 720/720, corpus 85/69/0 over 154,
  repl-smoke 8/66 goldens untouched, lsp-smoke 456, boot 129.
- 2026-09-10 (G3 SIGNED OFF; STAGE 4 OPENED): the user read the Stage 4
  draft and said "fold the stage 4 draft in and open it".  The draft is
  now the Stage 4 section (the standalone file is removed; git history
  keeps it); its premise bullets updated with G3's measured split (1.69 s
  = 0.86 read + 0.50 check + 0.30 debounce; wait 1.45 s), which is the
  before-side of every Stage-4 A/B.  7.0 brief next.
- 2026-09-10 (6.7 DONE — STAGE 3 COMPLETE, STOPPED AT G3): see the
  item's DONE paragraph and "Gate evidence (G3)".  The reviewer's
  interleaved pair against the Stage-3 opening commit settled the round
  trip question: 1.57 -> 1.7 s since G2 is machine drift on code that
  predates the stage; Stage 3's own contribution is -65 ms.  Implementer
  ~68 + 3 min, reviewer ~50 min.  Eight items, eight commits, sixteen
  agent runs plus fix rounds, one JVM at a time throughout; tickets E4
  fixed and E5-E10 filed; Stage 4 drafted separately
  (tracker/LSP-STAGE4-DRAFT.md) from a prior-art survey the user asked
  for (tracker/loopmodel/STAGE4-PRIOR-ART.md).
- 2026-09-10 (6.6 DONE): see the item's DONE paragraph.  Implementer
  GREEN (sweep 99.83% clean, 100% on the honest reading), reviewer
  FIX-THEN-ADVANCE with record fixes and one line (the own-field
  exemption), fix round closed all; no second pass needed (the two code
  changes were the reviewer's own).  The plan's `import M (a, b)` was
  wrong for this grammar (`using`/`hiding`); corrected by the
  implementer.  Ticket E10 filed.  Implementer ~80 + 10 min, reviewer
  ~32 min.  Baselines: TestLoopTrace 720/720, five suites 94/94, corpus
  85/69/0 over 154, repl-smoke 8/66 goldens untouched, lsp-smoke 454,
  boot 129.
- 2026-09-10 (6.5 DONE): see the item's DONE paragraph.  Implementer
  GREEN; reviewer FIX-THEN-ADVANCE twice (the grammar has no dotted
  references at all, so qualified completion was refuted and rebuilt as
  a bare-name edit plus an import line; then three applied-edit shapes
  that did not check clean); two fix rounds.  The 4.2 scope-at-position
  layer, never tested until it had a consumer, had two bugs (fold order;
  do-binder frame) — fixed in Renamer.scala, which the batch path never
  reads for frames (reviewer: frozen by construction).  Implementer
  ~40 + 16 + 7 min, reviewer ~27 + 14 min.  Baselines: TestLoopTrace
  720/720, six suites 104/104, corpus 85/69/0 over 154, repl-smoke 8/66
  goldens untouched, lsp-smoke 407, boot 129.
- 2026-09-10 (6.4 DONE): see the item's DONE paragraph.  Implementer
  GREEN, reviewer FIX-THEN-ADVANCE (the report claimed non-overlapping
  sibling ranges while 171 corpus pairs straddled; a namespace leak into
  workspace symbols), fix round closed all, second pass ADVANCE.  Ticket
  E9 (stdlib hits land in the build output tree) filed.  Implementer
  ~43 + 17 min, reviewer ~26 + 17 min.  Baselines: TestLoopTrace 720/720,
  five suites 72/72, corpus 85/69/0 over 154, repl-smoke 8/66 goldens
  untouched, lsp-smoke 344, boot 129.
- 2026-09-10 (6.3 DONE): see the item's DONE paragraph.  Implementer
  GREEN, reviewer FIX-THEN-ADVANCE with two HIGH wrong-edit paths the
  fixtures had not reached (re-export key split; backtick replace range)
  and a stale-sibling gap, fix round closed all three with live pins,
  second pass ADVANCE.  Ticket E8 (tab-expanded parser columns make every
  editor range on a tab-indented line wrong) filed.  Implementer ~45 min
  + 25 min fix round, reviewer ~23 + 12 min.  Baselines: TestLoopTrace
  720/720, five suites 68/68, corpus 85/69/0 over 154, repl-smoke 8/66
  goldens untouched, lsp-smoke 306, boot 129.
- 2026-09-10 (6.2 DONE as PARTIAL, 62.4%): see the item's DONE paragraph
  and the FORK under Blocked/Awaiting.  The night's lesson: the plan's
  premise ("one zonk per binder") was checked by the implementer FIRST,
  as the brief demanded, and found half false; the reviewer then refuted
  the implementer's proposed checker hook (restrictTypes drops the
  recorded meta) AND found the option nobody had seen — the arity split,
  no checker change — which took coverage from 5.6% to 62.4%.  Two
  review passes, one fix round, three orchestrator fixes.  Implementer
  ~3h, reviewer ~45 min.  Code commit 11be9bb; this roadmap entry landed
  in a follow-up commit because the bookkeeping script failed on an
  anchor and the code commit went ahead without it.  Baselines:
  TestLoopTrace 720/720, seven suites 124/124, corpus 85/69/0 over 154,
  repl-smoke 8/66 goldens untouched, lsp-smoke 237, boot 129.
- 2026-09-10 (6.1 DONE): see the item's DONE paragraph.  Implementer
  2h30 (one interruption: an API login expiry killed its turn mid-edit;
  resumed from its transcript with the tree state spelled out — the
  half-written edit compiled, nothing lost), reviewer 26 min, fix round
  5 min.  Two tickets filed from it: E6 (lambda blame needs a checking
  mode; Tier 2 + goldens) and E7 (suppression rule misses operators and
  types; editor path).  Baselines: TestLoopTrace 720/720, corpus 85/69/0
  over 154, repl-smoke 8/66 goldens untouched, lsp-smoke 207, boot 129.
- 2026-09-09 (6.0 DONE): see the item's DONE paragraph.  Orchestration
  as agreed: brief -> fresh Opus implementer (2h20, 180 tool uses) ->
  fresh Opus reviewer (52 min, one re-run of Tier 0 + the third full
  run) -> orchestrator Tier 0 + commit.  One correction to the plan's
  own text: the R-1 mechanism the review had asserted was wrong, and
  the orchestrator's code read that doubted it was itself incomplete —
  the probe, not either reading, settled it.  Baselines: core/test
  943/943 x3 (deterministic), TestLoopTrace 720/720, corpus 85/69/0 over
  154, repl-smoke 8 groups / 66 checks, lsp-smoke 185, /tmp clean.

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

## Gate evidence (G3, recorded 2026-09-10)

G3 SIGNED OFF 2026-09-10 by the user, by opening Stage 4.


Stage 3 shipped in eight item commits on branch scala3-migration, 132354d
(6.0) through the 6.7 commit, each preceded by a fresh Opus implementer,
a fresh Opus reviewer re-running the item's tier once, and the
orchestrator's own Tier 0.  Every item's report and review live under
tracker/loopmodel/LSP3-6.*-*.md; the per-item DONE paragraphs above carry
the numbers.  The gate numbers below are the 6.7 REVIEWER's (its brief
made them the ones of record); the implementer's are in
tracker/loopmodel/LSP3-6.7-WIRING.md.

BATCH STRICTNESS FROZEN — the gate's hard half.  Across the whole stage
the strict path is untouched: `Session.load`/`loadModule`, the REPL
goldens (tracker/repl-tests/*.expected, byte-identical at every commit),
TestReplDifferential and TestTolerantRead's 180-file agreement property
green throughout.  Two shared files changed and were each cleared by
review: `NewPipeline.Read` gained a defaulted `scope` field the strict
path drops (6.3), and `Renamer.scala`'s scope frames were fixed (6.5) —
frames have no batch reader.  No `Subst.scala`, `Type.scala` or printer
change.

BASELINES AT GATE (reviewer's run, one JVM at a time, alone on the tree)
- core/test: 988 total, 988 passed, 0 failed, 0 errors (26m56s), the second full run of the final tree agreeing with the implementer's 988/988 — deterministic since 6.0 (the F4-era flake
  was a test flipping ermine.loadInSeries process-wide).
- tracker/tools/lsp-smoke.sh: 454 checks PASS (185 when the
  stage opened).
- tracker/tools/repl-smoke.sh: 8 groups / 66 checks, goldens unmodified.
- TestLoopTrace 720/720; corpus-run --batch 85 / 69 / 0 over 154;
  g1-validate 9/9 (first run since the stage opened; no signature drift).
- bin/ermine-lsp boot: 129 modules.
- No .ei droppings; git diff -- core/src empty for 6.7 itself.

WHAT THE GATE ASKED FOR, AND WHERE IT IS CHECKED
- the new fixtures (Locals, Refs, Decls symbols, Complete, Fix,
  BadImport): all in tracker/lsp-tests, all in lsp-smoke; the G3 demo
  transcript tracker/lsp-tests/G3-demo.txt exercises every capability in
  one scripted run (tracker/tools/lsp-demo.sh).
- the 6.2 perf line: interleaved A/B on Layout/Report.e, every pair inside
  the 5%/80 ms budget (implementer -13.5 ms pooled; reviewer -9 ms; fix
  round -21 ms) — locals ship ON.
- the 6.6 sweep: 1166 signatures offered over 253 files, 1164 clean
  (99.83%; both type-fails are unfolded aliases that re-check silently),
  0 parse-fails, 168 refused by named reason; ship bar 95% met, both
  actions unfiltered.
- Tier 2 alone on the tree: 988 total, 988 passed, 0 failed, 0 errors (26m56s), the second full run of the final tree agreeing with the implementer's 988/988.

LATENCY AT GATE (Layout/Report.e, 1757 lines; the 6.7 reviewer's
re-measurement, load 0.95-1.31, one JVM, nothing else running)
- keystroke -> diagnostics: 1.69-1.70 s = 0.86 read + 0.50 typecheck
  + 0.30 debounce + 0.03, 97 of 154 components reused; ≈1.9 s on a
  busy machine (the implementer's 1.859 s at load 1.3-2.2).
- THE 1.57 -> 1.7 GAP SINCE G2 IS MACHINE DRIFT, MEASURED: an
  interleaved pair (before/after/before/after) against a scratch build
  of 78d860f — the Stage-3 opening commit, no Stage-3 code — gives
  BEFORE 1.759 s, AFTER 1.694 s (Δ = -65 ms in the final tree's favour,
  -96 and -34 pairwise); the same pre-Stage-3 code reads 0.89-0.92 s
  today against G2's 0.80, which is the whole of the gap.  Stage 3's
  contribution to the round trip is negative on both pairs.
- worst-case request wait DURING a check: 1.45 s median (a hover sent
  352 ms after the keystroke, answered 1.81 s after it; the server does
  not read the request until the check ends); the same hover on an idle
  server 0.58 ms — the 2500x ratio is the whole content of the parked
  worker-thread fork.
- completion 2.2 ms server-side (6.9 ms client round trip); workspace/
  symbol 1.1 ms warm (48 ms first); documentSymbol 21 ms round trip (398
  top-level, 511 total); index build 12.9-18.7 ms warm (56 ms cold);
  code action 52 ms first after a check, ~1 ms after; boot 12.4-12.9 s.

NOT SATISFIED, STATED PLAINLY
- 6.2 is PARTIAL by the item's letter: 62.4% of local binders hover
  (let/where heads, equation arguments, signed binders, plus kinds on
  type names); lambda arguments, case and do binders and nested pattern
  variables need a flag-gated hook at four hot-path sites in Subst.scala
  — the FORK under Blocked/Awaiting, the user's decision.
- Open user-visible tickets from the stage's reviews: E8 (parser columns
  are tab-expanded, so ranges on tab-indented lines are off), E9 (stdlib
  navigation lands in the build-output tree).  Documented residuals: E7
  (the import-failure suppression misses operators and types), the
  group-level refusal at 0:0 outside the corpus.
- Deferred to Stage 4 (draft tracker/LSP-STAGE4-DRAFT.md): the read is
  ~0.9 s of a ~1.9 s round trip and requests wait for an in-flight check
  (~1.5 s worst case) — Stage 3 confirmed inference is not the
  bottleneck and moved the round trip by nothing measurable.

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
