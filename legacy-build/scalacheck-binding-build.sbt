scalacOptions <<= scalacOptions in core

name <<= artifactNameNormalizer(_("scala-core-scalacheck-binding"))

//logLevel := Level.Debug

suppressScalazItervWarnings
