# Ermine language server

`bin/ermine-lsp` speaks LSP over stdio. On `initialize`/`initialized` it boots a
resident Ermine session (Lib.preamble plus the Prelude/Layout closure, type
checking on, interface files off; ~13s, reported through `window/logMessage`),
then serves:

- **Diagnostics** on `didOpen`, `didSave`, and ~300ms after the last
  `didChange` — no save required. Checking runs against the open BUFFER, for
  this file and its workspace siblings alike, so a cross-file check sees
  unsaved edits. Every check uses a fresh copy of the resident session, so a
  broken file poisons nothing.

  A file gets **all** of its diagnostics, not just the first: every
  unparseable statement, every shadowing refusal, every unknown operator, and
  every independent type error. Syntax errors are blamed where the parser
  actually gave up, including inside `where`/`let` blocks. The healthy
  definitions of a broken file are still type checked; whatever depends on
  something broken is reported "unchecked: depends on a broken definition"
  rather than inferred against unconstrained metavariables.

  An import that will not load — a module that does not exist, or one whose
  file has a syntax error of its own — is reported ON ITS OWN `import`
  statement, squiggling the module name, with the loader's own message (which
  names the failing file and the position inside it) after an `import X
  failed:` prefix. Each failing import gets its own diagnostic, so one broken
  import cannot hide another, and the file is checked anyway: its other
  diagnostics, its navigation and its hovers all still work. Fixing a broken
  sibling in ITS buffer clears the importing file's diagnostic on the next
  check, with no save anywhere.

  While an import has failed, the editor withholds the notes that are merely
  consequences of the names that never arrived: "undefined term" and
  "unchecked: depends on a broken definition" are suppressed for that check —
  the import failure is the error to act on, and a file's worth of undefined
  names on top of it is noise. (The same rule already applies while a
  statement is too broken to parse.) It is deliberately blunt: a genuine typo
  goes quiet until the import is fixed. Two consequences of a missing import
  are NOT withheld today — an operator it would have supplied still draws
  "unknown operator" (plus the two lowering diagnostics that follow it) and a
  type it would have supplied still draws "undefined type".

- **Go-to-definition** for every name that has a source position: equations,
  signatures and local binders; `field` and `table` declarations; data
  constructors; foreign declarations; type names (`data`, `type`, `class`,
  `foreign data`) and their aliases; the operator named in a fixity
  declaration; and the module named by an `import`, which opens its file.
  Same file, workspace siblings, and the stdlib alike. It works on the
  healthy statements of a broken file, and follows a sibling's unsaved edits.

  Names installed by Scala rather than declared in source — `Just`, `True`,
  `Int`, `Maybe` and the rest of `Builtin` — answer null, because there is no
  source to open.

- **Hover** with the inferred or declared type for top-level, imported and
  declared names (`Nav.twice : forall a. a -> a`, `GroupBy.value : Field
  (|value|) Double`), including at the declaration itself.

  A **type name** hovers with its KIND — `Builtin.Bool : *`,
  `Locals.Boxed : * -> *` — imported and own alike, at a mention and at the
  declaration head. Builtin type atoms (`->`, `*`, rho) have no constructor
  and answer null.

  A **local binder** hovers with the type the last check gave it, at its
  def-site and at every use, with no `forall` and with still-free metas
  rendered as type variables (`idy : a -> a`). Since 6.2 this covers `let`
  and `where` bindings, every ARGUMENT of an equation (top-level or in a
  `where`), and any binder carrying an explicit signature, which shows AS
  DECLARED. An equation's arguments are read off the binding's own type by
  its arity, so their type variables are the SAME ones the binding's hover
  shows: `konst : forall a b. a -> b -> a` gives `k : a` and `j : b`.

  It does NOT cover an unsigned pattern binder with no equation head over
  it — a lambda's argument, a `case` alternative's binder, a `do` binder, or
  a variable nested inside a constructor pattern. Their types exist only
  inside `Subst.inferPatternType`, which mints a fresh variable per pattern
  into a copy of the body and writes nothing back, so the editor answers
  null rather than guessing (`tracker/loopmodel/LSP3-6.2-LOCALS.md`).

  One caveat worth knowing: a local's type variables are named
  independently of the ENCLOSING binding's, so the same letter in two
  hovers need not be the same variable — a `where` helper may hover
  `h : a -> a` inside a binding whose own hover calls that variable `b`.
  Within one binding (its own type and its arguments) the letters do
  agree.

  In fast mode no local answers at all — nothing computes them.

- **Find references** and **document highlight**, from the same index. What
  the set is depends on the name:

  A **local** — a `let` or `where` binding, an equation argument, a `case`,
  `do` or lambda binder, a type variable — is a renamer binder id, so the
  set is every mention of it in THAT FILE, plus the def-site itself when
  `context.includeDeclaration` asks for it. Highlight marks the def-site
  Write and the uses Read.

  A **global** — this module's own top level, a `data`/`type`/`class` head,
  a constructor, a `field`, a `table`, a foreign declaration, or a name
  imported from anywhere — is a canonical name, chased through any
  re-export chain to the module that DEFINES it (`Prelude` re-exports
  `Bool`, and a use of `not` reached through `Prelude` is the same name as
  `Bool.e`'s own), so the set is every mention in every OPEN BUFFER: uses, the defining module's signature and equation
  heads, its declaration head, its fixity line, and the
  `import M using (n)` entries that name it. An ALIAS-imported mention
  counts: the key is the canonical origin, not the spelling. The def-site is
  in the set even when its file is not open. Document highlight is always
  per-document.

  COVERAGE: the workspace is the OPEN BUFFERS. A module that imports the
  name but is not open is not searched, and the server cannot know whether
  one exists — so every global references or rename request sends one
  `window/showMessage` warning saying how many open files were searched.

- **Rename** (with `prepareRename`) writes ONE `WorkspaceEdit` over exactly
  that set. It never produces a partial edit: it refuses instead, with a
  message, when the name is defined in a file that is not open (a stdlib
  name); when the new name is not a valid Ermine identifier, or is one of
  the other case (a constructor or type name stays upper-case, a term
  lower-case); when either name is an operator (an operator's spelling
  carries its fixity); when the new name is already bound where the old one
  is used, is already a top level of the module, or already resolves through
  the file's imports; when a mention is written under another spelling (an
  alias import or a qualified use, which a textual rename cannot follow);
  when the source writes the name in a form that is not its spelling — a
  `` ``literal`` `` name, whose backticks and escapes a textual rename
  cannot rebuild, or a name behind a TAB, where the server's columns (the
  parser's, expanded to eight-column stops) and the editor's disagree;
  when another open buffer holds that spelling under a different
  definition; when a mention of the name is ambiguous; and when ANY open
  document has been edited since its last check ("check pending; retry
  after diagnostics update"), which is the honest answer while a debounced
  check is owed — a buffer that has just gained a mention cannot be edited
  from an index that predates it.

  References and highlight are correct on all of those, `` ``literal`` ``
  names included: their extent is the whole backticked token.

Logging goes to the file named by `ERMINE_LSP_LOG` (or `-Dermine.lsp.log`);
stdout is reserved for the protocol.

## Fast mode

`initializationOptions: { fastMode: true }`, or a `workspace/didChangeConfiguration`
carrying `{ settings: { ermine: { fastMode: true } } }`, skips type checking.
On a 1757-line module a check splits roughly 0.80s read + 0.45s typecheck, so
this is about half the latency.

Kept: every syntax, shadowing, unknown-operator and lowering diagnostic;
go-to-definition, including to this module's own fields and constructors,
whose positions come from the surface tree rather than from the check; hover
on imported names, and on imported TYPE names' kinds. Lost: all type errors,
the "unchecked" notes, import-list export requirements, hover on the module's
own definitions, and hover on every local binder.

## Latency

Measured on `core/src/main/resources/modules/Layout/Report.e`, 1757 lines:

| | |
|---|---|
| session boot | ~13s, once |
| keystroke to diagnostics | ~1.57s (0.80s read + 0.45s typecheck + 0.30s debounce) |
| binding groups re-inferred | 40 of 154; the rest are reused |

Small modules are far below that. Dispatch is single-threaded by design
(SessionEnv is not thread-safe), so requests are served one at a time —
navigation requests arriving during boot answer null immediately rather than
queueing behind it.

## VS Code

An extension lives in `editor/vscode` — syntax highlighting plus a client for
this server. See its README for install and settings. VS Code has no built-in
generic LSP client, so an extension is the only route.

## Emacs (eglot)

```elisp
(define-derived-mode ermine-mode prog-mode "Ermine"
  "Bare major mode for Ermine `.e' files.")
(add-to-list 'auto-mode-alist '("\\.e\\'" . ermine-mode))
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(ermine-mode . ("/path/to/ermine-scala/bin/ermine-lsp"))))
;; M-x eglot in an .e buffer. M-. for definition, K / eldoc for hover.
```

For fast mode, add `:initializationOptions (:fastMode t)` to the server entry.

## Regression harness

`tracker/tools/lsp-smoke.sh` runs the scripted client
(`tracker/tools/lsp-client.py`) against the fixtures in `tracker/lsp-tests/` —
306 checks over everything above, including didChange without save, the
sibling-buffer path, local and kind hovers, references/highlight/rename with
their refusals, and fast mode. Run it with `core/test` and
`repl-smoke.sh` before committing server changes
(`tracker/LSP-ROADMAP.md`, Baselines).
