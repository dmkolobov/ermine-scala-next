# Brief: signature entailment, stage S1 -- the warn-mode survey (measure before enforcing)

Worktree `/home/dmitry/research/ermine/ermine-scala-wt-sig`, branch `sig-entail` (NOT the main
checkout; another loop owns that one). Toolchain `export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`;
sbt allowed (`sbt -batch -J-Xmx3g ...`). ONE JVM at a time; before any Tier run or corpus
sweep check `pgrep -af sbt-launch` is empty and no file under
`../ermine-scala/tracker/loopmodel/` changed in the last 10 minutes (the LSP loop's agent may be
measuring there). No commits. Do not touch `tracker/lean/`. Delete every `.ei` you cause.
Scratch: a `S1/` directory under the session scratchpad named in your launch message.
Plan of record: `tracker/SIG-ENTAIL-PLAN.md` (read all of it first); gates
`tracker/GATE-POLICY.md`; the fixture rule at the top of
`scalacheck-binding/src/main/scala/TestErmine.scala` (never `System.setProperty` a per-call flag).

THIS STAGE MEASURES. It adds no entailment logic and changes no verdict. Shipped behaviour under
the default must be byte-identical.

## (a) The probe
Add `ermine.sigEntail` = `off` (default) | `warn`, read the way the other `GenRules`-style
flags are read (find the pattern in `Constraints.scala`/`Session.scala`; one read at session
construction, not per call). Under `warn`, in `Subst.subsumeType` (:527-553) when it is
checking a USER SIGNATURE -- reached from `typeCheck` (:638) and `typeCheckExplicitBinding`
(:655), and NOT from the App case (:918-924) or any other caller: first find every caller and
say in the report which ones are signature checks -- print one line per element of `rs`
(:534-536, the skolem-mentioning wanteds):

    sigEntail\t<module>\t<binding>\t<file:line:col of the wanted's Located>\t<shape>\t<literal?>\t<wanted pretty>\t<givens pretty>

SHAPE: `concrete-ext` = lhs is one skolem, parts are concrete labels plus exactly one fresh
(flexible) variable; `skolem-in-parts` = a skolem occurs among the parts; `multi-skolem` =
more than one skolem anywhere; `other`. LITERAL: the wanted is alpha-equivalent, up to the
fresh remainder, to some element of `qs`. Print through the same channel the row trace uses
(`-Dermine.rowTrace`), so it lands in the per-file `.out` of `corpus-run.sh`.

## (b) The sweep
`tracker/tools/corpus-run.sh` with `ERMINE_JAVA_OPTS="-Dermine.useInterface=false
-Dermine.sigEntail=warn"` over the whole corpus (stdlib boot is inside every run; core/examples
incl. every subdirectory that must load, Ai/ with Common.e first -- the script knows). Per-file
default; `--batch` only for a second, confirming count. Aggregate with a small script under
`tracker/tools/` (commit-worthy): hits per shape, per module, literal vs not.

## (c) The classification
Every non-literal hit goes into one of: (b) entailed -- write the one-line argument for a
sample of 20 chosen across shapes and modules; (c) NOT entailed -- a real hole in shipped code.
For every (c): file:line, the signature, the wanted, and whether any call in the corpus could
reach the crash (grep the callers; if one can, show the REPL evidence as in
`shouldfail/sig01`'s header). Every (c) item is a finding the user sees; do not merge or
summarise them away.

## (d) The sig03 explanation -- REQUIRED
`core/examples/shouldfail/sig03_let_bound_signature.e` is the let-bound twin of sig01 and is
REFUSED today, at the call (20:12), with "the whole contains it but no part does". sig01 is
accepted. Both go through `typeCheckExplicitBinding`. Trace both (`-Dermine.rowTrace`, and a
debugger-style print of `hm`'s constraint list before/after :655 if needed): which residual
survives in the let path, where it lands (the enclosing binding's inferred type? the ambient
`hm`?), why the top-level path loses it (`restrictTypes` at :540? the module-level
generalisation?), and whether the surviving mechanism is the seed of the fix or a coincidence
that would also refuse honest programs (try control08's `localWith`, which loads today, and a
let-bound honest signature called at TWO different rows). State the answer in one paragraph a
reader can check, with line numbers.

## (e) Gates and report
Tier 0 with the flag OFF: `sbt core/compile core/copyResources`; `sbt 'core/testOnly
*TestLoopTrace'`; `sbt 'core/testOnly *TestSigEntail *TestStage1Pins *TestReplDifferential'`;
`tracker/tools/repl-smoke.sh` (goldens byte-identical); corpus batch verdicts identical to a
run without the flag. Report `tracker/loopmodel/SIG-1-SURVEY.md`: the caller table from (a),
the counts, the (c) list, the sig03 paragraph, the exact commands, and a "what S2 must decide"
list (every shape you saw that the plan's refutation trick does not cover, with an example).
Stop and write up if you exceed ~6 hours of machine+reading time.
