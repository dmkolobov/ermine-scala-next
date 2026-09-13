# LSP interstage item 6.2c — E14, the constrained local head

Implementer report.  Brief `tracker/loopmodel/briefs/brief-LSP-6.2c.md`; item of record
`tracker/LSP-ROADMAP.md` § "Interstage item 6.2c"; ticket `tracker/TICKET-stdlib-findings.md` E14;
gates `tracker/GATE-POLICY.md`.  Branch `scala3-migration`, from `b0eee247` (code at `336b5204`).
No commits.  Pre-change worktree left in place at `../ermine-scala-wt-62c` (detached at `336b5204`,
built, its `tracker/repl-classpath.txt` regenerated and left uncommitted per the worktree note).
Scratch (every log path below is relative to it):
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.2c/`.

**OUTCOME: DONE.**  A local binding head hovers the type the checker published for it, constraints
included.  E14's `go` goes from `List a -> a -> a` to `forall a. Num a => List a -> a -> a`, and the
corpus says E14 was never one file: **eight** local heads over the 253 clean modules were hovering a
constraint-free type the checker does not hold, and all eight now carry their constraint.  Two
residuals, both named and neither silent: (1) the arity split's `acc : a` still sits beside the
hook's `h : Int` at E14's def-sites — the 6.2b disagreement set is UNCHANGED, and §6 says why the
hook's `Int` is the frame-dragged answer and `a` the binder's own; (2) a local head's scheme whose
constraint quantifies its own existentials has that constraint ELIDED from the hover (§4, rule 1),
which is what the `.ei` publishes too.

---

## 1. The mechanism, measured before anything was written

Probe: a temporary instrumentation of `Subst.scala` under `-Dermine.probe62c=true`
(`probe-patch.py`, reverted before the fix) printing, per implicit binding, the head `V`'s meta, the
`rp` it was subsumed against, the ids handed to `restrictTypes`, the scheme `generalize` published,
and `hm.binderTypes` at that moment; driven by a scratch `runMain`
(`Probe62c.scala`, deleted — copy in the scratch dir).  Output `logs/probe1.log`, on the E14 shape
`prod xs = let go [] acc = acc / go (h::t) acc = go t (h * acc) in go xs 1`:

```
P62C infer   go^48898 @TC(8:7) meta=48899 rp=List a -> a -> a restrictTypes(tts)= zonk(meta)=List a -> a -> a metaInTypes=true
P62C publish go^48898 @TC(8:7) scheme=forall a. Num a => List a -> a -> a zonk(meta)=List a -> a -> a publishing=false
P62C   hook (8,17) = a zonk=a          <- acc, at the local publish
P62C   hook (9,11) = a zonk=a          <- h
P62C publish prod^48896 @TC(7:1) scheme=List Int -> Int zonk(meta)=List Int -> Int publishing=true
P62C   hook (8,17) = Int zonk=Int      <- acc, at the TOP-LEVEL publish
P62C   hook (9,11) = Int zonk=Int      <- h
```

**THE MECHANISM.**  `Subst.inferImplicitBindingTypes` (`Subst.scala:869-899`) takes the head's own
Lower meta as `tp = substType(b.v.extract)` (:882), unbinds the inferred type into the rho `rp`
(:883) and binds the meta to it with `subsumeType(tp, rp)` (:886) — `tp` is a bare `VarT`, so
`unbind` falls through and `unifyType` instantiates the meta to `rp` (`metaInTypes=true` above).
`restrictTypes` is not what breaks it: the probe shows `tts` EMPTY at *this* binding, and — the part
that is general, and the part the sentence should have led with (review R-9) — the head's meta is never
among the variables `restrictTypes` is given, at any binding.  `tts` is NOT empty everywhere: at
`pairLocal` two shapes down the same probe prints `restrictTypes(tts)=51791`.  So the 6.2 review's R-1
mechanism is not this one, which is why the orchestrator's `pairUp` control renders correctly.  Two statements later the `generalize` at :910-911 quantifies
`rp`'s free metas into the SCHEME and moves the deferred constraints (`csp`) into that scheme's `q`
— and it rewrites only the scheme and `hm.binderTypes` (:1712), never `hm.types`.  Nothing binds
those metas again, so `substType(headMeta)` returns `List a -> a -> a` for ever: one frame behind the
type the checker published, with `Num a` gone.  The scheme itself is handed out only in the map
`b.v -> b.v.as(scheme)` (:912) that `inferType`'s `Let` case substitutes into the BODY, so the head —
whose `V` in the tree is still Lower's — had no way to reach it.  `TolerantCheck.collectLocals.headType`
read that meta, which is why hover said `List a -> a -> a`.

The same probe explains the hook's `Int` (§6): at the LOCAL publish the hook holds `a` — the scheme's
Bound variable, rewritten there by `generalize`'s `binderTypes` line — and by the TOP-LEVEL publish it
holds `Int`, because `unbind` (`Subst.scala:650-652`) rewrites `binderTypes` again at the first
instantiation of `go`'s scheme in the body (`go xs 1`), and that instance is then unified with `Int`.

## 2. What changed, and why at that site

**`Subst.scala`.**  Two guarded blocks, one field and one hoist — the first version of this sentence
said "every executable line behind `hm.recordBinders`" and that was false (review R-8); the exact
inventory, with each line's guard, is in the fix round's §11:

* `SubstEnv.headTypes: Map[(Int,Int), Type]` — the scheme `inferImplicitBindingTypes` publishes,
  keyed by the head `V`'s def-site `(line, column)`, exactly as `binderTypes` is keyed and safe for
  the same single-module reason (6.2b review R-9).
* the record itself, at the `generalize` that produces the scheme (`:910-921`): the ONE place a
  binding head's published type exists.  `b.v.loc` must be a `Pos`; an `Inferred`/builtin loc is
  skipped, as the pattern-binder hook does.
* `instantiateType` (`:222-231`): the existing guarded block becomes
  `if (hm.recordBinders) { if (binderTypes.nonEmpty) …; if (headTypes.nonEmpty) … }` — the strict path
  still pays exactly one boolean test.  This site is MANDATORY and the only eager rewrite `headTypes`
  gets: it is what keeps a scheme's FREE metas live (`let g x = (x, y)` publishes
  `forall a. a -> (a, b)` before the body fixes `b` at `Int`).  `unbind` and `generalize` deliberately
  do NOT rewrite it — an entry here is a scheme whose quantified variables are `Bound`, and those two
  rewrites would drag it into whichever instance the body took first (which is precisely what they do
  to `binderTypes`; §6).

**`TolerantCheck.scala` (153+/9-):** `headRecorded` reads the record (zonked, then display-normalised);
`headType`'s implicit case prefers it and keeps the meta as the fallback for a head the record cannot
key; `displayScheme` + `varOrder` are the two display rules of §4; `headAgree` is the cross-check of
§5; `Result` gains `headAgreed` / `headDisagreements` / `headRequantified` / `headElided`.
**`Resident.scala` (13+/2-):** `Checked` carries the four out to the sweep, as it already does for
6.2b's three.

The fix is at the HEAD.  Nothing in the arity split changed: `domains` already peels a `Forall`
structurally, so the split now peels the corrected head and `args` renders its domains with
`prettyTypeIn(head, …)` — the argument inherits the head's letters, which is Decision (a)'s own rule.

## 3. The E14 hover, before and after (real server, my client)

`tracker/tools/lsp-client.py`-based probe over `com.clarifi.reporting.ermine.lsp.Main`, fixture
`e14/Heads2.e` (the orchestrator's `Heads.e` plus controls), before = the `336b5204` worktree build,
after = this tree.  `logs/hover2-before.log`, `logs/heads-after-full.log`:

```
                          BEFORE                          AFTER
go   (head, def-site)     go : List a -> a -> a           go : forall a. Num a => List a -> a -> a
go   (head, at a use)     go : List a -> a -> a           go : forall a. Num a => List a -> a -> a
acc  (arity split)        acc : a                         acc : a
h    (6.2b hook)          h : Int                         h : Int
t    (6.2b hook)          t : List Int                    t : List Int
xs   (equation arg)       xs : List Int                   xs : List Int
```

Controls, all from the same run — the two shapes of the brief's fact 3, a signed local, and the
top-level renderings the local head now matches:

```
g    (head, var fixed later)   g : a -> (a, Int)       g : forall a. a -> (a, Int)
z    (head, settled)           z : Bool                z : Bool          (unchanged)
sl   (SIGNED local head)       sl : Int -> Int         sl : Int -> Int   (unchanged, Decision (a))
idy  (polymorphic where head)  idy : a -> a            idy : forall a. a -> a
mul  (TOP-LEVEL, constrained)  Heads2.mul : forall a. Num a => a -> a -> a   (unchanged, both sides)
idt  (TOP-LEVEL, polymorphic)  Heads2.idt : forall a. a -> a                 (unchanged, both sides)
```

The last two lines are the whole argument for the rendering: a local head now reads exactly the way a
top-level head has always read.  The visible cost is that a polymorphic local head gains its `forall`
(`idy`), which is a rendering change and not a content change — counted separately (§5,
`requantified 94`) and pinned in the 6.2 / 6.2b unit properties and in `lsp-client.py`, each with the
reason written beside it.

## 4. The two display rules (`TolerantCheck.displayScheme`)

A published scheme is an internal object and two of its properties are not fit for a hover as they
stand.  Both rules are structural, both are documented at the definition, and both were MEASURED
before being adopted (`logs/probe-warm.log`, `logs/probe-warm2.log`, `logs/probe-warm3.log`):

1. **A constraint that quantifies its own existentials is elided.**  Without this rule
   `Relation.e`'s locals hover a 300-character blob of twenty ambiguous row variables, and — worse —
   two checks of ONE UNEDITED file print that blob in different orders, because the constraint set and
   its existential binder list are id-keyed (6.6's "145 of 223 divergences, all order").  The probe
   measured 21 such local sites over the six modules and **12 of the 21 were not even alpha-equal**
   between two warm checks, i.e. the hover would visibly flicker.
   **CORRECTED IN THE FIX ROUND (review R-1 and R-2).**  This rule as first written erased the whole
   constraint set whenever one existential appeared in it, which lost `Num a` on 246 of 930 elision
   events; and the sentence that justified it — "the compiler does not publish those constraints
   either, the `.ei` carries the bare type" — is FALSE: an `.ei` keeps its existential row constraints,
   and the deletion that paragraph was remembering is C12's TAUTOLOGY deletion under
   `publishing = true`, a different predicate that runs for a module's top-level group only.  §11 has
   the rule as it now stands (a per-constraint VISIBILITY filter) and the numbers.
2. **The quantifier's variables are re-ordered by first occurrence** (`varOrder`).  `generalize`
   builds `ts` from a `Set`, and `ppForall` names the binders before printing the body, so the LETTERS
   followed variable ids.  Re-ordering makes them follow the text.

With both rules the 21 flickering sites go to **0 of 0** (`logs/probe3.log`), and the 7.2 corpus
sweep's own counters IMPROVE against the 6.2b baseline: "18 render differently on an UNSHIFTED reuse"
→ 16, "8 render a LOCAL differently on two COLD checks" → 1 (0 on the final run), mismatches 0 → 0.  `Forall.apply`
collapses a scheme with nothing left to quantify to its bare body, so a monomorphic local head
(`z : Bool`) renders the string it rendered before 6.2c.

## 5. The head cross-check at corpus scale

> **SUPERSEDED BY §11.**  The figures in this section are the first round's.  After review R-1 (rule 1
> is a filter, not an erase) and R-6 (the comparison reads the PUBLISHED scheme, not the displayed one)
> the numbers are `agreed 174, disagreed 65, requantified 94, elided 58, lost 0, hover SHOWS a
> constraint 12`, and the table below is replaced by §11's twelve-site table.  Kept for the record.


The equation arguments' check, one binding level up.  Both answers for an implicit local head are
compared where both speak: the SCHEME the checker published (what hover shows now) and the META hover
read until 6.2c.  They AGREE when the meta is the scheme's body up to renaming and the scheme
quantifies no constraint; they DISAGREE when the hover changes in CONTENT.  Sweep line
(`logs/ttc-final.log`, property "6.2b: the 253-file sweep"):

```
### 6.2c heads: agreed 231, disagreed 8, requantified 94, constraint elided 57
### 6.2c head disagreements: Report.e:643:9 ;; Report.e:690:7 ;; Report.e:1111:11 ;; Report.e:1604:9 ;; Scan.e:70:9 ;; Op.e:178:9 ;; Scan.e:150:9 ;; LetAndPatternMatching.e:8:7
```

239 local heads compared over 253 clean modules (anti-vacuity asserts ≥ 200), the SET pinned (R-4).
Every member read at source and hovered on both sides (`logs/heads-before-full.log`,
`logs/heads-after-full.log`) — all eight are ONE class, and it is the fix working:

| def-site | head | before | after — the constraint the rho could not carry |
|---|---|---|---|
| `LetAndPatternMatching.e:8:7` | `go` | `List a -> a -> a` | `+ Num a` — **ticket E14** |
| `Layout/Report.e:643:9` | `capture` | `((c d e, b), a) -> ((Presentation d e, b), a)` | `+ AsPresentation a` |
| `Layout/Report.e:690:7` | `defaultLg` | `List (Record k) -> Maybe (…)` | `+ a1 <- (i, k, v1)` (a row constraint with no existentials of its own, so rule 1 keeps it) |
| `Layout/Report.e:1111:11` | `ope` | `Maybe a -> Maybe# PrimExpr#` | `+ Primitive a` |
| `Layout/Report.e:1604:9` | `npair` | `((pr r a, Maybe (SortStrategy r)), SortPriority) -> …` | `+ AsPresentation pr` |
| `Layout/Scan.e:70:9` | `go` | `(a1, Column (Unbound a, l, p, d) k v) -> …` | `+ Primitive c` |
| `Relation/Scan.e:150:9` | `extractF` | `f r -> Scan z b` | `+ Relational f` |
| `Relation/Op.e:178:9` | `showE` | `(String, PrimT) -> Op t s` | `+ PrimitiveString s` |

None is a further defect: each is a head whose hover was missing a constraint the checker holds.
`requantified 94` is the cosmetic half (heads that gained a `forall`); `elided 57` is rule 1 firing.

## 6. The 6.2b disagreement set: UNCHANGED, and why

```
### 6.2b sweep: 253 clean modules of 257 — Arg(equation) 2874/2874, Arg(other) 1776/1804,
    CaseBound 116/117, DoBound 31/31, LetBound 165/165, WhereBound 92/92; misses 29;
    split-vs-hook agreed 2869 disagreed 14
```

Identical to 6.2b's: same 14 def-sites, `LetAndPatternMatching.e:8:17` and `:9:17` among them, and
`agreed` unchanged at 2869.  That is the predicted movement and the brief's second option: the head is
now a constrained SCHEME and the hook's answer is one INSTANCE of it, so the two still differ at those
two sites.  The reason is in the property's comment and is the probe's, not a guess: the hook records a
pattern binder's meta where `inferPatternType` mints it; `generalize` rewrites that record to the
scheme's Bound variable (`acc : a` at the local publish, above); then `unbind` rewrites it AGAIN at the
first instantiation of the scheme in the body, and `go xs 1` is the only instantiation, so the record
lands on `Int`.  `acc : a` is the binder's own type — `go` is polymorphic, and if the body used it at
two types `Int` would be indefensible — while `h : Int` and `t : List Int` are that single use.

**FOLLOW-UP 1 (not taken, and the biggest thing I found).**  The hook's answer for ANY pattern binder
under a generalised binding is frame-dragged by `unbind`'s `binderTypes` rewrite to the first instance
the module takes of that binding's scheme.  It is right whenever there is exactly one instance and
arbitrary otherwise, and it is why E14's three lines cannot be made one frame by fixing the head alone.
The fix would be to stop `unbind` from rewriting `binderTypes` (`Subst.scala:650-652`) so a binder of a
polymorphic binding keeps the scheme's Bound variable; that changes shipped hover answers for every
local under a polymorphic binding, moves the 6.2b set, and is Tier 1 — an item, not a patch.  Ticket
this as E15.

## 7. Gates

Tier 0 (parallel where independent; the two A/Bs ran ALONE, last, each round waiting for load < 1.3):

| gate | figure | log |
|---|---|---|
| `core/compile` + `core/copyResources` | success | `logs/probe3.log`, `logs/lsp-1.log` |
| `TestTolerantCheck` | **55 of 55**, 0 failed (51 baseline + 4 new); re-run last on the final tree | `logs/ttc-final.log` (and `logs/ttc-3.log`) |
| `TestLoopTrace` | 3 properties OK; **720 segments, 720 agree, 0 skipped** | `logs/looptrace-suite.log` |
| corpus `corpus-run.sh --batch` BEFORE (worktree) | **89 LOADED / 79 REJECTED / 0 UNKNOWN of 168** | `logs/corpus-before.log` |
| corpus AFTER (this tree) | **89 / 79 / 0 of 168**, verdict list byte-identical to before (`diff` clean; the `.out` text is not compared — batch-loader nondeterminism, 6.2b review §1.2) | `logs/corpus-after.log`, `verdicts-before.txt`, `verdicts-after.txt` |
| `repl-smoke.sh` | **8 groups PASS** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); goldens untouched (`git status`) | `logs/repl-smoke.log` |
| `lsp-smoke.sh` | **PASS 573 checks** (565 baseline + 8 new), 0 FAIL | `logs/lsp-1.log` |
| boot | `session: ready — 129 modules in 16.0s` | `logs/lsp-smoke-server.log` |
| `.ei` droppings | **0** (`find . -name '*.ei' -not -path './tracker/g1-*'`) | — |
| diff-stat parity | `git diff --stat --histogram` == `--histogram -w` | — |
| line endings | all five touched files LF, `file` type unchanged before/after | — |

Tier 1 (`Subst.scala` changed), both sides:

| gate | figure | log |
|---|---|---|
| `looptrace-corpus.sh` (`LOOPTRACE_PAR=3`), before in the worktree with `LOOPTRACE_BIN` at the main tree's model binary, after here | 18 groups a side, `rc=0`, `timeouts=0`, `dropped=0`, model agrees on every segment on both sides | `logs/lt-before.log`, `logs/lt-after.log` |
| `trace-ab.py` per group (all record kinds) | **18 of 18 groups IDENTICAL, sinmoved 0, 3 210 881 segments** | `logs/ab/*.log` |
| — path rewrite | the worktree path occurs ONLY in field 3 (`loc`) — CHECKED for every group with an awk field scan before rewriting, 0 occurrences in any other field — and was rewritten to the main-tree path in all 18 before-traces (`lt-before-rw/`) | — |
| `ei-diff.sh --snapshot --batch` with `-Dermine.loadInSeries=true`, both sides | **274 interfaces captured on BOTH sides**, 7m11s / 7m12s, neither side re-run | `logs/ei-before.log`, `logs/ei-after.log` |
| `ei-classify.py` | `interfaces: A 274  B 274  only-in-A -  only-in-B -` ; **`0 of 274 interfaces differ`** ; `bindings by verdict: {'identical': 3523}` | `logs/ei-classify.log` |
| `g1-validate.sh` | **9 of 9 PASS**; `g1-compare: 129 files, 1447 signatures, EQUIVALENT`; no drift from `tracker/g1-baseline` | `logs/g1.log` |

Tier 2 (full `core/test`) is the reviewer's; expect 1063 baseline + 4 new = 1067.

## 8. The A/Bs

Both ran alone, interleaved before/after, each round gated on 1-minute load < 1.3 (the harness
re-checks with `PERF_MAX_LOAD=1.3` and prints the load it ran at).  `logs/ab-batch.log`,
`logs/ab-editor.log`; scripts `ab-batch.sh`, `ab-editor.sh`.

**Batch** (`perf-bench.sh batch -n 3`, in-process "Loaded 129 modules" median):

| round | before (`336b5204`) | after |
|---|---|---|
| 1 | 11.40 s (spread 0.12) | 11.26 s (spread 0.32) |
| 2 | 11.21 s (spread 0.24) | 11.31 s (spread 0.19) |
| **median of rounds** | **11.305 s** | **11.285 s** |

−0.02 s, −0.18 % — inside the ~1 % floor, and inside a single round's own spread.  Expected: the
strict path pays one boolean test per guarded site and writes nothing.

**Editor** (`perf-bench.sh editor -k 15`, debounce pinned 300 ms, `reused=97/154` on every run):

| round | before round trip | after round trip | before typecheck | after typecheck |
|---|---|---|---|---|
| 1 | 0.908 s | 0.918 s | 0.540 s | 0.545 s |
| 2 | 0.911 s | 0.923 s | 0.540 s | 0.540 s |
| 3 | 0.912 s | 0.933 s | 0.535 s | 0.550 s |
| 4 | 0.908 s | 0.908 s | 0.535 s | 0.530 s |
| **median** | **0.9095 s** | **0.9205 s** | **0.5375 s** | **0.5425 s** |

+0.011 s round trip (+1.2 %) and +0.005 s typecheck (+0.9 %).  Read honestly: that is inside the
after side's own round-to-round spread (its four medians span 0.908–0.933, 2.7 %) and round 4 is a
dead heat on both measures, but the after side is on the high side in three of four rounds, so the
right claim is "within the measured noise, not demonstrably zero".  The before side reproduces 6.2b's
after-side figures (0.913 round trip, 0.530 typecheck) to 0.004 s.  What this item adds to a check is
one map insert per implicit binding head, one extra `subType` pass over that map per
`instantiateType` while it is non-empty, and per local head one zonk, one `displayScheme` and one
`alphaEq` — the last three only under `wantLocals`.

## 9. Files changed

```
45	5	core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala
13	2	core/src/main/scala/com/clarifi/reporting/ermine/lsp/Resident.scala
153	9	core/src/main/scala/com/clarifi/reporting/ermine/session/TolerantCheck.scala
161	2	scalacheck-binding/src/main/scala/TestTolerantCheck.scala
44	3	tracker/tools/lsp-client.py
                 tracker/lsp-tests/Heads.e   (new, 28 lines)
```

New pins: four `TestTolerantCheck` properties (the E14 shape's head, argument and the hook's answer
beside it; the two fact-3 controls; the signed local head; the head cross-check on the fixture), the
head set and anti-vacuity inside the 253-file sweep, and eight `lsp-smoke` checks through the real
server on the new `Heads.e` (head at def and at a use, the argument, the hook's answer, both controls,
the signed head, and the fixture being clean).  Two existing pins MOVED, each with the reason written
in place: `6.2: every LET and WHERE binder gets a type` (`idy : a -> a` → `forall a. a -> a`),
`6.2b: a where-bound polymorphic local's LAMBDA argument shares its letters` (`pl`, same), and
`lsp-client.py`'s "hover polymorphic where binder".  No other pin moved; the 6.2b disagreement set and
every 7.2 assertion are untouched and green.

## 10. Follow-ups found and not taken

1. **The hook's frame drag (E15).**  §6.  The biggest of these, and the reason E14's three lines are
   still two frames.
2. **Rule 1 hides a real constraint.**  A local head whose scheme has existential row constraints
   hovers without them (57 heads).  That matches the `.ei` and it is what makes the hover stable and
   readable, but it IS information the checker holds and the editor does not show.  If it is ever
   wanted, it wants a normal form for constraint sets (order-free), not a change here.
3. **`sameUpToVarNaming` cannot see a `Skolem`** — 6.2b review R-8, still open; the head check reuses
   the same comparator and inherits it.
4. **`AlphaEq.aeq`'s `Forall` case pairs binder lists POSITIONALLY**, so two schemes that differ only
   by a permutation of their quantifier are reported unequal (measured: 12 of 21 pairs in
   `logs/probe-warm2.log`).  It did not matter here once `displayScheme` normalised the order, but any
   future sweep comparing schemes will hit it.
5. A stale polling shell from the 6.2b session was still spinning on
   `pgrep -f 'looptrace-corpus.sh'` from a command line containing that pattern — the self-wait trap
   the brief warns about; it can never exit.  Killed (pid 3327678).  Nothing of mine polls that way.

---

# FIX ROUND (2026-09-13) — the review's code findings

Review of record: `tracker/loopmodel/LSP-6.2c-REVIEW.md`, **ACCEPT WITH FIXES**.  This round applies its
one blocking finding and four small ones, plus the two documentation items the user ruled on.  Same
rules: no commits, no `git stash`, pre-change worktree untouched at `../ermine-scala-wt-62c`.  Logs
under the same scratch dir.

**Decision (a) (review R-3) — RULED BY THE USER, 2026-09-13:** a `let`/`where` HEAD renders its
published scheme with `forall` and constraints, exactly like a top-level hover; pattern binders and
equation arguments stay monotypes with no `forall`.  The rendering therefore stays as built.  The
roadmap amendment is the orchestrator's (the `tracker/LSP-ROADMAP.md` diff in this tree is theirs, not
mine); `docs/lsp.md` is mine and is rewritten below (R-4).

## 11. What changed, and the numbers now

### R-1 (blocking) — rule 1 was an ERASE; it is now a per-constraint FILTER

Confirmed exactly as reported: `Subst.generalize` puts the whole published set in ONE `Exists`, so
`case Exists(_, xs, _) if xs.nonEmpty => Exists(l.inferred)` dropped every sibling constraint as soon as
one existential appeared anywhere.  `TolerantCheck.displayScheme` now filters constraint by constraint,
and the predicate is **VISIBILITY**, which is strictly stronger than the review's suggested
"mentions none of `xs`": a constraint is KEPT when every type variable in it is one the scheme
quantifies or one its body shows.

Why visibility and not the review's version — this is the fix round's own finding, and it is measured.
With the review's predicate the 7.2 cache-invisibility property FAILED (`logs/ttc-fix1.log`):

```
### 7.2 sweep: … 2 render a LOCAL differently on two COLD checks; mismatches 3
###   Report.e: LOCALS differ between a SHIFTED and an UNSHIFTED warm check
###   Tree.e: LOCALS differ between a SHIFTED and an UNSHIFTED warm check
```

Two causes, both in `logs/fix-warm.log`, both about constraints that name variables the hovered type
never shows:

```
Report.e (1340,7)  warm: … a <- (r, r2, s, k, v) => List (Record k) -> Report f z
                   ctl : … a <- (s, r, r2, k, v) => List (Record k) -> Report f z     <- rhs ORDER
Report.e (1393,7)  warm: … a1 <- (v1, k, r2, r, s) => List (Record k) -> …
                   ctl : …                            List (Record k) -> …            <- PRESENT vs ABSENT
```

The second is the checker's own nondeterminism, not the display's: the published row-constraint set of
two cold checks of one unedited file differs (7.2's own "publish different row constraints on two COLD
checks" counter has been non-zero since before this item), so whether that constraint exists at all
flickers.  Visibility removes both classes from the hover — and nothing a reader can act on, since the
variables in question appear nowhere in the type being hovered.  `Num a` on a quantified `a` is kept,
which is the whole point of E14.

### R-7 — constraint ORDER normalised, and the partition right-hand side with it

`constraintKey` serialises a constraint with every variable replaced by its position in the body's
first-occurrence order, then by its NAME, and never by its id; the kept set is sorted by it, and a
partition's right-hand side is re-ordered by it too (`normaliseConstraint`; `new Part`, not the smart
constructor).  Rule 2 (binder order) is unchanged.  Result — warm probe over every module that has ever
flickered in this item (Report, Tree, Relation ×4, SoftRelation ×2, Op, Helpers ×4, Signatures ×4,
Comprehensions, Accumulate), `logs/fix-warm2.log`:

```
## Report.e: 0 local(s) differ of 966      ## Tree.e: 0 local(s) differ of 47
## Relation.e: 0 of 62 / 0 of 134 / 0 of 4 ## SoftRelation.e: 0 of 17 / 0 of 8
## Op.e: 0 of 56   ## Helpers.e: 0 of 55/171/68/115   ## Signatures.e: 0 of 24/33/35/66
## Comprehensions.e: 0 of 6   ## Accumulate.e: 0 of 1
```

and the 7.2 property (`logs/ttc-fix4.log`), with BOTH halves of R-7's point quoted:

```
### 7.2 sweep: 253 clean modules of 257 — … 16 render differently on an UNSHIFTED reuse (pre-7.2),
    2 publish different row constraints on two COLD checks, 1 on two WARM checks,
    0 render a LOCAL differently on two COLD checks; mismatches 0
```

The checker still publishes different row constraints on two cold checks (2 modules).  The local hover
is stable because what it shows no longer depends on that — not because the source of it moved.

### R-6 — the cross-check compares the PUBLISHED scheme

`headAgree` read `headRecorded`, i.e. the DISPLAYED scheme, so an elided head's constraint set looked
trivial and the pair counted as agreed.  It now reads the raw record.  `headDisagreements` therefore
means what the property claims — the meta-vs-scheme gap — and it moved **8 → 65, with nothing leaving**
(`logs/ttc-fix3.log`; the 57 additions are the heads whose entire published set is ambiguous row
residual, which rule 1 elides and the pre-6.2c rho could not carry either).  Because 65 def-sites is not
a table a reader can use, the USER-VISIBLE half is now carried and pinned separately:
`Result.headShown`, the heads whose hover actually displays a constraint.

### R-5 — `headElided` now has a pin, and so does the fixture

`Result.headLost`: a published constraint over the scheme's OWN QUANTIFIED variables only (`Num a`,
`AsPresentation pr`) must survive into the displayed scheme.  Deliberately NARROWER than the filter's
predicate and computed from the published set, so it can fail — and under the pre-fix rule it did, at
the review's 246 events.  Asserted empty on the fixture and over the corpus.  The unit fixture is the
review's own witness shape (`mixLocal`/`gx`, a row residual from `appendR` beside `PrimitiveNum a` in
ONE scheme) and pins the rendered string, `headElided >= 1` and `headLost == Nil`.

### R-8 — every added executable line in `Subst.scala`, with its guard

`git diff … | grep -v comments` (13 lines, verbatim):

| # | line | guard |
|---|---|---|
| 1 | `var headTypes: Map[(Int, Int), Type] = Map()` | **none** — a field.  One reference to the shared empty `Map` per `SubstEnv`; no work, and nothing reads it unless `recordBinders`.  It cannot be guarded without a `lazy val`, which would add a check on every access. |
| 2 | `if (hm.recordBinders && (hm.binderTypes.nonEmpty \|\| hm.headTypes.nonEmpty)) {` | is the guard.  **Tightened this round** (R-8's third bullet): the map at line 3 is no longer allocated when both records are empty. |
| 3-6 | `val sv = …` and the two rewrites | behind line 2 |
| 7-8 | `val scheme = RowTrace.withBinding(…)(generalize(…))` | **none** — the hoist of the expression that was already there, evaluated exactly once as before.  Semantically identical; no added work on any path. |
| 9-12 | `if (hm.recordBinders) b.v.loc match { case p: Pos => … }` | is the guard |
| 13 | `b.v -> b.v.as(scheme)` | **none** — the same expression as before, reading the hoisted val. |

So the strict path pays **one boolean test at each of two sites**, and nothing else.  That is what §2's
sentence should have said, and Tier 1 is what carries it.

### R-10 — the two inherited notes, written into the field comment

`SubstEnv.headTypes`'s comment now states (a) that the KIND instantiation (`instantiateKind`) rewrites
`hm.types` and neither record, so a scheme recorded before one of its kind metas is solved keeps the
unsolved kind meta — the 6.2b review's §1.7 asymmetry, inherited; and (b) that the record's
read-modify-write is non-atomic on a shared `SubstEnv` and is safe only because `recordBinders` is set
by `checkWith` alone, which the server drives single-threaded with a fresh `SubstEnv` per component.

### R-4 — `docs/lsp.md`

Rewritten in the local-hover section: the lead paragraph now separates the HEAD (published scheme,
`forall` and constraints, with the amendment named) from every other local binder (monotype, no
`forall`); the `let`/`where` bullet states the one display rule and says plainly that the `.ei` makes a
DIFFERENT choice (keeps existential row constraints, deletes tautologies instead) so the two are not
one predicate; the equation-argument condition no longer says "a `forall` on a local is what the
rendering rule forbids" but that the reconstruction divides an arrow chain and has no scheme to hand
out; the 29 silent binders are explained as the limit of the two mechanisms (both record MONOTYPES —
`d.mono`, `t.mono`), with the old justification named as no longer holding; and a new paragraph, **"Two
frames in one `let`"**, shows E14's three lines and says which answer is which frame and why, ending at
ticket E15.

## 12. The head table, remade (`logs/ttc-fix4.log`, `logs/fix-shown12.log`)

```
### 6.2c heads: agreed 174, disagreed 65, requantified 94, constraint elided 58,
                usable constraint lost 0, hover SHOWS a constraint 12
```

The twelve heads whose hover displays a constraint, every one hovered through the real server after the
fix:

| def-site | head | shows |
|---|---|---|
| `LetAndPatternMatching.e:8:7` | `go` | `Num a` — **ticket E14** |
| `Layout/Report.e:643:9` | `capture` | `AsPresentation a` |
| `Layout/Report.e:1111:11` | `ope` | `Primitive a` |
| `Layout/Report.e:1604:9` | `npair` | `AsPresentation pr` |
| `Layout/Scan.e:70:9` | `go` | `Primitive c` |
| `Relation/Scan.e:150:9` | `extractF` | `Relational f` |
| `Relation/Op.e:178:9` | `showE` | `PrimitiveString s` |
| `Relation/Op.e:181:9` | `comma` | `(AsOp opl1, AsOp opl)` — **recovered by R-1** |
| `core/examples/Accumulate.e:34:14` | `f` | `RelationalComb a` — **recovered by R-1** |
| `Layout/Report/SoftRelation.e:41:7` | `pickk` | `RelationalComb a` — **recovered by R-1** |
| `Algebra/Comprehensions.e:206:11` | `step` | `a <- (b, (\|balanceEur\|))` — **recovered by R-1** |
| `Layout/Report/Relation.e:39:7` | `f` | `a <- (r2, (\|cutoff\|))` — **recovered by R-1** |

Five heads gained a constraint the erase had dropped, including both class constraints the review named
(`AsOp opl`, `RelationalComb a`).  One head LEFT the shown set: `Layout/Report.e:690:7` (`defaultLg`),
whose `a1 <- (i, k, v1)` names `a1` and `v1`, which its displayed type shows nowhere — and whose sibling
heads in the same module are the ones two checks disagree about (above).  It is still in
`headDisagreements`, because the checker does hold that constraint.

**The R-1 witness, before and after** (`logs/fix-hover-after.log`, the review's `fix/HeadsRev3.e`):

```
before (review, this build)  g : forall a (a1: rho) (b: rho). List a -> a -> Record a1 -> Record b -> a
after                        g : forall a (a1: rho) (b: rho). Num a =>
                                   List a -> a -> Record a1 -> Record b -> a
E14, unchanged by this round go : forall a. Num a => List a -> a -> a   (def-site and use)
```

**6.2b disagreement set: still UNCHANGED** — `split-vs-hook agreed 2869 disagreed 14`, same fourteen.

## 13. Gates re-run after the fix

| gate | figure | log |
|---|---|---|
| `core/compile` | success | `logs/ttc-fix4.log` |
| `TestTolerantCheck` | **56 of 56**, 0 failed (51 baseline + 5 new: the fix round adds the R-1/R-5 fixture property) | `logs/ttc-fix4.log` |
| — its sweep lines | `6.2b sweep … agreed 2869 disagreed 14`; `6.2c heads: agreed 174, disagreed 65, requantified 94, elided 58, lost 0, SHOWS 12`; `7.2 sweep … 0 render a LOCAL differently on two COLD checks; mismatches 0` | same |
| `TestLoopTrace` | 3 properties OK; **720 segments, 720 agree, 0 skipped** | `logs/looptrace-fix.log` |
| `lsp-smoke.sh` | **PASS 573 checks**, 0 FAIL (unchanged: the new fixture's head has no row residual) | `logs/lsp-fix.log` |
| corpus `--batch` | **89 LOADED / 79 REJECTED / 0 UNKNOWN of 168**, verdict list identical to the before side | `logs/corpus-fix.log`, `verdicts-fix.txt` |
| `g1-validate.sh` | **9 of 9 PASS**; `g1-compare: 129 files, 1447 signatures, EQUIVALENT`; no drift from the baseline | `logs/g1-fix.log` |
| `ei-diff.sh --snapshot --batch` with `-Dermine.loadInSeries=true` (after side re-run; the before-side snapshot is the same untouched worktree build and was reused) + `ei-classify.py` | `274 interfaces captured`; `interfaces: A 274  B 274  only-in-A -  only-in-B -`; **`0 of 274 interfaces differ`**; `{'identical': 3523}` | `logs/ei-fix.log`, `logs/ei-classify-fix.log` |
| warm probe, 21 module checks | 0 locals differ anywhere | `logs/fix-warm2.log` |

`looptrace-corpus` was NOT re-run and does not need to be: the only `Subst.scala` change this round is
inside the `recordBinders` guard (the added `nonEmpty` test) plus comments, so no line outside the flag
changed behaviour.  The A/Bs were not re-run either (the review attributed the item's editor cost at
0.33 %).

No probe source survives: `Probe62c.scala` and `Probe62cWarm.scala` are deleted again (copies in the
scratch dir).  `.ei` count 0 at the end.
