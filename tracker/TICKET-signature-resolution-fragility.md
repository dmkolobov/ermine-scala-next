# Whether a published signature is RESOLVED is order-fragile (2026-09-02)

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
