#!/usr/bin/env bash
# Compile and run the partition-level reproducer against the built compiler classes.
#   tracker/repro/nameloss/run.sh [id-bases...]           # sweeps; extra args = minimal-instance bases to replay
#   ERMINE_JAVA_OPTS="-Dermine.rowTrace=/tmp/tr.tsv" tracker/repro/nameloss/run.sh 1 0   # step traces at bases 1 (fails) and 0 (pins)
# Needs `sbt -batch core/compile` done first (target/ermine-classpath is written by the build).
set -euo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$here"
CS=~/.cache/coursier/v1/https/repo1.maven.org/maven2
COMP="$CS/org/scala-lang/scala3-compiler_3/3.3.8/scala3-compiler_3-3.3.8.jar:$CS/org/scala-lang/scala3-interfaces/3.3.8/scala3-interfaces-3.3.8.jar:$CS/org/scala-lang/tasty-core_3/3.3.8/tasty-core_3-3.3.8.jar:$CS/org/scala-lang/modules/scala-asm/9.9.0-scala-1/scala-asm-9.9.0-scala-1.jar:$CS/org/scala-sbt/compiler-interface/1.10.7/compiler-interface-1.10.7.jar"
CP="$(cat target/ermine-classpath)"
out="${NAMELOSS_OUT:-/tmp/nameloss-classes}"
mkdir -p "$out"
java -cp "$COMP:$CP" dotty.tools.dotc.Main -d "$out" -classpath "$CP" \
  tracker/repro/nameloss/Replay.scala tracker/repro/nameloss/NameLossRepro.scala
opts=()
[[ -n ${ERMINE_JAVA_OPTS:-} ]] && read -r -a opts <<< "$ERMINE_JAVA_OPTS"
exec java "${opts[@]}" -cp "$out:$CP" NameLossRepro "$@"
