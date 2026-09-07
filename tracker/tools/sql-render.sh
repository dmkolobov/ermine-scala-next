#!/usr/bin/env bash
# THE NEAREST THING THIS REPOSITORY HAS TO `render`.
#
#   tracker/tools/sql-render.sh <probe.e> <outdir>
#
# There is no `render` in ermine-scala: running a `Report` needs a `Writer f z`, and every
# concrete writer lives in the separate `ermine-writers` project (see tracker/loopmodel/
# E1-EXAMPLES.md section 7.1).  What CAN be done is compile a report's underlying RELATION to
# SQL with `Scanners.dumpQuery` and execute it, which exercises the whole relational pipeline
# -- join, group, pivot, window -- and produces a real table.  Every Ermine relation literal
# compiles to a table-value constructor, so the queries are self-contained and need no schema;
# that is the whole reason this works against an EMPTY database.
#
# <probe.e> is an Ermine module that imports the example modules and defines, for each
# relation to render, a String binding
#
#     lite = sqlite     cachedSMEnv      -- Scanners + Internal.SMEnv + IO.Unsafe
#     mss  = sqlServer  cachedSMEnv
#     q_foo = unsafePerformIO (dumpQuery lite theRelation)
#
# and <probe>.in drives the REPL over them.  THE `.in` FILE IS SELF-LABELLING: each binding
# name is preceded by the string literal `"@@<name>"`, so the extractor pairs a name with the
# answer that follows it instead of counting positions.  It used to count, and that was a
# latent defect (E1 review, N-7): a name the probe module does not define prints no `res`
# answer, which silently shifted every following name and would have written real SQL under
# the wrong `q_*` name.  The extractor now also FAILS LOUDLY if any name in the `.in` file
# never appears in the transcript.
#
# WHY TWO EMITTERS.  `SqlEmitter.emitOver` is a stub on every emitter except MS SQL, so a
# window function dumped through the SQLite scanner comes out as
# `TODO I don't yet know how to play RANK over SqlOver(...)` spliced into the query text.
# Dump window relations through `sqlServer` and non-window ones through `sqlite`;
# `tsql2sqlite.py` fixes the two dialect differences that matter (table-value constructors,
# and the missing space before `desc`).  The `OVER (partition by … order by … rows between …)`
# clauses pass through untouched -- SQLite has parsed them since 3.25.
#
# WHY python3 AND NOT A JVM.  This script used to shell out to a 35-line `SqlRun.java` run by
# single-file source launch, with the driver jar scraped out of `target/ermine-classpath`
# (`grep sqlite-jdbc`).  That was an undeclared dependency on a file `bin/ermine` happens to
# have written, and an empty `CP` failed per query with no diagnostic.  `python3`'s STDLIB
# `sqlite3` does the same job with no jar, no classpath and no JVM, so the execution step is
# now inline below (E1 review, N-8).  `SqlRun.java` was deleted with it.
#
# KNOWN LIMITS, all of them in E1-EXAMPLES.md section 7 and none of them this script's:
#   * a `Mem` (anything `groupBy` produces) answers "Don't know how to dump a mem"
#     (`Scanner.scala:35`, no `SqlScanner` override);
#   * `lookupLatest`/`nearestDate` materialise a temp table and answer
#     "Emission not supported for sql statement SqlLoad";
#   * any pivot PANICS in `Native.Record.scalaRecord#` before a query is ever produced;
#   * one statement is executed per query, so a plan that emits an `insert` ahead of its
#     `select` cannot run here;
#   * `SqlEmitter.scala:262` emits a join's LEFT and RIGHT operands bare
#     (`r1 … op … r2 on (…)`), so a right-nested join tree comes out as
#     `A join C join D on (c2) on (c3)`.  SQL-92 makes a `<joined table>` a `<table
#     reference>`, so T-SQL and Postgres re-associate that correctly; SQLite's join grammar is
#     a FLAT list and rejects two stacked `ON`s outright.  That is a PORTABILITY BUG IN THE
#     EMITTER, not in this route -- `SqliteEmitter` has the hook to parenthesise a join
#     operand that is itself a join and does not use it.  `Wide/` never trips it because its
#     join trees are left-deep (`fact ** dim ** dim`); `Algebra/` does.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
probe="${1:?usage: sql-render.sh <probe.e> <outdir>}"
out="${2:?usage: sql-render.sh <probe.e> <outdir>}"
inp="${probe%.e}.in"
mkdir -p "$out/sql" "$out/out"

modules=( ${ERMINE_RENDER_MODULES:-core/examples/Wide/Helpers.e $(find core/examples/Wide -maxdepth 1 -name '*.e' ! -name 'Helpers.e' | sort)} )
ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2 -Dermine.useInterface=false" \
  timeout "${RENDER_TIMEOUT:-1200}" bin/ermine "${modules[@]}" < "$inp" > "$out/probe.out" 2>&1
echo "probe rc=$?"
find core/examples/Wide -name '*.ei' -delete

python3 - "$out" "$inp" <<'PY' || exit 1
import re, sys, os
out, inp = sys.argv[1], sys.argv[2]
s = open(os.path.join(out, 'probe.out'), encoding='utf-8', errors='replace').read()
i = s.find('Importing module'); s = s[i:] if i >= 0 else s
# the names the .in file asks for, in order, taken from the `"@@name"` labels
wanted = [l.strip()[3:-1] for l in open(inp) if l.strip().startswith('"@@')]
seen, cur, bad = {}, None, 0
for p in re.split(r'\n>> ', s)[1:]:
    if not p.startswith('res'):
        continue
    lab = re.search(r'=\s*"@@([A-Za-z0-9_]+)"\s*$', p, re.S)
    if lab:                       # a label answer: it names the NEXT result
        cur = lab.group(1)
        continue
    if cur is None:
        continue
    name, cur = cur, None
    if 'error:' in p or 'Panic' in p:
        seen[name] = None
        print('%-18s ERR %s' % (name, p.replace('\n', ' ')[:100]))
        continue
    m = re.search(r'=\s*\n?\s*"(.*)"\s*$', p, re.S)
    if not m:
        seen[name] = None
        continue
    seen[name] = True
    open(os.path.join(out, 'sql', name + '.sql'), 'w').write(m.group(1).replace('\\"', '"'))
missing = [n for n in wanted if n not in seen]
if missing:
    print('FATAL: %d of %d probe names never answered: %s' % (len(missing), len(wanted), missing))
    sys.exit(1)
print('names: %d asked, %d answered, %d produced SQL'
      % (len(wanted), len(seen), sum(1 for v in seen.values() if v)))
PY

for f in "$out"/sql/*.sql; do
  [ -e "$f" ] || continue
  case "$f" in *.lite.sql) continue ;; esac
  n=$(basename "$f" .sql)
  if grep -q '\[' "$f"; then python3 tracker/tools/tsql2sqlite.py < "$f" > "$out/sql/$n.lite.sql"
  else cp "$f" "$out/sql/$n.lite.sql"; fi
  python3 - "$out/sql/$n.lite.sql" > "$out/out/$n.txt" 2>&1 <<'PY'
import sqlite3, sys
sql = open(sys.argv[1], encoding='utf-8').read().strip()
cur = sqlite3.connect(':memory:').execute(sql)
hdr = [d[0] for d in cur.description]
rows = cur.fetchall()
print(' | '.join(hdr))
print('-+-'.join('-' * max(3, len(h)) for h in hdr))
for r in rows:
    print(' | '.join('null' if v is None else str(v) for v in r))
print('(%d rows)' % len(rows))
PY
  echo "$n: $(tail -1 "$out/out/$n.txt")"
done
