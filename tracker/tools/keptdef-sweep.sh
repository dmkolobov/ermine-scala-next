#!/usr/bin/env bash
# One serialized `-Dermine.rowTrace` pass per example module, analysed by keptdef-mints.py
# (PROMPT-default-termination.md, Q2: do the definitions `destructiveSub` keeps reach
# `splitConcrete` and mint?).  Per-file lines go to <outdir>/results.txt; traces are kept
# gzipped under <outdir>/ for re-analysis (`keptdef-mints.py --show N` on a `zcat`).
#
#   tracker/tools/keptdef-sweep.sh /tmp/keptdef          # ~45 min: 110 modules x (stdlib boot + module)
#
# Measured 2026-09-02 (110 modules, solve locations under core/examples only; the stdlib boot
# has 0 makeConcrete steps and so 0 of everything below):
#   kept-definition dequeues 715 (329 strict = the kept definition itself, 386 derived from one)
#   with a nonempty concrete part 284 (42 strict); splitConcrete MINTED 156 (24 strict), REUSED 128
#   modules with a mint 27 (14 with a mint on the kept definition itself)
# The positive control is tracker/repro/keepmint/run.sh (16 of 32 configurations mint).
# `-Dermine.loadInSeries=true` is REQUIRED: the analyser segments the trace by `solve` records,
# and a parallel load interleaves the records of different solves.
set -uo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
S="${1:?usage: keptdef-sweep.sh <outdir>}"
mkdir -p "$S/per-file"
: > "$S/results.txt"
find core/examples -name '*.ei' -delete
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
  ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx1500m -Dermine.useInterface=false -Dermine.loadInSeries=true -Dermine.rowTrace=$tr" \
    timeout "${KEPTDEF_TIMEOUT:-180}" bin/ermine "${args[@]}" </dev/null > "$S/per-file/$tag.out" 2>&1
  rc=$?
  verdict=$(grep -q "Unable to load module" "$S/per-file/$tag.out" && echo REJECTED || echo LOADED)
  [[ $rc == 124 ]] && verdict=TIMEOUT
  python3 tracker/tools/keptdef-mints.py "$tr" --filter core/examples > "$S/per-file/$tag.kept" 2>&1
  summary=$(grep -E "kept-definition dequeues|NONEMPTY|MINTED|REUSED" "$S/per-file/$tag.kept" | sed 's/^[^:]*: *//' | tr '\n' ' ')
  printf '%3d/%d %-60s %-8s %s\n' "$n" "${#files[@]}" "$f" "$verdict" "$summary" | tee -a "$S/results.txt"
  gzip -f "$tr"
done
find core/examples -name '*.ei' -delete
echo "done $(date)" >> "$S/results.txt"
