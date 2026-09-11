package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.session.{ Session, TolerantCheck }
import com.clarifi.reporting.ermine.surface.SurfaceCache

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
                       cache: TolerantCheck.Cache = TolerantCheck.Cache.empty,
                       /** 7.1b: the statement-extent surface cache the last
                         * check of this document built -- one parsed tree per
                         * open document, REPLACED WHOLESALE by the next check,
                         * so what it retains is bounded by the document and
                         * nothing accumulates across keystrokes. */
                       surface: Option[SurfaceCache.Cache] = None,
                       /** 6.6: the diagnostics the last check PUBLISHED for
                         * this document, each still paired with the source
                         * that produced it.  A code action answers from
                         * this list rather than from the client's copy of
                         * it, and the ranges here are the ranges that went
                         * out on the wire. */
                       diags: List[QuickFix.Published] = Nil) {
    /** The SourceFile a load should see for this document. */
    def source: Session.Buffer = Session.Buffer(path.toString, text, version)
  }

  private var docs = Map.empty[String, Doc]

  def get(uri: String): Option[Doc] = docs get uri

  /** Every open document.  References and rename (6.3) answer across
    * OPEN BUFFERS -- that set is the workspace Stage-3 Decision (c)
    * admits, and it is the set the coverage warning names. */
  def all: List[Doc] = docs.valuesIterator.toList.sortBy(_.uri)

  /** The navigation index, if this document has been checked. */
  def index(uri: String): Option[Definitions.DocIndex] = docs.get(uri).flatMap(_.index)

  /** Stamp the index with the version of the buffer it was built from
    * (6.3, Decision d).  Dispatch is single-threaded and the check ran
    * on this same buffer, so `d.version` IS that version; recording it
    * here is what lets rename refuse on a stale index instead of
    * writing an edit at positions the text no longer has. */
  def putIndex(uri: String, idx: Definitions.DocIndex): Unit =
    docs.get(uri) foreach { d =>
      docs += uri -> d.copy(index = Some(idx.copy(version = d.version)))
    }

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
                  prev.map(_.cache) getOrElse TolerantCheck.Cache.empty,
                  // 7.1b: the surface cache survives the edit for the reason
                  // the inference cache does -- it is what the NEXT read
                  // reuses, and its own guard decides what of it still
                  // applies against the text that just arrived.
                  prev.flatMap(_.surface),
                  // 6.6: the published diagnostics survive the edit for
                  // the same reason the index does -- they are what the
                  // editor is still showing.  A code action does not USE
                  // them across an edit (it refuses on a stale index),
                  // but dropping them here would make the next check's
                  // publish race the request rather than settle it.
                  prev.map(_.diags) getOrElse Nil)
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

  /** 7.1b: the surface cache for a path, and its replacement. */
  def surfaceFor(fileName: String): Option[SurfaceCache.Cache] =
    byPath(fileName).flatMap(_.surface)

  def putSurface(fileName: String, c: Option[SurfaceCache.Cache]): Unit =
    byPath(fileName) foreach { d => docs += d.uri -> d.copy(surface = c) }

  /** Store what a check published (6.6.1).  Set in the same breath as the
    * index, from the same check, so the two can never disagree about
    * which buffer they describe. */
  def putDiags(uri: String, ds: List[QuickFix.Published]): Unit =
    docs.get(uri) foreach { d => docs += uri -> d.copy(diags = ds) }

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
