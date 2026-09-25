# CONTAINER: the local SQL Server (DB-PLAN S0)

Status: S0 was done by the infra role on 2026-09-24. Everything below was MEASURED on this machine that day unless a row says otherwise.
Decisions it follows: D1 (2022, rootless podman), D2 (2048 MB cap), D3 (`ermine` login), D4 (trust the self-signed certificate), D5 (one database per domain) and D12 (the data is kept until someone tears it down).

## Recipe

| Item | Value |
|---|---|
| Image | `mcr.microsoft.com/mssql/server:2022-latest`, digest `sha256:4402d880dd4c34bfa7d8705e56a86cd6c88da80a1f6bbbe741f999e76264a090`, image id `5b0916c7af8c`, 1.7 GB unpacked, created 2026-08-26, label `com.microsoft.version=16.0.4295.3` |
| Server | `Microsoft SQL Server 2022 (RTM-CU27) (KB5104824) - 16.0.4295.3 (X64) ... Developer Edition (64-bit) on Linux (Ubuntu 22.04.5 LTS)` (from `SELECT @@VERSION` as `ermine`) |
| Pull | took 18 s |
| Container | `ermine-mssql`, runs as `mssql` (uid 10001) inside the container |
| Memory cap | `MSSQL_MEMORY_LIMIT_MB=2048`, which is SQL Server's own limit. There is no cgroup `--memory` cap (see known gaps) |
| Volume | named volume `ermine-mssql-data` mounted at `/var/opt/mssql`, stored on the host at `~/.local/share/containers/storage/volumes/ermine-mssql-data/_data` |
| Bind mount | `/home/dmitry/research/ermine/scratch-widget-preview/db/load` -> `/load`, read-only, plain `:ro` with no `:Z` or `:U` (see podman facts) |
| Port | `127.0.0.1:1433` -> 1433. Nothing else on the host can reach it. `ss` shows `rootlessport` listening on `127.0.0.1:1433` |
| Restart policy | `no`: the user starts it with `scripts/db.sh up` |
| Healthcheck | every 10 s, 10 s timeout, 6 retries, 30 s start period, using the image's own sqlcmd as `sa`. The password reaches it through `SQLCMDPASSWORD`, expanded inside the container. `db.sh up` runs one check right away so `status` does not show `starting` |

The run command lives in `scripts/db.sh` (`create`). It is shown here with nothing secret in it: the SA password comes from a process-substitution env file that contains only that one line.

```
podman run -d --name ermine-mssql \
  --env-file <(grep '^MSSQL_SA_PASSWORD=' ~/.config/ermine/db.env) \
  -e ACCEPT_EULA=Y -e MSSQL_PID=Developer -e MSSQL_MEMORY_LIMIT_MB=2048 \
  -p 127.0.0.1:1433:1433 \
  -v ermine-mssql-data:/var/opt/mssql \
  -v /home/dmitry/research/ermine/scratch-widget-preview/db/load:/load:ro \
  --restart no \
  --health-cmd 'SQLCMDPASSWORD="$MSSQL_SA_PASSWORD" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -l 5 -Q "SELECT 1" -o /dev/null' \
  --health-interval 10s --health-timeout 10s --health-retries 6 --health-start-period 30s \
  mcr.microsoft.com/mssql/server:2022-latest
```

## Client

The client is go-sqlcmd v1.10.0 at `~/.local/bin/sqlcmd`. It came from the GitHub release `sqlcmd-linux-amd64.tar.bz2`. The tarball's sha256 is `92516d98c63d99b0994de5b61350c91f6915f9b76f139a59039fbcb225c2e987`, which matches the release's published digest. The binary's sha256 is `5c043495deff92687243e4c337e09494d497557a0217bdca81afefb1e4a2b4ce`. The host has no `bzip2`, so the tarball was unpacked with Python's `tarfile`. Every call uses `-S tcp:127.0.0.1,1433 -C -N` and passes the password in `SQLCMDPASSWORD`. The image's own `/opt/mssql-tools18/bin/sqlcmd` is used only by the healthcheck.

## Login and grants (D3)

| Where | What was granted | Why |
|---|---|---|
| server | SQL login `ermine`, `CHECK_POLICY=ON`, `CHECK_EXPIRATION=OFF`, default database `ErmineSales` | this is the login the playtest types. Its password is re-applied on every `up`, so the env file stays the source of truth |
| `ErmineSales`, `ErmineHR`, `ErmineScience` | user `ermine`, `db_owner` | the loader and `memoRelWithPK`'s persistent `MemoHash_*` tables need DDL in the connected database. Tested: CREATE and DROP of `dbo.MemoHash_probe` in ErmineHR as `ermine` |
| `tempdb` | user `ermine` with `db_ddladmin`, `db_datareader` and `db_datawriter` | D3 asked for CREATE TABLE in tempdb. These three roles are the least set that can create, fill, read and drop a permanent `tempdb.dbo` table. Tested as `ermine`. SQL Server rebuilds tempdb from `model` at every start, so `db.sh up` re-applies this grant every time it runs. If the container is started with plain `podman start`, the grant is not there |
| (none) | `##global` and `#local` temp tables | these need **no grant**. A probe login with no tempdb user created, filled, read and dropped `##p` and created `#l`. The scanner's `##<guid>` tables therefore work even without the tempdb grant above |
| (not granted) | `BULK INSERT` | `ermine` gets `Msg 4834 ... You do not have permission to use the bulk load statement` because this needs the server-level `ADMINISTER BULK OPERATIONS` / `bulkadmin`, which `ermine` deliberately does not have. The loader runs `BULK INSERT` as sa with `scripts/db.sh sql --sa DB ...`. Tested: sa loaded 2 rows from `/load/probe.csv` |

## What `down` and `down --all` do

| Command | Effect |
|---|---|
| `db.sh down` | Sends `SHUTDOWN` as sa, which checkpoints the databases, then waits for the container to exit (0.6 s). The container and volume are kept. The image's PID 1 is `launch_sqlservr.sh` and ignores SIGTERM: a plain `podman stop -t 30` waited the full 30 s and then used SIGKILL, which is why `down` does not rely on it |
| `db.sh down --all` | Same shutdown, then `podman rm` of `ermine-mssql` and `podman volume rm ermine-mssql-data`. Every database, the login and all grants are gone after this. It **keeps** the image (1.7 GB; remove it with `podman rmi mcr.microsoft.com/mssql/server:2022-latest`), the `/load` directory, `~/.config/ermine/db.env` and `~/.local/bin/sqlcmd` |

## Measurements

| What | Value |
|---|---|
| Time from container start to the log line "SQL Server is now ready", fresh volume | 4.7 s and 4.5 s (two creates, from the log timestamps). The first create, from `podman run` to the ready line, took 6.5 s |
| Same, restart on an existing volume | 3.6 s (log timestamps) |
| `db.sh up` end to end, including database recovery and provisioning | 7-8 s on a create, 4-5 s on a restart (`ready-after=` in the output) |
| RSS of `sqlservr` after boot, idle | 689-726 MiB across five boots (`VmRSS` of the larger of the two `sqlservr` processes). `podman stats` showed 643 MB on the first boot |
| Host `MemAvailable` | before the first create 4109 MiB, 30 s after it 4364 MiB. The host moves too much for this pair to isolate the server's share: other processes changed during the same window. On the later runs, `MemAvailable` was 5044 MiB before a create and 4.3 GiB after it (about 0.7 GiB lower), which matches the RSS |
| Disk | image 1.7 GB. Volume after one create and one restart, with the three databases empty: 185 MB (`podman unshare du -sh`) |

## Rootless podman facts that mattered

| Fact | Effect |
|---|---|
| podman 4.9.3, rootless, cgroup v2 (controllers delegated to the user: `cpu memory pids`), overlay storage | rootless worked first time. Nothing needed sudo |
| `/etc/subuid` and `/etc/subgid`: `dmitry:100000:65536` | covers the container's uid 10001, which is host uid 110000 |
| `kernel.apparmor_restrict_unprivileged_userns=1` | **did not block anything**. Ubuntu ships `/etc/apparmor.d/podman` (`profile podman /usr/bin/podman flags=(unconfined) { userns, }`), and also profiles for `crun`, `runc` and `slirp4netns`. No sysctl change is needed |
| Network backend netavark. A rootless container's network mode is `slirp4netns` (v1.2.1), and ports are forwarded by `rootlessport` | the default worked. No need to switch to `--network slirp4netns` or pasta |
| The `/load` bind mount | Ubuntu uses AppArmor rather than SELinux, so `:Z` is not needed. `:U` would chown the host directory to host uid 110000 and lock the generator out of its own output, so it is not used. Host files owned by dmitry appear as `0:0` inside the container, and `mssql` (10001) reads them through the "other" bits. **Files in `/load` must be 0644 and the directory 0755** |
| Healthchecks | rootless podman runs them through a user systemd timer. It worked, although `systemctl --user is-system-running` reports `degraded` |

## How the extension and the server connect

- JDBC: `jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true` (D4: the image's self-signed certificate is trusted rather than validated)
- user `ermine`. The password is prompted once per window (WP-13) and never read from a file by the extension.
- The Scala smoke (`tracker/tools/db-smoke.sh`, server role) may read `ERMINE_DB_PASSWORD` from `~/.config/ermine/db.env` through the environment.
- TLS: `sys.dm_exec_connections.encrypt_option = TRUE` for a TCP session. `ermine` cannot read its own `encrypt_option` without `VIEW SERVER STATE`, so `status` reads it on sa's session. Both logins connect with `-N`, which makes encryption mandatory: the client refuses an unencrypted channel.

## Test run, each subcommand once (the output as printed)

```
$ scripts/db.sh down --all
down --all container=removed volume=removed image=kept load-dir=kept
exit=0
host MemAvailable before-create=5044M
$ scripts/db.sh up
up created ready-after=7s login=ermine databases=ErmineSales,ErmineHR,ErmineScience port=127.0.0.1:1433
exit=0
$ scripts/db.sh status
container ermine-mssql state=running health=healthy image=mcr.microsoft.com/mssql/server:2022-latest volume=present
databases present=ErmineHR,ErmineSales,ErmineScience missing=none
login ermine ok via 127.0.0.1:1433 suser=ermine tls=TRUE
memory sqlservr-rss=720M cap=MSSQL_MEMORY_LIMIT_MB=2048 host-avail=4.3G
status OK
exit=0
$ scripts/db.sh sql ErmineSales SET NOCOUNT ON; SELECT 1 AS one, SUSER_SNAME() AS login, DB_NAME() AS db -W
one login db
--- ----- --
1 ermine ErmineSales

exit=0
$ scripts/db.sh sql ErmineHR -i /home/dmitry/research/ermine/scratch-widget-preview/db/probe.sql -h -1 -W
ErmineHR

ermine

exit=0
$ scripts/db.sh down
down container=exited volume=kept
exit=0
$ scripts/db.sh status
container ermine-mssql state=exited health=healthy image=mcr.microsoft.com/mssql/server:2022-latest volume=present
status DOWN
exit=1
$ scripts/db.sh up
up started ready-after=4s login=ermine databases=ErmineSales,ErmineHR,ErmineScience port=127.0.0.1:1433
exit=0
$ scripts/db.sh status
container ermine-mssql state=running health=healthy image=mcr.microsoft.com/mssql/server:2022-latest volume=present
databases present=ErmineHR,ErmineSales,ErmineScience missing=none
login ermine ok via 127.0.0.1:1433 suser=ermine tls=TRUE
memory sqlservr-rss=706M cap=MSSQL_MEMORY_LIMIT_MB=2048 host-avail=4.3G
status OK
exit=0
$ scripts/db.sh sql master bad sql here
Msg 102, Level 15, State 1, Server 64bc131cdc40, Line 1
Incorrect syntax near 'here'.
exit=5
$ scripts/db.sh bogus
usage: db.sh up                      create the container if absent, start it, wait for health,
                                     create/refresh the `ermine` login and the three databases
       db.sh down                    stop the container (data kept in the volume)
       db.sh down --all              remove the container AND the volume ermine-mssql-data
                                     (the image and the /load directory are kept)
       db.sh status                  one line per fact: container, health, databases, login, memory
       db.sh sql [--sa] DB "QUERY"   run QUERY in DB as `ermine` (or sa) over TCP 127.0.0.1:1433
       db.sh sql [--sa] DB -i FILE   run a host FILE (GO batches allowed) the same way
                                     extra sqlcmd flags may follow, e.g. -h -1 -s '|'

Everything reads ~/.config/ermine/db.env (override: ERMINE_DB_ENV). The client is go-sqlcmd at
~/.local/bin/sqlcmd (override: SQLCMD), always with -C (trust the self-signed cert) and -N (encrypt).
The host directory $ERMINE_DB_LOAD (default scratch-widget-preview/db/load) is mounted read-only
at /load inside the container for BULK INSERT; files there must be world-readable (0644).

exit: 0 ok, 1 status: not running / unhealthy / a fact missing, 2 usage, 3 env file or client
      missing/bad, 4 podman failed, 5 SQL failed, 6 timed out waiting for health
exit=2
host MemAvailable after=4403M
```

(The first `status` after a create, in an earlier run before the fix, showed `login ermine FAILED`. Cause: `ermine` cannot read `sys.dm_exec_connections`. `status` now checks `SUSER_SNAME()` as `ermine` and reads TLS on sa's session. That earlier run also showed `health=starting` right after `up`. Cause: the first healthcheck tick; `up` now runs one check itself.)

## Known gaps

1. **The SA password is fixed when the volume is created.** `MSSQL_SA_PASSWORD` only applies on a fresh `/var/opt/mssql`. If the SA line in `db.env` changes later, sa logins fail. Since Round 2, `up` and `down` exit 3 at once with a message that names the env file and this rule, and `status` prints `login sa FAILED: ...` (exit 1). Fix: restore the old value (or run `ALTER LOGIN sa WITH PASSWORD` while you still know it), or run `down --all` and recreate.
2. **The password is visible to this user.** `podman inspect ermine-mssql` shows `MSSQL_SA_PASSWORD` in the container's `Config.Env`, and `/proc/<pid>/environ` of the sqlcmd processes shows it too. Only the same user (dmitry) can read either, and that user can already read `db.env`. The password is never on a command line: `ps` shows no password in any argument list.
3. **No cgroup memory cap.** `MSSQL_MEMORY_LIMIT_MB=2048` caps SQL Server's own memory manager, but the process can go somewhat over it (thread stacks, CLR). A hard `--memory` limit set at or near 2048 MB risks an OOM kill, so none is set. The `memory` controller is delegated, so `--memory 3g` could be added later if needed.
4. **The tempdb grant does not survive a bare `podman start`.** Only `db.sh up` re-applies it. `##` temp tables are not affected, because they need no grant.
5. **`ermine` cannot run `BULK INSERT`.** This is by design: the loader uses `--sa`. Granting `bulkadmin` to `ermine` would let the playtest login read any file the server can read.
6. **No automatic start.** The restart policy is `no` and there is no systemd unit, so run `db.sh up` after a reboot.
7. **Image tag drift.** `2022-latest` is a moving tag. The digest recorded above is what was measured. A later `podman pull` may bring a newer CU, and `db.sh` does not pin the digest.
8. **tempdb growth not measured.** Measuring it under load is S4's job.

## Round 2 (2026-09-24, after REVIEW-S0 M1)

The review found one must-fix, M1. When `MSSQL_SA_PASSWORD` did not match the volume, `up` retried for 120 s and then exited 6 blaming startup. `status` printed go-sqlcmd's `Login failed` text (which it writes to **stdout**) as the database list and as the TLS value. `down` would have waited 60 s and then SIGKILLed the server without a checkpoint. What changed in `scripts/db.sh` (only the infra parts):

| Change | Detail |
|---|---|
| `sa_probe` | Classifies an sa connection attempt as ok, refused or not ready. Refused means the client prints exactly `Login failed for user 'sa'.` with no `Reason:`, **and** the server log confirms `Login failed for user 'sa'. Reason: Password did not match`. Other refusals, such as script-upgrade mode during startup, count as not ready and are retried |
| `up` | A refused sa login exits **3** at once, with a message naming the env file, the volume-creation rule and the two fixes. A timeout is still exit 6, and its message now includes the last client error |
| `status` | Runs one sa probe first. On failure it prints `login sa FAILED: ...` and `databases unknown (listing needs sa)`, prints `tls=unknown`, still checks `ermine`, and exits 1 |
| `down` | A refused sa login exits 3 **without stopping**, because a kill would skip the checkpoint. `down --all` goes on to `podman rm -f` without SHUTDOWN, since the volume is deleted anyway |
| Nits | `load_env` reads only the two keys instead of sourcing the file, exports nothing (`ERMINE_DB_PASSWORD` goes only to the provisioning sqlcmd), checks the file owner as well as mode 600, and rejects passwords outside `[A-Za-z0-9_.-]{8,128}`, because they are substituted into T-SQL literals. `mkdir` of `/load` is checked (exit 4). `status extra`, `down --all extra` and `down <anything>` are usage errors (exit 2). Not changed: the image is still used by tag (known gap 7) and the doubled go-sqlcmd error line (upstream) |
| Bug found while testing | The first cut used `podman logs ... \| grep -q`. Under `pipefail`, grep's early exit SIGPIPEs podman and fails the pipeline, so the refusal was never confirmed and `up` still timed out after 120 s with exit 6. It now uses `grep -F ... >/dev/null` |

Test: once each, against the running container, **without** changing the real env file and **without** stopping the container (its `StartedAt` of 22:12:29 did not change). The wrong-password cases use a mode-600 copy of `db.env` with only `MSSQL_SA_PASSWORD` altered, passed as `ERMINE_DB_ENV=$T/bad-sa.env`. `$T` is the session scratchpad.

```
# round 2, after the fix. Wrong SA password: a copied env file with only MSSQL_SA_PASSWORD altered (ERMINE_DB_ENV=<copy>)
$ env ERMINE_DB_ENV=$T/bad-sa.env scripts/db.sh up
db.sh: sa login refused: MSSQL_SA_PASSWORD in $T/bad-sa.env does not match the server (the SA password is fixed when the volume ermine-mssql-data is created; restore the old value or run 'db.sh down --all' to recreate; tracker/db/CONTAINER.md known gap 1)
exit=3 (0s)
$ env ERMINE_DB_ENV=$T/bad-sa.env scripts/db.sh status
container ermine-mssql state=running health=healthy image=mcr.microsoft.com/mssql/server:2022-latest volume=present
login sa FAILED: password in $T/bad-sa.env does not match the server (fixed at volume creation; CONTAINER.md known gap 1)
databases unknown (listing needs sa)
login ermine ok via 127.0.0.1:1433 suser=ermine tls=unknown
memory sqlservr-rss=908M cap=MSSQL_MEMORY_LIMIT_MB=2048 host-avail=2.3G
status DEGRADED
exit=1 (0s)
$ env ERMINE_DB_ENV=$T/bad-sa.env scripts/db.sh down
db.sh: sa login refused: MSSQL_SA_PASSWORD in $T/bad-sa.env does not match the server (the SA password is fixed when the volume ermine-mssql-data is created; restore the old value or run 'db.sh down --all' to recreate; tracker/db/CONTAINER.md known gap 1); not stopping (a kill would skip the checkpoint)
exit=3 (0s)
# real env file
$ scripts/db.sh up
up already-running ready-after=0s login=ermine databases=ErmineSales,ErmineHR,ErmineScience port=127.0.0.1:1433
exit=0 (0s)
$ scripts/db.sh status
container ermine-mssql state=running health=healthy image=mcr.microsoft.com/mssql/server:2022-latest volume=present
databases present=ErmineHR,ErmineSales,ErmineScience missing=none
login ermine ok via 127.0.0.1:1433 suser=ermine tls=TRUE
memory sqlservr-rss=908M cap=MSSQL_MEMORY_LIMIT_MB=2048 host-avail=2.4G
status OK
exit=0 (1s)
$ scripts/db.sh sql ErmineSales SET NOCOUNT ON; SELECT SUSER_SNAME() -h -1 -W
ermine

exit=0 (0s)
$ scripts/db.sh status extra
exit=2 (usage printed)
$ scripts/db.sh down --all extra
exit=2 (usage printed)
$ scripts/db.sh down ErmineSales
exit=2 (usage printed)
```
