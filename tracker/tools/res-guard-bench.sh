#!/usr/bin/env bash
# Time the ResStar family with and without `-Dermine.resGuard`, one JVM per module.
#
#   tracker/tools/gen-res-star.py --out /tmp/resprobe --star-to 6
#   tracker/tools/res-guard-bench.sh /tmp/resprobe /tmp/resbench
#
# Writes <outdir>/<module>-<off|on>.tsv row traces and prints a table of
# wall time / saturated partitions / Resolution derivations for each side.
#
# One JVM per module, always: a module that diverges must not hide the others, and the
# loader StackOverflows on batch loads (tracker/ROW-CONSTRAINT-STATE.md, "Traps").
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"

probes="${1:?usage: res-guard-bench.sh <probedir> <outdir>}"
out="${2:?usage: res-guard-bench.sh <probedir> <outdir>}"
timeout_s="${RES_TIMEOUT:-300}"
mkdir -p "$out"

printf '%-12s %-5s %8s %8s %8s %8s\n' module guard wall sat derived resolution

for f in "$probes"/*.e; do
  m="$(basename "$f" .e)"
  for g in false true; do
    tag=$([ "$g" = true ] && echo on || echo off)
    trace="$out/$m-$tag.tsv"
    : > "$trace"
    start=$(date +%s.%N)
    ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.resGuard=$g -Dermine.rowTrace=$trace" \
      timeout "$timeout_s" bin/ermine "$f" </dev/null > "$out/$m-$tag.out" 2>&1
    rc=$?
    end=$(date +%s.%N)
    wall=$(echo "$end - $start" | bc)
    if [[ $rc == 124 ]]; then
      printf '%-12s %-5s %8s %8s %8s %8s\n' "$m" "$tag" TIMEOUT - - -
      continue
    fi
    # count only the records for THIS module's own file, not the 129-module boot
    sat=$(awk -F'\t' -v m="$m" '$1=="solve" && index($3,m".e")>0 {s+=$6} END{print s+0}' "$trace")
    der=$(awk -F'\t' -v m="$m" '$1=="solve" && index($3,m".e")>0 {s+=$7} END{print s+0}' "$trace")
    res=$(awk -F'\t' -v m="$m" '$1=="solve" && index($3,m".e")>0 {
             n=split($10,a,","); for(i=1;i<=n;i++){ split(a[i],b,":"); if(b[1]=="Resolution") s+=b[2] }
           } END{print s+0}' "$trace")
    printf '%-12s %-5s %8.1f %8s %8s %8s\n' "$m" "$tag" "$wall" "$sat" "$der" "$res"
  done
done
