# Review brief: signature entailment, stage S2 -- the design and its Lean proof

You are reviewing S2 in `/home/dmitry/research/ermine/ermine-scala-wt-sig` (branch `sig-entail`, HEAD 5fa512a
plus the UNCOMMITTED deliverables `tracker/loopmodel/SIG-2-DESIGN.md` and `tracker/lean/Rowpartition/SigEntail.lean`;
the designer's scratch with `sigcheck.py` and `verdicts.txt` is
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/S2/`).
Designer's brief `tracker/loopmodel/briefs/brief-SIG-2.md`; plan `tracker/SIG-ENTAIL-PLAN.md`; S1 evidence
`tracker/loopmodel/SIG-1-SURVEY.md` and `SIG-1-REVIEW.md`. You edit nothing except your scratch directory
`.../scratchpad/review-S2/` and your report `tracker/loopmodel/SIG-2-REVIEW.md`. No commits, never `git stash`.
Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
`lake build Rowpartition.SigEntail` and the audit are allowed (no `lake exe cache get`); JVMs run in parallel
on this machine by policy. Budget 4 hours. Verdict ADVANCE / FIX-THEN-ADVANCE (exact edits) / BLOCK.

The user will implement S3 from this design. Attack it:

1. **The crux lemma.** `sigEntails_of_lsig` says per-label F-choices glue into one row assignment. Read the
   proof, not the statement: does the gluing rely on labels being finite (`Finset Label`) in a way that
   breaks for the generic-label class (a class standing for infinitely many labels)? Is the generic class
   handled by one representative label with a uniformity lemma (`sigEntails_of_uniform`), and is THAT
   lemma's hypothesis actually met by the procedure for every input, or only for inputs with no
   literal labels in W? Construct an input that mixes literal labels in Q with variable-only W and
   check the theorem chain covers it.
2. **Completeness hypothesis.** `lsig_of_sigEntails` needs Q satisfiable; `lsig_stronger_of_unsat` covers
   the other case. Confirm the procedure's verdicts are correct on BOTH sides for an unsatisfiable Q
   (construct one: `r <- (a, b), r <- (a), b <- ((|x|), c)` style) and that the "vacuously accepted but never
   silent" policy is what the Scala checklist implements.
3. **Rigidity choices.** Q's existentials rigid; `Bound` rigid; ambient metas in F conservative. For each,
   find a program where the choice makes the checker REJECT an honest signature (false positive) or
   ACCEPT a dishonest one. The report claims 0/309 wanteds mention a Q-existential and 0/36,328 mention a
   Bound var -- check how it counted (does `SigEntail.scala`'s probe even see them?).
4. **The executable procedure vs the Lean one.** `sigDecide` in Lean vs `sigcheck.py` vs the S3 checklist's
   Scala: are they the same algorithm? In particular the model enumeration "deduplicated on the projection
   to vars(W) ∩ R" -- is that deduplication sound (two Q-models with the same projection but different
   F-freedom)? And the budget-exhausted branch ("warn + accept"): is that acceptable for a soundness check,
   and is there an input in the corpus that hits it (the 24,109-step case)?
5. **The five new rejections in `Time/Helpers.e`** (`dayCount`, `monthsBetween`, `monthsSince`, `daysSince`,
   `daysUntil`): read each signature and body; confirm they are real holes and say why S1's probe+triage
   missed them (a bug in `sigentail-entail.py`, or a shape S1 classified as (b)?). Run the designer's
   `sigcheck.py` yourself on the S1 records and confirm 288/21/0.
6. **The (b) samples that must ACCEPT.** Pick five MORE from S1's (b) list that the designer did not check,
   across buckets C/D/G, run `sigcheck.py` on them, and read one by hand.
7. **Lean hygiene.** `lake build` and the audit yourself (the report says 4670 theorems, 0 non-standard
   axioms with the import); check for `sorry`, `native_decide`, `partial`, unused hypotheses that
   weaken a statement, and whether any theorem is stated over a strictly narrower system type than the
   procedure needs.
8. **S3 checklist completeness.** Every code site by line? The `error/warn/off` semantics at each point?
   The message and two blame locations? The fixture's session-option mechanism for running the KNOWN HOLE
   properties under `error`? The `Rowpartition.lean` import line the designer left to S3? Anything the
   implementer would have to decide alone?

Report `tracker/loopmodel/SIG-2-REVIEW.md`: verdict first, then 1-8 with evidence, the edit list. Under 350 lines.
