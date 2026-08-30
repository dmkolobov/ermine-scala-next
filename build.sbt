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

val scalazVersion = "7.3.9"

// Packages under core/src/main/scala not yet ported to Scala 3.
// Shrink this list as the migration proceeds; it is the migration's scoreboard.
lazy val unportedCorePackages = settingKey[Seq[String]](
  "relative source paths excluded from the Scala 3 core build")

/** Restrict a source tree to the files that are in scope for the port. */
def portedSources(base: File, excluded: Seq[String]): Seq[File] =
  (base ** "*.scala").get.filterNot { f =>
    val rel = f.relativeTo(base).map(_.getPath).getOrElse(f.getName)
    excluded.exists(p => rel == p || rel.startsWith(p + "/"))
  }

lazy val parsers = (project in file("parsers"))
  .settings(
    name := "ermine-parsers",
    libraryDependencies ++= Seq(
      "org.scalaz" %% "scalaz-core" % scalazVersion
    )
  )

lazy val core = (project in file("core"))
  .dependsOn(parsers)
  .settings(
    name := "ermine-core",
    unportedCorePackages := Seq(
      "com/clarifi/reporting/writers",
      "com/clarifi/reporting/remote",
      "com/clarifi/reporting/flatteners",
      "com/clarifi/reporting/backends",
      "com/clarifi/reporting/sql",
      "com/clarifi/reporting/relational",
      "com/clarifi/reporting/record"
    ),
    Compile / unmanagedSources := portedSources(
      (Compile / scalaSource).value, unportedCorePackages.value),
    Test / unmanagedSources := Seq.empty,
    libraryDependencies ++= Seq(
      "org.scalaz"    %% "scalaz-core"       % scalazVersion,
      "org.scalaz"    %% "scalaz-concurrent" % scalazVersion,
      "org.scalaz"    %% "scalaz-effect"     % scalazVersion,
      "org.jline"      % "jline"             % "3.30.9",
      "commons-codec"  % "commons-codec"     % "1.19.0"
    ),
    Compile / run / mainClass := Some("com.clarifi.reporting.ermine.session.Console"),
    Compile / run / fork := true,
    Compile / run / connectInput := true,
    outputStrategy := Some(StdoutOutput)
  )

lazy val root = (project in file("."))
  .aggregate(parsers, core)
  .settings(
    name := "ermine",
    publish / skip := true
  )
