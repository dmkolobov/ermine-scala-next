# Brief: S5 — residual hygiene: the tautology deletion (ticket C12) and a solver-configuration key on the `.ei` cache (Rose rank 6)

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from commit `c6ada70`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time, sbt allowed; `sbt core/compile
core/copyResources` before any `bin/ermine` gate; Lean `export PATH=$HOME/.elan/bin:$PATH` in `tracker/lean/`,
`LEAN_NUM_THREADS=2`, `lake build` allowed (you are the only agent; never while your own JVM runs `looptrace`); disk
rules (no `lake exe cache get`, no `require`, no new project, CutSearch out); delete every `.ei` you cause; no commits.
Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/S5/`. GATES per `tracker/GATE-POLICY.md`: Tier 0 always; Tier 1
for S5.1 (it changes published residuals) — the interface sweep with `ei-diff.sh --batch` under
`-Dermine.loadInSeries=true` both sides (or `--snapshot`), classified with `ei-classify.py`; the row trace must NOT
move (mkSimplified is post-loop): `TestLoopTrace` 720/720 and a two-group trace comparison with
`tracker/tools/trace-ab.py` (all record kinds) byte-identical.

## S5.1 — C12, the tautology deletion (read `tracker/TICKET-stdlib-findings.md` C12 in full first)
Five stdlib signatures (`Layout/Scan.e` `sumBy` :44, `sumBy'` :43, `count` :47, `count'` :48, `avgBy'` :45) publish
`(exists (t: rho) (h: rho). r <- (t, h)) => …` with `r` UNIVERSAL and both parts existential occurring nowhere
else. Every row splits (`t := r`, `h := ∅`), so the qualification constrains no caller.
(a) THE THEOREM, in `tracker/lean/Rowpartition/Determined.lean` (its `Residual`/`Holds`/`REquiv` vocabulary):
    `REquiv ⟨ex ∪ {t,h}, insert (mk r {t,h} ∅) G⟩ ⟨ex, G⟩` when `t`, `h` occur in no constraint of `G`, `r ∉ {t,h}`,
    `t ≠ h` — state the GENERAL form (k ≥ 1 existential parts, no concrete labels, all parts fresh w.r.t. `G`) and
    derive the two-part instance; witness `t := rho r`, remaining parts `∅` (the reviewer's
    `RevCheck.pairwise_not_necessary` in `/home/dmitry/.claude/jobs/880c725d/tmp/review-R3/Check1.lean` has the
    shape). Standard axioms; `#print axioms` saved. Say precisely how it relates to R3's
    `dead_delete_of_pairwise`/`_le_one_part` (left-hand side existential) — this one has the universal on the left.
(b) THE DELETION, in `Subst.mkSimplified` beside S3's `a <- (a)` case (`normalPart`/the `dumb` list): delete a
    partition whose left-hand side is universal (or any variable), whose parts are ALL existential, carry NO concrete
    labels, and occur in NO other published constraint. It must be exactly the theorem's side condition — no wider.
    Behind NO flag if criterion (c) holds; behind a flag default OFF if any other interface moves (then STOP and
    report before going on).
(c) THE MEASUREMENT: `ei-diff.sh --batch` over the stdlib + `core/examples`: EXACTLY the five signatures shorten and
    every other interface is byte-identical (this answers R3's open question of how many published interfaces
    change); `Present/Signatures.e`, `Algebra/Signatures.e`, `Time/Signatures.e` still check (any hand-written
    certificate of this tautology in the corpus now redundant? say which); `corpus-run.sh --batch` 85 / 69 / 0;
    `core/test` unchanged; `sql-render.sh` byte-identical.

## S5.2 — Rose rank 6, the `.ei` cache keyed by the solver configuration
TODAY nothing keys a published `.ei` by the rules that produced it (`Constraints.scala` ~1371 records the gap;
A1 review R-4; S4B review H-8): a tree built partly at one configuration silently mixes interfaces, and every
adoption has needed a manual `find . -name '*.ei' -delete`. With S5.1 (and the canonicaliser after it) the published
form is a function of the configuration, so this must land now.
(a) DEFINE the key: `GenRules.toString` is the fingerprint (`cut+label-early+resguard+…+pol:smallcanon+budget:20000+
    topnorm`); add a stable INTERFACE-FORMAT version (bump it in this stage, since S5.1 changes the published form)
    so `key = <format version>|<fingerprint>`. Say what is deliberately NOT in the key (e.g. `rowTrace`, `loadInSeries`,
    `foreign.tolerant` — anything that cannot change published bytes) and why, with a test that flipping such a flag
    does NOT invalidate the cache.
(b) WRITE it into the `.ei` header (find `writeInterface` in `Session.scala` ~:460 and the format the reader parses;
    keep the file's existing sortedness) and CHECK it on read: a mismatch is "stale" exactly like a source change
    (full check, rewrite) — find where `readInterface`/the interface hash chain decides currency and add the key to
    that decision, never as a separate path. A missing key (an old `.ei`) is stale.
(c) TESTS: a `core/test` property in the style of `TestInterfaceRoundTrip` (its own temp workspace, dep cache cleared
    under `ErmineFixture.literalLock`): cold write under configuration A, warm read under A = Interface; warm read
    under B (`-Dermine.topNormalise=false` or another key-bearing flag set programmatically on the SessionEnv if the
    property is read once at boot — say how you vary it) = Full and the file is rewritten with B's key; a non-key flag
    flipped = still Interface. Plus: the LSP `Resident` boots and `lsp-smoke.sh` stays green; `repl-smoke.sh` goldens
    unchanged; the 143 checked-in `.ei` under `tracker/g1-baseline`/`g1-oracle-tests` — say whether their readers
    (`G1Compare`, `TestTolerantRead`) parse the new header, and update the baselines ONLY if a test requires it
    (report what changed).
(d) Remove the "clear the cache once" instructions from the state file's ADOPTED blocks where the key now makes
    them unnecessary (additive dated note, do not rewrite history), and the `Constraints.scala` OPEN GAP comment.

## Report
`tracker/loopmodel/S5-HYGIENE.md`: the theorem, the deletion, the five-signature before/after, the sweep numbers,
the key format, the tests, every gate; ticket C12 "FIXED in <commit>"; plan row S5; state file additive notes;
`ROSE-COMPARISON.md` rank 6 dated DONE note. Outcomes: (GREEN) both; (PARTIAL) which and why. No silent weakening;
report early; STOP after the report — a reviewer re-runs the gates once.
