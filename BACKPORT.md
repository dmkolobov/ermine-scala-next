Back-port of the scala3-migration fixes to the Scala 2.11 branch
===================================================================

Branch `backport-2.11`, forked from `default` at 8de8010.  Scope, as agreed:
minimal.  The Scala 3 branch's language server, resolution-free parser
(`surface/`, `rename/`), tolerant read path and REPL pipeline cutover are
NOT here; only the two families of fixes are.

1. Scoping fix (parser)
-----------------------
Cherry-pick of scala3-migration f9cf42a: `let`/`where` bindings and pattern
variables may shadow imports and enclosing binders, and a block restores the
outer scope on exit (LocalBlocks in parsing/TermNameParsers.scala, the
checkShadows alias-capture refusal).  Properties: TestScopes.scala.

2. Row solver (type inference)
------------------------------
The end state of scala3-migration's Constraints.scala, Subst.scala, Type.scala,
Vars.scala, Kind.scala and RowTrace.scala (as of 257f032), with the Scala-3-only
hunks reverted (Traversable instead of ForeachIterable, no Tag.unwrap).  What it
contains, each adopted as the shipped default on the Scala 3 branch after its
own gate:
  - per-label refutation instead of the CSE minting branch (-Dermine.genRules=cut,
    labelCheck, labelCheckEarly, resGuard);
  - the concretised variable keeps its multi-part definitions (the NameLoss fix);
  - keyed split guard (splitKey) and concrete-row reuse for both mints (splitRow,
    resRow): the proved-terminating queue;
  - rowSound (no false acceptance), dequeuePolicy=smallcanon, solveBudget=20000;
  - written-partition normalisation (topNormalise) and residual hygiene
    (mkSimplified duplicate/tautology removal, tautoDelete on publish);
  - blame row-constraint errors on the call site (Term.scala: Var(vp at v.loc)).
Every rule is still switchable with the same -Dermine.* property and the same
default as on scala3-migration; ermine.emptyRow and ermine.disjunction stay off.

Interface cache: a published .ei now starts with a solver-configuration key
(Session.interfaceHeader); a file with another key, or none, is rechecked and
rewritten (scala3-migration ed53fe7).  TypeParsers.scala carries the F4 fix so
row labels with a lower-case last segment read back (78adf6d).  So the first
load after switching to this branch rechecks every module once.

Not ported on purpose: the stdlib .e library fixes (Date, NonEmpty, Relation),
the loop-model replay tests, TestInterfaceConcreteRow (needs tools/G1Compare).

Line endings: the branch's files are CRLF and stay CRLF; diff against
`default` with plain `git diff` -- there is no line-ending churn.

Verification (2026-09-09, sbt 0.13.5 / Scala 2.11.5 / JDK 8)
-------------------------------------------------------------
  - sbt core/test: 713 properties, 0 failures (default: 685 pass, 1 discarded).
  - TestScopes (scalacheckBinding/runMain com.clarifi.reporting.TestScopes):
    all 28 scoping properties pass.
  - REPL boot: 129 modules, type checking on, interfaces off, ~23 s on both
    `default` and this branch (three interleaved runs each; the solver work
    changes the pathological cases, not the stdlib boot).
  - REPL smoke inputs from scala3-migration's tracker/repl-tests: scoping now
    passes (it fails on `default`); relations, tauto and smoke match except
    for two `\x -> ...` lambda lines, which the Scala 2 grammar never accepted
    (they fail identically on `default`); aliasing is REFUSED here
    ("would capture references to Function.id, in scope under multiple names")
    -- that is the documented C#-style refusal of the cherry-picked fix; the
    Scala 3 branch accepts it only through its later renamer.
  - Interface key by hand: a load writes `-- ermine-interface 2|cut+...+tauto`
    as the first line of the .ei; flipping -Dermine.tautoDelete=false rewrites
    it with the flag gone, flipping back rewrites it again.
  - TestInterfaceKey was NOT ported: its "warm load under ermine.loadInSeries"
    step deadlocks the 2.11 module loader (the Scala 3 branch's loader was
    reworked in 939c2aa; this branch has no loadInSeries).

Building this branch today
--------------------------
The bintray repositories the build resolved from are gone.  What works:
  - JDK 8 (e.g. `cs java-home --jvm adoptium:8`); the toolchain's JDK 21 is
    wrong for Scala 2.11.5.
  - sbt-launch 0.13.5 from
    https://repo.scala-sbt.org/scalasbt/ivy-releases/org.scala-sbt/sbt-launch/0.13.5/sbt-launch.jar
    run with -Dsbt.repository.config=<file> -Dsbt.override.build.repos=true,
    where the file lists `local`, `central-https: https://repo1.maven.org/maven2/`
    and the https typesafe/scala-sbt ivy patterns (sbt 0.13.5's built-in
    http://repo.typesafe.com entry hangs forever).
  - An `hg` shim on PATH answering `hg id` / `hg id -b` / `hg id -t` from git:
    computeRevision runs on every `update` (project/Settings.scala:21).
  - publishLocal of the three unpublished libraries from their sources
    (https://github.com/ermine-language/ermine-parser tag 0.2.3 as
    scala-parsers:scala-parsers:0.2.3; scala-machines at 2bba88e as
    machines:machines:1.1 on scalaz 7.0.7; f0 tag v1.1.3 as com.clarifi:f0:1.1.2),
    each with the bintray plugin lines removed and scalaVersion 2.11.5.
  - kind-projector 0.6.3 instead of 0.5.2 (the only build-file change on
    this branch; 0.5.2 was bintray-only).
