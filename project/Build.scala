package com.clarifi.reporting.project

import sbt._
import Keys._

object ReportingBuild extends Build {
  val clarifiMode         = SettingKey[Boolean]("clarifi-mode", "Set distribution settings for local publication.")
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

  lazy val examples = Project( id = "examples"
    , base = file("core") / "examples"
    , settings = projectSettings
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
  def publishedProjects[A](implicit bc: Project => A): Seq[A] =
    Seq(core, examples, utilJavafx, ermineEditor, scalacheckBinding)

  private[this] def cons[A](a: A, as: Seq[A]) = a +: as // Scala is weird.

  lazy val project = Project (
    "Ermine",
    file ("."),
    settings = projectSettings ++
      Set(fullRunInputTask(repl, Compile, "com.clarifi.reporting.Main")),
    aggregate = publishedProjects
  )

  /** Seriously evil. */
  private[this] val initedClassloaders =
    collection.mutable.WeakHashMap[ClassLoader, Map[Set[File], ClassLoader]]()

  /** An evil way to hijack the classloader sharing in sbt.  Used in
    * scalaInstance setting.  Using anywhere else will not work.
    */
  def sharedClassloaderInit(files: Seq[File], parent: ClassLoader
                          )(init: => ClassLoader): ClassLoader =
    initedClassloaders.synchronized{
      val m = initedClassloaders get parent getOrElse Map()
      val fs = files.toSet
      m get fs getOrElse {
        val cl = init
        initedClassloaders(parent) = m updated (fs, cl)
        cl
      }
    }

  /** Make a `scalaInstance` that can use jline 1.0 safely, and recycles
    * via `sharedClassloaderInit`.
    */
  def jlineOneScalaInstance(s: TaskStreams, dc: Seq[Attributed[File]],
                            si: ScalaInstance): ScalaInstance = {
    import sbt.classpath.ClasspathUtilities.{makeLoader, rootLoader}
    val extras = dc.view.map(_.data)
      .filter(_.getPath matches "(?si).*jline[^\\\\/]*\\.jar$").force
    if (extras.isEmpty) si else {
      // si.loader has an incompatible jline loaded into it, so we
      // use rootLoader instead of si.loader.
      val jljxload = sharedClassloaderInit(extras, rootLoader){
        makeLoader(extras, rootLoader, si)
      }
      s.log.debug("Using custom classloader " + jljxload)
      // XXX will likely need to be adapted for sbt 0.14 -SMRC
      new ScalaInstance(si.version, jljxload, si.libraryJar,
                        si.compilerJar, si.extraJars, si.explicitActual)
    }
  }

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
    Seq(f(Compile), f(Test), f(Runtime))

  /** Update for local publication. */
  def withClarifiMode[T](k: SettingKey[T])(f: T => T) =
    k <<= (k, clarifiMode in ThisBuild)((o, cm) => if (cm) f(o) else o)

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

  // We're still using scala-iterv; we know, so stop telling us.
  lazy val suppressScalazItervWarnings =
    logManager in Compile ~= {coreLogMgr =>
      filterLogs(coreLogMgr){coreLog =>
        val suppWarnTails = Seq("in package scalaz is deprecated: Scalaz 6 compatibility. Migrate to scalaz.iteratee.",
                                // -unchecked always on in 2.10.2 compiler I think
                                "is unchecked since it is eliminated by erasure")
        val suppress = new java.util.concurrent.atomic.AtomicInteger(0)
        def zero(n:Int) = suppress.compareAndSet(n, 0)
        (level, message) => {
          suppress.decrementAndGet() match {
            case n if suppWarnTails exists message.endsWith =>
              suppress.compareAndSet(n, 2)
            case 1 if level == Level.Warn => ()
            case 0 if level == Level.Warn && (message endsWith "^") => ()
            case n if coreLog atLevel level =>
              zero(n)
              coreLog.log(level, message)
            case n => zero(n)
          }
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
