#!/usr/bin/env bash
# EVALUATOR A/B bench for WP-6 stage 2 (tracker/JSON-WIDGET-PLAYGROUND.md, the
# Instruments row of section 11).  It answers ONE question: what does the
# cooperative-cancel check at the HEAD of `Runtime.swhnf` -- one volatile load
# and one null branch, in the binary whether the switch is on or off -- cost
# EVALUATION?
#
#   tracker/tools/eval-bench.sh --a <tree> --b <tree> --label <name>
#   tracker/tools/eval-bench.sh --a <tree> --b <tree> --label noise    # A vs A
#   tracker/tools/eval-bench.sh --a <tree> --diag --label c2           # C2 evidence
#
# `<tree>` is a checkout root (a worktree path).  Both sides must already be
# built: this script NEVER runs sbt, and NEVER edits a tree.  It reads each
# tree's own `target/ermine-classpath` and starts a plain `java -cp` REPL, so
# sbt's JVM cannot pollute a number.
#
# WHY NOT perf-bench.sh: that one is a TYPECHECKER bench (`tracker/PERF-ROADMAP.md`
# targets [B] batch load and [E] editor round trip).  A typechecker barely enters
# `swhnf`, so it would report "no movement" whatever the cost was.
#
# WHAT IT RUNS.  One JVM per FORK.  The session boots ONCE per fork (129 stdlib
# modules, `ermine.useInterface=false` so nothing writes an `.ei` into the tree),
# then the fork evaluates two workloads as REPL expressions, K times each, over
# a pipe; the timer is around the write of the expression and the read of its
# answer, so it measures parse + typecheck + EVALUATION of one line and nothing
# else.  Both workloads are pure: no IO, no scan, no printing beyond one Int.
#
#   W1 BUILD-AND-FOLD  `sum (range 0 200000)`
#       a strict left fold (`foldl f !z`) over a LAZILY produced list: every
#       cons cell is built and forced exactly once.  This is the ordinary
#       evaluation shape.
#   W2 REFOLD          `(xs -> sum xs + sum xs) (range 0 200000)`
#       the same list, folded TWICE through one shared binding.  The second
#       fold walks cells that are ALREADY `Evaluated`, which is `swhnf`'s
#       cheapest path and therefore its DENSEST: more `swhnf` calls per unit of
#       other work than W1.  W2 is the upper bound, W1 the realistic case.
#
# Answers are PINNED -- N(N-1)/2 and twice that, wrapped to a signed 32-bit
# `Int` (`-1474936480` and `1345094336` at the default N=200000) -- and a fork
# whose answer is wrong fails the run: a bench that measured a different
# computation on the two sides would be worse than no bench.
#
# THE FORKS ARE INTERLEAVED A,B,A,B,... so a machine that drifts during the run
# drifts through both sides.  The first W warm-up iterations of each workload in
# each fork are DISCARDED; the fork's figure is the MEDIAN of the rest.  A
# side's figure is the MEDIAN OF ITS FORK MEDIANS.
#
# ---------------------------------------------------------------------------
# THE NOISE STATISTIC, NAMED HERE BEFORE THE FIRST MEASURED RUN (condition 2 of
# the stage 1 review's four).  A decision rule whose threshold is chosen after
# the numbers are in is not a rule.
#
#   spread_AA  =  | median(A2) - median(A1) |  /  median(A1),  as a percent,
#
# where A1 and A2 are the two SIDES of a run in which BOTH sides are the SAME
# tree (`--label noise`), and median(X) is the median of that side's five fork
# medians.  It is deliberately the SAME statistic the A/B run reports as
# `B/A - 1`, computed where the true answer is known to be zero.  Reported
# alongside it, as dispersion and NOT as the threshold: the RANGE of each
# side's five fork medians.
#
#   DECISION RULE (unchanged from the design, per workload):
#     no movement  iff  |median(B) - median(A)|  <=  max(spread_AA, 2% of median(A))
#
# The instrument's RESOLUTION is that same `max(...)`: a real cost below it
# cannot be seen here and must be reported as "not distinguishable from noise",
# never as zero.
# ---------------------------------------------------------------------------
#
# --diag runs ONE fork of one side with -XX:+PrintCompilation into the log, for
# condition 4's C2 evidence, and measures nothing (PrintCompilation perturbs).
#
# REFUSES TO RUN while any FOREIGN Ermine JVM is alive -- an editor language
# server, a `bin/ermine`, a `ermine-serve`, or an sbt -- because a second JVM
# competing for cores is exactly what this instrument cannot survive.  The check
# is re-run BEFORE EVERY FORK, not once at the start.  It never kills anything.
#
# Env: JAVA_HOME (defaulted to the toolchain JDK), EVAL_BENCH_OUT (artifact dir),
#      EVAL_BENCH_TIMEOUT (default 300).  It caps the WHOLE boot and each WHOLE
#      iteration -- not one line read, which is what it used to cap and which
#      let a fork that kept emitting output run unbounded.
#
# EXIT CODES
#   0  the run completed; the summary line is on stdout
#   2  usage error (unknown flag, missing --a, --diag with --b, ...)
#   3  REFUSED: liveness shows a foreign Ermine JVM or an sbt, OR liveness
#      itself could not be read (the guard fails CLOSED).  Nothing was run
#   4  a tree is not usable: no target/ermine-classpath, or it names no classes
#   5  a fork failed: the REPL died, the boot or an iteration hit
#      EVAL_BENCH_TIMEOUT, or an answer was wrong.  The rows written so far are
#      kept as <label>.csv.partial -- NOT at the <label>.csv path, so a later
#      analysis cannot mistake a half-run for a run -- and named in the message
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
liveness="$here/../scripts/liveness.sh"
: "${JAVA_HOME:=$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
: "${EVAL_BENCH_OUT:=/tmp/eval-bench}"
: "${EVAL_BENCH_TIMEOUT:=300}"
export LC_ALL=C

# A value-taking flag with no value used to die on `set -u` with a raw bash
# message and exit 1, not the documented 2 (stage 2 review, nit).
need() { [ "$1" -ge 2 ] || { echo "eval-bench: $2 needs a value" >&2; exit 2; }; }

A=""; B=""; FORKS=5; K=15; WARMUP=5; LABEL="run"; DIAG=0; N=200000
while [ $# -gt 0 ]; do
  case "$1" in
    --a)      need "$#" --a;      A="$2"; shift ;;
    --b)      need "$#" --b;      B="$2"; shift ;;
    --forks)  need "$#" --forks;  FORKS="$2"; shift ;;
    -k)       need "$#" -k;       K="$2"; shift ;;
    --warmup) need "$#" --warmup; WARMUP="$2"; shift ;;
    --label)  need "$#" --label;  LABEL="$2"; shift ;;
    --size)   need "$#" --size;   N="$2"; shift ;;
    --diag)   DIAG=1 ;;
    # Print the leading comment block, however long it is.  A hard-coded line
    # range silently starts printing code the first time this file is edited,
    # which is what the stage 2 review caught.
    -h|--help) sed -n '2,$p' "$0" | sed -n '/^#/!q;p' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "eval-bench: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$A" ] || { echo "eval-bench: --a <tree> is required" >&2; exit 2; }
[ "$DIAG" = 1 ] && [ -n "$B" ] && { echo "eval-bench: --diag takes one side only" >&2; exit 2; }
[ "$DIAG" = 1 ] || [ -n "$B" ] || { echo "eval-bench: --b <tree> is required without --diag" >&2; exit 2; }
[ "$WARMUP" -lt "$K" ] || { echo "eval-bench: --warmup must be less than -k" >&2; exit 2; }

OUT="$EVAL_BENCH_OUT"
mkdir -p "$OUT" || { echo "eval-bench: cannot create $OUT" >&2; exit 2; }
CSV="$OUT/$LABEL.csv"
LOG="$OUT/$LABEL.log"

# The two workloads and their pinned answers, as ONE string each so that both
# sides are driven by byte-identical text from a single copy of this file.
W1_EXPR="sum (range 0 $N)"
W2_EXPR="(xs -> sum xs + sum xs) (range 0 $N)"
# The pinned answers, DERIVED from $N rather than typed in, so that --size
# cannot silently turn the correctness check off: sum(0..N-1) = N(N-1)/2, and
# W2 is twice that, each wrapped the way Ermine's `Int` wraps (32-bit, signed).
wrap32() { local v=$(( $1 % 4294967296 ))
           [ "$v" -ge 2147483648 ] && v=$(( v - 4294967296 ))
           echo "$v"; }
W1_WANT="$(wrap32 $(( N * (N - 1) / 2 )))"
W2_WANT="$(wrap32 $(( N * (N - 1) )))"

resolve() {  # a tree path -> its absolute root, or empty
  case "$1" in
    main) echo "$here/../ermine-scala" ;;
    /*)   echo "$1" ;;
    */*)  echo "$1" ;;
    *)    echo "$here/../ermine-scala-wt-$1" ;;
  esac
}

check_tree() {
  local t="$1" cpf="$1/target/ermine-classpath"
  [ -d "$t" ] || { echo "eval-bench: no such tree: $t" >&2; return 4; }
  [ -s "$cpf" ] || { echo "eval-bench: $cpf is missing or empty; build the tree first (sbt -batch 'export core/fullClasspath')" >&2; return 4; }
  local cls
  cls="$(head -c 4096 "$cpf" | tr ':' '\n' | grep -m1 'core/target/.*/classes')"
  [ -n "$cls" ] || { echo "eval-bench: $cpf names no core classes directory" >&2; return 4; }
  [ -f "$cls/com/clarifi/reporting/ermine/Runtime\$.class" ] || { echo "eval-bench: $cls holds no compiled Runtime; build the tree first" >&2; return 4; }
  [ -d "$cls/modules" ] || { echo "eval-bench: $cls holds no modules/ (run core/copyResources)" >&2; return 4; }
  return 0
}

liveness_ok() {  # 0 when the box is quiet enough to measure on
  local line
  line="$("$liveness" 2>/dev/null | head -1)"
  echo "$line" >> "$LOG"
  # FAIL CLOSED (stage 2 review, bug 2).  This used to take `head -1` of a
  # command that may not exist, default every missing count to 0, and return
  # SUCCESS -- so a missing or broken scripts/liveness.sh silently disabled the
  # whole refusal.  An unreadable answer is now a refusal, not a pass.
  case "$line" in
    live\ *) ;;
    *) echo "eval-bench: REFUSED, $liveness produced no usable status line" >&2
       [ -n "$line" ] && echo "  got: $line" >&2
       return 1 ;;
  esac
  local bad=""
  for k in sbt console lsp serve ermine-jvm; do
    local v
    v="$(echo "$line" | tr ' ' '\n' | sed -n "s/^$k=//p")"
    # A key that is ABSENT is also a refusal: it means this script and
    # liveness.sh disagree about the format, and silence would read as quiet.
    [ -z "$v" ] && { echo "eval-bench: REFUSED, no '$k=' field in the liveness line" >&2; return 1; }
    [ "$v" != "0" ] && bad="$bad $k=$v"
  done
  if [ -n "$bad" ]; then
    echo "eval-bench: REFUSED, a foreign JVM is alive:$bad" >&2
    echo "  $line" >&2
    return 1
  fi
  return 0
}

# ONE FORK.  $1 side label, $2 tree, $3 fork index.  Appends to $CSV.
run_fork() {
  local side="$1" tree="$2" idx="$3"
  local cp; cp="$(tr -d '\n' < "$tree/target/ermine-classpath")"
  local extra=()
  [ "$DIAG" = 1 ] && extra=(-XX:+PrintCompilation)
  local rc=0
  (
    cd "$tree" || exit 5
    coproc REPL { "$JAVA_HOME/bin/java" \
        -Dermine.typeCheck=true -Dermine.useInterface=false \
        -XX:+UseG1GC -Xms2g -Xmx2g "${extra[@]+"${extra[@]}"}" \
        -cp "$cp" com.clarifi.reporting.ermine.session.Console 2>&1; }
    # BUG FIXED (stage 2 review, bug 1): bash UNSETS REPL_PID once the coprocess
    # has gone, so under `set -u` the old `trap 'kill "$REPL_PID"' EXIT` raised
    # "REPL_PID: unbound variable" and THE KILL NEVER RAN -- a failed fork could
    # leave a JVM behind.  Guarded, and never `kill 0`, which would signal this
    # whole process group.
    cleanup_repl() {
      local pid="${REPL_PID:-}"
      case "$pid" in ''|0|*[!0-9]*) return 0 ;; esac
      kill "$pid" 2>/dev/null || true
    }
    trap cleanup_repl EXIT
    # EVAL_BENCH_TIMEOUT is now a cap on the WHOLE boot / the WHOLE iteration
    # (stage 2 review, bug 3).  It used to be a cap on ONE line read, so a fork
    # that kept emitting output -- exactly what -XX:+PrintCompilation does --
    # could run unbounded.  `remaining` turns the deadline back into the
    # fractional argument `read -t` wants.
    local deadline line rem
    remaining() { awk -v d="$1" -v n="$EPOCHREALTIME" 'BEGIN{ r = d - n; if (r < 0) r = 0; printf "%.2f", r }'; }
    # NEVER pass 0 to `read -t`: bash then returns SUCCESS whenever input is
    # merely available, WITHOUT consuming it, which would spin for ever.  The
    # expiry is tested here instead, before the read.
    deadline="$(awk -v a="$EPOCHREALTIME" -v t="$EVAL_BENCH_TIMEOUT" 'BEGIN{ printf "%.3f", a + t }')"
    local booted=0
    while :; do
      rem="$(remaining "$deadline")"; [ "$rem" = "0.00" ] && break
      IFS= read -r -t "$rem" -u "${REPL[0]}" line || break
      printf '%s\n' "$line" >> "$LOG"
      case "$line" in *"Loaded 129 modules"*) booted=1; break ;; esac
    done
    [ "$booted" = 1 ] || { echo "eval-bench: $side fork $idx never booted within ${EVAL_BENCH_TIMEOUT}s" >&2; exit 5; }
    local w expr want i t0 t1 got
    for w in 1 2; do
      if [ "$w" = 1 ]; then expr="$W1_EXPR"; want="$W1_WANT"
      else                  expr="$W2_EXPR"; want="$W2_WANT"; fi
      for (( i = 1; i <= K; i++ )); do
        t0=$EPOCHREALTIME
        printf '%s\n' "$expr" >&"${REPL[1]}"
        got=""
        deadline="$(awk -v a="$t0" -v t="$EVAL_BENCH_TIMEOUT" 'BEGIN{ printf "%.3f", a + t }')"
        while :; do
          rem="$(remaining "$deadline")"; [ "$rem" = "0.00" ] && break
          IFS= read -r -t "$rem" -u "${REPL[0]}" line || break
          printf '%s\n' "$line" >> "$LOG"
          case "$line" in *" : Int = "*) got="${line##* = }"; break ;; esac
        done
        t1=$EPOCHREALTIME
        [ -n "$got" ] || { echo "eval-bench: $side fork $idx W$w iter $i did not answer within ${EVAL_BENCH_TIMEOUT}s (or the REPL died)" >&2; exit 5; }
        [ "$got" = "$want" ] || { echo "eval-bench: $side fork $idx W$w iter $i answered '$got', wanted '$want'" >&2; exit 5; }
        awk -v s="$side" -v f="$idx" -v w="$w" -v i="$i" -v a="$t0" -v b="$t1" \
            -v k="$([ "$i" -le "$WARMUP" ] && echo warmup || echo measured)" \
            'BEGIN{ printf "%s,%d,W%s,%d,%s,%.6f\n", s, f, w, i, k, b-a }' >> "$CSV"
      done
    done
    printf ':quit\n' >&"${REPL[1]}"
    exit 0
  )
  rc=$?
  return $rc
}

for t in A B; do
  [ "$t" = B ] && [ -z "$B" ] && continue
  eval "p=\$$t"
  eval "$t=\"\$(resolve \"\$p\")\""
  eval "p=\$$t"
  check_tree "$p" || exit 4
done

: > "$CSV"; : > "$LOG"
echo "side,fork,workload,iter,kind,seconds" >> "$CSV"
{
  echo "== eval-bench $LABEL =="
  echo "date      $(date -Is)"
  echo "A         $A"
  [ -n "$B" ] && echo "B         $B"
  echo "forks     $FORKS   K=$K warmup=$WARMUP size=$N diag=$DIAG"
  echo "java      $("$JAVA_HOME/bin/java" -version 2>&1 | tr '\n' ' ')"
  echo "flags     -Dermine.typeCheck=true -Dermine.useInterface=false -XX:+UseG1GC -Xms2g -Xmx2g"
  echo "W1        $W1_EXPR   -> $W1_WANT"
  echo "W2        $W2_EXPR   -> $W2_WANT"
  echo "governor  $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unreadable)"
  echo "loadavg   $(cat /proc/loadavg)"
} >> "$LOG"

# A run that did not finish must not leave rows at the $LABEL.csv path, where a
# later stats pass would read a half-run as a run (stage 2 review, nit).
abandon() {
  local why="$1"
  if [ -s "$CSV" ]; then
    mv -f "$CSV" "$CSV.partial" 2>/dev/null &&
      echo "eval-bench: partial rows kept as $CSV.partial" >&2
  else
    rm -f "$CSV"
  fi
  exit "$why"
}

if [ "$DIAG" = 1 ]; then
  liveness_ok || abandon 3
  run_fork A "$A" 1 || abandon 5
  echo "eval-bench $LABEL: DIAG one fork of $A, PrintCompilation in $LOG"
  exit 0
fi

for (( f = 1; f <= FORKS; f++ )); do
  for side in A B; do
    eval "tree=\$$side"
    liveness_ok || abandon 3
    echo "eval-bench: $LABEL $side fork $f ..." >&2
    run_fork "$side" "$tree" "$f" || abandon 5
  done
done
echo "loadavg-end $(cat /proc/loadavg)" >> "$LOG"

# ---- summary -------------------------------------------------------------
summary="$(python3 - "$CSV" <<'PY'
import csv, statistics, sys, collections
rows = list(csv.DictReader(open(sys.argv[1])))
d = collections.defaultdict(list)
for r in rows:
    if r["kind"] == "measured":
        d[(r["side"], r["workload"], r["fork"])].append(float(r["seconds"]))
fm = collections.defaultdict(list)
for (s, w, f), xs in sorted(d.items()):
    fm[(s, w)].append(statistics.median(xs))
out = []
for w in ("W1", "W2"):
    if ("A", w) not in fm: continue
    a = statistics.median(fm[("A", w)]); ra = max(fm[("A", w)]) - min(fm[("A", w)])
    if ("B", w) in fm:
        b = statistics.median(fm[("B", w)]); rb = max(fm[("B", w)]) - min(fm[("B", w)])
        out.append(f"{w} A={a:.3f}s B={b:.3f}s ratio={b/a:.4f} rangeA={ra:.3f} rangeB={rb:.3f}")
        out.append("  forkmedians A: " + " ".join(f"{x:.3f}" for x in fm[("A", w)]))
        out.append("  forkmedians B: " + " ".join(f"{x:.3f}" for x in fm[("B", w)]))
    else:
        out.append(f"{w} A={a:.3f}s rangeA={ra:.3f}")
        out.append("  forkmedians A: " + " ".join(f"{x:.3f}" for x in fm[("A", w)]))
print("\n".join(out))
PY
)"
printf '%s\n' "$summary" >> "$LOG"
printf '%s\n' "$summary"
echo "eval-bench $LABEL: $FORKS forks/side, K=$K (first $WARMUP discarded), size=$N | csv=$CSV log=$LOG"
exit 0
