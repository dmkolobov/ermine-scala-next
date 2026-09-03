#!/usr/bin/env bash
# Compile and run the C-rule (Lean witness W) replay against the built compiler classes.
#   tracker/repro/crule/run.sh sweep W 0 99            # in-process sweep, 10 s cap, stops after 6 hung threads (exit 3)
#   tracker/repro/crule/run.sh sweep gseed 0 4         # controls: gseed | G4 | Wsat
#   ERMINE_JAVA_OPTS="-Dermine.rowTrace=/tmp/tr.tsv" timeout 8 tracker/repro/crule/run.sh sweep W 7 7 1000
# Needs `sbt -batch core/compile` done first (target/ermine-classpath is written by the build).
# JVM heap defaults to -Xmx2g (override with CRULE_XMX).
set -euo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$here"
CS=~/.cache/coursier/v1/https/repo1.maven.org/maven2
COMP="$CS/org/scala-lang/scala3-compiler_3/3.3.8/scala3-compiler_3-3.3.8.jar:$CS/org/scala-lang/scala3-interfaces/3.3.8/scala3-interfaces-3.3.8.jar:$CS/org/scala-lang/tasty-core_3/3.3.8/tasty-core_3-3.3.8.jar:$CS/org/scala-lang/modules/scala-asm/9.9.0-scala-1/scala-asm-9.9.0-scala-1.jar:$CS/org/scala-sbt/compiler-interface/1.10.7/compiler-interface-1.10.7.jar"
CP="$(cat target/ermine-classpath)"
out="${CRULE_OUT:-/tmp/crule-classes}"
mkdir -p "$out"
# recompile only when a source is newer than the last build
if [[ ! -f "$out/CRuleRepro.class" || tracker/repro/crule/CRuleRepro.scala -nt "$out/CRuleRepro.class" || tracker/repro/nameloss/Replay.scala -nt "$out/CRuleRepro.class" ]]; then
  java -cp "$COMP:$CP" dotty.tools.dotc.Main -d "$out" -classpath "$CP" \
    tracker/repro/nameloss/Replay.scala tracker/repro/crule/CRuleRepro.scala
fi
opts=( "-Xmx${CRULE_XMX:-2g}" )
[[ -n ${ERMINE_JAVA_OPTS:-} ]] && read -r -a extra <<< "$ERMINE_JAVA_OPTS" && opts+=( "${extra[@]}" )
exec java "${opts[@]}" -cp "$out:$CP" CRuleRepro "$@"
