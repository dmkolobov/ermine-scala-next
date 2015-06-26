name <<= artifactNameNormalizer(_("editor"))

scalacOptions ~= (so => (so filterNot Set("-Xlint"))
                    ++ Seq("-Ywarn-nullary-override", "-Ywarn-inaccessible"))

//logLevel := Level.Debug
