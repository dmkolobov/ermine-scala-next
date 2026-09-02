#!/usr/bin/env bash
# Run `bin/ermine` on every corpus file, ONE INVOCATION PER FILE, into <outdir>.
#
#   tracker/tools/corpus-run.sh /tmp/corpus-base
#   ERMINE_JAVA_OPTS="-Dermine.resGuard=true" tracker/tools/corpus-run.sh /tmp/corpus-guard
#   diff -ru /tmp/corpus-base /tmp/corpus-guard
#
# WHY PER FILE.  The module loader StackOverflows in `StreamTUtils.chop` after roughly
# two heavy modules in one invocation (tracker/ROW-CONSTRAINT-STATE.md, "Traps").  A
# batch load therefore dies partway and BOTH sides of a comparison are truncated, which
# has already invalidated one corpus comparison in this work.  Never batch-load.
#
# Ai/ modules import `Ai.Common`, which the CLI cannot resolve on its own (the editor
# can, since lsp/Resident.scala `checkFile` was fixed), so `Common.e` goes first on the
# command line for those.
#
# CRITICAL: `bin/ermine` WRITES `.ei` interface files next to the sources it loads, and
# `ermine.useInterface` defaults to TRUE, so a second run READS what the first one wrote and
# never re-runs the solver on those modules.  That silently invalidates any A/B comparison:
# it showed up on 2026-09-01 as the type-hole report vanishing from `Holes.e` and the boot
# dropping from 12s to 5.6s on the second side.  This script therefore deletes generated
# `.ei` files before each run AND passes `-Dermine.useInterface=false`.
#
# SNAPSHOT THE CLASSES FIRST if you intend to recompile while a sweep runs.  `bin/ermine`
# puts the LIVE `*/target/scala-*/classes` directories on the classpath, so an `sbt compile`
# during a sweep changes the compiler under the running JVMs and the two sides of an A/B
# stop being what they claim.  Set ERMINE_CP to a file holding a classpath whose class
# directories are copies, e.g.
#
#   snap=/tmp/snap-base; mkdir -p $snap; cp=""
#   while IFS= read -r p; do
#     if [[ -d $p ]]; then m=$(echo "$p" | sed "s|$PWD/||; s|/target/.*||"); mkdir -p $snap/$m
#       cp -r "$p" $snap/$m/classes; cp+="$snap/$m/classes:"; else cp+="$p:"; fi
#   done < <(tr ':' '\n' < target/ermine-classpath); echo "${cp%:}" > $snap/classpath
#   ERMINE_CP=$snap/classpath tracker/tools/corpus-run.sh /tmp/corpus-base
#
# (2026-09-02: the labelCheckEarly adoption was measured this way, four sweeps in flight
# while the fix was being compiled.)
#
# Directories covered, 66 files: core/examples/*.e (15), core/examples/Ai/*.e (11),
# core/examples/shouldfail/*.e (40).  `incomplete/` is NOT here: four of its modules
# diverge on pristine code and are named `.slow` for that reason; use --incomplete for
# it, which applies a timeout per file.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
# set it here rather than relying on the caller: a background invocation without it
# produces 66 files of `bin/ermine: exec: java: not found` and a comparison that reads
# "0 of 66 differ" (2026-09-02)
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH

incomplete=0
if [[ ${1:-} == "--incomplete" ]]; then incomplete=1; shift; fi
out="${1:?usage: corpus-run.sh [--incomplete] <outdir>}"
timeout_s="${CORPUS_TIMEOUT:-120}"

mkdir -p "$out"
: > "$out/verdicts.txt"

# see the header: interfaces written by a previous run would be read by this one
find core/examples -name '*.ei' -delete

files=( core/examples/*.e core/examples/Ai/*.e core/examples/shouldfail/*.e )
if [[ $incomplete == 1 ]]; then files=( core/examples/incomplete/*.e ); fi

for f in "${files[@]}"; do
  name="${f#core/examples/}"; name="${name//\//_}"
  args=( "$f" )
  case "$f" in
    core/examples/Ai/Common.e) ;;
    core/examples/Ai/*)        args=( core/examples/Ai/Common.e "$f" ) ;;
  esac
  if [[ -n ${ERMINE_CP:-} ]]; then
    # same JVM invocation as bin/ermine, classpath from the snapshot file
    read -r -a extra <<< "${ERMINE_JAVA_OPTS:-}"
    timeout "$timeout_s" java -Dermine.typeCheck=true -Dermine.useInterface=false ${extra[@]+"${extra[@]}"} \
      -cp "$(cat "$ERMINE_CP")" com.clarifi.reporting.ermine.session.Console "${args[@]}" \
      </dev/null > "$out/$name.out" 2>&1
  else
    ERMINE_JAVA_OPTS="-Dermine.useInterface=false ${ERMINE_JAVA_OPTS:-}" \
      timeout "$timeout_s" bin/ermine "${args[@]}" </dev/null > "$out/$name.out" 2>&1
  fi
  rc=$?
  printf '%s\t%s\n' "$rc" "$f" >> "$out/verdicts.txt"
done

echo "wrote $(ls "$out"/*.out | wc -l) outputs to $out"
