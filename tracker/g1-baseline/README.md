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
