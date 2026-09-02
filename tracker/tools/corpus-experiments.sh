#!/usr/bin/env bash
# Mine the EXAMPLE corpus for what the row-solver flags actually do, rather than asking a
# synthetic probe.  Ticket §7.9: zero of 383 stdlib solve inputs carry a concrete label
# against 39% in core/examples, so the examples are the only population that can answer
# any of this.  See tracker/TICKET-row-solver-8abc.md.
#
#   tracker/tools/corpus-experiments.sh /tmp/exp            # both parts
#   tracker/tools/corpus-experiments.sh /tmp/exp trace      # part 1 only
#   tracker/tools/corpus-experiments.sh /tmp/exp slow       # part 2 only
#
# PART 1 -- one `-Dermine.rowTrace` pass over every example module, answering two things
# at once:
#   * does `resolution` fire on real code?  (if not, `-Dermine.resGuard` has no target
#     outside the probes, and that is the honest headline)
#   * how often is `Subst.reduce`'s splice NOT conservative -- the three flags
#     hlhs/hdis/hdup of `Rowpartition.splice_entails_iff`, which is ticket item 8b
#
# PART 2 -- the six `.slow` modules that diverge, plus the two cheap-end cases `gu01`/`gu05`
# that terminate.  core/examples/incomplete/README.md records that all six run fast under
# `genRules=cut` (today's default) and time out under `genRules=all`, and that the driver
# is `commonSubexpression`, not `resolution`.  So this measures whether guarding
# `resolution` helps where CSE is the cause -- the prediction is NO, and a surprise either
# way is worth having.  Note `corpus-run.sh --incomplete` globs `*.e` and therefore SKIPS
# the `.slow` files; they need this explicit run.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$here"
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
out="${1:?usage: corpus-experiments.sh <outdir> [trace|slow]}"
what="${2:-both}"
mkdir -p "$out"

run() {  # run <outfile> <flags> <files...>
  local of="$1"; shift
  local flags="$1"; shift
  ERMINE_JAVA_OPTS="-Dermine.useInterface=false $flags" \
    timeout "${EXP_TIMEOUT:-120}" bin/ermine "$@" </dev/null > "$of" 2>&1
}

if [[ $what == both || $what == trace ]]; then
  echo "######## PART 1: one traced pass over every example module"
  trace="$out/trace.tsv"; : > "$trace"
  find core/examples -name '*.ei' -delete
  mapfile -t files < <(find core/examples -name '*.e' | sort)
  for f in "${files[@]}"; do
    args=( "$f" )
    case "$f" in
      core/examples/Ai/Common.e) ;;
      core/examples/Ai/*)        args=( core/examples/Ai/Common.e "$f" ) ;;
    esac
    run "$out/$(echo "${f#core/examples/}" | tr '/' '_').out" "-Dermine.rowTrace=$trace" "${args[@]}"
  done
  echo "== ${#files[@]} modules traced"
  python3 tracker/tools/rowtrace-summary.py "$trace"
  echo
  echo "== does resolution fire on real code?  per-file Resolution derivations"
  awk -F'\t' '$1=="solve" && $10!="-" {
      n=split($10,a,","); for(i=1;i<=n;i++){ split(a[i],b,":");
        if(b[1]=="Resolution") { sub(/^.*modules\//,"",$3); print $3, b[2] } } }' "$trace" \
    | sort | uniq -c | sort -rn | head -20
  echo "  (empty above = resolution never fires on the example corpus either)"
  echo
  echo "== non-conservative splices (item 8b), per file"
  awk -F'\t' '$1=="splice" && NF>=11 && !($9=="true" && $10=="true" && $11=="true") {
      print $3, "changed="$8, "hlhs="$9, "hdis="$10, "hdup="$11 }' "$trace" \
    | sort | uniq -c | sort -rn | head -20
  echo "  (empty above = every splice the compiler performs is provably conservative)"
fi

if [[ $what == both || $what == slow ]]; then
  echo
  echo "######## PART 2: the divergers, four configurations"
  slow=( core/examples/incomplete/gu02_star_join_7dim_inferred.slow
         core/examples/incomplete/gu03_star_join_8dim_inferred.slow
         core/examples/incomplete/gu07_label_helper_callsite.slow
         core/examples/incomplete/gu09_star_join_halves_composed.slow
         core/examples/incomplete/np05a_inferring_the_helper.slow
         core/examples/incomplete/np05c_helper_at_a_call_site.slow
         core/examples/incomplete/gu01_star_join_6dim_inferred.e
         core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e )
  printf '%-42s %-34s %9s %s\n' module flags wall verdict
  for f in "${slow[@]}"; do
    for flags in "" \
                 "-Dermine.resGuard=true" \
                 "-Dermine.genRules=all" \
                 "-Dermine.genRules=all -Dermine.resGuard=true"; do
      tag="${flags:-default}"
      of="$out/slow_$(basename "$f")_$(echo "$tag" | tr -c 'A-Za-z0-9' '_').out"
      s=$(date +%s.%N); run "$of" "$flags" "$f"; rc=$?; e=$(date +%s.%N)
      if [[ $rc == 124 ]]; then
        printf '%-42s %-34s %9s %s\n' "$(basename "$f")" "$tag" TIMEOUT "-"
      else
        v=$(grep -q "Unable to load module" "$of" && echo REJECTED || echo LOADED)
        printf '%-42s %-34s %9.1f %s\n' "$(basename "$f")" "$tag" "$(echo "$e - $s" | bc)" "$v"
      fi
    done
  done
  echo
  echo "(subtract the ~12s stdlib boot from every figure)"
fi
