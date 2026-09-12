# SIG-2: the signature-entailment check, designed -- the GENERAL case, with the Lean proof

Stage S2 of `tracker/SIG-ENTAIL-PLAN.md`, worktree `ermine-scala-wt-sig`, branch
`sig-entail` (from `5fa512a`). DESIGN plus a Lean statement and proof; no compiler code
changed (`git status`: one new file, `tracker/lean/Rowpartition/SigEntail.lean`). Input:
`SIG-1-SURVEY.md` (912 row obligations in 309 signatures) and `SIG-1-REVIEW.md` (the A-G
taxonomy: the refutation trick reaches 4.7%; the other 95.3% are partitions of variables
alone), so this stage designs the GENERAL procedure.

REVISED after the review (`SIG-2-REVIEW.md`, verdict FIX-THEN-ADVANCE). The corrections are
folded in and attributed: `R`/`F` restated as the oracle implements them and ambient metas
decided (F1, §(a)); the `Bound` widening dropped for the `Forall.mk` theorem and the real
`ds` gap closed by a closure (F2, §(a3)); the differential test and the `Part`-shape
encoding contract made stage items (F3, (e) 2a/2b); the vacuous path's third verdict (F4,
§(a2)); budget semantics and the honest headroom (F5, §(b3)/(b4)); the `:548-549` loop KEPT
(F7, §(d1)); the interface-key asymmetry (F8, §(d2)); the session option replacing the
global guards (F9, (e) 5); counts corrected (F10). The mathematics is unchanged and the
Lean module is byte-identical to the reviewed version.

## Verdict

The judgement decomposes PER LABEL -- one small 2QBF per label class, the existential over
the minted variables chosen label by label -- soundly without hypotheses and completely
whenever the signature's givens are satisfiable. Both halves are proved in Lean
(`sigEntails_iff_forall_label`), where the procedure is also executable (`sigDecide`, sound
and complete). Run on the whole S1 corpus it decides all 309 signatures with no budget
exhaustion and rejects **21**: S1's twelve (c) holes, the four pins, and **five new ones**
(`Time/Helpers.e`'s documented unconstrained-result-row family, which S1's triage put in
(b)). 288 accept, including all four spellings of `control08`, `ok5`, and every (b) sample.

Reproduce (one JVM, two Python passes, one Lean build):

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  tracker/tools/corpus-run.sh --batch $OUT/corpus-warn   # 159 outputs, exit 0
tracker/tools/sigentail-agg.py $OUT/corpus-warn          # 1490 hits, 912 row obligations
python3 $SCRATCH/sigcheck.py  $OUT/corpus-warn           # THE PROCEDURE: 288 ACCEPT / 21 REJECT
python3 $SCRATCH/rf2.py       $OUT/corpus-warn           # the |R|/|F|/label-class numbers
cd tracker/lean && lake build Rowpartition.SigEntail && lake env lean $SCRATCH/AuditSig.lean
```

`sigcheck.py` (the procedure) and `rf2.py` are in this stage's scratch
(`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S2/`),
worth committing with S3 as the expected-verdict oracle; `AuditSig.lean` is
`Audit.lean` plus `import Rowpartition.SigEntail`. (This batch sweep reports 1490 unique
hits / 912 row obligations / 309 signatures against S1's per-file 1502 / 914 / 308: +2 for
the `sig05` pin added after S1, the rest the per-file-vs-batch difference S1 §3 describes.
No verdict below depends on it.)

## (a) The judgement, fixed

At a `subsumeType(declared, inferred, Some(site))` call (`Subst.scala:534`) on a declared
`forall xs. Q => T`: `sks` are its universals `xs` as skolems (`:535`); `qs` the givens with
existentials opened as `qxs` (`:538-539`); `ps` the body's residual with existentials opened
as `pxs` (`:540`); `rs` the elements of `ps` mentioning a skolem (`:541`). Write **Q** for
the `Part`-shaped elements of `qs` ((a4) for the rest), **W** for the obligations,
**R**/**F** for the rigid/existential variables:

    F = { v ∈ vars(W) | v is SOLVER-MINTED IN THIS BODY'S RESIDUAL } \ vars(Q)
        = vars(W) ∩ pxs  \  vars(Q)                          (the closed form S3 computes)
    R = ( vars(Q) ∪ vars(W) ) \ F
    W = the closure of rs under shared F variables within ps  (= rs on this corpus; see (a3))

**The signature is honest iff**

    for every rho with rho ⊨ Q, there is rho' agreeing with rho off F such that rho' ⊨ W.

Rigid variables are UNIVERSALLY quantified (the caller instantiates them), `F` is chosen
per model. In Lean: `SigEntail.SigEntails Q W F` (SigEntail.lean §2).

**`F ∩ voc(Q) = ∅` is a standing invariant, not a convenience** (reviewer F1): it is what
keeps the witness `rho'` a model of `Q` -- move a variable of `Q` and "extend a model of the
givens" means nothing -- and what makes (b3) step 4's "models of `Q_l` over `R`" well
defined. Everything in `Q` is rigid by definition, an ambient meta included.

**Rigidity is read off the variable's FLAVOUR and its membership in `Q`, never off this
call's `sks` list.** `vars(W) ∩ pxs` is the positive form (`pxs` is what
`unbindExists(Free, substType(pz))` minted at `:540` for THIS residual); the form to assert
in a test is that every variable of `W` outside `pxs` has `v.ty ∈ {Skolem, Bound}` or occurs
in `Q` -- measured, the wanteds' flavour histogram is `{S: 64426, A: 58370}`, no bare `Free`
at all. Deriving rigidity from `sks` would be UNSOUND: an ENCLOSING signature's skolem is in
none of `sks`/`qxs`/`Bound`, so it would land in `F` and be CHOSEN, accepting a dishonest
signature. Nested signed bindings do reach this call (`inferBindingGroupTypes` `:780` runs
`typeCheckExplicitBinding` for every `let`/`where` explicit binding, and S1 §6's probe P6
shows a `where` signature reaching the checker; `Lang.Helpers.withRunning`,
`Lang/Helpers.e:485`, is the sweep's signed binding with a nested group, benign because all
its variables are its own), and the corpus cannot exonerate the `sks` formula either way
because the probe prints no `sks` list.

**Ambient metas and foreign skolems: CONSERVATIVE, decided here (was open question 2).**
Anything in `W` outside `pxs` is rigid -- an ambient meta of an enclosing group, an
enclosing signature's skolem, either. The permissive rule (any non-skolem is choosable)
differs on `W = { m <- (r, f) }`, `m` ambient, `f` minted: permissive ACCEPTS, conservative
REJECTS (reviewer's `ambient.py`). Ship conservative: an ambient meta is pinned once by the
enclosing solve, so choosing it per model is optimistic in exactly the direction that
accepts a dishonest signature. Two riders. (i) The corpus cannot tell the rules apart (no
bare `Free` in any wanted), so this is a decision, not a measurement -- **the user may
relax it** after S4, whose editor path carries a much richer ambient environment; the
measurement to take there is the per-site flavour histogram of `vars(W) \ (pxs ∪ vars(Q))`
under `warn`. (ii) A FOREIGN SKOLEM (`v.ty == Skolem`, `v ∉ sks`, `v ∉ vars(Q)`) can make
the conservative reading FALSELY REJECT, because the enclosing signature's row facts are not
in `Q`; so `sks` is used for one thing only -- if the refuting model assigns such a
variable the verdict degrades to NO VERDICT (warn, accept), leaving nested sites at S1's
status quo instead of noisy.

The existential over `F` is per-model rather than one substitution for all models because
rows carry no runtime evidence: nothing in the compiled body depends on which row a minted
variable denotes, so this is the WEAKEST sound requirement, and it is what keeps
`control08` accepted. The solver's answer is stronger -- one row EXPRESSION per minted
variable -- and implies it (`sigEntails_of_uniform`), so a derivational check can only be
incomplete for this judgement, never unsound for it ((b6), open question 3).

### (a1) Q's own existentials (`exists c. a <- (b, c)` in `Has`): RIGID

`Has r h = exists c. r <- (h, c)` (`Constraint.e:5`). Decision: `qxs` joins `R`.

* **Semantically** the witness is chosen by whoever satisfied the context, not by the body.
  Read the other way the check would accept `Has r ((|health|)) => ...` for a body needing
  `r <- ((|health|))` exactly -- pick `c = (||)` -- and a caller passing `{health, position}`
  then runs a body type-checked at the wrong row.
* **Structurally the two readings cannot differ here**: `qxs` is minted fresh at `:539` and
  `pxs` at `:540`, so no wanted can mention a given's witness. Measured: of the 309
  signatures **0** have a given-existential in a wanted (`Relation.firstBy`'s given is
  `r <- (c^471996A, h)`, its wanted `h <- (c^472001A, h)` -- a DIFFERENT variable, which
  resolves S1 §8 item 5b; `SIG-1-REVIEW.md`'s (b) argument #3, "take `c = (||)`", is about
  the wanted's own existential and is legitimate).
* **In Lean**: `sigEntails_hidden_iff` -- the universal and the chosen reading
  (`SigEntailsEx`) AGREE whenever no wanted mentions the variable, so the cheap
  implementation (`qxs` as just more rigid variables) is provably right here.

### (a2) Unsatisfiable givens: accept the judgement, but never in silence

If `Q` has no model the judgement is vacuously true, so the check must not reject "because
the body is wrong". But the per-label reading is then STRICTLY STRONGER than the judgement
(Lean: `lsig_stronger_of_unsat`, transported from `Basic.Counterexample`), so the procedure
may accept or reject unpredictably. Rule: run the procedure; if it accepts, done (no
satisfiability check, no cost). If it reports a failing class, decide `Q`'s satisfiability
ONCE -- `Constraints.labelDecide(Q, rowSoundBudget, rowSoundSolveBudget)`, the machinery
`Subst.solve:1453` already uses -- and branch on all THREE of its verdicts:

| `labelDecide` on `Q` alone | what is reported |
|---|---|
| `LabelSat` | "not entailed", with the witness ((d3)) -- error under `error`, warning under `warn` |
| `LabelRefuted` | *"the signature's constraints have no solution: no call can satisfy them"* -- error under `error`, warning under `warn`; the body is NOT blamed |
| `LabelNoVerdict` | NEITHER claim may be made: one warning naming the field and the reason, and the signature is ACCEPTED (the (b3) step-5 rule) |

A vacuous context is always a bug, and blaming the body for it is the failure mode
`labelCheckEarly` was declined for on 2026-09-01; claiming it on a no-verdict would be the
same error twice. Cost is zero on the accepting path; the sweep has no such signature (the
reviewer measured it: 0 of 309 have a label class with no model of `Q`), so the branch is
policy, not throughput -- and the oracle should ASSERT that rather than remark it.

One thing that looks like a bug here and is not: `labelDecide`'s label set is
`ps.foldLeft(...)(_ ++ r.concr)` (`Constraints.scala:2717`), i.e. the mentioned labels only,
with no synthetic generic label, so a label-free `Q` comes back `LabelSat`. That is CORRECT
for satisfiability -- the all-empty assignment models every partition system with no
concrete part, so unsatisfiability of a partition system is always visible at a concrete
label -- while the ENTAILMENT classes of (b2) genuinely need the synthetic label. The two
label sets differ for a reason.

### (a3) The `Bound` flavour is rigid -- and what `W` really has to contain

`Forall.mk` keeps only binders that occur in the BODY (`nts = typeVars(b).filter(tm)`,
`Type.scala:373`), so a variable occurring only in the constraint survives as a dangling
`Bound`: `sig02`'s own given is `r^1479755S <- ((|mana|), t^1476568B)`, and 17,487 of the
37,264 row-obligation records in this sweep have a `Bound` in the givens. It is RIGID (a
universal whose binder was dropped; its witness is determined by the partition it sits in --
`Determined.lean`'s `cancelAdd` clause).

**And no wanted can ever mention one -- a theorem, not a corpus accident** (reviewer F2):
such a variable occurs only in `q`, never in the declared type's body `b`, so the one
`unifyType(r1, r2)` in `subsumeType` (`:537`) cannot introduce it into the inferred
residual, and the measured 0 of 37,264 follows. So `ps.filter(mentions R) = rs` exactly:
the widening an earlier draft asked for catches nothing, is dropped, and would have violated
the very hypothesis `sigEntails_hidden_iff` needs ("no wanted mentions them").

**The real gap is the other half of the partition at `:541`.** A residual that mentions no
rigid variable goes to `ds`, and it can still PIN an `F` variable that `W` uses. The
reviewer's witness: `ps = { sk <- (f1, f2), f1 <- (f3), f2 <- (f3) }` with `sk` rigid and
`f1, f2, f3` minted. `rs` is the first constraint alone, which the procedure ACCEPTS
(`f1 := sk`, `f2 := ∅`); all of `ps` REJECTS, because the two dropped constraints force
`f1 = f2 = f3` and hence `sk = ∅`. Decision: **`W` is the closure of `rs` under shared `F`
variables within `ps`** -- start from `rs`, repeatedly add any element of `ps` sharing an `F`
variable with the set (union-find over `F`, one pass, `O(|ps| · |vars|)`). Not all of `ps`:
a `ds` component sharing no `F` variable with any obligation constrains nothing the
signature is responsible for, and one that is unsatisfiable on its own is the enclosing
solve's diagnostic, not this signature's. The closure is strictly STRONGER than `W = rs`
(more constraints, more `F` variables), so it can only reject more.

**Corpus status of the closure, exactly.** The probe prints `rs` only, so the closure is
invisible in the S1 data: every printed record mentions a skolem, so the closure over the
printed set IS the printed set. Re-run with the closure wired in
(`scratchpad/S2/sigcheck-closure.py`) the oracle reproduces `{ACCEPT: 288, REJECT: 21}` and
the same 21 names -- by construction, not as evidence. The 17-signature criterion of (e) is
therefore valid **for `W = rs`**; S3 must add the `ds` half to the probe record (one more
tab-separated column, rendered like the givens), re-run with the closure and re-state the
criterion. A verdict that moves is a new (c) item and a stop point, not a bug.

### (a4) Unexpanded aliases and constraints the check cannot read

`unbind` (`:535`) runs `substAlias` (`Subst.scala:117`) on the type, so an alias that IS in
scope arrives expanded: `control08.healthHas`'s `Has r ((|health|))` reaches the check as
`r^584045S <- ((|health|), c^584047A)`. Nothing to do for that case.

An alias NOT in scope is closed over as an ordinary type variable and applied:
`DrilldownList.e` has no `import Constraint` and its givens arrive as
`((Has^435209B rout^435579S) r^435578S)` -- genuinely VACUOUS. Decision: the check reads only
`Part`-shaped givens (after `substType`, stripping `Memory`) and drops the rest, which is
right for class constraints and for this -- **but the message must list what it ignored**,
and when an ignored given is an application headed by a type VARIABLE it must say so
("`(Has rout f1)` constrains no row here: `Has` is not in scope -- did you forget
`import Constraint`?"), or `cons_Bracket`'s rejection is unreadable. One diagnostic the
survey did not ask for, and cheap: the classification is syntactic.

## (b) The decision procedure
### (b1) The per-label decomposition, and why the choice for F per label is legitimate

A partition is label-wise: `v <- (p1..pk)` says that for EVERY label `l`, `l ∈ v` iff `l` is
in exactly one `pi`. So at one label the system becomes a Boolean formula over the membership
bits and the judgement becomes, per label, *for every bit-vector `b` of the R-bits with
`b ⊨ Q_l` there are F-bits making `b' ⊨ W_l`* -- a 2QBF (Lean: `BSigStep`, and
`LSigEntails` for all labels).

* **Sound, unconditionally** (`sigEntails_of_lsig`) -- the crux. Rows are ARBITRARY finite
  label sets, so the label-by-label choices for `F` glue into ONE row assignment:
  `rho' v = { l ∈ span | beta_l v }` for `v ∈ F` and `rho v` elsewhere, where
  `span = concLabels(Q ++ W) ∪ (voc(Q ++ W)).biUnion rho`. The gluing must be FINITE, and
  outside `span` the all-false choice already models `W` (`bmodels_false_of_not_mem`) --
  which is why the witness is a `Finset.filter` over `span`. `Q` need not be satisfiable.
* **Complete when `Q` is satisfiable** (`lsig_of_sigEntails`), by
  `entails_iff_forall_label`'s method (`Basic.lean:525`): splice the bit-vector into a model
  of `Q` at that label (`exists_splice`), apply the judgement, project back. Not removable -- (a2).

### (b2) Label classes: the mentioned labels, and ONE generic label

The per-label problem reads the label only through the concrete parts (`bsat_label_congr`),
so labels in the same concrete sets give the SAME problem. Hence: one class per label
mentioned literally in `Q` or `W`, plus ONE class standing for every label mentioned
nowhere (`lsig_iff_classes`, with `l₀ ∉ concLabels (Q ++ W)`).

Measured over the 309 signatures: at most **6** literal labels, so at most **7** classes --
and **293 of 309 mention no literal label at all**, i.e. the whole check is ONE generic
class, which is where 16 of the 21 rejections are decided. That class is also exactly what
the refutation trick cannot see (`Q + {sk' <- (sk, X)}` unsatisfiable decides "X meets sk in
every model", a statement about literal labels), and `Constraints.labelDecide` visits only
`r.concr` labels: **S3 must add the synthetic generic label; reusing `labelDecide`'s label
set alone decides nothing on 95% of the corpus.**

### (b3) The algorithm

Per signature, once. (1) **Normalise** the givens: `substType`, strip `Memory`, keep
`Part`s, classify the rest ((a4)) and apply (e) 2b's shape rules; build `W` as (a3)'s
closure; split the variables into `R`/`F` by (a)'s rule -- flavour plus membership in `Q`,
never this call's `sks`. (2) **Label
classes**: `concLabels(Q ++ W)` plus one fresh label ((b2)). (3) **Per class** build the
Boolean problem: each partition gives `lhs = OR(parts)` and `at-most-one(parts)`, each
concrete part's bit fixed by the class. (4) **Decide the 2QBF** by search with unit
propagation -- `Constraints.propagate`'s five one-hot rules verbatim
(`Constraints.scala:2816-2865`): enumerate the models of `Q_l` over `R`, deduplicated on
their projection to `vars(W) ∩ R`, and for each freeze the `R`-bits and ask whether `W_l`
is satisfiable with the `F`-bits free, by the same search (`decideLabel`, `:2755`).
(5) **Verdicts**: all classes pass -> accept; a `Q_l`-model that no `F`-choice extends ->
reject, carrying (class, model, the first unsatisfied wanted); budget exhausted -> NO
VERDICT, which must warn and accept, never silently accept (`Subst.solve:1470`'s `rowSound`
no-verdict line is the precedent and the wording).

**Budget semantics** (reviewer F5). Two caps mirroring
`rowSoundBudget`/`rowSoundSolveBudget`: one per LABEL CLASS, one per SIGNATURE capping the
sum so a wide signature cannot spend `#classes ×` the first. Every class is decided before
anything is reported, and **a REJECT at one class outranks a NO VERDICT at another** (a
refutation at any class refutes the judgement, `lsig_iff_classes`); NO VERDICT is reported
only when no class rejected and one was left undecided. A rejection whose witness assigns a
foreign skolem also degrades to NO VERDICT ((a)), and step 1's normaliser has its own NO
VERDICT cases ((e) 2b). Step 1 computes `W` as (a3)'s closure from `rs` and `ds` together;
the engine sees one obligation set and does not care which half a constraint came from.

### (b4) Complexity, and what the corpus actually costs

Worst case the per-class problem is Pi-2 complete in the bit vocabulary (the at-most-one
constraints encode exact cover), and naive enumeration is `2^|R| x 2^|F|` per class. The
corpus, from `rf2.py` (per signature, deduplicated, row obligations only):

| | max | mean | median | p90 |
|---|---|---|---|---|
| variables per signature | **44** (`Wide.Signatures.melt3Full`) | 8.6 | 7 | 16 |
| `\|R\|` (rigid) | 32 | 5.2 | 4 | 9 |
| `\|F\|` (minted) | 28 (`Wide.Helpers.melt4`) | 3.5 | 2 | 9 |
| row wanteds | 24 | 3.0 | 2 | 6 |
| literal labels | 6 | 0.1 | 0 | 0 |

So **enumeration is not an option at the tail** (`2^26 x 2^18` for `melt3Full`): propagation
is not a nicety. With it, over all 309 decisions: **propagation steps max 24,109, median 53,
p90 508; models of `Q` at one label max 256, median 4; label classes max 7.** The one-hot
structure does it -- a whole that is 0 forces every part to 0, a part that is 1 forces the
whole to 1 and its siblings to 0 -- so most bits are forced, not searched. The headroom,
honestly (reviewer F5): the maximum is 24,109 propagation POPS
(`Algebra.Signatures.runningTotalFullViaWritten`, 248 models; then 16,374 for
`Wide.Helpers.withDerived3`; 99,133 over all 309 decisions) against
`GenRules.rowSoundBudget = 200,000` DECISION NODES (`Constraints.scala:1275`) -- about 8x,
in units that do not match, since a decision node is a case split and a pop is a
propagation step. S3 must re-measure with `decideLabel`'s own counter before fixing the
default; that measurement is an S3 acceptance item, not a design claim.

### (b5) The worked evaluation

Verdicts below are MEASURED by `sigcheck.py` (the procedure of (b3) on the S1 records); the
witness column is the counterexample it printed, translated back into rows, and "class" is
the label class that decided it.

**Must reject -- the pins.** All four decided at the literal label `health`; all four are
bucket A, so the refutation trick would also decide them.

| case | Q | W | class | witness | verdict |
|---|---|---|---|---|---|
| `sig01.healthOpt` | (none) | `r^S <- ((\|health\|), _^A)` | `health` | every row empty | **REJECT** |
| `sig02.wrongLabel` | `r^S <- ((\|mana\|), t^B)` | `r^S <- ((\|health\|), _^A)` | `health` | `r = {mana}` | **REJECT** |
| `sig04.bump` | (none) | `r^S <- ((\|health\|), t^A)` | `health` | every row empty | **REJECT** |
| `sig05.<annot>` (`ann` site) | (none) | `r^S <- ((\|health\|), _^A)` | `health` | every row empty | **REJECT** |

**Must accept -- `control08`'s four spellings and `ok5`** (run separately; not in
`corpus-run.sh`'s globs). All five ACCEPT.

| spelling | Q | W | why it passes |
|---|---|---|---|
| `healthWith` | `r <- ((\|health\|), t^B)` | `r <- ((\|health\|), _^A)` | `_ := t` |
| `healthHas` | `r <- ((\|health\|), c^A)` (Q's existential) | `r <- ((\|health\|), _^A)` | `_ := c`; (a1) makes `c` rigid and it does not matter |
| `bumpWith` | `r <- ((\|health\|), t^B)` | `r <- ((\|health\|), t'^A)` | `t' := t` |
| `tagged` | `t <- ((\|health\|), r)` | identical | the wanted IS the given, `F = ∅` |
| `ok5` (`ann`) | `r <- ((\|health\|), t^B)` | `r <- ((\|health\|), _^A)` | as `healthWith` |
| `localWith` (let) | -- | -- | **no obligation reaches the check**: the renamer drops let signatures (S1 §6), so this spelling tests nothing -- open question 5 |

**Must reject -- all twelve (c) items of S1.** Every one is rejected, eleven of them in the
GENERIC class (16 of the 21 rejections overall; the other five are at a literal label).

| # | signature | class | the procedure's witness |
|---|---|---|---|
| c1 | `Relation.UnifyFields.unify1` | generic | a label in `f1` alone (`f1` is in no given) |
| c2 | `Relation.partialLookup` | generic | a label in `base^B` and `val` at once -> `W` has no model |
| c3 | `DrilldownList.cons_Bracket` | generic | a label in `rout` and in none of `f1`, `f2`, `r` (the three `Has` givens are vacuous, (a4)) |
| c4 | `Report.Keyed.softRelation` | generic | a label in both `k` and `v` -> `o' <- (k, v)` has no model |
| c5 | `Report.Keyed.keyValueTabular` | generic | a label in `r2` alone (`i`, `v`, `k` unconstrained) |
| c6 | `Report.Relation.cutoffs` | generic | a label in `v` -> `r'' <- (r, v)` with `v ⊆ r` given |
| c7 | `Report.Relation.others` | `cutoffChild` | `cutoffChild ∈ r`: the dual shape, bucket E |
| c8a-d | `Wide.Helpers.melt2`/`melt3`/`melt4`, `Wide.Signatures.melt3Simple` | generic | a label in both `key` and `fb` (same mechanism in all four) |
| c9 | `Algebra.Signatures.runningTotalFullViaWritten` | generic | a label in `a` (`ord`) alone, in none of the 21 givens |

**Must accept -- (b) samples across buckets C, D and G.** All accept; five of them:

| S1 (b) # | signature | bucket | Q | W | witness the procedure found |
|---|---|---|---|---|---|
| 5 | `Relation.join1` | C | `r <- (k, r1^B, r2^B)`, `ra <- (k, r1)`, `rb <- (k, r2)` | `r <- (_1,_2,_3)`, `ra <- (_1,_2)`, `rb <- (_2,_3)` | `_1 := r1`, `_2 := k`, `_3 := r2` |
| 15 | `Relation.Scan.groupBy'` | C | `r <- (h, t^B)` | `r <- (_1,_2)`, `r <- (_0,_1,_2)`, `h <- (_0,_1)`, `r <- (h,c)` | `_0 := ∅` forced, `_1 := h`, `_2 := c := t` |
| 8/9 | `Relation.leafRows` | D | `r <- (parent, child, t^B)` | six, incl. `r <- (child, c)`, `parent <- (parent, _)` | `c := parent+t`, `_ := ∅` |
| 14 | `Relation.Row.spanT` | D | `r <- (h, t)` | `r <- (t', h)`, `r <- (t,h)` | `t' := t` |
| 20 | `Report.SoftRelation.joinKey` | G | `r <- (i, k, v)` | `t' <- (v, i)`, `r <- (k, t')` | `t' := v+i`, one choice for both wanteds |

Samples 19 (`Tree.fromRel`) and 16 (`Sort.reorderSome`) also accept; `joinKey` is in the
Lean kernel as `Corpus.joinKey_entailed`.

**Five signatures the procedure rejects that S1's triage put in (b)**, all in the generic
class, all with the witness "a label in `out` and in neither operand row":
`Time.Helpers.dayCount`, `.monthsBetween`, `.monthsSince`, `.daysSince`, `.daysUntil`. They
are a real finding, not a false positive -- `Time/Helpers.e:287-294` says so in as many
words: *"THE SIGNATURE BELOW STILL REPEATS THE
HOLE, deliberately: `forall out` is accepted for this body ... Tightening it to
`RUnion2 out r r1 => ...` was measured in F3 to load the whole `Time/` group cleanly."* The
obligations are `out <- (ro, so, rs)`, `r <- (ro, rs)`, `r1 <- (so, rs)` with `ro`/`so`/`rs`
minted -- `out = r ∪ r1` -- so with `out` unconstrained a label of `out` outside both
operands breaks it. The procedure rediscovered a hole a human had already written down, and
**S1's (c) list is five signatures short**: 17 signatures (7 stdlib + 10 example), which is
the S3 acceptance criterion **for `W = rs`** -- (a3) says what re-stating it under the
closure costs.

**Cases the procedure cannot decide: none on this corpus** -- 309 of 309 decided, 0 budget
exhaustions. Two caveats about the DATA, not the procedure: obligations that never reach
`rs` are invisible to the probe (the `Bound`-only ones of (a3) -- measured 0), and class
constraints are out of scope (S1 §8 item 6; they are checked at generalisation, `:389`).

**Robustness.** The riskiest accepts are the 12 ACCEPTED signatures with NO row givens (of
23 such; the other 11 reject), where acceptance demands the wanteds hold at EVERY assignment
of the rigid rows: all twelve were re-derived by hand, and `yearFrac365Simple` is the
instructive one -- `dayCount`'s sibling, ACCEPTED because its wanteds share one minted
variable rather than the two that make `out = r ∪ r1`. Four systems are decided twice, by
the Lean kernel (`by decide`) and by the sweep, and agree. The reviewer then re-decided all
309 with two engines of his own (exhaustive enumeration on 303, a plain DPLL on all 309) and
36,000 random differential trials: **0 disagreements**, and the 288/21/0 split reproduced
(`SIG-2-REVIEW.md` §4-§6, which also adds eight more (b) samples, all ACCEPT).

### (b6) The derivational alternative, and why the semantic procedure wins

A derivational check would run the solver on `Q`, add `W` with `F` fresh and ask whether the
solve closes without minting outside the input's vocabulary -- a UNIFORM witness: one row
expression per minted variable, good for every model (`UniformSigEntails`). Three reasons
the semantic procedure wins. **Completeness**: a uniform witness implies the judgement
(`sigEntails_of_uniform`), not conversely, and the solver is not complete for derivability
anyway -- a saturating loop whose termination on satisfiable input needed two guards
(`KeyedSplit`, `KeyedRow`) and which still diverges on some unsatisfiable input
(`ResGuardDiverge`, `DefaultSatDiverge`), so a check built on it inherits each gap as a
spurious rejection or a hang inside `subsumeType`. **Blame**: the semantic procedure fails
with a MODEL ("take `key` and `fb` to share a column"), which is what (d3) prints; a
derivational failure produces a stuck queue. **Cost**: (b4)'s median 53 propagation steps
against a second solve that mutates a `Supply` and a `SubstEnv`. The solver is still used
for ONE thing -- `Q`'s satisfiability on the rejecting path (a2).

## (c) The Lean statement and proof

New module `tracker/lean/Rowpartition/SigEntail.lean`, 796 lines, **46 named theorems**,
0 `sorry`, 0 custom axioms, no `native_decide`/`partial`/`unsafe`. The only Lean file this
stage creates or edits: `Rowpartition.lean` is NOT touched, so the import is the
orchestrator's edit (S3 checklist item 9).

```
$ cd tracker/lean && lake build Rowpartition.SigEntail  # success (786 jobs)
$ lake build Rowpartition Rowpartition.SigEntail        # success (871 jobs)
$ lake env lean Audit.lean                              # 4613 theorems audited; 0 non-standard axioms
$ lake env lean $SCRATCH/AuditSig.lean                  # 4670 theorems audited; 0 non-standard axioms
```
(This worktree had no `.lake`: `packages` is symlinked to the main checkout's -- the two
`tracker/lean` trees are byte-identical -- over a private copy of `build`, so nothing was
written into another tree. No `lake exe cache get`, no new project.)

| § | theorem | what it says |
|---|---|---|
| 1 | `mem_voc`(+3), `models_congr`, `bsat_congr`, `bmodels_congr`, `bsat_label_congr`, `bmodels_class_congr`, `sameClass_of_not_mem` | `Sat`/`BSat` read only the variables they mention, and the label only through the concrete parts |
| 2 | `AgreeOff`, `SigEntails`, `BAgreeOff`, `BSigStep`, `LSigEntails` (defs) | the judgement and its per-label reading |
| 3 | **`sigEntails_of_lsig`** | **SOUNDNESS of the per-label procedure, unconditional** -- the per-label choices for `F` glue into one finite row assignment (the crux) |
| 3 | **`lsig_of_sigEntails`** | **COMPLETENESS, given `Q` satisfiable** (`exists_splice`, `entails_iff_forall_label`'s method) |
| 3 | **`sigEntails_iff_forall_label`**, `lsig_stronger_of_unsat` | the decomposition, both halves; and the satisfiability hypothesis is not removable ((a2)) |
| 4 | `bsigStep_class_congr`, **`lsig_iff_classes`** | finitely many label classes: the mentioned labels plus ONE generic label |
| 5 | `SigEntailsEx` (def), **`sigEntails_hidden_iff`** | the givens' existentials and the dangling `Bound`s may be read rigid or chosen -- they agree when no wanted mentions them ((a1), (a3)) |
| 6 | `Holds`, `Avoids` (defs), **`sigEntails_bucketA_iff`**, **`sigEntails_bucketE_iff`** | closed forms for `sk <- ((\|K\|), f)` and for the dual `X <- ((\|K\|), sk)` |
| 6 | `holds_iff_unsat`, `avoids_iff_unsat` | "every model puts `l` in `v`" IS unsatisfiability of `Q` plus one constraint over a fresh variable (`Fresh`, `models_of_agree`, the `ConservativeExt` shape of `Rules.lean:412`) |
| 6 | **`sigEntails_bucketA_iff_refute`**, `sigEntails_bucketE_iff_refute` | **the refutation trick is a correct decision for bucket A** (the brief's (ii)) and for E |
| 7 | `subst`, `UniformSigEntails` (defs), `sigEntails_of_uniform` | a uniform witness suffices: the derivational check is sound for the judgement ((b6)) |
| 7 | `bmodelsB_iff`, `exists_bassign`, **`stepOk_iff`**, **`sigDecide_iff`** | the EXECUTABLE procedure decides the per-label judgement |
| 7 | **`sigEntails_of_sigDecide`** / **`not_sigEntails_of_sigDecide`** | acceptance is sound with no hypothesis on `Q`; rejection is sound provided `Q` has a model |
| 8 | `sig01_*`, `sig02_*` (+`sig02_sat`), `keyed_*` / `c08_*`, `tagged_*`, `joinKey_*` | the three rejections and the three acceptances, `by decide` on `sigDecide` (the brief's (iii)) |

The fix round changed no Lean statement: `Q`, `W` are arbitrary `List Constraint` and `F` an
arbitrary `Finset Var`, so (a)'s corrected `R`/`F` and (a3)'s closure change only what the
CALLER puts in them, and `Basic.Sat.eq_empty_of_dup` already licenses (e) 2b's one
normalisation. The module is byte-identical to the reviewed version.

`Corpus.keyed_*` is `Keyed.softRelation` (no concrete label anywhere: the GENERIC class
rejects it) and `Corpus.joinKey_*` is `SoftRelation.joinKey` (two wanteds sharing one minted
variable, accepted in the generic class) -- in the kernel because they are the shapes no
refutation-shaped procedure reaches. Per the `decide` memory note the instances use the
`Constraint` constructor, not `Divergence.mk`, so no `Finset.sort` reduces.

## (d) Where it runs, and the blame
### (d1) Placement

Inside `subsumeType`, one new call after the `ds`/`rs` partition:

```
  541    val (ds, rs)  = ps.partition(p => Type.fskvs(p).isEmpty)
  547    <the S1 probe, under `warn`>                      548-9  for (r <- rs) entails(qs,r)
  NEW    sig.foreach(s => SigEntail.check(s, qs, ps, rs, sks, pxs, hm))  -- (a)'s judgement
  550-3  restrictTypes(qxs) / restrictTypes(pxs) / restrictKinds(tks) / restrictTypes(tts)
  566    (q, mkSimplified(pz.loc, pxs, ds))               -- UNCHANGED
```

* **Before `restrictTypes` (`:550-553`)**: those lines delete substitution entries
  (`hm.types = hm.types -- xs`, `:153`) that `substType` on a wanted still needs, and the
  skolems must still be visible. The probe already sits there and S1's gates showed the
  position inert under `off`.
* **`entails(qs, r)` at `:548-549`: KEEP IT.** It is class-only (`entails` `:313`, `entail`
  `:394` gated on `isClassConstraint`) and its Boolean is discarded, so it is not the new
  check's business -- but deleting it is not free and an `.ei` diff cannot prove that it is:
  an `.ei` diff cannot observe a lost `die` (reviewer F7). `entails` walks the GIVENS
  through `bySuper`, which dies "Unknown class" when a class in `qs` is not in `hm.classes`
  (`:299`, `:307`); the WANTED half cannot die (a row `Part` has no `Con` head, so
  `unfurlApp` returns `None` and both `bySuper` and `byInst` return empty). The loop is pure
  and costs nothing, no test expects the message from this site, and the same `entails` runs
  on the same givens at generalisation (`:389`): so leave the two lines exactly as they are
  and add the new check beside them. S3 then has no behaviour to defend here at all.
* **`mkSimplified` at `:566` and `ds` are untouched**: the check reads, never rewrites, and
  `W` is computed from `ps` ((a3)) precisely so `ds` need not move.
* **Only where a `Site` is present**: `typeCheck` `:651` (`ann`), `typeCheckExplicitBinding`
  `:669` (`sig`). The `App` case `:936` passes `None` and must keep doing so;
  `typeCheckPattern` `:992` is dead. `TolerantCheck.scala:669` calls
  `typeCheckExplicitBinding` and inherits the check -- that is S4.

### (d2) The flag

`off` (default) | `warn` | `error`, read once (`SigEntail.mode`, `SigEntail.scala:29`).

| point | `off` | `warn` | `error` |
|---|---|---|---|
| `Site` allocation `:651`/`:669`; the check | none; not run | as today; run | as today; run |
| a rejection | -- | one `warning:` line, load continues | `tml.die` with the (d3) message |
| NO VERDICT (budget) | -- | `warning:` | `warning:`, then ACCEPT -- never a silent pass, never a false reject |
| unsatisfiable `Q` | -- | warning, (a2) wording | error, (a2) wording |

**The interface key must distinguish `error`.** `error` can change what is published (by
refusing), so a stale `.ei` written under `off` would hide the diagnostic on the next run.
Recommendation: APPEND `|sigEntail=error` to `Session.interfaceKey` (`Session.scala:167`)
only when the mode is `error`. The asymmetry that makes appending (rather than replacing)
right is that the staleness test is `key contains interfaceKey` (`Session.scala:472`): an
`.ei` written under `error` carries the suffix and so still matches under `off`, while one
written under `off` does not contain the `error` key and is rebuilt -- exactly the direction
wanted, and the 129-file baseline stays byte-identical under the default. Two test edits
come with it: `TestInterfaceKey`'s "key is `<format version>|<GenRules>`" property (`:157`)
must allow the suffix, and `notInKey` (`:151-152`) must gain `sigentail` so that nobody
later puts the flag into `GenRules` -- whose `toString` is the key's second half, where a
new field would invalidate every cached interface (`Constraints.scala:1569`).

### (d3) The message and the two locations

```
Wide/Helpers.e:325:10: the signature does not entail this row constraint
    wanted   t <- (fb, s)             (s is the solver's own and may be anything)
    given    out <- (i, key, val);  r <- (i, fa, fb)
  no rows satisfying the givens satisfy it: take a column in BOTH key and fb -- the
    givens never make those two disjoint             <- the witness, from (b3) step 5
  ignored given  (Has rout f1): an application of a type VARIABLE, which constrains no
    row here -- is `Constraint` imported?             <- only when (a4) applies
  declared at Wide/Helpers.e:318:1
```

* **PRIMARY location**: the wanted's own `Loc` (every element of `rs` carries one; the
  probe prints it) WHEN it is in the file being compiled. A large share of wanteds carry a
  builtin or another module's position (S1 §8 item 7), and an error whose only position is
  in the stdlib is the failure mode `labelCheckEarly` was declined for on 2026-09-01. Reuse
  `Subst.solve`'s `rowUnsat` (`Subst.scala:1343-1380`) verbatim: `file(tml.loc) orElse
  file(l)` decides "here", candidates are the constraints located here, prefer the one whose
  left-hand variable the witness refutes, else the first, else the signature;
  `sourcePosition` (`:873`) strips `Inferred` so no message ends in "inferred from". When
  the wanted's location is NOT here, the primary becomes the signature and the foreign
  position is quoted in the body ("required by the use of `-` at `Layout/Format.e:21:14`").
* **SECONDARY, "declared at"**: `binding.v.loc` for `sig`, `e.loc` for `ann` -- both within
  `SigEntail.Site`'s reach (`siteOf`/`siteAt`, `SigEntail.scala:39-48`); S3 widens `Site` to
  carry the `Loc`. The givens print as the check READ them, ignored ones listed separately
  ((a4)), through `SigEntail.render` (`SigEntail.scala:118`) -- `Pretty.prettyType` restarts
  its letter supply per call and would name two different variables `a` in the two columns.

## (e) The S3 implementation checklist

**Code**
1. `SigEntail.scala`: add `error` to the mode; add
   `check(site, qs, ps, rs, sks, pxs, hm)` returning
   `Ok | NotEntailed(class, model, wanted, ignoredGivens) | VacuousGivens | NoVerdict(why)`;
   the R/F rule of (a) (flavour + membership in `Q`, `pxs` for the positive form, `sks` only
   for foreign-skolem provenance); the `W` closure of (a3); the normaliser of (a4) and 2b;
   (d3)'s messages; the (a2) branch on all three `labelDecide` verdicts.
2. **The engine, and the two things nothing yet connects.** Do not write a second per-label
   search: lift `Constraints.decideLabel` (`:2755-2900`) to take a frozen partial assignment
   and a model callback, and to accept a synthetic label outside `r.concr` ((b2));
   `labelDecide`'s budget/no-verdict plumbing (`DecideResult`, `LabelNoVerdict`) is reused
   as is. Two gaps the implementer must NOT be left to decide (reviewer F3):
   **2a. A DIFFERENTIAL TEST is part of the stage, in `core/test`.** The Lean theorems are
   about `sigDecide`; the lifted `decideLabel` adds dedup, propagation and budgets. Pin it
   both ways: (i) over the 309 corpus signatures the shipped engine must agree with the
   committed oracle -- ship `sigcheck.py` and its 21-name expected list as a test resource;
   (ii) a ScalaCheck property over small random systems (≤ 5 variables, ≤ 4 constraints,
   ≤ 2 labels) against exhaustive enumeration, which is `sigDecide`'s own definition. The
   reviewer ran 36,000 such trials against the oracle with 0 disagreements: that is the bar,
   now against the SCALA.
   **2b. The encoding contract, because `Type` is wider than the model.** `RHS(abstr:
   Set[TypeVar], concr: Fields)` (`Constraints.scala:347`) loses a REPEATED part and MERGES
   concrete parts, while `Part.apply` deliberately leaves a partition with two OVERLAPPING
   concrete parts unmerged (`Type.scala:427-429`, the final `case _`) and can build a
   CONCRETE left-hand side (`:421-424`). Neither Lean's `Constraint` (one `lhs : Var`, one
   `conc`) nor `sigcheck.py` can express either shape. Rules:
   * a repeated variable part is NORMALISED to "that variable is empty" and deduped;
     verdict-preserving, and the theorem is already in the kernel
     (`Basic.Sat.eq_empty_of_dup`);
   * `≥ 2` concrete parts, or a concrete left-hand side: **NO VERDICT** with a named reason,
     never silently merged -- merging two DISJOINT concrete parts is verdict-preserving on
     paper but cannot even be STATED inside the verified model (`Constraint` has one `conc`
     field), and merging OVERLAPPING ones turns an unsatisfiable partition into a satisfiable
     one, flipping verdicts both ways.
   Corpus today: 0 repeated parts, 0 partitions with ≥2 concrete parts, 0 concrete left-hand
   sides, 25 of the benign `r <- (r, x)` shape (both models express it). This is about not
   shipping a silent unsoundness, not about a case that fires.
   **2c.** The conversion `qs`/`ps` (`Type`) -> the engine's `(TypeVar, RHS)` input is the
   stage's largest unwritten piece of work (reviewer §9), and is where 2b lives.
3. `Subst.scala`: one new call after the `:541` partition, per (d1); `:548-549` left alone;
   `:566` and `ds` untouched.
4. `Session.scala:167` + `TestInterfaceKey` (`:151-152`, `:157`) per (d2).
5. The flag must be settable PER SESSION or the suite cannot test it: `SessionEnv`
   (`SessionState.scala:95-121`) already carries `_typeCheck`/`_useInterface`/
   `_foreignTolerant` as `Option`s defaulting from a system property -- add `_sigEntail`
   the same way, pass it through `Session.subst` (`Session.scala:59`,
   `new SubstEnv(s.classes)`) into `SubstEnv` (`Subst.scala:93`) and read `hm.sigEntail`.
   That is the plan's "fixture session-option mechanism": `ErmineFixture(prepBaseEnv = ...)`
   sets it with no `System.setProperty` (`TestInterfaceKey.withProps` cannot help -- it
   flips properties AFTER the read-once vals are forced). **The session option must also
   REPLACE the three global `SigEntail.warn` guards** -- `Subst.scala:547` and the two
   `Site` allocations at `:652` and `:670` -- or the fixture can set the option and still
   get no `Site`, hence no check (reviewer F9).
6. The check must read the `qs`/`ps` captured at `:539-541` and never a re-`substType`d
   copy: (a1)'s freshness invariant (no wanted can name a given's existential) holds because
   those lists are taken after the only `unifyType` in `subsumeType`, and S4's editor path
   is where a later substitution could break it.

**Tests and pins to flip**
7. `TestSigEntail.scala`: the three `typeChecks` KNOWN HOLE properties (`:36`, `:40`, `:45`)
   become `no(...)`, and the ANNOTATION one (`:52`) is a `Prop.throws` and needs its own
   shape -- under `error` the module must be REFUSED, so it becomes a `no(typeChecks(...))`
   (or a `throws` of the checker's own failure), not a no-throw; all four run under a second
   fixture with the session option `error`; keep the four controls; the let-bound property
   (`:67`) keeps its comment that it pins inference, not the hole.
8. `shouldfail/sig0{1,2,4,5}_*.e` headers and `shouldfail/RESULTS.md` (§"Pinned, class 6")
   to "rejected" with (d3)'s message.
9. **The corpus criterion is this report's 17-signature list, not S1's 12** (and it is the
   list for `W = rs`, (a3)): under `error` the sweep must reject exactly `unify1`,
   `partialLookup`, `cons_Bracket`, `Keyed.softRelation`, `Keyed.keyValueTabular`,
   `Relation.cutoffs`, `Relation.others`, `melt2/3/4`, `melt3Simple`,
   `runningTotalFullViaWritten`, `dayCount`, `monthsBetween`, `monthsSince`, `daysSince`,
   `daysUntil`, plus the four pins.
10. One WORKED MESSAGE per rejection class in the stage's report, not just (d3)'s schema: a
    pin (literal label, empty witness), a generic-class stdlib case (`Keyed.softRelation`),
    an (a4) ignored-given case (`cons_Bracket`), a foreign-skolem NO VERDICT. The
    witness -> prose rule: name the label class, then the variables the refuting model sets
    to 1, in the source's own names.
11. `tracker/lean/Rowpartition.lean`: add `import Rowpartition.SigEntail` (orchestrator, not
    implementer), then `lake build Rowpartition` + `Audit.lean` green with the new theorems
    inside the audit.
12. The probe gains the `ds` column (a3) so the closure can be measured, and the oracle
    asserts that every signature's `Q` is satisfiable (§(a2)).
13. Gates: Tier 1 (`Subst` changes). `.ei` diff under `off` empty; `off`-vs-`warn` still
    byte-identical; `repl-smoke.sh` with the WORKTREE classpath (`tracker/repl-classpath.txt`
    holds absolute paths into the main checkout -- S1 review §5).

## Open questions for the user

The reviewer answered all six; where the answer is a decision this design can take, it is
taken above and recorded here. Two are still the user's.

1. **The five new holes -- STILL YOURS.** `Time/Helpers.e`'s `dayCount`/`monthsBetween`/
   `monthsSince`/`daysSince`/`daysUntil` are rejected and the file calls the hole deliberate
   ("left as a one-line follow-up"). Reviewer: FIX them -- the file names the fix
   (`RUnion2 out r r1`), F3 measured that it loads the whole `Time/` group, and shipping a
   checker that cannot load its own example corpus under `error` is worse. Alternative: keep
   them and accept that `Time/` does not load under `error`.
2. **Ambient metas -- DECIDED (conservative), see (a).** The corpus is silent by
   construction (no bare-`Free` variable occurs in any wanted), so "measure later" could
   not answer it; the decision is rigid-for-everything-not-minted-here, with NO VERDICT for
   a foreign skolem. You may relax it after S4's measurement.
3. **Per-model versus uniform witnesses.** Sound under row ERASURE -- `subsumeType` discards
   `pxs` at `:551`, so per-model is sound and strictly more permissive. If a feature ever
   makes a row expression observable at runtime (the JSON API's reflective serialiser), the
   uniform reading becomes right and the check stricter: a line in the JSON-API note.
4. **`warn` versus `error` as the default -- STILL YOURS (S5's question).** The rejected
   population is 17 signatures, 7 of them stdlib: S1's decision with a bigger numerator.
   Reviewer's recommendation: `warn`, and note that under `error` a NO VERDICT still
   accepts, so `error` is not a guarantee.
5. **The let-signature drop.** A separate ticket (`rename/Lower.scala:185-187`, `:298-299`);
   `sig03` stays a pin with its own explanation. Fixing the drop before S3 lands turns
   `sig03` from a rejection into an acceptance.
6. **Class constraints stay with generalisation** (`Subst.scala:389`, where they ARE
   checked): agreed, and the judgement is row-only by construction -- the check drops every
   non-`Part` given, and 578 of the 1490 hits are class constraints.
