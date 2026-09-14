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
* A collection of JavaFX utilities.

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
| **`scala3-migration`** (the main line) | Scala 3.3, sbt 1.10, JDK 17+ | everything: the language server and VS Code extension, the resolution-free parser and renamer, the tolerant read path, the loop-model tests, `tracker/` |
| **`backport-2.11`** (this branch, legacy) | Scala 2.11.5, sbt 0.13.5, JDK 8 | the original build, forked from the old `default` branch, plus a minimal back-port of the fixes: scoping, the row solver, signature entailment |

New work lands on `scala3-migration` and is cherry-picked here when it
has to reach Scala 2.11 users.  `BACKPORT.md` says exactly what was
ported, what was not, and why.  The language server and the editor
extension are **not** on this branch; `editor/` here is the old JavaFX
editor.


Building and running
--------------------

The Bintray repositories the original build resolved from are gone, so
the branch carries its own environment:

```
source backport/env-2.11.sh    # JDK 8, the sbt 0.13.5 launcher, an hg shim
sbt211 core/compile
sbt211 core/test
```

Three libraries have to be built and `publishLocal`ed once from their
sources (ermine-parser 0.2.3, scala-machines, f0 1.1.3).  `BACKPORT.md`
gives the tags, artifact names, the repository configuration that still
resolves, and the verification record for each family of fixes.

The REPL is `sbt211 core/run`; module bindings are type-checked when
`ermine.typeCheck` is set.  Line endings on this branch are CRLF and stay
CRLF, so diff against `default` with plain `git diff`.


Contribute
----------

Contributions and bug reports are welcome; open an issue or a pull
request.  Fixes go to `scala3-migration` first unless they are specific
to the 2.11 build.

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
