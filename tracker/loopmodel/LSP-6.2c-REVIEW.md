# Review — LSP interstage item 6.2c (E14, the constrained local head)

Reviewer's report.  Brief `tracker/loopmodel/briefs/brief-LSP-6.2c-review.md`; implementer's report
`tracker/loopmodel/LSP-6.2c-HEADS.md`; implementer's brief `tracker/loopmodel/briefs/brief-LSP-6.2c.md`;
item of record `tracker/LSP-ROADMAP.md` § "Interstage item 6.2c"; ticket E14.  Branch `scala3-migration`,
HEAD `b0eee247` plus the uncommitted deliverables.  Before build: the worktree at
`../ermine-scala-wt-62c` (`336b5204`), used as handed over and left untouched apart from its
`tracker/repl-classpath.txt`.  No commits, no `git stash`; the two files I instrumented were restored by
copy and verified by md5.

Scratch (every log path below is relative to it):
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.2c/`.

---

## VERDICT: ACCEPT WITH FIXES

The mechanism paragraph is right and reproduces exactly.  The record is the right mechanism and is in
the right place.  Every identity gate is green on both sides and reproduces the implementer's figures to
the digit.  E14's head is fixed: `go : forall a. Num a => List a -> a -> a` at def and at a use, on the
real server.

But **display rule 1 is not the rule the report describes, and as written it drops constraints a reader
needs** — including the very class constraint E14 is about.  That is R-1, it changes shipped hover
answers, and it must be fixed before the item closes.  Three more are documentation debts the brief
asked for by name (R-3, R-4) or that the report states wrongly (R-2), and the rest are notes.

---

## 1. THE R-ITEMS

### R-1 — CODE (blocking).  Rule 1 elides the WHOLE constraint set, not the constraints with existentials

`core/.../session/TolerantCheck.scala:462-471`, the predicate at **:465**:

```scala
val keep = q match {
  case Exists(_, xs, _) if xs.nonEmpty => Exists(l.inferred)   // <- erases every constraint
  case other                           => other
}
```

`Subst.generalize` (`Subst.scala:1735-1752`) builds **one** `Exists` for the entire published constraint
set — `mkSimplified(tml.loc, nxs, subType(zipTypes(xs,nxs),cs), publishing)` with `nxs` *all* the
ambiguous variables and `cs` *all* the constraints.  So a single existential anywhere in the set erases
every sibling constraint, whatever it quantifies.  The doc comment ("**A constraint** that quantifies its
OWN EXISTENTIALS is ELIDED … A constraint with no existentials — `Num a` — … is KEPT") describes a
per-constraint filter.  The code is a set-level erase.

**Witness, real server, this build** (`logs/hover-after3.log`, fixture `fix/HeadsRev3.e`):

```
mix3 xs rr ss = g xs 1 rr ss
  where g []       acc r s = acc
        g (h :: t) acc r s = const (g t (h * acc) r s) (appendR r s)
```

```
top level   HeadsRev3.mix3 : forall (a: rho) (b: rho). (exists (c: rho). c <- (b, a)) => List Int -> Record a -> Record b -> Int
LOCAL head  g              : forall a (a1: rho) (b: rho). List a -> a -> Record a1 -> Record b -> a
```

`g`'s published scheme carries `Num a` **and** `exists c. c <- (a1, b)`.  The hover shows neither.  The
`Num a` — the constraint this whole item exists to surface — is gone, and the head now asserts an
*unconstrained* `forall`, which is a stronger and false claim than the pre-6.2c bare rho
(`logs/hover-before.log`: `g : List a -> a -> Record a1 -> Record b -> a`).  So this is not a regression,
it is the fix failing to reach a class it reports as fixed.

**At corpus scale** (scratch instrumented build, `displayScheme` printing what it drops, over the
253-module sweep; `logs/probe-disp.log`, restored afterwards by copy + md5):

| | |
|---|---|
| elision events | **930** |
| events that dropped at least one constraint with NO existential of its own | **246** |
| distinct (module, lost-constraint-set) pairs | **19** (`elided-needed.txt`) |
| modules | Report.e 114, SoftRelation.e 36, Relation.e 30, Tree.e 18, Op.e 18, Comprehensions.e 18, Accumulate.e 12 |
| CLASS constraints among the losses | `AsOp opl` (Op.e), `RelationalComb a` (Accumulate.e, SoftRelation.e) |

The incoherence is visible inside one module: the report's own table keeps `a1 <- (i, k, v1)` at
`Report.e:690:7` because that constraint has no existentials, while another `Report.e` head loses
`a <- (v, k, i, r)` — the same kind of constraint, over quantified variables — only because a sibling in
its set has one.

**The change** (`TolerantCheck.scala:464-467`), filter instead of erase:

```scala
case Exists(el, xs, cs) if xs.nonEmpty =>
  val xi = xs.map(_.id).toSet
  Exists(el, Nil, cs.filterNot(c => Type.typeVars(c).exists(v => xi(v.id))))
```

I did not apply or test it; the sweep's `disagreed` set will move (see R-6) and that movement is the
item's, to be reported not repinned.

### R-2 — REPORT.  "the `.ei` drops them too" is false, and the two predicates are not related

Report §4 rule 1 justifies the elision with "the compiler does not publish those constraints either —
the `.ei` for such a binding carries the bare type".  Refuted.  `bin/ermine` on the R-1 fixture
(`logs/ei-mix3.log`, `.ei` deleted after):

```
mix3 : forall (a: rho) (b: rho). (exists (c: rho). c <- (b, a)) => Builtin.List Builtin.Int -> Builtin.Record a -> Builtin.Record b -> Builtin.Int
```

The `.ei` **keeps** the existential row constraint.  The `.ei` case the report cites
(`(exists h t. r <- (t,h)) => Relation r -> Relation r` against `Relation r -> Relation r`) is a
*different* mechanism, named two hundred lines away in the same file: `TolerantCheck.scala:955-964` sets
`publishing = true` for the module's top-level implicit group, which turns on `mkSimplified`'s **C12
tautology deletion** — a deletion of *provable* constraints, in the top-level group only.  A local group
generalises with `publishing = false` (my probe: `P62C publish go2 … publishing=false`), so nothing of
the kind runs for a local head at all.

Not shared, not merely similar: on one and the same constraint the two predicates go opposite ways.  The
paragraph must be rewritten, and the report's closing argument for the rendering ("a local head now reads
exactly the way a top-level head has always read") is false for the 57 elided heads until R-1 lands.

### R-3 — DECISION OVERRIDE, UNDECLARED (and `docs/lsp.md`)

"no `forall` on locals" is **Stage-3 Decision (a) itself**, `tracker/LSP-ROADMAP.md:671-676`:

> (a) Local hover shows the binder's MONOTYPE after solving, with the enclosing binding's generalized
> metas rendered as type variables; **no `forall` on locals** (the top-level's hover shows the scheme).

It is not the 6.2 report's reading of it.  6.2c overrides it for heads — deliberately and, I think,
correctly — but the override is nowhere declared: the report cites Decision (a) only for the signed-head
and letter-agreement clauses, and the roadmap's Decisions block says overrides go in "with a note, not
silently".  The item of record authorises the *constraint* ("the generalised scheme WITH its `Num`
constraint") but says nothing about the quantifier.

`docs/lsp.md` is unchanged and now contradicts the build in three places:

* **:125-127** — "A **local binder** hovers … with no `forall` and with still-free metas rendered as type
  variables (`idy : a -> a`)".  `idy` now hovers `forall a. a -> a` (the moved pin).
* **:136-139** — "the argument's own type must be a monotype (a rank-N argument is skipped, because a
  `forall` on a local is what the rendering rule forbids)".
* **:151-155** — the 29 silent binders are justified by the same sentence.

That third one is a coherence problem, not just stale prose: 29 binders stay silent on the authority of a
rule heads no longer obey.  The real reason is narrower and should be written as such — the split and the
hook record *monotypes* (`d.mono`, `t.mono`), and a rank-N binder has no monotype to record.

**Fix**: append the Decision-(a) amendment to the Stage-3 Decisions block; rewrite those three places in
`docs/lsp.md`; update the `idy` example.

### R-4 — THE TWO FRAMES ARE EXPLAINED NOWHERE A USER LOOKS

The implementer's brief required E14's two frames — `acc : a` (the scheme's frame) beside `h : Int` (the
hook's instance frame) — to be "explained in the hover text or the docs — say which and why".  Neither.
The hover carries no note; `docs/lsp.md` is not in the changed-files list.  The explanation exists only in
`LSP-6.2c-HEADS.md` §6 and in a `TestTolerantCheck` comment.  **Fix**: a paragraph in `docs/lsp.md`'s
local-hover section, naming E15 and saying which answer is which.  (`docs/lsp.md` already carries the
weaker caveat about a local head's *letters*; this is the stronger one about its *frame*.)

### R-5 — TEST.  `headElided` is printed and never asserted

`Result.headElided` is computed (`TolerantCheck.scala:612`), carried out through `Resident.Checked`, and
printed in the sweep line — but no property asserts anything about it.  Rule 1, the one display rule that
removes information, has no pin at all: it can start or stop firing anywhere in the corpus and every test
stays green.  After R-1 the pin that matters is a SET, in the style of R-4 from the 6.2b review: the heads
whose elision drops a constraint with no existential of its own — asserted EMPTY.

### R-6 — the head cross-check under-reports the content change, by construction

`headAgree` (`TolerantCheck.scala:603-620`) reads `headRecorded`, which has already applied
`displayScheme`.  So for an elided head `q.isTrivialConstraint` is true and the pair is counted
**agreed** — the 57 elided heads cannot appear in `headDisagreements` however much information they lost.
`### 6.2c heads: agreed 231, disagreed 8` therefore means "the hover string changed in content", not "the
meta and the published scheme differ".  That is a defensible thing to measure, but the property's comment
says the second.  Fix the comment; after R-1 the set will grow and that growth is the finding.

On the brief's vacuity question: the pin does **not** go vacuous if `headType` later stops reading the
meta — `headAgree` reads `Subst.substType(i.v.extract)` directly, not through `headType` — and it fails
loudly if the record itself breaks (`headRecorded` empty → `headAgreed` 0 → the `>= 200` floor).  It is a
real drift alarm on the meta-vs-scheme gap.

### R-7 — rule 1 HIDES the flicker; it does not fix it, and rule 2 does not cover the residual

The elided block *is* the nondeterministic part: the constraint set and its existential binder list are
id-keyed, and the ids move between two checks of one unedited file.  Rule 2 normalises the **quantifier's
binder order**; it does not normalise the **order of the constraints inside a kept `Exists`**, so a head
with two or more kept constraints can still render two ways.  Unmeasured — I did not find one in the
corpus, but nothing tests for it.

The evidence that the source nondeterminism is untouched is in the very sweep line that reports the 0:

```
### 7.2 sweep: … 16 render differently on an UNSHIFTED reuse (pre-7.2),
    2 publish different row constraints on two COLD checks, 1 on two WARM checks,
    0 render a LOCAL differently on two COLD checks; mismatches 0
```

The checker still publishes different row constraints on two cold checks; the local hover is stable
because it no longer prints them.  Both halves should be said in the report.

### R-8 — REPORT, minor.  "every executable line behind `hm.recordBinders`" — two are not

* `Subst.scala:154` `var headTypes: Map[(Int, Int), Type] = Map()` — a field, initialised on every
  `SubstEnv`, guarded by nothing.  Costs the shared empty-map reference; observes nothing.
* `Subst.scala:939-940` the `val scheme = …` hoist — a pure refactor of the old inline expression, not
  behind the flag, semantically identical.
* `Subst.scala:250` `val sv = Map(v -> e)` is now allocated whenever `recordBinders` is set, even when
  both maps are empty (it used to be built inside each branch).  Editor-only.

The two guarded blocks are `Subst.scala:249-253` (`instantiateType`) and `Subst.scala:947-950` (the
record).  On the strict path the change is one boolean test, exactly as claimed — but the *sentence* as
written is false and Tier 1 is what carries it.

### R-9 — REPORT, minor.  "`restrictTypes` is NOT involved"

True at `go`, not in general.  My re-run of the probe (`logs/probe-mech.log`) prints, from the same run:

```
P62C infer  go2^51714 @TC(8:7) … restrictTypes(tts)=          zonk(meta)=List a -> a -> a metaInTypes=true
P62C infer  gl^51728  @TC(13:7) … restrictTypes(tts)=51791    zonk(meta)=a -> (a, b)      metaInTypes=true
```

`tts` is empty at the E14 binding; it is not empty at the `pairLocal` binding two shapes down.  The
correct statement is the sentence's second half — the head's meta is never among them.

### R-10 — NOTE, inherited.  kind metas, and the loader threads

Only one site binds a TYPE meta (`Subst.scala:229-254`, `instantiateType`) and 6.2c covers it — that is
why the eager rewrite is enough.  But `Subst.scala:233` (`hm.types = subKind(s, hm.types)`, the KIND
instantiation) rewrites `hm.types` and rewrites neither `binderTypes` nor `headTypes`: a head scheme
recorded before one of its kind metas is solved keeps the unsolved kind meta.  Exactly the asymmetry the
6.2b review flagged (§1.7), inherited unchanged.

Separately: `hm.headTypes = hm.headTypes + (…)` is a non-atomic read-modify-write on a shared `SubstEnv`,
in a function whose own comment says generalisation "runs on several loader threads".  Unreachable —
`recordBinders` is set only by `checkWith`, which the server drives single-threaded (Decision 3) with a
fresh `SubstEnv` per component — but that is the argument, and it is worth one sentence in the field
comment, as 6.2b's R-9 asked for `binderTypes`.

---

## 2. WHAT I REFUTED, AND WITH WHAT

| claim (report) | verdict | evidence |
|---|---|---|
| "the `.ei` for such a binding carries the bare type" (§4 rule 1) | **REFUTED** | `bin/ermine fix/HeadsRev3.e` → `mix3 : … (exists (c: rho). c <- (b, a)) => …` (`logs/ei-mix3.log`) |
| "A constraint with no existentials — `Num a` — … is KEPT" (§4 rule 1) | **REFUTED** | `g : forall a (a1: rho) (b: rho). List a -> a -> Record a1 -> Record b -> a`, `Num a` gone (`logs/hover-after3.log`); 246 of 930 elisions corpus-wide (`logs/probe-disp.log`) |
| "a local head now reads exactly the way a top-level head has always read" (§3) | **REFUTED for the 57 elided heads** | the two lines of the R-1 witness, same file, same run |
| "`restrictTypes` is NOT involved" (§1, as a general statement) | **PARTLY REFUTED** | `restrictTypes(tts)=51791` at `gl` (`logs/probe-mech.log`) |
| "every executable line behind `hm.recordBinders`" (§2) | **PARTLY REFUTED** | `Subst.scala:154`, `:939` |
| "the after side is on the high side in three of four rounds" (§8) | **REPRODUCED, then ATTRIBUTED AWAY** | my four rounds are also high in 3 of 4; the three sites cost 4 ms of a 1210 ms check (§5) |
| §1 mechanism; the 8-site set; the 6.2b set; §7's gate figures | **CONFIRMED** | §4, §6 below |

---

## 3. THE MECHANISM (§1 of the brief) — verified, and the alternative

Probe re-run from the implementer's saved sources, adapted to the post-fix `Subst.scala` (patch
`patch-probe.py`, runner `ProbeRev62c.scala` under `scalacheck-binding/src/main/scala/` for the run,
DELETED after; both files restored by copy, md5 verified):

```
P62C infer   go2^51714 @TC(8:7) meta=51715 rp=List a -> a -> a restrictTypes(tts)= zonk(meta)=List a -> a -> a metaInTypes=true
P62C publish go2^51714 @TC(8:7) scheme=forall a. PrimitiveNum a => List a -> a -> a zonk(meta)=List a -> a -> a publishing=false
```

`metaInTypes=true`, `tts` EMPTY at this binding, the scheme carries `PrimitiveNum a`, `publishing=false`.
The paragraph holds as written (modulo R-9).

**Could the head's meta have been bound to the SCHEME instead?**  No, and there is no one-line
alternative either.

* *Bind the meta to the scheme* (`hm.types += (metaVar -> scheme)`): the scheme is a `Forall` whose
  quantified variables are `Bound`.  Putting it in `hm.types` makes every later `substType` yield a
  polymorphic type for a rho-level meta and leaks `Bound` variables into unification.  Not viable under
  HMF.
* *`as` the head `V` itself*: `inferImplicitBindingTypes` already does exactly that — `b.v -> b.v.as(scheme)`
  — and the result never reaches the head.  `inferType`'s `Let` case (`Subst.scala:1025-1032`) is
  `val (gp,ds,m) = inferBindingGroupTypes(…)` followed by `subTerm(m, body)`: **`m` is applied to the body
  and then discarded**.  The binding's own `V` in the tree keeps Lower's meta by construction.  Making the
  head see the scheme means rewriting the tree's binding heads too — a change on the batch path, not an
  editor-only one, and Tier 1 with real risk.

So a side-channel keyed by the def-site is the minimal mechanism, and `SubstEnv` is where the def-site
key already lives.  **The record is the better answer, and it is not a matter of taste.**

---

## 4. THE RECORD, ATTACKED (§2 of the brief)

**(a) Executable added lines in `Subst.scala`** — see R-8.  Two guarded blocks (`:249-253`, `:947-950`),
one unguarded field (`:154`), one unguarded refactor (`:939-940`).

**(b) The two "would break" cases, and their pins.**

* *If `headTypes` WERE rewritten at `unbind`/`generalize`*: `unbind` mints fresh metas for a scheme's
  `Bound` variables at each instantiation, so `go`'s record would become `List Int -> Int -> Int` at
  `go xs 1` — E14's own head, back to one frame behind, which is precisely the hook's frame drag (E15).
  **Pinned**: `TestTolerantCheck` "6.2c: a CONSTRAINED local head hovers its constraint, not a bare
  variable" asserts `go2 : forall a. PrimitiveNum a => List a -> a -> a` *together with* `h2 : Int` — the
  pair is the proof the head was not dragged; plus lsp-smoke's two `Heads.e` head checks.
* *If a FREE meta in a recorded scheme were NOT rewritten at `instantiateType`*: `let g x = (x, y)`
  publishes `forall a. a -> (a, b)` before `b := Int`, and the head would hover `b`.  **Pinned**:
  "6.2c: a head that mentions a variable fixed LATER still shows the settled type" (`gl : forall a. a -> (a, Int)`)
  and lsp-smoke "hover a head whose variable is fixed later".  Both cases are covered; no gap.

**(c) The shapes.**  All through the real server, `fix/HeadsRev4.e`, `logs/hover-4.log`:

| shape | head | answer |
|---|---|---|
| `where`-bound head | `wgo` | `forall a. Num a => List a -> a -> a`; its split arg `acc : a` |
| a `let` inside a let's BODY | `outer1` / `inner1` | `Int -> Int` / `Int -> Int` |
| a `let` inside a let's BINDING | `outer2` / `inner2` | `forall a. Num a => a -> a` / `forall a. Num a => a -> a`; arg `m : a` |
| mutually recursive local group | `ev` / `od` | `forall a. List a -> Bool` / `forall a. List a -> Bool` |
| one signed + one unsigned in ONE group | `sgn2` / `uns` | `Int -> Int` (declaration verbatim, Decision (a)) / `Int -> Int` |

Each head has exactly one record at its own def-site: the record is written once per binding in the
group's `generalize`, keyed by `b.v.loc`, and def-sites are unique within a module.

**(d) Key collision with a pattern binder.**  `headTypes` and `binderTypes` are separate maps, so the two
records cannot contaminate each other.  In `out` (the single `locals` map) the **head wins**: in the
`Let` case (`TolerantCheck.scala:686-690`) `binding(b2)` writes unconditionally and runs before `args` and
`alt`, and `hook` only writes `if out.get(k) == None`; a binder at the same key would be routed into the
`split`-comparison branch and could show up as a spurious `binderDisagreement` rather than overwrite the
head.  Not reachable in practice — a head `V` sits at the start of an equation and a pattern binder inside
its patterns — and nothing pins it.  Note, not a finding.

**(e) `Resident.scala` 13/2.**  The four new counters on `Checked` and their pass-through at :511-516;
nothing else.  Fast mode still answers null for heads, and for a stronger reason than a guard: at
`Resident.scala:427` fast mode returns `TolerantCheck.Result(Nil, Map())` without checking at all, so
`locals` is empty and `headType` is never called.

**(f) The dead-component pin.**  `collectLocals` runs only inside the `case Some(...)` arm, so a component
that dies contributes nothing; and the pin exists — `TestTolerantCheck:472` "6.2: a component that died
contributes no locals" asserts `!got.contains("bad")`, and `bad` is a binding HEAD.  Covered.

---

## 5. THE TWO DISPLAY RULES (§3 of the brief) — the part the user has to judge

**Rule 1's exact predicate** is in R-1: *if the published constraint is an `Exists` with a non-empty
existential binder list, drop the entire constraint*.  Not per-constraint.

**Is anything a user needs elided?**  Yes, and it is the item's own subject matter.  The class constraint
`Num a` on a quantified variable is dropped whenever any sibling constraint carries an existential (R-1's
witness); corpus-wide, 246 of 930 elisions lose at least one constraint with no existential of its own,
two of them class constraints.  The `{..r}` / derived-column shapes the brief asked me to try are the ones
that produce the existential in the first place — `appendR r s` gives `exists c. c <- (r, s)` — so they are
exactly the shapes that also take the class constraint down with them.

**Is the predicate the `.ei`'s?**  No — R-2.  Different code, different intent (tautology deletion vs
ambiguity hiding), different answer on the same constraint, and only one of them runs for a local group.

**Rule 2 is alpha-renaming only.**  `displayScheme` reorders the `Forall`'s `ts` list; the body refers to
those binders by identity, not by position, so the type is unchanged and only `Pretty.ppForall`'s letter
assignment moves.  The display copy never leaves hover.  It DOES mean the same type can print different
letters at top level (no reordering: `Definitions`/`.ei` print the published scheme as generalised) and in
a local head — visible in the R-1 witness, where the top-level prints `c <- (b, a)` and the local prints
`a1`/`b` in first-occurrence order.  **This does not break Decision (a)**: the arity split peels its
domains from the *displayed* head and renders them with `prettyTypeIn(head, …)`, so a binding's arguments
agree with its own head's letters — confirmed on the real server, `acc : a` under
`go : forall a. Num a => List a -> a -> a`, and `m : a` under `inner2 : forall a. Num a => a -> a`.  The
only residual is head-vs-enclosing-top-level, which `docs/lsp.md` already documents as a caveat.

**Does rule 1 fix the flicker or hide it?**  It hides it — see R-7.  The elided block is the
nondeterministic part; the 7.2 counter goes to 0 because the unstable text is no longer printed, and the
line that reports the 0 also reports that the checker still publishes different row constraints on two
cold checks.  Reproduced: `### 7.2 sweep: … 0 render a LOCAL differently on two COLD checks; mismatches 0`
(`logs/ttc.log`).

**My reading for the user.**  Hiding an *ambiguous* row residual from a local hover is the right call:
the reader cannot act on it, it is long, and it is unstable.  Hiding it by erasing the whole constraint
set is not — it silently removes the information the item was opened to add, in 7 modules of the corpus,
and it makes a local head claim an unconstrained `forall` that the compiler does not hold.  R-1's filter
keeps the good half of the decision and drops none of the actionable content.  If the ambiguous residual
is ever wanted back, it wants an order-free normal form for constraint sets, which is a different item.

---

## 6. E14, E15 AND THE SWEEPS

### The E14 hover, both builds, real server (`logs/hover-before.log`, `logs/hover-after2.log`, `logs/hover-t.log`)

```
                                    BEFORE (336b5204)          AFTER
LetAndPatternMatching.e  go  (def)  List a -> a -> a           forall a. Num a => List a -> a -> a
                         go  (use)  List a -> a -> a           forall a. Num a => List a -> a -> a
                         acc        a                          a
                         h          Int                        Int
                         t          List Int                   List Int
Heads.e (new fixture)    go         List a -> a -> a           forall a. PrimitiveNum a => List a -> a -> a
                         acc / h / t   a / Int / List Int      a / Int / List Int
                         gl         a -> (a, Int)              forall a. a -> (a, Int)
                         zl         Int                        Int          (monomorphic: no quantifier)
                         sg         Int -> Int                 Int -> Int   (signed: as declared)
```

The top-level convention is confirmed on the same runs: `HeadsRev.mul : forall a. Num a => a -> a -> a`
and `HeadsRev.idt : forall a. a -> a` — unchanged on both sides — so an unelided local head does now read
like a top-level one.  A monomorphic local still renders without a quantifier.

### E15 — REAL, and stronger than the report says

Witness (`fix/HeadsRev2.e`, both builds, `logs/hover-after2.log` / `logs/hover-before.log`):

```
e15b = let kk (h2 :: t2) = h2
           kk []         = kk []
       in (kk (1 :: []), kk (True :: []))

kk : forall a. List a -> a        h2 : Int        t2 : List Int
```

`kk` is instantiated at `List Int` **and** `List Bool` in its own body, and the hook answers `Int`.  So
"first instantiation wins" is exactly right, and the witness shows the answer is *arbitrary* rather than
merely one-of-one.  Ticket E15 should carry this fixture.  Two notes for whoever takes it:

* the plain shape the brief suggested — `let k x = x in (k 1, k True)` — does **not** show the drag
  (`k : forall a. a -> a`, `x : a`): `x` is an equation argument, so the arity SPLIT answers and the split
  peels the (correct) head.  The binder has to be inside a constructor pattern for the hook to answer.
* it is not a 6.2c regression: the before build gives the same three lines.

### The head agreement sweep (`logs/ttc.log`)

```
### 6.2c heads: agreed 231, disagreed 8, requantified 94, constraint elided 57
### 6.2c head disagreements: Report.e:643:9 ;; Report.e:690:7 ;; Report.e:1111:11 ;; Report.e:1604:9 ;; Scan.e:70:9 ;; Op.e:178:9 ;; Scan.e:150:9 ;; LetAndPatternMatching.e:8:7
```

Reproduced to the digit.  What is compared: the DISPLAYED published scheme against
`Subst.substType(i.v.extract)`, the meta hover read until 6.2c — see R-6 for what that does and does not
catch.  Since the hover now reads the record, a disagreement is a **drift alarm on the meta-vs-scheme
gap**, not a hover defect: it says "6.2c changed this head's hover in content".

All eight read at source, and all eight are one class — a `let`/`where` head whose published scheme
carries a constraint the pre-generalisation rho cannot hold:

| def-site | head | shape at source |
|---|---|---|
| `guide/LetAndPatternMatching.e:8:7` | `go` | `let` in `product`, `h * acc` → `Num a` (ticket E14) |
| `Layout/Report.e:643:9` | `capture` | `where` in `softRelation`, `asPresentation prv'` → `AsPresentation a` |
| `Layout/Report.e:690:7` | `defaultLg` | `let` in `keyValueTabular`, `joinKey softr hk (rheader r)` → `a1 <- (i, k, v1)` |
| `Layout/Report.e:1111:11` | `ope` | `where` in `scaled`, `primExpr#` → `Primitive a` |
| `Layout/Report.e:1604:9` | `npair` | `let` in `softValueCtor#`, `sortStrategy#` → `AsPresentation pr` |
| `Layout/Scan.e:70:9` | `go` | `where` in `columns`, `heading_C (val_L k) v` → `Primitive c` |
| `Relation/Scan.e:150:9` | `extractF` | `where` in `multiply`, `fromRelation runner` → `Relational f` |
| `Relation/Op.e:178:9` | `showE` | `where`, `existentialF s (unsafePrim# pt)` → `PrimitiveString s` |

All eight hover WITH the constraint on this build (spot-checked `LetAndPatternMatching.e:8:7`,
`Report.e:690:7`, `Report.e:643:9` through the real server: `logs/hover-after2.log`, `logs/attr-run.log`).
One observation in passing: `defaultLg`'s kept constraint prints as
`forall {a} n pres d (i: rho) (v: a). a1 <- (i, k, v1) => …` — `a1`, `k` and `v1` are not bound by the
quantifier the hover shows.  Pre-existing free-meta rendering, not 6.2c's, but it is what a "kept"
constraint can look like.

### The 6.2b set — UNCHANGED (`logs/ttc.log`)

```
### 6.2b sweep: 253 clean modules of 257 — Arg(equation) 2874/2874, Arg(other) 1776/1804, CaseBound 116/117,
    DoBound 31/31, LetBound 165/165, WhereBound 92/92; misses 29; split-vs-hook agreed 2869 disagreed 14
```

Same 14 def-sites, `agreed` 2869 — confirmed, byte-for-byte with 6.2b's.  The property's comment does
explain why `LetAndPatternMatching.e:8:17` and `:9:17` stay (scheme frame vs instance frame) and points at
the E15 write-up.  Accepted.

---

## 7. GATES (all re-run by me; every figure below is from my own log)

### Tier 0

| gate | figure | log |
|---|---|---|
| `core/compile` + `core/copyResources` | success (and again after each restore: `core/clean core/compile core/copyResources`) | `logs/compile.log`, `logs/restore-compile.log`, `logs/restore2-compile.log` |
| `TestTolerantCheck` | **55 of 55**, 0 failed, 0 errors (51 baseline + 4 new) | `logs/ttc.log` |
| `TestLoopTrace` | 3 properties OK; **720 segments, 720 agree, 0 skipped**, hashdiff 0, eqdiff 0 | `logs/looptrace-suite.log` |
| corpus `corpus-run.sh --batch` BEFORE (worktree) | **89 LOADED / 79 REJECTED / 0 UNKNOWN of 168** | `logs/corpus-before.log` |
| corpus AFTER | **89 / 79 / 0 of 168**; verdict lists `diff`-identical | `logs/corpus-after.log`, `verdicts-before.txt`, `verdicts-after.txt` |
| `repl-smoke.sh` | **8 groups PASS** — aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5 (66 checks); goldens untouched (`git status`) | `logs/repl-smoke.log` |
| `lsp-smoke.sh` | **PASS 573 checks**, 0 FAIL (565 + 8) | `logs/lsp-smoke.log` |
| boot | `session: ready — 129 modules in 24.9s` (under load) | `/tmp/lsp-smoke.log` |
| `.ei` droppings | **0** (`find . -name '*.ei' -not -path './tracker/g1-*'`), main tree and worktree | — |
| diff-stat parity | `git diff --stat --histogram` == `--histogram -w` (checked three times, incl. after both restores) | — |
| line endings | all five touched files + `Heads.e`: `file` output identical to `git show HEAD:<f> \| file -` | — |

The 8 new lsp-smoke checks: `Heads.e clean`; head at its def-site; the same head at a use; its argument in
the head's frame; the hook's answer beside it; a head whose variable is fixed later; a local settled
outright; a signed local head.  Moved pins (three, each with its reason written in place): `lsp-client.py`
"hover polymorphic where binder" (`idy : a -> a` → `forall a. a -> a`), and in `TestTolerantCheck`
"6.2: every LET and WHERE binder gets a type" (`idy`) and "6.2b: a where-bound polymorphic local's LAMBDA
argument shares its letters" (`pl`).  No other pin moved.

### Tier 1 (`Subst.scala` changed) — both sides

| gate | figure | log |
|---|---|---|
| `looptrace-corpus.sh` `LOOPTRACE_PAR=3`, before in the worktree with `LOOPTRACE_BIN` at the main tree's model binary | **18 groups a side**, `rc=0`, `timeouts=0`, `dropped=0`, model agrees on every segment on both sides | `logs/lt-after.log`, `logs/lt-before.log` |
| path rewrite | the worktree path occurs in **field 3 only** — verified by an awk field scan of every field of all 18 before-traces (`fields=[3]` for each, no exceptions) — then rewritten into `lt-before-rw/` | inline in the command; `lt-before-rw/` |
| `trace-ab.py` per group, ALL record kinds | **18 of 18 IDENTICAL, sinmoved 0, 3 210 881 segments** | `ab/*.log` |
| `ei-diff.sh --snapshot --batch` `-Dermine.loadInSeries=true`, both sides | **274 interfaces captured on BOTH sides**; neither side re-run | `logs/ei-before.log`, `logs/ei-after.log` |
| `ei-classify.py` | `A 274  B 274  only-in-A -  only-in-B -`; **0 of 274 interfaces differ**; `{'identical': 3523}` | `logs/ei-classify.log` |
| `g1-validate.sh` | **9 of 9 PASS**, 0 FAIL; `g1-compare: 129 files, 1447 signatures, EQUIVALENT`; no drift from `tracker/g1-baseline` | `logs/g1.log` |

### Tier 2

`sbt core/test`, alone, last: **1067 of 1067, 0 failed, 0 errors**, 26m39s — §9.

---

## 8. THE A/Bs — my figures beside the implementer's

Both ran ALONE, interleaved before/after, each round waiting for 1-minute load < 1.3 and printing the load
it ran at; each side from its own tree; debounce pinned at 300 ms by `perf-bench.sh`; `reused=97/154` on
every editor run.  `logs/ab-editor.log`, `logs/ab-batch.log`; scripts `ab-editor.sh`, `ab-batch.sh`.

### Editor (`perf-bench.sh editor -k 15`), four interleaved rounds

| round | load | before RT | after RT | before typecheck | after typecheck |
|---|---|---|---|---|---|
| 1 | 1.09 / 1.16 | 0.906 | 0.896 | 0.535 | 0.520 |
| 2 | 1.07 / 1.25 | 0.891 | 0.913 | 0.520 | 0.530 |
| 3 | 0.96 / 1.12 | 0.901 | 0.907 | 0.525 | 0.535 |
| 4 | 1.14 / 0.97 | 0.902 | 0.913 | 0.530 | 0.540 |
| **median of rounds** | | **0.9015** | **0.9100** | **0.5275** | **0.5325** |

**+0.0085 s round trip (+0.94 %), +0.005 s typecheck (+0.95 %).**  Beside the implementer's
0.9095 → 0.9205 (+1.2 %) and 0.5375 → 0.5425 (+0.9 %): the same sign, the same size, and — as they
reported — the after side high in **3 of 4** rounds (rounds 2, 3, 4; round 1 is lower on both measures).
Both sides' absolute levels moved down ~0.01 s between their session and mine, which is machine drift of
the same magnitude as the effect.

**Attribution** (the brief's trigger fired, so I did it).  Scratch instrumented build — `System.nanoTime`
around the three sites, restored by copy and md5 (`patch-attr.py`, `logs/attr-compile.log`,
`logs/restore2-compile.log`) — on ONE cold check of `Layout/Report.e` with `wantLocals=true`, which is the
editor bench's own target file (`logs/attr-run.log`):

```
P62CATTR displaySchemeMs=1 n=90  headAgreeMs=1 n=31  headTypesSubMs=2 n=713
         binderTypesSubMs=8 n=5017  instantiateTypeCalls=24712      [typecheck 1.21s]
```

* the `headTypes` rewrite at `instantiateType`: **2 ms** over 713 non-empty rewrites (of 24 712 calls)
* `headAgree` (the head comparison): **1 ms** over 31 heads
* `displayScheme` + `varOrder` (the two display rules): **1 ms** over 90 calls

**4 ms of a 1210 ms check — 0.33 %.**  6.2b's `binderTypes` rewrite alone costs twice that.  So the
+0.94 % the A/B shows is not this item's work; it is noise at the machine's floor.  That is the strongest
statement the measurement supports, and it is stronger than the report's "within the measured noise, not
demonstrably zero".

### Batch (`perf-bench.sh batch -n 3`, in-process cold median), two interleaved rounds

| round | before | after |
|---|---|---|
| 1 | 11.23 s (spread 0.18) | 11.24 s (spread 0.17) |
| 2 | 11.24 s (spread 0.34) | 11.36 s (spread 0.27) |
| **median of rounds** | **11.235 s** | **11.300 s** |

**+0.065 s, +0.58 %** — inside the ~1 % floor and inside a single round's own spread.  The implementer
measured −0.18 % on the same pair of builds; the two results bracket zero, which is what "no effect"
looks like.  Expected: the strict path pays one boolean test and writes nothing.

---

## 9. TIER 2 — full `core/test`, alone

```
[info] Passed: Total 1067, Failed 0, Errors 0, Passed 1067
rc=0 wall=1599s
```

**1067 of 1067** (1063 baseline + the 4 new `TestTolerantCheck` properties), **0 failed, 0 errors**, wall
**26m39s**, run alone and last (`logs/coretest.log`).  Neither E12 (`TestInterfaceRoundTrip`) nor E13
(`TestLegend."extra args are ignored"`) fired, so no suite needed its one allowed re-run, and nothing else
was red.

---

## 10. FOLLOW-UPS I CONFIRM AS REAL

1. **E15, the hook's frame drag** — confirmed with a two-instantiation witness (§6).  Ticket it with that
   fixture and the note that the binder must be inside a constructor pattern to see it.
2. **Rule 1 hides information** — now R-1 (blocking) for the part that is a defect, and a genuine open
   design question for the ambiguous-residual part, which wants an order-free normal form for constraint
   sets.
3. **`sameUpToVarNaming` cannot see a `Skolem`** (6.2b R-8) — still open, inherited by the head check.
4. **`AlphaEq.aeq`'s `Forall` case pairs binder lists POSITIONALLY** — real, and now partly masked by
   rule 2; any future sweep comparing schemes will hit it.
5. **kind metas are not rewritten in either record** (R-10) — inherited from 6.2b, unchanged.

---

## 11. NOT CHECKED

* The proposed R-1 change: not applied, not compiled, not swept.  I do not know what it does to the
  `disagreed` set (it will grow) or to the `elided` count.
* Head-granular counting for R-1: I measured elision EVENTS (246 of 930) and distinct
  (module, lost-set) pairs (19).  `displayScheme` is called ~3× per head, so the affected head count is
  roughly a third of 246 — I did not key the instrumentation by def-site.
* The 7.2 cache-invisibility matrix as a separate run: I ran the whole `TestTolerantCheck` suite (which
  contains it, all green) but not the 5.5 edit set on its own.
* The per-file (non-batch) corpus run and the per-file `.ei` sweep — batch only, both sides, as the brief
  specifies.
* `lsp-smoke.sh` on the BEFORE side, and `boot` on the before side.
* `where`-bound heads, nested lets, mutual recursion and the mixed signed/unsigned group are exercised
  through the real server only (§4c) — there is no `TestTolerantCheck` pin for any of them.
* The Scala 2.11 back-port branch.
* `docs/lsp.md`'s other sections (I read only :120-170).
* `tracker/tools/__pycache__/` was already untracked before I started; I left it alone.

---

## 12. HOUSEKEEPING

* No commits, no `git stash`.  Two files were instrumented twice (mechanism probe, then attribution) and
  restored by copy each time; `md5sum` matches `orig/md5.txt` on both
  (`755e9f440384cedab69055982e9b6ed2` Subst.scala, `f5557b98153b4485ac0b4c858e177a0b` TolerantCheck.scala)
  and the tree was rebuilt from clean afterwards.
* The probe source `scalacheck-binding/src/main/scala/ProbeRev62c.scala` was added for one run and
  deleted; my `.e` fixtures live in the scratch dir only.
* `.ei`: my one `bin/ermine` invocation wrote 129 stdlib interfaces into `core/target/.../modules`, and
  the full `core/test` left 7 more there; all deleted.  `find . -name '*.ei' -not -path './tracker/g1-*'`
  is **0** in both trees.  (Worth knowing for whoever runs the commit gate: `core/test` itself drops
  `.ei` files, so the droppings check has to run AFTER it, not before.)
* The worktree `../ermine-scala-wt-62c` shows `M tracker/repl-classpath.txt` and nothing else.
* No JVM of mine is running.  Four of my own wait-shells survived their Bash timeouts and were killed;
  so were **five more from the 6.2b session** (pids 3353994, 3356883, 3358922, 3362501, 3364953), each
  spinning on `pgrep -f 'ab-batch.sh'` / `'ab-editor.sh'` from a command line containing the pattern —
  the self-wait trap the brief names, the same one the implementer found one instance of.  They had been
  polling every 15-20 s throughout both A/B sessions.  No polling shell of mine or of 6.2b/6.2c survives.
* `git status --short` shows the implementer's five modified files, their three new files (report,
  `Heads.e`, the review brief), the pre-existing `tracker/tools/__pycache__/`, and this report.
