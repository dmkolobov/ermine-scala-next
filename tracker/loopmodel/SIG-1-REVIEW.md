# Review of SIG-1 (the warn-mode survey)

Reviewer pass against `tracker/loopmodel/briefs/brief-SIG-1-review.md`, in
`ermine-scala-wt-sig` at `be5d4e3` + the implementer's uncommitted tree. Nothing in the
worktree was changed except this file; every `.ei` caused here was deleted (`git status`
shows exactly the five implementer entries).

## VERDICT: FIX-THEN-ADVANCE

The code is what the stage asked for and is inert under `off` -- I confirmed that harder
than the report did (§G). The classification is sound: I could not refute a single one of
the twelve (c) items, I found no false positive and no false negative in the triage, and I
pushed **eight of them to a runtime witness** the report did not have. Three findings in
the report are wrong or materially understated and must be fixed before the stage is
committed; none needs new code.

The plan's stop point -- "(c) non-empty in stdlib" -- **fires**: 7 shipped signatures,
18 wanteds, and three of them now have a runtime failure to show the user.

### Edit list (all in `tracker/loopmodel/SIG-1-SURVEY.md` unless noted)

1. **§4, the `ann` claim -- the important one.** Delete "**Not one `ann` hit: no term
   annotation `e : T` anywhere in the corpus or the stdlib leaves a skolem-mentioning
   residual.**" as a statement about the SITE. The corpus half is true; the site is LIVE
   and carries the identical soundness hole. Measured today:

       a1 = ((r -> r ! health) : {..r} -> Int) { position = 2.0 }

   fires `ann:<annot> ... concrete-ext nolit  r^586561S <- ((|A1.health|), _^586563A)` with
   EMPTY givens, the module LOADS, and `a1` evaluates to `<error: key not found: health>`.
   The explicit-`forall` spelling `((r -> r ! health) : forall r. {..r} -> Int)` does the
   same (`res1 : Int = <error: key not found: health>`). `TyLower.annot` closes an
   annotation with `c.nf(...)` (TyLower.scala:250-257), so the `Forall` reaches
   `subsumeType` and skolems are minted; the corpus just never writes such an annotation.
   Rewrite §8 item 8 from "S2 must decide whether an annotation is a user signature" to
   "the `ann` site has the same defect, here is the witness", and recommend a fifth pin
   (`shouldfail/sig05_annotated_lambda.e`) so S3's acceptance criteria cover it. Two of
   `SIG-ENTAIL-PLAN.md`'s S3 lines name only sig01/02/04 and need the same addition.

2. **§5, the split table is 3 too many.** As printed, 465 + 417 + 32 + 3 = 917 > 914. The
   triage's own summary is `{'a': 465, 'b': 396, 'UNSURE': 53}` and the 53 decompose as
   32 (the twelve (c) signatures) + 3 (the pins) + **18** entailed-by-hand
   (`proj5Pinned` 5, `proj6Pinned` 6, `wildCells` 6, `nearestByDeduped` 1). So **(b) = 414**,
   "396 settled mechanically plus **18** settled by hand". The prose already lists 18 items;
   only the numbers 417/21 are wrong.

3. **§8 item 1, the stdlib clause is false.** "ZERO in the 161-module standard library" is
   TRUE for `concrete-ext`. The following clause -- "where no non-literal row obligation
   even MENTIONS a concrete label set" -- is FALSE. 43 of the 914 row obligations mention a
   concrete label set; **26 of those are stdlib** (all in `Layout/Report/Relation.e`) and
   **6 are `nolit`**: `others` 4 (= the c7 holes), `small` 1, `largers` 1. This matters for
   S2's scope, because those six are exactly the shape the obvious generalisation of the
   trick decides (§T).

4. **§6/§10, the `let` drop has a SECOND site and a stronger root cause.** The report names
   `Lower.scala:185-187`. Add `Lower.scala:298-299`: a `where` attached to an equation
   **inside a `let` block** also builds `Let(..., Nil, ...)`. And the cause is not "the
   second component is discarded" -- `Lower.bindings` is typed
   `(List[ImplicitBinding], List[Nothing])` (Lower.scala:287) and its signature case is
   `case _: SSigStatement => ()  // 4.1`: it never constructs an explicit binding at all.
   New measurements: `let g : Int -> Int; g x = x in g "hello"` LOADS and **`r1 : String =
   "hello"`** (the signature neither restricts nor is even consulted); the `where` twin is
   rejected at 3:6 "failed to unify type Int with type String"; a `where` inside a `let`
   LOADS; a `let` inside a `where` body LOADS.

5. **§7, the repl-smoke line was vacuous evidence.** `tracker/repl-classpath.txt` is a
   **checked-in** file of absolute paths into `/home/dmitry/research/ermine/ermine-scala`
   -- the MAIN checkout. `repl-smoke.sh` (line 15) reads it, so run from this worktree it
   tested the main checkout's build, not the sig-entail build; "8/8 PASS, goldens
   byte-identical" said nothing about this change. Re-run with the worktree classpath it is
   still **8/8, 66 checks**, so the conclusion survives -- but the sentence must say which
   classpath it used. `g1-validate.sh:12`, `lsp-smoke.sh:12`, `g1-diff.sh:17` and
   `perf-bench.sh:94` have the same defect in this worktree; worth a line in
   `tracker/GATE-POLICY.md` (a gate that silently measures another tree is worse than a
   missing gate).

6. **§7, "no new warning" was a no-op compile.** The implementer's `core/compile` finished
   in 1 s having compiled nothing. A clean build (`core/clean core/compile
   core/copyResources`, 104 s) emits 478 warning sites: 14 in `Subst.scala` (lines 100,
   101, 153, 158, 274, 478, 1460, 1464, 1604, 1605, 1978 -- all pre-existing, none within
   30 lines of an edit) and **0 in `SigEntail.scala`**. Say it that way.

7. **§7, the TestLoopTrace caveat can go.** The two skipped properties DO run: the main
   checkout has a built `looptrace` (2026-09-07) and `diff -rq` shows `tracker/lean` is
   **byte-identical** between the two trees, so the binary is valid here. With
   `-Dermine.looptrace=<that path>`: **3/3, no SKIPPED line, 64 s** (vs 2 s and two skips).
   Replace the caveat with this; no `lake build` was needed.

8. **§4, the shape table mixes classes into two rows.** 20+372+411+125 = 928 != 914:
   **14** of the `multi-skolem`/`skolem-in-parts` hits are CLASS constraints (`shapeOf`
   tests skolem count before it looks for a `Part`, and `sigentail-agg.py` splits only
   `other`). Add a footnote; the "20 of 914" headline is unaffected.

9. **New §8 item (S2 owes an answer).** The probe renders a GIVEN's existential and a
   WANTED's existential with the same `A` tag, and `subsumeType` itself mints both as
   `Free` (`unbindExists(Free, q)` :540 and :541). Semantically they are opposites: a
   given's existential is one the check must ACCEPT (effectively rigid -- "some `c` exists"),
   a wanted's is one it may CHOOSE. `literal()` and `sigentail-entail.py` conflate them,
   which can only make `lit`/entailed too generous. `Relation.firstBy`'s given
   `r <- (c^471996A, h)` is a live example. This belongs beside item 5 (`Bound`).

10. **Pins (outside the report).** `shouldfail/sig03_let_bound_signature.e`'s header and
    `core/examples/shouldfail/RESULTS.md:223` say the refusal is at `20:12`. Measured:
    **`core/examples/shouldfail/sig03_let_bound_signature.e:32:12`** (`in local { position
    = 2.0 }` is line 32). Correct both. Also add, per §6's own conclusion, a note on
    `TestSigEntail`'s "let-bound unconstrained signature is refused today" property saying
    it pins ordinary inference, not the hole.

11. **§5 c2, minor.** Two wanteds are counted but only one argued. `_606 <- (val, _607)`
    (Relation.e:116:6) is entailed *relative to* the other wanteds; it is in (c) only
    because the SET is unsatisfiable. One clause, either way.

Nothing else. §8 is otherwise complete and every item is backed by a record I found in the
sweep; the caller table's line numbers (:651, :669, :815, :936, :992,
`editor/BackendImpl.scala:447`, `inferBindingGroupTypes` :780,
`TolerantCheck.scala:669`) are all correct; the (c) table's file:line references all
resolve; nothing of substance is in the implementer's scratch that is not in the report.

## (c) The table

Verified by hand from the source and the deduped sweep (my structural re-tag of all 914
row obligations agrees with the report's tags exactly). "Witness" means the brief's
standard: a crash, or a value outside its printed type -- LOADS alone does not count.

| # | item | really not entailed? | runtime witness? | severity |
|---|---|---|---|---|
| c1 | `Relation.UnifyFields.unify1` | **yes.** `r2 <- (f2, r2')` against given `r2 <- (h,f2,t)` FORCES `r2' = h+t`, so `r2' <- (f1, _)` needs `f1 ⊆ h+t`; `f1` is in neither given. Model `h=(\|a\|), t=(\|\|), f=(\|b\|), f2=(\|c\|), f1=(\|d\|)` | **YES** — `unify1_UF d c rr rr2 : Relation (\|a,b\|)` = `<relation with Failure(NonEmpty[Renaming non-existent attribute])>` | **HIGH** — shipped stdlib, unsound, one-line call |
| c2 | `Relation.partialLookup` | **yes.** `key#base` (parts of `r`), `key#val` (parts of `kv`), nothing gives `val#base`; `key=(\|k\|), val=base=(\|v\|)` makes `r2' <- (base,val,key)` unsatisfiable | **YES** — `partialLookup k v kv rr : Relation (\|k,v\|)` = `Success(Map(k -> IntT(false)))`: runtime header lacks `v`, i.e. a relation outside its printed type | **HIGH** |
| c3 | `DrilldownList.cons_Bracket` | **yes.** `Has^435209B` is a *Bound type variable* — `DrilldownList.e` imports no `Constraint` — so all three givens are vacuous; and in scope `Has` gives containment, not the pairwise disjointness `append (single f2) . append (single f1)` needs | **YES, twice** — `projectT (toRow_DD bad2) {p=1,q=2,s=3} : Record (\|p\|)` prints `{s = 3, q = 2}`, and `... ! p` gives `<error: key not found: p>`. Honest control (`DrilldownList (\|q,s\|)`) behaves correctly | **HIGH** |
| c4 | `Layout.Report.Keyed.softRelation` | **yes.** `o' <- (k, v)` with only two class givens; `k=v=(\|a\|)` | no — presentation-valued, no corpus call (only `chart_K`, `tabular_K`, `pieChart_K`, `drilldownBarChart_K` appear); exported and callable | MEDIUM |
| c5 | `Layout.Report.Keyed.keyValueTabular` | **yes.** 7 row wanteds over the signature's own unconstrained universals; `r2=(\|a\|), i=v=k=(\|\|)` falsifies `r2 <- (i,v,k)` | no (as c4) | MEDIUM |
| c6 | `Layout.Report.Relation.cutoffs` | **yes, and worse:** `r'' <- (r, v)` with the given `r <- ((\|cutoff\|), v, p)` is UNSATISFIABLE for every non-empty `v`. Honest signature `r <- (p, (\|cutoff\|))` | **no** — `cutoffDrilldownRel` (the public path, exercised by `Present/AtomicAndRelation.e`'s `withOther`) evaluates to `Success` with exactly the declared header | MEDIUM — wrong published type, not a crash; blocks the module under an enforced check |
| c7 | `Layout.Report.Relation.others` | **yes.** 4 wanteds ask a literal cutoff column to be disjoint from `p`/`r`. Its own siblings `smallcount`/`smallid`/`smallgroup` DECLARE `r <- (p, (\|cutoffCount\|))` etc.; `others` declares nothing about `r`, and `l` is a dangling `Bound` | **no** (same measurement as c6) | MEDIUM |
| c8a | `Wide.Helpers.melt2` | **yes.** `t' <- (fa, out\val)` needs `key # fa`; givens give only `key#i`, `key#val`, `fa#i` | **YES** — `melt2 pp vcol pp qq src : Relation (\|vcol,pp,x\|)` = `Failure(Cannot union columns: expected Map(x, vcol), found Map(x, pp, vcol))` | MEDIUM — examples |
| c8b | `Wide.Helpers.melt3` | yes (3, same shape) | **YES** (same Failure) | MEDIUM |
| c8c | `Wide.Helpers.melt4` | yes (4, same shape) | not run separately — identical body shape and mechanism to c8a/c8b | MEDIUM |
| c8d | `Wide.Signatures.melt3Simple` | yes (3) | **YES** (same Failure) | MEDIUM |
| c9 | `Algebra.Signatures.runningTotalFullViaWritten` | **yes, both.** `r <- (a,b,rest)`: `a`,`b` occur in none of the 21 givens. `d <- (c, r)` needs `c = m`; refuted by `e1=(\|e\|), f1=(\|\|), n=(\|e,y\|), p=(\|\|), m=(\|m\|)` → `c=(\|y,m\|)`, `c ∩ r ∋ y` (I checked all 21 givens on that model) | **YES** — `runningTotalFullViaWritten ordc amtc totc src : Mem (\|totc,other\|)` = `Failure(Operation refers to nonexistent column (ordc) …(amtc)…)` | MEDIUM — examples; the module's documented claim is indeed NOT established |

No false positives. No false negatives found either: I re-derived the (b) arguments for
samples #3, #4, #7, #8, #9, #16 and #18 (all valid — e.g. #3's `c` really is the fresh
`c^472001A`, so "take `c = (||)`" is a legal choice), and of the 396 mechanically-settled
`b` verdicts I hand-checked the 15 riskiest (>=2 rigid parts against <=2 row givens); all
four distinct signatures among them are genuinely entailed.

## The `Lower.scala` let-signature drop: a REGRESSION of the new pipeline

It is a regression, and the commit that shipped it is **80df1eb** ("Post-G1 D3 part 2:
fused module path retired", 2026-08-31). The fused pipeline handled let signatures: its
`let` production (`parsing/TermParsers.scala:224-243` at `9ad5909^`) ran
`gatherBindings(bs)` then `checkBindings`, and yielded
`Let(letLoc, rewriteShadowed(sh, p.extract._1), rewriteShadowed(sh, p.extract._2), body)`
-- **both** halves into the `Let(pos, implicits, explicits, body)` slots, which is who
filled `explicits` before. The replacement was written empty: `Lower.scala`'s `SLet` case
(`:185-187`) passes `Nil`, because `Lower.bindings` (`:287`) is *typed*
`(List[ImplicitBinding], List[Nothing])` and drops signatures outright
(`case _: SSigStatement => ()  // 4.1`) -- a staged stub introduced in **91c0d52**
("Stage 3.4a: surface-to-core lowering with the tnodes differential", 2026-08-30) whose
promised 4.1 never came. It became reachable behind `-Dermine.pipeline=new` in **db16d0b**
(Stage 4.1c) and became the only module path when 80df1eb deleted the fused branch from
`Session.dep`. The fused term grammar itself was deleted in **9ad5909**, not 3ad2623 (that
one is "Post-G1 D7: the statement-extent scanner"); the review brief's guess was wrong.
`where` on a top-level equation is unaffected because it goes through
`NewPipeline.collectBlock` -> `lowerLet` -> `pairSigs` (NewPipeline.scala:346, 504-506,
367-376), which pairs by shared `V` -- but `lowerLet` is called from that one site only, so
a `where` nested inside a `let` block falls back to `Lower.bindings` (`:298-299`) and is
dropped too. Measured: let-restrict LOADS and yields `String`; where-restrict REJECTED;
where-inside-let LOADS; let-inside-where LOADS.

**LSP impact: nothing pins it, and one comment asserts the opposite.**
`session/TolerantCheck.scala:326-328` states "A local explicit binding is what `assemble`'s
`lowerLet` makes of a SIGNED `let`/`where` binding" -- true for `where`, false for `let`.
`TestTolerantCheck`'s "6.2: every LET and WHERE binder gets a type" repeats the claim in a
comment but only asserts `sw` from a `sigWhere` fixture; `tracker/lsp-tests/Locals.e` has
`sigLocal`/`strict` (a `where`) and no signed `let`. So **no LSP test pins let-signature
behaviour**, and hover on a signed `let` binding silently shows the inferred type instead of
the declaration (`headType` returns `i.v.extract` for an ImplicitBinding), quietly violating
Decision (a). The ordering hazard the report flags is right and stands: fixing
`Lower.scala:185` before S3 turns sig03 from a rejection into an acceptance.

## Taxonomy: what fraction the refutation trick covers  {#T}

I re-tagged all 914 row obligations structurally (script in my scratch), independently of
`shapeOf`. The tags are right -- my buckets reproduce the report's counts on the nose:

| structural bucket | count | report's tag |
|---|---|---|
| A `sk <- (concrete…, exactly 1 flex)` | **20** | `concrete-ext` (20) |
| B `sk <- (concrete…, rigid…, flex…)` | 3 | inside `multi-skolem`; all `lit` |
| C `sk <- (flexible parts only)` | **411** (2 parts 314, 3 parts 85, 4 parts 5, 7 parts 7) | `other-row` (411) |
| D `sk <- (vars, >=1 rigid)` | 310 | `multi-skolem`/`skolem-in-parts` |
| E `flex <- (concrete…, rigid…)` | 20 | `skolem-in-parts`/`multi-skolem` |
| G `flex <- (vars, >=1 rigid)` | 150 | `skolem-in-parts` |

**The brief's suspicion is refuted.** `other-row` (411) is exactly bucket C and contains
**no concrete label at all** -- not one record anywhere in the sweep has the form
`sk <- (concrete + TWO flexibles)`, so relaxing "exactly one flexible" buys nothing, and
`other-row` is not `concrete-ext` in disguise. Only **43 of 914 (4.7%)** row obligations
mention a concrete label set, and they are A + B + E.

**Coverage after the obvious generalisations: 43/914 = 4.7%** (2.2% as the trick is
literally stated).
* A (20) -- the trick as written, per label: `Q |= l ⊆ sk` iff `Q ∪ {sk' <- (sk, {l})}` unsat.
* E (20) -- the **dual**, and the generalisation that actually matters: `X <- (L, sk)` with
  `X` fresh is entailed iff `Q |= l ∉ sk` for every `l ∈ L`, i.e. `Q ∪ {sk <- ({l}, s')}`
  unsat -- the same single-label refutation the solver already performs. This bucket is
  where the c7 stdlib holes live (`r' <- ((|cutoffCount|), p)` and its two siblings, plus
  `r' <- ((|cutoffChild,cutoffCount,cutoffGroup|), r)`), so the dual decides four of the
  eighteen stdlib (c) wanteds and correctly accepts `small`'s and `largers`' analogues.
* B (3) -- the concrete half is decidable, the skolem part is not; all three are `lit` anyway.
* C + D + G = **871/914 (95.3%)** is out of reach of the trick in any form, because
  `Q ∪ {sk' <- (sk, X)}` unsat decides "X meets sk in every model", which for a variable
  `X` is not "X ⊆ sk" and admits no label-wise decomposition. These are pure
  variable-partition problems: containment and pairwise disjointness among skolems, `Bound`s
  and remainders. S2's decision procedure has to be a set-level solver over those, with the
  literal-match-plus-warning fallback carrying 95% of the stdlib -- which is the report's
  own conclusion, now with the number attached.

## Gates, each run once  {#G}

A `core/test` owned by the LSP loop was running in the main checkout (10:18-10:42 and again
from 10:43) and overlapped my compile and test runs. I started no second JVM of my own;
this inflates wall times (suites 285 s vs the implementer's 215 s) and touches no verdict.

| gate | result |
|---|---|
| `core/clean core/compile core/copyResources` | rc=0, 104 s. 478 warning sites; 14 in `Subst.scala`, all pre-existing lines; **0 in `SigEntail.scala`** |
| `*TestLoopTrace` with the prebuilt `looptrace` | **3/3 passed, NO skips**, 64 s -- the Lean model differential really ran |
| `*TestSigEntail *TestStage1Pins *TestReplDifferential` | **41/41 passed, 0 failed, 0 errors**, 285 s |
| corpus batch, flag OFF | **88 LOADED, 70 REJECTED, 0 UNKNOWN, 158 total** |
| corpus batch, flag WARN | **88 / 70 / 0 over 158**; 89 275 `sigEntail` records |
| `corpus-verdicts.py off warn` | **0 of 158 differ**; stronger, all 158 `.out` files are **byte-identical** after removing only the `sigEntail` lines, the progress-bar lines and embedded timings |
| `repl-smoke.sh`, **worktree** classpath | **8/8 PASS, 66 checks** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5), goldens byte-identical |
| `.ei`, flag OFF vs the committed `tracker/g1-baseline` | g1 boot: 129 modules, 1447 signature lines, 14 s. `G1 COMPARE: EQUIVALENT`; `browse.txt`/`groups.txt` identical; **all 129 `.ei` byte-identical** to the baseline once the S5.2 `-- ermine-interface` key line (absent from the baseline) is ignored -- and that key line does not mention `sigEntail` |
| `.ei`, OFF vs WARN (two `loadInSeries` boots) | **129/129 byte-identical** |
| `shouldfail-controls/control08` under warn | 4 hits, all `lit`; `localWith` none -- reproduces §4 exactly |
| `shouldfail/sig03` | refused at **`…/sig03_let_bound_signature.e:32:12`**, "Row partitions are unsatisfiable at field 'ShouldFail.Sig03.health'" -- header and RESULTS.md say 20:12 |
| `typeCheckPattern` | **dead** -- tree-wide grep (incl. `editor/`, `session/`, `scalacheck-binding/`; there is no separate `lsp/` project) finds only the definition at Subst.scala:987 and its own `subsumeType` call |

Byte-identity under `off` also holds structurally: the new third parameter is defaulted so
no existing call site changed; both new call sites are `if (SigEntail.warn) Some(...) else
None`, so under `off` no `Site` is allocated and `siteOf`/`siteAt` are never entered; the
probe sits after the `ds`/`rs` partition and before the `entails` loop (:546) and touches no
`Supply`, `hm` or `mkSimplified`; and `SigEntail` is absent from `Constraints.GenRules`, so
`Session.interfaceKey` is unchanged -- which the `.ei` key line above confirms empirically.

Follow-ups for the orchestrator, in order of value: (1) the `ann` pin and the S3 scope
change, (2) the checked-in `tracker/repl-classpath.txt` making five gate scripts measure the
wrong tree from any worktree, (3) `Lower.scala`'s two drop sites and the false
`TolerantCheck` comment, which belong to the LSP loop as much as to this one.
