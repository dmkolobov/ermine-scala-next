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
  (|value|) Double`), including at the declaration itself. Local binders and
  type names answer null for now — the former gated on
  `tracker/TICKET-perf-type-inference.md`, not on the protocol.

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
on imported names. Lost: all type errors, the "unchecked" notes, import-list
export requirements, and hover on the module's own definitions.

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
82 checks over everything above, including didChange without save, the
sibling-buffer path, and fast mode. Run it with `core/test` and
`repl-smoke.sh` before committing server changes
(`tracker/LSP-ROADMAP.md`, Baselines).
