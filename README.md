Ermine Scala
============

                                         _,-/"---,
                 ;"""""""""";          _`;; ""  «@`---v
                ; :::::  ::  "'      _` ;;  "    _.../
               ;"     ;;  ;;;  '",-`::    ;;,'""""
              ;"          ;;;;.  ;;  ;;;  ::`    ____
             ,/ / ;;  ;;;______;;;  ;;; ::,`    / __/_____ _  ( )__  __
             /;; _;;   ;;;       ;       ;     / _//`__/  ' \/ /`_ \/ -)
             | :/ / ,;'           ;_ "")/     /___/_/ /_/_/_/_/_//_/\__/
             ; ; / /"""=            \;;\\""=
          ;"""';\::""""""=            \\"""=
          \/"""

Ermine is a programming language, derived from Haskell, executing on
the JVM.  It was originally designed for creating interesting reports
from relational data.  It's based on the idea that advanced type
systems can be used to guide users towards the features of software
they're interested in for many different contexts.  Its key
enhancement over Haskell is its relational rowtype system.

This distribution includes several components:

* A type checker and interpreter for Ermine, built in Scala,
* An Ermine standard library (`core/src/main/resources/modules`),
* A relational database model and SQL generator, with API and extra
  tools in Ermine,
* An API for creating visual reports from relational data, with charts
  and graphs, for both authoring in Ermine and output engines in
  Scala,
* A language server (`bin/ermine-lsp`) and a VS Code extension
  (`editor/vscode`) — diagnostics as you type, navigation, hover types,
  rename, completion and quick fixes,
* A collection of JavaFX utilities (`utilJavafx`, legacy).

The output engines that display and export reports are part of a
separate distribution, ermine-writers.  Unlike this distribution, that
project has more complex licensing considerations, so be sure to check
out its `LICENSE.md` before doing anything important with it.


Two branches
------------

There are **two** maintained branches.  They share the language, the
standard library and the type-system fixes, and differ in toolchain and
in what tooling ships with them.

| Branch | Toolchain | What it has |
|---|---|---|
| **`scala3-migration`** (this branch, the main line) | Scala 3.3, sbt 1.10, JDK 17+ | everything: the language server and VS Code extension, the resolution-free parser and renamer, the tolerant read path, the loop-model tests, `tracker/` |
| **`backport-2.11`** (legacy) | Scala 2.11.5, sbt 0.13.5, JDK 8 | the original build, forked from the old `default` branch, plus a minimal back-port of the fixes: scoping, the row solver, signature entailment |

New work lands on `scala3-migration`.  `backport-2.11` exists for code
that still has to build on Scala 2.11; its `BACKPORT.md` says exactly
what was ported, what was not, and how to build it today (the original
repositories it resolved from are gone).  The language server and the
editor extension are **not** on the 2.11 branch.

The other branches in the repository are the pre-migration history
(`default`, `scala-2.9.2`, the `closed/*` and feature branches) and are
kept for reference only.


Building and running (scala3-migration)
---------------------------------------

Requirements: a JDK 17 or newer and sbt 1.x on `PATH`.

```
sbt compile          # all modules
bin/ermine           # start the REPL
```

`bin/ermine` caches the classpath in `target/ermine-classpath`; delete
that file after changing dependencies.  `sbt core/run` starts the same
REPL.

```
>> :type reverse
forall a. List a -> List a
>> 1 + 2
res0 : Int = 3
```

The session only type-checks module bindings when `ermine.typeCheck` is
set; both `bin/ermine` and `sbt core/run` set it for you.  Without it
every module binding loads as `forall a. a`.  All 129 standard-library
modules load with type checking on.

Three libraries the original build depended on are no longer published,
so they are vendored here: `parsers/` (ermine-parser), `machines/`
(scala-machines) and `f0/`.  `scalaz-compat/` carries the two scalaz
APIs removed after 7.0.  `tracker/` documents that migration and the
type-system work that followed it.


Building and running (backport-2.11)
------------------------------------

```
git checkout backport-2.11
source backport/env-2.11.sh    # JDK 8, the sbt 0.13.5 launcher, an hg shim
sbt211 core/compile
sbt211 core/test
```

The three unpublished libraries have to be built and `publishLocal`ed
once from their sources; `BACKPORT.md` on that branch gives the tags,
artifact names and the repository configuration that still resolves.


The editor
----------

`bin/ermine-lsp` is a language server over stdio.  `editor/vscode` is a
VS Code extension that starts it and adds the syntax grammar; its
`README.md` covers building, installing and what each feature does and
does not do, and `docs/lsp.md` is the full reference for the server.


Tests
-----

```
sbt core/test                      # the property suites
tracker/tools/repl-smoke.sh        # REPL goldens
tracker/tools/lsp-smoke.sh         # language-server checks
```

`repl-smoke.sh` and `lsp-smoke.sh` need the classpath exported once:

```
sbt -batch 'export core/fullClasspath' | tail -1 > tracker/repl-classpath.txt
```

`tracker/GATE-POLICY.md` says which of these a change has to pass, and
`tracker/LSP-ROADMAP.md` records the current baselines (suite counts
grow with the work, so the numbers live there rather than here).


Layout
------

| | |
|---|---|
| `core/` | the language, REPL, relational engine, SQL, report writers and the language server |
| `core/examples/` | example modules and reports; `core/examples/README.md` |
| `docs/` | `lsp.md` (the language server), design notes and the old tutorial |
| `editor/vscode/` | the VS Code extension |
| `bin/` | `ermine` (REPL) and `ermine-lsp` |
| `parsers/`, `machines/`, `f0/`, `scalaz-compat/` | vendored dependencies |
| `tracker/` | the migration log, design notes, tickets, the Lean development for the row solver, and the corpus and smoke tooling under `tracker/tools/` |
| `legacy-build/` | the sbt 0.13 build files, parked |


Contribute
----------

Contributions and bug reports are welcome; open an issue or a pull
request against `scala3-migration`.  A fix that has to reach Scala 2.11
users is cherry-picked to `backport-2.11` afterwards, as `BACKPORT.md`
describes.

This project was developed in sync with Ermine Writers.  Changes to the
report API here might require coordinated changes there.


Thanks
------

Thank you to all contributors to Ermine Scala, most of whom are listed
in `CONTRIBUTORS.md` in the distribution.

The Ermine Scala project was started at McGraw Hill Financial.


License
-------

Basically, Ermine Scala is licensed under the 2-clause BSD license, a
free and open source license; see `COPYING`.  Full details of the
licensing of this distribution are in `LICENSE.md`.
