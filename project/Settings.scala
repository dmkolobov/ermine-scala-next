package com.clarifi.reporting.project

import sbt._
import Keys._

import ReportingBuild.{
  allUnmanagedResourceDirectories, computeRevision, compileTestRuntime,
  goodJavascripts, jlineOneScalaInstance, jsLint,
  jsSources, repl, smrepl, enableTypeCheck
}

object Settings {
  // Settings that don't work as build settings, just as project
  // settings.  Probably.
  lazy val universalProjectSettings: SettingsDefinition = Seq[SettingsDefinition](

    compileTestRuntime(sc => classpathConfiguration in sc := sc)

   ,addCompilerPlugin("org.spire-math" % "kind-projector_2.11" % "0.6.3")

   ,update <<= (computeRevision, update.task) flatMap { case (_,p) => p }

   ,mainClass in (Compile, run) := Some("com.clarifi.reporting.ermine.session.Console")

   ,scalaInstance in (Compile, run) <<=
      (streams, dependencyClasspath in Compile,
       scalaInstance in (Compile, run)) map jlineOneScalaInstance

   ,scalaInstance in smrepl <<=
      (streams, dependencyClasspath in Compile,
       scalaInstance in smrepl) map jlineOneScalaInstance

   ,scalaInstance in repl <<=
      (streams, dependencyClasspath in Compile,
       scalaInstance in (Compile, run)) map jlineOneScalaInstance

   ,goodJavascripts <<= (unmanagedResources in Compile) map jsSources

    // enable overwriting published versions
   ,publishConfiguration ~= {pc =>
        Classpaths.publishConfig(
          artifacts = pc.artifacts, ivyFile = pc.ivyFile,
          checksums = pc.checksums, resolverName = pc.resolverName,
          logging = pc.logging, overwrite = true)
      }

   ,compile in Compile <<= (enableTypeCheck, (compile in Compile).task) flatMap { case (_, p) => p }

   ,compileTestRuntime(sco => allUnmanagedResourceDirectories in sco <<=
      (Defaults.inDependencies(unmanagedResourceDirectories in sco, _ => Seq.empty)
       (_.reverse.flatten)))

    // Usually, resources end up in the classpath by virtue of `compile'
    // copying them into target/scala-*/classes, and from there into jar.  But
    // we want in development (1) I can edit an Ermine module in src
    // resources, hit reload, and it's seen, and (2) I can edit CSS/JS, reload
    // the HTML, and it's seen.  So we (harmlessly) patch the src resources
    // dirs in *before* the classes dirs, so they will win in the classloader
    // lookup.
   ,compileTestRuntime(sco =>
      fullClasspath in sco <<= (allUnmanagedResourceDirectories in sco,
                                fullClasspath in sco) map {
        (urd, fc) => Attributed.blankSeq(urd) ++ fc
    })

    // Lint JS files.
   ,compile in Compile <<= (streams, goodJavascripts, compile in Compile) map {
      (s, rsrcs, cres) =>
      for {
        jsf <- rsrcs // TODO filter unchanged jses
        issue <- jsLint(jsf)
      } s.log.warn(issue.toString)
      cres
    }
  ) flatMap (_.settings)
}
