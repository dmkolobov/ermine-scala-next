package com.clarifi.reporting
package ermine.session

import System.nanoTime
import java.text.DecimalFormat
import java.net.URL
import java.io.File
import java.io.File.{separator, separatorChar}
import scala.util.control.NonFatal
import com.clarifi.reporting.{ PrimT, Header, Source, TableName }
import com.clarifi.reporting.Reporting.{ RefID }
import com.clarifi.reporting.ermine.session.SessionTask._
import com.clarifi.reporting.ermine.session.Printer._
import java.util.Date
import com.clarifi.reporting.ermine._
import com.clarifi.reporting.ermine.Relocatable.preserveLoc
import scalaparsers.{++, Death, Err, Loc, Located, Pos, Supply}
import scalaparsers.Document._
import com.clarifi.reporting.ermine.Type.{
  Con, ffi, io, bool, subType, int, long, float, double, string, char, date, byte, short, field, Nullable, typeVars,
  allTypeVars, True, False, Bad, Expanded, Unexpanded, primTypes
}
import com.clarifi.reporting.ermine.Term.{ subTermEx, termVars }
import com.clarifi.reporting.ermine.HasTermVars._
import com.clarifi.reporting.ermine.Runtime.Thunk
import com.clarifi.reporting.ermine.Subst.{
  inferTypeDefKindSchemas, inferBindingGroupTypes, kindCheck, substType, inferType, solve,
  assertTypeClosed, assertTermClosed, unfurlApp
}
import com.clarifi.reporting.ermine.syntax._
import com.clarifi.reporting.ermine.syntax.TypeDef.typeDefComponents
import com.clarifi.reporting.ermine.surface.Span
import com.clarifi.reporting.ermine.parsing.{
  phrase, ModuleHeader, ErParseState, ParseState, Parser, Recoverable
}
import ErParseState.Implicits._
import com.clarifi.reporting.ermine.parsing.ModuleParsers._
import com.clarifi.reporting.ermine.parsing.InterfaceParsers.interfaceFile
import com.clarifi.reporting.relational._

import scala.reflect._
import scalaz.Scalaz._
import scalaz.Monad
import scalaz.Free.{ suspend, Return }

import scala.collection.mutable.ListBuffer
import scala.jdk.CollectionConverters._
import scala.collection.immutable.List

import com.clarifi.reporting.util.PimpedLogger._

object Session {

  class Diagnostics {}
  private val _log = org.apache.log4j.Logger.getLogger(classOf[Diagnostics])

  type Stack = List[String]

  def subst[A](m: SubstEnv => A)(implicit s: SessionEnv) =
    m(new SubstEnv(s.classes, sigEntail = s.sigEntail))


  def install(v: TermVar, rep: Runtime)(implicit s: SessionEnv) = v.name match {
    case Some(g : Global) =>
       s.env = s.env + (v -> rep)
       s.termNames = s.termNames + (g -> v)
    case _ => die("install: non-global variable: " + v)
  }

  // @throws Death
  /** `loc` is the DEFINITION SITE of the name being installed, and the
    * variable keeps it: a data constructor, field, table or foreign
    * declaration is written in a source file just as an equation is, and
    * discarding the position (as this did until 2026-09-02) left the
    * editor with no place to jump to — every such name answered
    * textDocument/definition with null.  Scala-installed builtins reach
    * the 2-arg overload below and stay `Loc.builtin`. */
  def primOp(loc: Loc, name: Global, rep: Runtime, t: Type)(implicit s: SessionEnv, su: Supply): TermVar = {
    val v = V(loc, su.fresh, Some(name), Bound, t.nf)
    s.termNames.get(name) match {
      case Some(v) => die("primOp: rebinding " + name)
      case None    =>
        s.env = s.env + (v -> rep)
        s.termNames = s.termNames + (name -> v)
        v
    }
  }
  def primOp(name: Global, rep: Runtime, ty: Type)(implicit s: SessionEnv, su: Supply): TermVar = primOp(Loc.builtin, name, rep, ty)

  def addCon(c: Con)(implicit s: SessionEnv): Con =
    if (s.cons.contains(c.name)) die("addCon: rebinding constructor " + c.name)
    else {
      s.cons = s.cons + (c.name -> c)
      c
    }

  def parse[A](p: Parser[A], ps: ParseState)(implicit su: Supply): (ParseState, A) =
    p.run(ps, su.split) match {
      case Left(err) => die(err.pretty) // TODO: preserve err.stack.reverse.map({case (p,s) => p.report(s).toString}) ++ ("parsing" :: xs))
      case Right(r)  => r
    }

  // @throws Death
  def acyclic(x: SourceFile, xs: List[SourceFile]) = if (xs.exists(_ == x)) {
    val cycle = (x :: (xs.takeWhile(_ != x) ++ List(x))).map(x => text(x.toString)).reverse
    die("error: circular dependency" above nest(2, fillSep(punctuate(" => ", cycle))))
  }

  // was HashMap with SynchronizedMap, which 2.13 removed
  val depCache = new java.util.concurrent.ConcurrentHashMap[SourceFile, (Long, Dep)]().asScala

  /* ------------------------------------------------------------------ *
   * S5.2 (`tracker/ROSE-COMPARISON.md` §3 rank 6): the SOLVER-CONFIGURATION KEY
   * ------------------------------------------------------------------ */

  /** The interface FORMAT version: bumped whenever the shape of a published
    * signature changes for a reason that is not a solver flag.
    *
    * `1` is reserved for the UNKEYED format every `.ei` written before stage S5
    * carries; there is no such file with a key, so a missing key is exactly a
    * version-1 file and is stale.  `2` is the first keyed format.
    *
    * A SOLVER FLAG does NOT need a bump -- it is in the fingerprint below, which is
    * the other half of the key.  S5.1's tautology deletion, for instance, rides in
    * as `+tauto` (`GenRules.tautoDelete`).  Bump this when the published form moves
    * for a reason the fingerprint cannot see: the pretty-printer, the sort order, the
    * header format itself. */
  val interfaceFormatVersion: Int = 2

  /** **What a published `.ei` is keyed by.**  `<format version>|<solver
    * configuration>`, where the configuration is `Constraints.GenRules.toString` --
    * the same fingerprint S2's layers and `DisjProbe` already use, e.g.
    * `2|cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+
    * pol:smallcanon+budget:20000+topnorm+tauto`.
    *
    * WHY.  Until now nothing tied a published interface to the rules that produced
    * it (the OPEN GAP recorded at `Constraints.scala`'s `dequeuePolicy`; A1 review
    * R-4, S4B review H-8), so a tree built partly at one configuration silently
    * mixed interfaces and every adoption needed a manual `find . -name '*.ei'
    * -delete`.  A mismatch is now treated exactly like a source change: the module
    * is fully rechecked and its interface rewritten.
    *
    * WHAT IS DELIBERATELY NOT IN IT.  Anything that cannot change the bytes of a
    * SUCCESSFULLY published interface:
    *   - `ermine.rowTrace` / `ermine.rowTrace.draws` -- pure instrumentation;
    *   - `ermine.foreign.tolerant` -- decides whether an unresolvable `foreign
    *     data` is a refusal or keeps its declared name; it changes whether a module
    *     loads, never the type published for one that does;
    *   - `ermine.typeCheck` and `ermine.useInterface` -- neither can WRITE a bad
    *     `.ei`: with `typeCheck=false` the module is answered by `untyped` and
    *     reaches `CheckMethod.Interface`, so `writeInterface` is never called, and
    *     with `useInterface=false` `Dep.writeInterfaceString` is the no-op;
    *   - `ermine.loadInSeries` -- a LOADER schedule, not a solver rule.  It does
    *     reach interface bytes (parallel makes draw `Supply` ids in thread-timing
    *     order), but only through the NAMES of published existentials: two sides
    *     differ as alpha-variants, which type-check identically and which the
    *     canonicaliser of `ROSE-COMPARISON.md` rank 3 is what actually removes.
    *     Keying on it would invalidate every interface an LSP session (parallel)
    *     wrote for a batch build (which may not be), for no soundness gain.
    *   - `ermine.rowSound.budget` and `ermine.rowSound.solveBudget` (spelt in full:
    *     `ermine.solveBudget` is a DIFFERENT property and IS in the key, as
    *     `+budget:20000`) -- a lapse in either means NO VERDICT, so they can change
    *     whether a module is REFUTED, never the bytes of one that is published.
    * The three `rowSound*` switches themselves, `genRules`, `disjunction`,
    * `labelCheck`, `labelCheckEarly`, `resGuard`, `splitKey`, `splitRow`, `resRow`,
    * `emptyRow`, `dequeuePolicy`, `solveBudget`, `topNormalise` and `tautoDelete`
    * ARE in it: they are `GenRules.toString`. */
  /** S3 (`SIG-ENTAIL-PLAN.md`): `sigEntail=error` CAN change what is published, by
    * REFUSING a module whose signature is not entailed, so a stale `.ei` written under
    * `off` would hide the diagnostic on the next run.  It is APPENDED rather than folded
    * in, and only in `error` mode, so the default-mode baseline of an `off` run stays
    * byte-identical to every interface written before S3.  The staleness test is
    * `key contains interfaceKey` below, and `key` is an `Option`, so that is EQUALITY: an
    * `.ei` written under one mode is rebuilt under the other, in both directions.
    *
    * S3 REVIEW D5, KNOWN AND LEFT: this reads the PROCESS default while the check reads the
    * SESSION mode (`SessionEnv.sigEntail`), so a session differing from the process default --
    * which is exactly what the session option exists to allow -- writes a key describing the
    * wrong mode.  Harmless today: no production path sets a per-session mode, and every test
    * fixture that does also sets `useInterface = false`, so nothing reads or writes an `.ei`
    * under a session mode.  The fix threads a `SessionEnv` into this `def`; S4 item
    * (`tracker/loopmodel/SIG-3-IMPL.md` §8).
    *
    * The `.2` (2026-10): the check now decides a partition with a literal column set on
    * its left, where it used to warn and accept.  A module it would now refuse may have an
    * `.ei` cached from before, so the suffix changed and those interfaces are rebuilt once.
    * Change the number again whenever the check starts refusing something it accepted. */
  def interfaceKey: String = interfaceFormatVersion.toString + "|" + Constraints.GenRules.toString +
    (if (SigEntail.defaultMode == SigEntail.Error) "|sigEntail=error.2" else "")

  /** The header line an `.ei` carries.  It LOOKS like an Ermine line comment, and
    * that is deliberate -- but do not rely on it: `InterfaceParsers` does not accept
    * one here (see `splitInterfaceKey`), so every reader must strip it. */
  private val interfaceKeyMarker = "-- ermine-interface "

  def interfaceHeader: String = interfaceKeyMarker + interfaceKey

  /** Split a `.ei` into (its key, if it carries one) and (its body).
    *
    * The header line is REMOVED, not blanked.  `InterfaceParsers.interfaceSigs` is a
    * `laidout` block parsed straight off the file with no `phrase` wrapper, and it
    * accepts neither a leading `--` comment nor a leading blank line -- measured, both
    * of them, with `G1Compare --pair`.  So the body handed to the parser is exactly the
    * bytes an unkeyed `.ei` had, and a parse error's line number is one less than the
    * file's; nothing surfaces that number (the failure is `_log.debug` and a full
    * recheck), so nothing depends on it.  Every reader of an `.ei` must go through
    * here: `Session.dep`'s `preCk` and `G1Compare.parseEi` are the two. */
  def splitInterfaceKey(s: String): (Option[String], String) = {
    val i = s.indexOf('\n')
    val first = if (i < 0) s else s.substring(0, i)
    if (first startsWith interfaceKeyMarker)
      (Some(first.substring(interfaceKeyMarker.length).trim),
       if (i < 0) "" else s.substring(i + 1))
    else (None, s)
  }

  sealed abstract class SourceFile extends scala.Product with Serializable {
    // @throws Death
    def contents: String
    def defaultModuleName: String
    /** Whether loaded from some non-`SourceFile.Loader` source. */
    def exotic: Boolean = false
    def lastModified: Option[Long]
    def interfaceContents: Option[String]
    def interfaceWriteback(s: String): Unit = ()
  }

  case class Filesystem(fileName: String, override val exotic: Boolean = false)
      extends SourceFile {
    private val file = new File(fileName)

    def exists = file.exists
    def lastModified = if (exists) Some(file.lastModified) else None
    def contents =
      if(file.exists) {
        val source = scala.io.Source.fromFile(fileName, "UTF-8")
        val str = source.mkString
        source.close
        str
      } else die("File '" + fileName + "' does not exist.")
    def defaultModuleName: String = {
      val path = fileName.split(separatorChar).toList
      val sections = path.filter(s => s.length > 0 && s.head.isUpper) match {
        case List() => path
        case l      => l
      }
      (sections.init ++ List(sections.last.split('.')(0))).mkString(".") // strip off any file extension
    }
    override def toString = fileName

    private val interfaceFileName =
      if(fileName.endsWith(".e")) fileName + "i"
      else fileName + ".ei"

    private def interfaceFile = new File(interfaceFileName)

    def interfaceContents =
      try {
        if (lastModified.map(interfaceFile.lastModified > _).getOrElse(false)) {
          val source = scala.io.Source.fromFile(interfaceFileName)
          val str = source.mkString
          source.close
          Some(str)
        } else None
      } catch {
        case e : java.io.IOException => None
      }

    override def interfaceWriteback(s: String) =
      try {
        val wr = new java.io.PrintWriter(interfaceFileName)
        wr.println(s)
        wr.close
      } catch {
        case e : java.io.IOException => ()
      }
  }

  /** An OPEN EDITOR BUFFER (roadmap 5.3): text the language server holds
    * for a file whose saved contents may be older, or which has never
    * been saved at all.
    *
    * Identity is content-bearing, and `lastModified` is the document
    * VERSION.  Both matter, because depCache is process-global and
    * mtime-guarded: keying off the module name the way Literal and
    * Dynamic do would let one editor's text replay into every other
    * session's load of that name, and serving a buffer through a
    * Filesystem dep would hand back the dep built from the SAVED text,
    * whose on-disk mtime does not move when the buffer changes.  That is
    * the poisoning class fixed at D0 and D3 part 3b; this subclass exists
    * so the editor path cannot re-open it. */
  case class Buffer(fileName: String, contents: String, version: Long) extends SourceFile {
    override def exotic = true
    def lastModified = Some(version)
    def defaultModuleName: String = Filesystem(fileName).defaultModuleName
    def interfaceContents = None
    // toString is the FILE NAME threaded into parse states and every Pos
    // built from them: decorating it would break the "file:line:col:"
    // contract the Diagnostics regex and definition locations rest on.
    override def toString = fileName
  }

  case class Resource(module: String, url: URL) extends SourceFile {
    def contents = {
      val source = scala.io.Source.fromURL(url, "UTF-8")
      val str = source.mkString
      source.close
      str
    }
    def defaultModuleName: String = module
    def lastModified = Some(0)
    override def toString = url.toString

    private val interfaceURL = {
      val str = url.toString
      if (str endsWith ".e") Some(new URL(str + "i"))
      else None
    }

    def interfaceContents = interfaceURL flatMap { u =>
      try {
        val source = scala.io.Source.fromURL(u, "UTF-8")
        val str = source.mkString
        source.close
        Some(str)
      } catch {
        case e : java.io.IOException => None
      }
    }
  }

  case class Literal(contents: String, defaultModuleName: String) extends SourceFile {
    def lastModified = Some(0)
    override def toString = defaultModuleName |+| "<dynamic>"
    // depCache and others expect comparison to key off the module
    // name.  SourceFile originally only contained comparable
    // elements, but at some point this became untrue.  TODO: separate
    // the identifying component from the magic contents
    override def hashCode = defaultModuleName.##
    override def equals(o: Any) = o match {
      case o@Literal(_, dmn) if o canEqual this => dmn == defaultModuleName
      case _ => false
    }
    def interfaceContents = None
  }

  // like a literal, but contents can change
  case class Dynamic(_contents: () => String, _lastModified: () => Option[Long], defaultModuleName: String) extends SourceFile {
    def lastModified = _lastModified()
    def contents = _contents()
    // depCache and others expect comparison to key off the module
    // name.  SourceFile originally only contained comparable
    // elements, but at some point this became untrue.  TODO: separate
    // the identifying component from the magic contents
    override def hashCode = defaultModuleName.##
    override def equals(o: Any) = o match {
      case o@Dynamic(_, _, dmn) if o canEqual this => dmn == defaultModuleName
      case _ => false
    }
    def interfaceContents = None
  }

  case class NotFound(module: String) extends SourceFile {
    def contents = die("Module not found: '" + module + "'")
    def defaultModuleName: String = module
    def lastModified = None
    def interfaceContents = None
  }

  object SourceFile {
    type ALoader[-A] = A => Option[SourceFile]
    type Loader = ALoader[String]

    /** Search subloaders in order. */
    def inOrder[A](ls: ALoader[A]*): ALoader[A] =
      s => (ls.view map (_(s)) find (_ isDefined) join)

    /** Load from arbitrary filesystem location.
      *
      * @param root Filepath to Ermine module location.
      */
    def filesystem(root: String)(module: String): Option[SourceFile] = {
      val fileName = (root :: hierarchy(module)).mkString(separator) + ".e"
      if (new File(fileName) exists) Some(Filesystem(fileName))
      else None
    }

    /** Load from Java classloader, rooted at `root`. */
    def classloader(root: String = "modules")(module: String): Option[SourceFile] = {
      val path = (root :: hierarchy(module)).mkString("/") + ".e"
      Option(classOf[Resource].getClassLoader.getResource(path)) map {url =>
        if (Option(url.getProtocol) cata ("file".equalsIgnoreCase, false))
          Filesystem(new File(url.toURI.getPath).getPath)
        else Resource(module, url)
      }
    }

    /** Standard module loading rules. */
    def defaultLoader: Loader = classloader()

    private[SourceFile] def hierarchy(module: String): List[String] =
      module.split('.').toList

    private[Session] def forModule(module: String)(implicit s: SessionEnv): SourceFile =
      s.loadFile(module) | NotFound(module)

    // evil
    private[Session] def cache(sf: SourceFile, d: Dep): Dep = {
      sf.lastModified foreach (t => depCache += (sf -> (t, d)))
      d
    }

    private[Session] def cached(sf: SourceFile): Option[Dep] = for {
      lmd <- depCache get sf
      (lm, d) = lmd
      newTime <- sf.lastModified
      if newTime == lm
    } yield d

    private def sourceFileTypeScore(sf: SourceFile) = sf match {
      case _: Filesystem => 0
      case _: Buffer => 5
      case _: Resource => 10
      case _: Literal => 20
      case _: NotFound => 30
      case _: Dynamic => 40
      // update sourceFileOrdering if you add more here
    }

    implicit def sourceFileOrdering: Ordering[SourceFile] = new Ordering[SourceFile] {
      def compare(x: SourceFile, y: SourceFile) =
        (x, y, sourceFileTypeScore(x) - sourceFileTypeScore(y)) match {
          case (_, _, n) if n /== 0                => n
          case (Filesystem(fn1, e1),  Filesystem(fn2, e2),  _) =>
            Ordering[(String, Boolean)].compare((fn1,e1),(fn2,e2))
          case (Buffer(fn1, _, v1), Buffer(fn2, _, v2), _) =>
            Ordering[(String, Long)].compare((fn1,v1),(fn2,v2))
          case (Resource(m1, u1), Resource(m2,u2),  _) =>
            Ordering[(String,String)].compare((m1,u1.toString), (m2,u2.toString))
          case (Literal(s1, mn1), Literal(s2, mn2), _) =>
            Ordering[(String,String)].compare((s1, mn1), (s2, mn2))
          case (NotFound(s1),     NotFound(s2),     _) =>
            Ordering[String].compare(s1,s2)
          case (Dynamic(_,_,mn1), Dynamic(_,_,mn2), _) =>
            Ordering[String].compare(mn1,mn2)
          case (_, _, _) => sys.error(s"missing case: $x, $y")
      }
    }
  }

  private def cacheDep(file: SourceFile, making: List[SourceFile], expectedName: Option[String])(p: => Dep): Dep = {
    SourceFile.cached(file) match {
      case Some(d) => d copy (making = making, expectedName = expectedName)
      case None    => SourceFile.cache(file, p)
    }
  }

  private val all: (Option[String],List[Explicit[Global]],Boolean) = (None, List(), false)

  /**
   * Used when running in untyped mode. Answers the question of, 'do we know
   * the type of this variable,' always in the affirmative, with type
   * 'forall a. a'.
   */
  private def untyped(implicit su: Supply): PartialFunction[TermVar, TermVar] = {
    case v =>
        val a = fresh(v.loc, None, Bound, Star(v.loc))
        v.as(Forall(v.loc, List(), List(a), Exists.unit, VarT(a)))
    }

  def dep(file: SourceFile, making: List[SourceFile] = Nil, expectedName: Option[String] = None)(implicit s: SessionEnv, su: Supply): Dep = {
    acyclic(file, making)
    cacheDep(file, file :: making, expectedName) {
      val start = nanoTime
      val (ps, mh) = parse(moduleHeader(file.defaultModuleName), ErParseState.mk(file.toString, file.contents, file.defaultModuleName))
      val mhParse = nanoTime
      val expTys = mh.importExports.flatMap { ie => ie.explicits.collect { case e if e.isType => e.global } }
      val expTms = mh.importExports.flatMap { ie => ie.explicits.collect { case e if !e.isType => e.global } }
      val exports = nanoTime
      // ALWAYS the real interface-reading closure: deps are cached
      // process-wide and outlive this session — typeCheck/useInterface
      // gate at CALL time in make, with the live session (a dep cached
      // by a useInterface=false suite must not poison a =true one)
      val preCk : (Map[Global,Type.Con], Supply, ParseState) => Option[PartialFunction[TermVar,TermVar]] =
        (gcs, su, ps) => file.interfaceContents flatMap { intf =>
           /* S5.2: the SOLVER-CONFIGURATION KEY, checked on the same path that
            * already decides currency -- `interfaceContents` has just answered the
            * mtime question and the parse below answers the well-formedness one.
            * A key that does not match the running configuration, or a file with
            * no key at all (every `.ei` written before stage S5), is STALE in
            * exactly the sense a newer source is: `None` here means a full check,
            * and the full check rewrites the file with the current key. */
           val (key, body) = splitInterfaceKey(intf)
           if (!(key contains interfaceKey)) {
             _log.debug("Interface for '" + file + "' was written at a different solver " +
                        "configuration (" + (key getOrElse "<unkeyed>") + " vs " +
                        interfaceKey + "); rechecking")
             None
           } else {
             _log.trace("Interface contents: " + body)
             val newPs =
               scalaparsers.ParseState.mk(file.toString + "i", body, ps.s.copy(recognizedCons = gcs))
             interfaceFile.run(newPs,su.split) match {
               case Left(err) =>
                 _log.debug("Error parsing interface file:")
                 _log.debug(err)
                 None
               case Right((_,pf)) => Some(pf)
             }
           }
        }

      profile(file.defaultModuleName + " dep", start, "header parse" -> mhParse, "export handling" -> exports)
      Dep(
        mh.loc,
        file,
        expectedName,
        mh.name,
        mh.importExports.map(_.module).toSet,
        file :: making,
        (s, su) => s.loadedFiles.get(file) match {
          case Some(_) => None // we were already loaded
          case None    =>
            val before = nanoTime
            // post-G1 D3: the split pipeline (parse -> rename ->
            // reassociate -> lower) is the only module reader; the
            // fused moduleBody path is retired
            val r = com.clarifi.reporting.ermine.rename.NewPipeline.readModule(
              file.toString, file.contents, mh)(s, su)
            val after = nanoTime
            profile(mh.name + " parse module", before, "parsed" -> after)
            Some(r)
        },
        expTys,
        expTms,
        preCk,
        if (s.useInterface) file.interfaceWriteback else (_ => ())
      )
    }
  }

  type ModuleName = String
  type FileName = String

  def depsPrime(
    mods: Set[ModuleName], // loadedModules
    files: Map[SourceFile, ModuleName], // loadedFiles
    tick: Int = 0
  )(ds: List[Dep])(implicit s: SessionEnv, su: Supply): List[Dep] = {
    val m = ds.flatMap(d => d.imports.map((_,d.making))).toMap -- mods
    if (m.isEmpty) Nil
    else {
      val nds = m.toList.map {
        case (mn,making) => fork {
          case (sp, sup) => dep(SourceFile.forModule(mn), making, Some(mn))(sp, sup)
        }
      }
      val ndsp = joins(nds)
      ndsp ++ depsPrime(mods, files, tick + 1)(ndsp)
    }
  }

  // @throws Death
  def deps(modules: Set[String])(implicit s: SessionEnv, su: Supply): List[Dep] = {
    val ds = modules.map(m => dep(SourceFile.forModule(m), List(), Some(m))).toList
    ds ++ depsPrime(s.loadedModules.keySet, s.loadedFiles)(ds)
  }

  case class Dep(
    loc: Loc,
    file: SourceFile,
    expectedName: Option[String],
    moduleName: String,
    imports: Set[String],
    making: List[SourceFile],
    read: (SessionEnv, Supply) => Option[(ParseState, Module)],
    typeReqs: List[Global],
    termReqs: List[Global],
    readInterface: (Map[Global,Type.Con], Supply, ParseState) => Option[PartialFunction[TermVar, TermVar]],
    writeInterfaceString: String => Unit
  ) extends Located {
    private def writeInterface(defs: List[TermVar]): Unit = {
      val w = new java.io.StringWriter()
      // Sorted by name so interface bytes do not depend on HashMap-over-id
      // iteration order (ids are timing-dependent across runs); parse-back
      // is order-insensitive (InterfaceParsers sigs.toMap).  G1 oracle,
      // tracker/LSP-ROADMAP.md item 1.1.
      val sorted = defs.sortBy(_.name.map(_.toString) getOrElse "")
      vsep(sorted.map(Pretty.prettyVarHasType(_, Pretty.FullyQualified))).format(1000000, w)
      // S5.2: the solver-configuration key, as the FIRST line and above the sorted
      // signatures, which are left exactly as they were.
      writeInterfaceString(interfaceHeader + "\n" + w.toString)
    }

    def --(xs: Traversable[String]) = copy(imports = imports -- xs)
    // @throws Death
    def make(implicit s: SessionEnv, su: Supply): Unit = {
      checkNames
      read(s,su) match {
        case None => ()
        case Some((ps, m)) =>
          def preChecked(lcs: Map[Global,Type.Con]) =
            if (!s.typeCheck) Some(untyped)
            else if (!s.useInterface) None
            else if(imports.forall(im => s.loadedModules.get(im) == Some(CheckMethod.Interface)))
              readInterface(s.cons ++ s.privateCons ++ lcs, su, ps)
            else {
              _log.debug("Rechecking '" + moduleName + "' due to lack of (valid) interface for dependency")
              None
            }
          val (tc, _) = loadModule(ps, m, preChecked, writeInterface)
          s.loadedFiles = s.loadedFiles + (file -> m.name)
          s.loadedModules = s.loadedModules + (m.name -> tc)
      }
    }
    // @throws Death
    def checkNames(implicit s: SessionEnv): Unit = {
      for (n <- expectedName)
        if (moduleName != n)
          loc.die("expected a module named " + n)
      for (g <- typeReqs)
        if (!s.cons.contains(g))
          loc.die("Module '" + g.module + "' does not export type '" + g.string + "'.")
      for (g <- termReqs)
        if (!s.termNames.contains(g))
          loc.die("Module '" + g.module + "' does not export term '" + g.string + "'.")
    }
  }

  val percentFmt = new DecimalFormat("##0")
  val secFmt = new DecimalFormat("0.00")

  private def barP(k: Int, n: Int, t0: Long)(implicit con: Printer) =
    if (n == k) say(" " * (n + 13) + "\r")
    else say("[" + ("=" * k) + ("." * (n - k)) + "] " +
      percentFmt.format((k * 100.0) / n) + "% " +
      secFmt.format((nanoTime - t0)/1000000000.0) + "s\r")

  private def bar(k: Int, n: Int, t0: Long)(implicit con: Printer) =
    if (n >= 66) barP(k * 66 / n, 66, t0)
    else if (n >= 0) barP(k,n, t0)

  def loadMore(
    k: Int,
    n: Int,
    t0: Long,
    ds: Map[String, Dep],
    cps: Map[String,Set[String]],
    latches: Map[String, Int],
    zs: Set[String],
    tick: Int = 0
  )(implicit s: SessionEnv, su: Supply, con: Printer): Unit =
    if (zs.isEmpty) bar(n,n,t0)
    else {
      val ((ls, nzs), makes) = mapAccum((latches, Set[String]()), zs.toList) {
        case ((ls,nzs), z) =>
          val a = ds.get(z) match {
            case Some(dsz) =>
               // sayLn("Loading " + z + " in pass " + tick)
               fork { (sp,sup) => dsz.make(sp,sup) }
            case None => die("Can't load " + z)
          }
          ( cps.get(z) match {
              case None => (ls, nzs)
              case Some(ps) => ps.foldLeft((ls,nzs)) {
                case ((ls,nzs),p) =>
                  ls.get(p) match {
                    case Some(lsp) =>
                      if (lsp == 1)   (ls - p, nzs + p)
                      else (ls + (p -> (lsp - 1)), nzs)
                    case None => (ls, nzs)
                  }
              }
          }, a)
      }
      joins(makes)
      val nk = k + makes.length
      bar(nk,n,t0)
      loadMore(nk, n, t0, ds, cps, ls, nzs, tick + 1)
    }

  def loadModules(moduleNames: List[String])(implicit s: SessionEnv, su: Supply, con: Printer): Set[String] = {
    // The G1 oracle needs deterministic fresh-id draws: parallel makes give
    // thread-timing-dependent Supply order, which reaches interface bytes
    // through the constraint solver's id-hash queue (item 1.1).  Default off.
    if (java.lang.Boolean.getBoolean("ermine.loadInSeries")) {
      loadModulesInSeries(moduleNames)
      return moduleNames.toSet
    }
    val x = first
    val t0 = nanoTime
    val loaded = s.loadedModules.keySet
    val ds = deps(moduleNames.toSet &~ loaded).map(_ -- loaded)
    val needed = ds.map(_.moduleName).toSet &~ loaded
    val n = needed.size
    if (n == 0) Set[String]()
    else {
      info("Loading " + nest(2, oxford("and", needed.toList.sorted.map(text))))
      bar(0,n,t0)
      val cps = ds.foldLeft(Map[String, Set[String]]()) {
        (m,d) => d.imports.foldLeft(m) {
          case (m,c) => m + (c -> (m.getOrElse(c, Set()) + d.moduleName))
        }
      }
      val (zs,nzs) = ds.partition(_.imports.isEmpty)
      val latches = nzs.map(d => d.moduleName -> d.imports.size).toMap
      try {
        loadMore(
          0,
          n,
          t0,
          ds.map(d => d.moduleName -> d).toMap,
          cps,
          latches,
          zs.map(_.moduleName).toSet
        )
      } catch {
        case e: Exception =>
          say("\n")
          throw e
      }
      needed
    }
  }

  def loadModulesInSeries(moduleNames: List[String])(implicit s: SessionEnv, su: Supply, con: Printer) =
    for (m <- moduleNames) load(SourceFile.forModule(m), Some(m))

  /** A `.e` path as the loader names it: absolute and normalized.
    *
    * MOVED here from `lsp.Resident` (WP-4 review S5), unchanged, so that
    * `json.Runner.invalidate` -- which is `bin/ermine-serve`'s class, not the
    * language server's -- can name a loaded file the same way the resident
    * does without the `json` package importing `lsp`.  `Resident.normalize`
    * and `Resident.moduleUnder` forward here, so every existing caller and
    * every `Resident.…` reference in the design documents still resolves. */
  def normalize(fileName: String): java.nio.file.Path =
    java.nio.file.Paths.get(fileName).toAbsolutePath.normalize
  def normalize(p: java.nio.file.Path): java.nio.file.Path = p.toAbsolutePath.normalize

  /** The module name a `.e` path spells under one of `roots` (`<root>/A/B.e`
    * is `A.B`), if it is under one.  MOVED from `lsp.Resident` (S5). */
  def moduleUnder(roots: List[String], p: java.nio.file.Path): Option[String] =
    roots.iterator.map(java.nio.file.Paths.get(_)).map(normalize).collectFirst {
      case r if p.startsWith(r) && p.toString.endsWith(".e") =>
        val rel = r.relativize(p).toString
        rel.substring(0, rel.length - 2).replace(separatorChar, '.')
    }

  /** Where `env` read each of its modules from, by normalized path -- the
    * half of a file-change event that a session can answer for itself.
    * MOVED from `lsp.Resident`'s private copy (S5), which took the env as a
    * parameter and touched no resident state; `Resident.reload` and
    * `Runner.invalidate` are its two callers.
    *
    * The caller owns `env`; this locks nothing (the resident: the dispatch
    * thread; `Runner.invalidate`: under `evalLock`). */
  def loadedByPath(env: SessionEnv): Map[java.nio.file.Path, String] =
    env.loadedFiles.toList.collect {
      case (Session.Filesystem(f, _), m) => normalize(f) -> m
    }.toMap

  /** `roots` plus every loaded module that imports one of them, transitively.
    * The import sets come from the dependency cache the loads filled, keyed
    * by the very SourceFiles `loadedFiles` holds.
    *
    * Lifted out of `lsp.Resident` (WP-2) so a second session -- the widget
    * preview's render session -- can compute the same closure over its own
    * `loadedFiles` without going through the resident.
    *
    * The caller owns `env`; this locks nothing.  A `SessionEnv` is mutable
    * and not thread-safe, so the calling thread must be the only one using
    * that env while this runs (the resident: the dispatch loop; WP-4's
    * `Runner.invalidate`: under `evalLock`). */
  def dependentsOf(env: SessionEnv, roots: Set[String]): Set[String] = {
    val imports: Map[String, Set[String]] = env.loadedFiles.toList.flatMap {
      case (sf, m) => Session.depCache.get(sf).map { case (_, d) => m -> d.imports }
    }.toMap
    var seen     = roots
    var frontier = roots
    while (frontier.nonEmpty) {
      val next = imports.collect { case (m, is) if !seen(m) && (is & frontier).nonEmpty => m }.toSet
      seen ++= next
      frontier = next
    }
    seen
  }

  /** Scrub `modules` out of `e` down to their builtin state, `builtins`
    * being the env as it stands after that session's own `Lib.preamble`
    * and BEFORE any module is read.  Only what the SOURCE declares goes:
    * `Lib` installs builtins under the module they belong to -- `asOp` and
    * class `AsOp` are `Global("Relation.Op", ...)`, declared in Scala and
    * merely COMMENTED in `Relation/Op.e` -- so a scrub by module name alone
    * would delete them and re-reading the file could not put them back.
    * `reloadChangedModules` below guards its own scrub the same way, against
    * the "lib" session it takes as its `builtinEnv` parameter; this mirrors
    * it.
    *
    * A wrong `builtins` fails SILENTLY, not loudly: pass `e` itself, or a
    * snapshot taken after modules were read, and every `b.<table>.contains` guard
    * is true, so nothing is removed from `env`, `termNames`, `cons` or the
    * rest -- only `loadedFiles` and `loadedModules` shrink, and the stale
    * names stay in scope.  Doc, not a `require`: `builtins` must be the
    * post-`Lib.preamble`, pre-load snapshot of the SAME session as `e`.
    *
    * The caller owns `e`; this locks nothing.  A `SessionEnv` is mutable and
    * not thread-safe, so the calling thread must be the only one using that
    * env while this runs (the resident: the dispatch loop; WP-4's
    * `Runner.invalidate`: under `evalLock`).
    *
    * Lifted out of `lsp.Resident` (WP-2), which passes its own post-preamble
    * snapshot: it scrubs per check on the module being checked (on the copy)
    * and on the resident env when a reload runs.
    *
    * WP-25 (`tracker/JSON-WIDGET-PLAYGROUND.md` §14, §13 Q20): ANY SET IS
    * SAFE TO UNLOAD.  `scrub` used to rely, unchecked, on its caller
    * handing it a set CLOSED UNDER IMPORTERS: `e.env` goes by each `V`'s
    * OWN defining module while every name table goes by the KEY's module,
    * so a set holding a DEFINER but not its RE-EXPORTERS deleted
    * `Control.Functor.Functor` from `env` and left `Control.Monad.Functor`
    * naming it -- and the next read of a module whose spelling collapses to
    * the origin died in `Subst.assertTermClosed` with `undefined term`
    * inside a stdlib file.  It now closes the set over re-exporters itself
    * (`reExportClosure`) and repairs the re-export chains a scrub cuts
    * (`reorigin`).
    *
    * WHAT "SAFE" MEANS HERE, exactly: afterwards **no name outlives the
    * entity it names, and any module can be read** -- a spelling resolves to
    * what it would resolve to on a session where these modules were never
    * loaded, or fails to resolve out loud.  It does **NOT** mean "not
    * stale".  A surviving module that merely IMPORTS a scrubbed one keeps
    * its own values and its own `Type.Con`s, and a `Con` carries the `decl`
    * it was built with (`Type.Con.equals` compares only the name, so nothing
    * fails to unify, but `Pattern.scala:139,159` read that `decl`).  Making
    * a session not stale is the CALLER's question and the reason
    * `dependentsOf` exists; this method does not answer it.  Likewise the
    * process-wide constructor registry (`DataConDecl.register`) has no
    * `unregister` and `scrub` leaves it untouched, as it always has.
    *
    * THE RETURN VALUE is the set it scrubbed BY: `modules` unioned with the
    * closure, hence a SUPERSET of the argument.  It is **not** "what left
    * `loadedModules`" -- a module the caller names but this session never
    * loaded comes back in the result with nothing to show for it, and a
    * second scrub of an already-unloaded module returns it again.
    * Intersect with the caller's pre-scrub `loadedModules` for what actually
    * left.  **A caller that reloads must reload the RETURNED set**, not the
    * one it passed; a caller that only wanted the module out of a throwaway
    * copy (`lsp.Resident.checkFile`) may ignore it.  Pinned by `TestScrub`. */
  def scrub(e: SessionEnv, builtins: SessionEnv, modules: Set[String]): Set[String] = {
    val b  = builtins
    val ms = reExportClosure(e, b, modules)
    def mine(g: Global) = ms(g.module)
    e.env = e.env filter { case (v, _) => v.name match {
      case Some(g: Global) => !mine(g) || b.env.contains(v)
      case _               => true
    } }
    e.termNames       = e.termNames       filterNot { case (g, _) => mine(g) && !b.termNames.contains(g) }
    e.cons            = e.cons            filterNot { case (g, _) => mine(g) && !b.cons.contains(g) }
    e.privateCons     = e.privateCons     filterNot { case (g, _) => mine(g) && !b.privateCons.contains(g) }
    e.classes         = e.classes         filterNot { case (g, _) => mine(g) && !b.classes.contains(g) }
    // DEAD BY CONSTRUCTION (WP-25 review N4): no source-level `instance`
    // statement exists -- `instance` is in `parsing/package.scala`'s
    // `startingKeywords` and no parser consumes it -- so `s.classes` is
    // written only by `loadModule` below and by `Lib`, always under the
    // class's OWN name, and `classOrigins` has NO writer anywhere in the
    // repo.  Both lines are kept for the day one appears; neither has ever
    // removed an entry.
    e.classOrigins    = e.classOrigins    filterNot { case (g, _) => mine(g) && !b.classOrigins.contains(g) }
    e.loadedFiles     = e.loadedFiles     filterNot { case (_, n) => ms(n) }
    e.loadedModules   = e.loadedModules -- ms

    // THE NET.  `reExportClosure` only widens to modules this session has
    // LOADED, because a module it never loaded cannot be unloaded and
    // cannot be read back.  If such a module's key named something that
    // went, dropping the key is the only honest move left.  MEASURED to
    // remove NOTHING on the stdlib -- every key whose module is outside
    // `loadedModules` (`Double`, `Field`, `IO.Unsafe`, `Native.Function`,
    // `Layout.Presentation`, ...) is a BUILTIN, and builtins never leave
    // `env` -- so this is a net under the closure and not the mechanism.
    // The `forall` decides without allocating when there is nothing to do.
    def net[K, A](m: Map[K, A])(ok: ((K, A)) => Boolean): Map[K, A] =
      if (m forall ok) m else m filter ok
    e.termNames   = net(e.termNames)  { case (_, v) => e.env.contains(v) }
    e.cons        = net(e.cons)       { case (_, c) => e.cons.contains(c.name) }
    e.privateCons = net(e.privateCons){ case (_, c) => e.cons.contains(c.name) || e.privateCons.contains(c.name) }
    e.classes     = net(e.classes)    { case (_, c) => e.classes.contains(c.name) }

    // THE `*Origins` TABLES, LAST, because they are repaired against the
    // names that survived above.  See `reorigin`.
    e.termNameOrigins = reorigin(e.termNameOrigins, b.termNameOrigins, ms, mine, e.termNames.contains)
    e.consOrigins     = reorigin(e.consOrigins, b.consOrigins, ms, mine,
                                 g => e.cons.contains(g) || e.privateCons.contains(g))
    ms
  }

  /** WP-25, round 2: the `*Origins` half, and it is a REPAIR rather than a
    * deletion.
    *
    * `termNameOrigins`/`consOrigins` are name->NAME: `Prelude.Nil#` records
    * that `Prelude` imported the spelling from `Native`, and `Native.Nil#`
    * records that `Native` imported it from `Native.List`.
    * `ModuleScope.collapseNames` walks that chain to its GREATEST ANCESTOR
    * whenever a module reaches one spelling by two or more import paths, and
    * `Renamer.resolveGlobal` (`rename/Renamer.scala:158-164`) resolves ONLY a
    * one-element answer -- it compares NAMES, not entities, and calls
    * anything else `Ambiguous`, which `Lower.varFor` turns into a placeholder
    * and `assertTermClosed` into `undefined term`.
    *
    * So scrubbing a module that is a re-exporting INTERMEDIATE breaks the
    * chain in the MIDDLE: the link `Native.Nil# -> Native.List.Nil#` goes,
    * the walk stops at the dead `Native.Nil#`, and a module importing both
    * `Prelude` and `Native.List` -- which reads fine on a whole session --
    * gets two names where it used to get one and dies.  `reExportClosure`
    * cannot prevent this: it reasons about ENTITY ownership, and
    * `Prelude.Nil#`'s entity is `Native.List`'s (the definer), so `Prelude`
    * correctly stays loaded while the NAME-level edge through `Native` is
    * cut.  MEASURED on the resident's 130-module session: a scrub of
    * `{Native}` changes the walk's answer for **111** live names, and
    * `module T where import Prelude; import Native.List; t = Nil#` then dies
    * with `undefined term` where it loads clean on the unscrubbed session
    * (`scratchpad/wp25-splice.log`).
    *
    * WHAT THIS DOES: for every key that is STILL A NAME and that points at a
    * scrubbed name, replace that ancestor by ITS OWN greatest ancestors,
    * computed over the table AS IT WAS BEFORE this scrub -- so the walk
    * reaches exactly the name it reached before.  MEASURED: 111 changed
    * answers -> 0.
    *
    * WHAT IT DELIBERATELY DOES NOT DO: it does not remove a dead ancestor
    * that IS a greatest ancestor.  `Relation.append` names both
    * `Relation.Row.append` and `Relation.Sort.append`; scrubbing
    * `Relation.Row` leaves the first dead, and the spelling stays ambiguous
    * -- which is what it was BEFORE the scrub too (MEASURED: that module
    * dies identically on an unscrubbed session).  Deleting the entry, or
    * filtering the dead name out of it, were both measured: deleting leaves
    * the real failure above untouched while making the table look clean, and
    * filtering turns a legitimately ambiguous spelling into a resolvable one.
    * Neither is the walk a fresh load performs; this is.
    *
    * IT IS THE ONE PART THAT DOES NOT SELF-HEAL (review N5).  A repaired
    * entry belongs to a module that was NOT scrubbed, so reloading the
    * scrubbed module does not rewrite it: after `{Native}` is loaded back,
    * `Prelude.Nil#` still records `Native.List.Nil#` where a fresh load
    * records `Native.Nil#`.  That is walk-equivalent -- the greatest
    * ancestor is the same either way, and the witness reads -- and the entry
    * is rewritten when `Prelude` itself is next read.  MEASURED by the
    * WP-25 review: 0 walk movement and the witness OK after the reload.
    *
    * WHAT IT CANNOT KEEP, stated because it is a real limitation and not an
    * oversight: `lsp/Definitions.canonWith` chases only SINGLE-element
    * entries and stops at a multi-element one, so where a dead ancestor had
    * two greatest ancestors the repaired entry becomes two-element and that
    * chase stops one step early, at a different LIVE name.  No value can
    * prevent it: the answer it used to give was the dead name itself.
    * MEASURED on the 130-module session: exactly **2** of 3 701 names in
    * scope (`Prelude.head#`, `Prelude.tail#`, whose `Native.head#`/
    * `Native.tail#` each have two greatest ancestors), **0** for every
    * importer-closed set, and **0 buckets split** in every shape measured.
    * Pinned by `TestScrub`.
    *
    * COST: one pass, fused with the module filter this replaces, and the
    * patch is `kept ++ fix` over the handful of repaired entries rather than
    * a rebuild of the 16 000-entry map.  For a set that is CLOSED UNDER
    * IMPORTERS -- every product caller with intact dependency edges -- it
    * repairs nothing at all, because a key whose ancestor was scrubbed is
    * then itself scrubbed (MEASURED: 0 repairs on `dependentsOf` of
    * `Maybe`, `Native` and `Control.Functor`). */
  private def reorigin(m: Map[Global, List[Global]], bm: Map[Global, List[Global]],
                       ms: Set[String], mine: Global => Boolean,
                       live: Global => Boolean): Map[Global, List[Global]] = {
    val anc = greatestAncestors(m)          // over the PRE-scrub table
    def cut(g: Global, o: Global) = o != g && ms(o.module) && !live(o)
    var fix = Map.empty[Global, List[Global]]
    val kept = m filter { case (g, os) =>
      if (mine(g) && !bm.contains(g)) false
      else {
        // `ms(o.module)` first: it is a lookup in a set of a few strings and
        // it is false for almost every origin, so the two map lookups run
        // only for the entries that could possibly need a repair
        if (os.exists(cut(g, _)) && live(g)) {
          val spliced = os.flatMap(o => if (cut(g, o)) anc(o) else List(o)).distinct
          if (spliced != os) fix += g -> spliced
        }
        true
      }
    }
    if (fix.isEmpty) kept else kept ++ fix
  }

  /** `ModuleScope.collapseNames`' own greatest-ancestor walk, memoised, over
    * a given origins table.  The depth cap is `Definitions.canonWith`'s: the
    * real chains are two or three long, and a cap is cheaper than proving the
    * table acyclic.
    *
    * THE MEMO IS KEYED BY `g` ALONE, not by `(g, depth)` (review N6).  That
    * is sound while the table is ACYCLIC, which the import graph makes it
    * (`Session.acyclic`): every chain then reaches its greatest ancestors
    * well inside the cap, so the depth a name is first reached at cannot
    * change its answer.  Over a table with a cycle the walk still
    * TERMINATES -- the cap sees to that, and the review measured a real
    * scrub over an injected 2-cycle at 4.4 ms -- but the answer would then
    * depend on iteration order. */
  private def greatestAncestors(m: Map[Global, List[Global]]): Global => List[Global] = {
    val memo = scala.collection.mutable.HashMap.empty[Global, List[Global]]
    def go(g: Global, d: Int): List[Global] = memo.get(g) match {
      case Some(r) => r
      case None =>
        val up = m.getOrElse(g, List(g))
        val r  = if (d <= 0 || up == List(g)) List(g) else up.flatMap(go(_, d - 1)).distinct
        memo.put(g, r)
        r
    }
    go(_, 32)
  }

  /** WP-25: `modules` closed over RE-EXPORTERS -- the set `scrub` must
    * actually unload if `modules` is to be safe.
    *
    * A module RE-EXPORTS when one of its name keys holds an entity that
    * belongs to ANOTHER module: `Control.Monad.Functor` is a key under
    * `Control.Monad` whose `V` is `Control.Functor`'s, because `export`
    * aliases the ORIGIN's entity rather than minting a new one.  Unloading
    * the definer alone deletes that `V` from `env` -- the `env` filter goes
    * by the `V`'s own module -- and leaves the re-exporter's key naming it.
    *
    * WHY THE CLOSURE AND NOT A DROP, since dropping the dangling keys is
    * the smaller change and was the first proposal: MEASURED to be WORSE.
    * The spelling then leaves scope while its re-exporter stays in
    * `loadedFiles` LOOKING LOADED, so `loadModules` will not read it back
    * (`-- loaded`), and the next module that imports only the re-exporter
    * cannot find the name.  Over the 30 seeded subsets of `TestScrub` the
    * drop turned 0 reload failures into 8, and ROBUST-3's own reproduction
    * (`{Control.Functor, Maybe}`) still died with the same message.
    *
    * IT IS NOT THE IMPORTER CLOSURE, and must not be.  A module that
    * merely USES a name it does not re-export keeps its own values and
    * dangles nothing; it is STALE, which is the CALLER's question
    * (`dependentsOf`) and not this one.  That difference is what keeps the
    * editor path affordable: over the resident's 130-module session the
    * re-export closure of one module is at most 6 modules and 1.8 on
    * average, where the importer closure reaches 96 and averages 25.8
    * (MEASURED, `scratchpad/wp25-cost.log`).
    *
    * Computed from THIS SESSION's own tables -- never `Session.depCache`,
    * which is process-global and which WP-26 says can lose edges under the
    * resident.  Linear in the tables per round; the rounds are bounded by
    * the length of a re-export chain (2 on the stdlib). */
  private def reExportClosure(e: SessionEnv, b: SessionEnv, modules: Set[String]): Set[String] = {
    var ms   = modules
    var grew = true
    while (grew) {
      var add = Set.empty[String]
      // a key under `km` naming an entity of `om`: `km` must go too --
      // unless the entity is a BUILTIN (those never leave `env`, so the
      // key never dangles) or `km` is not loaded (see THE NET above).
      // `builtin` is BY NAME and tested LAST (review N3): it is a map
      // lookup, and `ms(om)` is false for almost every one of the ~3 700
      // entries this runs over on every round.
      def consider(km: String, om: String, builtin: => Boolean): Unit =
        if (ms(om) && !ms(km) && !add(km) && e.loadedModules.contains(km) && !builtin) add += km
      e.termNames foreach { case (g, v) => v.name match {
        case Some(o: Global) => consider(g.module, o.module, b.env.contains(v))
        case _               => ()
      } }
      e.cons        foreach { case (g, c) => consider(g.module, c.name.module, b.cons.contains(c.name)) }
      e.privateCons foreach { case (g, c) => consider(g.module, c.name.module, b.privateCons.contains(c.name)) }
      e.classes     foreach { case (g, c) => consider(g.module, c.name.module, b.classes.contains(c.name)) }
      grew = add.nonEmpty
      ms   = ms ++ add
    }
    ms
  }

  /** REPL :reload in a box.
    *
    * @param builtinEnv A "lib" session containing loaded builtins,
    *        such as from `Lib.preamble`.  Must be passed because we
    *        cannot reproduce those terms &c by merely loading Ermine
    *        code.
    * @param extraScrubbingModules Further modules to clean out, if
    *        not present in the `cleanState`.
    */
  def reloadChangedModules(builtinEnv: SessionEnv,
                           extraScrubbingModules: Set[String] = Set.empty)
                          (implicit sessionEnv: SessionEnv, su: Supply, con: Printer): Set[String] = {
    val dcl = Session.depCache.toList
    val dcm = dcl.map({ case (k,(_,v)) => (k,v)}).toMap // a local immutable depCache map sans times
    val possible = dcm.keySet
    // compute transitively dirty modules
    def go(dirt: Set[SourceFile]): Set[SourceFile] = {
      val dm = dirt.map(fn => dcm(fn).moduleName)
      val xs = (possible &~ dirt).filter(p => ! (dcm(p).imports & dm).isEmpty)
      if (xs.isEmpty) dirt
      else go(dirt | xs)
    }
    // a set of filesystem SourceFiles
    val dirtyFiles = go(
      dcl.collect{case (sf, (lm, d))
                  if sf.lastModified map (lm !=) getOrElse true =>
                    sf}.toSet)

    val dirtyModules = dirtyFiles.map(fn => dcm(fn).moduleName)
    val scrubbing = dirtyModules ++ extraScrubbingModules

    val (manualDirtyFiles, simpleDirtyFiles) = dirtyFiles partition (_.exotic)
    val simpleDirtyModules = simpleDirtyFiles.map(fn => dcm(fn).moduleName)

    // scrub those modules back down to their lib state
    val oldState = sessionEnv.copy
    sessionEnv.env = oldState.env.filter {
      case (v@V(_,_,Some(Global(m,_,_)),_,_),_) => !scrubbing(m) || builtinEnv.env.contains(v)
      case _ => true
    }
    sessionEnv.termNames = oldState.termNames.filter {
      case (n@Global(m,_,_),_) => !scrubbing(m) || builtinEnv.termNames.contains(n)
    }
    sessionEnv.cons = oldState.cons.filter {
      case (n@Global(m,_,_),_) => !scrubbing(m) || builtinEnv.cons.contains(n)
    }
    sessionEnv.loadedFiles = oldState.loadedFiles.filter { case (k,v) => !scrubbing(v) }
    sessionEnv.loadedModules = oldState.loadedModules -- scrubbing
    val died = if (simpleDirtyModules.isEmpty && manualDirtyFiles.isEmpty) {
      sayLn("No modules have changed.")
      None
    } else {
      try {
        benchmark({
          if (!simpleDirtyModules.isEmpty)
            loadModules(simpleDirtyModules.toList)
          for (fn <- manualDirtyFiles)
            load(fn, Some(dcm(fn).moduleName))
        }) { _ =>
          "Reloaded" :+: ordinal(dirtyModules.size,"dirty module","dirty modules") :+:
          "(" :: ordinal(manualDirtyFiles.size,"exotic file","exotic files") ::
          ") while retaining" :+: ordinal((possible &~ dirtyFiles).size,"module","modules")
        }
        None
      } catch { case e@Death(_, _) => Some(e) }
    }
    died match {
      case None => simpleDirtyModules
      case Some(e) =>
        // We've modified the dependency cache, a mutable hashmap, so we need to revert it.
        // There are two cases we need to revert: 1, we successfully parsed (and noted that we parsed) a modified file
        val dc = Session.depCache
        val toRevert = dcl.filter( {case (sf, _) => dirtyFiles.contains(sf)})
        toRevert.foreach( dc.+= _ ) // += overwrites old values
        // 2, we've added imports to a file, so we've added things to depCache
        val added = dc.keySet.diff( dcl.map(_._1).toSet )
        added.foreach( dc.-= _)
        sessionEnv := oldState

        sayLn("Error during reload, reverting.")
        throw e
    }
  }

  def readModule(fileName: String)(implicit s: SessionEnv, su: Supply, con: Printer): Module = {
    val file = Filesystem(fileName)
    val d = dep(file)
    val ms = s.loadedModules.keySet
    for (m <- d.imports &~ ms)
      load(SourceFile.forModule(m), Some(m), List(file))
    d.read(s,su).get._2
  }

  // evaluate an expression given by text, in the context of a set of imported modules
  def eval(
    text: String,
    importedModules: Map[String, (Option[String], List[Explicit[Global]], Boolean)],
    source: String = "<interactive>"
  )(implicit s: SessionEnv, su: Supply, con: Printer): (Type, Runtime) = {
    loadModules(importedModules.keySet.toList)
    // post-G1 D3: expressions ride the split pipeline unconditionally
    // (parity pinned by TestReplDifferential's corpus and repl-smoke);
    // REPL COMMAND parsing stays fused (Decision d covers ':' commands,
    // not the term grammar)
    val a = com.clarifi.reporting.ermine.rename.NewPipeline.replTerm(source, text, importedModules)
    val ty = subst { implicit hm => inferType(Nil,a.close) }
    (ty, Term.eval(a, s.env))
  }

  /* This is intended to be a waypoint between eval and evalInContext
   * If a module with the given moduleName is available to be imported, then
   * the expression in text is evaluated with said module imported unqualified.
   * This is equivalent to evalInContext as long as the expression only uses
   * public exported definitions from the single module, and is slightly easier
   * to use than eval.
   *
   * The main difference from evalInContext is that the expression may not have
   * access to the contents of modules imported by the context module. Instead,
   * the module must re-export such content by using an `export` statement
   * rather than an import. Fortunately, exported names are identical to the
   * locally available names, so any expression that would work with
   * evalInContext will also work with evalInNamedModuleContext so long as the
   * module exports all its dependencies.
   */
  def evalInNamedModuleContext(
    text: String,
    moduleName: String,
    source: String = "<remote>"
  ): (SessionEnv, Supply, Printer) => Runtime =
    eval(text, Map((moduleName, (None, List(), false))), source)(_, _, _)._2

  // load a module from a file. optionally checking to see if the name is what you expected
  // and/or passing a list of modules we're currently building for circular dependency checking
  // @throws Death
  def load(
    file: SourceFile,
    expectedModuleName: Option[String] = None,
    making: List[SourceFile] = Nil
  )(implicit s: SessionEnv, su: Supply, con: Printer) : String = s.loadedFiles.get(file) match {
    case Some(m) =>
      if (expectedModuleName.isDefined && expectedModuleName.get != m)
        die(file.toString :: ":1:1: error: expected a module named" :+: expectedModuleName.get)
      else m
    case None =>
      val d = dep(file, making)
      if (expectedModuleName.isDefined && expectedModuleName.get != d.moduleName)
        d.die("expected a module named " + expectedModuleName.get)
      for (m <- d.imports &~ s.loadedModules.keySet)
        load(SourceFile.forModule(m), Some(m), file :: making)
      d.make
      d.moduleName
  }

  def conMap(mod: String, tn: Map[Name,TypeVar])(implicit s: SessionEnv): Map[TypeVar,Type] =
    Type.conMap(mod, tn, s.cons)

  // @type Death
  def global(m: String, v: V[Any]): Global = v.name match {
    case Some(l : Local)                   => l global m
    case Some(g : Global) if g.module == m => g
    case _                                 => v.die("error: expected local name")
  }

  type Maps = (Map[TypeVar,Type],Map[TermVar,TermVar])

  def emptyMaps: Maps = (Map(),Map())
  def appendMaps(p: Maps, q: Maps): Maps = (p._1 ++ q._1, p._2 ++ q._2)
  def foldMaps(xs: List[Maps]): Maps = xs.foldLeft(emptyMaps)(appendMaps)

  def subTypeMaps[A:HasTypeVars](m: Maps, a: A): A = subType(preserveLoc(m._1), a)
  def subTermMaps[A:HasTermVars](m: Maps, a: A): A = subTermEx(Map(), preserveLoc(m._1), preserveLoc(m._2), a)
  def processTypeDefComponent(mn: String)(maps: Maps, tds: List[TypeDef])(implicit se: SessionEnv, su: Supply): Maps = {
    val dvs = tds.map(_.v)
    val tdsp = subTypeMaps(maps, tds).map(_.closeWith(dvs))
    for (td <- tdsp) assertTypeClosed(td, dvs.toSet)
    val ktds = subst(implicit hm => inferTypeDefKindSchemas(tdsp))
    var conMap: Map[TypeVar,Type] = null
    val cons = ktds.map {
      case (ks, DataStatement(l, v, kindArgs, typeArgs, cons, sels)) =>
        val tn = global(mn, v)
        // Stage 1a: (constructor V id, positional index) -> the source name
        // of that field.  Built from the DataStatement's selectors, which
        // cover EVERY named field -- including an existential one, which
        // gets no selector function but still has a name on the wire.
        val fieldName: Map[(Int, Int), String] =
          sels.flatMap(sel => sel.sites.map { case (cv, i) => ((cv.id, i), sel.name) }).toMap
        // the ordered constructors with their field types, kept on the Con
        // and in the encoder's registry (DataConDecl.scala); the field types
        // are substituted through this component's type map once it exists
        // (conMap is assigned below), hence the by-name argument
        val built = new DataConDecl(tn, l, kindArgs, typeArgs, {
          cons.map { case (es, cv, fs) =>
            DataConDecl.Constructor(global(mn, cv), es,
              subTypeMaps((maps._1 ++ conMap, maps._2), fs).zipWithIndex.map {
                case (t, i) => (fieldName.get((cv.id, i)), t)
              })
          }
        })
        // WP-3: the Con always carries the decl; whether the PROCESS-WIDE
        // registry is written too is the session's call.  The editor's
        // tolerant check runs this for every `data` in an open buffer, on
        // every debounced keystroke, and must not publish a half-typed
        // shape to a JSON encode running elsewhere in the JVM
        // (SessionState.scala `registerDecls`).
        val decl =
          if (se.registerDecls) DataConDecl.register(built, cons.map(cv => global(mn, cv._2)))
          else built
        v -> addCon(Con(l, tn, decl, ks))
      case (ks, ClassBlock(l, v, kindArgs, typeArgs, ctx, privates, body)) =>
        v -> addCon(Con(l, global(mn, v), ClassDecl, ks))
      case (ks, TypeStatement(l, v, kindArgs, typeArgs, body)) =>
        v -> addCon(Con(l, global(mn, v), new TypeAliasDecl(kindArgs, typeArgs, { subType(preserveLoc(conMap - v), body) }), ks))
    }
    conMap = cons.toMap
    mapAccum_((maps._1 ++ conMap, maps._2), ktds.zip(cons)) {
      case (s, ((_, DataStatement(l, v, kindArgs, typeArgs, cons, sels)), (_, con))) =>
        val subbed = cons.map { case (es, cv, fields) => (es, cv, subTypeMaps(s, fields)) }
        val conVars = subbed.map {
           case (es, v, fields) => v -> mkDataConstructor(v.loc,  global(mn, v), con.schema.forall, es, typeArgs, con, fields)
        }
        // the generated record-field selectors, installed exactly where and
        // how the constructors are, so the Full and Interface loads both get
        // them and neither needs a change to the .ei format
        val byCon = subbed.map { case (_, cv, fs) => cv.id -> fs }.toMap
        val selVars = sels.flatMap { sel => sel.v.map { sv =>
          val (cv0, i0) = sel.sites.head
          sv -> mkFieldSelector(sv.loc, global(mn, sv), sel.name, con.schema.forall, typeArgs, con,
                                byCon(cv0.id)(i0), sel.sites.map { case (cv, i) => (global(mn, cv), i) })
        } }
        (s._1, s._2 ++ conVars ++ selVars)
      case (s, ((_, ClassBlock(l,v, kindArgs, typeArgs, ctx, privates, body)), (_, con))) =>
        addClass(l, con, typeArgs, subTypeMaps(s, ctx), _ => typeArgs.map(_ => Bottom(sys.error("hahahahah"))))
        s
      case (s, _) => s
    }
  }

  lazy val first = nanoTime
  def profile(s: String, start: Long, times: (String, Long)*) =  {
    val df = new DecimalFormat("0.0000")
    val (end, msg) = (times.toList.foldLeft((start, s :: ":")) {
      case ((last,s),(msg,n)) =>
        (n, s :+: df.format((n - last) / 1000000000.0) :: "s" :+: "(" :: msg :: text(")"))
    })
    _log ldebug (
      ((start - first) / 1000000).toString :: "ms" :+: "-" :+:
      ((end - first) / 1000000).toString :: "ms" :+:
      msg :+: df.format((end - start) / 1000000000.0) :: "s (overall)"
    ).toString
  }

  def mkDataConstructor(
    loc: Loc,
    g: Global,
    ks: List[KindVar],
    es: List[TypeVar],
    ts: List[TypeVar],
    con: Type,
    f: List[Type])(implicit s: SessionEnv, su: Supply) =
    primOp(loc, g, Runtime.accumData(g, Nil, f.length),
      Forall.mk(loc.inferred, ks, ts ++ es, Exists(loc.inferred),
        f.foldRight(con(ts.map(VarT(_)):_*))(Arrow(loc.inferred,_,_))))

  /** A generated record-field selector (named constructor fields, design
    * note 3.1 item 2, Stage 1a): `forall {k..} a.. . T a.. -> fieldType`.
    *
    * The constructor's own existentials are NOT quantified here -- a field
    * whose type mentions one is refused a selector in the renamer, so
    * `fieldType` only ever mentions the type's own arguments.  The type is
    * the very `Type` `mkDataConstructor` gave that argument (both read the
    * substituted constructor field list), so a selector cannot drift from
    * the constructor it projects. */
  def mkFieldSelector(
    loc: Loc,
    g: Global,
    field: String,
    ks: List[KindVar],
    ts: List[TypeVar],
    con: Type,
    fieldType: Type,
    sites: List[(Global, Int)])(implicit s: SessionEnv, su: Supply) =
    primOp(loc, g, Runtime.selectData(field, sites.toMap),
      Forall.mk(loc.inferred, ks, ts, Exists(loc.inferred),
        Arrow(loc.inferred, con(ts.map(VarT(_)):_*), fieldType)))

  // assumes the binding group has had its cons replaced
  def loadModule(
    ps: ParseState,
    m: Module,
    preChecked: Map[Global,Type.Con] => Option[PartialFunction[TermVar,TermVar]],
    writeInterface: List[TermVar] => Unit = (_ => ())
  )(implicit s: SessionEnv, su: Supply): (CheckMethod, Maps) = {
    val prior = nanoTime
    var maps = (Type.conMap(m.name, ps.s.typeNames, s.cons), Map(): Map[TermVar,TermVar])
    val mod = m.name
    maps = mapAccum_(maps, m.fields) { processFieldStatement(mod, ps) }
    maps = mapAccum_(maps, m.foreignData) { processForeignDataStatement(mod) }
    maps = mapAccum_(maps, typeDefComponents(m.types)) { processTypeDefComponent(mod) }
    maps = mapAccum_(maps, m.foreigns) {
      (cm, cs) => cs match {
        case ffs : ForeignFunctionStatement    => processForeignFunctionStatement(mod)(cm, ffs)
        case fms : ForeignMethodStatement      => processForeignMethodStatement(mod)(cm, fms)
        case fvs : ForeignValueStatement       => processForeignValueStatement(mod)(cm, fvs)
        case fcs : ForeignConstructorStatement => processForeignConstructorStatement(mod)(cm, fcs)
        case fss : ForeignSubtypeStatement     => processForeignSubtypeStatement(mod)(cm, fss)
      }
    }
    maps = mapAccum_(maps, m.tables) { processTableStatement(mod) }
    val miscStatementTime = nanoTime
    val is = subTermMaps(maps, m.implicits).map(_.close).toList
    val es = subTermMaps(maps, m.explicits).map(_.close).toList
    val bs : List[Binding] = is ++ es
    val env = s.env
    assertTermClosed(bs, env.keySet ++ bs.map(_.v))
    assertTypeClosed(bs)
    val closureTime = nanoTime
    val localCons: Map[Global,Con] = maps._1 collect {
      case (V(_, _, Some(g : Global), _, _), t : Type.Con) => g -> t
      case (V(_, _, Some(l : Local), _, _), t : Type.Con) => l.global(m.name) -> t
    }
    val (tcm, (_, ds, varAnn)) = preChecked(localCons) match {
      case None =>
        subst { implicit hm =>
          // S5.1 follow-up: the last `true` is `publishing` -- this is the MODULE's
          // top-level binding group, the one whose generalised types are written to the
          // `.ei`.  `Subst.deleteTautologies` fires only here.
          val r@(_, ty, ms) = inferBindingGroupTypes(m.loc, Nil, is, es, true, true)
          if (!hm.remembered.isEmpty) {
            println("\nRemembered terms:\n")
            hm.remembered.values.toSeq
              .sortBy(_._3)(Loc.locOrder.toScalaOrdering)
              .foreach { case (_, typ, loc) =>
                println(loc.report(Pretty.prettyType(typ)))
            }
          }
          writeInterface(ms.values.toList)
          // do something with hm here, which is a SubstEnv
          (CheckMethod.Full, r)
        }
      case Some(remap) =>
        (CheckMethod.Interface, (List(), List(), remap))
    }
    for (d <- ds)
      if (!d.isTrivialConstraint)
        d.die("non-trivial top level constraint")
    val bgTime = nanoTime
    val mp = m.subTerm(varAnn)
    val pts = mp.privateTerms
    val buf = new ListBuffer[(Global,TermVar)]()
    val tmbuf = new ListBuffer[(TermVar, TermVar)]()
    bs.foreach {
      case b if pts.contains(b.v) =>
        if (varAnn.isDefinedAt(b.v))
          tmbuf += (b.v -> varAnn(b.v))
        else ()
      case b if !varAnn.isDefinedAt(b.v) =>
        b.die("pre-checked types failed to handle exported definition")
      case b =>
        val v = varAnn(b.v)
        val g = global(mp.name, v)
        buf += (g -> v.copy(name = Some(g)))
        tmbuf += (b.v -> v)
    }
    val tm = buf.toMap
    val terms = tmbuf.toMap
    val substTime = nanoTime

    val exports = m.importExports.filter(_.isExport)
    // re-exported terms
    val ess = for {
      (k,v) <- s.termNames
      e <- exports.filter(_.module == k.module)
      if e.exported(false, k)
    } yield (k.localized(e.as, Explicit.lookup(k, e.explicits.filter(!_.isType))).global(mp.name), v)

    val tmp = tm ++ ess
    // re-exported type cons
    val etcs = for {
      (k,v) <- s.cons
      e <- exports.filter(_.module == k.module)
      if e.exported(true, k)
    } yield (k.localized(e.as, Explicit.lookup(k, e.explicits.filter(_.isType))).global(mp.name), v)

    val reexportTime = nanoTime

    val tn = s.termNames
    val cs = s.cons

    val overwrites = tmp.keySet.intersect(tn.keySet).toList
    if (!overwrites.isEmpty)
      mp.die("error: loading would overwrite" :+:
        ordinal(overwrites.length,"existing global:", "existing globals:") :+:
        fillSep(punctuate("," :: line, overwrites.toList.map(Pretty.ppName(_)(Pretty.Unqualified).run)))
      )

    val overwrites2 = etcs.keySet.intersect(cs.keySet).toList
    if (!overwrites2.isEmpty)
      mp.die("error: loading would overwrite" :+:
        ordinal(overwrites2.length,"existing type constructor:", "existing type constructors:") :+:
        fillSep(punctuate("," :: line, overwrites2.toList.map(Pretty.ppName(_)(Pretty.Unqualified).run)))
      )

    val overwrites3 = tm.values.toSet.intersect(env.keySet).toList
    if (!overwrites3.isEmpty)
      mp.die("error: loading would overwrite" :+:
        ordinal(overwrites3.length,"existing global", "existing globals") :+: "in the environment:" :+:
        fillSep(punctuate("," :: line, overwrites3.toList.map(Pretty.ppVar(_)(Pretty.Unqualified).run)))
      )

    val overwriteCheckTime = nanoTime

    val gptms = mp.privateTerms.map(global(mp.name, _)).toList
    val gptys = mp.privateTypes.map(global(mp.name, _)).toSet

    val mpbs = subTermMaps(maps, (mp.implicits ++ mp.explicits) : List[Binding]).map(_.close)

    var envp: Term.Env = null
    envp = env ++ mpbs.map(b => b.v -> Thunk(Term.evalBinding(b, envp)))

    s.env = envp -- pts
    s.termNames = (tmp ++ s.termNames) -- gptms

    val (exCons, hiCons) = (etcs ++ s.cons) partition {
      case (g, v) if g.module == mp.name => !gptys(g)
      case _ => true
    }

    s.cons = exCons
    s.privateCons = (hiCons ++ s.privateCons)

    s.termNameOrigins = s.termNameOrigins ++ ps.s.termOrigins
    s.consOrigins = s.consOrigins ++ ps.s.typeOrigins


    val preEnv = nanoTime
    val msFinal = (maps._1, maps._2 ++ terms)
    val endTime = nanoTime
    // _ <- profile(mp.name + " loadModule", prior, "misc" -> miscStatementTime, "closure" -> closureTime, "binding" -> bgTime, "rest" -> endTime)
    profile(mp.name + " loadModule", prior, "misc" -> miscStatementTime, "closure" -> closureTime, "binding" -> bgTime, "misc" -> preEnv, "environment" -> endTime)
    (tcm, msFinal)
  }

  def unfurlType: Type => (List[Type], Type) = {
    case AppT(AppT(Arrow(_), a), b) => {
      val (ts, t) = unfurlType(b)
      (a :: ts, t)
    }
    case Forall(_, _, _, _, f) => unfurlType(f)
    case b => (Nil, b)
  }

  def perhapsForeign(post: ImportResult, v: => Any): Runtime = post match {
    case Raw => Prim(v)
    case FF(arg) => Prim(new FFI(perhapsForeign(arg, v)))
    case BOOL => if (v.asInstanceOf[Boolean]) True else False
    case UNIT => val u = v ; Runtime.arrUnit
    case IO(arg) => Data(Global("Builtin", "IO"),
                     Array(Fun((kp: Runtime) =>
                            Fun((kf: Runtime) =>
                              Fun((ke: Runtime) => kf(kp)(ke)(perhapsForeign(FF(arg), v)))))))
  }

  // Legacy marshalling; doesn't take any type information into account.
  def whnfForeign(a: Runtime, name: String): Any =
    a.whnf match {
      case Prim(p) => p.asInstanceOf[Object]
      case Fun(f) => (v: Any) => whnfForeign(f(Prim(v)), name)
      case Rel(r) => r
      case Arr(arr) if(arr.length == 0) => ()
      case b@Bottom(e) => b.extract[Any]
      case other => other
      // case e => error("Panic: foreign method " + name + " encountered nonscalar: " + e)
    }

  def marshalForeign(t: Type, a: Runtime, name: String): Any = {
    t match {
      case `bool`  => a.whnf match {
        case True  => true
        case False => false
        case _     => die("panic: marshalForeign: expected boolean, found: " + a.toString)
      }
      case _      => whnfForeign(a, name) // default to legacy
    }
  }

  sealed trait ImportResult
  case object Raw extends ImportResult
  case object BOOL extends ImportResult
  case object UNIT extends ImportResult
  case class FF(arg: ImportResult) extends ImportResult
  case class IO(arg: ImportResult) extends ImportResult

  def foreignLift(methName: String,
                  static: Boolean,
                  post: ImportResult,
                  dom: List[Type],
                  method: java.lang.reflect.Method): Runtime = {
      /** Re-resolve `method` against the receiver when it does not implement the
        * declaring class.
        *
        * A `.e` foreign declaration names the method on an *interface*, e.g.
        * `method "apply" funcall2# : Function2 a b c -> (a -> b -> c)`, and
        * passes a case class companion for it. In Scala 2 those companions
        * extended `FunctionN` so the interface method applied directly; Scala 3
        * dropped that, so the same `apply` has to be found on the companion's
        * own class instead. Same method, same arity — only the reflective
        * handle differs.
        */
      def resolve(self: Any): java.lang.reflect.Method =
        if (self == null || method.getDeclaringClass.isInstance(self)) method
        else {
          val cls = self.asInstanceOf[AnyRef].getClass
          val n = method.getParameterCount
          cls.getMethods.find(m => m.getName == method.getName && m.getParameterCount == n)
             .map { m => m.setAccessible(true); m }
             .getOrElse(method)
        }

      def mk(self: => Any) : Runtime = try {
        import scala.compat.{Platform => Pform}
        import com.clarifi.reporting.Profile
        val f = (args: Array[AnyRef]) => {
          val time = Pform.currentTime
          try {
            resolve(self).invoke(self, args:_*)
          } catch {
              case d : Death => throw d // Don't catch ermine panics as a side effect of foreign interface
              case e : java.lang.reflect.InvocationTargetException =>
                val ep = e.getTargetException
                val ep2 = if (ep != null) ep else e
                _log.debug(ep2.getMessage, ep2)
                throw ep2
              case e : Throwable =>
                println(args.mkString(", "))
                if( self != null && method != null ) {
                  _log.debug("error invoking foreign function: " + methName + " on object of type " + self.asInstanceOf[AnyRef].getClass + "; expected an object of type " + method.getDeclaringClass , e)
                  throw new RuntimeException("error invoking foreign function: " + methName + " on object of type " + self.asInstanceOf[AnyRef].getClass + "; expected an object of type " + method.getDeclaringClass , e)
                } else {
                  _log.debug("error invokingforeign function: " + methName
                            + "on object of type "
                            + Option(self).map( _.asInstanceOf[AnyRef].getClass.toString).getOrElse("null")
                            + "; expected an object of type " + Option(method).map(_.getDeclaringClass).getOrElse(" null") , e)
                  throw new RuntimeException("error invoking static foreign function: " + methName
                            + "on object of type "
                            + Option(self).map( _.asInstanceOf[AnyRef].getClass.toString).getOrElse("null")
                            + "; expected an object of type " + Option(method).map(_.getDeclaringClass).getOrElse(" null") , e)
                }
            }
            finally
            {
              def formatEntryKey(elapsed: Long) =
                methName + " (" + method.getDeclaringClass.getName + ')'
              def formatElapsed(p: (String,Long)) =
                "Invoked in " + p._2 + "ms: " + p._1
              val elapsed = Pform.currentTime - time
              val entry: (String,Long) = formatEntryKey(elapsed) -> elapsed
              Profile.instance+=(entry)

              if(_log.isDebugEnabled) {
                if( elapsed == 0 ) {
                  if(_log.isTraceEnabled)
                    _log.trace(formatElapsed(entry))
                }
                else {
                   _log.debug(formatElapsed(entry))
                }
              }
            }
        }
        val g = (z: List[Any]) =>
                   perhapsForeign(post, f(z.asInstanceOf[List[AnyRef]].reverse.toArray))
        val h = dom.foldRight(g)((t, b) => z => Fun(a => b(marshalForeign(t, a, methName) :: z)))

        h.apply(Nil)
      } catch {
        case d : Death => throw d // Don't catch ermine panics as a side effect of foreign interface
        case NonFatal(e) => Bottom(throw e)
      }
      if (static) mk(null) else Fun(x => mk(whnfForeign(x, methName)))
  }

  /**
   * Calculates the post process marshalling that should be done for a foreign import.
   * We have special support for importing Boolean and Unit/void result types, which
   * marshals between the Java representation and the ermine representation. Units will
   * have any nulls eliminated, as well.
   *
   * There is also special support for importing effectful things directly. Importing as
   * `FFI a` will allow catching exceptions thrown by the import. Importing as `IO a` will
   * automatically wrap into the continuation passing around `FFI` that we use to represent
   * I/O actions. Explicitly importing to `FFI/IO Bool/Unit` will also perform the
   * marshalling in the previous paragraph recursively. But `FFI (FFI a)` and the like will
   * not wrap multiple times; it is expected that this last case is for Java functions that
   * actually return FFI.
   */
  def computePost(c: Type, higher: Boolean): (Class[_], ImportResult) = c match {
    case AppT(`io`, a) if higher => computePost(a, false) match {
      case (cod, arg) => (cod, IO(arg))
    }
    case AppT(`ffi`, a) if higher => computePost(a, false) match {
      case (cod, arg) => (cod, FF(arg))
    }
    case `bool`         => (implicitly[ClassTag[Boolean]].runtimeClass, BOOL)
    case ProductT(_, 0) => (implicitly[ClassTag[Unit]].runtimeClass, UNIT)
    case _              => (c.foreignLookup, Raw)
  }

  // ---------------------------------------------------------- LSP-FFI
  // Tolerating a `foreign` declaration this JVM cannot resolve
  // (tracker/LSP-FFI-TOLERANCE.md).  Every branch below is guarded by
  // `s.foreignTolerant`, which is OFF for bin/ermine, the REPL and
  // core/test: with it off each `die`/`Death` here is the one that has
  // always been thrown, with the same words.

  /** The first of these types whose head is a `foreign data` with no
    * backing class, and the class name it wanted.
    *
    * This is the whole of "which operations need the class AT LOAD TIME":
    * a reflective method / field / constructor lookup, and the class
    * `computePost` demands of a codomain, all read `Type.foreignLookup`,
    * and nothing else in a load does.  So a `foreign data` of a missing
    * class is a perfectly good opaque type until one of those runs, and
    * marshalling does not change that — `marshalForeign` falls through to
    * `whnfForeign`, which uses no type information at all.
    *
    * It is NOT a complete test at RUN time (review finding P-6): a
    * foreign pattern match goes through `ConDecl.isInstance`, which has
    * no class to ask.  `TypeConDecl.isInstance` raises there rather than
    * quietly answering "no match"; the editor never evaluates, so this
    * only concerns a batch run with the option on. */
  private def unresolvedForeignIn(ts: List[Type]): Option[String] = {
    def head(t: Type): Option[Con] = t match {
      case Forall(_, _, _, _, b) => head(b)
      case _                     => unfurlApp(t).map(_._1)
    }
    def isSentinel(t: Type): Boolean =
      try t.foreignLookup eq classOf[UnresolvedForeign]
      catch { case NonFatal(_) => false }
    ts.find(isSentinel).map { t =>
      head(t).map(_.decl).collect { case TypeConDecl(_, _, Some(cn)) => cn }
             .getOrElse("an unresolved foreign class")
    }
  }

  /** The span of a declared NAME, for a failure with no class or member
    * string of its own (`foreign constructor`, `foreign subtype`). */
  private def nameSpan(v: TermVar): Option[Span] = v.loc match {
    case p: Pos => Some(Span(p.line, p.column, p.line,
                             p.column + v.name.map(_.string.length).getOrElse(1)))
    case _      => None
  }

  /** `loc` re-pointed at `span`, so a Death rendered from it blames the
    * class name or the member string rather than the statement head. */
  private def atSpan(loc: Loc, span: Option[Span]): Loc = (loc, span) match {
    case (p: Pos, Some(sp)) => Pos(p.fileName, "", sp.startLine, sp.startCol, false)
    case _                  => loc
  }

  /** Record ONE tolerated failure as a positioned note.
    *
    * The text is ONE line, "file:line:col: <label>: ...", positioned at
    * the same place as `span` — the class name or the member string, not
    * the statement head.  `Pos.report`'s usual source line and caret are
    * left off deliberately: the Pos a lowered statement carries has no
    * source text, so they would render as a blank line and a lone caret,
    * and the editor shows the whole report as the message.
    *
    * `severity` is the LSP one: 2 for a binding that will not resolve, 3
    * for the `foreign data` note, which is information and not a
    * complaint (review finding P-2). */
  private def noteForeign(mod: String, loc: Loc, span: Option[Span],
                          severity: Int, detail: String)
                         (implicit s: SessionEnv): Unit = {
    val (file, line, col) = (loc, span) match {
      case (p: Pos, Some(sp)) => (p.fileName, sp.startLine, sp.startCol)
      case (p: Pos, None)     => (p.fileName, p.line, p.column)
      case _                  => ("", 0, 0)
    }
    val at    = if (file.isEmpty) "" else file + ":" + line + ":" + col + ": "
    val label = if (severity == 2) "warning: " else "note: "
    s.noteForeign(ForeignNote(mod, span getOrElse Span(line, col, line, col),
                              severity, at + label + detail))
  }

  /** The warning AND the value the binding is installed with.  The stub
    * is bound at the DECLARED type, so the module and everything
    * downstream still type-check, navigate and hover; only RUNNING it
    * fails, with the sentence the warning carries. */
  private def foreignStub(mod: String, name: Global, loc: Loc, span: Option[Span],
                          kind: String, what: String, cause: String)
                         (implicit s: SessionEnv): Runtime = {
    val detail = "unresolved foreign binding `" + name.string + "`: " + kind + ": " + what +
                 (if (cause.isEmpty) "" else " — " + cause)
    noteForeign(mod, loc, span, 2, detail)
    Bottom(throw Death(text(detail)))
  }

  private def causeText(e: Throwable): String =
    e.getClass.getName + Option(e.getMessage).map(": " + _).getOrElse("")

  /** Why `getMethod` said no: the member's own class will not link, or it
    * is absent by name, present at another arity, or present at this
    * arity with other parameter types.
    *
    * `getMethods` resolves every public method's SIGNATURE classes while
    * it searches, so it throws the same `NoClassDefFoundError` the lookup
    * that got us here did (review finding P-1) — hence the `attempt`,
    * inside the tolerant branch where an escaping Error would blank the
    * whole file. */
  private def memberKind(clazz: Class[_], name: String, dom: List[Class[_]], cause: Throwable): String =
    if (!cause.isInstanceOf[Exception]) "member unloadable"
    else Recoverable.attempt(clazz.getMethods.filter(_.getName == name)) match {
      case Left(_) => "member unloadable"
      case Right(byName) =>
        if (byName.isEmpty) "member missing"
        else if (!byName.exists(_.getParameterCount == dom.length))
          "arity mismatch (declared " + dom.length + ", the class has " +
            byName.map(_.getParameterCount).distinct.sorted.mkString("/") + ")"
        else "signature mismatch"
    }

  def processForeignCommon(mod: String,
                           member: ForeignMember,
                           v: TermVar,
                           foreignCls: Option[ForeignClass],
                           reporter: Located,
                           tyz: Type)(implicit s: SessionEnv, su: Supply): TermVar = {
    val methName = member.name
    val static = foreignCls.isDefined
    val loc = reporter.loc
    val ty = subst(implicit hm => {
      implicit val loc: Located = tyz
      kindCheck(Nil, tyz, Star(tyz.loc.inferred)); substType(tyz)
    })
    assertTypeClosed(ty)

    def stub(span: Option[Span], kind: String, what: String, cause: String): TermVar = {
      val g = global(mod, v)
      primOp(v.loc, g, foreignStub(mod, g, v.loc, span, kind, what, cause), ty)
    }

    // (1)(2) the class named by `foreign function`/`foreign value` is
    // missing or will not link.  The reader kept the failure instead of
    // dying, so the warning lands on the CLASS NAME.
    foreignCls.flatMap(_.failure) match {
      case Some(f) if s.foreignTolerant =>
        return stub(Some(f.span), f.kind, f.className + "." + methName, f.causeText)
      case _ => ()
    }

    val (domainTypes, codomainType) = unfurlType(ty)
    val (clazz, domain, codomain, post) = {
      val (r, p) = computePost(codomainType, true)
      foreignCls match {
        case Some(fc) => (fc.cls, domainTypes, r, p)
        case None     => (domainTypes.head.foreignLookup, domainTypes.tail, r, p)
      }
    }
    val classDomain = domain.map(_.foreignLookup)

    // (9) the lookup below needs the class of a `foreign data` we do not
    // have.  Blame the MEMBER, and name the class that is actually
    // missing rather than reporting "no such method" on a sentinel.
    if (s.foreignTolerant)
      unresolvedForeignIn(domainTypes :+ codomainType) match {
        case Some(cn) =>
          return stub(Some(member.span), "unresolved foreign class",
                      cn + " (needed to resolve `" + methName + "`)", "")
        case None => ()
      }

    // `getMethod` resolves the SIGNATURE classes of everything it
    // searches, so a class that loaded fine still throws
    // `NoClassDefFoundError` here when one of its members mentions a
    // class this JVM lacks (review finding P-1) — an Error, which
    // `case e: Exception` let escape past TolerantCheck.guard and
    // Diagnostics.run, blanking the file.  `Recoverable` is the same
    // catch set `classLookup` uses.
    val looked = Recoverable.attempt(clazz.getMethod(methName, classDomain:_*))
    // (3) member missing, (4) arity mismatch, a signature mismatch
    // between them, and (2') the member's own class failing to link:
    // one `getMethod`, four diagnoses.
    val method = looked match {
      case Right(m) => m
      case Left(e) if s.foreignTolerant =>
        return stub(Some(member.span), memberKind(clazz, methName, classDomain, e),
                    clazz.getName + "." + methName +
                      classDomain.map(_.getName).mkString("(", ", ", ")"),
                    causeText(e))
      case Left(e: Exception) =>
        throw Death(
          "method" :+: methName :+:
          "with domain" :+: classDomain.mkString(",") :+:
          "not found in class" :+: text(clazz.getName),
          e
        )
      case Left(e) =>
        // An Error here was an UNCAUGHT crash before this stage, so there
        // is no message to keep byte-identical: give it the position and
        // the cause the class-name case gets.
        throw Death(atSpan(loc, Some(member.span)).report(
          "member" :+: methName :+:
          "of class" :+: clazz.getName :+:
          "could not be resolved:" :+: text(causeText(e))
        ))
    }

    // (5) the return type is not assignable to the declared codomain.
    if (!codomain.isAssignableFrom(method.getReturnType)) {
      if (s.foreignTolerant)
        return stub(Some(member.span), "return type mismatch",
                    clazz.getName + "." + methName,
                    "declared " + codomain.getName + ", found " + method.getReturnType.toString)
      reporter.die(
        "expected return type" :+: codomain.getName :+:
        "does not match foreign return type" :+: text(method.getReturnType.toString)
      )
    }

    if(java.lang.reflect.Modifier.isStatic(method.getModifiers) != static) {
      if (s.foreignTolerant)
        return stub(Some(member.span), "static/instance mismatch",
                    clazz.getName + "." + methName,
                    if (static) "the method is not static; use foreign method instead"
                    else "the method is static; use foreign function instead")
      reporter.die(
        "method" :+: methName :+:
        "in class" :+: clazz.getName :+:
        text(if (static) "is not static; use foreign method instead"
             else "is static; use foreign function instead")
      )
    }
    // v.loc is the declared NAME's position; `loc` is the statement's,
    // and stays the one error reports blame
    primOp(v.loc, global(mod, v), foreignLift(methName, static, post, domain, method), ty)
  }

  def processForeignValueStatement(
    mod: String
  )(
    cm: Maps,
    fvs: ForeignValueStatement
  )(implicit s: SessionEnv, su: Supply) = fvs match {
    case ForeignValueStatement(loc, v, ty, fc, member) =>
      val valName = member.name
      var typ = subTypeMaps(cm, ty).close
      val (_, post) = computePost(typ, true)
      typ = subst { implicit hm => {
        implicit val loc: Located = typ
        kindCheck(Nil, typ, Star(typ.loc.inferred)); substType(typ)
      } }
      assertTypeClosed(typ)
      def stub(span: Option[Span], kind: String, what: String, cause: String): TermVar = {
        val g = global(mod, v)
        primOp(v.loc, g, foreignStub(mod, g, v.loc, span, kind, what, cause), typ)
      }
      // (1)(2) the holder class, then (6) the static field itself.  The
      // field's VALUE stays lazy — `perhapsForeign` takes it by name and
      // Prim turns a throw into a Bottom — so only the lookup fails here.
      val r = fc.failure match {
        case Some(f) if s.foreignTolerant =>
          stub(Some(f.span), f.kind, f.className + "." + valName, f.causeText)
        case _ =>
          val clazz = fc.cls
          // `getField` resolves every public field's type as it searches:
          // same Error hazard as `getMethod` (review finding P-1).
          val looked = Recoverable.attempt(clazz.getField(valName))
          looked match {
            case Left(e) if s.foreignTolerant =>
              stub(Some(member.span),
                   if (e.isInstanceOf[Exception]) "field missing" else "field unloadable",
                   clazz.getName + "." + valName, causeText(e))
            case Left(e: Exception) =>
              throw Death(loc.report(
                "static field" :+: valName :+:
                "not found in class" :+: text(clazz.getName)
              ), e)
            case Left(e) =>
              throw Death(atSpan(loc, Some(member.span)).report(
                "static field" :+: valName :+:
                "of class" :+: clazz.getName :+:
                "could not be resolved:" :+: text(causeText(e))
              ))
            case Right(value) =>
              primOp(
                v.loc,
                global(mod, v),
                perhapsForeign(post, try { value.get(null) } catch { case NonFatal(e) => throw e.getCause }),
                typ
              )
          }
      }
      (cm._1, cm._2 + (fvs.v -> r))
  }

  def processForeignConstructorStatement(
    mod: String
  )(
    cm: Maps,
    fcs: ForeignConstructorStatement
  )(implicit s: SessionEnv, su: Supply) = fcs match {
    case ForeignConstructorStatement(loc, v, tyz) =>
      var ty = subTypeMaps(cm, tyz).close
      ty = subst { implicit hm => {
        implicit val loc: Located = tyz
        kindCheck(Nil, ty, Star(ty.loc.inferred)); substType(ty)
      } }
      assertTypeClosed(ty)
      val (domainTypes, codomainType) = unfurlType(ty)
      val (domain, codomain, post) = {
        val (cl, p) = computePost(codomainType, true)
        (domainTypes, cl, p)
      }
      val classDomain = domain.map(_.foreignLookup)
      val name = global(mod, v)
      // A `foreign constructor` names no class and no member: its class
      // IS its codomain, so a tolerated failure is blamed on the declared
      // NAME.  (9) first — a missing `foreign data` class is the honest
      // reason — then (7), the constructor itself.
      def stub(kind: String, what: String, cause: String): TermVar =
        primOp(v.loc, name, foreignStub(mod, name, v.loc, nameSpan(v), kind, what, cause), ty)
      val unresolved =
        if (s.foreignTolerant) unresolvedForeignIn(domainTypes :+ codomainType) else None
      val r = unresolved match {
        case Some(cn) =>
          stub("unresolved foreign class", cn + " (needed to resolve a constructor)", "")
        case None =>
          // `getConstructor` resolves every public constructor's
          // signature as it searches (review finding P-1).
          val looked = Recoverable.attempt(codomain.getConstructor(classDomain:_*))
          looked match {
            case Left(e) if s.foreignTolerant =>
              stub(if (e.isInstanceOf[Exception]) "constructor missing" else "constructor unloadable",
                   codomain.getName + classDomain.map(_.getName).mkString("(", ", ", ")"),
                   causeText(e))
            case Left(e: Exception) =>
              throw Death(loc.report(
                "constructor not found for" :+: codomain.getName + "with arguments (" ::
                classDomain.map(_.getName).mkString(", ") :: text(")")
              ), e)
            case Left(e) =>
              throw Death(atSpan(loc, nameSpan(v)).report(
                "constructor of" :+: codomain.getName :+:
                "could not be resolved:" :+: text(causeText(e))
              ))
            case Right(ctor) =>
              val g = (args : List[AnyRef]) =>
                        perhapsForeign(post,
                          try {
                            ctor.newInstance(args:_*)
                          } catch { case NonFatal(e) => throw e.getCause }
                        )
              val f = domain.foldRight((z: List[Any]) => g(z.asInstanceOf[List[AnyRef]].reverse)) { (t, b) =>
                        z => Fun(a => b(marshalForeign(t, a, name.string) :: z))
                      }
              primOp(v.loc, name, f.apply(Nil), ty)
          }
      }
      (cm._1, cm._2 + (fcs.v -> r))
  }

  // @throws Death
  def toHeader(mod: String, t: Type)(implicit s: SessionEnv): Header = t match {
    case AppT(_, r) => toHeader(mod, r)
    case ConcreteRho(loc, fields) =>
      fields.map({
        case l : Local  => s.cons(l.global(mod))
        case g : Global => s.cons(g)
      }).map({
        case Con(loc, g, FieldConDecl(Nullable(Con(_, ty, _, _))), _) =>
          g.string -> PrimT.withName(ty.string).withNull
        case Con(loc, g, FieldConDecl(Con(_, ty, _, _)), _) =>
          g.string -> PrimT.withName(ty.string)
        case f => die(f.report("Invalid field in table:" :+: text(f.toString)))
      }).toMap
    case _ => die(t.report("Expected concrete row but found:" :+: text(t.toString)))
  }

  def processTableStatement(mod: String)(cm: Maps, ts: TableStatement)(implicit se: SessionEnv, su: Supply): Maps = ts match {
    case TableStatement(loc, db, vs, tyz) =>
      var ty = subTypeMaps(cm, tyz)
      ty = subst { implicit hm => {
        implicit val loc: Located = ty
        kindCheck(List(), ty, Star(ty.loc.inferred)); substType(ty)(hm)
      } }
      assertTypeClosed(ty)
      mapAccum_(cm, vs) {
        case (cs, ns ++ v) =>
          val u = primOp(v.loc, global(mod, v),
                         Rel(ExtRel(Table(toHeader(mod, ty),
                                               TableName(v.name.get.string,
                                                         ns.map(_.string))), db)), ty)
          (cs._1, cs._2 + (v -> u))
      }
  }

  // deliberately does not take the con map, we don't need it
  def processForeignDataStatement(mod: String)(cm: Maps, fds: ForeignDataStatement)(implicit s: SessionEnv, su: Supply): Maps = fds match {
    case ForeignDataStatement(loc, v, vs, clazz) =>
      val k = vs.foldRight(Star(loc.inferred) : Kind)((u, r) => ArrowK(loc.inferred, u.extract, r))
      // (9) A `foreign data` whose class is missing is still a perfectly
      // good OPAQUE type: nothing about declaring it, mentioning it in a
      // signature or passing it around needs the class, so this is no
      // WARNING.  It is not silence either (review finding P-2): a module
      // whose only foreign statement is such a declaration would publish
      // nothing at all, and be indistinguishable from one whose FFI is
      // intact — which is the opposite of what someone pointing this
      // server at a fork wants to learn.  So: an INFORMATION note (LSP
      // severity 3, a hint rather than a squiggle) on the class name,
      // saying the type is usable and where the class would be needed.
      // The decl remembers the name, and every site that does need it
      // names it in its own warning.
      val decl = clazz.failure match {
        case Some(f) =>
          if (s.foreignTolerant)
            noteForeign(mod, loc, Some(f.span), 3,
              "opaque foreign type `" + global(mod, v).string + "`: " + f.className +
              " is not on this JVM (" + f.kind + ") — the type is usable and this module " +
              "checks normally; a foreign function, method, value or constructor over it " +
              "cannot be resolved, and will warn where it is declared")
          TypeConDecl(clazz.cls, true, Some(f.className))
        case None    => TypeConDecl(clazz.cls, true)
      }
      val c = addCon(Con(loc, global(mod, v), decl, k.schema))
      (cm._1 + (v -> c), cm._2)
  }

  def processForeignSubtypeStatement(mod: String)(cm: Maps, fss: ForeignSubtypeStatement)(implicit s: SessionEnv, su: Supply): Maps = {
    var ty = subTypeMaps(cm, fss.ty).close
    ty = subst { implicit hm => {
      implicit val loc: Located = fss.ty
      kindCheck(Nil, fss.ty, Star(fss.loc.inferred)); substType(ty)
    } }
    assertTypeClosed(ty)
    // (8) A `foreign subtype` performs NO reflection: it is the identity,
    // and an unchecked claim that one foreign type is assignable to
    // another.  When either side has no backing class the claim cannot be
    // checked against anything, so it is warned about and the identity is
    // installed anyway — a stub here would break callers at run time for a
    // coercion that was never going to look at the class.
    // "over", not "unverifiable" (review finding P-8): nothing here ever
    // verifies the claim, resolved classes or not, so calling this case
    // unverifiable would imply a check that does not exist.  What the
    // note says is that this module's FFI is stale and here is one more
    // place it shows.
    if (s.foreignTolerant) {
      val (d, c) = unfurlType(ty)
      unresolvedForeignIn(d :+ c) foreach { cn =>
        noteForeign(mod, fss.v.loc, nameSpan(fss.v), 2,
          "foreign subtype `" + global(mod, fss.v).string +
          "` over an unresolved foreign class: " + cn +
          " — the coercion is installed as the identity it always was, and is not checked " +
          "against the class (it never is)")
      }
    }
    (cm._1, cm._2 + (fss.v -> primOp(fss.v.loc, global(mod, fss.v), Fun(x => x), ty)))
  }

  def processForeignFunctionStatement(mod: String)(cm: Maps, ffs: ForeignFunctionStatement)(implicit s: SessionEnv, su: Supply) =
    ( cm._1,
      cm._2 + (
        ffs.v -> processForeignCommon(mod, ffs.member, ffs.v, Some(ffs.cls), ffs.loc, subTypeMaps(cm, ffs.ty).close)
      )
    )

  def processForeignMethodStatement(mod: String)(cm: Maps, fms: ForeignMethodStatement)(implicit s: SessionEnv, su: Supply) =
    ( cm._1,
      cm._2 + (
        fms.v -> processForeignCommon(mod, fms.member, fms.v, None, fms.loc, subTypeMaps(cm, fms.ty).close)
      )
    )

  /*
   * Expects that the FieldStatement has been 'type checked' and processed
   * such that:
   *
   *   the variables are globalized and have their appropriate unique id
   *   the type is a valid prim type
   *
   * tmv should take the variable names to the term variables that were chosen
   * during checking.
   */
  // @throws Death
  def loadFieldStatement(fs: FieldStatement, tmv: Name => TermVar)(implicit s: SessionEnv, su: Supply): Unit = {
    val ty = fs.ty
    val ptyp = ty match {
      case Nullable(typ) => primTypes(typ).withNull
      case _ => primTypes(ty)
    }
    for (v <- fs.vs)
      v.name match {
        case Some(g : Global) =>
          addCon(Con(v.loc.inferred, g, FieldConDecl(ty), Field(v.loc.inferred).schema))
          install(tmv(v.name.get), Data(g, Array(Prim(ptyp))))
        case _ => die("loadFieldStatement: un-globalized variable: " + v)
      }
  }

  def processFieldStatement(module: String, ps: ParseState)(cm: Maps, fs: FieldStatement)(implicit s: SessionEnv, su: Supply) =
    fs.vs.map({ case v =>
      val ty = subTypeMaps(cm, fs.ty)
      val otyp = ty match {
        case Nullable(typ) => primTypes.get(typ) map (_.withNull)
        case _ => primTypes.get(ty)
      }
      if (!otyp.isDefined) die(text("Invalid field type:") :+: text(ty.toString))
      val tyCon = addCon(Con(v.loc.inferred,global(module, v),FieldConDecl(ty),Field(v.loc.inferred).schema))
      // v.loc, not fs.loc: `field a, b : Int` declares two names at two
      // positions, and each one is its own definition site
      val tmv = primOp(v.loc, tyCon.name, Data(tyCon.name, Array(Prim(otyp.get))),
                       field(ConcreteRho(v.loc.inferred, Set(tyCon.name)), ty))
      ps.s.termNames.get(v.name.get) match {
        case None    => (Map(v -> tyCon), Map():Map[TermVar,TermVar])
        case Some(u) => (Map(v -> tyCon), Map(u -> tmv))
      }
    }).foldLeft(cm)(appendMaps)

  def addClass(
    l: Loc,
    cls: Con,
    args: List[TypeVar],
    sups: List[Type],
    destroy: Runtime => List[Runtime]
  )(implicit s: SessionEnv): Con = {
    s.classes = s.classes + (cls.name -> ClassDef(l, cls.name, args, sups, destroy, Map()))
    def step(c: Con): List[Con] = s.classes.get(c.name) match {
      case None => List()
      case Some(cls) => cls.sups.flatMap(unfurlApp(_) match {
        case Some((cp,_)) => List(cp)
        case None => List()
      })
    }
    def go(c: Con): Unit = {
      for (cp <- step(c))
        if (cp.name == cls.name) c.die("cyclic class hierarchy")
        else go(cp)
    }
    go(cls)
    cls
  }

  def unsafePerformSession[A](m: (SessionEnv, Supply, Printer) => A): A = {
    implicit val con = Printer.simple
    implicit val s = new SessionEnv
    implicit val su: Supply = Supply.create
    val lib = Lib.preamble
    m(s,su,con)
    // try { m } catch { case Death(err, _) => sys.error("Failure:\n" + err) }
  }

  def parseModule(filename: String, content: String, module: String)(implicit s: SessionEnv, v: Supply): Either[Err, Module] =
    // post-G1 D3: the split pipeline reads the module (Death from the
    // renamer/lowering surfaces as a Left the way parse errors did)
    moduleHeader(module).run(ErParseState.mk(filename, content, module), v).right flatMap {
      case (_, mh) =>
        try Right(com.clarifi.reporting.ermine.rename.NewPipeline.readModule(filename, content, mh)(s, v)._2)
        catch { case d: Death => Left(Err.report(Pos.start(filename, content), Some(scalaparsers.Document.text(d.getMessage)), Nil)) }
    }
}
