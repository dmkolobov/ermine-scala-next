# Brief: E11c-kind — the principled answer on `ChartsExample.e:stackedPair`'s kind binders (1 h)

Repo `/home/dmitry/research/ermine/ermine-scala`, branch `scala3-migration`, HEAD `5e2b6e9c` (E11c committed, flag
`-Dermine.solveDet` default OFF). Read `tracker/loopmodel/E11c-SOLVEDET.md` §6a and §5(d) (the `stackedPair` row) and
`tracker/loopmodel/E11c-REVIEW.md` R-3 first. Scratch:
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11c-kind/` (create it);
the two published renderings are `…/scratchpad/e11c/ei-pre/core_examples_ChartsExample.ei` (OFF, kind-polymorphic)
and `…/scratchpad/e11c/ei-on/core_examples_ChartsExample.ei` (ON, three binders fewer), line 22 each. You change NO
source and NO tracker file except your report `tracker/loopmodel/E11c-KIND.md`; scratch Ermine test modules and a
throw-away driver are fine (delete any test-tree file before writing up). Delete every `.ei` you cause under
`core/target` and under `core/examples`. Never commit, never flip a default. JVMs may run in parallel with anything.
Toolchain: `~/.claude/projects/-home-dmitry-research-ermine/memory/ermine-scala-toolchain.md` (PATH exports;
`bin/ermine` REPL; `-D` flags reach it via the launcher's JAVA_OPTS or `sbt core/console` -- find the shortest path
and say which). Budget 1 hour; at the budget, write up what you have.

## The question

Under OFF (shipped), at some id bases, `stackedPair : forall {a a1 b b1 c} (tdxfyf': a) (xa': a1) (ya': b)
(tdxfyf: b1) … (sa: c) …` -- five kind binders, `tdxfyf'`, `tdxfyf`, `sa` kind-polymorphic. Under ON (and, the report
implies, at other OFF bases) `forall {a b} tdxfyf' (xa': a) (ya': b) tdxfyf … sa …` -- those three at kind `*`. The
mechanism named: `typeDefComponents`' order (id-hash order as shipped, source order under ON) decides whether a kind
variable is still free at the point a group is generalised. WHICH ANSWER IS PRINCIPLED, and is the other one a bug?

## What to establish, with evidence

1. **The binding and its use of the three parameters.** `core/examples/ChartsExample.e:491` `stackedPair opts s x y
   r1 r2 = …`. Which type variables are `tdxfyf'`, `tdxfyf`, `sa` (they are probably minted names: say what they
   stand for in the inferred type) and where in the body they occur. Are they ever applied to arguments (which forces
   kind `k -> k'`) or constrained to `*` (used as a field type, a function argument type, etc.)? If they occur only
   as phantom parameters of some type constructor, what does THAT constructor's kind signature say about them?
2. **Where the kind is decided.** Read the kind checker (`Subst.kindCheck` :540 and its callers at :315/:318/:716,
   `KindSchema.scala`, `Statement.typeDefComponents` :150 and whatever generalises a type/data group's kinds). State,
   with line cites, the generalisation rule for kind variables: at what point is a kind variable generalised, and is
   the HM side condition (do not generalise a variable free in the environment) applied to KIND variables across
   type-group boundaries? Then show concretely for `stackedPair` which data/type declaration's kind is still open
   when `stackedPair`'s group is generalised under the polymorphic order, and what later fixes it (if anything).
3. **Principal or over-generalised?** Two cases: (i) the three kind variables are genuinely unconstrained by the
   whole module -- then the polymorphic signature is the PRINCIPAL kind and ON defaults it prematurely (a bug in
   ON's direction, though a harmless one until a caller instantiates at a higher kind); (ii) a later group FIXES the
   variable to `*` -- then generalising it earlier is the classic HM over-generalisation of a variable shared with
   the environment, the polymorphic signature is WRONG (more general than the module's own definitions justify),
   and ON is correct. Decide which, from the code path in 2 and the source in 1. If neither fits, say what does.
4. **A distinguishing program.** Write a scratch module that imports `ChartsExample` and instantiates one of the
   three parameters at a non-`*` kind (e.g. passes a value whose type mentions a type constructor there). Load it
   under OFF at a base that publishes the polymorphic signature (the E11a property's cold-check harness or repeated
   `Resident.checkFile`, or simply the REPL if it happens to land there -- say what you used and cite the rendering
   you got) and under ON. Report: accepted / rejected on each side, and if accepted under OFF, whether it evaluates
   correctly or misbehaves (an over-generalised kind usually shows up as a later kind error or a runtime cast; find
   out which). If you cannot reach the polymorphic base, say so and give the argument from 2-3 alone.
5. **Corpus impact.** Under ON, is `stackedPair` the ONLY binding whose kind binders shrink (the report says 7 of 274
   interfaces differ and this is the only kind change; confirm from `ei-classify`'s output in
   `…/scratchpad/e11c-review/rv-ei-classify.log`), and does anything in `core/examples` or the stdlib call
   `stackedPair` at all?

## Report `tracker/loopmodel/E11c-KIND.md`

Verdict first, one paragraph: which signature is principled, whether the other is a bug and in which direction, and
therefore whether the kind change is a reason to hold the flip, a reason FOR it, or neutral. Then the five sections
above with file:line cites and log paths. State what you could not establish. Time spent.

## Acceptance (five points)

1. The three parameters are identified in the source with their occurrences, and the constructor/kind that governs
   them is named.
2. The kind generalisation rule is stated from the code with line cites, and the concrete order dependence for
   `stackedPair` is shown (which group is open, what closes it).
3. The verdict is one of the three cases in point 3, argued from 1-2, not asserted.
4. The distinguishing program was attempted and its outcome under OFF and ON reported (or the reason it could not be
   run is stated).
5. No source or tracker change besides the report; no `.ei` left; nothing committed; inside 1 hour.
