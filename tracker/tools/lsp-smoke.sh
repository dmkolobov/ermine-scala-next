#!/usr/bin/env bash
# Smoke-test the Ermine language server end to end: spawn it on stdio, run
# the scripted client (tracker/tools/lsp-client.py) over the fixtures in
# tracker/lsp-tests/, PASS/FAIL like repl-smoke.sh.
#
#   sbt -batch 'export core/fullClasspath' | tail -1 > tracker/repl-classpath.txt
#   tracker/tools/lsp-smoke.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
cp="$(tr -d '\n' < tracker/repl-classpath.txt)"
export LSP_SMOKE_LOG="${LSP_SMOKE_LOG:-/tmp/lsp-smoke.log}"
: > "$LSP_SMOKE_LOG"
timeout 120 python3 tracker/tools/lsp-client.py \
  "$JAVA_HOME/bin/java" -Dermine.lsp.log="$LSP_SMOKE_LOG" \
  -cp "$cp" com.clarifi.reporting.ermine.lsp.Main
rc=$?
[ $rc -eq 124 ] && echo "  FAIL  lsp (timed out; log: $LSP_SMOKE_LOG)"
exit $rc
