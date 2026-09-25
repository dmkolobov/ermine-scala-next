#!/usr/bin/env bash
# WP-12(a) SQL Server smoke: run the TestMsSqlSmoke properties ONCE against the
# local container (tracker/db/SERVER.md §3).  The password is read from
# ~/.config/ermine/db.env (ERMINE_DB_PASSWORD, mode 600, outside the repo) and
# reaches the sbt JVM through its ENVIRONMENT only -- never argv, never a file
# in the repo, never printed (the property scrubs it from every message).
#
#   tracker/tools/db-smoke.sh            # live: 127.0.0.1:1433, ermine, ErmineSales
#   tracker/tools/db-smoke.sh --skip     # no credentials: the live property is NOT registered;
#                                        # passes iff the "DB suites: not requested" line is
#                                        # printed and no SKIPPED word is (the suites gate's rule)
#
# Overrides: ERMINE_DB_URL, ERMINE_DB_USER (the password only from db.env or
# an already-exported ERMINE_DB_PASSWORD).  Output: the sbt log, the
# `[mssql-smoke]` lines and the `+`/`!` property lines, in $DB_SMOKE_LOG
# (default: the scratchpad-style /tmp/ermine-db-smoke.log).
# Exit: 0 all properties passed; 1 a property failed; 2 another sbt is running
# (this box runs ONE sbt at a time); 3 no password found for a live run.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
export PATH="$JAVA_HOME/bin:$HOME/.local/ermine-toolchain/bin:$PATH"
log="${DB_SMOKE_LOG:-/tmp/ermine-db-smoke.log}"

if pgrep -f sbt-launch >/dev/null 2>&1; then
  echo "db-smoke: another sbt is running; one at a time on this box" >&2; exit 2
fi

if [[ ${1:-} == --skip ]]; then
  unset ERMINE_DB_URL ERMINE_DB_USER ERMINE_DB_PASSWORD
else
  if [[ -z ${ERMINE_DB_PASSWORD:-} && -r $HOME/.config/ermine/db.env ]]; then
    ERMINE_DB_PASSWORD="$(sed -n 's/^ERMINE_DB_PASSWORD=//p' "$HOME/.config/ermine/db.env")"
  fi
  [[ -n ${ERMINE_DB_PASSWORD:-} ]] || { echo "db-smoke: no ERMINE_DB_PASSWORD" >&2; exit 3; }
  export ERMINE_DB_PASSWORD
  export ERMINE_DB_URL="${ERMINE_DB_URL:-jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true}"
  export ERMINE_DB_USER="${ERMINE_DB_USER:-ermine}"
fi

sbt -batch 'core/testOnly com.clarifi.reporting.TestMsSqlSmoke' > "$log" 2>&1
rc=$?
grep -E '^\[mssql-smoke\]|^\[info\] [+!x] |Passed: Total|Failed: Total|\[error\]' "$log"
if [[ ${1:-} == --skip ]]; then
  grep -q 'DB suites: not requested' "$log" || { echo "db-smoke: --skip printed no 'not requested' line" >&2; rc=1; }
  if grep -q 'SKIPPED' "$log"; then echo "db-smoke: --skip printed SKIPPED (the suites gate fails on it)" >&2; rc=1; fi
fi
[[ $rc -eq 0 ]] && exit 0 || exit 1
