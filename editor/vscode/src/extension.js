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
// WHAT IS DECIDED WHERE (WP-7's re-review corrected an overstatement here:
// this used to say "EVERY DECISION IS IN src/preview-core.js"). The
// decisions that can be made from DATA ALONE live in src/preview-core.js
// and are unit-tested there -- which report a trigger names, whether a 404
// is a placement failure, what the status bar should say, how a pick is
// labelled, and (WP-22) the whole lifecycle of the wedge mark and the one
// consultation that reads it. What stays in this file is what needs the
// editor itself and therefore has no unit test: the coalescing window
// below, which file watchers are installed and when, the lazy status bar
// item, the untitled tab, and the restore-on-activate path.
//
// WP-22, THE WEDGE GUARD, in one paragraph. A render that wedges the
// preview ends with the server dead and restarted, and the transition back
// into `Running` asks for a re-render -- of the report that killed the last
// process. The extension therefore REMEMBERS ("I think 'remembering' is an
// extension concern" -- the user): one mark for the current pick, set when
// that pick wedges or dies mid-render, cleared by anything that says the
// inputs changed or that the job came back, and consulted at exactly one
// site -- `applyStuck`'s `rerender` effect for the `restart` trigger --
// where the automatic render is replaced by one non-modal question.
// NOTHING HERE HAS BEEN OBSERVED IN A REAL EDITOR BY ANYONE.

const PICK_KEY = "ermine.preview.pick";
// WP-22's wedge mark, mirrored beside the pick. The MODULE GLOBAL below is
// the authority for the live decision -- `Memento.update` is async and the
// loop it guards turns over in seconds -- and this key is the durable copy,
// read back in `restorePick` and discarded there if it is not that pick's.
const WEDGE_KEY = "ermine.preview.wedge";

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
/**
 * WP-22: ONE wedge mark, for the current pick, or null. Every transition
 * goes through `core.guardReduce`; this file only stores what it returns.
 */
let wedgeMark = null;
/**
 * GLUE, and the answer to "a second restart while held must not re-prompt
 * endlessly": VS Code stacks notifications, and a crash-restart loop would
 * stack one question per cycle. While a question is on screen the next
 * restart only logs. It NEVER loses the mark -- the mark is untouched by
 * this flag -- and the held status bar item says so the whole time.
 */
let heldPromptOpen = false;
/**
 * M1 (WP-22 review). THE IN-FLIGHT RENDER, AS A FACT THE ORDER CANNOT
 * TAKE AWAY: `{generation, pick}` while an `ermine/render` is out, or null.
 *
 * `renderInFlight` above is the SPINNER, and it is cleared by whatever
 * settles the promise -- including a transport rejection. That made
 * `died-mid-render` depend on whether the `Stopped` event reached the
 * handler before `renderNow`'s continuation ran, which is decided inside
 * `vscode-languageclient` and is unobservable from here. THIS latch is
 * cleared ONLY by a settled result (an answer, or a rejection a published
 * specification lets us read as the peer's own), so the `Stopped` handler
 * sees the in-flight render whichever way the race falls; and the
 * rejection path marks the wedge itself, so it is covered the other way
 * round too. `guardReduce`'s SET is idempotent per key, so both firing is
 * a no-op rather than a second mark.
 */
let inFlightRender = null;
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
 * LAZY on purpose: a second status bar item that says "no report picked"
 * before anyone has asked for a preview is noise.
 *
 * "NOT DURING ACTIVATION" IS NOT WHAT IT BUYS, and the earlier wording here
 * said otherwise (WP-7's re-review). `restorePick` runs from `activate` and
 * calls `setPreviewStatus`, so a workspace with a REMEMBERED PICK creates
 * this item during activation after all -- which is right, because there
 * really is something to show. test/load-test.js asserts exactly one status
 * bar item because it activates with NO saved pick; a fixture that saved one
 * would see two, and that would be correct rather than a regression.
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
    mark: wedgeMark,
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
    // WP-22: the server's own dependency closure is the exact "the report's
    // inputs changed" signal, so it clears the wedge mark (T3 is never
    // suppressed -- the notification IS the evidence).
    applyGuard(core.guardReduce(wedgeMark, { type: "invalidated", modules, pick: picked }));
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
    const event = {
      type: "notification",
      stuck: !!(params && params.stuck === true),
      message: params && params.message,
      seq: params && params.seq,
    };
    // THE TWO REDUCERS MUST ACCEPT THE SAME EVENTS (WP-22): rule (1)'s
    // answer is computed from the state BEFORE `stuckReduce` moves it, and
    // handed to the guard. A `{stuck:false}` the banner ignores must not
    // clear the mark either. The guard runs FIRST so that the consultation
    // and the status bar below already see the new mark.
    const applies = core.stuckEventApplies(stuckState, event);
    applyGuard(
      core.guardReduce(wedgeMark, {
        type: "notification",
        stuck: event.stuck,
        applies,
        // N2: the render that is IN FLIGHT is the better claim about what
        // wedged; the current pick is the fallback when nothing is running.
        pick: core.markPickFor(inFlightRender && inFlightRender.pick, picked),
        at: Date.now(),
      })
    );
    applyStuck(core.stuckReduce(stuckState, event), "recovered");
  });

  // Section 5's "Server stopped" row, and DD-2's `seq` reset. The library
  // passes through `Starting`, so "Stopped -> Running" is observed as any
  // transition INTO Running.
  if (typeof c.onDidChangeState === "function") {
    c.onDidChangeState((event) => {
      const to = CLIENT_STATE[event && event.newState];
      if (!to) return;
      if (to === "Stopped") {
        // WP-22: the server died while a render of the pick was in flight.
        // It may never have fired the watchdog -- at a small -Xmx the JVM
        // exits first (MEASURED, section 2.5: WpBlow at 256m, exit 3 at
        // 8.6 s, no fire). M1: `inFlightRender` -- unlike `renderInFlight`
        // -- is NOT cleared by the rejection that this same death causes,
        // so this branch does not depend on which of the two the library
        // delivers first, and `renderNow`'s catch marks it too.
        applyGuard(
          core.guardReduce(wedgeMark, {
            type: "clientState",
            to: "Stopped",
            renderInFlight: inFlightRender !== null,
            pick: core.markPickFor(inFlightRender && inFlightRender.pick, picked),
            at: Date.now(),
          })
        );
      }
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
        }),
        "restart"
      );
    });
  }
}

/**
 * WP-22's ONE CONSULTATION SITE, and everything else here is unchanged.
 *
 * `trigger` says which of the render triggers asked. Only `restart` -- the
 * `rerender` effect of the Stopped -> Running transition -- is ever
 * refused, and only for a mark that is THIS pick's. That single site also
 * covers the **Restart Language Server** button in the notification below:
 * it runs `ermine.restartServer` -> `restart(context)` -> a Stopped and
 * then a Running edge, which is the same path a crash takes. Before WP-22
 * the one remedy offered during a wedge re-issued the render that wedged.
 */
function applyStuck(result, trigger) {
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
  if (fx.rerender) {
    if (core.shouldAutoRender(wedgeMark, picked, trigger)) {
      scheduleRender(trigger === core.TRIGGER_RESTART ? "the language server restarted" : "the preview recovered");
    } else {
      holdRender();
    }
  }
  setPreviewStatus();
}

/**
 * The automatic render was NOT issued. Ask once, non-modally, and leave the
 * mark alone unless the answer is the one word that consents.
 *
 * DISMISSAL IS "Not now": `showWarningMessage` resolves with `undefined`
 * when the notification is dismissed or times out, and only the exact
 * "Render anyway" string clears the mark. Escape is never consent.
 */
function holdRender() {
  const message = core.heldMessage(wedgeMark, picked);
  if (!message) return;              // a mark that is not this pick's is never consulted
  log("preview: HELD — " + message);
  if (heldPromptOpen) {
    log("preview: the question is already on screen; not asking again");
    return;
  }
  heldPromptOpen = true;
  // M2 (WP-22 review): the question has no deadline. Remember WHICH report
  // it is about, because the user may answer it after picking another one,
  // and consent given for one report must not be spent on another.
  const asked = core.markKey(picked);
  const done = (choice) => {
    heldPromptOpen = false;
    const verdict = core.promptAnswerApplies(asked, picked, wedgeMark, choice);
    if (!verdict.render) {
      log(`preview: still held (${verdict.why})`);
      return;
    }
    if (verdict.why) log(`preview: rendering anyway (${verdict.why})`);
    applyGuard(core.guardReduce(wedgeMark, { type: "render", explicit: true }));
    renderNow("Render anyway", true).catch((err) =>
      log(`preview: render failed: ${err && err.stack ? err.stack : err}`)
    );
  };
  vscode.window
    .showWarningMessage(message, "Render anyway", "Not now")
    .then(done, (err) => {
      heldPromptOpen = false;
      log(`preview: could not ask about the held render: ${err && err.message ? err.message : err}`);
    });
}

/**
 * The mark's only writer. `guardReduce` decides; this stores, says so once
 * in the channel, and mirrors into `workspaceState` -- never waiting on
 * that write, which is a `Thenable` and would race the loop it guards.
 */
function applyGuard(result) {
  const before = wedgeMark;
  wedgeMark = result.mark;
  const fx = result.effects;
  // N4: a restore is not a fresh incident and must not read like one.
  if (fx.restored) log(`preview: a wedge mark was restored from the last session (${fx.reason})`);
  else if (fx.set) log(`preview: remembering that ${fx.label || core.pickLabel(picked)} wedged the preview (${fx.reason})`);
  if (fx.cleared) log(`preview: the wedge mark is cleared (${fx.why})`);
  // N3: a DISCARD at restore leaves both sides null, and the stale entry
  // has to go from the store as well or it is re-discarded for ever.
  if (before === wedgeMark && !fx.cleared) return;
  rememberWedge();
  setPreviewStatus();
}

function rememberWedge() {
  const state = extContext && extContext.workspaceState;
  if (!state || typeof state.update !== "function") return;
  try {
    // `undefined` REMOVES the key (Memento's documented behaviour, external).
    const written = state.update(WEDGE_KEY, wedgeMark || undefined);
    // `Memento.update` answers a Thenable, and an unhandled rejection from
    // it would be silent; the decision never waits on it (that is the whole
    // reason the module global is the authority), but a failure is said.
    if (written && typeof written.then === "function") {
      written.then(undefined, (err) =>
        log(`preview: could not remember the wedge mark: ${err && err.message ? err.message : err}`)
      );
    }
  } catch (err) {
    log(`preview: could not remember the wedge mark: ${err && err.message ? err.message : err}`);
  }
}

/**
 * M1: the latch is released by THIS render's own settled result, and only
 * by that one -- `renderNow` is re-entrant, so a slower render's
 * continuation must not release a newer render's latch.
 */
function releaseInFlight(generationOfThisRender) {
  if (inFlightRender && inFlightRender.generation === generationOfThisRender) inFlightRender = null;
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
  // N2: the pick this request is ABOUT, captured at send. A stuck answer
  // that arrives a minute later must not mark whatever is current then.
  const sentPick = picked;
  // M1: the latch the `Stopped` handler reads, cleared only on a settled
  // result below.
  inFlightRender = { generation: mine, pick: sentPick };
  renderInFlight = true;
  setPreviewStatus();
  log(`preview: render ${core.pickLabel(picked)} (generation ${mine}; ${reason})`);

  let answer;
  try {
    answer = await client.sendRequest("ermine/render", core.renderParams(picked, null, mine));
    releaseInFlight(mine);
  } catch (err) {
    // M1, and the half of it that does not depend on the ordering at all:
    // a rejection we cannot read as the PEER's own answer means the server
    // went away under this render, which is a wedge whether or not the
    // watchdog ever fired. `core.rejectionMeansServerGone` is where that is
    // decided, with its evidence; SET is idempotent, so the `Stopped`
    // handler doing the same thing first or second costs nothing.
    if (core.rejectionMeansServerGone(err)) {
      log(`preview: render ${mine} was lost with the connection (${err && err.message ? err.message : err})`);
      applyGuard(
        core.guardReduce(wedgeMark, {
          type: "clientState",
          to: "Stopped",
          renderInFlight: true,
          pick: sentPick,
          at: Date.now(),
        })
      );
    }
    releaseInFlight(mine);
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
  const stuckEvent = {
    type: "answer",
    stuck: !!(answer && answer.stuck === true),
    message: answer && answer.message,
    seqAtSend: sentAtMark,
  };
  // WP-22, and the same acceptance test the banner uses: a stuck refusal
  // decided BEFORE a clear raises no banner and marks nothing.
  applyGuard(
    core.guardReduce(wedgeMark, {
      type: "answer",
      stuck: stuckEvent.stuck,
      applies: core.stuckEventApplies(stuckState, stuckEvent),
      // N2: the pick this ANSWER is about, not whatever is current now.
      pick: sentPick,
      at: Date.now(),
    })
  );
  applyStuck(core.stuckReduce(stuckState, stuckEvent), "answer");
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
      // N1 (WP-22 review): the picked report's OWN file was created or
      // changed. That is the same evidence a save is -- and the watcher
      // fires exactly where `invalidated` cannot, because the module never
      // loaded -- so it clears the mark through the same rule, whether or
      // not it goes on to render.
      applyGuard(core.guardReduce(wedgeMark, { type: "save", path: where }));
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
  // N5: nothing is on screen after a teardown, so nothing is outstanding.
  // A notification LEFT UNANSWERED in the notification centre otherwise
  // keeps this true for the life of the window and no further restart
  // would ask -- which fails safe (nothing renders, and the status bar
  // still reads `held`) but leaves the user with no question to answer.
  heldPromptOpen = false;
  inFlightRender = null;
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
    // WP-22: the mark is restored NEXT TO THE PICK IT BELONGS TO, and
    // `guardReduce` discards it if its key or its roots do not match what
    // was just restored. `restorePick` renders nothing, so a restored mark
    // costs no question until the next restart.
    applyGuard(
      core.guardReduce(null, {
        type: "restore",
        mark: state && typeof state.get === "function" ? state.get(WEDGE_KEY) : undefined,
        pick: picked,
      })
    );
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
  // WP-22: a pick change clears the mark -- it was the OTHER report that
  // wedged -- and picking renders, which is consent in any case.
  applyGuard(core.guardReduce(wedgeMark, { type: "pick", pick: picked }));
  // N5: a question about the OLD pick is now meaningless. M2 makes
  // answering it a no-op; this makes the NEXT restart able to ask again.
  heldPromptOpen = false;
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
  // WP-22: asking for a render IS the confirmation (T2).
  applyGuard(core.guardReduce(wedgeMark, { type: "render", explicit: true }));
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
          // WP-22: a different root set is a different render, so the mark
          // no longer describes what would run (T5 is never suppressed).
          applyGuard(core.guardReduce(wedgeMark, { type: "roots", pick: picked }));
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

  // WP-22's fallback clear, and the one `ermine/preview/invalidated` cannot
  // give: while the server is DEAD nothing sends `didChangeWatchedFiles`,
  // so no notification can cover the window in which the developer fixes
  // the loop. Deliberately imprecise -- any `.e` save clears the mark --
  // because it errs towards asking LESS.
  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument((document) => {
      if (!wedgeMark) return;
      applyGuard(
        core.guardReduce(wedgeMark, {
          type: "save",
          path: document && (document.fileName || (document.uri && document.uri.fsPath)),
        })
      );
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
