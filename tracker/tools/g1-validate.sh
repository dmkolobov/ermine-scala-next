#!/usr/bin/env bash
# Validate the G1 oracle both ways (tracker/LSP-ROADMAP.md item 1.1):
#   1. mutation fixtures: hand-built .ei pairs the comparator MUST flag
#      (and permuted-but-equivalent pairs it must NOT) — guards against a
#      pass-everything comparator surviving self-agreement;
#   2. old-pipeline double run: two independent full-inference boots must
#      compare EQUIVALENT through the whole harness, zero file skips.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
cp="$(tr -d '\n' < tracker/repl-classpath.txt)"
fail=0

for d in tracker/g1-oracle-tests/*/; do
  name=$(basename "$d")
  case "$name" in eq-*) want=equal;; diff-*) want=differ;; *) continue;; esac
  if "$JAVA_HOME/bin/java" -cp "$cp" com.clarifi.reporting.ermine.tools.G1Compare \
       --pair "$d/a/M.ei" "$d/b/M.ei" --expect "$want" > /tmp/g1-fix-$name.log 2>&1; then
    echo "  PASS  fixture $name"
  else
    echo "  FAIL  fixture $name"; tail -5 /tmp/g1-fix-$name.log; fail=1
  fi
done

# REPAIRED 2026-08-31.  This gate had been failing since post-G1 D3 and had
# evidently not been run since: it called two things that D3 deleted.  The
# ModuleScope-vs-importing() differential ran com.clarifi.reporting.ermine.
# tools.G1Importing, deleted in 9ad5909 along with the fused grammar it
# compared against -- there is no second pipeline to differ from any more, so
# the check is GONE rather than repaired.  The double run asked g1-diff.sh for
# the 'old' pipeline, retired in 80df1eb, which exits 2.
#
# In its place the drift tripwire is finally ARMED.  tracker/g1-baseline has
# had the exact layout `compare` expects (ei/, browse.txt, groups.txt) since
# G1, and nothing in tracker/tools ever referenced it -- so inferred types
# could drift from the recorded baseline with no test saying so.  browse.txt
# is the only artifact sensitive to inferred BINDER ORDER and rendered names
# (g1-normalize.py sorts only within `exists` blocks), which is exactly what a
# substitution-representation change would move.  See PERF-ROADMAP.md P7.

echo "-- double run (2 full-inference boots + compare) --"
tracker/tools/g1-diff.sh run new /tmp/g1-selfA && \
tracker/tools/g1-diff.sh run new /tmp/g1-selfB && \
tracker/tools/g1-diff.sh compare /tmp/g1-selfA /tmp/g1-selfB \
  && echo "  PASS  double-run self-agreement" \
  || { echo "  FAIL  double-run self-agreement"; fail=1; }

# ADVISORY, not a hard gate, until the baseline is re-recorded -- see the
# PERF-ROADMAP P7 gate question.  First arming (2026-08-31) reported 1447
# signatures with exactly ONE differing: lookbackJoin, which is the DOCUMENTED
# solver-order-sensitive residual (the reason -Dermine.loadInSeries exists).
# The browse/groups diffs are explained by Stage 1 replacing the pipeline.  So
# the baseline is STALE, not the tree drifted -- and re-recording a golden is a
# Decision 9 act that needs sign-off, not a side effect of repairing a script.
echo "-- baseline drift (fresh run vs tracker/g1-baseline) [ADVISORY] --"
if tracker/tools/g1-diff.sh compare /tmp/g1-selfA tracker/g1-baseline > /tmp/g1-baseline-cmp.log 2>&1; then
  echo "  PASS  no drift from tracker/g1-baseline"
else
  echo "  ADVISORY  differs from tracker/g1-baseline (stale since Stage 1; see"
  echo "            PERF-ROADMAP P7 gate question).  Signature verdict:"
  sed -n 's/^\(g1-compare: [0-9]* files.*\)/            \1/p' /tmp/g1-baseline-cmp.log
fi
exit $fail
