# E11c-KIND — which of the two published kinds for `ChartsExample.e:stackedPair` is principled

Stage E11c-kind (brief `tracker/loopmodel/briefs/brief-E11c-kind.md`), implementer run 2026-09-14,
branch `scala3-migration`, HEAD `5e2b6e9c`, main checkout.  Scratch and every log:
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11c-kind/`
(`<k>` below); the two published renderings are in `…/scratchpad/e11c/ei-{pre,on}/core_examples_ChartsExample.ei`
line 22 (`<s>`), and `ei-classify`'s A/B in `…/scratchpad/e11c-review/rv-ei-classify.log` (`<r>`).
**Nothing committed, no source or other tracker file changed, no default flipped,
`find core/target core/examples -name '*.ei'` is 0.**

## Verdict

**NEITHER published signature is the principal kind, and the flag's change is a net improvement
on one of the three binders, a harmless over-specialisation on the other two, and no change at
all on a fourth and fifth defect that both sides share.**  The three binders do not have one
answer between them.  `sa` is governed by `AsPresentation s` (`s : ρ -> * -> *`, `Lib.scala:1100`)
applied as `s sr sa`, so its **only** well-kinded kind is `*`: the OFF rendering `(sa: c)` with `c`
bound in the scheme's own `forall` is a type **the compiler's own kind checker rejects when you
write it down** (`<k>/probe4-off.log`, `failed to unify kind * with kind !c`) — it is not a more
general type, it is an ill-kinded one, and ON is simply right.  `tdxfyf'` and `tdxfyf` are the
**phantom** first parameter of `ChartOptions` (`OptionTypes.e:114`, mentioned in no field), which
really is kind-polymorphic — `ChartOptions List Int Int` is **accepted** under both OFF and ON
(`<k>/probe5-off.log`, `<k>/probe-on.log`) — so there ON defaults a genuinely free kind variable
to `*` prematurely, a real but unexploited loss of generality.  And `xa'`/`ya'` are printed at kind
variables by **both** sides even though `ChartOptions`' second and third parameters are `*`
(`ChartOptions Int List Int` is **rejected**, `<k>/probe5-off.log`), so the same over-generalisation
survives the flag untouched.  Therefore: **the kind change is a weak reason FOR the flip, not a
reason to hold it** — it removes the one binder whose published kind is unsound, costs only phantom
generality that no caller in the corpus can use (`stackedPair`'s sole caller is `stackedGuy` eleven
lines below it, `ChartsExample.e:497`), and it does not pretend to fix the underlying defect.  The
underlying defect is that `Subst.generalize` gates kind generalisation **only** on the term
environment Γ (`Subst.scala:1769`) and nothing re-checks the generalised scheme's kinds, while
`inferKind`'s application rule generalises-and-re-instantiates a result kind at every `AppT` node
(`Subst.scala:572-573`), which can sever an argument's kind variable from the constructor parameter
that ought to fix it.  One correction to E11c-SOLVEDET §6a: **the mechanism is not
`typeDefComponents`.**  `ChartsExample.e` contains **zero** `data`/`type`/`class` declarations, so
`typeDefComponents(m.types)` is empty for that module; the flag reaches `stackedPair` through
`ImplicitBinding.implicitBindingComponents` (`Binding.scala:105`, the other half of cause 1),
`stackedPair` being an implicit (unsignatured) binding.

## 1. The binding, the three parameters, and what governs them

`core/examples/ChartsExample.e:491`

```
stackedPair opts s x y r1 r2=
    chart_K opts
      (unscaled Ascending)
      defaultScaled
      [bar s x y r1, line s x y r2]
```

No signature — an implicit binding.  Its only caller is `stackedGuy` at `ChartsExample.e:497-505`,
in the same file; `grep -rn stackedPair core/examples core/src/main/resources/modules` returns
exactly those two lines (§5).

The names are minted by the pretty-printer from the inferred variables.  Mapping them onto the
published type (`<s>/ei-pre/core_examples_ChartsExample.ei:22`):

| binder | where it occurs in the published type | what governs its kind |
|---|---|---|
| `tdxfyf'` | `ChartOptions tdxfyf' xa' ya' -> …` (the `opts` argument's **domain**) | **phantom** 1st parameter of `ChartOptions` — kind-polymorphic |
| `tdxfyf` | `… -> ChartOptions tdxfyf xa ya` (the `opts` argument's **codomain**) | same |
| `sa` | `s sr sa ->` (the `s` argument) with `(s: rho -> * -> *)` in the same scheme | **`*`**, forced by `AsPresentation s` |

* **`tdxfyf'`, `tdxfyf`.**  `Layout/Report/Keyed/OptionTypes.e:114`:
  `data ChartOptions tdloxlxfylyf xa ya = ChartOptions (Maybe String) Direction ChartLegendOptions#
  ChartRenderHints# AxisLabel (Format_Fmt xa) Bool AxisLabel (Format_Fmt ya) Bool`.  The first
  parameter appears in **no field** — it is the Bound/Unbound "which options have been set"
  witness that `Layout/Report/Keyed/Options.e:186-231` threads through `chartTitle`, `yDirection`,
  `xLabel`, … .  It is a pure phantom.  Never applied to anything, never a field type.
  `xa`/`ya` by contrast appear as `Format_Fmt xa`, `Format_Fmt ya`, so they are `*`.
  The declaration's own kind is generalised with an **empty** Delta (`Subst.scala:821`, §2), so
  `ChartOptions` really is polymorphic in its first argument, and the same shows in
  `OptionTypes.ei:3` — `chartDefaults : forall (u1: a) xa ya. …` — **byte-identical under OFF and
  ON**, i.e. the constructor's kind is not what the flag moves.
  * **Measured:** `p7 : ChartOptions List Int Int -> Int` (`List : * -> *` in position 1) **loads
    clean** under OFF and ON.  `p8 : ChartOptions Int List Int -> Int` (position 2) is
    **rejected**, `error: failed to unify kind * with kind (* -> *)`.  `<k>/probe5-off.log`,
    `<k>/probe-on.log`.
* **`sa`.**  `s` is `stackedPair`'s second argument, passed to `bar`/`line`, and the residual
  constraint is `Layout.Presentation.AsPresentation s`.  `AsPresentation` is a **builtin** class
  whose kind is written in Scala, not in Ermine — `session/Lib.scala:1099-1104`:
  ```scala
  val presentationKind = rho ->: star ->: star
  // class AsPresentation (a: ρ -> * -> *)
  val asPresCon = mkClassCon(Global(presentationMod, "AsPresentation"),
                             (presentationKind ->: constraint).schema)
  ```
  — monomorphic, **not** a kind schema.  `Presentation` itself is `mkCon[Presentation](…,
  presentationKind)` at `Lib.scala:1110-1111`, and the Ermine-side comment at
  `Layout/Presentation.e:109-112` records the same: `foreign data … Presentation (r: ρ) (a: *)`.
  So `AsPresentation s` forces `s : ρ -> * -> *`, and the occurrence `s sr sa` in the very same
  scheme forces **`sa : *`**.  The published OFF scheme prints `(s: rho -> * -> *)` and `(sa: c)`
  **side by side** — it is internally inconsistent on its face.
  * **Measured:** `p2 : (AsPresentation s) => s sr List -> Int` is **rejected**,
    `error: failed to unify kind * with kind (* -> *)` (`<k>/probe3-off.log`, `<k>/probe-on.log`).

## 2. Where the kind is decided — the generalisation rule, from the code

**(a) The rule for a term's scheme.**  `Subst.generalize` (`Subst.scala:1766`), the function that
makes every published binding signature:

```scala
val ks = (kindVars(t) -- kindVars(g)).filter(_.ty != Skolem).toList   // :1769
…
val nks = refreshList(Bound, li, ks)                                  // :1772
val km  = zipKinds(ks,nks)
val nts = refreshList(Bound, li, subKind(km, ts))                     // :1774
```

So: **every kind variable free in the type and not free in Γ, and not a skolem, is quantified.**
The HM side condition *is* applied to kind variables — but only against Γ, and Γ is the **term**
environment (`type Gamma = List[TermVar]`, `Subst.scala:735`; `delta(g) = kindVars(g).map(VarK(_))`,
`Subst.scala:726`).  Nothing else restrains it: not the kinds the scheme's own constraint context
imposes, not a pending type-def group, not a later binding group.  `:1774` then **snapshots** the
binder kinds into the scheme; a unification of that kind variable after this point cannot reach the
scheme any more.

Crucially, `inferImplicitBindingTypes` (`Subst.scala:905-963`) **never kind-checks the inferred
type before generalising it** — `generalize(omg, csp, substType(t).forget, publishing)` at
`Subst.scala:963` is reached from `subsumeType`/`solve` alone.  The published scheme's kinds are
whatever kind unifications term inference happened to perform, and nothing audits them afterwards.
Contrast the *signature* path: `unbindAnnot` (`Subst.scala:709-717`) does
`kindCheck(delta(g), t, Star(a.loc.inferred))`, and `typeCheckExplicitBinding` (`:757-759`) does it
again — which is exactly why writing the OFF scheme down is rejected (§4).

**(b) The rule for a type constructor's kind.**  `Subst.generalizeKind` (`Subst.scala:1805-1809`)
is the same rule with a Delta in place of Γ, and `inferTypeDefKindSchemas` calls it with
`Nil` — `val gk = generalizeKind(Nil, substKind(b.v.extract))` (`Subst.scala:821`).  **Every** kind
variable still free in a `data`/`type`/`class` head's kind after its group is checked is
generalised, unconditionally.  That is why `ChartOptions`' phantom parameter is genuinely
kind-polymorphic, and it is the right rule for a constructor: its group is closed at that point.

**(c) The mechanism that lets an argument's kind escape.**  `inferKind`'s application rule,
`Subst.scala:566-575`:

```scala
case a@AppT(f, x) => a.memoizedKindSchema match {
  case Some(ks) => ks
  case None =>
    val (fvs, i, o) = matchFunKind(inferKind(d, f))
    val (xvs, kx)   = unbindKindSchema(Free, inferKind(d, substType(x)))   // :569  RE-INSTANTIATES
    unifyKind(substKind(i), kx)
    val op = generalizeKind(substDelta(d), substKind(o)) at li             // :572  GENERALISES
    restrictKinds(fvs ++ xvs)
```

At **every** application node the result kind is generalised against the Delta and the consumer
re-instantiates it fresh (`:569`).  A kind variable that is not reachable from the Delta is
therefore **renamed at each hop**, and the identity between "the kind of the argument `sa`" and
"the second parameter kind of `s`" is not preserved across the generalise/re-instantiate pair.
That is the machinery by which `sa`'s kind meta can survive the whole check of `s sr sa` as a free
variable, and then be quantified by `:1769`.  (`Type.closeWith`, `Type.scala:78-84`, which builds
the implicit `forall` of a written signature, passes `List()` for the kind binders, so a written
signature's binder kinds are free metas too and go through the same door.)

**(d) The concrete order dependence, and what it is NOT.**  E11c-SOLVEDET §6a attributes this to
`TypeDef.typeDefComponents` (`syntax/Statement.scala:150-170`).  **That cannot be the mechanism
here:** `grep -c '^data \|^type \|^class ' core/examples/ChartsExample.e` is **0**, so
`typeDefComponents(m.types)` is the empty list for this module and the ON branch at
`Statement.scala:155/166` never runs on it.  The half of the flag that *does* reach `stackedPair`
is `ImplicitBinding.implicitBindingComponents` (`Binding.scala:105-112`), the same two id-hash
reads: `stackedPair` has no signature, so it is an implicit binding, its component and its position
inside that component are chosen by Tarjan's root order (id-keyed `Map.keySet.toList` under OFF,
the source-order vertex list under ON), and that decides which sibling's inference has already run
— and therefore which kind metas are already pinned — when `generalize` fires at `Subst.scala:963`.

**A minimal, self-contained reproduction.**  Six lines, no `data`, no `type`, no rows, no
`ChartsExample`:

```
module E11cP5 where
import Prelude
import Layout.Presentation
p5 : forall s sr sa. (AsPresentation s) => s sr sa -> Int
p5 _ = 1
```

| session | published `p5` | log |
|---|---|---|
| OFF, alone | `forall {a} (s: rho -> * -> *) (sr: rho) (sa: a). AsPresentation s => s sr sa -> Int` | `<k>/probe6-p5alone-off.log` |
| OFF, after `E11cP1`, `E11cP4` | `forall (s: rho -> * -> *) (sr: rho) sa. AsPresentation s => s sr sa -> Int` | `<k>/probe4-off.log` |
| OFF, after `E11cP6` / after `E11cP1` / after `E11cP4` | the `{a}` form | `<k>/probe5-off.log`, `<k>/probe7-p1p5-off.log`, `<k>/probe8-p4p5-off.log` |
| **ON** | `forall (s: rho -> * -> *) (sr: rho) sa. …` | `<k>/probe-on.log` |

So the whole `stackedPair` phenomenon — same source, two published kinds, decided by what the
session loaded before it — is reproducible in six lines that contain none of the machinery §6a
named, and under ON it lands on `*`.  (The variant `E11cP1`, the same binding with the `forall`
left implicit, behaves identically; `<k>/probe4-off.log`, `<k>/probe5-off.log`.)

## 3. Principal or over-generalised? — the answer per binder

The brief offers two cases.  **Neither fits as stated**, because the three binders split:

* **`sa` — case (iii), a new one: the kind variable is fixed by the scheme's OWN constraint
  context, not by a later group and not "genuinely unconstrained".**  `AsPresentation s` is a
  conjunct of the published scheme itself, and it pins `s : ρ -> * -> *` in the published scheme
  itself (the `.ei` prints it).  Generalising `sa`'s kind therefore does not produce a *more
  general* type; it produces an **ill-kinded** one — a `forall {c}` whose body is unkindable at
  `c ≠ *`.  This is worse than classic HM over-generalisation with the environment: there is no
  instantiation of `c` other than `*` under which the body has a kind at all.  **ON is correct
  here and OFF is a bug**, in the direction of publishing a scheme with no well-kinded reading.
* **`tdxfyf'`, `tdxfyf` — case (i).**  `ChartOptions`' first parameter is a phantom, its kind is
  generalised by the deliberate `generalizeKind(Nil, …)` at `Subst.scala:821`, and the checker
  demonstrably **accepts** `ChartOptions List Int Int`.  So the polymorphic kind is the principal
  one and **ON defaults it prematurely** — a bug in ON's direction, harmless until someone
  instantiates `ChartOptions`' phantom at a higher kind through `stackedPair` (nobody does; §5).
* **`xa'`, `ya'` — both sides wrong, identically.**  Both renderings bind them at kind variables
  (`{a1}`/`{b}` under OFF, `{a}`/`{b}` under ON) although `ChartOptions`' second and third
  parameters are `*` (`Format_Fmt xa`, and `ChartOptions Int List Int` is rejected).  The flag does
  not touch this, so **the ON signature is also not principal** — it merely has one fewer bad
  binder.

The principal kind of `stackedPair` is thus neither published form: it is
`forall {k1 k2} (tdxfyf': k1) (tdxfyf: k2) xa' ya' xa ya (s: rho -> * -> *) (sr: rho) sa …`,
which is what you get if the phantom is generalised and every other binder is pinned by the
constructor or class that uses it.  ON is two binders closer to it than OFF, and its one regression
(`tdxfyf'`, `tdxfyf` at `*`) is a **sound specialisation**, whereas OFF's `sa` is not sound at all.

## 4. The distinguishing program

**It cannot be written in the source language, and that is itself the result.**  Every program that
would instantiate `sa` at a non-`*` kind is rejected at kind check, under **both** settings, before
`stackedPair` is ever reached:

| probe | source (6-line module under `core/examples`, deleted afterwards) | OFF | ON |
|---|---|---|---|
| `p2` | `p2 : (AsPresentation s) => s sr List -> Int` | **rejected** `E11cP2.e:6:7: error: failed to unify kind * with kind (* -> *)` | **rejected**, same message |
| `p3` | `p3 : forall {c} (sa: c) s sr. (AsPresentation s) => s sr sa -> Int` — i.e. **the OFF rendering, written down** | **rejected** `E11cP3.e:6:32: error: failed to unify kind * with kind !c` | **rejected**, same message |
| `p5` | the same binding with kinds left to inference | publishes **`(sa: a)`** (the OFF rendering) at most bases, `sa : *` at some | publishes **`sa : *`**, stably |
| `p7` | `p7 : ChartOptions List Int Int -> Int` | **accepted** | **accepted** |
| `p8` | `p8 : ChartOptions Int List Int -> Int` | **rejected** `E11cP8.e:7:6: error: failed to unify kind * with kind (* -> *)` | **rejected**, same message |

Logs: `<k>/probe3-off.log`, `<k>/probe4-off.log`, `<k>/probe5-off.log`, `<k>/probe6-p5alone-off.log`,
`<k>/probe7-p1p5-off.log`, `<k>/probe8-p4p5-off.log`, `<k>/probe-on.log`.  Harness: the plain REPL,
`bin/ermine`, reading a `.in` script on stdin; the module files were written into `core/examples`
(a `SourceFile filesystem` search path, `session/Console.scala:844`) and pulled in with
`import <Module>`, then `:type <name>` / `:kind <name>` for the rendering.  `-Dermine.solveDet=true`
reaches the REPL through the launcher's **`ERMINE_JAVA_OPTS`** (`bin/ermine:22-24`) — that is the
shortest path and needs no sbt.  The `.e` files and every `.ei` they produced are deleted.

So `p3` is the decisive experiment the brief asked for, in a stronger form than "instantiate it":
**the compiler's own kind checker refuses the OFF signature as a signature.**  An over-generalised
kind here cannot be exploited into a runtime cast or a later type error, because the front end
rejects every type expression that would reach it — which is why the corpus notices nothing
(§5) and why the defect is a *publication* defect: the `.ei` carries a type the compiler would not
accept if it were asked to read it as a written signature.  I did not need to reach a particular id
base: the same rendering is reproduced deterministically by `E11cP5` alone under OFF
(`<k>/probe6-p5alone-off.log`), and `<s>/ei-pre/core_examples_ChartsExample.ei:22` is the published
`stackedPair` itself.

**Not established:** whether an `.ei` *re-read* of the OFF `stackedPair` (via the interface parser,
`parsing/InterfaceParsers.scala`, rather than the source type parser) also rejects it.  The
interface key differs between OFF and ON on all 274 files (`<r>/rv-ei-classify.log`, last line), so
a cross-reading needs a hand-built key and did not fit in the hour.  If the interface parser is
laxer than `unbindAnnot`, the bad kind would be silently re-imported rather than rejected — worth a
follow-up, since it is the difference between "unreachable" and "reachable by a downstream module".

## 5. Corpus impact

* **`stackedPair` is the only binding whose kind binders move.**  `<r>/rv-ei-classify.log`:
  `interfaces: A 274  B 274  only-in-A -  only-in-B -`, `== 7 of 274 interfaces differ`,
  `== bindings by verdict: {'identical': 3516, 'order-only': 1, 'other': 6}`.  The seven are
  `Algebra_SoftSchema.ei:pivoted` (order-only), `ChartsExample.ei:stackedPair`,
  `Present_WriterOutputs.ei:reportFor` (constraints 3 → 1), `incomplete_RevenueShare.ei:shareOfGroup`,
  `Layout_Report.ei:drilldownKeyValueTable2` (5 → 6), `Layout_Report_Relation.ei:cutoffGroupedFldsPosNegRel'`,
  `Relation.ei:lookbackJoin` (8 → 9).  Reading the A/B pairs, the other six differ **only** in the
  constraint set or existential naming; the `forall` binder kinds are character-identical on each.
  **Confirmed: `stackedPair` is the sole kind change.**
* **Nothing calls it.**  `grep -rn stackedPair core/examples core/src/main/resources/modules` →
  `core/examples/ChartsExample.e:491` (the definition) and `:498` (inside `stackedGuy`, same file).
  No stdlib module and no other example mentions it.  `stackedGuy`'s own published type is
  `forall (f: * -> *) z. Layout.Report.Report f z` — identical under OFF and ON (both `.ei` line 21),
  so the one caller is unaffected by either rendering.
* Consistent with E11c-SOLVEDET §5(d): the whole corpus still loads identically under ON, and
  `corpus-verdicts.py` output is byte-identical (`<r>/rv-verdict-diff.log`).

## 6. What I could not establish

1. **Whether the interface parser re-reads the OFF `stackedPair` without complaint** (§4).  This is
   the one thing that would turn "unexploitable" into "exploitable by a downstream module", and it
   is a ~30-minute follow-up: build an `.ei` with a hand-matched interface key, or add a
   read-back assertion to the E11a harness.
2. **The exact `implicitBindingComponents` permutation that flips `stackedPair`.**  I established
   that `typeDefComponents` cannot be it (no type defs in the module) and that the flip is
   reproducible from a six-line module whose published kind depends on what the session loaded
   before it — but I did not trace which sibling binding, when moved ahead of `stackedPair`, pins
   `sa`'s kind meta.  `E11cP4` ahead of `E11cP5` was enough to change the answer in one run
   (`<k>/probe4-off.log`) and not in a second (`<k>/probe8-p4p5-off.log`), so the trigger is the id
   base, not the neighbour's identity.
3. **Whether ON is stable at `*` for `sa` at *every* base**, as opposed to the four ON runs on
   record.  E11c's own gates give ON `KIND 0-1` across four sweeps, which is evidence but not proof.
4. **Whether `xa'`/`ya'` (bad under both) are a separate defect or the same one.**  They look like
   the same `Subst.scala:572` escape at a different `AppT` node, but I did not trace it.
5. `:kind ChartOptions` prints `ChartOptions : * -> * -> * -> *` even though `ChartOptions List Int
   Int` is accepted.  `Console.scala:549-556` runs `inferKind(List(), fty)` and
   `Pretty.prettyTypeHasKindSchema` (`Pretty.scala:439`); I did not determine whether `ppKindSchema`
   is eliding the quantifier or whether `:kind` instantiates before printing.  **Do not read the
   `:kind` output as evidence either way** — the accept/reject probes (`p7`/`p8`) are the evidence.

## 7. Time

Roughly 65 minutes wall clock (06:05–07:10 MDT, 2026-09-14): ~20 min reading the prior reports,
the `.ei` pair and the kind checker; ~30 min on the REPL probes (five `bin/ermine` sessions under
OFF, one under ON, ~40 s each plus iteration on the probe syntax); ~15 min writing up.  Over the
1 h budget by the write-up.
