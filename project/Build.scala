package com.clarifi.reporting.project

import sbt._
import Keys._

object ReportingBuild extends Build {
  val goodJavascripts     = TaskKey[Seq[File]]("good-javascripts", "Paths to Javascript sources we should test.")
  val allUnmanagedResourceDirectories = SettingKey[Seq[File]]("all-unmanaged-resource-directories", "unmanaged-resource-directories, transitively.")
  val ensureNoUncommitted = TaskKey[Unit]("ensure-no-uncommitted", "Fails if there are any uncommitted changes")
  val computeRevision     = TaskKey[Unit]("compute-revision", "Sets the mercurial.id environment variable to result of 'hg id'")
  val initLibraryPath     = TaskKey[Unit]("init-library-path", "Sets the java.library.path environment variable")
  val getLibraryPath      = TaskKey[Unit]("get-library-path", "Gets the java.library.path environment variable")
  val enableTypeCheck     = TaskKey[Unit]("enable-typechecking", "Sets the JVM property that turns on type checking.")
  val repl                = InputKey[Unit]("repl", "Run the Ermine read-eval-print loop")
  val smrepl              = InputKey[Unit]("sm-repl", "Run the Ermine read-eval-print loop with SM support")
  val main                = InputKey[Unit]("main", "Run the test Main class")
  val editor              = InputKey[Unit]("editor", "Run the Ermine Editor")

  private lazy val projectSettings =
    Defaults.defaultSettings ++ Settings.universalProjectSettings

  lazy val core = Project( id = "core"
                         , base = file("core")
                         , settings = projectSettings :+
      fullRunInputTask(repl, Compile, "com.clarifi.reporting.ermine.session.Console")
                         )

  lazy val utilJavafx = Project( id = "utilJavafx"
    , base = file("utilJavafx")
    , settings = projectSettings
  )

  lazy val ermineEditor = Project( id = "ermineEditor"
    , base = file("editor")
    , settings = projectSettings :+
          fullRunInputTask(editor, Compile, "com.clarifi.reporting.ermine.editor.StandaloneEditor")
    , dependencies = Seq(core, utilJavafx)
  )

  lazy val scalacheckBinding = Project( id = "scalacheckBinding"
    , base = file("scalacheck-binding")
    , settings = projectSettings
    , dependencies = Seq(core)
  )

  /** List of projects we actually publish. */
  def publishedProjects[A](implicit bc: Project => A): Seq[A] = Seq(core, utilJavafx, ermineEditor, scalacheckBinding)

  private[this] def cons[A](a: A, as: Seq[A]) = a +: as // Scala is weird.

  lazy val project = Project (
    "Ermine",
    file ("."),
    settings = projectSettings ++
      Set(fullRunInputTask(repl, Compile, "com.clarifi.reporting.Main")),
    aggregate = publishedProjects
  )

  /** Depend on log4j, with appropriate exclusions. */
  lazy val log4jDependency =
    ("log4j" % "log4j" % "1.2.15"
       exclude("com.sun.jdmk", "jmxtools")
       exclude("com.sun.jmx", "jmxri")
       exclude("javax.jms", "jms")
       exclude("javax.mail", "mail")
       exclude("javax.activation", "activation"))

  /** Multiply a setting across Compile, Test, Runtime. */
  def compileTestRuntime[A](f: Configuration => Setting[A]): SettingsDefinition =
    seq(f(Compile), f(Test), f(Runtime))

  /** Filter messages sent through loggers produced by `coreLogMgr`.
    *
    * @param logf Invoke for each acquired logger; invoke its result
    *             for each log message that comes in.
    */
  def filterLogs(coreLogMgr: LogManager
               )(logf: AbstractLogger => (Level.Value, => String) => Unit): LogManager =
    new LogManager {
      def apply(data: Settings[Scope], state: State,
                task: ScopedKey[_], writer: java.io.PrintWriter): Logger = {
        coreLogMgr(data, state, task, writer) match {
          case coreLog: AbstractLogger => new MultiLogger(List(coreLog)) {
            private val logfn = logf(coreLog)
            override def log(level: Level.Value, message: => String) =
              logfn(level, message)
          }
          case log => log
        }
      }
    }

  import scala.collection.JavaConverters._
  import com.googlecode.{jslint4java => jsl}

  /** Pick out our JavaScript sources. */
  def jsSources(rsrcs: Seq[java.io.File]): Seq[java.io.File] =
    rsrcs filter (fl => fl.getPath.endsWith(".js"))

  private lazy val linter = new jsl.JSLintBuilder().fromDefault()
  private val here = new File("").getAbsoluteFile.toURI
  private val suppressReasons = Set("Unexpected 'else' after 'return'.",
                                    "Don't make functions within a loop.")

  /** Run JSLint, producing issues. */
  def jsLint(jsf: java.io.File): Seq[jsl.Issue] = {
    val rel = here.relativize(jsf.toURI).getPath
    val r = new java.io.FileReader(jsf)
    // return } else detection seems broken in jslint 2012-12-04 (jslint4java 2.0.3)
    (try {linter lint (rel, r)} finally {r.close()})
      .getIssues.asScala filter (i => !suppressReasons(i.getReason))
  }
}
