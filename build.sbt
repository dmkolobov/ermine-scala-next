scalaVersion in ThisBuild := "2.11.5"

scalacOptions in ThisBuild ++=
  Seq("-encoding", "UTF-8", "-Yrecursion", "50", "-deprecation",
      "-unchecked", "-Xlint", "-Ywarn-unused-import",
      /* TODO enable "-Ywarn-adapted-args", */ "-Ydelambdafy:method", "-feature",
      "-language:implicitConversions", "-language:higherKinds",
      "-language:existentials", "-language:postfixOps")

javacOptions in ThisBuild in (Compile, compile) ++=
  Seq("-Werror", "-Xlint", "-Xlint:-path", "-Xlint:-serial")

incOptions in ThisBuild := (incOptions in ThisBuild).value.withNameHashing(true)

parallelExecution in ThisBuild := true

name <<= artifactNameNormalizer(_("scala"))

organization in ThisBuild := "com.clarifi.ermine"

version in ThisBuild := "2.14.0"

initialCommands in ThisBuild := ""

resolvers in ThisBuild ++= Seq(
  "Bintray JCenter Repo"    at "https://dl.bintray.com/bintray/jcenter",
  "Erik Osheim's Bintray Repo" at "http://dl.bintray.com/non/maven"
)

artifactNameNormalizer in ThisBuild := ("ermine-" + _)

enableTypeCheck in ThisBuild := {
  System.getProperty("ermine.typeCheck") match {
    case null => println("Enabling type checking")
                 System.setProperty("ermine.typeCheck", "true")
    case _    => ()
  }
}

computeRevision in ThisBuild <<= streams map { s =>
  import java.util.{Date, TimeZone}
  val formatter = new java.text.SimpleDateFormat("yyyyMMdd.HHmmss")
  formatter.setTimeZone(TimeZone.getTimeZone("GMT"))
  val timestamp = formatter.format(new Date)
  val hash = ("hg id" !!) takeWhile (c => c.isLetter || c.isDigit)
  val revision = timestamp + "." + hash
  val branch = ("hg id -b" !!).trim
  val tags = ("hg id -t" !!).trim
  s.log.info("computing revision")
  s.log.info("hash: " + hash)
  s.log.info("branch: " + branch)
  s.log.info("tags: " + tags)
  s.log.info("timestamp: " + timestamp)
  System.getProperties.setProperty("mercurial.id", hash)
  System.getProperties.setProperty("mercurial.branch", branch)
  System.getProperties.setProperty("mercurial.tags", tags)
  // System.setProperty("scala.timings", "true")
  val pubRev = (Seq("publish-revision", "revision")
                  collectFirst (Function unlift (s => Option(System getProperty s))))
  pubRev foreach (System.setProperty("rev", _))
  System.setProperty("publish.revision", pubRev getOrElse revision)
  System.setProperty("publish.branch", branch)
}

packageOptions in ThisBuild <+= computeRevision map { _ =>
  val m = new java.util.jar.Manifest
  val attrs = new java.util.jar.Attributes
  attrs.putValue("Mercurial-Hash", System.getProperties.getProperty("mercurial.id"))
  attrs.putValue("Mercurial-Branch", System.getProperties.getProperty("mercurial.branch"))
  attrs.putValue("Mercurial-Tags", System.getProperties.getProperty("mercurial.tags"))
  m.getEntries.put("reporting", attrs)
  Package.JarManifest(m)
}

ensureNoUncommitted in ThisBuild <<= streams map { s => 
  if (("hg st -mard" !!) isEmpty) () 
  else {
    s.log.error("must have clean working directory to publish - commit or shelve your changes") 
    s.log.error("to ensure 'hg st' returns no results or do 'publish-local' for local testing")
    error("unable to publish due to uncommitted changes")
  }
}

excludeFilter in ThisBuild := HiddenFileFilter || FileFilter.globFilter("*.ei")

publishLocal in ThisBuild <<= (computeRevision, publishLocal.task) flatMap { case (_,p) => p }

publish in ThisBuild <<= (computeRevision, ensureNoUncommitted, publish.task) flatMap { case (_,_,p) => p }

publishMavenStyle in ThisBuild := true

publishArtifact := false

//logLevel := Level.Debug
