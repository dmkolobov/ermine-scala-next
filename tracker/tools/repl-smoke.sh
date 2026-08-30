#!/usr/bin/env bash
# Feed tracker/repl-tests/smoke.in to the REPL and diff against smoke.expected.
#
#   sbt 'export core/fullClasspath' > /dev/null   # once, after a build
#   tracker/tools/repl-smoke.sh
#
# Interface caching is off so the run always exercises real inference;
# with it on, the second run answers from the .ei files instead.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
cp="$(tr -d '\n' < tracker/repl-classpath.txt)"

actual=$(
  "$JAVA_HOME/bin/java" -Dermine.typeCheck=true -Dermine.useInterface=false -cp "$cp" \
    com.clarifi.reporting.ermine.session.Console < tracker/repl-tests/smoke.in 2>&1 |
  sed -n '/Loaded [0-9]* modules/,$p' |          # drop banner + module list
  tail -n +2 |                                   # drop the "Loaded N modules" line
  sed 's/^>> //; s/^>>$//' |                     # strip prompts
  grep -v '^$'
)
if diff -u tracker/repl-tests/smoke.expected <(printf '%s\n' "$actual"); then
  echo "REPL smoke test: PASS ($(grep -c . tracker/repl-tests/smoke.expected) checks)"
else
  echo "REPL smoke test: FAIL"
  exit 1
fi
