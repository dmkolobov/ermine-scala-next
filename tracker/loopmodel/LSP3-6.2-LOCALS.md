# LSP Stage 3, item 6.2 — types at every binder (locals, kinds on type names)

Implementer report.  Brief `tracker/loopmodel/briefs/brief-LSP3-6.2.md`; item of record
`tracker/LSP-ROADMAP.md` § Stage 3, item 6.2 with the STAGE-3 INVARIANTS and Decisions (a)/(b);
gates `tracker/GATE-POLICY.md`.  Branch `scala3-migration`; round 1 from `361ff28`, the FIX ROUND
(this revision) on top of `f39453a`, which is where the orchestrator committed round 1.  No
commits of my own.  Review: `LSP3-6.2-REVIEW.md` (FIX-THEN-ADVANCE; R-1..R-5 all addressed —
R-1 and R-2 in §8 and §2a, R-3 and R-4 in `docs/lsp.md` and §2b, R-5 in the sweep's title).

**OUTCOME: PARTIAL** — but with **62.4 % of the corpus's local binders covered** (3156 of 5056),
not the 5.6 % of the first round.  Updated after the independent review
(`LSP3-6.2-REVIEW.md`, FIX-THEN-ADVANCE): the reviewer's **option 4 (R-2) is now IMPLEMENTED**, so
every argument of every equation — top-level and `where`, at any depth — hovers with its type,
recovered by arity from the binding's own type with no `Subst.scala` change.  Complete classes
(0 misses over 253 files): equation arguments 2872/2872, `LetBound` 156/156, `WhereBound` 89/89,
plus 39 signed pattern binders.  Still absent, by the mechanism §1 documents: a LAMBDA argument,
a `case` binder, a `do` binder, a var nested in a constructor or product pattern, and a
`let`-inside-a-term equation's arguments — 1900 binders.  That is why this is still PARTIAL by
the item's letter.  §8 is the fork for the rest, rewritten after the reviewer refuted its first
version.  Nothing was weakened silently: both sides of the line are pinned by tests.

---

## 1. The premise, verified — and where it fails

The brief's premise: *"`Lower.Ctx.binderV` (rename/Lower.scala ~:89) gives every renamer binder
id ONE `V[Type]` whose `loc` is `pos(defSiteSpan)` and whose type is a fresh meta
(`unspecified(site)`).  After inference succeeds, `Subst.substType(v.extract)(hm)` inside that
block is the binder's solved type."*

**The first half is true.**  `Lower.scala:88-94`:

```scala
def binderV(id: Int, spelling: String): V[Type] =
  vars.getOrElse(id, {
    val site = binderSites.getOrElse(id, Span(0, 0, 0, 0))
    val v = V(pos(site), freshId(), Some(localName(spelling)), Bound, unspecified(site))
    vars += id -> v; v })
```

One `V` per binder id, memoised; `loc` is a real `Pos` in this file (`pos(site)`,
`Lower.scala:78`), whose `line`/`column` are `Pos`'s field names; `unspecified(site)`
(`Lower.scala:80-81`) is a fresh `VarT` meta.  Occurrences are that same `V` relocated
(`binderV(id, n.spelling) at pos(n.span)`, `Lower.scala:113`), so ids join uses to def-sites.

**The second half holds for BINDING HEADS only.**

* `Subst.inferImplicitBindingTypes` (`Subst.scala:784-800`) does, per binding,
  `val tp = substType(b.v.extract)` … `subsumeType(tp, rp)`.  `b.v.extract` IS Lower's meta, and
  the subsumption binds it to the inferred type.  So for an `ImplicitBinding` — a top level, a
  `let` head, a `where` head, at any depth — `substType(v.extract)` after inference is the
  binder's solved monotype.  Verified live (§2).
* For a **pattern binder** the meta is thrown away before inference ever sees it.
  `Lower.pattern` (`Lower.scala:322-326`) builds `VarP(v.map(_ => annotOf(c, n.span)))` — `V.map`
  replaces `extract`, so the pattern var is a `V[Annot]` carrying `Annot.annotAny`
  (`Annot.scala:27-30`: `exists a. a`, `Loc.builtin`, var id **-1**), and Lower's meta is
  referenced by nothing that inference touches.  `Subst.inferPatternType`'s `VarP` case
  (`Subst.scala:1055-1057`) then mints a FRESH meta through `unbindAnnot`
  (`Subst.scala:602-610`, which always `refreshList`s the existential) and hands it out in
  `Patterned.vs`; `inferAltTypesPrime` (`Subst.scala:1010-1012`) substitutes THAT var into a
  local copy of the alt body, and `inferType`'s `Lam` case (`Subst.scala:930-933`) even
  `refreshList`s the bound vars to new ids first.  None of it is written back to any `V` this
  side holds.  A zonk of the binder's own meta therefore returns an unconstrained variable —
  not the binder's type, and worse than silence.

So the ZONK reaches `LetBound` and `WhereBound` and nothing else that is inferred.  Two things
are recovered without it:

* a **signed** pattern binder (`\(v : Bool) -> …`) carries its DECLARED type as the annot
  (`Lower.scala:348-352`, `SPSig`), read straight off the tree — Decision (a)'s "explicit local
  signatures show as declared";
* an **equation's arguments**, by arithmetic on the binding's own type (§2a).  This is the
  reviewer's option 4 and it is what moved coverage from 5.6 % to 62.4 %.

`Subst.scala` is still where the REMAINING binders' types live; the brief forbids changing it,
so that part **STOPPED** and is written up as a fork in §8 rather than built.

## 2. What the collection does

`TolerantCheck.collectLocals(bs, file)` (new, `TolerantCheck.scala`) walks a component's terms
AS INFERRED (`Term.subTerm(subs, comp)`, the very list handed to `inferImplicitBindingTypes`),
inside the component's own `Session.subst { … }` block, after inference returns:

| node | what is recorded |
|---|---|
| `Let`'s `is` (`ImplicitBinding`) | `Subst.substType(v.extract)` — the solved monotype |
| `Let`'s `es` (`ExplicitBinding`) | `Subst.substType(e.ty.body)` — the DECLARATION |
| any binding's ARGUMENT patterns | the head type's first `arity` arrow domains (§2a) |
| `VarP` with a real signature | `Subst.substType(annot.body)` — the DECLARATION, and it wins over the domain |
| `VarP` with `annotAny` (id -1), not an equation argument | nothing (see §1) |
| `Lam` / `Case` / `App` / `Sig` / `Rigid` / `Remember` | recursed into |
| `SigP` | not recursed — and it is DEAD: nothing constructs it (`Pattern.scala:117` is commented out), which the reviewer confirmed (R-6) |
| the component's own heads | no TYPE — `types` already carries them — but their ARGUMENTS are collected |

Each entry is a `LocalTy(ty, scope)`: `ty` is what to print, and `scope` is set only for an
argument, to the binding type whose letters it must agree with (§2b).

### 2a. The argument split (review R-2, "option 4")

For a binding with `arity > 0`, the head's type is an arrow chain whose first `arity` domains ARE
the argument types, in order; `b.alts` all carry `arity` patterns at the same positions, so one
split serves every alt.  The head type used is the one HOVER shows — the generalised scheme from
`sub` for a top-level implicit, `etm` for a top-level explicit, the binder's own solved monotype
or declaration for a `let`/`where` head — so the two hovers cannot disagree about what the
binding is.

Conservative by construction, because a wrong type is worse than none:

* the quantifier is peeled STRUCTURALLY (`case Forall(_,_,_,_,b) => b`), never with
  `Subst.unbind`, which would mint fresh metas and destroy the letter agreement of §2b;
* type aliases are expanded on the way down (`Subst.substAlias`);
* (CORRECTED by review S-2: a CONSTRAINT does not stop the split — it lives in the Forall's `q`, so
  `constrained cn = toInt cn` records `cn : a`, correctly; a RANK-N argument yielded `rk : forall a. a -> a`, a
  `forall` on a local that Decision (a) forbids, so a non-`mono` domain is now skipped for that binder.)
* if the chain does not yield `arity` arrows — an alias that
  hides one — **nothing at all** is recorded for that binding;
* only a `VarP` DIRECTLY under the alt is taken, plus the OUTER var of an `AsP` (whose type is
  the whole pattern's, hence the domain).  A var inside a `ConP`/`ProductP` has a type this
  arithmetic does not know; `StrictP`/`LazyP` are not unwrapped either, even though their type is
  the same, so that the rule stays one sentence long.

It is a RECONSTRUCTION, not the checker's own answer, so it is pinned against the checker on the
whole corpus: the sweep (§5) requires **0 misses over 2872 equation arguments in 249 modules**,
and three properties pin the shapes it must refuse.

### 2b. One binding, one letter supply (review R-4)

`Pretty.run`/`runPrec` start every rendering with an empty `chosen` map and a fresh `varSupply`,
so two independent hovers both begin at `a`: `g : forall a b. a -> b -> a` printed on its own,
and `g`'s second argument printed on its own, would both say `a` — telling the reader that two
different variables are one.  New `Pretty.prettyTypeIn(scope, t)` warms the state up by rendering
`scope` first and discarding it.  The warm-up mirrors `ppForall` exactly (`fresh` over `ks ++ ts`
in order, then the constraints, then the body) rather than calling `ppType(scope)`, because
`ppForall` wraps its body in `Pretty.scope`, which DELETES those assignments on the way out.

WHERE IT RUNS, and why: at the REQUEST, in `Definitions`'s hover handler, not at collection time.
The alternatives the brief offered — pre-render a string at collection time, or render each
binding's family together at index time — both move a printer onto the per-keystroke check path,
which is exactly what this item's budget is a gate on; the index is rebuilt on every keystroke and
almost none of it is ever hovered.  Deferring costs one extra `ppType` of the enclosing type per
hover request and nothing per check.  So `locals` still carries `Type`s, the cache still carries
`Type`s, and `Occ.hover` grew from `(String, Type)` to `TermHover(name, ty, scope)`.

Pinned both ways: `TestTolerantCheck` asserts the exact strings for
`g : forall a b. a -> b -> a` (`x : a`, `y : b`), and lsp-smoke asserts that `konst`'s own hover
and its two arguments' hovers agree letter for letter.  The WIDER caveat the reviewer found — a
local's letters versus its ENCLOSING binding's — is NOT reached by this mechanism (they are
different families), and now has its sentence in `docs/lsp.md`.

Keyed by `(Pos.line, Pos.column)` of the binder `V`'s `loc`, gated to `ps.loc.fileName` so a `V`
relocated to another file, or at `Loc.builtin` / `Inferred`, is never recorded.  The explicit
top-level path (`typeCheckExplicitBinding`) collects the same way inside its own subst block.

A **signed** `let`/`where` binding is a local `ExplicitBinding`: `NewPipeline.assemble`'s
`lowerLet`/`pairSigs` (`NewPipeline.scala:305-355`) pairs the local sig with its equation, unlike
`Lower.bindings`, which drops `SSigStatement`.  [Dated 2026-09-10. Since LET-1 (2026-09-11) one shared
`Lower.collectBlock`/`pairSigs`/`bindings` serves top level, `where` AND `let`; `lowerLet` is gone and a
`let`-bound signature is honoured -- see `tracker/loopmodel/LET-1-FIX.md`.]  This was found by the sweep, not by reading: the
first sweep run reported exactly 4 `WhereBound` misses (`Report.e:1154:11 scalafy`,
`Op.e:177:9 unsafeROp`, `Signatures.e:289:9 tautHere`, `FreeReportDsl.e:197:9 go`), all four of
them signed `where` bindings.  Reading a local explicit head's `V` meta would have been WRONG
(inference type-checks a copy carrying the declared type and leaves the tree's `V` untouched),
which is why the declaration is read instead.

**Rendering (Decision a).**  Nothing extra is needed and nothing extra is done: the monotype is
handed to the same `Pretty.prettyType(t, -1)` that top-level hover uses, and `Pretty.lookupFresh`
(`Pretty.scala:105-108`) names any still-free meta from the standard variable supply.  So a
where-bound polymorphic helper renders `idy : a -> a`, with no `forall` and no meta id — pinned
by a property and by lsp-smoke.  (Caveat, stated rather than fixed: each hover renders
independently, so a local's `a` is not guaranteed to be the same letter as the enclosing
binding's `a`.)  `Type.close` and `generalize` are NOT used: `close` would add the `forall`
Decision (a) forbids.

**Reachable vs not, on the corpus** (the 253-file sweep, §5):

| class | binders seen | with a type | round 1 |
|---|---|---|---|
| `Arg` under an EQUATION | 2872 | **2872 (0 misses)** | 0 |
| `LetBound` | 156 | **156** | 156 |
| `WhereBound` | 89 | **89** | 89 |
| `Arg`, other (lambda args, nested pattern vars, `let`-in-a-term equation args) | 1791 | 39 (the SIGNED ones) | 39 |
| `CaseBound` | 117 | 0 | 0 |
| `DoBound` | 31 | 0 | 0 |
| total local | 5056 | **3156 (62.4 %)** | 284 (5.6 %) |

A `do` binder is indeed a `Lam` pattern after desugar (`Lower.scala:SDo`), and is therefore in
the unreachable class, not a separate case.  A binder in a component that DIED is absent
(correct, pinned); so is every binder in fast mode (nothing computes them, pinned).

## 3. The cache (Decision b)

`Cache.entries` values grew from `Map[String, Type]` to `Entry(types, locals)`.  A reuse hit
restores the component's locals; note-bearing components stay uncached exactly as before.

The invariant is written at `Entry` in the code: the entry's key is a fingerprint of the group's
whole SOURCE TEXT **including its start lines** (`TolerantCheck.keys`), and top-level statements
start at column 1 — so an edit that could move a def-site inside the group (a line inserted above
it, a character inserted before it on its own line) changes the group's text or its start line,
hence the fingerprint, hence the key; and an edit above the group moves the group's own start
line, which is in the key too.  Tested, not merely argued: the 5.5 invisibility set now compares
`renderedLocals` (def-site keys AND rendered types) warm vs cold over the body edit, the
error-introducing edit, the fixing edit and the signature edit, and `base` grew a definition with
a local so the comparison is not vacuous.

## 4. Index, hover, kinds

`Resident.Checked` grew `locals`; `Resident.checkFile` is the ONLY caller that passes
`wantLocals = true`.  `TolerantCheck.check` — the non-LSP entry — keeps the default `false`, and
a property pins that it collects nothing.

`Definitions.index`: a `ToBinder` occurrence whose binder is not `TopLevel` (and not a type-level
kind) joins `binders(id).defSite` → `checked.locals` and hovers `(spelling, type)` — a local has
no module to qualify it with, so it is spelled as the source spells it.  A new `localDefOccs`
adds the binder's OWN def-site for pattern-kind binders, which are not occurrences at all
(`Renamer.patternBinders` records a binder and no occurrence); `dedup` leaves positions a real
occurrence already covers alone.

`Occ.hover` became `TermHover(name, ty, scope)` (§2b) and `Occ` grew
`kind: Option[(String, KindSchema)]`, both rendered on DEMAND in the request (an index is
rebuilt on every keystroke; a printer nobody asked for would be pure cost).  Type-level
occurrences — imported (`ToGlobal` with `typeLevel`), own (`Unresolved` with `typeLevel`) and the
`TyDef` heads — carry `env.cons(g).schema`, printed with `Pretty.ppKindSchema`, the same printer
`:kind` and `browse` use (`Console.scala:589` → `prettyConHasKindSchema`).  Own cons are in the
check copy because `TolerantCheck`'s type phase installs them (`Session.addCon`).  A Builtin type
atom with no `Con` (`->`, `*`, rho) stays null, as before.  Type-name lookup tries the TYPE
fixity bucket first and falls back to the term one (the pre-6.2 behaviour), so a type operator
resolves to the Global its `Con` was installed under without changing any existing answer.

## 5. Tests

`TestTolerantCheck` (17 → 26 properties, all green):
1. every LET and WHERE binder gets a type (incl. a signed `where` shown AS DECLARED, and a
   polymorphic one rendered `a -> a`);
2. **an EQUATION's arguments get their types from the head**, at every depth (a `where`
   helper's own arguments included);
3. **one binding's argument letters agree with its own type** — the R-4 pin, exact strings for
   `g : forall a b. a -> b -> a` → `x : a`, `y : b`;
4. **an argument the split cannot see stays absent** — a var inside a `ConP`, a lambda argument;
5. the pattern binders the split cannot reach are absent, **and that is the mechanism** — with
   an anti-vacuity clause asserting the renamer DID record them, so the absence is about the
   collection and not about an empty table;
6. an explicit local signature shows as declared;
7. a component that died contributes no locals, the healthy one does;
8. the batch entry collects nothing new;
9. the 5.5 invisibility set extended to locals (§3), rendered through the same `scope`-aware
   path hover uses;
10. **the sweep** — 253 corpus files (stdlib + `core/examples`), 249 checked cleanly.  TWO
    classes are now REQUIRED to be complete and are asserted at 0 misses: binding heads
    (`LetBound`/`WhereBound`) and equation arguments, the latter computed independently from the
    SURFACE tree (`eqArgSpans`: every bare-variable argument pattern of a top-level or `where`
    equation, parens and signatures seen through, an `as` pattern's outer var included) so the
    property does not grade the collection against itself.  The residual is printed as counts and
    is a CLASS: a pattern var with no equation head's arity over it.

`lsp-smoke`: **207 → 237 checks** (+30), fixtures `tracker/lsp-tests/Locals.e` and
`LocalsBroken.e`.  Hover on a let, a where, a signed where and a polymorphic where binder, each
at its def-site and at a use; on an EQUATION ARGUMENT at its def-site and at a use; on `konst`
and both its arguments, whose letters must agree (`forall a b. a -> b -> a`, `k : a`, `j : b`);
on a case binder → null; on `Bool` (imported),
own `data Shape` and own `type Boxed a` → `Builtin.Bool : *`, `Locals.Shape : *`,
`Locals.Boxed : * -> *`; a local whose definition moves down a line answers at the new position
and null at the old; a local in the healthy statement of a broken file answers, one in a
component that died answers null; in fast mode the same local answers null while an imported
type's kind still answers.  The three Nav.e checks that pinned `null` "(perf ticket)" were updated:
the where-local now answers `local1 : Int`, and `twice`'s argument answers `x : a` — from
`twice`'s own type, split by its arity.

## 6. Perf — the gate

Interleaved A/B, `tracker/tools/perf-bench.sh editor -k 15` on `Layout/Report.e` (1757 lines),
order before / after / before / after, each side waiting for a 1-minute load average under 1.3
(`PERF_MAX_LOAD=1.3`).  BEFORE is a `git worktree` of HEAD (`361ff28`) at
`<scratch>/6.2/before`, compiled there with `core/compile core/copyResources` and its own
`tracker/repl-classpath.txt`, so the classpath and the copied module tree match the shape the
main tree has.  AFTER is this tree with `wantLocals = true` in `Resident.checkFile`.  Both sides
ran interface-free (`ei_before=0 ei_after=0` on every run).

| run | tree | round trip (median) | read | typecheck |
|---|---|---|---|---|
| c1 | BEFORE | **1.621 s** | 0.795 | 0.500 |
| d1 | AFTER  | **1.679 s** | 0.865 | 0.490 |
| c2 | BEFORE | **1.706 s** | 0.860 | 0.515 |
| d2 | AFTER  | **1.621 s** | 0.810 | 0.480 |

Pooled BEFORE 1.6635 s, pooled AFTER 1.6500 s — **Δ = −0.0135 s, −0.8 %** of the round trip.
Budget: ≤ 5 % (≈ 80 ms).  **INSIDE BUDGET**, and the sign is negative, i.e. the walk plus its
zonks are below this harness's noise floor.  The half of the round trip the change is actually
in says the same thing: typecheck 0.500 / 0.515 before, 0.490 / 0.480 after (−23 ms).  What
moves between runs is the READ (0.795-0.865), which this item does not touch at all — the same
machine drift PERF-ROADMAP records.

Corroboration: an earlier interleave of the SAME BEFORE against the collection-only build (no
index or hover work) gave 1.641 / 1.669 / 1.655 — Δ +1.3 %, also inside budget.  Its fourth run
was refused by the harness's staleness guard (I had edited a source file), so it is quoted as
corroboration and the table above is the measurement of record.

### 6a. The FIX ROUND's pair (option 4 added)

Option 4 adds, per binding, one structural peel, one arrow walk of `arity` steps and `arity`
pattern matches — and nothing else on the check path, because the letter-agreement rendering was
deliberately deferred to the request (§2b).  One interleaved pair, same protocol, BEFORE rebuilt
from `361ff28` in a fresh worktree:

| run | tree | round trip (median of 14) | read | typecheck |
|---|---|---|---|---|
| fix-before | BEFORE `361ff28` | **1.631 s** | 0.820 | 0.485 |
| fix-after  | AFTER (option 4 + everything) | **1.610 s** | 0.800 | 0.480 |

Δ = **−21 ms, −1.3 %** of the round trip; the typecheck half moved −5 ms.  Budget 5 % ≈ 80 ms —
**INSIDE BUDGET**, and again below the harness's noise floor (the honest statement is an upper
bound well under 80 ms, not a speed-up).  `ei_before=0 ei_after=0`, both sides under load 1.25.

Sweep time: `TestTolerantCheck` as a suite ran **97 s** with the new sweep property in it (the fix round's
seven-suite run took longer, but the machine was also running a browser; the sweep line itself is
unchanged in shape)
(previously 8 properties without a corpus sweep; the 6.1 report's 51 s figure is
`TestTolerantRead`'s agreement sweep, which is untouched).  The 6.2 sweep itself checks 253
files through `Resident.checkFile` and shares the resident session with the 6.1 0:0 sweep under
`residentLock`.

## 7. Gates (Tier 0 + the targeted suites)

| gate | result |
|---|---|
| `sbt core/compile core/copyResources` | green |
| `sbt 'core/testOnly *TestLoopTrace'` | 720 segments / 720 replayed / 720 agree, 3 properties passed |
| `core/testOnly *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestStage1Pins *TestReplDifferential *TestRenamer *TestLower` | first round **121 / 121**; FIX ROUND **124 / 124 passed, 0 failed, 0 errors** (TestTolerantCheck 17 -> 26 properties; the other six suites unchanged, so the before count is 115) |
| `tracker/tools/corpus-run.sh --batch` | 154 outputs, **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** |
| `tracker/tools/repl-smoke.sh` | **8 groups / 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5); goldens unmodified (`git status tracker/repl-tests` clean) — re-run in the fix round, same |
| `tracker/tools/lsp-smoke.sh` | first round **234**; FIX ROUND **237 checks** (baseline re-measured on the BEFORE worktree: **207**) |
| boot | `Loaded 129 modules (11.65 seconds)` |
| `.ei` | 0 outside `tracker/g1-*` after everything (the `bin/ermine` boot wrote 129 into `core/target/.../modules`; deleted) |

Not run, and why: Tier 1 (no solver, `Type.scala` or Lean change), Tier 2 (`core/test` in full —
this is not an adoption commit; the item does not flip a default outside the editor path).

A NOTE ON ONE MEASUREMENT I DID NOT GET: a `core/testOnly` of the seven suites in the BEFORE
worktree, to quote the before/after property counts from two runs rather than one.  It ran for
over forty minutes without finishing (the main tree's identical run takes ~9 minutes) and I
killed it rather than let it block the perf pair; the before count above is derived from the
diff, not measured.  Worth one look by the reviewer if the number matters.

## 8. THE FORK — what the REMAINING 1900 binders would need

Option 4 (§2a) is done and shipped, so the fork is now only about a lambda's argument, a `case`
binder, a `do` binder, a var nested in a constructor or product pattern, and a `let`-in-a-term
equation's arguments — 1900 of 5056 local binders.  The information for those exists only inside
`Subst.inferPatternType`.

**Option 1 — a recording hook in `Subst`.  My first version of this was WRONG and the reviewer
refuted it by running it (review R-1).**  What I proposed — record `v.loc -> t` in
`inferPatternType`, merge into `TolerantCheck` after each component, zonk — returns an
UNCONSTRAINED VARIABLE, i.e. exactly the failure it was meant to cure.  The reviewer's probe, on
`f x = x && True`:

```
inferPatternType gave t   = 51736
zonk right after recording: a
zonk AFTER body inference : Bool     <== the answer if zonked THERE
zonk AFTER restrictTypes  : a        <== the answer if zonked LATER, as I proposed
```

The deciding line is **`Subst.scala:153`**, `def restrictTypes(xs) = hm.types = hm.types -- xs`,
reached with that very meta in `xs` from **`Subst.scala:942`** (`inferType`'s `Lam` case,
`restrictTypes(ts ++ pt.xs)`) and **`Subst.scala:1036`** (`inferAltTypesPrime`, where `rtypes`
accumulates `pts.xs`).  The recorded meta IS `pt.xs.head`.  By the time a post-component merge
zonks it, the binding has been deleted from the substitution.

`hm.remembered` does not have this problem because it is never zonked later: it is kept fully
substituted EAGERLY, at `instantiateType` (`Subst.scala:187`, which applies the substitution to
the whole map on every instantiation), at `unbind` (`:586`) and at `generalize` (`:1624`).  That
eager maintenance IS the mechanism; the `Map` on `SubstEnv` is the trivial part.  So the honest
cost of option 1 is **four sites, three of them on the checker's hottest path**, gated by a flag
on the BATCH path — a Tier-1 question, not the "~8 lines, batch-invisible" I first wrote.  A
cheaper correct variant exists — record `substType(t)` at the END of the alt/lam, just BEFORE
`restrictTypes`, needing no map maintenance — but it is still a `Subst.scala` edit and it freezes
the type at that instant, so a constraint arriving later from a sibling of the same SCC is missed.

**Option 2 — an editor-only tree rewrite** (replace the unsigned `VarP` annot with
`Annot(loc, Nil, Nil, VarT(ourMeta))`).  REJECTED, and the reviewer confirmed the reason
independently: `Patterned.xs` goes empty, and `xs` feeds the "unannotated parameters used
polymorphically" refusal (`Subst.scala:937-940`), `restrictTypes` (`:942`) and
`checkSkolemEscape` (`:1029`) — the editor would accept programs batch rejects.  Keeping an
existential and putting our own var in it does not help: `unbindAnnot` refreshes it
unconditionally (`Subst.scala:605`).

**Option 3 — wrapping local occurrences in `Remember`** so `hm.remembered` catches their types.
Works in principle but inserts `Memory` wrappers into inference on the editor path: a second
checking engine in spirit.

**Option 4 — split the head's type by arity.  DONE (§2a), Tier 0, no `Subst` change.**  Its
residual is the 1900 above; it cannot grow to cover them, because a lambda or a `case`
alternative has no arity to divide.

My reading after the review: option 1 is the only route to the rest, it is a genuine Tier-1
change costing four sites, and it is worth putting to the user as such — not as a small one.  The
gesture the fork now blocks is narrower than it was: hovering a function's parameter, the common
case, is answered today.

## 9. Files changed

* `core/src/main/scala/com/clarifi/reporting/ermine/Pretty.scala` — `prettyTypeIn` (§2b).  A
  PRINTER addition, which the brief allows; nothing else in `Pretty` changed.
* `core/src/main/scala/com/clarifi/reporting/ermine/session/TolerantCheck.scala` — `LocalTy`,
  `Result.locals`, `Cache.Entry`, `checkWith(wantLocals)`, `collectLocals` incl. the argument
  split.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Resident.scala` — `Checked.locals`,
  `wantLocals = true` on the editor path only.
* `core/src/main/scala/com/clarifi/reporting/ermine/lsp/Definitions.scala` — `TermHover`, local
  hover, kind hover (`Occ.kind`), `localDefOccs`, type-fixity Global lookup.
* `scalacheck-binding/src/main/scala/TestTolerantCheck.scala` — nine new properties, the sweep's
  two required classes, invisibility extended, `base` grew a local.
* `tracker/tools/lsp-client.py` — the 6.2 block, the fast-mode locals check, three Nav.e updates.
* `tracker/lsp-tests/Locals.e`, `tracker/lsp-tests/LocalsBroken.e` — new fixtures.
* `docs/lsp.md` — the hover paragraph.
* `tracker/loopmodel/LSP3-6.2-LOCALS.md` — this report.

No `Subst.scala`, no `Type.scala`, no `Lower.scala`, no `Renamer.scala` change.  No
`tracker/LSP-ROADMAP.md` or `tracker/lean/` change.  No commits.

Other untracked files in the tree at the end (`tracker/loopmodel/briefs/brief-LSP3-6.2b-
prototype.md`, `-6.3`, `-6.4`, `-6.5`, `-6.6`) appeared during this run and are NOT mine — the
tree was clean when I started.

Repro recipe for the reviewer's perf pair: `git worktree add <scratch>/before 361ff28`, then in
it `sbt -batch -J-Xmx3g core/compile core/copyResources` and
`sbt -batch 'export core/fullClasspath' | tail -1 > tracker/repl-classpath.txt`; run
`PERF_MAX_LOAD=1.3 <tree>/tracker/tools/perf-bench.sh editor -k 15` alternately from the two
trees.  TWO TRAPS COST ME THREE RUNS: perf-bench refuses when `pgrep -f 'sbt-launch|xsbt\.boot'`
matches ANYTHING — including a shell whose own command line contains that string, so a wait-loop
written as `until ! pgrep -f "sbt-launch"` silently fails every measurement; and an orphaned
`perf-client.py` from a killed run trips the "another ermine JVM is running" guard.  Check
`ps` for both before believing a refusal.
