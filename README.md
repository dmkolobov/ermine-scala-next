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
* An Ermine standard library,
* A relational database model and SQL generator, with API and extra
  tools in Ermine,
* An API for creating visual reports from relational data, with charts
  and graphs, for both authoring in Ermine and output engines in
  Scala,
* A collection of JavaFX utilities,
* An experimental type-aware text editor for Ermine source code.

The output engines that display and export reports are part of a
separate distribution, [ermine-writers][].  Unlike this distribution,
that project has more complex licensing considerations, so be sure to
check out its `LICENSE.md` before doing anything important with it.

[ermine-writers]: https://bitbucket.org/ermine-language/ermine-writers


Building and running
--------------------

This branch (`scala3-migration`) builds on **Scala 3** with **sbt 1.x** and a
**JDK 17+**.

```
sbt compile          # all modules
bin/ermine           # start the REPL
```

`bin/ermine` caches the classpath in `target/ermine-classpath`; delete that
file after changing dependencies. `sbt core/run` starts the same REPL.

```
>> :type reverse
forall a. List a -> List a
>> 1 + 2
res0 : Int = 3
```

The session only type-checks module bindings when `ermine.typeCheck` is set;
both `bin/ermine` and `sbt core/run` set it for you. Without it every module
binding loads as `forall a. a`.

To run the REPL tests:

```
sbt -batch 'export core/fullClasspath' | tail -1 > tracker/repl-classpath.txt
tracker/tools/repl-smoke.sh
```

`tracker/` documents the migration from Scala 2.11: what changed and why, the
three libraries that had to be vendored because they are no longer published
(`scalaparsers`, `machines`, `f0`) plus the scalaz APIs removed after 7.0, and
two pre-existing bugs found while testing.


Contribute
----------

[Contributions][] and [bug reports][] are welcome!  You can submit
both through Bitbucket.  We provide [build instructions][] on the
wiki.

[contributions]: https://bitbucket.org/ermine-language/ermine-scala/pull-requests
[bug reports]: https://bitbucket.org/ermine-language/ermine-scala/issues?status=new&status=open
[build instructions]: https://bitbucket.org/ermine-language/ermine-scala/wiki/Building

We have **two** main development branches, not just one: `scala-2.9.2`
and `default`.  [Check the wiki][Branches] for details, and advice on
which to base your contribution on.

Also, this project is developed in sync with [Ermine Writers][].  Any
changes to this one might require coordinated changes to that one.

[Branches]: https://bitbucket.org/ermine-language/ermine-scala/wiki/Branches
[Ermine Writers]: https://bitbucket.org/ermine-language/ermine-writers


Talk to us
----------

Ermine is a big project, and the developers have a wealth of knowledge
about how various parts of it work.  Join
[#ermine on irc.freenode.net](http://webchat.freenode.net/?channels=%23ermine)
to chat with the developers.  Leave us a bug report if you have a more
formal or detailed question.


Thanks
------

Thank you to all contributors to Ermine Scala, most of whom are listed
in `CONTRIBUTORS.md` in the distribution.  Further details of their
contributions are listed [on the wiki][Contributors].

[Contributors]: https://bitbucket.org/ermine-language/ermine-scala/wiki/Contributors

The Ermine Scala project was started and continues to be developed at
McGraw Hill Financial.


License
-------

Basically, Ermine Scala is licensed under the 2-clause BSD license, a
free and open source license; see `COPYING`.  Full details of the
licensing of this distribution are in `LICENSE.md`.
