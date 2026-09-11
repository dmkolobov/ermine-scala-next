# Review: LSP Stage 4, item 7.2 — ANCHORED POSITIONS

VERDICT: **FIX-THEN-ADVANCE.**  The anchoring mechanism is sound and the cliff
numbers reproduce to the digit on both sides.  What blocks a clean tick is a
different invariant that this item's change exposes: **a top-level statement
whose text is in NO cache key — an operator definition, a backtick-quoted name,
or any name containing `_` or `'` — can now be edited with a line-count change
and leave every cacheable dependent STALE, with the diagnostic silently
dropped.**  Before 7.2 the absolute start line in every group's text masked
that.  Reproduced as a before/after differential through the real server
(R-1), blast radius 46 of 358 corpus files.  The fix is a few lines in
`TolerantCheck.keys` and costs nothing the item measured.

Reviewed at branch `scala3-migration`, HEAD `315ebed`, with the uncommitted 7.2
deliverables in the working tree.  Everything below is my own run; nothing is
inherited.

**Provenance, because the tree moved while I was finishing.**  Every number in
this report was taken against the tree exactly as the implementer left it, which
I verified two ways: `git diff --stat` 674 insertions / 95 deletions on five
files with the strict path empty, and `core/target/scala-3.3.8/classes`
byte-identical to the implementer's saved `classes-after` tree.  At **18:00:08
and 18:15:40** — after my last measurement and after Tier 2 had finished
(18:15:26; `core/test` logged no compile at all, so it ran on the classes of
record) — `surface/Anchors.scala` and `session/TolerantCheck.scala` were edited
by another hand in this working tree, and the classes were rebuilt at 18:15:49.
Those edits are a fix round already addressing R-1, R-6 and R-7 below, one of
them still carrying a `// FIX-ROUND DEMO: R-1 disabled` marker; they are not
mine, I did not touch them, and they are NOT what this review covers.  Anything
that round changes needs its own gates.

Scratch (not in the tree):
`<scratch>/review-7.2/` — `probe.py` + `scenarios.json` (the attack harness, 15
scenarios through the real server, run on BOTH class trees), `nondet.py`,
`rv-cliff.sh`, `rv-ab.sh`, and every log.

---

## 1. FINDINGS

| id | severity | status | one line |
|---|---|---|---|
| **R-1** | **HIGH** | **CONFIRMED** | 7.2 removes the accidental guard over a pre-existing hole: editing a statement that is in no cache key now leaves its dependents stale and drops their diagnostics |
| **R-2** | MEDIUM | CONFIRMED | the component-level group tags are load-bearing and completely untested — replacing them with a constant leaves all 44 properties and all 480 smoke checks green |
| **R-3** | LOW | CONFIRMED | the 154 − 115 residue is exactly accounted for, but the report's account names the smallest of its three classes and omits the one R-1 is about |
| **R-4** | LOW | CONFIRMED | finding 4(ii) reproduced and worse than recorded — FOUR different hover types for one unchanged definition in four cold checks; not 7.2's, and it wants a ticket |
| **R-5** | LOW | REFUTED (as written) | "`Pretty.scala` does not contain the string `loc`" is false (13 × `localPrec`); the substance — no position is read — is true and I re-checked it properly |
| **R-6** | LOW | CONFIRMED | `Anchors`' "the identity anchor is the common case on a cold check" is wrong: a component's anchor is never 0, so that short-circuit is dead |
| **R-7** | LOW | CONFIRMED | `tracker/tools/perf-client.py` still documents the pre-7.2 key and tells a future reader that inserting a line invalidates everything below it |
| **R-8** | LOW | CONFIRMED | attack B of the 6.2 five is tabled with a result but is the one of the five that got no property |
| **R-9** | LOW | CONFIRMED | the TYPE half of the corpus sweep is asserted on 231–248 modules, not 249; the report gives the control counts but not the denominator |
| **R-10** | note | CONFIRMED | the boot gate writes 129 `.ei` into `*/target/`, where `git status` cannot see them; the `.ei` gate must be `find`, not `git status` |

### R-1 (HIGH, CONFIRMED).  A statement in no key, edited with a line shift, leaves its dependents stale

**The mechanism.**  `TolerantCheck.keys` makes a group only where the extent
scanner can NAME one:

    bindItems.filter(_.headWord.nonEmpty).groupBy(_.headWord)

and both readers look a group up by the binding's FULL spelling —
`localFp += sp -> fingerprint("sig", sp, g.text)` for an explicit sig, and
`gs = sps.map(groups.get)` in `fpOf`.  So a top-level statement's text reaches
no key at all when either

* its **head word is empty** — `StatementExtents.wordAt` reads only letters,
  digits, `#` and `.`, so `(<+>) x y = …` and `` ``1pixel`` = … `` both scan
  with `headWord == ""` and are filtered out of `groups`; or
* its **spelling contains a character `wordAt` does not consume** (`_`, `'`):
  `foo_a` scans with head word `foo`, so `groups` is keyed by `foo` and
  `groups.get("foo_a")` MISSES.

`scopeKey` does not cover them either — it hashes the scope-word items' TEXT,
the bind items' **head words** (not their text), the module name, the imports
key and the workspace key.  And because `fpOf` returns `None` for such a
component, no fingerprint is recorded for its spellings in `localFp`, so **its
dependents get no upstream edge**.  A dependent therefore keeps its cached type
across ANY edit to it.

Before 7.2 the absolute start line inside every group's text covered the common
case: add a line to an operator's body and every group below it changed key.
That is exactly what 7.2 removed.

**The differential, through the real server** (`<scratch>/review-7.2/probe.py`,
the same scenarios run against `classes-before` — a build of `6db2c3a`'s
`TolerantCheck.scala`/`Resident.scala` with `Anchors.scala` removed, verified by
`Resident$Checked` having no `reused` field — and against the tree of record):

`Opstale.e`, a five-line module: `infixl 6 <+>`, `(<+>) x y = x + y`,
`useOp = 1 <+> 2`.  The edit rewrites the operator as two lines,
`(<+>) x y =` / `  x && y`, so `useOp` is ill-typed afterwards.

| | pre-7.2 | 7.2 |
|---|---|---|
| cold open of the EDITED text (`Opcold.e`) | error published at `useOp` | error published at `useOp` |
| the same text reached by `didChange` | reused **0 of 2**, **error published**, hover `useOp` → None | reused **1 of 2**, **diagnostics []**, hover `useOp` → `Opstale.useOp : Int` |
| the same edit with NO line change (`Opsame.e`) | reused 1 of 2, no error | reused 1 of 2, no error |

`Hword.e` is the same experiment for the truncation half — `foo_a = 1` /
`usea = foo_a + 1`, edited to `foo_a =` / `  True`: pre-7.2 the error is
published, at 7.2 it is not and hover still says `Hword.usea : Int`.

The same-line control is the part that makes the diagnosis exact: it misses on
**both** trees, so the hole is 5.5's, and what 7.2 did is widen its trigger from
"a same-line edit" to "any edit".

`private` / `database` are NOT affected, and I checked rather than assumed:
a `private` block is ONE extent with head word `private`, a scope item, so its
whole TEXT is in the scope key.  `Privy.e` with a body edit inside the block
reuses **0 of 3** and publishes the dependent's error on both trees.

**Blast radius** (lexical scan of stdlib + `core/examples`, 358 files; the
scan is in the scratch and skips comments, block comments and the
column-1 continuation lines of bracketed expressions, which a naive scan
mistakes for statements): **46 files** carry at least one top-level statement
that is in no key — **192** operator or backtick-quoted definitions and
signatures, and **157** statements whose head word is truncated by `_`/`'`.
`Layout/Report.e` itself has 16 and 35.  Signed operators are in it too: the
renamer spells `(.)` as `.`, `groups` has no such key, so `localFp` records
nothing for it either.

**Why this blocks the tick rather than just earning a ticket.**  Item 7.2's
acceptance reads "cache INVISIBILITY holds — warm == cold, byte-identical, over
the 5.5 edit set **extended with line-shifting edits**".  `Opstale.e` is a
line-shifting edit on which warm and cold disagree about a diagnostic, at 7.2
and not before it.  That condition is not met.

**The fix I recommend** (small, and it does not cost the cliff): in
`TolerantCheck.keys`, add to the scope key the text of every bind item that
cannot be reached by its own spelling — `headWord.isEmpty`, or the character
following the head word inside the extent is `_` or `'`.  Those texts are
position-free (an extent's text runs from its first significant character to
just past its last), so a pure line shift still leaves the scope key untouched
and 115 of 154 stands; what changes is that editing an operator or a
prime-suffixed definition drops the per-uri cache, which is the conservative
answer 5.5 already gives for `private`.  Plus one property per half, on the
shape of `Opstale.e`/`Hword.e` above: after the edit, `warm.notes == cold.notes`.
The principled alternative — teach `wordAt` `_` and `'` so those names become
real groups — is Tier 1 (`StatementExtents` is pinned by a 180-file
differential) and still leaves the operator/backtick half needing the scope key,
so it is the wrong trade for this item.

### R-2 (MEDIUM, CONFIRMED).  The component tags are load-bearing and untested

`fpOf` tags each group with its offset from the component's anchor:

    val tags = sps.sorted.map(sp => sp + "@" + Anchors.tag(groups(sp).anchor, anchor))

That is the only thing that stops a line inserted BETWEEN two mutually
recursive groups from being invisible to a key that must re-anchor both of them
by ONE number.  It works — `Mutrec.e`/`Mutrec2.e` (`pingx`/`qongx`, one
component, two groups, a `let` local in each) reuse **0 of 2** after a blank
line is inserted between them, and both locals answer at their own lines.

But nothing pins it.  I replaced the tag with a constant `"0"`, leaving the
statement-level tags inside each group intact, recompiled, and:

* `core/testOnly *TestTolerantCheck` — **44 properties, 0 failed**;
* the behaviour is genuinely broken: the same `Mutrec2.e` edit now reuses
  **2 of 2**, and hover on the second group's local `b` at its new line returns
  **None** (the cached entry's keys were re-anchored by a delta that is right
  for the first group and wrong for the second).  `definition` still answers,
  because it reads the current renamer — which is §4.1 being right, not the key.

The fixture `anchorBase` has no mutually recursive pair and the corpus sweep
inserts only at the TOP (where every group shifts equally), so neither can see
this.  Ask for one property: a mutually recursive pair, a line inserted between
them, `reused < fullReuse`, and the second group's local present at its new
line.  (Tree restored; `sha256sum -c` on both files, and the rebuilt classes are
byte-identical to the tree of record.)

### R-3 (LOW, CONFIRMED).  154 − 115 = 39, exactly, and in three classes

The report says "the 39 that never reuse are components whose groups the extent
scanner cannot name — operators and anything inside a `private`/`database`
block".  Right in kind, incomplete in fact.  Counting `Layout/Report.e` (the
scan is in the scratch, and it agrees with the server's `components` to the
unit):

| class | count |
|---|---|
| top-level UNSIGNED bindings whose head word IS their spelling — the cacheable ones | **119** |
| items whose head word is EMPTY: 14 backtick-quoted names (`` ``1pixel`` `` … `` ``6cell`` ``) and **2** operator definitions (`(||)`, `(***)`) | **16** |
| PRIME-SUFFIXED names, head word truncated at `'`: `atomShown'`, `borderColor'`, `drilldownBarChart'`, `drilldownPivotTabular'`, `dropdown'`, `dropdownLateBinding'`, `hspace3'`, `pad'`, `unscaled'`, `valueGrid'`, `wrappedText'` | **11** |
| unsigned bindings inside the seven `private` blocks | **13** |
| total unsigned top-level bindings | **159** |

159 bindings against the server's **154 components** means five two-binding
SCCs; 115 = 119 − 4 and 39 = 40 − 1 closes it exactly (four of the five merges
among the cacheable bindings, one among the rest).  So the residue is entirely
"a spelling `groups` cannot be looked up by", and **operators are the smallest
of its three classes** — the prime-suffixed class the report does not mention is
precisely the class R-1 is about.

The brief's two alternative hypotheses are REFUTED: no group's text contributes
an absolute line to anything (the tag is relative and an extent's text is
position-free), and the scope key hashes scope items' TEXT only, so an import or
a fixity declaration moving cannot move it.

And 57 is not the same 39: `154 − 97 = 57` on a body edit is the 39 plus **18**
components invalidated by the pinned `emptyReport` digit edit and its transitive
dependents (`perf-client.py` records that definition as referenced 14 times
elsewhere in the file).  The 39 are a subset of the 57.

### R-4 (LOW, CONFIRMED).  Two cold checks, four different published types

`<scratch>/review-7.2/nondet.py`: didOpen / hover / didClose (which calls
`Documents.drop`, so the per-uri inference cache goes and the next open is cold)
four times over an UNCHANGED `core/examples/Present/WriterOutputs.e`, one JVM.
Hover on `reportFor`:

| round | constraint part of the published type |
|---|---|
| 0 | `(exists (b: rho). a <- ((\|pTitle, pMinValue, pRegion\|), b))` |
| 1 | `(exists (b: rho). a <- ((\|pMinValue, pRegion, pTitle\|), b))` |
| 2 | `(exists (b: rho) (c: rho). a <- ((\|pTitle, pMinValue, pRegion\|), c), a <- ((\|pRegion, pTitle\|), b))` |
| 3 | `(exists (b: rho) (c: rho). a <- ((\|pTitle, pMinValue, pRegion\|), c), a <- ((\|pTitle, pMinValue\|), b))` |

Four checks, four renderings: label order moves (0 vs 1) and the simplifier
drops the redundant conjunct in 0–1 and not in 2–3.  `asDocument` moves too
(rounds 0 vs 1).  **Yes — 6.2 hover shows a different type for the same
unchanged definition across checks.**

It is not this item's: the PRE-7.2 tree gives the same four renderings in the
same order, round for round.  It is the documented solver-order sensitivity
(`Session.scala`'s own note on `-Dermine.loadInSeries`: "parallel makes draw
`Supply` ids in thread-timing order, which reaches interface bytes through the
constraint solver's id-hash queue"; PERF-ROADMAP P10's id base moving GU05 from
743 to 47,317 draws) surfacing on the editor path, where the session is
single-threaded but the `Supply` has advanced between checks.  Per
ROW-CONSTRAINT-STATE.md's complete per-label decision the variants are
entailment-equivalent, so this is a presentation bug, not a soundness one — and
it is reproducible and ordered, not flaky, which makes it testable.

**Ticket (recommended).**  *"Hover publishes a constraint set that depends on
how many ids the session has drawn."*  It should ask for: (1) the repro above as
a test — N cold checks of one module in one JVM, the published type of a named
definition required equal **as rendered**, with `WriterOutputs.reportFor` and
`Relation.e` as the named modules; (2) a decision between the two fixes — render
a CANONICAL form of the constraint set at publication (ROSE-COMPARISON.md rank 3
canonicaliser, which is where this belongs, since it also fixes the `.ei`
order-only diffs) or make the editor path's queue order independent of the id
base (`dequeuePolicy=smallcanon` already exists and ROW-CONSTRAINT-STATE.md
records it as the cheaper order); (3) it must NOT be closed by loosening a test
to alpha-equivalence — the user sees the rendering. Severity: low/medium, editor
quality.  It is also the warning 7.1b's differential needs, which the report
already says.

Four controls, each justified by a count in my own run: `ctl == c0` **16**,
`cold == c0` **1** (the implementer saw 2–3; it is itself run-dependent),
`warm == ctl` **1**, rendered local types on two cold checks **0**.  None of them
can hide a POSITION regression, which is what this item is about — those four
assertions carry no control at all and hold 249 of 249.  See R-9 for what they
do cost.

### R-5 … R-10 (LOW)

* **R-5.**  §4.2's "`Pretty.scala` does not contain the string `loc` — checked,
  not assumed" is false as written: 13 occurrences, all `localPrec`.  The claim
  that matters is true and I checked it the right way —
  `grep -E "\.loc\b|\bPos\b|Located|startLine|\.line\b|\.column\b|report\("`
  over `Pretty.scala` is empty.  Reword to that.
* **R-6.**  `Anchors.relKeys`/`absKeys` short-circuit on `anchor == 0 ||
  m.isEmpty`, and the comment says "the identity anchor is the common case on a
  cold check and costs nothing".  A component's anchor is `min startLine`, so
  ≥ 1; and both call sites are inside `fpk foreach`/the hit branch, so the
  anchor is never 0 there.  Only the `m.isEmpty` arm is live.  Delete the
  sentence or the arm.
* **R-7.**  `tracker/tools/perf-client.py:27` still says the key is
  `startLine + ":" + text`, and :36 "It must NOT CHANGE THE LINE COUNT.  Start
  lines are in every group's key, so inserting a line invalidates everything
  below it."  The bench's pinned edit is still fine, but its stated reason is now
  false, and this docstring is the thing a future item reads to learn what the
  pinned edit must avoid.  One-line fix, and it belongs in this item's commit.
* **R-8.**  Of the 6.2 review's five attacks, A, C, D and E each became a
  property; **B** ("a comment line inside a `where` block") is tabled with
  "still 0 — the group's text changed" and has none.  It is trivially true (the
  comment is inside the extent, so the text moves), but the table reads as
  measured.
* **R-9.**  A warm-vs-cold TYPE divergence is only recorded when all three
  controls agree, and the controls fired on 16 + 1 + 1 modules in my run, so the
  type half of the sweep is asserted on **231–248** of 249, not 249.  The report
  gives every control's count but not the resulting denominator; one sentence
  fixes it.  The position half has no control and is the half the item rests on.
* **R-10.**  The boot gate (`bin/ermine`, 129 modules) writes an interface beside
  every stdlib module **inside `core/target/scala-3.3.8/classes/modules/`** —
  129 files that `git status` cannot see and that a later per-file corpus run
  would READ (`ermine.useInterface` defaults true).  I deleted mine and the tree
  is back to 143 tracked `.ei` and 0 untracked.  The `.ei` gate should be
  `find . -name '*.ei' | wc -l` (272 before I cleaned, 143 after), not
  `git status`.

---

## 2. THE ANCHORING INVARIANT, ATTACKED

All of the following ran through `Resident.checkFile` on the real server, every
scenario on BOTH class trees (`<scratch>/review-7.2/probe.py`, logs beside it).
`reuse` is the server's own `reused of components` pair, before the edit / after.

| the brief's case | what I built | 7.2 | verdict |
|---|---|---|---|
| (a) byte-identical BODIES, different heads | the suite's own `seven`/`eight` property, re-run; it FALSIFIES under the `absPos` sabotage, so it is not vacuous | keys hold the head spelling twice — it is the first token of every statement in the group text, and again in the component tag `spelling@offset` | **sound** |
| (a') two groups with identical HEADS | impossible as two groups: `groupBy(_.headWord)` puts them in ONE group whose text carries both statements AND their relative offsets | conservative, not a collision | **confirmed** — but see R-1 for the case where it merges two DIFFERENT spellings |
| (b) two mutually recursive groups, a line inserted BETWEEN them | `Mutrec.e` / `Mutrec2.e` | reuse **0/2 → 0/2**: the component MISSES, as it must; `a` stays at its line, `b` moves by one, both hovers answer | **sound**, and shown to be the tags' doing — R-2 |
| (c) a group whose first line is a comment | `Cmt.e`, a comment inserted directly above the group | reuse 0/2 → **2/2**, `cv`'s def-site +1.  The anchor is the HEAD TOKEN's line: `scan` does `skipWs()` before each item, so no comment or blank is ever inside an extent — the same frame `collectLocals` records (`b.v.loc`, the parser's binder `Pos`) | **sound** |
| (d) a def-site at Δ = 0 and on the group's last line | `Edge.e`: `headLocal x = (let h = x in h)` and a three-line `multiL` whose local is on its last line; 3 blank lines at the top | reuse 0/3 → **3/3**; `h` 4→7, `m` 7→10, columns untouched | **sound** |
| (e) a `where` local on a continuation line | `Wcont.e`, `keep` three lines below the anchor, 2 lines inserted | reuse 0/2 → **2/2**, `keep` 7→9 | **sound** |
| (f) CRLF | `EdgeCrlf.e`, the `Edge.e` fixture with `\r\n` | identical to LF cell for cell | **sound** — line arithmetic only, as claimed.  `Anchor.e` is LF, so no anchored CRLF pin exists; the risk is covered by `FixCrlf.e` elsewhere, and one anchored CRLF check would be cheap insurance |
| (g) the same head word inside `private` AND at top level | `Privy.e` | the renamer is never consulted: `keys` cannot see inside a `private` block (one extent, head word `private`, a scope item), so a private binding is in no group, its component is never cached, and an edit to it drops the WHOLE cache through the scope key — reuse 0/3, the dependent's error published | **sound** |
| the statement tags inside one group | `Eqgap.e`, a blank line between two equations of one group; `Siggap.e`, a blank line between a signature and its equation | both **MISS** (0/2, 0/1); the sig fingerprint is `fingerprint("sig", sp, g.text)` and the tags are inside `g.text` | **sound** |
| the control | `Ctl.e`, a pure top insertion | reuse 0/3 → **3/3** | **sound** |

**Reading of the invariant.**  The three-part argument at `Entry` holds as
stated, and its parts are in the right place: (1) the key pins every group's
text and every line offset inside the component — statement-to-group and
group-to-component — so the only freedom a hit leaves is the anchor; (2) a
top-level statement starts at column 1 by the header parse, and its own text
fixes every column inside it, so `relPos`/`absPos` never touching a column is
not a choice but a theorem; (3) one number is added at lookup.  Storing
RELATIVE rather than "absolute plus the old anchor" is the right call for the
reason given — `Definitions.index` reads `locals` two call layers from the
cache, and a relative map cannot be consumed without passing through
`absKeys`.

## 3. NO CACHED POSITION ESCAPES

Read, not assumed.  `c.locals` has exactly three readers —
`Definitions.scala:541` (hover on a local), `:693` (the local def-occurrence set
behind references / highlight / rename) and `Completion.scala:259` (completion
detail) — and all three use the CURRENT renamer's `b.defSite` / `d` as the
lookup KEY and take the reply's position from that same current value.  A stale
key can therefore only make a lookup miss (hover answers null) or hit a
different binder; it cannot move a position in a reply.  `Pretty` reads no
position at all (R-5).  `publishDiagnostics` positions come from the blame
`Located` of a component being checked now, and note-bearing components are
never cached.  §4.1's table is accurate.

**The named residue is real and I did not refute it.**  `Subst.occursFail` is
`e.die(…)` on the offending TYPE, so a cached type's `Loc` becomes that note's
own position; and `unifyType` renders a type's position into a message body in
four branches (`e2.report(e2.toString)` twice for constraints and arity,
`q.report`/`p.report` in the two `Exists` panics).  Pre-7.2 a hit required
identical absolute lines, so it could not be stale; now it can.  It needs one
edit that BOTH shifts lines and introduces an error of that class; the property
"a shift AND a new error together stay byte-identical" is exactly that case and
passes, and the 249-module note comparison is 0 differences.  **PLAUSIBLE,
unobserved** — and correctly recorded as the one place a future failure comes
from.  The rejected fix (a loc-rewriting traversal of `Type`) would be Tier 1;
not making it was right.

**Sabotage, mine.**  `Anchors.absPos` with `p._1 + anchor + 1`, recompiled:

* `lsp-smoke` → **3 of 480 fail, and exactly the three the report names**:
  `hover last local at its NEW line` (the existing 6.2 pin),
  `7.2 hover on a WHERE local survives a line shift`, and
  `7.2 hover on a LET local of an UNSIGNED binding survives a line shift`.
  The other 21 new checks pass — the routes they cover read the current run's
  tables, exactly as §4.3 says, so they are regression pins and not
  re-anchoring pins.  That is honest in the report and it is true.
* `core/testOnly *TestTolerantCheck` → **16 of 44 properties falsified**: the
  corpus sweep, all eleven drift attacks, three of the 5.5 invisibility
  properties, and `7.2 Anchors: a keyed map round-trips`.  The property suite is
  where the non-vacuity actually lives, and it is strong.

Both sabotages were reverted and verified by `sha256sum -c`; the rebuilt
`core/.../classes` tree is byte-identical to the tree of record.

## 4. THE CLIFF, RE-MEASURED

One JVM per side, `-Dermine.lsp.phases=true`, `Layout/Report.e` (1757 lines),
the pinned digit edit at line 281, the middle insertion one blank line at 884.
`checkWith` milliseconds from the server's own phases line.

| scenario | implementer before | **my before** | implementer after | **my after** | **my Δ** |
|---|---|---|---|---|---|
| `didOpen` (cold) | 1123 / 1166 ms, 0/154 | **1102 ms, 0/154** | 1165 / 1150 ms, 0/154 | **1152 ms, 0/154** | ≈ 0 |
| in-body edit (reference) | 506–552 ms, 97/154 | **506–595 ms, 97/154** | 517–575 ms, 97/154 | **499–600 ms, 97/154** | ≈ 0 |
| **TOP-INSERT, pure** | **1001 / 1048 ms, 0/154** | **1032 ms, 0/154** | **489 / 427 ms, 115/154** | **425 ms, 115/154** | **−607 ms, −59 %** |
| **TOP-DELETE, pure** | **984 / 1178 ms, 0/154** | **1038 ms, 0/154** | **429 / 419 ms, 115/154** | **415 ms, 115/154** | **−623 ms, −60 %** |
| **MID-INSERT, pure** | **712 / 781 ms, 83/154** | **759 ms, 83/154** | **424 / 433 ms, 115/154** | **454 ms, 115/154** | **−305 ms, −40 %** |
| **TOP-INSERT + body edit** | **1023 / 1090 ms, 0/154** | **1168 ms, 0/154** | **578 / 572 ms, 97/154** | **548 ms, 97/154** | **−620 ms, −53 %** |

Every reuse count reproduces to the unit on both sides, and every `checkWith`
median is inside the implementer's two-pass spread.  The roadmap's target
("typecheck 1.07 s → ~0.5 s on a top-of-file insertion") is met: **1.03 s →
0.43 s**.  A top-of-file insertion is now cheaper than an in-body edit, for the
stated reason — it invalidates nothing, where a body edit invalidates one group
and its dependents.  Read time is unchanged throughout (0.84–1.17 s on both
sides).

**The steady-state A/B, one interleaved pair, mine.**  `perf-client.py --rounds
15`, round 1 discarded, median of 14, before then after, load 1.03 / 1.61:

| | before | after | Δ |
|---|---|---|---|
| round trip median | **1.822 s** | **1.828 s** | **+6 ms (+0.3 %)** |
| read | 0.950 | 0.950 | 0 |
| typecheck | 0.540 | 0.545 | +5 ms |
| spread | 1.732–2.192 | 1.760–2.156 | straddling |
| cold `didOpen` | 2.415 | 2.375 | −40 ms |
| boot | 13.32 | 13.34 | +20 ms |
| reused | 97/154 | 97/154 | — |

The implementer measured −1.5 ms, I measure +6 ms; both are a fraction of the
harness's own between-run spread and the two orderings disagree on the sign.
**The steady state is unmoved**, which is the claim.  Well inside the 5 % / 80 ms
budget.  The batch half of Tier 2's perf gate is not owed: `TolerantCheck.keys`
and `checkWith` have exactly one non-test caller, `lsp/Resident.scala`, and the
strict-path diff is empty, so batch semantics cannot have moved.

## 5. THE COMPARATOR MOVE

Nothing about alpha-equivalence changed.  `aeq` and `multi` in `AlphaEq.scala`
are byte-identical to the versions inside the 6.6 sweep at `6db2c3a` — I
extracted both, normalised whitespace and diffed: the only difference is the new
object's closing brace.  `AlphaEq.strict` is
`G1Compare.alphaEq(a, b, Bij.empty).isDefined` verbatim, `loose` is
`aeq(a, b, empty).nonEmpty`, and the 6.6 sweep's `sameTy` still computes
`strict`, then `strict || AlphaEq.loose(a, b)`, counts `loose && !strict` into
`g1Only` and returns `loose` — the same two calls in the same order, so
`AlphaEq.same`'s short-circuit is the same function.  I did not re-run the
quarantined 6.6 quick-fix sweep (GATE-POLICY quarantines it; the implementer ran
it: 1/1 green, 87 s, "pairs equal only under the COMPLETE comparator: 5").
Moving it to a new FILE rather than up one scope is also what keeps
`git diff --stat -w` meaningful — see the gate table.

## 6. GATES (my runs, Tier 0 + the seven suites + Tier 2)

| gate | required | **my result** |
|---|---|---|
| `sbt core/compile core/copyResources` | green | **green** (no-op on arrival; green again after both sabotage reverts) |
| `core/testOnly *TestLoopTrace` | 720/720 | **720 solves, 720 segments, 720 agree, skipped 0, hashdiff 0, eqdiff 0, nonpart 0, fuel 0; 3/3 properties**; controls non-vacuous (id base +1: 46/720 disagree; `--flags=nongen`: 58/720) |
| the seven targeted suites | green | **156 properties, 0 failed, 0 errors**, 308 s — Tolerant check **44**, Ermine stage1 pins 34, Renamer 3 × 32, Lower 3 × 28, Tolerant read 11, Editor buffers 5 × 6, REPL eval goldens 1 |
| 7.2's corpus sweep (inside it) | new | **249 clean of 253; 123 of 137 modules with components reused after a top-of-file insertion, 1157 of 1334 components; mismatches 0**; controls `ctl` 16, cold 1, warm 1, local types 0 |
| 6.2's 253-file local sweep (inside it) | unchanged | **249 clean of 253; Arg(equation) 2872/2872, LetBound 156/156, WhereBound 89/89; required-class misses 0** |
| `corpus-run.sh --batch` | 85 / 69 / 0 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** (one JVM, exit 0, 41 s) |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups, 66 checks, all PASS**; `git status tracker/repl-tests/` EMPTY — goldens byte-unmodified |
| `lsp-smoke.sh` | 456 + 24 | **480 checks, PASS** (47 s); the 24 new ones are the `7.2 …` block, listed in the scratch |
| boot | 129 modules | **129 modules in 12.85 s** |
| `.ei` droppings | 0 | **0** — 143 tracked, 143 on disk after I deleted the 129 the boot gate wrote into `*/target/` (R-10) |
| strict path untouched | empty diff | `git diff -- session/Session.scala rename/NewPipeline.scala` **EMPTY** |
| `git diff --stat` vs `--stat -w` | identical | **identical under `--histogram`: 674 insertions / 95 deletions both ways.**  Under the default Myers, `-w` reports one MORE of each — the direction that cannot hide a reindentation.  Line audit: the only changed lines equal after stripping all whitespace are bare `}` (5 removed, 14 added) |
| CRLF preserved | yes | every touched file is LF before and after (`grep -c $'\r'` = 0 on all nine) |
| **Tier 2: `sbt -batch -J-Xmx3g core/test` ALONE** | 988 + 17 ≈ 1005 | **1005 properties, Failed 0, Errors 0**, 1569 s (26:09), one JVM, nothing else on the tree.  Exactly the predicted total.  Its own 7.2 sweep printed `mismatches 0` with controls 16 / **3** / 1 / 0 — the cold-check control is the only count that moves between runs (1 in my suite run, 3 here, 2–3 in the implementer's), which is finding 4(ii) being itself nondeterministic |

Tier 1 is not owed: nothing under `parsers/`, `Subst.scala` or `Type.scala` was
touched, and the one change that would have needed it (a loc-rewriting traversal
of `Type`) was deliberately not made.

## 7. THE REPORT ITSELF

663 lines, and accurate against my numbers with the exceptions above — every
cliff figure, every reuse count, every gate count and the sabotage's three
failing checks reproduce.  It is also unusually honest in two places that a
weaker report would have smoothed: the sabotage section says plainly that the
pins which bite are only the ones on locals of UNSIGNED bindings, and §3.1
records the control sequence (25 → 9 → 2 → 0 modules) rather than presenting the
final number alone.  Against the roadmap item's tick conditions:

| condition | status |
|---|---|
| before/after reuse count for a one-line top insertion on Report.e, MEASURED both sides | **met** — 0/154 → 115/154, reproduced |
| Stage-3 Decision (b) restated and re-attacked, the 6.2 reviewer's five attacks re-run | **met**, with R-8 (attack B has no pin) |
| cache INVISIBILITY over the 5.5 edit set extended with line-shifting edits | **NOT met** — R-1 |
| every escaping `Loc` re-anchored, enumerated, lsp-smoke fixture per route after a line-shifting `didChange` | **met**, non-vacuity established (and re-established by me) |
| 6.2's `locals` keys specifically pinned | **met** |
| Tier 0 + the seven suites; Tier 2 at adoption | **met** (this review) |

For the orchestrator, unchanged from the implementer's note: `LSP-ROADMAP.md`
still needs the Baselines lsp-smoke count 456 → **480** and item 7.2's tick, and
the tick should not record the invisibility condition as met until R-1 is
answered.  `docs/lsp.md` is already updated here (it was stale at 454).

---

## 8. VERDICT

**FIX-THEN-ADVANCE.**  The item does what it set out to do and the numbers are
real: a top-of-file insertion goes from reusing nothing to reusing more than an
in-body edit (115 of 154 against 97), `checkWith` **1.03 s → 0.43 s (−59 %)**, a
top deletion **1.04 s → 0.42 s (−60 %)**, a middle insertion **0.76 s → 0.45 s
(−40 %)**, the steady state unmoved (**+6 ms**, interleaved), and the anchoring
itself survives every attack in the brief — mutual recursion between two groups,
a comment above a group, Δ = 0 and last-line def-sites, a continuation-line
`where` local, CRLF, and the private/top-level head-word collision.

Before the tick:

1. **R-1 (required).**  Put the text of every top-level bind item that cannot be
   reached by its own spelling — empty head word, or a head word truncated by
   `_`/`'` — into the scope key, and add one property per half on the shape of
   `Opstale.e`/`Hword.e`.  Without it, an editor that used to report a type
   error when you split an operator's body across two lines now reports nothing,
   on 46 of 358 corpus files' worth of exposure, and the item's own invisibility
   condition is false.
2. **R-2 (required, cheap).**  One property for the component tags: a mutually
   recursive pair with a line inserted between them.  Today replacing those tags
   with a constant leaves 44 of 44 properties and 480 of 480 smoke checks green
   while breaking hover on the second group's locals.
3. **R-3, R-5, R-6, R-7, R-8, R-9 (editorial, same commit).**  Correct the
   residue's composition, the `Pretty` claim, the dead `anchor == 0` comment, the
   stale `perf-client.py` docstring, attack B's status, and the sweep's type
   denominator.
4. **R-4** is not this item's: open the ticket in §1 and cross-reference it from
   `ROW-CONSTRAINT-STATE.md`, as the report already proposes.

A fix round addressing items 1, 3 (part) and the R-6/R-7 editorials was already
in this working tree when I finished (see the provenance note at the top).  I
have not reviewed it and none of my numbers come from it: it needs Tier 0, the
seven suites and — because it changes what `keys` puts in the scope key, which is
shipped editor behaviour — an interleaved editor A/B and a fresh cliff
measurement, since every module with an unreachable top-level item now drops its
whole cache when that item is edited.  The 115 of 154 figure is unaffected by the
fix in principle (the added texts are position-free), but it should be
re-measured rather than argued.

STOPPED after this report.
