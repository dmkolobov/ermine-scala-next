name <<= artifactNameNormalizer(_("scala-examples"))

autoScalaLibrary := false

sourcesInBase := false

crossVersion := CrossVersion.Disabled

resourceDirectory in Compile <<= baseDirectory(identity)

excludeFilter in (Compile, unmanagedResources) ~=
  (_ || "*.sbt" || "*.md" || "src" || "target" || "ivy.xml" || "build.xml")

classDirectory in Compile ~= (_ / "com" / "clarifi" / "reporting" / "examples")

// Remove precisely as many path components as we added in
// `classDirectory in Compile`, for the jar output.
products in Compile <<= (classDirectory in Compile, products in Compile) map {
  (cd, filt) =>
  (filt filter (cd !=)) :+ (cd / ".." / ".." / ".." / "..")
}
