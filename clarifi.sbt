// You'll also need externalIvySettings & publishTo, in zbuild.sbt.

clarifiMode in ThisBuild := ("true" == System.getProperty("clarifi.mode"))

withClarifiMode(version in ThisBuild){o =>
  val hash = ("hg id" !!) takeWhile (c => c.isLetter || c.isDigit)
  hash
}

withClarifiMode(artifactNameNormalizer in ThisBuild){o =>
  s => o(s) + "_1.0.0"
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
