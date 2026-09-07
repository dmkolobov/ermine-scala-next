#!/usr/bin/env bash
# Stage L2 of tracker/LOOP-MODEL-PLAN.md: run the Lean loop model on EVERY `Subst.solve` the
# compiler performs on the corpus, and diff the two traces record for record.
#
#   tracker/tools/looptrace-corpus.sh <outdir>                       # boot + all 110 examples
#   LOOPTRACE_GROUPS="boot top" tracker/tools/looptrace-corpus.sh <outdir>
#   LOOPTRACE_FLAGS=--flags=emptyrow LOOPTRACE_JAVA=-Dermine.emptyRow=true ...   (flag variant)
#
# How it works.  `-Dermine.rowTrace` now writes, at the top of every `solve`, the four REPLAY
# records `RowTrace.scala` documents -- `sin` (the `Supply`'s bounds, and the segment
# boundary), `slbl` (the label table), `svar` (every input variable's `VarType` and name) and
# `scon` (the constraint list with each element's `hashCode` and `equals` class).  That is
# exactly what `lake exe looptrace --replay` needs to re-run the same solve in the Lean model
# at the compiler's own ids, so the two traces can be compared BYTE for byte with no
# normalisation.  `tracker/tools/looptrace-diff.py --segments` splits both sides at the `sin`
# records / the model's `#seg` markers, pairs them by index and classifies each pair.
#
# `-Dermine.loadInSeries=true` is the DEFAULT here (`LOOPTRACE_SERIES=true`): a segmentation
# that splits the file at every `sin` assumes one solve's records are contiguous, and a
# parallel load interleaves them.  `-Dermine.useInterface=false` and the `.ei` deletions are
# the standard corpus hygiene -- a second run would otherwise read the interfaces the first
# wrote and never run the solver.
#
# LOOPTRACE_SERIES=false runs the SHIPPED parallel loader instead (stage L4).  Every record
# now ends with a thread id (`RowTrace.log`), so the trace can be regrouped per thread into
# one in which each solve's records ARE contiguous; the script inserts that step
# (`looptrace-diff.py --demux`) before the model replay, and both the replay and the diff
# then read the regrouped file.  The `demux=` field of the results line reports how many
# segments were interleaved in the raw trace, i.e. how many the regrouping repaired.
#
# One JVM per corpus DIRECTORY, as `keptdef-sweep.sh --batch` does, so the ~18 s stdlib boot
# is paid once per group instead of once per file.  `incomplete/` is the exception and runs
# PER FILE (`LOOPTRACE_PERFILE`): several of its modules are non-terminating by design, and
# under `-Dermine.rowTrace` a diverging solve writes ~8 MB/s for as long as it is left alone.
# A file that hits its timeout has its LAST segment cut off at the trailing `sin`, because
# that segment's records stop wherever the kill landed and would diff as a false mismatch;
# the count of dropped segments is reported.  Under LOOPTRACE_SERIES=false that cut is not
# thread-aware -- it takes the last `sin` in FILE order, so up to one segment per THREAD can be
# left truncated instead of one.  It fails LOUDLY if it ever fires rather than agreeing falsely:
# a truncated segment either loses its `scon` block, and the model answers
# `skip: scon count != nCs` (a SKIP, counted as bad, exit 1), or loses trailing records the
# model recomputes (`length+`, also bad).  Cut per thread when this becomes worth fixing.  Traces are gzipped: disk here is tight.
set -uo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
LOOPTRACE_BIN="${LOOPTRACE_BIN:-$here/tracker/lean/.lake/build/bin/looptrace}"
S="${1:?usage: looptrace-corpus.sh <outdir>}"
mkdir -p "$S/traces" "$S/lean" "$S/diff"
: > "$S/results.txt"
find core/examples -name '*.ei' -delete

groups="${LOOPTRACE_GROUPS:-boot top Ai Wide Wide-shouldfail shouldfail bugs guide shouldfail-controls incomplete}"
perfile=" ${LOOPTRACE_PERFILE:-incomplete} "
flags="${LOOPTRACE_FLAGS:-}"
jopts="${LOOPTRACE_JAVA:-}"
series="${LOOPTRACE_SERIES:-true}"
if [[ "$series" == true ]]; then sopt="-Dermine.loadInSeries=true"; else sopt=""; fi

for g in $groups; do
  tr="$S/traces/$g.tsv"; rm -f "$tr" "$tr.gz"
  : > "$tr"
  case "$g" in
    boot) gf=() ;;
    top)  mapfile -t gf < <(find core/examples -maxdepth 1 -name '*.e' | sort) ;;
    Ai)   mapfile -t gf < <( { echo core/examples/Ai/Common.e
                               find core/examples/Ai -name '*.e' ! -name 'Common.e' | sort; } ) ;;
    # Wide/ is the Ai/ case with a different library: every Wide module imports
    # `Wide.Helpers`, and so does every module under Wide/shouldfail, so the library
    # goes first on both command lines (stage E1, 2026-09-06).
    Wide) mapfile -t gf < <( { echo core/examples/Wide/Helpers.e
                               find core/examples/Wide -maxdepth 1 -name '*.e' \
                                    ! -name 'Helpers.e' | sort; } ) ;;
    Wide-shouldfail)
          mapfile -t gf < <( { echo core/examples/Wide/Helpers.e
                               find core/examples/Wide/shouldfail -maxdepth 1 -name '*.e' \
                                 | sort; } ) ;;
    *)    mapfile -t gf < <(find "core/examples/$g" -maxdepth 1 -name '*.e' | sort) ;;
  esac
  t0=$(date +%s); dropped=0; timeouts=0
  if [[ "$perfile" == *" $g "* ]]; then
    for f in "${gf[@]}"; do
      one="$S/traces/.one.tsv"; rm -f "$one"
      ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx${LOOPTRACE_XMX:-3000m} -Dermine.useInterface=false $sopt $jopts -Dermine.rowTrace=$one" \
        timeout "${LOOPTRACE_FILE_TIMEOUT:-120}" bin/ermine "$f" </dev/null >> "$S/$g.out" 2>&1
      frc=$?
      cap="${LOOPTRACE_FILE_CAP:-300000000}"
      sz=$(stat -c%s "$one" 2>/dev/null || echo 0)
      if [[ $frc == 124 || $sz -gt $cap ]]; then
        [[ $frc == 124 ]] && timeouts=$((timeouts+1))
        # A diverging solve writes ~8 MB/s for as long as it is left alone, so cap the
        # bytes as well as the seconds; cutting at the last `sin` makes either cut safe.
        if [[ $sz -gt $cap ]]; then head -c "$cap" "$one" > "$one.cap" && mv "$one.cap" "$one"; fi
        # cut the interrupted solve: everything from the LAST `sin` to EOF
        last=$(grep -n $'^sin\t' "$one" | tail -1 | cut -d: -f1)
        if [[ -n "$last" ]]; then head -n $((last-1)) "$one" > "$one.cut" && mv "$one.cut" "$one"; fi
        dropped=$((dropped+1))
      fi
      cat "$one" >> "$tr"; rm -f "$one"
    done
    rc=0
  else
    ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx${LOOPTRACE_XMX:-3000m} -Dermine.useInterface=false $sopt $jopts -Dermine.rowTrace=$tr" \
      timeout "${LOOPTRACE_TIMEOUT:-2400}" bin/ermine ${gf[@]+"${gf[@]}"} </dev/null \
      > "$S/$g.out" 2>&1
    rc=$?
  fi
  t1=$(date +%s)
  nseg=$(grep -c $'^sin\t' "$tr" 2>/dev/null)
  # The parallel loader interleaves the records of concurrent solves, and `looptrace
  # --replay` has no notion of a thread: regroup by the trace's thread-id column first, and
  # let BOTH sides read the regrouped file so the segment indices line up.
  dmx="-"
  rep="$tr"
  if [[ "$series" != true ]]; then
    dmx=$(python3 tracker/tools/looptrace-diff.py --demux "$tr" --out "$tr.dx" \
            | sed -n 's/.*interleaved=\([0-9]*\).*/\1/p')
    rep="$tr.dx"
  fi
  t2=$(date +%s%3N)
  timeout "${LOOPTRACE_MODEL_TIMEOUT:-7200}" "$LOOPTRACE_BIN" --replay "$rep" $flags \
    > "$S/lean/$g.out" 2> "$S/lean/$g.err"
  mrc=$?
  t3=$(date +%s%3N)
  python3 tracker/tools/looptrace-diff.py --segments --lean "$S/lean/$g.out" \
      --scala "$rep" --report "$S/diff/$g.txt" --show 6 --per-thread > /dev/null 2>&1
  agree=$(awk '$1=="AGREE"{print $2}' "$S/diff/$g.txt")
  skip=$(awk '$1=="SKIP"{print $2}' "$S/diff/$g.txt")
  cls=$(awk '$1=="class"{printf "%s=%s ", $2, $3}' "$S/diff/$g.txt")
  thr=$(awk '$1=="threads:"{print $2}' "$S/diff/$g.txt")
  printf '%-20s files=%-3s ermine=%ss(rc=%s,timeouts=%s,dropped=%s) segments=%-6s threads=%-3s demux=%-6s model=%sms(rc=%s) agree=%-6s skip=%-4s %s\n' \
    "$g" "${#gf[@]}" "$((t1-t0))" "$rc" "$timeouts" "$dropped" "$nseg" "$thr" "$dmx" \
    "$((t3-t2))" "$mrc" "$agree" "$skip" "$cls" | tee -a "$S/results.txt"
  gzip -f "$tr"
  [[ -f "$tr.dx" ]] && gzip -f "$tr.dx"
done
find core/examples -name '*.ei' -delete
echo "done $(date)" >> "$S/results.txt"
