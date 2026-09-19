package com.clarifi.reporting.ermine.lsp

import java.nio.file.{ Files, Path, Paths }

/** LSP-STALENESS step 3: the "not built" signal.
  *
  * Steps 1 and 2 made the stdlib SOURCE live in the editor; the Scala half
  * of the language -- foreign bindings, the builtins `Lib` installs -- is
  * still whatever the classpath was compiled from.  A name added in Scala
  * and not yet compiled therefore surfaces as an ordinary "undefined term",
  * "does not export" or "class missing", which is true and useless.  This
  * object answers one question, cheaply: are the compiled classes the server
  * runs OLDER than the Scala sources of the checkout it serves?  If so the
  * boot says it as a warning and every diagnostic a stale build could
  * explain carries a one-line hint.
  *
  * The classes stamp is the newest `.class` under the directory the class
  * loader serves `modules` from (`core/target/<scala>/classes`), taken ONCE:
  * what the server runs does not change while it runs.  The proxy is mtime,
  * and sbt's zinc stamps sources by CONTENT HASH: a source whose mtime moved
  * with no change in it (a `git checkout` between branches where the file
  * is the same, `cp` without `-p`) stays "newer than the classes" until a
  * compile that writes a class, because `sbt core/compile` on such a tree
  * does nothing -- acceptable for a hint that says "if".  The sources are
  * `core/src/main/scala` of the checkout the first module root belongs to
  * (the workspace's), or of the checkout the classes were built in when
  * there are no roots; scanned at most every five seconds, and again on
  * `ermine.reloadModules` (`forget`).  Only `core` is compared: that is
  * where the Ermine builtins and the writers live. */
object BuildStamp {

  final case class Stale(scalaDir: Path, newer: Int, newest: Path,
                         newestMillis: Long, classesMillis: Long)

  /** `core/target/<scala>/classes`, when the classes come from a directory. */
  lazy val classesDir: Option[Path] =
    try
      for {
        u <- Option(getClass.getClassLoader.getResource("modules"))
        if Option(u.getProtocol).exists(_ equalsIgnoreCase "file")
      } yield Paths.get(u.toURI).toAbsolutePath.normalize.getParent
    catch { case _: Exception => None }

  /** The newest `.class` under `classesDir`, once. */
  lazy val classesMillis: Option[Long] =
    classesDir.flatMap(d => scan(d, ".class", Long.MinValue).map(_._2._2))

  /** `core/src/main/scala` of the checkout the first STDLIB root is in
    * (`<root>` is `<checkout>/core/src/main/resources/modules`, so the Scala
    * sources are two levels up and over; a root that is not a checkout's
    * stdlib -- a `moduleRoots` option -- has no such directory and is
    * skipped), else of the checkout the classes were built in
    * (`<checkout>/core/target/...`). */
  def scalaDir(roots: List[String]): Option[Path] = {
    val fromRoots = roots.iterator.flatMap { r =>
      Option(Paths.get(r).toAbsolutePath.normalize.getParent).flatMap(p => Option(p.getParent))
        .map(_.resolve("scala")).filter(Files.isDirectory(_))
    }.toList.headOption
    val fromClasses = classesDir.flatMap { c =>
      var q = c
      while (q != null && q.getFileName != null && q.getFileName.toString != "target") q = q.getParent
      Option(q).flatMap(t => Option(t.getParent)).map(_.resolve("src").resolve("main").resolve("scala"))
    }.filter(Files.isDirectory(_))
    fromRoots orElse fromClasses
  }

  /** (how many files with `suffix` are newer than `threshold`, the newest
    * of them all), or None when the directory has none. */
  private def scan(dir: Path, suffix: String, threshold: Long): Option[(Int, (Path, Long))] = {
    if (!Files.isDirectory(dir)) return None
    val s = Files.walk(dir)
    try {
      var count = 0
      var best: Option[(Path, Long)] = None
      s.forEach { p =>
        if (p.toString.endsWith(suffix) && Files.isRegularFile(p)) {
          val t = Files.getLastModifiedTime(p).toMillis
          if (t > threshold) count += 1
          if (best.forall(_._2 < t)) best = Some((p, t))
        }
      }
      best.map(b => (count, b))
    } finally s.close()
  }

  private var cached: Option[(Long, Option[Stale])] = None

  /** Scan again on the next `status`. */
  def forget(): Unit = cached = None

  /** The stale state, if any; memoised for five seconds. */
  def status(roots: List[String]): Option[Stale] = {
    val now = System.currentTimeMillis
    cached match {
      case Some((t, s)) if now - t < 5000 => s
      case _ =>
        val s = compute(roots)
        cached = Some((now, s))
        s
    }
  }

  /** A file deleted mid-walk (a `git checkout` while a check runs) is not
    * a stale build and must not cost the check its diagnostics: the scan's
    * I/O errors answer "fresh" and are seen again five seconds later. */
  private def compute(roots: List[String]): Option[Stale] =
    try
      for {
        classes <- classesMillis
        dir     <- scalaDir(roots)
        (n, (newest, t)) <- scan(dir, ".scala", classes)
        if n > 0
      } yield Stale(dir, n, newest, t, classes)
    catch { case _: java.io.IOException | _: java.io.UncheckedIOException => None }

  private def time(ms: Long): String =
    java.time.Instant.ofEpochMilli(ms).atZone(java.time.ZoneId.systemDefault)
      .format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))

  /** For the log. */
  def describe(roots: List[String], s: Option[Stale]): String = s match {
    case Some(x) =>
      s"NOT BUILT: ${x.newer} Scala source(s) under ${x.scalaDir} newer than the classes " +
        s"(${x.newest} at ${time(x.newestMillis)}; classes ${classesDir.getOrElse("?")} at ${time(x.classesMillis)})"
    case None =>
      "the compiled classes (" + classesMillis.map(time).getOrElse("no class directory") +
        ") are newer than every Scala source under " + scalaDir(roots).map(_.toString).getOrElse("(no source tree)")
  }

  /** The boot warning (`window/logMessage`, type 2). */
  def bootMessage(s: Stale): String =
    s"Ermine: not built -- ${s.newer} Scala source(s) under core/src/main/scala are newer than the " +
      s"compiled classes (newest ${s.newest.getFileName} at ${time(s.newestMillis)}, classes built " +
      s"${time(s.classesMillis)}): a name added in Scala (a foreign binding, a builtin) is missing " +
      "until `sbt core/compile` and Ermine: Restart Language Server"

  /** The one-line hint a diagnostic carries. */
  def hint(s: Stale): String =
    s"not built: the compiled classes (${time(s.classesMillis)}) are older than ${s.newer} Scala " +
      s"source(s) under core/src/main/scala, newest ${s.newest.getFileName} (${time(s.newestMillis)}); " +
      "if this name was added in Scala, run sbt core/compile and restart the server"

  /** The diagnostics a stale build can explain: a name that is not there,
    * an export that is not there, a foreign class or member that is not
    * there or will not link.  Not "Module not found": a module is a `.e`
    * file, never a name added in Scala. */
  private val explained = List("undefined term", "does not export",
                               "class missing", "member missing", "field missing",
                               "constructor missing", "unloadable")

  def explains(message: String): Boolean = explained.exists(message.contains)

  /** The diagnostic with the hint appended to its message, when it is one
    * the build can explain; unchanged otherwise. */
  def annotate(d: Json, s: Stale): Json = d match {
    case Json.Obj(fields) =>
      fields.collectFirst { case ("message", Json.Str(m)) => m } match {
        case Some(m) if explains(m) =>
          Json.Obj(fields.map {
            case ("message", _) => "message" -> Json.Str(m + "\n\n" + hint(s))
            case f              => f
          })
        case _ => d
      }
    case _ => d
  }
}
