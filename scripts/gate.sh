#!/usr/bin/env bash
# The gate runner of docs/gate-policy.md: runs named gates or whole tiers, and never runs the same
# gate twice on the same content.  Results are cached in .gate-cache/ at the MAIN checkout's root
# (shared by every worktree), keyed by the tree SHA of the content under test + the gate name.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/gates.sh
source "$HERE/gates.sh"

usage() {
  cat <<'EOF'
usage: scripts/gate.sh run TARGET... [--log-dir DIR] [--no-cache-write]
       scripts/gate.sh status [COMMIT]       cached results for COMMIT's tree (default HEAD)
       scripts/gate.sh list                  every gate: tier, timeout, scope
       scripts/gate.sh key                   the cache key (tree SHA) of the working tree

TARGET is a gate name or a tier: commit | pr | nightly (a tier runs every gate listed for it;
`pr` includes `commit`, `nightly` includes `pr`).

THE RULE: a gate never runs twice on the same content.  The key is the tree SHA of the working
tree INCLUDING uncommitted and untracked (not ignored) files, so a run before `git commit` is the
run for the commit that follows (a commit has exactly one tree), and an amend or rebase that
does not change content re-uses it.  A cached PASS or FAIL is final: it is printed, not re-run.
To get a different answer, change the content.  UNAVAILABLE (a precondition such as the Lean
binary was missing, so the gate did not run) is not cached.  A second process asking for the
same key + gate while one is running gets exit 6, not a duplicate run, and so does a second gate
run in the same worktree (the tools rewrite in-tree state such as .ei files).

  --log-dir DIR       where gate logs go (default .gate-cache/<key>/<gate>/)
  --no-cache-write    run without recording (the mutation harness still reads nothing either:
                      a mutant has its own content key)

Output: one line per gate: `gate <name> PASS|FAIL|UNAVAILABLE|CACHED-PASS|CACHED-FAIL <secs>s <summary>`.
exit: 0 all pass; 1 a gate failed; 2 usage; 3 a gate was unavailable (and none failed);
      6 locked (the same key + gate is running now)
EOF
}

take_lock() {  # take_lock PATH: a symlink whose target is our pid; creating it is atomic
  ln -s "$$" "$1" 2>/dev/null && return 0
  local pid; pid=$(readlink "$1" 2>/dev/null)
  [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && return 1
  rm -f "$1"                         # stale: its process is gone
  ln -s "$$" "$1" 2>/dev/null
}

common_root() { local c; c=$(git rev-parse --path-format=absolute --git-common-dir) || return 1; dirname "$c"; }

tree_key() {  # tree SHA of HEAD + every uncommitted/untracked change, without touching the real index
  # A FRESH index, not a copy of the worktree's: a copy carries stat data, and an edit that keeps a
  # file's size within the same mtime second is then invisible to `git add` (a same-size mutant got
  # HEAD's key and a cached PASS).  Hashing every file costs ~0.2 s.
  local idx; idx=$(mktemp) || return 1
  GIT_INDEX_FILE=$idx git read-tree HEAD || { rm -f "$idx"; return 1; }
  # the cache and mutation runs live at the main checkout's root: never part of anyone's content
  GIT_INDEX_FILE=$idx git add -A -- . ':!.gate-cache' ':!.mutation-runs' >/dev/null 2>&1 &&
    GIT_INDEX_FILE=$idx git write-tree
  local rc=$?; rm -f "$idx"; return $rc
}

expand_targets() {
  local t g
  for t in "$@"; do
    case $t in
      commit|pr|nightly) for g in $GATE_ORDER; do if tier_includes "$t" "${GATE_TIER[$g]}"; then echo "$g"; fi; done ;;
      *) [[ -n ${GATE_TIER[$t]:-} ]] || { echo "unknown gate or tier: $t" >&2; return 2; }; echo "$t" ;;
    esac
  done | awk '!seen[$0]++'
}

cmd=${1:-}; shift || true
case $cmd in
  -h|--help|"") usage; [[ -n $cmd ]]; exit $? ;;
  list)
    for g in $GATE_ORDER; do
      printf '%-12s tier=%-8s timeout=%5ss  %s\n' "$g" "${GATE_TIER[$g]}" "${GATE_TIMEOUT[$g]}" "${GATE_DESC[$g]}"
    done; exit 0 ;;
  key) tree_key; exit $? ;;
  status)
    root=$(common_root) || exit 2
    tree=$(git rev-parse "${1:-HEAD}^{tree}") || exit 2
    for g in $GATE_ORDER; do
      k=$tree; [[ -n ${GATE_KEYPATH[$g]:-} ]] && k=$(git rev-parse "$tree:${GATE_KEYPATH[$g]}")
      f="$root/.gate-cache/$k/$g.result"
      if [[ -f $f ]]; then
        awk -F= '{a[$1]=substr($0, length($1)+2)} END {printf "%-16s %-5s %6ss %s  %s\n", a["gate"], a["status"], a["seconds"], a["finished"], a["summary"]}' "$f"
      else printf '%-16s %-5s\n' "$g" "-"; fi
    done; exit 0 ;;
  run) ;;
  *) usage >&2; exit 2 ;;
esac

targets=(); logroot=""; write=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-dir) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; logroot="$2"; shift 2 ;;
    --no-cache-write) write=0; shift ;;
    -*) usage >&2; exit 2 ;;
    *) targets+=( "$1" ); shift ;;
  esac
done
[[ ${#targets[@]} -gt 0 ]] || { usage >&2; exit 2; }
gates=$(expand_targets "${targets[@]}") || exit 2

top=$(git rev-parse --show-toplevel) || exit 2
cd "$top" || exit 2
root=$(common_root) || exit 2
# one gate run per WORKTREE at a time as well: the tools delete and rewrite in-tree state (.ei files,
# tracker/repl-classpath.txt), so two gates in one checkout clobber each other whatever their keys
wtlock="$(git rev-parse --absolute-git-dir)/gate-run.lock"
if ! take_lock "$wtlock"; then echo "gate: LOCKED another gate run (pid $(readlink "$wtlock")) is using $top"; exit 6; fi
trap 'rm -f "$wtlock"' EXIT
key=$(tree_key) || { echo "gate: cannot compute the tree key" >&2; exit 2; }
gate_env

worst=0
for g in $gates; do
  # a gate that reads only part of the tree (GATE_KEYPATH) is keyed by that subtree
  gkey=$key
  [[ -n ${GATE_KEYPATH[$g]:-} ]] && gkey=$(git rev-parse "$key:${GATE_KEYPATH[$g]}")
  cache="$root/.gate-cache/$gkey"; mkdir -p "$cache"
  res="$cache/$g.result"
  if [[ -f $res ]]; then
    st=$(sed -n 's/^status=//p' "$res"); secs=$(sed -n 's/^seconds=//p' "$res"); sum=$(sed -n 's/^summary=//p' "$res")
    echo "gate $g CACHED-$st ${secs}s $sum"
    [[ $st == FAIL ]] && worst=1
    continue
  fi
  lock="$cache/$g.lock"
  if ! take_lock "$lock"; then echo "gate $g LOCKED key=$gkey pid=$(readlink "$lock")"; exit 6; fi
  out="${logroot:+$logroot/$g}"; out="${out:-$cache/$g}"
  rm -rf "$out"; mkdir -p "$out"
  started=$(date -Is); SECONDS=0
  GATE_OUT=$out GATE_LOG=$out/gate.log timeout --kill-after=30 "${GATE_TIMEOUT[$g]}" bash -c "source '$HERE/gates.sh'; gate_env; gate_$g" > "$out/gate.log" 2>&1
  rc=$?
  secs=$SECONDS
  sum=$(grep '^SUMMARY ' "$out/gate.log" | tail -1 | cut -c9-)
  case $rc in
    0)   st=PASS ;;
    3)   st=UNAVAILABLE ;;
    124|137) st=FAIL; sum="timeout after ${GATE_TIMEOUT[$g]}s${sum:+; $sum}" ;;
    *)   st=FAIL ;;
  esac
  echo "gate $g $st ${secs}s ${sum}"
  if [[ $st != UNAVAILABLE && $write == 1 ]]; then
    {
      echo "gate=$g"; echo "key=$gkey"; echo "tree=$key"; echo "commit=$(git rev-parse HEAD)"
      echo "clean=$([[ -z $(git status --porcelain) ]] && echo yes || echo no)"
      echo "status=$st"; echo "exit=$rc"; echo "seconds=$secs"; echo "started=$started"; echo "finished=$(date -Is)"
      echo "worktree=$top"; echo "log=$out/gate.log"; echo "summary=$sum"
      gate_provenance "$g"
    } > "$res.tmp" && mv "$res.tmp" "$res"
  fi
  rm -f "$lock"
  case $st in FAIL) worst=1 ;; UNAVAILABLE) [[ $worst == 0 ]] && worst=3 ;; esac
done
exit $worst
