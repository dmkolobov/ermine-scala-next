#!/usr/bin/env bash
# One serialized `-Dermine.rowTrace` pass per example module, counted by splitkey-counts.py:
# how often does `splitConcrete` MINT, syntactically REUSE, and (with -Dermine.splitKey=true)
# KEYED-REUSE, on real code?  Companion of tracker/tools/keptdef-sweep.sh, same shape.
#
#   tracker/tools/splitkey-sweep.sh /tmp/sk-off                          # flag off
#   SPLITKEY=true tracker/tools/splitkey-sweep.sh /tmp/sk-on             # flag on
#
# `-Dermine.loadInSeries=true` is REQUIRED (the analyser segments by `solve` records).
# `-Dermine.useInterface=false`, so this sweep neither reads nor WRITES `.ei` and can run
# beside an `ei-diff.sh` sweep without clobbering it.  Traces are deleted after analysis
# unless KEEP_TRACES=1 (they are ~8 MB each, 110 of them).
set -uo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
S="${1:?usage: splitkey-sweep.sh <outdir>}"
mkdir -p "$S/per-file"
: > "$S/results.tsv"
extra=""; [[ ${SPLITKEY:-} == true ]] && extra="-Dermine.splitKey=true"
mapfile -t files < <(find core/examples -name '*.e' | sort)
n=0
for f in "${files[@]}"; do
  n=$((n+1))
  args=( "$f" )
  case "$f" in
    core/examples/Ai/Common.e) ;;
    core/examples/Ai/*)        args=( core/examples/Ai/Common.e "$f" ) ;;
  esac
  tag=$(echo "${f#core/examples/}" | tr '/' '_')
  tr="$S/trace-$tag.tsv"; rm -f "$tr" "$tr.gz"
  ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx1500m -Dermine.useInterface=false -Dermine.loadInSeries=true -Dermine.rowTrace=$tr $extra" \
    timeout "${SPLITKEY_TIMEOUT:-240}" bin/ermine "${args[@]}" </dev/null > "$S/per-file/$tag.out" 2>&1
  rc=$?
  verdict=$(grep -q "Unable to load module" "$S/per-file/$tag.out" && echo REJECTED || echo LOADED)
  [[ $rc == 124 ]] && verdict=TIMEOUT
  line=$(python3 tracker/tools/splitkey-counts.py "$tr" --filter core/examples --tag "$tag" 2>&1)
  printf '%s\t%s\t%s\n' "$verdict" "$line" "$f" >> "$S/results.tsv"
  printf '%3d/%d %-8s %s\n' "$n" "${#files[@]}" "$verdict" "$line"
  if [[ ${KEEP_TRACES:-0} == 1 ]]; then gzip -f "$tr"; else rm -f "$tr"; fi
done
echo "done $(date)" >> "$S/results.tsv"
