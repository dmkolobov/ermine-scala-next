#!/usr/bin/env bash
# One serialized `-Dermine.rowTrace` pass per example module, analysed by keptdef-mints.py
# (PROMPT-default-termination.md, Q2: do the definitions `destructiveSub` keeps reach
# `splitConcrete` and mint?).  Per-file lines go to <outdir>/results.txt; traces are kept
# gzipped under <outdir>/ for re-analysis (`keptdef-mints.py --show N` on a `zcat`).
#
#   tracker/tools/keptdef-sweep.sh /tmp/keptdef          # ~45 min: 110 modules x (stdlib boot + module)
#   tracker/tools/keptdef-sweep.sh --batch /tmp/keptdef  # ~4 min: 4 JVMs, one per directory
#
# Measured 2026-09-02 (110 modules, solve locations under core/examples only; the stdlib boot
# has 0 makeConcrete steps and so 0 of everything below):
#   kept-definition dequeues 715 (329 strict = the kept definition itself, 386 derived from one)
#   with a nonempty concrete part 284 (42 strict); splitConcrete MINTED 156 (24 strict), REUSED 128
#   modules with a mint 27 (14 with a mint on the kept definition itself)
# The positive control is tracker/repro/keepmint/run.sh (16 of 32 configurations mint).
# `-Dermine.loadInSeries=true` is REQUIRED: the analyser segments the trace by `solve` records,
# and a parallel load interleaves the records of different solves.
#
# --batch (2026-09-03, possible since the loader stopped overflowing on batch loads --
# TICKET-editor-and-solver-followups.md item 4): one JVM per corpus DIRECTORY instead of one
# per file, so the ~11 s stdlib boot is paid four times.  The per-solve segmentation survives
# it: `Subst.scala`'s `solve` record carries the solve's source LOC, so the analyser's
# `--filter` picks one file's solves out of a whole group's trace, and `loadInSeries=true`
# keeps each solve's records contiguous exactly as before.  Two things do change, and the
# per-file mode stays the default because of them:
#   * `Ai/Common.e` is loaded ONCE in a batch and once per Ai module per file, so its solves
#     are counted once instead of ten times in any aggregate over the group;
#   * every module is compiled in a session that already holds the modules ahead of it.
# The groups are not merged into one JVM: `incomplete/gu05` solves in 0.4 s in a fresh
# session and runs for minutes in one that already holds the 66-file corpus.
set -uo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
batch=0
if [[ ${1:-} == "--batch" ]]; then batch=1; shift; fi
S="${1:?usage: keptdef-sweep.sh [--batch] <outdir>}"
mkdir -p "$S/per-file"
: > "$S/results.txt"
find core/examples -name '*.ei' -delete
mapfile -t files < <(find core/examples -name '*.e' | sort)

report() {  # report <n> <file> <verdict> <trace>
  local n="$1" f="$2" verdict="$3" tr="$4"
  local tag; tag=$(echo "${f#core/examples/}" | tr '/' '_')
  python3 tracker/tools/keptdef-mints.py "$tr" --filter "$f" > "$S/per-file/$tag.kept" 2>&1
  local summary; summary=$(grep -E "kept-definition dequeues|NONEMPTY|MINTED|REUSED" "$S/per-file/$tag.kept" |
                             sed 's/^[^:]*: *//' | tr '\n' ' ')
  printf '%3d/%d %-60s %-8s %s\n' "$n" "${#files[@]}" "$f" "$verdict" "$summary" | tee -a "$S/results.txt"
}

if [[ $batch == 1 ]]; then
  n=0
  for g in top Ai shouldfail incomplete; do
    case "$g" in
      top)  mapfile -t gf < <(find core/examples -maxdepth 1 -name '*.e' | sort) ;;
      Ai)   mapfile -t gf < <( { echo core/examples/Ai/Common.e
                                 find core/examples/Ai -name '*.e' ! -name 'Common.e' | sort; } ) ;;
      *)    mapfile -t gf < <(find "core/examples/$g" -name '*.e' | sort) ;;
    esac
    [[ ${#gf[@]} == 0 ]] && continue
    tr="$S/trace-$g.tsv"; rm -f "$tr" "$tr.gz"
    ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx${KEPTDEF_XMX:-2500m} -Dermine.useInterface=false -Dermine.loadInSeries=true -Dermine.rowTrace=$tr" \
      timeout "${KEPTDEF_BATCH_TIMEOUT:-1800}" bin/ermine "${gf[@]}" </dev/null > "$S/per-file/batch-$g.out" 2>&1
    python3 tracker/tools/batch-split.py "$S/per-file/batch-$g.out" "$S/per-file" "${gf[@]}" || exit 1
    for f in "${gf[@]}"; do
      n=$((n+1))
      tag=$(echo "${f#core/examples/}" | tr '/' '_')
      verdict=$(grep -q "Unable to load module" "$S/per-file/$tag.out" && echo REJECTED || echo LOADED)
      report "$n" "$f" "$verdict" "$tr"
    done
    gzip -f "$tr"
  done
  find core/examples -name '*.ei' -delete
  echo "done $(date)" >> "$S/results.txt"
  exit 0
fi

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
