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

# Gate DEFINITIONS (this directory) come from the checkout that runs the gate; the tree under test
# supplies the product code and tracker/tools.  The mutation harness relies on this: its lanes are
# checkouts of the commit being mutated, and the checker must not be the mutated copy.
GATE_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

gate_def corpus commit 900 "every core/examples module: verdict + refusal text vs tracker/corpus-verdicts.expected"
GATE_SCOPE[corpus]="$E/Subst.scala $E/Type.scala $E/Constraints.scala $E/SigEntail.scala $E/Kind.scala $E/KindSchema.scala $E/Term.scala $E/Pattern.scala $E/Binding.scala $E/rename/*.scala $E/parsing/*.scala"
gate_corpus() {
  tracker/tools/corpus-run.sh --batch "$GATE_OUT/corpus" || { echo "SUMMARY corpus-run failed"; return 1; }
  local rc; python3 "$GATE_SCRIPTS/corpus-check.py" "$GATE_OUT/corpus" tracker/corpus-verdicts.expected; rc=$?
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

gate_def extension commit 300 "editor/vscode: node --test test/preview-core.test.js (the preview loop's pure decisions; no node_modules)"
# WP-10 S1 (U7, the orchestrator's call on the design review's measurement: ~2 s, no precondition but
# `node`).  Registered straight at COMMIT rather than entering at nightly: it guards the one file every
# WP-7/8/10/22 decision lives in, and until now no gate ran node at all.  `npm run test:preview` is this
# exact command; it is spelled out so the gate needs no npm.  gate_client (npm test in client/) is the
# next gate, at nightly: it needs client/node_modules.
GATE_NOSCOPE[extension]="scripts/mutate.py's operators are Scala-shaped; the suite's own reverse-mutant batteries are run on copies per stage (scratch-widget-preview/)"
gate_extension() {
  command -v node > /dev/null || { echo "SUMMARY no node on PATH"; return 3; }
  ( cd editor/vscode && node --test test/preview-core.test.js ); local rc=$?
  local t p f
  t=$(grep -oE '^ℹ tests [0-9]+' "$GATE_LOG" | tail -1 | grep -oE '[0-9]+$')
  p=$(grep -oE '^ℹ pass [0-9]+' "$GATE_LOG" | tail -1 | grep -oE '[0-9]+$')
  f=$(grep -oE '^ℹ fail [0-9]+' "$GATE_LOG" | tail -1 | grep -oE '[0-9]+$')
  echo "SUMMARY ${t:-?} tests, ${p:-?} pass, ${f:-?} fail"
  [[ $rc == 0 && -n $t && $t == "$p" && ${f:-1} == 0 ]]
}

gate_def client nightly 1200 "client/: npm test (tsc, then node --test: the host reducer, the panel page, the widgets; the bundle tests SKIP unless built)"
# WP-10 S3.  Enters at NIGHTLY per docs/gate-policy.md ("a new gate enters at nightly and moves up on
# evidence").  UNAVAILABLE (3), never FAIL, where client/node_modules is absent: the closure (zod,
# typescript, jsdom, fast-check, webpack) is not vendored (WP-17), so a checkout without `npm install`
# cannot run it.  The gate never builds the bundle: the bundle tests SKIP by design when
# client/dist/browser is absent, and three corpus tests SKIP without the sbt-written fixtures -- a skip is
# counted and printed, not failed.  FAIL on any failing test, or when no counts were printed (tsc failed).
# The editor/vscode test "gate_client (WP-10 S3) ..." runs THIS function against a stub npm.
GATE_NOSCOPE[client]="scripts/mutate.py's operators are Scala-shaped; the client's reverse-mutant batteries are run on copies per stage (scratch-widget-preview/)"
gate_client() {
  command -v npm > /dev/null || { echo "SUMMARY no npm on PATH"; return 3; }
  [[ -d client/node_modules ]] || { echo "SUMMARY no client/node_modules (run npm install in client/ where the closure is available)"; return 3; }
  ( cd client && npm test ); local rc=$?
  local t p f s
  t=$(grep -oE '^ℹ tests [0-9]+' "$GATE_LOG" | tail -1 | grep -oE '[0-9]+$')
  p=$(grep -oE '^ℹ pass [0-9]+' "$GATE_LOG" | tail -1 | grep -oE '[0-9]+$')
  f=$(grep -oE '^ℹ fail [0-9]+' "$GATE_LOG" | tail -1 | grep -oE '[0-9]+$')
  s=$(grep -oE '^ℹ skipped [0-9]+' "$GATE_LOG" | tail -1 | grep -oE '[0-9]+$')
  if [[ -z $t || -z $p || -z $f ]]; then echo "SUMMARY npm test printed no test counts (did tsc fail?)"; return 1; fi
  echo "SUMMARY $t tests, $p pass, $f fail, ${s:-0} skipped"
  [[ $rc == 0 && $f == 0 && $((p + ${s:-0})) == "$t" ]]
}

# DELETED 2026-09-17 (docs/gate-audit.md §6): `g1` (tracker/tools/g1-validate.sh) was a pr gate.
# It caught two real defects in the record, both while comparing two builds during an intended change,
# but as a gate on one commit it caught 0 of 8 injected mutants -- 4 from the row solver (invisible:
# it boots the stdlib, which has no concrete-label row constraints) and, after its scope was corrected
# to inference and rendering, 4 more from Subst.scala and SigEntail.scala.  It stays as an instrument:
# run it when signatures are expected to move, and read its diff.  Ticket E19 is the fix that would
# make it a gate again (record the baseline over core/examples, where the rows are).
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

# DELETED 2026-09-17 (docs/gate-audit.md): `repl` (tracker/tools/repl-smoke.sh) and `looptrace`
# (a standalone TestLoopTrace run) were gates until today.  Neither has a catch on record -- 196 and
# 146 recorded runs, 6.5 and 0.9 machine-hours -- and in the mutation run repl caught 1 of 4 mutants
# in its own scope and looptrace 2 of 4.  TestLoopTrace still runs, inside `suites`, where a SKIPPED
# line is a FAIL; repl-smoke.sh stays as an instrument anyone can run.
