# Brief: E2 — `core/examples/Algebra/`: the relational-algebra corners and the generic helpers around them

Read `tracker/loopmodel/briefs/brief-E-common.md` FIRST; it carries the conventions, rules, wiring policy and
gates. This file says only what E2 covers. Stage name `E2`; group `core/examples/Algebra/`, module prefix
`Algebra.`, helper library `Algebra/Helpers.e`, report `tracker/loopmodel/E2-EXAMPLES.md`.

WHAT IS UNDER-EXAMPLED HERE. `Relation.e` is the heart of the language and most of its constrained helpers have
no example at all: `joinWithDefault` / `rightJoinWithDefault` (signatures with `exists c s.` — the only
existential-quantified constraints in the stdlib), `leftJoinOr` / `rightJoinOr` / `unsafeRightJoin`,
`partialLookup` / `partialLookup'`, `groupBy` over a generic key row, `join1` / `joinBy` / `joinBy'` (a key split
into head and tail), `copyColumn`, `leafRows`, `memoRelWithPK` / `letRWithPK`, `filterEq`/`firstBy`/`lastBy`;
`Relation.UnifyFields`, `Relation.RTree`, `Relation.Scan`, `Relation.Process` have ZERO example uses; set
operations (union / except / intersect / difference), self-joins, semi- and anti-joins expressed with
`except`, transitive closures over parent/child (`leafRows` and friends), and `Syntax.Relation`'s comprehension
forms are barely covered. `Layout.Report.SoftRelation` / `softRelation` (key-value schemas) appears twice.

READ, beyond the common list: `core/src/main/resources/modules/Relation.e` in full (every signature with `<-`
or `exists`), `Relation/Row.e`, `Relation/UnifyFields.e`, `Relation/RTree.e`, `Relation/Scan.e`,
`Relation/Process.e`, `Relation/Predicate.e`, `Relation/Sort.e`, `Syntax/Relation.e`, `Record.e`; the existing
uses in `core/examples/Accumulate.e`, `GroupBy.e`, `SoftRelation.e`, `incomplete/TopReadings.e` (a ranking
join-back), `incomplete/RunCalibration.e`, `incomplete/RevenueShare.e`.

## What to build (eight to ten modules plus `Helpers.e`, all realistic reports over tables of 15–40 fields)

* `Helpers.e`: generic, explicitly-signed helpers — `lookupOr` (a `joinWithDefault` wrapper over a generic key
  row and a generic default record), `enrich` (left join keeping every left row, generic extra columns),
  `antiJoin` / `semiJoin` (via `except`, generic keys), `dedupeBy` (`firstBy`/`lastBy` over a generic ordering
  row), `groupSum`/`groupTop` (`groupBy` with a generic key and a generic aggregate), `closure` (transitive
  parent/child closure, generic id columns), `splitKey` (a `joinBy'`-style head/tail key), `carry` (`copyColumn`
  over a generic remainder), `unify` (a `Relation.UnifyFields` use that makes two differently-named schemas
  joinable), `scanCumulative` (`Relation.Scan`), `pipeline` (a `Relation.Process` use if it fits); two of them
  with an `xFull`/`xSimple` signature pair proved equivalent (the `Signatures.e` pattern).
* Reports: an order-ledger enrichment where several dimensions are missing rows (defaults vs outer joins vs
  anti-joins, side by side, same data); a bill-of-materials explosion (transitive closure, `leafRows`, quantity
  roll-up); a customer-360 built from six differently-shaped sources unified by `UnifyFields`; an inventory
  reconciliation (set differences between two snapshots, both directions, and the intersection); a
  deduplication report (latest-record-wins over a generic key, `firstBy`/`lastBy`); a soft-relation
  (key/value) schema turned back into a wide table and joined against a hard one; a self-join report (manager
  chains, pairwise comparisons); a scan/process report (running reconciliation over a sorted ledger); plus the
  `Algebra/shouldfail/` negative (a `joinWithDefault` whose default record misses a column; an `except` over
  non-matching headers) with the expected diagnostics.

The point for the certification corpus: `joinWithDefault`'s `exists c s.` constraints and the closure/scan
helpers should push the solver into shapes the census never sees (existential instantiation at call sites,
chained residuals, the `concrete` branch on wide rows). Measure it (G3) and say what moved.
