# Stage 4 prior-art survey — incremental read, stable identity, concurrency, sync

Written 2026-09-10 as input to Stage-4 planning of `tracker/LSP-ROADMAP.md`.
Research only: nothing outside this file was edited and nothing was committed.  No
sbt build, no `bin/ermine` and no Ermine JVM were run; one disclosed exception is
recorded in the appendix (a research subagent ran a standalone Java microbenchmark in
the scratchpad for the figures in §4.3).  Every number attributed to Ermine is
quoted from `tracker/PERF-ROADMAP.md` or `tracker/LSP-ROADMAP.md`, not
re-measured here.  Where a claim about an external system is my inference
rather than something the source says, it is marked **[inferred]**.

**Contents.**  §0 the local problem in the survey's terms; §1 incremental parsing and
declaration-level re-parse; §2 stable identity across runs; §3 concurrency in language
servers; §4 TextDocumentSync deltas; §5 options for Ermine, ranked; appendix on
provenance and corrections.

**The one-line finding**, if only one is read: rename + reassoc + lower are **1.1 % of
editor samples (~12 ms)**, so the identity problem 5.5 parked is guarding twelve
milliseconds — while **parse is ~91 % of the 0.770 s read**, and the surface AST carries
no minted identity at all.  The largest available win needs no identity scheme.

---

## 0. The local problem, restated in the terms the survey needs

### 0.1 The numbers that constrain everything

BASELINE OF RECORD (PERF-ROADMAP, P1, commit 6763245, this machine):

| segment                          | median   | share of round trip |
|----------------------------------|----------|---------------------|
| read (parse + rename + lower)    | 0.770 s  | 48 %                |
| typecheck (inference)            | 0.515 s  | 32 %                |
| debounce (policy, not work)      | 0.300 s  | 19 %                |
| residual (env copy, scrub, index, protocol) | 0.017 s | 1 % |
| **round trip**                   | **1.616 s** | —                |

P2's editor profile (1970 samples, all on `main`) splits the compute:

| phase        | share of samples | implied seconds inside the 0.770 s read |
|--------------|------------------|------------------------------------------|
| parse        | 62.7 %           | ~0.70 s                                  |
| extent scan  | 4.8 %            | ~0.054 s (P5(a) has since cut this pass 11.5x) |
| lower        | 0.8 %            | ~0.009 s                                 |
| rename       | 0.2 %            | ~0.002 s                                 |
| reassoc      | 0.1 %            | ~0.001 s                                 |
| inference    | 30.8 %           | (the other segment)                      |

(The middle column is my arithmetic: the phase shares that fall inside the read
sum to 68.6 %, so parse is 62.7/68.6 = 91.4 % of the read.  **[inferred]**, and
subject to PERF-ROADMAP's standing warning that JFR over-attributed
`StatementExtents.offsetOf` by 3.5x — read these as upper bounds and measure the
pass directly before spending on it.)

Leaf families in the same profile: `scalaparsers`' `Free` trampoline 52.6 %,
`Fail.++` 8.3 %, free-variable collection 14.8 %, substitution 8.9 %, the Ermine
grammar itself 0.9 %.

**THE ONE FACT THAT REORDERS THE ROADMAP'S OWN PRIORITIES.**  Rename, reassoc
and lower together are **1.1 % of samples — about 12 ms**.  The identity problem
that LSP 5.5 named ("cached lowered trees cannot mix with fresh trees because
binder ids and V ids are fresh per run") is therefore guarding a ~12 ms prize on
the read path.  Solving it buys almost nothing in read latency directly.  What
the read costs is *parsing*, and parsing is the one phase in the pipeline that
has **no minted identity at all**.  Sections 1 and 5 turn on this.

### 0.2 What carries identity, and what does not

Verified by reading the source, not inferred:

- **Surface AST (`surface/Surface.scala`)** — `SVar`, `SApp`, `SLam`, ... carry
  only an `SLoc`/`Span` (`startLine, startCol, endLine, endCol`, 1-based) and
  literal payloads.  No node id, no binder id, no supply draw.  The header
  comment says it outright: "no desugaring, no fixity-driven tree shape".
  `SName` carries a `fixity` field, but at parse time that is the *lexical*
  fixity (`Idfix` for plain names, the paren-binder forms for `(infixl 5 op)`) —
  the fixity *environment* is applied later by Reassoc.  **A parsed statement is
  therefore independent of every other statement in the file**, modulo the
  layout column and lexical trivia.
- **Renamer (`rename/Renamer.scala`)** — `private final class S { var nextId = 0
  ... def fresh() = { val i = nextId; nextId += 1; i } }`.  Binder ids are a
  per-run counter *starting at 0*, so they are already deterministic given the
  same text; what makes them unstable is that an edit anywhere earlier in the
  file shifts every later binder's number.  They are only ever `Map` keys inside
  `Renamer.Result` (`binders: Map[Int, BinderInfo]`, `ToBinder(id)`); they never
  escape into the session.
- **Lower (`rename/Lower.scala`)** — `private def freshId(): Int = supply.fresh`,
  and the comment says why: "ids come from the session Supply: module loads
  accumulate their Vs in s.env/s.termNames, so a per-module counter would
  collide across loads".  `Resident` holds one `implicit val supply: Supply =
  Supply.create` for the whole server lifetime, and `scalaparsers.Supply` hands
  out 1024-id blocks from a process-global `synchronized` counter.  So core `V`
  ids are genuinely global, monotone, and not reproducible across runs.
- **TolerantCheck (`session/TolerantCheck.scala`)** — the 5.5 cache is keyed by
  `fingerprint` of *source text*, explicitly *because* ids are unstable: "every
  V in a fresh run has a fresh id, so a type rendering would be a moving
  target".  `keys` builds one group per top-level head word whose text is
  `startLine + ":" + text` per statement, plus a `scopeKey` over the module
  name, the imports key, the scope-bearing statements' text, the sorted head
  set and the other open buffers' versions.

**A nuance worth carrying into Stage 4.**  The 5.5 cache *does* already mix an
artifact minted in run *N* into run *N+1*: a hit splices the previous run's
`Type` into `subs` for the current run's `TermVar`s.  That is sound because a
generalized scheme is **closed** — its `V`s are its own, and the global `Supply`
guarantees they collide with nothing.  The identity problem bites only for
**open** artifacts, whose free variables must be the *same objects* as the ones
another part of this run holds.  That is exactly the distinction GHC draws
between a `ModIface` (closed, hashed, reusable) and Core (open, not), and the one
rust-analyzer draws between an item tree and a body (section 2).

### 0.3 The two primitives Stage 4 already owns

- `surface/StatementExtents.scala` — a pure lexical scan giving every top-level
  item's `Extent(startLine, startCol, endLine, endCol, headWord)`, with comments,
  strings and bracket depth handled, verified against the parser's own splitter
  over the 180-file corpus.  Cheap: 1.64 ms on Report.e after P5(a).
- `SurfaceParsers.statementFailure` — already parses **one statement from its
  own extent slice** with a repositioned `ParseState` (`loc = Pos(file, first,
  startLine, startCol)`, `input = slice`, `offset`, `layoutStack =
  List(IndentedLayout(startCol, "statement"), IndentedLayout(1, "top level"))`,
  `bol = false`) and `eof` at the end.  It exists to recover a failure position;
  the same call shape is what a per-statement *cache miss* would use to
  re-parse.  Its own docstring records the known divergence: "the re-parse may
  SUCCEED where the splitter rejected (context the slice lacks)".

Report.e is 1757 lines / 77,385 bytes with roughly 315 top-level statements
(LSP-ROADMAP 5.5's figure), i.e. ~245 bytes of source per statement.  A
one-character edit leaves ~314 of them byte-identical.

---
## 1. Incremental parsing, and the cheaper alternative

### 1.1 tree-sitter — incremental GLR, and one integer per node

Docs <https://tree-sitter.github.io/tree-sitter/>; source
<https://github.com/tree-sitter/tree-sitter> (`lib/src/parser.c`, `subtree.c`,
`reusable_node.h`, `get_changed_ranges.c`).

The API is two steps: `ts_tree_edit` adjusts every node's ranges to stay in sync
with the text ("You must describe the edit both in terms of byte offsets and in terms
of (row, column) coordinates"), then `ts_parser_parse` is called again with the old
tree and "will create a new tree that **internally shares structure** with the old
tree."

The reuse criterion is a **per-node lookahead byte count**.  `ts_subtree_edit`
descends from the root and skips a child only if

```c
// If this child ends before the edit, it is not affected.
if (child_right.bytes + ts_subtree_lookahead_bytes(*child) < edit.start.bytes) continue;
```

i.e. the node's extent *plus everything the lexer examined past it*.  That single
integer is what makes reuse sound in the presence of arbitrary lexer lookahead.

Reuse is refused for a documented list of reasons — `has_changes`, `is_error`,
`is_missing`, `is_fragile`, `contains_different_included_range` — and then again at
the leaf: "If the token was created in a state with the same set of lookaheads, it is
reusable."  Error regions are `fragile_left/right` and poison their ancestors.  On
refusal the parser *crumbles* one level (`reusable_node_descend`) and retries.

**Node identity.**  A reused `Subtree` is literally the same refcounted pointer.
`TSNode`, the API-level handle, is a **value struct computed on demand**
(`{ uint32_t context[4]; const void *id; const TSTree *tree; }`) — there is no
persistent handle stable across parses.  The root is never reusable.

**Layout.**  tree-sitter's entire indentation mechanism is one bit: `depends_on_column`,
set iff the lexer called `get_column()`, and propagated up the spine; a
column-dependent node is invalidated until the next line break.  That is the finest
granularity available and it is coarse.  Real layout support is a hand-written
external scanner that serializes an indent stack into every token — for Haskell,
**3,471 lines of C** (`tree-sitter-haskell/src/scanner.c`: "Since Haskell is
indentation sensitive and uses parse errors to end layouts, this component has many
responsibilities").  Native indentation support is an open discussion
(<https://github.com/tree-sitter/tree-sitter/discussions/2861>, cross-linked to issue
#219), not a feature.

**What Ermine could take from it.**  Not the algorithm — the *integer*.  A combinator
parser already threads a position through every alternative, so recording, per
top-level statement, how far past its own extent the parse looked is nearly free, and
it is the sound invalidation criterion that a pure extent comparison lacks (§1.10).
The second takeaway is negative and worth stating in the roadmap: tree-sitter is the
system most often proposed as "just use an incremental parser", and for a
layout-sensitive Haskell-like language its layout story is a hand-written C scanner
and an open feature request.  The third is the perf datum in §1.11: the one team that
made tree-sitter-haskell fast did it by **deleting a parser-combinator layer**, not by
being more incremental.

### 1.2 Wagner & Graham (1998), and Wagner's thesis

TOPLAS 20(5):980-1013.  Berkeley URLs are dead; mirrors:
preprint <https://web.archive.org/web/2018/http://harmonia.cs.berkeley.edu/papers/twagner-parsing.pdf>,
thesis (UCB/CSD-97-946)
<https://web.archive.org/web/2019/https://www2.eecs.berkeley.edu/Pubs/TechRpts/1997/CSD-97-946.pdf>,
DOI <https://dl.acm.org/doi/10.1145/293677.293678>.

**They rejected state matching, which is what most people mean by "incremental
parsing".**  §4.1: "each node in the parse tree records this state when it is shifted
onto the stack… **Testing the validity of the lookahead is usually accomplished
through a conservative check** … One disadvantage of state matching is the space
associated with storing states in tree nodes.  State matching also restricts the set
of contexts in which a subtree is considered valid, since **the state-matching test is
sufficient but not necessary**… **the large number of similar distinct states …
practically guarantees that legal syntactic edits will not have valid state
matches.**"

The replacement is **sentential-form parsing**: "**For LR(0) parsers, the mere fact
that the grammar symbol associated with a subtree's root node can be shifted in the
current parse state indicates that the entire subtree can be incorporated without
further analysis**… no states are recorded in nodes; subtrees can be reused in any
grammatically correct context; and lookahead validation is accomplished 'for free' by
consuming the input stream."  And: "**the shift test is not only sufficient but also
necessary.**"  The right edge of a shifted subtree still has to be broken down,
because its shape depended on lookahead from outside.

**Identity** is a stable object with *versioned fields*: "Self-versioning documents
are built simply by using versioned objects for the edges (link fields) in document
nodes… **the nodes themselves retain their identity to simplify reference
maintenance.**"  Overhead: "less than 4% of its running time is attributable to
versioning… Recording a change to most versioned datatypes requires only 34
additional bits."

**The incremental lexer** is the part most relevant here: "optimal, taking **O(c + s
lg N)** steps… **The batch lexer is invoked the minimal number of times: once for each
token in the updated token stream whose contents, lookahead, or starting state may
have been modified.**"  Per-token *lookahead* — a character count — is harvested by
instrumenting the generated lexer's `next_char`.  Again: one integer per token.

**The result that matters for a module of top-level declarations.**  §7: "parse
'trees' are really linked lists in practice… **Depending on the form of the grammar,
modifying either the beginning or end of the program — both common cases — will
require time linear in the length of the program text even for an optimal incremental
parser.**"  Their fix is `*`/`+` meta-syntax expanded into balanced trees, with "the
environment should always rebalance modified sequences immediately before committing
the update".

**Cost model, and what they measured.**  "O(t + s lg N) time for t new terminal
symbols and s modification sites in a tree containing N nodes… **the location of the
changes does not affect the running time.**"  But the TOPLAS paper has **no evaluation
section, no table and no timing** — it substitutes a performance model.  The thesis
reports only overheads (versioning <4%; parsing 12-15% of total time, "**Most of the
remaining time was spent in constructing the nodes**"; incremental IGLR vs incremental
LR "**undetectable**").  The only real incremental-vs-batch numbers in this line of
work arrive twenty years later, in Diekmann's Eco (§1.4).

**Layout is explicitly out of scope**, thesis §C.3 fn.7: "**Haskell is non-trivial to
describe in a manner suitable for incremental analysis… The latter violates the
assumption that the original set of terminal symbols is mutually exclusive with the
set of whitespace tokens.**"

**What Ermine could take from it.**  Two things and a warning.  (a) The shiftability
test is the *necessary and sufficient* condition, and Lezer implements exactly it
(`parser.getGoto(stack.state, cached.type.id) > -1`, §1.3) — but it presupposes an LR
automaton Ermine does not have.  (b) The **balanced-sequence result is a direct hit**:
a module is a flat list of top-level statements, so *any* scheme that rebuilds the
list on every edit is linear in the module, and the only reason that is acceptable for
Ermine is that the list nodes are cheap compared to the statements' own trees.  (c) The
warning: the canonical citation for "incremental parsing works" contains no measured
speedup, and its author says layout-sensitive languages are outside the model.

### 1.3 Lezer / CodeMirror 6 — fragments, and a coarser reuse unit than expected

Design notes: <https://marijnhaverbeke.nl/blog/lezer.html>; guide
<https://lezer.codemirror.net/docs/guide/>.

Haverbeke's post is worth reading for one paragraph in particular, because it is about
exactly Ermine's parser technology:

> "This system is a marvel… But unfortunately, if I'm honest, **it is a tragically bad
> idea taken way too far.  Parsing expression grammars are parsed by backtracking.  And
> as such, they are very poorly suited for implementing a stateful tokenizer.  In a
> backtracking system, you never know when you've definitely parsed a piece of
> content — later input might require you to backtrack again.**"

**The reuse unit is a whole `Tree` object, and small nodes are never reused.**
Lezer stores nodes below ~1024 characters in flat `TreeBuffer` arrays: "**That does
mean that we can't reuse small nodes.  But since their size is limited, the amount of
work that is involved in re-parsing them is also limited.**"  Asked directly whether
buffers are ever broken up (<https://discuss.codemirror.net/t/granularity-of-incremental-parsing/9258>),
Haverbeke: "**It'll reuse `Tree` objects, but any `TreeBuffer` touched by the changes
is going to be re-parsed.  There's no way to associate data with nodes inside
TreeBuffers in any case, since there's no object identity for those.**"  Incremental
reuse is disabled outright unless the parse is longer than `bufferLength * 4`.

**`TreeFragment`** is the model: `{ from, to, tree, offset, openStart, openEnd }`,
where `from`/`to` are positions **in the updated document** and `offset` is "the
offset between the fragment's tree and the document… Add this when going from document
to tree positions."  `TreeFragment.applyChanges(fragments, changes, minGap = 128)`
splits and shifts fragments around edits — and an unchanged stretch shorter than
**128 characters between two edits is discarded outright**.  "Open" ends mean the
boundary fell inside a node the edit cut in half; `cutAt` walks outward to the first
non-error sibling boundary and then backs off a further `Lookahead.Margin` (= 25).

**The reuse predicate** combines four things: the candidate is a `Tree` (not a buffer
child), it starts exactly at the parse position, it lies inside `[safeFrom, safeTo]`,
its recorded `lookAhead` prop does not reach past the fragment, **and** the LR
automaton has a GOTO on its type in the current state (`parser.getGoto(stack.state,
cached.type.id) > -1`) — i.e. Wagner's shiftability test — plus context-hash equality
when a `ContextTracker` is strict.

**Layout costs a hash, and the hash can be wrong.**  `ContextTracker` "track[s]
stateful context (**such as indentation in the Python grammar**)"; "**By default, nodes
can only be reused during incremental parsing if they were created in the same context
as the one in which they are reused**"; "**you can't reuse a Python block if the
surrounding indentation is different**".  The context is compressed to one integer
stored on the node, and its author on collisions
(<https://discuss.codemirror.net/t/understanding-the-python-indent-tracker-hash-function/5351>):
"I am not very knowledgeable about hash functions… **it's just smashing together bits
to get values that hopefully won't clash**" and, asked what a clash does, "**That could
lead to an incorrect parse.**"

**The bug history is the real lesson.**  From the `lezer-parser/lr` changelog:
0.12.1 infinite loop "when repeatedly reusing a **zero-length** cached node"; 0.13.5
"**overeager reuse of nodes on change boundaries**"; **0.15.0** "**node reuse didn't
take the amount of look-ahead done by the tokenizer into account, and could reuse
nodes whose content would tokenize differently due to changes after them**"; 1.4.1
reuse when a node "ended in a repeat or optional part, and was followed by a sequence
of **skipped nodes longer than 25 characters**".  Haverbeke's narrative of the worst
one: "**if a tokenizer looked ahead beyond the token that it eventually produced (for
example a block comment tokenizer giving up when not finding the closing `*/` marker
…), that created a dependency on all parts of the input that the tokenizer looked at,
and this was not properly tracked.**"

No measured wins are published: "I haven't ran any direct comparison benchmarks."

**What Ermine could take from it.**  Three.  (a) `TreeFragment`'s `offset` field is
exactly the span re-anchoring §5(a) needs, and its shape — keep the old tree, keep a
delta, translate on access — is cheaper than rewriting spans.  (b) The `minGap = 128`
and `bufferLength * 4` thresholds are the honest admission that fine-grained reuse
does not pay: Lezer's own designers set a floor of ~1 KB below which re-parsing is
cheaper than deciding whether to reuse.  Ermine's mean top-level statement is ~245
bytes, which sits *below* Lezer's floor — a strong argument that sub-statement
incrementality would not pay here either, and a mild argument that even
per-statement caching should be measured before it is believed.  (c) The 0.15.0 bug is
the one Ermine would reproduce: `attempt` in `SurfaceParsers` is exactly "a tokenizer
that looked ahead beyond the token it produced".

### 1.4 Papa Carlo — a Scala incremental parser built on lexical fragments

<https://lakhin.com/projects/papa-carlo/>, announcement
<http://lakhin.com/blog/15.11.2013-handy-incremental-parser/>.  Worth a look because
it is the only Scala entry in this section.

The idea is fragments between paired tokens: "Before the syntax parsing stage parser
selects simple syntactical **Fragments between the pair of specific tokens**… **The
main property of the Fragment is that it's meaning … in context of language's syntax
should be invariant to it's content.**"  Declared as
`trackContext("{", "}").allowCaching`, with `.forceSkip` and `.topContext` for strings
and comments.  On an edit, "**FragmentController is responsible to determine which
Fragment was invalidated… Syntax parser is looking for the cachable named rule that was
applied to this fragment last time and applied it again.  If there were no such rule…
parser chooses enclosing fragment**", falling back to a root fragment covering the
file.

Measured, on a ~600-line JSON file: cold parse **270 ms**, subsequent edits **7-8 ms**
— about 35x, but from a very slow baseline, which the author concedes: "**it's
performance may be not as good on startup as of parsers generated with ANTLR.**"
Third-party assessment (Dubroy & Warth, SLE 2017 §5.1): "**it is not a true packrat
parser, as it only employs memoization in a limited way, and therefore does not
guarantee linear parse times.  The author of a grammar must manually define the syntax
of its code fragments… and ensure that 'their syntactical meaning [is] invariant to
[their] internal content'.**"

**What Ermine could take from it.**  The negative result is the useful one: the whole
scheme rests on **lexically recognizable, content-invariant nesting delimiters**, and a
layout-sensitive language has none — a fragment boundary would have to be computed by
the very layout algorithm the caching is meant to short-circuit.  Ermine is the
exception that proves the rule, because `StatementExtents` *is* a purely lexical
fragment finder for a layout language, verified against the real splitter over 180
files.  That is an unusual asset and it is what makes §5(a) possible at all.  Papa
Carlo also has no lookahead tracking; correctness rests entirely on a declared
invariance the author hedges with "at least in most cases".

**Hazel / structure editors**, briefly: the transferable idea is not the editor but the
*total* analysis — "Type systems typically only define the conditions under which an
expression is well-typed… **This approach is insufficient as the basis for language
servers**" (Zhao et al., POPL 2024).  Ermine's Stage 2 already implemented the
practical form of that (tolerant read, per-SCC error capture, "unchecked: depends on a
broken definition").  Structure editing itself is not a live option; even Hazel's own
usability study (tylr, TyDe 2022) reports participants "in general slowed by a number
of limitations".

### 1.5 IntelliJ — reparseable elements, and the identity-preserving fallback

IntelliJ's block-level re-parse (`ILazyParseableElementType` /
`IReparseableElementType`) is the industrial version of "re-parse only the enclosing
block".  Its `isReparseable` guard is lexer-level (brace balance plus "the closing
brace is the last token"), and the SDK's own caveat is the one that matters here:

> "**Indent-based languages.  You should know about parent indent in order to decide if
> block is reparseable with given text.  Because if indent of some line became equal to
> parent indent then the block should have another parent or block is not block
> anymore.  So it cannot be reparsed and whole file or parent block should be
> reparsed.**"

Two further facts.  IntelliJ **gives up** on the identity-preserving diff above ~100 KB
(`PARSE_INCREMENTALLY` guards), accepting loss of PSI identity rather than paying the
diff.  And its "slow path" is not a plain re-parse: `makeFullParse` parses the whole
file into a scratch tree and then **diffs it into the live tree** (`mergeTrees` →
`DiffLog`), so every surviving node keeps its handle.  No quantitative claim is
published beyond the javadoc's "This can speed up reparse dramatically."

**What Ermine could take from it.**  The parent-indent caveat is the exact statement of
the hazard for a layout language, and Ermine's answer to it is already built:
`StatementExtents` recomputes the layout column and every boundary *from the new text*
on each check, so a change that merges or splits statements shows up as a change in the
extent list rather than as a silently wrong reuse.  The `makeFullParse` + diff pattern
is the fallback design worth copying if statement identity ever needs to survive a
cache miss.

### 1.6 rust-analyzer — it implemented block reparse and does not use it

`docs/dev/syntax.md`, § Incremental Reparse, in full:

> "Green trees are cheap to modify, so incremental reparse works by patching a previous
> tree, without maintaining any additional state.  The reparse is based on heuristic:
> we try to contain a change to a single `{}` block, and reparse only this block.
> **To do this, we maintain the invariant that, even for invalid code, curly braces are
> always paired correctly.**
> **In practice, incremental reparsing doesn't actually matter much for IDE use-cases,
> parsing from scratch seems to be fast enough.**"

The two strategies are a single-token replacement (with three guards: a removed newline
may extend the previous token; the new token must have the same kind and must not be a
contextual keyword; and the next character must not merge with it) and a `{}` block
re-parse gated on `is_balanced`.  The reusable nonterminals are a **whitelist of ten**,
and `ASSOC_ITEM_LIST` needs to know its `parent` (`IMPL` vs `TRAIT`) — parse *context*
leaking into a supposedly context-free splice.

Two facts settle its status.  The salsa-tracked parse query is a **full** parse, and it
is `#[salsa::tracked(lru = 128)]` — rust-analyzer **evicts and re-parses trees as a
memory-management strategy**.  And the only non-test callers of `reparse` are two
*speculative* synthetic edits (`typing.rs`, `completion/context.rs`).

Its differential oracle is worth copying: `crates/syntax/src/fuzz.rs` asserts
descendant-by-descendant `(kind, range)` equality between incremental and full reparse
— with `assert_eq!(new_file.errors(), full_reparse.errors())` **commented out behind a
`// FIXME`**, i.e. an accepted divergence in diagnostics.

**What Ermine could take from it.**  The fuzz harness, and the judgement.  matklad,
who wrote both, is explicit (<https://lobste.rs/s/ws0mt8/>): "**You don't need
incremental parsing even.  Parsing from scratch is fast enough most of the time.  …
Incremental parser is helpful, but by no means it is table stakes.  What you need
though is resilient parser, a parser that can deal with incomplete syntax.  This is
table stakes**" — and, on their own block heuristic, "**rust-analyzer included more or
less the same block reparsing heuristic from the beginning, but, as far as I am aware,
it is not actually enabled still.**"  Ermine already has the resilient parser (5.1,
5.2, 5.2b); what it does not have is a fast one, which is §1.11.

### 1.7 Lean 4 — the snapshot tree, and the counterexamples that bound it

Sources: `src/Lean/Language/Lean.lean`, `Basic.lean`, `Lean/Types.lean`,
`src/Lean/Server/README.md`.  This is the closest published design to
"re-parse only the statements after the change and splice".

**Why it works at all**, from `Note [Incremental Command Elaboration]`: "**Because of
Lean's use of persistent data structures, incremental reuse of fully elaborated
commands is easy because we can simply snapshot the entire state after each command and
then restart elaboration using the stored state at the next command above the point of
change.**"  Ullrich's thesis puts the guarantee formally: "**As long as the environment
is implemented as a persistent data structure and all involved operations are pure, it
is guaranteed that this incremental approach is equivalent to reprocessing the file
from the beginning.**"

**The shape**: `SnapshotTree { element : Snapshot, children : Array (SnapshotTask
SnapshotTree) }`, with a Lean-specific chain `HeaderParsedSnapshot →
HeaderProcessedSnapshot → firstCmdSnap → CommandParsedSnapshot { stx, parserState,
elabSnap, nextCmdSnap? }`.  The advice for other languages is in the server README:
"**In languages with less strict ordering and less syntax extensibility, there may be a
single snapshot for the full syntax tree of the file, and then nested snapshots for
processing each declaration in it.**"

**The key is positional syntax equality on a prefix**: `if stx.eqWithInfo old.stx then
return (← unchanged old parserState)`, where `eqWithInfo` compares `SourceInfo`, i.e.
absolute offsets.  The authors know it is the weak form: "**While ideally we would
decide what can be reused … using strong hashes over the full state and inputs,
currently we rely on simpler syntactic checks.**"  There is no state check at all —
"**As there is no cheap way to check whether the `Environment` is unchanged, i.e.
*semantic* change detection is currently not possible, we must make sure to pass `none`
as all follow-up 'previous states' from the first *syntactic* change onwards.**"

**THE COUNTEREXAMPLES**, verbatim from Note [Incremental Parsing] — these are the
reason a naive "re-parse from the edit" is unsound in any grammar with backtracking:

> "one initial thought could be that a user edit can only invalidate commands at or
> after the location of the change.  **Unfortunately, that's not true; take the
> (partial) input `def a := b private def c`.  If we remove the space after `private`,
> the two commands syntactically become one with an application of `privatedef` to `b`
> even though the edit was strictly after the end of the first command.**"
> "**Unfortunately this is not sufficient either**, given `structure a where /-- b -/
> @[c] private axiom d : Nat` … **If we again delete the space after private, it becomes
> a syntactically correct structure with a single field `privateaxiom`!**  So clearly,
> **because of uses of `atomic` in the grammar, an edit can affect a command syntax tree
> even across multiple tokens.**"
> "What we did in Lean 3 was to always reparse the last command completely preceding the
> edit location… **This worked well but did seem a bit arbitrary**" — and then a
> docstring-backtracking case broke it, "**Thus we need to go up two commands.**"
> "**Finally, a more actually principled and generic solution would be to invalidate a
> syntax tree when the parser has reached the edit location during parsing.  If it did
> not, surely the edit cannot have an effect on the syntax tree in question.  Sadly such
> a 'high-water mark' parser position does not exist currently**… Thus we remain at 'go
> up two commands' at this point."

The motivating measurement: "**on mathlib we average 41ms parsing per 1000 LoC.  But
there are quite a few files >= 1kloc (up to 4.5kloc) in there, so near the end of such
files lag from always reparsing from the beginning may very well be noticeable.**"

Everything else in the design is guardrails.  Sub-command incrementality is an
**opt-in whitelist** (`@[incremental]`; exactly two commands and about a dozen tactic
combinators) because "**For unmarked elaborators, the corresponding snapshot bundle
field … is unset so as to prevent accidental, incorrect reuse.**"  Whitespace forced a
switch from range comparison to `eqWithInfo` after PR #4395, "fix: incremental reuse
leading to goals in front of the text cursor being shown", because a request handler
read whitespace out of the info tree.  Reuse must not skip side effects ("disable
incrementality for `diagnostics` as reuse would skip counter accumulation").  Reused
diagnostics must be *object-identical* or the client reloads its view.  And header
edits are not handled at all — the worker process calls `IO.Process.forceExit 2`,
because "**doing this safely is pretty much impossible.**"

**What Ermine could take from it.**  This entry is the single most transferable one,
in both directions.  The **positive**: Lean's model is exactly §5(a) — lexically split
the file into commands, reuse the unchanged prefix, re-do the rest — and the guarantee
it rests on ("persistent data structures + pure operations ⇒ equivalent to
reprocessing from the beginning") is a property Ermine's surface parse already has,
because `SurfaceParsers` builds immutable `SStatement` values from text with no
context beyond the layout column.  The **negative and more important**: the two
counterexamples are the exact failure mode a statement-extent cache must answer, and
Ermine's answer is *better than Lean's* — `StatementExtents.scan` recomputes every
boundary lexically from the **new** text on every check, so a deleted space that merges
two statements changes the extent list and both statements are re-parsed, whereas Lean
compares against the old command list and has to guess how far back to go.  What
Ermine still owes is Lean's stated wish: **the high-water mark**.  Ermine's `statement`
parser peeks past its own extent (`atLayoutBoundary` runs `skipTrivia` over the
following text) and uses `attempt` throughout, so "the text of this extent is
unchanged" is not by itself sufficient.  The good news is that in a combinator parser
the high-water mark Lean says "does not exist currently" is a one-field addition to
`ParseState`.

### 1.8 Merlin — the answer is "no, and it doesn't matter"

Bour, Refis & Scherer, ICFP 2018 <https://arxiv.org/abs/1807.06702>.

**Merlin does not partially re-parse.**  The Menhir incremental machinery is present
(`seek_step`, `resume_parse`), but the only caller passes `` `None ``, and the reader
phase is memoized on a **whole-file digest**.  The paper says why this is fine: "the
whole pipeline is incremental and can recompute a result from previous states and a
source change, but this source change may either be communicated by the editor itself
or **computed by Merlin from the entire new buffer (copying source text in memory is
not a performance bottleneck)**."

**What it reuses is the typing state, over a prefix of top-level items.**  §2.3.4:
"**Merlin considers the post-processed source a sequence of toplevel phrases, and saves
the typing environment for each prefix sequence of phrases.  After a buffer change …
Merlin will only re-type-check the phrase currently being edited.**"  The cache entry
is `{ parsetree_item; typedtree_items; part_snapshot; part_stamp; part_uid; part_env;
part_errors; part_checks; part_warnings }`, and `compatible_prefix` walks the two item
lists comparing with OCaml's polymorphic structural `compare` — which includes
`Location.t`, so **the key is positional**, exactly as in Lean.

Menhir's own design note is the one to keep, because it describes what a combinator
parser could do cheaply: "**States and checkpoints are purely functional: they can be
stored and reused at will.  In particular, we get incrementality by caching them,
indexed by token location: when a part of the buffer is modified, we can restart from
the last checkpoint before it.  There is a lot of sharing within parsing stacks …
keeping the memory usage close to non-incremental parsing.**"

**They tried linearization first and abandoned it**: "**the effort to linearize nesting
constructs was tedious, incomplete, and consuming more and more time … The development
and maintenance burden was much too important.**"  And the maintenance tax of splicing
into a mutable compiler is visible in their changelog — "Cleanup functors caches when
backtracking, to avoid memory leaks"; "Reset uid counters when restoring the typer
cache so that uids are stable across re-typing"; "a typer fix … that would **trigger
assertions linked to scopes bit masks when backtracking the typer cache**" — every one
of them "we forgot to restore some global".

**The design-space table** (§2.5, Fig. 1) places languages by two axes:

| | definition before use | forward references |
|---|---|---|
| definitions at toplevel | easy, linearized prefixes (**C**) | **medium, full linearized (Haskell, Erlang, Java)** |
| rich scoping structures | medium, fine-grained prefixes (**ML, Lisp**) | hard, full fine-grained (**Scala**) |

with the explanation: "**it is relatively rare for identifiers to be used before their
declaration [in ML]… In contrast, many languages, typically Haskell … rely on liberal
uses of recursion nests; the model of working only with definitions above in the buffer
does not lead to an acceptable user experience.  On the other hand, linearization works
much better in these languages**, that have a simple top-level structure with less
nesting."

**What Ermine could take from it.**  Three.  (a) Merlin's placement of Haskell-like
languages says **prefix reuse is the wrong shape for Ermine** — an Ermine module has
forward references everywhere, so "reuse everything before the cursor" buys nothing;
what fits is whole-buffer, position-independent per-declaration reuse, which is §5(a)
plus §5(b-lite).  (b) The checkpoint idea is the cheap combinator-parser analogue of
incremental parsing and it composes with the extent scanner: cache the immutable
`ParseState` at each top-level boundary and resume from the last one before the edit.
Ermine's `ParseState` is already a pure value that `statementFailure` constructs by
hand, so this is available today — though note that it only helps edits near the *end*
of the file, whereas per-statement caching helps everywhere.  (c) The `--no-cache` mode
and the "presence or absence of saved state does not modify results, only performance"
rule are the acceptance criteria Stage 4 should adopt verbatim.

### 1.9 Sorbet, Dafny, Kotlin, swift-syntax: what declaration-level reuse costs

- **Sorbet** fingerprints a changed file by running a **full parse and index of it in a
  scratch `GlobalState`**, per keystroke, purely to compute the hash.  Its fast path is
  not cheap in absolute terms; it is cheap *relative to re-checking the workspace*.
  The frequency data is the useful part: slow-path edits fell from **19 % to 10 %**, and
  within that, "**unrecoverable syntax error**" accounts for only **0.7 % of all edits**
  — "Arguably Sorbet is already quite good at recovering from syntax errors."  Its
  testing note: "incremental mode previously accounted for only 2% of all Sorbet tests.
  **We 4x'd that.**"
- **Dafny** is the strongest measured case for declaration granularity (Leino &
  Wüstholz, CAV 2015, <https://pm.inf.ethz.ch/publications/LeinoWuestholz2015.pdf>):
  per-entity checksums computed from the AST so they are "**insensitive to certain
  textual changes, such as ones that concern comments or whitespace**", plus dependency
  checksums; basic caching gives "**more than an order of magnitude for many
  sessions**" and fine-grained adds 17-42 %.  But the win comes from re-verification
  being three or four orders of magnitude more expensive than parsing.  Its cost is a
  `Migrator` that has to re-locate previously published diagnostics, with a known bug
  where the two position-tracking systems disagree (dafny#2523).
- **Kotlin K2** has the most careful predicate, and it is the one that disqualifies the
  easy version for Ermine: `isReanalyzableContainer` requires `hasBlockBody() ||
  typeReference != null`.  A declaration is body-local only if **its signature does not
  depend on its body** — see §2.4.
- **swift-syntax** does declaration-level reuse in production, at exactly two points
  (`parseMemberBlockItem`, `parseCodeBlockItem`), and its predicate is the high-water
  mark: `lookaheadLength = lexemes.lookaheadTracker.pointee.furthestOffset -
  offsetToStart(startToken)`, checked against every edit's range.  Its memory
  safeguard is worth flagging for a JVM port: "**Incremental parsing reuses subtrees
  from the previous tree by reference, which keeps each reused subtree's origin arena
  alive.  Over a long editing session this accumulates arenas … without bound.**"  And
  its live soundness bug, issue #3397, is the one a naive implementation reproduces:
  "**when that reused node is registered for (potential) reuse in the next incremental
  parse … its original lookahead range is not preserved**" — invisible to single-edit
  tests, found only by multi-edit sequences.
- **Eclipse JDT** offers the *dual*: "**in diet mode, any blocks like method bodies are
  skipped, which can later be filled in using dedicated methods**".  Do not parse
  bodies until asked.

**What Ermine could take from it.**  Sorbet's 0.7 % figure is the empirical answer to
"but the file is broken while the user types": with a resilient parser, unrecoverable
syntax errors are a rounding error, and Ermine already has the resilient parser.
swift-syntax's `furthestOffset` is the concrete implementation of the high-water mark,
and #3397 is the specific bug to write a test for: **a reused statement must carry its
recorded lookahead forward into the new cache**, not merely be checked against it once.
JDT's diet parse is the option nobody on this roadmap has considered and it is cheaper
than everything else here — but it does not apply, because Ermine's inference needs the
bodies.

### 1.10 The convergent invalidation criterion, and why it is cheap in a combinator parser

Five independent systems arrived at the same rule, under five names:

| System | Name | What it records |
|---|---|---|
| tree-sitter | `lookahead_bytes` | bytes examined past the node |
| Wagner & Graham | per-token lookahead | characters examined past the token |
| Lezer | `NodeProp.lookAhead` | distance past the node (stored only when > 25) |
| swift-syntax | `lookaheadTracker.furthestOffset` | high-water mark minus node start |
| Ohm (incremental packrat) | `maxExaminedPos` / `examinedLength` | furthest position examined, **relative** |

Ohm's definition is the sharpest, and it explicitly covers backtracking
(<https://ohmjs.org/pubs/sle2017/incremental-packrat-parsing.pdf> §3.1.3): "**An input
position is examined when either (a) the character at that position is consumed, or (b)
the value of the character is used to make a parsing decision.** … the examined
interval … **contains all of the characters that could have influenced the result of
parsing that rule.** … **The memo table entry should be invalidated if and only if the
edit operation affects that portion of the input.**"  And §3.3: "**Our solution … is to
make the individual memo table entries position-independent, so that they can be
relocated at no extra cost.  To do this, we replace the `nextPos` property … with a
relative offset, which we call `matchLength`.  Similarly, the examined interval … is
stored as `examinedLength`.**"

Ohm's measurements, on a 279 KB / 4761 SLOC JavaScript file replaying 891 recorded real
keystrokes: initial parse 1483 ms; **subsequent parses mean 6.2 ms, median 4.7 ms** —
"roughly two orders of magnitude" faster than the non-incremental packrat, and faster
than the hand-optimized non-incremental Acorn (mean 23.7 ms).  Memory: "**The mean
additional memory usage for the memo table is 11.5%.**"  GPeg (SLE 2021,
<https://people.seas.harvard.edu/~chong/pubs/gpeg_sle21.pdf>) improves the table to an
interval tree, reporting "sub-5ms reparse times" across tens to thousands of KB.

**What Ermine could take from it.**  This is the *mechanism* recommendation of the whole
section.  Ermine does not need a memo table, an LR automaton, or a GLR engine to make
per-statement reuse sound.  It needs **one integer per top-level statement**: the
furthest input offset the parse of that statement examined.  A combinator parser
already threads the offset through `ParseState`, so recording a per-run maximum is a
`var` and one `max` in the primitive that advances position — the same shape as
`lookaheadTracker` in swift-syntax and `maxExaminedPos` in Ohm, and precisely the thing
Lean's note says "does not exist currently and likely could at best be approximated".
With it, the reuse rule is exact: **reuse statement *i* iff no edit intersects
`[start_i, start_i + examinedLength_i)`.**  Without it, the rule is a heuristic of the
Lean-3 kind, and the counterexamples in §1.7 say heuristics of that kind break.

### 1.11 The skeptics, and the constant-factor alternative

The strongest argument against everything in this section comes from the people who
built the systems in it.

- matklad, <https://lobste.rs/s/ws0mt8/>: "**You don't need incremental parsing even.
  Parsing from scratch is fast enough most of the time.  IntelliJ doesn't generally do
  incremental parsing, and yet it has full access to syntax tree all the time.**" …
  "**you don't need to invent a general incremental parsing algorithm, a simple
  heuristics work and it doesn't actually require modifying the parser itself much.**"
- matklad, *Three Architectures for a Responsive IDE*
  (<https://rust-analyzer.github.io/blog/2020/07/20/three-architectures-for-responsive-ide.html>):
  "**it's not the incrementality that makes an IDE fast.  Rather, it's laziness — the
  ability to skip huge swaths of code altogether.**"
- matklad, *Against Query Based Compilers* (Feb 2026,
  <https://matklad.github.io/2026/02/25/against-query-based-compilers.html>): "**push
  the need for queries as far down the compilation pipeline as possible, sticking to
  more direct approaches.  Not doing queries is simpler, faster, and simpler to make
  faster.**"  His recommended architecture is declaration-level splice **at the summary
  level**: "In parallel, a 'summary' is extracted from each file… **This phase is
  re-run whenever a summary of a file changes.  Conversely, changes to the body of any
  function do not invalidate resolved signatures.**"
- On the other side, an ex-JetBrains commenter: "**Without it you wouldn't be able to
  get the snappiness that IntelliJ has even in modest files**" — and Diekmann's thesis
  measured a *compiled* batch Rust parser exceeding 100 ms on Java-stdlib files, so
  "batch is fast enough" is a claim about a constant factor, not a law.

**The framing worth putting in the roadmap** is this pair.  Nelson Elhage, *Reflections
on software performance* (<https://blog.nelhage.com/post/reflections-on-performance/>):
"**Sorbet doesn't have to go to extreme lengths to save work, because it's often fast
enough to just do the work instead.**"  Jake Zimmerman's rejoinder
(<https://blog.jez.io/making-sorbet-more-incremental/>): "**after about 5 years of
codebase growth, the base-case performance had slowed to a point where it was no longer
fast enough to just do the work.**"

**And the constant-factor datum that is closest to Ermine's actual situation.**
`tree-sitter-haskell`'s scanner was a C++ parser-combinator library with the same
profile shape as Ermine's — allocation inside combinator plumbing dominating.  Owen
Shepherd, <https://owen.cafe/posts/tree-sitter-haskell-perf/>: "Inserting a character
was taking a ridiculous amount of time.  **On some buffers, it took half a second.**" …
"**Aaaand it was malloc.  Something in the lexer was calling malloc.  A lot.**" …
inlining the combinators took the benchmark from 1.06 s to 0.29 s (3.65x), "removal of
all parser combinators … brought the (maximum tested) speedup to **48.2x**", and the
C++→C port reached **52.8x**.

**What Ermine could take from it.**  PERF-ROADMAP's P5(c) already names the same target
— "The `Free` trampoline — 52.6 %, and it is architectural" — and P5(d) already tried
and reverted one localized fix.  The tree-sitter-haskell result is the strongest
available evidence that the localized-fix approach was the wrong shape and that the
win, if there is one, is in *removing* the combinator indirection rather than tuning it.
It is also the only intervention in this whole survey with **zero correctness risk to
the batch path** if it preserves behaviour, and it is a prerequisite for measuring
whether §5(a) is worth its complexity: if the parse of a 245-byte statement drops from
2.2 ms to 0.05 ms, the read stops being the target and the ranking in §5 changes.

### 1.12 The five obligations of splicing trees

Every implementation surveyed had to build all five.  Any Stage-4 item that splices
must budget for them:

1. **A guard function sound with respect to the *lexer*, not the parser** — and
   conservative, because a wrong `true` is a silent wrong-tree bug.
2. **Re-entrant parser entry points with their context assumptions made explicit** —
   rust-analyzer's `ASSOC_ITEM_LIST` needing its parent; IntelliJ's parent-indent rule.
3. **Reuse-guard metadata that survives being reused** — swift-syntax #3397.
4. **A differential oracle against full parse, plus a multi-edit fuzzer** —
   rust-analyzer's `fuzz.rs`; Sorbet's 4x test expansion.
5. **Resource bounds** — swift-syntax's periodic forced full re-parse, because
   reference-based reuse pins every superseded tree.
## 2. Stable identity across runs

The question each entry answers: **(i)** what is the unit of reuse, **(ii)** what is
the key, **(iii)** how are cross-unit references made stable, **(iv)** how are
fresh-variable supplies handled so they do not poison caching.

### 2.1 rust-analyzer + salsa — the split that names the whole problem

**(i)** Two units on either side of one seam: the `ItemTree` (one per file) and the
`Body` (one per `DefWithBodyId`).

> "A simplified AST that only contains items… One important purpose of this layer is
> to provide an **'invalidation barrier'** for incremental computations: when typing
> inside an item body, the `ItemTree` of the modified file is typically unaffected,
> so we don't have to recompute name resolution results or item data."
> — `crates/hir-def/src/item_tree.rs`

> "**The core invariant we maintain is 'typing inside a function's body never
> invalidates global derived data'.**" — `docs/dev/architecture.md`

**(ii)** `ErasedFileAstId`, a packed u32 of `(16-bit name hash, 11-bit index, 5-bit
kind)`, and the doc comment is the single best statement of why:

> "it enumerates all items in a file and uses the position of an item as an ID. That
> way, IDs don't change unless the set of items itself changes… if you invalidate the
> ID of a struct, and that struct has an impl (any impl!) this will cause the `Self`
> type of the impl to invalidate … **which is pretty much the worst thing that can
> happen incrementality wise.** So we want these IDs to stay as stable as possible.
> **For top-level items, we store their kind and name, which should be unique, but
> since they can still not be, we also store an index disambiguator.  For nested
> items, we also store the ID of their parent.**" — `crates/span/src/ast_id.rs`

The disambiguator counter is *per `(kind, name-hash)`*, not global —
`FxHashMap<(ErasedFileAstIdKind, u16), u32>` — and the traversal is breadth-first
"so that parents get lower ids than children… adding a new function to a trait does
not change ids of top-level items, which helps caching".  Inside a body, identity is
a **per-body arena index** (`exprs: Arena<Expr>`, `bindings: Arena<Binding>`), so an
edit in body A cannot renumber body B.

**(iii)** `InFile<T> = (HirFileId, T)`, and — the part that matters most for Ermine —
**spans themselves are anchored, not absolute**:

```rust
pub struct Span {
    /// The text range of this span, relative to the anchor.
    /// We need the anchor for incrementality, as storing absolute ranges will require
    /// recomputation on every change in a file at all times.
    pub range: TextRange,
    pub anchor: SpanAnchor,   // { file_id, ast_id }
    pub ctx: SyntaxContext,
}
```

**(iv)** No fresh-variable supply in the classical sense.  Item identity is
`(kind, name-hash, scoped disambiguator)`; body-node identity is an arena index; the
salsa interner turns structural keys into dense integers — "When you create two
interned structs with the same field values, you are guaranteed to get back the same
integer id."

Two salsa mechanisms worth naming separately.  **Durability**: "Typically 'high
durability' values are things like data read from the standard library or other
inputs that aren't actively being edited"; in code, `if source_root.is_library {
Durability::HIGH } else { Durability::LOW }`.  **The firewall query**:

```rust
#[salsa::tracked(lru = 512, returns(ref))]
pub fn with_source_map(db, def) -> (Arc<Body>, BodySourceMap) { ... }
#[salsa::tracked(returns(deref))]
pub fn body(db, def) -> Body { Self::with_source_map(db, def).0.clone() }
```

A whitespace edit changes the source map; the projected `body` **backdates** ("we
mark a value that was computed in revision R as having last changed in some earlier
revision"); inference does not re-run.

**What Ermine could take from it.**  This is the closest structural match to the
Ermine question, and it answers it in a way that is *cheaper* than the "stable binder
identity" the roadmap parked.  The `ItemTree`/`Body` seam maps onto Ermine's existing
split between the module-level head set (which `scopeKey` already covers) and each
group's own text (which the per-group fingerprint already covers).  Two concrete
transfers: (a) `AstId = (kind, name, disambiguator)` is exactly what the extent
scanner can compute today — `StatementExtents.Extent` already yields `headWord`, and
`TolerantCheck.keys` already groups by it, so the disambiguator is the ordinal within
that group; (b) **anchored spans** are the direct answer to the start-line component
of the 5.5 fingerprint, and the `Span` comment above is a verbatim statement of why
absolute positions are the wrong thing to store.  The firewall/backdating pattern is
the third: split the position-bearing part of a cached result out of the value that
dependents hash.

### 2.2 IntelliJ PSI stubs — identity by index, and a file-local string table

**(i)** The per-file serialized stub tree.  "A stub tree is a subset of the PSI tree
for a file; it is stored in a compact serialized binary format… Switching between the
two is transparent."  Bodies are excluded (they are `ILazyParseableElementType`
chameleons), which is why a body edit costs nothing.

**(ii)** For the tree: the file plus a schema version, under a purity rule stated
twice in the SDK docs — "**It is critical to ensure that all information stored in
the stub tree depends only on the contents of the file for which stubs are being
built.**"  For an element: **the pre-order index in the flattened stub list**
(`((ObjectStubBase<?>)root).id = result.size();`).  The persistent handle carries no
name at all: `PsiAnchor.StubIndexReference = (VirtualFile, Language, IElementType,
index)`, with the element type acting as a checksum on restore.

Invalidation compares the **derived artifact**, not the source:
`if (treesAreEqual(newSerializedStubTree, myCurrentTree)) return false;` — no index
update when the stub bytes are unchanged.  That is IntelliJ's early cutoff.

**(iii)** References are never stored resolved.  A stub index maps `key → file →
StubIdList`; resolution re-queries by name.  Object identity survives GC via
`SpineRef` (owning file + integer index), and `syncPsiWithStub` re-binds new tree
nodes to cached PSI objects rather than making duplicates; a mismatch raises
`STUB_PSI_MISMATCH` and rebuilds.

**(iv)** IntelliJ *has* a global counter (`IElementType.myIndex = size++`, class-load
order dependent) and routes around it with two firewalls: element types persist as
`getExternalId()` **strings**, and strings inside a stub tree get a **file-local
enumeration** allocated 1,2,3… in first-encounter order and shipped with the unit
(`FileLocalStringEnumerator`).  That is what makes two runs over the same bytes
produce byte-identical stubs — the precondition for `treesAreEqual`.

**What Ermine could take from it.**  The file-local enumeration is the cheapest
possible form of the "stable id" idea and it is exactly what `Renamer.S.nextId`
already almost is: a per-run counter starting at 0, deterministic given the same
text.  The only change needed to make it *stable under edits elsewhere* is to reset
it per top-level statement instead of per file.  And `treesAreEqual` is the pattern
Ermine's inference cache already implements one level up: compare the derived
artifact, not the source.

### 2.3 Roslyn — structure as identity, and a path for symbols

**(i)** Green subtrees (finest), `SyntaxTree`, and the bound `SemanticModel` of one
method body.

**(ii)** Green nodes are keyed by *structure*, interned on `(RawKind, NodeFlags,
reference-identical children)`, and they deliberately store **width, not position**:
"Crucially, green nodes do **not** store: **Absolute positions** … **Parent
pointers**… This design choice is fundamental. Everything else flows from it."  Red
nodes are `(green, parent, position)` façades, thrown away on every edit.

Across compilations, identity is `SymbolKey`: a structural name-and-signature path
from the assembly root.  Its documented limits are worth quoting because they are the
limits of *any* name-path scheme: ambiguity is normal ("class C { int M(); bool M();
} The SymbolKey for both 'M' methods will be the same" → `CandidateReason.Ambiguous`),
it cannot name interior symbols of a speculative model, it is "not guaranteed to work
across different versions of Roslyn", and it is versioned (`FormatVersion = 7`).

**(iii)** `SymbolKey.Resolve(compilation)`.  Within a file across versions, the IDE
matches body nodes by a **child-index path from the root**, guarded by
`IsEquivalentTo(topLevel: true)`; the body-edit fast path is a version stamp that
does not advance:

```csharp
var topLevelChanged = TopLevelChanged(oldTree, oldText, newTree, newText);
var version = topLevelChanged ? newVersion : oldVersion;
```

**(iv)** Three answers, none a counter.  Green nodes need no id (identity *is*
structure).  Method type parameters use a **binder-relative de Bruijn coordinate**:
push the enclosing method onto a stack, write `(methodIndex = depth, symbol.Ordinal)`.
Locals and labels get `(container key, kind, name, n-th occurrence of that
(kind,name))` — a derived ordinal, "resilient to basic forms of edits… However, it
may not find a matching symbol in the face of other sorts of edits".  The one real
counter (`SymbolKeyWriter._nextId`, for back-references) is pooled and reset per key.

**What Ermine could take from it.**  Two.  First, "store width, not position" is the
same lesson as rust-analyzer's anchored spans, arrived at independently, and it is
the single change that would let a cached statement — or a cached inference result —
survive an edit *above* it.  Second, the de Bruijn coordinate for type parameters is
the shape a stable `V` id would take if one is ever wanted: not a hash of a path, but
`(binder path, ordinal within binder)`, which is total, collision-free by
construction, and needs no probing.

### 2.4 Kotlin FIR / Analysis API — and the rule that disqualifies Ermine's easy case

**(i)** A **declaration resolved to a phase** (lazy, per-declaration, in-place under
a `@Volatile resolveState`), the `FileStructureElement`, and the `KaModule` — "Modules
are also the Analysis API's unit of modification."

**(ii)** In-session, raw object identity.  Across sessions, **path-like names**:
`ClassId` (package FQN + relative class name) and `CallableId`.  The bridge is
`KaSymbolPointer` — "A pointer is necessary because `KaSymbol`s cannot be shared past
the boundaries of the `KaSession` they were created in" — with concrete subclasses
storing a `ClassId`, a `CallableId`, an owner pointer plus a scope search, an IntelliJ
smart pointer, or `KaBaseUnrestorableSymbolPointer`, which always returns null.
Overloads are disambiguated by `hasTheSameSignature`.  Note the *absence* of any
index-in-parent scheme: positional identity is delegated to smart pointers or refused.

**(iii)** Sessions are soft-referenced and die with their module; references are
re-established by re-running the `ClassId`/`CallableId` lookup.  The name is the wire;
the object is disposable.

**(iv)** Fresh type variables are minted per candidate per call site, but they are
strictly intra-phase: `FirCallCompletionResultsWriterTransformer` writes the
substituted concrete types back into the FIR before the phase closes.  **Kotlin does
not stabilize its gensym; it makes the counter's lifetime shorter than the cache
entry's lifetime.**

**THE FINDING THAT MATTERS MOST FOR ERMINE.**  Kotlin's in-block predicate is:

```kotlin
private fun KtNamedFunction.isReanalyzableContainer(): Boolean = hasBlockBody() || typeReference != null
private fun KtProperty.isReanalyzableContainer(): Boolean = typeReference != null && !hasDelegateExpressionOrInitializer()
```

A declaration is body-local **only if its signature does not depend on its body**.
`fun f(): T { ... }` qualifies; `fun f() = expr` does not, because editing `expr`
changes `f`'s type and therefore every caller.  Ermine infers top-level types from
RHSs, so on this rule **almost no Ermine edit is "in-block"** at the syntax level.

**What Ermine could take from it.**  The consequence is precise and it *validates the
5.5 design*: Ermine's fast path cannot be "splice the tree and stop"; it must be
"re-parse and re-infer this group, and stop propagating only if its *inferred type*
is unchanged".  That is what the 5.5 fingerprint chain already does — a group's key
includes the fingerprints of the groups it references, so a change in an upstream
RHS reaches everything downstream.  Kotlin's rule also says why an explicit signature
is worth something to the cache: a signed group is a real invalidation barrier, and
Ermine's `es`/explicit-binding path already treats it as one.

### 2.5 Spoofax / Statix — unstable ids, tolerated by controlling every channel

This one contradicts the assumption in the brief, and the contradiction is the useful
part.

**(i)** The **compilation unit** in a hierarchical tree (project → package → file),
each with its own local scope graph plus shared scopes with its parent.  The reused
artifact is a triple: previous local scope graph, recorded non-local query set,
type-checker result.  "a type-checker result is determined completely by the AST of
the compilation unit, and the results of external name lookups.  Thus, a
type-checker result can be reused if its AST and external name lookups do not
change." (Zwaan, van Antwerpen & Visser, OOPSLA 2022,
<https://aronzwaan.github.io/assets/oopsla22-extended.pdf>)

**(ii)** **Scope identities are NOT deterministic.**  "**the scope generation
function FreshScope in fact creates non-deterministic identities.** For example, the
scope modeling a class might have identity 𝑠0 in G𝑛−1, but 𝑠1 in G𝑛." (§7)  A scope
is `(resource, name)` where `name` is `base + "-" + counter++` from a per-solver-state
counter.  The spec promises only distinctness, and the paper is explicit that the
diff-and-patch machinery exists *because* of that: "Scope graph diffing and result
patching are only required for type-checkers that generate non-deterministic scope
identities.  Type-checkers for which scope identities are deterministic can just use
the algorithm as presented in Fig. 8."

**(iii)** A four-stage pipeline: recorded **non-local residual queries** as the
dependency edges; **environment diffing** to answer "did this query's answer change?"
without re-running it; **scope-graph diffing** — an admitted greedy approximation to
graph isomorphism, seeded from shared scopes, where "matched scopes must always have
the same owner and data", and "**when an incorrect match is chosen, the incremental
algorithm is less precise, but not unsound**"; and a **patch substitution** applied to
the reused graph, query set and result.  The soundness argument is one sentence:
"**type-checkers can only obtain references to non-local scopes via paths in query
answers.**  Therefore, collecting patches for all scopes in an answer to a previous
query is sufficient."

**(iv)** Three per-unit counters (`freshScope`, `freshVar`, `freshWld`), none
stabilized.  Unification variables never escape the unit; scope ids do escape and are
handled by post-hoc alignment plus substitution.

**What Ermine could take from it.**  The general theorem: **you can tolerate unstable
ids across runs iff you control every channel by which an id crosses a unit
boundary.**  Ermine already relies on exactly this without saying so — the 5.5 cache
splices a previous run's `Type` into the current run, and that is sound because a
generalized scheme is closed and the global `Supply` guarantees non-collision.  Where
it is *not* sound is any artifact with free variables the current run must also hold,
which is why lowered trees are excluded.  Stating the invariant in the roadmap in
Statix's terms — "an id may cross a run boundary only inside a closed artifact" —
would make the boundary of the 5.5 design explicit rather than folkloric.  The second
transfer is the overload fix: where a key cannot distinguish two things, **enrich the
datum until it can** — Statix put syntactic argument types into the declaration
scope's datum; Kotlin uses `hasTheSameSignature`; Roslyn folds full signatures into
`SymbolKey`.  Ermine's analogue is that `headWord` alone is not a key for a group in
a `private`/`database` block, which is why `ScopeWords` currently drops the whole
cache for those.

### 2.6 Lean 4 — the counter is part of the snapshot

**(i)** Three nested granularities, all typed as snapshots: header, command, and
within-command (definition headers, bodies, individual tactic steps).  Reuse is
**opt-in per elaborator** (`@[incremental]`).

> "**Because of Lean's use of persistent data structures, incremental reuse of fully
> elaborated commands is easy because we can simply snapshot the entire state after
> each command and then restart elaboration using the stored state at the next
> command above the point of change.**" — `Note [Incremental Command Elaboration]`,
> `src/Lean/Language/Lean.lean`

**(ii)** Positional syntax equality on a **prefix chain**:
`if stx.eqWithInfo old.stx then return (← unchanged old parserState)`, where
`eqWithInfo` compares `SourceInfo`, i.e. absolute offsets.  The authors know this is
the weak form: "While ideally we would decide what can be reused… using strong hashes
over the full state and inputs, currently we rely on simpler syntactic checks", and
"In the future, the 1-element history `old?` may be replaced with a global cache
indexed by strong hashes."

**(iii)** `Name`s in the environment, no stamps.  The work goes into keeping
*generated* names stable, and the stated motive is cache invalidation: "we further
specify the context name down to be unique per declaration so that the numeric scopes
are not influenced by the elaboration of preceding declarations.  This helps both with
ensuring declaration names are more stable… as well as making exported information in
general more stable, **avoiding rebuilds under the module system.**"  The macro-scope
`<uniq>` is a **content hash** of the declaration name or command text, with a
deterministic linear probe on collision.

**(iv) This is the entry that answers the brief's question head-on.**
`NameGenerator` (`{ namePrefix := `_uniq, idx := 1 }`) feeds every `FVarId`/`MVarId`,
and **it is a field of the snapshotted state** — `ngen : NameGenerator` lives in both
`Core.State` and `Command.State`.  Restarting from a snapshot restarts the counter at
the same value: "if reuse is possible, `reusableResult?` should be set to the previous
result and state, **ensuring that the state after running `withRestoreOrSaveFull` is
identical in both runs.**"  Where full state comparison is unavailable, the counter is
literally part of the cache key: `guard <| state.term.meta.core.nextMacroScope ==
nextMacroScope`.  Under parallelism the supply becomes **path-derived**:
`mkChild g = ({ namePrefix := Name.mkNum g.namePrefix g.idx, idx := 1 }, …)`, so a
forked name is `_uniq.<parentIdx>.<childIdx>` — a path in the fork tree.
`DeclNameGenerator`, which names aux declarations that *do* escape into the
environment, carries `parentIdxs : List Nat` and `withDeclNameForAuxNaming` "resets
the nested counter".

**What Ermine could take from it.**  Lean's answer to "fresh ids make caches
unmixable" is **not** to make ids path-derived everywhere; it is to *snapshot the
supply along with the state*, so that a reused prefix and a fresh continuation agree
by construction.  For Ermine that translates directly: if per-statement rename+lower
caching is ever wanted, the cheapest correct scheme is not a global path-hash but
`Supply.split` per statement, with the split recorded in the cache entry — the
`Supply` class already has `def split: Supply`, and it is the same mechanism as
`mkChild`.  The second transfer is the parallel one: if the worker-thread fork is
taken, `mkChild`-style splitting is what keeps ids deterministic across threads, and
is strictly better than the current shared `Supply` (see §3.9 and the
`-Dermine.loadInSeries` note).

### 2.7 Merlin — restore only the supplies whose values escape

**(i)** A **prefix of top-level structure items**.  Merlin does not diff and patch a
typedtree; it re-typechecks from a saved typing state.  "**This snapshot feature
proved enough for most needs: after a buffer change, Merlin restarts typing from the
last snapshot before the change.**" (ICFP 2018, <https://arxiv.org/pdf/1807.06702>,
§3.3)  Each cached item stores the parsetree item, the typedtree items, a unification
trail watermark, an ident stamp, a uid, the environment, errors, delayed checks and
warnings.

**(ii)** An MRU of five typers keyed on `(filename, directory, flags, config)`, then
the longest prefix whose parsetree items are structurally equal
(`compare ritem.parsetree_item pitem = 0`).  Parsetree items embed `Location.t` with
absolute `pos_cnum`, so **the key is positional**, exactly as in Lean.

**(iii)** `Ident.Global of string` carries **no stamp** — cross-unit references are by
name, which is what makes `.cmi` loading order-independent.  Cross-unit *declaration*
identity is `Shape.Uid.Item { comp_unit : string; id : int }`, serialized into `.cmt`.

**(iv) The finding.** `Local_store` — written by the Merlin authors and upstreamed
into OCaml — snapshots global compiler state wholesale, but the **rewind is
selective**:

```ocaml
  Btype.backtrack snap';                     (* undo unification via the trail *)
  Env.cleanup_functor_caches ~stamp:stamp';  (* evict entries stamped > watermark *)
  Shape.Uid.restore_stamp uid_stamp';        (* the ONLY counter actually rewound *)
```

| Supply | Escapes? | On rewind | Why |
|---|---|---|---|
| `Shape.Uid.id` | **yes** (into `.cmt`) | **restored exactly** | must be a function of the unit's own text |
| `Ident.currentstamp` | no (locals only) | not restored; used as an **eviction watermark** | equality only asked within one run |
| `Types.new_id` | no | not restored; watermark only | the undo log handles semantics |

The rule, stated as a rule: **restore precisely those supplies whose values leak into
cached artifacts; leave the rest monotone and use them as epoch watermarks.**

And the correctness discipline worth copying verbatim: "**The important property to
ensure is that the presence or absence of saved state does not modify Merlin's
results, only its performance.**  In fact, Merlin does provide a short-running mode
that does not use any cache."

**What Ermine could take from it.**  Two things.  (a) The supply taxonomy answers the
roadmap's identity question with a *test* rather than a design: before building
anything, ask which supplies' values reach a cached artifact.  Today the answer is
"none, because only closed types are cached", which is why 5.5 works — and it is the
thing that would change the moment lowered trees were cached.  (b) The `--no-cache`
mode is the acceptance criterion Stage 4 should adopt: a flag that disables every
reuse path, with a corpus property asserting byte-identical diagnostics with and
without it.  `TestTolerantRead`'s 180-file agreement property is the same idea one
level down and is the obvious place to put it.

### 2.8 GHC + haskell-language-server — hash the interface, not the implementation

**(i)** Whole module for recompilation; per declaration for *invalidation*.  "**Why
the convoluted way?  Hashing individual declarations allows us to do fine-grained
recompilation checking for home package modules, which record precisely what they use
from each module.**" (`GHC/Iface/Recomp.hs`)  A finalised interface carries
`mi_decls :: [(Fingerprint, IfaceDecl)]`, `mi_mod_hash` ("Hash of the ABI only"),
`mi_exp_hash`, `mi_orphan_hash`, and `mi_hash_fn :: OccName -> Maybe (OccName,
Fingerprint)`.  Note that `mi_usages` — the dependency record — is deliberately
*excluded* from the module's own hash: "changing usages doesn't affect the hash of
this module".

**(ii)** `(Module, OccName)` — never a `Unique`.  The serializer is overridden so
that a decl's fingerprint depends on the *hashes* of the external names it mentions:

```haskell
-- | Used when we want to fingerprint a structure without depending on the
-- fingerprints of external Names that it refers to.
putNameLiterally bh name = assert (isExternalName name) $ do
    put_ bh $! nameModule name
    put_ bh $! nameOccName name
```

with the crucial asymmetry: "**we need to be careful to distinguish between
serialization of binding Names… and non-binding: only in the non-binding case should
we include the fingerprint**" — which *is* alpha-invariance at the top level.  Path
identity is semantically load-bearing, not merely convenient: the ABI includes the
full name "(inc. module and package, **because these are used to construct the symbol
name by which the identifier is known externally**)".

**(iii)** `usg_entities :: [(OccName, Fingerprint)]`, "Entities we depend on, sorted
by occurrence name and fingerprinted".  Three-stage check: ABI hash unchanged ⇒ stop;
else the export-list summary (**names only, types ignored** — a deliberately coarse
pre-filter); else per-entity `checkEntityUsage`.  Home-package modules get the fine
check; package modules get only the ABI hash, "safe but may entail more
recompilation".

**(iv)** Four firewalls around a genuinely nondeterministic supply.  "The order of
allocated `Uniques` is not stable across rebuilds… **When you add parallelism this
makes `Uniques` hopelessly random**" and "**To prevent from accidental use the Ord
Unique instance has been removed.**"  So: (1) the `NameCache` re-interns, so each
external name has one agreed `Unique` per invocation; (2) fingerprints never see a
`Unique`; (3) canonical sorting wherever a `UniqFM` is traversed; (4) generated names
are content-derived.

**The recursive-group recipe**, which is directly applicable to SCC keying: sort the
group's declarations by name → give each a sequential fingerprint 0,1,2… → hash the
group → member hash = `hash(group_fingerprint, i)`.  This exists because of #18733,
where two mutually recursive types received the *same* hash and, in GHC's own words,
the bug "lurked for many years before being uncovered".

**The cautionary tale** is the exact failure mode Ermine is trying to avoid: "Prior
to GHC 6.12, dictionary functions were named something like `M.$f23`… **Worse, the
numbers are assigned non-deterministically, so simply recompiling `M` without changing
its code could change the fingerprints.**"  The fix was content-derived names
(`$fOrdInteger`) and a depth-first walk "starting from the exports sorted by name".
The exception proves the rule: `mkLocalOcc` *does* embed a `Unique`, and is used only
for names that never reach an interface.

On the HLS side, `hls-graph` "drops all the persistency features", its `Key` is an
interned `Int` — safe only because nothing is serialized — and early cutoff is
content-addressed, joined to GHC by `hirIfaceFp = fingerprintToBS . getModuleHash $
hirModIface`.  **GHC's ABI hash is the IDE graph's content address.**

**What Ermine could take from it.**  The closest analogue to the 5.5 cache in the
whole survey, and it validates its shape while suggesting three refinements.  (a)
GHC's decl fingerprint is over the *structure with binder names excluded and
non-binder names replaced by their hashes* — the structural version of what Ermine
approximates with source text.  Moving from text to a structural hash of the lowered
group would make the cache survive comment and whitespace edits, which today
invalidate it.  (b) The recursive-group recipe is a live hazard for Ermine's SCC keys:
`fpOf` hashes `sps.sorted ::: texts ::: upstream`, so two members of one SCC get the
*same* key by construction — harmless today because the entry stores a `Map[String,
Type]` for all of them, but exactly the shape of #18733 and worth an adversarial test
that transposes occurrences within a group and asserts the fingerprint changes.  (c)
`mi_usages` being outside the module's own hash is the principle behind not putting
positions in a key that dependents consume.

### 2.9 Zinc and the Scala 3 presentation compiler — the nearest neighbour

**Zinc (i)** Invalidation per **class**, recompilation per **source file**, in a
fixpoint loop rather than GHC's single pass.

**(ii)** The key is the fully-qualified class name at the pickler phase, and
**`xsbti.api` contains no positions and no symbol ids at all** — the API
representation is deliberately position-free.  Hashing is order-insensitive
(`hashSymmetric` over MurmurHash3's unordered hash), and each name hash folds in the
enclosing `location.hashCode`, so same-named members in different owners do not
collide.

**(iii)** `usedNames` records **unqualified simple names**, matched against
`nameHashes` buckets.  Why not resolved references: "we do not use `A.foo`… but we use
`AOps.foo` and it's not immediately clear that `AOps.foo` has anything to do with
`A.foo`.  One would need to detect the fact that a call to `AOps.foo` [is] a result of
implicit conversion `richA`… This kind of analysis gets us very quickly to the
implementation complexity of Scala's type checker."  Inheritance edges bypass name
hashing and go transitive; macros, annotations and implicits force unconditional
invalidation.

**(iv) The case study, and it is Ermine's exact bug.**  Scala 2 expands `A[_]` to
`A[_$1] forSome { type _$1 }` using a **global fresh-name counter**, so the API hash
of an unchanged file changed between runs.  The fix (sbt/sbt#823):

> "The strategy is to rename all type variables bound by existential type to stable
> names by **assigning to each type variable a De Bruijn-like index**…
> `"existential_${nestingLevel}_${i}"`… **This way, all names of existential type
> variables depend only on the structure of existential types and are kept stable.**"
> — `ExtractAPI.scala`

Scoped, not global (`renameTo.remove` on exit, `nestingLevel -= 1`), shipped with a
`reproducible: Boolean` serializer and the assertion
`assert(HashAPI(a) == HashAPI(aAgain), "hash must be deterministic across runs")`.

**Scala 3 PC (i)-(iv)** A **one-entry, content-keyed memo**: same URI and
byte-identical content, else recompile.  Every query is a new `Run` over the same
`ContextBase`.  `class Symbol private[Symbols] (private var myCoord: Coord, val id:
Int, …)` with "A unique identifier of the symbol (**unique per ContextBase**)", fed by
`ContextState._nextSymId` — structurally identical to a `V.id` plus a `Supply`, and
safe only because it never leaves the process.  Crossing a run boundary is a **name
test in the owner's scope** (`owner.unforcedDecls.contains(denot.name, denot.symbol)`),
with re-resolution by `(owner, name, signature)`; failure is `StaleSymbol`.  The one
leaky counter is SemanticDB's `nextLocalIdx`, reset per document and **positional**,
so inserting a local renumbers everything below it — "Local symbols maintain
uniqueness only within a document."

**What Ermine could take from it.**  Zinc is the nearest-neighbour precedent in the
whole survey: a Scala compiler whose global fresh-name counter leaked into a cache
key, fixed by substituting a `(nestingLevel, index)` coordinate computed during the
hashing traversal, in about forty lines, in a build tool this project already
depends on.  If Ermine ever needs its lowered terms to hash stably, that is the
technique — not a global id redesign, but a **traversal-local de Bruijn renaming
applied at hash time**, leaving the runtime ids alone.  Scala 3's `nextSymId` is also
the direct precedent for "a plain counter is fine as long as nothing it keys reaches
disk", which is exactly true of Ermine's `Supply` today.

### 2.10 rustc — the closest thing to "path-based ids: module + statement head + ordinal"

**(ii)** `DefId` is explicitly *not* stable — "a `DefIndex`… **should really be
considered an interned shorthand for a particular DefPath**" — and `impl !Ord for
DefId {}` enforces that at the type level.  The stable thing is `DefPath`: a list of
`DisambiguatedDefPathData { data: DefPathData, disambiguator: u32 }`, where "The
integer is normally `0`, but in the event that there are multiple defs with the same
`parent` and `data`, we use this field to disambiguate."  The disambiguator counter is
**per parent, per kind** (`PerParentDisambiguatorState { next: FxHashMap<DefPathData,
u32> }`), never global.  The hash is an O(1) Merkle fold:

```rust
    parent.local_hash().hash(&mut hasher);
    std::mem::discriminant(data).hash(&mut hasher);
    if let Some(name) = data.hashed_symbol() {
        // Get a stable hash by considering the symbol chars rather than the symbol index.
        name.as_str().hash(&mut hasher); }
    disambiguator.hash(&mut hasher);
    DefPathHash::new(parent.stable_crate_id(), hasher.finish())
```

> "A `DefPathHash` is a fixed-size representation of a `DefPath` that is **stable
> across crate and compilation session boundaries**… The compiler therefore actively
> and exhaustively checks for such hash collisions and aborts compilation if it finds
> one."

**`HirId` is the model for node identity inside a declaration:**

> "This two-level structure makes for more stable values: One can move an item around
> within the source code, or add or remove stuff before it, **without the `local_id`
> part of the `HirId` changing**, which is a very useful property in incremental
> compilation."

**(iii)** Dep nodes are content-keyed: "the value of the key fingerprint does not
depend on anything specific to a given compilation session, like an unpredictable
interning key (e.g., `NodeId`, `DefId`, `Symbol`)… **Because a `DepNode` is
self-contained, we can instantiate `DepNodes` that refer to things that do not exist
anymore.**"  On decode, `DefPathHash → DefId` goes through an mmap-able table;
`decode_def_index` panics outright.  `ExpnHash` uses the better discipline — **hash
first, count only on collision** ("The keys of this map are always computed with
`ExpnData.disambiguator` set to 0").  Spans store `(file, line, col, len)` keyed by a
`StableSourceFileId`.

**(iv)** "whenever something is hashed that might change in between compilation
sessions (e.g. a `DefId`), we instead hash its stable equivalent", via
`ToStableHashKey`, with `StableOrd` as the "this ordering survives serialization"
witness.

**What Ermine could take from it.**  This is the entry that most directly maps onto
the roadmap's own phrasing.  The concrete lesson is that a path-based id is
`(parent hash, kind discriminant, name chars, per-(parent,kind) disambiguator)` — not
`(module, statement head, ordinal)` — and the difference matters: the disambiguator
must be scoped to the parent and kind, so that adding a `data` declaration does not
renumber the `field` declarations, and the *name characters* must be hashed rather
than any interned index.  `HirId`'s two-level `(owner DefId, item-local id)` is the
shape a stable Ermine binder id would take: `(statement key, ordinal within the
statement)`, which is exactly the change §5(b) proposes and is why it is cheap — the
renamer's counter already produces the second component.

### 2.11 Nameless representations, hash-consing, and the limit case

- **Locally nameless** (Charguéraud, JAR 2012, <https://chargueraud.org/research/2009/ln/main.pdf>):
  de Bruijn indices for bound variables, names for free ones — "**By featuring a
  unique representation of terms, it avoids traditional issues related to
  α-conversion**" — but the free side still needs a fresh-name generator, tamed by
  cofinite quantification.
- **`unbound`** (ICFP 2011, <https://www.engineering.upenn.edu/~sweirich/papers/icfp11.pdf>)
  names the problem exactly — "a global counter which is incremented every time
  `fresh` is called… this is unsatisfactory" — offers scoped `lfresh`/`avoid`, and
  supplies the bridge: "the locally nameless representation **interacts nicely with
  hash-consing, as all α-equivalent terms have the same representation**".
- **`bound`** (Kmett): "equality and comparison quotient out the distinct 'F'
  placements… **Alpha equivalence is just `(==)`.**"
- **Hash-consing** (Filliâtre & Conchon): a node is `{ hkey; tag; node }`, where `tag`
  is allocation-ordered (a gensym) and `hkey` is content-derived — the same
  architecture as `DefIndex`/`DefPathHash`.
- **Unison** is the limit case: "each Unison definition is identified by a hash of its
  syntax tree", names are "separately stored metadata that don't affect the function's
  hash", and the payoff is "**we can parse and typecheck definitions once, and then
  store the results in a cache which is never invalidated**".  Its recursive-cycle
  rule — sort members by their cycle-free hashes, then `#x.n` — is GHC's
  recursive-group recipe, discovered independently.

**What Ermine could take from it.**  The upstream Haskell Ermine used `Scope` in the
`bound` style, which gives alpha-equivalence as structural equality for free; the
Scala port dropped it in favour of `V` with an integer id.  That is the single
architectural fact behind the whole identity problem, and it is worth recording in
the roadmap: the 5.5 fingerprint is over *source text* precisely because the core
terms are not alpha-canonical.  A `bound`-style core is far too large a change to
contemplate, but its cheap shadow is not: a **hash-at-a-distance** function that
walks a lowered group and assigns de Bruijn indices to its binders as it hashes
(Zinc's `existential_${nestingLevel}_${i}` trick) would give an alpha-invariant
structural key without touching the runtime representation.

### 2.12 The recurring patterns

Across all ten systems, the same handful of moves appear:

1. **Separate the position-independent skeleton from the bodies.**  ItemTree/Body,
   stubs/chameleons, green/red, `mi_decls`/Core, diet parse.
2. **Derive ids from a path, not a counter** — and scope the disambiguator to the
   parent and kind (`DefPath`, `AstId`, `ClassId`, `Shape.Uid`).
3. **Hash the interface, not the implementation** (`mi_mod_hash`, `apiHash`,
   `SymbolKey`, `hierarchyHash`).
4. **Store width or an anchor, never an absolute position** (green nodes,
   rust-analyzer's `Span`, `xsbti.api`'s complete absence of positions).
5. **Backdate / early-cutoff on an equal result** (salsa, `treesAreEqual`,
   `ChangedRecomputeSame`, Roslyn's non-advancing version stamp).
6. **Invalidation may be finer than reuse** — GHC invalidates per decl and recompiles
   per module; Zinc invalidates per class and recompiles per file; rust-analyzer
   invalidates per item and lowers per file.  The *decision* is a cheap pure function
   of hashes; the *output* is not composable at that granularity.
7. **A counter is a legal key only while the cache's lifetime is inside the counter's
   lifetime.**  hls-graph's `Key`, Scala 3's `nextSymId`, Roslyn's
   `SymbolKeyWriter._nextId`, IntelliJ's `IElementType.myIndex` are all plain counters
   and all safe because nothing they key reaches disk.  This is the cleanest test to
   apply to Ermine's `Supply`.
8. **Restore only the supplies whose values escape** (Merlin's three-way taxonomy).
9. **Make the producer pure and prove it with a no-cache mode** (Merlin's
   `--no-cache`, IntelliJ's stub purity rule, Zinc's `reproducible` assertion,
   rustc's "hash_stable() must be independent of the current compilation session").
10. **Version the encoding** (`getStubVersion`, `SymbolKey.FormatVersion = 7`, the
    compiler version inside `StableCrateId`, Ermine's own `interfaceKey`).

And three cautionary findings, each with a shipped bug behind it: a per-run counter
that leaks into a *name* is a silent, long-lived correctness-of-caching bug (GHC's
`M.$f23`, Zinc's `_$1`); keeping two summaries of one artifact creates a consistency
obligation between them (Zinc's `apiHash` vs `nameHashes`, sbt#2490/#4441); and
fine-grained schemes fail in the *unsound* direction, quietly (GHC #18733, where two
mutually recursive types got the same hash and it "lurked for many years").
## 3. Concurrency in language servers

Everything in this section comes from a survey pass over Roslyn, salsa/rust-analyzer,
Metals, ghcide/HLS, clangd, gopls, Sorbet, TypeScript, IntelliJ, Dart and pyright.

### 3.0 There are only five answers, and every server picks one

| # | Strategy | Requires | Exemplars |
|---|---|---|---|
| 1 | **Immutable snapshot / fork** — an edit produces a new state; readers hold old ones | persistent data structures | Roslyn, gopls |
| 2 | **Cancel-in-place** — bump a revision, unwind everything reading, then mutate | unwinding + side-effect-free queries | salsa/rust-analyzer, IntelliJ |
| 3 | **Confine to one worker + queue** — dispatch never touches the compiler | a thread + futures | Metals, clangd, pyright |
| 4 | **Kill and restart the whole run** — no per-rule cancellation | cheap restart, durable cache | ghcide/HLS |
| 5 | **Cooperative yielding on one thread** — no second thread at all | yield points inside the check | Dart analysis server, tsserver |

matklad names the first three explicitly, and this post is the single most on-point
piece of writing for the Ermine situation
(<https://matklad.github.io/2023/05/06/zig-language-server-and-cancellation.html>):

> "The trivial solution is to run everything sequentially to completion. … This is
> a suboptimal behavior, because reads (computing completion) block writes (updating
> source code). … A more optimal solution is to make the whole data model of the
> server immutable… The cost of this model is the requirement that all data
> structures are immutable… A third approach is cancellation. … That way we don't
> need to defensively copy the data, and also avoid useless CPU work. This is the
> strategy employed by rust-analyzer."

and the sentence that rules out the naive fix:

> "It is possible to work-around this by applying feral concurrency control and just
> wrapping each individual bit of data in a mutex. This removes the data race, but
> leads to excessive synchronization, sprawling complexity and broken logical
> invariants (function body might change in the middle of typechecking)."

**What Ermine could take from it.**  The parked worker-thread fork is asking which
of these five it is.  The roadmap has already committed to (5)-without-the-yielding:
single-threaded dispatch, requests wait.  The upgrade path that costs least is not
(3) but a mixture of (1) and (5): `SessionEnv`'s fields are `var` slots over
immutable Scala `Map`s, so `env.copy` is already a Roslyn-style fork rather than a
deep copy, and the check already runs against one.  What is missing is the *reader*
half — the roadmap's "NO REQUEST TRIGGERS WORK" invariant is exactly the discipline
that makes a snapshot design work, and it is already in force.

### 3.1 Roslyn — immutability makes the problem vanish

- The model: <https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/work-with-workspace>
  — "A solution is an immutable model of the projects and documents. **This means
  that the model can be shared without locking or duplication.**"
- One mutable cell, lock-free reads (`Workspace.cs`):
  `private Solution _latestSolution;` … `public Solution CurrentSolution => Volatile.Read(ref _latestSolution);`
  Taking a snapshot is one volatile pointer read.
- "Fork" is the API name: `ICompilationTracker Fork(ProjectState newProject, TranslationAction? translate);`
  Unaffected projects are reused by reference, so a keystroke forks O(1) objects.
- The commit is a CAS loop over a *pure* transformation: "`transformation`: … **This
  may be run multiple times. As such it should be a purely functional transformation
  … It should not make stateful changes elsewhere.**"
- **A partially-built compilation is not cancelled — it is abandoned, and it loses
  nothing.**  `RegularCompilationTracker` publishes each applied delta before the
  next cancellation check: "// We have updated state, so store this new result; this
  allows us to drop the intermediate state we already processed even if we were to
  get cancelled at a later point."  Deltas merge (`TryMergeWithPrior`), so ten
  keystrokes become one.
- **Frozen partial semantics** is the latency answer: `Document.WithFrozenPartialSemantics`
  — "Creates a branched version of this document that has its semantic model frozen
  in whatever state it is available… **Repeated calls to this method may return
  documents with increasingly more complete semantics.**"  And: "**the primary
  purpose of 'frozen partial' is to get a snapshot *fast* that is allowed to be
  *inaccurate*.**"  The two-pass tagger pattern: fast-but-inaccurate first, then
  enqueue the accurate pass.
- The request queue states the price of mutability better than anything else found
  (`RequestExecutionQueue.cs`): mutating requests block the queue; non-mutating ones
  are fire-and-forget on `Task.Run`.  And the opt-in barrier Roslyn itself declines:
  "Indicates this queue requires in-progress work to be cancelled before servicing a
  mutating request.  This was added for WebTools consumption as they aren't resilient
  to incomplete requests continuing execution during didChange notifications.  **As
  their parse trees are mutable, a didChange notification requires all previous
  requests to be completed before processing.**"  8 handlers mutate, 49 do not.

**What Ermine could take from it.**  Two things, neither of which needs a thread.
First, `Document.WithFrozenPartialSemantics` is the principled version of the
existing `fastMode`: a *degraded input* fed to unmodified code, not a second code
path.  Ermine's fast mode already skips the check and keeps the read's index; making
it the *first* pass of every check, with the accurate pass enqueued behind it, would
publish navigation and syntax diagnostics in ~0.8 s instead of ~1.6 s with no new
concurrency at all.  Second, the WebTools sentence is the exact statement of why
Ermine's dispatch is single-threaded, and it is worth quoting in the roadmap: a
mutable model *must* serialize; the fix is to stop being mutable, not to add locks.

### 3.2 salsa / rust-analyzer — cancel by unwinding, and wait for it

- The doctrine (rust-analyzer `architecture.md`, § Cancellation): "the highlighting
  process should be cancelled -- its results are now stale, **and it also blocks
  modification of the inputs**. … salsa bumps [a global revision] counter and waits
  until all other threads using salsa finish. … That is, **rust-analyzer requires
  unwinding**."
- The reason (`crates/ide/src/lib.rs`): "**We can't just apply the change
  immediately: this will cause the pending query to see inconsistent state (it will
  observe an absence of repeatable read).**"
- salsa's own words (<https://salsa-rs.github.io/salsa/>): "**Cancellation is
  implemented via panicking, and Salsa internals are intended to be panic-safe.** If
  you have a query that contains a long loop which does not execute any intermediate
  queries, salsa won't be able to cancel it automatically."  And the precondition:
  "Salsa assumes that `your_program` is a purely deterministic function of its
  inputs, **or else this whole setup makes no sense**."
- `cancel_others` blocks until every reader is gone, and the doc warns it "could
  deadlock if there is a single worker with two handles to the same database".
- **Durability** is the stdlib/user split: "Typically 'high durability' values are
  things like data read from the standard library or other inputs that aren't
  actively being edited"; in code, `if source_root.is_library { Durability::HIGH }`.
- The main loop snapshots on the dispatch thread, then spawns; cancelled reads
  return `ContentModified`; completion / semantic tokens / symbols / folding are
  retried, goto-def / hover / references / rename are not.
- Cancellation is measurably slow: `process_changes` spawns `trigger_cancellation`
  in parallel "allowing us to do meaningful work while waiting", and the main loop
  logs "overly long loop turn … (cancellation took {cancellation_time:?})".

**What Ermine could take from it.**  The durability split maps one-to-one onto the
resident session: the 129 stdlib modules are HIGH, the edited buffer is LOW, and the
`scopeKey`/`importsKey` in `TolerantCheck.keys` is already a hand-rolled version of
that distinction.  The *cancellation* half does not transfer: it is sound only
because salsa queries write nothing outside their memoized result, and Ermine's
check writes into `Session.depCache` (process-global) and draws from a shared
`Supply`.  Unwinding out of the middle of an Ermine check would leave both in a
half-applied state.  That is the strongest available argument for "copy-on-check and
discard", which is what `withEnv` already does, over "interrupt the check".

### 3.3 Metals — the closest institutional analogue

- Metals' own interface doc says the constraint out loud
  (`RawPresentationCompiler.java`): "**Scala compiler can't run concurrent code at
  that point, so we need to enforce sequential, single threaded execution. It has to
  be implemented by the consumer of this API.**"
- The mechanism is a hand-built **LIFO single-thread executor**, not a lock
  (`CompilerJobQueue.scala`): "A thread pool executor to execute jobs on a single
  thread in a **last-in-first-out** order. … we care most about responding to the
  latest request even if it comes at the expense of ignoring older requests."
  `new ThreadPoolExecutor(1, 1, 0, MILLISECONDS, new LastInFirstOutBlockingQueue)`,
  with each job self-skipping if already cancelled.
- The history is the argument against a lock: PR
  <https://github.com/scalameta/metals/pull/736> replaced `.synchronized` with
  `CompletableFuture` + the queue — "we risked blocking threads forever preventing
  the Metals process from exiting" — after issue
  <https://github.com/scalameta/metals/issues/723> produced a jstack with **52
  threads BLOCKED on one monitor**.
- Cancellation is a polled token *and* `Thread.interrupt()`, with a recovery ladder:
  cancel token → interrupt both threads → after 20 s cancel the future and
  `askShutdown()` → 2 s later `Thread.stop()`.  (Note: `Thread.stop()` throws on
  JDK 20+, so on a modern JDK that last rung silently fails.)
- Metals keeps a **compiler-free answer path**: references and rename are served
  from the SemanticDB/mtags index, "because there are times when we want to rely on
  a symbol index even if the compiler cannot generate SemanticDB".

**What Ermine could take from it.**  Three concrete transfers.  (a) If the parked
worker fork is ever taken, the shape is Metals': a single-thread executor owning the
env, dispatch handing it work and getting futures back — never a lock the dispatch
loop blocks on.  (b) **LIFO, not FIFO**: on a debounced editor path the newest
request is the only one whose answer will be looked at.  (c) The 20 s timeout and
`_compiler = null` recovery is the model for "a check that will not terminate":
Ermine already has a solver budget (`-Dermine.solveBudget=20000`), and the resident
session is rebuildable, so "throw the env copy away and reboot the check" is
available and cheap.

### 3.4 ghcide / HLS — kill the whole run, keep the cache

- The unit of cancellation is the run, because Shake's own contract forbids
  concurrent builds and invalidation is only legal when no build is running.
- The split that makes it bearable (ghcide PR #554): "A hover in module M aborts the
  typechecking of module M, only to start over! … We introduce the concept of the
  `ShakeSession`… The `ShakeSession` enables a new command `shakeEnqueue`, which
  appends work to the existing `ShakeSession`. This command can be called in
  parallel without any restriction. The result is lightning fast performance for
  hover and code actions."  *Edits* restart; *reads* append.
- Cancelled generations are invalidated by a **step counter**, not a cleanup pass:
  `viewDirty currentStep (Running s _ _ re) | currentStep /= s = Dirty re`.
- The correctness hazard of two caches over one graph is documented as a Note:
  "a key might be marked as dirty in ShakeExtras while it's being recomputed by
  hls-graph… **This is problematic with early cut off because we are having a new
  rule cache matching the old hls-graph's internal state.**"  Fix: value-write and
  mark-clean in one transaction, and "**IMPORTANT: record the reverse deps before
  marking the key Clean.**"
- Early cutoff is content-addressed: "**Early cutoff content addresses the result**,
  so hls-graph reruns dependents only when the returned fingerprint has changed" —
  with the trap "**If everything depends on GetModificationTime, we lose early
  cutoff**".
- The measured cost of restarting, PR
  <https://github.com/haskell/haskell-language-server/pull/1862>: dirty-subset
  restarts took a Cabal-3.0.0.0 edit from ~700 ms to ~70 ms; without the dirty subset,
  issue #3476 reports "**10-20s (!)**" per keystroke on a few hundred modules.
- The reusable type-level idea: `IdeAction` is a *different monad* from `Action` —
  "IdeActions are used when we want to return a result immediately, even if it is
  stale.  Useful for UI actions like hover, completion where we don't want to block."
  UI-latency code cannot join the build graph and cannot be cancelled by a restart.
- Staleness is made *sound*: `PositionMapping`/`fromCurrentPosition` maps a query into
  the stale value's coordinate frame and returns `Nothing` when the cursor sits in
  text edited since — so HLS **declines** rather than answering wrongly.

**What Ermine could take from it.**  Two things.  First, `PositionMapping` is the
prior art for Stage-3 Decision (d)'s "refuse on a stale index": HLS refuses at
*position* granularity rather than at document-version granularity, which is
strictly more useful and is the same re-anchoring arithmetic option (b-lite) in §5
needs.  Second, "record the invalidation metadata before publishing the value" is
the rule that makes `Documents.putCache` / `putIndex` safe if a worker ever exists.

### 3.5 clangd — one worker per file, requests read the last good AST

<https://clangd.llvm.org/design/threads> is worth reading whole; the load-bearing
sentences:

> "Once built, the preamble is threadsafe (it's just immutable bytes). **However
> ASTs are not threadsafe, even for read-only operations.**"
> "**ClangdServer is not threadsafe. Therefore, its methods should not block** -
> that would block incoming messages which could be independent … or relevant
> (cancelling a slow request)."
> "This class maintains a set of ASTWorkers, each is responsible for one file. The
> ASTWorker has a queue of operations, and a thread consuming them: throwing away
> operations that are obsolete: reads that have been cancelled; writes immediately
> followed by writes (e.g. two consecutive keystrokes) … This ensures … that **reads
> see exactly the writes issued before them**."
> "**Debouncing** — … Building after the `f` is typed means … we'll never see the
> correct diagnostics until after 2 rebuilds. To address this, writes are debounced:
> rebuilding doesn't start until either a read is received or a short deadline
> expires."
> "**Code completion** … does not use the pre-built AST. … **Since completion is
> extremely time sensitive, it just uses whichever [preamble] is immediately
> available.**"

The policy knobs are types, not conventions: `ASTActionInvalidation ∈
{NoInvalidation, InvalidateOnUpdate}` and `PreambleConsistency ∈ {Stale,
StaleOrAbsent, Consistent}`.  Highlights, hover, inlay hints, document symbols and
codeAction are `InvalidateOnUpdate`; definitions, references and rename are not.
The debounce is *adaptive*: `DebouncePolicy{Min=50ms, Max=500ms, RebuildRatio=1}` —
"Target debounce, as a fraction of file rebuild time."

**What Ermine could take from it.**  The adaptive debounce is the cheapest item on
this whole list and it is PERF-ROADMAP's own P6: Ermine's 300 ms is a constant
picked in 5.3, and clangd derives its debounce from the *measured* rebuild time,
which `Resident` already logs on every check (`read Xs, typecheck Ys`).  The
`InvalidateOnUpdate` / `Stale` taxonomy is also directly transplantable onto the
Stage-3 request set, and it is the vocabulary in which "staleness is ACCEPTED and
documented" should be written down.

### 3.6 Copy-on-check, done literally: Sorbet

Sorbet is the one server whose state is a genuinely mutable global table, and it
does exactly what the parked fork proposes (`LSPTypechecker.cc`):

```cpp
ENFORCE(this_thread::get_id() == typecheckerThreadId, "runSlowPath can only be called from the typechecker thread.");
if (cancelable) {
  auto savedGS = std::exchange(this->gs, pipeline::copyForSlowPath(*this->gs, ...));
  this->cancellationUndoState = make_unique<UndoState>(std::move(savedGS), ..., updates.epoch);
}
```

with `UndoState::restore()` for a cancelled slow path, three documented
single-writer atomics (`currentlyProcessingLSPEpoch` bumped by the typechecker,
`lspEpochInvalidator` bumped by the preprocessor, `lastCommittedLSPEpoch`), and
**preemption**: a running slow path is interrupted at safe points to drain queued
fast requests.  The frequency data is what makes it affordable —
<https://blog.jez.io/making-sorbet-more-incremental/> reports the slow path falling
from **19 % of edits to 10 %**.  And Sorbet is the only server that makes the policy
*visible*: <https://sorbet.org/docs/server-status> — "**Most phases of Sorbet cause
requests for IDE features to queue until the end of the current operation.**"

**What Ermine could take from it.**  `copyForSlowPath` + `UndoState` is the exact
shape the parked fork needs for `Session.depCache`: give the worker its own cache
keyed by generation and merge on commit, rather than letting `Documents.put` delete
from a process-global map mid-check.  And the `sorbet/showOperation` idea —
telling the editor which phase is blocking which feature — is a two-line
`window/showMessage`-class addition that turns "hover hung for 1.3 s" into "check in
progress".

### 3.7 The rest of the field, briefly

- **gopls**: snapshots are immutable and forked; `invalidateViewLocked` cancels the
  previous snapshot's context under `context.WithoutCancel` so invalidation itself
  cannot be cancelled.
- **TypeScript/tsserver**: single-threaded, cancellation signalled out-of-band
  through a named pipe, checked through a `ThrottledCancellationToken` (20 ms) —
  "Checking cancellation can be expensive (as we have to marshall over to the host
  layer)."  VS Code's answer to "the semantic server is busy" is to **run a
  syntax-only second server** and route hover/completion/definition to it while the
  semantic project loads.
- **IntelliJ**: "**The recommended approach is to cancel the read action whenever
  there is a write action about to occur and restart that read action later from
  scratch**" — which requires the computation be idempotent.
- **Dart**: cooperative yielding on one thread, `await Future.delayed(Duration.zero)`
  every ~2 ms of work (500 yields/sec), with a nine-level priority enum and a stated
  eventual-consistency contract.
- **pyright**: share-nothing.  The worker holds its *own* `Program`; the parent
  replays edits as messages.  Cancellation is a file-based token throttled to 5 ms —
  "**This value was selected through empirical testing.**"  And the warning that
  matters most here: `invalidateTypeCacheIfCanceled` exists because "If the work was
  canceled before the function type was updated, **the function type in the type
  cache is in an invalid, partially-constructed state.**"

### 3.8 What arrives during a check: the policy table

| Server | Policy |
|---|---|
| clangd | FIFO per file; reads served with a **stale preamble**; completion bypasses the AST; transient reads auto-cancelled by the next update |
| rust-analyzer | Snapshot at dispatch; salsa cancels on the next write; some requests retry, the rest → `ContentModified` |
| Roslyn | Snapshot; nothing cancelled by an edit; latency-critical features use a **frozen partial** solution, then re-run accurately |
| ghcide/HLS | Edits restart the session; reads go through `useWithStaleFast` — stale now, refresh later |
| Metals | LIFO queue; running job not preempted; 20 s timeout → cancel + restart compiler |
| Sorbet | Queue, **and tell the user**; slow path can be preempted to drain fast requests |
| gopls | A new snapshot cancels the previous one's context |
| TS / VS Code | Route to a syntax-only second server while the semantic one loads |
| IntelliJ | Write action cancels background read actions; they restart from scratch |

And the LSP spec itself is on the side of "answer, don't cancel" (3.17, Implementation
Considerations): "**servers should therefore not decide by themselves to cancel
requests simply due to that fact that a state change notification is detected in the
queue. As said the result could still be useful for the client.**"  Plus the sentence
that describes Ermine exactly: "**if the server implementation uses a single threaded
synchronous programming language then there is little a server can do to react to a
`$/cancelRequest` notification.**"

### 3.9 The minimal safe pattern, and how much of it Ermine already has

The pattern, in one paragraph: **single-writer confinement + a versioned snapshot +
an honest stale-read path.**  (1) One thread ever touches the env, and dispatch is
not it — hand work to a queue that returns futures, never a lock the dispatcher
blocks on.  (2) The state handed to that worker is a copy taken on the dispatch
thread and owned by exactly one thread thereafter.  (3) Every result carries a
generation stamp, and stale generations are discarded by comparison rather than by
a cleanup pass.  (4) Requests never trigger work; they read the last good result and
say so, and where a stale answer would be *wrong* rather than merely old (rename,
refactor), they **refuse**.  (5) Cancellation is a cooperative flag polled at safe
points, never an interrupt into code that mutates shared state.

Measured against Ermine, points (1)-(4) are already satisfied or nearly so:
`SessionEnv` is `var` slots over immutable maps so `env.copy` is a real fork;
`Documents` is likewise a `var` over an immutable map; "NO REQUEST TRIGGERS WORK" is
a Stage-3 invariant; `Documents.putIndex` version-stamps the index and rename refuses
on a stale one; and `Diagnostics` already coalesces per uri with a versioned drop.
The residual hazards are exactly the three the parked fork lists, and they are
exactly the three things *not* behind an immutable slot:

- **`Session.depCache`** is a process-global `ConcurrentHashMap` — thread-safe per
  operation but not transactionally consistent, and `Documents.put` deletes from it
  mid-check.  Prior art: Sorbet's `UndoState` (worker-private cache, merge on commit)
  or ghcide's "record invalidation metadata before publishing the value".
- **The `Supply`** is one process-global block allocator shared by the resident
  session and every check.  `Supply.getBlock` is `synchronized`, so it is
  memory-safe; what it is not is *deterministic*, and Ermine has its own written
  evidence that this is observable — `Session.scala`'s note on
  `-Dermine.loadInSeries`: "parallel makes draw `Supply` ids in thread-timing order,
  **which reaches interface bytes through the constraint solver's id-hash queue**".
  The only correct answers are `split`-per-worker or confine-to-worker; never share.
- **The `Documents` map** read by the sibling loader is safe if the worker captures
  the map *value* once at fork time — which the immutable-map representation makes
  free.

Finally, the arithmetic.  A worker thread removes **0 ms** from the 1.616 s round
trip; it only converts the worst-case request wait (~1.3 s) into ~0.  Roslyn's
frozen-partial two-pass, TypeScript's syntax-server routing, and Dart's cooperative
yielding all buy most of that perceived latency with **no new thread and none of the
three hazards above** — and Ermine's `fastMode` is already 80 % of the frozen-partial
design.  That is the cheapest safe move, and it is what four of the six exemplars
actually shipped.

---

## 4. TextDocumentSync incremental deltas

### 4.1 What the spec says

- The enum: `None = 0`, `Full = 1`, `Incremental = 2` — and clients may not opt out:
  "Client support for `textDocument/didOpen`, `didChange` and `didClose` … is
  mandatory in the protocol and clients can not opt out supporting them. **This
  includes both full and incremental synchronization.**"
- The event is a *union*, not a flagged record:
  `{ range; rangeLength?; text } | { text }`, with "If only a text is provided it is
  considered to be the full content of the document."  So a range-less event means
  whole-document **regardless of the declared kind**.
- Ordering: "apply the `TextDocumentContentChangeEvent`s in a single notification in
  the order you receive them", each computed on the state left by the previous one.
- The hidden cost of Incremental: positions are UTF-16 by default, "**since the
  conversion from one encoding into another requires the content of the file / line
  the conversion is best done where the file is read which is usually on the server
  side**", and "Positions are line end character agnostic. So you can not specify a
  position that denotes `\r|\n`" — i.e. a line index plus a UTF-16 mapping plus a
  CRLF special case, which is precisely the trap already on record in this project.

### 4.2 What real clients send

| Client | Honours declared kind? | Debounce, Incremental | Debounce, Full | Sends `rangeLength`? |
|---|---|---|---|---|
| VS Code | yes | **none — immediate** | **250 ms, coalesced, flushed before any request** | yes |
| Neovim | yes | 150 ms | 150 ms | yes |
| eglot | yes | 0.5 s idle | 0.5 s idle | yes |
| lsp-mode | yes | none (1/keystroke) | 1.0 s idle, coalesced | yes |
| Helix | yes | none | none | **no** |
| Zed | yes | per edit | per edit | **no** |

The VS Code result is counterintuitive: Full-sync bodies go through a 250 ms
resetting delayer, but are **flushed before any request** ("If any document is synced
in full mode make sure we flush any pending full document syncs") — so a Full-sync
server sees *zero* added latency on completion/hover/definition and at most 250 ms on
push diagnostics.  lsp-mode actually sends *fewer* messages under Full than under
Incremental.  eglot falls back to Full even against an Incremental server
(`:emacs-messup`).

Incremental sync is where the client bugs live: Neovim has a string of desync issues
(#17085 filed by clangd's maintainer — "**clangd drops the file, as there's no way
for a server to recover once it fails to apply an incremental update**" — plus
#27383, #25092, #33224 still open); Helix and Zed omit the `rangeLength` clangd uses
to *detect* drift; LSP issue #1706 asked for a checksum so servers could notice
desync and was declined ("I don't want to force a client to compute that hash for
every change").

### 4.3 Cost, for a file this size

After the JSON parse, **Full is the cheaper branch**.  Microsoft's own reference
`TextDocument` implementation splices the string and then repairs the line-offset
array and runs a diff loop over the tail for Incremental, against
`this._content = change.text; this._lineOffsets = undefined;` for Full.  gopls copies
the whole document *per change* on the incremental path and rebuilds its `Mapper`
each time, with a `// TODO … much more efficient` next to it; clangd does
`std::string NewCode(*Code)` then a linear `positionToOffset`.  Every saving from
Incremental comes from the wire and the JSON parse, never from the splice.

A subagent measured the wire/parse half on this machine against this repo's actual
`Layout/Report.e` and this project's own JSON scanner, in a standalone Java
microbenchmark (Temurin 21, 20k iterations after warm-up).  **Caveat: this survey was
not supposed to run a JVM, and that measurement did; treat the numbers as indicative
and re-measure with `perf-bench.sh` before acting on them.**

| | |
|---|---|
| full-sync `didChange` frame on the wire | 79,538 bytes |
| parse of the full-sync frame with this project's scanner | ~369 µs |
| parse of an equivalent incremental frame | ~2 µs |
| socket read + UTF-8 decode of 79.5 KB | ~21 µs |
| splice one char into a 77 KB string | 6-16 µs |
| the check this competes with | ~1,300,000 µs |

That is **0.03 % of one check** and **0.12 % of the 300 ms debounce**.  The same
measurement found that `Rpc.scala`'s char-at-a-time string scanner is what costs the
369 µs, and that a run-based scanner that bulk-copies between backslashes measured
~61 µs — a ~5x win on that step for ten lines of code and no protocol change.

### 4.4 What the server authors said

- **gopls** declares Incremental but accepts a full body anyway: "**We accept a full
  content change even if the server expected incremental changes.**"  Its motivating
  issue (golang/go#31800) is about "large-ish files", and its own profiling put the
  didChange cost in **snapshot cloning**, not parsing.
- **rust-analyzer** is Incremental today but was Full until April 2020, and the
  switch was **not for performance**.  The issue it closed (#3762) reads: "**Some LSP
  clients (ahem, Gnome Builder) don't respect our choice for full text
  synchronization**"; in the PR, kjeremy: "**I would expect the over the wire
  performance to be negligible**"; lnicola: "**I can't really tell, I only checked
  that it works.**"  Two days later matklad filed a `is_char_boundary` panic that
  took five months to fix, followed by two more UTF-16 offset bugs.
- **Metals** — same JVM, same lsp4j, same heavyweight compiler — is **still Full in
  2026**.  Issue scalameta/metals#489, closed wontfix: olafurpg — "**Haven't observed
  any problems, just find it unsatisfying that the full source file is moved on every
  keystroke**" … "**We have no evidence so far to suggest that full text
  synchronization is a performance bottle-neck in Metals.**"
- **bash-language-server**: "For now we're using full-sync even though tree-sitter has
  great support for partial updates" — notable because tree-sitter is exactly the
  case where Incremental would pay.

**What Ermine could take from it.**  Stay on `Full`; the roadmap's "later
optimization" judgement is correct and the nearest institutional precedent (Metals)
reached the same conclusion and never revisited it.  If the door is to be kept open,
the cheap version is gopls' tolerant handler: keep advertising `change: 1`, but treat
a single range-less event as the whole document and apply ranges when present — which
is what the spec's union type already means and what eglot sends regardless.  One
correctness note found in passing: `Diagnostics.scala` reads `contentChanges …
lastOption … text`, which is exactly right for Full ("the last one wins") and would
be **silently wrong** under Incremental, where the spec requires applying every event
in order.  That line is the one that must change first if the capability is ever
flipped.
## 5. Options for Ermine, ranked

The budget being spent, once more: round trip **1.616 s** = read **0.770 s** +
typecheck **0.515 s** + debounce **0.300 s** + residual **0.017 s**; inside the read,
parse ≈ **0.70 s**, extent scan ≈ 0.054 s, and rename + reassoc + lower ≈ **0.012 s**.

### Ranking

| | Option | Removes from the round trip | Identity needed | Prior art that maps onto it | Risk |
|---|---|---|---|---|---|
| **1** | **(a) Surface-tree cache by statement extent, whole rename+lower** | **0.55-0.68 s (34-42 %)** | none | Lean 4 snapshot tree; Lezer `TreeFragment`; Merlin `compatible_prefix`; swift-syntax `parseCodeBlockItem` | slice-vs-context parse divergence; lookahead; a second module driver |
| **1=** | **(a′) Attack the parse constant factor instead (P5c)** | **unknown, potentially 0.5 s+** | none | tree-sitter-haskell 48-52x by de-combinatorizing | large, but zero *semantic* risk if behaviour is preserved |
| **2** | **(b-lite) Anchor cached positions; drop start lines from the 5.5 key** | 0 s typical; **up to 0.5 s** on any edit that shifts lines | none | rust-analyzer's anchored `Span`; Roslyn green nodes; Lezer's `offset` | must re-anchor `locals` keys and any `Loc` that escapes |
| **3** | **(f) Adaptive debounce (PERF-ROADMAP P6)** | up to **0.25 s (15 %)** after (a) lands | none | clangd `DebouncePolicy{50,500,ratio 1}` | none; pure policy |
| **4** | **(d) Worker-thread checks + read-only snapshots** | **0 s** of the round trip; ~1.3 s of worst-case request wait | none, but forces the `Supply` question | Metals `CompilerJobQueue`; Sorbet `copyForSlowPath`+`UndoState`; clangd `ASTWorker` | `depCache`, `Supply`, `Documents` — all three named in the parked fork |
| **5** | **(b) Stable binder/V identity → per-statement rename+lower caching** | **≤ 0.012 s** | the whole scheme | rustc `DefPath`/`HirId`; rust-analyzer `AstId`; Zinc's de Bruijn existentials | Tier 1: id order is observable (`loadInSeries`, GU05) |
| **6** | **(e) Incremental didChange** | **< 0.001 s** | none | LSP 3.17; gopls' tolerant handler | a real bug class (rust-analyzer, Neovim, Zed) for no measurable gain |
| **7** | **(c) A proper incremental parser** | ≤ (a), at far higher cost | node identity + lookahead metadata | tree-sitter, Lezer, Wagner & Graham | replaces the grammar and the layout algorithm; the 180-file differential |

Two judgements drive that ordering and both are new since the roadmap last looked:

- **The identity problem is guarding twelve milliseconds.**  5.5's review was right
  that lowered trees cannot mix across runs, and right to stop.  But P2's profile,
  taken after 5.5, says rename + reassoc + lower are **1.1 % of samples**.  Whatever
  stable-binder identity is worth, it is not worth it *for read latency*.
- **The parse is the read, and the parse has no identity problem at all.**
  `surface/Surface.scala`'s nodes carry only spans; the header comment says "no
  desugaring, no fixity-driven tree shape"; `SName`'s fixity at parse time is lexical.
  A parsed statement depends on nothing but its own text and its layout column.

### (a) Surface-tree cache by statement extent — recommended first

**The design, concretely.**  A new editor-path-only entry beside
`NewPipeline.readModuleTolerant`, because `read` currently begins with one
`SurfaceParsers.module(fileName, contents, mh.name)` call that both strict and tolerant
modes share, and the frozen-batch-semantics invariant forbids touching it.

1. `StatementExtents.scan(newText)` — already 1.64 ms after P5(a).
2. Diff against the cached scan.  The unit is the extent, keyed the rust-analyzer way:
   `(headWord, ordinal among extents with that headWord)`, which is exactly the
   grouping `TolerantCheck.keys` already computes.  A statement is *unchanged* iff its
   extent text is byte-identical **and** its recorded lookahead (below) is not touched.
3. For each unchanged statement, reuse the cached `SStatement` with its spans shifted
   by `Δline` — and because every top-level statement starts at column 1 and `Span` is
   `(startLine, startCol, endLine, endCol)`, **the shift is purely additive on the two
   line fields**; no column arithmetic is involved.  That is a rare and load-bearing
   property: Lezer needs a `cutAt` walk and a 25-character margin to do the same job.
4. For each changed statement, parse the slice with the machinery `statementFailure`
   already builds: a repositioned `ParseState` with
   `layoutStack = List(IndentedLayout(startCol, "statement"), IndentedLayout(1, "top level"))`,
   `bol = false`, and `statement` (not `statementAlts`) so the `rawStatement` fallback
   and the `atLayoutBoundary` check behave as they do in the whole-file driver.
5. Reassemble `SModule(fileName, header, statements)` and hand it to the existing
   rename → reassoc → lower → check pipeline unchanged.

**Why the identity question does not arise.**  The reused artifact is a *closed*
syntactic value: no ids, no supply draws, no references into any other statement.  This
is the same distinction §2.5 draws from Statix — an id may cross a run boundary only
inside a closed artifact — and it is why 5.5's inference cache is already sound while
a lowered-tree cache would not be.

**Ceiling.**  Report.e has ~315 top-level statements in 77 KB, so ~245 bytes each, and
the whole-file parse is ≈ 0.70 s.  A one-character edit leaves ~314 statements
byte-identical.  Optimistically the parse cost falls to one statement (~2.2 ms) plus
the diff plus the span shift; realistically call it **0.55-0.68 s saved, 34-42 % of the
round trip**, taking it to ~1.0 s.  After that, inference (0.515 s) is 51 % of what is
left and the debounce is 30 %.

**Risks, and what answers each.**

- *Lookahead past the extent.*  `statement` is `statementAlts(bindingStatement) <<
  atLayoutBoundary`, and `atLayoutBoundary` runs `StatementExtents.skipTrivia` over the
  text **after** the extent.  So byte-equality of the extent is not by itself
  sufficient — this is Lean's `private def` counterexample in miniature and Lezer's
  0.15.0 bug exactly.  The fix is the convergent one from §1.10: record a **high-water
  mark** per statement (`ParseState` already carries the offset; a `var furthest` and
  one `max` in the position-advancing primitive is the whole change), store
  `examinedLength = furthest - start` in the cache entry, and reuse iff no edit
  intersects `[start, start + examinedLength)`.  And per swift-syntax #3397: **carry
  the recorded lookahead forward into the new cache entry**, or the second consecutive
  edit reuses unsoundly in a way single-edit tests cannot see.
- *Slice-vs-whole-file divergence.*  `statementFailure`'s own docstring records it:
  "the re-parse may SUCCEED where the splitter rejected (context the slice lacks — the
  committed trailing-comment/vsemi interplay)".  The oracle is the one this project
  already runs: a 180-file differential asserting that the spliced `SModule` is equal to
  a fresh whole-file parse, modulo nothing — and, following rust-analyzer's `fuzz.rs`,
  a **multi-edit** property, not a single-edit one.  Note that rust-analyzer's fuzzer
  has `assert_eq!(errors)` commented out behind a FIXME; Ermine cannot afford that,
  because its diagnostics *are* the product.
- *Statement merging and splitting.*  Ermine is in a better position than Lean here:
  `StatementExtents.scan` recomputes every boundary lexically **from the new text** on
  every check, and its starts are pinned against the parser's own splitter over 180
  files, so a deleted space that merges two statements shows up as a change in the
  extent list rather than as a silently reused stale tree.  Lean, comparing against the
  old command list, has to guess how far back to go and settled on "up two commands".
- *Batch semantics.*  Editor-path entry point only; `SurfaceParsers.module` and
  `readModule` untouched; `TestTolerantRead`'s agreement property and the REPL goldens
  are the tripwires already in place.
- *Retention.*  swift-syntax's warning applies to a JVM: reference-based reuse makes
  the parse cache a GC root for whatever it holds.  The cache is per open document and
  replaced wholesale on each check, so this is bounded — but it should be stated.

**Prior art that maps most directly:** Lean 4's snapshot tree (same shape, better
boundary story here), Lezer's `TreeFragment` (the `offset` field is the span shift),
Merlin's `compatible_prefix` (same prefix/splice logic one phase later), swift-syntax's
`parseCodeBlockItem` (declaration-level reuse in production, with the high-water mark).

### (a′) The constant factor — measure before choosing between them

PERF-ROADMAP already names the target: the `Free` trampoline is 52.6 % of editor
samples and `Parser.run` alone is 23.2 %; P5(d) tried a localized fix and reverted it at
43 ms.  §1.11's tree-sitter-haskell result says the localized approach is the wrong
shape and the available win is **48-52x from removing the combinator indirection**, in
a system with the same profile signature (allocation in combinator plumbing).

This belongs in the same rank as (a) because **it changes (a)'s value**: if a
245-byte statement parses in 0.05 ms instead of 2.2 ms, the whole read drops to ~0.03 s
and per-statement caching becomes unnecessary.  The honest sequencing is Elhage's rule
(§1.11): find out whether it is still "fast enough to just do the work" before building
machinery to avoid the work.  A cheap experiment exists — time
`SurfaceParsers.statement` on one extracted 245-byte statement directly, 50 reps after
20 warm-ups, the P5(a) protocol — and it answers both questions at once: it gives (a)'s
per-miss cost and it says how much of the 0.70 s is per-statement work versus
per-character trampoline overhead.

### (b-lite) Anchor the cached positions — cheap, and it fixes a live cliff

`TolerantCheck.keys` puts each statement's **start line** into its group's text
(`x.startLine + ":" + off.text(x)`), and the comment explains why: a reused `Entry`
carries `types` and `locals` whose positions must not have drifted.  The consequence is
a cliff: **inserting one line at the top of the file changes every group's key, so
`reused` goes to 0 of 154 and the full 0.515 s of inference is paid** — for an edit that
changed nothing semantically.

The fix needs no identity scheme.  Store positions **relative to the group's start
line**, drop the start line from the key, and add `Δ` at lookup:
`Entry.locals` is `Map[(Int, Int), LocalTy]` keyed by def-site, so the shift is one map
transformation at read time; the `Type`s' `Loc`s only matter for notes, and
note-bearing components are never cached (the class comment says so).  This is
rust-analyzer's `Span { range relative to SpanAnchor }` with its stated rationale —
"storing absolute ranges will require recomputation on every change in a file at all
times" — and Roslyn's green-node rule, "**every node tracks its width but not its
absolute position**".

It is also the same arithmetic (a) needs for span re-anchoring, so the two share an
implementation.

### (f) Adaptive debounce

Not on the original list, but it is 19 % of the round trip and pure policy, and after
(a) it is 30 % of what remains.  clangd derives its debounce from measured rebuild time
(`DebouncePolicy{Min=50ms, Max=500ms, RebuildRatio=1}`, "Target debounce, as a fraction
of file rebuild time"), and `Resident` already logs exactly that number on every check.
PERF-ROADMAP's P6 says the same thing and correctly orders it last among the [E] items,
"shortening it while a check costs 1.27 s just queues more work" — which is precisely
why it becomes worth doing *after* (a).

### (d) Worker-thread checks

**It removes nothing from the round trip.**  Its whole value is converting the ~1.3 s
worst-case request wait into ~0, and §3 says four of six surveyed servers bought most
of that perceived latency without a thread: Roslyn's frozen-partial two-pass, VS Code's
syntax-only server routing, Dart's cooperative yielding, and clangd's "reads see the
last good AST".  **Ermine's `fastMode` is already 80 % of the frozen-partial design** —
it skips the check, keeps the read's index, and carries the cache forward untouched.
Promoting it to the *first* pass of every check, with the accurate pass enqueued behind
it, would publish navigation and syntax diagnostics in ~0.8 s (and, after (a), ~0.1 s)
with no new concurrency.

If the thread is nonetheless wanted, §3.9 has the shape and the three hazards.  The one
worth restating here is the `Supply`, because it is the same object option (b) would
change: `Supply.getBlock` is `synchronized`, so a worker is memory-safe, but ids would
interleave in thread-timing order — and `Session.scala`'s own comment on
`-Dermine.loadInSeries` says that "reaches interface bytes through the constraint
solver's id-hash queue".  The prior-art answer is Lean's `mkChild` /
`Supply.split`: give the worker its own split rather than sharing the block allocator.

### (b) Stable binder / V identity — what it would actually take

Ranked fifth because of the arithmetic, not because the design is bad.  Recording it in
full anyway, because the roadmap asked for it and because §5.6 of the LSP roadmap says
"if a stable-binder-identity scheme looks necessary … STOP: that is its own design
item".

**What the ids are today.**

- `Renamer.S.nextId` is a per-run counter starting at 0.  It is *already deterministic*
  given the same text; what makes it unstable is that an edit anywhere earlier shifts
  every later binder's number.  It never escapes `Renamer.Result` — it is a `Map` key
  and the payload of `ToBinder(id)`.
- `Lower.freshId()` draws from the session `Supply`.  These *do* escape: the comment
  says "module loads accumulate their Vs in s.env/s.termNames, so a per-module counter
  would collide across loads", and `V.equals`/`hashCode` are **purely the integer id**.
- `Resident` holds one `Supply` for the server's lifetime; `scalaparsers.Supply` draws
  1024-id blocks from a process-global `synchronized` counter.

**The design, if it were done.**

- **Renamer ids: `(statement key, ordinal within the statement)`, i.e. rustc's `HirId`.**
  "This two-level structure makes for more stable values: One can move an item around
  within the source code, or add or remove stuff before it, **without the `local_id`
  part of the `HirId` changing**."  The statement key is the same one (a) uses —
  `(headWord, ordinal among that headWord)` — which is rust-analyzer's
  `ErasedFileAstId` with the same warning attached: the disambiguator must be scoped
  **per (kind, name)**, not global, or adding a `data` declaration renumbers the
  `field` declarations.  Packing is easy since these are only map keys: `stmtIndex *
  2^k + local`, or a `case class BinderId(stmt: Int, local: Int)`.  This part is nearly
  free and has no external surface.
- **`V` ids: the hard half.**  A `V`'s id must be globally unique across every module in
  the session, so a path-derived id has to be `hash(moduleName, statementKey, kindTag,
  localIndex)` with collision detection — rustc does exactly this
  (`DefPathHash::new(parent.stable_crate_id(), hasher.finish())`, "The compiler
  therefore actively and exhaustively checks for such hash collisions and aborts
  compilation if it finds one") and so does Lean (`withInitQuotContext` with a
  deterministic linear probe).  The cheaper alternative, and the one the prior art
  actually recommends, is **not to make ids path-derived at all**: Lean snapshots the
  `NameGenerator` *as part of the state* so a reused prefix and a fresh continuation
  agree by construction, and `scalaparsers.Supply` already has `def split: Supply`,
  which is `mkChild` under another name.  A per-statement split recorded in the cache
  entry gives determinism without touching the id space.
- **What it would cost at the gate.**  Ermine has written evidence that id *order* is
  observable in two places.  `Session.scala`: "parallel makes draw `Supply` ids in
  thread-timing order, **which reaches interface bytes through the constraint solver's
  id-hash queue**" — the reason `-Dermine.loadInSeries` exists.  And PERF-ROADMAP P10:
  at the shipped dequeue order, the id base alone moved GU05 from **743 to 47,317
  draws** (≥ 63.7x), with wall clocks from 221 ms to 133-486 s.  The adopted
  `smallcanon` default flattened that to **306 draws at every one of 25 bases** — but
  `smallcanon` breaks ties **by id order**, so it is insensitive, not immune.  Any id
  redesign is therefore Tier 1: `g1-validate` alpha-equality over 129 `.ei` files, the
  REPL goldens, plus the GU05 sweep at ≥ 25 bases before and after.
- **Interaction with `TolerantCheck`'s fingerprints — the actual prize.**  The
  fingerprints are text-based *because* ids are unstable ("every V in a fresh run has a
  fresh id, so a type rendering would be a moving target").  With stable ids, or more
  cheaply with an **alpha-canonical structural hash** of the lowered group, the key
  could become structural, and three things would follow: comment- and
  whitespace-only edits would stop invalidating (today they change the group text);
  the start-line component could go (but (b-lite) achieves that alone); and cross-file
  reuse would become expressible.  The prior art for the cheap version is Zinc, and it
  is the nearest neighbour in the whole survey — a Scala compiler whose **global fresh-
  name counter leaked into a cache key**, fixed in about forty lines by assigning "a
  De Bruijn-like index… `existential_${nestingLevel}_${i}`" during the *hashing
  traversal*, leaving the runtime ids alone.  That is the shape to copy: a
  hash-at-a-distance walk over a lowered group that numbers binders in traversal order,
  not an id-space redesign.
- **One hazard to fix whatever else happens.**  `fpOf` builds an SCC's fingerprint from
  `sps.sorted ::: texts ::: upstream`, so every member of one SCC gets the *same* key.
  That is harmless today (the `Entry` stores a `Map[String, Type]` covering all of
  them) but it is structurally GHC #18733, where "two mutually recursive types [got] the
  same hash" and the bug "lurked for many years before being uncovered".  GHC's recipe
  is four lines: sort by name, assign sequential indices, hash the group, member hash =
  `hash(group_fp, i)`.  Worth an adversarial test that transposes recursive occurrences
  within a group and asserts the fingerprint changes.

### (e) Incremental didChange

Last but one, and the evidence is in §4.  The entire residual of the round trip — env
copy, self-scrub, header parse, extent scan, `Definitions.index`, protocol write — is
**0.017 s**, and incremental sync attacks a fraction of that.  Its supposed second
benefit, handing the server the edit range that (a)'s diff wants, is obtainable for
free by comparing statement texts, which `TolerantCheck.keys` already does; Lean
deliberately does the same thing (`firstDiffPos` over the whole input string) rather
than trusting LSP edit ranges.  Against that sits a real bug class with no
protocol-level detector (LSP #1706 asked for a checksum and was refused).  The nearest
precedent — Metals, same JVM, same lsp4j — closed the request wontfix in 2019 and is
still Full in 2026.

Keep `change: 1`.  If the door is to be left open, do it gopls' way: accept a
range-less event as the whole document, apply ranges when present — and fix
`Diagnostics.scala`'s `contentChanges.lastOption.text` first, since that is correct for
Full and silently wrong for Incremental.

### (c) A proper incremental parser

Last, and the survey is close to unanimous.  matklad, who implemented block reparse in
rust-analyzer: "**In practice, incremental reparsing doesn't actually matter much for
IDE use-cases, parsing from scratch seems to be fast enough**" — and it "is not
actually enabled still".  Lezer sets a floor of ~1 KB below which it does not reuse at
all, which is *four times* Ermine's mean statement.  Wagner & Graham's canonical paper
has no measured speedup and its author says layout-sensitive languages are outside the
model.  tree-sitter's answer for Haskell layout is 3,471 lines of hand-written C.  And
Ermine's own invalidation unit is already the top-level statement — 5.6 established,
with evidence, that a `where`-block is never a binding component of its own — so
sub-statement granularity has nothing finer to invalidate.

An incremental engine would also replace the grammar and the layout algorithm wholesale,
against a frozen batch semantics pinned by 180-file differentials and byte-exact REPL
goldens.  The marginal gain over (a) is granularity Ermine does not need; the marginal
cost is the whole front end.

### A suggested Stage-4 sequence

1. **Measure one statement's parse** (P5(a)'s protocol, 50 reps after 20 warm-ups).
   This costs an afternoon and it decides between (a) and (a′) — and it re-checks the
   3.5x-over-attribution warning before anything is built on the 0.70 s figure.
2. **(b-lite)** — anchored positions, start line out of the 5.5 key.  Small, no
   identity scheme, removes a real cliff, and it is the shared implementation (a) needs.
3. **The high-water mark** — a `var furthest` in `ParseState` and one `max`.  Useless
   on its own; it is (a)'s soundness precondition and it is what Lean says it wishes it
   had.
4. **(a)** — the statement cache, editor-path only, behind the 180-file differential
   and a *multi-edit* property.
5. **(f)** — re-derive the debounce from the now-smaller measured check cost.
6. Then re-open (d) and (b) with fresh numbers.  Both are likely to look different: (d)
   because the worst-case wait will have halved, and (b) because it will still be
   guarding twelve milliseconds.

---

## Appendix — provenance, caveats and corrections

**How this was produced.**  Local facts were read out of this repository
(`surface/Surface.scala`, `surface/SurfaceParsers.scala`, `surface/StatementExtents.scala`,
`rename/Renamer.scala`, `rename/Lower.scala`, `rename/NewPipeline.scala`,
`session/TolerantCheck.scala`, `session/Session.scala`, `lsp/Resident.scala`,
`lsp/Documents.scala`, `parsers/.../Supply.scala`) and out of
`tracker/LSP-ROADMAP.md` and `tracker/PERF-ROADMAP.md`.  External material came from
three parallel research passes over primary sources — compiler source files, design
notes, papers and issue threads — with URLs given inline.

**Constraint deviation, disclosed.**  This survey was asked not to run any JVM.  One
research subagent nonetheless ran a **standalone Java microbenchmark** in the session
scratchpad (a reimplementation of the JSON string scanner, not the Ermine build, not
sbt, not `bin/ermine`) to produce the didChange parse figures in §4.3.  Those numbers
are labelled where they appear and should be re-measured with `perf-bench.sh` before
anything is decided on them.  Nothing in the repository was modified other than this
file; nothing was committed.

**Corrections carried from the research passes.**

- Wagner & Graham's final citation is **TOPLAS 20(5):980-1013, September 1998**, despite
  the circulating preprint's running head saying 20(2)/March.  The Berkeley URLs are
  dead; use the Internet Archive mirrors given in §1.2.
- `matklad.github.io/2020/07/15/three-architectures-…` 404s; the live URL is
  <https://rust-analyzer.github.io/blog/2020/07/20/three-architectures-for-responsive-ide.html>.
- swift-syntax PR #3372's figures (0.16 ms → 0.19 ms per edit, 401 → 23 arenas,
  ~23 MB → ~4 MB) are the before/after of **arena compaction**, not
  incremental-vs-full.  A "~12x vs full parse" ratio circulating from an earlier draft
  is unverified.
- The Wagner & Graham TOPLAS paper has **no empirical evaluation section**; all figures
  attributed to that line of work here are overheads from the thesis, and the real
  incremental-vs-batch numbers come from Diekmann's Eco twenty years later.
- Zwaan's 2021 Delft thesis on incremental Statix is an **MSc**, not a PhD.
- The sbt 1.x "Understanding Recompilation" documentation page is stale on granularity;
  cite the 2017 Zinc 1.0 post or sbt/zinc#86 instead.
- Metals' `CompilerAccess.scala` has **moved** to
  `mtags-shared/src/main/scala/scala/meta/internal/pc/`.
- Metals' goto-definition is no longer unconditionally index-first: `DefinitionProvider`
  tries the compiler first for Scala 2 and Scala 3 ≥ 3.7.
- `Thread.stop()`, the last rung of Metals' recovery ladder, throws
  `UnsupportedOperationException` on JDK 20+ (JDK-8293852), so on a modern JDK that
  scheduled task fails silently.

**Unverified citations, flagged as such.**  The Coq/Rocq ITP 2015
asynchronous-processing paper (the RocqIDE manual quotes are verified; the paper itself
could not be fetched); the widely-quoted HLS "GHC is a batch compiler" line; Eclipse
JDT's `dietParse`/`parseBlockStatements` completion flow beyond the single verified wiki
sentence; rustc's `KeyFingerprintStyle::Opaque` enum definition (the `DepNode` module
doc states the same idea in prose and is quoted instead); Gabbay & Pitts (FAC 2002) and
Cαml, cited only as they appear in the POPL'08 and ICFP'11 bibliographies.

**One local claim that deserves a direct measurement before it is relied on.**  The
per-phase seconds inside the read in §0.1 are my arithmetic on P2's sample shares, and
PERF-ROADMAP's own P5(a) finding — JFR over-attributed `StatementExtents.offsetOf` by
**3.5x** — applies to them.  The first Stage-4 item in §5's suggested sequence is
precisely the direct measurement that would replace them.
