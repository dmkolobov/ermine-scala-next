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


Contribute
----------

[Contributions][] and [bug reports][] are welcome!  You can submit
both through Bitbucket.

[contributions]: https://bitbucket.org/ermine-language/ermine-scala/pull-requests
[bug reports]: https://bitbucket.org/ermine-language/ermine-scala/issues?status=new&status=open

Both the `scala-2.9.2` and `default` branches are under active
development.  `default` is required to always be a descendant of
`scala-2.9.2`; that is, `scala-2.9.2` must be fully merged to
`default`.  New features are developed on one branch or the other, but
there are somewhat stronger stability requirements for `scala-2.9.2`.
Please talk to us if you are unsure what branch your fix or feature
should be developed on.

Also, this project is developed in sync with [Ermine Writers][].  Any
changes to this one might require coordinated changes to that one.

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

Thank you to all contributors to Ermine Writers, most of whom are
listed in `CONTRIBUTORS.md` in the distribution.

The Ermine Scala project was started and continues to be developed at
McGraw Hill Financial.


License
-------

Basically, Ermine Scala is licensed under the 2-clause BSD license, a
free and open source license; see `COPYING`.  Full details of the
licensing of this distribution are in `LICENSE.md`.
