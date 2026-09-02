# CONFIRMED DEFECT: build order decides a published type

**STATUS 2026-09-02, EVENING: REINSTATED. The deciding experiment has now been RUN and it
comes back POSITIVE.** The headline claim was retracted earlier the same day because its
stated premise was false; the defect is real, the mechanism is different from the one first
proposed, and it reproduces under DEFAULT FLAGS with no experimental flag involved.

## The defect, in one experiment

Same compiler. Same flags (all defaults). Same source. The only thing that varies is which
`.ei` files happen to be on disk when the module is compiled:

    A. nothing on disk beforehand              -> labelled : Builtin.Relation (|..9 fields..|)
    B. after one HelloWorld boot (130 .ei)     -> labelled : Builtin.Relation (|..9 fields..|)
    C. after the sweep's own prefix (141 .ei)  -> labelled : forall t. (exists ..) => Relation t

`Ai/HeadcountPlan.labelled` publishes a RESOLVED CONCRETE ROW or a CONSTRAINED POLYMORPHIC
type depending on nothing but build order. Deterministic and reproducible in both directions.

## What triggers it, narrowed

Bisecting the prefix: the flip appears when `Ai/IncidentSeverity.e` is compiled first.
`IncidentSeverity` is unrelated to `HeadcountPlan` -- but compiling it PUBLISHES four interfaces
that `HeadcountPlan` does import (`Layout/Report/Keyed{,/Options,/OptionTypes,/Syntax}`), and
from then on those are READ instead of re-derived from source:

    full flipping state (137 .ei)          -> poly
    minus the 4 Layout/Report/Keyed*.ei    -> CONCRETE
    minus IncidentSeverity.ei only         -> poly          (IncidentSeverity is irrelevant)

Deleting any single one of `Keyed.ei`, `Keyed/OptionTypes.ei` or `Keyed/Syntax.ei` restores
the concrete answer; deleting `Keyed/Options.ei` alone does not.

**So the statement of the defect is: compiling a module against its dependencies' PUBLISHED
INTERFACES yields a different, less resolved type than compiling it against their SOURCE.**
Since `ermine.useInterface` defaults TRUE, this is the shipped configuration.

## Why this matters more than the original framing

The first write-up guessed at ordering inside the solver. The mechanism is upstream of that:
information is lost when an interface is PUBLISHED, and the loss is user-visible in the next
module's signature. That is the defect proved in Lean as
`Rowpartition/Splice.lean : DroppedPartition.dropped_can_lose` -- ticket item 8b -- which was
recorded as a proven-but-possibly-latent defect. **It is not latent.** The 8b repair was
declined on the evidence of an `.ei` diff that showed it degrading signatures; that diff was
itself taken in a build-order-dependent regime, so the decision deserves re-examination.

## A SECOND, INDEPENDENT cause found at the same time

`Ai/BatteryCycling.withHealth` also degrades, but from a different cause -- it bisects
cleanly to `genRules`, from a clean `.ei` state every time:

    today's defaults          -> poly        -Dermine.labelCheck=false  -> poly
    -Dermine.genRules=all     -> CONCRETE    -Dermine.resGuard=false    -> poly
                                             pre-work (all three off)   -> CONCRETE

**The cut costs signature resolution here.** That is a real, previously unrecorded cost of a
decision already taken, and it is NOT caused by `labelCheck` or `resGuard`. Whether it is
acceptable is a judgement call that should be made explicitly rather than by default.

## Still not established -- do not assume either way

* **Are the two forms equivalent?** The constraints in the polymorphic form should force `t`
  to the concrete row. If they do, this is a QUALITY defect; if they do not, a SOUNDNESS one,
  and the priority changes entirely. `Rowpartition/Splice.lean` and `Saturate.lean` have the
  vocabulary. This was step 2 of the original ticket and is still unrun.
* Whether the 8b repair (`Rowpartition/SpliceGuard.lean`, flag deleted in `cb7fab4`) fixes
  the build-order half. Testing it means restoring the flag.
* Whether `HeadcountPlan.withUnitCost` and `RevenueByPeriod.labelled` -- the other two SHAPE
  regressions in the cumulative `.ei` diff -- have the build-order cause or the cut cause.

---

# Superseded write-ups below, retained for their evidence and their errors

The RETRACTION that follows was correct about its own premise being false, and is kept because
the reasoning error it records is worth not repeating. It is no longer the status of the ticket.

It was opened on this reasoning: `Ai/ClinicalTrial.labelled` and `Ai/HeadcountPlan.withUnitCost`
have structurally identical constraint sets, and `-Dermine.spliceGuard=true` flips them in
OPPOSITE directions between a resolved concrete row and an unresolved constrained polymorphic
type — so the outcome must turn on ordering with no semantic content.

**The premise is false.** The two modules are not in the same situation: `labelled` has a
downstream use that pins the row (`renamed = rename armName cohortLabel labelled`),
`withUnitCost` has none (line 62 is its only occurrence). `tracker/repro/` isolates exactly
that: two 15-line modules differing only by a pinning use, publishing the two forms. Once the
premise goes, so does the inference.

**And both observations are fully explained without invoking fragility.**
`-Dermine.spliceGuard=true` suppresses ~90% of splices, so:

* `ClinicalTrial` — the existential is no longer eliminated, the residual really is different,
  and the use no longer pins the row;
* `HeadcountPlan` — the retained constraints pin `t` unaided, with no use needed.

A flag that changes solver behaviour substantially changing published signatures is not a
defect. The flag is DEFAULT OFF and `TICKET-row-solver-8abc.md` recommends it stay off.

**So: no problem has been demonstrated in the shipped compiler.** What follows is kept because
the question is worth settling, not because an answer has been established.

## The experiment that would settle it — NOT YET RUN

Perturb something SEMANTICALLY IRRELEVANT and see whether resolution flips:

* reorder two independent bindings in a source file;
* insert an unrelated definition above them;
* rename a field so `Supply` ids shift.

Then diff the `.ei`. If a published type moves between `Relation (|..|)` and
`forall t. (..) => Relation t` under any of those, the defect is real and this ticket becomes a
defect report. If nothing moves, WITHDRAW it — do not downgrade it, withdraw it. Anything
already known about constraint REORDERING is the pre-existing ten-site inventory in
`TICKET-row-constraint-decision.md` and is not this.

`tracker/repro/MinReproUse.e` is the base to perturb; `tracker/tools/ei-diff.sh` does the
capture (it deletes every `.ei` on both sides, which is mandatory — see
`ROW-CONSTRAINT-STATE.md`).

## What IS established, and is not in dispute

A downstream use at a concrete header pins the row and the published signature becomes
concrete; without one it stays constrained-polymorphic. That is ordinary inference. Whether the
compiler SHOULD resolve `derived` with no use is a design question, not a defect.

---

# Original write-up, retained for its evidence and its errors

Found while diffing `.ei` interfaces for ticket item 8b
(`tracker/TICKET-row-solver-8abc.md`). It is not an 8b defect and it is not fixed by any
change in that ticket.

## The observation

For the same source, the compiler sometimes publishes a fully resolved concrete row and
sometimes an unresolved constrained polymorphic type — and which one you get is decided by
ordering that has no semantic content.

`core/examples/Ai/ClinicalTrial.e`, under two settings of a flag that should not touch it:

    resolved     labelled : Builtin.Relation (|displayName, subjectId, siteId,
                                              subjectRef, armName, siteName|)

    unresolved   labelled : forall (t: rho).
                   (exists (a: rho) (rs: rho) (so: rho).
                      (|displayName|) <- (rs, so),
                      R <- ((|armName, siteName, subjectRef|), a, rs),
                      R <- ((|armName, siteName, subjectRef|), rs, a),
                      t <- ((|armName, siteName, subjectRef|), rs, so, a))
                   => Builtin.Relation t

`core/examples/Ai/HeadcountPlan.e` shows the SAME two forms for `withUnitCost`, with the
two settings swapped — the setting that resolves `ClinicalTrial` leaves `HeadcountPlan`
unresolved, and vice versa. The two constraint sets are structurally identical:

    ClinicalTrial   (|X|) <- (rs, so),  R <- (K, a, rs),  R <- (K, rs, a),  t <- (K, rs, so, a)
    HeadcountPlan   (|Y|) <- (rs, so),  S <- (L, a, rs),  S <- (L, rs, a),  t <- (L, rs, so, a)

Same shape, opposite outcomes. So this is not a semantic property of the flag; it is the
flag perturbing an order the answer happens to depend on.

## The precise claim, and what it is NOT

**It is deterministic.** Two runs with identical inputs produce byte-identical `.ei`
(checked: `ClinicalTrial.ei` twice, `diff` clean). This is not flaky output.

**It is FRAGILE.** A semantically irrelevant perturbation — here, a flag that changes when a
splice fires elsewhere in the same solve — flips whether the type gets resolved. Anything
else that perturbs the same orders (a `Supply` id shift, a new binding earlier in the file,
a stdlib edit upstream, a different module load order) can be expected to do the same.

That distinction matters for the fix: the problem is not "make it deterministic", it already
is. It is "make the answer independent of orders that carry no information".

## Why this is worse than the reordering already on file

`TICKET-row-constraint-decision.md` carries a **ten-site determinism inventory** (search for
"Determinism, against a complete inventory") and treats the symptom as constraint ORDER and
variable NAMING drift inside a signature — cosmetic, and the reason the `.ei` baseline is
compared by multiset. This is the same root cause with a materially worse symptom:

* it changes the **type a user sees and programs against**, not the order of its constraints;
* an unresolved `forall t. (..4 constraints..) => Relation t` propagates — every downstream
  caller now carries the constraints instead of a concrete row;
* it is invisible to a multiset comparison of constraints, because the two forms do not have
  the same constraints at all;
* and it means "the compiler resolved my type" is not a property of the program.

## Reproduction

    tracker/tools/ei-diff.sh /tmp/eidiff "-Dermine.spliceGuard=true"

captures 187 interfaces per side (deleting every `.ei` first, on both sides, so neither
reads the other's — see `ROW-CONSTRAINT-STATE.md` for why that matters) and prints the
content diffs. 18 of 187 differ; `Ai/ClinicalTrial`, `Ai/HeadcountPlan`, `Ai/IncidentSeverity`,
`Ai/GridTelemetry`, `Ai/TelescopeTime` and `Ai/SalesByRegion` are the interesting ones.
The flag is only a convenient perturbation — the defect is not in the flag.

## Where to look

The existing ten-site inventory is the map; these are the sites that plausibly decide THIS
symptom rather than mere ordering:

* **(6) `reduce`'s `abs.toList`** — `Subst.scala`, second case of `def reduce`. The spliced
  variables enter the emitted `Part` in `Set` iteration order.
* **(5) `Part.apply`'s RHS handling** — `Type.scala`. Its smart-constructor collapses
  (`ConcreteRho` tautology, the concrete-LHS flip) fire or not depending on the shape it is
  handed, so the order the RHS arrives in decides whether a constraint collapses to a
  resolved row.
* **`Exists.apply`'s `p.toSet.toList`** — `Type.scala:302`, which fixes the published binder
  and constraint order and is already flagged at `Type.scala:147`.
* **(7) the `Set[Partition]` folds into `++!`** — `Constraints.scala`. `insert` consults
  `rhsLookup` mid-fold, so whichever same-RHS partition lands first wins the
  common-partition unification and gets written into the global substitution. This class is
  immune to a comparator swap and is the most likely candidate for an outcome flip rather
  than an ordering flip.

## Narrowed 2026-09-02: what selects between the two forms

Step 1 below was done, and it corrects the diagnosis above. Both witnesses are one
`combine_Op` — adding a derived column to a relation with a concrete header. Distilled to
15 lines in `tracker/repro/`:

| module | differs by | published type |
|---|---|---|
| `MinRepro.e` | nothing uses `derived` | `forall t. (exists so rs a. ..4 constraints..) => Relation t` |
| `MinReproUse.e` | adds `use : [a,b,c,extra]; use = derived` | `Relation (\|b, a, c, extra\|)` |

**A downstream use at a concrete header pins the row, and the published signature becomes
concrete. Without one it stays constrained-polymorphic.** That rule accounts for the real
modules under the DEFAULT compiler, and it is not a defect — it is ordinary inference:

* `Ai/ClinicalTrial.labelled` is used (`renamed = rename armName cohortLabel labelled`) — resolves;
* `Ai/HeadcountPlan.withUnitCost` is used NOWHERE (line 62 is its only occurrence) — does not.

**So the ticket's opening framing is too strong.** "Same source, two different published
types" is right for the flag comparison, but the two forms are not two orderings of one
computation; one has a pinning use and the other does not. Delete that from the indictment.

**What survives, and is still a defect, is narrower and stranger.** Under
`-Dermine.spliceGuard=true` BOTH witnesses move AGAINST the rule:

* `ClinicalTrial.labelled` has a use and STOPS resolving — the flag broke the pinning;
* `HeadcountPlan.withUnitCost` has no use and STARTS resolving — the solver pinned it
  unaided, which is plausible, since skipping the splice retains constraints that can force
  `t`.

The 15-line reproducers are STABLE under the flag — neither flips. So they isolate the two
forms but do NOT reproduce the fragility, and the first witness for that is still a real
`Ai` module. **Shrinking the FLIP is the next task, and it is what step 1 has left to do.**

The suspected sites also change. Binding-group ordering — inventory site (10),
`Binding.scala`'s Tarjan over hash-ordered maps and `toGamma(m) = m.values.toList` — decides
whether a use is processed before the definition is generalised, which is exactly the
mechanism the reproducers expose. That is a better first suspect than `Part.apply` or
`reduce`'s `abs.toList`.

## What is needed, in order

1. **PARTLY DONE — see above.** The two published forms are isolated in `tracker/repro/`
   and the selector is a downstream pinning use. What remains is a minimal witness for the
   FLIP: take `MinReproUse.e` (a use, resolves) and find the smallest addition that makes
   `-Dermine.spliceGuard=true` break the pinning, as it does in `ClinicalTrial`. Start by
   adding a SECOND `combine_Op` and a second use, since both real witnesses sit in modules
   with several interacting derived relations and the reproducer has exactly one.
2. **Decide whether resolving is even the preferred answer.** Both forms are believed
   equivalent — the constraints in the unresolved form should force `t` to the concrete row.
   That is worth CHECKING rather than assuming: if they are equivalent, this is a quality
   defect; if they are not, it is a soundness one, and that changes its priority entirely.
   `Rowpartition/Splice.lean` and `Rowpartition/Saturate.lean` have the vocabulary.
3. **Then** apply the inventory's prescribed fix — a rank assigned by first occurrence in a
   left-to-right walk of the constraint list `solve` receives, with minted variables ranked
   after all input variables in mint order. The inventory is explicit that source `Loc` is
   NOT available for this (`refresh` makes it non-injective across instantiations).

## What this ticket is not

Not a request to rewrite the solver. The ten-site inventory estimates 600-900 lines of
ordering work and is a prerequisite for every proposed design; this ticket adds one fact to
it — that the payoff includes signature QUALITY and not only byte-stability — and one
reproduction that makes the symptom visible without a baseline to diff against.
