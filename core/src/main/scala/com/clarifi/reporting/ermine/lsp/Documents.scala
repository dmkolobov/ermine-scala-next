package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.session.Session

import java.io.File
import java.nio.file.{ Path, Paths }

/** The open documents (roadmap 5.3): one record per uri holding the
  * buffer text, its version, and the navigation index built from the
  * last check of it.  Before 5.3 the server read the SAVED file and the
  * index lived in its own map; folding them together is what lets a
  * check, a definition request and the sibling loader all agree on what
  * "the file" currently says.
  *
  * Single-threaded, like all request handling (roadmap decision 3).
  */
final class Documents {

  final case class Doc(uri: String, path: Path, text: String, version: Long,
                       index: Option[Definitions.DocIndex]) {
    /** The SourceFile a load should see for this document. */
    def source: Session.Buffer = Session.Buffer(path.toString, text, version)
  }

  private var docs = Map.empty[String, Doc]

  def get(uri: String): Option[Doc] = docs get uri

  /** The navigation index, if this document has been checked. */
  def index(uri: String): Option[Definitions.DocIndex] = docs.get(uri).flatMap(_.index)

  def putIndex(uri: String, idx: Definitions.DocIndex): Unit =
    docs.get(uri) foreach { d => docs += uri -> d.copy(index = Some(idx)) }

  /** didOpen / didChange.  The superseded buffer is evicted from the
    * process-global depCache: its key is content-bearing, so without
    * this a long editing session would leave one dead Dep per keystroke
    * behind (correctness is the mtime guard's job; this is hygiene). */
  def put(uri: String, text: String, version: Long): Option[Doc] =
    pathFor(uri) map { path =>
      docs.get(uri) foreach { old => Session.depCache -= old.source }
      // The index is kept across the edit on purpose: navigation on a
      // stale index beats none while the next check runs.
      val d = Doc(uri, path, text, version, docs.get(uri).flatMap(_.index))
      docs += uri -> d
      d
    }

  def drop(uri: String): Unit = {
    docs.get(uri) foreach { old => Session.depCache -= old.source }
    docs -= uri
  }

  /** The buffer for a path, if that file is open. */
  def byPath(fileName: String): Option[Doc] =
    docs.valuesIterator.find(_.path.toString == fileName)

  /** A loader that answers from open buffers, resolving module names the
    * way SourceFile.filesystem does (dots are directories) but WITHOUT
    * requiring the file to exist on disk — an unsaved new module is
    * exactly the case the saved-file loader cannot serve. */
  def loaderFor(dir: String): Session.SourceFile.Loader = module => {
    val fileName = (dir :: module.split('.').toList).mkString(File.separator) + ".e"
    byPath(fileName) map (_.source)
  }

  def pathFor(uri: String): Option[Path] =
    try {
      val u = new java.net.URI(uri)
      if (u.getScheme == "file") Some(Paths.get(u)) else None
    } catch { case _: Exception => None }
}
