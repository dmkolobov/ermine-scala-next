#!/usr/bin/env bash
# Diff the PUBLISHED SIGNATURES the compiler emits, under two flag settings.
#
#   tracker/tools/ei-diff.sh /tmp/eidiff "-Dermine.spliceGuard=true"
#   tracker/tools/ei-diff.sh --batch /tmp/eidiff "-Dermine.spliceGuard=true"
#   tracker/tools/ei-diff.sh /tmp/eictl ""     # same-configuration control, both sides
#
# WHY.  `.ei` interface files are what the compiler publishes: the constraint context that
# a downstream module actually sees.  Ticket item 8b says `Subst.reduce`'s splice can make
# that context WEAKER than the constraints the user wrote, and the trace says 90% of splices
# cannot be proved conservative (21141 of 23410 over the example corpus).  But "cannot be
# proved conservative" is not "loses information".  This diff measures the difference that
# actually reaches an interface, which is the only version of the question a user can see.
#
# METHOD, and the trap it is built around.  `bin/ermine` WRITES `.ei` and, by default, READS
# them -- so the second side of a naive A/B reads what the first side wrote (that invalidated
# a 66-file comparison earlier today; see ROW-CONSTRAINT-STATE.md).  Here every `.ei` is
# deleted before each side, and interfaces are deliberately left ENABLED, because
# `-Dermine.useInterface=false` suppresses writing as well as reading and would leave nothing
# to diff.  Within a side a later module may read an earlier module's interface -- that is
# symmetric across sides and is what makes signature changes PROPAGATE, which is the effect
# worth seeing.
#
# --batch: load the corpus FIVE FILES AT A TIME in one JVM instead of one JVM per file, so
# a side pays the ~12 s stdlib boot 22 times instead of 110.  Possible at all only since
# the loader's dependency-order computation was made iterative on 2026-09-03
# (TICKET-editor-and-solver-followups.md item 4); before that a batch load overflowed the
# stack partway through.  READ THE NEXT PARAGRAPH BEFORE USING IT.
#
# The chunk is FIVE, not a directory and not the corpus, and the sweep still does not come
# out whole.  Every module in a batch is compiled in a session that already holds the ones
# ahead of it, and WITH INTERFACES ENABLED -- which this script requires -- that gets
# expensive fast: `incomplete/gu05` takes 1.09 s alone, 26.9 s behind `gu01`+`gu04` in one
# JVM (7.5 s with `useInterface=false`), and minutes behind the 66-file corpus, all of it
# in `Constraints` (`PQueue.contains`, `learnPartitions`), none of it in the loader.
# Measured 2026-09-03 over the 110-file corpus, chunk 5, 180 s per chunk: a side takes
# 8m41s against 13m45s per file (1.6x), TWO chunks hit the timeout and the sweep captures
# 185 interfaces instead of 188; against a per-file side, 19 of 185 differ (1866 bindings
# identical, 31 order-only, 11 alpha-equivalent, 11 other) where a per-file CONTROL differs
# on PFCTL.  Use --batch for BOTH sides of an A/B, where the losses and the churn are
# symmetric, and never for one side against a per-file side.
#
# PER FILE IS STILL THE DEFAULT.  A batch loads each module into a session that already
# holds every module ahead of it, which is a different compilation from a virgin session --
# measured 2026-09-03 over the whole corpus, per-file vs batch, in `TICKET-editor-and-solver-
# followups.md` item 4.  Use --batch for both sides of an A/B, never for one side of one.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
batch=0
if [[ ${1:-} == "--batch" ]]; then batch=1; shift; fi
out="${1:?usage: ei-diff.sh [--batch] <outdir> [flags-for-side-B]}"
flagsB="${2:--Dermine.spliceGuard=true}"
mkdir -p "$out"

STDLIB=core/target/scala-3.3.8/classes/modules

# How many files one batched JVM loads (see the header: five, and it still loses two
# chunks to the timeout on this corpus).
CHUNK="${EI_BATCH_CHUNK:-5}"

sweep() {  # sweep <snapshot-dir> <flags>
  local snap="$1"; shift
  local flags="$1"; shift
  rm -rf "$snap"; mkdir -p "$snap"
  find core/examples "$STDLIB" -name '*.ei' -delete 2>/dev/null
  if [[ $batch == 1 ]]; then
    mapfile -t all < <(find core/examples -name '*.e' | sort)
    local i=0 k=0
    while (( i < ${#all[@]} )); do
      local chunk=( "${all[@]:i:CHUNK}" ) gf=()
      # an Ai module cannot resolve Ai.Common on its own, so every chunk that holds one
      # gets Common.e at its head (it is loaded again in its own chunk, harmlessly)
      case " ${chunk[*]} " in
        *" core/examples/Ai/"*) [[ " ${chunk[*]} " == *" core/examples/Ai/Common.e "* ]] ||
                                  gf=( core/examples/Ai/Common.e ) ;;
      esac
      gf+=( "${chunk[@]}" )
      ERMINE_JAVA_OPTS="$flags" timeout "${EI_BATCH_TIMEOUT:-180}" \
        bin/ermine "${gf[@]}" </dev/null > "$snap.chunk$k.log" 2>&1
      i=$(( i + CHUNK )); k=$(( k + 1 ))
    done
  else
    mapfile -t files < <(find core/examples -name '*.e' | sort)
    local f
    for f in "${files[@]}"; do
      local args=( "$f" )
      case "$f" in
        core/examples/Ai/Common.e) ;;
        core/examples/Ai/*)        args=( core/examples/Ai/Common.e "$f" ) ;;
      esac
      ERMINE_JAVA_OPTS="$flags" timeout "${EI_TIMEOUT:-120}" \
        bin/ermine "${args[@]}" </dev/null > /dev/null 2>&1
    done
  fi
  # snapshot both trees, flattened, so the diff is by module name
  for e in $(find core/examples "$STDLIB" -name '*.ei' | sort); do
    cp "$e" "$snap/$(echo "${e#./}" | tr '/' '_')"
  done
  echo "  $(ls "$snap" | wc -l) interfaces captured"
}

echo "== side A: default flags$([[ $batch == 1 ]] && echo ' (batch)')"
sweep "$out/A" ""
echo "== side B: $flagsB$([[ $batch == 1 ]] && echo ' (batch)')"
sweep "$out/B" "$flagsB"

echo
echo "== interfaces present on one side only"
diff <(ls "$out/A") <(ls "$out/B") || true
echo
echo "== interfaces whose CONTENT differs"
n=0
for f in "$out"/A/*; do
  b="$out/B/$(basename "$f")"
  [ -f "$b" ] || continue
  if ! diff -q "$f" "$b" >/dev/null; then
    echo "--- $(basename "$f")"
    diff "$f" "$b" | head -12
    n=$((n+1))
  fi
done
echo
echo "== $n of $(ls "$out/A" | wc -l) published interfaces differ"
echo "   (0 = the splice loses nothing that reaches an interface, on this corpus)"
