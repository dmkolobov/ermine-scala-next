# J2b Part 2: the builtin structural `Json a` constraint — design, and why it is not built

Design note §3.6 ("Builtin structural `Json a` constraint (compile-time
rejection)", effort S) and §2.4 row C. Written 2026-09-16 on `json-spread`.
Every file:line below is in this worktree.

**Verdict: DESIGN ONLY. Do not implement in this programme.** The brief's own
gate — "implement only if the design is a check with no inference changes (a
post-typecheck pass over instantiated `toJson#` call sites)" — cannot be met,
for a reason that is a fact about this compiler rather than a judgement call:
**the instantiation the check would read does not survive type checking**, and
the one call site of `toJson#` in the whole corpus is instantiated at a
skolem, not at a user's type. The two escape routes (make it a real class
constraint; teach the checker to retain instantiations) both change inference.
A cheaper check that buys most of the value — at the *runner's* boundary, not
in the language — is described at the end and needs nothing new.

## 1. What the check would have to do

Reject, at compile time and with a source location, a program that hands a
value of a non-serializable type to the JSON boundary: `toJson# : forall a. a
-> Json` (`core/src/main/scala/com/clarifi/reporting/ermine/session/Lib.scala:1478`),
and through it `Json.toJson`, `widget`, and a report's `Params -> Node`.
"Serializable" is already decided, in one place, by
`com.clarifi.reporting.ermine.json.Encode.reject(t: Type): Option[String]`
(`.../json/Encode.scala`, `def reject`), with `Schema.exportType` and
`Decode.entry` as the stricter static readings of the same fragment. The
check would *only* reject: no instance selection, no dictionary passing, no
effect on the value's meaning. That is what makes it look free.

## 2. Why the brief's shape (a post-typecheck pass over call sites) is not implementable

1. **There is no elaborated AST.** `Term` carries no type on any node
   (`ermine/Term.scala:21-113`; `App` at `:69`, `Var` at `:85`). The only
   type-bearing node is `Sig` (`:75`), which holds the *user-written* `Annot`
   (`ermine/Annot.scala:13`). There is no Core/elaborated IR in the pipeline:
   `core/Core.scala` exists but nothing in `session/`, `lsp/` or `rename/`
   refers to it, and evaluation runs directly on `Term`
   (`Term.scala:210`, `session/Session.scala:1130-1133`).

2. **The instantiation is deleted on purpose, one line after it is made.**
   Inference is a pure `Type`-returning function that writes nothing back:
   `Subst.inferType` (`ermine/Subst.scala:1018`); its `Var` case (`:1022`)
   returns the unopened `Forall`. In the `App` case (`:1055-1069`)
   `matchFunType` (`:1057`) opens `forall a` into a fresh `Free` meta, which
   `subsumeType` (`:1062`) binds in `hm.types` — and then `:1068` calls
   `restrictTypes(txs)`, whose body is `hm.types = hm.types -- xs` (`:221`),
   with a comment at `:216-220` saying exactly why ("it is pointless to keep
   instantiations for those variables around"). Even if it survived, the whole
   `SubstEnv` is per-block scratch, dropped on return
   (`session/Session.scala:59-60`). **So after checking, the type `a` was
   instantiated to at a given application cannot be recovered.**

3. **`toJson#` is called exactly once in the corpus, and there `a` is a
   skolem.** The only `.e` file that mentions it is
   `core/src/main/resources/modules/Json.e:67` (`toJson = toJson#`), under the
   explicit signature `toJson : a -> Json` (`:66`); `core/examples/` has none.
   Every user-visible call goes through `toJson`, an ordinary binding whose
   `V` carries `forall a. a -> Json`, so a pass over `Global("Json","toJson#")`
   nodes would see one site, instantiated at the wrapper's own skolem
   variable, and would have nothing to reject. The check would have to look at
   `Json.toJson` applications instead — i.e. at *every* application of *any*
   binding whose scheme mentions the constraint, which is the general problem,
   not a special case.

4. **Two checking drivers, not one.** Batch is `Session.Dep.make`
   (`Session.scala:593-611`) → `Session.loadModule` (`:1002`) →
   `Subst.inferBindingGroupTypes` (`:1042`); the LSP is
   `lsp/Resident.checkFile` (`Resident.scala:232`) →
   `session/TolerantCheck.checkWith` (`TolerantCheck.scala:831`), which runs
   inference per SCC in its own fresh `SubstEnv` (`:1060`, `:1078`, `:1113`)
   and does **not** go through `loadModule` (see the comment at
   `Resident.scala:221`). Anything new must be installed in both, or in the
   shared `inferBindingGroupTypes` — i.e. inside the checker.

Conclusion: the brief's post-pass needs the checker to start retaining
instantiations (a new map beside `Subst.remembered`, `Subst.scala:106`, which
today is minted only for holes and `?[e]`, `rename/Lower.scala:207-208`).
That is a change to the checker's hot path, its memory behaviour and both
drivers — small in lines, but not "a check with no inference changes".

## 3. Why the real-constraint route is worse, not better

Making `Json a` a genuine builtin constraint means registering a
`Requirements` (`Subst.scala:81-85`) under a `Global` in `hm.classes`
(`Subst.scala:94`, populated at `Session.scala:60` from
`SessionState.classes:105`), the way `Lib.addInstance` (`Lib.scala:56-65`)
registers builtin instances. Everything downstream then treats it as a class
constraint:

- `byInst` (`Subst.scala:384-390`), `bySuper` (`:376`), `entails` (`:392`),
  `simplifyPredicates` (`:400`), `toPNF` (`:424`), `reduce` (`:431`);
- `split` (`:465-471`) defers what it cannot discharge, so an unresolved
  `Json a` is **generalized into the binding's scheme** (`generalize`, `:1766`)
  and therefore appears in published signatures and in `.ei` interfaces
  (`Session.scala:578-589`, `:1051`);
- defaulting and ambiguity (`Subst.scala:459-462`), signature entailment
  (`SigEntail.enforce`, `SigEntail.scala:743`), and the top-level residual
  check (`Session.scala:1058-1060`, `Subst.scala:1847-1849`) all now see it.

So `toJson : Json a => a -> Json` changes the type of every function that
calls it, transitively, and the corpus's published interfaces with it. That is
precisely the class-machinery behaviour change the user ruled out
(2026-09-12), it is not confined to the new constraint, and it would move
`.ei` keys (`Session.scala:184`) and corpus verdicts. **Rejected.**

A "structural" `Requirements` whose `reqs` answers `Some(Nil)` or dies is not
a way out: the death would be thrown from `byInst` during solving, at whatever
location the solver happens to be at, and it would still take part in
generalization and entailment.

## 4. What IS implementable without touching inference, and what each buys

| Option | Where | Touches inference? | What it catches | Cost |
|---|---|---|---|---|
| (a) A pass over PUBLISHED SIGNATURES after checking | after `inferBindingGroupTypes` in both drivers (`Session.scala:1042`, `TolerantCheck.scala:1078`), over the generalized `TermVar`s that `writeInterface` already receives (`Session.scala:1051`) | no — it reads schemes, never subterms | a *declared* report/widget signature whose `Params` or props type is outside the fragment | S; but two hook sites, and it needs a rule for WHICH signatures are boundary signatures (there is no `Json a` to look for) |
| (b) A declaration sweep at load | inside `processTypeDefComponent`, where the `DataConDecl` registry is already populated (`Session.scala:915-922`), reusing `Encode.rejections` | no | a `data` declaration that can never be encoded | S, but useless as an ERROR: today's stdlib sweep is 101 types / 80 rejected fields (`TestJson`, "every stdlib data declaration is classified") — most of the standard library is legitimately not serializable |
| (c) The runner's boot-time check | J3c, in `json/Runner.scala` | no — it is library code | exactly the real boundary: `Decode.reportSignature` + `Decode.compile` on the `Params` half (already specified in report-J2a) and `Schema.exportType` / `Encode.reject` on the `Node` half | XS — the pieces exist |
| (d) The editor/CLI query | today: `bin/ermine-schema`, the `ermine/schema` LSP request | no | anything, on demand | zero — built |

**Recommendation: (c), plus (d) as the interactive form.** The value the
constraint was meant to deliver — "a widget that carries a function or an IO
action fails the build, not the request" — is delivered by the runner
refusing at boot/report-lookup time with a path into the type, which is where
the report's own contract lives. (a) is the only variant worth revisiting, and
only once `Layout/Doc.e` exists (J3b) so that "a boundary signature" has a
name to key on: `report : P -> Node`. It should then be a WARNING first, in
the `SigEntail` three-mode style (`Off`/`Warn`/`Error`,
`SigEntail.scala:62-72`, mode baked into the `.ei` key, `Session.scala:184-185`),
so a corpus that has never been checked this way cannot go red overnight.

## 5. If it is built anyway: the specification

For the record, so a later stage need not re-derive it.

- **Where**: a post-check pass over generalized schemes, called once per
  module from `Session.loadModule` (after `:1042`, before `writeInterface` at
  `:1051`) and once from `TolerantCheck.checkWith` (after `:1078`/`:1113`, via
  `guard` at `:844` so the LSP accumulates a `Note` instead of dying).
- **What it walks**: for each published `TermVar`, its scheme; strip
  `Forall`/`Exists`; if the result is `P -> Node` (the `Global` of
  `Layout.Doc.Node`, once J3b declares it) or mentions `Json.Json` in a
  position the boundary writes, run `Encode.reject` over the argument types
  and `Schema.exportType`/`Decode.entry` for the exact reading.
- **Free variables**: a scheme still quantifying over the offending variable
  is NOT an error — it is a polymorphic helper, and the instantiation is the
  caller's. Only a monomorphic boundary signature is checked. This is the
  one place the constraint would have been strictly stronger, and it is the
  price of staying out of inference.
- **Error and location**: `Subst.sourcePosition(v.loc).die(...)` with the
  `Encode.Rejected.report` wording already used by the sweep
  (`Encode.scala`, `Rejected.report(loc)`), i.e. `constructor C, field i:
  <reason>`; in the LSP a `Note` with a `Span` so it squiggles precisely
  (`TolerantCheck.Note`, `TolerantCheck.scala:60-71`;
  `lsp/Diagnostics.scala:314-322`).
- **Corpus impact**: zero today — no `.e` file in `core/examples/` mentions
  `toJson`, and no module declares a report signature yet, so the pass finds
  nothing to check. That is also why it cannot be tested on anything but
  generated modules until J3b/J3c land.
