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
# Directories covered, 66 files: core/examples/*.e (15), core/examples/Ai/*.e (11),
# core/examples/shouldfail/*.e (40).  `incomplete/` is NOT here: four of its modules
# diverge on pristine code and are named `.slow` for that reason; use --incomplete for
# it, which applies a timeout per file.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"

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
  ERMINE_JAVA_OPTS="-Dermine.useInterface=false ${ERMINE_JAVA_OPTS:-}" \
    timeout "$timeout_s" bin/ermine "${args[@]}" </dev/null > "$out/$name.out" 2>&1
  rc=$?
  printf '%s\t%s\n' "$rc" "$f" >> "$out/verdicts.txt"
done

echo "wrote $(ls "$out"/*.out | wc -l) outputs to $out"
