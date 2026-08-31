package com.clarifi.reporting

import com.clarifi.reporting.ermine.session.{ Session => S, SessionEnv }

import org.scalacheck._
import Prop._
import scalaparsers.Supply

import java.io.File

/** Stage 2 item 5.3: Session.Buffer, the SourceFile an open editor
  * buffer loads through.
  *
  * The properties here are the guard on the process-global depCache
  * poisoning class fixed at D0 and D3 part 3b.  Two shapes were
  * explicitly rejected for buffers: Session.Literal, whose equality
  * keys off the MODULE NAME (so one editor's text would replay into
  * every other session's load of that name), and a plain Filesystem
  * dep, whose mtime does not move when a buffer changes (so the dep
  * built from the SAVED text would be served back).  Buffer's identity
  * is content-bearing and its lastModified is the document version;
  * these pin both halves.
  */
object TestEditorBuffers extends Properties("Editor buffers 5.3") {
  private val fx = ErmineFixture()

  private val path = "editor-buffer-test" + File.separator + "BufOne.e"

  private def src(body: String) =
    "module BufOne where\nimport Primitive\n\n" + body

  /** Load one buffer in its OWN session and answer what it defined.  The
    * sessions are independent; the depCache between them is not. */
  private def namesFrom(text: String, version: Long): Set[String] =
    fx.session { implicit s =>
      implicit val su: Supply = fx.supply
      implicit val con = fx.con
      S.loadModules(List("Primitive"))
      S.load(S.Buffer(path, text, version))
      s.termNames.keysIterator.collect { case g if g.module == "BufOne" => g.string }.toSet
    }

  property("a buffer loads its own text, and the file need not exist") =
    (namesFrom(src("alpha = 1\n"), 1) ?= Set("alpha")) &&
      (!new File(path).exists :| "the test wrote a file it should not have")

  property("a new version is not served the old version's dep") = {
    val a = namesFrom(src("alpha = 1\n"), 1)
    val b = namesFrom(src("beta = 2\n"), 2)
    (a ?= Set("alpha")) && (b ?= Set("beta"))
  }

  property("same version, different text is still not served the old dep") = {
    // The sharp form: a client that reuses a version number (or a server
    // that forgets to bump one) must not get the previous text back.
    // Literal-style module-name keying fails exactly here.
    val a = namesFrom(src("alpha = 1\n"), 7)
    val b = namesFrom(src("gamma = 3\n"), 7)
    (a ?= Set("alpha")) && (b ?= Set("gamma"))
  }

  property("a buffer's toString is the plain file name") =
    // It is the fileName threaded into every ParseState and every Pos
    // built from one, so the "file:line:col:" contract the Diagnostics
    // regex and definition locations rest on depends on it.
    S.Buffer("/x/Y.e", "module Y where\n", 1).toString ?= "/x/Y.e"

  property("a buffer's lastModified IS its version") =
    S.Buffer("/x/Y.e", "module Y where\n", 42).lastModified ?= Some(42L)

  property("buffers for different paths are different cache keys") =
    (S.Buffer("/x/Y.e", "same", 1) != S.Buffer("/z/Y.e", "same", 1)) :|
      "same module name, different files must not collide (the Literal trap)"
}
