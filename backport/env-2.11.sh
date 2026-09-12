# Environment for the legacy Scala 2.11.5 / sbt 0.13.5 Ermine build (branch backport-2.11).
#
#   source backport/env-2.11.sh
#   sbt211 core/compile
#   sbt211 core/test
#
# Sourcing is idempotent and does not change the current directory.

_ERM_BP="$(cd "$(dirname "${BASH_SOURCE[0]:-backport/env-2.11.sh}")" && pwd)"
_ERM_ROOT="$(dirname "$_ERM_BP")"

# --- JDK 8 --------------------------------------------------------------------
# Scala 2.11.5 and sbt 0.13.5 do not run on newer JDKs; the toolchain's default
# JDK 21 is wrong for this branch.  Temurin 8 via coursier:
#   ~/.local/ermine-toolchain/cs java-home --jvm adoptium:8
if [ -z "${ERMINE_JDK8:-}" ]; then
  ERMINE_JDK8="$("$HOME/.local/ermine-toolchain/cs" java-home --jvm adoptium:8 2>/dev/null | tail -1)"
fi
export JAVA_HOME="$ERMINE_JDK8"

# --- PATH ---------------------------------------------------------------------
# $_ERM_BP first: it holds the `hg` shim (see backport/hg -- computeRevision runs
# `hg id` on every `update`, and the checkout is git).
export PATH="$JAVA_HOME/bin:$_ERM_BP:$HOME/.local/ermine-toolchain/bin:$PATH"

# --- the launcher -------------------------------------------------------------
# The genuine sbt 0.13.5 launcher jar, from
#   https://repo.scala-sbt.org/scalasbt/ivy-releases/org.scala-sbt/sbt-launch/0.13.5/sbt-launch.jar
# The sbt 2.x runner in ~/.local/ermine-toolchain/bin does boot 0.13.5, but its
# launcher never publishes the `compiler-interface-src` component, so any compile
# dies with "sbt.InvalidComponent: Could not find required component
# 'compiler-interface-src'".  Same trap applies to ~/.sbt/boot/scala-2.10.4/
# org.scala-sbt/sbt/0.13.5: if a flat copy of it was left by the sbt 2.x launcher,
# rm -rf it and let the 0.13.5 launcher repopulate it.
export ERMINE_SBT_LAUNCH="${ERMINE_SBT_LAUNCH:-$HOME/.local/ermine-toolchain/bin/sbt-launch-0.13.5.jar}"

# --- JVM/sbt flags ------------------------------------------------------------
# sbt.repository.config replaces 0.13.5's built-in resolver list (its
# http://repo.typesafe.com entry hangs forever); sbt.override.build.repos=true
# also neutralises the dead bintray resolvers hard-coded in build.sbt.
export SBT_OPTS="-Xmx3g -Xss16m -XX:MaxPermSize=512m -Dfile.encoding=UTF-8 -Dsbt.repository.config=$_ERM_BP/repositories -Dsbt.override.build.repos=true"

# sbt211 <task>... -- the build on this branch.
# build.sbt's enableTypeCheck task sets -Dermine.typeCheck=true itself when the
# property is unset, so the Ermine type checker is ON by default.
sbt211() { ( cd "$_ERM_ROOT" && "$JAVA_HOME/bin/java" $SBT_OPTS -jar "$ERMINE_SBT_LAUNCH" "$@" ); }

# ermine211 -- the REPL (mainClass com.clarifi.reporting.ermine.session.Console)
# straight off a cached classpath, without going through sbt.  Recompute the
# classpath after any source change:
#   sbt211 "export core/runtime:fullClasspath" | tail -1 > backport/.classpath
ermine211() {
  local cp="$_ERM_BP/.classpath"
  [ -f "$cp" ] || { echo "no $cp; run: sbt211 'export core/runtime:fullClasspath' | tail -1 > $cp" >&2; return 1; }
  "$JAVA_HOME/bin/java" -Xss16m -Dermine.typeCheck=true -Dermine.useInterface=false \
    -cp "$(tr -d '\n' < "$cp")" com.clarifi.reporting.ermine.session.Console "$@"
}

export -f sbt211 ermine211 2>/dev/null || true
unset _ERM_BP _ERM_ROOT
