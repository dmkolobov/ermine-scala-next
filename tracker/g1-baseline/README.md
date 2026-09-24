G1 oracle baseline — the split pipeline, serial load, full inference.

Produced by:  tracker/tools/g1-diff.sh run new /tmp/g1-fresh
              (then copied here; .ei files are force-added past .gitignore)

Role: drift TRIPWIRE.  tracker/tools/g1-validate.sh compares a fresh
full-inference run against this tree and FAILS on any difference, so an
inference change that alters a type — even one that still renders
alpha-equal — is caught.  browse.txt is the artifact sensitive to inferred
BINDER ORDER and rendered names; g1-normalize.py sorts only within
`(exists ...)` blocks, so ordering elsewhere is load-bearing.

RE-RECORDED 2026-08-31 (roadmap P7 Step 0, signed off).  The previous
baseline was cut with `run old` before post-G1 D3 and had gone stale: the
fused pipeline it came from no longer exists, and comparing it against HEAD
reported 1447 signatures with exactly ONE differing — lookbackJoin, the
documented solver-order-sensitive residual (the reason -Dermine.loadInSeries
exists).  1446/1447 were alpha-identical, so the tree had not drifted; the
baseline had.  browse.txt and groups.txt differed because Stage 1 replaced
the pipeline: group parse-errors went 5 -> 3, since the split pipeline
re-parses Native.List and Relation, which the fused one could not.

Re-cutting this is a Decision 9 act (PERF-ROADMAP.md) and needs sign-off —
never a silent re-cut to make a red gate green.

## Re-cut 2026-09-09 (stage S5 fix round, review finding Q-15)

`tracker/tools/g1-validate.sh`'s baseline-drift check had been RED since stage F3 and the
script says a red here "is a Decision 9 stop — explain it or revert it".  This is the
explanation, and the baseline is re-cut on it.

**What drifted, and why none of it is a regression.**  13 of 129 `.ei` (70 lines) and 46 of
1,301 `browse.txt` lines; `groups.txt` byte-identical.  `G1Compare` — which compares up to
alpha-equivalence, so it sees through renaming — reports 22 signatures in 7 files as
genuinely differing.  Two classes, both from adoptions COMMITTED after the baseline was
recorded in `7ebcbfa` (2026-08-31):

* `Relation/Scan.ei :: sumBy'` — F3 (`775a20f`, 2026-09-08) deleted a VACUOUS `r <- (h, t)`
  from the written signature in `Relation/Scan.e` by hand; the baseline still carries it.
  An intended source change, and the one the drift check was actually reporting.
* everything else — alpha-variants and part-order differences in `(&)`, `(&_Mem)`, `(**)`,
  `dateDiff`, `lookbackJoin`, `setColumn`, the `Predicate` comparisons and so on: the
  published constraint sets are the same up to renaming the existentials, which is the
  churn `smallcanon` (A1, `fe024a7`, 2026-09-06) and `topNormalise` (S4c, 2026-09-08)
  produce and which both adoptions measured and accepted.

**Stage S5 changes NONE of them.**  S5's tautology deletion moves exactly four signatures,
all in `Layout/Scan.ei`, which is not among the 13 files; and all 13 are byte-identical
between S5's flag-OFF and flag-ON interface snapshots.  Verified before the re-cut.

**Form.**  Re-cut from a fresh `g1-diff.sh run new`, with the stage-S5.2 interface key
header (`-- ermine-interface <format>|<GenRules>`) STRIPPED, so the baseline stays in the
unkeyed form it has always had and its diff shows only type changes.  `G1Compare` reads
through `Session.splitInterfaceKey`, so it compares a keyed tree against this unkeyed
baseline without either side being touched.
