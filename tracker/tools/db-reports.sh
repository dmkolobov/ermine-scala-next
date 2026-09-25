#!/usr/bin/env bash
# DB-PLAN S1 reports: run TestDbReports ONCE (tracker/db/REPORTS.md).  The
# DB-backed twins (doc/DbFetch*.e, modules/Doc/DbSalesReport.e) are rendered
# through the document runner on ErmineSales (SQL Server) and on the SQLite
# twin, and compared with the in-memory originals.  The database must hold
# tier xs.  Password handling is tracker/tools/db-smoke.sh's: read from
# ~/.config/ermine/db.env into the sbt JVM's ENVIRONMENT only, never printed.
#
#   tracker/tools/db-reports.sh           # live: SQL Server + the SQLite twin if its file exists
#   tracker/tools/db-reports.sh --skip    # no credentials, no SQLite file: nothing registered, one
#                                         # "DB suites: not requested" line per set
#
# Overrides: ERMINE_DB_URL, ERMINE_DB_USER, ERMINE_DB_SQLITE (default
# data/out/sales/xs/sales.sqlite).  Log: $DB_REPORTS_LOG (default
# /tmp/ermine-db-reports.log); prints the [db-reports] and property lines.
# Exit: 0 all passed; 1 a property failed; 2 another sbt is running; 3 no password.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/ermine-toolchain/jdk-21.0.12.1+1}"
export PATH="$JAVA_HOME/bin:$HOME/.local/ermine-toolchain/bin:$PATH"
log="${DB_REPORTS_LOG:-/tmp/ermine-db-reports.log}"

if pgrep -f sbt-launch >/dev/null 2>&1; then
  echo "db-reports: another sbt is running; one at a time on this box" >&2; exit 2
fi

if [[ ${1:-} == --skip ]]; then
  unset ERMINE_DB_URL ERMINE_DB_USER ERMINE_DB_PASSWORD
  export ERMINE_DB_SQLITE=/nonexistent/skip-mode.sqlite
else
  if [[ -z ${ERMINE_DB_PASSWORD:-} && -r $HOME/.config/ermine/db.env ]]; then
    ERMINE_DB_PASSWORD="$(sed -n 's/^ERMINE_DB_PASSWORD=//p' "$HOME/.config/ermine/db.env")"
  fi
  [[ -n ${ERMINE_DB_PASSWORD:-} ]] || { echo "db-reports: no ERMINE_DB_PASSWORD" >&2; exit 3; }
  export ERMINE_DB_PASSWORD
  export ERMINE_DB_URL="${ERMINE_DB_URL:-jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true}"
  export ERMINE_DB_USER="${ERMINE_DB_USER:-ermine}"
fi

sbt -batch 'core/testOnly com.clarifi.reporting.TestDbReports' > "$log" 2>&1
rc=$?
grep -E '^\[db-reports\]|^\[info\] [+!x] |Passed: Total|Failed: Total|\[error\]' "$log"
[[ $rc -eq 0 ]] && exit 0 || exit 1
