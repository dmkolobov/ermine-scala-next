# Brief: S3 — the three omissions in `Subst.mkSimplified` (published residuals: permuted duplicates and tautologies)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the commit the
orchestrator names (adopted defaults in force). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time (other agents share the machine); sbt
allowed for the gates; long runs under `setsid nohup` with a log; delete `.ei` files you cause; no commits.

ORIGIN: `tracker/ROSE-COMPARISON.md` §3, idea 1 (read it first, with `A1-REVIEW.md` §R-1/R-6 and
`core/examples/incomplete/Signatures.e`). Looking for Rose's simplifier led to Ermine's own: `Subst.mkSimplified`
already TRIES to delete permuted duplicate residual constraints and fails, because `NormalPart` overrides
`equals` (sorting `abstrakt`, ignoring `loc`) but NOT `hashCode`, and `List.distinct` buckets by hash — so two
permuted copies of one constraint both survive into the published signature. That is the mechanical
explanation of A1-REVIEW §R-1 (`np01.inferredRestate` publishing two verbatim duplicates with permuted parts).
Two siblings: `normalPart` has a `None` case for the concrete identity but none for the tautology `a <- (a)`
(which is why `incomplete/TopReadings.e:31` publishes one; `Signatures.e`'s `taut` documents it), and — verify —
no case for a constraint entailed by a duplicate-free sibling. All three are READ FROM CODE, not measured:
reproducing them is acceptance criterion 1.

## What to do

S3.1 Reproduce: a minimal module (or the two corpus modules named) whose published `.ei` carries (a) a permuted
     duplicate, (b) an `a <- (a)` tautology; show the `.ei` text before the fix.
S3.2 Fix `NormalPart.hashCode` to agree with its `equals` (hash the sorted `abstrakt` and the concrete part, not
     `loc`); add the tautology case to `normalPart`; say whether the third sibling exists and fix it if so. This
     is a SIMPLIFIER change: it can only remove constraints that are duplicates or tautologies, so every published
     residual stays entailment-equivalent by construction — state that argument in the report and, if cheap, in
     Lean: a lemma that deleting a duplicate or `a <- (a)` from a system preserves `SEntails`-equivalence
     (`Loop/Strict.lean`'s `NoLoss`/`Conserv` vocabulary; `Rowpartition/Canonical.lean` has related material) —
     you MAY build Lean only if no other agent is running the `looptrace` binary at that moment (check `ps` for
     `looptrace`; if one is running, do the Lean part last and coordinate via the report).
S3.3 Gates: `core/test` (913/914 or 912 with the known flake); `TestLoopTrace` 714/714 (the loop is untouched —
     `mkSimplified` is post-loop — so the row trace must be byte-identical: run `looptrace-corpus.sh` on two
     groups and diff against a pre-fix trace); the `.ei` sweep with the deterministic loader (`-Dermine.loadInSeries=true`)
     before and after: classify every changed binding with A1's `iso2.py`/`einorm3.py` — every change must be a
     deleted duplicate or tautology, NOTHING weaker or stronger, and the count of A1's "movers" should drop
     (report how many of the 30 remain and why); corpus verdicts unchanged (`corpus-run.sh --batch` both
     corpora); `Signatures.e` still checks (its `xDeduped = xFull` proofs must still hold — and say whether any
     of its hand-deduplications is now done by the compiler); perf-bench unchanged.
S3.4 Report `tracker/loopmodel/S3-SIMPLIFY.md` (the reproduction, the diff, every gate with numbers, the
     entailment-equivalence argument), the state file additively, a plan row. A reviewer re-runs everything.

Outcomes: (GREEN) reproduced and fixed with all gates green; (NOT-REPRODUCED) the defect read from code does
not occur — say why, with the evidence, and stop. No silent weakening; report early.
