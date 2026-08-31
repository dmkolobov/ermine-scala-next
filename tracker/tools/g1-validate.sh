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

echo "-- ModuleScope vs importing() differential (item 3.1) --"
if "$JAVA_HOME/bin/java" -cp "$cp" com.clarifi.reporting.ermine.tools.G1Importing verify > /tmp/g1-importing-verify.log 2>&1; then
  echo "  PASS  importing differential ($(tail -1 /tmp/g1-importing-verify.log))"
else
  echo "  FAIL  importing differential"; tail -8 /tmp/g1-importing-verify.log; fail=1
fi

echo "-- old-pipeline double run (2 full-inference boots + compare) --"
tracker/tools/g1-diff.sh run old /tmp/g1-selfA && \
tracker/tools/g1-diff.sh run old /tmp/g1-selfB && \
tracker/tools/g1-diff.sh compare /tmp/g1-selfA /tmp/g1-selfB \
  && echo "  PASS  double-run self-agreement" \
  || { echo "  FAIL  double-run self-agreement"; fail=1; }
exit $fail
