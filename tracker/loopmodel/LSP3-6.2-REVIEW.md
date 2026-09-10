# Review: LSP Stage 3, item 6.2 — types at every binder (PARTIAL)

Independent review of the uncommitted 6.2 deliverables on branch `scala3-migration`, tree at
`b3b160c` (= `361ff28` plus five orchestrator briefs; no code between them).  Implementer report
`tracker/loopmodel/LSP3-6.2-LOCALS.md`; briefs `briefs/brief-LSP3-6.2.md` and
`briefs/brief-LSP3-6.2-review.md`.  Reviewer edited nothing but a scratch directory and this file.

**VERDICT: FIX-THEN-ADVANCE.**  The delivered code is correct, in budget and well pinned; every
gate reproduced.  What must be fixed before this is committed is the FORK WRITE-UP: §8's
recommended option 1, as written, does not work — I ran it and the recorded meta comes back
unconstrained.  The fix is three lines in the report plus two off-by-one counts; the code needs
no change.

---

## 1. Findings

| id | severity | status | what |
|---|---|---|---|
| R-1 | **HIGH** | **CONFIRMED (premise) / REFUTED (the proposed fix as written)** | The premise failure is real and reproduces exactly; but §8 option 1's mechanism — "record `v.loc -> t` in `inferPatternType`, merge into `TolerantCheck` after each component and zonk" — returns an unconstrained variable, for the *same* reason the item failed. |
| R-2 | MEDIUM | CONFIRMED | §8 misses a fourth option that needs no `Subst.scala` change at all and covers most of the 4663 `Arg` binders: split the binding head's own inferred type by its arity. |
| R-3 | LOW | CONFIRMED | lsp-smoke is **234** checks, not 233: report §5 and `docs/lsp.md` both say 233 (§7's gate table is right). |
| R-4 | LOW | CONFIRMED | The Decision-(a) rendering caveat is real and can actively mislead: an enclosing binding printed `forall a b. a -> b -> b` while its local helper hovered `h : a -> a`, where the local's `a` IS the enclosing `b`. Stated in the report, absent from `docs/lsp.md`. |
| R-5 | INFO | CONFIRMED | The 253-file sweep property asserts 0 misses for `LetBound`/`WhereBound` but only *prints* the pattern-binder counts, so option 1 landing would not flip the sweep. It would flip the dedicated "PATTERN binders are absent" property and four lsp-smoke checks, which is enough — but the sweep's own title still says "the 180-file sweep". |
| R-6 | INFO | CONFIRMED | `collectLocals.pat` does not recurse `SigP`; `SigP` is constructed nowhere in the tree (`Pattern.scala:117` is the only mention besides its own `subst`), so the omission is dead code, not a hole. Term coverage IS complete against `Term.scala`. |
| R-7 | — | **CONFIRMED SOUND** | The Decision-(b) cache invariant survived five attacks (below). I could not break it, and the "top-level statements start at column 1" premise it rests on is enforced by the parser, not merely assumed. |

### R-1 — the premise failure, and whether the hook would work

**The premise failure: CONFIRMED, re-derived and reproduced live.**

Re-derived from the code:

* `Lower.Ctx.binderV` (`rename/Lower.scala:88-94`) mints one `V[Type]` per renamer binder id whose
  `loc` is `pos(defSiteSpan)` and whose `extract` is a fresh meta (`unspecified`, `:80-81`).  True.
* `Subst.inferImplicitBindingTypes` (`Subst.scala:797-799`) does `val tp = substType(b.v.extract)`
  … `subsumeType(tp, rp)` — so a BINDING HEAD's own meta is the solved type.  True.
* `Lower.pattern` (`Lower.scala:320`) builds `VarP(v.map(_ => annotOf(c, n.span)))`; `V.map`
  replaces `extract`, and `annotOf` (`Lower.scala:364-365`) is `Annot.annotAny` — `exists a. a`
  with hole id **-1** (`Annot.scala:27-30`).  The binder's meta survives only in the BODY's
  `Var` occurrences, which carry the same `V` id relocated (`Lower.scala:113`).
* `Subst.inferPatternType`'s `VarP` case (`Subst.scala:1055-1057`) calls `unbindAnnot`, whose
  `refreshList(Free, a.loc, …a.exists)` (`Subst.scala:605`) ALWAYS mints a fresh existential;
  `t = VarT(thatFreshVar)` and `Patterned(t, List(v as t), ks, List(), ts)` with `ts` = that same
  fresh var.  Nothing is written back to the `V` this side holds.

Live, on `module TC where / import Bool / f x = x && True / g x y = x` (scratch `Probe.scala`,
run against `tracker/repl-classpath.txt` inside one `Session.subst` block after
`inferImplicitBindingTypes`):

```
-- binding f
   published type             : Bool -> Bool
   zonk of the HEAD's own meta: Bool -> Bool     [Lower meta, id=51712]
   pattern binder 'x' at 4:3  vid=51714
       annot body = -1        (exists=List(-1), hole id=-1)
       zonk of annot body     : a
   body OCCURRENCE 'x' vid=51714
       zonk of Lower's binder meta: a            <== what 6.2 would have read
```

So the item's mechanism gives `Bool -> Bool` for the head and an unconstrained `a` for the
argument — worse than silence, exactly as §1 says.  4811 of 5056 local binders unreachable:
reproduced verbatim by the sweep (below).

**Would the option-1 hook work?  NO, not as §8 describes it.**  I ran the proposed recording
against the real machinery, in the same session, with the same pattern:

```
   inferPatternType gave t   = 51736
   Patterned.xs              = List(51736)   (the existential unbindAnnot minted)
   zonk right after recording: a
   body inferred as          : Bool
   zonk AFTER body inference : Bool   <== the hook's answer if zonked THERE
   zonk AFTER restrictTypes  : a      <== the hook's answer if zonked LATER (as proposed)
   hm.types still holds it?  : List((51736,None))
```

**The deciding line is `Subst.scala:153`** — `def restrictTypes(xs) = hm.types = hm.types -- xs` —
reached with the recorded meta in `xs` from **`Subst.scala:942`** (`inferType`'s `Lam` case,
`restrictTypes(ts ++ pt.xs)`) and **`Subst.scala:1036`** (`inferAltTypesPrime`'s
`restrictTypes(rtypes)`, where `rtypes` accumulates `pts.xs` at `:1035`).  The meta the hook would
record IS `pt.xs.head` (`Subst.scala:1055-1057` returns `t` and `ts = nxs` from the same
`unbindAnnot`).  So by the time `TolerantCheck` merges `hm.binderTypes` "after each component and
zonks", the binding has been deleted from the substitution and the zonk returns a free variable —
the failure the hook was meant to cure.

**Why `Remember` does not have this problem, and what option 1 actually costs.**  `hm.remembered`
survives `restrictTypes` because it is never zonked *later*: it is kept fully substituted at all
times, eagerly, in three places — `instantiateType` (`Subst.scala:187`, `subType(Map(v -> e), …)`
applied to the whole map on every single instantiation), `unbind` (`:586`) and `generalize`
(`:1624`).  That eager maintenance IS the mechanism; the `Map` in `SubstEnv` is the trivial part.
So option 1 is viable, but its real shape is:

* the ~8 lines in `inferPatternType` + `SubstEnv`, **plus**
* the maintenance line in `instantiateType` (`:187`) — mandatory, this is what defeats
  `restrictTypes`; and
* the maintenance lines in `unbind` (`:586`) and `generalize` (`:1624`) — needed if a still-free
  pattern meta is to render as the same variable the enclosing scheme quantified (without them a
  polymorphic argument still renders as *a* letter, via `Pretty.lookupFresh`, just not a
  consistent one — the same soft problem as R-4).

That is four sites, three of them on the checker's hottest path, and the flag-off cost is one
extra empty-`Map` traversal per instantiation unless each site is individually guarded (the
existing `remembered` line at `:187` pays that cost unconditionally today, so the marginal figure
is small — but it is a `Subst.scala` change on the batch path, gated only by a flag, which is a
Tier-1 question and not the "batch-invisible" claim §8 makes).  There is a cheaper correct
variant — record `substType(t)` at the *end of the alt/lam, before* `restrictTypes` — which needs
no map maintenance at all, but is still a `Subst.scala` edit, and it records the type as it stands
at that instant, so a constraint arriving later from a sibling of the same SCC would be missed.

Verdict on the fork: option 1 is the right direction and IS achievable, but §8's "~8 lines, and
the only one that is honest … `TolerantCheck` merges `hm.binderTypes` after each component and
zonks" would ship a feature that silently returns unconstrained variables.  The write-up must say
`instantiateType`.

**(b) Option 2's consequence: CONFIRMED.**  Replacing the annot with `Annot(loc, Nil, Nil,
VarT(ourMeta))` gives `a.exists = Nil`, so `unbindAnnot` returns `nxs = Nil` and
`Patterned.xs = Nil`.  `xs` is read at `Subst.scala:937-940` (`tanns = pt.xs.map(…)`; the
"unannotated parameters used polymorphically" refusal), `:942` (`restrictTypes`) and `:1029`
(`checkSkolemEscape(pts.ss, rtypes ++ pts.xs, …)`).  With `xs` empty the polymorphism refusal can
never fire, so the editor would accept programs batch rejects.  The rejection is right.  The
obvious repair — keep an existential and put OUR var in it — does not work either: `unbindAnnot`
refreshes it unconditionally (`Subst.scala:605`).

**(c) Is there an option 4?  Yes — R-2.**

### R-2 — the missed option: split the head's inferred type by arity

Inference does not leave the pattern's type anywhere reachable — I checked all three places the
brief named.  The `Alt` is never returned (only a `Type` is); the `Gamma` (`vsp ++ g`) is local to
the call; `hm.remembered` is keyed by `Memory` id and only carries what a `Remember` node asked
for (which is §8's option 3).  So nothing already-computed can be READ.

But for an **equation head** the argument types are recoverable by ARITHMETIC on the type
`TolerantCheck` already has, with no `Subst` change: `b.arity` is the number of patterns, and the
head's inferred type, `unbind`-ed, is an arrow chain whose first `arity` domains are the argument
types in order.  Live (Part C of the same probe, same session):

```
-- f : Bool -> Bool                  arity=1   split: List(x : Bool)
-- g : forall a b. a -> b -> a       arity=2   split: List(x : a, y : a)
```

(The two `a`s in the `g` line are NOT a bug in the split — they are two distinct metas from
`unbind`, printed by two independent `Pretty.prettyType` calls that each restart the letter
supply.  It is R-4 again, and it is the one thing this option would have to get right before it
could be shipped: the argument types of one binding must be rendered together.)

This costs one `unbind` + `arity` pattern matches per binding, reuses the collection, cache and
hover plumbing already delivered, and reaches the argument binders of every top-level and every
`let`/`where` equation — which is where the great majority of the 4663 `Arg` binders live.  It
does NOT reach lambda arguments, `case` binders or `do` binders, and it must be conservative:
emit only when the chain really yields `arity` arrows (a type alias, a constraint or a rank-N
signature can hide them) and only for `VarP` patterns directly under the alt, not vars nested
inside a `ConP`/`ProductP`.  It is a reconstruction rather than the checker's own answer, so it
should be pinned against the checker on the corpus before being trusted.  This belongs in front
of the user next to option 1: it is smaller, Tier-0, and covers the gesture §8 identifies as the
most common one.

### R-3 — count

`tracker/tools/lsp-smoke.sh` on this tree: **`PASS lsp (234 checks)`**.  Report §5 says "207 → 233
checks (+26)" and `docs/lsp.md` now says "233 checks"; §7's gate table says 234, which is right
(the Nav.e block gained one check net — one `null` assertion became two positive ones — on top of
the 26 in the new block, and 207 + 27 = 234).  Two one-character fixes.

### R-4 — the rendering caveat

Reproduced (scratch `Probe2.scala`, case F), on `outer x y = h y / where h w = w`:

```
   outer : forall a b. a -> b -> b
   locals: [((6,9), a -> a)]
```

The local `h` hovers `h : a -> a`; its `a` is the variable the enclosing signature calls `b`.  A
reader who hovers both in the same minute is told the same letter means two different things.
The report states the caveat honestly; `docs/lsp.md`'s new paragraph does not, and it is the file
a user reads.  One sentence there ("a local's type variables are named independently of the
enclosing binding's") would close it.  Not worth solving in this item — solving it means threading
one `Pretty` supply through a whole file's hovers.

### R-7 — attacking the cache invariant

`Entry`'s argument is that a def-site inside a group is a function of (`startLine`, extent text),
both of which are in the fingerprint (`TolerantCheck.keys`, `x.startLine + ":" + off.text(x)`).
The load-bearing premise is that top-level statements start at column 1 — otherwise the extent
text, which starts at `startCol` on the FIRST line only, could stay identical while every column
on that line shifted.  **That premise is enforced, not assumed**: I tried a module with indented
top-level statements and the header parse rejects it outright (`TC:3:3: expected '{', eof, or
semicolon`), so the case cannot arise.

Five live warm-vs-cold comparisons through `checkWith(wantLocals = true)`, each comparing the
def-site KEYS and the rendered types (scratch `Probe2.scala`):

| attack | reuse | locals warm == cold |
|---|---|---|
| A trailing whitespace after a statement (the 5.5 lesson) | 2/2 reused | yes — `(5,11)` both sides, nothing moved |
| B a comment line inserted INSIDE a `where` block | 0/2 reused (invalidated) | yes — `(6,9)` → `(8,5)` both sides |
| C a comment line inserted BETWEEN two statements | 1/2 reused — the one above it kept, the one below re-checked | yes — `(5,11)` kept, `(7,11)` → `(8,11)` both sides |
| D a blank line above everything | 0/1 | yes — `(5,11)` → `(6,11)` |
| E one extra space before a `let` binder on the head line | 0/2 | yes — `(5,11)` → `(5,12)` |

C is the interesting one: partial reuse, one component's positions restored from cache while the
other's moved, and warm still equals cold.  I could not break it.  The `Entry` comment's reasoning
is sound as written; it would be worth one clause noting that "column 1" is a *parser* guarantee.

---

## 2. What was delivered — spot checks

**`collectLocals` walk.**  Complete against `Term.scala`: `App`, `Sig`, `Lam`, `Rigid`, `Case`,
`Let`, `Remember` are recursed; `Var`, `Hole`, `EmptyRecord` and `Product(loc, n: Int)` have no
subterms (`Product` carries an arity, not children), so the catch-all is right.  Pattern walk
covers `VarP`, `AsP`, `ConP`, `ProductP`, `StrictP`, `LazyP`; `WildcardP` and the literals bind
nothing; `SigP` is dead (R-6).

**Explicit heads by declaration — the report's claim CONFIRMED.**  `typeCheckExplicitBinding`
(`Subst.scala`) unbinds `binding.ty` and checks against that; the line that would have written the
result back to the binder is present and COMMENTED OUT (`// _ <- unifyType(binding.ty,
v.extract)`), and `inferBindingGroupTypes` (`:755-757`) checks a COPY (`es.map(e => e.subst(…,
em))` where `em` maps `v -> v as declaredType`).  The tree's own `V` therefore keeps Lower's
untouched meta.  Reading `e.ty.body` is the only correct choice; the four sweep misses that
found it (`Report.e:1154:11 scalafy` &c.) are exactly local `ExplicitBinding`s produced by
`NewPipeline.assemble`'s `pairSigs`.

**Position join.**  `Pos(fileName, current, line, column, ending)` — Lower builds
`Pos(file, "", sp.startLine, sp.startCol, false)`; `collectLocals` keys on `(p.line, p.column)`;
`Definitions` looks up `(b.defSite.startLine, b.defSite.startCol)`.  Same numbers.  `Inferred` is
a separate `Loc` case class so `case p: Pos` correctly excludes it, and `p.fileName == file` gates
out relocated and builtin `V`s.

**Kind hover.**  `Pretty.ppKindSchema` is the printer `:kind`/`browse` use.  A `class` head IS
covered structurally even though lsp-smoke does not test one: `Session.processTypeDefComponent`
installs `ClassBlock` as `addCon(Con(l, global(mn, v), ClassDecl, ks))` with a kind schema, so it
answers through the same `env.cons` path.  `ownTyCon`'s TYPE-fixity-first / term-fixity-fallback
cannot change an existing answer: for an `Idfix` name the two Globals are equal, and if neither is
in `cons` the result is `None` → null, as before.

**Tests.**  The six new `TestTolerantCheck` properties do pin both sides of the line, including an
anti-vacuity clause on the renamer's binder table.  The sweep asserts 0 `LetBound`/`WhereBound`
misses; it reports the pattern kinds as counts only (R-5).  The lsp-smoke checks that assert the
PARTIAL behaviour (`hover arg binder -> null`, `hover arg use -> null`, `hover case binder ->
null`, `hover case-bound use -> null`, `hover arg x -> null (pattern binder)`) all assert `is
None`, so they FAIL loudly the day option 1 or option 4 lands.  That is the right shape.

**Sweep, reproduced exactly** (my run):

```
### 6.2 sweep: 249 clean modules of 253 — Arg 39/4663, CaseBound 0/117, DoBound 0/31,
    LetBound 156/156, WhereBound 89/89; binding-head misses 0
```

---

## 3. Gate table

| gate | implementer | reviewer (re-run once) |
|---|---|---|
| `git diff --stat`: `Subst.scala` / `Type.scala` / `Lower.scala` / `Renamer.scala` / `Session.scala` | untouched | **untouched** — six files changed, none of them; **Tier 0** confirmed |
| `sbt core/compile core/copyResources` | green | **green** |
| `core/testOnly *TestLoopTrace` | 720/720/720, 3 props | **720 segments / 720 replayed / 720 agree, 3 passed** |
| the seven targeted suites | 121/121, ~9 min | **121 passed, 0 failed, 0 errors — 3 m 42 s, nothing hung** (their BEFORE run that hung past 40 min did not reproduce in any form here) |
| 6.2 sweep line | Arg 39/4663, CaseBound 0/117, DoBound 0/31, LetBound 156/156, WhereBound 89/89, 0 misses, 249/253 | **identical** |
| `corpus-run.sh --batch` | 85 / 69 / 0 over 154 | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** (38 s) |
| `repl-smoke.sh` | 8 groups / 66 checks, goldens clean | **8 groups / 66 checks; `git status tracker/repl-tests` clean** |
| `lsp-smoke.sh` | 234 (§7) / 233 (§5, docs) | **234** — see R-3 |
| boot | `Loaded 129 modules (11.65 s)` | **`Loaded 129 modules (11.28 s)`** |
| `.ei` outside `tracker/g1-*` | 0 | **0** (129 written by the boot, deleted; 143 tracked files intact) |
| Tier 1 / Tier 2 | not run, correctly | agreed — no solver, `Type.scala` or Lean change; not an adoption commit |

### Perf — one interleaved pair, mine

`tracker/tools/perf-bench.sh editor -k 15` on `Layout/Report.e`, BEFORE = a `git worktree` of
`361ff28` built in scratch with its own `core/compile core/copyResources` and
`tracker/repl-classpath.txt`, AFTER = this tree with `wantLocals = true`.  `PERF_MAX_LOAD=1.3`,
both sides started under 1.15; no other JVM alive (the `scala-cli` bloop daemon from the probe was
killed first); `ei_before=0 ei_after=0` on both.

| run | tree | round trip (median of 14) | read | typecheck |
|---|---|---|---|---|
| c1 | BEFORE `361ff28` | **1.615 s** | 0.795 | 0.485 |
| d1 | AFTER  (`wantLocals`) | **1.606 s** | 0.800 | 0.495 |

Δ = **−9 ms, −0.6 %** of the round trip.  Budget 5 % ≈ 80 ms — **INSIDE BUDGET**, agreeing with
the implementer's pooled −13.5 ms / −0.8 % over two pairs.  Note the split moved the OTHER way in
my pair (typecheck +10 ms where theirs was −23 ms), which is the honest reading: the change is
below this harness's noise floor in both directions, and the defensible statement is an upper
bound well under 80 ms rather than a measured speed-up.  One `Type.subst` per `let`/`where` binder
plus one walk of the component's terms — a few hundred zonks on a 1757-line file, against a
0.49 s typecheck — is entirely plausible at that magnitude.

---

## 4. What to fix before committing

1. **R-1** — rewrite §8 option 1.  It must say that the recorded type is deleted by
   `restrictTypes` (`Subst.scala:153`, from `:942` and `:1036`) unless `binderTypes` is kept
   eagerly substituted the way `remembered` is at `instantiateType` (`Subst.scala:187`), and that
   the change is therefore four sites, not one, and touches the batch path behind a flag rather
   than being invisible to it.  Quote the two zonks (`Bool` before `restrictTypes`, `a` after).
2. **R-2** — add option 4 (split the head's inferred type by arity) to §8 with its coverage and
   its caveats, so the user's yes/no has the Tier-0 alternative in front of it.
3. **R-3** — 233 → 234 in report §5 and in `docs/lsp.md`.
4. **R-4** — one sentence in `docs/lsp.md`: a local's type variables are named independently of
   the enclosing binding's, so the same letter in two hovers need not be the same variable.
5. **R-5** (optional) — retitle the sweep property; it sweeps 253 files, not 180.

None of these touch the shipped code.  With them applied the PARTIAL is fit to commit as
delivered, the pattern-binder fork parked with its number.

---

Scratch artefacts (not in the repo):
`…/scratchpad/review-6.2/Probe.scala` (premise + hook + option 4),
`Probe2.scala` (cache attacks + rendering), `perf-before1/`, `perf-after1/`, `corpus/`.

---

# Second pass — the fix round (option 4 shipped, doc fixes applied)

Reviewed against tree `f39453a` (= `361ff28` + briefs only; code identical) plus the updated
uncommitted deliverables, which now also touch `core/.../Pretty.scala`.  Scope: only what changed
since the first pass.  `Subst.scala`, `Type.scala`, `Lower.scala`, `Renamer.scala`,
`Session.scala` still untouched — **Tier 0** stands.

**VERDICT: FIX-THEN-ADVANCE.**  The argument split is right, and I could not make it emit a wrong
type in twelve adversarial shapes.  The letter-agreement mechanism is correct and costs the check
path nothing.  Two things must be fixed before this is committed, both small: a whole-file
line-ending flattening of `Pretty.scala`, and a conservatism claim in §2a that is wrong in two of
its three named cases — one of which quietly breaks Decision (a).

## Findings (second pass)

| id | severity | status | what |
|---|---|---|---|
| S-1 | **MEDIUM** | CONFIRMED | `Pretty.scala` was CRLF at HEAD (420 lines) and the working copy has **zero** CRs: a 30-line addition arrives as an 870-line whole-file reformat. |
| S-2 | **MEDIUM** | CONFIRMED | §2a's "nothing at all is recorded" for a rank-N argument or a constraint is FALSE for both — and the rank-N case emits `rk : forall a. a -> a`, a `forall` on a local, which Decision (a) forbids and no test or doc mentions. |
| S-3 | LOW | CONFIRMED | The sweep asserts 0 misses for the new `Arg(equation)` class (good, and the class is computed independently) but has **no anti-vacuity clause** for it: an empty `eqArgSpans` would pass silently. |
| S-4 | INFO | ANALYSED, not reachable | `domains` calls `Subst.substAlias`, which `die`s on an under-applied alias; `collectLocals` runs inside `guard(Error)`, so that would become a spurious error note. Not constructible in a well-kinded type. |
| S-5 | — | **CONFIRMED SOUND** | Conservatism of the split: twelve adversarial shapes, no wrong type. |
| S-6 | — | **CONFIRMED SOUND** | Letter agreement: `prettyTypeIn` cannot disagree with `ppForall` except in one corner that needs a free SKOLEM kind variable inside a quantified type variable's kind. |
| S-7 | — | CONFIRMED | Rendering was not added to the check path: one production call site, in the hover request handler. |
| S-8 | INFO | CONFIRMED | §9 still says "two Nav.e updates"; §5 says three, and three is right. |

### S-1 — `Pretty.scala` line endings

```
git show HEAD:core/.../Pretty.scala | grep -c $'\r'   ->  420
grep -c $'\r' core/.../Pretty.scala                   ->    0
git diff --stat  -> 870 changed lines;  git diff --stat -w  ->  30 insertions
```

Every other file in the change kept its endings (all five were LF at HEAD).  99 of the 154 files
under `core/src/main/scala` are CRLF at HEAD and there is no `.gitattributes`, so CRLF is the
convention this file was following.  The effect is that the 6.2 commit would carry a whole-file
reformat of a file the item adds thirty lines to, and §9's "nothing else in `Pretty` changed"
would be true of the semantics and false of the diff.  This is the hazard the project has already
written down once (python text I/O rewrites CRLF); the fix is to re-apply the `prettyTypeIn`
block byte-wise onto the HEAD file so `git diff --stat` reads 30, not 870.

### S-2 — the split is LESS conservative than §2a says, and rank-N breaks Decision (a)

§2a: *"if the chain does not yield `arity` arrows — a rank-N argument, a constraint or an alias
that hides one — **nothing at all** is recorded for that binding"*.  Two of those three are wrong,
because neither a constraint nor a rank-N argument is an arrow-hiding shape:

* **a class constraint does not stop it.**  `constrained cn = toInt cn` (with `toInt : Num n =>
  n -> Int`) gives head `forall a. Num a => a -> Int` and records `cn : a`.  Correct — Ermine
  keeps constraints in the `Forall`'s `q` field, so `case Forall(_,_,_,_,b) => b` steps straight
  past them.  The same holds for a row-constrained scheme: `myGet gf gr = getF gf gr` records
  `gf : Field h a` and `gr : Record r` under
  `forall (h: rho) a (r: rho). (exists (t: rho). r <- (h, t)) => …`.
* **a rank-N ARGUMENT does not stop it either** — it *is* the domain, not a hidden arrow:

```
rankN : (forall a. a -> a) -> Bool
rankN rk = True
   rk   Arg   11:7 = forall a. a -> a     [scope: (forall a. a -> a) -> Bool]
```

  The type is right.  But Decision (a) says a local shows its monotype with **no `forall`**, and
  this is a `forall` on a local — untested, undocumented, and reachable from any rank-N signature.
  Two acceptable fixes: say so explicitly in §2a and `docs/lsp.md` (a declared polytype domain
  genuinely is polymorphic, so showing it is defensible), or refuse it with one guard —
  `Type.mono` is the predicate `Subst.scala:938` already uses to ask exactly this question about
  exactly these types.  What is not acceptable is the current state, where the report says the
  case cannot arise.

The rest of §2a is accurate: an alias IS expanded on the way down and gives the right answer
(`type Fn = Bool -> Bool; aliasHead : Fn` → `ax : Bool`; `type Endo a = a -> a;
endoHead : Bool -> Endo Bool` → `ex : Bool`, `ey : Bool`), the peel is structural, and a chain
too short yields nothing.

### S-5 — trying to make the split lie

All run live through `TolerantCheck.checkWith(wantLocals = true)` and rendered through exactly the
path `Definitions`' hover handler uses (scratch `Probe3.scala`).  **No shape produced a wrong
type.**

| shape | head | what the split said | verdict |
|---|---|---|---|
| alias to a function type | `aliasHead : Fn`, `type Fn = Bool -> Bool` | `ax : Bool` | right |
| alias hiding a LATER arrow | `endoHead : Bool -> Endo Bool` | `ex : Bool`, `ey : Bool` | right |
| partial-application head (arity 1, 2 arrows) | `partialHead : Bool -> Bool -> Bool`, `partialHead px = (py -> …)` | `px : Bool`; the lambda arg `py` **absent** | right |
| all-literal alts | `multiAlt True = False` … | nothing | right |
| mixed alts, literal + var | `mixAlt : forall a. Bool -> a -> a` | both `my` occurrences `a` | right |
| class constraint | `forall a. Num a => a -> Int` | `cn : a` | right (see S-2) |
| row constraint + kinded binders + existential | `myGet` (above) | `Field h a`, `Record r`, letters agree | right |
| as-pattern outer var | `asArg aw@(ah :: at)` : `forall a. List a -> List a` | `aw : List a`; `ah`, `at` **absent** | right |
| var nested in a `ConP` | `nested (Just nq)` | `nq` **absent** | right |
| higher-order argument | `forall a b. (a -> b) -> a -> b` | `hf : a -> b`, `hx : a` | right |
| signed head, top level and local | `top : Bool -> Bool`; `where sw : Bool -> Bool` | `tx : Bool`, `sy : Bool` | right |
| rank-N argument | `(forall a. a -> a) -> Bool` | `rk : forall a. a -> a` | type right, SHAPE wrong (S-2) |

Two structural notes behind that: alts whose pattern count differs from the split are skipped per
alt (`a.patterns.length == ds.length`), so `Binding.arity = alts.head.arity` cannot mis-assign;
and `argVar` takes only `VarP` and `AsP(_, VarP(v), _)`, so a `StrictP`/`LazyP` wrapper is silent
rather than guessed — conservative, as the report says.

### S-6 — can the letters still disagree?

Not except in one corner.  The head hover renders `prettyType(t, -1)` → `ppType` → `ppForall`,
which is `Pretty.scope(ks ++ ts, …)`, i.e. `fresh` over `ks ++ ts` **in that order** before
anything else, then `ppConstraints(q, body)` = `ppType(q)` then `ppType(body)`
(`Pretty.scala:223-227`).  `prettyTypeIn`'s warm-up is `fresh` over `ks ++ ts` in the same order,
then `ppType(cs)`, then `ppType(body)` — the same assignments in the same sequence, minus
`scope`'s cleanup, which is the point.  The argument type is a STRUCTURAL sub-term of the head
(no `Subst.unbind`, so the same `V` objects), and `chosen` is keyed by `V`, so every variable the
argument shares with the head is already assigned.

The one asymmetry is that `ppForall` also renders `ts.traverse(ppTypeVarBinder)` between the two,
and `ppTypeVarBinder` prints the variable's KIND (`Pretty.scala:259-266`).  A kind variable free
there and not in `ks` would consume a name in the head's rendering and not in the warm-up,
shifting every later free variable by one letter.  After `generalize`, `ks` is
`(kindVars(t) -- kindVars(g)).filter(_.ty != Skolem)` (`Subst.scala:1613`), so this needs a free
**Skolem** kind variable inside a quantified type variable's kind.  The corpus does not contain
one, and the `myGet` case above exercises the nearest thing to it (kinded `rho` binders plus an
existential constraint) with the letters agreeing.  Confirmed live for plain schemes too:
`konst : forall a b. a -> b -> a` → `kx : a`, `ky : b`.

The WIDER caveat from R-4 is correctly reported as out of reach of this mechanism: a `where`
helper's type is its own family (its `scope` is its own monotype), so its letters still need not
match the enclosing binding's — and `docs/lsp.md:80-85` now says so, with an example.

### S-7 / S-3 — where it runs, and how the sweep grades itself

`prettyTypeIn` has exactly one production call site, `Definitions.scala:74`, inside
`server.onRequest("textDocument/hover")`.  `TolerantCheck.LocalTy` carries `Type`s, the cache
carries `Type`s, and the index carries `TermHover(name, ty, scope)` — nothing renders per check.
Confirmed by grep and by the perf pair below.

The sweep's `eqArgSpans` walks `ch.module.statements`, the SURFACE tree (`SEquation`, `SPVar`,
`SPAs`, `SPParen`, `SPSig`, recursing into `where`, `private`, `database` and class bodies) — a
different tree, a different traversal and a different position source from `collectLocals`, which
walks the LOWERED `Binding`/`Term`/`Pattern` tree.  The two meet only at `(startLine, startCol)`.
So the property does not grade the collection against itself: **genuinely independent, and
asserted** — `misses` collects `Arg(equation)` alongside `LetBound`/`WhereBound` and the property
requires `misses.isEmpty`.  Reproduced: `Arg(equation) 2872/2872 … required-class misses 0`.

What is missing is the anti-vacuity clause.  `seen("LetBound") + seen("WhereBound") >= 200` is
asserted; nothing asserts that `Arg(equation)` is non-empty.  If `eqArgSpans` ever returned Nil —
a surface-AST rename, a new equation node it does not match — `required` would be empty, every
`Arg` would be classified `Arg(other)`, and the property would pass at 0 misses while checking
nothing.  One clause, `seen("Arg(equation)") >= 2000`, closes it.

## Gate table — second pass

| gate | implementer (fix round) | reviewer (re-run once) |
|---|---|---|
| Tier 0 (`Subst`/`Type`/`Lower`/`Renamer`/`Session` untouched) | yes | **yes** |
| `sbt core/compile core/copyResources` | green | **green** |
| the seven targeted suites | 124 / 124 | **124 passed, 0 failed, 0 errors — 3 m 34 s, nothing hung** |
| 6.2 sweep line | `Arg(equation) 2872/2872, Arg(other) 39/1791, CaseBound 0/117, DoBound 0/31, LetBound 156/156, WhereBound 89/89; required-class misses 0` | **identical** |
| `lsp-smoke.sh` | 237 | **237** |
| `repl-smoke.sh` | 8 groups / 66 checks, goldens clean | **8 / 66, `git status tracker/repl-tests` clean** |
| `docs/lsp.md` count (R-3) | 237 | **237 — fixed** |
| R-4 caveat in `docs/lsp.md` | added | **present, with an example (`docs/lsp.md:80-85`)** |
| §8 rewritten against R-1 | yes | **accurate — names `restrictTypes` (`:153`), the two call sites (`:942`, `:1036`) and the `instantiateType` (`:187`) maintenance, and quotes the zonks** |
| `.ei` outside `tracker/g1-*` | 0 | **0** (143 tracked files intact) |

### Perf — one interleaved pair, mine

Same protocol, BEFORE = a fresh `git worktree` of `361ff28` built in scratch with its own
classpath; `PERF_MAX_LOAD=1.3`, both sides started under 0.90; no other JVM alive;
`ei_before=0 ei_after=0` on both.

| run | tree | round trip (median of 14) | read | typecheck |
|---|---|---|---|---|
| e1 | BEFORE `361ff28` | **1.720 s** | 0.865 | 0.510 |
| f1 | AFTER (option 4 + everything) | **1.655 s** | 0.815 | 0.505 |

Δ = **−65 ms, −3.8 %** of the round trip — **INSIDE the 5 % / 80 ms budget**.  The implementer's
pair was −21 ms / −1.3 %; the two disagree on the round-trip figure by exactly the amount the
READ half moved (−50 ms here, −20 ms there), which this item does not touch.  Where the change
actually is, the two pairs agree to the millisecond: typecheck **−5 ms** in both.  The honest
statement remains an upper bound well under budget, not a measured speed-up — the split adds one
structural peel and `arity` pattern matches per binding, and the rendering was deliberately kept
off this path (S-7).

## What to fix before committing (second pass)

1. **S-1** — restore `Pretty.scala`'s CRLF endings; `git diff --stat` on it must read ~30, not 870.
2. **S-2** — correct §2a: a constraint and a rank-N argument do NOT stop the split.  Then decide
   the rank-N shape explicitly: document `rk : forall a. a -> a` as accepted (report + `docs/lsp.md`
   + one pinning test), or refuse a non-`mono` domain with one guard.
3. **S-3** (optional) — add `seen("Arg(equation)") >= 2000` to the sweep's anti-vacuity clause.
4. **S-8** (trivial) — §9 says two Nav.e updates; there are three.

Everything from the first pass is addressed: R-1's fork rewrite is accurate, R-2 is implemented
and pinned, R-3 and R-4 are fixed in both the report and `docs/lsp.md`, R-5's sweep is retitled
and now carries a second required class.

Scratch artefacts (not in the repo): `…/scratchpad/review-6.2/Probe3.scala` (the twelve shapes),
`perf-before2/`, `perf-after2/`.
