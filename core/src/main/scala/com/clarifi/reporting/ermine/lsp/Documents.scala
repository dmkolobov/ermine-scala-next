package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.session.{ Session, TolerantCheck }

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
                       index: Option[Definitions.DocIndex],
                       cache: TolerantCheck.Cache = TolerantCheck.Cache.empty) {
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
      // The index AND the inference cache survive the edit: the index
      // because stale navigation beats none while the next check runs,
      // the cache because its own scopeKey/fingerprints decide what of
      // it still applies (roadmap 5.5).
      val prev = docs.get(uri)
      val d = Doc(uri, path, text, version, prev.flatMap(_.index),
                  prev.map(_.cache) getOrElse TolerantCheck.Cache.empty)
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

  def cacheFor(fileName: String): TolerantCheck.Cache =
    byPath(fileName).map(_.cache) getOrElse TolerantCheck.Cache.empty

  def putCache(fileName: String, c: TolerantCheck.Cache): Unit =
    byPath(fileName) foreach { d => docs += d.uri -> d.copy(cache = c) }

  /** The versions of every OTHER open buffer, for a check's scope key: a
    * sibling's unsaved edit changes what this file's imports mean, and
    * its own version must NOT be in there or typing would invalidate
    * its own cache on every keystroke (roadmap 5.5). */
  def otherVersions(fileName: String): String =
    docs.valuesIterator.filter(_.path.toString != fileName)
      .map(d => d.path.toString + "@" + d.version).toList.sorted.mkString(",")

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
