# WP-25 as built — `Session.scrub`: any set of modules is safe to unload

> **FOLDED INTO `tracker/JSON-WIDGET-PLAYGROUND.md` ON 2026-09-21** (§10's edits, plus §11's new `TestScrub` row and §14's new WP-28): **that document is the authority from here on**; this file is kept as the ticket's own record.

Branch `wp25-scrub`, worktree `ermine-scala-wt-wp6-perfA`, forked from
`widget-preview` at `f8fb9de7`.  Nothing committed, nothing pushed, no
`scripts/gate.sh` run.  This file is a **new** tracker note on purpose:
`tracker/JSON-WIDGET-PLAYGROUND.md` is being edited by other agents, and the
amendments below are listed in §10 for whoever merges.

**Round 2 (after the independent review).**  The review's MUST-FIX 1 was
correct and is fixed here: the claim that no dangling origin was reachable
was false on the resident's own 130-module session.  Fixing it properly
turned out to need a different repair from the one the review proposed —
§3 gives the measurements that decide it, and §12 records the two places
where I disagreed with the review — both since conceded by it — and §11
records the withdrawn acceptance criterion and the `canonWith` decision.

Every claim carries its evidence class.  **MEASURED** = a number this ticket
produced and the log it is in; **READ** = read off the source; **INFERRED** =
argued, not measured; **UNVERIFIED** = neither.

---

## 1. The defect, and the two fixes that do not work

**READ.**  `scrub` filtered `e.env` by each `V`'s **own defining** module and
every name table by the **key's** module.  A set holding a DEFINER but not
its RE-EXPORTERS deleted `Control.Functor.Functor` from `env` while
`Control.Monad.Functor` went on naming it; the next read of a module whose
spelling collapses to the origin died in `Subst.assertTermClosed` with
`undefined term` inside a stdlib file.

**The one-line fix WP-25 was filed with makes things worse.  MEASURED**
(`scratchpad/wp25-design.log`).  Dropping every `termNames` entry whose value
has left `env` removes the dangling entries — and the re-exporter is then
still in `loadedFiles` **looking loaded**, so `loadModules` will not read it
back and the name is gone from every importer of it:

| variant over the SAME 30 random subsets | dangling entity | reload died | surface == a fresh load |
|---|---|---|---|
| **v0** today's scrub | 16 of 30 | 0 of 30 | 30 of 30 |
| **v4** the proposed drop | 0 of 30 | **8 of 30** | **14 of 30** |
| **v1** close the set over RE-EXPORTERS | 0 of 30 | 0 of 30 | 30 of 30 |
| **v3** close over IMPORTERS (the full closure) | 0 of 30 | 0 of 30 | 30 of 30 |

On ROBUST-3's own reproduction, `scrub({Control.Functor, Maybe})` then
reload, **v4 dies with the SAME message as v0** — because the renamer answers
`Unresolved` with **no diagnostic** (`rename/Renamer.scala:381`, *"unknown
constructors die at typecheck"*), so `Lower.varFor` mints a placeholder and
`assertTermClosed` reports `undefined term` at the same span.  The honest
"not in scope" the proposal aimed at does not exist on this path.

So the fix is to WIDEN, over RE-EXPORTERS, and to return the widened set.

---

## 2. Every name→entity map, and whether it can dangle

**MEASURED** unless stated.  Baseline: on a **fresh load** every invariant
below holds with 0 violations (`wp25-inv.log`).

| map | shape | aliased entries (130-mod session) | can it dangle under the old scrub? |
|---|---|---|---|
| `env: V -> Runtime` | keyed by the ENTITY | — | **no**, it is the backing store (READ) |
| `termNames: Global -> V` | name → entity | 1850 of 3701 | **YES** — the defect |
| `cons: Global -> Con` | name → entity | 174 of 401 | **YES** — `cons->cons=3` in the first failing seeded subset.  This is the row the ticket called UNVERIFIED |
| `privateCons: Global -> Con` | name → entity | 0 of 78 | not observed; same code path, closed the same way (MEASURED 0 + INFERRED) |
| `classes: Global -> ClassDef` | name → entity | **0** of 14 | **cannot** — upgraded from "not observed" by the review: no source-level `instance` statement exists (`instance` is in `parsing/package.scala`'s `startingKeywords` and no parser consumes it), so `s.classes` is written only under the class's OWN name.  The `classes` arm of the closure and of the net are **dead by construction** and say so |
| `termNameOrigins` | name → NAME | 16418 entries | **YES**, and it needs a different repair — see §3 |
| `consOrigins` | name → NAME | 6144 entries | **YES**, same |
| `classOrigins` | name → NAME | **empty** | **no writer anywhere in the repo** — upgraded from UNVERIFIED by the review; the filter is dead by construction and says so |

Two facts that shape the fix, both MEASURED: `Type.Con.equals` compares
**only the name** (`Type.scala:566-568`) and an alias holds the *same object*
(`eq` true), so a stale type alias does not split type identity — it carries
a stale `decl`; and 29 `termNames` key modules lie outside `loadedModules`
(`Double`, `Field`, `IO.Unsafe`, `Native.Function`, `Layout.Presentation`, …)
— every one a builtin whose `V` never leaves `env`.

---

## 3. The fix

| file:line | change |
|---|---|
| `core/…/session/Session.scala:846-891` | `scrub` returns `Set[String]`, closes its argument over re-exporters, and runs a NET over the entity tables |
| `…/session/Session.scala:1015-1041` | `private def reExportClosure`, from the session's OWN tables, never `Session.depCache`; `builtin` is by-name and tested last (review N3) |
| `…/session/Session.scala:944-982` | **NEW in round 2**: `private def reorigin` + `greatestAncestors` — the re-export-chain repair |
| `…/lsp/Resident.scala:189-240` (`:208`, `:230`, `:238`) | `reloadModules` reloads / pends / reports the returned set |
| `…/lsp/Resident.scala:432-441` | `checkFile` ignores the return, with the reason and cost written down |
| `…/json/Runner.scala:713-728` (`:721`) | `invalidate0` evicts reports, logs and answers with the returned set |
| `scalacheck-binding/src/main/scala/TestScrub.scala` | the pin — 7 properties, two fixtures |

### 3a. The closure (round 1), unchanged

A module RE-EXPORTS when one of its name keys holds an entity belonging to
another module.  `reExportClosure` adds every LOADED module holding such a
key, to a fixpoint, skipping builtin entities.  It is **not** the importer
closure — a module that merely USES a name it does not re-export keeps its
own values and dangles nothing; that is staleness, the caller's question.
**MEASURED** on the 130-module session, closure of ONE module:

| closure | max | mean |
|---|---|---|
| re-export (shipped) | **6** | **1.8** |
| importer (`dependentsOf`) | 96 | 29.3 |

### 3b. The re-export-chain repair (round 2) — what the review found

**The review's MUST-FIX 1 reproduces exactly** (`wp25-repro-attack2.log`):
`scrub({Native})` on `Prelude`+`Layout` leaves **85** `termNameOrigins` and
**26** `consOrigins` entries keyed by a live name and pointing at a dead one.
My round-1 claim of "0 reachable" came from three scrubs, not a sweep.

**The mechanism.**  `termNameOrigins` records the IMPORT PATH, not the
definer.  `Prelude.Nil#` records that `Prelude` took the spelling from
`Native`; `Native.Nil#` records that `Native` took it from `Native.List`.
`reExportClosure` reasons about ENTITY ownership, and `Prelude.Nil#`'s entity
is `Native.List`'s — so `Prelude` correctly stays loaded while the name-level
link through `Native` is cut, and the walk stops at the dead `Native.Nil#`.

**Why that matters, exactly.**  `Renamer.resolveGlobal`
(`rename/Renamer.scala:158-164`) resolves **only a one-element** answer and
calls anything else `Ambiguous` — it compares NAMES, not entities.  So a
module reaching one spelling by two import paths used to collapse to ONE name
and now gets two.

**The four candidates, all measured on the 130-module session**
(`wp25-splice.log`, `wp25-cheap.log`).  The witness is
`module T where import Prelude; import Native.List; t = Nil#`, and the
control is that witness on the UNSCRUBBED session:

| candidate | R:termNameOrigins after | witness after `scrub({Native})` | the ambiguous case |
|---|---|---|---|
| control, no scrub | 0 | **loads** | dies (pre-existing) |
| **none** (round 1) | 85 | **DIES** `undefined term` | dies |
| **DROP the entry** (the review's option 1) | **0** | **STILL DIES** | dies |
| **FILTER the dead ancestor out** | **0** | **STILL DIES** | **wrongly LOADS** |
| **SPLICE — shipped** | 0 | **loads** | dies, as the control does |

**That table is the whole argument.**  Deleting the entries scores a perfect
0 on the invariant the review asked to be pinned and leaves the real failure
untouched; filtering additionally turns a legitimately ambiguous spelling
into a resolvable one.  Both would have shipped a green pin over a live bug.

**What SPLICE does** (`reorigin`, `Session.scala:944-982`): for every key that
is still a name and that points at a scrubbed name, replace that ancestor by
**its own greatest ancestors, computed over the table as it was before this
scrub** — so the walk reaches exactly the name it reached before.  It
deliberately does NOT remove a dead ancestor that IS a greatest ancestor
(`Relation.append` keeps naming `Relation.Row.append`): that spelling was
ambiguous before the scrub too, and staying ambiguous is faithful.

**The invariant that is pinned is therefore the WALK, not the table**: *for
every name still in scope, `collapseNames`' greatest-ancestor walk answers
what it answered before the scrub*.  **MEASURED**: `{Native}` moves **111**
answers before the repair and **0** after; for an importer-closed set —
every product caller with intact edges — `reorigin` repairs **0** entries,
because a key whose ancestor was scrubbed is then itself scrubbed.

### 3c. What was NOT changed

**Builtins** — untouched; a property asserts a scrub of every module leaves
them whole.  **`reloadChangedModules` and the REPL** — untouched; its set is
the transitive-importer closure `go` (`Session.scala:1057-1062`), closed by
construction, and its only caller-supplied extra is `Set("REPL")`, which
nothing re-exports; its failure path restores `sessionEnv := oldState`
wholesale.  It is a **drift trap, not a correctness hole**: it is now a
second scrub over a different set of tables, missing five of them —
`termNameOrigins`, `privateCons`, `consOrigins`, `classes`, `classOrigins` —
which §10 item 6 tickets.

---

## 4. The pin — `scalacheck-binding/src/main/scala/TestScrub.scala`

Seven properties over **two** fixtures.  The small one is `Layout.Doc`'s
closure (20 files, ~2 s); the big one is `Prelude` + `Layout` — what
`lsp.Resident.boot` loads, 130 modules, **one ~13 s boot**.  The big fixture
exists because **the small one cannot hold the defect**: it has no re-export
chain three deep, so no scrub of it ever cuts a name-level edge (MEASURED:
every scrub of the small fixture leaves the walk unchanged).

| property | fixture | asks |
|---|---|---|
| `any subset is safe to unload` | small | for an arbitrary subset: the four entity invariants; the passed set really left; **the returned set intersected with what was loaded is exactly what left**; **the walk is unchanged**; **`gone ⊆ dependentsOf(s)`** (review N1); **the net removed nothing** (review N2) |
| `the closure of a known module is exactly its re-exporters` | small | the exact closures — `Control.Functor → {Control.Alt, Control.Ap, Control.Functor, Control.Monad}`, `Control.Ap → 3`, `Control.Monad`/`Control.Alt`/`Maybe → themselves`.  Without this nothing would notice a regression to the importer closure (review N1) |
| `the thirty seeded subsets` | small | the same, over ROBUST-3's 30 seeded subsets |
| `scrubbing every module leaves the builtins whole` | small | builtins survive a scrub of everything |
| `reloading what scrub unloaded restores a fresh session` | small | four sets incl. ROBUST-3's `{Control.Functor, Maybe}`: the reload of the returned set does not die and the surface matches a fresh load |
| **`the resident's own session: any subset is still safe`** | **big** | the review's two named cases (`{Native}`, the six-module subset) plus 25 seeded subsets of 1–6 modules, all conjuncts above |
| **`a read after a failed reload resolves what a whole session resolves`** | **big** | scrub `{Native}`, **reload nothing** (the `pendingReload` state), then read the witness — **and assert the CONTROL**, that the witness reads on the unscrubbed session |
| **`the definition index's canonical keys survive a scrub`** (round 3) | **big** | `lsp/Definitions.canonWith` mirrored: **0** moved keys and **0** split buckets for importer-closed sets and for a sample of `checkFile`-shaped single-module scrubs; **exactly `{Prelude.head#, Prelude.tail#}`** for `{Native}`, the one measured exception, pinned by name.  See §11 |

Neither fixture's properties read process-global state in their verdict: both
snapshot their own importer graph at boot, under `literalLock`.

**RED before round 2's repair**, same tree otherwise (`wp25-red3.log`):

```
[info] ! Scrub.the resident's own session: any subset is still safe: Falsified after 0 passed tests.
[info] scrub of {Native} (by {Native}) moved the greatest-ancestor walk for 111 names in scope;
       e.g. Prelude.toEitherZ#: Native.Either.toEitherZ# -> Native.toEitherZ#
          | Prelude.fromPair#: Native.Pair.fromPair# -> Native.fromPair#
          | Prelude.appendRec#: Native.Record.appendRec# -> Native.appendRec#
[info] ! Scrub.a read after a failed reload resolves what a whole session resolves: Falsified after 0 passed tests.
[info] after scrub({Native}) -> {Native} with nothing reloaded, the witness died:
       WpScrubWitness<dynamic>:5:18: error: undefined term
[info] Failed: Total 7, Failed 2, Errors 0, Passed 5
```

**Note which five passed**: every small-fixture property was green on the
broken tree.  That is the review's point, measured.

**RED before round 1's fix** (`wp25-red2.log`): `Failed: Total 4, Failed 3,
Errors 0, Passed 1`, with `Maybe.e:53:16: error: undefined term` and
`25 of 30 seeded subsets leave a dangling name`.  For the *shipped* form of
the invariant the count is **16 of 30** (`wp25-final.log`), measured out of
tree against the unhardened scrub; ROBUST-3's own narrower `termNames->env`
probe scored **13 of 30** on its own seed — the three numbers are three
different questions, and §10 item 1 says so for the merge.

---

## 5. Timing

**MEASURED**, `scratchpad/wp25-timing2.log`: one process, one 130-module
`Prelude`+`Layout` session, the two columns **interleaved** and each run
twice with the lower taken, so a load spike shows as noise in both.  "before"
is the scrub as it stands at `f8fb9de7`, replicated in the probe.

| scrub of | before | after | unloads by |
|---|---|---|---|
| `{Maybe}` | 1.20 ms | 3.01 ms | 2 |
| `{Control.Functor}` | 1.13 ms | 3.57 ms | 6 |
| `{Layout.Doc}` | 1.08 ms | 2.58 ms | 1 |
| `{Layout.Report}` | 1.53 ms | 4.54 ms | 3 |
| `{Native}` — the one case where the chain repair does work | 1.26 ms | 3.25 ms | 1 |
| the review's six-module subset | 1.70 ms | 4.01 ms | 10 |
| `dependentsOf(Maybe)` — 77 modules, **the shape every product caller passes** | 2.28 ms | 3.11 ms | 77 |

**+1.5 to +3.0 ms** on the per-check path (`Resident.checkFile`, one scrub per
debounced keystroke, against a ~50 ms editor budget) and **+0.8 ms** on an
importer-closed reload.  **What the round-2 chain repair costs**, measured the way review N8 asked —
**one input, with and without it** (`wp25-n8.log`; the "without" column is
the shipped method with `reorigin` replaced by the plain module filter it
took over, everything else identical):

| scrub of | without the repair | with it | delta |
|---|---|---|---|
| `{Native}` — repairs 85 + 26 entries | 1.93 ms | 3.00 ms | **+1.07 ms** |
| `{Maybe}` — repairs none | 2.55 ms | 3.06 ms | **+0.51 ms** (the scan alone) |
| `{Layout.Report}` | 3.59 ms | 4.50 ms | +0.91 ms |

(Round 2 of this document said "about 0.2 ms when it fires" by comparing
`{Native}` with `{Maybe}` — two different inputs.  The figures above replace
that claim.)  For comparison the rejected whole-table prune measured
**6.9–7.8 ms** on the same shapes (`wp25-break.log`, `wp25-after.log`).

---

## 6. Verdicts

| run | command | verdict | log |
|---|---|---|---|
| sbt 1 | `core/Test/compile` + `*TestScrub` | **abandoned** — my own new suite deadlocked (§8); killed by me | `wp25-red.log` |
| sbt 2 | `core/testOnly *TestScrub` (round-1 tree) | **RED as designed**: `Failed: Total 4, Failed 3, Errors 0, Passed 1` | `wp25-red2.log` |
| sbt 3 | `core/Test/compile` + `*TestScrub` (round-1 fix, with the prune that was later dropped) | `Passed: Total 4, Failed 0, Errors 0, Passed 4` | `wp25-green1.log` |
| sbt 4 | `core/Test/compile`, `*TestScrub`, the eight targeted suites (round 1) | `PASS 212/212 591s` | `wp25-verify.log` |
| **sbt 5** | `core/Test/compile` + `*TestScrub`, round-2 pin against the **pre-repair** origins code | **RED as designed**: `scripts/test-summary.sh` → **`FAIL 5/7 failed=TestScrub red=2 29s`**; the five that passed are all small-fixture properties | `wp25-red3.log` |
| **sbt 6** | `core/Test/compile`, `core/testOnly *TestScrub`, `core/testOnly *TestLspRobustness *TestRunner *TestSchema *TestTolerantCheck *TestInterfaceKey *TestNamedFields *TestInterfaceRoundTrip *TestInterfaceConcreteRow` | `Passed: Total 7, Failed 0, Errors 0, Passed 7` and `Passed: Total 208, Failed 0, Errors 0, Passed 208` in **420 s**; `scripts/test-summary.sh` → **`PASS 215/215 447s`**, exit 0 | `wp25-verify2.log` |
| sbt 7 | `core/Test/compile` + `*TestScrub` (round 3) | **compile error in my own new property** — a tuple destructuring left over from the fixture change; no test ran | `wp25-red4.log` |
| **sbt 8** | the same, with the round-3 conjunct temporarily demanding **0** moved keys on `{Native}` | **RED as designed**: `Failed: Total 8, Failed 1, Errors 0, Passed 7` — `scrub({Native}) moved {Prelude.head#,Prelude.tail#}` — so the conjunct can fail; the other seven properties passed | `wp25-red5.log` |
| **sbt 9** | `core/Test/compile` + `core/testOnly *TestScrub` (shipped) | `[success] Total time: 7 s` for the compile; **`Passed: Total 8, Failed 0, Errors 0, Passed 8`** | `wp25-green3.log` |

**Round 3 changed no behaviour** — `Session.scala` differs from the tree the
eight targeted suites passed on **by comment lines only** (verified
mechanically: strip comment lines from both and they are identical), and
`Runner.scala`'s only non-comment change is round 1's, which those suites
already ran.  The targeted suites were therefore not re-run, per the
orchestrator's instruction.

`core/Test/compile` clean on the shipped tree (`[success] Total time: 11 s`),
no new warning.  The four cache-clearing suites are in that JVM on purpose.
**`core/test` in full was NOT run** — the `pr` gate does that once.

**The reviewer's own probes, re-run against the fixed classes**
(`wp25-after-attack.log`, `wp25-after-attack2.log`):

| probe | review's run | this tree |
|---|---|---|
| `[F1 Native]` reachable-dangling | `termNameOrigins=85 consOrigins=26` | **`0` and `0`** |
| `[F1 six-module]` reachable-dangling | `termNameOrigins=3` | **`3` — DELIBERATE, see §3b and §11** |
| `[C sweep]` 25 random subsets | `reload-died=0 dangling=2 net-fired=0 outside-dependentsOf=0` | `reload-died=0` **`dangling=1`** `net-fired=0 outside-dependentsOf=0` |
| `[A1..A7]`, `[B …]` structural checks | `saidSuperset:true`, `within-dependentsOf:IN`, `NETwouldDrop=0` everywhere | unchanged |

The remaining `dangling=1` is exactly `[C17]`, the six-module subset, and it
is the faithful case: those three entries name a greatest ancestor whose
module really was unloaded, and the spelling is ambiguous with or without the
scrub (MEASURED control, §12).  `TestScrub`'s own property covers that subset
and is green, because it asks about the WALK — which that subset does not
move — rather than about the table.

---

## 7. What is UNVERIFIED

* **Nothing exercises `Resident.reloadModules` against a real widening.**
  With dep-cache edges intact `dependentsOf` is already importer-closed, so
  the closure adds nothing and `reorigin` repairs nothing — which is why the
  LSP suites are green either way.  Both paths are exercised only by
  `TestScrub` and the probes.
* **The REPL's `:reload` was not run.**  `reloadChangedModules` is untouched;
  an argument from the diff, not a measurement.
* **`privateCons` was never observed to alias**, so its arm of the closure
  has never fired.
* The editor-path cost is a **microbenchmark**, not an end-to-end
  `didChange` round trip.
* **`lsp/Definitions.canonWith` is NOT repaired, and it does not degrade
  gracefully.**  (Round 2 of this document said it "degrades to a name with
  no target".  That was **wrong**, and the review measured it.)  `canonWith`
  (`lsp/Definitions.scala:839-853`) follows only a `Some(List(y))` entry and
  **stops at a multi-ancestor one**, so a splice that turns a one-element
  entry into a two-element one makes it stop early and return a **different
  LIVE name**.  `canonTerm`/`canonType` feed `gkey` → `GlobalKey`
  (`:858-859`), the bucketing key for definition, references and **rename**,
  so two buckets where there should be one is an **incomplete rename edit set
  — a wrong edit, not a missing answer**.  **MEASURED BY THE REVIEW**
  (`scratchpad/wp25-review-attack3.log`): after `scrub({Native})`, **2** keys
  still in scope move (`Prelude.head#: Native.head# -> Prelude.head#`,
  `Prelude.tail#` likewise); after a `checkFile`-shaped `scrub({Layout.Doc})`,
  **0**.  **Exposure is the WP-26 case only**: every product caller with
  intact dep-cache edges passes an importer-closed set and measures **0**
  repairs, and `lsp/Main.scala:224-226` drops the symbol and quickfix caches
  after each reload.  §11 says why no repair can fix it and what is pinned
  instead.
* The "`checkFile` never needs the widened-away modules back" argument rests
  on import acyclicity — INFERRED by me, and independently **verified by the
  review** against `Session.acyclic` (`:104-106`).

---

## 8. Two things the ticket did not expect

**sbt runs the properties of ONE `Properties` object in parallel.**  The
first cut of `TestScrub` took `literalLock` inside the fixture's `lazy val`
initializer *and* inside a property that then forced it — the property held
the lock while waiting on the initialization latch, against the thread that
had won the latch and was waiting for the lock.  It hung for seven minutes.
The rule is in the suite: **force the fixture BEFORE taking `literalLock`**.

**A witness needs a control.**  The review's proposed witness
(`import Relation; import Relation.Sort; t = append`) dies on an
**unscrubbed** session too — it is a genuinely ambiguous spelling, not a
scrub effect.  The shipped property asserts its control first, which is what
caught it.

---

## 9. WP-26 (shared `depCache` vs per-session staleness)

**Changed in severity, not in substance, FOR THE MECHANISM WP-26 NAMES.**
WP-26's worse case was: the resident refreshes a shared `depCache` entry with
a changed import list, `dependentsOf` loses an importer edge, the dirty set
stops being importer-closed, *"and the user would then see a 500 naming a
file they did not touch."*  For that mechanism the last clause is now false —
a non-closed set produces a correct, if larger, unload, the chains it cuts
are repaired, and the reload of the returned set restores a fresh session
(MEASURED: 30 of 30 mid-walk splits reload clean; 25 more subsets on the
resident's session in the review's sweep, `reload-died=0`).  It is **not** a
claim that no 500 is reachable by any route.

What WP-26 still is: **a staleness bug** — a render session can keep serving
an OLD module because the shared entry's mtime was refreshed by the resident;
symptom, a stale preview document.  Neither of its proposed shapes is
affected.  **Re-scope WP-26 to the staleness half and strike its "and then a
500" paragraph.**

---

## 10. Fold into the main tracker at merge

**Cited by TEXT ANCHOR only (review N10): `widget-preview` has moved to
`d3c4ee11` and will move again, so any line number here would be stale by
the time this is merged.**

1. `tracker/JSON-WIDGET-PLAYGROUND.md` §14 **WP-25** — the row containing
   `PROPOSED HARDENING, ONE LINE` and `THE TYPE SIDE IS UNVERIFIED`: mark BUILT; the one-line drop was **measured to be worse
   than the status quo** (§1); replace with the re-export closure, the
   returning signature and the chain repair; replace "THE TYPE SIDE IS
   UNVERIFIED" with §2's measured row.  **Reconcile the counts**: the row
   says *"FAILS TODAY on 13 of 30"* (ROBUST-3's narrower `termNames->env`
   probe, its own seed); the as-built's **16 of 30** is the shipped
   multi-table form on this ticket's seed; the first red run printed **25 of
   30** for a flat origins form that is no longer used.  Say which is which
   or the merged row reads as a contradiction.
2. §14 **WP-26** — the cell containing `the user would then see a 500 naming
   a file they did not touch`: strike that clause **for the mechanism
   WP-26 names** and re-scope to staleness (§9).
3. §13 **Q20** — the row beginning `should `Session.scrub` be hardened`:
   answered — built, with the evidence in §1 and §3b;
   note that the proposed one-line change was refuted by measurement.
4. §11's gate-cost row — the cell ending `seconds to a minute`: `TestScrub` is a new suite, 7 properties, two
   fixtures, one of which pays a ~13 s `Prelude`+`Layout` boot.  Measure it
   into the row from the `pr` gate's own log.
5. §11's render-session row — the one containing the sentence *"the product half is
   WP-25"* — that is the anchor to point at this file.  (Round 1 of this
   document attributed that sentence to `tracker/LSP-STALENESS.md:214`, which
   was wrong: that entry's text is *"it uncovered two PRODUCT tickets that are
   NOT built -- `tracker/JSON-WIDGET-PLAYGROUND.md` §14 WP-25 and WP-26, and
   §13 Q20"*.  Both anchors are worth updating; the review caught the
   misquote.)
6. New ticket: `Session.reloadChangedModules`' inline scrub
   (`Session.scala:1077-1088`, the block beginning `sessionEnv.env =
   oldState.env.filter`) is a second, weaker scrub — it touches only
   `env`, `termNames`, `cons`, `loadedFiles` and `loadedModules`, and misses
   **`termNameOrigins`, `privateCons`, `consOrigins`, `classes` and
   `classOrigins`**.  Fold it into `Session.scrub`.

---

## 11. The withdrawn acceptance criterion, and the `canonWith` decision

**WITHDRAWN.**  The orchestrator's round-2 acceptance criterion —
*`R:termNameOrigins = 0` on the six-module subset* — was **withdrawn on the
reviewer's recommendation**, with the instruction *"do NOT ship FILTER"*.
The reviewer ran its own DROP and FILTER implementations and reproduced this
document's table: DROP scores 0 dangling and the witness still dies; FILTER
wrongly loads the ambiguous case; and on that six-module subset **both
INTRODUCE walk movement (3) where round 1 and SPLICE have none**
(`wp25-review-attack3.log`).  The three entries that keep a dead greatest
ancestor are therefore the correct state, not a residual defect.

**The `canonWith` question, decided by measurement — NO cheap fix exists,
and this is a proof rather than a budget.**

The orchestrator asked whether the splice could keep a spliced entry
single-element when the dead ancestor had exactly ONE greatest ancestor, and
whether the two moving keys are the case where it had TWO.  Both answers are
MEASURED (`scratchpad/wp25-canon.log`):

| question | answer |
|---|---|
| is the singleton case already preserved? | **yes, it already is** — of the single-element origin entries, **16 331** have a target with ONE greatest ancestor and only **25** have more; the splice leaves the chase intact for all 16 331 |
| are the two moving keys the multi case? | **yes** — `greatestAncestors(Native.head#) = {Native.NonEmpty.head#, Native.List.head#}` (size 2), and likewise `tail#`; `Nil#` and `(::#)` have size 1 and do not move |
| can any value restore the old answer? | **no.**  `canonWith` answered `Native.head#` before — a name whose module has just been unloaded.  Every post-scrub value is a live name or the key itself, so no entry can equal a dead name.  The honest goal is the weaker one: *keys that canon'd to the same dead name still canon to ONE common name* — buckets do not split |

**So nothing was improvised.**  What is pinned, all MEASURED
(`wp25-canon.log`, and the property `the definition index's canonical keys
survive a scrub`):

| shape | canonical keys moved | buckets split |
|---|---|---|
| importer-closed (`dependentsOf` of each of the 130 modules) — **every product caller** | **0 of 130** | 0 |
| `checkFile`'s single-module scrub (all 130, one at a time) | **1 of 130** — only `{Native}`, moving 2 keys | 0 |
| arbitrary subsets (the suite's own 25 seeds) | **0 of 25** | 0 |

The property asserts 0 for the importer-closed shape and for a sample of
single-module scrubs, asserts **exactly `{Prelude.head#, Prelude.tail#}`**
for `{Native}` — so the limitation is pinned with its names, and any change
to it fails — and asserts **0 split buckets everywhere**.  It was shown RED
by demanding 0 for `{Native}` too (§6).

**One flake fixed while doing it**: round 2's upper-bound conjunct called
`Session.dependentsOf`, which reads the process-global `Session.depCache`
that four other suites `clear()`.  Both fixtures now snapshot their own
importer graph under `literalLock` at boot, so **no property's verdict reads
shared state** (`TestScrub.scala`, `Fix.dependentsOf`).

---

## 12. Where I disagree with the review

Both points are about the EVIDENCE, not the verdict — MUST-FIX 1 was right
and is fixed.

1. **The named "killing shape" is not one.**  The review picked
   `Relation.append`, which keeps two ancestors with one dead, as *"exactly
   the `Maybe.e:53` shape"* and reasoned that `collapseNames` would hand the
   renamer two names.  It would — **and it does so on an unscrubbed session
   too**: `module T where import Relation; import Relation.Sort; t = append`
   dies with `undefined term` with no scrub at all (MEASURED,
   `wp25-splice.log` `[control no scrub]`), because that spelling is
   genuinely ambiguous.  The six-module subset it came from moves the walk
   for **0** names (MEASURED, `wp25-cheap.log`).  The real witness is the
   one the review dismissed as *"singletons — harmless today"*: the 85
   `{Native}` entries, where the chain is cut in the MIDDLE and a walk that
   used to reach `Native.List.Nil#` now stops at the dead `Native.Nil#`.
   The singleton-skip quirk applies to the CANONICAL entry, not to the
   origins entry, so a module seeing the spelling by two paths still chases.
2. **The proposed repair does not repair.**  Option (1) — drop the reachable
   dangling entries — was priced from my own `wp25-break.log` and judged
   *"semantically right"*.  MEASURED: it takes the invariant to 0 and the
   witness still dies (§3b).  The invariant the review asked to be pinned is
   satisfiable without fixing the bug, which is why the shipped pin asks
   about the WALK instead.

Everything else in the review is accepted and applied: MUST-FIX 2 (the
contract wording, §3), N1 (the upper bound and the exact closures), N2 (the
net pinned rather than asserted), N3 (`consider`'s by-name `builtin`), N4
(dead by construction for `classes` and `classOrigins`), the scaladoc
definition of "safe" and the `DataConDecl` line, the `Maybe`-restricted
surface note, §9's "for the mechanism WP-26 names", and §10's items 1, 5 and
6.
