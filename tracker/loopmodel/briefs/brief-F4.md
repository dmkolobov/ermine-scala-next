# Brief: F4 — the interface round-trip bug (ticket E1): a published partition with a CONCRETE part never warm-reads

Repository `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, from commit `9638e41`. Toolchain
`export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, ONE JVM at a time, sbt allowed; `sbt core/compile
core/copyResources` before any `bin/ermine` gate; delete every `.ei` you cause (never the 143 checked-in ones under
`tracker/g1-*`); do not touch `tracker/lean/`; no commits. Scratch `/home/dmitry/.claude/jobs/880c725d/tmp/F4/`.
Gates per `tracker/GATE-POLICY.md`: Tier 0; plus Tier 1's interface sweep and `g1-validate.sh` IF the fix is on the
printer (published bytes move); the row trace cannot move (this is the interface layer) — `TestLoopTrace` 720/720.

THE BUG (ticket `tracker/TICKET-stdlib-findings.md` E1; the S5 reviewer's probe
`/home/dmitry/.claude/jobs/880c725d/tmp/review-S5/probe/ConcProbe.e`, control `TautoProbe2.e`): a module whose
published signature carries a partition with a concrete-row PART, `r <- (h, (|foo|))`, is written to its `.ei` by
`Session.Dep.writeInterface` (~:560) but the interface parser `InterfaceParsers.interfaceSigs`
(`parsing/InterfaceParsers.scala:26`, built on `TypeParsers`) does not read that form back, so `Session.dep`'s
`preCk` yields `None`, the module is `CheckMethod.Full` on EVERY load and the `.ei` is rewritten every time
(observable: its mtime never converges). Silent: nothing fails. 18 of 268 corpus interfaces have the shape
(`Layout/Report/Relation.ei` among them). Concrete rows as TYPES round-trip fine (all 129 stdlib interfaces
warm-read, `Currency.ei` included); only a concrete row as a PART of a partition does not.

## What to do
F4.1 REPRODUCE: the probe, loaded twice with interfaces on, second load = Full and the `.ei` rewritten; the control
     second load = Interface. Then FIND THE CAUSE precisely: diff what the printer emits for that constraint against
     what `interfaceSigs`/`TypeParsers` accept (is it the `(|foo|)` spelling inside a part list, the `<-` constraint
     grammar, layout/indentation, or a `Part.apply` collapse on read that changes the type so the hash chain
     mismatches?). State which side is wrong: the PRINTER (emits something the language grammar does not read) or
     the PARSER (the interface grammar lags the type grammar). List every published form the printer can emit and
     tick each against the parser — this is criterion (3).
F4.2 FIX on the side that is wrong, with the smallest change. Prefer the PARSER (no published byte moves). If the
     PRINTER must change, the interface-format version in `Session.interfaceKey` bumps (`2|` → `3|`) so every old
     `.ei` is stale by key, and the Tier 1 sweep must show exactly which interfaces move and that every move is a
     spelling change of the same type (classify with `ei-classify.py`).
F4.3 TESTS: (1) the round-trip property in `TestInterfaceRoundTrip`'s style (own temp workspace, `Session.depCache.
     clear()` under `ErmineFixture.literalLock`, modules owning every interface they depend on — `TestInterfaceKey`
     is the pattern) that writes a module publishing `r <- (h, (|foo|))` and asserts the second load is
     `CheckMethod.Interface`; it MUST FAIL before the fix (show the failure). (2) A grammar round-trip property:
     every `.ei` the corpus produces (stdlib + `core/examples`, generated in a temp tree) parses with
     `interfaceSigs` and re-prints to the same bytes (or to a form that parses to the same types — say which and
     why). (3) The 18 corpus interfaces warm-read: two consecutive `bin/ermine` batch runs over the corpus rewrite
     0 `.ei` (mtimes unchanged on the second run) — list the 18 before/after.
F4.4 GATES: `core/test` (940 + your new properties); `TestLoopTrace` 720/720; `corpus-run.sh --batch` 85 / 69 / 0;
     `lsp-smoke.sh` 185 and `repl-smoke.sh` unchanged; `g1-validate.sh` 9/9 (if the printer changed, re-cut the
     baseline for exactly the moved spellings and list them); the LSP boot still 129 modules and — the payoff —
     the warm boot/load time of a tree containing the 18 modules before/after (measure it: this bug cost full
     inference for those modules on every warm load).
F4.5 REPORT `tracker/loopmodel/F4-ROUNDTRIP.md` (cause, the printer/parser table, the diff, the tests, the 18, the
     timing, every gate); ticket E1 "FIXED in <commit>"; plan row F4; a note beside the header-strip trap in
     `S5-HYGIENE.md` §2.3 is NOT needed — put the cross-reference in the ticket. Outcomes: (GREEN) fixed with all
     three tests; (PARTIAL) which criterion and why. No silent weakening; report early; STOP after the report — a
     reviewer re-runs the gates once.
