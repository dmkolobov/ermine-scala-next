# LSP-FFI — the language server tolerates missing or mismatched FFI bindings

Stage LSP-FFI, a DETOUR from the LSP roadmap (not Stage 3).  Branch `scala3-migration`, from `6d7c79e`.
Brief: `tracker/loopmodel/briefs/brief-LSP-FFI.md`.  Outcome: **GREEN — all nine failure kinds.**
Reviewed (`tracker/loopmodel/LSP-FFI-REVIEW.md`, FIX-THEN-ADVANCE); the fix round is the last section of this
file and is where the current numbers and the final behaviour live.

## 1. The ask, and the three decisions taken as defaults

The user (2026-09-08): *"make sure we are tolerant to missing FFI bindings of various kinds.  We will be using
the LSP with an older fork of Ermine which does not have Scala 3.  The primary work that has happened there is
changes to the FFI interface (the writer trait)."*

The fork's `Layout/Writer/*.e` and their users declare `foreign data`/`function`/`method`/`value` against
classes and members this JVM does not have, or has with other signatures.  Today ANY foreign resolution failure
kills the module at load, and the editor turns that death into one diagnostic for the whole file — so the
module and every dependent go unchecked.

The orchestrator's three defaults, taken unchanged (no override was asked for):

1. **SEVERITY: warning (LSP severity 2)** at the declaration.  Everything else in the module, and every
   dependent, is checked normally.  Not an error, and never silent.
2. **SCOPE: a session option.**  `SessionEnv._foreignTolerant`, system property `ermine.foreign.tolerant`,
   **default OFF** for `bin/ermine`, the REPL, `corpus-run.sh` and `core/test`, **ON in the LSP `Resident`
   only**.  With the option off every message is byte-identical to today (§3 has the diff: one line, and it is
   the `NoClassDefFoundError` crash being fixed).
3. **CORPUS: synthetic fixtures** under `tracker/lsp-tests/`, shaped like the fork's writer trait
   (`FfiWriter.e` is `foreign data "…MissingWriter" Writer# (f : * -> *) a` plus a factory `function` and an
   instance `method` over it — the shape of `core/src/main/resources/modules/Layout/Writer.e` and of
   `~/research/ermine/ermine-writers/writers/csv/…/Csv.e`).

## 2. Design

### 2.1 Where a foreign declaration can fail

Two phases, and the split is the whole design.

* **READ** (`NewPipeline.assemble` → `foreignClass` → `ForeignClasses.classLookup` → `Class.forName`) resolves
  the class NAMED BY A STRING: `foreign data "C" T`, `foreign function "C" "m" …`, `foreign value "C" "f" …`.
  `Renamer.foreignClasses` looks the same three up a phase earlier and is what actually refuses a batch load.
* **LOAD** (`Session.processForeign*Statement`) does everything else: `getMethod`, the return-assignability
  check, the static/instance check, `getField`, `getConstructor`, and the `Type.foreignLookup` that turns a
  declared Ermine type into the `Class` those lookups are keyed on.

### 2.2 The rule

> A warning is emitted exactly where a class was REQUIRED and could not be produced — never anywhere else.

That single rule settles the awkward cases:

* A `foreign data` of a missing class is a perfectly good **opaque type**.  Declaring it, naming it in a
  signature, passing it through Ermine code and pattern-free plumbing need no class at all, so the declaration
  **does not warn** (kind 9's silent half; fixture `FfiDataOpaque.e`, zero diagnostics).  The `TypeConDecl`
  remembers the class name it wanted and its `foreignLookup` becomes a sentinel class,
  `com.clarifi.reporting.ermine.UnresolvedForeign`.
* **Which operations need the class AT LOAD TIME**, exhaustively: a reflective member lookup (`getMethod`,
  `getField`, `getConstructor`) and the class `computePost` demands of a codomain.  Every one of those goes
  through `Type.foreignLookup`, so recognising the sentinel there is a complete test for a load — that is
  `Session.unresolvedForeignIn`.  Marshalling needs no class either: `marshalForeign` falls through to
  `whnfForeign`, which uses no type information at all.  At RUN time the test is not complete (P-6): a foreign
  pattern match asks `ConDecl.isInstance`, which has no class to ask, and now raises rather than quietly
  answering "no match".  The editor never evaluates, so this concerns only a batch run with the option on.
* A `foreign subtype` performs **no reflection**: it is the identity plus an unchecked claim that one foreign
  type is assignable to another.  When either side has no backing class the claim cannot be checked against
  anything, so the **claim** warns (kind 8) and the identity is installed as before.  Stubbing it would break
  callers at run time for a coercion that was never going to look at a class.

### 2.3 The stub

On a tolerated failure the binding is installed at its **declared type** with
`Session.primOp(v.loc, global(mod, v), stub, ty)` — the same call a successful one uses — where `stub` is
`Bottom(throw Death(…))`.  So the module type-checks, its dependents type-check, navigation and hover work
through the binding, and only EVALUATING it fails, with

```
unresolved foreign binding `render`: class missing: com.clarifi.reporting.writers.NoSuchWriter.render — java.lang.ClassNotFoundException: com.clarifi.reporting.writers.NoSuchWriter
```

which is the same sentence the warning carries.  `foreign data` registers the type with the sentinel class and
no value at all.

### 2.4 The note

Each tolerated failure appends a `session.ForeignNote(module, span, report)` to `SessionEnv.foreignNotes`.
`report` is ONE line, `file:line:col: warning: …`, positioned at the same place as `span`; `Pos.report`'s usual
source line and caret are deliberately left off (the Pos a lowered statement carries has no source text, so
they would render as a blank line and a lone caret, and the editor shows the whole report as the message).

`span` is the CLASS NAME string for (1)(2), the MEMBER string for (3)–(6) and (9), and the declared NAME for
(7)(8) — which have no class or member literal of their own.  `TolerantCheck.Note` grew an
`Option[Span]`, and `lsp/Diagnostics.fromSpan` renders it as a real range, so the squiggle covers the name
rather than sitting as a caret recovered from the report text.  `TolerantCheck.checkWith` takes this module's
notes at `Warning` (severity 2) right after the foreign phases; notes an IMPORT left behind stay on the import's
own file, which is what the `module` field is for.

`copy` deliberately does not carry the notes (a forked load or a fresh editor check starts empty) and `+=` merges
them back, so a `SessionTask.fork`ed parallel load reports its warnings on the module that produced them.

### 2.5 Interface (`.ei`) reads

**The tolerant path applies unchanged.**  `Session.loadModule` runs `processForeign*Statement` for every module
it loads, `preChecked`/`readInterface` or not — the interface only supplies inferred types for the binding
groups and skips inference, never the foreign statements, which come from the module's own SOURCE every time.
So a module whose interface mentions a stubbed binding installs the same stub and records the same warning.
(The LSP does not read interfaces at all — `Resident` runs `useInterface = false` — but batch loads with the
option on get the same behaviour.)

### 2.6 The `NoClassDefFoundError` gap, fixed in BOTH modes

`ForeignClasses.classLookup` caught `Exception`.  A class that is PRESENT but whose own supertype is not throws
`NoClassDefFoundError`, an `Error`, which escaped:

* batch: an uncaught `runtime error: com/fasterxml/jackson/databind/ObjectMapper` with no position and no
  "Unable to load module" line (fixture `FfiClassUnloadable.e`; §3 kind 2);
* editor: `Diagnostics.run` catches `Death` and `NonFatal` — an `Error` is neither — so it unwound to
  `Rpc`'s notification guard (`Rpc.scala:423`) and the file got **no diagnostics at all**: stale squiggles, a
  stack trace in the log, and nothing in the editor.

`classLookup` now catches `Throwable` and rethrows only what must never be swallowed: `VirtualMachineError`
(`OutOfMemoryError`, `StackOverflowError`), `InterruptedException` and `scala.util.control.ControlThrowable`.
Its result type is `Either[Throwable, ForeignClass]`.  With the option OFF this converts the crash into exactly
the positioned `error loading '…'` death a missing class already produced — the only behaviour change in
non-tolerant mode, and the only line of the §3 before/after diff.

### 2.7 Sweep (brief L5)

Every foreign loader, and what was done to it:

| site | kind of failure | treatment |
| --- | --- | --- |
| `parsing/ForeignClasses.classLookup` | `Class.forName` | catches `Throwable` minus the fatal three; `Either[Throwable, …]` |
| `rename/Renamer.foreignClasses` | class lookup for data/function/value | skipped when tolerant (the assemble phase records the failure instead of diagnosing it twice) |
| `rename/NewPipeline.foreignClass` | class lookup in assemble | tolerant: records `ForeignFailure(className, classSpan, cause)` on the `ForeignClass`; strict: unchanged `Death` |
| `session/Session.processForeignDataStatement` | — | tolerant: `TypeConDecl(sentinel, true, Some(className))`, NO warning |
| `session/Session.processForeignCommon` (function, method) | class, unresolved type, `getMethod`, return type, static/instance | five tolerated branches, each with its own kind |
| `session/Session.processForeignValueStatement` | class, `getField` | two tolerated branches |
| `session/Session.processForeignConstructorStatement` | unresolved type, `getConstructor` | two tolerated branches |
| `session/Session.processForeignSubtypeStatement` | unresolved type | warns, installs the identity |
| `Subst.checkForeignData` | — | mirrors the Session decl so the type-check-only path agrees |
| `Subst.checkForeignTerm` | — | types only, no reflection; nothing to do |
| `Session.foreignLift` | invocation, at run time | already `Bottom`s on `NonFatal`; untouched |

Places that catch a `Death` from a foreign failure, all re-read: `lsp/Diagnostics.run` (Death → one diagnostic
for the file — with tolerance on it no longer fires for foreign failures), `TolerantCheck.guard`,
`Console.session` (rolls the session back), `SessionTask.join`/`joins`, `Session.reloadChangedModules`.
`Class.forName` appears nowhere else for foreign resolution (`RowTrace` reflects on `Supply`, `backends/DB`
loads JDBC drivers).

## 3. The nine kinds — probes before and after

Probes: `tracker/lsp-tests/Ffi*.e`, driven through `:load` in one REPL for the batch side and through the
scripted LSP client for the editor side.  **Before** is the pristine tree at `6d7c79e` (`git stash`, rebuild,
probe, restore).  Columns: what the BATCH loader did before / what it does now with the option OFF / what the
EDITOR does now with the option ON.

| # | kind | fixture | before (batch) | option OFF (batch) | option ON (editor) |
| --- | --- | --- | --- | --- | --- |
| 1 | class missing (`ClassNotFoundException`) | `FfiClassMissing.e` | dies `…:6:12: error: error loading 'com.clarifi.reporting.writers.NoSuchWriter'`, module unloaded | **identical** | 1 warning, sev 2, at the class literal `5:11–5:56`, "class missing: …NoSuchWriter.render — java.lang.ClassNotFoundException" |
| 2 | class unloadable (`NoClassDefFoundError`) | `FfiClassUnloadable.e` | **uncaught Error**: `runtime error: com/fasterxml/jackson/databind/ObjectMapper`, no position, no "Unable to load module"; in the editor, NO diagnostic at all | **fixed**: `…:7:12: error: error loading 'org.apache.logging.log4j.core.jackson.Log4jJsonObjectMapper'` + "Unable to load module" | 1 warning at the class literal `6:11–6:73`, "class unloadable: … — java.lang.NoClassDefFoundError: com/fasterxml/jackson/databind/ObjectMapper" |
| 3 | member missing | `FfiMemberMissing.e` | dies `method noSuchMethodAtAll with domain class java.lang.String not found in class java.lang.String` (unpositioned) | **identical** | 1 warning at the member literal `4:30–4:50`, "member missing: java.lang.String.noSuchMethodAtAll(java.lang.String)" |
| 4 | arity mismatch | `FfiArity.e` | dies with the same *diagnosis* as (3) under a slightly different sentence (`method valueOf with domain class java.lang.String,class java.lang.String not found …`); it never says "arity" | **identical** | 1 warning at `4:30–4:40`, "**arity mismatch (declared 2, the class has 1/3)**" — `String.valueOf` exists at 1 and 3 |
| 5 | return type not assignable | `FfiReturn.e` | dies `…:5:3: expected return type java.lang.String does not match foreign return type int` (statement head) | **identical** | 1 warning at the member literal `4:9–4:18`, "return type mismatch: java.lang.String.length — declared java.lang.String, found int" |
| 6 | field missing (`foreign value`) | `FfiFieldMissing.e` | dies `…:5:3: static field NO_SUCH_FIELD not found in class java.lang.Integer` | **identical** | 1 warning at the member literal `4:28–4:44`, "field missing: java.lang.Integer.NO_SUCH_FIELD" |
| 7 | constructor missing | `FfiCtorMissing.e` | dies `…:7:3: constructor not found for java.lang.Stringwith arguments (…)` | **identical** | 1 warning at the declared NAME `6:14–6:16`, "constructor missing: java.lang.String(java.lang.String, java.lang.String)" |
| 8 | `foreign subtype` of a missing class | `FfiSubtype.e` | dies at the `foreign data` one line up: `…:7:8: error: error loading '…NoSuchBase'` | **identical** | 1 warning at the declared NAME `7:10–7:12`, "unverifiable foreign subtype `up`: subtype of an unresolved foreign class: …NoSuchBase — the coercion is installed as the identity it always was" |
| 9a | `foreign data` of a missing class, WITH a site that needs it | `FfiDataNeeded.e` | dies at the `data`: `…:7:8: error: error loading '…NoSuchOpaque'` | **identical** | 1 warning, on the MEMBER `7:9–7:18` and not on the data: "unresolved foreign class: …NoSuchOpaque (needed to resolve `render`)" |
| 9b | `foreign data` of a missing class, opaque, nothing needs it | `FfiDataOpaque.e` | dies the same way — the type could never be declared at all | **identical** | **zero diagnostics**; `keep : Opaque -> Opaque` and `first : Opaque -> Opaque -> Opaque` check normally |

And the three integration fixtures:

| fixture | before | option ON (editor) |
| --- | --- | --- |
| `FfiWriter.e` — the writer-trait look-alike | dies at the first `foreign data` | exactly 2 warnings (the factory's class at `10:11–10:60`, the method's unresolved receiver at `13:9–13:18`); the `data` is silent and `renderWith`/`csv` check clean |
| `FfiUse.e` — a dependent using the stub well-typed | the import fails, so the whole file was one diagnostic | **zero diagnostics**; go-to-definition on `render` jumps to `FfiClassMissing.e:6`, hover says `String -> String` |
| `FfiUseBad.e` — a dependent misusing it | same one diagnostic, about the import | exactly **one** error (sev 1) at the use site `7:7`, "failed to unify type String with type Int" — the declared type is live |

The batch before/after diff, with the option off, over the twelve fixtures a REPL can load is kind (2) alone —
one line out, **four** in (P-9.1: the "Unable to load module" line is new as well):

```
->> runtime error: com/fasterxml/jackson/databind/ObjectMapper
+>> tracker/lsp-tests/FfiClassUnloadable.e:7:12: error: error loading '…Log4jJsonObjectMapper'
+  function "…Log4jJsonObjectMapper" "readValue" readIt : String -> String
+           ^
+Unable to load module from 'tracker/lsp-tests/FfiClassUnloadable.e'
```

The class named there was log4j's, which made the fixture hostage to a dependency bump; the fix round replaced
it with a jar this repo builds itself (F7), and the same hunk is what the reviewer measured independently
against a compiler built from HEAD.

Evaluation of a stub, from `tracker/repl-tests/ffi-tolerant.expected`:

```
tracker/lsp-tests/FfiClassMissing.e:6:12: warning: unresolved foreign binding `render`: class missing: …NoSuchWriter.render — java.lang.ClassNotFoundException: …NoSuchWriter
String -> String
runtime error: unresolved foreign binding `render`: class missing: …NoSuchWriter.render — java.lang.ClassNotFoundException: …NoSuchWriter
```

— the type is there (`:type render` answers `String -> String`), and only `:eval render "x"` fails.

**Through an interface.**  With `-Dermine.useInterface=true -Dermine.foreign.tolerant=true`, `FfiWriter.e`
loaded twice — once writing `FfiWriter.ei`, once reading it — gives byte-identical output both times: both
warnings, `csv : String -> String`, and the stub's error on evaluation.  The written interface is

```
csv : Builtin.String -> Builtin.String
renderWith : forall (f: * -> *) a. FfiWriter.Writer# f a -> Builtin.String -> Builtin.String
```

— binding-group types only, no foreign statement in it, which is why §2.5 holds: the foreign declarations are
re-processed from source on every load.  (Both `.ei` files were deleted afterwards, along with the 129 the
gates left in `core/target`.)

## 4. Diffs

Scala (12 files):

| file | what |
| --- | --- |
| `session/SessionState.scala` | `_foreignTolerant`/`foreignTolerant` (property `ermine.foreign.tolerant`, default false); `case class ForeignNote(module, span, report)`; `var foreignNotes` + `noteForeign`, empty on `copy`, unioned by `+=`, replaced by `:=` |
| `parsing/ForeignClasses.scala` | `Either[Throwable, ForeignClass]`; catches `Throwable` minus `VirtualMachineError`/`InterruptedException`/`ControlThrowable` |
| `syntax/Statement.scala` | `ForeignFailure(className, span, cause)` with `kind`/`causeText`; `ForeignClass` gains `failure: Option[ForeignFailure]`; `ForeignMember` gains `span` |
| `Type.scala` | sentinel `final class UnresolvedForeign`; `TypeConDecl` gains `unresolved: Option[String]` |
| `rename/Renamer.scala` | `rename(m, scope, foreignTolerant = false)`; the foreign-class check is skipped when tolerant |
| `rename/NewPipeline.scala` | passes `s.foreignTolerant` to the renamer; `foreignClass` returns a failure-bearing `ForeignClass` when tolerant and positions its Pos at the real file; member spans reach `ForeignMember` |
| `session/Session.scala` | the tolerance block (`unresolvedForeignIn`, `nameSpan`, `noteForeign`, `foreignStub`, `causeText`, `memberKind`) and the tolerated branches in all five `processForeign*` paths; `processForeignCommon` now takes the `ForeignMember` and the `ForeignClass` instead of a bare name and `Class` |
| `Subst.scala` | `checkForeignData` mirrors the new decl |
| `session/TolerantCheck.scala` | `Warning = 2`; `Note` gains `span: Option[Span]`; drains this module's foreign notes after the foreign phases |
| `session/Console.scala` | `:load` prints the notes the load left behind (never any with the option off) |
| `lsp/Resident.scala` | `_foreignTolerant = Some(true)` — the only place tolerance is on |
| `lsp/Diagnostics.scala` | `fromSpan`: a note with a span renders as a real range |

Fixtures and harnesses:

* `tracker/lsp-tests/Ffi{ClassMissing,ClassUnloadable,MemberMissing,Arity,Return,FieldMissing,CtorMissing,Subtype,DataNeeded,DataOpaque,Writer,Use,UseBad}.e` — 13 new fixtures.
* `tracker/tools/lsp-client.py`: an `ffi(name, expected, keep_open)` helper and **52 new checks** (count,
  severity, exact range and message substring per diagnostic, the two navigation checks through a stub, and one
  that the stdlib's own `Layout/Writer.e` — the healthy version of the very trait this is about — still checks
  clean, so tolerance cannot invent warnings).
* `tracker/tools/repl-smoke.sh` +7 lines: an optional per-case `<name>.opts` file of JVM flags (only the new
  tolerant case has one, so every existing case runs on the command line it always did) and a `sed` that strips
  ` (N.NN seconds)` from a failed load's line — no existing golden contains one.
* `tracker/repl-tests/ffi.{in,expected}` — the default: the load still dies with today's message.
  `tracker/repl-tests/ffi-tolerant.{in,expected,opts}` — with `-Dermine.foreign.tolerant=true`: the warning,
  the live declared type, and the stub's evaluation-time error.

## 5. Gates (Tier 0 + the LSP's own)

*(These are the FIRST-PASS numbers.  The review's fix round re-ran all of them; §F10 has the current ones.)*

| gate | result |
| --- | --- |
| `sbt core/compile core/copyResources` | success (no new warnings) |
| `sbt 'core/testOnly *TestLoopTrace'` | **720/720** — 720 solves, 720 segments, 720 agree, hashdiff 0, eqdiff 0; controls 46/720 and 58/720 |
| `tracker/tools/corpus-run.sh --batch` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** — unchanged (the option is off there) |
| `tracker/tools/lsp-smoke.sh` | **PASS, 150 checks** = the old 98 + **52 new** |
| `tracker/tools/repl-smoke.sh` | **7/7**: aliasing 2, **ffi 3 (new)**, **ffi-tolerant 4 (new)**, pipedeof 12, relations 6, scoping 4, smoke 23 — the five pre-existing goldens byte-unchanged (`git status` shows no modified `.expected`) |
| `sbt core/test` | **Passed: Total 938, Failed 0, Errors 0** (exit 0).  No test added or removed; 938 is 939 minus the `TestConstraints."disjunction sound"` quarantine, which `GATE-POLICY.md` registers only under `-Dermine.test.disjunction=true` |
| LSP stdlib boot | **129 modules**, 12.5 s and 13.4 s on two runs — within noise of the 12.0 s the pre-change REPL took to load the same 129 in this session |
| `.ei` droppings | none (`find . -name '*.ei'` shows only the committed `tracker/g1-baseline/ei/`); the smoke suite's own "no .ei droppings" check passes |
| Tier 1 | not run and not needed: nothing in the solver, the row trace or `Type.scala`'s constraint construction moved (`TypeConDecl` gained a field with a default and a sentinel class was added), and `TestLoopTrace` 720/720 confirms the trace did not move |

## 6. Outcome

**GREEN.**  All nine failure kinds are tolerated, each with one warning at the class or member it is about, the
binding installed at its declared type, and the module and its dependents checked normally.  The
`NoClassDefFoundError` gap is closed in both modes.  With `ermine.foreign.tolerant` off, batch behaviour is
byte-identical to `6d7c79e` apart from that one crash becoming a positioned error.

Judgement calls worth a reviewer's eye, all argued in §2.2:

* a `foreign data` of a missing class does NOT warn — the type is opaque and needs nothing;
* a `foreign subtype` over such a type DOES warn but keeps the identity, because it performs no reflection and
  stubbing it would break callers for a coercion that never looks at a class;
* the "which operations need the class" test is `Type.foreignLookup == classOf[UnresolvedForeign]`, which is
  complete because every reflective lookup and every marshalling boundary is keyed on that one method.

---

## Fix round (LSP-FFI review)

Review `tracker/loopmodel/LSP-FFI-REVIEW.md`, verdict FIX-THEN-ADVANCE.  Every gate reproduced at the numbers
above, all nine kinds held up against the reviewer's own modules and probe classes, and default-off was shown
byte-identical over all 154 corpus outputs against a compiler built from HEAD.  What follows is what changed in
response, finding by finding.

| # | finding | verdict | what was done |
| --- | --- | --- | --- |
| **P-1** | BLOCKER: `getMethod` / `getField` / `getConstructor` still caught `Exception` only, and `memberKind`'s `getMethods` had no `try` at all.  A class that LOADS but whose member signatures name an absent class throws `NoClassDefFoundError` there; it escaped `TolerantCheck.guard` and `Diagnostics.run` and unwound to `Rpc`'s notification guard — **the file was published nothing**, the exact symptom §2.6 claims fixed, and exactly the shape of a stale fork jar. | fixed | §F1 |
| **P-2** | a `foreign data` of a missing class is *wholly* silent, so a module whose only foreign statement is one is indistinguishable from a healthy one | adopted | §F2 |
| **P-3** | warning ranges are one character wider than the literal for kinds 1–6/9 (exact for 7/8) | fixed | §F3 |
| **P-4** | a tolerant `:load` that dies after recording warnings prints none of them | fixed | §F4 |
| **P-5** | failed class lookups are never cached | done, and measured | §F5 |
| **P-6** | the "which operations need the class" claim is complete at load time only; `ConDecl.isInstance` on the sentinel silently mismatches | fixed + documented | §F6 |
| **P-7** | the kind-2 fixture depends on log4j shipping a class with a missing Jackson superclass | replaced | §F7 |
| **P-8** | "unverifiable foreign subtype" implies a check that never happens | reworded | §F8 |
| **P-9** | three prose inaccuracies in this report | fixed | §F9 |
| judgement (b) | `foreign subtype` warns and keeps the identity | reviewer agrees; kept | — |

*(gates: §F10)*

### F1 — the linkage hole at the MEMBER lookups (P-1)

`Class.getMethod` / `getField` / `getConstructor` resolve the signature classes of everything they search, so
`probejar.PresentMember.ok(String)` — an ordinary static method — cannot be looked up if a *sibling* method
returns a class this JVM lacks.  That throws `NoClassDefFoundError`, an `Error`: neither a `Death` nor
`NonFatal`, so it went straight past both guards.

Three changes:

1. **One catch set, named.**  `parsing.Recoverable` (new, in `ForeignClasses.scala`) is `NonFatal` plus the
   `LinkageError` family and minus nothing else: it rethrows `VirtualMachineError`, `InterruptedException` and
   `scala.util.control.ControlThrowable`, and catches everything else.  `ThreadDeath` is deliberately absent —
   unthrowable since JDK 20, and naming it is a deprecation warning.  `classLookup` and all four reflective
   sites now go through `Recoverable.attempt`.
2. **New kinds, at the member.**  Tolerant mode reports `member unloadable` / `field unloadable` /
   `constructor unloadable` with the JVM cause, at the member literal (or the declared name for a
   constructor), and installs the usual stub.  `memberKind` no longer calls `getMethods` unguarded: when the
   cause is an `Error`, or the re-scan itself throws, the kind is `member unloadable` rather than a crash.
3. **Default mode gets a POSITION.**  An `Error` here used to be an uncaught crash, so there is no message to
   keep byte-identical; it now dies with `<file>:<line>:<col>: member ok of class probejar.PresentMember could
   not be resolved: java.lang.NoClassDefFoundError: probejar/Missing`, positioned on the member.  The
   `Exception` path — every pre-existing kind — is untouched, word for word (verified: `repl-tests/ffi`).
4. **A backstop.**  `TolerantCheck.guard` and `Diagnostics.run` now catch `Recoverable` instead of `NonFatal`,
   so "the editor never goes dark" no longer rests on having enumerated every reflective call.

Before / after, all three sites (`FfiMemberUnloadable.e`, `FfiFieldUnloadable.e`, `FfiCtorUnloadable.e`):

| mode | before | after |
| --- | --- | --- |
| LSP (tolerant) | `rpc: notification textDocument/didOpen crashed: java.lang.NoClassDefFoundError: probejar/Missing`; **no diagnostics published** | one warning, severity 2, at the member/name span, naming the cause |
| batch (default) | `runtime error: probejar/Missing` — unpositioned, no "Unable to load module" | `…:10:37: member ok of class probejar.PresentMember could not be resolved: java.lang.NoClassDefFoundError: probejar/Missing` + "Unable to load module" |

### F2 — a `foreign data` of a missing class is not silent (P-2)

It is still not a *warning* — the opaque type is genuinely fine — but it now leaves an **Information note (LSP
severity 3)** on the class literal:

```
note: opaque foreign type `Opaque`: com.clarifi.reporting.writers.NoSuchOpaque is not on this JVM
(class missing) — the type is usable and this module checks normally; a foreign function, method,
value or constructor over it cannot be resolved, and will warn where it is declared
```

Severity 3 renders as a hint rather than a squiggle, so the noise objection does not apply, and the file that
*writes the class name down* is no longer the one file that says nothing about it.  `ForeignNote` grew a
`severity` field and `TolerantCheck` passes it through instead of forcing `Warning`.

### F3 — exact literal spans (P-3)

`spanned` ends a token's span where the next token begins, so every string-literal span ran one character into
the following space.  `NewPipeline.literalSpan` trims a recorded span back to the literal — the value plus its
two quotes, clamped to the recorded end so an escaped literal can only get shorter, never longer — and both
`ForeignFailure.span` and `ForeignMember.span` are built through it.  All nine class/member ranges lost their
trailing character (e.g. `FfiClassMissing` `[11,56)` → `[11,55)`); the name-derived spans for kinds 7 and 8 were
already exact, so the two families now agree.  Every client range assertion was updated to the exact value.

### F4 — a failed tolerant `:load` keeps its warnings (P-4)

`Console.session` rolls back to `sessionEnv.copy`, which deliberately carries no notes, so warnings recorded
before an unrelated death were dropped and "no warnings" was indistinguishable from "none were found".  The
rollback now carries the notes across.  Covered by `repl-tests/ffi-tolerant` through `FfiRollback.e`, which
declares a missing foreign class *and* a type error: the load dies, and the warning is printed anyway.

### F5 — the negative class-lookup cache, and what it is worth (P-5)

`ForeignClasses.failureMap` memoizes failures beside the successes.  A class absent from the application loader
cannot appear later — nothing here installs another loader — so a `Left` is as permanent as a `Right`.

**Measured, both ways, on a 40-binding file whose classes are all absent** (`p5.py`, keystroke-to-diagnostics
over ten `didChange` cycles, same JVM flags, cache disabled by a one-line revert and rebuilt for the control):

| | cold `didOpen` | `didChange` median (incl. the 300 ms debounce) | min–max |
| --- | --- | --- | --- |
| without the cache | 0.068 s | **0.327 s** | 0.321–0.335 |
| with the cache | 0.070 s | **0.324 s** | 0.318–0.331 |

So: **3 ms of a 324 ms round trip — noise.**  A direct micro-measurement agrees: 40 failed `Class.forName`
calls cost 33.7 ms on the first pass and 2.7–4.9 ms warm on this 19-entry classpath, so there was never much to
save.  The cache is kept because it makes the cost of a re-check *deterministic* rather than proportional to
how many bindings are broken, not because it was measurably slow; on a classpath with many directory entries,
or a file with hundreds of stale bindings, the same 0.07 ms per lookup would start to show.

### F6 — the completeness claim, and `isInstance` (P-6)

The claim in §2.2 is now stated as what it is: `Type.foreignLookup` is a complete test for **load-time**
operations — the reflective lookups and the class `computePost` demands of a codomain — and marshalling needs
no class at all, since `marshalForeign` falls through to `whnfForeign`, which uses no type information.  It is
*not* complete at run time: a foreign pattern match goes through `ConDecl.isInstance`, which the sentinel
answered with a flat `false`, silently taking the wrong branch.  `TypeConDecl.isInstance` now raises
"foreign type has no class on this JVM: C — a pattern match against it cannot be decided" instead.  Run time
only: the editor never evaluates, and batch only reaches it with the option on.

### F7 — a self-contained kind-2 fixture (P-7)

`tracker/lsp-tests/jsrc/probejar/` holds five three-line Java classes; `tracker/tools/build-probejar.sh`
compiles them into `target/lsp-ffi-probejar.jar` and **deletes `Missing.class` before jarring**, so the
remaining four are present-but-unlinkable in precisely the way a stale jar of the fork is.  `lsp-smoke.sh` and
`repl-smoke.sh` append the jar to the classpath (the JDK they already require is the only new dependency; the
jar rebuilds only when a source is newer).  `FfiClassUnloadable.e` now names `probejar.PresentSuper` instead of
a log4j class, so no library upgrade can silence it, and the same jar gives F1 its three regression fixtures.

### F8 — wording (P-8)

"unverifiable foreign subtype" became "foreign subtype `up` **over** an unresolved foreign class … the coercion
is installed as the identity it always was, and is not checked against the class (it never is)".  Nothing here
ever verifies the claim, resolved classes or not, so the old wording implied a check that does not exist.

### F9 — the report's own inaccuracies (P-9)

1. §3's before/after block is one line out and **four** in, not three — the `Unable to load module from '…'`
   line is new too.  Corrected below.
2. §3 kind 4 said the pre-change message was "the SAME … sentence" as kind 3.  It is the same *diagnosis*
   under a different sentence (it lists two domain classes).  Corrected: it never says "arity", which is the
   point.
3. §2.2's completeness claim — see F6.

### F10 — gates, re-run after the fix round

| gate | number |
| --- | --- |
| `sbt core/compile core/copyResources` | success, no new warnings |
| `sbt 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**, hashdiff 0, eqdiff 0, skipped 0, nonpart 0, rejected 36; controls 46/720 and 58/720 |
| `tracker/tools/corpus-run.sh --batch` | **85 LOADED / 69 REJECTED / 0 UNKNOWN over 154** — and, normalising only the progress-bar timings, `diff -rq` against the pre-fix-round corpus run is **0 of 154 differ**, so the fix round moved no batch output at all |
| `tracker/tools/lsp-smoke.sh` | **PASS, 181 checks** = the pre-stage 98 + **83 new** (52 before the fix round, +31: four probejar fixtures, the `foreign data` Information notes, and `FfiRollback`) |
| `tracker/tools/repl-smoke.sh` | **7/7** — aliasing 2, **ffi 5**, **ffi-tolerant 9**, pipedeof 12, relations 6, scoping 4, smoke 23; the five pre-existing goldens are still unmodified in `git status` |
| `sbt core/test` | **Passed: Total 938, Failed 0, Errors 0**, exit 0 — identical to the pre-fix-round run; no test added or removed |
| LSP stdlib boot | **129 modules in 12.8 s** |
| `.ei` droppings | none left |

The three tool diffs stay purely additive — `lsp-client.py` 156 insertions / 0 deletions, `lsp-smoke.sh` 5/0,
`repl-smoke.sh` 12/0 — so every pre-existing check is still the same assertion.

### F11 — what the fix round changed, file by file

| file | change |
| --- | --- |
| `parsing/ForeignClasses.scala` | `Recoverable` (the catch set, named once) and `failureMap` (the negative cache) |
| `session/Session.scala` | `Recoverable.attempt` at the three lookups; `memberKind` guarded and given the cause; the three `*-unloadable` kinds; positioned Deaths for the Error path in default mode; `atSpan`; the `foreign data` Information note; `noteForeign` takes a severity; the subtype wording |
| `session/SessionState.scala` | `ForeignNote.severity` |
| `session/TolerantCheck.scala` | `guard` catches `Recoverable`; notes carry their own severity |
| `session/Console.scala` | the rollback keeps the foreign notes |
| `lsp/Diagnostics.scala` | `run` catches `Recoverable` |
| `rename/NewPipeline.scala` | `literalSpan`, applied to the class and member literals |
| `Type.scala` | `TypeConDecl.isInstance` raises on the sentinel |
| `tracker/lsp-tests/jsrc/probejar/*.java`, `tracker/tools/build-probejar.sh` | the self-contained probe jar |
| `tracker/lsp-tests/Ffi{ClassUnloadable,MemberUnloadable,FieldUnloadable,CtorUnloadable,Rollback}.e` | new / rewritten fixtures |
| `tracker/tools/{lsp,repl}-smoke.sh` | build the jar and put it on the classpath |
| `tracker/tools/lsp-client.py`, `tracker/repl-tests/ffi*.{in,expected}` | the checks and goldens for all of the above |
