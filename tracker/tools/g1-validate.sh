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
       --pair "$d/a/M.ei" "$d/b/M.ei" --expect "$want" > "${TMPDIR:-/tmp}/g1-fix-$name.log" 2>&1; then
    echo "  PASS  fixture $name"
  else
    echo "  FAIL  fixture $name"; tail -5 "${TMPDIR:-/tmp}/g1-fix-$name.log"; fail=1
  fi
done

# REPAIRED 2026-08-31.  This gate had been failing since post-G1 D3 and had
# evidently not been run since: it called two things that D3 deleted.  The
# ModuleScope-vs-importing() differential ran com.clarifi.reporting.ermine.
# tools.G1Importing, deleted in d8a98a6 along with the fused grammar it
# compared against -- there is no second pipeline to differ from any more, so
# the check is GONE rather than repaired.  The double run asked g1-diff.sh for
# the 'old' pipeline, retired in faa5769, which exits 2.
#
# In its place the drift tripwire is finally ARMED.  tracker/g1-baseline has
# had the exact layout `compare` expects (ei/, browse.txt, groups.txt) since
# G1, and nothing in tracker/tools ever referenced it -- so inferred types
# could drift from the recorded baseline with no test saying so.  browse.txt
# is the only artifact sensitive to inferred BINDER ORDER and rendered names
# (g1-normalize.py sorts only within `exists` blocks), which is exactly what a
# substitution-representation change would move.  See PERF-ROADMAP.md P7.

echo "-- double run (2 full-inference boots + compare) --"
tracker/tools/g1-diff.sh run new "${TMPDIR:-/tmp}/g1-selfA" && \
tracker/tools/g1-diff.sh run new "${TMPDIR:-/tmp}/g1-selfB" && \
tracker/tools/g1-diff.sh compare "${TMPDIR:-/tmp}/g1-selfA" "${TMPDIR:-/tmp}/g1-selfB" \
  && echo "  PASS  double-run self-agreement" \
  || { echo "  FAIL  double-run self-agreement"; fail=1; }

# HARD GATE since 2026-08-31, when tracker/g1-baseline was re-recorded against
# the split pipeline (P7 Step 0, signed off).  This is the check that catches an
# inference change altering a type that still RENDERS alpha-equal, which the
# double run above cannot: two runs of the same build agree with each other
# whether or not they agree with yesterday.  A red here is a Decision 9 stop --
# explain it or revert it; never re-cut the baseline to make it green.
echo "-- baseline drift (fresh run vs tracker/g1-baseline) --"
if tracker/tools/g1-diff.sh compare "${TMPDIR:-/tmp}/g1-selfA" tracker/g1-baseline > "${TMPDIR:-/tmp}/g1-baseline-cmp.log" 2>&1; then
  echo "  PASS  no drift from tracker/g1-baseline"
else
  echo "  FAIL  drift from tracker/g1-baseline"; tail -12 "${TMPDIR:-/tmp}/g1-baseline-cmp.log"; fail=1
fi
exit $fail
