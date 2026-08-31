package com.clarifi.reporting.ermine.surface

import com.clarifi.reporting.ermine.Fixity

/** The LSP-shaped surface AST (tracker/LSP-ROADMAP.md, Stage 1 item 2.1).
  *
  * What the user WROTE, not what it means: no name resolution, no
  * desugaring, no fixity-driven tree shape.  Spans on every node; every
  * occurrence keeps its spelling as written (alias affix, parenthesized
  * operator form); operator chains are FLAT and re-associated by a later
  * pass (3.3); sugar (do, list/brace literals, records, relational
  * envelopes, negation) is represented, not expanded (3.4); error nodes
  * are designed in now and produced by recovery in Stage 2.
  *
  * Statement order is load-bearing (gatherBindings groups only adjacent
  * equations) — SModule.statements preserves source order verbatim, and
  * where-clauses stay attached to their equation rather than pre-folding
  * into Let.
  */

// ---------------------------------------------------------------- locations

/** Half-open span in one file; 1-based lines and columns, matching Pos.
  * The file is uniform per tree and lives on SModule. */
final case class Span(startLine: Int, startCol: Int, endLine: Int, endCol: Int) {
  def contains(line: Int, col: Int): Boolean =
    (line > startLine || (line == startLine && col >= startCol)) &&
    (line < endLine || (line == endLine && col < endCol))
  def to(other: Span): Span = Span(startLine, startCol, other.endLine, other.endCol)
}

/** Where a node came from.  Parsing only makes Real spans; the desugarer
  * (3.4) marks synthesized nodes with their origin instead of borrowing
  * a child's location (Decision h) — synthesized nodes are never
  * hit-tested, but still render "file:line:col:" in reports. */
sealed abstract class SLoc { def span: Span }
final case class Real(span: Span) extends SLoc
final case class Synth(origin: Span) extends SLoc { def span: Span = origin }

// -------------------------------------------------------------------- names

/** How a name occurrence was written. */
sealed abstract class NameForm
case object Plain          extends NameForm  // foo, Foo.bar is not a form — dots are part of the spelling
case object ParenOp        extends NameForm  // (++)
case object ParenPrefixOp  extends NameForm  // (prefix !)     [binder or reference]
case object ParenPostfixOp extends NameForm  // (postfix !)
/** (infixl 5 op) — a binder that also declares fixity; the declared
  * fixity governs later siblings only (Decision a). */
final case class ParenFixityBinder(declared: Fixity) extends NameForm

/** A name occurrence as written: spelling INCLUDES any `_Module` affix
  * (the affix is part of resolution — tracker/desugar-hooks.md channel A
  * — and of the fused pipeline's canonical keys).  `fixity` is the
  * SYNTACTIC bucket the occurrence was read under (Idfix for identifiers;
  * the op lexer's class for operators), not a resolved precedence. */
final case class SName(spelling: String, form: NameForm, fixity: Fixity, span: Span)

// --------------------------------------------------------------- op chains

/** Syntactic position of an operator token in a chain — computable
  * without any fixity environment (ParsingUtil's operand-position vs
  * post-operand-position split). */
sealed abstract class PosClass
case object OperandPos     extends PosClass  // prefix candidate
case object PostOperandPos extends PosClass  // infix or postfix candidate

final case class OpOcc(name: SName, posClass: PosClass)

/** A flat operator chain: operands and operator occurrences in source
  * order.  Re-association (3.3) turns this into a tree using the
  * positional fixity environment; until then no grammar decision has
  * been made.  A chain with no OpOccs is just its operand. */
final case class Chain[A](loc: SLoc, items: List[Either[A, OpOcc]])

// -------------------------------------------------------------------- terms

sealed abstract class STerm { def loc: SLoc }

final case class SVar(name: SName) extends STerm { def loc: SLoc = Real(name.span) }
final case class SLitInt(loc: SLoc, value: Int)        extends STerm
final case class SLitLong(loc: SLoc, value: Long)      extends STerm
final case class SLitByte(loc: SLoc, value: Byte)      extends STerm
final case class SLitShort(loc: SLoc, value: Short)    extends STerm
final case class SLitString(loc: SLoc, value: String)  extends STerm
final case class SLitChar(loc: SLoc, value: Char)      extends STerm
final case class SLitFloat(loc: SLoc, value: Float)    extends STerm
final case class SLitDouble(loc: SLoc, value: Double)  extends STerm
final case class SLitDate(loc: SLoc, value: java.util.Date) extends STerm

final case class SApp(fun: STerm, arg: STerm) extends STerm {
  def loc: SLoc = Real(fun.loc.span to arg.loc.span)
}
final case class SLam(loc: SLoc, params: List[SPat], body: STerm)   extends STerm
final case class SSig(loc: SLoc, term: STerm, annot: STy)           extends STerm
final case class SChain(chain: Chain[STerm]) extends STerm { def loc: SLoc = chain.loc }
/** Leading '-': applies Builtin.primNeg to the ENTIRE re-associated
  * chain, not the nearest operand (pinned by value in TestStage1Pins). */
final case class SNeg(loc: SLoc, minus: Span, operand: STerm)       extends STerm
final case class SParen(loc: SLoc, inner: STerm)                    extends STerm
final case class STuple(loc: SLoc, elems: List[STerm])              extends STerm
final case class STupleSection(loc: SLoc, arity: Int)               extends STerm  // (,,)
final case class SCase(loc: SLoc, scrutinee: STerm, alts: List[SAlt]) extends STerm
final case class SLet(loc: SLoc, statements: List[SStatement], body: STerm) extends STerm
final case class SDo(loc: SLoc, stmts: List[SDoStmt])               extends STerm
final case class SListLit(loc: SLoc, elems: List[STerm], suffix: Option[String])  extends STerm
final case class SBraceLit(loc: SLoc, elems: List[STerm], suffix: Option[String]) extends STerm
final case class SRecordLit(loc: SLoc, fields: List[(STerm, STerm)]) extends STerm
final case class SRelEnvelope(loc: SLoc, arrows: List[SRelArrow])   extends STerm
final case class SHole(loc: SLoc)                                   extends STerm
final case class SRemember(loc: SLoc, inner: STerm)                 extends STerm  // ?[e]
/** Recovery product (Stage 2); carries the skipped extent. */
final case class SErrorTerm(loc: SLoc, message: String)             extends STerm

final case class SAlt(loc: SLoc, pattern: SPat, body: STerm, where: Option[SWhere])

sealed abstract class SDoStmt { def loc: SLoc }
final case class SDoBind(loc: SLoc, binder: SPat, arrow: Span, rhs: STerm) extends SDoStmt
final case class SDoExpr(term: STerm) extends SDoStmt { def loc: SLoc = term.loc }

/** [| ... |] arrows by kind: the fixity/referent override region covers
  * combine and filter arms ONLY, never rename (tracker/desugar-hooks.md,
  * channel R). */
sealed abstract class SRelArrow { def loc: SLoc }
final case class SRenameArrow(loc: SLoc, to: SName, from: SName)      extends SRelArrow
final case class SCombineArrow(loc: SLoc, as: SName, expr: STerm)     extends SRelArrow
final case class SFilterArrow(expr: STerm) extends SRelArrow { def loc: SLoc = expr.loc }

// ----------------------------------------------------------------- patterns

sealed abstract class SPat { def loc: SLoc }

final case class SPVar(name: SName) extends SPat { def loc: SLoc = Real(name.span) }
final case class SPWildcard(loc: SLoc)                              extends SPat
final case class SPLitInt(loc: SLoc, value: Int)                    extends SPat
final case class SPLitLong(loc: SLoc, value: Long)                  extends SPat
final case class SPLitByte(loc: SLoc, value: Byte)                  extends SPat
final case class SPLitShort(loc: SLoc, value: Short)                extends SPat
final case class SPLitString(loc: SLoc, value: String)              extends SPat
final case class SPLitChar(loc: SLoc, value: Char)                  extends SPat
final case class SPLitFloat(loc: SLoc, value: Float)                extends SPat
final case class SPLitDouble(loc: SLoc, value: Double)              extends SPat
final case class SPLitDate(loc: SLoc, value: java.util.Date)        extends SPat
/** Constructor application: `Just x`, `(h :: t)` comes via SPChain. */
final case class SPApp(con: SName, args: List[SPat]) extends SPat {
  def loc: SLoc = Real(args.foldLeft(con.span)((s, p) => s to p.loc.span))
}
final case class SPChain(chain: Chain[SPat]) extends SPat { def loc: SLoc = chain.loc }
final case class SPParen(loc: SLoc, inner: SPat)                    extends SPat
final case class SPTuple(loc: SLoc, elems: List[SPat])              extends SPat
final case class SPList(loc: SLoc, elems: List[SPat])               extends SPat  // [p, q] sugar node
final case class SPAs(loc: SLoc, binder: SName, inner: SPat)        extends SPat  // v@p
final case class SPStrict(loc: SLoc, inner: SPat)                   extends SPat  // !p
final case class SPLazy(loc: SLoc, inner: SPat)                     extends SPat  // ~p
final case class SPSig(loc: SLoc, inner: SPat, annot: STy)          extends SPat
final case class SPError(loc: SLoc, message: String)                extends SPat

// -------------------------------------------------------------------- types

sealed abstract class STy { def loc: SLoc }

/** Variable or constructor — lexically decided at rename (lowercase head
  * = variable), spelling kept as written including qualification. */
final case class STyName(name: SName) extends STy { def loc: SLoc = Real(name.span) }
final case class STyApp(fun: STy, arg: STy) extends STy {
  def loc: SLoc = Real(fun.loc.span to arg.loc.span)
}
/** Type-level chains include `->`, `=>`, `<-` as builtin pseudo-fixity
  * ops (0R, 0R, 1N); Forall/Part construction happens post-rename. */
final case class STyChain(chain: Chain[STy]) extends STy { def loc: SLoc = chain.loc }
final case class STyParen(loc: SLoc, inner: STy)                    extends STy
final case class STyTuple(loc: SLoc, elems: List[STy])              extends STy
final case class STyList(loc: SLoc, elem: Option[STy])              extends STy  // [a] / []
final case class STyRowBrace(loc: SLoc, dots: Boolean, inner: List[STy]) extends STy  // {..r} / {a, b}
final case class STyRowBracket(loc: SLoc, dots: Boolean, inner: List[STy]) extends STy // [..r]
final case class STyBanana(loc: SLoc, dots: Boolean, inner: List[STy]) extends STy  // (| ... |)
final case class STyForall(loc: SLoc, kindBinders: List[SName], typeBinders: List[SBinder], body: STy) extends STy
final case class STyExists(loc: SLoc, binders: List[SBinder], body: List[STy]) extends STy
/** Annotation-level `some a b.` quantifier (TypeParsers.annot). */
final case class STySome(loc: SLoc, kindBinders: List[SName], binders: List[SBinder], body: STy) extends STy
final case class STyError(loc: SLoc, message: String)               extends STy

/** `(a : kind)` or bare `a` in binder position. */
final case class SBinder(name: SName, kind: Option[STy])

// --------------------------------------------------------------- statements

sealed abstract class SStatement { def loc: SLoc }

/** Fixity declarations stay IN the tree (the fused pipeline drops them
  * after mutating parse state) — the re-associator's positional fixity
  * environment is built from these. */
final case class SFixity(loc: SLoc, fixity: Fixity, typeLevel: Boolean, ops: List[SName]) extends SStatement

final case class SFieldStatement(loc: SLoc, names: List[SName], ty: STy) extends SStatement
final case class STableStatement(loc: SLoc, dbName: Option[String], names: List[SName], ty: STy) extends SStatement
final case class STypeAlias(loc: SLoc, name: SName, kindArgs: List[SName], typeArgs: List[SBinder], body: STy) extends SStatement
final case class SDataStatement(loc: SLoc, name: SName, kindArgs: List[SName], typeArgs: List[SBinder],
                                constructors: List[SConDef]) extends SStatement
/** One data constructor: optional per-constructor forall, then fields. */
final case class SConDef(loc: SLoc, exists: List[SBinder], name: SName, fields: List[STy])

final case class SClassStatement(loc: SLoc, name: SName, kindArgs: List[SName], typeArgs: List[SBinder],
                                 context: List[STy], body: List[SStatement]) extends SStatement

final case class SPrivateBlock(loc: SLoc, statements: List[SStatement])  extends SStatement
final case class SDatabaseBlock(loc: SLoc, dbName: String, statements: List[SStatement]) extends SStatement
final case class SForeignBlock(loc: SLoc, statements: List[SForeign])    extends SStatement

/** Foreign sub-forms carry the class name as STRING + span only:
  * Class.forName moves out of parsing entirely (3.2b). */
sealed abstract class SForeign { def loc: SLoc }
final case class SForeignData(loc: SLoc, name: SName, args: List[SBinder], className: String, classSpan: Span) extends SForeign
final case class SForeignFunction(loc: SLoc, name: SName, ty: STy, className: String, classSpan: Span, member: String, memberSpan: Span) extends SForeign
final case class SForeignMethod(loc: SLoc, name: SName, ty: STy, member: String, memberSpan: Span) extends SForeign
final case class SForeignValue(loc: SLoc, name: SName, ty: STy, className: String, classSpan: Span, member: String, memberSpan: Span) extends SForeign
final case class SForeignConstructor(loc: SLoc, name: SName, ty: STy) extends SForeign
final case class SForeignSubtype(loc: SLoc, name: SName, ty: STy) extends SForeign
/** `private <foreign statements>` inside a foreign block (per-item or
  * laid-out group; the old grammar reads both through one laidout). */
final case class SForeignPrivate(loc: SLoc, statements: List[SForeign]) extends SForeign

final case class SSigStatement(loc: SLoc, names: List[SName], annot: STy) extends SStatement
/** One equation: `f p1 p2 = body [where ...]`.  Adjacent equations of one
  * name merge at rename (gatherBindings parity) — the tree keeps them
  * separate and ordered. */
final case class SEquation(loc: SLoc, name: SName, args: List[SPat], body: STerm, where: Option[SWhere]) extends SStatement
/** A where block is its OWN node attached to its equation or alt — never
  * pre-folded into Let (the body/where parse-order semantics live in the
  * renamer, not the tree shape). */
final case class SWhere(loc: SLoc, statements: List[SStatement])

final case class SErrorStatement(loc: SLoc, message: String) extends SStatement

// ------------------------------------------------------------------- module

final case class SImportItem(name: SName, isType: Boolean, renameTo: Option[SName])
final case class SImport(loc: SLoc, isExport: Boolean, module: String, moduleSpan: Span,
                         as: Option[SName],
                         items: Option[(Boolean, List[SImportItem])]) // (isUsing, items); None = open import
final case class SHeader(loc: SLoc, name: String, nameSpan: Option[Span],
                         explicitLayout: Boolean, imports: List[SImport])

final case class SModule(file: String, header: SHeader, statements: List[SStatement])
