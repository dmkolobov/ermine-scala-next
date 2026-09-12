#!/usr/bin/env bash
# The GATE G4 demo run: spawn the language server exactly the way lsp-smoke.sh
# does, drive tracker/tools/lsp-demo.py over the fixtures, and print the
# transcript on stdout.
#
#   tracker/tools/lsp-demo.sh > tracker/lsp-tests/G4-demo.txt
#
# This is evidence, not a test: lsp-smoke.sh is the regression harness.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
cp="$(tr -d '\n' < tracker/repl-classpath.txt)"
export LSP_DEMO_LOG="${LSP_DEMO_LOG:-/tmp/lsp-demo.log}"
: > "$LSP_DEMO_LOG"
timeout 180 python3 tracker/tools/lsp-demo.py \
  "$JAVA_HOME/bin/java" -Dermine.lsp.log="$LSP_DEMO_LOG" \
  -cp "$cp" com.clarifi.reporting.ermine.lsp.Main
rc=$?
[ $rc -eq 124 ] && echo "  FAIL  lsp-demo (timed out; log: $LSP_DEMO_LOG)" >&2
exit $rc
