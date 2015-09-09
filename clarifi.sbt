// You'll also need externalIvySettings & publishTo, in zbuild.sbt.

clarifiMode in ThisBuild := ("true" == System.getProperty("clarifi.mode"))

withClarifiMode(version in ThisBuild){o =>
  // adapted from sbt project/Util.scala generateVersionFile
  import java.util.{Date, TimeZone}
  val formatter = new java.text.SimpleDateFormat("yyyyMMdd.HHmmss")
  formatter.setTimeZone(TimeZone.getTimeZone("GMT"))
  val timestamp = formatter.format(new Date)
  val hash = ("hg id" !!) takeWhile (c => c.isLetter || c.isDigit)
  val tags = ("hg id -t" !!).trim.split(' ').filterNot(s => s == "tip" || s.isEmpty)
  if(tags.isEmpty) timestamp + "." + hash
  else tags.last
}

withClarifiMode(artifactNameNormalizer in ThisBuild){o =>
  // Don't use dots (.) in the artifact name; these get transformed by
  // later sbt, presumably because they shouldn't have been allowed.
  // By convention, we replace all . with -, which is what sbt 0.13.5
  // does.
  s => o(s) + "_1-0-0"
}

withClarifiMode(publishMavenStyle in ThisBuild){o =>
  false
}

withClarifiMode(publishArtifact in ThisBuild in (Compile, packageDoc)){o =>
  false
}

withClarifiMode(publishArtifact in ThisBuild in (Compile, packageSrc)){o =>
  false
}

// Drop version numbers from our generated artifacts (jars)
withClarifiMode(artifactName in ThisBuild)(o =>
  (config, module: ModuleID, artifact: Artifact) =>
    artifact.name + "." + artifact.extension
)
