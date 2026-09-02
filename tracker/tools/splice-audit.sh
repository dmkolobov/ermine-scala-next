#!/usr/bin/env bash
# Measure `Subst.reduce` case 2 over the EXAMPLES, which is the only corpus that can show
# anything: ticket §7.9 measured ZERO of 383 stdlib solve inputs carrying a concrete label,
# against 39% in core/examples.  A figure for this taken from a stdlib boot is meaningless.
#
#   tracker/tools/splice-audit.sh /tmp/splice
#   ERMINE_JAVA_OPTS="-Dermine.spliceGuard=true" tracker/tools/splice-audit.sh /tmp/splice-on
#
# One JVM per file, `-Dermine.useInterface=false` and a fresh `.ei` sweep so the solver
# really runs (see corpus-run.sh).  Every invocation APPENDS to the same trace, so the
# summary covers the whole corpus.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
out="${1:?usage: splice-audit.sh <outdir>}"
mkdir -p "$out"
trace="$out/trace.tsv"
: > "$trace"
find core/examples -name '*.ei' -delete

files=( core/examples/*.e core/examples/Ai/*.e )
for f in "${files[@]}"; do
  args=( "$f" )
  case "$f" in
    core/examples/Ai/Common.e) ;;
    core/examples/Ai/*)        args=( core/examples/Ai/Common.e "$f" ) ;;
  esac
  ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.rowTrace=$trace ${ERMINE_JAVA_OPTS:-}" \
    timeout 180 bin/ermine "${args[@]}" </dev/null > "$out/$(basename "$f").out" 2>&1
done

echo "== ${#files[@]} example modules, trace at $trace"
python3 tracker/tools/rowtrace-summary.py "$trace"
echo
echo "== non-conservative splices, per file (hlhs/hdis/hdup from splice_entails_iff)"
awk -F'\t' '$1=="splice" && NF>=11 && !($9=="true" && $10=="true" && $11=="true") {
  print $3, "changed="$8, "hlhs="$9, "hdis="$10, "hdup="$11 }' "$trace" | sort | uniq -c | sort -rn | head -30
