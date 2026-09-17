# Gate registry for scripts/gate.sh and scripts/mutate-and-verify.sh (sourced, not executed).
# docs/gate-policy.md is the policy; this file is its executable form.  Each gate is:
#   GATE_TIER     commit | pr | nightly | manual   (commit gates also run for pr, pr gates for nightly)
#   GATE_TIMEOUT  seconds before the run is killed and recorded as FAIL
#   GATE_DESC     one line
#   GATE_SCOPE    source globs the gate claims to guard: where the mutation harness draws mutants.
#                 Empty = not mutation-testable, with the reason in GATE_NOSCOPE.
#   gate_<name>   the run, in the worktree root; prints a `SUMMARY ...` line; exit 0 PASS,
#                 1 FAIL, 3 UNAVAILABLE (a precondition is missing, so it did not run)
# shellcheck shell=bash

GATE_ORDER=""
declare -A GATE_TIER=() GATE_TIMEOUT=() GATE_DESC=() GATE_SCOPE=() GATE_NOSCOPE=() GATE_KEYPATH=()

E=core/src/main/scala/com/clarifi/reporting/ermine

gate_def() {  # gate_def NAME TIER TIMEOUT "DESC"
  GATE_ORDER="$GATE_ORDER $1"; GATE_TIER[$1]=$2; GATE_TIMEOUT[$1]=$3; GATE_DESC[$1]=$4
}

tier_includes() {  # tier_includes REQUESTED GATE_TIER
  case "$1" in
    commit)  [[ $2 == commit ]] ;;
    pr)      [[ $2 == commit || $2 == pr ]] ;;
    nightly) [[ $2 == commit || $2 == pr || $2 == nightly ]] ;;
    *) return 1 ;;
  esac
}

gate_env() {
  export JAVA_HOME="$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1"
  export PATH="$JAVA_HOME/bin:$HOME/.local/ermine-toolchain/bin:$HOME/.elan/bin:$PATH"
  # the tools write fixed file names under TMPDIR; a private one lets gates run side by side
  if [[ -n ${GATE_OUT:-} ]]; then export TMPDIR="$GATE_OUT/tmp"; mkdir -p "$TMPDIR"; fi
}

gate_build() {  # compile everything a gate needs, and bin/ermine's classpath cache for THIS checkout
  sbt -batch -J-Xmx3g core/compile core/copyResources core/Test/compile || return 1
  if [[ ! -s target/ermine-classpath || build.sbt -nt target/ermine-classpath ]] ||
     ! grep -q "^$PWD/" target/ermine-classpath; then
    mkdir -p target
    sbt -batch 'export core/fullClasspath' 2>/dev/null | grep -v '^\[' | grep -v '^$' | tail -1 |
      tr -d '\n' > target/ermine-classpath.tmp && mv target/ermine-classpath.tmp target/ermine-classpath
  fi
  grep -q "^$PWD/" target/ermine-classpath
}

with_own_classpath() {  # run "$@" with tracker/repl-classpath.txt pointing at THIS build; restore after
  local keep rc; keep=$(mktemp)
  cp -p tracker/repl-classpath.txt "$keep"
  # restore even when the gate's timeout kills this shell
  trap "cp -p '$keep' tracker/repl-classpath.txt; rm -f '$keep'" EXIT
  trap 'exit 143' TERM INT
  cp target/ermine-classpath tracker/repl-classpath.txt
  "$@"; rc=$?
  cp -p "$keep" tracker/repl-classpath.txt; rm -f "$keep"; trap - EXIT
  return $rc
}

looptrace_bin() {  # a looptrace built from exactly this tree's tracker/lean, or nothing
  local own=tracker/lean/.lake/build/bin/looptrace
  if [[ -x $own ]]; then echo "$PWD/$own"; return 0; fi
  [[ -z $(git status --porcelain -- tracker/lean) ]] || return 1
  local want wt c
  want=$(git rev-parse HEAD:tracker/lean) || return 1
  if [[ -n ${LOOPTRACE_BIN:-} ]]; then c=$LOOPTRACE_BIN; wt=${c%/tracker/lean/.lake/build/bin/looptrace}
    [[ -x $c && $(git -C "$wt" rev-parse HEAD:tracker/lean 2>/dev/null) == "$want" ]] && { echo "$c"; return 0; }
    return 1
  fi
  local root; root=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
  for c in "$(dirname "$root")"/ermine-scala*/tracker/lean/.lake/build/bin/looptrace; do
    wt=${c%/tracker/lean/.lake/build/bin/looptrace}
    [[ -x $c ]] || continue
    [[ -z $(git -C "$wt" status --porcelain -- tracker/lean 2>/dev/null) ]] || continue
    [[ $(git -C "$wt" rev-parse HEAD:tracker/lean 2>/dev/null) == "$want" ]] && { echo "$c"; return 0; }
  done
  return 1
}

gate_provenance() {
  echo "java=$(java -version 2>&1 | head -1)"
  case $1 in looptrace|suites|looptrace-corpus) echo "looptrace_bin=$(looptrace_bin || echo none)" ;; esac
}

# ---------------------------------------------------------------------------------------------------
gate_def compile commit 3600 "sbt core/compile core/copyResources core/Test/compile + classpath cache"
GATE_NOSCOPE[compile]="a type-correct mutant compiles by construction; its catches are stillborn mutants"
gate_compile() {
  gate_build; local rc=$?
  echo "SUMMARY $([[ $rc == 0 ]] && echo compiled || echo 'compile failed')"
  return $rc
}

gate_def looptrace nightly 900 "TestLoopTrace: compiler solve loop vs the Lean loop model, 720 solves (never skipped)"
GATE_SCOPE[looptrace]="$E/Subst.scala"
gate_looptrace() {
  local bin; bin=$(looptrace_bin) || { echo "SUMMARY no looptrace binary built from this tree's tracker/lean (run the lean gate)"; return 3; }
  sbt -batch -J-Xmx3g -Dermine.looptrace="$bin" 'core/testOnly *TestLoopTrace'; local rc=$?
  local line; line=$(grep -oE '[0-9]+ solves .*[0-9]+ agree' "$GATE_LOG" | tail -1)
  if grep -q 'SKIPPED' "$GATE_LOG"; then echo "SUMMARY FAIL: the property SKIPPED (a skip is not a pass)"; return 1; fi
  [[ -n $line ]] || { echo "SUMMARY FAIL: no agreement summary in the log"; return 1; }
  echo "SUMMARY $line"
  return $rc
}

gate_def corpus commit 900 "every core/examples module: verdict + refusal text vs tracker/corpus-verdicts.expected"
GATE_SCOPE[corpus]="$E/Subst.scala $E/Type.scala $E/Constraints.scala $E/SigEntail.scala $E/Kind.scala $E/KindSchema.scala $E/Term.scala $E/Pattern.scala $E/Binding.scala $E/rename/*.scala $E/parsing/*.scala"
gate_corpus() {
  tracker/tools/corpus-run.sh --batch "$GATE_OUT/corpus" || { echo "SUMMARY corpus-run failed"; return 1; }
  local rc; python3 scripts/corpus-check.py "$GATE_OUT/corpus" tracker/corpus-verdicts.expected; rc=$?
  rm -f "$GATE_OUT"/corpus/batch.log
  return $rc
}

GATE_SCOPE[repl]="$E/session/Console.scala $E/session/Printer.scala $E/Pretty.scala"
gate_repl() {
  with_own_classpath tracker/tools/repl-smoke.sh; local rc=$?
  echo "SUMMARY $(grep -c '^  PASS' "$GATE_LOG") pass, $(grep -c '^  FAIL' "$GATE_LOG") fail"
  return $rc
}

gate_def lsp commit 900 "tracker/tools/lsp-smoke.sh: the language server over tracker/lsp-tests"
GATE_SCOPE[lsp]="$E/lsp/*.scala $E/surface/*.scala"
gate_lsp() {
  LSP_SMOKE_LOG="$GATE_OUT/lsp-server.log" with_own_classpath tracker/tools/lsp-smoke.sh; local rc=$?
  echo "SUMMARY $(grep -oE 'PASS +lsp \([0-9]+ checks\)|FAIL.*' "$GATE_LOG" | tail -1)"
  return $rc
}

gate_def g1 pr 1200 "tracker/tools/g1-validate.sh: G1 comparator fixtures + stdlib signatures vs tracker/g1-baseline"
GATE_SCOPE[g1]="$E/Subst.scala $E/Type.scala $E/Constraints.scala $E/SigEntail.scala $E/Pretty.scala"
gate_g1() {
  with_own_classpath tracker/tools/g1-validate.sh; local rc=$?
  echo "SUMMARY $(grep -c '^  PASS' "$GATE_LOG") pass, $(grep -c '^  FAIL' "$GATE_LOG") fail"
  return $rc
}

gate_def suites pr 2400 "full sbt core/test (every suite; TestLoopTrace against the Lean binary, never skipped)"
GATE_SCOPE[suites]="core/src/main/scala/**/*.scala parsers/src/main/scala/**/*.scala"
gate_suites() {
  local bin; bin=$(looptrace_bin) || { echo "SUMMARY no looptrace binary built from this tree's tracker/lean (run the lean gate)"; return 3; }
  sbt -batch -J-Xmx3g -Dermine.looptrace="$bin" core/test; local rc=$?
  grep -q 'SKIPPED' "$GATE_LOG" && { echo "SUMMARY FAIL: a property SKIPPED"; return 1; }
  echo "SUMMARY $(grep -oE '(Passed|Failed|Error): Total [0-9]+, Failed [0-9]+, Errors [0-9]+' "$GATE_LOG" | tail -1)"
  return $rc
}

gate_def lean pr 5400 "tracker/lean: full lake build + Audit.lean (0 non-standard axioms); keyed by tracker/lean only"
GATE_KEYPATH[lean]=tracker/lean
GATE_NOSCOPE[lean]="the mutation operators are Scala-only; a Lean proof that stops holding fails to elaborate"
gate_lean() {
  [[ -d tracker/lean/.lake/packages/mathlib ]] || { echo "SUMMARY no tracker/lean/.lake here (a fresh one downloads Mathlib; run in a checkout that has one)"; return 3; }
  if pgrep -x looptrace > /dev/null; then echo "SUMMARY a looptrace binary is running (never lake build then)"; return 3; fi
  ( cd tracker/lean && lake build ) || { echo "SUMMARY lake build failed"; return 1; }
  local audit; audit=$(cd tracker/lean && lake env lean Audit.lean 2>&1 | tee -a "$GATE_LOG" | grep -oE 'audited: [0-9]+; declarations using a non-standard axiom: [0-9]+' | tail -1)
  echo "SUMMARY ${audit:-no audit line}"
  [[ $audit =~ axiom:\ 0$ ]]
}

gate_def looptrace-corpus nightly 5400 "tracker/tools/looptrace-corpus.sh: all 18 groups, every solve replayed in the Lean model"
GATE_SCOPE[looptrace-corpus]="$E/Subst.scala"
gate_looptrace-corpus() {
  local bin; bin=$(looptrace_bin) || { echo "SUMMARY no looptrace binary built from this tree's tracker/lean"; return 3; }
  LOOPTRACE_BIN=$bin tracker/tools/looptrace-corpus.sh "$GATE_OUT/lt"
  rm -rf "$GATE_OUT/lt/traces"   # ~1 GB; the per-group diff and results stay
  # the script exits 0 whatever the replay found: the verdict is in results.txt, one line per group
  python3 - "$GATE_OUT/lt/results.txt" <<'PY'
import re, sys
want = 18
lines = [l for l in open(sys.argv[1]) if re.match(r"^\S+\s+files=", l)] if __import__("os").path.exists(sys.argv[1]) else []
bad, segs = [], 0
for l in lines:
    f = dict(re.findall(r"(\w+)=(\S+)", l))
    g = l.split()[0]
    seg, agree, skip = int(f.get("segments", -1)), int(f.get("agree", -2)), int(f.get("skip", -1))
    segs += max(seg, 0)
    if "rc=0,timeouts=0,dropped=0" not in l or "(rc=0)" not in l.split("model=")[-1] or seg != agree or skip != 0 or seg <= 0:
        bad.append(g)
ok = len(lines) == want and not bad
print("SUMMARY %d/%d groups agree over %d segments%s" % (len(lines) - len(bad), want, segs, (" ; bad: " + " ".join(bad)) if bad else ""))
sys.exit(0 if ok else 1)
PY
}

gate_def repl nightly 900 "tracker/tools/repl-smoke.sh: REPL transcripts vs tracker/repl-tests/*.expected"
