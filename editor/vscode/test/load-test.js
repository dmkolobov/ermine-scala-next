#!/usr/bin/env node
"use strict";

// Load the extension for real, outside VS Code.
//
// `require("vscode")` only resolves inside the editor, so this installs a stub
// in the module loader and then calls activate() exactly as VS Code would. It
// proves the things a syntax check cannot: that the module loads, that
// vscode-languageclient is importable and constructible, that activation
// registers what package.json promises, that nothing throws, and — the point
// of the exercise — that activation does not BLOCK.
//
//     node editor/vscode/test/load-test.js
//
// Exits non-zero on any failure.

const Module = require("module");
const path = require("path");
const assert = require("assert");

const EXT_ROOT = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(EXT_ROOT, "..", "..");

const failures = [];
function check(name, cond, detail) {
  if (cond) return;
  failures.push(name + (detail ? ": " + detail : ""));
  console.log("  FAIL " + name + (detail ? ": " + detail : ""));
}

// ------------------------------------------------------------- vscode stub

const recorded = {
  commands: [],
  outputChannels: [],
  statusBarItems: [],
  progressTitles: [],
  errors: [],
  warnings: [],
  configListeners: [],
  registrations: [],
};

const settings = {
  serverPath: "",
  fastMode: false,
  logFile: "",
  warmClasspathOnStart: false, // the sbt warm-up is exercised separately
  "trace.server": "off",
};

const disposable = () => ({ dispose() {} });

const vscode = {
  workspace: {
    workspaceFolders: [{ uri: { fsPath: REPO_ROOT }, name: "ermine-scala", index: 0 }],
    getConfiguration(section) {
      assert.strictEqual(section, "ermine");
      return {
        get: (key, dflt) => (key in settings ? settings[key] : dflt),
        update: async (key, value) => { settings[key] = value; },
      };
    },
    onDidChangeConfiguration(cb) {
      recorded.configListeners.push(cb);
      return disposable();
    },
    onDidChangeTextDocument: () => disposable(),
    onDidOpenTextDocument: () => disposable(),
    onDidCloseTextDocument: () => disposable(),
    onDidSaveTextDocument: () => disposable(),
    textDocuments: [],
  },
  window: {
    createOutputChannel(name) {
      const ch = { name, lines: [], appendLine(l) { this.lines.push(l); },
                   append() {}, show() {}, clear() {}, dispose() {} };
      recorded.outputChannels.push(ch);
      return ch;
    },
    createStatusBarItem(alignment, priority) {
      const item = { alignment, priority, text: "", tooltip: "", command: "",
                     backgroundColor: undefined, shown: false,
                     show() { this.shown = true; }, hide() {}, dispose() {} };
      recorded.statusBarItems.push(item);
      return item;
    },
    withProgress(options, task) {
      recorded.progressTitles.push(options.title);
      return task({ report() {} }, { onCancellationRequested() {} });
    },
    showErrorMessage(msg) { recorded.errors.push(msg); return Promise.resolve(undefined); },
    showWarningMessage(msg) { recorded.warnings.push(msg); return Promise.resolve(undefined); },
    showInformationMessage() { return Promise.resolve(undefined); },
    setStatusBarMessage() { return disposable(); },
  },
  commands: {
    registerCommand(id, fn) { recorded.commands.push({ id, fn }); return disposable(); },
    executeCommand: () => Promise.resolve(),
  },
  // The client registers a provider per capability the server advertises;
  // auto-stub every register* so a real start() can get as far as the wire.
  languages: new Proxy(
    { createDiagnosticCollection: () => ({ set() {}, clear() {}, dispose() {} }) },
    {
      get(target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop === "string" && prop.startsWith("register")) {
          // Record it: which providers the client registers is the whole of
          // "the client serves these capabilities on its own" (6.7.1).
          return (...args) => { recorded.registrations.push({ name: prop, args }); return disposable(); };
        }
        return undefined;
      },
    }
  ),
  // Not generic-stubbable: vscode-languageclient builds a Map from the LSP
  // kind strings to these OBJECTS at module load, then calls `.append()` on
  // CodeActionKind.Empty for any string the map misses. A stub whose statics
  // are all 0 makes every lookup miss and then explodes on `0.append`, which
  // is what registering the 6.6 codeActionProvider's `codeActionKinds` hits.
  CodeActionKind: (() => {
    class CodeActionKind {
      constructor(value) { this.value = value; }
      append(part) { return new CodeActionKind(this.value ? this.value + "." + part : part); }
      contains(other) { return other.value === this.value || other.value.startsWith(this.value + "."); }
      intersects(other) { return this.contains(other) || other.contains(this); }
    }
    for (const [name, value] of [
      ["Empty", ""], ["QuickFix", "quickfix"], ["Refactor", "refactor"],
      ["RefactorExtract", "refactor.extract"], ["RefactorInline", "refactor.inline"],
      ["RefactorMove", "refactor.move"], ["RefactorRewrite", "refactor.rewrite"],
      ["Source", "source"], ["SourceOrganizeImports", "source.organizeImports"],
      ["SourceFixAll", "source.fixAll"], ["Notebook", "notebook"],
    ]) CodeActionKind[name] = new CodeActionKind(value);
    return CodeActionKind;
  })(),
  StatusBarAlignment: { Left: 1, Right: 2 },
  ProgressLocation: { SourceControl: 1, Window: 10, Notification: 15 },
  ConfigurationTarget: { Global: 1, Workspace: 2, WorkspaceFolder: 3 },
  ThemeColor: class ThemeColor { constructor(id) { this.id = id; } },
  EventEmitter: class EventEmitter {
    constructor() { this.listeners = []; }
    get event() { return (l) => { this.listeners.push(l); return disposable(); }; }
    fire(v) { this.listeners.forEach((l) => l(v)); }
    dispose() {}
  },
  Uri: {
    file: (f) => ({ scheme: "file", fsPath: f, path: f, toString: () => "file://" + f }),
    parse: (s) => ({ scheme: "file", fsPath: s, path: s, toString: () => s }),
  },
  Disposable: class Disposable { constructor(fn) { this.dispose = fn || (() => {}); } },
  version: "1.90.0",
  env: { language: "en", appName: "node-test-harness" },
  extensions: { getExtension: () => undefined },
};

// vscode-languageclient SUBCLASSES nine vscode API classes at module load
// (CompletionItem, CodeAction, Diagnostic, ...) and names dozens more lazily.
// Rather than enumerate them, hand back a generic class for any capitalised
// member the stub does not define; static access on it yields 0, which is
// enough for the enum-shaped ones.
const generic = new Map();
function genericClass(name) {
  if (!generic.has(name)) {
    const C = class Stub {
      constructor(...args) { this.args = args; }
    };
    Object.defineProperty(C, "name", { value: name });
    generic.set(name, new Proxy(C, {
      get(target, prop) {
        if (prop in target) return target[prop];
        return typeof prop === "string" && /^[A-Z]/.test(prop) ? 0 : undefined;
      },
    }));
  }
  return generic.get(name);
}

const vscodeStub = new Proxy(vscode, {
  get(target, prop) {
    if (prop in target) return target[prop];
    if (typeof prop === "string" && /^[A-Z]/.test(prop)) return genericClass(prop);
    return undefined;
  },
  has() { return true; },
});

const realResolve = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === "vscode") return vscodeStub;
  return realResolve.apply(this, arguments);
};

// ------------------------------------------------------------------- checks

async function main() {
  console.log("1. the extension module loads");
  let ext;
  try {
    ext = require(path.join(EXT_ROOT, "src", "extension.js"));
  } catch (err) {
    check("require(extension.js)", false, err && err.stack ? err.stack.split("\n")[0] : String(err));
    return;
  }
  check("exports activate", typeof ext.activate === "function");
  check("exports deactivate", typeof ext.deactivate === "function");

  console.log("2. vscode-languageclient is importable and constructible");
  try {
    const lc = require(path.join(EXT_ROOT, "node_modules", "vscode-languageclient", "node"));
    check("LanguageClient is exported", typeof lc.LanguageClient === "function");
    check("RevealOutputChannelOn is exported", lc.RevealOutputChannelOn !== undefined);
  } catch (err) {
    check("require(vscode-languageclient/node)", false, String(err).split("\n")[0]);
  }

  console.log("3. activate() returns promptly and does not throw");
  const ctx = { subscriptions: [] };
  const started = Date.now();
  try {
    await ext.activate(ctx);
  } catch (err) {
    check("activate() threw", false, err && err.stack ? err.stack.split("\n").slice(0, 3).join(" | ") : String(err));
  }
  const elapsed = Date.now() - started;
  // The server boot is ~13s. If activate() waited on it we would see it here.
  check("activate() did not block on the server", elapsed < 5000, elapsed + "ms");
  console.log("   activate() returned in " + elapsed + "ms");

  console.log("4. activation registered what package.json promises");
  const manifest = require(path.join(EXT_ROOT, "package.json"));
  const promised = manifest.contributes.commands.map((c) => c.command).sort();
  const registered = recorded.commands.map((c) => c.id).sort();
  check("every contributed command is registered",
        JSON.stringify(promised) === JSON.stringify(registered),
        "promised " + JSON.stringify(promised) + " got " + JSON.stringify(registered));
  check("an output channel was created", recorded.outputChannels.length === 1);
  check("a status bar item was created and shown",
        recorded.statusBarItems.length === 1 && recorded.statusBarItems[0].shown);
  check("a configuration listener was installed", recorded.configListeners.length === 1);
  check("subscriptions were registered for disposal", ctx.subscriptions.length >= 4,
        ctx.subscriptions.length + " subscriptions");

  console.log("5. the status bar reports the session starting, not silence");
  const bar = recorded.statusBarItems[0];
  check("status bar has text", typeof bar.text === "string" && bar.text.length > 0, JSON.stringify(bar.text));
  console.log("   status bar reads: " + JSON.stringify(bar.text));

  console.log("6. LIVE: the client handshakes with the real bin/ermine-lsp");
  // The extension only updates the status bar to plain "Ermine" from its own
  // window/logMessage handler, and the server only sends "ready" after the
  // session boots. So the status bar reaching that state is proof of the whole
  // chain: process spawned -> initialize/initialized -> notification routed
  // back through the client -> the extension's handler ran.
  const classpath = path.join(REPO_ROOT, "target", "ermine-classpath");
  const fs = require("fs");
  if (!fs.existsSync(classpath)) {
    console.log("   SKIPPED — no target/ermine-classpath; run bin/ermine-lsp once first");
  } else {
    const deadline = Date.now() + 90000;
    let ready = false;
    while (Date.now() < deadline) {
      // "session ready" is emitted only by Main.scala once boot completes, so
      // this cannot be confused with a status update the test itself provoked
      // — nor with the "loading the session" announcement that precedes it.
      if (/session ready/i.test(String(bar.tooltip))) {
        ready = true;
        break;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    check("the session reported READY through the client", ready,
          "last tooltip " + JSON.stringify(bar.tooltip) + ", text " + JSON.stringify(bar.text) +
          "; channel tail: " + JSON.stringify(recorded.outputChannels[0].lines.slice(-3)));
    if (ready) {
      console.log("   status bar now reads: " + JSON.stringify(bar.text));
      console.log("   tooltip (the server's own words): " + JSON.stringify(bar.tooltip));
      check("the status bar left the starting state once ready",
            !/starting session/.test(bar.text), bar.text);
      check("the ready notification carries the module count",
            /129 modules/.test(String(bar.tooltip)), String(bar.tooltip));

      // 6.7.1: NOTHING in this extension filters the server's capabilities.
      // vscode-languageclient registers one provider per advertised
      // capability all by itself, so the proof that completion, rename,
      // references, highlight, symbols and code actions reach the editor is
      // that these registrations happened -- with no code here to make them.
      const registered = recorded.registrations.map((r) => r.name);
      const expected = [
        "registerDefinitionProvider", "registerHoverProvider",
        "registerReferenceProvider", "registerDocumentHighlightProvider",
        "registerRenameProvider", "registerDocumentSymbolProvider",
        "registerWorkspaceSymbolProvider", "registerCompletionItemProvider",
        "registerCodeActionsProvider",
      ];
      for (const name of expected) {
        check("the client registered " + name + " from the server's capabilities",
              registered.includes(name), "registered " + JSON.stringify(registered));
      }
      console.log("   providers registered by the client: " + registered.length +
                  " (" + registered.map((n) => n.replace(/^register|Provider$/g, "")).join(", ") + ")");
      // The completion trigger character is the SERVER's (`.`), passed
      // through by the client; nothing in package.json declares it.
      const comp = recorded.registrations.find((r) => r.name === "registerCompletionItemProvider");
      check("the server's completion trigger character reached the editor",
            comp && comp.args.slice(2).includes("."),
            comp ? JSON.stringify(comp.args.slice(2)) : "no completion registration");
      const ca = recorded.registrations.find((r) => r.name === "registerCodeActionsProvider");
      const kinds = ca && ca.args[2] && ca.args[2].providedCodeActionKinds;
      check("the server's code-action kinds reached the editor",
            !!kinds && kinds.map((k) => k.value).join(",") === "quickfix,source",
            JSON.stringify(kinds && kinds.map((k) => k.value)));
    }
  }

  console.log("7. the fast-mode toggle flips the setting");
  const toggle = recorded.commands.find((c) => c.id === "ermine.toggleFastMode");
  check("toggle command exists", !!toggle);
  if (toggle) {
    const before = settings.fastMode;
    await toggle.fn();
    check("toggle flipped fastMode", settings.fastMode === !before,
          before + " -> " + settings.fastMode);
    await toggle.fn();
    check("toggle flips back", settings.fastMode === before);
  }

  console.log("8. a configuration change pushes settings without throwing");
  const listener = recorded.configListeners[0];
  try {
    await listener({ affectsConfiguration: (s) => s === "ermine" });
  } catch (err) {
    check("config listener threw", false, String(err).split("\n")[0]);
  }

  console.log("9. deactivate() is safe to call");
  try {
    await ext.deactivate();
  } catch (err) {
    check("deactivate() threw", false, String(err).split("\n")[0]);
  }

  console.log();
  const errs = recorded.errors.concat(recorded.warnings);
  if (errs.length) console.log("   (extension surfaced: " + JSON.stringify(errs) + ")");
}

main().then(
  () => {
    if (failures.length) {
      console.log("FAILED — " + failures.length + " problem(s)");
      process.exit(1);
    }
    console.log("PASS — the extension loads, activates and registers correctly");
    process.exit(0);
  },
  (err) => {
    console.log("HARNESS ERROR: " + (err && err.stack ? err.stack : err));
    process.exit(2);
  }
);
