# Brief: review of E11b Phase 1 — the entailment oracle comparison (1 h)

Repo `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD `8cc4d38c`. Under review:
`tracker/loopmodel/E11b-ORACLE.md`, written against `tracker/loopmodel/briefs/brief-E11b-oracle.md` (read the brief
first: it states the question, DELETABLE(c), and the five-part treatment each candidate owes). The implementer's
scratch is `/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11b-oracle/`
(`<impl>`); the previous probe's pairs are under
`/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/e11b/pairs/`.
Your scratch: `<impl>/../e11b-oracle-review/` (create it). You change NO source, NO Lean, and NO tracker file except
your review `tracker/loopmodel/E11b-ORACLE-REVIEW.md`. Delete every `.ei` you cause under `core/target`. Never
`lake build`; never commit. Budget 1 hour; at the budget, write up what you have.

Per `tracker/GATE-POLICY.md`: CITE the implementer's logs by path for every figure you accept; RE-RUN only what you
dispute or what the points below name. No whole-corpus run, no full `core/test`.

## What to do

1. **Break the soundness argument of the RECOMMENDED oracle.** Construct, on paper or in a scratch harness,
   residuals where the oracle would say ACCEPT (delete) but the deletion is NOT `REquiv` in ROSE §4.1's sense
   (`Residual`, `Holds` with the existentials, `REntails` both ways). Attack in turn: a constraint whose
   existentials are SHARED with the rest (so the "choose a different witness" freedom is constrained); an
   existential that is fresh in `c` but the rest of `c` is not entailed; a universal that occurs only in `c`; a
   concrete left-hand side (the proxy encoding, if the report proposes it); an unsatisfiable rest-set `Q` (every
   `c` is vacuously entailed — is deleting then faithful? Is `Q`'s satisfiability actually discharged where the pass
   would run?); a class constraint mentioning a row variable the deletion makes dead. For each attack: refuted by
   the argument (say which sentence), or a HOLE (give the residual and the wrong verdict). Read `SigEntail.check`
   (`SigEntail.scala:418-616`) yourself for anything the report claims about `F`, rigidity, `sks`, or the no-verdict
   discipline; cite lines.
2. **Re-derive two of the six by hand**: `lookbackJoin` (the probe's §6 pair) and ONE of the `Yahoo` bindings from
   its pair file, and check the report's per-pair verdict for the recommended oracle against your derivation.
3. **Check the convergence claim**: the report states a choice rule and says both variants of each pair land on the
   same set. Re-run its simulation script from `<impl>` on at least `lookbackJoin` and one pair where mutual
   entailment (two constraints each deletable given the other) occurs, and confirm the log. Then try to break the
   rule: a three-constraint mutual-entailment cycle, or a pair where one variant's fixpoint lands on a set that is
   neither variant.
4. **Check the cost figures**: open the (A) measurement log the report cites, confirm the `lastCost` numbers and
   the per-constraint wall time are read correctly, and check the per-scheme extrapolation arithmetic against the
   28-constraint stress case. If the extrapolated batch overhead exceeds ~1 % say so prominently.
5. **Check the determinism claim** against the code it cites (`canonRows`, `LabelSearch`'s variable indexing, any
   `Set` or `Map` iteration in the path), and the Phase 2 placement claim (that `mkSimplified` precedes
   `Canonical.scheme`: `Subst.scala:1776` vs `:1792`).

## Review `tracker/loopmodel/E11b-ORACLE-REVIEW.md`

Verdict first: ACCEPT / ACCEPT WITH FIXES / BLOCK, with the items R-1.. that justify it (blocking items marked).
Then, per numbered point above, what you did, what you found, and the log path. State the claims of the report you
did NOT check. Time spent, stated. Plain language.
