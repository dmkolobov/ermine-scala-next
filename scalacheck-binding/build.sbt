scalacOptions <<= scalacOptions in core

name := "ermine-scala-core-scalacheck-binding"

// There are no sources specific to this project; instead, we rebuild
// selected sources from the core tests.
unmanagedSources in Compile <+=
  scalaSource in core in Test map (_ / "com" / "clarifi" / "reporting" / "TestErmine.scala")

//logLevel := Level.Debug
