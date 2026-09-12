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
# LSP-FFI: a tiny self-contained jar whose classes LOAD but whose supertype
# and member signatures name a class that is NOT there -- the shape of a stale
# jar of the user's fork.  Built from tracker/lsp-tests/jsrc so no third-party
# library's contents can silence the linkage fixtures.
cp="$cp:$(tracker/tools/build-probejar.sh)" || exit 1
export LSP_SMOKE_LOG="${LSP_SMOKE_LOG:-/tmp/lsp-smoke.log}"
: > "$LSP_SMOKE_LOG"
# SIG-3: the signature-entailment mode the SERVER runs in.  Unset means the shipped
# default (`error`), which is what a user's editor does; `ERMINE_SIGENTAIL=off` drives the
# same fixtures with the check off, and `tracker/lsp-tests/SigEntail.e`'s block in
# lsp-client.py reads the same variable so its expectation follows the server's.
export ERMINE_SIGENTAIL="${ERMINE_SIGENTAIL:-error}"
timeout 120 python3 tracker/tools/lsp-client.py \
  "$JAVA_HOME/bin/java" -Dermine.lsp.log="$LSP_SMOKE_LOG" \
  -Dermine.sigEntail="$ERMINE_SIGENTAIL" \
  -cp "$cp" com.clarifi.reporting.ermine.lsp.Main
rc=$?
[ $rc -eq 124 ] && echo "  FAIL  lsp (timed out; log: $LSP_SMOKE_LOG)"
exit $rc
