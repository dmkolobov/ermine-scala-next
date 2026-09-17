#!/usr/bin/env bash
# measure.sh NAME -- CMD...   run CMD in the gate-audit worktree, log to NAME.log, append a TSV row
set -uo pipefail
S=/home/dmitry/research/ermine/scratch-gate-audit/measure
W=${MEASURE_WT:-/home/dmitry/research/ermine/ermine-scala-wt-gate-audit}
name=$1; shift; [[ $1 == -- ]] && shift
export PATH=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$HOME/.local/ermine-toolchain/bin:$HOME/.elan/bin:$PATH
export JAVA_HOME=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1
cd "$W"
l0=$(cut -d' ' -f1 /proc/loadavg); t0=$(date +%s.%N); d0=$(date -Is)
"$@" > "$S/$name.log" 2>&1; rc=$?
t1=$(date +%s.%N); l1=$(cut -d' ' -f1 /proc/loadavg)
secs=$(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.1f", b-a}')
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$d0" "$secs" "$rc" "$l0" "$l1" "$(git rev-parse --short HEAD)" "$W" >> "$S/measurements.tsv"
echo "$name secs=$secs exit=$rc load=$l0->$l1"
