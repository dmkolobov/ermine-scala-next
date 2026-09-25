ThisBuild / scalaVersion  := "3.3.8"
ThisBuild / organization  := "com.clarifi.ermine"
ThisBuild / version       := "3.0.0-SNAPSHOT"

// Ermine writes `.ei` interface files next to the modules it type-checks, as a
// cache. They must never be packaged (the sbt 0.13 build excluded them the same
// way) or a stale interface ships with the jar.
ThisBuild / excludeFilter := HiddenFileFilter || "*.ei"

ThisBuild / scalacOptions ++= Seq(
  "-encoding", "UTF-8",
  "-deprecation",
  "-feature",
  "-language:implicitConversions",
  "-language:higherKinds",
  "-language:existentials",
  "-language:postfixOps",
  "-source:3.3"
)

val scalazVersion = "7.2.36"
val log4jVersion  = "2.25.3"

lazy val unportedSources = settingKey[Seq[String]](
  "source paths held out of the Scala 3 build, relative to the scala source dir")

/** Restrict a source tree to the files that are in scope for the port. */
def portedSources(base: File, excluded: Seq[String]): Seq[File] =
  (base ** "*.scala").get.filterNot { f =>
    val rel = f.relativeTo(base).map(_.getPath).getOrElse(f.getName)
    excluded.exists(p => rel == p || rel.startsWith(p + "/"))
  }

// The parser combinator library the language is built on: ermine-language/
// ermine-parser, vendored because no Scala 3 artifact is published and the
// 2.11 one is no longer resolvable.
lazy val parsers = (project in file("parsers"))
  .settings(
    name := "ermine-parsers",
    libraryDependencies += "org.scalaz" %% "scalaz-core" % scalazVersion
  )

// scalaz APIs this code uses that were removed after 7.0, vendored from the
// 7.0.7 sources: the Scalaz 6 compatibility iteratees (`IterV` & friends,
// dropped in 7.1) and `concurrent.Promise` (also dropped in 7.1).
// See scalaz-compat/README.md.
lazy val scalazCompat = (project in file("scalaz-compat"))
  .settings(
    name := "ermine-scalaz-compat",
    libraryDependencies ++= Seq(
      "org.scalaz" %% "scalaz-core"       % scalazVersion,
      "org.scalaz" %% "scalaz-concurrent" % scalazVersion
    )
  )

// ermine-language/f0, vendored: the published com.clarifi %% f0 is gone from
// Maven Central. Used by the `backends` and `remote` layers.
lazy val f0 = (project in file("f0"))
  .settings(
    name := "ermine-f0",
    libraryDependencies += "org.scalaz" %% "scalaz-core" % scalazVersion
  )

// ermine-language/scala-machines, vendored for the same reason.
lazy val machines = (project in file("machines"))
  .settings(
    name := "ermine-machines",
    unportedSources := Seq("com/clarifi/machines/Test.scala"),
    Compile / unmanagedSources := portedSources(
      (Compile / scalaSource).value, unportedSources.value),
    libraryDependencies ++= Seq(
      "org.scalaz" %% "scalaz-core"   % scalazVersion,
      "org.scalaz" %% "scalaz-effect" % scalazVersion
    )
  )

lazy val core = (project in file("core"))
  .dependsOn(parsers, machines, scalazCompat, f0)
  .settings(
    name := "ermine-core",
    unportedSources := Seq(
      // Needs scalaz.concurrent, which has no Scala 3 build; only the
      // JavaFX editor used it.
      "com/clarifi/reporting/writers/jfx"
    ),
    Compile / unmanagedSources := portedSources(
      (Compile / scalaSource).value, unportedSources.value),
    // The scalacheck-binding module's sources are part of core's tests, as they
    // were in the sbt 0.13 build.
    Test / unmanagedSourceDirectories += (ThisBuild / baseDirectory).value / "scalacheck-binding" / "src" / "main" / "scala",
    // Not forked: the module-loading properties resolve `core/examples`
    // relative to the build root, and ErmineFixture already turns type
    // checking on for its own sessions.
    Test / fork := false,
    libraryDependencies ++= Seq(
      "org.scalaz"    %% "scalaz-core"       % scalazVersion,
      "org.scalaz"    %% "scalaz-effect"     % scalazVersion,
      "org.scalaz"    %% "scalaz-concurrent" % scalazVersion,
      "org.scalaz"    %% "scalaz-iteratee"   % scalazVersion,
      "org.jline"      % "jline"             % "3.30.9",
      // JSON AST for the encoder (core/json): 6.2.6 is the last argonaut
      // published for both Scala 2.11 and Scala 3, so the 2.11 back-port
      // pins the same version. tracker/JSON-API-DESIGN.md.
      "io.argonaut"   %% "argonaut"          % "6.2.6",
      "commons-codec"  % "commons-codec"     % "1.19.0",
      // The old build used log4j 1.2.15; the 1.2 API now comes from the
      // Log4j 2 compatibility bridge instead of the dead 1.x line.
      "org.apache.logging.log4j" % "log4j-1.2-api" % log4jVersion,
      "org.apache.logging.log4j" % "log4j-core"    % log4jVersion,
      // JDBC drivers, refreshed from the 2014-era pins.
      "com.mysql"            % "mysql-connector-j" % "9.5.0",
      "net.sourceforge.jtds" % "jtds"              % "1.3.1",
      "org.xerial"           % "sqlite-jdbc"       % "3.51.1.0",
      // SQL Server (WP-12(a), tracker/db/SERVER.md): "jre11" is part of the
      // version string, not a classifier; its compile deps are all optional.
      "com.microsoft.sqlserver" % "mssql-jdbc"   % "13.6.0.jre11",
      "org.scalacheck" %% "scalacheck" % "1.15.4" % Test,
      "org.scalaz"     %% "scalaz-scalacheck-binding" % "7.2.36-scalacheck-1.15" % Test
    ),
    Compile / run / mainClass := Some("com.clarifi.reporting.ermine.session.Console"),
    Compile / run / fork := true,
    Compile / run / connectInput := true,
    // The session type-checks module bindings only when this is set; the sbt
    // 0.13 build set it from an `enable-type-checking` task wired into
    // `compile`. Without it every module binding is loaded as `forall a. a`.
    Compile / run / javaOptions += "-Dermine.typeCheck=true",
    // Give the forked REPL the terminal directly, so jline sees a real tty.
    outputStrategy := Some(StdoutOutput),
    Compile / run / outputStrategy := Some(StdoutOutput)
  )

lazy val root = (project in file("."))
  .aggregate(parsers, machines, scalazCompat, f0, core)
  .settings(
    name := "ermine",
    publish / skip := true
  )
