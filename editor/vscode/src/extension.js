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
const { LanguageClient, RevealOutputChannelOn, State } = require("vscode-languageclient/node");
const core = require("./preview-core");

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

/**
 * The values the server reads out of BOTH settings routes (section 2.4 of
 * tracker/JSON-WIDGET-PLAYGROUND.md): `initializationOptions.preview.*` at
 * start and `settings.ermine.preview.*` on a push. Read once, shaped by
 * `preview-core`, so the two payloads cannot drift.
 */
function settingValues() {
  return {
    fastMode: config().get("fastMode", false),
    timeoutSeconds: config().get("preview.timeoutSeconds", undefined),
    maxDocumentBytes: config().get("preview.maxDocumentBytes", undefined),
  };
}

function reportSettingProblems(problems) {
  for (const problem of problems) log("settings: " + problem);
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

  // `ermine.maxHeap` -> ERMINE_LSP_XMX, which bin/ermine-lsp turns into
  // -Xmx (WP-5 stage C). A value the launcher would refuse is refused HERE
  // instead, out loud, and simply not exported: the launcher's own refusal
  // goes to the server's stderr, which is not where the developer who typed
  // the setting is looking. Either way the server runs on its own 2g.
  const heap = core.heapEnvironment(config().get("maxHeap", ""));
  if (heap.problem) {
    log("settings: " + heap.problem);
    vscode.window.showWarningMessage("Ermine: " + heap.problem);
  }
  Object.assign(env, heap.env);

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
    initializationOptions: (() => {
      const values = settingValues();
      reportSettingProblems(core.previewSettings(values).problems);
      return core.initializationOptions(values);
    })(),
    middleware: {
      // "Ermine: Reload Modules" (a server-declared command, see activate):
      // say what the server did, in the status bar.
      executeCommand: async (command, args, next) => {
        const r = await next(command, args);
        if (command === "ermine.reloadModules") {
          const n = r && r.reloaded ? r.reloaded.length : 0;
          vscode.window.setStatusBarMessage(
            n === 0 ? "Ermine: no loaded module changed"
                    : `Ermine: reloaded ${n} module(s)${r.failure ? " — with a failure, see the output" : ""}`,
            4000
          );
          if (r && r.failure) log(`reload failed: ${r.failure}`);
        }
        return r;
      },
    },
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

  installPreviewHandlers(client);

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

// ------------------------------------------------------------------ preview
//
// WP-7 of tracker/JSON-WIDGET-PLAYGROUND.md: the extension's half of the
// render loop, WITHOUT a panel. The webview is WP-10 and params files are
// WP-8, so what a banner would hold is shown with the plain editor UI --
// a status bar item, one error notification with the restart button, and
// ONE untitled JSON tab that is reused and updated in place.
//
// EVERY DECISION IS IN src/preview-core.js and is unit-tested there; this
// section only reads the editor's state, calls those, and does what they
// say.

const PICK_KEY = "ermine.preview.pick";

// A SHORT COALESCING WINDOW, and what it is and is not for. Two triggers
// that land inside it cost one render -- a save the watcher reports twice,
// a settings change that fires per key. IT IS NOT THE DEDUPE BETWEEN THE
// WATCHER AND `invalidated` (review DM-1): that one is structural and is in
// `core.isPlacement404`'s comment, because the server's notification
// follows its own reload of the file, which is seconds. The explicit render
// command does not go through this window at all.
const COALESCE_MS = 150;

const CLIENT_STATE = {};
CLIENT_STATE[(State && State.Stopped) || 1] = "Stopped";
CLIENT_STATE[(State && State.Running) || 2] = "Running";
CLIENT_STATE[(State && State.Starting) || 3] = "Starting";

/** @type {ReturnType<typeof core.makePick> | undefined} */
let picked;
let generation = 0;
let lastAnswer;
let stuckState = core.initialStuckState();
let renderInFlight = false;
let moduleRefreshInFlight = false;
let coalesceTimer;
/** @type {vscode.StatusBarItem | undefined} */
let previewStatus;
/** @type {vscode.TextDocument | undefined} */
let previewTab;
/** @type {vscode.Disposable[]} */
let pickWatchers = [];
let extContext;
/** Root problems already reported, so the warning really is once (S5). */
const warnedRoots = new Set();

/**
 * LAZY on purpose. A second status bar item that says "no report picked"
 * before anyone has asked for a preview is noise, and test/load-test.js
 * counts the items activation creates.
 */
function previewItem() {
  if (!previewStatus) {
    previewStatus = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 99);
    previewStatus.command = "ermine.previewReport";
    if (extContext && extContext.subscriptions) extContext.subscriptions.push(previewStatus);
  }
  return previewStatus;
}

function setPreviewStatus() {
  const view = core.statusBarState({
    stuck: stuckState.stuck,
    message: stuckState.message,
    running: stuckState.running,
    rendering: renderInFlight,
    pick: picked,
  });
  if (view.hidden) {
    if (previewStatus) previewStatus.hide();
    return;
  }
  const item = previewItem();
  item.text = view.text;
  item.tooltip = view.tooltip;
  item.backgroundColor =
    view.severity === "warning" ? new vscode.ThemeColor("statusBarItem.warningBackground") : undefined;
  item.show();
}

/**
 * `ermine.preview.roots` for the workspace folder that OWNS the picked
 * report (section 2.4: the setting is resource-scoped), absolutised against
 * that folder. A file outside every folder falls back to the window-scope
 * value and the first folder, which is the same fallback `resolveServer`
 * makes for the server path.
 *
 * NEVER THROWS: it is called from a command, from a settings change and
 * from activation, and a setting nobody can parse must not take any of
 * those down.
 */
function rootsFor(uri) {
  try {
    const folder =
      typeof vscode.workspace.getWorkspaceFolder === "function"
        ? vscode.workspace.getWorkspaceFolder(uri)
        : undefined;
    const scoped = folder ? vscode.workspace.getConfiguration("ermine", folder.uri) : config();
    const base = folder ? folder.uri.fsPath : workspaceRoot();
    const resolved = core.absoluteRoots(scoped.get("preview.roots", []), base);
    for (const problem of resolved.problems) {
      const key = String(base) + "␟" + problem;
      if (warnedRoots.has(key)) continue;
      warnedRoots.add(key);
      log("preview: " + problem);
      vscode.window.showWarningMessage("Ermine: " + problem);
    }
    return resolved.roots;
  } catch (err) {
    log(`preview: could not read ermine.preview.roots: ${err && err.message ? err.message : err}`);
    return [];
  }
}

function installPreviewHandlers(c) {
  // Section 3 step 5-6. The set already includes dependents, so saving a
  // widget module names every report that imports it.
  c.onNotification("ermine/preview/invalidated", (params) => {
    const modules = params && Array.isArray(params.modules) ? params.modules : [];
    if (!picked) return;
    if (core.shouldRerenderOnInvalidated(picked, modules)) {
      scheduleRender(`invalidated: ${picked.module}`);
    } else if (picked.module && modules.length) {
      // Section 3.2's own words for the case where nothing happens (S3).
      vscode.window.setStatusBarMessage(`Ermine: not used by ${core.pickLabel(picked)}`, 4000);
      log(`preview: invalidated [${modules.join(", ")}] — not used by ${core.pickLabel(picked)}`);
    }
  });

  // Section 4's `ermine/preview/stuck`. AUTHORITATIVE for the state; the
  // `window/showMessage` beside it is advisory and has no handler here, so
  // no state can be derived from it.
  c.onNotification("ermine/preview/stuck", (params) => {
    applyStuck(
      core.stuckReduce(stuckState, {
        type: "notification",
        stuck: !!(params && params.stuck === true),
        message: params && params.message,
        seq: params && params.seq,
      })
    );
  });

  // Section 5's "Server stopped" row, and DD-2's `seq` reset. The library
  // passes through `Starting`, so "Stopped -> Running" is observed as any
  // transition INTO Running.
  if (typeof c.onDidChangeState === "function") {
    c.onDidChangeState((event) => {
      const to = CLIENT_STATE[event && event.newState];
      if (!to) return;
      if (to === "Running" && !stuckState.running) {
        // A fresh process knows nothing about the last one: the answer we
        // are holding described a server that is gone.
        lastAnswer = undefined;
      }
      applyStuck(
        core.stuckReduce(stuckState, {
          type: "clientState",
          from: CLIENT_STATE[event && event.oldState],
          to,
        })
      );
    });
  }
}

function applyStuck(result) {
  stuckState = result.state;
  const fx = result.effects;
  if (fx.raised) {
    log("preview: STUCK — " + stuckState.message);
    vscode.window
      .showErrorMessage("Ermine: " + stuckState.message, "Restart Language Server")
      .then((choice) => {
        if (choice) vscode.commands.executeCommand("ermine.restartServer");
      });
  }
  if (fx.cleared) {
    log("preview: no longer stuck");
    vscode.window.setStatusBarMessage("Ermine: the preview recovered", 4000);
  }
  if (fx.offline) log("preview: the language server stopped — preview offline");
  if (fx.online) log("preview: the language server is running again");
  // WP-8's hook: every `invalidate` of a stuck interval was dropped, so the
  // params schema has to be asked for again once WP-8 writes params files.
  // WP-7 sends no params and needs no schema, so this only says so.
  if (fx.schema && picked) {
    log(`preview: a schema re-request belongs here (WP-8) for ${core.pickLabel(picked)}`);
  }
  if (fx.rerender) scheduleRender("the preview recovered");
  setPreviewStatus();
}

function scheduleRender(reason) {
  if (!picked) return;
  if (coalesceTimer) clearTimeout(coalesceTimer);
  coalesceTimer = setTimeout(() => {
    coalesceTimer = undefined;
    renderNow(reason).catch((err) => log(`preview: render failed: ${err && err.stack ? err.stack : err}`));
  }, COALESCE_MS);
}

async function renderNow(reason, reveal) {
  if (!picked) return;
  if (!client) {
    log("preview: no language client — nothing to render with");
    return;
  }
  generation += 1;
  const mine = generation;
  // PER REQUEST, not a module global (review S2): `renderNow` is re-entrant
  // and a second render must not rewrite the first one's mark.
  const sentAtMark = stuckState.highWater;
  renderInFlight = true;
  setPreviewStatus();
  log(`preview: render ${core.pickLabel(picked)} (generation ${mine}; ${reason})`);

  let answer;
  try {
    answer = await client.sendRequest("ermine/render", core.renderParams(picked, null, mine));
  } catch (err) {
    if (core.isDisplaced(err)) {
      log(`preview: render ${mine} was displaced by a newer one`);
      if (mine === generation) renderInFlight = false;
      setPreviewStatus();
      return;
    }
    answer = core.errorAnswer(err, mine);
  }
  if (mine === generation) renderInFlight = false;

  // Section 2.5: an answer behind the current generation is discarded.
  if (!core.isCurrentGeneration(generation, answer)) {
    log(`preview: discarded a stale answer (generation ${answer && answer.generation} < ${generation})`);
    setPreviewStatus();
    return;
  }

  lastAnswer = answer;
  if (core.isPlacement404(answer)) {
    log(`preview: the pick cannot be placed (${answer.reason}); watching ${picked.fsPath} for it to come back`);
  }
  applyStuck(
    core.stuckReduce(stuckState, {
      type: "answer",
      stuck: !!(answer && answer.stuck === true),
      message: answer && answer.message,
      seqAtSend: sentAtMark,
    })
  );
  await showAnswer(answer, reveal === true);
  if (core.isOk(answer) && !picked.module) refreshModule();
  setPreviewStatus();
}

/**
 * ONE untitled tab, reused and updated in place. A good answer shows the
 * DOCUMENT; a refusal shows the whole `{ok:false, status, message, path}`
 * answer, which is where the refusal's own diagnostic lives.
 *
 * IT IS REVEALED ONLY WHEN THE USER ASKED FOR IT (review IM-2): the picker
 * and the render command reveal, and every automatic re-render -- a save, a
 * recovery, a restart -- only applies the edit, so the loop cannot keep
 * pulling a tab in front of what is being edited. The first open goes
 * BESIDE the active column for the same reason. A tab the user closed is
 * re-created so that its content stays current, and stays unrevealed unless
 * this call was asked to reveal.
 */
async function showAnswer(answer, reveal) {
  const content = core.tabContent(answer);
  try {
    let created = false;
    if (!previewTab || previewTab.isClosed) {
      previewTab = await vscode.workspace.openTextDocument({ language: "json", content });
      created = true;
    } else {
      const edit = new vscode.WorkspaceEdit();
      const lastLine = previewTab.lineAt(previewTab.lineCount - 1);
      edit.replace(previewTab.uri, new vscode.Range(new vscode.Position(0, 0), lastLine.range.end), content);
      await vscode.workspace.applyEdit(edit);
    }
    if (reveal) {
      await vscode.window.showTextDocument(previewTab, {
        preview: false,
        preserveFocus: true,
        viewColumn: created ? vscode.ViewColumn.Beside : undefined,
      });
    }
  } catch (err) {
    log(`preview: could not show the answer: ${err && err.message ? err.message : err}`);
  }
}

/**
 * The module name is what `invalidated` names, and it comes from
 * `ermine/preview/reports`. A pick made by typing a binding on a file the
 * server could not list has none, so one extra `reports` request is made
 * after a SUCCESSFUL render — at most one in flight, and it stops for good
 * as soon as it answers.
 */
async function refreshModule() {
  if (moduleRefreshInFlight || !client || !picked || picked.module) return;
  moduleRefreshInFlight = true;
  try {
    const answer = await client.sendRequest("ermine/preview/reports", core.reportsParams(picked.uri));
    if (picked && answer && answer.module) {
      picked.module = String(answer.module);
      rememberPick();
      log(`preview: learned the module name ${picked.module}`);
      setPreviewStatus();
    }
  } catch (err) {
    log(`preview: could not learn the module name: ${err && err.message ? err.message : err}`);
  } finally {
    moduleRefreshInFlight = false;
  }
}

/**
 * Q11 (section 3 step 6): a watcher on the picked report's OWN path, and on
 * nothing else. Whether an event re-renders is `core.shouldRerenderOnFileEvent`'s
 * decision -- see its comment for why the two triggers cannot overlap.
 */
function installWatcher() {
  disposeWatchers();
  if (!picked) return;
  try {
    const pattern = new vscode.RelativePattern(
      vscode.Uri.file(path.dirname(picked.fsPath)),
      path.basename(picked.fsPath)
    );
    const watcher = vscode.workspace.createFileSystemWatcher(pattern);
    if (!watcher) return;
    const fire = (uri) => {
      if (!picked) return;
      const where = uri && uri.fsPath ? uri.fsPath : picked.fsPath;
      if (core.shouldRerenderOnFileEvent(picked, lastAnswer, where)) {
        scheduleRender("the picked report's own file appeared or changed after a placement 404");
      }
    };
    pickWatchers = [watcher, watcher.onDidCreate(fire), watcher.onDidChange(fire)];
  } catch (err) {
    log(`preview: could not watch ${picked.fsPath}: ${err && err.message ? err.message : err}`);
  }
}

function disposeWatchers() {
  for (const d of pickWatchers) {
    try {
      if (d && typeof d.dispose === "function") d.dispose();
    } catch (err) {
      /* a watcher that will not close is not worth a failed teardown */
    }
  }
  pickWatchers = [];
}

function disposePreview() {
  if (coalesceTimer) {
    clearTimeout(coalesceTimer);
    coalesceTimer = undefined;
  }
  disposeWatchers();
}

function restorePick(context) {
  extContext = context;
  const state = context && context.workspaceState;
  const saved = state && typeof state.get === "function" ? state.get(PICK_KEY) : undefined;
  if (!saved || !saved.uri || !saved.binding) return;
  try {
    const uri = vscode.Uri.parse(saved.uri);
    picked = core.makePick(saved.uri, uri.fsPath, saved.binding, saved.module, rootsFor(uri));
    installWatcher();
    setPreviewStatus();
    log(`preview: remembered ${core.pickLabel(picked)}`);
  } catch (err) {
    log(`preview: could not restore the remembered pick: ${err && err.message ? err.message : err}`);
  }
}

function rememberPick() {
  const state = extContext && extContext.workspaceState;
  if (!state || typeof state.update !== "function" || !picked) return;
  state.update(PICK_KEY, { uri: picked.uri, binding: picked.binding, module: picked.module });
}

/**
 * Section 3.2: a (file, binding) PAIR, in two steps, with a free-text
 * fallback because the type filter is a candidate list and a binding that
 * is not a report is a 400 at render, not a thing to hide from the picker.
 * Both lists are built by `preview-core`.
 */
async function pickReport(context) {
  extContext = context || extContext;
  if (!client) {
    vscode.window.showErrorMessage("Ermine: the language server is not running.");
    return;
  }

  const relative = (uri) =>
    typeof vscode.workspace.asRelativePath === "function" ? vscode.workspace.asRelativePath(uri) : uri.fsPath;
  const found = (await vscode.workspace.findFiles("**/*.e")) || [];
  const byPath = new Map();
  for (const uri of found) byPath.set(uri.fsPath, uri);
  const active = vscode.window.activeTextEditor;
  const activeUri =
    active && active.document && active.document.uri && active.document.uri.scheme === "file"
      ? active.document.uri
      : undefined;
  if (activeUri) byPath.set(activeUri.fsPath, activeUri);

  const items = core.pickerItems(
    found.map((uri) => ({ fsPath: uri.fsPath, relative: relative(uri) })),
    activeUri ? { fsPath: activeUri.fsPath, relative: relative(activeUri) } : undefined
  );
  if (!items.length) {
    vscode.window.showWarningMessage("Ermine: no .e file found in the workspace.");
    return;
  }
  const file = await vscode.window.showQuickPick(items, {
    placeHolder: "Ermine: which file holds the report?",
    matchOnDescription: true,
  });
  if (!file) return;
  const fileUri = byPath.get(file.fsPath) || vscode.Uri.file(file.fsPath);

  let listed;
  try {
    listed = await client.sendRequest("ermine/preview/reports", core.reportsParams(fileUri.toString()));
  } catch (err) {
    listed = { error: err && err.message ? err.message : String(err) };
  }
  if (listed && listed.error) log(`preview: ermine/preview/reports: ${listed.error}`);
  const moduleName = listed && listed.module ? String(listed.module) : null;

  const chosen = await vscode.window.showQuickPick(
    core.bindingItems(listed && listed.reports, listed && listed.error),
    { placeHolder: `Ermine: which binding in ${file.label}?`, matchOnDescription: true }
  );
  if (!chosen) return;

  let binding = chosen.binding;
  if (!binding) {
    binding = await vscode.window.showInputBox({
      prompt: `Binding name in ${file.label}`,
      value: "report",
    });
    if (!binding || !binding.trim()) return;
    binding = binding.trim();
  }

  picked = core.makePick(fileUri.toString(), file.fsPath, binding, moduleName, rootsFor(fileUri));
  lastAnswer = undefined;
  rememberPick();
  installWatcher();
  setPreviewStatus();
  // The user asked for this one, so it reveals the tab.
  await renderNow("the report was picked", true);
}

async function renderCommand(context) {
  extContext = context || extContext;
  if (!picked) {
    // Picking renders, so "Render Report to JSON" with no pick is the
    // picker: one command, not an error message telling you to run another.
    await pickReport(context);
    return;
  }
  await renderNow("Ermine: Render Report to JSON", true);
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
    }),
    vscode.commands.registerCommand("ermine.previewReport", () => pickReport(context)),
    vscode.commands.registerCommand("ermine.renderReport", () => renderCommand(context))
    // NOT "ermine.reloadModules": the server advertises it in
    // executeCommandProvider, and vscode-languageclient registers every such
    // command as a VS Code command itself (ExecuteCommandFeature), forwarding
    // the palette's invocation as workspace/executeCommand.  A second
    // registerCommand here would throw inside client.start().  The status
    // line for it is the executeCommand middleware in clientOptions.
  );

  // Push settings ourselves rather than relying on the client's synchronize
  // machinery, so the payload shape matches what the server reads exactly.
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (!event.affectsConfiguration("ermine")) return;
      if (client) {
        try {
          const values = settingValues();
          reportSettingProblems(core.previewSettings(values).problems);
          await client.sendNotification(
            "workspace/didChangeConfiguration",
            core.didChangeConfigurationParams(values)
          );
        } catch (err) {
          log(`could not push settings: ${err}`);
        }
      }
      setStatus(`Ermine${fastModeSuffix()}`, "Ermine language server");
      // A roots change is a NEW ROOT SET, which is the render session's
      // discard key (section 2.4): re-resolve the pick's roots and re-render,
      // so the next `ermine/schema` cannot disagree with the last render.
      if (event.affectsConfiguration("ermine.preview.roots") && picked) {
        try {
          picked.roots = rootsFor(vscode.Uri.parse(picked.uri));
          scheduleRender("ermine.preview.roots changed");
        } catch (err) {
          log(`preview: could not re-resolve the roots: ${err && err.message ? err.message : err}`);
        }
      }
      // These three only take effect on a fresh process.
      if (
        event.affectsConfiguration("ermine.serverPath") ||
        event.affectsConfiguration("ermine.logFile") ||
        event.affectsConfiguration("ermine.maxHeap")
      ) {
        await restart(context);
      }
    })
  );

  restorePick(context);

  // Not awaited on purpose — activation must not wait on the server.
  startClient(context);
}

function deactivate() {
  disposePreview();
  return stopQuietly(client);
}

module.exports = { activate, deactivate };
