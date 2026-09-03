#!/usr/bin/env bash
# Drive run.sh over a base range, restarting in a FRESH JVM whenever the in-process
# hung-thread limit (exit 3) is hit, so abandoned spinning threads never pile up.
#   tracker/repro/satterm/sweep.sh <seed> <from> <to> [capSec] [maxHung]   > out.txt
# The per-JVM SUMMARY lines are kept; the final TOTAL line aggregates them.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sd=$1; from=$2; to=$3; shift 3
next=$from
S=0; R=0; H=0; O=0
while (( next <= to )); do
  out=$("$here/run.sh" sweep "$sd" "$next" "$to" "$@" 2>&1); rc=$?
  printf '%s\n' "$out"
  s=$(printf '%s\n' "$out" | sed -n 's/^SUMMARY .* SOLVED=\([0-9]*\) REJECTED=\([0-9]*\) HANG=\([0-9]*\) OOM=\([0-9]*\).*/\1 \2 \3 \4/p')
  if [[ -n $s ]]; then read -r a b c d <<< "$s"; S=$((S+a)); R=$((R+b)); H=$((H+c)); O=$((O+d)); fi
  if (( rc == 3 )); then
    next=$(printf '%s\n' "$out" | sed -n 's/^HUNGLIMIT .*next=\([0-9]*\).*/\1/p')
    [[ -z $next ]] && { echo "driver: no next base after exit 3"; exit 1; }
    echo "driver: fresh JVM from base $next"
  else
    (( rc != 0 )) && echo "driver: run.sh exit $rc"
    break
  fi
done
echo "TOTAL seed=$sd bases=$from..$to SOLVED=$S REJECTED=$R HANG=$H OOM=$O"
