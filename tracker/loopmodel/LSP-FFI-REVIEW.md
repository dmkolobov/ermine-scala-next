# LSP-FFI review — tolerance to missing/mismatched FFI bindings in the language server

Reviewer: independent.  Brief `tracker/loopmodel/briefs/brief-LSP-FFI-review.md`.
Implementer report `tracker/LSP-FFI-TOLERANCE.md` (outcome GREEN).  Tree: HEAD `cb1565e`
(+ `8b514c1`, docs only) plus the UNCOMMITTED deliverables.  Scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-LSP-FFI/`.

## Verdict: **FIX-THEN-ADVANCE**

The design is right and the nine kinds all work — I rebuilt every one of them from scratch,
against my own modules and my own probe classes, and every one behaves as claimed, with the
rest of the module and its dependents still checked.  Default-off is byte-identical.  The
`.ei` claim holds cold and warm.  Every gate re-runs green.

What stops it being ADVANCE is **P-1**: the `NoClassDefFoundError` hole that §2.6 closes at
`Class.forName` is still wide open one layer down, at `getMethod` / `getField` /
`getConstructor`.  A class that LOADS but whose member signatures name a class this JVM
lacks — the *precise* shape of the user's Scala-2 fork sharing a jar with a changed writer
trait — still crashes the check.  In the editor the file gets **no diagnostics at all** and
the notification handler unwinds to `Rpc`, which is verbatim the symptom the report says it
fixed.  I reproduced it three ways with a three-line Java probe.  It is a ~10-line fix in
the same style as the one already made.

## 0. Gates, re-run once (my numbers)

| gate | my number | evidence |
| --- | --- | --- |
| `sbt core/compile core/copyResources` | success, exit 0, no new warnings | `compile.log` |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**, hashdiff 0, eqdiff 0, skip 0, nonpart 0, rejected 36, 10450 ms; controls **46/720** (id base +1) and **58/720** (nongen) | `looptrace.log` |
| `tracker/tools/corpus-run.sh --batch` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154**, 41.8 s | `corpus/`, `corpus-run.log` |
| `tracker/tools/lsp-smoke.sh` | **PASS, 150 checks**, 16.5 s | — |
| `tracker/tools/repl-smoke.sh` | **7/7** — aliasing 2, **ffi 3**, **ffi-tolerant 4**, pipedeof 12, relations 6, scoping 4, smoke 23 | — |
| `sbt core/test` | **Passed: Total 938, Failed 0, Errors 0**, exit 0, 1352 s | `coretest.log` |
| LSP boot | **129 modules in 13.3 s** (implementer measured 12.5/13.4) | `/tmp/lsp-smoke.log` |
| `.ei` droppings | 0 outside the 143 tracked ones; I deleted the 129 my own interface runs left in `core/target` | — |

The 150/98/52 arithmetic checks out exactly: the new block contributes `1` (stdlib
`Layout/Writer.e` clean) + `4` for each of the nine one-diagnostic fixtures + `1`
(`FfiDataOpaque`) + `7` (`FfiWriter`, two diagnostics) + `1` (`FfiUse`) + `1` + `1`
(definition, hover) + `4` (`FfiUseBad`) = **52**, so the pre-existing count was 98.
`git diff --numstat` on `tracker/tools/lsp-client.py` is **113 insertions, 0 deletions** and
on `repl-smoke.sh` **7 / 0** — purely additive, so all 98 pre-existing checks, positions
included, are byte-identical.  No `.expected` golden is modified (`git status`).

Tier 1 not run and not needed: nothing in the solver or the row trace moved, and
`TestLoopTrace` 720/720 with both controls at their usual values confirms it.

## 1. The nine kinds, re-probed from scratch

I did not use the implementer's fixtures.  I wrote fourteen of my own modules under
`scratch/probes/`, each with **a genuine type error elsewhere in the same module**
(`bad : Int` / `bad = "not an int"`), and compiled **my own probe classes** for the linkage
cases (`scratch/jsrc/*.java` → `scratch/jcls/`, with `probejar/Missing.class` deleted after
compilation), then drove the server with my own client (`scratch/client.py`) — not
`lsp-client.py`'s scenario.  Raw server output: `scratch/lsp-probe*.log`.

Every row below: **exactly two** diagnostics — the FFI warning AND the unrelated type error.
Ranges are 0-based LSP, as published.

| # | kind | my probe | FFI diagnostic | the unrelated type error also reported? |
| --- | --- | --- | --- | --- |
| 1 | class missing | `P1.e`, `com.nope.NoSuchWriter` | sev **2**, `3:11–3:35` = the CLASS literal, "unresolved foreign binding `render`: class missing: com.nope.NoSuchWriter.render — java.lang.ClassNotFoundException: com.nope.NoSuchWriter" | yes, sev 1 at `6:0` |
| 2 | class unloadable | `P2.e`, my `probejar.PresentSuper` (extends a deleted class) | sev **2**, `3:11–3:35` = CLASS literal, "class unloadable: probejar.PresentSuper.shout — java.lang.NoClassDefFoundError: probejar/Missing" | yes |
| 3 | member missing | `P3.e` | sev **2**, `3:30–3:49` = MEMBER literal, "member missing: java.lang.String.noSuchMemberHere(java.lang.String) — java.lang.NoSuchMethodException" | yes |
| 4 | arity mismatch | `P4.e`, `String.valueOf` at 2 | sev **2**, `3:30–3:40` = MEMBER, "arity mismatch (declared 2, the class has 1/3)" | yes |
| 5 | return not assignable | `P5.e`, `String.length` as `String` | sev **2**, `3:9–3:18` = MEMBER, "return type mismatch: java.lang.String.length — declared java.lang.String, found int" | yes |
| 6 | field missing | `P6.e` | sev **2**, `3:28–3:41` = MEMBER, "field missing: java.lang.Integer.NOPE_FIELD — java.lang.NoSuchFieldException" | yes |
| 7 | constructor missing | `P7.e` | sev **2**, `3:14–3:16` = the declared NAME `mk`, "constructor missing: java.lang.String(java.lang.String, java.lang.String)" | yes |
| 8 | `foreign subtype` of a missing class | `P8.e` | sev **2**, `4:10–4:12` = declared NAME `up`, "unverifiable foreign subtype `up`: subtype of an unresolved foreign class: com.nope.NoSuchBase — the coercion is installed as the identity it always was" | yes |
| 9a | `foreign data` missing, a site NEEDS it | `P9a.e` | sev **2**, `4:9–4:18` = MEMBER, "unresolved foreign class: com.nope.NoSuchOpaque (needed to resolve `render`)" | yes |
| 9b | `foreign data` missing, opaque | `P9b.e` | **no FFI diagnostic at all** | yes — the type error is the ONLY diagnostic |
| 9c | as 9b, module otherwise healthy | `P9c.e` | **zero diagnostics** | n/a |

So the severities, the ranges, the blame sites and the message texts are all as the report
claims, and **tolerance does not swallow the rest of the module**: in nine of nine cases the
deliberate type error four lines below the `foreign` block is reported alongside.

**Dependents.**  `P1ok.e` (the same missing class, no type error) → exactly one sev-2
warning.  `PDepOk2.e` imports it and uses `render "hello"` → **zero diagnostics**.
`PDepBad2.e` imports it and writes `render 42` → **exactly one** sev-1 error at `5:7`, "failed
to unify type String with type Int".  The declared type is live through the stub, as claimed.

One scope note, not a defect: tolerance covers FFI failures only.  When the imported module
has an ordinary *type* error, loading it as an import still dies and the dependent collapses
to one diagnostic at `0:0` naming the import's file (my first `PDepOk.e`/`PDepBad.e` pair,
which carried a type error, did exactly that).  That is pre-existing and out of this stage's
scope, but it is worth knowing that "the editor keeps checking dependents" holds for broken
FFI, not for broken imports generally.

**Repeat checks do not accumulate.**  didOpen + three didChange cycles on the same
two-warning module: 2, 2, 2, 2 (`scratch/client2.py`).  `SessionEnv.copy` dropping the notes
and `TolerantCheck` filtering on `module` is the right pair.

## 2. The judgement calls — decided

### (a) `foreign data` of a missing class never warns — **I disagree, mildly.  Emit an Information (severity 3) note.**

The *rule* is right: an opaque type needs no class, so a **warning** on the `data` would be
wrong and would bury the user in yellow on exactly the files they need to read.  But total
silence is a step past that, and it collides with the orchestrator's own decision 1
("Not an error, and never silent").  Confirmed with `P9c.e`: a module whose only foreign
statement is `foreign data "com.nope.NoSuchOpaque" Opaque`, plus healthy Ermine code over
it, publishes **zero** diagnostics — indistinguishable from a module whose FFI is intact.

For the user's stated scenario that is the wrong end of the trade.  The whole point of
pointing this server at the fork is to find out *which* classes the fork's writer trait no
longer has, and the `foreign data` line is where the class name is written.  A fork module
that declares the writer type and re-exports it — plausible for a trait split across files —
reports nothing at all.  `TypeConDecl.unresolved` already carries the name, `TolerantCheck`
already has `Information = 3`, and `Note` already carries a span, so this is a three-line
change: note at the class literal, severity 3, "opaque: com.nope.NoSuchOpaque is not on this
JVM; the type is usable, any reflective use of it will warn where it is used".  Severity 3
renders as a hint, not a squiggle, so the noise argument does not apply.  Recommended, not
blocking (**P-2**).

### (b) `foreign subtype` warns but keeps the identity — **agree, keep it.**

I checked the code path: `processForeignSubtypeStatement` installs `Fun(x => x)` and performs
no reflection, so there is nothing a stub could protect and a stub would turn a coercion that
never touches a class into a run-time bomb.  Warning-and-identity is the right call, and
confirmed working on `P8.e`.

One wording nit (**P-8**): the message says "**un**verifiable", which implies the claim is
normally verified.  It is not — `processForeignSubtypeStatement` never calls
`isAssignableFrom`, even when both classes resolve.  The warning is really "this module's FFI
is stale, and here is one more place it shows", which is still useful.  Suggest
"foreign subtype `up` over an unresolved foreign class …" or similar.

### (c) The stub at run time, and `IO.catch`

Measured in the REPL with `-Dermine.foreign.tolerant=true` (`scratch/repl-stub.in`):

```
>> :type render                → String -> String
>> :eval render "x"            → runtime error: unresolved foreign binding `render`: class
                                 missing: com.nope.NoSuchWriter.render —
                                 java.lang.ClassNotFoundException: com.nope.NoSuchWriter
                                 Use ":stack" to see a stack trace
```

The type is live; only evaluation fails, with the sentence the warning carries.  Confirmed.

**`IO.catch` does not catch it** — and neither does `IO.Unsafe.unsafeFFI`.  I declared the
same missing binding at `String -> IO String` and at `String -> FFI String` and wrapped them:
`catch (renderIO "x") (e -> return "CAUGHT-IO")` and
`case unsafeFFI (renderFFI "x") of Left e -> "CAUGHT-FFI"; Right a -> a` both evaluate to
`<error: unresolved foreign binding …>`, i.e. the Bottom propagates through the handler.
The reason is structural: the stub is a `Bottom` at the WHOLE declared type, so `runIO`'s
`case IO f` and `eval`'s `e.extract[FFI[_]]` force it outside the `try` that would route to
`ke`.

**This is not a regression.**  I ran the control: a genuine foreign that throws —
`foreign function "java.lang.Integer" "parseInt" parseIntF : String -> FFI Int` on
`"notanint"`, forced through `unsafeFFI` — also escapes as `<error: For input string:
"notanint">`, because `perhapsForeign` builds `Prim(new FFI(…))` lazily and the throw happens
when the result is forced, again outside `eval`'s `try`.  So the stub is exactly as
catchable as any other foreign failure on this path: not at all.  Nothing to change here;
worth one sentence in the report so nobody expects `IO.catch` to shield fork code.

### (d) the `Throwable` catch list, and `NoClassDefFoundError` in both modes

The list at `ForeignClasses.classLookup` — rethrow `VirtualMachineError`,
`InterruptedException`, `scala.util.control.ControlThrowable`, catch everything else — is
**right**.  It is the standard "fatal" set, it is what `NonFatal` would do plus the
`LinkageError` family this needs, and the three rethrows are the three that must never be
swallowed.  I would not add `ThreadDeath` (deprecated and unthrowable since JDK 20) and I
would not narrow it to `LinkageError`: `ExceptionInInitializerError` and
`NoSuchMethodError` from a static initialiser are the same failure to the user.

`NoClassDefFoundError` at the CLASS name is now a positioned error in both modes.  Verified
in batch on the pristine harness path:

```
tolerance OFF: tracker/lsp-tests/FfiClassUnloadable.e:7:12: error: error loading
               'org.apache.logging.log4j.core.jackson.Log4jJsonObjectMapper'
               … + "Unable to load module from …"
tolerance ON : …:7:12: warning: unresolved foreign binding `readIt`: class unloadable: … —
               java.lang.NoClassDefFoundError: com/fasterxml/jackson/databind/ObjectMapper
```

— and independently on my own self-contained class (`probejar.PresentSuper`, kind 2 above).
So the §2.6 claim holds, **for the class name only**.  See P-1.

## 3. Default OFF

* **repl-smoke goldens**: the five pre-existing `.expected` files are unmodified in
  `git status`, and the suite is 7/7 with tolerance off for all of them.  The one
  normalisation the harness gained — `sed 's/ ([0-9]*\.[0-9]*  seconds)//'` — cannot mask a
  change to an existing golden: `grep -rn seconds tracker/repl-tests/*.expected` is empty, so
  no pre-existing golden contains such a substring.  The per-case `.opts` mechanism is
  opt-in by file existence and only `ffi-tolerant.opts` exists.
* **corpus**: **85 / 69 / 0 over 154**, and see below for the byte comparison.
* **`TestLoopTrace`**: 720/720.

**Byte-for-byte against a pre-change compiler.**  I did not settle for the F3 baseline.  I
extracted HEAD to scratch (`git archive HEAD | tar -x -C scratch/pre` — the corpus sources and
`corpus-run.sh` there are `diff`-identical to the working tree, so this is the same corpus on
an older compiler), built it (`sbt core/compile core/copyResources`, its own classpath, and
`strings` on the built `Session$.class` confirms it does NOT contain the new code), and ran
`corpus-run.sh --batch` on it.

* **pre-change: 85 / 69 / 0 over 154.  post-change, tolerance off: 85 / 69 / 0 over 154.**
* Normalising only the progress-bar timings and the two repo-root path prefixes,
  `diff -rq` over all 154 per-file outputs is **EMPTY — 0 of 154 differ**, messages included.

For completeness I also diffed my run against the F3 review's saved corpus
(`review-F3/corpus/`): exactly one file differs,
`Time_shouldfail_date01_datediff_free_row.e.out`, position `50:7` -> `55:7` — and that module's
source was rewritten in `775a20f` *after* the F3 reviewer captured its baseline, so it is a
corpus-source change, not a compiler one.  The pre-change build above settles it independently.

**The fixture-level before/after, non-tolerant.**  Loading all thirteen `tracker/lsp-tests/Ffi*.e`
in one REPL, pre-change compiler vs this one with the option off, the whole diff is one hunk:

```
- >> runtime error: com/fasterxml/jackson/databind/ObjectMapper
+ >> …/FfiClassUnloadable.e:7:12: error: error loading 'org.apache.logging.log4j.core.jackson.Log4jJsonObjectMapper'
+   function "org.apache.logging.log4j.core.jackson.Log4jJsonObjectMapper" "readValue" readIt : String -> String
+            ^
+ Unable to load module from '…/FfiClassUnloadable.e' (TIME seconds)
```

— one line out, **four** in (the report's block says three; it omits the "Unable to load
module" line its own table mentions).  Every other kind's pre-change message is unchanged and
matches the report's "before (batch)" column, position for position.

## 4. The `.ei` claim

Structurally sound: `Session.loadModule` runs `processForeignDataStatement` and the five
`processForeign*Statement`s at lines 840–850, **before** `preChecked` decides interface vs
full inference; the interface only replaces the binding-group inference.  So the foreign
statements come from source on every load, interface or not.

Verified end to end on a two-module fixture (`scratch/ei/EiA.e`, the writer-trait shape,
plus `EiB.e` importing it), with `-Dermine.useInterface=true -Dermine.foreign.tolerant=true`,
run cold (no `.ei`) and then warm (`EiA.ei`/`EiB.ei` present).  The two outputs are
**identical apart from the load timing**:

```
EiA.e:5:12: warning: unresolved foreign binding `csvWriter`: class missing:
            com.nope.MissingCsvWriter.csvWriter — java.lang.ClassNotFoundException: …
EiA.e:6:10: warning: unresolved foreign binding `render#`: unresolved foreign class:
            com.nope.MissingWriter (needed to resolve `render`)
>> :type greet   → String
>> :eval greet   → <error: unresolved foreign binding `render#`: …>
```

and `EiA.ei` holds binding-group types only (`csv`, `renderWith`) — no foreign statement.
`diff` of the two transcripts is one line, `(0.09 seconds)` vs `(0.04 seconds)`.  Both `.ei`
deleted afterwards.

## 5. Coverage sweep

**Every foreign loader, and what it does with an Error.**

| site | reflective call | catches | Error-safe? |
| --- | --- | --- | --- |
| `parsing/ForeignClasses.classLookup` | `Class.forName` | `Throwable` − {VirtualMachineError, InterruptedException, ControlThrowable} | **yes** (this stage) |
| `rename/Renamer.foreignClasses` | via `classLookup` | — | yes; skipped entirely when tolerant |
| `rename/NewPipeline.foreignClass` | via `classLookup` | — | yes |
| `session/Session.processForeignCommon` | `clazz.getMethod` (Session.scala:1282) | `case e: Exception` | **NO — P-1** |
| `session/Session.memberKind` | `clazz.getMethods` | **no try at all** | **NO — P-1** |
| `session/Session.processForeignValueStatement` | `clazz.getField` (:1361) | `case e: Exception` | **NO — P-1** |
| `session/Session.processForeignConstructorStatement` | `codomain.getConstructor` (:1414) | `case e: Exception` | **NO — P-1** |
| `session/Session.processForeignSubtypeStatement` | none | — | n/a |
| `session/Session.processForeignDataStatement` | none | — | n/a |
| `Subst.checkForeignData` / `checkForeignTerm` | none (types only) | — | n/a |
| `Session.foreignLift` / `perhapsForeign` / `marshalForeign` | run time | `NonFatal` → Bottom | pre-existing |
| `backends/DB.scala:107,130` | `Class.forName(driver)` | JDBC, not a foreign declaration | out of scope |
| `RowTrace.scala:308` | `Class.forName("scalaparsers.Supply$")` | not FFI | out of scope |

**Every catch of a Death from a foreign failure.**  `lsp/Diagnostics.run` (Death + NonFatal —
Errors escape, P-1); `session/TolerantCheck.guard` (Death + NonFatal — same); `Console.session`
(Death → env rollback, P-4); `Console.handling` (Throwable — this is what turns the stub into
`runtime error: …`); `SessionTask.fork`/`join`/`joins` (Death → Left → rethrown);
`Session.scala:669` (Death probe in the reload path); `Session.scala:1618` (Death → `Err.report`);
`Session.scala:1067`/`:1116` rethrow Death out of a foreign invocation deliberately.

**`TolerantCheck.Note`'s new `Option[Span]`.**  The field is added last with a default of
`None`, and every pre-existing construction site (`Note(report, sev)`,
`Note(report, sev, Some(spelling))`) is unchanged, so those notes still take the
`fromReport` path.  The client diff is 113 insertions / 0 deletions, so all 98 pre-existing
checks — positions included — are literally the same assertions, and they pass.

**The kind-2 fixture's fragility — a self-contained fixture IS feasible, and I built one.**
`FfiClassUnloadable.e` depends on `log4j-core` shipping
`org.apache.logging.log4j.core.jackson.Log4jJsonObjectMapper` whose Jackson superclass this
build lacks.  That is a coincidence of the dependency tree, and a log4j or Jackson bump
silences it.  A self-contained replacement is three lines of Java and about ten of build
glue: compile `probejar/Missing.java` and `probejar/PresentSuper.java extends Missing`, then
delete `Missing.class` and jar the rest.  I did exactly that in scratch and it reproduces
kind 2 with a stable, self-describing message ("java.lang.NoClassDefFoundError:
probejar/Missing").  **Recommended**: ship the two `.java` files under `tracker/lsp-tests/jsrc/`
and have `lsp-smoke.sh`/`repl-smoke.sh` build the jar into `target/` with `javac` (the JDK is
already a hard requirement of both harnesses) and append it to the classpath.  The same jar
gives the P-1 regression test for free (`PresentMember`, `PresentField`, `PresentCtor`).

## 6. Findings

Ranked.  CONFIRMED = I ran it.

### P-1 (CONFIRMED, blocking) — the `NoClassDefFoundError` hole is only half closed: at the MEMBER lookups it still kills the check, and in the editor the file gets NO diagnostics

`ForeignClasses.classLookup` now catches `Throwable`.  The three reflective lookups one layer
down still catch `Exception` only, and a fourth has no `try` at all:

* `Session.scala:1282` `clazz.getMethod(methName, classDomain:_*)` — `catch { case e: Exception => Left(e) }`
* `Session.scala:1361` `clazz.getField(valName)` — same
* `Session.scala:1414` `codomain.getConstructor(classDomain:_*)` — same
* `Session.memberKind` `clazz.getMethods` — **no try**, and it runs *inside* the tolerant branch

`Class.getMethod` / `getField` / `getConstructor` resolve the signature classes of the
declared members, so a class that LOADS fine but whose members mention an absent class throws
`NoClassDefFoundError` — an `Error`, so it is neither a `Death` nor `NonFatal`.  It escapes
`TolerantCheck.guard`, escapes `Diagnostics.run`, and unwinds to `Rpc`'s notification guard.

Reproduced with a three-line Java probe (`probejar.Missing` deleted after compilation;
`PresentMember.bad()` returns it, `PresentField.GONE` is typed by it, `PresentCtor` takes it):

```
LSP, tolerance ON:
  rpc: notification textDocument/didOpen crashed: java.lang.NoClassDefFoundError: probejar/Missing
    at java.lang.Class.getMethod(Class.java:2395)
    at …Session$.processForeignCommon(Session.scala:1282)
    at …TolerantCheck$.guard$1(TolerantCheck.scala:137)          <- did not catch it
    at …Diagnostics$.run(Diagnostics.scala:110)                  <- did not catch it
  -> the file is published NOTHING.  Stale squiggles, a stack trace in the log.
  Same for getField (PField.e, Class.getField:2284) and getConstructor (PCtor.e, Class.getConstructor:2444).

batch, tolerance OFF *and* ON:
  >> runtime error: probejar/Missing        <- unpositioned, no "Unable to load module"
```

That last line is character-for-character the symptom §2.6 describes as the bug it fixed
(`runtime error: com/fasterxml/jackson/databind/ObjectMapper`), just triggered one level in.
It is *not* a regression — the `catch Exception` there predates this stage — but the stage's
stated deliverable is that this class of failure is a positioned diagnostic in both modes,
and for members it still is not.  It matters here specifically: the user is pointing the
server at a fork whose writer trait changed, and a stale jar of that trait on the classpath —
classes present, member signatures naming types this JVM lacks — lands exactly on this path.

**Fix** (small, same shape as the one already made):

1. wrap the three lookups (and `memberKind`'s `getMethods`) in the same `Throwable` minus
   {`VirtualMachineError`, `InterruptedException`, `ControlThrowable`} catch that
   `classLookup` now uses — `Left(e)` feeds the existing tolerated branches unchanged, so
   the editor gets "class unloadable: C.m — java.lang.NoClassDefFoundError: …" at the member,
   and batch gets the positioned Death it gets for kind 3;
2. widen `TolerantCheck.guard` and `Diagnostics.run` to catch the same set, so *any* future
   `Error` in a check degrades to a diagnostic instead of a blank file.  Without (2) the
   "the editor never goes dark" property rests on having enumerated every reflective call.
3. add the three probe classes as the P-1 regression test — see P-7, they come with the
   self-contained kind-2 fixture for free.

### P-2 (CONFIRMED, recommend) — a `foreign data` of a missing class is *wholly* silent

Judgement call (a), argued in §2 above.  `P9c.e` — the module declares an opaque type over a
class this JVM does not have, and publishes **zero** diagnostics.  Recommend an
Information-level (severity 3) note at the class literal.  The orchestrator's decision 1 says
"never silent"; the machinery (`TolerantCheck.Information`, `Note.span`,
`TypeConDecl.unresolved`) is already in place.

### P-3 (CONFIRMED, cosmetic) — the warning range is one character wider than the literal for kinds 1–6/9, and exact for 7/8

`spanned` records `loc` *after* the token, which in this grammar is the start of the next
token, so a string-literal span includes the trailing space.  Measured: the class literal in
`FfiClassMissing.e:6` occupies 0-based `[11,55)` and the published range is `[11,56)`; every
one of the nine is `+1`.  `Session.nameSpan` (kinds 7 and 8) builds `col … col+len`, which is
exact.  So the squiggle behaves differently for the two families.  This is the codebase's
pre-existing `spanned` convention (`fromDiag` converts identically), so it is not a defect
introduced here — but the report's table states the ranges as if they covered the literal,
and the two families are inconsistent with each other.  Worth one sentence in the report, or
a `-1` in `fromSpan` if the ranges are ever tightened (which would move all the existing
diagnostics too, so: leave it and document it).

### P-4 (CONFIRMED, minor) — a tolerant `:load` that dies *after* recording warnings prints none of them

`Console.session` rolls back with `sessionEnv = envp`, where `envp = sessionEnv.copy` and
`copy` deliberately drops `foreignNotes`.  So on the failure path `loadProject`'s
`foreignNotes.drop(notesBefore)` reads an empty list and the warnings recorded before the
death are lost.  Only affects the REPL, which is not the shipped mode; noting it so the
behaviour is not mistaken for "there were none".

### P-5 (CONFIRMED, minor) — failed class lookups are never cached, so every re-check redoes them

`ForeignClasses.classMap` caches successes only; a `Left` is not memoized.  Every editor
re-check of a fork module therefore re-runs `Class.forName` once per missing class and
re-throws a `ClassNotFoundException` (which walks the whole classpath first).  At my scale it
is invisible (`diagnostics: didOpen … in 0.0s`), but a fork file with dozens of stale
bindings, re-checked on every 300 ms debounce, is a different proposition.  Caching the
failure — or at least the *fact* of failure — is a two-line change and would also make the
diagnostics deterministic in cost.  Rank low; measure before acting.

### P-6 (CONFIRMED, minor) — the "which operations need the class" test is not quite complete

The report says every operation that needs the class goes through `Type.foreignLookup`, so
recognising the sentinel there is a complete test.  Sweeping the consumers:
`computePost`, the two `classDomain` maps, `unresolvedForeignIn` — and **`ConDecl.isInstance`,
used by `Pattern.scala:139` and `:159`** for foreign pattern matching.  On the sentinel
`isInstance` simply returns `false`, so a foreign pattern match against an unresolved
`foreign data` silently fails to match rather than reporting anything.  Run-time only, and
the LSP never evaluates, so the editor story is unaffected — but the completeness claim
should say "every load-time operation".  (Also: `marshalForeign` falls through to
`whnfForeign`, which uses no type information at all, so it needs no class either — that
*strengthens* the case for the silent `foreign data`, and the report can say so directly
instead of resting on `foreignLookup`.)

### P-7 (CONFIRMED, recommend) — replace the kind-2 fixture with a self-contained one; I built it

`FfiClassUnloadable.e` depends on log4j-core shipping a class whose Jackson superclass this
build lacks.  Three lines of Java replace it, deterministically, and give P-1's regression
test at the same time.  Details and the recommended wiring in §5.

### P-8 (CONFIRMED, prose) — "unverifiable foreign subtype" implies a check that never happens

`processForeignSubtypeStatement` never verifies assignability, resolved classes or not.  See
§2(b).

### P-9 (CONFIRMED, prose) — three small inaccuracies in `tracker/LSP-FFI-TOLERANCE.md`

1. §3's before/after code block is "one line out, **four** in", not three: the
   `Unable to load module from '…'` line is new too (the table row says so; the block omits it).
   My measured diff, pre-change compiler vs this one with tolerance off, over all thirteen
   fixtures, is exactly that one hunk and nothing else.
2. §3 kind 4 says the pre-change message is "the SAME … sentence as (3) — indistinguishable".
   It is the same *diagnosis* but not the same sentence — it lists two domain classes
   (`method valueOf with domain class java.lang.String,class java.lang.String not found …`).
   The point stands (it never says "arity"); the word "indistinguishable" does not.
3. §2.2's completeness claim — see P-6.

## 7. What I checked that came out clean

* Skipping `Renamer.foreignClasses` when tolerant loses nothing else: that function only does
  class lookups and appends `Diag`s — no occurrences, no binders — so navigation and the
  other rename diagnostics are untouched.  `renameOrDie`, which still renames non-tolerantly,
  has no callers.
* `SessionEnv`: `copy` drops the notes, `+=` merges them, `:=` replaces them;
  `SessionTask.fork` copies and `join`/`joins` merge, so a forked parallel load reports on the
  module that produced it.  Empirically, four consecutive checks of the same two-warning
  module publish 2, 2, 2, 2.
* `primOp` takes the stub strictly and `Bottom` takes its body by name, so exactly one note
  per statement per check and the `Death` is not thrown at load.
* `perhapsForeign` takes the field value by name, so `foreign value` stays lazy on the
  success path (unchanged).
* `foreignTolerant` is read in exactly three places (`NewPipeline.assemble`,
  `Renamer.rename`'s guard, and the `Session.processForeign*` branches) and set to `true` in
  exactly one (`lsp/Resident.boot`).  Nothing else in the tree turns it on.
* `SForeignPrivate` recurses through the same lowering, so `private foreign` blocks are
  covered.
* The stdlib's own `Layout/Writer.e` — the healthy version of the trait this is all about —
  still checks clean under tolerance (`lsp-smoke` asserts it; it passed).

## 8. Bottom line

ADVANCE once P-1 is fixed and re-gated (Tier 0 + `lsp-smoke`), and I would take P-2 and P-7
in the same pass since they are small and both improve exactly the scenario this stage
exists for.  P-3/P-4/P-5/P-6/P-8/P-9 are notes for the report and the tracker, not work.
