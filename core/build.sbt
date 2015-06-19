scalacOptions ~= (so => (so filterNot Set("-unchecked", "-Xlint"))
                    ++ Seq("-Ywarn-nullary-override", "-Ywarn-inaccessible"))

name <<= artifactNameNormalizer(_("scala-core"))

// Include (main) sources from scalacheck-binding in our (test).
unmanagedSourceDirectories in Test <++=
  (unmanagedSourceDirectories in Compile in scalacheckBinding)(identity)

//logLevel := Level.Debug

suppressScalazItervWarnings
