#!/usr/bin/env bash
# Run `bin/ermine` on every corpus file into <outdir>: ONE INVOCATION PER FILE by default,
# or all of them in ONE JVM with --batch.
#
#   tracker/tools/corpus-run.sh /tmp/corpus-base
#   tracker/tools/corpus-run.sh --batch /tmp/corpus-fast
#   ERMINE_JAVA_OPTS="-Dermine.resGuard=true" tracker/tools/corpus-run.sh /tmp/corpus-guard
#   diff -ru /tmp/corpus-base /tmp/corpus-guard
#
# PER FILE IS STILL THE DEFAULT, and it is the mode every adopted measurement in
# tracker/ROW-CONSTRAINT-STATE.md was taken in.  Per file, each module is compiled in a
# virgin session; in a batch it is compiled in a session that already holds every module
# ahead of it on the command line.  The verdicts came out identical on both corpora
# (2026-09-03: 0 of 66 and 0 of 34 differ, 23/43 and 18/16, `shouldfail/` 40/40) -- but seven
# modules print a DIFFERENT CLAUSE of the same refutation, at the same field and position.
# That is a measurement, not a guarantee: keep the default until a comparison you care about
# has been run both ways.  TICKET-editor-and-solver-followups.md item 4 has the numbers.
#
# --batch: ONE JVM for the whole corpus, split back into per-file `<name>.out` files by
# `tracker/tools/batch-split.py`, so `corpus-verdicts.py` and every diff built on it read a
# batch run exactly as they read a per-file one.  The saving is the stdlib boot, ~11 s per
# invocation:
#
#     66-file corpus     per file 19m22s   --batch 19.5s   (60x)
#     34-file incomplete per file  7m31s   --batch 15.4s   (29x)
#
# (measured 2026-09-03 on a shared machine, so the per-file side is an upper bound; the
# structural saving is one stdlib boot instead of N.)
#
# Batch loading was ruled out before 2026-09-03: the loader's dependency-order computation
# (`StreamTUtils.chop`/`postOrder`) recursed once per graph NODE and appended quadratically,
# so a big enough batch overflowed the stack partway through and both sides of a comparison
# were truncated -- which invalidated one corpus comparison in this work.  (At 98e7bf2 the
# threshold had moved: each corpus loaded in one JVM, all 110 files together did not.)  The
# computation is iterative now (TICKET-editor-and-solver-followups.md item 4).
# `batch-split.py` REFUSES to split a run that did not produce one terminator line per file,
# so a batch that dies partway is an error here rather than a partial count.
#
# Ai/ modules import `Ai.Common`, which the CLI cannot resolve on its own (the editor can,
# since lsp/Resident.scala `checkFile` was fixed), so `Common.e` goes first on the command
# line for those -- ahead of its group in a batch, immediately before each Ai module per file.
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
batch=0
while [[ ${1:-} == --* ]]; do
  case "$1" in
    --incomplete) incomplete=1; shift ;;
    --batch)      batch=1;      shift ;;
    *) echo "usage: corpus-run.sh [--incomplete] [--batch] <outdir>" >&2; exit 2 ;;
  esac
done
out="${1:?usage: corpus-run.sh [--incomplete] [--batch] <outdir>}"
timeout_s="${CORPUS_TIMEOUT:-120}"
batch_timeout_s="${CORPUS_BATCH_TIMEOUT:-900}"

mkdir -p "$out"
: > "$out/verdicts.txt"

# see the header: interfaces written by a previous run would be read by this one
find core/examples -name '*.ei' -delete

files=( core/examples/*.e core/examples/Ai/*.e core/examples/shouldfail/*.e )
if [[ $incomplete == 1 ]]; then files=( core/examples/incomplete/*.e ); fi

if [[ $batch == 1 ]]; then
  # one command line, with Ai/Common.e hoisted to the head of the Ai group
  bfiles=(); ai_done=0
  for f in "${files[@]}"; do
    case "$f" in
      core/examples/Ai/Common.e) ;;
      core/examples/Ai/*)
        if [[ $ai_done == 0 ]]; then bfiles+=( core/examples/Ai/Common.e ); ai_done=1; fi
        bfiles+=( "$f" ) ;;
      *) bfiles+=( "$f" ) ;;
    esac
  done
  if [[ -n ${ERMINE_CP:-} ]]; then
    read -r -a extra <<< "${ERMINE_JAVA_OPTS:-}"
    timeout "$batch_timeout_s" java -Dermine.typeCheck=true -Dermine.useInterface=false ${extra[@]+"${extra[@]}"} \
      -cp "$(cat "$ERMINE_CP")" com.clarifi.reporting.ermine.session.Console "${bfiles[@]}" \
      </dev/null > "$out/batch.log" 2>&1
  else
    ERMINE_JAVA_OPTS="-Dermine.useInterface=false ${ERMINE_JAVA_OPTS:-}" \
      timeout "$batch_timeout_s" bin/ermine "${bfiles[@]}" </dev/null > "$out/batch.log" 2>&1
  fi
  rc=$?
  # one exit code for the whole run: it distinguishes a timeout, nothing else (the verdict
  # a gate cares about is read out of the output by corpus-verdicts.py, as per file)
  for f in "${bfiles[@]}"; do printf '%s\t%s\n' "$rc" "$f" >> "$out/verdicts.txt"; done
  python3 tracker/tools/batch-split.py "$out/batch.log" "$out" "${bfiles[@]}" || exit 1
  echo "wrote $(ls "$out"/*.out | wc -l) outputs to $out (one JVM, exit $rc)"
  exit 0
fi

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
