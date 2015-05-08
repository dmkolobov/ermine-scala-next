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
  "com.clarifi"  %% "f0" % "1.0.1-2.9.2",
  "clarifi"      %% "machines"    % "8819a4a87d998f2cddda808a8d19ac4fc2772c97",
  // TODO: used in writers package that should move out,
  // but would be an annoying refactoring -- JC 4/27/15
  "jfree" % "jfreechart" % "1.0.1" exclude("junit", "junit"),
  "org.scalacheck" %% "scalacheck" % "1.10.1" % "test"
)

libraryDependencies += log4jDependency
