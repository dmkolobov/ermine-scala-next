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
declare -A GATE_TIER=() GATE_TIMEOUT=() GATE_DESC=() GATE_SCOPE=() GATE_NOSCOPE=() GATE_KEYPATH=() GATE_KEYFN=()
# GATE_KEYFN[g]=fn: a gate whose answer also depends on state OUTSIDE the tree (the `db` gate: what the
# local SQL Server holds) names a function printing that state; scripts/gate.sh hashes its output into
# the key.  An empty output or a failing function keys on content alone.

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

gate_def generated commit 120 "client/src/generated/widgets.ts: .e + generator sha256 vs the header, and every recursive declaration EQUAL to zod's inference (node + tsc, no JVM)"
# WP-32 S2.  `node client/scripts/check-fresh.js`: (a) every `// sha256` source line bin/ermine-schema
# wrote is recomputed over core/src/main/resources/modules, and every Layout/Widgets module must be
# listed; (b) every `// generator sha256` line client/scripts/generate.sh wrote (json/{Schema,SchemaMain,
# Zod}.scala) is recomputed; (c) the both-direction exactness probe (the S1 review's eq-probe) over every
# `export const X: z.ZodType<X> = E;`, typechecked with the client's tsc -- the annotation alone lets a
# WIDENED declaration through.  About two seconds.  Straight at COMMIT (the `extension` precedent): it
# is what keeps a stale or widened generated file from being committed, and it needs no JVM.
# UNAVAILABLE (3) without node or client/node_modules (tsc and zod are not vendored, WP-17).
# client/scripts/check-generated.sh (regenerate + diff, one JVM) stays a manual check.
GATE_NOSCOPE[generated]="scripts/mutate.py's operators are Scala-shaped; the checks' reverse mutants (a hash edited, a declaration widened) are run on copies per stage (scratch-widget-preview/wp32-s2)"
gate_generated() {
  command -v node > /dev/null || { echo "SUMMARY no node on PATH"; return 3; }
  local line rc
  line=$(node client/scripts/check-fresh.js 2>&1); rc=$?
  echo "$line"
  echo "SUMMARY ${line#generated: }"
  return $rc
}

gate_def client nightly 1200 "client/: the generated-file checks, then npm test (tsc, then node --test: the host reducer, the panel page, the widgets; the bundle tests SKIP unless built)"
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
  # WP-32 S2: the `generated` gate's checks first (sources, generator key, exactness probe); a stale
  # or widened generated file FAILS here, naming the offender, before any test runs
  local fresh frc
  fresh=$(node client/scripts/check-fresh.js 2>&1); frc=$?
  echo "$fresh"
  if [[ $frc == 3 ]]; then echo "SUMMARY generated-file check unavailable: ${fresh#generated: }"; return 3; fi
  if [[ $frc != 0 ]]; then echo "SUMMARY generated-file check failed: ${fresh#generated: }"; return 1; fi
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

gate_def db pr 900 "the DB suites (TestMsSqlSmoke, TestDbReports) against the local SQL Server + the SQLite twin; keyed also by ErmineSales's load stamp"
# DB-PLAN S1 (tracker/db/SERVER.md §5).  Without ERMINE_DB_* the two suites register NOTHING and print a
# "DB suites: not requested" line, so `suites` (core/test) stays free of SKIPPED; this gate is where they
# run.  UNAVAILABLE (3), the `lean` convention, when a precondition is missing: the container is not up
# (`scripts/db.sh up`), ErmineSales does not hold tier xs (the twins pin xs's totals), data/ has no
# node_modules, or another sbt is running (one sbt at a time on this box).  Never a silent pass.  The
# SQLite twin is built by the gate itself into $GATE_OUT (below).  STAGE-2 NIT (SERVER.md §5): a gate
# must not depend on the tier the user has loaded; the gate should load xs into its OWN database.  The password is read from
# ~/.config/ermine/db.env (ERMINE_DB_ENV overrides) into the sbt JVM's ENVIRONMENT only: never argv,
# never echoed, and the gate FAILS if it ever appears in its own log.
GATE_KEYFN[db]=db_key_extra
GATE_NOSCOPE[db]="needs the local SQL Server container and its loaded data; mutants are not run against a live database"
db_env_file() { echo "${ERMINE_DB_ENV:-$HOME/.config/ermine/db.env}"; }
db_stamp() {  # ErmineSales's loader stamp (tracker/db/LOADER.md §1), one JSON line, or nothing
  scripts/db.sh sql ErmineSales "SET NOCOUNT ON; SELECT CAST(value AS nvarchar(4000)) FROM sys.extended_properties WHERE class = 0 AND name = 'ermine.load.sales'" -h -1 -W 2>/dev/null | grep -m1 '^{'
}
db_stamp_field() {  # db_stamp_field JSON NAME
  sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}[,}].*/\1/p" <<<"$1"
}
db_key_extra() {  # tier + seed + manifest of what ErmineSales holds (the SQLite twin is built by the
  # gate from tier xs, which is a pure function of the tree's generator and contract: content covers it)
  local st; st=$(db_stamp) || return 1; [[ -n $st ]] || return 1
  echo "tier=$(db_stamp_field "$st" tier) seed=$(db_stamp_field "$st" seed) manifest=$(db_stamp_field "$st" manifestSha256)"
}
gate_db() {
  set +x
  [[ -x scripts/db.sh ]] || { echo "SUMMARY no scripts/db.sh in this tree"; return 3; }
  scripts/db.sh status > /dev/null 2>&1 || { echo "SUMMARY the SQL Server container is not up or not healthy (run scripts/db.sh up)"; return 3; }
  local st tier; st=$(db_stamp); tier=$(db_stamp_field "$st" tier)
  [[ $tier == xs ]] || { echo "SUMMARY ErmineSales holds tier ${tier:-<no stamp>}, the twins pin tier xs (run scripts/db.sh load sales --tier xs)"; return 3; }
  if pgrep -f sbt-launch > /dev/null; then echo "SUMMARY another sbt is running (one sbt at a time on this box)"; return 3; fi
  # The SQLite twin (D13) is BUILT HERE, into the gate's own directory, from tier xs: the suite must not
  # depend on whatever sits in the gitignored data/out/.  The loader regenerates the CSVs if missing.
  command -v npm > /dev/null || { echo "SUMMARY no npm on PATH (the SQLite twin is built with data/'s loader)"; return 3; }
  [[ -d data/node_modules ]] || { echo "SUMMARY no data/node_modules (run npm install in data/)"; return 3; }
  local lite=${GATE_OUT:-$PWD/target}/sales-xs.sqlite
  rm -f "$lite"
  ( cd data && npm run --silent load:sqlite -- --domain sales --tier xs --seed 42 --db "$lite" ) ||
    { echo "SUMMARY FAIL: the SQLite twin did not build (data/ load:sqlite, tier xs)"; return 1; }
  [[ -s $lite ]] || { echo "SUMMARY FAIL: the SQLite twin build left no file at $lite"; return 1; }
  local envf; envf=$(db_env_file)
  [[ -r $envf ]] || { echo "SUMMARY no readable $envf"; return 3; }
  local pw; pw=$(sed -n 's/^ERMINE_DB_PASSWORD=//p' "$envf")
  [[ -n $pw ]] || { echo "SUMMARY no ERMINE_DB_PASSWORD in $envf"; return 3; }
  local rc
  ERMINE_DB_PASSWORD=$pw \
  ERMINE_DB_URL="${ERMINE_DB_URL:-jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true}" \
  ERMINE_DB_USER="${ERMINE_DB_USER:-ermine}" \
  ERMINE_DB_SQLITE=$lite \
    sbt -batch 'core/testOnly *TestMsSqlSmoke* *TestDbReports*'
  rc=$?
  # the pattern goes in on a file descriptor, never on grep's command line (REVIEW-S1 R2-2)
  if grep -qFf <(printf '%s\n' "$pw") "$GATE_LOG"; then unset pw; echo "SUMMARY FAIL: the password reached the gate log"; return 1; fi
  unset pw
  if grep -q 'DB suites:.*not requested' "$GATE_LOG"; then echo "SUMMARY FAIL: a DB suite printed 'not requested' (the environment did not reach sbt)"; return 1; fi
  local n p f
  n=$(grep -cE '^\[info\] [+!x] ' "$GATE_LOG"); p=$(grep -cE '^\[info\] \+ ' "$GATE_LOG"); f=$((n - p))
  if [[ $rc == 0 && $f == 0 && $n -gt 0 ]]; then
    echo "SUMMARY db $n properties, $p passed, twins equal, totals pinned (ErmineSales tier $tier)"
    return 0
  fi
  echo "SUMMARY db $n properties, $p passed, $f failed (ErmineSales tier $tier; sbt exit $rc)"
  return 1
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
