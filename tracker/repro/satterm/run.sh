#!/usr/bin/env bash
# Compile and run the satisfiable-seed (W2 / H2 / NE6) replay against the built compiler classes.
#   tracker/repro/satterm/run.sh sweep W2 0 99                # in-process sweep, 10 s cap, exit 3 after 6 hung threads
#   tracker/repro/satterm/run.sh sweep H2 0 99 10 6
#   tracker/repro/satterm/run.sh sweep NE6 0 99
#   ERMINE_JAVA_OPTS="-Dermine.rowTrace=<fresh file>" tracker/repro/satterm/run.sh trace W2 0 10 40
#   ERMINE_JAVA_OPTS="-Dermine.genRules=nongen" tracker/repro/satterm/run.sh sweep W2 0 9
# Needs `sbt -batch core/compile` done first (target/ermine-classpath is written by the build).
# JVM heap defaults to -Xmx2g (override with SATTERM_XMX); classes go to SATTERM_OUT (default /tmp/satterm-classes).
set -euo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$here"
CS=~/.cache/coursier/v1/https/repo1.maven.org/maven2
COMP="$CS/org/scala-lang/scala3-compiler_3/3.3.8/scala3-compiler_3-3.3.8.jar:$CS/org/scala-lang/scala3-interfaces/3.3.8/scala3-interfaces-3.3.8.jar:$CS/org/scala-lang/tasty-core_3/3.3.8/tasty-core_3-3.3.8.jar:$CS/org/scala-lang/modules/scala-asm/9.9.0-scala-1/scala-asm-9.9.0-scala-1.jar:$CS/org/scala-sbt/compiler-interface/1.10.7/compiler-interface-1.10.7.jar"
CP="$(cat target/ermine-classpath)"
out="${SATTERM_OUT:-/tmp/satterm-classes}"
mkdir -p "$out"
# recompile only when a source is newer than the last build
if [[ ! -f "$out/SatTermRepro.class" || tracker/repro/satterm/SatTermRepro.scala -nt "$out/SatTermRepro.class" || tracker/repro/nameloss/Replay.scala -nt "$out/SatTermRepro.class" ]]; then
  java -cp "$COMP:$CP" dotty.tools.dotc.Main -d "$out" -classpath "$CP" \
    tracker/repro/nameloss/Replay.scala tracker/repro/satterm/SatTermRepro.scala
fi
opts=( "-Xmx${SATTERM_XMX:-2g}" )
[[ -n ${ERMINE_JAVA_OPTS:-} ]] && read -r -a extra <<< "$ERMINE_JAVA_OPTS" && opts+=( "${extra[@]}" )
exec java "${opts[@]}" -cp "$out:$CP" SatTermRepro "$@"
