name := "ermine-javafx-util"

compileOrder := CompileOrder.JavaThenScala

javacOptions in (Compile, compile) ++= Seq("-Xlint:unchecked", "-Xlint:rawtypes")

unmanagedJars in Compile <++= streams map { s =>
  val evidence = "javafx.scene.paint.Color"
  if (try {Class.forName(evidence); true}
      catch {case _:ClassNotFoundException => false}) Seq()
  else {
    val javaHome = System.getenv("JAVA_HOME")
    if (javaHome eq null) throw new RuntimeException("Set JAVA_HOME to a JDK 7u11 or later")
    val dir: File = new File(javaHome)
    //
    val jfxJar = new File(dir, "/jre/lib/jfxrt.jar")
    if (!jfxJar.exists) {
      throw new RuntimeException( "JavaFX not detected (needs Java 7u11 or later): "+ jfxJar.getPath )
    }
    s.log.info("Adding Java FX jar to classpath: " + jfxJar)
    Seq(Attributed.blank(jfxJar))
  }
}

//logLevel := Level.Debug
