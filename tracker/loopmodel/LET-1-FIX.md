# LET-1 — a `let`-bound signature reaches the type checker again (regression, fixed)

**Status: IMPLEMENTED AND GATED in the worktree `ermine-scala-wt-let` (branch
`let-signatures`, from `a15a97e`).  No commits.**  Brief:
`tracker/loopmodel/briefs/brief-LET-1.md`; the evidence that opened it is
`../ermine-scala-wt-sig/tracker/loopmodel/SIG-1-SURVEY.md` §6 and `SIG-1-REVIEW.md`
(the `Lower.scala` paragraph), both read-only from here.

## 0. The defect, reproduced first

Measured on the unfixed tree (`a15a97e` + the brief, `-Dermine.useInterface=false`,
probe modules in the scratch `probes/`):

| probe | program | BEFORE | AFTER |
|---|---|---|---|
| P1 | `r = let g : Int -> Int` / `g x = x` / `in g "hello"` | **LOADS**, and `r : String = "hello"` | REJECTED `5:8: error: failed to unify type Int with type String` |
| P2 | the same, `where`-bound | REJECTED `3:5: error: failed to unify type Int with type String` | unchanged, same position and text |
| P3 | a `where` (with a signature) inside a `let` block | **LOADS** | REJECTED `6:8:` (same message) |
| P4 | a `let` (with a signature) inside a `where` body | **LOADS** | REJECTED `3:5:` (same message) |
| P5 | `r = let g : Int -> Int` / `in 1` — a signature with no equation | **LOADS** (dropped in silence) | REJECTED `3:9: missing definition` |
| P6 | the same, `where`-bound | REJECTED `4:9: missing definition` | unchanged, same position and text |
| P7 | an honest polymorphic let signature (`g : a -> a`) used at two types | LOADS | LOADS |
| P8 | `let g : a -> Int` / `g x = x + 1` — signature more general than the body | **LOADS** | REJECTED `6:9: error: failed to unify type !a with type Int` (the skolem) |
| P9 | `sig03`'s row twin (declared context too weak) | REJECTED `10:12` (row partitions unsatisfiable, at the CALL) | **ACCEPTED** — see §4c, a KNOWN HOLE |

P1 is the clean statement of the defect: a `let`-bound signature could neither restrict
nor widen, and the compiler never said so — it was not even consulted.

## 1. The diff

Three compiler files, three test files, one editor fixture, one harness; plus seven new
corpus modules and their documentation (§5).

| file | lines | what |
|---|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/rename/Lower.scala` | imports :3-9; `Ctx.resetKindScope` :150-156; `SLet` :202-204; the block machinery :302-401 (`BlockEnv`, `ctxEnv`, `collectBlock`, `pairSigs`, `bindings`); the object comment :19-31 | the shared implementation; `SLet` now fills BOTH halves of `Let` |
| `core/src/main/scala/com/clarifi/reporting/ermine/rename/NewPipeline.scala` | imports :3-5; `resetKindScope` wiring :175-177 and :245; the assembly comment :278-281; `blockEnv`/`collectBlock`/`pairSigs` :330-349 (the old `collectBlock`, `pairSigs` and `lowerLet` deleted: 58 lines out, 20 in) | the module path delegates to `Lower`, supplying its own refusal channel and tolerance bracket |
| `core/src/main/scala/com/clarifi/reporting/ermine/session/TolerantCheck.scala` | :320-333 | the comment that asserted the opposite ("`lowerLet` makes ... of a SIGNED `let`/`where` binding" — false for `let`) |
| `scalacheck-binding/src/main/scala/TestLetSignatures.scala` | NEW, 150 | the pins of §3 |
| `scalacheck-binding/src/main/scala/TestTolerantCheck.scala` | `kindsBody` :187-190, the 6.2 property :204-212 | the `sigLet` twin of `sigWhere` (hover shows the DECLARED type) |
| `scalacheck-binding/src/main/scala/TestScopes.scala` | :102-110 | the signed-let test kept, with a comment saying what it now exercises |
| `tracker/lsp-tests/Locals.e` | :36-41 appended | a signed `let` in the editor fixture (appended, so no existing line number moves) |
| `tracker/tools/lsp-client.py` | :873-885 | three hover checks on it (signature, def-site, use) |
| `core/examples/Lang/LetSignatures.e` | NEW, 157 | §5: the positive corpus module |
| `core/examples/shouldfail/let01..let05*.e` | NEW, 134 total | §5: error class 7, the five negatives |
| `core/examples/shouldfail-controls/control09_let_signatures.e` | NEW, 45 | §5: their control |
| `core/examples/Lang/README.md`, `core/examples/shouldfail/RESULTS.md` | +1 row / +2 counts, +34 | §5: the corpus documentation |

### The two drop sites, before

```scala
    case SLet(l, ss, b)     =>                     // Lower.scala:185-187
      val (implicits, _) = bindings(ss, c)
      Let(c.pos(l.span), implicits, Nil, term(b, c))
...
  private def bindings(ss: List[SStatement], c: Ctx)   // :287
      : (List[ImplicitBinding], List[Nothing]) = {
      ...
      case Some(SWhere(wl, wss)) =>                // :298-299, the second site
        val (wis, _) = bindings(wss, c)
        Let(c.pos(wl.span), wis, Nil, term(body, c))
      ...
      case _: SSigStatement => ()  // 4.1
```

The second component was not discarded, it was EMPTY BY CONSTRUCTION: the return type was
`List[Nothing]` and the signature case built nothing.  `// 4.1` is gone, the return type is
`List[ExplicitBinding]`, and both sites now pass the explicit bindings on.

## 2. The shared implementation

Note (review edit 1): in the `let` channel a refusal is RECORDED through `Ctx.diags` and lowering
continues (an interleaved equation is still merged into its group), whereas the module path's
`Refusal` aborts the statement. The message is the same; `TestLetSignatures` pins the new let-block
interleaving refusal (`interleaved equations for f`).

`Lower` owns the three steps and `NewPipeline` calls them (`Lower.scala:293-393`):

* `Lower.collectBlock(ss, c, env)` — group the equations (adjacent equations of one name
  merge into one binding's alts; equations of one name must be consecutive among
  equations), lower each signature to a `Type` keyed by the binder's `V`, and recurse
  through `bindings` for a `where` attached to an equation.  Returns the groups (each with
  the first head's `Span`) and the signatures, UNPAIRED — which is what the module's top
  level needs, because a top-level signature pairs module-wide across adjacency blocks
  (`private map : t` with its equations outside the block), not inside one.
* `Lower.pairSigs(im, sigs, env)` — a signature whose `V` has a binding becomes an
  `ExplicitBinding(loc, v, Annot.plain(loc, ty), alts)` and that binding leaves the
  implicit list; a signature with no binding is refused, `"missing definition"`, at the
  signature's own span.
* `Lower.bindings(ss, c, env)` — `collectBlock` then `pairSigs`, which is exactly what both
  halves of `Let(pos, implicits, explicits, body)` want.  This is what `NewPipeline.lowerLet`
  was; `lowerLet` is deleted and its one call site (a `where` on an equation) is inside the
  shared `collectBlock` now, so a `where` nested in a `let` gets the same treatment as a
  `where` on a top-level equation.

`NewPipeline.assemble` keeps its own `collectBlock`/`pairSigs` names as one-line
delegations, so `bindingBlock` and the final top-level pairing read as they did.

### `Lower.BlockEnv`: the refusal channel, and why there are two

The shared code cannot throw `NewPipeline.Refusal` (it is private to `NewPipeline`, and
`Lower` must not depend on the module reader), and the module path must keep refusing
BYTE-IDENTICALLY.  So the two things a block needs from its caller are an interface:

```scala
  trait BlockEnv {
    def refuse(sp: Span, message: String): Unit
    def guarded[A](sp: Span)(a: => A): Option[A]
  }
```

* `NewPipeline` supplies `throw Refusal(sp, message)` and its own `guard` — so a top-level
  or `where` refusal is rendered by `read` exactly where it was, and a tolerant (editor)
  read still loses one statement rather than the file.  **Nothing changes on that path.**
* `Lower.ctxEnv(c)` — used by `term`'s `SLet` case, i.e. by every `let` block and every
  `where` inside one — records `Renamer.Diag(sp, message)` in the `Ctx`'s diagnostic sink.
  That is a NORMAL diagnostic in all three readers: the batch reader appends the sink to
  `ds` and `checkpoint()` throws the same `Death` with the same `render`, the editor collects
  it as a `Phase.Lower` diagnostic (a squiggle at the signature), and `replTerm` dies on it
  with the message at its position.  It does not catch anything, so an `Unsupported` from
  a nested statement still rides out to the enclosing statement's guard.

The message is `pairSigs`' own, unchanged, so the `let` and `where` spellings of a missing
definition now render the same text at their own spans (P5/P6 above, pinned in §3.4).
One ordering nuance, which is the existing policy and not new: an assemble refusal is
thrown during assembly and a `let`-block diagnostic is read out after it, so a module with
both reports the assemble one — the same order the `Phase` comment already describes.

### The kind scope

`NewPipeline` called `tctx.resetKindScope()` before `TyLower.annot` for a signature
statement, and `walk` calls it per top-level statement; it clears the map of NAMED KIND
VARIABLES, which are scoped to a statement (`TyLower.scala:117-126`).  `Lower.Ctx` had no
way to reach it, so the shared code reaches it through a second wired hook next to
`lowerAnnot`:

```scala
    var resetKindScope: () => Unit = () => ()      // Lower.Ctx
    lctx.resetKindScope = () => tctx.resetKindScope()   // NewPipeline.read, and replTerm
```

It is NOT unnecessary, and it is not a no-op for local signatures: the same shared code now
lowers top-level, `where`- and `let`-block signatures, and the top-level behaviour had to
stay what it was (a signature opens a fresh named-kind scope).  The consequence for a local
signature is the one `where` already had: a named kind variable in a local signature does
not share with the enclosing statement's, because the reset clears the whole map.  `replTerm`
wires the hook the same way, so a signature in a REPL `let` scopes its kind variables like
any other; a `Ctx` built by hand (`TestLower`) leaves the default no-op and never reaches
it, because none of its fixtures has a signature to lower.

## 3. The pins

New suite `scalacheck-binding/src/main/scala/TestLetSignatures.scala` ("Ermine let
signatures"), plus two edits in existing suites and one in the LSP fixture.

| # | pin | property |
|---|---|---|
| 1 | the signature RESTRICTS, in all four block shapes | `a let signature restricts its binding: Int -> Int refuses a String`; `the where twin is refused as it always was`; `a where inside a let block is checked too (the second drop site)`; `a let inside a where body is checked too` |
| 2 | an HONEST signature is not in the way | `a correct polymorphic let signature is honoured at two types` (`g : a -> a` used at `Int` and `Bool`), and its `where` twin |
| 3 | a signature the body cannot deliver | `a let signature more general than its body is refused` (`g : a -> Int`, `g q = q + 1`) |
| 4 | a signature with no definition | `a let signature with no definition is refused like a where's` — asserts the MESSAGE and the ANCHOR of both spellings: `missing definition` at the signature's own line and column 9 in each |
| 5 | the row twin, a KNOWN HOLE | `KNOWN HOLE: a let signature with a too-weak context is ACCEPTED` — §4c |
| 6 | the editor | `TestTolerantCheck` "6.2: every LET and WHERE binder gets a type" gains `sl` (a signed `let`) beside `sw` (a signed `where`), both `Bool -> Bool` AS DECLARED; `tracker/lsp-tests/Locals.e` gains `sigLetLocal`, and `lsp-client.py` three hovers on it |
| 7 | `TestScopes` | the signed-let test at :104 kept, with a comment that it now exercises the checker's explicit-binding path rather than only the pairing |

## 4. The measurement: what the fix STARTS checking

### 4a. The census, before any run

A scripted scan of every `.e` file in `core/examples` and the stdlib
(`core/src/main/resources/modules`) — 359 files — for signature statements INSIDE a `let`
block (the block's column computed from the `let` keyword, statements at that column,
block closed by the first line left of it) finds **three**, in two stdlib modules, and
**none** in `core/examples`:

| site | signature | definition |
|---|---|---|
| `core/src/main/resources/modules/Layout/Column/Unsafe.e:102` (in `single'`) | `unsafePres : Presentation r a -> Presentation r b` | `unsafePres = unsafeCoerce` |
| `core/src/main/resources/modules/Layout/Column/Unsafe.e:113` (in `hc'`) | `unsafePres : Presentation r a -> Presentation r b` | `unsafePres = unsafeCoerce` |
| `core/src/main/resources/modules/List/Util.e:37` (in `median`) | `m : Double` | `m = getJust ' "Invalid index" ' at midPoint sorted` |

A second scan for the SECOND drop site — a `where` (with a signature) attached to an
equation inside a `let` block — finds **zero**.  A third for interleaved `let` equations
(§7.2) finds **zero**.  So the whole shipped exposure of the stub is three local
signatures in two modules, and the sweeps below are the check that they are honest — not a
search for more.

### 4b. How the pairing joins, and why a signed `let` does not become "missing definition"

Worth recording, because it is the part that could have gone wrong quietly.
`Renamer.collectHeads(sts, LetBound, s)` gives a block ONE binder id per spelling, whose
def site is the FIRST EQUATION's head (`Renamer.scala:198-227`), and
`Renamer.statement`'s `SSigStatement` case records each signature name as an OCCURRENCE of
that same binder (`:540-543`, and `SLet` runs `statement` over its block, `:641-645`).  So
in the shared `collectBlock`:

* an equation head joins through `binderAtSite` (its span IS the def site);
* a signature name misses `binderAtSite` and joins through `varFor` -> `ToBinder(id)` ->
  the same `V`, relocated to the signature (`V.equals`/`hashCode` are by `id` alone,
  `Vars.scala:105-110`, so the relocation cannot break the `Map` lookup `pairSigs` does);
* a signature with NO equation gets the signature's own span as its def site
  (`collectHeads:217`), so it has a binder, no `ImplicitBinding`, and `pairSigs` refuses it
  — which is where P5's `missing definition` comes from.

### 4c. The one program whose verdict the fix REVERSES: the row twin (a KNOWN HOLE)

P9 is `shouldfail/sig03_let_bound_signature.e`'s program: `local : forall r. {..r} -> Int`
declared with an EMPTY context, `local r = r ! health` in the body (which needs
`r <- ((|health|), _)`), and the call `local { position = 2.0 }`.

* BEFORE: the signature was dropped, `local` was INFERRED as
  `forall r t. r <- ((|health|), t) => {..r} -> Int` — the honest constraint — and the call
  contradicted it, so the module was REJECTED at the CALL (10:12,
  "Row partitions are unsatisfiable at field 'health'").  The right verdict for the wrong
  reason: the signature was never consulted.
* AFTER: the declaration is honoured, `typeCheckExplicitBinding` skolemises `r`, the wanted
  `r^S <- ((|health|), _)` becomes a residual that the checker DROPS rather than refuses
  (the sig-entail hole, `Subst.scala`'s `rs`), the published local type carries no
  constraint, and the call has nothing to contradict: **ACCEPTED**.

This is exactly the behaviour of the identical program at the TOP LEVEL (`sig01`), which is
accepted today on every branch — so the fix makes `let` agree with the top level, and the
remaining wrongness is the entailment hole, not the lowering.  It is the sig-entail loop's
to close (`../ermine-scala-wt-sig`, SIG-1-SURVEY §6 predicted this exact flip and asked
for the ordering to be respected).  **For that branch:** when LET-1 lands,
`core/examples/shouldfail/sig03_let_bound_signature.e` stops being refused and
`TestSigEntail`'s "let-bound unconstrained signature is refused today (at the call site)"
property goes green for the wrong reason and must be re-pointed at S3's check.  Pinned here
as `KNOWN HOLE: a let signature with a too-weak context is ACCEPTED`, with that explanation
in the source.

### 4d. The corpus: 154 modules, both sides, two schedules

Both sides run the SAME java command line, each against a SNAPSHOT of its own build's
classes (`snap-base` = `a15a97e`, `snap-fix` = this tree), so the comparison is of two
BUILDS and not of two flag settings, and nothing recompiles under a running sweep:

```
ERMINE_CP=$S/snap-base/classpath tracker/tools/corpus-run.sh --batch $S/corpus-base-batch
ERMINE_CP=$S/snap-fix/classpath  tracker/tools/corpus-run.sh --batch $S/corpus-fix-batch
ERMINE_CP=$S/snap-base/classpath tracker/tools/corpus-run.sh        $S/corpus-base
ERMINE_CP=$S/snap-fix/classpath  tracker/tools/corpus-run.sh        $S/corpus-fix
python3 tracker/tools/corpus-verdicts.py $S/corpus-base{,-batch} ...
```

| schedule | side | LOADED | REJECTED | UNKNOWN | verdict changes |
|---|---|---|---|---|---|
| `--batch` | base | 85 | 69 | 0 | — |
| `--batch` | fix | 85 | 69 | 0 | **none** |
| per file | base | 85 | 69 | 0 | — |
| per file | fix | 85 | 69 | 0 | **none** |

85/69/0 is exactly the figure `tracker/GATE-POLICY.md` records for Tier 0 as of F3, on
both sides.

`corpus-verdicts.py` reports "2 of 154 files differ" on the batch pair and the same two on
the per-file pair — `shouldfail/sk03_field_copy_append_self.e` and
`shouldfail/sk05_derived_skolem_field_copy.e`.  Both differences are the ABSOLUTE PATH of
the stdlib `Field.e` inside the message (`.../snap-base/core/classes/modules/Field.e:22:24`
against `.../snap-fix/...`), which is an artifact of giving each side its own class
snapshot: same verdict, same field, same line, same clause.  Nothing else moved.

## 5. Corpus examples: the corpus now exercises the let-signature path

§4a's census is why the corpus could not see this bug: **no module under `core/examples`
had a signature on a `let`-bound binding at all**, and the stdlib had three.  Seven files
close that hole (orchestrator instruction, 2026-09-11).

### 5a. What was added

| file | lines | what it pins |
|---|---|---|
| `core/examples/Lang/LetSignatures.e` | 160 | POSITIVE: nine shapes carrying eleven local signatures, seven of which inference would NOT produce (review edit 2: shapes 3, 5, 7 and `tag` in 9 coincide with inference) — a monomorphic `let` signature; a polymorphic one (`forall a. (a, a) -> a`) instantiated at `Int` and `String` in the same body; a signed `where`; a signed `where` INSIDE a `let` block; a signed `let` inside a `where` body; a `let` signature carrying a ROW CONSTRAINT (`forall r t. r <- ((|runlogQty|), t) => {..r} -> Int`) discharged at a three-field record; one with an explicit KIND (`forall (r: rho).`); one that MONOMORPHISES a row (`{runlogStation, runlogQty, runlogNote} -> Int` where inference gives the row-polymorphic reader); and two ADJACENT signed bindings in one block |
| `core/examples/shouldfail/let01_let_signature_monomorphic.e` | 34 | NEGATIVE, error class 7: `let g : Int -> Int` applied at `String` |
| `core/examples/shouldfail/let02_where_in_let.e` | 25 | NEGATIVE: the second drop site — a signed `where` inside a `let` block |
| `core/examples/shouldfail/let03_let_in_where.e` | 23 | NEGATIVE: a signed `let` inside a `where` body |
| `core/examples/shouldfail/let04_let_signature_too_general.e` | 24 | NEGATIVE: `forall a. a -> Int` over a body that needs `Int` (the WIDENING half) |
| `core/examples/shouldfail/let05_let_signature_no_definition.e` | 28 | NEGATIVE: a signature with no equation in the block |
| `core/examples/shouldfail-controls/control09_let_signatures.e` | 45 | CONTROL: the same five shapes with signatures their bodies satisfy — MUST LOAD |
| `core/examples/Lang/README.md` | +1 row, 2 counts | the module table (ten → eleven modules, twelve → thirteen `.e` files) |
| `core/examples/shouldfail/RESULTS.md` | +30 | "2026-09-11: error class 7, LET SIGNATURE (LET-1)" with the table below, and `control09` added to the positive-controls note |

Every local signature in the positive module is one inference would not produce, and the
header says for each which inferred type it replaces — so the module cannot load by
accident on a compiler that ignores local signatures: it would infer something else.  Four
of the eleven (shapes 3, 5, 7 and `tag` in 9; review edit 2) are the inferred
type and are there for the SHAPE, which the header says as well.

No binding in the new module contains the substring `let`, `case` or `where`
(`signedLocalsReport`, not `letSigReport`): `Console.other` treats a typed line containing
one as unfinished, and `Lang/README.md`'s "REPL trap" section states the invariant for the
whole directory.

### 5b. Verdicts, measured per file with interfaces off

`ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine <file> </dev/null`, and the
`a15a97e` column is the SAME command against the baseline class snapshot
(`-cp $(cat snap-base/classpath)`), which is the regression demonstrated on the corpus
files themselves:

| file | this tree | at `a15a97e` |
|---|---|---|
| `Lang/LetSignatures.e` | **LOADED**; `signedLocalsReport` evaluates to `(3,(7,"North"),7,80,"[North]",3,40,40,(42,"#41"))` | not applicable (new file; it would load there too, with all eleven of its signatures silently ignored) |
| `shouldfail/let01_let_signature_monomorphic.e` | REJECTED `34:6: error: failed to unify type Int with type String` | **LOADED** |
| `shouldfail/let02_where_in_let.e` | REJECTED `25:6: error: failed to unify type Int with type String` | **LOADED** |
| `shouldfail/let03_let_in_where.e` | REJECTED `19:17: error: failed to unify type Int with type String` | **LOADED** |
| `shouldfail/let04_let_signature_too_general.e` | REJECTED `23:7: error: failed to unify type !a with type Int` | **LOADED** |
| `shouldfail/let05_let_signature_no_definition.e` | REJECTED `27:7: missing definition` | **LOADED** |
| `shouldfail-controls/control09_let_signatures.e` | **LOADED** | LOADED (its signatures are correct) |

### 5c. The corpus count after the additions

`tracker/tools/corpus-run.sh --batch` on the FIXED tree, which now globs 160 files
(`shouldfail-controls/` is not in its globs, so `control09` is verified per file only):

| run | LOADED | REJECTED | UNKNOWN | total |
|---|---|---|---|---|
| before the additions (both builds, batch and per file) | 85 | 69 | 0 | 154 |
| after | **86** | **74** | 0 | **160** |

+1 LOADED (`Lang/LetSignatures.e`) and +5 REJECTED (`let01`..`let05`), which are NEW ROWS,
not moved ones: the six files did not exist when the baselines were taken.  The batch
messages are identical to the per-file ones above.

## 6. Gates (Tier 2 — this changes shipped batch behaviour)

Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
one JVM at a time, `tracker/repl-classpath.txt` regenerated from THIS worktree's
`target/ermine-classpath` for every tool that reads it (and `git checkout`-ed back at the
end — the checked-in copy holds absolute paths into the MAIN checkout, which is the
worktree trap SIG-1-REVIEW §5 found).

### 6a. Tier 0 / Tier 2 numbers

| gate | command | result |
|---|---|---|
| compile | `sbt -batch -J-Xmx3g core/compile core/copyResources` | clean; incremental 7 s over the `a15a97e` build (478 pre-existing warnings, none new) |
| FULL test suite, ALONE on the tree | `sbt -batch -J-Xmx3g core/test` | **[success] 1405 s (23:25), 1017 properties, 0 failed** (`+` lines counted; the quarantined `TestConstraints."disjunction sound"` is registered only under `-Dermine.test.disjunction=true` and is not in the count) |
| the new pins | in that run | all **9** of `Ermine let signatures` pass, and `Tolerant check.6.2: every LET and WHERE binder gets a type` passes WITH the new signed-`let` assertion |
| `*TestLoopTrace` | reviewer's run | **720 solves / 720 segments / 720 agree / 0 skipped**, pointed at the main checkout's prebuilt `looptrace` (Lean sources byte-identical between the trees; review edit 4). My own run had skipped the differential for lack of a binary in this worktree |
| the probes | §0 | 9/9 as tabulated |


### 6b. The rest of the tier, with the numbers

Every tool below read `tracker/repl-classpath.txt` REGENERATED from this worktree's
`target/ermine-classpath` (`cp target/ermine-classpath tracker/repl-classpath.txt`), and
the file was `git checkout`-ed back afterwards.

| gate | command | result |
|---|---|---|
| corpus verdicts | `corpus-run.sh` (per file) and `--batch`, both builds | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154 on BOTH sides, both schedules**; the only `corpus-verdicts.py` differences are the two snapshot PATHS inside `sk03`/`sk05`'s message (§4d).  With the new examples the FIXED tree is **86 / 74 / 0 over 160** (§5c) |
| published interfaces | `ei-diff.sh --snapshot` per file, one side per build, `ei-classify.py` | **268 interfaces each side, 3474 bindings identical**, 2 interfaces differ: `Layout/Column/Unsafe.ei :: single'` alpha-equivalent (the let-signature site, a binder RENAME) and `Relation/Predicate.ei`'s six comparisons order-only/alpha-equivalent, which a same-build control shows moving between two boots of ONE build (§8) |
| `g1-validate.sh` | as is | **ALL GREEN, 9 checks**: 6 comparator fixtures PASS; double run EQUIVALENT (129 modules, 1447 signatures, 1301 normalised browse lines, 15 s and 14 s); **no drift from `tracker/g1-baseline`**.  So the `single'` rename is invisible to `G1Compare` (it compares up to alpha-equivalence) and the hard gate needs NO re-cut -- which matters, because that baseline was re-recorded on 2026-08-31 and re-cut on 2026-09-09, i.e. it was captured from the SPLIT pipeline WITH the let drop in place, not from the fused one (the brief's premise that it predates the regression is wrong; `tracker/g1-baseline/README.md` records both cuts) |
| `repl-smoke.sh` | worktree classpath | **8/8 PASS, 66 checks**, goldens byte-identical.  No golden holds a signed `let` (`smoke.in`'s `:type (let f x = x in f)` and `scoping.in`'s `(w -> (let w = "s" in w))` are unsigned), so there was nothing for this change to move |
| `lsp-smoke.sh` | worktree classpath | **PASS, 483 checks** (480 at LSP4-7.2 + the 3 new hovers on `Locals.e`'s signed `let`, at its signature, its def-site and a use -- all three answer `slet : Bool -> Bool`, the DECLARED type) |
| corpus-walking suites, AFTER the new examples | `core/testOnly *TestTolerantRead *TestTolerantCheck *TestSurfaceParsers *TestStatementExtents *TestInterfaceConcreteRow *TestRenamer *TestLetSignatures` | **[success] 262 s, 111 properties, 0 failed** (Tolerant check 47, Renamer 32, Tolerant read 11, let signatures 9, Surface parser 5, Statement extents 4 (271 files), Interface concrete row 3).  The floors all still hold, so the new files are IN the sweeps rather than skipped |
| round trip (no perf gate; measured once each way) | `perf-bench.sh editor -k 10` | before **median 1.623 s** (boot 11.94 s, reused 97/154), after **median 1.616 s** (boot 11.56 s, reused 97/154).  Within the harness's own spread (1.581-1.812 before, 1.587-1.911 after) -- a renamer-only change, one extra pairing per `let` block.  The baseline side had to be measured on a REVERTED tree (`perf-bench` refuses a build older than its sources), so the sequence was: revert the three core files, `core/clean core/compile`, measure, re-apply, recompile, measure |

## 7. What else the stub hid

Everything that went through `Lower.bindings`, audited:

1. **The signature itself** — the bug, both sites.  A `let`-bound signature was never
   lowered at all (`c.lowerAnnot` was not called on it), so it could not even produce a
   kind error: `let g : Int -> NoSuchType; g x = x in g 1` was as silent as a correct one.
   (After the fix the annotation is lowered by the same `TyLower.annot` as a top-level
   signature, so an unknown type in a local signature is diagnosed like any other.)
2. **The interleaving refusal.**  `Lower.bindings` had no `lastEq` check, so
   `let f 0 = 1; g y = y; f 1 = 2 in ...` silently MERGED the second `f` equation into the
   first group — the same defect the top level pins as a 4.2 regression
   (`TestStage1Pins`: "interleaved equations of one name are refused").  The fused `let`
   production used `gatherBindings`, which refused it, so this is part of the same
   regression; sharing the implementation restores it.  Exposure: **0** interleaved `let`
   equations in the 359 `.e` files of `core/examples` + the stdlib (scripted scan), and the
   corpus sweep of §4 confirms no module moved because of it.
3. **The group Span.**  The let path built `ImplicitBinding`s with no group span; nothing
   local consumed one, so nothing was lost, but the shared code now carries the first
   head's span in a `let` block too, which is what the new interleaving refusal points at.
4. **A signature with no equation** was silently dropped rather than refused (P5).  In the
   `let` case that is an unchecked, undefined name that the body cannot use — and the
   refusal is the top level's, verbatim, now.
5. **`do`-block binders and pattern binders lose nothing**, and never went through
   `bindings`: `SDo` is lowered in `term` (channel G, `Syntax.Do.bind`), a pattern variable
   gets `Annot.annotAny` from `annotOf`, and a SIGNED pattern variable `(x : Int)` already
   went through `Lower.pattern`'s `SPSig` case and `c.lowerAnnot`.  `TolerantCheck`'s
   "the pattern binders the split cannot reach are absent" property still holds for them.
6. **`private` blocks are a top-level shape only** (`bindingStatement = sigStatement |
   equationStatement`, `SurfaceParsers.scala:771-786`, is all a `let` or `where` block can
   hold), so the shared code's `case other => throw Unsupported(...)` is unreachable from
   either caller — the module path's old `case _ => ()` was equally unreachable, because
   `walk` only ever hands it equations and signatures.
7. **The editor was wrong about a signed `let`, and said so in a comment.**
   `TolerantCheck.collectLocals`' `headType` answers `e.ty.body` for an `ExplicitBinding`
   and `i.v.extract` for an implicit one; with the signature dropped a signed `let` binder
   was implicit, so hover showed the INFERRED type — a silent violation of LSP Stage-3
   Decision (a), asserted as correct by the comment at `TolerantCheck.scala:322-328` and
   untested (`TestTolerantCheck` asserted only `sw`, from a `where`; `tracker/lsp-tests/
   Locals.e` had no signed `let`).  The fix needs no change in `TolerantCheck` — `Let`'s
   explicit bindings were already walked (`(is ++ es)`) — only the comment and the pins.

## 8. The published interfaces: 268 on each side, one binding moves, and it moves by NAME

`tracker/tools/ei-diff.sh --snapshot` per file (the default schedule), one side per BUILD
-- the baseline side taken from the unfixed tree BEFORE any recompile, the fixed side from
this tree -- then `tracker/tools/ei-classify.py`:

```
tracker/tools/ei-diff.sh --snapshot $S/ei-base "-Dermine.useInterface=true"   # at a15a97e
tracker/tools/ei-diff.sh --snapshot $S/ei-fix  "-Dermine.useInterface=true"   # this tree
python3 tracker/tools/ei-classify.py $S/ei-base $S/ei-fix
```

| | |
|---|---|
| interfaces | 268 on each side, **none only on one side** |
| bindings | **3474 identical**, 3 alpha-equivalent, 4 order-only, **0 `concrete->polymorphic`, 0 `polymorphic->concrete`, 0 `other`** |
| interfaces that differ at all | **2 of 268** |

**`Layout/Column/Unsafe.ei :: single'` — the let-signature site, and the whole difference
is a BINDER NAME.**

```
- single' : forall {a} a1 (r: rho) ra (s: a) b  c d e g. ... Presentation r ra  ... Maybe b  ...
+ single' : forall {a} a1 (r: rho) b  (s: a) b1 c d e g. ... Presentation r b   ... Maybe b1 ...
```

`ra` became `b` and the old `b` became `b1`: alpha-equivalent, which is what
`ei-classify.py` says.  The mechanism is that the now-lowered local signature
(`unsafePres : Presentation r a -> Presentation r b`, `Layout/Column/Unsafe.e:102`) mints
its own named type variables, which shifts which names generalisation hands out when the
enclosing binding is rendered.  So the signature the stdlib has shipped since before the
regression is HONEST -- checking it changes no published type, here or anywhere -- and
`hc'` (the second site, `:113`) and `List/Util.ei` (`median`, the third) are
**byte-identical**.

**`Relation/Predicate.ei` — six comparison operators, and it is the noise floor, proven.**
`(!=)`, `(<)`, `(==)`, `(>)` are `order-only` (equal after sorting the constraint list) and
`(<=)`, `(>=)` are `alpha-equivalent`; `Relation/Predicate.e` has no local signature at
all, so the lowering of that module is identical on the two sides.  The control (which the
brief asked for and which I ran after the fact, not before):

```
# same build, same shape: three boots of the unfixed build, three of the fixed
for i in 1 2 3; do <delete all .ei>; echo ':quit' | bin/ermine; cp <modules>/Relation/Predicate.ei ctl-$i; done
```

**Two boots of ONE build produce different `Relation/Predicate.ei` bytes** (`base-boot1 vs
base-boot2: DIFFERS`), while `Layout/Column/Unsafe.ei` is stable across boots of one build
and differs across the two builds exactly as above.  The per-file `.ei` sweep does not set
`-Dermine.loadInSeries`, so the stdlib boot is parallel and the solver's id order varies
run to run -- the churn `tracker/g1-baseline/README.md` already names ("alpha-variants and
part-order differences in `(&)`, `(&_Mem)`, `(**)`, `dateDiff`, `lookbackJoin`,
`setColumn`, the `Predicate` comparisons").  None of it is an information change: no
binding on either side became more or less constrained.


## 9. Status, and what this leaves for others

**Done and green.**  The fix, the pins, the corpus examples and the whole of Tier 2 are in
the worktree `ermine-scala-wt-let` (branch `let-signatures`, from `a15a97e`).  **No
commits**, per the brief.  Nothing under `tracker/lean/` was touched; every `.ei` this work
caused is deleted (the 143 that remain are the checked-in `tracker/g1-baseline` and
`tracker/g1-oracle-tests` goldens); `tracker/repl-classpath.txt` is `git checkout`-ed back
to its committed (main-checkout) contents.

**No stdlib or examples module became REJECTED.**  The three shipped let signatures
(§4a) are honest: the corpus verdicts are identical on both sides in both schedules, and
the only published type that moves does so by renaming a binder (§8).  So there is no
"wrong shipped signature" finding to escalate, and nothing was edited in the stdlib.

**For the sig-entail loop (`../ermine-scala-wt-sig`), the ordering hazard its own survey
flagged is now real:** when this lands, `core/examples/shouldfail/sig03_let_bound_signature.e`
turns from REJECTED into ACCEPTED and `TestSigEntail`'s "let-bound unconstrained signature
is refused today (at the call site)" property goes green FOR THE WRONG REASON (§4c).  Both
need re-pointing at S3's check, and `TestLetSignatures`' `KNOWN HOLE` property is the one
to flip when S3 lands.

**For the LSP loop:** hover on a signed `let` binder now answers the DECLARED type, which
is Stage-3 Decision (a); it was silently answering the inferred one, and
`tracker/lsp-tests/Locals.e` plus three `lsp-client.py` checks pin it (§6b).

**Two gate observations worth carrying into the trackers,** neither caused by this change:

1. `tracker/g1-baseline` does NOT predate the let drop.  It was re-recorded on 2026-08-31
   (`7ebcbfa`) and re-cut on 2026-09-09 (`ed53fe7`), both AFTER `faa5769` made the split
   pipeline the only module path, so it was captured WITH the regression in place.  The
   brief's instruction to expect it to be "equal-or-closer" to a fused-pipeline baseline
   does not apply; it is green, and the reason it is green is that `G1Compare` reads
   through alpha-equivalence.
2. `*TestLoopTrace`'s model differential SKIPS in this worktree (no
   `tracker/lean/.lake/build/bin/looptrace`, and building it was out of scope), so that
   Tier-0 line was re-run by the reviewer with the main checkout's binary: 720/720.  A renamer change cannot move a solver
   trace, but the gate did not demonstrate it.
