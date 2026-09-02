#!/usr/bin/env bash
# Diff the PUBLISHED SIGNATURES the compiler emits, under two flag settings.
#
#   tracker/tools/ei-diff.sh /tmp/eidiff "-Dermine.spliceGuard=true"
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
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
out="${1:?usage: ei-diff.sh <outdir> [flags-for-side-B]}"
flagsB="${2:--Dermine.spliceGuard=true}"
mkdir -p "$out"

STDLIB=core/target/scala-3.3.8/classes/modules

sweep() {  # sweep <snapshot-dir> <flags>
  local snap="$1"; shift
  local flags="$1"; shift
  rm -rf "$snap"; mkdir -p "$snap"
  find core/examples "$STDLIB" -name '*.ei' -delete 2>/dev/null
  mapfile -t files < <(find core/examples -name '*.e' | sort)
  for f in "${files[@]}"; do
    local args=( "$f" )
    case "$f" in
      core/examples/Ai/Common.e) ;;
      core/examples/Ai/*)        args=( core/examples/Ai/Common.e "$f" ) ;;
    esac
    ERMINE_JAVA_OPTS="$flags" timeout "${EI_TIMEOUT:-120}" \
      bin/ermine "${args[@]}" </dev/null > /dev/null 2>&1
  done
  # snapshot both trees, flattened, so the diff is by module name
  for e in $(find core/examples "$STDLIB" -name '*.ei' | sort); do
    cp "$e" "$snap/$(echo "${e#./}" | tr '/' '_')"
  done
  echo "  $(ls "$snap" | wc -l) interfaces captured"
}

echo "== side A: default flags"
sweep "$out/A" ""
echo "== side B: $flagsB"
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
