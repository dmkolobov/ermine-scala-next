# Review brief: LSP Stage 3 item 6.2 — types at binders (PARTIAL: let/where + signed + kinds; pattern binders forked)

You are reviewing item 6.2 in `/home/dmitry/research/ermine/ermine-scala` (branch `scala3-migration`, HEAD `361ff28`
plus the UNCOMMITTED deliverables: `session/TolerantCheck.scala`, `lsp/Resident.scala`, `lsp/Definitions.scala`,
`scalacheck-binding/src/main/scala/TestTolerantCheck.scala`, `tracker/tools/lsp-client.py`, fixtures
`tracker/lsp-tests/Locals.e`, `LocalsBroken.e`, `docs/lsp.md`, report `tracker/loopmodel/LSP3-6.2-LOCALS.md`).
Implementer's brief `tracker/loopmodel/briefs/brief-LSP3-6.2.md`; item of record `tracker/LSP-ROADMAP.md` § Stage 3,
6.2 with the STAGE-3 INVARIANTS and Decisions (a)(b); gates `tracker/GATE-POLICY.md`. You edit NOTHING except a
scratch directory `/tmp/claude-1000/-home-dmitry-research-ermine/474b5320-1073-4e5c-9628-fcdc126defc7/scratchpad/review-6.2/`
and your report `tracker/loopmodel/LSP3-6.2-REVIEW.md`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`; sbt allowed
(`sbt -batch -J-Xmx3g ...`). ONE JVM at a time, no background JVMs; `sbt core/compile core/copyResources` before any
`bin/ermine` gate; delete every `.ei` you cause (the boot writes 129 into the target module tree — delete them; never
the checked-in `tracker/g1-*`); do not touch `tracker/lean/`; no commits. Confirm first that `Subst.scala`,
`Type.scala`, `Lower.scala`, `Renamer.scala`, `Session.scala` are byte-identical to HEAD (`git diff --stat`) — the
tier is Tier 0 only if so.

1. **THE PREMISE FAILURE — the finding that matters most.** The report (§1) says a PATTERN binder's `V` meta is
   discarded by `Lower.pattern` (`VarP(v.map(_ => annotOf(c, n.span)))` → `Annot.annotAny`, id −1) and
   `Subst.inferPatternType`'s `VarP` case mints a fresh meta via `unbindAnnot` into a local copy of the body, so a
   zonk of the binder's own meta yields an unconstrained variable — 4811 of 5056 local binders unreachable.
   Re-derive it from the code (`Lower.scala` ~:322-352, `Subst.scala` ~:602-610, ~:930-933, ~:1010-1012,
   ~:1055-1057, `Annot.scala` ~:27-30) and REPRODUCE it live (a module with `f x = x && True`; show what the zonk
   of the arg's meta returns vs the pattern var's real type). Then the FORK (§8): (a) option 1, the flag-gated
   `hm.binderTypes` hook in `inferPatternType` — is it really ~8 lines, is it really batch-invisible with the flag
   off (what does the flag cost on the hot path?), and does the recorded `t` stay CONNECTED to what inference later
   constrains given `inferAltTypesPrime`'s substitution into a body copy and `Lam`'s `refreshList` — or would the
   zonk of the recorded meta also come back unconstrained? This is the question the user needs answered; read the
   code until you can say yes or no with the line that decides it. (b) option 2 rejected because it empties
   `Patterned.xs` — confirm that consequence. (c) is there an option 4 the implementer missed that needs no
   `Subst` change (e.g. reading the pattern var's type off the INFERRED alt — does inference leave the pattern's
   type anywhere reachable, `Remember`, the `Gamma`, the returned `Alt`?)
2. **What WAS delivered.** `collectLocals`: walk it — every node type recursed; `Let` implicit heads by zonk,
   explicit heads and signed pattern vars by DECLARATION (the report says zonking a local explicit head's meta would
   be wrong — confirm why); file-gating by `ps.loc.fileName`. Decision (a) rendering: `Pretty.prettyType(t, -1)` on
   the monotype, `lookupFresh` naming free metas — confirm `idy : a -> a` and the stated caveat (a local's `a` may
   not match the enclosing binding's letter) — is the caveat acceptable or misleading for a user? Decision (b) cache:
   `Cache.Entry` carries locals; the invariant argument (start lines in the group text, column-1 statements) — try
   to break it: an edit that moves a where-binder's def-site WITHOUT changing the group's fingerprint (trailing
   whitespace was the 5.5 lesson; a comment line inside the group? a blank line?). Kind hover via
   `Pretty.ppKindSchema`: check `Bool`, an own `data`, a higher-kinded type, a class.
3. **Tests.** The six new TestTolerantCheck properties: does the sweep really assert 0 misses for LetBound/WhereBound
   AND pin the pattern-binder class as the documented miss (so a future fix flips it visibly)? The invisibility set
   extended to locals — byte-identical warm/cold? Fast mode → null pinned? Component died → absent pinned? The
   28 new lsp-smoke checks (207 → 234): list them by fixture; are any of them asserting the PARTIAL behaviour in a
   way that would silently pass after option 1 lands (they should FAIL then, or be marked)?
4. **Perf.** The implementer's interleaved pairs: 1.621/1.679/1.706/1.621 (before/after/before/after), pooled
   −13.5 ms. Run ONE interleaved pair yourself (before = a scratch worktree build of 361ff28; load < 1.3) and say
   whether the item is inside the 5% budget. Typecheck half 0.500 → 0.485-ish per the report — plausible for one
   zonk per let/where binder?
5. **Gates, re-run ONCE.** compile+copyResources; `TestLoopTrace` 720/720; the seven targeted suites (`*TestTolerantCheck
   *TestTolerantRead *TestEditorBuffers *TestStage1Pins *TestReplDifferential *TestRenamer *TestLower`, implementer
   121/121 — note their BEFORE baseline run hung past 40 min and was killed; run the AFTER once and say whether
   anything hangs); `corpus-run.sh --batch <outdir>` 85/69/0 over 154; `repl-smoke.sh` 8/66 goldens unmodified;
   `lsp-smoke.sh` 234; boot 129; `.ei` 0 after cleanup. NOT full `core/test`.
6. **The report and the fork write-up.** Accurate against your numbers? Is §8's recommendation (option 1 as its own
   Tier-1 item) the right framing for the user, and is anything missing from what a yes/no needs?

Report format: findings table (id, severity, CONFIRMED/PLAUSIBLE/REFUTED, a paragraph each — the fork analysis in
item 1 gets as much space as it needs), gate table (implementer vs yours), verdict ADVANCE (commit the PARTIAL as
delivered, fork parked) / FIX-THEN-ADVANCE (list) / BLOCK (why). Your numbers go into the trackers. STOP after the report.
