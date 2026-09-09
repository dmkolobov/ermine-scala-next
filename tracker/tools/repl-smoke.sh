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
# LSP-FFI: a tiny self-contained jar whose classes LOAD but whose supertype
# and member signatures name a class that is NOT there -- the shape of a stale
# jar of the user's fork.  Built from tracker/lsp-tests/jsrc so no third-party
# library's contents can silence the linkage fixtures.
cp="$cp:$(tracker/tools/build-probejar.sh)" || exit 1

fail=0
for input in tracker/repl-tests/*.in; do
  name=$(basename "$input" .in)
  expected="tracker/repl-tests/$name.expected"
  raw="/tmp/repl-smoke-$name.raw"
  # F1/A2: a TIMEOUT and an exit-code check.  `Console.other` used to reopen the
  # `|>` continuation for any line merely CONTAINING "case"/"let"/"where" and to
  # treat `readLine`'s null at EOF as a non-blank line, so a piped session could
  # spin for ever; `pipedeof.in` is exactly such an input and without a cap it
  # would hang this suite instead of failing it.
  # Per-case JVM flags: `<name>.opts`, one line of flags.  Only cases that
  # need a session option have one (LSP-FFI's `ermine.foreign.tolerant`),
  # so every existing case runs on exactly the command line it always did.
  opts=()
  [[ -f "tracker/repl-tests/$name.opts" ]] && read -r -a opts < "tracker/repl-tests/$name.opts"
  timeout "${REPL_SMOKE_TIMEOUT:-180}" \
    "$JAVA_HOME/bin/java" -Dermine.typeCheck=true -Dermine.useInterface=false \
      ${opts[@]+"${opts[@]}"} \
      -cp "$cp" com.clarifi.reporting.ermine.session.Console < "$input" > "$raw" 2>&1
  rc=$?
  actual=$(
    cat "$raw" |
    sed -n '/Loaded [0-9]* modules/,$p' |   # drop banner and startup module list
    tail -n +2 |                            # drop the "Loaded N modules" line
    grep -v '^  ' |                         # drop :import's module listing
    grep -v 'Importing module\|Loaded module' |  # timing varies run to run
    sed 's/ ([0-9]*\.[0-9]* seconds)//' |   # ... and so does a failed load's
    grep -v '^Imports:\|^Files:\|^Modules:' |   # :import's session summary
    sed 's/^>> //; s/^>>$//' |              # strip prompts
    grep -v '^$'
  )
  if [[ $rc != 0 ]]; then
    echo "  FAIL  $name (the REPL exited $rc$([[ $rc == 124 ]] && echo ' — timed out'); raw: $raw)"
    fail=1
    continue
  fi
  if diff -u "$expected" <(printf '%s\n' "$actual") > /tmp/repl-smoke-$name.diff 2>&1; then
    echo "  PASS  $name ($(grep -c . "$expected") checks)"
  else
    echo "  FAIL  $name"
    cat /tmp/repl-smoke-$name.diff
    fail=1
  fi
done
exit $fail
