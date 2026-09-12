package com.clarifi.reporting

import com.clarifi.reporting.ermine._
import scalaparsers.Loc

import org.scalacheck._
import Prop.{ Result => _, _ }

import java.io.File
import scala.io.Source

/** THE DIFFERENTIAL TEST for the signature-entailment decision procedure
  * (`tracker/loopmodel/SIG-2-DESIGN.md` (e) 2a, reviewer F3).
  *
  * The Lean development proves `sigDecide` -- an enumerating specification -- sound and
  * complete for the judgement (`sigEntails_iff_forall_label`, `sigDecide_iff`).  What SHIPS
  * is a third algorithm: `SigEntail.check` over the lifted `Constraints.LabelSearch`, with
  * dedup, one-hot propagation, budgets and a `Type` -> `RHS` encoder.  Nothing in Lean is
  * about that, so it is pinned here, twice:
  *
  *   1. THE CORPUS.  `core/src/test/resources/sigentail/records.tsv` is the whole corpus's
  *      probe records (module, binding, wanted, givens, `ds`) as a warn-mode sweep printed
  *      them, and `verdicts.tsv` is the verdict the committed PYTHON ORACLE
  *      (`tracker/tools/sigcheck.py`, an independent implementation of the same judgement,
  *      itself differentially tested against brute force and a DPLL at S2) reaches on each
  *      of the 310 signatures.  Every one must agree, verdict AND label class.  Regenerate
  *      BOTH FROM ONE SWEEP -- the records carry the ids that sweep minted and the hash order
  *      its given sets came out in (a fresh sweep reproduces `verdicts.tsv` byte for byte but
  *      not `records.tsv`), so a records file from one run with a verdicts file from another is
  *      not a differential -- with
  *        ERMINE_JAVA_OPTS="-Dermine.useInterface=false -Dermine.sigEntail=warn" \
  *          tracker/tools/corpus-run.sh --batch /tmp/corpus-warn
  *        tracker/tools/sigcheck.py /tmp/corpus-warn --assert-qsat \
  *          --records core/src/test/resources/sigentail/records.tsv \
  *          --tsv     core/src/test/resources/sigentail/verdicts.tsv
  *
  *   2. RANDOM SYSTEMS against EXHAUSTIVE ENUMERATION -- `sigDecide`'s own definition,
  *      written out here over at most 5 variables, 4 constraints and 2 labels, where
  *      `2^|R| x 2^|F|` per label class is affordable.  This is the property the shipped
  *      engine's optimisations (dedup, propagation) could break without any corpus
  *      signature noticing.
  *
  * Both sides read the same input through the same reader, so a disagreement is a
  * disagreement about the JUDGEMENT, not about parsing. */
object TestSigEntailDiff extends Properties("Ermine signature entailment (differential)") {

  /** 2,000 random systems, the number design (e) 2a asks for (the S2 reviewer ran 36,000
    * against the ORACLE with 0 disagreements; this is the same bar against the SCALA).  The
    * corpus and contract properties are `secure`/`proved`, so they run once regardless. */
  override def overrideParameters(p: Test.Parameters): Test.Parameters =
    p.withMinSuccessfulTests(2000)

  // ------------------------------------------------------------------ reading the records
  /** `name^123S` / `_^99A` / `(|a,b|)`; `S` skolem, `A` the existential `unbindExists` mints,
    * `B` a dangling `Bound`, bare = `Free`.  Exactly `SigEntail.render`'s spelling. */
  private val VarRe  = """^([A-Za-z0-9_.'\-]*)\^(\d+)([SAB]?)$""".r
  private val ConcRe = """^\(\|(.*)\|\)$""".r

  private def flavour(tag: String): VarType = tag match {
    case "S" => Skolem
    case "B" => Bound
    case "A" => Ambiguous(Free)
    case _   => Free
  }

  private def label(s: String): Name = Local(s)

  private def parsePart(t: String): Option[Type] = t match {
    case ConcRe(fs) =>
      Some(ConcreteRho(Loc.builtin, fs.split(",").filter(_.nonEmpty).map(label).toSet))
    case VarRe(n, id, tag) =>
      Some(VarT(V(Loc.builtin, id.toInt, Some(Local(if (n.isEmpty) "_" else n)),
                  flavour(tag), Rho(Loc.builtin))))
    case _ => None
  }

  /** One rendered constraint back into a `Type`, or `None` when it is not a partition at
    * all (a class constraint, an applied type variable): the check's own encoder is what
    * decides what to do with those, so they are passed through as an opaque `Con`. */
  private def parseConstraint(t: String): Option[Type] = {
    val i = t.indexOf(" <- ")
    if (i < 0) return None
    val lhs = t.substring(0, i)
    val rhs = t.substring(i + 4)
    if (!(rhs.startsWith("(") && rhs.endsWith(")"))) return None
    val ps = rhs.substring(1, rhs.length - 1)
    val parts = if (ps.trim.isEmpty) Nil else ps.split(", ").toList.map(parsePart)
    if (parts.exists(_.isEmpty)) return None
    parsePart(lhs).map(l => Part(Loc.builtin, l, parts.map(_.get)))
  }

  /** A given that is not a partition -- a class constraint, or the applied type VARIABLE of
    * design (a4) -- kept as an APPLICATION HEADED BY A VARIABLE so the check sees the same
    * number of givens and classifies it itself.  Verdict-equivalent to the real shape: the
    * encoder drops every non-`Part` given either way, and the only difference is whether the
    * message lists it.  Negative ids so nothing can collide with a corpus variable. */
  private def opaque(s: String): Type = {
    def v(k: Int) = V(Loc.builtin, -(math.abs(s.hashCode % 100000) * 4 + k), Some(Local("K")),
                      Bound, Rho(Loc.builtin))
    AppT(VarT(v(1)), VarT(v(2)))
  }

  private def parseSet(s: String): List[Type] =
    s.split("; ").toList.filter(_.trim.nonEmpty).map(t => parseConstraint(t).getOrElse(opaque(t)))

  private final case class Group(module: String, binding: String,
                                 qs: List[Type], ws: List[Type], ds: List[Type])

  private def readRecords(f: File): List[Group] = {
    val src = Source.fromFile(f, "UTF-8")
    val rows = try src.getLines().toList finally src.close()
    // group by (module, binding, givens) exactly as the oracle does: one group is one
    // id-universe of one signature (the same signature checked in two importing modules
    // gets two groups, alpha-variants of each other)
    val groups = scala.collection.mutable.LinkedHashMap[(String, String, String), (List[Type], List[Type])]()
    val qOf    = scala.collection.mutable.HashMap[(String, String, String), List[Type]]()
    for (line <- rows if line.nonEmpty) {
      val c = line.split("\t", -1)
      if (c.length >= 4) {
        val (mod, binding, wanted, givens) = (c(0), c(1), c(2), c(3))
        val free = if (c.length > 4) c(4) else ""
        val key = (mod, binding, givens)
        val (ws, ds) = groups.getOrElse(key, (Nil, Nil))
        val w  = parseConstraint(wanted)
        val dd = parseSet(free).filter(_.isInstanceOf[Part])
        groups(key) = (ws ++ w.toList, (ds ++ dd).distinct)
        qOf.getOrElseUpdate(key, parseSet(givens))
      }
    }
    groups.toList.map { case ((mod, b, g), (ws, ds)) => Group(mod, b, qOf((mod, b, g)), ws, ds) }
  }

  /** `pxs` -- the variables `unbindExists(Free, ...)` minted for THIS residual -- is what
    * `SigEntail.check` reads rigidity off.  In the probe's records that is exactly the
    * `A`-flavoured (and bare-`Free`) variables, which is the rule `sigcheck.py` uses too;
    * `sks` is every skolem, since the probe records no skolem list and the corpus has no
    * foreign skolem (a nested signature's own variables are its own). */
  private def varsOf(ts: List[Type]): List[TypeVar] = ts.flatMap(Type.typeVars(_).toList).distinct
  private def pxsOf(ts: List[Type]): List[TypeVar] =
    varsOf(ts).filter(v => v.ty != Skolem && v.ty != Bound)
  private def sksOf(ts: List[Type]): List[TypeVar] = varsOf(ts).filter(_.ty == Skolem)

  private def verdictOf(g: Group): (String, String) =
    SigEntail.check(g.qs, g.ws, g.ds, sksOf(g.qs ++ g.ws ++ g.ds), pxsOf(g.qs ++ g.ws ++ g.ds)) match {
      case SigEntail.Ok             => ("ACCEPT", "")
      case SigEntail.NoVerdict(_)   => ("NOVERDICT", "")
      case v: SigEntail.NotEntailed => ("REJECT", v.label.fold("*")(_.toString))
    }

  /** What the engine saw, for a disagreement's message: sizes, the minted set, and the
    * witness.  A differential test whose failure does not say WHY costs a debugging round. */
  private def describe(g: Group): String = {
    val v = SigEntail.check(g.qs, g.ws, g.ds, sksOf(g.qs ++ g.ws ++ g.ds), pxsOf(g.qs ++ g.ws ++ g.ds))
    val head = s"|Q|=${g.qs.length} |W|=${g.ws.length} |ds|=${g.ds.length}"
    v match {
      case x: SigEntail.NotEntailed =>
        head + " witness(true)=" +
          x.witness.filter(_._2).map(_._1.toString).mkString(",") +
          " minted=" + x.minted.length + " wanted=" + SigEntail.render(x.wanted)
      case other => head + " " + other
    }
  }

  private val recordFile  = new File("core/src/test/resources/sigentail/records.tsv")
  private val verdictFile = new File("core/src/test/resources/sigentail/verdicts.tsv")

  property("the corpus: the shipped engine agrees with the committed oracle on all 310 signatures") = secure {
    val groups = readRecords(recordFile)
    val src = Source.fromFile(verdictFile, "UTF-8")
    val expected = try src.getLines().toList.filter(_.nonEmpty).map { l =>
      val c = l.split("\t", -1); ((c(1), c(2)), (c(0), if (c.length > 3) c(3) else ""))
    }.toMap finally src.close()

    // a signature is decided per id-universe and the verdicts are ranked, as the oracle does
    val rank = Map("REJECT" -> 2, "NOVERDICT" -> 1, "ACCEPT" -> 0)
    val got = scala.collection.mutable.HashMap[(String, String), (String, String)]()
    for (g <- groups) {
      val v = verdictOf(g)
      val k = (g.module, g.binding)
      if (!got.contains(k) || rank(v._1) > rank(got(k)._1)) got(k) = v
    }
    val missing = expected.keySet -- got.keySet
    val extra   = got.keySet -- expected.keySet
    val bad = expected.toList.filter { case (k, e) => got.get(k).exists(_ != e) }
      .map { case (k, e) =>
        val g = groups.find(x => (x.module, x.binding) == k).get
        s"${k._1}.${k._2}: oracle $e, engine ${got(k)}   [${describe(g)}]" }
    (expected.nonEmpty ?= true) :| "the verdict resource is empty" &&
    (missing ?= Set.empty[(String, String)]) :| s"signatures the engine never decided: $missing" &&
    (extra   ?= Set.empty[(String, String)]) :| s"signatures not in the oracle's list: $extra" &&
    (bad     ?= Nil) :| s"${bad.length} disagreements:\n" + bad.take(10).mkString("\n")
  }

  /** The counts are READ FROM THE RESOURCE, not written here: the corrections on `sig-fixes`
    * turn 19 of the rejections into acceptances, and a literal in this file would make that
    * merge a test edit.  What the property pins is the invariant that survives any corpus --
    * every line is one of the three verdicts, every signature the resource names is decided
    * once, and the engine's own tally equals the resource's -- and it PRINTS the split so a
    * reader of the log sees what the corpus currently is. */
  property("the corpus: the engine's verdict tally equals the resource's, whatever it is") = secure {
    val src = Source.fromFile(verdictFile, "UTF-8")
    val vs = try src.getLines().toList.filter(_.nonEmpty).map(_.split("\t")(0)) finally src.close()
    val want = vs.groupBy(x => x).view.mapValues(_.size).toMap
    val got = readRecords(recordFile).groupBy(g => (g.module, g.binding)).toList.map { case (_, gs) =>
      val rank = Map("REJECT" -> 2, "NOVERDICT" -> 1, "ACCEPT" -> 0)
      gs.map(g => verdictOf(g)._1).maxBy(rank)
    }.groupBy(x => x).view.mapValues(_.size).toMap
    println("### SIG-3 corpus verdicts: " + vs.length + " signatures " +
            want.toList.sorted.mkString(", "))
    (vs.toSet.subsetOf(Set("ACCEPT", "REJECT", "NOVERDICT")) ?= true) :| vs.toSet.toString &&
    (got ?= want) :| s"engine $got vs resource $want"
  }

  /** THE COST MEASUREMENT design (b4) asks S3 for, in the engine's OWN counter (decision
    * nodes), not the oracle's propagation pops: the two numbers were 8x apart in mismatched
    * units and the budget was set on the wrong one.  It is a property rather than a script so
    * the number cannot go stale: the assertion is that the corpus maximum stays a decimal
    * order of magnitude under the per-class budget. */
  property("cost: the whole corpus stays far under the per-signature budget") = secure {
    val groups = readRecords(recordFile)
    val costs = groups.map { g =>
      SigEntail.check(g.qs, g.ws, g.ds, sksOf(g.qs ++ g.ws ++ g.ds), pxsOf(g.qs ++ g.ws ++ g.ds))
      SigEntail.lastCost
    }
    val nodes = costs.map(_.nodes).sorted
    val models = costs.map(_.models).sorted
    val classes = costs.map(_.classes).max
    val max = nodes.last
    val report = s"decision nodes max $max median ${nodes(nodes.length / 2)} " +
      s"p90 ${nodes((0.9 * nodes.length).toInt)} total ${nodes.sum}; " +
      s"models of Q at one class max ${models.last} median ${models(models.length / 2)}; " +
      s"label classes max $classes; ${groups.length} groups"
    // printed, the way TestTolerantCheck prints its sweep line: a measurement nobody can
    // read from a green tick is a measurement that goes stale
    println("### SIG-3 cost (the engine's own decision-node counter): " + report)
    ((max < 20000L) ?= true) :| report
  }

  /** THE FOREIGN-SKOLEM GUARD (design (a)'s rider, S3 review D4).  A skolem in the wanteds
    * that is NOT this call's and NOT in the givens belongs to an ENCLOSING signature, whose
    * own row facts are absent from `Q`; a counterexample that leans on it may be a lie, so the
    * verdict degrades to NO VERDICT.  The reviewer could not build a PROGRAM that reaches the
    * guard (on the shipped pipeline the enclosing row is still a `Free` meta when the inner
    * signature is checked, so its obligation lands in `ds`), which is exactly why it is tested
    * here at the level the guard is written: hand-built input to `check`.
    *
    * `enc <- (out, f)` with `out` this signature's skolem, `f` minted and `enc` the foreign
    * one is refuted by the model `enc = FALSE, out = TRUE` -- a refutation that assigns the
    * foreign skolem WITHOUT setting it true, which the first draft's `foreign.exists(ones)`
    * test let through as a rejection. */
  private def skv(id: Int, n: String) = V(Loc.builtin, id, Some(Local(n)), Skolem, Rho(Loc.builtin))
  private def mtv(id: Int, n: String) = V(Loc.builtin, id, Some(Local(n)), Ambiguous(Free), Rho(Loc.builtin))

  property("the foreign-skolem guard: a refutation that ASSIGNS one is NO VERDICT") = secure {
    val out = skv(9101, "out")
    val enc = skv(9102, "enc")
    val f   = mtv(9103, "f")
    val w   = Part(Loc.builtin, VarT(enc), List(VarT(out), VarT(f)))
    // `enc` is NOT among this call's skolems -> foreign -> no verdict
    val foreignCase = SigEntail.check(Nil, List(w), Nil, List(out), List(f))
    // the SAME system with `enc` this signature's own -> the rejection stands
    val ownCase     = SigEntail.check(Nil, List(w), Nil, List(out, enc), List(f))
    ((foreignCase match {
       case SigEntail.NoVerdict(why) =>
         ((why contains "enc") ?= true) :| why
       case other => falsified :| ("expected NO VERDICT, got " + other)
     }) &&
     (ownCase match {
       case v: SigEntail.NotEntailed =>
         // and the witness is the FALSE-bit model, which is the point of the widening
         ((v.witness.exists(p => p._1.id == 9102 && !p._2)) ?= true) :| v.witness.toString
       case other => falsified :| ("expected a rejection, got " + other)
     }))
  }

  // ------------------------------------------------------- random systems vs brute force
  /** The JUDGEMENT, enumerated: per label class, for every assignment of the RIGID bits
    * that models `Q`, some assignment of the MINTED bits must model `W`.  This is
    * `SigDecide`'s definition (Lean `sigDecide`), with no propagation and no dedup. */
  private def brute(qs: List[(Int, List[Int], Set[Name])], ws: List[(Int, List[Int], Set[Name])],
                    rigid: List[Int], minted: List[Int], labels: List[Option[Name]]): Boolean = {
    def holds(cs: List[(Int, List[Int], Set[Name])], m: Map[Int, Boolean], lab: Option[Name]): Boolean =
      cs.forall { case (lhs, ps, conc) =>
        val ones = ps.count(m) + (if (lab.exists(conc)) 1 else 0)
        ones <= 1 && ((ones == 1) == m(lhs))
      }
    def assigns(vs: List[Int]): List[Map[Int, Boolean]] =
      vs.foldLeft(List(Map[Int, Boolean]())) { (acc, v) =>
        acc.flatMap(m => List(m + (v -> false), m + (v -> true)))
      }
    labels.forall { lab =>
      assigns(rigid).forall { r =>
        !holds(qs, r.withDefaultValue(false), lab) ||
        assigns(minted).exists(f => holds(ws, (r ++ f).withDefaultValue(false), lab))
      }
    }
  }

  private val labA = Local("a")
  private val labB = Local("b")

  /** A small system: at most 5 variables (each rigid or minted), at most 4 constraints, at
    * most 2 literal labels -- the shape design (e) 2a asks for. */
  private val genSystem: Gen[(List[Type], List[Type], List[TypeVar], List[TypeVar])] = for {
    nv    <- Gen.choose(1, 5)
    nq    <- Gen.choose(0, 2)
    nw    <- Gen.choose(1, 2)
    flags <- Gen.listOfN(nv, Gen.oneOf(true, false))           // true = minted
    qs    <- Gen.listOfN(nq, genConstraint(nv))
    ws    <- Gen.listOfN(nw, genConstraint(nv))
  } yield {
    // a minted variable may not occur in the givens (`F ∩ voc(Q) = ∅` is an invariant of the
    // judgement), so a given mentioning one is rebuilt over the rigid variables only
    val rigidIx  = (0 until nv).filter(i => !flags(i)).toList
    val mintedIx = (0 until nv).filter(i => flags(i)).toList
    val vs = (0 until nv).map(i =>
      V(Loc.builtin, 1000 + i, Some(Local("x" + i)),
        if (flags(i)) Ambiguous(Free) else Skolem, Rho(Loc.builtin))).toList
    def build(c: (Int, List[Int], Set[Name]), onlyRigid: Boolean): Option[Type] = {
      val keep = if (onlyRigid) rigidIx.toSet else (0 until nv).toSet
      if (!keep(c._1)) None
      else {
        val ps = c._2.filter(keep).distinct.map(i => VarT(vs(i))) ++
                 (if (c._3.isEmpty) Nil else List(ConcreteRho(Loc.builtin, c._3)))
        Some(Part(Loc.builtin, VarT(vs(c._1)), ps))
      }
    }
    (qs.flatMap(c => build(c, true)), ws.flatMap(c => build(c, false)),
     rigidIx.map(vs), mintedIx.map(vs))
  }

  private def genConstraint(nv: Int): Gen[(Int, List[Int], Set[Name])] = for {
    lhs  <- Gen.choose(0, nv - 1)
    k    <- Gen.choose(0, 3)
    ps   <- Gen.listOfN(k, Gen.choose(0, nv - 1))
    conc <- Gen.oneOf(Set[Name](), Set[Name](labA), Set[Name](labB), Set[Name](labA, labB))
  } yield (lhs, ps, conc)

  /** The engine against the enumeration.  A NO VERDICT is not a disagreement (it claims
    * nothing) but the generator's systems are far below every budget, so it should not
    * happen; it is reported as a label rather than a failure. */
  property("random systems: the engine agrees with exhaustive enumeration") =
    forAll(genSystem) { case (qs, ws, rigid, minted) =>
      val pxs = minted
      val sks = rigid
      val ids = (qs ++ ws).flatMap(Type.typeVars(_).toList).map(_.id).distinct
      def encode(t: Type): (Int, List[Int], Set[Name]) = t match {
        case Part(_, VarT(v), ps) =>
          (v.id, ps.collect { case VarT(u) => u.id },
           ps.collect { case ConcreteRho(_, fs) => fs }.foldLeft(Set[Name]())(_ ++ _))
        case _ => (-1, Nil, Set())
      }
      val qe = qs.map(encode)
      val we = ws.map(encode)
      val labels: List[Option[Name]] =
        ((qe ++ we).flatMap(_._3).distinct.map(Some(_)) :+ None)
      val truth = brute(qe, we, rigid.map(_.id), minted.map(_.id), labels)
      SigEntail.check(qs, ws, Nil, sks, pxs) match {
        case SigEntail.Ok             => (truth ?= true)  :| s"engine ACCEPT, truth $truth: $qs |- $ws"
        case _: SigEntail.NotEntailed => (truth ?= false) :| s"engine REJECT, truth $truth: $qs |- $ws"
        case SigEntail.NoVerdict(why) => Prop.passed :| ("no verdict: " + why)
      }
    }

  /** The `Part`-shape contract of design (e) 2b, as three properties rather than a promise.
    * A repeated variable part NORMALISES (it forces that variable empty); the empty row on
    * the left normalises to "every part is empty"; a NON-EMPTY literal column set on the
    * left is dropped by name, and the drop forbids one verdict -- here an ACCEPT becomes a
    * NO VERDICT. */
  property("encoding contract: a repeated part forces that variable empty") = secure {
    val sk = V(Loc.builtin, 9001, Some(Local("r")), Skolem, Rho(Loc.builtin))
    val f  = V(Loc.builtin, 9002, Some(Local("f")), Ambiguous(Free), Rho(Loc.builtin))
    // `sk <- (f, f)` forces f empty, hence sk empty; with no givens `sk` is arbitrary,
    // so the signature is NOT entailed and the check must say so rather than merge.
    val w  = Part(Loc.builtin, VarT(sk), List(VarT(f), VarT(f)))
    SigEntail.check(Nil, List(w), Nil, List(sk), List(f)) match {
      case _: SigEntail.NotEntailed => proved
      case other                    => falsified :| ("expected a rejection, got " + other)
    }
  }

  property("encoding contract: the empty row on the left normalises, and decides") = secure {
    val out = V(Loc.builtin, 9011, Some(Local("out")), Skolem, Rho(Loc.builtin))
    val e   = V(Loc.builtin, 9012, Some(Local("e")), Ambiguous(Free), Rho(Loc.builtin))
    val f   = V(Loc.builtin, 9013, Some(Local("f")), Ambiguous(Free), Rho(Loc.builtin))
    val d   = V(Loc.builtin, 9014, Some(Local("d")), Ambiguous(Free), Rho(Loc.builtin))
    val r   = V(Loc.builtin, 9015, Some(Local("r")), Skolem, Rho(Loc.builtin))
    // out <- (f, e, d) with (||) <- (f, e) in the ds half and d determined by r:
    // f = e = empty, so out = d = r, and `out` unconstrained is NOT entailed.
    val w    = Part(Loc.builtin, VarT(out), List(VarT(f), VarT(e), VarT(d)))
    val dsEq = Part(Loc.builtin, ConcreteRho(Loc.builtin, Set()), List(VarT(f), VarT(e)))
    val dsR  = Part(Loc.builtin, VarT(r), List(VarT(d)))
    val withDs = SigEntail.check(Nil, List(w), List(dsEq, dsR), List(out, r), List(e, f, d))
    // without the `ds` half the same obligation is satisfied by f = out, e = d = empty
    val alone  = SigEntail.check(Nil, List(w), Nil, List(out, r), List(e, f, d))
    ((withDs match { case _: SigEntail.NotEntailed => proved
                     case o => falsified :| ("with ds: expected a rejection, got " + o) }) &&
     (alone match { case SigEntail.Ok => proved
                    case o => falsified :| ("rs alone: expected acceptance, got " + o) }))
  }

  property("encoding contract: a non-empty literal set on the left is dropped, and forbids ACCEPT") = secure {
    val sk = V(Loc.builtin, 9021, Some(Local("r")), Skolem, Rho(Loc.builtin))
    val f  = V(Loc.builtin, 9022, Some(Local("f")), Ambiguous(Free), Rho(Loc.builtin))
    val g  = V(Loc.builtin, 9023, Some(Local("g")), Ambiguous(Free), Rho(Loc.builtin))
    val w  = Part(Loc.builtin, VarT(sk), List(VarT(f)))                        // sk = f
    val bad = Part(Loc.builtin, ConcreteRho(Loc.builtin, Set(labA)), List(VarT(f), VarT(g)))
    SigEntail.check(Nil, List(w), List(bad), List(sk), List(f, g)) match {
      case SigEntail.NoVerdict(why) => (why.contains("literal column set") ?= true) :| why
      case other                    => falsified :| ("expected NO VERDICT, got " + other)
    }
  }
}
