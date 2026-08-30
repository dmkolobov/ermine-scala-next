# Ermine language server (stage 0)

`bin/ermine-lsp` speaks LSP over stdio. On `initialize`/`initialized` it
boots a resident Ermine session (Lib.preamble + the Prelude/Layout closure,
type checking on, interface files off; ~13s, reported via
`window/logMessage`), then serves:

- **Diagnostics** on `didOpen`/`didSave` of a `.e` file: the file is
  parsed and typechecked against a fresh copy of the resident session, so
  a broken file never poisons the server. Imports resolve against the
  file's directory first (workspace siblings), then the stdlib. One
  diagnostic per failure, positioned from the report; cleared on a clean
  check and on `didClose`.
- **Go-to-definition** for term names: same file, workspace siblings, and
  the stdlib (targets land in the classpath copy of the sources).
- **Hover** with the inferred type for top-level and imported names
  (`Nav.twice : forall a. a -> a`). Local binders answer null for now.

Logging goes to the file named by `ERMINE_LSP_LOG` (or the
`-Dermine.lsp.log` system property); stdout is reserved for the protocol.

## Emacs (eglot)

```elisp
(define-derived-mode ermine-mode prog-mode "Ermine"
  "Bare major mode for Ermine `.e' files (stage-0 LSP demo).")
(add-to-list 'auto-mode-alist '("\\.e\\'" . ermine-mode))
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(ermine-mode . ("/path/to/ermine-scala/bin/ermine-lsp"))))
;; M-x eglot in an .e buffer. Diagnostics on save, M-. for definition,
;; K / eldoc for hover.
```

## VS Code

VS Code has no built-in generic LSP client; wire the server through any
thin client extension by pointing it at `bin/ermine-lsp` for language id
`ermine` / files `*.e`, or scaffold a ten-line extension with
`vscode-languageclient`:

```js
const { LanguageClient } = require("vscode-languageclient/node");
exports.activate = (ctx) => {
  const client = new LanguageClient("ermine", "Ermine",
    { command: "/path/to/ermine-scala/bin/ermine-lsp" },
    { documentSelector: [{ pattern: "**/*.e" }] });
  ctx.subscriptions.push(client);
  client.start();
};
```

## Regression harness

`tracker/tools/lsp-smoke.sh` runs the scripted client
(`tracker/tools/lsp-client.py`) against the fixtures in
`tracker/lsp-tests/` — 27 checks over everything above. Run it with
core/test and repl-smoke before committing server changes
(tracker/LSP-ROADMAP.md, Baselines).
