#!/usr/bin/env bash
# Local SQL Server 2022 for the widget-preview DB programme (tracker/DB-PLAN.md, tracker/db/CONTAINER.md).
# Rootless podman container `ermine-mssql`, volume `ermine-mssql-data`, port 127.0.0.1:1433.
# Passwords live ONLY in ~/.config/ermine/db.env (mode 600; MSSQL_SA_PASSWORD, ERMINE_DB_PASSWORD);
# this script never prints them and never puts them on a command line (sqlcmd reads SQLCMDPASSWORD,
# the login DDL uses sqlcmd's environment-variable substitution).
set -uo pipefail

NAME=ermine-mssql
VOL=ermine-mssql-data
IMAGE=mcr.microsoft.com/mssql/server:2022-latest
MEM_MB=2048
DBS=(ErmineSales ErmineHR ErmineScience)
LOGIN=ermine
ENVF="${ERMINE_DB_ENV:-$HOME/.config/ermine/db.env}"
LOAD="${ERMINE_DB_LOAD:-/home/dmitry/research/ermine/scratch-widget-preview/db/load}"
SQLCMD="${SQLCMD:-$HOME/.local/bin/sqlcmd}"
SERVER="tcp:127.0.0.1,1433"
WAIT_S="${ERMINE_DB_WAIT:-120}"

usage() {
  cat <<'EOF'
usage: db.sh up                      create the container if absent, start it, wait for health,
                                     create/refresh the `ermine` login and the three databases
       db.sh down                    stop the container (data kept in the volume)
       db.sh down --all              remove the container AND the volume ermine-mssql-data
                                     (the image and the /load directory are kept)
       db.sh status                  one line per fact: container, health, databases, login, memory
       db.sh sql [--sa] DB "QUERY"   run QUERY in DB as `ermine` (or sa) over TCP 127.0.0.1:1433
       db.sh sql [--sa] DB -i FILE   run a host FILE (GO batches allowed) the same way
                                     extra sqlcmd flags may follow, e.g. -h -1 -s '|'
       db.sh load DOMAIN --tier T [--seed S] [--from DIR]  (re)create DOMAIN's tables from data/out CSVs + verify
       db.sh unload DOMAIN           drop DOMAIN's views and tables (the database, user and grants stay)
       db.sh verify DOMAIN           per table: rows vs manifest, sha256 dump vs CSV; then fk, smoke

Everything reads ~/.config/ermine/db.env (override: ERMINE_DB_ENV). The client is go-sqlcmd at
~/.local/bin/sqlcmd (override: SQLCMD), always with -C (trust the self-signed cert) and -N (encrypt).
The host directory $ERMINE_DB_LOAD (default scratch-widget-preview/db/load) is mounted read-only
at /load inside the container for BULK INSERT; files there must be world-readable (0644).

Passwords must match [A-Za-z0-9_.-]{8,128} (they are substituted into T-SQL string literals).

exit: 0 ok, 1 status: not running / unhealthy / a fact missing, 2 usage, 3 env file or client
      missing/bad, or sa login refused (MSSQL_SA_PASSWORD does not match the volume: the SA
      password is fixed when the volume is created), 4 podman failed, 5 SQL failed,
      6 timed out waiting for the server; load/unload/verify: 1 count/dump/smoke mismatch,
      7 generator failed, 8 loader build failed (data/src/load; BULK INSERT as sa, all else as ermine)
EOF
}

die() { echo "db.sh: $2" >&2; exit "$1"; }

load_env() {  # reads only the two keys (never sources the file); nothing is exported
  [[ -r $ENVF ]] || die 3 "no env file $ENVF (needs MSSQL_SA_PASSWORD and ERMINE_DB_PASSWORD, mode 600)"
  [[ $(stat -c %a "$ENVF") == 600 ]] || die 3 "$ENVF must be mode 600 (is $(stat -c %a "$ENVF"))"
  [[ $(stat -c %U "$ENVF") == "$(id -un)" ]] || die 3 "$ENVF must be owned by $(id -un)"
  MSSQL_SA_PASSWORD=""; ERMINE_DB_PASSWORD=""
  local k v
  while IFS='=' read -r k v || [[ -n $k ]]; do
    case "$k" in
      MSSQL_SA_PASSWORD)  MSSQL_SA_PASSWORD=$v ;;
      ERMINE_DB_PASSWORD) ERMINE_DB_PASSWORD=$v ;;
    esac
  done < "$ENVF"
  [[ -n $MSSQL_SA_PASSWORD && -n $ERMINE_DB_PASSWORD ]] || die 3 "$ENVF lacks MSSQL_SA_PASSWORD or ERMINE_DB_PASSWORD"
  local re='^[A-Za-z0-9_.-]{8,128}$'
  [[ $MSSQL_SA_PASSWORD =~ $re && $ERMINE_DB_PASSWORD =~ $re ]] || die 3 "passwords in $ENVF must match [A-Za-z0-9_.-]{8,128}"
  [[ -x $SQLCMD ]] || die 3 "no go-sqlcmd at $SQLCMD (see tracker/db/CONTAINER.md, Client)"
}

SA_REFUSED="sa login refused: MSSQL_SA_PASSWORD in $ENVF does not match the server (the SA password is fixed when the volume $VOL is created; restore the old value or run 'db.sh down --all' to recreate; tracker/db/CONTAINER.md known gap 1)"

# sa_probe: 0 = sa can log in; 10 = password refused (client says "Login failed for user 'sa'."
# with no Reason, and the server log confirms "Password did not match"); 11 = not reachable/ready.
# The last client error line is left in SA_ERR (never contains a password).
SA_ERR=""
sa_probe() {
  local out rc
  out=$(q sa master -h -1 -W -Q "SET NOCOUNT ON; SELECT 1" 2>&1); rc=$?
  (( rc == 0 )) && [[ $(grep -v '^$' <<<"$out" | head -1) == 1 ]] && return 0
  SA_ERR=$(grep -v '^$' <<<"$out" | tail -1)
  if grep -q "Login failed for user 'sa'\.$" <<<"$out" &&
     podman logs --since 10m "$NAME" 2>&1 | grep -F "Login failed for user 'sa'. Reason: Password did not match" >/dev/null; then
    # (not grep -q: under pipefail an early grep exit SIGPIPEs podman and fails the pipeline)
    return 10
  fi
  return 11
}

# q USER DB [sqlcmd args...]: sqlcmd as sa or ermine; password via the environment only
q() {
  local user=$1 db=$2; shift 2
  local pw=$ERMINE_DB_PASSWORD; [[ $user == sa ]] && pw=$MSSQL_SA_PASSWORD
  SQLCMDPASSWORD="$pw" "$SQLCMD" -S "$SERVER" -U "$user" -d "$db" -C -N -b -l 10 "$@"
}

exists() { podman container exists "$NAME"; }
state()  { podman inspect "$NAME" --format '{{.State.Status}}' 2>/dev/null || echo absent; }
health() { podman inspect "$NAME" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || echo none; }

create() {
  mkdir -p "$LOAD" && chmod 755 "$LOAD" || die 4 "cannot create $LOAD"
  # --env-file from a process substitution: only the SA password reaches the container, and it is
  # never on podman's command line
  podman run -d --name "$NAME" \
    --env-file <(grep '^MSSQL_SA_PASSWORD=' "$ENVF") \
    -e ACCEPT_EULA=Y -e MSSQL_PID=Developer -e MSSQL_MEMORY_LIMIT_MB=$MEM_MB \
    -p 127.0.0.1:1433:1433 \
    -v "$VOL":/var/opt/mssql \
    -v "$LOAD":/load:ro \
    --restart no \
    --health-cmd 'SQLCMDPASSWORD="$MSSQL_SA_PASSWORD" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -l 5 -Q "SELECT 1" -o /dev/null' \
    --health-interval 10s --health-timeout 10s --health-retries 6 --health-start-period 30s \
    "$IMAGE" >/dev/null || die 4 "podman run failed"
}

wait_ready() {  # poll a real login rather than the 10 s healthcheck timer
  local t0=$SECONDS
  while (( SECONDS - t0 < WAIT_S )); do
    [[ $(state) == running ]] || die 4 "container stopped while starting: podman logs $NAME"
    # ready = sa can log in AND every database has finished recovery (ONLINE);
    # a refused sa password fails at once instead of waiting out WAIT_S
    sa_probe; case $? in 10) die 3 "$SA_REFUSED" ;; 11) sleep 1; continue ;; esac
    local off; off=$(q sa master -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE state_desc <> 'ONLINE' OR DATABASEPROPERTYEX(name, 'Collation') IS NULL" 2>&1 | grep -v '^$' | head -1)
    if [[ $off == 0 ]]; then echo $(( SECONDS - t0 )); return 0; fi
    sleep 1
  done
  die 6 "server not ready after ${WAIT_S}s (last client error: ${SA_ERR:-none}): podman logs $NAME"
}

provision() {  # idempotent; tempdb is rebuilt from model at every start, so its grant is re-applied
  local sql="SET NOCOUNT ON;
IF SUSER_ID(N'$LOGIN') IS NULL
  CREATE LOGIN [$LOGIN] WITH PASSWORD = N'\$(ERMINE_DB_PASSWORD)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
ELSE
  ALTER LOGIN [$LOGIN] WITH PASSWORD = N'\$(ERMINE_DB_PASSWORD)';
ALTER LOGIN [$LOGIN] ENABLE;"
  local db
  for db in "${DBS[@]}" tempdb; do
    [[ $db != tempdb ]] && sql+="
IF DB_ID(N'$db') IS NULL CREATE DATABASE [$db];"
    local roles="ALTER ROLE [db_owner] ADD MEMBER [$LOGIN];"
    [[ $db == tempdb ]] && roles="ALTER ROLE [db_ddladmin] ADD MEMBER [$LOGIN]; ALTER ROLE [db_datareader] ADD MEMBER [$LOGIN]; ALTER ROLE [db_datawriter] ADD MEMBER [$LOGIN];"
    sql+="
EXEC(N'USE [$db]; IF USER_ID(N''$LOGIN'') IS NULL CREATE USER [$LOGIN] FOR LOGIN [$LOGIN]; $roles');"
  done
  sql+="
ALTER LOGIN [$LOGIN] WITH DEFAULT_DATABASE = [${DBS[0]}];"
  ERMINE_DB_PASSWORD="$ERMINE_DB_PASSWORD" q sa master -Q "$sql" || die 5 "provisioning SQL failed"
}

cmd_up() {
  load_env
  local how=started
  if ! exists; then create; how=created
  elif [[ $(state) == running ]]; then how=already-running
  else podman start "$NAME" >/dev/null || die 4 "podman start failed"; fi
  local secs; secs=$(wait_ready) || exit $?
  provision
  podman healthcheck run "$NAME" >/dev/null 2>&1  # refresh health now instead of at the next 10 s tick
  echo "up $how ready-after=${secs}s login=$LOGIN databases=$(IFS=,; echo "${DBS[*]}") port=127.0.0.1:1433"
}

graceful_stop() {  # PID 1 (launch_sqlservr.sh) ignores SIGTERM, so ask the server to SHUTDOWN (checkpoints)
  # $1 = keep: data is kept, so refuse to SIGKILL when sa is refused; $1 = discard: the volume goes anyway
  load_env
  sa_probe; local p=$?
  if (( p == 10 )); then
    [[ ${1:-keep} == keep ]] && die 3 "$SA_REFUSED; not stopping (a kill would skip the checkpoint)"
    echo "db.sh: sa login refused; removing without SHUTDOWN (the volume is being deleted)" >&2
    return 0
  fi
  (( p == 0 )) && q sa master -Q "SHUTDOWN" >/dev/null 2>&1
  timeout 60 podman wait "$NAME" >/dev/null 2>&1 || podman stop -t 10 "$NAME" >/dev/null 2>&1 || die 4 "podman stop failed"
}

cmd_down() {
  if [[ ${1:-} == --all && $# -eq 1 ]]; then
    if exists; then
      [[ $(state) == running ]] && graceful_stop discard
      podman rm -f "$NAME" >/dev/null || die 4 "podman rm failed"
    fi
    if podman volume exists "$VOL"; then podman volume rm "$VOL" >/dev/null || die 4 "podman volume rm failed"; fi
    echo "down --all container=removed volume=removed image=kept load-dir=kept"
  elif [[ $# -eq 0 ]]; then
    exists || { echo "down container=absent"; return 0; }
    [[ $(state) == running ]] && graceful_stop keep
    echo "down container=$(state) volume=kept"
  else usage >&2; exit 2; fi
}

cmd_status() {
  load_env
  local st h rc=0; st=$(state); h=$(health)
  echo "container $NAME state=$st health=$h image=$IMAGE volume=$(podman volume exists "$VOL" && echo present || echo absent)"
  if [[ $st != running ]]; then echo "status DOWN"; return 1; fi
  [[ $h == healthy ]] || rc=1
  local sa_ok=1
  sa_probe; case $? in
    10) sa_ok=0; echo "login sa FAILED: password in $ENVF does not match the server (fixed at volume creation; CONTAINER.md known gap 1)"; rc=1 ;;
    11) sa_ok=0; echo "login sa FAILED: ${SA_ERR:-no answer}"; rc=1 ;;
  esac
  if (( sa_ok )); then
  local have; have=$(q sa master -h -1 -W -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name IN ($(printf "N'%s'," "${DBS[@]}" | sed 's/,$//')) ORDER BY name" 2>/dev/null | grep -v '^$' | paste -sd, -)
  local missing=() db
  for db in "${DBS[@]}"; do [[ ,$have, == *,$db,* ]] || missing+=("$db"); done
  echo "databases present=${have:-none} missing=$( ((${#missing[@]})) && (IFS=,; echo "${missing[*]}") || echo none)"
  ((${#missing[@]})) && rc=1
  else echo "databases unknown (listing needs sa)"; fi
  # ermine cannot read its own encrypt_option (needs VIEW SERVER STATE), so TLS is read on sa's
  # session; both connect with -N (mandatory: the client refuses an unencrypted channel)
  local who enc
  who=$(q "$LOGIN" "${DBS[0]}" -h -1 -W -Q "SET NOCOUNT ON; SELECT SUSER_SNAME()" 2>/dev/null | grep -v '^$' | head -1)
  enc=unknown
  (( sa_ok )) && enc=$(q sa master -h -1 -W -Q "SET NOCOUNT ON; SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id = @@SPID" 2>/dev/null | grep -v '^$' | head -1)
  if [[ $who == "$LOGIN" ]]; then echo "login $LOGIN ok via 127.0.0.1:1433 suser=$who tls=$enc"; else echo "login $LOGIN FAILED"; rc=1; fi
  local pid rss=0 p
  for p in $(podman top "$NAME" hpid,args 2>/dev/null | awk '/sqlservr/ {print $1}'); do
    pid=$(awk '/VmRSS/ {print $2}' "/proc/$p/status" 2>/dev/null || echo 0); (( pid > rss )) && rss=$pid
  done
  echo "memory sqlservr-rss=$(( rss / 1024 ))M cap=MSSQL_MEMORY_LIMIT_MB=$MEM_MB host-avail=$(awk '/MemAvailable/ {printf "%.1fG", $2/1048576}' /proc/meminfo)"
  (( rc == 0 )) && echo "status OK" || echo "status DEGRADED"
  return $rc
}

cmd_sql() {
  local user=$LOGIN
  [[ ${1:-} == --sa ]] && { user=sa; shift; }
  [[ $# -ge 2 ]] || { usage >&2; exit 2; }
  load_env
  local db=$1; shift
  if [[ $1 == -i ]]; then
    [[ $# -ge 2 && -r $2 ]] || die 2 "no readable file: ${2:-}"
    local f=$2; shift 2; q "$user" "$db" -i "$f" "$@" || exit 5
  else
    local query=$1; shift; q "$user" "$db" -Q "$query" "$@" || exit 5
  fi
}

DATA="${ERMINE_DATA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data}"

# load|unload|verify DOMAIN [opts]: the node loader (data/src/load/cli.js), rebuilt when a source is newer
cmd_loader() {
  local verb=$1; shift
  [[ $# -ge 1 && ${1:0:1} != - ]] || { usage >&2; exit 2; }
  local domain=$1; shift
  [[ $verb == load || $# -eq 0 ]] || { usage >&2; exit 2; }
  local cli="$DATA/dist/src/load/cli.js"
  if [[ ! -f $cli || -n $(find "$DATA/src" "$DATA/tsconfig.json" -newer "$cli" -print -quit 2>/dev/null) ]]; then
    npm --prefix "$DATA" run --silent build >&2 || die 8 "loader build failed (npm --prefix $DATA run build)"
  fi
  ERMINE_DBSH="${BASH_SOURCE[0]}" ERMINE_DB_LOAD="$LOAD" exec node --disable-warning=ExperimentalWarning "$cli" mssql "$verb" --domain "$domain" "$@"
}

case "${1:-}" in
  -h|--help) usage ;;
  up)     shift; [[ $# -eq 0 ]] || { usage >&2; exit 2; }; cmd_up ;;
  down)   shift; cmd_down "$@" ;;
  status) shift; [[ $# -eq 0 ]] || { usage >&2; exit 2; }; cmd_status ;;
  sql)    shift; cmd_sql "$@" ;;
  load|unload|verify) cmd_loader "$@" ;;
  *)      usage >&2; exit 2 ;;
esac
