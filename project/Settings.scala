package com.clarifi.reporting.project

import sbt._
import Keys._

import ReportingBuild.{allUnmanagedResourceDirectories, computeRevision, compileTestRuntime,
  goodJavascripts, jsLint, jsSources, enableTypeCheck}

object Settings {
  // Settings that don't work as build settings, just as project
  // settings.  Probably.
  lazy val universalProjectSettings: SettingsDefinition = Seq[SettingsDefinition](

    compileTestRuntime(sc => classpathConfiguration in sc := sc)

   ,update <<= (computeRevision, update.task) flatMap { case (_,p) => p }

   ,mainClass in (Compile, run) := Some("com.clarifi.reporting.ermine.session.Console")

   ,goodJavascripts <<= (unmanagedResources in Compile) map jsSources

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
