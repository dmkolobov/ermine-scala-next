# Brief: signature entailment, stage S2 -- design the check, on paper, with the Lean statement

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-sig`, branch `sig-entail`, HEAD 0c5e357 (S1 committed).
No commits. Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
`lake` for Lean under `tracker/lean/` (build with `lake build Rowpartition` and run the audit the way
`tracker/lean/Audit.lean`'s header says; NO `lake exe cache get`, no new project). JVMs and other agents run in
PARALLEL on this machine by policy (tracker/GATE-POLICY.md "Parallelism rules" on the let-signatures branch --
read `../ermine-scala-wt-let/tracker/GATE-POLICY.md`); a REPL probe (`bin/ermine`) is fine any time. Budget:
6 hours wall clock -- write up and stop at the budget. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S2/`.

Read first, in this order: `tracker/SIG-ENTAIL-PLAN.md` (all; the S2 section is your contract);
`tracker/loopmodel/SIG-1-SURVEY.md` §8 ("READ THIS FIRST: the refutation trick reaches 4.7%") and the rest of
§8; `tracker/loopmodel/SIG-1-REVIEW.md` (the taxonomy buckets A-G and the (c) table); `Subst.scala:527-553`
(`subsumeType`) and `:638`, `:655`, `:918-924`; `SigEntail.scala` (the S1 probe: how Q, W and the flavours are
obtained today); `tracker/lean/Rowpartition/Basic.lean` (`Sat`, `Models`, `Entails`, `entails_iff_forall_label`
:525 and its satisfiability hypothesis), `Rules.lean:412` (`ConservativeExt`), `RoseTheory.lean:971,1001`.

WORKING ASSUMPTION (the orchestrator's, stated to the user): S2 designs the GENERAL procedure, not the
refutation trick. 871 of 914 real obligations mention no concrete label; a check that decides 4.7% of them is
not a check.

## (a) The judgement
Fix it exactly. Given a user signature with quantified row variables R (rigid) and constraint set Q, a body
residual W of partition constraints mentioning at least one variable of R, and F = the variables of W not in R
and not in Q's own existentials: the signature is honest iff

    for all rho modelling Q, there exists rho' agreeing with rho off F such that rho' models W.

Settle: (1) Q's own existentials (`exists c. a <- (b, c)` in `Has`) -- are they universally instantiated by the
caller (so they behave like R inside the body) or chosen? Argue from how `unbindExists` at :532-533 and the
callers instantiate them; the S1 §8 item 5b conflation is yours to resolve. (2) Unsatisfiable Q: reject the
signature ("no instance can satisfy this context") or accept vacuously -- decide and say why, and what the
message is. (3) The `Bound` flavour (`Forall.mk` dropping constraint-only binders, S1 §8 item 5): what the
checker must do with a wanted mentioning one. (4) Unexpanded aliases in Q (`Has`, user `type` aliases).

## (b) The decision procedure -- the heart of S2
Partition constraints are label-wise: `v <- (p1..pk)` says, for EVERY label l, l is in v iff it is in exactly
one pi. `entails_iff_forall_label` already decomposes one-sorted entailment per label under a satisfiability
hypothesis. Show whether the two-sorted judgement in (a) decomposes the same way: for each label, the
memberships of all row variables form a Boolean vector; Q and W become propositional formulas over that
vector (one per label); the judgement becomes "for every assignment of the R-and-Q variables' memberships
satisfying Q's formula, some assignment of the F variables' memberships satisfies W's formula" -- a small
2QBF per label class. Handle the labels that occur LITERALLY in Q or W (each is its own case) and the one
generic label for all others. Work out: whether the per-label existential choice for F is legitimate (rows
are arbitrary label sets, so choosing F's membership label by label is sound -- prove it, that is the crux);
the complexity (2^|vars| per label class; report the max |vars| over the 308 corpus signatures from the S1
data, `tracker/tools/sigentail-agg.py` output); and a worked evaluation of the procedure BY HAND on: sig01,
sig02, sig04, sig05 (must reject), control08's four spellings and `ok5` (must accept), all twelve (c) items
of S1 (must reject), and five of S1's (b) samples across buckets C, D, G (must accept). If some case needs
more than the per-label procedure, say what and why.

Also state what a DERIVATIONAL procedure would look like (run the solver on Q, check W is in the closure /
is derivable with F fresh) and why the semantic one is or is not preferable (completeness, blame, cost). If
the semantic procedure is right, the solver is used only for Q's satisfiability precondition.

## (c) The Lean statement and proof
New module `tracker/lean/Rowpartition/SigEntail.lean` (the only Lean file you create or edit; do not touch
others). Define the flavour split (a predicate on `Var`, or an explicit `R`/`F` finset pair), `SigEntails Q W F`
per (a), the per-label formulas, and prove: (i) soundness AND completeness of the per-label procedure for
`SigEntails` (the label-wise decomposition with the existential over F), reusing `entails_iff_forall_label`'s
method and `ConservativeExt`/`ndStep_extend` where they apply; (ii) the special case that the refutation trick
is a correct decision for bucket A, as a corollary; (iii) a `decide`-able instance on the sig01 and control08
systems (see the memory note [[ermine-lean-decide-recipe]] if `decide` stalls: simp with `vset_mk`/`mk_eq_iff`
first). `lake build` and the audit must be green; report the theorem list.

## (d) Where it runs, and the blame
Inside `subsumeType`, only when a `SigEntail.Site` is present (the S1 plumbing; `ann` and `sig`, never the App
case). Specify: the order relative to `restrictTypes(tts)` at :540 (the skolems must still be visible), what
replaces the discarded `for (r <- rs) entails(qs, r)` at :535-536, what is returned at :553, and what the
`error`/`warn`/`off` flag does at each point. The message: the wanted (pretty), "not entailed by the
signature's constraints", the givens, and TWO locations -- the term that generated the wanted (its `Located`,
which `rs` elements carry) and "declared at" on the signature. Check the existing blame machinery
(`-Dermine.rowSound`, ROW-CONSTRAINT-STATE.md "blame-location") for the mechanism to reuse.

## (e) Report
`tracker/loopmodel/SIG-2-DESIGN.md`: (a)-(d) with every code site by line, the worked table from (b), the
complexity numbers, the Lean theorem list, the S3 implementation checklist (files, functions, tests to flip:
sig01/02/04/05, TestSigEntail's KNOWN HOLE properties, the `error` flag under the fixture's session-option
mechanism), and an "open questions for the user" list. Under 500 lines.
