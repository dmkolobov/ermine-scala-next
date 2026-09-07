# E2 REVIEW — `core/examples/Algebra/` judged as programs and as corpus

Reviewer pass over stage E2 (report `tracker/loopmodel/E2-EXAMPLES.md`, 749 lines; group
`core/examples/Algebra/`, 18 `.e` files + `README.md`, uncommitted). Brief:
`tracker/loopmodel/briefs/brief-E-review.md` with `$STAGE = E2`, `$GROUP = Algebra`, on top of
`brief-E-common.md` and `brief-E2.md`. Repository at `40f80aa` (branch `scala3-migration`), the three
row-solver defaults as adopted at `fe024a7`. Every `bin/ermine` below ran with
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, one JVM at a time, 2026-09-07, on a box
carrying three other agents (load average 2–17 across the session, so wall clocks are not comparable
with the implementer's; the solver counts are exact and are). Scratch:
`/home/dmitry/.claude/jobs/880c725d/tmp/review-E2/`. Every `.ei` I caused was deleted. No commits, no
edits outside this file and that scratch directory. Findings are prefixed `Q-`.

---

## Verdict: **FIX-THEN-ADVANCE**

The measurement is exemplary. I re-ran every gate and **every solver number in the report reproduces
to the digit** — 151,993 segments 0/0/0, the whole census table, the per-module table, the five
heaviest solves, all 89 published partition constraints, 18 of 23 renderings with identical row
counts. I confirmed all seven stdlib/language findings with minimal modules of my own, and refuted
none. The helper library is the best thing in the examples tree: 28 signatures that a person would
actually write, published verbatim, each with a doc comment that names the constraint and says why.

What fails is the PROSE, in the files a user reads. Eight module-header or in-line claims are wrong
about the group's own code (a helper listed as used that is never used, two field counts, a column
count repeated three times, "four renames" where there are five, "six" in the same file, a
comment attached to the wrong definition), one negative module records an expected diagnostic that my
re-run contradicts, four of the report's five heaviest-solve attributions name the wrong construct
and lead the report to the wrong conclusion about what the group costs the solver, one name clash
makes a module's own `>> ` recipe fail in the session the group README tells you to open, and the
wiring line for `core/examples/README.md` no longer fits the table E1 rewrote. These are cheap to
fix and none of them requires rewriting a module — but this group's whole purpose is to be read, so
they must be fixed before it is committed. The required fixes are listed in §10.

---

## 1. Gates re-run

| gate | report | mine | verdict |
|---|---|---|---|
| G1(a) 12 modules per file | 12 LOADED, rc=0 | **12 LOADED, rc=0, 0 `error:`, 0 `Unable to load`** | ✔ |
| G1(a) own check time | 0.25–1.25 s | 0.11–0.78 s (quieter box) | ✔ nothing near 30 s, no `.slow` |
| G1(a) 6 negatives per file | 6 REJECTED | **6 REJECTED**, 0.04–0.08 s to refuse | ✔ |
| G1(b) one batch | rc=0, 15.5 s, 12+6 | **rc=0, 12.6 s, 12 imported, 6 rejected**; own-time sum 4.27 s | ✔ |
| G1(d) the three sweeps | `Expected 271 but got 315` only | **19 proved / 1 falsified on the settled tree; no `Algebra/` file in any failure label across three runs** | ✔ (see §11) |
| G2 `Algebra` | 96,815 seg, 0/0/0, nonpart 1,813 | **96,815 / 0 / 0 / 0, nonpart 1,813, rejected 0** | ✔ exact |
| G2 `Algebra-shouldfail` | 55,178 seg, 0/0/0, nonpart 1,086, rejected 3 | **55,178 / 0 / 0 / 0, nonpart 1,086, rejected 3** | ✔ exact |
| G3 census | see §6 | every cell reproduced | ✔ exact |
| G4(a) renderings | 18 of 23, 2 `Mem`s refused | **18 of 23, identical row counts, same 5 failures, same 2 refusals** | ✔ exact |
| G4(b) `.ei` | 28/16/27 bindings, 55/31/3 partitions, nine modules at 0 | **identical** | ✔ exact |

Per-file own times, mine (`Importing module 'Algebra.X' (t)`, one JVM per file, `.ei` deleted first):
Helpers 0.52, BillOfMaterials 0.77, ManagerChains 0.78, OrderLedger 0.75, SoftSchema 0.61,
RateStatistics 0.60, KeyDiscipline 0.59, LedgerScan 0.56, InventorySnapshots 0.54, Customer360 0.53,
Deduplication 0.39, Signatures 0.11. Wall 8.4–10.9 s each, of which ~8 s is the stdlib boot.

`sbt core/testOnly *TestSurfaceParsers *TestStatementExtents *TestTolerantRead` (first run, 01:02):
18 properties proved, two falsified — `Surface parser 2.3a.headers agree with the fused pipeline
across the stdlib`, label `Expected 271 but got 315`, `315 files`. I confirmed the arithmetic
independently:
`find core/src/main/resources/modules -name '*.e'` = **161**, `find core/examples -name '*.e'` =
**154** (110 original + 18 Algebra + 13 Wide + 13 Time) = **315**. The header-agreement half of the
property passed on all 315 files; only the count assertion falsified. `TestStatementExtents`'s three
"271 files" properties name the count in their titles and do not assert it — all three proved.
`TestTolerantRead`'s bound is `>= 180` and its `notGoodCode = Set("shouldfail",
"shouldfail-controls", "incomplete")` matches the PARENT DIRECTORY NAME, so `Algebra/shouldfail` is
excluded with no change. The report's §6(d) analysis is correct in every particular.

**A caution about that sbt run, and a live race.** My first `testOnly` (01:02) also falsified
`Tolerant read.strict and tolerant agree, and the tolerant read is silent, over the corpus` with
`never became ready: List(BranchDeposits.e, ClaimsExperience.e, Leaderboard.e, MediaSpend.e,
RevenueShare.e, SalesLedger.e)` — five `Wide/` modules and one `incomplete/` one, **no Algebra
module**. Between my file census (00:44, `core/examples` = 154 `.e`: 110 + 18 Algebra + 13 Wide + 13
Time) and that run, another agent DELETED `core/examples/Wide/` entirely (it was back an hour later,
with `Present/` beside it), so the arithmetic for `TestSurfaceParsers` moved three times in an
hour: 315, then 302, then 156 example files. The TolerantRead
falsification is that race, not this group. I re-ran the three sweeps twice more; the results are in
§11. Short version: on the tree of 01:07 the only falsification was the count constant; on the tree
of 01:12 (after that constant was made derived, and after E4's `Present/` landed) the count property
PASSES and the only falsification names `core/examples/Present/SalesDashboard.e`. **No `Algebra/`
file appears in any failure label in any of the three runs.**

---

## 2. The modules as programs

I read all 18 `.e` files and both READMEs in full. As a body of work this is the strongest example
group in the tree: every module states its subject, its tables and their widths, the helpers it uses,
the solver shapes it is there to exercise, and a `>> :load` recipe; the data is small enough to check
by hand and every number I checked was right; and each module carries at least one thing a reader
would not have known (the `except`-based anti-join, `firstBy` being the DESCENDING limit,
`unionAllWithHeader`'s empty case, `join1`'s real meaning, `pivot`'s eleven-existential residual).

### The three best

1. **`InventorySnapshots.e`.** The cleanest teaching module in the group and the one I would give a
   new user first. The header derives the whole algebra from two primitives (`intersection = join`,
   `A\B = difference`, `symmetric = union of both differences`, `changed = the two differences
   semi-joined on the key`) and then the code does exactly that, in that order, with a six-row
   snapshot you can verify in your head. `mondayLeftOver` is not decoration: it is a machine-checked
   PROOF that changed+removed+unchanged partitions Monday, and it renders as 0 rows. I rendered it:
   `unchanged` 3, `trulyRemoved` 1 (BAT-9001 lot 5514, the quarantined one), `trulyAdded` 1
   (TAP-1000), `mondayLeftOver` 0 — 2+1+3 = Monday's 6. Every prose claim in the file is true.
2. **`KeyDiscipline.e`.** The module the brief actually asked for: `join`, `join1`, `joinBy`,
   `joinBy'` on ONE pair of tables that share two columns, with what each one promises spelled out,
   the `join1` finding written up in place, and `shouldfail/alg05` as its negative control. It also
   carries the only `memoRelWithPK`/`letRWithPK`/`materializeWithPK`/`replaceColumn` uses in the tree
   and is honest about what `letRWithPK` cannot contain. Its `joinOnAtLeast` line is the group's
   single heaviest solve, which is the right module for that to be in.
3. **`Signatures.e`.** It improves on its own model. `core/examples/incomplete/Signatures.e` proves
   only `deduped ⊢ full`; this file adds `xFullViaWritten = xAsWritten`, so the hand-written set and
   the inferred set are proved EQUIVALENT rather than one-way comparable, and it says why that
   matters. I checked the claim it rests on — that the three quoted `xFull` sets are verbatim what
   the compiler infers — by putting the three unannotated bodies in a scratch module and `:type`ing
   them (`probes/QInfer.e`). All three match, member for member:
   `antiJoin` → `(exists c b. r1 <- (r1), a <- (r1, b), r <- (c, r1), RelationalComb rel)`;
   `dedupeBy` → `(exists c r. r <- (c, h), kv <- (k, h, c), Relational rel)`;
   `groupSum` → `(exists t r1. kv2 <- (k, r), r1 <- (r, t), Relational rel, PrimitiveNum n,
   kv <- (k, t, r))`. The only difference from the file is the `exists` prefix the REPL prints and
   which the file drops (harmless — free row variables in a hand-written signature behave the same
   way, as `Helpers.ei`'s own `q`, `o`, `kt` show).

   **Q-13 (minor, but in the file whose job is precision).** `antiJoinAsWritten`'s comment says
   "Note it is NOT the deduped set renamed". It is. Map `k↦r1, p↦r, r↦b, o↦c1, q↦c` and
   `antiJoinAsWritten`'s two constraints become `b <- (r1, c1)` and `r <- (r1, c)`, which are
   `antiJoinDeduped`'s `b <- (c1, r1)` and `r <- (r1, c)` — identical, because the right-hand side of
   a partition is a set, which is the very fact `rot3A/B/C` at the bottom of the same file exists to
   establish. The `dedupeBy` and `groupSum` pairs ARE substantive (a three-part partition against two
   two-part ones with the intermediate row named; and the key/measure/remainder split against the
   inferred one). So the file proves three equivalences, two of which are interesting and one of
   which is a renaming that the comment mis-sells.

`Helpers.e` deserves a mention beside these three. Rules 1–3 at the top are the right rules, stated
with their evidence; the joins section explains natural join before wrapping it; `alias` vs
`overwriteWith` — two helpers that differ by exactly one constraint and are type errors in
complementary situations — is the single best piece of teaching in the group.

### The three weakest

1. **`ManagerChains.e`** — four separate documentation defects in one 170-line file (Q-3, Q-4, Q-5),
   and two of its nine report sections are empty by construction. The code is fine; the prose around
   it is the least reliable in the group, which matters most here because the self-join is the case
   where the reader most needs to trust the narration.
2. **`LedgerScan.e`** — the header sells `Relation.Scan` as the escape hatch for "running totals,
   ranks, 'the account with the most postings' — none of which the relational operators express", and
   then computes **none of them**. Every scan in the file is either a column-selection (`pickK`,
   `filterK`, `removeK`, `mapK`, `sortK`) or a per-group FOLD (`sumBy'`, `count'`), both of which
   `groupBy` also does — and the file says so itself by computing `totalsRelational` "the same way".
   So the one module in the group whose subject is order-dependent computation never does one. It
   also lists `updateK` under "Stdlib exercised" and never calls it (Q-6), and leaves
   `unreconciledAccounts` defined and unused. Census-wise it is one of the two modules that mint
   nothing at all (max draws 1, depth 0, 0 % generative) — the cheapest realistic report in the tree,
   which is a fine thing to know but makes it the least valuable module for the corpus too.
3. **`Deduplication.e`** — the other zero-minting module (max draws 1, depth 0). Its header lists
   `groupSum` under "Helpers used" and it never calls it (Q-6); `neverTouchedByErp` returns EVENT
   rows and is captioned "Customers the ERP feed never touched" (it is 4 event rows for 2 customers);
   and because everything it computes with `groupBy` is a `Mem`, **not one of its results can be
   rendered** — the only relation in it that reaches SQL is a `filterEq`. As a program it is correct
   and readable; as a corpus contribution and as a demonstration it is the thinnest.

(`Customer360.e` is a near miss for this list — it carries the group's best discovery, and its
"20 columns" is wrong three times over (Q-2) — but the `UnifyFields` write-up earns it its place.)

### Q-findings from reading the code

* **Q-1 (should fix). `valued` is defined in two modules of the group, and the clash breaks
  `KeyDiscipline.e`'s own recipe.** `Algebra/InventorySnapshots.e:141` and
  `Algebra/KeyDiscipline.e:139` both define `valued`. `KeyDiscipline.e`'s header says
  `>> :load …/Helpers.e`, `>> :load …/KeyDiscipline.e`, `>> valued` — and `Algebra/README.md` tells
  the reader to load the whole group in one session. Measured: with `Helpers.e KeyDiscipline.e` on
  the command line, `valued` prints its 23-column header; with `Helpers.e KeyDiscipline.e
  InventorySnapshots.e` (and in the group session the README prescribes) it answers
  `<interactive>:1:1: error: undefined term`. It is the only name collision in the group (I diffed
  every top-level binder across the twelve modules). Fix: rename `InventorySnapshots.valued` to
  `fridayValued` (it is used twice, at `valueByWarehouse` and `biggestLots`).
* **Q-2 (should fix). "The joined row is 20 columns wide" — it is 19.**
  `Customer360.e:23`, `Algebra/README.md` ("a 20-column joined row") and `E2-EXAMPLES.md` §1
  ("4 each, joined to **20**") all say twenty. Measured in the REPL: `customer360` and `displayed`
  are both `Mem` of **19** columns (4 crm + 3 billing + 3 web + 3 erp + 3 support + 3 loyalty). The
  report's own §G4(a) block prints the 19 names, so the report contradicts itself.
* **Q-3 (should fix). `ManagerChains.e` counts its own renames three ways and none is the code.**
  Line 77: "Four renames turn a copy of the employee table into a MANAGER table" — the pipeline at
  lines 85–89 has **five** (`employeeId`, `fullName`, `jobTitle`, `department`, `salaryEur`). Line 27
  (the header): "Six `rename`s in sequence over the same 14-column concrete header" — the sequence is
  five; there is a sixth `alias` in the file but it is at line 122, on the closure result, not in the
  sequence. `E2-EXAMPLES.md` §1 says "alias×5", which is right about the sequence and wrong about the
  module (six calls).
* **Q-4 (should fix). `ManagerChains.e` lists `carry` as a helper it uses and never uses it, and the
  comment that mentions it is attached to the wrong definition.** Line 21 lists `carry`; the only
  other occurrence is line 132, "`carry` copies the id so it can be grouped on under a name that says
  what the group means" — immediately above `spanOfControl = groupBy {managerId} count employees`,
  which calls plain `groupBy` and copies nothing. `E2-EXAMPLES.md` §1 repeats the claim.
* **Q-5 (should fix). `ManagerChains.e:141`: "The five most expensive teams, ranked inside the whole
  org (one group)"** describes `biggestTeams = groupTop {department} {salaryEur} 3 (asMem employees)`
  — which is the top **three** rows per **department**, i.e. neither five, nor teams, nor one group.
* **Q-6 (should fix). Two more module headers claim a helper or a stdlib function they do not use.**
  `Deduplication.e:23` lists `groupSum` (never called — `supersededCount` uses plain `groupBy … count`);
  `LedgerScan.e:26` lists `updateK` under "Stdlib exercised" (it appears only in a prose sentence at
  line 114). The report's §1 table is right about `Deduplication` and inherits the `ManagerChains`
  error.
* **Q-7 (should fix). `KeyDiscipline.e:25–27` mis-states two of its three table widths.**
  "calibrations (sensorId, readingDate, calibSource + 5 more)" — `calibrations` has **7** columns,
  so "+4 more"; "sensors (sensorId + 8 more)" — `sensors` has **5**, so "+4 more". (`E2-EXAMPLES.md`
  §1 has the right numbers, 12 + 7 + 5.)
* **Q-8 (minor). `SoftSchema.hottest` does not compute what its name says, and is dead.**
  `hottest = groupTop {siteCode} {assetId} 1 (asMem assetWithReadings)` ranks by `assetId`, so it is
  "the highest-numbered asset per site". It appears in no report and in no header list. Either rank
  by `tempC` (it is a `String` in this schema, so say so) or delete it.
* **Q-9 (minor). Three of the group's "answers" are empty by construction, and two of them are
  captioned as if they were about entities when they return event rows.**
  `Customer360.neverLoggedIn` (every CRM account has a web user in the data — 0 rows),
  `ManagerChains.leaversWhoManage` (the one leaver is an IC — 0 rows) and
  `RateStatistics.preliminaryOnly` (every specimen has a final run — 0 rows) are all structurally
  empty; `Deduplication.neverTouchedByErp` and `RateStatistics.preliminaryOnly` are captioned
  "Customers …" / "Specimens …" but yield feed events / runs. `InventorySnapshots.mondayLeftOver`
  is the good use of an empty result — it is a stated proof obligation. The other three are just
  missing data: one row of each demonstration table should be changed so the reader sees the
  mechanism fire.
* **Q-10 (minor). `union` is the only set primitive not wrapped.** `Helpers.e` gives
  `intersectRows`/`exceptRows` names and doc comments, and `InventorySnapshots.e`'s header names
  `union` and `difference` as the two primitives — but `union` is then called raw four times while
  its two siblings go through the library. A `unionRows` for symmetry (and to carry the doc comment
  about identical headers) would cost one line.

---

## 3. The negatives, and every expected diagnostic checked

All six are REJECTED, each with exactly one diagnostic, at the position its header records. I ran
them three ways: per file (`bin/ermine Helpers.e <one>`), in the shouldfail-only batch
(`bin/ermine Helpers.e shouldfail/*.e` — the command line the headers name) and in the whole-group
batch (Helpers + 11 reports + 6 negatives).

| module | position | per file | `Helpers.e shouldfail/*.e` | whole group |
|---|---|---|---|---|
| `alg01` 43:7 | ✔ | `failed to unify type (\|customerName, customerTier\|) with type (\|customerName\|)` | same | same |
| `alg02` 41:7 | ✔ | `failed to unify type (\|sku, binCode, onHandQty, allocatedQty\|) with type (\|sku, binCode, onHandQty\|)` | same | same |
| `alg03` 44:7 | ✔ | `… at field '…customerId': the whole contains it but no part does` | same | same |
| `alg04` 45:7 | ✔ | `Fields appear twice in row: …eventVersion` | same | same |
| `alg05` 59:7 | ✔ | `… '…readingDate': the whole contains it but no part does` | **`two parts of one partition both contain it`** | `the whole contains it but no part does` |
| `alg06` 48:7 | ✔ | **`a part contains it but the whole does not`** | `a part contains it but the whole does not` | **`the whole contains it but no part does`** |

Five of the six headers are exactly right. One is not:

* **Q-11 (should fix). `alg06`'s header records the wrong per-file clause.** It says the "other
  clause" (`the whole contains it but no part does`) is what you get "per file or inside the whole
  group's batch". Measured: per file you get the SAME clause as the shouldfail-only line
  (`a part contains it but the whole does not`); only the whole-group batch switches. `alg05`'s
  header, which makes the same claim, is correct — the two negatives partition the space differently
  and the headers were written as if they behaved alike. Fix `alg06`'s header (and, since a reader
  will compare them, say in both that the two modules flip at DIFFERENT points, which is itself the
  sharpest statement of the finding).

The four refutation classes the report claims are really three mechanisms — plain unification
(`alg01`, `alg02`), `RHS.merge` reached by substitution (`alg04`), and the `rowSound` blame path
(`alg03`, `alg05`, `alg06`) with three different clauses. That is a fair claim as long as "class" is
read as "distinct sentence", which is how the report's table reads it. No objection.

The negatives are otherwise very good: each one is minimal (3–4 fields, one bad line), each explains
the constraint arithmetic before quoting the message, and `alg04`'s note — that the SQL spelling of
the same mistake (`GROUP BY a,b … ORDER BY b LIMIT 1`) is legal and silently wrong — is the kind of
sentence that justifies a negative module existing.

---

## 4. The seven stdlib/language findings — each CONFIRMED with my own module

Probe sources: `/home/dmitry/.claude/jobs/880c725d/tmp/review-E2/probes/*.e`, all loaded in one JVM
with `QCommon.e` first; a probe that must fail fails on its own and the rest still load.

| # | claim | my probe | result |
|---|---|---|---|
| F1 | `Relation.UnifyFields.unify1` cannot unify differently-named schemas | `Q1a`, `Q1c`, `Q1d` | **CONFIRMED** |
| F2 | `join1`'s doc comment is wrong; `join1 f` ≡ `joinBy {f}` | `Q2a`–`Q2d` | **CONFIRMED** |
| F3 | a row variable in `[f1,f2]` relation-type syntax is read as a LABEL | `Q3a`, `Q3b`, `:type` | **CONFIRMED** |
| F4 | the `rowSound` blame CLAUSE varies with the command line at a fixed field | three command lines × 6 negatives | **CONFIRMED** (and see Q-11) |
| F5 | there is no `render`, contra `Ai/README.md` | source + `Console.scala` | **CONFIRMED** |
| F7 | `rename'` requires the destination column to already EXIST | `Q7a`, `Q7b` | **CONFIRMED** (with a caveat) |
| F8 | `Relation.Scan.sumBy'` forces the `Op` row to be the WHOLE group row | `Q8a`, `Q8b` | **CONFIRMED** |
| F9 | `Layout.Scan` does not re-export all of `Relation.Scan` | `Q9a` + the re-export list | **CONFIRMED** |
| §4 | the `Ai/README.md` RUnion3+RUnion2 "does not finish" figure | five shapes, both default sets | **DOES NOT REPRODUCE** |

**F1 — CONFIRMED, and stronger than the report puts it.** `unify1 : (r <- (h,f,t), r2 <- (h,f2,t))
=> Field f1 a -> Field f2 a -> [..r] -> [..r2] -> [..r]`. Two sources keyed differently but sharing
one attribute (`Q1a`: `[customerId, name]` against `[custId, name]`) is
`Row partitions are unsatisfiable at field 'QCommon.customerId': a part contains it but the whole
does not`. Single-column operands, the degenerate best case (`Q1c`: `[customerId]` against
`[custId]`), is rejected with the same sentence. The only shape that loads (`Q1d`) is both operands
at the SAME header — a self-semi-join under a key alias, exactly as `Customer360.selfAliasSemiJoin`
does. Note also what the constraints DON'T say: `f1`, the column being renamed, occurs in no
constraint at all, so nothing forces it to be a column of either operand. The module is 8 lines,
exports one function, and that function cannot do the one thing its name promises.

**F2 — CONFIRMED, exactly.** `Q2a` (`[k,a]` × `[k,b]`, one shared column) LOADS. `Q2b` (`[k,k2,a]` ×
`[k,k2,b]`, two shared) is rejected: `… at field 'Q2b.k2': a part contains it but the whole does
not`. `Q2c`, the same data through `joinBy {k}`, is rejected too (`… the whole contains it but no
part does`) — so `join1 f` and `joinBy {f}` reject the same programs, which is the report's claim.
`Q2d`, `joinBy' {k}`, LOADS — so `joinBy'` is indeed the only spelling of the weaker promise the
doc comment describes. `Relation.e:159–161`'s comment ("requires a witness that the intersection is
nonempty") is wrong as written.

**F3 — CONFIRMED, with the compiler's own words.** `Q3a` defines `mk : Field c String -> [aid, c]`
where `c` is declared nowhere; it LOADS, and `:type mk` answers
`forall (c: rho). Field c String -> Relation (|aid, c|)`. `Q3b` annotates a call site
`use : [aid, c2]; use = mk c2` and fails with
`failed to unify type (|aid, c2|) with type (|aid, c|)`. So the `c` in the result is a fixed LABEL,
the helper looks row-polymorphic and is not, and the failure surfaces at a later call site — which
is precisely how it bit `SoftSchema.e`. This is the most valuable of the seven for a user: it is a
silent trap in surface syntax, not an obscure stdlib corner.

**F4 — CONFIRMED** (table in §3). Same field, same position, three command lines, three different
sentences across two modules. A regression test must pin the field and the position, not the
sentence. This reproduces `tracker/tools/corpus-run.sh`'s header note ("seven modules print a
DIFFERENT CLAUSE of the same refutation") on fresh modules, which is what makes it worth a ticket
line: it is not an artefact of the seven older files.

**F5 — CONFIRMED.** `grep -rn '\brender\b' core/src/main/resources/modules/` finds four unrelated
doc comments and no term. `Console.scala`'s only `render` is a local `def` inside `:browse`
(lines 525–534). `core/examples/Ai/README.md:30` says "then `render <theReport>`". A `Report` is a
function of a `Writer` and every concrete writer is in `ermine-writers`. The correct fix is to
soften `Ai/README.md`; `Algebra/README.md` already says so plainly, which is the right place for it.

**F7 — CONFIRMED as behaviour; the report over-blames the doc.** `Q7a` (`rename' a b` on `[a]`,
destination absent) is rejected `… at field 'Q7a.b': the whole contains it but no part does`; `Q7b`
(on `[a, b]`) LOADS. So `rename'` is "replace `b` with `a`", not "rename `a` to `b`". But
`Relation.e:156`'s comment already says exactly that — "Removes `f2`, then renames `f1` to `f2`". The
defect is the NAME (and the absence of a signature: `rename'` is the only one of these with no
declared type), not a wrong doc comment. `Helpers.alias`/`overwriteWith` is the right response and
is the group's best single contribution to usability.

**F8 — CONFIRMED.** `col : Field r a -> Op r a` (`Relation/Op.e:36`) makes the Op's row exactly the
field's, and `sumBy' : (r <- (h,t), AsOp op, PrimitiveNum n) => op r n -> Field r2 n -> Scan z (k,
[..r]) -> Scan z (k, [..r2])` makes `r` both the Op's row and the whole group row. `Q8a` (a group row
with one column of remainder) fails `failed to unify type (|amt|) with type (|amt, extra|)`; `Q8b`,
`count'` over the identical scan, LOADS. `scanTotals`'s remainder-free signature is forced, exactly
as `Helpers.e` says. Worth noting for the ticket: `r <- (h,t)` in `sumBy'`/`avgBy'`/`count'` is
VACUOUS — `h` and `t` occur nowhere else in those signatures — so it costs a partition constraint at
every call site and buys nothing.

**F9 — CONFIRMED.** `Q9a` calls `removeK_Sc` and gets `error: undefined term`. Diffing
`Layout/Scan.e`'s re-export list against `Relation/Scan.e`'s exports, the omissions are exactly
**`removeK`, `removeBy`, `multiply`** — the report's three. (`sort` and `mapScan` are re-exported
under new names, `sortScan` and `map_Scan`, which is a separate small trap.)

**§4, the `Ai/README.md` "does not finish" figure — DOES NOT REPRODUCE, at either default set.** I
re-ran the implementer's four shapes and added a fifth of my own on a 16-column fact table with three
chained call sites:

| shape | mine (loaded box) | implementer |
|---|---|---|
| A `combine_Op (if_Op p a b) f rel` inline | 0.34 s | 0.35 s |
| B via a `withColumn` helper (`RUnion2` only) | 0.65 s | 0.20 s |
| C a helper bundling `RUnion3` AND `RUnion2` | **1.39 s** | 0.53 s |
| C at `-Dermine.rowSound=false -Dermine.dequeuePolicy=shipped` | **1.47 s** | 0.48 s |
| D the same helper with NO signature | **2.20 s** | 0.56 s |
| E (mine) the two lattices sharing every variable, no partition between | ill-typed, refused in 1.05 s | — |

The absolute numbers are inflated (load average 9–17 while I ran these); what matters is that C
finishes at both default sets and that the A < B ordering the README reports is not even stable
across runs. I agree with the report's conclusion and with its caution: the original helper's source
was not preserved, so this REFUTES the reconstruction, not the historical measurement.

One thing my run adds that the report's does not draw out: **D, the unsignatured helper, is the
slowest of the four** (2.20 s against C's 1.39 s). That is direct evidence for `Helpers.e`'s Rule 1
("every helper has an explicit signature"), which the file currently justifies only by pointing at
`SoftSchema.pivoted`'s residual. Worth adding to §4.

---

## 5. G2 — the L2 differential, reproduced exactly

Traced with `-Dermine.useInterface=false -Dermine.loadInSeries=true -Dermine.rowTrace=…` on the two
file lists the report's wiring proposes, replayed with `tracker/lean/.lake/build/bin/looptrace
--replay`, classified with `tracker/tools/looptrace-diff.py --segments --per-thread`. No `lake build`.

```
Algebra             files=12 ermine=21s segments=96815 model=46442ms  AGREE 96815  SKIP 0
  #summary segments=96815 replayed=96815 skipped=0 hashdiff=0 eqdiff=0 nonpart=1813 rejected=0
Algebra-shouldfail  files=7  ermine=18s segments=55178 model=1390ms   AGREE 55178  SKIP 0
  #summary segments=55178 replayed=55178 skipped=0 hashdiff=0 eqdiff=0 nonpart=1086 rejected=3
```

**151,993 segments, 0 skipped / 0 hashdiff / 0 eqdiff**, one thread each, and the model reproduces
the compiler's own three refutation sentences:

```
#REJECTED  55111  … 'Algebra.Shouldfail.Alg03.customerId': the whole contains it but no part does
#REJECTED  55161  … 'Algebra.Shouldfail.Alg05.readingDate': two parts of one partition both contain it
#REJECTED  55177  … 'Algebra.Shouldfail.Alg06.customerId': a part contains it but the whole does not
```

Identical to the report's table in every field. (The `LOOP-MODEL-PLAN.md` row says 151,519 — see
Q-16.) No disagreement of any kind; the new group replays through the model with no change to
`tracker/lean/`, which is the result G2 exists to establish.

---

## 6. G3 — the census, and where the report reads it wrong

Every cell reproduces. Populations traced in one session (`Ai` with `Common.e` first, `boot` a bare
`bin/ermine`), censused with `looptrace --replay … --cycle | --depth | --mints` and aggregated with
my own summariser (`summ.py`; row-carrying = `nparts > 0`).

| population | solves | vocab-fixed | generative | concrete | max draws | max deq | max depth | max per-key mints | max parts | max vars | max labels |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Algebra reports, all | 34,226 | 99.71 % | 0.31 % | 5.87 % | 14 | 54 | 2 | 1 | 8 | 10 | 26 |
| Algebra reports, row-carrying | 7,309 | 98.65 % | 1.45 % | 27.47 % | 14 | 54 | 2 | 1 | 8 | 10 | **26** |
| Algebra shouldfail, all | 102 | 95.10 % | 5.88 % | 8.82 % | 3 | 15 | 1 | 1 | 5 | 6 | 4 |
| Algebra shouldfail, row-carrying | 19 | 73.68 % | 31.58 % | 47.37 % | 3 | 15 | 1 | 1 | 5 | 6 | 4 |
| `Ai` baseline, row-carrying | 4,069 | 95.45 % | 4.55 % | 28.46 % | 52 | 137 | 3 | 1 | 7 | 11 | 14 |
| stdlib boot, row-carrying | 407 | 100 % | 0 % | 0 % | 1 | 34 | 0 | 0 | 13 | 30 | 0 |

Not one figure differs from the report's. (The boot row is the non-Algebra part of the Algebra trace,
62,589 solves of which 407 carry a row — I reproduced 407 exactly once I used that population; a
free-standing `bin/ermine` boot gives 54,199 solves / 373 row-carrying, same maxima. Worth one
clarifying word in the report about which population it is.)

The per-module table reproduces line for line, including the ordering:

```
module                  solves rowcarry maxdraw maxdeq maxdepth maxparts maxlbl  conc%  gen%
BillOfMaterials           5006     1167      13     50        2        8     20   26.6   1.5
ManagerChains             3516      787      11     45        2        5     19   27.6   1.4
OrderLedger               3504      759      12     45        2        7     26   27.9   1.7
InventorySnapshots        3503      754      13     51        2        7     15   27.2   1.2
LedgerScan                3684      746       1      4        0        3     13   30.4   0.0
RateStatistics            3250      736       3      9        1        4     13   27.7   2.3
Deduplication             2955      649       1      4        0        3     15   25.9   0.0
KeyDiscipline             2900      595      14     54        2        7     24   28.1   3.2
SoftSchema                2963      589       9     36        2        6     17   27.0   1.5
Customer360               2393      491      10     39        2        5     19   28.1   2.2
Helpers                    462       30       0      5        0        3      0    0.0   0.0
Signatures                  90        6       0      5        0        3      0    0.0   0.0
```

**The claim the brief asked me to check — that the group is GENTLER than `Ai` (max draws 14, depth
≤ 2, per-key mints ≤ 1) while reaching the widest concrete label set (26) — is TRUE, and I reproduce
it.** 14 draws against `Ai`'s 52, 54 dequeues against 137, depth 2 against 3, per-key mints 1 against
1, 26 labels against 14, 8 input partitions against 7. The budget headroom is 1,429×; the budget
never fired anywhere in the group. That is a real result about this compiler and it is stated
plainly, which is the right thing to do.

* **Q-12 (should fix — it changes what the census MEANS). Four of the report's five heaviest-solve
  attributions name the wrong construct.** I reproduce the five lines exactly, and then read the
  source at each site:

  | site | report's label | what is actually there |
  |---|---|---|
  | `KeyDiscipline.e(114:17)` deq=54 draws=14 | joinOnAtLeast | ✔ `joinedAtLeast = joinOnAtLeast {sensorId} readings calibrations` |
  | `InventorySnapshots.e(141:10)` deq=51 draws=13 | "qtyMoves' joinOnExactly" | ✘ `valued = combine_Op (col_Op onHandQty *_Op col_Op unitCostEur) valueEur stockFriday` |
  | `BillOfMaterials.e(137:3)` deq=50 draws=13 | "accumulate roll-up" | ✘ `positionCost`'s `combine_Op (col_Op qtyPer *_Op …)` (`accumulate` is at line 146) |
  | `InventorySnapshots.e(126:13)` deq=46 draws=11 | "the 14-column union" | ✘ `qtyMoves = combine_Op (col_Op onHandQty -_Op col_Op deltaQty) availableQty …` |
  | `KeyDiscipline.e(140:3)` deq=46 draws=12 | "letRWithPK" | ✘ `valued`'s first `combine_Op` (`letRWithPK` is at line 190) |

  Extending the list to eight, the pattern is unmistakable: **seven of the group's eight heaviest
  solves are `Relation.Op.combine`** — `ManagerChains.e(103:3)` (`compared`), `OrderLedger.e(191:10)`
  (`priced`, and the 26-label solve), `KeyDiscipline.e(141:3)` (`siValue`). Only the very
  top one is a relational-algebra operator.

  This matters because §G3's headline reading is "`Ai`'s expense is `if_Op`'s `RUnion3` lattices, not
  join arity. Relational algebra over concrete headers is cheap." The first half stands; the second
  half is being supported by four solves that are not relational algebra. The honest statement is:
  **the join spellings are cheap (one `joinBy'` at 54 dequeues is the group's ceiling), and what
  actually costs this group is the same thing that costs `Ai` — `combine`'s `RUnion2` — only over a
  wider concrete row, which is exactly why the label maximum moved from 14 to 26 while draws fell
  from 52 to 14.** That is a better finding than the one the report writes, and it is the one its own
  numbers support.

* Two modules mint nothing at all (`LedgerScan`, `Deduplication`: max draws 1, depth 0, 0 %
  generative) — reproduced. The report calls them "the cheapest realistic reports in the whole
  example tree"; see the §2 note on what that costs them as demonstrations.

---

## 7. G4 — renderings and interfaces

**Renderings.** I re-ran the implementer's probe through E1's `tracker/tools/sql-render.sh` with
`ERMINE_RENDER_MODULES` pointed at `Algebra/`. **18 of 23 relations executed, and every row count is
identical to the report's and to the modules' prose:**

```
q_order_priced   8   q_inv_unchanged  3   q_mgr_compared 11
q_order_semi     7   q_inv_removed    1   q_mgr_ic        6
q_order_noCust   1   q_inv_added      1   q_ledger_unrec  4
q_bom_cost      14   q_inv_leftover   0   q_rate_firm     8
q_bom_leaves     8   q_c360_core      4   q_key_valued    6
q_soft_wide      4   q_c360_never     0   q_dedupe_noerp  4
```

I checked the row content, not just the counts: `q_order_priced` returns all eight order lines with
`(unknown customer)` on 4004, `(partner)` on channel 3 and `(house account)` on reps 6003/6004, and
every `lineTotal` is `quantity × unitPrice × (1 − discountPct)` to the last float digit
(473.09999999999997 for line 9001/1, 359.64000000000004 for 9002/1). `q_inv_*` reproduces the
three-way split with `mondayLeftOver` at 0. `q_bom_leaves` returns exactly the eight nodes that are
nobody's parent. The renderings are real and the prose is honest.

The two `Mem`s answer `Don't know how to dump a mem.` — E1's limit 1 — and the report is right that
this bites harder here than in `Wide/`: everything `groupBy` produces in this group is a `Mem`, so
no grouped result in the directory can be executed at all.

**The five failures, and a sharper diagnosis than the report's.** Two classes:

* `q_bom_reach`, `q_mgr_reports`: `SQLITE_ERROR … near "insert"`. Both are `closure`, whose
  `materialize` emits a temp-table `insert` ahead of the select and `SqlRun` executes one statement.
  Agreed, and it is E1's limit 2.
* `q_inv_moves`, `q_key_serial`, `q_soft_assets`: `SQLITE_ERROR … near "on"`. The report leaves this
  "as an observation for whoever owns `SqlEmitter`". It is diagnosable from the emitted text. Stripping
  the literal row constructors out of `q_inv_moves.lite.sql` leaves the join skeleton

  ```
  from (A) t718851 JOIN (B) t718850 ON(..) JOIN (C) t718855 JOIN (D) t718854 ON(..) ON(..)
  ```

  — a join whose RIGHT operand is itself a join, emitted **without parentheses**, so the two trailing
  `ON` clauses stack and SQLite's grammar rejects the second. `q_order_priced`, which runs, is
  left-deep (`(((fact LJ dim) LJ dim) LJ dim) J dim`) and has one `ON` per `JOIN`. So the trigger is
  not outer joins and not join count: **`SqlEmitter` flattens a non-left-deep join tree and loses the
  grouping**. All three failures are relations whose right operand is a join or a difference-of-joins
  (`joinOnExactly` of two semi-joins; `replaceColumn` against an already-joined relation;
  `assetDim ** widened`). That is a one-line reproduction for whoever owns the emitter and I would put
  it in the ticket rather than leaving it as an observation.

**Interfaces (G4(b)).** Reproduced exactly, with `-Dermine.useInterface=true` over the group:
`Helpers.ei` 28 bindings / **55** partition constraints, `Signatures.ei` 16 / **31**, `SoftSchema.ei`
27 / **3**, the other nine 14–25 bindings and **0** partitions; total **89**. I read `Helpers.ei` in
full against `Helpers.e`: every published signature is the written one with the constraint list
permuted and `Has` expanded — no weakening, no extra constraint, no residual the author did not
write. **Deterministic:** I generated the twelve interfaces twice in separate JVMs and
`diff -rq` reports them byte-identical, which is the loader property the brief asks about.
`lookupOr` publishes its `exists (c: rho) (s: rho).` intact; `pickHighest`/`pickLowest`
publish `Has` as `(exists (c: rho). r <- (ord, c))`; `joinOnAtLeast`'s `kt` appears in all three
constraints and in no argument type, as claimed. The report's "26 signatures publishing 55 partition
constraints" is right (`intersectRows` and `exceptRows` are the two with no partition — they still
publish `RelationalComb rel`, so "26 with a residual" in the §G4(b) table is loose wording, not an
error).

**REPL headers (G4(a)(i)).** Reproduced for all eleven: `OrderLedger.priced` 26 columns,
`KeyDiscipline.valued` 23, `ManagerChains.compared` 19, `SoftSchema.assetWithReadings` 17,
`Deduplication.latest` 15, `InventorySnapshots.qtyMoves` 7, `RateStatistics.averages` 5,
`LedgerScan.totalsRelational` 2, `BillOfMaterials.reachable` 2 / `rolledUp` 2 — and
`Customer360.displayed` **19**, which is the measurement that contradicts the "20 columns" in three
places (Q-2). `ledgerReport` prints `(Report <function>)`. Note that the report's eleven sessions
each loaded `Helpers.e` plus ONE module, which is why they did not hit the `valued` clash (Q-1).

---

## 8. The 28 helpers as things a user would reuse

Judged as a library rather than as corpus fodder, this is very good. The names say what the
operations are for rather than what they are (`semiJoin`/`antiJoin` over `join`/`difference`;
`joinOn1`/`joinOnExactly`/`joinOnAtLeast` over `join1`/`joinBy`/`joinBy'`; `pickHighest`/`pickLowest`
over the genuinely misleading `firstBy`/`lastBy`). The argument orders are pipeline-friendly — the
relation is last in every helper that takes one, so `r |> semiJoin ks probe` and
`r |> groupTop ks ord 3` read correctly. Every doc comment names the constraint that carries the
generality and says what goes wrong without it, and three of them (`enrich`, `groupTop`, `alias` vs
`overwriteWith`) name the exact negative module that is the mistake.

Four observations:

* `enrich : rel r1 -> rel r2 -> {..t} -> rel r3` puts the default record LAST, after both relations,
  which is neither pipeline-friendly nor what a person would write (`enrich defaults dim fact`). It
  is `leftJoinOr`'s own argument order, inherited verbatim, so this is the stdlib's shape and the
  helper is right not to reorder it — but a sentence saying so would help, because it is the one
  helper in the file whose call sites read awkwardly (`OrderLedger.withCustomer` spans five lines
  before the record appears).
* `closure f t n e` is not a transitive closure, it is "closure up to path length 2^n", and the
  caller has to know the depth of their own hierarchy. The doc comment says so honestly, and both
  call sites pass 4 for hierarchies four deep. It is the right compromise in a language with no
  fixpoint, but the name overpromises slightly; `closureUpTo` would not.
* `intersectRows`/`exceptRows` are wrapped and `union` is not (Q-10).
* The two `Relation.Process` helpers (`groupMedian`, `groupWeightedMean`) are the best find in the
  file: `Relation.Process`'s aggregators are already `rel r -> Mem v`, which IS `groupBy`'s group
  function, so a median costs one line — and nothing in the tree used that module before. That is
  exactly the kind of thing the brief asked for.

The `Signatures.e` proofs hold — verified by construction (the module compiles, so each `p = q`
discharges `q`'s constraints from `p`'s) and independently at the level of the premise (§2, the three
inferred sets checked in the REPL). One comment mis-sells one of the three (Q-13).

---

## 9. Coverage: what the group reached, and what it missed

Reached, against `brief-E2.md`'s list: `joinWithDefault` (twice, `exists c s.` instantiated),
`leftJoinOr`, `rightJoinOr`, `partialLookup`, `groupBy` over a generic key row, `join1`, `joinBy`,
`joinBy'`, `copyColumn`, `leafRows`, `memoRelWithPK`, `letRWithPK`, `materializeWithPK`,
`replaceColumn`, `rename'`, `filterEq`, `firstBy`, `lastBy`, `topK`/`bottomK` via `Relation.Sort`,
`union`/`difference`/intersection-as-join/`unionAll`/`unionAllWithHeader`/`relationWithHeader`,
semi- and anti-joins via `except`, transitive closure, `Relation.UnifyFields` (and its refutation),
`Relation.RTree`, `Relation.Scan` (nine functions), `Relation.Process` (three),
`Relation.Aggregate`'s dispersion set, `maxRowBy`/`minRowBy`, `accumulate`, `Relation.Pivot`,
`Layout.Report.SoftRelation`/`softRelation`/`keyValueTabular`, `withFieldCopy`. That is a large,
genuine expansion and it does what the brief asked.

Missed, and the report's §7 "what I could not write" does not mention any of them:

* **Q-14 (should note). Three functions named in the brief's own list are absent:**
  `rightJoinWithDefault`, `unsafeRightJoin`, `partialLookup'`. None is inexpressible —
  `rightJoinWithDefault` is `lookupOr`'s mirror and would be a two-line helper beside
  `enrich`/`enrichRight`; `partialLookup'` is `translate` without the fold-back and would show what
  `coalesce'`'s `RUnion2` publishes when it is NOT hidden under a rename. They were simply not
  written. (`filterNEq` and the `lookupLatest*` family are also unused, but the report's §7 does
  account for those under the `Relation`/`Mem` split.)
* **Q-15 (should note). Zero uses of `Syntax.Relation`'s comprehension syntax.** `brief-E2.md` names
  "`Syntax.Relation`'s comprehension forms are barely covered" as one of the gaps to close; the group
  contains no `[| … |]` at all (`grep -c '\[|' core/examples/Algebra/*.e` = 0 in all 18 files). Since
  `[| x = z + 50, x > 100, y <- x |]` desugars to exactly the `rename`/`filter`/`combine` chain this
  group is built out of, one module written both ways — the algebra and the comprehension side by
  side, with the two inferred types compared — would have been the single highest-value addition, and
  is the obvious follow-up module.
* **No running total.** `LedgerScan.e` advertises order-dependent computation and delivers only
  per-group folds (§2). A `Relation.Scan` cumulative fold (`transform` over the vector, or `consume`
  with a `scanl`) is the missing demonstration; the module's §7 note ("a `Relation.Scan` fold that
  returns a relation" is impossible) is a different and correct point.

The report's §7 list is otherwise sound and I checked three of its claims: `letRWithPK`'s
continuation really is `Relation a -> Relation b` so a `groupBy` body cannot go in it (`Relation.e`);
`Layout.Scan.columns` really needs a `Column` so only the primed folds render; and the
`Relation`/`Mem` split really does force an `asMem` in eight of the ten reports — I counted, it is
eight (`BillOfMaterials`, `Customer360`, `Deduplication`, `KeyDiscipline`, `LedgerScan`,
`ManagerChains`, `RateStatistics`, `SoftSchema`). That last bullet is the most useful thing in the
report for the language's future and deserves to be lifted into a ticket in its own right.

---

## 10. Required fixes before this group is committed

Cheap, all of them; none touches a definition's meaning.

1. **Q-1** rename `InventorySnapshots.valued` (two uses) so `KeyDiscipline.e`'s own `>> valued`
   recipe works in the session `Algebra/README.md` prescribes.
2. **Q-2** "20 columns" → 19, in `Customer360.e:23`, `Algebra/README.md` and `E2-EXAMPLES.md` §1.
3. **Q-3, Q-4, Q-5** `ManagerChains.e`: "Four renames" → five; "Six `rename`s in sequence" → five in
   the sequence (six calls in the file); drop `carry` from the header list and fix or delete the
   orphaned comment at line 132; fix line 141's caption to "the three best-paid people in each
   department". Drop `carry` from `E2-EXAMPLES.md` §1's ManagerChains row.
4. **Q-6** drop `groupSum` from `Deduplication.e:23` and `updateK` from `LedgerScan.e:26` (or use
   them).
5. **Q-7** `KeyDiscipline.e:25–27`: calibrations "+4 more", sensors "+4 more".
6. **Q-11** correct `alg06`'s header: per file it prints the SAME clause as the shouldfail-only
   command line; only the whole-group batch switches. Say in both `alg05` and `alg06` that the two
   flip at different points.
7. **Q-12** correct §G3's five heaviest-solve labels and rewrite the "what moved" paragraph around
   what the sites actually are (`combine`'s `RUnion2` over a wide row, not join arity).
8. **Q-16** bring `tracker/LOOP-MODEL-PLAN.md`'s E2 row into line with the report (below).
9. **Q-17** replace wiring item (c) with a row that fits the table E1 rewrote (below).

Optional but recommended: Q-8 (`hottest`), Q-9 (three empty demonstrations), Q-10 (`unionRows`),
Q-13 (the `antiJoinAsWritten` comment), Q-14/Q-15 (a follow-up module — see §12).

---

## 11. Numbers of mine that differ from the report's

Everything the solver measures agrees exactly. These are the differences:

| # | the report says | I measure |
|---|---|---|
| Q-2 | `Customer360` joined row is **20** columns (§1, README, module header) | **19** (REPL header, and the report's own §G4(a) block prints 19 names) |
| Q-3 | `ManagerChains` uses `alias`×5 (§1); the module says four (line 77) and six (line 27) | the rename SEQUENCE is **5**; the file has **6** `alias` calls |
| Q-4 | `ManagerChains` helpers include `carry` (§1 and the module header) | `carry` is **never called** in `ManagerChains.e` |
| Q-11 | `alg05` and `alg06` both switch clause per file | `alg05` switches per file; **`alg06` does not** — it switches only in the whole-group batch |
| Q-12 | heaviest solves are `joinOnExactly`, `accumulate`, "the 14-column union", `letRWithPK` | one `joinOnAtLeast` and, for the other four (and three more), **`combine_Op`** |
| Q-16 | plan row: **151,519** segments, own check 0.29–1.34 s, batch 14.9 s | report §G2 says 151,993 and I measure 151,993; own check 0.18–1.84 s in the report, 0.11–0.78 s here; batch 15.5 s in the report, 12.6 s here. The plan row is stale against the report it summarises. |
| — | `sbt core/test` 912/914, `Expected 271 but got 315` | see below — the tree moved twice under me |
| — | `stdlib boot, row-carrying 407` | 407 if the population is the non-Algebra part of the Algebra trace (62,589 solves); a free-standing boot gives **54,199 solves / 373 row-carrying**, same maxima. Say which. |
| — | §4 timings A 0.35 / B 0.20 / C 0.53 / D 0.56 / C-old 0.48 | A 0.34 / B 0.65 / **C 1.39** / **D 2.20** / C-old 1.47 on a loaded box. Same conclusion; the A<B ordering is not stable, and D (no signature) being slowest is worth saying. |

Also not a disagreement but worth recording: `Helpers.e` has 62 `<-` tokens in the source and the
interface publishes 55 — the other seven are in doc comments and the closing note.

**On the test-suite gate, which moved twice while I was reviewing it.** At 00:44 the tree held 315
`.e` files (161 stdlib + 110 original examples + 18 Algebra + 13 `Wide` + 13 `Time`) and
`TestSurfaceParsers.scala:81` still asserted `files ?= 271`. At 01:02 my first run reproduced
`Expected 271 but got 315` **and** a second falsification (`Tolerant read … never became ready:
BranchDeposits.e, ClaimsExperience.e, Leaderboard.e, MediaSpend.e, RevenueShare.e, SalesLedger.e`)
caused by another agent deleting `core/examples/Wide/` mid-run. At 01:07, on the settled tree (302
files), the sweeps gave **19 proved / 1 falsified**: only `Expected 271 but got 302`, with
`Tolerant read.strict and tolerant agree … over the corpus: OK, proved property`. So the report's
claim — that the file-count constant is the ONLY thing in these sweeps that an E-stage moves, and
that `Algebra/shouldfail` is excluded from the tolerant sweep with no change — is confirmed.

By the time I wrote this, someone had already replaced the constant with a derived value
(`val expected = moduleFiles.size`), which supersedes the report's wiring item (d) entirely: **no
count needs bumping any more, and E2 should drop (d) and say so.** I re-ran the sweeps a third time
(01:12) against that fix and `Surface parser 2.3a.headers agree with the fused pipeline across the
stdlib` now **passes**. That run falsified `Tolerant read … over the corpus` again, with a different
cause and again not this group: `newly noisy: … SalesDashboard.e (type check):
core/examples/Present/SalesDashboard.e:246:3: error: failed to unify type Double with type Int` —
E4's `Present/` group had landed in the tree between my runs, broken. **Across three runs on three
different trees, no `Algebra/` file ever appears in a failure label**, which is the statement the gate
needs. The orchestrator should re-run these three suites once all the E-groups have settled; a
per-group verdict is not obtainable while five agents write into one working tree.

---

## 12. The wiring lines, checked

I drove both tools by hand with exactly the file lists the report proposes, and both worked (§5).
The `looptrace-corpus.sh` lines are correct as written; the `corpus-run.sh` lines are correct as
written; item (c) is not, and item (d) is now moot.

**(a) `tracker/tools/looptrace-corpus.sh` — CORRECT AS WRITTEN.** The default group list gains
`Algebra Algebra-shouldfail` after the `Wide` pair, and the two `case` arms hoist
`core/examples/Algebra/Helpers.e` in front of `find … -maxdepth 1 … ! -name 'Helpers.e' | sort`. Note
the arms are REQUIRED, not cosmetic: the script's `*)` fallback would glob `Algebra/*.e`
alphabetically and put `BillOfMaterials.e` before `Helpers.e`, and every module would fail to load.
Verified: 96,815 and 55,178 segments, both clean.

**(b) `tracker/tools/corpus-run.sh` — CORRECT AS WRITTEN**, against the file as it stands now
(lines 102–103, 108–118, 142–148). Two notes for whoever applies it: the `core/examples/Algebra/*)`
arm must sit before the `*)` catch-all (it does, beside the `Wide` arms), and it correctly also
matches `core/examples/Algebra/shouldfail/*`, which needs `Helpers.e` too. The hoist fires on the
first Algebra file in glob order, `BillOfMaterials.e`, which is right.

**(c) `core/examples/README.md` — STALE, must be rewritten. (Q-17.)** The report proposes two
two-column rows. E1 rewrote that table to **three** columns (`directory | subject | library`) and
moved `shouldfail/` out of the table into prose. Two-column rows would render broken. The rows that
fit are:

```
| `Algebra/` | ten reports over **relational algebra** — outer joins with defaults, set operations, semi/anti-joins, transitive closure, deduplication, key/value schemas, self-joins, `Relation.Scan`, `Relation.Process` | `Algebra/Helpers.e` |
```

and the prose sentence becomes "`shouldfail/` (and `Wide/shouldfail/`, `Algebra/shouldfail/`) hold
modules that must **not** compile …". The load line to add beside the other two:

```
bin/ermine core/examples/Algebra/Helpers.e core/examples/Algebra/OrderLedger.e
```

(If `Wide/` does not come back — it was deleted from the tree while I reviewed — drop its row and
its mention from the same sentence.)

**(d) `TestSurfaceParsers.scala:81` — NO LONGER NEEDED.** The constant has been replaced by
`val expected = moduleFiles.size`. E2's item (d) should be struck and replaced with a sentence saying
the count is now derived. The three "271 files" property titles in `TestStatementExtents.scala` are
cosmetic and still say 271; renaming them is optional and belongs to whoever owns that file, not to
E2.

**Also for the orchestrator, not in the report:** `Algebra/README.md` names
`tracker/tools/sql-render.sh` and `ERMINE_RENDER_MODULES`, both of which are E1's uncommitted files
(`tracker/tools/sql-render.sh`, `SqlRun.java`, `tsql2sqlite.py`). If E1's tooling is not committed,
`Algebra/README.md`'s "Seeing the numbers" section points at nothing. They should land together.

---

## 13. Tickets I would open (recommendation only — I wrote nothing)

**New `tracker/TICKET-stdlib-findings.md`**, because none of these belong in the editor/solver
ticket and they are the first systematic audit of `Relation.e`'s neighbourhood:

1. `Relation.UnifyFields.unify1` cannot unify differently-named schemas (F1). Its constraints force
   the operands to agree on all but one column each and never mention `f1`. Either fix the signature
   (`r <- (h, f1, t)`, `r2 <- (h, f2, t)`, result `r2`-shaped) or delete the module. Reproduction:
   `Algebra/shouldfail/alg03` and my `Q1a`/`Q1c`/`Q1d`.
2. `Relation.join1`'s doc comment is wrong (F2): `r <- (k, r1, r2)` means `f` is the WHOLE key.
   One-line fix to the comment; `joinBy' {f}` is the function the comment describes.
3. `Relation.rename'` has no signature and a name that inverts its meaning (F7). Adding
   `Helpers.overwriteWith`'s signature to the stdlib would be a strict improvement.
4. `Relation.Scan.sumBy'`/`sumBy`/`avgBy'` force the aggregate's `Op` row to be the whole group row
   (F8), and their `r <- (h,t)` is vacuous (`h`, `t` occur nowhere else) so it costs a partition
   constraint per call site for nothing.
5. `Layout.Scan` omits `removeK`, `removeBy`, `multiply` from its re-export list (F9), and renames
   `sort`→`sortScan`, `mapScan`→`map_Scan` without saying so.
6. **The `Relation`/`Mem` split** — `asMem` goes one way and nothing comes back, `groupBy`/
   `accumulate`/`medianBy` produce `Mem` while `filterEq`/`firstBy`/`lastBy`/`leafRows`/`unionAll`
   are `Relation`-only, and `join`/`union`/`difference` insist both operands be the same `rel`. Eight
   of this group's ten reports carry an `asMem` that exists only for that. This is the report's own
   §7 bullet and it is the most consequential thing either of us found.

**`tracker/TICKET-editor-and-solver-followups.md`:**

7. Item 4 (blame-clause instability) gains a fresh reproduction on modules written this week, with
   the exact three command lines and the observation that two negatives flip at DIFFERENT points
   (F4, Q-11). The actionable consequence: pin the field and position, never the sentence.
8. **New:** a row variable written inside `[f1, f2]` relation-type syntax is silently read as a LABEL
   (F3). `mk : Field c String -> [aid, c]` type-checks as
   `forall (c: rho). Field c String -> Relation (|aid, c|)` and every call site fails elsewhere. This
   is a diagnostics problem — a warning at the definition would have saved the implementer an
   iteration and will save every user one.

**Whoever owns `SqlEmitter`** (a new ticket or E1's): a non-left-deep join tree is emitted without
parentheses, so `A JOIN B ON c1 JOIN (C JOIN D ON c2) ON c3` comes out as
`A JOIN B ON c1 JOIN C JOIN D ON c2 ON c3` and SQLite rejects the second `ON`. Three of this group's
relations hit it; `render-sql/sql/q_inv_moves.lite.sql` in my scratch is the reproduction.

**Documentation, not tickets:** `core/examples/Ai/README.md` should stop saying `render <theReport>`
(F5) and should soften its "does not finish" row to name the helper it measured, since the
reconstruction does not reproduce at either default set (§4).

---

## 14. The follow-up module I would ask for

One module, `Algebra/Comprehensions.e`, closing Q-14 and Q-15 together: the same report written
twice — once as the `rename`/`filter`/`combine` chain this group is built from, once as
`[| … |]` — with `:type` on both and the two published residuals compared, plus
`rightJoinWithDefault` and `partialLookup'` used once each so the brief's list is closed. It would
add the one surface-syntax family the group does not touch, it would give the solver the desugared
`exists`-heavy shape `Syntax/Relation.e`'s own header advertises, and it is the natural home for a
`Relation.Scan` running total, which is the demonstration `LedgerScan.e` promises and does not give.

---

## 15. Bottom line

The measurement in `E2-EXAMPLES.md` is trustworthy: I re-ran all of it and every solver number,
interface count, render row count and census cell reproduces exactly. The library is the best thing
in `core/examples`, the negatives are well-chosen and well-explained, the seven findings about Ermine
are all real and I confirmed each with my own module, and the census claim the brief singled out —
gentler than `Ai` on draws, depth and mints while reaching the widest concrete label set — is true.

Against that: nine documentation defects in the files a user reads, one of which (Q-1) breaks a
module's own printed recipe, one wrong expected diagnostic (Q-11), one wrong reading of the group's
own census (Q-12), one stale wiring line (Q-17), and two acknowledged-nowhere coverage gaps (Q-14,
Q-15). **FIX-THEN-ADVANCE**: apply §10 (an hour's work, all of it prose), then commit.
