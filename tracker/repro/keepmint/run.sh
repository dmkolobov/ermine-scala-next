#!/usr/bin/env bash
# Positive control for tracker/tools/keptdef-mints.py (PROMPT-default-termination.md, Q2):
# replay the KeepInert.lean counterexample  u <- (x, y, (|k|)); u <- (|k, c|); R <- (u, z)
# through the real `Subst.solve` at 8 id bases x 4 input orders, with the step trace on, and
# count the kept-definition dequeues on which `splitConcrete` mints.
#   tracker/repro/keepmint/run.sh            # expects 16 of 32 configurations to MINT
# Needs `sbt -batch core/compile` done first (target/ermine-classpath is written by the build).
set -euo pipefail
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$here"
CS=~/.cache/coursier/v1/https/repo1.maven.org/maven2
COMP="$CS/org/scala-lang/scala3-compiler_3/3.3.8/scala3-compiler_3-3.3.8.jar:$CS/org/scala-lang/scala3-interfaces/3.3.8/scala3-interfaces-3.3.8.jar:$CS/org/scala-lang/tasty-core_3/3.3.8/tasty-core_3-3.3.8.jar:$CS/org/scala-lang/modules/scala-asm/9.9.0-scala-1/scala-asm-9.9.0-scala-1.jar:$CS/org/scala-sbt/compiler-interface/1.10.7/compiler-interface-1.10.7.jar"
CP="$(cat target/ermine-classpath)"
out="${KEEPMINT_OUT:-/tmp/keepmint-classes}"
trace="${KEEPMINT_TRACE:-/tmp/keepmint-trace.tsv}"
mkdir -p "$out"; rm -f "$trace"
java -cp "$COMP:$CP" dotty.tools.dotc.Main -d "$out" -classpath "$CP" \
  tracker/repro/nameloss/Replay.scala tracker/repro/keepmint/KeepMintRepro.scala
java -Dermine.rowTrace="$trace" -cp "$out:$CP" KeepMintRepro
python3 tracker/tools/keptdef-mints.py "$trace" --show 1
