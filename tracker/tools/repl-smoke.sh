#!/usr/bin/env bash
# Run every tracker/repl-tests/*.in through the REPL and diff its answers
# against the matching *.expected.
#
#   sbt -batch 'export core/fullClasspath' | tail -1 > tracker/repl-classpath.txt
#   tracker/tools/repl-smoke.sh
#
# Interface caching is off so each run exercises real inference; with it on the
# second run answers from the cached .ei files instead, which prints types in a
# more explicit (but equivalent) form.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
cp="$(tr -d '\n' < tracker/repl-classpath.txt)"

fail=0
for input in tracker/repl-tests/*.in; do
  name=$(basename "$input" .in)
  expected="tracker/repl-tests/$name.expected"
  actual=$(
    "$JAVA_HOME/bin/java" -Dermine.typeCheck=true -Dermine.useInterface=false \
      ${REPL_PIPELINE:--Dermine.pipeline=new} \
      -cp "$cp" com.clarifi.reporting.ermine.session.Console < "$input" 2>&1 |
    sed -n '/Loaded [0-9]* modules/,$p' |   # drop banner and startup module list
    tail -n +2 |                            # drop the "Loaded N modules" line
    grep -v '^  ' |                         # drop :import's module listing
    grep -v 'Importing module\|Loaded module' |  # timing varies run to run
    grep -v '^Imports:\|^Files:\|^Modules:' |   # :import's session summary
    sed 's/^>> //; s/^>>$//' |              # strip prompts
    grep -v '^$'
  )
  if diff -u "$expected" <(printf '%s\n' "$actual") > /tmp/repl-smoke-$name.diff 2>&1; then
    echo "  PASS  $name ($(grep -c . "$expected") checks)"
  else
    echo "  FAIL  $name"
    cat /tmp/repl-smoke-$name.diff
    fail=1
  fi
done
exit $fail
