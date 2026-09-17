# SUBSUME-M2 REVIEW — merge `scala3-migration` into `json-encode`, and the B1 gate lift

Opus reviewer, 2026-09-17. I did not write this stage. Worktree `~/research/ermine/ermine-scala-wt-json`
(branch `json-encode`, merge commit **9ec3406d**, gate lift + follow-ups UNCOMMITTED). Every command below was
run from that worktree with `PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`
and `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=4"`. My logs are under
`<r>` = `/home/dmitry/research/ermine/scratch-subsume/review-m2/`; the implementer's are under
`<m>` = `/home/dmitry/research/ermine/scratch-subsume/m2/`.

## Verdict: **FIX-THEN-LAND**

One must-fix, and it is one number in a tracker document (§F-1). The merge itself, the gate lift and both
follow-ups are correct, and every gate I re-ran is green at or better than the reported figure. Nothing in the
uncommitted diff is outside what the report lists.

---

## 1. What I re-ran myself

| gate | my result | wall | my log |
|---|---|---|---|
| `sbt core/compile core/copyResources core/Test/compile` | **exit 0**, 0 errors, 0 warnings — the tree was already up to date at the follow-up state, so this confirms the compiled classes match the working tree rather than re-proving the compile | 5 s | `<r>/compile.log` |
| `timeout 600 sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'` — ALONE, default `minSuccessfulTests`, **no flag** | **13/13**, `Passed: Total 13, Failed 0, Errors 0`; **all thirteen read `OK, proved property`**, and `grep -c "passed 100 tests"` = **0**; the B1 refutation and `(B1-bound)` are both in that list | **244 s sbt / 4 min 08 s wall**, deadline never fired | `<r>/b1-alone.log` |
| `sbt 'core/testOnly com.clarifi.reporting.TestRunner'` ALONE | **17/17**; `(iso) … within a bound: OK, proved property` | 24 s | `<r>/testrunner-alone.log` |
| `sbt 'core/testOnly com.clarifi.reporting.TestNamedFields'` ALONE | **16/16**; *"an existential field gets no selector, a sibling still does"* reads `OK, proved property` (it read `OK, passed 100 tests` before F-1) | 18 s | `<r>/testnamedfields-alone.log` |
| `tracker/tools/lsp-smoke.sh` (classpath regenerated from this worktree, `git checkout --` afterwards — the tree is clean of it now) | **PASS, 582 checks**; the `RowUnsat.e` diagnostic is severity 1, *"Row partitions are unsatisfiable at field 'RowUnsat.startDate'"*, published **81 ms** after the `didOpen` (typecheck 0.06 s) | 63 s | `<r>/lsp-smoke.log`, `<r>/lsp-server.log` |
| instrumentation default OFF | read the `val`: `Subst.scala:2243` `val enabled = System.getProperty("ermine.subsumeTrace","false") == "true"`, read once like `RowTrace.enabled`; and no run of mine passed the flag — `grep -c subsumeTrace <r>/b1-alone.log` = **0** | — | — |
| `.ei` hygiene | my runs wrote **13** under `core/target/scala-3.3.8/classes/modules/` (gitignored); all deleted, `find core -name '*.ei' -newer <r>/EI-MARKER` = **0**, total back to the pre-review 117 | — | — |

**My B1 figure is the one I would put in a tracker**: 4 min 08 s alone at the default N, 13/13 all `proved`.
The implementer's 519 s was measured against the main checkout's M1 full run; mine was measured with the machine
otherwise idle. Either way the ten-minute deadline has ~2.5x headroom.

## 2. Read, not re-run (confirmed to say what the report says)

* `<m>/gate-full-core-test-2.log` — **`Passed: Total 1199, Failed 0, Errors 0, Passed 1199`**; I counted the
  property lines myself (`grep -cE '^\[info\] [+!] '` = **1199**) and the failure lines (`^\[info\] ! ` = **0**).
  sbt's own clock says **1214 s (20:14)** (the report says 1,218 s — see §F-4).
* `<m>/gate-full-core-test.log` (run 1) — 1199 property lines, `Failed: Total 1199, Failed 1`, **887 s (14:47)**;
  the one red is `(iso)`, "did not finish, 180004 ms", at **line 2763**.
* `<m>/gate-corpus-verdicts.txt` — **89 LOADED / 79 REJECTED / 0 UNKNOWN, 168 total**, which is json-encode's own
  baseline (`tracker/json-stage3/report-J3e.md`:224, report-J3a.md:74, report-J3c.md:142 all give 89/79/0).
  `<m>/gate-corpus-diff.txt` — **0 verdicts differ**; the only two file differences are the worktree path inside
  one message of `sk03`/`sk05`. No rejection became an acceptance or the reverse.
* `<m>/gate-check-corpus-fresh.log` — `tests 60 / pass 60 / fail 0`, `rc=0`, and it really is the fresh corpus
  (sbt re-wrote the 200 documents in the same log before the node run).
* `<m>/gate-b1.log` 13/13 (514 s), `<m>/gate-rowrefusals.log` 1 property 48 assertions (80 s),
  `<m>/gate-looptrace.log` 3/3 `720 solves; 720 segments; 720 agree; skipped=0 hashdiff=0 eqdiff=0 nonpart=0`,
  `<m>/gate-repl-smoke.log` PASS 9 groups / 86 checks (2+5+9+20+12+6+4+23+5), `<m>/gate-lsp-smoke.log` PASS 582,
  `<m>/followup-*.log` 16/16, 17/17, 46/46 — all as reported.
* `~/research/ermine/scratch-subsume/orch/m1-scala3-full-coretest.log` ends **20:20:23** after 1,124 s
  (1072/1072), so §4's contention account is accurate: it did overlap the compile, the B1 suite and the corpus
  batch, and it did not overlap either full `core/test`.

## 3. The merge resolutions — all three verified

**3.1 `Subst.scala`: both sides intact, exactly.** I ran both diffs the brief names.

* `git diff scala3-migration HEAD -- core/…/Subst.scala` = **+5/−5, five lines, all `sels`**: `:801`
  `case (b@DataStatement(l, v, kindArgs, typeArgs, cons, _), rk)`; `:831-832` the `DataStatement(…, cons, sels)`
  pattern and re-construction — the one site that *carries the field through*; `:1877` and `:1886` two `_`
  widenings. Nothing else. This is json-encode's named-fields change and it survived.
* `git diff 2afeb426 HEAD -- core/…/Subst.scala` = **+157/−2**, and I checked it is not merely the same count
  but the same patch: `diff <(git diff 2afeb426 HEAD -- …) <(git diff 478a369c scala3-migration -- …)` is
  **byte-identical**. S0's instrumentation arrived whole.
* The merged line numbers match the report's §1.1: `:367` `SubsumeTrace.cse`, `:618` `enter`, `:653` `atEscape`,
  `:654-655` `phaseFskvs`/`phaseKindVars`, `:2241` `object SubsumeTrace`.
* Third check: `TestNamedFields` 16/16 (§1) exercises the `sels` path; `TestRowRefusals`/B1 exercise `:648`.

**3.2 `tracker/tools/lsp-client.py`: both blocks kept.** `git diff --stat scala3-migration HEAD` = **+22**
(json-encode's `ermine/schema` block, 4 checks at `:448/:453/:456/:461`); `git diff --stat 2afeb426 HEAD` =
**+24** (S2's `RowUnsat.e` block, 5 checks at `:210/:213/:214/:216/:218`). Independently confirmed by count:
my own smoke run says **582 = 577 + 5**, and 577 is json-encode's figure at `report-J3e.md`:226 and
`review-J3e.md`:30.

**3.3 `TestDateAndScan.scala`: the union, then the lift.** On the merge commit,
`git diff scala3-migration HEAD -- TestDateAndScan.scala` is exactly json-encode's 12 lines — the `QUARANTINED`
comment plus `if (sys.props.contains("ermine.test.dateDiffReject"))` — standing above S2's `rejects(…)` body.
The report is right that this is the one place where a textually clean auto-merge is semantically wrong, and
right to make the gate lift the resolution rather than editing the merge commit. After the lift the working tree
differs from `scala3-migration` by **12 lines again**, all comment, no `if`.

**3.4 Nothing was lost in the merge.** `git diff 2afeb426 HEAD --diff-filter=D` is **empty** (no file deleted),
and json-encode's divergence from the base `478a369c` over all the programme's files is exactly the three files
the brief predicted (`git diff --stat 478a369c 2afeb426 --` over the eight candidate paths: Subst.scala 10,
TestDateAndScan 12, lsp-client.py 22 — the other five test files had no json-encode change to lose).

## 4. The gate lift — correct

* **The flag is gone from live code.** `grep -rn dateDiffReject` over the worktree returns only prose: the new
  `UNQUARANTINED` comment, GATE-POLICY's LIFTED paragraph, the ticket, the briefs and the programme reports. No
  `sys.props` read remains, so the property is registered unconditionally — confirmed by my own flagless run
  (§1), where it reports `OK, proved property`.
* **The body is `rejects`, not `no`** (`TestDateAndScan.scala:197-198`), and `import fx.{defAndEval, typeChecks, rejects}`
  at `:44` — `no` is no longer imported into this file at all, which is a nice belt-and-braces.
* **`tracker/GATE-POLICY.md`**: the nine-line bullet is gone and a seven-line `LIFTED 2026-09-17` paragraph
  stands after the bullet list, before "Standing rules that stay". The other four quarantines (disjunction,
  TestInterfaceRoundTrip, TestLegend, TestTolerantCheck E11a) are untouched — I diffed the section. Replacing
  rather than deleting is the right call: a reader who remembers the entry learns what happened to it.
* **`tracker/TICKET-editor-and-solver-followups.md` item 12**: heading marked CLOSED, and the appended section's
  citations check out one by one — 0.06–0.09 s at seventeen `Supply` id bases (S0 review §"1,099 s" block and
  `SUBSUME-STAGE2.md`:23; S0's own headline says 0.06–0.10 s over §1.3+§1.6, the 0.06–0.09 is the reviewer-verified
  17-base sweep, so the citation is the stronger one and is fine), 492,200 traced calls and `hm.types` max 1,566
  (`SUBSUME-STAGE0.md`:58-59), the S0 review's 1,099 s green run at the default N (`SUBSUME-STAGE0-REVIEW.md`:97),
  `no` → 100 evaluations and 1,282 s → 181–195 s / 1,698 s → 524 s (`SUBSUME-STAGE2.md`:32, :218, :39, :413), the
  58 ms LSP answer (`SUBSUME-STAGE2.md`:43, :385), and the `:648` perf residual 2.79 s/12.2 s = 23 %,
  45.4 s/184 s = 24.7 %, 12.1x `:365` (`TICKET-perf-type-inference.md`:97-101). **One figure is wrong — §F-1.**
* The property-count arithmetic is exact: 1,196 (json-encode at 5d0a2614, `JSON-STAGE3-PLAN.md`:351) + B1
  (registered at all for the first time on this branch) + `(B1-bound)` + `(rr)` = **1,199**, which is what both
  full runs report. The lift *adds* a property; it does not merely speed one up.

## 5. The follow-ups

**F-1, `TestNamedFields.scala:393` — confirmed, and confirmed to be the right shape.** The property's program is
a `val src = "data NfH = forall e. NfHidden { nfsecret : e, nfshown : Int }"` — a fixed string, **no generator
anywhere in the property** (I read `:391-402`); the other conjuncts are `typeChecks` and `sessionProof`. So
`rejects` is exactly right and `no`'s only effect was to ask ScalaCheck for 100 evaluations of a three-load
property. My flagless run has it as `OK, proved property` (§1). I also re-ran the census: the only remaining
`ErmineFixture.no` call site in the whole of `scalacheck-binding/src/main/scala` is **`TestScopes.scala:122`**,
which is `no(forAll(imported) { … })` — the one site the plan says must keep `no`. `TestDecode.scala`'s nine
`no(…)` calls are a local `def no(t: String, text: String): Decode.Error` at `:440`, unrelated. The report's
"one live site S2 never saw" is accurate and it is now the last one.

**F-2, `TestRunner.scala:941-965` `(iso)` — the diagnosis is sound and the fix is the right one.**

*The diagnosis.* I checked the run-1 log positions myself: the `(iso)` falsification is at **line 2763** of
`<m>/gate-full-core-test.log`, with `TestDateAndScan` properties completing at **2751** and **2756** just above
it and **2787** just below, and its two lock-holding properties — the B1 refutation at **2838** and `underZone`
("the same answers under five default zones") at **2847** — finishing shortly after. Timestamps in the
neighbouring lines (2757 = 20:33:27, 2770 = 20:33:44) put the failure at ≈20:33:30, i.e. the 180 s window opened
at ≈20:30:30, inside that suite's block. The mechanism is real and not inferred: `typeChecks` → `loadStatements`
→ `ErmineFixture.literalLock.synchronized` (`TestErmine.scala:152`), and `underZone`
(`TestDateAndScan.scala:51-56`) takes **the same monitor for a whole property body, several library-scale loads
long**. So a 180 s join on a `loadStatements` thread bounds the queue. This is the identical failure S2 hit in
its own first pin and wrote up as a rule (`TestDateAndScan.scala:228-238`, `SUBSUME-STAGE2.md` §2.3), and the
fix here is the identical move S2 made there (`typeChecks` → `loadNamed`).

*What is not proved, stated plainly.* No thread dump was taken at the moment of the red, so "blocked on the
monitor" is inferred from co-location plus the known lock, not observed; a 9x CPU starvation on a 4-core box
running many suites is not excluded, and the report says so itself ("honestly: not settled"). I agree with that
wording and with not quarantining. The fix is right under either cause, and it also makes the pin cheaper —
`TestRunner` alone went 44 s → 29 s for the implementer and 24 s for me.

*The change itself.* The 180 s deadline, the daemon thread, the `bootedOk` guard and `(answer.get ?= "ok")` are
character-for-character unchanged; only the loader and the module name moved
(`"IsoUse" + isoCounter.incrementAndGet()` at `:946`, its `AtomicInteger` at `:917`). `loadNamed`'s documented cost —
it takes no `literalLock`, so a load can be in flight while `underZone` has the JVM default zone changed, which
can change date VALUES but never a verdict (`TestErmine.scala:318-321`) — is respected: `(iso)` asserts a
verdict and nothing else. The unique-name requirement (`Session.Literal` identity is the module name) is met.
Two small observations, neither a finding: (a) `(iso)` no longer exercises the shared `"Test"` dep-cache key
after a Runner boot, but three dozen other properties in the same JVM still do, so the J3c intent (two
`SessionEnv`s coexisting) is intact; (b) this adds one more lock-free loader to a suite that already has two
(`(B1-bound)`, `TestRowRefusals`), which is a class of risk S2's review already signed.

## 6. Findings

**F-1 (must fix, one number). `tracker/TICKET-editor-and-solver-followups.md:411` cites a figure S0 retracted.**
The sentence reads *"0 cycles in 984,024 walks"* while the same sentence uses the corrected **492,200** call
count. 984,024 is the pre-correction number: `SUBSUME-STAGE0-REVIEW.md`:267 quotes S0's original §0.1 as
*"0 cycles in 984,024 identity-marked walks (492,012 escape checks …)"* and :269/:584 record the arithmetic as
FIXED to **492,200 / 984,400**, which is what `SUBSUME-STAGE0.md`:59 now says. *Failure scenario*: this
paragraph is the permanent closing record of a ticket that was closed on the strength of these very numbers; a
later reader who checks it against S0 finds a mismatched pair and has to re-derive which document is stale.
*Fix*: `984,024` → `984,400`. (Also stale at `SUBSUME-PLAN.md`:117, but that line is the programme's historical
log and predates the correction — out of scope for M2.)

**F-2 (should fix before the commit; hygiene, not a defect). `docs/JSON-GUIDE.md` must not be swept into the
gate-lift commit.** It is untracked, 87 KB, `mtime` 2026-09-16 21:01 — inside M2's working window, so a
`git add -A` or `git commit -a -A` would land it — yet its own header says *"Stages 0 through 3e, built
2026-09-14..16 on branch json-encode (tip 2afeb426)"*, i.e. it is JSON Stage-3 documentation written against the
**pre-merge** tip, not M2's product, and no review has read it. *Fix*: commit the six paths §5 of the report
names explicitly (the five modified files plus `tracker/satterm/SUBSUME-M2.md`, and now this review), never `-A`.

**F-3 (should fix; doc). `tracker/GATE-POLICY.md:66` — "the suite alone takes ~3 min" is optimistic for this
branch.** Measured on `json-encode`: **4 min 08 s** by me with the machine quiet, **8 min 34 s** by the
implementer beside another full `core/test`. The ~3 min is S2's figure on `scala3-migration`. *Failure
scenario*: a future agent sizes a deadline or a quarantine decision off this line and is surprised by a 9-minute
run under load. *Fix*: "~4 min alone, 8–9 min when the machine is busy; the suite carries its own 10-minute
deadline" — the number a reader needs is the headroom, not the best case.

**F-4 (nit; doc). `tracker/satterm/SUBSUME-M2.md` §4/§4.1 wall clocks do not match the logs they cite.** The
table says 519 s / 95 s / 43 s / 63 s and §4.1 says *"891 s (14:51)"* and *"1,218 s (20:18)"*, while the cited
logs' own `Total time` lines read 514 s / 80 s / 31 s and **887 s (14:47)** / **1214 s (20:14)**. The seconds
figures are defensible as command wall clock rather than sbt's internal clock (and §4 states plainly that none
of them is tracker-grade), but the *parentheticals* are sbt's own `mm:ss` rendering, so `(14:51)`/`(20:18)`
contradict the very lines they transcribe. *Fix*: quote the log's `mm:ss`, or drop the parentheses and say
"command wall clock, sbt reports 887 s".

Nothing else in the uncommitted diff is outside the report's list: `git diff --stat` is exactly
TestDateAndScan +12/−12, TestNamedFields +1/−1, TestRunner +22/−3, GATE-POLICY +8/−9, TICKET +31/−1 (74/26
total, and the gate lift's three files are 51/22 as §3 claims); `tracker/repl-classpath.txt` is clean in the
working tree; the only untracked paths are `tracker/satterm/SUBSUME-M2.md`, this review, and F-2's
`docs/JSON-GUIDE.md`.

## 7. The answer I would sign

M2 is a merge and a gate lift; it does not re-derive the programme's answer and does not claim to. What it does
establish, and what I verified independently, is the part of the answer that the quarantine denied:

> **The check terminates, and the harness was the thing that did not.** On `json-encode`, with no flag, the B1
> refutation is `OK, proved property` in a 13/13 suite that finishes in **4 minutes** — against the 20-minute
> "does not terminate" that justified `-Dermine.test.dateDiffReject` on 2026-09-16. The refutation is the same
> refutation; only `no` → `rejects` changed. Carried over unchanged from the programme: the compiler's 0.06–0.09 s
> refusal at seventeen `Supply` id bases and 492,200 returning escape checks (S0), and `runV_steps` /
> `RejectTerm` / `EnvBound` (S1a/S1b) — **with S1b §8's limits still standing**: no termination theorem under
> `-Dermine.dequeuePolicy=shipped`, and the `runSP_*` soundness family still assumes `rowSoundBare = false`.
> The `:648` whole-environment walk remains expensive (23–25 % of a boot or a suite run); that is a performance
> ticket, and M2 is right that it is no reason to gate a test.

So: **YES for this path**, with those limits — and, for M2 specifically, the merge preserves both sides of every
divergence and the 1,199/1,199 full run is a real landing figure.
