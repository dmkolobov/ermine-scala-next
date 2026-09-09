#!/usr/bin/env bash
# G1 differential oracle harness (tracker/LSP-ROADMAP.md, Stage 1 item 1.1).
#
#   g1-diff.sh run <old|new> <outdir>   full-inference boot; collect .ei tree
#                                       + normalized :browse + :groups dumps
#   g1-diff.sh compare <dirA> <dirB>    compare two collected runs
#   g1-diff.sh refresh-modules          regenerate tracker/tools/g1-modules.txt
#
# Discipline (do not weaken): every run deletes all .ei first — a warm
# interface-backed boot renders types differently and silently skips body
# inference, so it must never enter a comparison. Full-inference evidence
# is asserted via wall time.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
cp="$(tr -d '\n' < tracker/repl-classpath.txt)"
MODDIR=core/target/scala-3.3.8/classes/modules
MODLIST=tracker/tools/g1-modules.txt

# loadInSeries: deterministic Supply draws (thread timing otherwise reaches
# .ei bytes through the solver's id-hash queue — measured on lookbackJoin).
repl() { "$JAVA_HOME/bin/java" -Dermine.typeCheck=true -Dermine.loadInSeries=true \
           ${G1_PROPS:-} -cp "$cp" com.clarifi.reporting.ermine.session.Console; }

case "${1:-}" in
  refresh-modules)
    find "$MODDIR" -name '*.ei' -delete
    echo ':quit' | repl > /dev/null 2>&1
    find "$MODDIR" -name '*.ei' | sed "s|^$MODDIR/||; s|\.ei$||; s|/|.|g" | sort > "$MODLIST"
    echo "$(wc -l < "$MODLIST") modules -> $MODLIST";;
  run)
    pipe="${2:?old|new}"; out="${3:?outdir}"
    # post-G1 D3: the fused pipeline is retired — there is only one
    # pipeline to boot, and 'old' would silently collect the same data
    [[ $pipe == old ]] && { echo "g1-diff: 'old' retired at D3 (fused pipeline removed)" >&2; exit 2; }
    G1_PROPS=
    export G1_PROPS
    [[ -s $MODLIST ]] || { echo "run 'g1-diff.sh refresh-modules' first" >&2; exit 2; }
    mkdir -p "$out"; out="$(cd "$out" && pwd)"; rm -rf "$out/ei"
    find "$MODDIR" -name '*.ei' -delete
    t0=$SECONDS
    printf ':browse\n:quit\n' | repl > "$out/transcript.raw" 2> "$out/stderr.log"
    wall=$((SECONDS - t0)); echo "$wall" > "$out/wall-seconds.txt"
    (( wall > 10 )) || { echo "FAIL: ${wall}s wall <= 10s — interface-backed boot?" >&2; exit 1; }
    mkdir -p "$out/ei"
    (cd "$MODDIR" && find . -name '*.ei' -exec cp --parents {} "$out/ei/" \;)
    nei=$(find "$out/ei" -name '*.ei' | wc -l); nexp=$(wc -l < "$MODLIST")
    [[ $nei -eq $nexp ]] || { echo "FAIL: $nei .ei files, expected $nexp" >&2; exit 1; }
    # SIGNATURE lines only: since stage S5.2 every `.ei` opens with the
    # solver-configuration key (`-- ermine-interface <format>|<GenRules>`), which is not
    # a signature.  Counting it pushed 1447 to 1576 and ate half the band's headroom
    # (S5 review, Q-8); excluding it keeps the number comparable to every earlier run.
    nlines=$(cat $(find "$out/ei" -name '*.ei') | grep -v '^-- ermine-interface ' | grep -c .)
    (( nlines >= 1300 && nlines <= 1700 )) || { echo "FAIL: $nlines sig lines outside [1300,1700]" >&2; exit 1; }
    python3 tracker/tools/g1-normalize.py "$out/transcript.raw" "$out" || exit 1
    # SCC groups via the dedicated tool (the REPL's :groups cannot re-parse
    # most loaded modules); warm boot is fine — parse-only, no rendering.
    "$JAVA_HOME/bin/java" ${G1_PROPS:-} -cp "$cp" \
      com.clarifi.reporting.ermine.tools.G1Groups > "$out/groups.txt" 2>> "$out/stderr.log" || exit 1
    # Sanity ceiling, not a fingerprint.  This asserted exactly 5 until
    # 2026-08-31, which was a pre-Stage-1 snapshot: the split pipeline
    # re-parses two modules the fused one could not (Native.List, Relation),
    # so the count is 3 and the remaining three fail for a DIFFERENT reason
    # (unknown operator, i.e. fixity not in scope for a standalone re-parse,
    # rather than a layout failure).  A magic equality here reported that
    # improvement as a gate failure.  Drift between runs is caught by the
    # groups.txt diff in `compare`, which is the right instrument for it.
    npe=$(grep -c "PARSE-ERROR" "$out/groups.txt")
    (( npe <= 8 )) || { echo "FAIL: groups PARSE-ERROR count $npe > 8" >&2; exit 1; }
    echo "OK: $pipe run — $nei modules, $nlines sig lines, $npe group parse-errors, ${wall}s -> $out";;
  compare)
    a="${2:?dirA}"; b="${3:?dirB}"; rc=0
    "$JAVA_HOME/bin/java" -cp "$cp" com.clarifi.reporting.ermine.tools.G1Compare "$a/ei" "$b/ei" || rc=1
    diff -u "$a/browse.txt" "$b/browse.txt" > /tmp/g1-browse.diff || { echo "DIFF browse: /tmp/g1-browse.diff"; rc=1; }
    diff -u "$a/groups.txt" "$b/groups.txt" > /tmp/g1-groups.diff || { echo "DIFF groups: /tmp/g1-groups.diff"; rc=1; }
    if [[ $rc -eq 0 ]]; then echo "G1 COMPARE: EQUIVALENT"; else echo "G1 COMPARE: DIFFERS"; fi
    exit $rc;;
  *) echo "usage: g1-diff.sh run <old|new> <outdir> | compare <a> <b> | refresh-modules" >&2; exit 2;;
esac
