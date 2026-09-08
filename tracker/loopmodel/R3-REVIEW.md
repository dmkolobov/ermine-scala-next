# R3 review — the determinacy closure (Rose Definition 13): the Lean, the three answers, the instrument, the measurement

Independent review of stage R3 (report `tracker/loopmodel/R3-DETERMINED.md`, outcome GREEN), brief
`tracker/loopmodel/briefs/brief-R3-review.md`.  Reviewed at main HEAD `8e771ea` plus R3's uncommitted
deliverables, and the trace-only Scala in the worktree `~/research/ermine/ermine-scala-wt-r3`
(branch `determined-closure`).  Everything below marked CONFIRMED was re-run or re-derived by the
reviewer; scratch in `/home/dmitry/.claude/jobs/880c725d/tmp/review-R3/`.

## Verdict

**FIX-THEN-ADVANCE.**  Nothing in the Lean or in the instrument needs to change; three DOCUMENTS do,
before they enter the record.

Every Lean statement I re-elaborated is the statement the report claims, on the standard axioms; every
batch number in §4 reproduced to the digit from traces I generated myself; every gate reproduced.  The
two negative results (a) and (b) are correct and, in my judgement, decisive: the splice guard should
never be built, and the deletion licence really does founder on the partiality of the row algebra.
The stage is GREEN as an investigation and the work should be committed.

The fixes, all editorial:

1. **M-4** — replace "1,245 lines, **124 theorems**" with the real count in the three places it
   appears (`R3-DETERMINED.md` §1 and the plan row and memo note): the module has **163 source
   declarations (115 `theorem`, 47 `def`, 1 `structure`) and 197 non-internal constants, 136 of them
   theorems** — the last figure being exactly the Audit delta 4,582 − 4,446 the report itself quotes.
2. **M-1** — fold §4.4 of this review into `R3-DETERMINED.md` §5 and the memo note, and **close the
   recommended stage 2 rather than leaving it pending.**  I computed the number that stage was to go
   and get: the three-clause closure flags **11 of the 19**, not "at most 6", and two of the eleven
   survivors are provable false positives, so §5's acceptance criteria 3 and 4 both fail.  As written,
   the plan row ("add the third clause and re-measure") and the memo's "OPEN for the ambiguity
   warning" schedule work whose answer is already known.
3. **M-2** — soften "seven false positives, all failing for the SAME reason".  Two of the nineteen
   (`(>=)`, `(<=)`, the two largest of the family the sample drew from) are false positives that
   `resolution` does **not** clear, for a reason no clause of this family can reach.

None of this touches `Determined.lean`, `RowTrace.scala` or `Subst.scala`.  My advice on the substance
is in §6: adopt (i) and the "no warning" half of (ii), do not schedule the stage 2, and open a small
separate ticket for the one item here that would change something a user can see — the tautology
deletion.

## Findings

| | rank | status | |
|---|---|---|---|
| **M-1** | HIGH (about the recommendation, not the work) | CONFIRMED | The stage-2 acceptance criteria in §5(ii) cannot be met by the `resolution` clause, and the number stage 2 would produce is computable now: the three-clause closure flags **11 of the 19**, not "at most 6", and **2 of those 11 are provable false positives**, so criterion 4's "at most one in ten" fails too. |
| **M-2** | MEDIUM | CONFIRMED | "Seven false positives, all failing for the SAME reason" over-generalises from a sample that happens to exclude the two hardest cases.  `Relation/Predicate.(>=)` and `(<=)` — 11 flagged row existentials each — are false positives that `resolution` does **not** clear; they need a semantic disjointness argument, i.e. exactly the `CriterionIncomplete` gap. |
| **M-3** | MEDIUM | CONFIRMED | `dead_delete_of_pairwise` is **not** the strongest true deletion licence (kernel-checked counterexample below), and neither it nor `dead_delete_of_le_one_part` covers the shape that dominates R3's own true positives — the tautology `r <- (t, h)` with `r` universal and both parts existential.  §5(iii) offers a theorem for a shape nothing here shows the corpus to have, while §5(ii) recommends deleting a shape for which R3 proved nothing. |
| **M-4** | LOW | CONFIRMED | The declaration count "**1,245 lines, 124 theorems**" is wrong, in three places (report §1, the plan row, the memo note).  Lines: 1,245 ✓.  Declarations: 163 in the source (115 `theorem`, 47 `def`, 1 `structure`); 197 non-internal constants in the module, **136 of them theorems** — which is exactly the Audit delta 4,582 − 4,446 the report itself quotes. |
| **M-5** | LOW | CONFIRMED | The **stdlib-boot** row of §4.2 is not reproducible run to run: three runs of the same R3 binary gave 192 / 193 / 192 splices and 41 / 34 / 41 Rose-licensed (21.4 % / 17.6 % / 21.4 %).  The default parallel loader is the cause.  The report's boot row is one draw of a distribution with ~20 % relative spread on the closure columns.  The same noise, averaged over 153 boots, is why my per-file totals land within 0.009 % of the report's rather than on them (§4.5); the batch row reproduced exactly, and the headline zero was stable in every draw. |
| **M-6** | LOW | PLAUSIBLE (not observed) | §4.1's "`U₀` is exactly `fv(τ) ∪ universals` as far as the closure can tell" has an unnamed exception: an existential dropped from `pubExts` by `am` (`ambiguitiesIn`, class constraints) can still occur in a row part of `pruned`, and the instrument then counts it in `U₀` as a universal.  `iso` cannot do this; `am` is not filtered out of `dumb`.  Direction: **under**-flagging.  Not observed on the 104 (my independent recomputation matched the instrument on every one of the 19). |
| **M-7** | INFORMATIONAL | CONFIRMED | §7 item 4 says there is no correspondence check between `Subst.Determinacy` and the Lean beyond the three side conditions.  There is now some: I reimplemented `roseAdd`/`cancelAdd`/`resAdd` from the Lean, ran them on the published `.ei` qualifications, and got the instrument's flag count **existential for existential on all 19** — and the same reimplementation reproduces seven kernel-checked Lean instances (`Has`, `Disj`, `Pivot.bare`, `Pivot.full`, `CriterionIncomplete`, `NotEq.res_cures`, the tautology). |


## 1. The closure, its properties, `determined_unique`, and the `resolution` clause

**Definition 13 is restated faithfully.**  `roseAdd G D = (G.filter (fun c => vset c ⊆ D)).image
Constraint.lhs` is the paper's clause read n-arily, and the licence is real: `lhs_eq_pfold` is
`Rose.sat_iff_pfold` applied, so "the left-hand row is a function of the parts" is inherited from R2
rather than assumed.  The concrete part `c.conc` is a literal and needs no membership in `D`, which is
the only place the n-ary reading could have cheated and does not.

**`cancelAdd` is exactly the clause the memo names, and no more.**  `v ∈ cancelAdd G D` iff some
`c ∈ G` has `c.lhs ∈ D`, `v ∈ vset c` and `(vset c).erase v ⊆ D` — the whole, the other *variable*
parts, and (implicitly, because it is a literal) the concrete part.  Its semantic content is
`Sat.eq_sdiff`, and that proof genuinely needs both halves of `Sat`: `eq_biUnion` for `⊇`,
`disjoint_conc'`/`disjoint_of_ne'` for `⊆`.  I checked the two obvious ways it could be too strong and
it is neither: cancellation does not fire when a second part is unknown
(`RevCheck2.cancel_needs_all_others`, `(1 : Var) ∉ Determined {⟨0,[1,2],∅⟩} {0}`, kernel-checked), and
the duplicate case `a <- (v, v, w)` is sound because `vset` collapses the repeat and `Sat` forces
`rho v = ∅` anyway.

**The closure properties are real.**  `subset_determined` / `determined_mono` / `determined_closed` /
`determined_least` / `determined_idem`, and each is proved rather than asserted.  Two things I looked
at specifically:

* `determined_closed` is not "iterate enough times and hope".  `iterate_fixed` is a genuine
  pigeonhole (`card_iterate_ge`: `n` non-fixed steps grow the carrier by `n`), instantiated at
  `W = U ∪ allVars G`, and `detStep_eq_iff_closed` is what turns "fixed point of `detStep`" into
  "closed under both clauses".  So `Determined` really is Definition 13's `T⁺_Ψ` (plus cancellation),
  not an approximation of it.
* `determined_union_disjoint` is load-bearing for the instrument (it is what licenses reading `U₀` off
  the partitions rather than off `fv(τ)`), and it is stated in the strong form —
  `Determined G (U ∪ X) = Determined G U ∪ X` — not merely as an inclusion.  Correct, and used
  correctly.

**`determined_unique` is the right statement** — `SModels rho G → SModels rho' G → AgreeOn rho rho' U
→ AgreeOn rho rho' (Determined G U)` — and its proof uses exactly the partial-monoid facts it claims:
`agree_roseAdd` rewrites by `Sat.eq_biUnion` (the whole is a function of the parts) and
`agree_cancelAdd` by `Sat.eq_sdiff` (a part is a function of the whole and the rest).  It needs no
fixed-point property, which is why it survives the third clause unchanged.  Note what it does *not*
say: nothing about entailment, nothing about `Holds`.  The file is honest about that in §12.

**The `resolution` clause (§13) is sound**, and I re-elaborated the proof rather than trusting it.
`resAdd` fires when `c.lhs ∈ D`, `d.lhs ∈ D`, `vset c ⊆ vset d`, `c.conc ⊆ d.conc`, and all but one of
`vset d \ vset c` is known.  Soundness is `agree_resAdd`, which goes through `sdiff_set_eq`: since
`rho c.lhs = c.conc ∪ (vset c).biUnion rho` and `c.conc ⊆ d.conc`, the set `Sat.eq_sdiff` subtracts
for `d` can be rewritten as `d.conc ∪ rho c.lhs ∪ ((vset d \ vset c).erase v).biUnion rho`, every
piece of which is determined.  So a `resAdd`-derived fact is entailed, and `determined3_unique` is a
theorem about a genuinely larger closure (`determined_subset_determined3`).  The clause needs no
`c ≠ d` side condition (equal `vset`s leave nothing to derive) and is conservative when the concrete
parts do not nest.

**Is there a hypothesis in the file that no real residual satisfies?**  I looked for one and did not
find one — but I did find a hypothesis whose only *stated* instances are degenerate:

* `resAdd`'s hypothesis is met by real residuals — `NotEq.res_cures` is the stdlib `(!=)`, and my §4
  recomputation finds it firing on seven of the nineteen flagged corpus signatures.  Not vacuous.
* `dead_delete_of_pairwise`'s hypothesis (`∀ rho, SModels rho (R.sys.erase c) → (parts rho c).Pairwise
  Disjoint`) is stated only with its `le_one_part` corollary, where it holds trivially.  It is *not*
  vacuous in general — `RevCheck2.two_part_deletion_licensed` (kernel-checked) gives a two-part
  instance: `v <- (x, y)` deleted from a residual that also holds `z <- (x, y)`, which already forces
  `x` and `y` disjoint.  But see M-3: the hypothesis is not necessary either, and no corpus residual
  I looked at has the shape it covers.

## 2. The three answers

### (a) The splice guard — REFUTED IN BOTH DIRECTIONS is the right reading

I re-elaborated both witnesses against `Splice.lean` rather than reading the theorem statements.

*Sufficiency fails.*  `Gs = {b <- (v), b <- (y), v <- (x)}` is `DroppedPartition.G` verbatim
(`Gs_eq`, by `decide`), `U₀ = {x, y, b}` is `vars \ {v}`, and `v ∈ RoseDetermined Gs U₀` because
`v <- (x)` is in the residual with `x` universal — **Rose's clause alone**, no cancellation, so the
refutation is not an artefact of Ermine's larger closure.  The candidate guard's hypothesis holds, and
the splice still loses `x <- (y)`, which the input entails (`entails_c`) and the residual does not
(`not_entails`, via the refuting model `rhoCE`).  The lost consequence is over `U₀` alone (`c_over_U0`),
so the refutation survives the vocabulary-restricted reading too.  One detail worth stating because it
is what makes this a fair test of the *candidate guard as briefed*: the guard is evaluated on "the
residual minus its own partition", and `p = v <- (y)` is indeed not in `Gs`; what is in `Gs` is the
*other* partition `q = v <- (x)` with the same left-hand side, which is precisely the situation the
instrument sees at a splice.

*Necessity fails.*  `Hs = {b <- (v, w), b <- (x, w)}`, `V₀ = {x}`: neither closure reaches `v` (no
constraint's variable parts are all in `{x}`, and no left-hand side is), yet the input entails
`v <- (x)` by cancelling `w` out of both constraints (`entails_p`, two applications of
`Sat.eq_sdiff`), and `splice_entails_iff` applies because `v` heads nothing in `Hs` and `p.conc = ∅`
makes the other two conditions vacuous.  So the guard blocks a splice that loses nothing.

**The deciding condition really is `hlhs`, and it really is syntactic.**  In the first witness `hlhs`
is the one hypothesis of `splice_entails_iff` that fails; in the second it holds.  `hlhs` is
`∀ d ∈ G, d.lhs ≠ v` — a property of the *list* `reduce` emits, and two systems with the same models
can differ on it, so no closure on models can see it.  This is not a gap in Definition 13; it is a
statement about `reduce`, which rewrites right-hand sides and discards the partition it consumed.

**Is "never build it" justified by the theorems alone, the measurement alone, or both?**  By the
theorems alone, for the only thing a guard could be *for*: determinedness is neither necessary nor
sufficient for conservativity, so a determinacy guard cannot be justified as a correctness guard.
The measurement then kills the fallback justification — "use it as a cheap conservative *heuristic*" —
because Rose's closure and the withdrawn guard (`= hlhs`, measured) never once license the same
splice: they are not a strong and a weak version of one criterion, they are near-independent.  I agree
with "never build it", and I would put it exactly that way: the theorem closes the correctness
argument, the measurement closes the heuristic argument.

### (b) The deletion licence — "the value, not the definedness" is correct

For a partial monoid this is the right diagnosis and the two refutations are the right two.
`DeadTwoParts` is the sharp one: Rose's clause *does* determine `v` in `v <- (x, y)`, and the
constraint is still not deletable, because it also says `x ⊥ y` and that survives `∃v`.  The gap is
exactly `pfold`'s partiality — `Rose.labelAlgebra` combines only disjoint rows — so Definition 13, which
speaks only about *values*, cannot license a deletion that also discharges a *definedness* obligation.
`DeadUndetermined` closes the memo's own weaker hypothesis with a different mechanism (the concrete
part `(|Foo|)` restricts the universal `a`), and both are `REquiv` refutations, not entailment
refutations, which is the right notion for a published residual.

**Are the two licensed forms the strongest true statements?  No — see M-3.**  `dead_delete_of_pairwise`
is sufficient but not necessary, and the reason is structural rather than fiddly: `REquiv` lets the
*other* existentials be re-chosen, so what is actually needed is "every model of the remainder can be
*adjusted on `R.ex`* to make the parts combine", not "every model of the remainder already has them
disjoint".  Kernel-checked witness (`RevCheck.pairwise_not_necessary`, scratch `Check1.lean`, standard
axioms):

```lean
def c : Constraint := ⟨0, [4, 2], ∅⟩            -- v <- (w, y)
def R : Residual := ⟨{0, 4}, {c}⟩               -- v = 0 and w = 4 BOTH existential
def R' : Residual := ⟨{0, 4}, ∅⟩
theorem pairwise_not_necessary :
    DeadEx R 0 c ∧ REquiv R R' ∧
      ¬ (∀ rho, SModels rho (R.sys.erase c) → (parts rho c).Pairwise Disjoint)
```

The witness for `REquiv` is `w := ∅`, `v := y`.  This is not a pedantic gap: it is the shape that
matters, because the corpus's genuine ambiguities are precisely constraints whose parts are all
existential.  Which leads to the second half of M-3 — the shape R3's own measurement finds
(`Layout/Scan`'s five: `r <- (t, h)`, `r` **universal**, `t` and `h` existential) is a tautology and is
deletable, and *neither* licensed form covers it, because both are about a dead existential on the
LEFT.  §5(iii) proposes `dead_delete_of_le_one_part` as "one thing that IS licensed and is small", and
§5(ii) proposes deleting the tautological shape; those are two different shapes and only the first has
a theorem.  Not a defect in R3 — it delivered what the brief asked — but a stage 2 built on §5(iii)
would be measuring a shape the corpus may not have.

### (c) The ambiguity criterion, and the `pivotData` verdict

`RowAmbiguous R := ∃ v ∈ R.ex, v ∉ Determined R.sys (allVars R.sys \ R.ex)` with
`witness_unique_of_not_rowAmbiguous` is the right transfer, and the report's care about what it does
*not* buy (rows are erased; Theorem 15 is unavailable because Definition 14 quantifies over the
principal scheme, which Ermine has not got) is correct and worth keeping.  `CriterionIncomplete` is a
real incompleteness witness and, as §4 below shows, not an isolated curiosity — it is the mechanism
behind the two false positives that survive `resolution`.

**`Pivot.criterion_split` — pivotData is Rose-ambiguous and NOT Ermine-ambiguous — is the RIGHT
verdict, not a sign the Ermine criterion is too loose.**  Three checks:

1. *The model is faithful.*  I regenerated the interface myself (per file, `loadInSeries`) and the
   published residual is
   `(|Issue,Key,Value|) <- ((|Key|), v32, i)`, `s <- ((|Sector,Price,MarketCap|), i)`, plus three
   `RUnion` **class** constraints, `s` universal, seven existentials.  `Pivot.full`'s three
   constraints are exactly the two row partitions with a carrier variable for the concrete left-hand
   side; the class constraints are correctly outside a row closure.
2. *The mathematics is right, and I checked it independently of the closure.*  My exact per-label
   solver (§4) says: on the bare constraint `i` and `v3` are genuinely undetermined; on the published
   residual both are determined.  That agrees with `bare_genuinely_ambiguous` and `full_unique`, and
   the reason is elementary — `s = {Sector,Price,MarketCap} ⊎ i` pins `i`, and then
   `{Issue,Key,Value} = {Key} ⊎ v32 ⊎ i` pins `v32`.
3. *The compiler agrees.*  The `ramb` line in my own trace reads
   `ramb ? core/examples/PivotTest.e(36:1) pivotData^… 7 2 2 0 2 i^… v3^… (empty)` — seven published
   existentials, two of them row existentials, **2 Rose-undetermined and 0 Ermine-undetermined**.

So "four solutions" is a true statement about the constraint `TICKET-row-constraint-decision.md` §1.3
quotes *in isolation*, and R3's correction of the memo (and of `R2-REVIEW.md` K-9) is right.  If
anything this is the strongest single result in the stage, because it is the one place where the two
closures disagree on a case the tree already had an opinion about, and the models settle it.

## 3. The instrument: is it dead when tracing is off?

I diffed the worktree (`git diff -- core/src`) and read every insertion.  There are exactly three:

| site | guard |
|---|---|
| `Subst.reduce`, after the `splice` record | the whole block is inside `if (RowTrace.enabled)` |
| `Subst.mkSimplified`, before the `Exists` | the whole block is inside `if (RowTrace.enabled)` |
| `Subst.inferImplicitBindingTypes`, around the per-binding `generalize` | `RowTrace.withBinding`, whose first line is `if (!enabled) body` |

`RowTrace.enabled` is a `val` (`path.nonEmpty`, `path` read once from the system property), so the
guard is a field read.  `withBinding`'s name argument is by-name, so `b.v.toString` is not rendered
when tracing is off; the residual cost when disabled is one thunk allocation per generalised binding
and no thread-local touch at all (`binding0.get` is reached only on the enabled branch).  The
thread-local itself is only *constructed* at class-init.  `Determinacy` is an object with no state; it
reads a `List[Type]` and returns `Set[TypeVar]`, draws no ids, touches no `SubstEnv`, builds no `Type`.

**No existing record changed shape.**  `Subst.Determinacy.conds` is a character-for-character
transcription of the `splice` record's inline block (I diffed the two by eye and they agree, including
`concrOf`'s treatment of `Con`), and the `splice` string literal is untouched.  The one non-trace
refactor — hoisting `exts filterNot (v => iso(v) || am(v))` into `val pubExts` — is semantics-preserving
(same expression, evaluated once, in the same place).

**Byte-identity gate, re-run on two groups (CONFIRMED).**  `Present` (14 files) and `Lang` (13 files),
one JVM per group, `-Dermine.loadInSeries=true -Dermine.useInterface=false`, base = the MAIN tree at
HEAD, R3 = the worktree.  I first checked that the two trees differ *only* by the instrument:
`diff -rq core/src` reports exactly `RowTrace.scala` and `Subst.scala`, and `core/examples` and
`core/src/main/resources` are byte-identical, so the A/B is clean.

| group | base lines | R3 lines | `detm` | `ramb` | base + detm + ramb | filtered vs base |
|---|---:|---:|---:|---:|---:|---|
| `Present` | 554,143 | 576,159 | 1,340 | 20,676 | 576,159 ✓ | **BYTE-IDENTICAL** |
| `Lang` | 318,303 | 325,911 | 431 | 7,177 | 325,911 ✓ | **BYTE-IDENTICAL** |

The line arithmetic closing exactly is itself the check that no existing record changed *count*.  Two
normalisations, both legitimate and both forced by my running the two sides in two different
directories: the one nondeterministic field (`rsound ok`'s elapsed microseconds, blanked on both
sides — the same field `tnorm.sh` blanks) and the tree root inside `Loc` strings
(`…/ermine-scala/` vs `…/ermine-scala-wt-r3/`).  The implementer avoided the second by running both
sides in one worktree; my version of the gate is the stricter one in that it also crosses trees.

**`.ei` sweep, re-run on a sample (CONFIRMED).**  Per file, interfaces **enabled**, `loadInSeries`,
over `core/examples/*.e` + `core/examples/Present/*.e`: **169 interfaces captured on each side,
`diff -r` empty.**  Every `.ei` I caused was deleted from both trees afterwards (`find … -name '*.ei'`
returns nothing in either tree).  As a bonus cross-check, my `Relation/Predicate.ei` is byte-identical
to the one in the implementer's own snapshot, which is evidence that their 268-interface run and mine
are the same measurement.

**`TestLoopTrace` in the worktree (CONFIRMED).**  `720 solves (20 seed x 6 bases + 600 generated);
720 segments; 720 agree; hashdiff=0 eqdiff=0 nonpart=0 fuel=0`, with the two controls firing (46 and
58 of 720 disagree under injected divergence).  Run with `-Dermine.looptrace` pointed at the main
tree's binary, since the worktree has no `.lake`.

## 4. The measurement, re-derived

I regenerated every population I quote.  Analysis is my own script (`rv-analyse.py`), written from the
record layout, not the implementer's `analyse.py`.

### 4.1 Splices

**Corpus, 18 groups, `--batch` (one JVM, 153 files) — reproduced to the digit.**

| | splices | ROSE | ERMINE | WITHDRAWN guard | hdis | hdup |
|---|---:|---:|---:|---:|---:|---:|
| R3 report §4.2 | 6,624 | 225 (3.4 %) | 670 (10.1 %) | 4,237 (64.0 %) | 100 % | 100 % |
| **reviewer** | **6,624** | **225 (3.4 %)** | **670 (10.1 %)** | **4,237 (64.0 %)** | **100 %** | **100 %** |

| cross-tab (18 groups) | Rose ∧ guard | Erm ∧ guard | Erm ∧ ¬guard | ¬Erm ∧ guard | neither |
|---|---:|---:|---:|---:|---:|
| R3 report | **0** | 269 | 401 | 3,968 | 1,986 |
| **reviewer** | **0** | **269** | **401** | **3,968** | **1,986** |

`splice`/`detm` counts equal (6,624 / 6,624) and the `(hlhs, hdis, hdup)` multisets agree, so §4.3's
cross-check reproduces as well.  Because `hdis` and `hdup` are 100 %, "the withdrawn guard IS `hlhs`"
is confirmed on this population, exactly as `splice_conc_disjoint_of_models` /
`splice_conc_empty_of_models` predict.

**Stdlib boot — reproduced, but it is a lottery (M-5).**  Three runs of the *same* R3 binary:

| run | splices | ROSE | ERMINE | guard | Rose ∧ guard |
|---|---:|---:|---:|---:|---:|
| 1 (parallel loader) | 192 | 41 (21.4 %) | 52 (27.1 %) | 6 (3.1 %) | **0** |
| 2 (parallel loader) | **193** | **34 (17.6 %)** | **44 (22.8 %)** | **7 (3.6 %)** | **0** |
| 3 (parallel loader) | 192 | 41 (21.4 %) | 52 (27.1 %) | 6 (3.1 %) | **0** |
| 4 (`loadInSeries`) | 193 | — | — | — | — |

Run 2 reproduces §4.2's boot row exactly, including the cross-tab (0 / 3 / 41 / 4 / 145) and §4.4's
boot `ramb` row (1,658 / 1,302 / 1,117 / 367).  Runs 1 and 3 do not.  The `ramb` totals are stable
(1,658 / 1,302 / 1,117 every time; `ermUndet` 365 vs 367).  So the boot's *splice* figures carry
run-to-run noise of the same order as the difference between the two closures, and the report should
not have quoted them without a spread — but nothing downstream rests on them, and the headline was
zero in every draw.

**Per file — one group, regenerated (CONFIRMED); the full 153-file figure is §4.5 below.**
`core/examples/Present`, 14 virgin JVMs, tracing on:

```
files=14 splices=4057 rose=625(15.4%) erm=844(20.8%) guard=558(13.8%)
hlhs=558  roseANDguard=0  ermANDguard=121
```

`guard == hlhs` again, the shares are in the same neighbourhood as the report's per-file row
(13.6 / 18.6 / 14.7), and **Rose ∧ guard = 0** over another 4,057 splices.  Counting the three
populations I generated myself so far, the "never once the same splice" claim is confirmed over
193 + 6,624 + 4,057 = **10,874 splices** with zero coincidences; §4.5 raises that to 49,715.

### 4.2 Row ambiguity

**Reproduced to the digit.**  From my own 18-group batch trace, distinct top-level named signatures
(binding name present, `Loc` column 1, deduplicated by name × file × line):

| | signatures | ROSE flags | ERMINE flags |
|---|---:|---:|---:|
| stdlib | **64** | **51** | **19** |
| `core/examples` | **40** | **37** | **0** |
| both | **104** | **88** | **19** |

`ramb` totals also reproduce exactly (86,320 records; 10,526 with a row existential; 10,141
Rose-undetermined; 3,468 Ermine-undetermined), as does the nineteen-signature table of §4.4 —
name, module, line, row-existential count and flag count, all nineteen.  §4.4's
"**33** of the 37 example signatures Rose flags carry exactly one row existential" is confirmed
(33 with one, 4 with two); the draft in scratch said 34 and the report's 33 is the right number.

### 4.3 Five of the nineteen, hand-checked — and an exact answer instead of a pen-and-paper one

The report hand-judges ten: `(!=)`, `cons_Bracket`, `dateRange`, `(&)`, `(**)`, `setColumn`, `level1`,
`count`, `sumBy`, `lookbackJoin`.  I took **five different ones**: `(>=)`, `(&_Mem)`,
`drilldownPivotTabular`, `avgBy'`, `cutoffGroupedFldsPosNegRel'`.

Rather than answer by hand alone I built an exact decision procedure for the semantic question, which
is worth describing because it makes "is this existential really forced?" a computation rather than a
judgement.  A row is a finite set of labels and every constraint is a set partition, so **the question
decomposes per label**: for one label `l`, each variable becomes a bit and `a <- (p₁…pₙ, K)` becomes
`b_a = b_p₁ + … + b_pₙ + [l ∈ K]` with at most one summand true.  Only two label classes matter — a
label that is one of the concrete labels the residual names, and a generic label that is none of them
— so the whole question is two finite boolean CSPs, solved exactly by propagation and branching.
An existential is *semantically undetermined* iff, in some class, two solutions agree on every
universal bit and differ on it.  No closure is involved anywhere in this.

I validated the procedure against seven facts the Lean already proves, and it agrees with all seven:
`Has` determined (by cancellation only), `Disj` determined (by Rose's clause), `Pivot.bare` undetermined
at `i` and `v3`, `Pivot.full` determined at both, `CriterionIncomplete`'s `a <- (v,v,w)` semantically
determined but flagged by both closures, `NotEq` flagged by two clauses and cleared by three, and the
tautology `r <- (t,h)` undetermined.

| # | signature | row ex | flagged (2-clause) | semantically undetermined | verdict | does `resolution` clear it? |
|---|---|---:|---:|---:|---|---|
| 1 | `Relation/Predicate.(>=)` :63 | 11 | 11 | **0** | **FALSE POSITIVE** | **NO** |
| 2 | `Syntax/Relation.(&_Mem)` :56 | 3 | 3 | **0** | **FALSE POSITIVE** | YES |
| 3 | `Layout/Report.drilldownPivotTabular` :781 | 3 | 2 | **2** | TRUE POSITIVE | no (not needed) |
| 4 | `Layout/Scan.avgBy'` :45 | 2 | 2 | **2** | TRUE POSITIVE, a TAUTOLOGY | no (not needed) |
| 5 | `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` :38 | 34 | 33 | **16** | TRUE POSITIVE at the signature level, but the criterion over-flags 17 of the 34 | partly (33 → 31) |

So on my five: **two false positives out of five** — a better rate than the report's 7 of 10, and
consistent with it once you notice that the report's ten are drawn from the small-signature end.

Three of these are worth spelling out.

**1. `(>=)` is the finding (M-2).**  Its residual is nine partitions over three universals `a1`, `b`,
`t` and eleven existentials.  All eleven are semantically determined, and the argument is *not* a
propagation:

```
b  = f ⊎ e        a1 = e ⊎ d        c = f ⊎ e ⊎ d
```

From the first two, `f = b \ e` and `d = a1 \ e`; the third says `f` and `d` are **disjoint**, so
`(a1 ∩ b) \ e = ∅`, and with `e ⊆ a1 ∩ b` that forces `e = a1 ∩ b` exactly.  Everything else follows
(`c₁ = c`, then `so = ro`, and `t = ro ⊎ so ⊎ rs` forces `ro = so = ∅`).  The pin comes from a
*disjointness* obligation, not from a value anyone knows — which is precisely
`CriterionIncomplete.sound_not_complete`'s mechanism, at corpus scale.  No clause of the
`roseAdd`/`cancelAdd`/`resAdd` family can see it, and I verified that: with `resAdd` added, `(>=)` and
`(<=)` are still flagged, 11 existentials each.

**4. `avgBy'` (and `count`, `count'`, `sumBy`, `sumBy'`) is a tautology, and R3 has no theorem for it.**
`exists h t. r <- (t, h)` with `r` universal is true of every `r` (`t := r`, `h := ∅`), so the
criterion is right that it is undetermined and right that nobody should be warned about it.  But the
deletion licence R3 proves is about a dead existential on the LEFT, and here the left-hand side is the
*universal*.  This is the second half of M-3.

**5. `cutoffGroupedFldsPosNegRel'` is the case that argues for a warning and against a per-variable
one.**  26 partitions, 34 row existentials, 33 flagged, **16 genuinely undetermined**.  The signature
really is row-ambiguous, so a signature-level warning would be right; a warning that named the flagged
variables would name seventeen that are in fact pinned.

### 4.4 The stage-2 number, computed (M-1)

Because the criterion is a closure over the *published* residual, I could compute the three-clause
answer without touching the compiler: I reimplemented `roseAdd`, `cancelAdd` and `resAdd` from
`Determined.lean` in ~40 lines and ran them on the `.ei` qualifications of all nineteen.

**Validation first.**  My two-clause result matches `Subst.Determinacy`'s `ermUndet` count on **all
nineteen**, existential for existential (11, 11, 3, 3, 3, 3, 3, 3, 3, 9, 3, 2, 2, 2, 2, 2, 2, 2, 33).
That is an independent check on the transcription §7 item 4 says it lacks (M-7): two implementations
written from the Lean, one inside the compiler on `pruned` and one outside it on the published
interface, agree everywhere.

| signature | row ex | 2-clause | **3-clause** | semantic |
|---|---:|---:|---:|---:|
| `Predicate.(>=)` | 11 | 11 | **11** | 0 ← false positive survives |
| `Predicate.(<=)` | 11 | 11 | **11** | 0 ← false positive survives |
| `Predicate.(!=)` | 3 | 3 | **0** | 0 |
| `Syntax/Relation.(**)` | 3 | 3 | **0** | 0 |
| `Syntax/Relation.(&)` | 3 | 3 | **0** | 0 |
| `Syntax/Relation.(&_Mem)` | 3 | 3 | **0** | 0 |
| `Relation/Op.cons_Bracket` | 3 | 3 | **0** | 0 |
| `Relation/Op.dateRange` | 3 | 3 | **0** | 0 |
| `Relation.setColumn` | 4 | 3 | **0** | 0 |
| `Relation/RTree.level1` | 5 | 3 | **0** | 0 |
| `Relation.lookbackJoin` | 11 | 9 | **8** | 8 |
| `Layout/Scan.sumBy`, `sumBy'`, `avgBy'`, `count`, `count'` | 2 each | 2 | **2** | 2 |
| `Layout/Report.drilldownPivotTabular`, `…'` | 3 each | 2 | **2** | 2 |
| `Layout/Report/Relation.cutoffGroupedFldsPosNegRel'` | 34 | 33 | **31** | 16 |
| **signatures still flagged** | | **19 / 19** | **11 / 19** | **9 / 19** |

**This is the number the recommended stage 2 would go and get, and it fails the report's own
acceptance criteria.**

* §5 criterion 3 — "`core/examples` stays at zero flagged **and** the top-level stdlib count drops
  from 19 to at most the six the hand-judged sample says are genuine".  It drops to **11**, not 6.
  The six the report names (`count`, `count'`, `sumBy`, `sumBy'`, `avgBy'`, `lookbackJoin`) are all
  still there, correctly; the five it did not anticipate are `(>=)`, `(<=)` (false positives) and
  `drilldownPivotTabular`, `drilldownPivotTabular'`, `cutoffGroupedFldsPosNegRel'` (genuine).
* §5 criterion 4 — "a second hand-judged sample of ten from whatever remains flagged has a
  false-positive rate of at most one in ten".  Only eleven remain and **two of them are false
  positives**, so a sample of ten has an expected 1.8.  Marginal at best, and the two are not
  fixable by another propagation clause.
* §5 criteria 1 and 2 are met (the theorem is there; the byte-identity gate is the one this stage
  already passed).

Two consolations, both real: the eight signatures `resolution` *does* clear are cleared completely
(3 → 0, not 3 → 1 — `(!=)`, `(**)`, `(&)`, `(&_Mem)`, `cons_Bracket`, `dateRange`, `setColumn`,
`level1`), and the three-clause criterion's precision on the corpus is 9 genuine of 11
flagged — 82 %, against 9 of 19 (47 %) for the two-clause one.  So the clause is a large improvement;
it is just not the last one, and "near zero false positives" is not reachable by clauses at all while
`CriterionIncomplete`'s mechanism is live in the corpus.


### 4.5 The full per-file sweep (153 virgin JVMs), and the "90 % vs 64 %" correction

I ran the whole per-file sweep myself — 153 files, one virgin JVM each, tracing on, `useInterface`
off — because the "0 of 42,902" headline is stated on that population.

| | splices | ROSE | ERMINE | WITHDRAWN guard | Rose ∧ guard | Erm ∧ guard |
|---|---:|---:|---:|---:|---:|---:|
| R3 report §4.2 | 42,902 | 5,839 (13.6 %) | 7,972 (18.6 %) | 6,298 (14.7 %) | **0** | 799 |
| **reviewer** | **42,898** | **5,867 (13.7 %)** | **7,998 (18.6 %)** | **6,294 (14.7 %)** | **0** | **803** |

Every percentage matches; the raw counts differ by 4 splices in 42,898 (0.009 %) and by 28 / 26 / 4 in
the three closure columns, which is exactly the loader noise M-5 quantifies (each of the 153 JVMs
boots the stdlib and each boot is worth ±1 splice).  `hdis` and `hdup` are 42,898 / 42,898 — 100 % —
so `guard == hlhs` on this population too.  **`Rose ∧ guard = 0` over all 42,898.**  Counting every
population I generated (42,898 per file + 6,624 batch + 193 boot) the claim survives **49,715 splice
observations with zero coincidences**, which is a stronger base than the report's own 8,415 + 42,902.

The per-file `ramb` totals reproduce *exactly*: **357,367** records, **222,546** with a row
existential, **192,823** Rose-undetermined (report: the same three figures), 65,529 Ermine-undetermined
against the report's 65,537.  And §4.4's real claim — that the DISTINCT census does not depend on the
compilation mode — reproduces exactly: from the per-file sweep I get **104 distinct top-level named
signatures, 64 stdlib and 40 examples, Rose flagging 51 / 37 and Ermine 19 / 0**, identical to the
batch census in every cell.

**The "90 % vs 64 %" correction is right in substance, and one number in it is loose.**  I split the
splices by where they are located.  Per file, the boot really does swamp everything —
`core/examples/PivotTest.e` alone gives **193 stdlib-located splices passing the guard at 3.6 %** and
**10 corpus-located ones**; `Present/Helpers.e` gives 195 and 14.  So a per-file sweep is ~70 % boot,
and the historical 9.7 % is a fact about the boot, exactly as the report says.  On the 18-group batch,
though, the split is 816 stdlib-located splices at 13.6 % and **5,808 corpus-located at 71.0 %** — so
"the corpus modules' own splices pass at 64 %" is really the whole-batch rate (4,237 / 6,624); the
corpus modules' own rate is 71 %.  The correction's direction and its point are unaffected.

## 5. Gates, re-run

| gate | report | reviewer | |
|---|---|---|---|
| `lake build` | green, 870 jobs | **green, 870 jobs** (replay; `looptrace` not among them) | CONFIRMED |
| `Audit.lean` | 4,582 theorems / 0 non-standard | **4,582 / 0** | CONFIRMED |
| Audit baseline | 4,446 re-derived by removing the import | not re-run — but **arithmetically closed**: the module contributes exactly 136 theorems (below), and 4,582 − 136 = 4,446 | CONFIRMED (indirect) |
| `#print axioms` | "the 34 headline theorems" | **all 197 non-internal declarations of the module** (136 theorems, 58 defs, 3 other), enumerated from the environment by module index: **0 using a non-standard axiom**; the 26 headline names I picked by hand all print `[propext, Classical.choice, Quot.sound]` | CONFIRMED, and stronger than the report's |
| `sorry` / `axiom` / `native_decide` | 0 / 0 / 0 | **0 / 0 / 0** (grep, and `collectAxioms` over all 197 shows no `sorryAx`) | CONFIRMED |
| declaration count | "124 theorems" | **163 source declarations / 197 constants / 136 theorems** | **M-4, wrong** |
| `core/test` (worktree) | 922 total, 1 failed, 921 passed | **922 / 1 / 921**, the failure being exactly `Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded` | CONFIRMED |
| the `TestInterfaceRoundTrip` flake §6 mentions | passed on re-run | **did not reappear** in my run | CONFIRMED |
| `TestLoopTrace` | 720/720 | **720 solves, 720 segments, 720 agree** | CONFIRMED |
| trace byte-identity after filtering | byte-identical | **byte-identical on `Present` (554,143 lines) and `Lang` (318,303)** | CONFIRMED |
| `.ei` sweep | 268 interfaces byte-identical | **169-interface sample byte-identical**, and one file cross-checked byte-identical against the implementer's own snapshot | CONFIRMED (sample) |
| `looptrace` mtime | not rebuilt | **Sep 7 15:12**, i.e. before the stage started and unchanged by my `lake build` | CONFIRMED |
| `git diff --stat` in main | module, root import, docs only | `LOOP-MODEL-PLAN.md +2`, `ROSE-COMPARISON.md +51`, `Rowpartition.lean +32`, untracked `Rowpartition/Determined.lean` and `R3-DETERMINED.md`.  **Nothing else.** | CONFIRMED |
| worktree diff | `RowTrace.scala +51`, `Subst.scala +153` | confirmed, plus the tracked `tracker/repl-classpath.txt` one-liner the report flags in its own §1 note | CONFIRMED |
| trees differ only by the instrument | claimed | `diff -rq core/src` = those two files; `core/examples` and `core/src/main/resources` byte-identical | CONFIRMED |
| `.ei` hygiene | every `.ei` deleted | I caused and deleted my own; `find` over both trees returns **none** | CONFIRMED |
| perf-bench 10.97 → 10.95 s | unmoved | **not re-run** (an orchestrator A/B owns that measurement, and the claim is inside the base run's own spread) | not checked |

The plan row and the memo note are accurate to the report — same claims, same numbers — and both
inherit M-4's "124 theorems".  The memo note is properly additive and explicitly withdraws the two
sentences of rank 4 that R3 refuted, which is the right way to record a refutation.

## 6. The recommendation (§5), judged

### (i) The splice guard — NEVER.  **Agree, without reservation.**

This is the strongest part of the stage.  The guard is refuted in both directions on satisfiable
four- and five-variable systems with no concrete labels, so it fails for structural reasons and not
for want of a cleverer closure; and the report identifies *why* — the deciding condition is
`hlhs`, a property of what `reduce` emits, and closures see models.  The measurement then removes the
"use it as a heuristic anyway" escape: over 10,874 splices I generated myself, Rose's closure and the
withdrawn guard never license the same one.

I would keep the report's closing observation, because it is the actionable part: anything that fixes
the splice has to change `reduce` — append the consumed partition, or rewrite left-hand sides too —
not guard it.  That belongs in `TICKET-signature-resolution-fragility.md`, not in a stage 2.

### (ii) The ambiguity warning — **agree "not yet", but do NOT run the recommended stage 2.**

The recommendation's logic is: the criterion's false-positive rate is 7/10, every failure has one
cause, the cure is proved, so a stage 2 needs a number and not a theorem.  The first two premises are
where it slips.  The cure is proved, and it is a big improvement; but §4.4 above **is** that number,
and it says the stage would end in a "no" on its own criteria:

* the stdlib count drops 19 → **11**, not to 6;
* two of the eleven survivors are false positives, and they survive because of a *semantic*
  disjointness forcing, not a missing propagation clause — so criterion 4's "at most one in ten" is
  not reachable by adding clauses at all;
* `core/examples` stays at zero, which is criterion 3's other half, and that is a genuinely good sign.

**Are the acceptance criteria the right ones?**  Criterion 3's first half (`core/examples` stays at
zero) is exactly right — it is the population a user writes.  Criterion 4 is the right *kind* of
criterion with the wrong *unit*: it counts false positives per hand-judged signature, but the report's
own sample scores a signature as a false positive only when *every* flagged existential is determined,
and §4.3 case 5 shows the interesting middle (`cutoffGroupedFldsPosNegRel'`: flagged 33, genuine 16)
where the signature-level verdict is right and the variable-level verdict is badly wrong.  If a
warning were ever written it should be **signature-level** ("this signature's row residual does not
pin all of its row existentials") and never name the variables, and the acceptance criterion should be
signature-level too.  Under that reading the three-clause criterion scores 9 genuine of 11 flagged —
82 % precision, up from 47 % — which is respectable and still not "near zero false positives".

**And the threshold is not the real problem.**  Even a perfect criterion would be warning about
something a user cannot act on: Ermine's rows are erased, so the payoff is precision of the published
type, and five of the nine genuine flags are the *tautology* `exists h t. r <- (h, t)`, where the
right response is to delete the constraint, not to warn.  Strip those and the corpus has **four**
signatures a warning could usefully name, all stdlib, none in `core/examples`.  That is not enough to
justify a diagnostic, a flag, and the maintenance of a closure inside `mkSimplified`.

### (iii) What should be committed, and is a stage 2 worth the user's time?

**Commit R3 as it stands**, with M-4's count corrected in the three places it appears.  The Lean is
sound, complete for what it claims, and the two refutations are results the tree should not have to
rediscover.  I would also commit **the instrument** on its branch: it is provably dead when disabled
(§3), it is the only way anyone re-checks these numbers, and both of my strongest results came out of
running it.  `ROW-CONSTRAINT-STATE.md` untouched is correct — nothing solver-visible moved.

I would add one paragraph to `R3-DETERMINED.md` §5 (or to the memo note) recording §4.4's table, so
that the stage 2 is **closed** rather than left pending.  As it stands the plan row says "no ambiguity
warning yet — add the third clause and re-measure", which reads as scheduled work.

**Is a stage 2 worth the user's time?  For the ambiguity warning: no.**  Its number is above, it fails
its own criteria, and the criterion cannot be pushed further by clauses.

**There is one small thing that is worth a ticket, and it is not a warning.**  Of everything R3
touched, the only item that would change something a user can see is the **tautology deletion**:
`exists t h. r <- (t, h)` with `r` universal and both parts existential is true of every `r`
(`t := r`, `h := ∅`), it accounts for five of the nine genuine flags, and deleting it shortens five
published stdlib signatures.  It needs a theorem R3 does not have — M-3 shows neither
`dead_delete_of_pairwise` nor `dead_delete_of_le_one_part` covers it, because both are about a dead
existential on the *left* — but the proof is a two-line witness of the same kind as
`RevCheck.pairwise_not_necessary`, and the measurement is `ei-diff.sh`, which answers the question
§7 item 6 says the splice measurement could not: how many published interfaces actually change.  That
is a one-stage job with a user-visible result, and I would put it on the queue ahead of anything else
in this area — as its own ticket, not as "R3 stage 2".

## 7. Scope of this review, and what I did not check

* **Re-run by me, in full:** `lake build`; `Audit.lean`; axioms over every declaration of the module;
  the two-group trace byte-identity gate (both sides generated here, in two different trees); the
  compiler's own stdout on both groups (identical after normalising timings and the tree path); the
  169-interface `.ei` sweep; `TestLoopTrace`; `core/test`; the stdlib boot (four times); the 18-group
  `--batch` measurement; a one-group per-file measurement and then the full 153-file per-file
  sweep; the census of 104 published signatures; and an independent semantic decision procedure
  applied to five signatures and validated against seven kernel-checked Lean instances.
* **Not re-run:** `perf-bench` (an orchestrator A/B owns it, and the claim is inside the base run's
  own spread); the `--incomplete --batch` population; the Audit *baseline* by removing the import
  (closed arithmetically instead); `core/test` on the base side (the R3 side matches the documented
  figure, which is what "unchanged" needs).
* **A small gap for any stage 2, noted for completeness:** §13 defines `Determined3` but no
  `Row3Ambiguous` — the criterion itself is stated only over the two-clause closure.  Trivial to add,
  and it would need adding before anyone measured the three-clause criterion inside the compiler.
* **The one thing I would still like and could not get cheaply:** a correspondence *theorem* between
  `Subst.Determinacy` and `roseAdd`/`cancelAdd`, of the `KeyedSplitScala.lean` kind.  §7 item 4 is
  right that there is none.  My §4.4 recomputation is evidence at corpus scale (two independent
  implementations agreeing on all nineteen) but it is not a proof, and it reads the *published*
  residual rather than the `cs` that `reduce` sees, so it says nothing about the `detm` half.

### Reviewer artefacts

All in `/home/dmitry/.claude/jobs/880c725d/tmp/review-R3/`, none of it in the repository:
`AxiomsR3.lean` (the module-wide axiom scan), `Check1.lean` (`RevCheck.pairwise_not_necessary`),
`Check2.lean` (`RevCheck2.two_part_deletion_licensed`, `cancel_needs_all_others`), `determ.py` (the
exact per-label semantic decision procedure), `closures.py` (`roseAdd`/`cancelAdd`/`resAdd` on a
published `.ei`), `rv-analyse.py` (the trace summary), and the traces, `.ei` snapshots and per-file
aggregates behind every table above.
