# Review brief: the 2.11 back-port of the signature-entailment check (BP-1 + BP-2)

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-backport`, branch `backport-2.11`, HEAD 4fefc51 plus the
UNCOMMITTED deliverables of BP-1 (`backport/SIG-ENTAIL-2.11.md`) and BP-2 (`backport/CORRECTIONS.md`). Toolchain:
`source backport/env-2.11.sh` then `sbt211 ...` (JDK 8, sbt 0.13.5). You edit nothing except your scratch
`/tmp/claude-1000/-home-dmitry-research-ermine/3b4fa818-f9ac-4380-9d0a-a3c555e26b26/scratchpad/review-BP/` and
your report `backport/REVIEW.md`. No commits; never `git stash`; never touch `../ermine-scala` (read-only `git show`
of 5162945 is the reference). Budget 90 minutes. Verdict ADVANCE / FIX-THEN-ADVANCE (exact edits) / BLOCK.

This lands the check on the PRODUCTION branch (2.11) with default `error`. Attack:
1. **The three `SCALA 2.11` edits in `SigEntail.scala`** and any other divergence from 5162945's file: `diff` the
   two (normalise CRLF) and confirm every hunk is one of the three marked edits; read each for a semantic slip
   (the `nextOption` helper, the `ThreadLocal` initialValue, the `freeNow` rename).
2. **`Subst.scala` hunks**: the call placed after the `:534` partition and BEFORE `restrictTypes`; the `:553`
   return untouched; the two `Site` allocations at `ann` (:671) and `sig` (:689) and NOT at the App case; the
   "declared at" position = the declared type's loc on this branch's fused pipeline (the pins say :112:13 etc.
   -- confirm those are the signature lines by opening the files).
3. **The two main hunks deliberately NOT ported** (`Partition._._3`, LSP-FFI tolerance): are they really
   unrelated to the check, or does the engine's `encode` depend on the first?
4. **Corrections**: `git diff HEAD -- core/src/main/resources/modules` -- byte-compare each corrected signature
   with 5162945's; the `SoftRelation.e` fix; CRLF/LF preserved per file (`git diff --stat`, CR counts).
5. **Gates, once**: `sbt211 core/test` (expect 735/735); `sbt211 'scalacheckBinding/runMain
   com.clarifi.reporting.TestSigEntailDiff'` (106 signatures, engine ≡ oracle; 2,000 random); the stdlib boots
   at the default; `core/examples` under `off` vs `error` differ on exactly sig01..05 (use BP-1's report §
   commands). Confirm sig03 is refused AT THE SIGNATURE on this branch.
Report `backport/REVIEW.md`, verdict first, under 150 lines.
