  Research a principled decision procedure for Ermine's row-partition constraints.

  This is a RESEARCH task, not an implementation task. The deliverable is a design
  document with a defensible recommendation, plus (if it earns its place) a Lean
  development. Do not change Scala until a design is signed off.

  WORKING DIR: ~/research/ermine/ermine-scala, branch scala3-migration.
  All durable state is in the repo; you need nothing from prior transcripts.

  ## Orientation — read before anything

  - core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala. Read the
    240-line header comment IN FULL: it states the rule set. Then read
    `incorporateAll` (:743), `learnPartitions` (:805), and the four generative
    rules `splitConcrete` (:795), `resolution` (:1021), `commonSubexpression`
    (:1076), `disjunction` (:1092).
  - Type.scala:355-400 (`Part`, its smart constructor) and :141 (`ConcreteRho`).
  - tracker/PERF-ROADMAP.md, the iteration-log entries on the row-solver cliff and
    on "records are rows". They contain the measurements below.

  ## What is already established — do NOT re-derive

  THE CONSTRAINT LANGUAGE. `a <- (b, c, (|Foo|))` means row `a` is exactly the
  DISJOINT UNION of b, c and the singleton {Foo}: concatenation + disjointness +
  completeness in one relation. Rows are variables or fully concrete
  (`ConcreteRho`, a `Set[Name]` of labels). Constraints are legal only in
  strictly positive positions (Subst.scala:862, Type.scala:201), so they cannot
  accumulate across a higher-order boundary.

  THE SOLVER is forward-chaining saturation over a priority search queue, with an
  all-pairs comparison per worklist step. It is NOT backtracking and NOT a
  decision procedure.

  WHY IT HANGS. Resolution and Common-subexpression each consume two constraints
  and emit THREE, one carrying a FRESH variable, which re-enters the queue and is
  compared against everything already processed. There is no decreasing measure
  and no termination argument anywhere in the file. The header itself predicts
  poor behaviour (:208-212) and proposes a trim that was never implemented
  (:236-239). The cubic `disjunction` rule is commented out at both call sites.

  THE MEASURED CLIFF, from N left-nested `join`s in one UNANNOTATED definition
  (regenerate with tracker/tools/gen-row-stress.py):
    N=4 0.03s, N=5 0.13s, N=6 0.79s, N=7 10.94s, N=8 >138s killed.
  Step ratios 4.3x, 6.1x, 13.8x — the ratio itself grows, so worse than
  exponential. A JFR profile of N=7 is 98.4% constraint solving: 59.7% priority-
  queue maintenance, 38.4% the rules, led by commonSubexpression.

  WHAT THE CORPUS ACTUALLY NEEDS — this is the most important empirical fact and
  it should shape the whole investigation. Across the 129-module stdlib closure:
  105 of 129 modules produce ZERO partition constraints; of 199 constrained
  signatures, 126 carry exactly ONE; the global maximum residual is 15
  (`lookbackJoin`, Relation.e:206, which has 6 chained row-constrained calls —
  one step below the knee). Real code sits far inside the easy fragment.

  TWO EXISTING DEFECTS the current solver has, which any replacement must not
  inherit:
  1. NON-CONFLUENCE. `lookbackJoin`'s residual contains a vacuous `r <- (r)` and
     prints the same constraint twice under different RHS orderings. Saturation
     stops at a non-canonical form.
  2. NON-DETERMINISM. The queue key is `(rhs.hashCode, lhs.hashCode)` and a
     TypeVar's hash is its `Supply`-drawn id, so parallel loading changes solve
     order and reaches .ei bytes. That is why `-Dermine.loadInSeries` exists.
     Also: `Part.apply` REVERSES its RHS list on every pass, so a partition's
     rendered order depends on how many substitution passes ran.

  PRIOR ART IN THE REPO'S OWN HISTORY: commit 1213681 on branch
  features/limit-row-solving (Dan Doel, 2018), "Bail out of row constraint solving
  if it takes too long" — a 50,000-step countdown and an exception named
  `Eternity`, never merged. On cutoff it returns the constraint set UNSOLVED, so
  residuals leak into inferred types and typing becomes a function of how long the
  solver ran. Assume it was not merged because that is not a fix. Do not propose
  it again without addressing that.

  ## The research questions, in priority order

  1. WHAT IS THIS PROBLEM, EXACTLY? Characterise `a = b ⊎ c ⊎ …` over row
     variables with an open label set. Candidate framings to evaluate: unification
     modulo AC/ACI/ACU; set constraints; Boolean unification (encode "label ℓ ∈ r"
     as a Boolean variable per label — note Boolean unification is unitary, with
     most general unifiers via Löwenheim/variable elimination); linear equations
     over multiplicities. Establish decidability and complexity from the
     literature, and say which framing is FAITHFUL to Ermine's semantics rather
     than merely similar.
  2. IS THERE A DECIDABLE FRAGMENT THAT COVERS ALL REAL USES? Given the corpus
     statistics above, a weaker but terminating system may lose nothing anyone
     uses. Evaluate Gaster–Jones "lacks" constraints and Leijen's scoped labels
     against every partition constraint the 129 modules actually produce
     (tracker/g1-baseline/ei has them all; grep for `<- (`). If some fragment
     covers 1447/1447 signatures, that is a far better answer than a cleverer
     solver for the general case. QUANTIFY the answer, do not assert it.

  3. IF THE FULL LANGUAGE IS KEPT, what is the right algorithm? The existing rules
     ARE a constraint-handling-rules program; CHR has developed theory for
     confluence (critical-pair analysis) and termination orderings. Either produce
     a terminating, confluent rule set with a proof, or show none exists for this
     language and fall back to question 2.

  4. WHAT IS THE HONEST FAILURE MODE? If some inputs are genuinely intractable,
     the right behaviour is a DETERMINISTIC diagnostic — "row constraints too
     complex to infer here; add a signature" — not a hang and not a silent
     incompleteness. Annotated code already takes the cheap concrete path, so the
     escape hatch exists. Design the boundary so the same program always gets the
     same answer.

  ## Using Lean

  Use Lean 4 + Mathlib where it earns its place, not decoratively. It is most
  valuable for:
  - Formalising the constraint language: rows as finitely-supported label sets
    plus a variable part; define entailment semantically.
  - Proving SOUNDNESS of each existing rule (each should be fine — confirm).
  - Attempting TERMINATION of the saturation, and extracting the counterexample
    from the failed proof. The N-way join family is the expected witness; a Lean
    formulation should make the divergence structural rather than empirical.
  - Proving termination + soundness + completeness of whatever you propose.
  Say explicitly which results are proved in Lean, which are proved on paper, and
  which are cited from the literature. Do not blur those.

  ## Acceptance — what any proposal must survive

  - It must accept everything the 180-file corpus accepts (stdlib + core/examples)
    and produce .ei ALPHA-EQUAL results: `tracker/tools/g1-validate.sh` compares a
    fresh full-inference run against tracker/g1-baseline and must report 1447
    signatures EQUIVALENT with no drift.
  - REPL goldens (tracker/repl-tests/*.expected) byte-unchanged.
  - It must be DETERMINISTIC: no dependence on Supply order, thread scheduling, or
    iteration order of a hash-keyed structure. This is a hard requirement, not a
    nicety — the current solver fails it and that failure is load-bearing enough
    to have its own flag.
  - Residuals must be CANONICAL: no vacuous `r <- (r)`, no duplicate constraint
    under a permuted RHS.
  - The cliff must be gone or converted to a deterministic diagnostic. Verify with
    gen-row-stress.py at N=8..20.

  ## Deliverables

  1. tracker/TICKET-row-constraint-decision.md: the problem characterised, the
     literature surveyed with citations, the fragment analysis with corpus
     numbers, a recommendation, and an explicit list of what you could NOT settle.
  2. Any Lean development under tracker/lean/ with a README saying what is proved.
  3. A recommendation ranked against effort, including the option "restrict the
     language" and the option "do nothing but make it diagnose".

  Do not write Scala. This ends at a signed-off design.

  ## Toolchain

  export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
  sbt -batch core/test                  # 904 total; only "Constraints.disjunction
                                        # sound" may fail (known, and note it tests
                                        # the commented-out rule)
  bash tracker/tools/g1-validate.sh     # fixtures + double run + baseline drift
  bash tracker/tools/repl-smoke.sh      # 4 suites
  python3 tracker/tools/gen-row-stress.py --out /tmp/rowstress --to 10

