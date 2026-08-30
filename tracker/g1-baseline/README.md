G1 oracle baseline (old pipeline, serial load, full inference).
Produced by: tracker/tools/g1-diff.sh run old tracker/g1-baseline
Role: drift TRIPWIRE only — the primary G1 comparison is a same-commit
dual run (roadmap item 4.2); an old-vs-baseline mismatch stops the loop
for explanation, never a silent re-cut.
