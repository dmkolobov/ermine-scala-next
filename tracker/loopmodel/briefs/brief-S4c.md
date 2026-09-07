# Brief: S4c — the adoption prerequisites for `-Dermine.topNormalise`: the correspondence lemma and the S2 chain at ON

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from commit `0e1c86c` (S4 committed as
`c48f178`: flag DEFAULT OFF). LEAN ONLY: no Scala change, no example change. Toolchain `export PATH=$HOME/.elan/bin:$PATH`,
`LEAN_NUM_THREADS=2`, work in `tracker/lean/`. You are the ONLY agent on the machine: `lake build` is allowed, one at a
time. Disk is tight: never `lake exe cache get`, never add a `require`, never create another Lean project, never touch
`~/research/leanwork`; `Rowpartition/CutSearch.lean` OOMs and stays OUT of the root import list and the audit. Scratch
under `/home/dmitry/.claude/jobs/880c725d/tmp/S4c/`. No commits. Report early and keep it current.

READ FIRST: `tracker/loopmodel/S4B-REVIEW.md` §2.2, §5.2 and H-9; `tracker/loopmodel/S4-CHANGE.md` §1, §2, §7 and
"Fix round (S4B)" FR-1/FR-3; `tracker/loopmodel/S4Top.lean` (22 declarations, 18 audited theorems — abstract `System`,
`topAdds`/`topReads`, `models_rewrite`, `reads_of_rewrite`, `ssat_rewrite_fwd` with `c ∉ allVars G`, `noloss_of_top`,
`topAdd_escapes`, `topDrop`); `Rowpartition/Loop/Json.lean:187-232` (`topFamilies`, `topNormalise`, `buildQueue`);
`Loop/Seed.lean` (`solveSeed`), `Loop/PolicyReplay.lean` (`solveSeedP`); `Loop/NoFalseAccept.lean:930-1050` and
`Loop/PolicyStep.lean:2220-2280` (the six theorems carrying `htn : fl.topNormalise = false`); `Loop/Strict.lean`. The
MODELS to imitate: KeyedSplit's correspondence lemma (commit `d736bf9`), `K2ResStep.mint_toGRes`, `scalaEmptyRes_run`.

## S4c-1 — the correspondence lemma (required)

Bring `S4Top.lean` INTO the library (e.g. `Rowpartition/Loop/TopNormalise.lean`, namespace kept or renamed, added to
the root import list `Rowpartition.lean` so `Audit.lean` covers it; leave the scratch copy or replace it with a one-line
pointer — say which). Then prove, about the EXECUTABLE `Json.topNormalise true q su = .ok (q', su')` (or whatever its
exact shape is):
  (a) every family `topFamilies` selects satisfies the theorems' hypotheses: `fam ≠ []`, `k ≥ 3`, each member is a read
      `v <- (x_i, F_i)` with `x_i ≠ v`, `F_i` non-empty, pairwise-incomparable and DISTINCT, no concrete row at `v`,
      `F = ⋃ F_i`, `F_i ⊆ F`;
  (b) the carrier is fresh for the WHOLE system (from `Sup`'s counter: `c ∉ allVars (sys q)`), one carrier per family
      and distinct across families;
  (c) the returned queue, read as a system, is `(G ∪ ⋃ topAdds) \ ⋃ topReads` over the ORIGINAL families (one pass —
      state the multi-family composition and prove it, since `S4Top` is single-family);
  (d) the system-level consequence for the code: `SSat (sys q') → SSat (sys q)` (via `reads_of_rewrite` /
      `noloss_of_top`) and `SSat (sys q) → SSat (sys q')` (via `ssat_rewrite_fwd` + (b)), i.e. the executable rewrite
      is satisfiability-equivalent; and the `NoLoss`/`Conserv` statement in `Loop/Strict.lean`'s vocabulary.
Prove about the code AS IT IS. If a definition must be restructured to be provable (e.g. `topFamilies` split into
selector + rewrite), the executable behaviour must not change: TestLoopTrace 720/720 and the ON differential on
`Present` + `Lang` (`looptrace-corpus.sh` with `LOOPTRACE_JAVA=-Dermine.topNormalise=true LOOPTRACE_FLAGS=--flags=topnorm`,
agree = segments, 15 `tnorm` records) byte-identical before/after — run them and say so. `sin` now carries the flag, so
a plain replay of an ON trace also applies it.

## S4c-2 — the S2 no-false-acceptance chain at `topNormalise = true` (required to attempt; report the exact residue)

Remove `htn : fl.topNormalise = false` from `solveSeed_rejects_of_refuted`, `solve_noFalseAccept`,
`solve_accepted_faithful` and their three `PolicyStep` twins by case-splitting on the flag and bridging the ON case
with S4c-1(d) (the checks read the REWRITTEN queue, so "refuted on q'" must give "unsat on q", and "accepted on q'"
must give the faithful statement about q). Keep the OFF proofs intact. If a theorem cannot be closed at ON, keep its
`htn` and state precisely which statement is missing and why (that is a fact about the adoption, not a footnote).

## S4c-3 — a `LoopStrict` constructor for the additive mint: ONLY if it falls out; not required.

## Gates (report every number)
`cd tracker/lean && lake build` GREEN (full default target); `lake env lean Audit.lean` count with 0 non-standard
axioms; `#print axioms` for every new/changed theorem in scratch (`propext`/`Classical.choice`/`Quot.sound` only; no
`sorryAx`, no `nativeDecide`); `lake exe looptrace` rebuilt and `sbt -batch -J-Xmx3g 'core/testOnly *TestLoopTrace'`
720/720 (`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM, delete every `.ei` you cause); the ON
differential above if any executable Lean changed. Report `tracker/loopmodel/S4C-CORRESPONDENCE.md` (what is proved,
statement by statement, with the hypotheses discharged from the code; what remains); update the plan row S4c and the
state file's "AT ADOPTION" block additively. Outcomes: (GREEN) S4c-1 and S4c-2 closed; (PARTIAL) S4c-1 closed, S4c-2
residue named; (BLOCKED) say what and why. No silent weakening. The adoption itself (flipping the flag, moving
`proj01_seven_reads.e`, clearing `.ei`) is NOT yours — it is the user's.
