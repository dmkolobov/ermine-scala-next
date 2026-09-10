# LSP Stage 3, item 6.6 — quick fixes (add import, add type signature)

Implementer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.6.md`; item of record
`tracker/LSP-ROADMAP.md` § Stage 3, item 6.6 with the STAGE-3 INVARIANTS and Decision (e); gates
`tracker/GATE-POLICY.md`.  Branch `scala3-migration`, from `c933b61` (6.5 committed).  No commits of
my own; no change to `tracker/LSP-ROADMAP.md` or `tracker/lean/`.

**FIX ROUND** (this revision) after the independent review `tracker/loopmodel/LSP3-6.6-REVIEW.md`
(FIX-THEN-ADVANCE; every gate and every sweep number reproduced, no emitted edit wrong).  **R-1 is
addressed** by re-deriving the largest refusal class from the corpus and rewriting it here and in
`docs/lsp.md` (§5a, §9(4)); **R-2** by correcting the printer ticket's item-(2) examples and stating
the refusal ORDER (§7); **R-3** by tightening `fieldInScope` to the exact own-field shape, with the
sweep re-run to show the table does not move (§5a); **R-4** (§1c), **R-5** ("up to kinds", §5),
**R-6** (§5a), **R-7** (the four excluded files, §5a), **R-8** (§9(11)), **R-9** (§9(2)) and **R-10**
(the dead `SkipOpaque` branch removed and the stale doc comment fixed, §10) likewise.  Two code
changes in total, both in `QuickFix.scala`: R-3's one line, and R-10's restructuring of `Imp` so the
unreachable state is unrepresentable.

**OUTCOME: GREEN.**  `textDocument/codeAction` ships both actions, answered entirely from the last
check's stored results and the current buffer text.  The corpus sweep that Decision (e) makes the one
correctness measurement: **1166 signatures inserted over the 180-file corpus, 1164 of them clean —
99.83 %**, against a 95 % ship bar, with **zero parse failures**.  No syntactic shipping filter is
needed; the four printer limits the sweep found are REFUSALS in the shipped action (168 of 1334
groups) and a ticket draft (§7).  lsp-smoke **407 → 454**.  Every gate green (§8).

The item also closes, visibly, the gap 6.5 pinned as a negative check: a module imported with a
`using` list that does not name what you want is fixed by GROWING the list.

---

## 1. What answers a code action, and what does not

A `codeAction` request fires on every cursor move.  It reads exactly two things:

1. **THE LAST CHECK'S STORED RESULTS.**  The diagnostics that check PUBLISHED, each still paired with
   the source that produced it (`Documents.Doc.diags`, a `List[QuickFix.Published]` filled by
   `Diagnostics.check` in the same breath as the index); the SURFACE TREE and the inferred TYPES, now
   carried on `Definitions.DocIndex` beside 6.5's five references; and the `ModuleScope` scope maps
   plus the session's two origin tables.
2. **THE CURRENT BUFFER TEXT**, read LEXICALLY: the import statements (`QuickFix.imports`), the line
   a signature goes above, and the line terminator every inserted line has to match.

No parse, no rename, no check and no inference is reachable from the handler.  Decision (e) is
explicit that the signature action is offered WITHOUT server-side re-checking, and §5 is the one
measurement that buys that.

### 1a. Staleness is REFUSED here, not accepted — and that is a departure

Every other request in this server answers from a possibly-stale index, because a stale ANSWER is
harmless: a hover one keystroke behind is a hover one keystroke behind.  A code action is not an
answer, it is an **edit**.  A signature inserted at a line the buffer no longer has is corruption.

So: when `idx.version != d.version` — an edit has landed and the ~300 ms debounce has not fired — the
answer is `[]`, with the reason in the log.  This is 6.3's rename rule in the shape a *speculative*
request takes: rename refuses LOUDLY (a `ResponseError`) because the user asked for it; a code action
offers nothing, because the user did not.  Pinned both ways in lsp-smoke (§6, check group 10).

The import edits would in fact have been safe — they are computed against the CURRENT buffer, so
their positions are current by construction — but one rule for the whole request is easier to state
and to trust than two.

### 1b. What the check path pays

`Definitions.DocIndex` gained four fields, every one a REFERENCE to a table the check already built:
`module` (`c.module`, the surface tree), `types` (`c.types`, the map hover already reads),
`termOrigins`/`typeOrigins` (`env.termNameOrigins`/`env.consOrigins`).  Nothing is walked, copied or
rendered in `index`.  `Diagnostics.check` additionally builds one `Published` per diagnostic it is
about to publish — four integers read back off the JSON it just made — so a CLEAN file pays nothing
at all and a broken one pays per diagnostic.

Measured anyway, one pair, `Layout/Report.e` (1757 lines), cold + two warm checks, twice on each
side.  BEFORE is this tree with the five source edits stashed and `QuickFix.scala` moved out, rebuilt
and re-run in the same shell (the 6.4/6.5 protocol).

| | index build (cold / warm / warm) | check round trip |
|---|---|---|
| BEFORE, run 1 | 53.9 / 17.9 / 14.2 ms | 2.06 / 1.42 / 1.27 s |
| BEFORE, run 2 | 64.9 / 23.2 / 16.5 ms | 2.41 / 1.67 / 1.49 s |
| AFTER, run 1  | 63.3 / 20.1 / 18.3 ms | 2.34 / 1.54 / 1.39 s |
| AFTER, run 2  | 69.0 / 19.0 / 21.8 ms | 2.48 / 1.55 / 1.49 s |

Warm index 14.2–23.2 ms before, 18.3–21.8 ms after — one band, its own spread.  Round trip
1.27–2.41 s before, 1.39–2.48 s after.  **Unmoved**, as it must be for four stored references.  7980
occurrences and 511 symbols on both sides.  (Load average 1.8–4.5 throughout: the machine had a game
running in the foreground the whole session.  That is why the bands are quoted rather than a single
figure, and why the two sides overlap on every row.)

### 1c. Per-request cost, and the one memo

`Layout/Report.e`, server-side, from the standing log line:

| | |
|---|---|
| first request after a check | **51 ms** |
| every request after that | **0.1–0.4 ms** (median of ten: 0.3) |
| client round trip, median of ten | 1.8 ms |

The 51 ms is the `source` action: to say "add all missing signatures (N)" it has to know N, which
means rendering every unsigned group's type — `Layout/Report.e` has ~154 unsigned top-level groups,
answers **119 actions** (118 signature quickfixes plus the one `source` action) and logs 36
refusals, so MOST of them are offered and every one of them is rendered (review R-4 corrected the
first round's "36 groups, most of them refused", which had it backwards).  Doing
that on every cursor move is not acceptable, so the handler holds ONE memo keyed by
`(uri, document version)` — the same pair the staleness refusal already turns on, so an edit
invalidates it by construction and dispatch is single-threaded, so no lock.  Without the memo the
median was 28 ms and the worst case 51 ms; with it, 0.3 ms.  Both figures are in `docs/lsp.md`.

## 2. What is stored, and how a request matches it (6.6.1)

`QuickFix.Published(sl, sc, el, ec, message, severity, spelling, json)`, one per published
diagnostic, stored by `Diagnostics.stored` — which EVERY exit from `Diagnostics.check` now goes
through, the two unrecoverable `Death` cases included, so the stored list is never one check behind
the wire.

* The **range** is the one that WENT OUT, read back off the JSON the publish is about to send.  It
  cannot drift from what the editor shows, because it is the same object.
* The **source** is `TolerantCheck.Note.spelling` — the FLAG 5.4 put on undefined-term notes, not a
  match against rendered message text (6.1's rule: "the caller must not have to parse rendered report
  text to know what kind of note it holds").  A read-phase `NewPipeline.Diag` is stored too, with no
  spelling; nothing fixes one today, but the stored list is the whole published set or it is not the
  list the client is looking at.
* The published list **survives a didChange**, for the same reason the index does: it is what the
  editor is still showing.  A code action does not USE it across an edit (§1a).

**MATCHING.**  A stored diagnostic is in range when its LINES intersect the request's:
`p.sl <= el && sl <= p.el`.  Not character overlap — an undefined-term note has NO span (its `Note`
carries none, so `Diagnostics.fromReport` recovers the position from the report's `file:line:col:`
prefix and publishes a CARET, end = start), so a character test would only ever fire with the cursor
on that exact column.  "The fixes for the squiggles on these lines" is what a user asking for a fix
means.

**The client's copy is never trusted for correctness.**  `context.diagnostics` is used for one thing:
when a client-supplied diagnostic matches a stored one by (range, message) exactly, THAT object is
echoed back in the action's `diagnostics` field, so the client gets its own object identity.
Otherwise the stored rendering is echoed.  Selection is always from the stored list.

`context.only` is honoured (a kind matches itself or a `kind.` prefix); pinned both ways in the
smoke.

## 3. ADD IMPORT — the rules, every case (6.6.2)

**The candidates for an undefined term `s`:**

* **(a) the session.**  Every `Global` in the check's own `ModuleScope.termNames` — the session
  superset this file was checked against — whose spelling is `s`, mapped through the session's
  `termNameOrigins` to its GREATEST ANCESTOR.  So a module that re-exports a name and the module that
  DEFINES it are one candidate, and the one offered is the definer.  (A re-exporter would import
  fine too; the origin is the answer that does not depend on which re-exporter we happened to
  enumerate first.)  `not` therefore offers `Bool` and `Relation.Predicate` — two genuinely different
  definitions — and not the half-dozen modules that re-export `Bool`'s.
* **(b) the open siblings.**  Every other open buffer whose last check's `Renamer.Result.moduleTerms`
  declares `s`.  A module the resident session has never loaded is a candidate while its buffer is
  open.

At most **8** actions per name, alphabetically (`MaxImports`): a common spelling is exported by a
dozen stdlib modules and a menu of twelve is not a fix.  Stated in `docs/lsp.md`.

**`isPreferred` only when there is exactly one candidate.**  A client's auto-fix takes the preferred
action without asking, and choosing one of two modules for the user is not something this server
knows how to do.

**THE EDIT**, decided from the CURRENT buffer (an import typed a second ago counts, exactly as it
does for 6.5's qualified completion):

| how M is imported | what happens | title |
|---|---|---|
| M is this module | no action (`SkipOwn`) | — |
| not imported | `import M using name` on its own line after the LAST import; after the `module … where` line when there are none; at line 0 when there is no header either | `import M using name` |
| openly, `import M` | no action (`SkipOpen`) — every name M exports is in scope, so an undefined `s` did not come from M | — |
| with an alias, `import M as A` | no action (`SkipAlias`), whatever the list says | — |
| `using` a list WITHOUT the name | `; name` inserted after the list's last item — inside the braces when it has them | `add name to the M import list` |
| `using` a list WITH the name | no action (`SkipListed`) | — |
| `hiding` a list WITH the name, several items | the item is DELETED, with one separator | `stop hiding name from M` |
| `hiding` a list WITH the name, only item | the whole `hiding` clause is deleted, leaving `import M` | `stop hiding name from M` |
| `hiding` a list WITHOUT the name | no action (`SkipListed`) | — |

**Why an alias is refused rather than fixed.**  `ModuleScope.local` calls `Global.localized`, so
`import Bool as B` puts `not_B` in scope and never `not`; and `ModuleHeader.imports` **dies** on a
duplicate module import (`"Duplicate module imports not correctly handled"`), so a second, unaliased
`import Bool using not` is not available either.  There is no edit that makes the bare name resolve.
6.5 found the same wall from the other side and inserts the affix form instead.

**`(a, b)` IS NOT THE GRAMMAR.**  The brief and the roadmap item both say `import M (a, b)`; this fork
has no parenthesised import list at all.  `SurfaceParsers.importStatement` takes `using` / `hiding`
over a `laidout` list, which is why every title and every edit above says `using`.  6.5 found this
first; this item's scanner is the proof (§3a).

**OPERATORS.**  An import item writes an operator parenthesised — `import List.NonEmpty using (:|) ;
type NonEmpty` is in the stdlib — and `QuickFix.written` produces exactly that from the spelling and
the fixity, so the machinery is there.  In practice an undefined OPERATOR never reaches this action:
an unknown operator is a READ-phase failure (`unknown operator` from `Reassoc`, then `ill-formed
expression` and `error node` from `Lower` — 6.1's own ticket says so), a `NewPipeline.Diag` with no
`spelling`, not a `Note`.  So the operator path is written and unreachable, and the report says so
rather than claiming coverage.

**TYPE NAMES ARE OUT OF SCOPE**, as the brief allows.  An "undefined type" is not a `Note` with a
spelling: `Subst.scala:1743` dies with ALL the free type variables in ONE `Death`, which
`TolerantCheck.guard` turns into a single note with no spelling and no per-name span.  Carrying a
spelling means changing `Subst.scala`, which the Stage-3 invariant makes **Tier 1** and requires the
item to stop and say so.  This is the saying-so.  (6.1's E7 recorded the same absence.)

### 3a. The import scanner, and the bug the corpus found

`QuickFix.imports(text)` returns, per statement: the line, the LAST line under the layout rule (a
laid-out list continues onto every following line indented deeper than the `import` keyword — three
stdlib files do this), the module, the alias, `using`/`hiding`/open, the items with their spans, and
the two positions an edit needs.  6.5's `Completion.importLines` is now a projection of it, so there
is ONE scanner in the server and 6.5's pins still hold.

The buffer is scanned with **comments blanked out**, character for character (`QuickFix.masked`:
`--` lines, nesting `{- -}` blocks, string literals tracked so a `--` inside one is not a comment).
This is not decoration.  `core/src/main/resources/modules/Layout/Scan.e` carries
`import Layout.Presentation as P` at line 84 INSIDE a `{- -}` block: a scanner that reads it believes
the module is imported twice, skips the fix that would have worked, and anchors a new import line
inside a comment.  The 249-file differential in the sweep is what found it.

**THE DIFFERENTIAL:** for every corpus file whose check is silent, `QuickFix.imports` is compared
against the PARSER's own `SHeader.imports` on the same text — module, alias, list kind, and every
item's (name, isType, provided spelling).  **0 disagreements over 249 files.**  (The one
normalisation is on the parser's side: it keeps an operator item's parentheses in the spelling,
`(++)`; the scanner strips them, because the spelling an undefined-term note carries is the bare
one it has to match.)

**Stated assumptions**, because they are the whole of the scanner's soundness: an import statement
starts its line (no corpus file writes `import A; import B` on one line and no corpus header opens an
explicit `{` block); a braced list ends at its matching `}`; an unbraced one ends with the layout
block.  A file that broke any of these would get an edit at the wrong place — the differential is
what says none does.

## 4. ADD TYPE SIGNATURE — the rules (6.6.3)

**Which groups.**  `QuickFix.groups` walks the surface tree's top level plus `private` and `database`
blocks (their statements ARE top-level bindings), gathering per spelling: whether any
`SSigStatement` names it, and the first `SEquation` for it.  A `class` body is not walked — its
members are methods, whose signatures the class declares.  A group is a candidate when it has an
equation, has no signature, and `TolerantCheck.types` has its type.

**The edit.**  `<indent><head> : <rendered type>` inserted at (equation line, column 0), where
`<indent>` is the equation line's own leading whitespace and the line ends with the buffer's own
terminator.  Inside a `private` block that puts the signature inside the block, because the
indentation carries it there.

**The head comes from the source FORM, not the fixity.**  `SName.form` says `Plain`, `ParenOp`,
`ParenPrefixOp`, `ParenPostfixOp`; the head is the spelling, `(op)`, `(prefix op)`, `(postfix op)`
respectively, with a non-letter-initial `Plain` name double-backticked the way `Pretty` does it.
`Function.e` is why: `(`) a f = f a` defines the backtick operator, its `SName` carries `Idfix`
(fixity is the LEXER's bucket, not a resolved precedence), and a fixity-driven rendering wrote five
backticks.  The form says `ParenOp` and `` (`) `` is what the source wrote.

**The rendering is the printer hover uses** — `Pretty.prettyType(t, -1)` — laid out **flat**:
`Document.toString` formats at 80 columns, and a wrapped signature is a signature whose continuation
lines the layout rule may or may not accept.  Same document, no width limit.  A hard break (there is
none in type printing today) is caught and refused, not inserted.

**The `source` action**, "add all missing signatures (N)": one `WorkspaceEdit` with every insertion,
sorted by line **descending**.  A conforming client applies a `TextEdit[]` against the ORIGINAL
document, so order cannot matter to it; a client that applies them in sequence needs the later lines
first or every insertion after the first lands a line low.  Descending satisfies both.

**Kind: `quickfix`, not `refactor.rewrite`.**  The per-group signature action is a `quickfix` with no
`diagnostics` field; the file-wide one is `source`.  Those are the two kinds `codeActionProvider`
declares (6.6.5), and a client asking `only: ["refactor"]` must not be told we have something we then
do not send.

### 4a. The refusals, and why each one exists

Every one of these was found by the sweep, and each is a case where the offered line would not work.

| refusal | what it catches | corpus |
|---|---|---|
| `OutOfScope` | a type constructor (or an imported row field) the file does not have in scope under the spelling the printer writes | 117 |
| `FreeKind` | a kind variable in an `exists` binder's kind that no `forall {…}` quantifies | 36 |
| `StarArrow` | a nested `* ->` kind the printer writes without the brackets it needs | 10 |
| `Unlexable` | a name the printer writes with a `.` in it (`<:_Type.Cast`) | 2 |
| `FieldIdentity` | a concrete row whose IMPORTED field name does not round-trip | 3 |
| `HasSig`, `NoType`, `NotLineStart`, `BehindTab`, `Wrapped`, `NoHead` | structural: already signed, no inferred type, an equation that does not start its line (`a = 1; b = 2`), an equation behind a TAB (ticket E8's units problem), a wrapped rendering, a head form a signature cannot write | 0 over the corpus |

**The scope test is an IDENTITY test, not a spelling one.**  For each `Type.Con` in the type, the name
the printer will WRITE (`printedName`: the bare spelling for an `Idfix` global, `n_Module` for an
operator — `Pretty.ppType`'s operator cases at Pretty.scala:290-292 write the affix form whatever the
`Qualification` says) must be a key of the file's `canonicalTypes` whose entry DENOTES that very
`Con`, chased through `consOrigins` because `ModuleScope.collapseNames` keeps a singleton entry
un-collapsed (`Maybe.Maybe` where the `Con` says `Native.Maybe.Maybe`).  Own types short-circuit.

**Row FIELDS are stricter, and had to be.**  A type constructor reached through a re-export still
means the same type; a field does not.  `core/examples/Algebra/Deduplication.e` infers
`Mem (|Count, customerId|)` whose fields are `Field.Count.Count` and
`Algebra.Deduplication.customerId.customerId`, while the same two words WRITTEN in that file resolve
to `Prelude.Count` and `Algebra.Deduplication.customerId` — different `Global`s, and the checker then
refuses to unify the declared row with the inferred one ("failed to unify type `(|Count,
customerId|)` with type `(|Count, customerId|)`", which is exactly as helpful as it looks).  So an
IMPORTED field must resolve to ITSELF with no chase.  A field THIS module declares is exempt and had
to be: a `field` statement mints its own pseudo-module, the module's own names are not in
`canonicalTerms` at all, and the strict test refused **450** insertions over the corpus that check
perfectly well.  Measured both ways (§5a).

## 5. THE SWEEP — Decision (e)'s one correctness measurement (6.6.4)

**Where it lives.**  A property in `TestTolerantCheck` (it needs that suite's resident session and
its 180-file corpus list, both of which already exist), registered but gated: it runs only under
`-Dermine.sweep.quickfix=true`, and is `Prop.proved` otherwise.  It is NOT part of the shipped suite,
because it costs two checks of the whole corpus plus one per failing insertion — about 100 s on top
of `TestTolerantCheck`'s own two passes, taking the suite from ~75 s to ~175 s.  That is the gate
policy's own shape for a measurement that is not a per-commit gate.  Reproduce with:

```
sbt -batch -J-Xmx3g -Dermine.sweep.quickfix=true 'core/testOnly *TestTolerantCheck'
```

**What it does.**  For every file: check it; render the add-signature edit for EVERY unsigned
top-level group; apply them ALL to a copy of the text in memory; check the copy.  A copy that checks
silent AND whose every group's type is alpha-equivalent **up to kinds** (§5's comparator note) to the
original is N clean insertions.  A
copy that is not is **bisected**, one insertion at a time, so every failure is attributed to the line
that caused it and not to its neighbours.

**The classes.**  CLEAN; PARSE-FAIL (a new READ diagnostic — `Checked.diags`, the tolerant read's
own, so the inserted line did not parse); TYPE-FAIL (a new CHECK note, or a group whose type moved,
with the read silent); SKIPPED (the builder refused, with its reason).

**ALPHA-EQUIVALENCE — UP TO KINDS — is `tools/G1Compare.alphaEq`** — the comparator the G1 gate's `.ei` differential
is built on — with ONE completeness repair made in the test and NOT in `G1Compare` (that is a gate
tool and its verdicts are not this item's to move): `G1Compare.matchMultiset` keeps only the FIRST
bijection each constraint admits, so a permuted row-constraint set whose first pairing paints the
bijection into a corner is reported unequal even when a consistent pairing exists.  `Relation.e`'s
`&` is exactly that (`a <- (e, d), r <- (d, c)` against `a <- (d, e), r <- (c, d)`).  The version in
the sweep returns EVERY bijection lazily, so the search backtracks and stops at the first success; it
is strictly more permissive and agrees with `G1Compare` everywhere the latter succeeds.  **5 pairs
over the corpus are equal only under the complete comparator** — the number is printed, so both
comparators' verdicts are on the record.  (It was 6 on an earlier run of the same tree: the counter
only sees pairs the `forall` short-circuit actually reaches, so it is a lower bound on the
disagreement, not a census of it.)

**NEITHER COMPARATOR COMPARES KINDS** (review R-5).  `G1Compare.alphaEq`'s `Forall` case zips `ks`
into the bijection and never calls `kindEq`, and the complete variant inherits that: two types
differing only in a binder's KIND compare equal.  Inherited from the gate tool, not introduced here,
and bounded by the fact that CLEAN also requires a diagnostic-free re-check — a signature whose kinds
were wrong would not check.  Every "alpha-equivalent" in this report means "up to kinds".

**Comparing RENDERED TEXT was tried first and is not good enough**, and the first run proved it: 145
of its 223 "failures" were a `forall {a b c …}` kind-binder group in a different ORDER
(`Layout/Column.e`'s `endoColumn`) or a `Part`'s row-constraint arguments in a different order
(`Field.e`'s `getF2`) — the two classes G1's own gate calls logically equal.  That run reported
81.35 %; with the right comparator the same tree reported 97.37 %.

### 5a. THE SWEEP TABLE

Final tree, 2026-09-10.  Corpus: `core/src/main/resources/modules` + `core/examples` minus
`shouldfail`/`shouldfail-controls`/`incomplete`, the standing 180-file rule.

| | |
|---|---|
| files found | **253** |
| files excluded (their own check is not silent, so nothing can be attributed) | 4 — `core/examples/Interp.e`, `Sample.e`, `Yahoo.e`, `guide/HelloWorld.e`, all genuinely broken and the same four the 6.2 sweep excludes (review R-7) |
| unsigned top-level groups | **1334** |
| insertions OFFERED | **1166** |
| **CLEAN** | **1164 — 99.83 %** |
| PARSE-FAIL | **0** |
| TYPE-FAIL | **2** |
| SKIPPED (refused, with a reason) | **168** |
| import-scanner disagreements against the parser | **0 over 249 files** |
| pairs equal only under the complete comparator | 5 |

**SHIP BAR: ≥ 95 % clean.  Result 99.83 %.  Both actions ship, with no syntactic filter.**

This is the FIX-ROUND run, with review R-3's tightened `fieldInScope`.  **Every figure is unchanged**
from the first round's — 1166 insertions, 1164 clean, 168 skipped, `FieldIdentity` still 3 — which is
what says the loosened exemption was latent rather than active: no corpus module re-exports a field
through a submodule of itself, and now none can slip past the strict test if one ever does.

**PARSE-FAIL by construct: none.**  Eleven existed before the refusals of §4a were added, in three
classes, and all eleven are now refused rather than emitted (see the ticket, §7).

**TYPE-FAIL by construct — 2, both the same shape and both with a SILENT re-check:**

| construct | n | example |
|---|---|---|
| a type ALIAS unfolded by the re-check | 2 | `Validation.e` `empty_Bracket`: offered `Map String String -> Either (List Err) (Record (||))`; after the declaration the group's type renders `… Either (List (String, String)) …`.  `Validation.e:16` is `type Err = (String, String)` — the alias is unfolded, so the comparator sees the alias `Con` against its expansion.  The other is `cons_Bracket` in the same file. |

**BOTH INSERTED SIGNATURES ARE CORRECT, AND BOTH FILES RE-CHECK WITH ZERO DIAGNOSTICS** (review
R-6).  They are counted as failures only because the sweep's criterion is alpha-equivalence and an
alias unfold is a definitional step, not an alpha one.  The sweep's labels for them
(`type moved: concrete row (|…|)` / `type moved: row constraint (<-)`) are `shape()` buckets of the
inserted TEXT, not diagnoses — "row constraint" there reads like a row-order failure, and no row
order failed.  **The honest reading is 1166 of 1166 usable (100 %); the strict count is 1164 of 1166
(99.83 %).**  Both are far above the bar, and the strict one is what the table above reports.

**SKIPPED by reason — 168:**

| reason | n | example |
|---|---|---|
| **the type is not in scope under the spelling the printer writes** | **117** | `Layout/Chart/Unsafe.e` `axisChartData#`: the printer writes `Map`, and the file has `import Native.Map as NM` |
| the printer emits a kind variable nothing quantifies | 36 | `Relation/Aggregate.e` `avg` |
| the printer drops the parentheses a nested `* ->` kind needs | 10 | `Layout/Report.e` `drilldownPieChart2` |
| the printer writes a name with a `.` in it | 2 | `Native/Throwable.e` `throwableObject`: `<:_Type.Cast` |
| an imported row field does not round-trip | 3 | `core/examples/Algebra/Deduplication.e` `supersededCount` |

**THE 117, RE-DERIVED (review R-1).**  The first round called this class "the file genuinely does not
import the type", which is wrong for most of it, and said an add-import action would serve it, which
is true of hardly any of it.  The sweep now classifies every NAME each refusal cites (117 refusals
cite 150 type names between them, so these are name occurrences, not groups):

| sub-class | names | what it really is |
|---|---|---|
| **imported under an ALIAS** | **68** | the file DOES import the type — as `import Native.Map as NM`, `import Layout.Report as L` — so only the affix spelling `Map_NM` resolves and the printer writes the bare `Map`.  This is the printer ticket's item (3) in its `Idfix` form: `Pretty` under `Unqualified` writes a type constructor's BASE name and cannot know the file reaches it only through an alias.  Head names: `Report` 8, `Presentation` 8, `Map` 6, `Format` 6, `Column` 5. |
| **not nameable here at all** | **49** | the type cannot be written in this file however you spell it.  31 of them are one name: `ErasedMagnitude`, which is `private data` in `Native/Magnitude.e` (27 occurrences in `Layout/Report.e`, 4 in `StyleGridHeatmap.e`).  The rest are types no import of this file provides. |
| **the file's OWN synonym — a FALSE NEGATIVE** | **33** | the file CAN write the name, through a `type` synonym of its own, and the action refuses anyway.  29 of them are `Scan` in `Layout/Scan.e`, which declares `type Scan = Scan_S` over its aliased `import Relation.Scan as S`; the reviewer's control appends `probeScan : forall z a. Scan z a -> Scan z a` to that file and it checks with **0 diagnostics**. |

So of the 117: the first two sub-classes are **correct refusals** — the offered line would not have
parsed, and no add-import action can serve either of them (the alias case would need the affix
spelling the printer will not write; the private-data case has nothing to import).  The third is a
**gap in `inScope`**, and it is the only one of the five refusal reasons that costs a signature that
would have worked.  Controls that say the refusals themselves are right: `Vector` and `Report`
written bare in `Layout/Scan.e` both draw `undefined type`.

**Is the synonym false negative cheap to fix?  No, and it is a ticket line (§7 item 5).**  `inScope`
tests the printer's spelling against `ModuleScope.canonicalTypes`, which holds what the file's
IMPORTS put in scope; a module's own `type`/`data` names are not in it, and accepting any name the
surface tree declares as a type would be unsound (`type Foo = Bar` makes `Foo` writable, but says
nothing about whether the `Con` the printer is writing IS `Foo`'s expansion).  The sound test needs
the alias-to-`Con` map, which `TolerantCheck` builds in its local `maps`
(`Session.processTypeDefComponent`) and throws away: publishing it is a new `Checked`/`DocIndex`
field and a line in `TolerantCheck` — an editor-path change, not a Tier-1 one, but bigger than a fix
round and worth doing with the printer ticket's item (3), since the two together are 101 of the
117.

**The 450-insertion measurement behind the own-field exemption (§4a).**  With the strict field test
applied to a module's OWN fields too, insertions fell from 1166 to 719 and 450 clean insertions were
lost to catch the 3 that break.  Both numbers are from full sweep runs on this tree.

## 6. Tests

### 6a. `TestQuickFix` — a new suite, 18 properties, no session

The two edit builders as pure functions, exactly as the brief asks.  The import scanner (module,
alias, `using`, `hiding`, a braced list, a laid-out multi-line list, an operator item read WITHOUT its
parentheses, `x as y` providing `y`, and a `{- -}` block hiding its imports — the `Layout/Scan.e`
shape); the add-import edit for no imports, after the last import, into an existing `using` list in
all three of its layouts, out of a `hiding` list as the only / first / later item, and the four
refusals; the group walk over a parsed surface tree (a signature found, a `private` block treated as
top level, a class body not, an operator head written `(<+>)`); the signature edit's placement
(indentation, inside a `private` block, an operator head, the `already signed` and `does not start
its line` refusals); and CRLF on both edit kinds.

### 6b. `TestTolerantCheck` — the sweep (§5), 26 → 27 properties

### 6c. lsp-smoke — 407 → 454 (+47)

Four new fixtures — `tracker/lsp-tests/Fix.e`, `FixSib.e` (an open sibling that declares a name the
stdlib also exports), `FixTy.e` (a sibling with a TYPE of its own, so `Fix.e` can import the term
`paint` without the type `Colour` its signature would name) and `FixCrlf.e` (**CRLF on disk**) — all
of which check CLEAN.  What is pinned, live, end to end:

* the **capability** block, exactly `{"codeActionKinds": ["quickfix", "source"]}`;
* a request **before the session boots** → `[]`, sent before `initialized`;
* an **unsigned binding** offers `add signature: answer : Int`, a `quickfix` with no `diagnostics` and
  no `isPreferred`, whose edit is the exact insertion at (9,0); the client APPLIES it, re-sends the
  buffer, **it re-checks clean**, and **hover on `answer` afterwards shows the same type**;
* a **signed binding** offers no signature action;
* a group whose rendered type names an **unimported type** offers none either (`peek = paint` is
  `Colour`, and `Fix.e` imports only the term);
* **"add all missing signatures (2)"**, a `source` action: two insertions for the two offerable
  groups, at lines **[11, 9] — descending**, the second one the polymorphic
  `pairUp : forall a. a -> (a, a)`; applied, the file re-checks clean, and the action is then GONE;
* an **undefined `not`** offers **two** actions, `import Bool using not` and
  `import Relation.Predicate using not` (both modules really define one), each carrying the
  diagnostic it fixes, **neither preferred**; the Bool one's edit is the exact line insertion at
  (5,0), and applying it CLEARS the diagnostic;
* **the open sibling** is a candidate: `catMaybes` offers `import FixSib using catMaybes` (a new line)
  and `add catMaybes to the Maybe import list` (a list edit); both applied, both check clean;
* **THE 6.5 GAP CLOSED**: the Maybe action's edit is `; catMaybes` at (2,25), inside the existing
  `using` list — the very case 6.5 pinned as the diagnostic it leaves;
* **one candidate ⇒ `isPreferred`**: `isNothing` offers exactly `add isNothing to the Maybe import
  list`, preferred, and the applied `import Maybe using isJust; isNothing` checks clean;
* **a `hiding` list**: `id` under `import Function hiding id` offers `stop hiding id from Function`,
  whose edit deletes (3,15)-(3,25) — the whole clause, since `id` is its only item — and the applied
  `import Function` checks clean;
* **`context.only`**: `["source"]` answers the source action alone, `["quickfix"]` drops it;
* **the staleness refusal**, both ways: a didChange, then the request immediately (before the ~300 ms
  debounce) → `[]`; after the diagnostics for that check arrive, the same request answers;
* **CRLF end to end**: the signature line's `newText` ends `\r\n`, the applied buffer has no lone
  newline anywhere, and it re-checks clean; the same for an inserted import line;
* **cost** under 50 ms, asserted live (best of five);
* `Fix.e` on disk is byte-unchanged by all of it.

## 7. Printer ticket (draft)

> **Ticket (Stage 3/4, printer): `Pretty` renders four shapes that the grammar cannot read back, and
> the editor's scope test misses a fifth.**
> Found by the 6.6 corpus sweep (`tracker/loopmodel/LSP3-6.6-QUICKFIX.md` §5); the add-signature
> quick fix REFUSES all four rather than emitting them, which costs 51 of 1334 corpus groups
> (`QuickFix.StarArrow`, `FreeKind`, `Unlexable`, `FieldIdentity`).  Each is a printer bug, not a
> grammar gap, except (4).
>
> **(1) A nested `* ->` kind loses the parentheses it needs — 10 groups.**  Measured against the
> grammar directly: `forall (a: rho -> *)`, `forall (a: * -> *)`, `forall (a: rho -> rho -> *)` and
> `forall (a: rho -> (* -> *))` all PARSE; `forall (a: rho -> * -> *)` and `forall (a: * -> * -> *)`
> do NOT ("expected '=', pattern atom, or whitespace" — the signature alternative fails and the
> statement falls back to an equation).  The failing element is an `ArrowK` that is the RIGHT operand
> of another `ArrowK` and whose left operand is `*`.  `Pretty` writes kind arrows right-associatively
> without brackets, so `Relation/Op.e`'s `negate` renders
> `forall (opr: rho -> * -> *) (c: rho). AsOp opr => …` and does not parse.  Fix: parenthesise a
> nested arrow whose left operand is `Star` (or find and fix whatever in the kind parser makes `*`
> different from `rho` there — that is the more interesting question and the probes above are the
> reproduction).
>
> **(2) An `exists` binder's KIND names a variable nothing quantifies — 36 groups.**
> `Relation/Aggregate.e`'s `avg` renders
> `forall (op: rho -> * -> *) (r: rho) n. (exists (AsOp: (rho -> * -> *) -> a). AsOp op,
> PrimitiveNum n) => op r n -> Aggregate r n` and `Layout/Report/Relation.e`'s
> `cutoffGroupedFldsPosNegRel'` is the other named case; the shape in general is
> `(exists (AsOp: (rho -> * -> *) -> a). …)` where `a` is a kind variable and the enclosing `forall`
> has no `{…}` group binding it.  (The first round cited `Relation/Op.e`'s `cons_Bracket` and
> `Syntax/Procedure.e`'s `functionArg`; both are refused under item (1) instead, and `functionArg`
> renders `forall (a: rho -> * -> *) (b: rho) c. AsOp a => a b c -> FunctionArg` with no `exists` and
> no free kind variable at all — review R-2.)  `Forall.ks` is what the printer writes between
> braces and an `Exists` quantifies type variables only, so a kind variable under one has to have
> been quantified further out and is not.  Detected structurally by `QuickFix.freeKinds`.
>
> **(3) An infix constructor is written `n_Module` regardless of `Qualification` — 2 groups.**
> `Pretty.ppType`'s operator cases (Pretty.scala:290-292) write a `Global(m, n, Infix(p, a))` as
> `n_m`, the affixed REFERENCE form, with the module's FULL name as the affix — while `ppName`, on
> the same Global, honours `Unqualified` and writes `(n)`.  `Native/Throwable.e` imports `Type.Cast`
> plainly, so `<:` is in scope as `<:`, and `throwableObject` renders
> `Throwable <:_Type.Cast Object`, which the lexer reads as `<:_Type` then `.`
> ("unknown type operator `<:_Type`", then "unknown type operator `.`", then "ill-formed
> expression").  Under `Unqualified` the operator cases should write the bare spelling; the affix
> form is right only when the file imports that module under exactly that alias, which nothing
> checks.
>
> **(4) A concrete row's FIELD names do not round-trip — 3 groups, and this one is not the printer.**
> `core/examples/Algebra/Deduplication.e` infers `Mem (|Count, customerId|)` whose field `Global`s
> are `Field.Count.Count` and `Algebra.Deduplication.customerId.customerId`; the same two words
> written in that file resolve to `Prelude.Count` and `Algebra.Deduplication.customerId`.  Rows
> compare field names by `Global` identity, so the declared row does not unify with the inferred one
> and the error prints the two as the same text.  An own field is harmless in practice (450 corpus
> insertions with one check clean), an imported one reached through a RE-EXPORT is not.  The fix is
> in whatever mints a field's `Global` for a row, or in unification's notion of field identity — not
> in `Pretty`.  Evidence: `Deduplication.e` `supersededCount` / `eventsBySource`,
> `ManagerChains.e` `spanOfControl`.
>
> **THE TWO COUNTS ARE NOT INDEPENDENT.**  `sigEdit` tests `freeKinds` BEFORE `starArrow`, so a group
> whose rendering carries both lands in the item-(2) bucket and never reaches item (1).  36 and 10
> are therefore a partition of the groups by FIRST failing test, not a census of each shape.  Fixing
> (2) alone would move some of its 36 into (1).
>
> **(5) `inScope` cannot see through a module's OWN type synonym — 33 name occurrences.**  Not a
> printer bug and the mildest of the five, but the only refusal class that costs a signature which
> WOULD have checked.  `Layout/Scan.e` declares `type Scan = Scan_S` over `import Relation.Scan as
> S`; the printer writes `Scan`, `ModuleScope.canonicalTypes` holds only what the IMPORTS put in
> scope, and the action refuses 29 of that file's groups.  A control appending
> `probeScan : forall z a. Scan z a -> Scan z a` to it checks with 0 diagnostics.  The sound fix
> needs the alias-to-`Con` map `TolerantCheck` builds in its local `maps` and discards — a new
> `Checked`/`DocIndex` field and one line in `TolerantCheck`, which is editor-path, not Tier 1.
> Worth doing WITH item (3): together they are 101 of the 117 out-of-scope refusals.
>
> Fixing (1)-(3) would return 48 groups to the add-signature action and remove its three
> printer-shaped refusals; (3) and (5) together would return most of the 117 out-of-scope ones.  The
> sweep is the regression test: re-run it and the SKIPPED table moves.

## 8. Gates

Tier 0 plus the targeted suites.  One JVM at a time throughout; every number below is from the FINAL
tree.

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | **green** (the one pre-existing `NewPipeline.scala:361` deprecation, untouched) |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**; hashdiff 0, eqdiff 0, nonpart 0, fuel 0, skipped 0; 3 properties passed |
| `sbt 'core/testOnly *TestQuickFix *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestRenamer*'` | **94 / 94 passed, 0 failed, 0 errors** — TestQuickFix **18** (new), TestTolerantCheck **27** (26 + the sweep), TestTolerantRead 11, TestEditorBuffers 6, TestRenamer 32 (unchanged).  Fix round re-ran `*TestQuickFix *TestTolerantCheck`: **45 / 45** |
| the 6.6 sweep, `-Dermine.sweep.quickfix=true` | **1166 insertions, 1164 CLEAN (99.83 %)**, PARSE-FAIL 0, TYPE-FAIL 2 (both correct signatures, silent re-checks — §5a), SKIPPED 168, import-scanner disagreements 0 over 249 files.  RE-RUN in the fix round with R-3's tightened `fieldInScope`: **every figure identical** |
| `tracker/tools/corpus-run.sh --batch <scratch>/corpus` | 154 outputs, **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** |
| `tracker/tools/repl-smoke.sh` | **8 groups / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); goldens unmodified (`git status tracker/repl-tests` clean) |
| `tracker/tools/lsp-smoke.sh` | **454 checks** (6.5's baseline 407; +47) |
| boot | `Ermine session ready: 129 modules` — asserted by lsp-smoke on every run |
| Report.e check time before/after | index warm 14.2–23.2 ms before, 18.3–21.8 ms after; round trip 1.27–2.41 s before, 1.39–2.48 s after — **unmoved** (§1b) |
| codeAction cost | **51 ms** on the first request after a check, **0.1–0.4 ms** after (median of ten 0.3 ms; client round trip 1.8 ms) on `Layout/Report.e` (§1c) |
| `.ei` | **0** created; the only `.ei` in the tree are the 14 checked-in `tracker/g1-oracle-tests` fixtures, mtime unchanged |
| line endings | `git diff --stat` and `git diff --stat -w` are **IDENTICAL** — no file reformatted (every file this item touches was already LF; `FixCrlf.e` is a new CRLF fixture, deliberately) |

Not run, and why: **Tier 1** (no solver, no `Type.scala` constraint construction, no `Subst.scala`,
no executable Lean); **Tier 2** (`core/test` in full — not an adoption commit, no default flips); no
perf A/B (nothing is added to inference or to the check; the check-path pair in §1b is the
measurement this item owes).

## 9. What is inherited, incomplete or deliberately plain

1. **Type names get no add-import action** (§3), because the note carries no spelling and giving it
   one is a `Subst.scala` change, which is Tier 1.  Stated, not fixed.
2. **The operator path in add-import is written and unreachable** (§3): an unknown operator is a read
   diagnostic, not a `Note`.  6.1's ticket is the same finding from the other side.  And it is
   unreachable in TWO places, not one (review R-9): the sole caller of `addImport` hardcodes `Idfix`,
   so even if a note carried an operator spelling the item would be written ` ``++`` ` rather than
   `(++)`.  §3's "the machinery is there" is true of `written`, not of its caller.  Left as is
   deliberately: wiring a fixity through a path nothing can take would be untested code, and the
   `Note` change that makes it reachable is the same one that should supply the fixity.
3. **51 corpus groups are refused for a printer reason** (§4a, §7).  Each refusal is silent — the
   action simply is not offered, with the reason in the log.  A user sees nothing wrong; they also
   see nothing.
4. **117 groups are refused because the type is not in scope under the spelling the printer writes**
   — and that is three different situations, not one (review R-1; §5a has the counts and the
   controls).  **68 name occurrences are types the file DOES import, under an ALIAS**, where only the
   affix spelling resolves and the printer writes the bare name: an add-import action cannot serve
   them, because the module is already imported and the fix is in the printer (ticket item 3).  **49
   are types nothing can bring into that file**, 31 of them the `private data ErasedMagnitude`: an
   add-import action cannot serve those either.  **33 are a FALSE NEGATIVE** — the file can write the
   name through a `type` synonym of its own, and `inScope` cannot see through one (ticket item 5).
   So the first round's "an action that ALSO added the missing import would serve them" is true of
   hardly any of the 117, and is withdrawn.
5. **The import scanner is lexical and states its assumptions** (§3a); the 249-file differential is
   what makes them measured rather than assumed.
6. **`context.only` is honoured but `codeActionLiteralSupport` is not negotiated**: the server always
   answers with `CodeAction` objects, never the legacy `Command` form.  Every client this decade
   supports the literal form; no fixture exercises the other.
7. **Ticket E8 (tab-expanded parser columns) is inherited, not fixed** — a signature is REFUSED on a
   tab-indented equation (`BehindTab`) rather than inserted at the wrong column.  Zero corpus groups
   are in that class today (`core/examples/GridExample.e` is the only file with tabs).
8. **The staleness refusal is coarser than it needs to be** (§1a): the import edits would be safe on
   a stale index because they are computed from the current buffer.  One rule for the request.
9. **No `codeAction/resolve`**: every action arrives with its `edit` already on it, which is why §1c's
   memo matters.
10. **`MaxImports = 8` and the memo are constants in `QuickFix.scala`**, named and commented rather
    than tunable — there is no configuration surface in this server and this item did not open one.
11. **A re-exporter the file already imports with a `using` list is never offered** (review R-8).
    Candidates collapse to the ORIGIN (§3(a)), so with `import Prelude using isJust` in the header and
    an undefined `not`, the menu is `import Bool using not` and
    `import Relation.Predicate using not` — never `add not to the Prelude import list`, which is the
    smallest correct edit and the one a reader of that file would write.  Both offered edits apply
    and re-check clean, so nothing is broken; the origin rule buys "one candidate per definition"
    and pays for it here.  Offering a re-exporter the file ALREADY imports, in addition to the
    origins, is the obvious refinement and is not built.

## 10. Files changed

* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/QuickFix.scala` — **new**: `Published`, the
  comment masker, the import scanner (`masked`, `imports`, `scanOne`), the add-import edit
  (`addImport` and its `Skip` reasons), the group walk (`groups`, `headOf`), the signature edit
  (`render`, `mentioned`, `printedName`, `inScope`, `fieldInScope`, `freeKinds`, `starArrow`,
  `sigEdit`), the candidate rule (`candidates`), and the request handler with its memo.  FIX ROUND:
  `fieldInScope`'s exemption is the exact own-field shape (R-3), the import statement's clause is an
  `ImpList` whose three positions are total so the unreachable `SkipOpaque` state is now
  unrepresentable rather than dead (R-10), and the stale `{- -}` sentence in `imports`'s doc comment
  is gone (R-10).
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Definitions.scala` — `DocIndex` gained
  `module`, `types`, `termOrigins`, `typeOrigins`, all references to tables `index` already holds.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Diagnostics.scala` — every exit from `check`
  goes through `stored`, which records what was published with its source (`published`).
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Documents.scala` — `Doc.diags` and
  `putDiags`; the published list survives an edit the way the index does.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Main.scala` — the `codeActionProvider`
  capability and `QuickFix.install`.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Completion.scala` — `importLines` is now a
  projection of `QuickFix.imports`, so the server has ONE import scanner.
* `scalacheck-binding/src/main/scala/TestQuickFix.scala` — **new**, 18 properties (§6a).
* `scalacheck-binding/src/main/scala/TestTolerantCheck.scala` — the 6.6 sweep property, its complete
  alpha-equivalence comparator and the import-scanner differential (§5); the fix round added the
  out-of-scope sub-classification and the excluded-file list the table in §5a is built from.
* `tracker/tools/lsp-client.py` — the 6.6 block (+47 checks), the capability assertion and the
  before-boot pin.
* `tracker/lsp-tests/Fix.e`, `FixSib.e`, `FixTy.e`, `FixCrlf.e` — **new** fixtures.
* `docs/lsp.md` — the quick-fix section with both edit tables, the sweep's number, the staleness
  paragraph, the latency row, 407 → 454.
* `tracker/loopmodel/LSP3-6.6-QUICKFIX.md` — this report.

No `Subst.scala`, `Type.scala`, `Pretty.scala`, `Lower.scala`, `TolerantCheck.scala`, `Renamer.scala`
or `NewPipeline.scala` change.  No `tracker/LSP-ROADMAP.md` or `tracker/lean/` change.  No commits.
The untracked brief `tracker/loopmodel/briefs/brief-LSP3-6.7.md` was in the tree when I started and
is not mine.

STOP after this report, per the brief; a reviewer re-runs the gates and the sweep once.
