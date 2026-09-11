# LSP Stage 4, item 7.2 — ANCHORED POSITIONS: the inference cache survives an edit that shifts lines

OUTCOME: **GREEN**, after a FIX ROUND against the independent review
(`tracker/loopmodel/LSP4-7.2-REVIEW.md`, verdict FIX-THEN-ADVANCE).

> ### FIX ROUND — what changed after the review
>
> | id | severity | disposition |
> |---|---|---|
> | **R-1** | HIGH | **FIXED IN CODE, and the hole is now pinned by two properties that FAIL on the pre-fix tree.**  A top-level bind item whose own spelling cannot look its group up — an operator, a backtick name, any spelling containing `_` or `'` — reached NO cache key, so editing one left every cacheable dependent holding a stale type with its diagnostic silently dropped.  7.2 is what made that edit invisible: the absolute start line in every group's text had been masking it.  `keys` now puts such an item's TEXT in the SCOPE key.  §2.5. |
> | **R-2** | MEDIUM | **PINNED.**  The component tags were load-bearing and untested — the reviewer replaced them with a constant and 44/44 properties plus 480/480 smoke checks stayed green while hover on a mutually recursive pair's second local broke.  One property now fails instead; non-vacuity re-measured here with the same sabotage.  §3, “the fix round's three properties”. |
> | **F-1** | MEDIUM | **FOUND WHILE PINNING R-2, AND FIXED.**  A component's fingerprint sorted its group TAGS but took its group TEXTS in `comp` order — an SCC traversal order over id-keyed maps, not stable between runs — so a component with TWO OR MORE groups could fingerprint differently each time and then never be reused at all.  Measured: the R-2 fixture reused **4 of 5** components on an UNCHANGED re-run, the one that never hit being the mutually recursive pair, which made R-2's property unable to fail.  Sorting the texts with the tags fixes it (**4 of 5 → 5 of 5**) and makes the key a function of the text, which is what it always claimed to be.  Pre-dates 7.2.  §2.6. |
> | **R-3** | LOW | **CORRECTED.**  The residue 154 − 115 = 39 is in THREE classes, and operators are the smallest of them; the prime-suffixed class is precisely what R-1 is about.  §1. |
> | **R-4** | LOW | NOT this item's — the orchestrator files the row-constraint-nondeterminism ticket.  §3.1(ii) already carries the mechanism, and the reviewer's four-renderings-in-one-JVM repro is stronger than this report's; §3.1 now points at it. |
> | **R-5** | LOW | **CORRECTED.**  "`Pretty.scala` does not contain the string `loc`" was false (13 occurrences, all `localPrec`).  Re-verified the right way.  §4.2. |
> | **R-6** | LOW | **FIXED IN CODE.**  `Anchors.relKeys`/`absKeys`' `anchor == 0` arm is dead (an anchor is a 1-based line, and both call sites are inside the branch where a fingerprint exists); deleted, with the reason in its place. |
> | **R-7** | LOW | **FIXED.**  `tracker/tools/perf-client.py`'s docstring still told a future item that start lines are in every group's key and that an operator is simply never cached.  Both rewritten, the second to the post-R-1 rule. |
> | **R-8** | LOW | **CORRECTED.**  Attack B is marked DERIVED, not measured. |
> | **R-9** | LOW | **ADDED.**  The type half of the corpus sweep is asserted on 231–248 of 249, not 249; the position half has no control. |
> | **R-10** | LOW | **ADOPTED.**  The `.ei` gate is now `find . -name '*.ei' \| wc -l`, not `git status`: the boot gate writes 129 interfaces under `core/target/.../classes/modules/` that `git status` cannot see. |

Branch `scala3-migration`, from `6db2c3a` (7.0 committed).  Tier 0 + the seven
targeted suites.  No commit, no default flip, no strict-path change, no change
to batch semantics, no request-path work.

Item of record: `tracker/LSP-ROADMAP.md` § Stage 4, item **7.2**, with the
STAGE-4 INVARIANTS and Decisions (a)(b).  Measured premise:
`tracker/loopmodel/LSP4-7.0-READ.md` §7.  Gates: `tracker/GATE-POLICY.md`.

---

## 1. THE CLIFF, MEASURED FIRST (7.2.1)

`<scratch>/7.2/cliff2.py`, an extension of 7.0's `cliff.py`: one server, one
JVM, the `phases` property on, `Layout/Report.e` (1757 lines), the pinned
in-body digit edit at line 281, and the four line-shifting steps the item asks
for.  A "pure" step changes NOTHING but the line count — the body digit is held
fixed — so it isolates the shift from the edit.  The middle insertion is one
blank line at line 884, between `zipSelector`'s last equation and
`selectorFunctor`: it moves every group below it and no group above it.

BEFORE (load 0.65 at start) beside AFTER (load 1.31):

| step | reused BEFORE | `checkWith` BEFORE | reused AFTER | `checkWith` AFTER |
|---|---|---|---|---|
| `didOpen` (cold) | 0 of 154 | 1123 ms | 0 of 154 | 1165 ms |
| in-body edit ×3 | 97 of 154 | 506–552 ms | 97 of 154 | 517–575 ms |
| **TOP-INSERT + body edit** (7.0's cliff round) | **0 of 154** | **1023 ms** | **97 of 154** | **578 ms** |
| in-body, shifted | 97 of 154 | 548 ms | 97 of 154 | 639 ms |
| **TOP-INSERT, pure** (no body edit) | **0 of 154** | **1001 ms** | **115 of 154** | **489 ms** |
| in-body, shifted | 97 of 154 | 534 ms | 97 of 154 | 515 ms |
| **TOP-DELETE, pure** | **0 of 154** | **984 ms** | **115 of 154** | **429 ms** |
| in-body, shifted | 97 of 154 | 547 ms | 97 of 154 | 528 ms |
| **MID-INSERT, pure** (before some groups, after others) | **83 of 154** | **712 ms** | **115 of 154** | **424 ms** |
| in-body, after the mid insert | 97 of 154 | 502 ms | 97 of 154 | 490 ms |

Read time is unchanged throughout (0.86–1.14 s on both sides); the cliff is
entirely in `checkWith`.

Three things the before-column adds to 7.0's §7, which had measured only the
first of them:

* a **DELETION** at the top costs the same as an insertion — **0 of 154** — so
  this is not an "insert" bug, it is "any change to the line numbering";
* a **MIDDLE** insertion is a PARTIAL cliff, **83 of 154**: the groups above it
  keep their keys and every group below it loses its own.  That is the shape the
  code predicts, and it is the common case in real editing — nobody types at the
  top of a file, everybody types in the middle of one;
* **115 of 154** is the ceiling for a pure shift (97 when a body is edited too,
  because the edited group and its dependents must re-check).

**THE RESIDUE, 154 − 115 = 39, in three classes** (review R-3 corrected this
report's first answer, which named only operators and `private` blocks).  Over
`Layout/Report.e`'s **159 unsigned top-level bindings**:

| class | count |
|---|---|
| head word IS the spelling — the cacheable ones | **119** |
| head word EMPTY: 14 backtick-quoted names (`` `1pixel` `` …) + 2 operator definitions (`(\|\|)`, `(***)`) | **16** |
| head word TRUNCATED at `'`: `atomShown'`, `pad'`, `unscaled'`, `valueGrid'` … | **11** |
| unsigned bindings inside the seven `private` blocks | **13** |

159 bindings against 154 components is five two-binding SCCs, and
115 = 119 − 4, 39 = 40 − 1 closes it exactly.  **So the residue is entirely "a
spelling `groups` cannot be looked up by", and the prime-suffixed class — the
one this report first failed to mention — is precisely what review R-1 is
about** (§2.5).  `154 − 97 = 57` on a body edit is a different number: the 39
plus 18 components the pinned `emptyReport` digit edit invalidates transitively.

**The small file** (`Layout/Color.e`, 84 lines, 6 components, edit on line 45,
mid insert at 46): BEFORE 1 of 6 steady state, **0 of 6** on every one of the
three pure shifts and on the shift+body round; AFTER **1 of 6** on all of them.
The reuse cliff is there at every size; the TIME is not — the whole check is
8–13 ms and the 300 ms debounce is 90 % of the round trip, exactly as 7.0 §3
found.  (1 of 6 is the steady-state ceiling here: `Color.e` is five `private`/
`foreign` blocks and one cacheable group.)

---

## 2. THE FIX (7.2.2)

### 2.1 The key, in three sentences

The group key is now the group's own text with each statement tagged by its
offset from the GROUP's first line, the component key is those group texts plus
each group's offset from the COMPONENT's first line, and no absolute line
appears in either.  `Entry.locals` stores each local binder's def-site as
`(line − the component's anchor, column)`, and a cache hit adds the anchor the
component has in the buffer as it is NOW, so the positions a hit hands back are
the current buffer's.  All of that arithmetic — relative, absolute, a
`(line, col)` pair, a whole `Span` — is in one new object,
`surface/Anchors.scala`, which 7.1b reuses for the spans a spliced statement
carries.

### 2.2 Why RELATIVE and not "the absolute map plus the line it was recorded at"

The brief allows either.  Relative was chosen because it makes the
ILLEGAL STATE UNREPRESENTABLE IN THE VALUE: an entry that stores absolute
positions plus its old anchor is correct only if every reader remembers to
subtract, and `Definitions.index` reads `locals` straight out of `Checked`
two call layers away from the cache.  Stored relative, an entry cannot be
consumed without passing through `Anchors.absKeys`, because the numbers in it
are visibly not line numbers (they start at 0 and may be negative).  It also
costs less: one map rebuild per reused component at lookup either way, but no
second field to keep consistent, and `relKeys`/`absKeys` short-circuit at
anchor 0.

### 2.3 Why the offsets are in the KEY

This is the part the naive "drop the start line" version gets wrong.  A group
is a head word's statements — a signature and its equations — and a component
can hold SEVERAL groups (a mutually recursive pair).  Dropping the line
entirely would make these two buffers equal:

    three : Int          three : Int
    three = two          <blank>
                         three = two

Both have the same group text; the equation has moved.  So each statement goes
into the text tagged with its offset from the group's first line, and each
group goes into the component's fingerprint tagged with its offset from the
component's anchor.  The key therefore pins the component's whole internal
GEOMETRY, and the only thing a hit leaves undetermined is the anchor — one
number, which is what gets added back.  An explicit signature's own position is
deliberately NOT in its fingerprint: where an upstream annotation sits cannot
move a dependent's binders, and putting it in would re-create the cliff one
level up.

### 2.4 The drift invariant, restated

> A reused entry's positions are correct because (1) a hit means the
> component's text and its internal line geometry are byte-for-byte what they
> were, (2) no column can have moved — a top-level statement starts at column 1
> (a PARSER guarantee: an indented top-level statement is rejected by the
> header parse, 6.2 review R-7) and its own text fixes every column inside it,
> and (3) what remains is one number, the anchor, which `Anchors` adds at
> lookup.

It is written at `Entry` in the code in those three parts, where the old
argument was.

### 2.5 THE FIX ROUND (review R-1): the item in NO key, and the staleness it hid

The invariant above is about an entry that IS keyed.  The review found the
complement, and it is the one thing this item got wrong.

**The hole.**  `keys` could only make a group where the extent scanner can NAME
one, and both readers look a group up by the binding's FULL SPELLING.  The
scanner's head word is the run of letters, digits, `#` and `.` at the
statement's first significant character; the spelling is the run of
`Lexer.tailChar`s there — letters, digits, `_`, `#`, `'`.  They disagree in
three ways, and in each the statement's text reached **no key at all**:

* **head word EMPTY** — `(<+>) x y = …`, `` `1pixel` = … ``;
* **head word TRUNCATED** — `foo_a` scans as `foo`, `unscaled'` as `unscaled`;
* head word LONGER than the spelling, because `wordAt` eats a `.`.

Neither its own key nor its dependents': `fpOf` returns `None` for such a
component, so nothing records an upstream edge for it, and a cacheable dependent
keeps its cached type across ANY edit to it.

**Why 7.2 made it matter.**  Before 7.2 the absolute start line inside every
group's text covered the common case: add a line to an operator's body and every
group below it changed key.  That is exactly what this item removed.  The
review's differential through the real server makes it concrete — `Opstale.e`
(`infixl 6 <+>`, `(<+>) x y = x + y`, `useOp = 1 <+> 2`, the operator rewritten
over two lines so `useOp` becomes ill-typed):

| | pre-7.2 | 7.2 before the fix round |
|---|---|---|
| the edited text reached by `didChange` | reused 0 of 2, **error published** | reused 1 of 2, **diagnostics `[]`**, hover still `useOp : Int` |
| the same edit with NO line change | reused 1 of 2, no error | reused 1 of 2, no error |

The same-line control is what makes the diagnosis exact: it misses on BOTH
trees, so the hole is 5.5's, and what 7.2 did was widen its trigger from "a
same-line edit" to "any edit".  **Blast radius: 111 of 358 corpus files** carry
at least one such statement (668 empty-head items, 157 truncated);
`Layout/Report.e` has 16 and 11.  `private`/`database` are NOT affected and the
reviewer checked rather than assumed: a `private` block is one extent with head
word `private`, a scope item, so its whole text is already in the scope key.

**THE RULE AS IMPLEMENTED.**  Not "does the spelling contain an odd character"
but the direct question, which covers all three cases and stays right if either
character set changes:

> A bind item is REACHABLE iff its head word is non-empty AND **the head word is
> the WHOLE identifier lexeme** at the statement's first significant character.
> `keys` partitions `bindItems` on that; the reachable ones become `groups` as
> before, and **the TEXT of every unreachable one goes into the SCOPE key**.

So any edit to an operator, a backtick name or a `_`/`'` spelling drops the
whole per-uri cache — conservative and correct, the answer 5.5 already gives for
a `private` block — while a pure line shift still changes nothing, because an
extent's text is position-free.  **The cliff is untouched: 115 of 154 stands**
(§7.3).

**THE THIRD CASE DOES NOT OCCUR TODAY, and that is why the rule is phrased this
way and not as the review's two-character test.**  A lexical cross-check over the
253-file corpus (scratch, `python3`, approximating the scanner on column-1
statement starts) finds **659 empty-head items in 92 files** and **157 truncated
by `_`/`'` in 27 files** — the truncated count agrees with the reviewer's 157 to
the unit, and the empty-head count is lower than their 668 only because they
scanned 358 files including `shouldfail/` and `incomplete/`.  It also finds five
apparent `.`-case items, and **all five are continuation lines inside `{- -}`
block comments** (`Random.e:7`, `OptionTypes.e:10,14,17`, `Column/Unsafe.e:4`) —
my approximation's artifacts, not statements.  So the real count of the third
case is **0**: the rule costs nothing to cover it and stays correct if `wordAt`
or `Lexer.tailChar` ever changes, which a two-character test would not.

The principled alternative — teach `StatementExtents.wordAt` about `_` and `'`
so those names become real groups — is **Tier 1** (`StatementExtents` is pinned
by a 180-file differential) and would still leave the operator and backtick half
needing the scope key, so it is the wrong trade for this item.  It belongs with
7.1b, which has to re-visit the extent scanner anyway.

### 2.6 F-1: the component key was not a function of the text (found while pinning R-2)

`fpOf` built its fingerprint as `"scc" :: tags ::: gs.flatten.map(_.text) ::: upstream`,
where `tags` was `sps.sorted.map(...)` and `gs` was `sps.map(groups.get)` —
**sorted for the tags, `comp` order for the texts.**  `comp` is a component as
`implicitBindingComponents` produced it, an SCC traversal over id-keyed maps, and
its order is not stable between runs.  For a ONE-group component that is
invisible; for a component with two or more, the key moved for no reason and the
entry could never be hit.

It surfaced because review R-2's property could not fail: a mutually recursive
pair is exactly a two-group component, and the fixture reused **4 of 5**
components on an UNCHANGED re-run — the one that never hit being the pair.  A
property that asserts "the pair MISSES after an edit" proves nothing when the
pair never hits.

The fix is one expression: build the key from `sps.sorted`, carrying each
group's tag AND its text together, so the whole thing is a function of the
(sorted) spellings, their offsets and their texts.  Measured immediately:
**full reuse on the R-2 fixture went 4 of 5 to 5 of 5**, and the property then
behaves as intended — 4 of 5 after a line is inserted between the two groups.

It PRE-DATES 7.2 (the same mismatch is in `6db2c3a`), it is a reuse loss rather
than a correctness bug, and it is small — `Layout/Report.e`'s five two-binding
SCCs are 5 of 154 components, and the corpus sweep's totals did not move
(1157 of 1334 both before and after).  It is recorded here rather than deferred
because without it this item could not honour R-2.

---

## 3. THE DRIFT ATTACKS (7.2.3)

All of these are PROPERTIES in `TestTolerantCheck`, not a transcript: each
checks `before`, then `after` twice — warm against the cache `before` left, and
cold — and requires byte-identical notes, byte-identical rendered types,
byte-identical `locals` (positions AND rendered types), and the actual def-site
(line, column) of every `let` binder in the edited text, computed from the TEXT
rather than from the check.  The fixture carries two definitions whose bodies
are byte-identical apart from the head name, so the duplicate attack is not
vacuous.

`fullReuse` below is the reuse count of a re-run over UNCHANGED text — the
number a pure shift has to match.

### The five attacks of the 6.2 review (R-7), re-run against the anchored form

| # | attack | 6.2 (start lines in the key) | 7.2 (anchored) | warm == cold |
|---|---|---|---|---|
| A | trailing whitespace after a statement | reused | **reused** | yes |
| B | a comment line inside a `where` block | 0 reused (text changed) | **still 0** — DERIVED, not measured: the comment sits INSIDE the extent, so the group's text moves and the key cannot match.  It is the only one of the five with no property of its own (review R-8) | — |
| C | a comment line BETWEEN two statements | partial: above kept, below re-checked | **`fullReuse` — everything kept** | yes |
| D | a blank line above everything | 0 reused | **`fullReuse`** | yes |
| E | one space before a head-line `let` binder | 0 reused | **still 0** — the text changed, so the COLUMN change is caught | yes |

B and E are the two that must still MISS, and they do, for the reason they
always did: the group's text changed.  That is what keeps the "no column ever
moves" half of the invariant true — 7.2 never shifts a column, and the only
edits that move one change the text.

C and D are the cliff: C went from partial to total reuse, D from nothing to
everything.

### The line-shifting attacks this item exists for

| attack | result | property |
|---|---|---|
| one line inserted at the TOP | `fullReuse`, def-sites + 1 | "a line inserted at the TOP keeps every entry, re-anchored" |
| one line DELETED at the top | `fullReuse`, def-sites − 1 | "a line DELETED at the top keeps every entry, re-anchored" |
| TEN lines inserted at the top | `fullReuse`, def-sites + 10 | "ten lines inserted at the top keep every entry" |
| a blank line inserted BETWEEN two definitions | `fullReuse` | "a line inserted BETWEEN two definitions keeps every entry" |
| a COMMENT line inserted between two definitions | `fullReuse` | "a comment line inserted between two definitions keeps every entry" |
| a line inserted INSIDE a definition | `0 < reused < fullReuse` — that group MISSES, its neighbours keep | "a line inserted INSIDE a definition invalidates THAT definition only" |
| a whole group MOVED past another (re-ordered) | `fullReuse`, and each one's local lands on its NEW line | "a group MOVED past another still hits, at its new lines" |
| a shift AND a new type error in one edit | warm notes == cold notes, byte for byte | "a shift AND a new error together stay byte-identical" |

### The duplicate-group attack, and the rule

**Two groups in one file can never have the same key, and the reason is not an
ordinal — it is the head word.**  A "group" IS a top-level spelling, so two
groups have two different spellings by construction; the spelling is in the
group's text (it is the first token of every statement in it) and again in the
component's fingerprint as the tag `spelling@offset`.  Duplicating a definition
verbatim does not create a second group: both statements land in the SAME group
and change its text, so the key moves and the entry misses.

What remains is the near-miss the brief names: two definitions whose bodies are
byte-identical and whose heads differ.  The property
"two definitions with IDENTICAL bodies keep their own positions" builds exactly
that (`seven = (let dz = four in dz)` and `eight = (let dz = four in dz)`),
shifts the file, and requires BOTH `dz` def-sites to be present at their own
lines.  If the keys collided, one component's `dz` would come back at the
other's line; they do not collide, and both are right.

**No ordinal was added, and none is needed.**  That is worth stating because the
brief offered "key = text + ordinal-among-identical-texts" as an option: an
ordinal would be a position in disguise, and it would re-introduce exactly the
cliff this item removes (re-order two definitions and every ordinal below
moves).

### THE FIX ROUND'S THREE PROPERTIES (review R-1, R-2), and what they fail on

These are the two required by review R-1 and the one required by R-2.  Each is
stated with the tree it FAILS on, because a property that cannot fail is not a
pin.

| property | fixture | fails on | passes on |
|---|---|---|---|
| `7.2 R-1: splitting an OPERATOR's body over two lines is not invisible` | `infixl 6 <+>` / `(<+>) x y = x` / `useOp = three <+> three`, the operator rewritten as `(<+>) x y =` / `  True` | **the pre-fix 7.2 tree** | the fix round |
| `7.2 R-1: splitting a TRUNCATED-HEAD definition's body is not invisible` | `foo_a = one` / `usea = foo_a`, rewritten as `foo_a =` / `  True` | **the pre-fix 7.2 tree** | the fix round |
| `7.2 R-2: a line inserted BETWEEN two mutually recursive groups MISSES` | `pingx n = (let pa = n in qongx pa)` / `qongx m = (let qa = m in pingx qa)`, one blank line between them | **the component tags replaced by a constant**, and (before F-1) on the tree of record too, vacuously | the tree of record |

**Why the R-1 fixtures publish a TYPE divergence rather than a diagnostic.**  The
review's `Opstale.e` made the dependent ill-typed and watched the diagnostic
vanish.  These properties make the upstream's RESULT TYPE change instead
(`a -> b -> a` becomes `a -> b -> Bool`; `Int` becomes `Bool`), so warm and cold
disagree about the dependent's PUBLISHED TYPE.  That is the same hole read
through `invisible`'s existing type comparison, it needs no new machinery, and
it is strictly the stronger assertion of the two — a published type is what hover
shows on every keystroke, where the diagnostic only appears when the dependent
happens to be ill-typed.  Both halves also assert `expectReuse = false`, i.e.
that the fix's conservative answer actually fires: editing an unreachable item
drops the whole per-uri cache.  On the pre-fix tree **both clauses fail** — the
dependent reuses, and it publishes the stale type.

**THE MEASURED EVIDENCE, all four runs.**  A temporary diagnostic in the
property printed the numbers; it is not in the tree.

| tree | `fullReuse` | `warm.reused` | the second group's local `qa` | verdict |
|---|---|---|---|---|
| pre-R-1, pre-F-1 | 4 | 4 | correct | **PASSED VACUOUSLY** (the pair never cached) |
| post-R-1, pre-F-1 | 4 | 4 | correct | fails, and says why: "reused 4 of a possible 4" |
| **tree of record** | **5** | **4** | **(14,16) — correct** | **passes, and the pair MISSES** |
| tags replaced by `"0"` | 5 | **5** | **(13,16) — WRONG by one line** | **fails on both clauses** |

The last row is the whole point, and it shows the corruption as well as the
reuse: with a constant tag the entry is reused and then re-anchored by the FIRST
group's delta, so `qa` comes back at line 13 where the buffer has it at 14 —
which is hover on that local answering `null`, the breakage the review
demonstrated.  The tree was restored, rebuilt, and
`sha256sum -c` checked back to its pre-experiment value; `grep` for `DEMO`,
`SABOT` and `anchor + 1` over `TolerantCheck.scala`, `Anchors.scala` and
`TestTolerantCheck.scala` is empty.

**The R-1 demonstration, the same way.**  With the one-line scope-key
contribution disabled, `sbt 'core/testOnly *TestTolerantCheck -- -f "7.2 R-"'`
reports both halves Falsified with the stale type named:

    ! 7.2 R-1: splitting an OPERATOR's body over two lines is not invisible
      Expected ... useOp -> Bool ... but got ... useOp -> Int
      operator body split: types differ
    ! 7.2 R-1: splitting a TRUNCATED-HEAD definition's body is not invisible
      Expected ... usea -> Bool ... but got ... usea -> Int
      truncated head body split: types differ
    Failed: Total 3, Failed 2, Errors 0, Passed 1

and with it enabled, **3 of 3 pass**.

### The corpus-scale attack — 253 files, through the real server

The fixture attacks above are six definitions.  `TestTolerantCheck`'s new
property **"7.2: the corpus sweep — a shifted buffer reuses, invisibly"** runs
the same question over the whole corpus (stdlib + `core/examples`, the 180-file
rule) through `Resident.checkFile`, the call the server makes.  FOUR checks per
module: cold; the same text again WARM (the CONTROL — what reuse alone does);
the text with ONE BLANK LINE AT THE TOP, warm; and that shifted text COLD.

    ### 7.2 sweep: 249 clean modules of 253 — 123 of 137 with components
    reused after a top-of-file insertion, 1157 of 1334 components;
    16 render differently on an UNSHIFTED reuse (pre-7.2),
    2 publish different row constraints on two COLD checks, 1 on two WARM
    checks, 1 renders a LOCAL differently on two COLD checks; mismatches 0

(Four runs.  The three instability counts move by one between runs — that is
finding (ii) below, not this item — and `mismatches 0` is stable across all
four.)

What it asserts, per module:

* **the cliff, per module:** `warm.reused == ctl.reused` — a check whose only
  change is a line shift reuses EXACTLY what an unedited re-check reuses.  **249
  of 249.**  Before 7.2 the left side was 0 on every one of them.
* **notes** byte-identical warm vs cold: **249 of 249**.
* **def-site POSITIONS** equal warm vs cold AND equal to the first check's
  def-sites moved down exactly one line, columns untouched: **249 of 249**.
  That is the re-anchoring checked against a number no cache produced.
* **the locals, between the two WARM checks**, with the shift taken out of the
  keys: `locs(warm) == locs(ctl) + 1 line`.  **249 of 249.**  Both sides serve
  the same cache entries and a rendered local type carries no ids, so this
  comparison is fully deterministic — it is the strongest single statement of
  the re-anchoring in the suite.
* **the locals, between the two WARM checks**, with the shift taken out of the
  keys: `locs(warm) == locs(ctl) + 1 line`, def-site positions AND rendered
  types.  **249 of 249.**  Both sides serve the same cache entries, so this is
  the strongest single statement of the re-anchoring in the suite.
* **types** (see §3.1) and **local types as hover renders them**: 0 divergences
  attributable to the shift.
* anti-vacuity: the check must have read the EDITED BUFFER (`Checked.contents`
  == the shifted text).  The first draft of this sweep passed `corpusFiles`
  un-absolutised, `Documents.byPath` missed, and every check silently read the
  file from DISK — no buffer, no cache, no shift, and a vacuously green sweep.
  The assertion is there so that cannot recur.

### 3.1 TWO PRE-EXISTING FINDINGS the sweep turned up, neither caused by 7.2

Recorded because they are the reason the type comparison has two controls, and
because they are facts about the 5.5 cache and the checker that were not on
record.

**(i) 16 of 249 modules render a published type DIFFERENTLY on a reuse with no
edit at all.**  Two runs never draw the same `V` ids, and the printer's binder
and constraint ORDER follows id-keyed sets, so a reused scheme generalized in an
earlier run prints its `forall {a b c}` group or its row constraints in a
different order.  6.6's sweep measured the same thing from the other side (145
of 223 "failures", all order) and is why `AlphaEq` exists.  **A rendered-string
comparison is not a sound invisibility oracle for a top-level type**, and this
sweep says so with a number.

**(ii) 2–3 of 249 modules publish DIFFERENT ROW CONSTRAINTS on two COLD checks
in the same JVM** — no cache involved on either side.  `Layout/Report/Fulcrum/
WriterOutputs.e`'s `reportFor` is the clean example: one cold check publishes

    forall (a: rho) (f: * -> *) z.
      (exists (b: rho). a <- ((|pMinValue, pTitle, pRegion|), b)) => Record a -> Report f z

and another, later in the same JVM, publishes

    forall (a: rho) (f: * -> *) z.
      (exists (b: rho) (c: rho). a <- ((|pTitle, pMinValue, pRegion|), c),
       a <- ((|pRegion, pTitle|), b)) => Record a -> Report f z

— the same relation, one simplified and one not.  **The review's repro is
stronger and should be the ticket's**: four cold checks of an UNCHANGED
`WriterOutputs.e` in one JVM (didOpen / hover / didClose, which drops the cache)
give **four different renderings** of `reportFor` — label order moves between
rounds 0 and 1, and the redundant conjunct is dropped in 0–1 and kept in 2–3.
The PRE-7.2 tree gives the same four in the same order, so it is not this
item's; R-4 is the orchestrator's ticket.  The simplifier's queue is
id-hash ordered and the `Supply` has moved between the two checks; this is
`Session.scala`'s own note on `-Dermine.loadInSeries` and PERF-ROADMAP P10 (the
id base alone moved GU05 from 743 to 47,317 draws), showing up in a published
type.  **The cache is on the STABLE side of it**: the warm answer agreed with
the FIRST cold check in every case, and it was the second cold check that
differed.  That is not this item's to fix and it is not a regression — but a
later item that compares published types across runs must know it, and
ROW-CONSTRAINT-STATE.md is where it belongs.

The type oracle is therefore: **equal as hover RENDERS it, or equal up to alpha**
(`AlphaEq.same` — the gate comparator `G1Compare.alphaEq` OR the complete
backtracking one) — **and a divergence counts against this item only when all
THREE controls agree**:

| control | question it answers | modules it excuses |
|---|---|---|
| `ctl == c0` | does reuse alone, with no edit, change the answer? | 16 render differently; the alpha-level subset is smaller |
| `cold == c0` | does the CHECKER agree with itself across two cold runs? | **2–3** — finding (ii), `WriterOutputs.e` among them |
| `warm == ctl` | do the two WARM checks, serving the SAME cache entries, agree? | **1** — `Relation.e`; a disagreement here is in a component NEITHER of them cached, or in the comparator's non-transitivity, and either way not the shift |
| the same, for the RENDERED LOCAL types | a local's type carries row constraints too, so it is subject to the same instability | **0–1** — `Relation.e` again |

Each of those was added because a RUN demanded it, and the sequence is on the
record rather than smoothed over: the sweep was first written with no control
and reported 25 modules; with the reuse control, 9; with alpha instead of
rendering, 2; with the cold-check control, 0 — and then flaked once on
`Relation.e` in a later pass, which is what the warm-vs-warm control and the
local-types control answer.  **Nothing was loosened without a module name and a
mechanism**, and the four assertions that need no control at all are the ones
this item is about.

RESIDUAL RISK, stated: `locs(warm) == locs(ctl) + 1 line` is asserted with NO
control.  It compares two warm checks, so its reused components are literally
the same `LocalTy` objects; only a component NEITHER check cached could make it
flake, the same way `Relation.e` flakes above.  It has held on four runs.  If a
reviewer sees it fail on one module, §3.1 is the first thing to read — but it
should not be waved away, because it is the assertion that proves the
re-anchoring.

With those three, mismatches are **0**, twice, to the digit.  **THE DENOMINATOR,
stated plainly (review R-9): the controls fired on 16 + 2–3 + 1 + 0–1 modules,
so the TYPE half of the sweep is asserted on 231–248 of 249, not 249.**  The
POSITION half — notes, def-site positions warm vs cold, def-sites against the
pre-edit check + 1 line, and the locals between the two warm checks — has no
control at all and holds 249 of 249.  That is the half the item rests on, and it
is the half that would catch an anchoring bug.  Each control was
added because a run demanded it, and each is reported with the count it excuses
rather than folded in silently: **the type comparison across runs in this
compiler is not an exact oracle, and the item says so with numbers instead of
lowering the bar quietly.**  The assertions that ARE exact — notes, def-site
positions warm vs cold, def-site positions against the pre-edit check + 1 line,
and the locals between the two warm checks — carry the weight of the item and
pass on 249 of 249 with no control at all.

---

## 4. THE ESCAPE ROUTES (7.2.2c, 7.2.4) — enumerated, and each one pinned

The Stage-4 invariant is "NO IDENTITY IN A CACHE KEY, AND NO ID IN A CACHED
VALUE THAT ESCAPES".  A cached `Entry` holds exactly two things, so there are
exactly two classes of escape to enumerate: the `locals` KEYS (positions), and
the `types`/`LocalTy` VALUES (`Type`s, which carry `Loc`s from the run that
recorded them).

### 4.1 Positions: where a `Loc` reaches the client, and where it comes from

| route | the position in the reply comes from | cached? |
|---|---|---|
| `textDocument/hover` range | the `Occ`'s own line/col, from the CURRENT run's `Renamer.occurrences` | no |
| hover CONTENTS | `TermHover(name, ty, scope)` rendered by `Pretty` | value only — §4.2 |
| `textDocument/definition` | `Target(b.defSite, …)` from the current renamer; or `env.termNames(g).loc` (another module, read fresh); or `con.loc` (this module's `Con`, installed by this check's type phase — never cached) | no |
| `textDocument/references`, `documentHighlight` | the `Occ` set, current run | no |
| `textDocument/rename` edit ranges | the same `Occ` set | no |
| `textDocument/documentSymbol`, `workspace/symbol` | `Symbols.build(c.module, …)` over the CURRENT surface tree | no |
| `textDocument/codeAction` (add signature) | `QuickFix.groups(idx.module)` over the current surface tree, against the current buffer text | no |
| `textDocument/completion` | the request position + `idx.locals` as a LOOKUP KEY | key only — §4.3 |
| `publishDiagnostics` ranges | the leading `file:line:col:` of a note's report, i.e. the blame `Located` of the component being checked NOW; note-bearing components are never cached | no |

**So no cached POSITION is ever sent to the client.**  `locals`' def-site keys
are used in exactly one way: as a JOIN KEY against `BinderInfo.defSite` from the
current renamer (`Definitions.scala:541` and `:693`, and `idx.locals` for
completion detail).  A stale key cannot move a reply's position; it can only
make a lookup MISS (hover answers null) or, worse, HIT A DIFFERENT BINDER and
show it the wrong type.  Both are what the re-anchoring prevents and what §4.4
pins.

### 4.2 Values: do the `Loc`s inside a cached `Type` reach the client?

**No, on every route that renders a type.**  Checked the right way, after the
review caught the first version of this sentence being false as written
(`Pretty.scala` has 13 occurrences of `loc`, every one of them `localPrec`):
`grep -E "\.loc\b|\bPos\b|Located|startLine|\.line\b|\.column\b|report\("`
over `Pretty.scala` is **empty**.  The type printer reads kinds, names,
constraints and arity, never a position.  Hover, completion detail, the
documentSymbol `detail` and `QuickFix.sigEdit`'s rendered signature all go
through `Pretty`, and the add-signature EDIT RANGE comes from the surface group,
not from the type.

**The one residue, named rather than waved away.**  A cached `Type`'s `Loc`s are
not re-anchored, and a DOWNSTREAM component that is re-checked around a reused
one is inferred against those types (`subs` → `toGamma`).  A few `Subst` failure
sites render a position from a TYPE rather than from the term: `unifyType`'s
`Forall`-with-constraints and `Exists` branches call `e2.report(…)`, and
`occursFail` blames the offending type itself.  Before 7.2 a hit required
identical absolute lines, so such a position could not be stale; now it can, by
the anchor delta.  Three things bound it:

1. it can only appear in a note's MESSAGE BODY or, for `occursFail`, as a note's
   own position — and then only for an error whose blame genuinely is an
   upstream type;
2. it needs a single edit that BOTH shifts lines AND introduces an error of that
   specific class, since a pure shift re-checks nothing;
3. **it is tested, not argued**: the corpus sweep compares notes byte for byte
   over a shifted buffer on 249 modules (**0 differences**), and the unit
   property "a shift AND a new error together stay byte-identical" is exactly
   case (2).  No drift has been observed.

The cheap fix if one ever is — re-anchor a reused entry's `Type` `Loc`s — was
considered and rejected for this item: it needs a loc-rewriting traversal of
`Type`, `Kind` and `TypeVar`, which is a Tier-1-shaped change to `Type.scala`
for a divergence that does not occur.  It is recorded here as the one place a
future failure would come from.

### 4.3 lsp-smoke: a fixture per route, asserting a position AFTER a
line-shifting `didChange` with no save

New fixture `tracker/lsp-tests/Anchor.e` (19 lines: a `data`, a signed binding
with a `let` local, an unsigned binding with a `where` local, a user of a top
level, an unsigned binding with no local, and an unsigned binding with a `let`
local).  Every route is asked ONCE on the pristine buffer and ONCE after a
`didChange` that inserts THREE BLANK LINES AT THE TOP — no `didSave`, so the
file on disk still says the old lines — and every answer must have moved by
exactly three.  **lsp-smoke 456 → 480** (+24).

| pin | route |
|---|---|
| `7.2 hover on a LET local survives a line shift` | hover contents, local, signed binding |
| `7.2 hover on a WHERE local survives a line shift` | hover contents, local, UNSIGNED (cached) binding |
| `7.2 hover on a LET local of an UNSIGNED binding survives a line shift` | ditto, `let` form |
| `7.2 hover on a top level survives a line shift` | hover contents, `types` |
| `7.2 definition of a local is re-anchored` | definition, a local binder's def-site |
| `7.2 definition of a top level is re-anchored` | definition, a top-level def-site |
| `7.2 references are re-anchored` | references |
| `7.2 highlight ranges are re-anchored` | documentHighlight |
| `7.2 rename edit ranges are re-anchored` | rename, every edit range AND its newText |
| `7.2 documentSymbol ranges are re-anchored` | documentSymbol: name, range, selectionRange, children |
| `7.2 the add-signature edit range is re-anchored` | codeAction edit range |
| `7.2 the shifted buffer still checks clean` | diagnostics |
| `7.2 the cold open reuses nothing` / `7.2 the line-shifted check reuses every component` | **the acceptance number**, read from the server's own `check:` line in the log |

plus seven baseline checks that the routes answer at all before the edit (a pin
that compares a shifted answer against a baseline of `None` would be vacuous).

**NON-VACUITY, measured.**  `Anchors.absPos` was sabotaged with an off-by-one
(`p._1 + anchor + 1`) and lsp-smoke re-run: the `where`-local pin, the
unsigned-`let` pin and the EXISTING 6.2 pin "hover last local at its NEW line"
all fail; every other pin passes.  That is the honest reading of this block —
**the pins that bite are the ones on locals of UNSIGNED bindings**, because an
explicitly signed binding is an `ExplicitBinding`, `checkWith` never caches one,
and its locals are recomputed on every check.  The position pins on definition /
references / rename / symbols / codeAction are REGRESSION pins: they read the
current run's tables and would survive a broken re-anchoring, which is exactly
what makes them worth having — they are the statement that 7.2 did not move a
position it had no business moving.

---

## 5. CACHE INVISIBILITY (7.2.4), and the test inventory

The 5.5 edit set (`TestTolerantCheck`'s four "reuse is invisible" properties
plus the two cache-drop properties) is unchanged and still green; 6.2's
extension — comparing `renderedLocals`, def-site keys AND rendered types, warm
vs cold — is what the new properties reuse.  `TestTolerantCheck` went from
**27 properties to 47**:

| group | count | what |
|---|---|---|
| `7.2 Anchors: …` | 5 | the span arithmetic itself, `forAll` over 100 cases each: `rel`/`abs` inverse at one anchor; `rel` is `line − anchor` sign and all, and `tag` agrees; a COLUMN is never moved (pair and span, both directions); a span moves both ends by the same delta and round-trips; a keyed map round-trips, keys and values |
| `7.2: …` drift attacks | 11 | §3 |
| `7.2: the corpus sweep` | 1 | §3, 249 modules × 4 checks |
| **`7.2 R-1: …`** | **2** | the fix round: an operator's body split over two lines, and a truncated-head definition's.  **Both FAIL on the pre-fix tree** — §3 |
| **`7.2 R-2: …`** | **1** | the fix round: a line between two mutually recursive groups must MISS, and the second group's local must answer at its new line.  **Fails when the component tags are replaced by a constant** — §3 |
| 5.5 + 6.2, unchanged | 27 | including the 253-file 6.2 local-binder sweep (249 clean, required-class misses 0) |

The `Anchors` unit properties are in `TestTolerantCheck` rather than in a new
suite on purpose: the seven targeted suites are a named gate, and a helper with
its own suite would not be in it.

---

## 6. FILES CHANGED

| file | what |
|---|---|
| `core/.../surface/Anchors.scala` | **NEW**, ~66 lines (the dead `anchor == 0` arm removed in the fix round, R-6).  The span arithmetic in one place: `rel`/`abs`, `relPos`/`absPos`, `relSpan`/`absSpan`, `relKeys`/`absKeys`, `tag`.  Its three rules are in its comment and in the five properties: a relative line may be negative and nothing clamps; COLUMNS ARE NEVER SHIFTED; `rel` and `abs` are inverses at the same anchor and that is the only property a caller may rely on.  7.1b's spans go through `relSpan`/`absSpan`. |
| `core/.../session/TolerantCheck.scala` | **fix round:** `reachable`/`lexemeAt` and the `keyedItems`/`unkeyedItems` partition — an unreachable bind item's TEXT goes into the scope key (R-1), the `Cache` comment says so, and each bind item's text is now taken exactly once (strictly fewer `Offsets.text` calls than before this round); `fpOf`'s key built from `sps.sorted` with the texts carried along, so it is a function of the text and not of `comp`'s traversal order (F-1).  Then: `keys` returns `Map[String, Group]` (`Group(text, anchor)`) instead of `Map[String, String]`; the text carries each statement's offset from the group's anchor instead of its absolute start line; `fpOf` returns `(fingerprint, anchor)` and tags each group with its offset from the component anchor; `Entry.locals` is stored relative (`Anchors.relKeys`) and re-anchored on a hit (`Anchors.absKeys`); `Cache` and `Entry`'s doc comments carry the new invariant in place of the old argument. |
| `core/.../lsp/Resident.scala` | the `keys` call site's comment; `Checked` gains `reused`/`components` (defaulted), the pair the server already logs, so a test can ask whether an edit REUSED and not only whether it agreed. |
| `scalacheck-binding/.../TestTolerantCheck.scala` | +20 properties (§5), three of them the fix round's; `aeq`/`multi` moved out of the 6.6 sweep's body into `AlphaEq.scala` and both sweeps now call it. |
| `scalacheck-binding/.../AlphaEq.scala` | **NEW**.  The alpha-equivalence comparator the 6.6 sweep had inline: `strict` (the G1 gate comparator), `loose` (the complete backtracking one), `same`.  Moved rather than duplicated, and moved to its own FILE rather than up one scope, so the diff is a deletion plus a new file and `git diff --stat -w` stays meaningful. |
| `tracker/lsp-tests/Anchor.e` | **NEW** fixture, 19 lines. |
| `tracker/tools/lsp-client.py` | +24 checks (§4.3); Baselines note 456 → 480. |
| `tracker/tools/perf-client.py` | **fix round (R-7):** the docstring's two stale sentences — "start lines are in every group's key, so inserting a line invalidates everything below it" and "an operator is never cached" — rewritten to what the bench's pinned edit must now avoid and why. |
| `docs/lsp.md` | the harness section's lsp-smoke count and what it covers — it was **stale at 454** (7.0 raised the count and did not touch the doc); now 480, naming 7.0's phase-timer gate and 7.2's `Anchor.e` pins |
| `tracker/loopmodel/LSP4-7.2-ANCHORS.md` | **NEW** — this report. |

Scratch, deliberately not in the tree (`<scratch>/7.2/`): `cliff2.py` (the
before/after cliff driver), `ab.sh` (the interleaved A/B), the saved
`classes-before`/`classes-after` trees, and every run's log and table.

---

## 7. THE INTERLEAVED A/B (7.2.5)

`<scratch>/7.2/ab.sh`: the two sides are two saved `core/.../classes` trees
(`classes-before` built from `6db2c3a`'s `TolerantCheck.scala` and
`Resident.scala` with `Anchors.scala` removed, `classes-after` the tree of
record), selected by rewriting the core entry of `tracker/repl-classpath.txt`.
ONE JVM at a time, **before / after / before / after**, the `perf-bench.sh
editor -k 15` shape (`perf-client.py --rounds 15`, round 1 discarded, median of
14) on `Layout/Report.e`, then the same interleaving on the CLIFF scenario.

`perf-bench.sh` could not be the wrapper, for 7.0's reason unchanged: its
preflight `pgrep -f 'sbt-launch|xsbt\.boot'` matches an unrelated orchestrator
shell whose command line merely NAMES those strings.  `perf-client.py` is
invoked directly with the same JVM flags perf-bench passes.

### 7.1 Steady state — the in-body edit.  Δ ≈ 0, as predicted

| | before b1 | after a1 | before b2 | after a2 | **pooled before** | **pooled after** | **Δ** |
|---|---|---|---|---|---|---|---|
| round trip median | 1.766 | 1.793 | 1.762 | 1.732 | **1.7640 s** | **1.7625 s** | **−1.5 ms (−0.08 %)** |
| read | 0.885 | 0.920 | 0.885 | 0.865 | 0.8850 | 0.8925 | +7.5 ms |
| typecheck | 0.545 | 0.560 | 0.540 | 0.540 | 0.5425 | 0.5500 | +7.5 ms |
| cold `didOpen` | 2.290 | 2.333 | 2.286 | 2.246 | 2.288 | 2.290 | +1.5 ms |
| reused | 97/154 | 97/154 | 97/154 | 97/154 | — | — | — |
| boot | 13.42 | 13.72 | 13.03 | 13.57 | 13.23 | 13.65 | +0.42 s |

**This item does not speed up the common case and was not expected to: it
removes a cliff.**  −1.5 ms on the round trip is a hundredth of the harness's own
between-run spread (the roadmap records the read segment wandering 0.795–0.865 s
on an UNCHANGED tree), and the individual medians straddle each other
(after beats before in pass 2, loses in pass 1).  The per-reused-component cost
the fix adds is one `Map` rebuild of that component's `locals` at lookup; on
Report.e that is 97 small maps per check, and it is not visible.

**ON LOAD, honestly.**  Load was **1.14** at the start of the first measured run
and rose to 2.0–3.4 over the sequence — and that rise IS the harness: each run
boots a 13 s JVM and the 1-minute average is the previous run decaying.  There
was no other work on the machine (the only other JVM is an idle bloop daemon,
present for 7.0's runs too).  This is precisely the case GATE-POLICY answers with
interleaving rather than with a load threshold: b and a alternate, so whatever
the machine was doing it was doing to both sides, and waiting for the average to
fall between runs would have pushed the pairs FURTHER apart in time, not closer.
The steady-state claim is "no change", and both orderings agree on it.

### 7.2 The cliff — the number that matters

`checkWith` (the typecheck), medians of the two passes per side, from the
`phases` line:

| scenario | before `checkWith` | before reused | after `checkWith` | after reused | **Δ** |
|---|---|---|---|---|---|
| in-body edit (reference) | 541–604 ms | 97/154 | 537–626 ms | 97/154 | ≈ 0 |
| **TOP-INSERT + body edit** | **1090 / 1176 ms** | **0/154** | **572 / 537 ms** | **97/154** | **−578 ms, −52 %** |
| **TOP-INSERT, pure** | **1048 / 1046 ms** | **0/154** | **427 / 493 ms** | **115/154** | **−587 ms, −56 %** |
| **TOP-DELETE, pure** | **1178 / 1152 ms** | **0/154** | **419 / 474 ms** | **115/154** | **−719 ms, −62 %** |
| **MID-INSERT, pure** | **781 / 768 ms** | **83/154** | **433 / 448 ms** | **115/154** | **−335 ms, −43 %** |
| cold `didOpen` (reference) | 1166 / 1196 ms | 0/154 | 1150 / 1141 ms | 0/154 | ≈ 0 |

The roadmap's target was "typecheck 1.07 s → ~0.5 s on a top-of-file
insertion".  **Measured: 1.05 s → 0.46 s on the pure insertion, and the
insertion is no longer distinguishable from a cold open only because it no
longer resembles one** — after the fix a top-of-file insertion is *cheaper* than
an in-body edit (it invalidates nothing at all, where an in-body edit
invalidates one group and its dependents).

Round trip, from the non-interleaved pair of §1 (the same scenario, single runs):
the TOP-INSERT round trip went **2.40 / 2.26 / 2.20 s → 1.87 / 1.74 / 1.62 s**,
i.e. the +0.51 s regression 7.0 measured "for an edit that changed nothing" is
gone and the shifted round trip is now at or below the in-body steady state.

Every cell clears the 200 ms pooled gate by **1.7x–3.6x**, and the steady-state
Δ is inside the 5 % / 80 ms budget by three orders of magnitude.

### 7.3 THE FIX ROUND'S CLIFF RUN — R-1 fires, and the cliff stays gone

One server, `<scratch>/7.2/cliff3.py` (cliff2 plus an operator-edit mode on
`Layout/Report.e:876`, `(||) e1 e2 = orEvent e1 e2`, whose head word is empty and
which therefore reaches no group key).  Load 3.80 at the start — this is a
REUSE-COUNT experiment, not a timing one, and the counts are exact integers; the
times are shown for scale and are not the A/B.

| step | reused | `checkWith` |
|---|---|---|
| `didOpen` (cold) | 0 of 154 | 1201 ms |
| in-body edit ×2 | 97 of 154 | 521–570 ms |
| **TOP-INSERT, pure** | **115 of 154** | **471 ms** |
| in-body, shifted | 97 of 154 | 604 ms |
| **TOP-DELETE, pure** | **115 of 154** | **466 ms** |
| in-body | 97 of 154 | 544 ms |
| **OPERATOR edit, NO line-count change** | **0 of 154** | **1165 ms** |
| in-body (recovered) | 97 of 154 | 555 ms |
| **OPERATOR edit, SPLIT over two lines** | **0 of 154** | **1093 ms** |
| in-body (recovered again) | 97 of 154 | 513 ms |
| **TOP-INSERT, pure, with the operator still split** | **115 of 154** | **478 ms** |

Four things, each one a requirement of this round:

1. **R-1 did NOT re-create the cliff.**  A pure top-of-file insertion still
   reuses **115 of 154** at **471 ms**, and a deletion 115 at 466 — the same
   numbers as before the fix round (§1, §7.2).  The scope key grew a part, but
   that part is extent TEXT, which a line shift does not touch.
2. **R-1 FIRES, with and without a line-count change.**  Editing the operator
   drops the whole per-uri cache — **0 of 154**, indistinguishable from a cold
   open — whether the edit changes the line count or not.  That is the
   conservative answer, and it is the answer 5.5 already gives for a `private`
   block.
3. **A plain edit is unaffected**: 97 of 154 on every in-body round, before and
   after each operator edit, so recovery is immediate and the common case pays
   nothing.
4. **The two interact correctly**: with the operator left split, a pure shift
   still reuses 115 — the scope key is position-free, so one conservative drop
   does not poison the shifts that follow it.

**THE COST OF R-1, stated plainly.**  One keystroke inside an operator, a
backtick name or a `_`/`'` spelling now costs a full cold check (~1.1 s of
inference on Report.e instead of ~0.55 s), where before the fix round it cost
~0.55 s and gave a WRONG ANSWER.  111 of 358 corpus files have at least one such
item.  That is a real regression in one case, taken deliberately: a stale type
with its diagnostic dropped is not a performance trade.  §9 names the follow-on
that removes most of the cost (teach `wordAt` `_` and `'`, which is 157 of the
825 items and is Tier 1).

---

## 8. GATES

Tier 0, plus the seven targeted suites.  Tier 2 at adoption is the reviewer's /
orchestrator's, per the item.  Every run below is on the tree of record, one JVM
at a time.

| gate | required | **result** |
|---|---|---|
| `sbt core/compile core/copyResources` | green | **green** (one pre-existing `-W` pattern-match warning in `TolerantCheck.foreignTypes`, present at `6db2c3a`) |
| `core/testOnly *TestLoopTrace` | 720/720 | **720 segments, 720 agree, 0 hashdiff, 0 eqdiff, 0 skipped, 0 nonpart, fuel 0; 3/3 properties**; controls non-vacuous (id base +1: 46/720 disagree; `--flags=nongen`: 58/720) |
| `corpus-run.sh --batch` over 154 | 85 / 69 / 0 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** (one JVM, exit 0) |
| `repl-smoke.sh` | 8 groups / 66 checks | **8 groups, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); `git status tracker/repl-tests/` EMPTY — goldens byte-unmodified |
| `lsp-smoke.sh` | 456 + this item's | **480** (456 + 24), PASS |
| boot | 129 modules | **129 modules in 13.6 s** |
| `.ei` droppings | 143, no more | **143** by `find . -name '*.ei' \| wc -l` — the gate the review asked for (R-10), because the boot gate writes interfaces under `core/target/.../classes/modules/` that `git status` cannot see and a later per-file corpus run would READ.  All 143 are TRACKED (129 `tracker/g1-baseline/ei/`, 14 `tracker/g1-oracle-tests/`); **0 untracked, 0 under `core/target`** after the whole fix-round sequence (boot, lsp-smoke, repl-smoke, the cliff run) |
| **fix round:** `*TestTolerantCheck *TestTolerantRead *TestEditorBuffers` | green | **64 properties, 0 failed** — TestTolerantCheck **47**, Tolerant read 11, Editor buffers 6; both corpus sweeps re-run inside it, unmoved (6.2: 249 clean, misses 0; 7.2: 1157 of 1334 components, mismatches 0) |
| **fix round:** `lsp-smoke.sh` | 480 | **480**, PASS |
| **fix round:** `repl-smoke.sh` | 8 / 66 | **8 groups, 66 checks**; `git status tracker/repl-tests/` EMPTY |
| **fix round:** the cliff run | 115 / 0 / 97 | **115 of 154** on a pure shift, **0 of 154** on an operator edit (both with and without a line-count change), **97 of 154** on every plain in-body edit — §7.3 |
| **fix round:** `core/compile core/copyResources` | green | **green** |
| the seven targeted suites, pre-fix-round | green | **156 properties, 0 failed**: Tolerant check **44**, Ermine stage1 pins 34, Renamer 3 × 32, Lower 3 × 28, Tolerant read 11, Editor buffers 5 × 6, REPL eval goldens 1 |
| 6.2's 253-file local sweep (inside TestTolerantCheck) | unchanged | **249 clean of 253; Arg(equation) 2872/2872, LetBound 156/156, WhereBound 89/89; required-class misses 0** — identical to 7.0's run |
| 7.2's corpus sweep | new | **249 clean of 253; 123 of 137 modules with components reused after a line shift, 1157 of 1334 components; per-module shifted-reuse == unshifted-reuse on 249 of 249; mismatches 0** — four runs |
| the seven suites, re-run after the sweep's last control | green | **156 properties, 0 failed** |
| strict path untouched | empty diff | `git diff -- session/Session.scala rename/NewPipeline.scala` **EMPTY** |
| CRLF preserved | yes | every file touched is LF in the tree and LF after (checked with `grep -U $'\r'`); no line-ending change anywhere |
| `git diff --stat` == `--stat -w --histogram` | identical | **identical: 843 insertions / 107 deletions** by `--stat`, `--histogram --stat`, `--histogram --stat -w` and `--patience --stat -w` alike.  Under git's DEFAULT (Myers) algorithm `-w` alone reports one more insertion and one more deletion in `TolerantCheck.scala` (236 vs 234) — an alignment artifact, see below |

**The `--stat -w` note, because the gate is named in the brief.**  `git diff
--stat`, `--histogram --stat`, `--histogram --stat -w` and `--patience --stat -w`
all report **843 insertions, 107 deletions**.  Only git's DEFAULT (Myers)
algorithm with `-w` differs, by one insertion and one deletion, because it aligns
an unchanged `    }` line into a changed hunk that plain diff keeps as context.
That is an artifact in the direction that CANNOT hide anything — `-w` showing
MORE change than the plain diff is the opposite of a reindentation being
collapsed — and a line-level audit confirms it: over the whole diff the only
changed lines whose content is equal after stripping all whitespace are bare `}`
braces (5 removed, 17 added), i.e. structure, not reformatting.  The one place a
real reindentation would have appeared — moving `aeq`/`multi` out of the 6.6
sweep's body — was avoided by moving them to a NEW FILE (`AlphaEq.scala`) rather
than up one scope, so that change is a deletion plus an untracked new file and
nothing is re-indented.

### What was NOT run, and why

* **Tier 1**: nothing under `parsers/` (`scalaparsers`), `Subst.scala` or
  `Type.scala` was touched.  The one change that would have needed it — a
  loc-rewriting traversal of `Type` (§4.2) — was deliberately not made.
* **Tier 2** (full `core/test`, alone on the tree): the item assigns it to
  adoption.  The reviewer ran it on the PRE-FIX-ROUND tree — **1005 of 1005, 0
  failed, 0 errors** — and the orchestrator re-runs it on this tree.  The fix
  round's three code changes are all inside `TolerantCheck.keys`/`fpOf` and
  `Anchors`, i.e. the editor path only; the three suites re-run above cover it
  end to end, and the batch/REPL gates (`corpus-run.sh --batch` 85/69/0,
  `repl-smoke` 8/66 byte-exact) were green on the same tree.
* **The 6.6 quick-fix corpus sweep** (`-Dermine.sweep.quickfix=true`) is
  quarantined by GATE-POLICY, so it is not part of Tier 0 — but this item MOVED
  its comparator, so it was run anyway rather than argued about:
  **green, 1/1, 87 s**, import-scanner disagreements 0, and **"pairs equal only
  under the COMPLETE comparator: 5"**, i.e. `AlphaEq.loose` is still doing the
  work `G1Compare.alphaEq` cannot (the count the old inline `g1Only` reported,
  unchanged in meaning).  `AlphaEq.scala` is that `aeq`/`multi` moved verbatim,
  with `sameTy` rewritten to `AlphaEq.strict`/`AlphaEq.loose` — the same two
  calls in the same order.

### For the orchestrator: the Baselines note

`tracker/LSP-ROADMAP.md` is not this item's to edit, so two numbers there need
the committing hand: the **Baselines lsp-smoke count 456 → 480**, and item 7.2's
tick.  `docs/lsp.md`'s harness section has been updated here (it was **stale at
454** — 7.0 raised the count to 456 and did not touch the doc; it now says 480
and names the `Anchor.e` pins and 7.0's phase-timer gate).

---

## 9. VERDICT

> ## **GREEN**, after the fix round.  The cliff is removed: a top-of-file insertion now reuses MORE
> ## than an in-body edit (115 of 154 against 97), `checkWith` goes
> ## **1.05 s → 0.46 s (−56 %)**, a top-of-file DELETION **1.17 s → 0.45 s
> ## (−62 %)**, a middle insertion **0.77 s → 0.44 s (−43 %)**, and the
> ## steady-state round trip does not move (**Δ −1.5 ms**, interleaved).
> ## Positions are right on every escape route, and the drift invariant has
> ## been restated in the code and re-attacked — the 6.2 reviewer's five
> ## attacks, eight line-shifting ones, the duplicate-body case, and a
> ## 249-module corpus sweep whose per-module assertion is
> ## "a shift reuses exactly what no edit reuses": 249 of 249.

**The invisibility condition is now met, and it was not before the fix round.**
`keys` now puts the text of every unreachable top-level bind item in the scope
key, the two properties that fail without it are in the suite, the component key
is a function of the text (F-1), and the component tags have the property the
review asked for.
The review was right to block on it: `Opstale.e` is a line-shifting edit on which
warm and cold disagreed about a diagnostic, at 7.2 and not before it, and item
7.2's acceptance names exactly that.  §2.5 is the rule that closes it, and §3's
“fix round's three properties” the two that fail without it.

Both of the item's acceptance conditions hold and neither is marginal:

1. **the before/after reuse count for a one-line insertion at the top of
   Report.e, MEASURED on both sides: 0 of 154 → 115 of 154** (97 of 154 when the
   same edit also changes a body), reproduced on two interleaved passes;
2. **every `Loc` that escapes to the client is re-anchored**, the routes
   enumerated in §4 and each pinned in lsp-smoke after a line-shifting
   `didChange` with no save, with the non-vacuity of the pins established by
   sabotaging `Anchors.absPos`.

Cache invisibility holds over the 5.5 edit set extended with the line-shifting
edits, at fixture scale (17 new properties) and at corpus scale (249 modules ×
4 checks, 0 mismatches).

### What 7.1b inherits

* **`Anchors`** is the helper the item was asked to leave behind, and `relSpan`/
  `absSpan` are there for the `Span`s a spliced statement carries.  Its rule 2 —
  COLUMNS ARE NEVER SHIFTED — is the one 7.1b must not break: a spliced
  statement's columns are fixed by its own text, and if 7.1b ever needs to move
  one, its key is wrong.
* **THE FOLLOW-ON THAT PAYS FOR R-1.**  R-1's conservatism costs a full cold
  check per keystroke inside an operator, a backtick name or a `_`/`'` spelling,
  on 111 of 358 corpus files.  Teaching `StatementExtents.wordAt` the `_` and
  `'` that `Lexer.tailChar` already knows removes **157 of the 825** such items
  — every truncated-head one — and leaves only the operator/backtick half on the
  scope key.  It is Tier 1 (the scanner is pinned by a 180-file differential),
  which is why it is not this item's, and 7.1b has to revisit the scanner
  anyway.
* **THE EXTENT SCANNER'S NAMING IS NOW A CORRECTNESS SURFACE, not a coverage
  one.**  Before the fix round an item `groups` could not name was simply never
  cached; now its text is in the scope key, which is conservative but blunt — one
  keystroke in an operator's body drops the whole per-uri cache, and 111 of 358
  corpus files have at least one such item.  **The right long-term answer is
  7.1b's**, because it has to revisit `StatementExtents` anyway: teach `wordAt`
  the `_` and `'` that `Lexer.tailChar` already knows, which makes the 157
  truncated items real groups and leaves only the operator/backtick half on the
  scope key.  That is Tier 1 (the scanner is pinned by a 180-file differential),
  which is why it is not this item's.
* **The key shape generalises.**  7.1b's unit is a statement extent, not a
  group; the lesson of §2.3 is that the key must pin the INTERNAL geometry of
  whatever it covers and leave exactly one free number, the anchor.  For a
  single statement the internal geometry is its own text, so a statement cache
  needs no tags at all — one anchor per entry.
* **7.0's §4.3 finding still applies and is not softened by this item**: 62 of
  the 591 extents are `import`/`export` header lines the statement grammar falls
  back on, and 15 of 529 real statements differ from the whole-file parse in
  their top-level end `Span` — which a splice must re-derive from the next
  extent's start.  `Anchors.absSpan` will move that span correctly once it is
  right; it cannot make it right.
* **Finding (ii) of §3.1 is a warning for 7.1b's differential**: two cold checks
  of the same module in the same JVM can publish different (equivalent) row
  constraints, so a splice differential that compares published types across
  runs must compare up to alpha with the COMPLETE comparator and must expect
  2–3 modules in 249 to differ anyway.

STOPPED after this report.
