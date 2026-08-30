#!/usr/bin/env bash
# Drive the Ermine REPL non-interactively and show only its responses.
#
#   tracker/tools/repl-test.sh < expressions.txt
#   printf '1 + 2\n:quit\n' | tracker/tools/repl-test.sh
#
# Requires core/fullClasspath exported to $CLASSPATH_FILE (see repl-classpath).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
: "${CLASSPATH_FILE:=$here/tracker/repl-classpath.txt}"
cp="$(tr -d '\n' < "$CLASSPATH_FILE")"
"$JAVA_HOME/bin/java" -Dermine.typeCheck=true -cp "$cp" com.clarifi.reporting.ermine.session.Console 2>&1 |
  # drop the banner, the module list and the load progress bar
  sed -n '/Loaded [0-9]* modules/,$p'
