# Why does the redundant partition cost a Substitution?

Continue the Ermine row-solver work on branch `scala3-migration`. One specific
mechanism question is open. Everything else from 2026-09-02 is committed.

## Method (unchanged, and it is the point)

Lean leads, code follows. Our own reasoning is not trustworthy here — several
confident claims on 2026-09-02 were wrong and were caught only by measurement.
So: state the property a change relies on, prove it in `tracker/lean/Rowpartition/`,
and only then touch `Constraints.scala` or `Subst.scala`. If a property resists
proof, that is evidence about the design — report it and reconsider, rather than
shipping and hoping. Prefer proving a negative (a counterexample, a non-existence)
over asserting a limitation.

`tracker/lean/README.md` is the per-theorem authority for the existing
formalisation — **verify its claims rather than trusting them.**

## What is established (do not re-derive; do re-verify if you rely on it)

`Ai/HeadcountPlan.labelled` publishes either a resolved concrete row or a
constrained polymorphic type, decided by BUILD ORDER alone — same compiler, same
flags, same source, differing only in which `.ei` are on disk. Committed in
`751d4f2`; written up in `tracker/TICKET-signature-resolution-fragility.md`
(REINSTATED as a confirmed defect) and in the Gates section of
`tracker/TICKET-row-solver-8abc.md`.

It is a QUALITY defect, not a soundness one — settled twice in `753491d`.
Empirically, a consumer annotated at the exact 9-field header is ACCEPTED while
one field missing or one extra is REJECTED. By proof,
`Rowpartition/DerivedColumn.lean : t_determined_of_sat` shows the three published
constraints force `rho t = insert d K`, needing neither `L ⊆ K` nor `d ∉ K` nor
the `Pairwise Disjoint` halves of its hypotheses. Audit: 1469 theorems, 0
non-standard axioms.

So the constraint set ENTAILS the concrete row and the rule set does not DERIVE
it. The solver is incomplete here, which is expected — `cut` bought termination
by giving up completeness. **The open question is the precise mechanism.**

## The question

Row-tracing both regimes at the module-level solve gives:

    A  concrete  rows=3  in=5  sat=13  derived=7   CommonSubexpression:2, SplitConcrete:2, Substitution:3
    B  poly      rows=4  in=7  sat=12  derived=6   CommonSubexpression:2, SplitConcrete:2, Substitution:2

Two facts, both from the trace:

* **B receives a redundant constraint.** Arities `[2;3;3;4]` against A's `[2;3;4]`.
  The extra arity-3 is the duplicate visible in the published signature itself:
  `K <- (L, a, rs)` and `K <- (L, rs, a)` — the same partition, right-hand side in
  a different order.
* **B is exactly one `Substitution` short.** Both fire `CommonSubexpression:2` and
  `SplitConcrete:2`. That third substitution is what pins `t`.

**Does the redundant partition cause the missing Substitution, or is it a symptom
of something upstream?** That is the whole task.

## One guess already refuted, and the live hypothesis

REFUTED — do not spend time here. "Dedup fails because the RHS orderings differ."
`Constraints.scala:325` has `case class RHS(abstr: Set[TypeVar], concr: Fields)`,
so both orderings become the same `RHS`, and `rhsLookup` (`Constraints.scala:482`)
compares `p._2 == rhs`, which is order-insensitive. Note `Type.scala:385` has
`class Part(val loc, val lhs, val rhs: List[Type])` — the List lives in the Type
representation that is published to and parsed back from `.ei`, not in the solver.

LIVE, and only a hypothesis — test it, do not assume it. `Constraints.scala:778`
has `case class Partition(_1: TypeVar, _2: RHS, inf: Option[Inference])`, a case
class whose equality includes its PROVENANCE. `insert` (`Constraints.scala:~490-518`)
skips a partition only when `leq any (p == _)`. Two partitions with identical
`_1` and `_2` but different `inf` are therefore unequal and BOTH survive. If that
is what happens, the redundancy is real and self-inflicted.

Other candidates worth ruling in or out rather than ignoring: the `Set[Partition]`
folds into `++!` (site 7 of the determinism inventory), and `Part.apply`'s smart
constructor in `Type.scala` (site 5), whose collapses fire or not depending on the
shape it is handed.

## Reproduction

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
    STDLIB=core/target/scala-3.3.8/classes/modules

    # CONCRETE regime — dependencies re-derived from source
    find core/examples $STDLIB -name '*.ei' -delete
    bin/ermine core/examples/Ai/Common.e core/examples/Ai/HeadcountPlan.e </dev/null
    grep '^labelled' core/examples/Ai/HeadcountPlan.ei      # -> Builtin.Relation (|..9 fields..|)

    # POLY regime — the Layout/Report/Keyed* interfaces exist and are read
    find core/examples $STDLIB -name '*.ei' -delete
    bin/ermine core/examples/Accumulate.e </dev/null
    bin/ermine core/examples/Ai/Common.e core/examples/Ai/ClinicalTrial.e </dev/null
    bin/ermine core/examples/Ai/Common.e core/examples/Ai/IncidentSeverity.e </dev/null
    rm -f core/examples/Ai/HeadcountPlan.ei
    bin/ermine core/examples/Ai/Common.e core/examples/Ai/HeadcountPlan.e </dev/null
    grep '^labelled' core/examples/Ai/HeadcountPlan.ei      # -> forall (t: rho). ...

`IncidentSeverity` is not a dependency of `HeadcountPlan`; compiling it merely PUBLISHES
`Layout/Report/Keyed{,/Options,/OptionTypes,/Syntax}.ei`, which `HeadcountPlan`
does import. Deleting any one of `Keyed.ei`, `Keyed/OptionTypes.ei` or
`Keyed/Syntax.ei` from the flipping state restores the concrete answer; deleting
`Keyed/Options.ei` alone does not. **Try to shorten the recipe** — running only
`IncidentSeverity` then `HeadcountPlan` may suffice, but that was not verified.

Tracing:

    ERMINE_JAVA_OPTS="-Dermine.rowTrace=/tmp/tr.tsv" bin/ermine <files> </dev/null
    awk -F'\t' '/^solve/ && $3 ~ /HeadcountPlan.e\(1:1\)/ && $4+0>0 \
      {printf "rows=%s in=%s sat=%s derived=%s arities=[%s] rules=%s\n",$4,$5,$6,$7,$9,$10}' /tmp/tr.tsv

Columns are `solve, site, loc, rows, inParts, saturated, derived, concrete,
arities, byRule` — see the `RowTrace.log` block in `Subst.scala` (~line 1125).
`RowTrace` is inert unless the property is set.

## What a good answer looks like

1. A DECIDED mechanism: either the duplicate causes the missing Substitution, or
   it does not and something else does. Evidence, not argument.
2. If the duplicate is the cause: the ten-site determinism inventory in
   `TICKET-row-constraint-decision.md` currently treats right-hand-side ORDER as
   cosmetic — that claim would need updating, and that is a real result about a
   document several decisions rest on.
3. A minimal reproducer. Put it in `tracker/repro/`, **NOT** under
   `core/examples/`, which has a hard-coded corpus count in `TestSurfaceParsers`.
4. Whatever is proved, proved in `tracker/lean/Rowpartition/`.

Fixing the incompleteness is NOT the task. Identifying the mechanism is. If a fix
turns out to be small and licensed by a proof, propose it behind a flag defaulting
off, with measurements — do not adopt it.

## Method rules that cost time on 2026-09-02

* **Always run the EXAMPLES, not just the stdlib.** stdlib is minimal, especially
  for concrete rowtype usage: `resolution` fires on 18 example modules and 0 stdlib
  ones. Search `core/examples/` for relevant fodder before inventing a probe.
* **A zero is suspect until the instrument is shown capable of a non-zero.** Three
  times that day a "0 differ" meant "measured nothing". Positive control for the
  corpus harness: `core/examples/incomplete/unsound0[1-4]*.e` flip LOADED ->
  REJECTED under `-Dermine.labelCheck`.
* **A number belongs to an instrument, not to the compiler.** A corpus sweep
  compares verdicts and messages only — a loaded module prints one line and never
  a signature (`grep -lE 'forall|rho|<-' *.out` matches 0 of 66). Signatures need
  `tracker/tools/ei-diff.sh`. Carrying a figure between the two produced a wrong
  prediction that day.
* `bin/ermine` WRITES `.ei` and READS them by default. Delete them on BOTH sides of
  any A/B, or the second side reads what the first wrote.
* `tracker/tools/sweep-progress.py` attaches to an already-running sweep and shows
  progress; both sweep scripts are otherwise silent for 15-50 minutes.
* Running `bin/ermine` on one `core/examples/Ai/*.e` alone reports
  `Module not found: 'Ai.Common'` — put `Common.e` first on the command line.

## Constraints

* **Disk is tight.** Never run `lake exe cache get`, never add a Lean `require`,
  never create another Lean project, never touch `~/research/leanwork`.
  `Rowpartition/CutSearch.lean` OOMs at 15GB and is deliberately NOT in the root
  import list or the axiom audit.
* **Do not commit or merge without asking.**
* `core/examples/Yahoo.e` (modified) and `tracker/JSON-API-DESIGN.md` (untracked)
  are NOT ours — leave both alone.
* Re-measure rather than inherit any figure in this prompt.
