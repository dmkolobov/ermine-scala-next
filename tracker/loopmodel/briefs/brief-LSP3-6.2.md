# Brief: LSP Stage 3, item 6.2 — types at every binder (hover on locals; kinds on type names)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from the current HEAD (6.1 is
committed). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs. No commits. Do not touch
`tracker/lean/` or `tracker/LSP-ROADMAP.md`. Delete every `.ei` you cause (never the checked-in ones under
`tracker/g1-*`). Scratch: `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/6.2/`.
Item of record: `tracker/LSP-ROADMAP.md` § Stage 3, item **6.2**, plus the STAGE-3 INVARIANTS and Stage-3 Decisions
(a) and (b) above the checklist — read them first; gates `tracker/GATE-POLICY.md`; the fixture rule at the top of
`scalacheck-binding/src/main/scala/TestErmine.scala`.

WHY THIS IS NOW POSSIBLE (the premise the item rests on — verify it before building on it): Stages 0-2 deferred
hover on locals to the perf ticket. Since 5.4 the editor path runs inference itself: `TolerantCheck.checkWith`
infers each top-level binding SCC inside its own `Session.subst { implicit hm => ... }` block (implicit path ~:266,
explicit path ~:303), and `Lower.Ctx.binderV` (`rename/Lower.scala` ~:89) gives every renamer binder id ONE `V[Type]`
whose `loc` is `pos(defSiteSpan)` and whose type is a fresh meta (`unspecified(site)`). After inference succeeds,
`Subst.substType(v.extract)(hm)` inside that block is the binder's solved type — one zonk per binder, in a block
that already runs. No new inference, no `Subst.scala` change.

HARD RULES FOR THIS ITEM:
- BATCH FROZEN: `Session.load`, REPL goldens (`tracker/repl-tests/*.expected`), `TestReplDifferential`,
  `TestTolerantRead`'s agreement property — byte-identical / green. `TolerantCheck.check` (the non-LSP entry) keeps
  collecting NOTHING new (`wantLocals = false` default); only `Resident` asks for locals.
- NO `Subst.scala` / `Type.scala` CHANGE. If you find you need one (a private you cannot reach, a printer that does
  not exist), STOP, write what and why in the report, and continue with the rest — the orchestrator decides.
  `Pretty` (the printer) may gain a kind printer if none exists; that is not `Subst`.
- NO REQUEST-PATH WORK: hover answers from the index the last check built (`Definitions.Occ.hover`), as today.
- THE PERF BUDGET IS THE GATE (see 6.2.5). Over budget = the zonk stays behind the flag OFF, the item is PARKED
  with its number, and you still deliver everything else (kinds on type names, tests, fixtures).

## What to do

6.2.1 COLLECT. `TolerantCheck.Result` gains `locals: Map[(Int, Int), Type]` keyed by def-site (line, col) — the
      binder V's `loc` (`Pos.line`, `Pos.column`; check the field names), which `Lower` set from the renamer's
      `BinderInfo.defSite` start. `checkWith` gains `wantLocals: Boolean = false`. When true, INSIDE each component's
      `Session.subst` block, after `inferImplicitBindingTypes` (and, on the explicit path, after
      `typeCheckExplicitBinding`) returns, walk the component's terms and collect every `V[Type]` that is a BINDER
      (`VarP(v)` and the `v` inside `AsP`; `Lam` patterns; `Let`'s `is.map(_.v)`/`es.map(_.v)`; `Case` alt patterns —
      find the complete list of pattern/term node types in `Pattern.scala`/`Term.scala` and cover them all) whose
      `loc` is a real position in THIS file (not `.inferred`, not `Loc.builtin`), and record
      `Subst.substType(v.extract)`. Do the walk over the terms AS INFERRED (after `Term.subTerm(subs, comp)`), so the
      Vs are the ones inference touched. RENDERING (Decision a): the binder's monotype; metas still free after the
      component's generalisation render as type variables the way the top-level scheme renders them (say HOW you
      achieve that — `Type.close`? the same path `generalize` takes for the published type? — and pin it: a
      where-bound polymorphic helper shows `a -> a`, not a meta id); explicit local signatures show as declared;
      no `forall` on locals. State which binder kinds are reachable this way and which are not (e.g. a binder in a
      component that DIED is absent — correct; a `do` binder is a `Lam` pattern after desugar — reachable?).
6.2.2 CACHE (Decision b). `TolerantCheck.Cache.entries` values grow from `Map[String, Type]` to carry the
      component's locals too (a small case class). Reuse hits restore locals; note-bearing components stay uncached.
      Justify in code why a reused entry's local positions cannot have drifted (group text includes start lines;
      top-level statements start at column 1; so any edit that moves a def-site inside the group changes the key)
      — and TEST it: the 5.5 "reuse is invisible" set in `TestTolerantCheck` (props ~:139-148) extends to locals:
      warm == cold byte-identical for a body edit, an error-introducing edit, a fixing edit, a signature edit.
6.2.3 INDEX + HOVER. `Definitions.index`: a `ToBinder` occurrence whose binder is NOT `TopLevel` joins
      `binders(id).defSite` (startLine, startCol) → `checked.locals` and fills `Occ.hover` with
      `(spelling, type)`; the binder's own def-site occurrence (if the renamer emits one) hovers too. TYPE NAMES:
      type-level occurrences (`o.typeLevel`) resolving to a Con in `env.cons` (imported and own — own types are
      installed by `TolerantCheck`'s type phase into the check copy's `cons`) hover with the KIND: find how `Con`
      carries its kind schema (`con.schema`?) and how `:kind`/browse prints one (`Pretty` — reuse, do not
      reinvent); render as `Name : <kind>` in the same fenced block hover uses. Builtin type atoms without a Con
      stay null. In FAST MODE `checked.locals` is empty, so locals answer null (nothing computes them) — pin it.
6.2.4 TESTS. `TestTolerantCheck`: (i) every binder KIND gets a type — arg, let, where, do, case, as-pattern — on a
      fixture module written for it; (ii) a where-bound polymorphic helper shows its generalised monotype as type
      variables; (iii) an explicit local signature shows as declared; (iv) locals in a component that died are
      absent and the rest present; (v) the cache-invisibility set from 6.2.2; (vi) the 180-file SWEEP (stdlib +
      `core/examples`, the existing `corpusFiles`/`sweepFx` machinery in `TestTolerantRead`, or a sibling property):
      for every clean module, every renamer binder of a LOCAL kind (`Renamer.Result.binders` with kind in
      Arg/LetBound/WhereBound/DoBound/CaseBound — NOT the type-level kinds, not TopLevel) whose component checked
      has an entry in `locals` — report the miss count and list the first 10 misses by file:line:col; the property
      requires 0 misses, or documents the exact class of legitimate misses if there is one (e.g. binders inside
      `private`/`database` blocks?) — a class, not a number. Report the sweep's time before/after (it was 51 s).
      lsp-smoke, fixture `tracker/lsp-tests/Locals.e`: hover on an arg, a let, a where, a do and a case binder,
      each at its def-site and at a use (exact `Name : Type` strings); hover on a local after a didChange that
      moves its definition down a line (answers at the NEW position, old position null); hover on a local inside
      the healthy statement of a broken file; hover on `Bool` (imported) and on an own `data` type shows the kind;
      the same local in fast mode answers null; a local in a component that died answers null. Count grows from
      205; the number goes in your report.
6.2.5 THE PERF GATE — measure BEFORE you write 6.2.3, right after 6.2.1 compiles. Interleaved A/B on
      Layout/Report.e (1757 lines): `tracker/tools/perf-bench.sh editor -k 15` (read its header for the protocol,
      the load ceiling and the `.ei` pitfalls), BEFORE = a build of HEAD without your change (build it in scratch
      from a `git worktree`/`git stash` — say which; the classpath/`copyResources` must match), AFTER = your tree with
      `wantLocals` ON in `Resident`; order before/after/before/after, each side with load < 1.3 (wait for it; never
      under load). Report all four medians and the pooled delta. BUDGET: Δ ≤ 5% of the round trip (~80 ms of
      ~1.6 s). Over budget: leave the collection code in but `wantLocals = false` in `Resident`, deliver
      everything else, and write "PARKED: <numbers>" as the outcome — do not try to optimise into budget in this
      item (that is a Blocked/Awaiting design question for the orchestrator). Also report `Report.e`'s check time
      split (read / typecheck) from the LSP log line, before and after, and the sweep time from 6.2.4(vi).
6.2.6 GATES (Tier 0 + targeted): `sbt core/compile core/copyResources`; `sbt 'core/testOnly *TestLoopTrace'`
      720/720; `sbt 'core/testOnly *TestTolerantCheck *TestTolerantRead *TestEditorBuffers *TestStage1Pins
      *TestReplDifferential *TestRenamer *TestLower'` all green, counts before/after; `tracker/tools/corpus-run.sh
      --batch <scratch outdir>` 85 / 69 / 0 over 154; `tracker/tools/repl-smoke.sh` 8 groups / 66 checks, goldens
      unmodified; `tracker/tools/lsp-smoke.sh` (205 + yours); boot 129 modules. NOT the full `core/test`.
6.2.7 REPORT `tracker/loopmodel/LSP3-6.2-LOCALS.md`: the premise verified (where the binder V and its meta come
      from, with line numbers), the collection design (rendering of generalised metas; reachable vs unreachable
      binder kinds), the cache extension and its invariant, the perf table (four medians, delta, verdict against
      the budget), the sweep miss analysis, the kind-hover design, the diff summary, every gate number.
      Outcomes: (GREEN) locals ON within budget, all tests, kinds; (PARKED) locals OFF with the perf numbers,
      everything else delivered; (PARTIAL) which and why. No silent weakening; STOP after the report — a reviewer
      re-runs the gates and the perf pair once.
