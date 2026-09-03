#!/usr/bin/env bash
# run.sh <file.e|.slow> <tag> [timeout_s]   -- one JVM, default solver flags, row trace on.
# Writes runs/<tag>.out (raw), runs/<tag>.txt (\r->\n), runs/<tag>.tsv (row trace);
# appends one line to runs/RUNS.tsv:  tag  wall  rc  verdict  boot=<s>  mod=<s>  mem_avail_gb
set -uo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
S=/tmp/claude-1000/-home-dmitry-research-ermine/8ad54026-1a3a-4b68-a018-ea52aca01453/scratchpad/satterm/measure
OUT=$S/runs
f="$1"; tag="$2"; to="${3:-120}"
cd /home/dmitry/research/ermine/ermine-scala
# wait for >= 4 GB available (machine is shared)
while :; do av=$(free -g | awk '/^Mem:/{print $7}'); [ "$av" -ge 4 ] && break; sleep 10; done
if pgrep -f '^java .*ermine[.]session[.]Console' >/dev/null; then echo "another Console JVM is running; refusing" >&2; exit 2; fi
d="$(dirname "$f")"
before=$(find "$d" -maxdepth 1 -name '*.ei' 2>/dev/null | sort)
trace=$OUT/$tag.tsv; : > "$trace"
start=$(date +%s.%N)
if [ -n "$f" ]; then
  ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Xmx2g -Dermine.rowTrace=$trace" timeout "$to" bin/ermine "$f" </dev/null > "$OUT/$tag.out" 2>&1
else
  ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Xmx2g -Dermine.rowTrace=$trace" timeout "$to" bin/ermine </dev/null > "$OUT/$tag.out" 2>&1
fi
rc=$?
end=$(date +%s.%N)
wall=$(echo "$end - $start" | bc)
tr '\r' '\n' < "$OUT/$tag.out" > "$OUT/$tag.txt"
boot=$(grep -o "Loaded [A-Za-z0-9-]* modules ([0-9.,]* seconds)" "$OUT/$tag.txt" | tail -1 | grep -o '([0-9.,]*' | tr -d '(')
mod=$(grep -o "Importing module '[^']*' ([0-9.,]* seconds)" "$OUT/$tag.txt" | tail -1)
modsecs=$(echo "$mod" | grep -o '([0-9.,]*' | tr -d '(')
if [ "$rc" = 124 ]; then verdict=TIMEOUT
elif grep -q "Unable to load module" "$OUT/$tag.txt"; then verdict=REJECTED
elif [ -n "$mod" ]; then verdict=LOADED
elif [ -z "$f" ]; then verdict=BOOT
else verdict=UNKNOWN; fi
# delete only .ei files that this run created
after=$(find "$d" -maxdepth 1 -name '*.ei' 2>/dev/null | sort)
comm -13 <(echo "$before") <(echo "$after") | while read -r x; do [ -n "$x" ] && rm -f "$x" && echo "deleted stray $x" >&2; done
printf '%s\t%s\t%s\t%s\tboot=%s\tmod=%s\tavail=%s\n' "$tag" "$wall" "$rc" "$verdict" "${boot:-?}" "${modsecs:-?}" "$av" | tee -a "$OUT/RUNS.tsv"
