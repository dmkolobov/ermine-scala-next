#!/usr/bin/env bash
# Mutation harness: inject known bug classes into the source a gate claims to guard, run that gate,
# and assert the gate goes red.  A mutant the gate lets through is a SILENTLY BROKEN GATE.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/gates.sh
source "$HERE/gates.sh"

usage() {
  cat <<'EOF'
usage: scripts/mutate-and-verify.sh [--gates "G1 G2" | --tier commit|pr|nightly] [-n N] [--seed S]
                                    [--classes obo,swap,guard,mapord] [--lanes L] [--out DIR]
                                    [--keep-lanes] [--plan-only]

For every selected gate that declares a mutation scope (scripts/gates.sh, GATE_SCOPE):
  1. BASELINE: the gate must be green on the unmutated commit (scripts/gate.sh, so a result already
     cached for this content is re-used, never re-run).  A red baseline is reported as
     BROKEN-BASELINE and its mutants are not run: they would be "caught" by a gate that is red anyway.
  2. For each bug class, N mutants drawn (deterministically from --seed) from the gate's scope by
     scripts/mutate.py.  A mutant that does not compile is STILLBORN and the next site is tried.
  3. Each mutant is applied in a scratch worktree ("lane"), compiled, and the gate is run on it
     (scripts/gate.sh run --no-cache-write).  Red => CAUGHT.  Green => SURVIVED.
  4. Lanes are reset to the commit after every mutant; the checkout you run from is never edited.
Lanes check out HEAD, so the scoped sources must be committed. The gate definitions and tools the
lanes run are HEAD's too, except scripts/gate.sh and scripts/gates.sh, which come from this checkout.

  --gates / --tier  which gates (default: --tier pr)
  -n N              mutants per bug class per gate (default 1)
  --seed S          site selection seed (default 1)
  --lanes L         parallel scratch worktrees (default 2)
  --out DIR         default .mutation-runs/<commit>-s<seed> at the main checkout root
  --keep-lanes      leave the scratch worktrees in place
  --plan-only       print the first-choice mutant of every slot and stop (no build, no gate runs)

Env: MUTATE_MIN_MEM_GB (default 4): a lane waits before a build or a gate run until the machine has
this much MemAvailable, so the harness never starves other work on the machine.

Survivors listed in scripts/mutations.equivalent (`<mutant id> <reason>`) are reported as
EQUIVALENT instead: only for mutants shown not to change behaviour, with the reason written down.

Output: one line per mutant; then a per-gate table; then a banner naming every survivor.
exit: 0 every mutant caught; 1 a mutant SURVIVED or a baseline was red; 2 usage;
      3 the tree is dirty or a gate was UNAVAILABLE
EOF
}

gates_arg=""; tier=pr; n=1; seed=1; classes=obo,swap,guard,mapord; lanes=2; out=""; keep=0; planonly=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --gates) gates_arg="$2"; shift 2 ;;
    --tier) tier="$2"; shift 2 ;;
    -n) n="$2"; shift 2 ;;
    --seed) seed="$2"; shift 2 ;;
    --classes) classes="$2"; shift 2 ;;
    --lanes) lanes="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --keep-lanes) keep=1; shift ;;
    --plan-only) planonly=1; shift ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ $n =~ ^[1-9][0-9]*$ && $lanes =~ ^[1-9]$ ]] || { usage >&2; exit 2; }

top=$(git rev-parse --show-toplevel) || exit 2
cd "$top"
if [[ -n $gates_arg ]]; then gates=$gates_arg; else
  gates=$(for g in $GATE_ORDER; do tier_includes "$tier" "${GATE_TIER[$g]}" && echo "$g"; done)
fi
for g in $gates; do [[ -n ${GATE_TIER[$g]:-} ]] || { echo "unknown gate $g" >&2; exit 2; }; done

# lanes check out HEAD and mutants carry HEAD's line numbers, so every scoped source must be committed
for g in $gates; do
  # shellcheck disable=SC2086
  if [[ -n ${GATE_SCOPE[$g]:-} ]] && ! git diff --quiet HEAD -- ${GATE_SCOPE[$g]}; then
    echo "mutate: $g's scope has uncommitted changes; mutants are drawn from HEAD (commit first)"; exit 3
  fi
done

if [[ $planonly == 1 ]]; then
  for g in $gates; do
    [[ -n ${GATE_SCOPE[$g]:-} ]] || { echo "$g: not mutation-tested (${GATE_NOSCOPE[$g]:-no scope})"; continue; }
    # shellcheck disable=SC2086
    python3 "$HERE/mutate.py" candidates --gate "$g" --seed "$seed" --classes "$classes" ${GATE_SCOPE[$g]} |
      python3 -c '
import json, sys, collections
n = int(sys.argv[1]); seen = collections.Counter(); tot = collections.Counter()
rows = [json.loads(l) for l in sys.stdin]
for m in rows: tot[m["class"]] += 1
for m in rows:
    if seen[m["class"]] < n:
        seen[m["class"]] += 1
        print("%s %-6s %s:%d  (%d sites)\n    - %s\n    + %s" % (m["gate"], m["class"], m["file"].split("/")[-1], m["line"], tot[m["class"]], m["before"].strip()[:110], m["after"].strip()[:110]))
' "$n"
  done
  exit 0
fi

sha=$(git rev-parse HEAD)
root=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
out="${out:-$root/.mutation-runs/${sha:0:8}-s$seed}"
mkdir -p "$out"/{jobs,claimed,runs} || exit 2
results="$out/results.tsv"
printf 'gate\tclass\tverdict\tid\tsite\tseconds\tbefore\tafter\n' > "$results"


# lanes share the machine with whatever else runs (the user's editor included): a lane starts a
# build or a gate only while MemAvailable stays above MUTATE_MIN_MEM_GB (default 4)
wait_for_memory() {
  local want=$(( ${MUTATE_MIN_MEM_GB:-4} * 1048576 ))
  while (( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) < want )); do sleep 15; done
}

lane_dir() { echo "$out/lane-$1"; }
prepare_lane() {
  local d; d=$(lane_dir "$1")
  if [[ ! -d $d ]]; then git worktree add --detach "$d" "$sha" > /dev/null 2>&1 || return 1; fi
  ( cd "$d" && git checkout -q -f "$sha" && gate_env && gate_build > "$out/lane-$1.prep.log" 2>&1 )
}
cleanup() {
  [[ $keep == 1 ]] && return
  local i; for ((i = 1; i <= lanes; i++)); do git worktree remove --force "$(lane_dir $i)" > /dev/null 2>&1; done
}
trap cleanup EXIT

echo "mutate: commit ${sha:0:8} seed=$seed n=$n classes=$classes lanes=$lanes out=$out"
for ((i = 1; i <= lanes; i++)); do prepare_lane "$i" & done; wait
for ((i = 1; i <= lanes; i++)); do
  [[ -d $(lane_dir $i)/core/target ]] || { echo "mutate: lane $i failed to build (see $out/lane-$i.prep.log)"; exit 3; }
done

# 1. baselines (in lane 1: same content as the commit, so scripts/gate.sh re-uses any cached run) ----
declare -A broken=()
for g in $gates; do
  if [[ -z ${GATE_SCOPE[$g]:-} ]]; then
    echo "mutate: $g has no mutation scope (${GATE_NOSCOPE[$g]:-not declared}); skipped"
    printf '%s\t-\tNOT-MUTATION-TESTED\t-\t-\t-\t-\t%s\n' "$g" "${GATE_NOSCOPE[$g]:-}" >> "$results"
    continue
  fi
  line=$(cd "$(lane_dir 1)" && "$HERE/gate.sh" run "$g" 2>&1 | tail -1)
  echo "mutate: baseline $line"
  case "$line" in
    *" PASS "*|*" CACHED-PASS "*) ;;
    *" UNAVAILABLE "*) broken[$g]=UNAVAILABLE ;;
    *) broken[$g]=BROKEN-BASELINE ;;
  esac
  if [[ -n ${broken[$g]:-} ]]; then
    printf '%s\t-\t%s\t-\t-\t-\t-\t%s\n' "$g" "${broken[$g]}" "$line" >> "$results"
    continue
  fi
  # 2. plan: one job per (gate, class, slot), each carrying its pool of candidate sites
  cand="$out/candidates-$g.jsonl"
  # shellcheck disable=SC2086
  python3 "$HERE/mutate.py" candidates --gate "$g" --seed "$seed" --classes "$classes" ${GATE_SCOPE[$g]} > "$cand"
  for c in ${classes//,/ }; do
    grep "\"class\": \"$c\"" "$cand" > "$out/pool-$g-$c.jsonl"
    total=$(wc -l < "$out/pool-$g-$c.jsonl")
    for ((k = 0; k < n; k++)); do
      # each slot gets its own disjoint slice of 6 sites (the first that compiles is used)
      sed -n "$((k * 6 + 1)),$((k * 6 + 6))p" "$out/pool-$g-$c.jsonl" > "$out/jobs/$g.$c.$k"
      [[ -s $out/jobs/$g.$c.$k ]] || { rm -f "$out/jobs/$g.$c.$k"
        printf '%s\t%s\tNO-SITE\t-\t-\t-\t-\t%s candidates in scope\n' "$g" "$c" "$total" >> "$results"; }
    done
  done
done

# 3. lanes drain the job queue ------------------------------------------------------------------------
run_lane() {
  local i=$1 d job g c m id site cls t0 rc verdict
  d=$(lane_dir "$i")
  cd "$d" || return
  gate_env
  while :; do
    job=$(ls "$out/jobs" 2>/dev/null | head -1)
    [[ -n $job ]] || break
    mv "$out/jobs/$job" "$out/claimed/$job.$i" 2>/dev/null || continue
    g=${job%%.*}; c=${job#*.}; c=${c%%.*}
    verdict=""
    while IFS= read -r m; do
      id=$(python3 -c 'import json,sys; m=json.loads(sys.argv[1]); print(m["id"])' "$m")
      site=$(python3 -c 'import json,sys; m=json.loads(sys.argv[1]); print("%s:%d" % (m["file"], m["line"]))' "$m")
      git checkout -q -f "$sha" && git clean -fdq -e target -e '*.ei' > /dev/null
      python3 "$HERE/mutate.py" apply "$m" || { echo "$g $c $id APPLY-FAILED $site"; continue; }
      wait_for_memory
      t0=$SECONDS
      if ! timeout 1800 bash -c 'source "$1/gates.sh"; gate_env; gate_build' _ "$HERE" > "$out/runs/$id.build.log" 2>&1; then
        printf '%s\t%s\tSTILLBORN\t%s\t%s\t%s\t%s\t%s\n' "$g" "$c" "$id" "$site" "$((SECONDS - t0))" \
          "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["before"].strip())' "$m")" \
          "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["after"].strip())' "$m")" >> "$results"
        echo "mutant $g $c $id STILLBORN $site"
        continue
      fi
      wait_for_memory
      "$HERE/gate.sh" run "$g" --no-cache-write --log-dir "$out/runs/$id" > "$out/runs/$id.gate.txt" 2>&1
      rc=$?
      case $rc in
        0) verdict=SURVIVED ;;
        1) verdict=CAUGHT ;;
        3) verdict=UNAVAILABLE ;;
        *) verdict="ERROR-$rc" ;;
      esac
      if [[ $verdict == SURVIVED ]] && grep -q "^$id " "$HERE/mutations.equivalent" 2>/dev/null; then verdict=EQUIVALENT; fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$g" "$c" "$verdict" "$id" "$site" "$((SECONDS - t0))" \
        "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["before"].strip())' "$m")" \
        "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["after"].strip())' "$m")" >> "$results"
      echo "mutant $g $c $id $verdict $site $((SECONDS - t0))s"
      break
    done < "$out/claimed/$job.$i"
    [[ -n $verdict ]] || printf '%s\t%s\tALL-STILLBORN\t-\t-\t-\t-\t%s\n' "$g" "$c" "$job" >> "$results"
  done
  git checkout -q -f "$sha"
}
for ((i = 1; i <= lanes; i++)); do run_lane "$i" & done
wait

# 4. report ---------------------------------------------------------------------------------------
python3 - "$results" <<'PY'
import collections, csv, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
per = collections.defaultdict(collections.Counter)
for r in rows:
    per[r["gate"]][r["verdict"]] += 1
print("\n%-18s %6s %8s %9s %10s %9s  %s" % ("gate", "caught", "survived", "stillborn", "equivalent", "no-site", "other"))
for g, c in per.items():
    other = {k: v for k, v in c.items() if k not in ("CAUGHT", "SURVIVED", "STILLBORN", "EQUIVALENT", "NO-SITE")}
    print("%-18s %6d %8d %9d %10d %9d  %s" % (g, c["CAUGHT"], c["SURVIVED"], c["STILLBORN"], c["EQUIVALENT"],
                                              c["NO-SITE"], " ".join("%s=%d" % kv for kv in other.items())))
bad = [r for r in rows if r["verdict"] in ("SURVIVED", "BROKEN-BASELINE")]
if bad:
    print("\n" + "!" * 100)
    print("!!! SILENTLY BROKEN GATES: %d mutant(s) survived or a baseline was red" % len(bad))
    for r in bad:
        print("!!! %-16s %-8s %-16s %s" % (r["gate"], r["class"], r["verdict"], r["site"]))
        if r["before"] != "-":
            print("!!!     - %s\n!!!     + %s" % (r["before"][:140], r["after"][:140]))
    print("!" * 100)
PY
if grep -qP '\t(SURVIVED|BROKEN-BASELINE)\t' "$results"; then exit 1; fi
if grep -qP '\t(UNAVAILABLE|ERROR-[0-9]+|ALL-STILLBORN)\t' "$results"; then exit 3; fi
exit 0
