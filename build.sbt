ThisBuild / scalaVersion  := "3.3.8"
ThisBuild / organization  := "com.clarifi.ermine"
ThisBuild / version       := "3.0.0-SNAPSHOT"

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
  .dependsOn(parsers, machines)
  .settings(
    name := "ermine-core",
    unportedSources := Seq(
      // Needs scalaz.concurrent, which has no Scala 3 build; only the
      // JavaFX editor used it.
      "com/clarifi/reporting/writers/jfx"
    ),
    Compile / unmanagedSources := portedSources(
      (Compile / scalaSource).value, unportedSources.value),
    Test / unmanagedSources := Seq.empty,
    libraryDependencies ++= Seq(
      "org.scalaz"    %% "scalaz-core"       % scalazVersion,
      "org.scalaz"    %% "scalaz-effect"     % scalazVersion,
      "org.scalaz"    %% "scalaz-iteratee"   % scalazVersion,
      "org.jline"      % "jline"             % "3.30.9",
      "commons-codec"  % "commons-codec"     % "1.19.0",
      // The old build used log4j 1.2.15; the 1.2 API now comes from the
      // Log4j 2 compatibility bridge instead of the dead 1.x line.
      "org.apache.logging.log4j" % "log4j-1.2-api" % log4jVersion,
      "org.apache.logging.log4j" % "log4j-core"    % log4jVersion,
      // JDBC drivers, refreshed from the 2014-era pins.
      "com.mysql"            % "mysql-connector-j" % "9.5.0",
      "net.sourceforge.jtds" % "jtds"              % "1.3.1",
      "org.xerial"           % "sqlite-jdbc"       % "3.51.1.0"
    ),
    Compile / run / mainClass := Some("com.clarifi.reporting.ermine.session.Console"),
    Compile / run / fork := true,
    Compile / run / connectInput := true,
    outputStrategy := Some(StdoutOutput)
  )

lazy val root = (project in file("."))
  .aggregate(parsers, machines, core)
  .settings(
    name := "ermine",
    publish / skip := true
  )
