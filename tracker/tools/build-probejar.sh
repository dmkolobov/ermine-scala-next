#!/usr/bin/env bash
# Build the LSP-FFI probe jar and print its path (LSP-FFI, findings P-1/P-7).
#
#   cp="$(tr -d '\n' < tracker/repl-classpath.txt):$(tracker/tools/build-probejar.sh)"
#
# The jar holds four tiny classes from tracker/lsp-tests/jsrc/probejar and,
# deliberately, NOT the `Missing` class they all mention.  That reproduces the
# shape of a stale jar of the user's fork -- classes that are present but whose
# supertype or member signatures name a type this JVM does not have -- with no
# dependence on what some third-party library happens to ship this month.
#
# Rebuilds only when a source is newer than the jar.  Everything lands in
# target/, which is gitignored; only the .java sources are checked in, so a
# reviewer can see exactly what the fixtures are asserting against.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
src="$here/tracker/lsp-tests/jsrc"
out="$here/target/lsp-ffi-probejar"
jar="$here/target/lsp-ffi-probejar.jar"

# `ls | head` would trip pipefail on SIGPIPE; pick the newest without a pipe.
newest=""
for f in "$src"/probejar/*.java; do
  [[ -z $newest || $f -nt $newest ]] && newest="$f"
done
if [[ ! -f $jar || $newest -nt $jar ]]; then
  rm -rf "$out"; mkdir -p "$out"
  "$JAVA_HOME/bin/javac" -nowarn -d "$out" "$src"/probejar/*.java >&2
  # THE POINT: compile against Missing, then take it away.
  rm -f "$out/probejar/Missing.class"
  "$JAVA_HOME/bin/jar" --create --file "$jar" -C "$out" probejar >&2
fi
echo "$jar"
