// You'll also need externalIvySettings & publishTo, in zbuild.sbt.

clarifiMode in ThisBuild := ("true" == System.getProperty("clarifi.mode"))

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
