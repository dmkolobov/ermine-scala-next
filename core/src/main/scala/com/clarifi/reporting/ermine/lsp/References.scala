package com.clarifi.reporting.ermine.lsp

import com.clarifi.reporting.ermine.{ Idfix, Local }
import com.clarifi.reporting.ermine.rename.Renamer
import com.clarifi.reporting.ermine.surface.Lexer

/** textDocument/references, documentHighlight, prepareRename and rename
  * (tracker/LSP-ROADMAP.md, Stage 3 item 6.3).
  *
  * NOTHING HERE ANALYSES ANYTHING.  The Stage-3 invariant is that a
  * request reads the tables the LAST CHECK left behind and nothing else:
  * no parse, no rename pass, no inference, on any path reachable from a
  * request.  So every answer below is a comparison of `Definitions.Key`s
  * over `Documents`' stored `DocIndex`es, plus — for rename's refusals —
  * the renamer `Frame`s and `moduleTerms` the same index carries.
  *
  * WHAT "THE SET" IS, per key kind (6.3.2):
  *
  *  - a LOCAL key is a renamer binder id.  It means nothing outside the
  *    document whose check minted it, so the set is every occurrence in
  *    THIS document carrying that id, and the declaration is the binder's
  *    own def-site — which the index carries as an occurrence in its own
  *    right since 6.3, because a pattern binder is not an occurrence at
  *    all and a reader clicks exactly there.
  *
  *  - a GLOBAL key is a canonical `Global` (`ToGlobal.origin`, never the
  *    `g` a reference was written through: an alias-imported name and its
  *    canonical name ARE one name).  The set is every occurrence in every
  *    OPEN document with that origin — uses, the defining module's own
  *    equation heads, its declaration heads, its fixity lines and the
  *    `import M using (n)` lists that name it — plus the def-site.  When
  *    the defining file is not open the def-site is still a real
  *    position, and it is reported as a Location (it is the very Target
  *    go-to-definition answers); rename REFUSES rather than edit it.
  *
  * COVERAGE (Decision c).  The workspace is the open buffers.  A module
  * that imports the one being searched but is not open is not searched,
  * and the server cannot know whether such a module exists — so a global
  * references or rename request always says so, once, with a
  * `window/showMessage` warning.  A local key needs no warning (a local
  * cannot escape its file) and highlight needs none (it is per-document
  * by definition).
  *
  * RENAME (Decision d) never produces a partial edit: every refusal
  * below is checked BEFORE any edit is built, and the answer is a
  * ResponseError with a message a person can act on.
  */
object References {

  /** LSP DocumentHighlightKind. */
  private val HighlightRead  = 2
  private val HighlightWrite = 3

  /** The name classes a rename may not cross.  A constructor or type
    * name is upper-initial, a term or binder lower-initial, and an
    * operator is a different lexical thing altogether. */
  private sealed abstract class NameClass
  private case object LowerName extends NameClass
  private case object UpperName extends NameClass
  private case object OpName    extends NameClass

  /** Classify a spelling the way the SURFACE grammar does, not with a
    * regex of our own: an operator is what `Lexer.op` lexes whole (the
    * lexer ported byte-for-byte from the fused parser, key operators and
    * the comment rule included), and an identifier is `letter` followed
    * by `Lexer.isTailChar`s (`ParsingUtil.identTail`) that is not a
    * keyword.  Anything else — a qualified `M.foo`, a parenthesised
    * `(<+>)`, an empty string — is None, and rename refuses it. */
  private def classify(s: String): Option[NameClass] =
    if (s.isEmpty) None
    else if (Lexer.op(s, 0).exists(_.end == s.length)) Some(OpName)
    else if (s.charAt(0).isLetter &&
             s.substring(1).forall(Lexer.isTailChar) &&
             !com.clarifi.reporting.ermine.parsing.keywords(s))
      Some(if (s.charAt(0).isUpper) UpperName else LowerName)
    else None

  private def refuse(code: Int, message: String): Nothing = throw RpcError(code, message)

  def install(server: Server, ermine: Resident, docs: Documents, log: String => Unit): Unit = {

    // Same rule as navigation (Definitions): during the ~13s boot there
    // is no index to answer from, and a request must not read as a hang.
    def ifReady(answer: => Json): Json =
      if (ermine.ready) answer
      else { log("references: answering null, session still booting"); Json.Null }

    /** The occurrence under the cursor, with the document and index it
      * came from.  The hit-test is `Definitions.hit` — the one every
      * other request uses, so "the name at this position" has exactly
      * one meaning in this server. */
    def siteAt(params: Json): Option[(docs.Doc, Definitions.DocIndex, Definitions.Occ)] =
      for {
        uri  <- params / "textDocument" flatMap (_ / "uri") flatMap (_.str)
        d    <- docs get uri
        idx  <- d.index
        pos  <- params / "position"
        line <- pos / "line" flatMap (_.int)
        chr  <- pos / "character" flatMap (_.int)
        occ  <- Definitions.hit(idx, line + 1, chr + 1)  // LSP 0-based, Span 1-based
      } yield (d, idx, occ)

    /** Every stored occurrence of `key`.  A local key is scoped to its
      * own document; a global key spans the open buffers. */
    def occurrencesOf(home: docs.Doc, key: Definitions.Key)
        : List[(docs.Doc, Definitions.Occ)] = {
      val ds = key match {
        case _: Definitions.LocalKey  => List(home)
        case _: Definitions.GlobalKey => docs.all
      }
      ds.flatMap { d =>
        d.index.toList.flatMap(_.occs)
          .filter(_.key.contains(key))
          .sortBy(o => (o.line, o.startCol))
          .map(d -> _)
      }
    }

    def rangeOf(o: Definitions.Occ): Json =
      Json.obj(
        "start" -> Json.obj("line" -> Json.num(o.line - 1),
                            "character" -> Json.num(o.startCol - 1)),
        "end"   -> Json.obj("line" -> Json.num(o.line - 1),
                            "character" -> Json.num(o.startCol - 1 + o.len)))

    def locationOf(d: docs.Doc, o: Definitions.Occ): Json =
      Json.obj("uri" -> Json.Str(d.uri), "range" -> rangeOf(o))

    def isGlobal(key: Definitions.Key): Boolean = key match {
      case _: Definitions.GlobalKey => true
      case _                        => false
    }

    /** Decision (c).  Sent ONCE per request, and only for a global key:
      * the search covered the open buffers, and there is no way from
      * here to know whether an unopened module imports this name. */
    def coverageWarning(what: String): Unit = {
      val n = docs.all.size
      server.notify("window/showMessage", Json.obj(
        "type"    -> Json.num(2),
        "message" -> Json.Str(
          "Ermine: " + what + " searched in " + n + " open file" +
          (if (n == 1) "" else "s") + "; unopened importers are not searched")))
    }

    // ---------------------------------------------------------- references

    server.onRequest("textDocument/references") { params => ifReady {
      siteAt(params) match {
        case None => Json.Null
        case Some((home, _, occ)) => occ.key match {
          case None      => Json.Arr(Nil)
          case Some(key) =>
            val hits = occurrencesOf(home, key)
            val incl = (params / "context" flatMap (_ / "includeDeclaration")
                          flatMap (_.bool)) getOrElse true
            val uses = if (incl) hits else hits.filterNot(_._2.isDef)
            // The declaration of a global whose file nobody has open is
            // not an occurrence anywhere — but it is a real position,
            // and it is the one this very name's definition request
            // answers, so it belongs in the set when asked for.
            val outside =
              if (incl && !hits.exists(_._2.isDef))
                occ.target.flatMap(Definitions.location).toList
              else Nil
            if (isGlobal(key)) coverageWarning("references")
            Json.Arr(uses.map { case (d, o) => locationOf(d, o) } ++ outside)
        }
      }
    } }

    // --------------------------------------------------- document highlight

    server.onRequest("textDocument/documentHighlight") { params => ifReady {
      siteAt(params) match {
        case Some((_, idx, occ)) if occ.key.isDefined =>
          val key = occ.key.get
          // Per-document by definition, so no coverage warning: a
          // highlight is about the buffer on screen.
          Json.Arr(idx.occs.filter(_.key.contains(key))
            .sortBy(o => (o.line, o.startCol))
            .map(o => Json.obj(
              "range" -> rangeOf(o),
              "kind"  -> Json.num(if (o.isDef) HighlightWrite else HighlightRead))))
        case _ => Json.Null
      }
    } }

    // ------------------------------------------------------- prepareRename

    server.onRequest("textDocument/prepareRename") { params => ifReady {
      siteAt(params) match {
        // `exact` (review R2): a name whose SOURCE form differs from its
        // spelling -- a backtick literal, a parenthesised operator -- is
        // not renameable, so prepareRename says so before the user types
        // a new name.
        case Some((_, _, occ))
          if occ.key.isDefined && occ.exact && classify(occ.spelling).exists(_ != OpName) =>
          Json.obj("range" -> rangeOf(occ), "placeholder" -> Json.Str(occ.spelling))
        case _ => Json.Null   // not a renameable name here
      }
    } }

    // -------------------------------------------------------------- rename

    server.onRequest("textDocument/rename") { params =>
      if (!ermine.ready)
        refuse(Rpc.RequestFailed,
               "the Ermine session is still starting; retry once it is ready")

      val newName = (params / "newName" flatMap (_.str)) getOrElse
        refuse(Rpc.InvalidParams, "rename: the request carries no newName")

      val (home, _, occ) = siteAt(params) getOrElse
        refuse(Rpc.InvalidParams, "cannot rename: there is no name at that position")

      val key = occ.key getOrElse
        refuse(Rpc.InvalidParams,
               "cannot rename '" + occ.spelling + "': it resolves to nothing this " +
               "check could name")

      val old = occ.spelling

      // (vi) THE SOURCE FORM (review R2).  A backtick literal spells
      // `wide` and is written ``wide``; its span starts at the first
      // backtick, so a replacement measured by the spelling would write
      // over four characters of an eight-character token and leave the
      // file unparseable.  The index records whether the source spells
      // the name the way `spelling` does, and rename refuses when it
      // does not -- REFUSED rather than re-wrapped, because whether the
      // NEW name needs backticks is a grammar question (``1pixel`` is
      // digit-initial and legal only inside them, ``a b`` holds a space)
      // and the literal form carries its own backslash escapes.
      if (!occ.exact)
        refuse(Rpc.RequestFailed,
               "cannot rename '" + old + "': the source writes it in a form that is " +
               "not its spelling (a ``literal`` name, or a parenthesised operator) — " +
               "renaming it would have to rebuild that form")

      // (ii) OPERATORS, refused BOTH ways.  An operator's spelling is
      // bound up with its fixity declaration and its parse; there is no
      // textual rename of one that is safe.
      val oldClass = classify(old) match {
        case Some(OpName) =>
          refuse(Rpc.InvalidParams,
                 "cannot rename the operator '" + old + "': an operator's spelling " +
                 "carries its fixity, so renaming one is refused")
        case None =>
          refuse(Rpc.InvalidParams,
                 "cannot rename '" + old + "': it is not a plain Ermine identifier")
        case Some(c) => c
      }

      // (i) the new name must be a valid identifier of the SAME CASE CLASS.
      val newClass = classify(newName) match {
        case Some(OpName) =>
          refuse(Rpc.InvalidParams,
                 "cannot rename to '" + newName + "': that is an operator spelling")
        case None =>
          refuse(Rpc.InvalidParams,
                 "'" + newName + "' is not a valid Ermine identifier")
        case Some(c) => c
      }
      if (newClass != oldClass)
        refuse(Rpc.InvalidParams,
               "cannot rename '" + old + "' to '" + newName + "': " +
               (if (oldClass == UpperName)
                  "a constructor or type name must stay upper-case"
                else "a term name must stay lower-case"))

      val hits = occurrencesOf(home, key)

      // The DEF-SITE must be in a buffer this server may edit.  For a
      // local it always is; for a global it is exactly the stdlib case
      // (Decision d: never edit a file that is not open).
      if (!hits.exists(_._2.isDef))
        refuse(Rpc.RequestFailed,
               "cannot rename a name defined in a file that is not open — open '" +
               old + "''s defining module and try again")

      // Every mention must be written the way the def-site spells it.
      // An alias import (`import M as N`, `foo_M`) or a qualified use
      // spells the same name differently, and replacing those spans with
      // the new bare name would break the file.  Refusing is the only
      // answer that is not a partial or a wrong edit.
      val spellings = hits.map(_._2.spelling).distinct
      if (spellings.size > 1)
        refuse(Rpc.RequestFailed,
               "cannot rename '" + old + "': it is mentioned under more than one " +
               "spelling (" + spellings.sorted.mkString(", ") + ") — an alias import " +
               "or a qualified mention, which a textual rename cannot follow")

      // Every mention must be written the way the index measured it
      // (review R2): one non-exact occurrence anywhere in the set and the
      // whole edit is refused, never partly applied.
      hits.find(!_._2.exact).foreach { case (d, o) =>
        refuse(Rpc.RequestFailed,
               "cannot rename '" + old + "': it is written in a form that is not its " +
               "spelling at " + d.path.getFileName + ":" + o.line +
               " (a ``literal`` name, or a parenthesised operator)")
      }

      // (vii) ONE SPELLING, ONE GLOBAL KEY (review R1's belt).  If two
      // open buffers hold this spelling under DIFFERENT canonical
      // globals, then either two modules really do define it — in which
      // case a rename here would be read as a rename there — or the
      // canonicalisation above failed to join a re-export chain.  Either
      // way the set is not the whole story, so refuse rather than edit
      // part of it.  A LOCAL key is exempt on purpose: a local shadowing
      // a global of the same spelling is two names, two sets, and both
      // rename correctly.
      if (isGlobal(key))
        docs.all.foreach { d =>
          d.index.foreach { ix =>
            ix.occs.find(o => o.spelling == old && o.key.exists(k =>
                           isGlobal(k) && k != key)).foreach { o =>
              refuse(Rpc.RequestFailed,
                     "cannot rename '" + old + "': " + d.path.getFileName + ":" + o.line +
                     " holds that spelling under a different definition (" +
                     (o.key.get match { case Definitions.GlobalKey(g, _) => g.toString
                                        case k                          => k.toString }) +
                     ") — rename it from there, or close that buffer")
            }
          }
        }

      // (iv) STALE INDEX.  A keystroke since the last check means the
      // index's positions describe text that is gone.  Refuse; never
      // guess, and never edit only the files that happen to be current.
      //
      // Review R3: EVERY open document is checked for a global rename,
      // not only the ones that already have a hit — a sibling edited
      // since its last check may have just gained a mention its stale
      // index cannot know about, and it would be neither refused nor
      // edited.  A local key cannot leave its own file, so it checks only
      // that one.  A document with NO index has never been checked and so
      // has produced no mention; it is in the same class as an unopened
      // importer, which the coverage warning already speaks for.
      val toVersion =
        if (isGlobal(key)) docs.all
        else docs.all.filter(_.uri == home.uri)
      toVersion.foreach { d =>
        if (d.index.exists(_.version != d.version))
          refuse(Rpc.RequestFailed,
                 "check pending; retry after diagnostics update (" +
                 d.path.getFileName + " has been edited since its last check)")
      }

      val touched = docs.all.filter(d => hits.exists(_._1.uri == d.uri))

      // An AMBIGUOUS mention of the same spelling is a name the renamer
      // itself could not resolve, so the edit would be a guess.
      touched.foreach { d =>
        d.index.foreach { ix =>
          if (ix.renamed.occurrences.exists(o =>
                o.spelling == old && o.resolution.isInstanceOf[Renamer.Ambiguous]))
            refuse(Rpc.RequestFailed,
                   "cannot rename '" + old + "': it is mentioned ambiguously in " +
                   d.path.getFileName + " (two imports offer that name)")
        }
      }

      // (iii) CAPTURE.  Three ways the new name could mean something
      // else where the old one is used, all read off the tables:
      //   - it is already bound in a renamer FRAME containing one of our
      //     occurrences (an enclosing or sibling binder);
      //   - it is already one of that module's own top levels;
      //   - it already resolves through that file's canonical import
      //     scope (the map the renamer itself resolves through).
      // Any of them and the renamed name would either shadow something
      // or be shadowed by it.  We refuse rather than reason about which.
      val probe = Local(newName, Idfix)
      touched.foreach { d =>
        d.index.foreach { ix =>
          val ours = hits.filter(_._1.uri == d.uri).map(_._2)
          ours.foreach { o =>
            if (ix.renamed.scopeAt(o.line, o.startCol).contains(newName))
              refuse(Rpc.RequestFailed,
                     "cannot rename '" + old + "' to '" + newName + "': '" + newName +
                     "' is already bound where '" + old + "' is used (" +
                     d.path.getFileName + ":" + o.line + ")")
          }
          if (ours.nonEmpty) {
            val clashesTop =
              if (newClass == UpperName)
                ix.renamed.binders.values.exists(b =>
                  b.kind == Renamer.TyDef && b.spelling == newName) ||
                ix.renamed.moduleTerms.contains(newName)
              else ix.renamed.moduleTerms.contains(newName)
            if (clashesTop)
              refuse(Rpc.RequestFailed,
                     "cannot rename '" + old + "' to '" + newName + "': '" + newName +
                     "' is already defined at the top level of " + ix.moduleName)
            val inScope =
              ix.scopeTerms.contains(probe) ||
              (newClass == UpperName && ix.scopeTypes.contains(probe))
            if (inScope)
              refuse(Rpc.RequestFailed,
                     "cannot rename '" + old + "' to '" + newName + "': '" + newName +
                     "' is already in scope in " + d.path.getFileName + " (imported)")
          }
        }
      }

      // Only now, with every refusal past, is an edit built — and it is
      // built for EVERY site at once, so there is no partial outcome.
      val changes = touched.map { d =>
        val es = hits.filter(_._1.uri == d.uri).map(_._2)
          .sortBy(o => (o.line, o.startCol))
          .map(o => Json.obj("range" -> rangeOf(o), "newText" -> Json.Str(newName)))
        d.uri -> (Json.Arr(es): Json)
      }
      if (isGlobal(key)) coverageWarning("rename")
      log("rename: " + old + " -> " + newName + " in " + changes.size +
          " file(s), " + hits.size + " edit(s)")
      Json.obj("changes" -> Json.Obj(changes))
    }
  }
}
