#!/usr/bin/env bash
# Reproducible performance harness for the two targets in tracker/PERF-ROADMAP.md.
# This script is the MEASUREMENT OF RECORD (Decision 2): ad-hoc timings are not
# evidence, and every commit that claims a speedup quotes a before and an after
# from here, on the same machine, with the repetition count.
#
#   tracker/tools/perf-bench.sh                    # both targets, default reps
#   tracker/tools/perf-bench.sh batch -n 5         # [B] cold, interface-free
#   tracker/tools/perf-bench.sh batch --warm -n 5  # [B] with the .ei cache
#   tracker/tools/perf-bench.sh editor -k 15       # [E] K didChange round trips
#
# Env: JAVA_HOME (defaulted), PERF_OUT (artifact dir, default /tmp/perf-bench),
#      PERF_MAX_LOAD (refuse above this 1-minute load average, default 1.5),
#      PERF_JVM_PROPS (extra flags injected into BOTH JVMs -- this is how P2
#      hangs -XX:StartFlightRecording off the harness instead of hand-rolling a
#      different command line and quietly ceasing to be the measurement of
#      record; the unquoted-expansion idiom is g1-diff.sh's G1_PROPS).
#
# [B] BATCH: N loads of the 129-module stdlib closure, each in a FRESH JVM,
# because cold JIT is what a batch user actually pays.  The primary number is
# the one the program computes for itself -- "Loaded 129 modules (X.XX
# seconds)" -- not the shell's wall clock, which also folds in JVM startup, the
# logo and Lib.preamble.  Both are recorded; only the first is comparable.
#
# [E] EDITOR: one boot, then K didChange -> publishDiagnostics round trips
# through tracker/tools/perf-client.py, which pins the edit site and asserts
# the reuse counters.  Warm JVM, warm session, warm per-uri inference cache:
# that IS the editor's steady state.
#
# TRAPS THIS SCRIPT EXISTS TO CLOSE (all of them cost a measurement if missed):
#  - ermine.useInterface DEFAULTS TO TRUE and ermine.typeCheck DEFAULTS TO
#    FALSE (SessionState.scala:98-100).  Get one wrong and the run still looks
#    plausible while measuring nothing: without typeCheck every binding loads
#    as `forall a. a`, and with useInterface a "cold" rep repopulates all 129
#    .ei and contaminates every rep after it.
#  - The .ei delete MUST be scoped to the module tree.  `find . -name '*.ei'
#    -delete` from the repo root would destroy 143 TRACKED files -- the whole
#    G1 golden baseline and the comparator fixtures.  g1-diff.sh scopes it
#    correctly and this script cross-checks that it and g1-diff.sh agree on
#    the directory.
#  - The "Loaded ..." text does NOT start a line: the progress bar writes \r
#    frames with no newline, so an anchored grep finds nothing.  And ordinal()
#    spells small counts as WORDS ("Loaded two modules" under loadInSeries,
#    "Loaded no modules" when the closure is empty), which defeats a numeric
#    regex -- so a rep is validated on the captured count being exactly 129,
#    never on the exit code, which is 0 even after a panic.
#  - Decimal separators come from the default FORMAT locale in both the batch
#    DecimalFormat and the LSP's f-interpolation, so both JVMs are pinned to
#    en_US and every capture accepts [0-9.,].
set -uo pipefail
# The JVMs are pinned to en_US below; pin the shell side too, so `sort -n` and
# awk cannot disagree with the numbers they are parsing under a comma-decimal
# locale.  Both settings resolve to a '.' separator, so this changes no result
# on an en_US machine -- it removes a way for the harness to be wrong elsewhere.
export LC_ALL=C
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
OUT="${PERF_OUT:-/tmp/perf-bench}"
MAX_LOAD="${PERF_MAX_LOAD:-1.5}"

MODE=both; REPS=5; ROUNDS=15; WARM=0
TARGET_FILE=core/src/main/resources/modules/Layout/Report.e
while [ $# -gt 0 ]; do
  case "$1" in
    batch|editor|both) MODE=$1 ;;
    -n) REPS=$2; shift ;;
    -k) ROUNDS=$2; shift ;;
    --warm) WARM=1 ;;
    --file) TARGET_FILE=$2; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "perf-bench: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

fail() { echo "FAIL: $*" >&2; exit 2; }
mkdir -p "$OUT" "$OUT/cwd" || fail "cannot create $OUT"

# median/min/max/spread over numbers on stdin (median, not mean: one scheduling
# hiccup must not move the headline figure).
stats() {
  sort -n | awk '{a[NR]=$1} END {
    if (NR==0) { print "NA NA NA NA"; exit }
    m = (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2
    printf "%.2f %.2f %.2f %.2f\n", m, a[1], a[NR], a[NR]-a[1] }'
}

# --- preflight -------------------------------------------------------------
[ -x "$JAVA_HOME/bin/java" ] || fail "no java at $JAVA_HOME/bin/java"
[ -s tracker/repl-classpath.txt ] || fail \
  "tracker/repl-classpath.txt missing; regenerate with
      sbt -batch 'export core/fullClasspath' | tail -1 > tracker/repl-classpath.txt"
cp="$(tr -d '\n' < tracker/repl-classpath.txt)"
classes="$(cut -d: -f1 tracker/repl-classpath.txt)"
moddir="$classes/modules"
[ -d "$moddir" ] || fail "module tree $moddir does not exist (compile first)"

# The two harnesses must never disagree about which tree holds the interfaces.
g1_moddir="$(sed -n 's/^MODDIR=//p' tracker/tools/g1-diff.sh)"
[ "$moddir" = "$here/$g1_moddir" ] || fail \
  "module tree disagreement: perf-bench derives $moddir from the classpath,
   g1-diff.sh hardcodes $here/$g1_moddir"

# Measuring a stale build measures nothing.  Nothing else in tracker/tools
# checks this; a perf harness has to.
newest() { find "$@" -printf '%T@\n' 2>/dev/null | sort -rn | head -1; }
# 2s of slack: sbt's resource copy PRESERVES the source mtime but truncates it
# to millisecond precision, so a freshly copied file reads as microseconds
# OLDER than its source.  Without the tolerance this guard cries stale on a
# perfectly current tree.
staler_than() { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{exit !(a>b+2)}'; }
src_t="$(newest core/src/main/scala parsers/src/main/scala -name '*.scala')"
cls_t="$(newest "$classes" -name '*.class')"
staler_than "$src_t" "$cls_t" && fail \
  "sources are newer than $classes -- run 'sbt -batch core/compile' first"
res_t="$(newest core/src/main/resources/modules -name '*.e')"
mod_t="$(newest "$moddir" -name '*.e')"
staler_than "$res_t" "$mod_t" && fail \
  "module sources are newer than $moddir -- run 'sbt -batch core/compile' first"

# Another live ermine JVM writes .ei into the same tree with a truncating
# PrintWriter, which corrupts a warm rep and false-fails the cold assertion.
# NOTE THE ESCAPED DOTS.  Unescaped, `com.clarifi.reporting.ermine` is a regex
# whose dots match the SLASHES in the source path
# core/src/main/scala/com/clarifi/reporting/ermine/Type.scala -- so ANY process
# merely naming a source file (an editor, a build, or this harness's own paired
# before/after script, which lists those paths in a variable) matched, and the
# run was silently refused.  It cost two measurement runs before the message was
# read carefully.  Requiring a java invocation as well means a shell that only
# mentions the class does not count either.
ermine_jvm="$(pgrep -af 'com\.clarifi\.reporting\.ermine\.' 2>/dev/null | grep '/java ' | head -1)"
[ -n "$ermine_jvm" ] && fail "another ermine JVM is running: $ermine_jvm"
pgrep -f 'sbt-launch|xsbt\.boot' >/dev/null 2>&1 && fail "an sbt build is running"

load_before="$(cut -d' ' -f1 /proc/loadavg)"
awk -v l="$load_before" -v m="$MAX_LOAD" 'BEGIN{exit !(l>m)}' && fail \
  "1-minute load average is $load_before (max $MAX_LOAD); wall time is only
   meaningful on a quiet machine -- raise PERF_MAX_LOAD to override"

commit="$(git rev-parse --short HEAD 2>/dev/null)"
[ -z "$(git status --porcelain 2>/dev/null)" ] && dirty=clean || dirty=DIRTY
javaver="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | tr -d '"')"
heap_mb="$("$JAVA_HOME/bin/java" -XX:+PrintFlagsFinal -version 2>/dev/null |
  awk '/ MaxHeapSize/{printf "%d", $4/1048576}')"
ei_before="$(find "$moddir" -name '*.ei' | wc -l)"

echo "-- perf-bench: $MODE, commit $commit ($dirty), $(hostname) --"
echo "   java $javaver, max heap ${heap_mb}MB, load $load_before, .ei present $ei_before"

# Locale is pinned so the harness's own regexes cannot be defeated by a
# comma-decimal default (both the batch DecimalFormat and the LSP's %.2f go
# through the default FORMAT locale).
LOCALE_PROPS=(-Duser.language=en -Duser.country=US)

batch_median=NA; batch_wall_median=NA; batch_label=none
editor_line=""

# --- [B] batch -------------------------------------------------------------
run_batch() {
  local secs_f="$OUT/batch-$batch_label-secs.txt" wall_f="$OUT/batch-$batch_label-wall.txt"
  : > "$secs_f"; : > "$wall_f"
  local i t0 t1 out n secs
  for i in $(seq 1 "$REPS"); do
    t0=$(date +%s.%N)
    # Run from a scratch cwd: Console points jline's HISTORY_FILE at
    # ./.ermine_history, and the repo's copy is 165KB that every rep would
    # otherwise load and append to.  The 129 modules resolve through the
    # classloader to absolute paths, so cwd does not affect what is loaded.
    out="$(cd "$OUT/cwd" && "$JAVA_HOME/bin/java" \
             -Dermine.typeCheck=true "${IFACE_PROPS[@]}" "${LOCALE_PROPS[@]}" \
             ${PERF_JVM_PROPS:-} -cp "$cp" \
             com.clarifi.reporting.ermine.session.Console < /dev/null 2>&1)"
    t1=$(date +%s.%N)
    out="$(printf '%s' "$out" | tr '\r' '\n')"
    local reply="$OUT/batch-$batch_label-rep$i.log"
    printf '%s\n' "$out" > "$reply"
    case "$out" in
      *panic:*) fail "rep $i panicked; see $reply" ;;
      *"Unable to load"*) fail "rep $i failed to load the prelude; see $reply" ;;
    esac
    n="$(printf '%s' "$out" | sed -n 's/.*Loaded \([0-9][0-9]*\) modules.*/\1/p' | tail -1)"
    secs="$(printf '%s' "$out" | sed -n 's/.*Loaded [0-9][0-9]* modules (\([0-9][0-9.,]*\) seconds).*/\1/p' | tail -1)"
    [ "$n" = "129" ] || fail \
      "rep $i loaded '${n:-<no numeric count>}' modules, expected 129 -- a
   word-spelled count means loadInSeries or an empty closure; see $reply"
    secs="${secs//,/.}"
    echo "$secs" >> "$secs_f"
    awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f\n", b-a}' >> "$wall_f"
    printf '   rep %d/%d: %ss in-process, %ss wall\n' "$i" "$REPS" "$secs" \
      "$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')"
  done
  read -r batch_median bmin bmax bspread < <(stats < "$secs_f")
  read -r batch_wall_median wmin wmax wspread < <(stats < "$wall_f")
  echo "   $batch_label median ${batch_median}s in-process (min $bmin, max $bmax, spread $bspread) over $REPS reps"
  echo "   $batch_label median ${batch_wall_median}s wall (min $wmin, max $wmax) -- NOT comparable across commits"
}

if [ "$MODE" = batch ] || [ "$MODE" = both ]; then
  if [ "$WARM" = 1 ]; then
    batch_label=warm
    IFACE_PROPS=()   # ermine.useInterface defaults to true: read AND write .ei
    echo "-- [B] batch, WARM (.ei interface cache on) --"
    echo "   priming run (discarded) to populate the interface cache..."
    (cd "$OUT/cwd" && "$JAVA_HOME/bin/java" -Dermine.typeCheck=true \
       "${LOCALE_PROPS[@]}" ${PERF_JVM_PROPS:-} -cp "$cp" \
       com.clarifi.reporting.ermine.session.Console < /dev/null) >/dev/null 2>&1
    ei_primed="$(find "$moddir" -name '*.ei' | wc -l)"
    [ "$ei_primed" = "129" ] || fail \
      "priming left $ei_primed .ei files, expected 129 -- the cache is not warm"
    run_batch
  else
    batch_label=cold
    IFACE_PROPS=(-Dermine.useInterface=false)
    echo "-- [B] batch, COLD (interface-free, full inference) --"
    find "$moddir" -name '*.ei' -delete || fail "could not clear .ei in $moddir"
    run_batch
    ei_after="$(find "$moddir" -name '*.ei' | wc -l)"
    [ "$ei_after" = "0" ] || fail \
      "$ei_after .ei files appeared during a useInterface=false run -- the
   writeback gate moved (Session.scala:407) and every rep after the first was
   contaminated"
    echo "   .ei after: 0 (interface-free confirmed)"
  fi
fi

# --- [E] editor ------------------------------------------------------------
if [ "$MODE" = editor ] || [ "$MODE" = both ]; then
  echo "-- [E] editor round trip, $ROUNDS rounds on $TARGET_FILE --"
  [ -f "$TARGET_FILE" ] || fail "no such target file: $TARGET_FILE"
  # The buffer we edit must be the file the session would otherwise load: the
  # resident session resolves imports through the classpath copy, not the
  # source tree.
  rel="${TARGET_FILE#core/src/main/resources/modules/}"
  if [ "$rel" != "$TARGET_FILE" ] && [ -f "$moddir/$rel" ]; then
    cmp -s "$TARGET_FILE" "$moddir/$rel" || fail \
      "$TARGET_FILE and $moddir/$rel differ -- the buffer under edit would not
   match the module its importers resolve to; run 'sbt -batch core/compile'"
  fi
  log="$OUT/editor-lsp.log"; : > "$log"   # the server opens it in APPEND mode
  # Edit-site overrides, for benching a file other than the pinned default
  # (PERF_EDIT_MODE=space is the portable edit: doubling a mid-line space is
  # type-neutral on any line, and layout only reads a line's FIRST column).
  edit=()
  [ -n "${PERF_EDIT_LINE:-}" ]   && edit+=(--line "$PERF_EDIT_LINE")
  [ -n "${PERF_EDIT_ANCHOR:-}" ] && edit+=(--anchor "$PERF_EDIT_ANCHOR")
  [ -n "${PERF_EDIT_MODE:-}" ]   && edit+=(--mode "$PERF_EDIT_MODE")
  python3 tracker/tools/perf-client.py \
    --rounds "$ROUNDS" --file "$TARGET_FILE" --log "$log" \
    --out "$OUT/editor.json" --stderr "$OUT/editor-server.stderr" "${edit[@]}" \
    -- "$JAVA_HOME/bin/java" -Dermine.lsp.log="$log" "${LOCALE_PROPS[@]}" \
       ${PERF_JVM_PROPS:-} -cp "$cp" com.clarifi.reporting.ermine.lsp.Main \
    | tee "$OUT/editor.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail "editor bench failed; log: $log"
  editor_line="$(sed -n 's/^PERFBENCH-EDITOR //p' "$OUT/editor.txt")"
fi

# --- summary ---------------------------------------------------------------
load_after="$(cut -d' ' -f1 /proc/loadavg)"
ei_end="$(find "$moddir" -name '*.ei' | wc -l)"
echo "PERFBENCH commit=$commit tree=$dirty host=$(hostname) java=${javaver// /_}" \
     "heap_mb=$heap_mb load_before=$load_before load_after=$load_after" \
     "batch_mode=$batch_label batch_reps=$REPS" \
     "batch_${batch_label}_median_s=$batch_median batch_wall_median_s=$batch_wall_median" \
     "ei_before=$ei_before ei_after=$ei_end ${editor_line}"
echo "   artifacts in $OUT"
