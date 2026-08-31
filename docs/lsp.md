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

- **Go-to-definition** for term names: same file, workspace siblings, and the
  stdlib. It works on the healthy statements of a broken file, and follows a
  sibling's unsaved edits.

- **Hover** with the inferred type for top-level and imported names
  (`Nav.twice : forall a. a -> a`). Local binders answer null for now — gated
  on `tracker/TICKET-perf-type-inference.md`, not on the protocol.

Logging goes to the file named by `ERMINE_LSP_LOG` (or `-Dermine.lsp.log`);
stdout is reserved for the protocol.

## Fast mode

`initializationOptions: { fastMode: true }`, or a `workspace/didChangeConfiguration`
carrying `{ settings: { ermine: { fastMode: true } } }`, skips type checking.
On a 1757-line module a check splits roughly 0.80s read + 0.45s typecheck, so
this is about half the latency.

Kept: every syntax, shadowing, unknown-operator and lowering diagnostic;
go-to-definition; hover on imported names. Lost: all type errors, the
"unchecked" notes, import-list export requirements, and hover on the module's
own top-level names.

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
