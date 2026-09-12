# SIG-2 REVIEW: the signature-entailment design and its Lean proof

Reviewer pass over `SIG-2-DESIGN.md` + `tracker/lean/Rowpartition/SigEntail.lean` (both
UNCOMMITTED on `sig-entail`, HEAD 69f5200). Nothing in the tree was changed except this
file; scratch in `.../scratchpad/review-S2/` (`bf.py` brute force, `indep.py` a second
decision procedure, `cases.py` constructed inputs, `measure.py`/`qsat.py` corpus facts).

## Verdict: **FIX-THEN-ADVANCE**

The mathematics holds. I read the crux proof line by line, rebuilt the Lean module, ran
the audit, re-decided the whole corpus with TWO implementations I wrote myself, and ran
36,000 random differential trials against the designer's engine: **not one disagreement,
and the 288/21/0 split reproduces exactly**. The five new `Time/Helpers.e` rejections are
real holes and I found the precise bug in S1's triage that hid them.

What must be fixed before S3 is the **design's prose definition of `R`/`F` and `W`**, which
is NOT what its own oracle implements and is unsound as written (F1, F2), and three
checklist gaps that would otherwise be decided by the implementer alone (F3, F4, F5).
None of this touches the Lean proof; F1/F2 are edits to §(a)/(a3) and to the checklist.

---

## 1. The crux lemma: sound, and the generic label is handled correctly

`sigEntails_of_lsig` (SigEntail.lean:187-222) is right, and the brief's suspicion is not
where the risk lives.

* The gluing does **not** rely on the label set being finite. The per-label choices `β l`
  are obtained by `choose` over ALL labels; the witness is
  `fun v => if v ∈ F then S.filter (β · v) else rho v` with
  `S = span (Q ++ W) rho = concLabels (Q++W) ∪ (voc (Q++W)).biUnion rho` — finite because
  it is built from the finite input and the finitely-supported given model, which is what
  makes the witness a legal `Assign = Var → Finset Label`. Outside `S` the proof does not
  use `β` at all: it rewrites to the all-false assignment (`proj_false_of_not_mem_span`
  covers `v ∉ F`, `hl` kills the `filter` for `v ∈ F`) and closes with
  `bmodels_false_of_not_mem W`. Both branches check out.
* **The generic class is NOT handled by `sigEntails_of_uniform`** (the brief's hypothesis).
  It is handled by `bsat_label_congr` + `sameClass_of_not_mem` + `bsigStep_class_congr` →
  `lsig_iff_classes`: `BSat` reads the label only through `c.conc`, so any two labels
  outside `concLabels (Q ++ W)` give literally the same Boolean problem. That argument
  needs no uniformity and no hypothesis on `W`. `sigEntails_of_uniform` is used only for
  (b6)'s "a derivational check would be sound", and is correct there.
* **Mixed input (literal labels in `Q`, variable-only `W`)**: covered, because the class
  set is `concLabels (Q ++ W)` — Q's labels get their own classes even when `W` has none.
  I built the case (`cases.py`): `Q = r <- ((|health|), t)`, `W = o <- (r, t)` with `o`
  minted. The `health` class ACCEPTS and the **generic** class REJECTS (witness
  `r = t = 1`); with `o` rigid the `health` class rejects instead (witness `r = 1`). Both
  classes are load-bearing on one input, and `lsig_iff_classes` is exactly what glues them.
  The corresponding implementation requirement is met: `sigcheck.py` takes labels from
  `Q + W` (line 152), and (b2)/(b3) say `concLabels(Q ++ W)`.

## 2. Completeness and the unsatisfiable-`Q` branch

`lsig_of_sigEntails` needs `hsat` and uses it exactly as `entails_iff_forall_label` does
(`exists_splice`, project back). `lsig_stronger_of_unsat` witnesses that the hypothesis is
not removable (via `Basic.Counterexample`, `F = ∅`).

I built the brief's unsatisfiable system `Q = {r <- (a,b), r <- (a), b <- ((|x|), c)}`
(`cases.py`). Confirmed on both sides:

| `W` | procedure | truth |
|---|---|---|
| `o <- (r, a)`, `o` rigid | **REJECT**, generic class, witness `o = 1` | vacuously ENTAILED |
| `r <- (f)`, `f` minted | ACCEPT | vacuously ENTAILED |

So the per-label reading really is strictly stronger on real-shaped input and (a2) is
load-bearing, not decoration. Two consequences the design does not draw:

* `Q` has a model at the generic class and none at the `x` class — i.e. **unsatisfiability
  of a partition system is always visible at a concrete label** (all-empty rows model every
  concrete-label-free partition). So (a2)'s reuse of `Constraints.labelDecide`, whose label
  set is `ps.foldLeft(...)(_ ++ r.concr)` (Constraints.scala:2717) and which therefore
  returns `LabelSat` for a label-free `Q`, is **correct**, and the synthetic generic label
  of (b2) is needed for the ENTAILMENT classes only. Worth one sentence in (a2): it looks
  like the same bug otherwise.
* `sigcheck.py` implements no satisfiability check at all, so as S3's "expected-verdict
  oracle" it is valid only while no corpus signature has unsatisfiable givens. I measured
  that: **0 of 309 signatures have a label class admitting no model of `Q`** (`qsat.py`).
  The design's "the sweep found no such signature" is confirmed; make it an assertion in
  the oracle rather than a remark.
* The checklist implements the policy only in outline — see F4.

## 3. Rigidity: one choice is provably free, one is provably WRONG as written

**Q's own existentials (a1): sound, and free.** I re-measured independently
(`measure.py`, and the designer's `overlap.py` agrees): of 37,264 row-obligation records,
**0** have a wanted mentioning an `A`-tagged variable that also occurs in the givens. The
structural argument is airtight: `qxs` is minted at Subst.scala:539 and `ps` comes from
`substType(pz)` at :540, after the only `unifyType` in `subsumeType` (:537), so no wanted
can name a given's witness. `sigEntails_hidden_iff` then makes the reading free. One
caveat for S3: this holds only because the check is computed from the `qs`/`ps` of
:539-541; it must not be re-`substType`d after any later unification (S4's editor path).

**`Bound` (a3): rigid is right, but the stated reason is wrong.** A dangling `Bound`
survives because `Forall.mk` keeps only binders occurring in the BODY
(`nts = typeVars(b).filter(tm)`, Type.scala:373) — so such a variable occurs **only in
`q`, never in the declared type `b`**, hence `unifyType(r1, r2)` can never introduce it
into the body's residual. Therefore *no wanted can mention a dangling `Bound`, ever*: the
measured 0 is a theorem, not a corpus accident, and the (a3) widening of `W` catches
nothing — it is dead code. That matters because (a3) sells the widening as its own
justification while `sigEntails_hidden_iff`'s hypothesis ("no wanted mentions them") is
precisely what the widening would violate. Replace the paragraph with the `Forall.mk`
argument.

**The `R` formula is unsound as written — F1.** (a) says
`R = sks ∪ qxs ∪ {Bound free in Q or W}`, `F = vars(W) \ R`. Two failures:

1. It derives rigidity from **this call's** `sks` list. A skolem in `W` that belongs to an
   ENCLOSING signature is none of `sks`/`qxs`/`Bound`, so it lands in `F` and the check may
   CHOOSE it — accepting a dishonest signature. Nested signed bindings do reach the check:
   `Lang.Helpers.sig:withRunning` (a `where`-bound signature, `core/examples/Lang/Helpers.e`)
   is in the sweep. That instance is benign (all its variables are its own), but the formula
   is wrong in principle, and the corpus cannot exonerate it because the probe prints no
   `sks` list.
2. It does not put `vars(Q)` in `R`. If any variable of `Q` is not a skolem/qx/`Bound` (an
   ambient meta — open question 2), it falls into `F`, and then (i) the witness `rho'` need
   not model `Q` any more, so `SigEntails` stops meaning "extend a model of the givens",
   and (ii) (b3) step 4's "enumerate the models of `Q_l` over `R`" is not even well defined.

`sigcheck.py` has neither bug: it keys off the printed flavour tag and excludes every
given variable (`F = {v ∈ wv - qv : tag ∈ {A, ''}}`, line 149). So **the oracle and the
prose disagree, and the oracle is the correct one.** Fix (a) to
`R = vars(Q) ∪ {v ∈ vars(W) : v.ty ∈ {Skolem, Bound}} ∪ (ambient)`, `F = vars(W) \ R`,
and state `F ∩ voc(Q) = ∅` as a standing invariant of the judgement.

**Ambient metas (open question 2) must be decided BEFORE S3, and the corpus cannot help.**
I measured the flavour histogram over all wanted variables: `{S: 64426, A: 58370}` — **no
bare-`Free` variable occurs in any wanted**, so the permissive and conservative rules are
indistinguishable on this corpus. The divergence is real though: with `W = {m <- (r, f)}`,
`m` ambient, the permissive rule ACCEPTS and the conservative rule REJECTS (`ambient.py`).
Note the question is bigger than the design says: for an enclosing *skolem* the
conservative rule alone is not enough — the enclosing signature's row FACTS would also
have to enter `Q`, or the check would falsely reject. Recommendation: ship conservative
(rigid) and, when a wanted mentions a variable that is neither this call's skolem/`Bound`
nor body-minted, emit NO VERDICT rather than a rejection.

## 4. Lean vs `sigcheck.py` vs the S3 Scala: the same algorithm? Not the third one

* **Lean `sigDecide`** enumerates every assignment over `vs ⊇ voc (Q ++ W)` (F-bits
  included), and for each `Q_l`-model searches all F-assignments. `stepOk_iff` is proved
  both ways and the congruences it uses are the right ones. No dedup, no propagation, no
  budget: an honest specification, and the file says so.
* **`sigcheck.py`** = the same criterion plus one-hot propagation, dedup, and budgets. The
  outer loop enumerates only over `R`, which is equivalent because its own `F` rule forces
  `F ∩ voc(Q) = ∅` (see F1). **The dedup is sound**: the inner question frees every F-bit
  regardless of `b`, and `bmodels_congr` on `W` says it depends on `b` only through
  `voc(W) \ F = vars(W) ∩ R` — exactly the projection used as the key. Two `Q`-models with
  the same projection cannot differ in "F-freedom". Empirically: 0 disagreements against
  exhaustive enumeration on 303 of 309 corpus groups (the other 6 exceed 2^22) and on
  36,000 random systems (5 seeds), and 0 disagreements against `indep.py`, a plain DPLL I
  wrote with no propagation rules, no dedup and no budget, on **all 309** groups including
  the six big ones (`{ACCEPT: 288, REJECT: 21}`).
* **The S3 Scala is a third algorithm, and nothing connects it to the criterion.** Item 2
  says "lift `Constraints.decideLabel` to take a frozen partial assignment and a model
  callback"; that lifted search is neither proved (the Lean theorems are about `sigDecide`)
  nor differentially tested (the checklist has no such item), and its input type does not
  match the models: `RHS(abstr: Set[TypeVar], concr: Fields)` (Constraints.scala:347)
  loses repeated parts and merges concrete parts, while `Part.apply` deliberately leaves a
  constraint with two OVERLAPPING concrete parts unmerged (Type.scala:427-429) and can
  build a constraint with a CONCRETE left-hand side (:421-424). Neither `Constraint`
  (Lean: `lhs : Var`, one `conc`) nor `sigcheck.py` (`parse_constraint` returns `None` and
  the record is silently counted as `bad`) can express either. Corpus today: 0 repeated
  parts, 0 constraints with ≥2 concrete parts, 0 concrete left-hand sides, 25 constraints
  of the benign `r <- (r, x)` shape (handled correctly by both models). So these are latent
  cases — but a merge would turn an UNSATISFIABLE constraint into a satisfiable one, which
  flips verdicts in both directions. See F3.
* **The budget branch.** "Warn + accept" matches the `rowSound` precedent and is acceptable
  for a check that is `off` by default, but the checklist does not say where the budget
  lives (per class? per signature?), that a REJECT at one class must outrank a NO VERDICT
  at another, or what to do when the (a2) satisfiability call itself returns
  `LabelNoVerdict` — in which case "not entailed" may not be claimed at all. Nothing in
  the corpus comes near exhaustion: max 24,109 propagation steps
  (`Algebra.Signatures.runningTotalFullViaWritten`, 248 models), then 16,374
  (`Wide.Helpers.withDerived3`), median 53, p90 508, 99,133 over all 309 decisions. But
  `rowSoundBudget` is 200,000 (Constraints.scala:1275), so the headroom at the maximum is
  **8x, not "two orders of magnitude"**, and the two numbers count different things
  (sigcheck's queue pops vs `decideLabel`'s decision nodes). See F5.

## 5. The five new `Time/Helpers.e` rejections: REAL, and S1's triage has a bug

Real, and documented in the source before anyone measured it. `RUnion2 t r s =
exists ro so rs. t <- (ro,so,rs), r <- (ro,rs), s <- (so,rs)` (`modules/Constraint.e:7`);
`dateDiff`/`dateDiff_Op` carries `RUnion2 out r r1`, and `dayCount : forall r r1 out.
Field r Date -> Field r1 Date -> Op out Int` declares NO constraint. The probe's records
are exactly `out <- (ro,so,rs)`, `r <- (ro,rs)`, `r1 <- (so,rs)` with `ro/so/rs` minted, so
at any label `r = 1, out = 0` is a rigid assignment no F-choice extends (`r = so⊕rs = 1`
forces `out ≥ 1`). `Time/Helpers.e:287-293` says the hole is deliberate and names the
one-line fix. `daysSince`/`daysUntil`/`monthsSince` are the two-wanted variant, same
mechanism; `yearFrac365Simple` is accepted because its wanteds share ONE minted variable.

**Why S1 missed them — a bug in `sigentail-entail.py`, not a judgement call.** I ran the
triage and instrumented it: all five groups classify every wanted as `b`, so no group ever
reached the `UNSURE` bucket and no human looked (`grep` of the triage output: 0 hits for
all five names; 20 groups flagged in total). The branch is lines 109-115: when a wanted has
two or more unforced free parts, the tool computes `known` = the union of the *non-free*
parts and returns `b` if `known ⊆ X`. With no givens, `known = ∅` and every wanted passes
in isolation — the shared-choice requirement the survey's own prose insists on ("the choice
is made ONCE for the whole set") is enforced only by the single-unknown forcing fixpoint,
which cannot fire here. The tool's stated KNOWN LIMITATIONS (first-given decomposition,
no disjointness chains) both claim to push hits into the hand-checked bucket; **this third
limitation silently pushes them into `b`**. S1's (c) list is five signatures short, exactly
as the design says.

**My own `sigcheck.py` run** (designer's `corpus-warn`, 161 outputs):
`signatures decided: 309 {'ACCEPT': 288, 'REJECT': 21}`, `propagation steps max 24109
median 53 p90 508; Q-models at one label max 256 median 4; label classes max 7`. The 21
names are byte-identical to the designer's `verdicts.txt`. All four pins reject at their
literal `health` class with the empty witness; `Report.Relation.others` rejects at
`cutoffChild`; the other 16 in the generic class. `rf2.py` and `sigentail-agg.py` reproduce
the design's tables (1490 hits / 912 row obligations / 309 signatures, vars max 44,
|R| max 32, |F| max 28, labels max 6, 293 with no literal label).

## 6. Eight more (b) samples, all ACCEPT

Across buckets C/D/G, none of them checked by the designer:
`Relation.filterEq` (C), `Relation.firstBy` (C/D), `Relation.joinWithDefault` (C),
`Relation.copyColumn` (D), `Relation.leftJoinOr` (D), `Relation.nearestDate` (C, |F| = 12),
`Relation.Row.except` (C), `Layout.Report.pivotTabular` (G). All eight ACCEPT, and all
eight also accept under my independent DPLL. Hand-derived: `copyColumn`, givens
`ro <- (r1,r2,t)`, `ri <- (r1,t)`, wanteds `ro <- (a,b,c)`, `ri <- (d,r1)`, `r2 <- (a,b)`,
`ri <- (a,c)`; take `a = (||)`, `b = r2`, `c = ri`, `d = t` — `ro = r2 ⊎ ri` is the given
`ro` and every disjointness comes from the given's pairwise disjointness. Matches S1's
sample 7 argument and the procedure's verdict.

## 7. Lean hygiene: clean

```
lake build Rowpartition.SigEntail   -> success (786 jobs), EXIT=0
lake build Rowpartition             -> success (870 jobs), EXIT=0   (unchanged)
lake env lean Audit.lean            -> 4613 theorems audited; 0 non-standard axioms
lake env lean $S2/AuditSig.lean     -> 4670 theorems audited; 0 non-standard axioms
```

0 `sorry`, 0 `native_decide`, 0 `partial`, 0 `unsafe`, 0 `axiom`, 46 named theorems
(`grep -c '^theorem '`) — the audit's +57 is those plus auto-generated equation lemmas, all
axiom-clean. One cosmetic linter warning, the only one attributable to the new file:
`SigEntail.lean:548:31: This simp argument is unused`. No hypothesis in the module is
unused in a way that weakens a statement (`hfsk`/`hXsk`/`hz`/`hzv` are all consumed;
`hls`'s equality could be relaxed to `⊆` but only costs generality, not soundness), and no
main theorem is stated over a narrower system type than the procedure needs — `Q`, `W` are
arbitrary `List Constraint`, `F` an arbitrary `Finset Var`, and `Fv.toFinset` loses nothing.
The bucket A/E closed forms are single-constraint by design and labelled as such.
`Corpus`: I re-decided all six systems with two independent engines and got the same
verdicts as the `by decide` proofs (sig01/sig02/keyed REJECT, c08/tagged/joinKey ACCEPT).

## 8. The edit list

**F1 (must, §(a), §(b3)).** Restate `R`/`F` as the oracle implements them:
`R = vars(Q) ∪ {v ∈ vars(W) : v.ty ∈ {Skolem, Bound}} ∪ ambient`, `F = vars(W) \ R`; add
`F ∩ voc(Q) = ∅` as a standing invariant (it is what makes the witness still model `Q`, and
what makes (b3) step 4 well defined); say explicitly that rigidity is read off the
variable's FLAVOUR, never off this call's `sks` list, with the `Lang.Helpers.withRunning`
nested site as the reason. Decide open question 2 in the same edit (recommend: conservative,
plus NO VERDICT for a wanted variable of unknown provenance).

**F2 (must, §(a3), §(b5), checklist 8).** Replace the `Bound`-widening rationale with the
`Forall.mk` (Type.scala:373) argument — a dangling `Bound` cannot appear in any wanted, so
`W = ps.filter(mentions R) = rs` provably, and the widening adds nothing. Then treat the
gap that remains: residuals mentioning NO rigid variable are dropped, and they can pin `F`
variables that `W` uses. Witness (`cases.py`): `ps = {sk <- (f1,f2), f1 <- (f3), f2 <- (f3)}`
— the design's `W` ACCEPTS, the full `ps` REJECTS (the dropped pair forces `f1 = f2 = f3`,
hence `sk = ∅`). Either include all of `ps` in `W` or state why dropping is legitimate
(that both `subsumeType` callers discard `ds` is the honest reason, and it is a weaker
claim than "entailed"). Note that the probe prints `rs` only, so the 17-signature
acceptance criterion is valid **for `W = rs`**; widening `W` requires widening the probe
and re-running the oracle.

**F3 (must, checklist 2 and 6).** Add: (i) a differential property test of the shipped
engine against exhaustive enumeration on small random systems — the Lean theorems cover
`sigDecide`, not the lifted `decideLabel`; (ii) the encoding contract: `RHS.abstr` is a
`Set`, so a repeated part must be normalised to "that variable is empty", `RHS.concr`
merges concrete parts, and a constraint with ≥2 overlapping concrete parts
(Type.scala:427-429) or a concrete left-hand side (:421-424) must yield NO VERDICT rather
than be merged. Corpus counts are 0/0/0 today, so this is about not shipping a silent
unsoundness.

**F4 (should, §(a2), checklist 1).** Spell out the vacuous-givens path: `labelDecide` on
`Q` alone, on the rejecting path only, with which budget, and — the missing case — what
happens when it returns `LabelNoVerdict` (then neither "not entailed" nor "no solution" may
be claimed: degrade to a warning). Add the sentence that `labelDecide`'s `r.concr`-only
label set is correct HERE (all-empty rows satisfy any label-free partition system) even
though the entailment classes need the synthetic label.

**F5 (should, §(b3)/(b4)/(d2)).** Budget semantics: per class or per signature; REJECT at
one class outranks NO VERDICT at another; and restate the headroom honestly — 24,109
propagation steps at the corpus maximum against `rowSoundBudget = 200000` decision nodes is
8x in mismatched units, to be re-measured with the engine's own counter in S3.

**F6 (minor, checklist 7).** Drop "`sig03`'s position is `32:12`, not `20:12`": S1 already
fixed both the pin header and `shouldfail/RESULTS.md:225`; the stale item sends the
implementer hunting.

**F7 (minor, §(d1)).** The evidence for deleting `:548-549` must not be the `.ei` diff: an
`.ei` diff cannot observe a lost `die`, and `entails → bySuper/byInst` can raise
"Unknown class" (Subst.scala:299/307). The real argument is that a row `Part` has no `Con`
head so `unfurlApp` returns `None`, plus my grep showing no test or example anywhere
expects that message. Or simply keep the loop: it is pure and costs nothing.

**F8 (minor, §(d2)).** Say that the suffix scheme works because `Session.scala:472` tests
`key contains interfaceKey`, so the suffix must be APPENDED (an `.ei` written under `error`
then stays valid under `off`, and an `off`-written one is rebuilt under `error` — exactly
the wanted asymmetry), and that `TestInterfaceKey`'s `notInKey` list (:151-152) needs the
new flag as well as the property at :157.

**F9 (minor, checklist 5).** The session option must also replace the global
`SigEntail.warn` guards at `Subst.scala:547` and at the two `Site` allocations
(`:652`, `:670`), or the fixture cannot run anything under `error`.

**F10 (minor, §(a3)/(b5)).** Counts: the batch sweep has 37,264 row-obligation records
(`varcount.py`'s own total agrees), not 36,328 — say which sweep the number comes from. And
"12 signatures with NO row givens" is 12 ACCEPTED of 23 such signatures (`qsat.py`); the
other 11 are rejections.

## 9. S3 checklist gaps, in one list

Beyond F3/F4/F5/F9: (1) nothing says how `qs`/`ps` (`Type`) become the engine's
`(TypeVar, RHS)` input — the single largest unwritten piece of work; (2) the witness→prose
step of (d3) ("take a column in BOTH `key` and `fb`") is specified by example only, with no
rule for turning a bit-model into that sentence — ask for one worked message per rejection
class (a pin, a generic-class stdlib case, an `(a4)` ignored-given case); (3) `sigcheck.py`
is named the oracle in prose but not in the checklist — commit it with the expected
21-name list as a test resource; (4) item 6 says flip the four KNOWN HOLE properties to
`no(...)`, but `sig05`'s is a `Prop.throws`, which needs its own shape; (5) nothing says
the check must run on the `qs`/`ps` captured at `:539-541` and never on a re-substituted
copy (the invariant (a1) depends on).

## 10. Open questions: my answers

1. **The five `Time/` holes** — fix them. The file names the fix (`RUnion2 out r r1`), F3
   measured that it loads the whole group, and shipping a checker that cannot load its own
   example corpus under `error` is worse than a one-line follow-up.
2. **Ambient metas** — conservative, and decided now (F1); the corpus is silent by
   construction (0 bare-`Free` variables in any wanted), so "measure later" cannot answer it.
3. **Per-model vs uniform** — a line in the JSON-API note is right; today's compiler
   discards `pxs` at `:551`, so per-model is sound and strictly more permissive.
4. **`warn` vs `error` as default** — `warn`, on 17 signatures with 7 in the stdlib; and
   note that under `error` a NO VERDICT still accepts, so `error` is not a guarantee.
5. **The let drop** — a separate ticket; `sig03` stays a pin with its own explanation.
6. **Class constraints stay with generalisation** — agreed, and the judgement is row-only
   by construction (`sigcheck.py` drops non-`Part` givens; 578 of 1490 hits are class
   constraints).
