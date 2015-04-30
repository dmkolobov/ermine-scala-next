libraryDependencies ++= Seq (
  "jline"         % "jline" % "1.0",
  "org.scalaz"   %% "scalaz-core" % "7.0.7",
  "org.scalaz"   %% "scalaz-concurrent" % "7.0.7",
  "org.scalaz"   %% "scalaz-effect" % "7.0.7",
  "org.scalaz"   %% "scalaz-iterv" % "7.0.7",
  "org.scalaz"   %% "scalaz-scalacheck-binding" % "7.0.7" % "test",
  "commons-codec" % "commons-codec" % "1.4",
   // database connectors
  "mysql"         % "mysql-connector-java" % "5.1.6",
  "net.sourceforge.jtds" % "jtds" % "1.2.8",
  "org.xerial"    % "sqlite-jdbc" % "3.7.2",
  //"com.microsoft" % "jdbc4" % "4.0",
  "com.clarifi"  %% "f0" % "1.1.2",
  "scala-parsers" %% "scala-parsers" % "0.2.1",
  "machines"      %% "machines"    % "1.1",
  "org.scalacheck" %% "scalacheck" % "1.11.3" % "test"
)

libraryDependencies +=
  "log4j" % "log4j" % "1.2.15" excludeAll(
    ExclusionRule(organization = "com.sun.jdmk"),
    ExclusionRule(organization = "com.sun.jmx"),
    ExclusionRule(organization = "javax.jms"),
    ExclusionRule(organization = "javax.mail"),
    ExclusionRule(organization = "javax.activation")
  )
