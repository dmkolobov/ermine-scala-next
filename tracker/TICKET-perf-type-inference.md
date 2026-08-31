# Ticket: module load time is ~80% type inference — profile and reduce

Status: open · Filed: 2026-08-30 · Prior session: scoping fix + first JFR profile

WORK ON THIS TICKET IS DRIVEN BY tracker/PERF-ROADMAP.md (seeded
2026-08-31), which is the loop-state file: the checklist, the decisions,
the correctness gates and the iteration log all live there.  Two
corrections this ticket does not contain:
  - Its "Baselines to hold" are STALE (753 props; it is 902 now).
  - It describes ONE target.  There are two: batch load (this profile)
    and the LSP editor round trip, where after LSP-ROADMAP 5.5's per-SCC
    inference reuse, inference is 35% of compute and parse+rename+lower
    is 63% -- so "inference dominates" is false on that path.

## Problem

Loading the 129 stdlib modules with full type inference (`-Dermine.useInterface=false`)
takes ~12s on a quiet machine (~6s with the `.ei` interface cache, which skips
inference for unchanged modules). A JFR profile attributes the time:

| phase                                   | share of CPU samples |
|-----------------------------------------|----------------------|
| type/kind inference machinery           | 79.0%                |
| parsing (layout, fixity, name resolution) | 18.7%              |
| session driver / IO                     | 2.2%                 |
| term evaluation                         | ~0.1%                |

Inside inference the leaves are dominated by **free-variable collection** —
`Type.vars` / `Vars.apply` and kind equivalents, ~40% of ALL samples, spent
rebuilding immutable hash sets (Champ-trie `BitmapIndexedSetNode` etc.) while
walking type trees — and **substitution application** (`HasTypeVars.sub`,
`VarT.subst`, `Type.sub`, ~10–15%). Call paths: `Subst.inferBindingGroupTypes`
(on 71% of stacks) → `inferAltTypes` → `typeCheckExplicitBinding` → `inferType`
→ `subsumeType`; `unifyType` and `instantiateType` ~23% each. Classic
naive-substitution HM shape: ftvs recomputed and substitutions re-applied over
whole trees at every subsumption/instantiation.

Also observed: 963 of 967 samples sit on a single `ermine-session-task` thread —
module loading is effectively serial despite the task pool.

## Reproduce the profile (~30s)

    export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
    cd ermine-scala   # repo root
    ERMINE_JAVA_OPTS="-Dermine.useInterface=false \
      -XX:FlightRecorderOptions=stackdepth=512 \
      -XX:StartFlightRecording=filename=/tmp/ermine.jfr,settings=profile" \
      bash -c 'printf ":quit\n" | bin/ermine'
    jfr print --stack-depth 500 --events jdk.ExecutionSample /tmp/ermine.jfr > /tmp/samples.txt

Then bucket samples by first `com.clarifi.reporting.ermine[.parsing]` /
`scalaparsers` frame on each stack.

Pitfalls learned the hard way:
- `jfr print` silently truncates stacks to **5 frames** by default — always pass
  `--stack-depth`. The recording itself defaults to 64 frames; scalaz
  trampolines/recursion need `-XX:FlightRecorderOptions=stackdepth=512`.
- The loader is multi-threaded in structure: samples live on
  `ermine-session-task`, not `main` — don't filter to main.
- Delete or bypass `*.ei` files when measuring inference (`useInterface=false`);
  loads write `.ei` back, so a "cold" second run isn't cold.
- Wall time is only meaningful on a quiet machine; sample *proportions* are
  robust to background load.

## Candidate directions (unverified — measure first)

1. **Memoize/cache free-variable sets** on `Type`/`Kind` nodes (or an ftv-bearing
   wrapper): `Type.vars` alone is ~a quarter of load time. Types are immutable,
   so per-node caching is sound; watch allocation cost.
2. **Cut redundant `vars`/`sub` calls** in `Subst.subsumeType` /
   `instantiateType` / `inferBindingGroupTypes` (core/src/main/scala/com/clarifi/
   reporting/ermine/Subst.scala) — inspect whether ftvs of the same type are
   recomputed per generalization/skolemization within one binding group.
3. **Substitution representation**: trees are rebuilt per `sub` application;
   consider composing substitutions or mutable metavariables/levels (big change;
   measure 1–2 first).
4. **Parallel module loading**: dependency levels of the 129-module graph would
   allow width; today one `ermine-session-task` thread does everything. Session
   machinery is not thread-safe per its own comments — scope carefully.
5. Cheap win check: `Vars.apply`/`Vars.++` allocation — samples show set-builder
   churn; a size-hinted or unsorted representation may help without semantic risk.

## Baselines to hold

- `sbt core/test`: 753 props, 752 pass (Constraints.disjunction sound is the
  known pre-existing failure, tracker/06-tests.md).
- `tracker/tools/repl-smoke.sh`: relations, scoping, smoke all pass — smoke runs
  with `useInterface=false`, so it also guards inference behaviour.
- Load-time sanity: ~12s uncached / ~6s cached on a quiet machine (2026-08-30,
  JDK 21, this hardware); re-baseline before comparing.
