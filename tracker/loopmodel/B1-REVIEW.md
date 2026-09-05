# B1 review — the `makeEmpty` self-propagation fix

**Verdict: ADVANCE.**  2026-09-04.  Reviewer of `tracker/loopmodel/B1-FIX.md` (stage B1 of
`tracker/LOOP-MODEL-PLAN.md`).  Nothing below is taken from the report: every figure is one I
re-ran, and my "before" side is a pre-fix class snapshot I verified is pre-fix by
disassembly.  Five documentation findings, none blocking; the fix itself is correct,
complete, and — measured harder than the report measured it — **provably inert on everything
that used to work**.  I edited nothing but this file and my scratch
(`/home/dmitry/.claude/jobs/880c725d/tmp/review-B1/`); no commits, no Lean or Scala edits;
`core/examples` has 0 `.ei` and `core/target` the same 129 it started with.

**The one-line result the report does not have.**  The complete row-constraint trace of the
66-file corpus — stdlib boot plus every example, **363,570 records**, every `solve`, `step`,
`learn` and `sat` — is **BYTE-IDENTICAL** between the pre-fix and the post-fix compiler.  The
fix is not merely "verdict-preserving"; on the corpus it is a literal no-op at the level of
the solver's own record stream.  That is what makes it safe to ship unconditionally.

---

## 1. Lean: rebuild, audit, hygiene — all reproduce

| check | command | my result | report |
|---|---|---|---|
| build | `lake build Rowpartition` | **success, 841 jobs** | 841 ✓ |
| audit | `lake env lean Audit.lean` | **`Rowpartition theorems audited: 3058; declarations using a non-standard axiom: 0`** | 3058 / 0 ✓ |
| looptrace | `lake build looptrace` | **success, 24 jobs** | 24 ✓ |
| hygiene | grep `sorry`/`native_decide`/`axiom`/`partial`/`unsafe`/`opaque`/`implemented_by` over `Loop/{Step,Wf,Refine,Strict,StrictStep,StrictBound}.lean` | **0 real hits** (two doc-comment uses of the word "partial", `Step.lean:11,364`) | ✓ |

The audit total is **unchanged from L5 round 2's 3058**, which is the arithmetic the change
predicts: one theorem out (`makeEmpty_aux_emits_self`), one in
(`makeEmpty_aux_excludes_self`).  Module sizes: `Strict.lean` 612 (L5's figure, untouched),
`StrictStep.lean` 1,962 → **1,968**, `StrictBound.lean` 339 → **354** — deltas of +6 and +15,
consistent with exactly the three edits §5a claims in those two files and with nothing else.

**The model mirror is live**, checked directly and not through the report: `looptrace` now
SOLVES `PANIC3.json` at all of bases 0–19 (L5 recorded the model rejecting at bases 6 and 13),
and solves my own `RS5` seed at bases 0–9.

## 2. The Scala fix, read

`Constraints.scala`, `makeEmpty`'s `aux` (now line 1574): `abstr.map(v => …)` →
`(abstr - v).map(u => …)`, lambda parameter renamed.  **The fix is live in the main
checkout's compiled classes** — `javap -c` on `Constraints$.aux$2` shows `Set.$minus` before
the `map`; the pre-fix snapshot (`tmp/B1/snap-main`) does not, and its `aux$2` even has a
different parameter list.  So the A/B below is a real A/B.

**Is `(abstr - v)` right, and complete?**  Yes, and I checked completeness rather than
assuming it.  `makeEmpty(v)` partitions BOTH queues by `ruleInvolves(v)` = `u == v ||
rhs.contains(u)` (`:1081` — head AND right-hand side), then folds the extracted set:

* the `u == v` arm goes to `aux`, whose `RHSAbstr` case now emits
  `Partition(u, RHSEmpty(), PartitionEmpty)` only for `u ∈ abstr - v`, so nothing it emits is
  headed by `v`;
* the `u != v` arm emits `Partition(u, rhs - v, inf)` — head not `v`, right-hand side no
  longer mentioning `v`.

So `nps` mentions `v` nowhere, and `incmg`/`procd` are by construction the complements of
"involves `v`".  **The step now leaves no partition mentioning the variable it just bound** —
which is `QueueHygiene` for `v`, and exactly what the old code broke.  I found no second leak
inside the function.

The soundness argument is the right one: the emitted `v <- ()` was redundant because the same
call performs `instantiateType(v, ConcreteRho(-, Set()))` twelve lines below.  The codebase
already knew this shape was fatal: the Stage 7 `emptyRow` branch's comment (`:1274-1279`)
says in as many words that re-entering a partition about an emptied variable "would reach
`makeEmpty z` a second time — `instantiateType`'s 'panic: reinstantiated type'", and that
re-enqueueing `z <- ()` "is worse: it is dequeued, calls `makeEmpty` again, and cycles".
`selfSubstitution` (`:1157`) is the cited precedent and does use `(abstr - v)` — confirmed.

**No refutation is lost.**  The `_` arm (`die("Incompatible instantiations of 'v'")`) is
untouched, and after the (single) `makeEmpty v` no partition mentioning `v` remains for a
second call to refute.  §4a measures this; §3 and §6 measure it again at scale.

## 3. Differential re-runs — my harness, my baseline

`-Dermine.useInterface=false` throughout.  "pre" = the pre-fix class snapshot driven by my own
classpath-parameterised replay driver; "post" = the main checkout's classes through
`tracker/repro/satterm/sweep.sh`.

| # | run | pre-fix | post-fix | report |
|---|---|---|---|---|
| R1 | `PANIC3.json`, bases 0–99 | **SOLVED 89 / REJECTED 11**, all 11 the reinstantiation panic | **SOLVED 100 / REJECTED 0**, `DRAWN 0:x100` | 89/11 → 100/100 ✓ |
| R2 | L5's 14 hunt seeds, bases 0–99 = 1400 runs | **SOLVED 866 / REJECTED 534**, and **534 of 534** rejections are `panic: reinstantiated type` | **SOLVED 1400 / REJECTED 0 / HANG 0 / OOM 0** | 866/534 → 1400/0 ✓ |
| R2a | per-seed spread pre-fix | `e00438` 1/100 … `e01228` 78/100, `e01479` 78/100 | — | "1 of 100 … to 78 of 100" ✓ |
| R3 | all 18 tracked seeds, bases 0–19, per-seed flags (`RE` `emptyRow`, `D1–D4` `labelCheck=false`) | PANIC3 18/2; 11 seeds SOLVED 20/20; `D1 D2 D3 D4 REF SUP` REJECTED 20/20 | PANIC3 **20/0**; everything else identical | ✓ |
| R3a | R3 normalised diff (verdict line per base + bindings + `DRAWN` histogram + `SUMMARY`) | — | **exactly 3 differing lines in the whole sweep**: PANIC3 bases 6 and 13, and PANIC3's `SUMMARY` | "the ONLY difference … is PANIC3's two panics" ✓ |
| R4 | `crule/sweep.sh W 0 99` / `gseed 0 99` | — | **REJECTED 100/100** both | ✓ |
| R5 | `sbt -batch 'core/testOnly *LoopTrace*'` | — | **Total 3, Passed 3.** `708 solves (18 seed × 6 bases + 600 generated); 708 segments; 708 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; controls **47 of 708** (base +1) and **59 of 708** (`nongen`) | ✓ including `PANIC3` in the population (18 seeds, up from 17) |
| R6 | L1 seed sweep, `looptrace-diff.py --sweep`, all 18 seeds × bases 0–9, traces regenerated on both sides with the per-seed flags | — | **all 180 comparisons agree**, `PANIC3` `ok` at every base | 180/180 ✓ |
| R7 | `sbt -batch -J-Xmx3g core/test` | — | **Total 914, Passed 913, Failed 1** — `Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded`, the known starvation. `TestLoopTrace` runs for real and passes | 913/914 ✓ |
| R8 | `repl-smoke.sh` / `lsp-smoke.sh` | — | **PASS** 4/4 groups, 35 checks / **PASS** lsp, 98 checks | ✓ |

### 3a. Corpus replay — seven groups, not two

`looptrace-corpus.sh`, `-Dermine.loadInSeries=true`, model vs compiler, byte for byte:

| group | files | segments | agree | skip |
|---|---|---|---|---|
| boot | — | 54,199 | 54,199 | 0 |
| top | 15 | **92,673** | 92,673 | 0 |
| Ai | 11 | 83,942 | 83,942 | 0 |
| guide | 2 | 54,244 | 54,244 | 0 |
| bugs | 2 | 54,235 | 54,235 | 0 |
| shouldfail | 40 | **56,032** | 56,032 | 0 |
| shouldfail-controls | 5 | 54,739 | 54,739 | 0 |
| **total** | | **450,064** | **450,064** | **0** |

`top` and `shouldfail` reproduce the report's figures to the record.  The other five groups
are mine; the report ran two, I ran seven.

### 3b. Corpus verdicts and messages, pre vs post

`corpus-run.sh --batch`, main checkout, class set swapped via `ERMINE_CP`:

* 66-file corpus: **23 LOADED / 43 REJECTED / 0 UNKNOWN** on BOTH sides; `shouldfail/` 40/40.
* `--incomplete` 34: **18 LOADED / 16 REJECTED / 0 UNKNOWN** on BOTH sides.
* Message texts (progress bars and timings normalised away): **6 of 66 differ, 0 of 34**.  Two
  of the six (`sk03`, `sk05`) are only the class-directory root printed inside a stdlib path,
  i.e. an artefact of the pre side running from the snapshot.  The other four (`der01`,
  `der02`, `der06`, `der07`) are a DIFFERENT CLAUSE of the SAME refutation at the SAME field
  and the SAME line:column.  **Per-file re-run of all four on both class sets: 0 differing
  lines.**  So the report's gate 4d conclusion is independently confirmed, in the mode
  (`per file`) that every adopted measurement uses.  (My six are not literally the report's
  six — they had `np03b`/`unsound04` where I have the two path artefacts — which is itself the
  report's point: the batch clause choice is id-order churn, and my pre side loads the stdlib
  from a different root.)

### 3c. The measurement that settles it: the corpus trace is byte-identical

`corpus-run.sh --batch` with `-Dermine.rowTrace` and `-Dermine.loadInSeries=true`, once per
class set, over the 66-file corpus (stdlib boot + all 66 modules):

    pre-fix   363,570 trace records
    post-fix  363,570 trace records
    cmp (after canonicalising the class-directory root)  ->  IDENTICAL

Every `sin`, `svar`, `scon`, `step`, `learn`, `in`, `inpart`, `sat`, `solve`, `concr` and
`splice` record the solver emits on the whole corpus is the same before and after the fix.
This is strictly stronger than "verdicts identical", "messages identical" and "no published
type weakened" put together, and it is why I did not spend 27 minutes re-running the `.ei`
sweep (§8): with a bit-identical solver record stream on those sources, an interface
difference could only come from the sweep's own noise — which is exactly what the report's
same-checkout control (`21 order-only` either way) shows it has.

### 3d. Mint-neutrality on everything that used to work

Over L5's 14 hunt seeds at bases 0–99, **866 bases solved on both sides.  On all 866, `drawn`,
`bound` and `residual` are identical.**  0 differences.  Combined with R3a (identical `DRAWN`
histograms on all 18 tracked seeds), the fix does not change a single mint on any run the old
compiler completed.

## 4. Runs the implementer did not make

### 4a. 375 fresh satisfiable systems, 7,500 solves

L5's own `genE.py` population (satisfiable BY CONSTRUCTION), every 4th seed of the 1,500,
**bases 0–19 on the FIXED compiler**:

    SOLVED 7500   REJECTED 0   HANG 0   OOM 0

Not one death of any kind: no reinstantiation panic, no spurious `Incompatible instantiations`,
no `Infinite row partition`, no hang.  Five times gate 3e's population, and the gate that
matters most for shipping: on satisfiable input the fixed solver never refuses.

### 4b. An alias-biased population — 6,000 solves — to hunt the ALIAS form

The report leaves "the ALIAS form of the same `die`" explicitly uninvestigated.  I wrote a
generator (`review-B1/genU.py`) that is satisfiable by construction like `genE` but puts
SEVERAL variables on each value, so singleton links `a <- (b)` (the `unify` branch) and
duplicate right-hand sides (the `common` branch) — the only two callers of `instantiate`, and
therefore the only two ways to reach the alias `die` — are frequent, and self-references arise
by themselves.  300 seeds × 20 bases per side:

| | SOLVED | REJECTED | deaths |
|---|---|---|---|
| pre-fix | 5,859 | 141 | **141 of 141 the `ConcreteRho` panic** |
| post-fix | **6,000** | **0** | **none, of any kind** |

So the alias form is not exhibited by an alias-biased satisfiable population either before or
after the fix; and 12 more seeds join the list of satisfiable systems the shipped compiler
rejected.

### 4c. `RS5` — a satisfiable system the shipped compiler rejects at 100 % of bases

Seeds of my own construction, bases 0–49 on both class sets
(`review-B1/seeds/`):

| seed | system | pre-fix | post-fix |
|---|---|---|---|
| **RS5** | `v0 <- (v0,v1)`, `v1 <- (v1,v2)`, `v2 <- (v2,v0)`, `v9 <- (v5,(\|l100\|))` — SATISFIABLE (all empty, `v9 = {l100}`) | **REJECTED 50 / 50**, every one the reinstantiation panic | **SOLVED 50 / 50** |
| RS4 | satisfiable, self-reference through a two-step cycle | SOLVED 50/50 | SOLVED 50/50 |
| RS1 | `v0 <- ()`, `v0 <- (v0, v1, (\|l1\|))` — the `die` arm with a SELF-REFERENTIAL premise whose concrete part is NONEMPTY | REJECTED 50/50 | REJECTED 50/50, identical |
| RS2 | PANIC3 with a concrete part on the self-referential constraint | REJECTED 50/50 | REJECTED 50/50, identical |
| RS3 | PANIC3 plus a concrete definition of the self-referential variable | REJECTED 50/50 | REJECTED 50/50, identical |

`PANIC3` fails at 11 % of bases; **`RS5` fails at 100 %**.  Three self-referential constraints
instead of one turn the order-dependence into a certainty.  The bug was not a rare coincidence
of queue order.

## 5. The two questions the report left open

### 5a. The `die("Incompatible instantiations of 'v'")` arm with a self-referential premise — CONFIRMED reachable, CONFIRMED unchanged

Under the default flags `labelCheck` refutes RS1/RS3 first, so I re-ran them with
`-Dermine.labelCheck=false` — which is precisely why the tracked `D1`–`D4` seeds carry that
flag.  RS1 then reaches the arm at **40 of 50 bases**:

    Death: Incompatible instantiations of 'v0^N'   (40 bases)
    Death: Infinite row partition for 'v0^N'       (10 bases — selfSubstitution wins the race)

and RS3 reaches it at 44 of 50, on two different variables.  **The pre-fix and post-fix
message multisets are identical base for base.**  That is the correct outcome: the fix touches
only the `RHSAbstr` arm, and the `_` arm is a genuine refutation — `v <- (…, C)` with `C ≠ ∅`
while `v` is forced empty is unsatisfiable.  The 7,500- and 6,000-solve satisfiable sweeps are
the empirical half of the same claim: the arm never fires on satisfiable input.

### 5b. The ALIAS form — same die, same root cause, no path after the fix

**By reading.**  The alias death is the SAME line, `Subst.scala:184`; it fires when
`instantiate(v, u)` is called with `v` already in `hm.types`.  Its only two call sites are
`incorporateAll`'s `common` branch (`unify(v, u)` on the dequeued head, `:1126`) and its
`unify` branch (`unify(u, v)` on a singleton right-hand side, `:1130`).  During the partition
loop exactly TWO functions bind anything — `makeEmpty` (`instantiateType(v, ConcreteRho(∅))`)
and `instantiate` (`instantiateType(v, VarT(u))`); `makeConcrete` deliberately binds nothing
(I checked every `instantiateType` call site in the tree).  Both remove every partition
involving their variable, and after B1 neither re-emits one: §2 for `makeEmpty`; `instantiate`
maps `v ↦ u` through `replace`, and its extra `DeDuplication` partition is headed by `u`,
which is unbound.  The one rule that reads the environment and could name a bound variable —
the Stage 7 `emptyRow` reuse, `splitConcrete` `:1328-1335`, flag OFF by default — deliberately
does not mention the carrier, and says so in its comment.  So **the alias form has the same
root cause and the same fix**, and after B1 I can find no path to it.

**By experiment.**  §4b: 6,000 alias-biased satisfiable solves post-fix, zero deaths; and the
141 pre-fix deaths in that same population are all the `ConcreteRho` form, none the alias form.

This is not a proof of unreachability — that is `QueueHygiene.step`, L5 round-3 work — but it
is considerably more than "not investigated", and the ticket should say so (F3).

## 6. Can a source-level Ermine program reach it?

The report inherits L5 §6.5's "PLAUSIBLE, not demonstrated".  I attempted it and can sharpen
the answer in both directions.

**Attempt (negative).**  Nine `.e` probes through `bin/ermine` on the PRE-FIX classes
(`review-B1/src/RP1–RP9.e`): monomorphic recursion through `appendR`
(`rec2 r s = appendR (rec2 r s) s`, and the mirrored and mutually-recursive forms), self-append,
and nested appends with shared operands that force `empty` steps (RP6 fires four `empty` steps,
RP9 three).  All nine load; none panics; none produces a multi-part self-referential partition.
The reason is the one L5 found: each `appendR` mints a fresh whole, and the recursive
occurrence's row is unified with the result only AFTER the solve, so the solve sees three
distinct variables (`step learn ^free300016 <- (^free300015 ^free300014,)`).

**A finding that cuts the other way, and that the report does not have.**  I scanned all seven
corpus row traces — **1,082,449 records, 47,050 partition records** — for the shape.  There is
exactly **one multi-part self-referential partition, and it is in the SHIPPED STDLIB**:
`core/src/main/resources/modules/Layout/Report.e` yields the solve

    r^259807 <- (c, k, p, r^259805, v)
    o^259812 <- (k, v)
    r^259805 <- (o^259810, r^259805)        <-- multi-part SELF-REFERENCE

on **every compile**, in every one of the seven groups.  It does not reach `makeEmpty`'s `aux`:
the `learn` branch's `selfSubstitution` fires first (`learn new SelfSubstitution:
^ambiguous(free)259810 <- (,)`), which is the sister rule that already excluded `v`.  I lifted
that solve out verbatim into a seed (`review-B1/seeds/STDLIB.json`) plus two perturbations and
swept all three at bases 0–99 on the PRE-FIX compiler: **100/100 SOLVED each**.  So the stdlib
is safe, and safe robustly.

But the honest reading is that **the ingredient is already in the standard library**, and what
spares the corpus is only that the self-referential partition is dequeued (and dissolved by
`selfSubstitution`) before anything empties its head.  `PANIC3` and `RS5` are exactly the case
where it is not: the self-referential partition sits in `proc` while `v <- ()` arrives from
another rule.  "PLAUSIBLE that a source program reaches it" should be read as *the shape is in
the stdlib today; only the order spares us* — which is a stronger reason to have taken the fix,
not a weaker one.

## 7. The six proof sites, read for hidden weakening

| site | change | judgement |
|---|---|---|
| `Loop/Step.lean:126` | `(p.rhs.abstr.excl v).map …` plus a comment | faithful mirror; the `isEmpty` / `conc.isEmpty` / `else error` ladder still matches Scala's `RHSEmpty` / `RHSAbstr` (extractor: `con isEmpty`) / `_` exactly |
| `Loop/Wf.lean` `makeEmpty_ok` | the `set F := …` transcription updated | mechanical; the `git diff` hunk is entirely inside the proof, statement untouched |
| `Loop/Refine.lean` `makeEmpty_died` | same transcription | mechanical; statement untouched |
| `Loop/Refine.lean` `makeEmpty_run` | `adds_list` now called on `(x.rhs.abstr.excl v).elems.map …`; the `LoopRel.emptyProp` premise `w ∈ vset x.toConstraint` recovered as `(SSet.mem_excl_iff.mp hw).1` | **CONFIRMED "strictly fewer added facts."** The list is a sub-list and the exclusion is immediately DISCARDED to re-derive the same membership obligation. Statement untouched. Fewer things claimed added ⇒ the refinement is easier, not weaker |
| `Loop/StrictStep.lean` `makeEmpty_forward` | `List.mem_toFinset.mpr hw` → `… (SSet.mem_excl hw)` | statement, including the `hProp : ∀ S x, P (mk v S ∅) → x ∈ S → P (mk x ∅ ∅)` hypothesis, unchanged; the proof simply forgets the exclusion. Not a weakening |
| `Loop/StrictStep.lean` `MECover` + `makeEmpty_noLoss` | `MECover`'s middle disjunct now ranges over `(x.rhs.abstr.excl v).elems`; `makeEmpty_noLoss`'s `hcover` gained `by_cases hwv : w = v` | **CONFIRMED, and it is the interesting one.** `MECover` as a predicate IS weaker (it no longer promises a covering `z` for `w = v`) — but it is an internal covering predicate and its only consumer now discharges `w = v` from `hv0 : rho v = ∅`, obtained as `sat_empty_iff.mp (hm _ hvG)` where `hvG : mk v ∅ ∅ ∈ G` is the RETAINED environment fact. `makeEmpty_noLoss`'s own statement is unchanged. This is the Scala fix's soundness argument, in the model |
| `Loop/StrictBound.lean` `makeEmpty_aux_excludes_self` | replaces `makeEmpty_aux_emits_self` | **faithful.** Same subject (the propagation expression `(a.excl v).map (fun w => ⟨w, RHS.empty, partitionEmpty⟩)`), same shape as `selfSubstitution_excludes_self` (`∀ y ∈ S.elems, y.lhs ≠ v`), same proof skeleton. The old lemma stated the OLD behaviour and is now FALSE, so replacing it was required, not optional |

**`QueueHygiene` and `queueHygiene_no_rebind` are untouched.**  The definition body and the
theorem statement are byte-identical to the versions `L5-TERMINATION.md` §R2 quotes — the only
pre-B1 record, both files being untracked — and the proof is the same eight elementary lines.
Confirmed as instructed.

One scope note, which the report also states plainly: `makeEmpty_aux_excludes_self` is about
the propagation EXPRESSION, not about `makeEmpty`'s returned queues.  It removes the
counterexample to `QueueHygiene`; it does not prove preservation.  Deferred to L5 round 3.
Agreed, and §2's reading is the informal version of the missing proof.

## 8. Ship as the default? — YES

The fix is unconditional, with no flag, and that is right.

* **Nothing that worked stops working.**  Corpus trace byte-identical (363,570 records);
  corpus verdicts identical (23/43, 18/16, `shouldfail/` 40/40); per-file messages identical;
  18 tracked seeds identical to the byte including `DRAWN`; `drawn`/`bound`/`residual`
  identical on all 866 both-sides-solved hunt bases; both `crule` refutation controls still
  REJECTED 100/100; the six deliberate refutation seeds still REJECTED 20/20; `core/test`
  913/914 with only the pre-existing starvation; both smokes green.
* **Refutations are preserved**, including the `die` arm the fix sits next to (§5a: identical
  messages, base for base, with `labelCheck` off).
* **Valid programs that died are now accepted**: `PANIC3` 11/100 → 0, L5's fourteen seeds
  534/1400 → 0, my alias-biased population 141/6000 → 0, and `RS5` 50/50 → 0.  Nothing moved
  the other way in 7,500 + 6,000 + 1,400 + 360 + 450,064 measurements.
* **The alternative is worse**, and the report rejects it for the right reason: uncommenting
  `Subst.scala:183` would tolerate the re-binding and delete the only enforcement of queue
  hygiene, on which `EnvNodup` / `makeEmpty_env_len` and L5 §C3.4's branch table rest.

**Gates I did NOT re-run**, stated plainly: the `.ei` published-type sweep (gates 5/5b; ~13.5
min per side plus classification).  §3c is why — a bit-identical solver record stream over the
same 110 sources cannot produce a different interface, and the report's own same-checkout
control shows the sweep's noise (21 order-only bindings) is the same size as its signal.  I
also did not re-run `corpus-run.sh` per file over the whole corpus (19 minutes a side); I ran
it per file for the four modules whose batch messages differ, which is where it matters.

## 9. Findings

| # | severity | status | finding |
|---|---|---|---|
| **F1** | moderate (documentation) | **CONFIRMED** | `tracker/lean/README.md` **lines 458–469** are STALE. The paragraph "A compiler bug the hunt turned up" still describes the bug in the present tense (`makes the SHIPPED Subst.solve throw … at 11 of 100 id bases`) and the fix as prospective — "**The recommended fix is** `abstr.map` -> `(abstr - v).map`" and "**If it is adopted**, the Lean model's `makeEmpty` (`Loop/Step.lean:126`) changes in lock-step and L2/L4 must be re-run". Both trees now carry the fix and L2/L4 have been re-run. B1 updated the module table three rows above it (the `makeEmpty_aux_excludes_self` correction) but not this paragraph, so the README now contradicts itself. **Fix:** rewrite the paragraph in the past tense, point at `B1-FIX.md` and ticket item 11, and keep the mechanism (it is the best short statement of the root cause anywhere in the tree). |
| **F2** | minor (citation) | **CONFIRMED** | Three files cite **`L5-REVIEW.md` §4** for the root cause: `B1-FIX.md` §intro ("root-caused by `L5-REVIEW.md` §4/F3-F4"), `TICKET-editor-and-solver-followups.md` item 11 ("root-caused in `L5-REVIEW.md` §4 F3/F4"), `ROW-CONSTRAINT-STATE.md` ("root-caused in `L5-REVIEW.md` §4"). §4 is "The verbatim statements, checked against the modules". The root-cause trace is **§6.3**, the two-steps trace **§6.2**, the fix argument **§6.4**, and findings **F3/F4 are tabulated in §9**. |
| **F3** | minor (understated) | **CONFIRMED** | `B1-FIX.md` §6 and ticket item 11 "Left open (b)" say the alias form was "not investigated" and that "nothing in the hunt or the corpus exhibits it". §5b above investigates it: same `die` line, same two call sites, same root cause, no path after the fix by reading, and 6,000 alias-biased satisfiable solves with zero deaths of any kind (141 pre-fix, all the `ConcreteRho` form). **Fix:** replace "not investigated" with what is now known, and keep the residual as "unproved, pending `QueueHygiene.step`" rather than "unexamined". |
| **F4** | minor (materially understates the risk) | **CONFIRMED** | "nothing in the hunt or the **corpus** exhibits it" is true of the PANIC, but the PREMISE SHAPE is in the shipped standard library: `Layout/Report.e` produces `r <- (o, r)` — a multi-part self-reference — in every boot, in all seven corpus groups (§6). It is dissolved by `selfSubstitution` before any `makeEmpty` touches it, and the extracted seed plus two perturbations solve 100/100 at bases 0–99 on the PRE-FIX compiler, so the corpus really is safe. But "the shape is expressible" (L5 §6.5) understates it: **the shape is already compiled every day**, and only the dequeue order separates it from the panic. One sentence in ticket item 11 and in `B1-FIX.md` §1. |
| **F5** | informational | **PLAUSIBLE** (mechanism read; unobserved in every measurement) | The removed `v <- ()` was not inert while it sat in the incoming queue. `learnPartitions`' `concRows` (`Constraints.scala:1410-1418`) folds over `proc ++ incm` and indexes **every partition with an empty abstract part**, so a self-manufactured `v <- ()` was a visible EMPTY-ROW CARRIER for `findConcRow`/`findEmptyRow` — the lookups that guard `splitRow` and `resRow` (**both DEFAULT ON**) and `emptyRow`. In a state whose only empty-row carrier was that manufactured partition, a reuse could in principle become a mint. **Unobserved**: identical `drawn` on all 866 both-sides-solved runs, identical `DRAWN` histograms on all 18 tracked seeds at 20 bases, and a byte-identical corpus trace. Worth one sentence so that "changes NOTHING else that any gate can see" is read as the measured claim it is, not a structural one. |
| **F6** | cosmetic | CONFIRMED | The worktree's `B1-FIX.md` is the Part-A-only version (154 lines); the main tree's is the full 202-line report. Harmless while the worktree is short-lived; they will drift if it is kept. Worktree state is otherwise exactly as the report claims: branch `makeempty-self-fix` at `9be2214`, `M Constraints.scala` / `?? B1-FIX.md` / `?? seeds/PANIC3.json`, no commits, `tracker/repl-classpath.txt` restored, no `.ei` under `core/examples`; and the two trees' `Constraints.scala` and `PANIC3.json` are byte-identical. |

Nothing found that is incorrect in the fix, in the model mirror, or in any gate number the
report reports.  Every figure I re-ran matched.

## 10. Acceptance, gate by gate

| brief gate | re-run by me | verdict |
|---|---|---|
| A1 `core/compile` | implied by A2/R7 (`core/test` compiles first) | PASS |
| A2 `core/test` 913/914 | **yes** (main checkout, R7) | PASS |
| A3a `PANIC3` 100/100 | **yes**, with my own 89/11 baseline | PASS |
| A3b 18 tracked seeds identical | **yes**, normalised diff = 3 lines, all PANIC3 | PASS |
| A3c/d `crule` `W`/`gseed` 100/100 REJECTED | **yes** | PASS |
| A3e 14 hunt seeds 1400/1400 | **yes**, with my own 866/534 baseline | PASS |
| A4 corpus verdicts identical, `shouldfail/` 40/40 | **yes** (both corpora, both class sets) + per-file re-run of the differing four | PASS |
| A5 `.ei` 0 weaker | **not re-run** — superseded by §3c's byte-identical corpus trace; see §8 | PASS (by a stronger argument) |
| A6 `repl-smoke` / `lsp-smoke` | **yes**, 35 and 98 checks | PASS |
| B1 `lake build Rowpartition` 841 | **yes** | PASS |
| B2 `Audit.lean` 3058 / 0 | **yes** | PASS |
| B3 `lake build looptrace` | **yes**, 24 jobs | PASS |
| B5 `testOnly *LoopTrace*` 708/708, PANIC3 in the population, controls detected | **yes** | PASS |
| B6 L1 sweep 180/180 | **yes**, traces regenerated on both sides | PASS |
| B7 L2 corpus replay 0 differing | **yes**, and extended from 2 groups to 7 (450,064 segments) | PASS |
| B8 full `core/test` | **yes** | PASS |
| B-docs ticket item, state-file section, plan row | **read against my measurements** | PASS, subject to F1–F4 |

## 11. Verdict

**ADVANCE.**

The defect is real, the diagnosis is right, the fix is the minimal correct one, the model
mirrors it, and — measured further than the report measured it — the fix is a bit-for-bit
no-op on the entire corpus while removing every one of the 534 + 141 + 50 + 11 panics I could
provoke on satisfiable input.  Ship it as the default.

Recommended before the commit, none of them blocking and none of them touching code:

1. **F1** — rewrite `tracker/lean/README.md` lines 458–469 in the past tense.
2. **F2** — correct the three `L5-REVIEW.md §4` citations to §6.2/§6.3/§6.4 (findings F3/F4 in §9).
3. **F3** — reword ticket item 11's "Left open (b)" from "not investigated" to §5b's result.
4. **F4** — one sentence recording that the premise shape is in `Layout/Report.e` in the
   shipped stdlib, dissolved there by `selfSubstitution`, seed `STDLIB` 100/100 pre-fix.
5. **F5** — one sentence in `B1-FIX.md` §1 naming the `concRows` lookup as the mechanism by
   which the fix could in principle change a mint, and the measurements that show it does not.

Carried forward, unchanged from the report and agreed: `QueueHygiene.step` (L5 round 3) is the
proof that turns "unobserved" into "unreachable"; until it exists, §2 and §5b are readings, not
theorems.

---

### Appendix — where my evidence lives

`/home/dmitry/.claude/jobs/880c725d/tmp/review-B1/`:
`lake-build.log`, `audit.log`; `runcp.sh` (classpath-parameterised replay driver),
`classes-pre/`, `satterm-classes/`; `panic3-100.txt`, `hunt14/`, `hunt14-pre/`;
`hunt-post/` (375 genE seeds), `genU.py` + `seedsU/` + `huntU/` (300 alias-biased seeds, both
sides); `seeds/` (RS1–RS5, STDLIB, STDLIB2, STDLIB3) with `.pre`/`.post` sweeps and the
`labelCheck=false` variants; `seedsweep.sh` + `seeds18/{pre,post}.norm`; `l1/` + the 180-cell
sweep; `l2corpus/`, `l2corpus2/` (seven groups); `corpus-{pre,post}{,-inc}/` and `perfile/`;
`ctrace/{pre,post}.norm.tsv.gz` (the byte-identical corpus traces); `src/RP1–RP9.e` and
`runermine.sh`; `looptrace-test.log`, `core-test.log`, `repl-smoke.log`, `lsp-smoke.log`.
