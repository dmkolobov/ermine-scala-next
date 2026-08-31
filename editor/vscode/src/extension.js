"use strict";

// Ermine language client.
//
// The design constraint here is that NOTHING may block. The server is
// single-threaded by design (LSP-ROADMAP decision 3: SessionEnv is not
// thread-safe), it boots a ~13s Prelude/Layout closure before it can answer
// anything, and bin/ermine-lsp shells out to sbt on a cold checkout. Each of
// those looks like a hang from inside VS Code unless it is made visible, so:
//
//   - activate() returns immediately; the client starts on a promise
//   - the sbt classpath warm-up runs as a cancellable progress task BEFORE
//     the server is spawned, rather than invisibly inside it
//   - a status bar item tracks booting -> ready, driven by the server's own
//     window/logMessage
//   - navigation requests during boot are answered null by the server rather
//     than queued behind it (Definitions.scala), so nothing spins
//
// Fast mode is the escape hatch for the remaining cost: it skips type
// checking, which is about half the time to diagnostics.

const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");
const vscode = require("vscode");
const { LanguageClient, RevealOutputChannelOn } = require("vscode-languageclient/node");

const CLASSPATH_CACHE = path.join("target", "ermine-classpath");

/** @type {LanguageClient | undefined} */
let client;
/** @type {vscode.StatusBarItem | undefined} */
let status;
/** @type {vscode.OutputChannel | undefined} */
let channel;

// --------------------------------------------------------------- settings

function config() {
  return vscode.workspace.getConfiguration("ermine");
}

function workspaceRoot() {
  const folders = vscode.workspace.workspaceFolders;
  return folders && folders.length ? folders[0].uri.fsPath : undefined;
}

/** The server command, and the repo root it lives in. */
function resolveServer() {
  const configured = config().get("serverPath", "").trim();
  if (configured) return { command: configured, root: path.dirname(path.dirname(configured)) };
  const root = workspaceRoot();
  if (!root) return undefined;
  return { command: path.join(root, "bin", "ermine-lsp"), root };
}

// -------------------------------------------------------------- status bar

function setStatus(text, tooltip, warn) {
  if (!status) return;
  status.text = `$(symbol-namespace) ${text}`;
  status.tooltip = tooltip;
  status.backgroundColor = warn
    ? new vscode.ThemeColor("statusBarItem.warningBackground")
    : undefined;
  status.show();
}

function fastModeSuffix() {
  return config().get("fastMode", false) ? " (fast)" : "";
}

// ------------------------------------------------------- classpath warm-up

/**
 * bin/ermine-lsp builds its classpath with sbt on first run and caches it.
 * Left to itself that happens inside the spawned server with its output going
 * nowhere, so the editor just sits there for minutes. Do it up front, visibly,
 * and let the user cancel.
 *
 * Resolves true if the server is safe to start.
 */
async function warmClasspath(root, command) {
  const cache = path.join(root, CLASSPATH_CACHE);
  if (fs.existsSync(cache) && fs.statSync(cache).size > 0) return true;
  if (!config().get("warmClasspathOnStart", true)) return true;

  return vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      title: "Ermine: building the classpath cache (first run, sbt)",
      cancellable: true,
    },
    (_progress, token) =>
      new Promise((resolve) => {
        // Running the launcher with stdin closed makes it build the cache and
        // exit rather than serve; we only want the side effect.
        const child = execFile(command, [], { cwd: root }, (err) => {
          if (err && !fs.existsSync(cache)) {
            log(`classpath warm-up failed: ${err.message}`);
            vscode.window
              .showWarningMessage(
                "Ermine: could not build the classpath cache. The server may take several minutes to start.",
                "Show Output"
              )
              .then((pick) => pick && channel && channel.show(true));
          }
          resolve(true);
        });
        if (child.stdin) child.stdin.end();
        token.onCancellationRequested(() => {
          child.kill();
          log("classpath warm-up cancelled by the user");
          resolve(true);
        });
      })
  );
}

// ------------------------------------------------------------------- client

function log(message) {
  if (channel) channel.appendLine(message);
}

async function startClient(context) {
  const server = resolveServer();
  if (!server) {
    log("no workspace folder and no ermine.serverPath — not starting");
    setStatus("Ermine: no workspace", "Open the ermine-scala folder, or set ermine.serverPath.", true);
    return;
  }
  if (!fs.existsSync(server.command)) {
    setStatus("Ermine: server not found", `${server.command} does not exist`, true);
    vscode.window.showErrorMessage(
      `Ermine: ${server.command} not found. Set "ermine.serverPath" to your bin/ermine-lsp.`
    );
    return;
  }

  setStatus("Ermine: preparing…", "Checking the classpath cache");
  await warmClasspath(server.root, server.command);

  const env = { ...process.env };
  const logFile = config().get("logFile", "").trim();
  if (logFile) env.ERMINE_LSP_LOG = logFile;

  const serverOptions = {
    command: server.command,
    args: [],
    options: { cwd: server.root, env },
  };

  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "ermine" }],
    outputChannel: channel,
    // Diagnostics arriving is not a reason to steal focus.
    revealOutputChannelOn: RevealOutputChannelOn.Never,
    initializationOptions: { fastMode: config().get("fastMode", false) },
  };

  client = new LanguageClient("ermine", "Ermine Language Server", serverOptions, clientOptions);

  // The server reports boot progress and readiness through window/logMessage;
  // mirror it into the status bar so a 13s boot reads as progress, not a hang.
  client.onNotification("window/logMessage", (params) => {
    const message = String((params && params.message) || "");
    if (/ready/i.test(message)) {
      setStatus(`Ermine${fastModeSuffix()}`, message);
    } else if (/booting|Loading/i.test(message)) {
      setStatus("Ermine: starting session…", message);
    }
  });

  setStatus("Ermine: starting session…", "Loading the Prelude/Layout closure (~13s)");

  // Deliberately not awaited by activate(): VS Code should never wait on the
  // handshake, let alone on the session boot behind it.
  client.start().then(
    () => log("language client started"),
    (err) => {
      log(`language client failed to start: ${err && err.stack ? err.stack : err}`);
      setStatus("Ermine: server failed", String(err), true);
      vscode.window
        .showErrorMessage("Ermine: the language server failed to start.", "Show Output")
        .then((pick) => pick && channel && channel.show(true));
    }
  );

  context.subscriptions.push({ dispose: () => stopQuietly(client) });
}

/**
 * stop() throws if the client never reached `running` — which is exactly the
 * case after a failed start, and exactly when teardown still has to work.
 */
async function stopQuietly(c) {
  if (!c) return;
  try {
    await c.stop();
  } catch (err) {
    log(`stop skipped (${err && err.message ? err.message : err})`);
  }
}

async function restart(context) {
  if (client) {
    log("restarting…");
    await stopQuietly(client);
    client = undefined;
  }
  await startClient(context);
}

// ----------------------------------------------------------------- activate

async function activate(context) {
  channel = vscode.window.createOutputChannel("Ermine");
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  status.command = "ermine.showOutput";
  context.subscriptions.push(channel, status);

  context.subscriptions.push(
    vscode.commands.registerCommand("ermine.restartServer", () => restart(context)),
    vscode.commands.registerCommand("ermine.showOutput", () => channel && channel.show(true)),
    vscode.commands.registerCommand("ermine.toggleFastMode", async () => {
      const now = config().get("fastMode", false);
      await config().update("fastMode", !now, vscode.ConfigurationTarget.Workspace);
      vscode.window.setStatusBarMessage(
        `Ermine: fast mode ${!now ? "on — syntax-only diagnostics" : "off — full type checking"}`,
        3000
      );
    })
  );

  // Push settings ourselves rather than relying on the client's synchronize
  // machinery, so the payload shape matches what the server reads exactly.
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (!event.affectsConfiguration("ermine")) return;
      if (client) {
        try {
          await client.sendNotification("workspace/didChangeConfiguration", {
            settings: { ermine: { fastMode: config().get("fastMode", false) } },
          });
        } catch (err) {
          log(`could not push settings: ${err}`);
        }
      }
      setStatus(`Ermine${fastModeSuffix()}`, "Ermine language server");
      // These two only take effect on a fresh process.
      if (
        event.affectsConfiguration("ermine.serverPath") ||
        event.affectsConfiguration("ermine.logFile")
      ) {
        await restart(context);
      }
    })
  );

  // Not awaited on purpose — activation must not wait on the server.
  startClient(context);
}

function deactivate() {
  return stopQuietly(client);
}

module.exports = { activate, deactivate };
